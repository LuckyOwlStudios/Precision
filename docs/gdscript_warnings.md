# GDScript warnings: why they happened and how to avoid them

The Godot debugger's Errors tab used to show 22 entries every time Precision
started. None were crashes: they were all GDScript warnings, raised when each
script is compiled. They were fixed in the code (not silenced with
`@warning_ignore`), and this page records why each kind appeared so new code
doesn't bring them back. Keep the Errors tab at zero: a real error is easy to
miss among twenty warnings.

## The kinds we had, and the fix for each

### INTEGER_DIVISION: "Integer division. Decimal part will be discarded."

**Why:** dividing one `int` by another (`t / 60`, `RIM_RAYS / 2`,
`i / COLUMNS`) drops the fraction. Godot warns because that is often a bug.
Ours were all on purpose (minutes from seconds, grid rows from an index).
Dividing two `Vector2i`s warns too.

**Fix:** say the rounding out loud: `floori(t / 60.0)`,
`floori(i / float(COLUMNS))`. Use `%` for the remainder as before. Don't
"fix" it by making one side a float and storing the result in an `int`
variable: that is a narrowing conversion, a different warning.

### SHADOWED_VARIABLE / SHADOWED_VARIABLE_BASE_CLASS / SHADOWED_GLOBAL_IDENTIFIER

**Why:** a parameter or local variable used a name that already means
something: a function in the same class (`save`, `fixtures`,
`visible_beats`), a member variable (`look`), something from the base class
(`name` on a Node, `hidden` on a CanvasItem), or a built-in function
(`snapped`, `round`). Inside that function the old meaning is hidden, which
is how "why is `name` empty?" bugs start.

**Fix:** pick a name that says what this one is: `save_data`, `targets`,
`span`, `editing`, `new_name`, `is_hidden`, `slid`, `snap`, `decoded`.
Common traps on a Node or Control: `name`, `visible`, `hidden`, `show`,
`hide`, `size`, `position`, `scale`, `owner`. Built-ins: `round`, `snapped`,
`clamp`, `min`, `max`, `abs`, `sign`, `range`, `str`.

### INCOMPATIBLE_TERNARY: "Values of the ternary operator are not mutually compatible."

**Why:** `a if cond else b` where `a` and `b` have different types, for
example `roundi(v) if strobe else clampf(v, 0, 1)` (int vs float), or
`box if any else null` (AABB vs null). The result's type can't be known.

**Fix:** use a plain `if`/`else` that assigns or returns each case, or make
both sides the same type (`str(x) if x else "none"`).

### STANDALONE_TERNARY

**Why:** a ternary used as a statement (`view.key(K) if ok else _key(K)`),
so its value is thrown away.

**Fix:** write it as an `if`/`else` statement, or drop the branch that can't
happen.

### UNUSED_SIGNAL: "The signal ... is declared but never explicitly used in the class."

**Why:** `StudioContext` declared `delete_requested`, `duplicate_requested`
and `group_rename_requested`, but only other scripts emitted them
(`ctx.delete_requested.emit()`). Godot only counts uses inside the class
that declares the signal.

**Fix:** the class that owns a signal raises it. Give it a small method
(`ctx.request_delete()`, `ctx.request_duplicate()`,
`ctx.request_group_rename(g)`) and call that from elsewhere. This also keeps
one place to put logging or checks later.

### UNUSED_PARAMETER / UNUSED_VARIABLE

**Why:** a parameter kept "for later" (`base` in `LedRingPreview.pattern`),
or a local left behind after the code that used it was removed
(`centre_hit` in the drafting overlay, which also cost a wasted raycast per
fixture per redraw).

**Fix:** delete it. Add the parameter back when the code that needs it
arrives. Only prefix with `_` when a signature is fixed by something else
(an overridden virtual like `_process(_delta)`, or a signal callback).

### CONFUSABLE_LOCAL_DECLARATION

**Why:** a variable declared inside a loop or `if` with the same name as one
declared later in the enclosing block (`xf` in a `for` loop and again after
it).

**Fix:** give the later one its own name.

### INT_AS_ENUM_WITHOUT_CAST

**Why:** passing a bare number where an enum is expected
(`set_workspace(0)`).

**Fix:** use the enum value (`StudioContext.Workspace.STAGE`).

### REDUNDANT_AWAIT

**Why:** `await` on a function that never awaits anything, so it isn't a
coroutine.

**Fix:** call it without `await`. Careful the other way round: a function
that does contain `await` must still be awaited, or the caller runs on
before it finishes.

### "Cannot infer the type of X because the value doesn't have a set type" (a parse error)

**Why:** `var x := something_untyped` (a property on a `Variant`, or a
function with no return type). This one is not a warning: the script fails
to load. `tests/effects_test.gd` didn't load at all because of it.

**Fix:** give the type: `var x: float = ...`, or give the function a return
type.

## Checking

Run the app from the editor and look at Debugger > Errors: it should be
empty after startup. Warnings only show for scripts that have been loaded,
so also open any script you changed in the script editor, which reports its
warnings in the bar at the bottom.
