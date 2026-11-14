extends Node
## Recorrido completo en una ejecución; herramientas/prueba_final.ps1 añade un cierre real del proceso.
## Usa escenas, botones, puertas, herramientas, servicios y guardados del juego.
## Preparaciones explícitas: posición ante objetos, reloj detenido, calendario acelerado
## y condiciones económicas/sociales de cada final. No mide navegación ni equilibrio.

var _carpeta := ""
var _capturas := ""
var _fase := "completa"
var _sesion := "directa"
var _pasos: Array = []
var _terminada := false
var _inicio_ms := 0
var _ultimo_paso := "arranque"
var _clave_cultivo := ""
var _ruta_base := ""
var _pasos_previos := 0
var _superados_previos := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inicio_ms = Time.get_ticks_msec()
	for argumento in OS.get_cmdline_user_args():
		if argumento.begins_with("--carpeta="):
			_carpeta = argumento.trim_prefix("--carpeta=")
		elif argumento.begins_with("--capturas="):
			_capturas = argumento.trim_prefix("--capturas=")
		elif argumento.begins_with("--fase="):
			_fase = argumento.trim_prefix("--fase=")
		elif argumento.begins_with("--sesion="):
			_sesion = argumento.trim_prefix("--sesion=")
	if _carpeta.is_empty():
		_carpeta = ProjectSettings.globalize_path("res://../gestion/noche-codex/datos/T04-recorrido/directa")
	DirAccess.make_dir_recursive_absolute(_carpeta)
	_ruta_base = _carpeta.path_join("partida.json")
	Juego.ruta_partida = _ruta_base
	_ejecutar.call_deferred()


func _process(_delta: float) -> void:
	# Un error de script o una señal que nunca llega no puede dejar el proceso abierto.
	if not _terminada and Time.get_ticks_msec() - _inicio_ms > 900000:
		_comprobar(false, "Tiempo máximo de la fase; último paso: " + _ultimo_paso)
		_terminar()


func _comprobar(condicion: bool, texto: String) -> bool:
	_ultimo_paso = texto
	_pasos.append({"paso": texto, "superado": condicion})
	print("PASO %d %s: %s" % [_pasos_previos + _pasos.size(), "OK" if condicion else "FALLO", texto])
	return condicion


func _escribir(nombre: String, datos: Variant) -> bool:
	var archivo := FileAccess.open(_carpeta.path_join(nombre), FileAccess.WRITE)
	if archivo == null:
		_comprobar(false, "Escribir " + nombre)
		return false
	archivo.store_string(JSON.stringify(datos, "\t"))
	archivo.close()
	return true


func _leer(nombre: String) -> Dictionary:
	var datos: Variant = JSON.parse_string(FileAccess.get_file_as_string(_carpeta.path_join(nombre)))
	return datos if datos is Dictionary else {}


func _informe() -> Dictionary:
	var fallos := 0
	for paso: Dictionary in _pasos:
		if not paso.superado:
			fallos += 1
	return {"fase": _fase, "sesion": _sesion, "pid": OS.get_process_id(),
		"superados": _pasos.size() - fallos, "fallidos": fallos, "pasos": _pasos,
		"segundos": (Time.get_ticks_msec() - _inicio_ms) / 1000.0}


func _terminar() -> void:
	if _terminada:
		return
	_terminada = true
	var informe := _informe()
	var escrito := _escribir("resultado_" + _fase + ".json", informe)
	print("PRUEBA FINAL: %d de %d pasos" % [_superados_previos + informe.superados, _pasos_previos + _pasos.size()])
	get_tree().quit(0 if informe.fallidos == 0 and escrito else 1)


func _esperar(condicion: Callable, descripcion: String, segundos: float = 60.0) -> bool:
	var limite := Time.get_ticks_msec() + int(segundos * 1000.0)
	while not condicion.call() and Time.get_ticks_msec() < limite:
		await get_tree().process_frame
	return _comprobar(bool(condicion.call()), descripcion)


