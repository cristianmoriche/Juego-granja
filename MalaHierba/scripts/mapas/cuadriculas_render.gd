class_name CuadriculasRender
extends Node3D
## Divide los mapas exteriores en cuadrículas espaciales de 16 m para hacer frustum culling
## y reducir progresivamente el detalle (LOD, sombras y props diminutos) según la distancia.

const TAM_CUADRICULA := 16.0
const DISTANCIA_SEGURA_CAMARA := 0.5
const DISTANCIA_LUZ_DETRAS := 8.0
const MARGEN_FRUSTUM := 1.5

var _mapa: Mapa = null
var _celdas: Array[Dictionary] = []
var _mapa_celdas: Dictionary = {}
var _npcs_cache: Array[Node] = []
var _t_npcs: float = 0.0
var _t_actualizacion: float = 0.0
var _ult_cam_pos: Vector3 = Vector3.INF
var _ult_cam_dir: Vector3 = Vector3.ZERO
var _ult_calidad: int = -1
var _sucio: bool = true
var _forzar_visible: bool = false


func _ready() -> void:
	set_process(true)


func construir(mapa: Mapa, cargador: CargadorMapa) -> void:
	_mapa = mapa
	_celdas.clear()
	_mapa_celdas.clear()
	if cargador == null:
		return
	if cargador.geometria != null:
		_indexar_geometria(cargador.geometria)
	if cargador.nodo_instancias != null:
		_indexar_instancias(cargador.nodo_instancias)
	if cargador.nodo_luces != null:
		_indexar_luces(cargador.nodo_luces)
	for celda: Dictionary in _celdas:
		var caja := celda["aabb"] as AABB
		celda["centro"] = caja.get_center()
		celda["radio"] = caja.size.length() * 0.5
		celda["ultimo_estado"] = []
	_npcs_cache = get_tree().get_nodes_in_group("npc") if is_inside_tree() else []
	_sucio = true
	call_deferred("_evaluar_ahora")


func _evaluar_ahora() -> void:
	_sucio = true
	_ult_cam_pos = Vector3.INF
	_process(0.0)


func forzar_todo_visible(activo: bool) -> void:
	_forzar_visible = activo
	if activo:
		_restaurar_todo_visible()
	else:
		_sucio = true
		_ult_cam_pos = Vector3.INF


func resumen_estado() -> Dictionary:
	var vis := 0
	var ocultas := 0
	var nodos_ocultos := 0
	for celda: Dictionary in _celdas:
		var est: Array = celda["ultimo_estado"]
		var en_frustum := est.is_empty() or bool(est[0])
		if en_frustum:
			vis += 1
		else:
			ocultas += 1
		nodos_ocultos += _contar_ocultos_celda(celda)
	var npcs_vis := 0
	var npcs_ocultos := 0
	var lista_npcs := get_tree().get_nodes_in_group("npc") if is_inside_tree() else _npcs_cache
	for n: Node in lista_npcs:
		if not is_instance_valid(n):
			continue
		var modelo := n.get_node_or_null("Modelo") as Node3D
		if modelo != null and not modelo.visible:
			npcs_ocultos += 1
		else:
			npcs_vis += 1
	return {
		"celdas_total": _celdas.size(),
		"celdas_visibles": vis,
		"celdas_ocultas": ocultas,
		"nodos_ocultos": nodos_ocultos,
		"npcs_visibles": npcs_vis,
		"npcs_ocultos": npcs_ocultos,
	}


func _contar_ocultos_celda(celda: Dictionary) -> int:
	var ocultos := 0
	for clave: String in ["estructuras", "detalles", "arboles_l2", "arboles_peq", "mm_diminuta", "mm_hierba", "mm_rocas_peq", "mm_otros", "luces"]:
		for reg: Dictionary in celda[clave]:
			var n := reg["n"] as Node3D
			if is_instance_valid(n) and not n.visible:
				ocultos += 1
	return ocultos


