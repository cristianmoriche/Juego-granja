class_name Mapa
extends Node3D
## Raíz de cada escena de mapa (granja, pueblo, mina_exterior, mina_interior).
## Crea el CargadorMapa de L1 (si existe su script y sus datos), configura cielo, niebla, sol y salidas
## y avisa con `listo` cuando todo está preparado. Lo que añadan L4a/L4b va dentro del nodo `Objetos`.
##
## Hijos de la escena: WorldEnvironment, Sol (DirectionalLight3D con ciclo_dia.gd) y Objetos (Node3D).

signal listo

const RUTA_CARGADOR := "res://scripts/mapas/cargador_mapa.gd"
const RUTA_SALIDA := "res://escenas/objetos/salida.tscn"
const RUTA_DATOS_MAPA := "res://assets/mapas/%s/marcadores.json"
const RUTA_PUNTOS := "res://datos/puntos_interes.json"
## Capa 6 «limites»: los muros invisibles del borde del mapa solo los nota el jugador (la cámara y los rayos no).
const CAPA_LIMITES := 32
## Capa 7 «solo_jugador»: en las cuevas, techo, maderas, raíles y objetos. Leo y la cámara
## también comprueban esta capa. En la capa 1 queda la roca.
const CAPA_SOLO_JUGADOR := 64
const CAPA_SOLO_CAMARA := 128
const SEPARACION_POSTES := 2.6

@export var id_mapa: String = ""
@export var interior: bool = false
## Si es false no se crea el cargador de L1 (el mapa de prueba lleva su geometría dentro de la escena).
@export var usar_cargador: bool = true

var esta_listo: bool = false
var cargador: Node = null
## Polígono [x, z] del área jugable (de datos/limites.json); vacío si el mapa no tiene límites.
var poligono_limites: PackedVector2Array = PackedVector2Array()
## Valla de madera de los lados abiertos (se construye unos fotogramas después de `listo`).
var vallas: Node3D = null
var numero_postes: int = 0
var numero_travesanos: int = 0
## Interactuables de ejemplo creados desde datos/puntos_interes.json.
var puntos_interes: Array[Interactuable] = []
## Puertas interactuables creadas desde datos/conexiones.json (entradas con "puerta": true).
var puertas: Array[PuertaMapa] = []
var vallas_listas: bool = false

@onready var _entorno: WorldEnvironment = $WorldEnvironment
@onready var _sol: DirectionalLight3D = $Sol
@onready var objetos: Node3D = $Objetos

var _salidas: Array[Node] = []
var _lluvia: GPUParticles3D = null
var _nieve: GPUParticles3D = null
var _raiz_reparar: Node3D = null
var _mercader: Node3D = null
var _es_tormenta_lluvia: bool = false
var _relampago: DirectionalLight3D
var _espera_relampago := 0.0
var _fase_relampago := 0.0
var _salpicaduras: GPUParticles3D
var _espera_salpicadura := 0.0
var _azar_lluvia := RandomNumberGenerator.new()
var _mat_vallas: StandardMaterial3D = null
var _pass_nieve_vallas: ShaderMaterial = null
var _mat_toldo: StandardMaterial3D = null
var _pass_nieve_toldo: ShaderMaterial = null


func _ready() -> void:
	add_to_group("mapa")
	if not interior:
		var estacion := clampi(Juego.estacion, 0, 3)
		CieloH03.solicitar_hora(Juego.minutos, CicloDia.AMANECER[estacion], CicloDia.ATARDECER[estacion])
	_crear_cargador()
	if cargador == null:
		_al_cargar()
	Escenas.mapa_cargado.connect(_al_mapa_cargado)
	Juego.evento_cambiado.connect(_al_evento_cambiado)
	Juego.estacion_cambiada.connect(_actualizar_precipitacion)
	Juego.clima_cambiado.connect(_al_cambio_clima)


func _crear_cargador() -> void:
	if not usar_cargador or not ResourceLoader.exists(RUTA_CARGADOR):
		return
	if not FileAccess.file_exists(RUTA_DATOS_MAPA % id_mapa):
		push_warning("Mapa %s: todavía no hay datos de L1 (assets/mapas/%s/marcadores.json)." % [id_mapa, id_mapa])
		return
	var script := load(RUTA_CARGADOR) as GDScript
	if script == null:
		push_warning("Mapa %s: no se pudo cargar %s" % [id_mapa, RUTA_CARGADOR])
		return
	var nodo := script.new() as Node
	nodo.name = "CargadorMapa"
	nodo.set("id_mapa", id_mapa)
	cargador = nodo
	nodo.connect("cargado", _al_cargar)
	add_child(nodo)   # su _ready() llama a cargar()


func _al_cargar() -> void:
	if esta_listo:
		return
	if cargador == null and not _hay_suelo():
		_suelo_de_emergencia()
	var nm := get_node_or_null("Objetos/NivelMina")
	if interior and cargador != null:
		_mostrar_techos()
		_separar_colisiones_de_cueva()
		if id_mapa == "mina_interior":
			_alisar_paredes_de_llegada()
	if nm != null and nm.has_method("preparar"):
		nm.call("preparar", self)
	_configurar_entorno()
	_cargar_lightmap()
	if nm != null and nm.has_method("aplicar_ambiente"):
		nm.call("aplicar_ambiente", self)
	_crear_salidas()
	_crear_limites()
	if not interior:
		HorizonteH05.crear(self, id_mapa)
		if cargador is CargadorMapa:
			var cuad := CuadriculasRender.new()
			cuad.name = "CuadriculasRender"
			add_child(cuad)
			cuad.construir(self, cargador as CargadorMapa)
	esta_listo = true
	listo.emit()
	_construir_vallas_y_puntos()   # necesita colisiones ya registradas: espera unos fotogramas de física


## Carga iluminación indirecta prehorneada si el mapa cuenta con archivo .lmbake.
func _cargar_lightmap() -> void:
	var ruta := "res://assets/mapas/%s/%s.lmbake" % [id_mapa, id_mapa]
	if not ResourceLoader.exists(ruta):
		return
	var datos_lm := CargadorMapa.obtener_recurso(ruta) as LightmapGIData
	if datos_lm == null or datos_lm.get_user_count() <= 0:
		return
	var lm := LightmapGI.new()
	lm.name = "LightmapMapa"
	lm.interior = interior
	lm.light_data = datos_lm
	add_child(lm)


