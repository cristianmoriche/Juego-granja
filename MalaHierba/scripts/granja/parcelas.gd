class_name Parcelas
extends Node3D
## Parcelas de la granja (L4a): lee las zonas `Zona_Cultivo_*` del mapa, dibuja el estado de cada casilla de 1 m
## (con un MultiMesh por tipo, para que sea ligero) y atiende las herramientas del jugador (grupo «usable»).
## Los datos y las reglas están en el autoload `Cultivos`; aquí solo la geometría, lo visual y el cursor.
##
## Va dentro del nodo `Objetos` de `escenas/mapas/granja.tscn`. Se construye al llegar `Escenas.mapa_cargado("granja")`
## (también se puede llamar a `construir()` a mano).

const ID_MAPA := "granja"
const MAX_LADO := 40
const RESERVA_TAM := Vector2(10, 8)
const RESERVA_DISTANCIA := 2.5
const ALTO_ARADO := 0.07
const CapaMundo := 1

const RUTA_SUELO := "res://assets/texturas/farm_soil/farm_soil_albedo.jpg"
const RUTA_CORTEZA := "res://assets/texturas/pine_bark/pine_bark_albedo.jpg"
const RUTA_ROCA := "res://assets/texturas/rocky_terrain_02/rocky_terrain_02_albedo.jpg"
const DUR_SALTO_FASE := 0.62

# Forma de cada cultivo: ancho, alto, tamaño del fruto, altura del fruto sobre el suelo, tinte de las hojas.
const FORMAS := {
	"patata": [1.0, 0.8, 1.0, 0.0, Color(0.9, 1.0, 0.85)],
	"zanahoria": [0.7, 0.75, 0.9, 0.0, Color(1.0, 1.15, 0.95)],
	"haba": [0.8, 1.3, 1.0, 0.1, Color(0.9, 1.05, 1.0)],
	"tomate": [1.0, 1.4, 1.1, 0.12, Color(1.0, 1.0, 0.95)],
	"pimiento": [0.9, 1.1, 1.0, 0.1, Color(0.95, 1.05, 0.9)],
	"melon": [1.5, 0.6, 2.0, 0.0, Color(1.0, 1.1, 0.9)],
	"calabaza": [1.6, 0.7, 2.3, 0.0, Color(0.95, 1.05, 0.85)],
	"col": [1.2, 0.7, 1.8, 0.0, Color(0.75, 1.05, 1.0)],
	"boniato": [1.4, 0.55, 1.0, 0.0, Color(1.0, 0.9, 1.05)],
	"ajo": [0.6, 0.9, 0.9, 0.0, Color(1.1, 1.1, 0.85)],
	"espinaca": [1.05, 0.55, 0.9, 0.0, Color(0.32, 0.72, 0.35)],
	"nabo": [0.85, 0.7, 1.35, 0.0, Color(0.48, 0.82, 0.44)],
	"azafran": [0.75, 0.85, 1.15, 0.16, Color(0.38, 0.76, 0.42)],
}

var _zonas: Array[Dictionary] = []     # nombre, centro, yaw, nx, nz
var _celdas: Dictionary = {}           # clave -> {pos, yaw, x, z, zona}
var _listo: bool = false
var _sucio: bool = false
var _firma_obstaculos: String = ""

var _mm_arado: MultiMeshInstance3D
var _mm_limpio: MultiMeshInstance3D
var _mm_hierba: MultiMeshInstance3D
var _mm_piedra: MultiMeshInstance3D
var _mm_tronco: MultiMeshInstance3D
var _mm_planta: MultiMeshInstance3D
var _mm_fruto: MultiMeshInstance3D
var _cuerpo: StaticBody3D
var _marcas: Array[MeshInstance3D] = []
var _proxies: Dictionary = {}          # clave -> CultivoListo (interactuable para cosechar)
var _script_listo: GDScript = preload("res://scripts/granja/cultivo_listo.gd")
var _hay_corteza: bool = false
var _anim_fase: Dictionary = {}       # clave -> segundos restantes de salto y brillo
var _brillos_fase: Dictionary = {}    # clave -> intensidad actual de brillo aplicada al shader
var _indices_cultivo: Dictionary = {} # clave -> {p_idx, p_tr, p_col, f_idx, f_tr, f_col}
var _etapas_vistas: Dictionary = {}   # clave -> [id_cultivo, etapa]


func _ready() -> void:
	top_level = true           # sus coordenadas son siempre las del mundo
	add_to_group("usable")
	add_to_group("parcelas_apuntables")
	_crear_nodos()
	Cultivos.parcela_cambiada.connect(func(_k: String) -> void: _sucio = true)
	Cultivos.parcelas_cambiadas.connect(func() -> void: _sucio = true)
	Cultivos.accion_visual.connect(_al_efecto_accion)
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_efecto_accion(tipo: String, clave: String) -> void:
	if not _listo or not is_inside_tree() or not _celdas.has(clave):
		return
	EfectosAccion.soltar(self, tipo, posicion_de(clave))


func _al_mapa_cargado(id: String) -> void:
	if id == ID_MAPA:
		construir()


# --- Construcción de la rejilla -----------------------------------------------------------------------------------

