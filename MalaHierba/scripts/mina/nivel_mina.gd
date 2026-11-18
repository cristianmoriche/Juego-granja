class_name NivelMina
extends Node3D
## Gestor de los 20 niveles de la mina (T26):
## - Niveles 1 y 2 mantienen la cueva base de Blender para conservar compatibilidad total con L4b/M2/M1,
##   añadiendo antorchas, ascensor cada 5 niveles, puntos de aparición de enemigos y bajada al nivel 3.
## - Niveles 3..20 generan por semilla una caverna procedural de superficie creciente (~1,2× en el 3 hasta ~3× en el 20),
##   con 4 ambientaciones (piedra 1-5, húmeda con agua 6-10, cristal 11-15, magma 16-20), antorchas y ascensor.

const ID_MAPA := "mina_interior"
const GeneradorCavernaH04 := preload("res://scripts/mina/generador_caverna_h04.gd")
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
		"niebla": Color(0.016, 0.019, 0.030),
		"ambiente": Color(0.22, 0.24, 0.32),
		"luz_dir": Color(0.56, 0.62, 0.78),
		"energia_amb": 0.19,
		"densidad": 0.017,
		"rugosidad": 0.90,
	},
	"humeda": {
		"nombre": "Grutas húmedas",
		"roca": Color(0.17, 0.23, 0.27),
		"suelo": Color(0.14, 0.20, 0.24),
		"niebla": Color(0.014, 0.036, 0.056),
		"ambiente": Color(0.18, 0.34, 0.44),
		"luz_dir": Color(0.40, 0.68, 0.85),
		"energia_amb": 0.21,
		"densidad": 0.021,
		"rugosidad": 0.30,
	},
	"cristal": {
		"nombre": "Cavernas de cristal",
		"roca": Color(0.20, 0.17, 0.30),
		"suelo": Color(0.18, 0.15, 0.26),
		"niebla": Color(0.024, 0.014, 0.048),
		"ambiente": Color(0.30, 0.22, 0.52),
		"luz_dir": Color(0.62, 0.48, 0.92),
		"energia_amb": 0.20,
		"densidad": 0.018,
		"rugosidad": 0.70,
	},
	"magma": {
		"nombre": "Fallas de magma",
		"roca": Color(0.17, 0.13, 0.13),
		"suelo": Color(0.14, 0.11, 0.11),
		"niebla": Color(0.068, 0.018, 0.010),
		"ambiente": Color(0.40, 0.17, 0.10),
		"luz_dir": Color(0.92, 0.40, 0.20),
		"energia_amb": 0.22,
		"densidad": 0.019,
		"rugosidad": 0.84,
	},
}

signal niebla_actualizada
signal jefe_derrotado

const TAM_NIEBLA := 64
const RADIO_REVELAR := 13.5
const SHADER_AGUA_MINA := """shader_type spatial;
uniform sampler2D onda_norm : hint_normal, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec2 uv1 = UV * 3.2 + vec2(TIME * 0.025, TIME * 0.018);
	vec2 uv2 = UV * 4.8 + vec2(-TIME * 0.02, TIME * 0.028);
	vec3 n = normalize(mix(texture(onda_norm, uv1).rgb * 2.0 - 1.0, texture(onda_norm, uv2).rgb * 2.0 - 1.0, 0.5));
	float r = length(UV - vec2(0.5)) * 2.0;
	float borde = 1.0 - smoothstep(0.62, 0.98, r);
	ALBEDO = mix(vec3(0.02, 0.07, 0.10), vec3(0.04, 0.13, 0.18), 1.0 - r * 0.5);
	ALPHA = 0.84 * borde;
	ROUGHNESS = 0.06;
	METALLIC = 0.22;
	SPECULAR = 0.88;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.60;
}
"""

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
var nodo_puerta_oculta: Node3D = null
var jefe_vivo: bool = false
var _hoja_puerta_oculta: StaticBody3D = null
var _punto_puerta_oculta: Interactuable = null
var _luz_puerta_oculta: OmniLight3D = null
var _puerta_oculta_abierta: bool = false
var cofres_nivel: Array[Node3D] = []
var atajos_nivel: Array[Node3D] = []

var _geometria_proc: Node3D = null
var _celdas_cavadas: Dictionary = {}
var _celdas_info: Dictionary = {}
var _origen_proc: Vector2 = Vector2(400.0, 0.0)
var _aabb_proc: AABB = AABB()
var _rutas_enemigos: AStarGrid2D
var _distancias: Dictionary = {}
var _celda_bajada: Vector2i = Vector2i.ZERO
var _preparado_en_nivel: int = -1
var _escalera_profunda_ala: Vector3 = Vector3.INF
var _niebla_bytes: PackedByteArray = PackedByteArray()
var _niebla_img: Image = null
var _niebla_tex: ImageTexture = null
var _niebla_overlay_img: Image = null
var _niebla_overlay_tex: ImageTexture = null
var _niebla_rect: Rect2 = Rect2()
var _t_niebla: float = 0.0
var _t_goteo: float = 3.5

static var _origen_estatico: Vector2 = Vector2(400.0, 0.0)
static var _shader_agua: Shader = null
static var _mat_agua: ShaderMaterial = null


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
	_inicializar_niebla(mapa)


func _process(delta: float) -> void:
	var mapa := _mapa()
	if mapa == null or not bool(mapa.get("esta_listo")):
		return
	var j := Escenas.jugador()
	if j == null or not is_instance_valid(j):
		return
	_t_niebla -= delta
	if _t_niebla <= 0.0:
		_t_niebla = 0.14
		revelar_niebla_en(Vector2(j.global_position.x, j.global_position.z), RADIO_REVELAR)
	if DisplayServer.get_name() != "headless":
		_t_goteo -= delta
		if _t_goteo <= 0.0:
			_t_goteo = randf_range(3.8, 7.2)
			var ang := randf() * TAU
			var dist := randf_range(5.0, 12.5)
			var p_g := j.global_position + Vector3(cos(ang) * dist, randf_range(0.6, 2.2), sin(ang) * dist)
			Audio.reproducir_posicional("mina_goteo_1" if randf() < 0.55 else "mina_goteo_2", p_g, self, -4.0)


