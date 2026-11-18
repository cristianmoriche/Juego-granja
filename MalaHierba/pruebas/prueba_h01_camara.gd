extends Node
## H01: ejecutable con y sin ventana. Los ajustes y la partida de prueba usan rutas independientes.

const RUTA_AJUSTES := "user://ajustes_prueba_h01.cfg"
const RUTA_PARTIDA := "user://partida_prueba_h01.json"
const ESCENA_LEO := preload("res://escenas/jugador/jugador.tscn")

var _leo: Jugador
var _mundo: Node3D
var _aciertos := 0
var _errores := 0
var _usos := 0
var _otro_usos := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		push_error("H01: tiempo límite agotado")
		get_tree().quit(2))
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, texto: String) -> void:
	if condicion:
		_aciertos += 1
	else:
		_errores += 1
		push_error("H01: " + texto)


func _fisica(fotogramas: int = 3) -> void:
	await get_tree().create_timer(float(fotogramas) / Engine.physics_ticks_per_second, true, true).timeout
	await get_tree().process_frame


func _tecla(codigo: Key, pulsada: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = pulsada
	get_viewport().push_input(ev)


func _mando(boton: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = boton
	ev.pressed = true
	get_viewport().push_input(ev)


func _raton(relativa: Vector2, botones: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = relativa
	ev.screen_relative = relativa
	ev.button_mask = botones
	get_viewport().push_input(ev)


func _clic() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = get_viewport().get_visible_rect().get_center()
	ev.pressed = true
	get_viewport().push_input(ev)


func _caja(pos: Vector3, tamano: Vector3, capa: int = 1) -> StaticBody3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = capa
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = tamano
	forma.shape = caja
	cuerpo.add_child(forma)
	_mundo.add_child(cuerpo)
	cuerpo.position = pos
	return cuerpo


func _punto(nombre: String, pos: Vector3, al_usar: Callable) -> Interactuable:
	var nodo := Interactuable.new()
	nodo.verbo = "Abrir"
	nodo.nombre_objeto = nombre
	nodo.radio = 0.32
	nodo.altura_marca = 1.5
	nodo.usado.connect(al_usar)
	_mundo.add_child(nodo)
	nodo.position = pos
	return nodo


func _estado_cursor(capturado: bool, texto: String, mira_al_decorar: bool = false) -> void:
	_comprobar(Interfaz.cursor_de_juego == capturado and Interfaz._mira.visible == (capturado or mira_al_decorar), texto)
	if DisplayServer.get_name() != "headless":
		var modo := Input.MOUSE_MODE_CAPTURED if capturado else Input.MOUSE_MODE_VISIBLE
		_comprobar(Input.mouse_mode == modo, "modo real del ratón: " + texto)


func _ejecutar() -> void:
	Ajustes.ruta = RUTA_AJUSTES
	DirAccess.remove_absolute(RUTA_AJUSTES)
	Ajustes.cargar()
	Juego.ruta_partida = RUTA_PARTIDA
	Juego.nueva_partida("Prueba de cámara")
	Juego.pausar_tiempo(true)
	_mundo = Node3D.new()
	add_child(_mundo)
	_caja(Vector3(0.0, -0.1, 0.0), Vector3(24.0, 0.2, 24.0))
	_leo = ESCENA_LEO.instantiate() as Jugador
	_mundo.add_child(_leo)
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	_leo.activar()
	Interfaz.mostrar_hud(true)
	await _fisica(6)
	_comprobar(_leo.camara.primera_persona and _leo.camara.camara.fov == 80.0, "primera persona y 80° por defecto")
	var sombra := _leo.find_child("SombraCabeza", true, false) as MeshInstance3D
	var cuerpo := _leo.find_child("Leo_malla", true, false) as MeshInstance3D
	if sombra == null or cuerpo == null:
		push_error("H01: faltan las mallas de Leo")
		get_tree().quit(1)
		return
	_comprobar(_leo.camara.ancla_ojos is BoneAttachment3D, "ojos anclados al esqueleto")
	_comprobar(sombra.visible and sombra.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "cabeza proyecta sombra al ocultarse")
	_comprobar(cuerpo.mesh != _leo._vista_leo.original and cuerpo.visible, "solo la cabeza queda fuera de la cámara")
	_comprobar(_leo.camara.camara.global_position.y > 1.58 and _leo.camara.camara.global_position.y < 1.69, "altura de ojos en reposo")
	_estado_cursor(true, "captura inicial en primera")
	_comprobar(Interfaz._mira.global_position.distance_to(get_viewport().get_visible_rect().get_center()) < 1.0, "mira centrada")

	_tecla(KEY_V)
	await _fisica(6)
	_comprobar(not _leo.camara.primera_persona and _leo.camara._mezcla > 0.05 and _leo.camara._mezcla < 0.70, "transición gradual con V")
	await get_tree().create_timer(0.42, true, true).timeout
	_comprobar(is_equal_approx(_leo.camara._mezcla, 1.0) and _leo.camara.distancia_real > 2.5,
		"órbita alcanza la distancia de juego (mezcla %.3f, distancia %.3f)" % [_leo.camara._mezcla, _leo.camara.distancia_real])
	_comprobar(not sombra.visible and cuerpo.mesh == _leo._vista_leo.original, "la cabeza original reaparece en tercera")
	_estado_cursor(true, "captura en tercera")
	Ajustes.cargar()
	_comprobar(Ajustes.valores.vista == 1, "vista persiste en archivo")
	_mando(JOY_BUTTON_DPAD_UP)
	await get_tree().create_timer(0.42, true, true).timeout
	_comprobar(_leo.camara.primera_persona and sombra.visible, "cruceta cambia a primera")
	Ajustes.poner("fov", 200.0)
	_comprobar(_leo.camara.camara.fov == 100.0, "campo visual máximo")
	Ajustes.poner("fov", 10.0)
	_comprobar(_leo.camara.camara.fov == 70.0, "campo visual mínimo")
	Ajustes.poner("fov", 80.0)
	Ajustes.poner("distancia_tercera", 4.0)
	_comprobar(_leo.camara._dist_obj == 4.0, "distancia de tercera aplicada")
	_comprobar(Ajustes.ACCIONES.has("alternar_vista") and Ajustes.ACCIONES.has("interactuar"), "interacción y vista remapeables")
	_comprobar(Ajustes.remapear("alternar_vista", KEY_U), "cambiar tecla de vista")
	_tecla(KEY_U)
	await _fisica(20)
	_comprobar(not _leo.camara.primera_persona, "la tecla remapeada cambia de vista")
	Ajustes.restaurar_teclas()
	var yaw := _leo.camara.yaw
	var pitch := _leo.camara.pitch
	_raton(Vector2(20.0, 10.0))
	_comprobar(_leo.camara.yaw < yaw and _leo.camara.pitch > pitch, "ratón gira sin botón pulsado")
	pitch = _leo.camara.pitch
	Ajustes.poner("invertir_vertical", true)
	_raton(Vector2(0.0, 10.0))
	_comprobar(_leo.camara.pitch < pitch, "inversión vertical del ratón")
	pitch = _leo.camara.pitch
	_leo.camara.entrada_mando(Vector2(0.0, 0.9), 0.1)
	_comprobar(_leo.camara.pitch < pitch, "inversión vertical del mando")
	Ajustes.poner("invertir_vertical", false)
	yaw = _leo.camara.yaw
	var palanca := InputEventJoypadMotion.new()
	palanca.axis = JOY_AXIS_RIGHT_X
	palanca.axis_value = 0.85
	Input.parse_input_event(palanca)
	await _fisica(8)
	_comprobar(_leo.camara.yaw < yaw - 0.025, "el eje derecho asignado mueve la cámara durante el juego")
	palanca.axis_value = 0.0
	Input.parse_input_event(palanca)

	await _paneles()
	await _decoracion()
	await _interacciones()
	await _colision_camara()
	await _movimiento()
	Interfaz.cerrar_todo()
	Interfaz.mostrar_hud(false)
	_mundo.queue_free()
	await _fisica()
	_estado_cursor(false, "cursor visible al salir del juego")
	await _herramientas_y_accesos_reales()
	print("H01: %d aciertos, %d errores" % [_aciertos, _errores])
	get_tree().quit(0 if _errores == 0 else 1)


func _paneles() -> void:
	var paneles := [
		["pausa", func() -> void: Interfaz._pausa.abrir()],
		["ajustes", Interfaz.abrir_ajustes],
		["inventario", Interfaz.abrir_inventario],
		["diálogo", func() -> void: Interfaz.mostrar_dialogo("Clara", ["Buenos días."])],
		["pregunta", func() -> void: Interfaz.preguntar("¿Dormir?", ["Sí", "Volver"], func(_i: int) -> void: pass)],
		["tienda", func() -> void: Interfaz.abrir_tienda("tienda_mateo")],
		["mapa", Interfaz.alternar_mapa],
		["diario", func() -> void: Interfaz.abrir_diario()],
		["carpintería", Interfaz.abrir_carpinteria],
	]
	for entrada: Array in paneles:
		var abrir: Callable = entrada[1]
		abrir.call()
		await _fisica()
		_comprobar(Interfaz.ocupada(), "panel abierto: " + entrada[0])
		_estado_cursor(false, "cursor liberado en " + entrada[0])
		var yaw := _leo.camara.yaw
		_raton(Vector2(50.0, 20.0))
		_comprobar(is_equal_approx(yaw, _leo.camara.yaw), "la mirada espera mientras hay panel")
		Interfaz.cerrar_todo()
		await _fisica()
		_estado_cursor(true, "captura al cerrar " + entrada[0])
	Interfaz._pausa.abrir()
	Interfaz.abrir_ajustes()
	Interfaz._ajustes.cerrar()
	await _fisica()
	_estado_cursor(false, "cerrar Ajustes conserva el cursor en Pausa")
	Interfaz.cerrar_todo()
	await _fisica()


func _decoracion() -> void:
	var deco := DecoracionCasa.new()
	_mundo.add_child(deco)
	for vista: int in [0, 1]:
		Ajustes.poner("vista", vista)
		await _fisica(22)
		if vista == 0:
			_tecla(KEY_B)
		else:
			_mando(JOY_BUTTON_DPAD_DOWN)
		await _fisica()
		_comprobar(deco.esta_decorando(), "entrada a decoración en vista %d" % vista)
		_estado_cursor(false, "decoración libera el ratón y conserva la mira en vista %d" % vista, true)
		var yaw := _leo.camara.yaw
		_raton(Vector2(20.0, 5.0))
		_comprobar(is_equal_approx(yaw, _leo.camara.yaw), "el cursor libre puede moverse sin girar la cámara")
		_raton(Vector2(20.0, 5.0), MOUSE_BUTTON_MASK_RIGHT)
		_comprobar(not is_equal_approx(yaw, _leo.camara.yaw), "arrastrar con clic derecho orienta la mira")
		_estado_cursor(false, "el arrastre conserva el cursor libre", true)
		Interfaz.abrir_inventario()
		await _fisica()
		_estado_cursor(false, "en la mochila se oculta la mira de decoración")
		Interfaz.cerrar_todo()
		await _fisica()
		_estado_cursor(false, "al volver a decoración el cursor sigue libre", true)
		if vista == 0:
			_tecla(KEY_B)
		else:
			_mando(JOY_BUTTON_B)
		await _fisica()
		_comprobar(not deco.esta_decorando(), "salida de decoración en vista %d" % vista)
		_estado_cursor(true, "se captura el ratón al salir de decoración")
	deco.queue_free()
	await _fisica()


func _interacciones() -> void:
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	var principal := _punto("el baúl", Vector3(0.0, 0.65, -2.1), func(_j: Node3D) -> void: _usos += 1)
	var otro := _punto("el arcón de al lado", Vector3(1.3, 0.65, -2.0), func(_j: Node3D) -> void: _otro_usos += 1)
	await _fisica()
	for vista in [0, 1]:
		Ajustes.poner("vista", vista)
		await get_tree().create_timer(0.42, true, true).timeout
		var mira := principal.global_position + Vector3.UP * 0.75
		_leo.camara.mirar_hacia(mira)
		await _fisica()
		_comprobar(_leo.apuntado_actual().get("interactuable") == principal, "la mira elige el baúl en vista %d" % vista)
		_comprobar(_leo._resaltador.objetivo == principal and Interfaz.texto_accion().contains("Abrir el baúl"), "resaltado y cartel coinciden con la mira")
		_tecla(KEY_E)
		_clic()
		_mando(JOY_BUTTON_A)
		_comprobar(_usos == (vista + 1) * 3 and _otro_usos == 0, "E, clic y A usan solo el objetivo")
		_leo.camara.mirar_hacia(otro.global_position + Vector3.UP * 0.75)
		await _fisica()
		_comprobar(_leo.apuntado_actual().get("interactuable") == otro, "el cartel sigue la dirección de mira")
		_leo.camara.mirar_hacia(mira)
		var pared := _caja(Vector3(0.0, 1.3, -1.2), Vector3(1.1, 2.7, 0.12), 64)
		await _fisica()
		_comprobar(_leo.apuntado_actual().get("interactuable") == null, "no se interactúa a través de una pared")
		_tecla(KEY_E)
		_comprobar(_usos == (vista + 1) * 3, "E no acciona objetivos tapados")
		pared.queue_free()
		await _fisica()
	principal.queue_free()
	otro.queue_free()
	await _fisica()
	Ajustes.poner("vista", 0)
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	var puerta := _punto("la puerta cercana", Vector3(0.0, 0.75, -0.55), func(_j: Node3D) -> void: _usos += 1)
	var forma := puerta.get_child(0) as CollisionShape3D
	(forma.shape as SphereShape3D).radius = 1.35
	puerta.radio = 1.35
	await _fisica()
	_leo.camara.mirar_hacia(Vector3(0.0, 1.5, 1.2))
	await _fisica()
	_comprobar(_leo.apuntado_actual().get("interactuable") == null, "mirar de espaldas dentro del volumen de una puerta no la activa")
	_leo.camara.mirar_hacia(puerta.global_position + Vector3.UP * 0.75)
	await _fisica()
	_comprobar(_leo.apuntado_actual().get("interactuable") == puerta, "mirar a la puerta cercana sí la elige")
	puerta.queue_free()
	await _fisica()


func _colision_camara() -> void:
	Ajustes.poner("vista", 1)
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	var pared := _caja(Vector3(0.0, 2.4, 0.85), Vector3(8.0, 5.0, 0.1), 64)
	await _fisica(6)
	var cam := _leo.camara
	_comprobar(cam.camara.global_position.z < 0.79 and cam.distancia_real < 0.85, "la órbita se acorta ante paredes de cueva o mobiliario")
	pared.queue_free()
	await _fisica(28)
	_comprobar(cam.distancia_real > 3.5, "la cámara recupera la órbita al despejarse")
	var pegada := _caja(Vector3(0.0, 2.4, 0.39), Vector3(8.0, 5.0, 0.10), 64)
	await _fisica(8)
	var cam_pos := cam.camara.global_position
	var cuerpo := _leo._vista_leo.malla
	var sombra := _leo._vista_leo.sombra
	_comprobar(cam_pos.z < 0.33 and cam._fuera_del_cuerpo(cam_pos), "la cámara elude el cuerpo y la pared pegada a Leo")
	_comprobar(not cam.cabeza_oculta and not sombra.visible and cuerpo.mesh == _leo._vista_leo.original,
		"la tercera persona conserva la cabeza original con la órbita muy corta")
	var nuca := cam.ancla_ojos.global_position
	_comprobar(not cam.camara.is_position_behind(nuca) and get_viewport().get_visible_rect().has_point(cam.camara.unproject_position(nuca)),
		"la cámara de hombro encuadra la cabeza junto a una pared")
	_leo.global_position.z = 0.339
	cam._aplicar(0.0)
	_comprobar(cam.global_position.z < 0.31 and cam.camara.global_position.z < 0.33,
		"un empuje hasta el plano de la pared conserva el lado seguro del pivote")
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	pegada.queue_free()
	await _fisica(24)
	Ajustes.poner("vista", 0)
	Ajustes.poner("reducir_movimiento", true)
	_leo.colocar(Vector3.ZERO, NAN, 0.0)
	var frontal := _caja(Vector3(0.0, 1.4, -0.37), Vector3(8.0, 3.0, 0.10))
	cam.pitch = deg_to_rad(80.0)
	await _fisica(4)
	_comprobar(cam.camara.global_position.z > -0.30, "los ojos se retraen al mirar hacia abajo pegado al muro")
	_comprobar(cam._mezcla == 0.0 and not cam.hay_sacudida_activa(), "reducción de movimiento deja la vista estable")
	frontal.queue_free()
	await _fisica()


func _movimiento() -> void:
	var cam := _leo.camara
	cam.pitch = 0.0
	await _fisica(8)
	var altura := cam.camara.global_position.y
	Input.action_press("agachar")
	await _fisica(26)
	_comprobar(_leo.agachado and altura - cam.camara.global_position.y > 0.4, "la cámara baja al agacharse")
	Input.action_release("agachar")
	await get_tree().create_timer(0.55, true, true).timeout
	_comprobar(not _leo.agachado and absf(altura - cam.camara.global_position.y) < 0.05,
		"la altura se recupera al levantarse (%.3f → %.3f, agachado %s)" % [altura, cam.camara.global_position.y, _leo.agachado])
	_tecla(KEY_SPACE)
	await _fisica(16)
	_comprobar(_leo.saltos == 1 and cam.camara.global_position.y - altura > 0.6, "salto y cámara siguen unidos")
	await _fisica(40)


func _herramientas_y_accesos_reales() -> void:
	# La prueba sigue viva al sustituir su mundo de prueba por los mapas normales.
	get_tree().current_scene = null
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	var leo := Escenas.jugador() as Jugador
	var parcelas := get_tree().get_first_node_in_group("parcelas_apuntables") as Parcelas
	if leo == null or parcelas == null or not _equipar("hacha"):
		_comprobar(false, "la granja de prueba tiene parcelas y hacha")
		return
	for vista: int in [0, 1]:
		Ajustes.poner("vista", vista)
		await _fisica()
		var clave := await _tronco_apuntado(leo, parcelas)
		_comprobar(not clave.is_empty(), "la mira selecciona un tronco en vista %d" % vista)
		if not clave.is_empty():
			for golpe in Cultivos.golpes_necesarios(Cultivos.GOLPES_TRONCO, "hacha"):
				leo.camara.mirar_hacia(parcelas.posicion_de(clave) + Vector3.UP * 0.10)
				_usar_en_vista(vista)
				await get_tree().create_timer(0.64).timeout
			_comprobar(Cultivos.parcela(clave).get("estado") == "limpio", "tala completa con la mira en vista %d" % vista)

	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	leo = Escenas.jugador() as Jugador
	var rocas: RocasMina
	for nodo: Node in get_tree().get_nodes_in_group("usable"):
		if nodo is RocasMina:
			rocas = nodo
			break
	if leo == null or rocas == null or not _equipar("pico"):
		_comprobar(false, "la mina de prueba tiene rocas y pico")
		return
	for vista: int in [0, 1]:
		Ajustes.poner("vista", vista)
		await _fisica()
		var roca := await _roca_apuntada(leo, rocas)
		_comprobar(roca != null, "la mira selecciona roca real en vista %d" % vista)
		if roca != null:
			var dados := roca.golpes_dados
			_usar_en_vista(vista)
			_comprobar(roca.golpes_dados == dados + 1, "el pico golpea la roca de la mira en vista %d" % vista)
			await get_tree().create_timer(0.64).timeout
		await _probar_acceso(leo, "Escalera", vista)

	Juego.banderas["nivel_mina"] = 5
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	leo = Escenas.jugador() as Jugador
	if leo == null:
		_comprobar(false, "se carga el quinto nivel de la mina")
		return
	for vista: int in [0, 1]:
		Ajustes.poner("vista", vista)
		await _fisica()
		await _probar_acceso(leo, "InteractuableAscensor", vista)
	Interfaz.mostrar_hud(false)


func _equipar(id: String) -> bool:
	for i in 10:
		if Juego.inventario[i].get("id", "") == id:
			Juego.elegir_ranura(i)
			return true
	return false


func _usar_en_vista(vista: int) -> void:
	if vista == 0:
		_clic()
	else:
		_mando(JOY_BUTTON_X)


func _acercarse(leo: Jugador, centro: Vector3, lado: Vector3, altura: float = 0.0) -> bool:
	var cerca := centro + lado * 1.75
	var suelo := leo.camara.rayo_entre(cerca + Vector3.UP * 0.7, cerca + Vector3.DOWN * 0.65, 1 | 64)
	if suelo.is_empty() or (suelo.normal as Vector3).y < 0.68:
		return false
	var yaw := atan2(lado.x, lado.z)
	leo.colocar((suelo.position as Vector3) + Vector3.UP * 0.045, yaw + PI, yaw)
	await _fisica(2)
	leo.camara.mirar_hacia(centro + Vector3.UP * altura)
	return true


func _tronco_apuntado(leo: Jugador, parcelas: Parcelas) -> String:
	for clave: String in parcelas.claves():
		if Cultivos.parcela(clave).get("estado") != "tronco":
			continue
		for lado: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
			if await _acercarse(leo, parcelas.posicion_de(clave), lado, 0.10):
				if parcelas.celda_apuntada(leo.apuntar()).get("clave") == clave:
					return clave
	return ""


func _roca_apuntada(leo: Jugador, rocas: RocasMina) -> RocasMina.Roca:
	for roca: RocasMina.Roca in rocas.rocas_en_pie():
		for lado: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
			if await _acercarse(leo, roca.pos, lado, roca.radio * 0.52):
				if leo.apuntar().get("interactuable") == roca.punto:
					return roca
	return null


func _probar_acceso(leo: Jugador, nombre: String, vista: int) -> void:
	for punto: Node in get_tree().get_nodes_in_group("interactuable"):
		if punto.name != nombre or not punto is Interactuable:
			continue
		for lado: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
			if not await _acercarse(leo, punto.global_position, lado, punto.altura_marca * 0.46):
				continue
			if leo.apuntar().get("interactuable") != punto:
				continue
			if vista == 0:
				_tecla(KEY_E)
			else:
				_mando(JOY_BUTTON_A)
			_comprobar(Interfaz._pregunta.visible, "la mira abre %s en vista %d" % [nombre, vista])
			Interfaz.cerrar_todo()
			await _fisica()
			return
	_comprobar(false, "ningún acceso visible a %s desde la mira en vista %d" % [nombre, vista])