## Lee las zonas del mapa, crea las casillas que falten y dibuja. Se puede repetir.
func construir() -> void:
	_listo = false
	var mapa: Node = get_parent().get_parent() if get_parent() != null else null
	if mapa == null or not mapa.has_method("marcadores_de_tipo"):
		mapa = Escenas.mapa_actual_nodo()
	_zonas = _leer_zonas(mapa)
	_celdas.clear()
	_anim_fase.clear()
	_brillos_fase.clear()
	_indices_cultivo.clear()
	_etapas_vistas.clear()
	var espacio := get_world_3d().direct_space_state
	for zi in _zonas.size():
		var z: Dictionary = _zonas[zi]
		Cultivos.generar_zona(str(z["nombre"]), int(z["nx"]), int(z["nz"]))
		var base := Basis(Vector3.UP, float(z["yaw"]))
		var centro: Vector3 = z["centro"]
		for i in int(z["nx"]):
			for j in int(z["nz"]):
				var local := Vector3(i + 0.5 - float(z["nx"]) * 0.5, 0.0, j + 0.5 - float(z["nz"]) * 0.5)
				var pos: Vector3 = centro + base * local
				pos.y = _altura_suelo(espacio, pos, centro.y)
				_celdas[Cultivos.clave(str(z["nombre"]), i, j)] = {"pos": pos, "yaw": float(z["yaw"]), "x": i, "z": j, "zona": zi}
	_listo = not _celdas.is_empty()
	_sucio = true
	if Cultivos.marchitos_pendientes > 0:
		Interfaz.mensaje("Con el cambio de estación se han marchitado %d cultivos." % Cultivos.marchitos_pendientes)
		Cultivos.marchitos_pendientes = 0


func _altura_suelo(espacio: PhysicsDirectSpaceState3D, pos: Vector3, y_defecto: float) -> float:
	var rq := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 6, 0), pos + Vector3(0, -6, 0), CapaMundo)
	var hit := espacio.intersect_ray(rq)
	if hit.is_empty():
		return y_defecto
	var y: float = (hit["position"] as Vector3).y
	return y if absf(y - y_defecto) < 1.5 else y_defecto


func _leer_zonas(mapa: Node) -> Array[Dictionary]:
	var marcas: Array[Marker3D] = []
	if mapa != null and mapa.has_method("marcadores_de_tipo"):
		for m: Marker3D in mapa.call("marcadores_de_tipo", "zona"):
			if str(m.name).begins_with("Zona_Cultivo"):
				marcas.append(m)
	marcas.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return str(a.name) < str(b.name))
	var res: Array[Dictionary] = []
	for m in marcas:
		var tam: Vector2 = m.get_meta("tam", RESERVA_TAM)
		var b := m.global_transform.basis
		var z := {
			"nombre": str(m.name), "centro": m.global_position, "yaw": atan2(b.z.x, b.z.z),
			"nx": clampi(int(floor(tam.x + 0.001)), 1, MAX_LADO), "nz": clampi(int(floor(tam.y + 0.001)), 1, MAX_LADO),
		}
		if _solapa(z, res):
			push_warning("Parcelas: la zona %s se solapa con otra y se ignora." % z["nombre"])
			continue
		res.append(z)
	if res.is_empty():
		res.append(_zona_de_reserva(mapa))
	return res


## Sin zonas en el mapa: 10 × 8 m delante de `Spawn_Protagonista` (o del jugador si tampoco hay).
func _zona_de_reserva(mapa: Node) -> Dictionary:
	var origen := Vector3.ZERO
	var frente := Vector3(0, 0, 1)
	var m: Marker3D = null
	if mapa != null and mapa.has_method("marcador"):
		m = mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	if m != null:
		origen = m.global_position
		frente = m.global_transform.basis.z
	else:
		var j := Escenas.jugador()
		if j != null:
			origen = j.global_position
			var d: Variant = j.get("direccion")
			if d is Vector3:
				frente = d
	frente.y = 0.0
	frente = frente.normalized() if frente.length() > 0.01 else Vector3(0, 0, 1)
	var centro := origen + frente * (RESERVA_DISTANCIA + RESERVA_TAM.y * 0.5)
	return {"nombre": "Zona_Cultivo_Reserva", "centro": centro, "yaw": atan2(frente.x, frente.z),
		"nx": int(RESERVA_TAM.x), "nz": int(RESERVA_TAM.y)}


func _rect(z: Dictionary) -> Rect2:
	var c: Vector3 = z["centro"]
	var yaw := float(z["yaw"])
	var ex := absf(cos(yaw)) * float(z["nx"]) + absf(sin(yaw)) * float(z["nz"])
	var ez := absf(sin(yaw)) * float(z["nx"]) + absf(cos(yaw)) * float(z["nz"])
	return Rect2(c.x - ex * 0.5, c.z - ez * 0.5, ex, ez)


func _solapa(z: Dictionary, otras: Array[Dictionary]) -> bool:
	var r := _rect(z)
	for o in otras:
		var inter := r.intersection(_rect(o))
		if inter.get_area() > 0.2 * minf(r.get_area(), _rect(o).get_area()):
			return true
	return false


# --- Consultas de casillas ----------------------------------------------------------------------------------------

