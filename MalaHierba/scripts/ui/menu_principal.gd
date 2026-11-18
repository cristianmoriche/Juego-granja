extends Control
## Menú principal: Nueva partida (pide el nombre), Continuar (si hay partida guardada) y Salir.

const FONDO := "res://assets/ui/fondo_menu.png"
const Logros := preload("res://scripts/objetos/logros_h14.gd")

var _columna: VBoxContainer
var _panel_ranuras: PanelContainer
var _caja_ranuras: VBoxContainer
var _ranura_objetivo: int = 1
var _b_nueva: Button
var _b_continuar: Button
var _b_creditos: Button
var _b_salir: Button
var _panel_nombre: Control
var _panel_creditos: Control
var _scroll_creditos: ScrollContainer
var _b_cerrar_creditos: Button
var _campo_nombre: LineEdit


func _ready() -> void:
	theme = Estilo.tema()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Juego.partida_activa = false
	if Juego.es_ruta_de_ranura(Juego.ruta_partida):
		Juego.migrar_partida_legada()
		Juego.seleccionar_ranura_guardado(Juego.ranura_mas_reciente())
	Interfaz.mostrar_hud(false)
	Audio.poner_musica("mus_menu")
	Audio.poner_ambiente("")
	_construir_fondo()
	_construir_columna()
	_construir_panel_nombre()
	_construir_panel_creditos()
	refrescar_ranuras()
	CargadorMapa.solicitar_recurso(Escenas.RUTA_JUGADOR)
	if _b_continuar.disabled:
		_b_nueva.grab_focus.call_deferred()
	else:
		_b_continuar.grab_focus.call_deferred()


func _construir_fondo() -> void:
	var fondo := TextureRect.new()
	if ResourceLoader.exists(FONDO):
		fondo.texture = load(FONDO) as Texture2D
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	# Degradado oscuro de izquierda a derecha para que el texto se lea sobre la imagen.
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.03, 0.02, 0.92))
	g.set_color(1, Color(0.04, 0.03, 0.02, 0.0))
	g.set_offset(0, 0.0)
	g.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.62, 0.5)
	gt.width = 512
	gt.height = 8
	var velo := TextureRect.new()
	velo.texture = gt
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	velo.stretch_mode = TextureRect.STRETCH_SCALE
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(velo)


