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
const HORA_ANOCHECER := 1110  # 18:30

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

var _mapa: Mapa = null
var _id: String = ""
var _anochecer_generado: bool = false
var _nodo_enemigos: Node3D = null


static func preparar(mapa: Mapa) -> RecursosExteriores:
	var r := RecursosExteriores.new()
	r.name = "RecursosExteriores"
	r._mapa = mapa
	r._id = mapa.id_mapa
	mapa.objetos.add_child(r)
	r._construir()
	return r


func _construir() -> void:
	if _id == "granja":
		_construir_parcelas_desbloqueables()
	_construir_colision_arcos()
	_construir_hogueras()
	_construir_forrajeo()
	_construir_menas()
	_construir_cofres()
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


# ---------------------------------------------------------------------------- Enemigos puntuales al anochecer (solo zonas salvajes)
func _actualizar_enemigos_anochecer() -> void:
	if _anochecer_generado or _id == "granja" or _id == "pueblo":
		return
	if Juego.minutos < HORA_ANOCHECER:
		return
	var marcas := _mapa.marcadores_de_tipo("otro")
	var puestos: Array[Marker3D] = []
	for m: Marker3D in marcas:
		if ENEMIGOS_SALVAJES.has(String(m.name)):
			puestos.append(m)
	if puestos.is_empty():
		return
	_anochecer_generado = true
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

	for m: Marker3D in puestos:
		var eid: String = ENEMIGOS_SALVAJES[String(m.name)]
		var dat: Dictionary = (por_id.get(eid, {}) as Dictionary).duplicate(true)
		if dat.is_empty():
			continue
		dat["nivel_mina"] = 2
		var e := script_en.new() as CharacterBody3D
		_nodo_enemigos.add_child(e)
		e.global_position = m.global_position + Vector3(0.0, 0.1, 0.0)
		e.call("configurar", dat)


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


func _suelo_y(x: float, z: float) -> float:
	if _mapa != null and _mapa.has_method("_columna_suelo"):
		var col: Dictionary = _mapa.call("_columna_suelo", x, z)
		var y := float(col.get("suelo", NAN))
		if not is_nan(y):
			return y
	return 0.4
