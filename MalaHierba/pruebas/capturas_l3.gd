extends Node
## Capturas del núcleo (L3). Necesita ventana; se cierra sola:
##   godot.ps1 --path <proyecto> --scene res://pruebas/capturas_l3.tscn
## Guarda en res://pruebas/capturas/l3_*.png: menú, intro, mapa de prueba con HUD, inventario, diálogo y los mapas reales de L1.

const SALIDA := "res://pruebas/capturas/"
const MAPAS_REALES := ["granja", "pueblo", "mina_exterior", "mina_interior"]


func _ready() -> void:
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SALIDA + "l3_" + nombre + ".png"))
	print("captura ", nombre, " ", img.get_size())


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_l3.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))

	# Menú (con una partida guardada para que aparezca «Continuar»).
	Juego.nueva_partida("Leo")
	Juego.guardar()
	await Escenas.ir_a_escena(Escenas.ESCENA_MENU)
	await _esperar(1.0)
	await _foto("menu")

	# Intro: la carta de la abuela Rosa.
	await Escenas.ir_a_escena(Escenas.ESCENA_INTRO)
	await _esperar(1.5)
	await _foto("intro")

	# Mapa de prueba con HUD, inventario, diálogo y tienda.
	Juego.nueva_partida("Leo")
	await Escenas.ir_a_mapa("prueba")
	await _esperar(1.3)
	await _foto("mapa_prueba")
	Interfaz.abrir_inventario()
	await _esperar(0.5)
	await _foto("inventario")
	Interfaz.cerrar_todo()
	Interfaz.mostrar_dialogo("Clara", ["Buenos días, Leo. Dicen que has heredado la finca de tu abuela Rosa.", "Si necesitas herramientas, pasa por la fragua."])
	await _esperar(1.6)
	await _foto("dialogo")
	Interfaz.cerrar_todo()
	Interfaz.abrir_tienda("tienda_mateo")
	await _esperar(0.5)
	await _foto("tienda")
	Interfaz.cerrar_todo()
	Juego.minutos = 1320
	await _esperar(0.8)
	await _foto("noche_prueba")
	Juego.minutos = 480
	Juego.clima = "lluvia"
	await Escenas.ir_a_mapa("prueba")
	await _esperar(2.0)
	await _foto("lluvia_prueba")
	Juego.clima = "sol"

	# Mapas reales ya exportados por L1.
	for id: String in MAPAS_REALES:
		if not FileAccess.file_exists("res://assets/mapas/%s/marcadores.json" % id):
			continue
		Juego.minutos = 600
		await Escenas.ir_a_mapa(id, "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista")
		await _esperar(1.5)
		await _foto("mapa_" + id)
		Juego.minutos = 1330
		await _esperar(0.8)
		await _foto("noche_" + id)

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS OK")
	get_tree().quit(0)
