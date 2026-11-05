@tool
class_name TransportButton
extends Button
## Flat button that draws its own transport icon, so no icon font or image
## files are needed. The play button gets a ring, like a media player.

enum Icon { PLAY, PAUSE, STOP, PREV, NEXT }

## Size, flat style and cursor are set on the node in the scene.
@export var icon_kind: Icon = Icon.PLAY:
	set(v):
		icon_kind = v
		queue_redraw()
## Draw a circle around the icon (the main play button).
@export var ring := false:
	set(v):
		ring = v
		queue_redraw()


func _draw() -> void:
	var c := UIPalette.TEXT if is_hovered() else Color(UIPalette.TEXT, 0.85)
	var m := size * 0.5
	if ring:
		draw_arc(m, minf(size.x, size.y) * 0.5 - 2.0, 0, TAU, 48, c, 1.5, true)
	var s := 6.0
	match icon_kind:
		Icon.PLAY:
			draw_colored_polygon(PackedVector2Array([m + Vector2(-s * 0.6, -s), m + Vector2(s, 0), m + Vector2(-s * 0.6, s)]), c)
		Icon.PAUSE:
			draw_rect(Rect2(m + Vector2(-s * 0.75, -s), Vector2(s * 0.5, s * 2)), c)
			draw_rect(Rect2(m + Vector2(s * 0.25, -s), Vector2(s * 0.5, s * 2)), c)
		Icon.STOP:
			draw_rect(Rect2(m - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), c)
		Icon.PREV:
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s * 0.8), m + Vector2(-s, 0), m + Vector2(0, s * 0.8)]), c)
			draw_colored_polygon(PackedVector2Array([m + Vector2(s, -s * 0.8), m + Vector2(0, 0), m + Vector2(s, s * 0.8)]), c)
		Icon.NEXT:
			draw_colored_polygon(PackedVector2Array([m + Vector2(-s, -s * 0.8), m + Vector2(0, 0), m + Vector2(-s, s * 0.8)]), c)
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s * 0.8), m + Vector2(s, 0), m + Vector2(0, s * 0.8)]), c)
