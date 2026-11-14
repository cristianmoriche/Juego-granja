extends Node
## Capturas antes/después de T11-direccion-artistica desde exactamente las mismas cámaras:
## granja, pueblo, un interior (taberna) y mina_interior a las 08:00, 14:00 y 20:00,
## además de vistas de vegetación/árboles y mina_exterior a las 14:00.

const HORAS: Array[Dictionary] = [
	{"et": "0800", "min": 480},
	{"et": "1400", "min": 840},
	{"et": "2000", "min": 1200},
]

var _cam: Camera3D = null
var _salida: String = ""
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			push_error("T11 capturas: tiempo límite agotado")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _camara_libre(pos: Vector3, mirar: Vector3, fov: float = 54.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.far = 500.0
		_cam.near = 0.1
		get_tree().root.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = pos
	_cam.look_at(mirar, Vector3.UP)
	_cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame


func _foto(nombre: String) -> void:
	await _esperar(0.4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ruta := _salida + "/" + nombre + ".png"
	var err := img.save_png(ruta)
	print("captura ", nombre, " ", img.get_size(), " err=", err, " -> ", ruta)


func _cargar_mapa(id_m: String, minutos_dia: int) -> Node:
	print("-> cargando ", id_m, " min=", minutos_dia)
	Juego.estacion = 0
	Juego.dia = 5
	Juego.minutos = minutos_dia
	Juego.clima = "sol"
	Juego.pausar_tiempo(true)
	await Escenas.ir_a_mapa(id_m, "Spawn_Protagonista")
	Interfaz.mostrar_hud(false)
	var m := Escenas.mapa_actual_nodo()
	for _i in 180:
		if m != null and bool(m.get("vallas_listas")):
			break
		await get_tree().process_frame
	_fijar_hora(m, minutos_dia)
	await _esperar(0.5)
	return m


func _fijar_hora(m: Node, minutos_dia: int) -> void:
	Juego.minutos = minutos_dia
	Juego.pausar_tiempo(true)
	Juego.actualizar_entorno_shader()
	if m != null and m.get("_sol") != null:
		var sol := m.get("_sol") as Node
		if sol != null and sol.has_method("actualizar"):
			sol.call("actualizar")


func _ejecutar() -> void:
	print("T11_CAPTURAS_INICIO")
	var fase := OS.get_environment("MH_T11_FASE")
	if fase != "antes" and fase != "despues":
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T11-direccion-artistica/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _esperar(0.2)
	get_tree().current_scene = null

	var ruta_previa := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_capturas_t11.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")

	# 1. Granja (08:00, 14:00, 20:00 + detalle vegetación/bosque a las 14:00).
	var m_granja := await _cargar_mapa("granja", 480)
	var jl := Escenas.jugador()
	if jl != null:
		jl.global_position = Vector3(-3.2, 0.0, 3.2)
	for h: Dictionary in HORAS:
		_fijar_hora(m_granja, int(h["min"]))
		await _camara_libre(Vector3(-12.0, 8.8, 17.5), Vector3(1.5, 2.2, -5.5), 54.0)
		await _foto("granja_%s" % str(h["et"]))
	_fijar_hora(m_granja, 840)
	await _camara_libre(Vector3(-10.5, 2.1, 14.2), Vector3(-16.0, 2.6, 1.5), 52.0)
	await _foto("granja_vegetacion_1400")

	# 2. Pueblo (08:00, 14:00, 20:00 + primer plano árboles/fachadas a las 14:00).
	var m_pueblo := await _cargar_mapa("pueblo", 480)
	for h: Dictionary in HORAS:
		_fijar_hora(m_pueblo, int(h["min"]))
		await _camara_libre(Vector3(-5.5, 5.8, 11.2), Vector3(1.0, 1.6, -4.5), 54.0)
		await _foto("pueblo_%s" % str(h["et"]))
	_fijar_hora(m_pueblo, 840)
	await _camara_libre(Vector3(-6.0, 2.6, 9.5), Vector3(-1.0, 3.2, -9.0), 52.0)
	await _foto("pueblo_plaza_1400")

	# 3. Interior (taberna a las 08:00, 14:00 y 20:00).
	var m_taberna := await _cargar_mapa("taberna", 480)
	jl = Escenas.jugador()
	if jl != null:
		jl.global_position = Vector3(1.2, 0.0, 1.2)
	for h: Dictionary in HORAS:
		_fijar_hora(m_taberna, int(h["min"]))
		await _camara_libre(Vector3(3.4, 2.55, 3.6), Vector3(-1.0, 1.05, -1.6), 56.0)
		await _foto("taberna_%s" % str(h["et"]))

	# 4. Mina interior (08:00, 14:00 y 20:00) + mina exterior a las 14:00.
	var m_mina := await _cargar_mapa("mina_interior", 480)
	jl = Escenas.jugador()
	if jl != null:
		jl.global_position = Vector3(405.5, 0.0, -0.35)
	for h: Dictionary in HORAS:
		_fijar_hora(m_mina, int(h["min"]))
		await _camara_libre(Vector3(401.2, 1.7, 0.95), Vector3(413.0, 1.15, -0.35), 58.0)
		await _foto("mina_interior_%s" % str(h["et"]))

	var m_mext := await _cargar_mapa("mina_exterior", 840)
	_fijar_hora(m_mext, 840)
	await _camara_libre(Vector3(-13.2, 2.6, 13.5), Vector3(2.0, 2.8, -5.0), 54.0)
	await _foto("mina_exterior_1400")

	Juego.borrar_partida()
	Juego.ruta_partida = ruta_previa
	_terminado = true
	print("CAPTURAS T11 (" + fase + ") COMPLETADAS")
	get_tree().quit(0)
