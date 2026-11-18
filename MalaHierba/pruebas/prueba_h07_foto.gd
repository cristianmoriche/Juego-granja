extends Node
## Prueba breve de H07-modo-foto-y-detalles: modo foto, farol/antorcha equipables de noche, pasos y ambientes.

var _errores: int = 0
var _ok: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_errores += 1
		push_error("FALLO H07: " + msg)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().current_scene = null

	_check(InputMap.has_action("modo_foto"), "accion modo_foto existe")
	_check(InputMap.has_action("alternar_luz"), "accion alternar_luz existe")
	_check(Datos.existe_objeto("antorcha") and Datos.existe_objeto("farol_mano"), "antorcha y farol_mano en objetos.json")
	_check(Datos.tiene_icono("antorcha") and Datos.tiene_icono("farol_mano"), "iconos PNG de luz existen")

	for wav_id: String in ["paso_agua", "respiracion_fatiga", "amb_dia_pajaros", "amb_noche_grillos", "amb_viento_sierra", "amb_agua"]:
		_check(FileAccess.file_exists("res://assets/audio/%s.wav" % wav_id), "audio %s.wav presente" % wav_id)

	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 760
	_check(Juego.cantidad("antorcha") >= 1, "Leo recibe antorcha inicial")

	# Ambiente por zona y hora
	_check(Audio.ambiente_para_mapa("bosque_norte") == "amb_dia_pajaros", "ambiente dia bosque = pajaros")
	_check(Audio.ambiente_para_mapa("sierra_mirador") == "amb_viento_sierra", "ambiente sierra = viento")
	Juego.minutos = 1320 # 22:00 noche
	_check(Audio.ambiente_para_mapa("granja") == "amb_noche_grillos", "ambiente noche = grillos")
	Juego.minutos = 760

	await Escenas.ir_a_mapa("bosque_norte")
	await get_tree().process_frame
	await get_tree().process_frame

	var j := Escenas.jugador()
	_check(j != null, "jugador activo en bosque_norte")
	if j != null:
		# Pasos por superficie
		j.global_position = Vector3(-1.0, 0.25, 1.0) # puente madera
		_check(j.call("_sonido_paso") == "paso_madera", "paso en puente = madera")
		j.global_position = Vector3(-4.5, 0.05, 7.0) # orilla agua
		_check(j.call("_sonido_paso") == "paso_agua", "paso en orilla = agua")
		j.global_position = Vector3(-12.0, 0.4, 24.0) # bosque hierba
		_check(j.call("_sonido_paso") == "paso_hierba", "paso en prado = hierba")

		# Equipar farol y verificar luz nocturna exterior + toggle
		Juego.anadir_objeto("farol_mano", 1)
		for i in Juego.HUECOS:
			if str(Juego.inventario[i].get("id", "")) == "farol_mano":
				_check(Juego.equipar(i), "equipar farol_mano en ranura luz")
				break
		_check(str(Juego.equipo.get("luz", "")) == "farol_mano", "equipo['luz'] == farol_mano")
		Juego.minutos = 760
		Juego.hora_cambiada.emit(760)
		await get_tree().process_frame
		var farol := j.get_node("Farol") as OmniLight3D
		_check(not farol.visible, "de dia en exterior el farol esta apagado en automatico")
		Juego.avanzar_minutos(560) # 22:00 noche
		await get_tree().process_frame
		_check(farol.visible and farol.light_energy > 2.0, "de noche en exterior el farol se enciende")
		_check(j.call("alternar_luz_equipable") == false and not farol.visible, "tecla L apaga farol")
		_check(j.call("alternar_luz_equipable") == true and farol.visible, "tecla L enciende farol")

		# Modo foto: pausa árbol, limites, DoF, FOV, inclinación, ocultar Leo y captura PNG
		Interfaz.abrir_modo_foto()
		await get_tree().process_frame
		_check(Interfaz.modo_foto_abierto(), "modo foto se abre")
		_check(get_tree().paused, "modo foto pausa el arbol")
		var mf := Interfaz.get("_modo_foto") as ModoFoto
		var dir_tmp := ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H07-modo-foto-y-detalles").simplify_path()
		mf.ruta_capturas_personalizada = dir_tmp
		mf.poner_fov(48.0)
		mf.poner_exposicion(1.15)
		mf.poner_inclinacion(8.0)
		mf.poner_dof(true, 7.5, 0.20)
		mf.poner_filtro(1)
		mf.poner_ocultar_leo(true)
		var cam_f: Camera3D = mf.camara_foto()
		_check(cam_f != null and is_equal_approx(cam_f.fov, 48.0), "camara modo foto aplica FOV")
		var mod_leo := j.get_node_or_null("Modelo") as Node3D
		_check(mod_leo != null and not mod_leo.visible, "ocultar Leo oculta el modelo")
		if DisplayServer.get_name() != "headless":
			var png_path: String = await mf.capturar_foto("prueba_headless_ignorada.png")
			_check(not png_path.is_empty() and FileAccess.file_exists(png_path), "foto PNG guardada en disco")
		else:
			_check(not mf.directorio_capturas().is_empty(), "directorio de capturas valido")
		mf.cerrar_panel()
		await get_tree().process_frame
		_check(not Interfaz.modo_foto_abierto() and not get_tree().paused, "cerrar modo foto despausa el juego")
		_check(mod_leo != null and mod_leo.visible, "cerrar modo foto restaura modelo de Leo")

	if _errores == 0:
		print("PRUEBA H07 FOTO OK (%d comprobaciones)" % _ok)
	else:
		push_error("PRUEBA H07 CON %d ERRORES" % _errores)
	get_tree().quit(0 if _errores == 0 else 1)
