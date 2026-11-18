extends Node3D
## Captura de los vecinos con modelo propio (2026-11-16) a la escala del juego, con la luz del sol, mirando a cámara.
## El primero es Bernardo sin corregir (como venía) y el resto pasan por `Npc._quitar_metal`, igual que en el juego.
## Guarda ../gestion/capturas/vecinos_nuevos.png y se cierra.

const IDS := ["bernardo_original", "bernardo", "mateo", "clara", "ramon", "anselmo", "tomas", "eusebio", "gema"]


func _ready() -> void:
	var entorno := WorldEnvironment.new()
	entorno.environment = Environment.new()
	entorno.environment.background_mode = Environment.BG_SKY
	entorno.environment.sky = Sky.new()
	entorno.environment.sky.sky_material = ProceduralSkyMaterial.new()
	entorno.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(entorno)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, 25, 0)
	sol.light_energy = 1.2
	add_child(sol)
	var corrector := Npc.new()
	var x := -float(IDS.size() - 1) * 0.5
	for id: String in IDS:
		var modelo := id.trim_suffix("_original")
		var inst := (load("res://assets/personajes/aldeanos/%s.glb" % modelo) as PackedScene).instantiate() as Node3D
		inst.scale = Vector3.ONE * EscalaPersonaje.ESCALA
		inst.position = Vector3(x, 0, 0)
		add_child(inst)
		if not id.ends_with("_original"):
			corrector._quitar_metal(inst)
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			if ap.has_animation("Idle"):
				ap.play("Idle")
				ap.seek(0.5, true)
		x += 1.0
	corrector.free()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.95, 6.5)
	cam.fov = 50
	add_child(cam)
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://../gestion/capturas")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + "/vecinos_nuevos.png")
	print("CAPTURA GUARDADA")
	get_tree().quit()
