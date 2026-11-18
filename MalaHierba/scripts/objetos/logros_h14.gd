extends RefCounted
## Catálogo y evaluación del tablero de logros del Valle del Granado (H14).

const ZONAS_EXPLORACION: Array[String] = [
	"bosque_norte", "costa_lago", "robledal_niebla", "ruinas_valle", "sierra_mirador",
]

const DEFINICIONES: Array[Dictionary] = [
	{
		"id": "primera_cosecha",
		"nombre": "Manos a la tierra",
		"descripcion": "Cosecha tu primer cultivo en El Granado.",
		"icono": "logro_cosecha",
		"categoria": "Granja",
	},
	{
		"id": "gran_cosecha",
		"nombre": "Granero lleno",
		"descripcion": "Cosecha al menos 30 productos del campo.",
		"icono": "calabaza",
		"categoria": "Granja",
	},
	{
		"id": "primer_abono",
		"nombre": "Alivio en el banco",
		"descripcion": "Realiza tu primer pago de la deuda de la finca.",
		"icono": "logro_riqueza",
		"categoria": "Economía",
	},
	{
		"id": "deuda_saldada",
		"nombre": "El Granado es tuyo",
		"descripcion": "Salda por completo los 5.000 € de la deuda familiar.",
		"icono": "logro_leyenda",
		"categoria": "Economía",
	},
	{
		"id": "ahorrador",
		"nombre": "Monedero holgado",
		"descripcion": "Reúne 2.000 € en caja al mismo tiempo.",
		"icono": "lingote_oro",
		"categoria": "Economía",
	},
	{
		"id": "primer_amigo",
		"nombre": "Vecino de confianza",
		"descripcion": "Alcanza el máximo grado de amistad con un habitante de Villaverde.",
		"icono": "logro_amistad",
		"categoria": "Pueblo",
	},
	{
		"id": "alma_pueblo",
		"nombre": "Alma de Villaverde",
		"descripcion": "Entabla amistad cercana (nivel 1+) con al menos 4 vecinos.",
		"icono": "bocadillo",
		"categoria": "Pueblo",
	},
	{
		"id": "bajada_mina",
		"nombre": "Camino al subsuelo",
		"descripcion": "Desciende hasta el nivel 5 o más profundo en la mina.",
		"icono": "logro_mina",
		"categoria": "Mina",
	},
	{
		"id": "maestro_profundidades",
		"nombre": "Corazón de magma",
		"descripcion": "Alcanza las fallas del nivel 20 de la mina.",
		"icono": "diamante",
		"categoria": "Mina",
	},
	{
		"id": "caza_jefes_1",
		"nombre": "Primer guardián",
		"descripcion": "Derrota a uno de los guardianes jefe de la mina.",
		"icono": "logro_combate",
		"categoria": "Combate",
	},
	{
		"id": "caza_jefes_todos",
		"nombre": "Terror del abismo",
		"descripcion": "Derrota a los 4 guardianes jefe de la mina (niveles 5, 10, 15 y 20).",
		"icono": "logro_jefes",
		"categoria": "Combate",
	},
	{
		"id": "tirador_valle",
		"nombre": "Ojo de halcón",
		"descripcion": "Consigue un arco y prepara flechas para cazar a distancia.",
		"icono": "arco_caza",
		"categoria": "Combate",
	},
	{
		"id": "herrero_gemas",
		"nombre": "Joya del yunque",
		"descripcion": "Engasta una gema en tu equipo en el horno y banco de herrería.",
		"icono": "rubi",
		"categoria": "Forja",
	},
	{
		"id": "pescador_aficionado",
		"nombre": "Primera picada",
		"descripcion": "Captura 3 especies distintas de peces en los ríos y lagos.",
		"icono": "salmon_sierra",
		"categoria": "Pesca",
	},
	{
		"id": "album_completo",
		"nombre": "Leyenda del sedal",
		"descripcion": "Completa las 10 especies del álbum de pesca del valle.",
		"icono": "pez_ciego",
		"categoria": "Pesca",
	},
	{
		"id": "granjero_aves",
		"nombre": "Despertar del corral",
		"descripcion": "Repara el gallinero de la finca y acoge gallinas en él.",
		"icono": "huevo_blanco",
		"categoria": "Granja",
	},
	{
		"id": "apicultor_valle",
		"nombre": "Oro de colmena",
		"descripcion": "Cosecha tu primer tarro de miel del apiario.",
		"icono": "tarro_miel",
		"categoria": "Granja",
	},
	{
		"id": "fogata_nocturna",
		"nombre": "Noche bajo estrellas",
		"descripcion": "Monta o descansa en un campamento portátil en plena naturaleza.",
		"icono": "kit_campamento",
		"categoria": "Aventura",
	},
	{
		"id": "chef_valle",
		"nombre": "Fogones de El Granado",
		"descripcion": "Prepara 5 platos en los fogones o en una hoguera de campamento.",
		"icono": "logro_cocina",
		"categoria": "Cocina",
	},
	{
		"id": "habilidad_nv5",
		"nombre": "Veterano del valle",
		"descripcion": "Sube cualquiera de tus cinco habilidades al nivel 5 o superior.",
		"icono": "logro_habilidad",
		"categoria": "Oficio",
	},
	{
		"id": "explorador_valle",
		"nombre": "Pasos por la sierra",
		"descripcion": "Recorre las 5 zonas naturales del valle (bosque, costa, robledal, ruinas y sierra).",
		"icono": "logro_explora",
		"categoria": "Aventura",
	},
]