## Casilla que contiene el punto del mundo: {clave, x, z, zona} o {}.
func celda_en(punto: Vector3) -> Dictionary:
	for zi in _zonas.size():
		var z: Dictionary = _zonas[zi]
		var local: Vector3 = Basis(Vector3.UP, float(z["yaw"])).inverse() * (punto - (z["centro"] as Vector3))
		var i := int(floor(local.x + float(z["nx"]) * 0.5))
		var j := int(floor(local.z + float(z["nz"]) * 0.5))
		if i >= 0 and i < int(z["nx"]) and j >= 0 and j < int(z["nz"]):
			return {"clave": Cultivos.clave(str(z["nombre"]), i, j), "x": i, "z": j, "zona": zi}
	return {}


func posicion_de(k: String) -> Vector3:
	var info: Dictionary = _celdas.get(k, {})
	return info.get("pos", Vector3.ZERO)


func celda_apuntada(apuntado: Dictionary) -> Dictionary:
	if not apuntado.has("punto"):
		return {}
	var punto: Vector3 = apuntado.punto
	var celda := celda_en(punto)
	if celda.is_empty() or apuntado.get("colision") == _cuerpo:
		return celda
	var normal: Vector3 = apuntado.get("normal", Vector3.ZERO)
	if normal.y < 0.3 or absf(punto.y - posicion_de(celda.clave).y) > 0.40:
		return {}
	return celda


func claves() -> Array:
	return _celdas.keys()


func esta_construida() -> bool:
	return _listo


## Hasta tres casillas en línea desde `celda`, hacia donde mira el jugador (en los ejes de la zona).
func _linea(celda: Dictionary, jugador: Node3D, rumbo: Vector3 = Vector3.ZERO) -> Array:
	var res: Array = [celda["clave"]]
	var z: Dictionary = _zonas[int(celda["zona"])]
	var dir := Vector3(0, 0, 1)
	var d: Variant = jugador.get("direccion") if jugador != null else null
	if d is Vector3:
		dir = d
	if not rumbo.is_zero_approx():
		dir = rumbo
	var local := Basis(Vector3.UP, float(z["yaw"])).inverse() * dir
	var paso := Vector2i(int(signf(local.x)), 0) if absf(local.x) >= absf(local.z) else Vector2i(0, int(signf(local.z)))
	for s in range(1, 3):
		var i: int = int(celda["x"]) + paso.x * s
		var j: int = int(celda["z"]) + paso.y * s
		if i < 0 or i >= int(z["nx"]) or j < 0 or j >= int(z["nz"]):
			break
		res.append(Cultivos.clave(str(z["nombre"]), i, j))
	return res


# --- Uso de herramientas (grupo «usable») ---------------------------------------------------------------------------

func usar(id_objeto: String, punto: Vector3, jugador: Node3D) -> bool:
	if not _listo or Escenas.en_transicion:
		return false
	var tipo := str(Datos.objeto(id_objeto).get("tipo", ""))
	if tipo != "herramienta" and tipo != "semilla" and tipo != "tratamiento":
		return false
	var celda := celda_en(punto)
	if celda.is_empty():
		return false
	var lista: Array = [celda["clave"]]
	if (id_objeto == "azada" or id_objeto == "regadera") and Juego.nivel(id_objeto) >= 1:
		lista = _linea(celda, jugador)
	return Cultivos.aplicar(id_objeto, lista)


# --- Nodos fijos ----------------------------------------------------------------------------------------------------

func _crear_nodos() -> void:
	_hay_corteza = ResourceLoader.exists(RUTA_CORTEZA)
	var tex_suelo: Texture2D = load(RUTA_SUELO) if ResourceLoader.exists(RUTA_SUELO) else null
	var sh_nieve: Shader = load("res://shaders/nieve_corteza.gdshader") if ResourceLoader.exists("res://shaders/nieve_corteza.gdshader") else null

	# Tierra arada (despejada al removerla para distinguir lo labrado) y tierra limpia (con algo de escarcha invernal).
	var mat_arado := StandardMaterial3D.new()
	mat_arado.vertex_color_use_as_albedo = true
	mat_arado.vertex_color_is_srgb = true
	mat_arado.albedo_texture = tex_suelo if tex_suelo != null else _textura_tierra(true)
	mat_arado.roughness = 0.96
	mat_arado.metallic_specular = 0.12
	mat_arado.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm_arado = _crear_mm("Arado", _malla_terron(), mat_arado, true, false, true)

	var mat_limpio := StandardMaterial3D.new()
	mat_limpio.vertex_color_use_as_albedo = true
	mat_limpio.vertex_color_is_srgb = true
	mat_limpio.albedo_texture = tex_suelo if tex_suelo != null else _textura_tierra(false)
	mat_limpio.roughness = 0.96
	mat_limpio.metallic_specular = 0.10
	if sh_nieve != null:
		var np_limpio := ShaderMaterial.new()
		np_limpio.shader = sh_nieve
		np_limpio.set_shader_parameter("umbral", 0.96)
		mat_limpio.next_pass = np_limpio
	var plano := PlaneMesh.new()
	plano.size = Vector2(1.0, 1.0)
	_mm_limpio = _crear_mm("Limpio", plano, mat_limpio, true, false, false)

	# Maleza.
	var mat_hierba := StandardMaterial3D.new()
	mat_hierba.vertex_color_use_as_albedo = true
	mat_hierba.vertex_color_is_srgb = true
	mat_hierba.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_hierba.roughness = 0.92
	mat_hierba.metallic_specular = 0.10
	_mm_hierba = _crear_mm("Maleza", _malla_mata(), mat_hierba, true, false, false)

	# Piedras.
	var mat_roca := StandardMaterial3D.new()
	mat_roca.vertex_color_use_as_albedo = true
	mat_roca.roughness = 0.95
	mat_roca.metallic_specular = 0.16
	mat_roca.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(RUTA_ROCA):
		mat_roca.albedo_texture = load(RUTA_ROCA)
		mat_roca.uv1_triplanar = true
		mat_roca.uv1_scale = Vector3(1.4, 1.4, 1.4)
	if sh_nieve != null:
		var np_roca := ShaderMaterial.new()
		np_roca.shader = sh_nieve
		np_roca.set_shader_parameter("umbral", 0.45)
		mat_roca.next_pass = np_roca
	_mm_piedra = _crear_mm("Piedras", _malla_roca(), mat_roca, true, false, true)

	# Troncos caídos.
	var mat_tronco := StandardMaterial3D.new()
	mat_tronco.vertex_color_use_as_albedo = true
	mat_tronco.roughness = 1.0
	if _hay_corteza:
		mat_tronco.albedo_texture = load(RUTA_CORTEZA)
		mat_tronco.uv1_scale = Vector3(2.0, 1.0, 1.0)
	if sh_nieve != null:
		var np_tronco := ShaderMaterial.new()
		np_tronco.shader = sh_nieve
		np_tronco.set_shader_parameter("umbral", 0.42)
		mat_tronco.next_pass = np_tronco
	var cil := CylinderMesh.new()
	cil.top_radius = 0.17
	cil.bottom_radius = 0.2
	cil.height = 1.0
	cil.radial_segments = 10
	cil.rings = 1
	_mm_tronco = _crear_mm("Troncos", cil, mat_tronco, true, false, true)

	# Cultivos: hojas y fruto comparten un shader pequeño (el color del fruto llega como dato de instancia).
	var sombreador := Shader.new()
	sombreador.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 v_tinte;
