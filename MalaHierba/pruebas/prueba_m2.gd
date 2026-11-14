extends Node
## Prueba de M2 (tamaño de Leo y de los vecinos, saltar, agacharse). Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_m2.tscn
## Imprime «PRUEBA OK (N comprobaciones)» o «PRUEBA FALLO: <motivos>» y sale con 0 o 1.
## Usa las clases de verdad (Escenas.ir_a_mapa, Jugador, Npc, Interfaz, los muros de la capa 6); el teclado entra por el
## viewport como el de un jugador (Espacio) y las teclas mantenidas con Input.action_press (Ctrl, W, Shift).

const MAPAS := ["granja", "pueblo", "mina_exterior", "mina_interior"]

var _fallos: Array[String] = []
var _total: int = 0
var _mapa: Node = null
var _j: Jugador = null


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _fisica(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_m2.json"
	Juego.nueva_partida("Leo")

	_prueba_entradas()
	await _ir("granja")
	await _prueba_tamano_granja()
	await _prueba_salto()
	await _prueba_salto_bloqueado()
	await _prueba_agacharse()
	await _ir("pueblo")
	await _prueba_tamano_pueblo()
	await _prueba_vecinos()
	for id: String in MAPAS:
		if str(_mapa.get("id_mapa")) != id:
			await _ir(id)
		await _prueba_salto_contra_limites(id)

	_soltar_teclas()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)), "  (%d comprobaciones)" % _total)
		get_tree().quit(1)


# --- Utilidades ---------------------------------------------------------------------------------------------------

func _ir(id: String) -> void:
	print("[mapa %s]" % id)
	var mm: Minimapa = Interfaz.minimapa()
	var fotos_antes := mm.fotos_hechas
	var llegada := "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista"
	await Escenas.ir_a_mapa(id, llegada)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 120:
		if bool(_mapa.get("vallas_listas")) and mm.fotos_hechas > fotos_antes:
			break
		await get_tree().process_frame
	_comprobar(_mapa != null and str(_mapa.get("id_mapa")) == id, "%s: se carga el mapa" % id)
	_comprobar(_j != null, "%s: hay jugador" % id)
	Interfaz.cerrar_todo()


func _soltar_teclas() -> void:
	for a in ["mover_arriba", "mover_abajo", "mover_izquierda", "mover_derecha", "correr", "agachar", "saltar"]:
		Input.action_release(a)


## Pulsa y suelta el Espacio como un jugador: entra por el viewport.
func _espacio() -> void:
	for pulsada in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pulsada
		get_viewport().push_input(ev)


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z)
	return float(col["suelo"])


func _poner_a_leo(pos: Vector3, yaw: float) -> void:
	_j.colocar(pos, 0.0, yaw)
	_j._pos_segura = pos
	_j.direccion = Vector3(0, 0, -1).rotated(Vector3.UP, yaw)


## Altura (y máxima − y mínima) de las mallas de un nodo, en coordenadas del mundo.
func _caja(n: Node3D) -> AABB:
	var total := AABB()
	var primero := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_inside_tree():
			continue
		var a := mi.global_transform * mi.get_aabb()
		total = a if primero else total.merge(a)
		primero = false
	return total


## Caja de las mallas del mapa cuyo nombre empieza por `prefijo` (los importadores añaden «_001» al final).
func _caja_mapa(prefijo: String) -> AABB:
	var total := AABB()
	var primero := true
	for m in _mapa.find_children(prefijo + "*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		total = a if primero else total.merge(a)
		primero = false
	return total


## Una dirección horizontal con `largo` metros libres delante de `pos` (comprobado con la cápsula de Leo).
func _direccion_libre(pos: Vector3, largo: float) -> Vector3:
	for k in 16:
		var d := Vector3(0, 0, -1).rotated(Vector3.UP, TAU * float(k) / 16.0)
		var t := Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.3, 0))
		if _j.test_move(t, d * largo):
			continue
		# Y que el suelo de allí sea llano (sin escalones ni huecos).
		var llano := true
		for m in [0.25, 0.5, 0.75, 1.0]:
			var q := pos + d * largo * float(m)
			var y := _suelo(q.x, q.z)
			if is_nan(y) or absf(y - pos.y) > 0.35:
				llano = false
		if llano:
			return d
	return Vector3.INF


## Pone a Leo sobre suelo despejado: devuelve la dirección libre (o INF) y lo deja quieto y asentado.
func _colocar_despejado(largo: float) -> Vector3:
	var inicio := _mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	var base := inicio.global_position
	for desp in [Vector2(0, 0), Vector2(4, 4), Vector2(-4, 4), Vector2(4, -4), Vector2(-4, -4), Vector2(8, 0), Vector2(-8, 0)]:
		var p := base + Vector3(desp.x, 0, desp.y)
		var y := _suelo(p.x, p.z)
		if is_nan(y):
			continue
		p.y = y + 0.05
		_poner_a_leo(p, 0.0)
		var d := _direccion_libre(p, largo)
		if d != Vector3.INF:
			var yaw := atan2(-d.x, -d.z)
			_poner_a_leo(p, yaw)
			_soltar_teclas()
			return d
	return Vector3.INF


