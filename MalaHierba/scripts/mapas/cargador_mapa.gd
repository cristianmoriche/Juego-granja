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
const MAPAS_EXTERIORES: Array[String] = ["granja", "pueblo", "mina_exterior", "bosque_norte", "costa_lago"]
const TAM_CELDA := 24.0                 # metros: tamaño de cada trozo de MultiMesh (permite recortar lo que no se ve)
const ALCANCE_PLANTAS := 75.0           # distancia a partir de la cual desaparecen las plantas pequeñas
const ALTO_CILINDRO_TRONCO := 4.0
const ENERGIA_LUZ_MAX := 1.45
const ENERGIA_LUZ_EXT_MAX := 1.35
const ALCANCE_LUZ := 12.0

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
var _mat_nieve_corteza: ShaderMaterial = null
var _cache_forma_malla: Dictionary = {}
var _cache_protos: Dictionary = {}

static var _cache_rutas_mapa: Dictionary = {}


static func solicitar_recurso(ruta: String) -> void:
	if ruta.is_empty() or DisplayServer.get_name() == "headless" or ResourceLoader.has_cached(ruta) or not ResourceLoader.exists(ruta):
		return
	var st := ResourceLoader.load_threaded_get_status(ruta)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
		return
	ResourceLoader.load_threaded_request(ruta, "", false)


static func solicitar_lote(rutas: PackedStringArray) -> void:
	for r in rutas:
		solicitar_recurso(r)


static func obtener_recurso(ruta: String) -> Resource:
	if ruta.is_empty() or not ResourceLoader.exists(ruta):
		return null
	var st := ResourceLoader.load_threaded_get_status(ruta)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
		var r := ResourceLoader.load_threaded_get(ruta)
		if r != null:
			return r
	return load(ruta)


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
	var cielo: Variant = datos.get("cielo", null)
	if cielo is Dictionary:
		var hdri: Variant = (cielo as Dictionary).get("hdri", "")
		if hdri is String:
			anadir.call(hdri as String)
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
	anadir.call(base + id + ".glb")
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
		var m := _material_para(mi.mesh.surface_get_material(i))
		if m != null:
			mi.set_surface_override_material(i, m)
	if bool(info.get("solo_sombra", false)):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if bool(info.get("colision", true)):
		var forma := _cache_forma_malla.get(mi.mesh) as Shape3D
		if forma == null:
			forma = mi.mesh.create_trimesh_shape()
			_cache_forma_malla[mi.mesh] = forma
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.name = "col_" + String(mi.name)
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
	l.shadow_enabled = false
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
	_luces_mapa.append({"luz": l, "base": l.light_energy})


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
	return m


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
	if es_tejado or es_suelo:
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
		if es_suelo or es_tejado:
			rug_suelo = maxf(rug_suelo, 0.88)
		sm.set_shader_parameter("rug_base", rug_suelo)
		sm.set_shader_parameter("metalico", float(e.get("metalico", 0.0)))
		sm.set_shader_parameter("es_suelo", es_suelo)
		sm.set_shader_parameter("es_tejado", es_tejado)
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
	var cat_est := _categoria_tinte_estacional(nombre)
	if _es_exterior() and not cat_est.is_empty():
		_mats_estacionales.append({"mat": m, "base": m.albedo_color, "cat": cat_est})
		_aplicar_tinte_mat(m, m.albedo_color, cat_est)
	return m


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


func _aplicar_tinte_mat(m: StandardMaterial3D, base: Color, cat: String) -> void:
	var est := Juego.estacion
	if cat == "hierba":
		match est:
			1:
				m.albedo_color = base * Color(0.95, 1.05, 0.92, 1.0)
			2:
				m.albedo_color = base * Color(1.08, 0.84, 0.50, 1.0)
			3:
				m.albedo_color = base * Color(0.84, 0.90, 0.86, 1.0)
			_:
				m.albedo_color = base
	elif cat == "arbol":
		match est:
			2:
				m.albedo_color = base * Color(1.04, 0.92, 0.72, 1.0)
			3:
				m.albedo_color = base * Color(0.88, 0.94, 0.98, 1.0)
			_:
				m.albedo_color = base


func actualizar_estacion() -> void:
	for reg: Dictionary in _mats_estacionales:
		var m := reg.get("mat") as StandardMaterial3D
		if is_instance_valid(m):
			_aplicar_tinte_mat(m, reg["base"] as Color, str(reg["cat"]))
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
	for reg_l: Dictionary in _luces_mapa:
		var l := reg_l.get("luz") as Light3D
		if not is_instance_valid(l):
			continue
		var base := float(reg_l.get("base", 1.0))
		if _es_exterior():
			l.light_energy = base * clampf(factor_luces, 0.04, 1.0)
		else:
			l.light_energy = base


func _crear_nodo_arbol(nombre: String, mesh: Mesh, xf: Transform3D, r_ini: float, r_fin: float, m_ini: float, m_fin: float, lod_bias_val: float, sombra: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	mi.mesh = mesh
	mi.transform = xf
	mi.lod_bias = lod_bias_val
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
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom + "_L1", mesh_lod1, xf, 0.0, 14.0, 0.0, 2.5, 0.25, true))
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom + "_L2", mesh_lod1, xf, 11.5, 158.0, 2.5, 16.0, 0.060, false))
		elif "dead_tree" in p or "stump" in p:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom, mesh_lod0, xf, 0.0, 130.0, 0.0, 12.0, 0.12, true))
		else:
			nodo_instancias.add_child(_crear_nodo_arbol(base_nom, mesh_lod0, xf, 0.0, 34.0, 0.0, 6.0, 0.065, false))


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
	# agrupa por prototipo y por celda de 24 m
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
				mm.instance_count = ts.size()
				var buf := PackedFloat32Array()
				buf.resize(ts.size() * 12)
				var k := 0
				for t: Array in ts:
					buf[k] = t[0]; buf[k + 1] = t[3]; buf[k + 2] = t[6]; buf[k + 3] = t[9]
					buf[k + 4] = t[1]; buf[k + 5] = t[4]; buf[k + 6] = t[7]; buf[k + 7] = t[10]
					buf[k + 8] = t[2]; buf[k + 9] = t[5]; buf[k + 10] = t[8]; buf[k + 11] = t[11]
					k += 12
				mm.buffer = buf
				var mmi := MultiMeshInstance3D.new()
				mmi.name = "mm_%s_%d_%d" % [p, celda.x, celda.y]
				mmi.multimesh = mm
				if cat == "planta" or sin_col.has(p):
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mmi.visibility_range_end = ALCANCE_PLANTAS
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
			var nm := _material_para(mesh.surface_get_material(i))
			if nm != null:
				mesh.surface_set_material(i, nm)
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