## Las vistas de ojos y hombro dejan ver los techos originales, con sus materiales y colisión.
func _mostrar_techos() -> void:
	for nodo: Node in cargador.find_children("Techo*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.layers = FotoCenital.CAPA_TECHOS
			for i in mi.mesh.get_surface_count():
				var material := mi.get_active_material(i) as BaseMaterial3D
				if material != null:
					var interior_techo := material.duplicate() as BaseMaterial3D
					interior_techo.cull_mode = BaseMaterial3D.CULL_DISABLED
					if id_mapa == "mina_interior" and interior_techo.albedo_texture == null:
						CargadorMapa.aplicar_pbr_techo_roca(interior_techo)
					mi.set_surface_override_material(i, interior_techo)


## Conserva en la capa 1 la roca (formas «col_*Roca*»). El resto va a la capa 7.
func _separar_colisiones_de_cueva() -> void:
	var colisiones: Variant = cargador.get("colisiones")
	if not (colisiones is Node):
		return
	var solo_jugador := StaticBody3D.new()
	solo_jugador.name = "ColisionSoloJugador"
	solo_jugador.collision_layer = CAPA_SOLO_JUGADOR
	solo_jugador.collision_mask = 0
	add_child(solo_jugador)
	var solo_camara: StaticBody3D
	if id_mapa == "mina_interior":
		solo_camara = StaticBody3D.new()
		solo_camara.name = "ColisionSoloCamara"
		solo_camara.collision_layer = CAPA_SOLO_CAMARA
		solo_camara.collision_mask = 0
		add_child(solo_camara)
	for hijo: Node in (colisiones as Node).get_children():
		if not (hijo is CollisionShape3D):
			continue
		var nom := String(hijo.name)
		if id_mapa == "mina_interior":
			# Los faroles bajos dejan pasar a Leo y conservan la colisión de cámara.
			if nom.contains("Prop_int_Laton") or nom.contains("Prop_int_Hierro") or nom.contains("Prop_int_Cristal_farol"):
				hijo.reparent(solo_camara, true)
			elif not nom.contains("Roca"):
				hijo.reparent(solo_jugador, true)
		else:
			if not (nom.contains("Suelo") or nom.contains("Pared") or nom.contains("Techo")):
				hijo.reparent(solo_jugador, true)


## El relieve triangular de la entrada retenía la cápsula al caer de un salto.
## Se sustituye solo la colisión del tramo por suelo plano y paredes continuas.
func _alisar_paredes_de_llegada() -> void:
	# Se sustituyen las caras de este tramo, evitando solapar dos colisiones.
	for cs: Node in cargador.get_node("Colisiones").get_children():
		if not cs is CollisionShape3D or not String(cs.name).contains("Roca_inferior"):
			continue
		var original := (cs as CollisionShape3D).shape as ConcavePolygonShape3D
		if original == null:
			continue
		var caras := original.get_faces()
		var limpias := PackedVector3Array()
		for i in range(0, caras.size(), 3):
			var a: Vector3 = cs.global_transform * caras[i]
			var b: Vector3 = cs.global_transform * caras[i + 1]
			var c: Vector3 = cs.global_transform * caras[i + 2]
			var centro := (a + b + c) / 3.0
			if centro.x > 398.5 and centro.x < 407.5 and absf(centro.z) < 3.0:
				continue
			limpias.append_array(PackedVector3Array([caras[i], caras[i + 1], caras[i + 2]]))
		var nueva := ConcavePolygonShape3D.new()
		nueva.set_faces(limpias)
		(cs as CollisionShape3D).shape = nueva
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "ParedesLisasLlegada"
	cuerpo.collision_layer = CAPA_SOLO_JUGADOR
	cuerpo.collision_mask = 0
	add_child(cuerpo)
	var suelo := CollisionShape3D.new()
	var base := BoxShape3D.new()
	base.size = Vector3(9.0, 1.0, 2.4)
	suelo.shape = base
	# La cámara puede pasar sobre las paredes, pero sigue encontrando suelo bajo ella.
	var piso := StaticBody3D.new()
	piso.name = "SueloLisoLlegada"
	piso.collision_layer = 1
	piso.collision_mask = 0
	add_child(piso)
	piso.add_child(suelo)
	suelo.global_position = Vector3(403.0, -0.5, 0.0)
	for lado in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var caja := BoxShape3D.new()
		caja.size = Vector3(9.0, 4.0, 1.0)
		cs.shape = caja
		cuerpo.add_child(cs)
		cs.global_position = Vector3(403.0, 1.5, lado * 1.7)


# --- Consultas que usa Escenas (delegan en el cargador si lo hay) ------------------------------------------

func marcador(nombre: String) -> Marker3D:
	if cargador != null and cargador.has_method("marcador"):
		var m := cargador.call("marcador", nombre) as Marker3D
		if m != null:
			return m
	return find_child(nombre, true, false) as Marker3D


func marcadores_de_tipo(tipo: String) -> Array[Marker3D]:
	if cargador != null and cargador.has_method("marcadores_de_tipo"):
		var r: Array[Marker3D] = []
		for m: Variant in cargador.call("marcadores_de_tipo", tipo):
			r.append(m as Marker3D)
		return r
	return []


func aabb_mapa() -> AABB:
	var nm := get_node_or_null("Objetos/NivelMina")
	var caja := AABB(Vector3(-30, -1, -30), Vector3(60, 12, 60))
	if cargador != null and cargador.has_method("aabb_mapa"):
		caja = cargador.call("aabb_mapa")
	if nm != null and nm.has_method("aabb_nivel"):
		var extr: AABB = nm.call("aabb_nivel")
		if extr.has_volume():
			var nv := int(nm.get("nivel"))
			caja = caja.merge(extr) if nv <= 2 else extr
	return caja


## Giro (radianes alrededor de Y) con el que la cámara de juego mira, según el marcador Camara_juego.
func giro_camara() -> float:
	var m := marcador("Camara_juego")
	if m == null:
		m = marcador("Camara_juego_interior")
	if m == null:
		for c in marcadores_de_tipo("camara"):
			if c.name.begins_with("Camara_juego"):
				m = c
				break
	if m == null:
		return 0.0
	var f := -m.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		return 0.0
	return atan2(-f.x, -f.z)


func _info(metodo: String) -> Dictionary:
	if cargador != null and cargador.has_method(metodo):
		var d: Variant = cargador.call(metodo)
		if d is Dictionary:
			return d
	return {}


# --- Entorno ------------------------------------------------------------------------------------------------------------

func _hay_suelo() -> bool:
	return not find_children("*", "StaticBody3D", true, false).is_empty()


func _suelo_de_emergencia() -> void:
	push_warning("Mapa %s: sin geometría; se pone un suelo de emergencia." % id_mapa)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "SueloEmergencia"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(400, 2, 400)
	forma.shape = caja
	forma.position = Vector3(0, -1, 0)
	cuerpo.add_child(forma)
	var malla := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(400, 400)
	malla.mesh = plano
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.42, 0.27)
	malla.material_override = mat
	cuerpo.add_child(malla)
	add_child(cuerpo)


