extends Interactuable
## Cultivo listo para cosechar (L4a): interactuable que crea `Parcelas` sobre cada casilla con cultivo maduro
## y quita cuando se cosecha. «E · Cosechar tomates».

var clave: String = ""


func _ready() -> void:
	radio = 0.37
	altura_marca = 0.75
	resaltar_mallas = false
	super._ready()


func texto_interaccion() -> String:
	if not Cultivos.esta_listo(clave):
		return ""
	return Cultivos.texto_cosecha(clave)


func interactuar(_jugador: Node3D) -> void:
	Cultivos.cosechar(clave)
