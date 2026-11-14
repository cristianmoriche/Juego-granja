extends Node
## Prueba de M1 (cámara libre, límites, interacciones, minimapa, iconos). Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_m1.tscn
## Imprime «PRUEBA OK (N comprobaciones)» o «PRUEBA FALLO: <motivos>» y sale con 0 o 1.
## Con las mismas clases de verdad: Escenas.ir_a_mapa, el jugador, la cámara, los muros de la capa 6, el minimapa y la
## Interfaz; el teclado y el ratón se simulan con eventos que entran por el viewport (igual que los de un jugador).

const MAPAS := ["granja", "pueblo", "mina_exterior", "mina_interior"]

var _fallos: Array[String] = []
var _total: int = 0
var _mapa: Node = null
var _j: Jugador = null
var _usos: int = 0


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _fisica(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_m1.json"
	Juego.nueva_partida("Leo")

	_prueba_iconos()
	await _ir("granja")
	await _prueba_camara()
	await _prueba_interacciones()
	await _prueba_mapa_grande()
	for id: String in MAPAS:
		if str(_mapa.get("id_mapa")) != id:
			await _ir(id)
		await _prueba_mapa(id)
		if id == "granja":
			await _prueba_cartel_no_se_queda()   # termina en el pueblo
	await _prueba_aviso_herramienta()

	_soltar_teclas()
	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
		Juego.borrar_partida()   # también la copia de seguridad y los restos de un guardado
	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)), "  (%d comprobaciones)" % _total)
		get_tree().quit(1)


# --- Utilidades ---------------------------------------------------------------------------------------------------

## Entra en un mapa de verdad y espera a que estén las vallas y la foto del minimapa.
func _ir(id: String) -> void:
	print("[mapa %s]" % id)
	var mm: Minimapa = Interfaz.minimapa()
	var fotos_antes := mm.fotos_hechas
	var llegada := "Llegada_Interior" if id == "mina_interior" else "Spawn_Protagonista"
	await Escenas.ir_a_mapa(id, llegada)
	_mapa = Escenas.mapa_actual_nodo()
	_j = Escenas.jugador() as Jugador
	for _i in 120:
		if bool(_mapa.get("vallas_listas")) and mm.fotos_hechas > fotos_antes:
			break
		await get_tree().process_frame
	_comprobar(_mapa != null and str(_mapa.get("id_mapa")) == id, "%s: se carga el mapa" % id)
	_comprobar(_j != null, "%s: hay jugador" % id)
	Interfaz.cerrar_todo()


func _soltar_teclas() -> void:
	for a in ["mover_arriba", "mover_abajo", "mover_izquierda", "mover_derecha", "correr"]:
		Input.action_release(a)


