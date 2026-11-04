shader_type spatial;
// Soft halo around a lit lens: a camera-facing quad with a radial falloff,
// added on top of the scene. Brightest when you look straight into the lens.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow_color : source_color = vec3(1.0);
uniform float intensity = 0.0;
uniform float size = 0.6; // world radius of the halo
uniform vec3 beam_dir = vec3(0.0, -1.0, 0.0); // world direction the lens points

varying float facing;

void vertex() {
	// Billboard: keep the quad's centre, rebuild it in the camera's plane.
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y) * size;
	// Nudge towards the camera so the halo isn't cut by the fixture body.
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	world += to_cam * 0.12;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	facing = clamp(dot(normalize(beam_dir), to_cam), 0.0, 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = exp(-r * r * 28.0);
	float halo = exp(-r * 4.5) * (1.0 - smoothstep(0.7, 1.0, r));
	// Looking into the lens: much brighter (like a real fixture blinding you).
	float look = 0.25 + 0.75 * pow(facing, 3.0);
	ALBEDO = glow_color * intensity * look * (core * 2.5 + halo * 0.6);
}
