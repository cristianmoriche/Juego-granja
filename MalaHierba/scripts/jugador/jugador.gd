class_name Jugador
extends CharacterBody3D
## Leo: se mueve con WASD relativo a la cámara, interactúa con E y usa lo que lleva en la mano con el clic izquierdo.
## Cámara: clic derecho mantenido + ratón gira alrededor de Leo (el cursor se oculta),
## clic central o C = vista de juego por defecto. La rueda cambia de objeto en la barra (ver Interfaz).
## Interactuables: grupo «interactuable» con texto_interaccion() -> String e interactuar(jugador) (ver Interactuable);
## el elegido (el más de frente dentro de su alcance) se resalta con un Resaltador.
## Usables: grupo «usable» con usar(id_objeto, punto, jugador) -> bool (el receptor gasta la energía).
## M2: tamaño de Leo = el del `.glb` × EscalaPersonaje.ESCALA (1,75 m); saltar con Espacio (acción «saltar»: desde el suelo,
## sin doble salto, ~1 m, con algo de control en el aire) y agacharse con Ctrl izquierdo (acción «agachar», mantenido: la
## cápsula baja, anda más despacio, no corre y no se levanta si hay techo encima).
##
## Para L7 (animaciones definitivas): si el AnimationPlayer de Leo tiene alguna de estas animaciones, se usa en su estado y se
## apaga la pose provisional de ese estado: «saltar» (subiendo), «caer» (bajando), «aterrizar» (al tocar suelo tras una caída),
## «agachado_reposo» y «agachado_andar». Los estados que calcula este script (variable `estado_mov`) son «suelo», «salto»,
## «caida», «aterrizaje» y «agachado». Sin esas animaciones, el modelo se estira/encoge e inclina un poco (`_actualizar_pose`).

## Velocidades en m/s: las de antes (3,5 y 6,0) por la escala del personaje, para que la marcha siga pareciendo la misma.
const VEL_ANDAR := 3.5 * EscalaPersonaje.ESCALA
const VEL_CORRER := 6.0 * EscalaPersonaje.ESCALA
const VEL_AGACHADO := 1.5
const ACELERACION := 32.0
const ACELERACION_AIRE := 10.0   # en el aire se puede corregir el rumbo, pero con menos fuerza que en el suelo
const GRAVEDAD := 24.0
## Salto: con GRAVEDAD 24 m/s², v = √(2·24·1,0) = 6,93 m/s sube 1,0 m.
const ALTURA_SALTO := 1.0
const VEL_SALTO := 6.93
const TIEMPO_COYOTE := 0.08      # margen para saltar justo después de pisar el borde de algo
const TIEMPO_BUFER_SALTO := 0.12 # margen para el Espacio pulsado un instante antes de tocar suelo
const ALTURA_AGACHADO := 1.0     # altura de la cápsula agachado (de pie: EscalaPersonaje.ALTURA_PIE)
const CAIDA_MIN_AMORTIGUAR := 4.0 # velocidad de caída (m/s) a partir de la cual se nota el aterrizaje
const TIEMPO_ATERRIZAJE := 0.15
const TIEMPO_ATASCO_AIRE := 1.0  # segundos colgado en el aire sin moverse antes de volver al último sitio firme
const RUTA_MODELO := "res://assets/personajes/leo/leo.glb"
const RUTA_HERRAMIENTAS := "res://assets/herramientas/%s.glb"
const DIST_USAR := 1.2
const ALCANCE_INTERACTUAR := 2.0
const DURACION_HERRAMIENTA := 0.6
const GIRO_CAMARA_RATON := 0.0055
const PAUSA_AVISO_USO := 0.7
const CAPA_LIMITES := 32      # capa 6 «limites»: muros invisibles del borde de cada mapa (Mapa los crea)
const CAPA_SOLO_JUGADOR := 64 # capa 7 «solo_jugador»: techo y maderas de las cuevas (la cámara no choca con ellos)

@onready var _modelo: Node3D = $Modelo
@onready var _farol: OmniLight3D = $Farol

var camara: CamaraJuego = null
var direccion: Vector3 = Vector3(0, 0, 1)     # hacia dónde mira (plano XZ, normalizado)
var _activo: bool = false
var _anim: AnimationPlayer = null
var _anim_actual: String = ""
var _t_herramienta: float = 0.0
var _t_busqueda: float = 0.0
var _hay_cartel: bool = false
var _objetivo: Node3D = null
var _pos_segura: Vector3 = Vector3.ZERO
var _t_segura: float = 0.0
var _modelo_visual: Node3D = null
var _resaltador: Resaltador = null
var _girando: bool = false
var _pos_cursor: Vector2 = Vector2.ZERO
var _t_aviso_uso: float = 0.0
var _mapa: Node = null          # mapa en el que está (para la red de seguridad de los límites)

