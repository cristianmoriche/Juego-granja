extends Node
## Prueba breve de H14: migración legada, 3 ranuras, miniatura, confirmación, 21 logros y pestaña del diario.

const Logros := preload("res://scripts/objetos/logros_h14.gd")
const LEGADO_REAL := "res://../copias/partidas-2026-11-17-antes-hiperrealista/partida.json"

var _fallos: Array[String] = []
var _total := 0
var _senales_logro: Array[String] = []
var _respaldo_ranuras: Dictionary = {}


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(cond: bool, msg: String) -> void:
	_total += 1
	if not cond:
		_fallos.append(msg)
		push_error("H14 FALLO: " + msg)


func _respaldar_usuario() -> void:
	_respaldo_ranuras.clear()
	for slot in range(1, Juego.MAX_RANURAS + 1):
		for ruta: String in [
			Juego.ruta_ranura(slot),
			Juego.ruta_ranura(slot) + Juego.SUFIJO_COPIA,
			Juego.ruta_ranura(slot) + Juego.SUFIJO_TEMPORAL,
			Juego.ruta_miniatura_ranura(slot),
		]:
			if FileAccess.file_exists(ruta):
				_respaldo_ranuras[ruta] = FileAccess.get_file_as_bytes(ruta)


func _restaurar_usuario() -> void:
	for slot in range(1, Juego.MAX_RANURAS + 1):
		Juego.borrar_ranura(slot)
	for ruta: String in _respaldo_ranuras:
		var fw := FileAccess.open(ruta, FileAccess.WRITE)
		if fw != null:
			fw.store_buffer(_respaldo_ranuras[ruta] as PackedByteArray)
			fw.close()


