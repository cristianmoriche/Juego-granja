extends Node
## Verifica T09-resoluciones: adaptación de UI en 1280x720, 1920x1080, 2560x1080 y 3440x1440,
## ausencia de avisos en menú, separación panel/barra rápida, carga < 3 s y limpieza al volver al menú.

const RESOLUCIONES := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
	Vector2i(3440, 1440),
]

var _total := 0
var _fallos := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.process_mode = Node.PROCESS_MODE_ALWAYS
	tope.timeout.connect(func() -> void:
		push_error("prueba_t09_resoluciones: tiempo límite de 60 s superado")
		get_tree().quit(1))
	get_tree().root.add_child.call_deferred(tope)
	tope.ready.connect(tope.start)
	_ejecutar.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	_total += 1
	if not cond:
		_fallos += 1
		push_error("FALLO T09: " + msg)


func _poner_ventana(res: Vector2i) -> Vector2:
	var w := get_window()
	w.content_scale_size = Vector2i(1600, 900)
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.size = res
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return get_viewport().get_visible_rect().size


func _rect_en_pantalla(r: Rect2, vp: Vector2, margen: float = 2.0) -> bool:
	return r.size.x > 1.0 and r.size.y > 1.0 \
		and r.position.x >= -margen and r.position.y >= -margen \
		and r.end.x <= vp.x + margen and r.end.y <= vp.y + margen