func _construir_columna() -> void:
	var margen := MarginContainer.new()
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margen.add_theme_constant_override("margin_left", 86)
	margen.add_theme_constant_override("margin_right", 72)
	margen.add_theme_constant_override("margin_top", 54)
	margen.add_theme_constant_override("margin_bottom", 46)
	margen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margen)
	var fila_principal := HBoxContainer.new()
	fila_principal.add_theme_constant_override("separation", 36)
	fila_principal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margen.add_child(fila_principal)

	_columna = VBoxContainer.new()
	_columna.alignment = BoxContainer.ALIGNMENT_CENTER
	_columna.add_theme_constant_override("separation", 14)
	_columna.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_columna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila_principal.add_child(_columna)

	var sep_centro := Control.new()
	sep_centro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep_centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila_principal.add_child(sep_centro)

	_panel_ranuras = PanelContainer.new()
	_panel_ranuras.name = "PanelRanuras"
	_panel_ranuras.custom_minimum_size = Vector2(560, 0)
	_panel_ranuras.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Estilo.estilo_panel(_panel_ranuras, Color(0.07, 0.06, 0.05, 0.90), Estilo.COLOR_BORDE, 22)
	fila_principal.add_child(_panel_ranuras)
	var vr := VBoxContainer.new()
	vr.add_theme_constant_override("separation", 10)
	_panel_ranuras.add_child(vr)
	var tit_r := Estilo.etiqueta("Ranuras de aventura", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	vr.add_child(tit_r)
	var sub_r := Estilo.etiqueta("Elige partida, crea una nueva o gestiona tus 3 ranuras", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	vr.add_child(sub_r)
	vr.add_child(HSeparator.new())
	_caja_ranuras = VBoxContainer.new()
	_caja_ranuras.name = "ListaRanuras"
	_caja_ranuras.add_theme_constant_override("separation", 10)
	vr.add_child(_caja_ranuras)

	var titulo := Estilo.etiqueta(str(Datos.texto("titulo", "Mala Hierba")), 96, Estilo.COLOR_ACENTO)
	titulo.add_theme_constant_override("outline_size", 10)
	titulo.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.95))
	_columna.add_child(titulo)
	var sub := Estilo.etiqueta(str(Datos.texto("subtitulo", "")), Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	_columna.add_child(sub)
	var hueco := Control.new()
	hueco.custom_minimum_size = Vector2(0, 24)
	_columna.add_child(hueco)

	_b_nueva = Estilo.boton("Nueva partida", 360)
	_b_nueva.pressed.connect(_pedir_nombre_libre)
	_columna.add_child(_b_nueva)
	_b_continuar = Estilo.boton("Continuar", 360)
	_b_continuar.pressed.connect(_continuar)
	_columna.add_child(_b_continuar)
	var ajustes := Estilo.boton("Ajustes", 360)
	ajustes.pressed.connect(Interfaz.abrir_ajustes)
	_columna.add_child(ajustes)
	_b_creditos = Estilo.boton("Créditos", 360)
	_b_creditos.pressed.connect(_abrir_creditos)
	_columna.add_child(_b_creditos)
	_b_salir = Estilo.boton("Salir", 360)
	_b_salir.pressed.connect(func() -> void: get_tree().quit())
	_columna.add_child(_b_salir)
	for b in [_b_nueva, _b_continuar, ajustes, _b_creditos, _b_salir]:
		(b as Button).add_theme_font_size_override("font_size", Estilo.TAM_GRANDE)
		(b as Button).custom_minimum_size = Vector2(360, 52)
		(b as Button).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var pie := Estilo.etiqueta("Versión %s  ·  Cristian, Juan José y Daniel  ·  Godot 4.7" % str(ProjectSettings.get_setting("application/config/version", "1.0")), Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	pie.add_theme_constant_override("outline_size", 4)
	pie.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	var sep := Control.new()
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columna.add_child(sep)
	_columna.add_child(pie)


func _formato_tiempo_jugado(seg: float) -> String:
	var mins := int(seg / 60.0)
	var hrs := mins / 60
	var rem := mins % 60
	if hrs > 0:
		return "%dh %02dm" % [hrs, rem]
	return "%dm" % maxi(0, mins)


func refrescar_ranuras() -> void:
	var estado := Juego.estado_guardado()
	_b_continuar.disabled = estado == "ninguna"
	if estado == "ok":
		_b_continuar.text = "Ver el final" if _partida_terminada() else "Continuar"
		_b_continuar.tooltip_text = "Ranura %d · %s" % [Juego.ranura_guardado_activa, Juego.resumen_de(Juego.ruta_partida)]
	elif estado != "ninguna":
		_b_continuar.text = "Continuar (partida dañada)"
	else:
		_b_continuar.text = "Continuar"

	if _caja_ranuras == null:
		return
	for h in _caja_ranuras.get_children():
		h.queue_free()

	for slot in range(1, Juego.MAX_RANURAS + 1):
		var info := Juego.info_ranura(slot)
		var est := str(info.get("estado", "ninguna"))
		var es_act := (slot == Juego.ranura_guardado_activa)
		var card := PanelContainer.new()
		card.name = "Ranura_%d" % slot
		var borde := Estilo.COLOR_ACENTO if es_act else Estilo.COLOR_BORDE_SUAVE
		var fondo_c := Color(0.16, 0.13, 0.09, 0.94) if est == "ok" else Color(0.11, 0.09, 0.08, 0.78)
		Estilo.estilo_panel(card, fondo_c, borde, 12)
		_caja_ranuras.add_child(card)

		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 12)
		card.add_child(fila)

		var marco_mini := PanelContainer.new()
		marco_mini.custom_minimum_size = Vector2(144, 81)
		Estilo.estilo_panel(marco_mini, Color(0.05, 0.04, 0.03, 1.0), Estilo.COLOR_BORDE_SUAVE, 2)
		fila.add_child(marco_mini)
		var tex_mini := info.get("miniatura") as Texture2D
		if tex_mini != null:
			var tr := TextureRect.new()
			tr.texture = tex_mini
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = Vector2(140, 77)
			marco_mini.add_child(tr)
		else:
			var l_vac := Estilo.etiqueta("Libre" if est == "ninguna" else ("Ranura %d" % slot), 14, Estilo.COLOR_TEXTO_SUAVE)
			l_vac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l_vac.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			marco_mini.add_child(l_vac)

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		fila.add_child(col)

		if est == "ok":
			var cab_txt := "Ranura %d · %s%s" % [slot, str(info["nombre"]), " (Activa)" if es_act else ""]
			col.add_child(Estilo.etiqueta(cab_txt, Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO if es_act else Estilo.COLOR_TEXTO))
			var det1 := "%s, día %d (Año %d) · %s" % [str(info["estacion"]), int(info["dia"]), int(info["anio"]), Estilo.euros(int(info["dinero"]))]
			col.add_child(Estilo.etiqueta(det1, Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO))
			var det2 := "Mina nv.%d · %d/%d logros · %s jugados" % [
				int(info["mina_max_nivel"]), int(info["logros_count"]), Logros.total(),
				_formato_tiempo_jugado(float(info.get("tiempo_jugado_seg", 0.0))),
			]
			col.add_child(Estilo.etiqueta(det2, 13, Estilo.COLOR_TEXTO_SUAVE))
			var bots := HBoxContainer.new()
			bots.add_theme_constant_override("separation", 8)
			col.add_child(bots)
			var b_cargar := Estilo.boton("Cargar", 96)
			b_cargar.custom_minimum_size = Vector2(96, 36)
			b_cargar.pressed.connect(_cargar_ranura.bind(slot))
			bots.add_child(b_cargar)
			var b_reempl := Estilo.boton("Nueva", 86)
			b_reempl.custom_minimum_size = Vector2(86, 36)
			b_reempl.pressed.connect(_pedir_nueva_en_ranura.bind(slot))
			bots.add_child(b_reempl)
			var b_borrar := Estilo.boton("Borrar", 86)
			b_borrar.custom_minimum_size = Vector2(86, 36)
			b_borrar.pressed.connect(_confirmar_borrar_ranura.bind(slot))
			bots.add_child(b_borrar)
		elif est == "danada_con_copia":
			col.add_child(Estilo.etiqueta("Ranura %d · Partida dañada (hay copia)" % slot, Estilo.TAM_TEXTO, Estilo.COLOR_MALO))
			var bots_d := HBoxContainer.new()
			bots_d.add_theme_constant_override("separation", 8)
			col.add_child(bots_d)
			var b_rec := Estilo.boton("Recuperar", 118)
			b_rec.custom_minimum_size = Vector2(118, 36)
			b_rec.pressed.connect(_cargar_ranura.bind(slot))
			bots_d.add_child(b_rec)
			var b_borr := Estilo.boton("Borrar", 86)
			b_borr.custom_minimum_size = Vector2(86, 36)
			b_borr.pressed.connect(_confirmar_borrar_ranura.bind(slot))
			bots_d.add_child(b_borr)
		else:
			col.add_child(Estilo.etiqueta("Ranura %d · Vacía" % slot, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE))
			col.add_child(Estilo.etiqueta("Lista para comenzar una nueva historia en El Granado.", 13, Estilo.COLOR_TEXTO_SUAVE))
			var b_emp := Estilo.boton("Nueva aquí", 136)
			b_emp.custom_minimum_size = Vector2(136, 36)
			b_emp.pressed.connect(_pedir_nueva_en_ranura.bind(slot))
			col.add_child(b_emp)


func _cargar_ranura(slot: int) -> void:
	Juego.seleccionar_ranura_guardado(slot)
	refrescar_ranuras()
	_continuar()


func _pedir_nombre_libre() -> void:
	if not Juego.es_ruta_de_ranura(Juego.ruta_partida):
		_pedir_nombre()
		return
	var elegida := Juego.ranura_guardado_activa
	for slot in range(1, Juego.MAX_RANURAS + 1):
		if str(Juego.info_ranura(slot).get("estado", "ninguna")) == "ninguna":
			elegida = slot
			break
	_pedir_nueva_en_ranura(elegida)


func _pedir_nueva_en_ranura(slot: int) -> void:
	var info := Juego.info_ranura(slot)
	if str(info.get("estado", "ninguna")) != "ninguna":
		Interfaz.preguntar(
			"La ranura %d ya guarda la partida de %s (%s). ¿Sobrescribirla con una partida nueva?" % [
				slot, str(info.get("nombre", "Leo")), str(info.get("resumen", "")),
			],
			["Sobrescribir", "Cancelar"],
			func(i: int) -> void:
				if i == 0:
					_ranura_objetivo = slot
					Juego.seleccionar_ranura_guardado(slot)
					_pedir_nombre()
		)
		return
	_ranura_objetivo = slot
	Juego.seleccionar_ranura_guardado(slot)
	_pedir_nombre()


func _confirmar_borrar_ranura(slot: int) -> void:
	var info := Juego.info_ranura(slot)
	var nom := str(info.get("nombre", "esta ranura"))
	Interfaz.preguntar(
		"¿Borrar permanentemente la ranura %d (%s)? Esta acción no se puede deshacer." % [slot, nom],
		["Borrar", "Cancelar"],
		func(i: int) -> void:
			if i == 0:
				Juego.borrar_ranura(slot)
				if Juego.ranura_guardado_activa == slot:
					Juego.seleccionar_ranura_guardado(Juego.ranura_mas_reciente())
				refrescar_ranuras()
	)


func _partida_terminada() -> bool:
	var b: Variant = Juego.leer_archivo(Juego.ruta_partida).get("banderas", {})
	return b is Dictionary and bool((b as Dictionary).get("fin_anio", false))


func _construir_panel_nombre() -> void:
	_panel_nombre = Control.new()
	_panel_nombre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_nombre.visible = false
	add_child(_panel_nombre)
	var oscuro := ColorRect.new()
	oscuro.color = Color(0, 0, 0, 0.55)
	oscuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_nombre.add_child(oscuro)
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 30)
	_panel_nombre.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.custom_minimum_size = Vector2(520, 0)
	p.add_child(v)
	v.add_child(Estilo.etiqueta("¿Cómo te llamas?", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO))
	v.add_child(Estilo.etiqueta("Así te llamará la gente de Villaverde.", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE))
	_campo_nombre = LineEdit.new()
	_campo_nombre.text = "Leo"
	_campo_nombre.placeholder_text = "Leo"
	_campo_nombre.max_length = 16
	_campo_nombre.custom_minimum_size = Vector2(0, 56)
	_campo_nombre.text_submitted.connect(func(_t: String) -> void: _empezar())
	v.add_child(_campo_nombre)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	v.add_child(fila)
	var atras := Estilo.boton("Atrás", 160)
	atras.pressed.connect(_cerrar_nombre)
	fila.add_child(atras)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(sp)
	var empezar := Estilo.boton("Empezar", 220)
	empezar.pressed.connect(_empezar)
	fila.add_child(empezar)


