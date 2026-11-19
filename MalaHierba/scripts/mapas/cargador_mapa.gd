class_name CargadorMapa
extends Node3D
## Carga un mapa exportado de Blender (carril L1): geometría estática (glb), colisiones, instancias (MultiMesh en celdas),
## luces y marcadores. Datos en res://assets/mapas/<id_mapa>/ (ver CONTRATO.md).
## Hijos que crea: Geometria, Colisiones (StaticBody3D, capa 1), Instancias, Luces y Marcadores.

@export var id_mapa: String = ""

signal cargado

const RAIZ := "res://assets/mapas/"
const SHADER_TRIPLANAR: Shader = preload("res://shaders/triplanar_tinte.gdshader")
const SHADER_ESTACIONAL: Shader = preload("res://shaders/estandar_estacional.gdshader")
const SHADER_NIEVE_HOJAS: Shader = preload("res://shaders/nieve_hojas.gdshader")
const SHADER_NIEVE_CORTEZA: Shader = preload("res://shaders/nieve_corteza.gdshader")
const SHADER_AGUA: Shader = preload("res://shaders/agua_h03.gdshader")
const SHADER_FOLLAJE: Shader = preload("res://shaders/follaje_h03.gdshader")
const NORMAL_AGUA := "res://assets/agua/ondas_normal.png"
const NORMAL_MADERA_TEJADO := "res://assets/texturas/old_planks_02/old_planks_02_normal.png"
const NORMAL_PIEDRA_MURO := "res://assets/texturas/mossy_stone_wall/mossy_stone_wall_normal.png"
const NORMAL_ROCA_CUEVA := "res://assets/texturas/rocky_terrain_02/rocky_terrain_02_normal.png"
const SUELOS_H03 := {
	"granja": "stony_dirt_path", "pueblo": "stony_dirt_path", "bosque_norte": "forest_floor",
	"costa_lago": "coast_sand_rocks_02", "mina_exterior": "rocks_ground_06",
	"sierra_mirador": "rocky_trail", "robledal_niebla": "leaves_forest_ground",
	"ruinas_valle": "grass_path_2",
}
const SUELOS_H05_SET := ["sierra_mirador", "robledal_niebla", "ruinas_valle"]
const MAPAS_EXTERIORES: Array[String] = [
	"granja", "pueblo", "mina_exterior", "bosque_norte", "costa_lago",
	"sierra_mirador", "robledal_niebla", "ruinas_valle",
]
const TAM_CELDA := 38.0                 # metros: tamaño de cada trozo de MultiMesh para frustum culling por celdas
const ALCANCE_PLANTAS := 75.0           # distancia a partir de la cual desaparecen las plantas pequeñas
const ALTO_CILINDRO_TRONCO := 4.0
const ENERGIA_LUZ_MAX := 1.45
const ENERGIA_LUZ_EXT_MAX := 1.35
const ALCANCE_LUZ := 12.0
const MAX_SOMBRAS_EXT := 2              # máx. luces puntuales con sombra dinámica por mapa exterior
const MAX_SOMBRAS_INT := 4              # máx. luces puntuales con sombra dinámica por mapa interior

var listo: bool = false
var geometria: Node3D
var colisiones: StaticBody3D
var nodo_instancias: Node3D
var nodo_luces: Node3D
var nodo_marcadores: Node3D
var tiempo_carga_ms: int = 0
var num_instancias: int = 0
var num_trozos_multimesh: int = 0

var _datos: Dictionary = {}
var _materiales: Dictionary = {}
var _objetos: Dictionary = {}
var _inst: Dictionary = {}
var _cache_mat: Dictionary = {}
var _cache_forma: Dictionary = {}
var _marcadores: Dictionary = {}
var _mats_estacionales: Array[Dictionary] = []
var _mats_nieve: Array[Dictionary] = []
var _mats_ventana: Array[Dictionary] = []
var _luces_mapa: Array[Dictionary] = []
var _luces_ventana_h03: Array[SpotLight3D] = []
var _mat_nieve_corteza: ShaderMaterial = null
var _cache_forma_malla: Dictionary = {}
var _cache_protos: Dictionary = {}
var _sombras_ext_activas: int = 0
var _sombras_int_activas: int = 0

static var _cache_rutas_mapa: Dictionary = {}
static var _pedidas_hilo: Array[String] = []


static func solicitar_recurso(ruta: String) -> void:
	if ruta.is_empty() or DisplayServer.get_name() == "headless" or ResourceLoader.has_cached(ruta) or not ResourceLoader.exists(ruta):
		return
	var st := ResourceLoader.load_threaded_get_status(ruta)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
		return
	_pedidas_hilo.append(ruta)
	ResourceLoader.load_threaded_request(ruta, "", false)


static func solicitar_lote(rutas: PackedStringArray) -> void:
	for r in rutas:
		solicitar_recurso(r)


static func obtener_recurso(ruta: String) -> Resource:
	if ruta.is_empty() or not ResourceLoader.exists(ruta):
		return null
	var st := ResourceLoader.load_threaded_get_status(ruta)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
		_pedidas_hilo.erase(ruta)
		var r := ResourceLoader.load_threaded_get(ruta)
		if r != null:
			return r
	return load(ruta)


## Libera solicitudes pendientes de hilos y tablas de rutas al volver al menú principal.
static func limpiar_cache_menu() -> void:
	for r: String in _pedidas_hilo:
		var st := ResourceLoader.load_threaded_get_status(r)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
			var _descargado := ResourceLoader.load_threaded_get(r)
	_pedidas_hilo.clear()
	_cache_rutas_mapa.clear()


static func rutas_mapa(id: String) -> PackedStringArray:
	if id.is_empty():
		return PackedStringArray()
	if _cache_rutas_mapa.has(id):
		return _cache_rutas_mapa[id] as PackedStringArray
	var base := RAIZ + id + "/"
	var datos := _leer_json_estatico(base + "marcadores.json")
	var mats := _leer_json_estatico(base + "materiales.json")
	var inst := _leer_json_estatico(base + "instancias.json")
	var rutas := _rutas_de_datos(base, id, datos, mats, inst)
	_cache_rutas_mapa[id] = rutas
	return rutas


