class_name Song
extends RefCounted
## One track in the song library: where its audio lives, what it is called,
## its tempo, and the light show that plays with it.
##
## Plain data only. Loading audio is AudioDecoder's job and keeping the list
## is SongLibrary's, so this stays easy to save and to test.

## Stable id, taken from the file's contents, so the same track imported
## twice is recognised as a duplicate.
var id: String = ""
var title: String = ""
var artist: String = ""
var album: String = ""
## Seconds.
var duration: float = 0.0
## Beats per minute. 0 means unknown (the transport keeps its own tempo).
var bpm: float = 0.0
## The library's own copy of the audio (user://music/...).
var file_path: String = ""
## Where it was imported from, for display only.
var source_path: String = ""
var imported_at: int = 0 ## unix seconds

## Where the first beat (bar 1, beat 1) falls in the audio, in seconds. Many
## tracks start with silence or a pickup, so the beat grid is drawn from here
## instead of from 0. See StudioContext.set_beat_offset().
var beat_offset: float = 0.0
## Named sections of the song (intro, build, drop...), sorted by time. Each is
## {"time": seconds, "name": String}; a phrase runs until the next one starts.
## Kept in seconds so they stay on the music if the tempo is corrected.
var phrases: Array[Dictionary] = []
## True once you placed the first beat yourself; the automatic guess then leaves it alone.
var beat_offset_set: bool = false

## The light show linked to this song. When the song plays, this show plays.
## The show format is not built yet, so for now this is a name plus the path
## the show will be saved to (see SongLibrary.show_path_for()).
var show_id: String = ""
var show_name: String = ""

## Waveform: one peak (0..1) per 1/PEAKS_PER_SECOND seconds. Not saved in the
## library file; it is cached next to the audio and loaded on demand.
var peaks: PackedFloat32Array = PackedFloat32Array()
var analysing: bool = false

const PEAKS_PER_SECOND := 50


func display_title() -> String:
	return title if not title.is_empty() else file_path.get_file().get_basename()


## "DJ Owl · 3:42 · 128 BPM", skipping whatever is unknown.
func detail_line() -> String:
	var bits: PackedStringArray = []
	if not artist.is_empty():
		bits.append(artist)
	if duration > 0.0:
		bits.append(format_time(duration))
	if bpm > 0.0:
		bits.append("%s BPM" % _trim_float(bpm))
	return " · ".join(bits)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"artist": artist,
		"album": album,
		"duration": duration,
		"bpm": bpm,
		"file_path": file_path,
		"source_path": source_path,
		"imported_at": imported_at,
		"show_id": show_id,
		"show_name": show_name,
		"beat_offset": beat_offset,
		"beat_offset_set": beat_offset_set,
		"phrases": phrases.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Song:
	var s := Song.new()
	s.id = str(d.get("id", ""))
	s.title = str(d.get("title", ""))
	s.artist = str(d.get("artist", ""))
	s.album = str(d.get("album", ""))
	s.duration = float(d.get("duration", 0.0))
	s.bpm = float(d.get("bpm", 0.0))
	s.file_path = str(d.get("file_path", ""))
	s.source_path = str(d.get("source_path", ""))
	s.imported_at = int(d.get("imported_at", 0))
	s.show_id = str(d.get("show_id", ""))
	s.show_name = str(d.get("show_name", ""))
	s.beat_offset = maxf(0.0, float(d.get("beat_offset", 0.0)))
	s.beat_offset_set = bool(d.get("beat_offset_set", false))
	for p: Variant in d.get("phrases", []):
		if p is Dictionary and (p as Dictionary).has("time"):
			s.phrases.append({"time": float(p.time), "name": str(p.get("name", ""))})
	s.sort_phrases()
	return s


func sort_phrases() -> void:
	phrases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)


## Index of the phrase playing at `seconds`, or -1 before the first one.
func phrase_index_at(seconds: float) -> int:
	var found := -1
	for i in phrases.size():
		if phrases[i].time <= seconds + 0.0001:
			found = i
	return found


## The beat-grid and phrase state as one plain value, for undo.
func marks_state() -> Dictionary:
	return {"beat_offset": beat_offset, "beat_offset_set": beat_offset_set, "phrases": phrases.duplicate(true)}


func apply_marks_state(state: Dictionary) -> void:
	beat_offset = float(state.beat_offset)
	beat_offset_set = bool(state.get("beat_offset_set", beat_offset_set))
	phrases.clear()
	for p: Dictionary in state.phrases:
		phrases.append(p.duplicate())
	sort_phrases()


static func format_time(seconds: float) -> String:
	var t := int(roundf(seconds))
	return "%d:%02d" % [t / 60, t % 60]


static func _trim_float(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
