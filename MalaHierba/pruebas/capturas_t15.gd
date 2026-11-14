extends Node
## Capturas antes/después de T15-estaciones desde exactamente las mismas cámaras
## para primavera, verano, otono e invierno en granja y pueblo, más capturas de mecánicas T15.

const NOMBRES: Array[String] = ["primavera", "verano", "otono", "invierno"]

var _cam: Camera3D = null
var _salida: String = ""
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			push_error("T15 capturas: tiempo límite agotado")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _camara_libre(pos: Vector3, mirar: Vector3, fov: float = 52.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 400.0
		get_tree().root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(mirar, Vector3.UP)
	_cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame


func _foto(nombre: String) -> void:
	await _esperar(0.45)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := _salida + "/" + nombre + ".png"
	var err := img.save_png(ruta)
	print("captura ", nombre, " ", img.get_size(), " err=", err, " -> ", ruta)


func _cargar_mapa_estacion(id_m: String, est: int, hora_min: int = 660, clima: String = "sol", mantener_fecha: bool = false) -> Node:
	print("-> cargando ", id_m, " est=", est, " clima=", clima)
	if not mantener_fecha:
		Juego.estacion = est
		Juego.dia = 10
	Juego.minutos = hora_min
	Juego.clima = clima
	Juego.pausar_tiempo(true)
	await Escenas.ir_a_mapa(id_m, "Spawn_Protagonista")
	Interfaz.mostrar_hud(false)
	var m := Escenas.mapa_actual_nodo()
	for _i in 180:
		if m != null and bool(m.get("vallas_listas")):
			break
		await get_tree().process_frame
	Juego.minutos = hora_min
	Juego.pausar_tiempo(true)
	Juego.actualizar_entorno_shader()
	if m != null and m.has_method("_actualizar_precipitacion"):
		m.call("_actualizar_precipitacion")
	await _esperar(0.6)
	return m


func _poblar_huerta_invierno(m: Node) -> Vector3:
	var centro := Vector3.ZERO
	var pars := m.find_children("*", "Parcelas", true, false)
	if pars.is_empty():
		return centro
	var par := pars[0] as Parcelas
	var claves: Array = Cultivos.parcelas().keys()
	claves.sort()
	var ids_inv: Array[String] = ["espinaca", "nabo", "azafran", "ajo"]
	var count := 0
	var suma := Vector3.ZERO
	for i in mini(claves.size(), 16):
		var k := str(claves[i])
		var c := Cultivos.parcela(k)
		var id_c: String = ids_inv[i % ids_inv.size()]
		c["estado"] = "arado"
		c["regado"] = (i % 2 == 0)
		c["cultivo"] = id_c
		c["etapa"] = 3
		c["listo"] = true
		c["plaga"] = (i >= 12)
		if par != null:
			var pos_c: Vector3 = par.posicion_de(k)
			if pos_c != Vector3.ZERO:
				suma += pos_c
				count += 1
	Cultivos.parcelas_cambiadas.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return suma / maxf(float(count), 1.0)


func _buscar_dia_evento(tipo: String) -> int:
	var prog := Juego.eventos_anio()
	for d in range(1, 113):
		var c := str(d)
		if prog.has(c) and str((prog[c] as Dictionary).get("tipo", "")) == tipo:
			return d
	return -1


func _avanzar_a_dia(d_anio: int) -> void:
	while Juego.dia_anio() < d_anio:
		if not Juego.terminar_dia(false, false):
			break


func _ejecutar() -> void:
	print("T15_CAPTURAS_INICIO")
	var fase := OS.get_environment("MH_T15_FASE")
	if fase != "antes" and fase != "despues":
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T15-estaciones/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _esperar(0.2)
	get_tree().current_scene = null

	var ruta_previa := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_capturas_t15.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")

	for e in 4:
		var nom: String = NOMBRES[e]
		await _cargar_mapa_estacion("granja", e)
		await _camara_libre(Vector3(-12.5, 11.0, 17.5), Vector3(1.5, 2.2, -5.5), 54.0)
		await _foto("%02d_granja_%s" % [e * 2 + 1, nom])

		await _cargar_mapa_estacion("pueblo", e)
		await _camara_libre(Vector3(-17.0, 11.5, 20.0), Vector3(2.0, 2.5, -7.0), 54.0)
		await _foto("%02d_pueblo_%s" % [e * 2 + 2, nom])

	if fase == "despues":
		var tut_previo: bool = bool(Ajustes.valores.get("tutorial", true))
		Ajustes.valores["tutorial"] = false
		Tutorial.actualizado.emit()
		if Interfaz._hud != null and Interfaz._hud.get("_tutorial") != null:
			(Interfaz._hud.get("_tutorial") as Control).visible = false

		# 09: Huerta de invierno con cultivos invernales (espinaca, nabo, azafran, ajo) y nieve cayendo.
		var mgr := await _cargar_mapa_estacion("granja", 3, 680)
		var ch := await _poblar_huerta_invierno(mgr)
		Juego.anadir_objeto("remedio_plaga", 3)
		Juego.anadir_objeto("semilla_espinaca", 5)
		Juego.anadir_objeto("semilla_nabo", 4)
		Juego.anadir_objeto("semilla_azafran", 2)
		Juego.anadir_objeto("elixir_sierra", 1)
		Juego.anadir_objeto("ambar_valle", 1)
		Interfaz.mostrar_hud(true)
		if Interfaz._hud != null:
			Interfaz._hud.limpiar_avisos()
		await _camara_libre(ch + Vector3(-4.6, 3.8, 5.4), ch + Vector3(0.4, 0.15, 0.0), 50.0)
		await _esperar(1.0)
		await _foto("09_invierno_huerta_y_nieve")

		# 10: Tormenta real + cercas rotas y aviso en HUD.
		Juego.nueva_partida("Leo")
		var dia_torm := _buscar_dia_evento("tormenta")
		_avanzar_a_dia(dia_torm)
		var mgr_t := await _cargar_mapa_estacion("granja", Juego.estacion, 690, "tormenta", true)
		Interfaz.mostrar_hud(true)
		if Interfaz._hud != null:
			Interfaz._hud.limpiar_avisos()
		var r_cerca := mgr_t.get_node_or_null("RepararCercas") as Node3D
		if r_cerca != null and r_cerca.get_child_count() > 0:
			var pto := (r_cerca.get_child(0) as Node3D).global_position
			await _camara_libre(pto + Vector3(4.2, 3.4, 5.0), pto + Vector3(0, 0.4, 0), 52.0)
		else:
			await _camara_libre(Vector3(-12.5, 11.0, 17.5), Vector3(1.5, 2.2, -5.5), 54.0)
		await _esperar(1.0)
		await _foto("10_tormenta_cercas_rotas")

		# 11: Mercader ambulante en plaza nevada de invierno.
		Juego.nueva_partida("Leo")
		var ev_inv := 85
		for dd in range(85, 113):
			if str(Juego.evento_en_dia(dd).get("tipo", "")) == "comerciante":
				ev_inv = dd
				break
		_avanzar_a_dia(ev_inv)
		var mp := await _cargar_mapa_estacion("pueblo", Juego.estacion, 680, "sol", true)
		Interfaz.mostrar_hud(true)
		if Interfaz._hud != null:
			Interfaz._hud.limpiar_avisos()
		var merc := mp.objetos.get_node_or_null("MercaderAmbulante") as Node3D
		if merc != null:
			var pm := merc.global_position
			await _camara_libre(pm + merc.global_transform.basis.z * 4.4 + merc.global_transform.basis.x * 0.4 + Vector3(0, 1.95, 0), pm + Vector3(0, 1.05, 0), 48.0)
		else:
			await _camara_libre(Vector3(-17.0, 11.5, 20.0), Vector3(2.0, 2.5, -7.0), 54.0)
		await _esperar(1.0)
		await _foto("11_pueblo_mercader_invierno")

		# 12: Panel de tienda del mercader ambulante con artículos raros y cultivos nuevos.
		Interfaz.abrir_tienda("comerciante_ambulante")
		await _esperar(0.5)
		await _foto("12_tienda_mercader_objetos_raros")

		# 13: Mercado especial x2 + calidad normal vs baja por plaga.
		Interfaz.cerrar_todo()
		Juego.nueva_partida("Leo")
		var dia_merc := _buscar_dia_evento("mercado")
		_avanzar_a_dia(dia_merc)
		var cult_m := Juego.cultivo_mercado_especial()
		Juego.anadir_objeto(cult_m, 4, "")
		Juego.anadir_objeto(cult_m, 3, "baja")
		Juego.anadir_objeto("patata", 2, "baja")
		await _cargar_mapa_estacion("pueblo", Juego.estacion, 680, "sol", true)
		if Interfaz._hud != null:
			Interfaz._hud.limpiar_avisos()
		Interfaz.abrir_tienda("tienda_mateo")
		var pan := Interfaz._tienda
		if pan != null and pan.has_method("_cambiar_modo"):
			pan.call("_cambiar_modo", "vender")
		await _esperar(0.5)
		await _foto("13_tienda_mercado_especial_y_plaga")
		Interfaz.cerrar_todo()
		Ajustes.valores["tutorial"] = tut_previo
		Tutorial.actualizado.emit()

	Juego.borrar_partida()
	Juego.ruta_partida = ruta_previa
	_terminado = true
	print("CAPTURAS T15 (" + fase + ") COMPLETADAS")
	get_tree().quit(0)
