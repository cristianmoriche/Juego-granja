extends Node
## Prueba del guardado robusto. Se ejecuta sin ventana:
##   godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_guardado.tscn
## Comprueba: escritura atómica (temporal → partida), copia de seguridad de la partida válida anterior, versión de
## formato y migración desde la versión 1, partida dañada (con y sin copia), guardado interrumpido y partida de una
## versión futura. Usa un archivo propio en user:// y lo borra al terminar: la partida del jugador no se toca.
## Imprime «PRUEBA OK (n comprobaciones)» o «PRUEBA FALLO: <motivos>» y sale con 0 o 1.

const RUTA := "user://partida_prueba_guardado.json"

var _fallos: Array[String] = []
var _total: int = 0


func _ready() -> void:
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, motivo: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(motivo)
		print("  FALLO: ", motivo)


func _escribir(ruta: String, texto: String) -> void:
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	f.store_string(texto)
	f.close()


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = RUTA
	Juego.borrar_partida()
	var copia := RUTA + Juego.SUFIJO_COPIA
	var temporal := RUTA + Juego.SUFIJO_TEMPORAL

	print("[primer guardado]")
	_comprobar(Juego.estado_guardado() == "ninguna", "sin archivos el estado es «ninguna»")
	Juego.nueva_partida("Prueba")
	Juego.pausar_tiempo(true)
	Juego.dinero = 111
	_comprobar(Juego.guardar(), "guardar devuelve true")
	_comprobar(Juego.hay_partida() and not FileAccess.file_exists(temporal), "queda la partida y no queda temporal")
	_comprobar(not Juego.hay_copia(), "el primer guardado no crea copia (no había partida anterior)")
	_comprobar(Juego.estado_guardado() == "ok", "el estado es «ok»")
	var d := Juego.leer_archivo(RUTA)
	_comprobar(int(d.get("version", 0)) == Juego.VERSION_GUARDADO, "el archivo lleva la versión %d del formato" % Juego.VERSION_GUARDADO)
	_comprobar(not str(d.get("guardado_el", "")).is_empty(), "el archivo lleva la fecha del guardado")

	print("[copia de seguridad]")
	Juego.dinero = 222
	_comprobar(Juego.guardar(), "segundo guardado")
	_comprobar(Juego.hay_copia(), "el segundo guardado deja copia de seguridad")
	_comprobar(int(Juego.leer_archivo(copia).get("dinero", 0)) == 111, "la copia es la partida anterior (111 €)")
	_comprobar(int(Juego.leer_archivo(RUTA).get("dinero", 0)) == 222, "la partida es la nueva (222 €)")
	_comprobar("222" in Juego.resumen_de(RUTA), "el resumen para el menú dice el dinero (%s)" % Juego.resumen_de(RUTA))

	print("[partida dañada con copia]")
	_escribir(RUTA, "{\"dinero\": 22")     # cortada a medias
	_comprobar(Juego.estado_guardado() == "danada_con_copia", "partida cortada + copia = «danada_con_copia»")
	Juego.dinero = 999
	_comprobar(not Juego.cargar(), "cargar una partida dañada devuelve false")
	_comprobar(not Juego.ultimo_error_carga.is_empty(), "y explica por qué (%s)" % Juego.ultimo_error_carga)
	_comprobar(Juego.dinero == 999, "una carga fallida no toca el estado en memoria")
	_comprobar(Juego.recuperar_copia(), "recuperar la copia devuelve true")
	_comprobar(Juego.estado_guardado() == "ok" and Juego.cargar() and Juego.dinero == 111, "tras recuperar se carga la partida anterior (111 €)")
	_comprobar(FileAccess.file_exists(RUTA + Juego.SUFIJO_DANADA), "el archivo dañado se conserva aparte")
	_comprobar(Juego.hay_copia(), "la copia de seguridad sigue en su sitio después de recuperarla")

	print("[guardar encima de una partida dañada]")
	_escribir(RUTA, "esto no es json")
	Juego.dinero = 333
	_comprobar(Juego.guardar(), "se puede guardar aunque la partida del disco esté dañada")
	_comprobar(int(Juego.leer_archivo(copia).get("dinero", 0)) == 111, "la partida dañada no pisa la copia buena (sigue en 111 €)")
	_comprobar(int(Juego.leer_archivo(RUTA).get("dinero", 0)) == 333, "y la partida nueva es válida (333 €)")

	print("[partida dañada sin copia]")
	Juego.borrar_partida()
	_escribir(RUTA, "")
	_comprobar(Juego.estado_guardado() == "danada_sin_copia", "archivo vacío sin copia = «danada_sin_copia»")
	_comprobar(not Juego.recuperar_copia(), "sin copia no hay nada que recuperar")
	_escribir(RUTA, "{\"otra_cosa\": 1}")
	_comprobar(Juego.leer_archivo(RUTA).is_empty() and not Juego.cargar(), "un JSON que no es una partida no se carga")

	print("[guardado interrumpido]")
	# Como si el juego se hubiera cerrado entre apartar la partida anterior y poner la nueva: no hay partida, pero
	# sí el temporal (entero) y la copia.
	Juego.borrar_partida()
	Juego.dinero = 444
	Juego.guardar()
	Juego.dinero = 555
	Juego.guardar()
	DirAccess.rename_absolute(RUTA, temporal)
	_comprobar(not Juego.hay_partida() and Juego.estado_guardado() == "danada_con_copia", "sin partida pero con temporal y copia = «danada_con_copia»")
	_comprobar(Juego.recuperar_copia() and Juego.cargar() and Juego.dinero == 555, "se recupera lo más reciente: el temporal (555 €)")
	# Un temporal cortado no vale: se usa la copia.
	Juego.borrar_partida()
	Juego.dinero = 666
	Juego.guardar()
	Juego.dinero = 777
	Juego.guardar()
	DirAccess.remove_absolute(RUTA)
	_escribir(temporal, "{\"dinero\": 7")
	_comprobar(Juego.recuperar_copia() and Juego.cargar() and Juego.dinero == 666, "con el temporal cortado se recupera la copia (666 €)")

	print("[migración desde la versión 1]")
	Juego.borrar_partida()
	var vieja := {
		"version": 1, "nombre_jugador": "Antigua", "dinero": 1234, "deuda": 5000, "energia": 40, "energia_max": 100,
		"dia": 9, "estacion": 1, "anio": 1, "minutos": 700, "clima": "sol",
		"inventario": [{"id": "azada", "cantidad": 1}, {}, {"id": "objeto_que_ya_no_existe", "cantidad": 3}, {"id": "piedra", "cantidad": 500}],
		"ranura": 0, "amistad": {"mateo": 80}, "hablado_hoy": {}, "nivel_herramientas": {"pico": 1}, "estado_mapas": {},
		"banderas": {}, "mapa_actual": "pueblo", "estadisticas": {"cosechas": 7},
	}
	_escribir(RUTA, JSON.stringify(vieja))
	_comprobar(Juego.estado_guardado() == "ok", "una partida de la versión 1 se reconoce como válida")
	_comprobar(Juego.cargar(), "y se carga")
	_comprobar(Juego.nombre_jugador == "Antigua" and Juego.dinero == 1234 and Juego.dia == 9 and Juego.estacion == 1 and Juego.mapa_actual == "pueblo", "conserva nombre, dinero, fecha y mapa")
	_comprobar(Juego.puntos_amistad("mateo") == 80 and Juego.nivel("pico") == 1, "conserva amistad y nivel de herramientas")
	_comprobar(Juego.cantidad("azada") == 1 and Juego.cantidad("objeto_que_ya_no_existe") == 0, "conserva el inventario y descarta objetos que ya no existen")
	_comprobar(Juego.cantidad("piedra") == Juego.PILA_MAX, "una pila imposible (500) se recorta al máximo (%d)" % Juego.PILA_MAX)
	_comprobar(int(Juego.estadisticas.get("cosechas", 0)) == 7 and Juego.estadisticas.has("dinero_ganado"), "completa las estadísticas que faltaban sin perder las que había")
	_comprobar(Juego.guardar() and int(Juego.leer_archivo(RUTA).get("version", 0)) == Juego.VERSION_GUARDADO, "al guardar queda en el formato actual")
	_comprobar(int(Juego.leer_archivo(copia).get("version", 0)) == 1, "y la partida antigua queda de copia de seguridad, sin tocar")

	print("[valores fuera de rango y versión futura]")
	Juego.borrar_partida()
	vieja["dia"] = 99
	vieja["estacion"] = 7
	vieja["energia"] = 9999
	vieja["minutos"] = 5
	vieja["inventario"] = "no es una lista"
	_escribir(RUTA, JSON.stringify(vieja))
	_comprobar(not Juego.cargar(), "un inventario que no es una lista se rechaza")
	vieja["inventario"] = [42, "texto", {"id": "azada"}]
	_escribir(RUTA, JSON.stringify(vieja))
	_comprobar(Juego.cargar(), "huecos de inventario con basura no impiden cargar")
	_comprobar(Juego.dia == Juego.DIAS_ESTACION and Juego.estacion == 3 and Juego.energia <= Juego.energia_max and Juego.minutos == Juego.HORA_INICIO, "día, estación, energía y hora se recortan a valores posibles")
	_comprobar(Juego.cantidad("azada") == 1, "y lo que sí es un objeto se conserva")
	vieja["version"] = Juego.VERSION_GUARDADO + 5
	_escribir(RUTA, JSON.stringify(vieja))
	Juego.dinero = 31
	_comprobar(not Juego.cargar() and "más nueva" in Juego.ultimo_error_carga and Juego.dinero == 31, "una partida de una versión futura no se abre y se dice por qué")

	Juego.borrar_partida()
	_comprobar(Juego.estado_guardado() == "ninguna", "borrar_partida no deja restos")
	if _fallos.is_empty():
		print("PRUEBA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: ", "; ".join(PackedStringArray(_fallos)))
		get_tree().quit(1)
