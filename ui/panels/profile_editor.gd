class_name ProfileEditor
extends Window
## Make a fixture profile without touching a .tres file: type (or paste) the
## channel chart from the fixture's manual, or import the fixture from the
## Open Fixture Library or a GDTF file, then Save. Saved profiles land in the
## Fixtures library under "My fixtures".
##
## The chart is kept as `_rows` (plain Dictionaries) and turned into a
## FixtureProfile by _build_profile(). The layout lives in profile_editor.tscn.

signal saved(profile: FixtureProfile)

const ROW_SCENE := preload("res://ui/panels/profile_channel_row.tscn")
const MAX_CHANNELS := 512
const OFL_HOST := "open-fixture-library.org"

## {"kind": "channel", "name": String, "default": int}
## or {"kind": "pixels", "per": PackedStringArray, "count": int}
var _rows: Array[Dictionary] = []
var _layout := Vector2i.ZERO ## pixel columns x rows
var _pan_range := 540.0
var _tilt_range := 270.0
var _source_path := "" ## file being edited, "" for a new profile
var _imports: Array[FixtureProfile] = []
var _row_nodes: Array[ProfileChannelRow] = []

@onready var _name: LineEdit = %NameEdit
@onready var _body: OptionButton = %BodyType
@onready var _rows_box: VBoxContainer = %Rows
@onready var _scroll: ScrollContainer = %Scroll
@onready var _chips: HFlowContainer = %Chips
@onready var _status: Label = %Status
@onready var _save: Button = %Save
@onready var _mode_row: HBoxContainer = %ModeRow
@onready var _modes: OptionButton = %Modes
@onready var _url_row: HBoxContainer = %UrlRow
@onready var _url: LineEdit = %UrlEdit
@onready var _paste_box: VBoxContainer = %PasteBox
@onready var _paste_text: TextEdit = %PasteText
@onready var _pixel_box: HBoxContainer = %PixelBox
@onready var _mover_box: HBoxContainer = %MoverBox
@onready var _http: HTTPRequest = %Http


func _ready() -> void:
	close_requested.connect(hide)
	%Cancel.pressed.connect(hide)
	_save.pressed.connect(_on_save)
	for style in ["Par", "Moving head", "Bar", "Strobe"]:
		_body.add_item(style)
	_body.item_selected.connect(func(_i: int) -> void: _refresh())
	_name.text_changed.connect(func(_t: String) -> void: _refresh())
	for n in ProfileImport.STANDARD:
		var b := Button.new()
		b.text = n
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"PillButton"
		b.pressed.connect(_add_channel.bind(n))
		_chips.add_child(b)
	%AddOther.pressed.connect(_add_channel.bind(""))
	%PanRange.value_changed.connect(func(v: float) -> void: _pan_range = v)
	%TiltRange.value_changed.connect(func(v: float) -> void: _tilt_range = v)

	# Typing the chart from a pasted list.
	%PasteButton.pressed.connect(func() -> void: _paste_box.visible = not _paste_box.visible)
	%PasteApply.pressed.connect(_on_paste_apply)
	# Pixel bars.
	%PixelButton.pressed.connect(func() -> void: _pixel_box.visible = not _pixel_box.visible)
	%PixelApply.pressed.connect(_on_pixel_apply)
	# Importing.
	%ImportFile.pressed.connect(%FileDialog.popup_centered_ratio.bind(0.6))
	(%FileDialog as FileDialog).file_selected.connect(_on_file_selected)
	%ImportUrl.pressed.connect(func() -> void:
		_url_row.visible = not _url_row.visible
		if _url_row.visible:
			_url.grab_focus())
	%UrlGo.pressed.connect(_on_fetch)
	_url.text_submitted.connect(func(_t: String) -> void: _on_fetch())
	_http.request_completed.connect(_on_fetched)
	_modes.item_selected.connect(func(i: int) -> void: _load_profile(_imports[i]))


