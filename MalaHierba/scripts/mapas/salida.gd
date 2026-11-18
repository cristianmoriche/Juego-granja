class_name Salida
extends Area3D
## Salida entre mapas: al entrar el jugador, Escenas.ir_a_mapa(destino, llegada).
## La crea Mapa a partir de datos/conexiones.json. Se «arma» cuando el jugador ya está colocado, para no
## dispararse con el que acaba de llegar y está dentro de otra salida.

@export var destino: String = ""
@export var llegada: String = "Spawn_Protagonista"
@export var texto: String = ""
@export var radio: float = 2.5

const MARGEN_MS := 700

var _activa: bool = false
var _armada_ms: int = 0
var _bloqueada: bool = false
var _etiqueta: Label3D = null
var _t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2          # solo el jugador
	monitoring = false
	monitorable = false
	var forma := CollisionShape3D.new()
	var cil := CylinderShape3D.new()
	cil.radius = radio
	cil.height = 8.0
	forma.shape = cil
	forma.position = Vector3(0, 2.0, 0)
	add_child(forma)
	if not texto.is_empty():
		_etiqueta = Label3D.new()
		_etiqueta.text = texto
		_etiqueta.font = Estilo.fuente()
		_etiqueta.font_size = 44
		_etiqueta.pixel_size = 0.006
		_etiqueta.outline_size = 12
		_etiqueta.modulate = Color(1.0, 0.92, 0.7, 0.0)
		_etiqueta.outline_modulate = Color(0, 0, 0, 0.0)
		_etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_etiqueta.no_depth_test = true
		_etiqueta.position = Vector3(0, 2.6, 0)
		add_child(_etiqueta)
	body_entered.connect(_al_entrar)
	body_exited.connect(_al_salir)


func armar() -> void:
	_activa = true
	_bloqueada = false
	_armada_ms = Time.get_ticks_msec()
	monitoring = true


func _al_entrar(cuerpo: Node3D) -> void:
	if not _activa or not cuerpo.is_in_group("jugador"):
		return
	if Time.get_ticks_msec() - _armada_ms < MARGEN_MS:
		_bloqueada = true      # ya estaba dentro al empezar: hasta que salga no cuenta
		return
	if _bloqueada or Escenas.en_transicion:
		return
	Escenas.ir_a_mapa(destino, llegada)


func _al_salir(cuerpo: Node3D) -> void:
	if cuerpo.is_in_group("jugador"):
		_bloqueada = false


func _process(delta: float) -> void:
	if _etiqueta == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.15
	var j := Escenas.jugador()
	var a := 0.0
	if j != null:
		var d := j.global_position.distance_to(global_position)
		a = clampf(remap(d, 14.0, 7.0, 0.0, 0.9), 0.0, 0.9)
	_etiqueta.modulate.a = a
	_etiqueta.outline_modulate.a = a * 0.9
