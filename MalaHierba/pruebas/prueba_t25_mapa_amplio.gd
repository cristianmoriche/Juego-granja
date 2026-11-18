extends Node
## Prueba integral de T25-mapa-amplio: nuevas zonas bosque_norte y costa_lago, conexiones bidireccionales,
## postes de cruce, vegetación LOD1 con texturas, mapa grande, recogida de caña y pesca.
## Tope interno obligatorio de 60 s.

var _fallos: Array[String] = []
var _total: int = 0
var _j: Jugador = null
var _mapa: Mapa = null


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.timeout.connect(func() -> void:
		push_error("prueba_t25_mapa_amplio: tiempo máximo de 60 s superado")
		get_tree().quit(1)
	)
	add_child(tope)
	tope.start()
	_ejecutar.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	_total += 1
	if not cond:
		_fallos.append(msg)
		print("  FALLO: ", msg)


func _esperar_frames(n: int = 4) -> void:
	for _i in n:
		await get_tree().process_frame


func _esperar_mapa(id_esperado: String) -> void:
	var mm: Minimapa = Interfaz.minimapa()
	for _i in 600:
		var m := Escenas.mapa_actual_nodo() as Mapa
		if not Escenas.en_transicion and m != null and m.id_mapa == id_esperado and m.esta_listo and m.vallas_listas and mm.id_mapa == id_esperado and mm.lista():
			_mapa = m
			_j = Escenas.jugador() as Jugador
			await _esperar_frames(4)
			return
		await get_tree().process_frame
	_mapa = Escenas.mapa_actual_nodo() as Mapa
	_j = Escenas.jugador() as Jugador


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z) as Dictionary
	return float(col.get("suelo", NAN))


func _superficie_alta(x: float, z: float) -> float:
	var espacio := _mapa.get_world_3d().direct_space_state
	var hit := espacio.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 25.0, z), Vector3(x, -10.0, z), 1))
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _poner_leo(pos: Vector3, yaw: float = 0.0) -> void:
	_j.colocar(pos, 0.0, yaw)
	_j._pos_segura = pos
	_j.direccion = Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	_j._actualizar_interactuable()


func _entrar_en_salida(destino: String) -> bool:
	for n: Node in get_tree().get_nodes_in_group("salida"):
		if str(n.get("destino")) == destino:
			n.set("_armada_ms", 0)
			n.set("_bloqueada", false)
			n.set("_activa", true)
			n.call("_al_entrar", _j)
			await _esperar_mapa(destino)
			return _mapa != null and _mapa.id_mapa == destino
	return false


func _contar_peces() -> int:
	var total := 0
	for sp: String in PescaAvanzada.ESPECIES_ORDEN:
		total += Juego.cantidad(sp)
	return total


