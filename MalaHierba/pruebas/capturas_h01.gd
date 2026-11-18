extends Node
## Fotografías comparables de H01 y medición de tiempos de fotograma en Vulkan.

var _salida: String
var _antes: bool
var _referencia: Camera3D
var _medidas := PackedStringArray()
var _errores := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(180.0).timeout.connect(func() -> void: get_tree().quit(2))
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	_antes = OS.get_environment("MH_H01_FASE") == "antes"
	var fase := "antes" if _antes else "despues"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/H01-primera-persona/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)
	Ajustes.ruta = "user://ajustes_capturas_h01.cfg"
	Ajustes.poner("calidad", 2)
	Juego.ruta_partida = "user://partida_capturas_h01.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().current_scene = null
	if OS.get_environment("MH_H01_MUESTRA") == "pared":
		await Escenas.ir_a_mapa("casa_leo", "Spawn_Protagonista")
		await _hombro_junto_a_pared(Escenas.jugador() as Jugador)
		get_tree().quit(0 if _errores == 0 else 1)
		return
	for id in ["granja", "pueblo", "casa_leo", "mina_interior"]:
		Juego.minutos = 840
		var inicio := Time.get_ticks_msec()
		await Escenas.ir_a_mapa(id, "Spawn_Protagonista")
		var carga := Time.get_ticks_msec() - inicio
		var leo := Escenas.jugador() as Jugador
		if leo == null:
			_errores += 1
			continue
		var yaw := leo.camara.yaw
		await _vista(leo, false, yaw)
		await _foto(id + "_tercera")
		if id != "casa_leo":
			await _medir(id + " tercera", carga)
		await _vista(leo, true, yaw)
		await _foto(id + "_primera" + ("_referencia" if _antes else ""))
		if id != "casa_leo":
			await _medir(id + " primera", carga)
		if id == "granja" and not _antes:
			leo.camara.pitch = deg_to_rad(83.0)
			await _foto("granja_cuerpo")
			await _herramienta(leo)
		if id == "pueblo":
			await _conversacion(leo)
		if id == "casa_leo":
			await _decoracion(leo)
			if not _antes:
				await _hombro_junto_a_pared(leo)
		if id == "mina_interior" and not _antes:
			leo.colocar(Vector3(405.5, 0.07, -0.35), NAN, -PI * 0.5)
			await _vista(leo, true, -PI * 0.5)
			await _foto("mina_galeria_primera")
			await _vista(leo, false, -PI * 0.5)
			await _foto("mina_galeria_tercera")
	await _mina_profunda()
	await _paneles()
	var informe := FileAccess.open(_salida + "/rendimiento.txt", FileAccess.WRITE)
	if informe != null:
		informe.store_string("\n".join(_medidas) + "\n")
		informe.close()
	get_tree().quit(0 if _errores == 0 else 1)


func _vista(leo: Jugador, primera: bool, yaw: float) -> void:
	if _antes:
		leo.camara.camara.make_current()
		leo.camara.yaw = yaw
		if primera:
			if _referencia == null:
				_referencia = Camera3D.new()
				_referencia.fov = 80.0
				_referencia.near = 0.045
				add_child(_referencia)
			var frente := Vector3.FORWARD.rotated(Vector3.UP, yaw)
			_referencia.global_position = leo.global_position + Vector3.UP * 1.62 + frente * 0.24
			_referencia.rotation = Vector3(-0.12, yaw, 0.0)
			_referencia.make_current()
	else:
		Ajustes.poner("vista", 0 if primera else 1)
		leo.camara.yaw = yaw
		leo.camara.pitch = deg_to_rad(10.0 if primera else 20.0)
	await get_tree().create_timer(0.65).timeout


func _conversacion(leo: Jugador) -> void:
	var vecino: Npc
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Npc and (vecino == null or n.get("id") == "clara"):
			vecino = n as Npc
	if vecino == null:
		_errores += 1
		return
	var rumbo := (leo.global_position - vecino.global_position).slide(Vector3.UP).normalized()
	if rumbo.is_zero_approx():
		rumbo = Vector3.BACK
	var giro := atan2(rumbo.x, rumbo.z)
	for primera: bool in [false, true]:
		leo.colocar(vecino.global_position + rumbo * 1.95, giro + PI, giro)
		await _vista(leo, primera, giro)
		if not _antes and not await _iniciar_desde_mira(leo, vecino, rumbo):
			_errores += 1
			push_error("No se pudo encuadrar la conversación desde un sitio despejado.")
			continue
		if _antes:
			Conversacion.hablar(vecino, leo)
		if Interfaz._pregunta.visible:
			Interfaz._pregunta._elegir(Conversacion.acciones_de(vecino).find("hablar"))
		var vista := "primera" + ("_referencia" if _antes else "") if primera else "tercera"
		await _foto("conversacion_" + vista, 0.9)
		Interfaz.cerrar_todo()


