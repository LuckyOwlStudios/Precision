class_name SongLibrary
extends Node
## The list of songs you've imported. Importing copies the audio into the
## library folder (so moving or deleting the original doesn't break a show),
## reads its tags, and works out its waveform in the background.
## The list is saved to songs.json in the same folder after every change.
##
## Where that is: Godot's user data folder for the app, e.g.
##   Windows  %APPDATA%\Godot\app_userdata\Precision\library
##   macOS    ~/Library/Application Support/Godot/app_userdata/Precision/library
##   Linux    ~/.local/share/godot/app_userdata/Precision/library
##
## No UI in here: panels listen to the signals.

signal songs_changed
signal song_updated(song: Song) ## tags, tempo or waveform changed
## One per import call, after every file was tried. `failed` holds
## {path, reason} dictionaries.
signal import_finished(added: Array[Song], failed: Array[Dictionary])

## Override for tests; everything lives under this folder.
@export var root_dir: String = "user://library"

var songs: Array[Song] = []

var _tasks: Dictionary = {} ## WorkerThreadPool task id -> Song
var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func _ensure_loaded() -> void:
	if not _loaded:
		load_library()


func _exit_tree() -> void:
	for task_id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_tasks.clear()


# ------------------------------------------------------------------ paths

func music_dir() -> String:
	return root_dir.path_join("music")


func library_file() -> String:
	return root_dir.path_join("songs.json")


## Where the song's light show will be saved once shows are a file format.
func show_path_for(song: Song) -> String:
	return root_dir.path_join("shows").path_join(song.show_id + ".tres")


func _peaks_file(song: Song) -> String:
	return music_dir().path_join(song.id + ".peaks")


# ----------------------------------------------------------------- import

## Import files and folders (folders are searched for audio). Returns the
## songs that were added; duplicates and unsupported files are reported in
## import_finished instead.
func import_files(paths: PackedStringArray) -> Array[Song]:
	var added: Array[Song] = []
	var failed: Array[Dictionary] = []
	_ensure_loaded()
	DirAccess.make_dir_recursive_absolute(music_dir())
	for path in _expand(paths):
		var reason := AudioDecoder.unsupported_reason(path)
		if reason.is_empty():
			var result: Variant = _import_one(path)
			if result is Song:
				added.append(result)
				continue
			reason = str(result)
		failed.append({"path": path, "reason": reason})
	if not added.is_empty():
		save_library()
		songs_changed.emit()
	import_finished.emit(added, failed)
	return added