func _tecla(codigo: Key, pulsada: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.keycode = codigo
	ev.physical_keycode = codigo
	ev.pressed = pulsada
	get_viewport().push_input(ev)


func _boton(indice: MouseButton, pulsado: bool, ctrl: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = indice
	ev.pressed = pulsado
	ev.ctrl_pressed = ctrl
	ev.position = Vector2(400, 300)
	ev.global_position = ev.position
	get_viewport().push_input(ev)


func _raton(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = Vector2(400, 300)
	ev.global_position = ev.position
	get_viewport().push_input(ev)


func _suelo(x: float, z: float) -> float:
	var col: Dictionary = _mapa.call("_columna_suelo", x, z)
	return float(col["suelo"])


func _distancia_a_borde(p: Vector2, poligono: PackedVector2Array) -> float:
	var mejor := INF
	for i in poligono.size():
		var c := Geometry2D.get_closest_point_to_segment(p, poligono[i], poligono[(i + 1) % poligono.size()])
		mejor = minf(mejor, c.distance_to(p))
	return mejor


func _cerca_de_salida(p: Vector3, radio: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group("salida"):
		if (n as Node3D).global_position.distance_to(p) < radio:
			return true
	return false


func _poner_a_leo(pos: Vector3, yaw: float) -> void:
	_j.colocar(pos, 0.0, yaw)
	_j._pos_segura = pos
	_j.direccion = Vector3(0, 0, -1).rotated(Vector3.UP, yaw)


# --- Iconos -----------------------------------------------------------------------------------------------------------

func _prueba_iconos() -> void:
	print("[iconos]")
	Datos.recargar_iconos()
	var sin_archivo: Texture2D = Datos.icono("_sin_icono_prueba_m1")
	_comprobar(sin_archivo != null and sin_archivo.get_width() > 0, "Datos.icono devuelve una textura aunque no haya archivo")
	_comprobar(not Datos.tiene_icono("_sin_icono_prueba_m1"), "un id sin archivo usa la textura de reserva")
	var carpeta := ProjectSettings.globalize_path("res://assets/iconos")
	var existia := DirAccess.dir_exists_absolute(carpeta)
	DirAccess.make_dir_recursive_absolute(carpeta)
	var ruta := carpeta.path_join("_prueba_m1.png")
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.2))
	img.save_png(ruta)
	Datos.recargar_iconos()
	var con_archivo: Texture2D = Datos.icono("_prueba_m1")
	_comprobar(con_archivo != null and con_archivo.get_width() == 32, "Datos.icono carga el PNG de assets/iconos")
	_comprobar(Datos.tiene_icono("_prueba_m1"), "tiene_icono es true con archivo")
	DirAccess.remove_absolute(ruta)
	if not existia:
		DirAccess.remove_absolute(carpeta)
	Datos.recargar_iconos()


# --- Cámara -------------------------------------------------------------------------------------------------------------

func _prueba_camara() -> void:
	print("[cámara]")
	var cam := _j.camara
	var y0 := _suelo(-5.8, 1.8)
	_poner_a_leo(Vector3(-5.8, y0 + 0.05, 1.8), 0.0)
	await _fisica(6)
	await get_tree().process_frame

	# Órbita libre de 360°: la cámara se queda detrás, a cualquier ángulo.
	cam.pitch = deg_to_rad(30.0)
	for k in 8:
		var yaw := -PI + TAU * float(k) / 8.0
		cam.yaw = yaw
		cam.call("_aplicar", 0.0)
		var pivote: Vector3 = cam.global_position
		var h := Vector2(cam.camara.global_position.x - pivote.x, cam.camara.global_position.z - pivote.z)
		_comprobar(absf(angle_difference(atan2(h.x, h.y), yaw)) < 0.03, "la cámara queda detrás de Leo con giro %d°" % int(rad_to_deg(yaw)))
		_comprobar(cam.camara.global_position.y > pivote.y, "la cámara está por encima del punto de mira (giro %d°)" % int(rad_to_deg(yaw)))

	# Inclinación limitada a 8°–80°.
	cam.inclinar(10.0)
	_comprobar(is_equal_approx(cam.pitch, CamaraJuego.PITCH_MAX), "la inclinación máxima es de 80°")
	cam.inclinar(-10.0)
	_comprobar(is_equal_approx(cam.pitch, CamaraJuego.PITCH_MIN), "la inclinación mínima es de 8°")

	# Zoom de 2,5 a 22 m con suavidad.
	cam.pitch = deg_to_rad(35.0)
	for _i in 80:
		cam.zoom_rueda(-1)
	await _esperar(1.5)
	_comprobar(absf(cam.distancia - CamaraJuego.DIST_MIN) < 0.1, "zoom mínimo 2,5 m (da %.2f)" % cam.distancia)
	for _i in 80:
		cam.zoom_rueda(1)
	await _esperar(1.5)
	_comprobar(absf(cam.distancia - CamaraJuego.DIST_MAX) < 0.2, "zoom máximo 22 m (da %.2f)" % cam.distancia)

	# No atraviesa paredes: Leo pegado a la pared oeste de la cabaña y la cámara detrás, dentro de la cabaña.
	var yp := _suelo(-9.0, -3.0)
	_poner_a_leo(Vector3(-9.0, yp + 0.05, -3.0), PI * 0.5)
	cam.pitch = deg_to_rad(10.0)
	cam._dist_obj = 9.0
	cam.distancia = 9.0
	await _esperar(0.6)
	_comprobar(cam.distancia_real < 6.0, "la cámara se acerca ante la pared de la cabaña (%.2f de 9 m)" % cam.distancia_real)
	var espacio := _j.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.camara.global_position, 1)
	rq.exclude = [_j.get_rid()]
	_comprobar(espacio.intersect_ray(rq).is_empty(), "entre Leo y la cámara no hay paredes")
	# No atraviesa el suelo: a ras de suelo y desde varios lados, la cámara queda por encima del terreno.
	_poner_a_leo(Vector3(-5.8, _suelo(-5.8, 15.0) + 0.05, 15.0), 0.0)
	cam.pitch = CamaraJuego.PITCH_MIN
	cam._dist_obj = 14.0
	cam.distancia = 14.0
	var bajo_suelo := 0
	var atraviesa := 0
	for k in 12:
		cam.yaw = TAU * float(k) / 12.0
		cam.call("_aplicar", 0.0)
		var p: Vector3 = cam.camara.global_position
		var rd := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6, 0), p + Vector3(0, -6, 0), 1)
		var hd := espacio.intersect_ray(rd)
		if not hd.is_empty() and (hd["position"] as Vector3).y > p.y - 0.05:
			bajo_suelo += 1
		var rs := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1)
		rs.exclude = [_j.get_rid()]
		if not espacio.intersect_ray(rs).is_empty():
			atraviesa += 1
	_comprobar(bajo_suelo == 0, "la cámara nunca queda bajo el terreno (%d de 12 giros)" % bajo_suelo)
	_comprobar(atraviesa == 0, "la cámara nunca atraviesa nada a ras de suelo (%d de 12 giros)" % atraviesa)

	# Tercera persona baja: cerca y casi horizontal se ve a Leo.
	_poner_a_leo(Vector3(-5.8, y0 + 0.05, 1.8), 0.0)
	cam.yaw = 0.0
	cam.pitch = deg_to_rad(12.0)
	cam._dist_obj = 3.2
	cam.distancia = 3.2
	await _esperar(0.5)
	_comprobar(cam.distancia_real > 2.0 and cam.distancia_real <= 3.3, "tercera persona baja a %.2f m" % cam.distancia_real)

	# Leo se mueve relativo a la cámara: con la cámara mirando a −X, W lleva a −X.
	_poner_a_leo(Vector3(-5.8, y0 + 0.05, 1.8), PI * 0.5)
	await _fisica(8)
	var antes := _j.global_position
	Input.action_press("mover_arriba")
	await _fisica(45)
	Input.action_release("mover_arriba")
	var delta := _j.global_position - antes
	_comprobar(delta.x < -1.0 and absf(delta.z) < 0.5, "W lleva hacia donde mira la cámara (dx %.2f, dz %.2f)" % [delta.x, delta.z])

	# Clic derecho + ratón gira; la rueda cambia de ranura sin hacer zoom ni mover cámara; clic central vuelve a la vista de juego.
	_poner_a_leo(Vector3(-5.8, y0 + 0.05, 1.8), 0.0)
	cam.pitch = deg_to_rad(40.0)
	cam._dist_obj = 12.0
	cam.distancia = 12.0
	await _fisica(4)
	var yaw_antes := cam.yaw
	var pitch_antes := cam.pitch
	_boton(MOUSE_BUTTON_RIGHT, true)
	await get_tree().process_frame
	_comprobar(_j._girando, "el clic derecho empieza el giro")
	if DisplayServer.get_name() != "headless":
		_comprobar(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "el cursor se oculta mientras se gira")
	_raton(Vector2(120, 30))
	_comprobar(absf(angle_difference(cam.yaw, yaw_antes)) > 0.5, "mover el ratón con el clic derecho gira la cámara")
	_comprobar(cam.pitch > pitch_antes + 0.1, "y la inclina")
	_boton(MOUSE_BUTTON_RIGHT, false)
	await get_tree().process_frame
	_comprobar(not _j._girando, "soltar el clic derecho termina el giro")
	if DisplayServer.get_name() != "headless":
		_comprobar(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "el cursor vuelve al soltar")
	var yaw_quieto := cam.yaw
	_raton(Vector2(200, 0))
	_comprobar(is_equal_approx(cam.yaw, yaw_quieto), "sin clic derecho el ratón no gira la cámara")

	var d0: float = cam._dist_obj
	var yaw_r := cam.yaw
	var pitch_r := cam.pitch
	Juego.elegir_ranura(0)
	_boton(MOUSE_BUTTON_WHEEL_DOWN, true)
	_comprobar(Juego.ranura == 1, "rueda hacia abajo pasa al objeto siguiente (0 -> 1)")
	_comprobar(is_equal_approx(cam._dist_obj, d0) and is_equal_approx(cam.yaw, yaw_r) and is_equal_approx(cam.pitch, pitch_r), "la rueda no hace zoom ni mueve la cámara")
	_boton(MOUSE_BUTTON_WHEEL_UP, true)
	_comprobar(Juego.ranura == 0, "rueda hacia arriba vuelve al objeto anterior (1 -> 0)")
	_boton(MOUSE_BUTTON_WHEEL_UP, true)
	_comprobar(Juego.ranura == 9, "rueda hacia arriba da la vuelta en el extremo (0 -> 9)")
	_boton(MOUSE_BUTTON_WHEEL_DOWN, true)
	_comprobar(Juego.ranura == 0, "rueda hacia abajo da la vuelta en el extremo (9 -> 0)")
	_comprobar(is_equal_approx(cam._dist_obj, d0), "la rueda repetida tampoco altera el zoom")
	Juego.elegir_ranura(0)

	_boton(MOUSE_BUTTON_MIDDLE, true)
	_comprobar(cam._volviendo, "el clic central empieza a volver a la vista de juego")
	await _esperar(2.5)
	_comprobar(absf(cam.pitch - CamaraJuego.PITCH_JUEGO) < 0.03 and absf(cam._dist_obj - CamaraJuego.DIST_JUEGO) < 0.01, "vista de juego restaurada (inclinación %.1f°)" % rad_to_deg(cam.pitch))
	_tecla(KEY_C)
	_tecla(KEY_C, false)
	_comprobar(cam._volviendo or absf(angle_difference(cam.yaw, cam._yaw_juego)) < 0.05, "la tecla C también vuelve a la vista de juego")


