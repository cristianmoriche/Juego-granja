class_name CamaraJuego
extends Node3D
## Cámara de ojos y órbita de hombro. Comparte la dirección de mirada y la cámara del minimapa.
## `pitch` es positivo hacia abajo. `rayo_central` siempre parte de la cámara que dibuja el mundo.
const PITCH_JUEGO := deg_to_rad(20.0)
const PITCH_PRIMERA := deg_to_rad(12.0)
const PITCH_MIN := deg_to_rad(-82.0)
const PITCH_MAX := deg_to_rad(84.0)
const DIST_JUEGO := 3.6
const DIST_MIN := Ajustes.DISTANCIA_TERCERA_MIN
const DIST_MAX := Ajustes.DISTANCIA_TERCERA_MAX
const DIST_MAX_INTERIOR := 3.8
const ALTURA_CERCA := 1.42
const ALTURA_OJOS := 1.63
const SUAVIDAD_ZOOM := 9.0
const SUAVIDAD_VUELTA := 6.0
const RADIO_COLISION := 0.13
const MARGEN_COLISION := 0.04
const DURACION_VISTA := 0.3
const ESPACIO_ALREDEDOR_DE_LEO := 0.56
const DESVIOS_HOMBRO := [35.0, -35.0, 65.0, -65.0, 90.0, -90.0, 125.0, -125.0, 180.0]
const MASCARA_SOLIDA := 1 | 16 | 64 | 128 # Mundo, vecinos, techo, maderas, mobiliario y faroles.

signal vista_actualizada

var yaw: float = 0.0
var pitch: float = PITCH_JUEGO
var distancia: float = DIST_JUEGO
var objetivo: Node3D = null
var ancla_ojos: Node3D
var interlocutor: Node3D
var altura_relativa: float = 1.0
var rapidez: float = 0.0
var aterrizaje: float = 0.0
var camara: Camera3D = null
var interior: bool = false
var distancia_real: float = DIST_JUEGO
var primera_persona: bool = true
var cabeza_oculta: bool = true
var apuntando_arco: bool = false
var _fov_base: float = 70.0

var _dist_obj: float = DIST_JUEGO
var _yaw_juego: float = 0.0
var _volviendo: bool = false
var _excluir: Array[RID] = []
var _consulta_colision := PhysicsShapeQueryParameters3D.new()
var _consulta_rayo := PhysicsRayQueryParameters3D.new()
var _mezcla: float = 0.0
var _fraccion_libre: float = 1.0
var _pivote_seguro := Vector3.INF
var _detalle_ojos := Vector3.ZERO
var _fase_pasos: float = 0.0
var _t_sacudida: float = 0.0
var _dur_sacudida: float = 0.18
var _fuerza_sacudida: float = 0.0
var _fase_sacudida: float = 0.0


func _ready() -> void:
	top_level = true
	process_physics_priority = 10
	add_to_group("camara_juego")
	camara = Camera3D.new()
	camara.name = "Camara"
	camara.near = 0.05
	camara.far = 700.0
	add_child(camara)
	camara.current = true
	var forma := SphereShape3D.new()
	forma.radius = RADIO_COLISION
	_consulta_colision.shape = forma
	_consulta_colision.collision_mask = MASCARA_SOLIDA
	if objetivo is CollisionObject3D:
		_excluir.append((objetivo as CollisionObject3D).get_rid())
	_consulta_colision.exclude = _excluir
	Ajustes.cambiado.connect(_ajustes_cambiados)
	_ajustes_cambiados("")
	_mezcla = 0.0 if primera_persona else 1.0
	pitch = _pitch_inicial()
	_aplicar(0.0)


func _physics_process(delta: float) -> void:
	var reducir: bool = Ajustes.valores.reducir_movimiento
	var destino := 0.0 if primera_persona else 1.0
	_mezcla = destino if reducir else move_toward(_mezcla, destino, delta / DURACION_VISTA)
	distancia = lerpf(distancia, _dist_obj, 1.0 - exp(-SUAVIDAD_ZOOM * delta))
	if _volviendo and Ajustes.valores.reducir_movimiento:
		reiniciar_vista()
	if _volviendo:
		var k := 1.0 - exp(-SUAVIDAD_VUELTA * delta)
		yaw = lerp_angle(yaw, _yaw_juego, k)
		pitch = lerpf(pitch, _pitch_inicial(), k)
		if absf(angle_difference(yaw, _yaw_juego)) < 0.01 and absf(pitch - _pitch_inicial()) < 0.01:
			_volviendo = false
	_aplicar(delta)
	vista_actualizada.emit()


