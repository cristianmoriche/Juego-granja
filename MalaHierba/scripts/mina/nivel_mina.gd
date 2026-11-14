class_name NivelMina
extends Node3D
## Gestor de los 20 niveles de la mina (T26):
## - Niveles 1 y 2 mantienen la cueva base de Blender para conservar compatibilidad total con L4b/M2/M1,
##   añadiendo antorchas, ascensor cada 5 niveles, puntos de aparición de enemigos y bajada al nivel 3.
## - Niveles 3..20 generan por semilla una caverna procedural de superficie creciente (~1,2× en el 3 hasta ~3× en el 20),
##   con 4 ambientaciones (piedra 1-5, húmeda con agua 6-10, cristal 11-15, magma 16-20), antorchas y ascensor.

const ID_MAPA := "mina_interior"
const MAX_NIVEL := 20
const PASO := 2.5
const CEL_BASE := 36                 # macro-celdas de 2,5x2,5 m equivalentes a 1x (~225 m² pisables)
const CAPA_SOLO_JUGADOR := 64
const NIVELES_ASCENSOR: Array[int] = [1, 5, 10, 15, 20]

const AMBIENTACIONES := {
	"piedra": {
		"nombre": "Galerías de piedra",
		"roca": Color(0.32, 0.30, 0.33),
		"suelo": Color(0.28, 0.26, 0.29),
		"niebla": Color(0.026, 0.030, 0.042),
		"ambiente": Color(0.24, 0.27, 0.36),
		"luz_dir": Color(0.56, 0.62, 0.78),
		"energia_amb": 0.48,
		"densidad": 0.016,
		"rugosidad": 0.90,
	},
	"humeda": {
		"nombre": "Grutas húmedas",
		"roca": Color(0.17, 0.23, 0.27),
		"suelo": Color(0.14, 0.20, 0.24),
		"niebla": Color(0.018, 0.048, 0.072),
		"ambiente": Color(0.20, 0.38, 0.50),
		"luz_dir": Color(0.42, 0.70, 0.88),
		"energia_amb": 0.54,
		"densidad": 0.020,
		"rugosidad": 0.34,
	},
	"cristal": {
		"nombre": "Cavernas de cristal",
		"roca": Color(0.20, 0.17, 0.30),
		"suelo": Color(0.18, 0.15, 0.26),
		"niebla": Color(0.036, 0.022, 0.068),
		"ambiente": Color(0.34, 0.26, 0.58),
		"luz_dir": Color(0.66, 0.52, 0.95),
		"energia_amb": 0.56,
		"densidad": 0.017,
		"rugosidad": 0.72,
	},
	"magma": {
		"nombre": "Fallas de magma",
		"roca": Color(0.17, 0.13, 0.13),
		"suelo": Color(0.14, 0.11, 0.11),
		"niebla": Color(0.085, 0.024, 0.014),
		"ambiente": Color(0.48, 0.22, 0.14),
		"luz_dir": Color(0.95, 0.44, 0.22),
		"energia_amb": 0.58,
		"densidad": 0.019,
		"rugosidad": 0.84,
	},
}

var nivel: int = 1
var ambientacion_id: String = "piedra"
var superficie_objetivo_m2: float = 0.0
var superficie_generada_m2: float = 0.0
var puntos_evitar_rocas: Array[Vector3] = []
var posiciones_antorchas: Array[Vector3] = []
var posicion_ascensor: Vector3 = Vector3.INF
var puntos_enemigos: Node3D = null
var nodo_ascensor: Node3D = null
var nodo_escalera_profunda: Node3D = null
var nodo_escalera_subida: Node3D = null

var _geometria_proc: Node3D = null
var _celdas_cavadas: Dictionary = {}
var _distancias: Dictionary = {}
var _celda_bajada: Vector2i = Vector2i.ZERO
var _preparado_en_nivel: int = -1


static func nivel_actual() -> int:
	return clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, MAX_NIVEL)


static func escala_superficie(nv: int) -> float:
	var n := clampi(nv, 1, MAX_NIVEL)
	return 1.0 + 2.0 * float(n - 1) / float(MAX_NIVEL - 1)


static func id_ambientacion(nv: int) -> String:
	var n := clampi(nv, 1, MAX_NIVEL)
	if n <= 5:
		return "piedra"
	if n <= 10:
		return "humeda"
	if n <= 15:
		return "cristal"
	return "magma"


static func datos_ambientacion(nv: int) -> Dictionary:
	return (AMBIENTACIONES[id_ambientacion(nv)] as Dictionary)


static func ascensor_disponible_en(nv: int) -> bool:
	return clampi(nv, 1, MAX_NIVEL) in NIVELES_ASCENSOR


static func max_nivel_alcanzado() -> int:
	return clampi(maxi(int(Juego.banderas.get("mina_max_nivel", 1)), nivel_actual()), 1, MAX_NIVEL)


static func paradas_ascensor_desbloqueadas() -> Array[int]:
	var mx := max_nivel_alcanzado()
	var r: Array[int] = [1]
	for p: int in NIVELES_ASCENSOR:
		if p > 1 and mx >= p:
			r.append(p)
	return r


func _ready() -> void:
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	var mapa := _mapa()
	if mapa == null or id != ID_MAPA or str(mapa.get("id_mapa")) != ID_MAPA:
		return
	var nv := nivel_actual()
	if _preparado_en_nivel != nv:
		preparar(mapa)
		aplicar_ambiente(mapa)
	# En niveles 1 y 2 la exploración física de suelo funciona mejor tras emitir mapa_cargado.
	if nv <= 2:
		_colocar_extras_clasicos(mapa)


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