# --- Interacciones --------------------------------------------------------------------------------------------------------

func _prueba_interacciones() -> void:
	print("[interacciones]")
	var y0 := _suelo(-5.8, 1.8)
	# L5: la puerta de la cabaña lleva a casa_leo («Entrar en la cabaña»); «Dormir» vive dentro de casa_leo.
	var puerta := _mapa.call("marcador", "Puerta_Cabana") as Marker3D
	_comprobar(puerta != null, "la granja tiene el marcador Puerta_Cabana")
	var dormir := 0
	for n: Node in get_tree().get_nodes_in_group("interactuable"):
		if str(n.call("texto_interaccion")).begins_with("Dormir"):
			dormir += 1
	_comprobar(dormir == 0, "en el exterior de la granja no hay «Dormir» (vive en casa_leo; hay %d)" % dormir)
	var en_puerta := puerta.global_position + Vector3(0, 0.05, 0.6)
	_poner_a_leo(en_puerta, 0.0)    # mira hacia −Z, hacia la puerta (la cabaña queda al norte)
	await _fisica(4)
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo != null and str(_j._objetivo.call("texto_interaccion")) == "Entrar en la cabaña", "junto a la puerta se puede entrar en la cabaña")
	_comprobar(Interfaz.texto_accion() == "E  ·  Entrar en la cabaña", "el cartel dice «E · Entrar en la cabaña» (dice «%s»)" % Interfaz.texto_accion())
	_poner_a_leo(Vector3(12.0, _suelo(12.0, 20.0) + 0.05, 20.0), 0.0)
	_j._actualizar_interactuable()
	var dormir_lejos := _j._objetivo != null and str(_j._objetivo.call("texto_interaccion")).begins_with("Dormir")
	_comprobar(not dormir_lejos, "lejos de la cabaña no sale «Dormir»")

	# Interactuable de ejemplo: cartel con verbo y objeto, resaltado, señal y descripción
	# (en una zona despejada del patio para no solaparse con Puerta_Cabana en (-5.75, 0.86)).
	var y_cartel := _suelo(0.0, 6.0)
	_poner_a_leo(Vector3(0.0, y_cartel + 0.05, 6.0), 0.0)
	await _fisica(4)
	var adelante := _j.direccion
	var c := Interactuable.new()
	c.verbo = "Leer"
	c.nombre_objeto = "el cartel"
	c.descripcion = "Texto de prueba.\n\nSegundo párrafo."
	c.radio = 0.8
	_mapa.objetos.add_child(c)
	c.global_position = _j.global_position + adelante * 1.0
	_usos = 0
	c.usado.connect(func(_jug: Node3D) -> void: _usos += 1)
	await get_tree().process_frame
	_j._actualizar_interactuable()
	_comprobar(c.texto_interaccion() == "Leer el cartel", "texto del interactuable: verbo + objeto")
	_comprobar(_j._objetivo == c, "Leo elige el interactuable que tiene delante")
	_comprobar(Interfaz.texto_accion() == "E  ·  Leer el cartel", "cartel de acción «E · Leer el cartel» (dice «%s»)" % Interfaz.texto_accion())
	_comprobar(_j._resaltador.objetivo == c and _j._resaltador.visible, "el objetivo elegido se resalta")
	_comprobar(c.is_in_group("interactuable") and c.collision_layer == 4, "el interactuable está en la capa 3 y en su grupo")
	# El más de frente gana.
	var atras := Interactuable.new()
	atras.verbo = "Mirar"
	atras.nombre_objeto = "lo de atrás"
	atras.radio = 0.8
	_mapa.objetos.add_child(atras)
	atras.global_position = _j.global_position - adelante * 1.0
	await get_tree().process_frame
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo == c, "con dos cerca gana el de delante")
	_j.direccion = -adelante
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo == atras, "al girar gana el otro")
	_j.direccion = adelante
	atras.queue_free()
	# Usarlo.
	_j._actualizar_interactuable()
	_j._interactuar()
	_comprobar(_usos == 1, "E dispara la señal usado")
	_comprobar(Interfaz.ocupada(), "la descripción se muestra en un cuadro de diálogo")
	Interfaz.cerrar_todo()
	# Desactivado o lejos: sin cartel.
	c.activo = false
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo != c and Interfaz.texto_accion() != "E  ·  Leer el cartel", "desactivado no sale")
	c.activo = true
	_j.global_position += Vector3(8, 0, 0)
	_j._actualizar_interactuable()
	_comprobar(_j._objetivo == null and not _j._resaltador.visible and Interfaz.texto_accion().is_empty(), "lejos desaparecen el cartel y el resaltado")
	c.queue_free()


