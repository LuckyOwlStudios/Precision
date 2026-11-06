class_name MountRotation
extends RefCounted
## Which ways a fixture can be turned on the stage, worked out from how it is
## mounted right now. The rotate gizmo draws one ring per axis this returns.
##
##   Hung on a truss tube  -> SWING around the tube (the clamps turn on it).
##                            With a single clamp the fixture can also SPIN
##                            under it, on the clamp's bolt (a par or strobe
##                            on one hook clamp). Two or more clamps on the
##                            same tube (light bar, moving head on two omega
##                            brackets) lock that, so they only swing.
##   Standing on a surface -> SPIN about the floor's / wall's normal: its
##                            feet stay planted. A light bar (stand allowed
##                            in its scene) can also TILT on its stand: it
##                            turns about its own long axis on the bracket's
##                            knobs, to aim at a wall. That is the stand, not
##                            DMX tilt, and it lives in the fixture's
##                            transform, so move, undo and save need nothing
##                            extra.
##   Placed freely (Alt)   -> all three world axes, as before.
##
## The defaults come from the fixture scene's MountPoints (how many clamps,
## and whether each one swivels), and each fixture scene can override them on
## its root (StageFixture3D, "Rotating on stage"). So a new fixture scene gets
## sensible rotation without any code.
## Motorised pan and tilt are not part of this; they are DMX channels, set in
## the inspector and by cues.

enum Allow { AUTO, ALLOW, LOCK } ## AUTO = decide from the clamps and mounting
enum Mount { FREE, SURFACE, TRUSS }
enum Kind { SWING, SPIN_CLAMP, SPIN_SURFACE, TILT_STAND, FREE_X, FREE_Y, FREE_Z }

const _NAMES := {
	Kind.SWING: "Swing", Kind.SPIN_CLAMP: "Spin", Kind.SPIN_SURFACE: "Spin", Kind.TILT_STAND: "Tilt",
	Kind.FREE_X: "X", Kind.FREE_Y: "Y", Kind.FREE_Z: "Z",
}
## A mounting face closer than this to a surface counts as standing on it.
const ON_SURFACE_TOLERANCE := 0.02

static var _rules_cache: Dictionary = {} ## scene path -> Rules


## One way the fixture can turn: around `dir` (world, unit length) through
## the world point `pivot`.
class Axis:
	extends RefCounted
	var kind: MountRotation.Kind
	var dir: Vector3
	var pivot: Vector3

	func _init(p_kind: MountRotation.Kind, p_dir: Vector3, p_pivot: Vector3) -> void:
		kind = p_kind
		dir = p_dir.normalized()
		pivot = p_pivot

	func label() -> String:
		return MountRotation._NAMES[kind]

	## What dragging this ring does, shown while hovering it.
	func hint() -> String:
		match kind:
			MountRotation.Kind.SWING:
				return "Swing around the truss"
			MountRotation.Kind.SPIN_CLAMP:
				return "Spin under the clamp"
			MountRotation.Kind.SPIN_SURFACE:
				return "Spin on the spot"
			MountRotation.Kind.TILT_STAND:
				return "Tilt on the stand"
		return "Turn about " + label()

	## `xform` turned by `angle` radians about this axis.
	func turned(xform: Transform3D, angle: float) -> Transform3D:
		var r := Basis(dir, angle)
		return Transform3D((r * xform.basis).orthonormalized(), pivot + r * (xform.origin - pivot))


## What a fixture scene allows, read once from the scene.
class Rules:
	extends RefCounted
	var mounts := PackedVector3Array() ## clamp centres in the fixture's own space
	var swivels := 0 ## how many of those clamps let the fixture turn on their bolt
	var swing_on_truss: MountRotation.Allow = MountRotation.Allow.AUTO
	var spin_on_clamp: MountRotation.Allow = MountRotation.Allow.AUTO
	var spin_on_surface: MountRotation.Allow = MountRotation.Allow.AUTO
	var tilt_on_stand: MountRotation.Allow = MountRotation.Allow.AUTO

	func can_swing() -> bool:
		return MountRotation._decide(swing_on_truss, not mounts.is_empty())

	## AUTO: only one clamp, and it swivels. Two clamps on one tube hold the
	## fixture's line, so it cannot turn under them.
	func can_spin_on_clamp() -> bool:
		return MountRotation._decide(spin_on_clamp, mounts.size() == 1 and swivels == 1)

	func can_spin_on_surface() -> bool:
		return MountRotation._decide(spin_on_surface, true)

	## AUTO: no. Only fixtures whose scene has a tilting stand (the light bar).
	func can_tilt_on_stand() -> bool:
		return MountRotation._decide(tilt_on_stand, false)


static func _decide(rule: Allow, auto: bool) -> bool:
	match rule:
		Allow.ALLOW:
			return true
		Allow.LOCK:
			return false
	return auto


