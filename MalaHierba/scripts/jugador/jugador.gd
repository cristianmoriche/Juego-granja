class_name Jugador
extends CharacterBody3D
## Leo: se mueve con WASD relativo a la cámara, interactúa con E y usa lo que lleva en la mano con el clic izquierdo.
## V alterna los ojos y el hombro. El ratón y la palanca derecha orientan la mira.
## El Interactuable bajo la mira se resalta. Los receptores «usable» reciben
## usar(id_objeto, punto, jugador) -> bool y deciden el gasto de energía.
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
const VISTA_LEO := preload("res://scripts/jugador/vista_leo.gd")
const APUNTADO := preload("res://scripts/jugador/apuntado_jugador.gd")
const DURACION_HERRAMIENTA := 0.6
const GIRO_CAMARA_RATON := 0.0055
const PAUSA_AVISO_USO := 0.7
const CAPA_LIMITES := 32      # capa 6 «limites»: muros invisibles del borde de cada mapa (Mapa los crea)
const CAPA_SOLO_JUGADOR := 64 # capa 7 «solo_jugador»: techo y maderas de las cuevas (la cámara no choca con ellos)

@onready var _modelo: Node3D = $Modelo
@onready var _farol: OmniLight3D = $Farol

var camara: CamaraJuego = null
var combate: CombateJugador
var direccion: Vector3 = Vector3(0, 0, 1)     # hacia dónde mira (plano XZ, normalizado)
var _activo: bool = false
var _anim: AnimationPlayer = null
var _anim_actual: String = ""
var _anim_en_pausa := false
var _correr_sin_aire := false
var _t_herramienta: float = 0.0
var _hay_cartel: bool = false
var _objetivo: Node3D = null
var _apuntado: Dictionary = {}
var _pos_segura: Vector3 = Vector3.ZERO
var _t_segura: float = 0.0
var _modelo_visual: Node3D = null
var _resaltador: Resaltador = null
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
var _izquierda_soporte: Node3D = null
var _escudo_nodo: Node3D
var _escudo_actual := ""
var _carcaj_soporte: Node3D = null
var _carcaj_nodo: Node3D = null
var _carcaj_actual := ""
var _arco_primera: Node3D = null
var _herramienta_nodo: Node3D = null
var _objeto_en_mano: String = ""
var _nivel_en_mano: int = -1
var _modelos_mano: Dictionary = {}
var _vista_leo := VISTA_LEO.new()
var _farol_soporte_cadera: Node3D = null
var _farol_primera: Node3D = null
var _plato_primera: Node3D = null
var _plato_primera_id: String = ""
var _farol_tercera: Node3D = null
var _antorcha_primera: Node3D = null
var _antorcha_tercera: Node3D = null
var _farol_energia_base: float = 2.5
var _farol_tiempo: float = 0.0
var _luz_manual: int = 0   # 0 auto, 1 forzada encendida, -1 forzada apagada
var _t_respiracion: float = 0.0


func _ready() -> void:
	combate = CombateJugador.new(self)
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
	camara.ancla_ojos = _vista_leo.ancla_ojos
	add_child(camara)
	_resaltador = Resaltador.new()
	_resaltador.name = "Resaltador"
	add_child(_resaltador)
	camara.vista_actualizada.connect(_al_actualizar_vista)
	_farol.set_meta("sombra_h03", true)
	_farol.visible = false
	_preparar_modelos_farol()
	if not Juego.ranura_cambiada.is_connected(_on_mano_cambiada):
		Juego.ranura_cambiada.connect(_on_mano_cambiada)
	if not Juego.inventario_cambiado.is_connected(_actualizar_objeto_en_mano):
		Juego.inventario_cambiado.connect(_actualizar_objeto_en_mano)
	if not Juego.partida_cambiada.is_connected(_actualizar_objeto_en_mano):
		Juego.partida_cambiada.connect(_actualizar_objeto_en_mano)
	Juego.equipo_cambiado.connect(_actualizar_escudo)
	Juego.equipo_cambiado.connect(_actualizar_carcaj)
	Juego.equipo_cambiado.connect(_actualizar_estado_luz)
	Juego.hora_cambiada.connect(func(_m: int) -> void: _actualizar_estado_luz())
	_actualizar_escudo()
	_actualizar_carcaj()
	_actualizar_objeto_en_mano()
	_actualizar_escudo()


## La activa Escenas cuando ya está colocado y con suelo debajo.
func activar() -> void:
	_activo = true


