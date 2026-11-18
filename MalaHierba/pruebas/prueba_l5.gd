extends Node
## Prueba automática de L5 (interiores de las casas y puertas).
## Se ejecuta con:
##   herramientas/godot.ps1 --headless --path MalaHierba --scene res://pruebas/prueba_l5.tscn
## Imprime «PRUEBA OK (N comprobaciones)» o «PRUEBA FALLO: <motivo>» y sale con código 0 o 1.

const ALTURA_LEO := 1.75

const CASAS_PUEBLO: Array[Dictionary] = [
	{"id": "tienda", "marcador": "Puerta_Tienda", "malla_puerta": "tienda_Puerta", "prefijo": "tienda_"},
	{"id": "herreria", "marcador": "Puerta_Herreria", "malla_puerta": "herreria_Puerta", "prefijo": "herreria_"},
	{"id": "taberna", "marcador": "Puerta_Taberna", "malla_puerta": "taberna_Puerta", "prefijo": "taberna_"},
	{"id": "casa_alcalde", "marcador": "Puerta_Alcalde", "malla_puerta": "alcalde_Puerta", "prefijo": "alcalde_"},
	{"id": "capilla", "marcador": "Puerta_Capilla", "malla_puerta": "capilla_Puerta", "prefijo": "capilla_"},
	{"id": "casita_a", "marcador": "Puerta_CasitaA", "malla_puerta": "casita_a_Puerta", "prefijo": "casita_a_"},
	{"id": "casita_b", "marcador": "Puerta_CasitaB", "malla_puerta": "casita_b_Puerta", "prefijo": "casita_b_"},
]

const TODOS_INTERIORES: Array[String] = [
	"casa_leo",
	"tienda",
	"herreria",
	"taberna",
	"casa_alcalde",
	"capilla",
	"casita_a",
	"casita_b",
]

var _fallos: Array[String] = []
var _total: int = 0


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _frames(n: int = 3) -> void:
	for _i in n:
		await get_tree().process_frame


func _fisica(n: int = 4) -> void:
	for _i in n:
		await get_tree().physics_frame


func _terminar() -> void:
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)), " (%d comprobaciones)" % _total)
		get_tree().quit(1)


func _ejecutar() -> void:
	await _frames(2)
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_l5.json"
	Juego.nueva_partida("PruebaL5")
	Juego.pausar_tiempo(true)

	await _probar_escala_y_casas_pueblo()
	await _probar_puertas_pueblo()
	await _probar_puerta_y_cama_casa_leo()
	await _probar_arcon_casa_leo()
	await _probar_objetos_y_horarios_interiores()
	await _probar_limites_camara_y_minimapa()

	_terminar()


# --- Utilidades de geometría --------------------------------------------------

func _aabb_mundial_malla(mi: MeshInstance3D) -> AABB:
	if mi == null or mi.mesh == null:
		return AABB()
	return mi.global_transform * mi.mesh.get_aabb()


func _buscar_malla(raiz: Node, nombre: String) -> MeshInstance3D:
	if raiz == null:
		return null
	var lista := raiz.find_children(nombre + "*", "MeshInstance3D", true, false)
	if not lista.is_empty():
		return lista[0] as MeshInstance3D
	var n := raiz.find_child(nombre + "*", true, false)
	if n is MeshInstance3D:
		return n as MeshInstance3D
	if n != null:
		for h in n.find_children("*", "MeshInstance3D", true, false):
			return h as MeshInstance3D
	return null


func _aabb_prefijo(raiz: Node, prefijo: String) -> AABB:
	var primero := true
	var total := AABB()
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if not str(mi.name).begins_with(prefijo) and not (mi.get_parent() != null and str(mi.get_parent().name).begins_with(prefijo)):
			continue
		var caja := _aabb_mundial_malla(mi)
		if primero:
			total = caja
			primero = false
		else:
			total = total.merge(caja)
	return total


