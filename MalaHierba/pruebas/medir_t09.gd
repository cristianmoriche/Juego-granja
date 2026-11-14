extends Node
## Diagnóstico de T09: mide memoria en menú y tiempo de carga en frío de granja/pueblo.


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("medir_t09: tiempo límite de 60 s superado")
		get_tree().quit(1))
	get_tree().root.add_child.call_deferred(tope)
	tope.ready.connect(tope.start)
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	var scr := DisplayServer.screen_get_size()
	var win := get_window().size
	var modo := OS.get_environment("T09_MODO")
	if modo == "":
		modo = "menu"

	print("T09_INFO pantalla=%s ventana=%s mode=%s" % [scr, win, modo])
	if modo == "menu":
		var e := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(e)
		get_tree().current_scene = e
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		_imprimir_mem("menu_principal")
		get_tree().quit(0)
		return

	if modo == "flujo_granja" or modo == "flujo_pueblo":
		var id := "granja" if modo == "flujo_granja" else "pueblo"
		var menu := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(menu)
		get_tree().current_scene = menu
		await get_tree().process_frame
		await get_tree().process_frame
		_imprimir_mem("flujo_en_menu_" + id)
		Juego.nueva_partida("Leo")
		Juego.pausar_tiempo(true)
		var t0 := Time.get_ticks_msec()
		Escenas.ir_a_mapa(id, "Spawn_Protagonista")
		while Escenas.en_transicion:
			await get_tree().process_frame
		var dt := Time.get_ticks_msec() - t0
		var mapa_n := Escenas.mapa_actual_nodo()
		var c := mapa_n.get_node_or_null("CargadorMapa") if mapa_n != null else null
		var ms_carg := int(c.get("tiempo_carga_ms")) if c != null else -1
		print("T09_FLUJO %s total_transicion=%d ms cargador=%d ms" % [id, dt, ms_carg])
		_imprimir_mem("flujo_en_" + id)
		get_tree().quit(0)
		return

	if modo == "frio_granja" or modo == "frio_pueblo":
		var id := "granja" if modo == "frio_granja" else "pueblo"
		_imprimir_mem("antes_" + id)
		var t0 := Time.get_ticks_msec()
		var ps := load("res://escenas/mapas/%s.tscn" % id) as PackedScene
		var dt_load := Time.get_ticks_msec() - t0
		var nodo := ps.instantiate() as Node3D
		var t1 := Time.get_ticks_msec()
		add_child(nodo)
		if not bool(nodo.get("esta_listo")):
			await nodo.listo
		await get_tree().process_frame
		await get_tree().process_frame
		var dt_total := Time.get_ticks_msec() - t0
		var dt_inst := Time.get_ticks_msec() - t1
		var c := nodo.get_node_or_null("CargadorMapa")
		var ms_carg := int(c.get("tiempo_carga_ms")) if c != null else -1
		print("T09_CARGA %s load_tscn=%d ms inst_y_frame=%d ms total=%d ms cargador=%d ms" % [id, dt_load, dt_inst, dt_total, ms_carg])
		_imprimir_mem("despues_" + id)
		nodo.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return

	if modo == "probar_ventana":
		for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(3440, 1440)]:
			get_window().size = res
			await get_tree().process_frame
			await get_tree().process_frame
			print("T09_VENTANA pedida=%s real=%s vp=%s" % [res, get_window().size, get_viewport().get_visible_rect().size])
		get_tree().quit(0)


func _imprimir_mem(etiqueta: String) -> void:
	var st := OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var pk := OS.get_static_memory_peak_usage() / (1024.0 * 1024.0)
	var vr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var tx := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	var bf := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / (1024.0 * 1024.0)
	var info := OS.get_memory_info()
	print("T09_MEM [%s] static=%.1fMB peak=%.1fMB vram=%.1fMB (tex=%.1fMB buf=%.1fMB) phys_free=%.0fMB" % [
		etiqueta, st, pk, vr, tx, bf, float(info.get("available", 0)) / (1024.0 * 1024.0)
	])
