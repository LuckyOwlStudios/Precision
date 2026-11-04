class_name DJSync
extends Node
## Makes the lights follow the DJ. Listens to one DJSyncSource and:
##   * when the DJ starts a different track, finds it in your song library
##     (TrackMatcher) and loads that song and its show onto the timeline;
##   * when they play, pause or stop, the show plays, pauses or stops;
##   * every frame, the timeline's playhead is the DJ's playhead (seeks,
##     cue jumps and pitch changes included).
##
## While following, the app plays no audio itself: the DJ's speakers are the
## sound, we're just the lights. StudioContext asks is_following() and
## position_seconds() each frame.

signal status_changed
signal source_changed(source: DJSyncSource)

enum Kind { OFF, SIMULATOR, VIRTUALDJ }

## Shift the lights earlier (positive) or later (negative), in milliseconds,
## to make up for the delay of the DMX interface, the fixtures or a long
## speaker run. Most rigs want 0 to 40.
@export var light_offset_ms: float = 0.0

var ctx: StudioContext
var kind: Kind = Kind.OFF
var source: DJSyncSource
## The library song for the DJ's current track, or null.
var matched: Song
## How it was matched ("title and artist", "file path"...), for the panel.
var match_how: String = ""


## Switch to a kind of source. `settings` are applied as properties
## (e.g. {"host": "192.168.1.20", "port": 8080}). Returns the new source.
func use(p_kind: Kind, settings: Dictionary = {}) -> DJSyncSource:
	var src: DJSyncSource = null
	match p_kind:
		Kind.SIMULATOR:
			src = SimulatedDJSource.new()
		Kind.VIRTUALDJ:
			src = VirtualDJSource.new()
	if src:
		for key: String in settings:
			src.set(key, settings[key])
	kind = p_kind
	set_source(src)
	return src


func set_source(src: DJSyncSource) -> void:
	if source:
		source.stop()
		for sig: Array in _connections():
			if source.is_connected(sig[0], sig[1]):
				source.disconnect(sig[0], sig[1])
		source.queue_free()
	source = src
	matched = null
	match_how = ""
	if src:
		if src.name.is_empty() or src.name.begins_with("@"):
			src.name = src.source_name.validate_node_name()
		add_child(src)
		for sig: Array in _connections():
			src.connect(sig[0], sig[1])
		src.start()
		if src.track:
			_on_track_changed(src.track)
	elif kind != Kind.OFF:
		kind = Kind.OFF
	if ctx and src == null:
		ctx.playing = false
		ctx.transport_changed.emit()
	source_changed.emit(src)
	status_changed.emit()


func is_following() -> bool:
	return source != null


## The DJ's position in the current track, with the light offset applied.
func position_seconds() -> float:
	if source == null:
		return 0.0
	return source.position_seconds() + light_offset_ms / 1000.0


## The DJ's track isn't in the library; try again (call after importing).
func rematch() -> void:
	if source and source.track:
		_on_track_changed(source.track)


func status_text() -> String:
	if source == null:
		return "Off. The timeline plays on its own."
	return source.status_detail


func _connections() -> Array:
	return [
		["track_changed", _on_track_changed],
		["play_state_changed", _on_play_state_changed],
		["connection_changed", _on_connection_changed],
	]


func _on_track_changed(track: DJTrack) -> void:
	var found := {"song": null, "how": ""}
	if track and ctx:
		found = TrackMatcher.find_with_reason(track, ctx.library.songs)
	matched = found["song"]
	match_how = found["how"]
	if matched and matched.duration > 0.0:
		source.duration_hint = matched.duration
	if ctx:
		# Unknown track: clear the timeline so the last show doesn't carry on
		# over a song it wasn't made for.
		ctx.load_song(matched)
	status_changed.emit()


func _on_play_state_changed(_playing: bool) -> void:
	status_changed.emit()


func _on_connection_changed(_connected: bool, _detail: String) -> void:
	status_changed.emit()
