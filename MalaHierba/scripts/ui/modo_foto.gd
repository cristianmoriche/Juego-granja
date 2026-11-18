class_name ModoFoto
extends Control
## Modo foto (P / Capturar): pausa el mundo, cámara libre en torno a Leo, FOV, DoF, exposición, inclinación, filtros y PNG.

signal cerrado

const MAX_RADIO := 14.0
const VEL_BASE := 6.5
const FILTROS := [
	{"id": "ninguno", "nombre": "Natural", "tint": Color(1.0, 1.0, 1.0, 0.0)},
	{"id": "atardecer", "nombre": "Atardecer cálido", "tint": Color(1.0, 0.62, 0.26, 0.14)},
	{"id": "bosque", "nombre": "Bosque fresco", "tint": Color(0.28, 0.72, 0.48, 0.12)},
	{"id": "contraste", "nombre": "Día vívido", "tint": Color(0.95, 0.92, 0.80, 0.08)},
	{"id": "sepia", "nombre": "Sepia rural", "tint": Color(0.68, 0.45, 0.22, 0.24)},
	{"id": "nostalgia", "nombre": "Crepúsculo azul", "tint": Color(0.24, 0.44, 0.78, 0.16)},
]

var ruta_capturas_personalizada: String = ""

var _cam_orig: Camera3D = null
var _cam_foto: Camera3D = null
var _atributos := CameraAttributesPractical.new()
var _ancla: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll_deg: float = 0.0
var _fov: float = 70.0
var _exposicion: float = 1.0
var _dof_activo: bool = false
var _dof_distancia: float = 6.0
var _dof_cantidad: float = 0.12
var _filtro_idx: int = 0
var _ocultar_leo: bool = false
var _ocultar_ui: bool = false
var _leo_vis_antes: bool = true
var _hud_vis_antes: bool = true
var _arbellos_rotando := false
var _ultima_ruta: String = ""

var _rect_filtro: ColorRect
var _panel_ui: PanelContainer
var _s_fov: HSlider
var _l_fov: Label
var _s_exp: HSlider
var _l_exp: Label
var _s_roll: HSlider
var _l_roll: Label
var _chk_dof: CheckBox
var _s_dist: HSlider
var _l_dist: Label
var _s_blur: HSlider
var _l_blur: Label
var _opt_filtro: OptionButton
var _chk_leo: CheckBox
var _l_estado: Label
var _b_capturar: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_rect_filtro = ColorRect.new()
	_rect_filtro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect_filtro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_filtro.color = Color(1, 1, 1, 0)
	add_child(_rect_filtro)

	_panel_ui = PanelContainer.new()
	_panel_ui.anchor_left = 1.0
	_panel_ui.anchor_right = 1.0
	_panel_ui.anchor_top = 0.5
	_panel_ui.anchor_bottom = 0.5
	_panel_ui.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel_ui.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel_ui.offset_right = -18
	Estilo.estilo_panel(_panel_ui, Color(0.08, 0.06, 0.05, 0.90), Estilo.COLOR_BORDE, 18)
	add_child(_panel_ui)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.add_theme_constant_override("separation", 8)
	_panel_ui.add_child(v)

	v.add_child(Estilo.etiqueta("Modo foto", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO))
	var ayuda := Estilo.etiqueta("WASD / Q·E mover cámara · Arrastra clic der. para girar · H oculta menús", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ayuda)
	v.add_child(HSeparator.new())

	_l_fov = _crear_slider(v, "Campo visión", 25.0, 95.0, 1.0, 70.0, func(val: float) -> void:
		_fov = val
		_aplicar_camara())
	_s_fov = v.get_child(v.get_child_count() - 1) as HSlider

	_l_exp = _crear_slider(v, "Exposición", 0.5, 2.2, 0.05, 1.0, func(val: float) -> void:
		_exposicion = val
		_aplicar_camara())
	_s_exp = v.get_child(v.get_child_count() - 1) as HSlider

	_l_roll = _crear_slider(v, "Inclinación", -25.0, 25.0, 1.0, 0.0, func(val: float) -> void:
		_roll_deg = val
		_aplicar_camara())
	_s_roll = v.get_child(v.get_child_count() - 1) as HSlider

	_chk_dof = CheckBox.new()
	_chk_dof.text = "Profundidad de campo (DoF)"
	_chk_dof.toggled.connect(func(on: bool) -> void:
		_dof_activo = on
		_aplicar_camara())
	v.add_child(_chk_dof)

	_l_dist = _crear_slider(v, "Distancia enfoque (m)", 1.5, 45.0, 0.5, 6.0, func(val: float) -> void:
		_dof_distancia = val
		_aplicar_camara())
	_s_dist = v.get_child(v.get_child_count() - 1) as HSlider

	_l_blur = _crear_slider(v, "Desenfoque fondo", 0.02, 0.35, 0.01, 0.12, func(val: float) -> void:
		_dof_cantidad = val
		_aplicar_camara())
	_s_blur = v.get_child(v.get_child_count() - 1) as HSlider

	var hf := HBoxContainer.new()
	v.add_child(hf)
	hf.add_child(Estilo.etiqueta("Filtro:", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO))
	_opt_filtro = OptionButton.new()
	_opt_filtro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in FILTROS.size():
		_opt_filtro.add_item(str(FILTROS[i]["nombre"]), i)
	_opt_filtro.item_selected.connect(func(idx: int) -> void:
		poner_filtro(idx))
	hf.add_child(_opt_filtro)

	_chk_leo = CheckBox.new()
	_chk_leo.text = "Ocultar a Leo"
	_chk_leo.toggled.connect(func(on: bool) -> void:
		poner_ocultar_leo(on))
	v.add_child(_chk_leo)

	var fila_b := HBoxContainer.new()
	fila_b.add_theme_constant_override("separation", 8)
	v.add_child(fila_b)
	_b_capturar = Estilo.boton("Capturar PNG", 160.0)
	_b_capturar.pressed.connect(func() -> void: capturar_foto())
	fila_b.add_child(_b_capturar)
	var b_ui := Estilo.boton("Ocultar UI (H)", 150.0)
	b_ui.pressed.connect(func() -> void: alternar_ui())
	fila_b.add_child(b_ui)

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 8)
	v.add_child(pie)
	var b_reset := Estilo.boton("Restablecer", 145.0)
	b_reset.pressed.connect(_restablecer_ajustes)
	pie.add_child(b_reset)
	var b_salir := Estilo.boton("Salir (P / Esc)", 165.0)
	b_salir.pressed.connect(cerrar_panel)
	pie.add_child(b_salir)

	_l_estado = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO)
	_l_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_l_estado)


