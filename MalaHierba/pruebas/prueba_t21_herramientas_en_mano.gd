extends Node
## Prueba de T21-herramientas-en-mano:
## - Verifica modelos 3D texturizados de pico, hacha, azada, regadera, hoz, caña y semillas en assets/herramientas/.
## - Verifica en leo.glb las animaciones por herramienta, relajada al andar, y ausencia del gesto de levantar ambas manos.
## - Verifica en Jugador real el BoneAttachment3D en mano derecha, cambio por ranura y animación de uso por herramienta.

const HERRAMIENTAS_MOD := ["pico", "hacha", "azada", "regadera", "hoz", "cana", "semillas", "frasco", "mineral", "madera_mano", "cesta_mano"]
const ANIMS_T21 := ["usar_pico", "usar_hacha", "usar_azada", "usar_regadera", "usar_hoz", "usar_semilla", "usar_cana", "reposo_herramienta", "andar_herramienta"]

var _fallos: Array[String] = []
var _comprobaciones: int = 0
var _tope: Timer = null


func _ready() -> void:
	_tope = Timer.new()
	_tope.wait_time = 60.0
	_tope.one_shot = true
	_tope.autostart = true
	_tope.process_mode = Node.PROCESS_MODE_ALWAYS
	_tope.timeout.connect(Callable(get_tree(), "quit").bind(1))
	get_tree().root.call_deferred("add_child", _tope)
	_ejecutar.call_deferred()


func _comprobar(cond: bool, desc: String) -> void:
	_comprobaciones += 1
	if not cond:
		_fallos.append(desc)
		print("  FALLO: ", desc)
	else:
		print("  OK: ", desc)