func aabb_nivel() -> AABB:
	return _aabb_proc


func material_agua_subterranea() -> ShaderMaterial:
	if _mat_agua != null:
		return _mat_agua
	if _shader_agua == null:
		_shader_agua = Shader.new()
		_shader_agua.code = SHADER_AGUA_MINA
	_mat_agua = ShaderMaterial.new()
	_mat_agua.shader = _shader_agua
	if ResourceLoader.exists("res://assets/agua/ondas_normal.png"):
		_mat_agua.set_shader_parameter("onda_norm", load("res://assets/agua/ondas_normal.png"))
	return _mat_agua


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
		Juego.evaluar_logros()
		if ascensor_disponible_en(nivel) and nivel > 1:
			Juego.banderas["mina_ascensor_desbloqueado"] = true
			if Juego.partida_activa:
				Juego.guardar.call_deferred(false)
			Interfaz.mensaje.call_deferred("¡Has alcanzado el nivel %d! Ascensor y progreso de la mina guardados." % nivel)
	elif ascensor_disponible_en(nivel) and nivel > 1:
		Juego.banderas["mina_ascensor_desbloqueado"] = true

	if nivel <= 2:
		_generar_ala_clasica(mapa)
		return

	# Niveles 3..20: ocultar la cueva estática de L1/L2 y generar la caverna del nivel por semilla.
	_ocultar_cueva_base(mapa)
	_generar_caverna_procedural(mapa)


func _limpiar_nodos_propios() -> void:
	for h in get_children():
		h.queue_free()
	_geometria_proc = null
	puntos_enemigos = null
	_rutas_enemigos = null
	_celdas_cavadas.clear()
	_celdas_info.clear()
	_aabb_proc = AABB()
	_escalera_profunda_ala = Vector3.INF
	cofres_nivel.clear()
	atajos_nivel.clear()
	nodo_ascensor = null
	nodo_escalera_profunda = null
	nodo_escalera_subida = null
	nodo_puerta_oculta = null
	_hoja_puerta_oculta = null
	_punto_puerta_oculta = null
	_luz_puerta_oculta = null
	jefe_vivo = false
	_puerta_oculta_abierta = false


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
	for nombre in ["ColisionSoloJugador", "ColisionSoloCamara"]:
		var cuerpo := mapa.get_node_or_null(nombre) as StaticBody3D
		if cuerpo != null:
			cuerpo.collision_layer = 0
			for cs in cuerpo.get_children():
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
		sol.light_energy = 0.22 if ambientacion_id != "magma" else 0.30

	if nivel == 1:
		# Nivel 1 usa las antorchas clásicas y del ala nueva tras colocarse en mapa_cargado.
		return

	# Luz ambiental direccional muy tenue para recortar siluetas sin iluminar las galerías apagadas.
	var rel := DirectionalLight3D.new()
	rel.name = "LuzAmbientacionMina"
	rel.light_color = d["luz_dir"] as Color
	rel.light_energy = 0.14
	rel.shadow_enabled = false
	rel.rotation_degrees = Vector3(-72.0, -25.0, 0.0)
	add_child(rel)


# --- Generación procedural (niveles 1..20 H04) --------------------------------------------------------------

static func _mundo_celda(c: Vector2i) -> Vector2:
	return _origen_estatico + Vector2(float(c.x) * PASO, float(c.y) * PASO)


func _altura_celda(c: Vector2i) -> float:
	if _celdas_cavadas.has(c) and (_celdas_cavadas[c] is float or _celdas_cavadas[c] is int):
		return float(_celdas_cavadas[c])
	return float((_celdas_info.get(c, {}) as Dictionary).get("h0", 0.0))


func ruta_enemigo(desde: Vector3, hasta: Vector3) -> PackedVector3Array:
	var ruta := PackedVector3Array()
	if _celdas_cavadas.is_empty():
		return ruta
	var origen := _celda_pisable(desde)
	var destino := _celda_pisable(hasta)
	if not _celdas_cavadas.has(origen) or not _celdas_cavadas.has(destino) or origen == destino:
		return ruta
	if _rutas_enemigos == null:
		_preparar_rutas_enemigos()
	var ids := _rutas_enemigos.get_id_path(origen, destino)
	for i in range(1, ids.size()):
		var punto := _mundo_celda(ids[i])
		ruta.append(Vector3(punto.x, _altura_celda(ids[i]), punto.y))
	return ruta


func _celda_pisable(punto: Vector3) -> Vector2i:
	var origen := _mundo_celda(Vector2i.ZERO)
	var p := (Vector2(punto.x, punto.z) - origen) / PASO
	var celda := Vector2i(p.round())
	if _celdas_cavadas.has(celda):
		return celda
	var mejor := INF
	var cercana := celda
	for y in range(-1, 2):
		for x in range(-1, 2):
			var otra := celda + Vector2i(x, y)
			var dist := p.distance_squared_to(Vector2(otra))
			if dist < mejor and _celdas_cavadas.has(otra):
				cercana = otra
				mejor = dist
	return cercana


func _preparar_rutas_enemigos() -> void:
	var caja := Rect2i(Vector2i.ZERO, Vector2i.ONE)
	for celda: Vector2i in _celdas_cavadas:
		caja = caja.merge(Rect2i(celda, Vector2i.ONE))
	_rutas_enemigos = AStarGrid2D.new()
	_rutas_enemigos.region = caja
	_rutas_enemigos.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_rutas_enemigos.update()
	for y in range(caja.position.y, caja.end.y):
		for x in range(caja.position.x, caja.end.x):
			var celda := Vector2i(x, y)
			if not _celdas_cavadas.has(celda):
				_rutas_enemigos.set_point_solid(celda)


func _generar_ala_clasica(mapa: Node) -> void:
	var azar := RandomNumberGenerator.new()
	azar.seed = 26000 + nivel * 977
	var plan := GeneradorCavernaH04.construir_ala_clasica(self, mapa, nivel, azar)
	_origen_proc = plan["origen"]
	_origen_estatico = _origen_proc
	_celdas_info = plan["celdas_info"]
	_celdas_cavadas.clear()
	for c: Vector2i in _celdas_info:
		_celdas_cavadas[c] = float((_celdas_info[c] as Dictionary)["h0"])
	_escalera_profunda_ala = plan.get("escalera_profunda", Vector3.INF)

	_geometria_proc = Node3D.new()
	_geometria_proc.name = "GeometriaProcedural"
	add_child(_geometria_proc)
	var res := GeneradorCavernaH04.construir_geometria(self, _geometria_proc, plan, "piedra", nivel)
	_aabb_proc = res["aabb"]

	# Polígono en L compacto que rodea la cueva clásica y el ala este manteniendo lados amplios para pruebas de muro.
	var x_max := 456.5
	var z_min := -30.5
	for c: Vector2i in _celdas_info:
		var p := _mundo_celda(c)
		x_max = maxf(x_max, p.x + 4.0)
		z_min = minf(z_min, p.y - 4.0)
	mapa.set("poligono_limites", PackedVector2Array([
		Vector2(396.0, 22.0),
		Vector2(416.0, 22.0),
		Vector2(416.0, 5.5),
		Vector2(x_max, 5.5),
		Vector2(x_max, z_min),
		Vector2(396.0, z_min),
	]))

	superficie_generada_m2 = float(CEL_BASE + _celdas_cavadas.size()) * (PASO * PASO)
	superficie_objetivo_m2 = superficie_generada_m2
	_colocar_cofres_y_atajo(plan)
	# Proteger pasarelas estrechas en N2 para que RocasMina no las obstruya.
	for c_p: Vector2i in plan.get("puentes", []):
		var pw := _mundo_celda(c_p)
		puntos_evitar_rocas.append(Vector3(pw.x, _altura_celda(c_p), pw.y))


func _generar_caverna_procedural(mapa: Node) -> void:
	var azar := RandomNumberGenerator.new()
	azar.seed = 26000 + nivel * 977
	var plan := GeneradorCavernaH04.construir_disposicion_completa(nivel, ambientacion_id, azar)
	_origen_proc = plan["origen"]
	_origen_estatico = _origen_proc
	_celdas_info = plan["celdas_info"]
	_celdas_cavadas.clear()
	for c: Vector2i in _celdas_info:
		_celdas_cavadas[c] = float((_celdas_info[c] as Dictionary)["h0"])

	var x_min := 394.0
	var x_max := 420.0
	var z_min := -14.0
	var z_max := 10.0
	for dict_c in [_celdas_info, plan.get("simas", {})]:
		for c: Vector2i in dict_c:
			var p := _mundo_celda(c)
			x_min = minf(x_min, p.x - 4.2)
			x_max = maxf(x_max, p.x + 4.2)
			z_min = minf(z_min, p.y - 4.2)
			z_max = maxf(z_max, p.y + 4.2)
	mapa.set("poligono_limites", PackedVector2Array([
		Vector2(x_min, z_min),
		Vector2(x_max, z_min),
		Vector2(x_max, z_max),
		Vector2(x_min, z_max),
	]))

	superficie_generada_m2 = float(_celdas_cavadas.size()) * (PASO * PASO)
	superficie_objetivo_m2 = superficie_generada_m2

	# Distancias BFS desde la llegada (2, 0) para repartir enemigos, luces y bajada lejana.
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	_distancias = {Vector2i(2, 0): 0}
	var cola: Array[Vector2i] = [Vector2i(2, 0)]
	var cabeza := 0
	var celda_lejana: Vector2i = plan.get("celda_bajada", Vector2i(5, 0))
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
				if dist_c + 1 > max_dist and str((_celdas_info.get(n, {}) as Dictionary).get("tipo", "")) != "puente":
					max_dist = dist_c + 1
					celda_lejana = n
	_celda_bajada = celda_lejana

	_geometria_proc = Node3D.new()
	_geometria_proc.name = "GeometriaProcedural"
	add_child(_geometria_proc)
	var res := GeneradorCavernaH04.construir_geometria(self, _geometria_proc, plan, ambientacion_id, nivel)
	_aabb_proc = res["aabb"]
	_colocar_ambientacion_especifica(azar)
	_colocar_cofres_y_atajo(plan)
	for c_p: Vector2i in plan.get("puentes", []):
		var pw := _mundo_celda(c_p)
		puntos_evitar_rocas.append(Vector3(pw.x, _altura_celda(c_p), pw.y))
	_actualizar_marcadores_nivel(mapa)
	_colocar_elementos_nivel(mapa, azar)


