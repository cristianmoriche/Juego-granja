extends Node
## Capturas Vulkan H14: menu_ranuras.png y diario_logros.png

const CARPETA := "res://../gestion/noche-codex/capturas/H14-ranuras-logros-y-pulido/"
const Logros := preload("res://scripts/objetos/logros_h14.gd")

var _respaldo: Dictionary = {}


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 35.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("capturas_h14: timeout 35s")
		_restaurar_usuario()
		get_tree().quit(1))
	get_tree().root.add_child.call_deferred(tope)
	tope.ready.connect(tope.start)
	_ejecutar.call_deferred()


func _respaldar_usuario() -> void:
	_respaldo.clear()
	for slot in range(1, Juego.MAX_RANURAS + 1):
		for ruta: String in [
			Juego.ruta_ranura(slot),
			Juego.ruta_ranura(slot) + Juego.SUFIJO_COPIA,
			Juego.ruta_ranura(slot) + Juego.SUFIJO_TEMPORAL,
			Juego.ruta_miniatura_ranura(slot),
		]:
			if FileAccess.file_exists(ruta):
				_respaldo[ruta] = FileAccess.get_file_as_bytes(ruta)


func _restaurar_usuario() -> void:
	for slot in range(1, Juego.MAX_RANURAS + 1):
		Juego.borrar_ranura(slot)
	for ruta: String in _respaldo:
		var fw := FileAccess.open(ruta, FileAccess.WRITE)
		if fw != null:
			fw.store_buffer(_respaldo[ruta] as PackedByteArray)
			fw.close()


func _foto(nombre: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ruta := ProjectSettings.globalize_path(CARPETA + nombre + ".png")
	get_viewport().get_texture().get_image().save_png(ruta)
	print("Captura guardada: " + ruta)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA))
	_respaldar_usuario()
	for slot in range(1, Juego.MAX_RANURAS + 1):
		Juego.borrar_ranura(slot)

	# 1. Prepara una partida real con granja en ranura 1 para capturar miniatura real + logros parciales
	Juego.seleccionar_ranura_guardado(1)
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.estacion = 1
	Juego.dia = 14
	Juego.dinero = 2480
	Juego.deuda = 3200
	Juego.tiempo_jugado_seg = 9180.0
	Juego.banderas["mina_max_nivel"] = 12
	Juego.estadisticas["cosechas"] = 36
	Juego.estadisticas["platos_cocinados"] = 6
	Juego.anadir_objeto("arco_caza", 1)
	Juego.anadir_objeto("tarro_miel", 1)
	Juego.estadisticas["gemas_engastadas"] = 1
	Juego.registrar_jefe_derrotado("rata_reina")
	Juego.registrar_jefe_derrotado("sapo_gigante")
	for sp_id: String in ["trucha", "carpa", "perca", "salmon_sierra"]:
		Juego.registrar_captura_pesca({"id": sp_id, "cm": 44.5, "kg": 1.4}, "lago")
	Juego.ganar_xp_habilidad("agricultura", 720)
	Juego.evaluar_logros(false)

	Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	Juego.guardar(false)   # Guarda miniatura 256x144 real de granja en ranura 1
	for h in Interfaz._capa_flotante.get_children():
		h.queue_free()
	await get_tree().process_frame

	# 2. Captura diario_logros.png con la pestaña Logros abierta
	Interfaz.abrir_diario("logros")
	await _foto("diario_logros")
	Interfaz.cerrar_todo()

	# 3. Prepara ranura 2 en pueblo con miniatura real y deja ranura 3 vacía, vuelve al menú y captura menu_ranuras.png
	Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	while Escenas.en_transicion:
		await get_tree().process_frame
	for _f in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	Juego.seleccionar_ranura_guardado(2)
	Juego.nueva_partida("Clara")
	Juego.dia = 3
	Juego.estacion = 0
	Juego.dinero = 640
	Juego.tiempo_jugado_seg = 1620.0
	Juego.mapa_actual = "pueblo"
	Juego.guardar(false)
	Juego.seleccionar_ranura_guardado(1)

	await Escenas.ir_al_menu()
	await _foto("menu_ranuras")

	_restaurar_usuario()
	get_tree().quit(0)