func _fisica(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _buscar(raiz: Node, clase: String) -> Node:
	var res := raiz.find_children("*", clase, true, false)
	return res[0] if not res.is_empty() else null


func _comprobar_modelos_herramientas() -> void:
	for nom in HERRAMIENTAS_MOD:
		var ruta := "res://assets/herramientas/%s.glb" % nom
		var existe := ResourceLoader.exists(ruta)
		_comprobar(existe, "existe modelo 3D '%s'" % ruta)
		if not existe:
			continue
		var ps := load(ruta) as PackedScene
		_comprobar(ps != null, "carga PackedScene '%s'" % nom)
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		add_child(inst)
		var mallas := inst.find_children("*", "MeshInstance3D", true, false)
		_comprobar(not mallas.is_empty(), "'%s' contiene MeshInstance3D" % nom)
		var tris := 0
		var con_tex := 0
		for n in mallas:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in range(mi.mesh.get_surface_count()):
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3
				var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if mat != null and mat.albedo_texture != null:
					con_tex += 1
		_comprobar(tris >= 20, "'%s' tiene geometría detallada (%d tris)" % [nom, tris])
		_comprobar(con_tex >= 1, "'%s' tiene material con albedo_texture" % nom)
		inst.queue_free()


func _comprobar_esqueleto_y_anims() -> void:
	var ps := load(Jugador.RUTA_MODELO) as PackedScene
	var nodo := ps.instantiate() as Node3D
	add_child(nodo)
	var sk := _buscar(nodo, "Skeleton3D") as Skeleton3D
	var ap := _buscar(nodo, "AnimationPlayer") as AnimationPlayer
	_comprobar(sk != null and sk.get_bone_count() == 35, "Leo conserva 35 huesos")
	_comprobar(ap != null, "Leo tiene AnimationPlayer")
	if sk == null or ap == null:
		nodo.queue_free()
		return

	for anim_nom in ANIMS_T21:
		_comprobar(ap.has_animation(anim_nom), "leo.glb incluye animación '%s'" % anim_nom)
		if ap.has_animation(anim_nom):
			var a := ap.get_animation(anim_nom)
			_comprobar(a.length > 0.35 and a.get_track_count() >= 20,
				"'%s' válida (%.2fs, %d pistas)" % [anim_nom, a.length, a.get_track_count()])

	var b_hr := sk.find_bone("DEF-hand.R")
	var b_hl := sk.find_bone("DEF-hand.L")

	# Sin gesto viejo de ambas manos alzadas sobre la cabeza en 'herramienta'
	var ambos_arriba := false
	var lh_h := ap.get_animation("herramienta").length
	for f in 10:
		ap.play("herramienta")
		ap.seek(lh_h * float(f) / 9.0, true)
		var pr := sk.get_bone_global_pose(b_hr).origin
		var pl := sk.get_bone_global_pose(b_hl).origin
		if pr.y > 1.55 and pl.y > 1.55:
			ambos_arriba = true
	_comprobar(not ambos_arriba, "eliminado el gesto de levantar las dos manos sobre la cabeza en 'herramienta'")

	# Pico y hacha: golpe vertical amplio y mano izquierda acompaña
	for nom_g in ["usar_pico", "usar_hacha", "usar_azada"]:
		var min_y := 99.0
		var max_y := -99.0
		var max_hl := -99.0
		var len_g := ap.get_animation(nom_g).length
		for f in 15:
			ap.play(nom_g)
			ap.seek(len_g * float(f) / 14.0, true)
			var py := sk.get_bone_global_pose(b_hr).origin.y
			var ply := sk.get_bone_global_pose(b_hl).origin.y
			min_y = minf(min_y, py)
			max_y = maxf(max_y, py)
			max_hl = maxf(max_hl, ply)
		_comprobar(max_y - min_y > 0.35, "'%s' describe golpe amplio vertical (rango %.2fm)" % [nom_g, max_y - min_y])
		if nom_g in ["usar_pico", "usar_hacha"]:
			_comprobar(max_hl > 1.25, "'%s' usa las dos manos en el mango (hand.L maxY=%.2f)" % [nom_g, max_hl])

	# Regadera: mano izquierda baja y derecha inclina muñeca al frente
	ap.play("usar_regadera")
	ap.seek(0.0, true)
	var rot0 := sk.get_bone_global_pose(b_hr).basis.get_rotation_quaternion()
	ap.seek(ap.get_animation("usar_regadera").length * 0.55, true)
	var rot1 := sk.get_bone_global_pose(b_hr).basis.get_rotation_quaternion()
	var hl_reg := sk.get_bone_global_pose(b_hl).origin.y
	_comprobar(rad_to_deg(rot0.angle_to(rot1)) > 25.0,
		"usar_regadera inclina la mano/regadera (%.1f°)" % rad_to_deg(rot0.angle_to(rot1)))
	_comprobar(hl_reg < 1.05, "usar_regadera mantiene la mano izquierda relajada (%.2fm)" % hl_reg)

	# Hoz: barrido lateral en X
	var min_x := 99.0
	var max_x := -99.0
	var len_hoz := ap.get_animation("usar_hoz").length
	for f in 14:
		ap.play("usar_hoz")
		ap.seek(len_hoz * float(f) / 13.0, true)
		var px := sk.get_bone_global_pose(b_hr).origin.x
		min_x = minf(min_x, px)
		max_x = maxf(max_x, px)
	_comprobar(max_x - min_x > 0.45, "usar_hoz ejecuta barrido lateral amplio (%.2fm)" % (max_x - min_x))

	# Semillas: una sola mano
	var mov_r := 0.0
	var mov_l := 0.0
	ap.play("usar_semilla")
	ap.seek(0.0, true)
	var r0 := sk.get_bone_global_pose(b_hr).origin
	var l0 := sk.get_bone_global_pose(b_hl).origin
	for f in 12:
		ap.seek(ap.get_animation("usar_semilla").length * float(f) / 11.0, true)
		mov_r = maxf(mov_r, r0.distance_to(sk.get_bone_global_pose(b_hr).origin))
		mov_l = maxf(mov_l, l0.distance_to(sk.get_bone_global_pose(b_hl).origin))
	_comprobar(mov_r > 0.30 and mov_l < 0.12,
		"usar_semilla lanza con una mano (R=%.2fm, L=%.2fm)" % [mov_r, mov_l])

	nodo.queue_free()


func _comprobar_jugador() -> void:
	Juego.ruta_partida = "user://partida_prueba_t21.json"
	Juego.nueva_partida("Leo")

	var arena := Node3D.new()
	add_child(arena)
	var suelo := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(30, 1, 30)
	col.shape = caja
	col.position = Vector3(0, -0.5, 0)
	suelo.add_child(col)
	arena.add_child(suelo)

	var j := (load("res://escenas/jugador/jugador.tscn") as PackedScene).instantiate() as Jugador
	arena.add_child(j)
	j.colocar(Vector3.ZERO, 0.0, 0.0)
	j.activar()
	await _fisica(10)

	var adj := _buscar(j, "BoneAttachment3D") as BoneAttachment3D
	_comprobar(adj != null and not adj.bone_name.is_empty(),
		"Jugador monta BoneAttachment3D en mano derecha (%s)" % (adj.bone_name if adj else "null"))

	# Ranura 0..5 -> azada, regadera, hoz, hacha, pico, semilla_patata; ranura 7 -> vacío
	var esperadas := {
		0: "usar_azada",
		1: "usar_regadera",
		2: "usar_hoz",
		3: "usar_hacha",
		4: "usar_pico",
		5: "usar_semilla",
	}
	for r: int in esperadas.keys():
		Juego.elegir_ranura(r)
		await _fisica(3)
		_comprobar(j._herramienta_nodo != null and j._herramienta_nodo.get_parent() == j._mano_soporte,
			"ranura %d muestra modelo 3D en mano derecha" % r)
		_comprobar(j._anim_actual == "reposo_herramienta",
			"ranura %d en reposo usa pose relajada 'reposo_herramienta' (%s)" % [r, j._anim_actual])
		j._t_herramienta = 0.0
		j.animar_herramienta()
		_comprobar(j._anim_actual == esperadas[r],
			"ranura %d usa animación '%s' (actual='%s')" % [r, esperadas[r], j._anim_actual])
		j._t_herramienta = 0.0
		await _fisica(3)

	# Andar con herramienta
	Juego.elegir_ranura(4) # pico
	await _fisica(2)
	Input.action_press("mover_arriba")
	await _fisica(18)
	_comprobar(j._anim_actual == "andar_herramienta",
		"andar con herramienta usa 'andar_herramienta' (%s)" % j._anim_actual)
	Input.action_release("mover_arriba")
	await _fisica(10)

	# Hueco vacío retira modelo de la mano y vuelve a reposo normal (slot 7 trae la antorcha desde H07)
	Juego.elegir_ranura(8)
	await _fisica(4)
	_comprobar(j._herramienta_nodo == null and j._objeto_en_mano.is_empty(),
		"ranura vacía oculta el modelo de la mano")

	arena.queue_free()


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	_comprobar_modelos_herramientas()
	_comprobar_esqueleto_y_anims()
	await _comprobar_jugador()
	await _fisica(2)
	if is_instance_valid(_tope):
		_tope.queue_free()
		await get_tree().process_frame
	if _fallos.is_empty():
		print("PRUEBA T21_HERRAMIENTAS_EN_MANO OK (%d comprobaciones)" % _comprobaciones)
		get_tree().quit(0)
	else:
		print("PRUEBA T21_HERRAMIENTAS_EN_MANO FALLO (%d de %d)" % [_fallos.size(), _comprobaciones])
		get_tree().quit(1)
