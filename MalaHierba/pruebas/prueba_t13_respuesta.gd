extends Node
## Verifica la tarea T13-respuesta: partículas por acción, sacudida de cámara (solo pico/hacha y desactivable),
## salto/brillo de cultivos al cambiar de fase, números flotantes de dinero y avisos con icono sin duplicados.

const CONFIG_PRUEBA := "user://ajustes_t13_prueba.cfg"
var _fallos: Array[String] = []
var _total: int = 0
var _terminado: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		if not _terminado:
			_terminado = true
			print("FALLO: tiempo límite excedido en prueba_t13_respuesta")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _comprobar(condicion: bool, texto: String) -> void:
	_total += 1
	if not condicion:
		_fallos.append(texto)
		print("FALLO: ", texto)


func _fotogramas(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ejecutar() -> void:
	var valores_antes := Ajustes.valores.duplicate()
	var teclas_antes := Ajustes.teclas.duplicate()
	var ruta_antes := Ajustes.ruta
	Ajustes.ruta = CONFIG_PRUEBA
	Ajustes.restaurar()
	Ajustes.valores["reducir_movimiento"] = false

	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_t13.json"
	Juego.nueva_partida("Prueba T13")
	Juego.pausar_tiempo(true)
	Juego.minutos = 660
	Juego.clima = "sol"

	await Escenas.ir_a_mapa("granja")
	while Escenas.en_transicion:
		await get_tree().process_frame
	await _fotogramas(4)

	var granja := Escenas.mapa_actual_nodo()
	var p := granja.get_node("Objetos/Parcelas") as Parcelas
	var zona := str(p._zonas[0]["nombre"])
	var cam := get_tree().get_first_node_in_group("camara_juego") as CamaraJuego
	_comprobar(p != null and cam != null, "granja carga con Parcelas y CamaraJuego")

	# Asegura que no queden efectos residuales antes de empezar.
	await _esperar(0.75)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).is_empty(), "sin efectos activos al inicio")

	# 1. Labrar: crea partículas de tierra y NO sacude la cámara.
	var k_lab := _prep(zona, 2, 2, "limpio")
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	var ok_lab := Cultivos.aplicar("azada", [k_lab])
	_comprobar(ok_lab, "azada labra parcela limpia")
	await _fotogramas(2)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 1, "labrar genera partículas en la escena")
	_comprobar(cam == null or not cam.hay_sacudida_activa(), "labrar no sacude la cámara")
	await _esperar(0.95)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).is_empty(), "partículas de labrar se limpian solas")

	# 2. Regar: crea partículas de agua y NO sacude la cámara.
	var k_reg := _prep(zona, 2, 3, "arado")
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	var ok_reg := Cultivos.aplicar("regadera", [k_reg])
	_comprobar(ok_reg, "regadera riega parcela arada")
	await _fotogramas(2)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 1, "regar genera partículas de agua")
	_comprobar(cam == null or not cam.hay_sacudida_activa(), "regar no sacude la cámara")
	await _esperar(0.95)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).is_empty(), "partículas de regar se limpian solas")

	# 3. Cosechar: partículas de hojas, NO sacude cámara y deja 1 único aviso con icono (sin texto duplicado sin icono).
	var k_cos := _prep(zona, 2, 4, "arado", "tomate", 4, 3, false, true)
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	var ok_cos := Cultivos.cosechar(k_cos)
	await _fotogramas(2)
	_comprobar(ok_cos, "cosechar recoge fruto")
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 1, "cosechar genera partículas de hojas")
	_comprobar(cam == null or not cam.hay_sacudida_activa(), "cosechar no sacude la cámara")
	var caja_avisos := Interfaz._hud.find_child("Avisos", true, false)
	_comprobar(caja_avisos != null and caja_avisos.get_child_count() == 1, "cosechar muestra 1 solo aviso (sin duplicado sin icono)")
	if caja_avisos != null and caja_avisos.get_child_count() >= 1:
		var fila := caja_avisos.get_child(0)
		var rect_ico: TextureRect = null
		for h in fila.get_children():
			for nh in h.get_children():
				if nh is TextureRect:
					rect_ico = nh as TextureRect
		_comprobar(rect_ico != null and rect_ico.texture != null, "aviso de recompensa al cosechar lleva icono del objeto")
	await _esperar(0.95)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).is_empty(), "partículas de cosechar se limpian solas")

	# 4. Picar piedra en granja y talar tronco: partículas + sacudida suave de cámara.
	var k_pie := _prep(zona, 3, 2, "piedra")
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	_comprobar(Cultivos.aplicar("pico", [k_pie]), "pico golpea piedra de granja")
	await _fotogramas(1)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 2, "picar genera esquirlas y chispas")
	_comprobar(cam != null and cam.hay_sacudida_activa(), "picar activa sacudida de cámara")
	await _esperar(0.95)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).is_empty(), "partículas de picar se limpian solas")

	var k_tro := _prep(zona, 3, 3, "tronco")
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	_comprobar(Cultivos.aplicar("hacha", [k_tro]), "hacha golpea tronco de granja")
	await _fotogramas(1)
	_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 1, "talar genera astillas")
	_comprobar(cam != null and cam.hay_sacudida_activa(), "talar activa sacudida de cámara")
	await _esperar(0.95)

	# 5. Reducir movimiento desactiva la sacudida incluso al picar/talar.
	Ajustes.valores["reducir_movimiento"] = true
	var k_pie2 := _prep(zona, 3, 4, "piedra")
	Juego.energia = Juego.energia_max
	p.reconstruir()
	await _fotogramas(2)
	Cultivos.aplicar("pico", [k_pie2])
	await _fotogramas(1)
	_comprobar(cam == null or not cam.hay_sacudida_activa(), "reducir_movimiento impide la sacudida de cámara")
	Ajustes.valores["reducir_movimiento"] = false
	await _esperar(0.95)

	# 6. Cambio de fase en cultivos: animación de salto + brillo al pasar de día y limpieza automática.
	var k_fase := _prep(zona, 4, 2, "arado", "patata", 1, 0, true, false)
	p.reconstruir()
	await _fotogramas(2)
	var etapa_antes := int(Cultivos.parcela(k_fase)["etapa"])
	Cultivos.procesar_dia()
	await _esperar(0.15)
	_comprobar(int(Cultivos.parcela(k_fase)["etapa"]) > etapa_antes, "cultivo regado sube de etapa al cambiar de día")
	_comprobar(p.animaciones_fase_activas() >= 1, "cambio de fase activa animación de salto en Parcelas")
	_comprobar(p.brillo_fase(k_fase) > 0.05, "cultivo recibe brillo temporal al subir de fase")
	# El renderizador headless devuelve transformaciones y colores por defecto al leer el MultiMesh.
	var con_gpu := DisplayServer.get_name() != "headless"
	var reg_dur: Dictionary = p._indices_cultivo.get(k_fase, {})
	_comprobar(not reg_dur.is_empty(), "cultivo en crecimiento tiene una instancia de planta")
	if con_gpu and not reg_dur.is_empty():
		var idx := int(reg_dur["p_idx"])
		var cur_tr := p._mm_planta.multimesh.get_instance_transform(idx)
		_comprobar(cur_tr.basis.y.length() > (reg_dur["p_tr"] as Transform3D).basis.y.length() * 1.02, "cultivo se estira verticalmente al subir de fase")
		var cur_cd := p._mm_planta.multimesh.get_instance_custom_data(idx)
		_comprobar(cur_cd.a > 0.05, "shader del cultivo recibe INSTANCE_CUSTOM.a > 0.05")
	await _esperar(0.85)
	_comprobar(p.animaciones_fase_activas() == 0, "animación de fase termina limpiamente")
	_comprobar(p.brillo_fase(k_fase) <= 0.01, "brillo del cultivo vuelve a su nivel base")
	if con_gpu and p._indices_cultivo.has(k_fase):
		var idx2 := int(p._indices_cultivo[k_fase]["p_idx"])
		var fin_cd := p._mm_planta.multimesh.get_instance_custom_data(idx2)
		_comprobar(fin_cd.a <= 0.01, "INSTANCE_CUSTOM.a vuelve a 0 al acabar el pulso")
	if not con_gpu:
		print("T13 sin ventana: 3 comprobaciones de MultiMesh requieren renderizado.")

	# 7. Picar en mina_interior también suelta esquirlas y chispas y sacude la cámara.
	await Escenas.ir_a_mapa("mina_interior")
	while Escenas.en_transicion:
		await get_tree().process_frame
	await _fotogramas(4)
	var mina := Escenas.mapa_actual_nodo()
	var rocas := mina.get_node_or_null("Objetos/RocasMina") as RocasMina
	var cam_mina := get_tree().get_first_node_in_group("camara_juego") as CamaraJuego
	_comprobar(rocas != null and not rocas.rocas_en_pie().is_empty(), "mina_interior tiene rocas disponibles")
	if rocas != null and not rocas.rocas_en_pie().is_empty():
		Juego.energia = Juego.energia_max
		var r0: RocasMina.Roca = rocas.rocas_en_pie()[0]
		_comprobar(rocas.golpear(r0), "golpear roca en mina funciona")
		await _fotogramas(2)
		_comprobar(get_tree().get_nodes_in_group(EfectosAccion.GRUPO_EFECTO).size() >= 2, "picar en mina genera esquirlas y chispas")
		_comprobar(cam_mina != null and cam_mina.hay_sacudida_activa(), "picar en mina sacude la cámara")
		await _esperar(0.85)

	# 8. Vender en tienda, Servicios (minerales) y ObjetosPueblo (encargos): número flotante +X €.
	Juego.anadir_objeto("patata", 4)
	Interfaz.abrir_tienda("tienda_mateo")
	await _fotogramas(3)
	var tienda := Interfaz._tienda
	tienda._cambiar_modo("vender")
	tienda._elegir("patata")
	tienda._cantidad = 2
	tienda._confirmar()
	await _fotogramas(2)
	_comprobar(Interfaz.numeros_flotantes_activos() >= 1, "vender en tienda crea número flotante +X €")
	Interfaz.cerrar_todo()
	await _esperar(1.15)
	_comprobar(Interfaz.numeros_flotantes_activos() == 0, "número flotante se destruye tras la animación")

	Juego.anadir_objeto("cobre", 3)
	var cobrado := Servicios.vender_mineral("cobre", 2)
	await _fotogramas(2)
	_comprobar(cobrado > 0 and Interfaz.numeros_flotantes_activos() >= 1, "vender mineral con Tomás crea número flotante")
	await _esperar(1.15)

	var encargos := ObjetosPueblo.encargos_del_dia()
	_comprobar(not encargos.is_empty(), "existen encargos diarios para probar entrega")
	if not encargos.is_empty():
		var e: Dictionary = encargos[0]
		Juego.anadir_objeto(str(e["pide"]), int(e["cantidad"]))
		ObjetosPueblo._encargo_elegido(0, encargos)
		await _fotogramas(2)
		_comprobar(Interfaz.numeros_flotantes_activos() >= 1, "entregar encargo crea número flotante +X €")
		_comprobar(Interfaz.avisos_activos() >= 1, "entregar encargo muestra aviso de recompensa con icono")
		Interfaz.cerrar_todo()

	Ajustes.valores = valores_antes
	Ajustes.teclas = teclas_antes
	Ajustes.ruta = ruta_antes
	_terminado = true
	if _fallos.is_empty():
		print("PRUEBA T13 RESPUESTA OK (%d comprobaciones)" % _total)
		get_tree().quit(0)
	else:
		print("PRUEBA T13 RESPUESTA FALLOS (%d/%d): %s" % [_fallos.size(), _total, ", ".join(_fallos)])
		get_tree().quit(1)


func _prep(zona: String, x: int, z: int, estado: String, cultivo: String = "", dias: int = 0, etapa: int = 0, regado: bool = false, listo: bool = false) -> String:
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
