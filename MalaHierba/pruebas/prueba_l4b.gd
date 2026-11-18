extends Node
## Prueba del pueblo y la mina (L4b). Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_l4b.tscn
## Imprime «PRUEBA OK (n comprobaciones)» o «PRUEBA FALLO: <motivos>» y sale con 0 o 1.
## Usa las clases de verdad: Escenas.ir_a_mapa, el jugador, el sistema de interacción de M1 y los paneles de la interfaz
## (pulsando sus botones).

const SECCIONES: Array[String] = ["datos", "pueblo", "conversacion", "servicios", "objetos", "horario", "mina_exterior", "mina_interior", "guardado"]

var _fallos: Array[String] = []
var _total: int = 0
## Secciones que han llegado hasta el final. Un error de script dentro de una sección la corta sin dar fallo, así que
## al terminar se exige que estén todas.
var _hechas: Array[String] = []
var _j: Jugador = null
var _mapa: Node = null


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fisica(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _fin_de(seccion: String) -> void:
	_hechas.append(seccion)


func _terminar() -> void:
	Engine.time_scale = 1.0
	for s in SECCIONES:
		_comprobar(_hechas.has(s), "la sección «%s» no llegó hasta el final (error de script o salida anticipada)" % s)
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)))
		get_tree().quit(1)


# --- Ayudas de interfaz ------------------------------------------------------------------------------------

func _pregunta() -> PanelPregunta:
	return Interfaz.get_node("Raiz/Pregunta") as PanelPregunta


func _dialogo() -> PanelDialogo:
	return Interfaz.get_node("Raiz/Dialogo") as PanelDialogo


func _tienda() -> PanelTienda:
	return Interfaz.get_node("Raiz/Tienda") as PanelTienda


## Pulsa el botón de la pregunta abierta cuyo texto contiene `parte`. Devuelve false si no lo hay.
func _pulsar(parte: String) -> bool:
	var p := _pregunta()
	if not p.visible:
		return false
	for b in p._botones:
		if b.text.contains(parte):
			b.pressed.emit()
			return true
	return false


func _textos_pregunta() -> Array[String]:
	var r: Array[String] = []
	for b in _pregunta()._botones:
		r.append(b.text)
	return r


## Lee las frases del diálogo abierto hasta cerrarlo (como pulsar E).
func _pasar_dialogo() -> String:
	var d := _dialogo()
	var texto := ""
	var vueltas := 0
	while d.visible and vueltas < 40:
		texto += d._texto.text + " | "
		d._avanzar()
		d._avanzar()
		vueltas += 1
	return texto


func _cerrar_todo() -> void:
	Interfaz.cerrar_todo()


func _vecino(vecinos: Vecinos, id: String) -> Npc:
	return vecinos.npcs.get(id) as Npc


func _poner_a_leo(pos: Vector3, mira: Vector3) -> void:
	_j.colocar(pos + Vector3(0, 0.05, 0), 0.0, atan2(-mira.x, -mira.z))
	_j._pos_segura = pos
	_j.direccion = mira.normalized()


func _apuntar_interaccion(punto: Interactuable) -> bool:
	var centro := punto.global_position + Vector3.UP * minf(punto.altura_marca * 0.5, 1.0)
	for dir in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var pos := AyudasL4b.suelo(_mapa, punto.global_position + dir * 1.55, 1.2, 3.0)
		if pos == Vector3.INF or not _mapa.punto_dentro(pos, 0.15):
			continue
		_poner_a_leo(pos, -dir)
		await _fisica(4)
		_j.camara.mirar_hacia(centro)
		_j._actualizar_interactuable()
		if _j._objetivo == punto:
			return true
	return false


## Espera a que acabe el fundido de un cambio de mapa (Escenas lo marca con en_transicion).
func _esperar_transicion() -> void:
	var tope := 0
	while Escenas.en_transicion and tope < 600:
		await get_tree().process_frame
		tope += 1


func _ir(id: String, marcador: String = "Spawn_Protagonista") -> void:
	await Escenas.ir_a_mapa(id, marcador)
	await _frames(3)
	await _fisica(4)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador


# --- Ejecución --------------------------------------------------------------------------------------------------------

func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_l4b.json"
	Juego.nueva_partida("Prueba")
	Juego.pausar_tiempo(true)
	Juego.minutos = 600

	_prueba_datos()
	await _prueba_pueblo()
	await _prueba_conversacion()
	await _prueba_tienda_herreria_taberna()
	await _prueba_objetos_del_pueblo()
	await _prueba_horario()
	await _prueba_mina_exterior()
	await _prueba_mina_interior()
	await _prueba_guardado()
	_terminar()


# --- Datos --------------------------------------------------------------------------------------------------------------------

func _prueba_datos() -> void:
	print("[datos]")
	var todos := Vecinos.datos_de_todos()
	var ids: Dictionary = {}
	for d in todos:
		var id := str(d.get("id", ""))
		_comprobar(not id.is_empty() and not ids.has(id), "id de vecino repetido o vacío: «%s»" % id)
		ids[id] = true
		_comprobar(ResourceLoader.exists("res://assets/personajes/aldeanos/%s.glb" % str(d.get("modelo", ""))), "%s: falta el modelo %s" % [id, str(d.get("modelo", ""))])
		if bool(d.get("relleno", false)):
			_comprobar((d.get("dialogos", []) as Array).size() >= 4, "%s: el vecino de relleno necesita al menos 4 frases" % id)
	_comprobar(todos.size() >= 13, "hay vecinos principales y de relleno (%d)" % todos.size())
	_comprobar(Datos.ids_npc().size() == 6, "los principales siguen siendo 6 (no cuentan los de relleno en la amistad)")
	# Intercambio Mateo/Clara respecto al contrato: cada uno en el sitio de su oficio.
	_comprobar(str(Datos.npc("mateo")["marcador"]) == "Spawn_Tendera" and str(Datos.npc("clara")["marcador"]) == "Spawn_Herrero", "Mateo en la tienda y Clara en la herrería")

	# Horarios.
	var ramon := Datos.npc("ramon")
	_comprobar(str(Vecinos.ubicacion(ramon, 1400).get("mapa", "")) == "pueblo", "Ramón sigue en la taberna a las 23:20")
	_comprobar(Vecinos.ubicacion(ramon, 1450).is_empty(), "Ramón se va a las 00:00")
	_comprobar(Vecinos.ubicacion(ramon, 350).is_empty(), "nadie está antes de las 06:00")
	_comprobar(Vecinos.ubicacion(Datos.npc("mateo"), 1300).is_empty(), "Don Mateo no está de noche")
	var tomas := Datos.npc("tomas")
	_comprobar(str(Vecinos.ubicacion(tomas, 700).get("mapa", "")) == "mina_exterior", "Tomás trabaja en la mina por la mañana")
	_comprobar(str(Vecinos.ubicacion(tomas, 1100).get("mapa", "")) == "pueblo" and str(Vecinos.ubicacion(tomas, 1100).get("marcador", "")) == "Spawn_Tabernero", "Tomás va a la taberna a las 18:20")
	_comprobar(Vecinos.ubicacion(tomas, 1270).is_empty(), "Tomás se acuesta a las 21:00")
	var anselmo := Datos.npc("anselmo")
	_comprobar(str(Vecinos.ubicacion(anselmo, 800).get("marcador", "")) == "Spawn_Tabernero" and str(Vecinos.ubicacion(anselmo, 700).get("marcador", "")) == "Spawn_Alcalde", "el alcalde come en la taberna de 13:00 a 15:00")
	# El horario es general: una franja puede mandar a un vecino a otro mapa (así lo usará L5).
	var prueba := {"id": "x", "mapa": "pueblo", "marcador": "Spawn_Tendera", "horario": [{"desde": 540, "hasta": 1140, "mapa": "tienda", "marcador": "Dentro"}]}
	_comprobar(str(Vecinos.ubicacion(prueba, 600)["mapa"]) == "tienda" and str(Vecinos.ubicacion(prueba, 1200)["mapa"]) == "pueblo", "una franja puede cambiar de mapa")

	# Tablón: 3 encargos al día, y los de cada día son siempre los mismos.
	var todos_encargos := ObjetosPueblo.todos_los_encargos()
	_comprobar(todos_encargos.size() >= 9, "hay encargos de sobra en el tablón (%d)" % todos_encargos.size())
	for e in todos_encargos:
		_comprobar(Datos.existe_objeto(str(e.get("pide", ""))) and not Datos.npc(str(e.get("npc", ""))).is_empty(), "encargo %s: objeto y vecino existen" % str(e.get("id", "")))
	_comprobar(ObjetosPueblo.encargos_del_dia().size() == 3, "tres encargos al día")
	var hoy_a := ObjetosPueblo.encargos_del_dia().map(func(e: Dictionary) -> String: return str(e["id"]))
	var hoy_b := ObjetosPueblo.encargos_del_dia().map(func(e: Dictionary) -> String: return str(e["id"]))
	_comprobar(hoy_a == hoy_b, "los encargos del día no cambian durante el día")
	_fin_de("datos")


