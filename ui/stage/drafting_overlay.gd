class_name DraftingOverlay
extends Control
## The lighting designer's drawing sheet laid over the orthographic stage views
## (Top plan, Front and Side elevation). It is a 2D layer that sits inside the 3D
## viewport, so what it draws is part of the picture the stage view exports.
##   Grid and rulers   metres, with a step that follows the zoom; a scale bar
##   Fixture labels    name, DMX universe and address, trim height
##   Trim heights      dimension line from the floor up to each fixture (elevations)
##   Beam coverage     where each beam lands: its footprint on the plan, its cone
##                     and throw distance in an elevation
##   Measure           click two points (fixtures snap) for a distance
## Pure drawing and maths; StageView owns the camera and all the input.

enum Kind { NONE, PLAN, FRONT, SIDE }

const MINOR_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0]
const MAJOR_STEPS: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0]
const BAR_STEPS: Array[float] = [0.5, 1.0, 2.0, 5.0, 10.0]
const MIN_MINOR_PX := 14.0
const MIN_MAJOR_PX := 64.0
const FONT_SIZE := 12
const SMALL_FONT_SIZE := 11
const RIM_RAYS := 20 ## rays round the beam's edge, to find where it lands
const SNAP_PX := 12.0 ## measuring snaps to a fixture this close on screen
const GRID_SNAP := 0.25 ## metres, same as the move gizmo's snapping
const MARGIN := 16.0

var camera: Camera3D
var ctx: StudioContext
var visuals: Dictionary = {} ## DMXFixture -> StageFixture3D (the stage view's own map)
var surfaces: Array[StageRoom.Surface] = []

var kind := Kind.NONE:
	set(value):
		kind = value
		visible = kind != Kind.NONE
		_measure.clear()
		queue_redraw()
var show_grid := true:
	set(value):
		show_grid = value
		queue_redraw()
var show_labels := true:
	set(value):
		show_labels = value
		queue_redraw()
var show_beams := true:
	set(value):
		show_beams = value
		queue_redraw()
## Clicks place measuring points. Turning it off clears the measurement.
var measuring := false:
	set(value):
		measuring = value
		if not measuring:
			_measure.clear()
		queue_redraw()
## While true the sheet draws its title block and hides the cursor readout.
var exporting := false
## Cursor in this layer's pixels, (-1, -1) when it is outside.
var cursor := Vector2(-1, -1)

var _measure: Array[Vector3] = [] ## zero, one or two points
var _beams: Dictionary = {} ## DMXFixture -> {key, rim, centre, centre_hit}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw() # moving heads and live edits show as they happen


# ---------------------------------------------------------------- the view's maths

func _ortho() -> bool:
	return camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL


func _h() -> Vector3:
	return camera.global_basis.x.normalized() ## world direction of screen right


func _v() -> Vector3:
	return camera.global_basis.y.normalized() ## world direction of screen up


func _px_per_m() -> float:
	return maxf(size.y, 1.0) / maxf(camera.size, 0.01)


## A point on screen as a world position, taken on the plane through the origin
## square to the view: plan points are on the floor, elevations on the centre line.
func point_at(screen: Vector2) -> Vector3:
	var dir := camera.project_ray_normal(screen)
	var hit: Variant = Plane(dir, 0.0).intersects_ray(camera.project_ray_origin(screen), dir)
	return hit if hit != null else Vector3.ZERO


## Where a click lands for measuring: on a fixture's mounting point if one is
## close, else the cursor point, rounded to the grid when `snap` is on.
func snap_point(screen: Vector2, snap: bool) -> Vector3:
	var best := INF
	var found := Vector3.ZERO
	for fx: DMXFixture in visuals:
		if not is_instance_valid(fx):
			continue
		var m := StudioContext.fixture_transform(fx).origin
		var d := camera.unproject_position(m).distance_to(screen)
		if d < SNAP_PX and d < best:
			best = d
			found = _flatten(m)
	if best < INF:
		return found
	var p := point_at(screen)
	if snap:
		var h := _h()
		var v := _v()
		var a := snappedf(p.dot(h), GRID_SNAP)
		var b := snappedf(p.dot(v), GRID_SNAP)
		return h * a + v * b
	return p


