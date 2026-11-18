class_name Flecha
extends Node3D
## Proyectil físico parabólico con rozamiento del aire, impacto en enemigos/superficies, clavado o rebote y recuperación.

const GRAVEDAD := 9.8
const MASCARA_IMPACTO := 1 | 8 | 16 | 32 | 64 | 128
const ESCENA_FLECHA := "res://assets/combate/flecha_proyectil.glb"

var id_municion: String = "flecha_normal"
var velocidad: Vector3 = Vector3.ZERO
var dano_base: float = 26.0
var factor_caida: float = 1.0
var rozamiento: float = 0.08
var rompe_guardia: bool = false
var aturde: float = 0.14
var critico_extra: float = 0.0
var es_fuego: bool = false
var robo_vida: float = 0.0
var prob_recupera: float = 0.7
var origen_disparo: Vector3 = Vector3.ZERO
var excluir_rids: Array[RID] = []

var clavada: bool = false
var rebotada: bool = false
var critico_impacto: bool = false
var recupero_activo: bool = false

var _tiempo_vuelo: float = 0.0
var _tiempo_vida: float = 45.0
var _luz_fuego: OmniLight3D = null
var _malla: Node3D = null


## Ecuación de paso balístico idéntica al vuelo real para verificar trayectorias frente a la curva teórica.
static func paso_balistico(pos: Vector3, vel: Vector3, dt: float, caida: float = 1.0, drag: float = 0.08) -> Dictionary:
	var v_n := vel * exp(-drag * dt)
	v_n.y -= GRAVEDAD * caida * dt
	var p_n := pos + v_n * dt
	return {"pos": p_n, "vel": v_n}


func configurar(p_pos: Vector3, p_vel: Vector3, p_id_flecha: String, p_dano_arco: float, p_rids: Array[RID]) -> void:
	id_municion = p_id_flecha
	if is_inside_tree():
		global_position = p_pos
	else:
		position = p_pos
	origen_disparo = p_pos
	velocidad = p_vel
	excluir_rids = p_rids.duplicate()

	var fm := Datos.objeto(id_municion)
	dano_base = p_dano_arco + float(fm.get("bono_dano", 0.0))
	factor_caida = float(fm.get("caida", 1.0))
	rozamiento = 0.04 if id_municion == "flecha_cristal" else 0.08
	rompe_guardia = bool(fm.get("rompe_guardia", false))
	critico_extra = float(fm.get("critico_extra", 0.0))
	es_fuego = bool(fm.get("fuego", false))
	prob_recupera = float(fm.get("recupera", 0.7))
	var carcaj_id := str(Juego.equipo.get("carcaj", ""))
	if not carcaj_id.is_empty():
		prob_recupera = minf(0.95, prob_recupera + float(Datos.objeto(carcaj_id).get("recuperacion", 0.0)))

	_construir_visual()
	if velocidad.length_squared() > 0.01:
		if is_inside_tree():
			look_at(global_position + velocidad.normalized(), Vector3.UP)
		else:
			look_at_from_position(p_pos, p_pos + velocidad.normalized(), Vector3.UP)


func _construir_visual() -> void:
	if ResourceLoader.exists(ESCENA_FLECHA):
		var esc := load(ESCENA_FLECHA) as PackedScene
		if esc != null:
			_malla = esc.instantiate() as Node3D
			if _malla != null:
				# Modelo apunta hacia +Z local, rotar para mirar hacia -Z (look_at)
				_malla.rotation_degrees.y = 180.0
				_malla.scale = Vector3.ONE * 1.15
				add_child(_malla)
	if es_fuego:
		_luz_fuego = OmniLight3D.new()
		_luz_fuego.light_color = Color(1.0, 0.45, 0.12)
		_luz_fuego.light_energy = 1.65
		_luz_fuego.omni_range = 5.5
		_luz_fuego.shadow_enabled = false
		add_child(_luz_fuego)


func _physics_process(delta: float) -> void:
	_tiempo_vida -= delta
	if _tiempo_vida <= 0.0:
		queue_free()
		return
	if clavada:
		return
	_tiempo_vuelo += delta
	var res := paso_balistico(global_position, velocidad, delta, factor_caida, rozamiento)
	var destino: Vector3 = res["pos"]
	var v_siguiente: Vector3 = res["vel"]

	var espacio := get_world_3d().direct_space_state if get_world_3d() != null else null
	if espacio != null:
		var q := PhysicsRayQueryParameters3D.create(global_position, destino, MASCARA_IMPACTO, excluir_rids)
		q.collide_with_areas = false
		var impacto := espacio.intersect_ray(q)
		if not impacto.is_empty():
			_procesar_impacto(impacto, v_siguiente)
			return

	global_position = destino
	velocidad = v_siguiente
	if velocidad.length_squared() > 0.05:
		var dir_n := velocidad.normalized()
		if absf(dir_n.dot(Vector3.UP)) < 0.99:
			look_at(global_position + dir_n, Vector3.UP)


