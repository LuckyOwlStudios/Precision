class_name VirtualDJSource
extends DJSyncSource
## Follows VirtualDJ running on this computer (or another on the network).
##
## Two links, both built into VirtualDJ:
##   * Network Control plugin (HTTP): which deck is live, the track's title,
##     artist, file and length, play/pause, position and tempo. Polled many
##     times a second. Needs VirtualDJ 2023+ with a Pro licence; enable it in
##     Settings > Extensions > Effects > Other > "Network Control", then pick
##     it as an Auto-Start master effect and set its port (and optional
##     password) with the cog.
##   * OS2L (optional): a message on every beat, so the lights land exactly on
##     the beat. See OS2LListener for the one setting to change in VirtualDJ.
##
## The "live" deck is VirtualDJ's active deck (the one the crossfader and
## automix treat as leading), so when the DJ mixes into the next track its
## show takes over as soon as VirtualDJ makes that deck the active one.

@export var host: String = "127.0.0.1"
@export var port: int = 80
## The password set in the Network Control plugin, if any.
@export var password: String = ""
## Position/play-state reads per second.
@export var poll_hz: float = 20.0
## Also listen for OS2L beats.
@export var use_os2l: bool = true
@export var os2l_port: int = 9996

## Seconds between full track-info reads while nothing changes.
const INFO_INTERVAL := 1.0
## Give up on a request after this long.
const TIMEOUT := 1.5
## Busy-wait this long for a reply before yielding a frame. VirtualDJ on the
## same computer answers in about a millisecond, so this keeps each reading
## fresh without stalling the frame.
const SPIN_USEC := 3000

var os2l: OS2LListener
var active_deck: int = 0

var _http := HTTPClient.new()
var _running := false
var _busy := false
var _last_info_us := 0
var _info_now := false
var _deck_duration := 0.0
var _abs_bpm := 0.0


func _init() -> void:
	source_name = "VirtualDJ"


func start() -> void:
	if _running:
		return
	_running = true
	if use_os2l:
		os2l = OS2LListener.new()
		os2l.name = "OS2L"
		os2l.port = os2l_port
		add_child(os2l)
		os2l.listen()
		os2l.beat_received.connect(_on_os2l_beat)
	_set_connected(false, "Looking for VirtualDJ on %s:%d..." % [host, port])
	_run()


func stop() -> void:
	_running = false
	_http.close()
	if os2l:
		os2l.queue_free()
		os2l = null
	super()


func _exit_tree() -> void:
	_running = false
	_http.close()


# -------------------------------------------------------------- the loop

func _run() -> void:
	while _running and is_inside_tree():
		var started := Time.get_ticks_usec()
		if await _ensure_connected():
			await _poll_once()
		else:
			await get_tree().create_timer(1.0).timeout # retry gently
			continue
		var wait := 1.0 / maxf(poll_hz, 1.0) - float(Time.get_ticks_usec() - started) / 1_000_000.0
		if wait > 0.0 and _running and is_inside_tree():
			await get_tree().create_timer(wait).timeout


func _poll_once() -> void:
	var deck_raw: Variant = await _query("get_activedeck")
	if deck_raw == null:
		return
	var deck := int(str(deck_raw)) if str(deck_raw).is_valid_int() else 1
	deck = clampi(deck, 1, 8)
	var p := "deck %d " % deck
	var deck_changed := deck != active_deck
	active_deck = deck

	var now := Time.get_ticks_usec()
	if deck_changed or _info_now or now - _last_info_us > int(INFO_INTERVAL * 1_000_000.0):
		_info_now = false
		_last_info_us = now
		if not await _read_track_info(p, deck):
			return

	var playing_raw: Variant = await _query(p + "play")
	if playing_raw == null:
		return
	var is_playing := parse_bool(str(playing_raw)) and track != null

	var bpm_raw: Variant = await _query(p + "get_bpm")
	var heard_bpm := parse_number(str(bpm_raw)) if bpm_raw != null else 0.0
	var pitch_rate := heard_bpm / _abs_bpm if heard_bpm > 0.0 and _abs_bpm > 0.0 else -1.0

	# The position read last, timed on its own, so its age is known.
	var t0 := Time.get_ticks_usec()
	var pos_raw: Variant = await _query(p + "get_position")
	if pos_raw == null:
		return
	var age := float(Time.get_ticks_usec() - t0) / 2_000_000.0
	var fraction := parse_number(str(pos_raw))
	if fraction > 1.0:
		fraction /= 100.0 # some builds answer in percent

	if track == null:
		_set_playing(false)
		return
	if heard_bpm > 0.0:
		_set_bpm(heard_bpm)
	var length := _deck_duration
	if duration_hint > 0.0 and (length <= 0.0 or absf(duration_hint - length) < 2.0):
		length = duration_hint
	var seconds := fraction * length
	if is_playing != playing:
		_report_position(seconds, age if playing else 0.0, pitch_rate)
		_set_playing(is_playing)
	_report_position(seconds, age, pitch_rate)


