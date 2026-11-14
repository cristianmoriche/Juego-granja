class_name DecoracionCasa
extends Node3D
## Sistema de decoración interior en `casa_leo` (T24):
## cuadrícula de 14×12 celdas (0,75 m), vista previa verde/roja, rotación con R o rueda,
## colocación/recogida con mochila y persistencia en `Juego.banderas["muebles_casa"]`.

const COLS := 14
const FILAS := 12
const TAM_CELDA := 0.75
const ORIGEN := Vector3(-5.25, 0.0, -4.50)
const CAPA_SOLO_JUGADOR := 64
const CLAVE_BANDERA := "muebles_casa"

var _decorando: bool = false
var _cursor_celda: Vector2i = Vector2i(6, 5)
var _cursor_fijado: bool = false
var _rot_actual: int = 0
var _id_forzado: String = ""

var _contenedor: Node3D
var _capa_ui: CanvasLayer
var _panel_estado: PanelContainer
var _l_estado: Label
var _l_aviso: Label

var _rejilla: MeshInstance3D
var _cuadro_celda: MeshInstance3D
var _mat_cuadro: StandardMaterial3D
var _previa_nodo: Node3D
var _previa_id: String = ""
var _mat_verde: StandardMaterial3D
var _mat_rojo: StandardMaterial3D

var _colocados: Array[Dictionary] = []
var _ultimo_raton: Vector2 = Vector2(-9999.0, -9999.0)


class BaulInteractuable extends Node3D:
	func _ready() -> void:
		add_to_group("interactuable")

	func texto_interaccion() -> String:
		return "Abrir baúl"

	func alcance_interaccion() -> float:
		return 2.4

	func interactuar(_jugador: Node) -> void:
		InteraccionesInterior.abrir_arcon()


func _ready() -> void:
	add_to_group("decoracion_casa")
	add_to_group("usable")

	_contenedor = Node3D.new()
	_contenedor.name = "MueblesColocados"
	add_child(_contenedor)

	_preparar_materiales()
	_crear_rejilla()
	_crear_ui()
	_cargar_desde_partida()

	if not Juego.partida_cambiada.is_connected(_al_cambiar_partida):
		Juego.partida_cambiada.connect(_al_cambiar_partida)
	if not Juego.ranura_cambiada.is_connected(_al_cambiar_mano):
		Juego.ranura_cambiada.connect(_al_cambiar_mano)
	if not Juego.inventario_cambiado.is_connected(_refrescar_previa):
		Juego.inventario_cambiado.connect(_refrescar_previa)

	_actualizar_ui()


func _exit_tree() -> void:
	if Juego.partida_cambiada.is_connected(_al_cambiar_partida):
		Juego.partida_cambiada.disconnect(_al_cambiar_partida)
	if Juego.ranura_cambiada.is_connected(_al_cambiar_mano):
		Juego.ranura_cambiada.disconnect(_al_cambiar_mano)
	if Juego.inventario_cambiado.is_connected(_refrescar_previa):
		Juego.inventario_cambiado.disconnect(_refrescar_previa)


func _al_cambiar_partida() -> void:
	salir_modo_decorar()
	_cargar_desde_partida()


func _al_cambiar_mano(_r: int) -> void:
	if not _decorando:
		return
	var activo := Juego.objeto_activo()
	var id_act := str(activo.get("id", ""))
	if Datos.es_mueble(id_act):
		_id_forzado = ""
	_refrescar_previa()


func esta_decorando() -> bool:
	return _decorando


func consume_rueda() -> bool:
	return _decorando


func entrar_modo_decorar(id_opcional: String = "") -> void:
	if id_opcional != "" and Datos.es_mueble(id_opcional):
		_id_forzado = id_opcional
	elif Datos.es_mueble(str(Juego.objeto_activo().get("id", ""))):
		_id_forzado = ""
	_decorando = true
	if _rejilla != null:
		_rejilla.visible = true
	if _cuadro_celda != null:
		_cuadro_celda.visible = true
	if not _cursor_fijado:
		_actualizar_cursor_desde_mundo()
	_refrescar_previa()
	_actualizar_ui()


