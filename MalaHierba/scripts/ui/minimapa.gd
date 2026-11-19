class_name Minimapa
extends Control
## Minimapa redondo de la esquina superior izquierda: una foto cenital del mapa (FotoCenital, una vez por mapa) que se
## recorta en un círculo centrado en Leo y GIRA con la cámara (arriba = hacia donde mira la cámara). Encima: el borde
## del área jugable, una flecha para Leo (hacia donde mira), puntos para los vecinos (grupo «npc»), rombos en las salidas
## y puertas (grupos «salida» y «puerta»; las que quedan fuera del círculo salen como flecha en el borde), una «N» que
## marca el norte y el nombre del mapa encima. El mapa grande (MapaGrande, tecla M) reutiliza su foto y su rectángulo.
## Se prepara solo al cargarse un mapa (señal Escenas.mapa_cargado).

const DIAMETRO := 220.0
const ALTO_NOMBRE := 30.0
const RADIO_MUNDO := 21.0          # metros desde Leo hasta el borde del círculo
const SEGMENTOS := 72
const COLOR_FONDO := Color(0.07, 0.06, 0.05, 0.92)
const COLOR_ANILLO := Color(0.86, 0.62, 0.30)
const COLOR_LIMITE := Color(1.0, 0.86, 0.5, 0.85)
const COLOR_LEO := Color(1.0, 0.93, 0.55)
const COLOR_NPC := Color(0.55, 0.82, 1.0)
const COLOR_SALIDA := Color(1.0, 0.72, 0.22)
const COLOR_PUERTA := Color(0.9, 0.55, 0.3)
const COLOR_CONTORNO := Color(0.05, 0.04, 0.03, 0.95)
const LADO_FOTO := 1024

const SHADER_FOTO := "shader_type canvas_item;
uniform vec4 fuera : source_color = vec4(0.06, 0.05, 0.045, 1.0);
uniform float usar_niebla = 0.0;
uniform sampler2D tex_niebla : filter_linear;
uniform vec4 color_niebla : source_color = vec4(0.045, 0.045, 0.060, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) {
		c = fuera;
	} else if (usar_niebla > 0.5) {
		float vis = texture(tex_niebla, UV).r;
		c.rgb = mix(color_niebla.rgb, c.rgb, vis);
	}
	COLOR = c;
}
"

## Foto cenital del mapa actual (arriba de la imagen = −Z, derecha = +X); null hasta que se genera.
var textura: Texture2D = null
## Zona del mundo (x, z) que cubre la foto.
var rect_mundo: Rect2 = Rect2()
var id_mapa: String = ""
var nombre_mapa: String = ""
## Milisegundos que tardó la última foto.
var generado_ms: int = 0
## Cuántas veces se ha generado una foto (las pruebas lo miran).
var fotos_hechas: int = 0
var jugador: Node3D = null
var camara: CamaraJuego = null

var _fondo: Control
var _marcas: Control
var _l_nombre: Label
var _l_norte: Label
var _poligono: PackedVector2Array = PackedVector2Array()
var _mapa_actual: Node3D = null
var _mat_foto: ShaderMaterial = null
var _nivel_mina: Node3D = null
var _dir_circulo: PackedVector2Array = PackedVector2Array()
var _segs_poligono: PackedVector2Array = PackedVector2Array()
var _salidas_cache: Array[Node3D] = []
var _puertas_cache: Array[Node3D] = []
var _ult_pos: Vector2 = Vector2.INF
var _ult_yaw: float = NAN
var _ult_dir: Vector2 = Vector2.INF
var _ult_tex: Texture2D = null
var _t_refresco: float = 0.0
var _sucio: bool = true


func limpiar() -> void:
	textura = null
	id_mapa = ""
	nombre_mapa = ""
	jugador = null
	camara = null
	_mapa_actual = null
	_nivel_mina = null
	_poligono = PackedVector2Array()
	_segs_poligono = PackedVector2Array()
	_salidas_cache.clear()
	_puertas_cache.clear()
	_ult_pos = Vector2.INF
	_ult_yaw = NAN
	_ult_dir = Vector2.INF
	_ult_tex = null
	_t_refresco = 0.0
	_sucio = true


