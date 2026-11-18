extends Node
## Tutorial progresivo (autoload «Tutorial»): avisos breves no bloqueantes en orden según el progreso,
## con la tecla o botón del mando actual, persistentes en la partida y desactivables en Ajustes.

signal actualizado

const CLAVE_BANDERA := "tutorial"
const PAUSA_TRAS_CIERRE := 1.2
const DISTANCIA_MOVER := 1.4
const ORDEN_DIA1: Array[String] = ["mover", "labrar", "sembrar", "regar", "dormir"]

var _actual: String = ""
var _cola: Array[String] = []
var _enfriamiento: float = 0.0
var _pos_ant: Vector3 = Vector3.ZERO
var _tiene_pos_ant: bool = false
var _distancia_movida: float = 0.0
var _ultimo_mapa: String = ""
var _rocas_mina_previas: int = 0
var _dinero_ganado_previo: int = 0
var _dia_cerrado_auto: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Juego.partida_cambiada.connect(_al_cambiar_partida)
	Juego.dia_nuevo.connect(_al_dia_nuevo)
	Juego.dinero_cambiado.connect(_al_dinero_cambiado)
	Juego.inventario_cambiado.connect(_al_inventario_cambiado)
	Juego.amistad_cambiada.connect(_al_amistad_cambiada)
	Juego.hora_cambiada.connect(_al_hora_cambiada)
	Escenas.mapa_cargado.connect(_al_mapa_cargado)
	Cultivos.accion_visual.connect(_al_cultivo_accion)
	Cultivos.parcela_cambiada.connect(_al_parcela_cambiada)
	Ajustes.cambiado.connect(_al_ajuste_cambiado)


func _process(delta: float) -> void:
	if not Juego.partida_activa:
		return
	if not activo_en_ajustes():
		if not _actual.is_empty():
			_actual = ""
			actualizado.emit()
		return
	if _enfriamiento > 0.0 and not Interfaz.ocupada() and not Escenas.en_transicion:
		_enfriamiento = maxf(_enfriamiento - delta, 0.0)
		if _enfriamiento <= 0.0:
			_evaluar_progreso()

	if _actual.is_empty() and _enfriamiento <= 0.0 and _puede_mostrar_ahora():
		_siguiente_de_cola_o_dia1()

	_comprobar_movimiento_leo()
	_comprobar_regalos_y_minas_pendientes()


# --- API pública ---------------------------------------------------------------------

func activo_en_ajustes() -> bool:
	return bool(Ajustes.valores.get("tutorial", true))


func hay_aviso_activo() -> bool:
	return activo_en_ajustes() and not _actual.is_empty()


func actual() -> String:
	return _actual if activo_en_ajustes() else ""


## Devuelve {"id", "titulo", "texto", "cerrar"} del aviso actual, o {} si no hay ninguno visible.
func contenido_actual() -> Dictionary:
	if not hay_aviso_activo():
		return {}
	return contenido_de(_actual)


