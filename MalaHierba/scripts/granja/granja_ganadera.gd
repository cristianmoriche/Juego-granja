class_name GranjaGanadera
extends Node3D
## Gallinero y colmenas en la finca de Leo (H12).
## Usa los modelos PBR realistas de Claude (`gallinero_roto/reparado.glb`, `colmena_corcho.glb`, `colmena_cuadros.glb`,
## `huevo_pardo.glb`, `huevo_blanco.glb`, `tarro_miel.glb`) y los integra sobre la pradera libre junto a la casa.

const RUTA_ROTO := "res://assets/granja/gallinero_roto.glb"
const RUTA_REPARADO := "res://assets/granja/gallinero_reparado.glb"
const RUTA_CORCHO := "res://assets/granja/colmena_corcho.glb"
const RUTA_CUADROS := "res://assets/granja/colmena_cuadros.glb"
const RUTA_HUEVO_P := "res://assets/granja/huevo_pardo.glb"
const RUTA_HUEVO_B := "res://assets/granja/huevo_blanco.glb"
const RUTA_MIEL := "res://assets/granja/tarro_miel.glb"

var _mapa: Mapa = null
var _raiz_gallinero: Node3D = null
var _modelo_gallinero: Node3D = null
var _tapa_nidales: Node3D = null
var _trampilla: Node3D = null
var _nidos_huevos: Array[Node3D] = []
var _colmena_nodos: Array[Dictionary] = []
var _abejas: Array[Dictionary] = []
var _t_anim: float = 0.0
var _t_audio_granja: float = 0.0


static func preparar(mapa: Mapa, recursos_ext: Node3D) -> GranjaGanadera:
	var gg := GranjaGanadera.new()
	gg.name = "GranjaGanadera"
	gg._mapa = mapa
	recursos_ext.add_child(gg)
	gg._construir()
	return gg


func _suelo_y(x: float, z: float) -> float:
	if _mapa != null and _mapa.has_method("_columna_suelo"):
		var col: Dictionary = _mapa.call("_columna_suelo", x, z)
		var y := float(col.get("suelo", NAN))
		if not is_nan(y):
			return y
	return 0.4


func _origen_libre() -> Vector3:
	var mk_sp: Marker3D = _mapa.marcador("Spawn_Protagonista") if _mapa != null else null
	var base := mk_sp.global_position if mk_sp != null else Vector3.ZERO
	var zonas: Array[Vector3] = []
	for znom in ["Zona_Cultivo_1", "Zona_Cultivo_2", "Zona_Cultivo_3", "Zona_Cultivo_4", "Zona_Cultivo_5"]:
		var zm: Marker3D = _mapa.marcador(znom) if _mapa != null else null
		if zm != null:
			zonas.append(zm.global_position)
	# Prueba ubicaciones limpias cerca de la casa evitando parcelas
	for off: Vector2 in [Vector2(-12.5, -5.5), Vector2(12.5, -6.5), Vector2(-13.5, 4.5), Vector2(14.5, 5.5)]:
		var px := base.x + off.x
		var pz := base.z + off.y
		var libre := true
		for zp in zonas:
			if Vector2(px - zp.x, pz - zp.z).length() < 7.2:
				libre = false
				break
		if libre:
			return Vector3(px, _suelo_y(px, pz), pz)
	return Vector3(base.x - 12.5, _suelo_y(base.x - 12.5, base.z - 5.5), base.z - 5.5)


func _construir() -> void:
	add_to_group("usable")
	var pos := _origen_libre()
	global_position = pos
	_raiz_gallinero = Node3D.new()
	_raiz_gallinero.name = "GallineroFinca"
	add_child(_raiz_gallinero)
	_reconstruir_gallinero()
	_construir_colmenas()
	if not Juego.ganado_cambiado.is_connected(_al_cambiar_ganado):
		Juego.ganado_cambiado.connect(_al_cambiar_ganado)
	if not Juego.hora_cambiada.is_connected(_al_cambiar_hora):
		Juego.hora_cambiada.connect(_al_cambiar_hora)


