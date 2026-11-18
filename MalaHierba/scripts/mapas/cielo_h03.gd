class_name CieloH03
extends RefCounted
## Mezcla panoramas lineales en la esfera, registrados a partir de la luminaria de cada toma.

const RAIZ := "res://assets/hdri/h03/"
const SHADER_CIELO := preload("res://shaders/cielo_h03.gdshader")
const HDRI := [
	["qwantani_night_puresky", Vector4(0.600, 0.220, 0.047, 0.0)],
	["qwantani_dawn_puresky", Vector4(0.597, 0.454, 0.20, 0.0)],
	["qwantani_sunrise_puresky", Vector4(0.600, 0.488, 0.28, 0.70)],
	["qwantani_morning_puresky", Vector4(0.600, 0.388, 0.78, 1.0)],
	["qwantani_noon_puresky", Vector4(0.600, 0.223, 1.82, 1.0)],
	["qwantani_afternoon_puresky", Vector4(0.600, 0.273, 1.75, 1.0)],
	["qwantani_late_afternoon_puresky", Vector4(0.600, 0.394, 0.62, 1.0)],
	["qwantani_sunset_puresky", Vector4(0.600, 0.466, 0.44, 1.0)],
	["qwantani_dusk_2_puresky", Vector4(0.604, 0.412, 0.21, 0.0)],
	["qwantani_moonrise_puresky", Vector4(0.601, 0.423, 0.093, 0.8)],
]
const CUBIERTO := "kloofendal_overcast_puresky"
const NEBLINA := "kloofendal_misty_morning_puresky"

var material: ShaderMaterial
var _a := -1
var _b := -1
var _clima := ""


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER_CIELO


static func ruta(nombre: String) -> String:
	return RAIZ + nombre + "_4k.hdr"


static func tramo(minuto: float, sale: float, ocaso: float) -> Vector3:
	var dia := ocaso - sale
	var hitos := PackedFloat32Array([sale - 110.0, sale - 38.0, sale + 9.0, sale + dia * 0.20,
		sale + dia * 0.47, sale + dia * 0.65, sale + dia * 0.84, ocaso - 4.0, ocaso + 34.0, ocaso + 88.0, ocaso + 161.0])
	for i in range(1, hitos.size()):
		if minuto < hitos[i]:
			return Vector3(i - 1, i % HDRI.size(), smoothstep(hitos[i - 1], hitos[i], minuto))
	return Vector3.ZERO


static func solicitar_hora(minuto: float, sale: float, ocaso: float) -> void:
	var t := tramo(minuto, sale, ocaso)
	for indice in [int(t.x), int(t.y)]:
		CargadorMapa.solicitar_recurso(ruta(HDRI[indice][0]))
	if Juego.esta_lloviendo() or Juego.esta_nevando():
		CargadorMapa.solicitar_recurso(ruta(CUBIERTO))
	elif Juego.intensidad_neblina(sale) > 0.001:
		CargadorMapa.solicitar_recurso(ruta(NEBLINA))


func actualizar(minuto: float, sale: float, ocaso: float, fuerza: float, astro: Vector3,
		color: Color, noche: float, lluvia: bool, tormenta: bool, nieve: bool, niebla: float) -> void:
	var t := tramo(minuto, sale, ocaso)
	var a := int(t.x)
	var b := int(t.y)
	if _a != a:
		material.set_shader_parameter("panorama_a", CargadorMapa.obtener_recurso(ruta(HDRI[a][0])))
		_a = a
	if _b != b:
		material.set_shader_parameter("panorama_b", CargadorMapa.obtener_recurso(ruta(HDRI[b][0])))
		_b = b
	if t.z > 0.85:
		CargadorMapa.solicitar_recurso(ruta(HDRI[(b + 1) % HDRI.size()][0]))
	var nubosidad := (0.98 if tormenta else 0.89) if lluvia else (0.57 if nieve else niebla)
	var tipo := CUBIERTO if lluvia or nieve else NEBLINA
	if nubosidad > 0.001 and _clima != tipo:
		material.set_shader_parameter("panorama_clima", CargadorMapa.obtener_recurso(ruta(tipo)))
		_clima = tipo
	var registro_a: Vector4 = HDRI[a][1]
	var registro_b: Vector4 = HDRI[b][1]
	registro_a.z *= fuerza
	registro_b.z *= fuerza
	material.set_shader_parameter("registro_a", registro_a)
	material.set_shader_parameter("registro_b", registro_b)
	material.set_shader_parameter("transicion", t.z)
	material.set_shader_parameter("nubosidad", nubosidad)
	material.set_shader_parameter("luz_clima", lerpf(0.46 if lluvia else 0.43, 0.028, noche) * (0.70 if tormenta else 1.0))
	material.set_shader_parameter("astro", astro)
	material.set_shader_parameter("noche", noche)
	material.set_shader_parameter("tinte_astro", Vector3(color.r, color.g, color.b))