func _crear_slider(padre: VBoxContainer, nombre: String, min_v: float, max_v: float, paso: float, def_v: float, cb: Callable) -> Label:
	var h := HBoxContainer.new()
	padre.add_child(h)
	var ln := Estilo.etiqueta(nombre, Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ln)
	var lv := Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	h.add_child(lv)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = paso
	s.value = def_v
	s.value_changed.connect(cb)
	padre.add_child(s)
	return lv


func abrir() -> void:
	if visible:
		return
	var j := Escenas.jugador()
	_cam_orig = get_viewport().get_camera_3d()
	if j == null or _cam_orig == null:
		return
	Audio.reproducir("ui_menu")
	_ancla = j.global_position + Vector3(0.0, 1.2, 0.0)
	_cam_foto = Camera3D.new()
	_cam_foto.name = "CamaraModoFoto"
	_cam_foto.near = 0.05
	_cam_foto.far = _cam_orig.far
	get_tree().root.add_child(_cam_foto)
	_cam_foto.global_transform = _cam_orig.global_transform
	var euler := _cam_foto.global_basis.get_euler()
	_pitch = clampf(euler.x, deg_to_rad(-80.0), deg_to_rad(80.0))
	_yaw = euler.y
	_fov = clampf(_cam_orig.fov, 25.0, 95.0)
	_roll_deg = 0.0
	_exposicion = 1.0
	_dof_activo = false
	_dof_distancia = 6.0
	_dof_cantidad = 0.12
	_filtro_idx = 0
	_ocultar_leo = false
	_ocultar_ui = false
	_leo_vis_antes = true
	var mod_leo := j.get_node_or_null("Modelo") as Node3D
	if mod_leo != null:
		_leo_vis_antes = mod_leo.visible
	var vista_leo: Variant = j.get("_vista_leo")
	if vista_leo != null and vista_leo.has_method("mostrar_primera"):
		vista_leo.call("mostrar_primera", false)
	for prop_1p: String in ["_plato_primera", "_farol_primera", "_antorcha_primera"]:
		var n1 := j.get(prop_1p) as Node3D
		if n1 != null and is_instance_valid(n1):
			n1.visible = false
	_cam_foto.attributes = _atributos
	_cam_foto.current = true
	_sincronizar_ui()
	_aplicar_camara()
	_l_estado.text = ""
	visible = true
	_panel_ui.visible = true
	var hud_n := Interfaz.get("_hud") as Control
	if hud_n != null:
		_hud_vis_antes = hud_n.visible
		hud_n.visible = false
	get_tree().paused = true
	Juego.pausar_tiempo(true)
	_b_capturar.grab_focus.call_deferred()


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	poner_ocultar_leo(false)
	var j := Escenas.jugador()
	if j != null:
		var mod_leo := j.get_node_or_null("Modelo") as Node3D
		if mod_leo != null:
			mod_leo.visible = _leo_vis_antes
		var vista_leo: Variant = j.get("_vista_leo")
		if vista_leo != null and vista_leo.has_method("mostrar_primera"):
			vista_leo.call("mostrar_primera", j.camara.cabeza_oculta)
		if j.has_method("_actualizar_visibilidad_farol"):
			j.call("_actualizar_visibilidad_farol")
	_rect_filtro.color = Color(1, 1, 1, 0)
	var hud_n := Interfaz.get("_hud") as Control
	if hud_n != null:
		hud_n.visible = _hud_vis_antes
	if is_instance_valid(_cam_orig):
		_cam_orig.current = true
	if is_instance_valid(_cam_foto):
		_cam_foto.queue_free()
		_cam_foto = null
	get_tree().paused = false
	Juego.pausar_tiempo(false)
	cerrado.emit()


