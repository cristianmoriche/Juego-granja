extends Node
## Prueba de la granja (L4a). Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_l4a.tscn
## Imprime «PRUEBA OK» o «PRUEBA FALLO: <motivo>» y sale con 0 o 1.

var _fallos: Array[String] = []
var _avisos: Array[String] = []
var _eventos: Dictionary = {}
var _p: Parcelas = null
var _j: Node3D = null


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _terminar() -> void:
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)))
		get_tree().quit(1)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null     # Escenas descarta la escena actual al cambiar de mapa
	Juego.ruta_partida = "user://partida_prueba_l4a.json"
	Juego.mensaje.connect(func(t: String) -> void: _avisos.append(t))
	Juego.nueva_partida("Prueba")
	Juego.dia_nuevo.connect(func() -> void: _eventos["lluvias"] = int(_eventos.get("lluvias", 0)) + (1 if Juego.clima == "lluvia" else 0))
	Escenas.mapa_cargado.connect(func(_i: String) -> void: _eventos["mapa"] = int(_eventos.get("mapa", 0)) + 1)

	print("[carga de la granja]")
	await Escenas.ir_a_mapa("granja")
	await _frames(3)
	var mapa := Escenas.mapa_actual_nodo()
	_comprobar(mapa != null and str(mapa.name) == "Granja", "el mapa actual debe ser la granja")
	_p = mapa.get_node_or_null("Objetos/Parcelas") as Parcelas if mapa != null else null
	_j = Escenas.jugador()
	_comprobar(_p != null, "falta Objetos/Parcelas en la granja")
	_comprobar(_j != null, "no hay jugador en la granja")
	if _p == null or _j == null:
		_terminar()
		return
	_prueba_rejilla()
	_prueba_herramientas()
	await _frames(2)
	await _prueba_crecimiento_y_cosecha()
	_prueba_reglas()
	_prueba_guardado()
	await _prueba_dormir()
	_terminar()


# Primera clave de la zona con ese estado y sin cultivo ("" si no hay).
func _buscar(estado: String) -> String:
	for k: String in _p.claves():
		var c := Cultivos.parcela(k)
		if str(c.get("estado", "")) == estado and str(c.get("cultivo", "")) == "":
			return k
	return ""


func _usar(id: String, k: String) -> bool:
	return _p.usar(id, _p.posicion_de(k), _j)


func _estado(k: String) -> String:
	return str(Cultivos.parcela(k).get("estado", "?"))


func _hubo_aviso(trozo: String) -> bool:
	for a in _avisos:
		if trozo in a:
			return true
	return false


func _prueba_rejilla() -> void:
	print("[rejilla]")
	var n := Cultivos.contar()
	_comprobar(_p.esta_construida(), "Parcelas no se ha construido")
	_comprobar(n >= 40, "pocas casillas: %d" % n)
	var f_maleza := float(Cultivos.contar("maleza")) / float(maxi(n, 1))
	var f_piedra := float(Cultivos.contar("piedra")) / float(maxi(n, 1))
	var f_tronco := float(Cultivos.contar("tronco")) / float(maxi(n, 1))
	print("  casillas %d · maleza %.2f piedra %.2f tronco %.2f limpio %d" % [n, f_maleza, f_piedra, f_tronco, Cultivos.contar("limpio")])
	_comprobar(absf(f_maleza - 0.55) < 0.06, "reparto de maleza fuera de rango")
	_comprobar(absf(f_piedra - 0.10) < 0.06, "reparto de piedras fuera de rango")
	_comprobar(absf(f_tronco - 0.07) < 0.05, "reparto de troncos fuera de rango")
	_comprobar(Cultivos.contar("limpio") > 0, "debe haber casillas limpias")
	_comprobar(_p.is_in_group("usable"), "Parcelas debe estar en el grupo usable")
	# L5: la puerta de la cabaña lleva a casa_leo y la cama («Dormir en la cama») vive dentro de casa_leo.
	var puerta_cab := Escenas.mapa_actual_nodo().get_node_or_null("Salidas/Puerta_casa_leo")
	_comprobar(puerta_cab != null and puerta_cab.is_in_group("interactuable") and str(puerta_cab.call("texto_interaccion")) == "Entrar en la cabaña", "la puerta de la cabaña debe ofrecer Entrar en la cabaña")
	# Fuera de las zonas no pasa nada.
	_comprobar(not _p.usar("hoz", Vector3(500, 0, 500), _j), "usar lejos de las parcelas debe devolver false")


