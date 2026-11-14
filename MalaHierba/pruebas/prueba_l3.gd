extends Node
## Prueba del núcleo (L3). Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_l3.tscn
## Imprime «PRUEBA OK» o «PRUEBA FALLO: <motivo>» y sale con 0 o 1.

var _fallos: Array[String] = []
var _eventos: Dictionary = {}


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout


func _ejecutar() -> void:
	# La prueba no debe ser la escena actual: Escenas la descartaría al cambiar de mapa.
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_l3.json"   # no pisa la partida de verdad

	_prueba_datos()
	_prueba_entradas()
	_prueba_estado()
	_prueba_inventario()
	_prueba_guardado()
	_prueba_amistad_y_finales()
	await _prueba_mapa_y_jugador()
	await _prueba_mapas_reales()
	await _prueba_interfaz()
	await _prueba_escenas_de_menu()

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)))
		get_tree().quit(1)


# --- Datos ----------------------------------------------------------------------------------

func _prueba_datos() -> void:
	print("[datos]")
	_comprobar(not Datos.objeto("azada").is_empty(), "falta el objeto azada")
	_comprobar(Datos.objeto("no_existe").is_empty(), "objeto inexistente debe dar {}")
	_comprobar(str(Datos.cultivo_de_semilla("semilla_patata").get("id", "")) == "patata", "cultivo_de_semilla(patata)")
	_comprobar(str(Datos.npc("clara").get("modelo", "")) == "tendera", "Clara usa el modelo tendera")
	_comprobar(str(Datos.npc("mateo").get("modelo", "")) == "herrero", "Don Mateo usa el modelo herrero")
	_comprobar(Datos.ids_npc().size() == 6, "debe haber 6 vecinos")
	for id in Datos.ids_npc():
		for nivel in 3:
			var frases := Datos.dialogos_npc(id, nivel)
			_comprobar(frases.size() >= 4 and frases.size() <= 6, "%s nivel %d: %d frases" % [id, nivel, frases.size()])
		var n := Datos.npc(id)
		_comprobar(str(n.get("marcador", "")).begins_with("Spawn_"), "marcador de %s" % id)
		for g: Variant in n.get("gusta", []):
			_comprobar(Datos.existe_objeto(str(g)), "%s: gusto desconocido %s" % [id, str(g)])
	_comprobar(Datos.conexiones_de("pueblo").size() == 4, "el pueblo tiene 4 salidas")
	_comprobar(Datos.conexiones_de("granja").size() == 2, "la granja tiene 2 salidas")
	_comprobar(Datos.conexiones_de("bosque_norte").size() == 4, "bosque_norte tiene 4 salidas")
	_comprobar(Datos.conexiones_de("costa_lago").size() == 2, "costa_lago tiene 2 salidas")
	_comprobar(not str(Datos.texto("final.bueno.titulo")).is_empty(), "texto final bueno")
	_comprobar((Datos.texto("carta.parrafos", []) as Array).size() >= 6, "carta de la abuela Rosa")
	# Cada cultivo apunta a objetos que existen y hay 1 al menos por estación.
	var por_estacion := [0, 0, 0, 0]
	for id in Datos.ids_cultivos():
		var c := Datos.cultivo(id)
		_comprobar(Datos.existe_objeto(str(c["semilla"])), "semilla de %s" % id)
		_comprobar(Datos.existe_objeto(str(c["cosecha"])), "cosecha de %s" % id)
		for e: int in c["estaciones"]:
			por_estacion[e] += 1
		var pc := int(Datos.objeto(str(c["semilla"])).get("precio_compra", 0))
		var pv := int(Datos.objeto(str(c["cosecha"])).get("precio_venta", 0))
		_comprobar(pv > pc / 2, "%s: la cosecha debería rendir más que media semilla" % id)
	_comprobar(por_estacion[3] >= 2 and por_estacion[0] >= 2 and por_estacion[1] >= 2 and por_estacion[2] >= 2, "cultivos por estación: %s" % str(por_estacion))
	var tienda := Datos.tienda("tienda_mateo")
	_comprobar((tienda["vende"] as Array).has("pan"), "Don Mateo vende pan")
	for id: String in tienda["vende"]:
		_comprobar(Datos.existe_objeto(id), "la tienda vende un objeto que no existe: %s" % id)
	_comprobar(not Datos.mejora("azada", 1).is_empty(), "mejora de azada")


