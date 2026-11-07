shader_type spatial;
// The mirror plane of symmetry mode: a faint vertical sheet with a bright rim
// and floor line, drawn on a QuadMesh. Objects in front of it hide it as usual.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform vec4 color : source_color = vec4(0.55, 0.36, 1.0, 1.0);
uniform float fill = 0.08;
uniform float rim = 0.7;
uniform vec2 size = vec2(16.0, 6.0); // metres, to keep the rim a constant width

void fragment() {
	vec2 m = UV * size;
	vec2 d = min(m, size - m);
	float edge = 1.0 - smoothstep(0.0, 0.06, min(d.x, d.y));
	float floor_line = 1.0 - smoothstep(0.0, 0.05, size.y - m.y);
	float a = fill + (edge * rim) + floor_line * 0.3;
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 0.9);
}
