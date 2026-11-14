extends Node
## Capturas de la granja (L4a). Necesita ventana; se cierra sola:
##   godot.ps1 --path <proyecto> --scene res://pruebas/capturas_l4a.tscn
## Guarda en res://pruebas/capturas/l4a_*.png: inicio (abandonada), todos los estados, cursor, cultivos de cerca y lluvia.

const SALIDA := "res://pruebas/capturas/"

var _p: Parcelas
var _j: Node3D
var _cam: Camera3D


func _ready() -> void:
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SALIDA + "l4a_" + nombre + ".png"))
	print("captura ", nombre, " ", img.get_size())


func _poner(zona: String, x: int, z: int, estado: String, cultivo: String = "", etapa: int = 0, regado: bool = false, listo: bool = false) -> void:
	var c := Cultivos.parcela(Cultivos.clave(zona, x, z))
	if c.is_empty():
		return
	c["estado"] = estado
	c["cultivo"] = cultivo
	c["etapa"] = etapa
	c["regado"] = regado
	c["listo"] = listo
	c["golpes"] = 0


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_capturas_l4a.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	Juego.nueva_partida("Leo")
	Juego.minutos = 660
	await Escenas.ir_a_mapa("granja")
	await _esperar(1.5)
	var mapa := Escenas.mapa_actual_nodo()
	_p = mapa.get_node("Objetos/Parcelas") as Parcelas
	_j = Escenas.jugador()
	var z0: Dictionary = _p._zonas[0]
	var zona := str(z0["nombre"])
	var centro: Vector3 = z0["centro"]

	# 1. La granja abandonada, tal como empieza la partida (cámara de juego).
	await _foto("inicio")

	# 2. Leo junto a la zona, con la azada en la mano: se ve el recuadro del cursor.
	var borde: Vector3 = _p.posicion_de(Cultivos.clave(zona, 0, 3))
	_j.call("colocar", borde + Vector3(-1.3, 0.05, 0), 0.0, 0.0)
	_j.set("direccion", Basis(Vector3.UP, float(z0["yaw"])) * Vector3.RIGHT)
	Juego.elegir_ranura(0)
	await _esperar(1.0)
	await _foto("cursor")

	# 3. Todos los estados a la vez (vista cenital oblicua con cámara propia).
	for x in 10:
		for z in 8:
			if z <= 3:
				continue
			_poner(zona, x, z, "limpio")
	for x in 4:
		_poner(zona, x, 0, "arado", "patata", x, x % 2 == 0, x == 3)
		_poner(zona, x, 1, "arado", "tomate", x, true, x == 3)
	for x in 5:
		_poner(zona, x + 4, 2, "arado", "melon", x, x % 2 == 1, x == 4)
	var listos := ["calabaza", "col", "boniato", "ajo", "pimiento", "haba"]
	for i in listos.size():
		_poner(zona, i + 4, 3, "arado", listos[i], 3, true, true)
		_poner(zona, i + 4, 0, "arado", listos[i], 1, false, false)
	for x in 4:
		_poner(zona, x, 4, "arado", "", 0, x % 2 == 1)
		_poner(zona, x + 4, 4, "limpio")
	_poner(zona, 8, 4, "maleza")
	_poner(zona, 9, 4, "piedra")
	_poner(zona, 9, 5, "tronco")
	Cultivos.parcelas_cambiadas.emit()
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 50.0
	_cam.global_position = centro + Vector3(0, 8.5, 9.5)
	_cam.look_at(centro + Vector3(0, 0, 0.5), Vector3.UP)
	_cam.make_current()
	await _esperar(0.8)
	await _foto("estados")

	# 4. Cultivos de cerca.
	_cam.global_position = _p.posicion_de(Cultivos.clave(zona, 4, 3)) + Vector3(2.8, 2.0, 3.2)
	_cam.look_at(_p.posicion_de(Cultivos.clave(zona, 4, 3)) + Vector3(0.7, 0.1, -0.3), Vector3.UP)
	await _esperar(0.5)
	await _foto("cultivos_cerca")
	_cam.global_position = _p.posicion_de(Cultivos.clave(zona, 1, 0)) + Vector3(1.6, 1.6, 2.6)
	_cam.look_at(_p.posicion_de(Cultivos.clave(zona, 1, 0)) + Vector3(0.7, 0.1, 0.3), Vector3.UP)
	await _esperar(0.4)
	await _foto("etapas_cerca")

	# 5. Las parcelas sin tocar de cerca (maleza, piedras y troncos): se regenera una zona nueva en otra partida.
	Juego.nueva_partida("Leo")
	await Escenas.ir_a_mapa("granja")
	await _esperar(1.0)
	_p = Escenas.mapa_actual_nodo().get_node("Objetos/Parcelas") as Parcelas
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 50.0
	_cam.global_position = centro + Vector3(0, 6.5, 7.0)
	_cam.look_at(centro, Vector3.UP)
	_cam.make_current()
	await _esperar(0.8)
	await _foto("obstaculos")

	# 6. Lluvia: todo lo arado regado.
	for k: String in _p.claves():
		var c := Cultivos.parcela(k)
		if str(c["estado"]) == "limpio" and randf() < 0.5:
			c["estado"] = "arado"
			c["regado"] = true
	Cultivos.parcelas_cambiadas.emit()
	Juego.clima = "lluvia"
	await Escenas.ir_a_mapa("granja")
	await _esperar(1.5)
	await _foto("lluvia")
	Juego.clima = "sol"

	if FileAccess.file_exists(Juego.ruta_partida):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Juego.ruta_partida))
	get_tree().quit(0)