## Con «E · Entrar en la cabaña» a la vista se entra en el pueblo: el cartel no puede seguir ahí.
func _prueba_cartel_no_se_queda() -> void:
	print("[el cartel no se queda al cambiar de mapa]")
	var puerta := _mapa.call("marcador", "Puerta_Cabana") as Marker3D
	_poner_a_leo(puerta.global_position + Vector3(0, 0.05, 0.6), 0.0)
	await _fisica(4)
	_j._actualizar_interactuable()
	_comprobar(Interfaz.texto_accion().contains("cabaña"), "antes de salir se ve «Entrar en la cabaña» junto a la puerta")
	await _ir("pueblo")
	await _esperar(0.5)
	_comprobar(not Interfaz.texto_accion().contains("Dormir"), "en el pueblo no sale «Dormir» (dice «%s»)" % Interfaz.texto_accion())
	_comprobar(Interfaz.texto_accion().is_empty(), "en el pueblo, al aparecer, no hay cartel (dice «%s»)" % Interfaz.texto_accion())


# --- Mapa grande ------------------------------------------------------------------------------------------------------------

func _prueba_mapa_grande() -> void:
	print("[mapa grande]")
	var mm: Minimapa = Interfaz.minimapa()
	_comprobar(mm.is_visible_in_tree(), "el minimapa se ve en el juego")
	_comprobar(mm.get_global_rect().position.x < 40.0 and mm.get_global_rect().position.y < 40.0, "el minimapa está arriba a la izquierda")
	_comprobar(not Interfaz.mapa_grande_abierto(), "el mapa grande empieza cerrado")
	_tecla(KEY_M)
	_tecla(KEY_M, false)
	await get_tree().process_frame
	_comprobar(Interfaz.mapa_grande_abierto(), "M abre el mapa grande")
	_comprobar(Interfaz.ocupada(), "con el mapa abierto Leo no se mueve (panel ocupado)")
	var antes := _j.global_position
	Input.action_press("mover_arriba")
	await _fisica(30)
	Input.action_release("mover_arriba")
	_comprobar(_j.global_position.distance_to(antes) < 0.2, "con el mapa abierto Leo está quieto")
	_tecla(KEY_M)
	_tecla(KEY_M, false)
	await get_tree().process_frame
	_comprobar(not Interfaz.mapa_grande_abierto(), "M lo cierra")
	_tecla(KEY_M)
	_tecla(KEY_M, false)
	await get_tree().process_frame
	_comprobar(Interfaz.mapa_grande_abierto(), "M lo vuelve a abrir")
	_tecla(KEY_ESCAPE)
	_tecla(KEY_ESCAPE, false)
	await get_tree().process_frame
	_comprobar(not Interfaz.mapa_grande_abierto() and not Interfaz.ocupada(), "Esc lo cierra (y no abre la pausa)")
	var grande: MapaGrande = Interfaz.get_node("Raiz/MapaGrande")
	Interfaz.alternar_mapa()
	await get_tree().process_frame
	var area := grande.area_foto()
	_comprobar(Interfaz.mapa_grande_abierto() and area.size.x > 200.0 and area.size.y > 200.0, "el mapa grande ocupa casi toda la pantalla (%s)" % str(area.size))
	var rect := mm.rect_mundo
	var norte_oeste := grande.mundo_a_pantalla(rect.position)
	var sur_este := grande.mundo_a_pantalla(rect.end)
	_comprobar(norte_oeste.x < sur_este.x and norte_oeste.y < sur_este.y, "el mapa grande está orientado al norte")
	Interfaz.alternar_mapa()