## Returns the new Song, or a String saying why it wasn't imported.
func _import_one(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return "File not found."
	var md5 := FileAccess.get_md5(path)
	if md5.is_empty():
		return "Couldn't read the file."
	var id := md5.substr(0, 16)
	var existing := find(id)
	if existing:
		return "Already in your library as \"%s\"." % existing.display_title()

	var stream := AudioDecoder.load_stream(path)
	if stream == null or stream.get_length() <= 0.0:
		return "Couldn't decode this file. It may be damaged or use an unusual encoding."

	var dest := music_dir().path_join(id + "." + path.get_extension().to_lower())
	var err := DirAccess.copy_absolute(path, dest)
	if err != OK:
		return "Couldn't copy it into the library (%s)." % error_string(err)

	var tags := AudioMetadata.read(path)
	var song := Song.new()
	song.id = id
	song.title = tags.title
	song.artist = tags.artist
	song.album = tags.album
	song.bpm = tags.bpm
	song.duration = stream.get_length()
	song.file_path = dest
	song.source_path = path
	song.imported_at = int(Time.get_unix_time_from_system())
	song.show_id = id
	song.show_name = "%s show" % song.display_title()
	songs.append(song)
	ensure_peaks(song)
	return song


func _expand(paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths:
		if DirAccess.dir_exists_absolute(p):
			_walk(p, out, 0)
		else:
			out.append(p)
	return out


func _walk(dir: String, out: PackedStringArray, depth: int) -> void:
	if depth > 6:
		return
	for f in DirAccess.get_files_at(dir):
		if AudioDecoder.is_playable(f) or f.get_extension().to_lower() in AudioDecoder.KNOWN_UNSUPPORTED:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out, depth + 1)


# ------------------------------------------------------------- the list

func find(id: String) -> Song:
	for s in songs:
		if s.id == id:
			return s
	return null


## Songs whose title, artist or album contains `text` (case-insensitive).
func search(text: String) -> Array[Song]:
	var q := text.strip_edges().to_lower()
	if q.is_empty():
		return songs.duplicate()
	var out: Array[Song] = []
	for s in songs:
		if q in s.display_title().to_lower() or q in s.artist.to_lower() or q in s.album.to_lower():
			out.append(s)
	return out


## Removes the song and the library's copy of its audio (never the original).
func remove(song: Song) -> void:
	if not songs.has(song):
		return
	songs.erase(song)
	for p: String in [song.file_path, _peaks_file(song)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	save_library()
	songs_changed.emit()


## Call after changing a song's fields (tempo, show name...).
func update(song: Song) -> void:
	save_library()
	song_updated.emit(song)


# -------------------------------------------------------------- waveform

## Load the cached waveform, or start working it out in the background.
## song_updated fires when it's ready.
func ensure_peaks(song: Song) -> void:
	if not song.peaks.is_empty() or song.analysing:
		return
	var cache := _peaks_file(song)
	if FileAccess.file_exists(cache):
		var f := FileAccess.open(cache, FileAccess.READ)
		var data: Variant = f.get_var() if f else null
		if data is PackedFloat32Array and not (data as PackedFloat32Array).is_empty():
			song.peaks = data
			song_updated.emit(song)
			return
	song.analysing = true
	var path := song.file_path
	var task_id := WorkerThreadPool.add_task(func() -> void:
		var peaks := AudioDecoder.compute_peaks(AudioDecoder.load_stream(path), Song.PEAKS_PER_SECOND)
		_on_peaks_ready.call_deferred(song, peaks))
	_tasks[task_id] = song


func _on_peaks_ready(song: Song, peaks: PackedFloat32Array) -> void:
	for task_id: int in _tasks.keys():
		if _tasks[task_id] == song:
			WorkerThreadPool.wait_for_task_completion(task_id)
			_tasks.erase(task_id)
	song.analysing = false
	song.peaks = peaks
	if songs.has(song) and not peaks.is_empty():
		var f := FileAccess.open(_peaks_file(song), FileAccess.WRITE)
		if f:
			f.store_var(peaks)
	if songs.has(song):
		guess_first_beat(song)
	song_updated.emit(song)


## Guess where the first downbeat is from the waveform, unless you set it by
## hand. Needs the tempo and the waveform. Returns true if it changed.
func guess_first_beat(song: Song) -> bool:
	if song.first_beat_set or song.bpm <= 0.0 or song.peaks.is_empty():
		return false
	var t := BeatGrid.estimate_first_beat(song.peaks, Song.PEAKS_PER_SECOND, song.bpm)
	if t < 0.0 or is_equal_approx(t, song.first_beat):
		return false
	song.first_beat = t
	save_library()
	return true


# ----------------------------------------------------------- save / load

func save_library() -> void:
	DirAccess.make_dir_recursive_absolute(root_dir)
	var list: Array = []
	for s in songs:
		list.append(s.to_dict())
	var tmp := library_file() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SongLibrary: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"version": 1, "songs": list}, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, library_file())


func load_library() -> void:
	_loaded = true
	songs.clear()
	if FileAccess.file_exists(library_file()):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(library_file()))
		if data is Dictionary:
			for d: Variant in (data as Dictionary).get("songs", []):
				if d is Dictionary:
					var s := Song.from_dict(d)
					if FileAccess.file_exists(s.file_path):
						songs.append(s)
	songs_changed.emit()
