class_name PanelInventario
extends Control
## Inventario de 30 huecos (la primera fila es la barra rápida). Clic en un hueco y luego en otro: los intercambia
## (o junta las pilas del mismo objeto). Muestra la descripción y el precio de venta del objeto señalado.

signal cerrado

const COLUMNAS := 10
const TAM_HUECO := 70.0

var _huecos: Array[Hueco] = []
var _origen: int = -1
var _sel: int = 0
var _l_nombre: Label
var _l_desc: Label
var _l_precio: Label
var _l_dinero: Label
var _b_comer: Button
var _b_cerrar: Button
var _b_equipo: Button
var _puestos: Dictionary = {}
const NOMBRES_EQUIPO := {"escudo": "Escudo", "casco": "Casco", "peto": "Peto", "botas": "Botas", "luz": "Luz", "carcaj": "Carcaj"}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.4)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.445
	p.anchor_bottom = 0.445
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.95), Estilo.COLOR_BORDE, 24)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)

	var cab := HBoxContainer.new()
	v.add_child(cab)
	var titulo := Estilo.etiqueta("Inventario", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(titulo)
	cab.add_child(Estilo.etiqueta("Clic en un hueco y luego en otro para intercambiarlos", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))

	var rejilla := GridContainer.new()
	rejilla.columns = COLUMNAS
	rejilla.add_theme_constant_override("h_separation", 8)
	rejilla.add_theme_constant_override("v_separation", 8)
	v.add_child(rejilla)
	for i in Juego.HUECOS:
		var h := Hueco.new(TAM_HUECO, true)
		h.indice = i
		if i < 10:
			h.numero = str((i + 1) % 10)
		h.pulsado.connect(_al_pulsar)
		h.mouse_entered.connect(_señalar.bind(i))
		h.focus_entered.connect(_señalar.bind(i))
		rejilla.add_child(h)
		_huecos.append(h)

	v.add_child(HSeparator.new())
	var abajo := HBoxContainer.new()
	abajo.add_theme_constant_override("separation", 24)
	v.add_child(abajo)
	var izq := VBoxContainer.new()
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.custom_minimum_size = Vector2(500, 120)
	abajo.add_child(izq)
	_l_nombre = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	izq.add_child(_l_nombre)
	_l_desc = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_desc.custom_minimum_size = Vector2(500, 0)
	izq.add_child(_l_desc)
	_l_precio = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
	izq.add_child(_l_precio)
	var der := VBoxContainer.new()
	der.add_theme_constant_override("separation", 8)
	abajo.add_child(der)
	_l_dinero = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_dinero.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	der.add_child(_l_dinero)
	_b_comer = Estilo.boton("Comer", 200)
	_b_comer.pressed.connect(_comer)
	der.add_child(_b_comer)
	_b_equipo = Estilo.boton("Equipar", 200)
	_b_equipo.pressed.connect(_equipar)
	der.add_child(_b_equipo)
	var cerrar := Estilo.boton("Cerrar  (I)", 200)
	_b_cerrar = cerrar
	cerrar.pressed.connect(cerrar_panel)
	der.add_child(cerrar)
	var fila_equipo := HBoxContainer.new()
	fila_equipo.add_theme_constant_override("separation", 8)
	v.add_child(fila_equipo)
	for puesto: String in Juego.RANURAS_EQUIPO:
		var boton := Estilo.boton("", 150)
		boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boton.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		boton.pressed.connect(_desequipar.bind(puesto))
		fila_equipo.add_child(boton)
		_puestos[puesto] = boton

	Juego.inventario_cambiado.connect(refrescar)
	Juego.equipo_cambiado.connect(refrescar)
	Juego.ranura_cambiada.connect(func(_r: int) -> void: refrescar())
	Juego.dinero_cambiado.connect(func(_d: int) -> void: refrescar())


func abrir() -> void:
	_b_cerrar.text = "Cerrar  (%s)" % Ajustes.pista("inventario")
	_origen = -1
	_sel = Juego.ranura
	visible = true
	refrescar()
	_huecos[_sel].grab_focus.call_deferred()


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	_origen = -1
	cerrado.emit()


func refrescar() -> void:
	if _huecos.is_empty():
		return
	for i in _huecos.size():
		var h := _huecos[i]
		h.activo = (i == Juego.ranura)
		h.marcado = (i == _origen)
		h.poner(Juego.inventario[i])
	_l_dinero.text = "Dinero: %s\nDeuda: %s" % [Estilo.euros(Juego.dinero), Estilo.euros(Juego.deuda)]
	for sitio: String in _puestos:
		var b := _puestos[sitio] as Button
		var id := str(Juego.equipo.get(sitio, ""))
		var material := str((Datos.objeto(id).get("forja", {}) as Dictionary).get("material", ""))
		var etiq := Datos.nombre_objeto(material) if not material.is_empty() else Datos.nombre_objeto(id)
		b.text = "%s —" % NOMBRES_EQUIPO[sitio] if id.is_empty() else "%s · %s" % [NOMBRES_EQUIPO[sitio], etiq]
		b.icon = null if id.is_empty() else Datos.icono(id)
		b.add_theme_constant_override("icon_max_width", 28)
		b.tooltip_text = "" if id.is_empty() else "Quitar %s" % Datos.nombre_objeto(id).to_lower()
		b.disabled = id.is_empty()
	_mostrar_info(_sel)
	if visible:
		Interfaz.limitar_foco.call_deferred(self)


func _señalar(i: int) -> void:
	_sel = i
	var comer_visible := _b_comer.visible
	var equipo_visible := _b_equipo.visible
	_mostrar_info(i)
	if comer_visible != _b_comer.visible or equipo_visible != _b_equipo.visible:
		Interfaz.limitar_foco.call_deferred(self)


func _mostrar_info(i: int) -> void:
	var d: Dictionary = Juego.inventario[i]
	_b_comer.visible = false
	_b_equipo.visible = false
	if d.is_empty():
		_l_nombre.text = "Hueco vacío"
		_l_desc.text = "Aquí no hay nada."
		_l_precio.text = ""
		return
	var id := str(d["id"])
	var cal := str(d.get("calidad", ""))
	var o := Datos.objeto(id)
	var c := int(d.get("cantidad", 1))
	var suf_cal := " (calidad baja)" if cal == "baja" else ""
	var temple_inv := int(d.get("temple", 0))
	var suf_temple := " (+%d temple)" % temple_inv if temple_inv > 0 else ""
	_l_nombre.text = str(o.get("nombre", id)) + suf_cal + suf_temple + ("  ×%d" % c if c > 1 else "")
	_l_desc.text = str(o.get("descripcion", ""))
	var venta := Juego.precio_venta_item(id, cal)
	var partes: Array[String] = []
	var detalle := Datos.detalle_equipo(o)
	if not detalle.is_empty():
		partes.append(detalle)
	var gem_arr: Array = d.get("gemas", []) if d.get("gemas") is Array else []
	if Herreria.es_engastable(id):
		var noms_g: Array[String] = []
		for g: Variant in gem_arr:
			noms_g.append(Datos.nombre_objeto(str(g)))
		var g_txt := ", ".join(PackedStringArray(noms_g)) if not noms_g.is_empty() else "ninguna"
		partes.append("Gemas (%d/%d): %s" % [gem_arr.size(), Herreria.huecos_para(id), g_txt])
	_b_equipo.visible = o.has("ranura_equipo")
	if venta > 0:
		var msg_v := "Se vende por %s" % Estilo.euros(venta)
		if Juego.cultivo_mercado_especial() == id:
			msg_v += " (mercado ×2 hoy)"
		elif cal == "baja":
			msg_v += " (−50 % por plaga)"
		partes.append(msg_v)
	if o.get("tipo", "") == "comida":
		var detalle_com := Datos.detalle_comida(id)
		if detalle_com.is_empty():
			var energia := int(o.get("energia", 0))
			detalle_com = "Recupera %d de energía y hasta %d de salud" % [energia, roundi(energia * 0.5)]
		partes.append(detalle_com)
		_b_comer.visible = true
	elif o.get("tipo", "") == "herramienta":
		partes.append("Gasta %d de energía por uso" % int(o.get("energia", 0)))
	_l_precio.text = "  ·  ".join(partes)


func _al_pulsar(h: Hueco, boton: int) -> void:
	var i := h.indice
	_sel = i
	if boton == MOUSE_BUTTON_RIGHT:
		var d: Dictionary = Juego.inventario[i]
		var tipo := str(Datos.objeto(str(d.get("id", ""))).get("tipo", ""))
		if tipo == "comida":
			Juego.comer(str(d["id"]))
		elif tipo == "equipo":
			_equipar()
		elif i < 10:
			Juego.elegir_ranura(i)
		return
	if _origen == -1:
		if not (Juego.inventario[i] as Dictionary).is_empty():
			_origen = i
	elif _origen == i:
		_origen = -1
	else:
		Juego.mover_huecos(_origen, i)
		_origen = -1
	refrescar()


func _comer() -> void:
	var d: Dictionary = Juego.inventario[_sel]
	if not d.is_empty():
		Juego.comer(str(d["id"]))


func _equipar() -> void:
	if Juego.equipar(_sel):
		_origen = -1
		_huecos[_sel].grab_focus()
		refrescar()


func _desequipar(sitio: String) -> void:
	if Juego.desequipar(sitio):
		_huecos[_sel].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("inventario") or event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