func _procesar_impacto(impacto: Dictionary, v_actual: Vector3) -> void:
	var hit_pos: Vector3 = impacto.get("position", global_position)
	var normal: Vector3 = impacto.get("normal", Vector3.UP)
	var col: Node = impacto.get("collider") as Node
	global_position = hit_pos
	if v_actual.length_squared() > 0.01:
		var dir := v_actual.normalized()
		if absf(dir.dot(Vector3.UP)) < 0.99:
			look_at(global_position + dir, Vector3.UP)

	var enemigo := col as Enemigo
	if enemigo == null and col != null and col.get_parent() is Enemigo:
		enemigo = col.get_parent() as Enemigo

	if enemigo != null and enemigo.apuntable():
		var rel_y := hit_pos.y - enemigo.global_position.y
		var es_crit := rel_y >= enemigo.alto_modelo * (0.56 if enemigo.es_jefe else 0.68)
		critico_impacto = es_crit
		var mult := (1.55 + critico_extra) if es_crit else 1.0
		var empuje := v_actual.slide(Vector3.UP).normalized()
		var hit_ok := enemigo.recibir_golpe(dano_base * mult, empuje, rompe_guardia or es_crit, aturde, hit_pos)
		if hit_ok:
			Juego.ganar_xp_habilidad("combate", 8 if es_crit else 5)
			if enemigo.tipo == "volador":
				enemigo.desequilibrar(0.65)
			if enemigo.has_method("reaccionar_flechazo"):
				enemigo.call("reaccionar_flechazo", origen_disparo)
			if es_fuego:
				aplicar_quemadura(self, enemigo, 4.0)
			if robo_vida > 0.0:
				Juego.curar_vida(robo_vida)
			Audio.reproducir_posicional("flecha_clavada", hit_pos, self)
			_clavar_en(enemigo, hit_pos)
		else:
			# Enemigo bloqueó con guardia rígida: rebote
			_rebotar(hit_pos, normal, v_actual)
		return

	# Impacto en superficie del mundo: distinguir roca/metal (rebote) vs madera/tierra/hierba (clavada)
	if _es_superficie_dura(col):
		_rebotar(hit_pos, normal, v_actual)
	else:
		Audio.reproducir_posicional("flecha_clavada", hit_pos, self)
		if es_fuego:
			_fuego_en_hierba_seca(hit_pos)
		_clavar_en(col if col is Node3D and is_instance_valid(col) else get_parent(), hit_pos)


func _es_superficie_dura(col: Node) -> bool:
	if col == null:
		return false
	var nom := str(col.name).to_lower()
	if nom.contains("mina") or nom.contains("roca") or nom.contains("veta") or nom.contains("escudo") or nom.contains("piedra") or nom.contains("muro"):
		return true
	var mapa_n := get_tree().get_first_node_in_group("mapa")
	if mapa_n != null and str(mapa_n.get("id_mapa")) == "mina_interior":
		return true
	return false


func _clavar_en(objetivo: Node, hit_pos: Vector3) -> void:
	clavada = true
	velocidad = Vector3.ZERO
	if objetivo is Node3D and is_instance_valid(objetivo) and objetivo != get_parent():
		var xform_mundo := global_transform
		get_parent().remove_child(self)
		(objetivo as Node3D).add_child(self)
		global_transform = xform_mundo
	global_position = hit_pos
	_habilitar_recogida()


func _rebotar(hit_pos: Vector3, normal: Vector3, v_actual: Vector3) -> void:
	rebotada = true
	Audio.reproducir_posicional("flecha_rebote", hit_pos, self)
	if v_actual.length() > 8.0:
		# Un solo rebote físico visible antes de caer al suelo
		velocidad = v_actual.bounce(normal.normalized()) * 0.36
		global_position = hit_pos + normal.normalized() * 0.08
		if _tiempo_vuelo < 1.5 and not clavada:
			excluir_rids.clear()
			return
	clavada = true
	velocidad = Vector3.ZERO
	_habilitar_recogida()


func _habilitar_recogida() -> void:
	var roll_rec := prob_recupera * (0.45 if rebotada else 1.0)
	if randf() > roll_rec:
		return
	recupero_activo = true
	var pto := Interactuable.new()
	pto.verbo = "Recoger"
	pto.nombre_objeto = Datos.nombre_objeto(id_municion).to_lower()
	pto.radio = 1.7
	pto.altura_marca = 0.55
	add_child(pto)
	pto.usado.connect(func(_j: Node3D) -> void:
		if Juego.anadir_objeto(id_municion, 1) == 0:
			Interfaz.mensaje("Recoges 1 %s." % Datos.nombre_objeto(id_municion).to_lower())
		queue_free())


static func aplicar_quemadura(dueno: Node, enemigo: Enemigo, dano_tick: float = 4.0) -> void:
	if dueno == null or not is_instance_valid(enemigo):
		return
	var t := Timer.new()
	t.wait_time = 0.85
	t.one_shot = false
	var ticks := {"n": 4}
	dueno.add_child(t)
	t.timeout.connect(func() -> void:
		if ticks["n"] <= 0 or not is_instance_valid(enemigo) or enemigo.muerto:
			t.queue_free()
			return
		ticks["n"] -= 1
		enemigo.recibir_golpe(dano_tick, Vector3.ZERO, false, 0.0, enemigo.global_position))
	t.start()


func _fuego_en_hierba_seca(pos: Vector3) -> void:
	var mapa_n := get_tree().get_first_node_in_group("mapa")
	if mapa_n == null or bool(mapa_n.get("interior")) or Juego.esta_lloviendo() or Juego.esta_nevando():
		return
	var hoguera := Node3D.new()
	hoguera.name = "LlamaHierbaFlecha"
	mapa_n.add_child(hoguera)
	hoguera.global_position = pos + Vector3(0, 0.06, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.42, 0.12)
	l.light_energy = 1.8
	l.omni_range = 4.2
	l.shadow_enabled = false
	hoguera.add_child(l)
	var mesh_ll := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.24
	sph.height = 0.36
	mesh_ll.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.10, 0.85)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.42, 0.10)
	m.emission_energy_multiplier = 2.8
	mesh_ll.material_override = m
	hoguera.add_child(mesh_ll)
	var tw := hoguera.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.parallel().tween_property(mesh_ll, "scale", Vector3.ONE * 0.05, 0.5)
	tw.chain().tween_callback(hoguera.queue_free)
