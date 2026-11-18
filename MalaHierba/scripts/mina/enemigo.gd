class_name Enemigo
extends CharacterBody3D
## Enemigos de la mina (T26 + E1).
## Cada enemigo sale de datos/enemigos.json (estadísticas, niveles, modelo, tamaño) y usa su modelo 3D de
## assets/enemigos/<id>.glb con las animaciones del compañero: reposo, andar, atacar, golpeado y morir.
## Los jefes añaden un ataque especial (embestida, lengua, cristales) y el gusano de magma emerge y se hunde.
## Si no hay modelo, queda la cápsula invisible de marcador (pruebas antiguas).

signal atacado(dano: float)
signal fallecido(enemigo: Enemigo)
signal vida_cambiada(actual: float, maximo: float)

const ACTIVOS := true
const RUTA_DATOS := "res://datos/enemigos.json"
const RUTA_SHADER_EMISION := "res://shaders/enemigo_emision.gdshader"
const GRAVEDAD := 20.0
const CAPA_MUROS := 1
const CAPA_ROCAS := 64
const OBSTACULOS := 1 | 16 | 32 | 64 | 128
const GRUPO_ATAQUE := &"enemigos_atacando"
const ATACANTES_MAX := 2
const BOTIN := preload("res://scripts/mina/botin_enemigo.gd")
const EFECTOS := preload("res://scripts/mina/efectos_combate.gd")
const DANO_PICO_BASE := 14.0
const DANO_PICO_POR_NIVEL := 6.0

## Nombres lógicos -> nombres posibles dentro del .glb (el primero que exista). Los .glb no traen `volar`,
## `ataque_especial`, `emerger` ni `hundirse`: se usan `andar` y `atacar`, y el gusano emerge/se hunde por código.
const ALIAS_ANIMACION := {
	"reposo": ["reposo", "ANIM_Reposo", "Reposo"],
	"andar": ["andar", "ANIM_Andar", "Andar"],
	"volar": ["volar", "andar", "ANIM_Andar"],
	"atacar": ["atacar", "ANIM_Atacar", "Atacar"],
	"golpeado": ["golpeado", "ANIM_Golpeado", "Golpeado"],
	"morir": ["morir", "ANIM_Morir", "Morir"],
	"ataque_especial": ["ataque_especial", "atacar", "ANIM_Atacar"],
	"emerger": ["emerger"],
	"hundirse": ["hundirse"],
}
const ANIM_EN_BUCLE := ["reposo", "andar", "volar", "ANIM_Reposo", "ANIM_Andar", "Reposo", "Andar"]

enum Estado { LIBRE, ATACAR, GOLPEADO, ESPECIAL, HUNDIDO, EMERGER, HUNDIENDO, BAJO_TIERRA, RECUPERANDO, PATRULLA, PERSECUCION, HUIDA }

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
var es_jefe: bool = false
var especial: String = ""
var tamano: float = 0.0
var medida: String = "largo"
var giro: float = 0.0
var altura_vuelo: float = 0.0
var emision: Dictionary = {}
var material_impacto := "carne"
var protege_cuerpo := false
var mineral_botin := ""
var unidades_botin := 1

var activo: bool = ACTIVOS
var muerto: bool = false
var objetivo: Node3D = null
var estado: Estado = Estado.LIBRE
var marcador_capsula: MeshInstance3D = null
var modelo: Node3D = null            # instancia del .glb
var pivote: Node3D = null            # contenedor del modelo (giro, altura de vuelo, hundimiento)
var anim: AnimationPlayer = null
var alto_modelo: float = 1.4
var radio_cuerpo: float = 0.35
var radio_impacto: float = 0.6
var luz_brillo: OmniLight3D = null

var _colision: CollisionShape3D = null
var _enfriamiento: float = 0.0
var _cd_especial: float = 3.0
var _t_estado: float = 0.0
var _t_especial: float = 0.0
var _t_impacto: float = 0.0
var _golpe_hecho: bool = false
var _t_muerte: float = 0.0
var _t_bob: float = 0.0
var _t_salto: float = 0.0
var _vy: float = 0.0
var _en_suelo: bool = false
var _dir_embestida: Vector3 = Vector3.ZERO
var _alto_vuelo_actual: float = 0.0
var _instinto := InstintoEnemigo.new()
var _destino_patrulla := Vector3.INF
var _descanso_patrulla := 0.0
var _huyendo := false
var _retroceso := Vector3.ZERO
var _dir_ataque := Vector3.FORWARD
var _pausa_animacion := 0.0
var _retirada_jefe_hecha := false
var _t_retirada_jefe := 0.0


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


static func _en_rango(d: Dictionary, nivel: int) -> bool:
	var nv: Array = d.get("niveles", [1, 20])
	return nv.size() >= 2 and nivel >= int(nv[0]) and nivel <= int(nv[1])


