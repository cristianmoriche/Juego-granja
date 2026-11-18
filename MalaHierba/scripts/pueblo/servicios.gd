class_name Servicios
extends RefCounted
## Servicios de los vecinos del pueblo y la mina (L4b): herrería de Clara (mejorar herramientas), comidas de la taberna
## de Ramón, compra de minerales de Tomás y su charla sobre la mina. Cada servicio tiene una función «sin pantalla»
## (`mejorar`, `comer_aqui`, `vender_mineral`) que hace el trato y devuelve el resultado, y un menú que usa
## `Interfaz.preguntar` y `Interfaz.mostrar_dialogo`. La conversación (`Conversacion`) llama a los menús.

const HERRAMIENTAS: Array[String] = ["azada", "regadera", "hoz", "hacha", "pico"]
const FACTOR_TOMAS := 1.15
static var _lote_venta: bool = false


# --- Herrería (Clara) ------------------------------------------------------------------------------

## Mejora que toca ahora a una herramienta (vacío si ya está al máximo): nivel, nombre, dinero, material, cantidad.
static func siguiente_mejora(herramienta: String) -> Dictionary:
	return Datos.mejora(herramienta, Juego.nivel(herramienta) + 1)


## Hace la mejora: gasta material y dinero y sube el nivel. Devuelve «ok», «maximo», «sin_material» o «sin_dinero»
## (en los fallos no se gasta nada).
static func mejorar(herramienta: String) -> String:
	var m := siguiente_mejora(herramienta)
	if m.is_empty():
		return "maximo"
	var material := str(m.get("material", ""))
	var cantidad := int(m.get("cantidad", 0))
	var dinero := int(m.get("dinero", 0))
	if Juego.cantidad(material) < cantidad:
		return "sin_material"
	if Juego.dinero < dinero:
		return "sin_dinero"
	if not Juego.quitar_objeto(material, cantidad) or not Juego.cobrar(dinero):
		return "sin_dinero"
	Juego.nivel_herramientas[herramienta] = int(m.get("nivel", Juego.nivel(herramienta) + 1))
	Juego.inventario_cambiado.emit()
	Audio.reproducir("ui_comprar")
	return "ok"


## Texto de una opción del menú de la herrería: «Pico de cobre · 5 × Cobre + 150 €».
static func texto_mejora(m: Dictionary) -> String:
	var t := "%s · %d × %s + %s" % [str(m.get("nombre", "")), int(m.get("cantidad", 0)), Datos.nombre_objeto(str(m.get("material", ""))), Estilo.euros(int(m.get("dinero", 0)))]
	var falta: Array[String] = []
	if Juego.cantidad(str(m.get("material", ""))) < int(m.get("cantidad", 0)):
		falta.append("material")
	if Juego.dinero < int(m.get("dinero", 0)):
		falta.append("dinero")
	if not falta.is_empty():
		t += "  (te falta " + " y ".join(PackedStringArray(falta)) + ")"
	return t


static func menu_herreria(nombre_herrera: String) -> void:
	var herr: Array[String] = []
	var textos: Array = []
	for h in HERRAMIENTAS:
		var m := siguiente_mejora(h)
		if m.is_empty():
			continue
		herr.append(h)
		textos.append({"texto": texto_mejora(m), "icono": Datos.id_icono(h, int(m.get("nivel", 0)))})
	textos.append("Comprar o forjar armas y armaduras")
	textos.append("Arco, carcaj y flechas (taller)")
	textos.append("Nada, gracias")
	Interfaz.preguntar("¿Qué necesitas de la herrería?", textos, _mejora_elegida.bind(herr, nombre_herrera))


