extends RefCounted
## Resuelve la mira en las dos vistas. En tercera persona también comprueba la línea desde Leo.

const CAPA_INTERACCION := 4
const CAPA_HERRAMIENTA := 8
const ALCANCE := 2.5
const ALCANCE_CHARLA := 3.4
const MARGEN_SUPERFICIE := 0.08


static func calcular(camara: CamaraJuego) -> Dictionary:
	var distancia := camara.camara.global_position.distance_to(camara.posicion_mano()) + ALCANCE_CHARLA + 1.0
	var mundo := CamaraJuego.MASCARA_SOLIDA | CAPA_HERRAMIENTA
	var impacto := camara.rayo_central(mundo, distancia)
	var objetivo := _interactuable_visible(camara, impacto, distancia)
	var resultado := {"interactuable": objetivo}
	var punto: Vector3 = impacto.get("position", Vector3.INF)
	if punto.is_finite() and al_alcance(camara, punto) and _visible_desde_leo(camara, punto, impacto.rid):
		resultado["punto"] = punto
		resultado["normal"] = impacto.normal
		resultado["colision"] = impacto.collider
	return resultado


static func al_alcance(camara: CamaraJuego, punto: Vector3, alcance: float = ALCANCE) -> bool:
	var d := punto - camara.objetivo.global_position
	return d.slide(Vector3.UP).length_squared() <= alcance * alcance and d.y >= -1.0 and d.y <= 2.6


static func _interactuable_visible(camara: CamaraJuego, impacto: Dictionary, distancia: float) -> Interactuable:
	var cuerpo := impacto.get("collider") as CollisionObject3D
	if cuerpo != null:
		for hijo in cuerpo.get_children():
			if hijo is Interactuable and _admitir_interaccion(camara, hijo, impacto.position, impacto):
				return hijo
	var omitir: Array[RID] = []
	var origen := camara.camara.global_position
	for _i in 4:
		var sensor := camara.rayo_central(CAPA_INTERACCION, distancia, true, omitir)
		var area := sensor.get("collider") as Interactuable
		if area == null:
			break
		omitir.append(sensor.rid)
		var punto: Vector3 = sensor.position
		var corresponde := _cuerpo_del_interactuable(cuerpo, area, impacto)
		if corresponde:
			punto = impacto.position
		elif punto.is_equal_approx(origen):
			# Estar dentro del volumen de una puerta no permite abrirla mirando hacia otro lado.
			var centro := area.global_position + Vector3.UP * minf(area.altura_marca * 0.5, 1.0)
			var direccion := camara.direccion_mira()
			var metros := (centro - origen).dot(direccion)
			punto = origen + direccion * metros
			if metros < 0.06 or punto.distance_to(centro) > minf(area.radio, 0.55):
				continue
		var delante := impacto.is_empty() or origen.distance_to(punto) <= origen.distance_to(impacto.position) + MARGEN_SUPERFICIE
		# Los cuerpos de vecinos y rocas pueden sobresalir de su sensor sin tapar la interacción propia.
		if delante and _admitir_interaccion(camara, area, punto, impacto):
			return area
	return null


static func _admitir_interaccion(camara: CamaraJuego, area: Interactuable, punto: Vector3, impacto: Dictionary) -> bool:
	var distancia := ALCANCE_CHARLA if area.get_parent() is Npc else ALCANCE
	var cuerpo := impacto.get("collider") as CollisionObject3D
	var rid := RID()
	if _cuerpo_del_interactuable(cuerpo, area, impacto):
		rid = cuerpo.get_rid()
	return not area.texto_interaccion().is_empty() and al_alcance(camara, punto, distancia) and _visible_desde_leo(camara, punto, rid)


static func _cuerpo_del_interactuable(cuerpo: CollisionObject3D, area: Interactuable, impacto: Dictionary) -> bool:
	if cuerpo == null:
		return false
	if cuerpo == area.get_parent():
		return true
	var raiz := area.objetivo_resaltado
	if not is_instance_valid(raiz):
		return false
	if raiz == cuerpo or raiz.is_ancestor_of(cuerpo):
		return true
	var propietaria := cuerpo.shape_find_owner(int(impacto.shape))
	var forma := cuerpo.shape_owner_get_owner(propietaria)
	if forma == null or not forma.has_meta("malla_apuntada"):
		return false
	var malla := forma.get_meta("malla_apuntada") as Node3D
	return is_instance_valid(malla) and (malla == raiz or raiz.is_ancestor_of(malla))


static func _visible_desde_leo(camara: CamaraJuego, punto: Vector3, cuerpo: RID) -> bool:
	var mano := camara.posicion_mano()
	if mano.distance_squared_to(punto) < 0.001:
		return true
	var pared := camara.rayo_entre(mano, punto, CamaraJuego.MASCARA_SOLIDA)
	if pared.is_empty():
		return true
	var profundidad := 0.38 if pared.rid == cuerpo else MARGEN_SUPERFICIE
	return punto.distance_to(pared.position) <= profundidad