## Todos los enemigos (normales y jefe) de un nivel. Si no hay ninguno, devuelve el catálogo entero.
static func para_nivel(nivel: int) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for d: Dictionary in cargar_definiciones():
		if _en_rango(d, nivel):
			r.append(d)
	if r.is_empty():
		return cargar_definiciones()
	return r


## Enemigos normales (sin jefes) que pueden salir en el nivel.
static func normales_para_nivel(nivel: int) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for d: Dictionary in cargar_definiciones():
		if not bool(d.get("jefe", false)) and _en_rango(d, nivel):
			r.append(d)
	return r


## Jefe del nivel (niveles 5, 10, 15 y 20) o diccionario vacío.
static func jefe_para_nivel(nivel: int) -> Dictionary:
	for d: Dictionary in cargar_definiciones():
		if bool(d.get("jefe", false)) and _en_rango(d, nivel):
			return d
	return {}


func _ready() -> void:
	set_physics_process(activo and not muerto)
	set_process(false)


func configurar(datos: Dictionary) -> void:
	id_enemigo = str(datos.get("id", "enemigo"))
	tipo = str(datos.get("tipo", "generico"))
	nombre_visible = str(datos.get("nombre", id_enemigo))
	vida_max = maxf(float(datos.get("vida", 25.0)), 1.0)
	dano = maxf(float(datos.get("dano", 8.0)), 0.0)
	velocidad = maxf(float(datos.get("velocidad", 3.0)), 0.1)
	alcance_deteccion = maxf(float(datos.get("alcance_deteccion", 10.0)), 1.0)
	alcance_ataque = maxf(float(datos.get("alcance_ataque", 1.4)), 0.5)
	cadencia_ataque = maxf(float(datos.get("cadencia_ataque", 1.1)), 0.2)
	var nv: Array = datos.get("niveles", [1, 20])
	if nv.size() >= 2:
		rango_niveles = Vector2i(int(nv[0]), int(nv[1]))
	var profundidad := clampi(int(datos.get("nivel_mina", rango_niveles.x)) - rango_niveles.x, 0, 19)
	vida_max = roundf(vida_max * (1.0 + 0.028 * profundidad))
	vida = vida_max
	dano *= 1.0 + 0.024 * profundidad
	modelo_ruta = str(datos.get("modelo", ""))
	es_jefe = bool(datos.get("jefe", false))
	especial = str(datos.get("especial", ""))
	tamano = float(datos.get("tamano", 0.0))
	medida = str(datos.get("medida", "largo"))
	giro = float(datos.get("giro", 0.0))
	altura_vuelo = float(datos.get("altura_vuelo", 0.0))
	var em: Variant = datos.get("emision", {})
	emision = em as Dictionary if em is Dictionary else {}
	material_impacto = str(datos.get("material_impacto", "carne"))
	protege_cuerpo = bool(datos.get("guardia", false))
	mineral_botin = str(datos.get("botin", ""))
	unidades_botin = maxi(1, int(datos.get("unidades_botin", 1)))

	name = "Enemigo_%s" % id_enemigo
	collision_layer = 8 # Volumen de apuntado de herramientas, sin contacto físico con Leo.
	collision_mask = CAPA_MUROS | CAPA_ROCAS
	add_to_group("enemigos")
	add_to_group("usable")
	_construir_cuerpo()
	_aplicar_estado_activo()
	if especial == "emerger":
		_hundir_del_todo()


# --- Construcción ---------------------------------------------------------------------------------------

func _construir_cuerpo() -> void:
	if marcador_capsula == null:
		marcador_capsula = MeshInstance3D.new()
		marcador_capsula.name = "MarcadorCapsula"
		var cm := CapsuleMesh.new()
		cm.radius = 0.32
		cm.height = 1.35
		marcador_capsula.mesh = cm
		marcador_capsula.position = Vector3(0.0, 0.7, 0.0)
		marcador_capsula.visible = false   # solo es un marcador: el jugador ve el modelo
		add_child(marcador_capsula)
	if not modelo_ruta.is_empty() and ResourceLoader.exists(modelo_ruta):
		var esc := load(modelo_ruta) as PackedScene
		var inst: Node3D = esc.instantiate() as Node3D if esc != null else null
		if inst != null:
			_montar_modelo(inst)
	if _colision == null:
		_colision = CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radio_cuerpo
		cap.height = maxf(alto_modelo, radio_cuerpo * 2.0 + 0.05)
		_colision.shape = cap
		_colision.position = Vector3(0.0, cap.height * 0.5, 0.0)
		add_child(_colision)
	if modelo != null:
		_aplicar_emision()


