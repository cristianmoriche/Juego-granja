class_name CombateJugador
extends RefCounted
## Entrada, ventanas de contacto y defensa. El movimiento y la cámara los aplica Jugador.

signal objetivo_cambiado(objetivo: Enemigo)

const TIEMPO_CARGA := 0.38
const TIEMPO_PARADA := 0.20
const ALCANCE_FIJAR := 11.0
const DURACION_ESQUIVA := 0.36
const DISTANCIA_ESQUIVA := 1.42
const MASCARA_OBSTACULOS := 1 | 16 | 32 | 64 | 128
const MASCARA_CONTACTO := MASCARA_OBSTACULOS | 8
const EXTENSION_BRAZO := 0.18
const PASO_BARRIDO := 0.045
const PICO := {"dano": 14.0, "alcance": 1.62, "ciclo": 0.61, "coste": 10.0}
const HACHA := {"dano": 12.0, "alcance": 1.52, "ciclo": 0.56, "coste": 10.0}

var leo: Jugador
var objetivo_fijado: Enemigo
var objetivo_mostrado: Enemigo
var _indicaba_fijado := false
var bloqueando := false
var apuntando_arco := false
var tension_arco := 0.0
var _arco_temblor := 0.0
var _cadencia_arco := 0.0
var combo := 0
var cargado := false
var tiempo_esquiva := 0.0
var direccion_esquiva := Vector3.ZERO
var retroceso := Vector3.ZERO
var _seleccion := ""
var _t_carga := -1.0
var _t_guardia := 0.0
var _guardia_agotada := false
var _t_golpe := 0.0
var _ciclo := 0.0
var _arma: Dictionary = {}
var _siguiente := false
var _margen_combo := 0.0
var _dir_golpe := Vector3.FORWARD
var _eje_contacto := Vector3.FORWARD
var _golpeados: Dictionary = {}
var _pausa_impacto := 0.0
var _t_reaccion := 0.0
var _t_buscar := 0.0


func _init(jugador: Jugador) -> void:
	leo = jugador


func ocupado() -> bool:
	return _ciclo > 0.0 or tiempo_esquiva > 0.0 or _t_reaccion > 0.0


func pausa_de_impacto() -> bool:
	return _pausa_impacto > 0.0


func _arma_activa(id: String) -> Dictionary:
	var obj := Datos.objeto(id)
	if obj.get("tipo") == "arma":
		return obj
	if id in ["pico", "hacha"]:
		var herramienta := (PICO if id == "pico" else HACHA).duplicate()
		herramienta["dano"] += mini(Juego.nivel(id), 3) * 5.0
		return herramienta
	return {}


func es_arco_activo() -> bool:
	var id := str(Juego.objeto_activo().get("id", ""))
	return str(Datos.objeto(id).get("subtipo", "")) == "arco"


func preparar_ataque(id: String, colision: Node) -> bool:
	var arma := _arma_activa(id)
	if arma.is_empty() or (Datos.objeto(id).get("tipo") != "arma" and not (colision is Enemigo or is_instance_valid(objetivo_fijado))):
		return false
	if tiempo_esquiva > 0.0 or _t_reaccion > 0.0 or bloqueando or Juego.vida <= 0.0:
		return true
	if str(arma.get("subtipo", "")) == "arco":
		if _cadencia_arco > 0.0:
			return true
		if Juego.total_flechas() <= 0:
			Interfaz.mensaje("No te quedan flechas para el arco.")
			Audio.reproducir("ui_error")
			return true
		_seleccion = id
		_t_carga = 0.0
		tension_arco = 0.0
		Audio.reproducir("arco_tensar")
		return true
	_seleccion = id
	_t_carga = 0.0
	return true


func soltar_ataque() -> bool:
	if _t_carga < 0.0:
		return false
	var espera := _t_carga
	_t_carga = -1.0
	if str(Datos.objeto(_seleccion).get("subtipo", "")) == "arco":
		_disparar_flecha(espera)
		return true
	if _ciclo > 0.0:
		_siguiente = not cargado and combo < 3
	elif not ocupado() and not bloqueando:
		_iniciar_golpe(espera >= TIEMPO_CARGA)
	return true


