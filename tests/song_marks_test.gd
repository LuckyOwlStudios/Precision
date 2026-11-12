extends SceneTree
## Checks beat grid alignment and phrase markers: moving the first beat, adding,
## renaming, moving and deleting phrases, undo/redo, and saving with the song.
##   godot --headless --path . --script res://tests/song_marks_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.library.root_dir = "user://song_marks_test"

	var song := Song.new()
	song.id = "marks_test_song"
	song.duration = 120.0
	song.bpm = 120.0
	ctx.song = song # skip audio loading
	ctx.bpm = 120.0

	_expect(is_zero_approx(ctx.first_beat_beats()), "the grid starts at 0 by default")
	ctx.set_beat_offset(0.5)
	_expect(is_equal_approx(ctx.first_beat_beats(), 1.0), "0.5 s at 120 BPM is one beat in")
	ctx.position_beats = 4.0
	ctx.set_first_beat_here()
	_expect(is_equal_approx(song.beat_offset, 2.0), "first beat goes under the playhead")
	ctx.nudge_beat_offset(-0.01)
	_expect(is_equal_approx(song.beat_offset, 1.99), "nudge moves it by 10 ms")
	ctx.history.undo()
	_expect(is_equal_approx(song.beat_offset, 2.0), "undo puts it back")
	ctx.set_beat_offset(-5.0)
	_expect(is_zero_approx(song.beat_offset), "never before the start of the audio")

	ctx.add_phrase(30.0, "Drop")
	ctx.add_phrase(10.0, "Intro")
	_expect(song.phrases.size() == 2 and song.phrases[0].name == "Intro", "phrases stay sorted by time")
	_expect(song.phrase_index_at(5.0) == -1 and song.phrase_index_at(12.0) == 0 and song.phrase_index_at(31.0) == 1, "finding the phrase at a time")
	ctx.rename_phrase(0, "Build")
	_expect(song.phrases[0].name == "Build", "rename")

	# Dragging edits live, then commits as one undo step.
	var start := song.marks_state()
	song.phrases[0].time = 40.0
	song.sort_phrases()
	ctx.commit_marks("Move phrase", start)
	_expect(song.phrases[0].name == "Drop" and song.phrases[1].time == 40.0, "moving past another phrase re-sorts")
	ctx.history.undo()
	_expect(song.phrases[0].name == "Build" and song.phrases[0].time == 10.0, "undo a drag")
	ctx.history.redo()
	_expect(song.phrases[1].time == 40.0, "redo a drag")

	var back := Song.from_dict(song.to_dict())
	_expect(back.phrases.size() == 2 and back.phrases[1].name == "Build", "phrases survive saving")
	ctx.remove_phrase(0)
	_expect(song.phrases.size() == 1, "delete")
	ctx.history.undo()
	_expect(song.phrases.size() == 2, "undo delete")
	_expect(PhraseKinds.color_for("Drop 2") == PhraseKinds.COLORS["drop"], "names pick a colour by their first word")

	DirAccess.remove_absolute("user://song_marks_test/songs.json")
	print("song_marks_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
