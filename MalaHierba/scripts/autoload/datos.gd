extends Node
## Datos del juego: lee los JSON de res://datos/ una sola vez. Autoload «Datos».
## Todo lo que devuelve es de solo lectura (no modifiques los diccionarios).

const RUTA := "res://datos/"

var _objetos: Dictionary = {}
var _muebles: Array[Dictionary] = []
var _muebles_por_id: Dictionary = {}
var _cultivos: Dictionary = {}
var _cultivo_por_semilla: Dictionary = {}
var _npcs: Dictionary = {}
var _orden_npcs: Array[String] = []
var _tiendas: Dictionary = {}
var _conexiones: Array = []
var _interacciones: Dictionary = {}
var _mejoras: Dictionary = {}
var _textos: Dictionary = {}


func _init() -> void:
	_cargar_todo()


func _cargar_todo() -> void:
	for o: Variant in _leer("objetos.json", []):
		var d: Dictionary = o
		_objetos[str(d["id"])] = d
	var material_herreria: Array = _leer("equipo_combate.json", [])
	var vende_herreria: Array[String] = []
	var forja_herreria: Array[String] = []
	for d: Dictionary in material_herreria:
		var id := str(d["id"])
		_objetos[id] = d
		forja_herreria.append(id)
		if int(d["precio_compra"]) > 0:
			vende_herreria.append(id)
	_tiendas["forja"] = {"id": "forja", "nombre": "Herrería de Clara", "vende": vende_herreria,
		"forja": forja_herreria, "compra_tipos": []}
	for c: Variant in _leer("cultivos.json", []):
		var d: Dictionary = c
		var est: Array[int] = []
		for e: Variant in d.get("estaciones", []):
			est.append(int(e))
		d["estaciones"] = est
		_cultivos[str(d["id"])] = d
		_cultivo_por_semilla[str(d.get("semilla", ""))] = d
	for n: Variant in _leer("npcs.json", []):
		var d: Dictionary = n
		_npcs[str(d["id"])] = d
		_orden_npcs.append(str(d["id"]))
	for t: Variant in _leer("tiendas.json", []):
		var d: Dictionary = t
		d["vende"] = _a_textos(d.get("vende", []))
		d["compra_tipos"] = _a_textos(d.get("compra_tipos", []))
		_tiendas[str(d["id"])] = d
	_conexiones = _leer("conexiones.json", [])
	if FileAccess.file_exists(RUTA + "interacciones.json"):
		_interacciones = _leer("interacciones.json", {})
	_mejoras = _leer("mejoras.json", {})
	_textos = _leer("textos.json", {})
	_muebles.clear()
	_muebles_por_id.clear()
	if FileAccess.file_exists(RUTA + "muebles.json"):
		for mu: Variant in _leer("muebles.json", []):
			if mu is Dictionary:
				var d := mu as Dictionary
				_muebles.append(d)
				_muebles_por_id[str(d.get("id", ""))] = d


func _leer(archivo: String, defecto: Variant) -> Variant:
	var ruta := RUTA + archivo
	if not FileAccess.file_exists(ruta):
		push_error("Datos: falta %s" % ruta)
		return defecto
	var texto := FileAccess.get_file_as_string(ruta)
	var json := JSON.new()
	if json.parse(texto) != OK:
		push_error("Datos: JSON mal formado en %s (línea %d): %s" % [ruta, json.get_error_line(), json.get_error_message()])
		return defecto
	return normalizar_numeros(json.data)


func _a_textos(a: Array) -> Array[String]:
	var r: Array[String] = []
	for v: Variant in a:
		r.append(str(v))
	return r


