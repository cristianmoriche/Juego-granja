extends Node
## Capturas antes/después para T23-tareas-diarias (máximo 2 PNG por fase, tope de 60 s).

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
	var fase := OS.get_environment("MH_T23_FASE")
	if fase.is_empty():
		fase = "antes"
	var salida := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T23-tareas-diarias/" + fase)
	DirAccess.make_dir_recursive_absolute(salida)

	Juego.ruta_partida = "user://partida_capturas_t23.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 640
	Juego.dia = 2
	await Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	var mapa := Escenas.mapa_actual_nodo()
	var j := Escenas.jugador() as Jugador
	var obj := mapa.get_node("Objetos/ObjetosPueblo") as ObjetosPueblo
	for _i in 120:
		if obj.construido:
			break
		await get_tree().process_frame
	if obj.tablon != null:
		j.colocar(obj.tablon.global_position + Vector3(0.0, 0.05, 1.4), 0.0, 0.0)
		j.velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout

	obj.menu_tablon()
	await get_tree().create_timer(0.25).timeout
	await _grabar_foto(salida + "/01_tablon_pueblo.png")
	Interfaz.cerrar_todo()
	await get_tree().process_frame

	Interfaz.abrir_diario("hoy")
	await get_tree().create_timer(0.25).timeout
	await _grabar_foto(salida + "/02_diario_hoy.png")
	Interfaz.cerrar_todo()
	get_tree().quit(0)
