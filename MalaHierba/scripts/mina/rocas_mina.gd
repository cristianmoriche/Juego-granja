class_name RocasMina
extends Node3D
## Rocas de la mina interior (L4b). Va dentro del nodo `Objetos` de `mina_interior`; se construye al llegar
## `Escenas.mapa_cargado("mina_interior")`.
##
## Dónde: se explora a pie (rejilla de 0,5 m) todo el suelo que Leo puede pisar desde `Llegada_Interior` y se reparten las
## rocas por allí, sin cerrar nunca el paso: cada roca se comprueba contra un recorrido `Llegada_Interior` → `Bajada_Nivel_2`
## que deja al menos 70 cm libres a su alrededor, y se aleja de la llegada, de la salida y de la escalera.
## Cuántas y cuáles: 20 en el nivel 1 (piedra, cobre, hierro) y 28 en el 2 (más hierro y además cuarzo), según
## `Juego.banderas["nivel_mina"]`. Salen siempre en los mismos sitios en cada nivel.
## Cada roca es un cuerpo sólido (capa 7, solo choca Leo) con una malla low-poly deformada de su mena, una marca de
## Cada `Interactuable` muestra «Clic · Picar» y exige el pico equipado.
## Golpes: piedra 2, cobre 3, hierro 3, cuarzo 4; cada nivel del pico quita uno (mínimo 1). Energía por golpe: 2, 1,5, 1.
## Las rotas se guardan en `Juego.estado_mapas["mina_interior"]` y vuelven a salir al día siguiente.

const ID_MAPA := "mina_interior"
const CAPA_SOLO_JUGADOR := 64
const PASO := 0.5
const RADIO_CUERPO := 0.35
const HOLGURA := 0.7
const DIST_USO := 0.9
const LIMITE_CELDAS := 24000
const MASCARA_CUEVA := 1 | 64
## Se levanta la cápsula 30 cm al comprobar el suelo: los raíles y traviesas (más bajos) no cuentan como obstáculo.
const ELEVACION := 0.3
## Alto de la cápsula de comprobación: con la elevación y el margen de `AyudasL4b.cabe` llega justo a la altura real de
## Leo (1,75 m). Con 1,7 m llegaba a 2,15 m y tropezaba con los travesaños de las vigas (a 2,0 m), por donde Leo sí pasa:
## la exploración se quedaba en la entrada y no salía ninguna roca.
const ALTO_CUERPO := EscalaPersonaje.ALTURA_PIE - ELEVACION - 0.15

const TIPOS := {
	"piedra": {"golpes": 2, "min": 2, "max": 4, "extra": "", "color": Color(0.5, 0.5, 0.52), "nombre": "la roca"},
	"cobre": {"golpes": 3, "min": 1, "max": 3, "extra": "piedra", "color": Color(0.5, 0.41, 0.35), "nombre": "la roca de cobre"},
	"hierro": {"golpes": 3, "min": 1, "max": 3, "extra": "piedra", "color": Color(0.36, 0.4, 0.46), "nombre": "la roca de hierro"},
	"cuarzo": {"golpes": 4, "min": 1, "max": 2, "extra": "", "color": Color(0.48, 0.48, 0.55), "nombre": "la roca de cuarzo"},
	"oro": {"golpes": 4, "min": 1, "max": 3, "extra": "piedra", "color": Color(0.62, 0.50, 0.22), "nombre": "la veta de oro"},
	"amatista": {"golpes": 5, "min": 1, "max": 2, "extra": "cuarzo", "color": Color(0.46, 0.28, 0.60), "nombre": "la geoda de amatista"},
	"rubi": {"golpes": 5, "min": 1, "max": 2, "extra": "oro", "color": Color(0.56, 0.20, 0.26), "nombre": "la veta de rubí"},
	"diamante": {"golpes": 6, "min": 1, "max": 2, "extra": "oro", "color": Color(0.34, 0.56, 0.68), "nombre": "la veta de diamante"},
}
## Reparto exacto para niveles 1 y 2 (L4b); niveles 3..20 escalan dinámicamente por profundidad.
const REPARTO := {
	1: {"piedra": 10, "cobre": 6, "hierro": 4},
	2: {"piedra": 8, "cobre": 5, "hierro": 9, "cuarzo": 6},
}