func _ajustes_cambiados(clave: String) -> void:
	if clave.is_empty() or clave == "vista":
		primera_persona = int(Ajustes.valores.vista) == 0
	if clave.is_empty() or clave == "fov":
		_fov_base = float(Ajustes.valores.fov)
		camara.fov = _fov_base
	if clave.is_empty() or clave == "distancia_tercera":
		_dist_obj = _distancia_ajustada()


func _pitch_inicial() -> float:
	return PITCH_PRIMERA if primera_persona else PITCH_JUEGO


func _distancia_ajustada() -> float:
	return minf(float(Ajustes.valores.distancia_tercera), distancia_maxima())


func _aplicar(delta: float) -> void:
	if camara == null or not is_instance_valid(objetivo):
		return
	var reducir: bool = Ajustes.valores.reducir_movimiento
	var fov_obj := clampf(_fov_base - 18.0, 42.0, 56.0) if apuntando_arco else _fov_base
	if delta <= 0.0 or reducir:
		camara.fov = fov_obj
	else:
		camara.fov = lerpf(camara.fov, fov_obj, 1.0 - exp(-12.0 * delta))
	var avance := smoothstep(0.0, 1.0, _mezcla)
	var alto := lerpf(ALTURA_OJOS, ALTURA_CERCA, avance) * altura_relativa
	var pivote := objetivo.global_position + Vector3.UP * alto
	var centro_ojos := objetivo.global_position + Vector3.UP * (ALTURA_OJOS * altura_relativa)
	if primera_persona and is_instance_valid(interlocutor) and Interfaz.ocupada():
		var ojos_vecino: Vector3 = interlocutor.call("punto_ojos")
		_girar_hacia(ojos_vecino - centro_ojos, 1.0 if reducir else 1.0 - exp(-18.0 * delta))
	elif not Interfaz.ocupada():
		interlocutor = null
	rotation = Vector3(-pitch, yaw, 0.0)

	var ojos := centro_ojos + _desplazamiento_ojos(delta, reducir)
	var dist_actual := distancia * 0.62 if apuntando_arco else distancia
	var hombro_x := 0.72 if apuntando_arco else 0.61
	var brazo := global_basis * Vector3(hombro_x, 0.14 if apuntando_arco else 0.08, dist_actual)
	var destino := pivote + _arco_de_vista(ojos - pivote, brazo, avance)
	destino += global_basis * _desplazamiento_sacudida(delta)
	global_position = _pivote_despejado(pivote)
	var pedido := destino - global_position
	var libre := _fraccion_sin_obstaculos(global_position, pedido)
	# La corrección es inmediata ante un obstáculo. Se recupera despacio al despejarlo.
	if libre < _fraccion_libre or delta <= 0.0 or reducir:
		_fraccion_libre = libre
	else:
		_fraccion_libre = move_toward(_fraccion_libre, libre, delta * 4.0)
	var offset := pedido * _fraccion_libre
	var encuadre_cercano := false
	if _mezcla >= 0.80 and not _fuera_del_cuerpo(global_position + offset):
		# Primero prueba el mismo hombro. En un rincón, busca espacio a un lado o sobre Leo.
		# La cámara usa un punto exterior al modelo incluso con la órbita acortada.
		var directo := pedido * libre
		if _fuera_del_cuerpo(global_position + directo):
			offset = directo
			_fraccion_libre = libre
		else:
			offset = _buscar_hombro(brazo, avance, directo)
			encuadre_cercano = true
	camara.position = global_basis.inverse() * offset
	camara.rotation = Vector3.ZERO
	if encuadre_cercano:
		var blanco := pivote - global_basis.z * 0.75
		if blanco.distance_squared_to(camara.global_position) > 0.01:
			camara.look_at(blanco)
	distancia_real = offset.length()
	cabeza_oculta = primera_persona and _mezcla < 0.22


