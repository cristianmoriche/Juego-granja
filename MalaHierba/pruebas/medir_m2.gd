extends SceneTree
## Herramienta de M2 (no es una prueba): mide las casas, puertas y personajes reales para elegir la escala de Leo.
## Uso: godot.ps1 --headless --path <proyecto> --script res://pruebas/medir_m2.gd [-- detalle]
## Imprime líneas «MED» (una por objeto o grupo) y «PERS» (una por personaje).

func _aabb_mundo(n: Node3D) -> AABB:
	var total := AABB()
	var primero := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		if primero:
			total = a
			primero = false
		else:
			total = total.merge(a)
	return total


func _initialize() -> void:
	var detalle := "detalle" in OS.get_cmdline_user_args()
	for id in ["pueblo", "granja", "mina_exterior"]:
		var ps := load("res://assets/mapas/%s/%s.glb" % [id, id]) as PackedScene
		var raiz := ps.instantiate() as Node3D
		root.add_child(raiz)
		print("MED === ", id, "  escala raiz ", raiz.scale)
		var grupos: Dictionary = {}
		for m in raiz.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var nombre := String(mi.name)
			var pref := nombre.get_slice("_", 0)
			if pref in ["Terreno", "wooden", "txt"]:
				continue
			var a := mi.global_transform * mi.get_aabb()
			var clave := nombre if detalle else pref
			if nombre.to_lower().contains("puerta") or nombre.to_lower().contains("marco"):
				clave = nombre
			if not grupos.has(clave):
				grupos[clave] = a
			else:
				grupos[clave] = (grupos[clave] as AABB).merge(a)
		for k in grupos:
			var a: AABB = grupos[k]
			print("MED %-30s y=%.2f..%.2f  alto=%.2f  x=%.1f..%.1f z=%.1f..%.1f" % [k, a.position.y, a.end.y, a.size.y, a.position.x, a.end.x, a.position.z, a.end.z])
		raiz.queue_free()
	for modelo in ["leo", "herrero", "tendera", "tabernero", "alcalde", "minero", "nino"]:
		var ruta := "res://assets/personajes/leo/leo.glb" if modelo == "leo" else "res://assets/personajes/aldeanos/%s.glb" % modelo
		var inst := (load(ruta) as PackedScene).instantiate() as Node3D
		root.add_child(inst)
		var a := _aabb_mundo(inst)
		print("PERS %-10s base y=%.2f alto=%.2f  escala raiz %s" % [modelo, a.position.y, a.size.y, inst.scale])
		inst.queue_free()
	quit(0)
