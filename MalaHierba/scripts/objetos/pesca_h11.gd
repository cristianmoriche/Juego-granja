class_name PescaAvanzada
extends RefCounted
## Lógica pura de especies por zona/hora/estación/clima, cebos fabricables y física del sedal (H11).

const ESPECIES_ORDEN: Array[String] = [
	"trucha", "carpa", "perca", "tenca", "barbo",
	"lucio", "anguila", "salmon_sierra", "esturion", "pez_ciego",
]

const ESPECIES := {
	"trucha": {
		"nombre": "Trucha de río", "rareza": "Común", "zonas": ["bosque_norte", "robledal_niebla", "sierra_mirador", "ruinas_valle", "costa_lago"],
		"horas": [360, 1320], "estaciones": [0, 1, 2, 3], "climas": ["sol", "lluvia", "tormenta"],
		"cebos": ["cebo_masilla", "cebo_mosca"], "peso": 1.4, "fuerza": 0.48, "resistencia": 100.0,
		"cm": [22.0, 42.0], "kg": [0.35, 1.45],
		"desc": "Frecuente en ríos fríos y orillas limpias de día.",
	},
	"carpa": {
		"nombre": "Carpa dorada", "rareza": "Común", "zonas": ["costa_lago", "bosque_norte", "ruinas_valle", "robledal_niebla"],
		"horas": [360, 1560], "estaciones": [0, 1, 2], "climas": ["sol", "lluvia"],
		"cebos": ["cebo_lombriz", "cebo_masilla"], "peso": 1.35, "fuerza": 0.44, "resistencia": 95.0,
		"cm": [26.0, 54.0], "kg": [0.60, 2.80],
		"desc": "Prefiere remansos y fondos arcillosos entre primavera y otoño.",
	},
	"perca": {
		"nombre": "Perca del lago", "rareza": "Común", "zonas": ["costa_lago", "ruinas_valle", "bosque_norte"],
		"horas": [420, 1260], "estaciones": [0, 1, 2, 3], "climas": ["sol", "lluvia", "tormenta"],
		"cebos": ["cebo_masilla", "cebo_lombriz"], "peso": 1.25, "fuerza": 0.52, "resistencia": 108.0,
		"cm": [20.0, 38.0], "kg": [0.30, 1.25],
		"desc": "Abunda junto al muelle y rompeolas de piedra.",
	},
	"tenca": {
		"nombre": "Tenca verdosa", "rareza": "Poco común", "zonas": ["costa_lago", "ruinas_valle", "robledal_niebla"],
		"horas": [480, 1440], "estaciones": [0, 1], "climas": ["sol", "lluvia"],
		"cebos": ["cebo_lombriz", "cebo_masilla"], "peso": 0.95, "fuerza": 0.60, "resistencia": 122.0,
		"cm": [24.0, 46.0], "kg": [0.45, 2.10],
		"desc": "Suele picar en juncos templados de primavera y verano.",
	},
	"barbo": {
		"nombre": "Barbo ibérico", "rareza": "Poco común", "zonas": ["bosque_norte", "robledal_niebla", "sierra_mirador"],
		"horas": [360, 1200], "estaciones": [0, 1, 2], "climas": ["sol", "lluvia"],
		"cebos": ["cebo_lombriz", "cebo_mosca"], "peso": 0.95, "fuerza": 0.66, "resistencia": 130.0,
		"cm": [28.0, 56.0], "kg": [0.65, 2.60],
		"desc": "Nada en corrientes vivas; responde bien a la lombriz.",
	},
	"lucio": {
		"nombre": "Lucio real", "rareza": "Raro", "zonas": ["costa_lago", "robledal_niebla", "bosque_norte"],
		"horas": [420, 1380], "estaciones": [0, 2, 3], "climas": ["sol", "lluvia", "tormenta"],
		"cebos": ["cebo_mosca", "cebo_lombriz"], "peso": 0.62, "fuerza": 0.88, "resistencia": 158.0,
		"cm": [48.0, 96.0], "kg": [1.80, 7.50],
		"desc": "Depredador largo y feroz de tirón violento sobre el sedal.",
	},
	"anguila": {
		"nombre": "Anguila de río", "rareza": "Poco común", "zonas": ["robledal_niebla", "ruinas_valle", "bosque_norte", "mina_interior"],
		"horas": [1080, 1560], "estaciones": [0, 1, 2, 3], "climas": ["sol", "lluvia", "tormenta"],
		"cebos": ["cebo_lombriz", "cebo_luminoso"], "peso": 0.85, "fuerza": 0.72, "resistencia": 135.0,
		"cm": [42.0, 88.0], "kg": [0.40, 2.40],
		"desc": "Activa al anochecer, con lluvia o en aguas profundas de gruta.",
	},
	"salmon_sierra": {
		"nombre": "Salmón de torrente", "rareza": "Raro", "zonas": ["sierra_mirador", "bosque_norte", "robledal_niebla"],
		"horas": [360, 1140], "estaciones": [2, 3], "climas": ["sol", "lluvia"],
		"cebos": ["cebo_mosca"], "peso": 0.58, "fuerza": 0.94, "resistencia": 170.0,
		"cm": [44.0, 82.0], "kg": [1.50, 5.80],
		"desc": "Remonta las aguas frías en otoño e invierno ante moscas artificiales.",
	},
	"esturion": {
		"nombre": "Esturión dorado", "rareza": "Trofeo", "zonas": ["costa_lago"],
		"horas": [360, 1560], "estaciones": [0, 1, 2, 3], "climas": ["lluvia", "tormenta"],
		"cebos": ["cebo_mosca", "cebo_masilla"], "peso": 0.36, "fuerza": 1.15, "resistencia": 210.0,
		"cm": [82.0, 148.0], "kg": [5.50, 18.40],
		"desc": "Legendario gigante acorazado del lago en días de lluvia o tormenta.",
	},
	"pez_ciego": {
		"nombre": "Pez ciego de cueva", "rareza": "Trofeo", "zonas": ["mina_interior"],
		"horas": [360, 1560], "estaciones": [0, 1, 2, 3], "climas": ["sol", "lluvia", "tormenta"],
		"cebos": ["cebo_luminoso"], "peso": 1.15, "fuerza": 0.78, "resistencia": 148.0,
		"cm": [16.0, 32.0], "kg": [0.22, 0.95],
		"desc": "Especie albina traslúcida única de los lagos subterráneos de la mina.",
	},
}