class Roca extends RefCounted:
	var id: String = ""
	var tipo: String = "piedra"
	var radio: float = 0.6
	var golpes_dados: int = 0
	var cuerpo: StaticBody3D = null
	var punto: Interactuable = null
	var malla: MeshInstance3D = null
	var pos: Vector3 = Vector3.ZERO
	var rota: bool = false

var nivel: int = 1
var rocas: Array[Roca] = []
var celdas: Dictionary = {}          # Vector2i -> y del suelo (todo lo pisable desde la llegada)
var construido: bool = false
var descartadas: int = 0             # candidatas que se rechazaron por cerrar el paso (para las pruebas)

static var _materiales: Dictionary = {}

var _rechazadas: Dictionary = {}
var _bloqueadas: Dictionary = {}     # celdas ocupadas por las rocas ya colocadas
var _inicio: Vector2i = Vector2i.ZERO
var _fin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	add_to_group("usable")
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	var mapa := _mapa()
	if mapa != null and id == ID_MAPA and str(mapa.get("id_mapa")) == ID_MAPA:
		construir()


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


# --- Construcción ---------------------------------------------------------------------------------------------

func construir() -> void:
	limpiar()
	var mapa := _mapa()
	if mapa == null:
		return
	nivel = clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, NivelMina.MAX_NIVEL)
	var est := estado()
	if int(est.get("dia", -1)) != AyudasL4b.clave_dia():
		est["dia"] = AyudasL4b.clave_dia()
		est["rotas"] = []
	var m_ini := mapa.call("marcador", "Llegada_Interior") as Marker3D
	var m_fin := mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	var m_sal := mapa.call("marcador", "Entrada_Interior") as Marker3D
	if m_ini == null:
		push_warning("RocasMina: falta Llegada_Interior; no hay rocas.")
		return
	_explorar(m_ini.global_position)
	_inicio = _a_celda(m_ini.global_position)
	_fin = _celda_cercana(Vector2(m_fin.global_position.x, m_fin.global_position.z)) if m_fin != null else _inicio
	var evitar: Array[Vector3] = [m_ini.global_position]
	if m_fin != null:
		evitar.append(m_fin.global_position)
	if m_sal != null:
		evitar.append(m_sal.global_position)
	var nm := mapa.get_node_or_null("Objetos/NivelMina") as NivelMina
	if nm != null:
		for p_aux: Vector3 in nm.puntos_evitar_rocas:
			evitar.append(p_aux)

	var azar := RandomNumberGenerator.new()
	azar.seed = 7001 + nivel
	var tipos := _lista_de_tipos(azar)
	var candidatas: Array[Vector2i] = []
	for c: Vector2i in celdas:
		candidatas.append(c)
	candidatas.sort()   # orden estable antes de barajar con la semilla
	for i in range(candidatas.size() - 1, 0, -1):
		var j := azar.randi_range(0, i)
		var t := candidatas[i]
		candidatas[i] = candidatas[j]
		candidatas[j] = t

	var indice_candidata := 0
	var colocadas := 0
	var separacion := 1.25 if tipos.size() <= 22 else 0.7
	for tipo in tipos:
		var radio := azar.randf_range(0.5, 0.78)
		var puesta := false
		while indice_candidata < candidatas.size() and not puesta:
			var c := candidatas[indice_candidata]
			indice_candidata += 1
			if _sirve(c, radio, evitar, separacion):
				_poner(tipo, c, radio, colocadas, azar)
				colocadas += 1
				puesta = true
	construido = true
	# Las que ya se rompieron hoy no salen.
	for r in rocas:
		if (est["rotas"] as Array).has(r.id):
			_quitar(r)


func limpiar() -> void:
	for h in get_children():
		h.queue_free()
	rocas.clear()
	celdas.clear()
	_rechazadas.clear()
	_bloqueadas.clear()
	descartadas = 0
	construido = false


static func estado() -> Dictionary:
	if not (Juego.estado_mapas.get(ID_MAPA, null) is Dictionary):
		Juego.estado_mapas[ID_MAPA] = {}
	var e: Dictionary = Juego.estado_mapas[ID_MAPA]
	if not (e.get("rotas", null) is Array):
		e["rotas"] = []
	return e