func _reconstruir_gallinero() -> void:
	for h in _raiz_gallinero.get_children():
		h.queue_free()
	_nidos_huevos.clear()
	_modelo_gallinero = null
	_tapa_nidales = null
	_trampilla = null

	var g := Juego.ganado_estado()["gallinero"] as Dictionary
	var reparado := bool(g.get("reparado", false))
	var ruta := RUTA_REPARADO if reparado else RUTA_ROTO

	# Colisión exacta de gallinero (LEEME.md: cuerpo + caja de nidales)
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	var s1 := CollisionShape3D.new()
	var b1 := BoxShape3D.new()
	b1.size = Vector3(2.10, 1.95, 1.50)
	s1.shape = b1
	s1.position = Vector3(0.0, 0.975, 0.0)
	cuerpo.add_child(s1)
	var s2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(0.50, 0.85, 1.14)
	s2.shape = b2
	s2.position = Vector3(1.24, 0.80, 0.0)
	cuerpo.add_child(s2)
	_raiz_gallinero.add_child(cuerpo)

	if ResourceLoader.exists(ruta):
		var ps := load(ruta) as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			if inst != null:
				_raiz_gallinero.add_child(inst)
				_modelo_gallinero = inst
				_tapa_nidales = inst.find_child("TapaNidales", true, false) as Node3D
				_trampilla = inst.find_child("Trampilla", true, false) as Node3D

	var pto_puerta := Interactuable.new()
	pto_puerta.name = "InteraccionGallinero"
	pto_puerta.position = Vector3(0.08, 0.0, 1.05)
	pto_puerta.radio = 2.0
	pto_puerta.altura_marca = 1.95
	if not reparado:
		pto_puerta.verbo = "Reparar"
		pto_puerta.nombre_objeto = "el gallinero (8×Madera + 120 €)"
	else:
		pto_puerta.verbo = "Cuidar"
		pto_puerta.nombre_objeto = "el gallinero (%d/6 gallinas)" % int(g.get("gallinas", 0))
	_raiz_gallinero.add_child(pto_puerta)
	pto_puerta.usado.connect(func(_j: Node3D) -> void: _menu_gallinero())

	if reparado:
		var pto_h := Interactuable.new()
		pto_h.name = "InteraccionNidales"
		pto_h.position = Vector3(1.85, 0.0, 0.0)
		pto_h.radio = 1.65
		pto_h.altura_marca = 1.35
		pto_h.verbo = "Revisar"
		pto_h.nombre_objeto = "los nidales del gallinero"
		_raiz_gallinero.add_child(pto_h)
		pto_h.usado.connect(func(_j: Node3D) -> void: _recoger_huevos_con_tapa())

	_sincronizar_visual_gallinero()


func _sincronizar_visual_gallinero() -> void:
	for n in _nidos_huevos:
		if is_instance_valid(n):
			n.queue_free()
	_nidos_huevos.clear()

	var g := Juego.ganado_estado()["gallinero"] as Dictionary
	var reparado := bool(g.get("reparado", false))
	if not reparado:
		return

	if _trampilla != null and is_instance_valid(_trampilla):
		var de_noche := Juego.minutos >= 1140 or Juego.minutos < 420
		_trampilla.rotation.x = 0.0 if de_noche else -0.9

	var huevos := g.get("huevos", []) as Array
	if _tapa_nidales != null and is_instance_valid(_tapa_nidales):
		_tapa_nidales.rotation.z = 0.48 if not huevos.is_empty() else 0.0

	var p_nidos := [
		Vector3(1.215, 0.76, 0.38),
		Vector3(1.215, 0.76, 0.0),
		Vector3(1.215, 0.76, -0.38),
	]
	for i in mini(huevos.size(), 3):
		var ruta_h := RUTA_HUEVO_B if str(huevos[i]) == "huevo_blanco" else RUTA_HUEVO_P
		if not ResourceLoader.exists(ruta_h):
			continue
		var psh := load(ruta_h) as PackedScene
		if psh == null:
			continue
		var eh := psh.instantiate() as Node3D
		if eh != null:
			eh.position = p_nidos[i]
			eh.rotation_degrees = Vector3(14.0, 22.0 * float(i), 78.0)
			_raiz_gallinero.add_child(eh)
			_nidos_huevos.append(eh)


