extends Node
## Capturas representativas de H07 tomadas con el propio Modo Foto en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) panel_modo_foto.png (UI abierta en granja)
## 2) foto_sierra_atardecer.png (con el capturador de ModoFoto, filtro cálido y Leo en primer plano)
## 3) foto_ruinas_dof.png (con el capturador de ModoFoto, DoF en arcos de piedra y Leo oculto)
## 4) foto_bosque_noche_farol.png (22:00 noche con farol_mano iluminando el puente y luz con sombra)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H07-modo-foto-y-detalles").simplify_path()
	DirAccess.make_dir_recursive_absolute(_sal)
	_ejecutar.call_deferred()


func _esperar() -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _i in 6:
		await get_tree().physics_frame
	for _i in 4:
		await get_tree().process_frame


func _capturar_crudo(archivo: String) -> void:
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
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 760
	var mf := Interfaz.get("_modo_foto") as ModoFoto
	mf.ruta_capturas_personalizada = _sal

	# 1) Sierra del Mirador tomada con Modo Foto + filtro atardecer
	await Escenas.ir_a_mapa("sierra_mirador")
	await _esperar()
	var j := Escenas.jugador()
	Tutorial.cerrar_actual()
	Interfaz.abrir_modo_foto()
	await get_tree().process_frame
	var cf: Camera3D = mf.camara_foto()
	if cf != null and j != null:
		cf.global_position = j.global_position + Vector3(2.8, 2.2, 4.2)
		cf.look_at(j.global_position + Vector3(0.0, 1.0, -4.0))
	mf.poner_fov(58.0)
	mf.poner_filtro(1)
	mf.poner_inclinacion(4.0)
	await _capturar_crudo("panel_modo_foto.png")
	await mf.capturar_foto("foto_sierra_atardecer.png")
	mf.cerrar_panel()
	await get_tree().process_frame

	# 2) Ruinas del Molino Viejo tomadas con Modo Foto (DoF + ocultar Leo)
	await Escenas.ir_a_mapa("ruinas_valle")
	await _esperar()
	j = Escenas.jugador()
	if j != null:
		j.colocar(Vector3(0.0, 0.45, -2.0), 0.0, 0.0)
	Tutorial.cerrar_actual()
	Interfaz.abrir_modo_foto()
	await get_tree().process_frame
	cf = mf.camara_foto()
	if cf != null:
		cf.global_position = Vector3(-4.5, 2.2, -3.5)
		cf.look_at(Vector3(0.0, 1.8, -10.5))
	mf.poner_fov(46.0)
	mf.poner_dof(true, 8.5, 0.16)
	mf.poner_filtro(2)
	mf.poner_ocultar_leo(true)
	await mf.capturar_foto("foto_ruinas_dof.png")
	mf.cerrar_panel()
	await get_tree().process_frame

	# 3) Bosque de noche (22:00) con farol de hierro equipado en 1a persona
	Juego.anadir_objeto("farol_mano", 1)
	for i in Juego.HUECOS:
		if str(Juego.inventario[i].get("id", "")) == "farol_mano":
			Juego.equipar(i)
			break
	Juego.minutos = 1320
	await Escenas.ir_a_mapa("bosque_norte")
	await _esperar()
	j = Escenas.jugador()
	if j != null:
		j.colocar(Vector3(0.0, 0.25, 10.0), 0.0, 0.0)
		j.camara.primera_persona = true
		j.camara.fijar(Vector3(0.0, 0.25, 10.0), 0.0)
		j._al_actualizar_vista()
		j.call("_actualizar_estado_luz")
	Tutorial.cerrar_actual()
	await _capturar_crudo("foto_bosque_noche_farol.png")

	get_tree().quit(0)
