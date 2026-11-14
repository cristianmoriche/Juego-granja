extends Node
## Prueba de T12-mapa: etiquetas sin solapes, marcadores clave, dirección de Leo, leyenda >= 18 px con fondo,
## vegetación no blanca en la foto cenital y mundo 3D intacto. Funciona tanto en --headless como con ventana.

var _ok := 0
var _fallos: Array[String] = []
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			push_error("PRUEBA T12 MAPA AGOTO EL TIEMPO LIMITE (60 s)")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _comprobar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos.append(msg)
		push_error("FALLO T12: " + msg)


func _esperar_mapa() -> void:
	while Escenas.en_transicion:
		await get_tree().process_frame
	var mm: Minimapa = Interfaz.minimapa()
	var t0 := Time.get_ticks_msec()
	while (mm == null or not mm.lista()) and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await get_tree().process_frame


func _tiene_categoria(marcadores: Array, cat: String, nombre_sub: String = "") -> bool:
	for m: Dictionary in marcadores:
		if String(m.get("categoria", "")) == cat:
			if nombre_sub.is_empty() or nombre_sub.to_lower() in String(m.get("texto", "")).to_lower():
				return true
	return false


func _verificar_disposicion(mapa_id: String, res: Vector2i, escala_texto: int) -> void:
	var grande: MapaGrande = Interfaz.get_node("Raiz/MapaGrande")
	var disp: Dictionary = grande.calcular_disposicion()
	var area: Rect2 = disp["area"]
	var etiquetas: Array = disp["etiquetas"]
	var marcadores: Array = disp["marcadores"]
	var ley: Dictionary = disp["leyenda"]
	var rect_ley: Rect2 = ley["rect"]
	var tam_l := int(ley["tam"])
	var eti := "%s [%dx%d, txt=%d]" % [mapa_id, res.x, res.y, escala_texto]

	_comprobar(rect_ley.has_area(), "%s: la leyenda tiene rectángulo de fondo" % eti)
	_comprobar(rect_ley.position.y >= area.end.y, "%s: la leyenda no pisa la foto del mapa" % eti)
	_comprobar(rect_ley.end.y <= grande.size.y and rect_ley.position.x >= 0.0 and rect_ley.end.x <= grande.size.x,
		"%s: la leyenda cabe entera en pantalla" % eti)

	var escala_vp := float(res.x) / 1600.0
	if DisplayServer.get_name() != "headless" and grande.is_inside_tree():
		var sv := grande.get_viewport_transform().get_scale().x
		if sv > 0.01:
			escala_vp = sv
	_comprobar(tam_l >= 18, "%s: tamaño de fuente en lienzo >= 18 (%d)" % [eti, tam_l])
	_comprobar(float(tam_l) * escala_vp >= 17.99, "%s: tamaño real en pantalla >= 18 px (%.2f)" % [eti, float(tam_l) * escala_vp])

	# Ningún par de etiquetas puede solaparse ni salir del recuadro del mapa.
	var area_tol := area.grow(1.5)
	for i in etiquetas.size():
		var ei: Dictionary = etiquetas[i]
		var ri: Rect2 = ei["rect"]
		_comprobar(area_tol.encloses(ri), "%s: etiqueta «%s» dentro del mapa (%s vs %s)" % [eti, ei["texto"], ri, area])
		_comprobar(not ri.intersects(rect_ley), "%s: etiqueta «%s» no invade la leyenda" % [eti, ei["texto"]])
		for j in range(i + 1, etiquetas.size()):
			var ej: Dictionary = etiquetas[j]
			var rj: Rect2 = ej["rect"]
			_comprobar(not ri.intersects(rj), "%s: «%s» y «%s» no se solapan" % [eti, ei["texto"], ej["texto"]])
		# Tampoco tapa los iconos de otros marcadores ni el propio marcador.
		for m: Dictionary in marcadores:
			var rm: Rect2 = m["rect"]
			_comprobar(not ri.intersects(rm), "%s: «%s» no tapa el icono de «%s»" % [eti, ei["texto"], m["id"]])


