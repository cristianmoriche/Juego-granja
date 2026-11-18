class_name PanelDiario
extends Control
## Diario de misiones (T22) con sección extensible «Hoy» para encargos diarios (T23).

signal cerrado

var _tab: String = "curso"
var _seleccionada: String = ""
var _l_resumen: Label
var _b_tabs: Dictionary = {}
var _lista_vbox: VBoxContainer
var _scroll_lista: ScrollContainer
var _panel_detalle: PanelContainer
var _l_det_titulo: Label
var _l_det_meta: Label
var _l_det_desc: Label
var _vbox_pasos: VBoxContainer
var _l_det_rec: Label
var _b_activar: Button
var _b_cerrar: Button
var _panel_hoy: PanelContainer
var _vbox_hoy: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.5)
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
	p.custom_minimum_size = Vector2(980, 580)
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 24)
	add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)

	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 16)
	v.add_child(cab)
	var titulo := Estilo.etiqueta("Diario de misiones", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(titulo)
	_l_resumen = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_l_resumen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cab.add_child(_l_resumen)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	v.add_child(tabs)
	for clave: String in ["curso", "completadas", "todas", "hoy", "habilidades"]:
		var rotulo := ""
		match clave:
			"curso":
				rotulo = "En curso"
			"completadas":
				rotulo = "Completadas"
			"todas":
				rotulo = "Todas"
			"hoy":
				rotulo = "Hoy (Tablón)"
			"habilidades":
				rotulo = "Habilidades"
		var b := Estilo.boton(rotulo, 148.0)
		b.pressed.connect(func() -> void: _seleccionar_tab(clave))
		tabs.add_child(b)
		_b_tabs[clave] = b

	v.add_child(HSeparator.new())

	var cuerpo := HBoxContainer.new()
	cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cuerpo.add_theme_constant_override("separation", 16)
	v.add_child(cuerpo)

	_scroll_lista = ScrollContainer.new()
	_scroll_lista.custom_minimum_size = Vector2(360, 380)
	_scroll_lista.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cuerpo.add_child(_scroll_lista)
	_lista_vbox = VBoxContainer.new()
	_lista_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_vbox.add_theme_constant_override("separation", 8)
	_scroll_lista.add_child(_lista_vbox)

	_panel_detalle = PanelContainer.new()
	_panel_detalle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_detalle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Estilo.estilo_panel(_panel_detalle, Color(0.12, 0.09, 0.07, 0.92), Estilo.COLOR_BORDE_SUAVE, 18)
	cuerpo.add_child(_panel_detalle)

	var det := VBoxContainer.new()
	det.add_theme_constant_override("separation", 10)
	_panel_detalle.add_child(det)

	_l_det_titulo = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	_l_det_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_det_titulo)

	_l_det_meta = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	det.add_child(_l_det_meta)

	_l_det_desc = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_det_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_det_desc)

	det.add_child(HSeparator.new())
	var l_pasos := Estilo.etiqueta("Pasos:", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	det.add_child(l_pasos)
	_vbox_pasos = VBoxContainer.new()
	_vbox_pasos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox_pasos.add_theme_constant_override("separation", 6)
	det.add_child(_vbox_pasos)

	_l_det_rec = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_BUENO)
	_l_det_rec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.add_child(_l_det_rec)

	_panel_hoy = PanelContainer.new()
	_panel_hoy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_hoy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_hoy.visible = false
	Estilo.estilo_panel(_panel_hoy, Color(0.12, 0.09, 0.07, 0.92), Estilo.COLOR_BORDE_SUAVE, 18)
	cuerpo.add_child(_panel_hoy)
	_vbox_hoy = VBoxContainer.new()
	_vbox_hoy.add_theme_constant_override("separation", 10)
	_panel_hoy.add_child(_vbox_hoy)

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 12)
	v.add_child(pie)
	_b_activar = Estilo.boton("Seguir en el HUD", 220.0)
	_b_activar.pressed.connect(_al_pulsar_activar)
	pie.add_child(_b_activar)
	var hueco := Control.new()
	hueco.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pie.add_child(hueco)
	_b_cerrar = Estilo.boton("Cerrar (J / Esc)", 200.0)
	_b_cerrar.pressed.connect(cerrar)
	pie.add_child(_b_cerrar)

	Misiones.actualizado.connect(func() -> void:
		if visible:
			_refrescar())


