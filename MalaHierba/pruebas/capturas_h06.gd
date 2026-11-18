extends Node
## Captura visual representativa de H06 en Vulkan 1080p Alto (--audio-driver Dummy):
## panel_cocina, diario_habilidades y plato en la mano en primera persona junto a la hoguera.

var _sal := ""


func _ready() -> void:
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H06-cocina-y-habilidades").simplify_path()
	DirAccess.make_dir_recursive_absolute(_sal)
	_ejecutar.call_deferred()


func _esperar() -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _i in 6:
		await get_tree().physics_frame
	for _i in 4:
		await get_tree().process_frame


func _capturar(archivo: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_sal.path_join(archivo))
	print("CAPTURA ", archivo)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 760
	if Tutorial.has_method("cerrar_actual"):
		Tutorial.call("cerrar_actual")

	Juego.anadir_objeto("patata", 4)
	Juego.anadir_objeto("hierba_monte", 3)
	Juego.anadir_objeto("seta_silvestre", 4)
	Juego.anadir_objeto("ajo", 3)
	Juego.anadir_objeto("zanahoria", 2)
	Juego.subir_amistad("tomas", 45)
	Juego.ganar_xp_habilidad("combate", 80)
	Juego.ganar_xp_habilidad("agricultura", 55)
	Juego.ganar_xp_habilidad("mineria", 45)
	Juego.cocinar("salteado_setas", 1)
	Juego.cocinar("sopa_ajo", 1)
	Juego.comer("sopa_ajo")

	# 1) Interior de casa con PanelCocina abierto
	await Escenas.ir_a_mapa("casa_leo")
	await _esperar()
	Interfaz.abrir_cocina("Cocina de leña")
	await get_tree().process_frame
	await _capturar("panel_cocina.png")
	Interfaz.cerrar_todo()
	await get_tree().process_frame

	# 2) Diario pestaña Habilidades con bufos activos
	Interfaz.abrir_diario("habilidades")
	await get_tree().process_frame
	await _capturar("diario_habilidades.png")
	Interfaz.cerrar_todo()
	await get_tree().process_frame

	# 3) Robledal junto a la hoguera: plato cocinado en mano en primera persona + HUD bufo activo
	await Escenas.ir_a_mapa("robledal_niebla")
	await _esperar()
	var idx_plato := -1
	for i in Juego.HUECOS:
		if str(Juego.inventario[i].get("id", "")) == "salteado_setas":
			idx_plato = i
			break
	if idx_plato >= 10:
		Juego.mover_huecos(idx_plato, 9)
		idx_plato = 9
	if idx_plato >= 0:
		Juego.elegir_ranura(idx_plato)
	# Cerrar avisos acumulados para una captura limpia en primera persona
	var hud_n: Variant = Interfaz.get("_hud")
	if hud_n != null and (hud_n as Object).has_method("limpiar_avisos"):
		(hud_n as Object).call("limpiar_avisos")
	Tutorial.cerrar_actual()
	var j := Escenas.jugador()
	if j != null:
		# Colocar frente a la hoguera (-6, 10) desde (-6, 12.6) mirando al norte
		j.colocar(Vector3(-6.0, 0.45, 12.6), 0.0, 0.0)
		j.camara.primera_persona = true
		j.camara.fijar(Vector3(-6.0, 0.45, 12.6), 0.0)
		j._al_actualizar_vista()
		j._actualizar_objeto_en_mano()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capturar("plato_en_mano_1p.png")

	get_tree().quit(0)
