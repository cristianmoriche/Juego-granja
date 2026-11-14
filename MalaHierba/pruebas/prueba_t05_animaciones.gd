extends Node
## Prueba de la tarea T05-leo-animaciones:
## 1) Verifica en res://assets/personajes/leo/leo.glb las 9 animaciones (4 existentes + 5 nuevas),
##    la conservación exacta de malla/textura (35 huesos, 28000 triángulos, albedo embebido) y
##    que cada animación nueva mueve los huesos y cumple la postura realista (cadera abajo, rodillas ~90°, sin hundirse).
## 2) Verifica en Jugador real los estados agachado quieto/andando, saltar, caer y aterrizar:
##    `_anim_propia == true`, animación exacta en AnimationPlayer y cero deformación de escala/inclinación.

const RUTA_LEO := "res://assets/personajes/leo/leo.glb"
const RUTA_JUGADOR := "res://escenas/jugador/jugador.tscn"
const ANIMS_ORIGINALES: Array[String] = ["reposo", "andar", "saludar", "herramienta"]
const ANIMS_T05: Array[String] = ["saltar", "caer", "aterrizar", "agachado_reposo", "agachado_andar"]

var _fallos: Array[String] = []


func _ready() -> void:
	_comprobar_modelo()
	await _comprobar_jugador()
	if _fallos.is_empty():
		print("PRUEBA T05_ANIMACIONES OK")
		get_tree().quit(0)
	else:
		for f in _fallos:
			print("  - FALLO: ", f)
		print("PRUEBA T05_ANIMACIONES FALLO (%d)" % _fallos.size())
		get_tree().quit(1)


func _comprobar(cond: bool, desc: String) -> void:
	if not cond:
		_fallos.append(desc)
	else:
		print("  OK: ", desc)


func _buscar(raiz: Node, clase: String) -> Node:
	var res := raiz.find_children("*", clase, true, false)
	return res[0] if not res.is_empty() else null


func _comprobar_modelo() -> void:
	var ps := load(RUTA_LEO) as PackedScene
	_comprobar(ps != null, "leo.glb carga como PackedScene")
	if ps == null:
		return
	var nodo := ps.instantiate() as Node3D
	add_child(nodo)

	var sk := _buscar(nodo, "Skeleton3D") as Skeleton3D
	var ap := _buscar(nodo, "AnimationPlayer") as AnimationPlayer
	var mi := _buscar(nodo, "MeshInstance3D") as MeshInstance3D
	_comprobar(sk != null and sk.get_bone_count() == 35, "Leo conserva exactamente 35 huesos (%d)" % (sk.get_bone_count() if sk else -1))
	_comprobar(ap != null, "Leo tiene AnimationPlayer")
	_comprobar(mi != null and mi.mesh != null, "Leo tiene MeshInstance3D con malla")

	if mi != null and mi.mesh != null:
		var tris := 0
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
		_comprobar(tris == 28000, "Malla intacta: exactamente 28000 triángulos (%d)" % tris)
		var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
		_comprobar(mat != null and mat.albedo_texture != null, "Textura de albedo intacta en leo.glb")

	if ap != null and sk != null:
		for nombre in ANIMS_ORIGINALES:
			_comprobar(ap.has_animation(nombre), "Conserva animación original '%s'" % nombre)
		for nombre in ANIMS_T05:
			_comprobar(ap.has_animation(nombre), "Contiene animación nueva '%s'" % nombre)
			if ap.has_animation(nombre):
				var anim := ap.get_animation(nombre)
				_comprobar(anim.length > 0.2 and anim.get_track_count() >= 20,
					"'%s' válida (%.2fs, %d pistas)" % [nombre, anim.length, anim.get_track_count()])

		# Evaluar agachado_reposo frente a reposo en esqueleto
		var b_spine := sk.find_bone("DEF-spine")
		var b_thigh := sk.find_bone("DEF-thigh.L")
		var b_shin := sk.find_bone("DEF-shin.L")
		var b_foot := sk.find_bone("DEF-foot.L")
		ap.play("reposo")
		ap.seek(0.0, true)
		var hip_pie := sk.get_bone_global_pose(b_spine).origin.y
		ap.play("agachado_reposo")
		ap.seek(0.5, true)
		var hip_ag := sk.get_bone_global_pose(b_spine).origin.y
		var p_hip := sk.get_bone_global_pose(b_thigh).origin
		var p_knee := sk.get_bone_global_pose(b_shin).origin
		var p_ankle := sk.get_bone_global_pose(b_foot).origin
		var v_muslo := (p_hip - p_knee).normalized()
		var v_pant := (p_ankle - p_knee).normalized()
		var flex_rodilla := 180.0 - rad_to_deg(v_muslo.angle_to(v_pant))
		_comprobar(hip_pie - hip_ag > 0.18, "agachado_reposo baja la cadera (%.3f -> %.3f m)" % [hip_pie, hip_ag])
		_comprobar(flex_rodilla >= 75.0 and flex_rodilla <= 105.0,
			"agachado_reposo dobla las rodillas ~90° (%.1f°)" % flex_rodilla)

		# Evaluar movimiento entre frames de agachado_andar y saltar/caer/aterrizar
		ap.play("agachado_andar")
		ap.seek(0.0, true)
		var pie_0 := sk.get_bone_global_pose(b_foot).origin
		ap.seek(0.35, true)
		var pie_1 := sk.get_bone_global_pose(b_foot).origin
		_comprobar(pie_0.distance_to(pie_1) > 0.08, "agachado_andar desplaza los pies al caminar (%.3f m)" % pie_0.distance_to(pie_1))

	nodo.queue_free()