func _transicion() -> bool:
	await get_tree().process_frame
	return await _esperar(func() -> bool: return not Escenas.en_transicion, "Termina la transición")


func _escena(ruta: String) -> bool:
	if not await _transicion():
		return false
	return _comprobar(get_tree().current_scene != null and get_tree().current_scene.scene_file_path == ruta,
		"Escena " + ruta.get_file())


func _mapa(id: String) -> bool:
	if not await _transicion():
		return false
	var mapa := Escenas.mapa_actual_nodo() as Mapa
	if not _comprobar(mapa != null and mapa.id_mapa == id and mapa.esta_listo, "Mapa listo: " + id):
		return false
	var j := Escenas.jugador() as Jugador
	if not _comprobar(j != null, "Leo presente: " + id):
		return false
	await _esperar(func() -> bool: return j.is_on_floor(), "Suelo bajo Leo: " + id, 5.0)
	_comprobar(j.dentro_de_limites() and j.atascos_resueltos == 0, "Llegada dentro del mapa y sin rescate: " + id)
	_comprobar(j.camara != null and j.camara.camara.is_current(), "Cámara activa: " + id)
	var mini := Interfaz.find_child("Minimapa", true, false) as Minimapa
	_comprobar(mini != null and mini.id_mapa == id and mini.jugador == j, "Minimapa asociado: " + id)
	return true


func _capturar(nombre: String) -> void:
	if _capturas.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_capturas)
	var dialogo := Interfaz.get_node("Raiz/Dialogo") as PanelDialogo
	if dialogo.visible and dialogo._texto.visible_characters < dialogo._texto.get_total_character_count():
		# La misma pulsación que revela la frase permite leerla entera en la captura.
		dialogo._avanzar()
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	_comprobar(get_viewport().get_texture().get_image().save_png(_capturas.path_join(nombre + ".png")) == OK,
		"Captura " + nombre)


func _boton(raiz: Node, texto: String) -> bool:
	for nodo in raiz.find_children("*", "Button", true, false):
		var b := nodo as Button
		if b.text == texto and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return _comprobar(true, "Pulsar «%s»" % texto)
	return _comprobar(false, "Botón disponible «%s»" % texto)


func _elegir(indice: int) -> bool:
	var pregunta := Interfaz.get_node("Raiz/Pregunta") as PanelPregunta
	if not _comprobar(pregunta.visible and indice >= 0 and indice < pregunta._botones.size(), "Opción de diálogo %d disponible" % (indice + 1)):
		return false
	# Deja que se complete el enfoque diferido antes de sustituir una pregunta.
	await get_tree().process_frame
	pregunta._botones[indice].pressed.emit()
	return true


func _cerrar_dialogo() -> void:
	var dialogo := Interfaz.get_node("Raiz/Dialogo") as PanelDialogo
	for i in 30:
		if not dialogo.visible:
			break
		dialogo._avanzar()
		await get_tree().process_frame
	_comprobar(not dialogo.visible and not Interfaz.ocupada(), "Diálogo cerrado y control recuperado")


func _cruzar(destino: String) -> bool:
	Interfaz.cerrar_todo()
	var j := Escenas.jugador() as Jugador
	for nodo in get_tree().get_nodes_in_group("puerta"):
		if nodo is PuertaMapa and nodo.destino == destino:
			_comprobar(not nodo.texto_interaccion().is_empty(), "Puerta disponible hacia " + destino)
			nodo.interactuar(j)
			return await _mapa(destino)
	for nodo in get_tree().get_nodes_in_group("salida"):
		if nodo is Salida and nodo.destino == destino:
			# Entra físicamente en el Area3D; no llama a Escenas como sustituto de la salida.
			await get_tree().create_timer(0.8).timeout
			j.colocar(nodo.global_position + Vector3(0, 0.15, 0), 0.0, j.camara.yaw)
			if not await _esperar(func() -> bool: return Escenas.en_transicion, "Se activa el camino hacia " + destino, 5.0):
				return false
			return await _mapa(destino)
	return _comprobar(false, "Conexión disponible hacia " + destino)