func _buscar_mallas_abeto_sin_tex(raiz: Node, out_info: Dictionary) -> void:
	if raiz is MultiMeshInstance3D:
		var mm := (raiz as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null and String(raiz.name).contains("fir_tree"):
			out_info["multis"] = int(out_info["multis"]) + 1
			for s in mm.mesh.get_surface_count():
				var mat := mm.mesh.surface_get_material(s) as BaseMaterial3D
				if mat != null and mat.albedo_texture == null:
					out_info["sin_tex"] = int(out_info["sin_tex"]) + 1
	elif raiz is MeshInstance3D:
		var mi := raiz as MeshInstance3D
		if mi.mesh != null and String(mi.name).contains("fir_tree"):
			out_info["multis"] = int(out_info["multis"]) + 1
			for s in mi.mesh.get_surface_count():
				var mat2 := (mi.get_active_material(s) as BaseMaterial3D)
				if mat2 != null and mat2.albedo_texture == null:
					out_info["sin_tex"] = int(out_info["sin_tex"]) + 1
	for h in raiz.get_children():
		_buscar_mallas_abeto_sin_tex(h, out_info)


func _verificar_mapa_nuevo(id: String, puestos_minimos: int) -> void:
	await Escenas.ir_a_mapa(id, "Spawn_Protagonista")
	await _esperar_mapa(id)
	_ok(_mapa != null and _mapa.id_mapa == id, "%s: mapa cargado" % id)
	_ok(_j != null and _j.dentro_de_limites(), "%s: Leo nace dentro de límites" % id)
	var carga_ms := int(_mapa.cargador.get("tiempo_carga_ms"))
	_ok(carga_ms > 0 and carga_ms < 3000, "%s: tiempo de carga %d ms < 3000 ms" % [id, carga_ms])
	_ok(_mapa.poligono_limites.size() >= 6, "%s: tiene polígono de límites" % id)
	_ok(_mapa.vallas != null and _mapa.numero_postes >= 5, "%s: tiene vallas visibles (%d postes)" % [id, _mapa.numero_postes])
	_ok(_mapa.puntos_interes.size() >= puestos_minimos, "%s: tiene postes de cruce (%d)" % [id, _mapa.puntos_interes.size()])
	for p: Interactuable in _mapa.puntos_interes:
		_ok(_mapa.punto_dentro(p.global_position, 0.4), "%s: poste %s dentro de límites" % [id, p.name])
	for tipo in ["spawn", "salida"]:
		for mk: Marker3D in _mapa.call("marcadores_de_tipo", tipo):
			_ok(_mapa.punto_dentro(mk.global_position, 0.4), "%s: marcador %s dentro de límites" % [id, mk.name])
	# Verificar vegetación sin decimar y con texturas
	var jinst := JSON.new()
	var inst_err := jinst.parse(FileAccess.get_file_as_string("res://assets/mapas/%s/instancias.json" % id))
	var hay_lod1 := false
	var hay_lod2 := false
	if inst_err == OK and jinst.data is Dictionary:
		for it: Dictionary in (jinst.data as Dictionary).get("instancias", []):
			var pr := str(it.get("proto", ""))
			if pr.begins_with("fir_tree_") and pr.ends_with("_LOD1"):
				hay_lod1 = true
			elif pr.begins_with("fir_tree_") and pr.ends_with("_LOD2"):
				hay_lod2 = true
	_ok(hay_lod1 and not hay_lod2, "%s: abetos usan LOD1 sin bajar a LOD2" % id)
	var vinfo := {"multis": 0, "sin_tex": 0}
	_buscar_mallas_abeto_sin_tex(_mapa.cargador, vinfo)
	_ok(int(vinfo["multis"]) >= 1 and int(vinfo["sin_tex"]) == 0, "%s: %d lotes de abetos con todas las texturas (sin_tex=%d)" % [id, int(vinfo["multis"]), int(vinfo["sin_tex"])])
	# Minimapa y mapa grande (T12)
	var mm := Interfaz.minimapa()
	_ok(mm.textura != null and mm.textura.get_width() >= 64, "%s: minimapa con foto cenital (%d px)" % [id, mm.textura.get_width() if mm.textura else 0])
	Interfaz.alternar_mapa()
	await _esperar_frames(3)
	var mg := Interfaz.get_node("Raiz/MapaGrande") as MapaGrande
	_ok(Interfaz.mapa_grande_abierto() and mg.area_foto().size.x > 200.0, "%s: MapaGrande abre foto válida" % id)
	Interfaz.cerrar_todo()
	await _esperar_frames(2)


func _ejecutar() -> void:
	await _esperar_frames(2)
	get_tree().current_scene = null
	Ajustes.valores["vista"] = 0
	Juego.ruta_partida = "user://partida_prueba_t25.json"
	Juego.nueva_partida("Leo")

	# 1. Iconos nuevos
	Datos.recargar_iconos()
	for id_ic in ["cana", "trucha", "carpa", "perca"]:
		_ok(Datos.tiene_icono(id_ic), "icono existente para «%s»" % id_ic)
		_ok(Datos.icono(id_ic).get_width() == 128, "icono «%s» de 128 px" % id_ic)

	# 2. Verificar mapa grande y calidad L1 de ambos nuevos mapas
	await _verificar_mapa_nuevo("bosque_norte", 2)
	_ok(_mapa.get_node_or_null("TopesRio") != null, "bosque_norte: topes de río creados")
	var y_puente := _superficie_alta(0.0, 4.0)
	_ok(not is_nan(y_puente) and y_puente > 0.35, "bosque_norte: puente pisable a %.2f m" % y_puente)
	var y_rampa := _superficie_alta(0.0, 9.5)
	_poner_leo(Vector3(0.0, y_rampa + 0.08, 9.5), 0.0)
	_j.camara.yaw = 0.0
	await _esperar_frames(4)
	Input.action_press("mover_arriba")
	Input.action_press("correr")
	for _i in 240:
		await get_tree().physics_frame
	Input.action_release("mover_arriba")
	Input.action_release("correr")
	print("   puente pos final Leo: ", _j.global_position, " muro=", _j.is_on_wall())
	_ok(_j.global_position.z < 0.5 and _j.dentro_de_limites(), "bosque_norte: Leo cruza sobre el puente (pos=%s)" % str(_j.global_position))

	await _verificar_mapa_nuevo("costa_lago", 2)
	var y_muelle := _superficie_alta(0.0, 18.0)
	_ok(not is_nan(y_muelle) and y_muelle > 0.4, "costa_lago: muelle pisable a %.2f m" % y_muelle)

	# 3. Recoger caña del muelle y pescar en muelle y en río
	var mk_cana := _mapa.call("marcador", "Cana_Muelle") as Marker3D
	_ok(mk_cana != null, "costa_lago: marcador Cana_Muelle presente")
	_poner_leo(mk_cana.global_position + Vector3(0.4, 0.05, 0.0), PI * 0.5)
	_j.camara.mirar_hacia(mk_cana.global_position + Vector3.UP * 0.7)
	await _esperar_frames(4)
	_j._actualizar_interactuable()
	_j._interactuar()
	Interfaz.cerrar_todo()
	_ok(Juego.cantidad("cana") >= 1 and bool(Juego.banderas.get("cana_muelle", false)), "costa_lago: Leo recoge la caña del muelle")

	# Equipar caña y pescar en el extremo del muelle
	var r_cana := -1
	for i in Juego.inventario.size():
		if not Juego.inventario[i].is_empty() and str(Juego.inventario[i]["id"]) == "cana":
			r_cana = i
			break
	if r_cana >= 10:
		Juego.mover_huecos(r_cana, 8)
		r_cana = 8
	_ok(r_cana >= 0 and r_cana < 10, "cana está en la barra/inventario")
	Juego.elegir_ranura(maxi(0, r_cana))
	await _esperar_frames(2)
	_poner_leo(Vector3(0.0, y_muelle + 0.05, 18.3), PI)
	await _esperar_frames(3)
	var e0 := Juego.energia
	var p0 := _contar_peces()
	_j._usar()
	await _completar_pesca_h11()
	Interfaz.cerrar_todo()
	_ok(_contar_peces() == p0 + 1, "costa_lago: usar la caña en el muelle pesca un pez")
	_ok(Juego.energia < e0, "costa_lago: pescar consume energía")

	# 4. Circuito real de portales bidireccionales por los 5 mapas exteriores
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	await _esperar_mapa("granja")
	_ok(_mapa.puntos_interes.any(func(x: Interactuable) -> bool: return x.name == "Punto_cartel_bosque_granja"), "granja: poste hacia Bosque del Norte")

	_ok(await _entrar_en_salida("bosque_norte") and _j.dentro_de_limites(), "portal granja -> bosque_norte")
	# Probar también pesca en tercera persona en el río del Bosque del Norte.
	Ajustes.valores["vista"] = 1
	Ajustes.cambiado.emit("vista")
	_poner_leo(Vector3(-2.8, _suelo(-2.8, 10.2) + 0.05, 10.2), 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _esperar_frames(3)
	var p1 := _contar_peces()
	_j._usar()
	await _completar_pesca_h11()
	Interfaz.cerrar_todo()
	_ok(_contar_peces() == p1 + 1, "bosque_norte: usar la caña junto al río pesca un pez")

	_ok(await _entrar_en_salida("pueblo") and _j.dentro_de_limites(), "portal bosque_norte -> pueblo")
	_ok(await _entrar_en_salida("costa_lago") and _j.dentro_de_limites(), "portal pueblo -> costa_lago")
	_ok(await _entrar_en_salida("bosque_norte") and _j.dentro_de_limites(), "portal costa_lago -> bosque_norte")
	_ok(await _entrar_en_salida("mina_exterior") and _j.dentro_de_limites(), "portal bosque_norte -> mina_exterior")
	_ok(await _entrar_en_salida("bosque_norte") and _j.dentro_de_limites(), "portal mina_exterior -> bosque_norte")
	_ok(await _entrar_en_salida("granja") and _j.dentro_de_limites(), "portal bosque_norte -> granja")

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()

	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)), "  (%d comprobaciones)" % _total)
		get_tree().quit(1)


func _completar_pesca_h11() -> void:
	await get_tree().process_frame
	var panel: PanelPesca = Interfaz.get("_pesca") as PanelPesca
	if panel == null or not bool(panel.get("_activo")):
		return
	for _i in 600:
		if not bool(panel.get("_activo")):
			break
		var est := panel.estado_lucha()
		var debe_tirar := not bool(est.get("tirando", false)) and float(est.get("tension", 0.0)) < 0.72
		if debe_tirar:
			Input.action_press("usar")
		else:
			Input.action_release("usar")
		panel._process(0.10)
		await get_tree().process_frame
	Input.action_release("usar")
	await get_tree().process_frame