varying float v_brillo;
void vertex() {
	v_tinte = INSTANCE_CUSTOM.rgb;
	v_brillo = clamp(INSTANCE_CUSTOM.a, 0.0, 1.0);
}
void fragment() {
	vec3 base = mix(COLOR.rgb * v_tinte, v_tinte, COLOR.a);
	ALBEDO = mix(base, base * vec3(1.16, 1.24, 0.90), v_brillo * 0.55);
	EMISSION = mix(base, vec3(0.92, 0.88, 0.52), 0.35) * (v_brillo * 0.45);
	ROUGHNESS = 0.7;
}
"""
	var mat_cultivo := ShaderMaterial.new()
	mat_cultivo.shader = sombreador
	_mm_planta = _crear_mm("Plantas", _malla_planta(), mat_cultivo, false, true, true)
	_mm_fruto = _crear_mm("Frutos", _malla_fruto(), mat_cultivo, false, true, true)

	# Obstáculos con colisión (piedras y troncos).
	_cuerpo = StaticBody3D.new()
	_cuerpo.name = "Obstaculos"
	_cuerpo.collision_layer = 1
	_cuerpo.collision_mask = 0
	add_child(_cuerpo)

	# Recuadro de la casilla a la que apunta Leo (y las dos siguientes si la herramienta trabaja en línea).
	var mat_marca := StandardMaterial3D.new()
	mat_marca.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_marca.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_marca.albedo_texture = _textura_marco()
	mat_marca.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var m := MeshInstance3D.new()
		m.name = "Marca%d" % i
		var q := PlaneMesh.new()
		q.size = Vector2(0.98, 0.98)
		m.mesh = q
		m.material_override = mat_marca
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_marcas.append(m)


func _crear_mm(nombre: String, malla: Mesh, material: Material, colores: bool, custom: bool, sombra: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nombre
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colores
	mm.use_custom_data = custom
	mm.mesh = malla
	mm.instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# --- Dibujo ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _sucio and _listo:
		reconstruir()
	if not _anim_fase.is_empty():
		_actualizar_animacion_fases(delta)
	_actualizar_marcas()


## Redibuja todas las casillas a partir de los datos. Se llama sola cuando algo cambia.
func reconstruir() -> void:
	_sucio = false
	var datos := Cultivos.parcelas()
	for kf: Variant in Cultivos.fases_pendientes.keys():
		var ks := str(kf)
		if _celdas.has(ks):
			_anim_fase[ks] = DUR_SALTO_FASE
	Cultivos.fases_pendientes.clear()
	_indices_cultivo.clear()
	var rng := RandomNumberGenerator.new()
	var arado: Array[Transform3D] = []
	var c_arado: Array[Color] = []
	var limpio: Array[Transform3D] = []
	var c_limpio: Array[Color] = []
	var hierba: Array[Transform3D] = []
	var c_hierba: Array[Color] = []
	var piedra: Array[Transform3D] = []
	var c_piedra: Array[Color] = []
	var tronco: Array[Transform3D] = []
	var c_tronco: Array[Color] = []
	var planta: Array[Transform3D] = []
	var c_planta: Array[Color] = []
	var fruto: Array[Transform3D] = []
	var c_fruto: Array[Color] = []
	var obstaculos: Array[String] = []
	var formas_obst: Array = []
	var listos: Dictionary = {}
	var hay_suelo := ResourceLoader.exists(RUTA_SUELO)

	for k: String in _celdas:
		var c: Dictionary = datos.get(k, {})
		if c.is_empty():
			continue
		var info: Dictionary = _celdas[k]
		var pos: Vector3 = info["pos"]
		var yaw: float = info["yaw"]
		rng.seed = hash(k)
		var giro := yaw + rng.randf() * TAU
		var estado := str(c.get("estado", ""))
		var id_cultivo := str(c.get("cultivo", "")) if estado == "arado" else ""
		if id_cultivo.is_empty():
			_etapas_vistas.erase(k)
			_anim_fase.erase(k)
		match estado:
			"limpio":
				var seco := rng.randf_range(0.88, 1.06)
				limpio.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.98, 1, 0.98)), pos + Vector3(0, 0.02, 0)))
				c_limpio.append(Color(0.28, 0.22, 0.14) * seco if not hay_suelo else Color(0.55, 0.49, 0.42) * seco)
			"arado":
				var regado := bool(c.get("regado", false))
				arado.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.94, 1, 0.94)), pos))
				if regado:
					c_arado.append(Color(0.18, 0.11, 0.07) if not hay_suelo else Color(0.32, 0.27, 0.24))
				else:
					c_arado.append(Color(0.38, 0.25, 0.15) if not hay_suelo else Color(0.68, 0.60, 0.52))
				if id_cultivo != "":
					var etapa_act := int(c.get("etapa", 0))
					if _etapas_vistas.has(k):
						var prev: Array = _etapas_vistas[k]
						if str(prev[0]) == id_cultivo and etapa_act > int(prev[1]):
							_anim_fase[k] = DUR_SALTO_FASE
					_etapas_vistas[k] = [id_cultivo, etapa_act]
					var p_idx := planta.size()
					var f_idx_antes := fruto.size()
					_anadir_cultivo(c, id_cultivo, pos + Vector3(0, ALTO_ARADO - 0.01, 0), giro, planta, c_planta, fruto, c_fruto)
					if planta.size() > p_idx:
						var f_idx := f_idx_antes if fruto.size() > f_idx_antes else -1
						_indices_cultivo[k] = {
							"p_idx": p_idx, "p_tr": planta[p_idx], "p_col": c_planta[p_idx],
							"f_idx": f_idx,
							"f_tr": fruto[f_idx] if f_idx >= 0 else Transform3D.IDENTITY,
							"f_col": c_fruto[f_idx] if f_idx >= 0 else Color.WHITE,
						}
					if bool(c.get("listo", false)):
						listos[k] = pos
			"maleza":
				for n in 3:
					var d := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
					var e := rng.randf_range(0.9, 1.38)
					hierba.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(e, rng.randf_range(0.85, 1.3), e)), pos + d))
					var v := rng.randf_range(0.74, 0.96)
					c_hierba.append(Color(v * 0.94, v * rng.randf_range(0.95, 1.05), v * 0.88))
			"piedra":
				var golpes := int(c.get("golpes", 0))
				var f := 1.0 - 0.18 * golpes
				var sx := rng.randf_range(0.8, 1.1) * f
				var sy := rng.randf_range(0.8, 1.2) * f
				piedra.append(Transform3D(Basis(Vector3.UP, giro) * Basis.from_scale(Vector3(sx, sy, sx * rng.randf_range(0.85, 1.15))), pos + Vector3(0, 0.12 * sy, 0)))
				var g := rng.randf_range(0.8, 1.1)
				c_piedra.append(Color(g, g, g * 1.03))
				obstaculos.append(k)
				formas_obst.append([pos, giro, Vector3(0.75, 0.55, 0.75)])
			"tronco":
				var golpes_t := int(c.get("golpes", 0))
				var grosor := rng.randf_range(0.9, 1.2) * (1.0 - 0.1 * golpes_t)
				var largo := Basis(Vector3.UP, giro) * Basis(Vector3.BACK, PI * 0.5)
				tronco.append(Transform3D(largo * Basis.from_scale(Vector3(grosor, rng.randf_range(0.85, 1.0), grosor)), pos + Vector3(0, 0.19 * grosor, 0)))
				var t := rng.randf_range(0.85, 1.1)
				c_tronco.append(Color(t, t, t) if _hay_corteza else Color(0.36, 0.25, 0.16) * t)
				obstaculos.append(k)
				formas_obst.append([pos, giro, Vector3(1.0, 0.5, 0.45)])
	_llenar(_mm_arado, arado, c_arado)
	_llenar(_mm_limpio, limpio, c_limpio)
	_llenar(_mm_hierba, hierba, c_hierba)
	_llenar(_mm_piedra, piedra, c_piedra)
	_llenar(_mm_tronco, tronco, c_tronco)
	_llenar(_mm_planta, planta, c_planta, true)
	_llenar(_mm_fruto, fruto, c_fruto, true)
	for ka: Variant in _anim_fase.keys():
		var ks := str(ka)
		_aplicar_anim_cultivo(ks, float(_anim_fase[ks]))
	_sincronizar_colisiones(obstaculos, formas_obst)
	_sincronizar_cosechables(listos)


func _actualizar_animacion_fases(delta: float) -> void:
	var claves_activas := _anim_fase.keys()
	for ka: Variant in claves_activas:
		var k := str(ka)
		if not _indices_cultivo.has(k):
			_anim_fase.erase(k)
			continue
		var rem := float(_anim_fase[k])
		if not Escenas.en_transicion:
			rem -= delta
		if rem <= 0.0:
			_aplicar_anim_cultivo(k, 0.0)
			_anim_fase.erase(k)
		else:
			_anim_fase[k] = rem
			_aplicar_anim_cultivo(k, rem)


func _aplicar_anim_cultivo(k: String, restante: float) -> void:
	if not _indices_cultivo.has(k):
		return
	var reg: Dictionary = _indices_cultivo[k]
	var p := clampf(1.0 - (restante / DUR_SALTO_FASE), 0.0, 1.0)
	var pulso := sin(p * PI) if restante > 0.0 else 0.0
	var esc_y := 1.0 + 0.22 * pulso
	var esc_xz := 1.0 + 0.14 * pulso
	var brillo := clampf(0.95 * pulso, 0.0, 1.0)
	if brillo <= 0.001:
		_brillos_fase.erase(k)
	else:
		_brillos_fase[k] = brillo
	var tr_p: Transform3D = reg["p_tr"]
	var col_p: Color = reg["p_col"]
	var mm_p := _mm_planta.multimesh
	var p_idx := int(reg["p_idx"])
	if p_idx >= 0 and p_idx < mm_p.instance_count:
		mm_p.set_instance_transform(p_idx, Transform3D(tr_p.basis * Basis.from_scale(Vector3(esc_xz, esc_y, esc_xz)), tr_p.origin))
		mm_p.set_instance_custom_data(p_idx, Color(col_p.r, col_p.g, col_p.b, brillo))
	var f_idx := int(reg["f_idx"])
	if f_idx >= 0:
		var mm_f := _mm_fruto.multimesh
		if f_idx < mm_f.instance_count:
			var tr_f: Transform3D = reg["f_tr"]
			var col_f: Color = reg["f_col"]
			mm_f.set_instance_transform(f_idx, Transform3D(tr_f.basis * Basis.from_scale(Vector3(esc_xz, esc_y, esc_xz)), tr_f.origin))
			mm_f.set_instance_custom_data(f_idx, Color(col_f.r, col_f.g, col_f.b, brillo))


func animaciones_fase_activas() -> int:
	return _anim_fase.size()


func brillo_fase(clave: String) -> float:
	return float(_brillos_fase.get(clave, 0.0))


func _anadir_cultivo(c: Dictionary, id_cultivo: String, pos: Vector3, giro: float, planta: Array[Transform3D],
		c_planta: Array[Color], fruto: Array[Transform3D], c_fruto: Array[Color]) -> void:
	var def := Datos.cultivo(id_cultivo)
	if def.is_empty():
		return
	var forma: Array = FORMAS.get(id_cultivo, [1.0, 1.0, 1.0, 0.0, Color.WHITE])
	var etapas := maxi(int(def.get("etapas", 4)), 2)
	var f := float(clampi(int(c.get("etapa", 0)), 0, etapas - 1)) / float(etapas - 1)
	var sxz := (0.35 + 0.65 * f) * float(forma[0])
	var sy := (0.25 + 0.75 * f) * float(forma[1])
	planta.append(Transform3D(Basis(Vector3.UP, giro) * Basis.from_scale(Vector3(sxz, sy, sxz)), pos))
	var tinte: Color = forma[4]
	if bool(c.get("listo", false)):
		tinte = Color(tinte.r * 1.1, tinte.g * 0.95, tinte.b * 0.8)   # hojas algo más pajizas al madurar
	if bool(c.get("plaga", false)):
		tinte = Color(0.86, 0.72, 0.24)   # hojas amarillentas con plaga visible
	elif bool(c.get("calidad_baja", false)):
		tinte = Color(tinte.r * 0.78, tinte.g * 0.72, tinte.b * 0.56)
	tinte.a = 0.0
	c_planta.append(tinte)
	if bool(c.get("listo", false)):
		var k := float(forma[2])
		fruto.append(Transform3D(Basis(Vector3.UP, giro) * Basis.from_scale(Vector3(k, k, k)), pos + Vector3(0, float(forma[3]), 0)))
		var cf := Color.html(str(def.get("color", "#cc4444")))
		if bool(c.get("plaga", false)) or bool(c.get("calidad_baja", false)):
			cf = cf.darkened(0.32)
		cf.a = 0.0
		c_fruto.append(cf)


func _llenar(mmi: MultiMeshInstance3D, tr: Array[Transform3D], co: Array[Color], custom: bool = false) -> void:
	var mm := mmi.multimesh
	mm.instance_count = tr.size()
	for i in tr.size():
		mm.set_instance_transform(i, tr[i])
		if custom:
			mm.set_instance_custom_data(i, co[i])
		else:
			mm.set_instance_color(i, co[i])


func _sincronizar_colisiones(claves_obst: Array[String], formas: Array) -> void:
	var firma := ",".join(PackedStringArray(claves_obst))
	if firma == _firma_obstaculos:
		return
	_firma_obstaculos = firma
	for h in _cuerpo.get_children():
		h.queue_free()
	for f: Array in formas:
		var cs := CollisionShape3D.new()
		var caja := BoxShape3D.new()
		caja.size = f[2]
		cs.shape = caja
		cs.transform = Transform3D(Basis(Vector3.UP, float(f[1])), (f[0] as Vector3) + Vector3(0, (f[2] as Vector3).y * 0.5, 0))
		_cuerpo.add_child(cs)


func _sincronizar_cosechables(listos: Dictionary) -> void:
	for k: String in _proxies.keys():
		if not listos.has(k) or not is_instance_valid(_proxies[k]):
			if is_instance_valid(_proxies[k]):
				(_proxies[k] as Node).queue_free()
			_proxies.erase(k)
	for k: String in listos:
		if not _proxies.has(k):
			var p := _script_listo.new() as Node3D
			p.set("clave", k)
			add_child(p)
			p.global_position = listos[k]
			_proxies[k] = p


## Cuántos cultivos listos hay ahora (para pruebas y diagnóstico).
func cosechables() -> int:
	return _proxies.size()


# --- Recuadro del cursor --------------------------------------------------------------------------------------------

func _actualizar_marcas() -> void:
	var punto := Vector3.ZERO
	var celda: Dictionary = {}
	var j := Escenas.jugador()
	if _listo and j is Jugador and not Interfaz.ocupada() and not Escenas.en_transicion:
		var obj := Juego.objeto_activo()
		var tipo := str(Datos.objeto(str(obj.get("id", ""))).get("tipo", "")) if not obj.is_empty() else ""
		if tipo in ["herramienta", "semilla", "tratamiento"]:
			var objetivo: Dictionary = j.apuntado_actual()
			celda = celda_apuntada(objetivo) if objetivo.get("interactuable") == null else {}
			punto = objetivo.get("punto", Vector3.ZERO)
	var lista: Array = []
	if not celda.is_empty():
		var id := str(Juego.objeto_activo().get("id", ""))
		lista = [celda["clave"]]
		if (id == "azada" or id == "regadera") and Juego.nivel(id) >= 1:
			lista = _linea(celda, j, j.direccion_de_uso(punto))
	for i in _marcas.size():
		var m := _marcas[i]
		if i < lista.size() and _celdas.has(lista[i]):
			var info: Dictionary = _celdas[lista[i]]
			m.global_transform = Transform3D(Basis(Vector3.UP, float(info["yaw"])), (info["pos"] as Vector3) + Vector3(0, 0.11, 0))
			m.visible = true
		else:
			m.visible = false


# --- Mallas y texturas procedurales ----------------------------------------------------------------------------------

func _v(st: SurfaceTool, p: Vector3, c: Color, n: Vector3 = Vector3.UP, uv: Vector2 = Vector2.ZERO) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## Terrón de tierra: tapa superior con la textura completa y lados inclinados.
func _malla_terron() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var h := 0.47
	var b := 0.5
	var ya := ALTO_ARADO
	var yb := -0.12
	var blanco := Color.WHITE
	var oscuro := Color(0.7, 0.7, 0.7)
	# Tapa.
	var a1 := Vector3(-h, ya, -h)
	var a2 := Vector3(h, ya, -h)
	var a3 := Vector3(h, ya, h)
	var a4 := Vector3(-h, ya, h)
	_v(st, a1, blanco, Vector3.UP, Vector2(0, 0))
	_v(st, a2, blanco, Vector3.UP, Vector2(1, 0))
	_v(st, a3, blanco, Vector3.UP, Vector2(1, 1))
	_v(st, a1, blanco, Vector3.UP, Vector2(0, 0))
	_v(st, a3, blanco, Vector3.UP, Vector2(1, 1))
	_v(st, a4, blanco, Vector3.UP, Vector2(0, 1))
	# Lados (de la base a la tapa).
	var base: Array[Vector3] = [Vector3(-b, yb, -b), Vector3(b, yb, -b), Vector3(b, yb, b), Vector3(-b, yb, b)]
	var tapa: Array[Vector3] = [a1, a2, a3, a4]
	for i in 4:
		var j := (i + 1) % 4
		var n := ((tapa[j] - tapa[i]).cross(base[i] - tapa[i])).normalized()
		_v(st, base[i], oscuro, n, Vector2(0, 1))
		_v(st, base[j], oscuro, n, Vector2(1, 1))
		_v(st, tapa[j], oscuro, n, Vector2(1, 0))
		_v(st, base[i], oscuro, n, Vector2(0, 1))
		_v(st, tapa[j], oscuro, n, Vector2(1, 0))
		_v(st, tapa[i], oscuro, n, Vector2(0, 0))
	return st.commit()


## Mata de hierba y hojas: unas 14 briznas de dos tramos con la punta inclinada (algunas secas).
func _malla_mata() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.2)
		var fuera := Vector3(cos(ang), 0, sin(ang))
		var base := fuera * r
		var lado := fuera.cross(Vector3.UP).normalized()
		var alto := rng.randf_range(0.35, 0.75)
		var ancho := rng.randf_range(0.035, 0.065)
		var inclin := rng.randf_range(0.1, 0.4)
		var c0 := Color(0.11, 0.19, 0.06)
		var c1 := Color(0.20, 0.33, 0.10)
		var c2 := Color(0.30, 0.44, 0.15)
		if rng.randf() < 0.2:
			c0 = Color(0.22, 0.18, 0.08)
			c1 = Color(0.34, 0.28, 0.12)
			c2 = Color(0.44, 0.36, 0.16)
		var mid := base + fuera * (inclin * alto * 0.4) + Vector3(0, alto * 0.55, 0)
		var punta := base + fuera * (inclin * alto * 1.2) + Vector3(0, alto, 0)
		var p0 := base - lado * ancho
		var p1 := base + lado * ancho
		var m0 := mid - lado * ancho * 0.6
		var m1 := mid + lado * ancho * 0.6
		_v(st, p0, c0)
		_v(st, p1, c0)
		_v(st, m1, c1)
		_v(st, p0, c0)
		_v(st, m1, c1)
		_v(st, m0, c1)
		_v(st, m0, c1)
		_v(st, m1, c1)
		_v(st, punta, c2)
	return st.commit()


## Roca baja y facetada: icosaedro subdividido una vez, deformado con ruido y aplastado; sombreado plano.
func _malla_roca() -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var caras: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10],
		[8, 6, 7], [9, 8, 1]]
	var ruido := FastNoiseLite.new()
	ruido.seed = 5
	ruido.frequency = 1.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for cara: Array in caras:
		var a: Vector3 = v[cara[0]]
		var b: Vector3 = v[cara[1]]
		var c: Vector3 = v[cara[2]]
		var ab := ((a + b) * 0.5).normalized()
		var bc := ((b + c) * 0.5).normalized()
		var ca := ((c + a) * 0.5).normalized()
		for tri: Array in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			# Orden (0, 2, 1): sentido horario visto desde fuera, el que usa Godot.
			for idx in [0, 2, 1]:
				var d: Vector3 = tri[idx]
				var radio := 0.5 * (0.82 + 0.34 * (0.5 + 0.5 * ruido.get_noise_3dv(d * 1.7)))
				var p := d * radio * Vector3(1.0, 0.72, 1.0)
				var g := 0.72 + 0.28 * (0.5 + 0.5 * ruido.get_noise_3dv(d * 3.1 + Vector3(9, 9, 9)))
				st.set_color(Color(g, g, g))
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


## Planta joven: tallo y siete hojas en espiral (alfa del color = 0 → color de hoja).
func _malla_planta() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tallo0 := Color(0.2, 0.32, 0.1, 0.0)
	var tallo1 := Color(0.3, 0.45, 0.14, 0.0)
	for giro in [0.0, PI * 0.5]:
		var l := Vector3(cos(giro), 0, sin(giro)) * 0.018
		_v(st, -l, tallo0)
		_v(st, l, tallo0)
		_v(st, l + Vector3(0, 0.42, 0), tallo1)
		_v(st, -l, tallo0)
		_v(st, l + Vector3(0, 0.42, 0), tallo1)
		_v(st, -l + Vector3(0, 0.42, 0), tallo1)
	for k in 7:
		var f := float(k) / 6.0
		var ang := k * 2.4
		var dir := Vector3(cos(ang), 0, sin(ang))
		var lado := dir.cross(Vector3.UP).normalized()
		var y := 0.06 + 0.34 * f
		var largo := 0.3 - 0.1 * f
		var b := Vector3(0, y, 0)
		var s1 := dir * largo * 0.5 + lado * 0.09 + Vector3(0, y + 0.07, 0)
		var s2 := dir * largo * 0.5 - lado * 0.09 + Vector3(0, y + 0.07, 0)
		var punta := dir * largo + Vector3(0, y + 0.1, 0)
		var c0 := Color(0.16, 0.32, 0.09, 0.0)
		var c1 := Color(0.3, 0.5, 0.15, 0.0)
		var c2 := Color(0.4, 0.6, 0.2, 0.0)
		_v(st, b, c0)
		_v(st, s1, c1)
		_v(st, punta, c2)
		_v(st, b, c0)
		_v(st, punta, c2)
		_v(st, s2, c1)
	return st.commit()


## Fruto maduro: un racimo de cinco esferas pequeñas (sin color de vértice: alfa 1 → color del cultivo).
func _malla_fruto() -> ArrayMesh:
	var esfera := SphereMesh.new()
	esfera.radius = 0.085
	esfera.height = 0.17
	esfera.radial_segments = 10
	esfera.rings = 5
	var st := SurfaceTool.new()
	var puestos: Array[Vector3] = [Vector3(0.14, 0.09, 0.05), Vector3(-0.12, 0.09, 0.1), Vector3(0.02, 0.09, -0.15),
		Vector3(-0.1, 0.1, -0.08), Vector3(0.08, 0.09, 0.15)]
	for p in puestos:
		st.append_from(esfera, 0, Transform3D(Basis.IDENTITY, p))
	return st.commit()


static func _textura_tierra(surcos: bool) -> ImageTexture:
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var ruido := FastNoiseLite.new()
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ruido.frequency = 0.09
	ruido.seed = 11
	for y in 128:
		for x in 128:
			var n := 0.5 + 0.5 * ruido.get_noise_2d(x, y)
			var g := 0.62 + 0.34 * n
			if surcos:
				g *= 0.7 + 0.3 * sin(PI * float(y % 32) / 32.0)
			else:
				g *= 0.92 + 0.08 * ruido.get_noise_2d(x * 3.0, y * 3.0)
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _textura_marco() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var borde := x < 3 or y < 3 or x > 60 or y > 60
			img.set_pixel(x, y, Color(1.0, 0.97, 0.8, 0.95) if borde else Color(1.0, 1.0, 1.0, 0.16))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
