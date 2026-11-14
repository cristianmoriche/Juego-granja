class_name AyudasL4b
extends RefCounted
## Utilidades compartidas por el pueblo y la mina (L4b): suelo, sitios libres y claves de día.

const CAPA_MUNDO := 1


## Clave numérica del día actual (cambia al dormir). Sirve para «una vez al día».
static func clave_dia() -> int:
	return Juego.anio * 10000 + Juego.estacion * 100 + Juego.dia


## Punto del suelo bajo `pos` (rayo de la capa «mundo»). Devuelve Vector3.INF si no hay suelo.
## Empieza `arriba` metros por encima de pos.y (poco, para no tocar tejados) y baja hasta `abajo`.
static func suelo(nodo: Node3D, pos: Vector3, arriba: float = 1.2, abajo: float = 6.0) -> Vector3:
	var esp := nodo.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(pos + Vector3(0, arriba, 0), pos + Vector3(0, -abajo, 0), CAPA_MUNDO)
	var h := esp.intersect_ray(rq)
	if h.is_empty():
		return Vector3.INF
	return h["position"]


## ¿Cabe un cuerpo de `radio` × `alto` en `pos` (suelo) sin tocar nada de la capa «mundo» (u otras capas, con `mascara`; con `elevacion` el cuerpo se levanta esos metros para no contar raíles y otras cosas bajas)?
static func cabe(nodo: Node3D, pos: Vector3, radio: float = 0.4, alto: float = 1.7, mascara: int = CAPA_MUNDO, elevacion: float = 0.0) -> bool:
	var forma := CapsuleShape3D.new()
	forma.radius = radio
	forma.height = alto
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma
	q.collision_mask = mascara
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, alto * 0.5 + 0.15 + elevacion, 0))
	return nodo.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Busca en espiral, alrededor de `centro`, un sitio de suelo libre donde quepa un vecino.
## Si no encuentra ninguno devuelve el suelo bajo `centro` (o `centro`).
static func sitio_libre(nodo: Node3D, centro: Vector3, radio_cuerpo: float = 0.4, maximo: float = 5.0) -> Vector3:
	var primero := suelo(nodo, centro)
	var r := 0.0
	while r <= maximo:
		var pasos := 1 if r == 0.0 else int(ceilf(TAU * r / 0.7))
		for i in pasos:
			var a := TAU * float(i) / float(pasos)
			var p := centro + Vector3(cos(a), 0, sin(a)) * r
			var s := suelo(nodo, p)
			if s == Vector3.INF or absf(s.y - centro.y) > 1.1:
				continue
			if cabe(nodo, s, radio_cuerpo):
				return s
		r += 0.6
	return primero if primero != Vector3.INF else centro


## Una caja de sólido (StaticBody3D de la capa mundo) con malla y color, para objetos sencillos.
static func caja(padre: Node3D, tam: Vector3, pos: Vector3, color: Color, con_colision: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = pos
	padre.add_child(mi)
	if con_colision:
		var cuerpo := StaticBody3D.new()
		cuerpo.collision_layer = CAPA_MUNDO
		cuerpo.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = tam
		cs.shape = bs
		cuerpo.add_child(cs)
		cuerpo.position = pos
		padre.add_child(cuerpo)
	return mi
