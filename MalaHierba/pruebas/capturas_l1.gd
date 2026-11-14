extends Node
## Capturas del carril L1: carga cada mapa, lo mira desde sus cámaras Camara_juego y Camara_suelo y guarda
## res://pruebas/capturas/<id>_juego.png y <id>_suelo.png. Mide los fps medios de 120 fotogramas.
## Uso (con ventana, se cierra sola): godot.ps1 --path <proyecto> --scene res://pruebas/capturas_l1.tscn
## Variable de entorno L1_SOLO=<id> para un solo mapa.

const MAPAS := ["mina_interior", "mina_exterior", "pueblo", "granja", "bosque_norte", "costa_lago"]
const FOTOGRAMAS_FPS := 120

var informe: Array[String] = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var solo: String = OS.get_environment("L1_SOLO")
	for id: String in MAPAS:
		if solo != "" and solo != id:
			continue
		await _capturar_mapa(id)
	var f := FileAccess.open("res://pruebas/capturas/informe_l1.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(informe) + "\n")
		f.close()
	print("CAPTURAS LISTAS\n" + "\n".join(informe))
	get_tree().quit(0)


func _capturar_mapa(id: String) -> void:
	var c := CargadorMapa.new()
	c.id_mapa = id
	add_child(c)
	var env := WorldEnvironment.new()
	env.environment = c.crear_entorno()
	add_child(env)
	var sol := c.crear_sol()
	if sol != null:
		add_child(sol)
	var cam := Camera3D.new()
	cam.far = 800.0
	cam.near = 0.1
	add_child(cam)
	cam.current = true
	for clave: String in ["juego", "suelo"]:
		var m := _camara(c, clave)
		if m == null:
			informe.append("%s: sin cámara %s" % [id, clave])
			continue
		cam.global_transform = m.global_transform
		cam.fov = float(m.get_meta("fov", 50.0))
		for i in 25:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in FOTOGRAMAS_FPS:
			await get_tree().process_frame
		var seg := float(Time.get_ticks_usec() - t0) / 1_000_000.0
		var fps := float(FOTOGRAMAS_FPS) / seg
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var ruta := ProjectSettings.globalize_path("res://pruebas/capturas/%s_%s.png" % [id, clave])
		DirAccess.make_dir_recursive_absolute(ruta.get_base_dir())
		img.save_png(ruta)
		var info := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		informe.append("%s %s: %.1f fps · %d primitivas · carga %d ms · %d instancias" % [id, clave, fps, info, c.tiempo_carga_ms, c.num_instancias])
		print(informe[-1])
	cam.queue_free()
	env.queue_free()
	if sol != null:
		sol.queue_free()
	c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _camara(c: CargadorMapa, clave: String) -> Marker3D:
	for m in c.marcadores_de_tipo("camara"):
		if String(m.name).to_lower().contains(clave):
			return m
	return null