func _obtener_celda(pos: Vector3, caja: AABB) -> Dictionary:
	var coord := Vector2i(floori(pos.x / TAM_CUADRICULA), floori(pos.z / TAM_CUADRICULA))
	if _mapa_celdas.has(coord):
		var c: Dictionary = _mapa_celdas[coord]
		c["aabb"] = (c["aabb"] as AABB).merge(caja)
		return c
	var nueva := {
		"coord": coord,
		"aabb": caja,
		"centro": caja.get_center(),
		"radio": 1.0,
		"estructuras": [],
		"detalles": [],
		"arboles_l2": [],
		"arboles_peq": [],
		"mm_diminuta": [],
		"mm_hierba": [],
		"mm_rocas_peq": [],
		"mm_otros": [],
		"luces": [],
		"ultimo_estado": [],
	}
	_mapa_celdas[coord] = nueva
	_celdas.append(nueva)
	return nueva


func _indexar_geometria(raiz: Node) -> void:
	var pilas: Array[Node] = [raiz]
	while not pilas.is_empty():
		var nodo: Node = pilas.pop_back()
		for h in nodo.get_children():
			pilas.append(h)
		if not (nodo is MeshInstance3D):
			continue
		var mi := nodo as MeshInstance3D
		if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var nom := String(mi.name)
		if nom.begins_with("Terreno") or nom.contains("agua") or nom == "Ventanas_luz":
			continue
		var caja := mi.global_transform * mi.get_aabb()
		if maxf(caja.size.x, caja.size.z) > 36.0:
			continue
		var max_dim := maxf(caja.size.x, maxf(caja.size.y, caja.size.z))
		var celda := _obtener_celda(caja.get_center(), caja)
		var reg := {"n": mi, "lod": mi.lod_bias, "sombra": mi.cast_shadow}
		var es_detalle := max_dim < 4.0 or nom.contains("wooden_barrels_") or nom.contains("wooden_crate_") or nom.contains("wooden_bucket_") or nom.begins_with("txt_")
		if es_detalle:
			(celda["detalles"] as Array).append(reg)
		else:
			(celda["estructuras"] as Array).append(reg)


func _indexar_instancias(cont: Node) -> void:
	for h in cont.get_children():
		if h is MeshInstance3D:
			var mi := h as MeshInstance3D
			var nom := String(mi.name)
			# T12 exige que los _L1 sigan visible = true tras FotoCenital (se ocultan por visibility_range_end).
			if nom.ends_with("_L1"):
				continue
			var caja := mi.global_transform * mi.get_aabb()
			if not caja.has_volume():
				caja = AABB(mi.global_position - Vector3(1.5, 0.0, 1.5), Vector3(3.0, 8.0, 3.0))
			var celda := _obtener_celda(mi.global_position, caja)
			var reg := {"n": mi, "lod": mi.lod_bias, "sombra": mi.cast_shadow}
			if nom.contains("stump") or nom.contains("sapling"):
				(celda["arboles_peq"] as Array).append(reg)
			else:
				(celda["arboles_l2"] as Array).append(reg)
		elif h is MultiMeshInstance3D:
			var mmi := h as MultiMeshInstance3D
			var caja := mmi.global_transform * mmi.get_aabb()
			if not caja.has_volume():
				caja = AABB(mmi.global_position - Vector3.ONE, Vector3.ONE * 2.0)
			var celda := _obtener_celda(caja.get_center(), caja)
			var reg := {"n": mmi, "lod": mmi.lod_bias}
			var nom := String(mmi.name)
			if nom.contains("tiny") or nom.contains("moss_") or nom.contains("dandelion") or nom.contains("weed") or nom.contains("shrub_sorrel") or nom.contains("dry_branches") or nom.contains("grass_medium_02"):
				(celda["mm_diminuta"] as Array).append(reg)
			elif nom.contains("rock_moss_set_02_") or nom.contains("stone_01"):
				(celda["mm_rocas_peq"] as Array).append(reg)
			elif nom.contains("mm_grass_") or nom.contains("mm_fern_") or nom.contains("mm_shrub_") or nom.contains("mm_trigo_"):
				(celda["mm_hierba"] as Array).append(reg)
			else:
				(celda["mm_otros"] as Array).append(reg)