# --- Cada mapa ----------------------------------------------------------------------------------------------------------------

func _prueba_mapa(id: String) -> void:
	var mm: Minimapa = Interfaz.minimapa()
	var pol: PackedVector2Array = _mapa.poligono_limites
	var n := pol.size()

	# Polígono, muro invisible y marcadores dentro.
	_comprobar(n >= 3, "%s: tiene polígono de límites" % id)
	_comprobar(_mapa.get_node_or_null("Limites") != null, "%s: tiene el muro de límites" % id)
	_comprobar(_j.dentro_de_limites(), "%s: Leo empieza dentro" % id)
	for tipo in ["spawn", "salida"]:
		for m: Marker3D in _mapa.call("marcadores_de_tipo", tipo):
			_comprobar(_mapa.punto_dentro(m.global_position, 0.5), "%s: %s está dentro de los límites" % [id, m.name])

	# Cada lado del polígono tiene muro: un rayo que lo cruza en la capa 6 lo toca; la cámara (capa 1) no lo ve.
	var espacio := _j.get_world_3d().direct_space_state
	var caja: AABB = _mapa.call("aabb_mapa")
	var y := caja.position.y + 2.0
	var lados_con_muro := 0
	var muro_visible_a_camara := 0
	var cuerpo := _mapa.get_node("Limites")
	for i in n:
		var a := pol[i]
		var b := pol[(i + 1) % n]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var dentro_v := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon(mid + dentro_v * 0.6, pol):
			dentro_v = -dentro_v
		var p_in := Vector3(mid.x + dentro_v.x, y, mid.y + dentro_v.y)
		var p_out := Vector3(mid.x - dentro_v.x, y, mid.y - dentro_v.y)
		var r6 := PhysicsRayQueryParameters3D.create(p_in, p_out, 32)
		var h6 := espacio.intersect_ray(r6)
		if not h6.is_empty() and h6["collider"] == cuerpo:
			lados_con_muro += 1
		var r1 := PhysicsRayQueryParameters3D.create(p_in, p_out, 1)
		var h1 := espacio.intersect_ray(r1)
		if not h1.is_empty() and h1["collider"] == cuerpo:
			muro_visible_a_camara += 1
	_comprobar(lados_con_muro == n, "%s: los %d lados tienen muro (%d)" % [id, n, lados_con_muro])
	_comprobar(muro_visible_a_camara == 0, "%s: el muro no está en la capa 1 (la cámara no choca)" % id)

	# Leo no sale: se le empuja hacia fuera por los lados con valla y dos más.
	await _prueba_salir_del_mapa(id)

	# Vallas visibles.
	var con_valla := n - LimitesMapa.lados_sin_valla(id).size()
	if LimitesMapa.tipo_valla(id) == "ninguna" or con_valla <= 0:
		_comprobar(_mapa.vallas == null, "%s: sin vallas" % id)
	else:
		_comprobar(int(_mapa.get("numero_postes")) >= 5 and int(_mapa.get("numero_travesanos")) >= 4, "%s: hay valla de madera (%d postes, %d travesaños)" % [id, int(_mapa.get("numero_postes")), int(_mapa.get("numero_travesanos"))])

	# Salidas señaladas.
	_comprobar(get_tree().get_nodes_in_group("salida").size() == Datos.conexiones_de(id).size(), "%s: las salidas están en el grupo «salida»" % id)

	# Dormir solo en casa_leo (ningún mapa exterior tiene «Dormir»).
	var dormir := 0
	for nodo: Node in get_tree().get_nodes_in_group("interactuable"):
		if str(nodo.call("texto_interaccion")).begins_with("Dormir"):
			dormir += 1
	_comprobar(dormir == 0, "%s: «Dormir» no existe en el exterior (vive en casa_leo; hay %d)" % [id, dormir])
	if id != "granja":
		_j._actualizar_interactuable()
		_comprobar(_j._objetivo == null or not str(_j._objetivo.call("texto_interaccion")).begins_with("Dormir"), "%s: al aparecer no sale «E · Dormir»" % id)

	# Interactuables de ejemplo.
	var esperados := _puntos_esperados(id)
	var puntos: Array = _mapa.puntos_interes
	_comprobar(puntos.size() == esperados, "%s: %d interactuables de ejemplo (esperados %d)" % [id, puntos.size(), esperados])
	for p: Interactuable in puntos:
		_comprobar(p.is_in_group("interactuable") and not p.texto_interaccion().is_empty() and not p.descripcion.is_empty(), "%s: %s tiene verbo, objeto y texto" % [id, p.name])
		_comprobar(_mapa.punto_dentro(p.global_position, 0.5), "%s: %s está dentro de los límites" % [id, p.name])

	# Cuevas: la cámara no choca con el techo invisible y no se queda pegada a Leo.
	if bool(_mapa.get("interior")):
		await _esperar(0.8)
		_comprobar(_j.camara.distancia_real > 3.5, "%s: la cámara no se queda pegada a Leo (%.2f m)" % [id, _j.camara.distancia_real])
		var aparte := _mapa.get_node_or_null("ColisionSoloJugador") as StaticBody3D
		_comprobar(aparte != null and aparte.collision_layer == 64 and aparte.get_child_count() > 0, "%s: techo y maderas están en la capa 7 (solo Leo choca)" % id)
		var restos := 0
		var rocas := 0
		for h: Node in (_mapa.cargador.get("colisiones") as Node).get_children():
			if String(h.name).contains("Roca"):
				rocas += 1
			elif h is CollisionShape3D:
				restos += 1
		_comprobar(restos == 0 and rocas > 0, "%s: en la capa 1 queda solo la roca (%d formas de roca, %d de otra cosa)" % [id, rocas, restos])

	# Minimapa.
	_comprobar(mm.lista() and mm.id_mapa == id, "%s: el minimapa tiene su foto" % id)
	_comprobar(mm.textura != null and mm.textura.get_width() > 16 and mm.textura.get_height() > 16, "%s: la foto del minimapa tiene tamaño" % id)
	_comprobar(mm.rect_mundo.size.x > 10.0 and mm.rect_mundo.size.y > 10.0, "%s: el minimapa cubre una zona del mapa" % id)
	_comprobar(mm.nombre_mapa == LimitesMapa.nombre(id) and not mm.nombre_mapa.is_empty(), "%s: el minimapa lleva el nombre del mapa (%s)" % [id, mm.nombre_mapa])
	_poner_a_leo(_j.global_position, 0.0)
	var leo2 := Vector2(_j.global_position.x, _j.global_position.z)
	_comprobar(mm.mundo_a_pantalla(leo2).distance_to(mm._centro()) < 0.01, "%s: Leo está en el centro del minimapa" % id)
	var uv := mm.uv_de(leo2)
	_comprobar(uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0, "%s: Leo cae dentro de la foto" % id)
	var p_mundo := leo2 + Vector2(5.0, 3.0)
	_comprobar(mm.pantalla_a_mundo(mm.mundo_a_pantalla(p_mundo)).distance_to(p_mundo) < 0.01, "%s: del mundo a la pantalla y vuelta" % id)
	# Gira con la cámara: arriba es hacia donde mira.
	_j.camara.yaw = 0.0
	var norte := mm.mundo_a_pantalla(leo2 + Vector2(0, -10))
	_comprobar(norte.y < mm._centro().y - 20.0 and absf(norte.x - mm._centro().x) < 0.1, "%s: con la cámara al norte, el norte está arriba" % id)
	_j.camara.yaw = PI * 0.5
	var oeste := mm.mundo_a_pantalla(leo2 + Vector2(-10, 0))
	_comprobar(oeste.y < mm._centro().y - 20.0 and absf(oeste.x - mm._centro().x) < 0.1, "%s: con la cámara al oeste, el oeste está arriba" % id)
	mm._poner_norte()
	var pn := mm.posicion_norte()
	_comprobar(pn.x > mm._centro().x + 20.0 and absf(pn.y - mm._centro().y) < 8.0, "%s: la «N» gira con la cámara (queda a la derecha)" % id)
	_j.camara.yaw = 0.0
	_comprobar(FotoCenital.ultimo_ms < 2000, "%s: la foto cenital tardó %d ms" % [id, FotoCenital.ultimo_ms])


