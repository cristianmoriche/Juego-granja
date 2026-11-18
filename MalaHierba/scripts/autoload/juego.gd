extends Node
## Estado de la partida y reloj del juego. Autoload «Juego».
## Un día va de las 06:00 a las 02:00 (1.200 minutos de juego = 14 min reales).
## A las 02:00 (o con energía 0) Leo se desmaya: despierta en casa con la mitad de energía y pierde algo de dinero.

signal hora_cambiada(minutos: int)
signal dia_nuevo()
signal dinero_cambiado(dinero: int)
signal energia_cambiada(energia: float, maximo: float)
signal vida_cambiada(vida: float, maximo: float)
signal dano_recibido(cantidad: float)
signal resistencia_cambiada(actual: float, maximo: float)
signal equipo_cambiado()
signal inventario_cambiado()
signal ranura_cambiada(ranura: int)
signal mensaje(texto: String)
signal mensaje_objeto(texto: String, id_icono: String)
signal amistad_cambiada(npc: String, puntos: int)
signal partida_cambiada()
signal fin_de_anio()
signal estacion_cambiada()
signal clima_cambiado(nuevo: String)
signal evento_cambiado()
signal deuda_cambiada(deuda_restante: int)
signal horno_cambiado()
signal gemas_cambiadas()
signal pesca_cambiada()
signal ganado_cambiado()
signal logro_desbloqueado(datos: Dictionary)
signal logros_cambiados()

const MINUTO_REAL := 0.7        # segundos reales por minuto de juego
const HORA_INICIO := 360        # 06:00
const HORA_FIN := 1560          # 02:00 del día siguiente
const DIAS_ESTACION := 28
const HUECOS := 30
const PILA_MAX := 99
const DINERO_INICIAL := 500
const DEUDA_INICIAL := 5000
const ENERGIA_INICIAL := 100.0
const VIDA_INICIAL := 100.0
const PROB_LLUVIA := 0.2
const AMISTAD_MAX := 300
const AMISTAD_NIVEL_1 := 60
const AMISTAD_NIVEL_2 := 150
const AMISTAD_BUENA := 100      # media mínima con el pueblo para el final bueno
const AMISTAD_POR_CHARLA := 5
const RUTA_PARTIDA := "user://partida.json"
const Logros := preload("res://scripts/objetos/logros_h14.gd")
const MAX_RANURAS := 3
const NOMBRES_ESTACION: Array[String] = ["Primavera", "Verano", "Otoño", "Invierno"]
const NOMBRES_DIA_SEMANA: Array[String] = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
const DIA_FESTIVO_PRIMAVERA := 14
const DIA_FESTIVO_OTONO := 74   # 18 de otoño (56 + 18)

var ranura_guardado_activa: int = 1
var ruta_partida: String = "user://partida_1.json"
var tiempo_jugado_seg: float = 0.0
var nombre_jugador: String = "Leo"
var dinero: int = DINERO_INICIAL
var deuda: int = DEUDA_INICIAL
var energia: float = ENERGIA_INICIAL
var energia_max: float = ENERGIA_INICIAL
var vida: float = VIDA_INICIAL
var vida_max: float = VIDA_INICIAL
const RESISTENCIA_MAX := 100.0
const RANURAS_EQUIPO := ["escudo", "casco", "peto", "botas", "luz", "carcaj"]
var resistencia: float = RESISTENCIA_MAX
var equipo: Dictionary = {}
var _pausa_resistencia: float = 0.0
var _desmayo_pendiente: bool = false
var dia: int = 1
var estacion: int = 0:          # 0 primavera, 1 verano, 2 otoño, 3 invierno
	set(v):
		var cambio := v != estacion
		estacion = v
		actualizar_entorno_shader()
		if cambio and is_inside_tree():
			estacion_cambiada.emit()
var anio: int = 1
var minutos: int = HORA_INICIO
var clima: String = "sol"       # "sol" | "lluvia" | "tormenta"
var inventario: Array = []      # HUECOS entradas: {} o {"id": String, "cantidad": int[, "calidad": "baja"]}
var ranura: int = 0             # 0..9

var amistad: Dictionary = {}            # id de vecino -> puntos
var hablado_hoy: Dictionary = {}        # id de vecino -> true
var nivel_herramientas: Dictionary = {} # herramienta -> nivel (0 básica)
var estado_mapas: Dictionary = {}       # lo usan L4a/L4b: solo datos compatibles con JSON
var banderas: Dictionary = {}
var mapa_actual: String = "":
	set(v):
		mapa_actual = v
		actualizar_entorno_shader()
var estadisticas: Dictionary = {}       # cosechas, dias, dinero_ganado, dinero_gastado, ...

## Hay una partida en marcha (el reloj solo corre entonces).
var partida_activa: bool = false
## Posición [x, y, z] del jugador al guardar (la usa Escenas.continuar_partida y la borra después).
var posicion_guardada: Array = []

var _pausa_externa: bool = false
var _pausa_tiempo_debug: bool = false
var debug_vuelo: bool = false
var debug_inmortal: bool = false
var debug_energia_infinita: bool = false
var debug_hitboxes: bool = false
var _sin_foco: bool = false
var _minimizada: bool = false
var _pausa_por_ventana: bool = false
var _arbol_pausado_antes: bool = false
var _acumulado: float = 0.0
var _aviso_cansancio: bool = false


func _ready() -> void:
	# Recibe la recuperación del foco incluso con el árbol detenido.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().focus_exited.connect(_cambiar_foco.bind(false))
	get_window().focus_entered.connect(_cambiar_foco.bind(true))
	migrar_partida_legada()
	seleccionar_ranura_guardado(ranura_mas_reciente())
	_vaciar_inventario()
	actualizar_entorno_shader()
	partida_cambiada.connect(_al_cambiar_partida_h06)
	_conectar_misiones_h06.call_deferred()


func _conectar_misiones_h06() -> void:
	var m := get_node_or_null("/root/Misiones")
	if m != null and m.has_signal("actualizado") and not m.is_connected("actualizado", sincronizar_recetas):
		m.connect("actualizado", sincronizar_recetas)


func _notification(que: int) -> void:
	if not is_inside_tree():
		return
	if que == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cambiar_foco(false)
	elif que == NOTIFICATION_APPLICATION_FOCUS_IN:
		_cambiar_foco(true)


func _cambiar_foco(con_foco: bool) -> void:
	_sin_foco = not con_foco
	_actualizar_pausa_de_ventana()


func _actualizar_pausa_de_ventana() -> void:
	var pausar := _sin_foco or _minimizada
	if pausar and not _pausa_por_ventana:
		_arbol_pausado_antes = get_tree().paused
		get_tree().paused = true
	elif not pausar and _pausa_por_ventana:
		get_tree().paused = _arbol_pausado_antes
	_pausa_por_ventana = pausar


func _process(delta: float) -> void:
	# Windows puede minimizar sin emitir un cambio de foco: se comprueba también el modo.
	if DisplayServer.get_name() != "headless":
		var minimizada := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
		if minimizada != _minimizada:
			_minimizada = minimizada
			_actualizar_pausa_de_ventana()
	if not partida_activa or not tiempo_corre():
		return
	tiempo_jugado_seg += delta
	_acumulado += delta
	while _acumulado >= MINUTO_REAL and partida_activa:
		_acumulado -= MINUTO_REAL
		avanzar_minutos(1)


## El reloj corre cuando hay partida, un jugador en el mapa y ningún menú, diálogo o carga.
func tiempo_corre() -> bool:
	if not partida_activa or _pausa_externa or _pausa_tiempo_debug or _pausa_por_ventana or get_tree().paused:
		return false
	if Escenas.en_transicion or Escenas.jugador() == null:
		return false
	return not Interfaz.ocupada()


func pausar_tiempo(p: bool) -> void:
	_pausa_externa = p


func pausar_tiempo_debug(p: bool) -> void:
	_pausa_tiempo_debug = p


func tiempo_debug_pausado() -> bool:
	return _pausa_tiempo_debug


func limpiar_debug() -> void:
	debug_vuelo = false
	debug_inmortal = false
	debug_energia_infinita = false
	debug_hitboxes = false
	_pausa_tiempo_debug = false


func ajustar_dinero_debug(delta_euros: int) -> void:
	if delta_euros > 0:
		ingresar(delta_euros)
	elif delta_euros < 0:
		var nuevo := maxi(0, dinero + delta_euros)
		dinero = nuevo
		dinero_cambiado.emit(dinero)


# --- Partida nueva, tiempo y días ---------------------------------------------

func nueva_partida(nombre: String) -> void:
	nombre_jugador = nombre.strip_edges() if not nombre.strip_edges().is_empty() else "Leo"
	dinero = DINERO_INICIAL
	deuda = DEUDA_INICIAL
	energia_max = ENERGIA_INICIAL
	energia = energia_max
	vida_max = VIDA_INICIAL
	vida = vida_max
	resistencia = RESISTENCIA_MAX
	equipo = {}
	_pausa_resistencia = 0.0
	_desmayo_pendiente = false
	dia = 1
	estacion = 0
	anio = 1
	minutos = HORA_INICIO
	clima = "sol"
	ranura = 0
	amistad = {}
	hablado_hoy = {}
	nivel_herramientas = {}
	estado_mapas = {}
	banderas = {}
	_inicializar_eventos()
	mapa_actual = ""
	tiempo_jugado_seg = 0.0
	estadisticas = {"cosechas": 0, "dias": 0, "dinero_ganado": 0, "dinero_gastado": 0}
	_acumulado = 0.0
	_aviso_cansancio = false
	_vaciar_inventario()
	_poner("azada", 1)
	_poner("regadera", 1)
	_poner("hoz", 1)
	_poner("hacha", 1)
	_poner("pico", 1)
	_poner("semilla_patata", 15)
	_poner("bocadillo", 2)
	_poner("antorcha", 1)
	_asegurar_estado_h06(false)
	partida_activa = true
	actualizar_entorno_shader()
	_emitir_todo()
	partida_cambiada.emit()
	evento_cambiado.emit()
	logros_cambiados.emit()


func _emitir_todo() -> void:
	dinero_cambiado.emit(dinero)
	deuda_cambiada.emit(deuda)
	energia_cambiada.emit(energia, energia_max)
	vida_cambiada.emit(vida, vida_max)
	resistencia_cambiada.emit(resistencia, RESISTENCIA_MAX)
	equipo_cambiado.emit()
	inventario_cambiado.emit()
	ranura_cambiada.emit(ranura)
	hora_cambiada.emit(minutos)


func avanzar_minutos(n: int) -> void:
	for i in n:
		minutos += 1
		_avanzar_bufos(1)
		_avanzar_horno(1)
		hora_cambiada.emit(minutos)
		if minutos == 1440:
			mensaje.emit("Es medianoche. Convendría ir pensando en dormir.")
		elif minutos == 1500:
			mensaje.emit("Es la una de la madrugada. Estás agotado.")
		if minutos >= HORA_FIN:
			_solicitar_desmayo("Dan las dos de la madrugada y te rindes al sueño.", false, false)
			return


## Dormir: termina el día con la energía llena, pasa al día siguiente y guarda.
## Con un jugador en el mapa hace el fundido y despierta en casa (Escenas); sin jugador (pruebas) es inmediato.
func dormir() -> void:
	if Escenas.jugador() != null:
		Escenas.secuencia_dormir(false)
	else:
		terminar_dia(false)


func _solicitar_desmayo(motivo: String, por_heridas: bool = false, diferir: bool = true) -> void:
	if not partida_activa or _desmayo_pendiente:
		return
	_desmayo_pendiente = true
	if diferir:
		_desmayar.call_deferred(motivo, por_heridas)
	else:
		_desmayar(motivo, por_heridas)


func _desmayar(motivo: String, por_heridas: bool) -> void:
	if not partida_activa or not _desmayo_pendiente:
		return
	mensaje.emit(motivo)
	if Escenas.jugador() != null:
		Escenas.secuencia_dormir(true, por_heridas)
	else:
		terminar_dia(true)