func salir_modo_decorar() -> void:
	_decorando = false
	_cursor_fijado = false
	_id_forzado = ""
	if _rejilla != null:
		_rejilla.visible = false
	if _cuadro_celda != null:
		_cuadro_celda.visible = false
	_limpiar_previa()
	_actualizar_ui()


func fijar_cursor_celda(celda: Vector2i, rot: int = -1) -> void:
	_cursor_fijado = true
	_cursor_celda = Vector2i(clampi(celda.x, 0, COLS - 1), clampi(celda.y, 0, FILAS - 1))
	if rot >= 0:
		_rot_actual = ((rot % 4) + 4) % 4
	_refrescar_previa()
	_actualizar_ui()


func girar_mueble(paso: int = 1) -> void:
	_rot_actual = (((_rot_actual + paso) % 4) + 4) % 4
	_refrescar_previa()
	_actualizar_ui()


func muebles_colocados() -> Array:
	var raw: Variant = Juego.banderas.get(CLAVE_BANDERA, [])
	if raw is Array:
		return (raw as Array).duplicate(true)
	return []


func usar(id: String, _punto: Vector3, _jugador: Node) -> bool:
	if not Datos.es_mueble(id):
		return false
	if not _decorando:
		entrar_modo_decorar(id)
		return true
	accion_principal()
	return true


func accion_principal() -> void:
	if not _decorando:
		return
	var id_sel := _id_mueble_activo()
	if id_sel != "":
		if colocar_mueble_en_celda(id_sel, _cursor_celda, _rot_actual, false):
			Audio.reproducir("ui_aceptar")
			if not Datos.es_mueble(str(Juego.objeto_activo().get("id", ""))):
				_id_forzado = ""
			_refrescar_previa()
			_actualizar_ui()
		else:
			Audio.reproducir("ui_error")
			var chk := puede_colocar(id_sel, _cursor_celda.x, _cursor_celda.y, _rot_actual)
			Interfaz.mensaje(str(chk.get("motivo", "No cabe aquí.")))
	else:
		var recogido := recoger_mueble_en_celda(_cursor_celda)
		if recogido != "":
			Audio.reproducir("ui_aceptar")
			_refrescar_previa()
			_actualizar_ui()


func _process(_delta: float) -> void:
	var vis := Interfaz.hud_visible() and not Interfaz.ocupada()
	if _capa_ui != null:
		_capa_ui.visible = vis
	if not _decorando or Interfaz.ocupada():
		return
	if not _cursor_fijado:
		_actualizar_cursor_desde_mundo()
		_refrescar_previa()
		_actualizar_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not Interfaz.hud_visible() or Interfaz.ocupada() or Escenas.en_transicion:
		return
	if event is InputEventMouseMotion and _decorando:
		var pos_r := (event as InputEventMouseMotion).position
		if _ultimo_raton.distance_to(pos_r) > 6.0:
			_cursor_fijado = false
		_ultimo_raton = pos_r
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo:
			var codigo := ek.keycode if ek.keycode != KEY_NONE else ek.physical_keycode
			if codigo == KEY_B:
				if _decorando:
					salir_modo_decorar()
				else:
					entrar_modo_decorar()
				get_viewport().set_input_as_handled()
				return
			if codigo == KEY_F:
				Interfaz.abrir_carpinteria()
				get_viewport().set_input_as_handled()
				return
			if _decorando:
				if codigo == KEY_R:
					girar_mueble(1)
					get_viewport().set_input_as_handled()
					return
				if codigo == KEY_X or codigo == KEY_DELETE or codigo == KEY_BACKSPACE:
					var rec := recoger_mueble_en_celda(_cursor_celda)
					if rec != "":
						Audio.reproducir("ui_aceptar")
						_refrescar_previa()
						_actualizar_ui()
					get_viewport().set_input_as_handled()
					return
				if codigo == KEY_ESCAPE:
					salir_modo_decorar()
					get_viewport().set_input_as_handled()
					return
	if _decorando and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				girar_mueble(-1)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				girar_mueble(1)
				get_viewport().set_input_as_handled()
				return