## Capa que dibuja solo la foto (lleva el shader que deja oscuro lo que cae fuera de la imagen).
class CapaFoto extends Control:
	var dueno: Minimapa

	func _draw() -> void:
		if dueno != null:
			dueno._dibujar_foto(self)


## Capa que dibuja el aro, los límites y las marcas.
class CapaMarcas extends Control:
	var dueno: Minimapa

	func _draw() -> void:
		if dueno != null:
			dueno._dibujar_marcas(self)


func _init() -> void:
	custom_minimum_size = Vector2(DIAMETRO, DIAMETRO + ALTO_NOMBRE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_dir_circulo.resize(SEGMENTOS)
	for i in SEGMENTOS:
		var a := TAU * float(i) / float(SEGMENTOS)
		_dir_circulo[i] = Vector2(cos(a), sin(a))
	_l_nombre = Estilo.etiqueta("", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO)
	_l_nombre.position = Vector2(0, 0)
	_l_nombre.size = Vector2(DIAMETRO, ALTO_NOMBRE)
	_l_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_nombre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_l_nombre.add_theme_constant_override("outline_size", 6)
	_l_nombre.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_l_nombre)

	_fondo = CapaFoto.new()
	_fondo.dueno = self
	_fondo.name = "Foto"
	_fondo.position = Vector2.ZERO
	_fondo.size = Vector2(DIAMETRO, DIAMETRO + ALTO_NOMBRE)
	_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fondo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var sh := Shader.new()
	sh.code = SHADER_FOTO
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mat_foto = mat
	_fondo.material = mat
	add_child(_fondo)

	_marcas = CapaMarcas.new()
	_marcas.dueno = self
	_marcas.name = "Marcas"
	_marcas.size = Vector2(DIAMETRO, DIAMETRO + ALTO_NOMBRE)
	_marcas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marcas)

	_l_norte = Estilo.etiqueta("N", Estilo.TAM_PEQUENO, Color(1.0, 0.95, 0.8))
	_l_norte.add_theme_constant_override("outline_size", 5)
	_l_norte.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_l_norte.size = Vector2(20, 22)
	_l_norte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_l_norte)

	Escenas.mapa_cargado.connect(_al_mapa_cargado)
	# Si ya hay un mapa en marcha (el HUD se creó después), se prepara con él.
	var m := Escenas.mapa_actual_nodo()
	if m != null and Escenas.jugador() != null:
		_al_mapa_cargado(str(m.get("id_mapa")))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _mat_foto != null:
		var tex_n: Variant = _nivel_mina.call("textura_niebla") if (id_mapa == "mina_interior" and _nivel_mina != null and is_instance_valid(_nivel_mina) and _nivel_mina.has_method("textura_niebla")) else null
		if tex_n is Texture2D:
			_mat_foto.set_shader_parameter("usar_niebla", 1.0)
			_mat_foto.set_shader_parameter("tex_niebla", tex_n)
		else:
			_mat_foto.set_shader_parameter("usar_niebla", 0.0)
	_t_refresco += delta
	var pos_actual := _pos_jugador()
	var yaw_actual := _yaw()
	var dir_actual := Vector2(0, -1)
	if jugador != null and is_instance_valid(jugador):
		var d3: Variant = jugador.get("direccion")
		if d3 is Vector3:
			dir_actual = Vector2((d3 as Vector3).x, (d3 as Vector3).z)
	var cambio := _sucio or textura != _ult_tex or _ult_pos == Vector2.INF or pos_actual.distance_squared_to(_ult_pos) > 0.0004 or is_nan(_ult_yaw) or absf(yaw_actual - _ult_yaw) > 0.002 or dir_actual.distance_squared_to(_ult_dir) > 0.0004 or _t_refresco >= 0.10
	if not cambio:
		return
	_ult_tex = textura
	_ult_pos = pos_actual
	_ult_yaw = yaw_actual
	_ult_dir = dir_actual
	_t_refresco = 0.0
	_sucio = false
	_poner_norte()
	_fondo.queue_redraw()
	_marcas.queue_redraw()


