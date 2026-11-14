extends Node
## Herramienta de exploración de M1 (no es una prueba): para cada mapa saca una foto cenital con rejilla en metros
## y marca por encima qué casillas de 1 m puede pisar Leo de verdad (cápsula contra la capa 1, pendiente máxima y
## relleno desde el punto de aparición). Sirve para dibujar los polígonos de `datos/limites.json` mirando datos reales.
## Uso (con ventana, se cierra sola):
##   godot.ps1 --path <proyecto> --position 40,40 --resolution 640x360 --scene res://pruebas/explorar_m1.tscn -- <carpeta_salida> [id[:x0,z0,x1,z1]]...
## Genera <carpeta_salida>/exp_<id>.png (rejilla cada 10 m con su número; verde = alcanzable, amarillo = pisable pero
## aislado, rojo = bloqueado por colisión, negro = sin suelo) y <carpeta_salida>/exp_<id>.txt con el resumen.

const RADIO := 0.35
const ALTO := 1.8
const ELEVACION := 0.2
const PENDIENTE_MIN_NY := 0.64
const SALTO_MAX := 0.8
const DIGITOS := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
	"4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
	"8": "111101111101111", "9": "111101111001111", "-": "000000111000000",
}


func _ready() -> void:
	_ejecutar.call_deferred()


func _ejecutar() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Falta la carpeta de salida")
		get_tree().quit(1)
		return
	var salida := args[0]
	var pedidos: Array[String] = []
	for i in range(1, args.size()):
		pedidos.append(args[i])
	if pedidos.is_empty():
		pedidos = ["granja", "pueblo", "mina_exterior"]
	for p in pedidos:
		await _explorar(p, salida)
	print("EXPLORACION OK")
	get_tree().quit(0)