func _montar_modelo(inst: Node3D) -> void:
	pivote = Node3D.new()
	pivote.name = "Modelo"
	pivote.rotation.y = deg_to_rad(giro)
	add_child(pivote)
	modelo = inst
	pivote.add_child(inst)
	# Los modelos vienen normalizados a ~2 m: se escalan al tamaño de la tabla y se apoyan en el suelo.
	var caja := _caja_de(inst)
	var ref := caja.size.y if medida == "alto" else maxf(caja.size.x, caja.size.z)
	var f := tamano / maxf(ref, 0.01) if tamano > 0.0 else 1.0
	inst.scale = Vector3.ONE * f
	var c := caja.get_center()
	inst.position = Vector3(-c.x * f, -caja.position.y * f, -c.z * f)
	alto_modelo = caja.size.y * f
	var ancho := minf(caja.size.x, caja.size.z) * f
	radio_cuerpo = clampf(ancho * 0.4, 0.18, 1.1)
	radio_impacto = clampf(maxf(caja.size.x, caja.size.z) * f * 0.4, 0.5, 3.0)
	if tipo == "volador":
		_alto_vuelo_actual = altura_vuelo
		pivote.position.y = altura_vuelo
	var aps := inst.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0] as AnimationPlayer
		for n: String in anim.get_animation_list():
			var a := anim.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if n in ANIM_EN_BUCLE else Animation.LOOP_NONE
		reproducir("reposo", 0.0)


## Caja (en el espacio del modelo, antes de escalar) de todas sus mallas en pose de reposo.
func _caja_de(raiz: Node3D) -> AABB:
	var r := AABB()
	var primero := true
	for n: Node in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != raiz:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var a := xf * mi.get_aabb()
		if primero:
			r = a
			primero = false
		else:
			r = r.merge(a)
	return r


## Brillo (lava, cristal, babosa, polilla): pasada aditiva con los píxeles claros y saturados de su textura + una luz tenue.
func _aplicar_emision() -> void:
	if emision.is_empty() or modelo == null:
		return
	var sh := load(RUTA_SHADER_EMISION) as Shader
	if sh == null:
		return
	var tinte: Array = emision.get("tinte", [1.0, 1.0, 1.0])
	for n: Node in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var dup := base.duplicate() as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("tex_color", base.albedo_texture)
			sm.set_shader_parameter("umbral_luz", float(emision.get("umbral_luz", 0.5)))
			sm.set_shader_parameter("umbral_sat", float(emision.get("umbral_sat", 0.5)))
			sm.set_shader_parameter("fuerza", float(emision.get("fuerza", 1.2)))
			sm.set_shader_parameter("pulso", float(emision.get("pulso", 0.0)))
			if tinte.size() >= 3:
				sm.set_shader_parameter("tinte", Color(float(tinte[0]), float(tinte[1]), float(tinte[2])))
			dup.next_pass = sm
			mi.set_surface_override_material(s, dup)
	var lc: Array = emision.get("luz_color", [1.0, 0.6, 0.3])
	luz_brillo = OmniLight3D.new()
	luz_brillo.name = "LuzBrillo"
	luz_brillo.light_color = Color(float(lc[0]), float(lc[1]), float(lc[2])) if lc.size() >= 3 else Color(1.0, 0.6, 0.3)
	luz_brillo.light_energy = float(emision.get("luz_energia", 0.6))
	luz_brillo.omni_range = clampf(maxf(tamano, 0.6) * 2.4, 2.5, 9.0)
	luz_brillo.shadow_enabled = false
	luz_brillo.position = Vector3(0.0, alto_modelo * 0.5 + altura_vuelo, 0.0)
	add_child(luz_brillo)


func _aplicar_estado_activo() -> void:
	var corriendo := activo and not muerto
	if _colision != null:
		if is_inside_tree():
			_colision.set_deferred("disabled", not corriendo)
		else:
			_colision.disabled = not corriendo
	if not corriendo:
		_liberar_ataque()
	set_physics_process(corriendo)


func activar_para_prueba(valor: bool = true, obj: Node3D = null) -> void:
	activo = valor
	objetivo = obj
	if not muerto:
		_aplicar_estado_activo()


# --- Animaciones ----------------------------------------------------------------------------------------

## Nombre real de la animación para un nombre lógico (vacío si el modelo no la trae).
func nombre_animacion(logico: String) -> String:
	if anim == null:
		return ""
	for n: String in ALIAS_ANIMACION.get(logico, [logico]):
		if anim.has_animation(n):
			return n
	return ""


func tiene_animacion(logico: String) -> bool:
	return not nombre_animacion(logico).is_empty()