func _prueba_entradas() -> void:
	print("[entradas]")
	for a in ["mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo", "correr", "interactuar", "usar",
			"inventario", "pausa", "pantalla_completa", "ranura_1", "ranura_5", "ranura_10"]:
		_comprobar(InputMap.has_action(a), "falta la acción %s" % a)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_W
	e.pressed = true
	_comprobar(e.is_action("mover_arriba"), "W debe mover hacia arriba")
	var e2 := InputEventKey.new()
	e2.physical_keycode = KEY_TAB
	_comprobar(e2.is_action("inventario"), "Tab abre el inventario")
	var e3 := InputEventMouseButton.new()
	e3.button_index = MOUSE_BUTTON_LEFT
	_comprobar(e3.is_action("usar"), "clic izquierdo = usar")


# --- Estado, tiempo, energía, dinero ---------------------------------------------------------------

func _prueba_estado() -> void:
	print("[estado]")
	Juego.nueva_partida("Prueba")
	_comprobar(Juego.nombre_jugador == "Prueba", "nombre del jugador")
	_comprobar(Juego.dinero == 500 and Juego.deuda == 5000, "dinero y deuda iniciales")
	_comprobar(Juego.dia == 1 and Juego.estacion == 0 and Juego.minutos == 360, "fecha inicial")
	_comprobar(Juego.texto_hora() == "06:00", "hora inicial 06:00")
	_comprobar(Juego.cantidad("azada") == 1 and Juego.cantidad("semilla_patata") == 15 and Juego.cantidad("bocadillo") == 2, "inventario inicial")
	_comprobar(str(Juego.objeto_activo().get("id", "")) == "azada", "ranura 0 = azada")
	_comprobar(Juego.inventario.size() == 30, "30 huecos")

	Juego.avanzar_minutos(60)
	_comprobar(Juego.minutos == 420 and Juego.texto_hora() == "07:00", "avanzar 60 minutos")

	# Energía.
	_comprobar(Juego.gastar_energia(30.0) and is_equal_approx(Juego.energia, 70.0), "gastar energía")
	_comprobar(not Juego.gastar_energia(100.0) and is_equal_approx(Juego.energia, 70.0), "no gasta si no hay bastante")
	Juego.recuperar_energia(500.0)
	_comprobar(is_equal_approx(Juego.energia, 100.0), "recuperar se limita al máximo")

	# Dinero.
	Juego.ingresar(100)
	_comprobar(Juego.dinero == 600, "ingresar")
	_comprobar(not Juego.cobrar(1000) and Juego.dinero == 600, "cobrar sin fondos no resta")
	_comprobar(Juego.cobrar(200) and Juego.dinero == 400, "cobrar")

	# Dormir → día siguiente con energía llena.
	Juego.hablado_hoy["clara"] = true
	Juego.energia = 12.0
	var dia_antes := Juego.dia
	Juego.dormir()
	_comprobar(Juego.dia == dia_antes + 1, "dormir pasa al día siguiente")
	_comprobar(is_equal_approx(Juego.energia, Juego.energia_max), "dormir llena la energía")
	_comprobar(Juego.minutos == Juego.HORA_INICIO, "se despierta a las 06:00")
	_comprobar(Juego.hablado_hoy.is_empty(), "se reinicia hablado_hoy")

	# Desmayo: la mitad de energía y pierde algo de dinero.
	var dinero_antes := Juego.dinero
	Juego.energia = 2.0
	Juego.terminar_dia(true)
	_comprobar(is_equal_approx(Juego.energia, Juego.energia_max * 0.5), "desmayo: mitad de energía")
	_comprobar(Juego.dinero < dinero_antes and Juego.dinero >= dinero_antes - 150, "desmayo: pierde un poco de dinero (%d → %d)" % [dinero_antes, Juego.dinero])

	# El reloj llega a las 02:00 y desmaya solo.
	Juego.minutos = Juego.HORA_FIN - 1
	var d := Juego.dia
	Juego.avanzar_minutos(1)
	_comprobar(Juego.dia == d + 1 and Juego.minutos == Juego.HORA_INICIO, "a las 02:00 pasa al día siguiente")

	# Estaciones: día 28 → día 1 de la siguiente.
	Juego.dia = 28
	Juego.estacion = 0
	Juego.dormir()
	_comprobar(Juego.dia == 1 and Juego.estacion == 1, "cambio de estación")
	_comprobar(Juego.texto_fecha() == "Verano, día 1", "texto de fecha: %s" % Juego.texto_fecha())

	# Clima: el invierno nunca llueve; el resto, alguna vez.
	Juego.estacion = 3
	var lluvias_invierno := 0
	for i in 200:
		Juego._sortear_clima()
		if Juego.clima == "lluvia":
			lluvias_invierno += 1
	_comprobar(lluvias_invierno == 0, "en invierno no llueve")
	Juego.estacion = 1
	var lluvias := 0
	for i in 1000:
		Juego._sortear_clima()
		if Juego.clima == "lluvia":
			lluvias += 1
	_comprobar(lluvias > 120 and lluvias < 290, "≈20 %% de días de lluvia (salieron %d de 1000)" % lluvias)

	# Fin de año.
	_eventos["fin"] = false
	var al_fin := func() -> void: _eventos["fin"] = true
	Juego.fin_de_anio.connect(al_fin)
	# Escenas lanzaría de verdad la escena final: se desconecta mientras dura la comprobación.
	Juego.fin_de_anio.disconnect(Escenas._al_fin_de_anio)
	Juego.estacion = 3
	Juego.dia = 28
	var sigue := Juego.terminar_dia(false)
	_comprobar(not sigue and bool(_eventos["fin"]), "fin de año emite fin_de_anio")
	Juego.fin_de_anio.disconnect(al_fin)
	Juego.fin_de_anio.connect(Escenas._al_fin_de_anio)
	Escenas._fin_solicitado = false