func _colocar_jugador_mirando(j: Node3D, pos: Vector3, hacia: Vector3) -> void:
	var dir := Vector3(hacia.x - pos.x, 0.0, hacia.z - pos.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var yaw := atan2(-dir.x, -dir.z)
	if j.has_method("colocar"):
		j.call("colocar", pos, yaw, yaw)
	else:
		j.global_position = pos
	j.set("direccion", dir)


func _contar_dormir() -> int:
	var n := 0
	for it: Node in get_tree().get_nodes_in_group("interactuable"):
		if str(it.call("texto_interaccion")).begins_with("Dormir"):
			n += 1
	return n


func _ir(id: String, llegada: String = "Spawn_Protagonista") -> void:
	await Escenas.ir_a_mapa(id, llegada)
	await _frames(4)
	await _fisica(4)
	Interfaz.cerrar_todo()


# --- 1. Escala de Leo, casas bajas agrandadas y holguras en el pueblo ---------

func _probar_escala_y_casas_pueblo() -> void:
	print("[1. Casas agrandadas, puertas > Leo y holguras en el pueblo]")
	_comprobar(is_equal_approx(EscalaPersonaje.ESCALA, 0.89), "EscalaPersonaje.ESCALA se mantiene en 0.89 (ni Leo ni los vecinos se han encogido)")

	await _ir("pueblo")
	var mapa := Escenas.mapa_actual_nodo()
	var j := Escenas.jugador()
	_comprobar(mapa != null and Juego.mapa_actual == "pueblo", "el pueblo se carga correctamente")
	_comprobar(j != null, "Leo existe en el pueblo")
	_comprobar(_contar_dormir() == 0, "en el exterior del pueblo no hay ningún «Dormir»")

	# Comprobar que las 4 casas que tenían el alero bajo ahora superan ampliamente su altura antigua
	var minimos_cumbrera := {
		"casita_a_": 5.2,
		"casita_b_": 5.1,
		"tienda_": 6.2,
		"herreria_": 5.4,
	}
	for prefijo: String in minimos_cumbrera.keys():
		var caja_casa := _aabb_prefijo(mapa, prefijo)
		var alto_total := caja_casa.size.y
		var min_esperado: float = float(minimos_cumbrera[prefijo])
		_comprobar(alto_total >= min_esperado, "la casa «%s» se ha agrandado (cumbrera %.2f m >= %.2f m)" % [prefijo, alto_total, min_esperado])

	# Comprobar las 7 puertas del pueblo: existen, miden > 2,00 m (> 1,75 m de Leo) y caben bajo la casa
	for info: Dictionary in CASAS_PUEBLO:
		var id_casa := str(info["id"])
		var nombre_malla := str(info["malla_puerta"])
		var nombre_marc := str(info["marcador"])
		var prefijo := str(info["prefijo"])

		var mi_puerta := _buscar_malla(mapa, nombre_malla)
		_comprobar(mi_puerta != null, "existe la malla de puerta «%s» en el pueblo" % nombre_malla)
		if mi_puerta != null:
			var aabb_p := _aabb_mundial_malla(mi_puerta)
			var alto_puerta := aabb_p.size.y
			var ancho_puerta := maxf(aabb_p.size.x, aabb_p.size.z)
			var caja_casa := _aabb_prefijo(mapa, prefijo)
			_comprobar(alto_puerta > ALTURA_LEO + 0.30, "la puerta «%s» mide %.2f m (> %.2f m de Leo)" % [nombre_malla, alto_puerta, ALTURA_LEO])
			_comprobar(ancho_puerta >= 0.95, "la puerta «%s» tiene ancho suficiente (%.2f m)" % [nombre_malla, ancho_puerta])
			_comprobar(aabb_p.end.y + 0.15 < caja_casa.end.y, "la puerta «%s» cabe con holgura dentro de su fachada (tope puerta %.2f m < cumbrera %.2f m)" % [nombre_malla, aabb_p.end.y, caja_casa.end.y])

		var marc := mapa.call("marcador", nombre_marc) as Marker3D
		_comprobar(marc != null, "existe el marcador «%s» para la casa «%s»" % [nombre_marc, id_casa])

	# Comprobar que las casas agrandadas no pisan el pozo (centro de la plaza)
	for info: Dictionary in CASAS_PUEBLO:
		var prefijo := str(info["prefijo"])
		var caja := _aabb_prefijo(mapa, prefijo)
		var caja_planta := AABB(Vector3(caja.position.x, -1.0, caja.position.z), Vector3(caja.size.x, 10.0, caja.size.z))
		_comprobar(not caja_planta.has_point(Vector3(0.0, 0.0, 0.0)), "la casa «%s» no invade el pozo de la plaza" % prefijo)

	# Comprobar que los vecinos en el pueblo caben sin chocar con edificios ni vallas a las 08:30, 12:30 y 19:30
	var vecinos_nodo := mapa.get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vecinos_nodo != null, "existe Objetos/Vecinos en el pueblo")
	if vecinos_nodo != null:
		for hora in [510, 750, 1170]:
			Juego.minutos = hora
			vecinos_nodo.sincronizar(true)
			await _fisica(2)
			for npc_v: Variant in vecinos_nodo.npcs.values():
				var npc := npc_v as Npc
				if npc == null:
					continue
				var libre := AyudasL4b.cabe(mapa, npc.global_position, 0.30, 1.5)
				_comprobar(libre, "el vecino «%s» a las %02d:%02d no queda pisado por casas ni vallas en %v" % [npc.id, hora / 60, hora % 60, npc.global_position])


