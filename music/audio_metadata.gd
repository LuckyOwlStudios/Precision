class_name AudioMetadata
extends RefCounted
## Reads title / artist / album / BPM tags from audio files without
## decoding the audio:
##   MP3: ID3v2.2/2.3/2.4 frames, then the old ID3v1 block at the end.
##   OGG: the Vorbis comment header (TITLE=, ARTIST=, ...).
##   WAV: the RIFF LIST/INFO chunk (INAM, IART, IPRD) and an "id3 " chunk.
## Anything missing falls back to the file name ("Artist - Title.mp3").


## Returns {title, artist, album, bpm} with "" / 0.0 for unknown fields.
static func read(path: String) -> Dictionary:
	var tags := {"title": "", "artist": "", "album": "", "bpm": 0.0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		match path.get_extension().to_lower():
			"mp3":
				_read_id3v2(f, 0, tags)
				if str(tags.title).is_empty():
					_read_id3v1(f, tags)
			"ogg", "oga":
				_read_vorbis(f, tags)
			"wav", "wave":
				_read_wav(f, tags)
		f.close()
	_fill_from_filename(path, tags)
	return tags


# ------------------------------------------------------------------- ID3v2

static func _read_id3v2(f: FileAccess, offset: int, tags: Dictionary) -> void:
	f.seek(offset)
	if f.get_length() - offset < 10:
		return
	var head := f.get_buffer(10)
	if head.slice(0, 3).get_string_from_ascii() != "ID3":
		return
	var major := head[3]
	var flags := head[5]
	var size := _syncsafe(head, 6)
	var end := offset + 10 + size
	var pos := offset + 10
	if flags & 0x40 and major >= 3: # extended header: skip it
		f.seek(pos)
		var ext := f.get_buffer(4)
		pos += (_syncsafe(ext, 0) if major == 4 else _be32(ext, 0) + 4)
	var id_len := 3 if major == 2 else 4
	var hdr_len := 6 if major == 2 else 10
	while pos + hdr_len <= end:
		f.seek(pos)
		var fh := f.get_buffer(hdr_len)
		if fh[0] == 0:
			break # padding
		var frame_id := fh.slice(0, id_len).get_string_from_ascii()
		var frame_size: int
		if major == 2:
			frame_size = (fh[3] << 16) | (fh[4] << 8) | fh[5]
		elif major == 4:
			frame_size = _syncsafe(fh, 4)
		else:
			frame_size = _be32(fh, 4)
		pos += hdr_len
		if frame_size <= 0 or pos + frame_size > end:
			break
		var key := ""
		match frame_id:
			"TIT2", "TT2": key = "title"
			"TPE1", "TP1": key = "artist"
			"TALB", "TAL": key = "album"
			"TBPM", "TBP": key = "bpm"
		if not key.is_empty() and frame_size < 4096:
			var text := _id3_text(f.get_buffer(frame_size))
			_set_tag(tags, key, text)
		pos += frame_size


## A text frame: one encoding byte, then the string (maybe several, 0-separated).
static func _id3_text(data: PackedByteArray) -> String:
	if data.is_empty():
		return ""
	var enc := data[0]
	var body := data.slice(1)
	var s := ""
	match enc:
		0: s = _latin1(body)
		1: s = _utf16(body, true)
		2: s = _utf16(body, false)
		_: s = body.get_string_from_utf8()
	var nul := s.find(char(0))
	if nul >= 0:
		s = s.substr(0, nul)
	return s.strip_edges()


static func _read_id3v1(f: FileAccess, tags: Dictionary) -> void:
	if f.get_length() < 128:
		return
	f.seek(f.get_length() - 128)
	var b := f.get_buffer(128)
	if b.slice(0, 3).get_string_from_ascii() != "TAG":
		return
	_set_tag(tags, "title", _latin1(b.slice(3, 33)).strip_edges())
	_set_tag(tags, "artist", _latin1(b.slice(33, 63)).strip_edges())
	_set_tag(tags, "album", _latin1(b.slice(63, 93)).strip_edges())


# ------------------------------------------------------------------ Vorbis

## The comment header is the second Vorbis packet, almost always within the
## first few KB. Search for its signature instead of walking Ogg pages.
static func _read_vorbis(f: FileAccess, tags: Dictionary) -> void:
	var buf := f.get_buffer(mini(f.get_length(), 65536))
	var sig := PackedByteArray([0x03, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73]) # \x03vorbis
	var at := _find(buf, sig)
	if at < 0:
		return
	var p := at + sig.size()
	if p + 4 > buf.size():
		return
	p += 4 + _le32(buf, p) # vendor string
	if p + 4 > buf.size():
		return
	var count := _le32(buf, p)
	p += 4
	for i in mini(count, 256):
		if p + 4 > buf.size():
			return
		var n := _le32(buf, p)
		p += 4
		if n < 0 or p + n > buf.size():
			return
		var entry := buf.slice(p, p + n).get_string_from_utf8()
		p += n
		var eq := entry.find("=")
		if eq <= 0:
			continue
		var value := entry.substr(eq + 1).strip_edges()
		match entry.substr(0, eq).to_upper():
			"TITLE": _set_tag(tags, "title", value)
			"ARTIST": _set_tag(tags, "artist", value)
			"ALBUM": _set_tag(tags, "album", value)
			"BPM", "TEMPO": _set_tag(tags, "bpm", value)


# --------------------------------------------------------------------- WAV

static func _read_wav(f: FileAccess, tags: Dictionary) -> void:
	f.seek(0)
	var riff := f.get_buffer(12)
	if riff.size() < 12 or riff.slice(0, 4).get_string_from_ascii() != "RIFF":
		return
	var pos := 12
	var length := f.get_length()
	while pos + 8 <= length:
		f.seek(pos)
		var ch := f.get_buffer(8)
		var cid := ch.slice(0, 4).get_string_from_ascii()
		var csize := _le32(ch, 4)
		var body := pos + 8
		if cid == "LIST" and csize >= 4 and csize < 1 << 20:
			var data := f.get_buffer(csize)
			if data.slice(0, 4).get_string_from_ascii() == "INFO":
				var p := 4
				while p + 8 <= data.size():
					var sid := data.slice(p, p + 4).get_string_from_ascii()
					var ssize := _le32(data, p + 4)
					var text := data.slice(p + 8, p + 8 + ssize).get_string_from_utf8().strip_edges()
					match sid:
						"INAM": _set_tag(tags, "title", text)
						"IART": _set_tag(tags, "artist", text)
						"IPRD": _set_tag(tags, "album", text)
					p += 8 + ssize + (ssize & 1)
		elif cid.to_lower() == "id3 ":
			_read_id3v2(f, body, tags)
		pos = body + csize + (csize & 1)


# ---------------------------------------------------------------- fallback

## "Artist - Title.mp3" -> both; otherwise the bare name becomes the title.
static func _fill_from_filename(path: String, tags: Dictionary) -> void:
	var base := path.get_file().get_basename().replace("_", " ").strip_edges()
	var parts := base.split(" - ", false, 1)
	if str(tags.title).is_empty():
		tags.title = parts[1].strip_edges() if parts.size() == 2 else base
	if str(tags.artist).is_empty() and parts.size() == 2:
		tags.artist = parts[0].strip_edges()


static func _set_tag(tags: Dictionary, key: String, value: String) -> void:
	if value.is_empty():
		return
	if key == "bpm":
		var v := value.to_float()
		if v >= 30.0 and v <= 300.0 and float(tags.bpm) == 0.0:
			tags.bpm = v
	elif str(tags[key]).is_empty():
		tags[key] = value


# ------------------------------------------------------------------- bytes

static func _syncsafe(b: PackedByteArray, i: int) -> int:
	return ((b[i] & 0x7f) << 21) | ((b[i + 1] & 0x7f) << 14) | ((b[i + 2] & 0x7f) << 7) | (b[i + 3] & 0x7f)


static func _be32(b: PackedByteArray, i: int) -> int:
	return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]