func nivel_mina_actual() -> Node3D:
	return _nivel_mina if is_instance_valid(_nivel_mina) else null


# --- Preparación ---------------------------------------------------------------------------------------

func _al_mapa_cargado(id: String) -> void:
	var mapa := Escenas.mapa_actual_nodo()
	if mapa == null:
		return
	_mapa_actual = mapa
	_nivel_mina = mapa.get_node_or_null("Objetos/NivelMina") as Node3D if id == "mina_interior" else null
	jugador = Escenas.jugador()
	camara = jugador.get("camara") as CamaraJuego if jugador != null else null
	id_mapa = id
	nombre_mapa = LimitesMapa.nombre(id)
	if id == "mina_interior":
		var nv := clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, 20)
		_l_nombre.text = "%s · Nv. %d" % [nombre_mapa, nv]
	else:
		_l_nombre.text = nombre_mapa
	_poligono = LimitesMapa.poligono(id) if LimitesMapa.mostrar_borde(id) else PackedVector2Array()
	_segs_poligono = PackedVector2Array()
	if _poligono.size() >= 3:
		var n_pol := _poligono.size()
		for i in n_pol:
			var a := _poligono[i]
			var b := _poligono[(i + 1) % n_pol]
			var largo := a.distance_to(b)
			var trozos := maxi(int(ceil(largo / 1.5)), 1)
			for k in trozos:
				_segs_poligono.append(a.lerp(b, float(k) / float(trozos)))
				_segs_poligono.append(a.lerp(b, float(k + 1) / float(trozos)))
	_salidas_cache.clear()
	_puertas_cache.clear()
	_sucio = true
	var rect := Rect2()
	if mapa.has_method("rect_mapa"):
		rect = mapa.call("rect_mapa")
	else:
		rect = LimitesMapa.rect(id, AABB(Vector3(-30, 0, -30), Vector3(60, 10, 60)))
	rect_mundo = rect
	textura = null
	var clave_foto := "%s_n%d" % [id, clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, 20)] if id == "mina_interior" else id
	_generar_foto_diferida.call_deferred(id, mapa, clave_foto, rect)


func _generar_foto_diferida(id: String, mapa: Node3D, clave_foto: String, rect: Rect2) -> void:
	if id != id_mapa or not is_instance_valid(mapa):
		return
	var foto := await FotoCenital.generar(mapa, clave_foto, rect, LADO_FOTO)
	if id != id_mapa:
		return      # mientras tanto se cambió de mapa
	textura = foto
	generado_ms = FotoCenital.ultimo_ms
	fotos_hechas += 1
	_sucio = true


## ¿Hay foto lista para dibujar?
func lista() -> bool:
	return textura != null and rect_mundo.size.x > 0.0 and rect_mundo.size.y > 0.0


# --- Geometría ------------------------------------------------------------------------------------------

func _yaw() -> float:
	return camara.yaw if camara != null else 0.0


func _adelante() -> Vector2:
	var y := _yaw()
	return Vector2(-sin(y), -cos(y))


func _derecha() -> Vector2:
	var y := _yaw()
	return Vector2(cos(y), -sin(y))


func _centro() -> Vector2:
	return Vector2(DIAMETRO * 0.5, ALTO_NOMBRE + DIAMETRO * 0.5)


func _radio_pantalla() -> float:
	return DIAMETRO * 0.5 - 4.0


