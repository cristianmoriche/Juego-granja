class_name RecursosExteriores
extends Node3D
## Elementos interactivos en zonas exteriores ampliadas y nuevas (H05):
## - Parcelas adicionales desbrozables/comprables en El Granado (`Zona_Cultivo_4`, `Zona_Cultivo_5`).
## - Recolección silvestre diaria (`seta_silvestre`, `hierba_monte`, `mora_silvestre`).
## - Vetas de mineral en superficie (`Sierra del Mirador`, `Ruinas del Molino Viejo`, `Las minas` oeste).
## - Cofres escondidos (`cofre_mina.glb`) con tapa abatible y botín.
## - Colisiones en jambas de los arcos de ruinas para poder cruzar por debajo.
## - Encuentros puntuales al anochecer (>= 18:30) solo en zonas salvajes (H05).

const ESCENA_COFRE := "res://assets/mina/cofre_mina.glb"
const ESCENA_HOGUERA := "res://assets/naturaleza/hoguera_h06.glb"
const ESCENA_CAMPAMENTO := "res://assets/naturaleza/campamento_h13.glb"
const HORA_ANOCHECER := 1110  # 18:30
const ZONAS_SEGURAS := ["granja", "pueblo"]

const HOGUERAS_EXT := {
	"bosque_norte": Vector2(-8.0, 24.0),
	"costa_lago": Vector2(14.0, -18.0),
	"mina_exterior": Vector2(6.0, -10.0),
	"sierra_mirador": Vector2(6.0, -6.0),
	"robledal_niebla": Vector2(-6.0, 10.0),
	"ruinas_valle": Vector2(2.0, 0.0),
}

const FORRAJE_DEF := {
	"seta": {"modelo": "res://assets/naturaleza/seta_silvestre.glb", "item": "seta_silvestre", "nombre": "las setas silvestres", "cant": 2, "escala": 1.35},
	"hierba": {"modelo": "res://assets/naturaleza/hierba_monte.glb", "item": "hierba_monte", "nombre": "el romero de monte", "cant": 2, "escala": 1.25},
	"mora": {"modelo": "res://assets/naturaleza/mora_silvestre.glb", "item": "mora_silvestre", "nombre": "las moras silvestres", "cant": 3, "escala": 1.25},
}

const MENAS_EXT := {
	"Mena_Sierra_1": {"id": "cobre", "golpes": 3, "min": 2, "max": 3, "color": Color(0.72, 0.44, 0.25), "nombre": "la veta de cobre"},
	"Mena_Sierra_2": {"id": "hierro", "golpes": 3, "min": 2, "max": 3, "color": Color(0.55, 0.62, 0.72), "nombre": "la veta de hierro"},
	"Mena_Sierra_3": {"id": "cuarzo", "golpes": 4, "min": 1, "max": 2, "color": Color(0.84, 0.90, 0.98), "nombre": "la veta de cuarzo"},
	"Mena_Sierra_4": {"id": "cobre", "golpes": 3, "min": 1, "max": 3, "color": Color(0.72, 0.44, 0.25), "nombre": "la veta de cobre"},
	"Mena_Sierra_5": {"id": "oro", "golpes": 4, "min": 1, "max": 2, "color": Color(0.92, 0.74, 0.22), "nombre": "la veta de oro"},
	"Mena_Ambar_Sierra": {"id": "ambar_valle", "golpes": 4, "min": 1, "max": 1, "color": Color(0.88, 0.56, 0.14), "nombre": "el afloramiento de ámbar del valle"},
	"Mena_Ruinas_1": {"id": "cobre", "golpes": 3, "min": 1, "max": 2, "color": Color(0.72, 0.44, 0.25), "nombre": "la roca de cobre"},
	"Mena_Ruinas_2": {"id": "cuarzo", "golpes": 3, "min": 1, "max": 2, "color": Color(0.84, 0.90, 0.98), "nombre": "la roca de cuarzo"},
}

const COFRES_EXT := {
	"Cofre_Sierra": [
		{"id": "cuarzo", "cantidad": 2},
		{"id": "oro", "cantidad": 1},
		{"id": "elixir_sierra", "cantidad": 1},
	],
	"Cofre_Robledal": [
		{"id": "mora_silvestre", "cantidad": 4},
		{"id": "semilla_azafran", "cantidad": 1},
		{"id": "madera", "cantidad": 8},
	],
	"Cofre_Ruinas": [
		{"id": "ambar_valle", "cantidad": 1},
		{"id": "oro", "cantidad": 1},
		{"id": "hierba_monte", "cantidad": 3},
	],
}

const ENEMIGOS_SALVAJES := {
	"Enemigo_Sierra_1": "escarabajo_roca",
	"Enemigo_Sierra_2": "escarabajo_roca",
	"Enemigo_Robledal_1": "babosa_gruta",
	"Enemigo_Robledal_2": "murcielago",
	"Enemigo_Ruinas_1": "escarabajo_roca",
	"Enemigo_Ruinas_2": "arana_cristal",
}

const ARBOLES_TAMANOS := {
	"pequeno": {
		"modelo": "res://assets/mapas/granja/protos/pine_sapling_small_a.glb",
		"escala": 1.05,
		"golpes": 2,
		"madera": 3,
		"radio": 0.24,
		"alto_col": 1.8,
		"nombre": "el pino pequeño",
		"tinte_copa": Color(0.78, 1.06, 0.56),
	},
	"mediano": {
		"modelo": "res://assets/mapas/granja/protos/fir_sapling_a.glb",
		"escala": 0.90,
		"golpes": 3,
		"madera": 5,
		"radio": 0.30,
		"alto_col": 2.3,
		"nombre": "el abeto mediano",
		"tinte_copa": Color(0.70, 0.98, 0.52),
	},
	"joven": {
		"modelo": "res://assets/mapas/granja/protos/fir_sapling_b.glb",
		"escala": 1.18,
		"golpes": 4,
		"madera": 7,
		"radio": 0.35,
		"alto_col": 2.8,
		"nombre": "el abeto joven",
		"tinte_copa": Color(0.84, 0.98, 0.56),
	},
}
const ESCENA_TOCON := "res://assets/mapas/granja/protos/tree_stump_01.glb"

var _mapa: Mapa = null
var _id: String = ""
var _anochecer_generado: bool = false
var _nodo_enemigos: Node3D = null
var _arboles_talables: Array[Dictionary] = []


static func preparar(mapa: Mapa) -> RecursosExteriores:
	var r := RecursosExteriores.new()
	r.name = "RecursosExteriores"
	r._mapa = mapa
	r._id = mapa.id_mapa
	mapa.objetos.add_child(r)
	r._construir()
	return r


