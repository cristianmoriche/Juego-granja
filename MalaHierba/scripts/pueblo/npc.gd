class_name Npc
extends CharacterBody3D
## Un vecino del pueblo (L4b). Cuerpo en la capa 5 (npc), modelo `assets/personajes/aldeanos/<modelo>.glb`
## (si falta, una cápsula con su nombre). De día pasea despacio alrededor de su sitio (`centro`, `radio`),
## y al hablar mira a Leo y lo saluda. La charla en sí está en `Conversacion`.
##
## Lo crea `Vecinos` con `Npc.crear(datos)`. `datos` viene de `datos/npcs.json` o de `datos/vecinos_relleno.json`
## (en este último caso `datos["relleno"] = true`: sin amistad ni regalos).

const ESCENA := "res://escenas/npc/npc.tscn"
const RUTA_MODELO := "res://assets/personajes/aldeanos/%s.glb"
const VEL_PASEO := 0.9
const VEL_VIAJE := 1.7
const GRAVEDAD := 24.0
const PALABRAS_ROPA: Array[String] = ["chal", "falda", "chaleco", "bufanda", "pano"]
## Modelos propios de los vecinos (2026-11-16, riggeados por un compañero): sus animaciones se llaman Idle, Walk, Talk
## y una de oficio distinta en cada uno (Hammer_Forge, Count_Coins…). Se dan de alta con los nombres del juego.
const ALIAS_ANIM := {"reposo": ["Idle"], "andar": ["Walk"], "saludar": ["Wave_Greeting", "Talk"], "hablar": ["Talk"]}
const ANIMS_BASE: Array[String] = ["Idle", "Walk", "Talk", "Wave_Greeting", "reposo", "andar", "saludar", "hablar", "RESET"]
const PUESTOS_TRABAJO := {
	"mateo": {"mapa": "tienda", "marcador": "Puesto_Mateo", "desde": 540, "hasta": 1140},
	"clara": {"mapa": "herreria", "marcador": "Puesto_Clara", "desde": 480, "hasta": 1080},
	"ramon": {"mapa": "taberna", "marcador": "Puesto_Ramon", "desde": 720, "hasta": 1440},
	"anselmo": {"mapa": "casa_alcalde", "marcador": "Puesto_Anselmo", "desde": 480, "hasta": 780},
	"tomas": {"mapa": "mina_exterior", "marcador": "Spawn_Minero", "desde": 360, "hasta": 1080},
}

var datos: Dictionary = {}
var id: String = ""
var nombre: String = ""
var relleno: bool = false
## Sitio alrededor del que pasea y radio del paseo (m). Radio 0: se queda quieto.
var centro: Vector3 = Vector3.ZERO
var radio: float = 3.0
## Marcador (o clave de sitio) en el que está ahora; lo usa `Vecinos` para saber si debe moverse.
var sitio_actual: String = ""
## Nivel de animación/ánimo (0.0 habitual, hasta 1.0 al pagar deuda o en festividad).
var animo: float = 0.0
var _t_saludo_animado: float = 0.0

var _modelo: Node3D = null
var _anim: AnimationPlayer = null
var _anim_actual: String = ""
## Animación de oficio del modelo propio (vacía en los modelos antiguos); la hace de vez en cuando estando quieto.
var _anim_oficio: String = ""
var _punto: Interactuable = null
var _estado: String = "quieto"        # quieto | andando
var _viajando: bool = false
var _espera: float = 1.0
var _destino: Vector3 = Vector3.ZERO
var _atasco: float = 0.0
var _t_charla: float = 0.0
var _mirar_a: Vector3 = Vector3.INF
var _giro: float = 0.0
var _t_saludo: float = 0.0
var _alto_visible: float = 1.75
var _listo: bool = false
var _mapa: Node = null          # el mapa en el que está (para no salirse del área jugable)
var _saliendo: bool = false
var ruta_diaria: Array[Vector3] = []
var ruta_dia_clave: int = -1
var _indice_ruta: int = 0


## Crea un vecino con sus datos (aún sin añadir al árbol).
static func crear(d: Dictionary) -> Npc:
	var n := (CargadorMapa.obtener_recurso(ESCENA) as PackedScene).instantiate() as Npc
	n.datos = d
	n.id = str(d.get("id", ""))
	n.nombre = str(d.get("nombre", n.id))
	n.relleno = bool(d.get("relleno", false))
	n.radio = float(d.get("radio", 3.0))
	n.name = "Vecino_" + n.id
	return n


