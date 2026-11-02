# Lucky DMX: fixture control from Godot 4

Open `project.godot` in Godot 4.4+ and press Play.
Controls: **SPACE** = GO next cue, **B** = back, **P** = play/stop timeline, **ESC** = blackout.

## Hooking up your light
1. In `demo/demo.gd`, set `PROFILE_CHANNELS` to your fixture's channel list,
   in order, as shown in its manual for the DMX mode it's set to. Set `START_ADDRESS`
   to the address shown on the fixture.
2. Set `TARGET_IP` to your Art-Net node's IP. Broadcast (255.255.255.255) works for a first test.
3. No hardware yet? Point it at 127.0.0.1 and use a visualizer such as QLC+ (free)
   with an Art-Net input to check the values.

## Pieces (addons/lucky_dmx)
| Script | What it does |
|---|---|
| `ArtNetOutput` | Sends ArtDMX packets over UDP. Subclass `DMXOutput` for sACN or a USB interface. |
| `DMXUniverse` | 512-channel buffer, sent at 40 Hz. |
| `FixtureProfile` | Resource listing a fixture's channels. Save one `.tres` per fixture model. |
| `DMXFixture` | A light. `dimmer`, `color`, `pan`, `tilt` etc. are ordinary properties. Use `set_raw()` for anything else. |
| `CueStack` + `LightCue` | Console-style cue list with fade times. Use `record_cue()` to snapshot the current look. |

## Using the timeline in the editor
Because fixture settings are ordinary properties, an **AnimationPlayer is your timeline**.
Add a DMXFixture node, then keyframe its color and dimmer with the key icon in the
Inspector. Turn on `send_in_editor` on the DMXUniverse and the real light follows as you
scrub. A Call Method track can fire `CueStack.go_to()` at set times.
