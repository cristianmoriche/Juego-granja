extends Node
## Captura representativa en primera persona de H12 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) granja_gallinero_colmenas_1p.png (1P frente al gallinero reparado de Claude con huevos en nidales y colmenas al lado)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H12-granja-ganadera").simplify_path()
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


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	var vista_orig: int = int(Ajustes.valores.vista)
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 660
	Juego.dinero = 900
	Juego.anadir_objeto("madera", 25)
	Juego.anadir_objeto("ahumador", 1)
	Juego.reparar_gallinero()
	Juego.comprar_gallina()
	Juego.alimentar_gallinero()
	Juego.dar_agua_gallinero()
	Juego.desbloquear_colmena(1)
	Juego.estacion = 0
	for _i in 3:
		Juego.terminar_dia(false, false)
	Juego.minutos = 660

	await Escenas.ir_a_mapa("granja")
	await _esperar(10)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	Ajustes.poner("vista", 0)
	await _esperar(10)

	var gg := get_tree().get_first_node_in_group("mapa").find_child("GranjaGanadera", true, false) as GranjaGanadera
	if gg != null and j != null:
		j.global_position = gg.global_position + Vector3(2.4, 0.1, 4.6)
		j.camara.yaw = atan2(-(gg.global_position.x + 1.4 - j.global_position.x), -(gg.global_position.z - j.global_position.z))
		j.camara.pitch = 0.06
	await _esperar(14)
	await _capturar("granja_gallinero_colmenas_1p.png")

	Ajustes.poner("vista", vista_orig)
	print("CAPTURAS H12 COMPLETAS")
	get_tree().quit(0)
