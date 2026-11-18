class_name Herreria
extends RefCounted
## Definiciones de fundición en horno, temple con lingotes y engaste de gemas (H10).

const COSTE_ENGASTE := 35
const COSTE_DESENGASTE := 45
const PROB_ROTURA_DESENGASTE := 0.35
const TEMPLE_MAX := 3

## Recetas del horno de fundición. `comb_alt` permite usar carbón vegetal O leña (`madera`).
const RECETAS_HORNO := [
	{
		"id": "fundir_carbon",
		"nombre": "Carbón vegetal (×2)",
		"mineral": "madera",
		"cantidad": 3,
		"combustible": "",
		"coste_comb": 0,
		"lingote": "carbon",
		"entrega": 2,
		"dinero": 5,
		"minutos": 40,
		"desc": "Carboniza madera lentamente dentro del horno para obtener carbón de fragua."
	},
	{
		"id": "fundir_cobre",
		"nombre": "Lingote de cobre",
		"mineral": "cobre",
		"cantidad": 3,
		"combustible": "carbon",
		"coste_comb": 1,
		"madera_alt": 2,
		"lingote": "lingote_cobre",
		"entrega": 1,
		"dinero": 12,
		"minutos": 50,
		"desc": "Funde 3 menas de cobre con carbón o madera en un lingote puro para armas y aperos."
	},
	{
		"id": "fundir_hierro",
		"nombre": "Lingote de hierro",
		"mineral": "hierro",
		"cantidad": 3,
		"combustible": "carbon",
		"coste_comb": 1,
		"madera_alt": 2,
		"lingote": "lingote_hierro",
		"entrega": 1,
		"dinero": 18,
		"minutos": 65,
		"desc": "Funde 3 menas de hierro en barra resistente apta para temple pesado."
	},
	{
		"id": "fundir_oro",
		"nombre": "Lingote de oro",
		"mineral": "oro",
		"cantidad": 2,
		"combustible": "carbon",
		"coste_comb": 1,
		"madera_alt": 2,
		"lingote": "lingote_oro",
		"entrega": 1,
		"dinero": 28,
		"minutos": 80,
		"desc": "Refina 2 pepitas de oro para temple maestro y engastes de alto valor."
	},
]

const GEMAS := {
	"oro": {
		"nombre": "Oro (Fortuna minera)",
		"resumen": "+18 % suerte minera · +12 % valor de botín",
		"color": Color(1.0, 0.80, 0.25),
		"suerte_minera": 0.18,
		"bono_botin": 0.12,
	},
	"amatista": {
		"nombre": "Amatista (Vigor)",
		"resumen": "-18 % gasto de resistencia en combate",
		"color": Color(0.75, 0.38, 1.0),
		"ahorro_resistencia": 0.18,
	},
	"rubi": {
		"nombre": "Rubí (Fuego)",
		"resumen": "+18 % daño de fuego y quemadura al golpear",
		"color": Color(1.0, 0.32, 0.16),
		"dano_fuego": 0.18,
		"quemadura": 5.0,
	},
	"diamante": {
		"nombre": "Diamante (Cristal/Rotura)",
		"resumen": "+16 % daño cristal, rompe escudos / +14 % bloqueo",
		"color": Color(0.45, 0.88, 1.0),
		"dano_cristal": 0.16,
		"rompe_guardia": true,
		"bono_bloqueo": 0.14,
	},
	"ambar_valle": {
		"nombre": "Ámbar del Valle (Vitalidad)",
		"resumen": "+4 salud al golpear · +3 defensa en equipo",
		"color": Color(1.0, 0.62, 0.16),
		"robo_vida": 4.0,
		"bono_defensa": 3.0,
	},
}

const ORDEN_GEMAS: Array[String] = ["oro", "amatista", "rubi", "diamante", "ambar_valle"]


static func es_engastable(id: String) -> bool:
	if id.is_empty():
		return false
	var o := Datos.objeto(id)
	var tipo := str(o.get("tipo", ""))
	if tipo == "arma":
		return true
	if tipo == "equipo":
		var ranura := str(o.get("ranura_equipo", ""))
		return ranura in ["escudo", "casco", "peto", "botas", "carcaj"]
	return false


static func huecos_para(id: String) -> int:
	if not es_engastable(id):
		return 0
	var grado := int(Datos.objeto(id).get("grado", 0))
	return clampi(grado + 1, 1, 3)


static func receta_horno(id_receta: String) -> Dictionary:
	for r: Dictionary in RECETAS_HORNO:
		if str(r["id"]) == id_receta:
			return r
	return {}


static func stats_pieza(id: String, gemas: Array, temple: int = 0) -> Dictionary:
	var o := Datos.objeto(id)
	var dano_base := float(o.get("dano", 0.0))
	var def_base := float(o.get("defensa", 0.0))
	var red_base := float(o.get("reduccion", 0.0))
	var t := clampi(temple, 0, TEMPLE_MAX)
	var dano := dano_base * (1.0 + 0.10 * float(t)) if dano_base > 0.0 else 0.0
	var defensa := def_base + (2.0 * float(t) if def_base > 0.0 else 0.0)
	var reduccion := minf(0.94, red_base + (0.04 * float(t) if red_base > 0.0 else 0.0))
	var suerte := 0.0
	var ahorro_res := 0.0
	var bono_dano := 0.0
	var quemadura := 0.0
	var robo_vida := 0.0
	var rompe := bool(o.get("rompe_guardia", false))
	for g: Variant in gemas:
		var gd: Dictionary = GEMAS.get(str(g), {}) as Dictionary
		if gd.is_empty():
			continue
		suerte += float(gd.get("suerte_minera", 0.0))
		ahorro_res += float(gd.get("ahorro_resistencia", 0.0))
		var bd := float(gd.get("dano_fuego", 0.0)) + float(gd.get("dano_cristal", 0.0))
		bono_dano += bd
		if dano_base > 0.0:
			dano += dano_base * bd
		quemadura += float(gd.get("quemadura", 0.0))
		robo_vida += float(gd.get("robo_vida", 0.0))
		if bool(gd.get("rompe_guardia", false)):
			rompe = true
		defensa += float(gd.get("bono_defensa", 0.0))
		if red_base > 0.0:
			reduccion = minf(0.95, reduccion + float(gd.get("bono_bloqueo", 0.0)) * 0.5)
	return {
		"huecos": huecos_para(id),
		"temple": t,
		"dano": dano,
		"defensa": defensa,
		"reduccion": reduccion,
		"suerte_minera": suerte,
		"ahorro_resistencia": minf(0.60, ahorro_res),
		"bono_dano": bono_dano,
		"quemadura": quemadura,
		"robo_vida": robo_vida,
		"rompe_guardia": rompe,
	}


static func lingote_para_grado(grado: int) -> String:
	match clampi(grado, 0, 2):
		0: return "lingote_cobre"
		1: return "lingote_hierro"
		_: return "lingote_oro"