# --- Entradas -------------------------------------------------------------------------------------------------------

func _prueba_entradas() -> void:
	print("[entradas]")
	_comprobar(InputMap.has_action("saltar") and InputMap.has_action("agachar"), "existen las acciones saltar y agachar")
	var esp := InputEventKey.new()
	esp.physical_keycode = KEY_SPACE
	esp.pressed = true
	_comprobar(esp.is_action("saltar"), "Espacio = saltar")
	_comprobar(not esp.is_action("usar"), "el Espacio ya no es «usar» (el clic izquierdo sigue siéndolo)")
	var clic := InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	_comprobar(clic.is_action("usar"), "clic izquierdo = usar")
	var ctrl := InputEventKey.new()
	ctrl.physical_keycode = KEY_CTRL
	ctrl.location = KEY_LOCATION_LEFT
	ctrl.pressed = true
	_comprobar(ctrl.is_action("agachar"), "Ctrl izquierdo = agacharse")
	var ctrl_d := InputEventKey.new()
	ctrl_d.physical_keycode = KEY_CTRL
	ctrl_d.location = KEY_LOCATION_RIGHT
	ctrl_d.pressed = true
	_comprobar(not ctrl_d.is_action("agachar"), "Ctrl derecho no agacha (es el izquierdo, como se pidió)")
	# Ninguna otra acción usa el Espacio ni el Ctrl izquierdo.
	for a: StringName in InputMap.get_actions():
		if str(a).begins_with("ui_") or a == &"saltar" or a == &"agachar":
			continue
		for ev: InputEvent in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				_comprobar(k.physical_keycode != KEY_SPACE and k.physical_keycode != KEY_CTRL, "la acción %s no pisa el Espacio ni el Ctrl" % a)


# --- Tamaño de Leo frente a puertas y casas ----------------------------------------------------------------------

func _prueba_tamano_granja() -> void:
	print("[tamaño en la granja]")
	await _fisica(10)
	var esc := EscalaPersonaje.ESCALA
	_comprobar(esc > 0.8 and esc < 0.95, "la escala común (%.2f) es una reducción razonable" % esc)
	var caja_leo := _caja(_j.get_node("Modelo") as Node3D)
	var alto := caja_leo.size.y
	print("   Leo mide %.2f m (el modelo del .glb mide %.2f m)" % [alto, EscalaPersonaje.ALTURA_MODELO_LEO])
	_comprobar(absf(alto - EscalaPersonaje.altura_leo()) < 0.03, "Leo mide %.2f m (esperado %.2f)" % [alto, EscalaPersonaje.altura_leo()])
	_comprobar(alto >= 1.70 and alto <= 1.80, "Leo mide entre 1,70 y 1,80 m (%.2f)" % alto)
	var forma := _j.get_node("Colision").get("shape") as CapsuleShape3D
	_comprobar(absf(forma.height - EscalaPersonaje.ALTURA_PIE) < 0.01 and absf(forma.radius - EscalaPersonaje.RADIO) < 0.01, "cápsula de pie %.2f × r %.2f" % [forma.height, forma.radius])
	_comprobar(forma.height <= alto + 0.01 and forma.height >= alto * 0.85, "la cápsula (%.2f m) casa con el modelo (%.2f m)" % [forma.height, alto])
	# Puerta de la cabaña: ~2 m; Leo pasa con holgura y tampoco es un enano.
	var puerta := _caja_mapa("Cabana_puerta")
	print("   puerta de la cabaña: %.2f m de alto" % puerta.size.y)
	_comprobar(puerta.size.y > 1.8 and puerta.size.y < 2.2, "puerta de la cabaña de ~2 m (%.2f)" % puerta.size.y)
	_comprobar(alto + 0.15 <= puerta.size.y, "Leo (%.2f) cabe de pie por la puerta de la cabaña (%.2f) con 15 cm de holgura" % [alto, puerta.size.y])
	_comprobar(alto >= puerta.size.y * 0.8, "Leo (%.2f) no es desproporcionadamente bajo frente a la puerta (%.2f)" % [alto, puerta.size.y])
	var puerta_silo := _caja_mapa("Silo_puerta")
	_comprobar(alto + 0.1 <= puerta_silo.size.y, "Leo (%.2f) cabe por la puerta del silo (%.2f)" % [alto, puerta_silo.size.y])
	# Casas: la cabaña y el silo son mucho más altos que él.
	var troncos := _caja_mapa("Cabana_troncos")
	var tejado := _caja_mapa("Cabana_tejado")
	print("   cabaña: troncos hasta %.2f m, tejado hasta %.2f m" % [troncos.end.y, tejado.end.y])
	_comprobar(troncos.size.y > 0.0 and troncos.end.y > alto + 0.5, "las paredes de la cabaña (%.2f) pasan de la cabeza de Leo (%.2f)" % [troncos.end.y, alto])
	_comprobar(tejado.end.y >= alto * 2.5, "el tejado de la cabaña (%.2f) es más de 2,5 veces Leo" % tejado.end.y)
	_comprobar(_caja_mapa("Silo_muro").end.y >= alto * 3.0, "el silo es al menos tres veces más alto que Leo")
	# La cámara por defecto sigue la escala.
	_comprobar(absf(CamaraJuego.DIST_JUEGO - 12.0 * esc) < 0.001, "distancia de la vista de juego = 12 × escala (%.2f)" % CamaraJuego.DIST_JUEGO)
	_comprobar(CamaraJuego.DIST_MIN == 2.5 and CamaraJuego.DIST_MAX == 22.0, "el rango del zoom sigue siendo 2,5–22 m")


