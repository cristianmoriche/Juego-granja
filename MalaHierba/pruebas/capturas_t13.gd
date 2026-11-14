extends Node
## Capturas antes y después de T13-respuesta desde cámaras fijas.

const RAIZ_CAPTURAS := "C:/Users/cristianfsc/Desktop/Boveda/raw/juego-personajes/juego/gestion/noche-codex/capturas/T13-respuesta/"

var _fase: String = "antes"
var _carpeta: String = ""
var _cam: Camera3D = null
var _terminado: bool = false


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(nombre: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_carpeta + nombre + ".png")
	print("CAPTURA T13 [", _fase, "] ", nombre, " ", img.get_size())


func _poner_camara(pos: Vector3, mirar: Vector3) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = 45.0
		add_child(_cam)
	_cam.current = true
	_cam.global_position = pos
	_cam.look_at(mirar, Vector3.UP)


func _limpiar_camara() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
		_cam = null


func _preparar_parcela(zona: String, x: int, z: int, estado: String, cultivo: String = "", dias: int = 0, etapa: int = 0, regado: bool = false, listo: bool = false) -> String:
	var k := Cultivos.clave(zona, x, z)
	var c := Cultivos.parcela(k)
	if c.is_empty():
		return k
	c["estado"] = estado
	c["cultivo"] = cultivo
	c["dias"] = dias
	c["etapa"] = etapa
	c["regado"] = regado
	c["listo"] = listo
	c["golpes"] = 0
	return k


