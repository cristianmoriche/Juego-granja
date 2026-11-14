extends Node
## Capturas de M1 (cámara libre, límites, interacciones, minimapa). Necesita ventana y se cierra sola (< 40 s):
##   godot.ps1 --path <proyecto> --position 40,40 --resolution 1024x576 --scene res://pruebas/capturas_m1.tscn
## Guarda en res://pruebas/capturas/m1_*.png: la granja desde tres ángulos de cámara (incluida tercera persona baja), el
## minimapa, el mapa grande, el resaltado de un interactuable, las vallas del borde, el pueblo y la mina.

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
	img.save_png(ProjectSettings.globalize_path(SALIDA + "m1_" + nombre + ".png"))
	print("captura ", nombre, " ", img.get_size())


## Recorte del minimapa (esquina superior izquierda) ampliado ×1, para verlo bien.
func _foto_minimapa(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var escala := float(img.get_width()) / 1600.0
	var recorte := img.get_region(Rect2i(0, 0, int(260.0 * escala), int(262.0 * escala)))
	recorte.save_png(ProjectSettings.globalize_path(SALIDA + "m1_" + nombre + ".png"))
	print("captura ", nombre, " ", recorte.get_size())


func _ir(id: String, llegada: String = "Spawn_Protagonista") -> void:
	var mm: Minimapa = Interfaz.minimapa()
	var antes := mm.fotos_hechas
	await Escenas.ir_a_mapa(id, llegada)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")) and mm.fotos_hechas > antes:
			break
		await get_tree().process_frame
	print("mapa ", id, ": foto del minimapa en ", mm.generado_ms, " ms (real: ", FotoCenital.ultimo_real, "), postes ", _mapa.get("numero_postes"))
	await _esperar(0.8)


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z)
	return float(col["suelo"])


## Pone a Leo en (x, z) y la cámara con ese giro, inclinación (grados) y distancia.
func _vista(x: float, z: float, yaw_grados: float, pitch_grados: float, distancia: float) -> void:
	var pos := Vector3(x, _suelo(x, z) + 0.05, z)
	_j.colocar(pos, 0.0, deg_to_rad(yaw_grados))
	_j.camara.pitch = deg_to_rad(pitch_grados)
	_j.camara._dist_obj = distancia
	_j.camara.distancia = distancia
	await _esperar(0.7)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_m1.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	Juego.nueva_partida("Leo")
	Juego.minutos = 660     # a media mañana

	# --- Granja ---
	await _ir("granja")
	await _vista(-5.8, 1.8, _j.camara.yaw * 180.0 / PI, 50.0, 12.0)
	await _foto("granja_juego")
	await _foto_minimapa("minimapa_granja")
	await _vista(-5.8, 6.0, 90.0, 28.0, 8.0)
	await _foto("granja_orbita")
	await _vista(-5.8, 6.0, 200.0, 12.0, 3.4)
	await _foto("granja_tercera")

	# Resaltado: junto al silo, con su cartel.
	await _vista(-1.4, -2.3, 0.0, 30.0, 6.5)
	_j.direccion = Vector3(0, 0, -1)
	await _esperar(0.4)
	await _foto("granja_resaltado")

	# Dormir solo junto a la puerta de la cabaña.
	var puerta := _mapa.call("marcador", "Puerta_Cabana") as Marker3D
	await _vista(puerta.global_position.x, puerta.global_position.z + 1.1, 20.0, 30.0, 6.0)
	_j.direccion = Vector3(0, 0, -1)
	await _esperar(0.4)
	await _foto("granja_dormir")

	# El borde con valla, junto a la salida al pueblo.
	await _vista(9.0, 34.6, 180.0, 22.0, 7.5)
	await _foto("granja_valla")
	await _vista(-4.0, 31.0, 160.0, 40.0, 14.0)
	await _foto("granja_salida")

	# Mapa grande.
	await _vista(-5.8, 1.8, 0.0, 50.0, 12.0)
	Interfaz.alternar_mapa()
	await _esperar(0.5)
	await _foto("mapa_grande_granja")
	Interfaz.alternar_mapa()

	# --- Pueblo ---
	await _ir("pueblo")
	await _foto("pueblo_juego")
	await _vista(-8.7, 3.7, 0.0, 30.0, 6.5)
	_j.direccion = Vector3(0, 0, -1)
	await _esperar(0.4)
	await _foto("pueblo_cartel")
	Interfaz.alternar_mapa()
	await _esperar(0.5)
	await _foto("mapa_grande_pueblo")
	Interfaz.alternar_mapa()

	# --- Mina ---
	await _ir("mina_exterior")
	await _foto("mina_exterior_juego")
	Interfaz.alternar_mapa()
	await _esperar(0.5)
	await _foto("mapa_grande_mina_exterior")
	Interfaz.alternar_mapa()
	await _ir("mina_interior", "Llegada_Interior")
	await _foto("mina_interior_juego")

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS OK")
	get_tree().quit(0)