static func reparto_de_nivel(nv: int) -> Dictionary:
	if REPARTO.has(nv):
		return REPARTO[nv]
	var total := 32 + (nv - 2) * 3
	if nv <= 5:
		return {
			"piedra": maxi(5, total / 3),
			"cobre": maxi(4, total / 4),
			"hierro": maxi(5, total / 4),
			"cuarzo": maxi(3, total - maxi(5, total / 3) - maxi(4, total / 4) - maxi(5, total / 4)),
		}
	if nv <= 10:
		var oro := 3 + (nv - 5)
		var piedra := maxi(5, total / 5)
		var cobre := maxi(4, total / 5)
		var hierro := maxi(6, total / 4)
		var cuarzo := maxi(3, total - oro - piedra - cobre - hierro)
		return {"piedra": piedra, "cobre": cobre, "hierro": hierro, "cuarzo": cuarzo, "oro": oro}
	if nv <= 15:
		var amat := 4 + (nv - 10)
		var oro := 6 + (nv - 10) / 2
		var rubi := 2 if nv >= 14 else 0
		var hierro := maxi(6, total / 5)
		var cuarzo := maxi(6, total / 5)
		var cobre := 3
		var piedra := maxi(3, total - amat - oro - rubi - hierro - cuarzo - cobre)
		var d := {"piedra": piedra, "cobre": cobre, "hierro": hierro, "cuarzo": cuarzo, "oro": oro, "amatista": amat}
		if rubi > 0:
			d["rubi"] = rubi
		return d
	var diam := 2 + (nv - 16)
	var rubi_d := 5 + (nv - 16)
	var amat_d := 6 + (nv - 16) / 2
	var oro_d := 10 + (nv - 16)
	var cuarzo_d := 8
	var hierro_d := maxi(5, total / 6)
	var piedra_d := maxi(3, total - diam - rubi_d - amat_d - oro_d - cuarzo_d - hierro_d)
	return {"piedra": piedra_d, "hierro": hierro_d, "cuarzo": cuarzo_d, "oro": oro_d, "amatista": amat_d, "rubi": rubi_d, "diamante": diam}


## Tipos de roca del nivel, mezclados.
func _lista_de_tipos(azar: RandomNumberGenerator) -> Array[String]:
	var r: Array[String] = []
	var reparto: Dictionary = reparto_de_nivel(nivel)
	for tipo: String in reparto:
		for i in int(reparto[tipo]):
			r.append(tipo)
	for i in range(r.size() - 1, 0, -1):
		var j := azar.randi_range(0, i)
		var t := r[i]
		r[i] = r[j]
		r[j] = t
	return r


# --- Rejilla de suelo pisable -------------------------------------------------------------------------------------

func _a_celda(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / PASO), roundi(p.z / PASO))


func _a_mundo(c: Vector2i) -> Vector2:
	return Vector2(float(c.x) * PASO, float(c.y) * PASO)


func _celda_cercana(xz: Vector2) -> Vector2i:
	var mejor := _inicio
	var d_mejor := INF
	for c: Vector2i in celdas:
		var d := _a_mundo(c).distance_to(xz)
		if d < d_mejor:
			d_mejor = d
			mejor = c
	return mejor


## Recorre desde la llegada todo el suelo que se puede pisar (cápsula de Leo contra el mundo y las maderas de la cueva).
func _explorar(origen: Vector3) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	var c0 := _a_celda(origen)
	var s0 := AyudasL4b.suelo(self, origen, 1.0, 3.0)
	celdas[c0] = s0.y if s0 != Vector3.INF else origen.y
	var cola: Array[Vector2i] = [c0]
	var cabeza := 0
	while cabeza < cola.size() and celdas.size() < LIMITE_CELDAS:
		var c := cola[cabeza]
		cabeza += 1
		var y_ref: float = celdas[c]
		for d in dirs:
			var n := c + d
			if celdas.has(n) or _rechazadas.has(n):
				continue
			var xz := _a_mundo(n)
			var s := AyudasL4b.suelo(self, Vector3(xz.x, y_ref, xz.y), 0.9, 1.8)
			if s == Vector3.INF or absf(s.y - y_ref) > 0.55 or not AyudasL4b.cabe(self, s, RADIO_CUERPO, ALTO_CUERPO, MASCARA_CUEVA, ELEVACION):
				_rechazadas[n] = true
				continue
			celdas[n] = s.y
			cola.append(n)