# --- Saltar y agacharse (M2) ---
## true mientras Ctrl está pulsado o hay techo encima que no deja levantarse.
var agachado: bool = false
## Estado de movimiento: «suelo», «salto» (subiendo), «caida», «aterrizaje» o «agachado» (ver la cabecera).
var estado_mov: String = "suelo"
## Saltos hechos desde que existe este Leo (lo usan las pruebas).
var saltos: int = 0
## Veces que se le sacó de una grieta en la que se quedó colgado en el aire (lo usan las pruebas).
var atascos_resueltos: int = 0
var _pos_ant: Vector3 = Vector3.ZERO
var _t_atasco_aire: float = 0.0
var _t_coyote: float = 0.0
var _t_bufer_salto: float = 0.0
var _t_aterrizaje: float = 0.0
var _vy_previa: float = 0.0
var _estaba_en_suelo: bool = true
var _colision: CollisionShape3D = null
var _forma: CapsuleShape3D = null
var _forma_cabeza: CylinderShape3D = null
var _visual: Node3D = null       # nodo del modelo al que se aplica la pose provisional
var _pose_escala: Vector3 = Vector3.ONE
var _pose_inclin: float = 0.0
var _anim_propia: bool = false   # el estado actual usa una animación propia (no la pose provisional)
var _altura_cam: float = 1.0     # altura relativa de la mira de la cámara (1 de pie, menos agachado), suavizada
var _t_paso: float = 0.0         # temporizador para el sonido de pisadas
var _mano_soporte: Node3D = null
var _herramienta_nodo: Node3D = null
var _objeto_en_mano: String = ""
var _nivel_en_mano: int = -1
var _modelos_mano: Dictionary = {}


