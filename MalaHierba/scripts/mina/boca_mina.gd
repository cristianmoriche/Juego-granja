class_name BocaMina
extends Node3D
## Boca de la mina (L4b). Va dentro del nodo `Objetos` de `mina_exterior`. Al llegar al mapa de fuera (se sale de la
## mina por la boca o se viene del pueblo) la mina vuelve a su nivel 1: el próximo «Entrar» baja al primer nivel.

const ID_MAPA := "mina_exterior"


func _ready() -> void:
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	if id == ID_MAPA:
		Juego.banderas["nivel_mina"] = 1
