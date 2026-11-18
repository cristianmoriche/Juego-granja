extends Node
## Comprobaciones específicas para las 4 mejoras:
## 1) Menú debug oculto, 2) Árboles talables, 3) NPC rutas diarias + solo puesto de trabajo,
## 4) Mina deslizamiento/hitboxes rocas + bloqueo salida habitual y puerta oculta de jefe cada 5 plantas.

var _ok: int = 0
var _fallos: Array[String] = []


func _ready() -> void:
	var tope := Timer.new()
	tope.wait_time = 90.0
	tope.one_shot = true
	tope.timeout.connect(func() -> void:
		push_error("prueba_m3_cuatro_mejoras: timeout 90s")
		get_tree().quit(1))
	add_child(tope)
	tope.start()
	_ejecutar.call_deferred()


func _chk(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos.append(msg)
		print("  FALLO M3: ", msg)


func _frames(n: int = 4) -> void:
	for _i in n:
		await get_tree().process_frame


func _fisica(n: int = 4) -> void:
	for _i in n:
		await get_tree().physics_frame


func _ir(id_m: String, llegada: String = "Spawn_Protagonista") -> Node:
	await Escenas.ir_a_mapa(id_m, llegada)
	var m := Escenas.mapa_actual_nodo()
	for _i in 240:
		if not Escenas.en_transicion and m != null and str(m.get("id_mapa")) == id_m and bool(m.get("esta_listo")):
			break
		await get_tree().process_frame
		m = Escenas.mapa_actual_nodo()
	await _frames(4)
	await _fisica(4)
	return m


func _ejecutar() -> void:
	await _frames(2)
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_m3_mejoras.json"
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 600

	await _probar_arboles_talables()
	await _probar_menu_debug_oculto()
	await _probar_npcs_pueblo()
	await _probar_mina_deslizamiento_y_jefe()

	Juego.limpiar_debug()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	if _fallos.is_empty():
		print("PRUEBA M3 CUATRO MEJORAS OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA M3 CUATRO MEJORAS FALLO (%d fallos, %d ok): %s" % [_fallos.size(), _ok, "; ".join(PackedStringArray(_fallos))])
		get_tree().quit(1)


func _probar_menu_debug_oculto() -> void:
	print("[1] Menú debug oculto")
	var m := await _ir("granja")
	var dbg := Interfaz.debug_panel()
	_chk(dbg != null and not dbg.visible, "menú debug oculto inicialmente")

	var ev := InputEventKey.new()
	ev.keycode = KEY_F9
	ev.physical_keycode = KEY_F9
	ev.pressed = true
	get_viewport().push_input(ev)
	await _frames(2)
	_chk(dbg.visible and Interfaz.ocupada(), "F9 abre el menú debug oculto en partida")

	var ruta_cap := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capturar="):
			ruta_cap = arg.trim_prefix("--capturar=")
	if not ruta_cap.is_empty() and DisplayServer.get_name() != "headless":
		await _frames(3)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ruta_cap)

	# Cierra con F10 y vuelve a abrir con Ctrl+Shift+D incluso sobre pausa
	var ev10 := InputEventKey.new()
	ev10.keycode = KEY_F10
	ev10.physical_keycode = KEY_F10
	ev10.pressed = true
	get_viewport().push_input(ev10)
	await _frames(2)
	_chk(not dbg.visible, "F10 cierra el menú debug")

	Interfaz._pausa.abrir()
	await _frames(1)
	var ev_csd := InputEventKey.new()
	ev_csd.keycode = KEY_D
	ev_csd.physical_keycode = KEY_D
	ev_csd.ctrl_pressed = true
	ev_csd.shift_pressed = true
	ev_csd.pressed = true
	get_viewport().push_input(ev_csd)
	await _frames(2)
	_chk(dbg.visible and not Interfaz._pausa.visible, "Ctrl+Shift+D abre el menú debug incluso desde Pausa")

	# Tiempo pausa / reanudar
	Juego.pausar_tiempo(false)
	dbg.cerrar()
	await _frames(2)
	_chk(Juego.tiempo_corre(), "con debug cerrado y sin pausa externa, el tiempo corre")
	Juego.pausar_tiempo_debug(true)
	_chk(not Juego.tiempo_corre(), "debug puede pausar el tiempo")
	Juego.pausar_tiempo_debug(false)
	_chk(Juego.tiempo_corre(), "debug puede reanudar el tiempo")
	Juego.pausar_tiempo(true)

	# Dinero +/-
	var d0 := Juego.dinero
	Juego.ajustar_dinero_debug(1500)
	_chk(Juego.dinero == d0 + 1500, "debug añade dinero")
	Juego.ajustar_dinero_debug(-500)
	_chk(Juego.dinero == d0 + 1000, "debug quita dinero")
	Juego.ajustar_dinero_debug(-999999)
	_chk(Juego.dinero == 0, "debug no deja dinero negativo")

	# Energía ilimitada e inmortalidad
	Juego.energia = 20.0
	Juego.vida = 50.0
	dbg.poner_energia_infinita(true)
	_chk(is_equal_approx(Juego.energia, Juego.energia_max) and Juego.gastar_energia(30.0) and is_equal_approx(Juego.energia, Juego.energia_max), "energía ilimitada mantiene energía al máximo")
	dbg.poner_inmortal(true)
	_chk(is_equal_approx(Juego.vida, Juego.vida_max), "inmortalidad restaura vida al máximo")
	Juego.recibir_dano(45.0)
	var j := Escenas.jugador() as Jugador
	j.recibir_ataque(40.0, null, j.global_position + Vector3.FORWARD, false)
	_chk(is_equal_approx(Juego.vida, Juego.vida_max), "inmortalidad bloquea daño de Juego y Combate")
	dbg.poner_energia_infinita(false)
	dbg.poner_inmortal(false)

	# Hitboxes
	dbg.poner_hitboxes(true)
	await _frames(2)
	var nh := get_tree().get_nodes_in_group(PanelDebug.GRUPO_HITBOX).size()
	_chk(nh >= 10, "mostrar hitboxes genera visualizaciones reales (%d)" % nh)
	dbg.poner_hitboxes(false)
	await _frames(3)
	_chk(get_tree().get_nodes_in_group(PanelDebug.GRUPO_HITBOX).size() == 0, "ocultar hitboxes limpia todas las mallas")

	# Vuelo libre y viaje entre zonas / plantas de mina
	dbg.poner_vuelo(true)
	var y0 := j.global_position.y
	Input.action_press("saltar")
	await _fisica(20)
	Input.action_release("saltar")
	_chk(j.global_position.y > y0 + 1.5 and j.motion_mode == CharacterBody3D.MOTION_MODE_FLOATING, "vuelo sube libremente sin gravedad")
	dbg.poner_vuelo(false)

	dbg.ir_planta_mina(4)
	for _i in 240:
		var mm := Escenas.mapa_actual_nodo()
		if not Escenas.en_transicion and mm != null and str(mm.get("id_mapa")) == "mina_interior" and bool(mm.get("esta_listo")):
			break
		await get_tree().process_frame
	_chk(Juego.mapa_actual == "mina_interior" and int(Juego.banderas.get("nivel_mina", 0)) == 4, "debug viaja a la planta exacta de la mina (nv 4)")

	m = await _ir("pueblo")
	_chk(str(m.get("id_mapa")) == "pueblo", "vuelve de debug a pueblo sin error")


