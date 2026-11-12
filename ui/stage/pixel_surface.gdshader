shader_type spatial;
// The light-emitting face of a pixel fixture (LED bar, pixel strip, matrix):
// a grid of pixel cells, each glowing in its own colour, read from a tiny
// texture with one texel per pixel (StageFixture3D writes it every frame:
// RGB = the pixel's colour, alpha = its white).
// Works for any layout: set `grid` to columns x rows and the texture to match.
// Between the LEDs you see the dark lens/housing, like a real bar.
//
// Two ways to draw a cell:
// - led_rows = 0: one LED dot per pixel (a generic bar).
// - led_rows > 0: lines of small LEDs running along the face, `dots_per_pixel`
//   per pixel in each line, like a real SMD bar. Each line has a position
//   across the face and a kind: 0 = colour + white, 1 = colour only (RGB
//   chips), 2 = white only (white chips). Lines sit across the face (V), so a
//   bar with a white line top and bottom and a double RGB line in the middle
//   is row_pos (0.15, 0.4, 0.6, 0.85) with row_kind (2, 1, 1, 2).
render_mode cull_back;

uniform sampler2D pixel_data : source_color, filter_nearest, repeat_disable;
uniform ivec2 grid = ivec2(8, 1);
uniform float energy = 0.0; // brightness of a fully lit pixel (dimmer folded in)
// Size of the face in metres, so dots stay round on a long thin bar.
uniform vec2 face_size = vec2(1.0, 0.05);
// One-dot mode: share of a cell that is dark gap around the LED (0 = cells touch).
uniform float gap : hint_range(0.0, 0.9) = 0.18;
// One-dot mode: 1 = round LED dots, 0 = square segments (a diffused strip).
uniform float roundness : hint_range(0.0, 1.0) = 1.0;
// Light that leaks past an LED's edge, so a lit bar reads as one glowing strip.
uniform float bleed : hint_range(0.0, 1.0) = 0.12;
uniform vec3 housing_color : source_color = vec3(0.027, 0.031, 0.039);

// LED-line mode (see above).
uniform int led_rows : hint_range(0, 8) = 0;
uniform int dots_per_pixel : hint_range(1, 32) = 6;
uniform float dot_size = 0.0035; // LED chip width in metres
uniform float row_pos[8];
uniform int row_kind[8];
uniform vec3 white_tint : source_color = vec3(1.0, 0.96, 0.9);

float dot_mask(float d, float r, float aa) {
	float lit = 1.0 - smoothstep(r - aa, r + aa, d);
	float halo = (1.0 - smoothstep(r, r * 2.5, d)) * bleed;
	return max(lit, halo);
}

void fragment() {
	vec2 g = vec2(max(grid, ivec2(1)));
	vec2 cell_f = UV * g;
	vec2 cell = clamp(floor(cell_f), vec2(0.0), g - 1.0);
	vec2 cell_m = face_size / g;
	vec4 px = texture(pixel_data, (cell + 0.5) / g);
	vec3 rgb = px.rgb;
	vec3 wh = white_tint * px.a;
	vec3 light = vec3(0.0);

	if (led_rows > 0) {
		// Metres from the LED centres: along the face to the nearest chip in
		// this pixel, across it to each line.
		float along = fract(UV.x * g.x * float(dots_per_pixel)) - 0.5;
		float dx = along * face_size.x / (g.x * float(dots_per_pixel));
		float r = dot_size * 0.5;
		for (int i = 0; i < led_rows && i < 8; i++) {
			float dy = (UV.y - row_pos[i]) * face_size.y;
			// Square-ish SMD chips.
			float d = max(abs(dx), abs(dy));
			float aa = max(fwidth(d), 0.00005);
			float m = dot_mask(d, r, aa);
			vec3 c = row_kind[i] == 1 ? rgb : (row_kind[i] == 2 ? wh : rgb + wh);
			light = max(light, c * m);
		}
	} else {
		vec2 local = fract(cell_f) * 2.0 - 1.0; // -1..1 inside the cell
		// Keep dots round in metres, not stretched with the face: measure in
		// units of the cell's shorter side. Square segments (roundness 0)
		// fill their whole cell instead.
		local *= mix(vec2(1.0), cell_m / min(cell_m.x, cell_m.y), roundness);
		vec2 a = abs(local);
		float edge = mix(max(a.x, a.y), length(local), roundness);
		float r = 1.0 - gap;
		float aa = max(fwidth(edge), 0.001);
		float lit = 1.0 - smoothstep(r - aa, r + aa, edge);
		float halo = (1.0 - smoothstep(r, 1.0 + r * 0.5, edge)) * bleed;
		light = (rgb + wh) * max(lit, halo);
	}

	ALBEDO = housing_color;
	METALLIC = 0.2;
	ROUGHNESS = 0.08;
	EMISSION = light * energy;
}
