class_name TareasDiarias
extends RefCounted
## Tareas diarias del tablón (T23): 3 encargos al día entre plantillas variadas con escala por progreso.

const RUTA_TABLON := "res://datos/tablon.json"
const RUTA_TAREAS := "res://datos/tareas_diarias.json"
const ENCARGOS_AL_DIA := 3

static var _cache: Array[Dictionary] = []
static var _cache_entregas: Array[Dictionary] = []


static func _cargar_json_lista(ruta: String) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	if FileAccess.file_exists(ruta):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(ruta)) == OK and json.data is Array:
			for v: Variant in Datos.normalizar_numeros(json.data):
				r.append(v as Dictionary)
	return r


static func todos_los_encargos_entrega() -> Array[Dictionary]:
	if _cache_entregas.is_empty():
		_cache_entregas = _cargar_json_lista(RUTA_TABLON)
	return _cache_entregas


static func todos_los_encargos() -> Array[Dictionary]:
	if _cache.is_empty():
		_cache.append_array(todos_los_encargos_entrega())
		_cache.append_array(_cargar_json_lista(RUTA_TAREAS))
	return _cache


static func _estado() -> Dictionary:
	var hoy := AyudasL4b.clave_dia()
	var raw: Variant = Juego.banderas.get("tareas_diarias", null)
	if not (raw is Dictionary) or int((raw as Dictionary).get("dia", -1)) != hoy:
		raw = {
			"dia": hoy,
			"escala": escala_progreso(),
			"progreso": {},
			"hechos": [],
		}
		Juego.banderas["tareas_diarias"] = raw
	var d := raw as Dictionary
	if not (d.get("progreso", null) is Dictionary):
		d["progreso"] = {}
	if not (d.get("hechos", null) is Array):
		d["hechos"] = []
	return d


static func al_empezar_dia() -> Dictionary:
	return _estado()


static func escala_progreso() -> float:
	var est_fac := float(Juego.estacion) * 0.20
	var deuda_fac := clampf(float(Juego.deuda_pagada()) / 5000.0, 0.0, 1.0) * 0.50
	var suma_h := 0.0
	for h: String in ["azada", "regadera", "hoz", "hacha", "pico"]:
		suma_h += float(Juego.nivel(h))
	var her_fac := (suma_h / 5.0) * 0.20
	return clampf(1.0 + est_fac + deuda_fac + her_fac, 1.0, 2.2)


static func _es_elegible(e: Dictionary) -> bool:
	var ests: Variant = e.get("estaciones", [])
	if ests is Array and not (ests as Array).is_empty():
		if not (ests as Array).has(Juego.estacion):
			return false
	if str(e.get("tipo", "entregar")) == "pescar":
		var pesca_ok := bool(Juego.banderas.get("pesca_habilitada", false)) or Juego.cantidad("cana") > 0
		if not pesca_ok:
			return false
	return true


static func _escalar_encargo(base: Dictionary, escala: float) -> Dictionary:
	var r := base.duplicate(true)
	var tipo := str(r.get("tipo", "entregar"))
	var cant_base := maxi(int(r.get("cantidad", 1)), 1)
	if tipo == "regalar":
		r["cantidad"] = 1 if escala < 1.65 else mini(2, cant_base)
	else:
		r["cantidad"] = maxi(1, roundi(float(cant_base) * escala))
	var din_base := int(r.get("dinero", 20))
	r["dinero"] = maxi(15, roundi(float(din_base) * clampf(sqrt(escala), 1.0, 1.5)))
	r["amistad"] = int(r.get("amistad", 8)) + (2 if escala >= 1.5 else 0)
	return r