const RECETAS_CEBO := [
	{"id": "cebo_lombriz", "nombre": "Cebo de lombriz (×4)", "entrega": 4, "ingredientes": [{"id": "fibra", "cantidad": 2}, {"id": "patata", "cantidad": 1}]},
	{"id": "cebo_masilla", "nombre": "Masilla de pan dulce (×5)", "entrega": 5, "ingredientes": [{"id": "pan", "cantidad": 1}]},
	{"id": "cebo_mosca", "nombre": "Mosca artificial (×3)", "entrega": 3, "ingredientes": [{"id": "fibra", "cantidad": 2}, {"id": "cobre", "cantidad": 1}]},
	{"id": "cebo_luminoso", "nombre": "Cebo luminiscente (×3)", "entrega": 3, "ingredientes": [{"id": "cuarzo", "cantidad": 1}, {"id": "mora_silvestre", "cantidad": 2}]},
]


static func elegir_especie(zona: String, minutos: int, estacion: int, clima: String, cebo: String = "") -> String:
	var candidatos: Array[Dictionary] = []
	for sid: String in ESPECIES_ORDEN:
		var sp: Dictionary = ESPECIES[sid]
		if not (sp["zonas"] as Array).has(zona):
			continue
		var hrs := sp["horas"] as Array
		# Con cebo luminoso o en mina se ignora la restricción diurna/nocturna parcial
		var en_hora := (minutos >= int(hrs[0]) and minutos <= int(hrs[1]))
		if sid == "anguila" and (clima in ["lluvia", "tormenta"] or zona == "mina_interior"):
			en_hora = true
		if not en_hora and cebo != "cebo_luminoso":
			continue
		if not (sp["estaciones"] as Array).has(estacion):
			continue
		if not (sp["climas"] as Array).has(clima) and cebo == "":
			continue
		var peso := float(sp["peso"])
		if not cebo.is_empty() and (sp["cebos"] as Array).has(cebo):
			peso *= 2.8 if sid in ["pez_ciego", "salmon_sierra", "esturion", "anguila"] else 1.75
		elif not (sp["climas"] as Array).has(clima):
			peso *= 0.25
		if peso > 0.0:
			candidatos.append({"id": sid, "peso": peso})

	if candidatos.is_empty():
		return "pez_ciego" if zona == "mina_interior" else "trucha"

	var total := 0.0
	for c: Dictionary in candidatos:
		total += float(c["peso"])
	var r := randf() * total
	var acum := 0.0
	for c: Dictionary in candidatos:
		acum += float(c["peso"])
		if r <= acum:
			return str(c["id"])
	return str(candidatos[-1]["id"])