# --- Celdas, colisiones y reglas de colocación --------------------------------------------------

static func tam_efectivo(id: String, rot: int) -> Vector2i:
	var m := Datos.mueble(id)
	var tam: Array = m.get("tam", [1, 1])
	var w := maxi(1, int(tam[0]))
	var d := maxi(1, int(tam[1]))
	if posmod(rot, 2) == 1:
		return Vector2i(d, w)
	return Vector2i(w, d)


static func celdas_ocupadas(gx: int, gz: int, id: String, rot: int) -> Array[Vector2i]:
	var eff := tam_efectivo(id, rot)
	var lista: Array[Vector2i] = []
	for dx in eff.x:
		for dz in eff.y:
			lista.append(Vector2i(gx + dx, gz + dz))
	return lista


static func centro_mundo(gx: int, gz: int, id: String, rot: int, y: float = 0.0) -> Vector3:
	var eff := tam_efectivo(id, rot)
	return Vector3(
		ORIGEN.x + (float(gx) + float(eff.x) * 0.5) * TAM_CELDA,
		y,
		ORIGEN.z + (float(gz) + float(eff.y) * 0.5) * TAM_CELDA
	)


static func _es_celda_fija_bloqueada(c: Vector2i, capa: String) -> bool:
	var x := c.x
	var z := c.y
	if capa == "pared":
		# Cabecero cama (0..2), estantería norte (3..5), calendario (7..8), cocina (10..13) y puerta sur (6..7).
		if z == 0 and (x <= 5 or x == 7 or x == 8 or x >= 10):
			return true
		if x == 13 and z <= 1:
			return true
		if z == FILAS - 1 and (x == 6 or x == 7):
			return true
		return false

	# Cama NW (0..2, 0..3)
	if x <= 2 and z <= 3:
		return true
	# Estantería norte (3..5, 0)
	if x >= 3 and x <= 5 and z == 0:
		return true
	# Cocina piedra + encimera NE (10..13, 0..1) y (12..13, 2..3)
	if z <= 1 and x >= 10:
		return true
	if z >= 2 and z <= 3 and x >= 12:
		return true
	# Mesa carta abuela E (11..13, 5..7)
	if x >= 11 and z >= 5 and z <= 7:
		return true
	# Banco carpintería W (0..1, 5..7)
	if x <= 1 and z >= 5 and z <= 7:
		return true
	# Arcón SW (0..1, 9..11)
	if x <= 1 and z >= 9:
		return true
	# Puerta de salida S (6..7, 10..11)
	if (x == 6 or x == 7) and z >= 10:
		return true
	return false


func puede_colocar(id: String, gx: int, gz: int, rot: int) -> Dictionary:
	var m := Datos.mueble(id)
	if m.is_empty():
		return {"ok": false, "motivo": "Mueble desconocido."}
	var r := posmod(rot, 4)
	var eff := tam_efectivo(id, r)
	var capa := str(m.get("capa", "suelo"))
	var celdas := celdas_ocupadas(gx, gz, id, r)

	for c in celdas:
		if c.x < 0 or c.x >= COLS or c.y < 0 or c.y >= FILAS:
			return {"ok": false, "motivo": "Se sale de los límites de la casa."}
		if _es_celda_fija_bloqueada(c, capa):
			return {"ok": false, "motivo": "Hay un elemento fijo o paso de puerta ahí."}

	if capa == "pared":
		var pega_pared := (
			(r == 0 and gz == 0)
			or (r == 1 and gx == 0)
			or (r == 2 and gz + eff.y == FILAS)
			or (r == 3 and gx + eff.x == COLS)
		)
		if not pega_pared:
			return {"ok": false, "motivo": "Los cuadros deben pegarse a una pared (gira con R)."}

	for ex: Dictionary in _colocados:
		var capa_ex := str(ex.get("capa", "suelo"))
		var coincide := false
		if capa == "alfombra" and capa_ex == "alfombra":
			coincide = true
		elif capa == "pared" and capa_ex == "pared" and posmod(int(ex.get("rot", 0)), 4) == r:
			coincide = true
		elif capa == "suelo" and capa_ex == "suelo":
			coincide = true
		if not coincide:
			continue
		var c_ex: Array = ex.get("celdas", [])
		for c in celdas:
			if c in c_ex:
				return {"ok": false, "motivo": "Ese hueco ya está ocupado."}

	return {"ok": true, "motivo": ""}


