extends Node
## Captura las dos vistas, la herrería y los tiempos de fotograma de H02.

var _salida: String
var _medidas := PackedStringArray()
var _errores := 0
var _impactos := PackedStringArray()


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	get_tree().create_timer(180.0).timeout.connect(func() -> void: get_tree().quit(2))
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/H02-combate/despues")
	DirAccess.make_dir_recursive_absolute(_salida)
	Ajustes.ruta = "user://ajustes_capturas_h02_r3_despues.cfg"
	Juego.ruta_partida = "user://partida_capturas_h02_r3_despues.json"
	Ajustes.poner("calidad", 2)
	Ajustes.poner("tutorial", true)
	Ajustes.poner("fov", 80)
	Ajustes.poner("distancia_tercera", 3.6)
	get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 840
	get_tree().current_scene = null
	if OS.get_environment("H02_SOLO_MATERIALES") == "1":
		await _materiales()
		get_tree().quit(0 if _errores == 0 else 1)
		return
	for id: String in ["granja", "pueblo", "mina_interior"]:
		var inicio := Time.get_ticks_msec()
		await Escenas.ir_a_mapa(id, "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista")
		var carga := Time.get_ticks_msec() - inicio
		var leo := Escenas.jugador() as Jugador
		if leo == null:
			_errores += 1
			continue
		if id == "mina_interior":
			await _mina(leo)
		else:
			await _foto(id)
		for primera: bool in [true, false]:
			Ajustes.poner("vista", 0 if primera else 1)
			await _medir(id + (" primera" if primera else " tercera"), carga)
		Ajustes.poner("vista", 0)
	await _mina_profunda()
	var f := FileAccess.open(_salida + "/r3_rendimiento.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_medidas) + "\n")
		f.close()
	else:
		_errores += 1
	await _paneles()
	await _combate()
	await _materiales()
	var evidencia := FileAccess.open(_salida.path_join("r3_verificacion_impactos.txt"), FileAccess.WRITE)
	if evidencia != null:
		evidencia.store_string("\n".join(_impactos) + "\n")
		evidencia.close()
	else:
		_errores += 1
	await Escenas._quitar_escena_actual()
	await get_tree().process_frame
	get_tree().quit(0 if _errores == 0 else 1)


func _paneles() -> void:
	await Escenas.ir_a_mapa("herreria", "Entrada")
	Interfaz._hud.limpiar_avisos()
	Servicios.menu_herreria("Clara")
	await _foto("herreria_mejoras")
	Interfaz.cerrar_todo()
	if not Datos.tienda("forja").is_empty():
		Interfaz.abrir_tienda("forja")
		await _foto("herreria_comprar")
		Juego.anadir_objeto("hierro", 18)
		Interfaz._tienda._b_forjar_tab.pressed.emit()
		Interfaz._tienda._elegir("espada_hierro")
		await _foto("herreria_forjar")
		Interfaz.cerrar_todo()
	_elegir("casco_cobre")
	Juego.equipar(Juego.ranura)
	_elegir("peto_hierro")
	Juego.equipar(Juego.ranura)
	_elegir("botas_cuarzo")
	Juego.equipar(Juego.ranura)
	_elegir("espada_hierro")
	Interfaz.abrir_inventario()
	await _foto("inventario_equipo")
	Interfaz.cerrar_todo()
	Interfaz._pausa.abrir()
	await _foto("pausa_controles")
	Interfaz.abrir_ajustes()
	for boton: Button in Interfaz._ajustes.find_children("*", "Button", true, false):
		if boton.text == "Controles":
			boton.pressed.emit()
			break
	var lista := Interfaz._ajustes.find_children("*", "ScrollContainer", true, false)
	var vinculo := Interfaz._ajustes._botones_tecla.get("fijar_objetivo") as Button
	await get_tree().process_frame
	await get_tree().process_frame
	if not lista.is_empty() and vinculo != null:
		(lista[0] as ScrollContainer).ensure_control_visible(vinculo)
	await _foto("ajustes_combate")
	Interfaz.cerrar_todo()


func _mina(leo: Jugador) -> void:
	leo.colocar(Vector3(405.5, 0.07, -0.35), NAN, -PI * 0.5)
	var rata := Enemigo.new()
	rata.configurar(Enemigo.normales_para_nivel(1)[0])
	leo.get_parent().add_child(rata)
	rata.global_position = leo.global_position + Vector3(1.7, 0, 0)
	rata.set_physics_process(false)
	for primera: bool in [true, false]:
		Ajustes.poner("vista", 0 if primera else 1)
		leo.camara.yaw = -PI * 0.5
		leo.camara.pitch = deg_to_rad(19.0 if primera else 12.0)
		await _foto("mina_" + ("primera" if primera else "tercera"))
	rata.queue_free()


func _mina_profunda() -> void:
	Juego.banderas["nivel_mina"] = 20
	var inicio := Time.get_ticks_msec()
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	var carga := Time.get_ticks_msec() - inicio
	for primera: bool in [true, false]:
		Ajustes.poner("vista", 0 if primera else 1)
		var nombre := "nivel_20_" + ("primera" if primera else "tercera")
		await _foto(nombre)
		await _medir(nombre, carga)
	Ajustes.poner("vista", 0)


func _combate() -> void:
	Juego.banderas["nivel_mina"] = 5
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	var leo := Escenas.jugador() as Jugador
	if leo == null:
		_errores += 1
		return
	await get_tree().process_frame
	var jefa: Enemigo
	for en: Enemigo in get_tree().get_nodes_in_group("enemigos"):
		en.set_physics_process(false)
		if en.es_jefe:
			jefa = en
	if jefa == null:
		_errores += 1
		return
	_jefa_a_suelo(jefa)
	_elegir("escudo_hierro")
	Juego.equipar(Juego.ranura)
	_elegir("espada_hierro")
	Interfaz._hud.limpiar_avisos()
	Ajustes.poner("distancia_tercera", 2.6)
	var eje := _posicion_combate(leo, jefa)
	leo.colocar(jefa.global_position + eje * 1.78 + Vector3.UP * 0.06, NAN, atan2(eje.x, eje.z))
	jefa.rotation.y = atan2(eje.x, eje.z)
	jefa.reproducir("reposo")
	Juego.recibir_dano(21.0)
	for primera: bool in [true, false]:
		Ajustes.poner("vista", 0 if primera else 1)
		leo.camara.mirar_hacia(jefa.centro_impacto())
		var sufijo := "primera" if primera else "tercera"
		await get_tree().create_timer(0.37).timeout
		if not is_instance_valid(leo.combate.objetivo_fijado):
			leo.combate.cambiar_objetivo()
		if primera:
			await _foto("tutorial_combate", 0.22)
			Tutorial.cerrar_actual()
			Ajustes.poner("tutorial", false)
		Input.action_press("bloquear")
		await _foto("defensa_" + sufijo, 0.36)
		Input.action_release("bloquear")
		await get_tree().create_timer(0.12).timeout
		await _pulsar_ataque()
		await _foto("golpe_ligero_" + sufijo, 0.21)
		await get_tree().create_timer(0.57).timeout
	Input.action_press("bloquear")
	await get_tree().create_timer(0.05).timeout
	leo.recibir_ataque(18.0, jefa, jefa.global_position)
	await _foto("parada", 0.13)
	Input.action_release("bloquear")
	await get_tree().create_timer(0.27).timeout
	leo.combate.esquivar(Vector2.ZERO)
	await _foto("esquiva", 0.15)
	await get_tree().create_timer(0.37).timeout
	Juego.recibir_dano(57.0)
	await _foto("herida", 0.16)
	Juego.curar_vida(100.0)
	await _armas_en_mano(leo, jefa, eje)
	await _mira_al_techo(leo, jefa, eje)
	jefa.recibir_dano(jefa.vida)
	await get_tree().create_timer(0.48).timeout
	var botines := get_tree().get_nodes_in_group("botin_enemigo")
	if not botines.is_empty():
		var botin := botines.back() as Interactuable
		Ajustes.poner("vista", 0)
		leo.colocar(botin.global_position + eje * 1.60 + Vector3.UP * .06, NAN, atan2(eje.x, eje.z))
		leo.camara.mirar_hacia(botin.global_position + Vector3.UP * .23)
		await _foto("botin")
	else:
		_errores += 1
	await _desmayo(leo, eje)
	Interfaz.cerrar_todo()


func _armas_en_mano(leo: Jugador, jefa: Enemigo, eje: Vector3) -> void:
	var punto := jefa.global_position + eje * 1.44 + Vector3.UP * 0.06
	var giro := atan2(eje.x, eje.z)
	if is_instance_valid(leo.combate.objetivo_fijado):
		leo.combate.cambiar_objetivo()
	leo.colocar(punto, NAN, giro)
	for id: String in ["daga_cobre", "maza_hierro", "martillo_guerra_cuarzo"]:
		_elegir(id)
		Interfaz._hud.limpiar_avisos()
		var datos := Datos.objeto(id)
		var nombre := str(datos["modelo"])
		var ciclo := float(datos["ciclo"])
		for primera: bool in [true, false]:
			Ajustes.poner("vista", 0 if primera else 1)
			leo.camara.mirar_hacia(jefa.centro_impacto())
			await get_tree().create_timer(0.33).timeout
			jefa.vida = jefa.vida_max
			jefa.vida_cambiada.emit(jefa.vida, jefa.vida_max)
			if primera:
				# Mirada a la altura del cuerpo para que se vea el arma completa en guardia.
				Ajustes.poner("fov", 100)
				leo.camara.mirar_hacia(jefa.global_position + Vector3.UP * 1.22)
				Input.action_press("bloquear")
				await _foto(nombre + "_en_mano_primera", 0.27)
				Input.action_release("bloquear")
				Ajustes.poner("fov", 80)
				await get_tree().create_timer(0.12).timeout
				leo.camara.mirar_hacia(jefa.centro_impacto())
			await _pulsar_ataque()
			await _foto(nombre + ("_ataque_primera" if primera else "_ataque_tercera"), ciclo * 0.42)
			await get_tree().create_timer(1.08).timeout


func _mira_al_techo(leo: Jugador, jefa: Enemigo, eje: Vector3) -> void:
	Ajustes.poner("vista", 0)
	_elegir("espada_hierro")
	leo.colocar(jefa.global_position + eje * 1.52 + Vector3.UP * 0.06, NAN, atan2(eje.x, eje.z))
	leo.camara.mirar_hacia(jefa.centro_impacto())
	await get_tree().create_timer(0.22).timeout
	leo.combate.cambiar_objetivo()
	var antes := jefa.vida
	await _foto("mira_al_enemigo_antes", 0.10)
	leo.camara.mirar_hacia(jefa.global_position + Vector3.UP * 9.0)
	await _pulsar_ataque()
	await _foto("mira_al_techo", 0.2)
	await get_tree().create_timer(0.48).timeout
	if jefa.vida != antes:
		push_error("Una criatura a ras de suelo recibió daño con la mira en el techo.")
		_errores += 1
	leo.camara.mirar_hacia(jefa.centro_impacto())
	await _pulsar_ataque()
	await _foto("mira_al_enemigo", 0.33)
	if jefa.vida >= antes:
		push_error("El golpe apuntado a la criatura no llegó a su cuerpo.")
		_errores += 1


func _desmayo(leo: Jugador, eje: Vector3) -> void:
	Ajustes.poner("vista", 1)
	leo.colocar(leo.global_position, NAN, atan2(eje.x, eje.z))
	leo.camara.girar(0.66)
	leo.camara.pitch = deg_to_rad(34.0)
	await get_tree().create_timer(0.35).timeout
	Juego.recibir_dano(Juego.vida)
	await _foto("desmayo_tercera", 0.60)
	for _i in 60:
		if not Escenas.en_transicion:
			break
		await get_tree().create_timer(0.12).timeout
	if Juego.mapa_actual != "casa_leo":
		_errores += 1
	await _foto("despertar_en_casa", 0.42)


func _materiales() -> void:
	Juego.banderas["nivel_mina"] = 1
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	Ajustes.poner("tutorial", false)
	Ajustes.poner("distancia_tercera", 2.6)
	Interfaz._hud.limpiar_avisos()
	var leo := Escenas.jugador() as Jugador
	if leo == null:
		_error("Falta Leo en la mina")
		return
	for nodo: Node in get_tree().get_nodes_in_group("enemigos"):
		nodo.set_physics_process(false)
	var muestras := {"escarabajo_roca": "roca", "arana_cristal": "cristal"}
	for dato: Dictionary in Enemigo.cargar_definiciones():
		var id := str(dato["id"])
		if not muestras.has(id):
			continue
		for primera: bool in [true, false]:
			await _carga_e_impacto(leo, dato, str(muestras[id]), primera)


func _carga_e_impacto(leo: Jugador, dato: Dictionary, material: String, primera: bool) -> void:
	var mina := leo.get_parent()
	var enemigo := Enemigo.new()
	enemigo.configurar(dato)
	mina.add_child(enemigo)
	enemigo.set_physics_process(false)
	enemigo.global_position = Vector3(407.15, 0.07, -0.35)
	enemigo.rotation.y = -PI * 0.5
	Ajustes.poner("vista", 0 if primera else 1)
	_elegir("espada_cobre")
	leo.colocar(Vector3(405.5, 0.07, -0.35), NAN, -PI * 0.5)
	await get_tree().process_frame
	leo.camara.mirar_hacia(enemigo.centro_impacto())
	await get_tree().create_timer(0.7).timeout
	var vista := "primera" if primera else "tercera"
	var sufijo := material + "_" + vista
	await _foto("antes_del_golpe_" + sufijo, 0.0)
	var antes := enemigo.vida
	var resistencia := Juego.resistencia

	# Se mantiene el clic tanto en la anticipación como al entrar en contacto.
	_clic(true)
	await get_tree().physics_frame
	var limite := Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < limite and not (leo.combate.cargado and leo.combate._ciclo > 0.0
			and leo.combate._t_golpe / leo.combate._ciclo >= 0.33):
		await get_tree().physics_frame
	if leo._anim_actual == "combate_cargado" and is_equal_approx(antes, enemigo.vida):
		await _foto("ataque_cargado_" + sufijo, 0.0)
	else:
		_error("No se observó la anticipación del cargado: " + sufijo)

	while Time.get_ticks_msec() < limite and is_equal_approx(antes, enemigo.vida):
		await get_tree().physics_frame
	var particulas := mina.get_node_or_null("Impacto_" + material) as CPUParticles3D
	var impacto := antes - enemigo.vida
	var pausa := leo.combate._pausa_impacto
	var perfil := float(Datos.objeto("espada_cobre")["dano"])
	if particulas != null and particulas.emitting and is_equal_approx(impacto, minf(antes, perfil * 1.85)) and pausa > 0.0:
		await _foto("impacto_" + sufijo, 0.105)
		var linea := "%s · %s · %s · %.1f de daño efectivo (%.1f × 1,85 antes de limitar por vida) · %d partículas · %.0f ms de pausa" % [
			vista, enemigo.nombre_visible, leo._anim_actual, impacto, perfil, particulas.amount, pausa * 1000.0]
		_impactos.append(linea)
		print(linea)
	else:
		_error("Sin contacto cargado con partículas de %s (daño %.2f, mapa %s)" % [sufijo, impacto, Juego.mapa_actual])
	_clic(false)
	if Juego.resistencia >= resistencia:
		_error("El cargado no gastó resistencia: " + sufijo)
	enemigo.queue_free()
	await get_tree().create_timer(1.0).timeout


func _error(mensaje: String) -> void:
	_errores += 1
	push_error(mensaje)


func _pulsar_ataque() -> void:
	_clic(true)
	await get_tree().create_timer(0.035).timeout
	_clic(false)


func _clic(pulsado: bool) -> void:
	var clic := InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = pulsado
	Input.parse_input_event(clic)


func _jefa_a_suelo(jefa: Enemigo) -> void:
	var r := jefa.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(jefa.global_position + Vector3.UP, jefa.global_position + Vector3.DOWN * 2.0, 1))
	if not r.is_empty():
		jefa.global_position = (r.position as Vector3) + Vector3.UP * .02


