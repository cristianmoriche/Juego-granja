class_name CicloDia
extends DirectionalLight3D
## Luz del Sol según la hora del juego: amanecer cálido, mediodía, atardecer, noche azul oscura.
## También regula el brillo del cielo y el color de la niebla. En interiores no hay sol.

# Por estación (primavera, verano, otoño, invierno): minuto del amanecer y del atardecer, y altura máxima del sol.
const AMANECER: Array[int] = [405, 360, 435, 450]
const ATARDECER: Array[int] = [1230, 1290, 1185, 1110]
const ELEVACION_MAX: Array[float] = [58.0, 68.0, 44.0, 30.0]
const CREPUSCULO := 45.0       # minutos de transición entre el día y la noche

var _env: Environment = null
var _mat_cielo: Material = null
var _cielo_h03: CieloH03
var _cargador: Node = null
var _interior: bool = false
var _es_mina: bool = false
var _color_niebla: Color = Color(0.72, 0.78, 0.85)
var _densidad_niebla: float = 0.0
var _dir_base: Vector3 = Vector3(-0.35, -0.8, -0.5).normalized()
var _color_base: Color = Color(1.0, 0.96, 0.88)
var _energia_base: float = 1.0
var _fuerza_cielo: float = 1.0
var _configurado: bool = false


func _ready() -> void:
	shadow_enabled = true
	directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	directional_shadow_max_distance = 90.0
	shadow_bias = 0.05
	shadow_normal_bias = 1.2


## Lo llama Mapa cuando conoce la información del mapa. info_sol: {dir, color, energia} o {}.
func configurar(info_sol: Dictionary, env: Environment, mat_cielo: Material, es_interior: bool, color_niebla: Color, fuerza_cielo: float, densidad: float, cargador: Node = null) -> void:
	_env = env
	_mat_cielo = mat_cielo
	_cargador = cargador
	_interior = es_interior
	_es_mina = (_cargador != null and String(_cargador.get("id_mapa")) == "mina_interior")
	_color_niebla = color_niebla
	_fuerza_cielo = fuerza_cielo
	_densidad_niebla = densidad
	if not _interior and _env != null and _env.sky != null:
		_cielo_h03 = CieloH03.new()
		_env.sky.sky_material = _cielo_h03.material
	if info_sol.has("dir"):
		var d: Array = info_sol["dir"]
		var v := Vector3(float(d[0]), float(d[1]), float(d[2]))
		if v.length() > 0.01:
			_dir_base = v.normalized()
	if info_sol.has("color"):
		var c: Array = info_sol["color"]
		_color_base = Color(float(c[0]), float(c[1]), float(c[2]))
	_energia_base = clampf(float(info_sol.get("energia", 1.0)), 0.3, 3.0)
	_configurado = true
	if _interior:
		visible = false
		light_energy = 0.0
	if not Juego.hora_cambiada.is_connected(_al_cambiar_hora):
		Juego.hora_cambiada.connect(_al_cambiar_hora)
		Juego.dia_nuevo.connect(actualizar)
		if Juego.has_signal("estacion_cambiada"):
			Juego.estacion_cambiada.connect(actualizar)
		if Juego.has_signal("clima_cambiado"):
			Juego.clima_cambiado.connect(func(_c: String) -> void: actualizar())
	actualizar()


func _al_cambiar_hora(_m: int) -> void:
	actualizar()


