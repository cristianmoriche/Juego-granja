extends Node
## Comprueba cobertura de recursos e interacciones reales; con ventana guarda las capturas de T01.

const SALIDA := "res://../gestion/noche-codex/capturas/T01-iconos/"
var _fallos: Array[String] = []
var _total := 0


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(valor: bool, texto: String) -> void:
	_total += 1
	if not valor:
		_fallos.append(texto)
		push_error(texto)


func _foto(nombre: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var ruta := ProjectSettings.globalize_path(SALIDA + nombre + ".png")
	_comprobar(get_viewport().get_texture().get_image().save_png(ruta) == OK, "Captura " + nombre)


func _revisar_icono(id: String) -> void:
	_comprobar(Datos.tiene_icono(id), "Existe ilustración: " + id)
	var textura := Datos.icono(id)
	_comprobar(textura.get_size() == Vector2(128, 128), "128 px: " + id)
	var imagen := textura.get_image()
	_comprobar(imagen.detect_alpha() != Image.ALPHA_NONE, "Transparencia: " + id)
	_comprobar(imagen.get_pixel(0, 0).a == 0.0, "Margen transparente: " + id)


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	var objetos: Array = JSON.parse_string(FileAccess.get_file_as_string("res://datos/objetos.json"))
	for objeto: Dictionary in objetos:
		_revisar_icono(str(objeto["id"]))
	for herramienta in Servicios.HERRAMIENTAS:
		for nivel in range(1, 4):
			_revisar_icono(Datos.id_icono(herramienta, nivel))
	if not _fallos.is_empty():
		_terminar()
		return

	await Escenas.ir_a_mapa("granja")
	Juego.pausar_tiempo(true)
	# Dos páginas muestran todos los objetos sin tocar una partida guardada.
	for pagina in 2:
		for i in Juego.HUECOS:
			var indice := pagina * 30 + i
			Juego.inventario[i] = {"id": str(objetos[indice]["id"]), "cantidad": 12} if indice < objetos.size() else {}
		Juego.inventario_cambiado.emit()
		Interfaz.abrir_inventario()
		await _foto("inventario_%d" % (pagina + 1))
		Interfaz.cerrar_todo()
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Interfaz.mostrar_hud(true)
	Interfaz.abrir_tienda("tienda_mateo")
	var tienda: PanelTienda = Interfaz.get_node("Raiz/Tienda")
	for estacion in 4:
		Juego.estacion = estacion
		tienda.abrir("tienda_mateo")
		for id in tienda._ids_visibles():
			var fila := tienda._fila(id)
			var ic := fila.get_child(0).get_child(0) as TextureRect
			_comprobar(ic.texture == Datos.icono(id), "Lista de tienda ilustrada: " + id)
			fila.free()
		await _foto("tienda_" + Juego.nombre_estacion().to_lower())
	Juego.estacion = 0
	tienda.abrir("tienda_mateo")
	tienda._elegir("pan")
	var dinero_antes := Juego.dinero
	var pan_antes := Juego.cantidad("pan")
	tienda._confirmar()
	_comprobar(Juego.dinero == dinero_antes - 12 and Juego.cantidad("pan") == pan_antes + 1, "Compra real de pan")
	Interfaz.cerrar_todo()
	Juego.anadir_objeto("cuarzo", 3)
	await _foto("recompensa_objeto")
	Interfaz.abrir_tienda("taberna")
	await _foto("tienda_taberna")
	Interfaz.cerrar_todo()
	Juego.anadir_objeto("patata", 5)
	Interfaz.abrir_tienda("tienda_mateo")
	tienda._cambiar_modo("vender")
	tienda._elegir("patata")
	dinero_antes = Juego.dinero
	tienda._confirmar()
	var precio_patata := int(Datos.objeto("patata").get("precio_venta", 0))
	_comprobar(Juego.cantidad("patata") == 4 and Juego.dinero == dinero_antes + precio_patata, "Venta real de patata")
	await _foto("tienda_venta")
	Interfaz.cerrar_todo()
	var pueblo := ObjetosPueblo.new()
	pueblo.menu_tablon()
	var pregunta: PanelPregunta = Interfaz.get_node("Raiz/Pregunta")
	var encargos := ObjetosPueblo.encargos_del_dia()
	var idx_entrega := 0
	for i in encargos.size():
		var e: Dictionary = encargos[i]
		var tipo := str(e.get("tipo", "entregar"))
		var id_ico := str(e.get("pide", "")) if tipo == "entregar" else str(e.get("icono", "pan"))
		_comprobar(pregunta._botones[i].icon == Datos.icono(id_ico), "Encargo ilustrado")
		if tipo == "entregar" and idx_entrega == 0:
			idx_entrega = i
	await _foto("encargos")
	var encargo: Dictionary = encargos[idx_entrega]
	var pide_id := str(encargo.get("pide", str(encargo.get("icono", "pan"))))
	if str(encargo.get("tipo", "entregar")) == "entregar":
		Juego.anadir_objeto(pide_id, int(encargo.get("cantidad", 1)))
	dinero_antes = Juego.dinero
	pregunta._elegir(idx_entrega)
	_comprobar(ObjetosPueblo.encargo_hecho(str(encargo["id"])), "Encargo entregado")
	_comprobar(Juego.dinero == dinero_antes + int(encargo["dinero"]), "Recompensa cobrada")
	var dialogo: PanelDialogo = Interfaz.get_node("Raiz/Dialogo")
	_comprobar(dialogo._icono.visible and dialogo._icono.texture == Datos.icono(pide_id), "Recompensa ilustrada")
	dialogo._avanzar()
	await _foto("recompensa_encargo")
	Interfaz.cerrar_todo()
	for nivel in range(1, 4):
		for herramienta in Servicios.HERRAMIENTAS:
			Juego.nivel_herramientas[herramienta] = nivel - 1
		Juego.dinero = 10000
		for material in ["cobre", "hierro", "cuarzo"]:
			Juego.anadir_objeto(material, 10)
		Servicios.menu_herreria("Clara")
		_comprobar(pregunta._botones[0].icon == Datos.icono(Datos.id_icono("azada", nivel)), "Mejora ilustrada de nivel %d" % nivel)
		await _foto("mejoras_nivel_%d" % nivel)
		pregunta._elegir(0)
		_comprobar(Juego.nivel("azada") == nivel, "Mejora real de nivel %d" % nivel)
		dialogo._avanzar()
		await _foto("herramienta_mejorada_%d" % nivel)
		Interfaz.cerrar_todo()
	pueblo.free()
	_terminar()


func _terminar() -> void:
	if _fallos.is_empty():
		print("PRUEBA ICONOS OK (%d comprobaciones)" % _total)
	else:
		print("PRUEBA ICONOS FALLO: ", _fallos)
	get_tree().quit(0 if _fallos.is_empty() else 1)
