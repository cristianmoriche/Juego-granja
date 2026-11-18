class_name ZonaPesca
extends Node3D
## Puntos de pesca en Bosque del Norte (río) y Costa del Lago (muelle), además de los topes invisibles del cauce.

const ENERGIA_PESCA := 4.0
const RADIO_RIO := 6.5
const RADIO_MUELLE := 5.5

@export var marcador_pesca: String = "Pesca_Muelle"
@export var radio_uso: float = 5.5

var _punto_pesca: Vector3 = Vector3.ZERO
var _cana_pickup: Interactuable = null


func _ready() -> void:
	add_to_group("usable")
	add_to_group("zona_pesca")
	var m := _mapa()
	if m == null:
		return
	await m.listo
	var mk := m.marcador(marcador_pesca)
	if mk != null:
		_punto_pesca = mk.global_position
		global_position = _punto_pesca
	if m.id_mapa == "bosque_norte":
		_crear_topes_rio(m)
	elif m.id_mapa == "costa_lago":
		_crear_cana_muelle(m)


func _mapa() -> Mapa:
	var n := get_parent()
	while n != null:
		if n is Mapa:
			return n as Mapa
		n = n.get_parent()
	return null


func usar(id: String, punto: Vector3, _jugador: Node3D) -> bool:
	if id != "cana":
		return false
	var d := Vector2(punto.x - _punto_pesca.x, punto.z - _punto_pesca.z).length()
	if d > radio_uso:
		return false
	if not Juego.gastar_energia(ENERGIA_PESCA * Juego.factor_energia_habilidad("pesca")):
		Interfaz.mensaje("No te quedan fuerzas para seguir pescando hoy.")
		return true
	Juego.banderas["pesca_habilitada"] = true
	var m := _mapa()
	var id_m := m.id_mapa if m != null else ""
	var tabla := ["trucha", "trucha", "carpa", "perca"]
	if id_m == "costa_lago":
		tabla = ["perca", "carpa", "perca", "trucha"]
	elif id_m == "robledal_niebla":
		tabla = ["trucha", "carpa", "trucha", "carpa"]
	elif id_m == "ruinas_valle":
		tabla = ["carpa", "trucha", "perca", "carpa"]
	var pez: String = tabla[randi() % tabla.size()]
	Juego.anadir_objeto(pez, 1)
	TareasDiarias.registrar_progreso("pescar", 1)
	Juego.ganar_xp_habilidad("pesca", 24 if pez == "perca" else 18)
	if randf() < Juego.bono_suerte_pesca() and Juego.espacio_para(pez) > 0:
		Juego.anadir_objeto(pez, 1)
	var nom := str(Datos.objeto(pez).get("nombre", pez))
	Interfaz.mensaje("¡Buena picada! Has pescado %s." % nom, pez)
	return true


func _crear_cana_muelle(m: Mapa) -> void:
	if bool(Juego.banderas.get("cana_muelle", false)) or Juego.cantidad("cana") > 0:
		return
	var mk := m.marcador("Cana_Muelle")
	if mk == null:
		return
	var c := Interactuable.new()
	c.name = "CanaMuelle"
	c.verbo = "Recoger"
	c.nombre_objeto = "la caña vieja"
	c.radio = 1.4
	c.altura_marca = 1.6
	add_child(c)
	c.global_position = mk.global_position

	# Instanciar el modelo real de la caña apoyado junto a la caja de cebo
	var escena_cana := load("res://assets/herramientas/cana.glb") as PackedScene
	if escena_cana != null:
		var mod := escena_cana.instantiate() as Node3D
		mod.position = Vector3(0.0, 0.08, 0.0)
		mod.rotation_degrees = Vector3(14.0, 28.0, -18.0)
		mod.scale = Vector3.ONE * 1.15
		c.add_child(mod)
	else:
		var palo := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.028
		cm.height = 1.65
		palo.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.50, 0.34, 0.18)
		mat.roughness = 0.7
		palo.material_override = mat
		palo.position = Vector3(0.0, 0.78, 0.0)
		palo.rotation_degrees = Vector3(12.0, 0.0, -18.0)
		c.add_child(palo)

	c.usado.connect(func(_j: Node3D) -> void:
		if bool(Juego.banderas.get("cana_muelle", false)):
			return
		Juego.banderas["cana_muelle"] = true
		Juego.banderas["pesca_habilitada"] = true
		Juego.anadir_objeto("cana", 1)
		Interfaz.mensaje("Recoges la caña del abuelo. Úsala en el extremo del muelle o junto al puente.", "cana")
		c.queue_free()
	)
	_cana_pickup = c


func _crear_topes_rio(m: Mapa) -> void:
	var body := StaticBody3D.new()
	body.name = "TopesRio"
	body.collision_layer = 1
	body.collision_mask = 0
	m.add_child(body)
	var forma := BoxShape3D.new()
	forma.size = Vector3(4.4, 3.0, 5.2)
	for tramos in [[-44.0, -3.2], [3.2, 44.0]]:
		var x: float = tramos[0]
		while x <= tramos[1]:
			var z_rio := -2.0 + 7.5 * sin(x * 0.055 + 0.4) + 3.0 * cos(x * 0.11)
			var cs := CollisionShape3D.new()
			cs.shape = forma
			cs.position = Vector3(x, 0.3, z_rio)
			body.add_child(cs)
			x += 4.0
