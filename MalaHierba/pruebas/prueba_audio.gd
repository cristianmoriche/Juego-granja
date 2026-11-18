extends Node
## Prueba de T07: buses, archivos WAV, músicas en bucle y disparo real de sonidos por acción.

var _fallos: Array[String] = []
var _total := 0


var _terminado: bool = false


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(_por_tiempo)
	_ejecutar.call_deferred()


func _por_tiempo() -> void:
	if _terminado:
		return
	_terminado = true
	print("PRUEBA AUDIO FALLO: tiempo límite de 60 s agotado")
	get_tree().quit(1)


func _finalizar() -> void:
	if _terminado:
		return
	_terminado = true
	if _fallos.is_empty():
		print("PRUEBA AUDIO OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA AUDIO FALLO: %d de %d" % [_fallos.size(), _total])
		get_tree().quit(1)


func _esperar_transicion(max_ms: int = 15000) -> bool:
	var limite := Time.get_ticks_msec() + max_ms
	while Escenas.en_transicion and Time.get_ticks_msec() < limite:
		await get_tree().process_frame
	return not Escenas.en_transicion


func _comprobar(condicion: bool, texto: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(texto)
		print("FALLO: ", texto)


func _fotogramas(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	# 1. Buses
	for bus: String in ["Musica", "Efectos", "Ambiente"]:
		var idx := AudioServer.get_bus_index(bus)
		_comprobar(idx >= 0, "existe bus " + bus)
		if idx >= 0:
			_comprobar(AudioServer.get_bus_send(idx) == "Master", bus + " envía a Master")

	# 2. Archivos WAV y duración de músicas (60-90 s)
	var obligatorios := [
		"paso_tierra", "paso_hierba", "paso_madera", "paso_piedra",
		"azada", "regadera", "hoz", "hacha", "pico", "cosecha",
		"puerta_abrir", "puerta_cerrar",
		"ui_clic", "ui_menu", "ui_comprar", "ui_error",
		"amb_lluvia", "amb_pueblo", "amb_mina",
		"mus_menu", "mus_granja", "mus_pueblo", "mus_interiores", "mus_mina",
	]
	for id: String in obligatorios:
		var ruta := "res://assets/audio/%s.wav" % id
		_comprobar(ResourceLoader.exists(ruta), "existe " + ruta)
		var s := Audio._cargar_stream(id, id.begins_with("mus_") or id.begins_with("amb_"))
		_comprobar(s != null, "carga stream " + id)
		if id.begins_with("mus_") and s != null:
			var dur := s.get_length()
			_comprobar(dur >= 60.0 and dur <= 90.0, "música %s dura %.1f s (60-90)" % [id, dur])

	# 3. Música y ambiente en menú y mapas
	Audio.conteo_efectos.clear()
	var menu := load("res://escenas/menu_principal.tscn").instantiate() as Control
	add_child(menu)
	await _fotogramas()
	_comprobar(Audio.musica_actual == "mus_menu", "menú reproduce mus_menu")
	_comprobar(Audio.ambiente_actual == "", "menú sin ambiente")
	menu.queue_free()
	await menu.tree_exited

	Juego.nueva_partida("Prueba Audio")
	Juego.pausar_tiempo(true)
	Juego.clima = "sol"
	await Escenas.ir_a_mapa("granja")
	await _esperar_transicion()
	_comprobar(Audio.musica_actual == "mus_granja", "granja reproduce mus_granja")
	_comprobar(Audio.ambiente_actual == "amb_dia_pajaros", "granja sin lluvia reproduce ambiente diurno de pájaros")

	Juego.clima = "lluvia"
	Audio._actualizar_ambiente_actual()
	_comprobar(Audio.ambiente_actual == "amb_lluvia", "lluvia activa amb_lluvia")
	Juego.clima = "sol"

	# 4. Pasos por zona
	var j := Escenas.jugador() as Jugador
	j.global_position = Vector3(0, 0, 0)
	_comprobar(j._sonido_paso() == "paso_tierra", "paso en tierra en zona granja")
	j.global_position = Vector3(30, 0, 30)
	_comprobar(j._sonido_paso() == "paso_hierba", "paso en hierba fuera de parcelas")

	# 5. Herramientas y cosecha en granja
	var p := Cultivos.parcelas()
	var k := ""
	for clave: Variant in p:
		k = str(clave)
		break
	if not k.is_empty():
		var c := Cultivos.parcela(k)
		c["estado"] = "maleza"
		Cultivos.aplicar("hoz", [k])
		_comprobar(int(Audio.conteo_efectos.get("hoz", 0)) >= 1, "hoz dispara sonido hoz")
		c["estado"] = "piedra"
		Cultivos.aplicar("pico", [k])
		_comprobar(int(Audio.conteo_efectos.get("pico", 0)) >= 1, "pico dispara sonido pico")
		c["estado"] = "tronco"
		Cultivos.aplicar("hacha", [k])
		_comprobar(int(Audio.conteo_efectos.get("hacha", 0)) >= 1, "hacha dispara sonido hacha")
		c["estado"] = "limpio"
		Cultivos.aplicar("azada", [k])
		_comprobar(int(Audio.conteo_efectos.get("azada", 0)) >= 1, "azada dispara sonido azada")
		c["regado"] = false
		Cultivos.aplicar("regadera", [k])
		_comprobar(int(Audio.conteo_efectos.get("regadera", 0)) >= 1, "regadera dispara sonido regadera")
		c["cultivo"] = "patata"
		c["listo"] = true
		Cultivos.cosechar(k)
		_comprobar(int(Audio.conteo_efectos.get("cosecha", 0)) >= 1, "cosechar dispara sonido cosecha")

	# 6. Interfaz: menú, clic, comprar, error
	Interfaz.abrir_inventario()
	await _fotogramas()
	_comprobar(int(Audio.conteo_efectos.get("ui_menu", 0)) >= 1, "abrir inventario dispara ui_menu")
	Interfaz.cerrar_todo()

	Interfaz.abrir_tienda("tienda_mateo")
	await _fotogramas()
	var tienda := Interfaz._tienda
	tienda._elegir("semilla_zanahoria")
	tienda._cantidad = 1
	tienda._confirmar()
	_comprobar(int(Audio.conteo_efectos.get("ui_comprar", 0)) >= 1, "comprar dispara ui_comprar")
	Juego.dinero = 0
	tienda._elegir("semilla_zanahoria")
	tienda._cantidad = 1
	tienda._confirmar()
	_comprobar(int(Audio.conteo_efectos.get("ui_error", 0)) >= 1, "compra sin dinero dispara ui_error")
	Interfaz.cerrar_todo()

	var btn := Button.new()
	add_child(btn)
	btn.pressed.emit()
	_comprobar(int(Audio.conteo_efectos.get("ui_clic", 0)) >= 1, "botón dispara ui_clic")
	btn.queue_free()

	# 7. Pueblo, interior y mina (música, ambiente, pasos y puerta)
	await Escenas.ir_a_mapa("pueblo")
	await _esperar_transicion()
	_comprobar(Audio.musica_actual == "mus_pueblo", "pueblo reproduce mus_pueblo")
	_comprobar(Audio.ambiente_actual == "amb_pueblo", "pueblo reproduce amb_pueblo")
	_comprobar((Escenas.jugador() as Jugador)._sonido_paso() == "paso_tierra", "paso en pueblo")

	var puerta := PuertaMapa.new()
	puerta.destino = "tienda"
	puerta.llegada = "Entrada"
	var cargo_tienda := [false]
	var cb_tienda := func(id_m: String) -> void:
		if id_m == "tienda":
			cargo_tienda[0] = true
	Escenas.mapa_cargado.connect(cb_tienda)
	puerta._al_usar(Escenas.jugador())
	var limite_puerta := Time.get_ticks_msec() + 15000
	while (not cargo_tienda[0] or Escenas.en_transicion) and Time.get_ticks_msec() < limite_puerta:
		await get_tree().process_frame
	if Escenas.mapa_cargado.is_connected(cb_tienda):
		Escenas.mapa_cargado.disconnect(cb_tienda)
	puerta.queue_free()
	_comprobar(cargo_tienda[0], "puerta carga tienda")
	_comprobar(int(Audio.conteo_efectos.get("puerta_abrir", 0)) >= 1, "puerta dispara puerta_abrir")
	_comprobar(int(Audio.conteo_efectos.get("puerta_cerrar", 0)) >= 1, "puerta dispara puerta_cerrar")
	_comprobar(Audio.musica_actual == "mus_interiores", "interior reproduce mus_interiores")
	_comprobar((Escenas.jugador() as Jugador)._sonido_paso() == "paso_madera", "paso en interior")

	await Escenas.ir_a_mapa("mina_interior")
	await _esperar_transicion()
	_comprobar(Audio.musica_actual == "mus_mina", "mina reproduce mus_mina")
	_comprobar(Audio.ambiente_actual == "amb_mina", "mina reproduce amb_mina")
	_comprobar((Escenas.jugador() as Jugador)._sonido_paso() == "paso_piedra", "paso en mina")

	_finalizar()
