extends Node
## Capturas antes y después de T12-mapa a 1280x720 y 1920x1080 en granja, pueblo, mina_exterior y mina_interior.

const RAIZ := "C:/Users/cristianfsc/Desktop/Boveda/raw/juego-personajes/juego/gestion/noche-codex/capturas/T12-mapa/"

var _fase: String = "antes"
var _terminado: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _esperar_mapa() -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	var m := Interfaz.minimapa()
	var t0 := Time.get_ticks_msec()
	while (m == null or not m.lista()) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame


func _ejecutar() -> void:
	var env_fase := OS.get_environment("MH_T12_FASE")
	if env_fase == "antes" or env_fase == "despues":
		_fase = env_fase
	var carpeta := RAIZ + _fase + "/"
	DirAccess.make_dir_recursive_absolute(carpeta)

	var vals_antes := Ajustes.valores.duplicate()
	var ruta_antes := Ajustes.ruta
	Ajustes.ruta = "user://ajustes_capturas_t12.cfg"
	Ajustes.restaurar()

	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_t12.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 660
	Juego.clima = "sol"
	FotoCenital.olvidar()

	for mapa_id: String in ["granja", "pueblo", "mina_exterior", "mina_interior"]:
		await Escenas.ir_a_mapa(mapa_id)
		await _esperar_mapa()
		Interfaz.cerrar_todo()
		Interfaz.alternar_mapa()
		for tam: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(tam)
			await get_tree().create_timer(0.45).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var archivo := "%s%s_%dx%d.png" % [carpeta, mapa_id, tam.x, tam.y]
			img.save_png(archivo)
			print("CAPTURA T12 [", _fase, "] ", mapa_id, " ", tam.x, "x", tam.y, " -> img=", img.get_size())

	DisplayServer.window_set_size(Vector2i(1600, 900))
	Ajustes.valores = vals_antes
	Ajustes.ruta = ruta_antes
	_terminado = true
	print("CAPTURAS T12 LISTAS (", _fase, ")")
	get_tree().quit(0)
