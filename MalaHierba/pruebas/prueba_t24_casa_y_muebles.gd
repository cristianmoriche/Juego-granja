extends Node
## Prueba automática de T24-casa-y-muebles (tope interno 60 s).

var _ok: int = 0
var _fallos: int = 0


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		printerr("PRUEBA T24 TIMEOUT (> 60 s)")
		get_tree().quit(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _chk(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		printerr("FALLO T24: " + msg)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null

	Juego.ruta_partida = "user://prueba_t24.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 600

	# 1. Entrar desde granja por la puerta de la cabaña hasta casa_leo.
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	var puerta: PuertaMapa = null
	for nodo in get_tree().get_nodes_in_group("puerta"):
		if nodo is PuertaMapa and (nodo as PuertaMapa).destino == "casa_leo":
			puerta = nodo as PuertaMapa
			break
	_chk(puerta != null, "Existe puerta hacia casa_leo en granja")
	if puerta != null:
		puerta.interactuar(Escenas.jugador())
		for _i in 300:
			var act := Escenas.mapa_actual_nodo()
			if act != null and str(act.get("id_mapa")) == "casa_leo" and not Escenas.en_transicion:
				break
			await get_tree().create_timer(0.05).timeout

	var mapa := Escenas.mapa_actual_nodo()
	_chk(mapa != null and str(mapa.get("id_mapa")) == "casa_leo", "Transición a casa_leo correcta")
	for marc in ["Obj_cama", "Obj_cocina", "Obj_carpinteria", "Obj_arcon", "Obj_calendario", "Obj_carta_abuela"]:
		_chk(mapa.call("marcador", marc) != null, "Marcador %s presente en casa_leo" % marc)

	var deco := mapa.get_node_or_null("Objetos/DecoracionCasa") as DecoracionCasa
	_chk(deco != null, "DecoracionCasa montado en CasaLeo/Objetos")
	if deco == null:
		printerr("PRUEBA T24 ABORTADA: DecoracionCasa null")
		get_tree().quit(1)
		return

	# 2. Banco de carpintería y 20 muebles con modelo + icono + receta + tienda.
	var muebles := Datos.muebles()
	_chk(muebles.size() >= 20, "Catálogo de muebles tiene >= 20 modelos (%d)" % muebles.size())
	var tienda := Datos.tienda("tienda_mateo")
	var vende: Array = tienda.get("vende", [])
	for m: Dictionary in muebles:
		var id := str(m.get("id", ""))
		var ruta_mod := str(m.get("modelo", ""))
		_chk(Datos.es_mueble(id), "%s reconocido por Datos.es_mueble" % id)
		_chk(ResourceLoader.exists(ruta_mod), "Modelo %s existe (%s)" % [id, ruta_mod])
		_chk(Datos.icono(id) != null, "Icono PNG existe para %s" % id)
		_chk(id in vende, "Mueble %s se vende en tienda_mateo" % id)

	# Banco de carpintería abre PanelCarpinteria; cama y cocina existen.
	var inter := mapa.get_node_or_null("Objetos/InteraccionesInterior")
	_chk(inter != null, "InteraccionesInterior presente")
	if inter != null:
		inter.call("ejecutar_accion", "carpinteria", {})
		await get_tree().process_frame
		_chk(Interfaz.carpinteria_abierta(), "Acción carpintería abre PanelCarpinteria")
		Interfaz.cerrar_todo()
		_chk(inter.call("nodo_interaccion", "cocina") != null, "Cocina interactuable presente")
	_chk(mapa.find_child("PuntoDormir", true, false) != null, "PuntoDormir (cama) presente")

	# 3. Fabricación de muebles con materiales.
	Juego.quitar_objeto("madera", Juego.cantidad("madera"))
	_chk(PanelCarpinteria.fabricar("mesa_roble") == "sin_material", "Fabricar sin madera devuelve sin_material")
	Juego.anadir_objeto("madera", 10)
	_chk(PanelCarpinteria.fabricar("mesa_roble") == "ok", "Fabricar mesa_roble con madera suficiente")
	_chk(Juego.cantidad("mesa_roble") == 1 and Juego.cantidad("madera") == 2, "Mueble fabricado y materiales descontados")

	# 4. Validación de rejilla: bloqueos fijos, paredes, alfombra y capas.
	_chk(not bool(deco.puede_colocar("silla_roble", 0, 1, 0).get("ok", true)), "No cabe sobre la cama (0,1)")
	_chk(not bool(deco.puede_colocar("silla_roble", 11, 0, 0).get("ok", true)), "No cabe en la cocina (11,0)")
	_chk(not bool(deco.puede_colocar("silla_roble", 6, 10, 0).get("ok", true)), "No bloquea la puerta (6,10)")
	_chk(not bool(deco.puede_colocar("silla_roble", -1, 0, 0).get("ok", true)), "Fuera de límites (-1,0)")
	_chk(not bool(deco.puede_colocar("cuadro_valle", 5, 5, 0).get("ok", true)), "Cuadro no cabe en medio de la sala")
	_chk(not bool(deco.puede_colocar("cuadro_valle", 6, 0, 1).get("ok", true)), "Cuadro en pared norte requiere rotación 0")
	_chk(bool(deco.puede_colocar("cuadro_valle", 6, 0, 0).get("ok", false)), "Cuadro cabe en pared norte rot=0")
	_chk(bool(deco.puede_colocar("cuadro_girasoles", 0, 4, 1).get("ok", false)), "Cuadro cabe en pared oeste rot=1")

	Juego.anadir_objeto("alfombra_roja", 2)
	Juego.anadir_objeto("cuadro_valle", 1)
	Juego.anadir_objeto("baul_roble", 1)
	Juego.anadir_objeto("chimenea_piedra", 1)
	_chk(deco.colocar_mueble_en_celda("alfombra_roja", Vector2i(5, 4), 0, false), "Coloca alfombra_roja en (5,4)")
	_chk(not deco.colocar_mueble_en_celda("alfombra_roja", Vector2i(5, 4), 0, false), "No apila dos alfombras iguales en (5,4)")
	_chk(deco.colocar_mueble_en_celda("mesa_roble", Vector2i(5, 4), 0, false), "Mesa_roble cabe encima de alfombra_roja")
	_chk(not bool(deco.puede_colocar("silla_roble", 5, 4, 0).get("ok", true)), "Silla no cabe sobre celda ocupada por mesa_roble")
	_chk(deco.colocar_mueble_en_celda("cuadro_valle", Vector2i(6, 0), 0, false), "Cuadro colocado en pared norte")
	_chk(deco.colocar_mueble_en_celda("baul_roble", Vector2i(4, 1), 0, false), "Baúl colocado en (4,1)")
	_chk(deco.colocar_mueble_en_celda("chimenea_piedra", Vector2i(13, 8), 3, false), "Chimenea colocada en pared este")

	var hay_baul := false
	for n: Node in get_tree().get_nodes_in_group("interactuable"):
		if n.has_method("texto_interaccion") and str(n.call("texto_interaccion")) == "Abrir baúl":
			hay_baul = true
			break
	_chk(hay_baul, "baul_roble colocado expone interacción 'Abrir baúl'")

	# 5. Rotación y rueda en modo decorar vs rueda T20 fuera de modo decorar.
	Juego.elegir_ranura(0)
	var ran_antes := Juego.ranura
	deco.entrar_modo_decorar("silla_roble")
	_chk(deco.esta_decorando() and deco.consume_rueda(), "Modo decorar activo y consume rueda")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	deco._unhandled_input(wheel_down)
	_chk(deco._rot_actual == 1, "Rueda gira mueble en modo decorar (rot == 1)")
	_chk(Juego.ranura == ran_antes, "Rueda no cambia ranura de barra mientras decora")
	deco.girar_mueble(1)
	_chk(deco._rot_actual == 2, "girar_mueble suma rotación (rot == 2)")
	deco.salir_modo_decorar()
	_chk(not deco.esta_decorando() and not deco.consume_rueda(), "Sale de modo decorar correctamente")

	# 6. Recoger muebles a la mochila.
	var rec1 := deco.recoger_mueble_en_celda(Vector2i(5, 4))
	_chk(rec1 == "mesa_roble", "Recoger en (5,4) devuelve primero mesa_roble (%s)" % rec1)
	_chk(Juego.cantidad("mesa_roble") == 1, "mesa_roble vuelve al inventario")
	var rec2 := deco.recoger_mueble_en_celda(Vector2i(5, 4))
	_chk(rec2 == "alfombra_roja", "Segundo recoger en (5,4) devuelve alfombra_roja (%s)" % rec2)
	Juego.anadir_objeto("silla_roble", 1)
	var leo := Escenas.jugador() as Jugador
	var centro := DecoracionCasa.centro_mundo(5, 4, "silla_roble", 0, 0.015)
	for vista in [0, 1]:
		Ajustes.valores["vista"] = vista
		Ajustes.cambiado.emit("vista")
		leo.colocar(centro + Vector3(0.0, 0.04, 1.5), NAN, 0.0)
		await get_tree().create_timer(0.40).timeout
		deco.entrar_modo_decorar("silla_roble")
		leo.camara.mirar_hacia(centro)
		await get_tree().create_timer(0.15).timeout
		_chk(deco._cursor_valido and deco._cursor_celda == Vector2i(5, 4), "la mira de vista %d marca la casilla (5,4)" % vista)
		Interfaz.abrir_carpinteria()
		await get_tree().process_frame
		await get_tree().process_frame
		_chk(not Interfaz.cursor_de_juego, "la carpintería libera el ratón al decorar")
		Interfaz.cerrar_todo()
		await get_tree().process_frame
		await get_tree().process_frame
		_chk(not Interfaz.cursor_de_juego and Interfaz.apuntando_decoracion and deco.esta_decorando(),
			"se retoma la mira con el cursor libre al cerrar la carpintería")
		var accion: InputEvent
		if vista == 0:
			var clic := InputEventMouseButton.new()
			clic.button_index = MOUSE_BUTTON_LEFT
			clic.position = get_viewport().get_visible_rect().get_center()
			clic.pressed = true
			accion = clic
		else:
			var boton := InputEventJoypadButton.new()
			boton.button_index = JOY_BUTTON_A
			boton.pressed = true
			accion = boton
		get_viewport().push_input(accion)
		_chk(deco.recoger_mueble_en_celda(Vector2i(5, 4)) == "silla_roble", "la vista %d confirma la colocación en la casilla apuntada" % vista)
		deco.salir_modo_decorar()

	# 7. Persistencia en guardado + carga de partida.
	_chk(Juego.guardar(), "Guardar partida con muebles colocados")
	_chk(Juego.cargar(), "Cargar partida")
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	await Escenas.ir_a_mapa("casa_leo", "Entrada")
	var deco2 := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/DecoracionCasa") as DecoracionCasa
	_chk(deco2 != null and deco2.muebles_colocados().size() == 3, "Persisten los 3 muebles tras guardar/recargar (%d)" % (deco2.muebles_colocados().size() if deco2 != null else -1))

	await get_tree().process_frame
	if _fallos == 0:
		print("PRUEBA T24_CASA_Y_MUEBLES OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		printerr("PRUEBA T24_CASA_Y_MUEBLES FALLO (%d errores, %d ok)" % [_fallos, _ok])
		get_tree().quit(1)
