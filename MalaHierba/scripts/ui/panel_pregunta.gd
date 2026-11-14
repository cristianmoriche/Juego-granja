class_name PanelPregunta
extends Control
## Pregunta con opciones: botones en columna; también valen las teclas 1–9.

var _caja: VBoxContainer
var _texto: Label
var _botones: Array[Button] = []
var _al_elegir: Callable = Callable()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.45)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.95), Estilo.COLOR_BORDE, 26)
	add_child(p)
	_caja = VBoxContainer.new()
	_caja.add_theme_constant_override("separation", 12)
	_caja.custom_minimum_size = Vector2(560, 0)
	p.add_child(_caja)
	_texto = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(560, 0)
	_caja.add_child(_texto)


func abrir(texto: String, opciones: Array, al_elegir: Callable) -> void:
	for b in _botones:
		_caja.remove_child(b)
		b.queue_free()
	_botones.clear()
	_texto.text = texto
	_al_elegir = al_elegir
	for i in opciones.size():
		var opcion: Variant = opciones[i]
		var texto_opcion := str(opcion.get("texto", "")) if opcion is Dictionary else str(opcion)
		var b := Estilo.boton("%d.  %s" % [i + 1, texto_opcion])
		if opcion is Dictionary and not str(opcion.get("icono", "")).is_empty():
			b.icon = Datos.icono(str(opcion["icono"]))
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 48)
			b.add_theme_constant_override("h_separation", 12)
			b.custom_minimum_size.y = 60
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_elegir.bind(i))
		_caja.add_child(b)
		_botones.append(b)
	visible = true
	_enfocar_opcion_actual.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)


## La pregunta puede cambiar varias veces en un fotograma: enfoca solo la opción vigente.
func _enfocar_opcion_actual() -> void:
	if is_inside_tree() and is_visible_in_tree() and not _botones.is_empty():
		var boton := _botones[0]
		if is_instance_valid(boton) and boton.is_inside_tree() and not boton.is_queued_for_deletion():
			boton.grab_focus()


func _elegir(i: int) -> void:
	visible = false
	var cb := _al_elegir
	_al_elegir = Callable()
	if cb.is_valid():
		cb.call(i)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			var i := int(k) - int(KEY_1)
			if i < _botones.size():
				_elegir(i)
				get_viewport().set_input_as_handled()