## ¿Puede ir una roca de ese radio en esa celda? Lejos de la llegada, la salida y la escalera, separada de las demás,
## con sitio sólido y sin cerrar el paso entre la llegada y la escalera.
func _sirve(c: Vector2i, radio: float, evitar: Array[Vector3], separacion: float = 0.7) -> bool:
	var centro := _a_mundo(c)
	for i_ev in evitar.size():
		var min_d := 3.8 if i_ev < 3 else 1.85
		if centro.distance_to(Vector2(evitar[i_ev].x, evitar[i_ev].z)) < min_d:
			return false
	for r in rocas:
		if centro.distance_to(Vector2(r.pos.x, r.pos.z)) < radio + r.radio + separacion:
			return false
	var y: float = celdas[c]
	if not AyudasL4b.cabe(self, Vector3(centro.x, y, centro.y), radio, 1.0, MASCARA_CUEVA, ELEVACION):
		return false
	var nuevas := _celdas_de_roca(centro, radio)
	var antes: Dictionary = _bloqueadas.duplicate()
	for n in nuevas:
		_bloqueadas[n] = true
	if _anillo_local_conectado(nuevas) or _hay_camino():
		return true
	_bloqueadas = antes
	descartadas += 1
	return false


## Si toda la frontera habitable alrededor de las celdas nuevas sigue conectada entre sí dentro de un radio
## pequeño, esta roca no bloquea ningún corredor de larga distancia (evita recorrer todo el nivel en cada piedra).
func _anillo_local_conectado(nuevas: Array[Vector2i]) -> bool:
	if _bloqueadas.has(_inicio) or _bloqueadas.has(_fin):
		return false
	var caja := Rect2i(nuevas[0], Vector2i.ONE)
	var conjunto_nuevo: Dictionary = {}
	for n in nuevas:
		conjunto_nuevo[n] = true
		caja = caja.merge(Rect2i(n, Vector2i.ONE))
	caja = caja.grow(3)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	var anillo: Array[Vector2i] = []
	var anillo_set: Dictionary = {}
	for n in nuevas:
		for d in dirs:
			var v := n + d
			if v == _inicio or v == _fin:
				return false
			if not conjunto_nuevo.has(v) and not anillo_set.has(v) and celdas.has(v) and not _bloqueadas.has(v):
				anillo_set[v] = true
				anillo.append(v)
	if anillo.size() <= 1:
		return false
	var vistos: Dictionary = {anillo[0]: true}
	var cola: Array[Vector2i] = [anillo[0]]
	var alcanzados := 1
	var head := 0
	while head < cola.size():
		var c := cola[head]
		head += 1
		for d in dirs:
			var v := c + d
			if not caja.has_point(v) or vistos.has(v) or not celdas.has(v) or _bloqueadas.has(v):
				continue
			vistos[v] = true
			if anillo_set.has(v):
				alcanzados += 1
				if alcanzados == anillo.size():
					return true
			cola.append(v)
	return alcanzados == anillo.size()


func _celdas_de_roca(centro: Vector2, radio: float) -> Array[Vector2i]:
	var r: Array[Vector2i] = []
	var alcance := radio + HOLGURA
	var n := int(ceil(alcance / PASO))
	var c0 := Vector2i(roundi(centro.x / PASO), roundi(centro.y / PASO))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var c := c0 + Vector2i(i, j)
			if _a_mundo(c).distance_to(centro) < alcance:
				r.append(c)
	return r


func _hay_camino() -> bool:
	if _bloqueadas.has(_inicio) or _bloqueadas.has(_fin):
		return false
	var vistos: Dictionary = {_inicio: true}
	var cola: Array[Vector2i] = [_inicio]
	var cabeza := 0
	while cabeza < cola.size():
		var c := cola[cabeza]
		cabeza += 1
		if c == _fin:
			return true
		# Las mismas 8 direcciones que la exploración: en los pasos estrechos de las vigas solo hay enlace en diagonal.
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if vistos.has(n) or not celdas.has(n) or _bloqueadas.has(n):
				continue
			vistos[n] = true
			cola.append(n)
	return false


# --- Una roca -----------------------------------------------------------------------------------------------------