# --- 2. Entrar y salir por cada una de las 7 puertas del pueblo ---------------

func _probar_puertas_pueblo() -> void:
	print("[2. Entrar y salir por las 7 puertas del pueblo]")
	for info: Dictionary in CASAS_PUEBLO:
		var id_casa := str(info["id"])
		var nombre_marc := str(info["marcador"])

		if Juego.mapa_actual != "pueblo":
			await _ir("pueblo")

		var mapa_pueblo := Escenas.mapa_actual_nodo()
		var j := Escenas.jugador()
		var marc := mapa_pueblo.call("marcador", nombre_marc) as Marker3D
		var nodo_puerta := mapa_pueblo.get_node_or_null("Salidas/Puerta_" + id_casa) as Node3D
		_comprobar(nodo_puerta != null and nodo_puerta is PuertaMapa, "en el pueblo existe PuertaMapa «Puerta_%s»" % id_casa)
		if marc == null or nodo_puerta == null:
			continue

		_comprobar(nodo_puerta.is_in_group("puerta") and nodo_puerta.is_in_group("interactuable"), "«Puerta_%s» está en los grupos puerta e interactuable" % id_casa)

		# Colocar a Leo en el marcador mirando hacia la puerta
		var delante := marc.global_position + marc.global_basis.z * 1.12
		_colocar_jugador_mirando(j, delante + Vector3.UP * 0.05, nodo_puerta.global_position)
		await _fisica(3)
		(j as Jugador).camara.mirar_hacia(nodo_puerta.global_position + Vector3.UP * 0.95)
		j.call("_actualizar_interactuable")

		var obj: Node = j.get("_objetivo")
		_comprobar(obj == nodo_puerta, "frente a «%s» Leo selecciona la puerta de «%s»" % [nombre_marc, id_casa])
		var cartel: String = Interfaz.texto_accion()
		_comprobar(cartel.begins_with("E  ·  Entrar"), "el cartel de acción en «%s» dice «%s»" % [id_casa, cartel])
		var resaltador := j.get("_resaltador") as Node3D
		_comprobar(resaltador != null and resaltador.visible, "el resaltador (anillo + flecha) es visible en la puerta de «%s»" % id_casa)

		# Entrar por la puerta
		nodo_puerta.call("interactuar", j)
		var tope := 0
		while (Escenas.en_transicion or Juego.mapa_actual != id_casa) and tope < 240:
			await get_tree().process_frame
			tope += 1
		await _frames(4)
		await _fisica(4)

		_comprobar(Juego.mapa_actual == id_casa, "al usar la puerta se entra en el interior «%s» (mapa actual: «%s»)" % [id_casa, Juego.mapa_actual])
		var mapa_int := Escenas.mapa_actual_nodo()
		var j_int := Escenas.jugador()
		_comprobar(mapa_int != null and j_int != null, "el interior «%s» tiene mapa y jugador" % id_casa)
		if mapa_int == null or j_int == null:
			continue

		var m_entrada := mapa_int.call("marcador", "Entrada") as Marker3D
		_comprobar(m_entrada != null, "el interior «%s» tiene marcador Entrada" % id_casa)
		if m_entrada != null:
			var dist_ent := Vector2(j_int.global_position.x - m_entrada.global_position.x, j_int.global_position.z - m_entrada.global_position.z).length()
			_comprobar(dist_ent < 0.85, "al entrar en «%s» Leo aparece en Entrada (dist %.2f m)" % [id_casa, dist_ent])
		var dir_ent: Vector3 = j_int.get("direccion")
		_comprobar(dir_ent.z < -0.7, "al entrar en «%s» Leo mira hacia dentro de la sala (dir %v)" % [id_casa, dir_ent])

		# Comprobar que la puerta interior mide más que Leo
		var mi_puerta_int := _buscar_malla(mapa_int, "Puerta_hoja")
		if mi_puerta_int == null:
			mi_puerta_int = _buscar_malla(mapa_int, "Puerta_salida")
		_comprobar(mi_puerta_int != null, "el interior «%s» tiene malla de puerta de salida" % id_casa)
		if mi_puerta_int != null:
			var alto_p_int := _aabb_mundial_malla(mi_puerta_int).size.y
			_comprobar(alto_p_int > ALTURA_LEO + 0.30, "la puerta interior de «%s» mide %.2f m (> %.2f m de Leo)" % [id_casa, alto_p_int, ALTURA_LEO])

		# Salir por la puerta interior de vuelta al pueblo
		var m_salida := mapa_int.call("marcador", "Salida") as Marker3D
		var puerta_sal := mapa_int.get_node_or_null("Salidas/Puerta_pueblo") as Node3D
		_comprobar(m_salida != null and puerta_sal != null and puerta_sal is PuertaMapa, "el interior «%s» tiene marcador Salida y PuertaMapa Puerta_pueblo" % id_casa)
		if m_salida != null and puerta_sal != null:
			_colocar_jugador_mirando(j_int, m_salida.global_position + Vector3(0.0, 0.05, -1.05), puerta_sal.global_position)
			await _fisica(3)
			(j_int as Jugador).camara.mirar_hacia(puerta_sal.global_position + Vector3.UP * 0.95)
			j_int.call("_actualizar_interactuable")
			_comprobar(Interfaz.texto_accion().begins_with("E  ·  Salir"), "junto a la salida de «%s» el cartel ofrece «%s»" % [id_casa, Interfaz.texto_accion()])

			puerta_sal.call("interactuar", j_int)
			tope = 0
			while (Escenas.en_transicion or Juego.mapa_actual != "pueblo") and tope < 240:
				await get_tree().process_frame
				tope += 1
			await _frames(4)
			await _fisica(4)

			_comprobar(Juego.mapa_actual == "pueblo", "al salir de «%s» se regresa al pueblo" % id_casa)
			var mapa_ext := Escenas.mapa_actual_nodo()
			var j_ext := Escenas.jugador()
			var marc_ext := mapa_ext.call("marcador", nombre_marc) as Marker3D if mapa_ext != null else null
			if j_ext != null and marc_ext != null:
				var dist_sal := Vector2(j_ext.global_position.x - marc_ext.global_position.x, j_ext.global_position.z - marc_ext.global_position.z).length()
				_comprobar(dist_sal < 0.85, "al salir de «%s» Leo aparece en «%s» (dist %.2f m)" % [id_casa, nombre_marc, dist_sal])
				var dir_esperada := Vector3(marc_ext.global_transform.basis.z.x, 0.0, marc_ext.global_transform.basis.z.z).normalized()
				var dir_real: Vector3 = j_ext.get("direccion")
				_comprobar(dir_real.dot(dir_esperada) > 0.8, "al salir de «%s» Leo mira hacia fuera de la fachada (dot %.2f)" % [id_casa, dir_real.dot(dir_esperada)])


