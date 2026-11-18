class_name MapaGrande
extends Control
## Mapa grande a pantalla casi completa (tecla M; M o Esc lo cierra): la misma foto cenital del minimapa, orientada al
## norte (arriba = −Z), con el borde del área jugable, a Leo con su dirección, vecinos, edificios y salidas con su nombre
## sin solaparse, y una leyenda legible con fondo propio.

signal cerrado

const MARGEN_LATERAL := 60.0
const MARGEN_ARRIBA := 80.0
const MARGEN_HINT := 32.0
const MARGEN_LEYENDA_GAP := 12.0
const TAM_ETIQUETA := 19
const TAM_LEYENDA_MIN := 23
const COLOR_VELO := Color(0.02, 0.015, 0.012, 0.93)

const COLOR_CASA := Color(0.60, 0.88, 0.44)
const COLOR_CASITA := Color(0.84, 0.76, 0.62)
const COLOR_TIENDA := Color(0.30, 0.84, 0.78)
const COLOR_HERRERIA := Color(0.96, 0.48, 0.25)
const COLOR_TABERNA := Color(0.96, 0.74, 0.24)
const COLOR_AYUNTAMIENTO := Color(0.48, 0.72, 0.98)
const COLOR_MINA := Color(0.84, 0.76, 0.52)
const COLOR_CAPILLA := Color(0.86, 0.80, 0.94)
const COLOR_MIRADOR := Color(0.95, 0.82, 0.36)
const COLOR_PESCA := Color(0.35, 0.78, 0.92)

const PILL_PAD_X := 8.0
const PILL_PAD_Y := 4.0

var minimapa: Minimapa = null

