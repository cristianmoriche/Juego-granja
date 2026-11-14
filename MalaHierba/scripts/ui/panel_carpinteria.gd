class_name PanelCarpinteria
extends Control
## Panel de fabricación de muebles (T24): lista las 20 recetas de `datos/muebles.json`,
## muestra los materiales disponibles en la mochila y permite construir cualquier mueble.

signal cerrado

var _sel: String = ""
var _titulo: Label
var _l_aviso: Label
var _lista: VBoxContainer
var _icono: Hueco
var _l_nombre: Label
var _l_desc: Label
var _l_meta: Label
var _l_receta: Label
var _b_fabricar: Button
var _b_cerrar: Button


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
	_titulo = Estilo.etiqueta("Banco de carpintería · Fabricar muebles", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_titulo)
	_b_cerrar = Estilo.boton("Cerrar", 130)
	_b_cerrar.pressed.connect(cerrar_panel)
	cab.add_child(_b_cerrar)

	var cuerpo := HBoxContainer.new()
	cuerpo.add_theme_constant_override("separation", 20)
	v.add_child(cuerpo)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(510, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cuerpo.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 6)
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lista)

	var det := VBoxContainer.new()
	det.add_theme_constant_override("separation", 10)
	det.custom_minimum_size = Vector2(420, 0)
	cuerpo.add_child(det)
	_icono = Hueco.new(96.0, false)
	det.add_child(_icono)
	_l_nombre = Estilo.etiqueta("", Estilo.TAM_TITULO, Estilo.COLOR_TEXTO)
	_l_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_nombre)
	_l_meta = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	det.add_child(_l_meta)
	_l_desc = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_desc.custom_minimum_size = Vector2(400, 90)
	det.add_child(_l_desc)
	_l_receta = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_receta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_receta.custom_minimum_size = Vector2(400, 90)
	det.add_child(_l_receta)
	_b_fabricar = Estilo.boton("Fabricar mueble", 240)
	_b_fabricar.pressed.connect(_al_fabricar)
	det.add_child(_b_fabricar)
	_l_aviso = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_MALO)
	_l_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_aviso)

	Juego.inventario_cambiado.connect(func() -> void:
		if visible:
			_reconstruir())


func abrir() -> void:
	_l_aviso.text = ""
	var lista := Datos.muebles()
	if _sel.is_empty() and not lista.is_empty():
		_sel = str(lista[0].get("id", ""))
	visible = true
	_reconstruir()
	_b_cerrar.grab_focus.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


static func puede_fabricar(id: String) -> bool:
	var m := Datos.mueble(id)
	if m.is_empty():
		return false
	var receta: Variant = m.get("receta", {})
	if not (receta is Dictionary) or (receta as Dictionary).is_empty():
		return false
	for k: Variant in (receta as Dictionary):
		if Juego.cantidad(str(k)) < int((receta as Dictionary)[k]):
			return false
	return true


## Fabrica el mueble descontando sus materiales y colocándolo en la mochila.
## Devuelve «ok», «desconocido», «sin_material» o «sin_espacio».
static func fabricar(id: String) -> String:
	var m := Datos.mueble(id)
	if m.is_empty():
		return "desconocido"
	var receta: Variant = m.get("receta", {})
	if not (receta is Dictionary) or (receta as Dictionary).is_empty():
		return "desconocido"
	if not puede_fabricar(id):
		return "sin_material"
	if Juego.espacio_para(id) < 1:
		return "sin_espacio"
	for k: Variant in (receta as Dictionary):
		var req := int((receta as Dictionary)[k])
		if not Juego.quitar_objeto(str(k), req):
			return "sin_material"
	Juego.anadir_objeto(id, 1)
	Audio.reproducir("ui_comprar")
	return "ok"


func _reconstruir() -> void:
	for c in _lista.get_children():
		_lista.remove_child(c)
		c.queue_free()
	var muebles := Datos.muebles()
	for m: Dictionary in muebles:
		var id := str(m.get("id", ""))
		var ok := puede_fabricar(id)
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var nombre := str(m.get("nombre", id))
		var cat := str(m.get("categoria", "Mueble"))
		b.text = "  %s · %s" % [nombre, cat]
		b.icon = Datos.icono(id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 34)
		var col := Estilo.COLOR_ACENTO if id == _sel else (Estilo.COLOR_BUENO if ok else Estilo.COLOR_TEXTO)
		b.add_theme_color_override("font_color", col)
		b.pressed.connect(func() -> void:
			_sel = id
			_l_aviso.text = ""
			_reconstruir())
		fila.add_child(b)
		_lista.add_child(fila)
	_actualizar_detalle()


func _actualizar_detalle() -> void:
	var m := Datos.mueble(_sel)
	if m.is_empty():
		_icono.poner({})
		_l_nombre.text = "Elige un mueble"
		_l_meta.text = ""
		_l_desc.text = ""
		_l_receta.text = ""
		_b_fabricar.disabled = true
		return
	var o := Datos.objeto(_sel)
	_icono.poner({"id": _sel, "cantidad": maxi(1, Juego.cantidad(_sel))})
	_l_nombre.text = str(m.get("nombre", _sel))
	var tam: Array = m.get("tam", [1, 1])
	var capa := str(m.get("capa", "suelo"))
	var zona := "Pared" if capa == "pared" else ("Suelo (alfombra)" if capa == "alfombra" else "Suelo")
	_l_meta.text = "%s · Tamaño %d×%d · En mochila: %d" % [zona, int(tam[0]), int(tam[1]), Juego.cantidad(_sel)]
	_l_desc.text = str(o.get("descripcion", ""))

	var lineas: Array[String] = ["Materiales necesarios:"]
	var receta: Dictionary = m.get("receta", {})
	var falta_alguno := false
	for k: Variant in receta:
		var id_mat := str(k)
		var req := int(receta[k])
		var hay := Juego.cantidad(id_mat)
		if hay < req:
			falta_alguno = true
		lineas.append("• %s: %d / %d" % [Datos.nombre_objeto(id_mat), hay, req])
	_l_receta.text = "\n".join(lineas)
	_b_fabricar.disabled = falta_alguno


func _al_fabricar() -> void:
	var res := fabricar(_sel)
	if res == "ok":
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_BUENO)
		_l_aviso.text = "Fabricado: %s." % Datos.nombre_objeto(_sel)
		_reconstruir()
	elif res == "sin_espacio":
		Audio.reproducir("ui_error")
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
		_l_aviso.text = "No tienes hueco en la mochila."
	else:
		Audio.reproducir("ui_error")
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
		_l_aviso.text = "Te faltan materiales para fabricar este mueble."


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
