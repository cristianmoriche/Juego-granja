class_name InteraccionesInterior
extends Node3D
## Objetos interactuables dentro de los interiores (encargo L5).
## Lee `Datos.interacciones_de(id_mapa)` (desde `res://datos/interacciones.json`), busca cada marcador
## `Interaccion_<nombre>` (o `Obj_<nombre>`) en el mapa y crea un `Interactuable` (sistema de M1: cartel
## «E · Verbo objeto», anillo en el suelo y flecha sobre la malla del mueble).
## También gestiona el arcón de 30 huecos de `casa_leo` en `Juego.estado_mapas["casa_leo"]["arcon"]`,
## la carta de la abuela Rosa, el calendario y los mostradores con horario de tienda, herrería y taberna.

const HUECOS_ARCON := 30
const ID_CASA_LEO := "casa_leo"

var puntos: Array[Interactuable] = []
var por_marcador: Dictionary = {}
var id_mapa: String = ""
var construido: bool = false


func _ready() -> void:
	Escenas.mapa_cargado.connect(_al_mapa_cargado)
	var m := _mapa()
	if m != null and bool(m.get("esta_listo")):
		construir.call_deferred()


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


func _al_mapa_cargado(id: String) -> void:
	var m := _mapa()
	if m != null and str(m.get("id_mapa")) == id:
		construir()


func construir() -> void:
	var mapa := _mapa()
	if mapa == null:
		return
	id_mapa = str(mapa.get("id_mapa"))
	for h in get_children():
		h.queue_free()
	puntos.clear()
	por_marcador.clear()

	var esc: Node = null
	var cargador: Node = mapa.get("cargador") as Node
	if cargador != null:
		esc = cargador.get("escenario") as Node

	for d: Dictionary in Datos.interacciones_de(id_mapa):
		var nom_marc := str(d.get("marcador", ""))
		var m := mapa.call("marcador", nom_marc) as Marker3D
		if m == null and nom_marc.begins_with("Interaccion_"):
			m = mapa.call("marcador", "Obj_" + nom_marc.substr(12)) as Marker3D
		if m == null:
			push_warning("InteraccionesInterior (%s): falta el marcador %s" % [id_mapa, nom_marc])
			continue
		var accion := str(d.get("accion", ""))
		if accion == "dormir" and mapa.find_child("Cama", true, false) != null:
			continue
		var c := Interactuable.new()
		c.name = nom_marc
		c.verbo = str(d.get("verbo", "Examinar"))
		c.nombre_objeto = str(d.get("nombre", "objeto"))
		c.radio = float(d.get("radio", 1.4))
		c.altura_marca = 1.65
		c.descripcion = str(d.get("descripcion", ""))
		var tit := c.nombre_objeto
		if tit.length() > 0:
			tit = tit.substr(0, 1).to_upper() + tit.substr(1)
		c.titulo_dialogo = tit
		c.mostrar_descripcion = accion.is_empty()

		var nom_malla := str(d.get("malla", ""))
		if not nom_malla.is_empty():
			var mallas := mapa.find_children(nom_malla + "*", "MeshInstance3D", true, false)
			if not mallas.is_empty():
				c.objetivo_resaltado = mallas[0] as Node3D
			else:
				var mi := mapa.find_child(nom_malla + "*", true, false) as Node3D
				if mi != null:
					c.objetivo_resaltado = mi

		add_child(c)
		c.global_position = m.global_position
		if not accion.is_empty():
			c.usado.connect(func(_j: Node3D) -> void: ejecutar_accion(accion, d))
		puntos.append(c)
		por_marcador[nom_marc] = c
		var id_obj := str(d.get("id", ""))
		if not id_obj.is_empty():
			por_marcador[id_obj] = c
	construido = true


func nodo_interaccion(clave: String) -> Interactuable:
	if por_marcador.has(clave):
		return por_marcador[clave] as Interactuable
	if por_marcador.has("Interaccion_" + clave):
		return por_marcador["Interaccion_" + clave] as Interactuable
	return null