func _ready() -> void:
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(55.0)
	collision_mask |= CAPA_LIMITES | CAPA_SOLO_JUGADOR
	# Tamaño: modelo y cápsula a la escala común de los personajes. La forma se duplica para poder cambiarle la altura.
	_modelo.scale = Vector3.ONE * EscalaPersonaje.ESCALA
	_colision = $Colision
	_forma = (_colision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	_forma.radius = EscalaPersonaje.RADIO
	_colision.shape = _forma
	_forma_cabeza = CylinderShape3D.new()
	_poner_altura(EscalaPersonaje.ALTURA_PIE)
	_farol.position.y = 2.2 * EscalaPersonaje.ESCALA
	_cargar_modelo()
	camara = CamaraJuego.new()
	camara.name = "CamaraRig"
	camara.objetivo = self
	add_child(camara)
	_resaltador = Resaltador.new()
	_resaltador.name = "Resaltador"
	add_child(_resaltador)
	_farol.visible = false
	if not Juego.ranura_cambiada.is_connected(_on_mano_cambiada):
		Juego.ranura_cambiada.connect(_on_mano_cambiada)
	if not Juego.inventario_cambiado.is_connected(_actualizar_objeto_en_mano):
		Juego.inventario_cambiado.connect(_actualizar_objeto_en_mano)
	if not Juego.partida_cambiada.is_connected(_actualizar_objeto_en_mano):
		Juego.partida_cambiada.connect(_actualizar_objeto_en_mano)
	_actualizar_objeto_en_mano()


## La activa Escenas cuando ya está colocado y con suelo debajo.
func activar() -> void:
	_activo = true


## Coloca a Leo de golpe: posición y giro de la cámara. Mira hacia delante de la cámara (el giro del marcador
## de aparición no se usa: así se le ve siempre de espaldas al entrar).
func colocar(pos: Vector3, _giro_cuerpo: float, giro_camara: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_t_bufer_salto = 0.0
	_t_coyote = 0.0
	_t_atasco_aire = 0.0
	_pos_ant = pos
	_pos_segura = pos
	if not is_nan(_giro_cuerpo):
		direccion = Vector3(sin(_giro_cuerpo), 0.0, cos(_giro_cuerpo)).normalized()
	else:
		direccion = Vector3(0, 0, -1).rotated(Vector3.UP, giro_camara)
	_modelo.rotation.y = atan2(direccion.x, direccion.z)
	camara.fijar(pos, giro_camara)


## Luz de farol en interiores (la mina) y nada más; la cámara no se aleja tanto dentro.
func configurar_para_mapa(mapa: Node) -> void:
	_mapa = mapa
	var interior: bool = bool(mapa.get("interior"))
	_farol.visible = interior
	camara.poner_interior(interior)


## ¿Está Leo dentro del área jugable del mapa (datos/limites.json)? Sin límites o sin mapa, sí.
func dentro_de_limites() -> bool:
	if _mapa == null or not is_instance_valid(_mapa) or not _mapa.has_method("punto_dentro"):
		return true
	return bool(_mapa.call("punto_dentro", global_position, 0.7))


## Punto del suelo a `dist` metros por delante.
func punto_delante(dist: float = DIST_USAR) -> Vector3:
	return global_position + direccion * dist


## Anima el golpe de herramienta y bloquea el movimiento ~0,6 s. Lo llama _usar() y puede llamarlo quien lo necesite.
func animar_herramienta() -> void:
	_t_herramienta = DURACION_HERRAMIENTA
	var nom := _animacion_de_herramienta(_objeto_en_mano)
	if _anim != null and not _anim.has_animation(nom):
		nom = "herramienta"
	_reproducir(nom, 0.05)
	if _modelo_visual != null:
		# Sin animación (cápsula de prueba): un pequeño empujón hacia delante para que se note.
		var t := create_tween()
		t.tween_property(_modelo_visual, "position:z", 0.3, 0.15)
		t.tween_property(_modelo_visual, "position:z", 0.0, 0.25)


func bloquear(segundos: float) -> void:
	_t_herramienta = maxf(_t_herramienta, segundos)


# --- Saltar y agacharse (M2) -------------------------------------------------------------------

## Pide un salto (lo hace Espacio). Se hará en cuanto la física pueda: desde el suelo, sin doble salto, no agachado,
## con la interfaz cerrada y sin estar usando una herramienta. Si no se puede en 0,12 s, se olvida.
func solicitar_salto() -> void:
	_t_bufer_salto = TIEMPO_BUFER_SALTO


## Altura actual de la cápsula de colisión (de pie o agachado), con los pies siempre en el origen de Leo.
func _poner_altura(h: float) -> void:
	_forma.height = h
	_colision.position.y = h * 0.5


func _actualizar_agachado(quiere: bool) -> void:
	if quiere and not agachado:
		agachado = true
		_poner_altura(ALTURA_AGACHADO)
	elif not quiere and agachado and not techo_encima():
		agachado = false
		_poner_altura(EscalaPersonaje.ALTURA_PIE)


## ¿Hay algo (mundo o techo de cueva) justo por encima de la cabeza agachada, en el hueco que ocuparía de pie?
## Con eso encima no se levanta: sigue agachado hasta que haya sitio.
func techo_encima() -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var espacio := get_world_3d().direct_space_state
	if espacio == null:
		return false
	var h0 := ALTURA_AGACHADO + 0.02
	var h1 := EscalaPersonaje.ALTURA_PIE
	_forma_cabeza.radius = EscalaPersonaje.RADIO - 0.04
	_forma_cabeza.height = h1 - h0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _forma_cabeza
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, (h0 + h1) * 0.5, 0))
	q.collision_mask = 1 | CAPA_SOLO_JUGADOR
	q.exclude = [get_rid()]
	return not espacio.intersect_shape(q, 1).is_empty()


## Elige la animación del estado. Si el modelo trae la propia del estado (L7), se usa; si no, se deja el reposo o el
## andar de siempre y `_actualizar_pose` pone una pose provisional (estirado al saltar, encogido e inclinado al agacharse).
func _animar_estado(rapidez: float, corriendo: bool) -> void:
	var propia := ""
	match estado_mov:
		"salto":
			propia = "saltar"
		"caida":
			propia = "caer"
		"aterrizaje":
			propia = "aterrizar"
		"agachado":
			propia = "agachado_andar" if rapidez > 0.3 else "agachado_reposo"
	_anim_propia = false
	if not propia.is_empty() and _anim != null and _anim.has_animation(propia):
		_anim_propia = true
		var mezcla := 0.2 if estado_mov == "agachado" else 0.15
		_reproducir(propia, mezcla, 1.0)
		return
	var con_herramienta := not _objeto_en_mano.is_empty()
	var nom_andar := "andar_herramienta" if (con_herramienta and _anim != null and _anim.has_animation("andar_herramienta")) else "andar"
	var nom_reposo := "reposo_herramienta" if (con_herramienta and _anim != null and _anim.has_animation("reposo_herramienta")) else "reposo"
	if estado_mov == "salto" or estado_mov == "caida":
		_reproducir(nom_reposo, 0.1)       # en el aire no mueve las piernas como si anduviera
	elif rapidez > 0.4:
		_reproducir(nom_andar, 0.15, 1.45 if corriendo else (0.5 if agachado else 1.0))
	else:
		_reproducir(nom_reposo, 0.2)