func _poner(tipo: String, c: Vector2i, radio: float, numero: int, azar: RandomNumberGenerator) -> void:
	var r := Roca.new()
	r.id = "n%d_%02d" % [nivel, numero]
	r.tipo = tipo
	r.radio = radio
	var xz := _a_mundo(c)
	r.pos = Vector3(xz.x, float(celdas[c]), xz.y)

	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Roca_" + r.id
	cuerpo.collision_layer = CAPA_SOLO_JUGADOR
	cuerpo.collision_mask = 0
	add_child(cuerpo)
	cuerpo.global_position = r.pos + Vector3(0, -0.06, 0)
	cuerpo.rotation.y = azar.randf_range(0.0, TAU)
	var mi := MeshInstance3D.new()
	mi.name = "Malla"
	mi.mesh = _malla(tipo, azar.randi(), radio)
	cuerpo.add_child(mi)
	var cs := CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = radio * 0.85
	cs.shape = esfera
	cs.position = Vector3(0, radio * 0.4, 0)
	cuerpo.add_child(cs)
	var p := Interactuable.new()
	p.name = "Picar"
	p.verbo = "Picar"
	p.herramienta = "pico"
	p.nombre_objeto = str(TIPOS[tipo]["nombre"])
	p.radio = radio
	p.altura_marca = radio * 0.8 + 0.9
	p.mostrar_descripcion = false
	p.nodo_visual = NodePath("..")
	p.usado.connect(_picar_apuntada.bind(r))
	cuerpo.add_child(p)

	r.cuerpo = cuerpo
	r.punto = p
	r.malla = mi
	rocas.append(r)
	for n in _celdas_de_roca(Vector2(xz.x, xz.y), radio):
		_bloqueadas[n] = true


func _quitar(r: Roca) -> void:
	r.rota = true
	if r.punto != null and is_instance_valid(r.punto):
		r.punto.activo = false
		r.punto.remove_from_group("interactuable")
	if r.cuerpo != null and is_instance_valid(r.cuerpo):
		r.cuerpo.collision_layer = 0
		r.cuerpo.visible = false
		r.cuerpo.queue_free()


# --- Picar -------------------------------------------------------------------------------------------------------------

## Rocas que quedan sin romper.
func rocas_en_pie() -> Array[Roca]:
	var r: Array[Roca] = []
	for x in rocas:
		if not x.rota:
			r.append(x)
	return r


func cuenta_de(tipo: String) -> int:
	var n := 0
	for r in rocas_en_pie():
		if r.tipo == tipo:
			n += 1
	return n


func golpes_necesarios(r: Roca) -> int:
	return maxi(1, int(TIPOS[r.tipo]["golpes"]) - Juego.nivel("pico"))


static func energia_por_golpe() -> float:
	var base := 1.0
	match Juego.nivel("pico"):
		0:
			base = 2.0
		1:
			base = 1.5
	return base * Juego.factor_energia_habilidad("mineria")


func roca_cercana(punto: Vector3, margen: float = DIST_USO) -> Roca:
	var mejor: Roca = null
	var d_mejor := INF
	for r in rocas_en_pie():
		var d := Vector2(r.pos.x - punto.x, r.pos.z - punto.z).length()
		if d <= r.radio + margen and d < d_mejor:
			d_mejor = d
			mejor = r
	return mejor


## Lo llama el jugador al usar una herramienta (grupo «usable»): si hay una roca delante y es el pico, la golpea.
func usar(id_objeto: String, punto: Vector3, _jugador: Node3D) -> bool:
	if not construido:
		return false
	var r := roca_cercana(punto)
	if r == null:
		return false
	if id_objeto != "pico":
		Interfaz.mensaje("Esta roca solo cede a golpes de pico.")
		return false
	return golpear(r)


## Golpea la roca concreta elegida por la mira.
func _picar_apuntada(jugador: Node3D, r: Roca) -> void:
	if Juego.cantidad("pico") <= 0:
		Interfaz.mensaje("Necesitas un pico para picar la roca.")
		return
	if golpear(r) and jugador != null and jugador.has_method("animar_herramienta"):
		jugador.call("animar_herramienta")


