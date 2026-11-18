extends Node
## Captura visual representativa de H05 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1 muestra ampliada (granja), 3 zonas nuevas (sierra_mirador, robledal_niebla, ruinas_valle) + horizonte.

var _sal := ""


func _ready() -> void:
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H05-mapa-grande").simplify_path()
	DirAccess.make_dir_recursive_absolute(_sal)
	_ejecutar.call_deferred()


func _esperar() -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _i in 6:
		await get_tree().physics_frame
	for _i in 4:
		await get_tree().process_frame


func _medir_fps_y_capturar(archivo: String) -> void:
	for _w in 18:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for _i in 20:
		await get_tree().process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1_000_000.0
	var fps := 20.0 / maxf(dt, 0.001)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_sal.path_join(archivo))
	print("CAPTURA %s -> %.1f FPS" % [archivo, fps])


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 750  # 12:30 luz clara

	# 1) Granja ampliada mirando al horizonte este y parcela 4
	await Escenas.ir_a_mapa("granja")
	await _esperar()
	var j := Escenas.jugador()
	if j != null:
		j.colocar(Vector3(14.0, 0.8, 12.0), -1.3, 0.08)
	await _medir_fps_y_capturar("granja_ampliada.png")

	# 2) Sierra del Mirador desde la cumbre hacia el horizonte
	await Escenas.ir_a_mapa("sierra_mirador")
	await _esperar()
	j = Escenas.jugador()
	if j != null:
		j.colocar(Vector3(1.5, 9.2, -31.5), 0.15, 0.0)
	await _medir_fps_y_capturar("sierra_mirador.png")

	# 3) Robledal de la Niebla (robles + estanque)
	await Escenas.ir_a_mapa("robledal_niebla")
	await _esperar()
	j = Escenas.jugador()
	if j != null:
		j.colocar(Vector3(-4.0, 1.0, 14.0), -1.1, 0.04)
	await _medir_fps_y_capturar("robledal_niebla.png")

	# 4) Ruinas del Molino Viejo (arcos + muela + arroyo)
	await Escenas.ir_a_mapa("ruinas_valle")
	await _esperar()
	j = Escenas.jugador()
	if j != null:
		j.colocar(Vector3(3.0, 1.0, 4.0), 0.55, 0.05)
	await _medir_fps_y_capturar("ruinas_valle.png")

	print("CAPTURAS H05 OK")
	get_tree().quit(0)
