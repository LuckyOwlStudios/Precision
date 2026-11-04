shader_type spatial;
// Fake volumetric light beam: an additive cone that fades along its length and
// towards its silhouette edges. Black = invisible, so it only adds light.
// - soft edges: brightest through the middle of the cone, fading at the rim
// - soft contact: fades out where it meets the floor or a wall, no hard line
// - drifting haze: slow moving noise so it reads as light in smoke
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 beam_color : source_color = vec3(1.0);
uniform float intensity = 0.2;
uniform float beam_length = 6.0;
uniform float edge_softness : hint_range(0.5, 4.0) = 1.6;
uniform float haze_texture : hint_range(0.0, 1.0) = 0.35; // how much the smoke drifts
uniform float contact_fade = 0.35; // metres of fade where the beam hits something
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float along; // 0 at the lens, 1 at the far end
varying vec3 world_pos;

void vertex() {
	along = clamp(0.5 - VERTEX.y / beam_length, 0.0, 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// Light spreads out, so it thins along the beam (but not to nothing too soon).
	// Clamp first: with MSAA, varyings can be sampled just outside the triangle,
	// and pow() of a negative number is NaN, which glow smears across the screen.
	float a = clamp(along, 0.0, 1.0);
	float fade = pow(1.0 - a, 1.6) * smoothstep(0.0, 0.04, a + 0.01);
	// Seen side-on the cone is thick in the middle and thin at the rim.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(max(smoothstep(0.0, 1.0, facing), 1e-4), edge_softness);

	// Fade where the cone passes into the floor, a wall or the booth.
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -view.z / view.w;
	float contact = clamp((scene_z - (-VERTEX.z)) / contact_fade, 0.0, 1.0);
	contact = isnan(contact) ? 1.0 : contact;

	// Don't blind the camera when it sits inside a beam.
	float near = smoothstep(0.2, 1.2, -VERTEX.z);

	float smoke = noise(world_pos * 1.3 + vec3(0.0, TIME * 0.12, TIME * 0.07));
	smoke = mix(1.0, 0.45 + smoke * 1.1, haze_texture);

	ALBEDO = beam_color * intensity * fade * edge * contact * near * smoke;
}