## Un golpe de pico: gasta energía, la roca tiembla y, al último, se rompe y suelta lo suyo. Devuelve true si golpeó.
func golpear(r: Roca) -> bool:
	if r.rota:
		return false
	if not Juego.gastar_energia(energia_por_golpe()):
		return false
	Audio.reproducir("pico")
	EfectosAccion.soltar(self, "picar", r.pos + Vector3(0.0, r.radio * 0.38, 0.0), TIPOS[r.tipo]["color"] as Color)
	CamaraJuego.sacudir_activa(0.055, 0.18)
	r.golpes_dados += 1
	Juego.ganar_xp_habilidad("mineria", 4)
	if r.golpes_dados >= golpes_necesarios(r):
		_romper(r)
	else:
		_temblar(r)
	return true


func _temblar(r: Roca) -> void:
	if r.cuerpo == null or not is_instance_valid(r.cuerpo):
		return
	var t := r.cuerpo.create_tween()
	t.tween_property(r.malla, "scale", Vector3(1.1, 0.9, 1.1), 0.05)
	t.tween_property(r.malla, "rotation:z", 0.07, 0.05)
	t.tween_property(r.malla, "rotation:z", -0.05, 0.06)
	t.tween_property(r.malla, "scale", Vector3.ONE, 0.06)
	t.tween_property(r.malla, "rotation:z", 0.0, 0.05)


## Rompe la roca: suelta objetos (van al inventario), salta algo de gravilla y no vuelve a salir hasta mañana.
func _romper(r: Roca) -> void:
	var info: Dictionary = TIPOS[r.tipo]
	var n := randi_range(int(info["min"]), int(info["max"])) + (1 if randf() < Juego.bono_suerte_minera() else 0)
	Juego.anadir_objeto(r.tipo, n)
	var extra := str(info["extra"])
	if not extra.is_empty() and randf() < (0.5 + Juego.bono_suerte_minera() * 0.5):
		Juego.anadir_objeto(extra, 1)
	var xp_roca := 22 if r.tipo in ["oro", "amatista", "rubi", "diamante"] else (16 if r.tipo in ["hierro", "cuarzo"] else 12)
	Juego.ganar_xp_habilidad("mineria", xp_roca)
	var est := estado()
	if not (est["rotas"] as Array).has(r.id):
		(est["rotas"] as Array).append(r.id)
	TareasDiarias.registrar_progreso("minar", 1)
	_gravilla(r)
	_quitar(r)


func _gravilla(r: Roca) -> void:
	var base: Color = (TIPOS[r.tipo]["color"] as Color)
	for i in 7:
		var trozo := MeshInstance3D.new()
		var caja := BoxMesh.new()
		var lado := randf_range(0.07, 0.16)
		caja.size = Vector3(lado, lado * 0.8, lado)
		trozo.mesh = caja
		trozo.material_override = _material("grava_" + r.tipo, base, 0.0, false)
		add_child(trozo)
		trozo.global_position = r.pos + Vector3(0, r.radio * 0.5, 0)
		var a := randf() * TAU
		var destino := r.pos + Vector3(cos(a), 0.05, sin(a)) * randf_range(0.5, 1.2)
		var t := trozo.create_tween()
		t.set_parallel(true)
		t.tween_property(trozo, "global_position", destino, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(trozo, "scale", Vector3.ONE * 0.05, 0.7).set_delay(0.3)
		t.chain().tween_callback(trozo.queue_free)


# --- Mallas y materiales --------------------------------------------------------------------------------------------

static func _material(clave: String, color: Color, brillo: float, vertices: bool, doble_cara: bool = false) -> StandardMaterial3D:
	if _materiales.has(clave) and is_instance_valid(_materiales[clave]):
		return _materiales[clave]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.88 if vertices else 0.22
	if not vertices:
		m.metallic = 0.32
		m.metallic_specular = 0.78
	if vertices:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		const BASE := "res://assets/texturas/h04/rock_wall_08/rock_wall_08_%s_1k.jpg"
		if ResourceLoader.exists(BASE % "diff"):
			m.albedo_texture = load(BASE % "diff")
		if ResourceLoader.exists(BASE % "nor_gl"):
			m.normal_enabled = true
			m.normal_texture = load(BASE % "nor_gl")
			m.normal_scale = 0.75
		if ResourceLoader.exists(BASE % "rough"):
			m.roughness_texture = load(BASE % "rough")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.75, 0.75, 0.75)
	if brillo > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = brillo
	if doble_cara:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materiales[clave] = m
	return m