func abrir(pestana: String = "") -> void:
	if not pestana.is_empty():
		_tab = pestana
	Misiones.sincronizar(false)
	var act := Misiones.mision_activa()
	if _seleccionada.is_empty() and not act.is_empty():
		_seleccionada = str(act.get("id", ""))
	visible = true
	_refrescar()
	_b_cerrar.grab_focus.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)


func cerrar() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


func pestana_actual() -> String:
	return _tab


func contenedor_hoy() -> VBoxContainer:
	return _vbox_hoy


func _seleccionar_tab(clave: String) -> void:
	_tab = clave
	_refrescar()


func _al_pulsar_activar() -> void:
	if _seleccionada.is_empty():
		return
	if Misiones.activar_mision(_seleccionada):
		_refrescar()


func _misiones_filtradas() -> Array[Dictionary]:
	match _tab:
		"curso":
			return Misiones.en_curso()
		"completadas":
			return Misiones.completadas()
		"todas":
			var r: Array[Dictionary] = []
			for m: Dictionary in Misiones.todas():
				if Misiones.desbloqueada(str(m["id"])):
					r.append(m)
			return r
	return []


func _refrescar() -> void:
	var comp := Misiones.completadas().size()
	var total := Misiones.todas().size()
	_l_resumen.text = "Completadas: %d / %d  ·  Deuda pendiente: %s" % [comp, total, Estilo.euros(Juego.deuda)]
	for k: String in _b_tabs:
		var b := _b_tabs[k] as Button
		b.modulate = Estilo.COLOR_ACENTO if k == _tab else Color.WHITE

	var es_hoy := (_tab == "hoy")
	var es_hab := (_tab == "habilidades")
	_scroll_lista.visible = not es_hoy and not es_hab
	_panel_detalle.visible = not es_hoy and not es_hab
	_panel_hoy.visible = es_hoy or es_hab
	if es_hoy:
		_b_activar.visible = false
		_rellenar_hoy()
		Interfaz.limitar_foco.call_deferred(self)
		return
	if es_hab:
		_b_activar.visible = false
		_rellenar_habilidades()
		Interfaz.limitar_foco.call_deferred(self)
		return

	_b_activar.visible = true
	for h in _lista_vbox.get_children():
		h.queue_free()

	var lista := _misiones_filtradas()
	var id_act := Misiones.id_activa()
	var ids_lista: Array[String] = []
	for m: Dictionary in lista:
		ids_lista.append(str(m["id"]))
	if not ids_lista.has(_seleccionada):
		_seleccionada = ids_lista[0] if not ids_lista.is_empty() else ""

	if lista.is_empty():
		var vacio := Estilo.etiqueta("No hay misiones en esta pestaña.", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
		vacio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lista_vbox.add_child(vacio)
	else:
		for m: Dictionary in lista:
			var mid := str(m["id"])
			var est_txt := Misiones.nombre_estacion(int(m.get("estacion", 0)))
			var marca := ""
			if Misiones.esta_completada(mid):
				marca = "✓ "
			elif mid == id_act:
				marca = "★ "
			var b := Estilo.boton("%s%s\n[%s · %s]" % [marca, str(m.get("titulo", mid)), est_txt, Misiones.nombre_npc(str(m.get("quien", "")))])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if mid == _seleccionada:
				b.modulate = Estilo.COLOR_ACENTO
			b.pressed.connect(func() -> void:
				_seleccionada = mid
				_refrescar())
			_lista_vbox.add_child(b)

	_rellenar_detalle()
	Interfaz.limitar_foco.call_deferred(self)


func _rellenar_detalle() -> void:
	for h in _vbox_pasos.get_children():
		h.queue_free()
	var m := Misiones.mision(_seleccionada)
	if m.is_empty():
		_l_det_titulo.text = "Sin misión seleccionada"
		_l_det_meta.text = ""
		_l_det_desc.text = "Avanza en la granja o cambia de estación para recibir nuevos encargos."
		_l_det_rec.text = ""
		_b_activar.disabled = true
		return

	var mid := str(m["id"])
	var hecha := Misiones.esta_completada(mid)
	_l_det_titulo.text = str(m.get("titulo", mid))
	var estado_str := "Completada" if hecha else ("Seguida en HUD" if mid == Misiones.id_activa() else "En curso")
	_l_det_meta.text = "Encargo de %s  ·  %s  ·  %s" % [
		Misiones.nombre_npc(str(m.get("quien", ""))),
		Misiones.nombre_estacion(int(m.get("estacion", 0))),
		estado_str
	]
	_l_det_desc.text = str(m.get("descripcion", ""))

	var est := Misiones.estado_de(mid)
	var paso_idx := int(est.get("paso", 0))
	var pasos: Array = m.get("pasos", [])
	for i in pasos.size():
		var p: Dictionary = pasos[i] as Dictionary
		var txt := str(p.get("texto", ""))
		var lbl: Label
		if hecha or i < paso_idx:
			lbl = Estilo.etiqueta("✓  " + txt, Estilo.TAM_TEXTO, Estilo.COLOR_BUENO)
		elif i == paso_idx:
			var prog := Misiones.progreso_paso(mid)
			lbl = Estilo.etiqueta("▶  %s  (%d / %d)" % [txt, prog.x, prog.y], Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
		else:
			lbl = Estilo.etiqueta("•  " + txt, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox_pasos.add_child(lbl)

	_l_det_rec.text = "Recompensa: " + Misiones.texto_recompensa(m)
	_b_activar.disabled = hecha or mid == Misiones.id_activa()


func _rellenar_hoy() -> void:
	for h in _vbox_hoy.get_children():
		h.queue_free()
	var encargos := TareasDiarias.encargos_del_dia()
	var hechas := 0
	for e: Dictionary in encargos:
		if TareasDiarias.encargo_hecho(str(e.get("id", ""))):
			hechas += 1
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	_vbox_hoy.add_child(cab)
	var titulo := Estilo.etiqueta("Tareas diarias del tablón (%d / %d)" % [hechas, encargos.size()], Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(titulo)
	cab.add_child(Estilo.etiqueta("Caducan al terminar el día · Escala ×%.1f" % TareasDiarias.escala_progreso(), Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	_vbox_hoy.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_theme_constant_override("separation", 10)
	scroll.add_child(lista)

	for e: Dictionary in encargos:
		var id_e := str(e.get("id", ""))
		var hecha := TareasDiarias.encargo_hecho(id_e)
		var lista_cobrar := TareasDiarias.lista_para_cobrar(e)
		var prog := TareasDiarias.progreso_de(e)

		var card := PanelContainer.new()
		var borde := Estilo.COLOR_BUENO if hecha else (Estilo.COLOR_ACENTO if lista_cobrar else Estilo.COLOR_BORDE_SUAVE)
		Estilo.estilo_panel(card, Color(0.16, 0.12, 0.09, 0.94), borde, 12)
		lista.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		cv.add_child(top)
		var estado_txt := "✓ Cobrada hoy" if hecha else ("★ Lista para entregar/cobrar en el tablón" if lista_cobrar else "▶ En curso (%d / %d)" % [prog.x, prog.y])
		var col_estado := Estilo.COLOR_BUENO if hecha else (Estilo.COLOR_ACENTO if lista_cobrar else Estilo.COLOR_TEXTO_SUAVE)
		var l_est := Estilo.etiqueta(estado_txt, Estilo.TAM_PEQUENO, col_estado)
		l_est.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(l_est)
		top.add_child(Estilo.etiqueta("Vecino: %s  ·  %s + %d amistad" % [
			Misiones.nombre_npc(str(e.get("npc", ""))),
			Estilo.euros(int(e.get("dinero", 0))),
			int(e.get("amistad", 0))
		], Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))

		var l_txt := Estilo.etiqueta(TareasDiarias.texto_encargo(e), Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
		l_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(l_txt)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = float(maxi(prog.y, 1))
		bar.value = float(prog.x)
		bar.add_theme_stylebox_override("fill", Estilo.caja(col_estado, col_estado, 0, 3, 0))
		cv.add_child(bar)

	var pie_hoy := Estilo.etiqueta("Acércate al tablón de anuncios en la plaza de Villaverde para cobrar las tareas completadas.", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	pie_hoy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox_hoy.add_child(pie_hoy)


func _rellenar_habilidades() -> void:
	for h in _vbox_hoy.get_children():
		h.queue_free()
	var total_nv := 0
	for id_h: String in Juego.HABILIDADES_ORDEN:
		total_nv += Juego.nivel_habilidad(id_h)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 12)
	_vbox_hoy.add_child(cab)
	var titulo := Estilo.etiqueta("Habilidades de Leo (%d / %d)" % [total_nv, Juego.HABILIDADES_ORDEN.size() * Juego.NIVEL_HABILIDAD_MAX], Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(titulo)
	cab.add_child(Estilo.etiqueta("Salud máx.: %d PS" % roundi(Juego.vida_max), Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 340)
	_vbox_hoy.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_theme_constant_override("separation", 8)
	scroll.add_child(lista)

	for id_h: String in Juego.HABILIDADES_ORDEN:
		var nv := Juego.nivel_habilidad(id_h)
		var xp := Juego.xp_habilidad(id_h)
		var req := Juego.xp_siguiente_nivel(nv)
		var card := PanelContainer.new()
		Estilo.estilo_panel(card, Color(0.16, 0.12, 0.09, 0.94), Estilo.COLOR_BORDE_SUAVE, 10)
		lista.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		cv.add_child(top)
		var l_nom := Estilo.etiqueta("%s  ·  Nivel %d / %d" % [str(Juego.HABILIDADES_NOMBRES.get(id_h, id_h)), nv, Juego.NIVEL_HABILIDAD_MAX], Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
		l_nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(l_nom)
		var xp_txt := "Nivel máximo" if req <= 0 else "%d / %d XP" % [xp, req]
		top.add_child(Estilo.etiqueta(xp_txt, Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO if req <= 0 else Estilo.COLOR_TEXTO_SUAVE))
		var barra := ProgressBar.new()
		barra.show_percentage = false
		barra.custom_minimum_size = Vector2(0, 10)
		barra.max_value = float(maxi(req, 1))
		barra.value = float(maxi(req, 1) if req <= 0 else xp)
		barra.add_theme_stylebox_override("fill", Estilo.caja(Estilo.COLOR_BUENO if nv >= 5 else Estilo.COLOR_ACENTO, Color.TRANSPARENT, 0, 3, 0))
		cv.add_child(barra)
		var l_ven := Estilo.etiqueta(str(Juego.HABILIDADES_VENTAJAS.get(id_h, "")), Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
		l_ven.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(l_ven)

	var bufos := Juego.bufos_activos()
	lista.add_child(Estilo.etiqueta("Mejoras de comida activas:", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO))
	if bufos.is_empty():
		lista.add_child(Estilo.etiqueta("Ninguna mejora de comida activa ahora mismo.", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	else:
		for k: Variant in bufos:
			var b := bufos[k] as Dictionary
			var rest := int(b.get("restante", 0))
			lista.add_child(Estilo.etiqueta("★ %s: %s (%dh %02dmin)" % [str(b.get("origen", "")), str(b.get("etiqueta", "")), rest / 60, rest % 60], Estilo.TAM_PEQUENO, Estilo.COLOR_BUENO))


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pausa") or event.is_action_pressed("diario")):
		cerrar()
		get_viewport().set_input_as_handled()