func _ready() -> void:
	add_to_group("usable")


func _construir() -> void:
	if _id == "granja":
		_construir_parcelas_desbloqueables()
		GranjaGanadera.preparar(_mapa, self)
	elif _id == "pueblo":
		_construir_horno_pueblo()
	if _id in ["robledal_niebla", "ruinas_valle", "sierra_mirador"]:
		_construir_zona_pesca_salvaje()
	_construir_colision_arcos()
	_construir_hogueras()
	_construir_forrajeo()
	_construir_menas()
	_construir_cofres()
	_construir_arboles_talables()
	_construir_campamento_mapa()
	_actualizar_enemigos_anochecer()
	if not Juego.hora_cambiada.is_connected(_al_cambiar_hora):
		Juego.hora_cambiada.connect(_al_cambiar_hora)


func _al_cambiar_hora(_min: int) -> void:
	_actualizar_enemigos_anochecer()


func _clave_dia() -> int:
	return AyudasL4b.clave_dia()


func _estado_mapa() -> Dictionary:
	var raw: Variant = Juego.estado_mapas.get(_id, null)
	if not (raw is Dictionary):
		raw = {}
		Juego.estado_mapas[_id] = raw
	var d := raw as Dictionary
	var hoy := _clave_dia()
	if int(d.get("dia_h05", -1)) != hoy:
		d["dia_h05"] = hoy
		d["forraje"] = {}
		d["menas"] = {}
	return d


# ---------------------------------------------------------------------------- Parcelas desbloqueables en Granja
func _construir_parcelas_desbloqueables() -> void:
	var parcelas_nodo := _mapa.objetos.get_node_or_null("Parcelas")
	var defs := [
		{"flag": "parcela_este_abierta", "zona": "Zona_Cultivo_4", "nombre": "la huerta este (8×8)", "precio": 150},
		{"flag": "parcela_oeste_abierta", "zona": "Zona_Cultivo_5", "nombre": "la vega oeste (8×6)", "precio": 200},
	]
	for d: Dictionary in defs:
		var flag := str(d["flag"])
		if bool(Juego.banderas.get(flag, false)):
			continue
		var mk := _mapa.marcador(str(d["zona"]))
		if mk == null:
			continue
		var tam: Vector2 = mk.get_meta("tam", Vector2(8.0, 8.0))
		var grupo := Node3D.new()
		grupo.name = "Bloqueo_" + str(d["zona"])
		add_child(grupo)
		grupo.global_position = mk.global_position

		# Maleza y troncos cerrando la parcela sin desbrozar
		for ox in [-tam.x * 0.25, tam.x * 0.22]:
			for oz in [-tam.y * 0.25, tam.y * 0.22]:
				AyudasL4b.caja(grupo, Vector3(1.5, 0.55, 1.5), Vector3(ox, 0.25, oz), Color(0.28, 0.34, 0.16))
		# Letrero de desbroce / compra
		var poste := Node3D.new()
		poste.position = Vector3(0.0, 0.0, tam.y * 0.5 + 1.0)
		grupo.add_child(poste)
		AyudasL4b.caja(poste, Vector3(0.14, 1.15, 0.14), Vector3(0.0, 0.55, 0.0), Color(0.38, 0.25, 0.14))
		AyudasL4b.caja(poste, Vector3(0.95, 0.45, 0.08), Vector3(0.0, 1.05, 0.04), Color(0.55, 0.38, 0.22))

		var precio := int(d["precio"])
		var nom := str(d["nombre"])
		var pto := Interactuable.new()
		pto.verbo = "Desbrozar"
		pto.nombre_objeto = "%s · %d €" % [nom, precio]
		pto.radio = 2.0
		pto.altura_marca = 1.8
		poste.add_child(pto)
		pto.usado.connect(func(_j: Node3D) -> void:
			if not Juego.cobrar(precio):
				Interfaz.mensaje("Necesitas %d € para contratar el desbroce de %s." % [precio, nom])
				Audio.reproducir("ui_error")
				return
			Juego.banderas[flag] = true
			Audio.reproducir("hacha")
			Interfaz.mensaje("¡%s desbrozada! Ya puedes ararla y sembrar más cultivos." % nom.capitalize())
			if is_instance_valid(grupo):
				grupo.queue_free()
			if parcelas_nodo != null and parcelas_nodo.has_method("reconstruir_desde_h05"):
				parcelas_nodo.call("reconstruir_desde_h05"))


# ---------------------------------------------------------------------------- Colisiones jambas arcos en Ruinas
func _construir_colision_arcos() -> void:
	if _id != "ruinas_valle" or _mapa.cargador == null:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "ColisionArcosRuinas"
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	add_child(cuerpo)
	# Dos arcos colocados en (0, -10.5) rot 0 y (-9.5, -2.0) rot 90 deg
	for arco in [
		{"pos": Vector3(0.0, _suelo_y(0.0, -10.5), -10.5), "yaw": 0.0},
		{"pos": Vector3(-9.5, _suelo_y(-9.5, -2.0), -2.0), "yaw": PI * 0.5},
	]:
		var p: Vector3 = arco["pos"]
		var rot := Basis(Vector3.UP, float(arco["yaw"]))
		for lx in [-2.05, 2.05]:
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(1.15, 3.6, 1.15)
			cs.shape = bx
			cs.transform = Transform3D(rot, p + rot * Vector3(lx, 1.8, 0.0))
			cuerpo.add_child(cs)


# ---------------------------------------------------------------------------- Recolección silvestre diaria
func _construir_forrajeo() -> void:
	var est := _estado_mapa()
	var cogido: Dictionary = est.get("forraje", {}) as Dictionary
	var extra_nodos := _puntos_forraje_lista()
	for entry: Dictionary in extra_nodos:
		var kid := str(entry["id"])
		if bool(cogido.get(kid, false)):
			continue
		var fdef: Dictionary = FORRAJE_DEF.get(str(entry["tipo"]), FORRAJE_DEF["seta"])
		var pos: Vector3 = entry["pos"]
		var nodo := Node3D.new()
		nodo.name = "Forraje_" + kid
		add_child(nodo)
		nodo.global_position = pos

		var esc_path := str(fdef["modelo"])
		if ResourceLoader.exists(esc_path):
			var ps := load(esc_path) as PackedScene
			if ps != null:
				var vis := ps.instantiate() as Node3D
				if vis != null:
					vis.scale = Vector3.ONE * float(fdef["escala"])
					vis.rotation.y = randf_range(0.0, TAU)
					nodo.add_child(vis)

		var pto := Interactuable.new()
		pto.verbo = "Recoger"
		pto.nombre_objeto = str(fdef["nombre"])
		pto.radio = 1.65
		pto.altura_marca = 1.0
		nodo.add_child(pto)
		var item_id := str(fdef["item"])
		var cant := int(fdef["cant"])
		pto.usado.connect(func(_j: Node3D) -> void:
			est["forraje"][kid] = true
			var total_cant := cant + (1 if randf() < Juego.bono_suerte_recoleccion() else 0)
			Juego.anadir_objeto(item_id, total_cant)
			Juego.ganar_xp_habilidad("recoleccion", 14)
			TareasDiarias.registrar_progreso("recolectar", 1)
			Audio.reproducir("cosecha")
			if is_instance_valid(nodo):
				nodo.queue_free())


