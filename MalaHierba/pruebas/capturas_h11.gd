extends Node
## Capturas representativas de H11 en Vulkan 1080p Alto (--audio-driver Dummy):
## 1) pesca_lucha_lago.png (Leo luchando con pez en costa_lago: flotador, onda, sedal 3D e interfaz de tension/cansancio)
## 2) diario_album_pesca.png (PanelDiario abierto en la pestana Album de pesca con especies descubiertas y records)

var _sal := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sal = ProjectSettings.globalize_path("res://").path_join("../gestion/noche-codex/capturas/H11-pesca-avanzada").simplify_path()
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
	Juego.minutos = 920

	Juego.anadir_objeto("cana", 1)
	Juego.anadir_objeto("cebo_mosca", 4)
	Juego.elegir_cebo("cebo_mosca")
	Juego.registrar_captura_pesca({"id": "trucha", "cm": 37.5, "kg": 1.18, "rareza": "Común"}, "bosque_norte")
	Juego.registrar_captura_pesca({"id": "esturion", "cm": 124.0, "kg": 13.4, "rareza": "Trofeo"}, "costa_lago")
	Juego.registrar_captura_pesca({"id": "pez_ciego", "cm": 24.8, "kg": 0.56, "rareza": "Trofeo"}, "mina_interior")

	await Escenas.ir_a_mapa("costa_lago")
	await _esperar(8)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	var idx_cana := _buscar_ranura("cana")
	if idx_cana >= 0 and idx_cana < 10:
		Juego.elegir_ranura(idx_cana)
	Ajustes.poner("vista", 1)
	await _esperar(10)

	var zp := get_tree().get_first_node_in_group("zona_pesca") as ZonaPesca
	if zp != null and j != null:
		j.global_position = zp.global_position + Vector3(-2.6, 0.25, 2.6)
		j.direccion = (zp.global_position - j.global_position).slide(Vector3.UP).normalized()
		j.camara.yaw = atan2(-j.direccion.x, -j.direccion.z)
		j.camara.pitch = -0.22
		await _esperar(8)
		zp.usar("cana", zp.global_position + Vector3(0.4, 0.0, -0.4), j)
		var pp := Interfaz.get("_pesca") as PanelPesca
		if pp != null:
			var est := pp.estado_lucha()
			est["tirando"] = true
			est["tension"] = 0.68
			est["cansancio"] = 0.45
		await _esperar(8)
	await _capturar("pesca_lucha_lago.png")

	var pp2 := Interfaz.get("_pesca") as PanelPesca
	if pp2 != null:
		pp2.cancelar()
	Interfaz.abrir_diario("pesca")
	await _esperar(6)
	await _capturar("diario_album_pesca.png")
	Interfaz._diario.cerrar()
	Ajustes.poner("vista", vista_orig)
	print("CAPTURAS H11 COMPLETAS")
	get_tree().quit(0)
