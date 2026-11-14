extends Control
## Final del año: resumen de las cuentas y uno de los tres finales (malo, regular, bueno).

const FONDO := "res://assets/ui/fondo_menu.png"


func _ready() -> void:
	theme = Estilo.tema()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Juego.partida_activa = false
	Interfaz.mostrar_hud(false)
	var r := Juego.resumen_final()
	var clave := str(r["final"])
	var tinte := Color(0.03, 0.02, 0.015, 0.84)
	var color_titulo := Estilo.COLOR_ACENTO
	if clave == "malo":
		tinte = Color(0.03, 0.035, 0.05, 0.9)
		color_titulo = Color(0.75, 0.8, 0.9)
	elif clave == "bueno":
		tinte = Color(0.06, 0.04, 0.01, 0.74)
		color_titulo = Color(1.0, 0.86, 0.45)
	_construir(r, clave, tinte, color_titulo)


func _construir(r: Dictionary, clave: String, tinte: Color, color_titulo: Color) -> void:
	var fondo := TextureRect.new()
	if ResourceLoader.exists(FONDO):
		fondo.texture = load(FONDO) as Texture2D
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if clave == "malo":
		fondo.modulate = Color(0.55, 0.6, 0.7)
	add_child(fondo)
	var velo := ColorRect.new()
	velo.color = tinte
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(velo)

	var margen := MarginContainer.new()
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right"]:
		margen.add_theme_constant_override("margin_" + lado, 90)
	margen.add_theme_constant_override("margin_top", 60)
	margen.add_theme_constant_override("margin_bottom", 50)
	add_child(margen)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 60)
	margen.add_child(fila)

	# Columna del relato.
	var izq := VBoxContainer.new()
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.add_theme_constant_override("separation", 18)
	fila.add_child(izq)
	var cab := Estilo.etiqueta("Final del año  ·  Villaverde de los Rosales", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	izq.add_child(cab)
	var titulo := Estilo.etiqueta(str(Datos.texto("final.%s.titulo" % clave, "")), 56, color_titulo)
	titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titulo.add_theme_constant_override("outline_size", 8)
	titulo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	izq.add_child(titulo)
	var parrafos: Array = Datos.texto("final.%s.parrafos" % clave, [])
	for p: Variant in parrafos:
		var l := Estilo.etiqueta(str(p), 26, Estilo.COLOR_TEXTO)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(760, 0)
		izq.add_child(l)

	# Columna de las cuentas.
	var der := VBoxContainer.new()
	der.alignment = BoxContainer.ALIGNMENT_CENTER
	der.add_theme_constant_override("separation", 16)
	fila.add_child(der)
	var p := PanelContainer.new()
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.9), Estilo.COLOR_BORDE, 26)
	der.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(470, 0)
	p.add_child(v)
	v.add_child(Estilo.etiqueta("Resumen del año", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO))
	var saldo := int(r["saldo"])
	_linea(v, str(Datos.texto("resumen_final.dinero")), Estilo.euros(int(r["dinero"])))
	_linea(v, str(Datos.texto("resumen_final.deuda")), Estilo.euros(int(r["deuda"])))
	_linea(v, str(Datos.texto("resumen_final.saldo")), Estilo.euros(saldo), Estilo.COLOR_BUENO if saldo >= 0 else Estilo.COLOR_MALO)
	_linea(v, str(Datos.texto("resumen_final.amistad")), "%d de %d" % [int(round(float(r["amistad"]))), Juego.AMISTAD_MAX])
	_linea(v, str(Datos.texto("resumen_final.cosechas")), str(int(r["cosechas"])))
	_linea(v, str(Datos.texto("resumen_final.dias")), str(int(r["dias"])))
	var volver := Estilo.boton("Volver al menú", 300)
	volver.add_theme_font_size_override("font_size", Estilo.TAM_GRANDE)
	volver.pressed.connect(func() -> void: Escenas.ir_al_menu())
	der.add_child(volver)
	volver.grab_focus.call_deferred()


func _linea(padre: VBoxContainer, clave: String, valor: String, color: Color = Estilo.COLOR_TEXTO) -> void:
	var h := HBoxContainer.new()
	padre.add_child(h)
	var a := Estilo.etiqueta(clave, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := Estilo.etiqueta(valor, Estilo.TAM_TEXTO, color)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(b)
