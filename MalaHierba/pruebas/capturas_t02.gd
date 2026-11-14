extends Node3D
## Inspección reproducible de los siete modelos en el renderizador real del juego.
## -- antes / despues; conserva frente, perfil y espalda en reposo y durante el paso.

const MODELOS := ["leo", "herrero", "tendera", "tabernero", "alcalde", "minero", "nino"]
var camara: Camera3D

func _ready() -> void:
	_ejecutar.call_deferred()

func _ejecutar() -> void:
	Interfaz.mostrar_hud(false)
	Juego.pausar_tiempo(true)
	var fase := "antes" if "antes" in OS.get_cmdline_user_args() else "despues"
	var barrido := "barrido" in OS.get_cmdline_user_args()
	var variantes := "variantes" in OS.get_cmdline_user_args()
	var salida := ProjectSettings.globalize_path("res://../gestion/noche-codex/capturas/T02-personajes/" + fase + "/")
	if barrido:
		salida += "barrido/"
	if variantes:
		salida += "vecinos/"
	DirAccess.make_dir_recursive_absolute(salida)
	var entorno := WorldEnvironment.new()
	entorno.environment = Environment.new()
	entorno.environment.background_mode = Environment.BG_COLOR
	entorno.environment.background_color = Color("465763")
	entorno.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	entorno.environment.ambient_light_color = Color.WHITE
	entorno.environment.ambient_light_energy = 0.65
	add_child(entorno)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-35, -35, 0)
	luz.light_energy = 1.2
	add_child(luz)
	var relleno := DirectionalLight3D.new()
	relleno.rotation_degrees = Vector3(-20, 145, 0)
	relleno.light_energy = 0.7
	add_child(relleno)
	camara = Camera3D.new()
	camara.projection = Camera3D.PROJECTION_ORTHOGONAL
	camara.size = 2.35
	add_child(camara)
	camara.current = true
	var rotulo := Label.new()
	rotulo.position = Vector2(20, 20)
	rotulo.add_theme_font_size_override("font_size", 24)
	add_child(rotulo)
	var lista: Array = MODELOS.duplicate()
	var fichas: Dictionary = {}
	if variantes:
		lista.clear()
		for d: Dictionary in Vecinos.datos_de_todos():
			lista.append(d["id"])
			fichas[d["id"]] = d
	for id: String in lista:
		var ruta := "res://assets/personajes/leo/leo.glb" if id == "leo" else "res://assets/personajes/aldeanos/%s.glb" % id
		var modelo: Node3D
		if variantes:
			var npc := Npc.crear(fichas[id])
			add_child(npc)
			npc.set_physics_process(false)
			npc._modelo.rotation = Vector3.ZERO
			npc._punto.visible = false
			if fase == "antes":
				for hijo in npc._modelo.get_children():
					npc._modelo.remove_child(hijo)
					hijo.queue_free()
				var documento := GLTFDocument.new()
				var datos_gltf := GLTFState.new()
				var original := ProjectSettings.globalize_path("res://../gestion/noche-codex/copias/T02-personajes/personajes/aldeanos/%s.glb" % fichas[id]["modelo"])
				assert(documento.append_from_file(original, datos_gltf) == OK)
				var inst := documento.generate_scene(datos_gltf)
				var escala := float(fichas[id].get("escala", 1.0)) * EscalaPersonaje.ESCALA
				inst.scale = Vector3.ONE * escala
				npc._modelo.add_child(inst)
				npc._teñir(inst, fichas[id].get("tinte", {}))
				var sombrero := str(fichas[id].get("sombrero", ""))
				if not sombrero.is_empty():
					npc._poner_sombrero(inst, sombrero, escala)
			modelo = npc
		else:
			if fase == "antes":
				# Cargar la copia evita sustituir los modelos del proyecto para repetir el diagnóstico.
				var documento := GLTFDocument.new()
				var datos_gltf := GLTFState.new()
				var original := ruta.replace("res://assets/personajes/", "res://../gestion/noche-codex/copias/T02-personajes/personajes/")
				assert(documento.append_from_file(ProjectSettings.globalize_path(original), datos_gltf) == OK)
				modelo = documento.generate_scene(datos_gltf)
			else:
				modelo = (load(ruta) as PackedScene).instantiate() as Node3D
			add_child(modelo)
		var anim := modelo.find_child("*", true, false)
		var reproductores := modelo.find_children("*", "AnimationPlayer", true, false)
		if not reproductores.is_empty():
			anim = reproductores[0]
		var estados: Array = ["reposo", "andar"]
		if barrido:
			estados = ["reposo", "andar_0", "andar_1", "andar_2", "andar_3"]
		for estado: String in estados:
			if anim is AnimationPlayer:
				var nombre := "andar" if estado.begins_with("andar") else estado
				anim.play(nombre)
				var tiempo := 0.30 if estado == "andar" else 0.0
				if estado.begins_with("andar_"):
					tiempo = anim.get_animation("andar").length * (float(estado.get_slice("_", 1)) + 0.5) / 4.0
				anim.seek(tiempo, true)
				anim.pause()
			var vistas: Array = ["frente", "perfil", "espalda"]
			if barrido:
				vistas = ["00", "01", "02", "03", "04", "05", "06", "07"]
			for vista: String in vistas:
				var angulo: float = float(vista) * TAU / 8.0 if barrido else {"frente": 0.0, "perfil": PI / 2.0, "espalda": PI}[vista]
				camara.position = Vector3(sin(angulo) * 4.0, 1.05, cos(angulo) * 4.0)
				camara.look_at(Vector3(0, 1.05, 0))
				rotulo.text = "%s · %s · %s · %s" % [id, fase, estado, vista]
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var imagen := get_viewport().get_texture().get_image()
				imagen.save_png(salida + "%s_%s_%s.png" % [id, estado, vista])
		modelo.queue_free()
		await get_tree().process_frame
	print("CAPTURAS T02 OK: ", fase)
	get_tree().quit()