func _actualizar_pasos(rapidez: float, corriendo: bool, delta: float) -> void:
	if (estado_mov == "suelo" or estado_mov == "agachado") and rapidez > 0.4:
		_t_paso -= delta
		if _t_paso <= 0.0:
			_t_paso = 0.34 if corriendo else (0.65 if agachado else 0.48)
			Audio.reproducir(_sonido_paso())
	else:
		_t_paso = 0.08


func _sonido_paso() -> String:
	var id := str(_mapa.get("id_mapa")) if _mapa != null else ""
	if id == "mina_interior" or id == "mina_exterior":
		return "paso_piedra"
	if _mapa != null and bool(_mapa.get("interior")):
		return "paso_madera"
	if id == "pueblo":
		return "paso_tierra"
	if id == "granja" and absf(global_position.x) < 15.0 and absf(global_position.z) < 12.0:
		return "paso_tierra"
	return "paso_hierba"


## Pose provisional (hasta que L7 traiga animaciones de verdad): deforma y inclina el modelo con suavidad.
func _actualizar_pose(delta: float) -> void:
	if _visual == null:
		return
	var esc := Vector3.ONE
	var incl := 0.0
	if not _anim_propia:
		match estado_mov:
			"agachado":
				esc = Vector3(1.06, 0.68, 1.06)
				incl = 0.35
			"salto":
				esc = Vector3(0.94, 1.07, 0.94)
			"caida":
				esc = Vector3(0.97, 1.03, 0.97)
				incl = 0.1
			"aterrizaje":
				esc = Vector3(1.1, 0.84, 1.1)
				incl = 0.12
	var k := 1.0 - exp(-16.0 * delta)
	_pose_escala = _pose_escala.lerp(esc, k)
	_pose_inclin = lerpf(_pose_inclin, incl, k)
	_visual.scale = _pose_escala
	_visual.rotation.x = _pose_inclin


