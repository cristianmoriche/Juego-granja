class_name Conversacion
extends RefCounted
## Qué pasa cuando Leo habla con un vecino (L4b). `Npc` llama a `Conversacion.hablar(npc, jugador)`.
## Vecinos principales (de `datos/npcs.json`): menú con su servicio (tienda, herrería, taberna, minerales),
## «Hablar» (+5 de amistad la primera vez cada día y una frase del nivel de amistad que no repita la anterior)
## y «Regalar» (lo que Leo lleva en la mano: gusta +20, no gusta −10, otra cosa +3; un regalo al día por vecino).
## Vecinos de relleno (`datos/vecinos_relleno.json`): solo frases, sin menú ni amistad.

const NOMBRES_NIVEL: Array[String] = ["conocido", "amigo", "de confianza"]
const RUTA_HISTORIAS := "res://datos/historias_npcs.json"
const PUNTOS_GUSTA := 20
const PUNTOS_NO_GUSTA := -10
const PUNTOS_NEUTRO := 3

static var _historias_cache: Dictionary = {}


static func _historias() -> Dictionary:
	if _historias_cache.is_empty() and FileAccess.file_exists(RUTA_HISTORIAS):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(RUTA_HISTORIAS)) == OK and json.data is Dictionary:
			_historias_cache = Datos.normalizar_numeros(json.data) as Dictionary
		else:
			push_warning("Conversacion: %s mal formado." % RUTA_HISTORIAS)
	return _historias_cache


static func hablar(npc: Npc, jugador: Node3D) -> void:
	if Interfaz.ocupada():
		return
	npc.empezar_charla(jugador)
	if npc.relleno:
		Interfaz.mostrar_dialogo(npc.nombre, [frase_de_relleno(npc)])
		return
	var acciones: Array[String] = acciones_de(npc)
	var textos: Array = []
	for a in acciones:
		textos.append(texto_accion(a, npc))
	var rol := str(npc.datos.get("rol", ""))
	var cabecera := "%s · %s · %s" % [npc.nombre, rol, NOMBRES_NIVEL[Juego.nivel_amistad(npc.id)]]
	if npc.es_oficio_comercial() and not npc.en_lugar_trabajo():
		cabecera += " · (Fuera de su puesto)"
	Interfaz.preguntar(cabecera, textos, func(i: int) -> void:
		if i >= 0 and i < acciones.size():
			ejecutar(acciones[i], npc))


## Acciones del menú de un vecino, según su oficio. Compras y servicios avanzados solo en su lugar de trabajo.
static func acciones_de(npc: Npc) -> Array[String]:
	var r: Array[String] = []
	var en_puesto := npc.en_lugar_trabajo()
	match npc.id:
		"mateo":
			if en_puesto:
				r.append("tienda")
		"clara":
			if en_puesto:
				r.append("herreria")
		"ramon":
			if en_puesto:
				r.append("comer")
				r.append("llevar")
		"anselmo":
			if en_puesto and Juego.deuda > 0:
				r.append("deuda")
		"tomas":
			if en_puesto:
				r.append("minerales")
			r.append("mina")
	r.append("hablar")
	r.append("regalar")
	if not Misiones.paso_entregar_para(npc.id).is_empty():
		r.append("entregar_mision")
	r.append("adios")
	return r


static func texto_accion(accion: String, _npc: Npc) -> String:
	match accion:
		"tienda":
			return "Comprar y vender"
		"herreria":
			return "Mejorar herramientas"
		"comer":
			return "Comer aquí"
		"llevar":
			return "Comprar para llevar"
		"deuda":
			return "Abonar deuda de la finca (%s)" % Estilo.euros(Juego.deuda)
		"minerales":
			return "Vender minerales"
		"mina":
			return "Preguntar por la mina"
		"hablar":
			return "Hablar"
		"regalar":
			return "Regalar lo que llevo en la mano"
		"entregar_mision":
			var info := Misiones.paso_entregar_para(_npc.id)
			var titulo := str((info.get("mision", {}) as Dictionary).get("titulo", "misión"))
			return "Entregar (%s)" % titulo
	return "Adiós"