func _arco_de_vista(ojos: Vector3, hombro: Vector3, avance: float) -> Vector3:
	# El cambio rodea el hombro derecho y conserva la altura de cada extremo.
	var inicio := ojos.slide(Vector3.UP)
	var fin := hombro.slide(Vector3.UP)
	var angulo := inicio.signed_angle_to(fin, Vector3.UP)
	if angulo > 0.0:
		angulo -= TAU
	var radio := lerpf(inicio.length(), fin.length(), avance)
	var horizontal := inicio.normalized().rotated(Vector3.UP, angulo * avance) * radio
	return horizontal + Vector3.UP * lerpf(ojos.y, hombro.y, avance)


func _fuera_del_cuerpo(punto: Vector3) -> bool:
	var desde_pies := punto - objetivo.global_position
	return desde_pies.slide(Vector3.UP).length() >= ESPACIO_ALREDEDOR_DE_LEO \
		or desde_pies.y >= ALTURA_OJOS * altura_relativa + 0.33


func _buscar_hombro(brazo: Vector3, avance: float, directo: Vector3) -> Vector3:
	var mejor := directo
	var limitado := brazo.slide(Vector3.UP).limit_length(1.10) * avance
	for grados: float in DESVIOS_HOMBRO:
		var lado := limitado.rotated(Vector3.UP, deg_to_rad(grados)) + Vector3.UP * 0.13
		var libre := lado * _fraccion_sin_obstaculos(global_position, lado)
		if _fuera_del_cuerpo(global_position + libre):
			return libre
		if libre.length_squared() > mejor.length_squared():
			mejor = libre
	var elevado := limitado * 0.30 + Vector3.UP * 0.91
	elevado *= _fraccion_sin_obstaculos(global_position, elevado)
	if _fuera_del_cuerpo(global_position + elevado):
		return elevado
	return mejor


func _pivote_despejado(centro: Vector3) -> Vector3:
	# Leo puede pasar por un farol sin colisión corporal. Si roza los ojos, mueve el pivote
	# unos centímetros alrededor de la cabeza antes de barrer hacia la posición pedida.
	var espacio := get_world_3d().direct_space_state
	if espacio == null:
		return centro
	_consulta_colision.motion = Vector3.ZERO
	_consulta_colision.transform = Transform3D(Basis.IDENTITY, centro)
	var roce := not espacio.intersect_shape(_consulta_colision, 1).is_empty()
	if _pivote_seguro.is_finite():
		var paso := centro - _pivote_seguro
		var avance := paso.length()
		# Una corrección física puede empujar a Leo hasta el plano de un muro. Conserva
		# el lado del último pivote libre antes de calcular el brazo de la cámara.
		if avance <= 0.75 and (roce or avance > 0.07):
			var libre := _fraccion_sin_obstaculos(_pivote_seguro, paso)
			if libre < 1.0:
				_pivote_seguro += paso * libre
				return _pivote_seguro
	if not roce:
		_pivote_seguro = centro
		return centro
	_consulta_colision.motion = Vector3.ZERO
	_consulta_colision.transform.origin = centro
	var contacto := espacio.get_rest_info(_consulta_colision)
	var normal: Vector3 = contacto.get("normal", Vector3.ZERO)
	var lado := Vector3.RIGHT.rotated(Vector3.UP, yaw) * 0.22
	for desplazamiento: Vector3 in [normal * 0.21, Vector3.UP * 0.20, lado, -lado, Vector3.DOWN * 0.24]:
		var candidato := centro + desplazamiento
		_consulta_colision.transform.origin = candidato
		if espacio.intersect_shape(_consulta_colision, 1).is_empty():
			_pivote_seguro = candidato
			return candidato
	if _pivote_seguro.is_finite() and _pivote_seguro.distance_squared_to(centro) <= 0.56:
		return _pivote_seguro
	return centro