func _colocar_leo_en_celda(j: Node3D, p: Parcelas, k: String) -> Vector3:
	Juego.energia = Juego.energia_max
	var pos := p.posicion_de(k)
	var pie := pos + Vector3(-0.9, 0.02, 0.0)
	if j != null:
		j.global_position = pie
		j.set("direccion", Vector3(1, 0, 0))
	return pos


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	var env_fase := OS.get_environment("MH_T13_FASE")
	if env_fase == "antes" or env_fase == "despues":
		_fase = env_fase
	_carpeta = RAIZ_CAPTURAS + _fase + "/"
	DirAccess.make_dir_recursive_absolute(_carpeta)

	Juego.ruta_partida = "user://partida_capturas_t13.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.minutos = 680
	Juego.clima = "sol"
	await Escenas.ir_a_mapa("granja")
	await _esperar(0.8)

	var granja := Escenas.mapa_actual_nodo()
	var p := granja.get_node("Objetos/Parcelas") as Parcelas
	var j := Escenas.jugador()
	var zona := str(p._zonas[0]["nombre"])
	Interfaz.mostrar_hud(false)

	# 1. Labrar con azada
	var k1 := _preparar_parcela(zona, 2, 2, "limpio")
	var pos1 := _colocar_leo_en_celda(j, p, k1)
	p.reconstruir()
	_poner_camara(pos1 + Vector3(1.6, 1.35, 1.75), pos1 + Vector3(0.0, 0.15, 0.0))
	await get_tree().process_frame
	Cultivos.aplicar("azada", [k1])
	await _esperar(0.11)
	await _foto("01_labrar")
	await _esperar(0.7)

	# 2. Regar con regadera
	var k2 := _preparar_parcela(zona, 2, 3, "arado")
	var pos2 := _colocar_leo_en_celda(j, p, k2)
	p.reconstruir()
	_poner_camara(pos2 + Vector3(1.6, 1.35, 1.75), pos2 + Vector3(0.0, 0.25, 0.0))
	await get_tree().process_frame
	Cultivos.aplicar("regadera", [k2])
	await _esperar(0.10)
	await _foto("02_regar")
	await _esperar(0.7)

	# 3. Cosechar cultivo maduro
	var k3 := _preparar_parcela(zona, 2, 4, "arado", "tomate", 4, 3, false, true)
	var pos3 := _colocar_leo_en_celda(j, p, k3)
	p.reconstruir()
	_poner_camara(pos3 + Vector3(1.6, 1.4, 1.75), pos3 + Vector3(0.0, 0.45, 0.0))
	await get_tree().process_frame
	Cultivos.cosechar(k3)
	await _esperar(0.11)
	await _foto("03_cosechar")
	await _esperar(0.7)

	# 4. Talar tronco con hacha
	var k4 := _preparar_parcela(zona, 3, 2, "tronco")
	var pos4 := _colocar_leo_en_celda(j, p, k4)
	p.reconstruir()
	_poner_camara(pos4 + Vector3(1.6, 1.35, 1.75), pos4 + Vector3(0.0, 0.25, 0.0))
	await get_tree().process_frame
	Cultivos.aplicar("hacha", [k4])
	await _esperar(0.10)
	await _foto("04_talar")
	await _esperar(0.7)

	# 5. Picar piedra en granja
	var k5 := _preparar_parcela(zona, 3, 3, "piedra")
	var pos5 := _colocar_leo_en_celda(j, p, k5)
	p.reconstruir()
	_poner_camara(pos5 + Vector3(1.6, 1.35, 1.75), pos5 + Vector3(0.0, 0.25, 0.0))
	await get_tree().process_frame
	Cultivos.aplicar("pico", [k5])
	await _esperar(0.08)
	await _foto("05_picar_granja")
	await _esperar(0.7)

	# 6. Cambio de fase de cultivos (saltan y brillan): usar cultivos de primavera y despejar alrededor
	for dx in range(3, 6):
		for dz in range(1, 6):
			_preparar_parcela(zona, dx, dz, "limpio")
	var k6a := _preparar_parcela(zona, 4, 2, "arado", "patata", 1, 0, true, false)
	var k6b := _preparar_parcela(zona, 4, 3, "arado", "zanahoria", 1, 0, true, false)
	var k6c := _preparar_parcela(zona, 4, 4, "arado", "haba", 1, 0, true, false)
	var pos6 := p.posicion_de(k6b)
	if j != null:
		j.global_position = pos6 + Vector3(0.0, 0.02, 2.8)
	p.reconstruir()
	_poner_camara(pos6 + Vector3(2.0, 1.35, 2.0), pos6 + Vector3(0.0, 0.28, 0.0))
	await get_tree().process_frame
	Cultivos.procesar_dia()
	await _esperar(0.14)
	await _foto("06_cambio_fase_cultivo")

	# 7. Picar en mina_interior
	_limpiar_camara()
	await Escenas.ir_a_mapa("mina_interior")
	await _esperar(0.7)
	var mina := Escenas.mapa_actual_nodo()
	var rocas := mina.get_node("Objetos/RocasMina") as RocasMina
	Interfaz.mostrar_hud(false)
	var r0: RocasMina.Roca = rocas.rocas_en_pie()[0]
	var jm := Escenas.jugador()
	if jm != null:
		jm.global_position = r0.pos + Vector3(0.0, 0.02, 1.15)
		jm.set("direccion", Vector3(0, 0, -1))
	_poner_camara(r0.pos + Vector3(1.5, 1.25, 1.65), r0.pos + Vector3(0.0, 0.3, 0.0))
	await get_tree().process_frame
	rocas.golpear(r0)
	await _esperar(0.08)
	await _foto("07_picar_mina")
	_limpiar_camara()

	# 8. Vender en tienda (número flotante de dinero)
	Interfaz.mostrar_hud(true)
	Juego.anadir_objeto("patata", 6)
	Interfaz.abrir_tienda("tienda_mateo")
	await _esperar(0.25)
	var tienda := Interfaz._tienda
	tienda._cambiar_modo("vender")
	tienda._elegir("patata")
	tienda._cantidad = 3
	tienda._confirmar()
	await _esperar(0.22)
	await _foto("08_vender_dinero")
	Interfaz.cerrar_todo()

	# 9. Recompensa con icono (encargo del tablón + objeto añadido)
	var encargos := ObjetosPueblo.encargos_del_dia()
	if not encargos.is_empty():
		var e: Dictionary = encargos[0]
		Juego.anadir_objeto(str(e["pide"]), int(e["cantidad"]))
		ObjetosPueblo._encargo_elegido(0, encargos)
		await _esperar(0.25)
		await _foto("09_recompensa_icono")
		Interfaz.cerrar_todo()

	_terminado = true
	print("CAPTURAS T13 LISTAS (" + _fase + ")")
	get_tree().quit(0)