func _posicion_combate(leo: Jugador, jefa: Enemigo) -> Vector3:
	var mejor := Vector3.BACK
	var distancia := -1.0
	for i in 12:
		var eje := Vector3.BACK.rotated(Vector3.UP, TAU * i / 12.0)
		var salida := jefa.global_position + Vector3.UP * 1.35
		var muro := leo.camara.rayo_entre(salida, salida + eje * 5.3, 1 | 64 | 128)
		var libre := 5.3 if muro.is_empty() else salida.distance_to(muro.position)
		if libre > distancia:
			distancia = libre
			mejor = eje
	return mejor


func _elegir(id: String) -> void:
	if Juego.cantidad(id) == 0:
		Juego.anadir_objeto(id)
	for i in Juego.inventario.size():
		if str(Juego.inventario[i].get("id", "")) == id:
			if i >= 10:
				Juego.mover_huecos(i, 9)
				i = 9
			Juego.elegir_ranura(i)
			return


func _foto(nombre: String, espera: float = 0.65) -> void:
	await get_tree().create_timer(espera).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty() or img.save_png(_salida.path_join("r3_" + nombre + ".png")) != OK:
		_errores += 1
	else:
		print("Captura H02: ", nombre, " ", img.get_size())


func _medir(nombre: String, carga: int) -> void:
	const FOTOGRAMAS := 600
	await get_tree().create_timer(1.0).timeout
	var tiempos := PackedFloat64Array()
	var total := 0.0
	var previo := Time.get_ticks_usec()
	for _i in FOTOGRAMAS:
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		var ms := float(ahora - previo) / 1000.0
		tiempos.append(ms)
		total += ms
		previo = ahora
	tiempos.sort()
	var ms_peores := 0.0
	for i in range(FOTOGRAMAS - 6, FOTOGRAMAS):
		ms_peores += tiempos[i] / 6.0
	var linea := "%s: %.1f FPS medios, %.1f FPS (1 %% más lento), carga %d ms" % [
		nombre, FOTOGRAMAS * 1000.0 / total, 1000.0 / ms_peores, carga]
	_medidas.append(linea)
	print(linea)