## Cierra el día y abre el siguiente. Devuelve false si ha terminado el año (se emite fin_de_anio).
## Escenas puede aplazar el guardado hasta haber colocado a Leo donde despierta.
func terminar_dia(desmayo: bool = false, guardar_al_terminar: bool = true) -> bool:
	estadisticas["dias"] = int(estadisticas.get("dias", 0)) + 1
	var perdido := 0
	if desmayo:
		energia = energia_max * 0.5
		vida = vida_max * 0.75
		perdido = mini(dinero, clampi(dinero / 10, 10, 150))
		dinero -= perdido
	else:
		energia = energia_max
		vida = vida_max
	_limpiar_bufos()
	_avanzar_horno(480)
	_avanzar_ganado_dia()
	_fijar_resistencia(RESISTENCIA_MAX)
	_pausa_resistencia = 0.0
	_desmayo_pendiente = false
	vida_cambiada.emit(vida, vida_max)
	_aviso_cansancio = false
	if estacion == 3 and dia >= DIAS_ESTACION:
		banderas["fin_anio"] = true
		energia_cambiada.emit(energia, energia_max)
		dinero_cambiado.emit(dinero)
		guardar()
		fin_de_anio.emit()
		return false
	dia += 1
	if dia > DIAS_ESTACION:
		dia = 1
		estacion += 1
	minutos = HORA_INICIO
	_acumulado = 0.0
	hablado_hoy = {}
	_sortear_clima()
	_aplicar_evento_del_dia()
	energia_cambiada.emit(energia, energia_max)
	if perdido > 0:
		dinero_cambiado.emit(dinero)
		mensaje.emit("Te despiertas en casa con un dolor de cabeza. Te falta dinero: %s." % Estilo.euros(perdido))
	hora_cambiada.emit(minutos)
	dia_nuevo.emit()
	if guardar_al_terminar:
		guardar()
	return true


func _sortear_clima() -> void:
	var antes := clima
	# En invierno nieva visualmente; el resto del año llueve el 20 % de los días (y las tormentas llegan por evento).
	if estacion != 3 and randf() < PROB_LLUVIA:
		clima = "lluvia"
	else:
		clima = "sol"
	if clima != antes and is_inside_tree():
		clima_cambiado.emit(clima)


func esta_lloviendo() -> bool:
	return clima == "lluvia" or clima == "tormenta"


func esta_nevando() -> bool:
	return estacion == 3


## Bancos matinales en días despejados. El tiempo de cultivo sigue siendo el de un día de sol.
func intensidad_neblina(amanecer: float) -> float:
	if esta_lloviendo() or esta_nevando():
		return 0.0
	if clima == "niebla":
		return 0.92
	if (dia + estacion * 7 + anio * 3) % 4 != 3:
		return 0.0
	var desde_alba := float(minutos) - amanecer
	return 0.67 * smoothstep(-50.0, -4.0, desde_alba) * (1.0 - smoothstep(46.0, 183.0, desde_alba))


func nombre_clima() -> String:
	if clima == "tormenta":
		return "Tormenta"
	if clima == "lluvia":
		return "Lluvia"
	if estacion == 3:
		return "Nevando"
	var amanecer: float = CicloDia.AMANECER[clampi(estacion, 0, 3)]
	if intensidad_neblina(amanecer) > 0.38:
		return "Niebla"
	return "Soleado" if estacion == 1 else "Despejado"


func dia_anio() -> int:
	return clampi(estacion, 0, 3) * DIAS_ESTACION + clampi(dia, 1, DIAS_ESTACION)


func actualizar_entorno_shader() -> void:
	var interior := mapa_actual == "casa" or mapa_actual == "mina" or mapa_actual.begins_with("interior")
	var es_ext := not interior
	RenderingServer.global_shader_parameter_set("nieve_estacion", 1.0 if es_ext and estacion == 3 else 0.0)
	RenderingServer.global_shader_parameter_set("calidez_otono", 1.0 if es_ext and estacion == 2 else 0.0)


func _inicializar_eventos() -> void:
	var prog: Dictionary = {}
	var cult_prim := ["patata", "zanahoria", "haba"]
	var cult_ver := ["tomate", "pimiento", "melon"]
	var cult_oto := ["calabaza", "col", "boniato"]
	var cult_inv := ["ajo", "espinaca", "nabo", "azafran"]

	var plan: Array[Array] = [
		# Primavera (1..28): tormenta, mercado, comerciante (evitando día 14 de la Feria de la Siembra)
		[randi_range(6, 9), "tormenta", "", "Tormenta de primavera: ha regado los cultivos, pero el viento ha roto tramos de la cerca."],
		[randi_range(16, 19), "mercado", cult_prim[randi() % cult_prim.size()], ""],
		[randi_range(22, 25), "comerciante", "", "Visita en el pueblo: un mercader ambulante ofrece artículos raros en la plaza."],
		# Verano (29..56): plaga, tormenta, mercado
		[28 + randi_range(6, 9), "plaga", "", ""],
		[28 + randi_range(14, 17), "tormenta", "", "Tormenta de verano: descarga con fuerza sobre la finca y daña algunas cercas."],
		[28 + randi_range(22, 25), "mercado", cult_ver[randi() % cult_ver.size()], ""],
		# Otoño (57..84): comerciante, plaga, mercado (evitando día 74 = 18 de otoño, Fiesta de la Cosecha)
		[56 + randi_range(5, 8), "comerciante", "", "Visita de otoño: vuelve el mercader ambulante con bulbos raros y reliquias del valle."],
		[56 + randi_range(12, 15), "plaga", "", ""],
		[56 + randi_range(21, 24), "mercado", cult_oto[randi() % cult_oto.size()], ""],
		# Invierno (85..112): tormenta, comerciante, mercado
		[84 + randi_range(6, 9), "tormenta", "", "Temporal de invierno: las ráfagas azotan la granja y han derribado parte de las cercas."],
		[84 + randi_range(14, 17), "comerciante", "", "Visita invernal: el mercader ambulante desafía el frío en la plaza con reservas raras."],
		[84 + randi_range(21, 24), "mercado", cult_inv[randi() % cult_inv.size()], ""],
	]
	for item: Array in plan:
		var ev_dict: Dictionary = {"tipo": str(item[1])}
		if not str(item[2]).is_empty():
			ev_dict["cultivo"] = str(item[2])
		if not str(item[3]).is_empty():
			ev_dict["aviso"] = str(item[3])
		prog[str(int(item[0]))] = ev_dict

	_poner_festividades_fijas(prog)

	banderas["eventos"] = {
		"programados": prog,
		"cercas_rotas": [],
		"mercado_cultivo": "",
		"plaga_cultivo": "",
		"aviso_hoy": "",
	}


func _poner_festividades_fijas(prog: Dictionary) -> void:
	prog[str(DIA_FESTIVO_PRIMAVERA)] = {
		"tipo": "festividad",
		"id": "feria_siembra",
		"nombre": "Feria de la Siembra",
		"aviso": "¡Hoy es la Feria de la Siembra! Todo el pueblo se reúne en la plaza.",
	}
	prog[str(DIA_FESTIVO_OTONO)] = {
		"tipo": "festividad",
		"id": "fiesta_cosecha",
		"nombre": "Fiesta de la Cosecha",
		"aviso": "¡Hoy es la Fiesta de la Cosecha! Hay puestos, calabazas y fiesta en la plaza.",
	}


func _asegurar_eventos() -> Dictionary:
	var ev: Variant = banderas.get("eventos", {})
	if not (ev is Dictionary) or not (ev as Dictionary).has("programados") or ((ev as Dictionary)["programados"] as Dictionary).is_empty():
		_inicializar_eventos()
		ev = banderas["eventos"]
	var ev_d := ev as Dictionary
	var prog: Dictionary = ev_d["programados"]
	if str((prog.get(str(DIA_FESTIVO_PRIMAVERA), {}) as Dictionary).get("tipo", "")) != "festividad" \
			or str((prog.get(str(DIA_FESTIVO_OTONO), {}) as Dictionary).get("tipo", "")) != "festividad":
		_poner_festividades_fijas(prog)
	return ev_d


func eventos_anio() -> Dictionary:
	return _asegurar_eventos().get("programados", {})


func evento_en_dia(d_anio: int) -> Dictionary:
	var prog := eventos_anio()
	var c := str(d_anio)
	return prog[c] if prog.has(c) and prog[c] is Dictionary else {}


func evento_hoy() -> Dictionary:
	return evento_en_dia(dia_anio())


func aplicar_evento_hoy() -> void:
	_aplicar_evento_del_dia()


func _aplicar_evento_del_dia() -> void:
	var ev := _asegurar_eventos()
	ev["mercado_cultivo"] = ""
	ev["aviso_hoy"] = ""
	ev["plaga_cultivo"] = ""
	var dato := evento_hoy()
	if not dato.is_empty():
		var tipo := str(dato.get("tipo", ""))
		match tipo:
			"festividad":
				var antes_f := clima
				clima = "sol"
				if clima != antes_f and is_inside_tree():
					clima_cambiado.emit(clima)
				ev["aviso_hoy"] = str(dato.get("aviso", "¡Hoy hay fiesta en Villaverde de los Rosales!"))
			"tormenta":
				var antes := clima
				clima = "tormenta"
				if clima != antes and is_inside_tree():
					clima_cambiado.emit(clima)
				_romper_cercas(ev)
				ev["aviso_hoy"] = str(dato.get("aviso", "Tormenta en el valle: no hace falta regar, pero hay cercas rotas."))
			"plaga":
				ev["aviso_hoy"] = "Plaga en los cultivos: revisa la huerta y usa remedio antipulgas o perderán calidad."
			"mercado":
				var cult := str(dato.get("cultivo", "patata"))
				ev["mercado_cultivo"] = cult
				ev["aviso_hoy"] = "Mercado especial: hoy las tiendas pagan el doble por %s." % Datos.nombre_objeto(cult).to_lower()
			"comerciante":
				ev["aviso_hoy"] = str(dato.get("aviso", "Mercader ambulante: hoy tiene puesto en la plaza del pueblo con objetos raros."))
	if not str(ev.get("aviso_hoy", "")).is_empty():
		mensaje.emit(str(ev["aviso_hoy"]))
	if is_inside_tree():
		evento_cambiado.emit()


func _romper_cercas(ev: Dictionary) -> void:
	var rotas: Array = ev.get("cercas_rotas", []) if ev.get("cercas_rotas", []) is Array else []
	for idx: int in [1, 4, 8, 12]:
		if not rotas.has(idx):
			rotas.append(idx)
	ev["cercas_rotas"] = rotas


func cercas_rotas() -> Array:
	var ev := _asegurar_eventos()
	return ev.get("cercas_rotas", []) if ev.get("cercas_rotas", []) is Array else []


func hay_cercas_rotas() -> bool:
	return not cercas_rotas().is_empty()


func reparar_cercas(gratis: bool = false) -> bool:
	if not hay_cercas_rotas():
		return false
	if not gratis:
		if cantidad("madera") < 2:
			mensaje.emit("Necesitas 2 de madera para reparar los tramos rotos de la cerca.")
			return false
		quitar_objeto("madera", 2)
	var ev := _asegurar_eventos()
	ev["cercas_rotas"] = []
	mensaje.emit("Has reparado todas las cercas de la granja.")
	if is_inside_tree():
		evento_cambiado.emit()
	return true


func cultivo_mercado_especial() -> String:
	return str(_asegurar_eventos().get("mercado_cultivo", ""))


func hay_comerciante() -> bool:
	return str(evento_hoy().get("tipo", "")) == "comerciante"


func festividad_hoy() -> String:
	var ev := evento_hoy()
	if str(ev.get("tipo", "")) != "festividad":
		return ""
	return str(ev.get("id", ""))


func nombre_festividad_hoy() -> String:
	var ev := evento_hoy()
	if str(ev.get("tipo", "")) != "festividad":
		return ""
	return str(ev.get("nombre", "Fiesta del pueblo"))


func dia_semana() -> int:
	return posmod(dia_anio() - 1, 7)


func nombre_dia_semana() -> String:
	return NOMBRES_DIA_SEMANA[dia_semana()]


func deuda_pagada() -> int:
	return maxi(0, DEUDA_INICIAL - deuda)


func tramo_deuda() -> int:
	var pagada := deuda_pagada()
	if deuda <= 0 or pagada >= DEUDA_INICIAL:
		return 3
	if pagada >= 3000:
		return 2
	if pagada >= 1500:
		return 1
	return 0


func pagar_deuda(n: int) -> int:
	if n <= 0 or deuda <= 0 or dinero <= 0:
		return 0
	var abono := mini(n, mini(dinero, deuda))
	if abono <= 0 or not cobrar(abono):
		return 0
	deuda -= abono
	banderas["deuda_pagada"] = deuda_pagada()
	if is_inside_tree():
		deuda_cambiada.emit(deuda)
	evaluar_logros()
	if deuda <= 0:
		mensaje.emit("¡Has saldado por completo la deuda de El Granado! Villaverde está a salvo.")
	else:
		mensaje.emit("Has abonado %s de la deuda. Quedan %s." % [Estilo.euros(abono), Estilo.euros(deuda)])
	return abono


func aviso_evento_hoy() -> String:
	return str(_asegurar_eventos().get("aviso_hoy", ""))