## Devuelve todos los textos formateados con las teclas o botones del dispositivo actual.
func contenido_de(id: String) -> Dictionary:
	var mando := Ajustes.ultimo_mando
	var cerrar := "%s · Cerrar" % Ajustes.pista("cerrar_tutorial")
	var titulo := ""
	var texto := ""
	match id:
		"mover":
			titulo = "1/5 · Moverse"
			if mando:
				texto = "Muévete con la palanca izquierda (púlsala para correr), mira con la derecha y cambia de vista con la cruceta arriba."
			else:
				texto = "Muévete con %s (mantén %s para correr), mira con el ratón y cambia de vista con %s." % [_pista_movimiento(), Ajustes.pista("correr"), Ajustes.pista("alternar_vista")]
		"labrar":
			titulo = "2/5 · Labrar"
			texto = "Elige la azada (%s), apunta a la tierra limpia y úsala (%s) para abrir un bancal." % [_pista_ranura(1), Ajustes.pista("usar")]
		"sembrar":
			titulo = "3/5 · Sembrar"
			texto = "Selecciona las semillas de patata (%s) y plántalas (%s) en la tierra labrada." % [_pista_ranura(6), Ajustes.pista("usar")]
		"regar":
			titulo = "4/5 · Regar"
			texto = "Equipa la regadera (%s) y riega (%s) lo sembrado; sin riego diario los cultivos no crecen." % [_pista_ranura(2), Ajustes.pista("usar")]
		"dormir":
			titulo = "5/5 · Dormir"
			texto = "Al terminar el día, entra en la cabaña e interactúa (%s) con la cama para dormir hasta mañana." % Ajustes.pista("interactuar")
		"vender":
			titulo = "Cosecha y venta"
			texto = "¡Primera cosecha! Lleva lo recogido al pueblo e interactúa (%s) con Don Mateo para venderlo en la tienda." % Ajustes.pista("interactuar")
		"pueblo":
			titulo = "Villaverde de los Rosales"
			texto = "En el pueblo puedes hablar (%s) con los vecinos para hacer amistad y entrar en la tienda de Don Mateo." % Ajustes.pista("interactuar")
		"regalos":
			titulo = "Hacer regalos"
			texto = "Has ganado tu primera amistad. Elige un objeto (%s o barra rápida) e interactúa (%s) con un vecino para regalárselo." % [Ajustes.pista("inventario"), Ajustes.pista("interactuar")]
		"mina":
			titulo = "La mina"
			texto = "Equipa el pico (%s), apunta a la roca y golpéala (%s). Para salir, sigue los raíles hacia la entrada." % [_pista_ranura(5), Ajustes.pista("usar")]
		"combate":
			titulo = "Primer combate"
			texto = "Golpea con %s. Encadena tres toques o mantén para cargar. %s alza la guardia. Púlsalo justo antes del golpe para pararlo. %s esquiva y %s fija la criatura." % [
				Ajustes.pista("usar"), Ajustes.pista("bloquear"), Ajustes.pista("esquivar"), Ajustes.pista("fijar_objetivo")]
		"mejoras":
			titulo = "Mejorar herramientas"
			texto = "Tienes dinero suficiente para mejorar herramientas: habla (%s) con Clara en el pueblo y tráele mineral de la mina." % Ajustes.pista("interactuar")
	return {"id": id, "titulo": titulo, "texto": texto, "cerrar": cerrar}


## Cierra el aviso actual manualmente con la tecla o botón; queda marcado como visto y no vuelve a salir.
func cerrar_actual() -> void:
	if _actual.is_empty():
		return
	var id := _actual
	_marcar_visto(id)
	_actual = ""
	_enfriamiento = PAUSA_TRAS_CIERRE
	Audio.reproducir("ui_boton")
	actualizado.emit()


## Devuelve una copia de los avisos ya vistos.
func vistos() -> Dictionary:
	return (_datos()["vistos"] as Dictionary).duplicate()


## Devuelve los IDs en el orden cronológico exacto en que aparecieron al jugador en esta partida.
func orden_mostrado() -> Array[String]:
	var r: Array[String] = []
	for item: Variant in _datos()["orden"]:
		r.append(str(item))
	return r


func esta_visto(id: String) -> bool:
	return bool((_datos()["vistos"] as Dictionary).get(id, false))


func esta_hecho(id: String) -> bool:
	return bool((_datos()["hechos"] as Dictionary).get(id, false))


## Reevaluación explícita del estado actual (p. ej. tras activar la bandera de mina abierta).
func evaluar() -> void:
	_evaluar_progreso()


# --- Persistencia en Juego.banderas["tutorial"] -------------------------------------

func _datos() -> Dictionary:
	var d: Variant = Juego.banderas.get(CLAVE_BANDERA, {})
	if not (d is Dictionary):
		d = {}
	var dict := d as Dictionary
	if not (dict.get("vistos") is Dictionary):
		dict["vistos"] = {}
	if not (dict.get("hechos") is Dictionary):
		dict["hechos"] = {}
	if not (dict.get("orden") is Array):
		dict["orden"] = []
	Juego.banderas[CLAVE_BANDERA] = dict
	return dict


