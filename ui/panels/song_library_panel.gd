class_name SongLibraryPanel
extends MarginContainer
## Songs and the light show linked to each one. Placeholder until audio import
## and song-to-show linking land; the layout is here so the column feels right.

var ctx: StudioContext


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var head := UIKit.section("Songs", "+", "Import a song (coming soon)")
	(head.get_meta("action") as Button).disabled = true
	col.add_child(head)

	var search := LineEdit.new()
	search.placeholder_text = "Search songs"
	search.editable = false
	col.add_child(search)

	col.add_child(UIKit.empty_state("No songs yet", "Import a track and it gets its own light show. Play the song in your DJ software and its show plays with it."))

	var playlists := UIKit.section("Sets")
	col.add_child(playlists)
	var none := Label.new()
	none.text = "Group songs into a set for a night."
	none.theme_type_variation = &"Caption"
	none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(none)
