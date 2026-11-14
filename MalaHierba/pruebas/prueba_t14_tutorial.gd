extends Node
## Regresión completa de T14-tutorial:
## - Secuencia de día 1 en orden estricto (mover → labrar → sembrar → regar → dormir)
## - Hitos contextuales (cosechar → vender, pueblo, amistad → regalos, mina, dinero → mejoras)
## - Nunca bloquea el juego ni Interfaz.ocupada(), muestra tecla/botón del mando real
## - Se cierra con la tecla asignada, se desactiva en Ajustes y no se repite tras guardar y cargar.

const ESPERADO := ["mover", "labrar", "sembrar", "regar", "dormir", "vender", "pueblo", "regalos", "mina", "mejoras"]

var _fallos: Array[String] = []
var _total := 0
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if not _terminado:
			print("PRUEBA T14 TUTORIAL TIMEOUT")
			_finalizar(1))
	_ejecutar.call_deferred()


func _comprobar(cond: bool, desc: String) -> void:
	_total += 1
	if not cond:
		_fallos.append(desc)
		print("FALLO: ", desc)


func _hud() -> Hud:
	return Interfaz.get("_hud") as Hud


func _esperar_frames(n: int = 4) -> void:
	for i in n:
		await get_tree().process_frame


func _esperar_transicion() -> void:
	var t0 := Time.get_ticks_msec()
	while Escenas.en_transicion and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await _esperar_frames(6)


