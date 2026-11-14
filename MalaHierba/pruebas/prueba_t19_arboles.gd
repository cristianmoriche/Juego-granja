extends Node
## Prueba permanente T19: verifica que los árboles de los mapas se exportan sin decimación,
## conservan LOD1 con auto-LOD y visibility_range con fundido, mantienen CULL_BACK en cortezas/troncos
## y CULL_DISABLED + recorte alfa en agujas, y cargan en menos de 5 segundos.

const MAPAS := ["granja", "pueblo", "mina_exterior"]
const TRIS_MIN := {
	"fir_tree_01_a_LOD1": 170000,
	"fir_tree_01_b_LOD1": 120000,
	"fir_tree_01_c_LOD1": 65000,
	"fir_sapling_a": 150000,
	"fir_sapling_b": 145000,
	"fir_sapling_c": 120000,
	"pine_sapling_small_a": 140000,
	"pine_sapling_small_b": 120000,
	"pine_sapling_small_c": 130000,
	"dead_tree_trunk": 100000,
	"tree_stump_01": 40000,
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
	if not nombre_nodo.begins_with("arb_"):
		return ""
	var partes := nombre_nodo.substr(4).split("_")
	if partes.size() >= 2 and partes[-1].begins_with("L") and partes[-1].substr(1).is_valid_int():
		partes.resize(partes.size() - 1)
	var recortar := 3
	while recortar > 0 and partes.size() > 1 and partes[-1].is_valid_int():
		partes.resize(partes.size() - 1)
		recortar -= 1
	return "_".join(partes)


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
		if c.tiempo_carga_ms > 5000:
			fallos.append("%s carga lenta: %d ms (> 5000 ms)" % [id_m, c.tiempo_carga_ms])

		var vistos := {}
		var nodos_arbol := 0
		for h in c.nodo_instancias.get_children():
			if not (h is MeshInstance3D):
				continue
			var mi := h as MeshInstance3D
			var proto := _proto_arbol(String(mi.name))
			if proto.is_empty():
				continue
			nodos_arbol += 1
			if mi.mesh == null:
				fallos.append("%s árbol %s sin malla" % [id_m, mi.name])
				continue
			if mi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF or mi.visibility_range_end <= 0.0:
				fallos.append("%s árbol %s sin visibility_range con fundido" % [id_m, mi.name])
				break
			if vistos.has(proto):
				continue
			vistos[proto] = true
			if proto.ends_with("_LOD2"):
				fallos.append("%s sigue usando prototipo principal LOD2 (%s)" % [id_m, proto])
			var tris := _contar_tris(mi.mesh)
			if TRIS_MIN.has(proto) and tris < int(TRIS_MIN[proto]):
				fallos.append("%s %s decimado (%d < %d tris)" % [id_m, proto, tris, int(TRIS_MIN[proto])])
			var dir_import := "res://assets/mapas/%s/protos/%s.glb.import" % [id_m, proto]
			if FileAccess.file_exists(dir_import):
				var cfg := ConfigFile.new()
				if cfg.load(dir_import) == OK and not bool(cfg.get_value("params", "meshes/generate_lods", false)):
					fallos.append("%s %s sin meshes/generate_lods=true" % [id_m, proto])
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if sm == null:
					fallos.append("%s %s sup %d sin StandardMaterial3D" % [id_m, proto, i])
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
			fallos.append("%s sin nodos MeshInstance3D de árboles" % id_m)
		print("[%s] arboles OK (%d nodos, %d protos, carga %d ms)" % [id_m, nodos_arbol, vistos.size(), c.tiempo_carga_ms])
		c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