func _construir_colmenas() -> void:
	for d: Dictionary in _colmena_nodos:
		var nd := d.get("nodo") as Node3D
		if nd != null and is_instance_valid(nd):
			nd.queue_free()
	_colmena_nodos.clear()
	_abejas.clear()

	var cols := Juego.ganado_estado()["colmenas"] as Array
	var offsets := [Vector3(3.65, 0.0, 0.2), Vector3(4.95, 0.0, 0.65), Vector3(6.15, 0.0, 0.25)]
	for i in mini(cols.size(), 3):
		var c := cols[i] as Dictionary
		var nodo := Node3D.new()
		nodo.name = "Colmena_%d" % (i + 1)
		var off: Vector3 = offsets[i]
		nodo.position = Vector3(off.x, _suelo_y(global_position.x + off.x, global_position.z + off.z) - global_position.y, off.z)
		add_child(nodo)

		var desb := bool(c.get("desbloqueada", false))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.62, 0.95, 0.56)
		sh.shape = bx
		sh.position = Vector3(0.0, 0.47, 0.0)
		body.add_child(sh)
		nodo.add_child(body)

		var es_corcho := str(c.get("tipo", "cuadros")) == "corcho"
		var ruta := RUTA_CORCHO if es_corcho else RUTA_CUADROS
		var vis: Node3D = null
		if desb and ResourceLoader.exists(ruta):
			var ps := load(ruta) as PackedScene
			if ps != null:
				vis = ps.instantiate() as Node3D
				if vis != null:
					nodo.add_child(vis)
		elif not desb:
			# Poste de madera marcando sitio para colmena ampliable
			AyudasL4b.caja(nodo, Vector3(0.52, 0.14, 0.52), Vector3(0.0, 0.07, 0.0), Color(0.42, 0.34, 0.24))
			AyudasL4b.caja(nodo, Vector3(0.10, 0.65, 0.10), Vector3(0.0, 0.32, 0.0), Color(0.36, 0.24, 0.14))

		var pto := Interactuable.new()
		pto.position = Vector3(0.0, 0.0, 0.85)
		pto.radio = 1.65
		pto.altura_marca = 1.15
		var idx := i
		if not desb:
			pto.verbo = "Construir"
			pto.nombre_objeto = "la colmena %d (6×Madera + 90 €)" % (i + 1)
			pto.usado.connect(func(_j: Node3D) -> void: _construir_o_cosechar_colmena(idx))
		else:
			var miel := int(c.get("miel", 0))
			pto.verbo = "Recoger" if miel > 0 else "Revisar"
			pto.nombre_objeto = ("miel de colmena %d (%d tarro)" % [i + 1, miel]) if miel > 0 else ("la colmena %d" % (i + 1))
			pto.usado.connect(func(_j: Node3D) -> void: _construir_o_cosechar_colmena(idx))
		nodo.add_child(pto)

		var tarro_vis: Node3D = null
		if desb and int(c.get("miel", 0)) > 0 and ResourceLoader.exists(RUTA_MIEL):
			var psm := load(RUTA_MIEL) as PackedScene
			if psm != null:
				tarro_vis = psm.instantiate() as Node3D
				if tarro_vis != null:
					tarro_vis.position = Vector3(0.0, 0.86 if not es_corcho else 1.06, 0.0)
					tarro_vis.scale = Vector3.ONE * 1.35
					nodo.add_child(tarro_vis)

		# Pequeñas abejas orbitando frente a la piquera (salvo en invierno)
		if desb and Juego.estacion != 3:
			for k in 3:
				var ab := MeshInstance3D.new()
				var sph := SphereMesh.new()
				sph.radius = 0.016
				sph.height = 0.024
				ab.mesh = sph
				var ma := StandardMaterial3D.new()
				ma.albedo_color = Color(0.95, 0.72, 0.14)
				ma.roughness = 0.5
				ab.material_override = ma
				nodo.add_child(ab)
				_abejas.append({"nodo": ab, "base": Vector3(-0.04, 0.34, 0.34), "fase": float(i * 3 + k) * 1.3})

		_colmena_nodos.append({"nodo": nodo, "vis": vis, "tarro": tarro_vis, "pto": pto})


func _process(delta: float) -> void:
	_t_anim += delta
	for item: Dictionary in _abejas:
		var nd := item.get("nodo") as Node3D
		if nd == null or not is_instance_valid(nd):
			continue
		var visible_ab := Juego.estacion != 3
		nd.visible = visible_ab
		if not visible_ab:
			continue
		var base: Vector3 = item["base"]
		var fase: float = float(item["fase"]) + _t_anim * 4.2
		nd.position = base + Vector3(sin(fase) * 0.16, cos(fase * 1.6) * 0.07, cos(fase * 0.9) * 0.14)

	_t_audio_granja -= delta
	if _t_audio_granja <= 0.0:
		_t_audio_granja = 9.5
		var j := Escenas.jugador()
		if j != null and j.global_position.distance_squared_to(global_position) < 90.0:
			var g := Juego.ganado_estado()["gallinero"] as Dictionary
			if bool(g.get("reparado", false)) and int(g.get("gallinas", 0)) > 0:
				Audio.reproducir_posicional("gallinas_cacareo", _raiz_gallinero.global_position, self)
			elif Juego.estacion != 3:
				Audio.reproducir_posicional("abejas_zumbido", global_position + Vector3(4.2, 0.6, 0.4), self)


