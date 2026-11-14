class_name Hud
extends Control
## Pantalla de juego: reloj, dinero y energía (arriba a la derecha), barra de 10 ranuras (abajo),
## cartel de acción («E · Hablar con Clara») y avisos.

const MAX_AVISOS := 5
const TAM_RANURA := 64.0

var _panel_info: PanelContainer
var _panel_barra: PanelContainer
var _minimapa: Minimapa
var _l_fecha: Label
var _l_hora: Label
var _l_dinero: Label
var _l_deuda: Label
var _l_evento: Label
var _barra: ProgressBar
var _l_energia: Label
var _estilo_relleno: StyleBoxFlat
var _barra_vida: ProgressBar
var _l_vida: Label
var _estilo_vida: StyleBoxFlat
var _huecos: Array[Hueco] = []
var _l_activo: Label
var _cartel: PanelContainer
var _l_cartel: Label
var _columna_izq: VBoxContainer
var _panel_mision: PanelContainer
var _l_mision_titulo: Label
var _l_mision_paso: Label
var _barra_mision: ProgressBar
var _avisos: VBoxContainer
var _tutorial: PanelContainer
var _l_tut_titulo: Label
var _l_tut_cerrar: Label
var _l_tut_texto: Label
var _tut_ultimo_mando: bool = false
var _tut_id_mostrado: String = ""
var _tween_tutorial: Tween = null


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = Estilo.tema()
	_minimapa = Minimapa.new()
	_minimapa.name = "Minimapa"
	_minimapa.position = Vector2(16, 12)
	add_child(_minimapa)
	_construir_info()
	_construir_barra()
	_construir_cartel()
	_construir_avisos()
	_construir_tutorial()
	Juego.hora_cambiada.connect(func(_m: int) -> void: _actualizar_reloj())
	Juego.dia_nuevo.connect(_actualizar_reloj)
	Juego.clima_cambiado.connect(func(_c: String) -> void: _actualizar_reloj())
	Juego.evento_cambiado.connect(_actualizar_evento)
	Juego.dinero_cambiado.connect(func(_d: int) -> void: _actualizar_dinero())
	Juego.deuda_cambiada.connect(func(_d: int) -> void: _actualizar_dinero())
	Juego.partida_cambiada.connect(limpiar_avisos)
	Juego.partida_cambiada.connect(_actualizar_mision)
	Misiones.actualizado.connect(_actualizar_mision)
	Juego.energia_cambiada.connect(_actualizar_energia)
	Juego.vida_cambiada.connect(_actualizar_vida)
	Escenas.mapa_cargado.connect(func(_id: String) -> void: _actualizar_visibilidad_vida())
	Juego.inventario_cambiado.connect(_actualizar_barra)
	Juego.ranura_cambiada.connect(func(_r: int) -> void: _actualizar_barra())
	Tutorial.actualizado.connect(refrescar_tutorial)
	_tut_ultimo_mando = Ajustes.ultimo_mando
	refrescar()


## Vuelve a leer todo el estado (al empezar o cargar una partida).
func refrescar() -> void:
	_actualizar_reloj()
	_actualizar_dinero()
	_actualizar_evento()
	_actualizar_energia(Juego.energia, Juego.energia_max)
	_actualizar_vida(Juego.vida, Juego.vida_max)
	_actualizar_visibilidad_vida()
	_actualizar_barra()
	_actualizar_mision()
	refrescar_tutorial()


func _process(_delta: float) -> void:
	if _tutorial == null:
		return
	if Ajustes.ultimo_mando != _tut_ultimo_mando:
		_tut_ultimo_mando = Ajustes.ultimo_mando
		refrescar_tutorial()
		return
	var mostrar := _debe_verse_tutorial()
	if mostrar != _tutorial.visible:
		if mostrar:
			refrescar_tutorial()
		else:
			_tutorial.visible = false


# --- Construcción ----------------------------------------------------------------

