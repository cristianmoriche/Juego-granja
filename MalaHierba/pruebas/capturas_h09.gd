extends Node
## Capturas representativas de H09 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) arco_1p_apuntando.png (1P tensando arco de caza frente al puente / bosque con visor de tension HUD)
## 2) arco_3p_carcaj_flecha.png (3P mostrando arco cristal, carcaj en espalda y flecha de fuego clavada)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H09-combate-distancia").simplify_path()
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
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 760

	await Escenas.ir_a_mapa("robledal_niebla")
	await _esperar(8)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()

	Juego.anadir_objeto("arco_caza", 1)
	Juego.anadir_objeto("arco_cristal", 1)
	Juego.anadir_objeto("carcaj_cuero", 1)
	Juego.anadir_objeto("flecha_fuego", 12)
	var idx_carcaj: int = _buscar_ranura("carcaj_cuero")
	if idx_carcaj >= 0:
		Juego.equipar(idx_carcaj)

	# 1) 1P tensando arco de caza y visor HUD
	var vista_orig: int = int(Ajustes.valores.vista)
	var idx_caza: int = _buscar_ranura("arco_caza")
	Juego.elegir_ranura(idx_caza)
	Ajustes.poner("vista", 0)
	await _esperar(38)
	j.combate.preparar_ataque("arco_caza", null)
	j.combate.actualizar(0.62, true, true)
	j._actualizar_arco_primera(0.5)
	await _capturar("arco_1p_apuntando.png")
	j.combate.soltar_ataque()
	await _esperar(10)

	# 2) 3P con arco de cristal, carcaj en la espalda y flecha de fuego clavada cerca
	var idx_cristal: int = _buscar_ranura("arco_cristal")
	Juego.elegir_ranura(idx_cristal)
	Ajustes.poner("vista", 1)
	await _esperar(38)
	j.camara.yaw = 2.55
	j.camara.pitch = -0.16
	j.direccion = Vector3(-0.35, 0.0, -0.93).normalized()
	var f_demo := Flecha.new()
	j.get_parent().add_child(f_demo)
	var punto_clavo := j.global_position + Vector3(0.9, 0.45, -1.2)
	f_demo.configurar(punto_clavo - Vector3(-0.4, -0.3, -0.85), Vector3(-0.4, -0.3, -0.85) * 28.0, "flecha_fuego", 24.0, [j.get_rid()])
	f_demo._clavar_en(j.get_parent(), punto_clavo)
	await _esperar(8)
	await _capturar("arco_3p_carcaj_flecha.png")
	Ajustes.poner("vista", vista_orig)

	print("CAPTURAS H09 COMPLETAS")
	get_tree().quit(0)