## Reproduce una animación por su nombre lógico y devuelve lo que dura (0 si no existe).
func reproducir(logico: String, mezcla: float = 0.15, vel: float = 1.0) -> float:
	var n := nombre_animacion(logico)
	if n.is_empty():
		return 0.0
	var a := anim.get_animation(n)
	var bucle := a.loop_mode != Animation.LOOP_NONE
	if not (bucle and anim.current_animation == n and anim.is_playing()):
		anim.play(n, mezcla, vel)
	return a.length / maxf(absf(vel), 0.01)


# --- Búsqueda de objetivo y movimiento -------------------------------------------------------------------

func _objetivo_actual() -> Node3D:
	var obj := objetivo if objetivo != null and is_instance_valid(objetivo) else Escenas.jugador()
	return obj if obj != null and is_instance_valid(obj) else null


func _dist_horizontal(obj: Node3D) -> float:
	var d := obj.global_position - global_position
	d.y = 0.0
	return d.length()


func _mirar(obj: Node3D, delta: float) -> void:
	mirar_direccion(obj.global_position - global_position, delta)


func mirar_direccion(direccion_nueva: Vector3, delta: float) -> void:
	var d := direccion_nueva.slide(Vector3.UP)
	if d.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), clampf(delta * 9.0, 0.0, 1.0))


func centro_impacto() -> Vector3:
	var altura := _alto_vuelo_actual if tipo == "volador" else 0.0
	return global_position + Vector3.UP * (altura + alto_modelo * 0.46)


func apuntable() -> bool:
	return activo and not muerto and not _invulnerable()