# --- 3. Puerta de la cabaña de la granja y «Dormir» exclusivo en casa_leo -----

func _probar_puerta_y_cama_casa_leo() -> void:
	print("[3. Puerta de la cabaña en la granja y «Dormir» exclusivo en casa_leo]")
	await _ir("granja")

	var granja := Escenas.mapa_actual_nodo()
	var j := Escenas.jugador()
	_comprobar(granja != null and Juego.mapa_actual == "granja", "la granja está cargada")
	_comprobar(_contar_dormir() == 0, "en el exterior de la granja hay 0 «Dormir»")

	var mi_puerta_cab := _buscar_malla(granja, "Cabana_puerta")
	_comprobar(mi_puerta_cab != null, "existe la malla Cabana_puerta en la granja")
	if mi_puerta_cab != null:
		var alto_cab := _aabb_mundial_malla(mi_puerta_cab).size.y
		_comprobar(alto_cab > ALTURA_LEO + 0.30, "Cabana_puerta mide %.2f m (> %.2f m de Leo)" % [alto_cab, ALTURA_LEO])

	var marc_cab := granja.call("marcador", "Puerta_Cabana") as Marker3D
	var puerta_cab := granja.get_node_or_null("Salidas/Puerta_casa_leo") as Node3D
	_comprobar(marc_cab != null and puerta_cab != null and puerta_cab is PuertaMapa, "la granja tiene Puerta_Cabana y Puerta_casa_leo")

	_colocar_jugador_mirando(j, marc_cab.global_position + Vector3(0.0, 0.05, 0.5), marc_cab.global_position + Vector3(0.0, 0.05, -1.0))
	await _fisica(3)
	(j as Jugador).camara.mirar_hacia(puerta_cab.global_position + Vector3.UP * 0.9)
	j.call("_actualizar_interactuable")
	_comprobar(j.get("_objetivo") == puerta_cab and Interfaz.texto_accion() == "E  ·  Entrar en la cabaña", "frente a la cabaña aparece «E · Entrar en la cabaña»")

	# Entrar en casa_leo
	if puerta_cab != null:
		puerta_cab.call("interactuar", j)
	var tope := 0
	while (Escenas.en_transicion or Juego.mapa_actual != "casa_leo") and tope < 240:
		await get_tree().process_frame
		tope += 1
	await _frames(4)
	await _fisica(4)
	_comprobar(Juego.mapa_actual == "casa_leo", "al entrar por la puerta de la cabaña se carga casa_leo")
	_comprobar(_contar_dormir() == 1, "dentro de casa_leo hay exactamente 1 «Dormir»")

	var casa := Escenas.mapa_actual_nodo()
	var cama := casa.get_node_or_null("Objetos/Cama/PuntoDormir") as Interactuable
	_comprobar(cama != null and cama.texto_interaccion() == "Dormir en la cama", "en casa_leo existe PuntoDormir con «Dormir en la cama»")

	# Probar dormir desde la cama de casa_leo
	var dia_antes := Juego.dia
	Juego.dormir()
	var t0 := Time.get_ticks_msec()
	while (Escenas.en_transicion or Juego.dia == dia_antes) and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	await _frames(4)
	_comprobar(Juego.dia == dia_antes + 1, "dormir avanza al día siguiente")

	# Volver a entrar en casa_leo y salir por su puerta a Puerta_Cabana
	await _ir("casa_leo", "Entrada")
	casa = Escenas.mapa_actual_nodo()
	var puerta_sal := casa.get_node_or_null("Salidas/Puerta_granja") as Node3D
	_comprobar(puerta_sal != null and puerta_sal is PuertaMapa, "en casa_leo existe Puerta_granja")
	if puerta_sal != null:
		puerta_sal.call("interactuar", Escenas.jugador())
		tope = 0
		while (Escenas.en_transicion or Juego.mapa_actual != "granja") and tope < 240:
			await get_tree().process_frame
			tope += 1
		await _frames(4)
		await _fisica(4)
		_comprobar(Juego.mapa_actual == "granja", "al salir de casa_leo se vuelve a la granja")
		var j_ext := Escenas.jugador()
		var dir_ext: Vector3 = j_ext.get("direccion")
		_comprobar(dir_ext.z > 0.7, "al salir de la cabaña Leo mira hacia el sur (hacia el patio de la granja)")


