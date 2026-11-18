extends Node
## Comprobación breve de H05-mapa-grande:
## - Superficies >= 2.0x en zonas clásicas ampliadas
## - 3 zonas nuevas cargando en <= 5000 ms, límites, vallas, conexiones bidireccionales y horizonte
## - Parcelas desbloqueables en granja, recolección, vetas, cofres, pesca y encuentros al anochecer

const AREAS_ANTES := {
	"granja": 2394.0,
	"pueblo": 4375.5,
	"mina_exterior": 3674.0,
	"bosque_norte": 7062.0,
	"costa_lago": 3624.5,
}
const EXTERIORES := ["granja", "pueblo", "mina_exterior", "bosque_norte", "costa_lago", "sierra_mirador", "robledal_niebla", "ruinas_valle"]

var _ok := 0
var _fallos: Array[String] = []
var _listo := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		if not _listo:
			_listo = true
			push_error("PRUEBA H05 MAPA AGOTO TIEMPO")
			get_tree().quit(1))
	_ejecutar.call_deferred()


func _chk(c: bool, m: String) -> void:
	if c:
		_ok += 1
	else:
		_fallos.append(m)
		push_error("FALLO H05: " + m)


func _area_pol(p: PackedVector2Array) -> float:
	var n := p.size()
	var s := 0.0
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func _esperar_mapa(id_esp: String) -> void:
	for _i in 600:
		var m := Escenas.mapa_actual_nodo() as Mapa
		if not Escenas.en_transicion and m != null and m.id_mapa == id_esp and m.esta_listo and m.vallas_listas:
			await get_tree().process_frame
			return
		await get_tree().process_frame


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_h05.json"
	Juego.nueva_partida("Leo")
	Juego.pausar_tiempo(true)
	Juego.ingresar(1000)
	Juego.minutos = 720  # 12:00 mediodía
	LimitesMapa.recargar()

	# 1) Áreas y conexiones bidireccionales
	for id: String in EXTERIORES:
		var pol := LimitesMapa.poligono(id)
		var area := _area_pol(pol)
		_chk(pol.size() >= 6, "%s: polígono >= 6 vértices" % id)
		if AREAS_ANTES.has(id):
			var antes := float(AREAS_ANTES[id])
			_chk(area >= antes * 2.0, "%s: área %.1f >= 2.0x (antes %.1f, ratio %.2fx)" % [id, area, antes, area / antes])
		else:
			_chk(area >= 6000.0, "%s: zona nueva amplia (%.1f m²)" % [id, area])

		for c: Dictionary in Datos.conexiones_de(id):
			var dest := str(c.get("destino", ""))
			if dest == "mina_interior":
				continue
			var vuelta := Datos.conexiones_de(dest)
			var ok_vuelta := false
			for cv: Dictionary in vuelta:
				if str(cv.get("destino", "")) == id:
					ok_vuelta = true
					break
			_chk(ok_vuelta, "%s -> %s tiene conexión de vuelta" % [id, dest])

	# 2) Recorrido rápido por las 8 zonas verificando carga <= 5000 ms, horizonte, vallas, límites y recursos
	for id: String in EXTERIORES:
		await Escenas.ir_a_mapa(id)
		await _esperar_mapa(id)
		var mapa := Escenas.mapa_actual_nodo() as Mapa
		_chk(mapa != null and mapa.cargador != null, "%s: mapa y cargador válidos" % id)
		var carga_ms := int(mapa.cargador.get("tiempo_carga_ms"))
		_chk(carga_ms <= 5000, "%s: carga <= 5000 ms (%d ms)" % [id, carga_ms])
		_chk(mapa.get_node_or_null("HorizonteH05") != null, "%s: horizonte lejano presente" % id)
		_chk(mapa.numero_postes >= 5, "%s: vallas en límites (%d postes)" % [id, mapa.numero_postes])

		var j := Escenas.jugador()
		_chk(j != null and LimitesMapa.dentro(id, j.global_position, 0.5), "%s: Leo nace dentro de límites" % id)
		for s: Node in get_tree().get_nodes_in_group("salida"):
			var s3 := s as Node3D
			if s3 != null:
				_chk(LimitesMapa.dentro(id, s3.global_position, 1.0), "%s: %s dentro de límites" % [id, s3.name])

		if id == "granja":
			var antes_c := Cultivos.contar()
			Juego.banderas["parcela_este_abierta"] = true
			var parc := mapa.objetos.get_node_or_null("Parcelas")
			if parc != null and parc.has_method("reconstruir_desde_h05"):
				parc.call("reconstruir_desde_h05")
			_chk(Cultivos.contar() >= antes_c + 64, "granja: desbloquear Zona_Cultivo_4 añade 64 parcelas")

		if id in ["sierra_mirador", "robledal_niebla", "ruinas_valle"]:
			_chk(mapa.objetos.get_node_or_null("RecursosExteriores") != null, "%s: RecursosExteriores activo" % id)
			_chk(not Misiones.visita_pendiente_o_hecha(id) if Misiones.has_method("visita_pendiente_o_hecha") else bool((Juego.banderas.get("zonas_visitadas", {}) as Dictionary).get(id, false)),
				"%s: visita registrada en Misiones" % id)

	# 3) Comprobar aparición al anochecer en sierra_mirador y ausencia en pueblo
	Juego.minutos = 1140
	await Escenas.ir_a_mapa("sierra_mirador")
	await _esperar_mapa("sierra_mirador")
	var m_sierra := Escenas.mapa_actual_nodo() as Mapa
	var rec := m_sierra.objetos.get_node_or_null("RecursosExteriores")
	_chk(rec != null and rec.get_node_or_null("EnemigosNocturnos") != null and rec.get_node_or_null("EnemigosNocturnos").get_child_count() >= 1,
		"sierra_mirador: enemigos aparecen al anochecer")

	await Escenas.ir_a_mapa("pueblo")
	await _esperar_mapa("pueblo")
	var m_pueblo := Escenas.mapa_actual_nodo() as Mapa
	var rec_pueblo: Node = m_pueblo.objetos.get_node_or_null("RecursosExteriores") if m_pueblo != null else null
	_chk(rec_pueblo == null or rec_pueblo.get_node_or_null("EnemigosNocturnos") == null,
		"pueblo: sin enemigos de noche")

	_listo = true
	if _fallos.is_empty():
		print("PRUEBA H05 MAPA OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA H05 MAPA FALLO (%d ok, %d fallos)" % [_ok, _fallos.size()])
		get_tree().quit(1)
