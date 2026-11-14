class_name CamaraJuego
extends Node3D
## Cámara orbital alrededor de Leo (3D libre).
## - Giro libre de 360° (yaw) e inclinación de ~8° a ~80° (pitch); lo manda jugador.gd con el clic derecho.
## - Zoom de 2,5 a 22 m con suavidad (8 m como máximo en interiores).
## - No atraviesa terreno ni paredes (capa 1): lanza una esfera hacia atrás y acorta la distancia con margen.
## - Mira a la altura del pecho cuando está cerca y baja el punto de mira al alejarse.
## - `reiniciar_vista()` vuelve a la vista de juego por defecto: yaw del marcador Camara_juego, 50° y 12 m.
## El movimiento de Leo es relativo a `yaw`: W va hacia donde mira la cámara.

## M2: Leo mide ahora EscalaPersonaje.ESCALA (0,89) de lo que medía; las distancias de la vista de juego y las alturas de
## la mira se escalan igual, así Leo se ve del mismo tamaño en pantalla y lo que cambia es que las casas se ven más
## grandes a su lado. El rango del zoom (2,5–22 m) no cambia.
const PITCH_JUEGO := deg_to_rad(50.0)
const PITCH_MIN := deg_to_rad(8.0)
const PITCH_MAX := deg_to_rad(80.0)
const DIST_JUEGO := 12.0 * EscalaPersonaje.ESCALA
const DIST_MIN := 2.5
const DIST_MAX := 22.0
const DIST_MAX_INTERIOR := 8.0
const DIST_JUEGO_INTERIOR := 7.0 * EscalaPersonaje.ESCALA
const ALTURA_CERCA := 1.45 * EscalaPersonaje.ESCALA   # a la altura del pecho cuando la cámara está cerca
const ALTURA_LEJOS := 1.0 * EscalaPersonaje.ESCALA
const SUAVIDAD_SEGUIR := 10.0
const SUAVIDAD_ZOOM := 9.0
const SUAVIDAD_VUELTA := 6.0
const RADIO_COLISION := 0.3
const MARGEN_COLISION := 0.15

var yaw: float = 0.0
var pitch: float = PITCH_JUEGO            # radianes hacia abajo (0 = horizontal, 80° = casi cenital)
var distancia: float = DIST_JUEGO         # distancia pedida (suavizada)
var objetivo: Node3D = null
## Multiplica la altura de la mira: 1 con Leo de pie, menos si se agacha (lo pone jugador.gd, ya suavizado).
var altura_relativa: float = 1.0
var camara: Camera3D = null
var interior: bool = false
var distancia_real: float = DIST_JUEGO    # tras acortarla por colisiones

var _dist_obj: float = DIST_JUEGO
var _yaw_juego: float = 0.0
var _volviendo: bool = false
var _forma: SphereShape3D = null
var _excluir: Array[RID] = []
var _t_sacudida: float = 0.0
var _dur_sacudida: float = 0.18
var _fuerza_sacudida: float = 0.0
var _fase_sacudida: float = 0.0


func _ready() -> void:
	top_level = true
	add_to_group("camara_juego")
	camara = Camera3D.new()
	camara.name = "Camara"
	camara.fov = 45.0
	camara.near = 0.1
	camara.far = 700.0
	add_child(camara)
	camara.current = true
	_forma = SphereShape3D.new()
	_forma.radius = RADIO_COLISION
	if objetivo is CollisionObject3D:
		_excluir.append((objetivo as CollisionObject3D).get_rid())
	_aplicar(0.0)


