class_name LimitesMapa
extends RefCounted
## Lee res://datos/limites.json: por mapa, el nombre que sale en el minimapa y el polígono [[x, z], ...]
## del área jugable (coordenadas de Godot). Lo usan mapa.gd (muros y vallas), el minimapa y la red de seguridad.
## Formato por mapa: {"nombre": "...", "poligono": [[x, z], ...], "valla": "madera"|"ninguna", "sin_valla": [índices de lado]}
## El lado i va del punto i al punto i+1 (el último vuelve al primero).

const RUTA := "res://datos/limites.json"

static var _datos: Dictionary = {}
static var _cargado: bool = false


static func _cargar() -> void:
	if _cargado:
		return
	_cargado = true
	if not FileAccess.file_exists(RUTA):
		push_warning("LimitesMapa: falta %s" % RUTA)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(RUTA)) != OK or not (json.data is Dictionary):
		push_error("LimitesMapa: JSON mal formado en %s" % RUTA)
		return
	_datos = json.data


static func recargar() -> void:
	_cargado = false
	_datos = {}
	_cargar()


static func existe(id: String) -> bool:
	_cargar()
	return _datos.has(id) and poligono(id).size() >= 3


static func nombre(id: String) -> String:
	_cargar()
	var d: Dictionary = _datos.get(id, {})
	return str(d.get("nombre", id))


static func poligono(id: String) -> PackedVector2Array:
	_cargar()
	var r := PackedVector2Array()
	var d: Dictionary = _datos.get(id, {})
	for p: Variant in d.get("poligono", []):
		var a: Array = p
		r.append(Vector2(float(a[0]), float(a[1])))
	return r


static func tipo_valla(id: String) -> String:
	_cargar()
	var d: Dictionary = _datos.get(id, {})
	return str(d.get("valla", "madera"))


## false en las cuevas: sus límites son la propia roca y el rectángulo del polígono no significa nada para el jugador.
static func mostrar_borde(id: String) -> bool:
	return existe(id) and tipo_valla(id) != "ninguna"


static func lados_sin_valla(id: String) -> Array[int]:
	_cargar()
	var d: Dictionary = _datos.get(id, {})
	var r: Array[int] = []
	for v: Variant in d.get("sin_valla", []):
		r.append(int(v))
	return r


static func rect_poligono(p: PackedVector2Array, caja: AABB = AABB(), margen: float = 8.0) -> Rect2:
	if p.size() >= 3:
		var mn := p[0]
		var mx := p[0]
		for v in p:
			mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
			mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
		return Rect2(mn - Vector2(margen, margen), (mx - mn) + Vector2(margen, margen) * 2.0)
	return Rect2(Vector2(caja.position.x, caja.position.z), Vector2(caja.size.x, caja.size.z))


## Zona que enseña el minimapa: el polígono con un margen, o la caja del mapa si no hay polígono.
static func rect(id: String, caja: AABB = AABB(), margen: float = 8.0) -> Rect2:
	return rect_poligono(poligono(id), caja, margen)


static func dentro_poligono(p: PackedVector2Array, punto: Vector3, holgura: float = 0.0) -> bool:
	if p.size() < 3:
		return true
	var q := Vector2(punto.x, punto.z)
	if Geometry2D.is_point_in_polygon(q, p):
		return true
	if holgura <= 0.0:
		return false
	# Margen: cuenta como dentro si está a menos de `holgura` de algún lado.
	for i in p.size():
		var c := Geometry2D.get_closest_point_to_segment(q, p[i], p[(i + 1) % p.size()])
		if c.distance_to(q) <= holgura:
			return true
	return false


static func dentro(id: String, punto: Vector3, holgura: float = 0.0) -> bool:
	return dentro_poligono(poligono(id), punto, holgura)
