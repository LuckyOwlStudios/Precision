class_name ShowCodec
extends RefCounted
## Turns Godot values into JSON-friendly data and back, for the show file.
##
## Plain numbers, strings, bools, arrays and string-keyed dictionaries pass
## through. Godot types JSON can't hold (Color, Vector3, Basis, Transform3D,
## packed arrays) become a small tagged dictionary: {"$t": "color", "v": [...]}.
## A save file therefore stays readable and a diff shows what changed.
##
## JSON has one number type, so whole numbers come back as floats. When you
## put a decoded value on a property, use apply() (it converts to the type the
## property already has) or type_convert() yourself.

const TAG := "$t"


static func encode(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_COLOR:
			var c: Color = value
			return _tagged("color", [c.r, c.g, c.b, c.a])
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return _tagged("vec2", [v2.x, v2.y])
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return _tagged("vec3", [v3.x, v3.y, v3.z])
		TYPE_BASIS:
			var b: Basis = value
			return _tagged("basis", [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z])
		TYPE_TRANSFORM3D:
			var t: Transform3D = value
			return _tagged("xform", [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z])
		TYPE_PACKED_COLOR_ARRAY:
			var flat: Array = []
			for c: Color in (value as PackedColorArray):
				flat.append_array([c.r, c.g, c.b, c.a])
			return _tagged("colors", flat)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return _tagged("floats", Array(value))
		TYPE_PACKED_STRING_ARRAY:
			return _tagged("strings", Array(value))
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return _tagged("ints", Array(value))
		TYPE_ARRAY:
			var list: Array = []
			for item: Variant in value:
				list.append(encode(item))
			return list
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in value:
				d[str(k)] = encode(value[k])
			return d
	push_warning("ShowCodec: can't save a value of type %d, left out" % typeof(value))
	return null


static func decode(data: Variant) -> Variant:
	if data is Array:
		var list: Array = []
		for item: Variant in data:
			list.append(decode(item))
		return list
	if not data is Dictionary:
		return data
	var d: Dictionary = data
	if not d.has(TAG):
		var out := {}
		for k: Variant in d:
			out[k] = decode(d[k])
		return out
	var v: Array = d.get("v", [])
	match str(d[TAG]):
		"color":
			return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
		"vec2":
			return Vector2(float(v[0]), float(v[1]))
		"vec3":
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		"basis":
			return Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8]))
		"xform":
			return Transform3D(Basis(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), Vector3(v[6], v[7], v[8])),
				Vector3(v[9], v[10], v[11]))
		"colors":
			var colors := PackedColorArray()
			for i in range(0, v.size() - 3, 4):
				colors.append(Color(float(v[i]), float(v[i + 1]), float(v[i + 2]), float(v[i + 3])))
			return colors
		"floats":
			return PackedFloat32Array(v)
		"strings":
			return PackedStringArray(v)
		"ints":
			return PackedInt32Array(v)
	push_warning("ShowCodec: unknown value type '%s', left out" % d[TAG])
	return null


## Decode `data` and set it as `prop` of `obj`, converted to the type that
## property has now (a strobe saved as 3 comes back as the int 3).
static func apply(obj: Object, prop: StringName, data: Variant) -> void:
	var value: Variant = decode(data)
	var current: Variant = obj.get(prop)
	if current != null and typeof(current) != typeof(value) and typeof(value) != TYPE_NIL:
		value = type_convert(value, typeof(current))
	obj.set(prop, value)


static func _tagged(type_name: String, value: Array) -> Dictionary:
	return {TAG: type_name, "v": value}