func colocar_mueble_en_celda(id: String, celda: Vector2i, rot: int = 0, gratis_si_falta: bool = false) -> bool:
	var r := posmod(rot, 4)
	var chk := puede_colocar(id, celda.x, celda.y, r)
	if not bool(chk.get("ok", false)):
		return false
	if Juego.cantidad(id) > 0:
		var hue := Juego.objeto_activo()
		if str(hue.get("id", "")) == id:
			Juego.quitar_de_hueco(Juego.ranura, 1)
		else:
			Juego.quitar_objeto(id, 1)
	elif not gratis_si_falta:
		Interfaz.mensaje("No te quedan unidades de ese mueble.")
		return false

	var entrada := {"id": id, "gx": celda.x, "gz": celda.y, "rot": r}
	var lista := muebles_colocados()
	lista.append(entrada)
	Juego.banderas[CLAVE_BANDERA] = lista
	_instanciar_y_registrar(entrada)
	return true


func recoger_mueble_en_celda(celda: Vector2i) -> String:
	var idx := _buscar_mueble_en_celda(celda)
	if idx < 0:
		return ""
	var registro: Dictionary = _colocados[idx]
	var id := str(registro.get("id", ""))
	if Juego.espacio_para(id) < 1:
		Interfaz.mensaje("No tienes espacio en la mochila para guardar el mueble.")
		return ""
	var nodo := registro.get("nodo", null) as Node
	if nodo != null and is_instance_valid(nodo):
		nodo.queue_free()
	_colocados.remove_at(idx)

	var lista := muebles_colocados()
	if idx < lista.size():
		lista.remove_at(idx)
		Juego.banderas[CLAVE_BANDERA] = lista

	Juego.anadir_objeto(id, 1)
	Interfaz.mensaje("Guardado en mochila: %s." % Datos.nombre_objeto(id))
	return id


func _buscar_mueble_en_celda(celda: Vector2i) -> int:
	# Prioridad: suelo -> pared -> alfombra (así se recoge primero la mesa encima de una alfombra).
	for prioridad in ["suelo", "pared", "alfombra"]:
		for i in range(_colocados.size() - 1, -1, -1):
			var ex: Dictionary = _colocados[i]
			if str(ex.get("capa", "suelo")) != prioridad:
				continue
			var c_ex: Array = ex.get("celdas", [])
			if celda in c_ex:
				return i
	return -1


# --- Instanciación 3D, colisión, luz y baúl ------------------------------------------------------

func _cargar_desde_partida() -> void:
	for c in _contenedor.get_children():
		c.queue_free()
	_colocados.clear()
	var lista := muebles_colocados()
	var validos: Array = []
	for item: Variant in lista:
		if item is Dictionary:
			var d := item as Dictionary
			var id := str(d.get("id", ""))
			if not Datos.es_mueble(id):
				continue
			validos.append(d)
			_instanciar_y_registrar(d)
	if validos.size() != lista.size():
		Juego.banderas[CLAVE_BANDERA] = validos


func _instanciar_y_registrar(d: Dictionary) -> void:
	var id := str(d.get("id", ""))
	var gx := int(d.get("gx", 0))
	var gz := int(d.get("gz", 0))
	var rot := posmod(int(d.get("rot", 0)), 4)
	var m := Datos.mueble(id)
	var capa := str(m.get("capa", "suelo"))

	var nodo := _crear_nodo_mueble(id, false)
	nodo.name = "Mueble_%s_%d" % [id, _colocados.size()]
	nodo.position = centro_mundo(gx, gz, id, rot, 0.008 if capa == "alfombra" else 0.0)
	nodo.rotation.y = float(rot) * PI * 0.5
	_contenedor.add_child(nodo)

	_colocados.append({
		"id": id,
		"gx": gx,
		"gz": gz,
		"rot": rot,
		"capa": capa,
		"celdas": celdas_ocupadas(gx, gz, id, rot),
		"nodo": nodo,
	})


