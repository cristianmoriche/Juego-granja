extends Node
## Cambios de escena y de mapa: fundido a negro, carga, colocación del jugador. Autoload «Escenas».

signal mapa_cargado(id_mapa: String)

const RUTA_MAPA := "res://escenas/mapas/%s.tscn"
const RUTA_JUGADOR := "res://escenas/jugador/jugador.tscn"
const ESCENA_MENU := "res://escenas/menu_principal.tscn"
const ESCENA_INTRO := "res://escenas/intro.tscn"
const ESCENA_FINAL := "res://escenas/final.tscn"
const ESPERA_MAXIMA_MAPA := 40.0     # segundos antes de dar por perdido un mapa que no avisa de que está listo

## Hay un cambio de mapa o escena en marcha (el reloj y el jugador se paran).
var en_transicion: bool = false

## Mapa y marcador donde se despierta tras dormir o desmayarse (las pruebas lo cambian).
var mapa_de_despertar: String = "granja"
var marcador_de_despertar: String = "Spawn_Protagonista"

var _fin_solicitado: bool = false


func _ready() -> void:
	Juego.fin_de_anio.connect(_al_fin_de_anio)


func jugador() -> Node3D:
	var n := get_tree().get_first_node_in_group("jugador")
	return n as Node3D if is_instance_valid(n) else null


## Nodo raíz del mapa en el que se está jugando (null en menús).
func mapa_actual_nodo() -> Node3D:
	var e := get_tree().current_scene
	if e is Node3D and e.is_in_group("mapa"):
		return e as Node3D
	return null


# --- Cambio de escena (menús, intro, final) ---------------------------------------------

func ir_a_escena(ruta: String) -> void:
	if en_transicion:
		return
	en_transicion = true
	await _ir_a_escena_interno(ruta)
	en_transicion = false


func _ir_a_escena_interno(ruta: String) -> void:
	if not ResourceLoader.exists(ruta):
		push_error("Escenas: no existe %s" % ruta)
		return
	await Interfaz.fundido_a_negro(0.3)
	Interfaz.mostrar_hud(false)
	Interfaz.cerrar_todo()
	await _quitar_escena_actual()
	var nueva := (load(ruta) as PackedScene).instantiate()
	get_tree().root.add_child(nueva)
	get_tree().current_scene = nueva
	await get_tree().process_frame
	await Interfaz.fundido_desde_negro(0.3)


func _quitar_escena_actual() -> void:
	var actual := get_tree().current_scene
	if actual == null or not is_instance_valid(actual):
		return
	get_tree().current_scene = null
	actual.queue_free()
	if actual.is_inside_tree():
		await actual.tree_exited


# --- Cambio de mapa -------------------------------------------------------------------------

## Fundido a negro, carga del mapa, colocación del jugador en el marcador (si no existe:
## Spawn_Protagonista; si tampoco, el centro del mapa) y fundido de vuelta.
func ir_a_mapa(id_mapa: String, marcador: String = "Spawn_Protagonista") -> void:
	if en_transicion:
		return
	en_transicion = true
	await _ir_a_mapa_interno(id_mapa, marcador, Vector3.INF)
	en_transicion = false


## Empieza a cargar en segundo plano los recursos del mapa antes del fundido o en momentos de espera.
func precargar_mapa(id_mapa: String) -> void:
	if id_mapa.is_empty():
		return
	if id_mapa in CargadorMapa.MAPAS_EXTERIORES:
		var estacion := clampi(Juego.estacion, 0, 3)
		CieloH03.solicitar_hora(Juego.minutos, CicloDia.AMANECER[estacion], CicloDia.ATARDECER[estacion])
	var rutas: PackedStringArray = PackedStringArray([RUTA_MAPA % id_mapa, RUTA_JUGADOR])
	rutas.append_array(CargadorMapa.rutas_mapa(id_mapa))
	var v := get_node_or_null("/root/Vecinos")
	if v != null and v.has_method("rutas_mapa"):
		rutas.append_array(v.call("rutas_mapa", id_mapa) as PackedStringArray)
	var r_mus := Audio.ruta_musica_mapa(id_mapa)
	if not r_mus.is_empty():
		rutas.append(r_mus)
	var r_amb := Audio.ruta_ambiente_mapa(id_mapa)
	if not r_amb.is_empty():
		rutas.append(r_amb)
	CargadorMapa.solicitar_lote(rutas)