func _pedir_nombre() -> void:
	_panel_nombre.visible = true
	_campo_nombre.grab_focus.call_deferred()
	_campo_nombre.select_all.call_deferred()
	Interfaz.limitar_foco.call_deferred(_panel_nombre)


func _cerrar_nombre() -> void:
	_panel_nombre.visible = false
	_b_nueva.grab_focus()


func _empezar() -> void:
	var nombre := _campo_nombre.text.strip_edges()
	if nombre.is_empty():
		nombre = "Leo"
	if Juego.es_ruta_de_ranura(Juego.ruta_partida):
		Juego.borrar_ranura(_ranura_objetivo)
		Juego.seleccionar_ranura_guardado(_ranura_objetivo)
	Escenas.precargar_mapa("granja")
	Juego.nueva_partida(nombre)
	Escenas.ir_a_escena(Escenas.ESCENA_INTRO)


func _continuar() -> void:
	match Juego.estado_guardado():
		"ok":
			Escenas.continuar_partida()
		"danada_con_copia":
			var copia := Juego.resumen_de(Juego.ruta_partida + Juego.SUFIJO_TEMPORAL)
			if copia.is_empty():
				copia = Juego.resumen_de(Juego.ruta_partida + Juego.SUFIJO_COPIA)
			Interfaz.preguntar("La partida guardada está dañada y no se puede abrir.\nHay una copia de seguridad del guardado anterior (%s). ¿Quieres recuperarla?" % copia, ["Recuperar la copia", "Volver"], func(i: int) -> void:
				if i == 0:
					if Juego.recuperar_copia():
						Escenas.continuar_partida()
					else:
						Interfaz.mensaje("No se ha podido recuperar la copia de seguridad.")
				else:
					_b_continuar.grab_focus())
		"danada_sin_copia":
			Interfaz.preguntar("La partida guardada está dañada y no hay copia de seguridad.\nPuedes empezar una partida nueva; el archivo dañado no se borra hasta que vuelvas a guardar.", ["Entendido"], func(_i: int) -> void:
				_b_nueva.grab_focus())
		_:
			Interfaz.mensaje("No hay ninguna partida guardada.")