## Ejecuta una acción del menú (se puede llamar a mano, por ejemplo desde las pruebas).
static func ejecutar(accion: String, npc: Npc) -> void:
	if accion in ["tienda", "herreria", "comer", "llevar", "deuda", "minerales"] and not npc.en_lugar_trabajo():
		Interfaz.mostrar_dialogo(npc.nombre, ["Pásate por mi lugar de trabajo en mi horario de atención, Leo."])
		return
	match accion:
		"tienda":
			Interfaz.abrir_tienda(str(npc.datos.get("tienda", "tienda_mateo")))
		"herreria":
			Servicios.menu_herreria(npc.nombre)
		"comer":
			Servicios.menu_comer(npc.nombre)
		"llevar":
			Interfaz.abrir_tienda(str(npc.datos.get("tienda", "taberna")))
		"deuda":
			_menu_deuda(npc.nombre)
		"minerales":
			Servicios.menu_vender_minerales(npc.nombre)
		"mina":
			Servicios.charla_mina(npc.nombre)
		"hablar":
			charlar(npc)
		"regalar":
			regalar(npc)
		"entregar_mision":
			var res := Misiones.entregar_a_npc(npc.id)
			if bool(res.get("ok", false)):
				Interfaz.mostrar_dialogo(npc.nombre, [str(res.get("texto", ""))])


static func _menu_deuda(nombre_alcalde: String) -> void:
	if Juego.deuda <= 0:
		Interfaz.mostrar_dialogo(nombre_alcalde, ["La deuda de El Granado ya está completamente saldada, Leo."])
		return
	var cabecera := "Deuda pendiente sobre El Granado: %s (llevas abonados %s).\n¿Cuánto quieres amortizar hoy?" % [Estilo.euros(Juego.deuda), Estilo.euros(Juego.deuda_pagada())]
	var montos: Array[int] = []
	var opciones: Array = []
	for tramo: int in [500, 1500]:
		if Juego.dinero >= tramo and Juego.deuda > tramo:
			montos.append(tramo)
			opciones.append("Abonar %s" % Estilo.euros(tramo))
	if Juego.dinero >= Juego.deuda:
		montos.append(Juego.deuda)
		opciones.append("Saldar lo que falta (%s)" % Estilo.euros(Juego.deuda))
	elif Juego.dinero > 0:
		montos.append(Juego.dinero)
		opciones.append("Abonar todo mi dinero (%s)" % Estilo.euros(Juego.dinero))
	opciones.append("Más adelante")
	Interfaz.preguntar(cabecera, opciones, func(i: int) -> void:
		if i < 0 or i >= montos.size():
			return
		var abonado := Juego.pagar_deuda(montos[i])
		if abonado <= 0:
			Interfaz.mostrar_dialogo(nombre_alcalde, ["No llevas dinero suficiente encima para hacer un abono ahora mismo."])
		elif Juego.deuda <= 0:
			Interfaz.mostrar_dialogo(nombre_alcalde, [
				"Recibo extendido y sellado, Leo. Con este pago de %s, la deuda de cinco mil euros queda saldada para siempre." % Estilo.euros(abonado),
				"Villaverde de los Rosales entero respira hoy tranquilo. Tu abuela Rosa estaría orgullosa."
			])
		else:
			Interfaz.mostrar_dialogo(nombre_alcalde, [
				"Anotado en el registro municipal: %s menos de deuda. Ya solo quedan %s pendientes." % [Estilo.euros(abonado), Estilo.euros(Juego.deuda)]
			]))


# --- Hablar e historias personales --------------------------------------------------------------------

## Siguiente escena de la historia personal del vecino desbloqueada por amistad, o `{}` si no hay ninguna pendiente.
static func escena_pendiente(id: String) -> Dictionary:
	var h := _historias()
	var escenas_all: Variant = h.get("escenas", {})
	if not (escenas_all is Dictionary) or not (escenas_all as Dictionary).has(id):
		return {}
	var lista: Array = (escenas_all as Dictionary)[id]
	var umbrales: Array = h.get("umbrales", [20, 60, 110, 160])
	var reg: Dictionary = Juego.banderas.get("escenas_npc", {}) if Juego.banderas.get("escenas_npc", {}) is Dictionary else {}
	var vistas := int(reg.get(id, 0))
	if vistas >= lista.size() or vistas >= umbrales.size():
		return {}
	var pts := Juego.puntos_amistad(id)
	var umbral := int(umbrales[vistas])
	if pts < umbral:
		return {}
	var esc: Dictionary = (lista[vistas] as Dictionary).duplicate()
	esc["numero"] = vistas + 1
	return esc


static func escenas_vistas(id: String) -> int:
	var reg: Variant = Juego.banderas.get("escenas_npc", {})
	if not (reg is Dictionary):
		return 0
	return int((reg as Dictionary).get(id, 0))


