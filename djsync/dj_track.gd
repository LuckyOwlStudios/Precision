class_name DJTrack
extends RefCounted
## What the DJ software says is playing. Every adapter fills in what its
## protocol knows and leaves the rest empty; TrackMatcher uses whatever is
## there to find the song in your library.

var title: String = ""
var artist: String = ""
## Full path of the audio file on the DJ's computer, if the software tells us.
var file_path: String = ""
## Seconds. 0 means unknown.
var duration: float = 0.0
## The track's own tempo (before the DJ's pitch fader). 0 means unknown.
var bpm: float = 0.0
## Which deck it is on (1-based), 0 if the protocol has no decks.
var deck: int = 0


static func make(p_title: String, p_artist: String = "", p_file_path: String = "", p_duration: float = 0.0, p_bpm: float = 0.0, p_deck: int = 0) -> DJTrack:
	var t := DJTrack.new()
	t.title = p_title
	t.artist = p_artist
	t.file_path = p_file_path
	t.duration = p_duration
	t.bpm = p_bpm
	t.deck = p_deck
	return t


## Two reports describe the same track (used to spot a real track change).
func same_as(other: DJTrack) -> bool:
	if other == null:
		return false
	if not file_path.is_empty() and not other.file_path.is_empty():
		return file_path == other.file_path
	return title == other.title and artist == other.artist


func is_empty() -> bool:
	return title.is_empty() and file_path.is_empty()


## "Artist - Title" for status lines.
func label() -> String:
	var t := title if not title.is_empty() else file_path.get_file().get_basename()
	return t if artist.is_empty() else "%s - %s" % [artist, t]
