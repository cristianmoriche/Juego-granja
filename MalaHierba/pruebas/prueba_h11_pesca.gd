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
		push_error("FALLO H11: " + msg)


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

	# 1. Especies y cebos
	for id in ["cebo_lombriz", "cebo_masilla", "cebo_mosca", "cebo_luminoso", "tenca", "barbo", "lucio", "anguila", "salmon_sierra", "esturion", "pez_ciego"]:
		_comprobar(Datos.existe_objeto(id), "Objeto H11 existe: " + id)
	_comprobar(PescaAvanzada.ESPECIES_ORDEN.size() == 10, "Diez especies registradas en PescaAvanzada")

	# 2. Fabricación y equipamiento de cebos
	Juego.anadir_objeto("fibra", 6)
	Juego.anadir_objeto("patata", 2)
	Juego.anadir_objeto("pan", 2)
	Juego.anadir_objeto("cobre", 2)
	Juego.anadir_objeto("cuarzo", 2)
	Juego.anadir_objeto("mora_silvestre", 4)
	_comprobar(Juego.fabricar_cebo("cebo_lombriz") and Juego.cantidad("cebo_lombriz") == 4, "Fabrica cebo lombriz")
	_comprobar(Juego.fabricar_cebo("cebo_masilla") and Juego.cantidad("cebo_masilla") == 5, "Fabrica masilla")
	_comprobar(Juego.fabricar_cebo("cebo_mosca") and Juego.cantidad("cebo_mosca") == 3, "Fabrica mosca")
	_comprobar(Juego.fabricar_cebo("cebo_luminoso") and Juego.cantidad("cebo_luminoso") == 3, "Fabrica cebo luminoso")
	_comprobar(Juego.elegir_cebo("cebo_luminoso") and Juego.cebo_activo() == "cebo_luminoso", "Equipa cebo luminoso")

	# 3. Filtrado por zona / clima / cebo y tamano/peso variable
	var sp_mina := PescaAvanzada.elegir_especie("mina_interior", 700, 0, "sol", "cebo_luminoso")
	_comprobar(sp_mina in ["pez_ciego", "anguila"], "Cueva genera especie subterranea: " + sp_mina)
	var vio_ciego := false
	for _i in 20:
		if PescaAvanzada.elegir_especie("mina_interior", 700, 0, "sol", "cebo_luminoso") == "pez_ciego":
			vio_ciego = true
			break
	_comprobar(vio_ciego, "Pez ciego de cueva aparece en lago de mina")

	var vio_esturion := false
	for _i in 35:
		if PescaAvanzada.elegir_especie("costa_lago", 760, 1, "tormenta", "cebo_mosca") == "esturion":
			vio_esturion = true
			break
	_comprobar(vio_esturion, "Esturion aparece en costa_lago con tormenta")

	var ej1 := PescaAvanzada.generar_ejemplar("esturion", "cebo_mosca", 0.1)
	_comprobar(float(ej1["cm"]) >= 70.0 and float(ej1["kg"]) >= 5.0, "Generador de calibre devuelve dimensiones coherentes")

	# 4. Fisica del sedal: rotura si recoge durante tiron fuerte vs captura si regula tension
	var est_rot := PescaAvanzada.nuevo_estado_lucha("esturion", 1)
	est_rot["tirando"] = true
	est_rot["fase_t"] = 8.0
	for _step in 60:
		est_rot = PescaAvanzada.simular_paso(est_rot, true, 0.05)
		if str(est_rot["resultado"]) != "curso":
			break
	_comprobar(str(est_rot["resultado"]) == "roto", "Recoger sin descanso durante tiron rompe sedal")

	var est_ok := PescaAvanzada.nuevo_estado_lucha("carpa", 4)
	for _step in 260:
		var rec_ahora := not bool(est_ok["tirando"]) and float(est_ok["tension"]) < 0.72
		est_ok = PescaAvanzada.simular_paso(est_ok, rec_ahora, 0.05)
		if str(est_ok["resultado"]) != "curso":
			break
	_comprobar(str(est_ok["resultado"]) == "capturado", "Alternar carrete segun tirones cansa y captura al pez")

	# 5. Album, diario y persistencia
	var rec_a := Juego.registrar_captura_pesca(ej1, "costa_lago")
	_comprobar(bool(rec_a["nueva"]) and Juego.album_pesca().has("esturion"), "Registro en album de pesca")
	var ruta_orig := Juego.ruta_partida
	Juego.ruta_partida = "user://prueba_h11_tmp.json"
	_comprobar(Juego.guardar(false), "Guarda partida H11")
	Juego.nueva_partida("Otro")
	_comprobar(Juego.cargar(), "Carga partida H11")
	_comprobar(Juego.album_pesca().has("esturion") and Juego.cebo_activo() == "cebo_luminoso", "Guardado conserva album y cebo")
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_orig

	# 6. Pez en mano 3D y zonas de pesca en mina humeda (nivel 6) + diario
	Juego.anadir_objeto("pez_ciego", 1)
	var idx_pc := _buscar_ranura("pez_ciego")
	if idx_pc >= 10:
		var tmp_inv: Dictionary = Juego.inventario[8]
		Juego.inventario[8] = Juego.inventario[idx_pc]
		Juego.inventario[idx_pc] = tmp_inv
		idx_pc = 8
	await Escenas.ir_a_mapa("costa_lago")
	await _esperar(8)
	var j := Escenas.jugador() as Jugador
	Tutorial.cerrar_actual()
	Juego.elegir_ranura(idx_pc)
	await _esperar(3)
	_comprobar(j.get("_herramienta_nodo") != null, "Pez en mano 3D instanciado en mano de Leo")

	Interfaz.abrir_diario("pesca")
	await _esperar(2)
	_comprobar(Interfaz.diario_abierto(), "Diario abre directamente en pestana Album pesca")
	Interfaz._diario.cerrar()
	await _esperar(2)

	if _fallos == 0:
		print("PRUEBA H11 PESCA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H11 PESCA FALLO (%d ok, %d fallos)" % [_ok, _fallos])
		get_tree().quit(1)