## Ejecuta la acción especial de un objeto de interior y devuelve un código de resultado («carta», «calendario»,
## «arcon», «abierto», «cerrado», «dormir» o «descripcion»).
func ejecutar_accion(accion: String, d: Dictionary = {}) -> String:
	if accion == "carta":
		leer_carta_abuela()
		return "carta"
	if accion == "calendario":
		mirar_calendario()
		return "calendario"
	if accion == "arcon":
		abrir_arcon()
		return "arcon"
	if accion == "carpinteria":
		if Interfaz.has_method("abrir_carpinteria"):
			Interfaz.call("abrir_carpinteria")
		return "carpinteria"
	if accion == "cocina":
		if Interfaz.has_method("abrir_cocina"):
			Interfaz.call("abrir_cocina", "Cocina de leña")
		return "cocina"
	if accion == "dormir":
		Interfaz.preguntar("¿Dormir hasta mañana?", ["Dormir", "Todavía no"], func(i: int) -> void:
			if i == 0:
				Juego.dormir())
		return "dormir"
	if accion == "mejoras":
		return usar_yunque()
	if accion.begins_with("tienda:"):
		var id_t := accion.get_slice(":", 1)
		if id_t == "tienda_mateo":
			return usar_mostrador_tienda()
		return usar_barra_taberna()
	var desc := str(d.get("descripcion", ""))
	if not desc.is_empty():
		Interfaz.mostrar_dialogo(str(d.get("nombre", "Examinar")), [desc])
	return "descripcion"


# --- Carta de la abuela Rosa y calendario (casa_leo) ----------------------------------------------

static func leer_carta_abuela() -> void:
	var parrafos_crudos: Variant = Datos.texto("intro.carta", [])
	var lineas: Array[String] = []
	var nombre := Juego.nombre_jugador if not Juego.nombre_jugador.is_empty() else "Leo"
	if parrafos_crudos is Array:
		for p: Variant in parrafos_crudos:
			lineas.append(str(p).replace("{nombre}", nombre))
	if lineas.is_empty():
		lineas.append("Querido %s: si estás leyendo esto, ya estás en El Granado. Cuida la tierra y a los vecinos de Villaverde." % nombre)
	Interfaz.mostrar_dialogo("Carta de la abuela Rosa", lineas)


static func mirar_calendario() -> void:
	var faltan := maxi(0, Juego.DIAS_ESTACION - Juego.dia)
	var fiestas: Dictionary = {
		0: "Fiesta de esta estación: Feria de la Siembra (14 de primavera) en la plaza del pueblo.",
		1: "Próxima gran fiesta: Fiesta de la Cosecha (18 de otoño) en la plaza del pueblo.",
		2: "Fiesta de esta estación: Fiesta de la Cosecha (18 de otoño) en la plaza del pueblo.",
		3: "Próxima gran fiesta: Feria de la Siembra (14 de primavera) cuando vuelva el buen tiempo.",
	}
	var texto_fiesta := str(fiestas.get(Juego.estacion, fiestas[0]))
	var lineas: Array[String] = [
		"Hoy es %s, %s (%s). Quedan %d día(s) para que termine la estación." % [Juego.nombre_dia_semana().to_lower(), Juego.texto_fecha(), Juego.texto_hora(), faltan],
		texto_fiesta,
	]
	Interfaz.mostrar_dialogo("Calendario de Villaverde", lineas)


# --- Arcón de 30 huecos en casa_leo --------------------------------------------------------------

## Devuelve el array persistente de 30 huecos en `Juego.estado_mapas["casa_leo"]["arcon"]`.
static func ranuras_arcon() -> Array:
	if not (Juego.estado_mapas.get(ID_CASA_LEO, null) is Dictionary):
		Juego.estado_mapas[ID_CASA_LEO] = {}
	var est: Dictionary = Juego.estado_mapas[ID_CASA_LEO]
	if not (est.get("arcon", null) is Array):
		var nuevo: Array = []
		for _i in HUECOS_ARCON:
			nuevo.append({})
		est["arcon"] = nuevo
	var arr: Array = est["arcon"]
	while arr.size() < HUECOS_ARCON:
		arr.append({})
	return arr