# --- 4. Arcón de 30 huecos y persistencia en casa_leo -------------------------

func _probar_arcon_casa_leo() -> void:
	print("[4. Arcón de 30 huecos, carta y calendario en casa_leo]")
	await _ir("casa_leo", "Entrada")

	var casa := Escenas.mapa_actual_nodo()
	var inter := casa.get_node_or_null("Objetos/InteraccionesInterior") as InteraccionesInterior
	_comprobar(inter != null, "existe Objetos/InteraccionesInterior en casa_leo")
	if inter == null:
		return

	# Comprobar carta de la abuela Rosa
	var n_carta: Interactuable = inter.nodo_interaccion("Interaccion_carta_abuela")
	_comprobar(n_carta != null and n_carta.texto_interaccion() == "Leer la carta de la abuela Rosa", "existe «Leer la carta de la abuela Rosa» en casa_leo")
	if n_carta != null:
		n_carta.interactuar(Escenas.jugador())
		await _frames(2)
		_comprobar(Interfaz.ocupada(), "leer la carta abre el cuadro de diálogo")
		Interfaz.cerrar_todo()

	# Comprobar calendario
	var n_cal: Interactuable = inter.nodo_interaccion("calendario")
	_comprobar(n_cal != null and n_cal.texto_interaccion() == "Mirar el calendario", "existe «Mirar el calendario» en casa_leo")
	if n_cal != null:
		n_cal.interactuar(Escenas.jugador())
		await _frames(2)
		_comprobar(Interfaz.ocupada(), "mirar el calendario abre el cuadro de diálogo con la fecha")
		Interfaz.cerrar_todo()

	# Comprobar arcón: abrir panel, meter y sacar objetos, y persistencia al salir y guardar/cargar
	var n_arcon: Interactuable = inter.nodo_interaccion("arcon")
	_comprobar(n_arcon != null and n_arcon.texto_interaccion() == "Abrir el arcón", "existe «Abrir el arcón» en casa_leo")
	if n_arcon != null:
		n_arcon.interactuar(Escenas.jugador())
		await _frames(2)
		_comprobar(Interfaz.ocupada(), "al interactuar con el arcón se abre el menú del arcón")
		Interfaz.cerrar_todo()

	Juego.anadir_objeto("madera", 7)
	var madera_antes := Juego.cantidad("madera")
	var arcon_arr: Array = InteraccionesInterior.ranuras_arcon()
	_comprobar(arcon_arr.size() == InteraccionesInterior.HUECOS_ARCON, "el arcón tiene %d huecos" % InteraccionesInterior.HUECOS_ARCON)

	var ok_guardar := InteraccionesInterior.guardar_en_arcon("madera", 5)
	_comprobar(ok_guardar and Juego.cantidad("madera") == madera_antes - 5, "guardar 5 de madera en el arcón los descuenta de la mochila")
	_comprobar(InteraccionesInterior.cantidad_en_arcon("madera") == 5, "el arcón registra 5 de madera")

	# Salir a la granja, guardar/cargar y volver a entrar para verificar persistencia
	await _ir("granja", "Puerta_Cabana")
	_comprobar(Juego.guardar(), "se guarda la partida con objetos en el arcón")
	Juego.estado_mapas = {}
	_comprobar(Juego.cargar(), "se recarga la partida guardada")

	await _ir("casa_leo", "Entrada")
	var inter2 := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/InteraccionesInterior") as InteraccionesInterior
	_comprobar(inter2 != null, "InteraccionesInterior sigue presente tras recargar casa_leo")
	_comprobar(InteraccionesInterior.cantidad_en_arcon("madera") == 5, "el arcón conserva los 5 de madera tras cambiar de mapa y guardar/cargar")
	var madera_pre_sacar := Juego.cantidad("madera")
	var ok_sacar := InteraccionesInterior.sacar_de_arcon("madera", 5)
	_comprobar(ok_sacar and Juego.cantidad("madera") == madera_pre_sacar + 5 and InteraccionesInterior.cantidad_en_arcon("madera") == 0, "sacar los 5 de madera del arcón los devuelve a la mochila")


