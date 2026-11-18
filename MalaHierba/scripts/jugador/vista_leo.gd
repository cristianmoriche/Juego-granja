extends RefCounted
## Separa la cabeza de Leo en memoria, conservando material PBR, pesos y malla originales.
## La exportación de Leo reúne cuerpo, barba, pelo y gorra en una única superficie.

const HUESO_CABEZA := "DEF-spine.006"
const HUESOS_CABEZA := ["DEF-spine.004", "DEF-spine.005", HUESO_CABEZA]

static var _cuerpo: ArrayMesh
static var _cabeza: ArrayMesh


static func olvidar() -> void:
	_cuerpo = null
	_cabeza = null

var ancla_ojos: BoneAttachment3D
var malla: MeshInstance3D
var sombra: MeshInstance3D
var original: Mesh


func preparar(modelo: Node3D, esqueleto: Skeleton3D) -> void:
	if esqueleto.find_bone(HUESO_CABEZA) == -1:
		return
	malla = modelo.find_child("Leo_malla", true, false) as MeshInstance3D
	if malla == null or not malla.mesh is ArrayMesh or malla.skin == null:
		return
	original = malla.mesh
	if _cuerpo == null:
		_separar(original as ArrayMesh, malla.skin, esqueleto)
	if _cuerpo == null:
		return

	ancla_ojos = BoneAttachment3D.new()
	ancla_ojos.name = "CabezaVista"
	ancla_ojos.bone_name = HUESO_CABEZA
	esqueleto.add_child(ancla_ojos)

	sombra = MeshInstance3D.new()
	sombra.name = "SombraCabeza"
	sombra.mesh = _cabeza
	sombra.skin = malla.skin
	sombra.skeleton = malla.skeleton
	sombra.transform = malla.transform
	sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	sombra.visible = false
	malla.add_sibling(sombra)


func mostrar_primera(primera: bool) -> void:
	if sombra == null or sombra.visible == primera:
		return
	malla.mesh = _cuerpo if primera else original
	sombra.visible = primera


static func _separar(malla_original: ArrayMesh, piel: Skin, esqueleto: Skeleton3D) -> void:
	var cuerpo := ArrayMesh.new()
	var cabeza := ArrayMesh.new()
	var ligados: Dictionary = {}
	for i in piel.get_bind_count():
		var nombre := piel.get_bind_name(i)
		var hueso := piel.get_bind_bone(i)
		if nombre.is_empty() and hueso >= 0 and hueso < esqueleto.get_bone_count():
			nombre = esqueleto.get_bone_name(hueso)
		if String(nombre) in HUESOS_CABEZA:
			ligados[i] = true
	if ligados.is_empty():
		return
	for s in malla_original.get_surface_count():
		var datos := malla_original.surface_get_arrays(s)
		var vertices: PackedVector3Array = datos[Mesh.ARRAY_VERTEX]
		var huesos: PackedInt32Array = datos[Mesh.ARRAY_BONES]
		var pesos: PackedFloat32Array = datos[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = datos[Mesh.ARRAY_INDEX]
		if indices.is_empty() or pesos.is_empty():
			return
		var influencias := int(huesos.size() / float(vertices.size()))
		var cabeza_por_vertice := PackedFloat32Array()
		cabeza_por_vertice.resize(vertices.size())
		for i in vertices.size():
			for j in influencias:
				var entrada := i * influencias + j
				if ligados.has(huesos[entrada]):
					cabeza_por_vertice[i] += pesos[entrada]

		var indices_cabeza := PackedInt32Array()
		var indices_cuerpo := PackedInt32Array()
		for i in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			if (cabeza_por_vertice[a] + cabeza_por_vertice[b] + cabeza_por_vertice[c]) >= 1.5:
				indices_cabeza.append(a)
				indices_cabeza.append(b)
				indices_cabeza.append(c)
			else:
				indices_cuerpo.append(a)
				indices_cuerpo.append(b)
				indices_cuerpo.append(c)
		var flags := malla_original.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		var material := malla_original.surface_get_material(s)
		# Desde dentro de una prenda no deben aparecer sus caras traseras en la cámara.
		var material_cuerpo := material as BaseMaterial3D
		if material_cuerpo != null and material_cuerpo.cull_mode != BaseMaterial3D.CULL_BACK:
			material_cuerpo = material_cuerpo.duplicate() as BaseMaterial3D
			material_cuerpo.cull_mode = BaseMaterial3D.CULL_BACK
		_anadir_superficie(cuerpo, datos, indices_cuerpo, material_cuerpo if material_cuerpo != null else material, flags)
		_anadir_superficie(cabeza, datos, indices_cabeza, material, flags)
	if cuerpo.get_surface_count() > 0 and cabeza.get_surface_count() > 0:
		_cuerpo = cuerpo
		_cabeza = cabeza


static func _anadir_superficie(destino: ArrayMesh, datos: Array, indices: PackedInt32Array,
		material: Material, flags: int) -> void:
	if indices.is_empty():
		return
	datos[Mesh.ARRAY_INDEX] = indices
	destino.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, datos, [], {}, flags)
	destino.surface_set_material(destino.get_surface_count() - 1, material)