static func _rutas_de_datos(base: String, id: String, datos: Dictionary, mats: Dictionary, inst: Dictionary) -> PackedStringArray:
	var vistas: Dictionary = {}
	var salida: Array[String] = []
	var anadir := func(r: String) -> void:
		if not r.is_empty() and not vistas.has(r):
			vistas[r] = true
			salida.append(r)
	# Primero texturas e HDRI para evitar contención al cargar escenas en paralelo.
	for e: Variant in mats.values():
		if e is Dictionary:
			var d := e as Dictionary
			for k: String in ["albedo", "normal", "rugosidad", "ao", "emision"]:
				var t: Variant = d.get(k, "")
				if t is String:
					anadir.call(t as String)
	if not MAPAS_EXTERIORES.has(id):
		var cielo: Variant = datos.get("cielo", null)
		if cielo is Dictionary:
			var hdri: Variant = (cielo as Dictionary).get("hdri", "")
			if hdri is String:
				anadir.call(hdri as String)
	if SUELOS_H03.has(id):
		for mapa_pbr: String in ["diff", "nor_gl", "rough", "disp"]:
			anadir.call(_ruta_suelo_h03(id, mapa_pbr))
	if id == "costa_lago" or id == "bosque_norte" or id == "robledal_niebla" or id == "ruinas_valle":
		anadir.call(NORMAL_AGUA)
	var protos: Dictionary = inst.get("protos", {})
	var info: Dictionary = inst.get("info", {})
	var usados: Dictionary = {}
	for d: Variant in inst.get("instancias", []):
		if d is Dictionary:
			var pv: Variant = (d as Dictionary).get("proto", "")
			if pv is String:
				usados[pv as String] = true
	for p: String in usados.keys():
		var info_p: Dictionary = info.get(p, {}) as Dictionary
		var cat := str(info_p.get("cat", "prop"))
		var lods: Dictionary = info_p.get("lods", {}) as Dictionary
		if cat == "arbol" and lods.has("LOD1"):
			anadir.call(_ruta_proto(base, str(lods.get("LOD1", ""))))
		else:
			anadir.call(_ruta_proto(base, str(protos.get(p, ""))))
			if lods.has("LOD1"):
				anadir.call(_ruta_proto(base, str(lods.get("LOD1", ""))))
			elif lods.has("LOD2"):
				anadir.call(_ruta_proto(base, str(lods.get("LOD2", ""))))
	if id in ["pueblo", "granja", "mina_exterior", "mina_interior"]:
		anadir.call(NORMAL_MADERA_TEJADO)
		anadir.call(NORMAL_PIEDRA_MURO)
		anadir.call(NORMAL_ROCA_CUEVA)
	anadir.call(base + id + ".glb")
	if ResourceLoader.exists(base + id + ".lmbake"):
		anadir.call(base + id + ".lmbake")
	return PackedStringArray(salida)


func _ready() -> void:
	if Juego.has_signal("estacion_cambiada") and not Juego.estacion_cambiada.is_connected(actualizar_estacion):
		Juego.estacion_cambiada.connect(actualizar_estacion)
	if id_mapa != "" and not listo:
		cargar()


func cargar() -> void:
	if id_mapa == "":
		push_error("CargadorMapa: falta id_mapa")
		return
	var t0 := Time.get_ticks_msec()
	var base := RAIZ + id_mapa + "/"
	_datos = _leer_json(base + "marcadores.json")
	_materiales = _leer_json(base + "materiales.json")
	_objetos = _leer_json(base + "objetos.json")
	_inst = _leer_json(base + "instancias.json")
	var rutas := _rutas_de_datos(base, id_mapa, _datos, _materiales, _inst)
	_cache_rutas_mapa[id_mapa] = rutas
	solicitar_lote(rutas)
	_crear_nodos()
	_cargar_geometria(base)
	_cargar_instancias(base)
	_crear_marcadores()
	listo = true
	tiempo_carga_ms = Time.get_ticks_msec() - t0
	cargado.emit()


# ------------------------------------------------------------------------------------------------ API pública
func marcador(nombre: String) -> Marker3D:
	return _marcadores.get(nombre, null)


func marcadores_de_tipo(tipo: String) -> Array[Marker3D]:
	var r: Array[Marker3D] = []
	for m: Marker3D in _marcadores.values():
		if String(m.get_meta("tipo", "otro")) == tipo:
			r.append(m)
	return r


func aabb_mapa() -> AABB:
	var a: Array = _datos.get("aabb", [0, 0, 0, 0, 0, 0])
	var mn := Vector3(a[0], a[1], a[2])
	return AABB(mn, Vector3(a[3], a[4], a[5]) - mn)


func info_sol() -> Dictionary:
	return _datos.get("sol", {}) if _datos.get("sol", null) != null else {}


func info_cielo() -> Dictionary:
	return _datos.get("cielo", {}) if _datos.get("cielo", null) != null else {}


func info_niebla() -> Dictionary:
	return _datos.get("niebla", {}) if _datos.get("niebla", null) != null else {}


func info_ambiente() -> Dictionary:
	return _datos.get("ambiente", {}) if _datos.get("ambiente", null) != null else {}


## Entorno listo para un WorldEnvironment (cielo HDRI o fondo oscuro, niebla, tonemap). Añadido por L1 para que lo use mapa.gd.
func crear_entorno() -> Environment:
	var env := Environment.new()
	var cielo := info_cielo()
	var nieb := info_niebla()
	var amb := info_ambiente()
	if not cielo.is_empty() and ResourceLoader.exists(String(cielo.get("hdri", ""))):
		var cm := PanoramaSkyMaterial.new()
		cm.panorama = obtener_recurso(String(cielo["hdri"])) as Texture2D
		var sky := Sky.new()
		sky.sky_material = cm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.background_energy_multiplier = float(cielo.get("fuerza", 1.0))
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 0.9
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.01, 0.012)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var c: Array = amb.get("color", [0.1, 0.08, 0.06])
		env.ambient_light_color = Color(c[0], c[1], c[2])
		env.ambient_light_energy = float(amb.get("energia", 0.5))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	if not nieb.is_empty():
		var col: Array = nieb.get("color", [0.7, 0.75, 0.85])
		env.fog_enabled = true
		env.fog_light_color = Color(col[0], col[1], col[2])
		env.fog_density = float(nieb.get("densidad", 0.005))
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	return env


## DirectionalLight3D con la luz solar del .blend (null si el mapa no tiene sol, como la cueva).
func crear_sol() -> DirectionalLight3D:
	var s := info_sol()
	if s.is_empty():
		return null
	var luz := DirectionalLight3D.new()
	luz.name = "Sol"
	var d: Array = s["dir"]
	var dir := Vector3(d[0], d[1], d[2]).normalized()
	var arriba := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	luz.transform = Transform3D(Basis.looking_at(dir, arriba), Vector3.ZERO)
	var c: Array = s.get("color", [1, 1, 1])
	luz.light_color = Color(c[0], c[1], c[2])
	luz.light_energy = float(s.get("energia", 1.0))
	luz.shadow_enabled = true
	luz.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	luz.directional_shadow_max_distance = 90.0
	luz.shadow_bias = 0.04
	luz.shadow_normal_bias = 1.0
	return luz