## Prepara geometría procedural (niveles 3..20) y marcadores antes de salidas y límites del mapa.
func preparar(mapa: Node) -> void:
	nivel = nivel_actual()
	_preparado_en_nivel = nivel
	ambientacion_id = id_ambientacion(nivel)
	superficie_objetivo_m2 = float(CEL_BASE) * escala_superficie(nivel) * (PASO * PASO)
	puntos_evitar_rocas.clear()
	posiciones_antorchas.clear()
	posicion_ascensor = Vector3.INF
	_limpiar_nodos_propios()

	# Guardar progreso en banderas y desbloquear paradas de ascensor cada 5 niveles.
	var prev_max := int(Juego.banderas.get("mina_max_nivel", 1))
	if nivel > prev_max:
		Juego.banderas["mina_max_nivel"] = nivel
		if ascensor_disponible_en(nivel) and nivel > 1:
			Juego.banderas["mina_ascensor_desbloqueado"] = true
			if Juego.partida_activa:
				Juego.guardar.call_deferred(false)
			Interfaz.mensaje.call_deferred("¡Has alcanzado el nivel %d! Ascensor y progreso de la mina guardados." % nivel)
	elif ascensor_disponible_en(nivel) and nivel > 1:
		Juego.banderas["mina_ascensor_desbloqueado"] = true

	if nivel <= 2:
		superficie_generada_m2 = float(CEL_BASE) * (PASO * PASO)
		return

	# Niveles 3..20: ocultar la cueva estática de L1/L2 y generar la caverna del nivel por semilla.
	_ocultar_cueva_base(mapa)
	_generar_caverna_procedural(mapa)


func _limpiar_nodos_propios() -> void:
	for h in get_children():
		h.queue_free()
	_geometria_proc = null
	puntos_enemigos = null
	nodo_ascensor = null
	nodo_escalera_profunda = null
	nodo_escalera_subida = null


func _ocultar_cueva_base(mapa: Node) -> void:
	var carg: Node = mapa.get("cargador") as Node
	if carg != null:
		var geo := carg.get("geometria") as Node3D
		if geo != null:
			geo.visible = false
		var inst := carg.get("nodo_instancias") as Node3D
		if inst != null:
			inst.visible = false
		var luces := carg.get("nodo_luces") as Node3D
		if luces != null:
			luces.visible = false
		var cols := carg.get("colisiones") as StaticBody3D
		if cols != null:
			cols.collision_layer = 0
			for cs in cols.get_children():
				if cs is CollisionShape3D:
					(cs as CollisionShape3D).disabled = true
	var solo_jug := mapa.get_node_or_null("ColisionSoloJugador") as StaticBody3D
	if solo_jug != null:
		solo_jug.collision_layer = 0
		for cs in solo_jug.get_children():
			if cs is CollisionShape3D:
				(cs as CollisionShape3D).disabled = true
	for nom_extra: String in ["ParedesLisasLlegada", "SueloLisoLlegada"]:
		var n_ex := mapa.get_node_or_null(nom_extra) as CollisionObject3D
		if n_ex != null:
			n_ex.collision_layer = 0
			for cs in n_ex.get_children():
				if cs is CollisionShape3D:
					(cs as CollisionShape3D).disabled = true


func aplicar_ambiente(mapa: Node) -> void:
	# Nivel 2 conserva exactamente el ambiente oscuro azulado de BajadaMina.oscurecer() para pasar L4b.
	if nivel == 2:
		return
	var we := mapa.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var d := datos_ambientacion(nivel)
	var env := we.environment
	env.background_color = (d["niebla"] as Color) * 0.45
	env.ambient_light_color = d["ambiente"] as Color
	env.ambient_light_energy = float(d["energia_amb"])
	env.fog_enabled = true
	env.fog_light_color = d["niebla"] as Color
	env.fog_density = float(d["densidad"])

	var sol := mapa.get_node_or_null("Sol") as DirectionalLight3D
	if sol != null and nivel >= 3:
		sol.light_color = d["luz_dir"] as Color
		sol.light_energy = 0.55 if ambientacion_id != "magma" else 0.70

	if nivel == 1:
		# En nivel 1 dejamos las antorchas clásicas tras cargar suelo.
		return

	# Luz ambiental direccional extra suave en niveles profundos para resaltar el relieve.
	var rel := DirectionalLight3D.new()
	rel.name = "LuzAmbientacionMina"
	rel.light_color = d["luz_dir"] as Color
	rel.light_energy = 0.36
	rel.shadow_enabled = false
	rel.rotation_degrees = Vector3(-72.0, -25.0, 0.0)
	add_child(rel)


# --- Generación procedural (niveles 3..20) --------------------------------------------------------------

static func _mundo_celda(c: Vector2i) -> Vector2:
	return Vector2(402.5 + float(c.x) * PASO, 0.0 + float(c.y) * PASO)


