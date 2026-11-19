class_name FotoCenital
extends RefCounted
## Foto cenital ortográfica de un mapa para el minimapa: un SubViewport con una Camera3D ortográfica mirando hacia
## abajo, sin niebla y con luz de mediodía; se hace una vez por mapa (queda en caché) y tarda unos milisegundos.
## `await FotoCenital.generar(mapa, id, rect)` devuelve una Texture2D (arriba de la imagen = −Z, derecha = +X).
## Sin ventana gráfica (--headless) devuelve un esquema dibujado con el polígono de límites.

const CAPA_TECHOS := 1 << 19

static var _cache: Dictionary = {}
static var ultimo_ms: int = 0
static var ultimo_real: bool = false     # true si la última era una foto de verdad y no un esquema


static func olvidar(id: String = "") -> void:
	if id.is_empty():
		_cache.clear()
	else:
		_cache.erase(id)


static func generar(mapa: Node3D, id: String, rect: Rect2, max_lado: int = 1024, y_alto: float = 120.0, y_bajo: float = -30.0, forzar: bool = false) -> Texture2D:
	if not forzar and _cache.has(id):
		return _cache[id]
	var t0 := Time.get_ticks_msec()
	var tex: Texture2D = null
	ultimo_real = false
	if DisplayServer.get_name() != "headless" and mapa != null and mapa.is_inside_tree():
		tex = await _fotografiar(mapa, rect, max_lado, y_alto, y_bajo)
		ultimo_real = tex != null
	if tex == null:
		tex = esquema(id, rect)
	ultimo_ms = Time.get_ticks_msec() - t0
	_cache[id] = tex
	return tex


static func _fotografiar(mapa: Node3D, rect: Rect2, max_lado: int, y_alto: float, y_bajo: float) -> Texture2D:
	var arbol := mapa.get_tree()
	var escala := float(max_lado) / maxf(rect.size.x, rect.size.y)
	var tam := Vector2i(maxi(int(rect.size.x * escala), 64), maxi(int(rect.size.y * escala), 64))

	var sv := SubViewport.new()
	sv.size = tam
	sv.own_world_3d = false          # mira el mismo mundo 3D que la ventana
	sv.transparent_bg = false
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.positional_shadow_atlas_size = 0
	sv.use_occlusion_culling = false

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.08, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.76, 0.81, 0.75)
	env.ambient_light_energy = 0.56
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.ssao_enabled = false
	env.glow_enabled = false

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.cull_mask &= ~CAPA_TECHOS
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rect.size.y
	cam.near = 0.5
	cam.far = (y_alto - y_bajo) + 20.0
	cam.environment = env
	sv.add_child(cam)

	# Luz de mediodía algo inclinada para que el relieve se note sin quemar hojas ni techos; sin sombras (barato y sin cortes).
	var luz := DirectionalLight3D.new()
	luz.light_energy = 0.92
	luz.light_color = Color(1.0, 0.97, 0.90)
	luz.shadow_enabled = false
	luz.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	sv.add_child(luz)

	# El sol del mapa, la lluvia y el jugador no salen en la foto.
	var ocultos: Array[Node3D] = []
	for ruta in ["Sol", "Lluvia"]:
		var n := mapa.get_node_or_null(ruta) as Node3D
		if n != null and n.visible:
			ocultos.append(n)
			n.visible = false
	for j: Node in arbol.get_nodes_in_group("jugador"):
		var j3 := j as Node3D
		if j3 != null and j3.visible:
			ocultos.append(j3)
			j3.visible = false

	# Para la foto cenital se muestran también árboles jóvenes, helechos y hierba a distancia (sin tocar el mundo 3D al acabar).
	var cuad := mapa.get_node_or_null("CuadriculasRender")
	if cuad != null and cuad.has_method("forzar_todo_visible"):
		cuad.call("forzar_todo_visible", true)
	var ajustes_vis: Array[Dictionary] = []
	for nodo: Node in mapa.find_children("*", "GeometryInstance3D", true, false):
		var g := nodo as GeometryInstance3D
		if g == null or not g.visible:
			continue
		var es_l1 := String(g.name).ends_with("_L1")
		if not es_l1 and g.visibility_range_end <= 0.0 and g.visibility_range_begin <= 0.0:
			continue
		ajustes_vis.append({
			"nodo": g,
			"vis": g.visible,
			"r_ini": g.visibility_range_begin,
			"r_fin": g.visibility_range_end,
			"m_ini": g.visibility_range_begin_margin,
			"m_fin": g.visibility_range_end_margin,
			"lod": g.lod_bias,
		})
		if es_l1:
			g.visible = false
		else:
			g.visibility_range_begin = 0.0
			g.visibility_range_end = 0.0
			g.visibility_range_begin_margin = 0.0
			g.visibility_range_end_margin = 0.0
			g.lod_bias = maxf(g.lod_bias, 0.45)

	arbol.root.add_child(sv)
	cam.global_position = Vector3(rect.get_center().x, y_alto, rect.get_center().y)
	cam.global_rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()

	for d: Dictionary in ajustes_vis:
		var g := d["nodo"] as GeometryInstance3D
		if is_instance_valid(g):
			g.visible = bool(d["vis"])
			g.visibility_range_begin = float(d["r_ini"])
			g.visibility_range_end = float(d["r_fin"])
			g.visibility_range_begin_margin = float(d["m_ini"])
			g.visibility_range_end_margin = float(d["m_fin"])
			g.lod_bias = float(d["lod"])
	for n in ocultos:
		if is_instance_valid(n):
			n.visible = true
	if cuad != null and cuad.has_method("forzar_todo_visible"):
		cuad.call("forzar_todo_visible", false)
	sv.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Esquema sin gráficos: el polígono de límites en verde sobre fondo oscuro (para pruebas sin ventana).
static func esquema(id: String, rect: Rect2) -> Texture2D:
	var lado := 192
	var w := lado
	var h := maxi(int(float(lado) * rect.size.y / maxf(rect.size.x, 0.1)), 32)
	if rect.size.y > rect.size.x:
		h = lado
		w = maxi(int(float(lado) * rect.size.x / maxf(rect.size.y, 0.1)), 32)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.08, 0.07))
	var poligono := LimitesMapa.poligono(id)
	for y in h:
		for x in w:
			var p := rect.position + Vector2((float(x) + 0.5) / float(w) * rect.size.x, (float(y) + 0.5) / float(h) * rect.size.y)
			if poligono.size() < 3 or Geometry2D.is_point_in_polygon(p, poligono):
				img.set_pixel(x, y, Color(0.38, 0.5, 0.3))
	return ImageTexture.create_from_image(img)
