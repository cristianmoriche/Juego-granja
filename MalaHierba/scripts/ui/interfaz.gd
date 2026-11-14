extends CanvasLayer
## Interfaz del juego (autoload «Interfaz», escena res://escenas/ui/interfaz.tscn): HUD, diálogos, preguntas,
## inventario, tienda, pausa y pantalla de carga. Todo se construye en código con el tema de Estilo.

var _hud: Hud
var _dialogo: PanelDialogo
var _pregunta: PanelPregunta
var _inventario: PanelInventario
var _tienda: PanelTienda
var _pausa: PanelPausa
var _ajustes: PanelAjustes
var _mapa_grande: MapaGrande
var _diario: PanelDiario
var _carpinteria: PanelCarpinteria
var _capa_flotante: Control
var _capa_negra: CanvasLayer
var _negro: ColorRect
var _l_carga: Label
var _tween_fundido: Tween
var _hud_visible: bool = false
## Cuántos avisos se han mostrado en total (el jugador lo usa para saber si algo ya explicó por qué no pasó nada).
var avisos_emitidos: int = 0


func _ready() -> void:
	layer = 10
	var raiz := Control.new()
	raiz.name = "Raiz"
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.theme = Estilo.tema()
	add_child(raiz)

	_hud = Hud.new()
	_hud.name = "Hud"
	raiz.add_child(_hud)
	_dialogo = PanelDialogo.new()
	_dialogo.name = "Dialogo"
	raiz.add_child(_dialogo)
	_inventario = PanelInventario.new()
	_inventario.name = "Inventario"
	raiz.add_child(_inventario)
	_tienda = PanelTienda.new()
	_tienda.name = "Tienda"
	raiz.add_child(_tienda)
	_pausa = PanelPausa.new()
	_pausa.name = "Pausa"
	raiz.add_child(_pausa)
	_mapa_grande = MapaGrande.new()
	_mapa_grande.name = "MapaGrande"
	raiz.add_child(_mapa_grande)
	_diario = PanelDiario.new()
	_diario.name = "Diario"
	raiz.add_child(_diario)
	_carpinteria = PanelCarpinteria.new()
	_carpinteria.name = "Carpinteria"
	raiz.add_child(_carpinteria)
	_pregunta = PanelPregunta.new()
	_pregunta.name = "Pregunta"
	raiz.add_child(_pregunta)
	_ajustes = PanelAjustes.new()
	_ajustes.name = "Ajustes"
	raiz.add_child(_ajustes)
	_capa_flotante = Control.new()
	_capa_flotante.name = "CapaFlotante"
	_capa_flotante.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capa_flotante.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(_capa_flotante)

	# Capa propia por encima de todo para el fundido y el rótulo «Cargando…».
	_capa_negra = CanvasLayer.new()
	_capa_negra.layer = 100
	add_child(_capa_negra)
	_negro = ColorRect.new()
	_negro.color = Color(0.02, 0.015, 0.012, 0.0)
	_negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_negro.visible = false
	_capa_negra.add_child(_negro)
	_l_carga = Estilo.etiqueta("Cargando…", Estilo.TAM_TITULO, Estilo.COLOR_ACENTO)
	_l_carga.theme = Estilo.tema()
	_l_carga.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_l_carga.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_carga.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_l_carga.visible = false
	_capa_negra.add_child(_l_carga)

	mostrar_hud(false)
	Juego.mensaje.connect(mensaje)
	Juego.mensaje_objeto.connect(_al_mensaje_objeto)
	Juego.nombre_jugador = Juego.nombre_jugador   # sin efecto: asegura que el autoload Juego ya existe


# --- API pública ---------------------------------------------------------------------

func mensaje(texto: String, id_icono: String = "") -> void:
	avisos_emitidos += 1
	_hud.aviso(texto, id_icono)


func _al_mensaje_objeto(texto: String, id_icono: String = "") -> void:
	if not _hud_visible:
		return
	mensaje(texto, id_icono)


## Número flotante discreto con el dinero cobrado (+X €) sobre el marcador de dinero visible.
func mostrar_dinero_flotante(cantidad: int) -> void:
	if cantidad <= 0 or _capa_flotante == null:
		return
	var l := Estilo.etiqueta("+" + Estilo.euros(cantidad), Estilo.TAM_GRANDE + 3, Color(0.92, 0.80, 0.42))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.92))
	var apilado := float(_capa_flotante.get_child_count()) * 26.0
	_capa_flotante.add_child(l)
	var tam := l.get_combined_minimum_size()
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var pos := Vector2(maxf(vp.x - 190.0, 20.0), 100.0)
	if _tienda != null and _tienda.visible and _tienda._l_dinero != null:
		var r := _tienda._l_dinero.get_global_rect()
		if r.size.x > 1.0:
			pos = Vector2(r.end.x - maxf(tam.x, 90.0) - 4.0, maxf(16.0, r.position.y - 10.0 - apilado))
	elif _hud != null and _hud_visible:
		var r_hud := _hud.rect_dinero()
		if r_hud.size.x > 1.0:
			pos = Vector2(maxf(20.0, r_hud.position.x - maxf(tam.x, 80.0) - 14.0), maxf(16.0, r_hud.position.y - 2.0 - apilado))
	l.position = pos
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", pos.y - 34.0, 1.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.72).set_delay(0.42)
	t.chain().tween_callback(l.queue_free)


