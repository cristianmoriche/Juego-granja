class_name Vecinos
extends Node3D
## Los vecinos de un mapa (L4b). Va dentro del nodo `Objetos` del pueblo y de la mina exterior. Al llegar
## `Escenas.mapa_cargado` de su mapa crea a los vecinos que, a la hora actual, están en él, y con cada minuto del juego
## (`Juego.hora_cambiada`) los hace llegar, cambiar de sitio o irse según su horario.
##
## Quiénes: los de `datos/npcs.json` (con amistad, conversación y servicio) y los de relleno de
## `datos/vecinos_relleno.json` (solo frases; no cuentan en `Juego.amistad_media()`).
## Horario (todos los campos son opcionales; las horas son minutos del día, 360 = 06:00):
##   `llega` (por defecto 360) y `se_va` (por defecto 1260 = 21:00): fuera de esas horas no están en ningún mapa.
##   `horario`: [{"desde": 540, "hasta": 1140, "mapa": "<id>", "marcador": "<m>", "desplazar": [dx, dz]}]:
##   dentro de cada franja están en ese mapa y marcador; fuera de ellas, en su `mapa` y `marcador` de siempre.
## `desplazar` mueve el sitio respecto del marcador (metros en x, z). El encargo L5 (interiores) mete a Don Mateo,
## Clara y Ramón en sus locales con franjas de `horario` cuyo `mapa` es el del interior.

const RUTA_RELLENO := "res://datos/vecinos_relleno.json"
const LLEGA := 360
const SE_VA := 1260
const SEPARACION := 1.3

## Los vecinos que están ahora en este mapa: id → Npc.
var npcs: Dictionary = {}
## Datos de todos los vecinos que podrían salir (principales y de relleno).
var lista: Array[Dictionary] = []
var id_mapa: String = ""
var construido: bool = false


func _ready() -> void:
	Escenas.mapa_cargado.connect(_al_mapa_cargado)
	Juego.hora_cambiada.connect(_al_cambiar_hora)
	Juego.dia_nuevo.connect(_resincronizar)
	Juego.estacion_cambiada.connect(_resincronizar)
	Juego.clima_cambiado.connect(func(_c: String) -> void: _resincronizar())
	Juego.evento_cambiado.connect(_resincronizar)
	Juego.deuda_cambiada.connect(func(_d: int) -> void: _resincronizar())


func _resincronizar() -> void:
	if construido:
		sincronizar()


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


func _al_mapa_cargado(id: String) -> void:
	var mapa := _mapa()
	if mapa != null and str(mapa.get("id_mapa")) == id:
		construir()


func _al_cambiar_hora(_minutos: int) -> void:
	if construido:
		sincronizar()


## Crea a los vecinos de ahora. Se puede repetir (empieza quitando los que hubiera).
func construir() -> void:
	var mapa := _mapa()
	if mapa == null:
		return
	id_mapa = str(mapa.get("id_mapa"))
	for n: Variant in npcs.values():
		if is_instance_valid(n):
			(n as Node).queue_free()
	npcs.clear()
	lista = datos_de_todos()
	CargadorMapa.solicitar_lote(rutas_mapa(id_mapa, lista))
	construido = true
	sincronizar(true)


## Rutas de escena y modelos de los vecinos presentes ahora en `id` para precarga en paralelo.
func rutas_mapa(id: String, todos: Array[Dictionary] = []) -> PackedStringArray:
	var escena_npc := "res://escenas/npc/npc.tscn"
	var tpl_modelo := "res://assets/personajes/aldeanos/%s.glb"
	var vistas: Dictionary = {}
	var salida: Array[String] = [escena_npc]
	vistas[escena_npc] = true
	var origen := datos_de_todos() if todos.is_empty() else todos
	var mins := Juego.minutos
	for d in origen:
		var ub := ubicacion_en_mapa(d, mins, id)
		if ub.is_empty() or str(ub.get("mapa", "")) != id:
			continue
		var modelo := str(d.get("modelo", ""))
		if modelo.is_empty():
			continue
		var ruta := tpl_modelo % modelo
		if not vistas.has(ruta) and ResourceLoader.exists(ruta):
			vistas[ruta] = true
			salida.append(ruta)
	return PackedStringArray(salida)


