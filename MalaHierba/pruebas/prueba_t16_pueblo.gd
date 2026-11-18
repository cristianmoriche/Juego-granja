extends Node
## Prueba permanente T16-pueblo: rutinas por día de la semana/estación/lluvia, dos festividades
## (primavera y otoño) con pueblo decorado y diálogos propios, historias de vecinos en 4 escenas,
## diálogo con menciones a vecinos/deuda y evolución visual del pueblo según la deuda pagada.

var _errores: Array[String] = []
var _pasadas := 0
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			push_error("PRUEBA T16 FALLO: tiempo límite de 60 s agotado")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pasadas += 1
	else:
		_errores.append(msg)
		push_error("FALLO T16: " + msg)


func _cargar_mapa(id_m: String) -> Node:
	await Escenas.ir_a_mapa(id_m, "Spawn_Protagonista")
	var m := Escenas.mapa_actual_nodo()
	for _i in 180:
		if m != null and bool(m.get("vallas_listas")):
			break
		await get_tree().process_frame
	return m


func _sincronizar_en_pueblo(est: int, dia: int, min_dia: int, clima: String) -> Node:
	Juego.estacion = est
	Juego.dia = dia
	Juego.minutos = min_dia
	Juego.clima = clima
	Juego.aplicar_evento_hoy()
	var m := Escenas.mapa_actual_nodo()
	if m == null or str(m.get("id_mapa")) != "pueblo":
		m = await _cargar_mapa("pueblo")
	Juego.minutos = min_dia
	Juego.clima = clima
	var obj := m.get_node_or_null("Objetos/ObjetosPueblo") as ObjetosPueblo
	if obj != null and obj.vida_pueblo != null:
		obj.vida_pueblo.actualizar()
	var vec := m.get_node_or_null("Objetos/Vecinos") as Vecinos
	if vec != null:
		vec.sincronizar(true)
	await get_tree().process_frame
	return m


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null

	var ruta_previa := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_prueba_t16.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)

	# 1. Calendario, días de la semana y festividades fijas (14 de primavera y 18 de otoño).
	Juego.estacion = 0
	Juego.dia = 1
	_ok(Juego.dia_semana() == 0 and Juego.nombre_dia_semana() == "Lunes", "Día 1 de primavera es lunes")
	_ok(Juego.festividad_hoy() == "", "El día 1 no hay festividad")
	Juego.dia = 14
	Juego.clima = "lluvia"
	Juego.aplicar_evento_hoy()
	_ok(Juego.festividad_hoy() == "feria_siembra" and Juego.clima == "sol", "14 de primavera activa Feria de la Siembra con sol")
	Juego.estacion = 2
	Juego.dia = 18
	Juego.clima = "tormenta"
	Juego.aplicar_evento_hoy()
	_ok(Juego.festividad_hoy() == "fiesta_cosecha" and Juego.clima == "sol", "18 de otoño activa Fiesta de la Cosecha con sol")

	# 2. Cargar pueblo y comprobar rutinas por día de la semana, estación y lluvia.
	await _cargar_mapa("pueblo")

	# Miércoles (día 3): cuentacuentos en plaza a las 18:30 (1110) con Lucía todavía presente.
	await _sincronizar_en_pueblo(0, 3, 1110, "sol")
	var mp := Escenas.mapa_actual_nodo()
	var vec := mp.get_node("Objetos/Vecinos") as Vecinos
	_ok(vec.npcs.has("lucia") and vec.npcs.has("pablo") and vec.npcs.has("irene"), "Miércoles 18:30: Lucía, Pablo e Irene en el cuentacuentos de la plaza")

	# Domingo (día 7): Don Anselmo sale de casa por la mañana (10:00), Tomás está en el pueblo por la tarde (15:30) y Gema baja de visita.
	await _sincronizar_en_pueblo(0, 7, 600, "sol")
	_ok(vec.npcs.has("anselmo"), "Domingo 10:00: Don Anselmo pasea por la plaza en vez de encerrarse en el despacho")
	await _sincronizar_en_pueblo(0, 7, 930, "sol")
	_ok(vec.npcs.has("tomas") and vec.npcs.has("gema"), "Domingo 15:30: Tomás y Gema visitan el pueblo")

	# Viernes (día 5): velada animada en plaza/taberna a las 19:00 (1140).
	await _sincronizar_en_pueblo(0, 5, 1140, "sol")
	_ok(vec.npcs.has("mateo") and vec.npcs.has("clara") and vec.npcs.has("tomas"), "Viernes 19:00: Mateo, Clara y Tomás siguen juntos en el entorno de la taberna")

	# Invierno (estación 3, lunes día 1, 16:00 = 960): Marisol y Eusebio se refugian dentro de la taberna y Pablo/Irene se recogen pronto a las 18:10 (1090).
	Juego.estacion = 3
	Juego.dia = 1
	Juego.clima = "sol"
	Juego.aplicar_evento_hoy()
	var ub_marisol_inv := Vecinos.ubicacion_en_mapa(Vecinos.datos_de_todos().filter(func(d: Dictionary) -> bool: return str(d.get("id", "")) == "marisol")[0] as Dictionary, 960, "taberna")
	_ok(str(ub_marisol_inv.get("mapa", "")) == "taberna", "Invierno 16:00: Marisol entra a resguardarse del frío en la taberna")
	await _sincronizar_en_pueblo(3, 1, 1090, "sol")
	_ok(not vec.npcs.has("pablo") and not vec.npcs.has("irene"), "Invierno 18:10: Pablo e Irene ya se recogieron por anochecer antes")

	# Lluvia (primavera, lunes día 1, 11:30 = 690): Pablo pasa al porche de la tienda (Spawn_Tendera) y Marisol ya está bajo techo.
	await _sincronizar_en_pueblo(0, 1, 690, "lluvia")
	var pablo_lluvia := vec.npcs.get("pablo") as Npc
	_ok(pablo_lluvia != null and pablo_lluvia.sitio_actual.begins_with("Spawn_Tendera"), "Lluvia 11:30: Pablo se cobija bajo el porche de Spawn_Tendera (%s)" % (pablo_lluvia.sitio_actual if pablo_lluvia != null else "null"))

	# 3. Decoración y diálogos en ambas festividades.
	await _sincronizar_en_pueblo(0, 14, 750, "sol")
	var obj := mp.get_node("Objetos/ObjetosPueblo") as ObjetosPueblo
	var vp := obj.vida_pueblo
	var dec_prim := vp.get_node("DecoracionPlaza")
	_ok(vp.mesa_festiva != null and dec_prim.get_node_or_null("ArcoPlaza") != null, "14 de primavera: se crea la decoración de Feria de la Siembra en la plaza")
	_ok(vec.npcs.has("tomas") and vec.npcs.has("rufino") and vec.npcs.has("gema") and vec.npcs.has("anselmo"), "14 de primavera: hasta Tomás, Rufino y Gema bajan a la fiesta del pueblo")
	_ok(is_equal_approx((vec.npcs["anselmo"] as Npc).animo, 1.0), "En festividad los vecinos tienen ánimo al máximo")
	var f_fiesta_p := Conversacion.charlar(vec.npcs["anselmo"] as Npc)
	Interfaz.cerrar_todo()
	_ok(f_fiesta_p.contains("Siembra") or f_fiesta_p.contains("Feria") or f_fiesta_p.contains("guirnaldas") or f_fiesta_p.contains("plaza"), "Anselmo tiene diálogo propio de Feria de la Siembra: %s" % f_fiesta_p)

	await _sincronizar_en_pueblo(2, 18, 960, "sol")
	var dec_oto := vp.get_node("DecoracionPlaza")
	_ok(vp.mesa_festiva != null and dec_oto.get_node_or_null("PuestoFestivo") != null, "18 de otoño: se crea la decoración de Fiesta de la Cosecha")
	var f_fiesta_o := Conversacion.charlar(vec.npcs["mateo"] as Npc)
	Interfaz.cerrar_todo()
	_ok(f_fiesta_o.contains("Cosecha") or f_fiesta_o.contains("calabaza") or f_fiesta_o.contains("otoñ") or f_fiesta_o.contains("pozo"), "Mateo tiene diálogo propio de Fiesta de la Cosecha: %s" % f_fiesta_o)
	var f_relleno_o := Conversacion.frase_de_relleno(vec.npcs["marisol"] as Npc)
	_ok(not f_relleno_o.is_empty() and (f_relleno_o.contains("calabaza") or f_relleno_o.contains("mosto") or f_relleno_o.contains("casa")), "Vecinos de relleno también comentan la Fiesta de la Cosecha: %s" % f_relleno_o)

	# 4. Historias personales en 4 escenas por los 6 vecinos principales según amistad.
	Juego.estacion = 0
	Juego.dia = 2
	Juego.clima = "sol"
	Juego.aplicar_evento_hoy()
	await _sincronizar_en_pueblo(0, 2, 690, "sol")
	var umbrales: Array[int] = [20, 60, 110, 160]
	for id_npc: String in ["mateo", "clara", "ramon", "anselmo", "tomas", "pablo"]:
		Juego.amistad[id_npc] = 0
		_ok(Conversacion.escena_pendiente(id_npc).is_empty(), "%s con amistad 0 no salta aún su historia" % id_npc)
		var npc_ficticio := Npc.crear(Datos.npc(id_npc))
		for paso in umbrales.size():
			Juego.amistad[id_npc] = umbrales[paso]
			Juego.hablado_hoy.erase(id_npc)
			var esc := Conversacion.escena_pendiente(id_npc)
			_ok(int(esc.get("numero", 0)) == paso + 1, "%s desbloquea escena %d al llegar a %d de amistad" % [id_npc, paso + 1, umbrales[paso]])
			var dicho := Conversacion.charlar(npc_ficticio)
			Interfaz.cerrar_todo()
			_ok(not dicho.is_empty() and Conversacion.escenas_vistas(id_npc) == paso + 1, "%s reproduce y registra escena %d" % [id_npc, paso + 1])
			_ok(Conversacion.escena_pendiente(id_npc).is_empty(), "%s no repite la escena %d justo después" % [id_npc, paso + 1])
		npc_ficticio.queue_free()

	# 5. Abono de deuda (solo en su lugar de trabajo) y evolución visible del pueblo por tramos pagados.
	Juego.dinero = 6000
	var ans_npc := vec.npcs["anselmo"] as Npc
	_ok(not Conversacion.acciones_de(ans_npc).has("deuda"), "En la plaza (fuera del ayuntamiento) no sale abonar deuda")
	var m_alc := await _cargar_mapa("casa_alcalde")
	var vec_alc := m_alc.get_node("Objetos/Vecinos") as Vecinos
	var ans_alc := vec_alc.npcs["anselmo"] as Npc
	_ok(ans_alc.en_lugar_trabajo() and Conversacion.acciones_de(ans_alc).has("deuda"), "En el ayuntamiento (puesto de trabajo), Don Anselmo ofrece abonar la deuda")
	await _sincronizar_en_pueblo(0, 2, 690, "sol")
	mp = Escenas.mapa_actual_nodo()
	vec = mp.get_node("Objetos/Vecinos") as Vecinos
	ans_npc = vec.npcs["anselmo"] as Npc
	var obj_p2 := mp.get_node("Objetos/ObjetosPueblo") as ObjetosPueblo
	vp = obj_p2.vida_pueblo
	_ok(vp.get_node("DecoracionPlaza").get_node_or_null("Jardinera") == null and vp.puesto_panaderia == null, "Tramo 0 (deuda 5000): aún no hay jardineras ni panadería")

	var abono1 := Juego.pagar_deuda(1500)
	await get_tree().process_frame
	_ok(abono1 == 1500 and Juego.deuda == 3500 and Juego.tramo_deuda() == 1, "Abonar 1500 € pasa a tramo 1 (deuda restante %d)" % Juego.deuda)
	_ok(vp.get_node("DecoracionPlaza").get_node_or_null("Jardinera") != null and vp.puesto_panaderia == null, "Tramo 1: aparecen las jardineras con flores en la plaza")

	var abono2 := Juego.pagar_deuda(1500)
	await get_tree().process_frame
	_ok(abono2 == 1500 and Juego.deuda == 2000 and Juego.tramo_deuda() == 2, "Abonar 3000 € acumulados pasa a tramo 2")
	_ok(vp.puesto_panaderia != null and not Datos.tienda("panaderia").is_empty(), "Tramo 2: abre el puesto del Horno de Villaverde con tienda válida")

	var abono3 := Juego.pagar_deuda(2000)
	await get_tree().process_frame
	_ok(abono3 == 2000 and Juego.deuda == 0 and Juego.tramo_deuda() == 3, "Saldar los 5000 € pasa a tramo 3 (deuda 0)")
	_ok(vp.get_node("DecoracionPlaza").get_node_or_null("ArcoPlaza") != null and not Conversacion.acciones_de(ans_npc).has("deuda"), "Tramo 3: aparece el arco conmemorativo y ya no sale opción de deuda")
	_ok(is_equal_approx(ans_npc.animo, 1.0), "Con la deuda saldada, los vecinos de la plaza tienen ánimo máximo")

	# Guardado y carga preservan escenas personales y deuda saldada.
	Juego.guardar(false)
	Juego.nueva_partida("Otro")
	_ok(Juego.cargar() and Juego.deuda == 0 and Conversacion.escenas_vistas("clara") == 4, "Guardar y cargar conserva deuda saldada y las 4 escenas vistas")

	Juego.borrar_partida()
	Juego.ruta_partida = ruta_previa
	_terminado = true
	print("PRUEBA T16 PUEBLO: %d comprobaciones OK, %d fallos" % [_pasadas, _errores.size()])
	if _errores.is_empty():
		print("PRUEBA T16 PUEBLO OK")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