func _crear_nodo_mueble(id: String, es_previa: bool) -> Node3D:
	var raiz := Node3D.new()
	var m := Datos.mueble(id)
	var ruta := str(m.get("modelo", ""))
	if not ruta.is_empty() and ResourceLoader.exists(ruta):
		var ps := load(ruta) as PackedScene
		if ps != null:
			var mod := ps.instantiate() as Node3D
			if mod != null:
				raiz.add_child(mod)
				_ajustar_mallas(mod, es_previa)
	if not es_previa:
		var col: Variant = m.get("colision", [])
		if col is Array and (col as Array).size() >= 3:
			var sx := float((col as Array)[0])
			var sy := float((col as Array)[1])
			var sz := float((col as Array)[2])
			var sb := StaticBody3D.new()
			sb.collision_layer = CAPA_SOLO_JUGADOR
			sb.collision_mask = 0
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(sx, sy, sz)
			cs.shape = box
			cs.position = Vector3(0.0, sy * 0.5, 0.0)
			sb.add_child(cs)
			raiz.add_child(sb)
		if m.has("luz") and m["luz"] is Dictionary:
			var lz := m["luz"] as Dictionary
			var l := OmniLight3D.new()
			var c_arr: Array = lz.get("color", [1.0, 0.8, 0.5])
			l.light_color = Color(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]))
			l.light_energy = float(lz.get("energia", 1.0))
			l.omni_range = float(lz.get("alcance", 6.0))
			l.omni_attenuation = 1.4
			var p_arr: Array = lz.get("pos", [0.0, 1.0, 0.0])
			l.position = Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
			raiz.add_child(l)
		if bool(m.get("almacen", false)):
			var baul := BaulInteractuable.new()
			baul.name = "InteraccionBaul"
			baul.position = Vector3(0.0, 0.35, 0.45)
			raiz.add_child(baul)
	return raiz


func _ajustar_mallas(n: Node, es_previa: bool) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if es_previa:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						bm.alpha_scissor_threshold = 0.4
						bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for h in n.get_children():
		_ajustar_mallas(h, es_previa)


# --- Rejilla, vista previa y cursor -------------------------------------------------------------

func _preparar_materiales() -> void:
	_mat_verde = StandardMaterial3D.new()
	_mat_verde.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_verde.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_verde.albedo_color = Color(0.20, 0.90, 0.35, 0.56)

	_mat_rojo = StandardMaterial3D.new()
	_mat_rojo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_rojo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_rojo.albedo_color = Color(0.95, 0.22, 0.18, 0.56)

	_mat_cuadro = StandardMaterial3D.new()
	_mat_cuadro.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cuadro.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cuadro.albedo_color = Color(0.20, 0.90, 0.35, 0.42)
	_mat_cuadro.cull_mode = BaseMaterial3D.CULL_DISABLED


func _crear_rejilla() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var y := 0.018
	var max_x := ORIGEN.x + float(COLS) * TAM_CELDA
	var max_z := ORIGEN.z + float(FILAS) * TAM_CELDA
	for x in COLS + 1:
		var wx := ORIGEN.x + float(x) * TAM_CELDA
		im.surface_add_vertex(Vector3(wx, y, ORIGEN.z))
		im.surface_add_vertex(Vector3(wx, y, max_z))
	for z in FILAS + 1:
		var wz := ORIGEN.z + float(z) * TAM_CELDA
		im.surface_add_vertex(Vector3(ORIGEN.x, y, wz))
		im.surface_add_vertex(Vector3(max_x, y, wz))
	im.surface_end()

	_rejilla = MeshInstance3D.new()
	_rejilla.name = "RejillaDecorar"
	_rejilla.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.96, 0.88, 0.58, 0.55)
	_rejilla.material_override = mat
	_rejilla.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rejilla.visible = false
	add_child(_rejilla)

	var quad := PlaneMesh.new()
	quad.size = Vector2(TAM_CELDA - 0.04, TAM_CELDA - 0.04)
	_cuadro_celda = MeshInstance3D.new()
	_cuadro_celda.name = "CeldaCursor"
	_cuadro_celda.mesh = quad
	_cuadro_celda.material_override = _mat_cuadro
	_cuadro_celda.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cuadro_celda.visible = false
	add_child(_cuadro_celda)