func _construir_info() -> void:
	var p := PanelContainer.new()
	_panel_info = p
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -16
	p.offset_top = 16
	Estilo.estilo_panel(p, Estilo.COLOR_FONDO, Estilo.COLOR_BORDE, 14)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	_l_fecha = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_l_fecha.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_l_fecha)
	_l_hora = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_l_hora.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_l_hora)
	_l_dinero = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_ACENTO)
	_l_dinero.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_l_dinero)
	_l_deuda = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_l_deuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_l_deuda)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)
	_barra = ProgressBar.new()
	_barra.custom_minimum_size = Vector2(250, 28)
	_barra.show_percentage = false
	_barra.min_value = 0
	_barra.max_value = 100
	_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo_relleno = Estilo.caja(Estilo.COLOR_BUENO, Estilo.COLOR_BUENO, 0, 4, 0)
	_barra.add_theme_stylebox_override("fill", _estilo_relleno)
	v.add_child(_barra)
	_l_energia = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Color.WHITE)
	_l_energia.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_l_energia.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_energia.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_l_energia.add_theme_constant_override("outline_size", 4)
	_l_energia.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_barra.add_child(_l_energia)
	_barra_vida = ProgressBar.new()
	_barra_vida.name = "BarraVida"
	_barra_vida.custom_minimum_size = Vector2(250, 22)
	_barra_vida.show_percentage = false
	_barra_vida.min_value = 0
	_barra_vida.max_value = 100
	_barra_vida.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo_vida = Estilo.caja(Color(0.76, 0.24, 0.24), Color(0.76, 0.24, 0.24), 0, 4, 0)
	_barra_vida.add_theme_stylebox_override("fill", _estilo_vida)
	_barra_vida.visible = false
	v.add_child(_barra_vida)
	_l_vida = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Color.WHITE)
	_l_vida.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_l_vida.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_vida.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_l_vida.add_theme_constant_override("outline_size", 4)
	_l_vida.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_barra_vida.add_child(_l_vida)
	_l_evento = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	_l_evento.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_l_evento.visible = false
	v.add_child(_l_evento)


func _construir_barra() -> void:
	var p := PanelContainer.new()
	_panel_barra = p
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -14
	Estilo.estilo_panel(p, Color(0.09, 0.07, 0.06, 0.78), Estilo.COLOR_BORDE_SUAVE, 8)
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	for i in 10:
		var hu := Hueco.new(TAM_RANURA, true)
		# La barra acepta el ratón; la cruceta del mando cambia de ranura sin robar la interacción A.
		hu.focus_mode = Control.FOCUS_NONE
		hu.indice = i
		hu.numero = str((i + 1) % 10)
		hu.pulsado.connect(func(_hh: Hueco, _b: int) -> void: Juego.elegir_ranura(i))
		h.add_child(hu)
		_huecos.append(hu)
	_l_activo = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_activo.anchor_left = 0.5
	_l_activo.anchor_right = 0.5
	_l_activo.anchor_top = 1.0
	_l_activo.anchor_bottom = 1.0
	_l_activo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_l_activo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_l_activo.offset_bottom = -(14 + TAM_RANURA + 26)
	_l_activo.add_theme_constant_override("outline_size", 6)
	_l_activo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_l_activo)


