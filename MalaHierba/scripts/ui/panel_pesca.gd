class_name PanelPesca
extends Control
## Minijuego interactivo de pesca avanzada (tensión del sedal, tirones del pez, cansancio y cebos) (H11).

signal finalizada(resultado: String, ejemplar: Dictionary)

var _activo: bool = false
var _zona: String = "bosque_norte"
var _estado: Dictionary = {}
var _ejemplar: Dictionary = {}
var _cebo_usado: String = ""
var _t_audio_ten: float = 0.0
var _solapado_cebos: bool = false

var _marco: PanelContainer
var _l_titulo: Label
var _l_aviso: Label
var _l_especie_pista: Label
var _barra_tension: ProgressBar
var _barra_cansancio: ProgressBar
var _l_cebo: Label
var _panel_cebos: PanelContainer
var _fila_cebos: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_marco = PanelContainer.new()
	_marco.anchor_left = 0.5
	_marco.anchor_right = 0.5
	_marco.anchor_top = 0.72
	_marco.anchor_bottom = 0.72
	_marco.offset_left = -225
	_marco.offset_right = 225
	_marco.offset_top = -95
	_marco.offset_bottom = 85
	_marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Estilo.estilo_panel(_marco, Color(0.055, 0.068, 0.082, 0.90), Color(0.32, 0.62, 0.74), 14)
	add_child(_marco)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_marco.add_child(v)

	var cab := HBoxContainer.new()
	v.add_child(cab)
	_l_titulo = Estilo.etiqueta("¡Ha picado!", Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
	_l_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_l_titulo)
	_l_cebo = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	cab.add_child(_l_cebo)

	_l_aviso = Estilo.etiqueta("Mantén Usar / Clic izq. para recoger", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
	_l_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_l_aviso)

	v.add_child(Estilo.etiqueta("Tensión del sedal", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	_barra_tension = ProgressBar.new()
	_barra_tension.max_value = 1.0
	_barra_tension.show_percentage = false
	_barra_tension.custom_minimum_size = Vector2(400, 14)
	_barra_tension.add_theme_stylebox_override("fill", Estilo.caja(Color(0.35, 0.85, 0.45), Color.TRANSPARENT, 0, 3, 0))
	v.add_child(_barra_tension)

	v.add_child(Estilo.etiqueta("Resistencia restante del pez", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	_barra_cansancio = ProgressBar.new()
	_barra_cansancio.max_value = 1.0
	_barra_cansancio.show_percentage = false
	_barra_cansancio.custom_minimum_size = Vector2(400, 12)
	_barra_cansancio.add_theme_stylebox_override("fill", Estilo.caja(Color(0.36, 0.72, 0.96), Color.TRANSPARENT, 0, 3, 0))
	v.add_child(_barra_cansancio)

	_l_especie_pista = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_l_especie_pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_l_especie_pista)

	# Subpanel modal compacto de selección y fabricación de cebos
	_panel_cebos = PanelContainer.new()
	_panel_cebos.anchor_left = 0.5
	_panel_cebos.anchor_right = 0.5
	_panel_cebos.anchor_top = 0.5
	_panel_cebos.anchor_bottom = 0.5
	_panel_cebos.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel_cebos.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(_panel_cebos, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 20)
	_panel_cebos.hide()
	add_child(_panel_cebos)

	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 10)
	vc.custom_minimum_size = Vector2(560, 0)
	_panel_cebos.add_child(vc)
	vc.add_child(Estilo.etiqueta("Cebos de pesca (seleccionar o fabricar)", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO))
	_fila_cebos = VBoxContainer.new()
	_fila_cebos.add_theme_constant_override("separation", 8)
	vc.add_child(_fila_cebos)
	var b_cer := Estilo.boton("Cerrar (Esc)", 150)
	b_cer.pressed.connect(cerrar_cebos)
	vc.add_child(b_cer)

	Juego.pesca_cambiada.connect(_refrescar_cebos)


func esta_activa() -> bool:
	return _activo or _panel_cebos.visible


func estado_lucha() -> Dictionary:
	return _estado


func abrir_cebos() -> void:
	_activo = false
	_marco.visible = false
	_panel_cebos.visible = true
	visible = true
	_solapado_cebos = true
	_refrescar_cebos()
	Interfaz.limitar_foco.call_deferred(_panel_cebos)


func cerrar_cebos() -> void:
	_panel_cebos.visible = false
	_solapado_cebos = false
	visible = _activo


func iniciar_pesca(zona: String, ejemplar: Dictionary, cebo: String) -> void:
	_panel_cebos.visible = false
	_solapado_cebos = false
	_zona = zona
	_ejemplar = ejemplar
	_cebo_usado = cebo
	_estado = PescaAvanzada.nuevo_estado_lucha(str(ejemplar["id"]), Juego.nivel_habilidad("pesca"))
	_activo = true
	_marco.visible = true
	visible = true
	_t_audio_ten = 0.0
	_l_cebo.text = "Cebo: %s" % (Datos.nombre_objeto(cebo) if not cebo.is_empty() else "Sin cebo")
	_l_especie_pista.text = "Calibre estimado: %s" % str(ejemplar.get("rareza", "Común"))
	Audio.reproducir("pesca_lance")


func cancelar() -> void:
	_activo = false
	_marco.visible = false
	visible = _solapado_cebos


func _unhandled_input(ev: InputEvent) -> void:
	if _panel_cebos.visible and (ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pausa")):
		cerrar_cebos()
		get_viewport().set_input_as_handled()
		return
	if _activo and ev.is_action_pressed("ui_cancel"):
		cancelar()
		finalizada.emit("cancelado", {})
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _activo:
		return
	var recogiendo := Input.is_action_pressed("usar") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_estado = PescaAvanzada.simular_paso(_estado, recogiendo, delta)
	var ten := clampf(float(_estado.get("tension", 0.0)), 0.0, 1.0)
	var can := clampf(float(_estado.get("cansancio", 0.0)), 0.0, 1.0)
	var tir := bool(_estado.get("tirando", false))
	_barra_tension.value = ten
	_barra_cansancio.value = can

	var fill := _barra_tension.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		if ten > 0.78:
			fill.bg_color = Color(0.95, 0.25, 0.20)
		elif ten > 0.50:
			fill.bg_color = Color(0.95, 0.74, 0.22)
		else:
			fill.bg_color = Color(0.32, 0.85, 0.44)

	if tir:
		_l_aviso.text = "¡TIRÓN FUERTE! Suelta carrete para no romper"
		_l_aviso.modulate = Color(1.0, 0.62, 0.38)
		_t_audio_ten -= delta
		if _t_audio_ten <= 0.0 and recogiendo:
			_t_audio_ten = 0.28
			Audio.reproducir("pesca_tension")
			Input.start_joy_vibration(0, 0.25, 0.65, 0.14)
	else:
		_l_aviso.text = "Pez fatigado · Mantén clic izq. o Usar para recoger"
		_l_aviso.modulate = Color(0.75, 0.96, 0.82)

	var res := str(_estado.get("resultado", "curso"))
	if res != "curso":
		_activo = false
		_marco.visible = false
		visible = false
		finalizada.emit(res, _ejemplar)


func _refrescar_cebos() -> void:
	if not _panel_cebos.visible:
		return
	for h in _fila_cebos.get_children():
		h.queue_free()
	var activo := Juego.cebo_activo()
	for rec: Dictionary in PescaAvanzada.RECETAS_CEBO:
		var cid := str(rec["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var b_eq := Estilo.boton("  %s (×%d)" % [Datos.nombre_objeto(cid), Juego.cantidad(cid)], 260)
		b_eq.icon = Datos.icono(cid)
		b_eq.add_theme_constant_override("icon_max_width", 26)
		b_eq.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b_eq.disabled = (Juego.cantidad(cid) <= 0 or activo == cid)
		b_eq.pressed.connect(func() -> void:
			Juego.elegir_cebo(cid)
			_refrescar_cebos())
		row.add_child(b_eq)

		var partes: Array[String] = []
		var puede := true
		for ing: Variant in rec.get("ingredientes", []):
			if ing is Dictionary:
				var d := ing as Dictionary
				var iid := str(d["id"])
				var nec := int(d["cantidad"])
				if Juego.cantidad(iid) < nec:
					puede = false
				partes.append("%d×%s" % [nec, Datos.nombre_objeto(iid)])
		var b_fab := Estilo.boton("Fabricar (+%d) [%s]" % [int(rec["entrega"]), ", ".join(PackedStringArray(partes))], 275)
		b_fab.disabled = not puede
		b_fab.pressed.connect(func() -> void:
			if Juego.fabricar_cebo(cid):
				Interfaz.mensaje("Fabricas %d × %s." % [int(rec["entrega"]), Datos.nombre_objeto(cid)], cid)
			_refrescar_cebos())
		row.add_child(b_fab)
		_fila_cebos.add_child(row)
