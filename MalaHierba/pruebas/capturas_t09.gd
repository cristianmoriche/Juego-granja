extends Node
## Capturas antes/después para T09-resoluciones en 1280x720, 1920x1080, 2560x1080 y 3440x1440.
## Saca menú, granja, pueblo, inventario y mapa en cada resolución.

const RESOLUCIONES := [
	{"etiqueta": "1280x720", "tam": Vector2i(1280, 720)},
	{"etiqueta": "1920x1080", "tam": Vector2i(1920, 1080)},
	{"etiqueta": "2560x1080", "tam": Vector2i(2560, 1080)},
	{"etiqueta": "3440x1440", "tam": Vector2i(3440, 1440)},
]

var _dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("capturas_t09: tiempo límite de 60 s superado")
		get_tree().quit(1))
	get_tree().root.add_child.call_deferred(tope)
	tope.ready.connect(tope.start)
	var fase := OS.get_environment("MH_T09_FASE")
	if fase.is_empty():
		fase = "despues"
	_dir = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T09-resoluciones/" + fase)
	DirAccess.make_dir_recursive_absolute(_dir)
	_ejecutar.call_deferred()


func _poner_resolucion(tam: Vector2i) -> void:
	var w := get_window()
	w.content_scale_size = Vector2i(1600, 900)
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if w.mode != Window.MODE_WINDOWED:
		w.mode = Window.MODE_WINDOWED
	w.size = tam
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("  res pedida=%s real=%s vp=%s" % [tam, w.size, get_viewport().get_visible_rect().size])


func _capturar(etiqueta_res: String, nombre: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sub := _dir + "/" + etiqueta_res
	DirAccess.make_dir_recursive_absolute(sub)
	var ruta := "%s/%s.png" % [sub, nombre]
	var err := img.save_png(ruta)
	print("captura %s/%s %s err=%d -> %s" % [etiqueta_res, nombre, str(img.get_size()), err, ruta])


func _quitar_escena() -> void:
	var act := get_tree().current_scene
	if act != null and is_instance_valid(act) and act != self:
		get_tree().current_scene = null
		act.queue_free()
		if act.is_inside_tree():
			await act.tree_exited
	await get_tree().process_frame


func _esperar_no_transicion() -> void:
	var n := 0
	while Escenas.en_transicion and n < 600:
		await get_tree().process_frame
		n += 1


func _esperar_minimapa() -> void:
	var m := Interfaz.minimapa()
	var t0 := Time.get_ticks_msec()
	while (m == null or not m.lista()) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame


func _iniciar_partida_demo() -> void:
	Juego.ruta_partida = "user://partida_capturas_t09.json"
	Juego.nueva_partida("Leo")
	Juego.anadir_objeto("patata", 6)
	Juego.anadir_objeto("cobre", 5)
	Juego.anadir_objeto("nabo", 3)
	Juego.pausar_tiempo(true)
	Juego.minutos = 720
	Juego.estacion = 0
	Juego.clima = "sol"
	FotoCenital.olvidar()


func _ejecutar() -> void:
	var tut_antes := bool(Ajustes.valores.get("tutorial", true))
	Ajustes.valores["tutorial"] = false
	_iniciar_partida_demo()

	var solo_dos := OS.get_environment("MH_T09_FASE") != "antes"
	var res_lista: Array = [RESOLUCIONES[0]] if solo_dos else RESOLUCIONES

	# 1) Menú principal
	get_tree().current_scene = null
	var menu_ps := load("res://escenas/menu_principal.tscn") as PackedScene
	var menu := menu_ps.instantiate() as Control
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	for r: Dictionary in res_lista:
		await _poner_resolucion(r["tam"] as Vector2i)
		await _capturar(str(r["etiqueta"]), "menu")
	if is_instance_valid(menu):
		menu.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame

	# 2) Granja + Inventario
	await _poner_resolucion(Vector2i(1600, 900))
	Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	await _esperar_no_transicion()
	await _esperar_minimapa()
	for r: Dictionary in res_lista:
		await _poner_resolucion(r["tam"] as Vector2i)
		if not solo_dos:
			await _capturar(str(r["etiqueta"]), "granja")
		Interfaz.abrir_inventario()
		await get_tree().process_frame
		await get_tree().process_frame
		await _capturar(str(r["etiqueta"]), "inventario")
		Interfaz.cerrar_todo()
		await get_tree().process_frame

	# 3) Pueblo + Mapa grande (solo cuando se piden todas las resoluciones)
	if not solo_dos:
		Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
		await _esperar_no_transicion()
		await _esperar_minimapa()
		for r: Dictionary in RESOLUCIONES:
			await _poner_resolucion(r["tam"] as Vector2i)
			await _capturar(str(r["etiqueta"]), "pueblo")
			Interfaz.alternar_mapa()
			await get_tree().process_frame
			await get_tree().process_frame
			await _capturar(str(r["etiqueta"]), "mapa")
			Interfaz.cerrar_todo()
			await get_tree().process_frame

	await _quitar_escena()
	Interfaz.mostrar_hud(false)
	Ajustes.valores["tutorial"] = tut_antes
	get_window().size = Vector2i(1600, 900)
	print("CAPTURAS T09 COMPLETADAS")
	get_tree().quit(0)