static func _color(a: Variant, defecto: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		var v: Array = a
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return defecto


func _configurar_entorno() -> void:
	var info_sol := _info("info_sol")
	var info_cielo := _info("info_cielo")
	var info_niebla := _info("info_niebla")

	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.90 if id_mapa == "mina_interior" else (0.92 if interior else 0.96)
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.25
	env.ssao_power = 1.25
	env.ssao_detail = 0.4
	env.glow_enabled = false

	var color_niebla := _color(info_niebla.get("color"), Color(0.72, 0.78, 0.85))
	var densidad: float = clampf(float(info_niebla.get("densidad", 0.0)), 0.0, 0.015)
	var mat_cielo: Material = null
	var fuerza_cielo := 1.0

	if interior:
		if id_mapa != "mina_interior":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.07, 0.055, 0.045)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.80, 0.72, 0.60)
			env.ambient_light_energy = 0.48
			env.fog_enabled = false
		else:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.008, 0.010, 0.016)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.22, 0.23, 0.29)
			env.ambient_light_energy = 0.20
			var ambiente := _info("info_ambiente")
			if not ambiente.is_empty():
				var amb_map := _color(ambiente.get("color"), Color(0.14, 0.13, 0.12)).linear_to_srgb()
				env.ambient_light_color = Color(0.22, 0.23, 0.29).lerp(amb_map, 0.22)
				env.ambient_light_energy = clampf(float(ambiente.get("energia", 0.40)) * 0.45, 0.17, 0.24)
			env.fog_enabled = true
			env.fog_light_color = Color(0.016, 0.019, 0.030)
			env.fog_density = maxf(densidad, 0.016)
	else:
		var cielo := Sky.new()
		fuerza_cielo = float(info_cielo.get("fuerza", 1.0))
		cielo.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		cielo.radiance_size = Sky.RADIANCE_SIZE_128
		env.background_mode = Environment.BG_SKY
		env.sky = cielo
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.85
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_enabled = densidad > 0.0
		env.fog_light_color = color_niebla
		env.fog_density = densidad * 0.78
		env.fog_sky_affect = 0.24
	GraficaH03.preparar_entorno(env, interior, id_mapa == "mina_interior")
	_entorno.environment = env
	_entorno.camera_attributes = GraficaH03.exposicion(interior)
	GraficaH03.ajustar_entorno(_entorno, int(Ajustes.valores.calidad))

	if _sol.has_method("configurar"):
		_sol.call("configurar", info_sol, env, mat_cielo, interior, color_niebla, fuerza_cielo, densidad * 0.78, cargador)


# --- Salidas entre mapas ------------------------------------------------------------------------------------------------

func _crear_salidas() -> void:
	var contenedor := Node3D.new()
	contenedor.name = "Salidas"
	add_child(contenedor)
	var plantilla := load(RUTA_SALIDA) as PackedScene
	if plantilla == null:
		return
	for c in Datos.conexiones_de(id_mapa):
		var pos := Vector3.ZERO
		var m: Marker3D = null
		if c.has("marcador"):
			m = marcador(str(c["marcador"]))
		if m != null:
			pos = m.global_position
		elif c.has("pos"):
			var p: Array = c["pos"]
			pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
		else:
			push_warning("Mapa %s: falta el marcador «%s» de la salida a %s." % [id_mapa, str(c.get("marcador", "?")), str(c.get("destino", "?"))])
			continue
		var s := plantilla.instantiate() as Area3D
		s.set("destino", str(c.get("destino", "")))
		s.set("llegada", str(c.get("llegada", "Spawn_Protagonista")))
		s.set("texto", str(c.get("texto", "")))
		s.set("radio", float(c.get("radio", 2.5)))
		s.name = "Salida_" + str(c.get("destino", ""))
		s.add_to_group("salida")      # el minimapa las marca con una flecha
		contenedor.add_child(s)
		s.global_position = pos
		_salidas.append(s)
	for c in Datos.puertas_de(id_mapa):
		var pos := Vector3.ZERO
		var m: Marker3D = null
		if c.has("marcador"):
			m = marcador(str(c["marcador"]))
		if m != null:
			pos = m.global_position
		elif c.has("pos"):
			var p: Array = c["pos"]
			pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
		else:
			push_warning("Mapa %s: falta el marcador «%s» de la puerta a %s." % [id_mapa, str(c.get("marcador", "?")), str(c.get("destino", "?"))])
			continue
		var puerta := PuertaMapa.new()
		puerta.name = "Puerta_" + str(c.get("destino", ""))
		puerta.destino = str(c.get("destino", ""))
		puerta.llegada = str(c.get("llegada", "Entrada"))
		puerta.texto = str(c.get("texto", ""))
		puerta.verbo = str(c.get("verbo", "Entrar en"))
		puerta.nombre_objeto = str(c.get("nombre_objeto", "la puerta"))
		puerta.radio = float(c.get("radio", 1.35))
		puerta.altura_marca = 2.25
		puerta.nombre_malla = str(c.get("malla", ""))
		if not puerta.nombre_malla.is_empty():
			var mallas := find_children(puerta.nombre_malla + "*", "MeshInstance3D", true, false)
			if not mallas.is_empty():
				puerta.objetivo_resaltado = mallas[0] as Node3D
			else:
				var n_malla := find_child(puerta.nombre_malla + "*", true, false) as Node3D
				if n_malla != null:
					puerta.objetivo_resaltado = n_malla
		contenedor.add_child(puerta)
		puerta.global_position = pos
		puertas.append(puerta)