## Coloca a Leo de golpe y orienta el cuerpo y la cámara al aparecer.
func colocar(pos: Vector3, _giro_cuerpo: float, giro_camara: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_t_bufer_salto = 0.0
	_t_coyote = 0.0
	_t_atasco_aire = 0.0
	_pos_ant = pos
	_pos_segura = pos
	if not camara.primera_persona and not is_nan(_giro_cuerpo):
		direccion = Vector3(sin(_giro_cuerpo), 0.0, cos(_giro_cuerpo)).normalized()
	else:
		direccion = Vector3(0, 0, -1).rotated(Vector3.UP, giro_camara)
	_modelo.rotation.y = atan2(direccion.x, direccion.z)
	camara.fijar(pos, giro_camara)
	_vista_leo.mostrar_primera(camara.cabeza_oculta)


## Luz de farol en interiores (la mina) y útil de noche o manualmente en exterior con farol/antorcha equipado.
func configurar_para_mapa(mapa: Node) -> void:
	_mapa = mapa
	_luz_manual = 0
	_actualizar_estado_luz()
	camara.poner_interior(bool(mapa.get("interior")) if mapa != null else false)


func _actualizar_estado_luz() -> void:
	if _farol == null:
		return
	var interior := bool(_mapa.get("interior")) if _mapa != null else false
	var es_mina := str(_mapa.get("id_mapa")) == "mina_interior" if _mapa != null else false
	var eq_luz := str(Juego.equipo.get("luz", ""))
	var es_noche := Juego.minutos >= 1110 or Juego.minutos < 390
	var encender := false
	if interior:
		encender = _luz_manual != -1
	elif not eq_luz.is_empty():
		encender = (_luz_manual == 1) or (_luz_manual == 0 and es_noche)
	_farol.visible = encender
	if eq_luz == "antorcha":
		_farol.light_color = Color(1.0, 0.64, 0.28)
		_farol_energia_base = 2.35
		_farol.omni_range = 13.5
		_farol.omni_attenuation = 1.35
	elif eq_luz == "farol_mano":
		_farol.light_color = Color(1.0, 0.86, 0.56)
		_farol_energia_base = 2.85
		_farol.omni_range = 17.5
		_farol.omni_attenuation = 1.2
	elif es_mina:
		_farol.light_color = Color(1.0, 0.80, 0.50)
		_farol_energia_base = 2.55
		_farol.omni_range = 15.5
		_farol.omni_attenuation = 1.25
	else:
		_farol.light_color = Color(1.0, 0.85, 0.60)
		_farol_energia_base = 1.95
		_farol.omni_range = 12.0
		_farol.omni_attenuation = 1.4
	_farol.light_energy = _farol_energia_base if encender else 0.0
	GraficaH03.ajustar_luz(_farol, int(Ajustes.valores.calidad))
	_actualizar_visibilidad_farol()


func alternar_luz_equipable() -> bool:
	if str(Juego.equipo.get("luz", "")).is_empty():
		for i in Juego.HUECOS:
			var id_h := str(Juego.inventario[i].get("id", ""))
			if id_h == "farol_mano" or id_h == "antorcha":
				Juego.equipar(i)
				break
	if str(Juego.equipo.get("luz", "")).is_empty() and not (bool(_mapa.get("interior")) if _mapa != null else false):
		Interfaz.mensaje("Equipa una antorcha o un farol de hierro desde el inventario (I).")
		return false
	_luz_manual = -1 if _farol.visible else 1
	_actualizar_estado_luz()
	Audio.reproducir("ui_clic")
	return _farol.visible


func fijar_energia_base_farol(energia: float) -> void:
	_farol_energia_base = energia
	_farol.light_energy = energia


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
	if estado_mov == "suelo" and rapidez <= 0.4 and _anim != null and _anim.has_animation("combate_reposo") \
		and (_escudo_nodo != null or Datos.objeto(_objeto_en_mano).get("tipo") == "arma"):
		_reproducir("combate_reposo", 0.12)
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


func _actualizar_realismo_audio(corriendo: bool, delta: float) -> void:
	_t_respiracion = maxf(0.0, _t_respiracion - delta)
	if (corriendo or _correr_sin_aire) and Juego.resistencia < 26.0 and _t_respiracion <= 0.0:
		Audio.reproducir("respiracion_fatiga", 0.06)
		_t_respiracion = 2.2
	if _mapa == null or not is_instance_valid(_mapa):
		Audio.poner_nivel_agua(0.0)
		return
	var id := str(_mapa.get("id_mapa"))
	var cercania := 0.0
	var p := global_position
	match id:
		"bosque_norte":
			var z_rio := -2.0 + 7.5 * sin(p.x * 0.055 + 0.4) + 3.0 * cos(p.x * 0.11)
			cercania = clampf(1.0 - absf(p.z - z_rio) / 14.0, 0.0, 1.0)
		"costa_lago":
			if p.z > -4.0:
				cercania = clampf((p.z + 4.0) / 16.0, 0.0, 1.0)
		"robledal_niebla":
			var dist_e := Vector2(p.x - 10.0, p.z - 20.0).length()
			cercania = clampf(1.0 - dist_e / 16.0, 0.0, 1.0)
		"ruinas_valle":
			if p.z > 8.0:
				cercania = clampf((p.z - 8.0) / 16.0, 0.0, 1.0)
	Audio.poner_nivel_agua(cercania)


func _sonido_paso() -> String:
	var id := str(_mapa.get("id_mapa")) if _mapa != null else ""
	var p := global_position
	if id == "mina_interior" or id == "mina_exterior":
		return "paso_piedra"
	if _mapa != null and bool(_mapa.get("interior")):
		return "paso_madera"
	# Puentes y muelle de madera
	if id == "bosque_norte" and absf(p.x) < 3.0 and absf(p.z - 0.6) < 4.6:
		return "paso_madera"
	if id == "costa_lago" and absf(p.x) < 2.2 and p.z > 10.0:
		return "paso_madera"
	# Orillas y agua somera
	if id in ["bosque_norte", "costa_lago", "robledal_niebla", "ruinas_valle"] and p.y < 0.22:
		return "paso_agua"
	if id == "pueblo":
		return "paso_piedra" if Vector2(p.x, p.z).length() < 12.0 else "paso_tierra"
	if id == "sierra_mirador" or (id == "ruinas_valle" and Vector2(p.x + 2.0, p.z + 5.0).length() < 14.0):
		return "paso_piedra"
	if id == "granja" and absf(p.x) < 15.0 and absf(p.z) < 12.0:
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
	var libre_ui: bool = not Interfaz.ocupada() and not Escenas.en_transicion
	if libre_ui:
		camara.entrada_mando(Input.get_vector("camara_izquierda", "camara_derecha", "camara_arriba", "camara_abajo"), delta)
	var libre_combate: bool = libre_ui and not Interfaz.apuntando_decoracion and Juego.vida > 0.0
	combate.actualizar(delta, libre_combate and _t_herramienta <= 0.0, Input.is_action_pressed("bloquear"))
	var libre: bool = libre_ui and Juego.vida > 0.0 and _t_herramienta <= 0.0 and not combate.ocupado() and not combate.bloqueando
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
	if _correr_sin_aire and Juego.resistencia >= 17.0:
		_correr_sin_aire = false
	if entrada.length() > 0.01:
		# Relativo a la cámara: W va hacia donde ella mira, aunque esté girada del todo.
		var dir3 := Vector3(entrada.x, 0.0, entrada.y).rotated(Vector3.UP, camara.yaw)
		var tensando_arco: bool = combate.es_arco_activo() and (combate.apuntando_arco or combate.tension_arco > 0.0)
		if Input.is_action_pressed("correr") and not agachado and not _correr_sin_aire and not tensando_arco:
			corriendo = Juego.gastar_resistencia(16.0 * delta)
			_correr_sin_aire = not corriendo
		var vel := (VEL_AGACHADO if agachado else (VEL_CORRER if corriendo else VEL_ANDAR)) * (1.0 + Juego.bono_velocidad())
		if tensando_arco:
			vel *= 0.68
		objetivo_vel = dir3 * vel
		if not combate.bloqueando and not tensando_arco and not is_instance_valid(combate.objetivo_fijado):
			direccion = dir3.normalized()
	if libre_ui and not corriendo and not combate.bloqueando:
		Juego.recuperar_resistencia(delta)
	if camara.primera_persona and not combate.ocupado():
		direccion = Vector3.FORWARD.rotated(Vector3.UP, camara.yaw)
	if combate.tiempo_esquiva > 0.0:
		objetivo_vel = combate.velocidad_esquiva()
	objetivo_vel += combate.retroceso
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
	if combate.tiempo_esquiva > 0.0:
		velocity.x = objetivo_vel.x
		velocity.z = objetivo_vel.z
	else:
		if combate.ocupado() or combate.bloqueando:
			acel = maxf(acel, 48.0)
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
	if _anim != null:
		if combate.pausa_de_impacto() and not _anim_en_pausa:
			_anim.pause()
			_anim_en_pausa = true
		elif not combate.pausa_de_impacto() and _anim_en_pausa:
			_anim_en_pausa = false
			if combate.ocupado():
				_anim.play()
	if _t_herramienta > 0.0 or combate.ocupado() or combate.bloqueando or Juego.vida <= 0.0:
		pass
	else:
		_animar_estado(rapidez, corriendo)
		_actualizar_pasos(rapidez, corriendo, delta)
	_actualizar_realismo_audio(corriendo, delta)
	_actualizar_pose(delta)
	_actualizar_farol(delta, rapidez, ahora_en_suelo)
	_actualizar_arco_primera(delta)

	# La cámara baja la mira al agacharse y la sube al levantarse, sin tirones.
	_altura_cam = lerpf(_altura_cam, _forma.height / EscalaPersonaje.ALTURA_PIE, 1.0 - exp(-9.0 * delta))
	camara.altura_relativa = _altura_cam
	camara.rapidez = rapidez if ahora_en_suelo else 0.0
	camara.aterrizaje = _t_aterrizaje / TIEMPO_ATERRIZAJE

	# Red de seguridad: si cae por una sima o acaba fuera del polígono de límites (los muros de Mapa lo
	# impiden; esto es por si algo falla), vuelve al último sitio firme dentro.
	_t_segura -= delta
	var dentro := dentro_de_limites()
	if is_on_floor() and _t_segura <= 0.0 and dentro:
		_pos_segura = global_position
		_t_segura = 0.5
	if not dentro or global_position.y < _pos_segura.y - 11.0:
		global_position = _pos_segura + Vector3(0, 0.5, 0)
		velocity = Vector3.ZERO


# --- Interacción ---------------------------------------------------------------------------

func _al_actualizar_vista() -> void:
	_vista_leo.mostrar_primera(camara.cabeza_oculta)
	_resaltador.primera_persona = camara.cabeza_oculta
	_actualizar_visibilidad_farol()
	if _activo:
		_t_aviso_uso = maxf(_t_aviso_uso - get_physics_process_delta_time(), 0.0)
		_actualizar_interactuable()


## Impacto de la mira. Puede incluir punto, normal, colisión e interactuable a alcance.
func apuntar() -> Dictionary:
	return APUNTADO.calcular(camara)


## Impacto de la última actualización de la cámara, para marcas y vistas previas.
func apuntado_actual() -> Dictionary:
	return _apuntado


func encuadrar_interlocutor(vecino: Node3D) -> void:
	camara.interlocutor = vecino


func _actualizar_interactuable() -> void:
	var libre: bool = not Interfaz.ocupada() and not Escenas.en_transicion
	_apuntado = apuntar() if libre else {}
	var deco := get_tree().get_first_node_in_group("decoracion_casa")
	var decorando := deco != null and bool(deco.call("esta_decorando"))
	_objetivo = _apuntado.get("interactuable") as Interactuable if not decorando else null
	if _objetivo is Interactuable and not (_objetivo as Interactuable).herramienta.is_empty() \
		and Datos.objeto(str(Juego.objeto_activo().get("id", ""))).get("tipo") == "arma":
		_objetivo = null
	_resaltador.apuntar(_objetivo)
	var texto := ""
	if _objetivo is Interactuable:
		var zona := _objetivo as Interactuable
		texto = Ajustes.pista("interactuar" if zona.herramienta.is_empty() else "usar") + "  ·  " + zona.texto_interaccion()
	elif libre and not decorando and _apuntado.has("punto"):
		var parcelas := get_tree().get_first_node_in_group("parcelas_apuntables") as Parcelas
		if parcelas != null and not parcelas.celda_apuntada(_apuntado).is_empty():
			var id := str(Juego.objeto_activo().get("id", ""))
			var verbo := str({"azada": "Cavar", "regadera": "Regar", "hoz": "Segar", "hacha": "Talar", "pico": "Picar"}.get(id, ""))
			if Datos.objeto(id).get("tipo", "") == "semilla":
				verbo = "Sembrar"
			if not verbo.is_empty():
				texto = Ajustes.pista("usar") + "  ·  " + verbo
	Interfaz.enfocar_mira(not texto.is_empty())
	if not texto.is_empty():
		if Interfaz.texto_accion() != texto:
			Interfaz.mostrar_accion(texto)
		_hay_cartel = true
	elif _hay_cartel:
		Interfaz.ocultar_accion()
		_hay_cartel = false


func _unhandled_input(event: InputEvent) -> void:
	if not _activo or Interfaz.ocupada() or Escenas.en_transicion:
		return
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		var arrastre: bool = Interfaz.apuntando_decoracion and bool(m.button_mask & MOUSE_BUTTON_MASK_RIGHT)
		if Interfaz.cursor_de_juego or arrastre:
			var factor := GIRO_CAMARA_RATON * float(Ajustes.valores.sensibilidad)
			camara.girar(-m.screen_relative.x * factor)
			camara.inclinar(m.screen_relative.y * factor)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("usar") and combate.soltar_ataque():
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("alternar_vista"):
		Ajustes.poner("vista", 1 if camara.primera_persona else 0)
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("alternar_luz") and event.is_action_pressed("alternar_luz"):
		alternar_luz_equipable()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("camara_reiniciar"):
		camara.reiniciar_vista()
		get_viewport().set_input_as_handled()
		return
	var deco := get_tree().get_first_node_in_group("decoracion_casa")
	if deco != null and bool(deco.call("esta_decorando")):
		if event.is_action_pressed("ui_cancel"):
			deco.call("salir_modo_decorar")
		elif event.is_action_pressed("usar") and event is InputEventJoypadButton:
			deco.call("girar_mueble")
		elif event.is_action_pressed("interactuar") or event.is_action_pressed("usar"):
			deco.call("accion_principal")
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("esquivar"):
		combate.esquivar(Input.get_vector("mover_izquierda", "mover_derecha", "mover_arriba", "mover_abajo"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fijar_objetivo"):
		combate.cambiar_objetivo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("saltar") and (not event is InputEventJoypadMotion or Input.is_action_just_pressed_by_event("saltar", event)):
		solicitar_salto()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interactuar"):
		_interactuar()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("usar"):
		_usar(true)
		get_viewport().set_input_as_handled()


func _interactuar() -> void:
	_actualizar_interactuable()
	var zona := _objetivo as Interactuable
	if zona != null and zona.herramienta.is_empty():
		_activar_interactuable(zona)


func _activar_interactuable(zona: Interactuable) -> void:
	_orientar_uso(zona.global_position)
	zona.interactuar(self)


func _orientar_uso(punto: Vector3) -> void:
	direccion = direccion_de_uso(punto)


func direccion_de_uso(punto: Vector3) -> Vector3:
	var d := (punto - global_position).slide(Vector3.UP)
	if camara.primera_persona:
		return Vector3.FORWARD.rotated(Vector3.UP, camara.yaw)
	return d.normalized() if d.length_squared() > 0.04 else direccion


func _usar(desde_entrada: bool = false) -> void:
	if Juego.vida <= 0.0:
		return
	var objetivo_mira := apuntar()
	var zona := objetivo_mira.get("interactuable") as Interactuable
	# Con un enemigo en la mira se ataca aunque haya un punto interactuable detrás (raíles, carteles…).
	if zona != null and objetivo_mira.get("colision") is Enemigo:
		zona = null
	if zona != null and zona.herramienta.is_empty():
		_activar_interactuable(zona)
		return
	if _t_herramienta > 0.0:
		return
	var obj := Juego.objeto_activo()
	var id := str(obj.get("id", ""))
	var datos := Datos.objeto(id)
	var impacto := objetivo_mira.get("colision") as Node
	if desde_entrada and datos.get("tipo") == "arma":
		combate.preparar_ataque(id, impacto)
		return
	if zona != null:
		if id == zona.herramienta:
			_activar_interactuable(zona)
		elif _t_aviso_uso <= 0.0:
			_t_aviso_uso = PAUSA_AVISO_USO
			Interfaz.mensaje("Necesitas usar %s." % Datos.nombre_objeto(zona.herramienta))
		return
	if id.is_empty():
		return
	if datos.get("tipo") == "equipo":
		Juego.equipar(Juego.ranura)
		return
	if desde_entrada and combate.preparar_ataque(id, impacto):
		return
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
	var punto: Vector3 = objetivo_mira.get("punto", Vector3.INF)
	var destino := objetivo_mira.get("colision") as Node
	while destino != null and not destino.is_in_group("usable"):
		destino = destino.get_parent()
	if destino == null and punto.is_finite():
		var parcelas := get_tree().get_first_node_in_group("parcelas_apuntables") as Parcelas
		if parcelas != null and not parcelas.celda_apuntada(objetivo_mira).is_empty():
			destino = parcelas
	if id == "cana" and destino == null:
		destino = get_tree().get_first_node_in_group("zona_pesca")
		if destino != null:
			punto = _lance_de_pesca()
	var avisos_antes: int = Interfaz.avisos_emitidos
	if destino != null and punto.is_finite():
		_orientar_uso(punto)
		if bool(destino.call("usar", id, punto, self)):
			animar_herramienta()
			return
	# Nadie ha hecho nada: si tampoco ha avisado de por qué, lo decimos nosotros (sin repetirlo en cada clic).
	if Interfaz.avisos_emitidos == avisos_antes and _t_aviso_uso <= 0.0:
		_t_aviso_uso = PAUSA_AVISO_USO
		Interfaz.mensaje(motivo_sin_efecto(id))


func _lance_de_pesca() -> Vector3:
	# El agua no tiene cuerpo físico. Se toma un punto de la mira a corta distancia por delante de Leo.
	var origen := camara.camara.global_position
	var frente := camara.direccion_mira()
	var distancia := maxf(0.0, (camara.posicion_mano() - origen).dot(frente)) + APUNTADO.ALCANCE
	var impacto := camara.rayo_central(CamaraJuego.MASCARA_SOLIDA, distancia)
	var normal: Vector3 = impacto.get("normal", Vector3.UP)
	if normal.y < 0.25:
		return Vector3.INF
	var punto: Vector3 = impacto.get("position", origen + frente * distancia)
	var obstaculo := camara.rayo_entre(camara.posicion_mano(), punto, CamaraJuego.MASCARA_SOLIDA)
	if not obstaculo.is_empty() and punto.distance_to(obstaculo.position) > 0.15:
		return Vector3.INF
	return punto


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
				for nombre in ["reposo", "andar", "reposo_herramienta", "andar_herramienta", "agachado_reposo", "agachado_andar", "caer", "combate_reposo"]:
					if _anim.has_animation(nombre):
						_anim.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR
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


func animar_combate(nombre: String, duracion: float) -> void:
	if _anim == null or not _anim.has_animation(nombre):
		return
	var clip := _anim.get_animation(nombre)
	_anim_actual = nombre
	_anim.speed_scale = clip.length / duracion if duracion > 0.0 else 1.0
	_anim.play(nombre, 0.07)
	_anim.seek(0.0)


func recibir_ataque(cantidad: float, atacante: Enemigo, origen: Vector3, admite_parada: bool = true) -> void:
	combate.recibir_ataque(cantidad, atacante, origen, admite_parada)


func caer_desmayado() -> void:
	animar_combate("combate_desmayo", 0.68)
	velocity = Vector3.ZERO


func _configurar_soporte_mano(inst: Node3D) -> void:
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	_vista_leo.preparar(inst, sk)
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
	var izquierda := BoneAttachment3D.new()
	izquierda.name = "ManoIzquierda"
	izquierda.bone_name = "DEF-hand.L"
	if sk.find_bone(izquierda.bone_name) >= 0:
		sk.add_child(izquierda)
		var empunadura := Node3D.new()
		empunadura.position = Vector3(0.025, 0.074, 0.006)
		izquierda.add_child(empunadura)
		_izquierda_soporte = empunadura
	else:
		izquierda.free()
	var cadera := BoneAttachment3D.new()
	cadera.name = "CaderaIzquierda"
	cadera.bone_name = "DEF-spine"
	if sk.find_bone(cadera.bone_name) >= 0:
		sk.add_child(cadera)
		var ancla := Node3D.new()
		ancla.position = Vector3(-0.24, 0.02, 0.09)
		cadera.add_child(ancla)
		_farol_soporte_cadera = ancla
	else:
		cadera.free()
	var espalda := BoneAttachment3D.new()
	espalda.name = "EspaldaCarcaj"
	espalda.bone_name = "DEF-spine"
	if sk.find_bone(espalda.bone_name) >= 0:
		sk.add_child(espalda)
		var ancla_carcaj := Node3D.new()
		ancla_carcaj.position = Vector3(0.14, 0.30, -0.22)
		ancla_carcaj.rotation_degrees = Vector3(-14.0, 14.0, -30.0)
		ancla_carcaj.scale = Vector3.ONE * 1.15
		espalda.add_child(ancla_carcaj)
		_carcaj_soporte = ancla_carcaj
	else:
		espalda.free()


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
	_limpiar_plato_primera()
	_limpiar_arco_primera()
	if _mano_soporte == null or id.is_empty():
		_actualizar_visibilidad_farol()
		return
	var datos := Datos.objeto(id)
	var es_arma: bool = datos.get("tipo") == "arma"
	var es_arco: bool = str(datos.get("subtipo", "")) == "arco"
	var clave := str(datos.get("modelo", "")) if es_arma else _modelo_para_objeto(id)
	if datos.get("tipo") == "equipo":
		_actualizar_visibilidad_farol()
		return
	if clave.is_empty():
		_actualizar_visibilidad_farol()
		return
	var ps: PackedScene = _modelos_mano.get(clave, null) as PackedScene
	if ps == null:
		var ruta := "res://assets/combate/%s.glb" % clave if es_arma else RUTA_HERRAMIENTAS % clave
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
	if es_arma:
		_aplicar_temple(inst, int(datos.get("grado", 0)))
	if es_arco:
		inst.rotation_degrees = Vector3(0.0, 180.0, -10.0)
		inst.scale = Vector3.ONE * 0.88
		_tenido_arco(inst, id)
	_mano_soporte.add_child(inst)
	_herramienta_nodo = inst
	if str(datos.get("tipo", "")) == "comida" and camara != null and camara.camara != null:
		_crear_plato_primera(clave, id)
	elif es_arco and camara != null and camara.camara != null:
		_crear_arco_primera(clave, id)
	_actualizar_visibilidad_farol()


func _actualizar_escudo() -> void:
	if _izquierda_soporte == null:
		return
	var id := str(Juego.equipo.get("escudo", ""))
	if id == _escudo_actual:
		return
	_escudo_actual = id
	if is_instance_valid(_escudo_nodo):
		_izquierda_soporte.remove_child(_escudo_nodo)
		_escudo_nodo.queue_free()
		_escudo_nodo = null
	if id.is_empty() or not ResourceLoader.exists("res://assets/combate/escudo.glb"):
		_reubicar_farol_tercera()
		return
	var escena := load("res://assets/combate/escudo.glb") as PackedScene
	_escudo_nodo = escena.instantiate() as Node3D
	_aplicar_temple(_escudo_nodo, int(Datos.objeto(id).get("grado", 0)))
	_izquierda_soporte.add_child(_escudo_nodo)
	_reubicar_farol_tercera()


func _actualizar_carcaj() -> void:
	if _carcaj_soporte == null:
		return
	var id := str(Juego.equipo.get("carcaj", ""))
	if id == _carcaj_actual:
		return
	_carcaj_actual = id
	if is_instance_valid(_carcaj_nodo):
		if _carcaj_nodo.get_parent() != null:
			_carcaj_nodo.get_parent().remove_child(_carcaj_nodo)
		_carcaj_nodo.queue_free()
		_carcaj_nodo = null
	if id.is_empty() or not ResourceLoader.exists("res://assets/combate/carcaj_leo.glb"):
		return
	var escena := load("res://assets/combate/carcaj_leo.glb") as PackedScene
	if escena == null:
		return
	_carcaj_nodo = escena.instantiate() as Node3D
	if _carcaj_nodo != null:
		_carcaj_nodo.name = "CarcajEspalda"
		_carcaj_soporte.add_child(_carcaj_nodo)


func _preparar_modelos_farol() -> void:
	const RUTA_FAROL := "res://assets/mina/farol_leo.glb"
	if not ResourceLoader.exists(RUTA_FAROL):
		return
	var escena := load(RUTA_FAROL) as PackedScene
	if escena == null:
		return
	if camara != null and camara.camara != null:
		var f1 := escena.instantiate() as Node3D
		if f1 != null:
			f1.name = "FarolPrimeraPersona"
			f1.position = Vector3(-0.37, -0.15, -0.44)
			f1.scale = Vector3.ONE * 0.54
			f1.rotation_degrees = Vector3(3.0, 14.0, -3.0)
			_desactivar_sombras_farol(f1)
			camara.camara.add_child(f1)
			_farol_primera = f1
	var f3 := escena.instantiate() as Node3D
	if f3 != null:
		f3.name = "FarolTerceraPersona"
		f3.scale = Vector3.ONE * 0.85
		_desactivar_sombras_farol(f3)
		_farol_tercera = f3
		_reubicar_farol_tercera()
	const RUTA_ANTORCHA := "res://assets/mina/antorcha_leo.glb"
	if ResourceLoader.exists(RUTA_ANTORCHA):
		var esc_a := load(RUTA_ANTORCHA) as PackedScene
		if esc_a != null:
			if camara != null and camara.camara != null:
				var a1 := esc_a.instantiate() as Node3D
				if a1 != null:
					a1.name = "AntorchaPrimeraPersona"
					a1.position = Vector3(-0.35, -0.22, -0.44)
					a1.rotation_degrees = Vector3(18.0, 10.0, -8.0)
					_desactivar_sombras_farol(a1)
					camara.camara.add_child(a1)
					_antorcha_primera = a1
			var a3 := esc_a.instantiate() as Node3D
			if a3 != null:
				a3.name = "AntorchaTerceraPersona"
				a3.rotation_degrees = Vector3(14.0, 0.0, 0.0)
				_desactivar_sombras_farol(a3)
				_antorcha_tercera = a3
	_actualizar_visibilidad_farol()


static func _desactivar_sombras_farol(raiz: Node3D) -> void:
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _reubicar_farol_tercera() -> void:
	var destino: Node3D = _farol_soporte_cadera if (_escudo_nodo != null or _izquierda_soporte == null) else _izquierda_soporte
	if destino == null:
		destino = _modelo
	for nodo: Node3D in [_farol_tercera, _antorcha_tercera]:
		if nodo == null:
			continue
		if nodo.get_parent() != destino:
			if nodo.get_parent() != null:
				nodo.get_parent().remove_child(nodo)
			destino.add_child(nodo)
		nodo.position = Vector3.ZERO if destino != _modelo else Vector3(-0.34, 1.05, 0.14)


func _actualizar_visibilidad_farol() -> void:
	_reubicar_farol_tercera()
	var activo := _farol != null and _farol.visible
	var primera := camara != null and camara.cabeza_oculta
	var es_ant := str(Juego.equipo.get("luz", "")) == "antorcha"
	if _farol_primera != null:
		_farol_primera.visible = activo and primera and not es_ant
	if _farol_tercera != null:
		_farol_tercera.visible = activo and not primera and not es_ant
	if _antorcha_primera != null:
		_antorcha_primera.visible = activo and primera and es_ant
	if _antorcha_tercera != null:
		_antorcha_tercera.visible = activo and not primera and es_ant
	var mostrar_plato_1p := primera and _plato_primera != null and is_instance_valid(_plato_primera)
	if _plato_primera != null and is_instance_valid(_plato_primera):
		_plato_primera.visible = mostrar_plato_1p
	var mostrar_arco_1p := primera and _arco_primera != null and is_instance_valid(_arco_primera)
	if _arco_primera != null and is_instance_valid(_arco_primera):
		_arco_primera.visible = mostrar_arco_1p
	if _herramienta_nodo != null and is_instance_valid(_herramienta_nodo) and (not _plato_primera_id.is_empty() or _arco_primera != null):
		_herramienta_nodo.visible = not (mostrar_plato_1p or mostrar_arco_1p)


func _limpiar_plato_primera() -> void:
	_plato_primera_id = ""
	if _plato_primera != null and is_instance_valid(_plato_primera):
		if _plato_primera.get_parent() != null:
			_plato_primera.get_parent().remove_child(_plato_primera)
		_plato_primera.queue_free()
	_plato_primera = null


func _crear_plato_primera(clave: String, id: String) -> void:
	var ruta := RUTA_HERRAMIENTAS % clave
	if not ResourceLoader.exists(ruta):
		return
	var esc := load(ruta) as PackedScene
	if esc == null:
		return
	var p1 := esc.instantiate() as Node3D
	if p1 == null:
		return
	p1.name = "PlatoPrimeraPersona"
	p1.position = Vector3(0.28, -0.22, -0.44)
	p1.rotation_degrees = Vector3(14.0, -24.0, 4.0)
	p1.scale = Vector3.ONE * 0.92
	_desactivar_sombras_farol(p1)
	camara.camara.add_child(p1)
	_plato_primera = p1
	_plato_primera_id = id


func _limpiar_arco_primera() -> void:
	if _arco_primera != null and is_instance_valid(_arco_primera):
		if _arco_primera.get_parent() != null:
			_arco_primera.get_parent().remove_child(_arco_primera)
		_arco_primera.queue_free()
	_arco_primera = null


func _crear_arco_primera(clave: String, id: String) -> void:
	var ruta := "res://assets/combate/%s.glb" % clave
	if not ResourceLoader.exists(ruta):
		return
	var esc := load(ruta) as PackedScene
	if esc == null:
		return
	var a1 := esc.instantiate() as Node3D
	if a1 == null:
		return
	a1.name = "ArcoPrimeraPersona"
	a1.position = Vector3(-0.30, -0.14, -0.49)
	a1.rotation_degrees = Vector3(4.0, -10.0, -18.0)
	a1.scale = Vector3.ONE * 0.44
	_tenido_arco(a1, id)
	_desactivar_sombras_farol(a1)
	camara.camara.add_child(a1)
	_arco_primera = a1


func _tenido_arco(nodo: Node3D, id: String) -> void:
	if id != "arco_cristal" or nodo == null:
		return
	for mi: MeshInstance3D in nodo.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base != null and base.resource_name != "CuerdaArco":
				var mat_c := base.duplicate() as BaseMaterial3D
				if i == 0:
					mat_c.albedo_color = Color(0.56, 0.84, 0.98)
					mat_c.emission_enabled = true
					mat_c.emission = Color(0.32, 0.68, 0.95)
					mat_c.emission_energy_multiplier = 0.55
				else:
					mat_c.albedo_color *= Color(0.88, 0.95, 1.0)
				mi.set_surface_override_material(i, mat_c)


func _actualizar_arco_primera(delta: float) -> void:
	if _arco_primera == null or not is_instance_valid(_arco_primera) or not _arco_primera.visible:
		return
	var tens := combate.tension_arco if combate != null else 0.0
	var ap := combate != null and combate.apuntando_arco
	var k := 1.0 - exp(-12.0 * delta)
	var obj_pos := Vector3(
		lerpf(-0.30, -0.22, maxf(tens, 0.55 if ap else 0.0)),
		lerpf(-0.14, -0.09, maxf(tens, 0.55 if ap else 0.0)),
		lerpf(-0.49, -0.43, tens)
	)
	var obj_rot := Vector3(
		lerpf(4.0, -2.0, tens),
		lerpf(-10.0, -4.0, tens),
		lerpf(-18.0, -32.0, tens)
	)
	_arco_primera.position = _arco_primera.position.lerp(obj_pos, k)
	_arco_primera.rotation_degrees = _arco_primera.rotation_degrees.lerp(obj_rot, k)


func punto_salida_flecha() -> Vector3:
	if _arco_primera != null and is_instance_valid(_arco_primera) and _arco_primera.visible and camara != null and camara.camara != null:
		return _arco_primera.global_position + camara.camara.global_basis * Vector3(0.08, 0.04, -0.36)
	if camara != null and camara.camara != null:
		return camara.posicion_mano() + camara.direccion_mira() * 0.45 + Vector3.UP * 0.25
	return global_position + Vector3(0.0, 1.38, 0.0) + direccion.normalized() * 0.55


func _actualizar_farol(delta: float, rapidez: float, en_suelo: bool) -> void:
	if _farol == null or not _farol.visible:
		return
	_farol_tiempo += delta
	var reducir: bool = Ajustes.valores.reducir_movimiento
	var eq_ant := str(Juego.equipo.get("luz", "")) == "antorcha"
	var parpadeo := (0.91 + 0.09 * sin(_farol_tiempo * 14.5) + 0.05 * cos(_farol_tiempo * 23.0)) if eq_ant else (0.96 + 0.04 * sin(_farol_tiempo * 9.5) + 0.025 * cos(_farol_tiempo * 15.7))
	_farol.light_energy = _farol_energia_base * (1.0 if reducir else parpadeo)
	var izq_1p := _antorcha_primera if eq_ant else _farol_primera
	var izq_3p := _antorcha_tercera if eq_ant else _farol_tercera
	if izq_1p != null and izq_1p.visible:
		var amp := 0.0 if (reducir or not en_suelo) else clampf(rapidez / 6.0, 0.0, 1.0)
		var osc_x := sin(_farol_tiempo * 7.2) * 0.008 * amp
		var osc_y := absf(cos(_farol_tiempo * 7.2)) * 0.010 * amp
		var base_y := -0.22 if eq_ant else -0.15
		izq_1p.position = Vector3(-0.37 + osc_x, base_y - osc_y, -0.44)
		izq_1p.rotation_degrees = Vector3((18.0 if eq_ant else 3.0) + osc_y * 180.0, 14.0, -3.0 - osc_x * 260.0)
	if izq_3p != null and izq_3p.visible and not reducir:
		var balanceo := clampf(rapidez / 6.0, 0.0, 1.0) * 14.0 * sin(_farol_tiempo * 6.8)
		izq_3p.rotation_degrees = Vector3(balanceo, 0.0, sin(_farol_tiempo * 3.1) * 4.0)


func _aplicar_temple(raiz: Node3D, grado: int) -> void:
	var tonos := [Color(0.97, 0.76, 0.64), Color(0.85, 0.94, 1), Color(0.94, 0.96, 1)]
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base != null:
				var acabado := base.duplicate() as BaseMaterial3D
				acabado.albedo_color *= tonos[clampi(grado, 0, 2)]
				mi.set_surface_override_material(i, acabado)


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
	var rec := Datos.receta(id)
	if not rec.is_empty():
		return str(rec.get("modelo_mano", "plato_comida"))
	var tipo := str(Datos.objeto(id).get("tipo", ""))
	if tipo == "comida":
		return "cuenco_guiso" if id in ["caldo", "guiso"] else "plato_comida"
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
