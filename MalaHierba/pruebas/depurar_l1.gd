extends Node
# Depuración de L1: lista las colisiones de un mapa (L1_SOLO) y lanza rayos hacia abajo en una rejilla alrededor de un punto.
func _ready() -> void:
	var id := OS.get_environment("L1_SOLO")
	var c := CargadorMapa.new()
	c.id_mapa = id
	add_child(c)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for cs in c.colisiones.get_children():
		if not cs is CollisionShape3D:
			continue
		var s := (cs as CollisionShape3D).shape as ConcavePolygonShape3D if (cs as CollisionShape3D).shape is ConcavePolygonShape3D else null
		var bb := AABB()
		if s != null:
			var caras := s.get_faces()
			if caras.size() > 0:
				bb = AABB(cs.global_transform * caras[0], Vector3.ZERO)
				for v in caras:
					bb = bb.expand(cs.global_transform * v)
		print(cs.name, " ", bb)
	var p := c.marcador(OS.get_environment("L1_MARC")).global_position
	for dx in [-2.0, 0.0, 2.0, 6.0, 12.0]:
		for dz in [-1.0, 0.0, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(dx, 1.5, dz), p + Vector3(dx, -5, dz), 1)
			var r := c.get_world_3d().direct_space_state.intersect_ray(q)
			print("rayo ", dx, ",", dz, " -> ", r.get("position", "nada"), " ", r.get("collider", null))
	get_tree().quit(0)