## Escenas la llama cuando el jugador ya está colocado: las salidas empiezan a vigilar.
func armar_salidas() -> void:
	for s in _salidas:
		if is_instance_valid(s):
			s.call("armar")


# --- Límites del mapa (M1) --------------------------------------------------------------------------------------------------

## ¿Está el punto dentro del área jugable de datos/limites.json? Sin límites definidos, siempre.
func punto_dentro(p: Vector3, holgura: float = 0.0) -> bool:
	if poligono_limites.size() < 3:
		return true
	return LimitesMapa.dentro_poligono(poligono_limites, p, holgura)


## Zona que enseñan el minimapa y el mapa grande (el polígono con un margen).
func rect_mapa() -> Rect2:
	if poligono_limites.size() >= 3:
		return LimitesMapa.rect_poligono(poligono_limites, aabb_mapa())
	return LimitesMapa.rect(id_mapa, aabb_mapa())


## Nombre que sale sobre el minimapa.
func nombre_visible() -> String:
	return LimitesMapa.nombre(id_mapa)


## Muro invisible a lo largo de todo el polígono (una malla de triángulos con colisión por las dos caras, en la capa 6):
## el jugador no puede salir, pero la cámara (que mira la capa 1) lo atraviesa sin chocar.
func _crear_limites() -> void:
	if poligono_limites.size() < 3:
		poligono_limites = LimitesMapa.poligono(id_mapa)
	if poligono_limites.size() < 3:
		return
	var caja := aabb_mapa()
	var y0 := caja.position.y - 8.0
	var y1 := caja.end.y + 30.0
	var caras := PackedVector3Array()
	var n := poligono_limites.size()
	for i in n:
		var a := poligono_limites[i]
		var b := poligono_limites[(i + 1) % n]
		var a0 := Vector3(a.x, y0, a.y)
		var a1 := Vector3(a.x, y1, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var b1 := Vector3(b.x, y1, b.y)
		caras.append_array(PackedVector3Array([a0, b0, b1, a0, b1, a1]))
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(caras)
	var cs := CollisionShape3D.new()
	cs.name = "Forma"
	cs.shape = forma
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Limites"
	cuerpo.collision_layer = CAPA_LIMITES
	cuerpo.collision_mask = 0
	cuerpo.add_child(cs)
	add_child(cuerpo)


## Suelo de la columna (x, z): {"suelo": y del punto más bajo con la cara hacia arriba, "obstaculo": lo que se alza
## por encima (tronco, roca, muro, edificio)}. Los troncos y rocas van sobre el terreno, así que se atraviesan con varios rayos.
func _columna_suelo(x: float, z: float) -> Dictionary:
	var espacio := get_world_3d().direct_space_state
	var caja := aabb_mapa()
	var y := caja.end.y + 30.0
	var y_bajo := caja.position.y - 20.0
	var primero := NAN
	var suelo := NAN
	for _i in 8:
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, y_bajo, z), 1)
		var hit := espacio.intersect_ray(rq)
		if hit.is_empty():
			break
		var p: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if is_nan(primero):
			primero = p.y
		if normal.y > 0.2:
			suelo = p.y
		y = p.y - 0.02
	if is_nan(suelo):
		return {"suelo": NAN, "obstaculo": 99.0}
	return {"suelo": suelo, "obstaculo": maxf(primero - suelo, 0.0)}


func _construir_vallas_y_puntos() -> void:
	for _i in 3:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	_crear_vallas()
	_crear_puntos_interes()
	if not interior:
		RecursosExteriores.preparar(self)
	vallas_listas = true