static func _mejora_elegida(i: int, herr: Array[String], nombre_herrera: String) -> void:
	if i == herr.size():
		Interfaz.abrir_tienda("forja")
		return
	if i == herr.size() + 1:
		Interfaz.abrir_tienda("arqueria")
		return
	if i < 0 or i >= herr.size():
		return
	var h := herr[i]
	var nombre_nuevo := str(siguiente_mejora(h).get("nombre", h))
	var resultado := mejorar(h)
	if resultado == "ok":
		var icono := Datos.id_icono(h, Juego.nivel(h))
		Interfaz.mensaje("Herramienta mejorada: %s." % nombre_nuevo, icono)
		Interfaz.mostrar_dialogo(nombre_herrera, [{"texto": "Hecho. Aquí tienes: %s. Pruébala, que está recién salida de la fragua." % nombre_nuevo.to_lower(), "icono": icono}])
	elif resultado == "sin_material":
		Audio.reproducir("ui_error")
		Interfaz.mostrar_dialogo(nombre_herrera, ["Me falta metal para eso. Tráeme el material de la mina y lo hacemos."])
	elif resultado == "sin_dinero":
		Audio.reproducir("ui_error")
		Interfaz.mostrar_dialogo(nombre_herrera, ["El metal lo tienes, pero el trabajo hay que pagarlo. Vuelve cuando lleves el dinero."])
	else:
		Audio.reproducir("ui_error")
		Interfaz.mostrar_dialogo(nombre_herrera, ["Eso ya no se puede mejorar más."])


# --- Taberna (Ramón) ------------------------------------------------------------------------------

## Come en la barra: paga y recupera la energía del plato al momento. Devuelve «ok», «sin_hambre» o «sin_dinero».
static func comer_aqui(id: String) -> String:
	var o := Datos.objeto(id)
	if o.is_empty():
		return "sin_dinero"
	if Juego.energia >= Juego.energia_max - 0.01:
		return "sin_hambre"
	if not Juego.cobrar(int(o.get("precio_compra", 0))):
		return "sin_dinero"
	Juego.recuperar_energia(float(o.get("energia", 0)))
	Juego.mensaje.emit("%s: recuperas %d de energía." % [Datos.nombre_objeto(id), int(o.get("energia", 0))])
	Audio.reproducir("ui_comprar")
	return "ok"


static func menu_comer(nombre_tabernero: String) -> void:
	var ids: Array[String] = []
	var textos: Array = []
	for v: Variant in Datos.tienda("taberna").get("vende", []):
		var id := str(v)
		var o := Datos.objeto(id)
		if o.is_empty():
			continue
		ids.append(id)
		textos.append({"texto": "%s · %s · +%d de energía" % [Datos.nombre_objeto(id), Estilo.euros(int(o.get("precio_compra", 0))), int(o.get("energia", 0))], "icono": id})
	textos.append("Nada, gracias")
	Interfaz.preguntar("¿Qué te pongo? Se toma aquí, en la barra.", textos, _plato_elegido.bind(ids, nombre_tabernero))


static func _plato_elegido(i: int, ids: Array[String], nombre_tabernero: String) -> void:
	if i < 0 or i >= ids.size():
		return
	var resultado := comer_aqui(ids[i])
	if resultado == "ok":
		Interfaz.mostrar_dialogo(nombre_tabernero, ["Que aproveche. Se te ve con mejor cara."])
	elif resultado == "sin_hambre":
		Audio.reproducir("ui_error")
		Interfaz.mostrar_dialogo(nombre_tabernero, ["Pero si vas sobrado de fuerzas. Vuelve cuando tengas hambre de verdad."])
	else:
		Audio.reproducir("ui_error")
		Interfaz.mostrar_dialogo(nombre_tabernero, ["Eso son %s y no llevas tanto encima. Otro día." % Estilo.euros(int(Datos.objeto(ids[i]).get("precio_compra", 0)))])


# --- Minerales (Tomás) -------------------------------------------------------------------------------

static func precio_mineral(id: String, factor: float = FACTOR_TOMAS) -> int:
	return roundi(float(int(Datos.objeto(id).get("precio_venta", 0))) * factor)


