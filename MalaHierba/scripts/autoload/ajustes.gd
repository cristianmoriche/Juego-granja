extends Node
## Preferencias independientes de la partida. Se aplican antes de construir los menús.

signal cambiado(clave: String)
const RUTA := "user://ajustes.cfg"
const RESOLUCIONES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const DEFECTO := {"general": 1.0, "musica": 0.8, "efectos": 1.0, "ambiente": 0.8,
	"sensibilidad": 1.0, "resolucion": 1, "pantalla_completa": false, "calidad": 2,
	"texto": 0, "alto_contraste": false, "reducir_movimiento": false, "tutorial": true}
const ACCIONES := {"mover_arriba": "Avanzar", "mover_abajo": "Retroceder", "mover_izquierda": "Izquierda",
	"mover_derecha": "Derecha", "correr": "Correr", "saltar": "Saltar", "agachar": "Agacharse",
	"interactuar": "Interactuar", "usar": "Usar herramienta", "inventario": "Inventario", "mapa": "Mapa", "diario": "Diario de misiones",
	"pausa": "Pausa", "camara_reiniciar": "Centrar cámara", "pantalla_completa": "Pantalla completa",
	"cerrar_tutorial": "Cerrar aviso",
	"ranura_1": "Ranura 1", "ranura_2": "Ranura 2", "ranura_3": "Ranura 3", "ranura_4": "Ranura 4",
	"ranura_5": "Ranura 5", "ranura_6": "Ranura 6", "ranura_7": "Ranura 7", "ranura_8": "Ranura 8",
	"ranura_9": "Ranura 9", "ranura_10": "Ranura 10"}
var valores: Dictionary = DEFECTO.duplicate()
var teclas: Dictionary = {}
var ruta := RUTA
var ultimo_error := OK
var ultimo_mando := false
var _originales: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for accion: String in ACCIONES:
		_originales[accion] = InputMap.action_get_events(accion).duplicate()
	_crear_mando()
	_crear_buses()
	cargar()
	get_tree().node_added.connect(_nodo_anadido)
	get_window().size_changed.connect(_escala_render)
	_conectar_mapa.call_deferred()

func _conectar_mapa() -> void:
	Escenas.mapa_cargado.connect(func(_id: String) -> void: aplicar_graficos())
	aplicar_interfaz()

func _crear_buses() -> void:
	for nombre: String in ["Musica", "Efectos", "Ambiente"]:
		if AudioServer.get_bus_index(nombre) < 0:
			AudioServer.add_bus()
			var indice := AudioServer.bus_count - 1
			AudioServer.set_bus_name(indice, nombre)
			AudioServer.set_bus_send(indice, "Master")

func poner(clave: String, valor: Variant) -> void:
	if not DEFECTO.has(clave):
		return
	valores[clave] = _validar(clave, valor)
	aplicar(clave)
	guardar()
	cambiado.emit(clave)

func _validar(clave: String, valor: Variant) -> Variant:
	match clave:
		"general", "musica", "efectos", "ambiente": return clampf(float(valor), 0.0, 1.0)
		"sensibilidad": return clampf(float(valor), 0.25, 3.0)
		"resolucion": return clampi(int(valor), 0, 4)
		"calidad", "texto": return clampi(int(valor), 0, 2)
		_: return bool(valor)

func guardar() -> bool:
	var cfg := ConfigFile.new()
	for clave: String in valores:
		cfg.set_value("ajustes", clave, valores[clave])
	for accion: String in teclas:
		cfg.set_value("teclas", accion, teclas[accion])
	ultimo_error = cfg.save(ruta)
	return ultimo_error == OK

func cargar() -> void:
	valores = DEFECTO.duplicate()
	teclas.clear()
	var cfg := ConfigFile.new()
	if cfg.load(ruta) == OK:
		for clave: String in DEFECTO:
			var valor: Variant = cfg.get_value("ajustes", clave, DEFECTO[clave])
			if typeof(valor) == typeof(DEFECTO[clave]) or (valor is float and DEFECTO[clave] is int) or (valor is int and DEFECTO[clave] is float):
				valores[clave] = _validar(clave, valor)
		for accion: String in ACCIONES:
			var codigo := int(cfg.get_value("teclas", accion, 0))
			if codigo > 0:
				teclas[accion] = codigo
	_aplicar_teclas()
	aplicar()
	cambiado.emit("")

