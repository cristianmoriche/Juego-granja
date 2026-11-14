extends Node
## Capturas antes/después para T24-casa-y-muebles (máximo 2 PNG por fase, tope de 60 s).

var _j: Jugador = null
var _mapa: Node = null


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _grabar_foto(ruta: String, ancho_max: int = 1280) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > ancho_max:
		img.resize(ancho_max, int(float(img.get_height()) * float(ancho_max) / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png(ruta)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	var fase := OS.get_environment("MH_T24_FASE")
	if fase.is_empty():
		fase = "antes"
	var salida := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T24-casa-y-muebles/" + fase)
	DirAccess.make_dir_recursive_absolute(salida)

	Juego.ruta_partida = "user://partida_capturas_t24.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 660
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")):
			break
		await get_tree().process_frame

	if fase == "antes":
		var p_cab := _mapa.call("marcador", "Puerta_Cabana") as Marker3D
		if p_cab != null:
			_j.colocar(p_cab.global_position + Vector3(0.0, 0.02, 1.3), PI, 0.0)
			if _j.camara != null:
				_j.camara.yaw = 0.0
				_j.camara.pitch = deg_to_rad(30.0)
				_j.camara._dist_obj = 6.0
		await get_tree().create_timer(0.5).timeout
		await _grabar_foto(salida + "/01_entrada_cabana.png")

		await Escenas.ir_a_mapa("casa_leo", "Entrada")
		_mapa = Escenas.mapa_actual_nodo()
		_j = Escenas.jugador() as Jugador
		if _j.camara != null:
			_j.camara.yaw = 0.0
			_j.camara.pitch = deg_to_rad(42.0)
			_j.camara._dist_obj = 6.2
		await get_tree().create_timer(0.5).timeout
		await _grabar_foto(salida + "/02_interior_antes.png")
	else:
		await Escenas.ir_a_mapa("casa_leo", "Entrada")
		_mapa = Escenas.mapa_actual_nodo()
		_j = Escenas.jugador() as Jugador
		var deco := _mapa.get_node_or_null("Objetos/DecoracionCasa")
		if deco != null:
			var ejemplos := [
				{"id": "chimenea_piedra", "gx": 13, "gz": 8, "rot": 3},
				{"id": "alfombra_roja", "gx": 5, "gz": 4, "rot": 0},
				{"id": "mesa_roble", "gx": 5, "gz": 4, "rot": 0},
				{"id": "silla_roble", "gx": 4, "gz": 4, "rot": 1},
				{"id": "silla_roble", "gx": 7, "gz": 4, "rot": 3},
				{"id": "lampara_pie", "gx": 3, "gz": 1, "rot": 0},
				{"id": "maceta_helecho", "gx": 11, "gz": 2, "rot": 0},
				{"id": "cuadro_valle", "gx": 6, "gz": 0, "rot": 0},
				{"id": "cuadro_girasoles", "gx": 9, "gz": 0, "rot": 0},
				{"id": "baul_roble", "gx": 4, "gz": 1, "rot": 0},
				{"id": "estanteria_baja", "gx": 9, "gz": 1, "rot": 0},
			]
			for ej: Dictionary in ejemplos:
				Juego.anadir_objeto(str(ej["id"]), 1)
				deco.call("colocar_mueble_en_celda", str(ej["id"]), Vector2i(int(ej["gx"]), int(ej["gz"])), int(ej["rot"]), true)
		_j.colocar(Vector3(0.0, 0.02, 0.8), PI, 0.0)
		if _j.camara != null:
			_j.camara.yaw = 0.25
			_j.camara.pitch = deg_to_rad(36.0)
			_j.camara._dist_obj = 4.9
		await get_tree().create_timer(0.5).timeout
		await _grabar_foto(salida + "/01_interior_amueblado.png")

		if deco != null:
			Juego.anadir_objeto("mesa_redonda", 1)
			var idx := -1
			for i in Juego.inventario.size():
				if str((Juego.inventario[i] as Dictionary).get("id", "")) == "mesa_redonda":
					idx = i
					break
			if idx >= 0 and idx < 10:
				Juego.elegir_ranura(idx)
			elif idx >= 10:
				Juego.mover_huecos(idx, 9)
				Juego.elegir_ranura(9)
			deco.call("entrar_modo_decorar", "mesa_redonda")
			deco.call("fijar_cursor_celda", Vector2i(4, 6), 0)
		await get_tree().create_timer(0.4).timeout
		await _grabar_foto(salida + "/02_modo_decorar_rejilla.png")

	Interfaz.cerrar_todo()
	get_tree().quit(0)