func _parcelas() -> Parcelas:
	for nodo in get_tree().get_nodes_in_group("usable"):
		if nodo is Parcelas:
			return nodo
	return null


func _usar_cultivo(objeto: String) -> void:
	var p := _parcelas()
	var j := Escenas.jugador() as Jugador
	var pos := p.posicion_de(_clave_cultivo)
	j.colocar(pos - Vector3(0, -0.05, 1.2), 0.0, j.camara.yaw)
	_seleccionar(objeto)
	await get_tree().create_timer(0.65).timeout
	# El punto delante de Leo y el despachador de herramientas son los del jugador.
	j.colocar(pos - Vector3(0, -0.05, 1.2), 0.0, j.camara.yaw)
	j._usar()
	await get_tree().process_frame


func _seleccionar(objeto: String) -> bool:
	for i in Juego.inventario.size():
		if Juego.inventario[i].get("id", "") == objeto:
			if i >= 10:
				Juego.mover_huecos(i, 9)
				i = 9
			Juego.elegir_ranura(i)
			return _comprobar(Juego.objeto_activo().get("id") == objeto, "Seleccionar " + objeto)
	return _comprobar(false, "Objeto disponible: " + objeto)


func _dormir_en_cama() -> bool:
	for nodo in get_tree().get_nodes_in_group("interactuable"):
		if nodo.name == "PuntoDormir":
			nodo.interactuar(Escenas.jugador())
			await _elegir(0)
			return await _transicion()
	return _comprobar(false, "Cama interactuable disponible")


func _agricultura() -> bool:
	var parcelas := _parcelas()
	if not _comprobar(parcelas != null and parcelas.esta_construida(), "Parcelas de la granja construidas"):
		return false
	for clave: String in parcelas.claves():
		if Cultivos.parcela(clave).estado == "limpio":
			_clave_cultivo = clave
			break
	if not _comprobar(not _clave_cultivo.is_empty(), "Casilla libre para cultivar"):
		return false
	var energia := Juego.energia
	await _usar_cultivo("azada")
	_comprobar(Cultivos.parcela(_clave_cultivo).estado == "arado" and Juego.energia < energia, "Labrar consume energía y prepara la tierra")
	var semillas := Juego.cantidad("semilla_patata")
	await _usar_cultivo("semilla_patata")
	_comprobar(Cultivos.parcela(_clave_cultivo).cultivo == "patata" and Juego.cantidad("semilla_patata") == semillas - 1, "Sembrar consume una semilla de patata")
	for dia in int(Datos.cultivo("patata").dias):
		if not Cultivos.parcela(_clave_cultivo).regado:
			await _usar_cultivo("regadera")
		_comprobar(Cultivos.parcela(_clave_cultivo).regado, "Riego del cultivo: día %d" % (dia + 1))
		if dia == 0:
			await _capturar("01_cultivo_regado")
		if not await _cruzar("casa_leo"):
			return false
		var fecha := Juego.dia
		if not await _dormir_en_cama() or not await _mapa("granja"):
			return false
		_comprobar(Juego.dia == fecha + 1 and Juego.energia == Juego.energia_max, "Dormir avanza un día y recupera energía")
		var guardado := Juego.leer_archivo(Juego.ruta_partida)
		_comprobar(guardado.get("mapa_actual") == Juego.mapa_actual, "Autoguardado al despertar conserva el mapa de llegada")
		var posicion: Array = guardado.get("posicion", [])
		_comprobar(posicion.size() == 3 and Vector3(posicion[0], posicion[1], posicion[2]).distance_to(Escenas.jugador().global_position) < 0.3,
			"Autoguardado al despertar conserva la posición de llegada")
		_comprobar(int(Cultivos.parcela(_clave_cultivo).dias) == dia + 1, "El cultivo crece tras la noche regada")
	if not _comprobar(Cultivos.esta_listo(_clave_cultivo), "Patata madura tras sus días de crecimiento"):
		return false
	# La captura de la cosecha debe encuadrar el cultivo, no la puerta donde Leo despierta.
	var j := Escenas.jugador() as Jugador
	j.colocar(_parcelas().posicion_de(_clave_cultivo) - Vector3(0, -0.05, 1.2), 0.0, j.camara.yaw)
	await get_tree().create_timer(0.7).timeout
	await _capturar("02_cosecha_lista")
	var cantidad := Juego.cantidad("patata")
	var cosechas := int(Juego.estadisticas.get("cosechas", 0))
	var proxy: Node3D = _parcelas()._proxies.get(_clave_cultivo)
	if not _comprobar(proxy != null and not proxy.texto_interaccion().is_empty(), "Cosecha disponible como interacción"):
		return false
	proxy.interactuar(Escenas.jugador())
	_comprobar(Juego.cantidad("patata") > cantidad and int(Juego.estadisticas.cosechas) == cosechas + Juego.cantidad("patata") - cantidad and not Cultivos.esta_listo(_clave_cultivo), "Cosechar entrega patatas y registra todas las unidades cosechadas")
	return true