## Todos los vecinos que pueden salir en algún mapa (los de relleno llevan `relleno: true`).
static func datos_de_todos() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for id in Datos.ids_npc():
		r.append(Datos.npc(id))
	if FileAccess.file_exists(RUTA_RELLENO):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(RUTA_RELLENO)) == OK and json.data is Array:
			for v: Variant in Datos.normalizar_numeros(json.data):
				var d: Dictionary = (v as Dictionary).duplicate()
				d["relleno"] = true
				r.append(d)
		else:
			push_warning("Vecinos: %s mal formado." % RUTA_RELLENO)
	return r


## Comprueba si una regla de `reglas_horario` aplica en el contexto actual de `Juego` y a esta hora (`minutos`).
static func _regla_aplica(r: Dictionary, minutos: int) -> bool:
	if r.has("festividad"):
		var es_fiesta := not Juego.festividad_hoy().is_empty()
		if bool(r["festividad"]) != es_fiesta:
			return false
	if r.has("lluvia"):
		if bool(r["lluvia"]) != Juego.esta_lloviendo():
			return false
	if r.has("dias"):
		var dias: Array = r["dias"] if r["dias"] is Array else []
		if not dias.has(Juego.dia_semana()):
			return false
	if r.has("estaciones"):
		var ests: Array = r["estaciones"] if r["estaciones"] is Array else []
		if not ests.has(Juego.estacion):
			return false
	if r.has("tramo_deuda_min") and Juego.tramo_deuda() < int(r["tramo_deuda_min"]):
		return false
	if r.has("tramo_deuda_max") and Juego.tramo_deuda() > int(r["tramo_deuda_max"]):
		return false
	if r.has("desde") and minutos < int(r["desde"]):
		return false
	if r.has("hasta") and minutos >= int(r["hasta"]):
		return false
	return true


static func _regla_activa(d: Dictionary, minutos: int) -> Dictionary:
	for v: Variant in d.get("reglas_horario", []):
		if not (v is Dictionary):
			continue
		var r := v as Dictionary
		if _regla_aplica(r, minutos):
			return r
	return {}


## Dónde está un vecino a una hora (minutos del día): {"mapa", "marcador", "desplazar"} o {} si no está en ningún mapa.
static func ubicacion(d: Dictionary, minutos: int) -> Dictionary:
	var regla := _regla_activa(d, minutos)
	var llega := int(regla.get("llega", d.get("llega", LLEGA)))
	var se_va := int(regla.get("se_va", d.get("se_va", SE_VA)))
	if minutos < llega or minutos >= se_va:
		return {}
	if not regla.is_empty():
		var res := {
			"mapa": str(regla.get("mapa", d.get("mapa", ""))),
			"marcador": str(regla.get("marcador", d.get("marcador", ""))),
			"desplazar": regla.get("desplazar", d.get("desplazar", [0, 0])),
		}
		if regla.has("fijo"):
			res["fijo"] = bool(regla["fijo"])
		if regla.has("radio"):
			res["radio"] = float(regla["radio"])
		return res
	for h: Variant in d.get("horario", []):
		var f: Dictionary = h
		if minutos >= int(f.get("desde", 0)) and minutos < int(f.get("hasta", 0)):
			return {
				"mapa": str(f.get("mapa", d.get("mapa", ""))),
				"marcador": str(f.get("marcador", d.get("marcador", ""))),
				"desplazar": f.get("desplazar", [0, 0]),
			}
	return {"mapa": str(d.get("mapa", "")), "marcador": str(d.get("marcador", "")), "desplazar": d.get("desplazar", [0, 0])}


