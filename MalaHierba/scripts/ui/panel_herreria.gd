class_name PanelHerreria
extends Control
## Panel de fundición en horno, mejora con lingotes, temple y engaste de gemas (H10).

signal cerrado

var _solapa: int = 0
var _sel_receta: String = "fundir_cobre"
var _usar_madera: bool = false
var _sel_herr: String = ""
var _sel_pieza_key: String = ""
var _sel_gema: String = "rubi"

var _l_dinero: Label
var _b_tab_horno: Button
var _b_tab_gemas: Button
var _b_tienda: Button
var _b_cerrar: Button

var _vista_horno: Control
var _lista_horno: VBoxContainer
var _icono_rec: Hueco
var _l_rec_nom: Label
var _l_rec_desc: Label
var _l_rec_req: Label
var _b_comb: Button
var _b_fundir: Button
var _lista_cola: VBoxContainer
var _b_recoger: Button

var _vista_gemas: Control
var _lista_piezas: VBoxContainer
var _icono_pieza: Hueco
var _l_pieza_nom: Label
var _l_pieza_stats: Label
var _l_comparar: Label
var _fila_huecos: HBoxContainer
var _fila_gemas: GridContainer
var _l_gema_info: Label
var _b_engastar: Button
var _b_templar: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0.0, 0.0, 0.0, 0.48)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.48
	p.anchor_bottom = 0.48
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.085, 0.062, 0.052, 0.96), Estilo.COLOR_BORDE, 22)
	add_child(p)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(960, 560)
	p.add_child(v)

	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	v.add_child(cab)
	var tit := Estilo.etiqueta("Herrería · Horno y Gemas", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	tit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(tit)
	_b_tab_horno = Estilo.boton("Horno", 130)
	_b_tab_horno.pressed.connect(_poner_solapa.bind(0))
	cab.add_child(_b_tab_horno)
	_b_tab_gemas = Estilo.boton("Engaste y temple", 175)
	_b_tab_gemas.pressed.connect(_poner_solapa.bind(1))
	cab.add_child(_b_tab_gemas)
	_l_dinero = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	_l_dinero.custom_minimum_size = Vector2(140, 0)
	_l_dinero.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cab.add_child(_l_dinero)

	_construir_horno(v)
	_construir_gemas(v)

	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 12)
	v.add_child(pie)
	_b_tienda = Estilo.boton("Forja de armas y armaduras", 260)
	_b_tienda.pressed.connect(func() -> void:
		cerrar()
		Interfaz.abrir_tienda("forja"))
	pie.add_child(_b_tienda)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pie.add_child(sp)
	_b_cerrar = Estilo.boton("Cerrar (Esc)", 150)
	_b_cerrar.pressed.connect(cerrar)
	pie.add_child(_b_cerrar)

	Juego.horno_cambiado.connect(refrescar)
	Juego.gemas_cambiadas.connect(refrescar)
	Juego.inventario_cambiado.connect(refrescar)
	Juego.dinero_cambiado.connect(func(_d: int) -> void: refrescar())


