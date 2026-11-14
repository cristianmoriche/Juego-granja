extends Node
## Capturas reproducibles del menú y de los ajustes, con el renderizador real.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ejecutar.call_deferred()

func _ejecutar() -> void:
	var antes := not has_node("/root/Ajustes")
	var carpeta := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T06-ajustes/")
	DirAccess.make_dir_recursive_absolute(carpeta)
	var menu := load("res://escenas/menu_principal.tscn").instantiate() as Control
	add_child(menu)
	for tam: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(tam)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta + ("antes" if antes else "despues") + "_menu_%dx%d.png" % [tam.x, tam.y])
		if not antes:
			Interfaz.call("abrir_ajustes")
			Interfaz.get("_ajustes").call("_mostrar_pagina", 0)
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(carpeta + "ajustes_%dx%d.png" % [tam.x, tam.y])
			for pagina in 4:
				Interfaz.get("_ajustes").call("_mostrar_pagina", pagina)
				await get_tree().create_timer(0.3).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(carpeta + "ajustes_%dx%d_pagina%d.png" % [tam.x, tam.y, pagina])
			Ajustes.ruta = "res://../gestion/noche-codex/registros/T06-ajustes/ajustes_capturas.cfg"
			Ajustes.poner("texto", 2)
			Ajustes.poner("alto_contraste", true)
			Interfaz.get("_ajustes").call("_mostrar_pagina", 2)
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(carpeta + "accesibilidad_%dx%d.png" % [tam.x, tam.y])
			Ajustes.restaurar()
			Interfaz.get("_ajustes").call("cerrar")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await get_tree().create_timer(0.3).timeout
	menu.queue_free()
	get_tree().current_scene = null
	Juego.nueva_partida("Prueba de ajustes")
	Juego.pausar_tiempo(true)
	Escenas.ir_a_mapa("granja")
	await Escenas.mapa_cargado
	while Escenas.en_transicion:
		await get_tree().process_frame
	for pantalla: String in ["granja", "pausa", "inventario", "tienda"]:
		Interfaz.cerrar_todo()
		match pantalla:
			"pausa": Interfaz.get("_pausa").call("abrir")
			"inventario": Interfaz.abrir_inventario()
			"tienda": Interfaz.abrir_tienda("tienda_mateo")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta + ("antes_" if antes else "despues_") + pantalla + ".png")
	if not antes:
		Interfaz.cerrar_todo()
		for calidad in 3:
			Ajustes.poner("calidad", calidad)
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(carpeta + "granja_calidad%d.png" % calidad)
		Ajustes.restaurar()
		DisplayServer.window_set_size(Vector2i(1280, 720))
		for grande: bool in [false, true]:
			Ajustes.poner("texto", 2 if grande else 0)
			Ajustes.poner("alto_contraste", grande)
			for pantalla: String in ["dialogo", "inventario", "pregunta", "pausa", "mapa"]:
				Interfaz.cerrar_todo()
				match pantalla:
					"dialogo":
						Interfaz.mostrar_dialogo("Don Mateo", ["Bienvenido a Villaverde. En la tienda encontrarás semillas, comida y herramientas para sacar adelante El Granado. Cuida los cultivos, visita a tus vecinos y vuelve cuando necesites algo."], Callable())
						Interfaz._dialogo._avanzar()
					"inventario": Interfaz.abrir_inventario()
					"pregunta": Interfaz.preguntar("¿Quieres volver al pueblo y visitar a tus vecinos?", ["Volver al pueblo", "Seguir en la granja"], func(_i: int) -> void: pass)
					"pausa": Interfaz._pausa.abrir()
					"mapa": Interfaz.alternar_mapa()
				await get_tree().create_timer(0.4).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(carpeta + ("texto_muy_grande_" if grande else "texto_normal_") + pantalla + ".png")
		Ajustes.restaurar()
	get_tree().quit()