# --- Física y animación ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _activo:
		return
	var libre_ui := not Interfaz.ocupada() and not Escenas.en_transicion
	if libre_ui:
		camara.entrada_mando(Input.get_vector("camara_izquierda", "camara_derecha", "camara_arriba", "camara_abajo"), delta)
	var libre := libre_ui and _t_herramienta <= 0.0
	_t_herramienta = maxf(_t_herramienta - delta, 0.0)
	_t_bufer_salto = maxf(_t_bufer_salto - delta, 0.0)
	_t_aterrizaje = maxf(_t_aterrizaje - delta, 0.0)

	# Agacharse: Ctrl mantenido. Al soltar se levanta, salvo que haya techo encima.
	_actualizar_agachado(libre_ui and Input.is_action_pressed("agachar"))

	var entrada := Vector2.ZERO
	if libre:
		entrada = Input.get_vector("mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo")
	var objetivo_vel := Vector3.ZERO
	var corriendo := false
	if entrada.length() > 0.01:
		# Relativo a la cámara: W va hacia donde ella mira, aunque esté girada del todo.
		var dir3 := Vector3(entrada.x, 0.0, entrada.y).rotated(Vector3.UP, camara.yaw)
		corriendo = Input.is_action_pressed("correr") and not agachado
		var vel := VEL_AGACHADO if agachado else (VEL_CORRER if corriendo else VEL_ANDAR)
		objetivo_vel = dir3 * vel
		direccion = dir3.normalized()
	var en_suelo := is_on_floor()
	if not en_suelo and is_on_wall():
		# En el aire contra una pared no se empuja hacia ella: si no, en una grieta de la roca Leo se queda colgado
		# apretado contra la pared en vez de resbalar y caer.
		var hacia_pared := -get_wall_normal()
		hacia_pared.y = 0.0
		if hacia_pared.length() > 0.01:
			hacia_pared = hacia_pared.normalized()
			var hacia := objetivo_vel.dot(hacia_pared)
			if hacia > 0.0:
				objetivo_vel -= hacia_pared * hacia
	var acel := ACELERACION if en_suelo else ACELERACION_AIRE
	velocity.x = move_toward(velocity.x, objetivo_vel.x, acel * delta)
	velocity.z = move_toward(velocity.z, objetivo_vel.z, acel * delta)

	# Saltar: solo desde el suelo (con un margen mínimo al pisar un borde), sin doble salto, y no agachado ni con la
	# interfaz abierta o usando una herramienta. El Espacio pulsado un instante antes de aterrizar también cuenta.
	if en_suelo:
		_t_coyote = TIEMPO_COYOTE
	else:
		_t_coyote = maxf(_t_coyote - delta, 0.0)
	if _t_bufer_salto > 0.0 and _t_coyote > 0.0 and libre and not agachado:
		velocity.y = VEL_SALTO
		_t_coyote = 0.0
		_t_bufer_salto = 0.0
		saltos += 1
		en_suelo = false
	if en_suelo:
		velocity.y = -1.0
	else:
		velocity.y -= GRAVEDAD * delta
	_vy_previa = velocity.y
	move_and_slide()

	# Aterrizaje tras una caída de verdad (no al pisar el suelo andando).
	var ahora_en_suelo := is_on_floor()
	if ahora_en_suelo and not _estaba_en_suelo and _vy_previa < -CAIDA_MIN_AMORTIGUAR:
		_t_aterrizaje = TIEMPO_ATERRIZAJE
	_estaba_en_suelo = ahora_en_suelo
	# Colgado en el aire (saltando se puede acabar encajado en una grieta de la roca de la cueva: ni toca suelo ni cae):
	# si lleva más de un segundo sin moverse, vuelve al último sitio firme.
	if not ahora_en_suelo and (global_position - _pos_ant).length() < 0.002:
		_t_atasco_aire += delta
	else:
		_t_atasco_aire = 0.0
	_pos_ant = global_position
	if _t_atasco_aire > TIEMPO_ATASCO_AIRE:
		_t_atasco_aire = 0.0
		global_position = _pos_segura + Vector3(0, 0.3, 0)
		velocity = Vector3.ZERO
		atascos_resueltos += 1
	if not ahora_en_suelo:
		estado_mov = "salto" if velocity.y > 0.5 else "caida"
	elif agachado:
		estado_mov = "agachado"
	elif _t_aterrizaje > 0.0:
		estado_mov = "aterrizaje"
	else:
		estado_mov = "suelo"

	# Gira el modelo con suavidad hacia donde anda.
	var objetivo_giro := atan2(direccion.x, direccion.z)
	_modelo.rotation.y = lerp_angle(_modelo.rotation.y, objetivo_giro, 1.0 - exp(-14.0 * delta))

	# Animación según lo que hace.
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if _t_herramienta > 0.0:
		pass
	else:
		_animar_estado(rapidez, corriendo)
		_actualizar_pasos(rapidez, corriendo, delta)
	_actualizar_pose(delta)

	# La cámara baja la mira al agacharse y la sube al levantarse, sin tirones.
	_altura_cam = lerpf(_altura_cam, _forma.height / EscalaPersonaje.ALTURA_PIE, 1.0 - exp(-9.0 * delta))
	camara.altura_relativa = _altura_cam

	# Red de seguridad: si cae por un agujero del mapa o acaba fuera del polígono de límites (los muros de Mapa lo
	# impiden; esto es por si algo falla), vuelve al último sitio firme dentro.
	_t_segura -= delta
	var dentro := dentro_de_limites()
	if is_on_floor() and _t_segura <= 0.0 and dentro:
		_pos_segura = global_position
		_t_segura = 0.5
	if not dentro or global_position.y < _pos_segura.y - 40.0:
		global_position = _pos_segura + Vector3(0, 0.5, 0)
		velocity = Vector3.ZERO


func _process(delta: float) -> void:
	if not _activo:
		return
	_t_aviso_uso = maxf(_t_aviso_uso - delta, 0.0)
	if _girando and (Interfaz.ocupada() or Escenas.en_transicion):
		_terminar_giro()
	_t_busqueda -= delta
	if _t_busqueda <= 0.0:
		_t_busqueda = 0.1
		_actualizar_interactuable()


# --- Interacción ---------------------------------------------------------------------------