func _colocar_cofres_y_atajo(plan: Dictionary) -> void:
	if _geometria_proc == null:
		return
	for cf: Dictionary in plan.get("cofres", []):
		var id_c := str(cf["id"])
		var pos_c: Vector3 = cf["pos"]
		var abierto := GeneradorCavernaH04.estado_contiene("cofres", id_c)
		var nodo_c := GeneradorCavernaH04.crear_cofre(_geometria_proc, id_c, pos_c, float(cf.get("rot", 0.0)), nivel, abierto)
		cofres_nivel.append(nodo_c)
		puntos_evitar_rocas.append(pos_c)
	var ata: Dictionary = plan.get("atajo", {})
	if not ata.is_empty():
		var c_at: Vector2i = ata["celda"]
		var pw := _mundo_celda(c_at)
		var pos_at := Vector3(pw.x, float(ata["y"]), pw.y)
		var id_a := str(ata["id"])
		var abierto := GeneradorCavernaH04.estado_contiene("atajos", id_a)
		var nodo_a := GeneradorCavernaH04.crear_atajo(_geometria_proc, id_a, pos_at, ata["dir"] as Vector2i, abierto)
		atajos_nivel.append(nodo_a)
		puntos_evitar_rocas.append(pos_at)


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

	var st_techo := SurfaceTool.new()
	st_techo.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_techo.set_smooth_group(0)
	var tono_techo := col_roca.lerp(Color(0.70, 0.68, 0.65), 0.42)
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

		var t0 := Vector3(p0.x, _altura_techo(c, alto_muro), p0.z)
		var t1 := Vector3(p1.x, _altura_techo(c + Vector2i.RIGHT, alto_muro), p1.z)
		var t2 := Vector3(p2.x, _altura_techo(c + Vector2i.ONE, alto_muro), p2.z)
		var t3 := Vector3(p3.x, _altura_techo(c + Vector2i.DOWN, alto_muro), p3.z)
		for tri in [[t0, t2, t1], [t0, t3, t2]]:
			st_techo.set_color(tono_techo)
			for v: Vector3 in tri:
				st_techo.add_vertex(v)
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
			var va_techo := Vector3(va.x, alto_muro, va.z)
			var vb_techo := Vector3(vb.x, alto_muro, vb.z)
			for tri in [[va_techo, vb_t, vb_techo], [va_techo, va_t, vb_t]]:
				st_techo.set_color(tono_techo)
				for v: Vector3 in tri:
					st_techo.add_vertex(v)

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
				var borde0 := Vector3(cn.x - ms, alto_muro, cn.y - ms)
				var borde1 := Vector3(cn.x + ms, alto_muro, cn.y - ms)
				var borde2 := Vector3(cn.x + ms, alto_muro, cn.y + ms)
				var borde3 := Vector3(cn.x - ms, alto_muro, cn.y + ms)
				var c_cap := Color(col_roca.r * 0.35, col_roca.g * 0.35, col_roca.b * 0.35)
				for tri in [[borde0, borde1, borde2], [borde0, borde2, borde3]]:
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
	_montar_techo(st_techo)

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


func _altura_techo(esquina: Vector2i, alto_muro: float) -> float:
	# El contorno coincide con las paredes, mientras el interior del techo conserva relieve.
	for adyacente in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, -Vector2i.ONE]:
		if not _celdas_cavadas.has(esquina + adyacente):
			return alto_muro
	return alto_muro + 0.16 * sin(float(esquina.x) * 0.61) + 0.18 * cos(float(esquina.y) * 0.47)


func _montar_techo(superficie: SurfaceTool) -> void:
	superficie.generate_normals()
	var roca := StandardMaterial3D.new()
	CargadorMapa.aplicar_pbr_techo_roca(roca)
	roca.vertex_color_use_as_albedo = true
	roca.vertex_color_is_srgb = true
	var techo := MeshInstance3D.new()
	techo.name = "TechoCaverna"
	techo.layers = FotoCenital.CAPA_TECHOS
	techo.mesh = superficie.commit()
	techo.material_override = roca
	_geometria_proc.add_child(techo)