func _puntos_forraje_lista() -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	for mk: Marker3D in _mapa.marcadores_de_tipo("otro"):
		var nom := String(mk.name)
		if nom.begins_with("Forraj_"):
			var tipo := "seta"
			if "Hierba" in nom:
				tipo = "hierba"
			elif "Mora" in nom:
				tipo = "mora"
			res.append({"id": nom, "tipo": tipo, "pos": mk.global_position})
	# Algunos puntos adicionales naturales en los claros recien abiertos de las zonas clasicas
	var extras := {
		"granja": [
			{"id": "granja_mora_1", "tipo": "mora", "xz": Vector2(-38.0, 22.0)},
			{"id": "granja_hierba_1", "tipo": "hierba", "xz": Vector2(40.0, -18.0)},
		],
		"bosque_norte": [
			{"id": "bosque_seta_1", "tipo": "seta", "xz": Vector2(-28.0, -52.0)},
			{"id": "bosque_seta_2", "tipo": "seta", "xz": Vector2(36.0, -48.0)},
			{"id": "bosque_mora_1", "tipo": "mora", "xz": Vector2(-54.0, 22.0)},
		],
		"costa_lago": [
			{"id": "costa_mora_1", "tipo": "mora", "xz": Vector2(54.0, -12.0)},
			{"id": "costa_hierba_1", "tipo": "hierba", "xz": Vector2(-50.0, -24.0)},
		],
		"pueblo": [
			{"id": "pueblo_hierba_1", "tipo": "hierba", "xz": Vector2(44.0, -24.0)},
		],
		"mina_exterior": [
			{"id": "mina_hierba_1", "tipo": "hierba", "xz": Vector2(-42.0, -18.0)},
		],
	}
	for d: Dictionary in extras.get(_id, []):
		var xz: Vector2 = d["xz"]
		res.append({"id": str(d["id"]), "tipo": str(d["tipo"]), "pos": Vector3(xz.x, _suelo_y(xz.x, xz.y), xz.y)})
	return res


# ---------------------------------------------------------------------------- Vetas en superficie (Sierra y Ruinas)
func _construir_menas() -> void:
	var est := _estado_mapa()
	var rotas: Dictionary = est.get("menas", {}) as Dictionary
	for mk: Marker3D in _mapa.marcadores_de_tipo("otro"):
		var nom := String(mk.name)
		if not MENAS_EXT.has(nom) or bool(rotas.get(nom, false)):
			continue
		var md: Dictionary = MENAS_EXT[nom]
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Veta_" + nom
		cuerpo.collision_layer = 1 | 8
		cuerpo.collision_mask = 0
		add_child(cuerpo)
		cuerpo.global_position = mk.global_position

		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.72
		cs.shape = sp
		cs.position = Vector3(0.0, 0.5, 0.0)
		cuerpo.add_child(cs)

		# Roca base + vetas cristalinas visibles
		var malla_r := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.65
		sph.height = 1.05
		sph.radial_segments = 10
		sph.rings = 5
		malla_r.mesh = sph
		malla_r.position = Vector3(0.0, 0.42, 0.0)
		malla_r.scale = Vector3(1.15, 0.85, 1.0)
		var mat_r := StandardMaterial3D.new()
		mat_r.albedo_color = Color(0.32, 0.31, 0.30)
		mat_r.roughness = 0.92
		malla_r.material_override = mat_r
		cuerpo.add_child(malla_r)

		var col_mena: Color = md["color"]
		for offset: Vector3 in [Vector3(0.28, 0.56, 0.18), Vector3(-0.22, 0.48, -0.22), Vector3(0.05, 0.72, -0.10)]:
			var cr := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.24, 0.32, 0.24)
			cr.mesh = bx
			cr.position = offset
			cr.rotation_degrees = Vector3(randf_range(-25, 25), randf_range(0, 180), randf_range(-25, 25))
			var mc := StandardMaterial3D.new()
			mc.albedo_color = col_mena
			mc.roughness = 0.32
			mc.metallic_specular = 0.75
			if str(md["id"]) == "ambar_valle" or str(md["id"]) == "oro":
				mc.emission_enabled = true
				mc.emission = col_mena * 0.55
				mc.emission_energy_multiplier = 0.65
			cr.material_override = mc
			cuerpo.add_child(cr)

		var estado_veta := {"golpes": 0}
		var max_golpes := maxi(1, int(md["golpes"]) - Juego.nivel("pico"))
		var pto := Interactuable.new()
		pto.verbo = "Picar"
		pto.nombre_objeto = str(md["nombre"])
		pto.radio = 1.85
		pto.altura_marca = 1.25
		cuerpo.add_child(pto)
		pto.usado.connect(func(_j: Node3D) -> void:
			if Juego.id_objeto_en_mano() != "pico":
				Interfaz.mensaje("Equipa el pico para picar %s." % str(md["nombre"]))
				Audio.reproducir("ui_error")
				return
			if not Juego.gastar_energia(2.0 * Juego.factor_energia_habilidad("mineria")):
				Interfaz.mensaje("No te quedan fuerzas para seguir picando.")
				return
			Audio.reproducir("pico")
			estado_veta["golpes"] += 1
			Juego.ganar_xp_habilidad("mineria", 4)
			if int(estado_veta["golpes"]) >= max_golpes:
				est["menas"][nom] = true
				var n_drop := randi_range(int(md["min"]), int(md["max"])) + (1 if randf() < Juego.bono_suerte_minera() else 0)
				Juego.anadir_objeto(str(md["id"]), n_drop)
				Juego.ganar_xp_habilidad("mineria", 14)
				TareasDiarias.registrar_progreso("minar", 1)
				if is_instance_valid(cuerpo):
					cuerpo.queue_free())


