class_name StageLook
extends RefCounted
## How the 3D stage is rendered: shading mode, haze amount, quality level and
## the club-room environment (tonemapping, glow, fog, reflections, ambient occlusion).
## Pure visuals: nothing here touches DMX or the show. Haze and shading are saved
## per machine in user://stage_look.cfg. Quality is a Settings choice (AppSettings,
## because it depends on the computer, not the show); the stage view copies it here.

signal changed

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
## Like a 3D app's viewport shading. WORK: the house lights are on, the room is
## lit evenly so you can see and place the rig. SHOW: the dark club with only
## the fixtures (and haze) lighting it, the way the audience sees it.
enum Shading { WORK, SHOW }

const QUALITY_NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
const SHADING_NAMES: PackedStringArray = ["Work", "Show"]
const SAVE_PATH := "user://stage_look.cfg"
## What a fresh install starts with, and what the bottom-bar labels reset to.
const DEFAULT_HAZE := 0.45
const DEFAULT_QUALITY := Quality.HIGH

## 0 = clean air, 1 = thick haze. Beams and light shafts read more in haze.
var haze: float = DEFAULT_HAZE:
	set(v):
		haze = clampf(v, 0.0, 1.0)
		changed.emit()
var quality: Quality = DEFAULT_QUALITY:
	set(v):
		quality = v
		changed.emit()
var shading: Shading = Shading.SHOW:
	set(v):
		shading = v
		changed.emit()

## Forward+ has volumetric fog, SSR, SSAO and glow that behaves; the
## Compatibility renderer gets a simpler look (beam cones still carry the haze).
var forward_plus: bool = RenderingServer.get_current_rendering_method() == "forward_plus"


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	haze = float(cfg.get_value("stage", "haze", haze))
	shading = clampi(int(cfg.get_value("stage", "shading", shading)), 0, Shading.SHOW) as Shading


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stage", "haze", haze)
	cfg.set_value("stage", "shading", shading)
	cfg.save(SAVE_PATH)


func work_lights() -> bool:
	return shading == Shading.WORK


# ---------------------------------------------------------------- per-fixture choices

## Real shadows from moving heads (the beam stops at the booth, people, truss).
func mover_shadows() -> bool:
	return forward_plus and quality >= Quality.MEDIUM


## Shadows from pars, bars and strobes too.
func wash_shadows() -> bool:
	return forward_plus and quality >= Quality.HIGH


## Lights feed the volumetric haze (the light shafts). Off on Low, and with the
## work lights on (a lit room washes the shafts out and they only get in the way).
func volumetric() -> bool:
	return forward_plus and quality >= Quality.MEDIUM and haze > 0.001 and not work_lights()


## How strongly the fake beam cones show. Some beam is always drawn so a
## programmer can see where things point even in clean air or a lit room.
func beam_strength() -> float:
	if work_lights():
		return lerpf(0.3, 0.6, haze)
	return lerpf(0.35, 1.25, haze)


func msaa() -> Viewport.MSAA:
	match quality:
		Quality.LOW:
			return Viewport.MSAA_2X
		Quality.ULTRA:
			return Viewport.MSAA_8X
	return Viewport.MSAA_4X


func shadow_atlas_size() -> int:
	return 2048 if quality <= Quality.MEDIUM else 4096


# ---------------------------------------------------------------- environment

## A dark club room: almost no ambient light so the fixtures do the work.
func build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("050608")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2a3140")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	apply(env)
	return env


## Re-tune an environment for the current shading, haze and quality.
func apply(env: Environment) -> void:
	if work_lights():
		# House lights: a neutral grey room and flat, even ambient so every
		# piece of truss and every fixture body reads, lit or not.
		env.background_color = Color("3b4049")
		env.ambient_light_color = Color("d9dde6")
		env.ambient_light_energy = 0.9 if forward_plus else 1.1
	else:
		# Enough ambient to see the rig when every light is off, low enough
		# that a single par paints the room.
		env.background_color = Color("050608")
		env.ambient_light_color = Color("2a3140")
		env.ambient_light_energy = 0.35 if forward_plus else 0.55

	if forward_plus:
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
		env.tonemap_white = 6.0
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Glow: lenses and hot spots bloom. Compatibility washes the frame grey
	# with glow on, so only Forward+ gets it.
	env.glow_enabled = forward_plus
	env.glow_normalized = false
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.6 if work_lights() else 1.0 # in a lit room only the lenses bloom
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 0.8, 1.0, 0.7, 0.5, 0.0][i])

	# Haze: volumetric fog lit by every fixture.
	env.volumetric_fog_enabled = volumetric()
	env.volumetric_fog_density = lerpf(0.002, 0.03, haze)
	env.volumetric_fog_albedo = Color(0.9, 0.92, 1.0)
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_anisotropy = 0.55 # forward scatter: beams glow when you look into them
	env.volumetric_fog_length = 28.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = quality >= Quality.HIGH
	env.volumetric_fog_temporal_reprojection_amount = 0.85
	if forward_plus:
		match quality:
			Quality.MEDIUM:
				RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
			Quality.HIGH:
				RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
			Quality.ULTRA:
				RenderingServer.environment_set_volumetric_fog_volume_size(192, 128)
		RenderingServer.environment_set_volumetric_fog_filter_active(quality >= Quality.HIGH)

	env.ssao_enabled = forward_plus and quality >= Quality.MEDIUM
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.15
	env.ssr_enabled = forward_plus and quality >= Quality.HIGH
	env.ssr_max_steps = 48 if quality == Quality.HIGH else 96
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssil_enabled = forward_plus and quality == Quality.ULTRA
	env.ssil_intensity = 0.8
