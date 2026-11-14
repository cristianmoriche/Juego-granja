extends Node
## Capturas antes/después para T22-misiones (máximo 2 PNG por fase, tope de 60 s).

var _j: Jugador = null
var _mapa: Node = null


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _grabar_foto(ruta: String, ancho_max: int = 1280) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > ancho_max:
		img.resize(ancho_max, int(float(img.get_height()) * float(ancho_max) / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png(ruta)


func _buscar_claro() -> Vector3:
	for x in [0.5, -2.5, 1.5]:
		for z in [16.0, 19.0, 14.0]:
			var col: Dictionary = _mapa.call("_columna_suelo", x, z)
			var ys := float(col.get("suelo", NAN))
			var obs := float(col.get("obstaculo", 99.0))
			if not is_nan(ys) and obs <= 0.04:
				var p := Vector3(x, ys + 0.02, z)
				if _mapa.call("punto_dentro", p):
					return p
	var sp := (_mapa.call("marcador", "Spawn_Protagonista") as Marker3D).global_position
	return sp + Vector3(0.0, 0.05, 0.0)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	var fase := OS.get_environment("MH_T22_FASE")
	if fase.is_empty():
		fase = "antes"
	var salida := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T22-misiones/" + fase)
	DirAccess.make_dir_recursive_absolute(salida)

	Juego.ruta_partida = "user://partida_capturas_t22.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 640
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")):
			break
		await get_tree().process_frame

	var claro := _buscar_claro()
	_j.colocar(claro, 0.0, 0.35)
	_j.velocity = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout

	if fase == "antes":
		await _grabar_foto(salida + "/01_hud_sin_mision.png")
		Interfaz._pausa.abrir()
		await get_tree().create_timer(0.25).timeout
		await _grabar_foto(salida + "/02_pausa_sin_diario.png")
	else:
		await _grabar_foto(salida + "/01_hud_con_mision.png")
		if Interfaz.has_method("abrir_diario"):
			Interfaz.call("abrir_diario")
		await get_tree().create_timer(0.25).timeout
		await _grabar_foto(salida + "/02_diario_misiones.png")

	Interfaz.cerrar_todo()
	get_tree().quit(0)
