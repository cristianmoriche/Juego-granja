extends Node
## Capturas antes/después para T21-herramientas-en-mano (2 PNG + secuencia de vídeo).

var _j: Jugador = null
var _mapa: Node = null
var _salida: String = ""
var _frames_dir: String = ""
var _idx_frame: int = 0
var _base: Vector3 = Vector3.ZERO


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.autostart = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.call_deferred("add_child", tope)
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _fisica(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _poner_cam(yaw: float = 0.42, dist: float = 2.45) -> void:
	var cam := _j.camara
	cam.yaw = yaw
	cam.pitch = deg_to_rad(12.0)
	cam._dist_obj = dist
	cam.distancia = dist
	cam.global_position = _j.global_position + Vector3(0.0, cam._altura_mira() * cam.altura_relativa, 0.0)
	cam._aplicar(0.0)


func _colocar(pos: Vector3, dir_y: float = 0.0, yaw_cam: float = 0.42) -> void:
	_j.colocar(pos, dir_y, yaw_cam)
	_j.velocity = Vector3.ZERO
	_poner_cam(yaw_cam)


func _grabar_foto(ruta_completa: String, ancho_max: int = 960) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > ancho_max:
		img.resize(ancho_max, int(float(img.get_height()) * float(ancho_max) / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png(ruta_completa)


func _grabar_frame() -> void:
	var p := "%s/f_%03d.png" % [_frames_dir, _idx_frame]
	_idx_frame += 1
	await _grabar_foto(p, 768)


func _grabar_rafaga(frames: int, fisica_entre: int = 3) -> void:
	for _i in frames:
		await _fisica(fisica_entre)
		_poner_cam()
		await _grabar_frame()


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
	var fase := OS.get_environment("MH_T21_FASE")
	if fase.is_empty():
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T21-herramientas-en-mano/" + fase)
	_frames_dir = _salida + "/tmp_frames"
	DirAccess.make_dir_recursive_absolute(_frames_dir)

	Juego.ruta_partida = "user://partida_capturas_t21.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 680
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")):
			break
		await get_tree().process_frame
	Interfaz.mostrar_hud(false)
	_base = _buscar_claro()

	# 1) Pico en mano andando
	Juego.elegir_ranura(4) # pico
	_colocar(_base, 0.0, 0.42)
	await _fisica(4)
	Input.action_press("mover_abajo")
	await _esperar(0.32)
	_poner_cam(0.42)
	await _grabar_foto(_salida + "/01_caminando_con_pico.png")
	await _grabar_rafaga(8, 3)
	Input.action_release("mover_abajo")
	await _fisica(4)

	# 2) Azada + foto fija mitad de golpe + resto de herramientas en vídeo
	var ranuras := [0, 4, 3, 1, 2, 5] # azada, pico, hacha, regadera, hoz, semilla_patata
	for r in ranuras:
		Juego.elegir_ranura(r)
		_colocar(_base, 0.0, 0.42)
		_j._t_herramienta = 0.0
		await _fisica(3)
		_j.animar_herramienta()
		if r == 0:
			await _esperar(0.26)
			_poner_cam(0.42)
			await _grabar_foto(_salida + "/02_usando_herramienta.png")
		await _grabar_rafaga(10, 3)

	print("CAPTURAS T21 OK (", fase, ", frames=", _idx_frame, ")")
	get_tree().quit(0)
