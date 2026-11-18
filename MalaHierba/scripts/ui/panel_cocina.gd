class_name PanelCocina
extends Control
## Panel de cocina para preparar platos con ingredientes del inventario (cocina interior y hogueras silvestres).

signal cerrado

var _titulo_texto: String = "Cocina de leña"
var _sel: String = ""
var _cantidad: int = 1
var _solo_disponibles: bool = false

var _l_titulo: Label
var _b_filtro: Button
var _lista: VBoxContainer
var _icono: Hueco
var _l_nombre: Label
var _l_desc: Label
var _l_efectos: Label
var _vbox_ing: VBoxContainer
var _l_origen: Label
var _l_cantidad: Label
var _b_menos: Button
var _b_mas: Button
var _b_max: Button
var _b_cocinar: Button
var _l_aviso: Label
var _b_cerrar: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.48)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.455
	p.anchor_bottom = 0.455
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 24)
	add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)

	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	v.add_child(cab)
	_l_titulo = Estilo.etiqueta(_titulo_texto, Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	_l_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_l_titulo)
	_b_filtro = Estilo.boton("Solo cocinables", 190)
	_b_filtro.toggle_mode = true
	_b_filtro.pressed.connect(func() -> void:
		_solo_disponibles = _b_filtro.button_pressed
		_reconstruir())
	cab.add_child(_b_filtro)

	var cuerpo := HBoxContainer.new()
	cuerpo.add_theme_constant_override("separation", 20)
	v.add_child(cuerpo)

	var col_izq := VBoxContainer.new()
	col_izq.add_theme_constant_override("separation", 6)
	cuerpo.add_child(col_izq)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_izq.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 6)
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lista)

	var det := VBoxContainer.new()
	det.custom_minimum_size = Vector2(410, 0)
	det.add_theme_constant_override("separation", 10)
	cuerpo.add_child(det)

	var top_det := HBoxContainer.new()
	top_det.add_theme_constant_override("separation", 14)
	det.add_child(top_det)
	_icono = Hueco.new(68, true)
	_icono.focus_mode = Control.FOCUS_NONE
	top_det.add_child(_icono)
	var info_det := VBoxContainer.new()
	info_det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_det.add_theme_constant_override("separation", 4)
	top_det.add_child(info_det)
	_l_nombre = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_l_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_det.add_child(_l_nombre)
	_l_efectos = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO)
	_l_efectos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_det.add_child(_l_efectos)

	_l_desc = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_desc)

	var l_ing_cab := Estilo.etiqueta("Ingredientes necesarios:", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	det.add_child(l_ing_cab)
	_vbox_ing = VBoxContainer.new()
	_vbox_ing.add_theme_constant_override("separation", 5)
	det.add_child(_vbox_ing)

	_l_origen = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	_l_origen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_origen)

	var fila_cant := HBoxContainer.new()
	fila_cant.add_theme_constant_override("separation", 8)
	det.add_child(fila_cant)
	_b_menos = Estilo.boton("−", 48)
	_b_menos.pressed.connect(func() -> void: _ajustar_cantidad(-1))
	fila_cant.add_child(_b_menos)
	_l_cantidad = Estilo.etiqueta("1", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_l_cantidad.custom_minimum_size = Vector2(46, 0)
	_l_cantidad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fila_cant.add_child(_l_cantidad)
	_b_mas = Estilo.boton("+", 48)
	_b_mas.pressed.connect(func() -> void: _ajustar_cantidad(1))
	fila_cant.add_child(_b_mas)
	_b_max = Estilo.boton("Máx", 76)
	_b_max.pressed.connect(func() -> void: _ajustar_cantidad(999))
	fila_cant.add_child(_b_max)
	var hueco := Control.new()
	hueco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_cant.add_child(hueco)
	_b_cocinar = Estilo.boton("Cocinar", 145)
	_b_cocinar.pressed.connect(_cocinar)
	fila_cant.add_child(_b_cocinar)

	_l_aviso = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO)
	_l_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_aviso)

	var pie := HBoxContainer.new()
	pie.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(pie)
	_b_cerrar = Estilo.boton("Cerrar (Esc)", 180)
	_b_cerrar.pressed.connect(cerrar_panel)
	pie.add_child(_b_cerrar)


func abrir(titulo_panel: String = "Cocina de leña") -> void:
	Juego.sincronizar_recetas(false)
	_titulo_texto = titulo_panel
	if _l_titulo != null:
		_l_titulo.text = titulo_panel
	_l_aviso.text = ""
	_cantidad = 1
	visible = true
	_reconstruir()
	_enfocar_primero.call_deferred()


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


func _enfocar_primero() -> void:
	if not visible:
		return
	if _lista.get_child_count() > 0 and _lista.get_child(0) is Button:
		(_lista.get_child(0) as Button).grab_focus()
	else:
		_b_cerrar.grab_focus()
	Interfaz.limitar_foco.call_deferred(self)


func _maximo_cocinable(id: String) -> int:
	if not Juego.tiene_receta(id):
		return 0
	var rec := Datos.receta(id)
	if rec.is_empty():
		return 0
	var max_ing := 999
	for ing: Variant in rec.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			var req := maxi(1, int(d.get("cantidad", 1)))
			max_ing = mini(max_ing, Juego.cantidad(str(d.get("id", ""))) / req)
	return mini(max_ing, Juego.espacio_para(id))


