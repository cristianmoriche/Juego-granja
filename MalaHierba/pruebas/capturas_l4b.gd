extends Node
## Capturas de L4b (vecinos, conversación, tienda, mina con rocas y nivel 2). Necesita ventana y se cierra sola (< 40 s):
##   godot.ps1 --path <proyecto> --position 40,40 --resolution 1024x576 --scene res://pruebas/capturas_l4b.tscn
## Guarda en res://pruebas/capturas/l4b_*.png.

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
	img.save_png(ProjectSettings.globalize_path(SALIDA + "l4b_" + nombre + ".png"))
	print("captura ", nombre, " ", img.get_size(), " · ", Engine.get_frames_per_second(), " fps")


func _ir(id: String, llegada: String = "Spawn_Protagonista") -> void:
	await Escenas.ir_a_mapa(id, llegada)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	await _esperar(1.2)


## Leo a `dist` metros de `objetivo`, mirándolo, con la cámara detrás de él.
func _frente_a(objetivo: Vector3, desde: Vector3, dist: float, pitch_grados: float, distancia_camara: float, giro_extra: float = 0.0) -> void:
	var d := desde - objetivo
	d.y = 0.0
	d = d.normalized()
	var pos := objetivo + d * dist
	pos.y = objetivo.y
	var mira := -d
	var yaw := atan2(-mira.x, -mira.z) + deg_to_rad(giro_extra)
	_j.colocar(pos, 0.0, yaw)
	_j.direccion = mira
	_j.camara.pitch = deg_to_rad(pitch_grados)
	_j.camara._dist_obj = distancia_camara
	_j.camara.distancia = distancia_camara
	await _esperar(0.9)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_l4b.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 660
	Juego.anadir_objeto("cobre", 3)

	# --- Pueblo ---
	await _ir("pueblo")
	var vecinos := _mapa.get_node("Objetos/Vecinos") as Vecinos
	var mateo := vecinos.npcs["pablo"] as Npc      # Pablo está en plaza abierta (junto a la tienda la cámara choca con el tejadillo)
	print("vecinos en el pueblo: ", vecinos.npcs.keys())
	for id in vecinos.npcs:
		var n := vecinos.npcs[id] as Npc
		print("  ", id, " ", n.global_position)
	var mejor_giro := 90.0       # de lado: se ven Leo y el vecino uno junto al otro
	await _frente_a(mateo.global_position, Vector3(-3.0, 0, 0.5), 1.5, 45.0, 9.0, mejor_giro)
	await _foto("pueblo_vecinos")
	# Minimapa (esquina superior izquierda) con los puntos de los vecinos.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var escala := float(img.get_width()) / 1600.0
	img.get_region(Rect2i(0, 0, int(260.0 * escala), int(262.0 * escala))).save_png(ProjectSettings.globalize_path(SALIDA + "l4b_minimapa_pueblo.png"))

	# Plaza: el pozo, los bancos y el tablón, con gente alrededor.
	await _frente_a(Vector3(0, 0, 0), Vector3(-1.0, 0, 6.0), 2.8, 38.0, 8.5)
	await _foto("pueblo_pozo")
	var obj := _mapa.get_node("Objetos/ObjetosPueblo") as ObjetosPueblo
	await _frente_a(obj.tablon.global_position, Vector3(0, 0, 0), 1.2, 35.0, 6.5)
	await _foto("pueblo_tablon")

	# Conversación: menú y frase de Don Mateo, y su tienda.
	await _frente_a(mateo.global_position, Vector3(-3.0, 0, 0.5), 1.5, 45.0, 9.0, mejor_giro)
	Conversacion.hablar(mateo, _j)
	await _esperar(0.5)
	await _foto("menu_pablo")
	var p := Interfaz.get_node("Raiz/Pregunta") as PanelPregunta
	for b in p._botones:
		if b.text.contains("Hablar"):
			b.pressed.emit()
			break
	await _esperar(1.6)
	await _foto("dialogo")
	Interfaz.cerrar_todo()
	Interfaz.abrir_tienda("tienda_mateo")
	await _esperar(0.5)
	await _foto("tienda")
	Interfaz.cerrar_todo()

	# --- Mina exterior con vecinos ---
	await _ir("mina_exterior")
	var vm := _mapa.get_node("Objetos/Vecinos") as Vecinos
	var tomas := vm.npcs["tomas"] as Npc
	await _frente_a(tomas.global_position, Vector3(-8.0, 0, 4.0), 1.5, 40.0, 9.0)
	await _foto("mina_exterior_tomas")

	# --- Mina interior: nivel 1 y nivel 2 ---
	await _ir("mina_interior", "Llegada_Interior")
	var rocas := _mapa.get_node("Objetos/RocasMina") as RocasMina
	var elegida: RocasMina.Roca = null
	var mejor := INF
	for r in rocas.rocas_en_pie():
		if r.tipo == "cobre" or r.tipo == "hierro":
			var d := r.pos.distance_to(_j.global_position)
			if d < mejor:
				mejor = d
				elegida = r
	print("nivel 1: ", rocas.rocas_en_pie().size(), " rocas; la elegida ", elegida.id, " ", elegida.tipo, " en ", elegida.pos)
	await _frente_a(elegida.pos, _j.global_position, 1.9, 48.0, 7.0, 75.0)
	await _foto("mina_rocas_nivel1")
	# Vista amplia de la cueva grande.
	var escalera := _mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	await _frente_a(escalera.global_position, escalera.global_position + Vector3(-3.0, 0, 3.0), 1.6, 50.0, 9.0)
	await _foto("mina_escalera")
	Juego.banderas["nivel_mina"] = 2
	await _ir("mina_interior", "Llegada_Interior")
	rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
	var q: RocasMina.Roca = null
	mejor = INF
	for r in rocas.rocas_en_pie():
		if r.tipo == "cuarzo":
			var d2 := r.pos.distance_to(_j.global_position)
			if d2 < mejor:
				mejor = d2
				q = r
	print("nivel 2: ", rocas.rocas_en_pie().size(), " rocas; cuarzo ", q.id, " en ", q.pos)
	await _frente_a(q.pos, _j.global_position, 1.9, 48.0, 7.0, 75.0)
	await _foto("mina_cuarzo_nivel2")

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS OK")
	get_tree().quit(0)
