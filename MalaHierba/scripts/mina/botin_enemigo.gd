extends Interactuable
## Mineral abandonado por la criatura. Se mantiene en el suelo si no cabe.

var id_mineral: String
var unidades: int


func configurar(id: String, cantidad: int) -> void:
	id_mineral = id
	unidades = cantidad
	nombre_objeto = Datos.nombre_objeto(id).to_lower()
	verbo = "Recoger"
	radio = 0.42
	altura_marca = 0.44
	add_to_group("botin_enemigo")


func _ready() -> void:
	super._ready()
	var mineral := load("res://assets/herramientas/mineral.glb") as PackedScene
	var pieza := mineral.instantiate() as Node3D
	pieza.rotation.y = randf_range(0.0, TAU)
	pieza.scale = Vector3.ONE * 1.55
	pieza.position.y = 0.14
	add_child(pieza)
	for mi: MeshInstance3D in pieza.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base != null:
				var acabado := base.duplicate() as BaseMaterial3D
				acabado.albedo_color = Datos.color_objeto(id_mineral).lerp(Color.WHITE, 0.45)
				mi.set_surface_override_material(i, acabado)


func _al_usar(_jugador: Node3D) -> void:
	unidades = Juego.anadir_objeto(id_mineral, unidades)
	if unidades <= 0:
		activo = false
		queue_free()