func _marcar_visto(id: String) -> void:
	var d := _datos()
	var v: Dictionary = d["vistos"]
	if not bool(v.get(id, false)):
		v[id] = true
		var ord: Array = d["orden"]
		if not ord.has(id):
			ord.append(id)


func _marcar_hecho(id: String) -> void:
	var d := _datos()
	(d["hechos"] as Dictionary)[id] = true


# --- Cola y activación ----------------------------------------------------------------

func avisar_combate() -> void:
	if _actual == "mina" and not esta_visto("combate"):
		_actual = ""
	_encolar("combate", true)


func _puede_mostrar_ahora() -> bool:
	return Juego.partida_activa and activo_en_ajustes() and Interfaz.hud_visible() and Escenas.jugador() != null and not Escenas.en_transicion and not Interfaz.ocupada()


func _encolar(id: String, prioritario: bool = false) -> void:
	if id.is_empty() or not activo_en_ajustes() or esta_visto(id):
		return
	if _actual == id or _cola.has(id):
		return
	if prioritario:
		_cola.push_front(id)
	else:
		_cola.append(id)
	if _actual.is_empty() and _enfriamiento <= 0.0 and _puede_mostrar_ahora():
		_mostrar_siguiente()


func _mostrar_siguiente() -> void:
	if not _puede_mostrar_ahora() or _enfriamiento > 0.0:
		return
	while not _cola.is_empty():
		var cand: String = str(_cola.pop_front())
		if not esta_visto(cand) and _es_valido_ahora(cand):
			_actual = cand
			_marcar_visto(cand)
			actualizado.emit()
			return


func _completar(id: String, esperar_en_cierre: bool = false) -> void:
	_marcar_hecho(id)
	_cola.erase(id)
	if _actual == id:
		_marcar_visto(id)
		_actual = ""
		if esperar_en_cierre:
			_enfriamiento = PAUSA_TRAS_CIERRE
		actualizado.emit()
		_evaluar_progreso()


func _es_valido_ahora(id: String) -> bool:
	if id in ["mover", "labrar", "sembrar", "regar"]:
		return Juego.dia == 1 and Juego.estacion == 0 and Juego.anio == 1 and Juego.mapa_actual == "granja"
	if id == "dormir":
		return (Juego.dia == 1 and Juego.estacion == 0 and Juego.anio == 1) and (Juego.mapa_actual == "granja" or Juego.mapa_actual == "casa_leo")
	return true


func _siguiente_de_cola_o_dia1() -> void:
	if not _cola.is_empty():
		_mostrar_siguiente()
		return
	_evaluar_dia1()


func _evaluar_progreso() -> void:
	if not Juego.partida_activa or not activo_en_ajustes():
		return
	_evaluar_dia1()
	_evaluar_hitostemporal()
	_evaluar_mejoras()
	if _actual.is_empty() and _enfriamiento <= 0.0 and not _cola.is_empty():
		_mostrar_siguiente()


func _evaluar_dia1() -> void:
	if Juego.dia != 1 or Juego.estacion != 0 or Juego.anio != 1:
		return
	if Juego.mapa_actual != "granja" and Juego.mapa_actual != "casa_leo":
		return
	for paso: String in ORDEN_DIA1:
		if not _es_valido_ahora(paso):
			continue
		if not esta_visto(paso):
			_encolar(paso)
			return
		# Mientras el paso anterior de la secuencia siga activo y sin completar/cerrar, no adelantar al siguiente.
		if _actual == paso:
			return


func _evaluar_hitostemporal() -> void:
	if Juego.mapa_actual == "pueblo" and not esta_visto("pueblo") and not esta_hecho("pueblo"):
		_encolar("pueblo")
	if int(Juego.estadisticas.get("cosechas", 0)) > 0 and not esta_visto("vender") and not esta_hecho("vender"):
		_encolar("vender")
	if _hay_amistad_positiva() and not esta_visto("regalos") and not esta_hecho("regalos"):
		_encolar("regalos")
	if Juego.mapa_actual == "mina_interior" or (Juego.mapa_actual == "mina_exterior" and bool(Juego.banderas.get("mina_abierta", false))):
		if not esta_visto("mina") and not esta_hecho("mina"):
			_encolar("mina")