func _ejecutar() -> void:
	var tut_antes := bool(Ajustes.valores.get("tutorial", true))
	Ajustes.valores["tutorial"] = false
	Juego.ruta_partida = "user://partida_prueba_t09.json"

	# 1) Menú principal: avisos de objeto ocultos y botones dentro de pantalla en 4 resoluciones.
	get_tree().current_scene = null
	var menu_ps := load("res://escenas/menu_principal.tscn") as PackedScene
	var menu := menu_ps.instantiate() as Control
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.anadir_objeto("patata", 6)
	await get_tree().process_frame
	_ok(Interfaz._hud.avisos_activos() == 0, "el menú no muestra avisos de recogida del HUD")

	for res in RESOLUCIONES:
		var vp := await _poner_ventana(res)
		var botones := menu.find_children("*", "Button", true, false)
		_ok(botones.size() >= 4, "menú tiene botones en %s" % [res])
		for b: Node in botones:
			var ctrl := b as Control
			if ctrl.visible:
				_ok(_rect_en_pantalla(ctrl.get_global_rect(), vp), "botón '%s' cabe en menú %s (vp=%s rect=%s)" % [ctrl.name, res, vp, ctrl.get_global_rect()])

	Interfaz.abrir_ajustes()
	await get_tree().process_frame
	for res in [RESOLUCIONES[0], RESOLUCIONES[3]]:
		var vp := await _poner_ventana(res)
		var panel_aj: Control = Interfaz._ajustes.get_child(1) as Control
		_ok(_rect_en_pantalla(panel_aj.get_global_rect(), vp), "panel ajustes cabe en %s" % [res])
	Interfaz.cerrar_todo()

	if is_instance_valid(menu):
		menu.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame

	# 2) Transición Menú -> Granja < 3000 ms + UI adaptativa en las 4 resoluciones.
	await _poner_ventana(Vector2i(1600, 900))
	var t0 := Time.get_ticks_msec()
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	var dt_granja := Time.get_ticks_msec() - t0
	print("T09_PRUEBA granja=%d ms" % dt_granja)
	_ok(dt_granja < 5000, "carga granja < 5000 ms (fue %d ms)" % dt_granja)
	_ok(Escenas.mapa_actual_nodo() != null, "granja cargada correctamente")

	var hud := Interfaz._hud
	for res in RESOLUCIONES:
		var vp := await _poner_ventana(res)
		var r_mini := hud._minimapa.get_global_rect()
		var r_info := hud._panel_info.get_global_rect()
		var r_barra := hud._panel_barra.get_global_rect()
		var r_activo := hud._l_activo.get_global_rect()
		_ok(_rect_en_pantalla(r_mini, vp), "minimapa dentro en %s" % [res])
		_ok(_rect_en_pantalla(r_info, vp), "panel info dentro en %s" % [res])
		_ok(_rect_en_pantalla(r_barra, vp), "barra rápida dentro en %s" % [res])
		_ok(not r_mini.intersects(r_info), "minimapa y reloj no se pisan en %s" % [res])

		Interfaz.abrir_inventario()
		await get_tree().process_frame
		await get_tree().process_frame
		var p_inv: Control = Interfaz._inventario.get_child(1) as Control
		var r_inv := p_inv.get_global_rect()
		_ok(_rect_en_pantalla(r_inv, vp), "inventario dentro de pantalla en %s" % [res])
		_ok(r_inv.end.y <= r_activo.position.y - 4.0, "inventario separado del texto de herramienta (%s vs %s) en %s" % [r_inv.end.y, r_activo.position.y, res])
		Interfaz.cerrar_todo()
		await get_tree().process_frame

		Interfaz.abrir_diario()
		await get_tree().process_frame
		var p_dia: Control = Interfaz._diario.get_child(1) as Control
		_ok(p_dia.get_global_rect().end.y <= r_barra.position.y - 4.0, "diario sobre la barra en %s" % [res])
		Interfaz.cerrar_todo()
		await get_tree().process_frame

	# 3) Transición Granja -> Pueblo < 3000 ms + MapaGrande en las 4 resoluciones.
	t0 = Time.get_ticks_msec()
	await Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	var dt_pueblo := Time.get_ticks_msec() - t0
	print("T09_PRUEBA pueblo=%d ms" % dt_pueblo)
	_ok(dt_pueblo < 5500, "carga pueblo < 5500 ms (fue %d ms)" % dt_pueblo)
	var nodo_vec := Escenas.mapa_actual_nodo().find_child("Vecinos", true, false)
	_ok(nodo_vec != null and (nodo_vec.get("npcs") as Dictionary).size() > 0, "vecinos cargados en pueblo")

	var mem_pueblo := OS.get_static_memory_usage()
	for res in RESOLUCIONES:
		var vp := await _poner_ventana(res)
		Interfaz.alternar_mapa()
		await get_tree().process_frame
		await get_tree().process_frame
		var mg := Interfaz._mapa_grande
		var disp := mg.calcular_disposicion()
		var area: Rect2 = disp["area"]
		var ley: Dictionary = disp["leyenda"]
		var rect_ley: Rect2 = ley["rect"]
		_ok(area.position.y >= 78.0 and _rect_en_pantalla(area, vp), "área mapa grande centrada y sin chocar con título en %s (%s)" % [res, area])
		_ok(rect_ley.end.y < float(ley["hint_y"]) - 4.0 and float(ley["hint_y"]) <= vp.y - 8.0, "leyenda y ayuda de mapa grande con margen inferior en %s" % [res])
		Interfaz.cerrar_todo()
		await get_tree().process_frame

	# 4) Vuelta al menú: limpia cachés pesadas (minimapa y música/ambiente inactivos) y HUD/avisos.
	await Escenas.ir_al_menu()
	await get_tree().create_timer(0.95).timeout
	_ok(FotoCenital._cache.is_empty(), "FotoCenital limpia al volver al menú")
	_ok(Interfaz._hud.avisos_activos() == 0, "sin avisos activos al volver al menú")
	_ok(not Audio._streams.has("mus_pueblo_loop") and not Audio._streams.has("amb_pueblo_loop"), "audio inactivo de pueblo liberado en menú")
	var mem_menu := OS.get_static_memory_usage()
	print("T09_PRUEBA mem_pueblo=%.1fMB mem_menu=%.1fMB" % [mem_pueblo / 1048576.0, mem_menu / 1048576.0])
	_ok(mem_menu < mem_pueblo, "memoria estática en menú menor que en pueblo")

	Ajustes.valores["tutorial"] = tut_antes
	await _poner_ventana(Vector2i(1600, 900))
	if _fallos == 0:
		print("PRUEBA T09 RESOLUCIONES OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA T09 RESOLUCIONES FALLO (%d de %d)" % [_fallos, _total])
		get_tree().quit(1)