func numeros_flotantes_activos() -> int:
	return _capa_flotante.get_child_count() if _capa_flotante != null else 0


func avisos_activos() -> int:
	return _hud.avisos_activos() if _hud != null else 0


## Cuadro de diálogo. `lineas`: textos (String) o diccionarios {"nombre", "texto"}.
func mostrar_dialogo(nombre: String, lineas: Array, al_terminar: Callable = Callable()) -> void:
	_dialogo.abrir(nombre, lineas, al_terminar)


## Pregunta con opciones; al_elegir(indice: int).
func preguntar(texto: String, opciones: Array, al_elegir: Callable) -> void:
	_pregunta.abrir(texto, opciones, al_elegir)


func abrir_tienda(id_tienda: String) -> void:
	Audio.reproducir("ui_menu")
	_tienda.abrir(id_tienda)


func abrir_ajustes() -> void:
	Audio.reproducir("ui_menu")
	_ajustes.abrir()


## Vecinos de foco dentro del panel: el mando nunca salta a un botón que esté detrás del modal.
func limitar_foco(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_visible_in_tree():
		return
	var controles: Array[Control] = []
	_recoger_focos(panel, controles)
	for control: Control in controles:
		var centro := control.get_global_rect().get_center()
		var direcciones := {"focus_neighbor_left": Vector2.LEFT, "focus_neighbor_right": Vector2.RIGHT,
			"focus_neighbor_top": Vector2.UP, "focus_neighbor_bottom": Vector2.DOWN}
		for propiedad: String in direcciones:
			var direccion: Vector2 = direcciones[propiedad]
			var vecino := control
			var mejor := INF
			for candidato: Control in controles:
				if candidato == control:
					continue
				var diferencia := candidato.get_global_rect().get_center() - centro
				var avance := diferencia.dot(direccion)
				var lateral := absf(diferencia.cross(direccion))
				var coste := avance + lateral * 0.5
				if avance > 1.0 and coste < mejor:
					mejor = coste
					vecino = candidato
			control.set(propiedad, control.get_path_to(vecino))

func _recoger_focos(nodo: Node, controles: Array[Control]) -> void:
	if nodo is Control and nodo.is_visible_in_tree() and nodo.focus_mode == Control.FOCUS_ALL:
		if not nodo is BaseButton or not nodo.disabled:
			controles.append(nodo)
	for hijo: Node in nodo.get_children():
		_recoger_focos(hijo, controles)


func abrir_inventario() -> void:
	if not ocupada():
		Audio.reproducir("ui_menu")
		_inventario.abrir()


func mostrar_accion(texto: String) -> void:
	_hud.mostrar_accion(texto)


func ocultar_accion() -> void:
	_hud.ocultar_accion()


func texto_accion() -> String:
	return _hud.texto_accion()


func minimapa() -> Minimapa:
	return _hud.minimapa()


func mapa_grande_abierto() -> bool:
	return _mapa_grande != null and _mapa_grande.visible


func alternar_mapa() -> void:
	if _mapa_grande == null:
		return
	if _mapa_grande.visible:
		_mapa_grande.cerrar()
	elif not ocupada():
		Audio.reproducir("ui_menu")
		_mapa_grande.abrir(_hud.minimapa())


func abrir_diario(pestana: String = "") -> void:
	if _diario == null:
		return
	if _diario.visible:
		_diario.cerrar()
	elif _pausa != null and _pausa.visible:
		_pausa.cerrar_panel()
		Audio.reproducir("ui_menu")
		_diario.abrir(pestana)
	elif not ocupada():
		Audio.reproducir("ui_menu")
		_diario.abrir(pestana)


func diario_abierto() -> bool:
	return _diario != null and _diario.visible


func abrir_carpinteria() -> void:
	if _carpinteria == null:
		return
	if _carpinteria.visible:
		_carpinteria.cerrar_panel()
	elif not ocupada():
		Audio.reproducir("ui_menu")
		_carpinteria.abrir()


func carpinteria_abierta() -> bool:
	return _carpinteria != null and _carpinteria.visible


## Muestra u oculta el HUD de juego (reloj, energía, barra rápida). Los avisos siguen visibles.
func mostrar_hud(v: bool) -> void:
	_hud_visible = v
	_hud.mostrar_juego(v)
	if v:
		_hud.refrescar()
	else:
		_hud.limpiar_avisos()


func hud_visible() -> bool:
	return _hud_visible


## Hay un panel modal abierto: el jugador no se mueve y el tiempo se para.
func ocupada() -> bool:
	return _ajustes.visible or _dialogo.visible or _pregunta.visible or _inventario.visible or _tienda.visible or _pausa.visible or (_mapa_grande != null and _mapa_grande.visible) or (_diario != null and _diario.visible) or (_carpinteria != null and _carpinteria.visible)


func cerrar_todo() -> void:
	if _ajustes.visible:
		_ajustes.cerrar()
	_dialogo.visible = false
	_pregunta.visible = false
	_inventario.visible = false
	_tienda.visible = false
	_pausa.visible = false
	if _diario != null:
		_diario.cerrar()
	if _carpinteria != null:
		_carpinteria.cerrar_panel()
	if _mapa_grande != null:
		_mapa_grande.cerrar()
	_hud.ocultar_accion()


# --- Fundido y pantalla de carga --------------------------------------------------------

func fundido_a_negro(duracion: float = 0.35) -> void:
	if _tween_fundido != null and _tween_fundido.is_valid():
		_tween_fundido.kill()
	_negro.visible = true
	_negro.mouse_filter = Control.MOUSE_FILTER_STOP
	if _negro.color.a >= 0.99:
		return
	_tween_fundido = create_tween()
	_tween_fundido.tween_property(_negro, "color:a", 1.0, duracion)
	await _tween_fundido.finished


func fundido_desde_negro(duracion: float = 0.35) -> void:
	if _tween_fundido != null and _tween_fundido.is_valid():
		_tween_fundido.kill()
	_l_carga.visible = false
	_tween_fundido = create_tween()
	_tween_fundido.tween_property(_negro, "color:a", 0.0, duracion)
	await _tween_fundido.finished
	_negro.visible = false
	_negro.mouse_filter = Control.MOUSE_FILTER_IGNORE


func mostrar_carga(v: bool) -> void:
	_l_carga.visible = v
	if v:
		_negro.visible = true
		_negro.color.a = 1.0


# --- Entrada global ---------------------------------------------------------------------

func _decoracion_activa() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("decoracion_casa")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pantalla_completa"):
		Ajustes.poner("pantalla_completa", not Ajustes.valores.pantalla_completa)
		get_viewport().set_input_as_handled()
		return
	# El resto solo vale con un jugador en un mapa.
	if not _hud_visible or Escenas.en_transicion or Escenas.jugador() == null:
		return
	if _carpinteria != null and _carpinteria.visible and (event.is_action_pressed("pausa") or event.is_action_pressed("ui_cancel")):
		_carpinteria.cerrar_panel()
		get_viewport().set_input_as_handled()
		return
	if _mapa_grande.visible and event.is_action_pressed("ui_cancel"):
		_mapa_grande.cerrar()
		get_viewport().set_input_as_handled()
		return
	if not ocupada() and Tutorial.hay_aviso_activo() and event.is_action_pressed("cerrar_tutorial"):
		Tutorial.cerrar_actual()
		get_viewport().set_input_as_handled()
		return
	var deco := _decoracion_activa()
	var decorando := deco != null and bool(deco.call("esta_decorando"))
	var pulsa_mapa := event.is_action_pressed("mapa") if InputMap.has_action("mapa") else false
	if not InputMap.has_action("mapa") and not pulsa_mapa and event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and (ek.keycode == KEY_M or ek.physical_keycode == KEY_M):
			pulsa_mapa = true
	if pulsa_mapa and (_mapa_grande.visible or not ocupada()):
		alternar_mapa()
		get_viewport().set_input_as_handled()
		return
	var pulsa_diario := event.is_action_pressed("diario") if InputMap.has_action("diario") else false
	if not InputMap.has_action("diario") and not pulsa_diario and event is InputEventKey:
		var ek_d := event as InputEventKey
		if ek_d.pressed and not ek_d.echo and (ek_d.keycode == KEY_J or ek_d.physical_keycode == KEY_J):
			pulsa_diario = true
	if pulsa_diario and (_diario.visible or not ocupada()):
		abrir_diario()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pausa"):
		if decorando:
			deco.call("salir_modo_decorar")
			get_viewport().set_input_as_handled()
			return
		if _mapa_grande != null and _mapa_grande.visible:
			_mapa_grande.cerrar()
			get_viewport().set_input_as_handled()
			return
		if not ocupada():
			_pausa.abrir()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inventario") and not ocupada():
		_inventario.abrir()
		get_viewport().set_input_as_handled()
		return
	if not ocupada() and (event.is_action_pressed("ranura_anterior") or event.is_action_pressed("ranura_siguiente")):
		Juego.elegir_ranura(Juego.ranura + (1 if event.is_action_pressed("ranura_siguiente") else -1))
		get_viewport().set_input_as_handled()
		return
	if not ocupada() or _inventario.visible:
		for i in 10:
			if event.is_action_pressed("ranura_%d" % (i + 1)):
				Juego.elegir_ranura(i)
				get_viewport().set_input_as_handled()
				return
	# La rueda del ratón cambia el objeto seleccionado de la barra dando la vuelta en los extremos
	# (salvo mientras se está girando o colocando un mueble en el modo decorar).
	if not ocupada() and not (deco != null and bool(deco.call("consume_rueda"))) and event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				Juego.elegir_ranura(Juego.ranura - 1)
				get_viewport().set_input_as_handled()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				Juego.elegir_ranura(Juego.ranura + 1)
				get_viewport().set_input_as_handled()