## Opens an empty editor.
func open_new() -> void:
	_load_profile(null)
	_show()


## Opens the editor on a saved profile; Save writes it back to the same file.
func open_edit(profile: FixtureProfile) -> void:
	_load_profile(profile)
	_show()


func _show() -> void:
	_url_row.visible = false
	_paste_box.visible = false
	_pixel_box.visible = false
	_mode_row.visible = false
	_imports.clear()
	popup_centered()
	_name.grab_focus()


# --- Loading and building -----------------------------------------------------

## Fills the editor from `profile` (null = blank). Keeps the file being edited
## unless it's an imported mode.
func _load_profile(profile: FixtureProfile) -> void:
	_rows.clear()
	_layout = Vector2i.ZERO
	if profile == null:
		_source_path = ""
		_name.text = ""
		_body.select(0)
		_pan_range = 540.0
		_tilt_range = 270.0
	else:
		if _imports.has(profile):
			_source_path = ""
		else:
			_source_path = profile.resource_path
		_name.text = profile.fixture_name
		_body.select(clampi(profile.body_style, 0, _body.item_count - 1))
		_pan_range = profile.pan_range_deg
		_tilt_range = profile.tilt_range_deg
		_layout = profile.pixel_layout
		_rows_from_channels(profile)
	%PanRange.set_value_no_signal(_pan_range)
	%TiltRange.set_value_no_signal(_tilt_range)
	_rebuild_rows()


## Turns a profile's channel list into rows, folding a regular pixel run into
## one row.
func _rows_from_channels(profile: FixtureProfile) -> void:
	var chans := profile.channels
	var first := -1
	for i in chans.size():
		if profile.channel_pixel(i) >= 0:
			first = i
			break
	var folded := false
	if first >= 0:
		var per := PackedStringArray()
		var n := profile.pixel_count()
		for i in range(first, chans.size()):
			if profile.channel_pixel(i) == 0:
				per.append(profile.channel_base(i))
		var run := FixtureProfile.pixel_channels(per, n)
		var last := first + run.size()
		if per.size() > 0 and last <= chans.size() and chans.slice(first, last) == run:
			for i in first:
				_rows.append(_channel_row(chans[i], profile))
			_rows.append({"kind": "pixels", "per": per, "count": n})
			for i in range(last, chans.size()):
				_rows.append(_channel_row(chans[i], profile))
			folded = true
	if not folded:
		for c in chans:
			_rows.append(_channel_row(c, profile))


func _channel_row(channel_name: String, profile: FixtureProfile) -> Dictionary:
	return {"kind": "channel", "name": channel_name, "default": int(profile.defaults.get(channel_name, 0))}


## The profile the editor currently describes.
func _build_profile() -> FixtureProfile:
	var p := FixtureProfile.new()
	p.fixture_name = _name.text.strip_edges()
	p.body_style = _body.selected
	p.channels = _expanded_channels()
	var defaults: Dictionary = {}
	for r in _rows:
		if r["kind"] == "channel":
			var n := str(r["name"]).strip_edges()
			if int(r["default"]) > 0 and not ProfileImport.STANDARD.has(n):
				defaults[n] = int(r["default"])
	p.defaults = defaults
	p.pan_range_deg = _pan_range
	p.tilt_range_deg = _tilt_range
	if p.pixel_count() > 0:
		p.pixel_layout = _layout
	return p


func _expanded_channels() -> PackedStringArray:
	var out := PackedStringArray()
	for r in _rows:
		if r["kind"] == "pixels":
			out.append_array(FixtureProfile.pixel_channels(r["per"], int(r["count"])))
		else:
			out.append(str(r["name"]).strip_edges())
	return out


# --- Rows ---------------------------------------------------------------------

func _add_channel(channel_name: String) -> void:
	_rows.append({"kind": "channel", "name": channel_name, "default": 0})
	_rebuild_rows()
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	if channel_name.is_empty() and not _row_nodes.is_empty():
		_row_nodes[-1].focus_name()


