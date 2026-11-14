class_name ObjetosPueblo
extends Node3D
## Cosas del pueblo con las que Leo puede interactuar (L4b), todas con la base `Interactuable` de M1:
## - el pozo de la plaza («Sacar agua del pozo»: llena la regadera y, una vez al día, +5 de energía);
## - el tablón de anuncios junto a la casa del alcalde (3 encargos al día de `datos/tablon.json`: entregar lo que
##   piden da dinero y amistad);
## - el carro (examinar) y dos bancos junto a la plaza («Sentarse»: +15 minutos y +3 de energía).
## Los carteles `txt_*` y otros objetos de ejemplo del pueblo los crea M1 (`Mapa`); aquí no se repiten.
## Va dentro del nodo `Objetos` del pueblo; se construye al llegar `Escenas.mapa_cargado("pueblo")`.

const ID_MAPA := "pueblo"
const RUTA_TABLON := "res://datos/tablon.json"
const POZO := Vector2(0.0, 0.0)
const RADIO_POZO := 1.8
const CARRO := Vector2(-5.2, 6.4)
const MARCADOR_TABLON := "Spawn_Alcalde"
const DESPLAZAR_TABLON := Vector2(-2.0, 1.5)
const ENCARGOS_AL_DIA := 3
const ENERGIA_POZO := 5.0
const MINUTOS_BANCO := 15
const ENERGIA_BANCO := 3.0

var pozo: Array[Interactuable] = []
var tablon: Interactuable = null
var carro: Interactuable = null
var bancos: Array[Interactuable] = []
var vida_pueblo: VidaPueblo = null
var construido: bool = false

static var _encargos_cache: Array[Dictionary] = []


func _ready() -> void:
	Escenas.mapa_cargado.connect(_al_mapa_cargado)


func _al_mapa_cargado(id: String) -> void:
	if id == ID_MAPA:
		construir()


## Crea (o rehace) los objetos. Necesita las colisiones del mapa ya registradas.
func construir() -> void:
	for h in get_children():
		remove_child(h)
		h.queue_free()
	pozo.clear()
	bancos.clear()
	tablon = null
	carro = null
	vida_pueblo = null
	_crear_pozo()
	_crear_tablon()
	_crear_carro()
	_crear_bancos()
	vida_pueblo = VidaPueblo.new()
	vida_pueblo.name = "VidaPueblo"
	add_child(vida_pueblo)
	vida_pueblo.actualizar()
	construido = true


func _suelo_en(x: float, z: float) -> Vector3:
	var s := AyudasL4b.suelo(self, Vector3(x, 0.0, z), 4.0, 8.0)
	return s if s != Vector3.INF else Vector3(x, 0.0, z)


func _punto(nombre: String, verbo: String, objeto: String, radio: float, altura: float) -> Interactuable:
	var c := Interactuable.new()
	c.name = nombre
	c.verbo = verbo
	c.nombre_objeto = objeto
	c.radio = radio
	c.altura_marca = altura
	c.mostrar_descripcion = false
	add_child(c)
	return c


# --- Pozo --------------------------------------------------------------------------------------------

## El pozo mide unos 3,6 m (con su tejadillo): cuatro puntos de uso en cruz a su alrededor, para que valga
## acercarse por cualquier lado.
func _crear_pozo() -> void:
	for i in 4:
		var a := TAU * float(i) / 4.0
		var p := _suelo_en(POZO.x + cos(a) * RADIO_POZO, POZO.y + sin(a) * RADIO_POZO)
		var c := _punto("Pozo_%d" % i, "Sacar", "agua del pozo", 1.0, 1.6)
		c.global_position = p
		c.usado.connect(func(_j: Node3D) -> void: sacar_agua())
		pozo.append(c)


## Llena la regadera y, la primera vez cada día, bebe: +5 de energía. Devuelve true si ha bebido.
func sacar_agua() -> bool:
	var est := estado()
	var bebido := false
	if int(est.get("pozo_dia", -1)) != AyudasL4b.clave_dia() and Juego.energia < Juego.energia_max - 0.01:
		est["pozo_dia"] = AyudasL4b.clave_dia()
		Juego.recuperar_energia(ENERGIA_POZO)
		bebido = true
		Interfaz.mensaje("Llenas la regadera. Bebes agua fresca: +%d de energía." % int(ENERGIA_POZO))
	elif int(est.get("pozo_dia", -1)) == AyudasL4b.clave_dia():
		Interfaz.mensaje("Llenas la regadera hasta el borde. Hoy ya has bebido bastante.")
	else:
		Interfaz.mensaje("Llenas la regadera hasta el borde. Tienes las fuerzas a tope.")
	return bebido