func _desplazamiento_ojos(delta: float, reducir: bool) -> Vector3:
	var detalle := Vector3.ZERO
	if is_instance_valid(ancla_ojos) and not reducir and _mezcla < 1.0:
		var pos := ancla_ojos.global_position - objetivo.global_position
		detalle = pos.slide(Vector3.UP).limit_length(0.055) * 0.28
		if altura_relativa > 0.92:
			detalle.y = clampf((pos.y - 1.57) * 0.25, -0.023, 0.023)
	_detalle_ojos = _detalle_ojos.lerp(detalle, 1.0 if reducir or delta <= 0.0 else 1.0 - exp(-14.0 * delta))
	# Los ojos se sitúan delante del eje del cuello. La animación aporta solo un desplazamiento amortiguado.
	var frente := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var inclinacion := smoothstep(deg_to_rad(27.0), deg_to_rad(80.0), pitch)
	var desplazamiento := frente * lerpf(0.22, 0.39, inclinacion) + _detalle_ojos
	desplazamiento.y -= inclinacion * 0.045
	if not reducir:
		_fase_pasos += delta * (8.0 + minf(rapidez, 5.0))
		var intensidad := clampf(rapidez / 5.0, 0.0, 1.0)
		desplazamiento += frente.cross(Vector3.UP) * (sin(_fase_pasos) * intensidad * 0.011)
		desplazamiento.y += cos(_fase_pasos * 2.0) * intensidad * 0.016 - aterrizaje * 0.058
	return desplazamiento


## Centro superior de Leo para medir alcance y visibilidad desde el cuerpo.
func posicion_mano() -> Vector3:
	return objetivo.global_position + Vector3.UP * (1.40 * altura_relativa)


## Origen y dirección de la mira en coordenadas del mundo.
func direccion_mira() -> Vector3:
	return -camara.global_basis.z


func mirar_hacia(punto: Vector3) -> void:
	# En la órbita, el origen de la cámara también se mueve al girar.
	_volviendo = false
	for i in 16:
		var frente := punto - camara.global_position
		if i > 0 and frente.normalized().dot(direccion_mira()) > 0.99999:
			break
		_girar_hacia(frente, 1.0)
		_aplicar(0.0)


func seguir_punto(punto: Vector3, delta: float) -> void:
	_volviendo = false
	_girar_hacia(punto - camara.global_position, 1.0 - exp(-14.0 * delta))


func _girar_hacia(frente: Vector3, peso: float) -> void:
	var horizontal := frente.slide(Vector3.UP).length()
	if horizontal > 0.001:
		yaw = lerp_angle(yaw, atan2(-frente.x, -frente.z), peso)
	pitch = lerpf(pitch, clampf(atan2(-frente.y, horizontal), PITCH_MIN, PITCH_MAX), peso)


func rayo_central(mascara: int, metros: float, areas: bool = false, omitir: Array[RID] = []) -> Dictionary:
	var origen := camara.global_position
	return rayo_entre(origen, origen + direccion_mira() * metros, mascara, areas, omitir)


func rayo_entre(desde: Vector3, hasta: Vector3, mascara: int, areas: bool = false,
		omitir: Array[RID] = []) -> Dictionary:
	var espacio := get_world_3d().direct_space_state
	if espacio == null:
		return {}
	_consulta_rayo.from = desde
	_consulta_rayo.to = hasta
	_consulta_rayo.collision_mask = mascara
	_consulta_rayo.collide_with_areas = areas
	_consulta_rayo.hit_from_inside = true
	_consulta_rayo.exclude = _excluir + omitir
	return espacio.intersect_ray(_consulta_rayo)


func _fraccion_sin_obstaculos(origen: Vector3, desplazamiento: Vector3) -> float:
	var espacio := get_world_3d().direct_space_state
	if espacio == null or desplazamiento.length_squared() < 0.000001:
		return 1.0
	_consulta_colision.transform = Transform3D(Basis.IDENTITY, origen)
	_consulta_colision.motion = desplazamiento
	var r := espacio.cast_motion(_consulta_colision)
	# El rayo protege también si la esfera empieza solapada con una superficie muy cercana.
	var pared := rayo_entre(origen, origen + desplazamiento, MASCARA_SOLIDA)
	var fraccion := r[0] if r.size() >= 2 else 1.0
	if not pared.is_empty():
		fraccion = minf(fraccion, origen.distance_to(pared.position) / desplazamiento.length())
	if fraccion < 1.0:
		fraccion = maxf(0.0, fraccion - MARGEN_COLISION / desplazamiento.length())
	return fraccion


func _desplazamiento_sacudida(delta: float) -> Vector3:
	if _t_sacudida <= 0.0 or Ajustes.valores.reducir_movimiento:
		_t_sacudida = 0.0
		_fuerza_sacudida = 0.0
		return Vector3.ZERO
	_t_sacudida = maxf(_t_sacudida - maxf(delta, 0.0), 0.0)
	_fase_sacudida += maxf(delta, 0.0) * 52.0
	var k := _t_sacudida / maxf(_dur_sacudida, 0.001)
	var envolvente := k * k
	return Vector3(sin(_fase_sacudida) * 0.65, cos(_fase_sacudida * 1.37), 0.0) * (_fuerza_sacudida * envolvente)


