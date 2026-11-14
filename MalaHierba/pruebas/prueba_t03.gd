extends Node
## Regresión de foco, física detenida y preguntas reemplazadas en el mismo fotograma.
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

func _esperar() -> void:
	await get_tree().create_timer(0.9, true).timeout

func _ejecutar() -> void:
	get_tree().current_scene = null
	Juego.nueva_partida("Prueba de foco")
	Escenas.ir_a_mapa("prueba")
	await Escenas.mapa_cargado
	while Escenas.en_transicion:
		await get_tree().process_frame
	Interfaz.cerrar_todo()
	await _esperar()
	_comprobar(Juego.tiempo_corre(), "el reloj arranca con Leo en el mapa")
	var j := Escenas.jugador() as Jugador
	Input.action_press("mover_arriba")
	await _esperar()
	_comprobar(j.velocity.length() > 0.1, "Leo se mueve antes de perder el foco")
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var pos := j.global_position
	var minutos := Juego.minutos
	var acumulado: float = Juego._acumulado
	await _esperar()
	_comprobar(get_tree().paused and not Juego.tiempo_corre(), "sin foco el árbol y el tiempo quedan pausados")
	_comprobar(j.global_position == pos, "la física queda detenida aunque haya movimiento pulsado")
	_comprobar(Juego.minutos == minutos and Juego._acumulado == acumulado, "no avanza ni se acumula tiempo sin foco")
	Input.action_release("mover_arriba")
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _esperar()
	_comprobar(not get_tree().paused and Juego.minutos > minutos, "recuperar foco reanuda el reloj sin duplicar tiempo")
	Juego.pausar_tiempo(true)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_comprobar(not Juego.tiempo_corre(), "recuperar foco respeta la pausa externa")
	Juego.pausar_tiempo(false)
	Interfaz.get_node("Raiz/Pausa").abrir()
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_comprobar(Interfaz.ocupada() and not Juego.tiempo_corre(), "el menú sigue abierto y el reloj parado al regresar")
	Interfaz.cerrar_todo()
	_comprobar(Juego.tiempo_corre(), "cerrar el menú permite continuar")
	get_tree().paused = true
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Juego.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_comprobar(get_tree().paused, "conserva una pausa previa del árbol")
	get_tree().paused = false
	var p := Interfaz.get_node("Raiz/Pregunta") as PanelPregunta
	p.abrir("Primera", ["Cambiar"], func(_i: int) -> void: pass)
	var anterior := p._botones[0]
	p.abrir("Segunda", ["Seguir"], func(_i: int) -> void: pass)
	_comprobar(not anterior.is_inside_tree(), "la opción sustituida ya está fuera del árbol")
	await get_tree().process_frame
	await get_tree().process_frame
	_comprobar(p._botones[0].has_focus(), "solo recibe foco la opción vigente")
	p._elegir(0)
	p.abrir("Cierre inmediato", ["Cerrar"], func(_i: int) -> void: pass)
	p._elegir(0)
	await get_tree().process_frame
	_comprobar(not p.visible, "la llamada diferida respeta la pregunta cerrada")
	Interfaz.cerrar_todo()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		await _esperar()
		_comprobar(Juego._pausa_por_ventana and get_tree().paused, "minimizar la ventana real pausa el juego")
		var min0 := Juego.minutos
		await _esperar()
		_comprobar(Juego.minutos == min0, "minimizada la ventana real no corre el reloj")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()
		await _esperar()
		_comprobar(not Juego._sin_foco and not get_tree().paused, "restaurar la ventana real reanuda el juego")
		Interfaz.get_node("Raiz/Pausa").abrir()
		await RenderingServer.frame_post_draw
		var ruta := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T03-foco-y-errores/pausa_recuperada.png")
		DirAccess.make_dir_recursive_absolute(ruta.get_base_dir())
		_comprobar(get_viewport().get_texture().get_image().save_png(ruta) == OK, "captura del menú conservado")
	print("PRUEBA OK (%d comprobaciones)" % _total if _fallos.is_empty() else "PRUEBA FALLO: " + "; ".join(_fallos))
	get_tree().quit(0 if _fallos.is_empty() else 1)
