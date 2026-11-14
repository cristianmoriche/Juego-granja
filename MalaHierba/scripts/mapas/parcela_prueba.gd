extends Node3D
## Usable de prueba (mapa de prueba de L3): una parcela que se ara con la azada y gasta energía.

var arada: bool = false
var _malla: MeshInstance3D


func _ready() -> void:
	add_to_group("usable")
	_malla = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.6, 0.1, 1.6)
	_malla.mesh = b
	_malla.position = Vector3(0, 0.05, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.6, 0.3)
	_malla.material_override = m
	add_child(_malla)


func usar(id_objeto: String, punto: Vector3, _jugador: Node3D) -> bool:
	if id_objeto != "azada" or arada:
		return false
	if punto.distance_to(global_position) > 1.4:
		return false
	if not Juego.gastar_energia(3.0):
		return true   # se intentó, pero está cansado: el golpe cuenta
	arada = true
	(_malla.material_override as StandardMaterial3D).albedo_color = Color(0.32, 0.2, 0.12)
	Interfaz.mensaje("Has arado la parcela.")
	return true