## A world point with the depth coordinate (the one square to this view) zeroed.
func _flatten(p: Vector3) -> Vector3:
	return _h() * p.dot(_h()) + _v() * p.dot(_v())


func _s(a: float, b: float) -> Vector2:
	return camera.unproject_position(_h() * a + _v() * b)


## One click while measuring: first and second point, a third starts again.
func measure_click(screen: Vector2, snap: bool) -> void:
	if _measure.size() >= 2:
		_measure.clear()
	_measure.append(snap_point(screen, snap))
	queue_redraw()


func has_measurement() -> bool:
	return not _measure.is_empty()


func clear_measurement() -> void:
	_measure.clear()
	queue_redraw()


## Smallest step in `steps` that is at least `at_least`, the biggest if none is.
static func pick_step(steps: Array[float], at_least: float) -> float:
	for s in steps:
		if s >= at_least:
			return s
	return steps[steps.size() - 1]


## Name of the current view, for the title block and file names.
func view_name() -> String:
	match kind:
		Kind.PLAN:
			return "Plan"
		Kind.FRONT:
			return "Front elevation"
		Kind.SIDE:
			return "Side elevation"
	return ""


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if kind == Kind.NONE or not _ortho():
		return
	if show_grid:
		_draw_grid()
	if kind == Kind.PLAN:
		_draw_captions()
	var fixtures := _fixtures()
	if show_beams:
		for fx in fixtures:
			_draw_beam(fx)
	_draw_fixtures(fixtures)
	_draw_measure()
	_draw_scale_bar()
	if exporting:
		_draw_title_block(fixtures.size())
	else:
		_draw_readout()


func _fixtures() -> Array[DMXFixture]:
	var list: Array[DMXFixture] = []
	for fx: DMXFixture in visuals:
		if is_instance_valid(fx) and is_instance_valid(visuals[fx]):
			list.append(fx)
	return list


func _text(pos: Vector2, text: String, color: Color, font_size := FONT_SIZE) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.02, 0.024, 0.031, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _text_width(text: String, font_size := FONT_SIZE) -> float:
	return get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _draw_grid() -> void:
	var ppm := _px_per_m()
	var minor := pick_step(MINOR_STEPS, MIN_MINOR_PX / ppm)
	var major := minor
	for m in MAJOR_STEPS:
		if m >= minor and m * ppm >= MIN_MAJOR_PX and _multiple(m, minor):
			major = m
			break
	var h := _h()
	var v := _v()
	var p0 := point_at(Vector2.ZERO)
	var p1 := point_at(size)
	var a_lo := minf(p0.dot(h), p1.dot(h))
	var a_hi := maxf(p0.dot(h), p1.dot(h))
	var b_lo := minf(p0.dot(v), p1.dot(v))
	var b_hi := maxf(p0.dot(v), p1.dot(v))
	var minor_color := Color(1, 1, 1, 0.045)
	var major_color := Color(1, 1, 1, 0.11)
	var axis_color := Color(UIPalette.ACCENT, 0.45)
	for i in range(ceili(a_lo / minor), floori(a_hi / minor) + 1):
		var a := i * minor
		var is_major := _multiple(a, major)
		var x := _s(a, b_lo).x
		var c := axis_color if i == 0 else (major_color if is_major else minor_color)
		draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
		if is_major:
			draw_line(Vector2(x, 0), Vector2(x, 6), UIPalette.TEXT_FAINT, 1.0)
			_text(Vector2(x + 3, 11), _metres(a), UIPalette.TEXT_DIM, SMALL_FONT_SIZE)
	for j in range(ceili(b_lo / minor), floori(b_hi / minor) + 1):
		var b := j * minor
		var is_major := _multiple(b, major)
		var y := _s(a_lo, b).y
		var c := axis_color if j == 0 else (major_color if is_major else minor_color)
		draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
		if is_major:
			draw_line(Vector2(0, y), Vector2(6, y), UIPalette.TEXT_FAINT, 1.0)
			if y > 66.0: # not under the view buttons
				_text(Vector2(9, y - 3), _metres(-b if kind == Kind.PLAN else b), UIPalette.TEXT_DIM, SMALL_FONT_SIZE)


