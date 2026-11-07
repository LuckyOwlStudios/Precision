class_name LuckyTheme
extends RefCounted
## Builds the Precision dark Theme from UIPalette.
##
## The theme is generated in code so colours stay in one file, then baked to
## res://ui/theme/lucky_dark.tres (see bake_theme.gd) so the editor shows it
## too. Project Settings > GUI > Theme > Custom points at the baked file.
##
## Type variations (set a Control's "Theme Type Variation" to use them):
##   PanelContainer: HeaderBar, FooterBar, SidePanel, CenterPanel, StagePanel, Card, HeroBar
##   Label:          SectionTitle, Subtitle, Caption, TitleLabel, BigTitle, MonoLabel
##   Button:         FlatButton, AccentButton, DangerButton, PillButton
##   TabBar:         WorkspaceTabs
##   HSeparator:     Hairline

const P := preload("res://ui/theme/ui_palette.gd")


## `touch` makes controls fingertip-sized; it is applied at run time, never baked.
static func build(touch := false) -> Theme:
	var t := Theme.new()
	var ui := _system_font(P.UI_FONTS, 400)
	var ui_bold := _system_font(P.UI_FONTS, 600)
	var ui_light := _system_font(P.UI_FONTS, 300)
	var mono := _system_font(P.MONO_FONTS, 400)

	t.default_font = ui
	t.default_font_size = P.FONT_SIZE

	_panels(t)
	_labels(t, ui_bold, ui_light, mono)
	_buttons(t, ui_bold)
	_inputs(t)
	_lists(t)
	_tabs(t, ui_bold)
	_sliders_and_scrollbars(t)
	_popups(t)
	_containers(t)
	if touch:
		_touch_sizing(t)
	return t


## Touchscreen present (or PRECISION_TOUCH=1 to try it without one).
static func touch_wanted() -> bool:
	return OS.get_environment("PRECISION_TOUCH") == "1" or DisplayServer.is_touchscreen_available()


## Fingertip-sized controls: taller buttons and list rows, fatter scrollbars.
## Mouse layouts are untouched.
static func _touch_sizing(t: Theme) -> void:
	for type: StringName in ["Button", "OptionButton", "MenuButton", "ColorPickerButton",
			"FlatButton", "AccentButton", "DangerButton", "PillButton"]:
		for state: StringName in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := t.get_stylebox(state, type)
			if box:
				var big := box.duplicate() as StyleBox
				big.content_margin_top = maxf(box.content_margin_top, TOUCH_PAD_V)
				big.content_margin_bottom = maxf(box.content_margin_bottom, TOUCH_PAD_V)
				t.set_stylebox(state, type, big)
	for type: StringName in ["CheckBox", "CheckButton"]:
		for state: StringName in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := t.get_stylebox(state, type).duplicate() as StyleBox
			box.content_margin_top = TOUCH_PAD_V
			box.content_margin_bottom = TOUCH_PAD_V
			t.set_stylebox(state, type, box)
	t.set_constant("v_separation", "ItemList", 18)
	t.set_constant("v_separation", "Tree", 14)
	t.set_constant("v_separation", "PopupMenu", 16)
	for type: StringName in ["HScrollBar", "VScrollBar"]:
		for state: StringName in ["scroll", "scroll_focus"]:
			var box := t.get_stylebox(state, type).duplicate() as StyleBox
			box.content_margin_left = 9
			box.content_margin_right = 9
			box.content_margin_top = 9
			box.content_margin_bottom = 9
			t.set_stylebox(state, type, box)


const TOUCH_PAD_V := 12.0 ## button padding top and bottom with a touchscreen (about 44 px tall)


# ---------------------------------------------------------------- helpers