func camara_foto() -> Camera3D:
	return _cam_foto


func poner_fov(v: float) -> void:
	_fov = clampf(v, 25.0, 95.0)
	if _s_fov != null:
		_s_fov.value = _fov
	_aplicar_camara()


func poner_exposicion(v: float) -> void:
	_exposicion = clampf(v, 0.5, 2.2)
	if _s_exp != null:
		_s_exp.value = _exposicion
	_aplicar_camara()


func poner_inclinacion(grados: float) -> void:
	_roll_deg = clampf(grados, -25.0, 25.0)
	if _s_roll != null:
		_s_roll.value = _roll_deg
	_aplicar_camara()


func poner_dof(activo: bool, distancia: float = 6.0, cantidad: float = 0.12) -> void:
	_dof_activo = activo
	_dof_distancia = clampf(distancia, 1.5, 45.0)
	_dof_cantidad = clampf(cantidad, 0.02, 0.35)
	if _chk_dof != null:
		_chk_dof.button_pressed = activo
		_s_dist.value = _dof_distancia
		_s_blur.value = _dof_cantidad
	_aplicar_camara()


func poner_filtro(idx: int) -> void:
	_filtro_idx = clampi(idx, 0, FILTROS.size() - 1)
	if _opt_filtro != null:
		_opt_filtro.select(_filtro_idx)
	_rect_filtro.color = FILTROS[_filtro_idx]["tint"]


func poner_ocultar_leo(ocultar: bool) -> void:
	_ocultar_leo = ocultar
	var j := Escenas.jugador()
	if j != null:
		var mod_leo := j.get_node_or_null("Modelo") as Node3D
		if mod_leo != null:
			mod_leo.visible = not ocultar and _leo_vis_antes
		var plato := j.get("_plato_primera") as Node3D
		if plato != null and is_instance_valid(plato):
			plato.visible = not ocultar


func alternar_ui() -> void:
	_ocultar_ui = not _ocultar_ui
	_panel_ui.visible = not _ocultar_ui


func ultima_ruta_captura() -> String:
	return _ultima_ruta


func directorio_capturas() -> String:
	if not ruta_capturas_personalizada.is_empty():
		return ruta_capturas_personalizada
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics.is_empty():
		return OS.get_user_data_dir().path_join("capturas")
	return pics.path_join("MalaHierba")