func restaurar() -> void:
	valores = DEFECTO.duplicate()
	restaurar_teclas()
	aplicar()
	guardar()
	cambiado.emit("")

func restaurar_teclas() -> void:
	teclas.clear()
	_aplicar_teclas()
	guardar()

func conflicto(accion: String, codigo: int) -> String:
	for otra: String in ACCIONES:
		if otra == accion:
			continue
		for evento: InputEvent in InputMap.action_get_events(otra):
			if evento is InputEventKey and (evento.physical_keycode == codigo or evento.keycode == codigo):
				return otra
	return ""

func remapear(accion: String, codigo: int) -> bool:
	if not ACCIONES.has(accion) or codigo <= 0 or not conflicto(accion, codigo).is_empty():
		return false
	teclas[accion] = codigo
	_aplicar_teclas()
	guardar()
	return true

func _aplicar_teclas() -> void:
	for accion: String in _originales:
		# Conserva los botones y ejes del mando; sustituye solo teclado y ratón.
		for evento: InputEvent in InputMap.action_get_events(accion):
			if evento is InputEventKey or evento is InputEventMouseButton:
				InputMap.action_erase_event(accion, evento)
		if teclas.has(accion):
			var evento := InputEventKey.new()
			evento.physical_keycode = int(teclas[accion])
			InputMap.action_add_event(accion, evento)
		else:
			for evento: InputEvent in _originales[accion]:
				InputMap.action_add_event(accion, evento)

func texto_tecla(accion: String) -> String:
	var textos: PackedStringArray = []
	for evento: InputEvent in InputMap.action_get_events(accion):
		if evento is InputEventKey:
			var nombre := OS.get_keycode_string(evento.physical_keycode if evento.physical_keycode else evento.keycode)
			var traducciones := {"Up": "Arriba", "Down": "Abajo", "Left": "Izquierda", "Right": "Derecha", "Shift": "Mayús", "Space": "Espacio", "Enter": "Intro", "Escape": "Esc", "Backspace": "Retroceso", "Delete": "Supr", "Home": "Inicio", "End": "Fin", "PageUp": "RePág", "PageDown": "AvPág", "Insert": "Insertar"}
			textos.append(str(traducciones.get(nombre, nombre)))
		elif evento is InputEventMouseButton:
			textos.append("Clic izquierdo" if evento.button_index == MOUSE_BUTTON_LEFT else "Ratón")
	return " / ".join(textos)

func pista(accion: String) -> String:
	if ultimo_mando:
		return str({"interactuar": "A", "inventario": "Y", "usar": "X", "saltar": "B", "pausa": "Start", "mapa": "View", "correr": "L3", "agachar": "LB", "camara_reiniciar": "R3", "cerrar_tutorial": "RB"}.get(accion, texto_tecla(accion)))
	return texto_tecla(accion).split(" / ")[0]

func _input(evento: InputEvent) -> void:
	registrar_dispositivo(evento)

func registrar_dispositivo(evento: InputEvent) -> void:
	if evento is InputEventJoypadButton and evento.pressed:
		ultimo_mando = true
	elif evento is InputEventJoypadMotion and absf(evento.axis_value) > 0.3:
		ultimo_mando = true
	elif (evento is InputEventKey or evento is InputEventMouseButton) and evento.pressed:
		ultimo_mando = false
	elif evento is InputEventMouseMotion and evento.relative.length() > 2.0:
		ultimo_mando = false

func aplicar(clave: String = "") -> void:
	if clave.is_empty() or clave in ["general", "musica", "efectos", "ambiente"]:
		for par: Array in [["general", "Master"], ["musica", "Musica"], ["efectos", "Efectos"], ["ambiente", "Ambiente"]]:
			var indice := AudioServer.get_bus_index(par[1])
			AudioServer.set_bus_volume_db(indice, linear_to_db(maxf(0.0001, valores[par[0]])))
			AudioServer.set_bus_mute(indice, valores[par[0]] == 0.0)
	if clave.is_empty() or clave in ["pantalla_completa", "resolucion"]:
		aplicar_ventana()
	if clave.is_empty() or clave == "calidad":
		aplicar_graficos()
	if clave.is_empty() or clave in ["texto", "alto_contraste"]:
		aplicar_interfaz()

