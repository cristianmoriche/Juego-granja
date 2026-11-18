extends Node
## Prueba el flujo de combate con eventos reales y una arena física aislada de la granja.

const NIVEL_IDS := ["rata_mina", "sapo_ciego", "arana_cristal", "salamandra_magma"]
const NIVELES := [1, 6, 11, 20]
const ARMAS := ["daga_cobre", "espada_hierro", "maza_hierro", "martillo_guerra_cuarzo"]
var _ok := 0
var _fallos := 0
var _leo: Jugador
var _arena: Node3D
var _centro: Vector3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	Juego.ruta_partida = "user://partida_prueba_h02.json"
	Ajustes.ruta = "user://ajustes_prueba_h02.cfg"
	Juego.borrar_partida()
	Ajustes.restaurar_teclas()
	Ajustes.poner("tutorial", false)
	Ajustes.poner("reducir_movimiento", true)
	Ajustes.poner("vista", 0)
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	get_tree().current_scene = null
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	_leo = Escenas.jugador() as Jugador
	if _leo == null:
		push_error("H02: no se pudo cargar la granja.")
		get_tree().quit(1)
		return
	_preparar_arena()
	await _esperar(0.18)
	_catalogo_y_forja()
	await _equipo_con_mando()
	await _controles_y_combos()
	await _defensa()
	await _vida_y_resistencia()
	await _contacto_tridimensional()
	_equilibrio_por_profundidad()
	await _enemigos_y_botin()
	await _romper_guardia()
	await _presion_en_grupo()
	await _retiradas()
	await _navegacion()
	await _guardado_y_despertar()
	Juego.borrar_partida()
	print("H02 combate: %d correctas, %d fallos." % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _preparar_arena() -> void:
	_arena = Node3D.new()
	Escenas.mapa_actual_nodo().add_child(_arena)
	_centro = _leo.global_position + Vector3.UP * 14.0
	_bloque(_centro + Vector3.DOWN * 0.26, Vector3(18.0, 0.50, 18.0))
	_leo.colocar(_centro + Vector3.UP * 0.04, NAN, 0.0)


func _bloque(posicion: Vector3, tamano: Vector3) -> StaticBody3D:
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	var volumen := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = tamano
	volumen.shape = caja
	cuerpo.add_child(volumen)
	_arena.add_child(cuerpo)
	cuerpo.global_position = posicion
	return cuerpo


func _catalogo_y_forja() -> void:
	var tienda := Datos.tienda("forja")
	_comprobar((tienda.get("vende", []) as Array).size() == 8 and (tienda.get("forja", []) as Array).size() == 24,
		"ocho piezas de compra directa y veinticuatro recetas")
	for id: String in tienda.get("forja", []):
		var o := Datos.objeto(id)
		_comprobar(Datos.tiene_icono(id) and Datos.existe_objeto(str(o["forja"]["material"])), "icono y mineral de " + id)
	for familia: String in ["daga", "espada", "maza", "martillo_guerra", "escudo"]:
		var escena := load("res://assets/combate/%s.glb" % familia) as PackedScene
		var modelo := escena.instantiate()
		var pbr := false
		for mi: MeshInstance3D in modelo.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(i) as BaseMaterial3D
					pbr = pbr or (mat != null and mat.normal_enabled and mat.albedo_texture != null)
		_comprobar(pbr, familia + " tiene malla con color y mapa normal")
		modelo.free()
	_comprobar(not Juego.forjar_equipo("espada_hierro"), "la forja no cobra si falta hierro")
	Juego.anadir_objeto("hierro", 20)
	var dinero := Juego.dinero
	var receta: Dictionary = Datos.objeto("espada_hierro")["forja"]
	_comprobar(Juego.forjar_equipo("espada_hierro") and Juego.cantidad("espada_hierro") == 1
		and Juego.dinero == dinero - int(receta.dinero) and Juego.cantidad("hierro") == 20 - int(receta.cantidad),
		"forjar consume justo el precio y el mineral y entrega el arma")
	var golpes: Array[int] = []
	var impactos: Array[int] = []
	for i in NIVELES.size():
		var nivel: int = NIVELES[i]
		var vida_media := 0.0
		var dano_medio := 0.0
		var cantidad := 0
		for d: Dictionary in Enemigo.normales_para_nivel(nivel):
			var intervalo: Array = d["niveles"]
			var d_nivel := float(nivel - int(intervalo[0]))
			vida_media += float(d["vida"]) * (1.0 + 0.028*d_nivel)
			dano_medio += float(d["dano"]) * (1.0 + 0.024*d_nivel)
			cantidad += 1
		var arma := Datos.objeto(ARMAS[i])
		golpes.append(ceili(vida_media / cantidad / float(arma["dano"])))
		impactos.append(ceili(Juego.vida_max / (dano_medio / cantidad)))
		print("Nivel %d: %d golpes de referencia para abatir; %d recibidos para caer." % [nivel, golpes[-1], impactos[-1]])
	_comprobar(golpes[0] <= 2 and golpes[-1] >= 3 and impactos[0] > impactos[-1] * 2,
		"el nivel 1 permite aprender y el 20 exige más golpes y defensa")


func _equipo_con_mando() -> void:
	Juego.anadir_objeto("cobre", 4)
	var dagas := Juego.cantidad("daga_cobre")
	Interfaz.abrir_tienda("forja")
	var tienda := Interfaz._tienda
	await _esperar(0.08)
	await _pulsar_mando(JOY_BUTTON_DPAD_UP)
	_comprobar(get_viewport().gui_get_focus_owner() == tienda._b_forjar_tab,
		"la cruceta llega desde el equipo en venta hasta la pestaña Forjar")
	await _pulsar_mando(JOY_BUTTON_A)
	_comprobar(tienda._modo == "forjar" and get_viewport().gui_get_focus_owner() == tienda._lista.get_child(0),
		"A abre las recetas y da el foco a la primera")
	await _pulsar_mando(JOY_BUTTON_DPAD_RIGHT)
	_comprobar(get_viewport().gui_get_focus_owner() == tienda._b_confirmar,
		"derecha pasa de la receta a su botón Forjar")
	await _pulsar_mando(JOY_BUTTON_A)
	_comprobar(Juego.cantidad("daga_cobre") == dagas + 1, "la daga se puede forjar solo con mando")
	await _pulsar_mando(JOY_BUTTON_B)
	_comprobar(not tienda.visible, "B cierra la forja")

	_elegir("casco_cobre")
	Juego.mover_huecos(Juego.ranura, 9)
	Juego.elegir_ranura(8)
	Interfaz.abrir_inventario()
	await _esperar(0.08)
	var mochila := Interfaz._inventario
	await _pulsar_mando(JOY_BUTTON_DPAD_RIGHT)
	_comprobar(get_viewport().gui_get_focus_owner() == mochila._huecos[9] and mochila._b_equipo.visible,
		"el mando selecciona el casco y muestra Equipar")
	await _pulsar_mando(JOY_BUTTON_DPAD_RIGHT)
	await _pulsar_mando(JOY_BUTTON_A)
	_comprobar(Juego.equipo.get("casco", "") == "casco_cobre", "se puede equipar desde la mochila solo con mando")
	await _pulsar_mando(JOY_BUTTON_B)
	Juego.desequipar("casco")


func _controles_y_combos() -> void:
	_elegir("daga_cobre")
	var rata := _crear_enemigo("rata_mina", _centro + Vector3(0, 0.04, -1.36))
	rata.vida_max = 220.0
	rata.vida = rata.vida_max
	_leo.camara.mirar_hacia(rata.centro_impacto())
	await _esperar(0.14)
	_evento_raton(MOUSE_BUTTON_MIDDLE, true)
	await _esperar(0.035)
	_evento_raton(MOUSE_BUTTON_MIDDLE, false)
	_comprobar(_leo.combate.objetivo_fijado == rata, "clic central fija la criatura visible en primera persona")
	var antes := rata.vida
	await _toque(false)
	_comprobar(antes == rata.vida and _leo.combate.combo == 1, "primer golpe: preparación con la zona de golpe cerrada")
	await _esperar(0.49)
	_comprobar(is_equal_approx(rata.vida, antes - 24.0), "los fotogramas activos hieren una vez")
	await _toque(false)
	_comprobar(_leo.combate.combo == 2, "segundo toque enlaza el combo")
	await _esperar(0.53)
	await _toque(false)
	_comprobar(_leo.combate.combo == 3, "tercer toque completa el combo")
	await _esperar(0.60)
	_comprobar(is_equal_approx(rata.vida, antes - 24.0 * (1.0 + 1.12 + 1.32)), "los tres golpes tienen daño distinto")

	Ajustes.poner("vista", 1)
	await _esperar(0.34)
	_evento_mando(JOY_BUTTON_RIGHT_STICK, true)
	await _esperar(0.02)
	_evento_mando(JOY_BUTTON_RIGHT_STICK, false)
	await _esperar(0.12)
	_comprobar(_leo.combate.objetivo_fijado == null, "R3 suelta el objetivo en tercera persona")
	_leo.camara.mirar_hacia(rata.centro_impacto())
	_evento_mando(JOY_BUTTON_RIGHT_STICK, true)
	await _esperar(0.02)
	_evento_mando(JOY_BUTTON_RIGHT_STICK, false)
	_comprobar(_leo.combate.objetivo_fijado == rata, "R3 vuelve a fijar en tercera persona")
	antes = rata.vida
	_evento_mando(JOY_BUTTON_X, true)
	await _esperar(0.82)
	_comprobar(_leo.combate.cargado and is_equal_approx(rata.vida, antes - 24.0 * 1.85),
		"mantener X acierta un único golpe cargado")
	_evento_mando(JOY_BUTTON_X, false)
	await _esperar(0.45)
	rata.queue_free()
	await _esperar(0.14)


func _defensa() -> void:
	_leo.colocar(_centro + Vector3.UP * .04, NAN, 0.0)
	var en := _crear_enemigo("rata_mina", _centro + Vector3(0, 0.04, -1.32))
	_elegir("espada_hierro")
	var salud := Juego.vida
	_evento_raton(MOUSE_BUTTON_RIGHT, true)
	await _esperar(0.26)
	var resistencia := Juego.resistencia
	_leo.recibir_ataque(20.0, en, en.global_position)
	_comprobar(_leo.combate.bloqueando and is_equal_approx(Juego.vida, salud - 11.6)
		and Juego.resistencia < resistencia, "el arma desvía parte de un golpe a costa de resistencia")
	_evento_raton(MOUSE_BUTTON_RIGHT, false)
	await _esperar(0.06)

	_elegir("escudo_cobre")
	_leo._usar()
	_elegir("espada_hierro")
	_comprobar(Juego.equipo.get("escudo") == "escudo_cobre" and is_instance_valid(_leo._escudo_nodo),
		"el escudo ocupa la mano izquierda")
	Juego.curar_vida(100.0)
	_eje(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _esperar(0.04)
	salud = Juego.vida
	_leo.recibir_ataque(20, en, en.global_position)
	_comprobar(en.estado == Enemigo.Estado.GOLPEADO and Juego.vida == salud, "LT dentro de 0,2 s para y desequilibra")
	await _esperar(0.25)
	_leo.recibir_ataque(20, en, en.global_position)
	_comprobar(is_equal_approx(Juego.vida, salud - 6.8), "escudo de cobre bloquea el 66 % de frente")
	_eje(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _esperar(1.30)
	var punto := _leo.global_position
	_evento_mando(JOY_BUTTON_B, true)
	await _esperar(0.02)
	_evento_mando(JOY_BUTTON_B, false)
	await _esperar(0.08)
	salud = Juego.vida
	_leo.recibir_ataque(11, en, en.global_position)
	_comprobar(_leo.combate.invulnerable() and Juego.vida == salud and _leo.global_position.distance_to(punto) > .20,
		"B desplaza e impide recibir daño en la ventana de esquiva")
	await _esperar(0.39)
	_leo.recibir_ataque(11, en, en.global_position)
	_comprobar(Juego.vida < salud and not _leo.combate.invulnerable(), "la vulnerabilidad vuelve al acabar")
	en.queue_free()
	await _esperar(0.37)


func _vida_y_resistencia() -> void:
	_comprobar(Interfaz._hud.barra_vida_visible(), "el HUD de salud está disponible fuera de la mina")
	_elegir("casco_cobre")
	_leo._usar()
	_elegir("peto_hierro")
	_leo._usar()
	_elegir("botas_cuarzo")
	_leo._usar()
	var salud := Juego.vida
	_leo.recibir_ataque(20.0, null, _leo.global_position + Vector3.FORWARD)
	_comprobar(Juego.defensa_equipo() == 31.0 and salud - Juego.vida < 15.0, "casco, peto y botas aportan defensa por pieza")
	salud = Juego.vida
	_comprobar(Juego.comer("bocadillo") and Juego.vida > salud, "comer restaura salud fuera de la mina")
	await _esperar(.35)
	_leo.colocar(_centro + Vector3.UP*.04, NAN, 0.0)
	var antes := Juego.resistencia
	_tecla(KEY_W, true)
	_tecla(KEY_SHIFT, true)
	await _esperar(.42)
	_tecla(KEY_W, false)
	_tecla(KEY_SHIFT, false)
	_comprobar(Juego.resistencia < antes - 5.0, "correr gasta resistencia")
	antes = Juego.resistencia
	await _esperar(1.10)
	_comprobar(Juego.resistencia > antes, "la resistencia se recupera sola tras dejar de gastar")
	_leo.colocar(_centro + Vector3.UP*.04, NAN, 0.0)
	await _esperar(.14)
	var saltos := _leo.saltos
	_eje(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _esperar(0.18)
	_eje(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_comprobar(_leo.saltos == saltos + 1, "RT salta con el mando")
	await _esperar(.62)


func _contacto_tridimensional() -> void:
	_elegir("espada_hierro")
	_leo.colocar(_centro + Vector3.UP * 0.04, NAN, 0.0)
	var rata := _crear_enemigo("rata_mina", _centro + Vector3(0.0, 0.04, -1.38))
	rata.vida_max = 1000.0
	rata.vida = rata.vida_max
	var techo := _bloque(_centro + Vector3.UP * 3.5, Vector3(4.0, 0.2, 5.0))
	for primera: bool in [true, false]:
		Ajustes.poner("vista", 0 if primera else 1)
		await _esperar(0.27)
		_leo.camara.mirar_hacia(rata.centro_impacto())
		if primera:
			_evento_raton(MOUSE_BUTTON_MIDDLE, true)
			await _esperar(0.02)
			_evento_raton(MOUSE_BUTTON_MIDDLE, false)
			_comprobar(_leo.combate.objetivo_fijado == rata, "fijar en primera no sustituye la mira vertical")
		var vista := "primera" if primera else "tercera"
		var antes := rata.vida
		_leo.camara.mirar_hacia(_centro + Vector3(0.0, 8.0, -1.38))
		await _toque(not primera)
		await _esperar(0.68)
		_comprobar(rata.vida == antes, "en " + vista + " apuntar al techo no hiere a la rata")
		_leo.camara.mirar_hacia(_centro + Vector3(0.0, -7.0, -1.38))
		await _toque(not primera)
		await _esperar(0.68)
		_comprobar(rata.vida == antes, "en " + vista + " apuntar al suelo junto a Leo no hiere a la rata")
		_leo.camara.mirar_hacia(rata.centro_impacto())
		await _toque(not primera)
		await _esperar(0.68)
		_comprobar(rata.vida < antes, "en " + vista + " bajar la mira sí alcanza a la rata")
		if primera:
			_leo.combate.cambiar_objetivo()
	var posicion_rata := rata.global_position
	rata.global_position += Vector3.FORWARD * 1.8
	await _esperar(0.04)
	_leo.camara.mirar_hacia(rata.centro_impacto())
	var antes := rata.vida
	await _toque(true)
	await _esperar(0.68)
	_comprobar(rata.vida == antes, "en tercera el alcance se mide desde Leo")
	rata.global_position = posicion_rata
	Ajustes.poner("vista", 0)
	await _esperar(0.27)
	var muro := _bloque(_centro + Vector3(0.0, 1.0, -0.70), Vector3(1.7, 2.0, 0.1))
	_leo.camara.mirar_hacia(rata.centro_impacto())
	await _toque(false)
	await _esperar(0.68)
	_comprobar(rata.vida == antes, "el contacto no atraviesa una pared entre Leo y el enemigo")
	rata.queue_free()
	muro.queue_free()
	techo.queue_free()
	await _esperar(1.7)


func _equilibrio_por_profundidad() -> void:
	var vida_inicial := Juego.vida_max
	var daño_daga := float(Datos.objeto("daga_cobre")["dano"])
	var daño_martillo := float(Datos.objeto("martillo_guerra_cuarzo")["dano"])
	var inicio := Enemigo.new()
	inicio.configurar(Enemigo.normales_para_nivel(1)[0].merged({"nivel_mina": 1}))
	var fondo := Enemigo.new()
	fondo.configurar(Enemigo.jefe_para_nivel(20).merged({"nivel_mina": 20}))
	var golpes_inicio := ceili(inicio.vida_max / daño_daga)
	var golpes_fondo := ceili(fondo.vida_max / daño_martillo)
	var golpes_para_caer_inicio := ceili(vida_inicial / inicio.dano)
	var golpes_para_caer_fondo := ceili(vida_inicial / fondo.dano)
	_comprobar(golpes_inicio <= 2 and golpes_para_caer_inicio >= 12,
		"nivel 1 con daga de cobre: %d golpes a la rata, %d golpes recibidos para caer" % [golpes_inicio, golpes_para_caer_inicio])
	_comprobar(golpes_fondo >= 8 and golpes_para_caer_fondo <= 5,
		"nivel 20 con martillo de cuarzo: %d golpes al jefe, %d golpes recibidos para caer sin protección" % [golpes_fondo, golpes_para_caer_fondo])
	inicio.free()
	fondo.free()


func _enemigos_y_botin() -> void:
	Ajustes.poner("vista", 0)
	for i in NIVEL_IDS.size():
		_elegir(ARMAS[i])
		_leo.colocar(_centro + Vector3.UP*.04, NAN, 0.0)
		var en := _crear_enemigo(NIVEL_IDS[i], _centro + Vector3(0.0,.04,-1.27), NIVELES[i])
		en.rotation.y = 0.0
		_leo.camara.mirar_hacia(en.centro_impacto())
		await _esperar(.38)
		var inicial := en.vida
		var murio := [false]
		en.fallecido.connect(func(_e: Enemigo) -> void: murio[0] = true)
		var toques := 0
		while is_instance_valid(en) and not en.muerto and toques < 8:
			if Juego.resistencia < 39.0:
				await _esperar(2.7)
			_evento_raton(MOUSE_BUTTON_LEFT, true)
			await _esperar(.44)
			_evento_raton(MOUSE_BUTTON_LEFT, false)
			await _esperar(1.38)
			if toques == 0:
				_comprobar(not is_instance_valid(en) or en.vida < inicial, "golpe real contra " + NIVEL_IDS[i])
			toques += 1
		_comprobar(murio[0], "Leo derrota a " + NIVEL_IDS[i])
		var botines := get_tree().get_nodes_in_group("botin_enemigo")
		var botin := botines.back() as Interactuable if not botines.is_empty() else null
		if botin != null:
			var mineral := str(botin.get("id_mineral"))
			var total := Juego.cantidad(mineral)
			var unidades := int(botin.get("unidades"))
			_leo.camara.mirar_hacia(botin.global_position + Vector3.UP*.22)
			await _esperar(.10)
			_tecla(KEY_E, true)
			await _esperar(.025)
			_tecla(KEY_E, false)
			_comprobar(Juego.cantidad(mineral) == total + unidades, "recoges " + mineral + " con E")
			if is_instance_valid(botin):
				botin.queue_free()
		else:
			_comprobar(false, "falta botín de la zona %d" % (i+1))
		if is_instance_valid(en):
			en.queue_free()
		await _esperar(.09)


func _presion_en_grupo() -> void:
	Juego.curar_vida(100.0)
	_leo.colocar(_centro + Vector3.UP*.04, NAN, 0.0)
	var grupo: Array[Enemigo] = []
	for i in 5:
		var pos := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 5.0) * 0.95
		var en := _crear_enemigo("rata_mina", _centro + pos + Vector3.UP*.04)
		en.rotation.y = atan2(-pos.x, -pos.z)
		en.set_physics_process(true)
		grupo.append(en)
	var simultaneos := 0
	var sin_turno := 0
	for i in 150:
		await get_tree().physics_frame
		var atacan := 0
		for en in grupo:
			if en.estado == Enemigo.Estado.ATACAR:
				atacan += 1
				sin_turno += int(not en.is_in_group(Enemigo.GRUPO_ATAQUE))
		simultaneos = maxi(simultaneos, atacan)
	_comprobar(simultaneos == 2 and sin_turno == 0, "cinco enemigos comparten dos turnos simultáneos de ataque")
	for en in grupo:
		en.queue_free()
	await _esperar(.1)


func _retiradas() -> void:
	_leo.colocar(_centro + Vector3.UP * 0.04, NAN, 0.0)
	var rata := _crear_enemigo("rata_mina", _centro + Vector3(0.0, 0.06, -2.0))
	rata.vida = rata.vida_max * 0.18
	rata._instinto.recordar(_leo.global_position)
	rata.set_physics_process(true)
	await _esperar(0.26)
	_comprobar(rata.estado == Enemigo.Estado.HUIDA and rata.global_position.z < _centro.z - 2.25,
		"una criatura malherida se aleja sin ocupar turno de ataque")
	rata.queue_free()
	var jefa := _crear_enemigo("rata_reina", _centro + Vector3(0.0, 0.06, -2.0), 5)
	jefa.vida = jefa.vida_max * 0.18
	jefa._instinto.recordar(_leo.global_position)
	jefa.set_physics_process(true)
	await _esperar(0.24)
	_comprobar(jefa.estado == Enemigo.Estado.HUIDA and jefa._retirada_jefe_hecha,
		"la jefa se repliega al quedar malherida")
	await _esperar(0.80)
	_comprobar(jefa.estado != Enemigo.Estado.HUIDA, "la jefa vuelve al combate tras un repliegue")
	jefa.queue_free()


func _navegacion() -> void:
	var primero := _centro + Vector3(-3.1,.03,0)
	var meta := _centro + Vector3(3.0,.03,0)
	var muro := _bloque(_centro + Vector3.UP*.64, Vector3(.42,1.3,2.05))
	var en := _crear_enemigo("rata_mina", primero)
	en.rotation.y = PI * .5
	await _esperar(.11)
	_comprobar(not en.linea_despejada(meta + Vector3.UP*.90), "el obstáculo corta la línea de visión")
	var distancia := primero.distance_to(meta)
	for i in 380:
		await get_tree().physics_frame
		en._instinto.paso(en, meta, get_physics_process_delta_time(), 3.4)
	_comprobar(en.global_position.distance_to(meta) < distancia * .28, "un enemigo rodea un obstáculo físico y avanza")
	en.queue_free()
	muro.queue_free()
	Juego.banderas["nivel_mina"] = 10
	await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	_leo = Escenas.jugador() as Jugador
	var mina := Escenas.mapa_actual_nodo().get_node_or_null("Objetos/NivelMina") as NivelMina
	if mina == null:
		_comprobar(false, "carga la mina procedural")
		return
	var salida := NivelMina._mundo_celda(Vector2i.ZERO)
	var fondo := NivelMina._mundo_celda(mina._celda_bajada)
	var ruta := mina.ruta_enemigo(Vector3(salida.x, 0, salida.y), Vector3(fondo.x, 0, fondo.y))
	var todos_pisables := true
	for p: Vector3 in ruta:
		todos_pisables = todos_pisables and mina._celdas_cavadas.has(mina._celda_pisable(p))
	_comprobar(ruta.size() > 6 and todos_pisables and Vector2(ruta[-1].x, ruta[-1].z).distance_to(fondo) < .1,
		"la ruta A* sigue galerías pisables hasta el fondo real")


func _romper_guardia() -> void:
	var en := _crear_enemigo("golem_cuarzo", _centro + Vector3(0,.06,-2.0), 13)
	var vida := en.vida
	en.recibir_golpe(24, Vector3.FORWARD, false, 0.0)
	_comprobar(vida - en.vida < 15.0, "el gólem acorazado amortigua un golpe frontal ligero")
	en.estado = Enemigo.Estado.LIBRE
	en._t_estado = 0.0
	vida = en.vida
	en.recibir_golpe(24, Vector3.FORWARD, true, 0.75)
	_comprobar(is_equal_approx(vida - en.vida, 24.0) and en._t_estado >= .75,
		"un golpe que rompe guardia hace daño completo y aturde")
	en.queue_free()
	await _esperar(.08)


func _guardado_y_despertar() -> void:
	_comprobar(Juego.guardar(), "guarda el formato 3 con el equipo y las armas")
	Juego.equipo.clear()
	_comprobar(Juego.cargar() and Juego.equipo.size() == 4 and Juego.cantidad("martillo_guerra_cuarzo") > 0,
		"cargar restaura las cuatro piezas y la barra rápida")
	var anterior := Juego.leer_archivo(Juego.ruta_partida)
	anterior["version"] = 2
	anterior.erase("equipo")
	var f := FileAccess.open(Juego.ruta_partida, FileAccess.WRITE)
	f.store_string(JSON.stringify(anterior))
	f.close()
	_comprobar(Juego.cargar() and Juego.equipo.is_empty() and Juego.cantidad("daga_cobre") > 0,
		"una partida con versión 2 migra sin perder inventario")
	var antes := Juego.dinero
	var dia := Juego.dia
	Juego.recibir_dano(999.0)
	Juego.recibir_dano(999.0)
	await _esperar(.16)
	_comprobar(Juego.vida <= .01 and _leo._anim_actual == "combate_desmayo", "Leo se desmaya al agotar la salud")
	for _i in 60:
		if not Escenas.en_transicion:
			break
		await _esperar(.12)
	_comprobar(Juego.mapa_actual == "casa_leo" and Juego.dia == dia + 1 and Juego.vida == Juego.vida_max * .75,
		"despierta en casa al día siguiente, con salud parcial")
	_comprobar(Juego.dinero == antes - mini(antes, clampi(antes / 10, 10, 150))
		and Juego.leer_archivo(Juego.ruta_partida).get("mapa_actual") == "casa_leo",
		"pierde dinero una vez y el autoguardado conserva la casa como destino")


func _crear_enemigo(id: String, punto: Vector3, nivel: int = 1) -> Enemigo:
	for d: Dictionary in Enemigo.cargar_definiciones():
		if str(d["id"]) != id:
			continue
		var copia := d.duplicate()
		copia["nivel_mina"] = nivel
		var en := Enemigo.new()
		en.configurar(copia)
		_arena.add_child(en)
		en.global_position = punto
		en.set_physics_process(false)
		return en
	return null


func _elegir(id: String) -> void:
	if Juego.cantidad(id) == 0:
		_comprobar(Juego.anadir_objeto(id) == 0, "entra en la mochila " + id)
	for i in Juego.inventario.size():
		if str(Juego.inventario[i].get("id", "")) == id:
			if i >= 10:
				Juego.mover_huecos(i, 9)
				i = 9
			Juego.elegir_ranura(i)
			return


func _toque(mando: bool) -> void:
	if mando:
		_evento_mando(JOY_BUTTON_X, true)
	else:
		_evento_raton(MOUSE_BUTTON_LEFT, true)
	await _esperar(.045)
	if mando:
		_evento_mando(JOY_BUTTON_X, false)
	else:
		_evento_raton(MOUSE_BUTTON_LEFT, false)
	await _esperar(.028)


func _evento_raton(boton: MouseButton, pulsado: bool) -> void:
	var evento := InputEventMouseButton.new()
	evento.button_index = boton
	evento.pressed = pulsado
	Input.parse_input_event(evento)


func _evento_mando(boton: JoyButton, pulsado: bool) -> void:
	var evento := InputEventJoypadButton.new()
	evento.button_index = boton
	evento.pressed = pulsado
	Input.parse_input_event(evento)


func _pulsar_mando(boton: JoyButton) -> void:
	_evento_mando(boton, true)
	await _esperar(0.03)
	_evento_mando(boton, false)
	await _esperar(0.07)


func _eje(eje: JoyAxis, fuerza: float) -> void:
	var evento := InputEventJoypadMotion.new()
	evento.axis = eje
	evento.axis_value = fuerza
	Input.parse_input_event(evento)


func _tecla(codigo: Key, pulsada: bool) -> void:
	var evento := InputEventKey.new()
	evento.physical_keycode = codigo
	evento.pressed = pulsada
	Input.parse_input_event(evento)


func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos, true, true).timeout


func _comprobar(v: bool, texto: String) -> void:
	if v:
		_ok += 1
	else:
		_fallos += 1
		push_error("H02: " + texto)