func _iniciar_desde_mira(leo: Jugador, vecino: Npc, rumbo: Vector3) -> bool:
	var espacio := leo.get_world_3d().direct_space_state
	for grados: float in [0.0, -45.0, 45.0, -90.0, 90.0, -135.0, 135.0, 180.0]:
		var lado := rumbo.rotated(Vector3.UP, deg_to_rad(grados))
		var cerca := vecino.global_position + lado * 2.05
		var q := PhysicsRayQueryParameters3D.create(cerca + Vector3.UP * 0.55, cerca + Vector3.DOWN * 0.65, 1 | 64)
		var suelo := espacio.intersect_ray(q)
		if suelo.is_empty() or (suelo.normal as Vector3).y < 0.72:
			continue
		var giro := atan2(lado.x, lado.z)
		leo.colocar((suelo.position as Vector3) + Vector3.UP * 0.04, giro + PI, giro)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var cara: Vector3 = vecino.call("punto_ojos")
		leo.camara.call("mirar_hacia", cara)
		var interior: Dictionary = leo.camara.call("rayo_entre", leo.camara.camara.global_position, cara, 1 | 64 | 128)
		if not interior.is_empty():
			continue
		var blanco: Dictionary = leo.call("apuntar")
		var objetivo := blanco.get("interactuable") as Node3D
		if objetivo == null or objetivo.get_parent() != vecino:
			continue
		leo._interactuar()
		return Interfaz.ocupada()
	return false


func _herramienta(leo: Jugador) -> void:
	var parcelas := get_tree().get_first_node_in_group("parcelas_apuntables") as Parcelas
	if parcelas == null:
		return
	for clave: String in parcelas.claves():
		if Cultivos.parcela(clave).get("estado") != "limpio":
			continue
		var p := parcelas.posicion_de(clave)
		leo.colocar(p + Vector3(0.0, 0.02, 1.55), NAN, 0.0)
		leo.camara.call("mirar_hacia", p + Vector3.UP * 0.035)
		await get_tree().create_timer(0.18).timeout
		if not leo.call("apuntado_actual").has("punto"):
			continue
		var resultado: Vector3 = leo.call("apuntado_actual").punto
		if parcelas.celda_en(resultado).get("clave") != clave:
			continue
		await _foto("granja_mira_en_casilla")
		leo._usar()
		await _foto("granja_azada_en_uso", 0.14)
		return
	_errores += 1
	push_error("No se encontró una parcela con la mira para fotografiar la azada.")


func _mina_profunda() -> void:
	Juego.banderas["nivel_mina"] = 5
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	var leo := Escenas.jugador() as Jugador
	if leo == null:
		_errores += 1
		return
	var yaw := leo.camara.yaw
	await _vista(leo, true, yaw)
	if _antes:
		_referencia.rotation.x = deg_to_rad(26.0)
	else:
		leo.camara.pitch = deg_to_rad(-26.0)
	await _foto("mina_nivel_5_techo_primera" + ("_referencia" if _antes else ""))
	await _vista(leo, false, yaw)
	leo.camara.pitch = deg_to_rad(38.0)
	await _foto("mina_nivel_5_techo_tercera")


func _decoracion(leo: Jugador) -> void:
	var deco := get_tree().get_first_node_in_group("decoracion_casa") as DecoracionCasa
	if deco == null:
		_errores += 1
		return
	var celda := Vector2i(6, 5)
	Juego.anadir_objeto("silla_roble", 1)
	for primera: bool in [false, true]:
		var punto := DecoracionCasa.centro_mundo(celda.x, celda.y, "silla_roble", 0)
		leo.colocar(punto + Vector3(0.0, 0.06, 1.55), NAN, 0.0)
		await _vista(leo, primera, 0.0)
		deco.entrar_modo_decorar("silla_roble")
		if _antes:
			deco.fijar_cursor_celda(celda)
		else:
			leo.camara.call("mirar_hacia", punto + Vector3.UP * 0.03)
			await get_tree().physics_frame
			await get_tree().process_frame
			if not Interfaz.get("apuntando_decoracion") or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				_errores += 1
				push_error("La captura de decoración requiere la mira y el cursor libre.")
		var vista := "primera" + ("_referencia" if _antes else "") if primera else "tercera"
		await _foto("decoracion_" + vista)
		deco.salir_modo_decorar()


