extends Node
## Captura representativa Vulkan (1920x1080, calidad Alto, 1ª persona con farol) de los biomas de H04-minas-grandes
## y medición real de FPS por nivel.

const SALIDA := "res://../gestion/noche-codex/capturas/H04-minas-grandes"
const FOTOGRAMAS := 180

var _salida: String = ""
var _fallos: int = 0


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void: get_tree().quit(2))
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	_salida = ProjectSettings.globalize_path(SALIDA)
	DirAccess.make_dir_recursive_absolute(_salida)
	Ajustes.ruta = "user://ajustes_capturas_h04.cfg"
	Juego.ruta_partida = "user://partida_capturas_h04.json"
	Ajustes.poner("vista", 0)
	Ajustes.poner("fov", 80)
	Ajustes.poner("calidad", 2)
	Ajustes.poner("pantalla_completa", false)
	Ajustes.poner("resolucion", 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Juego.nueva_partida("CapturasH04")
	Juego.pausar_tiempo(true)
	Juego.minutos = 720
	get_tree().current_scene = null

	var muestras := [
		{"nv": 1, "archivo": "nv01_piedra_ala", "pos": Vector3(440.5, 0.0, -15.9), "yaw": -PI * 0.5},
		{"nv": 2, "archivo": "nv02_puente_oscura", "pos": Vector3(454.5, 0.0, -15.9), "yaw": -PI * 0.5},
		{"nv": 8, "archivo": "nv08_humeda_lago", "pos": Vector3.INF, "yaw": 0.0},
		{"nv": 13, "archivo": "nv13_cristal", "pos": Vector3.INF, "yaw": 0.0},
		{"nv": 20, "archivo": "nv20_magma_puente", "pos": Vector3.INF, "yaw": 0.0},
	]

	for m: Dictionary in muestras:
		var nv := int(m["nv"])
		Juego.banderas["nivel_mina"] = nv
		var t0 := Time.get_ticks_msec()
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		var carga_ms := Time.get_ticks_msec() - t0
		var mapa := Escenas.mapa_actual_nodo()
		var nm := mapa.get_node_or_null("Objetos/NivelMina") as NivelMina
		var j := Escenas.jugador() as Jugador
		if j == null or nm == null:
			_fallos += 1
			continue
		j.camara.primera_persona = true
		var pos_v: Vector3 = m["pos"]
		var yaw_v := float(m["yaw"])
		if pos_v == Vector3.INF:
			var objetivo := _buscar_vista_interesante(nm)
			pos_v = objetivo["pos"]
			yaw_v = float(objetivo["yaw"])
		j.colocar(pos_v, 0.0, yaw_v)
		j.camara.pitch = deg_to_rad(8.0)
		nm.revelar_niebla_en(Vector2(pos_v.x, pos_v.z), 13.5)
		await _frames(10)

		await _medir(str(m["archivo"]), carga_ms)
		await _foto(str(m["archivo"]))

		if nv == 1:
			Interfaz.alternar_mapa()
			await get_tree().create_timer(0.45).timeout
			await _foto("nv01_mapa_niebla")
			Interfaz.alternar_mapa()
			await _frames(4)

	await Escenas._quitar_escena_actual()
	print("CAPTURAS H04 OK")
	get_tree().quit(0 if _fallos == 0 else 1)


func _buscar_vista_interesante(nm: NivelMina) -> Dictionary:
	var geo := nm.get_node_or_null("GeometriaProcedural")
	var pos := Vector3(408.7, 0.0, 2.0)
	var yaw := -PI * 0.5
	if geo != null:
		var candidato := geo.find_child("Pasarela", true, false) as Node3D
		if candidato == null:
			for pref in ["Charco_", "Cristales_", "Magma_"]:
				var lista := geo.find_children(pref + "*", "Node3D", false, false)
				if not lista.is_empty():
					candidato = lista[0] as Node3D
					break
		if candidato != null:
			var cp := candidato.global_position
			var mejor_c := cp
			for c: Vector2i in nm._celdas_cavadas:
				var p2 := nm._mundo_celda(c)
				var h := float(nm._celdas_cavadas[c])
				var p3 := Vector3(p2.x, h, p2.y)
				if p3.distance_to(cp) >= 2.2 and p3.distance_to(cp) <= 6.5:
					mejor_c = p3
					break
			pos = mejor_c
			var d := cp - pos
			d.y = 0.0
			if d.length() > 0.1:
				yaw = atan2(-d.x, -d.z)
	return {"pos": pos, "yaw": yaw}


func _medir(nombre: String, carga_ms: int) -> void:
	await get_tree().create_timer(0.6).timeout
	var tiempos := PackedFloat64Array()
	var inicio := Time.get_ticks_usec()
	var previo := inicio
	for _i in FOTOGRAMAS:
		await get_tree().process_frame
		var ahora := Time.get_ticks_usec()
		tiempos.append((ahora - previo) * 0.001)
		previo = ahora
	tiempos.sort()
	var peor := 0.0
	var cantidad := maxi(1, FOTOGRAMAS / 100)
	for i in range(FOTOGRAMAS - cantidad, FOTOGRAMAS):
		peor += tiempos[i] / cantidad
	print("H04 %s | carga %d ms | %.1f FPS medios | %.1f FPS (1%% más lento)" % [
		nombre, carga_ms, FOTOGRAMAS * 1000000.0 / maxf(float(previo - inicio), 1.0), 1000.0 / maxf(peor, 0.001)
	])


func _foto(nombre: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var imagen := get_viewport().get_texture().get_image()
	if imagen == null or imagen.save_png(_salida.path_join(nombre + ".png")) != OK:
		push_error("Captura H04 fallida: " + nombre)
		_fallos += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