func _probar_arboles_talables() -> void:
	print("[2] Árboles talables")
	Juego.dinero = 500
	var m := await _ir("granja")
	var rec := m.get_node_or_null("Objetos/RecursosExteriores") as RecursosExteriores
	_chk(rec != null, "RecursosExteriores presente en granja")
	var arbs := rec.arboles_talables()
	var vistos_tam: Dictionary = {}
	for a: Dictionary in arbs:
		vistos_tam[str(a["tamano"])] = true
		var cf := a["col_forma"] as CollisionShape3D
		_chk(cf.shape is CylinderShape3D and (cf.shape as CylinderShape3D).height <= 3.0, "árbol %s más pequeño que los decorativos gigantes" % str(a["id"]))
		var copa := a["pivot"] as Node3D
		_chk(copa.find_child("MarcaTala", true, false) != null, "árbol %s tiene marca distintiva" % str(a["id"]))
	_chk(vistos_tam.size() == 3, "existen los 3 tamaños de árboles talables (%s)" % str(vistos_tam.keys()))

	var blanco: Dictionary = arbs[0]
	var id_b := str(blanco["id"])
	var pivot := blanco["pivot"] as Node3D
	var tocon := blanco["tocon"] as Node3D
	var mad0 := Juego.cantidad("madera")
	var req := int(blanco["golpes_max"])
	for _g in req:
		rec.usar("hacha", blanco["pos"] as Vector3, Escenas.jugador())
	_chk(bool(blanco["talado"]) and Juego.cantidad("madera") == mad0 + int(blanco["madera"]), "talar con hacha entrega madera")
	_chk(tocon.visible and not (blanco["punto"] as Interactuable).activo, "al caer muestra tocón y desactiva tala")
	# Esperar animación de caída (~0.7s)
	await get_tree().create_timer(0.85).timeout
	_chk(pivot.visible and rad_to_deg(pivot.rotation.x) >= 75.0, "animación de tala deja el árbol visible tumbado (%.1f°)" % rad_to_deg(pivot.rotation.x))

	# Recargar el mapa el mismo día y verificar persistencia visual en estado talado
	m = await _ir("bosque_norte")
	var rec_b := m.get_node_or_null("Objetos/RecursosExteriores") as RecursosExteriores
	_chk(rec_b != null and rec_b.arboles_talables().size() >= 6, "bosque_norte también tiene árboles talables")
	m = await _ir("granja")
	rec = m.get_node_or_null("Objetos/RecursosExteriores") as RecursosExteriores
	var encontrado := false
	for a2: Dictionary in rec.arboles_talables():
		if str(a2["id"]) == id_b:
			encontrado = true
			_chk(bool(a2["talado"]) and (a2["tocon"] as Node3D).visible and rad_to_deg((a2["pivot"] as Node3D).rotation.x) >= 75.0, "estado talado persiste visible al volver al mapa")
			break
	_chk(encontrado, "árbol talado localizado tras recargar granja")