func _npc(id: String, accion: String) -> bool:
	for nodo in get_tree().get_nodes_in_group("npc"):
		if nodo is Npc and nodo.id == id:
			# El jugador interactúa con el punto «Hablar», hijo del cuerpo del vecino.
			nodo.get_node("Hablar").interactuar(Escenas.jugador())
			return await _elegir(Conversacion.acciones_de(nodo).find(accion))
	return _comprobar(false, "Vecino presente: " + id)


func _tienda() -> void:
	var amistad := Juego.puntos_amistad("mateo")
	if await _npc("mateo", "hablar"):
		_comprobar(Juego.puntos_amistad("mateo") == amistad + Juego.AMISTAD_POR_CHARLA, "Conversar con Mateo aumenta la amistad")
		await _cerrar_dialogo()
	if not await _npc("mateo", "tienda"):
		return
	var tienda := Interfaz.get_node("Raiz/Tienda") as PanelTienda
	_comprobar(tienda.visible, "Se abre la tienda desde Mateo")
	var semillas := Juego.cantidad("semilla_patata")
	var dinero := Juego.dinero
	tienda._elegir("semilla_patata")
	tienda._b_confirmar.pressed.emit()
	_comprobar(Juego.cantidad("semilla_patata") == semillas + 1 and Juego.dinero == dinero - int(Datos.objeto("semilla_patata").precio_compra), "Comprar semillas descuenta el precio exacto")
	tienda._b_vender_tab.pressed.emit()
	_comprobar(tienda._ids_visibles().has("patata"), "La cosecha aparece entre los productos vendibles")
	tienda._elegir("patata")
	tienda._b_max.pressed.emit()
	var cantidad := Juego.cantidad("patata")
	dinero = Juego.dinero
	tienda._b_confirmar.pressed.emit()
	_comprobar(cantidad > 0 and Juego.cantidad("patata") == 0 and Juego.dinero == dinero + cantidad * int(Datos.objeto("patata").precio_venta), "Vender toda la cosecha ingresa el precio exacto")
	await _capturar("03_venta")
	tienda.cerrar_panel()
	# Regalo real desde la conversación y su confirmación; se usa una semilla comprada.
	_seleccionar("semilla_patata")
	semillas = Juego.cantidad("semilla_patata")
	amistad = Juego.puntos_amistad("mateo")
	if await _npc("mateo", "regalar"):
		await _elegir(0)
		_comprobar(Juego.cantidad("semilla_patata") == semillas - 1 and Juego.puntos_amistad("mateo") == amistad + Conversacion.PUNTOS_NEUTRO and bool(Juego.hablado_hoy.get("regalo_mateo", false)), "Regalar una semilla consume una unidad y aumenta la amistad")
		await _capturar("03b_regalo")
		await _cerrar_dialogo()