func _escala() -> float:
	var r_mundo := RADIO_MUNDO
	if rect_mundo.size.x > 0.0 and maxf(rect_mundo.size.x, rect_mundo.size.y) < 25.0:
		r_mundo = clampf(maxf(rect_mundo.size.x, rect_mundo.size.y) * 0.65, 7.0, RADIO_MUNDO)
	return _radio_pantalla() / r_mundo


func _pos_jugador() -> Vector2:
	if jugador == null or not is_instance_valid(jugador):
		return rect_mundo.get_center()
	return Vector2(jugador.global_position.x, jugador.global_position.z)


## Punto del mundo (x, z) → posición dentro del control (el centro es Leo y arriba es hacia donde mira la cámara).
func mundo_a_pantalla(p: Vector2) -> Vector2:
	var d := p - _pos_jugador()
	return _centro() + Vector2(d.dot(_derecha()), -d.dot(_adelante())) * _escala()


## Lo inverso: posición del control → punto del mundo (x, z).
func pantalla_a_mundo(q: Vector2) -> Vector2:
	var o := (q - _centro()) / _escala()
	return _pos_jugador() + _derecha() * o.x - _adelante() * o.y


func _uv(p: Vector2) -> Vector2:
	return Vector2((p.x - rect_mundo.position.x) / rect_mundo.size.x, (p.y - rect_mundo.position.y) / rect_mundo.size.y)


## UV del punto del mundo en la foto (0..1 dentro de ella).
func uv_de(p: Vector2) -> Vector2:
	return _uv(p)


# --- Dibujo ------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_circle(_centro(), _radio_pantalla() + 3.0, COLOR_FONDO)


func _dibujar_foto(c: Control) -> void:
	if not lista():
		return
	var puntos := PackedVector2Array()
	var colores := PackedColorArray()
	var uvs := PackedVector2Array()
	puntos.resize(SEGMENTOS)
	colores.resize(SEGMENTOS)
	uvs.resize(SEGMENTOS)
	var centro := _centro()
	var r := _radio_pantalla()
	for i in SEGMENTOS:
		var q := centro + _dir_circulo[i] * r
		puntos[i] = q
		colores[i] = Color.WHITE
		uvs[i] = _uv(pantalla_a_mundo(q))
	c.draw_polygon(puntos, colores, uvs, textura)