## Sacudida suave al picar o talar; queda desactivada si está activada la reducción de movimiento.
func sacudir(fuerza: float = 0.055, duracion: float = 0.18) -> void:
	if Ajustes.valores.reducir_movimiento:
		_t_sacudida = 0.0
		_fuerza_sacudida = 0.0
		return
	_fuerza_sacudida = maxf(_fuerza_sacudida, clampf(fuerza, 0.0, 0.12))
	_dur_sacudida = clampf(duracion, 0.06, 0.35)
	_t_sacudida = _dur_sacudida


func hay_sacudida_activa() -> bool:
	return _t_sacudida > 0.0 and not Ajustes.valores.reducir_movimiento


## Lanza una sacudida sobre la cámara activa del jugador (solo al picar y talar).
static func sacudir_activa(fuerza: float = 0.055, duracion: float = 0.18) -> void:
	if Ajustes.valores.reducir_movimiento:
		return
	var j := Escenas.jugador()
	if j != null:
		var c: Variant = j.get("camara")
		if c is CamaraJuego:
			(c as CamaraJuego).sacudir(fuerza, duracion)
			return
	var arbol := Engine.get_main_loop() as SceneTree
	if arbol != null:
		var cam := arbol.get_first_node_in_group("camara_juego") as CamaraJuego
		if cam != null:
			cam.sacudir(fuerza, duracion)


## Acerca (negativo) o aleja (positivo) la cámara en metros.
func acercar(metros: float) -> void:
	_dist_obj = clampf(_dist_obj + metros, DIST_MIN, distancia_maxima())


## Un paso de rueda: dirección +1 aleja, −1 acerca (proporcional a la distancia, así se nota igual de cerca y de lejos).
func zoom_rueda(direccion: int) -> void:
	_dist_obj = clampf(_dist_obj * (1.0 + 0.12 * float(direccion)), DIST_MIN, distancia_maxima())


func distancia_maxima() -> float:
	return DIST_MAX_INTERIOR if interior else DIST_MAX


func girar(radianes: float) -> void:
	yaw = wrapf(yaw + radianes, -PI, PI)
	_volviendo = false


## Palanca derecha: la velocidad depende del tiempo y de la sensibilidad elegida.
func entrada_mando(entrada: Vector2, delta: float) -> void:
	if entrada.length_squared() <= 0.0001:
		return
	var velocidad := 2.0 * float(Ajustes.valores.sensibilidad) * delta
	girar(-entrada.x * velocidad)
	inclinar(entrada.y * velocidad)


func inclinar(radianes: float) -> void:
	if Ajustes.valores.invertir_vertical:
		radianes = -radianes
	pitch = clampf(pitch + radianes, PITCH_MIN, PITCH_MAX)
	_volviendo = false


## Interiores: la órbita tiene menor alcance dentro de una habitación.
func poner_interior(v: bool) -> void:
	interior = v
	_dist_obj = _distancia_ajustada()


## Vuelve a la vista de juego por defecto (la del marcador Camara_juego), con suavidad.
func reiniciar_vista() -> void:
	_volviendo = true
	_dist_obj = _distancia_ajustada()
	if Ajustes.valores.reducir_movimiento:
		# Cámara estable: sin barrido orbital ni zoom animado al recuperar la vista.
		_volviendo = false
		yaw = _yaw_juego
		pitch = _pitch_inicial()
		distancia = _dist_obj


## Coloca la cámara de golpe sobre el objetivo (al cargar un mapa) con la vista de juego.
func fijar(_pos: Vector3, yaw_nuevo: float) -> void:
	_pivote_seguro = Vector3.INF
	yaw = yaw_nuevo
	_yaw_juego = yaw_nuevo
	pitch = _pitch_inicial()
	_volviendo = false
	_dist_obj = _distancia_ajustada()
	distancia = _dist_obj
	_mezcla = 0.0 if primera_persona else 1.0
	_detalle_ojos = Vector3.ZERO
	interlocutor = null
	_aplicar(0.0)