func _interiores() -> bool:
	Juego.avanzar_minutos(600 - Juego.minutos)
	if not await _cruzar("pueblo"):
		return false
	for id in ["tienda", "herreria", "taberna", "casa_alcalde", "capilla", "casita_a", "casita_b"]:
		if not await _cruzar(id):
			return false
		_comprobar(Escenas.mapa_actual_nodo().interior, "Interior reconocido: " + id)
		await _capturar("interior_" + id)
		if id == "tienda":
			await _tienda()
		if not await _cruzar("pueblo"):
			return false
	return true


func _rocas() -> RocasMina:
	for nodo in get_tree().get_nodes_in_group("usable"):
		if nodo is RocasMina:
			return nodo
	return null


func _picar(tipo: String, cantidad: int) -> bool:
	var rocas := _rocas()
	if not _comprobar(rocas != null and rocas.construido, "Rocas construidas en la mina"):
		return false
	var antes := Juego.cantidad(tipo)
	var energia := Juego.energia
	for roca in rocas.rocas_en_pie():
		if roca.tipo != tipo:
			continue
		for golpe in rocas.golpes_necesarios(roca):
			roca.punto.interactuar(Escenas.jugador())
			await get_tree().create_timer(0.65).timeout
		_comprobar(roca.rota, "La roca de %s se rompe a golpes de pico" % tipo)
		if Juego.cantidad(tipo) >= antes + cantidad:
			break
	return _comprobar(Juego.cantidad(tipo) >= antes + cantidad and Juego.energia < energia, "Extraer %s entrega mineral y consume energía" % tipo)


func _nivel_mina(nivel: int) -> bool:
	for nodo in get_tree().get_nodes_in_group("interactuable"):
		if nodo.name == "Escalera":
			nodo.interactuar(Escenas.jugador())
			await _elegir(0)
			if not await _mapa("mina_interior"):
				return false
			return _comprobar(int(Juego.banderas.get("nivel_mina", 0)) == nivel and _rocas().nivel == nivel, "Escalera cambia al nivel %d" % nivel)
	return _comprobar(false, "Escalera de la mina disponible")


func _mina_y_mejora() -> bool:
	if not await _cruzar("mina_exterior") or not await _cruzar("mina_interior"):
		return false
	var mejora := Servicios.siguiente_mejora("pico")
	if not await _picar(str(mejora.material), int(mejora.cantidad)):
		return false
	if not await _nivel_mina(2) or not await _picar("cuarzo", 1):
		return false
	await _capturar("04_mina_nivel_2")
	if not await _nivel_mina(1):
		return false
	if not await _cruzar("mina_exterior") or not await _cruzar("pueblo") or not await _cruzar("herreria"):
		return false
	var cobre := Juego.cantidad(str(mejora.material))
	var dinero := Juego.dinero
	if not await _npc("clara", "herreria"):
		return false
	await _elegir(Servicios.HERRAMIENTAS.find("pico"))
	_comprobar(Juego.nivel("pico") == 1 and Juego.cantidad(str(mejora.material)) == cobre - int(mejora.cantidad) and Juego.dinero == dinero - int(mejora.dinero), "Mejorar el pico consume el mineral extraído y el dinero exacto")
	await _capturar("05_pico_mejorado")
	await _cerrar_dialogo()
	return true