func _disparar_flecha(_espera: float) -> Flecha:
	var t_ten := clampf(tension_arco, 0.16, 1.0)
	var temblor := _arco_temblor
	tension_arco = 0.0
	_arco_temblor = 0.0
	var arma := _arma_activa(_seleccion)
	if arma.is_empty() or Juego.objeto_activo().get("id", "") != _seleccion:
		return null
	var id_flecha := Juego.municion_disponible()
	if id_flecha.is_empty():
		return null
	if not Juego.gastar_resistencia(float(arma.get("coste", 7.0))):
		return null
	if not Juego.quitar_objeto(id_flecha, 1):
		return null

	_cadencia_arco = 0.25
	var origen := leo.punto_salida_flecha()
	var mira := leo.camara.direccion_mira()
	var ojo := leo.camara.camara.global_position
	var toque := leo.camara.rayo_central(MASCARA_CONTACTO, 72.0)
	var blanco: Vector3 = toque.get("position", ojo + mira * 46.0)
	var dir_tiro := (blanco - origen).normalized()
	if dir_tiro.dot(mira) < 0.1:
		dir_tiro = mira

	var disp := (0.002 if apuntando_arco else 0.016) + temblor
	dir_tiro = (dir_tiro + Vector3(randf_range(-disp, disp), randf_range(-disp, disp), randf_range(-disp, disp))).normalized()

	var vel_esc := lerpf(19.0, 39.0, t_ten) * float(Datos.objeto(id_flecha).get("velocidad", 1.0))
	if _seleccion == "arco_cristal":
		vel_esc *= 1.15
	var dano_tiro := float(arma["dano"]) * lerpf(0.48, 1.62, t_ten) * (1.0 + Juego.bono_dano_combate())

	var flecha := Flecha.new()
	var mapa_n := leo.get_tree().get_first_node_in_group("mapa")
	var padre: Node = mapa_n if mapa_n != null else leo.get_parent()
	padre.add_child(flecha)
	var rids: Array[RID] = [leo.get_rid()]
	flecha.configurar(origen, dir_tiro * vel_esc, id_flecha, dano_tiro, rids)
	Audio.reproducir("arco_soltar")
	Audio.reproducir("flecha_aire")
	leo.camara.sacudir(0.016, 0.09)
	return flecha


func _iniciar_golpe(fuerte: bool) -> void:
	var arma := _arma_activa(_seleccion)
	if arma.is_empty() or Juego.objeto_activo().get("id", "") != _seleccion:
		return
	var coste := float(arma["coste"]) * (1.65 if fuerte else 1.0)
	if not Juego.gastar_resistencia(coste):
		return
	_arma = arma
	cargado = fuerte
	combo = 1 if fuerte or _margen_combo <= 0.0 or combo >= 3 else combo + 1
	_ciclo = float(arma["ciclo"]) * (1.54 if fuerte else [1.0, 1.03, 1.16][combo - 1])
	_t_golpe = 0.0
	_margen_combo = 0.0
	_golpeados.clear()
	_dir_golpe = _frente()
	leo.direccion = _dir_golpe
	var clip := "combate_cargado" if fuerte else "combate_golpe_%d" % combo
	if _seleccion in ["pico", "hacha"]:
		clip = leo._animacion_de_herramienta(_seleccion)
	leo.animar_combate(clip, _ciclo)
	Audio.reproducir("combate_aire_fuerte" if fuerte else "combate_aire")


func cambiar_objetivo() -> void:
	if is_instance_valid(objetivo_fijado):
		objetivo_fijado = null
		_t_buscar = 0.0
		return
	objetivo_fijado = _enemigo_en_mira(ALCANCE_FIJAR)
	if objetivo_fijado == null:
		# En la órbita la mira puede quedar encima de las criaturas bajas.
		var mejor := 0.86
		var frente := leo.camara.direccion_mira()
		var origen := leo.camara.camara.global_position
		for enemigo: Enemigo in leo.get_tree().get_nodes_in_group("enemigos"):
			if not _fijable(enemigo):
				continue
			var producto := frente.dot((enemigo.centro_impacto() - origen).normalized())
			if producto > mejor:
				mejor = producto
				objetivo_fijado = enemigo
	_t_buscar = 0.0


