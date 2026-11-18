class_name ZonaPesca
extends Node3D
## Puntos de pesca en Bosque del Norte (río) y Costa del Lago (muelle), además de los topes invisibles del cauce.

const ENERGIA_PESCA := 4.0
const RADIO_RIO := 6.5
const RADIO_MUELLE := 5.5

@export var marcador_pesca: String = "Pesca_Muelle"
@export var radio_uso: float = 5.5
@export var id_zona_fija: String = ""

var _punto_pesca: Vector3 = Vector3.ZERO
var _cana_pickup: Interactuable = null
var _en_lucha: bool = false
var _panel_pesca: PanelPesca = null
var _jugador_activo: Node3D = null
var _flotador: Node3D = null
var _sedal: MeshInstance3D = null
var _onda: MeshInstance3D = null
var _base_flotador: Vector3 = Vector3.ZERO
var _t_onda: float = 0.0
var _cebo_lanzado: String = ""


func _ready() -> void:
	add_to_group("usable")
	add_to_group("zona_pesca")
	var m := _mapa()
	if m == null:
		if not id_zona_fija.is_empty():
			_punto_pesca = global_position
		return
	if not m.esta_listo:
		await m.listo
	if not marcador_pesca.is_empty():
		var mk := m.marcador(marcador_pesca)
		if mk != null:
			_punto_pesca = mk.global_position
			global_position = _punto_pesca
		else:
			_punto_pesca = global_position
	else:
		_punto_pesca = global_position
	if m.id_mapa == "bosque_norte":
		_crear_topes_rio(m)
	elif m.id_mapa == "costa_lago":
		_crear_cana_muelle(m)


func _mapa() -> Mapa:
	var n := get_parent()
	while n != null:
		if n is Mapa:
			return n as Mapa
		n = n.get_parent()
	return null


func usar(id: String, punto: Vector3, jugador: Node3D) -> bool:
	if id != "cana":
		return false
	if _en_lucha or bool(Interfaz.call("pescando_activa")):
		return true
	var d := Vector2(punto.x - _punto_pesca.x, punto.z - _punto_pesca.z).length()
	if d > radio_uso:
		return false
	if not Juego.gastar_energia(ENERGIA_PESCA * Juego.factor_energia_habilidad("pesca")):
		Interfaz.mensaje("No te quedan fuerzas para seguir pescando hoy.")
		return true
	Juego.banderas["pesca_habilitada"] = true
	var m := _mapa()
	var id_m := id_zona_fija if not id_zona_fija.is_empty() else (m.id_mapa if m != null else "bosque_norte")
	_cebo_lanzado = Juego.consumir_cebo()
	var sp_id := PescaAvanzada.elegir_especie(id_m, Juego.minutos, Juego.estacion, Juego.clima, _cebo_lanzado)
	var ejemplar := PescaAvanzada.generar_ejemplar(sp_id, _cebo_lanzado, Juego.bono_suerte_pesca())
	_jugador_activo = jugador
	_iniciar_escena_lance(punto, id_m, ejemplar)
	return true


