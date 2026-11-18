extends Node
## Prueba automatica T10-distribucion: icono, metadatos, creditos y licencias.

var _ok := 0
var _fallos := 0


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.ignore_time_scale = true
	tope.timeout.connect(func() -> void:
		printerr("TIMEOUT prueba_t10_distribucion (60 s)")
		get_tree().quit(1)
	)
	get_tree().root.add_child.call_deferred(tope)

	await _ejecutar()


func _verificar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("FALLO T10: ", msg)


func _ejecutar() -> void:
	# 1. Metadatos e iconos en ProjectSettings.
	_verificar(str(ProjectSettings.get_setting("application/config/name", "")) == "Mala Hierba", "nombre de aplicacion")
	_verificar(str(ProjectSettings.get_setting("application/config/version", "")) == "0.3.0", "version 0.3.0")
	_verificar(not str(ProjectSettings.get_setting("application/config/description", "")).is_empty(), "descripcion")
	_verificar(str(ProjectSettings.get_setting("application/config/icon", "")) == "res://assets/ui/icono.png", "icono png en project.godot")
	_verificar(str(ProjectSettings.get_setting("application/config/windows_native_icon", "")) == "res://assets/ui/icono.ico", "icono ico windows en project.godot")

	# 2. Recursos de icono (PNG 256x256 + ICO multi-tamano 16/32/48/64/128/256).
	var tex_icono := load("res://assets/ui/icono.png") as Texture2D
	_verificar(tex_icono != null and tex_icono.get_size() == Vector2(256, 256), "icono.png 256x256 valido")
	var tamanos_ico := _leer_tamanos_ico("res://assets/ui/icono.ico")
	for tam in [16, 32, 48, 64, 128, 256]:
		_verificar(tam in tamanos_ico, "icono.ico contiene tamano %d" % tam)

	# 3. Export presets Windows con metadatos e icono.
	var cf := ConfigFile.new()
	var err_cf := cf.load("res://export_presets.cfg")
	_verificar(err_cf == OK, "cargar export_presets.cfg")
	if err_cf == OK:
		_verificar(bool(cf.get_value("preset.0.options", "application/modify_resources", false)), "modify_resources activo")
		_verificar(str(cf.get_value("preset.0.options", "application/icon", "")) == "res://assets/ui/icono.ico", "icono ico en export_presets")
		_verificar(str(cf.get_value("preset.0.options", "application/file_version", "")) == "0.3.0.0", "file_version 0.3.0.0")
		_verificar(str(cf.get_value("preset.0.options", "application/product_version", "")) == "0.3.0", "product_version 0.3.0")
		_verificar("Cristian" in str(cf.get_value("preset.0.options", "application/company_name", "")), "autores en company_name")
		_verificar(str(cf.get_value("preset.0.options", "application/product_name", "")) == "Mala Hierba", "product_name")
		_verificar(not str(cf.get_value("preset.0.options", "application/copyright", "")).is_empty(), "copyright")

	# 4. CREDITOS.md y carpeta licencias/.
	_verificar(FileAccess.file_exists("res://CREDITOS.md"), "existe CREDITOS.md")
	var txt_cred := ""
	if FileAccess.file_exists("res://CREDITOS.md"):
		txt_cred = FileAccess.get_file_as_string("res://CREDITOS.md")
	_verificar("Godot Engine 4.7.2" in txt_cred and "MIT" in txt_cred, "creditos citan Godot MIT")
	_verificar("Poly Haven" in txt_cred and "CC0 1.0" in txt_cred, "creditos citan Poly Haven CC0")
	_verificar("Cristian, Juan José y Daniel" in txt_cred, "creditos citan autores")
	_verificar("PENDIENTE de verificación" in txt_cred, "creditos marcan recursos externos pendientes sin inventar licencia")

	for lic in ["res://licencias/godot_MIT.txt", "res://licencias/CC0-1.0.txt", "res://licencias/terceros_pendientes.txt"]:
		_verificar(FileAccess.file_exists(lic) and FileAccess.get_file_as_string(lic).length() > 120, "existe licencia %s" % lic)

	# 5. Escena MenuPrincipal: version visible, boton Creditos y modal interactivo.
	var menu := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
	add_child(menu)
	for _i in 4:
		await get_tree().process_frame

	var etiquetas := _recoger_etiquetas(menu)
	var tiene_pie := false
	for lb in etiquetas:
		if "Versión 0.3.0" in lb.text:
			tiene_pie = true
			break
	_verificar(tiene_pie, "pie del menu muestra Version 0.3.0")

	var btn_cred := _buscar_boton(menu, "Créditos")
	_verificar(btn_cred != null and btn_cred.visible, "boton Creditos visible en MenuPrincipal")

	var panel_cred := menu.get_node_or_null("PanelCreditos") as Control
	_verificar(panel_cred != null and not panel_cred.visible, "PanelCreditos oculto al inicio")

	if btn_cred != null and panel_cred != null:
		btn_cred.pressed.emit()
		for _i in 4:
			await get_tree().process_frame
		_verificar(panel_cred.visible, "PanelCreditos se abre al pulsar Creditos")

		var scroll := _buscar_scroll(panel_cred)
		_verificar(scroll != null and scroll.scroll_vertical == 0, "ScrollCreditos empieza arriba")
		var etiquetas_panel := _recoger_etiquetas(panel_cred)
		_verificar(etiquetas_panel.size() >= 15, "PanelCreditos contiene secciones de creditos (%d)" % etiquetas_panel.size())

		var ev_bajar := InputEventAction.new()
		ev_bajar.action = "ui_page_down"
		ev_bajar.pressed = true
		Input.parse_input_event(ev_bajar)
		for _i in 3:
			await get_tree().process_frame
		_verificar(scroll != null and scroll.scroll_vertical > 0, "ScrollCreditos responde a ui_page_down")

		var btn_cerrar := _buscar_boton(panel_cred, "Cerrar")
		_verificar(btn_cerrar != null and btn_cerrar.has_focus(), "boton Cerrar recibe el foco al abrir")

		# Cierre por accion ui_cancel (Esc / mando B) y restauracion de foco.
		var ev_esc := InputEventAction.new()
		ev_esc.action = "ui_cancel"
		ev_esc.pressed = true
		Input.parse_input_event(ev_esc)
		for _i in 4:
			await get_tree().process_frame
		_verificar(not panel_cred.visible, "PanelCreditos se cierra con ui_cancel")
		_verificar(btn_cred.has_focus(), "foco vuelve al boton Creditos tras cerrar con ui_cancel")

		# Reabrir y cerrar pulsando el boton Cerrar.
		btn_cred.pressed.emit()
		for _i in 3:
			await get_tree().process_frame
		if btn_cerrar != null:
			btn_cerrar.pressed.emit()
		for _i in 3:
			await get_tree().process_frame
		_verificar(not panel_cred.visible, "PanelCreditos se cierra con boton Cerrar")

	if is_instance_valid(menu):
		menu.queue_free()
	await get_tree().create_timer(0.15).timeout
	Audio._exit_tree()
	await get_tree().process_frame

	if _fallos == 0:
		print("PRUEBA T10 DISTRIBUCION OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		printerr("PRUEBA T10 DISTRIBUCION CON FALLOS: ok=%d fallos=%d" % [_ok, _fallos])
		get_tree().quit(1)


func _leer_tamanos_ico(ruta: String) -> Array[int]:
	var out: Array[int] = []
	var bytes := FileAccess.get_file_as_bytes(ruta)
	if bytes.size() < 6:
		return out
	var cuenta := bytes.decode_u16(4)
	for i in cuenta:
		var off := 6 + i * 16
		if off + 2 >= bytes.size():
			break
		var w := int(bytes[off])
		out.append(256 if w == 0 else w)
	return out


func _buscar_boton(nodo: Node, texto: String) -> Button:
	if nodo is Button and (nodo as Button).text == texto:
		return nodo as Button
	for hijo in nodo.get_children():
		var res := _buscar_boton(hijo, texto)
		if res != null:
			return res
	return null


func _buscar_scroll(nodo: Node) -> ScrollContainer:
	if nodo is ScrollContainer:
		return nodo as ScrollContainer
	for hijo in nodo.get_children():
		var res := _buscar_scroll(hijo)
		if res != null:
			return res
	return null


func _recoger_etiquetas(nodo: Node) -> Array[Label]:
	var res: Array[Label] = []
	if nodo is Label:
		res.append(nodo as Label)
	for hijo in nodo.get_children():
		res.append_array(_recoger_etiquetas(hijo))
	return res
