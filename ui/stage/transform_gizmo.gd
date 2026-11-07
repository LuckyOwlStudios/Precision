class_name TransformGizmo
extends Control
## Move and rotate handles for the selected fixture, drawn in 2D on top of the
## 3D view so they stay the same size on screen and are always clickable.
##   Move:   arrows drag along one world axis, squares drag in a plane.
##   Rotate: one ring per way the fixture can turn where it is mounted (see
##           MountRotation): around the truss tube it hangs from, under its
##           clamp, on the spot on the floor, or about any world axis when it
##           is placed freely. Each ring sits on its own pivot and is coloured
##           like the world axis it is closest to (X red, Y green, Z blue).
## It only works out a new Transform3D; the stage view decides what to do with it.

enum Mode { MOVE, ROTATE }
enum Handle { NONE, X, Y, Z, XY, XZ, YZ }

const SIZE_PX := 96.0 ## arrow length on screen
const PICK_PX := 9.0
const PLANE_FROM := 0.22 ## plane squares sit between these fractions of the arrow
const PLANE_TO := 0.42
const RING_SCALE := 0.8
const MOVE_STEP := 0.25 ## metres, when snapping
const ROTATE_STEP := 15.0 ## degrees, when snapping

const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS: Array[Color] = [Color("ff5d6c"), Color("6fdc8c"), Color("5aa8ff")]

var mode: Mode = Mode.MOVE:
	set(value):
		mode = value
		hovered = Handle.NONE
		queue_redraw()
var camera: Camera3D
## The transform being edited. Hidden while `shown` is false.
var target := Transform3D.IDENTITY
## The ways the target can turn (rotate mode), at most three. Empty = locked.
var rings: Array[MountRotation.Axis] = []:
	set(value):
		rings = value
		queue_redraw()
var shown := false:
	set(value):
		shown = value
		queue_redraw()
var hovered: Handle = Handle.NONE:
	set(value):
		if hovered != value:
			hovered = value
			queue_redraw()

var _active: Handle = Handle.NONE
var _start := Transform3D.IDENTITY
var _plane := Plane()
var _grab := Vector3.ZERO
var _last_angle := 0.0
var _turned := 0.0
var _ring: MountRotation.Axis ## the ring being dragged
var _ring_edge_on := false ## seen side on: drag along the ring instead of around it
var _ring_tangent := Vector2.ZERO ## screen direction the grabbed point moves for a + turn
var _ring_px_per_rad := 100.0
var _grab_mouse := Vector2.ZERO
var _angle := 0.0 ## current turn while rotating, radians
var _readout := ""
var pick_px := PICK_PX ## how near a handle must be to grab it (bigger for a fingertip)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_dragging() -> bool:
	return _active != Handle.NONE


## Which handle is under a point on screen.
func handle_at(p: Vector2) -> Handle:
	if not shown or camera == null or _behind():
		return Handle.NONE
	var o := _screen(target.origin)
	var span := _world_len()
	if mode == Mode.MOVE:
		# Planes first: they sit inside the arrows' corner and are small.
		for h: Handle in [Handle.XY, Handle.XZ, Handle.YZ]:
			if Geometry2D.is_point_in_polygon(p, _plane_quad(h, span)):
				return h
		var best := Handle.NONE
		var best_d := pick_px
		for i in 3:
			var tip := _screen(target.origin + AXES[i] * span)
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, o, tip))
			if d < best_d:
				best_d = d
				best = (Handle.X + i) as Handle
		return best
	var best_r := Handle.NONE
	var best_rd := pick_px
	for i in mini(rings.size(), 3):
		var pts := _ring_points(rings[i])
		for j in pts.size() - 1:
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]))
			if d < best_rd:
				best_rd = d
				best_r = (Handle.X + i) as Handle
	return best_r


func begin_drag(h: Handle, mouse: Vector2) -> void:
	_active = h
	_start = target
	_readout = ""
	if mode == Mode.ROTATE:
		_begin_turn(rings[h - Handle.X], mouse)
		return
	var view := camera.project_ray_normal(mouse)
	var normal: Vector3
	match h:
		Handle.XY: normal = Vector3.BACK
		Handle.XZ: normal = Vector3.UP
		Handle.YZ: normal = Vector3.RIGHT
		_:
			# The plane that holds the axis and faces the camera the most.
			var axis := _axis(h)
			normal = axis.cross(view).cross(axis)
			if normal.length() < 1e-4:
				normal = -view
	_plane = Plane(normal.normalized(), _start.origin)
	var hit: Variant = _plane.intersects_ray(camera.project_ray_origin(mouse), view)
	_grab = hit if hit != null else _start.origin


