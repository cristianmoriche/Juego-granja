extends SceneTree
## Herramienta de M2 (no es una prueba): mide a qué velocidad avanza el suelo bajo los pies de Leo en la animación
## «andar» (el pie de apoyo va hacia atrás a esa velocidad): es la velocidad de marcha que no patina con la escala 1.
## Uso: godot.ps1 --headless --path <proyecto> --script res://pruebas/medir_andar_m2.gd

func _initialize() -> void:
	var inst := (load("res://assets/personajes/leo/leo.glb") as PackedScene).instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	await process_frame
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("ANIM animaciones: ", ap.get_animation_list())
	var pies: Array[int] = []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i).to_lower()
		if n.contains("foot") and not n.contains("ik") and not n.contains("ctrl"):
			pies.append(i)
			print("ANIM hueso pie: ", sk.get_bone_name(i))
	for nombre in ["andar", "reposo"]:
		var an := ap.get_animation(nombre)
		if an == null:
			continue
		print("ANIM %s dura %.3f s, bucle %s" % [nombre, an.length, an.loop_mode])
		for pie in pies:
			var zs: Array[float] = []
			var ys: Array[float] = []
			var paso := 1.0 / 60.0
			var t := 0.0
			ap.play(nombre)
			while t < an.length - 0.0001:
				ap.seek(t, true)
				var p := (sk.global_transform * sk.get_bone_global_pose(pie)).origin
				zs.append(p.z)
				ys.append(p.y)
				t += paso
			var ymin := 1e9
			for y in ys:
				ymin = minf(ymin, y)
			# Apoyo = fotogramas con el pie cerca de su punto más bajo; su velocidad hacia atrás es la del suelo.
			var suma := 0.0
			var n := 0
			for k in range(1, zs.size()):
				if ys[k] < ymin + 0.06 and ys[k - 1] < ymin + 0.06:
					suma += -(zs[k] - zs[k - 1]) / paso
					n += 1
			var zmin := 1e9
			var zmax := -1e9
			for z in zs:
				zmin = minf(zmin, z)
				zmax = maxf(zmax, z)
			print("ANIM %s %s: apoyo %d fotogramas, velocidad de suelo media %.2f m/s, recorrido z %.2f m, y min %.2f" % [nombre, sk.get_bone_name(pie), n, suma / maxf(n, 1), zmax - zmin, ymin])
	quit(0)
