class_name CamaGranja
extends Node3D
## Dormir en la cama de la casa de Leo (L4a/M1, movida al interior `casa_leo` en L5):
## un Interactuable «Dormir en la cama» en el marcador `Interaccion_cama` (o `Obj_cama`) de `casa_leo`.
## Solo existe en la casa de Leo (`casa_leo`): en ningún otro mapa ni interior aparece «Dormir».
## «E · Dormir en la cama» → pregunta → `Juego.dormir()`.

const ID_MAPA := "casa_leo"
const MARCADOR := "Interaccion_cama"
const MARCADOR_ALT := "Obj_cama"
const MALLA_CAMA := "Cama_estructura"

var _activa: bool = false
var _punto: Interactuable = null


func _ready() -> void:
	_punto = Interactuable.new()
	_punto.name = "PuntoDormir"
	_punto.verbo = "Dormir"
	_punto.nombre_objeto = "en la cama"
	_punto.radio = 1.4
	_punto.altura_marca = 1.5
	_punto.mostrar_descripcion = false
	_punto.activo = false
	_punto.usado.connect(func(_j: Node3D) -> void: _al_usar())
	add_child(_punto)
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	if id == ID_MAPA:
		colocar()
	else:
		_activa = false
		_punto.activo = false


## Se coloca junto a la cama de `casa_leo`; fuera de `casa_leo` no hay cama.
func colocar() -> void:
	var mapa: Node = get_parent().get_parent() if get_parent() != null else null
	if mapa == null or not mapa.has_method("marcador"):
		mapa = Escenas.mapa_actual_nodo()
	_activa = false
	if mapa != null and str(mapa.get("id_mapa")) == ID_MAPA and mapa.has_method("marcador"):
		var m := mapa.call("marcador", MARCADOR) as Marker3D
		if m == null:
			m = mapa.call("marcador", MARCADOR_ALT) as Marker3D
		if m != null:
			global_position = m.global_position
			_activa = true
		var mallas := mapa.find_children(MALLA_CAMA + "*", "MeshInstance3D", true, false)
		if not mallas.is_empty():
			_punto.objetivo_resaltado = mallas[0] as Node3D
		else:
			var mi := mapa.find_child(MALLA_CAMA + "*", true, false) as Node3D
			if mi != null:
				_punto.objetivo_resaltado = mi
	_punto.activo = _activa


func texto_interaccion() -> String:
	return _punto.texto_interaccion() if _activa and _punto != null else ""


func interactuar(_jugador: Node3D) -> void:
	_al_usar()


func _al_usar() -> void:
	Interfaz.preguntar("¿Dormir hasta mañana?", ["Dormir", "Todavía no"], _al_elegir)


func _al_elegir(indice: int) -> void:
	if indice == 0:
		Juego.dormir()
