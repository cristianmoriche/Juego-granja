extends Node
## Prueba autónoma de T26-mina-20-niveles (con tope interno de 58 s -> quit(1)).

var _fallos: Array[String] = []
var _ok: int = 0
var _terminado: bool = false


func _ready() -> void:
	var arbol := get_tree()
	var tope := arbol.create_timer(58.0)
	tope.timeout.connect(func() -> void:
		if not _terminado:
			push_error("PruebaT26Mina: tiempo agotado (60 s)")
			arbol.quit(1))
	await _ejecutar()


func _comprobar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos.append(msg)
		push_error("FALLO T26: %s" % msg)


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _fisica(n: int = 2) -> void:
	for i in n:
		await get_tree().physics_frame


func _ir(id: String, marcador: String = "Spawn_Protagonista") -> Node3D:
	await Escenas.ir_a_mapa(id, marcador)
	await _frames(3)
	await _fisica(3)
	return Escenas.mapa_actual_nodo()


func _area_poligono(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_t26.json"
	Juego.nueva_partida("PruebaT26")
	Juego.pausar_tiempo(true)
	Juego.minutos = 600

	# 1. Datos de minerales nuevos, iconos y enemigos.json
	print("[1] Datos de minerales y enemigos")
	for mid in ["oro", "amatista", "rubi", "diamante"]:
		var o := Datos.objeto(mid)
		_comprobar(not o.is_empty() and str(o.get("tipo", "")) == "mineral", "mineral %s existe en objetos.json" % mid)
		_comprobar(Datos.tiene_icono(mid), "icono %s.png cargado" % mid)
	_comprobar(int(Datos.objeto("oro")["precio_venta"]) < int(Datos.objeto("amatista")["precio_venta"]) and int(Datos.objeto("amatista")["precio_venta"]) < int(Datos.objeto("rubi")["precio_venta"]) and int(Datos.objeto("rubi")["precio_venta"]) < int(Datos.objeto("diamante")["precio_venta"]), "valor creciente de oro y gemas")

	var defs := Enemigo.cargar_definiciones()
	_comprobar(defs.size() >= 4, "enemigos.json define >= 4 tipos de enemigo (%d)" % defs.size())
	_comprobar(not Enemigo.ACTIVOS, "Enemigo.ACTIVOS es false hasta recibir modelos")
	for d: Dictionary in defs:
		_comprobar(not str(d.get("tipo", "")).is_empty() and float(d.get("vida", 0)) > 0.0 and float(d.get("dano", 0)) > 0.0 and float(d.get("velocidad", 0)) > 0.0, "enemigo %s tiene tipo/vida/daño/velocidad" % str(d.get("id", "?")))
		_comprobar(str(d.get("modelo", "x")) == "", "enemigo %s tiene ruta de modelo vacía" % str(d.get("id", "?")))
		var nv: Array = d.get("niveles", [])
		_comprobar(nv.size() == 2, "enemigo %s define rango de niveles" % str(d.get("id", "?")))

	# 2. Barra de vida en HUD solo dentro de la mina
	print("[2] HUD barra de vida solo dentro de la mina")
	await _ir("granja", "Spawn_Protagonista")
	var hud := Interfaz._hud as Hud
	_comprobar(hud != null and not hud.barra_vida_visible(), "en la granja la barra de vida está oculta")

	# 3. Recorrido por niveles representativos 1..20, ambientaciones, tamaño, minerales, antorchas y ascensor
	print("[3] Niveles 1..20, tamaño 1x->3x, 4 ambientaciones y minerales")
	var area_l1 := 0.0
	var celdas_l1 := 0
	var area_l20 := 0.0
	var celdas_l20 := 0
	var muestras := [1, 2, 3, 5, 6, 8, 10, 11, 13, 15, 16, 18, 20]
	var prev_area_suelo := 0.0

	for nv: int in muestras:
		Juego.banderas["nivel_mina"] = nv
		var mapa := await _ir("mina_interior", "Llegada_Interior")
		_comprobar(mapa != null and str(mapa.get("id_mapa")) == "mina_interior", "carga mina_interior nivel %d" % nv)
		if nv == 1:
			_comprobar(hud.barra_vida_visible(), "dentro de la mina la barra de vida sí se muestra")
		var nm := mapa.get_node_or_null("Objetos/NivelMina") as NivelMina
		var rocas := mapa.get_node_or_null("Objetos/RocasMina") as RocasMina
		var bajada := mapa.get_node_or_null("Objetos/BajadaMina") as BajadaMina
		_comprobar(nm != null and rocas != null and bajada != null, "nivel %d: nodos NivelMina/RocasMina/BajadaMina presentes" % nv)
		_comprobar(nm.ambientacion_id == NivelMina.id_ambientacion(nv), "nivel %d: ambientación correcta (%s)" % [nv, nm.ambientacion_id])
		_comprobar(nm.posiciones_antorchas.size() >= 5, "nivel %d: antorchas con luz (%d)" % [nv, nm.posiciones_antorchas.size()])
		_comprobar(nm.puntos_enemigos != null and nm.puntos_enemigos.get_child_count() >= 3, "nivel %d: puntos de aparición de enemigos (%d)" % [nv, nm.puntos_enemigos.get_child_count() if nm.puntos_enemigos != null else 0])
		# Verificar que no hay enemigos activos spawneados mientras ACTIVOS = false
		var enemigos_vivos := 0
		if nm.puntos_enemigos != null:
			for h in nm.puntos_enemigos.get_children():
				if h is Enemigo:
					enemigos_vivos += 1
		_comprobar(enemigos_vivos == 0, "nivel %d: ningún enemigo activo con ACTIVOS = false" % nv)

		var es_asc := nv in [1, 5, 10, 15, 20]
		_comprobar((nm.nodo_ascensor != null) == es_asc, "nivel %d: ascensor cada 5 niveles (%s)" % [nv, str(es_asc)])

		if nv == 2:
			_comprobar(nm.nodo_escalera_profunda != null, "nivel 2: tiene escalera profunda hacia el nivel 3")
			_comprobar("Subir al nivel 1" in bajada.punto.texto_interaccion(), "nivel 2: mantiene Subir al nivel 1 en Bajada_Nivel_2")
		elif nv < 20:
			_comprobar("Bajar al nivel %d" % (nv + 1) in bajada.punto.texto_interaccion(), "nivel %d: escalera de bajada al %d" % [nv, nv + 1])

		var poly: PackedVector2Array = mapa.get("poligono_limites")
		var area_p := _area_poligono(poly)
		var celdas := rocas.celdas.size()
		_comprobar(rocas.rocas.size() >= 18, "nivel %d: hay rocas generadas (%d, celdas=%d, poly=%.0f m2)" % [nv, rocas.rocas.size(), celdas, area_p])
		if nv == 1:
			area_l1 = area_p
			celdas_l1 = celdas
		elif nv == 20:
			area_l20 = area_p
			celdas_l20 = celdas
		if nv >= 3:
			var geo := nm.get_node_or_null("GeometriaProcedural")
			_comprobar(geo != null, "nivel %d: geometría procedural activa" % nv)
			_comprobar(nm.superficie_generada_m2 > prev_area_suelo, "nivel %d: superficie crece respecto a muestra anterior (%.1f > %.1f)" % [nv, nm.superficie_generada_m2, prev_area_suelo])
			prev_area_suelo = nm.superficie_generada_m2
			if nm.ambientacion_id == "humeda":
				_comprobar(geo.find_children("Charco_*", "MeshInstance3D", false, false).size() >= 1, "nivel %d: ambientación húmeda con charcos de agua" % nv)
			elif nm.ambientacion_id == "cristal":
				_comprobar(geo.find_children("Cristales_*", "Node3D", false, false).size() >= 1, "nivel %d: ambientación cristal con cristales luminosos" % nv)
			elif nm.ambientacion_id == "magma":
				_comprobar(geo.find_children("Magma_*", "MeshInstance3D", false, false).size() >= 1, "nivel %d: ambientación magma con pozas incandescentes" % nv)
		else:
			prev_area_suelo = nm.superficie_generada_m2

		# Verificar minerales por profundidad
		var tipos_presentes: Dictionary = {}
		for r in rocas.rocas:
			tipos_presentes[r.tipo] = int(tipos_presentes.get(r.tipo, 0)) + 1
		if nv == 8:
			_comprobar(int(tipos_presentes.get("oro", 0)) >= 2, "nivel 8: ya aparece oro (%d vetas)" % int(tipos_presentes.get("oro", 0)))
		elif nv == 13:
			_comprobar(int(tipos_presentes.get("amatista", 0)) >= 2, "nivel 13: aparecen gemas amatista (%d)" % int(tipos_presentes.get("amatista", 0)))
		elif nv == 20:
			_comprobar(int(tipos_presentes.get("rubi", 0)) >= 2 and int(tipos_presentes.get("diamante", 0)) >= 2, "nivel 20: aparecen rubí y diamante")

	print("   Comparativa tamaño: L1=%.0f m2 (%d celdas 0.5m) -> L20=%.0f m2 (%d celdas 0.5m), ratio poly=%.2fx, ratio celdas=%.2fx" % [
		area_l1, celdas_l1, area_l20, celdas_l20, area_l20 / maxf(area_l1, 1.0), float(celdas_l20) / float(maxi(celdas_l1, 1))
	])
	_comprobar(area_l20 / maxf(area_l1, 1.0) >= 2.8, "nivel 20 alcanza ~3x superficie del polígono de nivel 1 (%.2fx)" % (area_l20 / maxf(area_l1, 1.0)))
	_comprobar(celdas_l20 >= celdas_l1 * 2, "nivel 20 al menos duplica/triplica las celdas pisables de nivel 1 (%d vs %d)" % [celdas_l20, celdas_l1])

	# 4. Progreso de ascensor y guardado/carga
	print("[4] Ascensor y persistencia de progreso")
	var paradas := NivelMina.paradas_ascensor_desbloqueadas()
	_comprobar(paradas == [1, 5, 10, 15, 20], "paradas de ascensor desbloqueadas tras llegar al nivel 20 (%s)" % str(paradas))
	_comprobar(int(Juego.banderas.get("mina_max_nivel", 0)) == 20, "mina_max_nivel guardado a 20")

	Juego.recibir_dano(30.0)
	_comprobar(is_equal_approx(Juego.vida, 70.0), "recibir_dano reduce vida de Leo (70)")
	_comprobar(Juego.guardar(), "se guarda partida con vida y progreso de mina")
	Juego.banderas.clear()
	Juego.vida = 100.0
	_comprobar(Juego.cargar(), "se recarga partida")
	_comprobar(is_equal_approx(Juego.vida, 70.0) and int(Juego.banderas.get("mina_max_nivel", 0)) == 20, "se conservan vida=70 y mina_max_nivel=20")

	# 5. Prueba funcional de Enemigo (perseguir, atacar, morir con cápsula invisible)
	print("[5] Enemigo base (perseguir, atacar, morir)")
	Juego.banderas["nivel_mina"] = 12
	var mapa12 := await _ir("mina_interior", "Llegada_Interior")
	var nm12 := mapa12.get_node("Objetos/NivelMina") as NivelMina
	var jugador := Escenas.jugador()
	var enemigos := nm12.instanciar_enemigos_prueba(true)
	_comprobar(not enemigos.is_empty(), "instanciar_enemigos_prueba crea enemigos de muestra")
	var en := enemigos[0]
	_comprobar(en.marcador_capsula != null and not en.marcador_capsula.visible, "cápsula de marcador es invisible para el jugador")
	en.global_position = jugador.global_position + Vector3(4.0, 0.0, 0.0)
	var dist0 := en.global_position.distance_to(jugador.global_position)
	en.perseguir(jugador, 0.4)
	var dist1 := en.global_position.distance_to(jugador.global_position)
	_comprobar(dist1 < dist0, "enemigo.perseguir acerca al enemigo a Leo (%.2f -> %.2f)" % [dist0, dist1])
	en.global_position = jugador.global_position + Vector3(0.8, 0.0, 0.0)
	var vida_antes := Juego.vida
	var golpeo := en.atacar(jugador)
	_comprobar(golpeo and Juego.vida < vida_antes, "enemigo.atacar daña a Leo (%.1f -> %.1f)" % [vida_antes, Juego.vida])
	en.recibir_dano(en.vida_max)
	_comprobar(en.muerto, "enemigo.morir marca muerto=true al agotar su vida")

	# 6. Salir de la mina vuelve a ocultar la barra de vida y restaura nivel_mina=1 al salir por la boca
	await _ir("mina_exterior", "Spawn_Protagonista")
	_comprobar(not hud.barra_vida_visible(), "al salir de la mina la barra de vida se oculta otra vez")

	_terminado = true
	if _fallos.is_empty():
		print("PRUEBA T26 MINA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA T26 MINA FALLO (%d errores, %d ok)" % [_fallos.size(), _ok])
		get_tree().quit(1)
