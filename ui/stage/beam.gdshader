shader_type spatial;
// Fake volumetric light beam: an additive cone that fades along its length and
// towards its silhouette edges. Black = invisible, so it only adds light.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 beam_color : source_color = vec3(1.0);
uniform float intensity = 0.2;
uniform float beam_length = 6.0;

varying float along; // 0 at the lens, 1 at the far end

void vertex() {
	along = clamp(0.5 - VERTEX.y / beam_length, 0.0, 1.0);
}

void fragment() {
	float fade = pow(1.0 - along, 2.2);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.05, 1.0, facing);
	ALBEDO = beam_color * intensity * fade * edge;
}
