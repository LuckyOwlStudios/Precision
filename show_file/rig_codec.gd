class_name RigCodec
extends RefCounted
## The rig section of a show file: every fixture with its profile, patch,
## position, look and mirror link. (The truss it hangs from is the separate
## "structure" section, see StructureCodec.)
##
## Layout:
##   { "profiles": [ {name, channels, pixel_layout, defaults, pan_range_deg, tilt_range_deg}, ... ],
##     "fixtures": [ {name, label?, profile, address, body, profile_label, position, basis,
##                    look: {dimmer, color, ...}, mirror?: {partner, flip}}, ... ] }
## Fixtures keep their node name ("Par 3") because looks, cues and song shows
## find fixtures by that path.


static func save(ctx: StudioContext) -> Dictionary:
	var profiles: Array = []
	var profile_ids: Dictionary = {} ## encoded profile (JSON text) -> index, so shared profiles are stored once
	var fixtures: Array = []
	var list := ctx.fixtures()
	for fx in list:
		var pd := _profile_data(fx.profile)
		var key := JSON.stringify(ShowCodec.encode(pd))
		if not profile_ids.has(key):
			profile_ids[key] = profiles.size()
			profiles.append(pd)
		var entry := {
			"name": String(fx.name),
			"profile": profile_ids[key],
			"address": fx.start_address,
			"body": FixtureCatalog.Body.keys()[int(fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR))],
			"profile_label": String(fx.get_meta(StudioContext.META_PROFILE_LABEL, "")),
			"position": StudioContext.fixture_transform(fx).origin,
			"basis": StudioContext.fixture_transform(fx).basis,
			"look": fx.capture(),
		}
		if fx.has_meta(StudioContext.META_LABEL):
			entry["label"] = String(fx.get_meta(StudioContext.META_LABEL))
		var twin := StageSymmetry.partner_of(fx)
		if twin != null and list.has(twin):
			entry["mirror"] = {"partner": list.find(twin), "flip": int(fx.get_meta(StageSymmetry.META_FLIP, -1))}
		fixtures.append(entry)
	return {"profiles": profiles, "fixtures": fixtures}


## Take every fixture off the rig.
static func clear(ctx: StudioContext) -> void:
	var gone := ctx.fixtures()
	for fx in gone:
		ctx.rig.remove_child(fx)
	ctx.fixtures_changed.emit() # the stage drops their 3D bodies
	for fx in gone:
		fx.free()


static func load_data(ctx: StudioContext, data: Variant) -> void:
	clear(ctx)
	if not data is Dictionary:
		return
	var profiles: Array[FixtureProfile] = []
	for pd: Variant in (data as Dictionary).get("profiles", []):
		profiles.append(_profile_from(pd as Dictionary))
	var made: Array[DMXFixture] = []
	var entries: Array = (data as Dictionary).get("fixtures", [])
	for e: Variant in entries:
		var entry: Dictionary = e
		var pi := int(entry.get("profile", -1))
		if pi < 0 or pi >= profiles.size():
			push_warning("Show file: fixture '%s' has no profile, skipped" % entry.get("name", "?"))
			made.append(null)
			continue
		var fx := DMXFixture.new()
		fx.name = str(entry.get("name", "Fixture"))
		fx.profile = profiles[pi]
		fx.universe = ctx.universe
		fx.start_address = clampi(int(entry.get("address", 1)), 1, 512)
		var look: Dictionary = entry.get("look", {})
		for prop: String in DMXFixture.LOOK_PROPERTIES:
			if look.has(prop):
				ShowCodec.apply(fx, prop, look[prop])
		var body_name := str(entry.get("body", "PAR"))
		fx.set_meta(StudioContext.META_BODY, FixtureCatalog.Body.get(body_name, FixtureCatalog.Body.PAR))
		fx.set_meta(StudioContext.META_PROFILE_LABEL, str(entry.get("profile_label", fx.profile.fixture_name)))
		fx.set_meta(StudioContext.META_POSITION, ShowCodec.decode(entry.get("position", Vector3.ZERO)))
		fx.set_meta(StudioContext.META_BASIS, ShowCodec.decode(entry.get("basis", Basis.IDENTITY)))
		if entry.has("label"):
			fx.set_meta(StudioContext.META_LABEL, str(entry["label"]))
		ctx.rig.add_child(fx)
		made.append(fx)
	for i in made.size():
		var m: Variant = (entries[i] as Dictionary).get("mirror")
		if made[i] == null or not m is Dictionary:
			continue
		var other := int((m as Dictionary).get("partner", -1))
		if other > i and other < made.size() and made[other] != null:
			StageSymmetry.link(made[i], made[other], int((m as Dictionary).get("flip", -1)))
	ctx.rebuild_name_counters()
	ctx.fixtures_changed.emit()


static func _profile_data(p: FixtureProfile) -> Dictionary:
	return {
		"name": p.fixture_name,
		"channels": p.channels,
		"pixel_layout": [p.pixel_layout.x, p.pixel_layout.y],
		"defaults": p.defaults,
		"pan_range_deg": p.pan_range_deg,
		"tilt_range_deg": p.tilt_range_deg,
	}


static func _profile_from(d: Dictionary) -> FixtureProfile:
	var p := FixtureProfile.new()
	p.fixture_name = str(d.get("name", "Fixture"))
	p.channels = PackedStringArray(ShowCodec.decode(d.get("channels", [])))
	var layout: Array = d.get("pixel_layout", [0, 0])
	p.pixel_layout = Vector2i(int(layout[0]), int(layout[1]))
	var defaults := {}
	for k: Variant in (d.get("defaults", {}) as Dictionary):
		defaults[str(k)] = int(d["defaults"][k])
	p.defaults = defaults
	p.pan_range_deg = float(d.get("pan_range_deg", 540.0))
	p.tilt_range_deg = float(d.get("tilt_range_deg", 270.0))
	return p