func _prueba_herramientas() -> void:
	print("[herramientas]")
	var e0 := Juego.energia
	# Hoz sobre maleza.
	var km := _buscar("maleza")
	_comprobar(not km.is_empty(), "no hay maleza")
	var fibra0 := Juego.cantidad("fibra")
	_comprobar(_usar("hoz", km), "la hoz debe segar la maleza")
	_comprobar(_estado(km) == "limpio", "la maleza segada queda limpia")
	_comprobar(Juego.cantidad("fibra") > fibra0, "la maleza da fibra")
	_comprobar(absf((e0 - Juego.energia) - 2.0) < 0.01, "la hoz de nivel 0 gasta 2 de energía (gastó %.2f)" % (e0 - Juego.energia))
	# Herramienta equivocada: aviso y nada.
	var kp := _buscar("piedra")
	_comprobar(not kp.is_empty(), "no hay piedras")
	_avisos.clear()
	_comprobar(not _usar("hoz", kp) and _estado(kp) == "piedra", "la hoz no rompe piedras")
	_comprobar(_hubo_aviso("pico"), "aviso de que la piedra pide el pico")
	# Pico: 2 golpes.
	_comprobar(_usar("pico", kp) and _estado(kp) == "piedra", "el primer picotazo no la rompe")
	var piedra0 := Juego.cantidad("piedra")
	_comprobar(_usar("pico", kp) and _estado(kp) == "limpio", "el segundo picotazo rompe la piedra")
	var dp := Juego.cantidad("piedra") - piedra0
	_comprobar(dp >= 1 and dp <= 3, "la piedra da 1 a 3 (dio %d)" % dp)
	# Hacha: 3 golpes.
	var kt := _buscar("tronco")
	_comprobar(not kt.is_empty(), "no hay troncos")
	_usar("hacha", kt)
	_usar("hacha", kt)
	_comprobar(_estado(kt) == "tronco", "dos hachazos no bastan")
	var madera0 := Juego.cantidad("madera")
	_usar("hacha", kt)
	_comprobar(_estado(kt) == "limpio", "el tercer hachazo parte el tronco")
	var dm := Juego.cantidad("madera") - madera0
	_comprobar(dm >= 2 and dm <= 4, "el tronco da 2 a 4 de madera (dio %d)" % dm)
	# Azada, semilla de otra estación, semilla buena y regadera.
	var kl := _buscar("limpio")
	_comprobar(_usar("azada", kl) and _estado(kl) == "arado", "la azada ara lo limpio")
	Juego.anadir_objeto("semilla_tomate", 2)
	_avisos.clear()
	_comprobar(not _usar("semilla_tomate", kl), "no se siembra una semilla de otra estación")
	_comprobar(str(Cultivos.parcela(kl).get("cultivo", "")) == "" and Juego.cantidad("semilla_tomate") == 2, "la semilla fuera de estación no se gasta ni se planta")
	_comprobar(_hubo_aviso("no es de"), "aviso Esta semilla no es de ...")
	var s0 := Juego.cantidad("semilla_patata")
	_comprobar(_usar("semilla_patata", kl), "se siembra la patata")
	_comprobar(str(Cultivos.parcela(kl).get("cultivo", "")) == "patata" and Juego.cantidad("semilla_patata") == s0 - 1, "la patata queda plantada y gasta una semilla")
	_comprobar(_usar("regadera", kl) and bool(Cultivos.parcela(kl).get("regado", false)), "la regadera riega lo arado")
	_comprobar(not _usar("regadera", kl), "regar dos veces no hace nada")
	_eventos["cultivo"] = kl
	# Segunda patata, sin regar nunca (control).
	var kl2 := _buscar("limpio")
	_usar("azada", kl2)
	_usar("semilla_patata", kl2)
	_eventos["control"] = kl2
	_comprobar(str(Cultivos.parcela(kl2).get("cultivo", "")) == "patata", "segunda patata plantada")
	# Sin energía: nada.
	var km2 := _buscar("maleza")
	Juego.energia = 0.5
	_comprobar(not _usar("hoz", km2) and _estado(km2) == "maleza", "sin energía no se hace nada")
	Juego.energia = Juego.energia_max
	# Nivel 1: azada y regadera en línea de 3 casillas, 1,5 de energía.
	var z0: Dictionary = _p._zonas[0]
	var nombre := str(z0["nombre"])
	var zz := -1
	for z in int(z0["nz"]):
		var libre := true
		for x in 3:
			var kk := Cultivos.clave(nombre, x, z)
			if _estado(kk) == "arado" or str(Cultivos.parcela(kk).get("cultivo", "")) != "":
				libre = false
		if libre:
			zz = z
			break
	_comprobar(zz >= 0, "no hay hueco para probar la línea")
	if zz >= 0:
		for x in 3:
			Cultivos.parcela(Cultivos.clave(nombre, x, zz))["estado"] = "limpio"
		Juego.nivel_herramientas["azada"] = 1
		Juego.nivel_herramientas["regadera"] = 1
		_j.set("direccion", Basis(Vector3.UP, float(z0["yaw"])) * Vector3.RIGHT)
		var base_k := Cultivos.clave(nombre, 0, zz)
		var e1 := Juego.energia
		_comprobar(_usar("azada", base_k), "azada de nivel 1")
		_comprobar(absf((e1 - Juego.energia) - 1.5) < 0.01, "azada de nivel 1 gasta 1,5 (gastó %.2f)" % (e1 - Juego.energia))
		var aradas := 0
		for x in 3:
			if _estado(Cultivos.clave(nombre, x, zz)) == "arado":
				aradas += 1
		_comprobar(aradas == 3, "la azada de nivel 1 ara 3 casillas en línea (aradas %d)" % aradas)
		_comprobar(_usar("regadera", base_k), "regadera de nivel 1")
		var regadas := 0
		for x in 3:
			if bool(Cultivos.parcela(Cultivos.clave(nombre, x, zz)).get("regado", false)):
				regadas += 1
		_comprobar(regadas == 3, "la regadera de nivel 1 riega 3 casillas (regadas %d)" % regadas)
		Juego.nivel_herramientas["azada"] = 0
		Juego.nivel_herramientas["regadera"] = 0
	# Pico de nivel 1: una sola pedrada.
	Juego.nivel_herramientas["pico"] = 1
	var kp2 := _buscar("piedra")
	if not kp2.is_empty():
		_usar("pico", kp2)
		_comprobar(_estado(kp2) == "limpio", "con el pico de nivel 1 la piedra cede a la primera")
	Juego.nivel_herramientas["pico"] = 0
	Juego.energia = Juego.energia_max


