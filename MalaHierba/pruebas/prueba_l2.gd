extends Node
## Prueba del carril L2 (personajes): carga cada glb, comprueba Skeleton3D, AnimationPlayer y nombres de animación,
## cuenta triángulos y comprueba altura, pies en el suelo y frente (+Z). Imprime PRUEBA OK o PRUEBA FALLO.

const RUTA_LEO := "res://assets/personajes/leo/leo.glb"
const RUTA_ALDEANO := "res://assets/personajes/aldeanos/%s.glb"
const ALDEANOS: Array[String] = ["herrero", "tendera", "tabernero", "alcalde", "minero", "nino"]
const ANIMS_LEO: Array[String] = ["reposo", "andar", "saludar", "herramienta"]
const ANIMS_ALDEANO: Array[String] = ["reposo", "andar", "saludar"]
## Aldeanos que se entregaron sin rig (se apuntan aquí y en el estado de L2). Ahora: ninguno.
const ESTATICOS: Array[String] = []
const MAX_TRIS_LEO := 32000
const MAX_TRIS_ALDEANO := 22000
## Altura esperada (m) de cada modelo, con margen del 12 %.
const ALTURAS := {"leo": 1.97, "herrero": 1.75, "tendera": 1.65, "tabernero": 1.70, "alcalde": 1.75, "minero": 1.75, "nino": 1.25}

var fallos: Array[String] = []


func _ready() -> void:
	_comprobar("leo", RUTA_LEO, ANIMS_LEO, MAX_TRIS_LEO)
	for id in ALDEANOS:
		_comprobar(id, RUTA_ALDEANO % id, ANIMS_ALDEANO, MAX_TRIS_ALDEANO)
	if fallos.is_empty():
		print("PRUEBA OK")
		get_tree().quit(0)
	else:
		for f in fallos:
			print("  - ", f)
		print("PRUEBA FALLO: %d problema(s)" % fallos.size())
		get_tree().quit(1)


func _fallo(id: String, texto: String) -> void:
	fallos.append("%s: %s" % [id, texto])


func _comprobar(id: String, ruta: String, anims: Array[String], max_tris: int) -> void:
	if not ResourceLoader.exists(ruta):
		_fallo(id, "no existe " + ruta)
		return
	var esc := load(ruta) as PackedScene
	if esc == null:
		_fallo(id, "no se pudo cargar " + ruta)
		return
	var nodo := esc.instantiate() as Node3D
	add_child(nodo)
	var sk := _buscar(nodo, "Skeleton3D") as Skeleton3D
	var ap := _buscar(nodo, "AnimationPlayer") as AnimationPlayer
	var tris := _triangulos(nodo)
	var caja := _aabb(nodo)
	var info := "%s: %d triángulos, altura %.2f m, base y=%.2f" % [id, tris, caja.size.y, caja.position.y]
	if id in ESTATICOS:
		print(info, " (estático, sin rig)")
		nodo.queue_free()
		return
	if sk == null:
		_fallo(id, "sin Skeleton3D")
	else:
		info += ", %d huesos" % sk.get_bone_count()
		_comprobar_frente(id, sk)
	if ap == null:
		_fallo(id, "sin AnimationPlayer")
	else:
		var lista := Array(ap.get_animation_list())
		info += ", animaciones " + str(lista)
		for a in anims:
			if not ap.has_animation(a):
				_fallo(id, "falta la animación '%s'" % a)
			elif ap.get_animation(a).length <= 0.1 or ap.get_animation(a).get_track_count() < 10:
				_fallo(id, "animación '%s' vacía" % a)
		# la animación se evalúa sin errores y mueve huesos
		if ap.has_animation("andar") and sk != null:
			var antes := sk.get_bone_global_pose(sk.find_bone(_primer_hueso_pierna(sk))).origin
			ap.play("andar")
			ap.seek(0.35, true)
			var despues := sk.get_bone_global_pose(sk.find_bone(_primer_hueso_pierna(sk))).origin
			if antes.distance_to(despues) < 0.01:
				_fallo(id, "'andar' no mueve las piernas")
	if tris <= 0:
		_fallo(id, "sin triángulos")
	if tris > max_tris:
		_fallo(id, "demasiados triángulos (%d > %d)" % [tris, max_tris])
	var esperada: float = ALTURAS.get(id, 1.7)
	if absf(caja.size.y - esperada) > esperada * 0.12:
		_fallo(id, "altura %.2f m, se esperaba ~%.2f" % [caja.size.y, esperada])
	if absf(caja.position.y) > 0.08:
		_fallo(id, "los pies no están en y=0 (%.2f)" % caja.position.y)
	print(info)
	nodo.queue_free()


## Frente en +Z: la puntera debe quedar por delante (z mayor) del tobillo en el reposo del esqueleto.
func _comprobar_frente(id: String, sk: Skeleton3D) -> void:
	var tobillo := sk.find_bone("DEF-foot.L")
	var puntera := sk.find_bone("DEF-toe.L")
	if tobillo < 0 or puntera < 0:
		_fallo(id, "no encuentro los huesos DEF-foot.L / DEF-toe.L (nombres: %s)" % str(_nombres(sk)).substr(0, 120))
		return
	var z1 := sk.get_bone_global_rest(tobillo).origin.z
	var z2 := sk.get_bone_global_rest(puntera).origin.z
	if z2 <= z1:
		_fallo(id, "el frente no es +Z (puntera z=%.2f, tobillo z=%.2f)" % [z2, z1])


func _primer_hueso_pierna(sk: Skeleton3D) -> String:
	return "DEF-foot.L"


func _nombres(sk: Skeleton3D) -> Array:
	var r := []
	for i in sk.get_bone_count():
		r.append(sk.get_bone_name(i))
	return r


func _buscar(n: Node, clase: String) -> Node:
	if n.is_class(clase):
		return n
	for h in n.get_children():
		var r := _buscar(h, clase)
		if r != null:
			return r
	return null


func _triangulos(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				t += idx.size() / 3
			else:
				t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for h in n.get_children():
		t += _triangulos(h)
	return t


## Caja envolvente de las mallas en el espacio del nodo raíz (pose de reposo, sin animar).
func _aabb(raiz: Node3D) -> AABB:
	var caja := AABB()
	var primera := true
	for mi in _mallas(raiz):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		var gt: Transform3D = raiz.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		var b := gt * a
		if primera:
			caja = b
			primera = false
		else:
			caja = caja.merge(b)
	return caja


func _mallas(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D:
		r.append(n)
	for h in n.get_children():
		r += _mallas(h)
	return r
