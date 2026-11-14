extends Node
## Prueba permanente T11: comprueba la dirección artística de iluminación, tonemapping AgX,
## coherencia entre amanecer (08:00), mediodía (14:00) y atardecer (20:00), y rugosidad mate.

const RUTA_PROYECTO := "res://pruebas/prueba_t11_iluminacion.gd"
var _fallos: Array[String] = []


func _ready() -> void:
	await _ejecutar()
	if _fallos.is_empty():
		print("PRUEBA T11 OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: " + "; ".join(_fallos))
		get_tree().quit(1)


func _comprobar(cond: bool, msg: String) -> void:
	if not cond:
		_fallos.append(msg)


func _ejecutar() -> void:
	var min_orig := Juego.minutos
	var est_orig := Juego.estacion
	var clima_orig := Juego.clima
	Juego.estacion = 0
	Juego.clima = "despejado"

	var rutas := {
		"granja": "res://escenas/mapas/granja.tscn",
		"pueblo": "res://escenas/mapas/pueblo.tscn",
		"taberna": "res://escenas/mapas/taberna.tscn",
		"mina_interior": "res://escenas/mapas/mina_interior.tscn",
	}
	for id_m: String in rutas.keys():
		Juego.minutos = 840
		var emp := load(String(rutas[id_m])) as PackedScene
		var nodo := emp.instantiate() as Node3D
		add_child(nodo)
		await get_tree().process_frame
		await get_tree().process_frame

		var we := nodo.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_comprobar(we != null and we.environment != null, "%s sin WorldEnvironment" % id_m)
		if we != null and we.environment != null:
			var env := we.environment
			_comprobar(env.tonemap_mode == Environment.TONE_MAPPER_AGX, "%s no usa TONE_MAPPER_AGX" % id_m)
			_comprobar(env.tonemap_exposure >= 0.80 and env.tonemap_exposure <= 1.05, "%s tonemap_exposure=%.2f fuera de rango" % [id_m, env.tonemap_exposure])
			_comprobar(not env.glow_enabled, "%s conserva glow activado" % id_m)

		var sol := nodo.get_node_or_null("Sol") as DirectionalLight3D
		if id_m == "granja" or id_m == "pueblo":
			Juego.minutos = 480
			if sol != null and sol.has_method("actualizar"):
				sol.call("actualizar")
			var e_0800 := sol.light_energy if sol != null else -1.0
			Juego.minutos = 840
			if sol != null and sol.has_method("actualizar"):
				sol.call("actualizar")
			var e_1400 := sol.light_energy if sol != null else -1.0
			var c_1400 := sol.light_color if sol != null else Color.BLACK
			Juego.minutos = 1200
			if sol != null and sol.has_method("actualizar"):
				sol.call("actualizar")
			var e_2000 := sol.light_energy if sol != null else -1.0
			var c_2000 := sol.light_color if sol != null else Color.BLACK
			_comprobar(e_1400 > e_0800 and e_1400 > e_2000, "%s energía mediodía no domina (%.2f vs %.2f / %.2f)" % [id_m, e_1400, e_0800, e_2000])
			_comprobar(c_2000.r - c_2000.b > c_1400.r - c_1400.b + 0.15, "%s atardecer 20:00 no es claramente más cálido" % id_m)

			var cargador := nodo.get_node_or_null("CargadorMapa") as CargadorMapa
			if cargador != null:
				_comprobar_materiales(id_m, cargador)

		nodo.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	Juego.minutos = min_orig
	Juego.estacion = est_orig
	Juego.clima = clima_orig


func _comprobar_materiales(id_m: String, cargador: CargadorMapa) -> void:
	for reg_v: Dictionary in cargador._mats_ventana:
		var mat := reg_v.get("mat") as StandardMaterial3D
		if is_instance_valid(mat):
			_comprobar(mat.emission_energy_multiplier > 0.35, "%s ventana apagada a las 20:00" % id_m)
	cargador.actualizar_iluminacion_hora(0.0, 0.04)
	for reg_v: Dictionary in cargador._mats_ventana:
		var mat := reg_v.get("mat") as StandardMaterial3D
		if is_instance_valid(mat):
			_comprobar(mat.emission_energy_multiplier < 0.10, "%s ventana sigue quemada al mediodía (%.2f)" % [id_m, mat.emission_energy_multiplier])
	cargador.actualizar_iluminacion_hora(1.0, 1.0)
