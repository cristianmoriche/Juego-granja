extends Node
## Repite encuadres desde los ojos de Leo y mide tiempos de fotograma en Vulkan.

const MAPAS := ["granja", "pueblo", "bosque_norte", "costa_lago", "mina_exterior", "mina_interior", "casa_leo"]
const MEDIR := ["granja", "pueblo", "mina_interior"]
const MINUTOS := [480, 840, 1200, 1380]
const CLIMAS := ["sol", "lluvia", "niebla"]
const FOTOGRAMAS := 300
var _salida: String
var _medidas := PackedStringArray()
var _fallos := 0


func _ready() -> void:
	get_tree().create_timer(650.0).timeout.connect(func() -> void: get_tree().quit(2))
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	var fase := "antes" if OS.get_environment("H03_FASE") == "antes" else "despues"
	var solo := OS.get_environment("H03_MAPA")
	var solo_medidas := OS.get_environment("H03_MEDIR") == "1"
	var muestra := OS.get_environment("H03_MUESTRA") == "1"
	if muestra and solo.is_empty():
		solo = "granja"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/H03-graficos-hiperrealistas/" + ("muestra" if muestra else fase))
	DirAccess.make_dir_recursive_absolute(_salida)
	Ajustes.ruta = "user://ajustes_capturas_h03.cfg"
	Juego.ruta_partida = "user://partida_capturas_h03.json"
	Ajustes.poner("vista", 0)
	Ajustes.poner("fov", 80)
	Ajustes.poner("calidad", 2)
	Ajustes.poner("pantalla_completa", false)
	Ajustes.poner("resolucion", 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.estacion = 0
	get_tree().current_scene = null
	for id: String in MAPAS:
		if (not solo.is_empty() and id != solo) or (solo_medidas and id not in MEDIR):
			continue
		_cambiar(840, "sol")
		var inicio := Time.get_ticks_msec()
		await Escenas.ir_a_mapa(id, "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista")
		var carga := Time.get_ticks_msec() - inicio
		var leo := Escenas.jugador() as Jugador
		var mapa := Escenas.mapa_actual_nodo() as Mapa
		if leo == null or mapa == null:
			_fallos += 1
			continue
		leo.set_physics_process(false)
		_encuadrar(id, leo, mapa)
		var interfaz := get_tree().root.get_node_or_null("Interfaz") as CanvasLayer
		if interfaz != null:
			interfaz.hide()
		if muestra:
			print("%s · carga de geometría e instancias: %d ms" % [id, mapa.cargador.tiempo_carga_ms])
			if id == "costa_lago":
				_cambiar(1380, "sol")
				await _foto(id + "_23-00_sol")
			else:
				_cambiar(840, "lluvia")
				await _foto(id + "_14-00_lluvia")
			if id in MEDIR:
				if interfaz != null:
					interfaz.show()
				_cambiar(840, "sol")
				await _medir(id, 2, carga)
			continue
		if not solo_medidas:
			for clima: String in CLIMAS:
				for minutos: int in MINUTOS:
					_cambiar(minutos, clima)
					await _foto("%s_%02d-%02d_%s" % [id, minutos / 60, minutos % 60, clima])
		if id in MEDIR:
			if interfaz != null:
				interfaz.show()
			_cambiar(840, "sol")
			for calidad in (3 if fase == "antes" else 4):
				Ajustes.poner("calidad", calidad)
				await _medir(id, calidad, carga)
			Ajustes.poner("calidad", 2)
	if not _medidas.is_empty():
		var archivo := FileAccess.open(_salida.path_join("rendimiento" + ("_" + solo if not solo.is_empty() else "") + ".txt"), FileAccess.WRITE)
		if archivo != null:
			archivo.store_string("Vulkan, 1920 × 1080, 14:00, sol, primera persona, %d fotogramas por preajuste.\n" % FOTOGRAMAS)
			archivo.store_string("\n".join(_medidas) + "\n")
		else:
			_fallos += 1
	await Escenas._quitar_escena_actual()
	get_tree().quit(0 if _fallos == 0 else 1)


func _encuadrar(id: String, leo: Jugador, mapa: Mapa) -> void:
	var origen := leo.global_position
	var rumbo := -leo.camara.camara.global_basis.z
	var marca := mapa.marcador("Camara_suelo")
	if marca != null and id != "costa_lago":
		origen = marca.global_position
		rumbo = -marca.global_basis.z
	elif id == "costa_lago":
		origen = mapa.marcador("Pesca_Muelle").global_position + Vector3(0.30, 0, -2.4)
		rumbo = Vector3(-0.66, -0.17, -0.75)
	elif id == "casa_leo":
		rumbo = Vector3(-0.2, -0.13, -1)
	elif id == "mina_interior":
		rumbo.y = -0.04
	var columna := PhysicsRayQueryParameters3D.create(origen + Vector3.UP * 0.45, origen - Vector3.UP * 5.0, 1, [leo.get_rid()])
	var suelo := mapa.get_world_3d().direct_space_state.intersect_ray(columna)
	if not suelo.is_empty():
		origen.y = float(suelo.position.y) + 0.03
	leo.global_position = origen
	leo.camara.mirar_hacia(leo.camara.camara.global_position + rumbo * 15.0)


func _cambiar(minutos: int, clima: String) -> void:
	Juego.minutos = minutos
	Juego.clima = clima
	Juego.clima_cambiado.emit(clima)
	Juego.hora_cambiada.emit(minutos)


func _foto(nombre: String) -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var imagen := get_viewport().get_texture().get_image()
	if imagen == null or imagen.get_size() != Vector2i(1920, 1080) or imagen.save_png(_salida.path_join(nombre + ".png")) != OK:
		push_error("Captura H03 fallida: " + nombre)
		_fallos += 1


func _medir(id: String, calidad: int, carga: int) -> void:
	await get_tree().create_timer(0.9).timeout
	var tiempos := PackedFloat64Array()
	var inicio := Time.get_ticks_usec()
	var previo := inicio
	for _i in FOTOGRAMAS:
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		tiempos.append((ahora - previo) * 0.001)
		previo = ahora
	tiempos.sort()
	var peor := 0.0
	var cantidad := FOTOGRAMAS / 100
	for i in range(FOTOGRAMAS - cantidad, FOTOGRAMAS):
		peor += tiempos[i] / cantidad
	var linea := "%s · %s · %.1f FPS medios · %.1f FPS (1 %% más lento) · carga %d ms" % [
		id, ["Bajo", "Medio", "Alto", "Ultra"][calidad], FOTOGRAMAS * 1000000.0 / (previo - inicio), 1000.0 / peor, carga]
	_medidas.append(linea)
	print(linea)