static func _multiple(value: float, step: float) -> bool:
	var n := value / step
	return absf(n - roundf(n)) < 0.001


static func _metres(value: float) -> String:
	return String.num(snappedf(value, 0.01), 2)


## Which way is the back of the stage and which way the audience, on the plan.
func _draw_captions() -> void:
	var top := Vector2(size.x * 0.5, 54.0)
	var bottom := Vector2(size.x * 0.5, size.y - 50.0)
	var up := "STAGE BACK"
	var down := "AUDIENCE"
	_text(top - Vector2(_text_width(up) * 0.5, 0), up, UIPalette.TEXT_FAINT)
	_text(bottom - Vector2(_text_width(down) * 0.5, 0), down, UIPalette.TEXT_FAINT)


func _fixture_color(fx: DMXFixture) -> Color:
	var c := fx.color
	if c.get_luminance() < 0.15:
		return Color.WHITE # a black or blacked-out light still has a beam on the plot
	return Color(c, 1.0)


## Where a fixture's beam lands, worked out only when it moves or turns.
func _beam_of(fx: DMXFixture) -> Dictionary:
	var v: StageFixture3D = visuals[fx]
	var origin := v.beam_origin()
	var dir := v.beam_dir()
	var half := deg_to_rad(v.beam_half_angle())
	var reach := v.beam_length() ## the drawn beam fades out here, wall or not
	var key := [origin, dir, half, reach]
	var cached: Dictionary = _beams.get(fx, {})
	if cached.get("key") == key:
		return cached
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var u := dir.cross(up).normalized()
	var w := dir.cross(u).normalized()
	var rim := PackedVector3Array()
	for i in RIM_RAYS:
		var t := TAU * i / RIM_RAYS
		var d := (dir * cos(half) + (u * cos(t) + w * sin(t)) * sin(half)).normalized()
		rim.append(_land(origin, d, reach))
	var centre_hit := StageRoom.raycast(surfaces, origin, dir)
	var result := {
		"key": key,
		"origin": origin,
		"rim": rim,
		"centre": _land(origin, dir, reach),
	}
	_beams[fx] = result
	return result


## Where a ray from a lens ends: the first surface it meets, or `reach` metres out.
func _land(origin: Vector3, dir: Vector3, reach: float) -> Vector3:
	var hit := StageRoom.raycast(surfaces, origin, dir)
	if hit and origin.distance_to(hit.position) <= reach:
		return hit.position
	return origin + dir * reach


func _draw_beam(fx: DMXFixture) -> void:
	var beam := _beam_of(fx)
	var origin: Vector3 = beam["origin"]
	var rim: PackedVector3Array = beam["rim"]
	var c := _fixture_color(fx)
	var chosen := fx == ctx.selected if ctx else false
	var points := PackedVector2Array([camera.unproject_position(origin)])
	for p in rim:
		points.append(camera.unproject_position(p))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() < 4:
		return
	draw_colored_polygon(hull, Color(c, 0.24 if chosen else 0.12))
	draw_polyline(hull, Color(UIPalette.ACCENT if chosen else c, 0.9 if chosen else 0.55), 1.5, true)
	var centre: Vector3 = beam["centre"]
	var from := camera.unproject_position(origin)
	var to := camera.unproject_position(centre)
	draw_dashed_line(from, to, Color(c, 0.6), 1.0, 5.0)
	draw_line(to + Vector2(-4, 0), to + Vector2(4, 0), Color(c, 0.9), 1.0)
	draw_line(to + Vector2(0, -4), to + Vector2(0, 4), Color(c, 0.9), 1.0)
	if not show_labels:
		return
	if kind == Kind.PLAN:
		var width := 0.0
		for i in RIM_RAYS / 2:
			width = maxf(width, rim[i].distance_to(rim[i + RIM_RAYS / 2]))
		var tag := "Ø %s m" % _metres(width) # centred above where it lands, clear of the label below the fixture
		_text(to + Vector2(-_text_width(tag, SMALL_FONT_SIZE) * 0.5, -10.0), tag, Color(c, 0.95), SMALL_FONT_SIZE)
	else:
		var mid := from.lerp(to, 0.62)
		_text(mid + Vector2(6, 0), "%s m throw" % _metres(origin.distance_to(centre)), Color(c, 0.95), SMALL_FONT_SIZE)


