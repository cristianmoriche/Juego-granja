class_name BajadaMina
extends Node3D
## Escalera del fondo de la mina interior (L4b): «E · Bajar al nivel 2» y, ya abajo, «E · Subir al nivel 1».
## Va dentro del nodo `Objetos` de `mina_interior` y se coloca en el marcador `Bajada_Nivel_2` al llegar
## `Escenas.mapa_cargado("mina_interior")`. Cambiar de nivel pone `Juego.banderas["nivel_mina"]` y recarga el mapa:
## se llega a `Llegada_Interior`. Lo que cambia con el nivel (rocas, ambiente más oscuro y azulado) se aplica solo,
## leyendo la bandera, al cargar el mapa (`RocasMina` pone las rocas; aquí, el ambiente).

const ID_MAPA := "mina_interior"
const MARCADOR := "Bajada_Nivel_2"
const LLEGADA := "Llegada_Interior"

var punto: Interactuable = null
var nivel: int = 1


func _ready() -> void:
	punto = Interactuable.new()
	punto.name = "Escalera"
	punto.radio = 1.3
	punto.altura_marca = 1.8
	punto.mostrar_descripcion = false
	punto.activo = false
	punto.usado.connect(func(_j: Node3D) -> void: preguntar())
	add_child(punto)
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	var mapa := _mapa()
	if mapa == null or id != ID_MAPA or str(mapa.get("id_mapa")) != ID_MAPA:
		return
	colocar(mapa)


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


## Coloca la escalera según el nivel en que se está y aplica el ambiente del nivel.
func colocar(mapa: Node) -> void:
	nivel = clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, NivelMina.MAX_NIVEL)
	var m := mapa.call("marcador", MARCADOR) as Marker3D
	if m == null:
		punto.activo = false
		return
	punto.global_position = m.global_position
	if nivel == 1:
		punto.verbo = "Bajar"
		punto.nombre_objeto = "al nivel 2"
	elif nivel == 2:
		punto.verbo = "Subir"
		punto.nombre_objeto = "al nivel 1"
	elif nivel < NivelMina.MAX_NIVEL:
		punto.verbo = "Bajar"
		punto.nombre_objeto = "al nivel %d" % (nivel + 1)
	else:
		punto.verbo = "Subir"
		punto.nombre_objeto = "al nivel %d" % (nivel - 1)
	punto.activo = true
	if nivel == 2:
		oscurecer(mapa)


func preguntar() -> void:
	if nivel == 1:
		Interfaz.preguntar("Una escalera de madera baja por el pozo. Abajo se oye gotear el agua. ¿Bajar al nivel 2?", ["Bajar al nivel 2", "Todavía no"], func(i: int) -> void:
			if i == 0:
				cambiar_de_nivel(2))
	elif nivel == 2:
		Interfaz.preguntar("La escalera vuelve a subir al nivel 1. ¿Subir?", ["Subir al nivel 1", "Quedarme"], func(i: int) -> void:
			if i == 0:
				cambiar_de_nivel(1))
	elif nivel < NivelMina.MAX_NIVEL:
		var sig := nivel + 1
		Interfaz.preguntar("Una escalera desciende al nivel %d (%s). ¿Bajar?" % [sig, str(NivelMina.datos_ambientacion(sig)["nombre"])], ["Bajar al nivel %d" % sig, "Todavía no"], func(i: int) -> void:
			if i == 0:
				cambiar_de_nivel(sig))
	else:
		Interfaz.preguntar("Has llegado al fondo conocido de la mina (nivel %d). ¿Subir al nivel %d?" % [nivel, nivel - 1], ["Subir al nivel %d" % (nivel - 1), "Quedarme"], func(i: int) -> void:
			if i == 0:
				cambiar_de_nivel(nivel - 1))


## Cambia de nivel y recarga la mina interior (fundido incluido).
func cambiar_de_nivel(nuevo: int) -> void:
	var n := clampi(nuevo, 1, NivelMina.MAX_NIVEL)
	Juego.banderas["nivel_mina"] = n
	Misiones.registrar_nivel_mina(n)
	if n > 1:
		Interfaz.mensaje("Nivel %d · %s." % [n, str(NivelMina.datos_ambientacion(n)["nombre"])])
	else:
		Interfaz.mensaje("Subes al nivel 1 de la mina.")
	Escenas.ir_a_mapa(ID_MAPA, LLEGADA)


## Nivel 2: la cueva se ve más oscura y azulada (cambia el ambiente y la niebla del mapa, no su geometría).
func oscurecer(mapa: Node) -> void:
	var we := mapa.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.background_color = Color(0.004, 0.008, 0.022)
	env.ambient_light_color = Color(0.16, 0.26, 0.60)
	env.ambient_light_energy = minf(env.ambient_light_energy, 0.30) * 0.65
	env.fog_light_color = Color(0.012, 0.024, 0.068)
	env.fog_density = env.fog_density * 1.35
	# Una luz azul muy tenue y sin sombras tiñe toda la cueva; el farol de Leo se vuelve más frío y contenido.
	var luz := DirectionalLight3D.new()
	luz.name = "LuzAzulNivel2"
	luz.light_color = Color(0.32, 0.48, 1.0)
	luz.light_energy = 0.28
	luz.shadow_enabled = false
	luz.rotation_degrees = Vector3(-80.0, 20.0, 0.0)
	mapa.add_child(luz)
	var jugador := Escenas.jugador()
	var farol: OmniLight3D = jugador.get_node_or_null("Farol") as OmniLight3D if jugador != null else null
	if farol != null:
		farol.light_color = Color(0.80, 0.89, 1.0)
		farol.light_energy *= 0.85
		if jugador.has_method("fijar_energia_base_farol"):
			jugador.call("fijar_energia_base_farol", farol.light_energy)
