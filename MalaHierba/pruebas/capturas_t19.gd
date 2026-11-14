extends Node
## Capturas de T19 (antes y después desde exactamente las mismas cámaras):
## Leo junto a un abeto en la granja, vista general del bosque de la granja, pueblo y mina exterior de día.

var _j: Jugador = null
var _mapa: Node = null
var _cam: Camera3D = null
var _salida: String = ""


func _ready() -> void:
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z)
	return float(col.get("suelo", 0.0))


func _ir(id_m: String) -> void:
	await Escenas.ir_a_mapa(id_m, "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")):
			break
		await get_tree().process_frame
	Juego.minutos = 660
	await _esperar(0.8)


func _camara_libre(pos: Vector3, mirar: Vector3, fov: float = 52.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 350.0
		get_tree().root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(mirar, Vector3.UP)
	_cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame


func _foto(nombre: String) -> void:
	await _esperar(0.35)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := _salida + "/" + nombre + ".png"
	img.save_png(ruta)
	print("captura ", nombre, " ", img.get_size(), " -> ", ruta)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	var fase := OS.get_environment("MH_T19_FASE")
	if fase.is_empty():
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T19-arboles-calidad/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)

	Juego.ruta_partida = "user://partida_capturas_t19.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 660
	Interfaz.mostrar_hud(false)

	# 1 y 2 y 5: Granja (Leo junto a abeto, vista general bosque, copas desde el bosque)
	await _ir("granja")
	Interfaz.mostrar_hud(false)

	# El abeto fir_tree_01_a más cercano está en (7.32, -0.14, -8.35).
	# Colocamos a Leo justo al lado y mirándolo, con la cámara fija en suelo/aire para encuadrar ambos.
	var y_leo := _suelo(5.6, -6.5)
	_j.colocar(Vector3(5.6, y_leo + 0.05, -6.5), deg_to_rad(-135.0), 0.0)
	_j.velocity = Vector3.ZERO
	await _esperar(0.3)
	await _camara_libre(Vector3(2.8, y_leo + 1.85, -3.2), Vector3(6.6, y_leo + 2.6, -7.7), 54.0)
	await _foto("01_granja_leo_abeto")

	# Vista general del bosque de la granja
	await _camara_libre(Vector3(-12.0, 10.5, 16.0), Vector3(4.5, 3.0, -10.0), 54.0)
	await _foto("02_granja_bosque")

	# Vista de copas y troncos desde el bosque hacia arriba
	var y_bos := _suelo(2.5, -9.0)
	await _camara_libre(Vector3(2.5, y_bos + 1.6, -7.0), Vector3(6.5, y_bos + 5.8, -11.5), 58.0)
	await _foto("05_granja_bosque_copas")

	# 3: Pueblo de día con abetos
	await _ir("pueblo")
	Interfaz.mostrar_hud(false)
	await _camara_libre(Vector3(-16.0, 11.0, 26.0), Vector3(4.0, 3.5, -14.0), 54.0)
	await _foto("03_pueblo_arboles")

	# 4: Mina exterior de día con abetos y entrada
	await _ir("mina_exterior")
	Interfaz.mostrar_hud(false)
	await _camara_libre(Vector3(11.0, 8.5, 22.0), Vector3(-5.5, 3.2, 4.0), 54.0)
	await _foto("04_mina_exterior_arboles")

	if is_instance_valid(_cam):
		_cam.queue_free()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS T19 OK (", fase, ")")
	get_tree().quit(0)