func _inicio() -> void:
	Juego.borrar_partida()
	Escenas.ir_al_menu()
	if not await _escena(Escenas.ESCENA_MENU):
		return
	var menu := get_tree().current_scene
	_comprobar(menu._b_continuar.disabled, "Sin partida no se puede continuar")
	_boton(menu, "Nueva partida")
	menu._campo_nombre.text = "Recorrido T04"
	_boton(menu, "Empezar")
	if not await _escena(Escenas.ESCENA_INTRO):
		return
	Juego.pausar_tiempo(true)
	var intro := get_tree().current_scene
	_comprobar(Juego.nombre_jugador == "Recorrido T04" and Juego.dinero == Juego.DINERO_INICIAL, "Partida nueva con nombre y recursos iniciales")
	_comprobar(intro._pagina == 0 and "Recorrido T04" in intro._texto.text, "Primera página de la carta personalizada")
	intro._b_siguiente.pressed.emit()
	_comprobar(intro._pagina == 1 and not intro._texto.text.is_empty(), "Segunda página de la introducción")
	await _capturar("00_introduccion")
	intro._b_siguiente.pressed.emit()
	if not await _mapa("granja"):
		return
	if not await _agricultura() or not await _interiores() or not await _mina_y_mejora():
		return
	if not await _cruzar("pueblo") or not await _cruzar("granja"):
		return
	# Deja un cultivo vivo y con crecimiento para que la carga no compruebe solo tierra vacía.
	await _usar_cultivo("semilla_patata")
	await _usar_cultivo("regadera")
	_comprobar(Cultivos.parcela(_clave_cultivo).cultivo == "patata" and Cultivos.parcela(_clave_cultivo).regado, "Segundo cultivo plantado y regado antes de guardar")
	if not await _cruzar("casa_leo"):
		return
	await _capturar("interior_casa_leo")
	_comprobar(Escenas.mapa_actual_nodo().interior, "Interior reconocido: casa_leo")
	if not await _cruzar("granja") or not await _cruzar("casa_leo"):
		return
	if not await _dormir_en_cama() or not await _mapa("granja"):
		return
	# Guardado manual desde la pausa, además del autoguardado nocturno.
	var pausa := Interfaz.get_node("Raiz/Pausa") as PanelPausa
	pausa.abrir()
	_boton(pausa, "Guardar partida")
	_comprobar(Juego.estado_guardado() == "ok", "Guardar desde la pausa deja una partida válida")
	var esperado := Juego._datos_de_guardado().duplicate(true)
	_escribir("esperado.json", {"sesion": _sesion, "pid": OS.get_process_id(), "datos": esperado, "clave_cultivo": _clave_cultivo})
	# El lanzador comprueba la salida real antes de iniciar el segundo proceso.
	if _informe().fallidos == 0:
		_boton(pausa, "Salir al menú" if _fase == "completa" else "Salir del juego")
		_comprobar(true, "Solicitar cerrar la partida desde la pausa")
		_escribir("resultado_inicio.json", _informe())
		await _elegir(0)
		if _fase == "completa":
			await _escena(Escenas.ESCENA_MENU)


func _continuar() -> void:
	var anterior := _leer("resultado_inicio.json")
	var esperado := _leer("esperado.json")
	if _fase == "completa":
		_escribir("resultado_inicio.json", _informe())
		anterior = _leer("resultado_inicio.json")
		_pasos = []
	_pasos_previos = (anterior.get("pasos", []) as Array).size()
	_superados_previos = int(anterior.get("superados", 0))
	if not _comprobar(anterior.get("sesion") == _sesion and int(anterior.get("fallidos", -1)) == 0 and esperado.get("sesion") == _sesion,
		"La fase inicial de esta sesión terminó sin fallos"):
		return
	if _fase != "completa":
		_comprobar(int(esperado.get("pid", 0)) != OS.get_process_id(), "Continuar se ejecuta en un proceso nuevo")
	else:
		_comprobar(not Juego.partida_activa and Escenas.jugador() == null, "Partida cerrada y Leo descargado antes de continuar")
	Escenas.ir_al_menu()
	if not await _escena(Escenas.ESCENA_MENU):
		return
	var menu := get_tree().current_scene
	_comprobar(not menu._b_continuar.disabled, "El menú detecta la partida guardada")
	_boton(menu, "Continuar")
	Juego.pausar_tiempo(true)
	if not await _mapa(str(esperado.datos.mapa_actual)):
		return
	# La referencia se leyó de JSON: sus números son float. Se hace el mismo viaje
	# con el estado actual para comparar valores persistidos, sin confundir 1 con 1.0.
	var actual: Dictionary = JSON.parse_string(JSON.stringify(Juego._datos_de_guardado()))
	for clave: String in esperado.datos:
		if clave in ["guardado_el", "posicion"]:
			continue
		_comprobar(JSON.stringify(actual.get(clave)) == JSON.stringify(esperado.datos[clave]), "Continuar conserva " + clave)
	var pos: Array = esperado.datos.posicion
	_comprobar(Escenas.jugador().global_position.distance_to(Vector3(pos[0], pos[1], pos[2])) < 0.3, "Continuar restaura la posición guardada")
	_clave_cultivo = str(esperado.clave_cultivo)
	_comprobar(Cultivos.parcela(_clave_cultivo).cultivo == "patata" and int(Cultivos.parcela(_clave_cultivo).dias) == 1 and Juego.nivel("pico") == 1, "Persisten el cultivo vivo con un día de crecimiento y la mejora")
	await _capturar("06_continuar")
	await _finales()