func _limpiar_previa() -> void:
	if _previa_nodo != null and is_instance_valid(_previa_nodo):
		_previa_nodo.queue_free()
	_previa_nodo = null
	_previa_id = ""


func _id_mueble_activo() -> String:
	var obj := Juego.objeto_activo()
	var id_act := str(obj.get("id", ""))
	if Datos.es_mueble(id_act):
		return id_act
	if _id_forzado != "" and Datos.es_mueble(_id_forzado):
		return _id_forzado
	return ""


func _actualizar_cursor_desde_mundo() -> void:
	var j := Escenas.jugador() as Jugador
	if j == null:
		return
	var p := Vector3.ZERO
	var valido := false
	if not Ajustes.ultimo_mando and j.camara != null and j.camara.camara != null and get_viewport() != null:
		var cam := j.camara.camara
		var mpos := get_viewport().get_mouse_position()
		var orig := cam.project_ray_origin(mpos)
		var dir := cam.project_ray_normal(mpos)
		if dir.y < -0.02:
			var t := (0.0 - orig.y) / dir.y
			if t > 0.0 and t < 35.0:
				var hit := orig + dir * t
				if absf(hit.x) <= 5.4 and absf(hit.z) <= 4.7:
					p = hit
					valido = true
	if not valido:
		p = j.punto_delante(1.35)
	var gx := clampi(int(floor((p.x - ORIGEN.x) / TAM_CELDA)), 0, COLS - 1)
	var gz := clampi(int(floor((p.z - ORIGEN.z) / TAM_CELDA)), 0, FILAS - 1)
	_cursor_celda = Vector2i(gx, gz)


func _refrescar_previa() -> void:
	if not _decorando:
		_limpiar_previa()
		if _cuadro_celda != null:
			_cuadro_celda.visible = false
		return

	var id := _id_mueble_activo()
	if id == "":
		_limpiar_previa()
		if _cuadro_celda != null:
			_cuadro_celda.visible = true
			var quad := _cuadro_celda.mesh as PlaneMesh
			if quad != null:
				quad.size = Vector2(TAM_CELDA - 0.06, TAM_CELDA - 0.06)
			_cuadro_celda.position = Vector3(
				ORIGEN.x + (float(_cursor_celda.x) + 0.5) * TAM_CELDA,
				0.026,
				ORIGEN.z + (float(_cursor_celda.y) + 0.5) * TAM_CELDA
			)
			var hay := _buscar_mueble_en_celda(_cursor_celda) >= 0
			_mat_cuadro.albedo_color = Color(0.98, 0.78, 0.22, 0.52) if hay else Color(0.75, 0.80, 0.88, 0.25)
		return

	if _previa_id != id or _previa_nodo == null or not is_instance_valid(_previa_nodo):
		_limpiar_previa()
		_previa_nodo = _crear_nodo_mueble(id, true)
		_previa_nodo.name = "PreviaMueble"
		add_child(_previa_nodo)
		_previa_id = id

	var m := Datos.mueble(id)
	var capa := str(m.get("capa", "suelo"))
	var eff := tam_efectivo(id, _rot_actual)
	var chk := puede_colocar(id, _cursor_celda.x, _cursor_celda.y, _rot_actual)
	var ok := bool(chk.get("ok", false))
	var mat := _mat_verde if ok else _mat_rojo

	_previa_nodo.position = centro_mundo(_cursor_celda.x, _cursor_celda.y, id, _rot_actual, 0.015 if capa == "alfombra" else 0.01)
	_previa_nodo.rotation.y = float(_rot_actual) * PI * 0.5
	_aplicar_material_previa(_previa_nodo, mat)

	if _cuadro_celda != null:
		_cuadro_celda.visible = true
		var quad := _cuadro_celda.mesh as PlaneMesh
		if quad != null:
			quad.size = Vector2(float(eff.x) * TAM_CELDA - 0.04, float(eff.y) * TAM_CELDA - 0.04)
		_cuadro_celda.position = centro_mundo(_cursor_celda.x, _cursor_celda.y, id, _rot_actual, 0.024)
		_mat_cuadro.albedo_color = Color(0.20, 0.90, 0.35, 0.45) if ok else Color(0.95, 0.22, 0.18, 0.48)