# --- 5. Todos los objetos interactuables y horarios de los 8 interiores -------

func _probar_objetos_y_horarios_interiores() -> void:
	print("[5. Objetos interactuables de los 8 interiores, resaltado y horarios]")
	for id_int: String in TODOS_INTERIORES:
		Juego.minutos = 11 * 60 if id_int != "taberna" else 14 * 60
		await _ir(id_int, "Entrada")

		var mapa := Escenas.mapa_actual_nodo()
		var j := Escenas.jugador()
		var inter := mapa.get_node_or_null("Objetos/InteraccionesInterior") as InteraccionesInterior
		_comprobar(inter != null, "el interior «%s» tiene InteraccionesInterior" % id_int)

		var dormir_aqui := _contar_dormir()
		if id_int == "casa_leo":
			_comprobar(dormir_aqui == 1, "en «casa_leo» hay exactamente 1 «Dormir»")
		else:
			_comprobar(dormir_aqui == 0, "en «%s» hay 0 «Dormir» (encontrados: %d)" % [id_int, dormir_aqui])

		var lista_datos: Array = Datos.interacciones_de(id_int)
		_comprobar(lista_datos.size() >= 2, "«%s» tiene al menos 2 objetos definidos en interacciones.json (%d)" % [id_int, lista_datos.size()])

		for d_var: Variant in lista_datos:
			var d: Dictionary = d_var as Dictionary
			var id_obj := str(d.get("id", ""))
			var nom_marc := str(d.get("marcador", "Interaccion_" + id_obj))
			if id_int == "casa_leo" and (id_obj == "cama" or nom_marc == "Interaccion_cama"):
				var n_cama := mapa.get_node_or_null("Objetos/Cama/PuntoDormir") as Interactuable
				_comprobar(n_cama != null and n_cama.objetivo_resaltado != null, "en «casa_leo» la cama tiene Interactuable y malla de resaltado")
				continue

			var nodo_it: Interactuable = inter.nodo_interaccion(nom_marc) if inter != null else null
			_comprobar(nodo_it != null and nodo_it.activo, "en «%s» existe el interactuable activo «%s»" % [id_int, nom_marc])
			if nodo_it == null:
				continue

			_comprobar(nodo_it.objetivo_resaltado != null, "en «%s» el objeto «%s» tiene malla objetivo_resaltado asignada" % [id_int, nom_marc])

			# Colocar a Leo frente al objeto y comprobar que puede seleccionarlo e interactuar
			var pos_obj: Vector3 = nodo_it.global_position
			var pos_leo := Vector3(pos_obj.x, 0.05, pos_obj.z + 1.05)
			if absf(pos_obj.z) > 2.0 and pos_obj.z > 0.0:
				pos_leo = Vector3(pos_obj.x, 0.05, pos_obj.z - 1.05)
			_colocar_jugador_mirando(j, pos_leo, pos_obj)
			await _fisica(2)
			(j as Jugador).camara.mirar_hacia(pos_obj + Vector3.UP * 0.8)
			j.call("_actualizar_interactuable")
			var malla := nodo_it.objetivo_resaltado as MeshInstance3D
			if j.get("_objetivo") == null and malla != null and malla.mesh != null:
				(j as Jugador).camara.mirar_hacia(_aabb_mundial_malla(malla).get_center())
				j.call("_actualizar_interactuable")
			_comprobar(j.get("_objetivo") != null, "en «%s» Leo detecta un interactuable al acercarse a «%s»" % [id_int, nom_marc])

			nodo_it.interactuar(j)
			await _frames(2)
			var hubo_respuesta: bool = Interfaz.ocupada()
			_comprobar(hubo_respuesta, "en «%s» interactuar con «%s» (%s) abre respuesta en la interfaz" % [id_int, nom_marc, nodo_it.texto_interaccion()])
			Interfaz.cerrar_todo()

	# Comprobar horarios de apertura/cierre y presencia de dueños en tienda, herrería, taberna y alcaldía
	# Tienda: abierta a las 11:00 (con Mateo), cerrada a las 20:00 (sin Mateo)
	Juego.minutos = 11 * 60
	await _ir("tienda", "Entrada")
	var vec_tienda := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vec_tienda != null and vec_tienda.npcs.has("mateo"), "a las 11:00 Mateo está dentro de la tienda")
	Juego.minutos = 20 * 60
	vec_tienda.sincronizar(true)
	await _frames(2)
	_comprobar(not vec_tienda.npcs.has("mateo"), "a las 20:00 Mateo ya no está en el mostrador de la tienda")
	var res_tienda_cerrada := InteraccionesInterior.usar_mostrador_tienda()
	_comprobar(res_tienda_cerrada == "cerrado" and Interfaz.ocupada(), "a las 20:00 el mostrador de la tienda avisa que está cerrada")
	Interfaz.cerrar_todo()

	# Herrería: abierta a las 11:00 (con Clara), cerrada a las 19:00
	Juego.minutos = 11 * 60
	await _ir("herreria", "Entrada")
	var vec_herr := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vec_herr != null and vec_herr.npcs.has("clara"), "a las 11:00 Clara está dentro de la herrería")
	Juego.minutos = 19 * 60
	vec_herr.sincronizar(true)
	await _frames(2)
	_comprobar(not vec_herr.npcs.has("clara"), "a las 19:00 Clara ya no está en la herrería")
	var res_herr_cerrada := InteraccionesInterior.usar_yunque()
	_comprobar(res_herr_cerrada == "cerrado" and Interfaz.ocupada(), "a las 19:00 el yunque de la herrería avisa que está cerrada")
	Interfaz.cerrar_todo()

	# Taberna: cerrada a las 09:00, abierta a las 14:00 (con Ramón)
	Juego.minutos = 9 * 60
	await _ir("taberna", "Entrada")
	var vec_tab := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vec_tab != null and not vec_tab.npcs.has("ramon"), "a las 09:00 Ramón no está en la barra de la taberna")
	var res_tab_cerrada := InteraccionesInterior.usar_barra_taberna()
	_comprobar(res_tab_cerrada == "cerrado" and Interfaz.ocupada(), "a las 09:00 la barra de la taberna avisa que está cerrada")
	Interfaz.cerrar_todo()
	Juego.minutos = 14 * 60
	vec_tab.sincronizar(true)
	await _frames(2)
	_comprobar(vec_tab.npcs.has("ramon"), "a las 14:00 Ramón atiende dentro de la taberna")


