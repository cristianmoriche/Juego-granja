extends Node
## Prueba permanente T18: verifica que todos los materiales de vegetación e instancias de los mapas
## tienen textura albedo real, UVs, recorte alfa (alpha scissor) y doble cara en hojas/agujas/plantas,
## y ningún material queda con prefijo ORIG_ sin conectar.

const MAPAS := ["granja", "pueblo", "mina_exterior", "mina_interior"]
const PREFIJOS_FOLIAGE := ["grass_", "fern_", "dandelion_", "shrub_", "weed_"]
const PREFIJOS_ARBOL_CON_COPA := ["fir_tree_01_", "fir_sapling_", "pine_sapling_small_"]
const PREFIJOS_VEG := [
	"fir_", "pine_", "dead_tree", "tree_stump", "grass_", "fern_",
	"dandelion_", "shrub_", "weed_", "dry_branches_", "rock_moss_"
]

var fallos: Array[String] = []


func _ready() -> void:
	await _ejecutar()
	if fallos.is_empty():
		print("PRUEBA T18 OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: " + "; ".join(fallos))
		get_tree().quit(1)


func _ejecutar() -> void:
	for id_m: String in MAPAS:
		var c := CargadorMapa.new()
		c.id_mapa = id_m
		add_child(c)
		if not c.listo:
			fallos.append("%s no cargó" % id_m)
			c.queue_free()
			await get_tree().process_frame
			continue

		_comprobar_estaticos(id_m, c.geometria)
		_comprobar_instancias(id_m, c.nodo_instancias)
		print("[%s] vegetación comprobada (%d nodos MultiMesh)" % [id_m, c.nodo_instancias.get_child_count()])
		c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame


func _comprobar_estaticos(id_m: String, nodo: Node) -> void:
	if nodo is MeshInstance3D:
		var mi := nodo as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var ov := mi.get_surface_override_material(i)
				var base := mi.mesh.surface_get_material(i)
				var mat := ov if ov != null else base
				if mat != null and String(mat.resource_name).begins_with("ORIG_"):
					fallos.append("%s estático %s conserva material %s" % [id_m, mi.name, mat.resource_name])
	for h in nodo.get_children():
		_comprobar_estaticos(id_m, h)


func _tiene_prefijo(nombre: String, prefijos: Array) -> bool:
	for p: String in prefijos:
		if nombre.begins_with(p):
			return true
	return false


func _proto_de_nodo(nombre_nodo: String) -> String:
	# Formato de CargadorMapa: mm_<proto>_<cx>_<cy> o arb_<proto>_<cx>_<cy>_<idx>[_L1/_L2]
	if nombre_nodo.begins_with("arb_"):
		var partes := nombre_nodo.substr(4).split("_")
		if partes.size() >= 2 and partes[-1].begins_with("L") and partes[-1].substr(1).is_valid_int():
			partes.resize(partes.size() - 1)
		var recortar := 3
		while recortar > 0 and partes.size() > 1 and partes[-1].is_valid_int():
			partes.resize(partes.size() - 1)
			recortar -= 1
		return "_".join(partes)
	if not nombre_nodo.begins_with("mm_"):
		return nombre_nodo
	var partes := nombre_nodo.substr(3).rsplit("_", true, 2)
	return partes[0] if partes.size() >= 3 else nombre_nodo


func _comprobar_instancias(id_m: String, cont: Node) -> void:
	var vistas := {}
	for h in cont.get_children():
		var mesh_inst: Mesh = null
		if h is MultiMeshInstance3D:
			var mmi := h as MultiMeshInstance3D
			if mmi.multimesh != null:
				mesh_inst = mmi.multimesh.mesh
		elif h is MeshInstance3D:
			mesh_inst = (h as MeshInstance3D).mesh
		if mesh_inst == null:
			continue
		var proto := _proto_de_nodo(String(h.name))
		if vistas.has(proto):
			continue
		vistas[proto] = true
		var mesh := mesh_inst
		var sup_cnt := mesh.get_surface_count()
		if sup_cnt == 0:
			fallos.append("%s proto %s sin superficies" % [id_m, proto])
			continue

		if proto.begins_with("trigo_"):
			var sm_t := mesh.surface_get_material(0) as StandardMaterial3D
			if sm_t == null or sm_t.albedo_color.b >= sm_t.albedo_color.r:
				fallos.append("%s proto %s sin color dorado de trigo" % [id_m, proto])
			continue

		if not _tiene_prefijo(proto, PREFIJOS_VEG):
			for i in sup_cnt:
				var m0 := mesh.surface_get_material(i)
				if m0 != null and String(m0.resource_name).begins_with("ORIG_"):
					fallos.append("%s proto %s material %s" % [id_m, proto, m0.resource_name])
			continue

		var tiene_corteza := false
		var tiene_recorte := false
		var es_arbol_copa := _tiene_prefijo(proto, PREFIJOS_ARBOL_CON_COPA)
		var es_planta_foliage := _tiene_prefijo(proto, PREFIJOS_FOLIAGE)

		for i in sup_cnt:
			var material := mesh.surface_get_material(i)
			var arr := mesh.surface_get_arrays(i)
			if arr.size() <= Mesh.ARRAY_TEX_UV or arr[Mesh.ARRAY_TEX_UV] == null:
				fallos.append("%s proto %s sup %d sin UV" % [id_m, proto, i])
			if material is ShaderMaterial and material.shader.resource_path == "res://shaders/follaje_h03.gdshader":
				tiene_recorte = true
				if material.get_shader_parameter("albedo_tex") == null:
					fallos.append("%s proto %s sup %d sin textura albedo" % [id_m, proto, i])
				if "ALPHA_SCISSOR_THRESHOLD" not in material.shader.code or "cull_disabled" not in material.shader.code:
					fallos.append("%s proto %s sup %d sin recorte de doble cara" % [id_m, proto, i])
				continue
			var sm := material as StandardMaterial3D
			if sm == null:
				fallos.append("%s proto %s sup %d tiene un material inesperado" % [id_m, proto, i])
				continue
			if String(sm.resource_name).begins_with("ORIG_"):
				fallos.append("%s proto %s conserva ORIG_ (%s)" % [id_m, proto, sm.resource_name])
			if sm.albedo_texture == null:
				fallos.append("%s proto %s sup %d sin textura albedo" % [id_m, proto, i])
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				fallos.append("%s proto %s sup %d usa transparencia mezclada en lugar de recorte" % [id_m, proto, i])
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				tiene_recorte = true
				if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
					fallos.append("%s proto %s sup %d alpha scissor sin doble cara" % [id_m, proto, i])
			else:
				tiene_corteza = true

		if es_planta_foliage and not tiene_recorte:
			fallos.append("%s proto %s planta sin alpha scissor" % [id_m, proto])
		if es_arbol_copa and (sup_cnt < 2 or not tiene_corteza or not tiene_recorte):
			fallos.append("%s proto %s árbol incompleto (sup=%d corteza=%s recorte=%s)" % [id_m, proto, sup_cnt, str(tiene_corteza), str(tiene_recorte)])