func _prueba_tamano_pueblo() -> void:
	print("[tamaño en el pueblo]")
	await _fisica(10)
	var alto := _caja(_j.get_node("Modelo") as Node3D).size.y
	# Casas de una planta: Leo queda por debajo del alero (tablas) y el caballete (vigas) es más del doble de alto que él.
	for casa: String in ["casita_a", "casita_b", "herreria", "tienda"]:
		var paredes := _caja_mapa(casa + "_Tablas")
		var vigas := _caja_mapa(casa + "_Vigas")
		_comprobar(paredes.size.y > 0.0 and vigas.size.y > 0.0, "%s: se encuentran sus paredes y vigas en el mapa" % casa)
		print("   %s: alero %.2f m, caballete %.2f m" % [casa, paredes.end.y, vigas.end.y])
		_comprobar(alto + 0.1 <= paredes.end.y, "%s: Leo (%.2f) queda por debajo del alero (%.2f)" % [casa, alto, paredes.end.y])
		_comprobar(vigas.end.y >= alto * 2.0, "%s: el caballete (%.2f) es más del doble de alto que Leo" % [casa, vigas.end.y])
	for casa: String in ["alcalde", "taberna", "capilla"]:
		var vigas := _caja_mapa(casa + "_Vigas")
		_comprobar(vigas.size.y > 0.0 and vigas.end.y >= alto * 3.0, "%s: más de tres veces la altura de Leo (%.2f)" % [casa, vigas.end.y])


# --- Vecinos a la misma escala ----------------------------------------------------------------------------------

## Altura (local, sin escalar) de las mallas de un modelo recién instanciado.
func _altura_nativa(ruta: String) -> float:
	var inst := (load(ruta) as PackedScene).instantiate() as Node3D
	var h := 0.0
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			h = maxf(h, mi.get_aabb().end.y)
	inst.free()
	return h


func _prueba_vecinos() -> void:
	print("[vecinos]")
	var datos: Array[Dictionary] = []
	for id: String in Datos.ids_npc():
		datos.append(Datos.npc(id))
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://datos/vecinos_relleno.json")) == OK and json.data is Array:
		for d: Variant in json.data:
			var dd: Dictionary = (d as Dictionary).duplicate()
			dd["relleno"] = true
			datos.append(dd)
	_comprobar(datos.size() >= 10, "hay vecinos que medir (%d)" % datos.size())
	var alto_leo := _caja(_j.get_node("Modelo") as Node3D).size.y
	var escala_leo := (_j.get_node("Modelo") as Node3D).scale.x
	var alturas: Dictionary = {}
	var creados: Array[Npc] = []
	for d: Dictionary in datos:
		var n := Npc.crear(d)
		_mapa.objetos.add_child(n)
		creados.append(n)
		n.global_position = Vector3(0, -500, 0)   # lejos, para no estorbar
		await get_tree().process_frame
		var inst := n._modelo.get_child(0) as Node3D
		var modelo := str(d.get("modelo", ""))
		var ajuste := float(d.get("escala", 1.0))
		var esperado := EscalaPersonaje.ESCALA * ajuste
		_comprobar(absf(inst.scale.x - esperado) < 0.0001, "%s: escala del modelo %.3f = escala común %.2f × ajuste propio %.2f" % [n.id, inst.scale.x, EscalaPersonaje.ESCALA, ajuste])
		_comprobar(absf(inst.scale.x - escala_leo * ajuste) < 0.0001, "%s: misma escala base que Leo (%.3f)" % [n.id, escala_leo])
		var h_juego := _caja(inst).size.y
		var h_nativa := _altura_nativa("res://assets/personajes/aldeanos/%s.glb" % modelo)
		_comprobar(absf(h_juego - h_nativa * esperado) < 0.03, "%s: mide %.2f m (modelo %.2f × %.3f)" % [n.id, h_juego, h_nativa, esperado])
		_comprobar(n._punto.altura_marca > h_juego + 0.2, "%s: la flecha (%.2f m) flota sobre su cabeza (%.2f m)" % [n.id, n._punto.altura_marca, h_juego])
		var forma := n.get_node("Colision").get("shape") as CapsuleShape3D
		_comprobar(absf(forma.radius - EscalaPersonaje.RADIO) < 0.001 and forma.height < EscalaPersonaje.ALTURA_PIE, "%s: cápsula (r %.2f, %.2f m) a la escala de Leo" % [n.id, forma.radius, forma.height])
		alturas[n.id] = [h_juego, modelo, ajuste]
	# Diferencias relativas conservadas: el niño sigue siendo mucho más bajo, y Leo sigue siendo el más alto de los principales.
	var nino: Array = alturas["pablo"]
	_comprobar(float(nino[0]) < alto_leo * 0.8, "el niño (%.2f) sigue siendo bastante más bajo que Leo (%.2f)" % [float(nino[0]), alto_leo])
	var proporcion_leo := alto_leo / EscalaPersonaje.ALTURA_MODELO_LEO
	_comprobar(absf(float(nino[0]) / alto_leo - _altura_nativa("res://assets/personajes/aldeanos/nino.glb") / EscalaPersonaje.ALTURA_MODELO_LEO) < 0.03, "la relación niño/Leo es la de los modelos originales")
	for id: String in ["mateo", "clara", "ramon", "anselmo", "tomas"]:
		_comprobar(float((alturas[id] as Array)[0]) <= alto_leo + 0.02, "%s no es más alto que Leo" % id)
	_comprobar(absf(proporcion_leo - EscalaPersonaje.ESCALA) < 0.02, "Leo = modelo × escala común")
	for n in creados:
		n.queue_free()
	await get_tree().process_frame