func _colocar_ambientacion_especifica(azar: RandomNumberGenerator) -> void:
	if _geometria_proc == null:
		return
	var borde_celdas: Array[Vector2i] = []
	var interiores: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c: Vector2i in _celdas_cavadas:
		var tipo_c := str((_celdas_info.get(c, {}) as Dictionary).get("tipo", ""))
		if int(_distancias.get(c, 0)) < 3 or c == _celda_bajada or tipo_c in ["puente", "rampa", "atajo"]:
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
	if borde_celdas.is_empty():
		return

	match ambientacion_id:
		"humeda":
			var mat_agua := material_agua_subterranea()
			var n_charcos := mini(5 + nivel / 2, borde_celdas.size())
			for i in n_charcos:
				var c := borde_celdas[(i * 7 + azar.randi_range(0, 3)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var h := _altura_celda(c)
				var disco := MeshInstance3D.new()
				disco.name = "Charco_%d" % i
				var pm := PlaneMesh.new()
				var lado := 3.4 if i == 0 else azar.randf_range(1.9, 2.7)
				pm.size = Vector2(lado, lado * (0.95 if i == 0 else azar.randf_range(0.85, 1.15)))
				disco.mesh = pm
				disco.material_override = mat_agua
				disco.position = Vector3(p.x, h + 0.015, p.y)
				disco.rotation.y = azar.randf_range(0.0, TAU)
				disco.visibility_range_end = 58.0
				_geometria_proc.add_child(disco)
				if i == 0:
					var zp := ZonaPesca.new()
					zp.name = "LagoSubterraneo"
					zp.marcador_pesca = ""
					zp.id_zona_fija = ID_MAPA
					zp.radio_uso = 6.2
					zp.position = Vector3(p.x, h + 0.04, p.y)
					_geometria_proc.add_child(zp)
		"cristal":
			var mats: Array[StandardMaterial3D] = []
			for col_c in [Color(0.62, 0.28, 0.92), Color(0.22, 0.76, 0.94)]:
				var mc := StandardMaterial3D.new()
				mc.albedo_color = col_c
				mc.emission_enabled = true
				mc.emission = col_c
				mc.emission_energy_multiplier = 0.95
				mc.roughness = 0.14
				mc.metallic = 0.25
				mats.append(mc)
			var n_c := mini(10 + nivel / 2, borde_celdas.size())
			for i in n_c:
				var c := borde_celdas[(i * 5 + azar.randi_range(0, 2)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var h := _altura_celda(c)
				var base := Node3D.new()
				base.name = "Cristales_%d" % i
				base.position = Vector3(p.x + azar.randf_range(-0.6, 0.6), h, p.y + azar.randf_range(-0.6, 0.6))
				var mat_e := mats[i % 2]
				for j in 3:
					var aguja := MeshInstance3D.new()
					var pm := PrismMesh.new()
					pm.size = Vector3(0.26, azar.randf_range(0.75, 1.55), 0.26)
					aguja.mesh = pm
					aguja.material_override = mat_e
					aguja.position = Vector3(azar.randf_range(-0.22, 0.22), pm.size.y * 0.42, azar.randf_range(-0.22, 0.22))
					aguja.rotation_degrees = Vector3(azar.randf_range(-16, 16), azar.randf_range(0, 180), azar.randf_range(-16, 16))
					aguja.visibility_range_end = 54.0
					base.add_child(aguja)
				if i % 2 == 0:
					var lc := OmniLight3D.new()
					lc.light_color = mat_e.albedo_color
					lc.light_energy = 1.10
					lc.omni_range = 7.8
					lc.shadow_enabled = false
					lc.set_meta("sin_sombra", true)
					lc.position = Vector3(0.0, 0.9, 0.0)
					base.add_child(lc)
				_geometria_proc.add_child(base)
				puntos_evitar_rocas.append(base.position)
		"magma":
			var mat_lava := GeneradorCavernaH04.material_magma()
			var n_l := mini(8 + nivel / 2, borde_celdas.size())
			for i in n_l:
				var c := borde_celdas[(i * 6 + azar.randi_range(0, 3)) % borde_celdas.size()]
				var p := _mundo_celda(c)
				var h := _altura_celda(c)
				var pos := Vector3(p.x, h + 0.03, p.y)
				var poza := MeshInstance3D.new()
				poza.name = "Magma_%d" % i
				var cm := CylinderMesh.new()
				cm.top_radius = azar.randf_range(0.85, 1.25)
				cm.bottom_radius = cm.top_radius * 1.12
				cm.height = 0.06
				cm.radial_segments = 14
				poza.mesh = cm
				poza.material_override = mat_lava
				poza.position = pos
				poza.visibility_range_end = 58.0
				_geometria_proc.add_child(poza)
				if i % 2 == 0:
					var ll := OmniLight3D.new()
					ll.light_color = Color(1.0, 0.40, 0.12)
					ll.light_energy = 1.40
					ll.omni_range = 8.4
					ll.shadow_enabled = false
					ll.set_meta("sin_sombra", true)
					ll.position = pos + Vector3(0.0, 0.7, 0.0)
					_geometria_proc.add_child(ll)
				puntos_evitar_rocas.append(pos)
		_:
			var mat_p := GeneradorCavernaH04._mat_viga()
			for i in mini(5, interiores.size()):
				var c := interiores[(i * 4) % interiores.size()]
				var p := _mundo_celda(c)
				var h := _altura_celda(c)
				var pilar := StaticBody3D.new()
				pilar.name = "Puntal_%d" % i
				pilar.collision_layer = CAPA_SOLO_JUGADOR
				pilar.collision_mask = 0
				pilar.position = Vector3(p.x, h, p.y)
				var mi := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.32, 6.4, 0.32)
				mi.mesh = box
				mi.material_override = mat_p
				mi.position = Vector3(0.0, 3.2, 0.0)
				mi.visibility_range_end = 54.0
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
	m_bajada.global_position = Vector3(dest.x, _altura_celda(_celda_bajada), dest.y)


func _colocar_elementos_nivel(mapa: Node, azar: RandomNumberGenerator) -> void:
	# 1. Antorchas con luz real repartidas por vestíbulo y puntos clave (dejando corredores oscuros para el farol).
	var candidatas_ant: Array[Vector2i] = []
	for c: Vector2i in _celdas_cavadas:
		var t_c := str((_celdas_info.get(c, {}) as Dictionary).get("tipo", ""))
		if t_c in ["sala", "galeria"]:
			candidatas_ant.append(c)
	candidatas_ant.sort()
	_poner_antorcha(Vector3(401.2, 0.0, -1.2))
	_poner_antorcha(Vector3(401.2, 0.0, 1.2))
	var dest_b := _mundo_celda(_celda_bajada)
	var hb := _altura_celda(_celda_bajada)
	_poner_antorcha(Vector3(dest_b.x - 1.0, hb, dest_b.y))
	var objetivo_ant := clampi(6 + nivel / 3, 6, 12)
	var paso_i := maxi(candidatas_ant.size() / maxi(objetivo_ant, 1), 1)
	for i in range(0, candidatas_ant.size(), paso_i):
		if posiciones_antorchas.size() >= objetivo_ant:
			break
		var cc := candidatas_ant[i]
		var pos2 := _mundo_celda(cc)
		var pos := Vector3(pos2.x + 0.75, _altura_celda(cc), pos2.y + 0.75)
		var demasiado_cerca := false
		for ya in posiciones_antorchas:
			if ya.distance_to(pos) < 10.5:
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

	# 4. Puntos de aparición de enemigos (y el jefe en los niveles 5, 10, 15 y 20).
	_colocar_puntos_enemigos(azar)
	if nivel % 5 == 0 and Enemigo.ACTIVOS:
		_colocar_puerta_oculta_jefe(mapa)


func salida_habitual_bloqueada() -> bool:
	return nivel % 5 == 0 and jefe_vivo and Enemigo.ACTIVOS


func puerta_oculta_abierta() -> bool:
	return _puerta_oculta_abierta


func _colocar_puerta_oculta_jefe(_mapa_n: Node) -> void:
	var dest_b := _mundo_celda(_celda_bajada)
	var p_puerta := Vector3(dest_b.x + 2.2, _altura_celda(_celda_bajada), dest_b.y)
	var s := AyudasL4b.suelo(self, p_puerta, 1.5, 3.0)
	if s == Vector3.INF:
		s = Vector3(dest_b.x - 2.0, _altura_celda(_celda_bajada), dest_b.y)
		var s2 := AyudasL4b.suelo(self, s, 1.5, 3.0)
		if s2 != Vector3.INF:
			s = s2
		else:
			s = Vector3(dest_b.x, _altura_celda(_celda_bajada), dest_b.y + 1.8)

	var marco := Node3D.new()
	marco.name = "PuertaOcultaJefe"
	marco.position = s
	add_child(marco)
	nodo_puerta_oculta = marco

	var mat_roca := StandardMaterial3D.new()
	mat_roca.albedo_color = Color(0.24, 0.22, 0.21)
	mat_roca.roughness = 0.92
	var mat_losa := StandardMaterial3D.new()
	mat_losa.albedo_color = Color(0.32, 0.29, 0.26)
	mat_losa.roughness = 0.88

	for sx in [-0.85, 0.85]:
		var jamba := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 2.35, 0.48)
		jamba.mesh = bm
		jamba.material_override = mat_roca
		jamba.position = Vector3(sx, 1.18, 0.0)
		marco.add_child(jamba)

	var dintel := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.05, 0.34, 0.52)
	dintel.mesh = dm
	dintel.material_override = mat_roca
	dintel.position = Vector3(0.0, 2.38, 0.0)
	marco.add_child(dintel)

	# Losa deslizante oculta: sellada y sólida mientras viva el jefe; se aparta al derrotarlo.
	var hoja := StaticBody3D.new()
	hoja.name = "LosaPuertaOculta"
	hoja.collision_layer = CAPA_SOLO_JUGADOR
	hoja.collision_mask = 0
	var mlosa := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.38, 2.15, 0.26)
	mlosa.mesh = lm
	mlosa.material_override = mat_losa
	mlosa.position = Vector3(0.0, 1.08, 0.0)
	hoja.add_child(mlosa)
	var cs_l := CollisionShape3D.new()
	var bs_l := BoxShape3D.new()
	bs_l.size = lm.size
	cs_l.shape = bs_l
	cs_l.position = Vector3(0.0, 1.08, 0.0)
	hoja.add_child(cs_l)
	marco.add_child(hoja)
	_hoja_puerta_oculta = hoja

	var luz := OmniLight3D.new()
	luz.light_color = Color(0.42, 0.96, 0.68)
	luz.light_energy = 0.0
	luz.omni_range = 7.5
	luz.shadow_enabled = false
	luz.set_meta("sin_sombra", true)
	luz.position = Vector3(0.0, 1.4, 0.3)
	marco.add_child(luz)
	_luz_puerta_oculta = luz

	var destino_nv := nivel + 1
	var p := Interactuable.new()
	p.name = "InteractuablePuertaOculta"
	p.verbo = "Entrar" if nivel < MAX_NIVEL else "Salir"
	p.nombre_objeto = ("por la puerta oculta al nivel %d" % destino_nv) if nivel < MAX_NIVEL else "por la cámara oculta al exterior"
	p.radio = 1.65
	p.altura_marca = 1.9
	p.mostrar_descripcion = false
	p.activo = false
	p.usado.connect(func(_j: Node3D) -> void:
		if not _puerta_oculta_abierta:
			return
		if nivel < MAX_NIVEL:
			_viajar_ascensor(destino_nv)
		else:
			Interfaz.preguntar("Has superado al guardián del fondo (nivel 20). ¿Salir por el pasadizo oculto al exterior?", ["Salir al exterior", "Quedarme"], func(idx: int) -> void:
				if idx == 0:
					Escenas.ir_a_mapa("mina_exterior", "Spawn_Protagonista")))
	marco.add_child(p)
	_punto_puerta_oculta = p
	puntos_evitar_rocas.append(s)