# --- Pueblo: vecinos --------------------------------------------------------------------------------------------------------

func _prueba_pueblo() -> void:
	print("[pueblo: vecinos]")
	await _ir("pueblo")
	_comprobar(_mapa != null and str(_mapa.name) == "Pueblo", "el mapa actual es el pueblo")
	var vecinos := _mapa.get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vecinos != null, "falta Objetos/Vecinos en el pueblo")
	_comprobar(_mapa.get_node_or_null("Objetos/ObjetosPueblo") != null, "falta Objetos/ObjetosPueblo")
	if vecinos == null or _j == null:
		return
	# A las 10:00: los 5 principales del pueblo (no Tomás, que está en la mina) y los 5 de relleno.
	for id in ["mateo", "clara", "ramon", "anselmo", "pablo", "marisol", "eusebio", "lucia", "bernardo", "irene"]:
		_comprobar(vecinos.npcs.has(id), "a las 10:00 está %s" % id)
	_comprobar(not vecinos.npcs.has("tomas"), "a las 10:00 Tomás no está en el pueblo")
	_comprobar(vecinos.npcs.size() == 10, "hay 10 vecinos en el pueblo (%d)" % vecinos.npcs.size())

	var enmapa := get_tree().get_nodes_in_group("npc")
	_comprobar(enmapa.size() == vecinos.npcs.size(), "todos los vecinos están en el grupo «npc» del minimapa (%d de %d)" % [enmapa.size(), vecinos.npcs.size()])
	_comprobar(Interfaz.minimapa() != null and Interfaz.minimapa().lista(), "el minimapa está listo y dibuja los vecinos del grupo «npc»")
	var lista: Array = vecinos.npcs.values()
	for n: Npc in lista:
		var p := n.global_position
		var suelo := AyudasL4b.suelo(_mapa, p + Vector3(0, 0.3, 0), 0.5, 3.0)
		_comprobar(suelo != Vector3.INF and absf(suelo.y - p.y) < 0.6, "%s: pisa el suelo (%.2f frente a %.2f)" % [n.id, p.y, suelo.y if suelo != Vector3.INF else -99.0])
		_comprobar(AyudasL4b.cabe(_mapa, p, 0.3, 1.5), "%s: no está dentro de un edificio ni de un objeto" % n.id)
		_comprobar(_mapa.punto_dentro(p, 0.5), "%s: está dentro del área jugable" % n.id)
		_comprobar(n.get_node_or_null("Hablar") != null and (n.get_node("Hablar") as Interactuable).texto_interaccion() == "Hablar con " + n.nombre, "%s: lleva su Interactuable «Hablar con»" % n.id)
		_comprobar(n.collision_layer == 16, "%s: cuerpo en la capa 5" % n.id)
		_comprobar(n._modelo.get_child_count() > 0, "%s: tiene modelo" % n.id)
	for i in lista.size():
		for k in range(i + 1, lista.size()):
			var a := (lista[i] as Npc).global_position
			var b := (lista[k] as Npc).global_position
			_comprobar(Vector2(a.x - b.x, a.z - b.z).length() > 0.9, "%s y %s no están uno encima del otro" % [(lista[i] as Npc).id, (lista[k] as Npc).id])
	# Cada oficio en su sitio.
	for par in [["mateo", "Spawn_Tendera"], ["clara", "Spawn_Herrero"], ["ramon", "Spawn_Tabernero"], ["anselmo", "Spawn_Alcalde"], ["pablo", "Spawn_Nino"]]:
		var m := _mapa.call("marcador", par[1]) as Marker3D
		var n := _vecino(vecinos, par[0])
		_comprobar(m != null and n != null and n.global_position.distance_to(m.global_position) < 4.0, "%s está junto a %s" % [par[0], par[1]])
	# Las variantes de relleno llevan otros colores y nombres propios.
	var datos_relleno := Vecinos.datos_de_todos().filter(func(d: Dictionary) -> bool: return bool(d.get("relleno", false)))
	_comprobar(datos_relleno.size() >= 3, "hay al menos 3 vecinos de relleno (%d)" % datos_relleno.size())

	# Cartel de acción al acercarse a Clara.
	var clara := _vecino(vecinos, "clara")
	_poner_a_leo(clara.global_position + Vector3(0, 0, 1.3), Vector3(0, 0, -1))
	_j.camara.mirar_hacia(clara.punto_ojos())
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo != null and Interfaz.texto_accion().contains("Hablar con Clara"), "junto a Clara sale «E · Hablar con Clara» (sale «%s»)" % Interfaz.texto_accion())
	# «Dormir» solo existe en la casa de Leo.
	var dormir := 0
	for n: Node in get_tree().get_nodes_in_group("interactuable"):
		if n.has_method("texto_interaccion") and str(n.call("texto_interaccion")).begins_with("Dormir"):
			dormir += 1
	_comprobar(dormir == 0, "en el pueblo no hay «Dormir» (hay %d)" % dormir)

	# Pasean: con el tiempo acelerado, varios se han movido.
	var antes: Dictionary = {}
	for n: Npc in lista:
		antes[n.id] = n.global_position
	Engine.time_scale = 4.0
	await get_tree().create_timer(3.0).timeout
	Engine.time_scale = 1.0
	var movidos := 0
	for n: Npc in lista:
		if (antes[n.id] as Vector3).distance_to(n.global_position) > 0.5:
			movidos += 1
		_comprobar(_mapa.punto_dentro(n.global_position, 0.0), "%s: paseando no sale del área jugable" % n.id)
	_comprobar(movidos >= 5, "los vecinos pasean: %d de %d se han movido" % [movidos, lista.size()])
	_fin_de("pueblo")


# --- Conversación y amistad ------------------------------------------------------------------------------------------

