extends Node
## Comprueba los cambios de calidad y tiempo sobre mapas de juego reales.

var _total := 0
var _fallos := 0


func _ready() -> void:
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	Juego.pausar_tiempo(true)
	Juego.estacion = 0
	_fijar_tiempo(840, "sol")
	_comprobar(int(Ajustes.DEFECTO.calidad) == 2, "Alto es el ajuste predeterminado")
	_comprobar_cielos()
	await _comprobar_mapa("costa_lago", false)
	await _comprobar_mapa("bosque_norte", false)
	await _comprobar_mapa("casa_leo", true)
	await _comprobar_mapa("mina_interior", true)
	print("H03 entorno: %d/%d comprobaciones pasadas" % [_total - _fallos, _total])
	get_tree().quit(0 if _fallos == 0 else 1)


func _comprobar_cielos() -> void:
	for registro: Array in CieloH03.HDRI:
		_comprobar(ResourceLoader.exists(CieloH03.ruta(registro[0]), "Texture2D"), "HDRI disponible: " + registro[0])
	for clima: String in [CieloH03.CUBIERTO, CieloH03.NEBLINA]:
		_comprobar(ResourceLoader.exists(CieloH03.ruta(clima), "Texture2D"), "HDRI de clima disponible: " + clima)
	var sale := float(CicloDia.AMANECER[0])
	var ocaso := float(CicloDia.ATARDECER[0])
	var madrugada := CieloH03.tramo(120.0, sale, ocaso)
	var tarde := CieloH03.tramo(840.0, sale, ocaso)
	_comprobar(madrugada.x == 0.0 and madrugada.z == 0.0, "La madrugada conserva el HDRI nocturno")
	_comprobar(tarde.x > 0.0 and tarde.x < tarde.y and tarde.z > 0.0 and tarde.z < 1.0, "La tarde interpola dos fotografías diurnas")


func _comprobar_mapa(id: String, interior: bool) -> void:
	_fijar_tiempo(840, "sol")
	var escena := load("res://escenas/mapas/%s.tscn" % id) as PackedScene
	var mapa := escena.instantiate() as Mapa
	add_child(mapa)
	if not mapa.esta_listo:
		await mapa.listo
	var mundo := mapa.get_node("WorldEnvironment") as WorldEnvironment
	var entorno := mundo.environment
	_comprobar(entorno.tonemap_mode == Environment.TONE_MAPPER_AGX, id + " conserva AgX")
	for nivel in 4:
		Ajustes.valores.calidad = nivel
		Ajustes.aplicar_graficos()
		_comprobar(entorno.ssao_enabled == (nivel >= 1), "%s calidad %d: oclusión" % [id, nivel])
		_comprobar(entorno.ssil_enabled == (nivel >= 3), "%s calidad %d: iluminación indirecta" % [id, nivel])
		_comprobar(entorno.ssr_enabled == (nivel >= 3), "%s calidad %d: reflejos" % [id, nivel])
		_comprobar(entorno.volumetric_fog_enabled == (nivel >= 2), "%s calidad %d: niebla volumétrica" % [id, nivel])
		if nivel == 3:
			_comprobar(entorno.sdfgi_enabled, id + " tiene rebote SDFGI en Ultra")
		if nivel <= 1:
			_comprobar(not entorno.sdfgi_enabled, id + " desactiva SDFGI en Bajo y Medio")
		_comprobar(mundo.camera_attributes is CameraAttributesPhysical, id + " tiene exposición física")
		_comprobar(mundo.camera_attributes.auto_exposure_enabled == (nivel >= 2), "%s calidad %d: autoexposición" % [id, nivel])
	Ajustes.valores.calidad = 2
	Ajustes.aplicar_graficos()
	if not interior:
		_comprobar_exterior(mapa, entorno)
	else:
		var sol := mapa.get_node("Sol") as DirectionalLight3D
		_comprobar(not sol.visible and sol.light_energy == 0.0, id + " no recibe sol directo a través del techo")
	mapa.queue_free()
	await get_tree().process_frame


func _comprobar_exterior(mapa: Mapa, entorno: Environment) -> void:
	var id := mapa.id_mapa
	var material := entorno.sky.sky_material as ShaderMaterial
	_comprobar(material != null and material.shader.resource_path == "res://shaders/cielo_h03.gdshader", id + " usa el cielo HDRI")
	var tiempo_seco := entorno.volumetric_fog_density
	_fijar_tiempo(840, "niebla")
	_comprobar(entorno.volumetric_fog_density > tiempo_seco, id + " refuerza la niebla con el clima")
	_fijar_tiempo(840, "tormenta")
	_comprobar(mapa.get_node_or_null("Lluvia") is GPUParticles3D, id + " emite lluvia en tormenta")
	_comprobar(mapa.get_node_or_null("Lluvia/Salpicaduras") is GPUParticles3D, id + " prepara salpicaduras junto al suelo")
	if id == "costa_lago":
		var rayo := mapa.get_node_or_null("Relampago") as DirectionalLight3D
		_comprobar(rayo != null, "La tormenta crea una luz direccional")
		if rayo != null:
			mapa._espera_relampago = 0.0
			mapa._actualizar_relampago(0.016)
			_comprobar(rayo.light_energy > 0.5, "El relámpago ilumina el mapa")
	_fijar_tiempo(840, "sol")
	_comprobar(mapa.get_node_or_null("Lluvia") == null, id + " quita la lluvia al despejar")
	var agua := mapa.cargador._material_para(_material_referencia_agua()) as ShaderMaterial
	_comprobar(agua != null and agua.shader.resource_path == "res://shaders/agua_h03.gdshader", id + " usa agua con profundidad")
	if agua != null:
		_comprobar(agua.get_shader_parameter("es_rio") == (id == "bosque_norte"), id + " selecciona la corriente del río o el lago")
	if id == "bosque_norte":
		var refuerzo := false
		for planta in mapa.cargador.nodo_instancias.get_children():
			if planta is MultiMeshInstance3D and String(planta.name).begins_with("mm_grass_"):
				var malla := planta.multimesh as MultiMesh
				if malla.use_custom_data and malla.instance_count >= 4:
					var material_hierba := malla.mesh.surface_get_material(0) as ShaderMaterial
					refuerzo = material_hierba != null and material_hierba.get_shader_parameter("es_hierba") == true
					if refuerzo and DisplayServer.get_name() != "headless":
						refuerzo = malla.get_instance_custom_data(malla.instance_count - 1).r > 0.5
					if refuerzo:
						break
		_comprobar(refuerzo, "El bosque tiene hierba con viento y densidad adicional de cerca")


func _material_referencia_agua() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "Agua"
	return material


func _fijar_tiempo(minuto: int, clima: String) -> void:
	Juego.minutos = minuto
	Juego.clima = clima
	Juego.hora_cambiada.emit(minuto)
	Juego.clima_cambiado.emit(clima)


func _comprobar(condicion: bool, texto: String) -> void:
	_total += 1
	if not condicion:
		_fallos += 1
		push_error("H03: " + texto)