func registrar_plaga_cultivo(id_cultivo: String) -> void:
	var ev := _asegurar_eventos()
	ev["plaga_cultivo"] = id_cultivo
	var texto := "Plaga de %s: usa remedio antipulgas hoy o perderá calidad." % Datos.nombre_objeto(id_cultivo).to_lower()
	ev["aviso_hoy"] = texto
	mensaje.emit(texto)
	if is_inside_tree():
		evento_cambiado.emit()


func precio_venta_item(id: String, calidad: String = "") -> int:
	var base := int(Datos.objeto(id).get("precio_venta", 0))
	if base <= 0:
		return 0
	if calidad == "baja":
		base = maxi(1, int(round(float(base) * 0.5)))
	if not id.is_empty() and cultivo_mercado_especial() == id:
		base *= 2
	return base


func texto_hora() -> String:
	var m := minutos % 1440
	return "%02d:%02d" % [m / 60, m % 60]


func texto_fecha() -> String:
	return "%s, día %d" % [NOMBRES_ESTACION[clampi(estacion, 0, 3)], dia]


func nombre_estacion() -> String:
	return NOMBRES_ESTACION[clampi(estacion, 0, 3)]


## Días que quedan hasta el final del año (contando hoy).
func dias_restantes() -> int:
	return (3 - estacion) * DIAS_ESTACION + (DIAS_ESTACION - dia) + 1


# --- Energía y dinero -------------------------------------------------------------

func gastar_energia(n: float) -> bool:
	if n <= 0.0:
		return true
	if debug_energia_infinita:
		if energia < energia_max:
			energia = energia_max
			energia_cambiada.emit(energia, energia_max)
		return true
	if energia + 0.001 < n:
		mensaje.emit("Estás demasiado cansado.")
		return false
	energia = maxf(energia - n, 0.0)
	energia_cambiada.emit(energia, energia_max)
	if energia <= 0.01:
		_solicitar_desmayo("Te quedas sin fuerzas y te desplomas.")
	elif energia <= 12.0 and not _aviso_cansancio:
		_aviso_cansancio = true
		mensaje.emit("Te estás quedando sin fuerzas. Come algo o vete a dormir.")
	return true


func recuperar_energia(n: float) -> void:
	energia = minf(energia + n, energia_max)
	if energia > 12.0:
		_aviso_cansancio = false
	energia_cambiada.emit(energia, energia_max)


func recibir_dano(n: float) -> void:
	if debug_inmortal or n <= 0.0 or not partida_activa or _desmayo_pendiente:
		return
	var anterior := vida
	vida = maxf(vida - n, 0.0)
	vida_cambiada.emit(vida, vida_max)
	dano_recibido.emit(anterior - vida)
	if vida <= 0.01:
		_solicitar_desmayo("Los golpes te hacen perder el conocimiento.", true)


func curar_vida(n: float) -> void:
	if n <= 0.0 or _desmayo_pendiente:
		return
	vida = minf(vida + n, vida_max)
	vida_cambiada.emit(vida, vida_max)


func _fijar_resistencia(n: float) -> void:
	var v := clampf(n, 0.0, RESISTENCIA_MAX)
	if not is_equal_approx(resistencia, v):
		resistencia = v
		resistencia_cambiada.emit(resistencia, RESISTENCIA_MAX)


func gastar_resistencia(n: float) -> bool:
	if n <= 0.0 or debug_energia_infinita:
		return true
	var ahorro := clampf(bono_ahorro_resistencia(), 0.0, 0.60)
	var coste := n * (1.0 - ahorro)
	if resistencia + 0.001 < coste or _desmayo_pendiente:
		return false
	_fijar_resistencia(resistencia - coste)
	_pausa_resistencia = 0.75
	return true


func agotar_resistencia() -> void:
	_fijar_resistencia(0.0)
	_pausa_resistencia = 1.15


func recuperar_resistencia(delta: float) -> void:
	_pausa_resistencia = maxf(0.0, _pausa_resistencia - delta)
	if _pausa_resistencia <= 0.0 and not _desmayo_pendiente:
		_fijar_resistencia(resistencia + 22.0 * delta)


func cobrar(n: int) -> bool:
	if n < 0 or dinero < n:
		return false
	dinero -= n
	estadisticas["dinero_gastado"] = int(estadisticas.get("dinero_gastado", 0)) + n
	dinero_cambiado.emit(dinero)
	return true


func ingresar(n: int) -> void:
	if n <= 0:
		return
	dinero += n
	estadisticas["dinero_ganado"] = int(estadisticas.get("dinero_ganado", 0)) + n
	dinero_cambiado.emit(dinero)
	evaluar_logros()


# --- Inventario -------------------------------------------------------------------

func _vaciar_inventario() -> void:
	inventario = []
	for i in HUECOS:
		inventario.append({})


func _poner(id: String, n: int, calidad: String = "") -> int:
	if n <= 0 or not Datos.existe_objeto(id):
		return n
	var cal := "baja" if calidad == "baja" else ""
	var falta := n
	# Primero completa las pilas que ya hay con la misma calidad (y sin gemas ni temple propios).
	for i in HUECOS:
		var h: Dictionary = inventario[i]
		if falta > 0 and not h.is_empty() and h["id"] == id and str(h.get("calidad", "")) == cal and not _tiene_meta_propia(h) and int(h["cantidad"]) < PILA_MAX:
			var cabe := PILA_MAX - int(h["cantidad"])
			var mete := mini(cabe, falta)
			h["cantidad"] = int(h["cantidad"]) + mete
			falta -= mete
	# Después, los huecos vacíos.
	for i in HUECOS:
		if falta <= 0:
			break
		if (inventario[i] as Dictionary).is_empty():
			var mete := mini(PILA_MAX, falta)
			var nuevo: Dictionary = {"id": id, "cantidad": mete}
			if cal == "baja":
				nuevo["calidad"] = "baja"
			inventario[i] = nuevo
			falta -= mete
	return falta


## Añade objetos al inventario; devuelve cuántos no cupieron.
func anadir_objeto(id: String, n: int = 1, calidad: String = "") -> int:
	if not Datos.existe_objeto(id):
		push_warning("Juego.anadir_objeto: objeto desconocido «%s»" % id)
		return n
	var sobra := _poner(id, n, calidad)
	inventario_cambiado.emit()
	if n - sobra > 0:
		var suf := " (calidad baja)" if calidad == "baja" else ""
		mensaje_objeto.emit("+%d %s%s" % [n - sobra, Datos.nombre_objeto(id), suf], Datos.id_icono(id, nivel(id)))
		if partida_activa:
			evaluar_logros()
	if sobra > 0:
		mensaje.emit("El inventario está lleno: no caben %d %s." % [sobra, Datos.nombre_objeto(id)])
	return sobra


func quitar_objeto(id: String, n: int = 1, calidad: String = "*") -> bool:
	if n <= 0:
		return true
	if cantidad(id, calidad) < n:
		return false
	_quitar_del_inventario(id, n, calidad)
	inventario_cambiado.emit()
	return true


func _quitar_del_inventario(id: String, n: int, calidad: String = "*") -> void:
	var falta := n
	for i in range(HUECOS - 1, -1, -1):
		var h: Dictionary = inventario[i]
		if falta <= 0:
			break
		if not h.is_empty() and h["id"] == id and (calidad == "*" or str(h.get("calidad", "")) == calidad):
			var quita := mini(int(h["cantidad"]), falta)
			h["cantidad"] = int(h["cantidad"]) - quita
			falta -= quita
			if int(h["cantidad"]) <= 0:
				inventario[i] = {}


## Fabrica una pieza. Cierra la transacción antes de avisar a la interfaz.
func forjar_equipo(id: String) -> bool:
	var receta := Datos.objeto(id).get("forja", {}) as Dictionary
	if receta.is_empty():
		return false
	var material := str(receta["material"])
	var unidades := int(receta["cantidad"])
	var precio := int(receta["dinero"])
	var entrega := maxi(1, int(receta.get("entrega", 1)))
	if cantidad(material) < unidades or dinero < precio:
		return false
	var anterior := inventario.duplicate(true)
	_quitar_del_inventario(material, unidades)
	if _poner(id, entrega) != 0:
		inventario = anterior
		mensaje.emit("El inventario está lleno. Haz sitio para la pieza forjada.")
		return false
	cobrar(precio)
	inventario_cambiado.emit()
	mensaje_objeto.emit("+%d %s" % [entrega, Datos.nombre_objeto(id)], id)
	return true


func municion_disponible() -> String:
	var activo := objeto_activo()
	var id_act := str(activo.get("id", ""))
	if str(Datos.objeto(id_act).get("tipo", "")) == "municion":
		return id_act
	for pass_hotbar in [true, false]:
		var inicio := 0 if pass_hotbar else 10
		var fin := 10 if pass_hotbar else HUECOS
		for i in range(inicio, fin):
			var h: Dictionary = inventario[i]
			if h.is_empty():
				continue
			var oid := str(h.get("id", ""))
			if str(Datos.objeto(oid).get("tipo", "")) == "municion":
				return oid
	return ""


func total_flechas() -> int:
	var n := 0
	for h: Dictionary in inventario:
		if not h.is_empty() and str(Datos.objeto(str(h.get("id", ""))).get("tipo", "")) == "municion":
			n += int(h.get("cantidad", 0))
	return n


func equipar(indice: int) -> bool:
	if not partida_activa or indice < 0 or indice >= inventario.size():
		return false
	var h: Dictionary = inventario[indice]
	var id := str(h.get("id", ""))
	var sitio := str(Datos.objeto(id).get("ranura_equipo", ""))
	if not sitio in RANURAS_EQUIPO:
		return false
	var meta_eq := _h10_equipo_meta()
	var prev_meta: Dictionary = (meta_eq.get(sitio, {}) as Dictionary).duplicate(true)
	var nuevo_meta := {"gemas": _lista_gemas(h), "temple": int(h.get("temple", 0))}
	var previo := str(equipo.get(sitio, ""))
	if previo == id and nuevo_meta == prev_meta:
		return false
	if int(h["cantidad"]) == 1:
		if previo.is_empty():
			inventario[indice] = {}
		else:
			inventario[indice] = _aplicar_meta_hueco({"id": previo, "cantidad": 1}, prev_meta)
	else:
		if not previo.is_empty():
			var devuelto := _poner(previo, 1)
			if devuelto != 0:
				mensaje.emit("Haz sitio en el inventario para la pieza que llevabas.")
				return false
			if not (prev_meta.get("gemas", []) as Array).is_empty() or int(prev_meta.get("temple", 0)) > 0:
				for j in HUECOS:
					var cand: Dictionary = inventario[j]
					if not cand.is_empty() and cand["id"] == previo and not _tiene_meta_propia(cand):
						_aplicar_meta_hueco(cand, prev_meta)
						break
		h["cantidad"] = int(h["cantidad"]) - 1
	equipo[sitio] = id
	if (nuevo_meta["gemas"] as Array).is_empty() and int(nuevo_meta["temple"]) <= 0:
		meta_eq.erase(sitio)
	else:
		meta_eq[sitio] = nuevo_meta
	inventario_cambiado.emit()
	equipo_cambiado.emit()
	gemas_cambiadas.emit()
	mensaje.emit("Equipas %s." % Datos.nombre_objeto(id))
	return true


func desequipar(sitio: String) -> bool:
	var id := str(equipo.get(sitio, ""))
	if id.is_empty():
		return false
	var meta_eq := _h10_equipo_meta()
	var meta_p: Dictionary = (meta_eq.get(sitio, {}) as Dictionary).duplicate(true)
	var tiene_meta := not (meta_p.get("gemas", []) as Array).is_empty() or int(meta_p.get("temple", 0)) > 0
	if tiene_meta:
		var hueco := -1
		for i in HUECOS:
			if (inventario[i] as Dictionary).is_empty():
				hueco = i
				break
		if hueco < 0:
			mensaje.emit("Haz sitio en el inventario para quitarte la pieza.")
			return false
		inventario[hueco] = _aplicar_meta_hueco({"id": id, "cantidad": 1}, meta_p)
	else:
		if _poner(id, 1) != 0:
			mensaje.emit("Haz sitio en el inventario para quitarte la pieza.")
			return false
	equipo.erase(sitio)
	meta_eq.erase(sitio)
	inventario_cambiado.emit()
	equipo_cambiado.emit()
	gemas_cambiadas.emit()
	return true


func defensa_equipo() -> float:
	var defensa := 0.0
	var meta_eq := _h10_equipo_meta()
	for sitio: String in ["casco", "peto", "botas"]:
		var id := str(equipo.get(sitio, ""))
		if id.is_empty():
			continue
		var m := meta_eq.get(sitio, {}) as Dictionary
		var st := Herreria.stats_pieza(id, _lista_gemas(m), int(m.get("temple", 0)))
		defensa += float(st.get("defensa", 0.0))
	return defensa


