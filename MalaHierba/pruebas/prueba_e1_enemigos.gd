extends Node
## Prueba de E1: los 16 enemigos de la mina (12 normales + 4 jefes) cargan con modelo y animaciones, aparecen en sus
## niveles, atacan, reciben daño y mueren. Tope interno de 110 s -> quit(1).

const IDS := ["rata_mina", "murcielago", "escarabajo_roca", "rata_reina", "babosa_gruta", "sapo_ciego", "ciempies", "sapo_gigante",
	"arana_cristal", "polilla_luminosa", "golem_cuarzo", "arana_madre", "salamandra_magma", "escorpion_ceniza", "golem_magma", "gusano_magma"]
const JEFES := {5: "rata_reina", 10: "sapo_gigante", 15: "arana_madre", 20: "gusano_magma"}
const ANIMS := ["reposo", "andar", "atacar", "golpeado", "morir"]

var _fallos: Array[String] = []
var _ok: int = 0
var _terminado: bool = false


class Muneco extends Node3D:
	var recibido: float = 0.0
	func recibir_dano(c: float) -> void:
		recibido += c


func _ready() -> void:
	var arbol := get_tree()
	arbol.create_timer(108.0).timeout.connect(func() -> void:
		if not _terminado:
			push_error("PruebaE1: tiempo agotado (110 s)")
			arbol.quit(1))
	await _ejecutar()


func _comprobar(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
	else:
		_fallos.append(msg)
		push_error("FALLO E1: %s" % msg)


func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg).timeout


func _def(id: String) -> Dictionary:
	for d: Dictionary in Enemigo.cargar_definiciones():
		if str(d.get("id", "")) == id:
			return d
	return {}


func _crear(id: String, padre: Node, pos: Vector3) -> Enemigo:
	var en := Enemigo.new()
	en.configurar(_def(id))
	en.position = pos
	padre.add_child(en)
	return en


