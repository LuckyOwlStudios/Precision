class_name UIKit
extends RefCounted
## Small builders for the repeated pieces of the layout, so every panel
## gets the same section headings, spacing and empty states.


## "FIXTURES   (+)" with a hairline under it, like the reference's GENRES heading.
## Returns the container; the optional action button is in meta "action".
static func section(title: String, action_text: String = "", action_tip: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.uppercase = true
	label.theme_type_variation = &"SectionTitle"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if not action_text.is_empty():
		var b := Button.new()
		b.text = action_text
		b.tooltip_text = action_tip
		b.theme_type_variation = &"FlatButton"
		b.focus_mode = Control.FOCUS_NONE
		row.add_child(b)
		box.set_meta("action", b)
	box.add_child(row)
	box.add_child(HSeparator.new())
	return box


## Padding wrapper used by side columns (20 px sides, like the reference).
static func padded(child: Control, h: int = UIPalette.COLUMN_PAD, v: int = 16) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.add_child(child)
	return m


## Centred grey message for panels with nothing in them yet.
static func empty_state(title: String, body: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"TitleLabel"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := Label.new()
	b.text = body
	b.theme_type_variation = &"Subtitle"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 160
	box.add_child(t)
	box.add_child(b)
	return box


## Two-line row: bold name over grey detail (the reference's album tiles).
static func title_pair(title: String, detail: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"TitleLabel"
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var d := Label.new()
	d.text = detail
	d.theme_type_variation = &"Subtitle"
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(t)
	box.add_child(d)
	box.set_meta("title", t)
	box.set_meta("detail", d)
	return box


## Label + control on one row, label fixed width (inspector fields).
static func field(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = &"Subtitle"
	l.custom_minimum_size.x = 72
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