func quitar_de_hueco(indice: int, n: int = 1) -> bool:
	if n <= 0 or indice < 0 or indice >= HUECOS:
		return false
	var h: Dictionary = inventario[indice]
	if h.is_empty() or int(h.get("cantidad", 0)) < n:
		return false
	h["cantidad"] = int(h["cantidad"]) - n
	if int(h["cantidad"]) <= 0:
		inventario[indice] = {}
	inventario_cambiado.emit()
	return true


func cantidad(id: String, calidad: String = "*") -> int:
	var total := 0
	for h: Dictionary in inventario:
		if not h.is_empty() and h["id"] == id and (calidad == "*" or str(h.get("calidad", "")) == calidad):
			total += int(h["cantidad"])
	return total


## Cuántas unidades de un objeto caben aún en el inventario.
func espacio_para(id: String, calidad: String = "") -> int:
	var cal := "baja" if calidad == "baja" else ""
	var libre := 0
	for h: Dictionary in inventario:
		if h.is_empty():
			libre += PILA_MAX
		elif h["id"] == id and str(h.get("calidad", "")) == cal:
			libre += PILA_MAX - int(h["cantidad"])
	return libre


func objeto_activo() -> Dictionary:
	if ranura < 0 or ranura >= inventario.size():
		return {}
	return inventario[ranura]


func elegir_ranura(r: int) -> void:
	var nueva := posmod(r, 10)
	if nueva != ranura:
		ranura = nueva
		ranura_cambiada.emit(ranura)


## Mueve o intercambia dos huecos; si llevan el mismo objeto y calidad, junta las pilas.
func mover_huecos(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= HUECOS or b >= HUECOS:
		return
	var ha: Dictionary = inventario[a]
	var hb: Dictionary = inventario[b]
	if not ha.is_empty() and not hb.is_empty() and ha["id"] == hb["id"] and str(ha.get("calidad", "")) == str(hb.get("calidad", "")):
		var cabe := PILA_MAX - int(hb["cantidad"])
		var pasa := mini(cabe, int(ha["cantidad"]))
		hb["cantidad"] = int(hb["cantidad"]) + pasa
		ha["cantidad"] = int(ha["cantidad"]) - pasa
		if int(ha["cantidad"]) <= 0:
			inventario[a] = {}
	else:
		inventario[a] = hb
		inventario[b] = ha
	inventario_cambiado.emit()


## Se come un objeto del inventario: recupera energía, salud, resistencia y aplica mejoras temporales.
func comer(id: String) -> bool:
	var o := Datos.objeto(id)
	if o.is_empty() or o.get("tipo", "") != "comida" or _desmayo_pendiente:
		return false
	var rec := Datos.receta(id)
	var e: float = float(rec.get("energia", o.get("energia", 0)))
	var v: float = float(rec.get("vida", e * 0.5))
	var res: float = float(rec.get("resistencia", 0.0))
	var bufo: Dictionary = rec.get("bufo", {}) if rec.get("bufo", {}) is Dictionary else {}
	var necesita_algo := energia < energia_max - 0.01 or vida < vida_max - 0.01 or (res > 0.0 and resistencia < RESISTENCIA_MAX - 0.01) or not bufo.is_empty()
	if not necesita_algo:
		mensaje.emit("No tienes hambre ahora mismo.")
		return false
	if not quitar_objeto(id, 1):
		return false
	if e > 0.0:
		recuperar_energia(e)
	var salud_antes := vida
	if v > 0.0:
		curar_vida(v)
	if res > 0.0:
		_fijar_resistencia(resistencia + res)
	if not bufo.is_empty():
		_aplicar_bufo(bufo, Datos.nombre_objeto(id))
	var partes: Array[String] = []
	if e > 0.0:
		partes.append("+%d energía" % int(e))
	var curada := roundi(vida - salud_antes)
	if curada > 0:
		partes.append("+%d salud" % curada)
	if res > 0.0:
		partes.append("+%d resistencia" % int(res))
	if not bufo.is_empty():
		partes.append(str(bufo.get("etiqueta", "bufo activo")))
	var detalle := " (%s)" % ", ".join(partes) if not partes.is_empty() else ""
	mensaje_objeto.emit("%s%s" % [Datos.nombre_objeto(id), detalle], id)
	return true


# --- Vecinos y herramientas -----------------------------------------------------------

func subir_amistad(npc: String, n: int) -> void:
	var antes := int(amistad.get(npc, 0))
	amistad[npc] = clampi(antes + n, 0, AMISTAD_MAX)
	if nivel_amistad(npc) > _nivel_de(antes):
		mensaje.emit("%s te tiene más confianza." % str(Datos.npc(npc).get("nombre", npc)))
	if n != 0:
		amistad_cambiada.emit(npc, n)
		evaluar_logros()
	sincronizar_recetas(true)


func puntos_amistad(npc: String) -> int:
	return int(amistad.get(npc, 0))


func _nivel_de(puntos: int) -> int:
	if puntos >= AMISTAD_NIVEL_2:
		return 2
	if puntos >= AMISTAD_NIVEL_1:
		return 1
	return 0


## Nivel de amistad con un vecino: 0 (conocido), 1 (amigo) o 2 (de confianza).
func nivel_amistad(npc: String) -> int:
	return _nivel_de(puntos_amistad(npc))


func amistad_media() -> float:
	var ids := Datos.ids_npc()
	if ids.is_empty():
		return 0.0
	var suma := 0
	for id in ids:
		suma += puntos_amistad(id)
	return float(suma) / float(ids.size())


func nivel(herramienta: String) -> int:
	return int(nivel_herramientas.get(herramienta, 0))


# --- Final del año ------------------------------------------------------------------

## «malo» si el dinero no cubre la deuda; «regular» si la salda pero el pueblo no te conoce bien; «bueno» si además
## la amistad media con los vecinos es alta.
func final_logrado() -> String:
	if dinero < deuda:
		return "malo"
	if amistad_media() >= AMISTAD_BUENA:
		return "bueno"
	return "regular"


func resumen_final() -> Dictionary:
	return {
		"final": final_logrado(),
		"dinero": dinero,
		"deuda": deuda,
		"saldo": dinero - deuda,
		"amistad": amistad_media(),
		"cosechas": int(estadisticas.get("cosechas", 0)),
		"dias": int(estadisticas.get("dias", 0)),
	}


# --- Guardado -------------------------------------------------------------------------
# Formato: JSON con «version». Se escribe primero en `<ruta>.tmp`, se comprueba releyéndolo y solo entonces sustituye a
# la partida; la partida anterior (si era válida) queda en `<ruta>.bak` como copia de seguridad. Si el juego se cierra a
# medias, siempre queda en disco una partida entera: la nueva, la anterior o las dos.

## Versión 3: añade el equipo que lleva puesto Leo.
const VERSION_GUARDADO := 3
const SUFIJO_TEMPORAL := ".tmp"
const SUFIJO_COPIA := ".bak"
const SUFIJO_DANADA := ".danada"

signal partida_guardada()
signal habilidad_subida(id: String, nivel_nuevo: int, ventaja: String)
signal habilidades_cambiadas()
signal recetas_cambiadas()
signal bufos_cambiados()

const NIVEL_HABILIDAD_MAX := 10
const HABILIDADES_ORDEN := ["agricultura", "mineria", "combate", "pesca", "recoleccion"]
const HABILIDADES_NOMBRES := {
	"agricultura": "Agricultura",
	"mineria": "Minería",
	"combate": "Combate",
	"pesca": "Pesca",
	"recoleccion": "Recolección",
}
const HABILIDADES_VENTAJAS := {
	"agricultura": "-3,2 % energía al cultivar y +5 % cosecha doble/nv",
	"mineria": "-3,2 % energía al picar y +4 % mineral extra/nv",
	"combate": "+5 salud máxima y +4 % daño cuerpo a cuerpo/nv",
	"pesca": "-3,2 % energía al pescar y +4 % captura extra o rara/nv",
	"recoleccion": "+5 % botín silvestre/madera extra y +2 % agilidad/nv",
}
const BUFOS_NOMBRES := {
	"dano": "Fuerza",
	"defensa": "Templanza",
	"suerte_minera": "Ojo minero",
	"velocidad": "Ligereza",
}


func _al_cambiar_partida_h06() -> void:
	_asegurar_estado_h06(false)
	habilidades_cambiadas.emit()
	recetas_cambiadas.emit()
	bufos_cambiados.emit()


func _asegurar_estado_h06(notificar_nuevas: bool = false) -> void:
	var habs_raw: Variant = banderas.get("habilidades", null)
	if not (habs_raw is Dictionary):
		habs_raw = {}
		banderas["habilidades"] = habs_raw
	var habs := habs_raw as Dictionary
	for id: String in HABILIDADES_ORDEN:
		var reg: Variant = habs.get(id, null)
		if not (reg is Dictionary):
			habs[id] = {"nivel": 1, "xp": 0}
		else:
			var d := reg as Dictionary
			d["nivel"] = clampi(int(d.get("nivel", 1)), 1, NIVEL_HABILIDAD_MAX)
			d["xp"] = maxi(0, int(d.get("xp", 0)))
	if not (banderas.get("recetas", null) is Array):
		banderas["recetas"] = []
	if not (banderas.get("bufos", null) is Dictionary):
		banderas["bufos"] = {}
	_recalcular_atributos_h06(false)
	sincronizar_recetas(notificar_nuevas)


func habilidades_estado() -> Dictionary:
	var habs_raw: Variant = banderas.get("habilidades", null)
	if not (habs_raw is Dictionary):
		_asegurar_estado_h06(false)
		habs_raw = banderas["habilidades"]
	return habs_raw as Dictionary


func nivel_habilidad(id: String) -> int:
	var est := habilidades_estado()
	var reg: Dictionary = est.get(id, {}) as Dictionary
	return clampi(int(reg.get("nivel", 1)), 1, NIVEL_HABILIDAD_MAX)


func xp_habilidad(id: String) -> int:
	var est := habilidades_estado()
	var reg: Dictionary = est.get(id, {}) as Dictionary
	return maxi(0, int(reg.get("xp", 0)))


func xp_siguiente_nivel(nv: int) -> int:
	if nv >= NIVEL_HABILIDAD_MAX:
		return 0
	return 35 + maxi(0, nv - 1) * 30


func ganar_xp_habilidad(id: String, xp: int) -> bool:
	if xp <= 0 or not HABILIDADES_NOMBRES.has(id):
		return false
	var est := habilidades_estado()
	var reg: Dictionary = est[id] as Dictionary
	var nv := clampi(int(reg.get("nivel", 1)), 1, NIVEL_HABILIDAD_MAX)
	if nv >= NIVEL_HABILIDAD_MAX:
		return false
	var xp_tot := int(reg.get("xp", 0)) + xp
	var subio := false
	while nv < NIVEL_HABILIDAD_MAX:
		var req := xp_siguiente_nivel(nv)
		if req <= 0 or xp_tot < req:
			break
		xp_tot -= req
		nv += 1
		subio = true
	if nv >= NIVEL_HABILIDAD_MAX:
		xp_tot = 0
	reg["nivel"] = nv
	reg["xp"] = xp_tot
	if subio:
		_recalcular_atributos_h06(true)
		var nom := str(HABILIDADES_NOMBRES.get(id, id))
		var ventaja := str(HABILIDADES_VENTAJAS.get(id, ""))
		mensaje.emit("¡Habilidad %s sube a nivel %d! (%s)" % [nom, nv, ventaja])
		habilidad_subida.emit(id, nv, ventaja)
	habilidades_cambiadas.emit()
	if subio:
		evaluar_logros()
	return subio


func _recalcular_atributos_h06(curar_diferencia: bool) -> void:
	var habs: Dictionary = banderas.get("habilidades", {}) as Dictionary
	var comb: Dictionary = habs.get("combate", {}) as Dictionary
	var nv_comb := clampi(int(comb.get("nivel", 1)), 1, NIVEL_HABILIDAD_MAX)
	var nueva_max := VIDA_INICIAL + float(nv_comb - 1) * 5.0
	if not is_equal_approx(vida_max, nueva_max):
		var delta_v := nueva_max - vida_max
		vida_max = nueva_max
		if curar_diferencia and delta_v > 0.0:
			vida = minf(vida + delta_v, vida_max)
		else:
			vida = minf(vida, vida_max)
		if is_inside_tree():
			vida_cambiada.emit(vida, vida_max)


func factor_energia_habilidad(id: String) -> float:
	return clampf(1.0 - float(nivel_habilidad(id) - 1) * 0.032, 0.70, 1.0)


func bono_suerte_cosecha() -> float:
	return float(nivel_habilidad("agricultura") - 1) * 0.05


func bono_suerte_minera() -> float:
	var gem_suerte := 0.0
	for p: Dictionary in _piezas_activas():
		gem_suerte += float(Herreria.stats_pieza(str(p["id"]), p["gemas"] as Array, int(p["temple"])).get("suerte_minera", 0.0))
	return float(nivel_habilidad("mineria") - 1) * 0.04 + valor_bufo("suerte_minera") + gem_suerte


func bono_dano_combate() -> float:
	var b := float(nivel_habilidad("combate") - 1) * 0.04 + valor_bufo("dano")
	var act := objeto_activo()
	if not act.is_empty():
		var st := Herreria.stats_pieza(str(act.get("id", "")), _lista_gemas(act), int(act.get("temple", 0)))
		b += float(st.get("bono_dano", 0.0)) + 0.10 * float(int(st.get("temple", 0)))
	return b


func bono_defensa_total() -> float:
	return defensa_equipo() + valor_bufo("defensa")


func bono_ahorro_resistencia() -> float:
	var ahorro := 0.0
	for p: Dictionary in _piezas_activas():
		ahorro += float(Herreria.stats_pieza(str(p["id"]), p["gemas"] as Array, int(p["temple"])).get("ahorro_resistencia", 0.0))
	return minf(0.60, ahorro)


func bono_suerte_pesca() -> float:
	return float(nivel_habilidad("pesca") - 1) * 0.04


func bono_suerte_recoleccion() -> float:
	return float(nivel_habilidad("recoleccion") - 1) * 0.05


func bono_velocidad() -> float:
	return float(nivel_habilidad("recoleccion") - 1) * 0.02 + valor_bufo("velocidad")


func recetas_aprendidas() -> Array[String]:
	if not (banderas.get("recetas", null) is Array):
		banderas["recetas"] = []
	var out: Array[String] = []
	for item: Variant in banderas["recetas"] as Array:
		var s := str(item)
		if not s.is_empty() and not out.has(s):
			out.append(s)
	return out


func tiene_receta(id: String) -> bool:
	return recetas_aprendidas().has(id)


func aprender_receta(id: String, notificar: bool = true) -> bool:
	if id.is_empty() or not Datos.existe_receta(id):
		return false
	if not (banderas.get("recetas", null) is Array):
		banderas["recetas"] = []
	var arr := banderas["recetas"] as Array
	if arr.has(id):
		return false
	arr.append(id)
	recetas_cambiadas.emit()
	if notificar:
		var nom := str(Datos.receta(id).get("nombre", id))
		mensaje_objeto.emit("Nueva receta aprendida: %s." % nom, id)
	return true


func sincronizar_recetas(notificar: bool = true) -> void:
	var misiones_node := get_node_or_null("/root/Misiones")
	for r: Dictionary in Datos.recetas():
		var rid := str(r.get("id", ""))
		if rid.is_empty() or tiene_receta(rid):
			continue
		var orig: Dictionary = r.get("origen", {}) as Dictionary
		var tipo := str(orig.get("tipo", ""))
		match tipo:
			"inicial":
				aprender_receta(rid, false)
			"amistad":
				var npc_id := str(orig.get("npc", ""))
				var pts := int(orig.get("puntos", 999))
				if puntos_amistad(npc_id) >= pts:
					aprender_receta(rid, notificar)
			"mision":
				var mid := str(orig.get("mision", ""))
				if misiones_node != null and misiones_node.has_method("esta_completada") and bool(misiones_node.call("esta_completada", mid)):
					aprender_receta(rid, notificar)


func puede_cocinar(id: String, veces: int = 1) -> bool:
	if veces <= 0 or not tiene_receta(id):
		return false
	var rec := Datos.receta(id)
	if rec.is_empty():
		return false
	for ing: Variant in rec.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			if cantidad(str(d.get("id", ""))) < int(d.get("cantidad", 1)) * veces:
				return false
	return espacio_para(id) >= veces


func cocinar(id: String, veces: int = 1) -> bool:
	if not puede_cocinar(id, veces):
		return false
	var rec := Datos.receta(id)
	for ing: Variant in rec.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			quitar_objeto(str(d.get("id", "")), int(d.get("cantidad", 1)) * veces)
	anadir_objeto(id, veces)
	ganar_xp_habilidad("recoleccion", 4 * veces)
	estadisticas["platos_cocinados"] = int(estadisticas.get("platos_cocinados", 0)) + veces
	evaluar_logros()
	return true


func bufos_activos() -> Dictionary:
	var raw: Variant = banderas.get("bufos", null)
	if not (raw is Dictionary):
		raw = {}
		banderas["bufos"] = raw
	return raw as Dictionary


func valor_bufo(tipo: String) -> float:
	var b := bufos_activos()
	var reg: Variant = b.get(tipo, null)
	if reg is Dictionary and float((reg as Dictionary).get("restante", 0.0)) > 0.0:
		return float((reg as Dictionary).get("valor", 0.0))
	return 0.0


func _aplicar_bufo(bufo: Dictionary, origen_nombre: String) -> void:
	var tipo := str(bufo.get("tipo", ""))
	if tipo.is_empty():
		return
	var b := bufos_activos()
	b[tipo] = {
		"valor": float(bufo.get("valor", 0.0)),
		"restante": maxi(15, int(bufo.get("duracion_min", 180))),
		"etiqueta": str(bufo.get("etiqueta", BUFOS_NOMBRES.get(tipo, tipo))),
		"origen": origen_nombre,
	}
	bufos_cambiados.emit()


func _avanzar_bufos(mins: int) -> void:
	if mins <= 0:
		return
	var raw: Variant = banderas.get("bufos", null)
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return
	var b := raw as Dictionary
	var expiro := false
	for k: Variant in b.keys():
		var reg := b[k] as Dictionary
		reg["restante"] = int(reg.get("restante", 0)) - mins
		if int(reg["restante"]) <= 0:
			b.erase(k)
			expiro = true
	if expiro or not b.is_empty():
		bufos_cambiados.emit()


func _limpiar_bufos() -> void:
	if banderas.get("bufos", {}) is Dictionary and not (banderas["bufos"] as Dictionary).is_empty():
		banderas["bufos"] = {}
		bufos_cambiados.emit()

## Por qué falló la última carga (texto para el jugador) o "" si fue bien.
var ultimo_error_carga: String = ""


func hay_partida() -> bool:
	return FileAccess.file_exists(ruta_partida)


## Hay una copia de seguridad (la partida válida anterior al último guardado).
func hay_copia() -> bool:
	return FileAccess.file_exists(ruta_partida + SUFIJO_COPIA)


## Lee un archivo de partida sin cargarlo. Devuelve {} si no existe, está dañado o no es una partida.
func leer_archivo(ruta: String) -> Dictionary:
	if not FileAccess.file_exists(ruta):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(ruta)) != OK or not (json.data is Dictionary):
		return {}
	var d: Dictionary = json.data
	# Una partida de verdad lleva al menos esto; un archivo cortado o vacío no pasa.
	for clave: String in ["dinero", "dia", "estacion", "inventario"]:
		if not d.has(clave):
			return {}
	if not (d["inventario"] is Array):
		return {}
	return d


