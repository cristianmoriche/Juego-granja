class_name PanelDebug
extends Control
## Menú debug oculto (F9 / Ctrl+Shift+D): viaje entre zonas, plantas de mina, vuelo, inmortalidad,
## energía ilimitada, dinero, visualización de hitboxes y pausa del tiempo.

const GRUPO_HITBOX := "debug_hitbox_visual"
const ZONAS := [
	{"id": "granja", "nombre": "Granja (El Granado)", "entrada": "Spawn_Protagonista"},
	{"id": "pueblo", "nombre": "Pueblo (Villaverde)", "entrada": "Spawn_Protagonista"},
	{"id": "bosque_norte", "nombre": "Bosque del Norte", "entrada": "Spawn_Protagonista"},
	{"id": "costa_lago", "nombre": "Costa del Lago", "entrada": "Spawn_Protagonista"},
	{"id": "robledal_niebla", "nombre": "Robledal de la Niebla", "entrada": "Spawn_Protagonista"},
	{"id": "ruinas_valle", "nombre": "Ruinas del Valle", "entrada": "Spawn_Protagonista"},
	{"id": "sierra_mirador", "nombre": "Mirador de la Sierra", "entrada": "Spawn_Protagonista"},
	{"id": "mina_exterior", "nombre": "Mina (Exterior)", "entrada": "Spawn_Protagonista"},
	{"id": "mina_interior", "nombre": "Mina (Interior)", "entrada": "Llegada_Interior"},
	{"id": "casa_leo", "nombre": "Casa de Leo", "entrada": "Entrada"},
	{"id": "tienda", "nombre": "Tienda de Don Mateo", "entrada": "Entrada"},
	{"id": "herreria", "nombre": "Herrería de Clara", "entrada": "Entrada"},
	{"id": "taberna", "nombre": "Taberna El Candil", "entrada": "Entrada"},
	{"id": "casa_alcalde", "nombre": "Ayuntamiento", "entrada": "Entrada"},
	{"id": "capilla", "nombre": "Capilla", "entrada": "Entrada"},
	{"id": "casita_a", "nombre": "Casita Oeste", "entrada": "Entrada"},
	{"id": "casita_b", "nombre": "Casita Este", "entrada": "Entrada"},
]