func _iniciar_escena_lance(punto: Vector3, id_m: String, ejemplar: Dictionary) -> void:
	_limpiar_lance()
	_en_lucha = true
	var padre: Node = get_parent() if get_parent() != null else self
	_base_flotador = Vector3(punto.x, _punto_pesca.y, punto.z)
	if id_zona_fija == "mina_interior":
		_base_flotador.y = _punto_pesca.y

	_flotador = Node3D.new()
	_flotador.name = "FlotadorPesca"
	var body_f := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.065
	sph.height = 0.14
	body_f.mesh = sph
	var mf := StandardMaterial3D.new()
	mf.albedo_color = Color(0.92, 0.22, 0.16)
	mf.roughness = 0.28
	body_f.material_override = mf
	_flotador.add_child(body_f)
	padre.add_child(_flotador)
	_flotador.global_position = _base_flotador

	_onda = MeshInstance3D.new()
	_onda.name = "OndaAguaPesca"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.22
	_onda.mesh = torus
	var mo := StandardMaterial3D.new()
	mo.albedo_color = Color(0.82, 0.94, 1.0, 0.72)
	mo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_onda.material_override = mo
	padre.add_child(_onda)
	_onda.global_position = _base_flotador + Vector3(0.0, 0.02, 0.0)

	_sedal = MeshInstance3D.new()
	_sedal.name = "Sedal3D"
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.86, 0.92, 0.98)
	ms.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sedal.material_override = ms
	_sedal.mesh = ImmediateMesh.new()
	padre.add_child(_sedal)

	_panel_pesca = Interfaz.call("iniciar_pesca", id_m, ejemplar, _cebo_lanzado) as PanelPesca
	if _panel_pesca != null:
		if _panel_pesca.is_connected("finalizada", _al_terminar_pesca):
			_panel_pesca.disconnect("finalizada", _al_terminar_pesca)
		_panel_pesca.connect("finalizada", _al_terminar_pesca.bind(id_m), CONNECT_ONE_SHOT)
	else:
		_al_terminar_pesca("capturado", ejemplar, id_m)


func _process(delta: float) -> void:
	if not _en_lucha or _flotador == null or not is_instance_valid(_flotador):
		return
	_t_onda += delta
	var est: Dictionary = _panel_pesca.estado_lucha() if _panel_pesca != null else {}
	var tirando := bool(est.get("tirando", false))
	var ten := clampf(float(est.get("tension", 0.3)), 0.0, 1.0)
	var amp := 0.38 if tirando else 0.10
	var vel_n := 5.8 if tirando else 2.2
	_flotador.global_position = _base_flotador + Vector3(
		sin(_t_onda * vel_n) * amp,
		sin(_t_onda * 7.5) * (0.045 if tirando else 0.015),
		cos(_t_onda * vel_n * 0.78) * amp * 0.8
	)
	if _onda != null and is_instance_valid(_onda):
		_onda.global_position = Vector3(_flotador.global_position.x, _base_flotador.y + 0.015, _flotador.global_position.z)
		var esc := 1.0 + fmod(_t_onda * (2.6 if tirando else 1.2), 1.4)
		_onda.scale = Vector3(esc, 0.35, esc)
	if _sedal != null and is_instance_valid(_sedal) and _sedal.mesh is ImmediateMesh and is_instance_valid(_jugador_activo):
		var im := _sedal.mesh as ImmediateMesh
		im.clear_surfaces()
		var p_ori := _jugador_activo.global_position + Vector3(0.0, 1.52, 0.0) + (-_jugador_activo.global_basis.z if _jugador_activo.has_method("punto_salida_flecha") else Vector3.FORWARD) * 0.65
		var mano_sop: Variant = _jugador_activo.get("_mano_soporte")
		if mano_sop is Node3D and is_instance_valid(mano_sop):
			p_ori = (mano_sop as Node3D).global_position + Vector3(0.0, 0.62, 0.0)
		var p_fin := _flotador.global_position
		var p_mid := p_ori.lerp(p_fin, 0.5) - Vector3(0.0, (1.0 - ten) * 0.32, 0.0)
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		im.surface_set_color(Color(1.0, 0.4, 0.3) if ten > 0.78 else Color(0.88, 0.94, 1.0))
		im.surface_add_vertex(p_ori)
		im.surface_add_vertex(p_mid)
		im.surface_add_vertex(p_fin)
		im.surface_end()