static func buscar(id: String) -> Dictionary:
	for d: Dictionary in DEFINICIONES:
		if str(d["id"]) == id:
			return d
	return {}


static func total() -> int:
	return DEFINICIONES.size()


static func ids_cumplidos(juego: Node) -> Array[String]:
	var cumplidos: Array[String] = []
	if juego == null:
		return cumplidos
	var est: Dictionary = juego.get("estadisticas") as Dictionary
	var band: Dictionary = juego.get("banderas") as Dictionary
	var cosechas := int(est.get("cosechas", 0))
	if cosechas >= 1:
		cumplidos.append("primera_cosecha")
	if cosechas >= 30:
		cumplidos.append("gran_cosecha")

	var deuda_pagada := int(juego.call("deuda_pagada"))
	if deuda_pagada > 0:
		cumplidos.append("primer_abono")
	if int(juego.get("deuda")) <= 0:
		cumplidos.append("deuda_saldada")
	if int(juego.get("dinero")) >= 2000:
		cumplidos.append("ahorrador")

	var amigos_nv1 := 0
	var amigos_nv2 := 0
	for npc_id: String in Datos.ids_npc():
		var nv := int(juego.call("nivel_amistad", npc_id))
		if nv >= 1:
			amigos_nv1 += 1
		if nv >= 2:
			amigos_nv2 += 1
	if amigos_nv2 >= 1:
		cumplidos.append("primer_amigo")
	if amigos_nv1 >= 4:
		cumplidos.append("alma_pueblo")

	var max_mina := int(band.get("mina_max_nivel", 1))
	if max_mina >= 5:
		cumplidos.append("bajada_mina")
	if max_mina >= 20:
		cumplidos.append("maestro_profundidades")

	var jefes_raw: Variant = band.get("jefes_derrotados", [])
	var num_jefes := (jefes_raw as Array).size() if jefes_raw is Array else 0
	if num_jefes >= 1:
		cumplidos.append("caza_jefes_1")
	if num_jefes >= 4:
		cumplidos.append("caza_jefes_todos")

	if int(juego.call("cantidad", "arco_leo")) + int(juego.call("cantidad", "arco_caza")) > 0 \
			or int(est.get("flechas_disparadas", 0)) > 0:
		cumplidos.append("tirador_valle")

	var tiene_engaste := int(est.get("gemas_engastadas", 0)) > 0
	if not tiene_engaste:
		for item: Variant in juego.call("listar_engastables") as Array:
			if item is Dictionary and not ((item as Dictionary).get("gemas", []) as Array).is_empty():
				tiene_engaste = true
				break
	if tiene_engaste:
		cumplidos.append("herrero_gemas")

	var alb_pesca: Dictionary = juego.call("album_pesca") as Dictionary
	var peces := alb_pesca.size()
	if peces >= 3:
		cumplidos.append("pescador_aficionado")
	if peces >= PescaAvanzada.ESPECIES.size():
		cumplidos.append("album_completo")

	var gan: Dictionary = juego.call("ganado_estado") as Dictionary
	var gal: Dictionary = gan.get("gallinero", {}) as Dictionary
	if bool(gal.get("reparado", false)) and int(gal.get("gallinas", 0)) > 0:
		cumplidos.append("granjero_aves")

	if int(est.get("miel_cosechada", 0)) >= 1 or int(juego.call("cantidad", "tarro_miel")) > 0:
		cumplidos.append("apicultor_valle")

	var camp: Dictionary = juego.call("campamento_estado") as Dictionary
	if not camp.is_empty() or int(est.get("descansos_campamento", 0)) >= 1:
		cumplidos.append("fogata_nocturna")

	if int(est.get("platos_cocinados", 0)) >= 5:
		cumplidos.append("chef_valle")

	var hab_max := 1
	for h_id: String in juego.get("HABILIDADES_ORDEN"):
		hab_max = maxi(hab_max, int(juego.call("nivel_habilidad", h_id)))
	if hab_max >= 5:
		cumplidos.append("habilidad_nv5")

	var vis_raw: Variant = band.get("zonas_visitadas", [])
	if vis_raw is Array:
		var vis := vis_raw as Array
		var todas := true
		for z: String in ZONAS_EXPLORACION:
			if not vis.has(z):
				todas = false
				break
		if todas:
			cumplidos.append("explorador_valle")

	return cumplidos
