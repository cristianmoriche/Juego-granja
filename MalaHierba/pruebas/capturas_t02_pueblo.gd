extends Node
## Comprobación visual de las instancias reales en el pueblo y en la entrada de la mina.
const SALIDA := "res://../gestion/noche-codex/capturas/T02-personajes/despues/partida/"

func _ready() -> void:
	_ejecutar.call_deferred()

func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = ProjectSettings.globalize_path("res://../gestion/noche-codex/temporales/T02-personajes/capturas_partida.json")
	Juego.nueva_partida("Leo")
	Juego.minutos = 450
	Juego.pausar_tiempo(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	for id_mapa: String in ["pueblo", "mina_exterior"]:
		print("T02: cargando ", id_mapa)
		await Escenas.ir_a_mapa(id_mapa, "Spawn_Protagonista")
		print("T02: mapa listo ", id_mapa)
		await get_tree().create_timer(1.0).timeout
		Interfaz.mostrar_hud(false)
		var jugador := Escenas.jugador() as Jugador
		jugador.set_physics_process(false)
		var camara := Camera3D.new()
		add_child(camara)
		camara.current = true
		camara.fov = 40
		var personajes: Array[Node3D] = [jugador]
		for n in get_tree().get_nodes_in_group("npc"):
			if n is Npc:
				n.set_physics_process(false)
				personajes.append(n)
		for p: Node3D in personajes:
			var modelo := p.get_node("Modelo") as Node3D
			# Una pared puede tapar la cámara de inspección junto al puesto de un vecino.
			# Se fotografía cada instancia en el punto despejado de Leo y luego se devuelve.
			var posicion_original := p.global_position
			var giro_original := modelo.global_rotation
			var jugador_visible := jugador.visible
			if p != jugador:
				p.global_position = jugador.global_position
				modelo.global_rotation = (jugador.get_node("Modelo") as Node3D).global_rotation
				jugador.visible = false
			var frente := modelo.global_basis.z.normalized()
			var centro := p.global_position + Vector3.UP * 0.9
			camara.global_position = centro + frente * 3.2 + Vector3.UP * .35
			camara.look_at(centro)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var nombre := "leo" if p == jugador else str(p.get("id"))
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SALIDA + id_mapa + "_" + nombre + ".png"))
			p.global_position = posicion_original
			modelo.global_rotation = giro_original
			jugador.visible = jugador_visible
		# Movimiento real de Leo con la entrada del juego, conservando el modelo de los vecinos en su mapa.
		camara.queue_free()
		jugador.set_physics_process(true)
		Input.action_press("mover_arriba")
		await get_tree().create_timer(.4).timeout
		Input.action_release("mover_arriba")
	print("CAPTURAS T02 PARTIDA OK")
	get_tree().quit()