## Valla de madera (postes y dos travesaños) en los lados abiertos del polígono: se salta donde hay un tronco, una roca o un muro,
## y sigue el relieve. El lado del bosque o de la roca no lleva valla: el bosque ya se ve como límite.
func _crear_vallas() -> void:
	if vallas != null and is_instance_valid(vallas):
		if vallas.get_parent() != null:
			vallas.get_parent().remove_child(vallas)
		vallas.queue_free()
		vallas = null
	if _raiz_reparar != null and is_instance_valid(_raiz_reparar):
		if _raiz_reparar.get_parent() != null:
			_raiz_reparar.get_parent().remove_child(_raiz_reparar)
		_raiz_reparar.queue_free()
		_raiz_reparar = null
	if poligono_limites.size() < 3 or LimitesMapa.tipo_valla(id_mapa) == "ninguna":
		return
	var sin_valla: Array[int] = LimitesMapa.lados_sin_valla(id_mapa)
	var rotas: Array = Juego.cercas_rotas() if id_mapa == "granja" else []
	var huecos_pos: Array[Vector3] = []
	var idx_tramo := 0
	var n := poligono_limites.size()
	var azar := RandomNumberGenerator.new()
	azar.seed = hash(id_mapa)
	var postes: Array[Transform3D] = []
	var colores_postes: Array[Color] = []
	var travesanos: Array[Transform3D] = []
	var colores_travesanos: Array[Color] = []
	for i in n:
		if sin_valla.has(i):
			continue
		var a := poligono_limites[i]
		var b := poligono_limites[(i + 1) % n]
		var largo := a.distance_to(b)
		if largo < 0.5:
			continue
		var d := (b - a) / largo
		var hacia_dentro := Vector2(-d.y, d.x)
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + hacia_dentro * 0.6, poligono_limites):
			hacia_dentro = -hacia_dentro
		var tramos := maxi(int(ceil(largo / SEPARACION_POSTES)), 1)
		var anterior := Vector3(NAN, NAN, NAN)
		for k in tramos + 1:
			var q := a.lerp(b, float(k) / float(tramos)) + hacia_dentro * 0.45
			var col := _columna_suelo(q.x, q.y)
			var y := float(col["suelo"])
			var valido := not is_nan(y) and float(col["obstaculo"]) < 0.45
			var pos := Vector3(q.x, y, q.y)
			if valido:
				var tono := azar.randf_range(0.82, 1.08)
				var tramo_roto := false
				if not is_nan(anterior.y) and absf(pos.y - anterior.y) < 1.2:
					tramo_roto = rotas.has(idx_tramo)
					if tramo_roto:
						huecos_pos.append((anterior + pos) * 0.5)
						# Poste doblado por la tormenta + un listón caído sobre el suelo.
						var eje_x := (pos - anterior).normalized()
						var eje_z := eje_x.cross(Vector3.UP).normalized()
						var b_caido := Basis(eje_x * anterior.distance_to(pos) * 0.85, eje_z, Vector3.UP).rotated(eje_z, 0.18)
						travesanos.append(Transform3D(b_caido, (anterior + pos) * 0.5 + eje_z * 0.28 + Vector3(0, 0.08, 0)))
						colores_travesanos.append(Color(0.30, 0.21, 0.13))
					else:
						for altura in [0.42, 0.92]:
							var p0: Vector3 = anterior + Vector3(0, altura, 0)
							var p1: Vector3 = pos + Vector3(0, altura, 0)
							var eje_x := (p1 - p0).normalized()
							var eje_z := eje_x.cross(Vector3.UP).normalized()
							var eje_y := eje_z.cross(eje_x)
							travesanos.append(Transform3D(Basis(eje_x * p0.distance_to(p1), eje_y, eje_z), (p0 + p1) * 0.5))
							var tono_t := azar.randf_range(0.85, 1.1)
							colores_travesanos.append(Color(0.38 * tono_t, 0.27 * tono_t, 0.17 * tono_t))
					idx_tramo += 1
				var basis_poste := Basis(Vector3.UP, azar.randf_range(-0.3, 0.3))
				var offset_poste := Vector3(0, 0.625, 0)
				if tramo_roto:
					basis_poste = basis_poste.rotated(Vector3(1, 0, 0.4).normalized(), 0.55)
					offset_poste = Vector3(0, 0.46, 0)
				postes.append(Transform3D(basis_poste, pos + offset_poste))
				colores_postes.append(Color(0.34 * tono, 0.23 * tono, 0.14 * tono))
			anterior = pos if valido else Vector3(NAN, NAN, NAN)
	numero_postes = postes.size()
	numero_travesanos = travesanos.size()
	vallas = Node3D.new()
	vallas.name = "Vallas"
	add_child(vallas)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	const NORMAL_VALLAS := "res://assets/texturas/old_planks_02/old_planks_02_normal.png"
	if ResourceLoader.exists(NORMAL_VALLAS):
		mat.normal_enabled = true
		mat.normal_texture = CargadorMapa.obtener_recurso(NORMAL_VALLAS) as Texture2D
		mat.normal_scale = 0.85
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
	_mat_vallas = mat
	_pass_nieve_vallas = null
	if not interior and ResourceLoader.exists("res://shaders/nieve_corteza.gdshader"):
		var np := ShaderMaterial.new()
		np.shader = load("res://shaders/nieve_corteza.gdshader")
		np.set_shader_parameter("umbral", 0.45)
		_pass_nieve_vallas = np
		if Juego.estacion == 3:
			mat.next_pass = np
	_multimalla("Postes", Vector3(0.15, 1.35, 0.15), postes, colores_postes, mat)
	_multimalla("Travesanos", Vector3(1.0, 0.11, 0.07), travesanos, colores_travesanos, mat)
	if not huecos_pos.is_empty():
		_crear_reparador_cercas(huecos_pos[0])


func _crear_reparador_cercas(pos: Vector3) -> void:
	_raiz_reparar = Node3D.new()
	_raiz_reparar.name = "RepararCercas"
	add_child(_raiz_reparar)
	var pto := Interactuable.new()
	pto.name = "Interactuable"
	pto.verbo = "Reparar"
	pto.nombre_objeto = "las cercas (2 de madera)"
	pto.radio = 2.0
	pto.altura_marca = 1.6
	pto.usado.connect(func(_j: Node3D) -> void:
		if Juego.reparar_cercas():
			_crear_vallas())
	_raiz_reparar.add_child(pto)
	pto.global_position = pos + Vector3(0, 0.1, 0)


func _multimalla(nombre: String, tam: Vector3, transformaciones: Array[Transform3D], colores: Array[Color], mat: Material) -> void:
	if transformaciones.is_empty():
		return
	var malla := BoxMesh.new()
	malla.size = tam
	malla.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = malla
	mm.instance_count = transformaciones.size()
	for i in transformaciones.size():
		mm.set_instance_transform(i, transformaciones[i])
		mm.set_instance_color(i, colores[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nombre
	mmi.multimesh = mm
	vallas.add_child(mmi)


# --- Interactuables de ejemplo (M1) -------------------------------------------------------------------------------------------

## Carteles, silo, barriles, raíles... de datos/puntos_interes.json (por mapa). Cada entrada: id, verbo, objeto, titulo, texto,
## y la posición como `marcador` (de marcadores.json) o `pos` [x, z]; opcionales: radio, altura, poste (dibuja un cartel de madera)
## y giro (grados) del cartel. El pozo, el tablón y los vecinos del pueblo son de L4b y no salen aquí.
func _crear_puntos_interes() -> void:
	if not FileAccess.file_exists(RUTA_PUNTOS):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(RUTA_PUNTOS)) != OK or not (json.data is Dictionary):
		push_warning("Mapa %s: %s mal formado." % [id_mapa, RUTA_PUNTOS])
		return
	var lista: Array = (json.data as Dictionary).get(id_mapa, [])
	for v: Variant in lista:
		var e: Dictionary = v
		var xz := Vector2.ZERO
		if e.has("marcador"):
			var m := marcador(str(e["marcador"]))
			if m == null:
				push_warning("Mapa %s: falta el marcador «%s» del punto de interés." % [id_mapa, str(e["marcador"])])
				continue
			xz = Vector2(m.global_position.x, m.global_position.z)
		elif e.has("pos"):
			var p: Array = e["pos"]
			xz = Vector2(float(p[0]), float(p[1]))
		else:
			continue
		var y := float(_columna_suelo(xz.x, xz.y)["suelo"])
		if is_nan(y):
			y = 0.0
		var c := Interactuable.new()
		c.name = "Punto_" + str(e.get("id", "sin_id"))
		c.verbo = str(e.get("verbo", "Examinar"))
		c.nombre_objeto = str(e.get("objeto", ""))
		c.descripcion = str(e.get("texto", ""))
		c.titulo_dialogo = str(e.get("titulo", ""))
		c.radio = float(e.get("radio", 0.8))
		c.altura_marca = float(e.get("altura", 1.5))
		objetos.add_child(c)
		c.global_position = Vector3(xz.x, y, xz.y)
		if bool(e.get("poste", false)):
			_poste_de_cartel(c, float(e.get("giro", 0.0)))
		puntos_interes.append(c)


## Poste con una tabla de madera, para los carteles que el mapa no trae dibujados.
func _poste_de_cartel(c: Interactuable, giro_grados: float) -> void:
	var raiz := Node3D.new()
	raiz.name = "CartelMadera"
	raiz.rotation_degrees.y = giro_grados
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.32, 0.2)
	mat.roughness = 0.95
	var poste := MeshInstance3D.new()
	var m_poste := BoxMesh.new()
	m_poste.size = Vector3(0.13, 1.7, 0.13)
	poste.mesh = m_poste
	poste.material_override = mat
	poste.position = Vector3(0, 0.85 - 0.05, 0)
	raiz.add_child(poste)
	var tabla := MeshInstance3D.new()
	var m_tabla := BoxMesh.new()
	m_tabla.size = Vector3(0.95, 0.4, 0.06)
	tabla.mesh = m_tabla
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.62, 0.47, 0.3)
	mat2.roughness = 0.9
	tabla.material_override = mat2
	tabla.position = Vector3(0.12, 1.45, 0.0)
	raiz.add_child(tabla)
	c.add_child(raiz)


