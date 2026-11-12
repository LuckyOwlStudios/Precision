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
## 1/2/3 = Stage/Program/Live workspace, Ctrl+K = search every action. None of these fire while you're typing
## in a text field: there Ctrl+Z undoes your typing instead.

@onready var ctx: StudioContext = %Studio
@onready var workspace_tabs: TabBar = %WorkspaceTabs
@onready var left_dock: Control = %LeftDock
@onready var left_tabs: TabContainer = %LeftTabs
@onready var right_tabs: TabContainer = %RightTabs
@onready var right_dock: Control = %RightDock
@onready var timeline: Control = %Timeline
@onready var stage: StageView = %StageView
@onready var output_label: Label = %OutputLabel
@onready var output_dot: Panel = %OutputDot
@onready var rig_label: Label = %RigLabel
@onready var palette: CommandPalette = %CommandPalette


func _ready() -> void:
	if LuckyTheme.touch_wanted():
		theme = LuckyTheme.build(true) # bigger buttons, rows and scrollbars for fingers
	for panel: Node in [%NowPlaying, stage, timeline, %Library, %OnStage, %Songs, %Inspector, %Looks, %LiveLooks, %Cues, %DMX, %DJ, %Effects]:
		panel.call("setup", ctx)

	_title_tabs(left_tabs, ["Library", "Songs", "Effects"])
	_title_tabs(right_tabs, ["Inspector", "Looks", "Looks", "Cues", "DMX", "DJ"])

	workspace_tabs.current_tab = ctx.workspace
	workspace_tabs.tab_changed.connect(func(i: int) -> void: ctx.set_workspace(i as StudioContext.Workspace))
	ctx.workspace_changed.connect(_apply_workspace)
	ctx.fixtures_changed.connect(_update_footers)
	ctx.blackout_changed.connect(func(_on: bool) -> void: _update_footers())
	# Selecting an effect clip on the timeline shows it in the Inspector tab.
	ctx.clip_selected.connect(func(clip: ShowClip) -> void:
		if clip and not right_tabs.is_tab_hidden(right_tabs.get_tab_idx_from_control(%Inspector)):
			right_tabs.current_tab = right_tabs.get_tab_idx_from_control(%Inspector))
	# Renaming happens in the inspector's Name field, so bring it to the front
	# (that field lives in Stage and Program; from Live, go to Stage).
	ctx.rename_requested.connect(func(_fx: DMXFixture) -> void:
		if ctx.workspace == StudioContext.Workspace.LIVE:
			ctx.set_workspace(StudioContext.Workspace.STAGE)
		right_tabs.current_tab = right_tabs.get_tab_idx_from_control(%Inspector))
	%SettingsButton.pressed.connect(%SettingsWindow.open)
	palette.setup(ctx.actions)
	ctx.actions.register(&"look.copy", "Copy look", func() -> void: _copy_look(), {category = "Fixture", shortcut = "Ctrl+C", keywords = "copy colour settings"})
	ctx.actions.register(&"look.paste", "Paste look", func() -> void: _paste_look(), {category = "Fixture", shortcut = "Ctrl+V", keywords = "paste colour settings", enabled = func() -> bool: return not ctx.look_clipboard.is_empty()})
	%SearchButton.pressed.connect(palette.open)
	_register_actions()
	_apply_workspace(ctx.workspace)
	# First launch: Stage with the fixture Library in front of the left dock.
	left_tabs.current_tab = left_tabs.get_tab_idx_from_control(%Library)
	_update_footers()

	# Audio files dropped anywhere on the window go into the song library.
	get_window().files_dropped.connect(_on_files_dropped)