## JSON entrega todos los números como float: los que son enteros vuelven a ser int.
static func normalizar_numeros(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if absf(f) < 1.0e15 and is_equal_approx(f, roundf(f)):
				return int(f)
			return f
		TYPE_ARRAY:
			var a: Array = v
			var r: Array = []
			r.resize(a.size())
			for i in a.size():
				r[i] = normalizar_numeros(a[i])
			return r
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var r: Dictionary = {}
			for k: Variant in d:
				r[k] = normalizar_numeros(d[k])
			return r
	return v


# --- Consultas ---------------------------------------------------------------

## id, nombre, tipo (herramienta|semilla|cultivo|mineral|recurso|comida), descripcion,
## precio_compra, precio_venta, energia, color. Vacío si no existe.
func objeto(id: String) -> Dictionary:
	return _objetos.get(id, {})


func detalle_equipo(o: Dictionary) -> String:
	if o.get("tipo") == "arma":
		if o.get("subtipo", "") == "arco":
			return "Arco · %d daño base · %d m alcance · %d resist./tiro" % [
				int(o.get("dano", 0)), roundi(float(o.get("alcance", 28.0))), int(o.get("coste", 7))]
		return "%d de daño · %.2f m de alcance · %d de resistencia por golpe" % [
			int(o.get("dano", 0)), float(o.get("alcance", 0)), int(o.get("coste", 0))]
	if o.get("tipo") == "municion":
		return "Flecha (+%d daño · recup. %d %%)" % [int(o.get("bono_dano", 0)), roundi(float(o.get("recupera", 0.5)) * 100.0)]
	if o.get("ranura_equipo") == "escudo":
		return "Bloqueo: reduce el daño frontal un %d %%" % roundi(float(o.get("reduccion", 0)) * 100.0)
	if o.has("defensa"):
		return "%d de defensa" % int(o["defensa"])
	return ""


func muebles() -> Array[Dictionary]:
	return _muebles


func mueble(id: String) -> Dictionary:
	return _muebles_por_id.get(id, {})


func es_mueble(id: String) -> bool:
	return _muebles_por_id.has(id)


func existe_objeto(id: String) -> bool:
	return _objetos.has(id)


func nombre_objeto(id: String) -> String:
	var o: Dictionary = _objetos.get(id, {})
	return str(o.get("nombre", id))


func color_objeto(id: String) -> Color:
	var o: Dictionary = _objetos.get(id, {})
	return Estilo.color_html(str(o.get("color", "")))


func objetos_de_tipo(tipo: String) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for id: String in _objetos:
		var o: Dictionary = _objetos[id]
		if o.get("tipo", "") == tipo:
			r.append(o)
	return r


## id, nombre, semilla, estaciones:Array[int], dias, etapas, cosecha, cantidad:[min,max], rebrota, color.
func cultivo(id: String) -> Dictionary:
	return _cultivos.get(id, {})


func cultivo_de_semilla(id_semilla: String) -> Dictionary:
	return _cultivo_por_semilla.get(id_semilla, {})


func ids_cultivos() -> Array[String]:
	var r: Array[String] = []
	for k: String in _cultivos:
		r.append(k)
	return r


## id, nombre, rol, mapa, marcador, modelo, tienda, gusta, no_gusta y dialogos
## ({"0": [...], "1": [...], "2": [...]}, una lista de frases por nivel de amistad).
func npc(id: String) -> Dictionary:
	return _npcs.get(id, {})


func ids_npc() -> Array[String]:
	return _orden_npcs


func npcs_de_mapa(mapa: String) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for id in _orden_npcs:
		var n: Dictionary = _npcs[id]
		if n.get("mapa", "") == mapa:
			r.append(n)
	return r


## Frases del vecino para un nivel de amistad (0, 1 o 2).
func dialogos_npc(id: String, nivel: int) -> Array:
	var n: Dictionary = _npcs.get(id, {})
	var d: Dictionary = n.get("dialogos", {})
	return d.get(str(clampi(nivel, 0, 2)), [])


## id, nombre, vende:Array[String], compra_tipos:Array[String].
func tienda(id: String) -> Dictionary:
	return _tiendas.get(id, {})


## Conexiones entre mapas (zonas de paso) que salen del mapa indicado (ver conexiones.json).
func conexiones_de(mapa: String) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for c: Variant in _conexiones:
		var d: Dictionary = c
		if d.get("mapa", "") == mapa and not bool(d.get("puerta", false)):
			r.append(d)
	return r


## Puertas interactuables que salen del mapa indicado (entradas con "puerta": true en conexiones.json).
func puertas_de(mapa: String) -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for c: Variant in _conexiones:
		var d: Dictionary = c
		if d.get("mapa", "") == mapa and bool(d.get("puerta", false)):
			r.append(d)
	return r


## Objetos interactuables definidos en datos/interacciones.json para el mapa indicado.
func interacciones_de(mapa: String) -> Array[Dictionary]:
	if _interacciones.is_empty() and FileAccess.file_exists(RUTA + "interacciones.json"):
		_interacciones = _leer("interacciones.json", {})
	var r: Array[Dictionary] = []
	var lista: Variant = _interacciones.get(mapa, [])
	if lista is Array:
		for item: Variant in lista:
			if item is Dictionary:
				r.append(item)
	return r


var _recetas: Array[Dictionary] = []
var _recetas_por_id: Dictionary = {}


func _asegurar_recetas() -> void:
	if not _recetas.is_empty():
		return
	var raw: Variant = _leer("recetas.json", [])
	if raw is Array:
		for item: Variant in raw:
			if item is Dictionary:
				var d := item as Dictionary
				var id := str(d.get("id", ""))
				if not id.is_empty():
					_recetas.append(d)
					_recetas_por_id[id] = d


func recetas() -> Array[Dictionary]:
	_asegurar_recetas()
	return _recetas


func receta(id: String) -> Dictionary:
	_asegurar_recetas()
	return _recetas_por_id.get(id, {})


func existe_receta(id: String) -> bool:
	_asegurar_recetas()
	return _recetas_por_id.has(id)


func detalle_comida(id: String) -> String:
	var rec := receta(id)
	var o := objeto(id)
	var partes: Array[String] = []
	var e := int(rec.get("energia", o.get("energia", 0)))
	if e > 0:
		partes.append("+%d energía" % e)
	var v := int(rec.get("vida", roundi(float(e) * 0.5)))
	if v > 0:
		partes.append("+%d salud" % v)
	var res := int(rec.get("resistencia", 0))
	if res > 0:
		partes.append("+%d resistencia" % res)
	var bufo: Variant = rec.get("bufo", {})
	if bufo is Dictionary and not (bufo as Dictionary).is_empty():
		var bd := bufo as Dictionary
		var mins := int(bd.get("duracion_min", 180))
		partes.append("%s (%d h)" % [str(bd.get("etiqueta", "")), maxi(1, roundi(float(mins) / 60.0))])
	return " · ".join(partes)


## Mejora de herramienta que lleva a `nivel` (1..3): nivel, nombre, dinero, material, cantidad. Vacío si no hay.
func mejora(herramienta: String, nivel: int) -> Dictionary:
	var lista: Array = _mejoras.get(herramienta, [])
	for m: Variant in lista:
		var d: Dictionary = m
		if int(d.get("nivel", 0)) == nivel:
			return d
	return {}


## Texto o estructura de textos.json por clave con puntos: «final.bueno.titulo».
func texto(clave: String, defecto: Variant = "") -> Variant:
	var actual: Variant = _textos
	for parte in clave.split("."):
		if actual is Dictionary and (actual as Dictionary).has(parte):
			actual = (actual as Dictionary)[parte]
		else:
			return defecto
	return actual


# --- Iconos de objetos (M1) -----------------------------------------------------------------

const RUTA_ICONOS := "res://assets/iconos/%s.png"
var _iconos: Dictionary = {}
var _iconos_reales: Dictionary = {}


## Id de ilustración para la herramienta y su metal; el resto conserva su propio id.
func id_icono(id: String, nivel: int = 0) -> String:
	if id.begins_with("receta:"):
		return id.trim_prefix("receta:")
	if objeto(id).get("tipo", "") == "herramienta" and nivel > 0:
		var m := mejora(id, nivel)
		if not m.is_empty():
			return id + "_" + str(m.get("material", ""))
	return id


## Icono transparente compartido. El cuadro de reserva solo se usa si falta el archivo.
func icono(id: String) -> Texture2D:
	var clave := id.trim_prefix("receta:") if id.begins_with("receta:") else id
	if _iconos.has(clave):
		return _iconos[clave]
	var tex := _cargar_icono_archivo(clave)
	_iconos_reales[clave] = tex != null
	if tex == null:
		tex = _icono_de_color(color_objeto(clave))
	_iconos[clave] = tex
	return tex


## true si hay un archivo de ilustración para ese objeto o variante.
func tiene_icono(id: String) -> bool:
	var clave := id.trim_prefix("receta:") if id.begins_with("receta:") else id
	if not _iconos_reales.has(clave):
		icono(clave)
	return bool(_iconos_reales[clave])


## Olvida los iconos cargados (por si se añaden archivos con el juego en marcha).
func recargar_iconos() -> void:
	_iconos.clear()
	_iconos_reales.clear()


func _cargar_icono_archivo(id: String) -> Texture2D:
	var ruta := RUTA_ICONOS % id
	if ResourceLoader.exists(ruta):
		var t := load(ruta) as Texture2D
		if t != null:
			return t
	if FileAccess.file_exists(ruta):
		# Aún sin importar en el editor: se lee el PNG tal cual.
		var img := Image.load_from_file(ProjectSettings.globalize_path(ruta))
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## Cuadro redondeado de 64×64 con el color del objeto, borde más oscuro y un brillo suave arriba.
func _icono_de_color(color: Color) -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var borde := color.darkened(0.45)
	for y in n:
		for x in n:
			var dx := maxf(absf(float(x) - 31.5) - 24.5, 0.0)
			var dy := maxf(absf(float(y) - 31.5) - 24.5, 0.0)
			var d := sqrt(dx * dx + dy * dy)
			if d > 7.0:
				continue
			var c := color.lightened(0.12 * (1.0 - float(y) / float(n)))
			if d > 5.0:
				c = borde
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
