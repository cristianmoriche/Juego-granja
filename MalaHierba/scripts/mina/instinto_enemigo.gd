class_name InstintoEnemigo
extends RefCounted
## Percepción a intervalos y guiado por las celdas de la mina.

var vio := false
var oyó := false
var rastro := Vector3.INF
var origen := Vector3.INF
var _t_sensor := 0.0
var _t_memoria := 0.0
var _t_ruta := 0.0
var _ruta := PackedVector3Array()
var _i_ruta := 0
var _lado := 1.0
var _t_rodeo := 0.0


func percibir(enemigo: Enemigo, obj: Node3D, delta: float) -> void:
	if not origen.is_finite():
		origen = enemigo.global_position
		_lado = 1.0 if enemigo.get_instance_id() % 2 == 0 else -1.0
	_t_sensor -= delta
	_t_memoria -= delta
	if _t_sensor > 0.0:
		return
	_t_sensor = 0.11 + float(enemigo.get_instance_id() % 5) * 0.011
	vio = false
	oyó = false
	var d := (obj.global_position - enemigo.global_position).slide(Vector3.UP)
	var rango := enemigo.alcance_deteccion
	if d.length_squared() <= rango * rango:
		var jugador := obj as Jugador
		var ruido := 1.8
		if jugador != null:
			var paso := jugador.velocity.slide(Vector3.UP).length()
			ruido = 0.8 if jugador.agachado else (1.7 + paso if paso > 0.25 else 1.15)
			if jugador.combate.ocupado():
				ruido = maxf(ruido, 4.8)
		var en_cono := d.length_squared() < 1.0 or enemigo.global_basis.z.dot(d.normalized()) > 0.40
		var libre := en_cono or d.length() < ruido
		libre = libre and enemigo.linea_despejada(obj.global_position + Vector3.UP * 0.90)
		vio = en_cono and libre
		oyó = d.length() < ruido * (1.0 if libre else 0.55)
		if vio or oyó:
			recordar(obj.global_position)
	if _t_memoria <= 0.0:
		rastro = Vector3.INF


func recordar(punto: Vector3) -> void:
	rastro = punto
	_t_memoria = 4.0


func paso(enemigo: Enemigo, punto: Vector3, delta: float, rapidez: float) -> void:
	var d := (punto - enemigo.global_position).slide(Vector3.UP)
	if d.length_squared() <= 0.03 or rapidez <= 0.0:
		enemigo.velocity = Vector3.ZERO
		return
	var directo := d.normalized()
	var dir := directo
	_t_ruta -= delta
	_t_rodeo = maxf(0.0, _t_rodeo - delta)
	var mina := enemigo.get_parent().get_parent() as NivelMina
	var tapado := not enemigo.linea_despejada(punto + Vector3.UP * 0.65)
	if mina != null and tapado:
		if _t_ruta <= 0.0:
			_ruta = mina.ruta_enemigo(enemigo.global_position, punto)
			_i_ruta = 0
			_t_ruta = 0.49
		while _i_ruta < _ruta.size():
			var tramo := (_ruta[_i_ruta] - enemigo.global_position).slide(Vector3.UP)
			if tramo.length_squared() > 0.31:
				dir = tramo.normalized()
				break
			_i_ruta += 1
	else:
		_t_ruta = 0.0
		_ruta.clear()
	var avanza := minf(rapidez * delta, d.length())
	if _t_rodeo > 0.0 or enemigo.test_move(enemigo.global_transform, dir * 0.42):
		dir = _rodear(enemigo, dir)
	enemigo.velocity = dir * rapidez
	enemigo.mirar_direccion(dir, delta)
	var col := enemigo.move_and_collide(dir * avanza)
	if col != null:
		var resto := col.get_remainder().slide(col.get_normal()).slide(Vector3.UP)
		enemigo.move_and_collide(resto)


func _rodear(enemigo: Enemigo, dir: Vector3) -> Vector3:
	var opciones := [0.57, 1.06, 1.55, -0.65, -1.15, -1.65, 2.5]
	if _t_rodeo <= 0.0 and not enemigo.test_move(enemigo.global_transform, dir * 0.42):
		return dir
	for angulo: float in opciones:
		var otra := dir.rotated(Vector3.UP, angulo * _lado)
		if not enemigo.test_move(enemigo.global_transform, otra * 0.55):
			_t_rodeo = 0.09 if _t_rodeo <= 0.0 else _t_rodeo
			return otra
	return dir