func _generar_caverna_procedural(mapa: Node) -> void:
	var escala := escala_superficie(nivel)
	var factor_lado := sqrt(escala)
	var ancho := 48.0 * factor_lado
	var largo := 40.0 * factor_lado
	var x0 := 394.0
	var x1 := x0 + ancho
	var z1 := 8.0
	var z0 := z1 - largo

	mapa.set("poligono_limites", PackedVector2Array([
		Vector2(x0, z0),
		Vector2(x1, z0),
		Vector2(x1, z1),
		Vector2(x0, z1),
	]))

	var ix_min := 0
	var ix_max := int(floor((x1 - 3.5 - 402.5) / PASO))
	var iz_min := int(ceil((z0 + 3.5) / PASO))
	var iz_max := 1

	var azar := RandomNumberGenerator.new()
	azar.seed = 26000 + nivel * 977

	_celdas_cavadas.clear()
	# Vestíbulo de entrada centrado en Entrada_Interior (400.0, 0.0) y Llegada_Interior (403.0, 0.07).
	_celdas_cavadas[Vector2i(-1, 0)] = true
	for ix in range(0, 3):
		for iz in range(-1, 2):
			_celdas_cavadas[Vector2i(ix, iz)] = true

	var objetivo := clampi(roundi(float(CEL_BASE) * escala), 42, 180)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	var punteros: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, -1), Vector2i(1, -1), Vector2i(3, -1)]
	var intentos := 0
	while _celdas_cavadas.size() < objetivo and intentos < 1800:
		intentos += 1
		var idx := intentos % punteros.size()
		var p: Vector2i = punteros[idx]
		var d: Vector2i = dirs[azar.randi_range(0, 3)]
		if p.x < 4 and azar.randf() < 0.55:
			d = Vector2i(1, 0)
		elif p.y > -3 and azar.randf() < 0.45:
			d = Vector2i(0, -1)
		var np := p + d
		np.x = clampi(np.x, 1, maxi(1, ix_max - 1))
		np.y = clampi(np.y, iz_min, maxi(iz_min, iz_max - 1))
		punteros[idx] = np
		for dx in 2:
			for dz in 2:
				if _celdas_cavadas.size() >= objetivo:
					break
				var c := Vector2i(clampi(np.x + dx, 1, ix_max), clampi(np.y + dz, iz_min, iz_max))
				_celdas_cavadas[c] = true
			if _celdas_cavadas.size() >= objetivo:
				break
		if _celdas_cavadas.size() < objetivo and azar.randf() < 0.16:
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if _celdas_cavadas.size() >= objetivo:
						break
					var c := Vector2i(clampi(np.x + dx, 1, ix_max), clampi(np.y + dz, iz_min, iz_max))
					_celdas_cavadas[c] = true
				if _celdas_cavadas.size() >= objetivo:
					break

	# Completar de forma determinista hasta objetivo si la caminata aleatoria tocó los bordes.
	if _celdas_cavadas.size() < objetivo:
		var frontera := true
		while _celdas_cavadas.size() < objetivo and frontera:
			frontera = false
			var actuales: Array[Vector2i] = []
			for k: Vector2i in _celdas_cavadas:
				if k.x >= 1:
					actuales.append(k)
			actuales.sort()
			for c: Vector2i in actuales:
				for d in dirs:
					var n := c + d
					if n.x >= 1 and n.x <= ix_max and n.y >= iz_min and n.y <= iz_max and not _celdas_cavadas.has(n):
						_celdas_cavadas[n] = true
						frontera = true
						if _celdas_cavadas.size() >= objetivo:
							break
				if _celdas_cavadas.size() >= objetivo:
					break

	superficie_generada_m2 = float(_celdas_cavadas.size()) * (PASO * PASO)

	# Calcular distancias BFS desde (0, 0) para situar bajada, antorchas y enemigos.
	_distancias = {Vector2i(0, 0): 0}
	var cola: Array[Vector2i] = [Vector2i(0, 0)]
	var cabeza := 0
	var celda_lejana := Vector2i(2, -1)
	var max_dist := 0
	while cabeza < cola.size():
		var c := cola[cabeza]
		cabeza += 1
		var dist_c := int(_distancias[c])
		for d in dirs:
			var n := c + d
			if _celdas_cavadas.has(n) and not _distancias.has(n):
				_distancias[n] = dist_c + 1
				cola.append(n)
				if dist_c + 1 > max_dist and (n.x >= 3 or n.y <= -3):
					max_dist = dist_c + 1
					celda_lejana = n
	_celda_bajada = celda_lejana

	_construir_malla_caverna(azar)
	_colocar_ambientacion_especifica(azar)
	_actualizar_marcadores_nivel(mapa)
	_colocar_elementos_nivel(mapa, azar)


func _altura_esquina(ix: int, iz: int, azar_semilla: int) -> float:
	# Vestíbulo de entrada y zona de bajada completamente planos.
	if ix >= -1 and ix <= 3 and iz >= -2 and iz <= 2:
		return 0.0
	if Vector2(float(ix), float(iz)).distance_to(Vector2(float(_celda_bajada.x), float(_celda_bajada.y))) <= 2.2:
		return 0.0
	var h := sin(float(ix) * 1.73 + float(azar_semilla)) * cos(float(iz) * 1.37 + float(azar_semilla) * 0.5)
	return clampf(h * 0.03, -0.03, 0.03)