func _construir_horno(v: VBoxContainer) -> void:
	_vista_horno = HBoxContainer.new()
	_vista_horno.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_vista_horno as HBoxContainer).add_theme_constant_override("separation", 18)
	v.add_child(_vista_horno)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(410, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vista_horno.add_child(sc)
	_lista_horno = VBoxContainer.new()
	_lista_horno.add_theme_constant_override("separation", 6)
	_lista_horno.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_lista_horno)

	var der := VBoxContainer.new()
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	der.add_theme_constant_override("separation", 8)
	_vista_horno.add_child(der)

	var fila_tit := HBoxContainer.new()
	fila_tit.add_theme_constant_override("separation", 12)
	der.add_child(fila_tit)
	_icono_rec = Hueco.new(64, false)
	fila_tit.add_child(_icono_rec)
	var vt := VBoxContainer.new()
	vt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_tit.add_child(vt)
	_l_rec_nom = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	vt.add_child(_l_rec_nom)
	_l_rec_desc = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_l_rec_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_child(_l_rec_desc)

	_l_rec_req = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_rec_req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	der.add_child(_l_rec_req)

	var fila_acc := HBoxContainer.new()
	fila_acc.add_theme_constant_override("separation", 10)
	der.add_child(fila_acc)
	_b_comb = Estilo.boton("Combustible: Carbón", 210)
	_b_comb.pressed.connect(func() -> void:
		_usar_madera = not _usar_madera
		refrescar())
	fila_acc.add_child(_b_comb)
	_b_fundir = Estilo.boton("Encender horno", 190)
	_b_fundir.pressed.connect(_al_pulsar_horno)
	fila_acc.add_child(_b_fundir)

	der.add_child(HSeparator.new())
	der.add_child(Estilo.etiqueta("Crisoles activos (listos al avanzar el día o al dormir)", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO))
	_lista_cola = VBoxContainer.new()
	_lista_cola.add_theme_constant_override("separation", 6)
	_lista_cola.size_flags_vertical = Control.SIZE_EXPAND_FILL
	der.add_child(_lista_cola)
	_b_recoger = Estilo.boton("Recoger lingotes listos", 230)
	_b_recoger.pressed.connect(func() -> void:
		var n := Juego.recoger_fundicion()
		if n > 0:
			Interfaz.mensaje("Recoges %d lingotes fundidos." % n)
		refrescar())
	der.add_child(_b_recoger)