# ------------------------------------------------------------------------------------------------ carga
static func _leer_json_estatico(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return v if v is Dictionary else {}


func _leer_json(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		push_warning("CargadorMapa: no existe " + ruta)
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if v is Dictionary:
		return v
	push_warning("CargadorMapa: JSON no válido " + ruta)
	return {}


func _crear_nodos() -> void:
	for h in get_children():
		h.queue_free()
	_marcadores.clear()
	_cache_mat.clear()
	_cache_forma.clear()
	_cache_forma_malla.clear()
	_cache_protos.clear()
	_mats_estacionales.clear()
	_mats_nieve.clear()
	_mats_ventana.clear()
	_luces_mapa.clear()
	_sombras_ext_activas = 0
	_sombras_int_activas = 0
	geometria = _nodo("Geometria")
	colisiones = StaticBody3D.new()
	colisiones.name = "Colisiones"
	colisiones.collision_layer = 1
	colisiones.collision_mask = 0
	add_child(colisiones)
	nodo_instancias = _nodo("Instancias")
	nodo_luces = _nodo("Luces")
	nodo_marcadores = _nodo("Marcadores")


func _nodo(nombre: String) -> Node3D:
	var n := Node3D.new()
	n.name = nombre
	add_child(n)
	return n


func _cargar_geometria(base: String) -> void:
	var ruta := base + id_mapa + ".glb"
	var ps := obtener_recurso(ruta) as PackedScene
	if ps == null:
		push_error("CargadorMapa: no se puede cargar " + ruta)
		return
	var raiz := ps.instantiate()
	geometria.add_child(raiz)
	var luces: Array[Node] = []
	_recorrer(raiz, luces)
	for l in luces:
		_ajustar_luz(l as Light3D)
		l.reparent(nodo_luces, true)
	if _es_exterior():
		_construir_oclusores(raiz)


func _construir_oclusores(raiz: Node) -> void:
	const INCLUIR := ["Pared", "Piedra", "Tejuelas", "Tejado", "Muro", "Silo_muro", "Cabana_hastiales", "Cabana_tejado", "Fachada", "Casa", "Torre", "Molino"]
	const EXCLUIR := ["Ventana", "Agua", "Llama", "Terreno", "Hollin", "Props_", "Postigos", "Tablas", "Vigas"]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var inv_cargador := global_transform.affine_inverse()
	var pilas: Array[Node] = [raiz]
	while not pilas.is_empty():
		var nodo: Node = pilas.pop_back()
		for h in nodo.get_children():
			pilas.append(h)
		if not (nodo is MeshInstance3D):
			continue
		var mi := nodo as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var nom := String(mi.name)
		var ok_nom := false
		for inc: String in INCLUIR:
			if nom.contains(inc):
				ok_nom = true
				break
		if not ok_nom:
			continue
		var excluido := false
		for exc: String in EXCLUIR:
			if nom.contains(exc):
				excluido = true
				break
		if excluido:
			continue
		var caja := mi.global_transform * mi.get_aabb()
		var max_horiz := maxf(caja.size.x, caja.size.z)
		if max_horiz < 3.0 or max_horiz > 30.0 or caja.size.y < 2.0:
			continue
		var sup_cnt := mi.mesh.get_surface_count()
		var tris_total := 0
		var opaco := true
		var sups_arrays: Array[Array] = []
		for s in sup_cnt:
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				opaco = false
				break
			var mat := mi.get_active_material(s)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					opaco = false
					break
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			sups_arrays.append(arr)
			var idx_arr: Variant = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
			if idx_arr is PackedInt32Array and (idx_arr as PackedInt32Array).size() >= 3:
				tris_total += (idx_arr as PackedInt32Array).size() / 3
			else:
				tris_total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		if not opaco or tris_total <= 0 or tris_total > 600:
			continue
		var rel := inv_cargador * mi.global_transform
		for arr: Array in sups_arrays:
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var base_v := vertices.size()
			for v: Vector3 in verts:
				vertices.append(rel * v)
			var idx_arr: Variant = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
			if idx_arr is PackedInt32Array and (idx_arr as PackedInt32Array).size() >= 3:
				for k: int in idx_arr as PackedInt32Array:
					indices.append(base_v + k)
			else:
				for k in verts.size():
					indices.append(base_v + k)
	if indices.size() < 9:
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(vertices, indices)
	var inst := OccluderInstance3D.new()
	inst.name = "OclusoresMapa"
	inst.occluder = occ
	inst.set_meta("tris_oclusor", indices.size() / 3)
	add_child(inst)


func _recorrer(n: Node, luces: Array[Node]) -> void:
	if n is MeshInstance3D:
		_preparar_malla(n as MeshInstance3D)
	elif n is Light3D:
		luces.append(n)
	for h in n.get_children():
		_recorrer(h, luces)


func _preparar_malla(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var info: Dictionary = _info_objeto(String(mi.name))
	for i in mi.mesh.get_surface_count():
		var mat_orig := mi.mesh.surface_get_material(i)
		var m := _material_para(mat_orig)
		if m != null:
			mi.set_surface_override_material(i, m)
		elif mat_orig is BaseMaterial3D:
			var bm := mat_orig as BaseMaterial3D
			if bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and bm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				bm.cull_mode = BaseMaterial3D.CULL_BACK
	if String(mi.name) == "Ventanas_luz" and not _es_exterior():
		_crear_luces_ventana_h03(mi)
	var nom_mi := String(mi.name)
	var tam_local := mi.get_aabb().size
	var es_agua := nom_mi == "Rio_agua" or nom_mi == "Lago_agua" or nom_mi == "Estanque_agua"
	var solo_sombra := bool(info.get("solo_sombra", false))
	var es_prop_peq := nom_mi.contains("wooden_barrels_") or nom_mi.contains("wooden_crate_") or nom_mi.contains("wooden_bucket_") or nom_mi.begins_with("txt_") or nom_mi.contains("Props_Llama") or nom_mi.contains("Props_Brasas") or maxf(tam_local.x, maxf(tam_local.y, tam_local.z)) < 4.0
	if es_agua:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	elif solo_sombra:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if (not _es_exterior() and nom_mi.begins_with("Techo")) else GeometryInstance3D.GI_MODE_DISABLED
	elif es_prop_peq:
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	else:
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	var cristal_farol := id_mapa == "mina_interior" and String(mi.name).begins_with("Prop_int_Cristal_farol")
	if bool(info.get("colision", true)) or cristal_farol:
		var forma := _cache_forma_malla.get(mi.mesh) as Shape3D
		if forma == null:
			forma = mi.mesh.create_trimesh_shape()
			_cache_forma_malla[mi.mesh] = forma
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.name = "col_" + String(mi.name)
		cs.set_meta("malla_apuntada", mi)
		colisiones.add_child(cs)
		cs.global_transform = mi.global_transform


## Datos de objetos.json de un nodo. Godot añade sufijos numéricos (`Techo_roca_001`, `Techo_roca2`) a los nombres repetidos al
## importar el glb: si el nombre exacto no está, se prueba sin ese sufijo.
func _info_objeto(nombre: String) -> Dictionary:
	if _objetos.has(nombre):
		return _objetos[nombre]
	# se quita UN sufijo numérico completo (con su separador): `Techo_roca_001` -> `Techo_roca`
	var fin := nombre.length()
	while fin > 1 and nombre[fin - 1] >= "0" and nombre[fin - 1] <= "9":
		fin -= 1
	if fin == nombre.length():
		return {}
	var base := nombre.left(fin)
	if base.ends_with("_") or base.ends_with("."):
		base = base.left(base.length() - 1)
	if base != "" and _objetos.has(base):
		return _objetos[base]
	return {}


func _ajustar_luz(l: Light3D) -> void:
	l.set_meta("sombra_h03", true)
	var tope := ENERGIA_LUZ_EXT_MAX if _es_exterior() else ENERGIA_LUZ_MAX
	if l is OmniLight3D:
		var o := l as OmniLight3D
		o.omni_range = ALCANCE_LUZ
		o.omni_attenuation = 1.25
		o.light_energy = clampf(o.light_energy, 0.2, tope)
	elif l is SpotLight3D:
		var s := l as SpotLight3D
		s.spot_range = ALCANCE_LUZ
		s.light_energy = clampf(s.light_energy, 0.2, tope)
	if _es_exterior():
		l.light_bake_mode = Light3D.BAKE_DYNAMIC
		if _sombras_ext_activas >= MAX_SOMBRAS_EXT or l.light_energy < 0.45:
			l.set_meta("sin_sombra", true)
		else:
			_sombras_ext_activas += 1
	else:
		if _sombras_int_activas >= MAX_SOMBRAS_INT or l.light_energy < 0.45:
			l.set_meta("sin_sombra", true)
			l.light_bake_mode = Light3D.BAKE_STATIC
		else:
			_sombras_int_activas += 1
			l.light_bake_mode = Light3D.BAKE_DYNAMIC
	_luces_mapa.append({"luz": l, "base": l.light_energy})
	GraficaH03.ajustar_luz(l, int(Ajustes.valores.calidad))


func _crear_luces_ventana_h03(ventanas: MeshInstance3D) -> void:
	var caja := ventanas.global_transform * ventanas.get_aabb()
	for lado in [-1.0, 1.0]:
		var foco := SpotLight3D.new()
		foco.name = "LuzVentana"
		foco.spot_range = 9.0
		foco.spot_angle = 20.0
		foco.spot_angle_attenuation = 1.25
		foco.spot_attenuation = 0.85
		foco.light_energy = 0.0
		foco.light_volumetric_fog_energy = 2.2
		foco.set_meta("sombra_h03", true)
		nodo_luces.add_child(foco, true)
		foco.global_position = caja.get_center() + Vector3.RIGHT * lado * maxf(0.0, caja.size.x * 0.5 - 0.15)
		_luces_ventana_h03.append(foco)


func iluminar_ventanas_h03(dia: float, avance_sol: float, lluvia: bool) -> void:
	var avance := clampf(avance_sol, 0.0, 1.0)
	var lateral := cos(avance * PI)
	for i in _luces_ventana_h03.size():
		var foco := _luces_ventana_h03[i]
		var lado := 1.0 if i == 0 else -1.0
		var entrada := maxf(0.0, lateral * lado)
		foco.light_energy = dia * (0.23 + entrada * 1.8)
		foco.light_volumetric_fog_energy = 0.75 if lluvia else 2.2
		foco.light_color = Color(0.81, 0.89, 1.0).lerp(Color(1.0, 0.80, 0.59), entrada * 0.6)
		foco.look_at(foco.global_position + Vector3(lado, -0.40 - sin(avance * PI) * 0.46, lateral * 0.27))
		GraficaH03.ajustar_luz(foco, int(Ajustes.valores.calidad))


# ------------------------------------------------------------------------------------------------ materiales
func _material_para(m: Material) -> Material:
	if m == null:
		return null
	var nombre := String(m.resource_name)
	if _cache_mat.has(nombre):
		return _cache_mat[nombre]
	if not _materiales.has(nombre):
		return null
	var nuevo := _construir_material(nombre, _materiales[nombre])
	_cache_mat[nombre] = nuevo
	return nuevo


## Material PBR existente, proyectado sobre la roca del techo desde los tres ejes.
static func aplicar_pbr_techo_roca(roca: BaseMaterial3D) -> void:
	roca.albedo_texture = preload("res://assets/texturas/rocky_terrain_02/rocky_terrain_02_albedo.jpg")
	roca.normal_texture = preload("res://assets/texturas/rocky_terrain_02/rocky_terrain_02_normal.png")
	roca.normal_enabled = true
	roca.roughness_texture = preload("res://assets/texturas/rocky_terrain_02/rocky_terrain_02_rug.jpg")
	roca.roughness = 0.94
	roca.uv1_triplanar = true
	roca.uv1_scale = Vector3.ONE * 0.8


func _tex(ruta: Variant) -> Texture2D:
	if ruta == null or String(ruta) == "":
		return null
	if ResourceLoader.exists(String(ruta)):
		return obtener_recurso(String(ruta)) as Texture2D
	push_warning("CargadorMapa: textura sin importar " + String(ruta))
	return null


func _color_lineal(a: Array) -> Color:
	return Color(a[0], a[1], a[2]).linear_to_srgb()


func _es_exterior() -> bool:
	return MAPAS_EXTERIORES.has(id_mapa)


func _construir_material(nombre: String, e: Dictionary) -> Material:
	if nombre == "Agua" and id_mapa in ["costa_lago", "bosque_norte", "robledal_niebla", "ruinas_valle"]:
		var agua := ShaderMaterial.new()
		agua.shader = SHADER_AGUA
		agua.set_shader_parameter("ondas", _tex(NORMAL_AGUA))
		agua.set_shader_parameter("es_rio", id_mapa == "bosque_norte" or id_mapa == "ruinas_valle")
		return agua
	var tipo := String(e.get("tipo", "triplanar"))
	if tipo == "triplanar":
		return _material_triplanar(e)
	return _material_estandar(nombre, e)


func _material_triplanar(e: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_TRIPLANAR
	var alb := _tex(e.get("albedo"))
	var nor := _tex(e.get("normal"))
	var rug := _tex(e.get("rugosidad"))
	if alb != null:
		m.set_shader_parameter("albedo_tex", alb)
	m.set_shader_parameter("normal_tex", nor)
	m.set_shader_parameter("usa_normal", nor != null)
	m.set_shader_parameter("rug_tex", rug)
	m.set_shader_parameter("usa_rug", rug != null)
	m.set_shader_parameter("escala", float(e.get("escala", 2.0)))
	var tn: Variant = e.get("tinte")
	if tn != null:
		m.set_shader_parameter("tinte", Vector3(tn[0], tn[1], tn[2]))
		m.set_shader_parameter("fuerza_tinte", float(e.get("fuerza_tinte", 0.0)))
	var tm: Variant = e.get("tinte_mult")
	if tm != null:
		m.set_shader_parameter("tinte_mult", Vector3(tm[0], tm[1], tm[2]))
	m.set_shader_parameter("rug_mult", float(e.get("rug_mult", 1.0)))
	m.set_shader_parameter("recibe_lluvia", _es_exterior())
	return m


static func _ruta_suelo_h03(mapa: String, canal: String) -> String:
	var prefijo: String = SUELOS_H03[mapa]
	if SUELOS_H05_SET.has(mapa):
		return "res://assets/texturas/h05/%s/%s_%s_1k.jpg" % [prefijo, prefijo, canal]
	return "res://assets/texturas/h03/%s/%s_%s_2k.jpg" % [prefijo, prefijo, canal]


func _material_estandar(nombre: String, e: Dictionary) -> Material:
	var es_tejado := _es_exterior() and (nombre.contains("Tejuelas") or nombre.contains("Tejado_madera"))
	var es_suelo := _es_exterior() and (nombre == "Terreno__Suelo" or nombre.begins_with("Fachada_roca") or nombre.begins_with("Tunel_entrada"))
	var alb := _tex(e.get("albedo"))
	var nor := _tex(e.get("normal"))
	var rug := _tex(e.get("rugosidad"))
	var c: Array = e.get("color", [1, 1, 1, 1])
	var col_base := _color_lineal(c)
	if c.size() > 3:
		col_base.a = float(c[3])
	var es_piedra_horneada := alb != null and nor == null and (
		nombre.contains("Piedra_alcalde")
		or nombre.contains("Silo_muro")
		or nombre.contains("Roca_cueva")
		or nombre.contains("Roca_inferior")
		or nombre.contains("Pozo_escalera")
	)
	if es_tejado or es_suelo or es_piedra_horneada:
		var sm := ShaderMaterial.new()
		sm.shader = SHADER_ESTACIONAL
		if alb != null:
			sm.set_shader_parameter("albedo_tex", alb)
		sm.set_shader_parameter("usa_albedo", alb != null)
		sm.set_shader_parameter("normal_tex", nor)
		sm.set_shader_parameter("usa_normal", nor != null)
		sm.set_shader_parameter("rug_tex", rug)
		sm.set_shader_parameter("usa_rug", rug != null)
		sm.set_shader_parameter("color_base", col_base)
		var rug_suelo := float(e.get("rug", 0.65))
		if es_suelo or es_tejado or es_piedra_horneada:
			rug_suelo = maxf(rug_suelo, 0.90 if es_piedra_horneada else 0.88)
		sm.set_shader_parameter("rug_base", rug_suelo)
		sm.set_shader_parameter("metalico", float(e.get("metalico", 0.0)))
		sm.set_shader_parameter("es_suelo", es_suelo)
		sm.set_shader_parameter("es_tejado", es_tejado)
		sm.set_shader_parameter("recibe_lluvia", _es_exterior())
		if es_tejado and nor == null:
			var t_mad := _tex(NORMAL_MADERA_TEJADO)
			if t_mad != null:
				sm.set_shader_parameter("usa_normal_mundo", true)
				sm.set_shader_parameter("normal_mundo_tex", t_mad)
				sm.set_shader_parameter("escala_normal_mundo", 2.4)
				sm.set_shader_parameter("fuerza_normal_mundo", 0.65)
		elif nor == null and (es_piedra_horneada or (es_suelo and nombre != "Terreno__Suelo")):
			var ruta_nm := NORMAL_PIEDRA_MURO if (nombre.contains("Piedra") or nombre.contains("Silo")) else NORMAL_ROCA_CUEVA
			var t_pie := _tex(ruta_nm)
			if t_pie != null:
				sm.set_shader_parameter("usa_normal_mundo", true)
				sm.set_shader_parameter("normal_mundo_tex", t_pie)
				sm.set_shader_parameter("escala_normal_mundo", 2.2)
				sm.set_shader_parameter("fuerza_normal_mundo", 0.72)
		if nombre == "Terreno__Suelo" and SUELOS_H03.has(id_mapa):
			sm.set_shader_parameter("usa_detalle", true)
			sm.set_shader_parameter("detalle_color", _tex(_ruta_suelo_h03(id_mapa, "diff")))
			sm.set_shader_parameter("detalle_normal", _tex(_ruta_suelo_h03(id_mapa, "nor_gl")))
			sm.set_shader_parameter("detalle_rugosidad", _tex(_ruta_suelo_h03(id_mapa, "rough")))
			sm.set_shader_parameter("detalle_altura", _tex(_ruta_suelo_h03(id_mapa, "disp")))
		return sm

	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color = col_base
	if alb != null:
		m.albedo_texture = alb
		m.albedo_color = _ajuste_albedo_textura(nombre, m.albedo_color.a)
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
	if rug != null:
		m.roughness_texture = rug
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
	else:
		m.roughness = float(e.get("rug", 0.8))
	m.metallic = float(e.get("metalico", 0.0))
	_calibrar_superficie(nombre, m, e)
	if e.has("emision"):
		var em: Array = e["emision"]
		if maxf(float(em[0]), maxf(float(em[1]), float(em[2]))) > 0.001:
			m.emission_enabled = true
			m.emission = _color_lineal(em)
			var fe := float(e.get("fuerza_emision", 1.0))
			m.emission_energy_multiplier = _ajustar_emision_base(nombre, fe)
	var a := String(e.get("alpha", ""))
	if a == "recorte":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	elif a == "mezcla":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(e.get("doble_cara", false)):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

	var cat_est := _categoria_tinte_estacional(nombre)
	if _es_exterior() and a == "recorte" and not cat_est.is_empty() and alb != null:
		return _material_follaje(nombre, m, cat_est)

	if nombre == "Ventana" or nombre == "Ventana_luz" or nombre == "Ventana_tenue" or nombre == "Ventana_calida":
		_mats_ventana.append({
			"mat": m,
			"emision": m.emission,
			"fuerza": m.emission_energy_multiplier,
			"albedo": m.albedo_color,
			"interior": not _es_exterior(),
		})

	if _es_exterior() and _lleva_nieve_estandar(nombre, e):
		var np := _next_pass_nieve(a == "recorte", alb)
		_mats_nieve.append({"mat": m, "pass": np})
		if Juego.estacion == 3:
			m.next_pass = np
	if _es_exterior() and not cat_est.is_empty():
		_mats_estacionales.append({"mat": m, "base": m.albedo_color, "cat": cat_est})
		m.albedo_color = _tinte_estacional(m.albedo_color, cat_est)
	return m


func _material_follaje(nombre: String, base: StandardMaterial3D, categoria: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER_FOLLAJE
	var hierba := nombre.begins_with("grass_")
	material.set_shader_parameter("albedo_tex", base.albedo_texture)
	material.set_shader_parameter("normal_tex", base.normal_texture)
	material.set_shader_parameter("usa_normal", base.normal_enabled)
	material.set_shader_parameter("rug_tex", base.roughness_texture)
	material.set_shader_parameter("usa_rug", base.roughness_texture != null)
	material.set_shader_parameter("rug_base", base.roughness)
	material.set_shader_parameter("es_hierba", hierba)
	material.set_shader_parameter("flexion", 0.28 if hierba else (0.21 if categoria == "arbol" else 0.16))
	material.set_shader_parameter("transmision", 0.20 if categoria == "arbol" else 0.36)
	material.set_shader_parameter("tinte", _tinte_estacional(base.albedo_color, categoria))
	_mats_estacionales.append({"mat": material, "base": base.albedo_color, "cat": categoria})
	return material


func _ajuste_albedo_textura(nombre: String, alfa: float) -> Color:
	if nombre.begins_with("shrub_04"):
		return Color(0.72, 0.84, 0.62, alfa)
	if nombre.begins_with("grass_") or nombre.begins_with("fern_") or nombre.begins_with("weed_") or nombre.begins_with("shrub_sorrel_") or nombre.begins_with("dandelion_"):
		return Color(0.82, 0.92, 0.75, alfa)
	if nombre.begins_with("fir_tree_01_twig") or nombre.begins_with("fir_sapling_twigs") or nombre.begins_with("pine_sapling_small_twig"):
		return Color(0.90, 0.98, 0.84, alfa)
	if nombre.begins_with("fir_") or nombre.begins_with("pine_") or nombre.begins_with("dead_tree_") or nombre.begins_with("tree_stump_") or nombre.begins_with("dry_branches_") or nombre == "Troncos":
		return Color(0.88, 0.84, 0.79, alfa)
	if nombre.begins_with("Roca_inferior") or nombre.begins_with("Pozo_escalera") or nombre.begins_with("Prop_int_Roca") or nombre.begins_with("rock_moss_"):
		return Color(0.78, 0.75, 0.71, alfa)
	if nombre == "Madera_mina" or nombre == "Vigas":
		return Color(0.88, 0.84, 0.79, alfa)
	return Color(1.0, 1.0, 1.0, alfa)


func _calibrar_superficie(nombre: String, m: StandardMaterial3D, e: Dictionary) -> void:
	var es_recorte := String(e.get("alpha", "")) == "recorte"
	var es_cueva := nombre.contains("Roca_cueva") or nombre.begins_with("rock_moss_") or nombre == "Madera_mina"
	var es_naturaleza := es_recorte or nombre.begins_with("fir_") or nombre.begins_with("pine_") or nombre.begins_with("dead_tree_") or nombre.begins_with("tree_stump_") or nombre.begins_with("dry_branches_") or nombre == "Troncos" or nombre.begins_with("wooden_")
	if es_recorte:
		m.metallic_specular = 0.10
		m.roughness = maxf(m.roughness, 0.88)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	elif es_cueva:
		m.metallic_specular = 0.14
		m.roughness = maxf(m.roughness, 0.92)
	elif es_naturaleza:
		m.metallic_specular = 0.16
		m.roughness = maxf(m.roughness, 0.86)
	elif nombre == "Agua":
		m.roughness = 0.08
	elif float(e.get("metalico", 0.0)) < 0.25:
		m.metallic_specular = 0.24
		m.roughness = maxf(m.roughness, 0.72)


func _ajustar_emision_base(nombre: String, fe: float) -> float:
	if nombre == "Llama":
		return minf(fe, 4.2)
	if nombre == "Brasas":
		return minf(fe, 2.6)
	if nombre == "Cristal_farol":
		return minf(fe, 0.85)
	if nombre == "Cristal_azul":
		return minf(fe, 2.2)
	if nombre == "Ventana" or nombre == "Ventana_luz" or nombre == "Ventana_tenue":
		return clampf(fe, 0.4, 1.45)
	if nombre == "Ventana_calida":
		return minf(fe, 0.85)
	return fe


func _lleva_nieve_estandar(nombre: String, e: Dictionary) -> bool:
	if String(e.get("alpha", "")) == "mezcla" or nombre.contains("glass") or nombre.contains("Ventana") or nombre == "Agua" or nombre == "Llama" or nombre == "proto_Trigo":
		return false
	for pref: String in ["fir_", "pine_", "grass_", "fern_", "dandelion_", "shrub_", "weed_", "tree_stump_", "dead_tree_", "dry_branches_", "rock_moss_", "Troncos", "wooden_"]:
		if nombre.begins_with(pref):
			return true
	return false


func _categoria_tinte_estacional(nombre: String) -> String:
	for pref: String in ["grass_", "fern_", "dandelion_", "shrub_", "weed_"]:
		if nombre.begins_with(pref):
			return "hierba"
	if nombre.begins_with("fir_") or nombre.begins_with("pine_"):
		return "arbol"
	return ""


func _next_pass_nieve(es_foliage: bool, alb: Texture2D) -> ShaderMaterial:
	if es_foliage:
		var sm := ShaderMaterial.new()
		sm.shader = SHADER_NIEVE_HOJAS
		if alb != null:
			sm.set_shader_parameter("albedo_tex", alb)
		sm.set_shader_parameter("usa_alpha", alb != null)
		return sm
	if _mat_nieve_corteza == null:
		_mat_nieve_corteza = ShaderMaterial.new()
		_mat_nieve_corteza.shader = SHADER_NIEVE_CORTEZA
	return _mat_nieve_corteza


func _tinte_estacional(base: Color, cat: String) -> Color:
	var est := Juego.estacion
	if cat == "hierba":
		match est:
			1:
				return base * Color(0.95, 1.05, 0.92, 1.0)
			2:
				return base * Color(1.08, 0.84, 0.50, 1.0)
			3:
				return base * Color(0.84, 0.90, 0.86, 1.0)
	elif cat == "arbol":
		match est:
			2:
				return base * Color(1.04, 0.92, 0.72, 1.0)
			3:
				return base * Color(0.88, 0.94, 0.98, 1.0)
	return base


func actualizar_estacion() -> void:
	for reg: Dictionary in _mats_estacionales:
		var m := reg.get("mat") as Material
		var tinte := _tinte_estacional(reg["base"] as Color, str(reg["cat"]))
		if m is ShaderMaterial:
			m.set_shader_parameter("tinte", tinte)
		elif m is StandardMaterial3D:
			m.albedo_color = tinte
	var inv := Juego.estacion == 3 and _es_exterior()
	for reg_n: Dictionary in _mats_nieve:
		var mn := reg_n.get("mat") as StandardMaterial3D
		if is_instance_valid(mn):
			mn.next_pass = (reg_n.get("pass") as ShaderMaterial) if inv else null


## Modula faroles y ventanas del mapa según la hora y el clima para evitar ventanas quemadas y reflejos de día.
func actualizar_iluminacion_hora(factor_ventanas: float, factor_luces: float, fuerza_int: float = 0.75) -> void:
	for reg_v: Dictionary in _mats_ventana:
		var mat := reg_v.get("mat") as StandardMaterial3D
		if not is_instance_valid(mat):
			continue
		var es_int := bool(reg_v.get("interior", false))
		var base_fe := float(reg_v.get("fuerza", 1.0))
		if es_int:
			var dia_ext := clampf(fuerza_int, 0.0, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.18, 0.22, 0.30).lerp(Color(0.56, 0.62, 0.70), dia_ext)
			mat.emission_energy_multiplier = lerpf(0.08, 0.85, dia_ext)
			mat.albedo_color = Color(0.08, 0.11, 0.17).lerp(Color(0.52, 0.56, 0.62), dia_ext)
		else:
			var encendido := clampf(factor_ventanas, 0.0, 1.0)
			mat.emission_energy_multiplier = maxf(0.03, base_fe * encendido)
			mat.roughness = lerpf(0.16, 0.45, encendido)
			var vidrio_dia := Color(0.12, 0.14, 0.18)
			mat.albedo_color = vidrio_dia.lerp(reg_v["albedo"] as Color, encendido)
	var calidad_actual := int(Ajustes.valores.calidad)
	for reg_l: Dictionary in _luces_mapa:
		var l := reg_l.get("luz") as Light3D
		if not is_instance_valid(l):
			continue
		var base := float(reg_l.get("base", 1.0))
		if _es_exterior():
			l.light_energy = base * clampf(factor_luces, 0.04, 1.0)
		else:
			l.light_energy = base
		var debe_sombra := (not l.has_meta("sin_sombra")) and calidad_actual >= 2 and l.light_energy > 0.065
		if l.shadow_enabled != debe_sombra or int(l.get_meta("calidad_luz_h03", -1)) != calidad_actual:
			l.set_meta("calidad_luz_h03", calidad_actual)
			GraficaH03.ajustar_luz(l, calidad_actual)


func _crear_nodo_arbol(nombre: String, mesh: Mesh, xf: Transform3D, r_ini: float, r_fin: float, m_ini: float, m_fin: float, lod_bias_val: float, sombra: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	mi.mesh = mesh
	mi.transform = xf
	mi.extra_cull_margin = 0.3
	mi.lod_bias = lod_bias_val
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_begin = r_ini
	mi.visibility_range_begin_margin = m_ini
	mi.visibility_range_end = r_fin
	mi.visibility_range_end_margin = m_fin
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not sombra:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _instanciar_celda_arbol(p: String, ts: Array, mesh_lod0: Mesh, mesh_lod1: Mesh, _mesh_lod2: Mesh, celda: Vector2i) -> void:
	var tiene_lods := mesh_lod1 != null
	var idx := 0
	for t: Array in ts:
		var xf := Transform3D(
			Vector3(float(t[0]), float(t[1]), float(t[2])),
			Vector3(float(t[3]), float(t[4]), float(t[5])),
			Vector3(float(t[6]), float(t[7]), float(t[8])),
			Vector3(float(t[9]), float(t[10]), float(t[11]))
		)
		var base_nom := "arb_%s_%d_%d_%d" % [p, celda.x, celda.y, idx]
		idx += 1
		if tiene_lods:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom + "_L1", mesh_lod1, xf, 0.0, 10.5, 0.0, 1.5, 0.12, true))
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom + "_L2", mesh_lod1, xf, 9.5, 100.0, 1.5, 10.0, 0.035, false))
		elif "dead_tree" in p:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom, mesh_lod0, xf, 0.0, 75.0, 0.0, 10.0, 0.06, true))
		elif "stump" in p:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom, mesh_lod0, xf, 0.0, 40.0, 0.0, 8.0, 0.04, false))
		else:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom, mesh_lod0, xf, 0.0, 25.0, 0.0, 5.0, 0.035, false))