func _indexar_luces(cont: Node) -> void:
	for h in cont.get_children():
		if h is Light3D and not (h is DirectionalLight3D):
			var l := h as Light3D
			var caja := AABB(l.global_position - Vector3(2.0, 2.0, 2.0), Vector3(4.0, 4.0, 4.0))
			var celda := _obtener_celda(l.global_position, caja)
			(celda["luces"] as Array).append({"n": l, "sombra_orig": l.shadow_enabled})


func _process(delta: float) -> void:
	if _forzar_visible or DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null or cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return
	_t_actualizacion += delta
	_t_npcs += delta
	if _t_npcs >= 1.0:
		_t_npcs = 0.0
		_npcs_cache = get_tree().get_nodes_in_group("npc")
	var cam_pos := cam.global_position
	var cam_dir := -cam.global_basis.z.normalized()
	var calidad := clampi(int(Ajustes.valores.calidad), 0, 3)
	var movida := _ult_cam_pos == Vector3.INF or cam_pos.distance_squared_to(_ult_cam_pos) > 0.09
	var girada := cam_dir.dot(_ult_cam_dir) < 0.9995
	if not _sucio and not movida and not girada and calidad == _ult_calidad and _t_actualizacion < 0.10:
		return
	_t_actualizacion = 0.0
	_sucio = false
	_ult_cam_pos = cam_pos
	_ult_cam_dir = cam_dir
	_ult_calidad = calidad

	var planos := cam.get_frustum()
	var signos := _calcular_signos_frustum(planos, cam)
	_actualizar_celdas(cam_pos, planos, signos, calidad)
	_actualizar_npcs(cam_pos, planos, signos, calidad)


func _calcular_signos_frustum(planos: Array[Plane], cam: Camera3D) -> PackedFloat32Array:
	var p_dentro := cam.global_position - cam.global_basis.z * minf(maxf(cam.near + 2.0, 4.0), cam.far * 0.5)
	var signos := PackedFloat32Array()
	signos.resize(planos.size())
	for i in planos.size():
		signos[i] = -1.0 if planos[i].distance_to(p_dentro) > 0.0 else 1.0
	return signos


func _aabb_en_frustum(caja: AABB, planos: Array[Plane], signos: PackedFloat32Array, margen: float) -> bool:
	var mn := caja.position
	var mx := caja.end
	for i in planos.size():
		var s := signos[i]
		var n := planos[i].normal * s
		var px := mn.x if n.x >= 0.0 else mx.x
		var py := mn.y if n.y >= 0.0 else mx.y
		var pz := mn.z if n.z >= 0.0 else mx.z
		if (n.x * px + n.y * py + n.z * pz - planos[i].d * s) > margen:
			return false
	return true