func _probar_npcs_pueblo() -> void:
	print("[3] NPC pueblo: recorridos diarios y servicios en puesto")
	Juego.estacion = 0
	Juego.dia = 1
	Juego.minutos = 600
	var m := await _ir("pueblo")
	var vec := m.get_node("Objetos/Vecinos") as Vecinos
	var mateo_p := vec.npcs.get("mateo") as Npc
	var clara_p := vec.npcs.get("clara") as Npc
	var marisol := vec.npcs.get("marisol") as Npc
	_chk(marisol != null and marisol.ruta_diaria.size() >= 2, "vecino de pueblo tiene circuito diario (%d puntos)" % (marisol.ruta_diaria.size() if marisol else 0))
	var ruta_dia1 := marisol.ruta_diaria.duplicate()

	Juego.dia = 2
	vec.sincronizar(true)
	await _frames(2)
	var ruta_dia2 := marisol.ruta_diaria.duplicate()
	var cambia_ruta := ruta_dia1.size() != ruta_dia2.size()
	if not cambia_ruta:
		for i in ruta_dia1.size():
			if ruta_dia1[i].distance_to(ruta_dia2[i]) > 0.4:
				cambia_ruta = true
				break
	_chk(cambia_ruta, "los recorridos diarios del NPC cambian al pasar al día 2")

	# Fuera de su puesto de trabajo no se permiten compras/forja/deuda
	_chk(mateo_p != null and not mateo_p.en_lugar_trabajo(), "Mateo en la plaza no está en su puesto")
	_chk(clara_p != null and not clara_p.en_lugar_trabajo(), "Clara en la plaza no está en su puesto")
	_chk(not Conversacion.acciones_de(mateo_p).has("tienda"), "Mateo en la plaza no ofrece «tienda»")
	_chk(not Conversacion.acciones_de(clara_p).has("herreria"), "Clara en la plaza no ofrece «herreria»")
	Conversacion.ejecutar("tienda", mateo_p)
	_chk(not Interfaz._tienda.visible, "ejecutar «tienda» fuera de puesto no abre la tienda")
	Interfaz.cerrar_todo()

	# Dentro del puesto y horario de trabajo sí habilitan compras y servicios
	Juego.minutos = 660
	await _ir("tienda", "Entrada")
	vec = Escenas.mapa_actual_nodo().get_node("Objetos/Vecinos") as Vecinos
	var mateo_t := vec.npcs.get("mateo") as Npc
	_chk(mateo_t != null and mateo_t.en_lugar_trabajo() and Conversacion.acciones_de(mateo_t).has("tienda"), "Mateo en tienda (11:00) habilita compras")

	await _ir("herreria", "Entrada")
	vec = Escenas.mapa_actual_nodo().get_node("Objetos/Vecinos") as Vecinos
	var clara_h := vec.npcs.get("clara") as Npc
	_chk(clara_h != null and clara_h.en_lugar_trabajo() and Conversacion.acciones_de(clara_h).has("herreria"), "Clara en herrería (11:00) habilita mejoras")

	Juego.minutos = 840
	await _ir("taberna", "Entrada")
	vec = Escenas.mapa_actual_nodo().get_node("Objetos/Vecinos") as Vecinos
	var ramon_tab := vec.npcs.get("ramon") as Npc
	_chk(ramon_tab != null and ramon_tab.en_lugar_trabajo() and Conversacion.acciones_de(ramon_tab).has("comer"), "Ramón en taberna (14:00) habilita comer y llevar")

	Juego.minutos = 600
	await _ir("casa_alcalde", "Entrada")
	vec = Escenas.mapa_actual_nodo().get_node("Objetos/Vecinos") as Vecinos
	var anselmo := vec.npcs.get("anselmo") as Npc
	_chk(anselmo != null and anselmo.en_lugar_trabajo() and Conversacion.acciones_de(anselmo).has("deuda"), "Anselmo en ayuntamiento (10:00) habilita deuda")


