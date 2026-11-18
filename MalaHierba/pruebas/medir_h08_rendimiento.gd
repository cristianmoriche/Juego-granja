extends Node
## Benchmark completo H08 en Vulkan 1080p: todas las zonas y 4 preajustes (FPS medio, 1% bajo, carga y memoria menú).

const ZONAS := [
	"granja", "pueblo", "bosque_norte", "costa_lago", "mina_exterior",
	"mina_interior", "robledal_niebla", "ruinas_valle", "sierra_mirador", "casa_leo",
]
const NOMBRES_CALIDAD := ["Bajo", "Medio", "Alto", "Ultra"]


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 240.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("medir_h08_rendimiento: timeout 240s")
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
	print("H08_MEM [%s] static=%.1fMB peak=%.1fMB vram=%.1fMB (tex=%.1fMB buf=%.1fMB)" % [etiqueta, st, pk, vr, tx, bf])


func _medir_frames(n_warmup: int = 16, n_muestra: int = 64) -> Dictionary:
	for _i in n_warmup:
		await get_tree().process_frame
	var dts: Array[float] = []
	var t_a := Time.get_ticks_usec()
	for _i in n_muestra:
		await get_tree().process_frame
		var t_b := Time.get_ticks_usec()
		dts.append(maxf(0.1, float(t_b - t_a) / 1000.0))
		t_a = t_b
	var suma := 0.0
	for dt in dts:
		suma += dt
	var fps_medio := 1000.0 / (suma / float(dts.size()))
	dts.sort()
	# Peor 1% (al menos 1 cuadro máximo cuando n < 100)
	var n_peor := maxi(1, int(ceil(float(dts.size()) * 0.01)))
	var sum_peor := 0.0
	for k in range(dts.size() - n_peor, dts.size()):
		sum_peor += dts[k]
	var fps_1pct := 1000.0 / (sum_peor / float(n_peor))
	return {"medio": fps_medio, "low1": fps_1pct}


func _ejecutar() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	var menu := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	for _i in 6:
		await get_tree().process_frame
	_mem("menu_inicial")

	Juego.ruta_partida = "user://partida_medir_h08.json"
	Juego.nueva_partida("Benchmark H08")
	Juego.pausar_tiempo(true)
	Juego.minutos = 900   # 15:00 luz diurna realista

	var bajo_60_alto: Array[String] = []
	for z: String in ZONAS:
		Ajustes.poner("calidad", 2)
		var t0 := Time.get_ticks_msec()
		Escenas.ir_a_mapa(z, "Spawn_Protagonista")
		while Escenas.en_transicion:
			await get_tree().process_frame
		var ms_trans := Time.get_ticks_msec() - t0
		var mapa := Escenas.mapa_actual_nodo()
		var carg := mapa.get_node_or_null("CargadorMapa") if mapa != null else null
		var ms_carg := int(carg.get("tiempo_carga_ms")) if carg != null else -1
		var resultados: Array[String] = []
		for cal in 4:
			Ajustes.poner("calidad", cal)
			var m := await _medir_frames(14, 60)
			if cal == 2 and float(m["medio"]) < 60.0:
				bajo_60_alto.append("%s (%.1f fps)" % [z, float(m["medio"])])
			resultados.append("%s=%.1f/%.1f" % [NOMBRES_CALIDAD[cal], float(m["medio"]), float(m["low1"])])
		print("H08_PERF [%s] trans=%dms carg=%dms | FPS(medio/1%%): %s" % [z, ms_trans, ms_carg, ", ".join(resultados)])

	Ajustes.poner("calidad", 2)
	await Escenas.ir_al_menu()
	for _i in 8:
		await get_tree().process_frame
	_mem("menu_tras_recorrido")
	Juego.borrar_partida()
	if not bajo_60_alto.is_empty():
		print("H08_AVISO_BAJO60: " + ", ".join(bajo_60_alto))
	print("H08_BENCH_OK")
	get_tree().quit(0)