func _prueba_conversacion() -> void:
	print("[conversación]")
	var vecinos := _mapa.get_node("Objetos/Vecinos") as Vecinos
	var clara := _vecino(vecinos, "clara")
	var mateo := _vecino(vecinos, "mateo")
	if clara == null or mateo == null:
		_comprobar(false, "faltan Clara o Don Mateo")
		return
	_cerrar_todo()
	# Menú de Clara por la vía real: E sobre su Interactuable.
	_poner_a_leo(clara.global_position + Vector3(0, 0, 1.3), Vector3(0, 0, -1))
	_j.camara.mirar_hacia(clara.punto_ojos())
	_j._actualizar_interactuable()
	_j._interactuar()
	_comprobar(Interfaz.ocupada() and _pregunta().visible, "E sobre Clara abre su menú")
	var textos := _textos_pregunta()
	_comprobar(textos.size() == 4 and "Mejorar herramientas" in textos[0] and "Hablar" in textos[1] and "Adiós" in textos[3], "menú de Clara: mejorar, hablar, regalar, adiós (%s)" % str(textos))
	_comprobar(_pulsar("Hablar"), "se puede elegir «Hablar»")
	_comprobar(_dialogo().visible, "«Hablar» abre el diálogo")
	var dicho := _pasar_dialogo()
	_comprobar(not Interfaz.ocupada(), "el diálogo se cierra")
	_comprobar(Juego.puntos_amistad("clara") == 5, "la primera charla del día da +5 de amistad (%d)" % Juego.puntos_amistad("clara"))
	_comprobar(Datos.dialogos_npc("clara", 0).any(func(f: String) -> bool: return dicho.contains(f)), "la frase sale de las de su nivel de amistad")
	# Segunda charla el mismo día: sin amistad extra y frase distinta.
	var f1 := Conversacion.frase_para("clara", 0)
	var f2 := Conversacion.frase_para("clara", 0)
	_comprobar(f1 != f2, "dos frases seguidas no se repiten")
	Conversacion.hablar(clara, _j)
	_pulsar("Hablar")
	_pasar_dialogo()
	_comprobar(Juego.puntos_amistad("clara") == 5, "hablar otra vez el mismo día no suma (%d)" % Juego.puntos_amistad("clara"))
	# Un día más tarde vuelve a sumar y el nivel sube con la amistad.
	Juego.terminar_dia(false)
	_comprobar(not bool(Juego.hablado_hoy.get("clara", false)), "al día siguiente se puede volver a hablar")
	Conversacion.hablar(clara, _j)
	_pulsar("Hablar")
	_pasar_dialogo()
	_comprobar(Juego.puntos_amistad("clara") == 10, "al día siguiente suma otros +5 (%d)" % Juego.puntos_amistad("clara"))
	Juego.amistad["clara"] = 70
	_comprobar(Juego.nivel_amistad("clara") == 1, "con 70 puntos la amistad es de nivel 1")
	var frase_n1 := Conversacion.frase_para("clara", Juego.nivel_amistad("clara"))
	_comprobar(Datos.dialogos_npc("clara", 1).has(frase_n1), "en el nivel 1 dice frases del nivel 1")
	Juego.amistad["clara"] = 10

	# Regalos.
	var gusta := str((Datos.npc("clara")["gusta"] as Array)[0])
	var no_gusta := str((Datos.npc("clara")["no_gusta"] as Array)[0])
	Juego.anadir_objeto(gusta, 2)
	Juego.anadir_objeto(no_gusta, 2)
	Juego.anadir_objeto("pan", 1)
	_comprobar(Conversacion.puntos_de_regalo(clara, gusta) == 20 and Conversacion.puntos_de_regalo(clara, no_gusta) == -10 and Conversacion.puntos_de_regalo(clara, "pan") == 3, "regalo: gusta +20, no gusta −10, otra cosa +3")
	_comprobar(Conversacion.puntos_de_regalo(clara, "azada") == 0, "una herramienta no se regala")
	var hueco := -1
	for i in 10:
		if str((Juego.inventario[i] as Dictionary).get("id", "")) == gusta:
			hueco = i
	if hueco < 0:
		for i in range(10, 30):
			if str((Juego.inventario[i] as Dictionary).get("id", "")) == gusta:
				Juego.mover_huecos(i, 9)
				hueco = 9
				break
	Juego.elegir_ranura(hueco)
	var antes := Juego.puntos_amistad("clara")
	var cant := Juego.cantidad(gusta)
	Conversacion.regalar(clara)
	_comprobar(_pregunta().visible, "regalar pregunta si seguro")
	_pulsar("Sí")
	_pasar_dialogo()
	_comprobar(Juego.puntos_amistad("clara") == antes + 20 and Juego.cantidad(gusta) == cant - 1, "regalar lo que gusta: +20 y se gasta uno (%d)" % (Juego.puntos_amistad("clara") - antes))
	Conversacion.regalar(clara)
	var d2 := _pasar_dialogo()
	_comprobar(Juego.puntos_amistad("clara") == antes + 20 and d2.contains("Ya me has traído"), "solo un regalo al día")
	_comprobar(Juego.puntos_amistad("mateo") == 0, "Don Mateo empieza sin amistad")
	Juego.amistad["mateo"] = 50
	Juego.anadir_objeto("fibra", 1)
	Conversacion.entregar_regalo(mateo, "fibra")
	_pasar_dialogo()
	_comprobar(Juego.puntos_amistad("mateo") == 40, "regalar algo que no gusta resta 10 (%d)" % Juego.puntos_amistad("mateo"))
	Juego.amistad["mateo"] = 0

	# Vecino de relleno: solo frases, sin menú ni amistad.
	var relleno := _vecino(vecinos, "marisol")
	Conversacion.hablar(relleno, _j)
	_comprobar(_dialogo().visible and not _pregunta().visible, "un vecino de relleno solo dice una frase")
	_pasar_dialogo()
	_comprobar(Juego.puntos_amistad("marisol") == 0 and not Juego.amistad.has("marisol"), "los vecinos de relleno no tienen amistad")
	_comprobar(not Datos.ids_npc().has("marisol"), "no cuentan para la amistad media")
	_cerrar_todo()
	_fin_de("conversacion")


# --- Tienda, herrería y taberna ---------------------------------------------------------------------------------------

