# Show files

A show is saved as one JSON file with the extension `.precision`
(File menu or Ctrl+N / Ctrl+O / Ctrl+S / Ctrl+Shift+S). Precision reopens the
show that was open when it was last closed.

## What is in it

| Section     | Order | Owner                      | Holds                                              |
|-------------|-------|----------------------------|----------------------------------------------------|
| `structure` | 10    | `StageView`                | truss, corner boxes, base plates, mirror twins     |
| `rig`       | 20    | `StudioContext` / `RigCodec` | fixtures, profiles, patch, position, look, labels, mirror twins |
| `cues`      | 30    | `StudioContext`            | the cue list                                       |
| `stage`     | 40    | `StudioContext`            | mirror plane                                       |

Not in the file, because they are computer-wide and already saved on their own:
Settings, the song library, the Looks shelf, the Effects shelf and each song's
timeline show (`user://library`).

## Envelope

```json
{ "format": "precision-show", "version": 1, "saved_at": "2026-11-12T19:00:00", "sections": { } }
```

`ShowFile` reads and writes this (the write goes to a temp file first, so a
crash never leaves half a show). A file with a higher `version` than the app
knows is refused with a message. Sections the app doesn't know are kept and
written back, so opening and saving in an older build loses nothing.

## Adding your feature to the file

Don't change the envelope. Register a section where your feature is set up:

```gdscript
ctx.shows.register_section(&"groups",
    func() -> Variant: return _to_data(),         # Save
    func(data: Variant) -> void: _from_data(data), # Open
    func() -> void: _clear(),                     # New, or a file without this section
    30)                                           # load order: lower loads first
```

* `_to_data()` returns a Dictionary/Array. It goes through `ShowCodec.encode`, which
  handles `Color`, `Vector2/3`, `Basis`, `Transform3D` and packed arrays.
* `_from_data(data)` gets the raw JSON: run values through `ShowCodec.decode`
  or `ShowCodec.apply(obj, prop, value)` (JSON numbers are floats; `apply`
  converts to the property's type).
* Refer to fixtures by node name (`Par 3`), like looks, cues and clips do. Load
  after order 20 if you need the fixtures to exist.
* Anything a person can edit should go through `ctx.record(...)` so undo and the
  unsaved-changes dot (`ctx.shows.is_dirty()`) work. For a change that isn't an
  undo step, call `ctx.shows.mark_dirty()`.
* Change the shape of an existing section? Bump `ShowFile.VERSION` and add a
  step to `ShowFile.migrate()`. Adding a new section never needs a bump.
