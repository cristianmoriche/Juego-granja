extends Node
## Prueba dedicada de H04-minas-grandes: escala, múltiples alturas/salas/ramales/puentes, biomas PBR,
## farol en 1ª/3ª persona, cofres, atajos, bus de eco, niebla de guerra en minimapa y rendimiento.

var _fallos: Array[String] = []
var _ok: int = 0
var _terminado: bool = false


func _ready() -> void:
	var arbol := get_tree()
	var tope := arbol.create_timer(75.0)
	tope.timeout.connect(func() -> void:
		if not _terminado:
			push_error("PruebaH04Mina: tiempo agotado (75 s)")
			arbol.quit(1))
	await _ejecutar()


func _comprobar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos.append(msg)
		push_error("FALLO H04: %s" % msg)


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _fisica(n: int = 2) -> void:
	for i in n:
		await get_tree().physics_frame


func _ir(id: String, marcador: String = "Llegada_Interior") -> Dictionary:
	var t0 := Time.get_ticks_msec()
	await Escenas.ir_a_mapa(id, marcador)
	await _frames(3)
	await _fisica(4)
	var ms := Time.get_ticks_msec() - t0
	return {"mapa": Escenas.mapa_actual_nodo(), "ms": ms}


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_h04.json"
	Juego.nueva_partida("PruebaH04")
	Juego.pausar_tiempo(true)
	Juego.minutos = 720
	Juego.anadir_objeto("pico", 1)

	# 1. Audio bus de eco y farol fuera de la mina
	print("[1] Audio MinaEco y estado exterior del farol")
	var idx_eco := AudioServer.get_bus_index(Audio.BUS_MINA_ECO)
	_comprobar(idx_eco >= 0 and AudioServer.get_bus_send(idx_eco) == "Efectos", "bus MinaEco existe y envía a Efectos")
	_comprobar(idx_eco >= 0 and AudioServer.get_bus_effect_count(idx_eco) >= 1 and AudioServer.get_bus_effect(idx_eco, 0) is AudioEffectReverb, "MinaEco tiene AudioEffectReverb")
	var r_granja := await _ir("granja", "Spawn_Protagonista")
	var j_ext := Escenas.jugador() as Jugador
	_comprobar(Audio.bus_efectos_actual("paso_hierba") == "Efectos", "fuera de la mina el bus de efectos es Efectos")
	var farol_ext := j_ext.get_node_or_null("Farol") as OmniLight3D
	_comprobar(farol_ext != null and not farol_ext.visible, "fuera de la mina el farol está apagado")

	# 2. Nivel 1: ala este abierta, alturas, farol 1ª/3ª persona, cofre, atajo, niebla y tiempos
	print("[2] Nivel 1: boquete este, farol, cofre, atajo y niebla de guerra")
	Juego.banderas["nivel_mina"] = 1
	var r1 := await _ir("mina_interior", "Llegada_Interior")
	var m1 := r1["mapa"] as Node3D
	var j1 := Escenas.jugador() as Jugador
	var nm1 := m1.get_node("Objetos/NivelMina") as NivelMina
	var rocas1 := m1.get_node("Objetos/RocasMina") as RocasMina
	print("   Nivel 1 carga: %d ms | celdas 0.5m: %d | superficie_m2: %.1f" % [int(r1["ms"]), rocas1.celdas.size(), nm1.superficie_generada_m2])
	_comprobar(int(r1["ms"]) <= 3500, "carga de nivel 1 en tiempo razonable (%d ms)" % int(r1["ms"]))
	_comprobar(Audio.bus_efectos_actual("mina_cofre") == "MinaEco", "dentro de mina_interior usa bus MinaEco")
	_comprobar(rocas1.celdas.size() >= 1700, "nivel 1 alcanza el ala este pasando el umbral (%d celdas)" % rocas1.celdas.size())

	# Verificar farol visual en 1ª y 3ª persona
	var farol_luz := j1.get_node_or_null("Farol") as OmniLight3D
	var fp1 := j1.find_child("FarolPrimeraPersona", true, false) as Node3D
	var fp3 := j1.find_child("FarolTerceraPersona", true, false) as Node3D
	_comprobar(farol_luz != null and farol_luz.visible, "dentro de la mina la luz del farol está encendida")
	_comprobar(fp1 != null and fp3 != null, "modelos 3D del farol cargados para 1ª y 3ª persona")
	Ajustes.poner("vista", 0)
	j1.camara.primera_persona = true
	await _fisica(28)
	_comprobar(fp1.visible and not fp3.visible, "en 1ª persona se ve el farol en mano y se oculta el de 3ª")
	j1.camara.primera_persona = false
	await _fisica(28)
	_comprobar(not fp1.visible and fp3.visible, "en 3ª persona se ve el farol en Leo y se oculta el de 1ª")
	j1.camara.primera_persona = true
	await _fisica(12)

	# Verificar cofre y atajo en nivel 1
	_comprobar(nm1.cofres_nivel.size() >= 1, "nivel 1 tiene al menos 1 cofre oculto")
	if not nm1.cofres_nivel.is_empty():
		var cf := nm1.cofres_nivel[0]
		var pc := cf.find_child("InteractuableCofre", true, false) as Interactuable
		var din0 := Juego.dinero
		_comprobar(pc != null and pc.activo, "cofre interactuable disponible")
		if pc != null:
			pc.usado.emit(j1)
			await _frames(3)
			_comprobar(not pc.activo and Juego.dinero > din0, "abrir cofre otorga monedas/minerales (%d -> %d)" % [din0, Juego.dinero])
	_comprobar(nm1.atajos_nivel.size() >= 1, "nivel 1 tiene puerta de atajo desbloqueable")
	if not nm1.atajos_nivel.is_empty():
		var at := nm1.atajos_nivel[0]
		var pa := at.find_child("InteractuableAtajo", true, false) as Interactuable
		_comprobar(pa != null and pa.activo, "atajo listo para desbloquearse")
		if pa != null:
			pa.usado.emit(j1)
			await _frames(3)
			_comprobar(not pa.activo, "desbloquear atajo abre el paso permanentemente")

	# Niebla de guerra en minimapa: salida cercana explorada, fondo lejano oculto hasta caminar allí
	var mm := Interfaz.minimapa()
	var frac0 := nm1.fraccion_explorada()
	var llegada1 := m1.call("marcador", "Llegada_Interior") as Marker3D
	_comprobar(nm1.es_punto_explorado(Vector2(llegada1.global_position.x, llegada1.global_position.z)), "llegada explorada desde inicio")
	_comprobar(frac0 < 0.75, "la niebla de guerra cubre la mayor parte de la mina sin explorar (%.0f%%)" % (frac0 * 100.0))
	var punto_lejano := Vector2(450.0, -25.0)
	_comprobar(not nm1.es_punto_explorado(punto_lejano), "la cámara noreste está cubierta por la niebla al entrar")
	nm1.revelar_niebla_en(punto_lejano)
	_comprobar(nm1.es_punto_explorado(punto_lejano) and nm1.fraccion_explorada() > frac0, "avanzar por la galería despeja la niebla en mapa y minimapa")
	_comprobar(mm != null and mm.nivel_mina_actual() == nm1 and nm1.textura_niebla() != null, "el minimapa enlaza la textura dinámica de niebla")

	# Verificar alturas alcanzables en rocas.celdas (sala sur elevada a +2.0 m)
	var min_y1 := INF
	var max_y1 := -INF
	for c_r: Vector2i in rocas1.celdas:
		var y_r := float(rocas1.celdas[c_r])
		min_y1 = minf(min_y1, y_r)
		max_y1 = maxf(max_y1, y_r)
	_comprobar(max_y1 - min_y1 >= 1.5, "nivel 1 tiene distintas cotas caminables (%.2f m .. %.2f m)" % [min_y1, max_y1])

	# 3. Biomas profundos, chunks espaciales, iluminación oscura, puentes y rendimiento
	print("[3] Niveles profundos (2, 8 húmeda, 13 cristal, 20 magma)")
	for nv: int in [2, 8, 13, 20]:
		Juego.banderas["nivel_mina"] = nv
		var res := await _ir("mina_interior", "Llegada_Interior")
		var mapa := res["mapa"] as Node3D
		var nm := mapa.get_node("Objetos/NivelMina") as NivelMina
		var rocas := mapa.get_node("Objetos/RocasMina") as RocasMina
		var env := (mapa.get_node("WorldEnvironment") as WorldEnvironment).environment
		var geo := nm.get_node_or_null("GeometriaProcedural")
		var trozos := geo.find_children("Trozo_*", "Node3D", false, false).size() if geo != null else 0
		var pasarelas := geo.find_children("Pasarela", "StaticBody3D", true, false).size() if geo != null else 0
		var b_min := INF
		var b_max := -INF
		for c_r: Vector2i in rocas.celdas:
			var yr := float(rocas.celdas[c_r])
			b_min = minf(b_min, yr)
			b_max = maxf(b_max, yr)
		print("   Nv.%d (%s): %d ms | chunks=%d | pasarelas=%d | amb=%.2f | y=%.1f..%.1f | celdas=%d" % [
			nv, nm.ambientacion_id, int(res["ms"]), trozos, pasarelas, env.ambient_light_energy, b_min, b_max, rocas.celdas.size()
		])
		_comprobar(int(res["ms"]) <= 3500, "nivel %d carga en <=3.5 s (%d ms)" % [nv, int(res["ms"])])
		_comprobar(trozos >= 2, "nivel %d particionado en chunks espaciales 20x20 (%d)" % [nv, trozos])
		_comprobar(pasarelas >= 1, "nivel %d tiene pasarela sobre sima (%d)" % [nv, pasarelas])
		_comprobar(env.ambient_light_energy <= 0.25, "nivel %d mantiene oscuridad real sin luces (%.2f)" % [nv, env.ambient_light_energy])
		if nv >= 8:
			_comprobar(b_max - b_min >= 1.5, "nivel %d tiene desnivel y rampas transitables (%.1f..%.1f)" % [nv, b_min, b_max])
			_comprobar(nm.cofres_nivel.size() >= 2, "nivel %d incluye cofres en ramales (%d)" % [nv, nm.cofres_nivel.size()])

	_terminado = true
	if _fallos.is_empty():
		print("PRUEBA H04 MINA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H04 MINA FALLO (%d errores, %d ok)" % [_fallos.size(), _ok])
		get_tree().quit(1)