# --- Inventario -----------------------------------------------------------------------------------

func _prueba_inventario() -> void:
	print("[inventario]")
	Juego.nueva_partida("Prueba")
	_comprobar(Juego.anadir_objeto("piedra", 10) == 0, "añadir 10 piedras")
	_comprobar(Juego.cantidad("piedra") == 10, "cantidad de piedra")
	_comprobar(Juego.quitar_objeto("piedra", 4) and Juego.cantidad("piedra") == 6, "quitar 4")
	_comprobar(not Juego.quitar_objeto("piedra", 7) and Juego.cantidad("piedra") == 6, "quitar de más no hace nada")
	# Pilas de 99.
	Juego.anadir_objeto("madera", 150)
	var pilas := 0
	for h: Dictionary in Juego.inventario:
		if not h.is_empty() and h["id"] == "madera":
			pilas += 1
			_comprobar(int(h["cantidad"]) <= 99, "pila de más de 99")
	_comprobar(pilas == 2, "150 de madera deben ocupar 2 pilas (%d)" % pilas)
	# Llenar el inventario.
	var libre := Juego.espacio_para("fibra")
	var sobra := Juego.anadir_objeto("fibra", libre + 25)
	_comprobar(sobra == 25, "inventario lleno: sobran 25 (sobraron %d)" % sobra)
	_comprobar(Juego.espacio_para("cobre") == 0, "no queda sitio")
	_comprobar(Juego.anadir_objeto("cobre", 1) == 1, "no cabe un objeto nuevo")
	_comprobar(Juego.quitar_objeto("fibra", Juego.cantidad("fibra")), "vaciar la fibra")
	_comprobar(Juego.cantidad("fibra") == 0 and Juego.espacio_para("cobre") > 0, "vuelve a haber sitio")
	_comprobar(Juego.anadir_objeto("no_existe", 1) == 1, "objeto desconocido no se añade")
	# Mover y juntar huecos.
	Juego.nueva_partida("Prueba")
	Juego.mover_huecos(0, 1)
	_comprobar(str(Juego.inventario[0]["id"]) == "regadera" and str(Juego.inventario[1]["id"]) == "azada", "intercambiar huecos")
	Juego.anadir_objeto("piedra", 5)
	Juego.inventario[20] = {"id": "piedra", "cantidad": 3}
	Juego.mover_huecos(20, 7)
	_comprobar(Juego.cantidad("piedra") == 8 and (Juego.inventario[20] as Dictionary).is_empty(), "juntar pilas")
	# Comer.
	Juego.energia = 50.0
	_comprobar(Juego.comer("bocadillo") and is_equal_approx(Juego.energia, 90.0) and Juego.cantidad("bocadillo") == 1, "comer un bocadillo")
	Juego.energia = Juego.energia_max
	_comprobar(not Juego.comer("bocadillo"), "no se come con la energía llena")
	# Ranura.
	Juego.elegir_ranura(12)
	_comprobar(Juego.ranura == 2, "la ranura da la vuelta (12 → 2)")
	Juego.elegir_ranura(-1)
	_comprobar(Juego.ranura == 9, "ranura -1 → 9")


# --- Guardado ------------------------------------------------------------------------------------------