func _prueba_tienda_herreria_taberna() -> void:
	print("[tienda, herrería y taberna]")
	var vecinos := _mapa.get_node("Objetos/Vecinos") as Vecinos
	var mateo := _vecino(vecinos, "mateo")
	var clara := _vecino(vecinos, "clara")
	var ramon := _vecino(vecinos, "ramon")
	_cerrar_todo()
	Juego.dinero = 500

	# Don Mateo: comprar semillas y vender patatas con el panel real.
	Conversacion.hablar(mateo, _j)
	var textos := _textos_pregunta()
	_comprobar("Comprar y vender" in textos[0], "menú de Don Mateo: «Comprar y vender» primero")
	_pulsar("Comprar y vender")
	_comprobar(_tienda().visible, "«Comprar y vender» abre la tienda de Don Mateo")
	var dinero0 := Juego.dinero
	var semillas0 := Juego.cantidad("semilla_zanahoria")
	_tienda()._elegir("semilla_zanahoria")
	_tienda()._cantidad = 3
	_tienda()._confirmar()
	var precio := int(Datos.objeto("semilla_zanahoria")["precio_compra"])
	_comprobar(Juego.dinero == dinero0 - 3 * precio and Juego.cantidad("semilla_zanahoria") == semillas0 + 3, "comprar 3 semillas resta %d € y suma 3 (dinero %d)" % [3 * precio, Juego.dinero])
	Juego.anadir_objeto("patata", 5)
	_tienda()._cambiar_modo("vender")
	var dinero1 := Juego.dinero
	_tienda()._elegir("patata")
	_tienda()._cantidad = 5
	_tienda()._confirmar()
	var pv := int(Datos.objeto("patata")["precio_venta"])
	_comprobar(Juego.dinero == dinero1 + 5 * pv and Juego.cantidad("patata") == 0, "vender 5 patatas suma %d € (dinero %d)" % [5 * pv, Juego.dinero])
	_tienda().cerrar_panel()
	_comprobar(not Interfaz.ocupada(), "se cierra la tienda")

	# Clara: mejorar herramientas.
	Juego.nivel_herramientas.clear()
	Juego.dinero = 500
	_comprobar(Servicios.mejorar("pico") == "sin_material" and Juego.nivel("pico") == 0, "sin material no se mejora")
	Juego.anadir_objeto("cobre", 5)
	Juego.dinero = 100
	_comprobar(Servicios.mejorar("pico") == "sin_dinero" and Juego.nivel("pico") == 0 and Juego.cantidad("cobre") == 5, "sin dinero no se mejora y no se gasta el material")
	Juego.dinero = 500
	Conversacion.hablar(clara, _j)
	_pulsar("Mejorar herramientas")
	_comprobar(_pregunta().visible, "«Mejorar herramientas» abre la lista de mejoras")
	var opciones := _textos_pregunta()
	_comprobar(opciones.size() == 7 and "Azada de cobre" in opciones[0] and "Pico de cobre" in opciones[4]
		and "Comprar o forjar armas y armaduras" in opciones[5], "la lista ofrece mejoras y equipo de combate (%s)" % str(opciones))
	_pulsar("Pico de cobre")
	_pasar_dialogo()
	_comprobar(Juego.nivel("pico") == 1 and Juego.cantidad("cobre") == 0 and Juego.dinero == 350, "mejorar el pico: nivel 1, sin cobre y −150 € (nivel %d, cobre %d, dinero %d)" % [Juego.nivel("pico"), Juego.cantidad("cobre"), Juego.dinero])
	_comprobar(Servicios.siguiente_mejora("pico")["nivel"] == 2 and Servicios.siguiente_mejora("pico")["material"] == "hierro", "luego toca el nivel 2, de hierro")
	Juego.nivel_herramientas["pico"] = 3
	_comprobar(Servicios.mejorar("pico") == "maximo", "el nivel 3 es el máximo")
	Juego.nivel_herramientas["pico"] = 0
	_cerrar_todo()

	# Ramón: comer en la barra y comprar para llevar.
	Juego.dinero = 500
	Juego.energia = 40.0
	var din := Juego.dinero
	_comprobar(Servicios.comer_aqui("cafe") == "ok" and is_equal_approx(Juego.energia, 60.0) and Juego.dinero == din - 10, "tomar un café cuesta 10 € y da 20 de energía")
	Juego.energia = Juego.energia_max
	_comprobar(Servicios.comer_aqui("cafe") == "sin_hambre" and Juego.dinero == din - 10, "con la energía llena no se cobra")
	Juego.energia = 30.0
	Conversacion.hablar(ramon, _j)
	textos = _textos_pregunta()
	_comprobar("Comer aquí" in textos[0] and "Comprar para llevar" in textos[1], "menú de Ramón: comer aquí y para llevar")
	_pulsar("Comer aquí")
	var carta := _textos_pregunta()
	_comprobar(carta.size() == 5 and "Guiso" in carta[3], "la carta de la taberna tiene 4 platos y «Nada» (%s)" % str(carta))
	_pulsar("Tortilla")
	_pasar_dialogo()
	_comprobar(is_equal_approx(Juego.energia, 90.0) and Juego.dinero == din - 10 - 45, "comer tortilla: +60 de energía y −45 € (energía %.0f, dinero %d)" % [Juego.energia, Juego.dinero])
	Conversacion.hablar(ramon, _j)
	_pulsar("Comprar para llevar")
	_comprobar(_tienda().visible, "«Comprar para llevar» abre la tienda de la taberna")
	_tienda().cerrar_panel()
	_cerrar_todo()
	Juego.energia = Juego.energia_max
	_fin_de("servicios")


# --- Pozo, tablón, carro y bancos ------------------------------------------------------------------------------------

func _prueba_objetos_del_pueblo() -> void:
	print("[pozo, tablón, carro y bancos]")
	var obj := _mapa.get_node("Objetos/ObjetosPueblo") as ObjetosPueblo
	_comprobar(obj.construido, "los objetos del pueblo están construidos")
	_comprobar(obj.pozo.size() == 4 and obj.tablon != null and obj.carro != null and obj.bancos.size() == 2, "pozo (4 puntos), tablón, carro y 2 bancos")
	var interactuables: Array = []
	interactuables.append_array(obj.pozo)
	interactuables.append(obj.tablon)
	interactuables.append(obj.carro)
	interactuables.append_array(obj.bancos)
	for c: Interactuable in interactuables:
		_comprobar(c.is_in_group("interactuable") and not c.texto_interaccion().is_empty() and c.collision_layer == 4, "%s es un Interactuable de M1 con cartel" % c.name)
		_comprobar(not c.texto_interaccion().begins_with("Dormir"), "%s no dice «Dormir»" % c.name)

	# Pozo: se alcanza desde cualquier lado y da +5 de energía una vez al día.
	for a in [0.0, 90.0, 180.0, 270.0]:
		var dir := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a)))
		var pos := AyudasL4b.suelo(_mapa, dir * 2.8 + Vector3(0, 0.5, 0), 3.0, 6.0)
		if pos == Vector3.INF:
			pos = dir * 2.8
		_poner_a_leo(pos, -dir)
		var punto := obj.pozo[roundi(a / 90.0)]
		_j.camara.mirar_hacia(punto.global_position + Vector3.UP * 0.8)
		_j._actualizar_interactuable()
		_comprobar(Interfaz.texto_accion().contains("Sacar agua del pozo"), "al acercarse al pozo por el lado %d° sale «Sacar agua del pozo» (sale «%s»)" % [int(a), Interfaz.texto_accion()])
	Juego.energia = 50.0
	_comprobar(obj.sacar_agua() and is_equal_approx(Juego.energia, 55.0), "beber del pozo da +5 de energía")
	_comprobar(not obj.sacar_agua() and is_equal_approx(Juego.energia, 55.0), "solo una vez al día")
	Juego.terminar_dia(false)
	Juego.energia = 50.0
	_comprobar(obj.sacar_agua() and is_equal_approx(Juego.energia, 55.0), "al día siguiente vuelve a dar energía")

	# Tablón: encargos, entrega, dinero y amistad.
	var vistos: Dictionary = {}
	for i in 6:
		var ids := ObjetosPueblo.encargos_del_dia().map(func(x: Dictionary) -> String: return str(x["id"]))
		vistos["|".join(PackedStringArray(ids))] = true
		Juego.terminar_dia(false)
	_comprobar(vistos.size() >= 3, "los encargos cambian de un día a otro (%d combinaciones en 6 días)" % vistos.size())
	var hoy := ObjetosPueblo.encargos_del_dia()
	var e: Dictionary = hoy[0]
	var id_e := str(e["id"])
	_comprobar(ObjetosPueblo.entregar(id_e) == "faltan" or Juego.cantidad(str(e["pide"])) >= int(e["cantidad"]), "sin lo que piden no se entrega")
	Juego.anadir_objeto(str(e["pide"]), int(e["cantidad"]))
	var tengo0 := Juego.cantidad(str(e["pide"]))
	var dinero0 := Juego.dinero
	var amistad0 := Juego.puntos_amistad(str(e["npc"]))
	_comprobar(ObjetosPueblo.entregar(id_e) == "ok", "entregar el encargo funciona")
	_comprobar(Juego.dinero == dinero0 + int(e["dinero"]) and Juego.puntos_amistad(str(e["npc"])) == amistad0 + int(e["amistad"]) and Juego.cantidad(str(e["pide"])) == tengo0 - int(e["cantidad"]), "da %d € y %d de amistad y se gasta lo entregado" % [int(e["dinero"]), int(e["amistad"])])
	_comprobar(ObjetosPueblo.entregar(id_e) == "hecho", "un encargo no se entrega dos veces")
	_comprobar(ObjetosPueblo.entregar("no_existe") == "no_hoy", "un encargo que no está hoy no se puede entregar")
	obj.menu_tablon()
	var op := _textos_pregunta()
	_comprobar(op.size() == 4 and "Entregado" in op[0] and op[3].ends_with("Cerrar"), "el menú del tablón lista 3 encargos y «Cerrar» (%s)" % str(op))
	_pulsar("Cerrar")
	_comprobar(not Interfaz.ocupada(), "«Cerrar» cierra el tablón")
	# Por la vía real: junto al tablón sale su cartel.
	await _apuntar_interaccion(obj.tablon)
	_comprobar(Interfaz.texto_accion().contains("Leer el tablón"), "junto al tablón sale «E · Leer el tablón de anuncios» (sale «%s»)" % Interfaz.texto_accion())
	_cerrar_todo()

	# Carro y bancos.
	_comprobar(obj.carro.descripcion.length() > 40 and obj.carro.mostrar_descripcion, "el carro se examina con un texto")
	Juego.energia = 50.0
	var min0 := Juego.minutos
	obj.descansar()
	_comprobar(Juego.minutos == min0 + 15 and is_equal_approx(Juego.energia, 53.0), "sentarse en el banco: +15 minutos y +3 de energía")
	obj.sentarse()
	_comprobar(_pregunta().visible and "Sentarse" in _textos_pregunta()[0], "el banco pregunta antes de sentarse")
	_pulsar("Ahora no")
	for b in obj.bancos:
		_comprobar(b.global_position.distance_to(Vector3.ZERO) < 12.0 and _mapa.punto_dentro(b.global_position, 0.5), "%s está cerca de la plaza y dentro del mapa" % b.name)
	Juego.minutos = 600
	_fin_de("objetos")