func _evaluar_mejoras() -> void:
	if esta_visto("mejoras") or esta_hecho("mejoras"):
		return
	if _tiene_herramienta_mejorada():
		_marcar_hecho("mejoras")
		return
	var minimo := _dinero_minimo_mejora()
	if minimo <= 0 or Juego.dinero < minimo:
		return
	var con_progreso := int(Juego.estadisticas.get("dinero_ganado", 0)) > 0 \
		or Juego.dia > 1 or Juego.estacion > 0 or Juego.anio > 1 \
		or _tiene_algun_mineral() \
		or (esta_visto("pueblo") and esta_visto("mina"))
	if con_progreso:
		_encolar("mejoras")


# --- Listeners del juego --------------------------------------------------------------

func _al_cambiar_partida() -> void:
	_actual = ""
	_cola.clear()
	_enfriamiento = 0.0
	_distancia_movida = 0.0
	_tiene_pos_ant = false
	_ultimo_mapa = Juego.mapa_actual
	_rocas_mina_previas = _contar_rocas_rotas_mina()
	_dinero_ganado_previo = int(Juego.estadisticas.get("dinero_ganado", 0))
	_dia_cerrado_auto = false
	actualizado.emit()
	_evaluar_progreso.call_deferred()


func _al_mapa_cargado(id: String) -> void:
	_tiene_pos_ant = false
	if id != _ultimo_mapa:
		_enfriamiento = 0.0
	if _ultimo_mapa == "mina_interior" and id != "mina_interior" and esta_visto("mina"):
		_completar("mina")
	_ultimo_mapa = id
	if _actual in ["mover", "labrar", "sembrar", "regar"] and id != "granja":
		_actual = ""
	if _actual == "pueblo" and id in ["granja", "casa_leo", "mina_exterior", "mina_interior"]:
		_actual = ""
	if _actual == "dormir" and id in ["pueblo", "mina_exterior", "mina_interior"]:
		_actual = ""
	if id == "pueblo" and not esta_visto("pueblo") and not esta_hecho("pueblo"):
		_encolar("pueblo", true)
	elif (id == "mina_interior" or (id == "mina_exterior" and bool(Juego.banderas.get("mina_abierta", false)))) and not esta_visto("mina") and not esta_hecho("mina"):
		_encolar("mina", true)
	elif id == "casa_leo" and Juego.dia == 1 and esta_visto("regar") and not esta_visto("dormir"):
		_encolar("dormir", true)
	_evaluar_progreso()
	actualizado.emit()


func _al_cultivo_accion(tipo: String, _clave: String) -> void:
	match tipo:
		"labrar":
			_completar("labrar")
		"regar":
			_completar("regar")
		"cosechar":
			if not esta_visto("vender") and not esta_hecho("vender"):
				_encolar("vender")


func _al_parcela_cambiada(clave: String) -> void:
	var c := Cultivos.parcela(clave)
	if str(c.get("cultivo", "")) != "":
		_completar("sembrar")


func _al_dia_nuevo() -> void:
	_completar("dormir")
	_evaluar_progreso()


func _al_dinero_cambiado(_dinero: int) -> void:
	var ganado_ahora := int(Juego.estadisticas.get("dinero_ganado", 0))
	if ganado_ahora > _dinero_ganado_previo:
		_dinero_ganado_previo = ganado_ahora
		if Interfaz.get("_tienda") != null and bool(Interfaz.get("_tienda").visible) and esta_visto("vender"):
			_completar("vender")
	_evaluar_mejoras()


func _al_inventario_cambiado() -> void:
	if _tiene_herramienta_mejorada():
		_completar("mejoras")
	_evaluar_mejoras()