var _estilo_leyenda: StyleBoxFlat = null
var _estilos_etiqueta: Dictionary = {}
var _ultima_disposicion: Dictionary = {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func abrir(m: Minimapa) -> void:
	minimapa = m
	visible = true
	queue_redraw()


func cerrar() -> void:
	if not visible:
		return
	visible = false
	cerrado.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Un clic cualquiera lo cierra; el resto de la entrada no pasa al juego mientras está abierto.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT:
			cerrar()
	accept_event()


## Factor de escala configurado por el usuario en Ajustes.
func _escala_texto() -> float:
	return float([1.0, 1.18, 1.35][int(Ajustes.valores.texto)])


## Tamaño de fuente de la leyenda: garantiza al menos 18 px reales también a 1280x720.
func tam_leyenda() -> int:
	var escala_vp := 1.0
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		var s := get_viewport_transform().get_scale().x
		if s >= 0.4:
			escala_vp = minf(s, 2.0)
	var base_px := ceili(maxf(float(TAM_LEYENDA_MIN), 18.0 / escala_vp))
	return roundi(float(base_px) * _escala_texto())


## Tamaño de fuente para etiquetas sobre el mapa.
func _tam_etiqueta() -> int:
	var factor := float([1.0, 1.12, 1.22][int(Ajustes.valores.texto)])
	return roundi(float(TAM_ETIQUETA) * factor)


## Rectángulo de pantalla donde se dibuja la foto (respeta la altura real de la leyenda y ayuda).
func area_foto() -> Rect2:
	if minimapa == null or not minimapa.lista():
		return Rect2(Vector2(MARGEN_LATERAL, MARGEN_ARRIBA), Vector2(100, 100))
	var fuente := Estilo.fuente()
	var ley := _maquetar_leyenda(fuente, maxf(size.x - MARGEN_LATERAL * 2.0, 320.0))
	var margen_abajo := float(ley["margen_abajo"])
	var rect := minimapa.rect_mundo
	var disp := Vector2(maxf(size.x - MARGEN_LATERAL * 2.0, 120.0), maxf(size.y - MARGEN_ARRIBA - margen_abajo, 120.0))
	var s := minf(disp.x / rect.size.x, disp.y / rect.size.y)
	var tam := rect.size * s
	return Rect2(Vector2(MARGEN_LATERAL + (disp.x - tam.x) * 0.5, MARGEN_ARRIBA + (disp.y - tam.y) * 0.5), tam)


## Punto del mundo (x, z) -> posición en pantalla del mapa grande.
func mundo_a_pantalla(p: Vector2) -> Vector2:
	var area := area_foto()
	var rect := minimapa.rect_mundo
	return area.position + (p - rect.position) / rect.size * area.size


## Devuelve la disposición calculada (marcadores, etiquetas sin solaparse y leyenda) para dibujar o verificar.
func calcular_disposicion() -> Dictionary:
	var fuente := Estilo.fuente()
	var tam_l := _tam_etiqueta()
	var area := area_foto()
	var ley := _maquetar_leyenda(fuente, maxf(size.x - MARGEN_LATERAL * 2.0, 320.0))
	var marcadores: Array[Dictionary] = []
	var vecinos: Array[Vector2] = []
	var obstaculos: Array[Rect2] = []
	var obstaculos_npc: Array[Rect2] = []
	var pendientes: Array[Dictionary] = []

	var norte_pos := Vector2(area.end.x - 28.0, area.position.y + 38.0)
	obstaculos.append(Rect2(norte_pos - Vector2(22.0, 26.0), Vector2(44.0, 56.0)))

	if minimapa != null and minimapa.lista():
		var nm_niebla := minimapa.nivel_mina_actual() if minimapa.id_mapa == "mina_interior" else null
		if is_inside_tree():
			for grupo in ["puerta", "salida"]:
				for n3: Node in get_tree().get_nodes_in_group(grupo):
					var nodo := n3 as Node3D
					if nodo == null or not nodo.is_inside_tree():
						continue
					if nm_niebla != null and nm_niebla.has_method("es_punto_explorado") and not bool(nm_niebla.call("es_punto_explorado", Vector2(nodo.global_position.x, nodo.global_position.z))):
						continue
					var q := mundo_a_pantalla(Vector2(nodo.global_position.x, nodo.global_position.z))
					var info := _clasificar_punto(nodo, grupo)
					var radio_obs := 15.0 if String(info["categoria"]) != "salida" else 13.0
					var m_rect := Rect2(q - Vector2(radio_obs, radio_obs), Vector2(radio_obs * 2.0, radio_obs * 2.0))
					obstaculos.append(m_rect)
					marcadores.append({
						"id": String(nodo.name),
						"categoria": String(info["categoria"]),
						"texto": String(info["etiqueta"]),
						"color": _color_categoria(String(info["categoria"])),
						"pos": q,
						"rect": m_rect,
					})
					var txt := String(info["etiqueta"])
					if not txt.is_empty():
						pendientes.append({
							"id": String(nodo.name),
							"categoria": String(info["categoria"]),
							"texto": txt,
							"anchor": q,
							"color": _color_etiqueta(String(info["categoria"])),
							"borde": _color_categoria(String(info["categoria"])),
							"prioridad": int(info["prioridad"]),
							"radio": radio_obs,
							"dir_frente": Vector2.ZERO,
						})
			var mapa_n := _mapa_actual_para_puntos()
			if mapa_n != null and mapa_n.has_method("marcadores_de_tipo"):
				for mk: Marker3D in mapa_n.call("marcadores_de_tipo", "otro"):
					var nom_mk := String(mk.name)
					if nom_mk != "Mirador_Valle" and not nom_mk.begins_with("Pesca_"):
						continue
					var qm := mundo_a_pantalla(Vector2(mk.global_position.x, mk.global_position.z))
					var cat_mk := "mirador" if nom_mk == "Mirador_Valle" else "pesca"
					var eti_mk := "Mirador de la Sierra" if nom_mk == "Mirador_Valle" else "Zona de pesca"
					var mr := Rect2(qm - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
					obstaculos.append(mr)
					marcadores.append({
						"id": nom_mk, "categoria": cat_mk, "texto": eti_mk,
						"color": _color_categoria(cat_mk), "pos": qm, "rect": mr,
					})
					pendientes.append({
						"id": nom_mk, "categoria": cat_mk, "texto": eti_mk, "anchor": qm,
						"color": _color_etiqueta(cat_mk), "borde": _color_categoria(cat_mk),
						"prioridad": 3, "radio": 12.0, "dir_frente": Vector2.ZERO,
					})
			for n3: Node in get_tree().get_nodes_in_group("npc"):
				var nodo := n3 as Node3D
				if nodo == null or not nodo.is_inside_tree() or not nodo.visible:
					continue
				var q := mundo_a_pantalla(Vector2(nodo.global_position.x, nodo.global_position.z))
				vecinos.append(q)
				obstaculos_npc.append(Rect2(q - Vector2(9.0, 9.0), Vector2(18.0, 18.0)))

		var j := minimapa.jugador
		if j != null and is_instance_valid(j):
			var q_leo := mundo_a_pantalla(Vector2(j.global_position.x, j.global_position.z))
			var dir := Vector2(0, -1)
			var d3: Variant = j.get("direccion")
			if d3 is Vector3:
				var d2 := Vector2((d3 as Vector3).x, (d3 as Vector3).z)
				if d2.length() > 0.01:
					dir = d2.normalized()
			var r_leo := Rect2(q_leo - Vector2(21.0, 21.0), Vector2(42.0, 42.0))
			obstaculos.append(r_leo)
			marcadores.append({
				"id": "Leo",
				"categoria": "leo",
				"texto": "Leo",
				"color": Minimapa.COLOR_LEO,
				"pos": q_leo,
				"dir": dir,
				"rect": r_leo,
			})
			pendientes.append({
				"id": "Leo",
				"categoria": "leo",
				"texto": "Leo",
				"anchor": q_leo,
				"color": Minimapa.COLOR_LEO,
				"borde": Minimapa.COLOR_LEO,
				"prioridad": 0,
				"radio": 21.0,
				"dir_frente": dir,
			})

	var etiquetas := _resolver_etiquetas(pendientes, obstaculos, obstaculos_npc, area, fuente, tam_l)
	_ultima_disposicion = {
		"area": area,
		"norte": norte_pos,
		"marcadores": marcadores,
		"vecinos": vecinos,
		"etiquetas": etiquetas,
		"leyenda": ley,
		"tam_etiqueta": tam_l,
	}
	return _ultima_disposicion


func ultimas_etiquetas() -> Array:
	if _ultima_disposicion.is_empty():
		calcular_disposicion()
	return _ultima_disposicion.get("etiquetas", [])


func ultimo_rect_leyenda() -> Rect2:
	if _ultima_disposicion.is_empty():
		calcular_disposicion()
	var ley: Dictionary = _ultima_disposicion.get("leyenda", {})
	return ley.get("rect", Rect2())


func ultimo_tam_leyenda() -> int:
	if _ultima_disposicion.is_empty():
		calcular_disposicion()
	var ley: Dictionary = _ultima_disposicion.get("leyenda", {})
	return int(ley.get("tam", tam_leyenda()))


func ultimos_marcadores() -> Array:
	if _ultima_disposicion.is_empty():
		calcular_disposicion()
	return _ultima_disposicion.get("marcadores", [])


func _clasificar_punto(nodo: Node3D, grupo: String) -> Dictionary:
	var nom := String(nodo.name).to_lower()
	var t: Variant = nodo.get("texto")
	var txt := str(t) if t != null else ""
	if "casa_leo" in nom or "cabaña" in txt.to_lower():
		return {"categoria": "casa", "etiqueta": "Casa de Leo", "prioridad": 1}
	if "tienda" in nom or "tienda" in txt.to_lower():
		return {"categoria": "tienda", "etiqueta": "Tienda de Don Mateo" if txt.is_empty() else txt, "prioridad": 2}
	if "herreria" in nom or "herrería" in txt.to_lower():
		return {"categoria": "herreria", "etiqueta": "Herrería de Clara" if txt.is_empty() else txt, "prioridad": 2}
	if "taberna" in nom or "taberna" in txt.to_lower():
		return {"categoria": "taberna", "etiqueta": "Taberna El Candil" if txt.is_empty() else txt, "prioridad": 1}
	if "alcalde" in nom or "ayuntamiento" in txt.to_lower():
		return {"categoria": "ayuntamiento", "etiqueta": "Ayuntamiento", "prioridad": 2}
	if "capilla" in nom:
		return {"categoria": "capilla", "etiqueta": "Capilla" if txt.is_empty() else txt, "prioridad": 2}
	if "casita" in nom:
		return {"categoria": "casita", "etiqueta": txt, "prioridad": 3}
	if nom == "salida_mina_interior" or "entrada de la mina" in txt.to_lower():
		return {"categoria": "mina", "etiqueta": "Entrada de la mina" if txt.is_empty() else txt, "prioridad": 1}
	return {"categoria": grupo, "etiqueta": txt, "prioridad": 2 if grupo == "salida" else 3}


func _color_categoria(cat: String) -> Color:
	match cat:
		"leo":
			return Minimapa.COLOR_LEO
		"vecino":
			return Minimapa.COLOR_NPC
		"casa":
			return COLOR_CASA
		"casita":
			return COLOR_CASITA
		"tienda":
			return COLOR_TIENDA
		"herreria":
			return COLOR_HERRERIA
		"taberna":
			return COLOR_TABERNA
		"ayuntamiento":
			return COLOR_AYUNTAMIENTO
		"mina":
			return COLOR_MINA
		"capilla":
			return COLOR_CAPILLA
		"mirador":
			return COLOR_MIRADOR
		"pesca":
			return COLOR_PESCA
		"puerta":
			return Minimapa.COLOR_PUERTA
		_:
			return Minimapa.COLOR_SALIDA


func _color_etiqueta(cat: String) -> Color:
	if Ajustes.valores.alto_contraste:
		return Color.WHITE
	if cat == "leo":
		return Minimapa.COLOR_LEO
	return Estilo.COLOR_TEXTO


func _resolver_etiquetas(pendientes: Array[Dictionary], obstaculos: Array[Rect2], obstaculos_npc: Array[Rect2], area: Rect2, fuente: Font, tam: int) -> Array[Dictionary]:
	if pendientes.is_empty():
		return []
	# Ordena por densidad cercana (los puntos en grupos apretados eligen antes su hueco).
	for e: Dictionary in pendientes:
		var a: Vector2 = e["anchor"]
		var vecinos_cerca := 0
		for o: Dictionary in pendientes:
			if o["id"] != e["id"] and a.distance_to(o["anchor"] as Vector2) < 120.0:
				vecinos_cerca += 1
		e["densidad"] = vecinos_cerca
	pendientes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["densidad"]) != int(b["densidad"]):
			return int(a["densidad"]) > int(b["densidad"])
		if int(a["prioridad"]) != int(b["prioridad"]):
			return int(a["prioridad"]) < int(b["prioridad"])
		return String(a["id"]) < String(b["id"])
	)

	var angulos := PackedFloat32Array([
		0.0, PI, -PI * 0.5, PI * 0.5,
		-PI * 0.25, -PI * 0.75, PI * 0.25, PI * 0.75,
		-PI / 8.0, -3.0 * PI / 8.0, -5.0 * PI / 8.0, -7.0 * PI / 8.0,
		PI / 8.0, 3.0 * PI / 8.0, 5.0 * PI / 8.0, 7.0 * PI / 8.0,
	])
	var anillos := PackedFloat32Array([8.0, 22.0, 38.0, 56.0, 78.0, 104.0, 134.0])
	var alto_txt := fuente.get_height(tam)
	var limites_caja := area.grow(-6.0)
	var colocadas: Array[Rect2] = []
	var resultado: Array[Dictionary] = []

	for e: Dictionary in pendientes:
		var txt := String(e["texto"])
		var ancho_txt := fuente.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
		var pill_tam := Vector2(ancho_txt + PILL_PAD_X * 2.0, alto_txt + PILL_PAD_Y * 2.0)
		var anchor: Vector2 = e["anchor"]
		var radio_propio := float(e["radio"])
		var dir_frente: Vector2 = e["dir_frente"]
		var mejor_rect := Rect2()
		var mejor_coste := INF

		for d in anillos:
			for ang in angulos:
				var dir := Vector2(cos(ang), sin(ang))
				var dist_centro := radio_propio + d
				var centro := anchor + Vector2(
					dir.x * (dist_centro + pill_tam.x * 0.5),
					dir.y * (dist_centro + pill_tam.y * 0.5)
				)
				var pos := centro - pill_tam * 0.5
				var cand := _clamped_cand(pos, pill_tam, limites_caja)
				var coste := _evaluar_candidato(cand, anchor, dir_frente, ang, colocadas, obstaculos, obstaculos_npc)
				if coste < mejor_coste:
					mejor_coste = coste
					mejor_rect = cand
			if mejor_coste < 50_000.0:
				break

		if mejor_coste >= 120_000.0:
			var max_x := maxf(limites_caja.position.x, limites_caja.end.x - pill_tam.x)
			var max_y := maxf(limites_caja.position.y, limites_caja.end.y - pill_tam.y)
			var y := limites_caja.position.y
			while y <= max_y + 0.5:
				var x := limites_caja.position.x
				while x <= max_x + 0.5:
					var cand := Rect2(Vector2(x, y), pill_tam)
					var coste := _evaluar_candidato(cand, anchor, dir_frente, 0.0, colocadas, obstaculos, obstaculos_npc)
					if coste < mejor_coste:
						mejor_coste = coste
						mejor_rect = cand
					x += 28.0
				y += 20.0

		colocadas.append(mejor_rect)
		var copia := e.duplicate()
		copia["rect"] = mejor_rect
		copia["tam"] = tam
		copia["guia"] = _punto_mas_cercano_rect(anchor, mejor_rect).distance_to(anchor) > 16.0
		resultado.append(copia)
	return resultado


