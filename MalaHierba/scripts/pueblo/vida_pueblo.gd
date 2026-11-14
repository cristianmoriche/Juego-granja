class_name VidaPueblo
extends Node3D
## Decoración y puestos dinámicos de la plaza de Villaverde según:
## 1) Las dos festividades del año («feria_siembra» el 14 de primavera y «fiesta_cosecha» el 18 de otoño).
## 2) La deuda de la finca pagada por Leo (tramo 1 >= 1500 €, tramo 2 >= 3000 €, tramo 3 == 5000 € / saldada).

const MADERA_OSCURA := Color(0.36, 0.24, 0.14)
const MADERA_CLARA := Color(0.58, 0.41, 0.25)
const TIERRA_COLOR := Color(0.24, 0.17, 0.12)
const HOJA_VERDE := Color(0.28, 0.48, 0.24)
const HOJA_CLARA := Color(0.38, 0.58, 0.30)

var puesto_panaderia: Interactuable = null
var mesa_festiva: Interactuable = null
var _raiz_decoracion: Node3D = null


func _ready() -> void:
	Juego.evento_cambiado.connect(actualizar)
	Juego.deuda_cambiada.connect(func(_d: int) -> void: actualizar())
	Juego.dia_nuevo.connect(actualizar)
	Juego.estacion_cambiada.connect(actualizar)
	Juego.partida_cambiada.connect(actualizar)


func actualizar() -> void:
	if not is_inside_tree():
		return
	if _raiz_decoracion != null and is_instance_valid(_raiz_decoracion):
		remove_child(_raiz_decoracion)
		_raiz_decoracion.queue_free()
	_raiz_decoracion = Node3D.new()
	_raiz_decoracion.name = "DecoracionPlaza"
	add_child(_raiz_decoracion)
	puesto_panaderia = null
	mesa_festiva = null

	var tramo := Juego.tramo_deuda()
	var fiesta := Juego.festividad_hoy()

	# --- Cambios visibles progresivos por deuda pagada ---
	if tramo >= 1:
		_construir_jardineras_y_faroles()
	if tramo >= 2:
		_construir_panaderia()
		_construir_terraza_taberna()
	if tramo >= 3 and fiesta.is_empty():
		_construir_arco_floral("¡Villaverde sigue vivo!", [Color(0.84, 0.32, 0.26), Color(0.92, 0.78, 0.30), Color(0.34, 0.56, 0.34), Color(0.93, 0.90, 0.80)], false)
		_construir_guirnalda_plaza([Color(0.84, 0.32, 0.26), Color(0.92, 0.78, 0.30), Color(0.34, 0.56, 0.34), Color(0.93, 0.90, 0.80)], false)
		_construir_corona_pozo([Color(0.88, 0.36, 0.30), Color(0.95, 0.84, 0.36), Color(0.96, 0.94, 0.88)])

	# --- Decoración de festividades (primavera y otoño) ---
	if fiesta == "feria_siembra":
		_construir_festividad_primavera()
	elif fiesta == "fiesta_cosecha":
		_construir_festividad_otono()


func _orientar_horizontal(n: Node3D, objetivo: Vector3) -> void:
	var p := n.global_position
	var dir := Vector3(objetivo.x - p.x, 0.0, objetivo.z - p.z)
	if dir.length_squared() > 0.001:
		n.look_at(Vector3(objetivo.x, p.y, objetivo.z), Vector3.UP, true)


func _texto_cartel(padre: Node3D, texto: String, pos: Vector3, rot_y: float = 0.0, color: Color = Color(0.24, 0.14, 0.07)) -> void:
	var lbl := Label3D.new()
	lbl.text = texto
	lbl.font_size = 38
	lbl.pixel_size = 0.0042
	lbl.modulate = color
	lbl.outline_modulate = Color(0.14, 0.08, 0.04)
	lbl.outline_size = 5
	lbl.position = pos
	lbl.rotation.y = rot_y
	padre.add_child(lbl)


func _suelo_en(x: float, z: float) -> Vector3:
	var s := AyudasL4b.suelo(self, Vector3(x, 0.5, z), 4.0, 10.0)
	return s if s != Vector3.INF else Vector3(x, 0.0, z)