static func generar_ejemplar(especie_id: String, cebo: String = "", suerte: float = 0.0) -> Dictionary:
	var sp: Dictionary = ESPECIES.get(especie_id, ESPECIES["trucha"]) as Dictionary
	var factor := clampf(randf() * 0.72 + (0.28 if cebo == "cebo_masilla" else 0.14) + suerte * 0.25, 0.0, 1.0)
	var cm_r := sp["cm"] as Array
	var kg_r := sp["kg"] as Array
	var cm := lerpf(float(cm_r[0]), float(cm_r[1]), factor)
	var kg := lerpf(float(kg_r[0]), float(kg_r[1]), pow(factor, 1.15))
	return {
		"id": especie_id,
		"cm": roundf(cm * 10.0) / 10.0,
		"kg": roundf(kg * 100.0) / 100.0,
		"fuerza": float(sp["fuerza"]),
		"resistencia": float(sp["resistencia"]),
		"rareza": str(sp["rareza"]),
	}


static func nuevo_estado_lucha(especie_id: String, habilidad_nv: int = 1) -> Dictionary:
	var sp: Dictionary = ESPECIES.get(especie_id, ESPECIES["trucha"]) as Dictionary
	return {
		"especie": especie_id,
		"tension": 0.24,
		"cansancio": 0.0,
		"resistencia_max": float(sp.get("resistencia", 100.0)),
		"fuerza": float(sp.get("fuerza", 0.55)),
		"tirando": false,
		"fase_t": 1.1,
		"tiempo": 0.0,
		"habilidad": maxi(1, habilidad_nv),
		"resultado": "curso",
	}


## Simula un paso de física del sedal durante la captura; usado tanto en tiempo real como en pruebas.
static func simular_paso(est: Dictionary, recogiendo: bool, delta: float) -> Dictionary:
	if str(est.get("resultado", "curso")) != "curso":
		return est
	var dt := clampf(delta, 0.0, 0.1)
	est["tiempo"] = float(est.get("tiempo", 0.0)) + dt
	var fuerza := float(est.get("fuerza", 0.55))
	var res_max := maxf(40.0, float(est.get("resistencia_max", 100.0)))
	var tension := float(est.get("tension", 0.25))
	var cansancio := float(est.get("cansancio", 0.0))
	var tirando := bool(est.get("tirando", false))
	var fase_t := float(est.get("fase_t", 1.0)) - dt
	if fase_t <= 0.0:
		tirando = not tirando
		fase_t = lerpf(0.85, 1.75, 0.5) if tirando else lerpf(1.25, 2.1, 0.5)
	est["tirando"] = tirando
	est["fase_t"] = fase_t

	var bono_hab := 1.0 + float(maxi(1, int(est.get("habilidad", 1))) - 1) * 0.06
	if tirando:
		if recogiendo:
			tension += (0.58 * fuerza + 0.14) * dt
			cansancio += (14.0 * bono_hab / res_max) * dt
		else:
			tension -= 0.48 * dt
			cansancio += (4.0 / res_max) * dt
	else:
		if recogiendo:
			tension += (0.14 * fuerza + 0.03) * dt
			cansancio += (44.0 * bono_hab / res_max) * dt
		else:
			tension -= 0.56 * dt
			cansancio = maxf(0.0, cansancio - (5.0 / res_max) * dt)

	est["tension"] = clampf(tension, 0.0, 1.05)
	est["cansancio"] = clampf(cansancio, 0.0, 1.0)
	if float(est["tension"]) >= 1.0:
		est["resultado"] = "roto"
	elif float(est["cansancio"]) >= 1.0:
		est["resultado"] = "capturado"
	return est
