class_name EffectPresetLibrary
extends Node
## The Effects shelf: built-in presets plus the ones you save. Your presets are
## saved one file each in <library>/effects/, straight after every change.

signal presets_changed

## Override for tests.
@export var root_dir: String = "user://library"

var presets: Array[EffectPreset] = [] ## built-ins first, then yours by save order

var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func presets_dir() -> String:
	return root_dir.path_join("effects")


func _ensure_loaded() -> void:
	if not _loaded:
		load_presets()


static func built_ins() -> Array[EffectPreset]:
	var list: Array[EffectPreset] = [
		EffectPreset.make("Circle", "circle"),
		EffectPreset.make("Wide slow circle", "circle", {"size": 50.0, "beats": 8.0}),
		EffectPreset.make("Circle fan", "circle", {"spread": 1.0}),
		EffectPreset.make("Crowd sweep", "sweep", {"width": 90.0, "beats": 8.0}),
		EffectPreset.make("Tilt nod", "sweep", {"axis": 1, "width": 40.0, "beats": 2.0}),
		EffectPreset.make("Strobe 1/8", "strobe", {"rate": 2.0}, 8.0),
		EffectPreset.make("Strobe fast", "strobe", {"rate": 4.0, "duty": 0.2}, 4.0),
		EffectPreset.make("Beat pulse", "pulse"),
		EffectPreset.make("Half-time pulse", "pulse", {"beats": 2.0}),
		EffectPreset.make("Chase", "chase"),
		EffectPreset.make("Bounce chase", "chase", {"bounce": true, "beats": 0.5}),
		EffectPreset.make("Rainbow", "rainbow"),
		EffectPreset.make("Red", "color", {"color": Color("ff2a3d")}, 8.0),
		EffectPreset.make("Blue", "color", {"color": Color("2a6bff")}, 8.0),
		EffectPreset.make("Blackout", "dimmer", {"level": 0.0}, 4.0),
	]
	for i in list.size():
		list[i].id = "builtin_%02d" % i
		list[i].built_in = true
	return list


func load_presets() -> void:
	_loaded = true
	presets = built_ins()
	var mine: Array[EffectPreset] = []
	var dir := DirAccess.open(presets_dir())
	if dir:
		for file in dir.get_files():
			if file.get_extension() == "tres":
				var p := ResourceLoader.load(presets_dir().path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as EffectPreset
				if p:
					mine.append(p)
	mine.sort_custom(func(a: EffectPreset, b: EffectPreset) -> bool: return a.id < b.id)
	presets.append_array(mine)
	presets_changed.emit()


func find(preset_id: String) -> EffectPreset:
	_ensure_loaded()
	for p in presets:
		if p.id == preset_id:
			return p
	return null


func is_name_taken(p_name: String, except: EffectPreset = null) -> bool:
	_ensure_loaded()
	var key := p_name.strip_edges().to_lower()
	for p in presets:
		if p != except and p.preset_name.strip_edges().to_lower() == key:
			return true
	return false


## "Circle 2" style name nobody uses yet.
func unique_name(base: String) -> String:
	if not is_name_taken(base):
		return base
	var n := 2
	while is_name_taken("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func add(p: EffectPreset) -> void:
	_ensure_loaded()
	if p.id.is_empty():
		p.id = "%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	if not presets.has(p):
		presets.append(p)
	save(p)
	presets_changed.emit()


func remove(p: EffectPreset) -> void:
	if p.built_in:
		return
	presets.erase(p)
	var path := _path(p)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	presets_changed.emit()


func rename(p: EffectPreset, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if p.built_in or new_name.is_empty() or is_name_taken(new_name, p):
		return
	p.preset_name = new_name
	save(p)
	presets_changed.emit()


func save(p: EffectPreset) -> void:
	if p.built_in:
		return
	DirAccess.make_dir_recursive_absolute(presets_dir())
	var err := ResourceSaver.save(p, _path(p))
	if err != OK:
		push_warning("EffectPresetLibrary: could not save '%s' (error %d)" % [p.preset_name, err])


func _path(p: EffectPreset) -> String:
	return presets_dir().path_join(p.id + ".tres")