## Elige el interactuable más de frente dentro de su alcance, lo resalta y pone su cartel.
func _actualizar_interactuable() -> void:
	var anterior := _objetivo
	_objetivo = null
	if not Interfaz.ocupada() and not Escenas.en_transicion:
		var mejor := -INF
		for n: Node in get_tree().get_nodes_in_group("interactuable"):
			var n3 := n as Node3D
			if n3 == null or not n3.is_inside_tree() or not n3.has_method("interactuar") or not n3.has_method("texto_interaccion"):
				continue
			var d := n3.global_position - global_position
			if absf(d.y) > 3.5:
				continue
			d.y = 0.0
			var dist := d.length()
			var alcance := ALCANCE_INTERACTUAR
			if n3.has_method("alcance_interaccion"):
				alcance = float(n3.call("alcance_interaccion"))
			if dist > alcance:
				continue
			var frente := 1.0
			if dist > 0.05:
				frente = d.normalized().dot(direccion)
			if dist > alcance * 0.4 and frente < 0.15:
				continue   # por detrás
			if str(n3.call("texto_interaccion")).is_empty():
				continue
			# El más de frente; a igualdad, el más cercano. El que ya estaba elegido tiene una pequeña ventaja
			# para que el cartel no parpadee entre dos objetos parecidos.
			var puntos := frente - 0.5 * dist / maxf(alcance, 0.1)
			if n3 == anterior:
				puntos += 0.12
			if puntos > mejor:
				mejor = puntos
				_objetivo = n3
	_resaltador.apuntar(_objetivo)
	if _objetivo != null:
		Interfaz.mostrar_accion(Ajustes.pista("interactuar") + "  ·  " + str(_objetivo.call("texto_interaccion")))
		_hay_cartel = true
	elif _hay_cartel:
		Interfaz.ocultar_accion()
		_hay_cartel = false


func _unhandled_input(event: InputEvent) -> void:
	# Soltar el clic derecho siempre cuenta, aunque se haya abierto algo mientras tanto.
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_RIGHT and not b.pressed and _girando:
			_terminar_giro()
			get_viewport().set_input_as_handled()
			return
	if not _activo or Interfaz.ocupada() or Escenas.en_transicion:
		return
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.pressed:
			match e.button_index:
				MOUSE_BUTTON_RIGHT:
					_empezar_giro()
					get_viewport().set_input_as_handled()
					return
				MOUSE_BUTTON_MIDDLE:
					camara.reiniciar_vista()
					get_viewport().set_input_as_handled()
					return
	if event is InputEventMouseMotion and _girando:
		var m := event as InputEventMouseMotion
		camara.girar(-m.relative.x * GIRO_CAMARA_RATON * float(Ajustes.valores.sensibilidad))
		camara.inclinar(m.relative.y * GIRO_CAMARA_RATON * float(Ajustes.valores.sensibilidad))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camara_reiniciar"):
		camara.reiniciar_vista()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("saltar"):
		solicitar_salto()
		get_viewport().set_input_as_handled()
		return
	var deco := get_tree().get_first_node_in_group("decoracion_casa") if get_tree() != null else null
	if deco != null and bool(deco.call("esta_decorando")):
		if event.is_action_pressed("interactuar"):
			deco.call("accion_principal")
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("usar") and not _girando:
			deco.call("accion_principal")
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interactuar"):
		_interactuar()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("usar") and not _girando:
		if event is InputEventMouseButton:
			_mirar_al_punto((event as InputEventMouseButton).position)
		_usar()
		get_viewport().set_input_as_handled()


## Clic derecho: el cursor se oculta y el ratón gira la cámara.
func _empezar_giro() -> void:
	if _girando:
		return
	_girando = true
	_pos_cursor = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Al soltar, el cursor vuelve a aparecer donde estaba.
func _terminar_giro() -> void:
	if not _girando:
		return
	_girando = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().warp_mouse(_pos_cursor)


func _exit_tree() -> void:
	if _girando:
		_girando = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_terminar_giro()


func _interactuar() -> void:
	_actualizar_interactuable()
	if _objetivo != null and is_instance_valid(_objetivo):
		# Mira hacia lo que va a tocar.
		var d := _objetivo.global_position - global_position
		d.y = 0.0
		if d.length() > 0.2:
			direccion = d.normalized()
		_objetivo.call("interactuar", self)


## Gira hacia el punto del suelo bajo el cursor (el punto de uso sigue siendo 1,2 m por delante).
func _mirar_al_punto(pantalla: Vector2) -> void:
	var cam := camara.camara
	if cam == null:
		return
	var origen := cam.project_ray_origin(pantalla)
	var rayo := cam.project_ray_normal(pantalla)
	if rayo.y >= -0.01:
		return
	var t := (global_position.y - origen.y) / rayo.y
	if t <= 0.0:
		return
	var p := origen + rayo * t
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.25:
		direccion = d.normalized()


