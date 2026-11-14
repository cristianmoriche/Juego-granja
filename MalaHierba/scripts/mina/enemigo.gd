class_name Enemigo
extends CharacterBody3D
## Base del sistema de enemigos de la mina (T26).
## Permanece desactivado (ACTIVOS = false) hasta que lleguen los modelos 3D definitivos:
## usa una cápsula de marcador invisible para el jugador y lee sus estadísticas de datos/enemigos.json.

signal atacado(dano: float)
signal fallecido(enemigo: Enemigo)

const ACTIVOS := false
const RUTA_DATOS := "res://datos/enemigos.json"

static var _cache_definiciones: Array[Dictionary] = []
static var _cargado: bool = false

var id_enemigo: String = ""
var tipo: String = ""
var nombre_visible: String = ""
var vida_max: float = 25.0
var vida: float = 25.0
var dano: float = 8.0
var velocidad: float = 3.0
var alcance_deteccion: float = 10.0
var alcance_ataque: float = 1.4
var cadencia_ataque: float = 1.1
var rango_niveles: Vector2i = Vector2i(1, 20)
var modelo_ruta: String = ""

var activo: bool = ACTIVOS
var muerto: bool = false
var objetivo: Node3D = null
var marcador_capsula: MeshInstance3D = null
var _colision: CollisionShape3D = null
var _enfriamiento: float = 0.0


static func cargar_definiciones() -> Array[Dictionary]:
	if _cargado:
		return _cache_definiciones
	_cargado = true
	_cache_definiciones = []
	if not FileAccess.file_exists(RUTA_DATOS):
		push_warning("Enemigo: falta %s" % RUTA_DATOS)
		return _cache_definiciones
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(RUTA_DATOS)) != OK or not (json.data is Array):
		push_error("Enemigo: JSON inválido en %s" % RUTA_DATOS)
		return _cache_definiciones
	for item: Variant in json.data:
		if item is Dictionary:
			_cache_definiciones.append(Datos.normalizar_numeros(item as Dictionary))
	return _cache_definiciones


static func para_nivel(nivel: int) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for d: Dictionary in cargar_definiciones():
		var nv: Array = d.get("niveles", [1, 20])
		if nv.size() >= 2 and nivel >= int(nv[0]) and nivel <= int(nv[1]):
			r.append(d)
	if r.is_empty():
		return cargar_definiciones()
	return r


func _ready() -> void:
	set_physics_process(activo and not muerto)


func configurar(datos: Dictionary) -> void:
	id_enemigo = str(datos.get("id", "enemigo"))
	tipo = str(datos.get("tipo", "generico"))
	nombre_visible = str(datos.get("nombre", id_enemigo))
	vida_max = maxf(float(datos.get("vida", 25.0)), 1.0)
	vida = vida_max
	dano = maxf(float(datos.get("dano", 8.0)), 0.0)
	velocidad = maxf(float(datos.get("velocidad", 3.0)), 0.1)
	alcance_deteccion = maxf(float(datos.get("alcance_deteccion", 10.0)), 1.0)
	alcance_ataque = maxf(float(datos.get("alcance_ataque", 1.4)), 0.5)
	cadencia_ataque = maxf(float(datos.get("cadencia_ataque", 1.1)), 0.2)
	var nv: Array = datos.get("niveles", [1, 20])
	if nv.size() >= 2:
		rango_niveles = Vector2i(int(nv[0]), int(nv[1]))
	modelo_ruta = str(datos.get("modelo", ""))

	name = "Enemigo_%s" % id_enemigo
	collision_layer = 0
	collision_mask = 1
	_construir_capsula_marcador()
	_aplicar_estado_activo()


func _construir_capsula_marcador() -> void:
	if _colision == null:
		_colision = CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.4
		_colision.shape = cap
		_colision.position = Vector3(0.0, 0.7, 0.0)
		add_child(_colision)
	if marcador_capsula == null:
		marcador_capsula = MeshInstance3D.new()
		marcador_capsula.name = "MarcadorCapsula"
		var cm := CapsuleMesh.new()
		cm.radius = 0.32
		cm.height = 1.35
		marcador_capsula.mesh = cm
		marcador_capsula.position = Vector3(0.0, 0.7, 0.0)
		# Sin modelo definitivo todavía: la cápsula permanece invisible para el jugador.
		marcador_capsula.visible = false
		add_child(marcador_capsula)
	if not modelo_ruta.is_empty() and ResourceLoader.exists(modelo_ruta):
		var esc := load(modelo_ruta) as PackedScene
		if esc != null:
			var modelo := esc.instantiate()
			add_child(modelo)
			marcador_capsula.visible = false


func _aplicar_estado_activo() -> void:
	var corriendo := activo and not muerto
	if _colision != null:
		_colision.disabled = not corriendo
	set_physics_process(corriendo)


func activar_para_prueba(valor: bool = true, obj: Node3D = null) -> void:
	activo = valor
	objetivo = obj
	if not muerto:
		_aplicar_estado_activo()


func _physics_process(delta: float) -> void:
	if not activo or muerto:
		return
	_enfriamiento = maxf(_enfriamiento - delta, 0.0)
	var obj := objetivo if objetivo != null and is_instance_valid(objetivo) else Escenas.jugador()
	if obj == null or not is_instance_valid(obj):
		return
	var dist := global_position.distance_to(obj.global_position)
	if dist <= alcance_ataque:
		velocity = Vector3.ZERO
		atacar(obj)
	elif dist <= alcance_deteccion:
		perseguir(obj, delta)


## Se desplaza hacia el objetivo horizontalmente; devuelve true si pudo avanzar o ya está a tiro.
func perseguir(obj: Node3D, delta: float) -> bool:
	if muerto or obj == null or not is_instance_valid(obj):
		return false
	var dif := obj.global_position - global_position
	dif.y = 0.0
	var dist := dif.length()
	if dist <= alcance_ataque:
		velocity = Vector3.ZERO
		return true
	if dist <= 0.001:
		return false
	var dir := dif / dist
	var paso := minf(velocidad * maxf(delta, 0.0), dist - alcance_ataque * 0.5)
	velocity = dir * velocidad
	if is_inside_tree():
		var col := move_and_collide(dir * paso)
		if col == null:
			return true
		# Desliza si roza un muro o escalón.
		move_and_slide()
		return true
	global_position += dir * paso
	return true


## Realiza un golpe contra el objetivo si está en rango y no en enfriamiento.
func atacar(obj: Node3D) -> bool:
	if muerto or obj == null or not is_instance_valid(obj) or _enfriamiento > 0.0:
		return false
	var dif := obj.global_position - global_position
	dif.y = 0.0
	if dif.length() > alcance_ataque + 0.35:
		return false
	_enfriamiento = cadencia_ataque
	if obj == Escenas.jugador():
		Juego.recibir_dano(dano)
	elif obj.has_method("recibir_dano"):
		obj.call("recibir_dano", dano)
	atacado.emit(dano)
	return true


func recibir_dano(cantidad: float) -> void:
	if muerto or cantidad <= 0.0:
		return
	vida = maxf(vida - cantidad, 0.0)
	if vida <= 0.001:
		morir()


func morir() -> void:
	if muerto:
		return
	muerto = true
	activo = false
	_aplicar_estado_activo()
	fallecido.emit(self)
	if is_inside_tree():
		queue_free()
