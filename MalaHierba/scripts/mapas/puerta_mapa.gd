class_name PuertaMapa
extends Interactuable
## Puerta interactuable entre un mapa exterior y un interior (encargo L5).
## Hereda de Interactuable (M1): muestra «E · Entrar en …» o «E · Salir a …», anillo y flecha de resaltado,
## y pertenece al grupo «puerta» para que el minimapa y el mapa grande la pinten con rombo.

@export var destino: String = ""
@export var llegada: String = "Entrada"
@export var texto: String = ""
@export var nombre_malla: String = ""


func _ready() -> void:
	mostrar_descripcion = false
	add_to_group("puerta")
	super._ready()


func _al_usar(_jugador: Node3D) -> void:
	if destino.is_empty() or Escenas.en_transicion:
		return
	Audio.usar_puerta()
	Escenas.ir_a_mapa(destino, llegada)