static func _marcar_escena_vista(id: String, num: int) -> void:
	var reg: Dictionary = Juego.banderas.get("escenas_npc", {}) if Juego.banderas.get("escenas_npc", {}) is Dictionary else {}
	if num > int(reg.get(id, 0)):
		reg[id] = num
		Juego.banderas["escenas_npc"] = reg


## Charla normal: la primera vez cada día suma amistad. Devuelve la frase principal que dice.
static func charlar(npc: Npc) -> String:
	if not bool(Juego.hablado_hoy.get(npc.id, false)):
		Juego.hablado_hoy[npc.id] = true
		Juego.subir_amistad(npc.id, Juego.AMISTAD_POR_CHARLA)
		Juego.mensaje.emit("%s: +%d de amistad." % [npc.nombre, Juego.AMISTAD_POR_CHARLA])

	var extra_mision := Misiones.registrar_charla(npc.id)
	var esc := escena_pendiente(npc.id)
	if not esc.is_empty():
		var lineas: Array = (esc.get("lineas", []) as Array).duplicate()
		_marcar_escena_vista(npc.id, int(esc.get("numero", 1)))
		if not extra_mision.is_empty():
			lineas.append(extra_mision)
		Interfaz.mostrar_dialogo(npc.nombre, lineas)
		if not lineas.is_empty() and lineas[0] is Dictionary:
			return str((lineas[0] as Dictionary).get("texto", ""))
		return str(lineas[0]) if not lineas.is_empty() else ""

	var nivel := Juego.nivel_amistad(npc.id)
	var frase := frase_contextual(npc.id, nivel)
	var dialogo_lineas: Array = [frase]
	if not extra_mision.is_empty():
		dialogo_lineas.append(extra_mision)
	Interfaz.mostrar_dialogo(npc.nombre, dialogo_lineas)
	return frase


## Frase teniendo en cuenta festividades, lluvia y menciones a vecinos/deuda; conserva `frase_para` puro.
static func frase_contextual(id: String, nivel: int) -> String:
	var h := _historias()
	var fiesta := Juego.festividad_hoy()
	if not fiesta.is_empty():
		var fest_map: Dictionary = h.get("festividades", {}) as Dictionary
		var f_dia: Dictionary = fest_map.get(fiesta, {}) as Dictionary
		if f_dia.has(id):
			return _sin_repetir("%s_fiesta_%s" % [id, fiesta], f_dia[id] as Array)

	if Juego.esta_lloviendo():
		var lluvia_map: Dictionary = h.get("lluvia", {}) as Dictionary
		if lluvia_map.has(id):
			return _sin_repetir("%s_lluvia" % id, lluvia_map[id] as Array)

	# En el tramo 1+ de deuda o cuando ya hay confianza/amistad, alterna con frases sobre vecinos y la deuda actual.
	var deuda_map: Dictionary = h.get("vecinos_y_deuda", {}) as Dictionary
	var tramo := str(Juego.tramo_deuda())
	if (Juego.tramo_deuda() > 0 or Juego.puntos_amistad(id) > Juego.AMISTAD_POR_CHARLA) and deuda_map.has(id):
		var por_tramo: Dictionary = deuda_map[id] as Dictionary
		var pool: Array = []
		if Juego.tramo_deuda() > 0 and por_tramo.has(tramo):
			pool.append_array(por_tramo[tramo] as Array)
			pool.append_array(Datos.dialogos_npc(id, nivel))
			return _sin_repetir("%s_ctx_%d_%s" % [id, nivel, tramo], pool)
		elif por_tramo.has(tramo) and randi() % 3 == 0:
			return _sin_repetir("%s_deuda_%s" % [id, tramo], por_tramo[tramo] as Array)

	return frase_para(id, nivel)


## Frase del vecino para un nivel de amistad que no sea la misma que dijo la última vez en ese nivel.
static func frase_para(id: String, nivel: int) -> String:
	return _sin_repetir("%s_%d" % [id, nivel], Datos.dialogos_npc(id, nivel))


static func frase_de_relleno(npc: Npc) -> String:
	var h := _historias()
	var fiesta := Juego.festividad_hoy()
	if not fiesta.is_empty():
		var fest_map: Dictionary = h.get("festividades", {}) as Dictionary
		var f_dia: Dictionary = fest_map.get(fiesta, {}) as Dictionary
		if f_dia.has(npc.id):
			return _sin_repetir("%s_fiesta_%s" % [npc.id, fiesta], f_dia[npc.id] as Array)

	if Juego.esta_lloviendo():
		var lluvia_map: Dictionary = h.get("lluvia", {}) as Dictionary
		if lluvia_map.has(npc.id):
			return _sin_repetir("%s_lluvia" % npc.id, lluvia_map[npc.id] as Array)

	var frases: Array = (npc.datos.get("dialogos", []) as Array).duplicate()
	var tramo := str(Juego.tramo_deuda())
	var deuda_frases: Variant = npc.datos.get("dialogos_deuda", {})
	if Juego.tramo_deuda() > 0 and deuda_frases is Dictionary and (deuda_frases as Dictionary).has(tramo):
		return _sin_repetir("%s_relleno_d%s" % [npc.id, tramo], (deuda_frases as Dictionary)[tramo] as Array)
	return _sin_repetir("%s_relleno" % npc.id, frases)


static func _sin_repetir(clave: String, frases: Array) -> String:
	if frases.is_empty():
		return "..."
	var registro: Dictionary = Juego.banderas.get("frases", {})
	var ultima := int(registro.get(clave, -1))
	var indice := randi() % frases.size()
	if frases.size() > 1 and indice == ultima:
		indice = (indice + 1 + randi() % (frases.size() - 1)) % frases.size()
	registro[clave] = indice
	Juego.banderas["frases"] = registro
	return str(frases[indice])


# --- Regalar -----------------------------------------------------------------------------------------

## Puntos de amistad que daría un regalo a este vecino (0 si no se puede regalar eso).
static func puntos_de_regalo(npc: Npc, id_objeto: String) -> int:
	if Datos.objeto(id_objeto).get("tipo", "") == "herramienta":
		return 0
	if (npc.datos.get("gusta", []) as Array).has(id_objeto):
		return PUNTOS_GUSTA
	if (npc.datos.get("no_gusta", []) as Array).has(id_objeto):
		return PUNTOS_NO_GUSTA
	return PUNTOS_NEUTRO


static func regalar(npc: Npc) -> void:
	if bool(Juego.hablado_hoy.get("regalo_" + npc.id, false)):
		Interfaz.mostrar_dialogo(npc.nombre, ["Ya me has traído algo hoy, Leo. Con un detalle al día me doy por más que pagado."])
		return
	var activo := Juego.objeto_activo()
	if activo.is_empty():
		Interfaz.mostrar_dialogo(npc.nombre, ["Llevas las manos vacías. Elige en la barra rápida lo que quieras regalarme y vuelve a intentarlo."])
		return
	var id_objeto := str(activo["id"])
	if puntos_de_regalo(npc, id_objeto) == 0:
		Interfaz.mostrar_dialogo(npc.nombre, ["Las herramientas no se regalan, que luego te hacen falta. Quédatela."])
		return
	Interfaz.preguntar("¿Regalar %s a %s?" % [Datos.nombre_objeto(id_objeto).to_lower(), npc.nombre], [{"texto": "Sí, regalarlo", "icono": id_objeto}, "No"], func(i: int) -> void:
		if i == 0:
			entregar_regalo(npc, id_objeto))


## Hace el regalo (quita uno del inventario, sube o baja la amistad y el vecino reacciona). Devuelve los puntos.
static func entregar_regalo(npc: Npc, id_objeto: String) -> int:
	var puntos := puntos_de_regalo(npc, id_objeto)
	if puntos == 0 or not Juego.quitar_objeto(id_objeto, 1):
		return 0
	Juego.hablado_hoy["regalo_" + npc.id] = true
	Juego.subir_amistad(npc.id, puntos)
	TareasDiarias.registrar_progreso("regalar", 1)
	var nombre_obj := Datos.nombre_objeto(id_objeto).to_lower()
	var reaccion := ""
	if puntos == PUNTOS_GUSTA:
		reaccion = "¡%s! Justo lo que más me gusta. Gracias, Leo, de verdad." % (nombre_obj.substr(0, 1).to_upper() + nombre_obj.substr(1))
		Juego.mensaje.emit("A %s le encanta el regalo: +%d de amistad." % [npc.nombre, puntos])
	elif puntos < 0:
		reaccion = "Hombre... gracias por acordarte, pero %s no es lo mío. Te lo agradezco igual." % nombre_obj
		Juego.mensaje.emit("A %s no le gusta nada ese regalo: %d de amistad." % [npc.nombre, puntos])
	else:
		reaccion = "Vaya, %s. Qué detalle. Gracias." % nombre_obj
		Juego.mensaje.emit("%s agradece el detalle: +%d de amistad." % [npc.nombre, puntos])
	Interfaz.mostrar_dialogo(npc.nombre, [reaccion])
	return puntos
