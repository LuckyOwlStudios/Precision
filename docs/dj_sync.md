# Following the DJ

The goal: whoever is DJing, the lights follow them. A new track loads that song's show,
pause pauses it, play carries on from the same spot, and the lights stay on the beat even
when the DJ moves the pitch fader or jumps around the track.

To do that the app needs four things from the DJ's setup, live: **which track** is playing,
**playing or paused**, **where in the track** they are, and the **tempo/beat**.

## What each kind of DJ setup can tell us (researched Nov 2026)

| Link | DJ setups | Which track | Play / pause | Position | Tempo + beat | Needs |
|---|---|---|---|---|---|---|
| **VirtualDJ Network Control + OS2L** | VirtualDJ on a laptop, any controller | Yes | Yes | Yes | Yes (OS2L sends every beat) | VirtualDJ Pro licence for Network Control. Nothing extra to install. **Built first.** |
| Pro DJ Link (via the open-source beat-link library) | Pioneer/AlphaTheta CDJs and XDJs on a network cable (what most clubs have) | Yes | Yes | Yes | Yes, very precise | Real CDJs, and a small Java helper program. Can't see rekordbox running on a laptop. |
| rekordbox on a laptop | rekordbox + controller | Only to SoundSwitch | | | Tempo via Ableton Link | Since Sept 2026 rekordbox and the PRO DJ LINK Bridge app talk to SoundSwitch, but through a private link, not an open one. |
| StageLinQ | Denon DJ Prime / SC6000 players and mixers (Engine DJ) | Yes | Yes | Beat position | Yes | Denon hardware. Open-source versions exist; could be written directly in the app. |
| Ableton Link / MIDI clock | Traktor, Serato, rekordbox, Ableton, most apps | No | Start/stop only | Beat phase only | Yes | Nothing, but it can't say which song is playing, so it can't pick a show on its own. |
| Listening to the audio (microphone / line in) | Anything, even a phone | No (could be added later by recognising songs from your library) | Silence detection | No | Yes, roughly | A sound input. Good fallback for busking, not for pre-programmed shows. |

## Recommendation

1. **VirtualDJ first** (done in this change). It is the only option that gives all four
   things from a laptop with no extra hardware, and both of its links are official, built-in
   and simple. If you haven't picked DJ software yet, VirtualDJ is the easiest one to make
   this work with today.
2. **Pro DJ Link next**, for when you play on club CDJs. It needs a small helper program
   (beat-link is Java) that forwards what it hears to the app; the app side plugs into the
   same pieces built here.
3. **StageLinQ** if you or your friends use Denon gear.
4. **Ableton Link and audio listening** as fallbacks that keep the lights on the beat when
   the track can't be identified (busking mode).

Serato and Traktor don't offer an open way to read the track and position live, so they'd
be limited to tempo-only (Ableton Link / MIDI clock).

## How it fits together (djsync/)

| Script | What it does |
|---|---|
| `DJSyncSource` | The shape every link fills in: track changed, play/pause, position, beats. Turns late, jittery network readings into a smooth clock the lights can follow every frame (small drift is eased out, real jumps snap). |
| `SimulatedDJSource` | A pretend DJ deck inside the app, so you can try everything with no software or hardware. It deliberately reports late and with jitter, like a network. |
| `VirtualDJSource` | Talks to VirtualDJ's Network Control plugin (reads ~20 times a second) and, optionally, listens for OS2L beats. |
| `OS2LListener` | Receives OS2L beat/button messages. |
| `TrackMatcher` | Finds the DJ's track in your song library: same file, same file name, same artist and title, then looser matches (ignores "(Original Mix)", "feat." and collaborator order). Never guesses between two songs. |
| `DJSync` | The glue: on a new track it loads the matching song and show; while it's on, the DJ's deck is the clock for the timeline and the app plays no audio of its own. |

The DMX code (addons/lucky_dmx) doesn't know any of this exists, and the links don't know
about shows.

## Trying it

* **Simulator:** open the **DJ** tab on the right, choose *Simulator*, pick a song from your
  library, press *Load* then *Play*. Pause, scrub and move the pitch: the timeline follows.
* **VirtualDJ:** in VirtualDJ go to Settings > Extensions > Effects > Other, enable
  *Network Control*, set it as an Auto-Start master effect and note its port. In the DJ tab
  choose *VirtualDJ* and enter that port. For beat-exact timing also set VirtualDJ's option
  `os2lDirectIp` to `127.0.0.1:9996`.
* **Light offset:** if the lights look a touch late (DMX interfaces and some fixtures add a
  few milliseconds), raise *Light offset* until they hit with the kick.

## Tests

```
godot --headless --path . --script res://tests/djsync_test.gd
python3 tests/fake_virtualdj.py & godot --headless --path . --script res://tests/djsync_test.gd -- vdj
```

The second line runs the VirtualDJ link against a stand-in for VirtualDJ that answers the
same questions.

## Not checked yet

The VirtualDJ link has only been tested against that stand-in, not real VirtualDJ. The
command names come from VirtualDJ's documentation and an open-source app that uses the same
plugin; `get_activedeck`, `get_songlength` and `get_position` should be confirmed on a real
copy, as should the `os2lDirectIp` setting name.

## Starting on the downbeat

Each song stores where its first beat is (`Song.beat_offset`, set with **First beat here** on the timeline). The ruler grid, bar numbers and snapping start there, so clips snapped to the grid start exactly on the downbeat while the DJ's deck plays the song.

When a song's waveform is ready and its BPM is known, the app guesses the first beat from the first loud hit and the beat phase (good to about 20 ms). A hand-set first beat is never overwritten. Ctrl+K "Find first beat automatically" guesses again (undoable).

Test with VirtualDJ: import a song with a known BPM, wait for the waveform, check the cyan first-beat flag sits on the first kick (fix it with **First beat here** if not), then turn on DJ sync, load the song on a deck and play from the start: the first clip snapped to bar 1 should fire on the first kick.
