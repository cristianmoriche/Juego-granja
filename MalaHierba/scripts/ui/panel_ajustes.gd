class_name PanelAjustes
extends Control
## El mismo panel se abre desde el inicio o sobre la pausa, conservando el foco de origen.

var _contenido: VBoxContainer
var _aviso: Label
var _pagina := 0
var _esperando := ""
var _botones_tecla: Dictionary = {}
var _focos: Dictionary = {}
var _foco_anterior: Control
var _categorias: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Estilo.tema()
	visible = false
	var velo := ColorRect.new()
	velo.color = Color(0.02, 0.015, 0.01, 0.88)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(velo)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 28
	panel.offset_bottom = -28
	Estilo.estilo_panel(panel, Estilo.COLOR_FONDO, Estilo.COLOR_BORDE, 24)
	add_child(panel)
	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 12)
	panel.add_child(columna)
	columna.add_child(Estilo.etiqueta("Ajustes", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO))
	columna.add_child(Estilo.etiqueta("Se aplican y se guardan al cambiarlos.", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE))
	var pestanas := HBoxContainer.new()
	pestanas.add_theme_constant_override("separation", 12)
	columna.add_child(pestanas)
	var nombres := ["Sonido", "Imagen", "Accesibilidad", "Controles"]
	for i in nombres.size():
		var boton := Estilo.boton(nombres[i])
		boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boton.toggle_mode = true
		boton.pressed.connect(_mostrar_pagina.bind(i))
		pestanas.add_child(boton)
		_categorias.append(boton)
	columna.add_child(HSeparator.new())
	var desplazamiento := ScrollContainer.new()
	desplazamiento.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desplazamiento.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	desplazamiento.follow_focus = true
	columna.add_child(desplazamiento)
	_contenido = VBoxContainer.new()
	_contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contenido.add_theme_constant_override("separation", 18)
	desplazamiento.add_child(_contenido)
	_aviso = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_ACENTO)
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	columna.add_child(_aviso)
	var pie := HBoxContainer.new()
	pie.add_theme_constant_override("separation", 16)
	columna.add_child(pie)
	var volver := Estilo.boton("Volver  ·  Esc / B", 260)
	volver.pressed.connect(cerrar)
	pie.add_child(volver)
	var restaurar := Estilo.boton("Restaurar todos los ajustes", 400)
	restaurar.pressed.connect(func() -> void:
		Ajustes.restaurar()
		_mostrar_pagina(_pagina)
		_aviso.text = "Ajustes y teclas restaurados."
		_categorias[_pagina].grab_focus())
	pie.add_child(restaurar)
	_mostrar_pagina(0)

func abrir() -> void:
	if visible:
		return
	_foco_anterior = get_viewport().gui_get_focus_owner()
	_focos.clear()
	_bloquear_focos(get_tree().root)
	visible = true
	_mostrar_pagina(_pagina)
	_categorias[_pagina].grab_focus.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)

func _bloquear_focos(nodo: Node) -> void:
	if nodo == self:
		return
	if nodo is Control and nodo.focus_mode != Control.FOCUS_NONE:
		_focos[nodo] = nodo.focus_mode
		nodo.focus_mode = Control.FOCUS_NONE
	for hijo: Node in nodo.get_children():
		_bloquear_focos(hijo)

func cerrar() -> void:
	_esperando = ""
	visible = false
	for nodo: Variant in _focos:
		if is_instance_valid(nodo):
			nodo.focus_mode = _focos[nodo]
	_focos.clear()
	if is_instance_valid(_foco_anterior) and _foco_anterior.is_visible_in_tree():
		_foco_anterior.grab_focus.call_deferred()

func _fila(nombre: String, control: Control) -> void:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 24)
	var etiqueta := Estilo.etiqueta(nombre)
	etiqueta.custom_minimum_size.x = 400
	etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	etiqueta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fila.add_child(etiqueta)
	control.custom_minimum_size.x = 460
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(control)
	_contenido.add_child(fila)

func _poner(clave: String, valor: Variant) -> void:
	Ajustes.poner(clave, valor)
	_aviso.text = "Guardado." if Ajustes.ultimo_error == OK else "No se ha podido guardar la configuración."

func _deslizador(clave: String, nombre: String, minimo: float, maximo: float, paso: float) -> void:
	var caja := HBoxContainer.new()
	var deslizador := HSlider.new()
	deslizador.min_value = minimo
	deslizador.max_value = maximo
	deslizador.step = paso
	deslizador.value = float(Ajustes.valores[clave])
	deslizador.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deslizador.custom_minimum_size.y = 48
	deslizador.focus_mode = Control.FOCUS_ALL
	var lectura := Estilo.etiqueta("%d %%" % roundi(deslizador.value * 100))
	lectura.custom_minimum_size.x = 100
	lectura.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caja.add_child(deslizador)
	caja.add_child(lectura)
	deslizador.value_changed.connect(func(valor: float) -> void:
		lectura.text = "%d %%" % roundi(valor * 100)
		_poner(clave, valor))
	_fila(nombre, caja)

func _opciones(clave: String, nombre: String, opciones: Array) -> void:
	var selector := OptionButton.new()
	for opcion: String in opciones:
		selector.add_item(opcion)
	selector.selected = int(Ajustes.valores[clave])
	selector.item_selected.connect(func(indice: int) -> void: _poner(clave, indice))
	_fila(nombre, selector)