func linea_despejada(punto: Vector3) -> bool:
	var salida := centro_impacto()
	if salida.distance_squared_to(punto) < 0.01:
		return true
	var rayo := PhysicsRayQueryParameters3D.create(salida, punto, OBSTACULOS, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(rayo).is_empty()


func _reservar_ataque() -> bool:
	if is_in_group(GRUPO_ATAQUE):
		return true
	if get_tree().get_node_count_in_group(GRUPO_ATAQUE) >= ATACANTES_MAX:
		return false
	add_to_group(GRUPO_ATAQUE)
	return true


func _liberar_ataque() -> void:
	if is_in_group(GRUPO_ATAQUE):
		remove_from_group(GRUPO_ATAQUE)


func _physics_process(delta: float) -> void:
	if not activo or muerto:
		return
	_enfriamiento = maxf(_enfriamiento - delta, 0.0)
	_cd_especial = maxf(_cd_especial - delta, 0.0)
	_t_bob += delta
	_gravedad_y_vuelo(delta)
	if _pausa_animacion > 0.0:
		_pausa_animacion -= delta
		if _pausa_animacion <= 0.0 and anim != null:
			anim.play()
		return
	var obj := _objetivo_actual()
	if obj == null or (obj is Jugador and (Escenas.en_transicion or Juego.vida <= 0.0)):
		_liberar_ataque()
		if estado in [Estado.ATACAR, Estado.ESPECIAL]:
			_recuperar(0.4)
		return
	_instinto.percibir(self, obj, delta)
	var dist := _dist_horizontal(obj)
	match estado:
		Estado.GOLPEADO:
			_t_estado -= delta
			if _retroceso.length_squared() > 0.01:
				move_and_collide(_retroceso * delta)
				_retroceso = _retroceso.move_toward(Vector3.ZERO, delta * 16.0)
			if _t_estado <= 0.0:
				estado = Estado.LIBRE
			return
		Estado.ATACAR:
			if _t_impacto > 0.18:
				_mirar(obj, delta)
				_dir_ataque = global_basis.z
			_t_estado -= delta
			_t_impacto -= delta
			if not _golpe_hecho and _t_impacto <= 0.0:
				_golpe_hecho = true
				var d := (obj.global_position - global_position).slide(Vector3.UP).normalized()
				if d.is_zero_approx() or _dir_ataque.dot(d) > 0.65:
					atacar(obj)
			if _t_estado <= 0.0:
				_recuperar(0.35 if es_jefe else 0.45)
			return
		Estado.RECUPERANDO:
			_t_estado -= delta
			if _t_estado <= 0.0:
				estado = Estado.LIBRE
			return
		Estado.ESPECIAL:
			_proceso_especial(obj, delta, dist)
			return
		Estado.HUNDIDO, Estado.EMERGER, Estado.HUNDIENDO, Estado.BAJO_TIERRA:
			_proceso_gusano(obj, delta, dist)
			return
	if not _instinto.rastro.is_finite():
		_patrullar(delta)
		return
	if vida < vida_max * 0.22 and obj is Jugador:
		if not es_jefe:
			_huyendo = true
		elif not _retirada_jefe_hecha:
			if especial == "emerger":
				if _reservar_ataque():
					_retirada_jefe_hecha = true
					_iniciar_hundimiento()
					return
			else:
				_retirada_jefe_hecha = true
				_t_retirada_jefe = 0.85
	if _huyendo or _t_retirada_jefe > 0.0:
		_t_retirada_jefe = maxf(0.0, _t_retirada_jefe - delta)
		estado = Estado.HUIDA
		var alejamiento := (global_position - obj.global_position).slide(Vector3.UP).normalized()
		_instinto.paso(self, global_position + alejamiento * 4.0, delta, velocidad * 1.12)
		reproducir("volar" if tipo == "volador" else "andar")
		return
	var a_la_vista := _instinto.vio or (_instinto.oyó and linea_despejada(obj.global_position + Vector3.UP * 0.9))
	if a_la_vista and especial != "" and especial != "emerger" and _cd_especial <= 0.0 and _puede_especial(dist) and _reservar_ataque():
		_iniciar_especial(obj, dist)
		return
	if especial == "emerger" and _cd_especial <= 0.0 and dist <= alcance_deteccion and dist > alcance_ataque and _reservar_ataque():
		_iniciar_hundimiento()
		return
	if dist <= alcance_ataque and a_la_vista:
		velocity = Vector3.ZERO
		_mirar(obj, delta)
		if _enfriamiento <= 0.0 and _reservar_ataque():
			_iniciar_ataque()
		else:
			# Cede el centro a quien está atacando.
			if not es_jefe and get_tree().get_node_count_in_group(GRUPO_ATAQUE) >= ATACANTES_MAX:
				var al_lado := global_basis.x.rotated(Vector3.UP, 0.38)
				_instinto.paso(self, global_position + al_lado, delta, velocidad * 0.44)
				reproducir("volar" if tipo == "volador" else "andar")
			else:
				estado = Estado.LIBRE
				reproducir("reposo")
		return
	estado = Estado.PERSECUCION
	var factor := _factor_salto(delta) if tipo == "saltador" else 1.0
	_instinto.paso(self, _instinto.rastro, delta, velocidad * factor)
	reproducir("volar" if tipo == "volador" else ("andar" if velocity.length_squared() > 0.04 else "reposo"))


func _patrullar(delta: float) -> void:
	estado = Estado.PATRULLA
	if not _destino_patrulla.is_finite() or global_position.slide(Vector3.UP).distance_squared_to(_destino_patrulla.slide(Vector3.UP)) < 0.3:
		_descanso_patrulla -= delta
		if _descanso_patrulla > 0.0:
			velocity = Vector3.ZERO
			reproducir("reposo")
			return
		_descanso_patrulla = randf_range(1.0, 2.5)
		var angulo := randf_range(0.0, TAU)
		var destino := _instinto.origen + Vector3.FORWARD.rotated(Vector3.UP, angulo) * randf_range(1.0, 3.0)
		if linea_despejada(destino + Vector3.UP * 0.45):
			_destino_patrulla = destino
		else:
			return
	_instinto.paso(self, _destino_patrulla, delta, velocidad * 0.34)
	if velocity.length_squared() < 0.04:
		_destino_patrulla = Vector3.INF
	reproducir("volar" if tipo == "volador" else "andar")


## Gravedad (o altura de vuelo con un leve balanceo en los voladores).
func _gravedad_y_vuelo(delta: float) -> void:
	if tipo == "volador":
		if pivote != null:
			var meta := altura_vuelo * (0.55 if estado == Estado.ATACAR else 1.0)
			_alto_vuelo_actual = move_toward(_alto_vuelo_actual, meta, delta * 2.2)
			pivote.position.y = _alto_vuelo_actual + sin(_t_bob * 3.1) * 0.1
			_colision.position.y = pivote.position.y + (_colision.shape as CapsuleShape3D).height * 0.5
		return
	if not is_inside_tree():
		return
	_vy -= GRAVEDAD * delta
	var col := move_and_collide(Vector3(0.0, _vy * delta, 0.0))
	_en_suelo = false
	if col != null:
		if col.get_normal().y > 0.5 and _vy < 0.0:
			_en_suelo = true
		_vy = 0.0


## Sapos: avanzan a saltos (parado en el suelo, salta y avanza en el aire).
func _factor_salto(delta: float) -> float:
	if _en_suelo:
		_t_salto -= delta
		if _t_salto <= 0.0:
			_vy = 5.5
			_t_salto = 0.55
		return 0.0
	return 1.9


## Se desplaza hacia el objetivo horizontalmente; devuelve true si pudo avanzar o ya está a tiro.
func perseguir(obj: Node3D, delta: float, factor: float = 1.0) -> bool:
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
	var paso := minf(velocidad * factor * maxf(delta, 0.0), dist - alcance_ataque * 0.5)
	velocity = dir * velocidad * factor
	if is_inside_tree():
		_mirar(obj, delta)
		var col := move_and_collide(dir * paso)
		if col != null:
			# Desliza si roza un muro, una roca o un escalón.
			var resto := col.get_remainder().slide(col.get_normal())
			resto.y = 0.0
			move_and_collide(resto)
		return true
	global_position += dir * paso
	return true


# --- Ataques ----------------------------------------------------------------------------------------------

func _iniciar_ataque() -> void:
	estado = Estado.ATACAR
	velocity = Vector3.ZERO
	var dur := reproducir("atacar", 0.1)
	_t_estado = maxf(dur, 0.7)
	_t_impacto = maxf(0.42, dur * 0.4)
	_t_estado = maxf(_t_estado, _t_impacto + 0.16)
	_golpe_hecho = false
	_dir_ataque = global_basis.z
	_avisar_ataque()


## Realiza un golpe contra el objetivo si está en rango y no en enfriamiento.
func atacar(obj: Node3D) -> bool:
	if muerto or obj == null or not is_instance_valid(obj) or _enfriamiento > 0.0:
		return false
	var dif := obj.global_position - global_position
	dif.y = 0.0
	if dif.length() > alcance_ataque + 0.35:
		return false
	if obj is Jugador and (absf(obj.global_position.y - global_position.y) > 1.6 or not linea_despejada(obj.global_position + Vector3.UP * 0.9)):
		return false
	_enfriamiento = cadencia_ataque
	_dano_a(obj, dano)
	return true


func _dano_a(obj: Node3D, cantidad: float) -> void:
	if obj is Jugador:
		if not linea_despejada(obj.global_position + Vector3.UP * 0.9):
			return
		(obj as Jugador).recibir_ataque(cantidad, self, global_position, estado != Estado.EMERGER)
	elif obj.has_method("recibir_dano"):
		obj.call("recibir_dano", cantidad)
	atacado.emit(cantidad)


func _puede_especial(dist: float) -> bool:
	match especial:
		"embestida":
			return dist >= 3.0 and dist <= 10.0
		"lengua":
			return dist > alcance_ataque and dist <= 5.2
		"cristales":
			return dist >= 3.5 and dist <= alcance_deteccion
	return false


func _iniciar_especial(obj: Node3D, _dist: float) -> void:
	estado = Estado.ESPECIAL
	_t_especial = 0.0
	_golpe_hecho = false
	var d := obj.global_position - global_position
	d.y = 0.0
	_dir_embestida = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	reproducir("ataque_especial", 0.1, 0.75)
	_avisar_ataque()
	match especial:
		"embestida":
			_cd_especial = 6.0
		"lengua":
			_cd_especial = 5.0
		"cristales":
			_cd_especial = 4.5


func _proceso_especial(obj: Node3D, delta: float, dist: float) -> void:
	_t_especial += delta
	match especial:
		"embestida":
			# Carga hacia donde estaba Leo: 0,5 s de preparación y 0,8 s de carrera.
			if _t_especial < 0.5:
				_mirar(obj, delta)
				var d := obj.global_position - global_position
				d.y = 0.0
				if d.length() > 0.01:
					_dir_embestida = d.normalized()
			elif _t_especial < 1.3:
				reproducir("andar", 0.05)
				var col := move_and_collide(_dir_embestida * velocidad * 3.2 * delta)
				if col != null:
					_t_especial = 1.3
				if not _golpe_hecho and dist <= alcance_ataque + 0.4:
					_golpe_hecho = true
					_dano_a(obj, dano * 1.4)
			else:
				_fin_especial(0.8)
		"lengua":
			_mirar(obj, delta)
			if not _golpe_hecho and _t_especial >= 0.55:
				_golpe_hecho = true
				var boca := global_position + Vector3(0.0, alto_modelo * 0.4, 0.0) + global_transform.basis.z * radio_cuerpo
				var meta := obj.global_position + Vector3(0.0, 0.9, 0.0)
				_trazo_lengua(boca, meta)
				if dist <= 5.8:
					_dano_a(obj, dano * 1.2)
			if _t_especial >= 1.2:
				_fin_especial(0.6)
		"cristales":
			_mirar(obj, delta)
			if not _golpe_hecho and _t_especial >= 0.5:
				_golpe_hecho = true
				_lanzar_cristales(obj)
			if _t_especial >= 1.3:
				_fin_especial(0.5)
		_:
			_fin_especial(0.5)


func _fin_especial(pausa: float) -> void:
	_recuperar(pausa)


func _recuperar(pausa: float) -> void:
	_liberar_ataque()
	estado = Estado.RECUPERANDO
	_t_estado = pausa
	_enfriamiento = maxf(_enfriamiento, pausa)
	reproducir("reposo", 0.18)


func _avisar_ataque() -> void:
	Audio.reproducir_posicional("combate_aviso_" + material_impacto, centro_impacto(), get_parent(), -8.0)


func _trazo_lengua(origen: Vector3, meta: Vector3) -> void:
	var padre := get_parent()
	if padre == null or origen.distance_to(meta) < 0.2:
		return
	var n := Node3D.new()
	padre.add_child(n)
	n.global_position = origen
	n.look_at(meta, Vector3.UP)
	var largo := origen.distance_to(meta)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.09
	cm.height = largo
	mi.mesh = cm
	mi.rotation_degrees.x = 90.0
	mi.position.z = -largo * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.36, 0.40)
	mat.roughness = 0.35
	mi.material_override = mat
	n.add_child(mi)
	get_tree().create_timer(0.3).timeout.connect(n.queue_free)