func _ready() -> void:
	_modelo = $Modelo
	_cargar_modelo()
	_punto = Interactuable.new()
	_punto.name = "Hablar"
	_punto.verbo = "Hablar con"
	_punto.nombre_objeto = nombre
	_punto.mostrar_nombre = true
	_punto.mostrar_descripcion = false
	_punto.radio = 0.7
	_punto.altura_marca = _alto_visible + 0.45   # antes 2,2 m fijos (~40 cm sobre la cabeza): ahora sigue a cada modelo
	_punto.usado.connect(_al_usar)
	add_child(_punto)
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	_mapa = n
	_giro = randf() * TAU
	_modelo.rotation.y = _giro
	_espera = randf_range(0.5, 3.0)
	floor_snap_length = 0.4
	_listo = true


## Coloca al vecino en un sitio y lo toma como su centro de paseo.
func colocar_en(pos: Vector3, clave_sitio: String) -> void:
	global_position = pos
	centro = pos
	sitio_actual = clave_sitio
	_estado = "quieto"
	_viajando = false


## Camina hasta un sitio nuevo (cambio de horario dentro del mismo mapa) y allí pasea.
func ir_a(pos: Vector3, clave_sitio: String) -> void:
	centro = pos
	sitio_actual = clave_sitio
	_destino = pos
	_estado = "andando"
	_viajando = true
	_atasco = 0.0


func fijar_ruta_diaria(puntos: Array[Vector3], dia_clave: int) -> void:
	ruta_diaria = puntos.duplicate()
	ruta_dia_clave = dia_clave
	_indice_ruta = 0


func es_oficio_comercial() -> bool:
	return PUESTOS_TRABAJO.has(id)


## Solo habilita tienda/forja/barra/deuda/minerales cuando el NPC atiende en su lugar y horario de trabajo.
func en_lugar_trabajo() -> bool:
	if not PUESTOS_TRABAJO.has(id) or _saliendo:
		return false
	var cfg: Dictionary = PUESTOS_TRABAJO[id]
	var id_m := str(_mapa.get("id_mapa")) if _mapa != null else Juego.mapa_actual
	if id_m != str(cfg["mapa"]):
		return false
	if not sitio_actual.begins_with(str(cfg["marcador"]) + "|"):
		return false
	return Juego.minutos >= int(cfg["desde"]) and Juego.minutos < int(cfg["hasta"])


## Leo ha empezado a hablar: se detiene, lo mira y saluda.
func empezar_charla(jugador: Node3D) -> void:
	_t_charla = 1.0
	_mirar_a = jugador.global_position
	if jugador.has_method("encuadrar_interlocutor"):
		jugador.call("encuadrar_interlocutor", self)
	_estado = "quieto"
	_t_saludo = 2.0
	_reproducir("saludar", 0.15)


func punto_ojos() -> Vector3:
	return global_position + Vector3.UP * (_alto_visible - 0.14)


## Aparece con un pequeño crecimiento (llega a su sitio según el horario).
func aparecer() -> void:
	_modelo.scale = Vector3.ONE * 0.02
	var t := create_tween()
	t.tween_property(_modelo, "scale", Vector3.ONE, 0.5)


## Se va (fin de su horario en este mapa): deja de poder hablarse, desaparece encogiéndose y se borra.
func retirarse() -> void:
	if _saliendo:
		return
	_saliendo = true
	remove_from_group("npc")
	if _punto != null:
		_punto.activo = false
	collision_layer = 0
	collision_mask = 0
	var t := create_tween()
	t.tween_property(_modelo, "scale", Vector3.ONE * 0.02, 0.6)
	t.finished.connect(_terminar_retirada)


func esta_charlando() -> bool:
	return _t_charla > 0.0


func _al_usar(jugador: Node3D) -> void:
	Conversacion.hablar(self, jugador)