func _draw_fixtures(fixtures: Array[DMXFixture]) -> void:
	for fx in fixtures:
		var v: StageFixture3D = visuals[fx]
		var chosen := fx == ctx.selected if ctx else false
		var at := camera.unproject_position(v.center())
		var ring := UIPalette.ACCENT if chosen else UIPalette.TEXT
		draw_circle(at, 4.0, Color(_fixture_color(fx), 0.95))
		draw_arc(at, 5.5, 0.0, TAU, 20, ring, 1.5 if chosen else 1.0, true)
		var mount := StudioContext.fixture_transform(fx).origin
		if kind != Kind.PLAN and mount.y > 0.05:
			var top := camera.unproject_position(mount)
			var bottom := camera.unproject_position(Vector3(mount.x, 0.0, mount.z))
			draw_dashed_line(top, bottom, Color(UIPalette.TEXT_DIM, 0.55), 1.0, 4.0)
			draw_line(bottom + Vector2(-5, 0), bottom + Vector2(5, 0), Color(UIPalette.TEXT_DIM, 0.8), 1.0)
			var tag := "%s m" % _metres(mount.y)
			_text(Vector2(top.x - _text_width(tag, SMALL_FONT_SIZE) - 6.0, top.y + (bottom.y - top.y) * 0.3 + 4.0), tag, UIPalette.TEXT_DIM, SMALL_FONT_SIZE)
		if not show_labels:
			continue
		var lines: Array[String] = [StudioContext.display_name(fx), _address_of(fx)]
		if kind == Kind.PLAN:
			lines.append("h %s m" % _metres(mount.y))
		# Always centred just below the dot, so fixtures in a row have labels in a row.
		var line_h := float(FONT_SIZE) + 2.0
		var y := at.y + 18.0
		for l in lines.size():
			var first := l == 0
			_text(Vector2(at.x - _text_width(lines[l], FONT_SIZE if first else SMALL_FONT_SIZE) * 0.5, y + line_h * l),
				lines[l], ring if first else UIPalette.TEXT_DIM, FONT_SIZE if first else SMALL_FONT_SIZE)


func _address_of(fx: DMXFixture) -> String:
	var uni := ctx.universe.universe_id + 1 if ctx and ctx.universe else 1
	return "U%d · %03d" % [uni, fx.start_address]


func _draw_measure() -> void:
	if _measure.is_empty():
		return
	var h := _h()
	var v := _v()
	var a := _measure[0]
	var b: Vector3
	var live := _measure.size() < 2
	if live:
		b = snap_point(cursor, true) if cursor.x >= 0.0 else a
	else:
		b = _measure[1]
	var sa := camera.unproject_position(a)
	var sb := camera.unproject_position(b)
	var c := UIPalette.ACCENT
	draw_line(sa, sb, c, 2.0, true)
	draw_circle(sa, 4.0, c)
	draw_circle(sb, 4.0, c)
	var dx := absf((b - a).dot(h))
	var dy := absf((b - a).dot(v))
	var label := "%s m" % _metres((b - a).length())
	var detail := "%s across · %s %s" % [_metres(dx), _metres(dy), "deep" if kind == Kind.PLAN else "high"]
	var mid := (sa + sb) * 0.5
	_text(mid + Vector2(10, -8), label, c)
	if dx > 0.005 and dy > 0.005:
		var corner := camera.unproject_position(a + h * (b - a).dot(h))
		draw_dashed_line(sa, corner, Color(c, 0.5), 1.0, 4.0)
		draw_dashed_line(corner, sb, Color(c, 0.5), 1.0, 4.0)
		_text(mid + Vector2(10, 8), detail, UIPalette.TEXT_DIM, SMALL_FONT_SIZE)


