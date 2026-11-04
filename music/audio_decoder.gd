class_name AudioDecoder
extends RefCounted
## Turns an audio file on disk into something Godot can play, and works out
## its waveform. Godot 4.4+ loads MP3, Ogg Vorbis and WAV at runtime.
## FLAC has no runtime loader in Godot yet, so it is refused with a clear
## reason instead of failing silently.

const PLAYABLE: PackedStringArray = ["mp3", "ogg", "oga", "wav", "wave"]
## Recognised as music, but not playable yet.
const KNOWN_UNSUPPORTED: PackedStringArray = ["flac", "m4a", "aac", "aiff", "aif", "wma", "opus", "alac"]


static func is_playable(path: String) -> bool:
	return path.get_extension().to_lower() in PLAYABLE


## Why a file can't be imported, or "" if it can.
static func unsupported_reason(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext in PLAYABLE:
		return ""
	if ext == "flac":
		return "FLAC isn't supported yet. Export it as WAV (same quality) or MP3 and drop that in."
	if ext in KNOWN_UNSUPPORTED:
		return "%s files aren't supported yet. Use MP3, WAV or OGG." % ext.to_upper()
	return "Not an audio file."


static func load_stream(path: String) -> AudioStream:
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
		"ogg", "oga":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav", "wave":
			stream = AudioStreamWAV.load_from_file(path)
	return stream


## Peak level (0..1, normalised so the loudest moment is 1) for every
## 1/peaks_per_second of the song. Decodes the whole file, so call it from a
## worker thread for long tracks; it does not touch the scene tree.
static func compute_peaks(stream: AudioStream, peaks_per_second: int) -> PackedFloat32Array:
	var peaks := PackedFloat32Array()
	if stream == null or stream.get_length() <= 0.0:
		return peaks
	var playback := stream.instantiate_playback()
	if playback == null:
		return peaks
	# mix_audio() resamples to the audio server's rate.
	var rate := AudioServer.get_mix_rate()
	var per_peak := maxi(1, int(rate / peaks_per_second))
	var count := ceili(stream.get_length() * peaks_per_second)
	peaks.resize(count)
	# Looking at every 4th frame is plenty for a picture and 4x faster in GDScript.
	const STRIDE := 4
	playback.start(0.0)
	var loudest := 0.0
	for i in count:
		var frames := playback.mix_audio(1.0, per_peak)
		var p := 0.0
		var j := 0
		var n := frames.size()
		while j < n:
			var fr := frames[j]
			var a := maxf(absf(fr.x), absf(fr.y))
			if a > p:
				p = a
			j += STRIDE
		peaks[i] = p
		loudest = maxf(loudest, p)
	playback.stop()
	if loudest > 0.0:
		for i in count:
			peaks[i] = peaks[i] / loudest
	return peaks