func _actualizar_celdas(cam_pos: Vector3, planos: Array[Plane], signos: PackedFloat32Array, cal: int) -> void:
	var d_diminuta: float = [20.0, 25.0, 32.0, 46.0][cal]
	var d_detalle: float = [24.0, 32.0, 42.0, 62.0][cal]
	var d_roca_peq: float = [30.0, 40.0, 52.0, 74.0][cal]
	var d_hierba: float = [34.0, 44.0, 56.0, 80.0][cal]
	var d_otros: float = [58.0, 74.0, 96.0, 130.0][cal]
	var d_arb_l2: float = [56.0, 72.0, 92.0, 125.0][cal]
	var d_arb_peq: float = [28.0, 34.0, 44.0, 60.0][cal]
	var d_sombra_est: float = [46.0, 60.0, 75.0, 110.0][cal]
	var d_luz: float = [28.0, 35.0, 44.0, 60.0][cal]

	for celda: Dictionary in _celdas:
		var caja := celda["aabb"] as AABB
		var centro := celda["centro"] as Vector3
		var radio := float(celda["radio"])
		var dist_borde := maxf(0.0, cam_pos.distance_to(centro) - radio)
		var en_frustum := caja.grow(DISTANCIA_SEGURA_CAMARA).has_point(cam_pos) or _aabb_en_frustum(caja, planos, signos, MARGEN_FRUSTUM)

		var vis_est := en_frustum
		var tier_est := 0 if dist_borde < 22.0 else (1 if dist_borde < 48.0 else 2)
		var sombra_est := en_frustum and dist_borde <= d_sombra_est
		var vis_det := en_frustum and dist_borde <= d_detalle
		var tier_det := 0 if dist_borde <= 16.0 else 1
		var vis_dim := en_frustum and dist_borde <= d_diminuta
		var vis_hierba := en_frustum and dist_borde <= d_hierba
		var tier_hierba := 0 if dist_borde <= 18.0 else 1
		var vis_roca_peq := en_frustum and dist_borde <= d_roca_peq
		var tier_roca_peq := 0 if dist_borde <= 16.0 else 1
		var vis_otros := en_frustum and dist_borde <= d_otros
		var tier_otros := 0 if dist_borde <= 28.0 else 1
		var vis_arb_l2 := en_frustum and dist_borde <= d_arb_l2
		var tier_arb_l2 := 0 if dist_borde <= 38.0 else 1
		var vis_arb_peq := en_frustum and dist_borde <= d_arb_peq
		var vis_luz := (en_frustum and dist_borde <= d_luz) or caja.grow(DISTANCIA_LUZ_DETRAS).has_point(cam_pos)

		var estado := [
			en_frustum, vis_est, tier_est, sombra_est, vis_det, tier_det,
			vis_dim, vis_hierba, tier_hierba, vis_roca_peq, tier_roca_peq,
			vis_otros, tier_otros, vis_arb_l2, tier_arb_l2, vis_arb_peq, vis_luz
		]
		var previo: Array = celda["ultimo_estado"]
		if previo == estado:
			continue
		var cambiar_est: bool = previo.is_empty() or previo[1] != vis_est or previo[2] != tier_est or previo[3] != sombra_est
		var cambiar_det: bool = previo.is_empty() or previo[4] != vis_det or previo[5] != tier_det
		var cambiar_dim: bool = previo.is_empty() or previo[6] != vis_dim
		var cambiar_hierba: bool = previo.is_empty() or previo[7] != vis_hierba or previo[8] != tier_hierba
		var cambiar_roca: bool = previo.is_empty() or previo[9] != vis_roca_peq or previo[10] != tier_roca_peq
		var cambiar_otros: bool = previo.is_empty() or previo[11] != vis_otros or previo[12] != tier_otros
		var cambiar_arb_l2: bool = previo.is_empty() or previo[13] != vis_arb_l2 or previo[14] != tier_arb_l2
		var cambiar_arb_peq: bool = previo.is_empty() or previo[15] != vis_arb_peq
		var cambiar_luz: bool = previo.is_empty() or previo[16] != vis_luz
		celda["ultimo_estado"] = estado

		if cambiar_est:
			for reg: Dictionary in celda["estructuras"]:
				var mi := reg["n"] as MeshInstance3D
				if not is_instance_valid(mi):
					continue
				mi.visible = vis_est
				if vis_est:
					var orig_lod := float(reg["lod"])
					mi.lod_bias = orig_lod if tier_est == 0 else (minf(orig_lod, 0.45) if tier_est == 1 else minf(orig_lod, 0.16))
					mi.cast_shadow = (reg["sombra"] as GeometryInstance3D.ShadowCastingSetting) if sombra_est else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cambiar_det:
			for reg: Dictionary in celda["detalles"]:
				var mi := reg["n"] as MeshInstance3D
				if not is_instance_valid(mi):
					continue
				mi.visible = vis_det
				if vis_det:
					var orig_lod := float(reg["lod"])
					mi.lod_bias = orig_lod if tier_det == 0 else minf(orig_lod, 0.20)
					mi.cast_shadow = (reg["sombra"] as GeometryInstance3D.ShadowCastingSetting) if tier_det == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cambiar_dim:
			for reg: Dictionary in celda["mm_diminuta"]:
				var mmi := reg["n"] as MultiMeshInstance3D
				if is_instance_valid(mmi):
					mmi.visible = vis_dim
		if cambiar_hierba:
			for reg: Dictionary in celda["mm_hierba"]:
				var mmi := reg["n"] as MultiMeshInstance3D
				if not is_instance_valid(mmi):
					continue
				mmi.visible = vis_hierba
				if vis_hierba:
					var orig_lod := float(reg["lod"])
					mmi.lod_bias = orig_lod if tier_hierba == 0 else minf(orig_lod, 0.35)
		if cambiar_roca:
			for reg: Dictionary in celda["mm_rocas_peq"]:
				var mmi := reg["n"] as MultiMeshInstance3D
				if not is_instance_valid(mmi):
					continue
				mmi.visible = vis_roca_peq
				if vis_roca_peq:
					var orig_lod := float(reg["lod"])
					mmi.lod_bias = orig_lod if tier_roca_peq == 0 else minf(orig_lod, 0.22)
		if cambiar_otros:
			for reg: Dictionary in celda["mm_otros"]:
				var mmi := reg["n"] as MultiMeshInstance3D
				if not is_instance_valid(mmi):
					continue
				mmi.visible = vis_otros
				if vis_otros:
					var orig_lod := float(reg["lod"])
					mmi.lod_bias = orig_lod if tier_otros == 0 else minf(orig_lod, 0.22)
		if cambiar_arb_l2:
			for reg: Dictionary in celda["arboles_l2"]:
				var mi := reg["n"] as MeshInstance3D
				if not is_instance_valid(mi):
					continue
				mi.visible = vis_arb_l2
				if vis_arb_l2:
					var orig_lod := float(reg["lod"])
					mi.lod_bias = orig_lod if tier_arb_l2 == 0 else minf(orig_lod, 0.022)
		if cambiar_arb_peq:
			for reg: Dictionary in celda["arboles_peq"]:
				var mi := reg["n"] as MeshInstance3D
				if is_instance_valid(mi):
					mi.visible = vis_arb_peq
		if cambiar_luz:
			for reg: Dictionary in celda["luces"]:
				var l := reg["n"] as Light3D
				if is_instance_valid(l):
					l.visible = vis_luz