func _prueba_guardado() -> void:
	print("[guardado]")
	Juego.nueva_partida("Marisol")
	Juego.ingresar(321)
	Juego.anadir_objeto("cuarzo", 3)
	Juego.subir_amistad("clara", 70)
	Juego.nivel_herramientas["azada"] = 2
	Juego.estado_mapas["granja"] = {"parcelas": {"3,4": {"cultivo": "patata", "dias": 2, "regada": true}}, "retirados": [1, 2, 3]}
	Juego.banderas["carta_leida"] = true
	Juego.dia = 9
	Juego.estacion = 1
	Juego.minutos = 700
	Juego.ranura = 4
	Juego.mapa_actual = "pueblo"
	var dinero_ref := Juego.dinero
	_comprobar(Juego.guardar(), "guardar devuelve true")
	_comprobar(Juego.hay_partida(), "hay partida guardada")
	# Se estropea todo y se carga.
	Juego.nueva_partida("Otro")
	_comprobar(Juego.nombre_jugador == "Otro" and Juego.dia == 1, "partida nueva distinta")
	_comprobar(Juego.cargar(), "cargar devuelve true")
	_comprobar(Juego.nombre_jugador == "Marisol", "nombre tras cargar")
	_comprobar(Juego.dinero == dinero_ref and typeof(Juego.dinero) == TYPE_INT, "dinero tras cargar es entero")
	_comprobar(Juego.dia == 9 and Juego.estacion == 1 and Juego.minutos == 700 and typeof(Juego.dia) == TYPE_INT, "fecha tras cargar")
	_comprobar(Juego.cantidad("cuarzo") == 3 and Juego.cantidad("semilla_patata") == 15, "inventario tras cargar")
	_comprobar(Juego.puntos_amistad("clara") == 70, "amistad tras cargar")
	_comprobar(Juego.nivel("azada") == 2, "nivel de herramienta tras cargar")
	_comprobar(Juego.ranura == 4 and Juego.mapa_actual == "pueblo", "ranura y mapa tras cargar")
	var parcela: Dictionary = Juego.estado_mapas["granja"]["parcelas"]["3,4"]
	_comprobar(str(parcela["cultivo"]) == "patata" and typeof(parcela["dias"]) == TYPE_INT and bool(parcela["regada"]), "estado de mapas anidado tras cargar")
	_comprobar(bool(Juego.banderas.get("carta_leida", false)), "banderas tras cargar")
	_comprobar(typeof((Juego.estado_mapas["granja"]["retirados"] as Array)[0]) == TYPE_INT, "enteros dentro de listas")


func _prueba_amistad_y_finales() -> void:
	print("[amistad y finales]")
	Juego.nueva_partida("Prueba")
	_comprobar(Juego.nivel_amistad("clara") == 0, "amistad nivel 0")
	Juego.subir_amistad("clara", 60)
	_comprobar(Juego.nivel_amistad("clara") == 1, "amistad nivel 1 con 60")
	Juego.subir_amistad("clara", 100)
	_comprobar(Juego.nivel_amistad("clara") == 2, "amistad nivel 2 con 160")
	Juego.subir_amistad("clara", 9999)
	_comprobar(Juego.puntos_amistad("clara") == Juego.AMISTAD_MAX, "la amistad tiene tope")
	# Finales.
	Juego.nueva_partida("Prueba")
	Juego.dinero = 4000
	_comprobar(Juego.final_logrado() == "malo", "dinero < deuda → malo")
	Juego.dinero = 6000
	_comprobar(Juego.final_logrado() == "regular", "salda pero sin amigos → regular")
	for id in Datos.ids_npc():
		Juego.amistad[id] = 120
	_comprobar(Juego.final_logrado() == "bueno", "salda y amistad alta → bueno")
	Juego.dinero = 4999
	_comprobar(Juego.final_logrado() == "malo", "con amigos pero sin saldar sigue siendo malo")
	var r := Juego.resumen_final()
	_comprobar(int(r["saldo"]) == 4999 - 5000, "resumen: saldo")


# --- Mapa de prueba y jugador ------------------------------------------------------------------------