## Estado del pueblo que se guarda con la partida (solo datos de JSON).
static func estado() -> Dictionary:
	if not (Juego.estado_mapas.get(ID_MAPA, null) is Dictionary):
		Juego.estado_mapas[ID_MAPA] = {}
	return Juego.estado_mapas[ID_MAPA]


# --- Tablón de anuncios ------------------------------------------------------------------------------------

func _crear_tablon() -> void:
	var mapa := _mapa()
	var m: Marker3D = mapa.call("marcador", MARCADOR_TABLON) as Marker3D if mapa != null else null
	var base := (m.global_position if m != null else Vector3.ZERO) + Vector3(DESPLAZAR_TABLON.x, 0, DESPLAZAR_TABLON.y)
	var p := AyudasL4b.sitio_libre(self, base, 0.7, 4.0)
	var madera := Color(0.43, 0.30, 0.18)
	var raiz := Node3D.new()
	raiz.name = "TablonAnuncios"
	add_child(raiz)
	raiz.global_position = p
	AyudasL4b.caja(raiz, Vector3(0.14, 2.0, 0.14), Vector3(-0.65, 1.0, 0), madera, true)
	AyudasL4b.caja(raiz, Vector3(0.14, 2.0, 0.14), Vector3(0.65, 1.0, 0), madera, true)
	AyudasL4b.caja(raiz, Vector3(1.6, 1.0, 0.07), Vector3(0, 1.45, 0), Color(0.58, 0.42, 0.26))
	AyudasL4b.caja(raiz, Vector3(1.76, 0.1, 0.2), Vector3(0, 2.02, 0), madera)
	# Papeles clavados.
	var papeles: Array = [[-0.45, 1.6, 0.4, 0.5], [0.05, 1.35, 0.35, 0.45], [0.5, 1.62, 0.38, 0.5]]
	for pp: Array in papeles:
		AyudasL4b.caja(raiz, Vector3(float(pp[2]), float(pp[3]), 0.015), Vector3(float(pp[0]), float(pp[1]), 0.045), Color(0.93, 0.89, 0.76))
	# Mirando a la plaza.
	raiz.look_at(Vector3(POZO.x, p.y, POZO.y), Vector3.UP, true)
	tablon = _punto("Tablon", "Leer", "el tablón de anuncios", 1.2, 2.4)
	tablon.global_position = p + raiz.global_transform.basis.z * 0.8
	tablon.usado.connect(func(_j: Node3D) -> void: menu_tablon())


func _mapa() -> Node:
	var n: Node = get_parent()
	while n != null and not n.is_in_group("mapa"):
		n = n.get_parent()
	return n


## Todos los encargos posibles de `datos/tablon.json`.
static func todos_los_encargos() -> Array[Dictionary]:
	return TareasDiarias.todos_los_encargos_entrega()


## Los encargos que hay hoy en el tablón: tres, siempre los mismos durante el día y distintos de un día a otro.
static func encargos_del_dia() -> Array[Dictionary]:
	return TareasDiarias.encargos_del_dia()


static func encargo_hecho(id_encargo: String) -> bool:
	return TareasDiarias.encargo_hecho(id_encargo)


static func texto_encargo(e: Dictionary) -> String:
	return TareasDiarias.texto_encargo(e)


## Entrega o cobra un encargo de hoy. Devuelve «ok», «hecho», «faltan» o «no_hoy».
static func entregar(id_encargo: String) -> String:
	return TareasDiarias.entregar(id_encargo)


func menu_tablon() -> void:
	var encargos := encargos_del_dia()
	var textos: Array = []
	var cabecera := "Tablón de anuncios del ayuntamiento. Tareas de hoy (caducan esta noche):"
	for e in encargos:
		cabecera += "\n· " + texto_encargo(e)
		var id_e := str(e.get("id", ""))
		var tipo := str(e.get("tipo", "entregar"))
		var icono := str(e.get("pide", "")) if tipo == "entregar" else str(e.get("icono", "pan"))
		var prog := TareasDiarias.progreso_de(e)
		if tipo == "entregar":
			var pide := Datos.nombre_objeto(str(e.get("pide", "")))
			if encargo_hecho(id_e):
				textos.append({"texto": "Entregado: %d × %s" % [int(e.get("cantidad", 0)), pide], "icono": icono})
			else:
				textos.append({"texto": "Entregar %d × %s por %s  (llevas %d)" % [int(e.get("cantidad", 0)), pide, Estilo.euros(int(e.get("dinero", 0))), prog.x], "icono": icono})
		else:
			if encargo_hecho(id_e):
				textos.append({"texto": "Completada: %s" % texto_encargo(e), "icono": icono})
			else:
				var marca := "Cobrar " if prog.x >= prog.y else "En curso "
				textos.append({"texto": "%s(%d/%d) por %s (+%d amistad)" % [marca, prog.x, prog.y, Estilo.euros(int(e.get("dinero", 0))), int(e.get("amistad", 0))], "icono": icono})
	textos.append("Cerrar")
	Interfaz.preguntar(cabecera, textos, _encargo_elegido.bind(encargos))