func _usar() -> void:
	if _t_herramienta > 0.0:
		return
	var obj := Juego.objeto_activo()
	if obj.is_empty():
		return
	var id := str(obj["id"])
	var datos := Datos.objeto(id)
	if datos.get("tipo", "") == "comida":
		Juego.comer(id)
		return
	if Datos.es_mueble(id):
		var deco := get_tree().get_first_node_in_group("decoracion_casa") if get_tree() != null else null
		if deco != null:
			deco.call("entrar_modo_decorar", id)
			return
		Interfaz.mensaje(motivo_sin_efecto(id))
		return
	var punto := punto_delante(DIST_USAR)
	var candidatos: Array[Node3D] = []
	for n: Node in get_tree().get_nodes_in_group("usable"):
		var n3 := n as Node3D
		if n3 != null and n3.is_inside_tree() and n3.has_method("usar"):
			candidatos.append(n3)
	candidatos.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(punto) < b.global_position.distance_squared_to(punto))
	var avisos_antes := Interfaz.avisos_emitidos
	for n3 in candidatos:
		if bool(n3.call("usar", id, punto, self)):
			animar_herramienta()
			return
	# Nadie ha hecho nada: si tampoco ha avisado de por qué, lo decimos nosotros (sin repetirlo en cada clic).
	if Interfaz.avisos_emitidos == avisos_antes and _t_aviso_uso <= 0.0:
		_t_aviso_uso = PAUSA_AVISO_USO
		Interfaz.mensaje(motivo_sin_efecto(id))


## Por qué no pasa nada al usar este objeto en este sitio.
static func motivo_sin_efecto(id: String) -> String:
	match id:
		"azada":
			return "Aquí no hay nada que cavar."
		"regadera":
			return "Aquí no hay nada que regar."
		"hoz":
			return "Aquí no hay nada que segar."
		"hacha":
			return "Aquí no hay nada que talar."
		"pico":
			return "Aquí no hay nada que picar."
		"cana":
			return "Acércate al puente del río o al muelle del lago para pescar."
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	if tipo == "semilla":
		return "Aquí no se puede sembrar: hace falta tierra arada."
	if tipo == "tratamiento":
		return "Aquí no hay ningún cultivo con plaga."
	if tipo == "mueble":
		return "Los muebles solo se colocan dentro de tu casa (pulsa B allí para decorar)."
	return "No puedes usar eso aquí."


# --- Modelo -------------------------------------------------------------------------------

func _cargar_modelo() -> void:
	if ResourceLoader.exists(RUTA_MODELO):
		var ps := load(RUTA_MODELO) as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			_modelo.add_child(inst)
			_visual = inst
			var anims := inst.find_children("*", "AnimationPlayer", true, false)
			if not anims.is_empty():
				_anim = anims[0] as AnimationPlayer
				for nombre in ["reposo", "andar", "reposo_herramienta", "andar_herramienta", "agachado_reposo", "agachado_andar", "caer"]:
					var a := _anim.get_animation(nombre)
					if a != null:
						a.loop_mode = Animation.LOOP_LINEAR
				for nombre in ["herramienta", "saltar", "aterrizar", "usar_pico", "usar_hacha", "usar_azada", "usar_regadera", "usar_hoz", "usar_semilla", "usar_cana"]:
					var a := _anim.get_animation(nombre)
					if a != null:
						a.loop_mode = Animation.LOOP_NONE
			_configurar_soporte_mano(inst)
			_reproducir("reposo", 0.0)
			return
	_modelo_de_prueba()


## Cápsula de prueba con una «nariz» en el frente (+Z) para ver hacia dónde mira.
func _modelo_de_prueba() -> void:
	var raiz := Node3D.new()
	raiz.name = "ModeloPrueba"
	_modelo.add_child(raiz)
	_modelo_visual = raiz
	_visual = raiz
	var cuerpo := MeshInstance3D.new()
	var capsula := CapsuleMesh.new()
	capsula.radius = 0.35
	capsula.height = 1.8
	cuerpo.mesh = capsula
	cuerpo.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.62, 0.35)
	cuerpo.material_override = mat
	raiz.add_child(cuerpo)
	var nariz := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(0.18, 0.18, 0.3)
	nariz.mesh = caja
	nariz.position = Vector3(0, 1.45, 0.38)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.95, 0.8, 0.45)
	nariz.material_override = mat2
	raiz.add_child(nariz)


