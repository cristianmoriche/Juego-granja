class_name PanelTienda
extends Control
## Tienda: pestañas Comprar / Vender, lista a la izquierda y detalle con cantidad a la derecha.
## Usa Datos.tienda(id): `vende` (ids de objeto) y `compra_tipos` (tipos de objeto que compra).
## Las semillas solo se ofrecen en su estación.

signal cerrado

var _tienda: Dictionary = {}
var _modo: String = "comprar"
var _sel: String = ""
var _cantidad: int = 1

var _titulo: Label
var _l_dinero: Label
var _b_comprar_tab: Button
var _b_vender_tab: Button
var _b_forjar_tab: Button
var _b_salir: Button
var _lista: VBoxContainer
var _nota: Label
var _icono: Hueco
var _l_nombre: Label
var _l_desc: Label
var _l_precio: Label
var _l_cantidad: Label
var _l_total: Label
var _b_confirmar: Button
var _b_menos: Button
var _b_mas: Button
var _b_max: Button
var _l_aviso: Label


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
	_titulo = Estilo.etiqueta("", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_titulo)
	_b_comprar_tab = Estilo.boton("Comprar", 150)
	_b_comprar_tab.pressed.connect(_cambiar_modo.bind("comprar"))
	cab.add_child(_b_comprar_tab)
	_b_vender_tab = Estilo.boton("Vender", 150)
	_b_vender_tab.pressed.connect(_cambiar_modo.bind("vender"))
	cab.add_child(_b_vender_tab)
	_b_forjar_tab = Estilo.boton("Forjar", 150)
	_b_forjar_tab.pressed.connect(_cambiar_modo.bind("forjar"))
	cab.add_child(_b_forjar_tab)
	_l_dinero = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	_l_dinero.custom_minimum_size = Vector2(170, 0)
	_l_dinero.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cab.add_child(_l_dinero)

	var cuerpo := HBoxContainer.new()
	cuerpo.add_theme_constant_override("separation", 20)
	v.add_child(cuerpo)

	var col_izq := VBoxContainer.new()
	cuerpo.add_child(col_izq)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_izq.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 6)
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lista)
	_nota = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nota.custom_minimum_size = Vector2(500, 0)
	col_izq.add_child(_nota)

	var det := VBoxContainer.new()
	det.add_theme_constant_override("separation", 10)
	det.custom_minimum_size = Vector2(440, 0)
	cuerpo.add_child(det)
	_icono = Hueco.new(96.0, false)
	det.add_child(_icono)
	_l_nombre = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_l_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_nombre)
	_l_desc = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_desc.custom_minimum_size = Vector2(440, 70)
	det.add_child(_l_desc)
	_l_precio = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
	det.add_child(_l_precio)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	det.add_child(fila)
	_b_menos = Estilo.boton("−", 56)
	_b_menos.pressed.connect(_cambiar_cantidad.bind(-1))
	fila.add_child(_b_menos)
	_l_cantidad = Estilo.etiqueta("1", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_l_cantidad.custom_minimum_size = Vector2(70, 0)
	_l_cantidad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_cantidad.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(_l_cantidad)
	_b_mas = Estilo.boton("+", 56)
	_b_mas.pressed.connect(_cambiar_cantidad.bind(1))
	fila.add_child(_b_mas)
	_b_max = Estilo.boton("Máx.", 90)
	_b_max.pressed.connect(_poner_maximo)
	fila.add_child(_b_max)
	_l_total = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	det.add_child(_l_total)
	_b_confirmar = Estilo.boton("Comprar", 260)
	_b_confirmar.pressed.connect(_confirmar)
	det.add_child(_b_confirmar)
	_l_aviso = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_BUENO)
	_l_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_aviso.custom_minimum_size = Vector2(440, 0)
	det.add_child(_l_aviso)

	var pie := HBoxContainer.new()
	pie.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(pie)
	_b_salir = Estilo.boton("Salir  (Esc)", 200)
	_b_salir.pressed.connect(cerrar_panel)
	pie.add_child(_b_salir)

	Juego.dinero_cambiado.connect(func(_d: int) -> void: _actualizar_dinero())