func _enemigo_en_mira(alcance: float) -> Enemigo:
	var cam := leo.camara
	var extra := cam.camara.global_position.distance_to(leo.global_position)
	var rayo := cam.rayo_central(MASCARA_CONTACTO, alcance + extra)
	var enemigo := rayo.get("collider") as Enemigo
	if not _fijable(enemigo) or leo.global_position.distance_to(enemigo.centro_impacto()) > alcance:
		return null
	return enemigo


func _fijable(enemigo: Enemigo) -> bool:
	return is_instance_valid(enemigo) and enemigo.apuntable() \
		and leo.global_position.distance_squared_to(enemigo.global_position) <= ALCANCE_FIJAR * ALCANCE_FIJAR \
		and _visible(enemigo.centro_impacto())


func _visible(punto: Vector3) -> bool:
	return leo.camara.rayo_entre(leo.global_position + Vector3.UP * 1.16, punto, MASCARA_OBSTACULOS).is_empty()


func _frente() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, leo.camara.yaw)


func esquivar(entrada: Vector2) -> void:
	if not leo.is_on_floor() or leo.agachado or Juego.vida <= 0.0 or ocupado():
		return
	if not Juego.gastar_resistencia(23.0):
		return
	bloqueando = false
	_t_carga = -1.0
	_margen_combo = 0.0
	direccion_esquiva = -_frente() if entrada.is_zero_approx() else Vector3(entrada.x, 0, entrada.y).rotated(Vector3.UP, leo.camara.yaw).normalized()
	var atras := direccion_esquiva.dot(_frente()) < -0.58
	leo.direccion = -direccion_esquiva if atras else direccion_esquiva
	tiempo_esquiva = DURACION_ESQUIVA
	leo.animar_combate("combate_esquiva_atras" if atras else "combate_esquiva", DURACION_ESQUIVA)
	Audio.reproducir("combate_esquiva")


func velocidad_esquiva() -> Vector3:
	var avance := 1.0 - tiempo_esquiva / DURACION_ESQUIVA
	return direccion_esquiva * ((1.0 - 0.72 * cos(TAU * avance)) * DISTANCIA_ESQUIVA / DURACION_ESQUIVA)


func invulnerable() -> bool:
	var transcurrido := DURACION_ESQUIVA - tiempo_esquiva
	return tiempo_esquiva > 0.0 and transcurrido >= 0.035 and transcurrido <= 0.22


func recibir_ataque(cantidad: float, atacante: Enemigo, origen: Vector3, admite_parada: bool) -> void:
	if cantidad <= 0.0 or Juego.vida <= 0.0 or invulnerable() or Escenas.en_transicion:
		return
	var desde := (origen - leo.global_position).slide(Vector3.UP).normalized()
	var delante := _frente().dot(desde) >= 0.28
	if bloqueando and delante:
		if admite_parada and _t_guardia <= TIEMPO_PARADA and Juego.gastar_resistencia(6.0):
			if is_instance_valid(atacante):
				atacante.desequilibrar(0.95)
			Juego.ganar_xp_habilidad("combate", 12)
			Audio.reproducir("combate_parada")
			leo.animar_combate("combate_parada", 0.25)
			leo.camara.sacudir(0.025, 0.13)
			_t_guardia = TIEMPO_PARADA + 0.01
			return
		var escudo := Datos.objeto(str(Juego.equipo.get("escudo", "")))
		var coste := cantidad * (0.68 if escudo.is_empty() else 0.49) + 3.0
		if Juego.gastar_resistencia(coste):
			cantidad *= 1.0 - float(escudo.get("reduccion", 0.42))
			Audio.reproducir("combate_bloqueo")
			_restar_salud(cantidad)
			leo.camara.sacudir(0.022, 0.12)
			return
		Juego.agotar_resistencia()
		bloqueando = false
		_guardia_agotada = true
	_cancelar_ataque()
	retroceso = -desde * 2.65
	_restar_salud(cantidad)
	if Juego.vida > 0.0:
		_t_reaccion = 0.29
		leo.animar_combate("combate_dolor", _t_reaccion)
	leo.camara.sacudir(0.043, 0.18)


func _restar_salud(cantidad: float) -> void:
	var defensa := Juego.bono_defensa_total()
	Juego.recibir_dano(cantidad * 45.0 / (45.0 + defensa))