func capturar_foto(ruta_archivo: String = "") -> String:
	var dir_sal := directorio_capturas()
	DirAccess.make_dir_recursive_absolute(dir_sal)
	var dest := ruta_archivo
	if dest.is_empty():
		var ts := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		dest = dir_sal.path_join("MalaHierba_%s.png" % ts)
	elif not dest.is_absolute_path():
		dest = dir_sal.path_join(dest)

	var ui_prev := _panel_ui.visible
	_panel_ui.visible = false
	var hud_n := Interfaz.get("_hud") as Control
	var hud_vis := hud_n.visible if hud_n != null else false
	if hud_n != null:
		hud_n.visible = false
	var err := ERR_SKIP
	if DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		err = img.save_png(dest)
	if hud_n != null:
		hud_n.visible = hud_vis
	_panel_ui.visible = ui_prev
	if err == OK or DisplayServer.get_name() == "headless":
		_ultima_ruta = dest
		_l_estado.text = "Guardada en: " + dest
		Juego.mensaje.emit("Foto guardada en: " + dest)
		Audio.reproducir("ui_clic")
		return dest
	_l_estado.text = "No se pudo guardar la foto."
	return ""


func _restablecer_ajustes() -> void:
	poner_fov(70.0)
	poner_exposicion(1.0)
	poner_inclinacion(0.0)
	poner_dof(false, 6.0, 0.12)
	poner_filtro(0)
	if _chk_leo != null:
		_chk_leo.button_pressed = false
	poner_ocultar_leo(false)


func _sincronizar_ui() -> void:
	if _s_fov != null:
		_s_fov.value = _fov
		_s_exp.value = _exposicion
		_s_roll.value = _roll_deg
		_chk_dof.button_pressed = _dof_activo
		_s_dist.value = _dof_distancia
		_s_blur.value = _dof_cantidad
		_opt_filtro.select(_filtro_idx)
		_chk_leo.button_pressed = _ocultar_leo


func _aplicar_camara() -> void:
	if not is_instance_valid(_cam_foto):
		return
	_cam_foto.fov = _fov
	_cam_foto.rotation = Vector3(_pitch, _yaw, deg_to_rad(_roll_deg))
	_atributos.exposure_multiplier = _exposicion
	_atributos.dof_blur_far_enabled = _dof_activo
	_atributos.dof_blur_far_distance = _dof_distancia
	_atributos.dof_blur_amount = _dof_cantidad
	if _l_fov != null:
		_l_fov.text = "%d°" % roundi(_fov)
		_l_exp.text = "%.2f" % _exposicion
		_l_roll.text = "%d°" % roundi(_roll_deg)
		_l_dist.text = "%.1f" % _dof_distancia
		_l_blur.text = "%.2f" % _dof_cantidad


func _process(delta: float) -> void:
	if not visible or not is_instance_valid(_cam_foto):
		return
	var mov := Input.get_vector("mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo")
	var subir := 0.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		subir += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		subir -= 1.0
	var vel := VEL_BASE * (1.8 if Input.is_action_pressed("correr") else 1.0)
	if mov.length_squared() > 0.001 or absf(subir) > 0.01:
		var frente := -_cam_foto.global_basis.z
		var der := _cam_foto.global_basis.x
		var dir3 := (der * mov.x - frente * mov.y + Vector3.UP * subir)
		var nueva := _cam_foto.global_position + dir3 * vel * delta
		nueva = _ancla + (nueva - _ancla).limit_length(MAX_RADIO)
		nueva.y = maxf(nueva.y, _ancla.y - 0.95)
		_cam_foto.global_position = nueva
	var giro_mando := Input.get_vector("camara_izquierda", "camara_derecha", "camara_arriba", "camara_abajo")
	if giro_mando.length_squared() > 0.001:
		_yaw = wrapf(_yaw - giro_mando.x * 1.8 * delta, -PI, PI)
		_pitch = clampf(_pitch - giro_mando.y * 1.8 * delta, deg_to_rad(-82.0), deg_to_rad(82.0))
		_aplicar_camara()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("modo_foto") or event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_H or ek.physical_keycode == KEY_H:
			alternar_ui()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_arbellos_rotando = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			poner_fov(_fov - 3.0)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			poner_fov(_fov + 3.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _arbellos_rotando:
		var mm := event as InputEventMouseMotion
		_yaw = wrapf(_yaw - mm.relative.x * 0.0045, -PI, PI)
		_pitch = clampf(_pitch - mm.relative.y * 0.0045, deg_to_rad(-82.0), deg_to_rad(82.0))
		_aplicar_camara()