# --- Horario en vivo -----------------------------------------------------------------------------------------------------------

func _prueba_horario() -> void:
	print("[horario]")
	Juego.clima = "despejado"
	var vecinos := _mapa.get_node("Objetos/Vecinos") as Vecinos
	var anselmo := _vecino(vecinos, "anselmo")
	var sitio0 := anselmo.sitio_actual
	var pos0 := anselmo.global_position
	# 13:00: el alcalde se va a la taberna.
	Juego.minutos = 779
	Juego.avanzar_minutos(1)
	_comprobar(anselmo.sitio_actual != sitio0 and anselmo.sitio_actual.begins_with("Spawn_Tabernero"), "a las 13:00 el alcalde cambia de sitio (%s)" % anselmo.sitio_actual)
	Engine.time_scale = 4.0
	await get_tree().create_timer(2.5).timeout
	Engine.time_scale = 1.0
	var tab := _mapa.call("marcador", "Spawn_Tabernero") as Marker3D
	_comprobar(anselmo.global_position.distance_to(tab.global_position) < pos0.distance_to(tab.global_position) - 2.0 or anselmo.global_position.distance_to(tab.global_position) < 6.0, "camina hacia su nuevo sitio (a %.1f m de la taberna, antes %.1f)" % [anselmo.global_position.distance_to(tab.global_position), pos0.distance_to(tab.global_position)])
	# 18:00: llega Tomás de la mina.
	Juego.minutos = 1079
	Juego.avanzar_minutos(1)
	_comprobar(vecinos.npcs.has("tomas"), "a las 18:00 Tomás llega a la taberna del pueblo")
	var tomas := _vecino(vecinos, "tomas")
	if tomas != null:
		_comprobar(tomas.global_position.distance_to(tab.global_position) < 6.0 and AyudasL4b.cabe(_mapa, tomas.global_position, 0.3, 1.5), "Tomás está junto a la taberna, en un sitio libre")
	# 18:00: Lucía se va a casa (se_va 1080) y a las 21:00 casi todos.
	_comprobar(not vecinos.npcs.has("lucia"), "a las 18:00 la maestra ya se ha ido")
	Juego.minutos = 1259
	Juego.avanzar_minutos(1)
	_comprobar(vecinos.npcs.keys() == ["ramon"], "a las 21:00 solo queda Ramón en la taberna (%s)" % str(vecinos.npcs.keys()))
	await get_tree().create_timer(1.2).timeout
	_comprobar(get_tree().get_nodes_in_group("npc").size() == 1, "los demás desaparecen del mapa (%d en el grupo npc)" % get_tree().get_nodes_in_group("npc").size())
	Juego.minutos = 1439
	Juego.avanzar_minutos(1)
	_comprobar(vecinos.npcs.is_empty(), "a las 00:00 Ramón cierra y no queda nadie")
	# Al día siguiente vuelven.
	Juego.terminar_dia(false)
	await get_tree().create_timer(0.8).timeout
	_comprobar(vecinos.npcs.has("mateo") and vecinos.npcs.has("ramon") and vecinos.npcs.has("marisol"), "al amanecer vuelven los vecinos")
	_comprobar(not vecinos.npcs.has("tomas"), "Tomás vuelve a la mina por la mañana")
	Juego.minutos = 600
	_fin_de("horario")


# --- Mina exterior ---------------------------------------------------------------------------------------------------------------

