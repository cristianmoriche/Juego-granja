class_name Resaltador
extends Node3D
## Marca el objeto con el que Leo puede interactuar: anillo en el suelo, flecha que flota y se mece sobre él,
## nombre flotante (vecinos) y un brillo suave y aditivo en sus mallas, si las tiene.
## Lo crea jugador.gd (uno por jugador) y le dice `apuntar(nodo)` al cambiar de objetivo; `apuntar(null)` lo apaga.

const COLOR := Color(1.0, 0.82, 0.38)
const BRILLO_BAJO := 0.10
const BRILLO_ALTO := 0.26

var objetivo: Node3D = null
var primera_persona: bool = false

var _anillo: MeshInstance3D
var _flecha: Sprite3D
var _nombre: Label3D
var _mat_brillo: StandardMaterial3D
var _mat_anillo: StandardMaterial3D
var _mallas: Array[MeshInstance3D] = []
var _previos: Dictionary = {}
var _t: float = 0.0
var _radio: float = 0.8


func _ready() -> void:
	top_level = true
	visible = false

	var toro := TorusMesh.new()
	toro.inner_radius = 0.84
	toro.outer_radius = 1.0
	toro.rings = 36
	toro.ring_segments = 6
	_mat_anillo = StandardMaterial3D.new()
	_mat_anillo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_anillo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_anillo.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.85)
	toro.material = _mat_anillo
	_anillo = MeshInstance3D.new()
	_anillo.name = "Anillo"
	_anillo.mesh = toro
	_anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_anillo)

	_flecha = Sprite3D.new()
	_flecha.name = "Flecha"
	_flecha.texture = _textura_flecha()
	_flecha.pixel_size = 0.0058
	_flecha.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flecha.shaded = false
	_flecha.no_depth_test = false
	_flecha.render_priority = 10
	_flecha.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flecha)

	_nombre = Label3D.new()
	_nombre.name = "Nombre"
	_nombre.font = Estilo.fuente()
	_nombre.font_size = 44
	_nombre.pixel_size = 0.0065
	_nombre.outline_size = 14
	_nombre.modulate = Color(1.0, 0.96, 0.85)
	_nombre.outline_modulate = Color(0, 0, 0, 0.9)
	_nombre.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nombre.no_depth_test = false
	_nombre.render_priority = 11
	add_child(_nombre)

	_mat_brillo = StandardMaterial3D.new()
	_mat_brillo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_brillo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_brillo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_brillo.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_brillo.albedo_color = Color(COLOR.r * BRILLO_BAJO, COLOR.g * BRILLO_BAJO, COLOR.b * BRILLO_BAJO, 1.0)


func _exit_tree() -> void:
	_quitar_brillo()


## Pone la marca sobre `nodo` (o la apaga con null).
func apuntar(nodo: Node3D) -> void:
	if nodo == objetivo:
		return
	_quitar_brillo()
	objetivo = nodo
	visible = nodo != null
	if nodo == null:
		return
	var r: Variant = nodo.get("radio")
	_radio = clampf(float(r) if r != null else 0.8, 0.35, 6.0)
	var rr := _radio + 0.25
	_anillo.scale = Vector3(rr, 0.12, rr)
	var texto := ""
	if nodo.has_method("nombre_resaltado"):
		texto = str(nodo.call("nombre_resaltado"))
	_nombre.text = texto
	_nombre.visible = not texto.is_empty()
	var raiz: Node3D = nodo
	if nodo.has_method("nodo_resaltado"):
		raiz = nodo.call("nodo_resaltado") as Node3D
	var permitido: Variant = nodo.get("resaltar_mallas")
	if raiz != null and (permitido == null or bool(permitido)):
		var candidatas: Array[Node] = []
		if raiz is MeshInstance3D:
			candidatas.append(raiz)
		candidatas.append_array(raiz.find_children("*", "MeshInstance3D", true, false))
		for m: Node in candidatas:
			var mi := m as MeshInstance3D
			if mi != null and mi.visible and not is_ancestor_of(mi) and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				_mallas.append(mi)
				_previos[mi] = mi.material_overlay
				mi.material_overlay = _mat_brillo
	_colocar(0.0)


func _quitar_brillo() -> void:
	for mi in _mallas:
		if is_instance_valid(mi):
			mi.material_overlay = _previos.get(mi)
	_mallas.clear()
	_previos.clear()


func _process(delta: float) -> void:
	if objetivo == null:
		return
	if not is_instance_valid(objetivo) or not objetivo.is_inside_tree():
		apuntar(null)
		return
	if not Ajustes.valores.reducir_movimiento:
		_t += delta
	_colocar(_t)


func _colocar(t: float) -> void:
	var base := objetivo.global_position
	global_position = base
	_anillo.visible = not primera_persona
	_flecha.visible = not primera_persona
	_nombre.visible = not primera_persona and not _nombre.text.is_empty()
	_anillo.position = Vector3(0, 0.2, 0)
	var pulso := 0.5 + 0.5 * sin(t * 4.0)
	_mat_anillo.albedo_color.a = 0.55 + 0.35 * pulso
	_anillo.scale = Vector3((_radio + 0.25) * (1.0 + 0.04 * pulso), 0.12, (_radio + 0.25) * (1.0 + 0.04 * pulso))
	var marca := base + Vector3(0, 1.5, 0)
	if objetivo.has_method("punto_marca"):
		marca = objetivo.call("punto_marca")
	var mece := 0.07 * sin(t * 3.2)
	_flecha.global_position = marca + Vector3(0, mece, 0)
	_nombre.global_position = marca + Vector3(0, 0.42 + mece, 0)
	var k := BRILLO_BAJO + (BRILLO_ALTO - BRILLO_BAJO) * pulso
	_mat_brillo.albedo_color = Color(COLOR.r * k, COLOR.g * k, COLOR.b * k, 1.0)


## Flecha hacia abajo de 64×64 con borde oscuro, dibujada en código.
static func _textura_flecha() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(4, 62):
		var f := float(62 - y) / 58.0
		var medio := f * 27.0
		for x in range(n):
			var dx := absf(float(x) - 31.5)
			if dx <= medio:
				var c := COLOR
				if dx > medio - 4.5 or y < 9:
					c = Color(0.18, 0.12, 0.05)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
