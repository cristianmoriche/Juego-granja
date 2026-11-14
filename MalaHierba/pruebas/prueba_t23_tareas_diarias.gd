extends Node
## Prueba completa de T23-tareas-diarias (~25+ plantillas, escala por progreso, caducidad, diario Hoy y guardado).

const RUTA_GUARDADO := "user://prueba_t23_save.json"

var _checks: int = 0
var _fallos: Array[String] = []


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("TIEMPO AGOTADO EN PRUEBA T23")
		get_tree().quit(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fallos.append(msg)
		push_error("FALLO T23: " + msg)


func _limpiar() -> void:
	if FileAccess.file_exists(RUTA_GUARDADO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_GUARDADO))


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	_limpiar()

	# 1. >=25 plantillas con los 6 tipos pedidos.
	var todas := TareasDiarias.todos_los_encargos()
	_ok(todas.size() >= 25, "al menos 25 plantillas (%d)" % todas.size())
	var tipos := {}
	for t: Dictionary in todas:
		var tipo := str(t.get("tipo", ""))
		tipos[tipo] = true
		_ok(not Datos.npc(str(t.get("npc", ""))).is_empty(), "NPC válido en plantilla %s" % str(t.get("id", "")))
	for req: String in ["entregar", "talar", "minar", "pescar", "regar", "regalar"]:
		_ok(tipos.has(req), "existe plantilla de tipo «%s»" % req)

	# 2. Tres tareas al día, coherentes por estación y con rotación.
	Juego.ruta_partida = RUTA_GUARDADO
	Juego.nueva_partida("Leo")
	Juego.banderas["pesca_habilitada"] = true
	var esc_ini := TareasDiarias.escala_progreso()
	_ok(is_equal_approx(esc_ini, 1.0), "escala inicial = 1.0 (%.2f)" % esc_ini)

	var combos := {}
	for _d in 6:
		var hoy := TareasDiarias.encargos_del_dia()
		_ok(hoy.size() == 3, "3 tareas diarias hoy (%d)" % hoy.size())
		_ok(str(hoy[0].get("tipo", "")) == "entregar", "la primera tarea siempre es entrega de objeto")
		var ids := hoy.map(func(x: Dictionary) -> String: return str(x.get("id", "")))
		combos["|".join(PackedStringArray(ids))] = true
		for x: Dictionary in hoy:
			var ests: Variant = x.get("estaciones", [])
			if ests is Array and not (ests as Array).is_empty():
				_ok((ests as Array).has(Juego.estacion), "cultivo del tablón coincide con la estación actual")
		Juego.terminar_dia(false)
	_ok(combos.size() >= 3, "rotación diaria real entre plantillas (%d distintas)" % combos.size())

	# 3. Escala según progreso del jugador (deuda + estación + herramientas).
	var dia_prueba := TareasDiarias.encargos_del_dia()
	var base_entrega := int(dia_prueba[0].get("cantidad", 1))
	var base_dinero := int(dia_prueba[0].get("dinero", 0))
	Juego.terminar_dia(false)
	Juego.estacion = 2
	Juego.pagar_deuda(2500)
	Juego.nivel_herramientas["pico"] = 2
	Juego.nivel_herramientas["azada"] = 2
	var esc_av := TareasDiarias.escala_progreso()
	_ok(esc_av > 1.5, "escala sube con progreso del jugador (%.2f)" % esc_av)
	var dia_av := TareasDiarias.encargos_del_dia()
	_ok(int(dia_av[0].get("dinero", 0)) >= 15, "tarea escalada conserva recompensa válida")
	Juego.nueva_partida("Leo")
	Juego.estacion = 2
	Juego.pagar_deuda(2500)
	Juego.nivel_herramientas["pico"] = 2
	Juego.nivel_herramientas["azada"] = 2
	# Comprobar escalado directo sobre plantilla fija.
	var p0 := TareasDiarias._escalar_encargo(todas[0], 1.0)
	var p1 := TareasDiarias._escalar_encargo(todas[0], esc_av)
	_ok(int(p1["cantidad"]) > int(p0["cantidad"]) and int(p1["dinero"]) > int(p0["dinero"]),
		"cantidad (%d -> %d) y dinero (%d -> %d) escalan con el progreso" % [base_entrega, int(p1["cantidad"]), base_dinero, int(p1["dinero"])])

	# 4. Progreso de acciones (regar en Cultivos + minar + talar + pescar + regalar) y cobro.
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	for _i in 60:
		if Interfaz.hud_visible():
			break
		await get_tree().process_frame
	Juego.energia = 100.0
	var regada := false
	for k: Variant in Cultivos.parcelas().keys():
		var pc := Cultivos.parcela(str(k))
		if str(pc.get("estado", "")) == "limpio" and Cultivos.aplicar("azada", [str(k)]):
			pc["regado"] = false
			if Cultivos.aplicar("regadera", [str(k)]):
				regada = true
				break
	_ok(regada, "Cultivos.aplicar(regadera) registra progreso de riego")
	var est_td := Juego.banderas.get("tareas_diarias", {}) as Dictionary
	var prog_td := est_td.get("progreso", {}) as Dictionary
	_ok(int(prog_td.get("regar", 0)) >= 1, "progreso diario regar >= 1 (%d)" % int(prog_td.get("regar", 0)))

	# Buscar un día en que aparezca tarea de acción no entrega para probar flujo de cobro y expiración.
	var tarea_accion: Dictionary = {}
	for _d in 8:
		for x: Dictionary in TareasDiarias.encargos_del_dia():
			if str(x.get("tipo", "entregar")) != "entregar":
				tarea_accion = x
				break
		if not tarea_accion.is_empty():
			break
		Juego.terminar_dia(false)
	_ok(not tarea_accion.is_empty(), "aparece tarea diaria de acción en rotación")
	if not tarea_accion.is_empty():
		var tid := str(tarea_accion["id"])
		var ttipo := str(tarea_accion["tipo"])
		var tmeta := int(tarea_accion["cantidad"])
		var tnpc := str(tarea_accion["npc"])
		_ok(TareasDiarias.entregar(tid) == "faltan", "sin completar progreso devuelve «faltan»")
		TareasDiarias.registrar_progreso(ttipo, tmeta)
		_ok(TareasDiarias.lista_para_cobrar(tarea_accion), "lista_para_cobrar == true al alcanzar meta")
		var d0 := Juego.dinero
		var a0 := Juego.puntos_amistad(tnpc)
		_ok(TareasDiarias.entregar(tid) == "ok", "entregar cobra la tarea de acción completada")
		_ok(Juego.dinero == d0 + int(tarea_accion["dinero"]), "dinero sumado correctamente")
		_ok(Juego.puntos_amistad(tnpc) == a0 + int(tarea_accion["amistad"]), "amistad sumada correctamente")
		_ok(TareasDiarias.encargo_hecho(tid) and TareasDiarias.entregar(tid) == "hecho", "no se cobra dos veces el mismo día")

		# 5. Persistencia al guardar y cargar.
		_ok(Juego.guardar(false), "Juego.guardar persiste tareas diarias")
		Juego.nueva_partida("Temp")
		_ok(Juego.cargar(), "Juego.cargar restaura estado")
		_ok(TareasDiarias.encargo_hecho(tid), "tarea cobrada persiste tras guardar y cargar")

		# 6. Caducidad al terminar el día.
		Juego.terminar_dia(false)
		var est_manana := Juego.banderas.get("tareas_diarias", {}) as Dictionary
		_ok((est_manana.get("progreso", {}) as Dictionary).is_empty() and (est_manana.get("hechos", []) as Array).is_empty(),
			"al avanzar de día caducan progreso y entregas del día anterior")

	# 7. Sección «Hoy» en el Diario muestra las 3 tareas diarias.
	Interfaz.abrir_diario("hoy")
	await get_tree().process_frame
	_ok(Interfaz.diario_abierto() and Interfaz._diario._panel_hoy.visible, "sección Hoy visible en el Diario")
	var scroll_hoy := Interfaz._diario._vbox_hoy.get_child(1) as ScrollContainer
	var cards := (scroll_hoy.get_child(0) as VBoxContainer).get_child_count()
	_ok(cards == 3, "sección Hoy muestra 3 tarjetas de tareas diarias (%d)" % cards)
	Interfaz.cerrar_todo()

	_limpiar()
	get_tree().current_scene = null
	if _fallos.is_empty():
		print("PRUEBA T23_TAREAS_DIARIAS OK (%d comprobaciones)" % _checks)
		get_tree().quit(0)
	else:
		print("PRUEBA T23_TAREAS_DIARIAS FALLO (%d fallos): %s" % [_fallos.size(), str(_fallos)])
		get_tree().quit(1)
