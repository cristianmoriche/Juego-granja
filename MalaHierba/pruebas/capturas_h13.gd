extends Node
## Captura nocturna en primera persona de H13 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) campamento_noche_1p.png (21:40 noche en Robledal de la Niebla: tienda de lona, saco y hoguera con sombras en 1P + farol)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H13-campamento-y-eventos-nocturnos").simplify_path()
	DirAccess.make_dir_recursive_absolute(_sal)
	_ejecutar.call_deferred()


func _esperar(frames: int = 6) -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _i in frames:
		await get_tree().physics_frame
	for _i in 4:
		await get_tree().process_frame


func _capturar(archivo: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_sal.path_join(archivo))
	print("CAPTURA ", archivo)


func _buscar_ranura(id: String) -> int:
	for i in Juego.inventario.size():
		if not Juego.inventario[i].is_empty() and str(Juego.inventario[i].get("id", "")) == id:
			return i
	return -1


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	var vista_orig: int = int(Ajustes.valores.vista)
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 1300  # 21:40 noche

	Juego.anadir_objeto("kit_campamento", 1)
	Juego.anadir_objeto("farol_mano", 1)
	var idx_f := _buscar_ranura("farol_mano")
	if idx_f >= 0:
		Juego.equipar(idx_f)

	await Escenas.ir_a_mapa("robledal_niebla")
	await _esperar(10)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	Ajustes.poner("vista", 0)
	await _esperar(10)

	if j != null:
		j.camara.yaw = 0.0
		j.camara.pitch = 0.14
		RecursosExteriores.montar_campamento_jugador(j)
		await _esperar(6)
		j.global_position += Vector3(1.15, 0.0, 0.95)
		j.camara.yaw = 0.55
		j.camara.pitch = 0.22
	await _esperar(14)
	await _capturar("campamento_noche_1p.png")

	Ajustes.poner("vista", vista_orig)
	print("CAPTURAS H13 COMPLETAS")
	get_tree().quit(0)