# ---------------------------------------------------------------------------- Cofres escondidos
func _construir_cofres() -> void:
	var abiertos: Variant = Juego.banderas.get("cofres_ext_abiertos", {})
	if not (abiertos is Dictionary):
		abiertos = {}
		Juego.banderas["cofres_ext_abiertos"] = abiertos
	var dic_abiertos := abiertos as Dictionary

	for mk: Marker3D in _mapa.marcadores_de_tipo("otro"):
		var nom := String(mk.name)
		if not COFRES_EXT.has(nom):
			continue
		var ya := bool(dic_abiertos.get(nom, false))
		var cuerpo := StaticBody3D.new()
		cuerpo.name = nom
		cuerpo.collision_layer = 1
		cuerpo.collision_mask = 0
		add_child(cuerpo)
		cuerpo.global_position = mk.global_position
		cuerpo.global_rotation = mk.global_rotation

		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.1, 0.85, 0.75)
		cs.shape = bx
		cs.position = Vector3(0.0, 0.42, 0.0)
		cuerpo.add_child(cs)

		var tapa: Node3D = null
		if ResourceLoader.exists(ESCENA_COFRE):
			var ps := load(ESCENA_COFRE) as PackedScene
			if ps != null:
				var vis := ps.instantiate() as Node3D
				if vis != null:
					vis.scale = Vector3.ONE * 1.15
					cuerpo.add_child(vis)
					tapa = vis.find_child("Tapa", true, false) as Node3D
					if ya and tapa != null:
						tapa.rotation_degrees.x = -95.0

		if ya:
			continue
		var botin: Array = COFRES_EXT[nom]
		var pto := Interactuable.new()
		pto.verbo = "Abrir"
		pto.nombre_objeto = "el cofre escondido"
		pto.radio = 1.9
		pto.altura_marca = 1.25
		cuerpo.add_child(pto)
		pto.usado.connect(func(_j: Node3D) -> void:
			dic_abiertos[nom] = true
			Audio.reproducir("mina_cofre")
			Juego.ganar_xp_habilidad("recoleccion", 20)
			var nombres_botin: Array[String] = []
			for b: Variant in botin:
				var bd := b as Dictionary
				Juego.anadir_objeto(str(bd["id"]), int(bd["cantidad"]))
				nombres_botin.append("%d× %s" % [int(bd["cantidad"]), Datos.nombre_objeto(str(bd["id"]))])
			Interfaz.mensaje("¡Cofre encontrado! Recibes " + ", ".join(nombres_botin))
			if tapa != null:
				var tw := create_tween()
				tw.tween_property(tapa, "rotation_degrees:x", -95.0, 0.45).set_trans(Tween.TRANS_BACK)
			if is_instance_valid(pto):
				pto.queue_free())


# ---------------------------------------------------------------------------- Enemigos puntuales al anochecer (solo zonas salvajes, H13)
func _actualizar_enemigos_anochecer(forzar: bool = false) -> void:
	if _anochecer_generado or _id in ZONAS_SEGURAS:
		return
	if Juego.minutos < HORA_ANOCHECER:
		return
	_anochecer_generado = true
	Tutorial.avisar_noche_salvaje()

	var marcas := _mapa.marcadores_de_tipo("otro")
	var puestos: Array[Marker3D] = []
	for m: Marker3D in marcas:
		if ENEMIGOS_SALVAJES.has(String(m.name)):
			puestos.append(m)
	# Si es zona salvaje sin marcadores predefinidos (bosque_norte, costa_lago, mina_exterior), crea 1 punto despejado
	if puestos.is_empty():
		var m_alt := Marker3D.new()
		m_alt.name = "Encuentro_Salvaje_Noche"
		add_child(m_alt)
		var off := Vector2(14.0, -10.0) if _id == "bosque_norte" else Vector2(-10.0, 12.0)
		m_alt.global_position = Vector3(off.x, _suelo_y(off.x, off.y), off.y)
		puestos.append(m_alt)

	# Encuentro puntual: ~65 % de probabilidad por entrada nocturna (si no está forzado para prueba)
	var dia_key := "%s_%d" % [_id, _clave_dia()]
	var reg: Dictionary = Juego.banderas.get("h13_encuentros", {}) as Dictionary
	if not forzar and reg.has(dia_key):
		return
	var hay_evento := true if forzar else (randf() < 0.72)
	if not hay_evento:
		return
	if not (Juego.banderas.get("h13_encuentros", null) is Dictionary):
		Juego.banderas["h13_encuentros"] = {}
	(Juego.banderas["h13_encuentros"] as Dictionary)[dia_key] = true

	var leo := Escenas.jugador()
	var con_farol := leo != null and leo.has_method("farol_encendido") and bool(leo.call("farol_encendido"))
	Audio.reproducir("aviso_encuentro")
	Audio.reproducir("noche_buho")
	if con_farol:
		Interfaz.mensaje("Aullidos en la noche... La luz de tu farol mantiene cautas a las bestias.")
	else:
		Interfaz.mensaje("¡Cuidado! Se acercan criaturas en la espesura nocturna.")

	_nodo_enemigos = Node3D.new()
	_nodo_enemigos.name = "EnemigosNocturnos"
	add_child(_nodo_enemigos)

	var script_en := load("res://scripts/mina/enemigo.gd") as GDScript
	if script_en == null:
		return
	var defs: Array = script_en.call("cargar_definiciones")
	var por_id := {}
	for d: Variant in defs:
		if d is Dictionary:
			var dic := d as Dictionary
			por_id[str(dic.get("id", ""))] = dic

	var max_gen := 1 if con_farol else puestos.size()
	var jefe_errante := (randf() < 0.28)
	for i in mini(puestos.size(), max_gen):
		var m := puestos[i]
		var eid: String = str(ENEMIGOS_SALVAJES.get(String(m.name), "arana_cristal"))
		var dat: Dictionary = (por_id.get(eid, {}) as Dictionary).duplicate(true)
		if dat.is_empty():
			continue
		dat["nivel_mina"] = 4 if jefe_errante and i == 0 else 2
		if jefe_errante and i == 0:
			dat["jefe"] = true
			dat["nombre"] = "Acechador nocturno"
			dat["vida"] = float(dat.get("vida", 45.0)) * 2.1
		var e := script_en.new() as CharacterBody3D
		e.set_meta("nocturno_h13", true)
		_nodo_enemigos.add_child(e)
		e.global_position = m.global_position + Vector3(0.0, 0.1, 0.0)
		e.call("configurar", dat)