func _pulsar_tecla(codigo: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = codigo
	ev.pressed = true
	Input.parse_input_event(ev)
	await _esperar_frames(3)
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = codigo
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await _esperar_frames(2)


func _pulsar_mando(boton: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = boton
	ev.pressed = true
	Input.parse_input_event(ev)
	await _esperar_frames(3)
	var ev_up := InputEventJoypadButton.new()
	ev_up.button_index = boton
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await _esperar_frames(2)


func _buscar_parcela(estado: String) -> String:
	var p := Cultivos.parcelas()
	for k: Variant in p:
		var d: Dictionary = p[k]
		if str(d.get("estado", "")) == estado and str(d.get("cultivo", "")) == "":
			return str(k)
	return ""


func _finalizar(codigo: int) -> void:
	if _terminado:
		return
	_terminado = true
	get_tree().quit(codigo)


func _ejecutar() -> void:
	var ruta_aj := Ajustes.ruta
	var vals_aj := Ajustes.valores.duplicate()
	var teclas_aj := Ajustes.teclas.duplicate()
	var ruta_part := Juego.ruta_partida

	Ajustes.ruta = "user://ajustes_prueba_t14.cfg"
	Ajustes.restaurar()
	Juego.ruta_partida = "user://partida_prueba_t14.json"
	Juego.borrar_partida()

	# 1. Día 1: comprobar orden estricto, formato teclado/mando, no bloqueo y cierre con tecla
	get_tree().current_scene = null
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.clima = "sol"
	Juego.dinero = 50   # por debajo del coste de mejoras para probar su disparador después
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()

	var hud := _hud()
	_comprobar(hud != null, "existe el HUD")
	_comprobar(Tutorial.actual() == "mover" and hud.tutorial_visible(), "día 1 empieza mostrando 'mover'")
	_comprobar(not Interfaz.ocupada(), "el aviso de tutorial nunca bloquea el juego")
	var txt_teclado := hud.texto_tutorial()
	_comprobar(txt_teclado.contains("WASD") and txt_teclado.contains("Mayús"), "muestra teclas de teclado para moverse")
	_comprobar(txt_teclado.count(".") <= 2, "aviso breve de 1 o 2 frases (%s)" % txt_teclado)

	# Cambio dinámico a mando: cambia el texto a controles de mando
	await _pulsar_mando(JOY_BUTTON_LEFT_STICK)
	await _esperar_frames(4)
	_comprobar(Ajustes.ultimo_mando, "detecta uso de mando")
	_comprobar(hud.texto_tutorial().contains("palanca izquierda"), "aviso cambia dinámicamente a mando (%s)" % hud.texto_tutorial())
	# Vuelta a teclado
	await _pulsar_tecla(KEY_SHIFT)
	await _esperar_frames(4)
	_comprobar(not Ajustes.ultimo_mando and hud.texto_tutorial().contains("WASD"), "vuelve a mostrar teclas de teclado")

	# Cierre con tecla asignada (T)
	await _pulsar_tecla(KEY_T)
	_comprobar(Tutorial.actual() == "" and not hud.tutorial_visible(), "pulsar T cierra inmediatamente el aviso actual")
	_comprobar(Tutorial.esta_visto("mover"), "el aviso cerrado con tecla queda marcado como visto")

	# Tras pasar la pausa de cierre, avanza a 'labrar'
	await get_tree().create_timer(Tutorial.PAUSA_TRAS_CIERRE + 0.15).timeout
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "labrar" and hud.tutorial_visible(), "tras 'mover' muestra 'labrar'")

	# Siembra / labrado / riego reales sobre parcela
	var k := _buscar_parcela("limpio")
	if k.is_empty():
		k = "Zona_Cultivo_1:0,0"
		Cultivos.parcelas()[k] = Cultivos.nueva_parcela("limpio")
	_comprobar(Cultivos.aplicar("azada", [k]), "labrar parcela real")
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "sembrar" and hud.tutorial_visible(), "tras labrar muestra 'sembrar'")

	_comprobar(Cultivos.aplicar("semilla_patata", [k]), "sembrar semilla real")
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "regar" and hud.tutorial_visible(), "tras sembrar muestra 'regar'")

	_comprobar(Cultivos.aplicar("regadera", [k]), "regar parcela real")
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "dormir" and hud.tutorial_visible(), "tras regar muestra 'dormir'")

	# Dormir pasa al día 2 y completa 'dormir'
	Juego.terminar_dia(false)
	await _esperar_frames(3)
	_comprobar(Juego.dia == 2 and Tutorial.esta_hecho("dormir"), "dormir pasa al día 2 y completa el paso de dormir")
	_comprobar(not Tutorial.esta_visto("mejoras"), "con 50 € aún no muestra el aviso de mejoras")

	# 2. Cosechar por primera vez -> 'vender'
	Cultivos.parcelas()[k]["cultivo"] = "patata"
	Cultivos.parcelas()[k]["listo"] = true
	_comprobar(Cultivos.cosechar(k), "cosechar cultivo listo")
	await _esperar_frames(4)
	_comprobar(Tutorial.actual() == "vender" and hud.tutorial_visible(), "al cosechar por primera vez muestra 'vender'")
	await _pulsar_tecla(KEY_T)
	_comprobar(Tutorial.actual() == "", "cierra 'vender' con T")

	# 3. Primera vez en pueblo -> 'pueblo', luego primera amistad -> 'regalos'
	Escenas.ir_a_mapa("pueblo", "Llegada_Granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(Tutorial.actual() == "pueblo" and hud.tutorial_visible(), "primera vez en pueblo muestra 'pueblo'")

	Juego.subir_amistad("mateo", 5)
	await _esperar_frames(4)
	_comprobar(Tutorial.actual() == "regalos" and hud.tutorial_visible(), "tras la primera amistad pasa de 'pueblo' a 'regalos'")
	await _pulsar_tecla(KEY_T)

	# 4. Abrir/entrar en la mina -> 'mina'
	Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(Tutorial.actual() == "mina" and hud.tutorial_visible(), "al entrar en la mina muestra 'mina'")
	await _pulsar_tecla(KEY_T)
	await get_tree().create_timer(Tutorial.PAUSA_TRAS_CIERRE + 0.15).timeout
	await _esperar_frames(3)

	# 5. Tener dinero suficiente -> 'mejoras'
	_comprobar(not Tutorial.esta_visto("mejoras"), "antes de tener dinero suficiente no ha salido 'mejoras'")
	Juego.ingresar(400)
	await _esperar_frames(4)
	_comprobar(Tutorial.actual() == "mejoras" and hud.tutorial_visible(), "al alcanzar dinero suficiente muestra 'mejoras'")
	await _pulsar_tecla(KEY_T)

	# Verificar orden estricto de todos los hitos
	var orden := Tutorial.orden_mostrado()
	_comprobar(orden == ESPERADO, "el orden completo es exacto: %s" % str(orden))

	# 6. Guardar y cargar: no se repiten tras guardar y cargar
	_comprobar(Juego.guardar(), "guarda la partida con el historial del tutorial")
	Juego.nueva_partida("Otro")
	await _esperar_frames(2)
	_comprobar(Tutorial.orden_mostrado().is_empty(), "una partida nueva reinicia el tutorial")
	_comprobar(Juego.cargar(), "carga la partida guardada")
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(Tutorial.actual() == "" and not hud.tutorial_visible(), "tras cargar no reaparece ningún aviso ya mostrado")

	# Repetir todas las acciones después de cargar -> ninguno se repite
	var k2 := _buscar_parcela("limpio")
	if not k2.is_empty():
		Cultivos.aplicar("azada", [k2])
		Cultivos.aplicar("semilla_patata", [k2])
		Cultivos.aplicar("regadera", [k2])
	var p2 := Cultivos.parcelas()
	p2[k]["cultivo"] = "patata"
	p2[k]["listo"] = true
	Cultivos.cosechar(k)
	Escenas.ir_a_mapa("pueblo", "Llegada_Granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	Juego.subir_amistad("clara", 5)
	Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	Juego.ingresar(500)
	await _esperar_frames(4)
	_comprobar(Tutorial.actual() == "" and not hud.tutorial_visible(), "ningún aviso se repite tras guardar, cargar y repetir las acciones")
	_comprobar(Tutorial.orden_mostrado() == ESPERADO, "el historial guardado permanece idéntico (%s)" % str(Tutorial.orden_mostrado()))

	# 7. Guardado a medias en día 1: ver mover+labrar, guardar, cargar en día 1 y comprobar no repetición ni salto atrás
	Juego.borrar_partida()
	Juego.nueva_partida("Leo")
	Juego.dinero = 50
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(Tutorial.actual() == "mover", "segunda partida empieza en 'mover'")
	await _pulsar_tecla(KEY_T)
	await get_tree().create_timer(Tutorial.PAUSA_TRAS_CIERRE + 0.15).timeout
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "labrar", "pasa a 'labrar'")
	_comprobar(Juego.guardar(), "guarda en día 1 a mitad de tutorial")
	Juego.nueva_partida("Otro2")
	_comprobar(Juego.cargar(), "carga partida a mitad de día 1")
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(Tutorial.actual() == "sembrar", "al recargar en día 1 no repite 'mover' ni 'labrar' y sigue por 'sembrar'")
	_comprobar(Tutorial.orden_mostrado().count("mover") == 1 and Tutorial.orden_mostrado().count("labrar") == 1, "mover y labrar siguen con una sola aparición")

	# 8. Desactivar en Ajustes
	Ajustes.poner("tutorial", false)
	await _esperar_frames(3)
	_comprobar(not Tutorial.hay_aviso_activo() and not hud.tutorial_visible(), "desactivar en Ajustes oculta los avisos")
	Escenas.ir_a_mapa("pueblo", "Llegada_Granja")
	await Escenas.mapa_cargado
	await _esperar_transicion()
	_comprobar(not hud.tutorial_visible() and not Tutorial.esta_visto("pueblo"), "con tutorial desactivado no muestra 'pueblo' al entrar")

	# Comprobar opción visible en PanelAjustes -> Accesibilidad
	Interfaz.abrir_ajustes()
	Interfaz._ajustes._mostrar_pagina(2)
	await _esperar_frames(3)
	var encontro_check := false
	for nodo: Node in Interfaz._ajustes._contenido.find_children("*", "Label", true, false):
		if (nodo as Label).text.contains("Avisos del tutorial"):
			encontro_check = true
			break
	_comprobar(encontro_check, "el panel de Ajustes incluye el interruptor de Avisos del tutorial")
	Interfaz.cerrar_todo()

	Ajustes.poner("tutorial", true)
	await _esperar_frames(3)
	_comprobar(Tutorial.actual() == "pueblo" and hud.tutorial_visible(), "reactivar en Ajustes vuelve a mostrar avisos no vistos")

	# Limpieza
	Juego.borrar_partida()
	Juego.ruta_partida = ruta_part
	Juego.partida_activa = false
	Ajustes.ruta = ruta_aj
	Ajustes.valores = vals_aj
	Ajustes.teclas = teclas_aj
	Ajustes._aplicar_teclas()
	Ajustes.aplicar()
	DirAccess.remove_absolute("user://ajustes_prueba_t14.cfg")

	print("PRUEBA T14 TUTORIAL OK (%d comprobaciones)" % _total if _fallos.is_empty() else "PRUEBA T14 TUTORIAL FALLO: %d de %d (%s)" % [_fallos.size(), _total, str(_fallos)])
	_finalizar(0 if _fallos.is_empty() else 1)