func _draw_scale_bar() -> void:
	var ppm := _px_per_m()
	var metres := pick_step(BAR_STEPS, 80.0 / ppm)
	var length := metres * ppm
	var y := size.y - 24.0
	var x0 := size.x * 0.5 - length * 0.5
	var c := UIPalette.TEXT
	draw_line(Vector2(x0, y), Vector2(x0 + length, y), Color(0, 0, 0, 0.6), 4.0)
	draw_line(Vector2(x0, y), Vector2(x0 + length, y), c, 2.0)
	for x in [x0, x0 + length]:
		draw_line(Vector2(x, y - 5), Vector2(x, y + 5), c, 2.0)
	var label := "%s m" % _metres(metres)
	_text(Vector2(size.x * 0.5 - _text_width(label) * 0.5, y - 9), label, c)


## Where the cursor is in metres, and what snaps: bottom left above the hints.
func _draw_readout() -> void:
	if cursor.x < 0.0:
		return
	var p := point_at(cursor)
	var a := p.dot(_h())
	var b := p.dot(_v())
	var text: String
	match kind:
		Kind.PLAN:
			text = "X %.2f m   Z %.2f m" % [a, -b]
		Kind.FRONT:
			text = "X %.2f m   Height %.2f m" % [a, b]
		_:
			text = "Z %.2f m   Height %.2f m" % [a, b]
	if measuring:
		text += "   ·   click to measure"
	_text(Vector2(MARGIN, size.y - 52.0), text, UIPalette.TEXT_DIM)


func _draw_title_block(fixture_count: int) -> void:
	var w := 300.0
	var h := 92.0
	var rect := Rect2(size.x - w - MARGIN, size.y - h - MARGIN, w, h)
	draw_rect(rect, Color(0.04, 0.05, 0.07, 0.92))
	draw_rect(rect, UIPalette.HAIRLINE, false, 1.0)
	var x := rect.position.x + 14.0
	var y := rect.position.y + 24.0
	_text(Vector2(x, y), "PRECISION  ·  Light plot", UIPalette.ACCENT, 14)
	_text(Vector2(x, y + 22), view_name(), UIPalette.TEXT)
	var grid := pick_step(MINOR_STEPS, MIN_MINOR_PX / _px_per_m())
	_text(Vector2(x, y + 42), "%d fixtures  ·  grid %s m" % [fixture_count, _metres(grid)], UIPalette.TEXT_DIM, SMALL_FONT_SIZE)
	_text(Vector2(x, y + 58), Time.get_datetime_string_from_system(false, true), UIPalette.TEXT_FAINT, SMALL_FONT_SIZE)


# ---------------------------------------------------------------- export

## Save what the sheet shows (3D view, grid, labels, beams and a title block) as
## a PNG in Documents/Precision/plots. Returns the path, or "" if it failed.
## Wait for it with `await`.
func export_png() -> String:
	if kind == Kind.NONE:
		return ""
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var folder := documents.path_join("Precision").path_join("plots") if not documents.is_empty() else ""
	if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder) != OK:
		folder = ProjectSettings.globalize_path("user://plots")
		DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "-")
	var path := folder.path_join("precision-%s-%s.png" % [view_name().to_lower().replace(" ", "-"), stamp])
	var was_cursor := cursor
	cursor = Vector2(-1, -1)
	exporting = true
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	exporting = false
	cursor = was_cursor
	queue_redraw()
	if image == null or image.save_png(path) != OK:
		return ""
	return path