# --- Saltar --------------------------------------------------------------------------------------------------------

## Un salto completo: pulsa el Espacio y mide mientras dura. `avanzar`: W (y Mayús si `correr`) mantenidos antes y durante.
## `a_mitad`: pulsaciones de Espacio extra a esos segundos tras despegar (intentos de doble salto);
## `lateral`: mantiene D (relativo a la cámara) desde que está en el aire.
func _saltar_y_medir(avanzar: bool, correr: bool, a_mitad: Array[float] = [], lateral: bool = false) -> Dictionary:
	var y0 := _j.global_position.y
	var saltos0 := _j.saltos
	if avanzar:
		Input.action_press("mover_arriba")
		if correr:
			Input.action_press("correr")
		await _fisica(60)
	var p0 := _j.global_position
	var r := {"despego": false, "ymax": 0.0, "aire": 0.0, "aterrizo": false, "recorrido": 0.0, "lateral": 0.0, "estados": []}
	_espacio()
	var extra := a_mitad.duplicate()
	var en_aire := 0
	var t_aire := 0.0
	var x_aire := 0.0
	var pa := Vector3.ZERO
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in 300:
		await get_tree().physics_frame
		if not _j.is_on_floor():
			if not bool(r["despego"]):
				r["despego"] = true
				pa = _j.global_position
				x_aire = _j.global_position.x
			en_aire += 1
			t_aire = float(en_aire) * dt
			r["ymax"] = maxf(float(r["ymax"]), _j.global_position.y - y0)
			var est: Array = r["estados"]
			if not est.has(_j.estado_mov):
				est.append(_j.estado_mov)
			if lateral and t_aire > 0.05:
				Input.action_press("mover_derecha")
			while not extra.is_empty() and t_aire >= float(extra[0]):
				_espacio()
				extra.remove_at(0)
		elif bool(r["despego"]):
			r["aterrizo"] = true
			break
		if i > 150 and not bool(r["despego"]):
			break
	r["aire"] = t_aire
	r["recorrido"] = Vector2(_j.global_position.x - pa.x, _j.global_position.z - pa.z).length()
	r["lateral"] = _j.global_position.x - x_aire
	r["saltos"] = _j.saltos - saltos0
	_soltar_teclas()
	await _fisica(90)    # que se pare y asiente
	return r


