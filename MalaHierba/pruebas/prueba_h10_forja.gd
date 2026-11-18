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
		push_error("FALLO H10: " + msg)


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

	# 1. Datos de lingotes, carbon y gemas
	for id in ["carbon", "lingote_cobre", "lingote_hierro", "lingote_oro", "oro", "amatista", "rubi", "diamante", "ambar_valle"]:
		_comprobar(Datos.existe_objeto(id), "Objeto H10 existe: " + id)
	var tienda_forja := Datos.tienda("forja")
	_comprobar((tienda_forja.get("vende", []) as Array).size() == 8 and (tienda_forja.get("forja", []) as Array).size() == 24,
		"H02 forja intacta tras H10")

	# 2. Horno: fundir madera->carbon y cobre+carbon->lingote_cobre por avance de tiempo y dormir
	Juego.dinero = 600
	Juego.anadir_objeto("madera", 10)
	Juego.anadir_objeto("cobre", 6)
	Juego.anadir_objeto("hierro", 6)
	Juego.anadir_objeto("carbon", 2)
	_comprobar(Juego.iniciar_fundicion("fundir_cobre", false), "Horno inicia fundicion de cobre con carbon")
	_comprobar(Juego.horno_cola().size() == 1 and Juego.horno_listos_total() == 0, "Crisol en proceso antes de esperar")
	Juego.avanzar_minutos(60)
	_comprobar(Juego.horno_listos_total() == 1, "Lingote cobre listo tras avanzar minutos del dia")
	var rec := Juego.recoger_fundicion()
	_comprobar(rec == 1 and Juego.cantidad("lingote_cobre") == 1, "Recoge 1 lingote cobre al inventario")

	# Fundicion usando madera alternativa y terminando al dormir
	_comprobar(Juego.iniciar_fundicion("fundir_hierro", true), "Horno inicia hierro usando madera")
	Juego.terminar_dia(false, false)
	_comprobar(Juego.horno_listos_total() == 1, "Fundicion nocturna lista tras dormir")
	_comprobar(Juego.recoger_fundicion() == 1 and Juego.cantidad("lingote_hierro") == 1, "Recoge lingote hierro tras dormir")

	# 3. Mejora de herramienta con lingotes + temple + engaste de gemas (1..3 huecos)
	Juego.anadir_objeto("lingote_cobre", 2)
	_comprobar(Servicios.mejorar_con_lingote("pico") == "ok" and Juego.nivel("pico") == 1, "Herramienta mejora con lingote cobre")

	_comprobar(Herreria.huecos_para("espada_cobre") == 1, "Grado 0 tiene 1 hueco")
	_comprobar(Herreria.huecos_para("espada_hierro") == 2, "Grado 1 tiene 2 huecos")
	_comprobar(Herreria.huecos_para("espada_cuarzo") == 3, "Grado 2 tiene 3 huecos")

	Juego.anadir_objeto("espada_hierro", 1)
	Juego.anadir_objeto("rubi", 1)
	Juego.anadir_objeto("oro", 1)
	Juego.anadir_objeto("diamante", 1)
	Juego.anadir_objeto("amatista", 1)
	Juego.anadir_objeto("ambar_valle", 1)
	var idx_esp: int = _buscar_ranura("espada_hierro")
	if idx_esp >= 10:
		var tmp_inv: Dictionary = Juego.inventario[8]
		Juego.inventario[8] = Juego.inventario[idx_esp]
		Juego.inventario[idx_esp] = tmp_inv
		idx_esp = 8
	_comprobar(idx_esp >= 0 and idx_esp < 10, "Espada hierro en barra rapida")

	var dano_antes := float(Juego.stats_arma_activa().get("dano", 0.0)) if Juego.ranura == idx_esp else float(Datos.objeto("espada_hierro").get("dano", 0.0))
	_comprobar(Juego.engastar_gema("inventario", idx_esp, "", "rubi"), "Engasta rubi en espada hierro")
	_comprobar(Juego.engastar_gema("inventario", idx_esp, "", "ambar_valle"), "Engasta ambar en espada hierro")
	_comprobar(not Juego.engastar_gema("inventario", idx_esp, "", "diamante"), "No supera los 2 huecos de hierro")

	Juego.elegir_ranura(idx_esp)
	var st_arma := Juego.stats_arma_activa()
	_comprobar(float(st_arma.get("dano", 0.0)) > dano_antes and float(st_arma.get("quemadura", 0.0)) > 0.0 and float(st_arma.get("robo_vida", 0.0)) > 0.0,
		"Rubi y Ambar aumentan dano, quemadura y robo de vida")

	# Desengastar con coste y posible rotura / devolucion
	var din_antes := Juego.dinero
	var amat_antes := Juego.cantidad("oro")
	Juego.anadir_objeto("escudo_hierro", 1)
	var idx_esc := _buscar_ranura("escudo_hierro")
	_comprobar(Juego.engastar_gema("inventario", idx_esc, "", "oro"), "Engasta oro en escudo")
	_comprobar(Juego.desengastar_gema("inventario", idx_esc, "", 0, 0) == "devuelta", "Desengaste sin rotura devuelve gema")
	_comprobar(Juego.cantidad("oro") == amat_antes and Juego.dinero == din_antes - Herreria.COSTE_ENGASTE - Herreria.COSTE_DESENGASTE,
		"Desengaste cobra coste exacto y devuelve gema")

	_comprobar(Juego.engastar_gema("inventario", idx_esc, "", "oro"), "Reengasta oro")
	_comprobar(Juego.desengastar_gema("inventario", idx_esc, "", 0, 1) == "rota", "Desengaste con rotura destruye la gema")
	_comprobar(Juego.cantidad("oro") == amat_antes - 1, "Gema rota no regresa al inventario")

	# Equipar escudo con diamante y verificar ahorro resistencia por amatista
	_comprobar(Juego.engastar_gema("inventario", idx_esc, "", "amatista"), "Engasta amatista en escudo")
	_comprobar(Juego.equipar(idx_esc), "Equipa escudo engastado")
	_comprobar(Juego.bono_ahorro_resistencia() > 0.15, "Amatista en escudo equipado aplica ahorro de resistencia")

	# Templar con lingote
	Juego.anadir_objeto("lingote_hierro", 2)
	_comprobar(Juego.templar_con_lingote("inventario", idx_esp, ""), "Templa espada hierro +1 con lingote")
	_comprobar(int(Juego.stats_arma_activa().get("temple", 0)) == 1, "Temple +1 guardado en el objeto")

	# 4. Persistencia de gemas, temple, equipo_meta y cola del horno al guardar/cargar
	var ruta_orig := Juego.ruta_partida
	Juego.ruta_partida = "user://prueba_h10_tmp.json"
	Juego.iniciar_fundicion("fundir_cobre", true)
	_comprobar(Juego.guardar(false), "Guardar partida H10")
	Juego.nueva_partida("Otro")
	_comprobar(Juego.cargar(), "Cargar partida H10")
	var st_cargado := Juego.stats_arma_activa()
	_comprobar(int(st_cargado.get("temple", 0)) == 1 and float(st_cargado.get("robo_vida", 0.0)) > 0.0, "Guardado/carga conserva temple y gemas en arma")
	_comprobar(Juego.bono_ahorro_resistencia() > 0.15, "Guardado/carga conserva gemas del escudo equipado")
	_comprobar(Juego.horno_cola().size() == 1, "Guardado/carga conserva cola del horno")
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_orig

	# 5. Horno fisico en pueblo y fragua en herreria
	await Escenas.ir_a_mapa("pueblo")
	await _esperar(8)
	var mapa_p := get_tree().get_first_node_in_group("mapa")
	_comprobar(mapa_p != null and mapa_p.find_child("HornoFundicionPueblo", true, false) != null, "Horno 3D presente en pueblo")
	Interfaz.call("abrir_herreria", 1)
	await _esperar(3)
	_comprobar(bool(Interfaz.call("herreria_abierta")), "PanelHerreria se abre en pestana Engaste")
	var panel_h: Control = Interfaz.get("_herreria") as Control
	panel_h.call("cerrar")
	await _esperar(2)

	if _fallos == 0:
		print("PRUEBA H10 FORJA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H10 FORJA FALLO (%d ok, %d fallos)" % [_ok, _fallos])
		get_tree().quit(1)