func _lanzar_cristales(obj: Node3D) -> void:
	var padre := get_parent()
	if padre == null:
		return
	var origen := global_position + Vector3(0.0, alto_modelo * 0.7, 0.0)
	var meta := obj.global_position + Vector3(0.0, 0.9, 0.0)
	var base := (meta - origen).normalized()
	for ang: float in [-0.28, 0.0, 0.28]:
		var p := ProyectilCristal.new()
		p.dano = dano * 0.7
		p.dir = base.rotated(Vector3.UP, ang)
		padre.add_child(p)
		p.global_position = origen
		p.look_at(origen + p.dir, Vector3.UP)


## Cristal lanzado por la araña madre.
class ProyectilCristal extends Node3D:
	var dir: Vector3 = Vector3.FORWARD
	var velocidad: float = 9.5
	var dano: float = 10.0
	var vida_t: float = 2.4

	func _init() -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.13
		cm.height = 0.55
		mi.mesh = cm
		mi.rotation_degrees.x = -90.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.75, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.65, 1.0)
		mat.emission_energy_multiplier = 2.6
		mi.material_override = mat
		add_child(mi)
		var luz := OmniLight3D.new()
		luz.light_color = Color(0.4, 0.65, 1.0)
		luz.light_energy = 0.8
		luz.omni_range = 3.0
		add_child(luz)

	func _physics_process(delta: float) -> void:
		var siguiente := global_position + dir * velocidad * delta
		var impacto := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(global_position, siguiente, OBSTACULOS))
		if not impacto.is_empty():
			queue_free()
			return
		vida_t -= delta
		if vida_t <= 0.0:
			queue_free()
			return
		var j := Escenas.jugador() as Jugador
		if j != null and (j.global_position + Vector3(0.0, 0.9, 0.0)).distance_to(siguiente) < 0.56:
			j.recibir_ataque(dano, null, global_position - dir, false)
			queue_free()
			return
		global_position = siguiente


