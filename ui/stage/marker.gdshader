shader_type spatial;
// Selection and placement markers, drawn on a 2 x 2 quad (QuadMesh size 2).
//   style 0: four corner brackets with a soft glow, for the selected fixture.
//   style 1: a ring with a centre dot, for where a dropped fixture will land.
// With `billboard` on, the quad turns to face the camera. Its size is
// `world_size` metres, but never smaller than `min_px` pixels on screen, so
// it stays readable when you zoom out and hugs the fixture when you zoom in.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 0.71, 0.28, 1.0);
uniform int style = 0;
uniform bool billboard = true;
uniform float world_size = 0.3; // half-width in metres
uniform float min_px = 26.0;    // half-width floor in pixels
uniform float appear = 1.0;     // 0 -> 1 when selected; brackets slide in

varying vec2 p;

void vertex() {
	p = VERTEX.xy;
	vec3 centre_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float depth = max(-centre_view.z, 0.05);
	// One pixel in metres at this depth.
	float px = depth * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float half_size = max(world_size, min_px * px);
	if (style == 0) {
		half_size *= mix(1.6, 1.0, appear);
	}
	if (billboard) {
		POSITION = PROJECTION_MATRIX * vec4(centre_view + vec3(VERTEX.xy * half_size, 0.0), 1.0);
	} else {
		// Lies in the quad's own plane (the surface); scale about its centre.
		vec3 world = (MODEL_MATRIX * vec4(VERTEX * half_size, 1.0)).xyz;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	}
}

float seg(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	float aa = fwidth(length(p)) * 1.2;
	float d;
	float stroke;
	if (style == 0) {
		// Corner brackets: an L in each corner (fold into one quadrant).
		vec2 q = abs(p);
		float c = 0.78;
		float arm = 0.32;
		d = min(seg(q, vec2(c - arm, c), vec2(c, c)), seg(q, vec2(c, c - arm), vec2(c, c)));
		stroke = 0.055;
	} else {
		float r = length(p);
		d = min(abs(r - 0.7), max(r - 0.09, 0.0));
		stroke = 0.05;
	}
	float line = 1.0 - smoothstep(stroke - aa, stroke + aa, d);
	float glow = exp(-d * 14.0) * 0.45;
	float a = clamp(line + glow * (1.0 - line), 0.0, 1.0) * color.a;
	if (style == 0) {
		a *= appear;
	}
	ALBEDO = mix(color.rgb, vec3(1.0), line * 0.25);
	ALPHA = a;
}
