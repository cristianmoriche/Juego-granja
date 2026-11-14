extends Node
## Capturas antes/después de T20-rueda-objetos desde la misma cámara de la granja.

const DIR_BASE := "C:/Users/cristianfsc/Desktop/Boveda/raw/juego-personajes/juego/gestion/noche-codex/capturas/T20-rueda-objetos"


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.add_child.call_deferred(tope)
	_ejecutar.call_deferred()


func _rueda(indice: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = indice
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var s := InputEventMouseButton.new()
	s.button_index = indice
	s.pressed = false
	Input.parse_input_event(s)
	await get_tree().process_frame


func _foto(carpeta: String, nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var ruta := "%s/%s.png" % [carpeta, nombre]
	get_viewport().get_texture().get_image().save_png(ruta)
	print("T20_FOTO ", ruta)


func _ejecutar() -> void:
	get_tree().current_scene = null
	var fase := OS.get_environment("MH_T20_FASE")
	if fase.is_empty():
		fase = "despues"
	var carpeta := "%s/%s" % [DIR_BASE, fase]
	DirAccess.make_dir_recursive_absolute(carpeta)

	Juego.ruta_partida = "user://partida_capturas_t20.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.elegir_ranura(0)
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	await get_tree().create_timer(0.6).timeout
	var j := Escenas.jugador() as Jugador
	var cam := j.camara

	await _foto(carpeta, "01_inicio")
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().create_timer(0.35).timeout
	print("T20_ESTADO_%s tras_abajo ranura=%d dist=%.2f" % [fase, Juego.ranura, cam.distancia])
	await _foto(carpeta, "02_tras_rueda_abajo")

	Juego.elegir_ranura(0)
	await _rueda(MOUSE_BUTTON_WHEEL_UP)
	await get_tree().create_timer(0.2).timeout
	print("T20_ESTADO_%s tras_arriba_desde_0 ranura=%d dist=%.2f" % [fase, Juego.ranura, cam.distancia])
	await _foto(carpeta, "03_vuelta_extremos")

	Juego.elegir_ranura(2)
	Interfaz.abrir_tienda("tienda_mateo")
	await get_tree().create_timer(0.25).timeout
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	print("T20_ESTADO_%s en_tienda ranura=%d" % [fase, Juego.ranura])
	await _foto(carpeta, "04_en_tienda")

	Interfaz.cerrar_todo()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	get_tree().quit(0)