## Devuelve las 3 tareas diarias de hoy (1 entrega asegurada + hasta 2 de actividad o entrega variada).
static func encargos_del_dia() -> Array[Dictionary]:
	var todos := todos_los_encargos()
	var r: Array[Dictionary] = []
	if todos.is_empty():
		return r
	var est := _estado()
	var escala := float(est.get("escala", 1.0))

	var entregas: Array[Dictionary] = []
	var acciones: Array[Dictionary] = []
	for t: Dictionary in todos:
		if not _es_elegible(t):
			continue
		if str(t.get("tipo", "entregar")) == "entregar":
			entregas.append(t)
		else:
			acciones.append(t)
	if entregas.is_empty() and acciones.is_empty():
		return r

	var azar := RandomNumberGenerator.new()
	azar.seed = hash(AyudasL4b.clave_dia()) ^ 0x4c4b
	_barajar(entregas, azar)
	_barajar(acciones, azar)

	var elegidos: Array[Dictionary] = []
	if not entregas.is_empty():
		elegidos.append(entregas.pop_front() as Dictionary)

	var tipos_usados: Dictionary = {}
	for acc: Dictionary in acciones:
		if elegidos.size() >= ENCARGOS_AL_DIA:
			break
		var tipo := str(acc.get("tipo", ""))
		if not tipos_usados.has(tipo):
			elegidos.append(acc)
			tipos_usados[tipo] = true

	var resto: Array[Dictionary] = []
	resto.append_array(entregas)
	for acc: Dictionary in acciones:
		if not elegidos.has(acc):
			resto.append(acc)
	for extra: Dictionary in resto:
		if elegidos.size() >= ENCARGOS_AL_DIA:
			break
		if not elegidos.has(extra):
			elegidos.append(extra)

	for item: Dictionary in elegidos:
		r.append(_escalar_encargo(item, escala))
	return r


static func _barajar(arr: Array[Dictionary], azar: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := azar.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func encargo_hecho(id_encargo: String) -> bool:
	var est := _estado()
	return (est["hechos"] as Array).has(id_encargo)


static func texto_encargo(e: Dictionary) -> String:
	return str(e.get("texto", "")).replace("{n}", str(int(e.get("cantidad", 0))))


static func progreso_de(e: Dictionary) -> Vector2i:
	var id_e := str(e.get("id", ""))
	var meta := maxi(int(e.get("cantidad", 1)), 1)
	if encargo_hecho(id_e):
		return Vector2i(meta, meta)
	var tipo := str(e.get("tipo", "entregar"))
	if tipo == "entregar":
		return Vector2i(mini(Juego.cantidad(str(e.get("pide", ""))), meta), meta)
	var est := _estado()
	var prog := est["progreso"] as Dictionary
	return Vector2i(mini(int(prog.get(tipo, 0)), meta), meta)


static func lista_para_cobrar(e: Dictionary) -> bool:
	if encargo_hecho(str(e.get("id", ""))):
		return false
	var p := progreso_de(e)
	return p.x >= p.y


static func registrar_progreso(tipo: String, cantidad: int = 1) -> void:
	if cantidad <= 0 or tipo.is_empty():
		return
	var est := _estado()
	var prog := est["progreso"] as Dictionary
	var antes := int(prog.get(tipo, 0))
	var despues := antes + cantidad
	prog[tipo] = despues
	for e: Dictionary in encargos_del_dia():
		if str(e.get("tipo", "entregar")) == tipo and not encargo_hecho(str(e.get("id", ""))):
			var meta := maxi(int(e.get("cantidad", 1)), 1)
			if antes < meta and despues >= meta:
				Juego.mensaje.emit("Tarea del tablón lista para cobrar: %s" % texto_encargo(e))
	if is_instance_valid(Misiones):
		Misiones.actualizado.emit()


static func entregar(id_encargo: String) -> String:
	var elegido: Dictionary = {}
	for e in encargos_del_dia():
		if str(e.get("id", "")) == id_encargo:
			elegido = e
			break
	if elegido.is_empty():
		return "no_hoy"
	if encargo_hecho(id_encargo):
		return "hecho"
	var tipo := str(elegido.get("tipo", "entregar"))
	var n := maxi(int(elegido.get("cantidad", 1)), 1)
	if tipo == "entregar":
		var pide := str(elegido.get("pide", ""))
		if Juego.cantidad(pide) < n or not Juego.quitar_objeto(pide, n):
			return "faltan"
	else:
		if progreso_de(elegido).x < n:
			return "faltan"
	var cobro := int(elegido.get("dinero", 0))
	Juego.ingresar(cobro)
	if cobro > 0 and is_instance_valid(Interfaz):
		Interfaz.mostrar_dinero_flotante(cobro)
	Juego.subir_amistad(str(elegido.get("npc", "")), int(elegido.get("amistad", 0)))
	var est := _estado()
	(est["hechos"] as Array).append(id_encargo)
	if is_instance_valid(Misiones):
		Misiones.actualizado.emit()
	return "ok"