## The rotation rules of a fixture body scene (cached).
static func rules_of(path: String) -> Rules:
	if _rules_cache.has(path):
		return _rules_cache[path]
	var rules := Rules.new()
	var root := (load(path) as PackedScene).instantiate()
	if root is StageFixture3D:
		var s := root as StageFixture3D
		rules.swing_on_truss = s.swing_on_truss
		rules.spin_on_clamp = s.spin_on_clamp
		rules.spin_on_surface = s.spin_on_surface
		rules.tilt_on_stand = s.tilt_on_stand
	for n in root.find_children("*", "", true, false):
		if n is MountPoint:
			var t := (n as Node3D).transform
			var p := n.get_parent()
			while p != root:
				t = (p as Node3D).transform * t
				p = p.get_parent()
			rules.mounts.append(t.origin)
			if (n as MountPoint).swivel:
				rules.swivels += 1
	root.free()
	_rules_cache[path] = rules
	return rules


## How a fixture is held right now: by a tube, standing on a surface, or
## neither (placed freely). `offset` is its mount_offset (origin to mounting face).
static func mount_of(xform: Transform3D, rules: Rules, offset: float,
		pipes: Array[StageRoom.Pipe], surfaces: Array[StageRoom.Surface]) -> Mount:
	if StageRoom.pipe_holding(pipes, xform, rules.mounts) != null:
		return Mount.TRUSS
	if standing_on(xform, offset, surfaces) or not is_nan(stand_tilt(xform, rules, offset, surfaces)):
		return Mount.SURFACE
	return Mount.FREE


## True if the fixture's mounting face (local +Y, `offset` from its origin)
## sits flush on a floor, wall or booth surface.
static func standing_on(xform: Transform3D, offset: float, surfaces: Array[StageRoom.Surface]) -> bool:
	var into := xform.basis.y.normalized() # mounting side, pointing into the surface
	var face := xform.origin + into * offset
	var hit := StageRoom.raycast(surfaces, face - into * 0.05, into)
	return hit != null and hit.normal.dot(-into) > 0.99 \
		and hit.position.distance_to(face) < ON_SURFACE_TOLERANCE


## For a fixture on a tilting stand: how far (radians, about its own X) it is
## tilted off sitting flat on a floor / wall, or NAN if it is not on one. The
## stand's pivot is the fixture's origin, so tilting never lifts the base:
## the origin stays `offset` off the surface, and the long axis (local X)
## stays parallel to it. Walls, floors and booth tops are axis aligned, so
## only the six axis normals need checking.
static func stand_tilt(xform: Transform3D, rules: Rules, offset: float,
		surfaces: Array[StageRoom.Surface]) -> float:
	if not rules.can_tilt_on_stand():
		return NAN
	var x := xform.basis.x.normalized()
	for n: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		if absf(x.dot(n)) > 0.01:
			continue
		var into := -n # flush mounting side, pointing into the surface
		var face := xform.origin + into * offset
		var hit := StageRoom.raycast(surfaces, face - into * 0.05, into)
		if hit == null or hit.normal.dot(n) < 0.99 or hit.position.distance_to(face) > ON_SURFACE_TOLERANCE:
			continue
		return into.signed_angle_to(xform.basis.y.normalized(), x)
	return NAN


## The axes a fixture can be turned about, given where it is. Empty if it is
## locked in place (a scene that locks every option).
static func axes(xform: Transform3D, rules: Rules, offset: float,
		pipes: Array[StageRoom.Pipe], surfaces: Array[StageRoom.Surface]) -> Array[Axis]:
	var list: Array[Axis] = []
	var pipe := StageRoom.pipe_holding(pipes, xform, rules.mounts)
	if pipe:
		var clamps := xform * StageRoom.centre_of(rules.mounts)
		if rules.can_swing():
			list.append(Axis.new(Kind.SWING, pipe.axis(), pipe.point(pipe.along_of(clamps))))
		if rules.can_spin_on_clamp():
			list.append(Axis.new(Kind.SPIN_CLAMP, xform.basis.y, clamps))
		return list
	var tilt := stand_tilt(xform, rules, offset, surfaces)
	if not is_nan(tilt):
		# Spin about the surface normal (not the tilted local Y); tilt about the bar's length.
		var up := xform.basis.y.rotated(xform.basis.x.normalized(), -tilt).normalized()
		if rules.can_spin_on_surface():
			list.append(Axis.new(Kind.SPIN_SURFACE, up, xform.origin))
		list.append(Axis.new(Kind.TILT_STAND, xform.basis.x, xform.origin))
		return list
	if standing_on(xform, offset, surfaces):
		if rules.can_spin_on_surface():
			list.append(Axis.new(Kind.SPIN_SURFACE, xform.basis.y, xform.origin))
		return list
	list.append(Axis.new(Kind.FREE_X, Vector3.RIGHT, xform.origin))
	list.append(Axis.new(Kind.FREE_Y, Vector3.UP, xform.origin))
	list.append(Axis.new(Kind.FREE_Z, Vector3.BACK, xform.origin))
	return list
