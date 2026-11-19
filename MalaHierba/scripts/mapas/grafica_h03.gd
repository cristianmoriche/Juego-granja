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


static var _ultimo_nivel_servidor: int = -1
static var _ultimo_vp_rid: RID = RID()


static func aplicar_calidad_servidor(viewport: Viewport, nivel: int) -> void:
	var n := clampi(nivel, 0, 3)
	var vp_rid := viewport.get_viewport_rid() if viewport != null else RID()
	if _ultimo_nivel_servidor == n and _ultimo_vp_rid == vp_rid:
		return
	_ultimo_nivel_servidor = n
	_ultimo_vp_rid = vp_rid
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 2048, 4096][n], true)
	if viewport != null:
		RenderingServer.viewport_set_positional_shadow_atlas_size(vp_rid, [1024, 1024, 2048, 2048][n], true)
		RenderingServer.viewport_set_anisotropic_filtering_level(vp_rid, [
			RenderingServer.VIEWPORT_ANISOTROPY_2X,
			RenderingServer.VIEWPORT_ANISOTROPY_4X,
			RenderingServer.VIEWPORT_ANISOTROPY_4X,
			RenderingServer.VIEWPORT_ANISOTROPY_8X,
		][n])
		viewport.use_occlusion_culling = true
		viewport.mesh_lod_threshold = [4.0, 2.8, 2.0, 1.2][n]
	var q_ssao: int = [
		RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
	][n]
	RenderingServer.environment_set_ssao_quality(q_ssao, true, 0.5, 1 if n <= 2 else 2, 40.0 if n <= 1 else 50.0, 120.0 if n <= 2 else 180.0)
	var q_ssil: int = RenderingServer.ENV_SSIL_QUALITY_LOW if n >= 3 else RenderingServer.ENV_SSIL_QUALITY_VERY_LOW
	RenderingServer.environment_set_ssil_quality(q_ssil, true, 0.5, 1 if n <= 2 else 2, 32.0 if n < 3 else 50.0, 95.0 if n < 3 else 160.0)
	RenderingServer.environment_set_ssr_half_size(n < 3)
	var vf_size := 64 if n >= 3 else 32
	var vf_depth := 64 if n >= 3 else 48
	RenderingServer.environment_set_volumetric_fog_volume_size(vf_size, vf_depth)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_8)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES)


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
	env.ssr_max_steps = 32 if nivel == 3 else 16
	if mundo.camera_attributes != null:
		mundo.camera_attributes.auto_exposure_enabled = nivel >= 2
	var sol := mapa.get_node_or_null("Sol") as DirectionalLight3D
	if sol != null and not mapa.interior:
		ajustar_sol(sol, nivel)


static func ajustar_sol(sol: DirectionalLight3D, nivel: int) -> void:
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if nivel >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sol.directional_shadow_split_1 = 0.09 if nivel >= 3 else 0.22
	sol.directional_shadow_split_2 = 0.22
	sol.directional_shadow_split_3 = 0.48
	sol.directional_shadow_blend_splits = nivel >= 3
	sol.directional_shadow_fade_start = 0.84
	sol.directional_shadow_max_distance = [48.0, 68.0, 78.0, 115.0][nivel]
	sol.light_angular_distance = [0.0, 0.0, 0.0, 0.45][nivel]
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
	luz.distance_fade_shadow = 12.0 if nivel == 2 else 20.0
	luz.distance_fade_length = 10.0
	if luz is OmniLight3D:
		luz.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID if nivel == 2 else OmniLight3D.SHADOW_CUBE