static func _ruta_proto(base: String, rel: String) -> String:
	return rel if rel.begins_with("res://") else base + rel


# ------------------------------------------------------------------------------------------------ instancias
func _cargar_instancias(base: String) -> void:
	var protos: Dictionary = _inst.get("protos", {})
	var lista: Array = _inst.get("instancias", [])
	var sin_col: Array = _inst.get("sin_colision", [])
	var troncos: Dictionary = _inst.get("troncos", {})
	var rocas: Dictionary = _inst.get("rocas", {})
	var info: Dictionary = _inst.get("info", {})
	# agrupa por prototipo y por celda de 42 m
	var grupos: Dictionary = {}
	for d: Dictionary in lista:
		var p: String = d["proto"]
		var t: Array = d["t"]
		var celda := Vector2i(floori(float(t[9]) / TAM_CELDA), floori(float(t[11]) / TAM_CELDA))
		if not grupos.has(p):
			grupos[p] = {}
		var g: Dictionary = grupos[p]
		if not g.has(celda):
			g[celda] = []
		(g[celda] as Array).append(t)
	var cuerpo_troncos := StaticBody3D.new()
	cuerpo_troncos.name = "ColisionInstancias"
	cuerpo_troncos.collision_layer = 1
	cuerpo_troncos.collision_mask = 0
	colisiones.add_child(cuerpo_troncos)
	for p: String in grupos.keys():
		var info_p: Dictionary = info.get(p, {}) as Dictionary
		var cat := String(info_p.get("cat", "prop"))
		var lods: Dictionary = info_p.get("lods", {}) as Dictionary
		var usar_solo_lod1 := (cat == "arbol" and lods.has("LOD1"))
		var mesh: Mesh = null if usar_solo_lod1 else _mesh_proto(_ruta_proto(base, String(protos.get(p, ""))))
		var mesh_lod1: Mesh = _mesh_proto(_ruta_proto(base, String(lods.get("LOD1", "")))) if lods.has("LOD1") else (mesh if "_LOD1" in p else null)
		var mesh_lod2: Mesh = _mesh_proto(_ruta_proto(base, String(lods.get("LOD2", "")))) if (mesh_lod1 == null and lods.has("LOD2")) else null
		if mesh == null and mesh_lod1 == null:
			continue
		var celdas: Dictionary = grupos[p]
		for celda: Vector2i in celdas.keys():
			var ts: Array = celdas[celda]
			if cat == "arbol":
				_instanciar_celda_arbol(p, ts, mesh, mesh_lod1, mesh_lod2, celda)
			else:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				_cargar_buffer_instancias(mm, ts, p.begins_with("grass_") and _es_exterior())
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "mm_%s_%d_%d" % [p, celda.x, celda.y]
				mmi.multimesh = mm
				if cat == "planta" or sin_col.has(p):
					mmi.extra_cull_margin = 0.3
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
					mmi.visibility_range_end = ALCANCE_PLANTAS
				elif cat == "roca":
					mmi.lod_bias = 0.45
					mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
					if p.begins_with("rock_moss_set_02_") or p == "stone_01":
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						mmi.visibility_range_end = 110.0
				nodo_instancias.add_child(mmi)
			num_trozos_multimesh += 1
			num_instancias += ts.size()
			# colisión de troncos y rocas: cilindros
			var radio := 0.0
			var alto := ALTO_CILINDRO_TRONCO
			if troncos.has(p):
				radio = float(troncos[p])
			elif rocas.has(p):
				radio = float(rocas[p][0])
				alto = float(rocas[p][1])
			if radio > 0.0:
				for t: Array in ts:
					var esc := Vector3(t[0], t[1], t[2]).length()
					var forma := _forma_cilindro(radio * esc, alto * esc)
					var cs := CollisionShape3D.new()
					cs.shape = forma
					cs.position = Vector3(t[9], t[10] + alto * esc * 0.5, t[11])
					cuerpo_troncos.add_child(cs)


