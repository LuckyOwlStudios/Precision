class_name TrackMatcher
extends RefCounted
## Finds the library song for whatever the DJ is playing.
##
## DJ software and our library often describe the same file a little
## differently (tags edited in one place, "(Original Mix)" added, different
## folder), so this tries the surest clues first and gets looser:
##   1. Same file path as the one you imported.
##   2. Same file name.
##   3. Same artist and title.
##   4. Same title, if only one song has it.
##   5. The same again with bracketed extras like "(Original Mix)" removed,
##      and with "Artist - Title" read from the file name.
## Returns null rather than guessing between two songs.


## The match, or null.
static func find(track: DJTrack, songs: Array[Song]) -> Song:
	return find_with_reason(track, songs).get("song")


## {"song": Song or null, "how": "file path" / "file name" / ... / ""}
static func find_with_reason(track: DJTrack, songs: Array[Song]) -> Dictionary:
	var none := {"song": null, "how": ""}
	if track == null or songs.is_empty():
		return none

	# 1. Exact path (the DJ is playing the very file you imported).
	if not track.file_path.is_empty():
		var p := _path_key(track.file_path)
		for s in songs:
			if not s.source_path.is_empty() and _path_key(s.source_path) == p:
				return {"song": s, "how": "file path"}

		# 2. File name, wherever it lives.
		var f := track.file_path.replace("\\", "/").get_file().to_lower()
		var hit := _unique(songs.filter(func(s: Song) -> bool:
			return not s.source_path.is_empty() and s.source_path.replace("\\", "/").get_file().to_lower() == f))
		if hit:
			return {"song": hit, "how": "file name"}

	# Candidate (title, artist) readings of the DJ's track.
	var readings: Array[PackedStringArray] = []
	if not track.title.is_empty():
		readings.append(PackedStringArray([track.title, track.artist]))
	if not track.file_path.is_empty():
		var base := track.file_path.replace("\\", "/").get_file().get_basename()
		var dash := base.find(" - ")
		if dash > 0:
			readings.append(PackedStringArray([base.substr(dash + 3), base.substr(0, dash)]))
		readings.append(PackedStringArray([base, ""]))

	for loose: bool in [false, true]:
		for r in readings:
			var title := normalize(r[0], loose)
			var artist := normalize_artist(r[1], loose)
			if title.is_empty():
				continue
			var same_title := songs.filter(func(s: Song) -> bool:
				return normalize(s.display_title(), loose) == title)
			# 3. Title and artist.
			if not artist.is_empty():
				var both := _unique(same_title.filter(func(s: Song) -> bool:
					return normalize_artist(s.artist, loose) == artist))
				if both:
					return {"song": both, "how": "title and artist" + (" (loose)" if loose else "")}
			# 4. Title alone, only if it can't be mistaken.
			var only := _unique(same_title)
			if only:
				return {"song": only, "how": "title" + (" (loose)" if loose else "")}
	return none


## Lowercase, punctuation to spaces, single spaces. `loose` also drops
## anything in brackets and "feat." credits.
static func normalize(text: String, loose: bool = false) -> String:
	var t := text.to_lower()
	if loose:
		t = _strip_brackets(t)
		t = _cut_feat(t)
	var out := ""
	for i in t.length():
		var c := t[i]
		var code := t.unicode_at(i)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code > 127
		out += c if is_alnum else " "
	return " ".join(out.split(" ", false))


## Artists also lose "feat." guests; `loose` ignores the order of
## collaborators ("A & B" = "B and A").
static func normalize_artist(text: String, loose: bool = false) -> String:
	var t := _cut_feat(text.to_lower())
	if not loose:
		return normalize(t)
	for sep: String in [" & ", " and ", " x ", " vs. ", " vs ", " + ", ";", "/"]:
		t = t.replace(sep, ",")
	var parts := PackedStringArray()
	for w in t.split(","):
		var p := normalize(w, true)
		if not p.is_empty():
			parts.append(p)
	parts.sort()
	return " ".join(parts)


static func _path_key(path: String) -> String:
	return path.replace("\\", "/").simplify_path().to_lower()


static func _unique(list: Array) -> Song:
	return list[0] if list.size() == 1 else null


static func _strip_brackets(t: String) -> String:
	var out := ""
	var depth := 0
	for c in t:
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += c
	return out


static func _cut_feat(t: String) -> String:
	for marker: String in [" feat. ", " feat ", " ft. ", " ft ", " featuring "]:
		var i := t.find(marker)
		if i >= 0:
			t = t.substr(0, i)
	return t