func _mat(color: Color, rugosidad: float = 0.88, emision: Color = Color.BLACK, fuerza_emision: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rugosidad
	if fuerza_emision > 0.0:
		m.emission_enabled = true
		m.emission = emision
		m.emission_energy_multiplier = fuerza_emision
	return m


func _malla(padre: Node3D, forma: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, colision: bool = false, tam_col: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = forma
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	padre.add_child(mi)
	if colision and tam_col != Vector3.ZERO:
		var cuerpo := StaticBody3D.new()
		cuerpo.collision_layer = AyudasL4b.CAPA_MUNDO
		cuerpo.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = tam_col
		cs.shape = bs
		cuerpo.add_child(cs)
		cuerpo.position = pos
		cuerpo.rotation = rot
		padre.add_child(cuerpo)
	return mi


func _caja(padre: Node3D, tam: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, colision: bool = false, rugosidad: float = 0.88) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = tam
	return _malla(padre, bm, pos, _mat(color, rugosidad), rot, colision, tam if colision else Vector3.ZERO)


func _cilindro(padre: Node3D, radio_sup: float, radio_inf: float, alto: float, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, segs: int = 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radio_sup
	cm.bottom_radius = radio_inf
	cm.height = alto
	cm.radial_segments = segs
	return _malla(padre, cm, pos, _mat(color), rot)


func _esfera(padre: Node3D, radio: float, pos: Vector3, color: Color, escala: Vector3 = Vector3.ONE, emision: float = 0.0) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = radio
	sm.height = radio * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var mi := _malla(padre, sm, pos, _mat(color, 0.78 if emision <= 0.0 else 0.4, color, emision))
	mi.scale = escala
	return mi


# --- Tramo deuda >= 1: Jardineras con flores y farolillos ------------------------------------------------

func _construir_jardineras_y_faroles() -> void:
	var puntos_jardin: Array = [
		[Vector2(-5.5, -0.5), 0.15, [Color(0.86, 0.30, 0.28), Color(0.95, 0.80, 0.32)]],
		[Vector2(5.5, -0.3), -0.12, [Color(0.92, 0.48, 0.56), Color(0.96, 0.92, 0.78)]],
		[Vector2(-2.9, -5.8), 0.0, [Color(0.95, 0.82, 0.32), Color(0.84, 0.36, 0.28)]],
		[Vector2(2.9, -5.8), 0.0, [Color(0.84, 0.32, 0.44), Color(0.95, 0.86, 0.52)]],
	]
	for item: Array in puntos_jardin:
		var v: Vector2 = item[0]
		_crear_jardinera(_suelo_en(v.x, v.y), float(item[1]), item[2] as Array)

	for pf: Vector2 in [Vector2(-5.2, -5.8), Vector2(5.2, -5.8)]:
		_crear_farol_pie(_suelo_en(pf.x, pf.y))


func _crear_jardinera(pos: Vector3, giro_y: float, colores_flor: Array) -> void:
	var n := Node3D.new()
	n.name = "Jardinera"
	_raiz_decoracion.add_child(n)
	n.global_position = pos
	n.rotation.y = giro_y
	_caja(n, Vector3(1.25, 0.40, 0.52), Vector3(0, 0.20, 0), MADERA_OSCURA, Vector3.ZERO, true)
	_caja(n, Vector3(1.32, 0.07, 0.58), Vector3(0, 0.41, 0), MADERA_CLARA)
	_caja(n, Vector3(1.16, 0.06, 0.44), Vector3(0, 0.40, 0), TIERRA_COLOR)
	for i in 4:
		var ox := -0.40 + float(i) * 0.26
		var oz := 0.04 if i % 2 == 0 else -0.05
		_esfera(n, 0.14, Vector3(ox, 0.50, oz), HOJA_VERDE if i % 2 == 0 else HOJA_CLARA, Vector3(1.15, 0.85, 1.05))
		var cf: Color = colores_flor[i % colores_flor.size()] as Color
		_esfera(n, 0.055, Vector3(ox - 0.04, 0.61, oz + 0.03), cf)
		_esfera(n, 0.048, Vector3(ox + 0.05, 0.59, oz - 0.03), cf)


func _crear_farol_pie(pos: Vector3) -> void:
	var n := Node3D.new()
	_raiz_decoracion.add_child(n)
	n.global_position = pos
	_cilindro(n, 0.06, 0.08, 2.35, Vector3(0, 1.175, 0), MADERA_OSCURA)
	_caja(n, Vector3(0.45, 0.08, 0.08), Vector3(0.18, 2.26, 0), MADERA_OSCURA)
	_caja(n, Vector3(0.22, 0.26, 0.22), Vector3(0.36, 2.08, 0), Color(0.98, 0.82, 0.48), Vector3.ZERO, false, 0.3)
	_esfera(n, 0.08, Vector3(0.36, 2.08, 0), Color(1.0, 0.86, 0.48), Vector3.ONE, 1.4)


# --- Tramo deuda >= 2: Horno de Villaverde (Panadería) y Terraza de Taberna ---------------------------

func _construir_panaderia() -> void:
	var base := _suelo_en(5.4, -2.2)
	var raiz := Node3D.new()
	raiz.name = "PuestoPanaderia"
	_raiz_decoracion.add_child(raiz)
	raiz.global_position = base
	_orientar_horizontal(raiz, _suelo_en(0.0, 0.0))

	# Mostrador y falda de lona cálida.
	_caja(raiz, Vector3(1.96, 0.88, 0.86), Vector3(0, 0.44, 0), MADERA_OSCURA, Vector3.ZERO, true)
	_caja(raiz, Vector3(1.86, 0.62, 0.89), Vector3(0, 0.40, 0), Color(0.82, 0.68, 0.50))
	_caja(raiz, Vector3(2.10, 0.08, 0.98), Vector3(0, 0.90, 0), MADERA_CLARA)

	# Postes y toldo rayado crema y terracota.
	for sx: float in [-0.92, 0.92]:
		for sz: float in [-0.38, 0.38]:
			_cilindro(raiz, 0.055, 0.06, 2.38, Vector3(sx, 1.19, sz), MADERA_OSCURA)
	for f in 5:
		var color_faja := Color(0.74, 0.32, 0.22) if f % 2 == 0 else Color(0.88, 0.82, 0.70)
		_caja(raiz, Vector3(0.45, 0.07, 1.32), Vector3(-0.90 + float(f) * 0.45, 2.42, 0.04), color_faja, Vector3(0.18, 0, 0))
	_caja(raiz, Vector3(1.78, 0.28, 0.06), Vector3(0, 2.12, 0.40), Color(0.32, 0.20, 0.12))
	_texto_cartel(raiz, "HORNO DE VILLAVERDE", Vector3(0, 2.12, 0.44), 0.0, Color(0.95, 0.88, 0.72))

	# Hogazas doradas, cestas y tarros de miel encima del mostrador.
	var pan_colores: Array[Color] = [Color(0.78, 0.54, 0.26), Color(0.82, 0.60, 0.30), Color(0.72, 0.48, 0.22)]
	for i in 4:
		var px := -0.62 + float(i) * 0.34
		_esfera(raiz, 0.13, Vector3(px, 0.99, 0.12 if i % 2 == 0 else -0.08), pan_colores[i % pan_colores.size()], Vector3(1.25, 0.62, 0.95))
	# Cesta con barras y tarros.
	_caja(raiz, Vector3(0.46, 0.14, 0.36), Vector3(0.62, 1.00, 0.04), Color(0.68, 0.52, 0.30))
	for j in 3:
		_cilindro(raiz, 0.055, 0.055, 0.16, Vector3(0.52 + float(j) * 0.11, 1.10, -0.22), Color(0.88, 0.66, 0.22))
		_cilindro(raiz, 0.058, 0.058, 0.03, Vector3(0.52 + float(j) * 0.11, 1.19, -0.22), Color(0.76, 0.24, 0.20))

	var pto := Interactuable.new()
	pto.name = "ComercioPanaderia"
	pto.verbo = "Comprar en"
	pto.nombre_objeto = "el Horno de Villaverde"
	pto.mostrar_nombre = true
	pto.radio = 1.9
	pto.altura_marca = 2.1
	pto.position = Vector3(0, 0.1, 0.78)
	pto.usado.connect(func(_j: Node3D) -> void: Interfaz.abrir_tienda("panaderia"))
	raiz.add_child(pto)
	puesto_panaderia = pto


func _construir_terraza_taberna() -> void:
	for coord: Vector2 in [Vector2(1.0, -7.2), Vector2(7.4, -6.8)]:
		var n := Node3D.new()
		_raiz_decoracion.add_child(n)
		n.global_position = _suelo_en(coord.x, coord.y)
		_cilindro(n, 0.07, 0.09, 0.72, Vector3(0, 0.36, 0), MADERA_OSCURA)
		_cilindro(n, 0.56, 0.56, 0.07, Vector3(0, 0.74, 0), MADERA_CLARA)
		_caja(n, Vector3(0.55, 0.74, 0.55), Vector3(0, 0.38, 0), MADERA_OSCURA, Vector3.ZERO, true).visible = false
		_cilindro(n, 0.07, 0.08, 0.16, Vector3(-0.14, 0.85, 0.08), Color(0.68, 0.38, 0.22))
		_cilindro(n, 0.06, 0.07, 0.14, Vector3(0.16, 0.84, -0.10), Color(0.68, 0.38, 0.22))
		for ang: float in [-0.85, 0.85]:
			var bx := sin(ang) * 0.78
			var bz := cos(ang) * 0.78
			_cilindro(n, 0.05, 0.06, 0.44, Vector3(bx, 0.22, bz), MADERA_OSCURA)
			_cilindro(n, 0.22, 0.22, 0.06, Vector3(bx, 0.45, bz), MADERA_CLARA)


# --- Tramo deuda 3 y Festividades: Arcos, guirnaldas de banderines, mesas y puestos -------------------

func _construir_festividad_primavera() -> void:
	var colores: Array = [
		Color(0.44, 0.68, 0.38),
		Color(0.94, 0.90, 0.76),
		Color(0.88, 0.68, 0.30),
		Color(0.46, 0.66, 0.84),
		Color(0.88, 0.50, 0.56),
	]
	_construir_arco_floral("Feria de la Siembra", colores, false)
	_construir_guirnalda_plaza(colores, false)
	_construir_corona_pozo([Color(0.92, 0.48, 0.54), Color(0.95, 0.86, 0.38), Color(0.96, 0.94, 0.88), Color(0.54, 0.72, 0.90)])
	_construir_mesa_festiva(Vector2(-3.5, 1.3), Color(0.92, 0.90, 0.82), Color(0.42, 0.64, 0.38), "siembra")
	_construir_mesa_festiva(Vector2(3.5, 1.3), Color(0.92, 0.90, 0.82), Color(0.42, 0.64, 0.38), "siembra")
	_construir_puesto_festivo(
		Vector2(-5.8, 0.6),
		Color(0.36, 0.58, 0.34),
		Color(0.90, 0.85, 0.72),
		"Feria de la Siembra",
		"Brindar en",
		"la mesa de la Feria de la Siembra",
		"Celebras la Feria de la Siembra con un zumo de hierbaluisa y pan dulce del valle. (+10 de energía)",
		"siembra"
	)


func _construir_festividad_otono() -> void:
	var colores: Array = [
		Color(0.86, 0.44, 0.16),
		Color(0.92, 0.68, 0.22),
		Color(0.68, 0.22, 0.20),
		Color(0.92, 0.84, 0.68),
		Color(0.76, 0.38, 0.18),
	]
	_construir_arco_floral("Fiesta de la Cosecha", colores, true)
	_construir_guirnalda_plaza(colores, true)
	_construir_corona_pozo([Color(0.88, 0.44, 0.16), Color(0.92, 0.72, 0.24), Color(0.70, 0.24, 0.20)])
	_construir_mesa_festiva(Vector2(-3.5, 1.3), Color(0.84, 0.66, 0.42), Color(0.68, 0.26, 0.18), "cosecha")
	_construir_mesa_festiva(Vector2(3.5, 1.3), Color(0.84, 0.66, 0.42), Color(0.68, 0.26, 0.18), "cosecha")
	for pc: Vector2 in [Vector2(-2.2, -2.0), Vector2(2.2, -2.0), Vector2(0.0, 2.5)]:
		var sp := _suelo_en(pc.x, pc.y)
		var grp := Node3D.new()
		_raiz_decoracion.add_child(grp)
		grp.global_position = sp
		_crear_calabaza(grp, Vector3(-0.22, 0.0, 0.0), 0.24, Color(0.88, 0.44, 0.14))
		_crear_calabaza(grp, Vector3(0.24, 0.0, 0.12), 0.19, Color(0.92, 0.56, 0.18))
		_crear_calabaza(grp, Vector3(0.0, 0.0, -0.22), 0.16, Color(0.32, 0.50, 0.24))
	_construir_puesto_festivo(
		Vector2(-5.8, 0.6),
		Color(0.72, 0.28, 0.18),
		Color(0.90, 0.76, 0.46),
		"Fiesta de la Cosecha",
		"Brindar en",
		"el puesto de la Fiesta de la Cosecha",
		"Pruebas un vaso de mosto tibio y boniato asado entre risas del pueblo. (+10 de energía)",
		"cosecha"
	)


func _crear_calabaza(padre: Node3D, pos: Vector3, radio: float, color: Color) -> void:
	_esfera(padre, radio, pos + Vector3(0, radio * 0.78, 0), color, Vector3(1.18, 0.78, 1.18))
	_cilindro(padre, radio * 0.12, radio * 0.18, radio * 0.45, pos + Vector3(0, radio * 1.50, 0), Color(0.30, 0.42, 0.18))


func _construir_arco_floral(titulo: String, colores: Array, con_farol: bool) -> void:
	var n := Node3D.new()
	n.name = "ArcoPlaza"
	_raiz_decoracion.add_child(n)
	n.global_position = _suelo_en(0.0, -4.9)
	for sx: float in [-2.1, 2.1]:
		_cilindro(n, 0.09, 0.11, 3.65, Vector3(sx, 1.825, 0), MADERA_OSCURA)
		_caja(n, Vector3(0.26, 3.6, 0.26), Vector3(sx, 1.8, 0), MADERA_OSCURA, Vector3.ZERO, true).visible = false
	_caja(n, Vector3(4.55, 0.18, 0.18), Vector3(0, 3.55, 0), MADERA_CLARA)
	_caja(n, Vector3(3.0, 0.46, 0.08), Vector3(0, 3.18, 0), Color(0.34, 0.22, 0.13))
	_texto_cartel(n, titulo.to_upper(), Vector3(0, 3.18, 0.048), 0.0, Color(0.96, 0.88, 0.68))
	_texto_cartel(n, titulo.to_upper(), Vector3(0, 3.18, -0.048), PI, Color(0.96, 0.88, 0.68))
	for i in 11:
		var t := -1.8 + float(i) * 0.36
		var c: Color = colores[i % colores.size()] as Color
		_esfera(n, 0.14, Vector3(t, 3.64, 0.08), HOJA_VERDE)
		_esfera(n, 0.075, Vector3(t, 3.62, 0.16), c, Vector3.ONE, 0.7 if con_farol else 0.0)


func _construir_guirnalda_plaza(colores: Array, con_faroles: bool) -> void:
	var postes: Array[Vector2] = [
		Vector2(-7.6, -5.4),
		Vector2(7.6, -5.4),
		Vector2(-7.6, 5.2),
		Vector2(7.6, 5.2),
	]
	var cimas: Array[Vector3] = []
	for p: Vector2 in postes:
		var sp := _suelo_en(p.x, p.y)
		var mastil := Node3D.new()
		_raiz_decoracion.add_child(mastil)
		mastil.global_position = sp
		_cilindro(mastil, 0.075, 0.095, 4.35, Vector3(0, 2.175, 0), MADERA_OSCURA)
		_esfera(mastil, 0.12, Vector3(0, 4.40, 0), colores[0] as Color)
		cimas.append(sp + Vector3(0, 4.15, 0))

	var pares: Array = [[0, 1], [2, 3], [0, 2], [1, 3], [0, 3], [1, 2]]
	for par: Array in pares:
		_colgar_cuerda_banderines(cimas[int(par[0])], cimas[int(par[1])], colores, con_faroles)


func _colgar_cuerda_banderines(a: Vector3, b: Vector3, colores: Array, con_faroles: bool) -> void:
	var n := Node3D.new()
	_raiz_decoracion.add_child(n)
	var dist := a.distance_to(b)
	var pasos := maxi(8, int(dist / 0.85))
	var dir_xz := Vector2(b.x - a.x, b.z - a.z).normalized()
	var ang_y := atan2(dir_xz.x, dir_xz.y)

	var punto_curva := func(idx: int) -> Vector3:
		var f := float(idx) / float(pasos)
		var p := a.lerp(b, f)
		p.y -= sin(f * PI) * 0.62
		return p

	var prev := a
	for i in range(1, pasos + 1):
		var curr: Vector3 = punto_curva.call(i)
		# Tramo real de cuerda oscura uniendo los puntos de la catenaria.
		var seg := prev.distance_to(curr)
		var tramo := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.013
		cm.bottom_radius = 0.013
		cm.height = seg
		cm.radial_segments = 6
		tramo.mesh = cm
		tramo.material_override = _mat(Color(0.22, 0.16, 0.11))
		n.add_child(tramo)
		tramo.global_position = (prev + curr) * 0.5
		var vec := curr - prev
		if vec.length() > 0.001:
			var up_alt := Vector3.RIGHT if absf(vec.normalized().y) > 0.95 else Vector3.UP
			tramo.look_at(curr, up_alt)
			tramo.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		prev = curr
		if i >= pasos:
			continue

		var c: Color = colores[i % colores.size()] as Color
		if con_faroles and i % 2 == 0:
			_cilindro(n, 0.10, 0.085, 0.22, curr - Vector3(0, 0.15, 0), c)
			_cilindro(n, 0.105, 0.105, 0.025, curr - Vector3(0, 0.04, 0), MADERA_OSCURA)
			_cilindro(n, 0.09, 0.09, 0.025, curr - Vector3(0, 0.26, 0), MADERA_OSCURA)
			_esfera(n, 0.085, curr - Vector3(0, 0.15, 0), Color(1.0, 0.78, 0.34), Vector3(1.0, 1.15, 1.0), 1.4)
		else:
			var band := PrismMesh.new()
			band.size = Vector3(0.22, 0.24, 0.022)
			var mat_b := _mat(c, 0.92)
			mat_b.cull_mode = BaseMaterial3D.CULL_DISABLED
			var mi := _malla(n, band, curr - Vector3(0, 0.12, 0), mat_b, Vector3(0, ang_y + PI * 0.5, PI))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _construir_corona_pozo(colores: Array) -> void:
	# Muestreamos junto al brocal para no chocar con el tejado del pozo.
	var base := _suelo_en(1.8, 0.0)
	base.x = 0.0
	base.z = 0.0
	var n := Node3D.new()
	_raiz_decoracion.add_child(n)
	n.global_position = base
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var r := 1.16
		var p := Vector3(cos(ang) * r, 0.88, sin(ang) * r)
		_esfera(n, 0.12, p, HOJA_VERDE)
		_esfera(n, 0.075, p + Vector3(0, 0.07, 0), colores[i % colores.size()] as Color)


func _construir_mesa_festiva(coord: Vector2, color_mantel: Color, color_corredor: Color, tema: String) -> void:
	var n := Node3D.new()
	n.name = "MesaFestiva"
	_raiz_decoracion.add_child(n)
	n.global_position = _suelo_en(coord.x, coord.y)
	_orientar_horizontal(n, _suelo_en(0.0, 0.0))
	for px: float in [-0.75, 0.75]:
		for pz: float in [-0.36, 0.36]:
			_cilindro(n, 0.045, 0.055, 0.74, Vector3(px, 0.37, pz), MADERA_OSCURA)
	_caja(n, Vector3(1.86, 0.08, 0.94), Vector3(0, 0.76, 0), MADERA_CLARA, Vector3.ZERO, true)
	_caja(n, Vector3(1.90, 0.12, 0.98), Vector3(0, 0.78, 0), color_mantel)
	_caja(n, Vector3(1.92, 0.14, 0.34), Vector3(0, 0.79, 0), color_corredor)
	if tema == "siembra":
		for k in 3:
			var x := -0.56 + float(k) * 0.56
			_cilindro(n, 0.13, 0.16, 0.22, Vector3(x, 0.96, 0), Color(0.76, 0.68, 0.50))
			_esfera(n, 0.12, Vector3(x, 1.12, 0), HOJA_CLARA)
			_esfera(n, 0.06, Vector3(x + 0.06, 1.18, 0.04), Color(0.92, 0.44, 0.52) if k % 2 == 0 else Color(0.96, 0.84, 0.34))
	else:
		_crear_calabaza(n, Vector3(-0.56, 0.84, 0.05), 0.19, Color(0.88, 0.44, 0.14))
		_crear_calabaza(n, Vector3(0.02, 0.84, -0.04), 0.23, Color(0.92, 0.54, 0.16))
		_esfera(n, 0.13, Vector3(0.56, 0.93, 0.05), Color(0.78, 0.54, 0.26), Vector3(1.25, 0.65, 0.95))
		_cilindro(n, 0.11, 0.11, 0.24, Vector3(0.32, 0.97, 0.22), Color(0.54, 0.36, 0.20))


func _construir_puesto_festivo(coord: Vector2, c1: Color, c2: Color, titulo: String, verbo: String, nombre_obj: String, mensaje_brindis: String, tema: String) -> void:
	var n := Node3D.new()
	n.name = "PuestoFestivo"
	_raiz_decoracion.add_child(n)
	n.global_position = _suelo_en(coord.x, coord.y)
	_orientar_horizontal(n, _suelo_en(0.0, 0.0))

	_caja(n, Vector3(1.9, 0.88, 0.82), Vector3(0, 0.44, 0), MADERA_OSCURA, Vector3.ZERO, true)
	_caja(n, Vector3(2.04, 0.08, 0.92), Vector3(0, 0.90, 0), MADERA_CLARA)
	for sx: float in [-0.90, 0.90]:
		for sz: float in [-0.36, 0.36]:
			_cilindro(n, 0.05, 0.055, 2.36, Vector3(sx, 1.18, sz), MADERA_OSCURA)
	for f in 5:
		var col := c1 if f % 2 == 0 else c2
		_caja(n, Vector3(0.44, 0.07, 1.24), Vector3(-0.88 + float(f) * 0.44, 2.40, 0.04), col, Vector3(0.16, 0, 0))
	_caja(n, Vector3(1.75, 0.24, 0.06), Vector3(0, 2.12, 0.40), Color(0.32, 0.20, 0.12))
	_texto_cartel(n, titulo.to_upper(), Vector3(0, 2.12, 0.44), 0.0, Color(0.95, 0.88, 0.72))
	if tema == "siembra":
		for i in 4:
			_esfera(n, 0.13, Vector3(-0.56 + float(i) * 0.36, 1.02, 0), HOJA_CLARA)
			_esfera(n, 0.06, Vector3(-0.56 + float(i) * 0.36, 1.12, 0.04), Color(0.95, 0.82, 0.32) if i % 2 == 0 else Color(0.88, 0.44, 0.56))
	else:
		_crear_calabaza(n, Vector3(-0.54, 0.94, 0.04), 0.18, Color(0.88, 0.44, 0.14))
		_crear_calabaza(n, Vector3(0.02, 0.94, -0.02), 0.20, Color(0.92, 0.56, 0.16))
		_cilindro(n, 0.16, 0.16, 0.32, Vector3(0.56, 1.10, 0.02), Color(0.48, 0.32, 0.18))

	var pto := Interactuable.new()
	pto.name = "PuestoFeria"
	pto.verbo = verbo
	pto.nombre_objeto = nombre_obj
	pto.mostrar_nombre = true
	pto.radio = 1.9
	pto.altura_marca = 2.1
	pto.position = Vector3(0, 0.1, 0.78)
	pto.usado.connect(func(_j: Node3D) -> void:
		var clave_dia := "brindis_fiesta_%d" % AyudasL4b.clave_dia()
		if not bool(Juego.banderas.get(clave_dia, false)):
			Juego.banderas[clave_dia] = true
			Juego.recuperar_energia(10.0)
			Interfaz.mostrar_dialogo(Juego.nombre_festividad_hoy(), [mensaje_brindis])
		else:
			Interfaz.mostrar_dialogo(Juego.nombre_festividad_hoy(), ["La plaza rebosa alegría y buena compañía. ¡Disfruta de la fiesta con los vecinos!"]))
	n.add_child(pto)
	mesa_festiva = pto
