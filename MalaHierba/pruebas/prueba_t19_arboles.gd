extends Node
## Prueba permanente T19: verifica que los árboles de los mapas están optimizados dentro de su presupuesto,
## se instancian en MultiMesh sin nodos arb_* sueltos ni doble dibujado (VISIBILITY_RANGE_FADE_DISABLED),
## conservan auto-LOD, CULL_BACK en cortezas/troncos y CULL_DISABLED + recorte alfa en agujas,
## y cargan en menos de 2.5 segundos.

const MAPAS := ["granja", "pueblo", "mina_exterior"]
const TRIS_RANGO := {
	"fir_tree_01_a_LOD1": [4000, 12000],
	"fir_tree_01_b_LOD1": [3500, 11000],
	"fir_tree_01_c_LOD1": [3000, 10000],
	"fir_sapling_a": [1500, 6500],
	"fir_sapling_b": [1500, 6500],
	"fir_sapling_c": [1500, 6500],
	"pine_sapling_small_a": [1500, 6500],
	"pine_sapling_small_b": [1500, 6500],
	"pine_sapling_small_c": [1500, 6500],
	"dead_tree_trunk": [1000, 5000],
	"tree_stump_01": [600, 3500],
}

var fallos: Array[String] = []


func _ready() -> void:
	await _ejecutar()
	if fallos.is_empty():
		print("PRUEBA T19 OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: " + "; ".join(fallos))
		get_tree().quit(1)


func _proto_arbol(nombre_nodo: String) -> String:
	if not nombre_nodo.begins_with("mm_"):
		return ""
	var partes := nombre_nodo.substr(3).rsplit("_", true, 2)
	if partes.size() < 3:
		return ""
	var proto := partes[0]
	return proto if (TRIS_RANGO.has(proto) or proto == "roble_viejo") else ""


func _ruta_import_arbol(id_m: String, cargador: CargadorMapa, proto: String) -> String:
	var base := "res://assets/mapas/%s/" % id_m
	var protos: Dictionary = cargador._inst.get("protos", {})
	var info: Dictionary = cargador._inst.get("info", {})
	var info_p: Dictionary = info.get(proto, {}) as Dictionary
	var lods: Dictionary = info_p.get("lods", {}) as Dictionary
	var rel := str(lods.get("LOD1", "")) if lods.has("LOD1") else str(protos.get(proto, ""))
	if rel.is_empty():
		return "res://assets/mapas/%s/protos/%s.glb.import" % [id_m, proto]
	return CargadorMapa._ruta_proto(base, rel) + ".import"


func _contar_tris(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var idx: int = mesh.surface_get_array_index_len(i) if mesh is ArrayMesh else 0
		if idx > 0:
			total += idx / 3
		else:
			var arr := mesh.surface_get_arrays(i)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
				total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _ejecutar() -> void:
	for id_m: String in MAPAS:
		var c := CargadorMapa.new()
		c.id_mapa = id_m
		add_child(c)
		for _i in 600:
			if c.listo:
				break
			await get_tree().process_frame
		if not c.listo:
			fallos.append("%s no cargó" % id_m)
			c.queue_free()
			await get_tree().process_frame
			continue
		if c.tiempo_carga_ms > 2500:
			fallos.append("%s carga lenta: %d ms (> 2500 ms)" % [id_m, c.tiempo_carga_ms])

		var vistos := {}
		var nodos_arbol := 0
		for h in c.nodo_instancias.get_children():
			if String(h.name).begins_with("arb_"):
				fallos.append("%s sigue creando nodo suelto %s" % [id_m, h.name])
				break
			if not (h is MultiMeshInstance3D):
				continue
			var mmi := h as MultiMeshInstance3D
			var proto := _proto_arbol(String(mmi.name))
			if proto.is_empty():
				continue
			nodos_arbol += 1
			var mesh_arb: Mesh = mmi.multimesh.mesh if mmi.multimesh != null else null
			if mesh_arb == null:
				fallos.append("%s árbol %s sin malla" % [id_m, mmi.name])
				continue
			if mmi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED or mmi.visibility_range_end <= 0.0:
				fallos.append("%s árbol %s fade/visibility incorrecto (fade=%d end=%.1f)" % [id_m, mmi.name, mmi.visibility_range_fade_mode, mmi.visibility_range_end])
				break
			if vistos.has(proto):
				continue
			vistos[proto] = true
			if proto.ends_with("_LOD2"):
				fallos.append("%s sigue usando prototipo principal LOD2 (%s)" % [id_m, proto])
			var tris := _contar_tris(mesh_arb)
			if TRIS_RANGO.has(proto):
				var rng: Array = TRIS_RANGO[proto]
				if tris < int(rng[0]) or tris > int(rng[1]):
					fallos.append("%s %s tris fuera de rango (%d no en [%d, %d])" % [id_m, proto, tris, int(rng[0]), int(rng[1])])
			var dir_import := _ruta_import_arbol(id_m, c, proto)
			if FileAccess.file_exists(dir_import):
				var cfg := ConfigFile.new()
				if cfg.load(dir_import) == OK and not bool(cfg.get_value("params", "meshes/generate_lods", false)):
					fallos.append("%s %s sin meshes/generate_lods=true" % [id_m, proto])
			else:
				fallos.append("%s %s falta %s" % [id_m, proto, dir_import])
			for i in mesh_arb.get_surface_count():
				var material := mesh_arb.surface_get_material(i)
				if material is ShaderMaterial and material.shader.resource_path == "res://shaders/follaje_h03.gdshader":
					if material.get_shader_parameter("albedo_tex") == null:
						fallos.append("%s %s sup %d sin textura albedo" % [id_m, proto, i])
					if "ALPHA_SCISSOR_THRESHOLD" not in material.shader.code or "cull_disabled" not in material.shader.code:
						fallos.append("%s %s sup %d sin recorte de doble cara" % [id_m, proto, i])
					continue
				var sm := material as StandardMaterial3D
				if sm == null:
					fallos.append("%s %s sup %d tiene un material inesperado" % [id_m, proto, i])
					continue
				if sm.albedo_texture == null:
					fallos.append("%s %s sup %d sin textura albedo" % [id_m, proto, i])
				if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					if sm.cull_mode != BaseMaterial3D.CULL_DISABLED:
						fallos.append("%s %s aguja sup %d sin CULL_DISABLED" % [id_m, proto, i])
				elif sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					if sm.cull_mode != BaseMaterial3D.CULL_BACK:
						fallos.append("%s %s tronco sup %d sin CULL_BACK" % [id_m, proto, i])
				else:
					fallos.append("%s %s sup %d transparencia inválida (%d)" % [id_m, proto, i, sm.transparency])
		if nodos_arbol == 0:
			fallos.append("%s sin nodos MultiMeshInstance3D de árboles" % id_m)
		print("[%s] arboles OK (%d nodos, %d protos, carga %d ms)" % [id_m, nodos_arbol, vistos.size(), c.tiempo_carga_ms])
		c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
