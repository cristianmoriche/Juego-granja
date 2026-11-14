extends Node
## Prueba permanente T15: estaciones, cultivos e iconos de invierno, shaders/nieve,
## planificación persistente de eventos a 112 días y efectos reales de tormenta,
## plaga (con/sin tratamiento), mercado especial (x2) y comerciante ambulante.

var _fallos: Array[String] = []
var _terminado := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		if not _terminado:
			_fallos.append("tiempo límite agotado")
			_salir())
	await _ejecutar()
	_salir()


func _salir() -> void:
	if _terminado:
		return
	_terminado = true
	Juego.pausar_tiempo(false)
	Juego.borrar_partida()
	if _fallos.is_empty():
		print("PRUEBA T15 OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: " + "; ".join(_fallos))
		get_tree().quit(1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fallos.append(msg)
		push_error("T15 FAIL: " + msg)


func _buscar_dia_evento(tipo: String, desde_dia: int = 1) -> int:
	var prog := Juego.eventos_anio()
	for d in range(maxi(desde_dia, 1), 113):
		var c := str(d)
		if prog.has(c) and str((prog[c] as Dictionary).get("tipo", "")) == tipo:
			return d
	return -1


func _avanzar_a_dia_anio(objetivo: int) -> void:
	while Juego.dia_anio() < objetivo:
		if not Juego.terminar_dia(false, false):
			break


func _ejecutar() -> void:
	get_tree().current_scene = null
	Juego.pausar_tiempo(true)
	var ruta_previa := Juego.ruta_partida
	Juego.ruta_partida = "user://partida_prueba_t15.json"
	Juego.borrar_partida()
	Juego.nueva_partida("PruebaT15")

	# 1. Cultivos de invierno e iconos nuevos (128x128 RGBA con fondo transparente).
	var cult_inv: Array[String] = []
	for id: String in Datos.ids_cultivos():
		var c := Datos.cultivo(id)
		var ests: Array = c.get("estaciones", [])
		if ests.has(3):
			cult_inv.append(id)
	_ok(cult_inv.size() >= 3, "invierno debería tener >= 3 cultivos (tiene %d)" % cult_inv.size())
	_ok(cult_inv.has("espinaca") and cult_inv.has("nabo") and cult_inv.has("azafran"),
		"faltan cultivos de invierno nuevos en cultivos.json: %s" % str(cult_inv))

	for ic_id: String in [
		"espinaca", "nabo", "azafran",
		"semilla_espinaca", "semilla_nabo", "semilla_azafran",
		"remedio_plaga", "elixir_sierra", "ambar_valle",
	]:
		_ok(Datos.existe_objeto(ic_id), "objeto inexistente: %s" % ic_id)
		var tex := Datos.icono(ic_id)
		_ok(tex != null and tex.get_width() == 128 and tex.get_height() == 128, "icono inválido %s" % ic_id)
		var img := tex.get_image()
		if img != null:
			_ok(img.get_pixel(0, 0).a < 0.05, "icono %s sin fondo transparente" % ic_id)

	# 2. Plan de 112 días: al menos 1 evento por estación y los 4 tipos garantizados, guardado y recargado.
	var evs := Juego.eventos_anio()
	var por_est := [0, 0, 0, 0]
	var tipos := {}
	for k: Variant in evs:
		var d := int(str(k))
		var e_idx := clampi((d - 1) / Juego.DIAS_ESTACION, 0, 3)
		por_est[e_idx] += 1
		tipos[str((evs[k] as Dictionary).get("tipo", ""))] = true
	for e_i in 4:
		_ok(por_est[e_i] >= 1, "estación %d sin ningún evento" % e_i)
	for req: String in ["tormenta", "plaga", "mercado", "comerciante"]:
		_ok(tipos.has(req), "falta evento requerido en el año: %s" % req)

	_ok(Juego.guardar(), "fallo al guardar partida T15")
	var firma_antes := JSON.stringify(Juego.eventos_anio())
	Juego.nueva_partida("Otro")
	_ok(Juego.cargar(), "fallo al recargar partida T15")
	_ok(JSON.stringify(Juego.eventos_anio()) == firma_antes, "los eventos no se conservaron tras cargar")

	# 3. Crecimiento real de cultivos de invierno + prueba de tormenta (riego + cercas rotas).
	Cultivos.generar_zona("ZTest", 6, 6)
	var k_torm := Cultivos.clave("ZTest", 0, 0)
	var p_torm := Cultivos.parcela(k_torm)
	p_torm["estado"] = "arado"
	p_torm["regado"] = false
	Juego.anadir_objeto("semilla_espinaca", 2)
	_ok(Cultivos.aplicar("semilla_espinaca", [k_torm]) == false, "no debe permitir sembrar espinaca en primavera")

	var dia_torm := _buscar_dia_evento("tormenta")
	_ok(dia_torm > 1, "no hay tormenta programada")
	_avanzar_a_dia_anio(dia_torm - 1)
	var k_seco := Cultivos.clave("ZTest", 1, 1)
	Cultivos.parcela(k_seco)["estado"] = "arado"
	Cultivos.parcela(k_seco)["regado"] = false
	Juego.anadir_objeto("semilla_patata", 1)
	_ok(Cultivos.aplicar("semilla_patata", [k_seco]), "siembra previa a tormenta")
	Cultivos.parcela(k_seco)["regado"] = false
	_avanzar_a_dia_anio(dia_torm)
	_ok(Juego.clima == "tormenta" and Juego.esta_lloviendo(), "en tormenta clima=%s" % Juego.clima)
	_ok(bool(Cultivos.parcela(k_seco).get("regado", false)), "la tormenta debe regar los cultivos")
	_ok(Juego.hay_cercas_rotas(), "la tormenta debe romper cercas en la granja")

	# Verificar en granja real vallas rotas + nieve + reparacion + invierno visual.
	Juego.anadir_objeto("madera", 4)
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	var mapa_granja := Escenas.mapa_actual_nodo()
	_ok(mapa_granja != null, "granja no cargó")
	if mapa_granja != null:
		for _i in 180:
			if bool(mapa_granja.get("vallas_listas")):
				break
			await get_tree().process_frame
		_ok(mapa_granja.get_node_or_null("RepararCercas") != null, "granja debe mostrar RepararCercas cuando hay cercas rotas")
		_ok(Juego.reparar_cercas(), "reparar_cercas falló teniendo madera")
		_ok(not Juego.hay_cercas_rotas(), "las cercas siguen marcadas rotas tras reparar")
		await get_tree().process_frame
		_ok(mapa_granja.get_node_or_null("RepararCercas") == null, "RepararCercas debe desaparecer tras reparar")

	# 4. Plaga: un cultivo tratado conserva calidad 100%, uno sin tratar baja al 50%.
	var dia_plaga := _buscar_dia_evento("plaga")
	_ok(dia_plaga > dia_torm, "no hay plaga posterior a la tormenta")
	_avanzar_a_dia_anio(dia_plaga - 1)
	var kt1 := Cultivos.clave("ZTest", 0, 0)
	var kt2 := Cultivos.clave("ZTest", 5, 5)
	for kk in [kt1, kt2]:
		var pc := Cultivos.parcela(kk)
		pc["estado"] = "arado"
		pc["cultivo"] = "tomate"
		pc["dias"] = 6
		pc["etapa"] = 3
		pc["listo"] = true
		pc["plaga"] = false
		pc["calidad_baja"] = false
	_avanzar_a_dia_anio(dia_plaga)
	_ok(bool(Cultivos.parcela(kt1).get("plaga", false)) and bool(Cultivos.parcela(kt2).get("plaga", false)),
		"la plaga debe marcar las parcelas del cultivo afectado")
	Juego.anadir_objeto("remedio_plaga", 2)
	_ok(Cultivos.aplicar("remedio_plaga", [kt1]), "remedio antipulgas debe curar kt1")
	_ok(not bool(Cultivos.parcela(kt1).get("plaga", false)), "kt1 debe quedar curada")
	_ok(bool(Cultivos.parcela(kt2).get("plaga", false)), "kt2 (lejos) debe seguir con plaga")
	_avanzar_a_dia_anio(dia_plaga + 1)
	_ok(not bool(Cultivos.parcela(kt1).get("calidad_baja", false)), "kt1 curada no debe perder calidad")
	_ok(bool(Cultivos.parcela(kt2).get("calidad_baja", false)), "kt2 sin tratar debe perder calidad")

	# Cosechar kt1 vs kt2 y comprobar precios de venta y apilado separado.
	_ok(Cultivos.cosechar(kt1), "cosecha de kt1")
	_ok(Cultivos.cosechar(kt2), "cosecha de kt2")
	_ok(Juego.cantidad("tomate", "") >= 1, "falta tomate de calidad normal")
	_ok(Juego.cantidad("tomate", "baja") >= 1, "falta tomate de calidad baja")
	_ok(Juego.precio_venta_item("tomate", "baja") < Juego.precio_venta_item("tomate", ""),
		"la calidad baja debe pagarse menos que la normal")

	# 5. Mercado especial: doble valor exacto en el dia del evento.
	var dia_merc := _buscar_dia_evento("mercado", Juego.dia_anio())
	_ok(dia_merc > 0, "no hay mercado especial programado")
	_avanzar_a_dia_anio(dia_merc)
	var c_merc := Juego.cultivo_mercado_especial()
	_ok(not c_merc.is_empty(), "mercado especial vacío en su día")
	var base_m := int(Datos.objeto(c_merc).get("precio_venta", 0))
	_ok(Juego.precio_venta_item(c_merc, "") == base_m * 2,
		"mercado especial debe duplicar precio de %s (esperado %d, real %d)" % [c_merc, base_m * 2, Juego.precio_venta_item(c_merc, "")])

	# 6. Comerciante ambulante en el pueblo + objetos raros + desaparición al día siguiente.
	var dia_com := _buscar_dia_evento("comerciante", Juego.dia_anio())
	_ok(dia_com > 0, "no hay comerciante ambulante programado")
	_avanzar_a_dia_anio(dia_com)
	_ok(Juego.hay_comerciante(), "Juego.hay_comerciante() debe ser true en su día")
	var t_amb := Datos.tienda("comerciante_ambulante")
	_ok(not t_amb.is_empty() and (t_amb.get("vende", []) as Array).has("semilla_azafran") and (t_amb.get("vende", []) as Array).has("elixir_sierra") and (t_amb.get("vende", []) as Array).has("ambar_valle"),
		"tienda del mercader ambulante sin los objetos raros")
	await Escenas.ir_a_mapa("pueblo", "Spawn_Protagonista")
	var mapa_pueblo := Escenas.mapa_actual_nodo()
	_ok(mapa_pueblo != null, "pueblo no cargó")
	if mapa_pueblo != null:
		await get_tree().process_frame
		_ok(mapa_pueblo.objetos.get_node_or_null("MercaderAmbulante") != null, "pueblo debe mostrar MercaderAmbulante en su día")
	_avanzar_a_dia_anio(dia_com + 1)
	await get_tree().process_frame
	_ok(not Juego.hay_comerciante(), "comerciante debe irse al día siguiente")
	if mapa_pueblo != null:
		_ok(mapa_pueblo.objetos.get_node_or_null("MercaderAmbulante") == null, "MercaderAmbulante debe desaparecer al día siguiente")

	# 7. Invierno: nieve en shader global, partículas Nieve y cosecha real de espinaca/nabo/azafrán.
	_avanzar_a_dia_anio(86)   # día 2 de invierno
	_ok(Juego.estacion == 3, "se esperaba invierno (est=%d)" % Juego.estacion)
	await Escenas.ir_a_mapa("granja", "Spawn_Protagonista")
	var m_inv := Escenas.mapa_actual_nodo()
	await get_tree().process_frame
	var snow_val: Variant = RenderingServer.global_shader_parameter_get("nieve_estacion")
	if snow_val != null:
		_ok(float(snow_val) >= 0.9,
			"nieve_estacion debe ser ~1.0 en exterior en invierno")
	_ok(Juego.esta_nevando(), "Juego.esta_nevando() debe ser true en invierno")
	_ok(m_inv != null and m_inv.get_node_or_null("Nieve") != null, "falta GPUParticles3D Nieve en invierno")

	Cultivos.generar_zona("ZInv", 4, 4)
	for idx_i in 3:
		var id_c: String = ["espinaca", "nabo", "azafran"][idx_i]
		var kk := Cultivos.clave("ZInv", idx_i, 0)
		var cc := Cultivos.parcela(kk)
		cc["estado"] = "arado"
		cc["regado"] = true
		Juego.anadir_objeto("semilla_" + id_c, 1)
		_ok(Cultivos.aplicar("semilla_" + id_c, [kk]), "sembrar %s en invierno" % id_c)
	for _d in 8:
		for idx_i in 3:
			Cultivos.parcela(Cultivos.clave("ZInv", idx_i, 0))["regado"] = true
		Juego.estacion = 3
		Juego.dia = clampi(Juego.dia, 1, 20)
		Juego.terminar_dia(false, false)
	for idx_i in 3:
		var id_c: String = ["espinaca", "nabo", "azafran"][idx_i]
		var kk := Cultivos.clave("ZInv", idx_i, 0)
		_ok(Cultivos.esta_listo(kk), "%s debería madurar en invierno" % id_c)
		_ok(Cultivos.cosechar(kk), "cosecha de %s en invierno" % id_c)
		_ok(Juego.cantidad(id_c) >= 1, "falta %s en inventario tras cosechar" % id_c)

	Juego.borrar_partida()
	Juego.ruta_partida = ruta_previa
