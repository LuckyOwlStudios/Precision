# Builds the straight truss models from Bryan's Blender box truss,
# box_truss_12in.blend in this folder. From the repo root:
#
#   blender -b structure/models/source/box_truss_12in.blend --python structure/models/source/build_truss.py
#   godot --headless --path . --script res://tools/import_truss_models.gd
#
# The first writes truss_*.glb here, the second turns them into the meshes
# the truss pieces load. The script edits the meshes in memory for each
# length and never saves the .blend. An output folder can be given after
# "--" to write the GLBs somewhere else.
#
# The .blend is a 2 m truss modelled at twice real size (chords 100 mm,
# 480 mm apart, 4 m long). Stretching one model would squash the braces, so
# each length is rebuilt from the same parts instead: the chords are cut to
# length, the end plates moved to the ends, the zig-zag braces re-spaced to
# fit and a rung put across the top or bottom at every zig-zag node, as in the
# model. Then the Geometry Nodes pipes are applied, everything is halved to
# real size and written as GLB.
# The GLBs are then turned into Godot meshes by tools/import_truss_models.gd.

import os
import sys
import bmesh
import bpy

LENGTHS = {"0_5m": 0.5, "1m": 1.0, "2m": 2.0, "3m": 3.0}  # real metres
BLEND_LEN = 4.0  # the .blend's length, at 2x scale
CHORD = 0.24  # chord centre offset from the middle, at 2x scale
BRACE_INSET = 0.2  # zig-zag starts this far in from each end, at 2x scale
BRACE_BAY = 0.36  # zig-zag bay length to aim for, at 2x scale
TOP_RUNG_X = 0.0  # a rung across the top in the .blend
BOTTOM_RUNG_X = 0.36  # a rung across the bottom in the .blend

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.dirname(os.path.abspath(__file__))
blend = bpy.data.filepath


def set_verts(obj, fn):
	me = obj.data
	for v in me.vertices:
		v.co = fn(v.co.copy())
	me.update()


def build(name, real_len):
	bpy.ops.wm.open_mainfile(filepath=blend)  # fresh copy of every part
	u = real_len * 2.0  # length in .blend units
	half = u * 0.5
	shift = half - BLEND_LEN * 0.5

	# Chords: the modelled quarter runs from -2 to 0, mirrored on all axes.
	# A straight tube only gets longer when scaled along its axis.
	set_verts(bpy.data.objects["Cylinder"],
		lambda c: c.__class__((c.x * half / (BLEND_LEN * 0.5), c.y, c.z)))

	# End frame and end plate: move the modelled end to the new end.
	for obj_name in ("Cube", "Cube.001"):
		set_verts(bpy.data.objects[obj_name],
			lambda c: c.__class__((c.x + (shift if c.x > 0 else -shift), c.y, c.z)))

	# Zig-zag braces on both side faces: an even number of bays, so the
	# pattern is the same from either end.
	span = 2.0 * (half - BRACE_INSET)
	bays = max(2, 2 * round(span / BRACE_BAY / 2.0))
	nodes = [(-span * 0.5 + span * i / bays, -CHORD if i % 2 == 0 else CHORD) for i in range(bays + 1)]
	zig = bpy.data.objects["Brace Zigzag"]
	bm = bmesh.new()
	for side in (CHORD, -CHORD):
		prev = None
		for x, z in nodes:
			v = bm.verts.new((x, side, z))
			if prev:
				bm.edges.new((prev, v))
			prev = v
	bm.to_mesh(zig.data)
	bm.free()

	# A rung across the top or bottom at every zig-zag node but the end ones.
	rungs = bpy.data.objects["Rungs"]
	bm = bmesh.new()
	bm.from_mesh(rungs.data)
	originals = bm.verts[:]

	def template(x0):
		verts = [v for v in originals if abs(v.co.x - x0) < 0.1]
		faces = {f for v in verts for f in v.link_faces}
		edges = {e for v in verts for e in v.link_edges}
		return verts + list(edges) + list(faces)

	top, bottom = template(TOP_RUNG_X), template(BOTTOM_RUNG_X)
	for x, z in nodes[1:-1]:
		src, x0 = (top, TOP_RUNG_X) if z > 0 else (bottom, BOTTOM_RUNG_X)
		dup = bmesh.ops.duplicate(bm, geom=src)
		moved = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
		bmesh.ops.translate(bm, verts=moved, vec=(x - x0, 0, 0))
	bmesh.ops.delete(bm, geom=originals, context="VERTS")
	bm.to_mesh(rungs.data)
	bm.free()

	# Real size: halve every part (all sit at the origin).
	for obj in bpy.data.objects:
		obj.scale = (0.5, 0.5, 0.5)

	path = f"{out_dir}/truss_{name}.glb"
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
		export_yup=True, export_cameras=False, export_lights=False)
	print("BUILT", path, "bays", bays, "rungs", len(nodes) - 2)


for key, length in LENGTHS.items():
	build(key, length)