var _selector_zona: OptionButton
var _spin_planta: SpinBox
var _chk_vuelo: CheckButton
var _chk_inmortal: CheckButton
var _chk_energia: CheckButton
var _chk_hitboxes: CheckButton
var _b_tiempo: Button
var _l_estado: Label
var _mat_solido: StandardMaterial3D
var _mat_area: StandardMaterial3D


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_mat_solido = StandardMaterial3D.new()
	_mat_solido.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_solido.albedo_color = Color(0.18, 0.96, 0.44, 0.78)
	_mat_solido.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_solido.no_depth_test = true
	_mat_solido.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_area = StandardMaterial3D.new()
	_mat_area.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_area.albedo_color = Color(0.28, 0.78, 1.0, 0.65)
	_mat_area.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_area.no_depth_test = true
	_mat_area.cull_mode = BaseMaterial3D.CULL_DISABLED

	var fondo := ColorRect.new()
	fondo.color = Color(0.02, 0.025, 0.035, 0.52)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var marco := PanelContainer.new()
	marco.anchor_left = 0.5
	marco.anchor_right = 0.5
	marco.anchor_top = 0.5
	marco.anchor_bottom = 0.5
	marco.grow_horizontal = Control.GROW_DIRECTION_BOTH
	marco.grow_vertical = Control.GROW_DIRECTION_BOTH
	Estilo.estilo_panel(marco, Color(0.06, 0.075, 0.095, 0.96), Color(0.32, 0.78, 0.56), 18)
	add_child(marco)

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(610, 0)
	v.add_theme_constant_override("separation", 10)
	marco.add_child(v)

	var cab := HBoxContainer.new()
	v.add_child(cab)
	var tit := Estilo.etiqueta("Herramientas Debug", Estilo.TAM_GRANDE, Color(0.45, 0.95, 0.68))
	tit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(tit)
	var b_cer := Estilo.boton("Cerrar (F9)", 140)
	b_cer.pressed.connect(cerrar)
	cab.add_child(b_cer)

	_l_estado = Estilo.etiqueta("", Estilo.TAM_PEQUENO, Estilo.COLOR_TEXTO_SUAVE)
	v.add_child(_l_estado)

	# 1. Viaje rápido entre zonas
	var f_zona := HBoxContainer.new()
	f_zona.add_theme_constant_override("separation", 8)
	v.add_child(f_zona)
	f_zona.add_child(Estilo.etiqueta("Zona:", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO))
	_selector_zona = OptionButton.new()
	_selector_zona.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for z: Dictionary in ZONAS:
		_selector_zona.add_item(str(z["nombre"]))
	f_zona.add_child(_selector_zona)
	var b_viajar := Estilo.boton("Viajar", 120)
	b_viajar.pressed.connect(_al_viajar)
	f_zona.add_child(b_viajar)

	# 2. Mina: planta exacta / bajar o subir
	var f_mina := HBoxContainer.new()
	f_mina.add_theme_constant_override("separation", 8)
	v.add_child(f_mina)
	f_mina.add_child(Estilo.etiqueta("Planta mina:", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO))
	_spin_planta = SpinBox.new()
	_spin_planta.min_value = 1
	_spin_planta.max_value = 20
	_spin_planta.value = 1
	_spin_planta.custom_minimum_size = Vector2(90, 36)
	f_mina.add_child(_spin_planta)
	var b_sub := Estilo.boton("-1", 56)
	b_sub.pressed.connect(func() -> void:
		ir_planta_mina(clampi(int(Juego.banderas.get("nivel_mina", 1)) - 1, 1, 20)))
	f_mina.add_child(b_sub)
	var b_baj := Estilo.boton("+1 Bajar", 110)
	b_baj.pressed.connect(func() -> void:
		ir_planta_mina(clampi(int(Juego.banderas.get("nivel_mina", 1)) + 1, 1, 20)))
	f_mina.add_child(b_baj)
	var b_ir_m := Estilo.boton("Ir a planta", 130)
	b_ir_m.pressed.connect(func() -> void: ir_planta_mina(int(_spin_planta.value)))
	f_mina.add_child(b_ir_m)

	# 3. Interruptores debug (vuelo, inmortalidad, energía, hitboxes)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)

	_chk_vuelo = CheckButton.new()
	_chk_vuelo.text = "Vuelo libre (Espacio/Ctrl)"
	_chk_vuelo.toggled.connect(poner_vuelo)
	grid.add_child(_chk_vuelo)

	_chk_inmortal = CheckButton.new()
	_chk_inmortal.text = "Inmortalidad"
	_chk_inmortal.toggled.connect(poner_inmortal)
	grid.add_child(_chk_inmortal)

	_chk_energia = CheckButton.new()
	_chk_energia.text = "Energía y vigor ilimitados"
	_chk_energia.toggled.connect(poner_energia_infinita)
	grid.add_child(_chk_energia)

	_chk_hitboxes = CheckButton.new()
	_chk_hitboxes.text = "Mostrar hitboxes"
	_chk_hitboxes.toggled.connect(poner_hitboxes)
	grid.add_child(_chk_hitboxes)

	# 4. Dinero y tiempo
	var f_din := HBoxContainer.new()
	f_din.add_theme_constant_override("separation", 8)
	v.add_child(f_din)
	f_din.add_child(Estilo.etiqueta("Dinero:", Estilo.TAM_TEXTO, Estilo.COLOR_TEXTO))
	for delta: int in [-5000, -500, 500, 5000]:
		var eti := ("%+d €" % delta)
		var b_d := Estilo.boton(eti, 100)
		b_d.pressed.connect(func() -> void:
			Juego.ajustar_dinero_debug(delta)
			refrescar())
		f_din.add_child(b_d)

	var f_tmp := HBoxContainer.new()
	f_tmp.add_theme_constant_override("separation", 10)
	v.add_child(f_tmp)
	_b_tiempo = Estilo.boton("Pausar tiempo", 260)
	_b_tiempo.pressed.connect(func() -> void:
		Juego.pausar_tiempo_debug(not Juego.tiempo_debug_pausado())
		refrescar())
	f_tmp.add_child(_b_tiempo)
	var b_curar := Estilo.boton("Restaurar vida y energía", 260)
	b_curar.pressed.connect(func() -> void:
		Juego.curar_vida(Juego.vida_max)
		Juego.recuperar_energia(Juego.energia_max)
		refrescar())
	f_tmp.add_child(b_curar)