func _al_cambiar_ganado() -> void:
	_reconstruir_gallinero()
	_construir_colmenas()


func _al_cambiar_hora(_m: int) -> void:
	_sincronizar_visual_gallinero()


func usar(id: String, punto: Vector3, _jugador: Node3D) -> bool:
	var g := Juego.ganado_estado()["gallinero"] as Dictionary
	if id == "regadera" and bool(g.get("reparado", false)) and punto.distance_to(_raiz_gallinero.global_position) <= 4.5:
		if Juego.dar_agua_gallinero():
			Interfaz.mensaje("Bebedero del gallinero lleno de agua fresca.")
		else:
			Interfaz.mensaje("El bebedero ya tiene agua para hoy.")
		return true
	if id == "ahumador":
		for i in _colmena_nodos.size():
			var d := _colmena_nodos[i]
			var nd := d.get("nodo") as Node3D
			if nd != null and punto.distance_to(nd.global_position) <= 2.5:
				_construir_o_cosechar_colmena(i)
				return true
	return false


func _menu_gallinero() -> void:
	var g := Juego.ganado_estado()["gallinero"] as Dictionary
	if not bool(g.get("reparado", false)):
		if Juego.reparar_gallinero():
			Interfaz.mensaje("¡Gallinero reparado! Ya viven 2 gallinas dentro.")
		else:
			Audio.reproducir("ui_error")
			Interfaz.mensaje("Necesitas 8 × Madera y 120 € para reparar el gallinero.")
		return

	var huevos := (g.get("huevos", []) as Array).size()
	var n_gallinas := int(g.get("gallinas", 0))
	var opc := [
		"Alimentar (1× Pienso, 1× Patata o 2× Fibra)" if not bool(g.get("comida", false)) else "Comedero ya lleno hoy ✓",
		"Dar agua al bebedero" if not bool(g.get("agua", false)) else "Bebedero ya lleno hoy ✓",
		"Recoger huevos (%d)" % huevos,
		"Añadir gallina (120 € · %d/6)" % n_gallinas,
		"Cerrar",
	]
	Interfaz.preguntar("Gallinero (%d/6 gallinas dentro)" % n_gallinas, opc, _al_elegir_gallinero.bind(n_gallinas))


func _al_elegir_gallinero(idx: int, n_gallinas: int) -> void:
	match idx:
		0:
			if Juego.alimentar_gallinero():
				Interfaz.mensaje("Gallinas alimentadas para hoy.")
			else:
				Interfaz.mensaje("No hace falta o te falta pienso/patata/fibra.")
		1:
			if Juego.dar_agua_gallinero():
				Interfaz.mensaje("Bebedero lleno con agua fresca.")
		2:
			_recoger_huevos_con_tapa()
		3:
			if Juego.comprar_gallina():
				Interfaz.mensaje("Nueva gallina en el gallinero (%d/6)." % (n_gallinas + 1))
			else:
				Interfaz.mensaje("Necesitas 120 € y sitio (máx. 6 gallinas).")


func _recoger_huevos_con_tapa() -> void:
	var n := Juego.recoger_huevos()
	if n > 0:
		Interfaz.mensaje("Recoges %d huevo(s) del nidal." % n, "huevo_pardo")
	else:
		Interfaz.mensaje("No hay huevos nuevos en los nidales todavía. Cuídalas y vuelve mañana.")


func _construir_o_cosechar_colmena(indice: int) -> void:
	var cols := Juego.ganado_estado()["colmenas"] as Array
	if indice < 0 or indice >= cols.size():
		return
	var c := cols[indice] as Dictionary
	if not bool(c.get("desbloqueada", false)):
		if Juego.desbloquear_colmena(indice):
			Interfaz.mensaje("Nueva colmena instalada en la pradera.")
		else:
			Audio.reproducir("ui_error")
			Interfaz.mensaje("Necesitas 6 × Madera y 90 € para montar esta colmena.")
		return
	if int(c.get("miel", 0)) <= 0:
		var aviso := "Las abejas hibernan en invierno." if Juego.estacion == 3 else "Aún están llenando los panales (%d/3). Planta flores cerca para acelerar." % int(c.get("progreso", 0))
		Interfaz.mensaje(aviso)
		return
	var res := Juego.cosechar_colmena(indice)
	if bool(res.get("ok", false)) and not bool(res.get("picadura", false)):
		Interfaz.mensaje("Cosechas %d tarro de miel del valle." % int(res.get("miel", 1)), "tarro_miel")