# ---------------------------------------------------------------------------- Campamento portátil (H13)
static func montar_campamento_jugador(jugador: Node3D) -> bool:
	var rec := jugador.get_tree().get_first_node_in_group("recursos_exteriores") as RecursosExteriores if jugador.get_tree() != null else null
	if rec == null:
		Interfaz.mensaje("Solo puedes montar el campamento al aire libre en zonas salvajes.")
		return false
	if rec._id in ZONAS_SEGURAS:
		Audio.reproducir("ui_error")
		Interfaz.mensaje("No hace falta acampar en la granja o el pueblo: solo en zonas salvajes.")
		return false
	var camp_prev := Juego.campamento_estado()
	if not camp_prev.is_empty():
		Interfaz.mensaje("Ya tienes un campamento montado en %s. Recógelo antes." % str(camp_prev.get("mapa", "")))
		return false
	if not Juego.quitar_objeto("kit_campamento", 1):
		return false
	var delante := jugador.global_position + Vector3.FORWARD.rotated(Vector3.UP, jugador.camara.yaw) * 2.4
	delante.y = rec._suelo_y(delante.x, delante.z)
	Juego.guardar_campamento(rec._id, delante)
	rec._construir_campamento_mapa()
	Audio.reproducir("hoguera_crepitando")
	Interfaz.mensaje("Campamento portátil montado. Usa la hoguera para cocinar, descansar o guardar.")
	return true


func _construir_campamento_mapa() -> void:
	if not is_in_group("recursos_exteriores"):
		add_to_group("recursos_exteriores")
	var viejo := get_node_or_null("CampamentoPortatil")
	if viejo != null:
		viejo.queue_free()
	var est := Juego.campamento_estado()
	if est.is_empty() or str(est.get("mapa", "")) != _id:
		return
	var arr: Array = est.get("pos", []) as Array
	if arr.size() != 3:
		return
	var pos := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	var raiz := StaticBody3D.new()
	raiz.name = "CampamentoPortatil"
	raiz.collision_layer = 1
	raiz.collision_mask = 0
	add_child(raiz)
	raiz.global_position = pos

	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.85, 1.35, 1.85)
	col.shape = bx
	col.position = Vector3(-0.6, 0.65, 0.0)
	raiz.add_child(col)

	if ResourceLoader.exists(ESCENA_CAMPAMENTO):
		var ps := load(ESCENA_CAMPAMENTO) as PackedScene
		if ps != null:
			var vis := ps.instantiate() as Node3D
			if vis != null:
				vis.rotation_degrees.y = -32.0
				_estilizar_campamento_pbr(vis)
				raiz.add_child(vis)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.56, 0.22)
	luz.light_energy = 2.4
	luz.omni_range = 8.5
	luz.position = Vector3(1.15, 0.55, 0.65)
	GraficaH03.ajustar_luz(luz, true)
	raiz.add_child(luz)

	var timer_audio := Timer.new()
	timer_audio.wait_time = 6.5
	timer_audio.autostart = true
	raiz.add_child(timer_audio)
	timer_audio.timeout.connect(func() -> void:
		var j := Escenas.jugador()
		if j != null and j.global_position.distance_squared_to(raiz.global_position) < 100.0:
			Audio.reproducir_posicional("hoguera_crepitando", raiz.global_position, raiz))

	var pto := Interactuable.new()
	pto.verbo = "Usar"
	pto.nombre_objeto = "el campamento portátil"
	pto.radio = 2.4
	pto.altura_marca = 1.65
	pto.position = Vector3(0.5, 0.0, 0.0)
	raiz.add_child(pto)
	pto.usado.connect(func(_j: Node3D) -> void:
		Interfaz.preguntar("Campamento portátil", [
			"Cocinar en la hoguera",
			"Descansar 3 horas (+Salud, +Energía, +Resistencia)",
			"Guardar partida aquí",
			"Recoger campamento",
			"Cerrar",
		], _al_usar_campamento.bind(raiz)))


func _al_usar_campamento(idx: int, raiz: Node3D) -> void:
	match idx:
		0:
			if Interfaz.has_method("abrir_cocina"):
				Interfaz.call("abrir_cocina", "Hoguera del campamento")
		1:
			if Juego.descansar_campamento(3):
				Audio.reproducir("hoguera_crepitando")
				Interfaz.mensaje("Descansas junto al fuego 3 horas. Recuperas salud, energía y aliento.")
		2:
			Juego.guardar(true)
		3:
			if Juego.anadir_objeto("kit_campamento", 1) == 0:
				Juego.limpiar_campamento()
				if is_instance_valid(raiz):
					raiz.queue_free()
				Interfaz.mensaje("Campamento recogido y guardado en la mochila.")


func _estilizar_campamento_pbr(raiz: Node3D) -> void:
	const DIFF := "res://assets/texturas/h03/rocks_ground_06/rocks_ground_06_diff_2k.jpg"
	const NOR := "res://assets/texturas/h03/rocks_ground_06/rocks_ground_06_nor_gl_2k.jpg"
	var t_diff := load(DIFF) as Texture2D if ResourceLoader.exists(DIFF) else null
	var t_nor := load(NOR) as Texture2D if ResourceLoader.exists(NOR) else null
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for idx in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			match idx:
				0:  # Lona de tienda verde oliva mate con doble cara para ver el interior
					m.albedo_color = Color(0.14, 0.20, 0.11)
					m.roughness = 0.94
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				1:  # Postes de madera
					m.albedo_color = Color(0.19, 0.12, 0.07)
					m.roughness = 0.88
				2:  # Saco de dormir rojo cálido
					m.albedo_color = Color(0.36, 0.12, 0.09)
					m.roughness = 0.92
				3:  # Piedras del anillo de hoguera (triplanar PBR)
					m.uv1_triplanar = true
					m.uv1_scale = Vector3.ONE * 0.7
					m.albedo_texture = t_diff
					m.normal_enabled = t_nor != null
					m.normal_texture = t_nor
					m.albedo_color = Color(0.45, 0.42, 0.40)
					m.roughness = 0.92
				4:  # Brasas vivas
					m.albedo_color = Color(1.0, 0.34, 0.05)
					m.emission_enabled = true
					m.emission = Color(1.0, 0.36, 0.05)
					m.emission_energy_multiplier = 4.6
				_:  # Olla de hierro fundido
					m.albedo_color = Color(0.08, 0.085, 0.095)
					m.metallic = 0.84
					m.roughness = 0.44
			mi.set_surface_override_material(idx, m)