func _prueba_mina_exterior() -> void:
	print("[mina exterior]")
	Juego.banderas["nivel_mina"] = 2
	await _ir("mina_exterior")
	var vecinos := _mapa.get_node_or_null("Objetos/Vecinos") as Vecinos
	_comprobar(vecinos != null and _mapa.get_node_or_null("Objetos/BocaMina") != null, "la mina exterior tiene vecinos y boca")
	if vecinos == null:
		return
	_comprobar(int(Juego.banderas.get("nivel_mina", 0)) == 1, "al llegar a la mina de fuera el nivel vuelve a 1")
	_comprobar(vecinos.npcs.has("tomas") and vecinos.npcs.has("rufino") and vecinos.npcs.has("gema"), "a las 10:00 hay vecinos en la mina: Tomás, Rufino y Gema (%s)" % str(vecinos.npcs.keys()))
	for n: Npc in vecinos.npcs.values():
		var p := n.global_position
		_comprobar(AyudasL4b.cabe(_mapa, p, 0.3, 1.5) and _mapa.punto_dentro(p, 0.5), "%s está en un sitio libre y dentro del mapa" % n.id)
	var tomas := _vecino(vecinos, "tomas")
	var minero := _mapa.call("marcador", "Spawn_Minero") as Marker3D
	_comprobar(tomas != null and tomas.global_position.distance_to(minero.global_position) < 3.0, "Tomás está en Spawn_Minero")
	_poner_a_leo(tomas.global_position + Vector3(0, 0, 1.3), Vector3(0, 0, -1))
	_j.camara.mirar_hacia(tomas.punto_ojos())
	_j._actualizar_interactuable()
	_comprobar(Interfaz.texto_accion().contains("Hablar con Tomás"), "junto a Tomás sale «E · Hablar con Tomás» (sale «%s»)" % Interfaz.texto_accion())
	# Tomás compra minerales un 15 % más caros que Don Mateo.
	Juego.dinero = 100
	for m in ["piedra", "cobre", "hierro", "cuarzo", "patata"]:
		Juego.quitar_objeto(m, Juego.cantidad(m))
	Juego.anadir_objeto("cobre", 4)
	Juego.anadir_objeto("piedra", 6)
	Juego.anadir_objeto("patata", 2)
	_comprobar(Servicios.precio_mineral("cobre") > int(Datos.objeto("cobre")["precio_venta"]) and Servicios.precio_mineral("piedra") > int(Datos.objeto("piedra")["precio_venta"]), "Tomás paga más que Don Mateo (cobre %d frente a %d)" % [Servicios.precio_mineral("cobre"), int(Datos.objeto("cobre")["precio_venta"])])
	_comprobar(Servicios.minerales_en_mochila().size() == 2 and not Servicios.minerales_en_mochila().has("patata"), "solo compra minerales")
	Conversacion.hablar(tomas, _j)
	var textos := _textos_pregunta()
	_comprobar("Vender minerales" in textos[0] and "Preguntar por la mina" in textos[1], "menú de Tomás: vender minerales y preguntar por la mina (%s)" % str(textos))
	_pulsar("Vender minerales")
	var ofertas := _textos_pregunta()
	_comprobar(ofertas.size() == 4 and "Venderlo todo" in ofertas[2], "ofrece vender cada mineral, venderlo todo y «Nada» (%s)" % str(ofertas))
	var esperado := 4 * Servicios.precio_mineral("cobre") + 6 * Servicios.precio_mineral("piedra")
	_pulsar("Venderlo todo")
	_pasar_dialogo()
	_comprobar(Juego.dinero == 100 + esperado and Juego.cantidad("cobre") == 0 and Juego.cantidad("piedra") == 0 and Juego.cantidad("patata") == 2, "vender todo cobra %d € y no toca las patatas (dinero %d)" % [esperado, Juego.dinero])
	Conversacion.ejecutar("mina", tomas)
	var charla := _pasar_dialogo()
	_comprobar(charla.contains("dos niveles") and charla.contains("escalera"), "Tomás explica la mina y los niveles")
	Conversacion.ejecutar("minerales", tomas)
	_pasar_dialogo()
	_comprobar(not Interfaz.ocupada(), "sin minerales, Tomás lo dice y no queda nada abierto")
	_cerrar_todo()
	_fin_de("mina_exterior")


# --- Mina interior: rocas, nivel 2 ---------------------------------------------------------------------------------------------

## ¿Hay una roca de RocasMina dentro de la cápsula de Leo (radio 0,35) en este punto del suelo? Usa las formas físicas reales.
func _tocan_rocas(pos: Vector3) -> bool:
	var forma := CapsuleShape3D.new()
	forma.radius = 0.35
	forma.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma
	q.collision_mask = 64
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.0, 0))
	for h in _j.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var c := h["collider"] as Node
		if c != null and str(c.name).begins_with("Roca_"):
			return true
	return false


## ¿Se puede ir andando (cápsula de Leo contra el mundo y las rocas colocadas, con sus formas físicas) de `desde` a cerca de `hasta`?
func _alcanzable(desde: Vector3, hasta: Vector3, cerca: float) -> bool:
	var paso := 0.4
	var c0 := Vector2i(roundi(desde.x / paso), roundi(desde.z / paso))
	var vistos: Dictionary = {c0: desde.y}
	var cola: Array[Vector2i] = [c0]
	var cabeza := 0
	while cabeza < cola.size() and vistos.size() < 9000:
		var c := cola[cabeza]
		cabeza += 1
		var y_ref: float = vistos[c]
		if Vector2(float(c.x) * paso, float(c.y) * paso).distance_to(Vector2(hasta.x, hasta.z)) < cerca:
			return true
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if vistos.has(n):
				continue
			var s := AyudasL4b.suelo(_mapa, Vector3(float(n.x) * paso, y_ref, float(n.y) * paso), 0.9, 1.6)
			if s == Vector3.INF or absf(s.y - y_ref) > 0.4 or not AyudasL4b.cabe(_mapa, s, 0.35, 1.7) or _tocan_rocas(s):
				vistos[n] = null
				continue
			vistos[n] = s.y
			cola.append(n)
	return false


