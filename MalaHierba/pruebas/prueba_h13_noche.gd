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
		push_error("FALLO H13: " + msg)


func _esperar(frames: int = 5) -> void:
	for _i in frames:
		await get_tree().physics_frame
	for _i in 2:
		await get_tree().process_frame


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 1220  # 20:20 noche

	# 1. Kit de campamento existente y no montable en granja
	_comprobar(Datos.existe_objeto("kit_campamento"), "Objeto kit_campamento existe")
	Juego.anadir_objeto("kit_campamento", 1)
	await Escenas.ir_a_mapa("granja")
	await _esperar(8)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	var rec_granja := get_tree().get_first_node_in_group("recursos_exteriores") as RecursosExteriores
	_comprobar(rec_granja != null and rec_granja.get_node_or_null("EnemigosNocturnos") == null,
		"Sin encuentros nocturnos en la granja")
	_comprobar(not RecursosExteriores.montar_campamento_jugador(j),
		"No deja montar campamento en granja")
	_comprobar(Juego.cantidad("kit_campamento") == 1, "Rechazar campamento no consume kit")

	# 2. Zona salvaje de noche: encuentros y montaje del campamento + descanso + guardado
	await Escenas.ir_a_mapa("robledal_niebla")
	await _esperar(8)
	j = Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	var rec_rob := get_tree().get_first_node_in_group("recursos_exteriores") as RecursosExteriores
	_comprobar(rec_rob != null, "RecursosExteriores activos en robledal_niebla")
	rec_rob._anochecer_generado = false
	rec_rob._actualizar_enemigos_anochecer(true)
	await _esperar(2)
	var nodo_en := rec_rob.get_node_or_null("EnemigosNocturnos")
	_comprobar(nodo_en != null and nodo_en.get_child_count() >= 1,
		"Encuentro nocturno puntual generado en zona salvaje")
	if nodo_en != null and nodo_en.get_child_count() > 0:
		var en := nodo_en.get_child(0) as Enemigo
		_comprobar(bool(en.get_meta("nocturno_h13", false)), "Enemigo marcado con botin raro nocturno H13")

	# Montar campamento, descansar (no pasa de dia!) y recoger
	_comprobar(RecursosExteriores.montar_campamento_jugador(j), "Monta campamento en zona salvaje")
	await _esperar(2)
	_comprobar(rec_rob.get_node_or_null("CampamentoPortatil") != null and not Juego.campamento_estado().is_empty(),
		"CampamentoPortatil instanciado con estado guardado")

	var dia_antes := Juego.dia
	Juego.vida = 50.0
	Juego.energia = 40.0
	Juego.gastar_resistencia(50.0)
	_comprobar(Juego.descansar_campamento(3), "Descansa en campamento")
	_comprobar(Juego.dia == dia_antes and Juego.vida > 80.0 and Juego.energia >= 70.0 and is_equal_approx(Juego.resistencia, Juego.RESISTENCIA_MAX),
		"Descansar en campamento recupera vida/energia/resistencia sin cambiar el dia agricola")

	# Guardar con campamento montado y recargar
	var ruta_orig := Juego.ruta_partida
	Juego.ruta_partida = "user://prueba_h13_tmp.json"
	_comprobar(Juego.guardar(false), "Guarda partida en campamento")
	Juego.nueva_partida("Otro")
	_comprobar(Juego.cargar() and str(Juego.campamento_estado().get("mapa", "")) == "robledal_niebla",
		"Cargar partida conserva campamento montado")
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_orig

	# 3. Tutorial nocturno de farol
	_comprobar(not Tutorial.contenido_de("noche_farol").is_empty(), "Entrada tutorial noche_farol existe")

	if _fallos == 0:
		print("PRUEBA H13 NOCHE OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H13 NOCHE FALLO (%d ok, %d fallos)" % [_ok, _fallos])
		get_tree().quit(1)
