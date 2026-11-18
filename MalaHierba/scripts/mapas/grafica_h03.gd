class_name GraficaH03
extends RefCounted
## Ajusta los efectos de Forward+ sin modificar la proyección de las cámaras del juego.

static func preparar_entorno(env: Environment, interior: bool, mina: bool) -> void:
	env.ssao_radius = 1.15 if interior else 1.55
	env.ssao_intensity = 1.12
	env.ssao_horizon = 0.08
	env.ssil_radius = 2.0 if interior else 3.0
	env.ssil_intensity = 0.54 if mina else 0.74
	env.ssil_sharpness = 0.95
	env.ssr_max_steps = 42
	env.ssr_depth_tolerance = 0.16
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.8
	env.sdfgi_cascades = 3 if interior else 4
	env.sdfgi_min_cell_size = 0.19 if interior else 0.32
	env.sdfgi_bounce_feedback = 0.34
	env.sdfgi_read_sky_light = not interior
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 0.62 if mina else (0.75 if interior else 0.57)
	env.volumetric_fog_length = 26.0 if interior else 82.0
	env.volumetric_fog_density = 0.008 if mina else (0.012 if interior else 0.003)
	env.volumetric_fog_albedo = Color(0.69, 0.70, 0.76) if mina else Color(0.83, 0.87, 0.91)
	env.volumetric_fog_anisotropy = 0.52 if interior else 0.63
	env.volumetric_fog_ambient_inject = 0.20
	env.volumetric_fog_gi_inject = 0.35
	env.volumetric_fog_sky_affect = 0.30
	env.volumetric_fog_temporal_reprojection_amount = 0.82


static func exposicion(interior: bool) -> CameraAttributesPhysical:
	var atributos := CameraAttributesPhysical.new()
	atributos.auto_exposure_min_exposure_value = -2.0 if interior else -2.8
	atributos.auto_exposure_max_exposure_value = 1.0 if interior else 1.1
	atributos.auto_exposure_scale = 0.12 if interior else 0.14
	atributos.auto_exposure_speed = 0.62
	return atributos


static func ajustar_entorno(mundo: WorldEnvironment, nivel: int) -> void:
	var env := mundo.environment
	env.ssao_enabled = nivel >= 1
	env.ssr_enabled = nivel >= 2
	if not mundo.get_parent() is Mapa:
		return
	var mapa := mundo.get_parent() as Mapa
	env.ssil_enabled = nivel >= 2
	env.sdfgi_enabled = nivel >= 3
	env.volumetric_fog_enabled = nivel >= 2
	env.ssr_max_steps = 64 if nivel == 3 else 34
	if mundo.camera_attributes != null:
		mundo.camera_attributes.auto_exposure_enabled = nivel >= 2
	var sol := mapa.get_node_or_null("Sol") as DirectionalLight3D
	if sol != null and not mapa.interior:
		ajustar_sol(sol, nivel)


static func ajustar_sol(sol: DirectionalLight3D, nivel: int) -> void:
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if nivel >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sol.directional_shadow_split_1 = 0.09
	sol.directional_shadow_split_2 = 0.22
	sol.directional_shadow_split_3 = 0.48
	sol.directional_shadow_blend_splits = nivel >= 2
	sol.directional_shadow_fade_start = 0.84
	sol.directional_shadow_max_distance = [55.0, 76.0, 104.0, 125.0][nivel]
	sol.light_angular_distance = [0.0, 0.0, 0.24, 0.53][nivel]
	sol.shadow_bias = 0.035
	sol.shadow_normal_bias = 1.2
	sol.shadow_blur = 1.0


static func ajustar_luz(luz: Light3D, nivel: int) -> void:
	if luz.has_meta("sin_sombra"):
		luz.shadow_enabled = false
		luz.distance_fade_enabled = true
		luz.distance_fade_begin = 32.0
		luz.distance_fade_length = 8.0
		return
	luz.shadow_enabled = nivel >= 2 and luz.light_energy > 0.065
	luz.shadow_blur = 1.18
	luz.shadow_bias = 0.055
	luz.shadow_normal_bias = 0.9
	luz.distance_fade_enabled = true
	luz.distance_fade_begin = 34.0
	luz.distance_fade_shadow = 15.0 if nivel == 2 else 24.0
	luz.distance_fade_length = 10.0
	if luz is OmniLight3D:
		luz.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID if nivel == 2 else OmniLight3D.SHADOW_CUBE