func _construir_malla_caverna(azar: RandomNumberGenerator) -> void:
	_geometria_proc = Node3D.new()
	_geometria_proc.name = "GeometriaProcedural"
	add_child(_geometria_proc)

	var d := datos_ambientacion(nivel)
	var col_suelo := d["suelo"] as Color
	var col_roca := d["roca"] as Color
	var alto_muro := 4.8

	var st_suelo := SurfaceTool.new()
	st_suelo.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_suelo.set_smooth_group(-1)

	var st_muros := SurfaceTool.new()
	st_muros.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_muros.set_smooth_group(-1)

	var caras_col := PackedVector3Array()
	var vistas_techo: Dictionary = {}

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var claves: Array[Vector2i] = []
	for k: Vector2i in _celdas_cavadas:
		claves.append(k)
	claves.sort()

	for c: Vector2i in claves:
		var centro := _mundo_celda(c)
		var ms := PASO * 0.5
		var p0 := Vector3(centro.x - ms, _altura_esquina(c.x, c.y, nivel), centro.y - ms)
		var p1 := Vector3(centro.x + ms, _altura_esquina(c.x + 1, c.y, nivel), centro.y - ms)
		var p2 := Vector3(centro.x + ms, _altura_esquina(c.x + 1, c.y + 1, nivel), centro.y + ms)
		var p3 := Vector3(centro.x - ms, _altura_esquina(c.x, c.y + 1, nivel), centro.y + ms)
		var tono_s := azar.randf_range(0.86, 1.10)
		var cs_col := Color(col_suelo.r * tono_s, col_suelo.g * tono_s, col_suelo.b * tono_s)
		for tri in [[p0, p1, p2], [p0, p2, p3]]:
			st_suelo.set_color(cs_col)
			for v: Vector3 in tri:
				st_suelo.add_vertex(v)
				caras_col.append(v)

		for dir in dirs:
			var n := c + dir
			if _celdas_cavadas.has(n):
				continue
			# Orden horario en Godot (va -> vb -> vb_m) con normal hacia el interior (-dir).
			var va := Vector3.ZERO
			var vb := Vector3.ZERO
			var dir_out := Vector3(float(dir.x), 0.0, float(dir.y))
			if dir == Vector2i(0, -1):
				va = p1; vb = p0
			elif dir == Vector2i(1, 0):
				va = p2; vb = p1
			elif dir == Vector2i(0, 1):
				va = p3; vb = p2
			else:
				va = p0; vb = p3
			var va_b := Vector3(va.x, -0.35, va.z)
			var vb_b := Vector3(vb.x, -0.35, vb.z)
			var off := dir_out * 0.42
			var va_m := Vector3(va.x + off.x * 0.35, 2.2 + azar.randf_range(-0.18, 0.22), va.z + off.z * 0.35)
			var vb_m := Vector3(vb.x + off.x * 0.35, 2.2 + azar.randf_range(-0.18, 0.22), vb.z + off.z * 0.35)
			var va_t := Vector3(va.x + off.x, alto_muro, va.z + off.z)
			var vb_t := Vector3(vb.x + off.x, alto_muro, vb.z + off.z)

			var tono_w := azar.randf_range(0.78, 1.08)
			var cw_bajo := Color(col_roca.r * tono_w, col_roca.g * tono_w, col_roca.b * tono_w)
			var cw_alto := cw_bajo * 0.65
			cw_alto.a = 1.0

			for tri in [[va_b, vb_b, vb_m], [va_b, vb_m, va_m], [va_m, vb_m, vb_t], [va_m, vb_t, va_t]]:
				var c_use := cw_bajo if (tri[2].y < 3.0) else cw_alto
				st_muros.set_color(c_use)
				for v: Vector3 in tri:
					st_muros.add_vertex(v)
			# Colisión vertical plana para evitar enganches de cámara o cápsula.
			var c_va0 := Vector3(va.x, -0.5, va.z)
			var c_vb0 := Vector3(vb.x, -0.5, vb.z)
			var c_va1 := Vector3(va.x, alto_muro + 1.0, va.z)
			var c_vb1 := Vector3(vb.x, alto_muro + 1.0, vb.z)
			caras_col.append_array(PackedVector3Array([c_va0, c_vb0, c_vb1, c_va0, c_vb1, c_va1]))

			# Tapa de roca circundante superior (sin colisión para no bloquear la cámara).
			if not vistas_techo.has(n):
				vistas_techo[n] = true
				var cn := _mundo_celda(n)
				var t0 := Vector3(cn.x - ms, alto_muro, cn.y - ms)
				var t1 := Vector3(cn.x + ms, alto_muro, cn.y - ms)
				var t2 := Vector3(cn.x + ms, alto_muro, cn.y + ms)
				var t3 := Vector3(cn.x - ms, alto_muro, cn.y + ms)
				var c_cap := Color(col_roca.r * 0.35, col_roca.g * 0.35, col_roca.b * 0.35)
				for tri in [[t0, t1, t2], [t0, t2, t3]]:
					st_muros.set_color(c_cap)
					for v: Vector3 in tri:
						st_muros.add_vertex(v)

	st_suelo.generate_normals()
	var m_suelo := st_suelo.commit()
	var mat_s := StandardMaterial3D.new()
	mat_s.vertex_color_use_as_albedo = true
	mat_s.vertex_color_is_srgb = true
	mat_s.roughness = float(d["rugosidad"])
	m_suelo.surface_set_material(0, mat_s)
	var mi_s := MeshInstance3D.new()
	mi_s.name = "SueloCaverna"
	mi_s.mesh = m_suelo
	_geometria_proc.add_child(mi_s)

	st_muros.generate_normals()
	var m_muros := st_muros.commit()
	var mat_m := StandardMaterial3D.new()
	mat_m.vertex_color_use_as_albedo = true
	mat_m.vertex_color_is_srgb = true
	mat_m.roughness = minf(float(d["rugosidad"]) + 0.08, 0.94)
	m_muros.surface_set_material(0, mat_m)
	var mi_m := MeshInstance3D.new()
	mi_m.name = "ParedesCaverna"
	mi_m.mesh = m_muros
	_geometria_proc.add_child(mi_m)

	var body := StaticBody3D.new()
	body.name = "ColisionCaverna"
	body.collision_layer = 1
	body.collision_mask = 0
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(caras_col)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	body.add_child(cs)
	_geometria_proc.add_child(body)