func _prueba_salto() -> void:
	print("[saltar]")
	var d := _colocar_despejado(7.0)
	_comprobar(d != Vector3.INF, "hay un sitio despejado para saltar")
	if d == Vector3.INF:
		return
	await _fisica(60)
	_comprobar(_j.is_on_floor(), "Leo está en el suelo antes de saltar")
	var base := _j.global_position
	# 1) Parado.
	var r := await _saltar_y_medir(false, false)
	print("   parado: sube %.2f m, %.2f s en el aire, estados %s" % [float(r["ymax"]), float(r["aire"]), str(r["estados"])])
	_comprobar(bool(r["despego"]), "con Espacio despega del suelo")
	_comprobar(float(r["ymax"]) > 0.85 and float(r["ymax"]) < 1.15, "el salto sube alrededor de un metro (%.2f m)" % float(r["ymax"]))
	_comprobar(bool(r["aterrizo"]) and float(r["aire"]) > 0.45 and float(r["aire"]) < 0.75, "cae y aterriza en %.2f s" % float(r["aire"]))
	_comprobar(int(r["saltos"]) == 1, "un solo salto contado (%d)" % int(r["saltos"]))
	_comprobar((r["estados"] as Array).has("salto") and (r["estados"] as Array).has("caida"), "pasa por los estados salto y caída %s" % str(r["estados"]))
	_comprobar(_j.is_on_floor() and absf(_j.global_position.y - base.y) < 0.1, "vuelve a la altura de partida")
	# 2) Sin doble salto: más Espacio en el aire (subiendo y bajando) no da otro impulso.
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	var r2 := await _saltar_y_medir(false, false, [0.12, 0.25, 0.37] as Array[float])
	print("   con Espacio extra en el aire: sube %.2f m, %.2f s" % [float(r2["ymax"]), float(r2["aire"])])
	_comprobar(int(r2["saltos"]) == 1, "no hay doble salto: %d salto(s) tras pulsar 4 veces" % int(r2["saltos"]))
	_comprobar(float(r2["ymax"]) < 1.15 and float(r2["aire"]) < 0.75, "el Espacio en el aire no cambia el salto (%.2f m, %.2f s)" % [float(r2["ymax"]), float(r2["aire"])])
	# 3) Y desde el suelo vuelve a funcionar.
	var r3 := await _saltar_y_medir(false, false)
	_comprobar(bool(r3["despego"]) and int(r3["saltos"]) == 1, "tras aterrizar se puede volver a saltar")
	# 4) Andando y corriendo: conserva el avance y recorre más que parado.
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	var r4 := await _saltar_y_medir(true, false)
	print("   andando: recorre %.2f m en el aire (a %.1f m/s serían %.2f)" % [float(r4["recorrido"]), Jugador.VEL_ANDAR, Jugador.VEL_ANDAR * float(r4["aire"])])
	_comprobar(bool(r4["despego"]) and float(r4["ymax"]) > 0.85, "andando también salta (%.2f m)" % float(r4["ymax"]))
	_comprobar(float(r4["recorrido"]) > Jugador.VEL_ANDAR * float(r4["aire"]) * 0.7, "andando avanza durante el salto (%.2f m)" % float(r4["recorrido"]))
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	var r5 := await _saltar_y_medir(true, true)
	print("   corriendo: recorre %.2f m en el aire" % float(r5["recorrido"]))
	_comprobar(bool(r5["despego"]) and float(r5["ymax"]) > 0.85, "corriendo también salta (%.2f m)" % float(r5["ymax"]))
	_comprobar(float(r5["recorrido"]) > float(r4["recorrido"]) * 1.3, "corriendo llega más lejos que andando (%.2f frente a %.2f m)" % [float(r5["recorrido"]), float(r4["recorrido"])])
	# 5) Control en el aire: con D pulsada desplaza a un lado; sin ella, casi nada.
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	var r6 := await _saltar_y_medir(false, false, [] as Array[float], true)
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	var r7 := await _saltar_y_medir(false, false)
	print("   control aéreo: con D se desplaza %.2f m de lado, sin D %.2f m" % [float(r6["lateral"]), float(r7["lateral"])])
	_comprobar(absf(float(r6["lateral"])) > 0.25 and absf(float(r6["lateral"])) > absf(float(r7["lateral"])) + 0.2, "hay control en el aire (%.2f m de lado con D)" % float(r6["lateral"]))


func _prueba_salto_bloqueado() -> void:
	print("[saltar: cuándo no]")
	var d := _colocar_despejado(3.0)
	if d == Vector3.INF:
		_comprobar(false, "sitio despejado para las pruebas de bloqueo")
		return
	await _fisica(60)
	var saltos0 := _j.saltos
	# Con un diálogo abierto no salta, ni al pulsar Espacio para pasarlo ni al cerrarlo.
	Interfaz.mostrar_dialogo("Prueba", ["Hola, esto es una prueba."])
	_comprobar(Interfaz.ocupada(), "el diálogo ocupa la interfaz")
	_espacio()
	await _fisica(30)
	_espacio()
	await _fisica(30)
	_comprobar(_j.saltos == saltos0 and _j.is_on_floor(), "con un diálogo abierto, el Espacio no salta")
	Interfaz.cerrar_todo()
	await _fisica(40)
	_comprobar(_j.saltos == saltos0 and _j.is_on_floor(), "al cerrar el diálogo no salta por el Espacio pendiente")
	# Con la tienda abierta.
	Interfaz.abrir_tienda("tienda_mateo")
	_comprobar(Interfaz.ocupada(), "la tienda ocupa la interfaz")
	_espacio()
	await _fisica(40)
	_comprobar(_j.saltos == saltos0 and _j.is_on_floor(), "con la tienda abierta, el Espacio no salta")
	Interfaz.cerrar_todo()
	await _fisica(40)
	_comprobar(_j.saltos == saltos0, "al cerrar la tienda tampoco salta")
	# Durante el golpe de herramienta.
	_j.animar_herramienta()
	_espacio()
	await _fisica(30)
	_comprobar(_j.saltos == saltos0 and _j.is_on_floor(), "mientras usa la herramienta no salta")
	await _esperar(0.9)
	_comprobar(_j.saltos == saltos0, "el Espacio pulsado durante el golpe se olvida")
	# Y se salta con normalidad una vez libre.
	_espacio()
	await _fisica(20)
	_comprobar(_j.saltos == saltos0 + 1, "libre otra vez, salta")
	await _esperar(1.0)


# --- Agacharse --------------------------------------------------------------------------------------------------