func _cancelar_ataque() -> void:
	_ciclo = 0.0
	_t_carga = -1.0
	_siguiente = false
	_margen_combo = 0.0


func actualizar(delta: float, libre: bool, guardia_pulsada: bool) -> void:
	_cadencia_arco = maxf(0.0, _cadencia_arco - delta)
	if not libre:
		_cancelar_ataque()
		bloqueando = false
		apuntando_arco = false
		leo.camara.apuntando_arco = false
		tension_arco = 0.0
		_arco_temblor = 0.0
		tiempo_esquiva = 0.0
		retroceso = Vector3.ZERO
		_pausa_impacto = 0.0
		_mostrar_objetivo(null)
		return
	apuntando_arco = es_arco_activo() and guardia_pulsada and _t_reaccion <= 0.0
	leo.camara.apuntando_arco = apuntando_arco
	_t_reaccion = maxf(0.0, _t_reaccion - delta)
	retroceso = retroceso.move_toward(Vector3.ZERO, 13.0 * delta)
	tiempo_esquiva = maxf(0.0, tiempo_esquiva - delta)
	_margen_combo = maxf(0.0, _margen_combo - delta)
	_actualizar_objetivo(delta)
	if _pausa_impacto > 0.0:
		_pausa_impacto = maxf(0.0, _pausa_impacto - delta)
		return
	if _t_carga >= 0.0:
		if _seleccion != Juego.objeto_activo().get("id", ""):
			_t_carga = -1.0
			tension_arco = 0.0
			_arco_temblor = 0.0
		else:
			_t_carga += delta
			if str(Datos.objeto(_seleccion).get("subtipo", "")) == "arco":
				var carcaj_id := str(Juego.equipo.get("carcaj", ""))
				var vel_c := 1.0 + (float(Datos.objeto(carcaj_id).get("velocidad_carga", 0.0)) if not carcaj_id.is_empty() else 0.0)
				tension_arco = clampf(_t_carga / (0.78 / vel_c), 0.0, 1.0)
				leo.direccion = _frente()
				if _t_carga > 2.2:
					_arco_temblor = clampf((_t_carga - 2.2) * 0.025, 0.0, 0.035)
					if not Juego.gastar_resistencia(6.5 * delta):
						soltar_ataque()
			elif _ciclo <= 0.0 and _t_carga >= TIEMPO_CARGA:
				soltar_ataque()
	else:
		tension_arco = 0.0
		_arco_temblor = 0.0
	_actualizar_guardia(delta, guardia_pulsada and _t_carga < 0.0)
	if _ciclo > 0.0 and _seleccion != Juego.objeto_activo().get("id", ""):
		_cancelar_ataque()
	if _ciclo <= 0.0:
		return
	var previo := _t_golpe / _ciclo
	_t_golpe += delta
	var progreso := _t_golpe / _ciclo
	var inicio := 0.53 if cargado else 0.37
	var fin := 0.68 if cargado else 0.56
	if progreso >= inicio and previo < fin:
		var desde := inverse_lerp(inicio, fin, maxf(inicio, previo))
		var hasta := inverse_lerp(inicio, fin, minf(fin, progreso))
		_contacto(desde, hasta, previo < inicio)
	if progreso >= 1.0:
		_ciclo = 0.0
		_margen_combo = 0.26 if not cargado and combo < 3 else 0.0
		if _siguiente:
			_siguiente = false
			_iniciar_golpe(false)


func _actualizar_guardia(delta: float, pulsada: bool) -> void:
	if es_arco_activo():
		bloqueando = false
		if apuntando_arco:
			leo.direccion = _frente()
		return
	if not pulsada:
		_guardia_agotada = false
	if not pulsada or ocupado() or _guardia_agotada:
		bloqueando = false
		return
	var id := str(Juego.objeto_activo().get("id", ""))
	if not Juego.equipo.has("escudo") and _arma_activa(id).is_empty():
		bloqueando = false
		return
	if not Juego.gastar_resistencia(2.0 * delta):
		bloqueando = false
		_guardia_agotada = true
		return
	if not bloqueando:
		_t_guardia = 0.0
		leo.animar_combate("combate_guardia", 0.0)
	bloqueando = true
	_t_guardia += delta
	leo.direccion = _frente()