func _prueba_mina_interior() -> void:
	print("[mina interior, nivel 1]")
	Juego.banderas["nivel_mina"] = 1
	Juego.nivel_herramientas.clear()
	Juego.energia = Juego.energia_max
	await _ir("mina_interior", "Llegada_Interior")
	var rocas := _mapa.get_node_or_null("Objetos/RocasMina") as RocasMina
	var bajada := _mapa.get_node_or_null("Objetos/BajadaMina") as BajadaMina
	_comprobar(rocas != null and bajada != null, "la mina interior tiene RocasMina y BajadaMina")
	if rocas == null or bajada == null:
		return
	_comprobar(rocas.construido and rocas.nivel == 1, "las rocas se han construido para el nivel 1")
	_comprobar(rocas.rocas_en_pie().size() == 20, "20 rocas en el nivel 1 (%d)" % rocas.rocas_en_pie().size())
	_comprobar(rocas.cuenta_de("piedra") == 10 and rocas.cuenta_de("cobre") == 6 and rocas.cuenta_de("hierro") == 4 and rocas.cuenta_de("cuarzo") == 0, "reparto del nivel 1: 10 piedra, 6 cobre, 4 hierro, sin cuarzo")
	_comprobar(rocas.is_in_group("usable"), "RocasMina está en el grupo «usable»")
	var llegada := _mapa.call("marcador", "Llegada_Interior") as Marker3D
	var escalera := _mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	var salida := _mapa.call("marcador", "Entrada_Interior") as Marker3D
	for r in rocas.rocas_en_pie():
		var p := r.pos
		_comprobar(_mapa.punto_dentro(p, 0.3), "roca %s dentro del área jugable" % r.id)
		_comprobar(r.cuerpo != null and r.cuerpo.collision_layer == 64 and r.cuerpo.get_child_count() >= 3, "roca %s: sólida para Leo (capa 7) con malla, forma y marca" % r.id)
		_comprobar(AyudasL4b.suelo(_mapa, p + Vector3(0, 0.3, 0), 0.5, 1.5) != Vector3.INF, "roca %s apoyada en el suelo" % r.id)
		_comprobar(Vector2(p.x - llegada.global_position.x, p.z - llegada.global_position.z).length() > 3.5 and Vector2(p.x - escalera.global_position.x, p.z - escalera.global_position.z).length() > 3.5 and Vector2(p.x - salida.global_position.x, p.z - salida.global_position.z).length() > 3.5, "roca %s no tapa la llegada, la salida ni la escalera" % r.id)
		_comprobar((r.malla.mesh as ArrayMesh).get_surface_count() >= 1 and r.malla.mesh.get_aabb().size.length() > 0.4, "roca %s tiene una malla con volumen" % r.id)
	await _fisica(3)
	_comprobar(_alcanzable(llegada.global_position, escalera.global_position, 2.5), "con las rocas puestas se puede andar de la llegada a la escalera")
	_comprobar(_alcanzable(llegada.global_position, salida.global_position, 1.5), "y volver hasta la salida")
	print("   rocas: ", rocas.rocas_en_pie().size(), " colocadas; ", rocas.descartadas, " candidatas descartadas por cerrar el paso; ", rocas.celdas.size(), " casillas pisables")

	# Picar: la roca de piedra aguanta 2 golpes con el pico básico.
	var objetivo: RocasMina.Roca = null
	for r in rocas.rocas_en_pie():
		if r.tipo == "piedra":
			objetivo = r
			break
	var delante := objetivo.pos + Vector3(1.2, 0, 0)
	Juego.energia = 50.0
	Juego.elegir_ranura(4)
	_comprobar(str(Juego.objeto_activo().get("id", "")) == "pico", "la ranura 5 lleva el pico")
	_comprobar(not rocas.usar("azada", objetivo.pos, _j) and rocas.rocas_en_pie().has(objetivo), "con la azada la roca no cede")
	_comprobar(not rocas.usar("pico", objetivo.pos + Vector3(8, 0, 0), _j), "lejos de una roca el pico no hace nada")
	var piedra0 := Juego.cantidad("piedra")
	_comprobar(rocas.golpes_necesarios(objetivo) == 2, "la piedra pide 2 golpes con el pico básico")
	_comprobar(rocas.usar("pico", delante, _j) and is_equal_approx(Juego.energia, 48.0) and not objetivo.rota, "primer golpe: gasta 2 de energía y la roca sigue en pie")
	await _frames(20)
	_comprobar(rocas.usar("pico", delante, _j) and objetivo.rota, "segundo golpe: la roca se rompe")
	var obtenido := Juego.cantidad("piedra") - piedra0
	_comprobar(obtenido >= 2 and obtenido <= 4, "romper una roca de piedra suelta 2–4 piedras (%d)" % obtenido)
	_comprobar(not rocas.rocas_en_pie().has(objetivo) and rocas.rocas_en_pie().size() == 19, "queda una roca menos (%d)" % rocas.rocas_en_pie().size())
	_comprobar((RocasMina.estado()["rotas"] as Array).has(objetivo.id), "la roca rota queda anotada en Juego.estado_mapas")
	_comprobar(not rocas.usar("pico", delante, _j), "ya no hay roca en ese sitio")
	await _frames(40)
	_comprobar(objetivo.cuerpo == null or not is_instance_valid(objetivo.cuerpo) or objetivo.cuerpo.is_queued_for_deletion(), "la roca rota desaparece")
	# Mejores picos: menos golpes y menos energía.
	var cobre := rocas.rocas_en_pie().filter(func(r: RocasMina.Roca) -> bool: return r.tipo == "cobre")[0] as RocasMina.Roca
	_comprobar(rocas.golpes_necesarios(cobre) == 3 and is_equal_approx(RocasMina.energia_por_golpe(), 2.0), "cobre: 3 golpes y 2 de energía con el pico básico")
	Juego.nivel_herramientas["pico"] = 1
	_comprobar(rocas.golpes_necesarios(cobre) == 2 and is_equal_approx(RocasMina.energia_por_golpe(), 1.5), "con el pico de nivel 1: 2 golpes y 1,5 de energía")
	Juego.nivel_herramientas["pico"] = 2
	_comprobar(is_equal_approx(RocasMina.energia_por_golpe(), 1.0) and rocas.golpes_necesarios(cobre) == 1, "con el pico de nivel 2: 1 golpe y 1 de energía")
	# Por la vía de la mira y el pico equipado.
	_poner_a_leo(cobre.pos + Vector3(1.3, 0, 0), Vector3(-1, 0, 0))
	_j.camara.mirar_hacia(cobre.cuerpo.global_position + Vector3.UP * (cobre.radio * 0.4))
	for i in 10:
		if Juego.inventario[i].get("id", "") == "pico":
			Juego.elegir_ranura(i)
			break
	_j._actualizar_interactuable()
	_comprobar(Interfaz.texto_accion().contains("Picar la roca de cobre"), "al apuntar sale «Clic · Picar la roca de cobre» (sale «%s»)" % Interfaz.texto_accion())
	var cobre0 := Juego.cantidad("cobre")
	var e0 := Juego.energia
	_j._usar()
	_comprobar(cobre.rota and Juego.cantidad("cobre") > cobre0 and Juego.energia < e0, "usar el pico contra la roca suelta cobre (cobre +%d)" % (Juego.cantidad("cobre") - cobre0))
	Juego.nivel_herramientas["pico"] = 0
	# Sin energía no se pica.
	var otra := rocas.rocas_en_pie()[0]
	Juego.energia = 1.0
	_comprobar(not rocas.golpear(otra) and is_equal_approx(Juego.energia, 1.0) and otra.golpes_dados == 0, "sin energía no se golpea ni se gasta")
	Juego.energia = 80.0

	# La misma jornada, al volver a entrar, la roca rota no vuelve; al día siguiente sí.
	var en_pie := rocas.rocas_en_pie().size()
	await _ir("mina_interior", "Llegada_Interior")
	rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
	_comprobar(rocas.rocas_en_pie().size() == en_pie, "al volver a entrar el mismo día siguen rotas las mismas (%d de %d)" % [rocas.rocas_en_pie().size(), en_pie])
	Juego.terminar_dia(false)
	await _ir("mina_interior", "Llegada_Interior")
	rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
	_comprobar(rocas.rocas_en_pie().size() == 20, "al día siguiente vuelven a salir todas (%d)" % rocas.rocas_en_pie().size())
	bajada = _mapa.get_node("Objetos/BajadaMina") as BajadaMina
	escalera = _mapa.call("marcador", "Bajada_Nivel_2") as Marker3D     # el mapa es otra instancia: los marcadores de antes ya no valen

	print("[mina interior, nivel 2]")
	_comprobar(bajada.punto.activo and bajada.punto.texto_interaccion() == "Bajar al nivel 2", "la escalera dice «Bajar al nivel 2» (dice «%s»)" % bajada.punto.texto_interaccion())
	_comprobar(bajada.punto.global_position.distance_to(escalera.global_position) < 0.1, "la escalera está en Bajada_Nivel_2")
	await _apuntar_interaccion(bajada.punto)
	_comprobar(Interfaz.texto_accion().contains("Bajar al nivel 2"), "junto a la escalera sale «E · Bajar al nivel 2» (sale «%s»)" % Interfaz.texto_accion())
	var env1 := (_mapa.get_node("WorldEnvironment") as WorldEnvironment).environment
	var azul1 := env1.ambient_light_color.b - env1.ambient_light_color.r
	var energia_amb1 := env1.ambient_light_energy
	var niebla1 := env1.fog_density
	_j._interactuar()
	_comprobar(_pregunta().visible and "Bajar al nivel 2" in _textos_pregunta()[0], "E abre la pregunta de bajar")
	_pulsar("Bajar al nivel 2")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	await _frames(3)
	await _fisica(4)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	_comprobar(int(Juego.banderas.get("nivel_mina", 0)) == 2 and str(_mapa.get("id_mapa")) == "mina_interior", "bajar recarga la mina interior con nivel_mina = 2")
	var llegada2 := _mapa.call("marcador", "Llegada_Interior") as Marker3D
	var escalera2 := _mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
	_comprobar(_j.global_position.distance_to(llegada2.global_position) < 2.0, "se llega a Llegada_Interior")
	rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
	bajada = _mapa.get_node("Objetos/BajadaMina") as BajadaMina
	_comprobar(rocas.nivel == 2 and rocas.rocas_en_pie().size() == 28, "28 rocas en el nivel 2 (%d)" % rocas.rocas_en_pie().size())
	_comprobar(rocas.cuenta_de("cuarzo") == 6 and rocas.cuenta_de("hierro") == 9 and rocas.cuenta_de("cuarzo") > 0, "el nivel 2 tiene cuarzo (%d) y más hierro (%d)" % [rocas.cuenta_de("cuarzo"), rocas.cuenta_de("hierro")])
	_comprobar(bajada.punto.texto_interaccion() == "Subir al nivel 1", "abajo la escalera dice «Subir al nivel 1»")
	var env2 := (_mapa.get_node("WorldEnvironment") as WorldEnvironment).environment
	var azul2 := env2.ambient_light_color.b - env2.ambient_light_color.r
	_comprobar(azul2 > azul1 + 0.2 and env2.ambient_light_color.b > env2.ambient_light_color.r, "el nivel 2 es más azul (%.2f frente a %.2f)" % [azul2, azul1])
	_comprobar(env2.ambient_light_energy < energia_amb1 and env2.fog_density > niebla1, "y más oscuro (ambiente %.2f frente a %.2f; niebla %.3f frente a %.3f)" % [env2.ambient_light_energy, energia_amb1, env2.fog_density, niebla1])
	_comprobar(_alcanzable(llegada2.global_position, escalera2.global_position, 2.5), "en el nivel 2 también se puede llegar a la escalera")
	# Cuarzo: más golpes y suelta cuarzo.
	var cuarzo: RocasMina.Roca = null
	for r in rocas.rocas_en_pie():
		if r.tipo == "cuarzo":
			cuarzo = r
			break
	Juego.energia = 90.0
	var cz0 := Juego.cantidad("cuarzo")
	_comprobar(rocas.golpes_necesarios(cuarzo) == 4, "el cuarzo pide 4 golpes con el pico básico")
	for i in 4:
		rocas.golpear(cuarzo)
	_comprobar(cuarzo.rota and Juego.cantidad("cuarzo") >= cz0 + 1 and Juego.cantidad("cuarzo") <= cz0 + 2, "romper una roca de cuarzo da 1–2 cuarzos (%d)" % (Juego.cantidad("cuarzo") - cz0))

	# No se puede salir del nivel 2 (mismos muros que el nivel 1): cada lado del polígono tiene muro y Leo, empujado, no sale.
	var pol: PackedVector2Array = _mapa.poligono_limites
	var n := pol.size()
	_comprobar(n >= 3 and _mapa.get_node_or_null("Limites") != null, "el nivel 2 tiene polígono y muro de límites")
	var espacio := _j.get_world_3d().direct_space_state
	var caja: AABB = _mapa.call("aabb_mapa")
	var y := caja.position.y + 2.0
	var lados := 0
	var cuerpo := _mapa.get_node("Limites")
	for i in n:
		var a := pol[i]
		var b := pol[(i + 1) % n]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var dentro_v := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon(mid + dentro_v * 0.6, pol):
			dentro_v = -dentro_v
		var rq := PhysicsRayQueryParameters3D.create(Vector3(mid.x + dentro_v.x, y, mid.y + dentro_v.y), Vector3(mid.x - dentro_v.x, y, mid.y - dentro_v.y), 32)
		var h := espacio.intersect_ray(rq)
		if not h.is_empty() and h["collider"] == cuerpo:
			lados += 1
	_comprobar(lados == n, "nivel 2: los %d lados del polígono tienen muro (%d)" % [n, lados])
	var fuera := 0
	var por_la_boca := 0
	for dir_empuje in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var yaw := atan2(-dir_empuje.x, -dir_empuje.z)
		_j.colocar(llegada2.global_position + Vector3(0, 0.05, 0), 0.0, yaw)
		_j._pos_segura = llegada2.global_position
		await _fisica(6)
		Input.action_press("mover_arriba")
		Input.action_press("correr")
		await _fisica(240)
		Input.action_release("mover_arriba")
		Input.action_release("correr")
		if not is_instance_valid(_j) or Escenas.mapa_actual_nodo() != _mapa:
			# Corriendo hacia la boca (a 3 m de la llegada) Leo sale de la mina por la salida de verdad: eso no es
			# escaparse del área. Se vuelve al nivel 2 y se sigue con los demás lados.
			por_la_boca += 1
			await _esperar_transicion()
			Juego.banderas["nivel_mina"] = 2
			await _ir("mina_interior", "Llegada_Interior")
			llegada2 = _mapa.call("marcador", "Llegada_Interior") as Marker3D
			escalera2 = _mapa.call("marcador", "Bajada_Nivel_2") as Marker3D
			rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
			bajada = _mapa.get_node("Objetos/BajadaMina") as BajadaMina
			continue
		if not _mapa.punto_dentro(_j.global_position):
			fuera += 1
	_comprobar(por_la_boca <= 1, "nivel 2: como mucho un lado lleva a la boca de la mina (%d)" % por_la_boca)
	_comprobar(fuera == 0, "nivel 2: empujado por los cuatro lados Leo no sale del área jugable (%d salidas)" % fuera)
	_comprobar(_j.dentro_de_limites(), "nivel 2: Leo sigue dentro de los límites")

	# Subir otra vez al nivel 1 y salir por la boca: el nivel vuelve a 1.
	await _apuntar_interaccion(bajada.punto)
	bajada.preguntar()
	_comprobar(_pregunta().visible and "Subir al nivel 1" in _textos_pregunta()[0], "abajo, la escalera pregunta si subir")
	_pulsar("Subir al nivel 1")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	await _frames(3)
	await _fisica(4)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	rocas = _mapa.get_node("Objetos/RocasMina") as RocasMina
	_comprobar(int(Juego.banderas.get("nivel_mina", 0)) == 1 and rocas.nivel == 1 and rocas.rocas_en_pie().size() >= 19, "subir vuelve al nivel 1 (%d rocas)" % rocas.rocas_en_pie().size())
	Juego.banderas["nivel_mina"] = 2
	await _ir("mina_exterior")
	_comprobar(int(Juego.banderas.get("nivel_mina", 0)) == 1, "al salir de la mina por la boca el nivel vuelve a 1")
	_fin_de("mina_interior")