# --- Gusano de magma: emerge, se hunde y vuelve a salir bajo Leo -------------------------------------------

func _hundimiento() -> float:
	return alto_modelo + 0.5


func _hundir_del_todo() -> void:
	estado = Estado.HUNDIDO
	if pivote != null:
		pivote.position.y = -_hundimiento()


func _iniciar_hundimiento() -> void:
	estado = Estado.HUNDIENDO
	_t_estado = 0.9


func _iniciar_emerger(area: bool) -> void:
	estado = Estado.EMERGER
	_t_estado = 1.4
	_golpe_hecho = not area
	_cd_especial = 9.0
	reproducir("emerger", 0.1)   # los .glb no la traen: sube por código
	_avisar_ataque()


func _proceso_gusano(obj: Node3D, delta: float, dist: float) -> void:
	var h := _hundimiento()
	match estado:
		Estado.HUNDIDO:
			if dist <= alcance_deteccion and _instinto.rastro.is_finite() and _reservar_ataque():
				_iniciar_emerger(true)
		Estado.EMERGER:
			_t_estado -= delta
			reproducir("reposo")
			var u := clampf(1.0 - _t_estado / 1.4, 0.0, 1.0)
			pivote.position.y = lerpf(-h, 0.0, u * u * (3.0 - 2.0 * u))
			_mirar(obj, delta)
			if not _golpe_hecho and u >= 0.45:
				_golpe_hecho = true
				if dist <= alcance_ataque + 0.6:
					_dano_a(obj, dano * 1.2)
			if _t_estado <= 0.0:
				pivote.position.y = 0.0
				_recuperar(0.6)
		Estado.HUNDIENDO:
			_t_estado -= delta
			reproducir("reposo")
			pivote.position.y = lerpf(0.0, -h, clampf(1.0 - _t_estado / 0.9, 0.0, 1.0))
			if _t_estado <= 0.0:
				estado = Estado.BAJO_TIERRA
				_t_estado = 2.0
		Estado.BAJO_TIERRA:
			_t_estado -= delta
			pivote.position.y = -h
			var d := obj.global_position - global_position
			d.y = 0.0
			if d.length() > 1.2 and _t_estado > 0.0:
				var col := move_and_collide(d.normalized() * velocidad * 2.2 * delta)
				if col != null:
					_t_estado = 0.0
			else:
				_t_estado = 0.0
			if _t_estado <= 0.0:
				_iniciar_emerger(true)


