class_name HorizonteH05
extends Node3D
## Paisaje lejano de montañas, valles y silueta de bosque en el horizonte exterior (H05).
## Sin colisiones y en una sola malla/MultiMesh ligera para mantener el rendimiento en Alto.

const SHADER_HORIZONTE := """shader_type spatial;
render_mode cull_back, specular_disabled;
uniform vec4 color_valle : source_color = vec4(0.16, 0.24, 0.17, 1.0);
uniform vec4 color_cumbre : source_color = vec4(0.24, 0.28, 0.29, 1.0);
uniform vec4 color_nieve : source_color = vec4(0.76, 0.80, 0.84, 1.0);
uniform float factor_nieve = 0.0;
varying float altura_norm;
varying vec3 mundo;
void vertex() {
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	altura_norm = clamp(VERTEX.y / 65.0, 0.0, 1.0);
}
void fragment() {
	vec3 col = mix(color_valle.rgb, color_cumbre.rgb, smoothstep(0.08, 0.72, altura_norm));
	float nieve = smoothstep(0.45, 0.88, altura_norm) * clamp(factor_nieve, 0.0, 1.0);
	col = mix(col, color_nieve.rgb, nieve * 0.72);
	float dist = length(mundo.xz);
	float bruma = smoothstep(140.0, 390.0, dist);
	col = mix(col, vec3(0.48, 0.56, 0.64), bruma * 0.55);
	ALBEDO = col;
	ROUGHNESS = 0.96;
}
"""


static func crear(mapa: Node3D, id_mapa: String) -> HorizonteH05:
	var h := HorizonteH05.new()
	h.name = "HorizonteH05"
	mapa.add_child(h)
	h._construir(id_mapa)
	return h


func _construir(id_mapa: String) -> void:
	_construir_cordillera(id_mapa)
	if Juego.has_signal("estacion_cambiada") and not Juego.estacion_cambiada.is_connected(_actualizar_estacion):
		Juego.estacion_cambiada.connect(_actualizar_estacion)


var _mat_monte: ShaderMaterial = null


func _actualizar_estacion() -> void:
	if _mat_monte != null:
		_mat_monte.set_shader_parameter("factor_nieve", 1.0 if Juego.estacion == 3 else (0.35 if id_sierra_activa() else 0.0))


var _es_sierra := false


func id_sierra_activa() -> bool:
	return _es_sierra


func _construir_cordillera(id_mapa: String) -> void:
	_es_sierra = (id_mapa == "sierra_mirador" or id_mapa == "mina_exterior")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs := 84
	var radios := [130.0, 185.0, 265.0, 380.0]
	var anillo_pts: Array[Array] = []
	var semilla := float(hash(id_mapa) & 1023) * 0.017

	for ri in radios.size():
		var r_base: float = radios[ri]
		var pts: Array[Vector3] = []
		for si in segs + 1:
			var ang := float(si) / float(segs) * TAU
			var cx := cos(ang)
			var sz := sin(ang)
			var h := -1.5
			if ri > 0:
				var onda := (
					sin(ang * 3.0 + semilla) * 0.45
					+ cos(ang * 7.0 - semilla * 1.4) * 0.32
					+ sin(ang * 13.0 + semilla * 2.1) * 0.23
				)
				var base_alt := 12.0 if ri == 1 else (30.0 if ri == 2 else 54.0)
				if id_mapa == "sierra_mirador":
					base_alt *= 1.28
				elif id_mapa == "costa_lago" and sz > 0.12:
					# Al sur de Costa del Lago se abre el espejo del lago hasta la orilla lejana.
					base_alt *= clampf(1.0 - (sz - 0.12) * 1.45, 0.04, 1.0)
				h = maxf(-1.8, base_alt * (0.68 + 0.42 * onda) - (6.0 if ri == 1 else 0.0))
			pts.append(Vector3(cx * r_base, h, sz * r_base))
		anillo_pts.append(pts)

	for ri in radios.size() - 1:
		var a0: Array = anillo_pts[ri]
		var a1: Array = anillo_pts[ri + 1]
		for si in segs:
			var p00: Vector3 = a0[si]
			var p10: Vector3 = a0[si + 1]
			var p01: Vector3 = a1[si]
			var p11: Vector3 = a1[si + 1]
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "CordilleraLejana"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	_mat_monte = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_HORIZONTE
	_mat_monte.shader = sh
	_actualizar_estacion()
	mi.material_override = _mat_monte
	add_child(mi)


func _construir_bosque_lejano(id_mapa: String) -> void:
	var n_pinos := 110
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("horizonte_" + id_mapa)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := 14.0
	var radio := 4.4
	var caras := 5
	for i in caras:
		var a0 := float(i) / float(caras) * TAU
		var a1 := float(i + 1) / float(caras) * TAU
		var p0 := Vector3(cos(a0) * radio, 0.0, sin(a0) * radio)
		var p1 := Vector3(cos(a1) * radio, 0.0, sin(a1) * radio)
		var top := Vector3(0.0, altura, 0.0)
		st.add_vertex(top); st.add_vertex(p1); st.add_vertex(p0)
	st.generate_normals()
	var pino_mesh := st.commit()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.20, 0.12) if Juego.estacion != 2 else Color(0.22, 0.21, 0.12)
	if Juego.estacion == 3:
		mat.albedo_color = Color(0.28, 0.34, 0.36)
	mat.roughness = 0.98
	mat.metallic_specular = 0.04
	pino_mesh.surface_set_material(0, mat)

	var xfs: Array[Transform3D] = []
	for _k in n_pinos:
		var ang := rng.randf_range(0.0, TAU)
		if id_mapa == "costa_lago" and sin(ang) > 0.15:
			continue
		var r := rng.randf_range(122.0, 178.0)
		var esc := rng.randf_range(0.85, 1.75)
		var pos := Vector3(cos(ang) * r, rng.randf_range(-1.0, 5.5), sin(ang) * r)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * esc), pos))

	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pino_mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SiluetaBosqueLejano"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
