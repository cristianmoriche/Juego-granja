extends Node
## Capturas de E1 (gestion/capturas/E1/): una por zona de la mina con sus enemigos y una con los cuatro jefes.
## La caverna real es demasiado estrecha para una cámara libre (techo y paredes), así que cada zona se monta en un
## pequeño escenario con su ambientación (niebla, ambiente, color de suelo y antorchas de NivelMina) y los enemigos
## con su textura, brillo y animación reales. Ventana pequeña (--position 40,40 --resolution 960x540); se cierra sola.

const RUTA_CAP := "res://../gestion/capturas/E1"
const ZONAS := [
	{"id": "piedra", "nivel": 3, "lo": 1, "hi": 5},
	{"id": "humeda", "nivel": 8, "lo": 6, "hi": 10},
	{"id": "cristal", "nivel": 13, "lo": 11, "hi": 15},
	{"id": "magma", "nivel": 18, "lo": 16, "hi": 20},
]
const JEFES := ["rata_reina", "sapo_gigante", "arana_madre", "gusano_magma"]

var _escena: Node3D = null


func _ready() -> void:
	# El juego se pausa al perder el foco (T03): en una captura lanzada en segundo plano hay que ignorarlo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tope := Timer.new()
	tope.wait_time = 60.0
	tope.one_shot = true
	tope.timeout.connect(func() -> void:
		push_error("capturas_e1: tiempo máximo de 60 s superado")
		get_tree().quit(1))
	add_child(tope)
	tope.start()
	_ejecutar.call_deferred()


func _process(_d: float) -> void:
	Juego._sin_foco = false
	Juego._minimizada = false
	if get_tree().paused:
		get_tree().paused = false


func _esperar(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _def(id: String) -> Dictionary:
	for d: Dictionary in Enemigo.cargar_definiciones():
		if str(d.get("id", "")) == id:
			return d
	return {}


## Escenario de una zona: suelo, ambiente y niebla de NivelMina, una luz tenue y dos antorchas.
func _montar(nivel: int, dist: float, alto_cam: float) -> void:
	if _escena != null:
		_escena.queue_free()
	_escena = Node3D.new()
	add_child(_escena)
	var amb := NivelMina.datos_ambientacion(nivel)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = amb["niebla"] as Color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = amb["ambiente"] as Color
	env.ambient_light_energy = float(amb["energia_amb"])
	env.fog_enabled = true
	env.fog_light_color = amb["niebla"] as Color
	env.fog_density = float(amb["densidad"])
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_escena.add_child(we)
	var suelo := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	suelo.mesh = pm
	var ms := StandardMaterial3D.new()
	ms.albedo_color = amb["suelo"] as Color
	ms.roughness = float(amb["rugosidad"])
	suelo.material_override = ms
	_escena.add_child(suelo)
	var dl := DirectionalLight3D.new()
	dl.light_color = amb["luz_dir"] as Color
	dl.light_energy = 0.35
	dl.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	_escena.add_child(dl)
	for x: float in [-dist * 0.55, dist * 0.55]:
		var antorcha := OmniLight3D.new()
		antorcha.light_color = Color(1.0, 0.62, 0.32)
		antorcha.light_energy = 1.5
		antorcha.omni_range = dist * 1.1
		antorcha.position = Vector3(x, 2.6, 0.5)
		_escena.add_child(antorcha)
	var linterna := OmniLight3D.new()   # el farol de Leo, para ver las texturas
	linterna.light_color = Color(1.0, 0.9, 0.75)
	linterna.light_energy = 0.9
	linterna.omni_range = dist * 2.0
	linterna.position = Vector3(0.0, alto_cam + 1.0, dist - 1.0)
	_escena.add_child(linterna)
	var cam := Camera3D.new()
	cam.fov = 50.0
	_escena.add_child(cam)
	cam.position = Vector3(0.0, alto_cam, dist)
	cam.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
	cam.current = true


func _poner(lista: Array[Enemigo], separacion: float) -> void:
	for k in lista.size():
		var en := lista[k]
		_escena.add_child(en)
		en.activar_para_prueba(false)
		en.position = Vector3((float(k) - float(lista.size() - 1) * 0.5) * separacion, 0.0, 0.0)
		en.reproducir("andar" if k % 2 == 0 else "reposo", 0.0)


func _foto(ruta: String) -> void:
	await _esperar(20)
	var img := get_viewport().get_texture().get_image()
	print("CAPTURA ", ruta, " -> ", img.save_png(ProjectSettings.globalize_path(ruta)))


func _ejecutar() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUTA_CAP))
	var num := 1
	for z: Dictionary in ZONAS:
		var lista: Array[Enemigo] = []
		for d: Dictionary in Enemigo.cargar_definiciones():
			var nv: Array = d["niveles"]
			if not bool(d.get("jefe", false)) and int(nv[0]) <= int(z["hi"]) and int(nv[1]) >= int(z["lo"]):
				var en := Enemigo.new()
				en.configurar(d)
				lista.append(en)
		_montar(int(z["nivel"]), 5.8, 1.6)
		_poner(lista, 1.75)
		await _foto("%s/%02d_%s_nivel_%d.png" % [RUTA_CAP, num, str(z["id"]), int(z["nivel"])])
		num += 1
	var jefes: Array[Enemigo] = []
	for id: String in JEFES:
		var en := Enemigo.new()
		en.configurar(_def(id))
		jefes.append(en)
	_montar(20, 11.5, 3.0)
	_poner(jefes, 4.6)
	for en in jefes:
		if en.especial == "emerger":
			en.estado = Enemigo.Estado.LIBRE
			en.pivote.position.y = 0.0
	await _foto("%s/%02d_jefes.png" % [RUTA_CAP, num])
	print("CAPTURAS_E1 OK")
	get_tree().quit(0)