static func _system_font(names: PackedStringArray, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = names
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


static func _flat(bg: Color, radius: int = P.RADIUS, margin_h: float = 8.0, margin_v: float = 4.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = radius > 0
	return s


static func _bordered(bg: Color, border: Color, width: int = 1, radius: int = P.RADIUS, margin_h: float = 8.0, margin_v: float = 4.0) -> StyleBoxFlat:
	var s := _flat(bg, radius, margin_h, margin_v)
	s.border_color = border
	s.set_border_width_all(width)
	return s


static func _empty(margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s


static func _variation(t: Theme, name: StringName, base: StringName) -> void:
	t.set_type_variation(name, base)


# ---------------------------------------------------------------- panels

static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "Panel", _flat(P.SIDE_BG, 0, 0, 0))
	t.set_stylebox("panel", "PanelContainer", _flat(P.SIDE_BG, 0, 0, 0))

	# Top bar: centre colour with a hairline underneath, roomy side padding.
	var header := _flat(P.CENTER_BG, 0, P.COLUMN_PAD, 0)
	header.border_color = P.HAIRLINE
	header.border_width_bottom = 1
	_variation(t, "HeaderBar", "PanelContainer")
	t.set_stylebox("panel", "HeaderBar", header)

	var footer := _flat(P.SIDE_BG, 0, P.COLUMN_PAD, 0)
	footer.border_color = P.HAIRLINE
	footer.border_width_top = 1
	_variation(t, "FooterBar", "PanelContainer")
	t.set_stylebox("panel", "FooterBar", footer)

	var side := _flat(P.SIDE_BG, 0, 0, 0)
	_variation(t, "SidePanel", "PanelContainer")
	t.set_stylebox("panel", "SidePanel", side)

	_variation(t, "CenterPanel", "PanelContainer")
	t.set_stylebox("panel", "CenterPanel", _flat(P.CENTER_BG, 0, 0, 0))

	_variation(t, "StagePanel", "PanelContainer")
	t.set_stylebox("panel", "StagePanel", _flat(P.APP_BG, 0, 0, 0))

	_variation(t, "Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _bordered(P.RAISED, P.HAIRLINE, 1, 6, P.PAD, P.PAD))

	# The "now playing" band draws its own gradient; the panel just pads it.
	_variation(t, "HeroBar", "PanelContainer")
	t.set_stylebox("panel", "HeroBar", _empty(P.COLUMN_PAD, 10))


# ---------------------------------------------------------------- text

static func _labels(t: Theme, bold: Font, light: Font, mono: Font) -> void:
	t.set_color("font_color", "Label", P.TEXT)

	# Thin, letter-spaced, uppercase section names ("FIXTURES", "CUES").
	var spaced := FontVariation.new()
	spaced.base_font = light
	spaced.spacing_glyph = 1
	_variation(t, "SectionTitle", "Label")
	t.set_font("font", "SectionTitle", spaced)
	t.set_font_size("font_size", "SectionTitle", P.FONT_SIZE_SECTION)
	t.set_color("font_color", "SectionTitle", P.TEXT)

	_variation(t, "Subtitle", "Label")
	t.set_color("font_color", "Subtitle", P.TEXT_DIM)
	t.set_font_size("font_size", "Subtitle", 12)

	_variation(t, "Caption", "Label")
	t.set_color("font_color", "Caption", P.TEXT_FAINT)
	t.set_font_size("font_size", "Caption", P.FONT_SIZE_SMALL)

	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", bold)

	_variation(t, "BigTitle", "Label")
	t.set_font("font", "BigTitle", light)
	t.set_font_size("font_size", "BigTitle", P.FONT_SIZE_TITLE)

	_variation(t, "MonoLabel", "Label")
	t.set_font("font", "MonoLabel", mono)
	t.set_font_size("font_size", "MonoLabel", 12)
	t.set_color("font_color", "MonoLabel", P.TEXT)

	t.set_font("mono_font", "LuckyDMX", mono) # read by custom-drawn widgets
	t.set_font("bold_font", "LuckyDMX", bold)


# ---------------------------------------------------------------- buttons

static func _button_colors(t: Theme, type: StringName, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_focus_color", type, normal)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, pressed)
	t.set_color("icon_disabled_color", type, disabled)


static func _buttons(t: Theme, bold: Font) -> void:
	var focus := _bordered(Color.TRANSPARENT, P.ACCENT, 1)
	focus.draw_center = false

	for type: StringName in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, _flat(P.RAISED, P.RADIUS, 10, 5))
		t.set_stylebox("hover", type, _flat(P.HOVER, P.RADIUS, 10, 5))
		t.set_stylebox("pressed", type, _bordered(P.ACCENT_DIM, P.ACCENT, 1, P.RADIUS, 10, 5))
		t.set_stylebox("hover_pressed", type, _bordered(P.ACCENT_DIM, P.ACCENT, 1, P.RADIUS, 10, 5))
		t.set_stylebox("disabled", type, _flat(P.RAISED.darkened(0.25), P.RADIUS, 10, 5))
		t.set_stylebox("focus", type, focus)
		_button_colors(t, type, P.TEXT, P.TEXT, P.ACCENT, P.TEXT_FAINT)
	t.set_constant("h_separation", "Button", 6)

	# Icon / text buttons that only show a background on hover (toolbars).
	_variation(t, "FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", _empty(6, 4))
	t.set_stylebox("hover", "FlatButton", _flat(P.HOVER, P.RADIUS, 6, 4))
	t.set_stylebox("pressed", "FlatButton", _flat(P.ACCENT_DIM, P.RADIUS, 6, 4))
	t.set_stylebox("hover_pressed", "FlatButton", _flat(P.ACCENT_DIM, P.RADIUS, 6, 4))
	t.set_stylebox("disabled", "FlatButton", _empty(6, 4))
	_button_colors(t, "FlatButton", P.TEXT_DIM, P.TEXT, P.ACCENT, P.TEXT_FAINT)

	# The one primary action in a panel (GO, Record).
	_variation(t, "AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _flat(P.ACCENT, P.RADIUS, 12, 5))
	t.set_stylebox("hover", "AccentButton", _flat(P.ACCENT.lightened(0.15), P.RADIUS, 12, 5))
	t.set_stylebox("pressed", "AccentButton", _flat(P.ACCENT.darkened(0.15), P.RADIUS, 12, 5))
	t.set_stylebox("hover_pressed", "AccentButton", _flat(P.ACCENT.darkened(0.15), P.RADIUS, 12, 5))
	t.set_font("font", "AccentButton", bold)
	_button_colors(t, "AccentButton", P.APP_BG, P.APP_BG, P.APP_BG, P.TEXT_FAINT)

	# Blackout and other "this affects the room right now" buttons.
	_variation(t, "DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", _bordered(Color(P.LIVE, 0.08), Color(P.LIVE, 0.6), 1, P.RADIUS, 12, 5))
	t.set_stylebox("hover", "DangerButton", _bordered(Color(P.LIVE, 0.18), P.LIVE, 1, P.RADIUS, 12, 5))
	t.set_stylebox("pressed", "DangerButton", _flat(P.LIVE, P.RADIUS, 12, 5))
	t.set_stylebox("hover_pressed", "DangerButton", _flat(P.LIVE, P.RADIUS, 12, 5))
	t.set_font("font", "DangerButton", bold)
	_button_colors(t, "DangerButton", P.LIVE, P.TEXT, P.TEXT, P.TEXT_FAINT)

	# Small rounded status chips (output state, BPM).
	_variation(t, "PillButton", "Button")
	t.set_stylebox("normal", "PillButton", _bordered(Color(0, 0, 0, 0.25), P.HAIRLINE, 1, 12, 10, 3))
	t.set_stylebox("hover", "PillButton", _bordered(Color(0, 0, 0, 0.35), P.TEXT_FAINT, 1, 12, 10, 3))
	t.set_stylebox("pressed", "PillButton", _bordered(Color(0, 0, 0, 0.35), P.ACCENT, 1, 12, 10, 3))
	t.set_font_size("font_size", "PillButton", P.FONT_SIZE_SMALL)
	_button_colors(t, "PillButton", P.TEXT_DIM, P.TEXT, P.ACCENT, P.TEXT_FAINT)

	for type: StringName in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, _empty(4, 2))
		t.set_stylebox("hover", type, _empty(4, 2))
		t.set_stylebox("pressed", type, _empty(4, 2))
		t.set_stylebox("hover_pressed", type, _empty(4, 2))
		t.set_stylebox("focus", type, _empty())
		_button_colors(t, type, P.TEXT_DIM, P.TEXT, P.TEXT, P.TEXT_FAINT)


# ---------------------------------------------------------------- inputs

static func _inputs(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", _bordered(P.INPUT_BG, P.HAIRLINE, 1, P.RADIUS, 10, 5))
	t.set_stylebox("focus", "LineEdit", _bordered(Color.TRANSPARENT, P.ACCENT, 1, P.RADIUS, 10, 5))
	t.set_stylebox("read_only", "LineEdit", _flat(P.INPUT_BG, P.RADIUS, 10, 5))
	t.set_color("font_color", "LineEdit", P.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", P.TEXT_FAINT)
	t.set_color("font_uneditable_color", "LineEdit", P.TEXT_DIM)
	t.set_color("caret_color", "LineEdit", P.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(P.ACCENT, 0.3))

	t.set_stylebox("normal", "TextEdit", _bordered(P.INPUT_BG, P.HAIRLINE, 1, P.RADIUS, 10, 6))
	t.set_stylebox("focus", "TextEdit", _bordered(Color.TRANSPARENT, P.ACCENT, 1, P.RADIUS, 10, 6))
	t.set_color("font_color", "TextEdit", P.TEXT)
	t.set_color("caret_color", "TextEdit", P.ACCENT)


# ---------------------------------------------------------------- lists

static func _lists(t: Theme) -> void:
	# The reference's selected row: a full-width grey band, no outline.
	var selected := _flat(P.SELECTED_ROW, 0, 0, 0)
	selected.border_color = P.ACCENT
	selected.border_width_left = 2
	var hovered := _flat(Color(P.HOVER, 0.6), 0, 0, 0)

	for type: StringName in ["Tree", "ItemList"]:
		t.set_stylebox("panel", type, _empty(0, 4))
		t.set_stylebox("focus", type, _empty())
		t.set_stylebox("selected", type, selected)
		t.set_stylebox("selected_focus", type, selected)
		t.set_stylebox("cursor", type, _empty())
		t.set_stylebox("cursor_unfocused", type, _empty())
		t.set_stylebox("hovered", type, hovered)
		t.set_color("font_color", type, P.TEXT_DIM)
		t.set_color("font_selected_color", type, P.TEXT)
		t.set_color("font_hovered_color", type, P.TEXT)
		t.set_color("guide_color", type, Color.TRANSPARENT)
		t.set_constant("h_separation", type, 8)

	t.set_constant("v_separation", "ItemList", 10)
	t.set_constant("line_separation", "ItemList", 4)

	t.set_constant("v_separation", "Tree", 8)
	t.set_constant("item_margin", "Tree", 14)
	t.set_constant("inner_item_margin_left", "Tree", 6)
	t.set_constant("draw_guides", "Tree", 0)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_color("relationship_line_color", "Tree", P.HAIRLINE)
	t.set_color("drop_position_color", "Tree", P.ACCENT)
	t.set_color("title_button_color", "Tree", P.TEXT_DIM)
	t.set_stylebox("title_button_normal", "Tree", _flat(P.SIDE_BG, 0, 8, 4))
	t.set_stylebox("title_button_hover", "Tree", _flat(P.HOVER, 0, 8, 4))
	t.set_stylebox("title_button_pressed", "Tree", _flat(P.HOVER, 0, 8, 4))
	t.set_stylebox("hovered_dimmed", "Tree", _empty())


# ---------------------------------------------------------------- tabs

static func _tabs(t: Theme, bold: Font) -> void:
	# Text-only tabs with an amber underline on the active one.
	var active := _flat(Color.TRANSPARENT, 0, 10, 8)
	active.draw_center = false
	active.border_color = P.ACCENT
	active.border_width_bottom = 2
	var idle := _empty(10, 8)
	var hover := _flat(Color.TRANSPARENT, 0, 10, 8)
	hover.draw_center = false
	hover.border_color = P.HAIRLINE
	hover.border_width_bottom = 2

	var bar_bg := _flat(P.SIDE_BG, 0, 8, 0)
	bar_bg.border_color = P.HAIRLINE
	bar_bg.border_width_bottom = 1

	for type: StringName in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, active)
		t.set_stylebox("tab_unselected", type, idle)
		t.set_stylebox("tab_hovered", type, hover)
		t.set_stylebox("tab_disabled", type, idle)
		t.set_stylebox("tab_focus", type, _empty())
		t.set_color("font_selected_color", type, P.TEXT)
		t.set_color("font_unselected_color", type, P.TEXT_DIM)
		t.set_color("font_hovered_color", type, P.TEXT)
		t.set_color("font_disabled_color", type, P.TEXT_FAINT)
		t.set_font("font", type, bold)
		t.set_font_size("font_size", type, P.FONT_SIZE_SMALL + 1)
	t.set_stylebox("panel", "TabContainer", _flat(P.SIDE_BG, 0, 0, 0))
	t.set_stylebox("tabbar_background", "TabContainer", bar_bg)
	t.set_constant("side_margin", "TabContainer", 12)

	# Workspace switcher in the header: same idea, a little larger.
	_variation(t, "WorkspaceTabs", "TabBar")
	var ws_active := active.duplicate() as StyleBoxFlat
	ws_active.content_margin_left = 14
	ws_active.content_margin_right = 14
	ws_active.content_margin_top = 18
	ws_active.content_margin_bottom = 16
	var ws_idle := _empty(14, 17)
	t.set_stylebox("tab_selected", "WorkspaceTabs", ws_active)
	t.set_stylebox("tab_unselected", "WorkspaceTabs", ws_idle)
	t.set_stylebox("tab_hovered", "WorkspaceTabs", ws_idle)
	t.set_font_size("font_size", "WorkspaceTabs", P.FONT_SIZE)


# ---------------------------------------------------------------- sliders

static func _sliders_and_scrollbars(t: Theme) -> void:
	var track := _flat(P.RAISED, 2, 0, 2)
	var filled := _flat(P.ACCENT, 2, 0, 2)
	var filled_hover := _flat(P.ACCENT.lightened(0.15), 2, 0, 2)
	for type: StringName in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, filled)
		t.set_stylebox("grabber_area_highlight", type, filled_hover)

	for type: StringName in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", type, _empty(3, 3))
		t.set_stylebox("scroll_focus", type, _empty(3, 3))
		t.set_stylebox("grabber", type, _flat(P.HOVER, 3, 3, 3))
		t.set_stylebox("grabber_highlight", type, _flat(P.TEXT_FAINT, 3, 3, 3))
		t.set_stylebox("grabber_pressed", type, _flat(P.TEXT_DIM, 3, 3, 3))

	t.set_stylebox("background", "ProgressBar", _flat(P.RAISED, 2, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _flat(P.ACCENT, 2, 0, 0))
	t.set_color("font_color", "ProgressBar", P.TEXT)


# ---------------------------------------------------------------- popups

static func _popups(t: Theme) -> void:
	var popup := _bordered(P.RAISED, P.HAIRLINE, 1, 6, 6, 6)
	popup.shadow_color = Color(0, 0, 0, 0.45)
	popup.shadow_size = 12
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("hover", "PopupMenu", _flat(P.HOVER, P.RADIUS, 8, 4))
	t.set_color("font_color", "PopupMenu", P.TEXT)
	t.set_color("font_hover_color", "PopupMenu", P.TEXT)
	t.set_color("font_disabled_color", "PopupMenu", P.TEXT_FAINT)
	t.set_color("font_separator_color", "PopupMenu", P.TEXT_FAINT)
	t.set_constant("v_separation", "PopupMenu", 8)

	t.set_stylebox("panel", "TooltipPanel", _bordered(P.RAISED, P.HAIRLINE, 1, P.RADIUS, 8, 5))
	t.set_color("font_color", "TooltipLabel", P.TEXT)

	t.set_stylebox("panel", "AcceptDialog", _flat(P.SIDE_BG, 6, P.PAD, P.PAD))


# ---------------------------------------------------------------- containers

static func _containers(t: Theme) -> void:
	t.set_constant("separation", "HSplitContainer", 1)
	t.set_constant("separation", "VSplitContainer", 1)
	t.set_constant("minimum_grab_thickness", "HSplitContainer", 8)
	t.set_constant("minimum_grab_thickness", "VSplitContainer", 8)
	t.set_constant("autohide", "HSplitContainer", 1)
	t.set_constant("autohide", "VSplitContainer", 1)
	# No dotted grabber: the 1 px hairline gap is the handle (cursor changes on hover).
	var none := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for type: StringName in ["SplitContainer", "HSplitContainer", "VSplitContainer"]:
		t.set_icon("grabber", type, none)
		t.set_icon("h_grabber", type, none)
		t.set_icon("v_grabber", type, none)
	t.set_constant("separation", "BoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)

	var line := StyleBoxLine.new()
	line.color = P.HAIRLINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 1)
	var vline := StyleBoxLine.new()
	vline.color = P.HAIRLINE
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	t.set_constant("separation", "VSeparator", 1)

	_variation(t, "Hairline", "HSeparator")
	t.set_stylebox("separator", "Hairline", line)