# --- Movimiento -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _listo:
		return
	var quieto_forzado: bool = Interfaz.ocupada() or Escenas.en_transicion
	if Interfaz.ocupada() and _t_charla > 0.0:
		_t_charla = 1.0
	elif _t_charla > 0.0:
		_t_charla -= delta
		if _t_charla <= 0.0:
			_mirar_a = Vector3.INF
	var horizontal := Vector3.ZERO
	if not quieto_forzado and _t_charla <= 0.0:
		horizontal = _paseo(delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVEDAD * delta
	move_and_slide()
	_girar(delta, horizontal)
	_animar(horizontal)


func _paseo(delta: float) -> Vector3:
	if _estado == "quieto":
		_espera -= delta
		_t_saludo_animado = maxf(_t_saludo_animado - delta, 0.0)
		if animo >= 0.45 and _t_saludo_animado <= 0.0 and _t_saludo <= 0.0 and _anim != null and _anim.has_animation("saludar"):
			if randf() < 0.012:
				_t_saludo = 1.15
				_t_saludo_animado = randf_range(7.0, 14.0)
				_reproducir("saludar", 0.2)
		if not _anim_oficio.is_empty() and _t_saludo <= 0.0 and _espera > 1.0 and randf() < 0.0015:
			var largo := _anim.get_animation(_anim_oficio).length
			_t_saludo = largo
			_espera = maxf(_espera, largo + 0.3)
			_reproducir(_anim_oficio, 0.25)
		if _espera <= 0.0 and radio > 0.2:
			_elegir_destino()
		return Vector3.ZERO
	var d := _destino - global_position
	d.y = 0.0
	if d.length() < 0.3:
		_estado = "quieto"
		_viajando = false
		_espera = randf_range(1.6, 4.4) if animo >= 0.45 else randf_range(3.0, 9.0)
		return Vector3.ZERO
	# Atasco: si apenas avanza durante casi un segundo, desiste y espera.
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	var vel := VEL_VIAJE if _viajando else VEL_PASEO * (1.0 + animo * 0.22)
	if real < vel * 0.25:
		_atasco += delta
		if _atasco > 0.9:
			_atasco = 0.0
			_estado = "quieto"
			_espera = randf_range(1.0, 3.0)
			if _viajando:
				# No llega: se queda donde está y toma ese sitio como centro.
				_viajando = false
				centro = global_position
			return Vector3.ZERO
	else:
		_atasco = 0.0
	return d.normalized() * vel


func _elegir_destino() -> void:
	if ruta_diaria.size() >= 2:
		var vueltas := ruta_diaria.size()
		for k in vueltas:
			_indice_ruta = (_indice_ruta + 1) % ruta_diaria.size()
			var base_r := ruta_diaria[_indice_ruta]
			var des := Vector3(randf_range(-0.65, 0.65), 0.0, randf_range(-0.65, 0.65))
			var s := AyudasL4b.suelo(self, base_r + des, 1.5, 4.0)
			if s == Vector3.INF or absf(s.y - base_r.y) > 0.9:
				continue
			if _mapa != null and _mapa.has_method("punto_dentro") and not bool(_mapa.call("punto_dentro", s, 1.2)):
				continue
			if not AyudasL4b.cabe(self, s, 0.45):
				continue
			_destino = s
			_estado = "andando"
			_atasco = 0.0
			return
	for i in 8:
		var a := randf() * TAU
		var r := randf_range(0.8, maxf(radio, 1.0))
		var p := centro + Vector3(cos(a), 0, sin(a)) * r
		var s := AyudasL4b.suelo(self, p, 1.5, 4.0)
		if s == Vector3.INF or absf(s.y - centro.y) > 0.7:
			continue
		if _mapa != null and _mapa.has_method("punto_dentro") and not bool(_mapa.call("punto_dentro", s, 1.2)):
			continue
		if not AyudasL4b.cabe(self, s, 0.45):
			continue
		_destino = s
		_estado = "andando"
		_atasco = 0.0
		return
	_espera = randf_range(2.0, 5.0)


func _girar(delta: float, horizontal: Vector3) -> void:
	var objetivo := _giro
	if _mirar_a != Vector3.INF:
		var d := _mirar_a - global_position
		d.y = 0.0
		if d.length() > 0.05:
			objetivo = atan2(d.x, d.z)
	elif horizontal.length() > 0.05:
		objetivo = atan2(horizontal.x, horizontal.z)
	_giro = objetivo
	_modelo.rotation.y = lerp_angle(_modelo.rotation.y, objetivo, 1.0 - exp(-8.0 * delta))


func _animar(horizontal: Vector3) -> void:
	_t_saludo = maxf(_t_saludo - get_physics_process_delta_time(), 0.0)
	if _t_saludo > 0.0:
		return
	if horizontal.length() > 0.05:
		_reproducir("andar", 0.2, 1.15 if _viajando else 0.8)
	elif _t_charla > 0.0 and _anim != null and _anim.has_animation("hablar"):
		_reproducir("hablar", 0.25)
	else:
		_reproducir("reposo", 0.25)


func _reproducir(anim: String, mezcla: float = 0.2, velocidad: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	_anim.speed_scale = velocidad
	if _anim_actual != anim:
		_anim_actual = anim
		_anim.play(anim, mezcla)


# --- Modelo ---------------------------------------------------------------------------------------

func _cargar_modelo() -> void:
	var modelo := str(datos.get("modelo", ""))
	var ruta := RUTA_MODELO % modelo
	# M2: la escala común de los personajes (la misma que Leo). `datos["escala"]` es el pequeño ajuste propio de cada vecino
	# de relleno (0,96–1,03) y se aplica encima de esa; así cada modelo conserva su altura relativa (el niño sigue más bajo).
	var esc := float(datos.get("escala", 1.0)) * EscalaPersonaje.ESCALA
	if not modelo.is_empty() and ResourceLoader.exists(ruta):
		var ps := CargadorMapa.obtener_recurso(ruta) as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			inst.scale = Vector3.ONE * esc
			_modelo.add_child(inst)
			_alto_visible = _altura_de(inst, esc)
			var anims := inst.find_children("*", "AnimationPlayer", true, false)
			if not anims.is_empty():
				_anim = anims[0] as AnimationPlayer
				_alias_animaciones()
				for a in ["reposo", "andar", "hablar"]:
					var an: Animation = _anim.get_animation(a) if _anim.has_animation(a) else null
					if an != null:
						an.loop_mode = Animation.LOOP_LINEAR
				var sal := _anim.get_animation("saludar")
				var habla: Animation = _anim.get_animation("hablar") if _anim.has_animation("hablar") else null
				if sal != null and sal != habla:
					sal.loop_mode = Animation.LOOP_NONE
				if not _anim_oficio.is_empty():
					_anim.get_animation(_anim_oficio).loop_mode = Animation.LOOP_NONE
				_reproducir("reposo", 0.0)
			_teñir(inst, datos.get("tinte", {}))
			var propio := modelo == id
			if propio:
				_quitar_metal(inst)
			var sombrero := str(datos.get("sombrero", ""))
			if not sombrero.is_empty() and not propio:
				_poner_sombrero(inst, sombrero, esc)
			return
	_modelo_de_emergencia()


## Materiales ya corregidos por `_quitar_metal` (original → copia), para que las instancias compartan la copia.
static var _sin_metal: Dictionary = {}


## Los modelos propios traen `metallicRoughnessTexture` sin `metallicFactor` (glTF lo toma como 1) y con la piel casi
## lisa en la textura de rugosidad: la piel y las manos brillaban como plástico. Se dejan sin metal, mates y con poco
## reflejo especular; la textura de color no se toca.
func _quitar_metal(inst: Node3D) -> void:
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null or m.metallic_texture == null:
				continue
			if not _sin_metal.has(m):
				var copia := m.duplicate() as BaseMaterial3D
				copia.metallic = 0.0
				copia.metallic_texture = null
				copia.roughness_texture = null
				copia.roughness = 0.88
				copia.metallic_specular = 0.25
				_sin_metal[m] = copia
			mi.set_surface_override_material(s, _sin_metal[m])


## Da a las animaciones de los modelos nuevos (Idle, Walk, Talk…) los nombres que usa el juego y localiza la de oficio.
## La biblioteca es compartida entre instancias del mismo modelo: solo se añade lo que falte.
func _alias_animaciones() -> void:
	var lib := _anim.get_animation_library("")
	if lib == null:
		return
	for nuevo: String in ALIAS_ANIM:
		if lib.has_animation(nuevo):
			continue
		for orig: String in ALIAS_ANIM[nuevo]:
			if lib.has_animation(orig):
				lib.add_animation(nuevo, lib.get_animation(orig))
				break
	if lib.has_animation("Idle"):
		for a in lib.get_animation_list():
			if not ANIMS_BASE.has(str(a)):
				_anim_oficio = str(a)
				break


## Cambia el color de pelo y de la ropa lisa (los materiales sin textura) de este vecino sin tocar el modelo compartido.
func _teñir(inst: Node3D, tinte: Variant) -> void:
	if not (tinte is Dictionary) or (tinte as Dictionary).is_empty():
		return
	var t: Dictionary = tinte
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null or m.albedo_texture != null:
				continue
			var nom := m.resource_name.to_lower()
			var color := Color.BLACK
			var hay := false
			if nom.contains("pelo") and t.has("pelo"):
				color = Color(str(t["pelo"]))
				hay = true
			elif t.has("ropa"):
				for p in PALABRAS_ROPA:
					if nom.contains(p):
						color = Color(str(t["ropa"]))
						hay = true
						break
			if hay:
				var copia := m.duplicate() as BaseMaterial3D
				copia.albedo_color = color
				mi.set_surface_override_material(s, copia)


## Altura (m) del modelo ya escalado: lo más alto de sus mallas.
func _altura_de(inst: Node3D, esc: float) -> float:
	var h := 0.0
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			h = maxf(h, mi.get_aabb().end.y)
	return h * esc


func _poner_sombrero(inst: Node3D, tipo: String, esc: float) -> void:
	# Altura de la coronilla: la malla del pelo (si no, 1,75 m).
	var cima := 1.75
	var cx := 0.0
	var cz := 0.0
	for n in inst.find_children("*pelo*", "MeshInstance3D", true, false):
		var ab := (n as MeshInstance3D).get_aabb()
		cima = ab.end.y
		cx = ab.get_center().x
		cz = ab.get_center().z
		break
	var raiz := Node3D.new()
	raiz.name = "Sombrero"
	raiz.position = Vector3(cx, cima - 0.07, cz) * esc
	_modelo.add_child(raiz)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	if tipo == "paja":
		mat.albedo_color = Color("#d4b36a")
		var ala := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 0.30
		cil.bottom_radius = 0.32
		cil.height = 0.025
		ala.mesh = cil
		ala.material_override = mat
		raiz.add_child(ala)
		var copa := MeshInstance3D.new()
		var cil2 := CylinderMesh.new()
		cil2.top_radius = 0.14
		cil2.bottom_radius = 0.17
		cil2.height = 0.15
		copa.mesh = cil2
		copa.material_override = mat
		copa.position = Vector3(0, 0.08, 0)
		raiz.add_child(copa)
	else:   # boina
		mat.albedo_color = Color("#3a3d44")
		var b := MeshInstance3D.new()
		var esf := SphereMesh.new()
		esf.radius = 0.20
		esf.height = 0.22
		b.mesh = esf
		b.material_override = mat
		b.scale = Vector3(1.0, 0.55, 1.0)
		b.position = Vector3(0.01, 0.04, 0)
		raiz.add_child(b)


## Cápsula con el nombre encima, por si falta el modelo.
func _modelo_de_emergencia() -> void:
	var raiz := Node3D.new()
	raiz.name = "Emergencia"
	raiz.scale = Vector3.ONE * EscalaPersonaje.ESCALA
	_modelo.add_child(raiz)
	var cuerpo := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.7
	cuerpo.mesh = cap
	cuerpo.position = Vector3(0, 0.85, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(float(abs(id.hash()) % 100) / 100.0, 0.45, 0.8)
	cuerpo.material_override = mat
	raiz.add_child(cuerpo)
	var nariz := MeshInstance3D.new()
	var caja := BoxMesh.new()
	caja.size = Vector3(0.16, 0.16, 0.26)
	nariz.mesh = caja
	nariz.position = Vector3(0, 1.4, 0.34)
	raiz.add_child(nariz)
	var et := Label3D.new()
	et.text = nombre
	et.position = Vector3(0, 2.0, 0)
	et.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	et.pixel_size = 0.006
	raiz.add_child(et)


## Separa la geometría antes de liberar sus materiales tras la animación de salida.
func _terminar_retirada() -> void:
	for n: Node in _modelo.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).mesh = null
	await get_tree().process_frame
	queue_free()