# --- Daño recibido y muerte --------------------------------------------------------------------------------

func _invulnerable() -> bool:
	return estado in [Estado.HUNDIDO, Estado.EMERGER, Estado.HUNDIENDO, Estado.BAJO_TIERRA]


## Golpe de Leo con el pico o el hacha (grupo «usable»): daño según el nivel de la herramienta.
func usar(id_objeto: String, punto: Vector3, _jugador: Node3D) -> bool:
	if muerto or _invulnerable() or not (id_objeto in ["pico", "hacha"]):
		return false
	var d := punto - global_position
	var dy := absf(punto.y - (global_position.y + (altura_vuelo if tipo == "volador" else 0.0)))
	d.y = 0.0
	if d.length() > radio_impacto + 1.0 or dy > 2.4:
		return false
	var cantidad := DANO_PICO_BASE + DANO_PICO_POR_NIVEL * float(Juego.nivel(id_objeto))
	if id_objeto == "hacha":
		cantidad *= 0.85
	Audio.reproducir("pico")
	recibir_dano(cantidad)
	return true


func recibir_dano(cantidad: float) -> void:
	if muerto or cantidad <= 0.0 or _invulnerable():
		return
	vida = maxf(vida - cantidad, 0.0)
	vida_cambiada.emit(vida, vida_max)
	if vida <= 0.001:
		morir()
		return
	if estado != Estado.ESPECIAL:
		desequilibrar(0.24 if es_jefe else 0.38)


func recibir_golpe(cantidad: float, direccion_golpe: Vector3, rompe_guardia: bool, aturde: float,
		punto_impacto: Vector3 = Vector3.INF) -> bool:
	if not apuntable() or cantidad <= 0.0:
		return false
	var centro := centro_impacto() if punto_impacto == Vector3.INF else punto_impacto
	_instinto.recordar(global_position - direccion_golpe * 1.4)
	var frente := global_basis.z.dot(-direccion_golpe) > 0.10
	var guardia := protege_cuerpo and frente and estado in [Estado.PATRULLA, Estado.LIBRE, Estado.PERSECUCION]
	if guardia and not rompe_guardia:
		cantidad *= 0.57
	recibir_dano(cantidad)
	EFECTOS.impacto(get_parent(), centro, direccion_golpe, material_impacto, guardia and not rompe_guardia)
	if muerto:
		return true
	if aturde > 0.0 or (guardia and rompe_guardia):
		desequilibrar(aturde + (0.38 if guardia and rompe_guardia else 0.0))
	_retroceso = direccion_golpe * (0.75 if es_jefe else (1.4 if guardia else 3.0))
	if anim != null:
		_pausa_animacion = 0.067 if aturde >= 0.29 else 0.058
		anim.pause()
	return true


func desequilibrar(segundos: float) -> void:
	if not apuntable():
		return
	_liberar_ataque()
	var previo := _t_estado if estado == Estado.GOLPEADO else 0.0
	estado = Estado.GOLPEADO
	_t_estado = maxf(previo, segundos)
	velocity = Vector3.ZERO
	reproducir("golpeado", 0.05)


func morir() -> void:
	if muerto:
		return
	muerto = true
	activo = false
	estado = Estado.LIBRE
	_aplicar_estado_activo()
	remove_from_group("usable")
	if luz_brillo != null:
		luz_brillo.visible = false
	fallecido.emit(self)
	if not is_inside_tree():
		return
	if not mineral_botin.is_empty() and Datos.existe_objeto(mineral_botin):
		var botin := BOTIN.new()
		botin.configurar(mineral_botin, unidades_botin)
		botin.position = position
		var piso := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.18, global_position + Vector3.DOWN * 4.0, CAPA_MUROS | CAPA_ROCAS))
		if not piso.is_empty():
			botin.position = get_parent().to_local(piso.position + Vector3.UP * 0.04)
		get_parent().add_child(botin)
	if pivote != null and tipo == "volador":
		pivote.position.y = 0.0   # el volador cae al suelo
	var dur := reproducir("morir", 0.1)
	if dur > 0.0:
		_t_muerte = dur + 1.0   # se queda un momento ahí tendido y luego desaparece
		set_process(true)
	else:
		queue_free()


func _process(delta: float) -> void:
	if muerto:
		_t_muerte -= delta
		if _t_muerte <= 0.0:
			queue_free()
