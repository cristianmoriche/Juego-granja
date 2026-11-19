extends Node
## Regresión de preferencias, aplicación real, mando, foco y conservación entre procesos.

const CONFIG_PRUEBA := "user://ajustes_prueba.cfg"
const ELEGIDOS := {"general": 0.35, "musica": 0.45, "efectos": 0.55, "ambiente": 0.65,
	"sensibilidad": 2.0, "resolucion": 0, "pantalla_completa": false, "calidad": 0, "limite_fps": 2,
	"texto": 2, "alto_contraste": true, "reducir_movimiento": true}
var _fallos: Array[String] = []
var _total := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ejecutar.call_deferred()

func _comprobar(condicion: bool, texto: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(texto)
		print("FALLO: ", texto)

func _fotogramas(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame

func _boton(boton: JoyButton, pulsado: bool = true) -> void:
	var evento := InputEventJoypadButton.new()
	evento.button_index = boton
	evento.pressed = pulsado
	Input.parse_input_event(evento)

func _eje(eje: JoyAxis, valor: float) -> void:
	var evento := InputEventJoypadMotion.new()
	evento.axis = eje
	evento.axis_value = valor
	Input.parse_input_event(evento)

func _pulsar(boton: JoyButton) -> void:
	_boton(boton)
	await _fotogramas()
	_boton(boton, false)
	await _fotogramas()

func _ejecutar() -> void:
	var valores_antes := Ajustes.valores.duplicate()
	var teclas_antes := Ajustes.teclas.duplicate()
	var ruta_antes := Ajustes.ruta
	Ajustes.ruta = CONFIG_PRUEBA
	if OS.get_environment("MH_AJUSTES_FASE") == "conservar":
		Ajustes.cargar()
		for clave: String in ELEGIDOS:
			_comprobar(Ajustes.valores[clave] == ELEGIDOS[clave], "otro proceso conserva " + clave)
		_comprobar(Ajustes.texto_tecla("mover_arriba") == "F7", "otro proceso conserva el remapeo")
		_comprobar(is_equal_approx(get_viewport().scaling_3d_scale, 0.75), "otro proceso aplica la calidad al arrancar")
	else:
		Ajustes.restaurar()
		# Construye un mapa real de pruebas, cámara orbital y jugador del juego.
		get_tree().current_scene = null
		Juego.nueva_partida("Prueba de ajustes")
		Juego.pausar_tiempo(true)
		Escenas.ir_a_mapa("prueba")
		await Escenas.mapa_cargado
		while Escenas.en_transicion:
			await get_tree().process_frame
		var jugador := Escenas.jugador() as Jugador
		var entorno := WorldEnvironment.new()
		entorno.environment = Environment.new()
		add_child(entorno)
		var malla := MeshInstance3D.new()
		malla.mesh = BoxMesh.new()
		malla.visibility_range_end = 250.0
		add_child(malla)
		for par: Array in [["general", "Master"], ["musica", "Musica"], ["efectos", "Efectos"], ["ambiente", "Ambiente"]]:
			var indice := AudioServer.get_bus_index(par[1])
			_comprobar(indice >= 0, "existe bus " + par[1])
			for volumen: float in [0.0, 0.4, 1.0]:
				Ajustes.poner(par[0], volumen)
				_comprobar(AudioServer.is_bus_mute(indice) == (volumen == 0.0), "silencio " + par[0])
				if volumen > 0.0:
					_comprobar(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(indice)), volumen), "volumen aplicado " + par[0])
		for calidad in 4:
			Ajustes.poner("calidad", calidad)
			_comprobar(is_equal_approx(get_viewport().scaling_3d_scale, [0.75, 0.80, 0.83, 1.0][calidad]), "escala de render " + str(calidad))
			_comprobar(entorno.environment.ssao_enabled == (calidad > 0), "SSAO " + str(calidad))
			_comprobar(entorno.environment.ssr_enabled == (calidad >= 3), "SSR " + str(calidad))
			_comprobar(jugador.camara.camara.far == [100.0, 220.0, 360.0, 600.0][calidad], "distancia de cámara " + str(calidad))
			_comprobar(malla.visibility_range_end == [90.0, 180.0, 250.0, 250.0][calidad], "restauración de distancia de malla " + str(calidad))
		Ajustes.poner("limite_fps", 2)
		_comprobar(int(Ajustes.valores.limite_fps) == 2 and Ajustes.fps_objetivo() == 60, "límite de FPS 60 seleccionado")
		Ajustes.poner("limite_fps", 0)
		for resolucion in 5:
			Ajustes.poner("resolucion", resolucion)
			var esperada: Vector2i = DisplayServer.screen_get_size() if resolucion == 4 else Ajustes.RESOLUCIONES[resolucion]
			_comprobar(Ajustes.resolucion_elegida() == esperada, "resolución " + str(resolucion))
			if DisplayServer.get_name() != "headless":
				await get_tree().create_timer(0.25).timeout
				_comprobar(DisplayServer.window_get_size() == esperada, "tamaño de ventana real " + str(resolucion))
		for completa: bool in [true, false]:
			Ajustes.poner("pantalla_completa", completa)
			if DisplayServer.get_name() != "headless":
				await get_tree().create_timer(0.3).timeout
				_comprobar(DisplayServer.window_get_mode() == (DisplayServer.WINDOW_MODE_FULLSCREEN if completa else DisplayServer.WINDOW_MODE_WINDOWED), "modo de ventana real")
		var etiqueta := Estilo.etiqueta("Prueba", 22)
		add_child(etiqueta)
		await _fotogramas()
		for tam in 3:
			Ajustes.poner("texto", tam)
			_comprobar(etiqueta.get_theme_font_size("font_size") == roundi(22 * [1.0, 1.18, 1.35][tam]), "texto " + str(tam))
		for contraste: bool in [true, false]:
			Ajustes.poner("alto_contraste", contraste)
			_comprobar(etiqueta.get_theme_color("font_color") == (Color.WHITE if contraste else Estilo.COLOR_TEXTO), "contraste reversible")
		etiqueta.queue_free()
		Ajustes.poner("sensibilidad", 2.5)
		var yaw := jugador.camara.yaw
		jugador.camara.entrada_mando(Vector2(1, 0), 0.1)
		_comprobar(is_equal_approx(angle_difference(yaw, jugador.camara.yaw), -0.5), "sensibilidad aplicada a la cámara del mando")
		Ajustes.poner("reducir_movimiento", true)
		jugador.camara.reiniciar_vista()
		_comprobar(not jugador.camara._volviendo and jugador.camara.pitch == jugador.camara._pitch_inicial(), "reducción de movimiento evita el barrido al centrar")
		Ajustes.poner("reducir_movimiento", false)
		jugador.camara.reiniciar_vista()
		_comprobar(jugador.camara._volviendo, "movimiento de cámara restaurado")
		_comprobar(not Ajustes.remapear("interactuar", KEY_W), "rechaza tecla en conflicto")
		_comprobar(Ajustes.conflicto("interactuar", KEY_W) == "mover_arriba", "identifica el conflicto")
		for accion: String in Ajustes.ACCIONES:
			_comprobar(Ajustes.remapear(accion, KEY_F7), "remapea " + accion)
			_comprobar(Ajustes.texto_tecla(accion) == "F7", "se aplica " + accion)
			Ajustes.restaurar_teclas()
		_comprobar(Ajustes.texto_tecla("mover_arriba").contains("W"), "restaura teclado")
		for accion: String in ["interactuar", "saltar", "usar", "inventario", "correr", "agachar", "pausa", "mapa", "bloquear", "esquivar", "fijar_objetivo"]:
			var tiene := false
			for evento: InputEvent in InputMap.action_get_events(accion):
				tiene = tiene or evento is InputEventJoypadButton or evento is InputEventJoypadMotion
			_comprobar(tiene, "mando conserva " + accion)
		_eje(JOY_AXIS_LEFT_X, 1.0)
		await _fotogramas()
		_comprobar(Input.get_action_strength("mover_derecha") > 0.9, "palanca mueve al jugador")
		_eje(JOY_AXIS_LEFT_X, 0.0)
		_eje(JOY_AXIS_RIGHT_X, 1.0)
		await _fotogramas()
		_comprobar(Input.get_action_strength("camara_derecha") > 0.9, "palanca de cámara")
		_eje(JOY_AXIS_RIGHT_X, 0.0)
		Interfaz.cerrar_todo()
		_boton(JOY_BUTTON_Y)
		await _fotogramas()
		_boton(JOY_BUTTON_Y, false)
		_comprobar(Interfaz._inventario.visible, "Y abre inventario")
		_comprobar(get_viewport().gui_get_focus_owner() is Hueco, "inventario tiene foco de mando")
		var primer_foco := get_viewport().gui_get_focus_owner()
		await _pulsar(JOY_BUTTON_DPAD_RIGHT)
		_comprobar(get_viewport().gui_get_focus_owner() != primer_foco and get_viewport().gui_get_focus_owner() is Hueco, "cruceta navega entre huecos")
		await _pulsar(JOY_BUTTON_A)
		_comprobar(Interfaz._inventario._origen >= 0, "A selecciona objeto para intercambiar")
		await _pulsar(JOY_BUTTON_DPAD_RIGHT)
		await _pulsar(JOY_BUTTON_A)
		_comprobar(Interfaz._inventario._origen == -1, "A intercambia el objeto")
		_boton(JOY_BUTTON_B)
		await _fotogramas()
		_boton(JOY_BUTTON_B, false)
		_comprobar(not Interfaz._inventario.visible, "B cierra inventario")
		_boton(JOY_BUTTON_START)
		await _fotogramas()
		_boton(JOY_BUTTON_START, false)
		_comprobar(Interfaz._pausa.visible, "Start abre pausa")
		await _pulsar(JOY_BUTTON_DPAD_DOWN)
		await _pulsar(JOY_BUTTON_DPAD_DOWN)
		_comprobar((get_viewport().gui_get_focus_owner() as Button).text == "Ajustes", "cruceta alcanza Ajustes en la pausa")
		await _pulsar(JOY_BUTTON_A)
		await _fotogramas()
		_comprobar(Interfaz.ocupada() and Interfaz._ajustes.visible, "ajustes son modales sobre pausa")
		await _pulsar(JOY_BUTTON_DPAD_RIGHT)
		await _pulsar(JOY_BUTTON_A)
		_comprobar(Interfaz._ajustes._pagina == 1, "mando cambia a Imagen")
		await _pulsar(JOY_BUTTON_DPAD_DOWN)
		_comprobar(get_viewport().gui_get_focus_owner() is OptionButton, "mando enfoca resolución")
		await _pulsar(JOY_BUTTON_A)
		await _pulsar(JOY_BUTTON_DPAD_DOWN)
		await _pulsar(JOY_BUTTON_A)
		_comprobar(int(Ajustes.valores.resolucion) != 4, "mando elige una resolución")
		for pagina in 4:
			Interfaz._ajustes._mostrar_pagina(pagina)
			await _fotogramas()
			_comprobar(Interfaz._ajustes._contenido.get_child_count() > 0, "página de ajustes " + str(pagina))
		var panel := Interfaz._ajustes
		panel._esperando = "interactuar"
		var tecla := InputEventKey.new()
		tecla.physical_keycode = KEY_W
		tecla.pressed = true
		Input.parse_input_event(tecla)
		await _fotogramas()
		_comprobar(panel._esperando == "interactuar" and panel._aviso.text.contains("Avanzar"), "el panel explica el conflicto sin aplicar la tecla")
		tecla = InputEventKey.new()
		tecla.physical_keycode = KEY_F8
		tecla.pressed = true
		Input.parse_input_event(tecla)
		await _fotogramas()
		_comprobar(panel._esperando.is_empty() and Ajustes.texto_tecla("interactuar") == "F8", "el panel captura y guarda una tecla libre")
		_comprobar(Ajustes.pista("interactuar") == "F8", "la pista respeta la tecla nueva")
		Ajustes.restaurar_teclas()
		panel._esperando = "interactuar"
		await _pulsar(JOY_BUTTON_B)
		_comprobar(panel.visible and panel._esperando.is_empty(), "B cancela la captura de tecla sin salir del panel")
		_boton(JOY_BUTTON_B)
		await _fotogramas()
		_boton(JOY_BUTTON_B, false)
		_comprobar(not Interfaz._ajustes.visible and Interfaz._pausa.visible, "B vuelve a la pausa")
		Interfaz.cerrar_todo()
		Interfaz.abrir_tienda("tienda_mateo")
		await _fotogramas()
		_comprobar(get_viewport().gui_get_focus_owner() is Button, "tienda navegable con mando")
		_boton(JOY_BUTTON_B)
		await _fotogramas()
		_boton(JOY_BUTTON_B, false)
		_comprobar(not Interfaz._tienda.visible, "B cierra tienda")
		Interfaz.alternar_mapa()
		await _pulsar(JOY_BUTTON_B)
		_comprobar(not Interfaz._mapa_grande.visible, "B cierra mapa")
		for par: Array in [["interactuar", JOY_BUTTON_A], ["esquivar", JOY_BUTTON_B], ["fijar_objetivo", JOY_BUTTON_RIGHT_STICK], ["usar", JOY_BUTTON_X], ["correr", JOY_BUTTON_LEFT_STICK], ["agachar", JOY_BUTTON_LEFT_SHOULDER]]:
			_boton(par[1])
			await _fotogramas()
			_comprobar(Input.is_action_pressed(par[0]), "entrada real del mando: " + par[0])
			_boton(par[1], false)
			await _fotogramas()
		_comprobar(Ajustes.pista("interactuar") == "A", "la pista cambia al usar el mando")
		var elegida := [-1]
		Interfaz.preguntar("Prueba de mando", ["Primera", "Segunda"], func(i: int) -> void: elegida[0] = i)
		await _fotogramas()
		await _pulsar(JOY_BUTTON_DPAD_DOWN)
		await _pulsar(JOY_BUTTON_A)
		_comprobar(elegida[0] == 1, "mando navega y confirma preguntas")
		# El menú inicial también abre los ajustes con la cruceta y A.
		Interfaz.cerrar_todo()
		Interfaz.mostrar_hud(false)
		var menu := load("res://escenas/menu_principal.tscn").instantiate() as Control
		add_child(menu)
		await _fotogramas()
		var encontrado := false
		for i in 5:
			var foco := get_viewport().gui_get_focus_owner() as Button
			if foco != null and foco.text == "Ajustes":
				encontrado = true
				break
			await _pulsar(JOY_BUTTON_DPAD_DOWN)
		_comprobar(encontrado, "cruceta alcanza Ajustes en el inicio")
		await _pulsar(JOY_BUTTON_A)
		_comprobar(Interfaz._ajustes.visible, "A abre Ajustes desde el inicio")
		await _pulsar(JOY_BUTTON_B)
		_comprobar(not Interfaz._ajustes.visible, "B devuelve al inicio")
		menu.queue_free()
		Ajustes.restaurar()
		_comprobar(int(Ajustes.valores.limite_fps) == 0, "restaura límite de FPS automático")
		for clave: String in ELEGIDOS:
			Ajustes.poner(clave, ELEGIDOS[clave])
		Ajustes.remapear("mover_arriba", KEY_F7)
		_comprobar(Ajustes.guardar(), "guarda configuración de prueba")
		# Reinicio de la configuración en memoria; se vuelve a leer del disco.
		Ajustes.valores = Ajustes.DEFECTO.duplicate()
		Ajustes.teclas.clear()
		Ajustes.cargar()
		for clave: String in ELEGIDOS:
			_comprobar(Ajustes.valores[clave] == ELEGIDOS[clave], "recarga conserva " + clave)
		_comprobar(Ajustes.texto_tecla("mover_arriba") == "F7", "recarga conserva tecla")
	Ajustes.ruta = ruta_antes
	Ajustes.valores = valores_antes
	Ajustes.teclas = teclas_antes
	Ajustes._aplicar_teclas()
	Ajustes.aplicar()
	if FileAccess.file_exists(CONFIG_PRUEBA):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PRUEBA))
	print("PRUEBA OK: %d comprobaciones de ajustes" % _total if _fallos.is_empty() else "PRUEBA FALLO: %d de %d" % [_fallos.size(), _total])
	get_tree().quit(0 if _fallos.is_empty() else 1)