## Calcula la posición, color e intensidad del sol (o de la luna) para la hora actual.
func actualizar() -> void:
	if not _configurado:
		return
	var m := float(Juego.minutos)
	var e := clampi(Juego.estacion, 0, 3)
	var sale := float(AMANECER[e])
	var se_pone := float(ATARDECER[e])
	var lluvia := Juego.esta_lloviendo()
	var tormenta := Juego.clima == "tormenta"
	var nieve := Juego.esta_nevando()
	var niebla := Juego.intensidad_neblina(sale)

	if _interior:
		visible = false
		light_energy = 0.0
		if not _es_mina and _env != null:
			var luz_dia := clampf(sin(clampf((m - sale) / (se_pone - sale), 0.0, 1.0) * PI), 0.0, 1.0) if (m >= sale and m <= se_pone) else 0.0
			var es_atardecer := smoothstep(se_pone - 95.0, se_pone + 10.0, m)
			var factor_ext := clampf(luz_dia * (1.0 - es_atardecer * 0.85), 0.0, 1.0)
			factor_ext *= 0.43 if lluvia else lerpf(1.0, 0.56, niebla)
			var calidez_hora := clampf((1.0 - smoothstep(0.15, 0.72, luz_dia)) * 0.55 + es_atardecer * 0.45, 0.0, 1.0)
			_env.ambient_light_color = Color(0.76, 0.72, 0.66).lerp(Color(0.84, 0.62, 0.40), calidez_hora * 0.82)
			_env.ambient_light_energy = lerpf(0.36, 0.50, factor_ext)
			if _cargador != null and _cargador.has_method("actualizar_iluminacion_hora"):
				_cargador.call("actualizar_iluminacion_hora", 1.0, 1.0, factor_ext)
				_cargador.call("iluminar_ventanas_h03", factor_ext, (m - sale) / (se_pone - sale), lluvia)
		elif _cargador != null and _cargador.has_method("actualizar_iluminacion_hora"):
			_cargador.call("actualizar_iluminacion_hora", 1.0, 1.0, 1.0)
		return

	# 0 = día pleno, 1 = noche cerrada.
	var noche := 0.0
	if m < sale - CREPUSCULO:
		noche = 1.0
	elif m < sale:
		noche = 1.0 - (m - (sale - CREPUSCULO)) / CREPUSCULO
	elif m <= se_pone:
		noche = 0.0
	elif m < se_pone + CREPUSCULO:
		noche = (m - se_pone) / CREPUSCULO
	else:
		noche = 1.0
	noche = smoothstep(0.0, 1.0, noche)

	# Sol: arco de este a oeste con la altura máxima de la estación.
	var t := clampf((m - sale) / (se_pone - sale), 0.0, 1.0)
	var elev := sin(t * PI)
	var grados := lerpf(3.0, ELEVACION_MAX[e], elev)
	var rad := deg_to_rad(grados)
	var h0 := atan2(_dir_base.x, _dir_base.z)
	var h := h0 + (0.5 - t) * PI * 0.85
	var dir_dia := Vector3(sin(h) * cos(rad), -sin(rad), cos(h) * cos(rad)).normalized()
	var calidez := 1.0 - smoothstep(0.0, 0.55, elev)       # 1 con el sol bajo
	var crep_manana := 1.0 - smoothstep(sale + 25.0, sale + 150.0, m)
	var crep_tarde := smoothstep(se_pone - 110.0, se_pone + 15.0, m)
	var sol_cenit := _color_base.lerp(Color(1.0, 0.98, 0.93), 0.48)
	var sol_bajo := Color(1.0, 0.74, 0.48).lerp(Color(1.0, 0.48, 0.18), crep_tarde)
	var color_dia := sol_cenit.lerp(sol_bajo, maxf(calidez * 0.85, crep_tarde * 0.92))
	if e == 2:
		color_dia = color_dia.lerp(Color(1.0, 0.84, 0.62), 0.26)
	elif e == 3:
		color_dia = color_dia.lerp(Color(0.88, 0.94, 1.0), 0.30)
	var energia_dia := _energia_base * lerpf(0.54, 1.02, smoothstep(0.15, 0.85, elev)) * lerpf(1.0, 0.70, crep_tarde)

	# Luna: azul y suave, desde arriba.
	var dir_noche := Vector3(0.35, -0.82, -0.45).normalized()
	var color_noche := Color(0.42, 0.52, 0.95)
	var energia_noche := 0.22

	var dir := dir_dia.slerp(dir_noche, noche)
	var color := color_dia.lerp(color_noche, noche)
	var energia := lerpf(energia_dia, energia_noche, noche)

	if tormenta:
		color = color.lerp(Color(0.56, 0.62, 0.72), 0.62)
		energia *= 0.38
	elif lluvia:
		color = color.lerp(Color(0.72, 0.76, 0.82), 0.45)
		energia *= 0.55
	elif nieve:
		color = color.lerp(Color(0.84, 0.89, 0.98), 0.35)
		energia *= 0.78
	else:
		energia *= lerpf(1.0, 0.48, niebla)

	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), global_position)
	light_color = color
	light_energy = energia
	RenderingServer.global_shader_parameter_set("humedad_h03", 1.0 if tormenta else (0.77 if lluvia else niebla * 0.27))
	RenderingServer.global_shader_parameter_set("viento_h03", 1.0 if tormenta else (0.59 if lluvia else (0.39 if nieve else 0.24)))
	var luz_agua := lerpf(0.46, 1.0, smoothstep(0.0, 0.92, elev))
	luz_agua *= (0.42 if tormenta else 0.72) if lluvia else lerpf(1.0, 0.66, niebla)
	RenderingServer.global_shader_parameter_set("luz_agua_h03", lerpf(luz_agua, 0.045, noche))

	if _env != null:
		var factor_cielo := 0.42 if tormenta else (0.68 if lluvia else (0.82 if nieve else 1.0))
		var curva_cielo := lerpf(0.44, 0.78, smoothstep(0.15, 0.90, elev)) * lerpf(1.0, 0.48, crep_tarde)
		var brillo := lerpf(curva_cielo, 0.04, noche) * _fuerza_cielo * factor_cielo
		if _cielo_h03 != null:
			_cielo_h03.actualizar(m, sale, se_pone, _fuerza_cielo, -dir, color, noche, lluvia, tormenta, nieve, niebla)
		elif _mat_cielo is PanoramaSkyMaterial:
			(_mat_cielo as PanoramaSkyMaterial).energy_multiplier = brillo
		elif _mat_cielo is ProceduralSkyMaterial:
			(_mat_cielo as ProceduralSkyMaterial).sky_energy_multiplier = brillo
		var amb_manana := Color(0.20, 0.26, 0.40)
		var amb_mediodia := Color(0.18, 0.24, 0.36)
		var amb_tarde := Color(0.28, 0.16, 0.24)
		var amb_dia := amb_mediodia.lerp(amb_manana, crep_manana * 0.6).lerp(amb_tarde, crep_tarde * (1.0 - noche) * 0.85)
		_env.ambient_light_color = amb_dia.lerp(Color(0.08, 0.12, 0.26), noche)
		_env.ambient_light_sky_contribution = lerpf(0.86, 0.42, maxf(crep_tarde * 0.45, noche))
		var amb_e := lerpf(0.45, 0.58, elev) * lerpf(1.0, 0.78, crep_tarde)
		_env.ambient_light_energy = lerpf(amb_e * lerpf(1.0, 0.78, niebla), 0.52, noche)
		var gris := Color(0.45, 0.49, 0.56) if tormenta else Color(0.55, 0.58, 0.62)
		var fn := _color_niebla
		if e == 3:
			fn = fn.lerp(Color(0.80, 0.86, 0.94), 0.55)
		elif e == 2:
			fn = fn.lerp(Color(0.84, 0.74, 0.60), 0.28)
		fn = fn.lerp(Color(0.76, 0.79, 0.88), crep_manana * 0.35)
		fn = fn.lerp(Color(0.72, 0.44, 0.30), crep_tarde * (1.0 - noche) * 0.78)
		fn = fn.lerp(Color(0.025, 0.035, 0.08), noche)
		if tormenta or lluvia:
			fn = fn.lerp(gris, 0.65 if tormenta else 0.5)
		_env.fog_light_color = fn
		var mult_niebla := 2.3 if tormenta else (1.6 if lluvia else (1.45 if e == 3 else lerpf(1.0, 1.32, crep_manana)))
		_env.fog_density = _densidad_niebla * mult_niebla * 0.77 + niebla * 0.012
		_env.fog_height = 3.5
		_env.fog_height_density = niebla * 0.065
		_env.fog_sun_scatter = 0.24 * (1.0 - noche) * (1.0 - niebla * 0.6)
		_env.fog_enabled = _env.fog_density > 0.0
		_env.volumetric_fog_density = 0.0028 + crep_manana * 0.004 + noche * 0.005 + niebla * 0.013 + (0.0045 if lluvia else 0.0)
		_env.volumetric_fog_albedo = Color(0.82, 0.87, 0.92).lerp(Color(0.50, 0.61, 0.75), noche * 0.46)

	if _cargador != null and _cargador.has_method("actualizar_iluminacion_hora"):
		var oscuro := clampf(crep_tarde * 1.15 + noche, 0.0, 1.0)
		var factor_ventanas := clampf(maxf(oscuro, 0.36 if lluvia else 0.0), 0.0, 1.0)
		var factor_luces := clampf(maxf(0.04, maxf(oscuro * 1.15, 0.45 if lluvia else 0.0)), 0.04, 1.0)
		_cargador.call("actualizar_iluminacion_hora", factor_ventanas, factor_luces)
	var lm := get_parent().get_node_or_null("LightmapMapa") as LightmapGI if get_parent() != null else null
	if lm != null:
		lm.visible = noche < 0.65