## The app-wide actions of the Ctrl+K search. Other features register their own
## on ctx.actions (see ActionRegistry); this is just the ones that belong to
## the window itself. The shortcut text is only shown, _unhandled_input below
## does the real work.
func _register_actions() -> void:
	var a := ctx.actions
	var has_selection := func() -> bool: return ctx.selected != null
	a.register(&"edit.undo", "Undo", ctx.undo, {category = "Edit", shortcut = "Ctrl+Z", keywords = "revert"})
	a.register(&"edit.redo", "Redo", ctx.redo, {category = "Edit", shortcut = "Ctrl+R", keywords = "again"})
	a.register(&"edit.remove_fixture", "Remove selected fixture", func() -> void: ctx.remove_fixture(ctx.selected),
		{category = "Fixture", shortcut = "Delete", keywords = "delete", enabled = has_selection})
	a.register(&"edit.rename_fixture", "Rename selected fixture", func() -> void: ctx.request_rename(ctx.selected),
		{category = "Fixture", shortcut = "F2", enabled = has_selection})
	a.register(&"transport.play", "Play / pause", ctx.toggle_play, {category = "Transport", shortcut = "Space", keywords = "start stop"})
	a.register(&"transport.start", "Back to start", func() -> void: ctx.seek(0.0), {category = "Transport", shortcut = "Home", keywords = "rewind"})
	a.register(&"transport.tap_tempo", "Tap tempo", ctx.tap_tempo,
		{category = "Transport", shortcut = "Y", keywords = "bpm beat tempo tap",
		enabled = func() -> bool: return not ctx.following_dj()})
	a.register(&"output.blackout", "Toggle blackout", func() -> void: ctx.blackout = not ctx.blackout,
		{category = "Output", shortcut = "Esc", keywords = "lights off dark"})
	a.register(&"workspace.stage", "Go to Stage", ctx.set_workspace.bind(StudioContext.Workspace.STAGE), {category = "Workspace", shortcut = "1", keywords = "rig build"})
	a.register(&"workspace.program", "Go to Program", ctx.set_workspace.bind(StudioContext.Workspace.PROGRAM), {category = "Workspace", shortcut = "2", keywords = "timeline show"})
	a.register(&"workspace.live", "Go to Live", ctx.set_workspace.bind(StudioContext.Workspace.LIVE), {category = "Workspace", shortcut = "3", keywords = "perform"})
	a.register(&"app.settings", "Open settings", %SettingsWindow.open, {category = "App", keywords = "preferences quality units language"})


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
##   Program - write a song's show: On stage over Effects + Songs on the left; Inspector
##             (look and aim) + Looks + Cues on the right, with the timeline below.
##   Live    - run the night: no left dock; big Looks tiles, DJ sync + Cues on the right (wider dock), timeline below.
func _apply_workspace(ws: StudioContext.Workspace) -> void:
	workspace_tabs.set_current_tab(ws)
	var left: Array[Control]
	var right: Array[Control]
	match ws:
		StudioContext.Workspace.STAGE:
			left = [%Library]
			right = [%Inspector, %DMX]
		StudioContext.Workspace.PROGRAM:
			left = [%Effects, %Songs]
			right = [%Inspector, %Looks, %Cues]
		StudioContext.Workspace.LIVE:
			right = [%LiveLooks, %DJ, %Cues]
	left_dock.visible = not left.is_empty()
	# Live gets a wider right dock so the look tiles are easy to hit.
	right_dock.custom_minimum_size.x = 440.0 if ws == StudioContext.Workspace.LIVE else 300.0
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
		KEY_Y:
			ctx.tap_tempo()
		KEY_HOME:
			ctx.seek(0.0) # back to the start; the timeline scrolls there too
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
		KEY_C:
			if not _copy_look():
				return
		KEY_V:
			if not _paste_look():
				return
		KEY_D:
			ctx.duplicate_requested.emit()
		KEY_K:
			palette.toggle()
		_:
			return
	get_viewport().set_input_as_handled()


## Ctrl+C: copy the picked fixture's look (the first of a box selection).
func _copy_look() -> bool:
	var fx := ctx.selected if ctx.selected else (ctx.selected_group[0] if not ctx.selected_group.is_empty() else null)
	return ctx.copy_look(fx)


## Ctrl+V: paste the copied look on the picked fixture(s), matching by channel.
func _paste_look() -> bool:
	var targets: Array = ctx.selected_group.duplicate()
	if ctx.selected:
		targets = [ctx.selected]
	if targets.is_empty() or ctx.look_clipboard.is_empty():
		return false
	ctx.paste_look(targets)
	return true


func _undo() -> void:
	# Not in the middle of a drag: the drag's own step isn't recorded yet.
	if not _mouse_held():
		ctx.undo()


func _redo() -> void:
	if not _mouse_held():
		ctx.redo()


func _mouse_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