static func huecos_ocupados_arcon() -> int:
	var n := 0
	for r: Variant in ranuras_arcon():
		if r is Dictionary and not (r as Dictionary).is_empty() and int((r as Dictionary).get("cantidad", 0)) > 0:
			n += 1
	return n


static func cantidad_en_arcon(id_objeto: String) -> int:
	var total := 0
	for r: Variant in ranuras_arcon():
		if r is Dictionary and str((r as Dictionary).get("id", "")) == id_objeto:
			total += int((r as Dictionary).get("cantidad", 0))
	return total


## Guarda `cantidad` unidades de `id_objeto` desde el inventario de Leo al arcón (30 huecos).
static func guardar_en_arcon(id_objeto: String, cantidad: int = 1) -> bool:
	if id_objeto.is_empty() or cantidad <= 0:
		return false
	if Juego.cantidad(id_objeto) < cantidad:
		return false
	var arr := ranuras_arcon()
	var apilable := bool(Datos.objeto(id_objeto).get("apilable", true))
	var idx_destino := -1
	if apilable:
		for i in arr.size():
			var d: Dictionary = arr[i] if arr[i] is Dictionary else {}
			if str(d.get("id", "")) == id_objeto and int(d.get("cantidad", 0)) > 0:
				idx_destino = i
				break
	if idx_destino < 0:
		for i in arr.size():
			var d: Dictionary = arr[i] if arr[i] is Dictionary else {}
			if d.is_empty() or int(d.get("cantidad", 0)) <= 0:
				idx_destino = i
				break
	if idx_destino < 0:
		return false
	if not Juego.quitar_objeto(id_objeto, cantidad):
		return false
	var actual: Dictionary = arr[idx_destino] if arr[idx_destino] is Dictionary else {}
	var prev := int(actual.get("cantidad", 0)) if str(actual.get("id", "")) == id_objeto else 0
	arr[idx_destino] = {"id": id_objeto, "cantidad": prev + cantidad}
	return true


## Saca `cantidad` unidades de `id_objeto` del arcón y las devuelve al inventario de Leo.
static func sacar_de_arcon(id_objeto: String, cantidad: int = 1) -> bool:
	if id_objeto.is_empty() or cantidad <= 0:
		return false
	if cantidad_en_arcon(id_objeto) < cantidad:
		return false
	if Juego.espacio_para(id_objeto) < cantidad:
		return false
	var arr := ranuras_arcon()
	var restante := cantidad
	for i in arr.size():
		if restante <= 0:
			break
		var d: Dictionary = arr[i] if arr[i] is Dictionary else {}
		if str(d.get("id", "")) != id_objeto:
			continue
		var hay := int(d.get("cantidad", 0))
		if hay <= 0:
			continue
		var quitar := mini(hay, restante)
		hay -= quitar
		restante -= quitar
		if hay <= 0:
			arr[i] = {}
		else:
			arr[i] = {"id": id_objeto, "cantidad": hay}
	var sobra := Juego.anadir_objeto(id_objeto, cantidad)
	return sobra == 0