func _finales() -> void:
	# Tres ramas independientes del guardado real. El calendario avanza con las reglas
	# normales de fin de día; solo se preparan los umbrales de dinero y amistad.
	for final in ["malo", "regular", "bueno"]:
		Juego.ruta_partida = _ruta_base
		if not _comprobar(Juego.cargar(), "Recuperar el recorrido para el final " + final):
			return
		Juego.ruta_partida = _carpeta.path_join("final_" + final + ".json")
		Juego.pausar_tiempo(true)
		Escenas.ir_a_mapa("casa_leo", "Entrada")
		if not await _mapa("casa_leo"):
			return
		var noches := 0
		while Juego.dias_restantes() > 1 and noches < 112:
			Juego.terminar_dia(false)
			noches += 1
		_comprobar(Juego.estacion == 3 and Juego.dia == 28, "Calendario acelerado llega al 28 de invierno: " + final)
		Juego.dinero = Juego.deuda - 1 if final == "malo" else Juego.deuda
		for id in Datos.ids_npc():
			Juego.amistad[id] = Juego.AMISTAD_BUENA if final == "bueno" else Juego.AMISTAD_BUENA - 1
		print("PREPARACIÓN DEL FINAL: ", final, "; dinero=", Juego.dinero, "; amistad=", Juego.amistad_media())
		if not await _dormir_en_cama() or not await _escena(Escenas.ESCENA_FINAL):
			return
		_comprobar(Juego.final_logrado() == final and bool(Juego.banderas.get("fin_anio", false)), "Dormir la última noche alcanza el final " + final)
		var titulo := str(Datos.texto("final.%s.titulo" % final))
		var mostrado := false
		for nodo in get_tree().current_scene.find_children("*", "Label", true, false):
			if nodo.text == titulo and not titulo.is_empty():
				mostrado = true
		_comprobar(mostrado and not Interfaz.hud_visible() and not Juego.partida_activa, "Pantalla y relato correctos del final " + final)
		await _capturar("final_" + final)
		_boton(get_tree().current_scene, "Volver al menú")
		if not await _escena(Escenas.ESCENA_MENU):
			return
		_boton(get_tree().current_scene, "Ver el final")
		if not await _escena(Escenas.ESCENA_FINAL):
			return
		_comprobar(Juego.final_logrado() == final, "Ver el final recupera la rama guardada: " + final)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	seed(20261111)
	print("PRUEBA FINAL: fase ", _fase, "; sesión ", _sesion, "; datos en ", _carpeta)
	if _fase == "inicio":
		await _inicio()
	elif _fase == "completa":
		await _inicio()
		if _informe().fallidos == 0:
			await _continuar()
	elif _fase == "continuar":
		await _continuar()
	else:
		_comprobar(false, "Fase desconocida: " + _fase)
	_terminar()