func _construir_hogueras() -> void:
	if not HOGUERAS_EXT.has(_id):
		return
	var xz: Vector2 = HOGUERAS_EXT[_id]
	var y := _suelo_y(xz.x, xz.y)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Hoguera_" + _id
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	add_child(cuerpo)
	cuerpo.global_position = Vector3(xz.x, y, xz.y)

	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.65
	cyl.height = 1.25
	cs.shape = cyl
	cs.position = Vector3(0.0, 0.62, 0.0)
	cuerpo.add_child(cs)

	if ResourceLoader.exists(ESCENA_HOGUERA):
		var ps := load(ESCENA_HOGUERA) as PackedScene
		if ps != null:
			var vis := ps.instantiate() as Node3D
			if vis != null:
				cuerpo.add_child(vis)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.58, 0.22)
	luz.light_energy = 1.4
	luz.omni_range = 6.5
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, 0.45, 0.0)
	cuerpo.add_child(luz)

	var pto := Interactuable.new()
	pto.verbo = "Cocinar en"
	pto.nombre_objeto = "la hoguera de campaña"
	pto.radio = 1.95
	pto.altura_marca = 1.45
	cuerpo.add_child(pto)
	pto.usado.connect(func(_j: Node3D) -> void:
		if Interfaz.has_method("abrir_cocina"):
			Interfaz.call("abrir_cocina", "Hoguera de campaña"))


func _construir_horno_pueblo() -> void:
	const ESCENA_HORNO := "res://assets/herreria/horno_fundicion.glb"
	var marca: Marker3D = _mapa.marcador("Spawn_Herrero") if _mapa != null and _mapa.has_method("marcador") else null
	var base := marca.global_position if marca != null else Vector3(14.0, 0.0, -8.0)
	var hx := base.x + 3.45
	var hz := base.z - 0.15
	var hy := _suelo_y(hx, hz)

	var cuerpo := StaticBody3D.new()
	cuerpo.name = "HornoFundicionPueblo"
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var cil := CylinderShape3D.new()
	cil.radius = 0.62
	cil.height = 1.9
	forma.shape = cil
	forma.position = Vector3(0.0, 0.95, 0.0)
	cuerpo.add_child(forma)
	add_child(cuerpo)
	cuerpo.global_position = Vector3(hx, hy, hz)
	cuerpo.rotation_degrees.y = 148.0

	if ResourceLoader.exists(ESCENA_HORNO):
		var ps := load(ESCENA_HORNO) as PackedScene
		if ps != null:
			var vis := ps.instantiate() as Node3D
			if vis != null:
				vis.scale = Vector3.ONE * 1.12
				_estilizar_horno_pbr(vis)
				cuerpo.add_child(vis)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.44, 0.14)
	luz.light_energy = 1.65
	luz.omni_range = 4.6
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, 0.58, 0.45)
	cuerpo.add_child(luz)

	var pto := Interactuable.new()
	pto.verbo = "Usar"
	pto.nombre_objeto = "el horno de fundición"
	pto.radio = 2.05
	pto.altura_marca = 2.35
	cuerpo.add_child(pto)
	pto.usado.connect(func(_j: Node3D) -> void:
		if Interfaz.has_method("abrir_herreria"):
			Interfaz.call("abrir_herreria", 0))


func _estilizar_horno_pbr(raiz: Node3D) -> void:
	const DIFF := "res://assets/texturas/h03/rocks_ground_06/rocks_ground_06_diff_2k.jpg"
	const NOR := "res://assets/texturas/h03/rocks_ground_06/rocks_ground_06_nor_gl_2k.jpg"
	const ROUGH := "res://assets/texturas/h03/rocks_ground_06/rocks_ground_06_rough_2k.jpg"
	var t_diff := load(DIFF) as Texture2D if ResourceLoader.exists(DIFF) else null
	var t_nor := load(NOR) as Texture2D if ResourceLoader.exists(NOR) else null
	var t_rough := load(ROUGH) as Texture2D if ResourceLoader.exists(ROUGH) else null
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for idx in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.55
			if idx == 0 or idx == 1:
				m.albedo_texture = t_diff
				m.normal_enabled = t_nor != null
				m.normal_texture = t_nor
				m.roughness_texture = t_rough
				m.albedo_color = Color(0.55, 0.52, 0.50) if idx == 0 else Color(0.72, 0.34, 0.24)
				m.roughness = 0.88
			elif idx == 2:
				m.albedo_color = Color(0.08, 0.085, 0.095)
				m.metallic = 0.85
				m.roughness = 0.42
			else:
				m.albedo_color = Color(1.0, 0.34, 0.05)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.36, 0.05)
				m.emission_energy_multiplier = 4.5
			mi.set_surface_override_material(idx, m)


func _construir_zona_pesca_salvaje() -> void:
	const POS_AGUAS := {
		"robledal_niebla": Vector2(18.0, 14.0),
		"ruinas_valle": Vector2(-16.0, 12.0),
		"sierra_mirador": Vector2(-14.0, -14.0),
	}
	if not POS_AGUAS.has(_id):
		return
	var p2: Vector2 = POS_AGUAS[_id]
	var y := _suelo_y(p2.x, p2.y)
	var disco := MeshInstance3D.new()
	disco.name = "EstanquePescaH11"
	var cm := CylinderMesh.new()
	cm.top_radius = 4.2
	cm.bottom_radius = 4.2
	cm.height = 0.08
	disco.mesh = cm
	var m_agua := StandardMaterial3D.new()
	m_agua.albedo_color = Color(0.08, 0.22, 0.28, 0.86)
	m_agua.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_agua.roughness = 0.08
	m_agua.metallic = 0.22
	disco.material_override = m_agua
	add_child(disco)
	disco.global_position = Vector3(p2.x, y + 0.02, p2.y)

	var zp := ZonaPesca.new()
	zp.name = "ZonaPescaSalvaje"
	zp.marcador_pesca = ""
	zp.id_zona_fija = _id
	zp.radio_uso = 7.2
	add_child(zp)
	zp.global_position = disco.global_position


func _suelo_y(x: float, z: float) -> float:
	if _mapa != null and _mapa.has_method("_columna_suelo"):
		var col: Dictionary = _mapa.call("_columna_suelo", x, z)
		var y := float(col.get("suelo", NAN))
		if not is_nan(y):
			return y
	return 0.4


# --- Árboles talables -----------------------------------------------------------------------------------------------

func arboles_talables() -> Array[Dictionary]:
	return _arboles_talables