func _hombro_junto_a_pared(leo: Jugador) -> void:
	# Busca una pared del interior real, por encima de los muebles bajos.
	var espacio := leo.get_world_3d().direct_space_state
	for caso: Array in [
		[Vector3(0.0, 1.50, 1.7), Vector3.RIGHT],
		[Vector3(0.0, 1.50, -1.7), Vector3.RIGHT],
		[Vector3(0.0, 1.50, 1.7), Vector3.LEFT],
		[Vector3(1.7, 1.50, 0.0), Vector3.BACK],
	]:
		var origen: Vector3 = caso[0]
		var dir: Vector3 = caso[1]
		var q := PhysicsRayQueryParameters3D.create(origen, origen + dir * 6.0, 1 | 64)
		var pared := espacio.intersect_ray(q)
		if pared.is_empty():
			continue
		var normal: Vector3 = pared.normal
		if absf(normal.y) > 0.12 or normal.dot(dir) > -0.8:
			continue
		var p: Vector3 = pared.position + normal * 0.36
		var suelo := espacio.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 2.0, 1 | 64))
		if suelo.is_empty() or (suelo.position as Vector3).y > 0.3:
			continue
		var yaw := atan2(-normal.x, -normal.z)
		leo.colocar((suelo.position as Vector3) + Vector3.UP * 0.04, NAN, yaw)
		await _vista(leo, false, yaw)
		leo.camara.pitch = deg_to_rad(8.0)
		await get_tree().create_timer(0.10).timeout
		var cam := leo.camara.camara
		var nuca: Vector3 = leo.camara.get("ancla_ojos").global_position
		if (cam.global_position - (pared.position as Vector3)).dot(normal) < 0.04:
			print("La colisión dejó la cámara fuera del interior en ", leo.global_position)
			continue
		if cam.is_position_behind(nuca) or not get_viewport().get_visible_rect().has_point(cam.unproject_position(nuca)):
			continue
		if leo.camara.distancia_real >= 1.6:
			continue
		await _foto("casa_tercera_pared")
		print("Pared H01: impacto ", pared.position, ", normal ", normal, ", colisión ", pared.collider,
			", Leo ", leo.global_position, ", pivote ", leo.camara.global_position,
			", cámara ", leo.camara.camara.global_position, ", distancia ", leo.camara.distancia_real)
		return
	_errores += 1
	push_error("No se encontró una pared de la casa para la captura de tercera persona.")


func _paneles() -> void:
	Interfaz._pausa.abrir()
	await _foto("pausa_controles")
	Interfaz.abrir_ajustes()
	var botones := Interfaz._ajustes.find_children("*", "Button", true, false)
	for pestana in ["Imagen", "Controles"]:
		for boton: Button in botones:
			if boton.text == pestana:
				boton.pressed.emit()
				break
		await _foto("ajustes_" + pestana.to_lower())
	if not _antes:
		var lista := Interfaz._ajustes.find_children("*", "ScrollContainer", true, false)
		var boton_vista := Interfaz._ajustes._botones_tecla.get("alternar_vista") as Button
		if not lista.is_empty() and boton_vista != null:
			(lista[0] as ScrollContainer).ensure_control_visible(boton_vista)
			await _foto("ajustes_remapeo_vista")
	Interfaz.cerrar_todo()


func _foto(nombre: String, espera: float = 0.35) -> void:
	await get_tree().create_timer(espera).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty() or img.save_png(_salida + "/" + nombre + ".png") != OK:
		_errores += 1
		push_error("No se pudo guardar la captura " + nombre)
	else:
		print("Captura H01: ", nombre, " ", img.get_size())


func _medir(nombre: String, carga: int) -> void:
	const FOTOGRAMAS := 600
	await get_tree().create_timer(2.0).timeout
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
	var peores := FOTOGRAMAS / 100
	for i in range(FOTOGRAMAS - peores, FOTOGRAMAS):
		ms_peores += tiempos[i] / peores
	var linea := "%s: %.1f FPS medios, %.1f FPS (1 %% más lento), carga %d ms" % [
		nombre, FOTOGRAMAS * 1000.0 / total, 1000.0 / ms_peores, carga]
	_medidas.append(linea)
	print(linea)