## Estado de lo que hay en disco: "ninguna", "ok", "danada_con_copia" o "danada_sin_copia".
## Si un guardado se quedó a medias (hay temporal o copia pero no partida) cuenta como dañada con copia.
func estado_guardado() -> String:
	var hay := hay_partida()
	if hay and not leer_archivo(ruta_partida).is_empty():
		return "ok"
	var copia_valida := not leer_archivo(ruta_partida + SUFIJO_COPIA).is_empty() or not leer_archivo(ruta_partida + SUFIJO_TEMPORAL).is_empty()
	if copia_valida:
		return "danada_con_copia"
	return "danada_sin_copia" if hay else "ninguna"


## Texto corto de una partida guardada («Verano, día 3 · 1.250 €») para los menús.
func resumen_de(ruta: String) -> String:
	var d := leer_archivo(ruta)
	if d.is_empty():
		return ""
	var est := clampi(int(d.get("estacion", 0)), 0, 3)
	return "%s, día %d · %s" % [NOMBRES_ESTACION[est], int(d.get("dia", 1)), Estilo.euros(int(d.get("dinero", 0)))]


func _datos_de_guardado() -> Dictionary:
	var datos: Dictionary = {
		"version": VERSION_GUARDADO,
		"version_juego": str(ProjectSettings.get_setting("application/config/version", "")),
		"guardado_el": Time.get_datetime_string_from_system(false, true),
		"nombre_jugador": nombre_jugador,
		"dinero": dinero,
		"deuda": deuda,
		"energia": energia,
		"energia_max": energia_max,
		"vida": vida,
		"vida_max": vida_max,
		"equipo": equipo.duplicate(),
		"dia": dia,
		"estacion": estacion,
		"anio": anio,
		"minutos": minutos,
		"clima": clima,
		"inventario": inventario,
		"ranura": ranura,
		"amistad": amistad,
		"hablado_hoy": hablado_hoy,
		"nivel_herramientas": nivel_herramientas,
		"estado_mapas": estado_mapas,
		"banderas": banderas,
		"mapa_actual": mapa_actual,
		"estadisticas": estadisticas,
		"tiempo_jugado_seg": tiempo_jugado_seg,
	}
	var j: Node3D = Escenas.jugador()
	if j != null:
		var p := j.global_position
		datos["posicion"] = [p.x, p.y, p.z]
	return datos


func guardar(avisar: bool = false) -> bool:
	var texto := JSON.stringify(_datos_de_guardado(), "\t")
	var temporal := ruta_partida + SUFIJO_TEMPORAL
	var copia := ruta_partida + SUFIJO_COPIA
	# 1) Se escribe entero en el temporal.
	var f := FileAccess.open(temporal, FileAccess.WRITE)
	if f == null:
		return _fallo_al_guardar("no se pudo crear el archivo (%s)" % error_string(FileAccess.get_open_error()))
	f.store_string(texto)
	var error_escritura := f.get_error()
	f.close()
	if error_escritura != OK:
		DirAccess.remove_absolute(temporal)
		return _fallo_al_guardar("no se pudo escribir (%s); ¿queda sitio en el disco?" % error_string(error_escritura))
	# 2) Se comprueba releyéndolo: si no es una partida entera, la que había no se toca.
	if leer_archivo(temporal).is_empty():
		DirAccess.remove_absolute(temporal)
		return _fallo_al_guardar("el archivo escrito no se pudo comprobar")
	# 3) La partida anterior, si era válida, pasa a ser la copia de seguridad; si estaba dañada, se quita.
	if FileAccess.file_exists(ruta_partida):
		if not leer_archivo(ruta_partida).is_empty():
			if FileAccess.file_exists(copia):
				DirAccess.remove_absolute(copia)
			if DirAccess.rename_absolute(ruta_partida, copia) != OK:
				DirAccess.remove_absolute(temporal)
				return _fallo_al_guardar("no se pudo apartar la partida anterior")
		else:
			DirAccess.remove_absolute(ruta_partida)
	# 4) El temporal sustituye a la partida.
	if DirAccess.rename_absolute(temporal, ruta_partida) != OK:
		return _fallo_al_guardar("no se pudo sustituir la partida (la anterior sigue en la copia de seguridad)")
	_capturar_miniatura_guardado()
	partida_guardada.emit()
	if avisar:
		mensaje.emit("Partida guardada.")
	return true


func _fallo_al_guardar(motivo: String) -> bool:
	push_error("No se pudo guardar la partida: %s" % motivo)
	mensaje.emit("No se ha podido guardar la partida: %s." % motivo)
	return false


## Borra la partida, su copia y los restos de un guardado a medias (lo usan las pruebas).
func borrar_partida() -> void:
	for sufijo: String in ["", SUFIJO_TEMPORAL, SUFIJO_COPIA, SUFIJO_DANADA]:
		if FileAccess.file_exists(ruta_partida + sufijo):
			DirAccess.remove_absolute(ruta_partida + sufijo)


## Pone la copia de seguridad (o el temporal de un guardado que no llegó a terminar) en el sitio de la partida. La
## dañada se conserva como `<ruta>.danada` por si se quiere mirar. Devuelve true si después hay una partida válida.
func recuperar_copia() -> bool:
	var origen := ""
	# El temporal, si es válido, es más reciente que la copia.
	for candidata: String in [ruta_partida + SUFIJO_TEMPORAL, ruta_partida + SUFIJO_COPIA]:
		if not leer_archivo(candidata).is_empty():
			origen = candidata
			break
	if origen.is_empty():
		return false
	if FileAccess.file_exists(ruta_partida):
		var apartada := ruta_partida + SUFIJO_DANADA
		if FileAccess.file_exists(apartada):
			DirAccess.remove_absolute(apartada)
		DirAccess.rename_absolute(ruta_partida, apartada)
	if DirAccess.copy_absolute(origen, ruta_partida) != OK:
		return false
	return not leer_archivo(ruta_partida).is_empty()