func _construir_arboles_talables() -> void:
	_arboles_talables.clear()
	if not (_id in ["granja", "bosque_norte", "costa_lago", "robledal_niebla", "ruinas_valle", "sierra_mirador", "mina_exterior"]):
		return
	var est := _estado_mapa()
	var talados_raw: Variant = est.get("arboles_talados", {})
	var talados: Dictionary = talados_raw as Dictionary if talados_raw is Dictionary else {}
	est["arboles_talados"] = talados

	var evitar: Array[Vector2] = []
	if _mapa != null:
		for n_mk in _mapa.find_children("*", "Marker3D", true, false):
			var mk := n_mk as Marker3D
			evitar.append(Vector2(mk.global_position.x, mk.global_position.z))
	if HOGUERAS_EXT.has(_id):
		evitar.append(HOGUERAS_EXT[_id])
	for hijo in get_children():
		if hijo is Node3D and (String(hijo.name).begins_with("Estanque") or String(hijo.name).begins_with("GranjaGanadera")):
			var h3 := hijo as Node3D
			evitar.append(Vector2(h3.global_position.x, h3.global_position.z))

	var contenedor := Node3D.new()
	contenedor.name = "ArbolesTalables"
	add_child(contenedor)

	var rng := RandomNumberGenerator.new()
	rng.seed = 8840 + int(_id.hash())
	var cajas_evitar := _cajas_parcelas_granja()
	var objetivo := 6 if _id == "granja" else 9
	var tamanos := ["pequeno", "mediano", "joven"]
	var puestos: Array[Vector2] = []

	var aabb_m: AABB = _mapa.call("aabb_mapa") if _mapa != null and _mapa.has_method("aabb_mapa") else AABB(Vector3(-40, -2, -40), Vector3(80, 20, 80))
	var intentos := 0
	while puestos.size() < objetivo and intentos < 240:
		intentos += 1
		var px := rng.randf_range(aabb_m.position.x + 4.5, aabb_m.end.x - 4.5)
		var pz := rng.randf_range(aabb_m.position.z + 4.5, aabb_m.end.z - 4.5)
		if _mapa == null or not _mapa.has_method("_columna_suelo"):
			continue
		var col: Dictionary = _mapa.call("_columna_suelo", px, pz)
		var py := float(col.get("suelo", NAN))
		if is_nan(py) or absf(float(col.get("obstaculo", 0.0))) > 0.25:
			continue
		if not _mapa.punto_dentro(Vector3(px, py, pz), 2.8):
			continue
		var p2 := Vector2(px, pz)
		var libre := true
		for ev: Vector2 in evitar:
			if p2.distance_to(ev) < 5.2:
				libre = false
				break
		if not libre:
			continue
		for rc: Rect2 in cajas_evitar:
			if rc.grow(2.5).has_point(p2):
				libre = false
				break
		if not libre:
			continue
		for ya: Vector2 in puestos:
			if p2.distance_to(ya) < 5.5:
				libre = false
				break
		if not libre:
			continue
		puestos.append(p2)
		var tam: String = tamanos[puestos.size() % tamanos.size()]
		var id_arb := "%s_arb_%d" % [_id, puestos.size()]
		_crear_arbol_talable(contenedor, id_arb, tam, Vector3(px, py, pz), rng, talados)


func _cajas_parcelas_granja() -> Array[Rect2]:
	var r: Array[Rect2] = []
	if _mapa == null:
		return r
	for n in _mapa.find_children("Zona_*", "Marker3D", true, false):
		var mk := n as Marker3D
		var tam := mk.get_meta("tam", Vector2(8.0, 8.0)) as Vector2
		var p := Vector2(mk.global_position.x, mk.global_position.z)
		r.append(Rect2(p - tam * 0.5, tam))
	return r


func _crear_arbol_talable(padre: Node3D, id_arb: String, tam: String, pos: Vector3, rng: RandomNumberGenerator, talados: Dictionary) -> void:
	var cfg: Dictionary = ARBOLES_TAMANOS[tam]
	var raiz := Node3D.new()
	raiz.name = "Arbol_" + id_arb
	raiz.position = pos
	padre.add_child(raiz)

	var cuerpo := StaticBody3D.new()
	cuerpo.name = "TroncoBase"
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	raiz.add_child(cuerpo)

	var cs := CollisionShape3D.new()
	var cil := CylinderShape3D.new()
	cil.radius = float(cfg["radio"])
	cil.height = float(cfg["alto_col"])
	cs.shape = cil
	cs.position = Vector3(0.0, cil.height * 0.5, 0.0)
	cuerpo.add_child(cs)

	var tocon := _crear_visual_tocon(float(cfg["radio"]))
	tocon.name = "ToconVisible"
	tocon.visible = talados.has(id_arb)
	raiz.add_child(tocon)

	var ang_caida := rng.randf_range(0.0, TAU)
	var pivot := Node3D.new()
	pivot.name = "CopaPivot"
	pivot.position = Vector3(0.0, 0.24, 0.0)
	pivot.rotation.y = ang_caida
	raiz.add_child(pivot)

	var vis := _crear_visual_arbol_talable(str(cfg["modelo"]), float(cfg["escala"]), cfg["tinte_copa"] as Color, float(cfg["radio"]))
	vis.rotation.y = rng.randf_range(0.0, TAU)
	vis.position = Vector3(0.0, -0.24, 0.0)
	pivot.add_child(vis)

	var pto := Interactuable.new()
	pto.name = "Talar"
	pto.verbo = "Talar"
	pto.herramienta = "hacha"
	pto.nombre_objeto = str(cfg["nombre"])
	pto.radio = 1.65
	pto.altura_marca = 1.45
	pto.mostrar_descripcion = false
	pto.nodo_visual = NodePath("..")
	cuerpo.add_child(pto)

	var reg := {
		"id": id_arb,
		"tamano": tam,
		"pos": pos,
		"golpes": 0,
		"golpes_max": int(cfg["golpes"]),
		"madera": int(cfg["madera"]),
		"nombre": str(cfg["nombre"]),
		"talado": talados.has(id_arb),
		"raiz": raiz,
		"cuerpo": cuerpo,
		"col_forma": cs,
		"tocon": tocon,
		"pivot": pivot,
		"punto": pto,
		"cil_orig": cil,
		"ang_caida": ang_caida,
	}
	pto.usado.connect(func(_j: Node3D) -> void: _golpear_arbol(reg))
	_arboles_talables.append(reg)

	if bool(reg["talado"]):
		var ang := float(talados.get(id_arb, reg["ang_caida"]))
		_aplicar_estado_talado_inmediato(reg, ang)