func _actualizar_npcs(cam_pos: Vector3, planos: Array[Plane], signos: PackedFloat32Array, cal: int) -> void:
	var d_max: float = [48.0, 58.0, 72.0, 100.0][cal]
	for n: Node in _npcs_cache:
		if not is_instance_valid(n) or not n.has_method("aplicar_culling_visual"):
			continue
		var n3 := n as Node3D
		var d_npc := cam_pos.distance_to(n3.global_position)
		var caja := AABB(n3.global_position - Vector3(0.9, 0.1, 0.9), Vector3(1.8, 2.2, 1.8))
		var en_vista := (d_npc <= 4.5) or _aabb_en_frustum(caja, planos, signos, 2.5)
		if not en_vista or d_npc > d_max:
			n.call("aplicar_culling_visual", false, 0.12, false, false)
		elif d_npc <= 16.0:
			n.call("aplicar_culling_visual", true, 1.0, true, true)
		elif d_npc <= 34.0:
			n.call("aplicar_culling_visual", true, 0.35, cal >= 2 and d_npc <= 26.0, true)
		else:
			n.call("aplicar_culling_visual", true, 0.12, false, d_npc <= 52.0)


func _restaurar_todo_visible() -> void:
	for celda: Dictionary in _celdas:
		celda["ultimo_estado"] = []
		for clave: String in ["estructuras", "detalles", "arboles_l2", "arboles_peq"]:
			for reg: Dictionary in celda[clave]:
				var mi := reg["n"] as MeshInstance3D
				if is_instance_valid(mi):
					mi.visible = true
					mi.lod_bias = float(reg["lod"])
					mi.cast_shadow = reg["sombra"] as GeometryInstance3D.ShadowCastingSetting
		for clave: String in ["mm_diminuta", "mm_hierba", "mm_rocas_peq", "mm_otros"]:
			for reg: Dictionary in celda[clave]:
				var mmi := reg["n"] as MultiMeshInstance3D
				if is_instance_valid(mmi):
					mmi.visible = true
					mmi.lod_bias = float(reg["lod"])
		for reg: Dictionary in celda["luces"]:
			var l := reg["n"] as Light3D
			if is_instance_valid(l):
				l.visible = true
	var npcs := get_tree().get_nodes_in_group("npc") if is_inside_tree() else _npcs_cache
	for n: Node in npcs:
		if is_instance_valid(n) and n.has_method("aplicar_culling_visual"):
			n.call("aplicar_culling_visual", true, 1.0, true, true)