func _verificar_vegetacion_y_mundo(mapa_id: String) -> void:
	var mapa := Escenas.mapa_actual_nodo()
	_comprobar(mapa != null and mapa.cargador != null, "%s: mapa y cargador válidos" % mapa_id)
	# Verificar que el mundo 3D conservó sus rangos originales de distancia (no fue alterado).
	for n: Node in mapa.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g == null:
			continue
		if String(g.name).ends_with("_L1"):
			_comprobar(g.visible, "%s: %s sigue visible tras FotoCenital" % [mapa_id, g.name])
		elif String(g.name).begins_with("mm_grass_") or String(g.name).begins_with("mm_fern_"):
			_comprobar(absf(g.visibility_range_end - CargadorMapa.ALCANCE_PLANTAS) < 0.1,
				"%s: %s mantiene ALCANCE_PLANTAS original (%.1f)" % [mapa_id, g.name, g.visibility_range_end])
			break

	if DisplayServer.get_name() == "headless":
		return

	var mm := Interfaz.minimapa()
	_comprobar(mm.textura != null, "%s: Minimapa tiene foto" % mapa_id)
	var img := mm.textura.get_image()
	_comprobar(img != null and not img.is_empty(), "%s: imagen cenital no vacía" % mapa_id)
	if img != null and (mapa_id == "granja" or mapa_id == "pueblo" or mapa_id == "mina_exterior"):
		var verdes := 0
		var blancos := 0
		var total := 0
		var paso_x := maxi(1, img.get_width() / 96)
		var paso_y := maxi(1, img.get_height() / 96)
		for y in range(0, img.get_height(), paso_y):
			for x in range(0, img.get_width(), paso_x):
				var c := img.get_pixel(x, y)
				total += 1
				if c.g > c.r * 0.96 and c.g > c.b * 1.15 and c.g > 0.08 and c.g < 0.78:
					verdes += 1
				if c.r > 0.95 and c.g > 0.95 and c.b > 0.95:
					blancos += 1
		var pct_blancos := 100.0 * float(blancos) / float(maxi(total, 1))
		_comprobar(verdes >= 15, "%s: presencia de vegetación verde natural en foto cenital (verdes=%d)" % [mapa_id, verdes])
		_comprobar(pct_blancos < 0.5, "%s: sin vegetación ni parches blancos quemados (%.2f%%)" % [mapa_id, pct_blancos])


func _ejecutar() -> void:
	var vals_antes := Ajustes.valores.duplicate()
	var ruta_antes := Ajustes.ruta
	Ajustes.ruta = "user://ajustes_prueba_t12.cfg"
	Ajustes.restaurar()

	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_t12.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 660
	Juego.clima = "sol"
	FotoCenital.olvidar()

	var con_ventana := DisplayServer.get_name() != "headless"
	var resoluciones: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]

	for mapa_id: String in ["granja", "pueblo", "mina_exterior", "mina_interior"]:
		await Escenas.ir_a_mapa(mapa_id)
		await _esperar_mapa()
		Interfaz.cerrar_todo()
		Interfaz.alternar_mapa()
		await get_tree().process_frame

		var grande: MapaGrande = Interfaz.get_node("Raiz/MapaGrande")
		var marcadores := grande.ultimos_marcadores()
		_comprobar(_tiene_categoria(marcadores, "leo", "leo"), "%s: marcador de Leo presente" % mapa_id)
		for m: Dictionary in marcadores:
			if String(m.get("categoria", "")) == "leo":
				_comprobar((m.get("dir", Vector2.ZERO) as Vector2).length() > 0.5, "%s: Leo incluye vector de dirección" % mapa_id)
		match mapa_id:
			"granja":
				_comprobar(_tiene_categoria(marcadores, "casa", "casa de leo"), "granja: marcador de Casa")
				_comprobar(_tiene_categoria(marcadores, "salida", "villaverde"), "granja: salida a Villaverde")
			"pueblo":
				_comprobar(_tiene_categoria(marcadores, "tienda", "tienda"), "pueblo: marcador de Tienda")
				_comprobar(_tiene_categoria(marcadores, "herreria", "herrer"), "pueblo: marcador de Herrería")
				_comprobar(_tiene_categoria(marcadores, "taberna", "taberna"), "pueblo: marcador de Taberna")
				_comprobar(_tiene_categoria(marcadores, "ayuntamiento", "ayuntamiento"), "pueblo: marcador de Ayuntamiento")
				_comprobar(_tiene_categoria(marcadores, "capilla", "capilla"), "pueblo: marcador de Capilla")
			"mina_exterior":
				_comprobar(_tiene_categoria(marcadores, "mina", "mina"), "mina_exterior: marcador de Mina")
				_comprobar(_tiene_categoria(marcadores, "salida", "villaverde"), "mina_exterior: salida a Villaverde")
			"mina_interior":
				_comprobar(_tiene_categoria(marcadores, "salida", "mina"), "mina_interior: salida de la mina")

		_verificar_vegetacion_y_mundo(mapa_id)

		for res in resoluciones:
			if con_ventana:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(res)
				await get_tree().process_frame
				await get_tree().process_frame
			for esc_txt: int in [0, 1, 2]:
				Ajustes.valores["texto"] = esc_txt
				_verificar_disposicion(mapa_id, res, esc_txt)

		Interfaz.alternar_mapa()
		await get_tree().process_frame

	if con_ventana:
		DisplayServer.window_set_size(Vector2i(1600, 900))
	Ajustes.valores = vals_antes
	Ajustes.ruta = ruta_antes
	_terminado = true

	if _fallos.is_empty():
		print("PRUEBA T12 MAPA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA T12 MAPA FALLIDA (%d fallos, %d ok): %s" % [_fallos.size(), _ok, str(_fallos)])
		get_tree().quit(1)
