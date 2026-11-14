extends Node
## Prueba completa de T22-misiones (progreso, Diario, marcador HUD, recompensa y guardado).

const RUTA_GUARDADO := "user://prueba_t22_save.json"

var _checks: int = 0
var _fallos: Array[String] = []


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("TIEMPO AGOTADO EN PRUEBA T22")
		get_tree().quit(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fallos.append(msg)
		push_error("FALLO T22: " + msg)


func _limpiar_archivos() -> void:
	if FileAccess.file_exists(RUTA_GUARDADO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA_GUARDADO))


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	_limpiar_archivos()

	# 1. Definiciones JSON: >=12 misiones en las 4 estaciones, cultivos válidos de su estación.
	var todas := Misiones.todas()
	_ok(todas.size() >= 12, "al menos 12 misiones (%d)" % todas.size())
	var por_est := {0: 0, 1: 0, 2: 0, 3: 0}
	for m: Dictionary in todas:
		var est := int(m.get("estacion", -1))
		_ok(est >= 0 and est <= 3, "estación válida en %s" % str(m.get("id", "")))
		por_est[est] = int(por_est.get(est, 0)) + 1
		var quien := str(m.get("quien", ""))
		_ok(not Datos.npc(quien).is_empty(), "NPC válido «%s» en %s" % [quien, str(m.get("id", ""))])
		var pasos: Array = m.get("pasos", [])
		_ok(not pasos.is_empty(), "tiene pasos: %s" % str(m.get("id", "")))
		for p: Variant in pasos:
			var pd := p as Dictionary
			if pd.get("tipo", "") == "cultivar":
				var cid := str(pd.get("objetivo", ""))
				var cdef := Datos.cultivo(cid)
				_ok(not cdef.is_empty(), "cultivo existe: %s" % cid)
				if not cdef.is_empty():
					var ests: Array = cdef.get("estaciones", [])
					_ok(ests.has(est), "cultivo %s crece en estación %d" % [cid, est])
	for e in 4:
		_ok(int(por_est[e]) >= 3, "estación %d tiene al menos 3 misiones (%d)" % [e, int(por_est[e])])

	# 2. Nueva partida y marcador HUD inicial en granja.
	Juego.ruta_partida = RUTA_GUARDADO
	Juego.nueva_partida("Leo")
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	for _i in 60:
		if Interfaz.hud_visible():
			break
		await get_tree().process_frame

	var act := Misiones.mision_activa()
	_ok(str(act.get("id", "")) == "p1_papel_el_granado", "misión activa inicial es p1_papel_el_granado")
	_ok("El primer pagaré" in Interfaz._hud.texto_mision_activa(), "HUD muestra la misión activa")

	# 3. Paso «hablar» y «cultivar» (usando Cultivos + Misiones).
	var resp_hablar := Misiones.registrar_charla("anselmo")
	_ok(not resp_hablar.is_empty(), "hablar con Don Anselmo avanza el paso 0 de p1")
	_ok(str(Misiones.paso_actual("p1_papel_el_granado").get("tipo", "")) == "cultivar", "p1 pasa a paso cultivar")
	_ok("patata" in Interfaz._hud.texto_mision_activa(), "HUD actualiza el paso activo tras hablar")

	Juego.energia = 100.0
	Juego.anadir_objeto("semilla_patata", 5)
	var cosechado := false
	var plantadas := 0
	for k: Variant in Cultivos.parcelas().keys():
		if plantadas >= 3:
			break
		var ks := str(k)
		var pc := Cultivos.parcela(ks)
		if str(pc.get("estado", "")) == "limpio" and Cultivos.aplicar("azada", [ks]) and Cultivos.aplicar("semilla_patata", [ks]):
			plantadas += 1
			pc["listo"] = true
			if Cultivos.cosechar(ks):
				cosechado = true
	_ok(cosechado, "Cultivos.cosechar funciona y dispara el gancho de misiones")
	if Misiones.progreso_paso("p1_papel_el_granado").x < 3 and Misiones.paso_actual("p1_papel_el_granado").get("tipo", "") == "cultivar":
		Misiones.registrar_cosecha("patata", 3)
	_ok(str(Misiones.paso_actual("p1_papel_el_granado").get("tipo", "")) == "entregar", "p1 pasa a paso entregar patata")

	# 4. Paso «entregar» y recompensa completa + desbloqueo de p3.
	if Juego.cantidad("patata") < 2:
		Juego.anadir_objeto("patata", 2)
	var info_ent := Misiones.paso_entregar_para("mateo")
	_ok(not info_ent.is_empty(), "Mateo ofrece entrega de misión cuando Leo lleva patatas")
	var dinero_antes := Juego.dinero
	var amist_antes := Juego.puntos_amistad("anselmo")
	var patatas_antes := Juego.cantidad("patata")
	var ent := Misiones.entregar_a_npc("mateo")
	_ok(bool(ent.get("ok", false)) and bool(ent.get("completada", false)), "entrega a Mateo completa p1_papel_el_granado")
	_ok(Misiones.esta_completada("p1_papel_el_granado"), "p1 marcada completada")
	_ok(Juego.cantidad("patata") == patatas_antes - 2, "entrega consume 2 patatas")
	var rec_p1 := (Misiones.mision("p1_papel_el_granado").get("recompensa", {}) as Dictionary)
	var din_p1 := int(rec_p1.get("dinero", 0))
	_ok(Juego.dinero == dinero_antes + din_p1, "recompensa +%d € sumada (%d -> %d)" % [din_p1, dinero_antes, Juego.dinero])
	_ok(Juego.puntos_amistad("anselmo") == amist_antes + 20, "recompensa +20 amistad")
	_ok(Misiones.desbloqueada("p3_luz_en_la_mina"), "completar p1 desbloquea p3_luz_en_la_mina")

	# 5. Paso «mina_nivel» al entrar en mina_interior.
	await Escenas.ir_a_mapa("mina_interior", "Spawn_Protagonista")
	for _i in 30:
		await get_tree().process_frame
	_ok(int(Juego.banderas.get("mina_max_nivel", 0)) >= 1, "mina_max_nivel registrado al entrar")
	_ok(str(Misiones.paso_actual("p3_luz_en_la_mina").get("tipo", "")) == "entregar", "p3 avanza automáticamente de mina_nivel 1 a entregar cobre")

	# 6. Paso «pagar_deuda» en p2_semillas_rosa.
	Misiones.registrar_cosecha("zanahoria", 4)
	_ok(str(Misiones.paso_actual("p2_semillas_rosa").get("tipo", "")) == "pagar_deuda", "p2 avanza a pagar_deuda")
	Juego.ingresar(300)
	Juego.pagar_deuda(250)
	await get_tree().process_frame
	_ok(Misiones.esta_completada("p2_semillas_rosa"), "pagar 250 € de deuda completa paso pagar_deuda 200 y finaliza p2")

	# 7. UI Diario de misiones: abrir, pestañas, elegir activa, bloquear rueda.
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	Juego.elegir_ranura(2)
	Interfaz.abrir_diario()
	await get_tree().process_frame
	_ok(Interfaz.diario_abierto() and Interfaz.ocupada(), "abrir_diario abre modal y ocupa interfaz")
	Interfaz._diario._seleccionar_tab("completadas")
	_ok(Interfaz._diario._misiones_filtradas().size() >= 2, "pestaña completadas lista p1 y p2")
	Interfaz._diario._seleccionar_tab("hoy")
	_ok(Interfaz._diario._panel_hoy.visible, "pestaña Hoy (Tablón) visible en Diario")
	Interfaz._diario._seleccionar_tab("curso")
	_ok(Misiones.activar_mision("p4_mesa_en_el_candil"), "activar_mision fija p4_mesa_en_el_candil")
	_ok("El primer guiso del año" in Interfaz._hud.texto_mision_activa(), "HUD refleja nueva misión elegida en Diario")

	var ev_rueda := InputEventMouseButton.new()
	ev_rueda.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev_rueda.pressed = true
	Interfaz._unhandled_input(ev_rueda)
	_ok(Juego.ranura == 2, "rueda del ratón NO cambia ranura con el Diario abierto")
	Interfaz.abrir_diario()
	await get_tree().process_frame
	_ok(not Interfaz.diario_abierto() and not Interfaz.ocupada(), "cerrar Diario libera interfaz")

	# 8. Persistencia en guardar/cargar partida.
	_ok(Juego.guardar(false), "Juego.guardar guarda estado de misiones")
	Juego.nueva_partida("Reinicio")
	_ok(not Misiones.esta_completada("p1_papel_el_granado") and Misiones.id_activa() == "p1_papel_el_granado", "nueva_partida reinicia estado")
	_ok(Juego.cargar(), "Juego.cargar restaura partida")
	_ok(Misiones.esta_completada("p1_papel_el_granado") and Misiones.esta_completada("p2_semillas_rosa"), "misiones completadas persisten al cargar")
	_ok(Misiones.id_activa() == "p4_mesa_en_el_candil", "misión activa persiste al cargar")
	_ok("El primer guiso del año" in Interfaz._hud.texto_mision_activa(), "HUD muestra la misión restaurada")

	Juego.estacion = 1
	await get_tree().process_frame
	_ok(Misiones.desbloqueada("v1_tomates_sol"), "señal estacion_cambiada desbloquea misiones de verano")

	_limpiar_archivos()
	get_tree().current_scene = null
	if _fallos.is_empty():
		print("PRUEBA T22_MISIONES OK (%d comprobaciones)" % _checks)
		get_tree().quit(0)
	else:
		print("PRUEBA T22_MISIONES FALLO (%d fallos): %s" % [_fallos.size(), str(_fallos)])
		get_tree().quit(1)
