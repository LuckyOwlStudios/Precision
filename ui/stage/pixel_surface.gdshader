shader_type spatial;
// The light-emitting face of a pixel fixture (LED bar, pixel strip, matrix):
// a grid of LED cells, each glowing in its own colour, read from a tiny
// texture with one texel per pixel (StageFixture3D writes it every frame).
// Works for any layout: set `grid` to columns x rows and the texture to match.
// Between the cells you see the dark lens/housing, like a real bar.
render_mode cull_back;

// One texel per pixel: x = column, y = row. Colour is the pixel's output.
uniform sampler2D pixel_data : source_color, filter_nearest, repeat_disable;
uniform ivec2 grid = ivec2(8, 1);
uniform float energy = 0.0; // brightness of a fully lit pixel (dimmer folded in)
// Share of a cell that is dark gap around the LED (0 = cells touch).
uniform float gap : hint_range(0.0, 0.9) = 0.18;
// 1 = round LED dots, 0 = square segments (a diffused strip).
uniform float roundness : hint_range(0.0, 1.0) = 1.0;
// Light that leaks past the cell edge, so a lit bar reads as one glowing strip.
uniform float bleed : hint_range(0.0, 1.0) = 0.12;
// Size of the face in metres, so dots stay round on a long thin bar.
uniform vec2 face_size = vec2(1.0, 0.05);
uniform vec3 housing_color : source_color = vec3(0.027, 0.031, 0.039);

void fragment() {
	vec2 g = vec2(max(grid, ivec2(1)));
	vec2 cell_f = UV * g;
	vec2 cell = clamp(floor(cell_f), vec2(0.0), g - 1.0);
	vec2 local = fract(cell_f) * 2.0 - 1.0; // -1..1 inside the cell

	// Keep dots round in metres, not stretched with the face: measure in units
	// of the cell's shorter side, so a 1 m x 5 cm bar of 28 pixels gets round
	// dots (centred in each cell) rather than ovals.
	vec2 cell_m = face_size / g;
	// Square segments (roundness 0) fill their whole cell instead.
	local *= mix(vec2(1.0), cell_m / min(cell_m.x, cell_m.y), roundness);
	vec2 a = abs(local);
	float edge = mix(max(a.x, a.y), length(local), roundness);
	float r = 1.0 - gap;
	float aa = max(fwidth(edge), 0.001);
	float lit = 1.0 - smoothstep(r - aa, r + aa, edge);
	float halo = (1.0 - smoothstep(r, 1.0 + r * 0.5, edge)) * bleed;

	vec3 c = texture(pixel_data, (cell + 0.5) / g).rgb;
	ALBEDO = housing_color;
	METALLIC = 0.2;
	ROUGHNESS = 0.08;
	EMISSION = c * energy * max(lit, halo);
}