# --- Lluvia, tormenta, nieve y mercader ---------------------------------------------------------------------

func _al_mapa_cargado(id: String) -> void:
	if id != id_mapa:
		return
	_actualizar_precipitacion()
	_actualizar_comerciante()


func _al_cambio_clima(_nuevo: String) -> void:
	_actualizar_precipitacion()


func _al_evento_cambiado() -> void:
	if not esta_listo:
		return
	if id_mapa == "granja" and vallas_listas:
		_crear_vallas()
	if id_mapa == "pueblo":
		_actualizar_comerciante()
	_actualizar_precipitacion()


func _actualizar_precipitacion() -> void:
	if _mat_vallas != null and is_instance_valid(_mat_vallas):
		_mat_vallas.next_pass = _pass_nieve_vallas if (Juego.estacion == 3 and not interior) else null
	if _mat_toldo != null and is_instance_valid(_mat_toldo):
		_mat_toldo.next_pass = _pass_nieve_toldo if Juego.estacion == 3 else null
	if interior:
		return
	var debe_llover := Juego.esta_lloviendo()
	var tormenta := Juego.clima == "tormenta"
	_ajustar_relampagos(tormenta)
	if debe_llover and (_lluvia == null or not is_instance_valid(_lluvia) or _es_tormenta_lluvia != tormenta):
		if _lluvia != null and is_instance_valid(_lluvia):
			if _lluvia.get_parent() != null:
				_lluvia.get_parent().remove_child(_lluvia)
			_lluvia.queue_free()
			_lluvia = null
		_crear_lluvia(tormenta)
	elif not debe_llover and _lluvia != null and is_instance_valid(_lluvia):
		if _lluvia.get_parent() != null:
			_lluvia.get_parent().remove_child(_lluvia)
		_lluvia.queue_free()
		_lluvia = null
		_salpicaduras = null

	var debe_nevar := Juego.esta_nevando()
	if debe_nevar and (_nieve == null or not is_instance_valid(_nieve)):
		_crear_nieve()
	elif not debe_nevar and _nieve != null and is_instance_valid(_nieve):
		if _nieve.get_parent() != null:
			_nieve.get_parent().remove_child(_nieve)
		_nieve.queue_free()
		_nieve = null
	set_process((_lluvia != null and is_instance_valid(_lluvia)) or (_nieve != null and is_instance_valid(_nieve)))


func _ajustar_relampagos(tormenta: bool) -> void:
	if tormenta and _relampago == null:
		_relampago = DirectionalLight3D.new()
		_relampago.name = "Relampago"
		_relampago.rotation_degrees = Vector3(-48, -66, 0)
		_relampago.light_color = Color(0.78, 0.86, 1.0)
		_relampago.light_energy = 0.0
		_relampago.light_volumetric_fog_energy = 0.48
		_relampago.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		add_child(_relampago)
		_espera_relampago = randf_range(6.5, 14.0)
		_fase_relampago = 0.0
	elif not tormenta and _relampago != null:
		_relampago.queue_free()
		_relampago = null


func _actualizar_relampago(delta: float) -> void:
	if _relampago == null:
		return
	_espera_relampago -= delta
	if _espera_relampago <= 0.0:
		_fase_relampago = 0.25
		_espera_relampago = randf_range(16.0, 38.0)
		_relampago.rotation_degrees.y = randf_range(-180.0, 180.0)
	var t := 0.25 - _fase_relampago
	_relampago.light_energy = 0.78 * exp(-t * 37.0) + 0.24 * exp(-absf(t - 0.093) * 50.0) if _fase_relampago > 0.0 else 0.0
	_fase_relampago = maxf(0.0, _fase_relampago - delta)


func _crear_lluvia(tormenta: bool = false) -> void:
	_es_tormenta_lluvia = tormenta
	var cal := clampi(int(Ajustes.valores.calidad), 0, 3)
	var p := GPUParticles3D.new()
	p.name = "Lluvia"
	p.amount = [1800, 2600, 3400, 4600][cal] if tormenta else [1200, 1800, 2400, 3000][cal]
	p.lifetime = 0.85 if tormenta else 1.0
	p.preprocess = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(18, 0.1, 18)
	proc.direction = Vector3(0.28, -1, 0.12) if tormenta else Vector3(0.12, -1, 0.05)
	proc.spread = 4.0 if tormenta else 2.0
	proc.initial_velocity_min = 27.0 if tormenta else 22.0
	proc.initial_velocity_max = 33.0 if tormenta else 26.0
	proc.gravity = Vector3.ZERO
	p.process_material = proc
	var malla := QuadMesh.new()
	malla.size = Vector2(0.018, 0.58) if tormenta else Vector2(0.014, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.66, 0.75, 0.88, 0.58) if tormenta else Color(0.75, 0.82, 0.92, 0.45)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	# Las gotas cercanas a la cámara (a 12 m del jugador) se desvanecen: de otro modo parecen barras gruesas.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 5.0
	mat.distance_fade_max_distance = 9.0
	malla.material = mat
	p.draw_pass_1 = malla
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_lluvia = p
	_crear_salpicaduras()