func _cargar_buffer_instancias(mm: MultiMesh, originales: Array, hierba: bool) -> void:
	# Refuerza los macizos existentes con un tallo bajo de cerca.
	var extras := (maxi(1, originales.size() / 6) if originales.size() >= 3 else 0) if hierba else 0
	var paso := 16 if hierba else 12
	mm.use_custom_data = hierba
	mm.instance_count = originales.size() + extras
	var buffer := PackedFloat32Array()
	buffer.resize(mm.instance_count * paso)
	for i in mm.instance_count:
		var extra := i >= originales.size()
		var indice := mini((i - originales.size()) * 6, originales.size() - 1) if extra else i
		var xf := _t_a_transform(originales[indice])
		if extra:
			var lateral := xf.basis.x.normalized() * 0.20
			xf.origin += Vector3(lateral.x, -0.045, lateral.z)
			xf.basis = xf.basis.rotated(Vector3.UP, 1.72).scaled(Vector3.ONE * 0.69)
			buffer[i * paso + 12] = 1.0
		# MultiMesh guarda las tres filas de la matriz seguidas de la traslación de cada eje.
		for eje in 3:
			var fila := i * paso + eje * 4
			buffer[fila] = xf.basis.x[eje]
			buffer[fila + 1] = xf.basis.y[eje]
			buffer[fila + 2] = xf.basis.z[eje]
			buffer[fila + 3] = xf.origin[eje]
	mm.buffer = buffer


