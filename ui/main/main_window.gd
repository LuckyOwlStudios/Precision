extends Control
## Main editor window. The layout lives in main_window.tscn so it can be
## rearranged in the Godot editor; this script only wires panels to the
## shared StudioContext and handles workspaces and global shortcuts.
##
## Drag audio files onto the window to import them into the song library.
##
## Shortcuts: Space = play/pause, Esc = blackout, Delete = remove selected fixture,
## F2 = rename selected fixture, W/E = move/rotate gizmo (stage view),
## Ctrl+Z = undo, Ctrl+R = redo (Ctrl+Shift+Z and Ctrl+Y redo too; Cmd on a Mac),
## 1/2/3 = Stage/Program/Live workspace. None of these fire while you're typing
## in a text field: there Ctrl+Z undoes your typing instead.

@onready var ctx: StudioContext = %Studio
@onready var workspace_tabs: TabBar = %WorkspaceTabs
@onready var left_dock: Control = %LeftDock
@onready var left_tabs: TabContainer = %LeftTabs
@onready var right_tabs: TabContainer = %RightTabs
@onready var timeline: Control = %Timeline
@onready var stage: StageView = %StageView
@onready var output_label: Label = %OutputLabel
@onready var output_dot: Panel = %OutputDot
@onready var rig_label: Label = %RigLabel


func _ready() -> void:
	for panel: Node in [%NowPlaying, stage, timeline, %Library, %OnStage, %Songs, %Inspector, %Cues, %DMX, %DJ]:
		panel.call("setup", ctx)

	_title_tabs(left_tabs, ["Library", "Songs"])
	_title_tabs(right_tabs, ["Inspector", "Cues", "DMX", "DJ"])

	workspace_tabs.current_tab = ctx.workspace
	workspace_tabs.tab_changed.connect(func(i: int) -> void: ctx.set_workspace(i as StudioContext.Workspace))
	ctx.workspace_changed.connect(_apply_workspace)
	ctx.fixtures_changed.connect(_update_footers)
	ctx.blackout_changed.connect(func(_on: bool) -> void: _update_footers())
	# Renaming happens in the inspector's Name field, so bring it to the front
	# (that field lives in Stage and Program; from Live, go to Stage).
	ctx.rename_requested.connect(func(_fx: DMXFixture) -> void:
		if ctx.workspace == StudioContext.Workspace.LIVE:
			ctx.set_workspace(StudioContext.Workspace.STAGE)
		right_tabs.current_tab = right_tabs.get_tab_idx_from_control(%Inspector))
	_apply_workspace(ctx.workspace)
	# First launch: Stage with the fixture Library in front of the left dock.
	left_tabs.current_tab = left_tabs.get_tab_idx_from_control(%Library)
	_update_footers()

	# Audio files dropped anywhere on the window go into the song library.
	get_window().files_dropped.connect(_on_files_dropped)


func _on_files_dropped(files: PackedStringArray) -> void:
	ctx.import_songs(files)
	# Songs live in Program, so go there to see what came in.
	if ctx.workspace != StudioContext.Workspace.PROGRAM:
		ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	left_tabs.current_tab = left_tabs.get_tab_idx_from_control(%Songs)


func _title_tabs(tabs: TabContainer, titles: Array[String]) -> void:
	for i in titles.size():
		tabs.set_tab_title(i, titles[i].to_upper())


## Each workspace shows only the dock tabs that belong to its job:
##   The left dock is a vertical split, like Godot's scene tree over its file
##   system: On stage (the rig) always on top, and below it the browser for the
##   job (a tab strip that only holds that workspace's tab).
##   Stage   - build the rig: On stage over Library on the left; Inspector (name,
##             patch, placement) + DMX patch map on the right. No timeline.
##   Program - write a song's show: On stage over Songs on the left; Inspector
##             (look and aim) + Cues on the right, with the timeline below.
##   Live    - run the night: no left dock; DJ sync + Cues on the right, timeline below.
func _apply_workspace(ws: StudioContext.Workspace) -> void:
	workspace_tabs.set_current_tab(ws)
	var left: Array[Control]
	var right: Array[Control]
	match ws:
		StudioContext.Workspace.STAGE:
			left = [%Library]
			right = [%Inspector, %DMX]
		StudioContext.Workspace.PROGRAM:
			left = [%Songs]
			right = [%Inspector, %Cues]
		StudioContext.Workspace.LIVE:
			right = [%DJ, %Cues]
	left_dock.visible = not left.is_empty()
	timeline.visible = ws != StudioContext.Workspace.STAGE
	_show_only(left_tabs, left)
	_show_only(right_tabs, right)


## Hide every tab of the container except `keep`; select the first of those
## unless the current tab is among them.
func _show_only(tabs: TabContainer, keep: Array[Control]) -> void:
	for i in tabs.get_tab_count():
		tabs.set_tab_hidden(i, not keep.has(tabs.get_tab_control(i)))
	if not keep.is_empty() and not keep.has(tabs.get_current_tab_control()):
		tabs.current_tab = tabs.get_tab_idx_from_control(keep[0])


func _update_footers() -> void:
	var ok := ctx.output != null
	(output_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UIPalette.LIVE if ctx.blackout else (UIPalette.OK if ok else UIPalette.TEXT_FAINT)
	output_label.text = ("Blackout · " if ctx.blackout else "") + "Art-Net · %s · Universe %d" % [ctx.output.target_ip, ctx.universe.universe_id + 1]
	var n := ctx.fixtures().size()
	rig_label.text = "%d fixture%s · %d channels" % [n, "" if n == 1 else "s", ctx.patched_channel_count()]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed or key.meta_pressed:
		_on_command_key(key)
		return
	match key.keycode:
		KEY_SPACE:
			ctx.toggle_play()
		KEY_ESCAPE:
			ctx.blackout = not ctx.blackout
		KEY_DELETE:
			if ctx.selected:
				ctx.remove_fixture(ctx.selected)
		KEY_F2:
			if ctx.selected:
				ctx.request_rename(ctx.selected)
		KEY_1:
			ctx.set_workspace(StudioContext.Workspace.STAGE)
		KEY_2:
			ctx.set_workspace(StudioContext.Workspace.PROGRAM)
		KEY_3:
			ctx.set_workspace(StudioContext.Workspace.LIVE)
		_:
			return
	get_viewport().set_input_as_handled()


## Ctrl (Cmd on a Mac) shortcuts. Any other Ctrl+key is left alone, so Ctrl+R
## or Ctrl+Z never also trigger the plain R / Z shortcuts.
func _on_command_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_Z:
			if key.shift_pressed:
				_redo()
			else:
				_undo()
		KEY_R, KEY_Y:
			_redo()
		_:
			return
	get_viewport().set_input_as_handled()


func _undo() -> void:
	# Not in the middle of a drag: the drag's own step isn't recorded yet.
	if not _mouse_held():
		ctx.undo()


func _redo() -> void:
	if not _mouse_held():
		ctx.redo()


func _mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