func _aplicar_material_previa(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for h in n.get_children():
		_aplicar_material_previa(h, mat)


# --- Cartel de controles ------------------------------------------------------------------------

func _crear_ui() -> void:
	_capa_ui = CanvasLayer.new()
	_capa_ui.name = "UiDecorarCasa"
	_capa_ui.layer = 5
	add_child(_capa_ui)

	_panel_estado = PanelContainer.new()
	_panel_estado.name = "PanelEstadoDecorar"
	_panel_estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Estilo.estilo_panel(_panel_estado, Color(0.08, 0.07, 0.05, 0.86), Estilo.COLOR_BORDE, 10)
	_capa_ui.add_child(_panel_estado)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_estado.add_child(vbox)

	_l_estado = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO)
	_l_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_l_estado)

	_l_aviso = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_MALO)
	_l_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_aviso.visible = false
	vbox.add_child(_l_aviso)


func _posicionar_panel_estado() -> void:
	if _panel_estado == null:
		return
	if _decorando:
		_panel_estado.anchor_left = 0.5
		_panel_estado.anchor_right = 0.5
		_panel_estado.anchor_top = 1.0
		_panel_estado.anchor_bottom = 1.0
		_panel_estado.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_panel_estado.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_panel_estado.offset_left = -360.0
		_panel_estado.offset_right = 360.0
		_panel_estado.offset_top = -182.0
		_panel_estado.offset_bottom = -142.0
	else:
		# Fuera del modo decorar, una pastilla discreta bajo Energía evita el cartel inferior y los tutoriales.
		_panel_estado.anchor_left = 1.0
		_panel_estado.anchor_right = 1.0
		_panel_estado.anchor_top = 0.0
		_panel_estado.anchor_bottom = 0.0
		_panel_estado.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_panel_estado.grow_vertical = Control.GROW_DIRECTION_END
		_panel_estado.offset_left = -280.0
		_panel_estado.offset_right = -16.0
		_panel_estado.offset_top = 196.0
		_panel_estado.offset_bottom = 228.0


func _actualizar_ui() -> void:
	if _l_estado == null or _l_aviso == null:
		return
	_posicionar_panel_estado()
	if not _decorando:
		_l_estado.text = "B · Decorar casa  |  F · Carpintería"
		_l_aviso.visible = false
		return
	var id := _id_mueble_activo()
	var gr := _rot_actual * 90
	if id != "":
		var chk := puede_colocar(id, _cursor_celda.x, _cursor_celda.y, _rot_actual)
		_l_estado.text = "DECORAR: %s (%d°)  ·  Clic/E: Colocar  ·  R/Rueda: Girar  ·  X: Guardar  ·  F: Carpintería  ·  B: Salir" % [
			Datos.nombre_objeto(id), gr
		]
		var ok := bool(chk.get("ok", false))
		_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
		_l_aviso.visible = not ok
		_l_aviso.text = str(chk.get("motivo", ""))
	else:
		var hay := _buscar_mueble_en_celda(_cursor_celda) >= 0
		_l_estado.text = "DECORAR: Selecciona un mueble en la barra (1-0)  ·  X/Clic: Recoger  ·  F: Carpintería  ·  B: Salir"
		_l_aviso.visible = hay
		if hay:
			_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_ACENTO)
			_l_aviso.text = "Pulsa Clic, E o X para recoger este mueble a la mochila."
		else:
			_l_aviso.add_theme_color_override("font_color", Estilo.COLOR_MALO)