func _al_morir_jefe(_en: Enemigo) -> void:
	if not jefe_vivo:
		return
	jefe_vivo = false
	_abrir_puerta_oculta()
	jefe_derrotado.emit()


func _abrir_puerta_oculta() -> void:
	if _puerta_oculta_abierta:
		return
	_puerta_oculta_abierta = true
	if _punto_puerta_oculta != null and is_instance_valid(_punto_puerta_oculta):
		_punto_puerta_oculta.activo = true
	if _luz_puerta_oculta != null and is_instance_valid(_luz_puerta_oculta):
		_luz_puerta_oculta.light_energy = 1.65
	if _hoja_puerta_oculta != null and is_instance_valid(_hoja_puerta_oculta):
		_hoja_puerta_oculta.collision_layer = 0
		var tw := _hoja_puerta_oculta.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_hoja_puerta_oculta, "position:x", 1.35, 0.9)
	Audio.reproducir("mina_atajo")
	var msg := "¡Has derrotado al guardián! Se ha abierto una puerta oculta hacia el nivel %d." % (nivel + 1) if nivel < MAX_NIVEL else "¡El guardián final ha caído! Se abre el pasadizo oculto de salida."
	Interfaz.mensaje(msg)


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
		Vector3(410.5, 0.0, -1.5),
		Vector3(420.5, 0.0, -8.5),
		Vector3(428.0, 0.0, -17.0),
		Vector3(434.2, 0.0, -14.5),
		Vector3(448.5, 0.0, -16.0),
		Vector3(449.0, 2.0, -4.0),
	]
	for p: Vector3 in candidatos_l1:
		var suelo := AyudasL4b.suelo(self, p, 1.5, 3.5)
		if suelo == Vector3.INF:
			suelo = AyudasL4b.sitio_libre(self, p, 0.25, 3.5)
		if suelo != Vector3.INF:
			var lejos := true
			for ya in posiciones_antorchas:
				if ya.distance_to(suelo) < 4.5:
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

	# Nivel 2: coloca la bajada adicional hacia el nivel 3 en la cámara este sin tocar Bajada_Nivel_2 («Subir al nivel 1»).
	if nivel == 2:
		var p_baj2 := m_baj.global_position if m_baj != null else Vector3(431.0, 0.0, -14.0)
		var objetivos := [
			_escalera_profunda_ala if _escalera_profunda_ala != Vector3.INF else Vector3(448.5, 0.0, -16.0),
			Vector3(448.5, 0.0, -16.0),
			Vector3(424.0, 0.0, -19.0),
			Vector3(417.0, 0.0, -14.5),
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
	luz.light_energy = 1.55
	luz.omni_range = 10.5
	luz.omni_attenuation = 1.35
	if posiciones_antorchas.size() <= 3:
		luz.set_meta("sombra_h03", true)
	else:
		luz.set_meta("sin_sombra", true)
	GraficaH03.ajustar_luz(luz, int(Ajustes.valores.calidad))
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
		var tc := str((_celdas_info.get(c, {}) as Dictionary).get("tipo", ""))
		if int(_distancias.get(c, 0)) >= 5 and c != _celda_bajada and not (tc in ["puente", "rampa", "atajo"]):
			candidatas.append(c)
	candidatas.sort()
	if candidatas.is_empty():
		candidatas.append(Vector2i(3, 0))
	for i in range(candidatas.size() - 1, 0, -1):
		var j := azar.randi_range(0, i)
		var tmp := candidatas[i]
		candidatas[i] = candidatas[j]
		candidatas[j] = tmp

	# Jefe en los niveles 5, 10, 15 y 20: uno solo, en la zona más despejada y alejada de la llegada.
	var jefe := Enemigo.jefe_para_nivel(nivel)
	var celda_jefe := Vector2i(999999, 999999)
	if not jefe.is_empty():
		celda_jefe = _celda_con_espacio(candidatas)
		var pj := _mundo_celda(celda_jefe)
		_registrar_punto_enemigo(0, Vector3(pj.x, _altura_celda(celda_jefe), pj.y), jefe)

	var catalogo := Enemigo.normales_para_nivel(nivel)
	var cantidad := clampi(4 + nivel / 2, 4, 12) - (1 if not jefe.is_empty() else 0)
	var puestos: Array[Vector2] = []
	var colocados := 0
	for c: Vector2i in candidatas:
		if colocados >= cantidad or catalogo.is_empty():
			break
		if c == celda_jefe or (not jefe.is_empty() and Vector2(c - celda_jefe).length() < 3.5):
			continue
		var p2 := _mundo_celda(c)
		var separado := true
		for ya_p: Vector2 in puestos:
			if ya_p.distance_to(p2) < 6.0:
				separado = false
				break
		if not separado:
			continue
		puestos.append(p2)
		_registrar_punto_enemigo(colocados + 1, Vector3(p2.x, _altura_celda(c), p2.y), catalogo[colocados % catalogo.size()])
		colocados += 1


## Celda pisable con más celdas libres alrededor (radio de 2 celdas = 5 m), lejos de la llegada: sitio con espacio para un jefe.
func _celda_con_espacio(candidatas: Array[Vector2i]) -> Vector2i:
	var mejor := candidatas[0]
	var mejor_valor := -1.0
	for c: Vector2i in candidatas:
		var libres := 0
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				if _celdas_cavadas.has(c + Vector2i(dx, dz)):
					libres += 1
		var valor := float(libres) * 10.0 + float(int(_distancias.get(c, 0)))
		if valor > mejor_valor:
			mejor_valor = valor
			mejor = c
	return mejor


func _colocar_puntos_enemigos_clasicos(p_lleg: Vector3, _azar: RandomNumberGenerator) -> void:
	if puntos_enemigos != null and is_instance_valid(puntos_enemigos):
		return
	puntos_enemigos = Node3D.new()
	puntos_enemigos.name = "PuntosEnemigos"
	add_child(puntos_enemigos)
	var catalogo := Enemigo.normales_para_nivel(nivel)
	var puestos := [
		Vector3(417.0, 0.0, -5.0),
		Vector3(424.0, 0.0, -10.5),
		Vector3(429.0, 0.0, -15.0),
		Vector3(446.5, 0.0, -15.5),
		Vector3(448.5, 2.0, -4.0),
	]
	for i in puestos.size():
		var s := AyudasL4b.suelo(self, puestos[i], 1.5, 3.0)
		var pos := s if s != Vector3.INF else p_lleg + Vector3(6.0 + float(i) * 2.5, 0.0, -4.0 - float(i) * 2.5)
		_registrar_punto_enemigo(i, pos, catalogo[i % catalogo.size()] if not catalogo.is_empty() else {})


func _registrar_punto_enemigo(indice: int, pos: Vector3, datos: Dictionary) -> void:
	if not datos.is_empty():
		datos = datos.duplicate()
		datos["nivel_mina"] = nivel
	var m := Marker3D.new()
	m.name = "SpawnEnemigo_%d" % (indice + 1)
	m.position = pos
	m.set_meta("enemigo_id", str(datos.get("id", "")))
	m.set_meta("enemigo_datos", datos)
	puntos_enemigos.add_child(m)
	if Enemigo.ACTIVOS and not datos.is_empty():
		var en := Enemigo.new()
		en.configurar(datos)
		en.position = pos + Vector3(0.0, 0.25, 0.0)
		puntos_enemigos.add_child(en)
		if en.es_jefe and nivel % 5 == 0:
			jefe_vivo = true
			en.fallecido.connect(_al_morir_jefe)


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


# --- Niebla de guerra en minimapa y mapa grande ---------------------------------------------------------

func _inicializar_niebla(mapa: Node) -> void:
	_niebla_rect = mapa.call("rect_mapa") if mapa.has_method("rect_mapa") else Rect2(394, -36, 80, 60)
	if not (Juego.estado_mapas.get(ID_MAPA, null) is Dictionary):
		Juego.estado_mapas[ID_MAPA] = {}
	var est: Dictionary = Juego.estado_mapas[ID_MAPA]
	if int(est.get("niebla_dia", -1)) != AyudasL4b.clave_dia():
		est["niebla_dia"] = AyudasL4b.clave_dia()
		est["niebla"] = {}
	if not (est.get("niebla", null) is Dictionary):
		est["niebla"] = {}
	var dic_niebla: Dictionary = est["niebla"]
	var clave := str(nivel)
	var bytes_n := TAM_NIEBLA * TAM_NIEBLA
	if dic_niebla.get(clave, null) is PackedByteArray and (dic_niebla[clave] as PackedByteArray).size() == bytes_n:
		_niebla_bytes = dic_niebla[clave] as PackedByteArray
	else:
		_niebla_bytes = PackedByteArray()
		_niebla_bytes.resize(bytes_n)
		_niebla_bytes.fill(0)
		dic_niebla[clave] = _niebla_bytes
	_niebla_img = Image.create_from_data(TAM_NIEBLA, TAM_NIEBLA, false, Image.FORMAT_R8, _niebla_bytes)
	_niebla_tex = ImageTexture.create_from_image(_niebla_img)
	_niebla_overlay_img = Image.create(TAM_NIEBLA, TAM_NIEBLA, false, Image.FORMAT_RGBA8)
	_niebla_overlay_tex = ImageTexture.create_from_image(_niebla_overlay_img)
	_actualizar_textura_overlay_niebla()
	var m_lleg := mapa.call("marcador", "Llegada_Interior") as Marker3D
	if m_lleg != null:
		revelar_niebla_en(Vector2(m_lleg.global_position.x, m_lleg.global_position.z), RADIO_REVELAR + 1.5)
	var j := Escenas.jugador()
	if j != null:
		revelar_niebla_en(Vector2(j.global_position.x, j.global_position.z), RADIO_REVELAR)


func _actualizar_textura_overlay_niebla() -> void:
	if _niebla_overlay_img == null or _niebla_overlay_tex == null:
		return
	for z in TAM_NIEBLA:
		for x in TAM_NIEBLA:
			var v := float(_niebla_bytes[z * TAM_NIEBLA + x]) / 255.0
			var a := (1.0 - v) * 0.94
			_niebla_overlay_img.set_pixel(x, z, Color(0.045, 0.045, 0.058, a))
	_niebla_overlay_tex.update(_niebla_overlay_img)


func revelar_niebla_en(pos_xz: Vector2, radio: float = RADIO_REVELAR) -> void:
	if _niebla_bytes.is_empty() or _niebla_rect.size.x <= 0.0 or _niebla_rect.size.y <= 0.0:
		return
	var cambios := false
	var gx_c := ((pos_xz.x - _niebla_rect.position.x) / _niebla_rect.size.x) * float(TAM_NIEBLA - 1)
	var gz_c := ((pos_xz.y - _niebla_rect.position.y) / _niebla_rect.size.y) * float(TAM_NIEBLA - 1)
	var rx := (radio / _niebla_rect.size.x) * float(TAM_NIEBLA - 1)
	var rz := (radio / _niebla_rect.size.y) * float(TAM_NIEBLA - 1)
	var x0 := maxi(0, floori(gx_c - rx))
	var x1 := mini(TAM_NIEBLA - 1, ceili(gx_c + rx))
	var z0 := maxi(0, floori(gz_c - rz))
	var z1 := mini(TAM_NIEBLA - 1, ceili(gz_c + rz))
	for z in range(z0, z1 + 1):
		var dz := (float(z) - gz_c) / maxf(rz, 0.01)
		for x in range(x0, x1 + 1):
			var dx := (float(x) - gx_c) / maxf(rx, 0.01)
			var d := sqrt(dx * dx + dz * dz)
			if d <= 1.0:
				var valor := clampi(roundi(smoothstep(1.0, 0.55, d) * 255.0), 0, 255)
				var idx := z * TAM_NIEBLA + x
				if valor > int(_niebla_bytes[idx]):
					_niebla_bytes[idx] = valor
					cambios = true
	if cambios and _niebla_img != null and _niebla_tex != null:
		_niebla_img.set_data(TAM_NIEBLA, TAM_NIEBLA, false, Image.FORMAT_R8, _niebla_bytes)
		_niebla_tex.update(_niebla_img)
		_actualizar_textura_overlay_niebla()
		if Juego.estado_mapas.get(ID_MAPA, null) is Dictionary:
			var est: Dictionary = Juego.estado_mapas[ID_MAPA]
			if est.get("niebla", null) is Dictionary:
				(est["niebla"] as Dictionary)[str(nivel)] = _niebla_bytes
		niebla_actualizada.emit()


func textura_niebla() -> Texture2D:
	return _niebla_tex


func textura_niebla_overlay() -> Texture2D:
	return _niebla_overlay_tex


func rect_niebla() -> Rect2:
	return _niebla_rect


func es_punto_explorado(pos_xz: Vector2) -> bool:
	if _niebla_bytes.is_empty() or _niebla_rect.size.x <= 0.0 or _niebla_rect.size.y <= 0.0:
		return true
	var gx := clampi(roundi(((pos_xz.x - _niebla_rect.position.x) / _niebla_rect.size.x) * float(TAM_NIEBLA - 1)), 0, TAM_NIEBLA - 1)
	var gz := clampi(roundi(((pos_xz.y - _niebla_rect.position.y) / _niebla_rect.size.y) * float(TAM_NIEBLA - 1)), 0, TAM_NIEBLA - 1)
	return int(_niebla_bytes[gz * TAM_NIEBLA + gx]) >= 64


func fraccion_explorada() -> float:
	if _niebla_bytes.is_empty():
		return 0.0
	var vis := 0
	for b in _niebla_bytes:
		if int(b) >= 64:
			vis += 1
	return float(vis) / float(_niebla_bytes.size())