func _construir_gemas(v: VBoxContainer) -> void:
	_vista_gemas = HBoxContainer.new()
	_vista_gemas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_vista_gemas as HBoxContainer).add_theme_constant_override("separation", 18)
	v.add_child(_vista_gemas)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(360, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vista_gemas.add_child(sc)
	_lista_piezas = VBoxContainer.new()
	_lista_piezas.add_theme_constant_override("separation", 6)
	_lista_piezas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_lista_piezas)

	var der := VBoxContainer.new()
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	der.add_theme_constant_override("separation", 8)
	_vista_gemas.add_child(der)

	var cab_p := HBoxContainer.new()
	cab_p.add_theme_constant_override("separation", 12)
	der.add_child(cab_p)
	_icono_pieza = Hueco.new(64, false)
	cab_p.add_child(_icono_pieza)
	var vp := VBoxContainer.new()
	vp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab_p.add_child(vp)
	_l_pieza_nom = Estilo.etiqueta("Elige arma o armadura", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	vp.add_child(_l_pieza_nom)
	_l_pieza_stats = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
	_l_pieza_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vp.add_child(_l_pieza_stats)

	der.add_child(Estilo.etiqueta("Huecos de gema (pulsa uno ocupado para desengastar · 45 € · 35 % riesgo de rotura)", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	_fila_huecos = HBoxContainer.new()
	_fila_huecos.add_theme_constant_override("separation", 8)
	der.add_child(_fila_huecos)

	der.add_child(HSeparator.new())
	der.add_child(Estilo.etiqueta("Gema disponible en mochila", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO))
	_fila_gemas = GridContainer.new()
	_fila_gemas.columns = 3
	_fila_gemas.add_theme_constant_override("h_separation", 8)
	_fila_gemas.add_theme_constant_override("v_separation", 6)
	der.add_child(_fila_gemas)
	_l_gema_info = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
	_l_gema_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	der.add_child(_l_gema_info)

	_l_comparar = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Color(0.68, 0.94, 0.72))
	_l_comparar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	der.add_child(_l_comparar)

	var fila_b := HBoxContainer.new()
	fila_b.add_theme_constant_override("separation", 10)
	der.add_child(fila_b)
	_b_engastar = Estilo.boton("Engastar gema (35 €)", 215)
	_b_engastar.pressed.connect(_al_engastar)
	fila_b.add_child(_b_engastar)
	_b_templar = Estilo.boton("Templar con lingotes", 250)
	_b_templar.pressed.connect(_al_templar)
	fila_b.add_child(_b_templar)


func abrir(solapa: int = 0) -> void:
	_solapa = clampi(solapa, 0, 1)
	visible = true
	refrescar()
	Interfaz.limitar_foco.call_deferred(self)


func cerrar() -> void:
	visible = false
	cerrado.emit()


func _poner_solapa(s: int) -> void:
	_solapa = clampi(s, 0, 1)
	refrescar()
	Interfaz.limitar_foco.call_deferred(self)


func _unhandled_input(ev: InputEvent) -> void:
	if visible and (ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pausa")):
		cerrar()
		get_viewport().set_input_as_handled()


func refrescar() -> void:
	if not visible:
		return
	_l_dinero.text = Estilo.euros(Juego.dinero)
	_vista_horno.visible = (_solapa == 0)
	_vista_gemas.visible = (_solapa == 1)
	_b_tab_horno.disabled = (_solapa == 0)
	_b_tab_gemas.disabled = (_solapa == 1)
	if _solapa == 0:
		_refrescar_horno()
	else:
		_refrescar_gemas()


func _refrescar_horno() -> void:
	for h in _lista_horno.get_children():
		h.queue_free()
	_lista_horno.add_child(Estilo.etiqueta("Horno de fundición", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO))
	for r: Dictionary in Herreria.RECETAS_HORNO:
		var rid := str(r["id"])
		var lid := str(r["lingote"])
		var b := Estilo.boton("  " + str(r["nombre"]), 390)
		b.icon = Datos.icono(lid)
		b.add_theme_constant_override("icon_max_width", 28)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = (_sel_herr.is_empty() and rid == _sel_receta)
		b.pressed.connect(func() -> void:
			_sel_herr = ""
			_sel_receta = rid
			refrescar())
		_lista_horno.add_child(b)

	_lista_horno.add_child(HSeparator.new())
	_lista_horno.add_child(Estilo.etiqueta("Mejorar herramientas con lingotes (-25 % €)", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO))
	for hid: String in Servicios.HERRAMIENTAS:
		var rm := Servicios.receta_herramienta_lingote(hid)
		if rm.is_empty():
			continue
		var bh := Estilo.boton("  %s (%d× %s)" % [str(rm["nombre"]), int(rm["cantidad"]), Datos.nombre_objeto(str(rm["lingote"]))], 390)
		bh.icon = Datos.icono(Datos.id_icono(hid, int(rm["nivel"])))
		bh.add_theme_constant_override("icon_max_width", 28)
		bh.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bh.disabled = (_sel_herr == hid)
		bh.pressed.connect(func() -> void:
			_sel_herr = hid
			refrescar())
		_lista_horno.add_child(bh)

	if not _sel_herr.is_empty():
		var rh := Servicios.receta_herramienta_lingote(_sel_herr)
		if rh.is_empty():
			_sel_herr = ""
		else:
			var lid := str(rh["lingote"])
			var cant := int(rh["cantidad"])
			var cost := int(rh["dinero"])
			_icono_rec.poner({"id": _sel_herr, "cantidad": 1})
			_l_rec_nom.text = str(rh["nombre"])
			_l_rec_desc.text = "Templa tu herramienta con lingotes depurados en lugar de mena bruta (-25 % €)."
			_l_rec_req.text = "Requiere: %d × %s (tienes %d) + %s" % [cant, Datos.nombre_objeto(lid), Juego.cantidad(lid), Estilo.euros(cost)]
			_b_comb.visible = false
			_b_fundir.text = "Mejorar herramienta"
			_b_fundir.disabled = Juego.cantidad(lid) < cant or Juego.dinero < cost

	if _sel_herr.is_empty():
		var r := Herreria.receta_horno(_sel_receta)
		var lid := str(r.get("lingote", ""))
		_icono_rec.poner({"id": lid, "cantidad": int(r.get("entrega", 1))})
		_l_rec_nom.text = str(r.get("nombre", ""))
		_l_rec_desc.text = str(r.get("desc", ""))
		var min_id := str(r.get("mineral", ""))
		var min_c := int(r.get("cantidad", 1))
		var precio := int(r.get("dinero", 0))
		var mins := int(r.get("minutos", 50))
		var comb_txt := ""
		var tiene_comb := true
		var base_c := str(r.get("combustible", ""))
		_b_comb.visible = not base_c.is_empty()
		if not base_c.is_empty():
			_b_comb.text = "Combustible: %s" % ("Leña (×%d)" % int(r.get("madera_alt", 2)) if _usar_madera else "Carbón (×1)")
			if _usar_madera:
				var m_c := int(r.get("madera_alt", 2))
				tiene_comb = Juego.cantidad("madera") >= m_c
				comb_txt = " + %d × Madera (%d)" % [m_c, Juego.cantidad("madera")]
			else:
				var c_c := int(r.get("coste_comb", 1))
				tiene_comb = Juego.cantidad("carbon") >= c_c
				comb_txt = " + %d × Carbón (%d)" % [c_c, Juego.cantidad("carbon")]
		_l_rec_req.text = "Necesitas: %d × %s (%d)%s + %s\nTiempo de fundición: %d min de juego" % [
			min_c, Datos.nombre_objeto(min_id), Juego.cantidad(min_id), comb_txt, Estilo.euros(precio), mins
		]
		_b_fundir.text = "Encender horno"
		_b_fundir.disabled = Juego.cantidad(min_id) < min_c or not tiene_comb or Juego.dinero < precio or Juego.horno_cola().size() >= 3

	for h in _lista_cola.get_children():
		h.queue_free()
	var cola := Juego.horno_cola()
	var listos := 0
	if cola.is_empty():
		_lista_cola.add_child(Estilo.etiqueta("Horno vacío. Inicia una fundición arriba.", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	for item: Variant in cola:
		if not (item is Dictionary):
			continue
		var d := item as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := Hueco.new(36, false)
		ic.poner({"id": str(d.get("lingote", "")), "cantidad": int(d.get("entrega", 1))})
		row.add_child(ic)
		var dur := maxi(1, int(d.get("duracion", 50)))
		var rest := maxi(0, int(d.get("restante", 0)))
		var bar := ProgressBar.new()
		bar.max_value = float(dur)
		bar.value = float(dur - rest)
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 14)
		row.add_child(bar)
		var est_txt := "LISTO" if rest <= 0 else "%d min" % rest
		if rest <= 0:
			listos += int(d.get("entrega", 1))
		row.add_child(Estilo.etiqueta("%s · %s" % [Datos.nombre_objeto(str(d.get("lingote", ""))), est_txt], Estilo.TAM_PEQUENO, Color(0.65, 0.95, 0.65) if rest <= 0 else Estilo.COLOR_TEXTO))
		_lista_cola.add_child(row)
	_b_recoger.disabled = (listos <= 0)
	_b_recoger.text = "Recoger listos (%d)" % listos if listos > 0 else "Recoger lingotes listos"


func _al_pulsar_horno() -> void:
	if not _sel_herr.is_empty():
		var res := Servicios.mejorar_con_lingote(_sel_herr)
		if res == "ok":
			Interfaz.mensaje("Herramienta mejorada con lingote: %s." % Datos.nombre_objeto(_sel_herr))
		refrescar()
		return
	if Juego.iniciar_fundicion(_sel_receta, _usar_madera):
		Interfaz.mensaje("Fundición en marcha en el horno.")
	refrescar()


func _clave_pieza(p: Dictionary) -> String:
	return "%s:%s:%d" % [str(p["origen"]), str(p["sitio"]), int(p["indice"])]


func _refrescar_gemas() -> void:
	for h in _lista_piezas.get_children():
		h.queue_free()
	var piezas := Juego.listar_engastables()
	var elegida: Dictionary = {}
	for p: Dictionary in piezas:
		if _clave_pieza(p) == _sel_pieza_key:
			elegida = p
			break
	if elegida.is_empty() and not piezas.is_empty():
		elegida = piezas[0]
		_sel_pieza_key = _clave_pieza(elegida)

	if piezas.is_empty():
		_lista_piezas.add_child(Estilo.etiqueta("No llevas armas ni armaduras engastables.", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	for p: Dictionary in piezas:
		var k := _clave_pieza(p)
		var gs := p["gemas"] as Array
		var max_h := Herreria.huecos_para(str(p["id"]))
		var pref := "[Eq.] " if str(p["origen"]) == "equipo" else ""
		var t := int(p["temple"])
		var suf := (" +%d" % t) if t > 0 else ""
		var bp := Estilo.boton("  %s%s%s [%d/%d]" % [pref, Datos.nombre_objeto(str(p["id"])), suf, gs.size(), max_h], 340)
		bp.icon = Datos.icono(str(p["id"]))
		bp.add_theme_constant_override("icon_max_width", 26)
		bp.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bp.disabled = (k == _sel_pieza_key)
		bp.pressed.connect(func() -> void:
			_sel_pieza_key = k
			refrescar())
		_lista_piezas.add_child(bp)

	for h in _fila_huecos.get_children():
		h.queue_free()
	for h in _fila_gemas.get_children():
		h.queue_free()

	if elegida.is_empty():
		_icono_pieza.poner({})
		_l_pieza_nom.text = "Sin piezas engastables"
		_l_pieza_stats.text = "Forja o compra armas, escudos o armadura en la herrería."
		_l_comparar.text = ""
		_b_engastar.disabled = true
		_b_templar.disabled = true
		return

	var pid := str(elegida["id"])
	var gs_actual: Array = elegida["gemas"] as Array
	var tmp_actual := int(elegida["temple"])
	var max_huecos := Herreria.huecos_para(pid)
	var st_antes := Herreria.stats_pieza(pid, gs_actual, tmp_actual)

	_icono_pieza.poner({"id": pid, "cantidad": 1})
	_l_pieza_nom.text = "%s%s (%d/%d huecos)" % [Datos.nombre_objeto(pid), (" · Temple +%d" % tmp_actual) if tmp_actual > 0 else "", gs_actual.size(), max_huecos]
	_l_pieza_stats.text = _texto_stats(st_antes)

	for i in max_huecos:
		if i < gs_actual.size():
			var gid := str(gs_actual[i])
			var bh := Estilo.boton(Datos.nombre_objeto(gid) + " ×", 155)
			bh.icon = Datos.icono(gid)
			bh.add_theme_constant_override("icon_max_width", 22)
			var idx_h := i
			bh.pressed.connect(func() -> void:
				var r := Juego.desengastar_gema(str(elegida["origen"]), int(elegida["indice"]), str(elegida["sitio"]), idx_h)
				if r == "devuelta":
					Interfaz.mensaje("Gema desengastada intacta y devuelta a la mochila.")
				elif r == "rota":
					Interfaz.mensaje("La gema se quebró al extraerla del engaste.")
				refrescar())
			_fila_huecos.add_child(bh)
		else:
			var lv := Estilo.boton("Hueco %d libre" % (i + 1), 135)
			lv.disabled = true
			_fila_huecos.add_child(lv)

	for g_id: String in Herreria.ORDEN_GEMAS:
		var cant := Juego.cantidad(g_id)
		var bg := Estilo.boton("%s (×%d)" % [Datos.nombre_objeto(g_id), cant], 172)
		bg.icon = Datos.icono(g_id)
		bg.add_theme_constant_override("icon_max_width", 22)
		bg.disabled = (g_id == _sel_gema)
		bg.pressed.connect(func() -> void:
			_sel_gema = g_id
			refrescar())
		_fila_gemas.add_child(bg)

	var gd: Dictionary = Herreria.GEMAS.get(_sel_gema, {}) as Dictionary
	_l_gema_info.text = "%s: %s" % [str(gd.get("nombre", _sel_gema)), str(gd.get("resumen", ""))]

	if gs_actual.size() < max_huecos:
		var gs_desp := gs_actual.duplicate()
		gs_desp.append(_sel_gema)
		var st_desp := Herreria.stats_pieza(pid, gs_desp, tmp_actual)
		_l_comparar.text = "Antes -> Después (+%s): %s" % [Datos.nombre_objeto(_sel_gema), _texto_comparar(st_antes, st_desp)]
	else:
		_l_comparar.text = "Todos los huecos ocupados. Desengasta una gema para hacer sitio."

	_b_engastar.disabled = gs_actual.size() >= max_huecos or Juego.cantidad(_sel_gema) < 1 or Juego.dinero < Herreria.COSTE_ENGASTE

	var grado := clampi(int(Datos.objeto(pid).get("grado", 0)), 0, 2)
	var lingote_req := Herreria.lingote_para_grado(mini(2, grado + (1 if tmp_actual >= 2 else 0)))
	var cant_req := 1 + tmp_actual
	var coste_tmp := 40 + tmp_actual * 35
	if tmp_actual >= Herreria.TEMPLE_MAX:
		_b_templar.text = "Temple al máximo (+3)"
		_b_templar.disabled = true
	else:
		_b_templar.text = "Templar +%d (%d× %s · %s)" % [tmp_actual + 1, cant_req, Datos.nombre_objeto(lingote_req), Estilo.euros(coste_tmp)]
		_b_templar.disabled = Juego.cantidad(lingote_req) < cant_req or Juego.dinero < coste_tmp


func _texto_stats(st: Dictionary) -> String:
	var pts: Array[String] = []
	if float(st.get("dano", 0.0)) > 0.0:
		pts.append("Daño: %.0f" % float(st["dano"]))
	if float(st.get("defensa", 0.0)) > 0.0:
		pts.append("Defensa: %.0f" % float(st["defensa"]))
	if float(st.get("reduccion", 0.0)) > 0.0:
		pts.append("Bloqueo: %d%%" % roundi(float(st["reduccion"]) * 100.0))
	if float(st.get("suerte_minera", 0.0)) > 0.0:
		pts.append("+%d%% fortuna minera" % roundi(float(st["suerte_minera"]) * 100.0))
	if float(st.get("ahorro_resistencia", 0.0)) > 0.0:
		pts.append("-%d%% resistencia" % roundi(float(st["ahorro_resistencia"]) * 100.0))
	if float(st.get("quemadura", 0.0)) > 0.0:
		pts.append("Fuego +%d" % roundi(float(st["quemadura"])))
	if float(st.get("robo_vida", 0.0)) > 0.0:
		pts.append("+%d PS al golpear" % roundi(float(st["robo_vida"])))
	if bool(st.get("rompe_guardia", false)):
		pts.append("Rompe guardia")
	return " · ".join(pts) if not pts.is_empty() else "Pieza estándar sin bonificadores"


func _texto_comparar(antes: Dictionary, despues: Dictionary) -> String:
	var cambios: Array[String] = []
	for k: Array in [["dano", "Daño", 1.0], ["defensa", "Defensa", 1.0], ["suerte_minera", "% Fortuna", 100.0], ["ahorro_resistencia", "% Ahorro res.", 100.0], ["quemadura", "Quemadura", 1.0], ["robo_vida", "Robo vida", 1.0]]:
		var va := float(antes.get(str(k[0]), 0.0)) * float(k[2])
		var vd := float(despues.get(str(k[0]), 0.0)) * float(k[2])
		if absf(vd - va) >= 0.5:
			cambios.append("%s %.0f -> %.0f" % [str(k[1]), va, vd])
	if not bool(antes.get("rompe_guardia", false)) and bool(despues.get("rompe_guardia", false)):
		cambios.append("Gana Rompe guardia")
	return " · ".join(cambios) if not cambios.is_empty() else "Sin variación"


func _al_engastar() -> void:
	for p: Dictionary in Juego.listar_engastables():
		if _clave_pieza(p) == _sel_pieza_key:
			if Juego.engastar_gema(str(p["origen"]), int(p["indice"]), str(p["sitio"]), _sel_gema):
				Interfaz.mensaje("Gema %s engastada en %s." % [Datos.nombre_objeto(_sel_gema), Datos.nombre_objeto(str(p["id"]))])
			break
	refrescar()


func _al_templar() -> void:
	for p: Dictionary in Juego.listar_engastables():
		if _clave_pieza(p) == _sel_pieza_key:
			if Juego.templar_con_lingote(str(p["origen"]), int(p["indice"]), str(p["sitio"])):
				Interfaz.mensaje("%s templado con éxito." % Datos.nombre_objeto(str(p["id"])))
			break
	refrescar()