static func _clamped_cand(pos: Vector2, pill_tam: Vector2, limites_caja: Rect2) -> Rect2:
	pos.x = clampf(pos.x, limites_caja.position.x, maxf(limites_caja.position.x, limites_caja.end.x - pill_tam.x))
	pos.y = clampf(pos.y, limites_caja.position.y, maxf(limites_caja.position.y, limites_caja.end.y - pill_tam.y))
	return Rect2(pos, pill_tam)


static func _evaluar_candidato(cand: Rect2, anchor: Vector2, dir_frente: Vector2, ang: float, colocadas: Array[Rect2], obstaculos: Array[Rect2], obstaculos_npc: Array[Rect2]) -> float:
	var coste := 0.0
	for r in colocadas:
		var rg := r.grow(6.0)
		if cand.intersects(rg):
			coste += 1_000_000.0 + _area_interseccion(cand, rg) * 80.0
	for obs in obstaculos:
		var og := obs.grow(5.0)
		if cand.intersects(og):
			coste += 120_000.0 + _area_interseccion(cand, og) * 40.0
	for n_obs in obstaculos_npc:
		var ng := n_obs.grow(4.0)
		if cand.intersects(ng):
			coste += 4_000.0
	var vec_c := cand.get_center() - anchor
	coste += vec_c.length() * 1.1
	coste += absf(sin(2.0 * ang)) * 10.0
	if dir_frente.length_squared() > 0.1 and vec_c.length() > 1.0:
		if vec_c.normalized().dot(dir_frente) > 0.55:
			coste += 48.0
	return coste