func _reproducir(nombre: String, mezcla: float = 0.15, velocidad: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(nombre):
		return
	_anim.speed_scale = velocidad
	var es_golpe := nombre == "herramienta" or nombre.begins_with("usar_")
	if _anim_actual != nombre or es_golpe:
		_anim_actual = nombre
		_anim.play(nombre, mezcla)


func _configurar_soporte_mano(inst: Node3D) -> void:
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	var hueso := _buscar_hueso_mano_derecha(sk)
	if hueso.is_empty():
		return
	var adjunto := BoneAttachment3D.new()
	adjunto.name = "ManoDerecha"
	adjunto.bone_name = hueso
	sk.add_child(adjunto)
	var soporte := Node3D.new()
	soporte.name = "SoporteHerramienta"
	# Centro de la palma cerrada de DEF-hand.R (-X palma, +Y hacia dedos, +Z adelante)
	soporte.position = Vector3(-0.025, 0.078, 0.005)
	adjunto.add_child(soporte)
	_mano_soporte = soporte


func _buscar_hueso_mano_derecha(sk: Skeleton3D) -> String:
	for cand in ["DEF-hand.R", "hand.R", "Hand.R", "RightHand", "mixamorigRightHand", "J_Bip_R_Hand"]:
		if sk.find_bone(cand) != -1:
			return cand
	for i in range(sk.get_bone_count()):
		var b := sk.get_bone_name(i)
		var l := b.to_lower()
		if ("hand" in l or "mano" in l) and (".r" in l or "_r" in l or "right" in l or "der" in l):
			return b
	return ""


func _on_mano_cambiada(_ranura: int) -> void:
	_actualizar_objeto_en_mano()


func _actualizar_objeto_en_mano() -> void:
	var obj := Juego.objeto_activo()
	var id := str(obj.get("id", ""))
	var nivel := Juego.nivel(id) if not id.is_empty() else 0
	if id == _objeto_en_mano and nivel == _nivel_en_mano:
		return
	_objeto_en_mano = id
	_nivel_en_mano = nivel
	if _herramienta_nodo != null and is_instance_valid(_herramienta_nodo):
		if _herramienta_nodo.get_parent() != null:
			_herramienta_nodo.get_parent().remove_child(_herramienta_nodo)
		_herramienta_nodo.queue_free()
		_herramienta_nodo = null
	if _mano_soporte == null or id.is_empty():
		return
	var clave := _modelo_para_objeto(id)
	if clave.is_empty():
		return
	var ps: PackedScene = _modelos_mano.get(clave, null) as PackedScene
	if ps == null:
		var ruta := RUTA_HERRAMIENTAS % clave
		if not ResourceLoader.exists(ruta):
			return
		ps = load(ruta) as PackedScene
		if ps == null:
			return
		_modelos_mano[clave] = ps
	var inst := ps.instantiate() as Node3D
	if inst == null:
		return
	_aplicar_nivel_herramienta(inst, id, nivel)
	_mano_soporte.add_child(inst)
	_herramienta_nodo = inst


func _modelo_para_objeto(id: String) -> String:
	match id:
		"pico", "hacha", "azada", "regadera", "hoz", "cana":
			return id
		"guadana":
			return "hoz"
		"madera":
			return "madera_mano"
		"piedra", "cobre", "hierro", "cuarzo", "ambar_valle":
			return "mineral"
		"remedio_plaga", "elixir_sierra", "cafe", "caldo":
			return "frasco"
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	if tipo == "semilla":
		return "semillas"
	if not id.is_empty():
		return "cesta_mano"
	return ""


func _animacion_de_herramienta(id: String) -> String:
	match id:
		"pico":
			return "usar_pico"
		"hacha":
			return "usar_hacha"
		"azada":
			return "usar_azada"
		"regadera":
			return "usar_regadera"
		"hoz", "guadana":
			return "usar_hoz"
		"cana":
			return "usar_cana"
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	if tipo == "semilla":
		return "usar_semilla"
	return "usar_semilla"


func _aplicar_nivel_herramienta(raiz: Node3D, id: String, nivel: int) -> void:
	if nivel <= 0 or not (id in ["pico", "hacha", "azada", "regadera", "hoz", "guadana"]):
		return
	var tint := Color.WHITE
	match nivel:
		1:
			tint = Color(0.86, 0.48, 0.28) # cobre
		2:
			tint = Color(0.76, 0.83, 0.90) # hierro templado
		_:
			tint = Color(0.92, 0.96, 1.00) # cuarzo
	for n in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(s) as StandardMaterial3D
			if mat != null and mat.metallic >= 0.5 and not mat.resource_name.contains("Laton"):
				var dup := mat.duplicate() as StandardMaterial3D
				dup.albedo_color = dup.albedo_color * tint
				mi.set_surface_override_material(s, dup)