## Pasa una partida de un formato antiguo al actual. Cada paso sube una versión; no se pierde nada de lo que hubiera.
func _migrar(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# 1 → 2: aparecen la fecha del guardado y la versión del juego; las estadísticas pueden venir incompletas.
		if not d.has("guardado_el"):
			d["guardado_el"] = ""
		if not d.has("version_juego"):
			d["version_juego"] = ""
		var est: Dictionary = _diccionario(d.get("estadisticas", {}))
		for clave: String in ["cosechas", "dias", "dinero_ganado", "dinero_gastado"]:
			if not est.has(clave):
				est[clave] = 0
		d["estadisticas"] = est
		v = 2
	if v < 3:
		d["equipo"] = {}
		v = 3
	d["version"] = v
	return d


## Carga la partida guardada. No cambia de escena: eso lo hace Escenas.continuar_partida().
## Si falla, `ultimo_error_carga` dice por qué y la partida en curso (si la había) no se toca.
func cargar() -> bool:
	ultimo_error_carga = ""
	if not hay_partida():
		ultimo_error_carga = "No hay ninguna partida guardada."
		return false
	var leido := leer_archivo(ruta_partida)
	if leido.is_empty():
		push_error("La partida guardada está dañada.")
		ultimo_error_carga = "La partida guardada está dañada y no se puede abrir."
		return false
	if int(leido.get("version", 1)) > VERSION_GUARDADO:
		ultimo_error_carga = "La partida es de una versión más nueva del juego. Actualiza Mala Hierba para abrirla."
		return false
	var d: Dictionary = _migrar(Datos.normalizar_numeros(leido))
	nombre_jugador = str(d.get("nombre_jugador", "Leo"))
	dinero = int(d.get("dinero", DINERO_INICIAL))
	deuda = int(d.get("deuda", DEUDA_INICIAL))
	energia_max = maxf(float(d.get("energia_max", ENERGIA_INICIAL)), 1.0)
	energia = clampf(float(d.get("energia", ENERGIA_INICIAL)), 0.0, energia_max)
	vida_max = maxf(float(d.get("vida_max", VIDA_INICIAL)), 1.0)
	vida = clampf(float(d.get("vida", vida_max)), 0.0, vida_max)
	if vida <= 0.0:
		vida = vida_max * 0.75
	resistencia = RESISTENCIA_MAX
	_pausa_resistencia = 0.0
	_desmayo_pendiente = false
	equipo = {}
	var equipo_guardado := _diccionario(d.get("equipo", {}))
	for sitio: String in RANURAS_EQUIPO:
		var id := str(equipo_guardado.get(sitio, ""))
		if Datos.objeto(id).get("ranura_equipo", "") == sitio:
			equipo[sitio] = id
	dia = clampi(int(d.get("dia", 1)), 1, DIAS_ESTACION)
	estacion = clampi(int(d.get("estacion", 0)), 0, 3)
	anio = int(d.get("anio", 1))
	minutos = clampi(int(d.get("minutos", HORA_INICIO)), HORA_INICIO, HORA_FIN - 1)
	clima = str(d.get("clima", "sol"))
	ranura = clampi(int(d.get("ranura", 0)), 0, 9)
	amistad = _diccionario(d.get("amistad", {}))
	hablado_hoy = _diccionario(d.get("hablado_hoy", {}))
	nivel_herramientas = _diccionario(d.get("nivel_herramientas", {}))
	estado_mapas = _diccionario(d.get("estado_mapas", {}))
	banderas = _diccionario(d.get("banderas", {}))
	_asegurar_eventos()
	mapa_actual = str(d.get("mapa_actual", ""))
	estadisticas = _diccionario(d.get("estadisticas", {}))
	tiempo_jugado_seg = maxf(0.0, float(d.get("tiempo_jugado_seg", 0.0)))
	_vaciar_inventario()
	var guardado: Array = d.get("inventario", []) if d.get("inventario", []) is Array else []
	for i in mini(guardado.size(), HUECOS):
		if not (guardado[i] is Dictionary):
			continue
		var h: Dictionary = guardado[i]
		if not h.is_empty() and Datos.existe_objeto(str(h.get("id", ""))):
			var cargado_h: Dictionary = {"id": str(h["id"]), "cantidad": clampi(int(h.get("cantidad", 1)), 1, PILA_MAX)}
			if str(h.get("calidad", "")) == "baja":
				cargado_h["calidad"] = "baja"
			var gem_raw: Variant = h.get("gemas", null)
			if gem_raw is Array and not (gem_raw as Array).is_empty():
				var g_limpias: Array[String] = []
				for g: Variant in gem_raw as Array:
					if Herreria.GEMAS.has(str(g)):
						g_limpias.append(str(g))
				if not g_limpias.is_empty():
					cargado_h["gemas"] = g_limpias
			var t_val := clampi(int(h.get("temple", 0)), 0, Herreria.TEMPLE_MAX)
			if t_val > 0:
				cargado_h["temple"] = t_val
			inventario[i] = cargado_h
	var pos: Variant = d.get("posicion", [])
	posicion_guardada = pos if pos is Array and (pos as Array).size() == 3 else []
	banderas.erase("_posicion_guardada")
	_acumulado = 0.0
	_aviso_cansancio = false
	partida_activa = true
	actualizar_entorno_shader()
	_emitir_todo()
	if not mapa_actual.is_empty():
		registrar_zona_visitada(mapa_actual, false)
	evaluar_logros(false)
	partida_cambiada.emit()
	evento_cambiado.emit()
	logros_cambiados.emit()
	return true


func _diccionario(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


# --- Horno de fundición, temple y engaste de gemas (H10) -----------------------------------------

func _tiene_meta_propia(h: Dictionary) -> bool:
	var g: Variant = h.get("gemas", null)
	return (g is Array and not (g as Array).is_empty()) or int(h.get("temple", 0)) > 0


func _lista_gemas(h: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var g: Variant = h.get("gemas", null)
	if g is Array:
		for x: Variant in g as Array:
			var s := str(x)
			if Herreria.GEMAS.has(s):
				out.append(s)
	return out


func _aplicar_meta_hueco(hueco: Dictionary, meta: Dictionary) -> Dictionary:
	var gs := _lista_gemas(meta)
	if not gs.is_empty():
		hueco["gemas"] = gs
	else:
		hueco.erase("gemas")
	var t := clampi(int(meta.get("temple", 0)), 0, Herreria.TEMPLE_MAX)
	if t > 0:
		hueco["temple"] = t
	else:
		hueco.erase("temple")
	return hueco


func _h10_equipo_meta() -> Dictionary:
	var raw: Variant = banderas.get("h10_equipo", null)
	if not (raw is Dictionary):
		raw = {}
		banderas["h10_equipo"] = raw
	return raw as Dictionary


func _piezas_activas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var act := objeto_activo()
	var oid := str(act.get("id", ""))
	if not oid.is_empty() and Herreria.es_engastable(oid) and not Datos.objeto(oid).has("ranura_equipo"):
		out.append({"id": oid, "gemas": _lista_gemas(act), "temple": int(act.get("temple", 0))})
	var meta_eq := _h10_equipo_meta()
	for sitio: String in RANURAS_EQUIPO:
		var eid := str(equipo.get(sitio, ""))
		if eid.is_empty():
			continue
		var m := meta_eq.get(sitio, {}) as Dictionary
		out.append({"id": eid, "gemas": _lista_gemas(m), "temple": int(m.get("temple", 0))})
	return out


func stats_arma_activa() -> Dictionary:
	var act := objeto_activo()
	if act.is_empty():
		return {}
	return Herreria.stats_pieza(str(act.get("id", "")), _lista_gemas(act), int(act.get("temple", 0)))


func reduccion_escudo() -> float:
	var eid := str(equipo.get("escudo", ""))
	if eid.is_empty():
		return 0.45
	var m := _h10_equipo_meta().get("escudo", {}) as Dictionary
	var st := Herreria.stats_pieza(eid, _lista_gemas(m), int(m.get("temple", 0)))
	return maxf(0.45, float(st.get("reduccion", 0.66)))


func horno_cola() -> Array:
	var raw: Variant = banderas.get("h10_horno", null)
	if not (raw is Array):
		raw = []
		banderas["h10_horno"] = raw
	return raw as Array


func horno_listos_total() -> int:
	var total := 0
	for l: Variant in horno_cola():
		if l is Dictionary and int((l as Dictionary).get("restante", 0)) <= 0:
			total += int((l as Dictionary).get("entrega", 1))
	return total


func iniciar_fundicion(id_receta: String, usar_madera: bool = false) -> bool:
	if horno_cola().size() >= 3:
		mensaje.emit("El horno está lleno (máximo 3 crisoles activos). Recoge antes lo fundido.")
		return false
	var r := Herreria.receta_horno(id_receta)
	if r.is_empty():
		return false
	var min_id := str(r["mineral"])
	var min_cant := int(r["cantidad"])
	var precio := int(r["dinero"])
	if cantidad(min_id) < min_cant or dinero < precio:
		return false
	var comb_id := ""
	var comb_cant := 0
	var base_comb := str(r.get("combustible", ""))
	if not base_comb.is_empty():
		if usar_madera and int(r.get("madera_alt", 0)) > 0:
			comb_id = "madera"
			comb_cant = int(r["madera_alt"])
		elif not usar_madera and cantidad(base_comb) >= int(r.get("coste_comb", 1)):
			comb_id = base_comb
			comb_cant = int(r.get("coste_comb", 1))
		elif int(r.get("madera_alt", 0)) > 0 and cantidad("madera") >= int(r["madera_alt"]):
			comb_id = "madera"
			comb_cant = int(r["madera_alt"])
		else:
			return false
	if not quitar_objeto(min_id, min_cant):
		return false
	if not comb_id.is_empty() and not quitar_objeto(comb_id, comb_cant):
		_poner(min_id, min_cant)
		return false
	cobrar(precio)
	var mins := int(r.get("minutos", 50))
	horno_cola().append({
		"receta": id_receta,
		"lingote": str(r["lingote"]),
		"entrega": int(r.get("entrega", 1)),
		"duracion": mins,
		"restante": mins,
	})
	horno_cambiado.emit()
	Audio.reproducir("horno_fundir")
	return true


func _avanzar_horno(mins: int) -> void:
	if mins <= 0:
		return
	var cola := horno_cola()
	if cola.is_empty():
		return
	var cambio := false
	for item: Variant in cola:
		if item is Dictionary:
			var d := item as Dictionary
			var rest := int(d.get("restante", 0))
			if rest > 0:
				d["restante"] = maxi(0, rest - mins)
				cambio = true
				if int(d["restante"]) == 0:
					mensaje.emit("Horno listo: %s." % Datos.nombre_objeto(str(d.get("lingote", ""))))
	if cambio:
		horno_cambiado.emit()


func recoger_fundicion() -> int:
	var cola := horno_cola()
	var recogidos := 0
	for i in range(cola.size() - 1, -1, -1):
		var d: Dictionary = cola[i] if cola[i] is Dictionary else {}
		if int(d.get("restante", 1)) > 0:
			continue
		var lid := str(d.get("lingote", ""))
		var cant := int(d.get("entrega", 1))
		if espacio_para(lid) < cant:
			mensaje.emit("Haz sitio en el inventario para recoger %s." % Datos.nombre_objeto(lid))
			continue
		cola.remove_at(i)
		anadir_objeto(lid, cant)
		recogidos += cant
	if recogidos > 0:
		horno_cambiado.emit()
		ganar_xp_habilidad("mineria", 3 * recogidos)
	return recogidos


func listar_engastables() -> Array[Dictionary]:
	var lista: Array[Dictionary] = []
	var meta_eq := _h10_equipo_meta()
	for sitio: String in RANURAS_EQUIPO:
		var eid := str(equipo.get(sitio, ""))
		if eid.is_empty() or not Herreria.es_engastable(eid):
			continue
		var m := meta_eq.get(sitio, {}) as Dictionary
		lista.append({"origen": "equipo", "sitio": sitio, "indice": -1, "id": eid, "gemas": _lista_gemas(m), "temple": int(m.get("temple", 0))})
	for i in HUECOS:
		var h: Dictionary = inventario[i]
		if h.is_empty():
			continue
		var oid := str(h.get("id", ""))
		if Herreria.es_engastable(oid):
			lista.append({"origen": "inventario", "sitio": "", "indice": i, "id": oid, "gemas": _lista_gemas(h), "temple": int(h.get("temple", 0))})
	return lista


func engastar_gema(origen: String, indice: int, sitio: String, gema_id: String) -> bool:
	if not Herreria.GEMAS.has(gema_id) or cantidad(gema_id) < 1 or dinero < Herreria.COSTE_ENGASTE:
		return false
	var meta := _leer_meta_pieza(origen, indice, sitio)
	if meta.is_empty():
		return false
	var id_pieza := str(meta["id"])
	var max_h := Herreria.huecos_para(id_pieza)
	var gs: Array[String] = meta["gemas"]
	if gs.size() >= max_h:
		return false
	if not quitar_objeto(gema_id, 1):
		return false
	cobrar(Herreria.COSTE_ENGASTE)
	gs.append(gema_id)
	_guardar_meta_pieza(origen, indice, sitio, gs, int(meta["temple"]))
	estadisticas["gemas_engastadas"] = int(estadisticas.get("gemas_engastadas", 0)) + 1
	Audio.reproducir("engaste_gema")
	evaluar_logros()
	return true


func desengastar_gema(origen: String, indice: int, sitio: String, idx_hueco: int, rotura_forzada: int = -1) -> String:
	var meta := _leer_meta_pieza(origen, indice, sitio)
	if meta.is_empty() or dinero < Herreria.COSTE_DESENGASTE:
		return "sin_dinero"
	var gs: Array[String] = meta["gemas"]
	if idx_hueco < 0 or idx_hueco >= gs.size():
		return "invalido"
	var gema_id := gs[idx_hueco]
	var rota := (rotura_forzada == 1) if rotura_forzada >= 0 else (randf() < Herreria.PROB_ROTURA_DESENGASTE)
	if not rota and espacio_para(gema_id) < 1:
		return "sin_espacio"
	cobrar(Herreria.COSTE_DESENGASTE)
	gs.remove_at(idx_hueco)
	_guardar_meta_pieza(origen, indice, sitio, gs, int(meta["temple"]))
	if not rota:
		anadir_objeto(gema_id, 1)
		Audio.reproducir("engaste_gema")
		return "devuelta"
	Audio.reproducir("roca_romper")
	return "rota"


func templar_con_lingote(origen: String, indice: int, sitio: String) -> bool:
	var meta := _leer_meta_pieza(origen, indice, sitio)
	if meta.is_empty():
		return false
	var temple := int(meta["temple"])
	if temple >= Herreria.TEMPLE_MAX:
		return false
	var grado := clampi(int(Datos.objeto(str(meta["id"])).get("grado", 0)), 0, 2)
	var lingote_id := Herreria.lingote_para_grado(mini(2, grado + (1 if temple >= 2 else 0)))
	var cant := 1 + temple
	var coste := 40 + temple * 35
	if cantidad(lingote_id) < cant or dinero < coste:
		return false
	if not quitar_objeto(lingote_id, cant):
		return false
	cobrar(coste)
	_guardar_meta_pieza(origen, indice, sitio, meta["gemas"] as Array, temple + 1)
	Audio.reproducir("horno_fundir")
	return true


func _leer_meta_pieza(origen: String, indice: int, sitio: String) -> Dictionary:
	if origen == "equipo":
		var id := str(equipo.get(sitio, ""))
		if id.is_empty() or not Herreria.es_engastable(id):
			return {}
		var m := _h10_equipo_meta().get(sitio, {}) as Dictionary
		return {"id": id, "gemas": _lista_gemas(m), "temple": int(m.get("temple", 0))}
	if indice < 0 or indice >= HUECOS:
		return {}
	var h: Dictionary = inventario[indice]
	var id_i := str(h.get("id", ""))
	if h.is_empty() or not Herreria.es_engastable(id_i):
		return {}
	return {"id": id_i, "gemas": _lista_gemas(h), "temple": int(h.get("temple", 0))}


func _guardar_meta_pieza(origen: String, indice: int, sitio: String, gs: Array, temple: int) -> void:
	if origen == "equipo":
		var meta_eq := _h10_equipo_meta()
		var nuevo := {"gemas": gs, "temple": temple}
		if gs.is_empty() and temple <= 0:
			meta_eq.erase(sitio)
		else:
			meta_eq[sitio] = nuevo
	else:
		var h: Dictionary = inventario[indice]
		if int(h.get("cantidad", 1)) > 1:
			# Separa 1 unidad única para recibir el engaste/temple sin duplicar la pila
			var hueco_libre := -1
			for k in HUECOS:
				if (inventario[k] as Dictionary).is_empty():
					hueco_libre = k
					break
			if hueco_libre >= 0:
				h["cantidad"] = int(h["cantidad"]) - 1
				var separada := _aplicar_meta_hueco({"id": h["id"], "cantidad": 1}, {"gemas": gs, "temple": temple})
				inventario[hueco_libre] = separada
		else:
			_aplicar_meta_hueco(h, {"gemas": gs, "temple": temple})
	inventario_cambiado.emit()
	equipo_cambiado.emit()
	gemas_cambiadas.emit()
	ranura_cambiada.emit(ranura)


# --- Pesca avanzada, cebos y álbum (H11) ----------------------------------------------------------

func cebo_activo() -> String:
	var id := str(banderas.get("cebo_activo", ""))
	if not id.is_empty() and cantidad(id) > 0:
		return id
	for c_id: String in ["cebo_lombriz", "cebo_masilla", "cebo_mosca", "cebo_luminoso"]:
		if cantidad(c_id) > 0:
			banderas["cebo_activo"] = c_id
			return c_id
	banderas["cebo_activo"] = ""
	return ""


func elegir_cebo(id_cebo: String) -> bool:
	if id_cebo.is_empty():
		banderas["cebo_activo"] = ""
		pesca_cambiada.emit()
		return true
	if cantidad(id_cebo) <= 0:
		return false
	banderas["cebo_activo"] = id_cebo
	pesca_cambiada.emit()
	return true


func consumir_cebo() -> String:
	var cid := cebo_activo()
	if not cid.is_empty() and quitar_objeto(cid, 1):
		pesca_cambiada.emit()
		return cid
	return ""


func fabricar_cebo(id_cebo: String) -> bool:
	var rec: Dictionary = {}
	for r: Dictionary in PescaAvanzada.RECETAS_CEBO:
		if str(r["id"]) == id_cebo:
			rec = r
			break
	if rec.is_empty():
		return false
	for ing: Variant in rec.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			if cantidad(str(d.get("id", ""))) < int(d.get("cantidad", 1)):
				return false
	var ent := int(rec.get("entrega", 1))
	if espacio_para(id_cebo) < ent:
		return false
	for ing: Variant in rec.get("ingredientes", []):
		if ing is Dictionary:
			var d := ing as Dictionary
			quitar_objeto(str(d.get("id", "")), int(d.get("cantidad", 1)))
	anadir_objeto(id_cebo, ent)
	if str(banderas.get("cebo_activo", "")).is_empty():
		banderas["cebo_activo"] = id_cebo
	pesca_cambiada.emit()
	return true


func album_pesca() -> Dictionary:
	var raw: Variant = banderas.get("album_pesca", null)
	if not (raw is Dictionary):
		raw = {}
		banderas["album_pesca"] = raw
	return raw as Dictionary


func registrar_captura_pesca(ejemplar: Dictionary, zona: String) -> Dictionary:
	var eid := str(ejemplar.get("id", "trucha"))
	var cm := float(ejemplar.get("cm", 25.0))
	var kg := float(ejemplar.get("kg", 0.5))
	var alb := album_pesca()
	var reg: Dictionary = alb.get(eid, {}) as Dictionary
	var nueva := reg.is_empty()
	var cap := int(reg.get("capturas", 0)) + 1
	var max_cm := maxf(float(reg.get("max_cm", 0.0)), cm)
	var max_kg := maxf(float(reg.get("max_kg", 0.0)), kg)
	var h := "%02d:%02d" % [minutos / 60, minutos % 60]
	var mom := "%s · Día %d · %s" % [NOMBRES_ESTACION[clampi(estacion, 0, 3)], dia, h]
	alb[eid] = {
		"capturas": cap,
		"max_cm": max_cm,
		"max_kg": max_kg,
		"zona": zona,
		"momento": mom,
	}
	var xp := 36 if eid in ["esturion", "pez_ciego", "salmon_sierra", "lucio"] else 22
	ganar_xp_habilidad("pesca", xp)
	pesca_cambiada.emit()
	evaluar_logros()
	return {
		"nueva": nueva,
		"record_cm": cm >= max_cm and not nueva,
		"record_kg": kg >= max_kg and not nueva,
	}


# --- Granja ganadera: gallinero y colmenas (H12) --------------------------------------------------

func ganado_estado() -> Dictionary:
	var raw: Variant = banderas.get("h12_ganado", null)
	if not (raw is Dictionary):
		raw = {}
		banderas["h12_ganado"] = raw
	var g := raw as Dictionary
	if not (g.get("gallinero", null) is Dictionary):
		g["gallinero"] = {"reparado": false, "gallinas": 0, "comida": false, "agua": false, "cuidado_dias": 0, "huevos": []}
	if not (g.get("colmenas", null) is Array) or (g["colmenas"] as Array).size() < 3:
		g["colmenas"] = [
			{"desbloqueada": true, "tipo": "corcho", "progreso": 0, "miel": 0},
			{"desbloqueada": false, "tipo": "cuadros", "progreso": 0, "miel": 0},
			{"desbloqueada": false, "tipo": "cuadros", "progreso": 0, "miel": 0},
		]
	return g


func reparar_gallinero() -> bool:
	var g := ganado_estado()["gallinero"] as Dictionary
	if bool(g.get("reparado", false)):
		return false
	if cantidad("madera") < 8 or dinero < 120:
		return false
	if not quitar_objeto("madera", 8) or not cobrar(120):
		return false
	g["reparado"] = true
	g["gallinas"] = 2
	ganado_cambiado.emit()

	Audio.reproducir("ui_comprar")
	Audio.reproducir("gallinas_cacareo")
	evaluar_logros()
	return true


func comprar_gallina() -> bool:
	var g := ganado_estado()["gallinero"] as Dictionary
	if not bool(g.get("reparado", false)) or int(g.get("gallinas", 0)) >= 6 or dinero < 120:
		return false
	if not cobrar(120):
		return false
	g["gallinas"] = int(g["gallinas"]) + 1
	ganado_cambiado.emit()

	Audio.reproducir("gallinas_cacareo")
	return true


func alimentar_gallinero() -> bool:
	var g := ganado_estado()["gallinero"] as Dictionary
	if not bool(g.get("reparado", false)) or bool(g.get("comida", false)):
		return false
	var usado := false
	if cantidad("pienso_aves") >= 1:
		usado = quitar_objeto("pienso_aves", 1)
	elif cantidad("patata") >= 1:
		usado = quitar_objeto("patata", 1)
	elif cantidad("fibra") >= 2:
		usado = quitar_objeto("fibra", 2)
	if not usado:
		return false
	g["comida"] = true
	ganado_cambiado.emit()

	Audio.reproducir("gallinas_cacareo")
	return true


func dar_agua_gallinero() -> bool:
	var g := ganado_estado()["gallinero"] as Dictionary
	if not bool(g.get("reparado", false)) or bool(g.get("agua", false)):
		return false
	g["agua"] = true
	ganado_cambiado.emit()

	return true


func recoger_huevos() -> int:
	var g := ganado_estado()["gallinero"] as Dictionary
	var huevos: Array = g.get("huevos", []) as Array
	if huevos.is_empty():
		return 0
	var cogidos := 0
	while not huevos.is_empty():
		var hid := str(huevos[-1])
		if espacio_para(hid) < 1:
			break
		huevos.pop_back()
		anadir_objeto(hid, 1)
		cogidos += 1
	if cogidos > 0:
		TareasDiarias.registrar_progreso("huevos", cogidos)
		ganar_xp_habilidad("agricultura", 5 * cogidos)
		ganado_cambiado.emit()

		Audio.reproducir("huevo_recoger")
	return cogidos


func desbloquear_colmena(indice: int) -> bool:
	var cols := ganado_estado()["colmenas"] as Array
	if indice < 0 or indice >= cols.size():
		return false
	var c := cols[indice] as Dictionary
	if bool(c.get("desbloqueada", false)) or cantidad("madera") < 6 or dinero < 90:
		return false
	if not quitar_objeto("madera", 6) or not cobrar(90):
		return false
	c["desbloqueada"] = true
	c["progreso"] = 0
	c["miel"] = 0
	ganado_cambiado.emit()

	Audio.reproducir("ui_comprar")
	return true


func cosechar_colmena(indice: int) -> Dictionary:
	var cols := ganado_estado()["colmenas"] as Array
	if indice < 0 or indice >= cols.size():
		return {"ok": false, "miel": 0, "picadura": false}
	var c := cols[indice] as Dictionary
	var miel := int(c.get("miel", 0))
	if not bool(c.get("desbloqueada", false)) or miel <= 0:
		return {"ok": false, "miel": 0, "picadura": false}
	if espacio_para("tarro_miel") < 1:
		mensaje.emit("Haz sitio en el inventario para recoger la miel.")
		return {"ok": false, "miel": 0, "picadura": false}
	var con_ahumador := cantidad("ahumador") > 0
	var picadura := not con_ahumador
	if picadura:
		recibir_dano(12.0)
		Audio.reproducir("abeja_picadura")
		mensaje.emit("¡Ay! Las abejas te pican al recoger miel sin ahumador (-12 salud).")
	var cogidos := 0
	while miel > 0 and espacio_para("tarro_miel") >= 1:
		anadir_objeto("tarro_miel", 1)
		miel -= 1
		cogidos += 1
	c["miel"] = miel
	if cogidos > 0:
		TareasDiarias.registrar_progreso("miel", cogidos)
		ganar_xp_habilidad("recoleccion", 6 * cogidos)
		estadisticas["miel_cosechada"] = int(estadisticas.get("miel_cosechada", 0)) + cogidos
		ganado_cambiado.emit()
		evaluar_logros()

		if not picadura:
			Audio.reproducir("ui_comprar")
	return {"ok": cogidos > 0, "miel": cogidos, "picadura": picadura}


func _contar_flores_granja() -> int:
	var gm: Dictionary = estado_mapas.get("granja", {}) as Dictionary
	var parc: Variant = gm.get("parcelas", null)
	if not (parc is Dictionary):
		return 0
	var total := 0
	for k: Variant in parc as Dictionary:
		var celda: Variant = (parc as Dictionary)[k]
		if celda is Dictionary and not str((celda as Dictionary).get("cultivo", "")).is_empty():
			total += 1
	return total


func _avanzar_ganado_dia() -> void:
	var g := ganado_estado()["gallinero"] as Dictionary
	if bool(g.get("reparado", false)) and int(g.get("gallinas", 0)) > 0:
		var comida := bool(g.get("comida", false))
		var agua := bool(g.get("agua", false))
		if comida and agua:
			g["cuidado_dias"] = int(g.get("cuidado_dias", 0)) + 1
		else:
			g["cuidado_dias"] = 0
		if comida or agua:
			var gallinas := int(g["gallinas"])
			var cant := gallinas if (comida and agua) else maxi(1, gallinas / 2)
			if estacion == 3:
				cant = maxi(1, cant - 1)
			var huevos := g.get("huevos", []) as Array
			var prob_blanco := 0.65 if (comida and agua and int(g["cuidado_dias"]) >= 2 and estacion in [0, 1]) else 0.20
			for _i in cant:
				if huevos.size() >= 6:
					break
				huevos.append("huevo_blanco" if randf() < prob_blanco else "huevo_pardo")
		g["comida"] = false
		g["agua"] = false

	# Colmenas: nada en invierno (estacion == 3); las flores cercanas aceleran la cosecha
	var flores := _contar_flores_granja()
	var paso := 0 if estacion == 3 else (2 if (flores >= 6 and estacion in [0, 1]) else 1)
	if paso > 0:
		for item: Variant in ganado_estado()["colmenas"] as Array:
			if not (item is Dictionary):
				continue
			var c := item as Dictionary
			if not bool(c.get("desbloqueada", false)):
				continue
			var p := int(c.get("progreso", 0)) + paso
			var miel := int(c.get("miel", 0))
			while p >= 3 and miel < 2:
				p -= 3
				miel += 1
			c["progreso"] = p
			c["miel"] = miel
	ganado_cambiado.emit()


# --- Campamento portátil y descanso nocturno (H13) ------------------------------------------------

func campamento_estado() -> Dictionary:
	var raw: Variant = banderas.get("h13_campamento", null)
	if not (raw is Dictionary):
		return {}
	return raw as Dictionary


func guardar_campamento(id_mapa: String, pos: Vector3) -> void:
	banderas["h13_campamento"] = {"mapa": id_mapa, "pos": [pos.x, pos.y, pos.z]}
	evaluar_logros()


func limpiar_campamento() -> void:
	banderas.erase("h13_campamento")


## Descansa unas horas en el campamento sin cerrar el día ni alterar el ciclo de los cultivos.
func descansar_campamento(horas: int = 3) -> bool:
	if not partida_activa:
		return false
	var mins_avance := mini(horas * 60, maxi(0, HORA_FIN - 25 - minutos))
	if mins_avance > 0:
		minutos += mins_avance
		_avanzar_bufos(mins_avance)
		_avanzar_horno(mins_avance)
		hora_cambiada.emit(minutos)
	energia = minf(energia_max, energia + 35.0)
	vida = minf(vida_max, vida + vida_max * 0.45)
	_fijar_resistencia(RESISTENCIA_MAX)
	estadisticas["descansos_campamento"] = int(estadisticas.get("descansos_campamento", 0)) + 1
	energia_cambiada.emit(energia, energia_max)
	vida_cambiada.emit(vida, vida_max)
	evaluar_logros()
	return true


# --- Ranuras de guardado, migración legada y logros (H14) -----------------------------------------

static func ruta_ranura(indice: int) -> String:
	return "user://partida_%d.json" % clampi(indice, 1, MAX_RANURAS)


static func ruta_miniatura_ranura(indice: int) -> String:
	return "user://miniatura_ranura_%d.png" % clampi(indice, 1, MAX_RANURAS)


static func es_ruta_de_ranura(ruta: String) -> bool:
	for i in range(1, MAX_RANURAS + 1):
		if ruta == ruta_ranura(i):
			return true
	return false


func seleccionar_ranura_guardado(indice: int) -> void:
	ranura_guardado_activa = clampi(indice, 1, MAX_RANURAS)
	ruta_partida = ruta_ranura(ranura_guardado_activa)


## Migra automáticamente una partida heredada (`user://partida.json`) a la ranura 1 sin borrarla.
func migrar_partida_legada(origen: String = RUTA_PARTIDA, destino: String = "") -> bool:
	var dest := destino if not destino.is_empty() else ruta_ranura(1)
	if FileAccess.file_exists(dest) and not leer_archivo(dest).is_empty():
		return false
	var fuente := ""
	for cand: String in [origen, origen + SUFIJO_COPIA, origen + SUFIJO_TEMPORAL]:
		if FileAccess.file_exists(cand) and not leer_archivo(cand).is_empty():
			fuente = cand
			break
	if fuente.is_empty():
		return false
	var abs_src := ProjectSettings.globalize_path(fuente)
	var abs_dst := ProjectSettings.globalize_path(dest)
	if DirAccess.copy_absolute(abs_src, abs_dst) != OK:
		return false
	if FileAccess.file_exists(origen + SUFIJO_COPIA) and not FileAccess.file_exists(dest + SUFIJO_COPIA):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(origen + SUFIJO_COPIA), ProjectSettings.globalize_path(dest + SUFIJO_COPIA))
	return not leer_archivo(dest).is_empty()


func ranura_mas_reciente() -> int:
	var mejor := 1
	var mejor_ts := ""
	for i in range(1, MAX_RANURAS + 1):
		var d := leer_archivo(ruta_ranura(i))
		if d.is_empty():
			continue
		var ts := str(d.get("guardado_el", ""))
		if mejor_ts.is_empty() or ts > mejor_ts:
			mejor_ts = ts
			mejor = i
	return mejor


func miniatura_de_ranura(indice: int) -> Texture2D:
	var r := ruta_miniatura_ranura(indice)
	if not FileAccess.file_exists(r):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(r))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func info_ranura(indice: int) -> Dictionary:
	var idx := clampi(indice, 1, MAX_RANURAS)
	var r := ruta_ranura(idx)
	var est_guard := "ninguna"
	var d := leer_archivo(r)
	if not d.is_empty():
		est_guard = "ok"
	elif not leer_archivo(r + SUFIJO_COPIA).is_empty() or not leer_archivo(r + SUFIJO_TEMPORAL).is_empty():
		est_guard = "danada_con_copia"
	elif FileAccess.file_exists(r):
		est_guard = "danada_sin_copia"
	if est_guard != "ok":
		return {
			"ranura": idx,
			"ruta": r,
			"estado": est_guard,
			"existe": false,
			"miniatura": miniatura_de_ranura(idx),
		}
	var est_num := clampi(int(d.get("estacion", 0)), 0, 3)
	var band_d: Dictionary = d.get("banderas", {}) as Dictionary
	var logros_d: Dictionary = band_d.get("logros", {}) as Dictionary
	return {
		"ranura": idx,
		"ruta": r,
		"estado": "ok",
		"existe": true,
		"nombre": str(d.get("nombre_jugador", "Leo")),
		"dia": int(d.get("dia", 1)),
		"estacion": NOMBRES_ESTACION[est_num],
		"anio": int(d.get("anio", 1)),
		"dinero": int(d.get("dinero", 0)),
		"mina_max_nivel": clampi(int(band_d.get("mina_max_nivel", 1)), 1, 20),
		"tiempo_jugado_seg": maxf(0.0, float(d.get("tiempo_jugado_seg", 0.0))),
		"logros_count": logros_d.size(),
		"fin_anio": bool(band_d.get("fin_anio", false)),
		"guardado_el": str(d.get("guardado_el", "")),
		"resumen": resumen_de(r),
		"miniatura": miniatura_de_ranura(idx),
	}


func borrar_ranura(indice: int) -> void:
	var idx := clampi(indice, 1, MAX_RANURAS)
	var r := ruta_ranura(idx)
	for sufijo: String in ["", SUFIJO_TEMPORAL, SUFIJO_COPIA, SUFIJO_DANADA]:
		if FileAccess.file_exists(r + sufijo):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(r + sufijo))
	var mini_r := ruta_miniatura_ranura(idx)
	if FileAccess.file_exists(mini_r):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(mini_r))