## Minerales del inventario que se pueden vender: {id: cantidad}.
static func minerales_en_mochila() -> Dictionary:
	var r: Dictionary = {}
	for h: Dictionary in Juego.inventario:
		if h.is_empty():
			continue
		var id := str(h["id"])
		if Datos.objeto(id).get("tipo", "") == "mineral" and int(Datos.objeto(id).get("precio_venta", 0)) > 0:
			r[id] = int(r.get(id, 0)) + int(h["cantidad"])
	return r


## Vende `n` unidades de un mineral (0 = todas) a `factor` veces el precio normal. Devuelve lo cobrado (0 si no hay).
static func vender_mineral(id: String, n: int = 0, factor: float = FACTOR_TOMAS) -> int:
	var tengo := Juego.cantidad(id)
	var cuantas := tengo if n <= 0 else mini(n, tengo)
	if cuantas <= 0 or Datos.objeto(id).get("tipo", "") != "mineral":
		return 0
	if not Juego.quitar_objeto(id, cuantas):
		return 0
	var total := cuantas * precio_mineral(id, factor)
	Juego.ingresar(total)
	if not _lote_venta:
		Interfaz.mostrar_dinero_flotante(total)
	Juego.mensaje.emit("Has vendido %d × %s por %s." % [cuantas, Datos.nombre_objeto(id), Estilo.euros(total)])
	return total


static func menu_vender_minerales(nombre_minero: String) -> void:
	var tengo := minerales_en_mochila()
	if tengo.is_empty():
		Interfaz.mostrar_dialogo(nombre_minero, ["No llevas ningún mineral. Cuando bajes a la mina y saques piedra, cobre, hierro o cuarzo, te lo compro a mejor precio que en el pueblo."])
		return
	var ids: Array[String] = []
	var textos: Array = []
	var total_todo := 0
	for id: String in tengo:
		ids.append(id)
		var n := int(tengo[id])
		total_todo += n * precio_mineral(id)
		textos.append({"texto": "Vender %s ×%d · %s cada uno" % [Datos.nombre_objeto(id), n, Estilo.euros(precio_mineral(id))], "icono": id})
	textos.append("Venderlo todo · %s" % Estilo.euros(total_todo))
	textos.append("Nada, gracias")
	Interfaz.preguntar("Te pago un quince por ciento más que en la tienda del pueblo.", textos, _mineral_elegido.bind(ids, nombre_minero))


static func _mineral_elegido(i: int, ids: Array[String], nombre_minero: String) -> void:
	if i < 0 or i > ids.size():
		return
	var cobrado := 0
	if i == ids.size():
		_lote_venta = true
		for id in ids:
			cobrado += vender_mineral(id)
		_lote_venta = false
		if cobrado > 0:
			Interfaz.mostrar_dinero_flotante(cobrado)
	else:
		cobrado = vender_mineral(ids[i])
	if cobrado > 0:
		Interfaz.mostrar_dialogo(nombre_minero, ["Trato hecho: %s. Da gusto negociar con quien trae el género limpio." % Estilo.euros(cobrado)])


## Lo que cuenta Tomás sobre la mina (cambia según lo que Leo ya ha visto).
static func charla_mina(nombre_minero: String) -> void:
	var lineas: Array = [
		"La mina vieja tiene dos niveles. El primero lo conozco como mi casa: piedra, algo de cobre y, si buscas bien, hierro.",
		"Hay que ir con pico y con paciencia. Cada roca aguanta unos cuantos golpes según lo que lleve dentro, y un pico mejor cuesta menos.",
		"Al fondo del primer nivel hay una escalera que baja al segundo. Allí hay más hierro y se ve brillar el cuarzo; es más oscuro y más frío.",
		"Las rocas vuelven a salir de un día para otro. La montaña es testaruda: por mucho que la piques, siempre guarda algo.",
	]
	if int(Juego.banderas.get("nivel_mina", 1)) >= 2:
		lineas = ["Veo que has bajado al segundo nivel. Allí se respira distinto, ¿verdad? Cuida la energía: cuanto más abajo, más cuesta volver.", lineas[3]]
	Interfaz.mostrar_dialogo(nombre_minero, lineas)