## New transform for the handle being dragged. `snap` rounds to MOVE_STEP / ROTATE_STEP.
func drag(mouse: Vector2, snap: bool) -> Transform3D:
	if _active == Handle.NONE:
		return target
	var result := _start
	if mode == Mode.ROTATE:
		var angle := _turn_angle(mouse)
		if snap:
			angle = snappedf(angle, deg_to_rad(ROTATE_STEP))
		_angle = angle
		result = _ring.turned(_start, angle)
		_readout = "%s %+.0f°" % [_ring.label(), rad_to_deg(angle)]
	else:
		var hit: Variant = _plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit == null:
			return target
		var delta: Vector3 = (hit as Vector3) - _grab
		var moved: Array[int] = []
		match _active:
			Handle.X, Handle.Y, Handle.Z:
				var axis := _axis(_active)
				delta = axis * delta.dot(axis)
				moved = [_active - Handle.X]
			Handle.XY: moved = [0, 1]
			Handle.XZ: moved = [0, 2]
			Handle.YZ: moved = [1, 2]
		result.origin = _start.origin + delta
		if snap:
			for i in moved:
				result.origin[i] = snappedf(result.origin[i], MOVE_STEP)
		var d := result.origin - _start.origin
		var parts: PackedStringArray = []
		for i in moved:
			parts.append("%s %+.2f m" % ["XYZ"[i], d[i]])
		_readout = "   ".join(parts)
	target = result
	queue_redraw()
	return result


func end_drag() -> void:
	_active = Handle.NONE
	_ring = null
	_readout = ""
	queue_redraw()


## Start turning about `ring`. Seen face on, the turn follows the cursor round
## the pivot; seen side on (the ring is a thin line on screen, like a truss
## tube pointing across the view), dragging along the line turns it instead.
func _begin_turn(ring: MountRotation.Axis, mouse: Vector2) -> void:
	_ring = ring
	_angle = 0.0
	_turned = 0.0
	_grab_mouse = mouse
	var view := (ring.pivot - camera.global_position).normalized()
	_ring_edge_on = absf(ring.dir.dot(view)) < 0.3
	_last_angle = (mouse - _screen(ring.pivot)).angle()
	if not _ring_edge_on:
		return
	# The point on the ring nearest the cursor, and which way it goes on screen.
	var radius := _world_len_at(ring.pivot) * RING_SCALE
	var u := _perpendicular(ring.dir)
	var v := ring.dir.cross(u)
	var grab := ring.pivot + u * radius
	var best := INF
	for i in 64:
		var t := TAU * i / 64.0
		var p := ring.pivot + (u * cos(t) + v * sin(t)) * radius
		var d := _screen(p).distance_to(mouse)
		if d < best:
			best = d
			grab = p
	var tangent := ring.dir.cross(grab - ring.pivot).normalized()
	var moved := _screen(grab + tangent * radius * 0.1) - _screen(grab)
	_ring_px_per_rad = maxf(moved.length() * 10.0, 20.0)
	_ring_tangent = moved.normalized() if moved.length() > 0.01 else Vector2.RIGHT


func _turn_angle(mouse: Vector2) -> float:
	if _ring_edge_on:
		return (mouse - _grab_mouse).dot(_ring_tangent) / _ring_px_per_rad
	var a := (mouse - _screen(_ring.pivot)).angle()
	_turned += wrapf(a - _last_angle, -PI, PI)
	_last_angle = a
	# Screen angles grow clockwise; a right-handed turn about an axis that
	# points at you looks anticlockwise, so flip when it does.
	var facing := _ring.dir.dot(camera.global_position - _ring.pivot) > 0.0
	return -_turned if facing else _turned


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not shown or camera == null or _behind():
		return
	var o := _screen(target.origin)
	var span := _world_len()
	if mode == Mode.MOVE:
		for h: Handle in [Handle.XY, Handle.XZ, Handle.YZ]:
			var c := _color(h)
			draw_colored_polygon(_plane_quad(h, span), Color(c, 0.45 if _lit(h) else 0.22))
		for i in 3:
			var h := (Handle.X + i) as Handle
			if _active != Handle.NONE and not _lit(h) and _active < Handle.XY:
				continue # dragging one axis: hide the others
			var tip := _screen(target.origin + AXES[i] * span)
			var dir := tip - o
			if dir.length() < 6.0:
				continue # pointing straight at the camera
			var c := _color(h)
			var n := dir.normalized()
			var side := n.orthogonal() * 6.0
			draw_line(o, tip - n * 10.0, c, 3.0 if _lit(h) else 2.0, true)
			draw_colored_polygon(PackedVector2Array([tip, tip - n * 14.0 + side, tip - n * 14.0 - side]), c)
		draw_circle(o, 4.0, Color.WHITE)
		if _active >= Handle.X and _active <= Handle.Z:
			# Long faint guide line through the fixture along the drag axis.
			var axis := AXES[_active - Handle.X]
			draw_line(_screen(_start.origin - axis * 50.0), _screen(_start.origin + axis * 50.0), Color(_color(_active), 0.35), 1.0, true)
	else:
		_draw_rings()
	if not _readout.is_empty():
		var font := get_theme_default_font()
		var pos := o + Vector2(18, -18)
		draw_string(font, pos + Vector2(1, 1), _readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.7))
		draw_string(font, pos, _readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPalette.TEXT)