func _colocar_ambientacion_especifica(azar: RandomNumberGenerator) -> void:
	if _geometria_proc == null:
		return
	# Seleccionar celdas periféricas o de salas anchas libres de entrada y bajada.
	var borde_celdas: Array[Vector2i] = []
	var interiores: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in _celdas_cavadas:
		if int(_distancias.get(c, 0)) < 3 or c == _celda_bajada:
			continue
		var vecinos := 0
		for d in dirs:
			if _celdas_cavadas.has(c + d):
				vecinos += 1
		if vecinos <= 2:
			borde_celdas.append(c)
		elif vecinos == 4:
			interiores.append(c)
	borde_celdas.sort()
	interiores.sort()

	match ambientacion_id:
		"humeda":
			# Charcos reflectantes y agua subterránea en zonas apartadas.
			var mat_agua := StandardMaterial3D.new()
			mat_agua.albedo_color = Color(0.14, 0.44, 0.56, 0.72)
			mat_agua.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat_agua.roughness = 0.06
			mat_agua.metallic = 0.25
			mat_agua.emission_enabled = true
			mat_agua.emission = Color(0.06, 0.20, 0.28)
			mat_agua.emission_energy_multiplier = 0.35
			var n_charcos := mini(4 + nivel / 3, borde_celdas.size())
			for i in n_charcos:
				var c := borde_celdas[(i * 7 + azar.randi_range(0, 3)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var disco := MeshInstance3D.new()
				disco.name = "Charco_%d" % i
				var cm := CylinderMesh.new()
				cm.top_radius = azar.randf_range(0.85, 1.30)
				cm.bottom_radius = cm.top_radius * 1.05
				cm.height = 0.04
				cm.radial_segments = 14
				disco.mesh = cm
				disco.material_override = mat_agua
				disco.position = Vector3(p.x, 0.025, p.y)
				_geometria_proc.add_child(disco)
		"cristal":
			# Clústeres luminosos de cristales amatista y cian junto a las paredes.
			var mats: Array[StandardMaterial3D] = []
			for col_c in [Color(0.68, 0.34, 0.96), Color(0.30, 0.86, 0.98)]:
				var mc := StandardMaterial3D.new()
				mc.albedo_color = col_c
				mc.emission_enabled = true
				mc.emission = col_c
				mc.emission_energy_multiplier = 1.65
				mc.roughness = 0.18
				mats.append(mc)
			var n_c := mini(8 + nivel / 2, borde_celdas.size())
			for i in n_c:
				var c := borde_celdas[(i * 5 + azar.randi_range(0, 2)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var base := Node3D.new()
				base.name = "Cristales_%d" % i
				base.position = Vector3(p.x + azar.randf_range(-0.6, 0.6), 0.0, p.y + azar.randf_range(-0.6, 0.6))
				var mat_e := mats[i % 2]
				for j in 3:
					var aguja := MeshInstance3D.new()
					var pm := PrismMesh.new()
					pm.size = Vector3(0.24, azar.randf_range(0.65, 1.35), 0.24)
					aguja.mesh = pm
					aguja.material_override = mat_e
					aguja.position = Vector3(azar.randf_range(-0.22, 0.22), pm.size.y * 0.42, azar.randf_range(-0.22, 0.22))
					aguja.rotation_degrees = Vector3(azar.randf_range(-16, 16), azar.randf_range(0, 180), azar.randf_range(-16, 16))
					base.add_child(aguja)
				if i % 2 == 0:
					var lc := OmniLight3D.new()
					lc.light_color = mat_e.albedo_color
					lc.light_energy = 1.15
					lc.omni_range = 7.5
					lc.shadow_enabled = false
					lc.position = Vector3(0.0, 0.9, 0.0)
					base.add_child(lc)
				_geometria_proc.add_child(base)
				puntos_evitar_rocas.append(base.position)
		"magma":
			# Pozas incandescentes de magma en los bordes con iluminación cálida.
			var mat_lava := StandardMaterial3D.new()
			mat_lava.albedo_color = Color(0.95, 0.34, 0.06)
			mat_lava.emission_enabled = true
			mat_lava.emission = Color(1.0, 0.30, 0.04)
			mat_lava.emission_energy_multiplier = 2.4
			mat_lava.roughness = 0.25
			var n_l := mini(6 + nivel / 3, borde_celdas.size())
			for i in n_l:
				var c := borde_celdas[(i * 6 + azar.randi_range(0, 3)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var pos := Vector3(p.x, 0.03, p.y)
				var poza := MeshInstance3D.new()
				poza.name = "Magma_%d" % i
				var cm := CylinderMesh.new()
				cm.top_radius = azar.randf_range(0.75, 1.10)
				cm.bottom_radius = cm.top_radius * 1.12
				cm.height = 0.06
				cm.radial_segments = 12
				poza.mesh = cm
				poza.material_override = mat_lava
				poza.position = pos
				_geometria_proc.add_child(poza)
				if i % 2 == 0:
					var ll := OmniLight3D.new()
					ll.light_color = Color(1.0, 0.42, 0.14)
					ll.light_energy = 1.45
					ll.omni_range = 8.0
					ll.shadow_enabled = false
					ll.position = pos + Vector3(0.0, 0.7, 0.0)
					_geometria_proc.add_child(ll)
				puntos_evitar_rocas.append(pos)
		_:
			# Niveles 3-5 piedra: algunos pilares de madera / roca de apoyo en salas grandes.
			var mat_p := StandardMaterial3D.new()
			mat_p.albedo_color = Color(0.28, 0.20, 0.14)
			mat_p.roughness = 0.90
			for i in mini(4, interiores.size()):
				var p := _mundo_celda(interiores[(i * 4) % interiores.size()])
				var pilar := StaticBody3D.new()
				pilar.name = "Puntal_%d" % i
				pilar.collision_layer = CAPA_SOLO_JUGADOR
				pilar.collision_mask = 0
				pilar.position = Vector3(p.x, 0.0, p.y)
				var mi := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.32, 4.6, 0.32)
				mi.mesh = box
				mi.material_override = mat_p
				mi.position = Vector3(0.0, 2.3, 0.0)
				pilar.add_child(mi)
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.36, 4.6, 0.36)
				cs.shape = bs
				cs.position = Vector3(0.0, 2.3, 0.0)
				pilar.add_child(cs)
				_geometria_proc.add_child(pilar)
				puntos_evitar_rocas.append(pilar.position)


func _actualizar_marcadores_nivel(mapa: Node) -> void:
	var m_bajada := mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	if m_bajada == null:
		return
	var dest := _mundo_celda(_celda_bajada)
	m_bajada.global_position = Vector3(dest.x, 0.0, dest.y)


func _colocar_elementos_nivel(mapa: Node, azar: RandomNumberGenerator) -> void:
	# 1. Antorchas con luz real repartidas por pasillos y vestíbulo.
	var candidatas_ant: Array[Vector2i] = []
	for c: Vector2i in _celdas_cavadas:
		candidatas_ant.append(c)
	candidatas_ant.sort()
	_poner_antorcha(Vector3(401.2, 0.0, -1.2))
	_poner_antorcha(Vector3(401.2, 0.0, 1.2))
	var dest_b := _mundo_celda(_celda_bajada)
	_poner_antorcha(Vector3(dest_b.x - 1.0, 0.0, dest_b.y))
	var objetivo_ant := clampi(6 + nivel / 2, 6, 16)
	var paso_i := maxi(candidatas_ant.size() / maxi(objetivo_ant, 1), 1)
	for i in range(0, candidatas_ant.size(), paso_i):
		if posiciones_antorchas.size() >= objetivo_ant:
			break
		var pos2 := _mundo_celda(candidatas_ant[i])
		var pos := Vector3(pos2.x + 0.8, 0.0, pos2.y + 0.8)
		var demasiado_cerca := false
		for ya in posiciones_antorchas:
			if ya.distance_to(pos) < 6.5:
				demasiado_cerca = true
				break
		if not demasiado_cerca:
			_poner_antorcha(pos)

	# 2. Ascensor en niveles 1, 5, 10, 15, 20.
	if ascensor_disponible_en(nivel):
		_poner_ascensor(Vector3(402.5, 0.0, -2.5))

	# 3. Escalera de subida al nivel anterior cerca del vestíbulo (niveles 3..20).
	if nivel >= 3:
		_poner_escalera_subida(Vector3(402.5, 0.0, 2.5), nivel - 1)

	# 4. Puntos de aparición de enemigos (inactivos hasta tener modelos, ACTIVOS = false).
	_colocar_puntos_enemigos(azar)


func _colocar_extras_clasicos(mapa: Node) -> void:
	# Antorchas y puntos extra sobre la geometría clásica (niveles 1 y 2) sin estorbar a RocasMina.
	var azar := RandomNumberGenerator.new()
	azar.seed = 26000 + nivel * 977
	var m_lleg := mapa.call("marcador", "Llegada_Interior") as Marker3D
	var m_baj := mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	var p_lleg := m_lleg.global_position if m_lleg != null else Vector3(408.7, 0.0, 2.0)

	# Antorchas repartidas por toda la cueva clásica buscando suelo real cerca de referencias del túnel y cavernas.
	var candidatos_l1 := [
		Vector3(401.6, 0.0, -0.9),
		Vector3(405.2, 0.0, 0.9),
		Vector3(410.5, 0.0, -1.5),
		Vector3(415.0, 0.0, -4.0),
		Vector3(420.5, 0.0, -8.5),
		Vector3(426.0, 0.0, -13.0),
		Vector3(428.0, 0.0, -17.0),
		Vector3(420.0, 0.0, -16.5),
	]
	for p: Vector3 in candidatos_l1:
		var suelo := AyudasL4b.suelo(self, p, 1.5, 3.0)
		if suelo == Vector3.INF:
			suelo = AyudasL4b.sitio_libre(self, p, 0.25, 3.0)
		if suelo != Vector3.INF:
			var lejos := true
			for ya in posiciones_antorchas:
				if ya.distance_to(suelo) < 3.0:
					lejos = false
					break
			if lejos:
				_poner_antorcha(suelo)

	if ascensor_disponible_en(nivel):
		var p_baj_ref := m_baj.global_position if m_baj != null else Vector3(428.8, 0.0, -18.5)
		var p_asc := Vector3.INF
		for cand_asc: Vector3 in [Vector3(410.5, 0.0, 0.5), Vector3(411.5, 0.0, -3.5), Vector3(413.0, 0.0, -2.0)]:
			var s := _buscar_suelo_libre(cand_asc, p_lleg, p_baj_ref)
			if s != Vector3.INF and s.x >= 408.5:
				p_asc = s
				break
		if p_asc == Vector3.INF:
			p_asc = AyudasL4b.sitio_libre(self, Vector3(411.5, 0.0, -3.5), 0.35, 3.5)
		_poner_ascensor(p_asc)

	# Nivel 2: coloca la bajada adicional hacia el nivel 3 sin tocar Bajada_Nivel_2 («Subir al nivel 1»).
	if nivel == 2:
		var p_baj2 := m_baj.global_position if m_baj != null else Vector3(431.0, 0.0, -14.0)
		var objetivos := [
			Vector3(424.0, 0.0, -19.0),
			Vector3(417.0, 0.0, -14.5),
			Vector3(433.0, 0.0, -8.5),
			p_baj2 + Vector3(-4.2, 0.0, 1.5),
		]
		var elegido := Vector3.INF
		for cand: Vector3 in objetivos:
			var s := _buscar_suelo_libre(cand, p_lleg, p_baj2)
			if s != Vector3.INF and s.distance_to(p_baj2) > 3.2 and s.distance_to(p_lleg) > 6.0:
				elegido = s
				break
		if elegido == Vector3.INF:
			elegido = p_lleg + Vector3(3.4, 0.0, -2.5)
		_poner_escalera_profunda(elegido, 3)

	_colocar_puntos_enemigos_clasicos(p_lleg, azar)


func _buscar_suelo_libre(ref: Vector3, p_lleg: Vector3, p_baj: Vector3) -> Vector3:
	for r in [0.0, 1.0, 2.0, 3.0, 4.0]:
		for ang in [0.0, 1.57, 3.14, 4.71, 0.78, 2.35, 3.92, 5.49]:
			var p := ref + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			var s := AyudasL4b.suelo(self, p, 1.0, 2.5)
			if s == Vector3.INF:
				continue
			if s.distance_to(p_lleg) < 1.8:
				continue
			if p_baj.distance_to(p_lleg) > 2.0 and s.distance_to(p_baj) < 2.2:
				continue
			if AyudasL4b.cabe(self, s, 0.35, EscalaPersonaje.ALTURA_PIE - 0.45, 1 | CAPA_SOLO_JUGADOR, 0.3):
				return s
			if r == 0.0:
				break
	return Vector3.INF


# --- Props visuales e interactuables ---------------------------------------------------------------------

func _poner_antorcha(pos: Vector3) -> void:
	posiciones_antorchas.append(pos)
	var ant := Node3D.new()
	ant.name = "Antorcha_%d" % posiciones_antorchas.size()
	ant.position = pos
	var palo := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.06
	cm.height = 1.45
	palo.mesh = cm
	var mp := StandardMaterial3D.new()
	mp.albedo_color = Color(0.30, 0.19, 0.11)
	mp.roughness = 0.88
	palo.material_override = mp
	palo.position = Vector3(0.0, 0.72, 0.0)
	ant.add_child(palo)

	var llama := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.095
	em.height = 0.20
	llama.mesh = em
	var ml := StandardMaterial3D.new()
	ml.albedo_color = Color(1.0, 0.72, 0.25)
	ml.emission_enabled = true
	ml.emission = Color(1.0, 0.56, 0.14)
	ml.emission_energy_multiplier = 2.5
	llama.material_override = ml
	llama.position = Vector3(0.0, 1.52, 0.0)
	ant.add_child(llama)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.68, 0.34)
	luz.light_energy = 1.60
	luz.omni_range = 11.5
	luz.omni_attenuation = 1.35
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, 1.65, 0.0)
	ant.add_child(luz)

	add_child(ant)
	puntos_evitar_rocas.append(pos)


func _poner_ascensor(pos: Vector3) -> void:
	posicion_ascensor = pos
	var raiz := StaticBody3D.new()
	raiz.name = "AscensorMina"
	raiz.collision_layer = CAPA_SOLO_JUGADOR
	raiz.collision_mask = 0
	raiz.position = pos
	add_child(raiz)
	nodo_ascensor = raiz

	var mat_madera := StandardMaterial3D.new()
	mat_madera.albedo_color = Color(0.36, 0.23, 0.13)
	mat_madera.roughness = 0.85
	var mat_hierro := StandardMaterial3D.new()
	mat_hierro.albedo_color = Color(0.24, 0.27, 0.31)
	mat_hierro.metallic = 0.65
	mat_hierro.roughness = 0.45

	var base := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.5, 0.12, 1.5)
	base.mesh = bmesh
	base.material_override = mat_madera
	base.position = Vector3(0.0, 0.06, 0.0)
	raiz.add_child(base)

	for sx in [-0.66, 0.66]:
		for sz in [-0.66, 0.66]:
			var poste := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.10, 2.35, 0.10)
			poste.mesh = pm
			poste.material_override = mat_hierro
			poste.position = Vector3(sx, 1.18, sz)
			raiz.add_child(poste)

	var techo := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.56, 0.14, 1.56)
	techo.mesh = tm
	techo.material_override = mat_hierro
	techo.position = Vector3(0.0, 2.35, 0.0)
	raiz.add_child(techo)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.35, 2.2, 1.35)
	cs.shape = bs
	cs.position = Vector3(0.0, 1.1, 0.0)
	raiz.add_child(cs)

	var punto := Interactuable.new()
	punto.name = "InteractuableAscensor"
	punto.verbo = "Usar"
	punto.nombre_objeto = "el ascensor de la mina"
	punto.radio = 1.65
	punto.altura_marca = 2.65
	punto.mostrar_descripcion = false
	punto.usado.connect(func(_j: Node3D) -> void: preguntar_ascensor())
	raiz.add_child(punto)
	puntos_evitar_rocas.append(pos)


