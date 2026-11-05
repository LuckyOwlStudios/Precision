extends Control
## Main editor window. The layout lives in main_window.tscn so it can be
## rearranged in the Godot editor; this script only wires panels to the
## shared StudioContext and handles workspaces and global shortcuts.
##
## Drag audio files onto the window to import them into the song library.
##
## Shortcuts: Space = play/pause, Esc = blackout, Delete = remove selected fixture,
## F2 = rename selected fixture, W/E = move/rotate gizmo (stage view),
## 1/2/3 = Stage/Program/Live workspace (when no text field has focus).

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

	_title_tabs(left_tabs, ["Library", "On stage", "Songs"])
	_title_tabs(right_tabs, ["Inspector", "Cues", "DMX", "DJ"])

	workspace_tabs.current_tab = ctx.workspace
	workspace_tabs.tab_changed.connect(func(i: int) -> void: ctx.set_workspace(i as StudioContext.Workspace))
	ctx.workspace_changed.connect(_apply_workspace)
	ctx.fixtures_changed.connect(_update_footers)
	ctx.blackout_changed.connect(func(_on: bool) -> void: _update_footers())
	# Renaming happens in the inspector's Name field, so bring it to the front.
	ctx.rename_requested.connect(func(_fx: DMXFixture) -> void: right_tabs.current_tab = 0)
	_apply_workspace(ctx.workspace)
	_update_footers()

	# Audio files dropped anywhere on the window go into the song library.
	get_window().files_dropped.connect(_on_files_dropped)


func _on_files_dropped(files: PackedStringArray) -> void:
	ctx.import_songs(files)
	if left_dock.visible:
		left_tabs.current_tab = 2 # Songs, so you see what came in


func _title_tabs(tabs: TabContainer, titles: Array[String]) -> void:
	for i in titles.size():
		tabs.set_tab_title(i, titles[i].to_upper())


func _apply_workspace(ws: StudioContext.Workspace) -> void:
	workspace_tabs.set_current_tab(ws)
	match ws:
		StudioContext.Workspace.STAGE: # place and patch fixtures
			left_dock.visible = true
			timeline.visible = false
			left_tabs.current_tab = 0
			right_tabs.current_tab = 0
		StudioContext.Workspace.PROGRAM: # build a song's show
			left_dock.visible = true
			timeline.visible = true
		StudioContext.Workspace.LIVE: # run the night
			left_dock.visible = false
			timeline.visible = true
			right_tabs.current_tab = 1


func _update_footers() -> void:
	var ok := ctx.output != null
	(output_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UIPalette.LIVE if ctx.blackout else (UIPalette.OK if ok else UIPalette.TEXT_FAINT)
	output_label.text = ("Blackout · " if ctx.blackout else "") + "Art-Net · %s · Universe %d" % [ctx.output.target_ip, ctx.universe.universe_id + 1]
	var n := ctx.fixtures().size()
	rig_label.text = "%d fixture%s · %d channels" % [n, "" if n == 1 else "s", ctx.patched_channel_count()]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match (event as InputEventKey).keycode:
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