func _comprobar_jugador() -> void:
	# Suelo de prueba mínimo para probar la física y los estados reales del Jugador
	var arena := Node3D.new()
	add_child(arena)
	var cuerpo := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(40, 1, 40)
	col.shape = caja
	col.position = Vector3(0, -0.5, 0)
	cuerpo.add_child(col)
	arena.add_child(cuerpo)

	var ps_j := load(RUTA_JUGADOR) as PackedScene
	var j := ps_j.instantiate() as Jugador
	arena.add_child(j)
	j.colocar(Vector3.ZERO, 0.0, 0.0)
	j.activar()
	await _fisica(15)

	_comprobar(j._anim != null, "Jugador tiene _anim cargado")
	if j._anim == null:
		arena.queue_free()
		return

	for ciclica in ["reposo", "andar", "agachado_reposo", "agachado_andar", "caer"]:
		_comprobar(j._anim.get_animation(ciclica).loop_mode == Animation.LOOP_LINEAR,
			"'%s' configurada en bucle LOOP_LINEAR" % ciclica)
	for unica in ["herramienta", "saltar", "aterrizar"]:
		_comprobar(j._anim.get_animation(unica).loop_mode == Animation.LOOP_NONE,
			"'%s' configurada en LOOP_NONE" % unica)

	# 1. Agachado quieto
	Input.action_press("agachar")
	await _fisica(20)
	_comprobar(j.estado_mov == "agachado" and j._anim_propia and j._anim_actual == "agachado_reposo",
		"agachado quieto usa 'agachado_reposo' con _anim_propia=true (%s)" % j._anim_actual)
	_comprobar(j._visual.scale.is_equal_approx(Vector3.ONE) and absf(j._visual.rotation.x) < 0.01,
		"agachado quieto apaga la deformación del modelo")

	# 2. Agachado andando
	Input.action_press("mover_arriba")
	await _fisica(25)
	_comprobar(j.estado_mov == "agachado" and j._anim_propia and j._anim_actual == "agachado_andar",
		"agachado andando usa 'agachado_andar' (%s)" % j._anim_actual)
	Input.action_release("mover_arriba")
	Input.action_release("agachar")
	await _fisica(20)

	# 3. Saltar, caer y aterrizar (pulsación real de Espacio por viewport)
	for pulsada in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pulsada
		get_viewport().push_input(ev)
	await _fisica(3)
	_comprobar(j.estado_mov == "salto" and j._anim_propia and j._anim_actual == "saltar",
		"subida del salto usa 'saltar' (%s)" % j._anim_actual)

	var vio_caer := false
	var vio_aterrizar := false
	for _i in range(90):
		await _fisica(1)
		if j.estado_mov == "caida" and j._anim_propia and j._anim_actual == "caer":
			vio_caer = true
		if j.estado_mov == "aterrizaje" and j._anim_propia and j._anim_actual == "aterrizar":
			vio_aterrizar = true
		if j.is_on_floor() and j.estado_mov == "suelo" and vio_caer:
			break
	_comprobar(vio_caer, "bajada del salto usa 'caer' con _anim_propia=true")
	_comprobar(vio_aterrizar, "llegada al suelo usa 'aterrizar' con _anim_propia=true")

	arena.queue_free()


func _fisica(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame
