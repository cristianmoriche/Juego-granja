extends Node
## Autoload «Misiones» (T22): misiones de historia ligadas a la deuda de 5.000 € y los vecinos.
## Guarda todo su progreso dentro de `Juego.banderas["misiones"]` para persistir con guardar/cargar.

signal actualizado
signal mision_completada(id: String)

const RUTA := "res://datos/misiones.json"
const ESTACIONES := ["Primavera", "Verano", "Otoño", "Invierno"]

var _definiciones: Array[Dictionary] = []
var _por_id: Dictionary = {}


func _ready() -> void:
	_cargar_definiciones()
	Juego.partida_cambiada.connect(_al_cambiar_partida)
	Juego.dia_nuevo.connect(func() -> void:
		TareasDiarias.al_empezar_dia()
		actualizado.emit())
	Juego.estacion_cambiada.connect(func() -> void: sincronizar())
	Juego.deuda_cambiada.connect(func(_d: int) -> void: sincronizar())
	Juego.inventario_cambiado.connect(func() -> void:
		_evaluar_todas_pasivas()
		actualizado.emit())
	Escenas.mapa_cargado.connect(_al_cargar_mapa)
	sincronizar(false)


func _cargar_definiciones() -> void:
	_definiciones.clear()
	_por_id.clear()
	if not FileAccess.file_exists(RUTA):
		push_warning("Misiones: no existe %s" % RUTA)
		return
	var f := FileAccess.open(RUTA, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Array):
		push_warning("Misiones: formato JSON inválido en %s" % RUTA)
		return
	for item: Variant in parsed:
		if item is Dictionary:
			var d: Dictionary = Datos.normalizar_numeros(item as Dictionary)
			var id := str(d.get("id", ""))
			if not id.is_empty():
				_definiciones.append(d)
				_por_id[id] = d


func _al_cambiar_partida() -> void:
	sincronizar(true)


func _al_cargar_mapa(id_mapa: String) -> void:
	registrar_visita(id_mapa)
	if id_mapa == "mina_interior":
		var nivel := int(Juego.banderas.get("nivel_mina", 1))
		registrar_nivel_mina(nivel)
	elif id_mapa == "pueblo" or id_mapa == "granja":
		sincronizar(false)


func _datos_guardados() -> Dictionary:
	var m: Variant = Juego.banderas.get("misiones", null)
	if not (m is Dictionary):
		m = {"activa": "", "estados": {}}
		Juego.banderas["misiones"] = m
	var d := m as Dictionary
	if not (d.get("estados", null) is Dictionary):
		d["estados"] = {}
	return d


func _estado_mut(id: String) -> Dictionary:
	var d := _datos_guardados()
	var estados := d["estados"] as Dictionary
	if not (estados.get(id, null) is Dictionary):
		estados[id] = {"paso": 0, "progreso": 0, "completada": false}
	return estados[id] as Dictionary


# --- Consultas públicas ---------------------------------------------------------------

func todas() -> Array[Dictionary]:
	return _definiciones


func mision(id: String) -> Dictionary:
	return _por_id.get(id, {})


func nombre_estacion(est: int) -> String:
	if est >= 0 and est < ESTACIONES.size():
		return ESTACIONES[est]
	return ""


func nombre_npc(npc_id: String) -> String:
	var n := Datos.npc(npc_id)
	return str(n.get("nombre", npc_id))


func esta_completada(id: String) -> bool:
	var d := _datos_guardados()
	var estados := d["estados"] as Dictionary
	if not (estados.get(id, null) is Dictionary):
		return false
	return bool((estados[id] as Dictionary).get("completada", false))


func desbloqueada(id: String) -> bool:
	var m := mision(id)
	if m.is_empty():
		return false
	if esta_completada(id):
		return true
	var est_req := int(m.get("estacion", 0))
	if Juego.estacion < est_req:
		return false
	var req := str(m.get("requiere", ""))
	if not req.is_empty() and not esta_completada(req):
		return false
	return true


func estado_de(id: String) -> Dictionary:
	if not _por_id.has(id):
		return {"paso": 0, "progreso": 0, "completada": false}
	return _estado_mut(id)


func paso_actual(id: String) -> Dictionary:
	var m := mision(id)
	if m.is_empty() or esta_completada(id):
		return {}
	var pasos: Array = m.get("pasos", [])
	var est := _estado_mut(id)
	var idx := int(est.get("paso", 0))
	if idx < 0 or idx >= pasos.size():
		return {}
	return pasos[idx] as Dictionary


func id_activa() -> String:
	var d := _datos_guardados()
	return str(d.get("activa", ""))


func mision_activa() -> Dictionary:
	var aid := id_activa()
	if aid.is_empty() or esta_completada(aid) or not desbloqueada(aid):
		_asegurar_activa()
		aid = id_activa()
	return mision(aid)


func activar_mision(id: String) -> bool:
	if not desbloqueada(id) or esta_completada(id):
		return false
	var d := _datos_guardados()
	d["activa"] = id
	actualizado.emit()
	return true


func en_curso() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	var aid := id_activa()
	if not aid.is_empty() and desbloqueada(aid) and not esta_completada(aid):
		r.append(mision(aid))
	for m: Dictionary in _definiciones:
		var mid := str(m["id"])
		if mid != aid and desbloqueada(mid) and not esta_completada(mid):
			r.append(m)
	return r


func completadas() -> Array[Dictionary]:
	var r: Array[Dictionary] = []
	for m: Dictionary in _definiciones:
		if esta_completada(str(m["id"])):
			r.append(m)
	return r


func progreso_paso(id: String) -> Vector2i:
	var p := paso_actual(id)
	if p.is_empty():
		return Vector2i(1, 1) if esta_completada(id) else Vector2i(0, 1)
	var tipo := str(p.get("tipo", ""))
	var obj := str(p.get("objetivo", ""))
	var total := maxi(int(p.get("cantidad", 1)), 1)
	var est := _estado_mut(id)
	match tipo:
		"cultivar":
			return Vector2i(mini(int(est.get("progreso", 0)), total), total)
		"entregar":
			return Vector2i(mini(Juego.cantidad(obj), total), total)
		"mina_nivel":
			var max_n := int(Juego.banderas.get("mina_max_nivel", 0))
			return Vector2i(mini(max_n, total), total)
		"pagar_deuda":
			return Vector2i(mini(Juego.deuda_pagada(), total), total)
		"hablar":
			return Vector2i(mini(int(est.get("progreso", 0)), 1), 1)
		"visitar":
			var visitadas: Dictionary = Juego.banderas.get("zonas_visitadas", {}) as Dictionary
			return Vector2i(1 if bool(visitadas.get(obj, false)) else 0, 1)
	return Vector2i(0, total)


func texto_recompensa(m: Dictionary) -> String:
	var rec: Dictionary = m.get("recompensa", {}) as Dictionary
	var partes: Array[String] = []
	var dinero := int(rec.get("dinero", 0))
	if dinero > 0:
		partes.append(Estilo.euros(dinero))
	var amistad := int(rec.get("amistad", 0))
	if amistad > 0:
		partes.append("+%d amistad" % amistad)
	for o: Variant in rec.get("objetos", []):
		if o is Dictionary:
			var od := o as Dictionary
			partes.append("%d× %s" % [int(od.get("cantidad", 1)), Datos.nombre_objeto(str(od.get("id", "")))])
	return ", ".join(partes)


# --- Progresión y ganchos -------------------------------------------------------------

func sincronizar(notificar: bool = true) -> void:
	_evaluar_todas_pasivas()
	_asegurar_activa()
	if notificar:
		actualizado.emit()


func registrar_cosecha(cultivo_id: String, cantidad: int = 1) -> void:
	if cantidad <= 0 or cultivo_id.is_empty():
		return
	var cambio := false
	for m: Dictionary in en_curso():
		var mid := str(m["id"])
		var p := paso_actual(mid)
		if p.get("tipo", "") == "cultivar" and str(p.get("objetivo", "")) == cultivo_id:
			var est := _estado_mut(mid)
			var total := maxi(int(p.get("cantidad", 1)), 1)
			est["progreso"] = mini(int(est.get("progreso", 0)) + cantidad, total)
			cambio = true
			if int(est["progreso"]) >= total:
				_avanzar_paso(mid)
	if cambio:
		_asegurar_activa()
		actualizado.emit()


func registrar_nivel_mina(nivel: int) -> void:
	var prev := int(Juego.banderas.get("mina_max_nivel", 0))
	if nivel > prev:
		Juego.banderas["mina_max_nivel"] = nivel
	sincronizar(true)


func registrar_visita(id_mapa: String) -> void:
	if id_mapa.is_empty():
		return
	var raw: Variant = Juego.banderas.get("zonas_visitadas", {})
	var dic: Dictionary = raw as Dictionary if raw is Dictionary else {}
	dic[id_mapa] = true
	Juego.banderas["zonas_visitadas"] = dic
	sincronizar(true)


func registrar_charla(npc_id: String) -> String:
	for m: Dictionary in en_curso():
		var mid := str(m["id"])
		var p := paso_actual(mid)
		if p.get("tipo", "") == "hablar" and str(p.get("objetivo", "")) == npc_id:
			var est := _estado_mut(mid)
			est["progreso"] = 1
			var era_ultimo := int(est.get("paso", 0)) + 1 >= (m.get("pasos", []) as Array).size()
			_avanzar_paso(mid)
			_asegurar_activa()
			actualizado.emit()
			if era_ultimo:
				return str(m.get("dialogo_fin", "Misión «%s» completada." % m.get("titulo", mid)))
			var siguiente := paso_actual(mid)
			return "Siguiente paso (%s): %s." % [m.get("titulo", mid), str(siguiente.get("texto", ""))]
	return ""