func _ejecutar() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Juego.ruta_partida = "user://partida_prueba_e1.json"
	Juego.nueva_partida("PruebaE1")
	Juego.pausar_tiempo(true)
	Juego.minutos = 600

	# 1. Datos
	print("[1] Datos: 12 enemigos + 4 jefes, niveles de la tabla y estadísticas que suben por zona")
	var defs := Enemigo.cargar_definiciones()
	_comprobar(defs.size() == 16, "enemigos.json tiene 16 entradas (%d)" % defs.size())
	var jefes_json := 0
	for id: String in IDS:
		var d := _def(id)
		_comprobar(not d.is_empty(), "%s está en enemigos.json" % id)
		_comprobar(ResourceLoader.exists(str(d.get("modelo", ""))), "%s: el .glb existe" % id)
		jefes_json += 1 if bool(d.get("jefe", false)) else 0
	_comprobar(jefes_json == 4, "hay 4 jefes (%d)" % jefes_json)
	var vida_zona := [0.0, 0.0, 0.0, 0.0]
	var cuenta_zona := [0, 0, 0, 0]
	for d: Dictionary in defs:
		if bool(d.get("jefe", false)):
			continue
		var z := clampi((int((d["niveles"] as Array)[0]) - 1) / 5, 0, 3)
		vida_zona[z] += float(d["vida"])
		cuenta_zona[z] += 1
	for z in 3:
		_comprobar(vida_zona[z] / maxf(cuenta_zona[z], 1) < vida_zona[z + 1] / maxf(cuenta_zona[z + 1], 1), "la vida media sube de la zona %d a la %d" % [z + 1, z + 2])

	# 2. Cada modelo: carga, escala, suelo, animaciones y brillo
	print("[2] Los 16 modelos: escala, origen en el suelo, animaciones y brillo")
	var mundo := Node3D.new()
	add_child(mundo)
	var i := 0
	for id: String in IDS:
		var d := _def(id)
		var en := _crear(id, mundo, Vector3(float(i) * 8.0, 0.0, 0.0))
		i += 1
		_comprobar(en.modelo != null and en.anim != null, "%s: carga el modelo con su AnimationPlayer" % id)
		if en.modelo == null:
			continue
		for a: String in ANIMS:
			_comprobar(en.tiene_animacion(a), "%s: trae la animación %s" % [id, a])
		if bool(d.get("jefe", false)):
			_comprobar(en.tiene_animacion("ataque_especial"), "%s: ataque_especial se mapea a atacar" % id)
		var caja := en._caja_de(en.modelo)
		var ext_h := maxf(caja.size.x, caja.size.z) * en.modelo.scale.x
		var ref := caja.size.y * en.modelo.scale.x if str(d.get("medida", "largo")) == "alto" else ext_h
		_comprobar(absf(ref - float(d["tamano"])) <= 0.05 * float(d["tamano"]) + 0.01, "%s: tamaño %.2f m (tabla %.2f m)" % [id, ref, float(d["tamano"])])
		var suelo := en.modelo.position.y + caja.position.y * en.modelo.scale.x
		_comprobar(absf(suelo) < 0.03, "%s: origen en el suelo (%.3f)" % [id, suelo])
		var mi := en.modelo.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var mat := mi.get_active_material(0) as BaseMaterial3D
		_comprobar(mat != null and mat.albedo_texture != null, "%s: material con textura de color" % id)
		_comprobar(en.marcador_capsula != null and not en.marcador_capsula.visible, "%s: la cápsula de marcador sigue invisible" % id)
		if d.has("emision"):
			var sm := mi.get_surface_override_material(0)
			_comprobar(sm is BaseMaterial3D and (sm as BaseMaterial3D).next_pass is ShaderMaterial and en.luz_brillo != null, "%s: material con brillo y luz" % id)
	await get_tree().process_frame

	# 3. Comportamientos con un muñeco como objetivo
	print("[3] Ataques, daño, jefes y muerte")
	var m1 := Muneco.new()
	m1.position = Vector3(0.0, 0.0, 1.0)
	var arena := Node3D.new()
	add_child(arena)
	arena.add_child(m1)
	var rata := _crear("rata_mina", arena, Vector3(0.0, 0.2, 0.0))
	rata.activar_para_prueba(true, m1)
	await _esperar(1.3)
	_comprobar(m1.recibido >= rata.dano - 0.01, "la rata ataca al objetivo (%.1f de daño)" % m1.recibido)
	rata.recibir_dano(1.0)
	_comprobar(rata.estado == Enemigo.Estado.GOLPEADO, "recibir daño pone el estado golpeado")
	var fallecidos := [0]
	rata.fallecido.connect(func(_e: Enemigo) -> void: fallecidos[0] += 1)
	rata.recibir_dano(1000.0)
	_comprobar(rata.muerto and fallecidos[0] == 1, "la rata muere y emite fallecido")
	_comprobar(is_instance_valid(rata), "al morir espera a que acabe la animación antes de quitarse")

	# Jefes: embestida (rata reina), lengua (sapo gigante), cristales (araña madre)
	var m2 := Muneco.new()
	m2.position = Vector3(0.0, 0.0, 6.0)
	arena.add_child(m2)
	var reina := _crear("rata_reina", arena, Vector3(0.0, 0.2, 0.0))
	reina.activar_para_prueba(true, m2)
	reina._cd_especial = 0.0
	await _esperar(1.9)
	_comprobar(m2.recibido >= reina.dano * 1.4 - 0.01, "la rata reina embiste y daña (%.1f)" % m2.recibido)
	reina.queue_free()

	var m3 := Muneco.new()
	m3.position = Vector3(0.0, 0.0, 4.0)
	arena.add_child(m3)
	var sapo := _crear("sapo_gigante", arena, Vector3(20.0, 0.2, 0.0))
	m3.position += sapo.position
	sapo.activar_para_prueba(true, m3)
	sapo._cd_especial = 0.0
	await _esperar(1.4)
	_comprobar(m3.recibido > 0.0, "el sapo gigante daña con la lengua a 4 m (%.1f)" % m3.recibido)
	sapo.queue_free()

	var m4 := Muneco.new()
	var madre := _crear("arana_madre", arena, Vector3(40.0, 0.2, 0.0))
	m4.position = madre.position + Vector3(0.0, 0.0, 8.0)
	arena.add_child(m4)
	madre.activar_para_prueba(true, m4)
	madre._cd_especial = 0.0
	await _esperar(0.8)
	var proyectiles := 0
	for h in arena.get_children():
		if h is Enemigo.ProyectilCristal:
			proyectiles += 1
	_comprobar(proyectiles >= 3, "la araña madre lanza cristales (%d)" % proyectiles)
	madre.queue_free()

	var m5 := Muneco.new()
	var gusano := _crear("gusano_magma", arena, Vector3(60.0, 0.2, 0.0))
	m5.position = gusano.position + Vector3(0.0, 0.0, 30.0)
	arena.add_child(m5)
	gusano.activar_para_prueba(true, m5)
	await _esperar(0.3)
	_comprobar(gusano.estado == Enemigo.Estado.HUNDIDO and gusano.pivote.position.y < -2.0, "el gusano espera hundido bajo el suelo")
	gusano.recibir_dano(50.0)
	_comprobar(is_equal_approx(gusano.vida, gusano.vida_max), "hundido es invulnerable")
	m5.position = gusano.position + Vector3(0.0, 0.0, 8.0)
	await _esperar(0.4)
	_comprobar(gusano.estado == Enemigo.Estado.EMERGER, "el gusano emerge al acercarse Leo")
	await _esperar(1.5)
	_comprobar(gusano.estado in [Enemigo.Estado.RECUPERANDO, Enemigo.Estado.PERSECUCION] and absf(gusano.pivote.position.y) < 0.01,
		"el gusano queda sobre el suelo y se recupera tras emerger")
	gusano._cd_especial = 0.0
	await _esperar(0.3)
	_comprobar(gusano.estado == Enemigo.Estado.HUNDIENDO, "el gusano se hunde entre ataques")
	await _esperar(3.8)
	_comprobar(gusano.estado in [Enemigo.Estado.EMERGER, Enemigo.Estado.RECUPERANDO, Enemigo.Estado.LIBRE, Enemigo.Estado.ATACAR]
		and gusano.pivote.position.y > -3.0, "el gusano vuelve a emerger (estado %d, y %.2f)" % [gusano.estado, gusano.pivote.position.y])
	gusano.queue_free()

	# Muerte con animación: el nodo sigue vivo mientras dura y se libera después.
	var cuervo := _crear("murcielago", arena, Vector3(80.0, 0.2, 0.0))
	cuervo.recibir_dano(1000.0)
	await _esperar(1.0)
	_comprobar(is_instance_valid(cuervo) and not cuervo.is_queued_for_deletion(), "el murciélago sigue ahí mientras dura `morir`")
	await _esperar(3.0)
	_comprobar(not is_instance_valid(cuervo) or cuervo.is_queued_for_deletion(), "el murciélago desaparece cuando acaba `morir`")
	mundo.queue_free()
	arena.queue_free()

	# 4. En la mina: qué sale en cada nivel y cómo golpea Leo
	print("[4] Niveles de la mina: enemigos de su zona y un jefe en 5, 10, 15 y 20")
	for nv: int in [1, 3, 5, 6, 8, 10, 12, 15, 16, 18, 20]:
		Juego.banderas["nivel_mina"] = nv
		await Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")
		for _k in 6:
			await get_tree().process_frame
		var mapa := Escenas.mapa_actual_nodo()
		var nm := mapa.get_node("Objetos/NivelMina") as NivelMina
		var jugador := Escenas.jugador()
		var normales := 0
		var jefes := 0
		var todos_en_nivel := true
		var jefe_en: Enemigo = null
		for h in nm.puntos_enemigos.get_children():
			if h is Enemigo:
				var en := h as Enemigo
				todos_en_nivel = todos_en_nivel and nv >= en.rango_niveles.x and nv <= en.rango_niveles.y
				if en.es_jefe:
					jefes += 1
					jefe_en = en
				else:
					normales += 1
				_comprobar(en.modelo != null, "nivel %d: %s con modelo" % [nv, en.id_enemigo])
		_comprobar(todos_en_nivel, "nivel %d: todos los enemigos son de su zona" % nv)
		_comprobar(normales >= 2, "nivel %d: enemigos normales (%d)" % [nv, normales])
		_comprobar(jefes == (1 if JEFES.has(nv) else 0), "nivel %d: jefes %d" % [nv, jefes])
		if JEFES.has(nv) and jefe_en != null:
			_comprobar(jefe_en.id_enemigo == JEFES[nv], "nivel %d: el jefe es %s" % [nv, JEFES[nv]])
			_comprobar(jefe_en.global_position.distance_to(jugador.global_position) >= 8.0, "nivel %d: el jefe sale lejos de la llegada" % nv)
		if nv == 8:
			var en8: Enemigo = null
			for h in nm.puntos_enemigos.get_children():
				if h is Enemigo and not (h as Enemigo).es_jefe:
					en8 = h as Enemigo
					break
			en8.global_position = jugador.global_position + Vector3(0.9, 0.0, 0.0)
			var antes := en8.vida
			var pico_ok := en8.usar("pico", jugador.global_position + Vector3(0.6, 0.0, 0.0), jugador)
			_comprobar(pico_ok and en8.vida < antes, "nivel 8: el pico de Leo hiere al enemigo (%.0f -> %.0f)" % [antes, en8.vida])
			_comprobar(not en8.usar("hoz", jugador.global_position + Vector3(0.6, 0.0, 0.0), jugador), "nivel 8: la hoz no hiere")

	_terminado = true
	if _fallos.is_empty():
		print("PRUEBA E1 ENEMIGOS OK (%d comprobaciones)" % _ok)
		get_tree().quit(0)
	else:
		print("PRUEBA E1 ENEMIGOS FALLO (%d errores, %d ok)" % [_fallos.size(), _ok])
		get_tree().quit(1)
