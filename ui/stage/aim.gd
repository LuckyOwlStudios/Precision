class_name Aim
extends RefCounted
## Works out where a moving head's pan and tilt must be for its beam to land on
## a point in the room. Pure maths, no nodes: it mirrors how StageFixture3D turns
## the fixture (Yoke about the fixture's Y by the pan angle, Head about X by the
## tilt angle, beam down the head's -Y), so what you see is what the maths aims.
##
## Pan and tilt each have two ways to reach the same spot (the head can flip over:
## turn the pan half a circle further and tilt the other way). The one that moves
## the least from where the fixture points now wins, so a light never swings round
## the long way for no reason.

## Where the head turns, in the fixture's own space (the Head node of the movers).
const HEAD_PIVOT := Vector3(0, -0.18, 0)
## A target closer than this to the head's axis leaves pan alone (straight down).
const AXIS_EPSILON := 1e-4


## Pan and tilt (each 0..1, as DMXFixture stores them) that point the beam from a
## fixture standing at `fixture_xf` at `target` (world space). `current` is the
## fixture's pan and tilt now. Returns null when the point is unreachable: the
## fixture's pan or tilt range is too small for either way of reaching it.
static func pan_tilt_for(fixture_xf: Transform3D, target: Vector3, pan_range_deg: float, tilt_range_deg: float, current: Vector2 = Vector2(0.5, 0.5)) -> Variant:
	var head := fixture_xf * HEAD_PIVOT
	var d := fixture_xf.basis.orthonormalized().inverse() * (target - head)
	if d.length() < 0.01:
		return null # the target is in the head itself
	d = d.normalized()
	# Beam after tilt phi (about X) then pan theta (about Y) is
	#   (-sin(phi) sin(theta), -cos(phi), -sin(phi) cos(theta)).
	var phi := acos(clampf(-d.y, -1.0, 1.0)) # 0 = straight down, PI = straight up
	var cur_pan := (current.x - 0.5) * pan_range_deg
	var theta := rad_to_deg(atan2(-d.x, -d.z))
	if absf(sin(phi)) < AXIS_EPSILON:
		theta = cur_pan # straight up or down: every pan points the same way
	var tilt_deg := rad_to_deg(phi)
	var best: Variant = null
	var best_cost := INF
	# Way 1: tilt +phi at pan theta. Way 2: tilt -phi at pan theta + 180.
	for way in 2:
		var t_deg := tilt_deg if way == 0 else -tilt_deg
		var base := theta if way == 0 else theta + 180.0
		# Pan has more than one turn of range on some fixtures: try each equivalent angle.
		for k in range(-2, 3):
			var p_deg := base + 360.0 * k
			if absf(p_deg) > pan_range_deg * 0.5 + 0.001 or absf(t_deg) > tilt_range_deg * 0.5 + 0.001:
				continue
			var cost := absf(p_deg - cur_pan) + absf(t_deg - (-(current.y - 0.5) * tilt_range_deg)) * 0.5
			if cost < best_cost:
				best_cost = cost
				best = Vector2(p_deg / pan_range_deg + 0.5, -t_deg / tilt_range_deg + 0.5)
	return best


## Which way the beam points (world space) for a pan and tilt: the same geometry
## the maths above inverts. Used to check an aim and to draw aim lines.
static func beam_direction(fixture_xf: Transform3D, pan: float, tilt: float, pan_range_deg: float, tilt_range_deg: float) -> Vector3:
	var theta := deg_to_rad((pan - 0.5) * pan_range_deg)
	var phi := deg_to_rad(-(tilt - 0.5) * tilt_range_deg)
	var local := Basis(Vector3.UP, theta) * Basis(Vector3.RIGHT, phi) * Vector3.DOWN
	return (fixture_xf.basis * local).normalized()


## True for a fixture that can be aimed: it has pan and tilt channels.
static func can_aim(fx: DMXFixture) -> bool:
	return fx != null and fx.profile != null and fx.profile.has_channel("pan") and fx.profile.has_channel("tilt")


## Point `fx` at `target` (world space) by setting its pan and tilt. Returns
## false (and leaves it alone) when it can't reach the point.
static func aim_at(fx: DMXFixture, fixture_xf: Transform3D, target: Vector3) -> bool:
	var r: Variant = pan_tilt_for(fixture_xf, target, fx.profile.pan_range_deg, fx.profile.tilt_range_deg, Vector2(fx.pan, fx.tilt))
	if r == null:
		return false
	var pt: Vector2 = r
	fx.pan = clampf(pt.x, 0.0, 1.0)
	fx.tilt = clampf(pt.y, 0.0, 1.0)
	return true