func _ir_a_mapa_interno(id_mapa: String, marcador: String, posicion: Vector3) -> void:
	var ruta := RUTA_MAPA % id_mapa
	if not ResourceLoader.exists(ruta):
		push_error("Escenas: no existe el mapa %s" % ruta)
		Interfaz.mensaje("Ese camino todavía no lleva a ninguna parte.")
		return
	precargar_mapa(id_mapa)
	await Interfaz.fundido_a_negro(0.18)
	Interfaz.mostrar_carga(true)
	Interfaz.cerrar_todo()
	# Un fotograma para mostrar «Cargando…» mientras terminan los hilos de carga.
	await get_tree().process_frame
	await _quitar_escena_actual()

	var mapa := (CargadorMapa.obtener_recurso(ruta) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(mapa)
	get_tree().current_scene = mapa
	if not bool(mapa.get("esta_listo")):
		await _esperar_mapa(mapa)

	Juego.mapa_actual = id_mapa
	Juego.registrar_zona_visitada(id_mapa)
	var j := (CargadorMapa.obtener_recurso(RUTA_JUGADOR) as PackedScene).instantiate() as Node3D
	j.process_mode = Node.PROCESS_MODE_DISABLED   # quieto hasta estar colocado y con suelo debajo
	mapa.add_child(j)
	await _colocar_jugador(j, mapa, marcador, posicion)
	j.process_mode = Node.PROCESS_MODE_INHERIT
	if j.has_method("activar"):
		j.call("activar")
	Interfaz.mostrar_hud(true)
	mapa_cargado.emit(id_mapa)
	if mapa.has_method("armar_salidas"):
		mapa.call("armar_salidas")
	Interfaz.mostrar_carga(false)
	await Interfaz.fundido_desde_negro(0.20)


func _esperar_mapa(mapa: Node3D) -> void:
	var limite := Time.get_ticks_msec() + int(ESPERA_MAXIMA_MAPA * 1000.0)
	while is_instance_valid(mapa) and not bool(mapa.get("esta_listo")) and Time.get_ticks_msec() < limite:
		await get_tree().process_frame
	if not bool(mapa.get("esta_listo")):
		push_warning("Escenas: el mapa tardó demasiado en cargar; se continúa igualmente.")


func _colocar_jugador(j: Node3D, mapa: Node3D, nombre_marcador: String, posicion_fija: Vector3) -> void:
	var pos := Vector3.ZERO
	var giro := NAN
	var tiene_pos := false
	if posicion_fija != Vector3.INF:
		pos = posicion_fija
		tiene_pos = true
	else:
		var m: Marker3D = null
		if mapa.has_method("marcador"):
			m = mapa.call("marcador", nombre_marcador) as Marker3D
			if m == null and nombre_marcador != "Spawn_Protagonista":
				m = mapa.call("marcador", "Spawn_Protagonista") as Marker3D
		if m != null:
			pos = m.global_position
			var frente := m.global_basis.z.slide(Vector3.UP)
			if frente.length_squared() > 0.001:
				giro = atan2(frente.x, frente.z)
			tiene_pos = true
	# Los colliders recién creados no cuentan hasta el siguiente fotograma de física.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var espacio := j.get_world_3d().direct_space_state
	if not tiene_pos:
		var caja := AABB(Vector3(-20, -1, -20), Vector3(40, 12, 40))
		if mapa.has_method("aabb_mapa"):
			caja = mapa.call("aabb_mapa")
		pos = caja.get_center()
		pos.y = caja.end.y + 2.0
	# Se baja hasta el suelo con un rayo (capa 1 = mundo).
	var arriba := pos + Vector3(0, 1.5 if tiene_pos else 0.0, 0)
	var abajo := pos + Vector3(0, -8.0 if tiene_pos else -200.0, 0)
	var rq := PhysicsRayQueryParameters3D.create(arriba, abajo, 1)
	var hit := espacio.intersect_ray(rq)
	if not hit.is_empty():
		pos = hit["position"]
	elif not tiene_pos:
		pos.y = 1.0
	# En una entrada orientada, mira hacia el interior. En otros puntos, ajusta el giro si hay una pared enfrente.
	var giro_camara := 0.0
	if mapa.has_method("giro_camara"):
		giro_camara = float(mapa.call("giro_camara"))
	if not is_nan(giro):
		giro_camara = wrapf(giro + PI, -PI, PI)
		if str(mapa.get("id_mapa")) == "mina_interior":
			giro_camara = _rumbo_despejado(espacio, pos, giro_camara, PI * 0.25)
	else:
		giro_camara = _rumbo_despejado(espacio, pos, giro_camara)
	if j.has_method("colocar"):
		j.call("colocar", pos + Vector3(0, 0.05, 0), giro, giro_camara)
	else:
		j.global_position = pos
	if j.has_method("configurar_para_mapa"):
		j.call("configurar_para_mapa", mapa)


func _rumbo_despejado(espacio: PhysicsDirectSpaceState3D, pos: Vector3, inicial: float, limite: float = PI) -> float:
	var origen := pos + Vector3.UP * 1.60
	var consulta := PhysicsRayQueryParameters3D.create(origen, origen, 1 | 64 | 128)
	consulta.hit_from_inside = true
	var rumbo := inicial
	var mejor := 0.0
	for giro in [0.0, PI * 0.125, -PI * 0.125, PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI]:
		if absf(giro) > limite:
			continue
		var angulo := inicial + float(giro)
		consulta.to = origen + Vector3.FORWARD.rotated(Vector3.UP, angulo) * 3.0
		var pared := espacio.intersect_ray(consulta)
		var metros := 3.0 if pared.is_empty() else origen.distance_to(pared.position)
		if is_zero_approx(giro) and metros >= 1.35:
			return inicial
		var puntos := metros - absf(giro) * 0.15
		if puntos > mejor:
			mejor = puntos
			rumbo = angulo
	return wrapf(rumbo, -PI, PI)


## Continúa la partida guardada: carga el estado y entra en el mapa donde se guardó.
func continuar_partida() -> void:
	if en_transicion:
		return
	if not Juego.cargar():
		Interfaz.mensaje(Juego.ultimo_error_carga if not Juego.ultimo_error_carga.is_empty() else "No hay ninguna partida guardada.")
		return
	if bool(Juego.banderas.get("fin_anio", false)):
		await ir_a_escena(ESCENA_FINAL)
		return
	en_transicion = true
	var id := Juego.mapa_actual if not Juego.mapa_actual.is_empty() else "granja"
	var posicion := Vector3.INF
	if Juego.posicion_guardada.size() == 3:
		posicion = Vector3(float(Juego.posicion_guardada[0]), float(Juego.posicion_guardada[1]), float(Juego.posicion_guardada[2]))
	Juego.posicion_guardada = []
	await _ir_a_mapa_interno(id, "Spawn_Protagonista", posicion)
	en_transicion = false


# --- Dormir y fin de año ------------------------------------------------------------------

## Fundido a negro, cierra el día y despierta en la granja (o va al final si acaba el año).
func secuencia_dormir(desmayo: bool, por_heridas: bool = false) -> void:
	if en_transicion:
		# Ya hay un cambio en curso: se cierra el día sin más y la próxima carga reflejará la fecha nueva.
		Juego.terminar_dia(desmayo)
		return
	en_transicion = true
	_fin_solicitado = false
	var leo := jugador()
	if por_heridas and leo != null:
		leo.call("caer_desmayado")
		await get_tree().create_timer(0.68).timeout
	await Interfaz.fundido_a_negro(0.6)
	var sigue := Juego.terminar_dia(desmayo, false)
	if sigue:
		var mapa := "casa_leo" if por_heridas else mapa_de_despertar
		var marcador := "Spawn_Protagonista" if por_heridas else marcador_de_despertar
		await _ir_a_mapa_interno(mapa, marcador, Vector3.INF)
		# El autoguardado debe conservar el mapa y la posición donde Leo despierta.
		Juego.guardar()
		if desmayo:
			Interfaz.mensaje("Despiertas en casa, con la cabeza pesada. Un nuevo día en El Granado.")
		elif not Juego.aviso_evento_hoy().is_empty():
			Interfaz.mensaje("%s · %s" % [Juego.texto_fecha(), Juego.aviso_evento_hoy()])
		else:
			Interfaz.mensaje("Has dormido bien. %s." % Juego.texto_fecha())
	elif _fin_solicitado:
		await _ir_a_escena_interno(ESCENA_FINAL)
	en_transicion = false
	_fin_solicitado = false


func _al_fin_de_anio() -> void:
	if en_transicion:
		_fin_solicitado = true
	else:
		ir_a_escena(ESCENA_FINAL)


## Vuelve al menú principal (sin guardar) y limpia cachés pesadas de partida.
func ir_al_menu() -> void:
	Juego.partida_activa = false
	FotoCenital.olvidar()
	Interfaz.limpiar_estado_menu()
	preload("res://scripts/jugador/vista_leo.gd").olvidar()
	preload("res://scripts/mina/generador_caverna_h04.gd").limpiar_cache()
	await ir_a_escena(ESCENA_MENU)
	CargadorMapa.limpiar_cache_menu()
	Audio.limpiar_cache_inactiva()