func _prueba_crecimiento_y_cosecha() -> void:
	print("[crecimiento y cosecha]")
	var k: String = _eventos.get("cultivo", "")
	var control: String = _eventos.get("control", "")
	_comprobar(not k.is_empty(), "no hay cultivo de la prueba anterior")
	if k.is_empty():
		return
	var dia0 := Juego.dia
	for i in 5:
		_comprobar(not Cultivos.esta_listo(k), "no puede estar listo antes de tiempo (noche %d)" % i)
		_usar("regadera", k)                # (si llovió, ya estaba regado)
		_comprobar(bool(Cultivos.parcela(k).get("regado", false)), "regado antes de dormir")
		Juego.terminar_dia()
	_comprobar(Juego.dia == dia0 + 5, "han pasado 5 días")
	await _frames(3)
	_comprobar(Cultivos.esta_listo(k), "la patata debe estar lista a los 5 días regada")
	var lluvias := int(_eventos.get("lluvias", 0))
	_comprobar(not Cultivos.esta_listo(control) and int(Cultivos.parcela(control).get("dias", 0)) <= lluvias, "lo no regado solo crece los días de lluvia (%d)" % lluvias)
	_comprobar(_p.cosechables() == 1, "debe haber un cultivo cosechable (hay %d)" % _p.cosechables())
	var proxy: Node = null
	for n in get_tree().get_nodes_in_group("interactuable"):
		if n.get("clave") == k:
			proxy = n
	_comprobar(proxy != null, "falta el interactuable del cultivo listo")
	if proxy != null:
		_comprobar(str(proxy.call("texto_interaccion")) == "Cosechar patatas", "texto Cosechar patatas (es %s)" % str(proxy.call("texto_interaccion")))
		var antes := Juego.cantidad("patata")
		proxy.call("interactuar", _j)
		_comprobar(Juego.cantidad("patata") > antes, "hay patatas en el inventario")
		_comprobar(int(Juego.estadisticas.get("cosechado", 0)) >= 1, "estadisticas[cosechado]")
		_comprobar(str(Cultivos.parcela(k).get("cultivo", "?")) == "", "la patata cosechada se quita (sin rebrote)")
	await _frames(3)
	_comprobar(_p.cosechables() == 0, "ya no hay cosechables")


