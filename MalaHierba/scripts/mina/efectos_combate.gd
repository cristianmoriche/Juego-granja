extends RefCounted
## Salpicadura, polvo o esquirlas según la superficie golpeada.

const PERFIL := {
	"carne": [Color(0.29, 0.045, 0.029), 0.045, 8, 0.33],
	"roca": [Color(0.39, 0.34, 0.27), 0.093, 17, 0.46],
	"cristal": [Color(0.48, 0.73, 0.83), 0.052, 13, 0.44],
}


static func impacto(padre: Node, lugar: Vector3, direccion: Vector3, material: String, guardia: bool) -> void:
	if DisplayServer.get_name() == "headless" or padre == null:
		return
	var perfil: Array = PERFIL.get(material, PERFIL["carne"])
	Audio.reproducir_posicional("combate_bloqueo" if guardia else "combate_impacto_" + material, lugar, padre, -3.0)
	var particulas := CPUParticles3D.new()
	particulas.name = "Impacto_" + material
	particulas.one_shot = true
	particulas.emitting = false
	particulas.amount = perfil[2]
	particulas.lifetime = perfil[3]
	particulas.explosiveness = 1.0
	particulas.direction = (-direccion * 0.55 + Vector3.UP).normalized()
	particulas.spread = 64.0
	particulas.initial_velocity_min = 0.5
	particulas.initial_velocity_max = 2.5
	particulas.scale_amount_min = 0.21
	particulas.scale_amount_max = 1.0
	var caida := Curve.new()
	caida.add_point(Vector2(0.0, 1.0))
	caida.add_point(Vector2(1.0, 0.0))
	particulas.scale_amount_curve = caida
	particulas.gravity = Vector3.DOWN * (4.0 if material == "roca" else 6.0)
	var fragmento := SphereMesh.new()
	fragmento.radial_segments = 5
	fragmento.rings = 3
	fragmento.radius = perfil[1]
	fragmento.height = fragmento.radius * (3.1 if material == "cristal" else 1.45)
	var acabado := StandardMaterial3D.new()
	acabado.albedo_color = perfil[0]
	acabado.roughness = 0.31 if material == "cristal" else 0.88
	if material == "cristal":
		acabado.metallic = 0.32
		acabado.emission_enabled = true
		acabado.emission = Color(0.09, 0.23, 0.31)
	fragmento.material = acabado
	particulas.mesh = fragmento
	padre.add_child(particulas)
	particulas.global_position = lugar
	particulas.finished.connect(particulas.queue_free)
	particulas.emitting = true