## Dónde está un vecino a una hora (minutos del día) cuando se consulta desde un mapa concreto.
static func ubicacion_en_mapa(d: Dictionary, minutos: int, mapa_destino: String) -> Dictionary:
	var regla := _regla_activa(d, minutos)
	var llega := int(regla.get("llega", d.get("llega", LLEGA)))
	var se_va := int(regla.get("se_va", d.get("se_va", SE_VA)))
	if minutos < llega or minutos >= se_va:
		return {}
	if not bool(regla.get("anular_interior", false)):
		for h: Variant in d.get("horario_interior", []):
			var f: Dictionary = h
			if str(f.get("mapa", "")) == mapa_destino and minutos >= int(f.get("desde", 0)) and minutos < int(f.get("hasta", 0)):
				return {
					"mapa": mapa_destino,
					"marcador": str(f.get("marcador", "")),
					"desplazar": f.get("desplazar", [0, 0]),
					"fijo": true,
				}
	return ubicacion(d, minutos)


static func clave_sitio(ub: Dictionary) -> String:
	return "%s|%s" % [str(ub.get("marcador", "")), str(ub.get("desplazar", [0, 0]))]


static func _animo_actual() -> float:
	if not Juego.festividad_hoy().is_empty():
		return 1.0
	var bases: Array[float] = [0.0, 0.35, 0.70, 1.0]
	var base: float = bases[clampi(Juego.tramo_deuda(), 0, 3)]
	if Juego.esta_lloviendo():
		base *= 0.4
	return base


## Pone a cada vecino donde toca a la hora actual: llega, camina a su nuevo sitio o se va.
## `inicial` es true al construir el mapa: los que ya estaban salen sin animación.
func sincronizar(inicial: bool = false) -> void:
	var animo_pueblo := _animo_actual()
	for d in lista:
		var id := str(d.get("id", ""))
		var ub := ubicacion_en_mapa(d, Juego.minutos, id_mapa)
		var aqui := not ub.is_empty() and str(ub["mapa"]) == id_mapa
		var existente: Npc = null
		if npcs.has(id) and is_instance_valid(npcs[id]):
			existente = npcs[id] as Npc
		if aqui:
			var clave := clave_sitio(ub)
			var clave_dia := AyudasL4b.clave_dia()
			var radio_efectivo: float = 0.0 if bool(ub.get("fijo", false)) else float(ub.get("radio", d.get("radio", 3.0)))
			if existente == null:
				var d_inst := d.duplicate()
				if bool(ub.get("fijo", false)) or ub.has("radio"):
					d_inst["radio"] = radio_efectivo
				var n := Npc.crear(d_inst)
				n.animo = animo_pueblo
				add_child(n)
				npcs[id] = n
				var p_ini := _posicion(ub, n)
				n.colocar_en(p_ini, clave)
				n.fijar_ruta_diaria(_construir_ruta_diaria(d, ub, p_ini, radio_efectivo, clave_dia), clave_dia)
				if not inicial:
					n.aparecer()
			else:
				existente.animo = animo_pueblo
				existente.radio = radio_efectivo
				if existente.sitio_actual != clave:
					var p_dest := _posicion(ub, existente)
					existente.ir_a(p_dest, clave)
					existente.fijar_ruta_diaria(_construir_ruta_diaria(d, ub, p_dest, radio_efectivo, clave_dia), clave_dia)
				elif existente.ruta_dia_clave != clave_dia:
					existente.fijar_ruta_diaria(_construir_ruta_diaria(d, ub, existente.centro, radio_efectivo, clave_dia), clave_dia)
		elif existente != null:
			npcs.erase(id)
			if inicial:
				existente.queue_free()
			else:
				existente.retirarse()
		elif npcs.has(id):
			npcs.erase(id)


