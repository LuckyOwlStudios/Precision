class_name UIPalette
extends RefCounted
## Every colour and size the Precision UI uses, in one place.
## The theme, the panels and the custom-drawn widgets all read from here,
## so a re-skin (or a light theme later) only touches this file.
##
## Rule of thumb: the UI stays near-black graphite with a faint cool-blue tint so the lights themselves are
## the brightest, most colourful thing on screen.

# --- Surfaces (darkest to lightest) ---
const APP_BG := Color("0a0d11")        ## Behind everything, and the 3D void
const SIDE_BG := Color("0f1318")       ## Left and right columns
const CENTER_BG := Color("14181e")     ## Header, timeline, centre surfaces
const RAISED := Color("1b2027")        ## Buttons, inputs, cards
const HOVER := Color("242a33")         ## Hovered rows and buttons
const SELECTED_ROW := Color("28303b")  ## The grey "selected" band
const HAIRLINE := Color("252b34")      ## 1 px rules and borders
const INPUT_BG := Color("0c0f13")

# --- Text ---
const TEXT := Color("e6e9ed")
const TEXT_DIM := Color("8f98a5")      ## Subtitles, secondary info
const TEXT_FAINT := Color("5b6572")    ## Placeholders, disabled, grid labels

# --- Meaning. Use each for its one job only. ---
const ACCENT := Color("ffb547")        ## Amber: selection, focus, primary action
const ACCENT_DIM := Color("ffb547", 0.16)
const LIVE := Color("ff5468")          ## Red: playhead, blackout, anything live
const OK := Color("3ddc97")            ## Green: output healthy
const BEAT := Color("5cc8ff")          ## Cyan: tempo, beat grid, audio

# --- Sizes (4 px grid) ---
const UNIT := 4
const PAD := 12                        ## Inner padding of panels
const COLUMN_PAD := 20                 ## Side column padding, like the reference
const RADIUS := 4
const ROW_HEIGHT := 28
const HEADER_HEIGHT := 56
const FOOTER_HEIGHT := 40

const FONT_SIZE := 13
const FONT_SIZE_SMALL := 11
const FONT_SIZE_SECTION := 15
const FONT_SIZE_TITLE := 22

## UI font: the first one installed wins. Bundle Inter (OFL) later for an
## identical look on every machine.
const UI_FONTS: PackedStringArray = ["Inter", "Open Sans", "Segoe UI", "SF Pro Text", "Helvetica Neue", "Noto Sans", "Arial", "sans-serif"]
## Numbers that change while you watch (DMX values, timecode, BPM).
const MONO_FONTS: PackedStringArray = ["JetBrains Mono", "Cascadia Mono", "SF Mono", "Menlo", "Consolas", "DejaVu Sans Mono", "monospace"]
