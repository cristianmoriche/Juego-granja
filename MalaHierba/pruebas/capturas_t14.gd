extends Node
## Capturas antes y después de T14-tutorial en granja (día 1), pueblo, mina interior y ajustes.

const RAIZ := "C:/Users/cristianfsc/Desktop/Boveda/raw/juego-personajes/juego/gestion/noche-codex/capturas/T14-tutorial/"

var _terminado := false


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
	for i in 12:
		await get_tree().process_frame


func _capturar(ruta: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ruta)


func _ejecutar() -> void:
	var fase := OS.get_environment("MH_T14_FASE")
	if fase != "antes" and fase != "despues":
		fase = "antes"
	var carpeta := RAIZ + fase + "/"
	DirAccess.make_dir_recursive_absolute(carpeta)

	var ruta_aj := Ajustes.ruta
	var vals_aj := Ajustes.valores.duplicate()
	Ajustes.ruta = "user://ajustes_capturas_t14.cfg"
	Ajustes.restaurar()
	Ajustes.poner("resolucion", 1)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _capturar(carpeta + "_warmup.png")
	DirAccess.remove_absolute(carpeta + "_warmup.png")

	get_tree().current_scene = null
	var ruta_p := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_capturas_t14.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 540
	Juego.clima = "sol"

	# 1. Granja día 1 (desde cámara de spawn)
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	await _esperar_mapa()
	await _capturar(carpeta + "granja_dia1.png")

	# Si ya existe el tutorial (fase después), capturar también vista en modo mando.
	var tut := get_node_or_null("/root/Tutorial")
	if fase == "despues" and tut != null:
		Ajustes.ultimo_mando = true
		if Interfaz.has_node("Raiz/Hud") and Interfaz.get_node("Raiz/Hud").has_method("refrescar_tutorial"):
			Interfaz.get_node("Raiz/Hud").call("refrescar_tutorial")
		await _capturar(carpeta + "granja_mando.png")
		Ajustes.ultimo_mando = false
		if Interfaz.has_node("Raiz/Hud") and Interfaz.get_node("Raiz/Hud").has_method("refrescar_tutorial"):
			Interfaz.get_node("Raiz/Hud").call("refrescar_tutorial")

	# 2. Primera entrada al pueblo
	Escenas.ir_a_mapa("pueblo", "Llegada_Granja")
	await Escenas.mapa_cargado
	await _esperar_mapa()
	await _capturar(carpeta + "pueblo_llegada.png")

	# 3. Entrada a la mina interior
	Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	await Escenas.mapa_cargado
	await _esperar_mapa()
	await _capturar(carpeta + "mina_interior.png")

	# 4. Ajustes -> Accesibilidad
	Interfaz.cerrar_todo()
	Interfaz.abrir_ajustes()
	Interfaz.get("_ajustes").call("_mostrar_pagina", 2)
	await _capturar(carpeta + "ajustes_accesibilidad.png")
	Interfaz.cerrar_todo()

	Juego.borrar_partida()
	Juego.ruta_partida = ruta_p
	Juego.partida_activa = false
	Ajustes.ruta = ruta_aj
	Ajustes.valores = vals_aj
	Ajustes.aplicar()
	print("CAPTURAS T14 OK (%s)" % fase)
	_terminado = true
	get_tree().quit(0)