func resolucion_elegida() -> Vector2i:
	return DisplayServer.screen_get_size() if int(valores.resolucion) == 4 else RESOLUCIONES[int(valores.resolucion)]

func aplicar_ventana() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if valores.pantalla_completa else DisplayServer.WINDOW_MODE_WINDOWED)
	# Mantiene el tamaño lógico de la interfaz; la resolución completa se aplica al render 3D.
	get_window().content_scale_size = Vector2i(1600, 900)
	if not valores.pantalla_completa:
		DisplayServer.window_set_size(resolucion_elegida())
		DisplayServer.window_set_position((DisplayServer.screen_get_size() - resolucion_elegida()) / 2)
	_escala_render.call_deferred()

func _escala_render() -> void:
	var escala: float = [0.75, 0.9, 1.0][int(valores.calidad)]
	if valores.pantalla_completa and DisplayServer.get_name() != "headless":
		var ventana := DisplayServer.window_get_size()
		escala *= minf(float(resolucion_elegida().x) / maxf(1, ventana.x), float(resolucion_elegida().y) / maxf(1, ventana.y))
	get_viewport().scaling_3d_scale = clampf(escala, 0.25, 2.0)

func aplicar_graficos() -> void:
	var calidad := int(valores.calidad)
	_escala_render()
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD if calidad == 0 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD if calidad == 0 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	_graficos_nodo(get_tree().root, calidad)

func _graficos_nodo(nodo: Node, calidad: int) -> void:
	if nodo is WorldEnvironment and nodo.environment != null:
		nodo.environment.ssao_enabled = calidad > 0
		nodo.environment.ssr_enabled = calidad == 2
	if nodo is Camera3D and nodo.get_parent() is CamaraJuego:
		nodo.far = [100.0, 300.0, 700.0][calidad]
	if nodo is GeometryInstance3D:
		if not nodo.has_meta("alcance_original"):
			nodo.set_meta("alcance_original", nodo.visibility_range_end)
		var original := float(nodo.get_meta("alcance_original"))
		var limite: float = [90.0, 180.0, 0.0][calidad]
		nodo.visibility_range_end = minf(original, limite) if original > 0.0 and limite > 0.0 else maxf(original, limite)
		if calidad == 2:
			nodo.visibility_range_end = original
	for hijo: Node in nodo.get_children():
		_graficos_nodo(hijo, calidad)

func _nodo_anadido(nodo: Node) -> void:
	if nodo is Control:
		# Algunas pruebas y paneles crean y destruyen controles en el mismo fotograma.
		_control_pendiente.call_deferred(nodo.get_instance_id())

func _control_pendiente(identificador: int) -> void:
	var nodo: Object = instance_from_id(identificador)
	if is_instance_valid(nodo) and nodo is Control:
		_interfaz_nodo(nodo as Control)

func aplicar_interfaz() -> void:
	_recorrer_interfaz(get_tree().root)

func _recorrer_interfaz(nodo: Node) -> void:
	if nodo is Control:
		_interfaz_nodo(nodo)
	for hijo: Node in nodo.get_children():
		_recorrer_interfaz(hijo)

