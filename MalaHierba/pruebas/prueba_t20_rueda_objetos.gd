extends Node
## Regresión de T20-rueda-objetos: rueda en barra de objetos, cero zoom/cámara, bloqueo con UI y soporte 1–0/mando.

var _fallos: Array[String] = []
var _total := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.add_child.call_deferred(tope)
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, texto: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(texto)
		print("FALLO: ", texto)


func _rueda(indice: int) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = indice
	e.pressed = true
	get_tree().root.push_input(e)
	await get_tree().process_frame
	var s := InputEventMouseButton.new()
	s.button_index = indice
	s.pressed = false
	get_tree().root.push_input(s)
	await get_tree().process_frame


func _tecla(codigo: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = codigo
	e.physical_keycode = codigo
	e.pressed = true
	get_tree().root.push_input(e)
	await get_tree().process_frame
	var s := InputEventKey.new()
	s.keycode = codigo
	s.physical_keycode = codigo
	s.pressed = false
	get_tree().root.push_input(s)
	await get_tree().process_frame


func _mando(boton: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = boton
	e.pressed = true
	get_tree().root.push_input(e)
	await get_tree().process_frame
	var s := InputEventJoypadButton.new()
	s.button_index = boton
	s.pressed = false
	get_tree().root.push_input(s)
	await get_tree().process_frame


func _ejecutar() -> void:
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_t20.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.elegir_ranura(0)
	await Escenas.ir_a_mapa("prueba")
	for _i in 20:
		await get_tree().physics_frame
		await get_tree().process_frame

	var j := Escenas.jugador() as Jugador
	var cam := j.camara
	_comprobar(j != null and cam != null, "jugador y cámara cargados en mapa de prueba")

	# 1. Rueda hacia abajo recorre todas las ranuras 0..9 y da la vuelta a 0.
	var dist_ini := cam.distancia
	var obj_ini := cam._dist_obj
	var yaw_ini := cam.yaw
	var pitch_ini := cam.pitch
	var pos_cam_ini := cam.camara.global_position
	var pos_leo_ini := j.global_position

	for paso in 10:
		await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
		_comprobar(Juego.ranura == (paso + 1) % 10, "rueda abajo paso %d -> ranura %d" % [paso, (paso + 1) % 10])
	_comprobar(Juego.ranura == 0, "rueda abajo da la vuelta completa de 9 a 0")

	# 2. Rueda hacia arriba retrocede y da la vuelta de 0 a 9 -> ... -> 0.
	for paso in 10:
		await _rueda(MOUSE_BUTTON_WHEEL_UP)
		_comprobar(Juego.ranura == posmod(-(paso + 1), 10), "rueda arriba paso %d" % paso)
	_comprobar(Juego.ranura == 0, "rueda arriba da la vuelta completa")

	# 3. Ni zoom ni movimiento de cámara al usar la rueda.
	await get_tree().process_frame
	_comprobar(is_equal_approx(cam._dist_obj, obj_ini) and is_equal_approx(cam.distancia, dist_ini), "la rueda no cambia el zoom")
	_comprobar(is_equal_approx(cam.yaw, yaw_ini) and is_equal_approx(cam.pitch, pitch_ini), "la rueda no gira ni inclina la cámara")
	_comprobar(cam.camara.global_position.distance_to(pos_cam_ini) < 0.005, "la rueda no desplaza la cámara")
	_comprobar(j.global_position.distance_to(pos_leo_ini) < 0.001, "la rueda no mueve a Leo")

	# 4. Bloqueada mientras haya menú (pausa, ajustes, inventario, mapa grande), tienda o diálogo abiertos.
	Juego.elegir_ranura(2)
	Interfaz._pausa.abrir()
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	await _rueda(MOUSE_BUTTON_WHEEL_UP)
	_comprobar(Juego.ranura == 2, "pausa abierta bloquea la rueda")
	Interfaz._pausa.cerrar_panel()

	Interfaz.abrir_ajustes()
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	_comprobar(Juego.ranura == 2, "ajustes abiertos bloquean la rueda")
	Interfaz._ajustes.cerrar()

	Interfaz.abrir_inventario()
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	await _rueda(MOUSE_BUTTON_WHEEL_UP)
	_comprobar(Juego.ranura == 2, "inventario abierto bloquea la rueda")
	Interfaz._inventario.cerrar_panel()

	Interfaz.alternar_mapa()
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	_comprobar(Juego.ranura == 2, "mapa grande abierto bloquea la rueda")
	Interfaz._mapa_grande.cerrar()

	Interfaz.abrir_tienda("tienda_mateo")
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	await _rueda(MOUSE_BUTTON_WHEEL_UP)
	_comprobar(Juego.ranura == 2, "tienda abierta bloquea la rueda")
	Interfaz.cerrar_todo()

	Interfaz.mostrar_dialogo("Mateo", ["Buenos días, Leo."])
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	await _rueda(MOUSE_BUTTON_WHEEL_UP)
	_comprobar(Juego.ranura == 2, "conversación abierta bloquea la rueda")
	Interfaz.cerrar_todo()

	Interfaz.preguntar("¿Seguir?", ["Sí", "No"], func(_i: int) -> void: pass)
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	_comprobar(Juego.ranura == 2, "pregunta abierta bloquea la rueda")
	Interfaz.cerrar_todo()

	# 5. Teclas 1–0 y botones del mando siguen funcionando.
	await _tecla(KEY_5)
	_comprobar(Juego.ranura == 4, "tecla 5 selecciona ranura 4")
	await _tecla(KEY_0)
	_comprobar(Juego.ranura == 9, "tecla 0 selecciona ranura 9")
	await _tecla(KEY_1)
	_comprobar(Juego.ranura == 0, "tecla 1 selecciona ranura 0")
	await _mando(JOY_BUTTON_DPAD_RIGHT)
	_comprobar(Juego.ranura == 1, "mando derecha avanza a ranura 1")
	await _mando(JOY_BUTTON_DPAD_LEFT)
	await _mando(JOY_BUTTON_DPAD_LEFT)
	_comprobar(Juego.ranura == 9, "mando izquierda da la vuelta de 0 a 9")

	# 6. En el menú principal la rueda no cambia el objeto seleccionado.
	await Escenas.ir_a_escena(Escenas.ESCENA_MENU)
	await get_tree().process_frame
	await _rueda(MOUSE_BUTTON_WHEEL_DOWN)
	_comprobar(Juego.ranura == 9, "en menú principal la rueda no cambia la ranura")

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	if _fallos.is_empty():
		print("PRUEBA T20 OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA T20 FALLO (%d/%d)" % [_fallos.size(), _total])
		get_tree().quit(1)