func abrir(id_tienda: String) -> void:
	_tienda = Datos.tienda(id_tienda)
	if _tienda.is_empty():
		Interfaz.mensaje("Esa tienda está cerrada.")
		return
	_titulo.text = str(_tienda.get("nombre", "Tienda"))
	var compra: Array = _tienda.get("compra_tipos", [])
	_b_vender_tab.visible = not compra.is_empty()
	_b_forjar_tab.visible = _tienda.has("forja")
	_modo = "comprar"
	_sel = ""
	_cantidad = 1
	_l_aviso.text = ""
	visible = true
	_actualizar_dinero()
	_reconstruir()
	_enfocar_lista.call_deferred()


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


func _actualizar_dinero() -> void:
	if _l_dinero != null:
		_l_dinero.text = Estilo.euros(Juego.dinero)


func _cambiar_modo(m: String) -> void:
	_modo = m
	_sel = ""
	_cantidad = 1
	_l_aviso.text = ""
	_reconstruir()
	_enfocar_lista.call_deferred()


func _enfocar_lista() -> void:
	if not visible:
		return
	var fila := _fila_seleccionada()
	if fila != null:
		fila.grab_focus()
	else:
		_b_salir.grab_focus()


func _fila_seleccionada() -> Button:
	var indice := _ids_visibles().find(_sel)
	return _lista.get_child(indice) as Button if indice >= 0 else null


func _actualizar_foco() -> void:
	if not visible:
		return
	Interfaz.limitar_foco(self)
	if _modo != "forjar" or _b_confirmar.disabled:
		return
	var fila := _fila_seleccionada()
	if fila != null:
		fila.focus_neighbor_right = fila.get_path_to(_b_confirmar)
		_b_confirmar.focus_neighbor_left = _b_confirmar.get_path_to(fila)


func _parse_clave(clave: String) -> Array[String]:
	if clave.ends_with("|baja"):
		return [clave.trim_suffix("|baja"), "baja"]
	return [clave, ""]


## Claves de los objetos que se pueden comprar o vender ahora mismo.
func _ids_visibles() -> Array[String]:
	var r: Array[String] = []
	if _modo == "forjar":
		r.assign(_tienda.get("forja", []))
		return r
	if _modo == "comprar":
		var vende: Array = _tienda.get("vende", [])
		for v: Variant in vende:
			var id := str(v)
			var o := Datos.objeto(id)
			if o.is_empty():
				continue
			if o.get("tipo", "") == "semilla":
				var c := Datos.cultivo_de_semilla(id)
				var est: Array = c.get("estaciones", [])
				if not est.is_empty() and not est.has(Juego.estacion):
					continue
			r.append(id)
		for rec_v: Variant in _tienda.get("recetas", []):
			var rid := str(rec_v)
			if Datos.existe_receta(rid):
				r.append("receta:" + rid)
	else:
		var tipos: Array = _tienda.get("compra_tipos", [])
		var vistos: Dictionary = {}
		for h: Dictionary in Juego.inventario:
			if h.is_empty():
				continue
			var id := str(h["id"])
			var cal := "baja" if str(h.get("calidad", "")) == "baja" else ""
			var clave := id + "|baja" if cal == "baja" else id
			if vistos.has(clave):
				continue
			vistos[clave] = true
			var o := Datos.objeto(id)
			if int(o.get("precio_venta", 0)) > 0 and tipos.has(o.get("tipo", "")):
				r.append(clave)
	return r


func _precio(clave: String) -> int:
	if clave.begins_with("receta:"):
		var rid := clave.trim_prefix("receta:")
		var orig: Dictionary = Datos.receta(rid).get("origen", {}) as Dictionary
		return int(orig.get("precio", 80))
	var partes := _parse_clave(clave)
	var id := partes[0]
	var cal := partes[1]
	if _modo == "comprar":
		return int(Datos.objeto(id).get("precio_compra", 0))
	if _modo == "forjar":
		return int(_receta(id).get("dinero", 0))
	return Juego.precio_venta_item(id, cal)