func _prueba_mapa_y_jugador() -> void:
	print("[mapa y jugador]")
	Juego.nueva_partida("Prueba")
	Escenas.mapa_de_despertar = "prueba"
	await Escenas.ir_a_mapa("prueba")
	var mapa := Escenas.mapa_actual_nodo()
	_comprobar(mapa != null and str(mapa.get("id_mapa")) == "prueba", "ir_a_mapa carga el mapa de prueba")
	_comprobar(Juego.mapa_actual == "prueba", "Juego.mapa_actual")
	var j := Escenas.jugador() as Jugador
	_comprobar(j != null, "hay jugador tras ir_a_mapa")
	if j == null or mapa == null:
		return
	_comprobar(not Escenas.en_transicion, "la transición ha terminado")
	_comprobar(Interfaz.hud_visible(), "el HUD se ve en el mapa")
	var spawn := mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	_comprobar(spawn != null, "el mapa tiene Spawn_Protagonista")
	var d := Vector2(j.global_position.x - spawn.global_position.x, j.global_position.z - spawn.global_position.z).length()
	_comprobar(d < 0.5, "el jugador aparece en su marcador (a %.2f m)" % d)

	await _esperar(0.7)
	_comprobar(j.is_on_floor(), "el jugador está sobre el suelo")
	_comprobar(j.global_position.y > -0.2 and j.global_position.y < 0.6, "altura del jugador (%.2f)" % j.global_position.y)
	_comprobar(j.camara != null and j.camara.camara.current, "la cámara de juego está activa")

	# Movimiento: simula W mantenida.
	var p0 := j.global_position
	Input.action_press("mover_arriba")
	await _esperar(0.6)
	Input.action_release("mover_arriba")
	var recorrido := Vector2(j.global_position.x - p0.x, j.global_position.z - p0.z).length()
	_comprobar(recorrido > 1.0 and recorrido < 3.0, "andar 0,6 s con W recorre ~2 m (%.2f)" % recorrido)
	# La cámara mira hacia -Z (giro 0): W debe llevar hacia -Z.
	_comprobar(j.global_position.z < p0.z - 0.5, "con la cámara en giro 0, W va hacia delante (-Z)")
	await _esperar(0.3)

	# Correr es más rápido que andar.
	var p1 := j.global_position
	Input.action_press("mover_abajo")
	Input.action_press("correr")
	await _esperar(0.6)
	Input.action_release("mover_abajo")
	Input.action_release("correr")
	var corrido := Vector2(j.global_position.x - p1.x, j.global_position.z - p1.z).length()
	_comprobar(corrido > recorrido * 1.3, "correr recorre más que andar (%.2f frente a %.2f)" % [corrido, recorrido])
	await _esperar(0.3)

	# Interactuar: Clara está en (3, 0, -3).
	j.colocar(Vector3(1.8, 0.05, -3.0), 0.0, 0.0)
	j.direccion = Vector3(1, 0, 0)
	await _esperar(0.4)
	j._actualizar_interactuable()
	_comprobar(j._objetivo != null and j._objetivo.name == "Clara", "detecta a Clara delante")
	var hud: Hud = Interfaz.get("_hud")
	_comprobar(hud._cartel.visible and hud._l_cartel.text.contains("Hablar con Clara"), "cartel de acción «E · Hablar con Clara»")
	j._interactuar()
	_comprobar(Interfaz.ocupada(), "el diálogo abierto ocupa la interfaz")
	var dialogo: PanelDialogo = Interfaz.get("_dialogo")
	_comprobar(dialogo.visible, "diálogo visible")
	_comprobar(not Juego.tiempo_corre(), "el reloj se para con un diálogo")
	var antes := Juego.minutos
	await _esperar(0.5)
	_comprobar(Juego.minutos == antes, "el tiempo no avanza durante el diálogo")
	# Se completa la primera frase y se pasa a la segunda, y se cierra.
	dialogo._avanzar()
	dialogo._avanzar()
	dialogo._avanzar()
	dialogo._avanzar()
	_comprobar(not dialogo.visible and not Interfaz.ocupada(), "el diálogo se cierra tras la última frase")
	# Con el diálogo abierto el jugador no se mueve.
	Interfaz.mostrar_dialogo("Prueba", ["Hola"])
	var p2 := j.global_position
	Input.action_press("mover_derecha")
	await _esperar(0.4)
	Input.action_release("mover_derecha")
	_comprobar(j.global_position.distance_to(p2) < 0.1, "no se mueve con un diálogo abierto")
	dialogo._avanzar()
	dialogo._avanzar()
	_comprobar(not Interfaz.ocupada(), "diálogo cerrado")
	await _esperar(0.3)

	# Usar la azada en la parcela de prueba (-2, 0, -3).
	var parcela := mapa.get_node("Parcela")
	Juego.elegir_ranura(0)
	_comprobar(str(Juego.objeto_activo()["id"]) == "azada", "azada en la ranura 1")
	j.colocar(Vector3(-0.7, 0.05, -3.0), 0.0, 0.0)
	j.direccion = Vector3(-1, 0, 0)
	var energia_antes := Juego.energia
	j._usar()
	_comprobar(bool(parcela.get("arada")), "usar la azada ara la parcela")
	_comprobar(is_equal_approx(Juego.energia, energia_antes - 3.0), "usar gasta energía (%.1f → %.1f)" % [energia_antes, Juego.energia])
	var antes_pos := j.global_position
	Input.action_press("mover_derecha")
	await _esperar(0.25)
	Input.action_release("mover_derecha")
	_comprobar(j.global_position.distance_to(antes_pos) < 0.15, "durante el golpe de herramienta no se mueve")
	await _esperar(0.6)
	# Comer con la ranura de los bocadillos.
	Juego.energia = 40.0
	Juego.elegir_ranura(6)
	_comprobar(str(Juego.objeto_activo()["id"]) == "bocadillo", "bocadillos en la ranura 7")
	j._usar()
	_comprobar(is_equal_approx(Juego.energia, 80.0), "usar comida recupera energía")

	# Zoom de cámara.
	var d0 := j.camara.distancia
	for i in 30:
		j.camara.acercar(-1.0)
	_comprobar(is_equal_approx(j.camara._dist_obj, 2.5), "zoom mínimo 2,5 m (M1)")
	for i in 40:
		j.camara.acercar(1.0)
	_comprobar(is_equal_approx(j.camara._dist_obj, 22.0), "zoom máximo 22 m")
	j.camara.acercar(-10.0)
	# M2: Leo mide EscalaPersonaje.ESCALA de lo que medía y la vista de juego se acercó en la misma proporción (antes 12 m).
	_comprobar(absf(d0 - 12.0 * EscalaPersonaje.ESCALA) < 0.001, "distancia inicial de la cámara 12 m × escala de los personajes (%.2f)" % d0)

	# Salida: una salida de prueba que lleva al mismo mapa (recarga y recoloca).
	var plantilla := load("res://escenas/objetos/salida.tscn") as PackedScene
	var salida := plantilla.instantiate() as Area3D
	salida.set("destino", "prueba")
	salida.set("llegada", "Spawn_Protagonista")
	salida.set("texto", "Salida de prueba")
	mapa.add_child(salida)
	salida.global_position = Vector3(20, 0, 20)
	salida.call("armar")
	await _esperar(0.9)
	var mapa_viejo := mapa
	salida.call("_al_entrar", j)
	_comprobar(Escenas.en_transicion, "entrar en una salida inicia la transición")
	await Escenas.mapa_cargado
	await _esperar(0.6)
	var mapa_nuevo := Escenas.mapa_actual_nodo()
	_comprobar(mapa_nuevo != null and mapa_nuevo != mapa_viejo, "la salida carga un mapa nuevo")
	_comprobar(Escenas.jugador() != null and Escenas.jugador() != j, "y un jugador nuevo")
	_comprobar(not Escenas.en_transicion, "la transición termina")
	j = Escenas.jugador() as Jugador

	# Dormir con jugador: fundido, día siguiente y vuelta al mapa de despertar.
	var dia := Juego.dia
	Juego.dormir()
	_comprobar(Escenas.en_transicion, "dormir con jugador hace un fundido")
	await Escenas.mapa_cargado
	await _esperar(0.7)
	_comprobar(Juego.dia == dia + 1, "dormir pasa de día (%d → %d)" % [dia, Juego.dia])
	_comprobar(Escenas.jugador() != null and not Escenas.en_transicion, "se despierta con jugador en el mapa")
	_comprobar(Juego.minutos == Juego.HORA_INICIO, "despierta a las 06:00")

	# El reloj corre mientras se juega.
	var m0 := Juego.minutos
	await _esperar(2.2)
	_comprobar(Juego.minutos >= m0 + 2 and Juego.minutos <= m0 + 5, "el reloj corre ~1 min cada 0,7 s (%d → %d)" % [m0, Juego.minutos])


