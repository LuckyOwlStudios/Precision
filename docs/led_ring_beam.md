# LED Ring Beam 100W (16ch)

From the "LED Beam Moving Head Light" user manual: 1 x 100 W white LED, a 30 LED RGB ring round the lens,
pan 540 deg, tilt 270 deg, 2.5 deg beam, 15 colours + open, 15 gobos + open, 8 facet prism.
The manual lists **one DMX mode, 16 channels**, so there is one profile (`FixtureCatalog`, "Moving heads").

| Ch | Name in Precision | Manual | Default |
|----|-------------------|--------|---------|
| 1, 2 | `pan`, `pan_fine` | X 0-540 deg, 16 bit | |
| 3, 4 | `tilt`, `tilt_fine` | Y 0-270 deg, 16 bit | |
| 5 | `speed` | XY speed, fast (0) to slow | 0 |
| 6 | `dimmer` | 0-100 % | |
| 7 | `shutter` | 0-3 off, 4-99 sync strobe, 100-149 pulse, 150-199 strobe, 200-250 random, 251-255 on | 255 (open) |
| 8 | `color_wheel` | white, colours 1-13, split colours, 140-255 rainbow spin | 0 |
| 9 | `gobo` | white, gobos 1-15, shake, 190-255 gobo wheel spin | 0 |
| 10 | `prism` | 0-31 out, 32-63 in, 64-255 rotate | 0 |
| 11 | `focus` | linear | 0 |
| 12 | `ring_dimmer` | "Dimmer" | 255 |
| 13 | `ring_shutter` | 0-3 off, 4-255 strobe | 4 |
| 14 | `ring_effect` | 0-51 inner effect, then 52-55 effect 1 ... 252-255 effect 51 | 0 |
| 15 | `ring_speed` | effect speed, slow to fast | 0 |
| 16 | `reset` | 200-205 resets the fixture | 0 |

Not confirmed by the manual (check on the real unit):
- Channels 12 and 13 repeat the names "Dimmer" and "Strobe". They sit next to the ring channels, so they are
  taken to be the ring's own dimmer and strobe (channels 6 and 7 being the beam's). The preview dims the
  ring with channel 12 and ignores 13.
- Channel 7 is called `shutter`, not `strobe`: on this fixture 0 means dark, but the app's strobe slider starts at 0.
  Strobe and the colour wheel, gobo, prism, focus and ring channels have no controls yet and send their default.

## The ring
The ring has **no per-LED DMX channels**: only an effect number and a speed. The 3D model still draws 30
individual LEDs (`ui/stage/fixtures/models/led_ring_beam.tscn`, one cell each through `pixel_surface.gdshader`;
LED 1 at the top, going clockwise seen from the front). The manual does not say what the 51 effects look
like, so `LedRingPreview` shows stand-in patterns (rainbow, comets, split, colour fade, RGB thirds); each effect
number gives a different one. Replace `LedRingPreview.pattern()` once the real effects are known.

## Model
The manual has no dimensions. The proportions come from its photo, scaled to about 37 cm tall:
head about 14 cm across and 25 cm long, yoke 23.5 cm across, octagonal base about 25 cm wide.