func _velocidad_horizontal() -> float:
	return Vector2(_j.velocity.x, _j.velocity.z).length()


func _prueba_agacharse() -> void:
	print("[agacharse]")
	var d := _colocar_despejado(5.0)
	if d == Vector3.INF:
		_comprobar(false, "sitio despejado para agacharse")
		return
	await _fisica(60)
	var base := _j.global_position
	var forma := _j.get_node("Colision").get("shape") as CapsuleShape3D
	var alto_pie := forma.height
	var cam := _j.camara
	# Velocidades de referencia de pie.
	Input.action_press("mover_arriba")
	await _fisica(55)
	var v_andar := _velocidad_horizontal()
	Input.action_press("correr")
	await _fisica(40)
	var v_correr := _velocidad_horizontal()
	_soltar_teclas()
	print("   de pie: anda a %.2f m/s, corre a %.2f m/s" % [v_andar, v_correr])
	_comprobar(absf(v_andar - Jugador.VEL_ANDAR) < 0.2 and absf(v_correr - Jugador.VEL_CORRER) < 0.3, "velocidades de pie %.2f / %.2f m/s (escala común)" % [v_andar, v_correr])
	await _fisica(40)
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(40)
	_comprobar(not _j.agachado and absf(forma.height - alto_pie) < 0.001, "de pie al empezar")
	# Agacharse: cápsula más baja, pies en el mismo sitio, cámara más baja y sin tirón.
	var cam_y0 := cam.camara.global_position.y
	var y_pies := _j.global_position.y
	Input.action_press("agachar")
	var t0 := Time.get_ticks_msec()
	var previa := cam_y0
	var salto_max := 0.0
	while Time.get_ticks_msec() - t0 < 1100:
		await get_tree().process_frame
		var y := cam.camara.global_position.y
		salto_max = maxf(salto_max, absf(y - previa))
		previa = y
	_comprobar(_j.agachado and _j.estado_mov == "agachado", "Ctrl: Leo se agacha (estado %s)" % _j.estado_mov)
	_comprobar(forma.height < alto_pie - 0.45 and absf(forma.height - Jugador.ALTURA_AGACHADO) < 0.01, "la cápsula baja de %.2f a %.2f m" % [alto_pie, forma.height])
	_comprobar(absf(_j.global_position.y - y_pies) < 0.05, "los pies siguen en el suelo al agacharse")
	var cabeza_alta := (_j.get_node("Colision") as Node3D).global_position.y + forma.height * 0.5
	_comprobar(cabeza_alta < y_pies + Jugador.ALTURA_AGACHADO + 0.02, "la cápsula agachada acaba a %.2f m sobre los pies" % (cabeza_alta - y_pies))
	var caida_cam := cam_y0 - cam.camara.global_position.y
	print("   cámara: baja %.2f m, mayor salto por fotograma %.3f m" % [caida_cam, salto_max])
	_comprobar(caida_cam > 0.2, "la cámara baja con él (%.2f m)" % caida_cam)
	_comprobar(salto_max < 0.15, "la cámara baja sin tirón (mayor paso %.3f m por fotograma)" % salto_max)
	if _j._anim != null and _j._anim.has_animation("agachado_reposo"):
		_comprobar(_j._anim_propia and _j._visual.scale.is_equal_approx(Vector3.ONE) and absf(_j._visual.rotation.x) < 0.01,
			"animación propia activa al agacharse sin deformar el modelo (escala %s)" % _j._visual.scale)
	else:
		_comprobar(_j._visual.scale.y < 0.8, "pose provisional: el modelo se encoge al agacharse (%.2f)" % _j._visual.scale.y)
	# Más lento y sin correr.
	Input.action_press("mover_arriba")
	await _fisica(60)
	var v_ag := _velocidad_horizontal()
	Input.action_press("correr")
	await _fisica(60)
	var v_ag_corr := _velocidad_horizontal()
	_soltar_teclas()
	Input.action_press("agachar")
	print("   agachado: anda a %.2f m/s, con Mayús %.2f m/s" % [v_ag, v_ag_corr])
	_comprobar(v_ag > 1.0 and v_ag < v_andar * 0.6, "agachado va más despacio (%.2f frente a %.2f m/s)" % [v_ag, v_andar])
	_comprobar(v_ag_corr < v_andar * 0.6, "agachado no corre aunque se pulse Mayús (%.2f m/s)" % v_ag_corr)
	# No salta agachado.
	var saltos0 := _j.saltos
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	_espacio()
	await _fisica(40)
	_comprobar(_j.saltos == saltos0 and _j.is_on_floor(), "agachado no salta")
	# Se levanta al soltar.
	Input.action_release("agachar")
	await _fisica(20)
	_comprobar(not _j.agachado and absf(forma.height - alto_pie) < 0.001, "al soltar Ctrl se levanta")
	# Techo bajo: agachado bajo una losa a 1,3 m de los pies, soltar Ctrl no lo levanta.
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(30)
	Input.action_press("agachar")
	await _fisica(20)
	var losa := _crear_losa(base, 1.3)
	await _fisica(10)
	_comprobar(_j.techo_encima(), "se detecta el techo encima de la cabeza")
	Input.action_release("agachar")
	await _fisica(120)
	_comprobar(_j.agachado and absf(forma.height - Jugador.ALTURA_AGACHADO) < 0.01, "con techo encima sigue agachado al soltar Ctrl")
	Input.action_press("mover_arriba")
	Input.action_press("correr")
	await _fisica(40)
	var v_techo := _velocidad_horizontal()
	_soltar_teclas()
	_comprobar(v_techo < v_andar * 0.6, "bajo el techo tampoco corre (%.2f m/s)" % v_techo)
	_poner_a_leo(base, _j.camara.yaw)
	await _fisica(20)
	# Quitado el techo, se levanta solo.
	losa.queue_free()
	await _fisica(20)
	_comprobar(not _j.agachado and absf(forma.height - alto_pie) < 0.001, "sin techo se levanta")
	# Un techo por encima de su altura de pie no lo retiene.
	Input.action_press("agachar")
	await _fisica(20)
	var alta := _crear_losa(base, 1.75)
	await _fisica(10)
	Input.action_release("agachar")
	await _fisica(30)
	_comprobar(not _j.agachado, "con un techo a 1,75 m (más alto que él) se levanta")
	alta.queue_free()
	await _fisica(10)
	_soltar_teclas()


