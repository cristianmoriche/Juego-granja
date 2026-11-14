extends Node
## Captura visual para T10-distribucion (menu principal con version 0.2.0 + pantalla de creditos).

const RUTA_DESPUES := "res://../gestion/noche-codex/capturas/T10-distribucion/despues"


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.ignore_time_scale = true
	tope.timeout.connect(func() -> void:
		printerr("TIMEOUT capturas_t10 (60 s)")
		get_tree().quit(1)
	)
	get_tree().root.add_child.call_deferred(tope)

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var dir_abs := ProjectSettings.globalize_path(RUTA_DESPUES)
	DirAccess.make_dir_recursive_absolute(dir_abs)

	var escena := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
	add_child(escena)

	for _i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout

	var img_menu := get_viewport().get_texture().get_image()
	var err1 := img_menu.save_png(dir_abs.path_join("menu.png"))
	print("CAPTURA menu.png: err=", err1, " tam=", img_menu.get_size())

	var btn_cred := _buscar_boton(escena, "Créditos")
	if btn_cred == null:
		printerr("No se encontro boton Creditos")
		get_tree().quit(1)
		return
	btn_cred.pressed.emit()

	for _i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout

	var img_cred := get_viewport().get_texture().get_image()
	var err2 := img_cred.save_png(dir_abs.path_join("creditos.png"))
	print("CAPTURA creditos.png: err=", err2, " tam=", img_cred.get_size())

	get_tree().quit(0)


func _buscar_boton(nodo: Node, texto: String) -> Button:
	if nodo is Button and (nodo as Button).text == texto:
		return nodo as Button
	for hijo in nodo.get_children():
		var res := _buscar_boton(hijo, texto)
		if res != null:
			return res
	return null
