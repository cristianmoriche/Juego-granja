extends "res://pruebas/prueba_m2.gd"
## Repite la regresión de la llegada en ambos niveles con la física y las rocas reales.
func _ejecutar() -> void:
	get_tree().current_scene = null
	Juego.nueva_partida("Prueba de mina")
	Juego.pausar_tiempo(true)
	for nivel in [1, 2]:
		Juego.banderas["nivel_mina"] = nivel
		await _ir("mina_interior")
		await _prueba_salto_en_cueva()
		_comprobar(_j.atascos_resueltos == 0, "nivel %d: cero rescates" % nivel)
		if DisplayServer.get_name() != "headless":
			var llegada := (_mapa.call("marcador", "Llegada_Interior") as Marker3D).global_position
			_poner_a_leo(llegada + Vector3(0, 0.05, 0), _mapa.giro_camara())
			await _fisica(30)
			await RenderingServer.frame_post_draw
			var ruta := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T03-foco-y-errores/mina_nivel_%d.png" % nivel)
			DirAccess.make_dir_recursive_absolute(ruta.get_base_dir())
			_comprobar(get_viewport().get_texture().get_image().save_png(ruta) == OK, "captura de la llegada al nivel %d" % nivel)
	print("PRUEBA OK (%d comprobaciones)" % _total if _fallos.is_empty() else "PRUEBA FALLO: " + "; ".join(_fallos))
	get_tree().quit(0 if _fallos.is_empty() else 1)