func _construir_cartel() -> void:
	_cartel = PanelContainer.new()
	_cartel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartel.anchor_left = 0.5
	_cartel.anchor_right = 0.5
	_cartel.anchor_top = 1.0
	_cartel.anchor_bottom = 1.0
	_cartel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cartel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cartel.offset_bottom = -(14 + TAM_RANURA + 66)
	Estilo.estilo_panel(_cartel, Color(0.09, 0.07, 0.06, 0.88), Estilo.COLOR_ACENTO, 16)
	_cartel.visible = false
	add_child(_cartel)
	_l_cartel = Estilo.etiqueta("", Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
	_cartel.add_child(_l_cartel)


func _construir_avisos() -> void:
	_columna_izq = VBoxContainer.new()
	_columna_izq.name = "ColumnaIzquierda"
	_columna_izq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columna_izq.offset_left = 16
	_columna_izq.offset_top = 272
	_columna_izq.add_theme_constant_override("separation", 8)
	add_child(_columna_izq)

	_panel_mision = PanelContainer.new()
	_panel_mision.name = "PanelMisionActiva"
	_panel_mision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_mision.custom_minimum_size = Vector2(236, 0)
	Estilo.estilo_panel(_panel_mision, Color(0.09, 0.07, 0.06, 0.84), Estilo.COLOR_BORDE, 10)
	_panel_mision.visible = false
	_columna_izq.add_child(_panel_mision)
	var vm := VBoxContainer.new()
	vm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm.add_theme_constant_override("separation", 3)
	_panel_mision.add_child(vm)
	var cab := Estilo.etiqueta("MISIÓN ACTIVA  ·  J", 13, Estilo.COLOR_ACENTO)
	vm.add_child(cab)
	_l_mision_titulo = Estilo.etiqueta("", 18, Estilo.COLOR_TEXTO)
	_l_mision_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_mision_titulo.custom_minimum_size = Vector2(214, 0)
	vm.add_child(_l_mision_titulo)
	_l_mision_paso = Estilo.etiqueta("", 15, Estilo.COLOR_TEXTO_SUAVE)
	_l_mision_paso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_mision_paso.custom_minimum_size = Vector2(214, 0)
	vm.add_child(_l_mision_paso)
	_barra_mision = ProgressBar.new()
	_barra_mision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra_mision.show_percentage = false
	_barra_mision.custom_minimum_size = Vector2(214, 7)
	_barra_mision.add_theme_stylebox_override("fill", Estilo.caja(Estilo.COLOR_ACENTO, Estilo.COLOR_ACENTO, 0, 3, 0))
	vm.add_child(_barra_mision)

	_avisos = VBoxContainer.new()
	_avisos.name = "Avisos"
	_avisos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avisos.add_theme_constant_override("separation", 6)
	_columna_izq.add_child(_avisos)


func _construir_tutorial() -> void:
	_tutorial = PanelContainer.new()
	_tutorial.name = "PanelTutorial"
	_tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial.anchor_left = 0.5
	_tutorial.anchor_right = 0.5
	_tutorial.anchor_top = 0.0
	_tutorial.anchor_bottom = 0.0
	_tutorial.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tutorial.offset_top = 16
	Estilo.estilo_panel(_tutorial, Color(0.09, 0.07, 0.06, 0.90), Estilo.COLOR_BORDE, 16)
	_tutorial.visible = false
	add_child(_tutorial)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial.add_child(v)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 16)
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cab)
	_l_tut_titulo = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_ACENTO)
	_l_tut_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(_l_tut_titulo)
	_l_tut_cerrar = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	cab.add_child(_l_tut_cerrar)
	_l_tut_texto = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_tut_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_tut_texto.custom_minimum_size = Vector2(540, 0)
	v.add_child(_l_tut_texto)


func mostrar_juego(v: bool) -> void:
	if _minimapa != null:
		_minimapa.visible = v
	if _panel_info != null:
		_panel_info.visible = v
	if _panel_barra != null:
		_panel_barra.visible = v
	if _l_activo != null:
		_l_activo.visible = v
	if _panel_mision != null:
		_panel_mision.visible = v and not Misiones.mision_activa().is_empty()
	_actualizar_visibilidad_vida(v)
	if not v:
		ocultar_accion()
		if _tutorial != null:
			_tutorial.visible = false
	else:
		_actualizar_mision()
		refrescar_tutorial()


func minimapa() -> Minimapa:
	return _minimapa


func texto_accion() -> String:
	if _cartel == null or not _cartel.visible:
		return ""
	return _l_cartel.text


# --- Actualización ------------------------------------------------------------------

func _actualizar_reloj() -> void:
	if _l_fecha == null:
		return
	_l_fecha.text = "%s · %s" % [Juego.nombre_dia_semana(), Juego.texto_fecha()]
	_l_hora.text = "%s   %s" % [Juego.texto_hora(), Juego.nombre_clima()]
	_actualizar_evento()