static func _area_interseccion(a: Rect2, b: Rect2) -> float:
	var c := a.intersection(b)
	return c.size.x * c.size.y if c.has_area() else 0.0


static func _punto_mas_cercano_rect(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


func _maquetar_leyenda(fuente: Font, max_ancho: float) -> Dictionary:
	var tam := tam_leyenda()
	var tam_hint := maxi(Estilo.TAM_PEQUENO, roundi(19.0 * _escala_texto()))
	var mostrar_lim := minimapa != null and LimitesMapa.mostrar_borde(minimapa.id_mapa)

	var fila_base: Array[Dictionary] = [
		{"cat": "leo", "texto": "Leo (dirección)"},
		{"cat": "vecino", "texto": "Vecinos"},
		{"cat": "salida", "texto": "Salidas"},
	]
	if mostrar_lim:
		fila_base.append({"cat": "limite", "texto": "Área jugable"})

	var fila_lugares: Array[Dictionary] = [
		{"cat": "casa", "texto": "Casa"},
		{"cat": "tienda", "texto": "Tienda"},
		{"cat": "herreria", "texto": "Herrería"},
		{"cat": "taberna", "texto": "Taberna"},
		{"cat": "ayuntamiento", "texto": "Ayuntamiento"},
		{"cat": "mina", "texto": "Mina"},
	]

	var pad_x := 18.0
	var pad_y := 10.0
	var sep_item := 24.0
	var ancho_icono := 28.0
	var max_interior := max_ancho - pad_x * 2.0
	var filas_salida: Array[Array] = []
	var anchos_fila: Array[float] = []

	for grupo_items in [fila_base, fila_lugares]:
		var actual: Array[Dictionary] = []
		var w_actual := 0.0
		for it: Dictionary in grupo_items:
			var w_txt := fuente.get_string_size(String(it["texto"]), HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
			var w_item := ancho_icono + w_txt
			it["ancho"] = w_item
			var extra := sep_item if not actual.is_empty() else 0.0
			if not actual.is_empty() and w_actual + extra + w_item > max_interior:
				filas_salida.append(actual)
				anchos_fila.append(w_actual)
				actual = [it]
				w_actual = w_item
			else:
				actual.append(it)
				w_actual += extra + w_item
		if not actual.is_empty():
			filas_salida.append(actual)
			anchos_fila.append(w_actual)

	var w_max := 0.0
	for wf in anchos_fila:
		w_max = maxf(w_max, wf)
	var alto_fila := maxf(fuente.get_height(tam), 24.0)
	var sep_fila := 8.0
	var caja_w := minf(max_ancho, w_max + pad_x * 2.0)
	var caja_h := pad_y * 2.0 + float(filas_salida.size()) * alto_fila + float(maxi(filas_salida.size() - 1, 0)) * sep_fila
	var bottom_hint := 18.0
	var alto_hint := fuente.get_height(tam_hint)
	var caja_y := size.y - bottom_hint - alto_hint - 10.0 - caja_h
	var caja_x := (size.x - caja_w) * 0.5
	var rect := Rect2(caja_x, caja_y, caja_w, caja_h)
	var margen_abajo := size.y - caja_y + MARGEN_LEYENDA_GAP

	return {
		"rect": rect,
		"filas": filas_salida,
		"anchos": anchos_fila,
		"tam": tam,
		"tam_hint": tam_hint,
		"alto_fila": alto_fila,
		"sep_fila": sep_fila,
		"sep_item": sep_item,
		"ancho_icono": ancho_icono,
		"pad_y": pad_y,
		"hint_y": size.y - bottom_hint - fuente.get_descent(tam_hint),
		"margen_abajo": margen_abajo,
	}


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_VELO)
	var fuente := Estilo.fuente()
	if minimapa == null or not minimapa.lista():
		draw_string(fuente, Vector2(0, size.y * 0.5), "Dibujando el mapa…", HORIZONTAL_ALIGNMENT_CENTER, size.x, Estilo.TAM_GRANDE, Estilo.COLOR_TEXTO)
		return

	var disp := calcular_disposicion()
	var area: Rect2 = disp["area"]
	var ley: Dictionary = disp["leyenda"]

	draw_rect(area.grow(10.0), Color(0.09, 0.07, 0.06, 0.96))
	draw_texture_rect(minimapa.textura, area, false)
	if minimapa.id_mapa == "mina_interior":
		var nm_n := minimapa.nivel_mina_actual()
		if nm_n != null and nm_n.has_method("textura_niebla_overlay"):
			var ov: Variant = nm_n.call("textura_niebla_overlay")
			if ov is Texture2D:
				draw_texture_rect(ov as Texture2D, area, false)
	draw_rect(area.grow(10.0), Estilo.COLOR_BORDE, false, 3.0)

	# Título superior y ayuda inferior.
	var tam_titulo := roundi(float(Estilo.TAM_TITULO) * minf(_escala_texto(), 1.15))
	_texto_con_borde(fuente, Vector2(0, 56.0), minimapa.nombre_mapa, HORIZONTAL_ALIGNMENT_CENTER, size.x, tam_titulo, Estilo.COLOR_ACENTO, false)

	var texto_ayuda := Ajustes.pista("mapa") + "  ·  " + ("B" if Ajustes.ultimo_mando else "Esc") + "   cerrar el mapa"
	_texto_con_borde(fuente, Vector2(0, float(ley["hint_y"])), texto_ayuda, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(ley["tam_hint"]), Estilo.COLOR_TEXTO_SUAVE, false)

	# Borde del área jugable.
	var poligono := LimitesMapa.poligono(minimapa.id_mapa) if LimitesMapa.mostrar_borde(minimapa.id_mapa) else PackedVector2Array()
	if poligono.size() >= 3:
		var pts := PackedVector2Array()
		for p in poligono:
			pts.append(mundo_a_pantalla(p))
		pts.append(pts[0])
		draw_polyline(pts, Minimapa.COLOR_CONTORNO, 5.0, true)
		draw_polyline(pts, Minimapa.COLOR_LIMITE, 2.5, true)

	# Vecinos (debajo de marcadores y etiquetas principales).
	for q: Vector2 in disp["vecinos"]:
		_dibujar_icono("vecino", q, 6.0)

	# Edificios y salidas.
	for m: Dictionary in disp["marcadores"]:
		if String(m["categoria"]) == "leo":
			continue
		_dibujar_icono(String(m["categoria"]), m["pos"] as Vector2, 11.0)

	# Leo con marcador direccional claro.
	for m: Dictionary in disp["marcadores"]:
		if String(m["categoria"]) == "leo":
			_dibujar_icono("leo", m["pos"] as Vector2, 16.0, m.get("dir", Vector2(0, -1)) as Vector2)

	# Norte (encima de un disco oscuro sutil para que se lea sobre cualquier terreno).
	var np: Vector2 = disp["norte"]
	draw_circle(np + Vector2(0.0, 2.0), 21.0, Color(0.06, 0.05, 0.04, 0.82))
	draw_arc(np + Vector2(0.0, 2.0), 21.0, 0.0, TAU, 32, Estilo.COLOR_BORDE_SUAVE, 1.5, true)
	draw_colored_polygon(PackedVector2Array([np + Vector2(0, -16), np + Vector2(7.5, 4), np + Vector2(-7.5, 4)]), Estilo.COLOR_ACENTO)
	_texto_con_borde(fuente, np + Vector2(-6.0, 20.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Estilo.COLOR_ACENTO, false)

	# Líneas guía de las etiquetas desplazadas.
	for e: Dictionary in disp["etiquetas"]:
		if not bool(e.get("guia", false)):
			continue
		var r: Rect2 = e["rect"]
		var anchor: Vector2 = e["anchor"]
		var borde_p := _punto_mas_cercano_rect(anchor, r)
		draw_line(anchor, borde_p, Minimapa.COLOR_CONTORNO, 3.5, true)
		draw_line(anchor, borde_p, (e["borde"] as Color) * Color(1, 1, 1, 0.85), 1.6, true)

	# Etiquetas (pill oscuro con borde sutil + texto perfilado, nunca solapado).
	for e: Dictionary in disp["etiquetas"]:
		var r: Rect2 = e["rect"]
		var cat_e := String(e.get("categoria", ""))
		if not _estilos_etiqueta.has(cat_e):
			var col_borde := (e["borde"] as Color) * Color(1, 1, 1, 0.65)
			_estilos_etiqueta[cat_e] = Estilo.caja(Color(0.06, 0.05, 0.04, 0.88), col_borde, 1, 5, 0)
		draw_style_box(_estilos_etiqueta[cat_e] as StyleBoxFlat, r)
		var tam_e := int(e["tam"])
		var base_y := r.position.y + PILL_PAD_Y + fuente.get_ascent(tam_e)
		_texto_con_borde(fuente, Vector2(r.position.x + PILL_PAD_X, base_y), String(e["texto"]), HORIZONTAL_ALIGNMENT_LEFT, -1, tam_e, e["color"] as Color, false)

	# Leyenda en panel legible.
	_dibujar_leyenda(fuente, ley)


func _dibujar_leyenda(fuente: Font, ley: Dictionary) -> void:
	if _estilo_leyenda == null:
		_estilo_leyenda = Estilo.caja(Color(0.07, 0.055, 0.045, 0.95), Estilo.COLOR_BORDE, 2, 8, 12)
	var rect: Rect2 = ley["rect"]
	draw_style_box(_estilo_leyenda, rect)

	var tam := int(ley["tam"])
	var filas: Array = ley["filas"]
	var anchos: Array = ley["anchos"]
	var alto_fila := float(ley["alto_fila"])
	var sep_fila := float(ley["sep_fila"])
	var sep_item := float(ley["sep_item"])
	var ancho_icono := float(ley["ancho_icono"])
	var y_top := rect.position.y + float(ley["pad_y"])
	var asc := fuente.get_ascent(tam)
	var color_txt := Color.WHITE if Ajustes.valores.alto_contraste else Estilo.COLOR_TEXTO

	for i in filas.size():
		var fila: Array = filas[i]
		var w_fila := float(anchos[i])
		var x := rect.position.x + (rect.size.x - w_fila) * 0.5
		var y_centro := y_top + alto_fila * 0.5
		var y_base := y_top + (alto_fila - fuente.get_height(tam)) * 0.5 + asc
		for item: Dictionary in fila:
			var cat := String(item["cat"])
			_dibujar_icono(cat, Vector2(x + ancho_icono * 0.42, y_centro), 9.0, Vector2(0, -1))
			_texto_con_borde(fuente, Vector2(x + ancho_icono, y_base), String(item["texto"]), HORIZONTAL_ALIGNMENT_LEFT, -1, tam, color_txt, false)
			x += float(item["ancho"]) + sep_item
		y_top += alto_fila + sep_fila


func _dibujar_icono(cat: String, q: Vector2, r: float, dir: Vector2 = Vector2(0, -1)) -> void:
	match cat:
		"leo":
			var d := dir.normalized() if dir.length_squared() > 0.001 else Vector2(0, -1)
			var ang := atan2(d.x, -d.y)
			draw_circle(q, r * 1.15, Color(1.0, 0.90, 0.35, 0.24))
			draw_arc(q, r * 1.05, 0.0, TAU, 28, Color(1.0, 0.93, 0.55, 0.85), 1.6, true)
			draw_set_transform(q, ang)
			var s := r / 14.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -18.0 * s), Vector2(12.5 * s, 13.0 * s), Vector2(0, 6.0 * s), Vector2(-12.5 * s, 13.0 * s)
			]), Minimapa.COLOR_CONTORNO)
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -14.5 * s), Vector2(9.2 * s, 10.0 * s), Vector2(0, 4.0 * s), Vector2(-9.2 * s, 10.0 * s)
			]), Minimapa.COLOR_LEO)
			draw_line(Vector2(0, 3.0 * s), Vector2(0, -11.5 * s), Color(1.0, 0.99, 0.88), maxf(1.6, 2.2 * s), true)
			draw_set_transform(Vector2.ZERO, 0.0)
		"vecino":
			draw_circle(q, r + 2.0, Minimapa.COLOR_CONTORNO)
			draw_circle(q, r, Minimapa.COLOR_NPC)
		"limite":
			draw_line(q - Vector2(r * 1.1, 0), q + Vector2(r * 1.1, 0), Minimapa.COLOR_CONTORNO, 5.0)
			draw_line(q - Vector2(r * 1.1, 0), q + Vector2(r * 1.1, 0), Minimapa.COLOR_LIMITE, 2.5)
		"casa", "casita":
			var col := COLOR_CASA if cat == "casa" else COLOR_CASITA
			var t := r * (1.0 if cat == "casa" else 0.88)
			draw_circle(q, t + 2.5, Minimapa.COLOR_CONTORNO)
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(0, -t), q + Vector2(t * 0.95, -t * 0.05), q + Vector2(-t * 0.95, -t * 0.05)
			]), col.lightened(0.15))
			draw_rect(Rect2(q + Vector2(-t * 0.65, -t * 0.08), Vector2(t * 1.3, t * 0.88)), col)
			draw_rect(Rect2(q + Vector2(-t * 0.18, t * 0.28), Vector2(t * 0.36, t * 0.52)), Minimapa.COLOR_CONTORNO)
		"tienda":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			draw_rect(Rect2(q + Vector2(-r * 0.68, -r * 0.12), Vector2(r * 1.36, r * 0.88)), COLOR_TIENDA.darkened(0.12))
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(-r * 0.92, -r * 0.12), q + Vector2(-r * 0.65, -r * 0.82),
				q + Vector2(r * 0.65, -r * 0.82), q + Vector2(r * 0.92, -r * 0.12)
			]), COLOR_TIENDA.lightened(0.2))
			draw_rect(Rect2(q + Vector2(-r * 0.25, r * 0.18), Vector2(r * 0.5, r * 0.45)), Color(1.0, 0.96, 0.82))
		"herreria":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			# Yunque de herrero.
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(-r * 0.92, -r * 0.42), q + Vector2(r * 0.72, -r * 0.42),
				q + Vector2(r * 0.92, -r * 0.10), q + Vector2(r * 0.35, -r * 0.02),
				q + Vector2(r * 0.35, r * 0.42), q + Vector2(r * 0.68, r * 0.72),
				q + Vector2(-r * 0.68, r * 0.72), q + Vector2(-r * 0.35, r * 0.42),
				q + Vector2(-r * 0.35, -r * 0.05)
			]), COLOR_HERRERIA)
		"taberna":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			# Jarra con asa.
			draw_rect(Rect2(q + Vector2(-r * 0.55, -r * 0.55), Vector2(r * 0.9, r * 1.2)), COLOR_TABERNA)
			draw_rect(Rect2(q + Vector2(-r * 0.6, -r * 0.78), Vector2(r * 1.0, r * 0.28)), Color(0.98, 0.94, 0.82))
			draw_arc(q + Vector2(r * 0.38, r * 0.02), r * 0.34, -PI * 0.5, PI * 0.5, 10, COLOR_TABERNA, maxf(1.8, r * 0.22), true)
		"ayuntamiento":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			# Frontón y columnas.
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(0, -r * 0.92), q + Vector2(r * 0.88, -r * 0.25), q + Vector2(-r * 0.88, -r * 0.25)
			]), Estilo.COLOR_ACENTO)
			for ox in [-0.52, 0.0, 0.52]:
				draw_rect(Rect2(q + Vector2(r * ox - r * 0.12, -r * 0.22), Vector2(r * 0.24, r * 0.78)), COLOR_AYUNTAMIENTO)
			draw_rect(Rect2(q + Vector2(-r * 0.84, r * 0.54), Vector2(r * 1.68, r * 0.26)), COLOR_AYUNTAMIENTO.lightened(0.2))
		"mina":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			# Boca de galería con arco.
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(-r * 0.85, r * 0.68), q + Vector2(-r * 0.78, -r * 0.32),
				q + Vector2(-r * 0.35, -r * 0.78), q + Vector2(r * 0.35, -r * 0.78),
				q + Vector2(r * 0.78, -r * 0.32), q + Vector2(r * 0.85, r * 0.68)
			]), COLOR_MINA)
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(-r * 0.48, r * 0.68), q + Vector2(-r * 0.42, -r * 0.15),
				q + Vector2(0, -r * 0.45), q + Vector2(r * 0.42, -r * 0.15),
				q + Vector2(r * 0.48, r * 0.68)
			]), Color(0.07, 0.06, 0.05))
		"capilla":
			draw_circle(q, r + 2.5, Minimapa.COLOR_CONTORNO)
			draw_colored_polygon(PackedVector2Array([
				q + Vector2(0, -r * 0.95), q + Vector2(r * 0.72, -r * 0.05), q + Vector2(-r * 0.72, -r * 0.05)
			]), COLOR_CAPILLA.lightened(0.15))
			draw_rect(Rect2(q + Vector2(-r * 0.52, -r * 0.08), Vector2(r * 1.04, r * 0.82)), COLOR_CAPILLA)
		"puerta":
			_rombo(q, r * 0.82, Minimapa.COLOR_PUERTA)
		"mirador":
			_rombo(q, r * 0.90, COLOR_MIRADOR)
		"pesca":
			draw_circle(q, r + 2.0, Minimapa.COLOR_CONTORNO)
			draw_circle(q, r * 0.85, COLOR_PESCA)
		_:
			_rombo(q, r * 0.82, Minimapa.COLOR_SALIDA)


func _mapa_actual_para_puntos() -> Node3D:
	return get_tree().get_first_node_in_group("mapa") as Node3D if is_inside_tree() else null


func _rombo(q: Vector2, t: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([q + Vector2(0, -t - 2), q + Vector2(t + 2, 0), q + Vector2(0, t + 2), q + Vector2(-t - 2, 0)]), Minimapa.COLOR_CONTORNO)
	draw_colored_polygon(PackedVector2Array([q + Vector2(0, -t), q + Vector2(t, 0), q + Vector2(0, t), q + Vector2(-t, 0)]), color)


func _texto_con_borde(fuente: Font, pos: Vector2, texto: String, alin: HorizontalAlignment, ancho: float, tam: int, color: Color, escalar: bool = true) -> void:
	if escalar:
		tam = roundi(float(tam) * _escala_texto())
	if Ajustes.valores.alto_contraste:
		color = Color.WHITE
	draw_string_outline(fuente, pos, texto, alin, ancho, tam, 6, Color(0, 0, 0, 0.92))
	draw_string(fuente, pos, texto, alin, ancho, tam, color)