func _crear_salpicaduras() -> void:
	var gotas := GPUParticles3D.new()
	gotas.name = "Salpicaduras"
	gotas.amount = 96
	gotas.lifetime = 0.22
	gotas.local_coords = false
	gotas.emitting = false
	gotas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gotas.visibility_aabb = AABB(Vector3(-9, -5, -9), Vector3(18, 10, 18))
	var movimiento := ParticleProcessMaterial.new()
	movimiento.gravity = Vector3(0, -9.8, 0)
	gotas.process_material = movimiento

	var color := Gradient.new()
	color.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	color.colors = PackedColorArray([
		Color(0.82, 0.88, 0.91, 0.72), Color(0.67, 0.75, 0.81, 0.35), Color(0.67, 0.75, 0.81, 0.0),
	])
	var textura := GradientTexture2D.new()
	textura.width = 16
	textura.height = 16
	textura.fill = GradientTexture2D.FILL_RADIAL
	textura.fill_from = Vector2(0.5, 0.5)
	textura.fill_to = Vector2(1, 0.5)
	textura.gradient = color
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = textura
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var malla := QuadMesh.new()
	malla.size = Vector2(0.022, 0.024)
	malla.material = material
	gotas.draw_pass_1 = malla
	_lluvia.add_child(gotas)
	_salpicaduras = gotas


func _salpicar_suelo(delta: float, centro: Vector3) -> void:
	_salpicaduras.global_position = centro
	_espera_salpicadura -= delta
	if _espera_salpicadura > 0.0 or int(Ajustes.valores.calidad) < 2:
		return
	_espera_salpicadura = 0.024 if _es_tormenta_lluvia else 0.045
	var lado := Vector2.from_angle(_azar_lluvia.randf_range(0.0, TAU)) * _azar_lluvia.randf_range(1.0, 6.5)
	var punto := centro + Vector3(lado.x, 0.0, lado.y)
	var rayo := PhysicsRayQueryParameters3D.create(punto + Vector3.UP * 2.5, punto + Vector3.DOWN * 4.0, 1)
	var choque := get_world_3d().direct_space_state.intersect_ray(rayo)
	if choque.is_empty() or choque.normal.y < 0.4:
		return
	var contacto: Vector3 = choque.position + choque.normal * 0.018
	var flags := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
	for _gota in 3:
		var salto := Vector3(
			_azar_lluvia.randf_range(-0.7, 0.7), _azar_lluvia.randf_range(0.55, 1.05), _azar_lluvia.randf_range(-0.7, 0.7),
		)
		_salpicaduras.emit_particle(Transform3D(Basis.IDENTITY, contacto), salto, Color.WHITE, Color(0, 0, 0, 0), flags)