func _prueba_reglas() -> void:
	print("[reglas]")
	var k := _buscar("limpio")
	var c := Cultivos.parcela(k)
	# Lluvia: riega todo lo arado.
	c["estado"] = "arado"
	c["regado"] = false
	Juego.clima = "lluvia"
	Cultivos.procesar_dia()
	_comprobar(bool(c["regado"]), "la lluvia riega lo arado")
	# Sol: lo arado sin sembrar vuelve a limpio a los 3 días secos.
	c["regado"] = false
	c["dias"] = 0
	Juego.clima = "sol"
	for i in 3:
		Cultivos.procesar_dia()
	_comprobar(str(c["estado"]) == "limpio", "lo arado y seco vuelve a limpio a los 3 días (es %s)" % str(c["estado"]))
	# Marchitar fuera de estación.
	c["estado"] = "arado"
	c["cultivo"] = "patata"
	c["etapa"] = 1
	c["dias"] = 2
	c["listo"] = false
	Juego.estacion = 1
	Cultivos.procesar_dia()
	Juego.estacion = 0
	_comprobar(str(c["cultivo"]) == "" and str(c["estado"]) == "arado", "una patata se marchita en verano")
	Cultivos.marchitos_pendientes = 0
	# Rebrote: la haba (6 días, rebrota 3) vuelve 3 días atrás.
	c["cultivo"] = "haba"
	c["listo"] = true
	c["dias"] = 6
	c["etapa"] = 3
	_comprobar(not Cultivos.cosechar("no:existe:0"), "cosechar una clave inexistente da false")
	_comprobar(Cultivos.cosechar(k), "se cosecha la haba")
	_comprobar(str(c["cultivo"]) == "haba" and not bool(c["listo"]) and int(c["dias"]) == 3, "la haba rebrota 3 días atrás")
	# Mochila llena: no se cosecha.
	c["cultivo"] = "patata"
	c["listo"] = true
	c["dias"] = 5
	var copia: Array = Juego.inventario.duplicate(true)
	for i in Juego.inventario.size():
		Juego.inventario[i] = {"id": "cuarzo", "cantidad": 99}
	_avisos.clear()
	_comprobar(not Cultivos.cosechar(k) and bool(c["listo"]), "con la mochila llena no se cosecha")
	_comprobar(_hubo_aviso("mochila"), "aviso de mochila llena")
	Juego.inventario = copia
	c["cultivo"] = ""
	c["listo"] = false
	c["dias"] = 0
	c["etapa"] = 0
	c["estado"] = "limpio"


func _prueba_guardado() -> void:
	print("[guardado]")
	_comprobar(Juego.guardar(), "se guarda la partida")
	var antes: Dictionary = Cultivos.parcelas().duplicate(true)
	Juego.estado_mapas = {}
	_comprobar(Cultivos.parcelas().is_empty(), "al vaciar el estado no hay parcelas")
	_comprobar(Juego.cargar(), "se carga la partida")
	var despues := Cultivos.parcelas()
	_comprobar(despues.size() == antes.size(), "mismo número de parcelas tras cargar (%d / %d)" % [despues.size(), antes.size()])
	var distintas := 0
	for k: Variant in antes:
		var a: Dictionary = antes[k]
		var b: Dictionary = despues.get(k, {})
		for campo: Variant in a:
			if str(a[campo]) != str(b.get(campo, "<falta>")) or typeof(a[campo]) != typeof(b.get(campo)):
				distintas += 1
	_comprobar(distintas == 0, "las parcelas cargadas son iguales (%d campos distintos)" % distintas)


func _prueba_dormir() -> void:
	print("[dormir]")
	await Escenas.ir_a_mapa("casa_leo", "Entrada")
	await _frames(3)
	var interior := Escenas.mapa_actual_nodo()
	var cama := interior.get_node_or_null("Objetos/Cama/PuntoDormir") if interior != null else null
	_comprobar(cama != null and cama.is_in_group("interactuable") and str(cama.call("texto_interaccion")) == "Dormir en la cama", "la cama en casa_leo debe ofrecer Dormir en la cama")
	var dia0 := Juego.dia
	var n0 := Cultivos.contar()
	var mapas0 := int(_eventos.get("mapa", 0))
	Juego.dormir()
	var t0 := Time.get_ticks_msec()
	while int(_eventos.get("mapa", 0)) == mapas0 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _frames(4)
	_comprobar(Juego.dia == dia0 + 1, "dormir pasa al día siguiente")
	var mapa := Escenas.mapa_actual_nodo()
	_comprobar(mapa != null and str(mapa.name) == "Granja", "se despierta en la granja")
	var p2 := mapa.get_node_or_null("Objetos/Parcelas") as Parcelas if mapa != null else null
	_comprobar(p2 != null and p2.esta_construida(), "la granja recargada vuelve a construir las parcelas")
	_comprobar(Cultivos.contar() == n0, "las parcelas siguen ahí tras dormir")
	var j := Escenas.jugador()
	var spawn: Marker3D = mapa.call("marcador", "Spawn_Protagonista") as Marker3D if mapa != null else null
	if j != null and spawn != null:
		_comprobar(j.global_position.distance_to(spawn.global_position) < 1.5, "Leo despierta junto a Spawn_Protagonista")