func _capturar_miniatura_guardado() -> void:
	if DisplayServer.get_name() == "headless" or not partida_activa:
		return
	var slot := -1
	for i in range(1, MAX_RANURAS + 1):
		if ruta_partida == ruta_ranura(i):
			slot = i
			break
	if slot < 0:
		return
	capturar_miniatura_ranura(slot)


func capturar_miniatura_ranura(indice: int) -> bool:
	if DisplayServer.get_name() == "headless" or get_viewport() == null:
		return false
	var tex := get_viewport().get_texture()
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null or img.is_empty():
		return false
	img.resize(256, 144, Image.INTERPOLATE_BILINEAR)
	return img.save_png(ProjectSettings.globalize_path(ruta_miniatura_ranura(indice))) == OK


func registrar_zona_visitada(id_mapa: String, evaluar: bool = true) -> void:
	if id_mapa.is_empty():
		return
	var raw: Variant = banderas.get("zonas_visitadas", null)
	if not (raw is Array):
		raw = []
		banderas["zonas_visitadas"] = raw
	var arr := raw as Array
	if not arr.has(id_mapa):
		arr.append(id_mapa)
	if evaluar and partida_activa:
		evaluar_logros()


func registrar_jefe_derrotado(id_enemigo: String) -> void:
	if id_enemigo.is_empty():
		return
	var raw: Variant = banderas.get("jefes_derrotados", null)
	if not (raw is Array):
		raw = []
		banderas["jefes_derrotados"] = raw
	var arr := raw as Array
	if not arr.has(id_enemigo):
		arr.append(id_enemigo)
	if partida_activa:
		evaluar_logros()


func logros_desbloqueados() -> Dictionary:
	var raw: Variant = banderas.get("logros", null)
	if not (raw is Dictionary):
		raw = {}
		banderas["logros"] = raw
	return raw as Dictionary


func es_logro_desbloqueado(id: String) -> bool:
	return logros_desbloqueados().has(id)


func evaluar_logros(notificar: bool = true) -> int:
	var cumplidos := Logros.ids_cumplidos(self)
	if cumplidos.is_empty():
		return 0
	var reg := logros_desbloqueados()
	var nuevos := 0
	var momento := "%s · Día %d" % [NOMBRES_ESTACION[clampi(estacion, 0, 3)], dia]
	for lid: String in cumplidos:
		if not reg.has(lid):
			reg[lid] = {"dia": dia, "estacion": estacion, "anio": anio, "momento": momento}
			nuevos += 1
			if notificar and partida_activa and is_inside_tree():
				logro_desbloqueado.emit(Logros.buscar(lid))
				Audio.reproducir("logro_desbloqueado")
	if nuevos > 0 and is_inside_tree():
		logros_cambiados.emit()
	return nuevos
