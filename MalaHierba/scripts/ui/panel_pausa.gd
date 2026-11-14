class_name PanelPausa
extends Control
## Menú de pausa: Continuar, Guardar, Salir al menú y Salir. Muestra también los controles.

signal cerrado

var _resumen: Label
var _controles: Label
var _b_continuar: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.55)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(p, Color(0.08, 0.06, 0.05, 0.96), Estilo.COLOR_BORDE, 30)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(440, 0)
	p.add_child(v)
	var t := Estilo.etiqueta("Pausa", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_resumen = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO_SUAVE)
	_resumen.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_resumen)
	_b_continuar = Estilo.boton("Continuar")
	_b_continuar.pressed.connect(cerrar_panel)
	v.add_child(_b_continuar)
	var guardar := Estilo.boton("Guardar partida")
	guardar.pressed.connect(func() -> void: Juego.guardar(true))
	v.add_child(guardar)
	var ajustes := Estilo.boton("Ajustes")
	ajustes.pressed.connect(Interfaz.abrir_ajustes)
	v.add_child(ajustes)
	var diario := Estilo.boton("Diario de misiones (J)")
	diario.pressed.connect(func() -> void: Interfaz.abrir_diario())
	v.add_child(diario)
	var menu := Estilo.boton("Salir al menú")
	menu.pressed.connect(_pedir_salir_al_menu)
	v.add_child(menu)
	var salir := Estilo.boton("Salir del juego")
	salir.pressed.connect(_pedir_salir_del_juego)
	v.add_child(salir)
	_controles = Estilo.etiqueta("Controles y mando: consulta Ajustes → Controles", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	_controles.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(HSeparator.new())
	v.add_child(_controles)


func abrir() -> void:
	Audio.reproducir("ui_menu")
	_resumen.text = "%s  ·  %s  ·  %s" % [Juego.texto_fecha(), Juego.texto_hora(), Estilo.euros(Juego.dinero)]
	visible = true
	_b_continuar.grab_focus.call_deferred()
	Interfaz.limitar_foco.call_deferred(self)


func cerrar_panel() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


func _pedir_salir_al_menu() -> void:
	visible = false
	Interfaz.preguntar("¿Salir al menú? Se perderá lo que no hayas guardado.", ["Salir al menú", "Volver"], func(i: int) -> void:
		if i == 0:
			cerrado.emit()
			Escenas.ir_al_menu()
		else:
			abrir())


func _pedir_salir_del_juego() -> void:
	visible = false
	Interfaz.preguntar("¿Salir del juego? Se perderá lo que no hayas guardado.", ["Salir del juego", "Volver"], func(i: int) -> void:
		if i == 0:
			get_tree().quit()
		else:
			abrir())


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel")):
		cerrar_panel()
		get_viewport().set_input_as_handled()
