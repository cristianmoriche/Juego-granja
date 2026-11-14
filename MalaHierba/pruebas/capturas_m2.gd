extends Node
## Captura de M2: Leo junto a una casa del pueblo para ver la proporción nueva. Necesita ventana y se cierra sola (< 30 s):
##   godot.ps1 --path <proyecto> --position 40,40 --resolution 640x360 --scene res://pruebas/capturas_m2.tscn
## Guarda res://pruebas/capturas/m2_leo_casa.png (Leo de espaldas, a metro y medio de la fachada norte de la casita del
## este, con la cámara baja para que se vean juntos el alero, el tejado y la cabeza de Leo) y m2_leo_agachado.png.

const SALIDA := "res://pruebas/capturas/"

var _j: Jugador = null
var _mapa: Node = null


func _ready() -> void:
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 800:
		img.resize(800, int(float(img.get_height()) * 800.0 / float(img.get_width())), Image.INTERPOLATE_LANCZOS)   # captura pequeña
	img.save_png(ProjectSettings.globalize_path(SALIDA + nombre + ".png"))
	print("captura ", nombre, " ", img.get_size())


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z)
	return float(col["suelo"])


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_m2.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	Juego.nueva_partida("Leo")
	Juego.minutos = 660     # a media mañana
	var mm: Minimapa = Interfaz.minimapa()
	var antes := mm.fotos_hechas
	await Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")) and mm.fotos_hechas > antes:
			break
		await get_tree().process_frame
	Interfaz.mostrar_hud(false)
	# Fachada norte de la casita del este (pared hacia z ≈ 8): Leo a 1,5 m, mirando a ella.
	var x := 9.6
	var z := 6.4
	_j.colocar(Vector3(x, _suelo(x, z) + 0.05, z), 0.0, PI)
	_j.camara.pitch = deg_to_rad(9.0)
	_j.camara._dist_obj = 8.5
	_j.camara.distancia = 8.5
	await _esperar(1.2)
	await _foto("m2_leo_casa")
	# Agachado, en el mismo sitio.
	Input.action_press("agachar")
	await _esperar(1.0)
	await _foto("m2_leo_agachado")
	Input.action_release("agachar")
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS OK")
	get_tree().quit(0)