# --- Mapas reales de L1 y modelo de L2 (solo los que ya están exportados) ----------------------------------------

func _nombres_marcadores(id: String) -> Array:
	var ruta := "res://assets/mapas/%s/marcadores.json" % id
	if not FileAccess.file_exists(ruta):
		return []
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	var nombres: Array = []
	if datos is Dictionary:
		for m: Dictionary in (datos as Dictionary).get("marcadores", []):
			nombres.append(str(m.get("nombre", "")))
	return nombres


func _prueba_mapas_reales() -> void:
	print("[mapas reales]")
	Juego.nueva_partida("Prueba")
	Escenas.mapa_de_despertar = "granja"
	# Las conexiones apuntan a marcadores que existen en los mapas exportados.
	for id in ["granja", "pueblo", "mina_exterior", "mina_interior"]:
		var propios := _nombres_marcadores(id)
		if propios.is_empty():
			print("  (", id, ": aún sin exportar)")
			continue
		_comprobar(propios.has("Spawn_Protagonista"), "%s tiene Spawn_Protagonista" % id)
		for c: Dictionary in Datos.conexiones_de(id):
			if c.has("marcador"):
				_comprobar(propios.has(str(c["marcador"])), "%s: existe el marcador de salida %s" % [id, c["marcador"]])
			var destino := _nombres_marcadores(str(c["destino"]))
			if not destino.is_empty():
				_comprobar(destino.has(str(c["llegada"])), "%s existe en %s (llegada desde %s)" % [c["llegada"], c["destino"], id])
	for id in ["granja", "pueblo", "mina_exterior", "mina_interior"]:
		if _nombres_marcadores(id).is_empty():
			continue
		var t0 := Time.get_ticks_msec()
		var llegada := "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista"
		await Escenas.ir_a_mapa(id, llegada)
		var carga := (Time.get_ticks_msec() - t0) / 1000.0
		var mapa := Escenas.mapa_actual_nodo()
		_comprobar(mapa != null and str(mapa.get("id_mapa")) == id, "%s: ir_a_mapa carga el mapa real (%.1f s)" % [id, carga])
		var j := Escenas.jugador() as Jugador
		_comprobar(j != null, "%s: hay jugador" % id)
		if mapa == null or j == null:
			continue
		var m := mapa.call("marcador", llegada) as Marker3D
		_comprobar(m != null, "%s: existe %s" % [id, llegada])
		if m != null:
			var d := Vector2(j.global_position.x - m.global_position.x, j.global_position.z - m.global_position.z).length()
			_comprobar(d < 0.6, "%s: el jugador aparece en %s (a %.2f m)" % [id, llegada, d])
			_comprobar(absf(j.global_position.y - m.global_position.y) < 1.0, "%s: altura sobre el marcador (%.2f)" % [id, j.global_position.y - m.global_position.y])
		await _esperar(1.2)
		_comprobar(j.is_on_floor(), "%s: el jugador pisa el suelo" % id)
		_comprobar(not Escenas.en_transicion and Escenas.mapa_actual_nodo() == mapa, "%s: no salta solo a otra salida al llegar" % id)
		_comprobar(j.camara != null and j.camara.camara.current, "%s: cámara de juego activa" % id)
		if id == "mina_interior":
			_comprobar(j.get_node_or_null("Farol") != null or j.find_children("*", "OmniLight3D", true, false).size() > 0, "mina_interior: el jugador lleva farol")
		# Modelo de Leo con sus animaciones.
		var anim: AnimationPlayer = j._anim
		_comprobar(anim != null, "%s: Leo tiene AnimationPlayer" % id)
		if anim != null:
			for a in ["reposo", "andar", "herramienta"]:
				_comprobar(anim.has_animation(a), "%s: Leo tiene la animación %s" % [id, a])
		print("  ", id, " ok en ", "%.1f" % carga, " s, ", Engine.get_frames_per_second(), " fps")


