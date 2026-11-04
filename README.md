# Lucky DMX: fixture control from Godot 4

Open `project.godot` in Godot 4.4+ and press Play. The editor UI opens (see below).
The original one-light test is still at `demo/demo.tscn` (open it and press F6).
Demo controls: **SPACE** = GO next cue, **B** = back, **P** = play/stop timeline, **ESC** = blackout.

![Lucky DMX editor UI](docs/ui/program.png)

## The editor UI (ui/)
| Area | What it's for |
|---|---|
| Header | Workspaces: **Stage** (place and patch), **Program** (build a song's show), **Live** (run the night). Keys 1/2/3. |
| Now playing band | Transport, tempo, beat dots, **Blackout** (Esc). Its background blends the rig's live colours. |
| Left dock | **Library** (drag a fixture onto the stage, or double-click), **On stage** (patch list), **Songs** (placeholder). |
| Centre | 3D stage. Right drag orbit, middle drag pan, wheel zoom, F frame, left click select, drag to move, Delete to remove. |
| Bottom | Beat-grid timeline: music lane, a lane per fixture, red playhead (Space plays). Clips come next. |
| Right dock | **Inspector** (patch, colour, dimmer, pan/tilt), **Cues** (Record / GO), **DMX** (live 512-channel monitor). |

The UI sends Art-Net to 127.0.0.1 by default so nothing hits the network until you
change `artnet_target` on the `Studio` node in `ui/main/main_window.tscn`.

### Theme
All colours, sizes and fonts live in `ui/theme/ui_palette.gd`. `ui/theme/lucky_theme.gd`
builds a Theme from them, baked to `ui/theme/lucky_dark.tres` (set as the project theme).
After changing the palette, open `ui/theme/bake_theme.gd` and use File > Run, or run
`godot --headless --script res://ui/theme/bake_theme_cli.gd`.
Fonts are looked up on the system (Inter, then Open Sans, Segoe UI, ...); install
[Inter](https://rsms.me/inter/) for the intended look.

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
