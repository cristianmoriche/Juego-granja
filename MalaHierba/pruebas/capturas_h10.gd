extends Node
## Capturas representativas de H10 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) horno_pueblo_arma_gemas.png (horno de fundición 3D junto a la herrería en pueblo + Leo empuñando espada engastada brillante)
## 2) panel_forja_gemas.png (PanelHerreria abierto en Engaste y temple con comparativa Antes -> Después)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H10-forja-y-gemas").simplify_path()
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
	Juego.minutos = 760
	Juego.dinero = 950

	await Escenas.ir_a_mapa("pueblo")
	await _esperar(8)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()

	Juego.anadir_objeto("espada_cuarzo", 1)
	Juego.anadir_objeto("rubi", 2)
	Juego.anadir_objeto("ambar_valle", 1)
	Juego.anadir_objeto("diamante", 1)
	Juego.anadir_objeto("cobre", 6)
	Juego.anadir_objeto("carbon", 2)
	Juego.anadir_objeto("lingote_hierro", 2)
	Juego.iniciar_fundicion("fundir_cobre", false)

	var idx_esp: int = _buscar_ranura("espada_cuarzo")
	if idx_esp >= 10:
		var tmp_slot: Dictionary = Juego.inventario[8]
		Juego.inventario[8] = Juego.inventario[idx_esp]
		Juego.inventario[idx_esp] = tmp_slot
		idx_esp = 8
	Juego.engastar_gema("inventario", idx_esp, "", "rubi")
	Juego.engastar_gema("inventario", idx_esp, "", "diamante")
	Juego.templar_con_lingote("inventario", idx_esp, "")
	Juego.elegir_ranura(idx_esp)

	var horno: Node3D = get_tree().get_first_node_in_group("mapa").find_child("HornoFundicionPueblo", true, false) as Node3D
	Ajustes.poner("vista", 1)
	await _esperar(10)
	if horno != null and j != null:
		j.global_position = horno.global_position + Vector3(-1.35, 0.05, 1.45)
		j.direccion = Vector3(-0.35, 0.0, 0.94).normalized()
		j.camara.yaw = 0.25
		j.camara.pitch = -0.16
	await _esperar(14)
	await _capturar("horno_pueblo_arma_gemas.png")

	# 2) Panel de engaste y temple abierto
	Interfaz.call("abrir_herreria", 1)
	await _esperar(6)
	await _capturar("panel_forja_gemas.png")
	var panel_h: Control = Interfaz.get("_herreria") as Control
	panel_h.call("cerrar")
	Ajustes.poner("vista", vista_orig)
	print("CAPTURAS H10 COMPLETAS")
	get_tree().quit(0)
