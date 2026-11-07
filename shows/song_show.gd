class_name SongShow
extends Resource
## The light show that belongs to one song: its clips on the beat grid.
## Saved next to the song library (SongLibrary.show_path_for()) and loaded
## whenever that song is put on the timeline, by hand or by the DJ.

@export var clips: Array[ShowClip] = []

## Where it is saved (set when loaded or first saved). Empty for the scratch
## show used while no song is loaded, which is not saved.
var file_path: String = ""
