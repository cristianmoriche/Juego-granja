class_name MapaPrueba
extends Mapa
## Mapa de prueba de L3 (no es del juego): suelo, unas cajas, árboles de cartón, un vecino para hablar con él
## y una parcela de juguete donde usar la azada. Sirve para probar jugador, cámara, HUD y diálogos sin esperar a L1.


func _ready() -> void:
	_construir()
	super._ready()


func _construir() -> void:
	# Suelo grande con colisión.
	var suelo := StaticBody3D.new()
	suelo.name = "Suelo"
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(120, 1, 120)
	forma.shape = caja
	forma.position = Vector3(0, -0.5, 0)
	suelo.add_child(forma)
	var malla := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(120, 120)
	malla.mesh = plano
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37, 0.52, 0.29)
	malla.material_override = mat
	suelo.add_child(malla)
	add_child(suelo)

	# Cajas y troncos repartidos para tener referencias de escala y sombras.
	var colores := [Color(0.62, 0.45, 0.3), Color(0.55, 0.55, 0.58), Color(0.7, 0.62, 0.45)]
	var posiciones := [Vector3(6, 0, -4), Vector3(-7, 0, -6), Vector3(9, 0, 5), Vector3(-5, 0, 8), Vector3(0, 0, -12), Vector3(14, 0, -2)]
	for i in posiciones.size():
		_poner_caja(posiciones[i], Vector3(2.0 + (i % 3), 1.5 + (i % 2) * 1.5, 2.0 + ((i + 1) % 3)), colores[i % colores.size()])
	for i in 9:
		_poner_arbol(Vector3(-16 + i * 4.0, 0, -18 + (i % 3) * 2.0))

	# Marcadores.
	var spawn := Marker3D.new()
	spawn.name = "Spawn_Protagonista"
	spawn.rotation.y = PI
	add_child(spawn)
	var cam := Marker3D.new()
	cam.name = "Camara_juego"
	add_child(cam)
	cam.position = Vector3(0, 12, 10)

	# Un «vecino» con el que hablar y una parcela donde usar la azada.
	var vecino := Area3D.new()
	vecino.set_script(load("res://scripts/mapas/objeto_prueba.gd"))
	vecino.name = "Clara"
	add_child(vecino)
	vecino.position = Vector3(3, 0, -3)
	var parcela := Node3D.new()
	parcela.set_script(load("res://scripts/mapas/parcela_prueba.gd"))
	parcela.name = "Parcela"
	add_child(parcela)
	parcela.position = Vector3(-2, 0, -3)


func _poner_caja(pos: Vector3, tam: Vector3, color: Color) -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var f := BoxShape3D.new()
	f.size = tam
	forma.shape = f
	cuerpo.add_child(forma)
	var malla := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	malla.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	malla.material_override = m
	cuerpo.add_child(malla)
	add_child(cuerpo)
	cuerpo.position = pos + Vector3(0, tam.y * 0.5, 0)


func _poner_arbol(pos: Vector3) -> void:
	var cuerpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var f := CylinderShape3D.new()
	f.radius = 0.4
	f.height = 3.0
	forma.shape = f
	forma.position = Vector3(0, 1.5, 0)
	cuerpo.add_child(forma)
	var tronco := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.35
	c.bottom_radius = 0.4
	c.height = 3.0
	tronco.mesh = c
	tronco.position = Vector3(0, 1.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.28, 0.18)
	tronco.material_override = m
	cuerpo.add_child(tronco)
	var copa := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.8
	s.height = 3.4
	copa.mesh = s
	copa.position = Vector3(0, 4.0, 0)
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.2, 0.45, 0.2)
	copa.material_override = m2
	cuerpo.add_child(copa)
	add_child(cuerpo)
	cuerpo.position = pos