func _actualizar_evento() -> void:
	if _l_evento == null:
		return
	var tipo := str(Juego.evento_hoy().get("tipo", ""))
	var texto := ""
	match tipo:
		"festividad":
			texto = "★ %s" % str(Juego.evento_hoy().get("nombre", "Festividad"))
		"mercado":
			texto = "Mercado ×2: %s" % Datos.nombre_objeto(Juego.cultivo_mercado_especial())
		"comerciante":
			texto = "Mercader ambulante en plaza"
		"plaga":
			texto = "¡Plaga en la huerta!"
		"tormenta":
			texto = "Tormenta · Cercas rotas" if Juego.hay_cercas_rotas() else "Tormenta en el valle"
		_:
			if Juego.hay_cercas_rotas():
				texto = "Cercas rotas en la granja"
	_l_evento.text = texto
	_l_evento.visible = not texto.is_empty()


func _actualizar_dinero() -> void:
	if _l_dinero == null:
		return
	_l_dinero.text = Estilo.euros(Juego.dinero)
	if Juego.deuda <= 0:
		_l_deuda.text = "Deuda saldada"
	else:
		_l_deuda.text = "Deuda: %s" % Estilo.euros(Juego.deuda)


func _actualizar_energia(e: float, maximo: float) -> void:
	if _barra == null:
		return
	_barra.max_value = maximo
	_barra.value = e
	_l_energia.text = "Energía  %d / %d" % [int(round(e)), int(round(maximo))]
	var f := e / maxf(maximo, 1.0)
	var c := Estilo.COLOR_BUENO
	if f < 0.2:
		c = Estilo.COLOR_MALO
	elif f < 0.45:
		c = Color(0.93, 0.74, 0.30)
	_estilo_relleno.bg_color = c
	_estilo_relleno.border_color = c


func _actualizar_vida(v: float, maximo: float) -> void:
	if _barra_vida == null:
		return
	_barra_vida.max_value = maximo
	_barra_vida.value = v
	_l_vida.text = "Salud  %d / %d" % [int(round(v)), int(round(maximo))]
	var f := v / maxf(maximo, 1.0)
	var c := Color(0.76, 0.24, 0.24)
	if f < 0.25:
		c = Color(0.92, 0.16, 0.16)
	elif f > 0.65:
		c = Color(0.84, 0.28, 0.28)
	_estilo_vida.bg_color = c
	_estilo_vida.border_color = c


func _actualizar_visibilidad_vida(juego_visible: bool = true) -> void:
	if _barra_vida == null:
		return
	var hud_on := juego_visible and (_panel_info == null or _panel_info.visible)
	var en_mina := Juego.mapa_actual == "mina_interior"
	if not en_mina:
		var m := Escenas.mapa_actual_nodo()
		en_mina = m != null and str(m.get("id_mapa")) == "mina_interior"
	_barra_vida.visible = hud_on and en_mina


func barra_vida_visible() -> bool:
	return _barra_vida != null and _barra_vida.visible


func _actualizar_barra() -> void:
	if _huecos.is_empty():
		return
	for i in 10:
		var h := _huecos[i]
		h.activo = (i == Juego.ranura)
		h.poner(Juego.inventario[i])
	var act := Juego.objeto_activo()
	if act.is_empty():
		_l_activo.text = ""
	else:
		var n := Datos.nombre_objeto(str(act["id"]))
		var c := int(act.get("cantidad", 1))
		_l_activo.text = n if c <= 1 else "%s  ×%d" % [n, c]


# --- Cartel de acción y avisos ------------------------------------------------------------

func mostrar_accion(texto: String) -> void:
	if _l_cartel.text != texto:
		_l_cartel.text = texto
	_cartel.visible = not texto.is_empty()


func ocultar_accion() -> void:
	_cartel.visible = false


