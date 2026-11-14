extends Control
## Intro: la carta de la abuela Rosa, en dos páginas. «Empezar» lleva a Leo a la granja.

const FONDO := "res://assets/ui/fondo_menu.png"
const PARRAFOS_PRIMERA_PAGINA := 4

var _pagina: int = 0
var _paginas: Array[PackedStringArray] = []
var _texto: RichTextLabel
var _b_anterior: Button
var _b_siguiente: Button
var _l_pagina: Label


func _ready() -> void:
	theme = Estilo.tema()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Interfaz.mostrar_hud(false)
	_preparar_paginas()
	_construir()
	_mostrar_pagina(0)


func _preparar_paginas() -> void:
	var todos: Array = Datos.texto("carta.parrafos", [])
	var a := PackedStringArray()
	var b := PackedStringArray()
	for i in todos.size():
		var t := str(todos[i]).replace("{nombre}", Juego.nombre_jugador)
		if i < PARRAFOS_PRIMERA_PAGINA:
			a.append(t)
		else:
			b.append(t)
	_paginas = [a, b]


func _construir() -> void:
	var fondo := TextureRect.new()
	if ResourceLoader.exists(FONDO):
		fondo.texture = load(FONDO) as Texture2D
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(fondo)
	var velo := ColorRect.new()
	velo.color = Color(0.03, 0.02, 0.015, 0.82)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(velo)

	var papel := PanelContainer.new()
	papel.anchor_left = 0.5
	papel.anchor_right = 0.5
	papel.anchor_top = 0.5
	papel.anchor_bottom = 0.5
	papel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	papel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := Estilo.caja(Color(0.93, 0.87, 0.72), Color(0.55, 0.38, 0.2), 4, 6, 44)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	papel.add_theme_stylebox_override("panel", sb)
	add_child(papel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	papel.add_child(v)

	_texto = RichTextLabel.new()
	_texto.bbcode_enabled = false
	_texto.fit_content = false
	_texto.scroll_active = false
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto.custom_minimum_size = Vector2(900, 470)
	var letra := SystemFont.new()
	letra.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Segoe Script", "Segoe UI"])
	_texto.add_theme_font_override("normal_font", letra)
	_texto.add_theme_font_size_override("normal_font_size", 30)
	_texto.add_theme_color_override("default_color", Color(0.2, 0.12, 0.07))
	v.add_child(_texto)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	v.add_child(fila)
	_b_anterior = Estilo.boton("◂ Anterior", 190)
	_b_anterior.pressed.connect(func() -> void: _mostrar_pagina(_pagina - 1))
	fila.add_child(_b_anterior)
	_l_pagina = Estilo.etiqueta("", Estilo.TAM_TEXTO, Color(0.4, 0.28, 0.16))
	_l_pagina.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_l_pagina.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_pagina.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(_l_pagina)
	_b_siguiente = Estilo.boton("Siguiente ▸", 220)
	_b_siguiente.pressed.connect(_siguiente)
	fila.add_child(_b_siguiente)


func _mostrar_pagina(p: int) -> void:
	_pagina = clampi(p, 0, _paginas.size() - 1)
	_texto.text = "\n\n".join(_paginas[_pagina])
	_b_anterior.visible = _pagina > 0
	_b_siguiente.text = "Empezar" if _pagina == _paginas.size() - 1 else "Siguiente ▸"
	_l_pagina.text = "%d / %d" % [_pagina + 1, _paginas.size()]
	_b_siguiente.grab_focus.call_deferred()


func _siguiente() -> void:
	if _pagina < _paginas.size() - 1:
		_mostrar_pagina(_pagina + 1)
	else:
		_empezar()


func _empezar() -> void:
	Juego.mapa_actual = "granja"
	Juego.guardar()
	Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
