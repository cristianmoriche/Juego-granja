extends Node
## Capturas visuales de T25-mapa-amplio (antes y después) con tope interno de 60 s.

const RUTA_CAP := "res://../gestion/noche-codex/capturas/T25-mapa-amplio"


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.timeout.connect(func() -> void:
		push_error("capturas_t25: tiempo máximo de 60 s superado")
		get_tree().quit(1)
	)
	add_child(tope)
	tope.start()
	_ejecutar.call_deferred()


func _esperar(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _esperar_mapa() -> Mapa:
	for i in range(600):
		var m := Escenas.mapa_actual_nodo() as Mapa
		if m != null and m.esta_listo and m.vallas_listas:
			await _esperar(4)
			return m
		await get_tree().process_frame
	return null


func _foto(ruta: String, pos: Vector3, mirar: Vector3, fov: float = 52.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	get_tree().root.add_child(cam)
	cam.global_position = pos
	cam.look_at(mirar, Vector3.UP)
	cam.current = true
	await _esperar(5)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(ruta))
	print("CAPTURA ", ruta, " -> ", err)
	cam.queue_free()


func _medir_alturas(m: Mapa, id: String, puntos: Array) -> void:
	for p: Variant in puntos:
		var v := p as Vector2
		var col: Dictionary = m.call("_columna_suelo", v.x, v.y) as Dictionary
		print("ALTURA %s (%.1f, %.1f) = suelo:%.3f choque:%s" % [id, v.x, v.y, float(col.get("suelo", NAN)), str(col.get("hay_suelo", false))])


func _ejecutar() -> void:
	var args := OS.get_cmdline_user_args()
	var fase := "antes"
	for a: String in args:
		if a.begins_with("--fase="):
			fase = a.substr(7)

	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_t25.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 720
	Juego.clima = "sol"
	Interfaz.cerrar_todo()

	if fase == "antes":
		await Escenas.ir_a_mapa("granja")
		var mg := await _esperar_mapa()
		if mg != null:
			_medir_alturas(mg, "granja", [Vector2(3.0, -16.2), Vector2(3.0, -12.5), Vector2(4.8, -12.5)])
			await _foto(RUTA_CAP + "/antes/01_granja_norte.png", Vector3(3.0, 2.5, -2.5), Vector3(3.0, 1.3, -18.0))

		await Escenas.ir_a_mapa("pueblo")
		var mp := await _esperar_mapa()
		if mp != null:
			_medir_alturas(mp, "pueblo", [Vector2(13.5, -28.0), Vector2(13.5, -24.5), Vector2(11.0, -24.0), Vector2(1.5, 42.5), Vector2(1.5, 38.5), Vector2(4.0, 38.0)])
			await _foto(RUTA_CAP + "/antes/02_pueblo_sur.png", Vector3(1.5, 4.2, 16.0), Vector3(1.5, 1.2, 46.0))

		await Escenas.ir_a_mapa("mina_exterior")
		var mm := await _esperar_mapa()
		if mm != null:
			_medir_alturas(mm, "mina_exterior", [Vector2(32.5, 20.0), Vector2(28.5, 20.0), Vector2(28.0, 17.5)])
	else:
		await Escenas.ir_a_mapa("bosque_norte")
		var mb := await _esperar_mapa()
		if mb != null:
			await _foto(RUTA_CAP + "/despues/01_bosque_norte.png", Vector3(-6.0, 5.2, 16.0), Vector3(4.0, 1.8, -6.0), 56.0)

		await Escenas.ir_a_mapa("costa_lago")
		var mc := await _esperar_mapa()
		if mc != null:
			await _foto(RUTA_CAP + "/despues/02_costa_lago.png", Vector3(-12.0, 4.8, -10.0), Vector3(4.0, 0.8, 12.0), 56.0)

	print("CAPTURAS_T25 OK (", fase, ")")
	get_tree().quit(0)