func _construir_panel_creditos() -> void:
	_panel_creditos = Control.new()
	_panel_creditos.name = "PanelCreditos"
	_panel_creditos.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_creditos.visible = false
	add_child(_panel_creditos)
	var oscuro := ColorRect.new()
	oscuro.color = Color(0.0, 0.0, 0.0, 0.68)
	oscuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	oscuro.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_cerrar_creditos()
	)
	_panel_creditos.add_child(oscuro)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(840, 560)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 26)
	_panel_creditos.add_child(p)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	p.add_child(caja)
	var titulo := Estilo.etiqueta("Créditos y licencias", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	caja.add_child(titulo)
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.2.0"))
	var sub := Estilo.etiqueta("Mala Hierba · El Granado · Versión %s" % ver, Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	caja.add_child(sub)
	caja.add_child(HSeparator.new())
	_scroll_creditos = ScrollContainer.new()
	_scroll_creditos.name = "ScrollCreditos"
	_scroll_creditos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_creditos.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	caja.add_child(_scroll_creditos)
	var contenido := VBoxContainer.new()
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 6)
	_scroll_creditos.add_child(contenido)
	_poblar_creditos(contenido)
	caja.add_child(HSeparator.new())
	var pie_modal := HBoxContainer.new()
	pie_modal.add_theme_constant_override("separation", 12)
	caja.add_child(pie_modal)
	var nota := Estilo.etiqueta("Textos completos en CREDITOS.md y carpeta licencias/", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	nota.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pie_modal.add_child(nota)
	_b_cerrar_creditos = Estilo.boton("Cerrar", 170)
	_b_cerrar_creditos.pressed.connect(_cerrar_creditos)
	pie_modal.add_child(_b_cerrar_creditos)


func _poblar_creditos(caja: VBoxContainer) -> void:
	var lineas := PackedStringArray()
	if FileAccess.file_exists("res://CREDITOS.md"):
		var f := FileAccess.open("res://CREDITOS.md", FileAccess.READ)
		if f != null:
			lineas = f.get_as_text().split("\n")
	if lineas.is_empty():
		lineas = PackedStringArray([
			"## Equipo",
			"- Autores: Cristian, Juan José y Daniel.",
			"- Motor: Godot Engine 4.7.2 (MIT).",
			"- Activos externos verificados: Poly Haven (CC0 1.0).",
		])
	for raw: String in lineas:
		var l := raw.strip_edges()
		if l.begins_with("# ") or l.begins_with("**Mala Hierba**"):
			continue
		if l.is_empty():
			var hueco := Control.new()
			hueco.custom_minimum_size = Vector2(0, 4)
			caja.add_child(hueco)
			continue
		if l.begins_with("## "):
			var h := Estilo.etiqueta(l.substr(3), Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			caja.add_child(h)
			continue
		var color := Estilo.COLOR_TEXTO if l.begins_with("- ") else Estilo.COLOR_TEXTO_SUAVE
		var txt := _limpiar_markdown(l)
		if txt.begins_with("- "):
			txt = "· " + txt.substr(2)
		var lb := Estilo.etiqueta(txt, Estilo.TAM_PEQUENO, color)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caja.add_child(lb)


func _limpiar_markdown(texto: String) -> String:
	var s := texto.replace("**", "").replace("`", "")
	s = s.replace("[Poly Haven](https://polyhaven.com)", "Poly Haven (polyhaven.com)")
	return s


func _abrir_creditos() -> void:
	if _panel_nombre != null and _panel_nombre.visible:
		_panel_nombre.visible = false
	_panel_creditos.visible = true
	if _scroll_creditos != null:
		_scroll_creditos.scroll_vertical = 0
	_b_cerrar_creditos.grab_focus.call_deferred()
	Interfaz.limitar_foco.call_deferred(_panel_creditos)


func _cerrar_creditos() -> void:
	_panel_creditos.visible = false
	_b_creditos.grab_focus.call_deferred()


func _mover_scroll_creditos(delta: int) -> void:
	if _scroll_creditos == null:
		return
	var barra := _scroll_creditos.get_v_scroll_bar()
	var maximo := int(maxf(0.0, barra.max_value - barra.page)) if barra != null else 0
	_scroll_creditos.scroll_vertical = clampi(_scroll_creditos.scroll_vertical + delta, 0, maximo)


func _input(event: InputEvent) -> void:
	if _panel_creditos == null or not _panel_creditos.visible:
		return
	if event.is_action_pressed("ui_down"):
		_mover_scroll_creditos(54)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_mover_scroll_creditos(-54)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down"):
		_mover_scroll_creditos(240)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		_mover_scroll_creditos(-240)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _panel_creditos != null and _panel_creditos.visible and (event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel")):
		_cerrar_creditos()
		get_viewport().set_input_as_handled()
		return
	if _panel_nombre != null and _panel_nombre.visible and (event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel")):
		_cerrar_nombre()
		get_viewport().set_input_as_handled()