func _explorar(pedido: String, salida: String) -> void:
	var id := pedido.get_slice(":", 0)
	var mapa := (load("res://escenas/mapas/%s.tscn" % id) as PackedScene).instantiate() as Node3D
	add_child(mapa)
	if not bool(mapa.get("esta_listo")):
		await mapa.listo
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var caja: AABB = mapa.call("aabb_mapa")
	var rect := Rect2(Vector2(caja.position.x, caja.position.z), Vector2(caja.size.x, caja.size.z))
	if ":" in pedido:
		var n := pedido.get_slice(":", 1).split(",")
		rect = Rect2(Vector2(float(n[0]), float(n[1])), Vector2(float(n[2]) - float(n[0]), float(n[3]) - float(n[1])))
	var y_top := caja.end.y + 30.0
	var y_bot := caja.position.y - 20.0

	# --- Escaneo de casillas ---
	var nx := int(ceil(rect.size.x / 1.0))
	var nz := int(ceil(rect.size.y / 1.0))
	var suelo := PackedFloat32Array()
	suelo.resize(nx * nz)
	suelo.fill(NAN)
	var estado := PackedByteArray()     # 0 sin suelo, 1 pisable, 2 bloqueado
	estado.resize(nx * nz)
	var espacio := mapa.get_world_3d().direct_space_state
	var capsula := CapsuleShape3D.new()
	capsula.radius = RADIO
	capsula.height = ALTO
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = capsula
	consulta.collision_mask = 1
	for iz in nz:
		for ix in nx:
			var x := rect.position.x + (float(ix) + 0.5)
			var z := rect.position.y + (float(iz) + 0.5)
			var g := _suelo_en(espacio, x, z, y_top, y_bot)
			if g.is_empty():
				continue
			var gy: float = g["y"]
			suelo[iz * nx + ix] = gy
			if float(g["ny"]) < PENDIENTE_MIN_NY:
				estado[iz * nx + ix] = 2
				continue
			consulta.transform = Transform3D(Basis.IDENTITY, Vector3(x, gy + ELEVACION + ALTO * 0.5, z))
			var choques := espacio.intersect_shape(consulta, 1)
			estado[iz * nx + ix] = 2 if not choques.is_empty() else 1

	# --- Relleno desde el punto de aparición ---
	var spawn := mapa.call("marcador", "Spawn_Protagonista") as Marker3D
	var alcanzable := PackedByteArray()
	alcanzable.resize(nx * nz)
	var sx := int(floor(spawn.global_position.x - rect.position.x))
	var sz := int(floor(spawn.global_position.z - rect.position.y))
	var cola: Array[int] = []
	if sx >= 0 and sx < nx and sz >= 0 and sz < nz and estado[sz * nx + sx] == 1:
		cola.append(sz * nx + sx)
		alcanzable[sz * nx + sx] = 1
	var cabeza := 0
	while cabeza < cola.size():
		var c := cola[cabeza]
		cabeza += 1
		var cx := c % nx
		var cz := c / nx
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var ax: int = cx + dx
				var az: int = cz + dz
				if ax < 0 or ax >= nx or az < 0 or az >= nz:
					continue
				var a := az * nx + ax
				if alcanzable[a] == 1 or estado[a] != 1:
					continue
				if absf(suelo[a] - suelo[c]) > SALTO_MAX:
					continue
				alcanzable[a] = 1
				cola.append(a)

	# --- Resumen ---
	var minx := 1000000
	var maxx := -1000000
	var minz := 1000000
	var maxz := -1000000
	for i in nx * nz:
		if alcanzable[i] == 1:
			minx = mini(minx, i % nx)
			maxx = maxi(maxx, i % nx)
			minz = mini(minz, i / nx)
			maxz = maxi(maxz, i / nx)
	var texto := "mapa %s  rect %s  casillas %d  alcanzables %d\n" % [id, str(rect), nx * nz, cola.size()]
	texto += "alcanzable x [%.0f, %.0f]  z [%.0f, %.0f]\n" % [rect.position.x + minx, rect.position.x + maxx + 1, rect.position.y + minz, rect.position.y + maxz + 1]
	# Perfil por filas de 4 m: extremos alcanzables en x (para dibujar el polígono).
	texto += "perfil (z: xmin..xmax alcanzable)\n"
	var z0 := minz - (minz % 4)
	for iz in range(maxi(z0, 0), mini(maxz + 1, nz), 4):
		var a := 100000
		var b := -100000
		for k in 4:
			if iz + k >= nz:
				break
			for ix in nx:
				if alcanzable[(iz + k) * nx + ix] == 1:
					a = mini(a, ix)
					b = maxi(b, ix)
		if b >= a:
			texto += "  z %.0f: %.0f .. %.0f\n" % [rect.position.y + iz, rect.position.x + a, rect.position.x + b + 1]
	var f := FileAccess.open(salida.path_join("exp_%s.txt" % id), FileAccess.WRITE)
	f.store_string(texto)
	f.close()
	print(texto.get_slice("\n", 0), " / ", texto.get_slice("\n", 1))

	# --- Imagen ---
	var tex := await FotoCenital.generar(mapa, id, rect, 1600, y_top, y_bot, true)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for py in h:
		for px in w:
			var ix := clampi(int(float(px) / float(w) * float(nx)), 0, nx - 1)
			var iz := clampi(int(float(py) / float(h) * float(nz)), 0, nz - 1)
			var i := iz * nx + ix
			var tinte := Color(0, 0, 0, 0)
			if alcanzable[i] == 1:
				tinte = Color(0.1, 0.9, 0.2, 0.28)
			elif estado[i] == 1:
				tinte = Color(0.95, 0.85, 0.1, 0.35)
			elif estado[i] == 2:
				tinte = Color(0.95, 0.1, 0.1, 0.28)
			else:
				tinte = Color(0, 0, 0, 0.75)
			if tinte.a > 0.0:
				var base := img.get_pixel(px, py)
				img.set_pixel(px, py, base.lerp(Color(tinte.r, tinte.g, tinte.b), tinte.a))
	# Rejilla cada 10 m.
	var esc_x := float(w) / rect.size.x
	var esc_z := float(h) / rect.size.y
	var x_ini := int(ceil(rect.position.x / 10.0)) * 10
	while float(x_ini) < rect.end.x:
		var px := int((float(x_ini) - rect.position.x) * esc_x)
		var grueso := x_ini % 50 == 0
		for py in h:
			_mezclar(img, px, py, Color(1, 1, 1), 0.7 if grueso else 0.3)
		_texto(img, px + 3, 3, str(x_ini))
		_texto(img, px + 3, h - 14, str(x_ini))
		x_ini += 10
	var z_ini := int(ceil(rect.position.y / 10.0)) * 10
	while float(z_ini) < rect.end.y:
		var py := int((float(z_ini) - rect.position.y) * esc_z)
		var grueso := z_ini % 50 == 0
		for px in w:
			_mezclar(img, px, py, Color(1, 1, 1), 0.7 if grueso else 0.3)
		_texto(img, 3, py + 3, str(z_ini))
		_texto(img, w - 40, py + 3, str(z_ini))
		z_ini += 10
	# Marcadores.
	for m: Marker3D in mapa.call("marcadores_de_tipo", "spawn"):
		_cruz(img, int((m.global_position.x - rect.position.x) * esc_x), int((m.global_position.z - rect.position.y) * esc_z), Color(0.2, 0.5, 1.0))
	for m: Marker3D in mapa.call("marcadores_de_tipo", "salida"):
		_cruz(img, int((m.global_position.x - rect.position.x) * esc_x), int((m.global_position.z - rect.position.y) * esc_z), Color(1.0, 0.2, 1.0))
	img.save_png(salida.path_join("exp_%s.png" % id))
	print("imagen ", id, " ", img.get_size())
	mapa.queue_free()
	await get_tree().process_frame


## Suelo de la columna (x, z): el punto más bajo con superficie hacia arriba (los troncos van sobre el terreno).
func _suelo_en(espacio: PhysicsDirectSpaceState3D, x: float, z: float, y_top: float, y_bot: float) -> Dictionary:
	var y := y_top
	var mejor := {}
	for _i in 8:
		var rq := PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, y_bot, z), 1)
		var hit := espacio.intersect_ray(rq)
		if hit.is_empty():
			break
		var n: Vector3 = hit["normal"]
		var p: Vector3 = hit["position"]
		if n.y > 0.2:
			mejor = {"y": p.y, "ny": n.y}
		y = p.y - 0.02
	return mejor


func _mezclar(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, a))


func _cruz(img: Image, x: int, y: int, c: Color) -> void:
	for d in range(-6, 7):
		for g in range(-1, 2):
			_mezclar(img, x + d, y + g, c, 1.0)
			_mezclar(img, x + g, y + d, c, 1.0)


func _texto(img: Image, x: int, y: int, s: String) -> void:
	var esc := 2
	var ancho := s.length() * 4 * esc + 2
	for yy in range(-1, 5 * esc + 1):
		for xx in range(-1, ancho):
			_mezclar(img, x + xx, y + yy, Color(0, 0, 0), 0.7)
	var cx := x
	for ch in s:
		var patron: String = DIGITOS.get(ch, "000000000000000")
		for r in 5:
			for c in 3:
				if patron[r * 3 + c] == "1":
					for ey in esc:
						for ex in esc:
							_mezclar(img, cx + c * esc + ex, y + r * esc + ey, Color(1, 1, 0.6), 1.0)
		cx += 4 * esc
