extends Node
## Mide tiempos de carga, FPS/drawcalls en zonas densas y consumo en menú antes y después de optimizar (H14).

const ZONAS := ["granja", "pueblo", "bosque_norte", "robledal_niebla"]


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 90.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("medir_h14: timeout 90s")
		get_tree().quit(1))
	get_tree().root.add_child.call_deferred(tope)
	tope.ready.connect(tope.start)
	_ejecutar.call_deferred()


func _mem(etiqueta: String) -> void:
	var st := OS.get_static_memory_usage() / (1024.0 * 1024.0)
	var pk := OS.get_static_memory_peak_usage() / (1024.0 * 1024.0)
	var vr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var tx := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	var bf := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / (1024.0 * 1024.0)
	print("H14_MEM [%s] static=%.1fMB peak=%.1fMB vram=%.1fMB (tex=%.1fMB buf=%.1fMB)" % [etiqueta, st, pk, vr, tx, bf])


func _contar_sombras(mapa: Node) -> Dictionary:
	var luces_totales := 0
	var luces_con_sombra := 0
	var mallas_inst := 0
	var mm_inst := 0
	var pilas := [mapa]
	while not pilas.is_empty():
		var n: Node = pilas.pop_back()
		if n is Light3D and not (n is DirectionalLight3D):
			luces_totales += 1
			if (n as Light3D).shadow_enabled:
				luces_con_sombra += 1
		elif n is MeshInstance3D:
			mallas_inst += 1
		elif n is MultiMeshInstance3D:
			mm_inst += 1
		for h in n.get_children():
			pilas.append(h)
	return {
		"luces": luces_totales,
		"sombras": luces_con_sombra,
		"mallas": mallas_inst,
		"mm": mm_inst,
	}


func _ejecutar() -> void:
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	var menu := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	for _i in 6:
		await get_tree().process_frame
	_mem("menu_inicial")

	Juego.ruta_partida = "user://partida_medir_h14.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 1170   # 19:30 para activar luces exteriores en pueblo/granja

	for z: String in ZONAS:
		var t0 := Time.get_ticks_msec()
		Escenas.ir_a_mapa(z, "Spawn_Protagonista")
		while Escenas.en_transicion:
			await get_tree().process_frame
		var ms_trans := Time.get_ticks_msec() - t0
		# Deja asentar 20 frames y mide 60 frames
		for _f in 20:
			await get_tree().process_frame
		var tiempos: Array[float] = []
		var t_a := Time.get_ticks_usec()
		for _f in 60:
			await get_tree().process_frame
			var t_b := Time.get_ticks_usec()
			tiempos.append(float(t_b - t_a) / 1000.0)
			t_a = t_b
		var suma := 0.0
		for dt in tiempos:
			suma += dt
		var fps := 1000.0 / maxf(0.1, suma / float(tiempos.size()))
		var mapa := Escenas.mapa_actual_nodo()
		var carg := mapa.get_node_or_null("CargadorMapa") if mapa != null else null
		var ms_carg := int(carg.get("tiempo_carga_ms")) if carg != null else -1
		var dc := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var cs := _contar_sombras(mapa)
		print("H14_ZONA [%s] trans=%dms cargador=%dms fps=%.1f draw=%d prims=%d lights=%d(shadow=%d) meshes=%d mm=%d" % [
			z, ms_trans, ms_carg, fps, dc, prims, int(cs["luces"]), int(cs["sombras"]), int(cs["mallas"]), int(cs["mm"])
		])

	var t_m0 := Time.get_ticks_msec()
	await Escenas.ir_al_menu()
	var dt_menu := Time.get_ticks_msec() - t_m0
	for _i in 10:
		await get_tree().process_frame
	print("H14_RETORNO_MENU dt=%dms" % dt_menu)
	_mem("menu_tras_jugar")
	Juego.borrar_partida()
	get_tree().quit(0)
