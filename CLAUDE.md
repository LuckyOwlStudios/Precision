# Notes for Claude sessions

- Keep the Godot debugger's Errors tab at zero. Fix GDScript warnings in the
  code instead of silencing them with `@warning_ignore`. The common ones and
  their fixes are in [docs/gdscript_warnings.md](docs/gdscript_warnings.md):
  integer division (`floori(a / float(b))`), names that shadow a function,
  member, base-class property or built-in, mixed-type ternaries, signals
  emitted only from outside their class, and leftover unused variables.