# --- Interfaz: HUD, inventario, tienda, pregunta, pausa --------------------------------------------------------

func _prueba_interfaz() -> void:
	print("[interfaz]")
	var hud: Hud = Interfaz.get("_hud")
	Juego.dinero = 1000
	Juego.dinero_cambiado.emit(1000)
	_comprobar(hud._l_dinero.text == "1.000 €", "dinero en el HUD con separador de miles: %s" % hud._l_dinero.text)
	_comprobar(Estilo.euros(5000) == "5.000 €" and Estilo.euros(12) == "12 €" and Estilo.euros(1234567) == "1.234.567 €", "formato de euros")
	Juego.energia = 25.0
	Juego.energia_cambiada.emit(25.0, 100.0)
	_comprobar(hud._l_energia.text.contains("25"), "barra de energía")
	_comprobar(hud._huecos[0].datos.get("id", "") == "azada", "la barra rápida muestra la azada")

	# Avisos.
	Interfaz.mensaje("Aviso de prueba")
	_comprobar(hud._avisos.get_child_count() >= 1, "los avisos aparecen")

	# Pregunta.
	_eventos["resp"] = -1
	var resp := func(i: int) -> void: _eventos["resp"] = i
	Interfaz.preguntar("¿Pregunta?", ["Sí", "No"], resp)
	var pregunta: PanelPregunta = Interfaz.get("_pregunta")
	_comprobar(pregunta.visible and Interfaz.ocupada(), "la pregunta se muestra")
	pregunta._elegir(1)
	_comprobar(int(_eventos["resp"]) == 1 and not Interfaz.ocupada(), "la pregunta devuelve el índice elegido")

	# Inventario.
	var inv: PanelInventario = Interfaz.get("_inventario")
	inv.abrir()
	_comprobar(inv.visible and Interfaz.ocupada(), "inventario abierto")
	_comprobar(inv._huecos.size() == 30, "30 huecos en el inventario")
	var id0 := str(Juego.inventario[0]["id"])
	var id3 := str(Juego.inventario[3]["id"])
	inv._al_pulsar(inv._huecos[0], MOUSE_BUTTON_LEFT)
	inv._al_pulsar(inv._huecos[3], MOUSE_BUTTON_LEFT)
	_comprobar(str(Juego.inventario[0]["id"]) == id3 and str(Juego.inventario[3]["id"]) == id0, "clic en dos huecos los intercambia")
	inv._al_pulsar(inv._huecos[0], MOUSE_BUTTON_LEFT)
	inv._al_pulsar(inv._huecos[3], MOUSE_BUTTON_LEFT)
	inv.cerrar_panel()
	_comprobar(not Interfaz.ocupada(), "inventario cerrado")

	# Tienda de Don Mateo.
	Juego.nueva_partida("Prueba")
	Juego.mapa_actual = "prueba"
	Interfaz.mostrar_hud(true)
	var tienda: PanelTienda = Interfaz.get("_tienda")
	Interfaz.abrir_tienda("tienda_mateo")
	_comprobar(tienda.visible and Interfaz.ocupada(), "tienda abierta")
	var ids := tienda._ids_visibles()
	_comprobar(ids.has("semilla_zanahoria") and ids.has("pan") and not ids.has("semilla_ajo"), "en primavera solo hay semillas de primavera (%s)" % str(ids))
	tienda._elegir("semilla_zanahoria")
	tienda._cantidad = 3
	var dinero_antes := Juego.dinero
	tienda._confirmar()
	var precio_zanahoria := int(Datos.objeto("semilla_zanahoria").get("precio_compra", 0))
	_comprobar(Juego.cantidad("semilla_zanahoria") == 3 and Juego.dinero == dinero_antes - 3 * precio_zanahoria, "comprar 3 semillas de zanahoria (%d → %d)" % [dinero_antes, Juego.dinero])
	Juego.dinero = 5
	tienda._elegir("semilla_melon")
	tienda._cantidad = 1
	tienda._confirmar()
	_comprobar(Juego.dinero == 5 and Juego.cantidad("semilla_melon") == 0, "sin dinero no se compra")
	Juego.anadir_objeto("patata", 5)
	Juego.anadir_objeto("cobre", 2)
	Juego.anadir_objeto("azada", 1)
	tienda._cambiar_modo("vender")
	var vendibles := tienda._ids_visibles()
	_comprobar(vendibles.has("patata") and vendibles.has("cobre") and not vendibles.has("azada") and not vendibles.has("semilla_patata"), "se pueden vender cultivos y minerales, no herramientas ni semillas (%s)" % str(vendibles))
	tienda._elegir("patata")
	tienda._cantidad = 5
	var antes_v := Juego.dinero
	tienda._confirmar()
	var precio_patata := int(Datos.objeto("patata").get("precio_venta", 0))
	_comprobar(Juego.dinero == antes_v + 5 * precio_patata and Juego.cantidad("patata") == 0, "vender 5 patatas (%d → %d)" % [antes_v, Juego.dinero])
	tienda.cerrar_panel()
	_comprobar(not Interfaz.ocupada(), "tienda cerrada")
	Interfaz.abrir_tienda("taberna")
	_comprobar(tienda.visible and tienda._ids_visibles().has("guiso"), "taberna abierta con comidas")
	tienda.cerrar_panel()

	# Pausa.
	var pausa: PanelPausa = Interfaz.get("_pausa")
	pausa.abrir()
	_comprobar(pausa.visible and Interfaz.ocupada(), "pausa abierta")
	pausa.cerrar_panel()
	_comprobar(not Interfaz.ocupada(), "pausa cerrada")


# --- Menú, intro y final ------------------------------------------------------------------------------------

func _prueba_escenas_de_menu() -> void:
	print("[menú, intro, final]")
	Juego.nueva_partida("Prueba")
	await Escenas.ir_a_escena(Escenas.ESCENA_MENU)
	var menu := get_tree().current_scene
	_comprobar(menu != null and menu.name == "MenuPrincipal", "se carga el menú principal")
	_comprobar(not Interfaz.hud_visible(), "el menú no muestra el HUD")
	await Escenas.ir_a_escena(Escenas.ESCENA_INTRO)
	_comprobar(get_tree().current_scene != null and get_tree().current_scene.name == "Intro", "se carga la intro")
	await Escenas.ir_a_escena(Escenas.ESCENA_FINAL)
	_comprobar(get_tree().current_scene != null and get_tree().current_scene.name == "Final", "se carga el final")
	await Escenas.ir_a_escena(Escenas.ESCENA_MENU)
	_comprobar(get_tree().current_scene != null and get_tree().current_scene.name == "MenuPrincipal", "vuelta al menú")
