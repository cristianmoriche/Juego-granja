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
const NOMBRES_ESTACION: Array[String] = ["Primavera", "Verano", "Otoño", "Invierno"]
const NOMBRES_DIA_SEMANA: Array[String] = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
const DIA_FESTIVO_PRIMAVERA := 14
const DIA_FESTIVO_OTONO := 74   # 18 de otoño (56 + 18)

var ruta_partida: String = RUTA_PARTIDA
var nombre_jugador: String = "Leo"
var dinero: int = DINERO_INICIAL
var deuda: int = DEUDA_INICIAL
var energia: float = ENERGIA_INICIAL
var energia_max: float = ENERGIA_INICIAL
var vida: float = VIDA_INICIAL
var vida_max: float = VIDA_INICIAL
const RESISTENCIA_MAX := 100.0
const RANURAS_EQUIPO := ["escudo", "casco", "peto", "botas"]
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
	_vaciar_inventario()
	actualizar_entorno_shader()


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
	_acumulado += delta
	while _acumulado >= MINUTO_REAL and partida_activa:
		_acumulado -= MINUTO_REAL
		avanzar_minutos(1)


## El reloj corre cuando hay partida, un jugador en el mapa y ningún menú, diálogo o carga.
func tiempo_corre() -> bool:
	if not partida_activa or _pausa_externa or _pausa_por_ventana or get_tree().paused:
		return false
	if Escenas.en_transicion or Escenas.jugador() == null:
		return false
	return not Interfaz.ocupada()


func pausar_tiempo(p: bool) -> void:
	_pausa_externa = p


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
	partida_activa = true
	actualizar_entorno_shader()
	_emitir_todo()
	partida_cambiada.emit()
	evento_cambiado.emit()


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
	if n <= 0.0 or not partida_activa or _desmayo_pendiente:
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
	if n <= 0.0:
		return true
	if resistencia + 0.001 < n or _desmayo_pendiente:
		return false
	_fijar_resistencia(resistencia - n)
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
	# Primero completa las pilas que ya hay con la misma calidad.
	for i in HUECOS:
		var h: Dictionary = inventario[i]
		if falta > 0 and not h.is_empty() and h["id"] == id and str(h.get("calidad", "")) == cal and int(h["cantidad"]) < PILA_MAX:
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
	if cantidad(material) < unidades or dinero < precio:
		return false
	var anterior := inventario.duplicate(true)
	_quitar_del_inventario(material, unidades)
	if _poner(id, 1) != 0:
		inventario = anterior
		mensaje.emit("El inventario está lleno. Haz sitio para la pieza forjada.")
		return false
	cobrar(precio)
	inventario_cambiado.emit()
	mensaje_objeto.emit("+1 %s" % Datos.nombre_objeto(id), id)
	return true


func equipar(indice: int) -> bool:
	if not partida_activa or indice < 0 or indice >= inventario.size():
		return false
	var h: Dictionary = inventario[indice]
	var id := str(h.get("id", ""))
	var sitio := str(Datos.objeto(id).get("ranura_equipo", ""))
	if not sitio in RANURAS_EQUIPO:
		return false
	var previo := str(equipo.get(sitio, ""))
	if previo == id:
		return false
	if int(h["cantidad"]) == 1:
		inventario[indice] = {} if previo.is_empty() else {"id": previo, "cantidad": 1}
	else:
		if not previo.is_empty() and _poner(previo, 1) != 0:
			mensaje.emit("Haz sitio en el inventario para la pieza que llevabas.")
			return false
		h["cantidad"] = int(h["cantidad"]) - 1
	equipo[sitio] = id
	inventario_cambiado.emit()
	equipo_cambiado.emit()
	mensaje.emit("Equipas %s." % Datos.nombre_objeto(id))
	return true


func desequipar(sitio: String) -> bool:
	var id := str(equipo.get(sitio, ""))
	if id.is_empty():
		return false
	if _poner(id, 1) != 0:
		mensaje.emit("Haz sitio en el inventario para quitarte la pieza.")
		return false
	equipo.erase(sitio)
	inventario_cambiado.emit()
	equipo_cambiado.emit()
	return true


func defensa_equipo() -> float:
	var defensa := 0.0
	for sitio: String in ["casco", "peto", "botas"]:
		defensa += float(Datos.objeto(str(equipo.get(sitio, ""))).get("defensa", 0))
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


## Se come un objeto del inventario: recupera energía y salud.
func comer(id: String) -> bool:
	var o := Datos.objeto(id)
	if o.is_empty() or o.get("tipo", "") != "comida" or _desmayo_pendiente:
		return false
	if energia >= energia_max - 0.01 and vida >= vida_max - 0.01:
		mensaje.emit("No tienes hambre ahora mismo.")
		return false
	if not quitar_objeto(id, 1):
		return false
	var e: float = float(o.get("energia", 0))
	recuperar_energia(e)
	var salud_anterior := vida
	curar_vida(e * 0.5)
	var salud_curada := roundi(vida - salud_anterior)
	var texto_salud := " y %d de salud" % salud_curada if salud_curada > 0 else ""
	mensaje.emit("%s: recuperas %d de energía%s." % [Datos.nombre_objeto(id), int(e), texto_salud])
	return true


# --- Vecinos y herramientas -----------------------------------------------------------

func subir_amistad(npc: String, n: int) -> void:
	var antes := int(amistad.get(npc, 0))
	amistad[npc] = clampi(antes + n, 0, AMISTAD_MAX)
	if nivel_amistad(npc) > _nivel_de(antes):
		mensaje.emit("%s te tiene más confianza." % str(Datos.npc(npc).get("nombre", npc)))
	if n != 0:
		amistad_cambiada.emit(npc, n)


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
			inventario[i] = cargado_h
	var pos: Variant = d.get("posicion", [])
	posicion_guardada = pos if pos is Array and (pos as Array).size() == 3 else []
	banderas.erase("_posicion_guardada")
	_acumulado = 0.0
	_aviso_cansancio = false
	partida_activa = true
	actualizar_entorno_shader()
	_emitir_todo()
	partida_cambiada.emit()
	evento_cambiado.emit()
	return true


func _diccionario(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