func _actualizar_objetivo(delta: float) -> void:
	_t_buscar -= delta
	if _t_buscar <= 0.0:
		_t_buscar = 0.12
		if leo.get_tree().get_node_count_in_group("enemigos") == 0:
			objetivo_fijado = null
			_mostrar_objetivo(null)
			return
		if not is_instance_valid(objetivo_fijado) or not _fijable(objetivo_fijado):
			objetivo_fijado = null
		_mostrar_objetivo(objetivo_fijado if objetivo_fijado != null else _enemigo_en_mira(7.0))
	if is_instance_valid(objetivo_fijado):
		if not leo.camara.primera_persona:
			leo.camara.seguir_punto(objetivo_fijado.centro_impacto(), delta)
		if not ocupado():
			leo.direccion = (objetivo_fijado.global_position - leo.global_position).slide(Vector3.UP).normalized()


func _mostrar_objetivo(enemigo: Enemigo) -> void:
	var fijado := is_instance_valid(objetivo_fijado) and enemigo == objetivo_fijado
	if objetivo_mostrado != enemigo or fijado != _indicaba_fijado:
		objetivo_mostrado = enemigo
		_indicaba_fijado = fijado
		objetivo_cambiado.emit(enemigo)
		if enemigo != null:
			Tutorial.avisar_combate()


func _eje_desde_mira(origen: Vector3, alcance: float) -> Vector3:
	var cam := leo.camara
	var mira := cam.direccion_mira()
	var ojo := cam.camara.global_position
	# La órbita apunta desde detrás de Leo. El golpe sale del cuerpo y converge hacia la mira.
	var profundidad := maxf(0.0, (origen - ojo).dot(mira))
	var distancia := profundidad + alcance
	var toque := cam.rayo_central(MASCARA_CONTACTO, distancia + 0.6)
	var punto: Vector3 = toque.get("position", ojo + mira * distancia)
	var desde_cuerpo := punto - origen
	return desde_cuerpo.normalized() if desde_cuerpo.dot(mira) > 0.01 else mira


func _contacto(desde: float, hasta: float, comienza: bool) -> void:
	var origen := leo.global_position + Vector3.UP * (0.72 if leo.agachado else 1.02)
	var alcance := float(_arma["alcance"]) + EXTENSION_BRAZO + (0.22 if cargado else 0.0)
	if comienza:
		_eje_contacto = _eje_desde_mira(origen, alcance)
	var arco := 0.42 if cargado else 0.54
	if combo == 2:
		arco = -arco
	var primer_angulo := lerpf(-arco, arco, desde)
	var ultimo_angulo := lerpf(-arco, arco, hasta)
	var pasos := maxi(1, ceili(absf(ultimo_angulo - primer_angulo) / PASO_BARRIDO))
	var escala := 1.85 if cargado else float([1.0, 1.12, 1.32][combo - 1])
	var rompe := cargado or bool(_arma.get("rompe_guardia", false))
	var aturde := float(_arma.get("aturde", 0.0)) + (0.29 if cargado else 0.0)
	var impacto := false
	for i in range(0 if comienza else 1, pasos + 1):
		var angulo := lerpf(primer_angulo, ultimo_angulo, float(i) / pasos)
		var direccion := _eje_contacto.rotated(Vector3.UP, angulo)
		var toque := leo.camara.rayo_entre(origen, origen + direccion * alcance, MASCARA_CONTACTO)
		var enemigo := toque.get("collider") as Enemigo
		if enemigo == null or _golpeados.has(enemigo.get_instance_id()):
			continue
		var empuje := (enemigo.global_position - leo.global_position).slide(Vector3.UP).normalized()
		var dano_total := float(_arma["dano"]) * escala * (1.0 + Juego.bono_dano_combate())
		if enemigo.recibir_golpe(dano_total, empuje, rompe, aturde, toque.position):
			_golpeados[enemigo.get_instance_id()] = true
			Juego.ganar_xp_habilidad("combate", 5)
			impacto = true
	if impacto:
		_pausa_impacto = 0.067 if cargado else 0.058
		leo.camara.sacudir(0.039 if cargado else 0.024, 0.14)