func _draw_rings() -> void:
	if rings.is_empty():
		_draw_label(_screen(target.origin) + Vector2(14, -14), "Can't turn: locked in place")
		return
	for i in mini(rings.size(), 3):
		var h := (Handle.X + i) as Handle
		if _active != Handle.NONE and _active != h:
			continue
		var ring := rings[i]
		var c := _color(h)
		if _active == h:
			# The axis it turns about (the tube, the bolt, the floor normal),
			# and a wedge from where it started to where it is now.
			var reach := _world_len_at(ring.pivot) * 1.6
			draw_line(_screen(ring.pivot - ring.dir * reach), _screen(ring.pivot + ring.dir * reach), Color(c, 0.5), 1.5, true)
			_draw_wedge(ring, Color(c, 0.18))
		draw_polyline(_ring_points(ring), c, 3.0 if _lit(h) else 2.0, true)
		draw_circle(_screen(ring.pivot), 3.0, Color.WHITE)
		if _active == Handle.NONE and hovered == h:
			_draw_label(_screen(ring.pivot) + Vector2(18, 18), ring.hint())


## Filled slice of the ring from the start of the turn to now.
func _draw_wedge(ring: MountRotation.Axis, c: Color) -> void:
	if absf(_angle) < 0.01:
		return
	var radius := _world_len_at(ring.pivot) * RING_SCALE
	var start_dir := _start_dir(ring)
	var pts := PackedVector2Array([_screen(ring.pivot)])
	var steps := maxi(2, int(absf(_angle) / TAU * 64.0))
	for i in steps + 1:
		var a := _angle * i / steps
		pts.append(_screen(ring.pivot + Basis(ring.dir, a) * start_dir * radius))
	if pts.size() >= 3:
		draw_colored_polygon(pts, c)


## Where the wedge starts: the fixture's beam direction flattened onto the ring.
func _start_dir(ring: MountRotation.Axis) -> Vector3:
	var beam := -_start.basis.y
	var flat := beam - ring.dir * beam.dot(ring.dir)
	if flat.length() < 0.05:
		return _perpendicular(ring.dir)
	return flat.normalized()


func _draw_label(pos: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.7))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPalette.TEXT)


func _lit(h: Handle) -> bool:
	return h == _active or (_active == Handle.NONE and h == hovered)


func _color(h: Handle) -> Color:
	if _lit(h):
		return UIPalette.ACCENT
	if mode == Mode.ROTATE:
		var i := h - Handle.X
		if i >= 0 and i < rings.size():
			# Coloured like the world axis the ring turns about most.
			var d := rings[i].dir.abs()
			return AXIS_COLORS[0 if d.x >= d.y and d.x >= d.z else (1 if d.y >= d.z else 2)]
	match h:
		Handle.X, Handle.YZ: return AXIS_COLORS[0]
		Handle.Y, Handle.XZ: return AXIS_COLORS[1]
	return AXIS_COLORS[2]


# ---------------------------------------------------------------- geometry

func _axis(h: Handle) -> Vector3:
	return AXES[clampi(h - Handle.X, 0, 2)]


func _screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _behind() -> bool:
	return camera.is_position_behind(target.origin)


## World length that shows up as SIZE_PX on screen at the target's depth.
func _world_len() -> float:
	return _world_len_at(target.origin)


func _world_len_at(p: Vector3) -> float:
	var depth := -(camera.global_transform.affine_inverse() * p).z
	var h := camera.get_viewport().get_visible_rect().size.y
	return maxf(depth, 0.1) * 2.0 * tan(deg_to_rad(camera.fov) * 0.5) * SIZE_PX / maxf(h, 1.0)


func _plane_quad(h: Handle, span: float) -> PackedVector2Array:
	var a: Vector3
	var b: Vector3
	match h:
		Handle.XY:
			a = Vector3.RIGHT
			b = Vector3.UP
		Handle.XZ:
			a = Vector3.RIGHT
			b = Vector3.BACK
		_:
			a = Vector3.UP
			b = Vector3.BACK
	var o := target.origin
	var lo := span * PLANE_FROM
	var hi := span * PLANE_TO
	return PackedVector2Array([
		_screen(o + a * lo + b * lo), _screen(o + a * hi + b * lo),
		_screen(o + a * hi + b * hi), _screen(o + a * lo + b * hi)])


## A ring around `ring.pivot`, square to its axis, as a closed screen polyline.
func _ring_points(ring: MountRotation.Axis) -> PackedVector2Array:
	var radius := _world_len_at(ring.pivot) * RING_SCALE
	var u := _perpendicular(ring.dir)
	var v := ring.dir.cross(u)
	var pts := PackedVector2Array()
	for i in 65:
		var t := TAU * i / 64.0
		pts.append(_screen(ring.pivot + (u * cos(t) + v * sin(t)) * radius))
	return pts


## Some unit vector square to `dir`.
static func _perpendicular(dir: Vector3) -> Vector3:
	var other := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	return dir.cross(other).normalized()