func _forma_cilindro(radio: float, alto: float) -> CylinderShape3D:
	var clave := "%.2f_%.2f" % [radio, alto]
	if _cache_forma.has(clave):
		return _cache_forma[clave]
	var f := CylinderShape3D.new()
	f.radius = radio
	f.height = alto
	_cache_forma[clave] = f
	return f


func _mesh_proto(ruta: String) -> Mesh:
	if _cache_protos.has(ruta):
		return _cache_protos[ruta] as Mesh
	var ps := obtener_recurso(ruta) as PackedScene
	if ps == null:
		push_warning("CargadorMapa: prototipo sin cargar " + ruta)
		return null
	var n := ps.instantiate()
	var mi := _primera_malla(n)
	var mesh: Mesh = null
	if mi != null:
		mesh = mi.mesh
		for i in mesh.get_surface_count():
			var mat_orig := mesh.surface_get_material(i)
			var nm := _material_para(mat_orig)
			if nm != null:
				mesh.surface_set_material(i, nm)
			elif mat_orig is StandardMaterial3D:
				var sm := mat_orig as StandardMaterial3D
				if ruta.ends_with("grass_medium_02.glb"):
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					sm.alpha_scissor_threshold = 0.5
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				elif ruta.ends_with("roble_viejo.glb") and i == 0:
					sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					sm.cull_mode = BaseMaterial3D.CULL_BACK
				elif sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
					sm.cull_mode = BaseMaterial3D.CULL_BACK
	n.free()
	_cache_protos[ruta] = mesh
	return mesh


func _primera_malla(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for h in n.get_children():
		var r := _primera_malla(h)
		if r != null:
			return r
	return null


# ------------------------------------------------------------------------------------------------ marcadores
func _t_a_transform(t: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8])), Vector3(t[9], t[10], t[11]))


func _crear_marcadores() -> void:
	for d: Dictionary in _datos.get("marcadores", []):
		_nuevo_marcador(d, String(d.get("tipo", "otro")))
	for d: Dictionary in _datos.get("zonas", []):
		_nuevo_marcador(d, "zona")


func _nuevo_marcador(d: Dictionary, tipo: String) -> void:
	var m := Marker3D.new()
	m.name = String(d["nombre"])
	m.transform = _t_a_transform(d["t"])
	m.set_meta("tipo", tipo)
	if d.has("tam"):
		m.set_meta("tam", Vector2(d["tam"][0], d["tam"][1]))
	if d.has("fov"):
		m.set_meta("fov", float(d["fov"]))
	if d.has("texto"):
		m.set_meta("texto", String(d["texto"]))
	if d.has("sintetico"):
		m.set_meta("sintetico", true)
	nodo_marcadores.add_child(m)
	_marcadores[String(d["nombre"])] = m
