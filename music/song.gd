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
	return s


static func format_time(seconds: float) -> String:
	var t := int(roundf(seconds))
	return "%d:%02d" % [t / 60, t % 60]


static func _trim_float(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
