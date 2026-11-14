class_name PanelDialogo
extends Control
## Cuadro de diálogo: nombre y texto que aparece letra a letra; E, espacio o clic para seguir.

signal terminado

const LETRAS_POR_SEGUNDO := 55.0

var _nombre: Label
var _texto: RichTextLabel
var _icono: TextureRect
var _pista: Label
var _lineas: Array = []
var _indice: int = 0
var _nombre_base: String = ""
var _avance: float = 0.0
var _panel: PanelContainer
var _al_terminar: Callable = Callable()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var p := PanelContainer.new()
	_panel = p
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -560
	p.offset_right = 560
	p.offset_top = -250
	p.offset_bottom = -26
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.93), Estilo.COLOR_BORDE, 22)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	_nombre = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	v.add_child(_nombre)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 18)
	fila.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fila)
	_icono = TextureRect.new()
	_icono.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icono.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icono.custom_minimum_size = Vector2(80, 80)
	_icono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icono.visible = false
	fila.add_child(_icono)
	_texto = RichTextLabel.new()
	_texto.bbcode_enabled = false
	_texto.fit_content = false
	_texto.scroll_active = false
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(0, 100)
	_texto.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texto.add_theme_font_size_override("normal_font_size", 27)
	fila.add_child(_texto)
	_pista = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_pista)
	_actualizar_tamano()
	Ajustes.cambiado.connect(_actualizar_tamano)


## Conserva el espacio de lectura al crecer tanto la letra como el número de líneas.
func _actualizar_tamano(clave: String = "") -> void:
	if not clave.is_empty() and clave != "texto":
		return
	var factor: float = [1.0, 1.18, 1.35][int(Ajustes.valores.texto)]
	_panel.offset_top = -250.0 * factor * factor


func abrir(nombre: String, lineas: Array, al_terminar: Callable) -> void:
	if lineas.is_empty():
		if al_terminar.is_valid():
			al_terminar.call()
		return
	_nombre_base = nombre
	_lineas = lineas
	_al_terminar = al_terminar
	_indice = -1
	visible = true
	_siguiente()


func _siguiente() -> void:
	_indice += 1
	if _indice >= _lineas.size():
		_cerrar()
		return
	var l: Variant = _lineas[_indice]
	var quien := _nombre_base
	var texto := ""
	_icono.visible = false
	if l is Dictionary:
		var d: Dictionary = l
		quien = str(d.get("nombre", _nombre_base))
		texto = str(d.get("texto", ""))
		var id_icono := str(d.get("icono", ""))
		if not id_icono.is_empty():
			_icono.texture = Datos.icono(id_icono)
			_icono.visible = true
	else:
		texto = str(l)
	_nombre.text = quien
	_nombre.visible = not quien.is_empty()
	_texto.text = texto
	_texto.visible_characters = 0
	_avance = 0.0
	_pista.text = ""


func _cerrar() -> void:
	visible = false
	_lineas = []
	var cb := _al_terminar
	_al_terminar = Callable()
	terminado.emit()
	if cb.is_valid():
		cb.call()


func _process(delta: float) -> void:
	if not visible:
		return
	var total := _texto.get_total_character_count()
	if _texto.visible_characters < total:
		_avance += LETRAS_POR_SEGUNDO * delta
		_texto.visible_characters = mini(int(_avance), total)
	else:
		_pista.text = Ajustes.pista("interactuar") + (" ▸ seguir" if _indice < _lineas.size() - 1 else " ▸ cerrar")


func _avanzar() -> void:
	var total := _texto.get_total_character_count()
	if _texto.visible_characters < total:
		_texto.visible_characters = total      # primero se completa la frase
		_avance = float(total)
	else:
		_siguiente()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_avanzar()
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interactuar") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.is_action_pressed("usar")):
		_avanzar()
		get_viewport().set_input_as_handled()
