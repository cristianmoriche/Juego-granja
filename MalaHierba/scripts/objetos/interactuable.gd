class_name Interactuable
extends Area3D
## Base reutilizable de todo lo que se puede usar con E: carteles, pozos, puertas, vecinos, cajas...
## Es un Area3D en la capa 3 («interactuables»). El jugador lo detecta con la mira, lo resalta y
## al pulsar E o hacer clic llama a interactuar(). Si requiere herramienta, muestra la pista de «usar».
##
## Uso rápido (sin heredar):
##   var c := Interactuable.new()
##   c.verbo = "Leer"; c.nombre_objeto = "el cartel"; c.descripcion = "Camino a las minas."
##   mapa.objetos.add_child(c); c.global_position = punto
## Para hacer algo propio: conecta la señal `usado(jugador)` (y pon `mostrar_descripcion = false` si no quieres
## el cuadro de texto), o hereda y sobreescribe `_al_usar(jugador)`.

## Se dispara al pulsar E sobre el objeto.
signal usado(jugador: Node3D)

## Verbo del cartel de acción: «Examinar», «Leer», «Hablar con», «Entrar en»...
@export var verbo: String = "Examinar"
## Lo que sale tras el verbo: «el cartel», «Clara», «la tienda»... Si va vacío, solo se ve el verbo.
@export var nombre_objeto: String = ""
## Texto que se muestra al usarlo (varios párrafos separados por una línea en blanco). Vacío: no muestra nada.
@export_multiline var descripcion: String = ""
## Nombre que sale en el cuadro de texto (por defecto, `nombre_objeto` con mayúscula inicial).
@export var titulo_dialogo: String = ""
## Radio de la marca y de la esfera de apuntado si el objeto no trae una forma propia.
@export var radio: float = 0.8
## Altura de la flecha que marca el objeto elegido (y del nombre flotante).
@export var altura_marca: float = 1.5
## Si es false, no se puede elegir ni usar (el cartel desaparece).
@export var activo: bool = true:
	set(valor):
		activo = valor
		set_deferred("collision_layer", 4 if activo else 0)
## Objeto que se debe llevar en la mano para accionar este punto con «usar».
@export var herramienta: String = ""
## Si es true y hay `descripcion`, se muestra con Interfaz.mostrar_dialogo tras emitir `usado`.
@export var mostrar_descripcion: bool = true
## Pone el nombre flotando sobre el objeto elegido (para vecinos).
@export var mostrar_nombre: bool = false
## Resalta con brillo las mallas (MeshInstance3D) que cuelgan de este nodo. Los carteles y edificios del mapa son
## geometría fusionada y no se pueden resaltar así: para ellos sirve el anillo y la flecha, que siempre salen.
@export var resaltar_mallas: bool = true
## Nodo cuyas mallas se resaltan. Por defecto: el padre si es un cuerpo físico (un vecino), si no este nodo.
@export var nodo_visual: NodePath
## Referencia directa opcional al nodo/malla que debe brillar al resaltar (puertas y muebles de interiores).
var objetivo_resaltado: Node3D = null

const ALCANCE := 1.2


func _ready() -> void:
	collision_layer = 4 if activo else 0
	collision_mask = 0
	monitoring = false
	add_to_group("interactuable")
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		var forma := CollisionShape3D.new()
		var esfera := SphereShape3D.new()
		esfera.radius = maxf(radio, 0.3)
		forma.shape = esfera
		forma.position = Vector3(0, minf(altura_marca * 0.5, 1.0), 0)
		add_child(forma)


## Texto del cartel de acción, sin la tecla: «Leer el cartel». Vacío si no se puede usar.
func texto_interaccion() -> String:
	if not activo:
		return ""
	if nombre_objeto.is_empty():
		return verbo
	return verbo + " " + nombre_objeto


## Alcance antiguo desde el centro del objeto, para consultas geométricas existentes.
func alcance_interaccion() -> float:
	return ALCANCE + radio


## Nodo cuyas mallas brillan al elegirlo.
func nodo_resaltado() -> Node3D:
	if objetivo_resaltado != null and is_instance_valid(objetivo_resaltado):
		return objetivo_resaltado
	if not nodo_visual.is_empty():
		var n := get_node_or_null(nodo_visual) as Node3D
		if n != null:
			return n
	var p := get_parent() as PhysicsBody3D
	return p if p != null else self


## Punto sobre el que flota la flecha de resaltado.
func punto_marca() -> Vector3:
	return global_position + Vector3(0, altura_marca, 0)


## Nombre que flota sobre el objeto elegido (vacío si no hay que mostrarlo).
func nombre_resaltado() -> String:
	return nombre_objeto if mostrar_nombre else ""


func interactuar(jugador: Node3D) -> void:
	if not activo:
		return
	_al_usar(jugador)
	usado.emit(jugador)
	if mostrar_descripcion and not descripcion.is_empty():
		var titulo := titulo_dialogo
		if titulo.is_empty() and not nombre_objeto.is_empty():
			titulo = nombre_objeto.substr(0, 1).to_upper() + nombre_objeto.substr(1)
		var lineas: Array = []
		for p in descripcion.split("\n\n", false):
			lineas.append(p.strip_edges())
		Interfaz.mostrar_dialogo(titulo, lineas)


## Para heredar: lo que hace al usarlo (antes de la señal y del texto).
func _al_usar(_jugador: Node3D) -> void:
	pass