func preguntar_ascensor() -> void:
	var paradas := paradas_ascensor_desbloqueadas()
	if paradas.size() <= 1 and nivel == 1:
		Interfaz.preguntar(
			"Ascensor de la mina (nivel máximo alcanzado: %d). Alcanza los niveles 5, 10, 15 o 20 para desbloquear paradas." % max_nivel_alcanzado(),
			["Entendido"],
			func(_i: int) -> void: pass
		)
		return
	var opciones: Array[String] = []
	var destinos: Array[int] = []
	for p: int in paradas:
		if p != nivel:
			opciones.append("Ir al nivel %d" % p)
			destinos.append(p)
	opciones.append("Quedarme")
	Interfaz.preguntar("Ascensor de la mina · Nivel actual: %d (máximo: %d)." % [nivel, max_nivel_alcanzado()], opciones, func(idx: int) -> void:
		if idx >= 0 and idx < destinos.size():
			_viajar_ascensor(destinos[idx]))


func _viajar_ascensor(destino: int) -> void:
	var mapa := _mapa()
	var bajada := mapa.get_node_or_null("Objetos/BajadaMina") as BajadaMina if mapa != null else null
	if bajada != null:
		bajada.cambiar_de_nivel(destino)
	else:
		Juego.banderas["nivel_mina"] = clampi(destino, 1, MAX_NIVEL)
		Escenas.ir_a_mapa(ID_MAPA, "Llegada_Interior")


