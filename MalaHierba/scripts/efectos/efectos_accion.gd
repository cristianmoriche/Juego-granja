class_name EfectosAccion
extends RefCounted
## Partículas 3D discretas y realistas para acciones del juego (T13):
## tierra al labrar, gotas al regar, hojas al cosechar, chispas y esquirlas al picar y astillas al talar.

const GRUPO_EFECTO := "efecto_accion"


## Lanza el efecto correspondiente en `pos` (coordenadas globales) colgando los nodos de `padre`.
static func soltar(padre: Node3D, tipo: String, pos: Vector3, tinte: Color = Color.WHITE) -> void:
	if padre == null or not is_instance_valid(padre) or not padre.is_inside_tree():
		return
	var cache := _cache_de(padre)
	match tipo:
		"labrar":
			_emitir(padre, cache, "tierra", pos + Vector3(0.0, 0.06, 0.0), _curva_decreciente(cache, 1.0, 0.2), {
				"cantidad": 18, "vida": 0.48, "explosivo": 0.90,
				"extents": Vector3(0.30, 0.03, 0.30),
				"dir": Vector3(0.0, 1.0, 0.0), "apertura": 48.0,
				"vmin": 1.6, "vmax": 2.9, "gravedad": Vector3(0.0, -9.8, 0.0),
				"giro": 220.0, "emin": 0.75, "emax": 1.45,
			})
		"regar":
			_emitir(padre, cache, "agua", pos + Vector3(0.0, 0.40, 0.0), _curva_decreciente(cache, 1.0, 0.35), {
				"cantidad": 22, "vida": 0.42, "explosivo": 0.72,
				"extents": Vector3(0.28, 0.10, 0.28),
				"dir": Vector3(0.0, 0.2, 0.0), "apertura": 55.0,
				"vmin": 1.1, "vmax": 2.1, "gravedad": Vector3(0.0, -10.5, 0.0),
				"giro": 40.0, "emin": 0.85, "emax": 1.35,
			})
		"cosechar":
			_emitir(padre, cache, "hoja", pos + Vector3(0.0, 0.40, 0.0), _curva_decreciente(cache, 1.0, 0.3), {
				"cantidad": 16, "vida": 0.60, "explosivo": 0.88,
				"radio": 0.22,
				"dir": Vector3(0.0, 0.58, 0.0), "apertura": 80.0,
				"vmin": 1.6, "vmax": 2.7, "gravedad": Vector3(0.0, -4.4, 0.0),
				"freno": 2.0, "giro": 260.0, "emin": 0.85, "emax": 1.35,
			})
		"picar":
			var clave_roca := "esquirla_" + tinte.to_html(false)
			_asegurar_esquirla(cache, clave_roca, tinte)
			_emitir(padre, cache, clave_roca, pos + Vector3(0.0, 0.38, 0.0), _curva_decreciente(cache, 1.0, 0.25), {
				"cantidad": 14, "vida": 0.46, "explosivo": 0.94,
				"radio": 0.16,
				"dir": Vector3(0.0, 0.68, 0.0), "apertura": 74.0,
				"vmin": 2.2, "vmax": 3.8, "gravedad": Vector3(0.0, -10.5, 0.0),
				"giro": 320.0, "emin": 0.8, "emax": 1.35,
			})
			_emitir(padre, cache, "chispa", pos + Vector3(0.0, 0.42, 0.0), _curva_decreciente(cache, 1.0, 0.15), {
				"cantidad": 10, "vida": 0.28, "explosivo": 0.96,
				"radio": 0.10,
				"dir": Vector3(0.0, 0.62, 0.0), "apertura": 78.0,
				"vmin": 3.2, "vmax": 5.0, "gravedad": Vector3(0.0, -7.2, 0.0),
				"giro": 180.0, "emin": 0.75, "emax": 1.25,
			})
		"talar":
			_emitir(padre, cache, "astilla", pos + Vector3(0.0, 0.36, 0.0), _curva_decreciente(cache, 1.0, 0.25), {
				"cantidad": 16, "vida": 0.50, "explosivo": 0.92,
				"radio": 0.18,
				"dir": Vector3(0.0, 0.55, 0.0), "apertura": 82.0,
				"vmin": 2.2, "vmax": 3.6, "gravedad": Vector3(0.0, -10.0, 0.0),
				"giro": 340.0, "emin": 0.85, "emax": 1.4,
			})