func _reconstruir() -> void:
	_b_comprar_tab.disabled = (_modo == "comprar")
	_b_vender_tab.disabled = (_modo == "vender")
	_b_forjar_tab.disabled = (_modo == "forjar")
	for c in _lista.get_children():
		_lista.remove_child(c)
		c.queue_free()
	var ids := _ids_visibles()
	if ids.is_empty():
		var vacio := Estilo.etiqueta("No hay nada que vender aquí." if _modo == "vender" else "Hoy no queda nada.", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
		_lista.add_child(vacio)
	for clave in ids:
		_lista.add_child(_fila(clave))
	if _modo == "comprar":
		_nota.text = "Las semillas que ves son las de esta estación (%s)." % Juego.nombre_estacion().to_lower() if _tienda_tiene_semillas() else ""
	elif _modo == "forjar":
		_nota.text = "Trae el mineral y paga el trabajo de Clara."
	else:
		var esp := Juego.cultivo_mercado_especial()
		_nota.text = "¡Mercado especial! Hoy se paga al doble: %s." % Datos.nombre_objeto(esp) if not esp.is_empty() else "Aquí se compra lo que cosechas y sacas de la mina."
	if _sel.is_empty() or not ids.has(_sel):
		_sel = ids[0] if not ids.is_empty() else ""
		_cantidad = 1
	_actualizar_detalle()
	_actualizar_foco.call_deferred()


func _tienda_tiene_semillas() -> bool:
	for v: Variant in _tienda.get("vende", []):
		if Datos.objeto(str(v)).get("tipo", "") == "semilla":
			return true
	return false


func _fila(clave: String) -> Button:
	if clave.begins_with("receta:"):
		var rid := clave.trim_prefix("receta:")
		var rec := Datos.receta(rid)
		var aprendida := Juego.tiene_receta(rid)
		var b_r := Button.new()
		b_r.custom_minimum_size = Vector2(0, 54)
		b_r.toggle_mode = true
		b_r.button_pressed = (clave == _sel)
		b_r.focus_mode = Control.FOCUS_ALL
		b_r.pressed.connect(_elegir.bind(clave))
		var h_r := HBoxContainer.new()
		h_r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h_r.offset_left = 10
		h_r.offset_right = -12
		h_r.add_theme_constant_override("separation", 12)
		h_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b_r.add_child(h_r)
		var ic_r := TextureRect.new()
		ic_r.texture = Datos.icono(rid)
		ic_r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic_r.custom_minimum_size = Vector2(48, 48)
		ic_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h_r.add_child(ic_r)
		var ln_r := Estilo.etiqueta("Receta: %s" % str(rec.get("nombre", rid)), Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE if aprendida else Estilo.COLOR_TEXTO)
		ln_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ln_r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ln_r.clip_text = true
		h_r.add_child(ln_r)
		var lp_r := Estilo.etiqueta("Aprendida" if aprendida else Estilo.euros(_precio(clave)), Estilo.TAM_TEXTO, Estilo.COLOR_BUENO if aprendida else Estilo.COLOR_ACENTO)
		lp_r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h_r.add_child(lp_r)
		return b_r
	var partes := _parse_clave(clave)
	var id := partes[0]
	var cal := partes[1]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.toggle_mode = true
	b.button_pressed = (clave == _sel)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(_elegir.bind(clave))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -12
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := TextureRect.new()
	ic.texture = Datos.icono(Datos.id_icono(id, Juego.nivel(id)))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(48, 48)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var nombre := Datos.nombre_objeto(id)
	if cal == "baja":
		nombre += " (cal. baja)"
	if _modo == "vender":
		nombre += "  ×%d" % Juego.cantidad(id, cal)
		if Juego.cultivo_mercado_especial() == id:
			nombre += " ★×2"
	var ln := Estilo.etiqueta(nombre, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ln.clip_text = true
	h.add_child(ln)
	var lp := Estilo.etiqueta(Estilo.euros(_precio(clave)), Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
	lp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(lp)
	return b


func _elegir(id: String) -> void:
	_sel = id
	_cantidad = 1
	_l_aviso.text = ""
	for c in _lista.get_children():
		if c is Button:
			(c as Button).button_pressed = false
	_reconstruir_seleccion_visual()
	_actualizar_detalle()
	if _modo == "forjar":
		_actualizar_foco.call_deferred()


func _reconstruir_seleccion_visual() -> void:
	var ids := _ids_visibles()
	var n := _lista.get_child_count()
	for i in mini(n, ids.size()):
		var b := _lista.get_child(i)
		if b is Button:
			(b as Button).button_pressed = (ids[i] == _sel)


func _maximo() -> int:
	if _sel.is_empty():
		return 0
	if _sel.begins_with("receta:"):
		var rid := _sel.trim_prefix("receta:")
		return 1 if (not Juego.tiene_receta(rid) and Juego.dinero >= _precio(_sel)) else 0
	var partes := _parse_clave(_sel)
	var id := partes[0]
	var cal := partes[1]
	var pr := _precio(_sel)
	if _modo == "comprar":
		var por_dinero := Juego.dinero / maxi(pr, 1)
		return clampi(mini(por_dinero, Juego.espacio_para(id)), 0, Juego.PILA_MAX)
	if _modo == "forjar":
		var receta := _receta(id)
		return int(not receta.is_empty() and Juego.dinero >= pr and Juego.cantidad(str(receta["material"])) >= int(receta["cantidad"]))
	return Juego.cantidad(id, cal)


func _receta(id: String) -> Dictionary:
	return Datos.objeto(id).get("forja", {})


func _actualizar_detalle() -> void:
	if _sel.begins_with("receta:"):
		var rid := _sel.trim_prefix("receta:")
		var rec := Datos.receta(rid)
		var aprendida := Juego.tiene_receta(rid)
		_icono.visible = true
		_icono.poner({"id": rid, "cantidad": 1})
		_b_menos.visible = false
		_b_mas.visible = false
		_b_max.visible = false
		_l_cantidad.visible = false
		_l_nombre.text = "Receta: %s" % str(rec.get("nombre", rid))
		var d_txt := "%s\nEfecto del plato: %s" % [str(rec.get("descripcion", "")), Datos.detalle_comida(rid)]
		var ings: Array[String] = []
		for iv: Variant in rec.get("ingredientes", []):
			if iv is Dictionary:
				var id_i := str((iv as Dictionary).get("id", ""))
				ings.append("%d× %s" % [int((iv as Dictionary).get("cantidad", 1)), Datos.nombre_objeto(id_i)])
		if not ings.is_empty():
			d_txt += "\nIngredientes: " + ", ".join(ings)
		_l_desc.text = d_txt
		var pr_r := _precio(_sel)
		_l_precio.text = "Receta ya aprendida" if aprendida else "Precio del cuaderno: %s" % Estilo.euros(pr_r)
		_l_total.text = "Lista para cocinar en tu cabaña u hoguera." if aprendida else ""
		_b_confirmar.text = "Aprendida" if aprendida else "Aprender receta"
		_b_confirmar.disabled = aprendida or Juego.dinero < pr_r
		if not aprendida and Juego.dinero < pr_r:
			_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
			_l_aviso.text = "No tienes bastante dinero."
		return
	var hay := not _sel.is_empty()
	_icono.visible = hay
	_b_menos.disabled = not hay
	_b_mas.disabled = not hay
	_b_max.disabled = not hay
	_b_confirmar.disabled = not hay
	_b_menos.visible = _modo != "forjar"
	_b_mas.visible = _modo != "forjar"
	_b_max.visible = _modo != "forjar"
	_l_cantidad.visible = _modo != "forjar"
	if not hay:
		_l_nombre.text = ""
		_l_desc.text = ""
		_l_precio.text = ""
		_l_cantidad.text = "0"
		_l_total.text = ""
		return
	var partes := _parse_clave(_sel)
	var id := partes[0]
	var cal := partes[1]
	var o := Datos.objeto(id)
	_icono.poner({"id": id, "cantidad": 1, "calidad": cal})
	_l_nombre.text = str(o.get("nombre", id)) + (" (calidad baja)" if cal == "baja" else "")
	var desc := str(o.get("descripcion", ""))
	var detalle := Datos.detalle_equipo(o)
	if not detalle.is_empty():
		desc += "\n" + detalle
	if _modo == "vender":
		if cal == "baja":
			desc += "\nCalidad reducida por la plaga (−50 % de valor)."
		if Juego.cultivo_mercado_especial() == id:
			desc += "\n¡Mercado especial! Hoy se paga al doble."
	_l_desc.text = desc
	var pr := _precio(_sel)
	if _modo == "forjar":
		var receta := _receta(id)
		var mineral := str(receta["material"])
		var cantidad_mineral := int(receta["cantidad"])
		_l_precio.text = "%s y %d × %s" % [Estilo.euros(pr), cantidad_mineral, Datos.nombre_objeto(mineral)]
		_l_total.text = "En la mochila: %d × %s" % [Juego.cantidad(mineral), Datos.nombre_objeto(mineral)]
		_b_confirmar.text = "Forjar"
		_b_confirmar.disabled = _maximo() == 0
		if _b_confirmar.disabled:
			_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
			_l_aviso.text = "Falta mineral o dinero."
		return
	_l_precio.text = "%s: %s cada uno" % ["Precio" if _modo == "comprar" else "Te lo pagan a", Estilo.euros(pr)]
	var mx := _maximo()
	_cantidad = clampi(_cantidad, 1 if mx > 0 else 0, maxi(mx, 1))
	_l_cantidad.text = str(_cantidad)
	_l_total.text = "Total: %s" % Estilo.euros(_cantidad * pr)
	_b_confirmar.text = "Comprar" if _modo == "comprar" else "Vender"
	_b_confirmar.disabled = (mx <= 0)
	if _modo == "comprar" and mx <= 0:
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
		_l_aviso.text = "No tienes bastante dinero." if Juego.dinero < pr else "No te cabe más en el inventario."


func _cambiar_cantidad(delta: int) -> void:
	_cantidad += delta
	_l_aviso.text = ""
	_actualizar_detalle()


func _poner_maximo() -> void:
	_cantidad = maxi(_maximo(), 1)
	_l_aviso.text = ""
	_actualizar_detalle()


func _confirmar() -> void:
	if _sel.is_empty():
		return
	if _sel.begins_with("receta:"):
		var rid := _sel.trim_prefix("receta:")
		var pr_r := _precio(_sel)
		if Juego.tiene_receta(rid):
			_aviso_malo("Ya conoces esta receta.")
			return
		if not Juego.cobrar(pr_r):
			_aviso_malo("No tienes bastante dinero.")
			return
		Juego.aprender_receta(rid, true)
		_aviso_bueno("Has aprendido: %s." % str(Datos.receta(rid).get("nombre", rid)))
		_reconstruir()
		return
	var partes := _parse_clave(_sel)
	var id := partes[0]
	var cal := partes[1]
	var pr := _precio(_sel)
	var n := _cantidad
	var nombre := Datos.nombre_objeto(id)
	if _modo == "forjar":
		if not Juego.forjar_equipo(id):
			_aviso_malo("No se pudo forjar. Comprueba el mineral, el dinero y el espacio.")
			return
		_aviso_bueno("Clara ha forjado %s." % nombre.to_lower())
	elif _modo == "comprar":
		if n <= 0 or not Juego.cobrar(n * pr):
			_aviso_malo("No tienes bastante dinero.")
			return
		var sobra := Juego.anadir_objeto(id, n)
		if sobra > 0:
			Juego.ingresar(sobra * pr)
		_aviso_bueno("Has comprado %d × %s." % [n - sobra, nombre])
	else:
		if n <= 0 or not Juego.quitar_objeto(id, n, cal):
			_aviso_malo("No tienes tantos.")
			return
		Juego.ingresar(n * pr)
		Interfaz.mostrar_dinero_flotante(n * pr)
		_aviso_bueno("Has vendido %d × %s por %s." % [n, nombre, Estilo.euros(n * pr)])
	_cantidad = 1
	_reconstruir()
	if _modo == "forjar":
		_enfocar_lista.call_deferred()


func _aviso_bueno(t: String) -> void:
	Audio.reproducir("ui_comprar")
	_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_BUENO)
	_l_aviso.text = t


func _aviso_malo(t: String) -> void:
	Audio.reproducir("ui_error")
	_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
	_l_aviso.text = t


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel"):
		cerrar_panel()
		get_viewport().set_input_as_handled()