func _rebuild_rows() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_row_nodes.clear()
	for i in _rows.size():
		var node := ROW_SCENE.instantiate() as ProfileChannelRow
		_rows_box.add_child(node)
		var r := _rows[i]
		if r["kind"] == "pixels":
			var per: PackedStringArray = r["per"]
			node.show_pixels("%d pixels × (%s)" % [int(r["count"]), ", ".join(per)])
		else:
			node.show_channel(str(r["name"]), int(r["default"]))
			node.name_changed.connect(func(t: String) -> void:
				r["name"] = t
				_refresh())
			node.default_changed.connect(func(v: int) -> void: r["default"] = v)
		node.move_requested.connect(_move_row.bind(i))
		node.delete_requested.connect(func() -> void:
			_rows.remove_at(i)
			_rebuild_rows())
		_row_nodes.append(node)
	_refresh()


func _move_row(direction: int, index: int) -> void:
	var to := index + direction
	if to < 0 or to >= _rows.size():
		return
	var r := _rows[index]
	_rows.remove_at(index)
	_rows.insert(to, r)
	_rebuild_rows()


## Addresses on each row, the status line and whether Save is allowed.
func _refresh() -> void:
	if _row_nodes.size() != _rows.size():
		return
	var at := 1
	for i in _rows.size():
		var width := 1
		if _rows[i]["kind"] == "pixels":
			width = (_rows[i]["per"] as PackedStringArray).size() * int(_rows[i]["count"])
		_row_nodes[i].set_address_text(str(at) if width == 1 else "%d–%d" % [at, at + width - 1])
		at += width
	_mover_box.visible = _body.selected == 1
	var report := validate(_name.text, _expanded_channels())
	for i in _row_nodes.size():
		var bad := false
		if _rows[i]["kind"] == "channel":
			var n := str(_rows[i]["name"]).strip_edges()
			bad = n.is_empty() or (report.dupes as Dictionary).has(n)
		_row_nodes[i].set_problem(bad)
	var errors: PackedStringArray = report.errors
	var warnings: PackedStringArray = report.warnings
	_save.disabled = not errors.is_empty()
	if not errors.is_empty():
		_status.text = errors[0]
		_status.modulate = UIPalette.LIVE
	elif not warnings.is_empty():
		_status.text = warnings[0]
		_status.modulate = UIPalette.ACCENT
	else:
		var p := _build_profile()
		_status.text = "%d channels: %s" % [p.channels.size(), p.summary()]
		_status.modulate = UIPalette.TEXT_DIM


## What's wrong with a name + channel list. Errors block saving; warnings don't.
## Returns {"errors", "warnings": PackedStringArray, "dupes": Dictionary}.
static func validate(profile_name: String, channels: PackedStringArray) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var dupes: Dictionary = {}
	var seen: Dictionary = {}
	for i in channels.size():
		var c := channels[i]
		if c.is_empty():
			errors.append("Channel %d needs a name." % (i + 1))
		elif seen.has(c):
			dupes[c] = true
		seen[c] = true
	if channels.is_empty():
		errors.append("Add the channels in the order the manual lists them.")
	if channels.size() > MAX_CHANNELS:
		errors.append("A universe only has %d channels." % MAX_CHANNELS)
	if profile_name.strip_edges().is_empty():
		errors.append("Give the fixture a name.")
	if not dupes.is_empty():
		warnings.append("Two channels are called \"%s\"; only the first one will be driven." % str(dupes.keys()[0]))
	return {"errors": errors, "warnings": warnings, "dupes": dupes}


# --- Paste and pixels -----------------------------------------------------------