static func _emitir(padre: Node3D, cache: Dictionary, tipo_malla: String, pos: Vector3, curva: Curve, cfg: Dictionary) -> void:
	var p := CPUParticles3D.new()
	p.top_level = true
	p.add_to_group(GRUPO_EFECTO)
	p.one_shot = true
	p.local_coords = false
	p.amount = int(cfg["cantidad"])
	p.lifetime = float(cfg["vida"])
	p.explosiveness = float(cfg["explosivo"])
	p.mesh = cache["mallas"][tipo_malla]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cfg.has("extents"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = cfg["extents"]
	elif cfg.has("radio"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(cfg["radio"])
	p.direction = cfg["dir"]
	p.spread = float(cfg["apertura"])
	p.initial_velocity_min = float(cfg["vmin"])
	p.initial_velocity_max = float(cfg["vmax"])
	p.gravity = cfg["gravedad"]
	if cfg.has("freno"):
		p.damping_min = float(cfg["freno"]) * 0.7
		p.damping_max = float(cfg["freno"])
	p.particle_flag_align_y = bool(cfg.get("alinear", true))
	var giro := float(cfg.get("giro", 0.0))
	if giro > 0.0:
		p.particle_flag_rotate_y = true
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.angular_velocity_min = -giro
		p.angular_velocity_max = giro
	p.scale_amount_min = float(cfg["emin"])
	p.scale_amount_max = float(cfg["emax"])
	p.scale_amount_curve = curva
	p.color_ramp = cache["rampas"].get(tipo_malla, null)
	padre.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	# Salvaguarda por si en modo sin pantalla `finished` tarda: Timer hijo ligado al propio ciclo de vida de `p`.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = p.lifetime + 0.35
	timer.timeout.connect(p.queue_free)
	p.add_child(timer)
	timer.start()


static func _cache_de(padre: Node3D) -> Dictionary:
	if padre.has_meta("_efectos_accion_res"):
		return padre.get_meta("_efectos_accion_res") as Dictionary
	var mallas: Dictionary = {}
	var rampas: Dictionary = {}

	# 1. Tierra al labrar: terrones orgánicos oscuros mates.
	var bt := SphereMesh.new()
	bt.radius = 0.034
	bt.height = 0.056
	bt.radial_segments = 5
	bt.rings = 2
	bt.material = _mat(Color(0.30, 0.21, 0.14), 0.96, false, 0.0)
	mallas["tierra"] = bt
	rampas["tierra"] = _rampa(Color(0.95, 0.92, 0.88), Color(0.75, 0.70, 0.65))

	# 2. Gotas al regar: azul grisáceo translúcido natural.
	var ba := SphereMesh.new()
	ba.radius = 0.020
	ba.height = 0.055
	ba.radial_segments = 6
	ba.rings = 3
	var ma := _mat(Color(0.62, 0.75, 0.83, 0.65), 0.15, false, 0.0)
	ma.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ba.material = ma
	mallas["agua"] = ba
	rampas["agua"] = _rampa(Color(1.0, 1.0, 1.0, 0.9), Color(0.9, 0.95, 1.0, 0.1))

	# 3. Hojas y tallos al cosechar: verde oliva y paja discreta, inclinadas según el vuelo.
	var bh := BoxMesh.new()
	bh.size = Vector3(0.088, 0.014, 0.044)
	bh.material = _mat(Color(0.26, 0.42, 0.17), 0.82, true, 0.0)
	mallas["hoja"] = bh
	rampas["hoja"] = _rampa(Color(0.90, 1.0, 0.85), Color(0.85, 0.82, 0.55))

	# 4. Chispas al picar: trazos cálidos de impacto metálico orientados en vuelo.
	var bc := BoxMesh.new()
	bc.size = Vector3(0.015, 0.062, 0.015)
	var mc := _mat(Color(0.96, 0.68, 0.30), 0.40, false, 1.35)
	mc.emission = Color(0.90, 0.52, 0.16)
	bc.material = mc
	mallas["chispa"] = bc
	rampas["chispa"] = _rampa(Color(1.0, 0.95, 0.78), Color(0.65, 0.28, 0.08))

	# 5. Astillas al talar: madera natural astillada orientada transversalmente para girar al volar.
	var bas := BoxMesh.new()
	bas.size = Vector3(0.115, 0.022, 0.026)
	bas.material = _mat(Color(0.56, 0.41, 0.25), 0.88, false, 0.0)
	mallas["astilla"] = bas
	rampas["astilla"] = _rampa(Color(1.0, 0.95, 0.88), Color(0.75, 0.66, 0.54))

	var cache := {"mallas": mallas, "rampas": rampas, "curvas": {}}
	padre.set_meta("_efectos_accion_res", cache)
	return cache


static func _asegurar_esquirla(cache: Dictionary, clave: String, tinte: Color) -> void:
	if (cache["mallas"] as Dictionary).has(clave):
		return
	var color_roca := Color(0.45, 0.44, 0.42) if tinte == Color.WHITE else Color(tinte.r * 0.88, tinte.g * 0.88, tinte.b * 0.88)
	var be := SphereMesh.new()
	be.radius = 0.032
	be.height = 0.060
	be.radial_segments = 4
	be.rings = 2
	be.material = _mat(color_roca, 0.92, false, 0.0)
	cache["mallas"][clave] = be
	cache["rampas"][clave] = _rampa(Color.WHITE, Color(0.78, 0.76, 0.74))


static func _mat(color: Color, rugosidad: float, doble_cara: bool, emision: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rugosidad
	m.vertex_color_use_as_albedo = true
	if doble_cara:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emision > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emision
	return m


static func _rampa(inicio: Color, fin: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, inicio)
	g.set_color(1, fin)
	return g


static func _curva_decreciente(cache: Dictionary, a: float, b: float) -> Curve:
	var ck := "%.2f_%.2f" % [a, b]
	var curvas: Dictionary = cache["curvas"]
	if curvas.has(ck):
		return curvas[ck] as Curve
	var c := Curve.new()
	c.add_point(Vector2(0.0, a))
	c.add_point(Vector2(0.65, lerp(a, b, 0.35)))
	c.add_point(Vector2(1.0, b))
	curvas[ck] = c
	return c