# --- 6. Límites (andando y saltando), cámara bajo techo y minimapa ------------

func _probar_limites_camara_y_minimapa() -> void:
	print("[6. Límites de paredes/techo, cámara sin atravesar muros y minimapa]")
	for id_int: String in TODOS_INTERIORES:
		await _ir(id_int, "Entrada")

		var mapa := Escenas.mapa_actual_nodo()
		var j := Escenas.jugador() as Jugador
		var cam: CamaraJuego = j.camara if j != null else null
		var minimapa: Minimapa = Interfaz.minimapa()
		_comprobar(mapa != null and j != null and cam != null, "en «%s» existen mapa, jugador y CamaraJuego" % id_int)
		if mapa == null or j == null or cam == null:
			continue

		# Minimapa coherente y listo
		for _w in 60:
			if minimapa != null and minimapa.lista() and minimapa.id_mapa == id_int:
				break
			await get_tree().process_frame
		_comprobar(minimapa != null and minimapa.lista() and minimapa.id_mapa == id_int, "el minimapa está listo y renderizado dentro de «%s»" % id_int)

		# Averiguar semiancho, semilargo y altura del techo a partir de la geometría del suelo y techo
		var mi_suelo := _buscar_malla(mapa, "Suelo")
		var mi_techo := _buscar_malla(mapa, "Techo_interior")
		var aabb_suelo := _aabb_mundial_malla(mi_suelo)
		var aabb_techo := _aabb_mundial_malla(mi_techo)
		var max_x := aabb_suelo.end.x + 0.05
		var min_x := aabb_suelo.position.x - 0.05
		var max_z := aabb_suelo.end.z + 0.05
		var min_z := aabb_suelo.position.z - 0.05
		var alto_techo := aabb_techo.position.y if aabb_techo.size.y > 0.0 else 3.5

		# Comprobar que la cámara no atraviesa paredes ni techo al girar 360° e inclinar pitch
		var cam_ok := true
		for ang_i in 8:
			cam.yaw = float(ang_i) * TAU / 8.0
			for pitch_deg in [10.0, 28.0, 55.0, 78.0]:
				cam.pitch = deg_to_rad(pitch_deg)
				await _fisica(2)
				var p_cam := cam.camara.global_position
				if p_cam.y > alto_techo + 0.05 or p_cam.x < min_x - 0.25 or p_cam.x > max_x + 0.25 or p_cam.z < min_z - 0.25 or p_cam.z > max_z + 0.25:
					cam_ok = false
		_comprobar(cam_ok, "en «%s» la cámara orbital nunca atraviesa paredes ni supera el techo (%.2f m)" % [id_int, alto_techo])

		# En casa_leo, casita_a y tienda probar además a empujar a Leo andando y saltando contra las 4 paredes
		if id_int in ["casa_leo", "casita_a", "tienda"]:
			var dirs: Array[Vector3] = [
				Vector3(-1.0, 0.0, 0.0),
				Vector3(1.0, 0.0, 0.0),
				Vector3(0.0, 0.0, -1.0),
				Vector3(0.0, 0.0, 1.0),
			]
			var escapo := false
			for d: Vector3 in dirs:
				j.global_position = Vector3(0.0, 0.05, 0.0)
				j.velocity = Vector3.ZERO
				for paso in 36:
					j.velocity.x = d.x * 9.0
					j.velocity.z = d.z * 9.0
					if paso % 9 == 0 and j.is_on_floor():
						j.velocity.y = 6.5
					j.move_and_slide()
					await get_tree().physics_frame
					if not bool(mapa.call("punto_dentro", j.global_position)):
						escapo = true
					if j.global_position.x < min_x or j.global_position.x > max_x or j.global_position.z < min_z or j.global_position.z > max_z:
						escapo = true
					if j.global_position.y + ALTURA_LEO > alto_techo + 0.20:
						escapo = true
			j.velocity = Vector3.ZERO
			_comprobar(not escapo, "en «%s» Leo no puede salirse del interior ni andando ni saltando contra las 4 paredes ni el techo" % id_int)