func _crear_nieve() -> void:
	var cal := clampi(int(Ajustes.valores.calidad), 0, 3)
	var p := GPUParticles3D.new()
	p.name = "Nieve"
	p.amount = [700, 1100, 1400, 1800][cal]
	p.lifetime = 4.2
	p.preprocess = 2.5
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-34, -18, -34), Vector3(68, 36, 68))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(20, 1.0, 20)
	proc.direction = Vector3(0.18, -1.0, 0.08)
	proc.spread = 16.0
	proc.initial_velocity_min = 2.2
	proc.initial_velocity_max = 3.8
	proc.gravity = Vector3(0.22, -0.35, 0.08)
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.75
	proc.scale_min = 0.65
	proc.scale_max = 1.35
	p.process_material = proc
	var gtex := GradientTexture2D.new()
	gtex.width = 24
	gtex.height = 24
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.95), Color(0.95, 0.98, 1.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	gtex.gradient = grad
	var malla := QuadMesh.new()
	malla.size = Vector2(0.11, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = gtex
	mat.albedo_color = Color(0.96, 0.98, 1.0, 0.9)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 2.0
	mat.distance_fade_max_distance = 4.5
	malla.material = mat
	p.draw_pass_1 = malla
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_nieve = p


func _actualizar_comerciante() -> void:
	if id_mapa != "pueblo":
		return
	var activo := Juego.hay_comerciante()
	if not activo:
		if _mercader != null and is_instance_valid(_mercader):
			if _mercader.get_parent() != null:
				_mercader.get_parent().remove_child(_mercader)
			_mercader.queue_free()
			_mercader = null
		return
	if _mercader != null and is_instance_valid(_mercader):
		return
	var raiz := Node3D.new()
	raiz.name = "MercaderAmbulante"
	objetos.add_child(raiz)
	var base := _sitio_libre_mercader()
	raiz.global_position = base
	raiz.look_at(Vector3(0, base.y, 0), Vector3.UP, true)

	# Puesto artesanal de madera envejecida, toldo invernal cubrible por nieve y mercancía variada.
	var madera_osc := Color(0.32, 0.21, 0.13)
	var madera_clara := Color(0.45, 0.31, 0.19)
	AyudasL4b.caja(raiz, Vector3(2.1, 0.80, 0.82), Vector3(0, 0.40, 0), madera_osc, true)
	AyudasL4b.caja(raiz, Vector3(2.24, 0.08, 0.98), Vector3(0, 0.84, 0), madera_clara, true)
	AyudasL4b.caja(raiz, Vector3(0.11, 2.28, 0.11), Vector3(-0.98, 1.14, -0.36), madera_osc, true)
	AyudasL4b.caja(raiz, Vector3(0.11, 2.28, 0.11), Vector3(0.98, 1.14, -0.36), madera_osc, true)
	AyudasL4b.caja(raiz, Vector3(0.10, 2.16, 0.10), Vector3(-0.98, 1.08, 0.36), madera_osc, false)
	AyudasL4b.caja(raiz, Vector3(0.10, 2.16, 0.10), Vector3(0.98, 1.08, 0.36), madera_osc, false)
	AyudasL4b.caja(raiz, Vector3(2.08, 0.10, 0.10), Vector3(0, 2.18, 0.36), madera_osc, false)

	var toldo := MeshInstance3D.new()
	var m_toldo := BoxMesh.new()
	m_toldo.size = Vector3(2.36, 0.09, 1.48)
	var mat_toldo := StandardMaterial3D.new()
	mat_toldo.albedo_color = Color(0.46, 0.15, 0.13)
	mat_toldo.roughness = 0.92
	_mat_toldo = mat_toldo
	_pass_nieve_toldo = null
	if ResourceLoader.exists("res://shaders/nieve_corteza.gdshader"):
		var np_t := ShaderMaterial.new()
		np_t.shader = load("res://shaders/nieve_corteza.gdshader")
		np_t.set_shader_parameter("umbral", 0.42)
		_pass_nieve_toldo = np_t
		if Juego.estacion == 3:
			mat_toldo.next_pass = np_t
	m_toldo.material = mat_toldo
	toldo.mesh = m_toldo
	toldo.position = Vector3(0, 2.26, 0.04)
	toldo.rotation_degrees.x = 6.0
	raiz.add_child(toldo)

	# Cajón de madera, fardo de tela, tarros de boticario y farol cálido sobre el mostrador.
	AyudasL4b.caja(raiz, Vector3(0.44, 0.24, 0.34), Vector3(-0.66, 1.00, 0.02), Color(0.39, 0.26, 0.15))
	AyudasL4b.caja(raiz, Vector3(0.36, 0.18, 0.28), Vector3(-0.66, 1.19, 0.02), Color(0.64, 0.56, 0.42))
	AyudasL4b.caja(raiz, Vector3(0.30, 0.22, 0.26), Vector3(0.64, 0.99, -0.02), Color(0.48, 0.36, 0.22))
	var frasco_ambar := MeshInstance3D.new()
	var c_ambar := CylinderMesh.new()
	c_ambar.top_radius = 0.055
	c_ambar.bottom_radius = 0.075
	c_ambar.height = 0.20
	var mat_ambar := StandardMaterial3D.new()
	mat_ambar.albedo_color = Color(0.68, 0.44, 0.14)
	mat_ambar.roughness = 0.25
	mat_ambar.metallic = 0.15
	c_ambar.material = mat_ambar
	frasco_ambar.mesh = c_ambar
	frasco_ambar.position = Vector3(0.14, 0.98, 0.04)
	raiz.add_child(frasco_ambar)
	var elixir_m := MeshInstance3D.new()
	var c_elix := CylinderMesh.new()
	c_elix.top_radius = 0.045
	c_elix.bottom_radius = 0.065
	c_elix.height = 0.24
	var mat_elix := StandardMaterial3D.new()
	mat_elix.albedo_color = Color(0.22, 0.48, 0.36)
	mat_elix.roughness = 0.2
	mat_elix.emission_enabled = true
	mat_elix.emission = Color(0.22, 0.46, 0.30)
	mat_elix.emission_energy_multiplier = 0.35
	c_elix.material = mat_elix
	elixir_m.mesh = c_elix
	elixir_m.position = Vector3(-0.04, 1.00, 0.12)
	raiz.add_child(elixir_m)

	var npc_script := load("res://scripts/pueblo/npc.gd")
	if npc_script != null and npc_script.has_method("crear"):
		var npc_nodo: Node3D = npc_script.crear({
			"id": "mercader_ambulante",
			"nombre": "Mercader ambulante",
			"modelo": "alcalde",
			"radio": 0.0,
			"tinte": {"pelo": "#4b301b", "ropa": "#264e70"},
			"sombrero": "boina",
		})
		raiz.add_child(npc_nodo)
		npc_nodo.position = Vector3(0, 0.02, -0.78)
		npc_nodo.set("_giro", 0.0)
		var mod_npc := npc_nodo.get_node_or_null("Modelo") as Node3D
		if mod_npc != null:
			mod_npc.rotation.y = 0.0
		var hablar := npc_nodo.get_node_or_null("Hablar")
		if hablar != null:
			hablar.queue_free()

	var pto := Interactuable.new()
	pto.name = "Comerciar"
	pto.verbo = "Comerciar con"
	pto.nombre_objeto = "el mercader ambulante"
	pto.mostrar_nombre = true
	pto.radio = 1.9
	pto.altura_marca = 2.15
	pto.position = Vector3(0, 0.1, 0.72)
	pto.usado.connect(func(_j: Node3D) -> void:
		Interfaz.abrir_tienda("comerciante_ambulante"))
	raiz.add_child(pto)
	_mercader = raiz


func _sitio_libre_mercader() -> Vector3:
	for cand: Vector2 in [Vector2(4.2, -3.5), Vector2(4.6, 3.6), Vector2(-4.4, -3.8), Vector2(5.4, -2.0)]:
		var col := _columna_suelo(cand.x, cand.y)
		var y := float(col["suelo"])
		if not is_nan(y) and float(col["obstaculo"]) < 0.35:
			return Vector3(cand.x, y, cand.y)
	var base := _columna_suelo(4.0, -3.2)
	var yb := float(base["suelo"]) if not is_nan(float(base["suelo"])) else 0.0
	return Vector3(4.0, yb, -3.2)


func _centro_precipitacion() -> Vector3:
	var j := Escenas.jugador()
	var cam := get_viewport().get_camera_3d()
	if j != null and cam != null:
		if cam.global_position.distance_to(j.global_position) > 22.0:
			return cam.global_position + (-cam.global_basis.z * 11.0)
	if j != null:
		return j.global_position
	if cam != null:
		return cam.global_position + (-cam.global_basis.z * 11.0)
	return Vector3.ZERO


func _process(delta: float) -> void:
	if _relampago != null:
		_actualizar_relampago(delta)
	var hay_lluvia := _lluvia != null and is_instance_valid(_lluvia)
	var hay_nieve := _nieve != null and is_instance_valid(_nieve)
	if not hay_lluvia and not hay_nieve:
		return
	var centro := _centro_precipitacion()
	if hay_lluvia:
		_lluvia.global_position = centro + Vector3(0, 13, 0)
		_salpicar_suelo(delta, centro)
	if hay_nieve:
		_nieve.global_position = centro + Vector3(0, 10, 0)