static func _le32(b: PackedByteArray, i: int) -> int:
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)


static func _latin1(b: PackedByteArray) -> String:
	var s := ""
	for c in b:
		if c == 0:
			break
		s += char(c)
	return s


static func _utf16(b: PackedByteArray, has_bom: bool) -> String:
	var little := false # UTF-16BE unless the BOM says otherwise
	var start := 0
	if has_bom and b.size() >= 2:
		if b[0] == 0xff and b[1] == 0xfe:
			little = true
			start = 2
		elif b[0] == 0xfe and b[1] == 0xff:
			start = 2
	var s := ""
	var i := start
	while i + 1 < b.size():
		var unit: int = (b[i] | (b[i + 1] << 8)) if little else ((b[i] << 8) | b[i + 1])
		if unit == 0:
			break
		if unit >= 0xd800 and unit < 0xdc00 and i + 3 < b.size(): # surrogate pair
			var lo: int = (b[i + 2] | (b[i + 3] << 8)) if little else ((b[i + 2] << 8) | b[i + 3])
			unit = 0x10000 + ((unit - 0xd800) << 10) + (lo - 0xdc00)
			i += 2
		s += char(unit)
		i += 2
	return s


static func _find(hay: PackedByteArray, needle: PackedByteArray) -> int:
	var first := needle[0]
	var at := hay.find(first)
	while at >= 0 and at + needle.size() <= hay.size():
		if hay.slice(at, at + needle.size()) == needle:
			return at
		at = hay.find(first, at + 1)
	return -1