func _dibujar_marcas(c: Control) -> void:
	var centro := _centro()
	var r := _radio_pantalla()
	var r_lim := r - 1.0
	# Borde del área jugable.
	if not _segs_poligono.is_empty():
		var lineas := PackedVector2Array()
		for i in range(0, _segs_poligono.size(), 2):
			var p0 := mundo_a_pantalla(_segs_poligono[i])
			var p1 := mundo_a_pantalla(_segs_poligono[i + 1])
			if p0.distance_to(centro) < r_lim and p1.distance_to(centro) < r_lim:
				lineas.append(p0)
				lineas.append(p1)
		if not lineas.is_empty():
			c.draw_multiline(lineas, COLOR_LIMITE, 2.0)
	# Salidas y puertas.
	if is_inside_tree():
		if _salidas_cache.is_empty():
			for n3: Node in get_tree().get_nodes_in_group("salida"):
				if n3 is Node3D:
					_salidas_cache.append(n3 as Node3D)
		if _puertas_cache.is_empty():
			for n3: Node in get_tree().get_nodes_in_group("puerta"):
				if n3 is Node3D:
					_puertas_cache.append(n3 as Node3D)
		for par_grupo: Array in [[_salidas_cache, COLOR_SALIDA], [_puertas_cache, COLOR_PUERTA]]:
			var lista_nodos: Array[Node3D] = par_grupo[0]
			var color: Color = par_grupo[1]
			for nodo: Node3D in lista_nodos:
				if not is_instance_valid(nodo) or not nodo.is_inside_tree():
					continue
				if id_mapa == "mina_interior" and _nivel_mina != null and is_instance_valid(_nivel_mina) and _nivel_mina.has_method("es_punto_explorado"):
					if not bool(_nivel_mina.call("es_punto_explorado", Vector2(nodo.global_position.x, nodo.global_position.z))):
						continue
				var q := mundo_a_pantalla(Vector2(nodo.global_position.x, nodo.global_position.z))
				if q.distance_to(centro) <= r - 7.0:
					_rombo(c, q, 7.0, color)
				else:
					_flecha_borde(c, q, color)
		# Vecinos.
		for n3: Node in get_tree().get_nodes_in_group("npc"):
			var nodo := n3 as Node3D
			if nodo == null or not nodo.is_inside_tree() or not nodo.visible:
				continue
			var q := mundo_a_pantalla(Vector2(nodo.global_position.x, nodo.global_position.z))
			if q.distance_to(centro) <= r - 5.0:
				c.draw_circle(q, 5.5, COLOR_CONTORNO)
				c.draw_circle(q, 3.8, COLOR_NPC)
	# Leo.
	var dir := Vector2(0, -1)
	if jugador != null and is_instance_valid(jugador):
		var d3: Variant = jugador.get("direccion")
		if d3 is Vector3:
			dir = Vector2((d3 as Vector3).x, (d3 as Vector3).z)
	var ang := atan2(dir.dot(_derecha()), dir.dot(_adelante()))
	c.draw_set_transform(centro, ang)
	var flecha := PackedVector2Array([Vector2(0, -11), Vector2(7.5, 8), Vector2(0, 3.5), Vector2(-7.5, 8)])
	var contorno := PackedVector2Array([Vector2(0, -13.5), Vector2(10, 10.5), Vector2(0, 5), Vector2(-10, 10.5)])
	c.draw_colored_polygon(contorno, COLOR_CONTORNO)
	c.draw_colored_polygon(flecha, COLOR_LEO)
	c.draw_set_transform(Vector2.ZERO, 0.0)
	# Aro.
	c.draw_arc(centro, r + 1.5, 0.0, TAU, 96, COLOR_CONTORNO, 5.0, true)
	c.draw_arc(centro, r + 1.5, 0.0, TAU, 96, COLOR_ANILLO, 3.0, true)


func _rombo(c: Control, q: Vector2, t: float, color: Color) -> void:
	var fuera := PackedVector2Array([q + Vector2(0, -t - 2), q + Vector2(t + 2, 0), q + Vector2(0, t + 2), q + Vector2(-t - 2, 0)])
	var dentro := PackedVector2Array([q + Vector2(0, -t), q + Vector2(t, 0), q + Vector2(0, t), q + Vector2(-t, 0)])
	c.draw_colored_polygon(fuera, COLOR_CONTORNO)
	c.draw_colored_polygon(dentro, color)


## Flecha pegada al borde del círculo que apunta hacia una salida que queda lejos.
func _flecha_borde(c: Control, q: Vector2, color: Color) -> void:
	var centro := _centro()
	var v := (q - centro).normalized()
	var base := centro + v * (_radio_pantalla() - 9.0)
	var perp := Vector2(-v.y, v.x)
	var pts := PackedVector2Array([base + v * 8.0, base - v * 5.0 + perp * 6.5, base - v * 5.0 - perp * 6.5])
	var gran := PackedVector2Array([base + v * 11.0, base - v * 7.5 + perp * 9.5, base - v * 7.5 - perp * 9.5])
	c.draw_colored_polygon(gran, COLOR_CONTORNO)
	c.draw_colored_polygon(pts, color)


## La «N» se pega al borde del círculo en la dirección del norte (−Z) y gira con la cámara.
func _poner_norte() -> void:
	var norte := Vector2(0, -1)
	var v := Vector2(norte.dot(_derecha()), -norte.dot(_adelante()))
	var p := _centro() + v * (_radio_pantalla() - 12.0)
	_l_norte.position = p - _l_norte.size * 0.5


## Posición (en el control) de la «N», para las pruebas.
func posicion_norte() -> Vector2:
	return _l_norte.position + _l_norte.size * 0.5