func paso_entregar_para(npc_id: String) -> Dictionary:
	for m: Dictionary in en_curso():
		var mid := str(m["id"])
		var p := paso_actual(mid)
		if p.get("tipo", "") == "entregar":
			var dest := str(p.get("destino", m.get("quien", "")))
			if dest == npc_id:
				var obj := str(p.get("objetivo", ""))
				var cant := maxi(int(p.get("cantidad", 1)), 1)
				if Juego.cantidad(obj) >= cant:
					return {"mision": m, "paso": p}
	return {}


func entregar_a_npc(npc_id: String) -> Dictionary:
	var info := paso_entregar_para(npc_id)
	if info.is_empty():
		return {"ok": false}
	var m: Dictionary = info["mision"]
	var p: Dictionary = info["paso"]
	var mid := str(m["id"])
	var obj := str(p.get("objetivo", ""))
	var cant := maxi(int(p.get("cantidad", 1)), 1)
	if not Juego.quitar_objeto(obj, cant):
		return {"ok": false}
	var est := _estado_mut(mid)
	var era_ultimo := int(est.get("paso", 0)) + 1 >= (m.get("pasos", []) as Array).size()
	est["progreso"] = cant
	_avanzar_paso(mid)
	_asegurar_activa()
	actualizado.emit()
	var msg := ""
	if era_ultimo:
		msg = str(m.get("dialogo_fin", "Gracias por la entrega, Leo."))
	else:
		msg = "Entrega recibida (%s). Siguiente paso: %s" % [m.get("titulo", mid), str(paso_actual(mid).get("texto", ""))]
	return {"ok": true, "completada": era_ultimo, "titulo": str(m.get("titulo", mid)), "texto": msg}


func _evaluar_todas_pasivas() -> void:
	for m: Dictionary in _definiciones:
		var mid := str(m["id"])
		if desbloqueada(mid) and not esta_completada(mid):
			_evaluar_pasos_pasivos_de(mid)


func _evaluar_pasos_pasivos_de(id: String) -> void:
	var m := mision(id)
	var pasos: Array = m.get("pasos", [])
	for _i in pasos.size():
		if esta_completada(id):
			break
		var p := paso_actual(id)
		if p.is_empty():
			break
		var tipo := str(p.get("tipo", ""))
		var cant := maxi(int(p.get("cantidad", 1)), 1)
		var cumplido := false
		if tipo == "mina_nivel":
			cumplido = int(Juego.banderas.get("mina_max_nivel", 0)) >= cant
		elif tipo == "pagar_deuda":
			cumplido = Juego.deuda_pagada() >= cant
		elif tipo == "visitar":
			var visitadas: Dictionary = Juego.banderas.get("zonas_visitadas", {}) as Dictionary
			cumplido = bool(visitadas.get(str(p.get("objetivo", "")), false))
		if not cumplido:
			break
		_avanzar_paso(id, false)


func _avanzar_paso(id: String, evaluar_pasivos: bool = true) -> void:
	var m := mision(id)
	if m.is_empty():
		return
	var pasos: Array = m.get("pasos", [])
	var est := _estado_mut(id)
	var nuevo_paso := int(est.get("paso", 0)) + 1
	est["progreso"] = 0
	if nuevo_paso >= pasos.size():
		est["paso"] = pasos.size()
		est["completada"] = true
		_dar_recompensa(m)
		mision_completada.emit(id)
	else:
		est["paso"] = nuevo_paso
		if evaluar_pasivos:
			_evaluar_pasos_pasivos_de(id)


func _dar_recompensa(m: Dictionary) -> void:
	var rec: Dictionary = m.get("recompensa", {}) as Dictionary
	var dinero := int(rec.get("dinero", 0))
	if dinero > 0:
		Juego.ingresar(dinero)
		if is_instance_valid(Interfaz):
			Interfaz.mostrar_dinero_flotante(dinero)
	var amistad := int(rec.get("amistad", 0))
	var quien := str(m.get("quien", ""))
	if amistad > 0 and not quien.is_empty():
		Juego.subir_amistad(quien, amistad)
	for o: Variant in rec.get("objetos", []):
		if o is Dictionary:
			var od := o as Dictionary
			var oid := str(od.get("id", ""))
			var ocant := int(od.get("cantidad", 1))
			if not oid.is_empty() and ocant > 0:
				Juego.anadir_objeto(oid, ocant)
	var resumen := texto_recompensa(m)
	var titulo := str(m.get("titulo", m.get("id", "")))
	Juego.mensaje.emit("Misión completada: «%s» (%s)" % [titulo, resumen])


func _asegurar_activa() -> void:
	var d := _datos_guardados()
	var aid := str(d.get("activa", ""))
	if not aid.is_empty() and desbloqueada(aid) and not esta_completada(aid):
		return
	d["activa"] = ""
	for m: Dictionary in _definiciones:
		var mid := str(m["id"])
		if desbloqueada(mid) and not esta_completada(mid):
			d["activa"] = mid
			return