func _puntos_esperados(id: String) -> int:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://datos/puntos_interes.json")) != OK:
		return -1
	var d: Dictionary = json.data
	return (d.get(id, []) as Array).size()


## Empuja a Leo (corriendo) hacia fuera por cada lado con valla y dos lados más: debe seguir dentro y llegar al muro.
func _prueba_salir_del_mapa(id: String) -> void:
	var pol: PackedVector2Array = _mapa.poligono_limites
	var n := pol.size()
	var con_valla: Array[int] = []
	var sin_valla: Array[int] = LimitesMapa.lados_sin_valla(id)
	for i in n:
		if not sin_valla.has(i) and LimitesMapa.tipo_valla(id) != "ninguna":
			con_valla.append(i)
	var lados: Array[int] = con_valla.duplicate()
	var extra := 0
	for i in n:
		if sin_valla.has(i) and extra < 2:
			lados.append(i)
			extra += 1
	var probados := 0
	var probados_valla := 0
	var fuera := 0
	var llegaron := 0
	var llegaron_valla := 0
	for i in lados:
		var a := pol[i]
		var b := pol[(i + 1) % n]
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var hacia_dentro := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon(mid + hacia_dentro * 0.6, pol):
			hacia_dentro = -hacia_dentro
		var s2 := mid + hacia_dentro * 2.0
		var col: Dictionary = _mapa.call("_columna_suelo", s2.x, s2.y)
		var ys := float(col["suelo"])
		if is_nan(ys) or float(col["obstaculo"]) > 0.4:
			continue
		var inicio := Vector3(s2.x, ys + 0.05, s2.y)
		if not _mapa.punto_dentro(inicio) or _cerca_de_salida(inicio, 6.0):
			continue
		var afuera := -hacia_dentro
		_poner_a_leo(inicio, atan2(-afuera.x, -afuera.y))
		await _fisica(6)
		Input.action_press("mover_arriba")
		Input.action_press("correr")
		await _fisica(120)
		_soltar_teclas()
		var p3 := _j.global_position
		var p2 := Vector2(p3.x, p3.z)
		probados += 1
		if con_valla.has(i):
			probados_valla += 1
		if not _mapa.punto_dentro(p3):
			fuera += 1
		if _distancia_a_borde(p2, pol) < 1.0:
			llegaron += 1
			if con_valla.has(i):
				llegaron_valla += 1
	print("   ", id, ": empujado hacia fuera por ", probados, " lados; llegó al muro en ", llegaron, " (", llegaron_valla, " con valla)")
	_comprobar(fuera == 0, "%s: Leo no sale del mapa (%d de %d empujones lo sacaron)" % [id, fuera, probados])
	if probados_valla > 0:
		_comprobar(llegaron_valla >= 1, "%s: en los lados con valla Leo llega hasta el muro (%d de %d)" % [id, llegaron_valla, probados_valla])
	# Control (solo en la granja): sin muro ni red de seguridad, el mismo empujón sí lo saca. Demuestra que la prueba mide algo.
	if id == "granja" and not con_valla.is_empty():
		var i2: int = con_valla[0]
		var a2 := pol[i2]
		var b2 := pol[(i2 + 1) % n]
		var mid2 := (a2 + b2) * 0.5
		var dir2 := (b2 - a2).normalized()
		var hd2 := Vector2(-dir2.y, dir2.x)
		if not Geometry2D.is_point_in_polygon(mid2 + hd2 * 0.6, pol):
			hd2 = -hd2
		var s3 := mid2 + hd2 * 2.0
		var y3 := _suelo(s3.x, s3.y)
		_j.collision_mask &= ~Jugador.CAPA_LIMITES
		_j._mapa = null
		var af2 := -hd2
		_poner_a_leo(Vector3(s3.x, y3 + 0.05, s3.y), atan2(-af2.x, -af2.y))
		await _fisica(6)
		Input.action_press("mover_arriba")
		Input.action_press("correr")
		await _fisica(120)
		_soltar_teclas()
		_comprobar(not _mapa.punto_dentro(_j.global_position), "control: sin muro, el mismo empujón saca a Leo del polígono")
		_j.collision_mask |= Jugador.CAPA_LIMITES
		_j.configurar_para_mapa(_mapa)
		_poner_a_leo(inicio_seguro(), 0.0)
	# Red de seguridad: si algo lo sacara, vuelve al último punto firme dentro.
	var seguro := inicio_seguro()
	_poner_a_leo(seguro, 0.0)
	await _fisica(30)
	_j.global_position = Vector3(pol[0].x - 30.0, seguro.y + 5.0, pol[0].y - 30.0)
	await _fisica(10)
	_comprobar(_j.dentro_de_limites(), "%s: la red de seguridad devuelve a Leo si acaba fuera" % id)


