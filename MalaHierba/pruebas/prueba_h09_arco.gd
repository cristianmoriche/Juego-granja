extends Node

var _ok := 0
var _fallos := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ejecutar.call_deferred()


func _comprobar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos += 1
		push_error("FALLO H09: " + msg)


func _esperar(frames: int = 4) -> void:
	for _i in frames:
		await get_tree().physics_frame
	for _i in 2:
		await get_tree().process_frame


func _buscar_ranura(id: String) -> int:
	for i in Juego.inventario.size():
		if not Juego.inventario[i].is_empty() and str(Juego.inventario[i].get("id", "")) == id:
			return i
	return -1


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)

	# 1. Datos y tienda arqueria sin romper forja (H02)
	var tienda_forja := Datos.tienda("forja")
	var vende_forja: Array = tienda_forja.get("vende", [])
	var forja_rec: Array = tienda_forja.get("forja", [])
	_comprobar(vende_forja.size() == 8 and forja_rec.size() == 24, "H02 forja intacta (8 vende, 24 forja)")

	var arq := Datos.tienda("arqueria")
	var vende_arq: Array = arq.get("vende", [])
	var forja_arq: Array = arq.get("forja", [])
	_comprobar(not vende_arq.is_empty() and not forja_arq.is_empty(), "Tienda arqueria poblada")
	for id in ["arco_caza", "arco_cristal", "carcaj_cuero", "flecha_normal", "flecha_cobre", "flecha_cristal", "flecha_fuego"]:
		_comprobar(not Datos.objeto(id).is_empty(), "Objeto existe: " + id)
	_comprobar(str(Datos.objeto("arco_caza").get("subtipo", "")) == "arco", "Arco caza subtipo arco")
	_comprobar(str(Datos.objeto("flecha_fuego").get("tipo", "")) == "municion", "Flecha fuego tipo municion")

	# 2. Ecuación balística vs paso real
	var pos := Vector3(0.0, 2.0, 0.0)
	var vel := Vector3(0.0, 4.0, -34.0)
	var paso := Flecha.paso_balistico(pos, vel, 0.02, 1.0, 0.08)
	var p_esp: Vector3 = paso.get("pos", Vector3.ZERO)
	var v_esp: Vector3 = paso.get("vel", Vector3.ZERO)
	var v_manual := vel * exp(-0.08 * 0.02)
	v_manual.y -= Flecha.GRAVEDAD * 0.02
	_comprobar(p_esp.distance_to(pos + v_manual * 0.02) < 0.0001 and v_esp.distance_to(v_manual) < 0.0001, "Balistica Flecha exacta")

	# 3. Jugador, arco en 1P/3P, carcaj en espalda, HUD y disparo con consumo
	await Escenas.ir_a_mapa("granja")
	await _esperar(8)
	var leo := Escenas.jugador() as Jugador
	_comprobar(leo != null, "Leo cargado en granja")
	Tutorial.cerrar_actual()

	Juego.anadir_objeto("arco_caza", 1)
	Juego.anadir_objeto("carcaj_cuero", 1)
	Juego.anadir_objeto("flecha_fuego", 6)
	Juego.anadir_objeto("flecha_normal", 5)
	_comprobar(Juego.total_flechas() == 11, "Total flechas == 11")
	_comprobar(Juego.municion_disponible() == "flecha_fuego" or Juego.municion_disponible() == "flecha_normal", "Municion disponible valida")

	# Equipar carcaj desde inventario
	var idx_carcaj: int = _buscar_ranura("carcaj_cuero")
	_comprobar(idx_carcaj >= 0, "Carcaj en inventario")
	Juego.equipar(idx_carcaj)
	await _esperar(3)
	_comprobar(str(Juego.equipo.get("carcaj", "")) == "carcaj_cuero", "Carcaj equipado en ranura carcaj")
	var carcaj_nodo: Node = leo.get("_carcaj_nodo") as Node
	_comprobar(carcaj_nodo != null and is_instance_valid(carcaj_nodo), "Carcaj 3D montado en Leo")

	# Seleccionar arco en barra rapida
	var idx_arco: int = _buscar_ranura("arco_caza")
	_comprobar(idx_arco >= 0 and idx_arco < 9, "Arco caza en barra rapida")
	Juego.elegir_ranura(idx_arco)
	await _esperar(3)
	var combate: CombateJugador = leo.combate
	_comprobar(combate.es_arco_activo(), "Combate reconoce arco activo")
	var panel_arco: Control = Interfaz._hud.get("_panel_arco") as Control
	_comprobar(panel_arco != null and panel_arco.visible, "HUD visor arco visible al equipar arco")

	# 1P arco + punto de salida
	var vista_previa: int = int(Ajustes.valores.vista)
	Ajustes.poner("vista", 0)
	await _esperar(35)
	var arco_1p: Node3D = leo.get("_arco_primera") as Node3D
	_comprobar(leo.camara.primera_persona and arco_1p != null and arco_1p.visible, "Arco 1P visible en primera persona")
	var salida: Vector3 = leo.punto_salida_flecha()
	_comprobar(salida.is_finite() and salida.distance_to(leo.global_position) < 3.0, "Punto salida flecha valido")

	# Tensión progresiva y disparo
	var flechas_antes: int = Juego.total_flechas()
	combate.preparar_ataque("arco_caza", null)
	combate.actualizar(0.45, true, true)
	var tens_mid: float = combate.tension_arco
	_comprobar(tens_mid > 0.35, "Tension de arco sube al mantener")
	_comprobar(panel_arco.visible, "HUD visor arco activo al apuntar")
	combate.soltar_ataque()
	await _esperar(2)
	_comprobar(Juego.total_flechas() == flechas_antes - 1, "Disparo consume 1 flecha")
	var flechas_vivas: Array = get_tree().get_nodes_in_group("flechas_vivas")
	if flechas_vivas.is_empty():
		var map_root: Node = leo.get_parent()
		for h in map_root.get_children():
			if h is Flecha:
				flechas_vivas.append(h)
	_comprobar(not flechas_vivas.is_empty(), "Flecha instanciada en el mundo tras disparar")

	# 4. Probabilidad de recuperacion mejorada con carcaj + impacto vs roca/enemigo
	if not flechas_vivas.is_empty():
		var f: Flecha = flechas_vivas[0] as Flecha
		var base_rec: float = float(Datos.objeto(f.id_municion).get("recupera", 0.0))
		_comprobar(f.prob_recupera > base_rec + 0.05, "Carcaj aumenta probabilidad de recuperar flecha")

	# 5. Reaccion de enemigo ante flechazo
	var dummy := Enemigo.new()
	dummy.id_enemigo = "bicho_espina"
	dummy.vida_max = 100.0
	dummy.vida = 100.0
	leo.get_parent().add_child(dummy)
	dummy.global_position = leo.global_position + Vector3(8.0, 0.0, 0.0)
	dummy.reaccionar_flechazo(leo.global_position)
	_comprobar(float(dummy.get("_t_zigzag_flecha")) > 3.0, "Enemigo activa zigzag tras recibir flechazo")
	dummy.queue_free()

	# 6. Guardado / carga conserva carcaj y flechas
	var ruta_orig := Juego.ruta_partida
	Juego.ruta_partida = "user://prueba_h09_tmp.json"
	_comprobar(Juego.guardar(false), "Guardar partida H09 con carcaj")
	Juego.nueva_partida("Otro")
	_comprobar(Juego.cargar(), "Cargar partida H09 con carcaj")
	_comprobar(str(Juego.equipo.get("carcaj", "")) == "carcaj_cuero", "Guardado/carga conserva carcaj")
	_comprobar(Juego.total_flechas() == flechas_antes - 1, "Guardado/carga conserva flechas exactas")
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_orig

	# Restaurar
	Ajustes.poner("vista", vista_previa)
	await _esperar(4)

	if _fallos == 0:
		print("PRUEBA H09 ARCO OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H09 ARCO FALLO (%d ok, %d fallos)" % [_ok, _fallos])
		get_tree().quit(1)