# --- Guardado --------------------------------------------------------------------------------------------------------------------

func _prueba_guardado() -> void:
	print("[guardado]")
	Juego.banderas["nivel_mina"] = 2
	var rotas0: Array = (RocasMina.estado()["rotas"] as Array).duplicate()
	Juego.estado_mapas["pueblo"]["pozo_dia"] = AyudasL4b.clave_dia()
	Juego.amistad["clara"] = 33
	_comprobar(Juego.guardar(), "se guarda la partida")
	var texto := FileAccess.get_file_as_string(Juego.ruta_partida)
	var json := JSON.new()
	_comprobar(json.parse(texto) == OK, "el guardado es un JSON válido (estado de mapas, banderas y amistad)")
	Juego.estado_mapas = {}
	Juego.banderas = {}
	Juego.amistad = {}
	_comprobar(Juego.cargar(), "se carga la partida")
	_comprobar(int(Juego.banderas.get("nivel_mina", 0)) == 2 and Juego.puntos_amistad("clara") == 33, "se recuperan el nivel de la mina y la amistad")
	_comprobar((Juego.estado_mapas["mina_interior"]["rotas"] as Array) == rotas0, "se recuperan las rocas rotas del día")
	_comprobar(int(Juego.estado_mapas["pueblo"]["pozo_dia"]) == AyudasL4b.clave_dia(), "se recupera lo hecho en el pozo hoy")
	_fin_de("guardado")