func _poner_escalera_profunda(pos: Vector3, destino: int) -> void:
	var n := _crear_visual_escalera("EscaleraProfunda", pos, Color(0.55, 0.36, 0.20))
	nodo_escalera_profunda = n
	add_child(n)
	var p := Interactuable.new()
	p.name = "InteractuableBajadaProfunda"
	p.verbo = "Bajar"
	p.nombre_objeto = "al nivel %d" % destino
	p.radio = 1.4
	p.altura_marca = 1.9
	p.mostrar_descripcion = false
	p.usado.connect(func(_j: Node3D) -> void:
		Interfaz.preguntar("Una escalera desciende hacia las galerías del nivel %d. ¿Bajar?" % destino, ["Bajar al nivel %d" % destino, "Todavía no"], func(i: int) -> void:
			if i == 0:
				_viajar_ascensor(destino)))
	n.add_child(p)
	puntos_evitar_rocas.append(pos)


func _poner_escalera_subida(pos: Vector3, destino: int) -> void:
	var n := _crear_visual_escalera("EscaleraSubida", pos, Color(0.45, 0.31, 0.18))
	nodo_escalera_subida = n
	add_child(n)
	var p := Interactuable.new()
	p.name = "InteractuableSubida"
	p.verbo = "Subir"
	p.nombre_objeto = "al nivel %d" % destino
	p.radio = 1.4
	p.altura_marca = 1.9
	p.mostrar_descripcion = false
	p.usado.connect(func(_j: Node3D) -> void:
		Interfaz.preguntar("La escalera vuelve al nivel %d. ¿Subir?" % destino, ["Subir al nivel %d" % destino, "Quedarme"], func(i: int) -> void:
			if i == 0:
				_viajar_ascensor(destino)))
	n.add_child(p)
	puntos_evitar_rocas.append(pos)