static func _encargo_elegido(i: int, encargos: Array[Dictionary]) -> void:
	if i < 0 or i >= encargos.size():
		return
	var e: Dictionary = encargos[i]
	var quien := str(Datos.npc(str(e.get("npc", ""))).get("nombre", "el vecino"))
	var tipo := str(e.get("tipo", "entregar"))
	var icono := str(e.get("pide", "")) if tipo == "entregar" else str(e.get("icono", "pan"))
	var resultado := entregar(str(e.get("id", "")))
	if resultado == "ok":
		var texto := "Completada la tarea de %s: cobras %s y +%d de amistad." % [quien, Estilo.euros(int(e.get("dinero", 0))), int(e.get("amistad", 0))]
		Interfaz.mensaje(texto, icono)
		Interfaz.mostrar_dialogo("Tablón", [{"texto": texto, "icono": icono}])
	elif resultado == "hecho":
		Interfaz.mostrar_dialogo("Tablón", ["Esta tarea ya está completada. Mañana habrá otras."])
	elif resultado == "faltan":
		if tipo == "entregar":
			Interfaz.mostrar_dialogo("Tablón", ["Todavía no llevas lo que piden: %d × %s." % [int(e.get("cantidad", 0)), Datos.nombre_objeto(str(e.get("pide", "")))]])
		else:
			var prog := TareasDiarias.progreso_de(e)
			Interfaz.mostrar_dialogo("Tablón", ["Aún te falta completar la tarea (%d / %d): %s" % [prog.x, prog.y, texto_encargo(e)]])
	else:
		Interfaz.mostrar_dialogo("Tablón", ["Ese anuncio ya no está."])


# --- Carro y bancos ----------------------------------------------------------------------------------

func _crear_carro() -> void:
	carro = _punto("Carro", "Examinar", "el carro", 1.3, 1.6)
	carro.global_position = _suelo_en(CARRO.x, CARRO.y)
	carro.descripcion = "Un carro de labranza con una rueda aflojada y paja seca en el fondo. Lleva ahí parado mucho tiempo, pero la madera sigue firme.\n\nSe nota que antes llevaba género al mercado de los jueves."
	carro.titulo_dialogo = "El carro"
	carro.mostrar_descripcion = true


## Dos bancos de madera cerca de la plaza, mirando al pozo.
func _crear_bancos() -> void:
	var deseados: Array[Vector2] = [Vector2(4.6, 3.4), Vector2(-4.4, -3.6)]
	for k in deseados.size():
		var d := deseados[k]
		var p := AyudasL4b.sitio_libre(self, _suelo_en(d.x, d.y), 1.0, 5.0)
		var raiz := Node3D.new()
		raiz.name = "Banco_%d" % k
		add_child(raiz)
		raiz.global_position = p
		var madera := Color(0.47, 0.33, 0.2)
		AyudasL4b.caja(raiz, Vector3(1.7, 0.08, 0.5), Vector3(0, 0.46, 0), madera, true)
		AyudasL4b.caja(raiz, Vector3(1.7, 0.4, 0.07), Vector3(0, 0.78, -0.22), madera)
		AyudasL4b.caja(raiz, Vector3(0.08, 0.46, 0.46), Vector3(-0.72, 0.23, 0), Color(0.3, 0.3, 0.32))
		AyudasL4b.caja(raiz, Vector3(0.08, 0.46, 0.46), Vector3(0.72, 0.23, 0), Color(0.3, 0.3, 0.32))
		raiz.look_at(Vector3(POZO.x, p.y, POZO.y), Vector3.UP, true)
		var c := _punto("Sentarse_%d" % k, "Sentarse", "en el banco", 1.0, 1.4)
		c.global_position = p + raiz.global_transform.basis.z * 0.5
		c.usado.connect(func(_j: Node3D) -> void: sentarse())
		bancos.append(c)


## Descansa un rato: pasan 15 minutos y recupera 3 de energía.
func sentarse() -> void:
	Interfaz.preguntar("Hay un banco a la sombra. ¿Descansar un rato?", ["Sentarse un rato (+%d min, +%d de energía)" % [MINUTOS_BANCO, int(ENERGIA_BANCO)], "Ahora no"], func(i: int) -> void:
		if i == 0:
			descansar())


func descansar() -> void:
	Juego.recuperar_energia(ENERGIA_BANCO)
	Interfaz.mensaje("Te sientas un rato a ver pasar la tarde. Recuperas %d de energía." % int(ENERGIA_BANCO))
	Juego.avanzar_minutos(MINUTOS_BANCO)