func _process(delta: float) -> void:
	if _volviendo and Ajustes.valores.reducir_movimiento:
		reiniciar_vista()
	if objetivo != null and is_instance_valid(objetivo):
		var destino := objetivo.global_position + Vector3(0, _altura_mira() * altura_relativa, 0)
		global_position = global_position.lerp(destino, 1.0 - exp(-SUAVIDAD_SEGUIR * delta))
	distancia = lerpf(distancia, _dist_obj, 1.0 - exp(-SUAVIDAD_ZOOM * delta))
	if _volviendo:
		var k := 1.0 - exp(-SUAVIDAD_VUELTA * delta)
		yaw = lerp_angle(yaw, _yaw_juego, k)
		pitch = lerpf(pitch, PITCH_JUEGO, k)
		if absf(angle_difference(yaw, _yaw_juego)) < 0.01 and absf(pitch - PITCH_JUEGO) < 0.01:
			_volviendo = false
	_aplicar(delta)


func _altura_mira() -> float:
	var f := clampf((distancia - 3.0 * EscalaPersonaje.ESCALA) / (8.0 * EscalaPersonaje.ESCALA), 0.0, 1.0)
	return lerpf(ALTURA_CERCA, ALTURA_LEJOS, f)


func _aplicar(delta: float) -> void:
	rotation = Vector3(-pitch, yaw, 0.0)
	if camara == null:
		return
	var permitida := _distancia_libre(distancia)
	# Si algo se interpone, se acerca de golpe; al despejarse, vuelve despacio.
	if permitida < distancia_real or delta <= 0.0:
		distancia_real = permitida
	else:
		distancia_real = lerpf(distancia_real, permitida, 1.0 - exp(-5.0 * delta))
	camara.position = Vector3(0, 0, distancia_real) + _desplazamiento_sacudida(delta)


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


## Distancia máxima hacia atrás sin meter la cámara en el terreno o en una pared.
func _distancia_libre(pedida: float) -> float:
	if not is_inside_tree() or get_world_3d() == null:
		return pedida
	var espacio := get_world_3d().direct_space_state
	if espacio == null:
		return pedida
	var origen := global_position
	var atras := global_transform.basis.z.normalized()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _forma
	q.transform = Transform3D(Basis.IDENTITY, origen)
	q.motion = atras * (pedida + MARGEN_COLISION)
	q.collision_mask = 1
	q.exclude = _excluir
	var r := espacio.cast_motion(q)
	if r.size() < 2:
		return pedida
	var libre := float(r[0]) * (pedida + MARGEN_COLISION) - MARGEN_COLISION
	return clampf(libre, 0.6, pedida)


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
	pitch = clampf(pitch + radianes, PITCH_MIN, PITCH_MAX)
	_volviendo = false


## Interiores: la cámara no se aleja más de 8 m.
func poner_interior(v: bool) -> void:
	interior = v
	_dist_obj = clampf(_dist_obj, DIST_MIN, distancia_maxima())
	if v:
		_dist_obj = minf(_dist_obj, DIST_JUEGO_INTERIOR)
		distancia = minf(distancia, _dist_obj)


## Vuelve a la vista de juego por defecto (la del marcador Camara_juego), con suavidad.
func reiniciar_vista() -> void:
	_volviendo = true
	_dist_obj = DIST_JUEGO_INTERIOR if interior else DIST_JUEGO
	if Ajustes.valores.reducir_movimiento:
		# Cámara estable: sin barrido orbital ni zoom animado al recuperar la vista.
		_volviendo = false
		yaw = _yaw_juego
		pitch = PITCH_JUEGO
		distancia = _dist_obj


## Coloca la cámara de golpe sobre el objetivo (al cargar un mapa) con la vista de juego.
func fijar(pos: Vector3, yaw_nuevo: float) -> void:
	yaw = yaw_nuevo
	_yaw_juego = yaw_nuevo
	pitch = PITCH_JUEGO
	_volviendo = false
	_dist_obj = DIST_JUEGO_INTERIOR if interior else DIST_JUEGO
	distancia = _dist_obj
	global_position = pos + Vector3(0, ALTURA_CERCA if distancia < 3.0 * EscalaPersonaje.ESCALA else _altura_mira(), 0)
	_aplicar(0.0)