## Sitio libre en el suelo para un vecino, junto al marcador (más el desplazamiento) y sin pisar a otro vecino.
func _posicion(ub: Dictionary, quien: Npc) -> Vector3:
	var mapa := _mapa()
	var m: Marker3D = null
	if mapa != null and mapa.has_method("marcador"):
		m = mapa.call("marcador", str(ub.get("marcador", ""))) as Marker3D
		if m == null:
			m = mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	var base := m.global_position if m != null else Vector3.ZERO
	var des: Array = ub.get("desplazar", [0, 0])
	base += Vector3(float(des[0]), 0.0, float(des[1]))
	if bool(ub.get("fijo", false)):
		return base
	var p := AyudasL4b.sitio_libre(self, base)
	for k in 14:
		if _libre_de_vecinos(p, quien):
			break
		var a := float(k) * 2.4
		var r := 0.9 + 0.55 * float(k)
		p = AyudasL4b.sitio_libre(self, base + Vector3(cos(a), 0, sin(a)) * r)
	return p


func _libre_de_vecinos(p: Vector3, quien: Npc) -> bool:
	for n: Variant in npcs.values():
		if n == quien or not is_instance_valid(n):
			continue
		var o := (n as Node3D).global_position
		if Vector2(o.x - p.x, o.z - p.z).length() < SEPARACION:
			return false
	return true


## Construye un circuito diario determinista distinto cada día del año cuando el NPC pasea por exteriores.
func _construir_ruta_diaria(d: Dictionary, ub: Dictionary, centro_base: Vector3, radio_eff: float, clave_dia: int) -> Array[Vector3]:
	var ruta: Array[Vector3] = []
	if bool(ub.get("fijo", false)) or radio_eff <= 0.2:
		return ruta
	var mapa := _mapa()
	if mapa == null or bool(mapa.get("interior")):
		return ruta
	var id_npc := str(d.get("id", ""))
	var azar := RandomNumberGenerator.new()
	azar.seed = int(id_npc.hash()) + clave_dia * 131 + 19

	if id_mapa == "pueblo":
		var candidatos := [
			"Spawn_Tendera", "Spawn_Herrero", "Spawn_Tabernero", "Spawn_Alcalde",
			"Spawn_Nino", "Puerta_Tienda", "Puerta_Herreria", "Puerta_Taberna",
			"Puerta_Alcalde", "Puerta_Capilla",
		]
		# Baraja según el día para que cada jornada visite zonas distintas del pueblo.
		for i in range(candidatos.size() - 1, 0, -1):
			var j := azar.randi_range(0, i)
			var tmp: String = candidatos[i]
			candidatos[i] = candidatos[j]
			candidatos[j] = tmp
		ruta.append(centro_base)
		for nom_mk: String in candidatos:
			if ruta.size() >= 4:
				break
			var mk := mapa.call("marcador", nom_mk) as Marker3D
			if mk == null:
				continue
			var ang := azar.randf_range(0.0, TAU)
			var dist := azar.randf_range(1.2, 3.0)
			var cand := mk.global_position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
			if Vector2(cand.x, cand.z).length() < 4.5:
				continue
			var s := AyudasL4b.sitio_libre(self, cand)
			if s != Vector3.INF and mapa.punto_dentro(s, 1.2):
				ruta.append(s)
		return ruta

	# Otros mapas exteriores (como mina_exterior): puntos variados alrededor del centro según el día.
	ruta.append(centro_base)
	var base_ang := azar.randf_range(0.0, TAU)
	for i in 3:
		var a := base_ang + float(i) * (TAU / 3.0) + azar.randf_range(-0.4, 0.4)
		var r := clampf(radio_eff * azar.randf_range(0.55, 1.15), 1.0, 4.0)
		var cand := centro_base + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var s := AyudasL4b.sitio_libre(self, cand)
		if s != Vector3.INF and (not mapa.has_method("punto_dentro") or bool(mapa.call("punto_dentro", s, 1.0))):
			ruta.append(s)
	return ruta
