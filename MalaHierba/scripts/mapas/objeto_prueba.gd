extends Interactuable
## Interactuable de prueba (mapa de prueba de L3): habla con Leo para ver el cartel de acción y el diálogo.


func _ready() -> void:
	radio = 0.4
	altura_marca = 1.7
	super._ready()
	var cuerpo := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = 0.35
	c.height = 1.7
	cuerpo.mesh = c
	cuerpo.position = Vector3(0, 0.85, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.5, 0.35)
	cuerpo.material_override = m
	add_child(cuerpo)


func texto_interaccion() -> String:
	return "Hablar con Clara"


func interactuar(_jugador: Node3D) -> void:
	Interfaz.mostrar_dialogo("Clara", [
		"Ah, el de la ciudad. Soy Clara, la herrera. Si algo se te rompe, ven a verme.",
		"Para mejorar una herramienta necesito metal: cobre, hierro y, si hay suerte, cuarzo.",
	])
