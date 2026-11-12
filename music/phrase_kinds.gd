class_name PhraseKinds
extends RefCounted
## The usual sections of a dance track, with a colour each, for the phrase
## markers on the timeline. Names are free text; a name that starts with one
## of these gets its colour, anything else is grey.

const KINDS: Array[String] = ["Intro", "Verse", "Build", "Drop", "Chorus", "Breakdown", "Bridge", "Outro"]

const COLORS := {
	"intro": Color("5cc8ff"),
	"verse": Color("8f98a5"),
	"build": Color("ffb547"),
	"drop": Color("ff5468"),
	"chorus": Color("c77dff"),
	"breakdown": Color("3ddc97"),
	"bridge": Color("ffd166"),
	"outro": Color("5b8def"),
}


static func color_for(phrase_name: String) -> Color:
	var n := phrase_name.strip_edges().to_lower()
	for key: String in COLORS:
		if n.begins_with(key):
			return COLORS[key]
	return Color("8f98a5")