func aviso(texto: String, id_icono: String = "") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var borde := Estilo.COLOR_ACENTO if not id_icono.is_empty() else Estilo.COLOR_BORDE_SUAVE
	Estilo.estilo_panel(p, Color(0.09, 0.07, 0.06, 0.88), borde, 12)
	var fila := HBoxContainer.new()
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_theme_constant_override("separation", 10)
	p.add_child(fila)
	if not id_icono.is_empty():
		var ic := TextureRect.new()
		ic.texture = Datos.icono(id_icono)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(48, 48)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fila.add_child(ic)
	var l := Estilo.etiqueta(texto, Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(l)
	_avisos.add_child(p)
	while _avisos.get_child_count() > MAX_AVISOS:
		var viejo := _avisos.get_child(0)
		_avisos.remove_child(viejo)
		viejo.queue_free()
	p.modulate.a = 0.0
	var t := p.create_tween()
	t.tween_property(p, "modulate:a", 1.0, 0.14)
	t.tween_interval(3.4)
	t.tween_property(p, "modulate:a", 0.0, 0.6)
	t.tween_callback(p.queue_free)


func rect_dinero() -> Rect2:
	if _l_dinero != null and is_instance_valid(_l_dinero):
		return _l_dinero.get_global_rect()
	return Rect2()


func avisos_activos() -> int:
	return _avisos.get_child_count() if _avisos != null else 0


func limpiar_avisos() -> void:
	if _avisos == null:
		return
	for h in _avisos.get_children():
		_avisos.remove_child(h)
		h.queue_free()


# --- Tutorial progresivo ----------------------------------------------------------------

func _debe_verse_tutorial() -> bool:
	return _panel_barra != null and _panel_barra.visible and Tutorial.hay_aviso_activo() and not Interfaz.ocupada() and not Escenas.en_transicion


func refrescar_tutorial() -> void:
	if _tutorial == null:
		return
	var datos := Tutorial.contenido_actual()
	if datos.is_empty() or not _debe_verse_tutorial():
		_tutorial.visible = false
		_tut_id_mostrado = ""
		return
	var id := str(datos.get("id", ""))
	_l_tut_titulo.text = str(datos.get("titulo", ""))
	_l_tut_cerrar.text = str(datos.get("cerrar", ""))
	_l_tut_texto.text = str(datos.get("texto", ""))
	var es_nuevo := id != _tut_id_mostrado
	_tut_id_mostrado = id
	_tutorial.visible = true
	if es_nuevo:
		if _tween_tutorial != null and _tween_tutorial.is_valid():
			_tween_tutorial.kill()
		if bool(Ajustes.valores.get("reducir_movimiento", false)) or DisplayServer.get_name() == "headless":
			_tutorial.modulate.a = 1.0
		else:
			_tutorial.modulate.a = 0.0
			_tween_tutorial = _tutorial.create_tween()
			_tween_tutorial.tween_property(_tutorial, "modulate:a", 1.0, 0.16)


func tutorial_visible() -> bool:
	return _tutorial != null and _tutorial.visible


func texto_tutorial() -> String:
	return _l_tut_texto.text if _l_tut_texto != null else ""


func _actualizar_mision() -> void:
	if _panel_mision == null:
		return
	var hud_on := _panel_barra != null and _panel_barra.visible
	var m := Misiones.mision_activa()
	if m.is_empty():
		_panel_mision.visible = false
		_l_mision_titulo.text = ""
		_l_mision_paso.text = ""
		return
	var mid := str(m.get("id", ""))
	var p := Misiones.paso_actual(mid)
	var prog := Misiones.progreso_paso(mid)
	_l_mision_titulo.text = str(m.get("titulo", mid))
	_l_mision_paso.text = "%s (%d/%d)" % [str(p.get("texto", "")), prog.x, prog.y]
	_barra_mision.max_value = float(maxi(prog.y, 1))
	_barra_mision.value = float(prog.x)
	_panel_mision.visible = hud_on


func texto_mision_activa() -> String:
	if _panel_mision == null or not _panel_mision.visible:
		return ""
	return "%s | %s" % [_l_mision_titulo.text, _l_mision_paso.text]