func _probar_mina_deslizamiento_y_jefe() -> void:
	print("[4] Mina: deslizamiento, hitboxes minerales y jefe cada 5 plantas")
	Juego.banderas["nivel_mina"] = 5
	var m5 := await _ir("mina_interior", "Llegada_Interior")
	var j := Escenas.jugador() as Jugador
	var nm := m5.get_node("Objetos/NivelMina") as NivelMina
	var rocas := m5.get_node("Objetos/RocasMina") as RocasMina
	var bajada := m5.get_node("Objetos/BajadaMina") as BajadaMina

	_chk(not j.floor_block_on_wall and is_zero_approx(j.wall_min_slide_angle), "Jugador en mina configura colisiones por deslizamiento")
	_chk(rocas.rocas.size() >= 20, "rocas construidas en nivel 5 (%d)" % rocas.rocas.size())
	var r0 := rocas.rocas[0]
	var cs_roca := r0.cuerpo.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	_chk(cs_roca.shape is CylinderShape3D and (cs_roca.shape as CylinderShape3D).radius <= 0.43, "roca usa hitbox cilíndrica ceñida (r=%.2f)" % (cs_roca.shape as CylinderShape3D).radius)

	# Empujar en diagonal contra una roca mineral despejada: debe deslizar lateralmente sin bloquearse
	var r_libre: RocasMina.Roca = null
	for cand_r: RocasMina.Roca in rocas.rocas:
		var cerca_ok := true
		for otro: RocasMina.Roca in rocas.rocas:
			if otro != cand_r and cand_r.pos.distance_to(otro.pos) < 1.8:
				cerca_ok = false
				break
		if cerca_ok:
			r_libre = cand_r
			break
	if r_libre != null:
		var p_ini := r_libre.pos + Vector3(0.22, 0.05, r_libre.radio + 0.50)
		j.colocar(p_ini, 0.0, 0.0)
		j._pos_segura = p_ini
		await _fisica(4)
		Input.action_press("mover_arriba")
		await _fisica(80)
		Input.action_release("mover_arriba")
		var rodeo := j.global_position.z < r_libre.pos.z
		_chk(absf(j.global_position.x - p_ini.x) > 0.15 and rodeo and j.atascos_resueltos == 0, "Leo desliza rodeando el mineral hasta superarlo (dx=%.2f, z=%.2f < %.2f)" % [absf(j.global_position.x - p_ini.x), j.global_position.z, r_libre.pos.z])

	# Jefe cada 5 plantas bloquea salida habitual mientras viva
	_chk(nm.salida_habitual_bloqueada() and nm.jefe_vivo, "planta 5 con jefe vivo bloquea salida habitual")
	_chk(not nm.puerta_oculta_abierta() and nm.nodo_puerta_oculta != null, "puerta oculta presente y cerrada mientras viva el jefe")
	bajada.preguntar()
	await _frames(2)
	_chk(Interfaz._dialogo.visible and int(Juego.banderas.get("nivel_mina", 0)) == 5, "intentar salida habitual con jefe vivo avisa bloqueo y no baja")
	Interfaz.cerrar_todo()

	var jefe: Enemigo = null
	for en: Node in get_tree().get_nodes_in_group("enemigos"):
		if en is Enemigo and (en as Enemigo).es_jefe:
			jefe = en as Enemigo
			break
	_chk(jefe != null, "jefe presente en planta 5")
	if jefe != null:
		jefe.recibir_dano(9999.0)
		await _frames(4)
		_chk(not nm.salida_habitual_bloqueada() and not nm.jefe_vivo, "al derrotar al jefe se desbloquea la salida habitual")
		_chk(nm.puerta_oculta_abierta(), "al derrotar al jefe se abre la puerta oculta")
		var p_oc := nm.nodo_puerta_oculta.find_child("InteractuablePuertaOculta", true, false) as Interactuable
		_chk(p_oc != null and p_oc.activo, "interactuable de la puerta oculta queda activo")
		if p_oc != null:
			p_oc.interactuar(j)
			for _i in 240:
				if not Escenas.en_transicion and int(Juego.banderas.get("nivel_mina", 0)) == 6:
					break
				await get_tree().process_frame
			_chk(int(Juego.banderas.get("nivel_mina", 0)) == 6, "entrar por la puerta oculta baja a la planta 6")