## Una losa de 4 × 0,2 × 4 m con su cara inferior a `altura` metros sobre `pos` (capa 1, como el mundo).
func _crear_losa(pos: Vector3, altura: float) -> StaticBody3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	var cs := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(4, 0.2, 4)
	cs.shape = caja
	cuerpo.add_child(cs)
	_mapa.add_child(cuerpo)
	cuerpo.global_position = pos + Vector3(0, altura + 0.1, 0)
	return cuerpo


# --- Saltar contra los límites ---------------------------------------------------------------------------------

func _cerca_de_salida(p: Vector3, radio: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group("salida"):
		if (n as Node3D).global_position.distance_to(p) < radio:
			return true
	return false


func _distancia_a_borde(p: Vector2, poligono: PackedVector2Array) -> float:
	var mejor := INF
	for i in poligono.size():
		var c := Geometry2D.get_closest_point_to_segment(p, poligono[i], poligono[(i + 1) % poligono.size()])
		mejor = minf(mejor, c.distance_to(p))
	return mejor


## Corre hacia fuera del polígono saltando sin parar (Espacio cada 0,7 s): Leo no debe salir.
func _empujar_saltando(id: String, i: int, pol: PackedVector2Array, segundos: float) -> Dictionary:
	var n := pol.size()
	var a := pol[i]
	var b := pol[(i + 1) % n]
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var hacia_dentro := Vector2(-dir.y, dir.x)
	if not Geometry2D.is_point_in_polygon(mid + hacia_dentro * 0.6, pol):
		hacia_dentro = -hacia_dentro
	var s2 := mid + hacia_dentro * 2.0
	var col: Dictionary = _mapa.call("_columna_suelo", s2.x, s2.y)
	var ys := float(col["suelo"])
	if is_nan(ys) or float(col["obstaculo"]) > 0.4:
		return {}
	var inicio := Vector3(s2.x, ys + 0.05, s2.y)
	if not _mapa.punto_dentro(inicio) or _cerca_de_salida(inicio, 6.0):
		return {}
	var afuera := -hacia_dentro
	_poner_a_leo(inicio, atan2(-afuera.x, -afuera.y))
	await _fisica(6)
	var saltos0 := _j.saltos
	Input.action_press("mover_arriba")
	Input.action_press("correr")
	var ticks := int(segundos * float(Engine.physics_ticks_per_second))
	var cada := int(0.7 * float(Engine.physics_ticks_per_second))
	var min_borde := INF
	for t in ticks:
		if t % cada == 0:
			_espacio()
		await get_tree().physics_frame
		var p3 := _j.global_position
		min_borde = minf(min_borde, _distancia_a_borde(Vector2(p3.x, p3.z), pol))
	_soltar_teclas()
	var p := _j.global_position
	return {"fuera": not _mapa.punto_dentro(p), "borde": min_borde, "saltos": _j.saltos - saltos0}


## Mina interior: desde la llegada, corre y salta 3 s en 8 direcciones; no sale del polígono, no cae por debajo de la cueva
## ni sube por encima de ella (el techo y la roca lo paran).
func _prueba_salto_en_cueva() -> void:
	for s: Node in get_tree().get_nodes_in_group("salida"):
		(s as Area3D).set_deferred("monitoring", false)   # que correr no lo saque del mapa
	await _fisica(2)
	var llegada := (_mapa.call("marcador", "Llegada_Interior") as Marker3D).global_position
	var caja: AABB = _mapa.call("aabb_mapa")
	var saltos0 := _j.saltos
	var fuera := 0
	var fuera_vertical := 0
	var ymax := -INF
	for k in 8:
		var yaw := TAU * float(k) / 8.0
		_poner_a_leo(llegada + Vector3(0, 0.05, 0), yaw)
		await _fisica(6)
		Input.action_press("mover_arriba")
		Input.action_press("correr")
		for t in 360:
			if t % 84 == 0:
				_espacio()
			await get_tree().physics_frame
			ymax = maxf(ymax, _j.global_position.y)
		_soltar_teclas()
		var p := _j.global_position
		print("      dirección ", k, ": saltos ", _j.saltos - saltos0, " (acumulados), recorrió ", "%.1f" % Vector2(p.x - llegada.x, p.z - llegada.z).length(), " m, en suelo ", _j.is_on_floor())
		if not _mapa.punto_dentro(p):
			fuera += 1
		if p.y < caja.position.y - 1.0 or p.y > caja.end.y + 1.0 or p.y > llegada.y + 6.0:
			fuera_vertical += 1
	print("   mina_interior: 8 direcciones, ", _j.saltos - saltos0, " saltos, altura máxima de Leo ", "%.2f" % (ymax - llegada.y), " m sobre la llegada, atascos resueltos ", _j.atascos_resueltos)
	_comprobar(_j.atascos_resueltos == 0, "mina_interior: ocho direcciones sin rescates antiatasco")
	# Regresión: correr y saltar de frente contra la roca de la llegada dejaba a Leo encajado en una grieta, colgado en el
	# aire (ni toca suelo ni cae). La colisión lisa debe evitarlo sin recurrir al antiatasco.
	_poner_a_leo(llegada + Vector3(0, 0.05, 0), 0.0)
	await _fisica(6)
	Input.action_press("mover_arriba")
	Input.action_press("correr")
	_espacio()
	await _fisica(120)
	_soltar_teclas()
	await _esperar(3.0)
	_comprobar(_j.is_on_floor() and _j.global_position.y < llegada.y + 3.0, "mina_interior: tras correr y saltar contra la roca de la llegada, Leo no se queda colgado en el aire")
	_comprobar(_j.atascos_resueltos == 0, "mina_interior: regresión de la roca sin rescates antiatasco")
	_comprobar(_j.saltos - saltos0 >= 8, "mina_interior: Leo saltó de verdad (%d saltos)" % (_j.saltos - saltos0))
	_comprobar(fuera == 0, "mina_interior: corriendo y saltando en 8 direcciones no sale del polígono (%d fuera)" % fuera)
	_comprobar(fuera_vertical == 0, "mina_interior: ni cae ni sube fuera de la cueva (%d casos)" % fuera_vertical)


func _prueba_salto_contra_limites(id: String) -> void:
	print("[saltar contra los límites: %s]" % id)
	var pol: PackedVector2Array = _mapa.poligono_limites
	_comprobar(pol.size() >= 3, "%s: tiene polígono de límites" % id)
	var probados := 0
	var fuera := 0
	var saltos := 0
	var llegaron := 0
	for i in pol.size():
		if probados >= 6:
			break
		var r: Dictionary = await _empujar_saltando(id, i, pol, 2.6)
		if r.is_empty():
			continue
		probados += 1
		saltos += int(r["saltos"])
		if bool(r["fuera"]):
			fuera += 1
		if float(r["borde"]) < 1.0:
			llegaron += 1
	print("   ", id, ": ", probados, " lados probados corriendo y saltando contra el muro; saltos ", saltos, "; llegó al muro en ", llegaron)
	if id == "mina_interior":
		# En la cueva el borde del polígono es un rectángulo dentro de la roca: sus lados no se pueden pisar. Los límites
		# de verdad son la roca y el techo, así que se corre y salta en todas direcciones desde la llegada.
		await _prueba_salto_en_cueva()
	else:
		_comprobar(probados >= 2, "%s: se probaron al menos 2 lados (%d)" % [id, probados])
		_comprobar(saltos >= probados * 2, "%s: Leo saltó de verdad durante las pruebas (%d saltos)" % [id, saltos])
	_comprobar(fuera == 0, "%s: saltando contra el muro Leo no sale del mapa (%d de %d lo sacaron)" % [id, fuera, probados])
	if LimitesMapa.tipo_valla(id) != "ninguna":
		_comprobar(llegaron >= 1, "%s: llegó hasta el muro saltando (%d de %d)" % [id, llegaron, probados])
	# Control en la granja: sin muro ni red de seguridad, el mismo empujón saltando sí lo saca (la prueba mide algo).
	if id == "granja":
		_j.collision_mask &= ~Jugador.CAPA_LIMITES
		_j._mapa = null
		var r2: Dictionary = {}
		for i in pol.size():
			r2 = await _empujar_saltando(id, i, pol, 3.0)
			if not r2.is_empty():
				break
		_comprobar(not r2.is_empty() and bool(r2["fuera"]), "control: sin muro, el mismo empujón saltando saca a Leo del polígono")
		_j.collision_mask |= Jugador.CAPA_LIMITES
		_j.configurar_para_mapa(_mapa)
		var seguro := (_mapa.call("marcador", "Spawn_Protagonista") as Marker3D).global_position + Vector3(0, 0.3, 0)
		_poner_a_leo(seguro, 0.0)
		await _fisica(30)