func _interfaz_nodo(nodo: Node) -> void:
	if not is_instance_valid(nodo) or not nodo is Control:
		return
	var c := nodo as Control
	if not c.has_meta("estilo_original"):
		var original := {"tamanos": {}, "colores": {}, "cajas": {}}
		for propiedad: String in ["font_size", "normal_font_size", "bold_font_size"]:
			original.tamanos[propiedad] = c.get_theme_font_size(propiedad)
		for propiedad: String in ["font_color", "font_hover_color", "font_focus_color", "default_color"]:
			original.colores[propiedad] = c.get_theme_color(propiedad)
		for propiedad: String in ["panel", "normal", "hover", "pressed", "focus"]:
			var caja := c.get_theme_stylebox(propiedad)
			if caja is StyleBoxFlat:
				original.cajas[propiedad] = caja.duplicate()
		c.set_meta("estilo_original", original)
	var original: Dictionary = c.get_meta("estilo_original")
	var factor := float([1.0, 1.18, 1.35][int(valores.texto)])
	for propiedad: String in original.tamanos:
		c.add_theme_font_size_override(propiedad, roundi(int(original.tamanos[propiedad]) * factor))
	for propiedad: String in original.colores:
		c.add_theme_color_override(propiedad, Color.WHITE if valores.alto_contraste else original.colores[propiedad])
	for propiedad: String in original.cajas:
		var caja := (original.cajas[propiedad] as StyleBoxFlat).duplicate() as StyleBoxFlat
		if valores.alto_contraste:
			caja.bg_color = Color.BLACK
			caja.border_color = Color.YELLOW if propiedad == "focus" else Color.WHITE
		c.add_theme_stylebox_override(propiedad, caja)
	if c is OptionButton:
		var desplegable: PopupMenu = c.get_popup()
		desplegable.add_theme_font_override("font", Estilo.fuente())
		desplegable.add_theme_font_size_override("font_size", roundi(Estilo.TAM_TEXTO * factor))
		desplegable.add_theme_color_override("font_color", Color.WHITE if valores.alto_contraste else Estilo.COLOR_TEXTO)
		desplegable.add_theme_color_override("font_hover_color", Color.WHITE)
		desplegable.add_theme_stylebox_override("panel", Estilo.caja(Color.BLACK if valores.alto_contraste else Estilo.COLOR_FONDO, Color.WHITE if valores.alto_contraste else Estilo.COLOR_BORDE))
		desplegable.add_theme_stylebox_override("hover", Estilo.caja(Color(0.25, 0.18, 0.09), Color.YELLOW if valores.alto_contraste else Estilo.COLOR_ACENTO))
	c.queue_redraw()

func _boton_mando(accion: String, boton: JoyButton) -> void:
	if not InputMap.has_action(accion):
		InputMap.add_action(accion, 0.22)
	var evento := InputEventJoypadButton.new()
	evento.button_index = boton
	InputMap.action_add_event(accion, evento)

func _eje_mando(accion: String, eje: JoyAxis, valor: float) -> void:
	if not InputMap.has_action(accion):
		InputMap.add_action(accion, 0.22)
	var evento := InputEventJoypadMotion.new()
	evento.axis = eje
	evento.axis_value = valor
	InputMap.action_add_event(accion, evento)

func _crear_mando() -> void:
	for par: Array in [["mover_izquierda", JOY_AXIS_LEFT_X, -1.0], ["mover_derecha", JOY_AXIS_LEFT_X, 1.0], ["mover_arriba", JOY_AXIS_LEFT_Y, -1.0], ["mover_abajo", JOY_AXIS_LEFT_Y, 1.0], ["camara_izquierda", JOY_AXIS_RIGHT_X, -1.0], ["camara_derecha", JOY_AXIS_RIGHT_X, 1.0], ["camara_arriba", JOY_AXIS_RIGHT_Y, -1.0], ["camara_abajo", JOY_AXIS_RIGHT_Y, 1.0]]:
		_eje_mando(par[0], par[1], par[2])
	for par: Array in [["interactuar", JOY_BUTTON_A], ["saltar", JOY_BUTTON_B], ["usar", JOY_BUTTON_X], ["inventario", JOY_BUTTON_Y], ["correr", JOY_BUTTON_LEFT_STICK], ["agachar", JOY_BUTTON_LEFT_SHOULDER], ["camara_reiniciar", JOY_BUTTON_RIGHT_STICK], ["cerrar_tutorial", JOY_BUTTON_RIGHT_SHOULDER], ["pausa", JOY_BUTTON_START], ["mapa", JOY_BUTTON_BACK], ["ranura_anterior", JOY_BUTTON_DPAD_LEFT], ["ranura_siguiente", JOY_BUTTON_DPAD_RIGHT], ["ui_cancel", JOY_BUTTON_B]]:
		_boton_mando(par[0], par[1])
	# Godot ya asigna cruceta y palanca izquierda a ui_*; A confirma y B vuelve.
	_boton_mando("ui_accept", JOY_BUTTON_A)
