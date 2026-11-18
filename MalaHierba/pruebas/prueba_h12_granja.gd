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
		push_error("FALLO H12: " + msg)


func _esperar(frames: int = 4) -> void:
	for _i in frames:
		await get_tree().physics_frame
	for _i in 2:
		await get_tree().process_frame


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.dinero = 900

	# 1. Objetos y recetas H12 presentes
	for id in ["ahumador", "pienso_aves", "huevo_pardo", "huevo_blanco", "tarro_miel"]:
		_comprobar(Datos.existe_objeto(id), "Objeto H12 existe: " + id)
	for rid in ["revuelto_huevos", "flan_miel"]:
		_comprobar(Datos.existe_receta(rid), "Receta H12 existe: " + rid)

	# 2. Gallinero empieza roto, se repara, se cuida y pone huevos al avanzar dias
	var est0: Dictionary = Juego.ganado_estado()
	var co0: Dictionary = est0["gallinero"]
	_comprobar(not bool(co0["reparado"]), "Gallinero inicia roto")
	Juego.anadir_objeto("madera", 25)
	_comprobar(Juego.reparar_gallinero(), "Repara gallinero con madera y dinero")
	_comprobar(bool((Juego.ganado_estado()["gallinero"] as Dictionary)["reparado"]) and int((Juego.ganado_estado()["gallinero"] as Dictionary)["gallinas"]) == 2,
		"Gallinero reparado con 2 gallinas iniciales")
	_comprobar(Juego.comprar_gallina() and int((Juego.ganado_estado()["gallinero"] as Dictionary)["gallinas"]) == 3,
		"Compra tercera gallina")

	Juego.anadir_objeto("pienso_aves", 2)
	_comprobar(Juego.alimentar_gallinero(), "Alimenta gallinero")
	_comprobar(Juego.dar_agua_gallinero(), "Da agua al gallinero")
	Juego.terminar_dia(false, false)
	var huevos_dia1: Array = (Juego.ganado_estado()["gallinero"] as Dictionary)["huevos"]
	_comprobar(huevos_dia1.size() >= 2, "Ponen huevos tras dormir cuidadas")
	var recog := Juego.recoger_huevos()
	_comprobar(recog >= 2 and (Juego.cantidad("huevo_pardo") + Juego.cantidad("huevo_blanco")) == recog,
		"Recoge huevos frescos al inventario")

	# 3. Colmenas: cosecha, sin miel en invierno, picadura sin ahumador y limpia con ahumador
	_comprobar(Juego.desbloquear_colmena(1), "Construye segunda colmena")
	Juego.estacion = 3  # Invierno
	for _d in 3:
		Juego.terminar_dia(false, false)
	var miel_inv: int = int(((Juego.ganado_estado()["colmenas"] as Array)[0] as Dictionary)["miel"])
	_comprobar(miel_inv == 0, "En invierno las abejas no producen miel")

	Juego.estacion = 0  # Primavera
	for _d in 4:
		Juego.terminar_dia(false, false)
	var miel_prim: int = int(((Juego.ganado_estado()["colmenas"] as Array)[0] as Dictionary)["miel"])
	_comprobar(miel_prim >= 1, "En primavera producen miel tras avanzar dias")

	var vida_antes := Juego.vida
	var res_sin := Juego.cosechar_colmena(0)
	_comprobar(bool(res_sin["ok"]) and bool(res_sin["picadura"]) and Juego.vida < vida_antes,
		"Cosechar sin ahumador causa picadura (-salud)")

	Juego.anadir_objeto("ahumador", 1)
	var vida_con := Juego.vida
	var res_con := Juego.cosechar_colmena(1)
	_comprobar(bool(res_con["ok"]) and not bool(res_con["picadura"]) and is_equal_approx(Juego.vida, vida_con),
		"Cosechar con ahumador evita picaduras")

	# 4. Cocinar con huevo y miel
	Juego.aprender_receta("revuelto_huevos", false)
	Juego.aprender_receta("flan_miel", false)
	Juego.anadir_objeto("huevo_pardo", 4)
	Juego.anadir_objeto("seta_silvestre", 2)
	Juego.anadir_objeto("tarro_miel", 1)
	_comprobar(Juego.cocinar("revuelto_huevos") and Juego.cantidad("revuelto_huevos") == 1, "Cocina revuelto con huevo")
	_comprobar(Juego.cocinar("flan_miel") and Juego.cantidad("flan_miel") == 1, "Cocina crema dorada con huevo y miel")

	# 5. Guardado / carga e instancia 3D en granja
	var ruta_orig := Juego.ruta_partida
	Juego.ruta_partida = "user://prueba_h12_tmp.json"
	_comprobar(Juego.guardar(false), "Guarda partida H12")
	Juego.nueva_partida("Otro")
	_comprobar(Juego.cargar(), "Carga partida H12")
	_comprobar(bool((Juego.ganado_estado()["gallinero"] as Dictionary)["reparado"]), "Guardado conserva estado gallinero")
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_orig

	await Escenas.ir_a_mapa("granja")
	await _esperar(8)
	var gg := get_tree().get_first_node_in_group("mapa").find_child("GranjaGanadera", true, false) as GranjaGanadera
	_comprobar(gg != null and gg.find_child("GallineroFinca", true, false) != null and gg.find_child("Colmena_1", true, false) != null,
		"Gallinero y colmenas instanciados en escena 3D de granja")

	if _fallos == 0:
		print("PRUEBA H12 GRANJA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H12 GRANJA FALLO (%d ok, %d fallos)" % [_ok, _fallos])
		get_tree().quit(1)
