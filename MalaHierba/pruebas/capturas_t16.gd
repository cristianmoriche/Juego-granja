extends Node
## Capturas antes/después de T16-pueblo desde exactamente las mismas cámaras:
## plaza normal, festividad de primavera (14 de primavera), festividad de otoño (18 de otoño),
## día de lluvia, plaza con la deuda pagada y diálogo/HUD festivo.

var _cam: Camera3D = null
var _salida: String = ""
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			push_error("T16 capturas: tiempo límite agotado")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _camara_libre(pos: Vector3, mirar: Vector3, fov: float = 52.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 400.0
		get_tree().root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(mirar, Vector3.UP)
	_cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame


func _foto(nombre: String) -> void:
	await _esperar(0.45)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := _salida + "/" + nombre + ".png"
	var err := img.save_png(ruta)
	print("captura ", nombre, " ", img.get_size(), " err=", err, " -> ", ruta)


func _cargar_pueblo(est: int, d: int, hora_min: int, clima: String) -> Node:
	print("-> pueblo est=", est, " dia=", d, " min=", hora_min, " clima=", clima)
	Juego.estacion = est
	Juego.dia = d
	Juego.minutos = hora_min
	Juego.clima = clima
	Juego.aplicar_evento_hoy()
	Juego.pausar_tiempo(true)
	await Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	Interfaz.mostrar_hud(false)
	var m := Escenas.mapa_actual_nodo()
	for _i in 180:
		if m != null and bool(m.get("vallas_listas")):
			break
		await get_tree().process_frame
	Juego.minutos = hora_min
	Juego.clima = clima
	Juego.pausar_tiempo(true)
	Juego.actualizar_entorno_shader()
	if m != null and m.has_method("_actualizar_precipitacion"):
		m.call("_actualizar_precipitacion")
	if m != null:
		var vec := m.get_node_or_null("Objetos/Vecinos") as Vecinos
		if vec != null:
			vec.sincronizar(true)
	if Interfaz._hud != null:
		Interfaz._hud.limpiar_avisos()
	await _esperar(0.75)
	return m


func _ejecutar() -> void:
	print("T16_CAPTURAS_INICIO")
	var fase := OS.get_environment("MH_T16_FASE")
	if fase != "antes" and fase != "despues":
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T16-pueblo/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _esperar(0.2)
	get_tree().current_scene = null

	var tut_previo: bool = bool(Ajustes.valores.get("tutorial", true))
	Ajustes.valores["tutorial"] = false
	Tutorial.actualizado.emit()

	var ruta_previa := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_capturas_t16.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")

	# 01: Plaza normal (día 1 de primavera, 11:30, sol, deuda 5000).
	await _cargar_pueblo(0, 1, 690, "sol")
	await _camara_libre(Vector3(-5.5, 5.8, 11.2), Vector3(1.0, 1.6, -4.5), 54.0)
	await _foto("01_plaza_normal")

	# 02 y 03: Festividad de primavera (14 de primavera, 12:30, sol).
	var mp_prim := await _cargar_pueblo(0, 14, 750, "sol")
	await _camara_libre(Vector3(-5.5, 5.8, 11.2), Vector3(1.0, 1.6, -4.5), 54.0)
	await _foto("02_festividad_primavera")
	await _camara_libre(Vector3(-7.5, 4.2, 9.5), Vector3(0.5, 1.4, -2.5), 50.0)
	await _foto("03_festividad_primavera_detalle")

	# 07: HUD + diálogo durante festividad de primavera.
	Interfaz.mostrar_hud(true)
	if Interfaz._hud != null:
		Interfaz._hud.limpiar_avisos()
		if Interfaz._hud.get("_tutorial") != null:
			(Interfaz._hud.get("_tutorial") as Control).visible = false
	var vec_p := mp_prim.get_node_or_null("Objetos/Vecinos") as Vecinos if mp_prim != null else null
	var anselmo := vec_p.npcs.get("anselmo") as Npc if vec_p != null else null
	if anselmo != null:
		Conversacion.charlar(anselmo)
		await _esperar(2.8)
	await _foto("07_dialogo_y_hud_festival")
	Interfaz.cerrar_todo()
	if Interfaz._hud != null:
		Interfaz._hud.limpiar_avisos()

	# 04: Festividad de otoño (18 de otoño, 16:00, sol).
	await _cargar_pueblo(2, 18, 960, "sol")
	await _camara_libre(Vector3(-5.5, 5.8, 11.2), Vector3(1.0, 1.6, -4.5), 54.0)
	await _foto("04_festividad_otono")

	# 05: Rutina de lluvia (3 de primavera, 11:30, lluvia).
	await _cargar_pueblo(0, 3, 690, "lluvia")
	await _camara_libre(Vector3(-8.0, 5.2, 12.0), Vector3(3.5, 1.5, -8.5), 52.0)
	await _foto("05_lluvia_rutina")

	# 06: Pueblo tras pagar la deuda (deuda = 0, verano día 20, 11:30).
	Juego.nueva_partida("Leo")
	Juego.dinero = 6000
	if Juego.has_method("pagar_deuda"):
		Juego.call("pagar_deuda", Juego.deuda)
	else:
		Juego.deuda = 0
		Juego.banderas["deuda_pagada"] = 5000
	await _cargar_pueblo(1, 20, 690, "sol")
	await _camara_libre(Vector3(-3.5, 4.8, 10.2), Vector3(1.5, 1.5, -3.5), 52.0)
	await _foto("06_deuda_pagada_plaza")

	Ajustes.valores["tutorial"] = tut_previo
	Tutorial.actualizado.emit()
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_previa
	_terminado = true
	print("CAPTURAS T16 (" + fase + ") COMPLETADAS")
	get_tree().quit(0)