func abrir() -> void:
	refrescar()
	visible = true


func cerrar() -> void:
	visible = false


func refrescar() -> void:
	var mapa := Escenas.mapa_actual_nodo()
	var id_act := str(mapa.get("id_mapa")) if mapa != null else Juego.mapa_actual
	for i in ZONAS.size():
		if str(ZONAS[i]["id"]) == id_act:
			_selector_zona.select(i)
			break
	var niv := clampi(int(Juego.banderas.get("nivel_mina", 1)), 1, 20)
	_spin_planta.set_value_no_signal(niv)
	_chk_vuelo.set_pressed_no_signal(Juego.debug_vuelo)
	_chk_inmortal.set_pressed_no_signal(Juego.debug_inmortal)
	_chk_energia.set_pressed_no_signal(Juego.debug_energia_infinita)
	_chk_hitboxes.set_pressed_no_signal(Juego.debug_hitboxes)
	_b_tiempo.text = "Reanudar tiempo (PAUSADO)" if Juego.tiempo_debug_pausado() else "Pausar tiempo (CORRIENDO)"
	_l_estado.text = "Mapa: %s | Planta mina: %d | Dinero: %s | Vida: %.0f/%.0f | Energía: %.0f/%.0f" % [
		id_act, niv, Estilo.euros(Juego.dinero), Juego.vida, Juego.vida_max, Juego.energia, Juego.energia_max
	]


func _al_viajar() -> void:
	var idx := clampi(_selector_zona.selected, 0, ZONAS.size() - 1)
	var z: Dictionary = ZONAS[idx]
	cerrar()
	Escenas.ir_a_mapa(str(z["id"]), str(z["entrada"]))


func ir_planta_mina(nivel: int) -> void:
	var n := clampi(nivel, 1, 20)
	Juego.banderas["nivel_mina"] = n
	if n > int(Juego.banderas.get("mina_max_nivel", 1)):
		Juego.banderas["mina_max_nivel"] = n
	cerrar()
	Escenas.ir_a_mapa("mina_interior", "Llegada_Interior")


func poner_vuelo(activo: bool) -> void:
	Juego.debug_vuelo = activo
	var j := Escenas.jugador()
	if j != null and j.has_method("aplicar_modo_vuelo"):
		j.call("aplicar_modo_vuelo", activo)
	refrescar()


func poner_inmortal(activo: bool) -> void:
	Juego.debug_inmortal = activo
	if activo:
		Juego.curar_vida(Juego.vida_max)
	refrescar()


func poner_energia_infinita(activo: bool) -> void:
	Juego.debug_energia_infinita = activo
	if activo:
		Juego.recuperar_energia(Juego.energia_max)
	refrescar()


func poner_hitboxes(activo: bool) -> void:
	Juego.debug_hitboxes = activo
	sincronizar_hitboxes()
	refrescar()


func sincronizar_hitboxes() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	for n: Node in get_tree().get_nodes_in_group(GRUPO_HITBOX):
		if is_instance_valid(n):
			n.queue_free()
	if not Juego.debug_hitboxes:
		return
	var mapa := Escenas.mapa_actual_nodo()
	var j := Escenas.jugador()
	for raiz: Node in [mapa, j]:
		if raiz != null and is_instance_valid(raiz):
			_crear_mallas_colision(raiz)


func _crear_mallas_colision(nodo: Node) -> void:
	if nodo is CollisionShape3D:
		var cs := nodo as CollisionShape3D
		if cs.shape != null and not cs.disabled and cs.is_inside_tree():
			var par := cs.get_parent()
			var es_area := par is Area3D
			if not (cs.shape is ConcavePolygonShape3D and (cs.shape as ConcavePolygonShape3D).get_faces().size() > 1500):
				var mi := MeshInstance3D.new()
				mi.name = "DebugHitbox"
				mi.add_to_group(GRUPO_HITBOX)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.mesh = cs.shape.get_debug_mesh()
				mi.material_override = _mat_area if es_area else _mat_solido
				cs.add_child(mi)
	for h: Node in nodo.get_children():
		if h is Node and not h.is_in_group(GRUPO_HITBOX):
			_crear_mallas_colision(h)