## Returns false if the connection dropped part-way.
func _read_track_info(p: String, deck: int) -> bool:
	var answers: Array[String] = []
	for q: String in [p + "get_loaded_song 'title'", p + "get_loaded_song 'artist'", p + "get_filepath", p + "get_songlength", p + "get_bpm absolute", p + "loaded", p + "get_time total"]:
		var a: Variant = await _query(q)
		if a == null:
			return false
		answers.append(str(a))
	if not parse_bool(answers[5]) and answers[2].is_empty():
		_deck_duration = 0.0
		_set_track(null)
		return true
	# get_songlength is in seconds with decimals; get_time total may be rounded.
	_deck_duration = parse_duration(answers[3])
	if _deck_duration <= 0.0:
		_deck_duration = parse_duration(answers[6])
	_abs_bpm = parse_number(answers[4])
	_set_track(DJTrack.make(answers[0], answers[1], answers[2], _deck_duration, _abs_bpm, deck))
	return true


func _on_os2l_beat(pos: int, p_bpm: float, change: bool, _strength: float) -> void:
	if change:
		_info_now = true # a new track or a jump: re-read straight away
	_report_beat(pos, p_bpm)


# ------------------------------------------------------------------ HTTP

func _ensure_connected() -> bool:
	_http.poll()
	var st := _http.get_status()
	if st == HTTPClient.STATUS_CONNECTED:
		return true
	if st != HTTPClient.STATUS_CONNECTING and st != HTTPClient.STATUS_RESOLVING:
		_http.close()
		if _http.connect_to_host(host, port) != OK:
			_set_connected(false, "Can't reach %s:%d" % [host, port])
			return false
	var deadline := Time.get_ticks_usec() + int(TIMEOUT * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		_http.poll()
		st = _http.get_status()
		if st == HTTPClient.STATUS_CONNECTED:
			return true
		if st != HTTPClient.STATUS_CONNECTING and st != HTTPClient.STATUS_RESOLVING:
			break
		await get_tree().process_frame
	_http.close()
	_set_connected(false, "VirtualDJ isn't answering on %s:%d. Is the Network Control plugin on?" % [host, port])
	return false


## The answer as a String ("" for VirtualDJ's "error:..." answers), or null
## if the connection failed.
func _query(script: String) -> Variant:
	if _busy:
		return null
	_busy = true
	var answer: Variant = await _request(script)
	_busy = false
	if answer == null:
		_http.close()
		_set_connected(false, "Lost VirtualDJ on %s:%d" % [host, port])
		if playing:
			_set_playing(false)
		return null
	if not connected:
		_set_connected(true, "Connected to VirtualDJ on %s:%d" % [host, port])
	var s := strip_quotes(str(answer))
	return "" if s.begins_with("error") else s


func _request(script: String) -> Variant:
	var url := "/query?script=" + script.uri_encode()
	if not password.is_empty():
		url += "&bearer=" + password.uri_encode()
	var headers := PackedStringArray(["Connection: keep-alive"])
	if _http.request(HTTPClient.METHOD_GET, url, headers) != OK:
		return null
	var deadline := Time.get_ticks_usec() + int(TIMEOUT * 1_000_000.0)
	var spin_until := Time.get_ticks_usec() + SPIN_USEC
	var body := PackedByteArray()
	while Time.get_ticks_usec() < deadline:
		_http.poll()
		var st := _http.get_status()
		match st:
			HTTPClient.STATUS_REQUESTING:
				pass
			HTTPClient.STATUS_BODY:
				var chunk := _http.read_response_body_chunk()
				if not chunk.is_empty():
					body.append_array(chunk)
					continue
			HTTPClient.STATUS_CONNECTED:
				if _http.has_response():
					var code := _http.get_response_code()
					if code == 401 or code == 403:
						_set_connected(false, "VirtualDJ refused the password")
						return null
					return body.get_string_from_utf8() if code < 400 else ""
				return null
			_:
				return null
		if Time.get_ticks_usec() < spin_until:
			OS.delay_usec(100)
		else:
			await get_tree().process_frame
	return null


# --------------------------------------------------------------- parsing

static func parse_bool(raw: String) -> bool:
	return raw.strip_edges().to_lower() in ["true", "yes", "on", "1"]


static func parse_number(raw: String) -> float:
	var t := strip_quotes(raw).replace(",", ".").replace("%", "").strip_edges()
	return t.to_float() if t.is_valid_float() else 0.0


## "243.5", "4:03" or "1:04:03" to seconds. VirtualDJ answers with either.
static func parse_duration(raw: String) -> float:
	var t := strip_quotes(raw).strip_edges()
	if t.is_empty():
		return 0.0
	if t.is_valid_float():
		var n := t.to_float()
		return n / 1000.0 if n > 36000.0 else n # some builds answer in ms
	var parts := t.split(":")
	var total := 0.0
	for part in parts:
		if not part.is_valid_float():
			return 0.0
		total = total * 60.0 + part.to_float()
	return total


static func strip_quotes(raw: String) -> String:
	var t := raw.strip_edges()
	if t.length() >= 2 and ((t.begins_with("\"") and t.ends_with("\"")) or (t.begins_with("'") and t.ends_with("'"))):
		return t.substr(1, t.length() - 2)
	return t
