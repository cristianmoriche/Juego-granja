extends Node
## Capturas visuales de T26-mina-20-niveles (antes y después) con tope interno de 60 s.

const RUTA_CAP := "res://../gestion/noche-codex/capturas/T26-mina-20-niveles"


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.timeout.connect(func() -> void:
		push_error("capturas_t26: tiempo máximo de 60 s superado")
		get_tree().quit(1)
	)
	add_child(tope)
	tope.start()
	_ejecutar.call_deferred()


func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _esperar_mina() -> Mapa:
	for _i in 600:
		var m := Escenas.mapa_actual_nodo() as Mapa
		if not Escenas.en_transicion and m != null and m.id_mapa == "mina_interior" and m.esta_listo and m.vallas_listas:
			await _esperar(6)
			return m
		await get_tree().process_frame
	return null


func _foto_jugador(ruta: String, yaw: float = 0.45, dist: float = 11.0, pitch_deg: float = 28.0) -> void:
	var j := Escenas.jugador() as Jugador
	if j != null and j.camara != null:
		j.camara.yaw = yaw
		j.camara.pitch = deg_to_rad(pitch_deg)
		j.camara._dist_obj = dist
		j.camara.distancia = dist
		j.camara.call("_aplicar", 0.0)
	await _esperar(6)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(ruta))
	print("CAPTURA ", ruta, " -> ", err)


func _ejecutar() -> void:
	var args := OS.get_cmdline_user_args()
	var fase := "antes"
	for a: String in args:
		if a.begins_with("--fase="):
			fase = a.substr(7)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUTA_CAP + "/" + fase))
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_t26.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Interfaz.cerrar_todo()

	if fase == "antes":
		Juego.banderas["nivel_mina"] = 1
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		await _esperar_mina()
		await _foto_jugador(RUTA_CAP + "/antes/01_mina_nivel_1.png", -0.75, 11.5, 26.0)

		Juego.banderas["nivel_mina"] = 2
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		await _esperar_mina()
		await _foto_jugador(RUTA_CAP + "/antes/02_mina_nivel_2.png", -0.75, 11.5, 26.0)
	else:
		# Bioma cristal (nivel 12) y magma (nivel 18) con HUD de vida + antorchas + ascensor/escalera
		Juego.banderas["mina_max_nivel"] = 20
		Juego.banderas["nivel_mina"] = 12
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		await _esperar_mina()
		await _foto_jugador(RUTA_CAP + "/despues/01_mina_cristal_n12.png", -0.65, 13.0, 28.0)

		Juego.banderas["nivel_mina"] = 18
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		await _esperar_mina()
		await _foto_jugador(RUTA_CAP + "/despues/02_mina_magma_n18.png", -0.65, 13.5, 28.0)

	print("CAPTURAS_T26 OK (", fase, ")")
	get_tree().quit(0)