static func abrir_arcon() -> void:
	var arr := ranuras_arcon()
	var ocupados := huecos_ocupados_arcon()
	var acciones: Array[Callable] = []
	var opciones: Array = []

	# 1. Objetos que Leo lleva en la mochila (salvo las 5 herramientas básicas) para guardar
	var vistos_inv: Dictionary = {}
	for h: Dictionary in Juego.inventario:
		if h.is_empty():
			continue
		var id_obj := str(h.get("id", ""))
		if id_obj.is_empty() or vistos_inv.has(id_obj):
			continue
		if str(Datos.objeto(id_obj).get("tipo", "")) == "herramienta":
			continue
		var cant := Juego.cantidad(id_obj)
		if cant <= 0:
			continue
		vistos_inv[id_obj] = true
		opciones.append("Guardar %s (×%d en mochila)" % [Datos.nombre_objeto(id_obj), cant])
		acciones.append(func() -> void:
			if guardar_en_arcon(id_obj, cant):
				Interfaz.mensaje("Guardado en el arcón: %d × %s." % [cant, Datos.nombre_objeto(id_obj)]))

	# 2. Objetos dentro del arcón para sacar a la mochila
	var vistos_arc: Dictionary = {}
	for r: Variant in arr:
		if not (r is Dictionary) or (r as Dictionary).is_empty():
			continue
		var id_obj := str((r as Dictionary).get("id", ""))
		if id_obj.is_empty() or vistos_arc.has(id_obj):
			continue
		var cant := cantidad_en_arcon(id_obj)
		if cant <= 0:
			continue
		vistos_arc[id_obj] = true
		opciones.append("Sacar %s (×%d en el arcón)" % [Datos.nombre_objeto(id_obj), cant])
		acciones.append(func() -> void:
			if sacar_de_arcon(id_obj, cant):
				Interfaz.mensaje("Has sacado del arcón: %d × %s." % [cant, Datos.nombre_objeto(id_obj)])
			else:
				Interfaz.mensaje("No tienes espacio en la mochila."))

	opciones.append("Cerrar el arcón")
	var cabecera := "Arcón de la cabaña (%d/%d huecos ocupados)." % [ocupados, HUECOS_ARCON]
	if ocupados == 0 and acciones.is_empty():
		cabecera += " Está vacío y ahora mismo solo llevas tus herramientas encima."
	Interfaz.preguntar(cabecera, opciones, func(i: int) -> void:
		if i >= 0 and i < acciones.size():
			acciones[i].call())


# --- Mostradores de tienda, herrería y taberna con horario ---------------------------------------

static func tienda_abierta(minutos: int = -1) -> bool:
	var m := Juego.minutos if minutos < 0 else minutos
	return m >= 540 and m < 1140   # 09:00 a 19:00


static func herreria_abierta(minutos: int = -1) -> bool:
	var m := Juego.minutos if minutos < 0 else minutos
	return m >= 480 and m < 1080   # 08:00 a 18:00


static func taberna_abierta(minutos: int = -1) -> bool:
	var m := Juego.minutos if minutos < 0 else minutos
	return m >= 720 and m <= 1440  # 12:00 a 24:00


static func usar_mostrador_tienda() -> String:
	if not tienda_abierta():
		Interfaz.mostrar_dialogo("Tienda de Don Mateo", ["La tienda está cerrada. Abre a las 09:00 (de 09:00 a 19:00)."])
		return "cerrado"
	Interfaz.abrir_tienda("tienda_mateo")
	return "abierto"


static func usar_yunque() -> String:
	if not herreria_abierta():
		Interfaz.mostrar_dialogo("Herrería de Clara", ["La herrería está cerrada. Abre a las 08:00 (de 08:00 a 18:00)."])
		return "cerrado"
	Servicios.menu_herreria("Clara")
	return "abierto"


static func usar_barra_taberna() -> String:
	if not taberna_abierta():
		Interfaz.mostrar_dialogo("Taberna El Candil", ["La taberna está cerrada. Abre a las 12:00 (de 12:00 a 24:00)."])
		return "cerrado"
	Interfaz.preguntar("Barra de la taberna El Candil. ¿Qué quieres pedir?", ["Comer aquí en la barra", "Comprar para llevar", "Nada, gracias"], func(i: int) -> void:
		if i == 0:
			Servicios.menu_comer("Ramón")
		elif i == 1:
			Interfaz.abrir_tienda("taberna"))
	return "abierto"
