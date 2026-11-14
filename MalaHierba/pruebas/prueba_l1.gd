extends Node
## Prueba del carril L1 (mapas): carga los cuatro mapas uno a uno y comprueba marcadores obligatorios, colisión bajo
## el punto de aparición y número de instancias. Imprime PRUEBA OK o PRUEBA FALLO: <motivo> y sale con 0 o 1.
## Uso: godot.ps1 --headless --path <proyecto> --scene res://pruebas/prueba_l1.tscn

const OBLIGATORIOS := {
	"granja": ["Spawn_Protagonista", "Puerta_Cabana", "Salida_Pueblo", "Llegada_Pueblo"],
	"pueblo": ["Spawn_Protagonista", "Salida_Minas", "Salida_Granja", "Llegada_Granja", "Llegada_Minas"],
	"mina_exterior": ["Spawn_Protagonista", "Salida_Pueblo", "Llegada_Pueblo", "Entrada_Mina", "Llegada_Exterior"],
	"mina_interior": ["Entrada_Interior", "Salida_Exterior", "Bajada_Nivel_2", "Llegada_Interior"],
}
const ZONAS := {
	"granja": ["Zona_Cultivo_1"],
	"mina_interior": ["Zona_Rocas"],
}
const PUNTO_SUELO := {
	"granja": "Spawn_Protagonista",
	"pueblo": "Spawn_Protagonista",
	"mina_exterior": "Spawn_Protagonista",
	"mina_interior": "Llegada_Interior",
}
const MIN_INSTANCIAS := {"granja": 100, "pueblo": 100, "mina_exterior": 100, "mina_interior": 0}

var fallos: Array[String] = []


func _ready() -> void:
	await _probar()
	if fallos.is_empty():
		print("PRUEBA OK")
		get_tree().quit(0)
	else:
		print("PRUEBA FALLO: " + "; ".join(fallos))
		get_tree().quit(1)


func _probar() -> void:
	var solo: String = OS.get_environment("L1_SOLO")
	for id: String in OBLIGATORIOS.keys():
		if solo != "" and solo != id:
			continue
		var c := CargadorMapa.new()
		c.id_mapa = id
		add_child(c)
		print("[%s] cargado en %d ms · %d instancias en %d trozos · %d marcadores" % [id, c.tiempo_carga_ms, c.num_instancias, c.num_trozos_multimesh, c.nodo_marcadores.get_child_count()])
		if not c.listo:
			fallos.append("%s no terminó de cargar" % id)
		if c.tiempo_carga_ms > 5000:
			fallos.append("%s tarda %d ms (> 5000)" % [id, c.tiempo_carga_ms])
		for m: String in OBLIGATORIOS[id]:
			if c.marcador(m) == null:
				fallos.append("%s: falta el marcador %s" % [id, m])
		for z: String in ZONAS.get(id, []):
			var mz := c.marcador(z)
			if mz == null or not mz.has_meta("tam"):
				fallos.append("%s: falta la zona %s" % [id, z])
		if c.num_instancias < int(MIN_INSTANCIAS[id]):
			fallos.append("%s: pocas instancias (%d)" % [id, c.num_instancias])
		if c.aabb_mapa().size.length() < 5.0:
			fallos.append("%s: aabb vacío" % id)
		# colisión bajo el punto de aparición
		await get_tree().physics_frame
		await get_tree().physics_frame
		var mk := c.marcador(String(PUNTO_SUELO[id]))
		if mk != null:
			var p := mk.global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, 1)
			var r := c.get_world_3d().direct_space_state.intersect_ray(q)
			if r.is_empty():
				fallos.append("%s: no hay colisión bajo %s (%s)" % [id, mk.name, str(p)])
			else:
				print("   suelo bajo %s: y=%.2f (marcador y=%.2f)" % [mk.name, r["position"].y, p.y])
		# tipos de marcador
		var n_sp := c.marcadores_de_tipo("spawn").size()
		if n_sp == 0:
			fallos.append("%s: ningún marcador de tipo spawn" % id)
		var sol := c.info_sol()
		print("   sol: %s · cielo: %s · luces: %d" % [str(not sol.is_empty()), str(not c.info_cielo().is_empty()), c.nodo_luces.get_child_count()])
		c.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