func _recetas_ordenadas() -> Array[Dictionary]:
	var aprendidas_ok: Array[Dictionary] = []
	var aprendidas_falta: Array[Dictionary] = []
	var bloqueadas: Array[Dictionary] = []
	for r: Dictionary in Datos.recetas():
		var rid := str(r.get("id", ""))
		if Juego.tiene_receta(rid):
			if _maximo_cocinable(rid) > 0:
				aprendidas_ok.append(r)
			elif not _solo_disponibles:
				aprendidas_falta.append(r)
		elif not _solo_disponibles:
			bloqueadas.append(r)
	var out: Array[Dictionary] = []
	out.append_array(aprendidas_ok)
	out.append_array(aprendidas_falta)
	out.append_array(bloqueadas)
	return out


func _reconstruir() -> void:
	for c in _lista.get_children():
		_lista.remove_child(c)
		c.queue_free()
	var recs := _recetas_ordenadas()
	var ids: Array[String] = []
	for r: Dictionary in recs:
		ids.append(str(r.get("id", "")))
	if _sel.is_empty() or not ids.has(_sel):
		_sel = ids[0] if not ids.is_empty() else ""
	if recs.is_empty():
		_lista.add_child(Estilo.etiqueta("No tienes ingredientes suficientes para ninguna receta conocida.", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE))
	for r: Dictionary in recs:
		_lista.add_child(_fila_receta(r))
	_actualizar_detalle()
	Interfaz.limitar_foco.call_deferred(self)


func _fila_receta(r: Dictionary) -> Button:
	var rid := str(r.get("id", ""))
	var aprendida := Juego.tiene_receta(rid)
	var mx := _maximo_cocinable(rid)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 52)
	b.toggle_mode = true
	b.button_pressed = (rid == _sel)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		_sel = rid
		_cantidad = 1
		_l_aviso.text = ""
		_reconstruir())
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)

	var ic := TextureRect.new()
	ic.texture = Datos.icono(rid)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(40, 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = Color.WHITE if aprendida else Color(0.45, 0.45, 0.45, 0.75)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)

	var nom := str(r.get("nombre", rid)) if aprendida else "🔒 " + str(r.get("nombre", rid))
	var ln := Estilo.etiqueta(nom, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO if aprendida else Estilo.COLOR_TEXTO_SUAVE)
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ln.clip_text = true
	h.add_child(ln)

	var estado := "×%d" % mx if mx > 0 else ("Falta ing." if aprendida else "Bloqueada")
	var col := Estilo.COLOR_BUENO if mx > 0 else Estilo.COLOR_TEXTO_SUAVE
	var le := Estilo.etiqueta(estado, Estilo.TAM_PEQUENO, col)
	le.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(le)
	return b


func _actualizar_detalle() -> void:
	for c in _vbox_ing.get_children():
		_vbox_ing.remove_child(c)
		c.queue_free()
	var r := Datos.receta(_sel)
	if r.is_empty():
		_icono.visible = false
		_l_nombre.text = "Sin receta seleccionada"
		_l_efectos.text = ""
		_l_desc.text = ""
		_l_origen.text = ""
		_b_cocinar.disabled = true
		return

	var rid := str(r["id"])
	var aprendida := Juego.tiene_receta(rid)
	var mx := _maximo_cocinable(rid)
	_icono.visible = true
	_icono.poner({"id": rid, "cantidad": 1})
	_icono.modulate = Color.WHITE if aprendida else Color(0.5, 0.5, 0.5, 0.8)
	_l_nombre.text = str(r.get("nombre", rid))
	_l_efectos.text = Datos.detalle_comida(rid)
	_l_desc.text = str(r.get("descripcion", ""))

	for ing: Variant in r.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			var iid := str(d.get("id", ""))
			var req := maxi(1, int(d.get("cantidad", 1)))
			var tengo := Juego.cantidad(iid)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_vbox_ing.add_child(row)
			var ic := TextureRect.new()
			ic.texture = Datos.icono(iid)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(26, 26)
			row.add_child(ic)
			var li := Estilo.etiqueta("%s (%d / %d)" % [Datos.nombre_objeto(iid), tengo, req], Estilo.TAM_TEXTO,
				Estilo.COLOR_BUENO if tengo >= req else Estilo.COLOR_MALO)
			row.add_child(li)

	_l_origen.text = str(r.get("pista_origen", ""))
	_l_origen.visible = not aprendida

	_cantidad = clampi(_cantidad, 1, maxi(mx, 1))
	_l_cantidad.text = str(_cantidad)
	_b_menos.disabled = not aprendida or mx <= 1
	_b_mas.disabled = not aprendida or mx <= 1
	_b_max.disabled = not aprendida or mx <= 1
	_b_cocinar.disabled = not aprendida or mx <= 0


func _ajustar_cantidad(delta: int) -> void:
	var mx := maxi(_maximo_cocinable(_sel), 1)
	if delta > 500:
		_cantidad = mx
	else:
		_cantidad = clampi(_cantidad + delta, 1, mx)
	_actualizar_detalle()


func _cocinar() -> void:
	if _sel.is_empty():
		return
	var r := Datos.receta(_sel)
	if Juego.cocinar(_sel, _cantidad):
		Audio.reproducir("ui_comprar")
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_BUENO)
		_l_aviso.text = "¡Cocinado! %d× %s guardado en tu mochila." % [_cantidad, str(r.get("nombre", _sel))]
		_cantidad = 1
		_reconstruir()
	else:
		Audio.reproducir("ui_error")
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
		_l_aviso.text = "Faltan ingredientes o espacio en la mochila."


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