func _on_paste_apply() -> void:
	var names := ProfileImport.from_text(_paste_text.text)
	if names.is_empty():
		_status.text = "Couldn't find any channels in that text."
		_status.modulate = UIPalette.LIVE
		return
	_rows.clear()
	_layout = Vector2i.ZERO
	for n in names:
		_rows.append({"kind": "channel", "name": n, "default": 0})
	_paste_text.text = ""
	_paste_box.visible = false
	_rebuild_rows()


func _on_pixel_apply() -> void:
	var per := PackedStringArray()
	for part in (%PixelChannels as LineEdit).text.split(",", false):
		var n := ProfileImport.normalize_name(part)
		if not n.is_empty():
			per.append(n)
	var count := int((%PixelCount as SpinBox).value)
	if per.is_empty():
		_status.text = "List what each pixel has, e.g. red, green, blue."
		_status.modulate = UIPalette.LIVE
		return
	for r in _rows:
		if r["kind"] == "pixels":
			_status.text = "This fixture already has a pixel run."
			_status.modulate = UIPalette.LIVE
			return
	_rows.append({"kind": "pixels", "per": per, "count": count})
	_layout = Vector2i(int((%PixelCols as SpinBox).value), int((%PixelRows as SpinBox).value))
	_pixel_box.visible = false
	_rebuild_rows()


# --- Importing ----------------------------------------------------------------

func _on_file_selected(path: String) -> void:
	if path.get_extension().to_lower() == "gdtf":
		_show_import(ProfileImport.from_gdtf(path))
	else:
		_show_import(ProfileImport.from_ofl(FileAccess.get_file_as_string(path)))


func _on_fetch() -> void:
	var url := ofl_json_url(_url.text)
	if url.is_empty():
		_status.text = "Paste the fixture's page address from open-fixture-library.org."
		_status.modulate = UIPalette.LIVE
		return
	_status.text = "Fetching…"
	_status.modulate = UIPalette.TEXT_DIM
	if _http.request(url) != OK:
		_status.text = "Couldn't start the download."
		_status.modulate = UIPalette.LIVE


func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_status.text = "Couldn't download that fixture (%s). Check the address, or download the .json and use Import file."\
				% ("not found" if code == 404 else "error %d" % maxi(code, result))
		_status.modulate = UIPalette.LIVE
		return
	_url_row.visible = false
	_show_import(ProfileImport.from_ofl(body.get_string_from_utf8()))


## "https://open-fixture-library.org/cameo/flat-pro-12" -> ".../flat-pro-12.json".
## "" if it isn't an Open Fixture Library address.
static func ofl_json_url(text: String) -> String:
	var url := text.strip_edges()
	if not url.begins_with("http"):
		url = "https://" + url
	var host := url.get_slice("/", 2)
	if not (host == OFL_HOST or host == "www." + OFL_HOST):
		return ""
	url = url.get_slice("?", 0).get_slice("#", 0).trim_suffix("/")
	if url.get_slice("/", 3).is_empty() or url.get_slice("/", 4).is_empty():
		return ""
	return url if url.ends_with(".json") else url + ".json"


func _show_import(result: Dictionary) -> void:
	var profiles: Array[FixtureProfile] = []
	profiles.assign(result["profiles"])
	var notes: PackedStringArray = result["notes"]
	if profiles.is_empty():
		_status.text = notes[0] if not notes.is_empty() else "Nothing to import in that file."
		_status.modulate = UIPalette.LIVE
		return
	_imports = profiles
	_modes.clear()
	for p in profiles:
		_modes.add_item(p.fixture_name)
	_mode_row.visible = profiles.size() > 1
	_load_profile(profiles[0])
	if not notes.is_empty():
		_status.text = notes[0]
		_status.modulate = UIPalette.ACCENT


# --- Saving -------------------------------------------------------------------

func _on_save() -> void:
	var p := _build_profile()
	var path := ProfileStore.save(p, _source_path)
	if path.is_empty():
		_status.text = "Couldn't save the profile."
		_status.modulate = UIPalette.LIVE
		return
	hide()
	saved.emit(p)