## Punto firme dentro del mapa donde dejar a Leo: el marcador de aparición.
func inicio_seguro() -> Vector3:
	var m := _mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	var p := m.global_position
	var y := _suelo(p.x, p.z)
	if not is_nan(y):
		p.y = y
	return p + Vector3(0, 0.05, 0)


# --- Aviso de herramienta sin efecto -------------------------------------------------------------------------------------------

func _prueba_aviso_herramienta() -> void:
	print("[herramientas]")
	_comprobar(Jugador.motivo_sin_efecto("azada") == "Aquí no hay nada que cavar.", "aviso de la azada")
	_comprobar(Jugador.motivo_sin_efecto("regadera") == "Aquí no hay nada que regar.", "aviso de la regadera")
	_comprobar(Jugador.motivo_sin_efecto("pico") == "Aquí no hay nada que picar.", "aviso del pico")
	await _ir("pueblo")
	Juego.elegir_ranura(0)
	await _fisica(4)
	var antes := Interfaz.avisos_emitidos
	_j._usar()
	_comprobar(Interfaz.avisos_emitidos == antes + 1, "la azada donde no hay nada que cavar avisa")
	_j._usar()
	_comprobar(Interfaz.avisos_emitidos == antes + 1, "el aviso no se repite en cada clic")
	Interfaz.cerrar_todo()