func _al_terminar_pesca(resultado: String, ejemplar: Dictionary, id_m: String) -> void:
	_en_lucha = false
	_limpiar_lance()
	if resultado == "roto":
		Audio.reproducir("flecha_rebote")
		Interfaz.mensaje("¡Se rompió el sedal! Demasiada tensión durante el tirón.")
		return
	if resultado != "capturado" or ejemplar.is_empty():
		return
	var pez := str(ejemplar.get("id", "trucha"))
	Juego.anadir_objeto(pez, 1)
	TareasDiarias.registrar_progreso("pescar", 1)
	var rec := Juego.registrar_captura_pesca(ejemplar, id_m)
	if randf() < Juego.bono_suerte_pesca() and Juego.espacio_para(pez) > 0:
		Juego.anadir_objeto(pez, 1)
	Audio.reproducir("pesca_captura")
	var nom := str(Datos.objeto(pez).get("nombre", pez))
	var suf := " ¡Nueva especie!" if bool(rec.get("nueva", false)) else (" ¡Récord!" if bool(rec.get("record_kg", false)) else "")
	Interfaz.mensaje("¡%s! %.1f cm · %.2f kg.%s" % [nom, float(ejemplar.get("cm", 25.0)), float(ejemplar.get("kg", 0.5)), suf], pez)


func _limpiar_lance() -> void:
	if _flotador != null and is_instance_valid(_flotador):
		_flotador.queue_free()
	_flotador = null
	if _onda != null and is_instance_valid(_onda):
		_onda.queue_free()
	_onda = null
	if _sedal != null and is_instance_valid(_sedal):
		_sedal.queue_free()
	_sedal = null


func _exit_tree() -> void:
	_limpiar_lance()


func _crear_cana_muelle(m: Mapa) -> void:
	if bool(Juego.banderas.get("cana_muelle", false)) or Juego.cantidad("cana") > 0:
		return
	var mk := m.marcador("Cana_Muelle")
	if mk == null:
		return
	var c := Interactuable.new()
	c.name = "CanaMuelle"
	c.verbo = "Recoger"
	c.nombre_objeto = "la caña vieja"
	c.radio = 1.4
	c.altura_marca = 1.6
	add_child(c)
	c.global_position = mk.global_position

	# Instanciar el modelo real de la caña apoyado junto a la caja de cebo
	var escena_cana := load("res://assets/herramientas/cana.glb") as PackedScene
	if escena_cana != null:
		var mod := escena_cana.instantiate() as Node3D
		mod.position = Vector3(0.0, 0.08, 0.0)
		mod.rotation_degrees = Vector3(14.0, 28.0, -18.0)
		mod.scale = Vector3.ONE * 1.15
		c.add_child(mod)
	else:
		var palo := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.028
		cm.height = 1.65
		palo.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.50, 0.34, 0.18)
		mat.roughness = 0.7
		palo.material_override = mat
		palo.position = Vector3(0.0, 0.78, 0.0)
		palo.rotation_degrees = Vector3(12.0, 0.0, -18.0)
		c.add_child(palo)

	c.usado.connect(func(_j: Node3D) -> void:
		if bool(Juego.banderas.get("cana_muelle", false)):
			return
		Juego.banderas["cana_muelle"] = true
		Juego.banderas["pesca_habilitada"] = true
		Juego.anadir_objeto("cana", 1)
		Interfaz.mensaje("Recoges la caña del abuelo. Úsala en el extremo del muelle o junto al puente.", "cana")
		c.queue_free()
	)
	_cana_pickup = c


func _crear_topes_rio(m: Mapa) -> void:
	var body := StaticBody3D.new()
	body.name = "TopesRio"
	body.collision_layer = 1
	body.collision_mask = 0
	m.add_child(body)
	var forma := BoxShape3D.new()
	forma.size = Vector3(4.4, 3.0, 5.2)
	for tramos in [[-44.0, -3.2], [3.2, 44.0]]:
		var x: float = tramos[0]
		while x <= tramos[1]:
			var z_rio := -2.0 + 7.5 * sin(x * 0.055 + 0.4) + 3.0 * cos(x * 0.11)
			var cs := CollisionShape3D.new()
			cs.shape = forma
			cs.position = Vector3(x, 0.3, z_rio)
			body.add_child(cs)
			x += 4.0