func _casilla(clave: String, nombre: String) -> void:
	var casilla := CheckButton.new()
	casilla.text = "Activado" if Ajustes.valores[clave] else "Desactivado"
	casilla.button_pressed = bool(Ajustes.valores[clave])
	casilla.toggled.connect(func(valor: bool) -> void:
		casilla.text = "Activado" if valor else "Desactivado"
		_poner(clave, valor))
	_fila(nombre, casilla)

func _nota(texto: String) -> void:
	var nota := Estilo.etiqueta(texto, Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contenido.add_child(nota)

func _mostrar_pagina(indice: int) -> void:
	_pagina = indice
	_esperando = ""
	_botones_tecla.clear()
	for hijo: Node in _contenido.get_children():
		_contenido.remove_child(hijo)
		hijo.queue_free()
	for i in _categorias.size():
		_categorias[i].button_pressed = i == indice
	_aviso.text = "Cruceta / palanca: navegar   ·   A: elegir   ·   B: volver" if _aviso != null else ""
	match indice:
		0:
			_deslizador("general", "Volumen general", 0.0, 1.0, 0.05)
			_deslizador("musica", "Música", 0.0, 1.0, 0.05)
			_deslizador("efectos", "Efectos", 0.0, 1.0, 0.05)
			_deslizador("ambiente", "Ambiente", 0.0, 1.0, 0.05)
			_nota("El volumen general controla todas las categorías. El 0 % silencia el canal.")
		1:
			_opciones("resolucion", "Resolución", ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440", "Nativa del monitor"])
			_casilla("pantalla_completa", "Pantalla completa")
			_opciones("calidad", "Calidad gráfica", ["Baja", "Media", "Alta"])
			_nota("Baja: render al 75 %, distancia reducida, sombras sin filtro suave, sin SSAO ni SSR. Pensada para equipos sin RTX.\nMedia: render al 90 %, SSAO y distancia intermedia. Alta: render al 100 %, SSAO, SSR y distancia completa.")
		2:
			_opciones("texto", "Tamaño de texto", ["Normal", "Grande", "Muy grande"])
			_casilla("alto_contraste", "Alto contraste en la interfaz")
			_casilla("reducir_movimiento", "Reducción de movimiento")
			_casilla("tutorial", "Avisos del tutorial")
			_nota("La reducción de movimiento mantiene estable la cámara y evita sacudidas y balanceo. No altera el control manual de la vista.\nLos avisos del tutorial muestran indicaciones breves la primera vez que descubres cada mecánica; puedes ocultarlos aquí en cualquier momento.")
		3:
			_deslizador("sensibilidad", "Sensibilidad de cámara", 0.25, 3.0, 0.05)
			_nota("Mando: palanca izquierda, moverse; derecha, cámara; A, interactuar; B, saltar / volver; X, herramienta; Y, inventario; pulsar izquierda, correr; LB, agacharse; pulsar derecha, centrar vista; cruceta izquierda / derecha, ranura; View, mapa; Start, pausa.\nPara cambiar una tecla, elige su botón y pulsa la nueva. Esc cancela. Se rechazan los conflictos.")
			for accion: String in Ajustes.ACCIONES:
				var boton := Estilo.boton(Ajustes.texto_tecla(accion))
				boton.pressed.connect(func() -> void:
					_esperando = accion
					_aviso.text = "Pulsa una tecla para «%s». Esc cancela." % Ajustes.ACCIONES[accion])
				_botones_tecla[accion] = boton
				_fila(Ajustes.ACCIONES[accion], boton)
			var restaurar := Estilo.boton("Restaurar teclas originales")
			restaurar.pressed.connect(func() -> void:
				Ajustes.restaurar_teclas()
				for accion: String in _botones_tecla:
					_botones_tecla[accion].text = Ajustes.texto_tecla(accion)
				_aviso.text = "Teclas restauradas; el mando conserva sus controles.")
			_contenido.add_child(restaurar)
	Ajustes.aplicar_interfaz.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)

func _input(evento: InputEvent) -> void:
	if not visible:
		return
	Ajustes.registrar_dispositivo(evento)
	if not _esperando.is_empty():
		if evento.is_action_pressed("ui_cancel") and not evento is InputEventKey:
			_esperando = ""
			_aviso.text = "Cambio cancelado."
		elif evento is InputEventKey and evento.pressed and not evento.echo:
			var codigo: int = evento.physical_keycode if evento.physical_keycode else evento.keycode
			if codigo == KEY_ESCAPE:
				_esperando = ""
				_aviso.text = "Cambio cancelado."
			else:
				var otra := Ajustes.conflicto(_esperando, codigo)
				if not otra.is_empty():
					_aviso.text = "Esa tecla ya está asignada a «%s». Elige otra o pulsa Esc." % Ajustes.ACCIONES[otra]
				elif Ajustes.remapear(_esperando, codigo):
					_botones_tecla[_esperando].text = Ajustes.texto_tecla(_esperando)
					_esperando = ""
					_aviso.text = "Tecla guardada."
		get_viewport().set_input_as_handled()
	elif evento.is_action_pressed("pausa") or evento.is_action_pressed("ui_cancel"):
		cerrar()
		get_viewport().set_input_as_handled()
