extends Node
## Capturas de T05 en el juego real (antes y después): de pie, andando, agachado quieto, agachado andando,
## saltando y cayendo, de frente y de perfil.
## Uso (con ventana): godot.ps1 --path <proyecto> --position 40,40 --resolution 1280x720 --scene res://pruebas/capturas_t05.tscn

var _j: Jugador = null
var _mapa: Node = null
var _salida: String = ""
var _base: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _fisica(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _poner_cam(yaw: float) -> void:
	var cam := _j.camara
	cam.yaw = yaw
	cam.pitch = deg_to_rad(10.0)
	cam._dist_obj = 3.2
	cam.distancia = 3.2
	cam.global_position = _j.global_position + Vector3(0.0, cam._altura_mira() * cam.altura_relativa, 0.0)
	cam._aplicar(0.0)


func _colocar(pos: Vector3, yaw_cam: float) -> void:
	_j.colocar(pos, 0.0, yaw_cam)
	_j.velocity = Vector3.ZERO
	_poner_cam(yaw_cam)


func _soltar() -> void:
	for a in ["mover_arriba", "mover_abajo", "mover_izquierda", "mover_derecha", "correr", "agachar", "saltar"]:
		Input.action_release(a)


func _pulsar_salto() -> void:
	for pulsada in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pulsada
		get_viewport().push_input(ev)


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 960:
		img.resize(960, int(float(img.get_height()) * 960.0 / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png(_salida + "/" + nombre + ".png")
	print("captura ", nombre, " ", img.get_size(), " estado=", _j.estado_mov, " anim=", _j._anim_actual)


func _en_zona_cultivo(x: float, z: float) -> bool:
	for zb in [Vector3(3.5, 3.5, 6.0), Vector3(1.5, -4.5, 4.0), Vector3(-10.5, -1.0, 4.0)]:
		if absf(x - zb.x) < zb.z and absf(z - zb.y) < zb.z:
			return true
	return false


func _buscar_claro() -> Vector3:
	for x in [0.5, -2.5, 1.5, -4.5, 3.0]:
		for z in [16.0, 19.0, 14.0, 22.0, 25.0, 11.0]:
			if _en_zona_cultivo(x, z):
				continue
			var libre := true
			var y0 := NAN
			for dz in [-4.0, -2.0, 0.0, 2.0, 4.0]:
				for dx in [-4.0, -2.0, 0.0, 2.0, 4.0]:
					var col: Dictionary = _mapa.call("_columna_suelo", x + dx, z + dz)
					var ys := float(col.get("suelo", NAN))
					var obs := float(col.get("obstaculo", 99.0))
					if is_nan(ys) or obs > 0.04:
						libre = false
						break
					if dx == 0.0 and dz == 0.0:
						y0 = ys
					elif absf(ys - y0) > 0.3:
						libre = false
						break
				if not libre:
					break
			if libre and not is_nan(y0):
				var p := Vector3(x, y0 + 0.02, z)
				if _mapa.call("punto_dentro", p):
					print("claro elegido: ", p)
					return p
	var sp := (_mapa.call("marcador", "Spawn_Protagonista") as Marker3D).global_position
	return sp + Vector3(0.0, 0.05, 0.0)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	var fase := OS.get_environment("MH_T05_FASE")
	if fase.is_empty():
		fase = "antes"
	_salida = ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T05-leo-animaciones/" + fase)
	DirAccess.make_dir_recursive_absolute(_salida)
	Juego.ruta_partida = "user://partida_capturas_t05.json"
	Juego.nueva_partida("Leo")
	Juego.minutos = 680   # ~11:20 mañana soleada
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 180:
		if bool(_mapa.get("vallas_listas")):
			break
		await get_tree().process_frame
	Interfaz.mostrar_hud(false)
	_base = _buscar_claro()

	# 1. De pie (quieto)
	_colocar(_base, 0.0)
	await _esperar(0.45)
	_poner_cam(0.0)
	await _fisica(2)
	await _foto("01_pie_frente")
	_poner_cam(PI * 0.5)
	await _fisica(2)
	await _foto("02_pie_perfil")

	# 2. Andando
	_colocar(_base, 0.0)
	await _fisica(4)
	Input.action_press("mover_abajo")
	await _esperar(0.38)
	_poner_cam(0.0)
	await _fisica(2)
	await _foto("03_andando_frente")
	_soltar()

	_colocar(_base, PI * 0.5)
	await _fisica(4)
	Input.action_press("mover_izquierda")
	await _esperar(0.38)
	_poner_cam(PI * 0.5)
	await _fisica(2)
	await _foto("04_andando_perfil")
	_soltar()

	# 3. Agachado quieto
	_colocar(_base, 0.0)
	await _fisica(4)
	Input.action_press("agachar")
	await _esperar(0.6)
	_poner_cam(0.0)
	await _fisica(2)
	await _foto("05_agachado_quieto_frente")
	_poner_cam(PI * 0.5)
	await _fisica(2)
	await _foto("06_agachado_quieto_perfil")
	_soltar()
	await _esperar(0.35)

	# 4. Agachado andando
	_colocar(_base, 0.0)
	await _fisica(4)
	Input.action_press("agachar")
	await _esperar(0.45)
	Input.action_press("mover_abajo")
	await _esperar(0.45)
	_poner_cam(0.0)
	await _fisica(2)
	await _foto("07_agachado_andando_frente")
	_soltar()
	await _esperar(0.35)

	_colocar(_base, PI * 0.5)
	await _fisica(4)
	Input.action_press("agachar")
	await _esperar(0.45)
	Input.action_press("mover_izquierda")
	await _esperar(0.45)
	_poner_cam(PI * 0.5)
	await _fisica(2)
	await _foto("08_agachado_andando_perfil")
	_soltar()
	await _esperar(0.4)

	# 5 & 6. Saltando y cayendo (frente)
	_colocar(_base, 0.0)
	await _fisica(10)
	_pulsar_salto()
	await _fisica(9) # ~0.15s: subiendo ("salto")
	_poner_cam(0.0)
	await _foto("09_saltando_frente")
	for _i in 40:
		if _j.estado_mov == "caida":
			break
		await get_tree().physics_frame
	await _fisica(6) # ~0.10s cayendo ("caida")
	_poner_cam(0.0)
	await _foto("11_cayendo_frente")
	await _esperar(0.6)

	# 5 & 6. Saltando y cayendo (perfil)
	_colocar(_base, PI * 0.5)
	await _fisica(10)
	_pulsar_salto()
	await _fisica(9)
	_poner_cam(PI * 0.5)
	await _foto("10_saltando_perfil")
	for _i in 40:
		if _j.estado_mov == "caida":
			break
		await get_tree().physics_frame
	await _fisica(6)
	_poner_cam(PI * 0.5)
	await _foto("12_cayendo_perfil")
	await _esperar(0.5)

	_soltar()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	print("CAPTURAS T05 OK (" + fase + ") en " + _salida)
	get_tree().quit(0)
