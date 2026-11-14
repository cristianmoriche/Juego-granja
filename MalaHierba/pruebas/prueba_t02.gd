extends Node
## Comprueba la causa de los agujeros: cuerpo cerrado y pesos coherentes entre superficies.
## Los vértices repetidos por material deben deformarse igual en todas las animaciones.
const IDS := ["leo", "herrero", "tendera", "tabernero", "alcalde", "minero", "nino"]
var fallos: Array[String] = []
var total := 0

func comprobar(condicion: bool, mensaje: String) -> void:
	total += 1
	if not condicion:
		fallos.append(mensaje)

func clave(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 100000), roundi(p.y * 100000), roundi(p.z * 100000)]

func _ready() -> void:
	for id: String in IDS:
		var ruta := "res://assets/personajes/leo/leo.glb" if id == "leo" else "res://assets/personajes/aldeanos/%s.glb" % id
		var modelo := (load(ruta) as PackedScene).instantiate()
		add_child(modelo)
		# T02b: el cuerpo vuelve a llamarse como en el modelo original (<vecino>_cuerpo, Leo_malla).
		var cuerpos := modelo.find_children("*_cuerpo*", "MeshInstance3D", true, false)
		if cuerpos.is_empty():
			cuerpos = modelo.find_children("*Leo_malla*", "MeshInstance3D", true, false)
		comprobar(cuerpos.size() == 1, id + ": cuerpo reconstruido presente")
		for mi: MeshInstance3D in modelo.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				comprobar(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, id + ": superficie opaca " + mi.name)
		if not cuerpos.is_empty():
			_comprobar_cuerpo(id, cuerpos[0], modelo)
		# Las prendas reconstruidas también deben ser cerradas y deformarse sin grietas.
		for prenda: MeshInstance3D in modelo.find_children("Prenda_*", "MeshInstance3D", true, false):
			_comprobar_cuerpo(id + "/" + prenda.name, prenda, modelo)
		modelo.queue_free()
	if fallos.is_empty():
		print("PRUEBA T02 OK (%d comprobaciones)" % total)
		get_tree().quit(0)
	else:
		for f: String in fallos:
			print("FALLO: ", f)
		print("PRUEBA T02 FALLO (%d)" % fallos.size())
		get_tree().quit(1)

func _comprobar_cuerpo(id: String, mi: MeshInstance3D, modelo: Node) -> void:
	var aristas: Dictionary = {}
	var pesos_por_posicion: Dictionary = {}
	var conexiones: Dictionary = {}
	var sk := mi.get_node(mi.skeleton) as Skeleton3D
	var puntos: Array[Vector3] = []
	var influencias: Array[Dictionary] = []
	var pesos_validos := true
	var juntas_coherentes := true
	for s in mi.mesh.get_surface_count():
		var a := mi.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var huesos: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var pesos: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var por_vertice := pesos.size() / vertices.size()
		for v in vertices.size():
			var suma := 0.0
			var inf: Dictionary = {}
			for j in por_vertice:
				var w := pesos[v * por_vertice + j]
				if w > 0.00001:
					var b := huesos[v * por_vertice + j]
					inf[b] = w
					suma += w
					pesos_validos = pesos_validos and b >= 0 and b < mi.skin.get_bind_count()
			pesos_validos = pesos_validos and absf(suma - 1.0) < 0.002
			var k := clave(vertices[v])
			if pesos_por_posicion.has(k):
				var anteriores: Dictionary = pesos_por_posicion[k]
				for b: int in inf:
					juntas_coherentes = juntas_coherentes and absf(inf[b] - anteriores.get(b, 0.0)) < 0.002
			else:
				pesos_por_posicion[k] = inf
			puntos.append(vertices[v])
			influencias.append(inf)
		for t in range(0, indices.size(), 3):
			for j in 3:
				var k1 := clave(vertices[indices[t + j]])
				var k2 := clave(vertices[indices[t + (j + 1) % 3]])
				var k := k1 + "/" + k2 if k1 < k2 else k2 + "/" + k1
				aristas[k] = aristas.get(k, 0) + 1
				if not conexiones.has(k1):
					conexiones[k1] = []
				if not conexiones.has(k2):
					conexiones[k2] = []
				conexiones[k1].append(k2)
				conexiones[k2].append(k1)
	var abiertas := 0
	for n: int in aristas.values():
		if n != 2:
			abiertas += 1
	comprobar(abiertas == 0, "%s: %d aristas abiertas o múltiples" % [id, abiertas])
	var visitados: Dictionary = {}
	var islas := 0
	for inicio: String in conexiones:
		if visitados.has(inicio):
			continue
		islas += 1
		var pila: Array = [inicio]
		while not pila.is_empty():
			var actual: String = pila.pop_back()
			if visitados.has(actual):
				continue
			visitados[actual] = true
			for vecino: String in conexiones[actual]:
				if not visitados.has(vecino):
					pila.append(vecino)
	comprobar(islas == 1, "%s: cuerpo en una sola pieza (%d islas)" % [id, islas])
	comprobar(pesos_validos, id + ": pesos normalizados y huesos válidos")
	comprobar(juntas_coherentes, id + ": continuidad entre materiales durante la animación")
	var anim := modelo.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for nombre: String in anim.get_animation_list():
		if nombre == "RESET":
			continue
		anim.play(nombre)
		for paso in 12:
			anim.seek(anim.get_animation(nombre).length * paso / 12.0, true)
			sk.force_update_all_bone_transforms()
			var transformaciones: Array[Transform3D] = []
			for b in mi.skin.get_bind_count():
				var indice := mi.skin.get_bind_bone(b)
				if indice < 0:
					indice = sk.find_bone(mi.skin.get_bind_name(b))
				transformaciones.append(sk.get_bone_global_pose(indice) * mi.skin.get_bind_pose(b))
			var correctos := true
			for i in puntos.size():
				var p := Vector3.ZERO
				for b: int in influencias[i]:
					p += (transformaciones[b] * puntos[i]) * float(influencias[i][b])
				correctos = correctos and p.is_finite() and p.length() < 3.5
			comprobar(correctos, "%s: deformación finita en %s, muestra %d" % [id, nombre, paso])
	print(id, ": cuerpo cerrado, ", pesos_por_posicion.size(), " vértices geométricos; animaciones comprobadas")