func _crear_visual_tocon(radio_base: float) -> Node3D:
	if ResourceLoader.exists(ESCENA_TOCON):
		var ps := load(ESCENA_TOCON) as PackedScene
		if ps != null:
			var n := ps.instantiate() as Node3D
			if n != null:
				n.scale = Vector3.ONE * clampf(radio_base * 1.45, 0.35, 0.65)
				return n
	var mi := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = radio_base * 0.85
	cil.bottom_radius = radio_base * 1.05
	cil.height = 0.28
	mi.mesh = cil
	mi.position = Vector3(0.0, 0.14, 0.0)
	return mi


func _crear_visual_arbol_talable(ruta_modelo: String, escala: float, tinte: Color, radio: float) -> Node3D:
	var cont := Node3D.new()
	cont.name = "MallaArbol"
	if ResourceLoader.exists(ruta_modelo):
		var ps := load(ruta_modelo) as PackedScene
		if ps != null:
			var mod := ps.instantiate() as Node3D
			if mod != null:
				mod.scale = Vector3.ONE * escala
				for mi: MeshInstance3D in mod.find_children("*", "MeshInstance3D", true, false):
					if mi.mesh == null:
						continue
					for s in mi.mesh.get_surface_count():
						var mat := mi.get_active_material(s)
						if mat is StandardMaterial3D:
							var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
							var nom_m := String(mi.name).to_lower()
							if "twig" in nom_m or "leaf" in nom_m or "needle" in nom_m or sm.albedo_texture != null:
								if sm.albedo_texture != null and sm.albedo_texture.has_alpha():
									sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
									sm.alpha_scissor_threshold = 0.45
									sm.cull_mode = BaseMaterial3D.CULL_DISABLED
								sm.albedo_color = sm.albedo_color * tinte
							mi.set_surface_override_material(s, sm)
				cont.add_child(mod)
	# Marca distintiva de corte en la base para diferenciar los árboles talables del bosque decorativo.
	var banda := MeshInstance3D.new()
	banda.name = "MarcaTala"
	var bm := CylinderMesh.new()
	bm.top_radius = radio * 0.92
	bm.bottom_radius = radio * 0.95
	bm.height = 0.12
	banda.mesh = bm
	banda.position = Vector3(0.0, 0.44, 0.0)
	var m_banda := StandardMaterial3D.new()
	m_banda.albedo_color = Color(0.74, 0.56, 0.28)
	m_banda.roughness = 0.85
	banda.material_override = m_banda
	cont.add_child(banda)
	return cont


func usar(id: String, punto: Vector3, _jugador: Node3D) -> bool:
	if id != "hacha":
		return false
	for reg: Dictionary in _arboles_talables:
		if bool(reg["talado"]):
			continue
		var pos_a: Vector3 = reg["pos"]
		if Vector2(punto.x - pos_a.x, punto.z - pos_a.z).length() <= 1.85:
			_golpear_arbol(reg)
			return true
	return false


func _golpear_arbol(reg: Dictionary) -> void:
	if bool(reg["talado"]):
		return
	if not Juego.gastar_energia(2.0 * Juego.factor_energia_habilidad("recoleccion")):
		return
	var necesarias := maxi(1, int(reg["golpes_max"]) - mini(2, Juego.nivel("hacha")))
	reg["golpes"] = int(reg["golpes"]) + 1
	var pivot := reg["pivot"] as Node3D
	var pos_a: Vector3 = reg["pos"]
	Audio.reproducir("hacha")
	EfectosAccion.soltar(self, "talar", pos_a + Vector3(0.0, 0.3, 0.0))
	CamaraJuego.sacudir_activa(0.04, 0.14)

	if int(reg["golpes"]) < necesarias:
		if pivot != null and is_instance_valid(pivot):
			var tw := pivot.create_tween()
			tw.tween_property(pivot, "rotation:z", 0.06, 0.07)
			tw.tween_property(pivot, "rotation:z", -0.05, 0.08)
			tw.tween_property(pivot, "rotation:z", 0.0, 0.08)
		return

	# Último hachazo: animar caída y dejar visible en estado talado.
	reg["talado"] = true
	var est := _estado_mapa()
	var talados := est.get("arboles_talados", {}) as Dictionary
	var ang := float(reg["ang_caida"])
	talados[str(reg["id"])] = ang
	est["arboles_talados"] = talados

	var pto := reg["punto"] as Interactuable
	if pto != null and is_instance_valid(pto):
		pto.activo = false
	var tocon := reg["tocon"] as Node3D
	if tocon != null and is_instance_valid(tocon):
		tocon.visible = true
	_reducir_colision_tocon(reg)

	if pivot != null and is_instance_valid(pivot):
		pivot.rotation.y = ang
		var tw_c := pivot.create_tween()
		tw_c.set_trans(Tween.TRANS_CUBIC)
		tw_c.set_ease(Tween.EASE_IN)
		tw_c.tween_property(pivot, "rotation:x", deg_to_rad(85.0), 0.68)
		tw_c.parallel().tween_property(pivot, "position:y", 0.14, 0.68)
		tw_c.finished.connect(func() -> void:
			EfectosAccion.soltar(self, "talar", pos_a + Vector3(0.0, 0.1, 0.0)))

	var cant_madera := int(reg["madera"])
	Juego.anadir_objeto("madera", cant_madera)
	Juego.ganar_xp_habilidad("recoleccion", 14)
	TareasDiarias.registrar_progreso("talar", 1)
	Interfaz.mensaje("Talas %s (+%d madera)." % [str(reg["nombre"]), cant_madera], "madera")


func _aplicar_estado_talado_inmediato(reg: Dictionary, ang: float) -> void:
	var pto := reg["punto"] as Interactuable
	if pto != null and is_instance_valid(pto):
		pto.activo = false
	var tocon := reg["tocon"] as Node3D
	if tocon != null and is_instance_valid(tocon):
		tocon.visible = true
	var pivot := reg["pivot"] as Node3D
	if pivot != null and is_instance_valid(pivot):
		pivot.position.y = 0.14
		pivot.rotation = Vector3(deg_to_rad(85.0), ang, 0.0)
	_reducir_colision_tocon(reg)


func _reducir_colision_tocon(reg: Dictionary) -> void:
	var cs := reg["col_forma"] as CollisionShape3D
	if cs != null and is_instance_valid(cs) and cs.shape is CylinderShape3D:
		var cil := cs.shape as CylinderShape3D
		cil.height = 0.38
		cs.position.y = 0.19