## Roca picable con relieve PBR y gemas/pepitas con brillo cristalino contenido (sin quemar blancos).
static func _malla(tipo: String, semilla: int, radio: float) -> ArrayMesh:
	var azar := RandomNumberGenerator.new()
	azar.seed = semilla
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 2.0
	esfera.radial_segments = 8
	esfera.rings = 4
	var arr := esfera.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ruido: Dictionary = {}
	var def := PackedVector3Array()
	for v in vs:
		var clave := Vector3i(roundi(v.x * 50.0), roundi(v.y * 50.0), roundi(v.z * 50.0))
		if not ruido.has(clave):
			ruido[clave] = azar.randf_range(0.76, 1.18)
		var q := Vector3(v.x, v.y * 0.64, v.z * 0.92) * float(ruido[clave]) * radio
		q.y = maxf(q.y, -0.10 * radio)
		def.append(q)
	var base: Color = (TIPOS[tipo]["color"] as Color).lightened(0.24)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for t in range(0, ix.size(), 3):
		var tono := azar.randf_range(0.86, 1.12)
		st.set_color(Color(base.r * tono, base.g * tono, base.b * tono))
		for k in 3:
			st.add_vertex(def[ix[t + k]])
	st.generate_normals()
	var malla := st.commit()
	malla.surface_set_material(0, _material("roca", Color.WHITE, 0.0, true))
	if tipo == "piedra":
		return malla
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_smooth_group(-1)
	var es_gema := tipo in ["cuarzo", "amatista", "rubi", "diamante"]
	var cuantas := 4 if es_gema else 6
	for i in cuantas:
		var dir := Vector3(azar.randf_range(-1.0, 1.0), azar.randf_range(0.3, 1.0), azar.randf_range(-1.0, 1.0)).normalized()
		var sobre := Vector3(dir.x, dir.y * 0.64, dir.z * 0.92) * radio * 0.96
		if es_gema:
			_cristal(st2, sobre, dir, radio * azar.randf_range(0.42, 0.72), radio * azar.randf_range(0.09, 0.14))
		else:
			_pepita(st2, sobre, radio * azar.randf_range(0.12, 0.20))
	st2.generate_normals()
	st2.commit(malla)
	var color_mena := Color(0.84, 0.44, 0.22)
	var brillo := 0.35
	match tipo:
		"hierro":
			color_mena = Color(0.54, 0.64, 0.78)
			brillo = 0.22
		"cuarzo":
			color_mena = Color(0.72, 0.90, 0.98)
			brillo = 0.78
		"oro":
			color_mena = Color(0.95, 0.72, 0.14)
			brillo = 0.55
		"amatista":
			color_mena = Color(0.68, 0.32, 0.95)
			brillo = 0.90
		"rubi":
			color_mena = Color(0.92, 0.14, 0.24)
			brillo = 0.95
		"diamante":
			color_mena = Color(0.48, 0.88, 1.0)
			brillo = 1.05
	malla.surface_set_material(1, _material("mena_" + tipo, color_mena, brillo, false, true))
	return malla


static func _pepita(st: SurfaceTool, c: Vector3, r: float) -> void:
	var px := c + Vector3(r, 0, 0)
	var nx := c - Vector3(r, 0, 0)
	var py := c + Vector3(0, r * 1.1, 0)
	var ny := c - Vector3(0, r * 0.7, 0)
	var pz := c + Vector3(0, 0, r)
	var nz := c - Vector3(0, 0, r)
	for t in [[px, py, pz], [pz, py, nx], [nx, py, nz], [nz, py, px], [px, pz, ny], [pz, nx, ny], [nx, nz, ny], [nz, px, ny]]:
		for v in t:
			st.add_vertex(v)


static func _cristal(st: SurfaceTool, p: Vector3, dir: Vector3, largo: float, ancho: float) -> void:
	var u := dir.cross(Vector3.UP)
	if u.length() < 0.1:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := dir.cross(u).normalized()
	var b0 := p + (u + w) * ancho
	var b1 := p + (u - w) * ancho
	var b2 := p + (-u - w) * ancho
	var b3 := p + (-u + w) * ancho
	var cima := p + dir * largo
	for t in [[b0, b1, cima], [b1, b2, cima], [b2, b3, cima], [b3, b0, cima]]:
		for v in t:
			st.add_vertex(v)