func _al_amistad_cambiada(_npc: String, puntos: int) -> void:
	if puntos > 0:
		if _actual == "pueblo":
			_completar("pueblo")
		if not esta_visto("regalos") and not esta_hecho("regalos"):
			_encolar("regalos")


func _al_hora_cambiada(minutos: int) -> void:
	if Juego.dia == 1 and Juego.estacion == 0 and Juego.anio == 1 and minutos >= 1200:
		if esta_visto("mover") and not esta_visto("dormir") and not esta_hecho("dormir") and not _dia_cerrado_auto:
			_dia_cerrado_auto = true
			_encolar("dormir")


func _al_ajuste_cambiado(clave: String) -> void:
	if clave.is_empty() or clave == "tutorial":
		if not activo_en_ajustes():
			_actual = ""
		else:
			_evaluar_progreso()
	actualizado.emit()


func _comprobar_movimiento_leo() -> void:
	if esta_hecho("mover") or Juego.mapa_actual != "granja" or Interfaz.ocupada():
		return
	var j := Escenas.jugador()
	if j == null:
		return
	var pos := j.global_position
	if not _tiene_pos_ant:
		_pos_ant = pos
		_tiene_pos_ant = true
		return
	var salto := Vector2(pos.x - _pos_ant.x, pos.z - _pos_ant.z).length()
	_pos_ant = pos
	if salto > 0.005 and salto < 2.0:
		_distancia_movida += salto
	if _distancia_movida >= DISTANCIA_MOVER:
		_completar("mover")


func _comprobar_regalos_y_minas_pendientes() -> void:
	if not esta_hecho("regalos"):
		for k: Variant in Juego.hablado_hoy:
			if str(k).begins_with("regalo_"):
				_completar("regalos")
				break
	if Juego.mapa_actual == "mina_interior":
		var rotas := _contar_rocas_rotas_mina()
		if rotas > _rocas_mina_previas:
			_rocas_mina_previas = rotas
			_completar("mina")
	if esta_visto("pueblo") and not esta_hecho("pueblo"):
		var tienda: Node = Interfaz.get("_tienda")
		if tienda != null and bool(tienda.get("visible")):
			_completar("pueblo")


# --- Helpers de estado y formato -----------------------------------------------------

func _hay_amistad_positiva() -> bool:
	for k: Variant in Juego.amistad:
		if int(Juego.amistad[k]) > 0:
			return true
	return false


func _tiene_algun_mineral() -> bool:
	for id: String in ["cobre", "hierro", "cuarzo"]:
		if Juego.cantidad(id) > 0:
			return true
	return false


func _tiene_herramienta_mejorada() -> bool:
	for h: String in Servicios.HERRAMIENTAS:
		if Juego.nivel(h) > 0:
			return true
	return false


func _dinero_minimo_mejora() -> int:
	var min_dinero := -1
	for h: String in Servicios.HERRAMIENTAS:
		var m := Servicios.siguiente_mejora(h)
		if m.is_empty():
			continue
		var d := int(m.get("dinero", 0))
		if d > 0 and (min_dinero < 0 or d < min_dinero):
			min_dinero = d
	return min_dinero


func _contar_rocas_rotas_mina() -> int:
	var m: Variant = Juego.estado_mapas.get("mina_interior", {})
	if m is Dictionary:
		var rotas: Variant = (m as Dictionary).get("rotas", [])
		if rotas is Array:
			return (rotas as Array).size()
	return 0


func _pista_movimiento() -> String:
	var arriba := Ajustes.pista("mover_arriba")
	var izq := Ajustes.pista("mover_izquierda")
	var abajo := Ajustes.pista("mover_abajo")
	var der := Ajustes.pista("mover_derecha")
	if arriba == "W" and izq == "A" and abajo == "S" and der == "D":
		return "WASD o flechas"
	return "%s / %s / %s / %s" % [arriba, izq, abajo, der]


func _pista_ranura(n: int) -> String:
	if Ajustes.ultimo_mando:
		return "cruceta ◄ ►"
	return Ajustes.pista("ranura_%d" % n)