static func _crear_visual_escalera(nombre: String, pos: Vector3, color: Color) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	n.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	for sx in [-0.32, 0.32]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 1.9, 0.08)
		rail.mesh = bm
		rail.material_override = mat
		rail.position = Vector3(sx, 0.85, 0.0)
		rail.rotation_degrees.x = -12.0
		n.add_child(rail)
	for i in 5:
		var pel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.68, 0.06, 0.07)
		pel.mesh = pm
		pel.material_override = mat
		pel.position = Vector3(0.0, 0.25 + float(i) * 0.34, float(i) * -0.07)
		n.add_child(pel)
	return n


# --- Puntos de aparición de enemigos ---------------------------------------------------------------------

func _colocar_puntos_enemigos(azar: RandomNumberGenerator) -> void:
	puntos_enemigos = Node3D.new()
	puntos_enemigos.name = "PuntosEnemigos"
	add_child(puntos_enemigos)

	var candidatas: Array[Vector2i] = []
	for c: Vector2i in _celdas_cavadas:
		if int(_distancias.get(c, 0)) >= 4 and c != _celda_bajada:
			candidatas.append(c)
	candidatas.sort()
	if candidatas.is_empty():
		candidatas.append(Vector2i(0, -1))
	for i in range(candidatas.size() - 1, 0, -1):
		var j := azar.randi_range(0, i)
		var tmp := candidatas[i]
		candidatas[i] = candidatas[j]
		candidatas[j] = tmp

	var catalogo := Enemigo.para_nivel(nivel)
	var cantidad := clampi(3 + nivel / 3, 3, 9)
	for i in mini(cantidad, candidatas.size()):
		var p2 := _mundo_celda(candidatas[i])
		var pos := Vector3(p2.x, 0.0, p2.y)
		_registrar_punto_enemigo(i, pos, catalogo[i % catalogo.size()] if not catalogo.is_empty() else {})


func _colocar_puntos_enemigos_clasicos(p_lleg: Vector3, _azar: RandomNumberGenerator) -> void:
	if puntos_enemigos != null and is_instance_valid(puntos_enemigos):
		return
	puntos_enemigos = Node3D.new()
	puntos_enemigos.name = "PuntosEnemigos"
	add_child(puntos_enemigos)
	var catalogo := Enemigo.para_nivel(nivel)
	var puestos := [
		Vector3(417.0, 0.0, -5.0),
		Vector3(424.0, 0.0, -10.5),
		Vector3(429.0, 0.0, -15.0),
	]
	for i in puestos.size():
		var s := AyudasL4b.suelo(self, puestos[i], 1.0, 2.5)
		var pos := s if s != Vector3.INF else p_lleg + Vector3(6.0 + float(i) * 2.5, 0.0, -4.0 - float(i) * 2.5)
		_registrar_punto_enemigo(i, pos, catalogo[i % catalogo.size()] if not catalogo.is_empty() else {})


func _registrar_punto_enemigo(indice: int, pos: Vector3, datos: Dictionary) -> void:
	var m := Marker3D.new()
	m.name = "SpawnEnemigo_%d" % (indice + 1)
	m.position = pos
	m.set_meta("enemigo_id", str(datos.get("id", "")))
	m.set_meta("enemigo_datos", datos)
	puntos_enemigos.add_child(m)
	if Enemigo.ACTIVOS and not datos.is_empty():
		var en := Enemigo.new()
		en.configurar(datos)
		en.position = pos
		puntos_enemigos.add_child(en)


## Instancia enemigos de prueba sobre los marcadores del nivel actual (p. ej. desde prueba_t26_mina).
func instanciar_enemigos_prueba(forzar_activos: bool = true) -> Array[Enemigo]:
	var r: Array[Enemigo] = []
	if puntos_enemigos == null:
		return r
	for h in puntos_enemigos.get_children():
		if h is Marker3D and h.has_meta("enemigo_datos"):
			var datos: Variant = h.get_meta("enemigo_datos")
			if datos is Dictionary and not (datos as Dictionary).is_empty():
				var en := Enemigo.new()
				en.configurar(datos as Dictionary)
				en.position = (h as Marker3D).position
				puntos_enemigos.add_child(en)
				en.activar_para_prueba(forzar_activos)
				r.append(en)
	return r