func _ejecutar() -> void:
	await get_tree().process_frame
	_respaldar_usuario()
	Juego.logro_desbloqueado.connect(func(d: Dictionary) -> void: _senales_logro.append(str(d.get("id", ""))))

	# 1. Catálogo e iconos de los 21 logros
	_comprobar(Logros.total() >= 18 and Logros.total() <= 25, "Catálogo entre 18 y 25 logros (%d)" % Logros.total())
	var ids_vistos: Dictionary = {}
	for d: Dictionary in Logros.DEFINICIONES:
		var lid := str(d.get("id", ""))
		var ico := str(d.get("icono", ""))
		_comprobar(not lid.is_empty() and not ids_vistos.has(lid), "ID de logro único: " + lid)
		ids_vistos[lid] = true
		_comprobar(Datos.tiene_icono(ico), "Icono de logro real existe: " + ico)
		var tex := Datos.icono(ico)
		_comprobar(tex.get_size() == Vector2(128, 128), "Icono 128x128: " + ico)

	# 2. Migración automática de partida legada real (copia 2026-11-17) sin pérdida
	for slot in range(1, Juego.MAX_RANURAS + 1):
		Juego.borrar_ranura(slot)
	var r_leg := "user://test_h14_legado.json"
	var r_dest := "user://test_h14_migrada_1.json"
	for tmp_r: String in [r_leg, r_dest, r_dest + Juego.SUFIJO_COPIA]:
		if FileAccess.file_exists(tmp_r):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_r))

	if FileAccess.file_exists(LEGADO_REAL):
		var bytes_orig := FileAccess.get_file_as_bytes(LEGADO_REAL)
		var fl := FileAccess.open(r_leg, FileAccess.WRITE)
		fl.store_buffer(bytes_orig)
		fl.close()
		var ok_mig := Juego.migrar_partida_legada(r_leg, r_dest)
		_comprobar(ok_mig, "Migración de partida.json legada (2026-11-17) a ranura 1 devuelve true")
		_comprobar(FileAccess.file_exists(r_leg), "El archivo legado original no se pierde ni se borra")
		var d_orig := Juego.leer_archivo(r_leg)
		var d_dest := Juego.leer_archivo(r_dest)
		_comprobar(not d_dest.is_empty() and int(d_dest["dinero"]) == int(d_orig["dinero"]) and int(d_dest["dia"]) == int(d_orig["dia"]),
			"Partida migrada conserva dinero y día exactos")
		_comprobar(not Juego.migrar_partida_legada(r_leg, r_dest), "Segunda ejecución no sobrescribe la ranura 1 ya migrada")
		Juego.ruta_partida = r_dest
		_comprobar(Juego.cargar(), "La partida legada real de 2026-11-17 carga limpia en v0.3.0")
	for tmp_r: String in [r_leg, r_dest, r_dest + Juego.SUFIJO_COPIA]:
		if FileAccess.file_exists(tmp_r):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_r))

	# 3. 3 ranuras independientes, resumen, tiempo jugado y borrado selectivo
	Juego.seleccionar_ranura_guardado(1)
	Juego.nueva_partida("Elena")
	Juego.dinero = 777
	Juego.dia = 4
	Juego.tiempo_jugado_seg = 420.0
	Juego.anadir_objeto("arco_caza", 1)
	_comprobar(Juego.guardar(), "Guardar en ranura 1")

	Juego.seleccionar_ranura_guardado(2)
	Juego.nueva_partida("Marco")
	Juego.dinero = 1450
	Juego.dia = 11
	Juego.banderas["mina_max_nivel"] = 7
	Juego.tiempo_jugado_seg = 3660.0
	_comprobar(Juego.guardar(), "Guardar en ranura 2")

	Juego.seleccionar_ranura_guardado(3)
	Juego.nueva_partida("Sofia")
	Juego.dinero = 3100
	Juego.dia = 19
	_comprobar(Juego.guardar(), "Guardar en ranura 3")

	var i1 := Juego.info_ranura(1)
	var i2 := Juego.info_ranura(2)
	var i3 := Juego.info_ranura(3)
	_comprobar(bool(i1["existe"]) and str(i1["nombre"]) == "Elena" and int(i1["dinero"]) == 777, "Info ranura 1 correcta")
	_comprobar(bool(i2["existe"]) and str(i2["nombre"]) == "Marco" and int(i2["mina_max_nivel"]) == 7 and int(i2["tiempo_jugado_seg"]) >= 3600, "Info ranura 2 correcta")
	_comprobar(bool(i3["existe"]) and str(i3["nombre"]) == "Sofia" and int(i3["dinero"]) == 3100, "Info ranura 3 correcta")

	# Simula miniatura PNG en disco para ranura 1 y comprueba miniatura_de_ranura
	var img_m := Image.create(256, 144, false, Image.FORMAT_RGBA8)
	img_m.fill(Color(0.24, 0.45, 0.28))
	img_m.save_png(ProjectSettings.globalize_path(Juego.ruta_miniatura_ranura(1)))
	_comprobar(Juego.miniatura_de_ranura(1) != null, "Miniatura PNG cargada en ranura 1")

	Juego.borrar_ranura(2)
	_comprobar(not bool(Juego.info_ranura(2)["existe"]) and str(Juego.info_ranura(2)["estado"]) == "ninguna", "Ranura 2 borrada limpiamente")
	_comprobar(bool(Juego.info_ranura(1)["existe"]) and bool(Juego.info_ranura(3)["existe"]), "Ranuras 1 y 3 permanecen intactas")

	# 4. Menú principal con tarjetas de 3 ranuras
	var menu := (load("res://escenas/menu_principal.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var lista_ranuras := menu.get_node_or_null("MarginContainer/HBoxContainer/PanelRanuras/VBoxContainer/ListaRanuras")
	if lista_ranuras == null:
		lista_ranuras = menu.find_child("ListaRanuras", true, false)
	_comprobar(lista_ranuras != null and lista_ranuras.get_child_count() == 3, "Menú principal construye las 3 tarjetas de ranura")
	menu.queue_free()
	await get_tree().process_frame

	# 5. Desbloqueo de los 21 logros, señales, audio y persistencia
	_senales_logro.clear()
	Juego.seleccionar_ranura_guardado(1)
	Juego.nueva_partida("LogrosTester")
	Juego.estadisticas["cosechas"] = 32
	Juego.ingresar(5000)
	Juego.pagar_deuda(5000)
	Juego.dinero = 2500
	var npcs := Datos.ids_npc()
	for idx in mini(4, npcs.size()):
		Juego.subir_amistad(npcs[idx], 160 if idx == 0 else 70)
	Juego.banderas["mina_max_nivel"] = 20
	for jid: String in ["rata_reina", "sapo_gigante", "arana_madre", "gusano_magma"]:
		Juego.registrar_jefe_derrotado(jid)
	Juego.anadir_objeto("arco_caza", 1)
	Juego.estadisticas["flechas_disparadas"] = 3
	Juego.estadisticas["gemas_engastadas"] = 1
	for sp_id: String in PescaAvanzada.ESPECIES_ORDEN:
		Juego.registrar_captura_pesca({"id": sp_id, "cm": 35.0, "kg": 1.2}, "lago")
	Juego.ingresar(1000)
	Juego.anadir_objeto("madera", 12)
	Juego.reparar_gallinero()
	Juego.anadir_objeto("tarro_miel", 1)
	Juego.guardar_campamento("bosque_norte", Vector3(2, 0, 2))
	Juego.descansar_campamento(2)
	Juego.estadisticas["platos_cocinados"] = 6
	Juego.ganar_xp_habilidad("agricultura", 800)
	for z: String in Logros.ZONAS_EXPLORACION:
		Juego.registrar_zona_visitada(z, false)

	Juego.evaluar_logros(true)
	_comprobar(Juego.logros_desbloqueados().size() == Logros.total(), "Desbloqueados los %d/%d logros" % [Juego.logros_desbloqueados().size(), Logros.total()])
	_comprobar(_senales_logro.size() > 0, "Emite señal logro_desbloqueado al cumplir criterios")
	Juego.guardar()

	# Recarga y comprueba persistencia
	Juego.nueva_partida("Vacia")
	_comprobar(Juego.logros_desbloqueados().is_empty(), "Nueva partida parte con 0 logros")
	_comprobar(Juego.cargar(), "Carga ranura con logros")
	_comprobar(Juego.logros_desbloqueados().size() == Logros.total(), "Logros persisten completos tras guardar y cargar")

	# 6. Pestaña «Logros» en PanelDiario
	Interfaz.abrir_diario("logros")
	await get_tree().process_frame
	var diario := Interfaz._diario
	_comprobar(diario != null and diario.visible and diario.pestana_actual() == "logros", "Diario abre en la pestaña 'logros'")
	var tit_logros := diario.find_child("RejillaLogros", true, false)
	_comprobar(tit_logros != null and tit_logros.get_child_count() == Logros.total(), "Tablero visual muestra las %d tarjetas de logros" % Logros.total())
	Interfaz.cerrar_todo()

	_restaurar_usuario()
	if _fallos.is_empty():
		print("PRUEBA H14 RANURAS LOGROS OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA H14 FALLO: ", "; ".join(PackedStringArray(_fallos)), "  (%d comprobaciones)" % _total)
		get_tree().quit(1)
