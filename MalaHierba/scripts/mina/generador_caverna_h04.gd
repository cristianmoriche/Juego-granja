class_name GeneradorCavernaH04
extends RefCounted
## Generador procedural de minas grandes (H04) para los niveles 1..20:
## - Niveles 1 y 2: abre paso en la pared este (x=434, z=-15.9) de la cueva clásica y añade un ala
##   procedural multi-sala (~2,6-2,9× superficie total frente a L4b), cofre oculto, atajo y pasarela.
## - Niveles 3..20: caverna multi-sala y multi-altura con rampas suaves, galerías entibadas con raíles
##   y vagonetas, ramales con cofres, pasarelas sobre simas con barandilla, atajo desbloqueable y
##   trozos espaciales de 20×20 m con texturas PBR CC0 por bioma.

const PASO := 2.5
const TAM_TROZO := 20.0
const CAPA_MUNDO := 1
const CAPA_SOLO_JUGADOR := 64

const RUTA_COFRE := "res://assets/mina/cofre_mina.glb"
const RUTA_VAGONETA := "res://assets/mina/vagoneta_mina.glb"
const RUTA_ROCAS_CC0 := [
	"res://assets/mina/roca_pared_01.glb",
	"res://assets/mina/roca_pared_02.glb",
	"res://assets/mina/penasco_01.glb",
	"res://assets/mina/roca_suelo_07.glb",
	"res://assets/mina/roca_suelo_09.glb",
]

const TEXTURAS_BIOMA := {
	"piedra": {
		"pared_dir": "res://assets/texturas/h04/rock_wall_08",
		"pared_pref": "rock_wall_08",
		"suelo_dir": "res://assets/texturas/h04/gravel_floor_02",
		"suelo_pref": "gravel_floor_02",
		"escala_pared": 0.24,
		"escala_suelo": 0.34,
		"tinte_pared": Color(0.86, 0.83, 0.80),
		"tinte_suelo": Color(0.84, 0.80, 0.76),
		"brillo_humedad": 0.0,
	},
	"humeda": {
		"pared_dir": "res://assets/texturas/h04/mossy_rock",
		"pared_pref": "mossy_rock",
		"suelo_dir": "res://assets/texturas/h04/rock_pitted_mossy",
		"suelo_pref": "rock_pitted_mossy",
		"escala_pared": 0.25,
		"escala_suelo": 0.32,
		"tinte_pared": Color(0.76, 0.88, 0.88),
		"tinte_suelo": Color(0.70, 0.82, 0.84),
		"brillo_humedad": 0.28,
	},
	"cristal": {
		"pared_dir": "res://assets/texturas/h04/dark_rock",
		"pared_pref": "dark_rock",
		"suelo_dir": "res://assets/texturas/h04/excavated_soil_wall",
		"suelo_pref": "excavated_soil_wall",
		"escala_pared": 0.25,
		"escala_suelo": 0.32,
		"tinte_pared": Color(0.74, 0.68, 0.94),
		"tinte_suelo": Color(0.70, 0.65, 0.88),
		"brillo_humedad": 0.14,
	},
	"magma": {
		"pared_dir": "res://assets/texturas/h04/cracked_red_ground",
		"pared_pref": "cracked_red_ground",
		"suelo_dir": "res://assets/texturas/h04/burned_ground_01",
		"suelo_pref": "burned_ground_01",
		"escala_pared": 0.26,
		"escala_suelo": 0.34,
		"tinte_pared": Color(0.90, 0.68, 0.60),
		"tinte_suelo": Color(0.82, 0.64, 0.56),
		"brillo_humedad": 0.04,
	},
}

const SHADER_CAVERNAS_PBR := """shader_type spatial;
uniform sampler2D tex_pared_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pared_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pared_rug : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_suelo_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_suelo_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_suelo_rug : filter_linear_mipmap, repeat_enable;
uniform vec4 tinte_pared : source_color = vec4(0.85, 0.82, 0.78, 1.0);
uniform vec4 tinte_suelo : source_color = vec4(0.82, 0.78, 0.74, 1.0);
uniform float escala_pared = 0.24;
uniform float escala_suelo = 0.34;
uniform float humedad = 0.0;

varying vec3 v_wpos;
varying vec3 v_wnorm;

vec4 triplanar_grad(sampler2D t, vec3 uv_p, vec3 w, vec2 dxx, vec2 dxy, vec2 dyx, vec2 dyy, vec2 dzx, vec2 dzy) {
	vec4 r = vec4(0.0);
	if (w.x > 0.01) {
		r += textureGrad(t, uv_p.zy, dxx, dxy) * w.x;
	}
	if (w.y > 0.01) {
		r += textureGrad(t, uv_p.xz, dyx, dyy) * w.y;
	}
	if (w.z > 0.01) {
		r += textureGrad(t, uv_p.xy, dzx, dzy) * w.z;
	}
	return r;
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnorm);
	vec3 an = pow(abs(n), vec3(4.0));
	vec3 w = an / max(an.x + an.y + an.z, 0.0001);
	float es_suelo = smoothstep(0.55, 0.85, n.y);

	vec3 uv_p = v_wpos * escala_pared;
	vec2 pxx = dFdx(uv_p.zy); vec2 pxy = dFdy(uv_p.zy);
	vec2 pyx = dFdx(uv_p.xz); vec2 pyy = dFdy(uv_p.xz);
	vec2 pzx = dFdx(uv_p.xy); vec2 pzy = dFdy(uv_p.xy);

	vec3 uv_s = v_wpos * escala_suelo;
	vec2 sxx = dFdx(uv_s.zy); vec2 sxy = dFdy(uv_s.zy);
	vec2 syx = dFdx(uv_s.xz); vec2 syy = dFdy(uv_s.xz);
	vec2 szx = dFdx(uv_s.xy); vec2 szy = dFdy(uv_s.xy);

	vec3 alb_p = vec3(0.0);
	float rug_p = 0.85;
	vec3 np = vec3(0.5, 0.5, 1.0);
	if (es_suelo < 0.99) {
		alb_p = triplanar_grad(tex_pared_alb, uv_p, w, pxx, pxy, pyx, pyy, pzx, pzy).rgb * tinte_pared.rgb;
		rug_p = triplanar_grad(tex_pared_rug, uv_p, w, pxx, pxy, pyx, pyy, pzx, pzy).r;
		np = triplanar_grad(tex_pared_nor, uv_p, w, pxx, pxy, pyx, pyy, pzx, pzy).xyz;
	}

	vec3 alb_s = vec3(0.0);
	float rug_s = 0.85;
	vec3 ns = vec3(0.5, 0.5, 1.0);
	if (es_suelo > 0.01) {
		alb_s = triplanar_grad(tex_suelo_alb, uv_s, w, sxx, sxy, syx, syy, szx, szy).rgb * tinte_suelo.rgb;
		rug_s = triplanar_grad(tex_suelo_rug, uv_s, w, sxx, sxy, syx, syy, szx, szy).r;
		ns = triplanar_grad(tex_suelo_nor, uv_s, w, sxx, sxy, syx, syy, szx, szy).xyz;
	}

	float macro = 0.88 + 0.18 * sin(v_wpos.x * 0.17 + v_wpos.z * 0.13) * cos(v_wpos.z * 0.19 - v_wpos.y * 0.23);
	ALBEDO = mix(alb_p, alb_s, es_suelo) * macro;

	float rug = mix(rug_p, rug_s, es_suelo);
	if (humedad > 0.01) {
		float charco_w = smoothstep(0.35, 0.75, sin(v_wpos.x * 0.45) * cos(v_wpos.z * 0.41));
		rug = mix(rug, 0.16, humedad * charco_w * 0.72);
	}
	ROUGHNESS = clamp(rug, 0.14, 0.96);
	SPECULAR = mix(0.45, 0.78, humedad * es_suelo);

	NORMAL_MAP = mix(np, ns, es_suelo);
	NORMAL_MAP_DEPTH = 0.85;
}
"""

const SHADER_MAGMA := """shader_type spatial;
uniform float intensidad = 2.6;
void fragment() {
	vec2 uv = UV * 4.5 + vec2(TIME * 0.04, -TIME * 0.03);
	float f1 = sin(uv.x * 3.1 + cos(uv.y * 2.7 + TIME * 0.7)) * 0.5 + 0.5;
	float f2 = cos(uv.y * 4.3 - sin(uv.x * 3.6 - TIME * 0.5)) * 0.5 + 0.5;
	float grieta = smoothstep(0.28, 0.82, f1 * f2);
	vec3 costra = vec3(0.11, 0.04, 0.03);
	vec3 lava = mix(vec3(0.95, 0.22, 0.02), vec3(1.0, 0.74, 0.18), grieta);
	ALBEDO = mix(costra, lava, grieta);
	EMISSION = lava * mix(0.35, intensidad, grieta);
	ROUGHNESS = mix(0.85, 0.25, grieta);
}
"""

static var _shader_caverna: Shader = null
static var _shader_magma: Shader = null
static var _mats_bioma: Dictionary = {}
static var _mat_madera: StandardMaterial3D = null
static var _mat_hierro: StandardMaterial3D = null
static var _mat_magma_inst: ShaderMaterial = null
static var _escenas_props: Dictionary = {}


static func limpiar_cache() -> void:
	_mats_bioma.clear()
	_escenas_props.clear()
	_mat_madera = null
	_mat_hierro = null
	_mat_magma_inst = null


static func material_bioma(bioma: String) -> Material:
	if _mats_bioma.has(bioma):
		return _mats_bioma[bioma] as Material
	if _shader_caverna == null:
		_shader_caverna = Shader.new()
		_shader_caverna.code = SHADER_CAVERNAS_PBR
	var d: Dictionary = TEXTURAS_BIOMA.get(bioma, TEXTURAS_BIOMA["piedra"])
	var mat := ShaderMaterial.new()
	mat.shader = _shader_caverna
	_cargar_set_pbr(mat, "tex_pared", str(d["pared_dir"]), str(d["pared_pref"]))
	_cargar_set_pbr(mat, "tex_suelo", str(d["suelo_dir"]), str(d["suelo_pref"]))
	mat.set_shader_parameter("escala_pared", float(d["escala_pared"]))
	mat.set_shader_parameter("escala_suelo", float(d["escala_suelo"]))
	mat.set_shader_parameter("tinte_pared", d["tinte_pared"])
	mat.set_shader_parameter("tinte_suelo", d["tinte_suelo"])
	mat.set_shader_parameter("humedad", float(d["brillo_humedad"]))
	_mats_bioma[bioma] = mat
	return mat


static func _cargar_set_pbr(mat: ShaderMaterial, clave: String, dir_ruta: String, prefijo: String) -> void:
	for par in [["alb", "diff"], ["nor", "nor_gl"], ["rug", "rough"]]:
		var ruta := "%s/%s_%s_1k.jpg" % [dir_ruta, prefijo, par[1]]
		if not ResourceLoader.exists(ruta):
			ruta = "%s/%s_%s_2k.jpg" % [dir_ruta, prefijo, par[1]]
		if ResourceLoader.exists(ruta):
			mat.set_shader_parameter("%s_%s" % [clave, par[0]], load(ruta))


static func _mat_viga() -> StandardMaterial3D:
	if _mat_madera != null:
		return _mat_madera
	_mat_madera = StandardMaterial3D.new()
	_mat_madera.albedo_color = Color(0.56, 0.42, 0.30)
	_mat_madera.roughness = 0.86
	const BASE := "res://assets/texturas/old_planks_02/old_planks_02_%s"
	if ResourceLoader.exists(BASE % "albedo.jpg"):
		_mat_madera.albedo_texture = load(BASE % "albedo.jpg")
		_mat_madera.albedo_color = Color(0.88, 0.82, 0.76)
	if ResourceLoader.exists(BASE % "normal.png"):
		_mat_madera.normal_enabled = true
		_mat_madera.normal_texture = load(BASE % "normal.png")
	if ResourceLoader.exists(BASE % "rug.jpg"):
		_mat_madera.roughness_texture = load(BASE % "rug.jpg")
	_mat_madera.uv1_triplanar = true
	_mat_madera.uv1_scale = Vector3(0.45, 0.45, 0.45)
	return _mat_madera


static func _mat_riel() -> StandardMaterial3D:
	if _mat_hierro != null:
		return _mat_hierro
	_mat_hierro = StandardMaterial3D.new()
	_mat_hierro.albedo_color = Color(0.24, 0.25, 0.28)
	_mat_hierro.metallic = 0.82
	_mat_hierro.roughness = 0.42
	return _mat_hierro


static func material_magma() -> ShaderMaterial:
	if _mat_magma_inst != null:
		return _mat_magma_inst
	if _shader_magma == null:
		_shader_magma = Shader.new()
		_shader_magma.code = SHADER_MAGMA
	_mat_magma_inst = ShaderMaterial.new()
	_mat_magma_inst.shader = _shader_magma
	return _mat_magma_inst


## Niveles 1 y 2: abre una galería en la pared este (x=434, z=-15.9) de mina_interior.glb
## y añade un ala procedural multi-sala que lleva el nivel a ~2,6–2,9× la superficie previa.
static func construir_ala_clasica(_nm: Node3D, mapa: Node, nv: int, azar: RandomNumberGenerator) -> Dictionary:
	var origen := Vector2(436.25, -15.9)
	_abrir_boquete_este(mapa)
	var celdas_info: Dictionary = {}   # Vector2i -> {"h0": float, "tipo": String, "techo": float}
	var simas: Dictionary = {}         # Vector2i -> true
	var rampa_info: Dictionary = {}    # Vector2i -> {"dir": Vector2i, "h0": float, "h1": float}
	var raices_entibado: Array[Vector2i] = []
	var puentes: Array[Vector2i] = []
	var salas_centros: Array[Vector2i] = []

	# Galería de enlace directo desde el arco x=434 (-1,0) hacia sala principal del ala este.
	for dx in range(0, 3):
		celdas_info[Vector2i(dx, 0)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.2}
		raices_entibado.append(Vector2i(dx, 0))

	# Salón de cantera este (5x5 = 25 celdas, techo alto abovedado 8.6 m).
	for dx in range(3, 8):
		for dz in range(-2, 3):
			celdas_info[Vector2i(dx, dz)] = {"h0": 0.0, "tipo": "sala", "techo": 8.6}
	salas_centros.append(Vector2i(5, 0))

	# Ramal norte con cámara de mineral + cofre oculto (compacto en z para alinear límites).
	celdas_info[Vector2i(5, -3)] = {"h0": 0.0, "tipo": "ramal", "techo": 4.2}
	raices_entibado.append(Vector2i(5, -3))
	for dx in range(4, 7):
		for dz in range(-5, -3):
			celdas_info[Vector2i(dx, dz)] = {"h0": 0.0, "tipo": "sala", "techo": 6.8}
	var pos_cofre := Vector3(origen.x + 5.0 * PASO, 0.0, origen.y - 4.5 * PASO)

	# Rampa sur subiendo a plataforma elevada (+2.0 m).
	rampa_info[Vector2i(4, 3)] = {"dir": Vector2i(0, 1), "h0": 0.0, "h1": 1.0}
	rampa_info[Vector2i(4, 4)] = {"dir": Vector2i(0, 1), "h0": 1.0, "h1": 2.0}
	celdas_info[Vector2i(4, 3)] = {"h0": 0.5, "tipo": "rampa", "techo": 5.4}
	celdas_info[Vector2i(4, 4)] = {"h0": 1.5, "tipo": "rampa", "techo": 6.2}
	for dx in range(3, 8):
		for dz in range(5, 8):
			celdas_info[Vector2i(dx, dz)] = {"h0": 2.0, "tipo": "sala", "techo": 7.6}
	salas_centros.append(Vector2i(5, 6))

	# Bucle oeste desde el mirador sur -> ramal de vuelta + puente sobre sima (en nivel 2) + atajo al túnel sur.
	celdas_info[Vector2i(2, 6)] = {"h0": 2.0, "tipo": "galeria", "techo": 4.6}
	celdas_info[Vector2i(1, 6)] = {"h0": 2.0, "tipo": "galeria", "techo": 4.6}
	rampa_info[Vector2i(0, 6)] = {"dir": Vector2i(-1, 0), "h0": 2.0, "h1": 1.0}
	rampa_info[Vector2i(-1, 6)] = {"dir": Vector2i(-1, 0), "h0": 1.0, "h1": 0.0}
	celdas_info[Vector2i(0, 6)] = {"h0": 1.5, "tipo": "rampa", "techo": 5.6}
	celdas_info[Vector2i(-1, 6)] = {"h0": 0.5, "tipo": "rampa", "techo": 4.8}
	# Cámara trasera oeste del ala (nivel 2 suma extensión norte adicional con pasarela).
	for dx in range(-3, -1):
		for dz in range(4, 7):
			celdas_info[Vector2i(dx, dz)] = {"h0": 0.0, "tipo": "sala", "techo": 6.5}
	# Conexión en bucle hacia (2, 1) pasando por celda atajo (0, 2) -> (0, 1).
	celdas_info[Vector2i(-2, 3)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
	celdas_info[Vector2i(-2, 2)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
	celdas_info[Vector2i(-1, 2)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
	var celda_atajo := Vector2i(0, 2)
	celdas_info[celda_atajo] = {"h0": 0.0, "tipo": "atajo", "techo": 4.0}
	celdas_info[Vector2i(0, 1)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
	celdas_info[Vector2i(1, 1)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
	celdas_info[Vector2i(2, 1)] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}

	var pos_escalera_n2 := Vector3.INF
	if nv == 2:
		# Extensión este + pasarela sobre sima para superar claramente la superficie de N1 (~660 m²).
		celdas_info[Vector2i(8, 0)] = {"h0": 0.0, "tipo": "galeria", "techo": 5.2}
		for dx in range(9, 11):
			var c_p := Vector2i(dx, 0)
			celdas_info[c_p] = {"h0": 0.0, "tipo": "puente", "techo": 8.0}
			puentes.append(c_p)
			simas[Vector2i(dx, -1)] = true
			simas[Vector2i(dx, 1)] = true
		for dx in range(11, 14):
			for dz in range(-2, 2):
				celdas_info[Vector2i(dx, dz)] = {"h0": 0.0, "tipo": "sala", "techo": 8.8}
		salas_centros.append(Vector2i(12, 0))
		pos_escalera_n2 = Vector3(origen.x + 12.0 * PASO, 0.0, origen.y)

	return {
		"origen": origen,
		"celdas_info": celdas_info,
		"simas": simas,
		"rampa_info": rampa_info,
		"puentes": puentes,
		"raices_entibado": raices_entibado,
		"salas_centros": salas_centros,
		"cofres": [{"pos": pos_cofre, "rot": 0.0, "id": "cofre_n%d_1" % nv}],
		"atajo": {"celda": celda_atajo, "dir": Vector2i(0, -1), "y": 0.0, "id": "atajo_n%d" % nv},
		"escalera_profunda": pos_escalera_n2,
		"azar": azar,
		"es_ala_clasica": true,
	}


## Niveles 3..20: caverna multi-sala y multi-altura 2,5-3× más grande en planta que la anterior.
static func construir_disposicion_completa(nv: int, bioma: String, azar: RandomNumberGenerator) -> Dictionary:
	var origen := Vector2(400.0, 0.0)
	var celdas_info: Dictionary = {}
	var simas: Dictionary = {}
	var rampa_info: Dictionary = {}
	var puentes: Array[Vector2i] = []
	var raices_entibado: Array[Vector2i] = []
	var salas_centros: Array[Vector2i] = []
	var alturas_sala: Dictionary = {}

	# Vestíbulo de llegada clásico (compatibilidad L4b/M2/T12 en x=400..411, z=-4..4, y=0.0).
	for x in range(0, 5):
		for z in range(-2, 3):
			celdas_info[Vector2i(x, z)] = {"h0": 0.0, "tipo": "entrada", "techo": 6.4}
	salas_centros.append(Vector2i(2, 0))
	alturas_sala[Vector2i(2, 0)] = 0.0

	var target := 118 + (nv - 3) * 11
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
	var n_salas := clampi(3 + (nv - 3) / 4, 3, 7)

	# Construir cadena principal de salas grandes a distintas cotas conectadas por galerías, rampas o pasarelas.
	var prev_centro := Vector2i(3, 0)
	var prev_h := 0.0
	var dir_general := Vector2i(1, 0)
	for s_idx in n_salas:
		# Alternar dirección principal evitando solapes y manteniendo expansión holgada hacia +X / ±Z.
		var opciones_dir: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
		if s_idx > 1:
			opciones_dir.append(Vector2i(-1, 0))
		var elegida := dir_general
		var centro_cand := Vector2i.ZERO
		for _intento in 20:
			var cand_d: Vector2i = opciones_dir[azar.randi_range(0, opciones_dir.size() - 1)]
			var separacion := azar.randi_range(7, 10)
			var cc := prev_centro + cand_d * separacion
			if cc.x < 6:
				cc.x = 6 + azar.randi_range(2, 5)
			var ocupado := false
			for existe_c in salas_centros:
				if (existe_c - cc).length() < 6.0:
					ocupado = true
					break
			if not ocupado:
				elegida = cand_d
				centro_cand = cc
				break
		if centro_cand == Vector2i.ZERO:
			centro_cand = prev_centro + Vector2i(8, azar.randi_range(-3, 3))
		dir_general = elegida

		# Elegir cota nueva (±2 m si no es puente, o mantener cota para colocar pasarela sobre sima).
		var usar_puente := (s_idx == 1) or (s_idx == 3 and nv >= 10)
		var nueva_h := prev_h
		if not usar_puente:
			var pasos_alt := [0.0, 2.0, -2.0]
			if nv >= 10:
				pasos_alt.append(4.0 if prev_h > 0.0 else -4.0)
			var cand_h: float = pasos_alt[azar.randi_range(0, pasos_alt.size() - 1)]
			if absf(cand_h - prev_h) <= 2.1:
				nueva_h = clampf(cand_h, -4.0, 4.0)
			else:
				nueva_h = clampf(prev_h + (2.0 if cand_h > prev_h else -2.0), -4.0, 4.0)

		var rw := azar.randi_range(1, 2)
		var rd := azar.randi_range(1, 2)
		var techo_h := azar.randf_range(7.8, 10.6)
		for dx in range(-rw, rw + 1):
			for dz in range(-rd, rd + 1):
				var cc := centro_cand + Vector2i(dx, dz)
				celdas_info[cc] = {"h0": nueva_h, "tipo": "sala", "techo": techo_h}

		# Conectar prev_centro -> centro_cand con codo recto y rampa/puente limpio.
		_conectar_salas(
			prev_centro, centro_cand, prev_h, nueva_h, usar_puente,
			celdas_info, simas, rampa_info, puentes, raices_entibado, azar
		)
		salas_centros.append(centro_cand)
		alturas_sala[centro_cand] = nueva_h
		prev_centro = centro_cand
		prev_h = nueva_h

	# Ramales laterales con cofres ocultos, vías de vagoneta y superficie proporcional al nivel.
	var cofres: Array[Dictionary] = []
	var n_cofres := 1 if nv <= 6 else 2
	var indice_ramal := 0
	var max_ramales := 28
	while celdas_info.size() + 10 < target and indice_ramal < max_ramales:
		indice_ramal += 1
		var base_s: Vector2i = salas_centros[indice_ramal % salas_centros.size()]
		var h_s := float(alturas_sala.get(base_s, 0.0))
		var d: Vector2i = dirs[(indice_ramal + azar.randi_range(0, 3)) % dirs.size()]
		var largo := azar.randi_range(4, 6)
		var punta := base_s
		var ramal_celdas: Array[Vector2i] = []
		for paso_i in range(2, 2 + largo):
			var p := base_s + d * paso_i
			if p.x < 1:
				break
			if not celdas_info.has(p) and not simas.has(p):
				celdas_info[p] = {"h0": h_s, "tipo": "ramal", "techo": 4.2}
				raices_entibado.append(p)
				ramal_celdas.append(p)
				punta = p
		if not ramal_celdas.is_empty():
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if celdas_info.size() >= target:
						break
					var q := punta + Vector2i(dx, dz)
					if q.x >= 1 and not celdas_info.has(q) and not simas.has(q):
						celdas_info[q] = {"h0": h_s, "tipo": "sala", "techo": azar.randf_range(6.4, 8.2)}
			if cofres.size() < n_cofres and indice_ramal >= 2:
				var pw := origen + Vector2(punta.x, punta.y) * PASO
				cofres.append({"pos": Vector3(pw.x, h_s, pw.y), "rot": atan2(-float(d.x), -float(d.y)), "id": "cofre_n%d_%d" % [nv, cofres.size() + 1]})

	# Asegurar un crecimiento estricto celda a celda hasta alcanzar exactamente el objetivo de superficie.
	var ensanchables: Array[Vector2i] = []
	for sc: Vector2i in salas_centros:
		ensanchables.append(sc)
	var guardia := 0
	while celdas_info.size() < target and guardia < 2000:
		guardia += 1
		var listas: Array[Vector2i] = []
		for c_ext: Vector2i in celdas_info:
			if str(celdas_info[c_ext]["tipo"]) in ["sala", "ramal"]:
				listas.append(c_ext)
		listas.sort()
		var anadido := false
		for c_ext: Vector2i in listas:
			if celdas_info.size() >= target:
				break
			var h_c := float(celdas_info[c_ext]["h0"])
			for d in dirs:
				var nb := c_ext + d
				if nb.x >= 2 and not celdas_info.has(nb) and not simas.has(nb) and not rampa_info.has(c_ext):
					# Evitar tocar celdas a distinta cota para mantener transiciones sin escalones bruscos.
					var choque := false
					for d2 in dirs:
						var nb2 := nb + d2
						if celdas_info.has(nb2) and absf(float(celdas_info[nb2]["h0"]) - h_c) > 0.25:
							choque = true
							break
					if not choque:
						celdas_info[nb] = {"h0": h_c, "tipo": "sala", "techo": 8.4}
						anadido = true
						break
		if not anadido:
			break

	# Si todavía no hay cofre en niveles pequeños, colocar uno seguro en un borde de una sala intermedia.
	if cofres.is_empty() and salas_centros.size() >= 2:
		var sc_cof := salas_centros[mini(1, salas_centros.size() - 1)]
		var hc := float(alturas_sala.get(sc_cof, 0.0))
		var pwc := origen + Vector2(sc_cof.x, sc_cof.y) * PASO
		cofres.append({"pos": Vector3(pwc.x + 1.2, hc, pwc.y), "rot": -PI * 0.5, "id": "cofre_n%d_1" % nv})

	# Atajo desbloqueable con barricada: conecta un ramal norte del vestíbulo con un tramo de galería a cota compatible.
	var atajo: Dictionary = {}
	if salas_centros.size() >= 2:
		var z_a := -3
		while celdas_info.has(Vector2i(2, z_a)) or simas.has(Vector2i(2, z_a)):
			z_a -= 1
		var c_base := Vector2i(2, z_a)
		celdas_info[c_base] = {"h0": 0.0, "tipo": "galeria", "techo": 4.0}
		var c_puerta := Vector2i(2, z_a - 1)
		if not celdas_info.has(c_puerta) and not simas.has(c_puerta):
			celdas_info[c_puerta] = {"h0": 0.0, "tipo": "atajo", "techo": 4.0}
			var meta := salas_centros[1]
			_conectar_simple(Vector2i(2, z_a - 2), meta, 0.0, float(alturas_sala.get(meta, 0.0)), celdas_info, simas, rampa_info)
			atajo = {"celda": c_puerta, "dir": Vector2i(0, 1), "y": 0.0, "id": "atajo_n%d" % nv}

	var celda_bajada: Vector2i = prev_centro
	return {
		"origen": origen,
		"celdas_info": celdas_info,
		"simas": simas,
		"rampa_info": rampa_info,
		"puentes": puentes,
		"raices_entibado": raices_entibado,
		"salas_centros": salas_centros,
		"celda_bajada": celda_bajada,
		"h_bajada": prev_h,
		"cofres": cofres,
		"atajo": atajo,
		"azar": azar,
		"es_ala_clasica": false,
		"bioma": bioma,
	}


static func _conectar_salas(
	a: Vector2i, b: Vector2i, ha: float, hb: float, usar_puente: bool,
	celdas_info: Dictionary, simas: Dictionary, rampa_info: Dictionary,
	puentes: Array[Vector2i], raices_entibado: Array[Vector2i], azar: RandomNumberGenerator
) -> void:
	var codo := Vector2i(b.x, a.y)
	var tramo1 := _tramo_recto(a, codo)
	var tramo2 := _tramo_recto(codo, b)
	var ruta: Array[Vector2i] = []
	for p in tramo1:
		ruta.append(p)
	for i in range(1, tramo2.size()):
		ruta.append(tramo2[i])

	var h_actual := ha
	var i := 1
	while i < ruta.size() - 1:
		var c := ruta[i]
		# Puente sobre sima en un segmento recto horizontal/vertical con suficiente longitud.
		if usar_puente and is_equal_approx(ha, hb) and i >= 2 and i + 2 < ruta.size():
			var d1 := c - ruta[i - 1]
			var d2 := ruta[i + 1] - c
			if d1 == d2 and d1.length() == 1.0:
				var perp := Vector2i(-d1.y, d1.x)
				var libre_puente := true
				for step in 2:
					var cp := ruta[i + step]
					if celdas_info.has(cp + perp) or celdas_info.has(cp - perp):
						libre_puente = false
						break
				if libre_puente:
					for step in 2:
						var cp := ruta[i + step]
						celdas_info[cp] = {"h0": h_actual, "tipo": "puente", "techo": 8.4}
						puentes.append(cp)
						simas[cp + perp] = true
						simas[cp - perp] = true
						simas[cp + perp * 2] = true
						simas[cp - perp * 2] = true
					i += 2
					continue
		# Cambio de altura mediante rampa limpia de 2 celdas en un tramo recto.
		if absf(hb - h_actual) >= 1.5 and i + 2 < ruta.size():
			var d1 := c - ruta[i - 1]
			var d2 := ruta[i + 1] - c
			var d3 := ruta[i + 2] - ruta[i + 1]
			if d1 == d2 and d2 == d3 and not celdas_info.has(c) and not celdas_info.has(ruta[i + 1]):
				var paso_h := 1.0 if hb > h_actual else -1.0
				rampa_info[c] = {"dir": d1, "h0": h_actual, "h1": h_actual + paso_h}
				rampa_info[ruta[i + 1]] = {"dir": d1, "h0": h_actual + paso_h, "h1": h_actual + paso_h * 2.0}
				celdas_info[c] = {"h0": h_actual + paso_h * 0.5, "tipo": "rampa", "techo": 5.0}
				celdas_info[ruta[i + 1]] = {"h0": h_actual + paso_h * 1.5, "tipo": "rampa", "techo": 5.0}
				h_actual += paso_h * 2.0
				i += 2
				continue
		if not celdas_info.has(c) and not simas.has(c):
			celdas_info[c] = {"h0": h_actual, "tipo": "galeria", "techo": azar.randf_range(4.0, 4.8)}
			raices_entibado.append(c)
		i += 1


static func _conectar_simple(a: Vector2i, b: Vector2i, ha: float, hb: float, celdas_info: Dictionary, simas: Dictionary, rampa_info: Dictionary) -> void:
	var codo := Vector2i(a.x, b.y)
	var pts := _tramo_recto(a, codo) + _tramo_recto(codo, b)
	var h_act := ha
	var i := 0
	while i < pts.size():
		var c := pts[i]
		if absf(hb - h_act) >= 1.5 and i + 2 < pts.size():
			var d1 := pts[i + 1] - c
			var d2 := pts[i + 2] - pts[i + 1]
			if d1 == d2 and d1.length() == 1.0 and not celdas_info.has(c) and not celdas_info.has(pts[i + 1]):
				var step := 1.0 if hb > h_act else -1.0
				rampa_info[c] = {"dir": d1, "h0": h_act, "h1": h_act + step}
				rampa_info[pts[i + 1]] = {"dir": d1, "h0": h_act + step, "h1": h_act + step * 2.0}
				celdas_info[c] = {"h0": h_act + step * 0.5, "tipo": "rampa", "techo": 5.0}
				celdas_info[pts[i + 1]] = {"h0": h_act + step * 1.5, "tipo": "rampa", "techo": 5.0}
				h_act += step * 2.0
				i += 2
				continue
		if not celdas_info.has(c) and not simas.has(c):
			celdas_info[c] = {"h0": h_act, "tipo": "ramal", "techo": 4.0}
		i += 1


static func _tramo_recto(desde: Vector2i, hasta: Vector2i) -> Array[Vector2i]:
	var r: Array[Vector2i] = []
	var cur := desde
	r.append(cur)
	while cur != hasta:
		if cur.x != hasta.x:
			cur.x += 1 if hasta.x > cur.x else -1
		elif cur.y != hasta.y:
			cur.y += 1 if hasta.y > cur.y else -1
		r.append(cur)
	return r


## Abre una puerta arqueada en el extremo este de mina_interior.glb sin tocar el suelo ni romper los recursos cacheados.
static func _abrir_boquete_este(mapa: Node) -> void:
	var carg: Node = mapa.get("cargador") as Node
	if carg == null:
		return
	var geo := carg.get("geometria") as Node3D
	if geo != null:
		for nodo: Node in geo.find_children("*", "MeshInstance3D", true, false):
			var mi := nodo as MeshInstance3D
			var nom := String(mi.name)
			if not (nom.begins_with("Roca_inferior") or nom.begins_with("Techo_roca") or nom.begins_with("Roca_int")):
				continue
			var recortada := _recortar_malla_boquete(mi.mesh, mi.global_transform)
			if recortada != null:
				mi.mesh = recortada
	for padre_col in [carg.get("colisiones") as Node, mapa.get_node_or_null("ColisionSoloJugador")]:
		if padre_col == null:
			continue
		for nodo: Node in padre_col.get_children():
			if nodo is CollisionShape3D:
				var cs := nodo as CollisionShape3D
				if cs.shape is ConcavePolygonShape3D:
					var caras_n := _filtrar_caras_boquete((cs.shape as ConcavePolygonShape3D).get_faces(), cs.global_transform)
					var nueva_forma := ConcavePolygonShape3D.new()
					nueva_forma.backface_collision = true
					nueva_forma.set_faces(caras_n)
					cs.shape = nueva_forma


static func _en_boquete(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var cen := (a + b + c) / 3.0
	if cen.x < 430.8 or cen.x > 435.2 or cen.z < -17.7 or cen.z > -14.1 or cen.y > 4.2:
		return false
	var norm := (b - a).cross(c - a)
	var len_n := norm.length()
	var ny := absf(norm.y / len_n) if len_n > 0.0001 else 0.0
	# Mantener el suelo plano bajo y=0.16; recortar toda rampa de pared o faldón de techo en el umbral.
	if cen.y <= 0.16 and ny > 0.80:
		return false
	return true


static func _recortar_malla_boquete(malla: Mesh, xform: Transform3D) -> ArrayMesh:
	if malla == null:
		return null
	var salida := ArrayMesh.new()
	var cambio := false
	for s in malla.get_surface_count():
		var arrays := malla.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var nuevo_idx := PackedInt32Array()
		var paso_tri := idx.size() if not idx.is_empty() else verts.size()
		for i in range(0, paso_tri, 3):
			var i0 := idx[i] if not idx.is_empty() else i
			var i1 := idx[i + 1] if not idx.is_empty() else i + 1
			var i2 := idx[i + 2] if not idx.is_empty() else i + 2
			if _en_boquete(xform * verts[i0], xform * verts[i1], xform * verts[i2]):
				cambio = true
				continue
			nuevo_idx.append_array(PackedInt32Array([i0, i1, i2]))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in nuevo_idx:
			if not norms.is_empty():
				st.set_normal(norms[k])
			if not uvs.is_empty():
				st.set_uv(uvs[k])
			st.add_vertex(verts[k])
		st.commit(salida)
		var mat := malla.surface_get_material(s)
		if mat != null:
			salida.surface_set_material(s, mat)
	return salida if cambio else null


static func _filtrar_caras_boquete(caras: PackedVector3Array, xform: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, caras.size(), 3):
		var a := caras[i]
		var b := caras[i + 1]
		var c := caras[i + 2]
		if not _en_boquete(xform * a, xform * b, xform * c):
			out.append_array(PackedVector3Array([a, b, c]))
	return out


## Construye la geometría real en trozos de 20x20 m y añade elementos interactivos y decoración.
static func construir_geometria(nm: Node3D, raiz: Node3D, plan: Dictionary, bioma: String, nv: int) -> Dictionary:
	var origen: Vector2 = plan["origen"]
	var celdas_info: Dictionary = plan["celdas_info"]
	var simas: Dictionary = plan["simas"]
	var rampa_info: Dictionary = plan["rampa_info"]
	var azar: RandomNumberGenerator = plan["azar"]
	var es_ala := bool(plan.get("es_ala_clasica", false))

	var mat_roca := material_bioma(bioma)
	var mat_madera := _mat_viga()
	var mat_metal := _mat_riel()

	# Alturas de esquina compartidas para uniones estancas entre salas y rampas.
	var esq_y: Dictionary = _calcular_alturas_esquina(celdas_info, simas, rampa_info)

	# Acumular triángulos visuales y caras simplificadas de colisión por trozo de 20×20 m.
	var chunks_suelo: Dictionary = {}
	var chunks_col_s: Dictionary = {}
	var chunks_techo: Dictionary = {}
	var aabb_total := AABB()
	var primero_aabb := true

	var todas_abiertas: Dictionary = {}
	for c in celdas_info:
		todas_abiertas[c] = celdas_info[c]
	for s_c in simas:
		todas_abiertas[s_c] = {"h0": -4.2, "tipo": "sima", "techo": 12.2}

	var half := PASO * 0.5
	for c: Vector2i in todas_abiertas:
		var info: Dictionary = todas_abiertas[c]
		var tipo := str(info["tipo"])
		var h0 := float(info["h0"])
		var th := float(info["techo"])
		var es_sima := tipo == "sima"
		var es_puente := tipo == "puente"
		var y_base := -4.2 if (es_sima or es_puente) else h0

		var wx := origen.x + float(c.x) * PASO
		var wz := origen.y + float(c.y) * PASO
		var chunk_id := Vector2i(floori(wx / TAM_TROZO), floori(wz / TAM_TROZO))
		if not chunks_suelo.has(chunk_id):
			chunks_suelo[chunk_id] = PackedVector3Array()
			chunks_col_s[chunk_id] = PackedVector3Array()
			chunks_techo[chunk_id] = PackedVector3Array()
		var tris_s: PackedVector3Array = chunks_suelo[chunk_id]
		var tris_cs: PackedVector3Array = chunks_col_s[chunk_id]
		var tris_t: PackedVector3Array = chunks_techo[chunk_id]

		var y_tl := y_base if (es_sima or es_puente) else float(esq_y.get(Vector2i(c.x, c.y), h0))
		var y_tr := y_base if (es_sima or es_puente) else float(esq_y.get(Vector2i(c.x + 1, c.y), h0))
		var y_br := y_base if (es_sima or es_puente) else float(esq_y.get(Vector2i(c.x + 1, c.y + 1), h0))
		var y_bl := y_base if (es_sima or es_puente) else float(esq_y.get(Vector2i(c.x, c.y + 1), h0))

		var p_tl := Vector3(wx - half, y_tl, wz - half)
		var p_tr := Vector3(wx + half, y_tr, wz - half)
		var p_br := Vector3(wx + half, y_br, wz + half)
		var p_bl := Vector3(wx - half, y_bl, wz + half)

		# Suelo (en las simas/puentes va abajo a -4.2 m para revelar el abismo debajo).
		var suelo_tris := PackedVector3Array([p_tl, p_tr, p_br, p_tl, p_br, p_bl])
		tris_s.append_array(suelo_tris)
		tris_cs.append_array(suelo_tris)

		# Techo abovedado con relieve natural orgánico (oculto para el minimapa cenital).
		var yc := (-4.2 + th) if es_sima else (maxf(h0, 0.0) + th)
		var c_tl := _vert_techo(Vector3(wx - half, yc, wz - half), th)
		var c_tr := _vert_techo(Vector3(wx + half, yc, wz - half), th)
		var c_br := _vert_techo(Vector3(wx + half, yc, wz + half), th)
		var c_bl := _vert_techo(Vector3(wx - half, yc, wz + half), th)
		tris_t.append_array(PackedVector3Array([c_tl, c_bl, c_br, c_tl, c_br, c_tr]))

		var caja_c := AABB(Vector3(wx - half, minf(y_base, -4.5), wz - half), Vector3(PASO, yc + 8.0, PASO))
		aabb_total = caja_c if primero_aabb else aabb_total.merge(caja_c)
		primero_aabb = false

		# Paredes hacia roca sólida, cierres de desnivel de techo entre salas/ramales y faldones de sima.
		for pair in [
			[Vector2i(0, -1), p_tl, p_tr, c_tl, c_tr],
			[Vector2i(0, 1), p_br, p_bl, c_br, c_bl],
			[Vector2i(1, 0), p_tr, p_br, c_tr, c_br],
			[Vector2i(-1, 0), p_bl, p_tl, c_bl, c_tl],
		]:
			var dir: Vector2i = pair[0]
			var a: Vector3 = pair[1]
			var b: Vector3 = pair[2]
			var ca: Vector3 = pair[3]
			var cb: Vector3 = pair[4]
			var vc := c + dir
			if es_ala and c == Vector2i(0, 0) and dir == Vector2i(-1, 0):
				continue   # El lado oeste del bloque de acceso enlaza directo con la cueva clásica x=434
			if not todas_abiertas.has(vc):
				# Colisión plana y rápida de 2 triángulos + malla visual estratificada de 6 triángulos.
				tris_cs.append_array(PackedVector3Array([a, ca, cb, a, cb, b]))
				var dir_f := Vector3(float(dir.x), 0.0, float(dir.y))
				var emp_a := dir_f * maxf(0.12, 0.24 + _ruido(a.x, a.z) * 0.22)
				var emp_b := dir_f * maxf(0.12, 0.24 + _ruido(b.x, b.z) * 0.22)
				var mid_m := (a + b) * 0.5 + dir_f * maxf(0.18, 0.34 + _ruido(wx + dir.x, wz + dir.y) * 0.26)
				var h_m := Vector3(mid_m.x, lerpf((a.y + b.y) * 0.5, (ca.y + cb.y) * 0.5, 0.52), mid_m.z)
				var h_a := a.lerp(ca, 0.54) + emp_a
				var h_b := b.lerp(cb, 0.54) + emp_b
				tris_s.append_array(PackedVector3Array([
					a, h_a, h_m, a, h_m, b, b, h_m, h_b,
					h_a, ca, h_m, h_m, ca, cb, h_b, h_m, cb,
				]))
			else:
				var info_v: Dictionary = todas_abiertas[vc]
				var tipo_v := str(info_v["tipo"])
				var h_v := float(info_v["h0"])
				var th_v := float(info_v["techo"])
				var yc_v := (-4.2 + th_v) if tipo_v == "sima" else (maxf(h_v, 0.0) + th_v)
				# Cerrar el tabique superior cuando una cámara alta enlaza con una galería baja.
				if yc > yc_v + 0.08:
					var ca_low := Vector3(ca.x, _vert_techo(Vector3(ca.x, yc_v, ca.z), th_v).y - 0.04, ca.z)
					var cb_low := Vector3(cb.x, _vert_techo(Vector3(cb.x, yc_v, cb.z), th_v).y - 0.04, cb.z)
					tris_s.append_array(PackedVector3Array([ca_low, ca, cb, ca_low, cb, cb_low]))
				if (es_sima or es_puente) and not (tipo_v in ["sima", "puente"]):
					# Faldón rocoso bajo los bordes sólidos que asoman a la sima.
					var sa := Vector3(a.x, h_v, a.z)
					var sb := Vector3(b.x, h_v, b.z)
					var faldon := PackedVector3Array([b, a, sa, b, sa, sb])
					tris_s.append_array(faldon)
					tris_cs.append_array(faldon)
		chunks_suelo[chunk_id] = tris_s
		chunks_col_s[chunk_id] = tris_cs
		chunks_techo[chunk_id] = tris_t

	# Enlace plano de entrada cuando es el ala este de N1/N2.
	if es_ala:
		var cid0 := Vector2i(floori(434.0 / TAM_TROZO), floori(-15.9 / TAM_TROZO))
		var losa := PackedVector3Array([
			Vector3(430.5, 0.015, -17.5), Vector3(435.3, 0.015, -17.5), Vector3(435.3, 0.015, -14.3),
			Vector3(430.5, 0.015, -17.5), Vector3(435.3, 0.015, -14.3), Vector3(430.5, 0.015, -14.3),
		])
		var ts_e: PackedVector3Array = chunks_suelo.get(cid0, PackedVector3Array())
		ts_e.append_array(losa)
		chunks_suelo[cid0] = ts_e
		var tcs_e: PackedVector3Array = chunks_col_s.get(cid0, PackedVector3Array())
		tcs_e.append_array(losa)
		chunks_col_s[cid0] = tcs_e

	# Instanciar trozos (StaticBody3D + MeshInstance3D por chunk de 20×20 m).
	var nodos_chunk: Dictionary = {}
	for cid: Vector2i in chunks_suelo:
		var chunk_n := Node3D.new()
		chunk_n.name = "Trozo_%d_%d" % [cid.x, cid.y]
		raiz.add_child(chunk_n)
		nodos_chunk[cid] = chunk_n

		var caras_s: PackedVector3Array = chunks_suelo[cid]
		var caras_cs: PackedVector3Array = chunks_col_s.get(cid, caras_s)
		if not caras_s.is_empty():
			var cuerpo_s := StaticBody3D.new()
			cuerpo_s.name = "ColSueloParedes"
			cuerpo_s.collision_layer = CAPA_MUNDO
			cuerpo_s.collision_mask = 0
			var cs_s := CollisionShape3D.new()
			var sh_s := ConcavePolygonShape3D.new()
			sh_s.backface_collision = true
			sh_s.set_faces(caras_cs)
			cs_s.shape = sh_s
			cuerpo_s.add_child(cs_s)
			chunk_n.add_child(cuerpo_s)

			var mi_s := MeshInstance3D.new()
			mi_s.name = "MallaRoca"
			mi_s.mesh = _crear_array_mesh(caras_s)
			mi_s.material_override = mat_roca
			mi_s.visibility_range_end = 78.0
			mi_s.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			chunk_n.add_child(mi_s)

		var caras_t: PackedVector3Array = chunks_techo.get(cid, PackedVector3Array())
		if not caras_t.is_empty():
			var cuerpo_t := StaticBody3D.new()
			cuerpo_t.name = "ColTecho"
			cuerpo_t.collision_layer = CAPA_SOLO_JUGADOR
			cuerpo_t.collision_mask = 0
			var cs_t := CollisionShape3D.new()
			var sh_t := ConcavePolygonShape3D.new()
			sh_t.backface_collision = true
			sh_t.set_faces(caras_t)
			cs_t.shape = sh_t
			cuerpo_t.add_child(cs_t)
			chunk_n.add_child(cuerpo_t)

			var mi_t := MeshInstance3D.new()
			mi_t.name = "TechoRoca"
			mi_t.layers = FotoCenital.CAPA_TECHOS
			mi_t.mesh = _crear_array_mesh(caras_t)
			mi_t.material_override = mat_roca
			mi_t.visibility_range_end = 78.0
			chunk_n.add_child(mi_t)

	# Pasarelas de madera con barandilla segura sobre las simas.
	var puentes_arr: Array = plan.get("puentes", [])
	for c_p: Vector2i in puentes_arr:
		var info_p: Dictionary = celdas_info[c_p]
		var wx := origen.x + float(c_p.x) * PASO
		var wz := origen.y + float(c_p.y) * PASO
		var y_p := float(info_p["h0"])
		var por_x := celdas_info.has(c_p + Vector2i(1, 0)) or celdas_info.has(c_p + Vector2i(-1, 0))
		var chunk_n := _obtener_chunk(nodos_chunk, raiz, wx, wz)
		_construir_pasarela(chunk_n, Vector3(wx, y_p, wz), por_x, mat_madera)
		# Abismo visual en el fondo de la sima (magma o agua subterránea).
		if bioma == "magma":
			var poza := MeshInstance3D.new()
			poza.name = "Magma_Sima_%d_%d" % [c_p.x, c_p.y]
			var pm := PlaneMesh.new()
			pm.size = Vector2(PASO * 2.8, PASO * 2.8)
			poza.mesh = pm
			poza.material_override = material_magma()
			poza.position = Vector3(wx, -3.95, wz)
			raiz.add_child(poza)
			var l_lava := OmniLight3D.new()
			l_lava.light_color = Color(1.0, 0.36, 0.08)
			l_lava.light_energy = 1.65
			l_lava.omni_range = 10.5
			l_lava.shadow_enabled = false
			l_lava.set_meta("sin_sombra", true)
			l_lava.position = Vector3(wx, -2.5, wz)
			raiz.add_child(l_lava)
		elif bioma == "humeda":
			var agua := MeshInstance3D.new()
			agua.name = "Charco_Sima_%d_%d" % [c_p.x, c_p.y]
			var pm := PlaneMesh.new()
			pm.size = Vector2(PASO * 2.8, PASO * 2.8)
			agua.mesh = pm
			agua.material_override = nm.material_agua_subterranea() if nm.has_method("material_agua_subterranea") else null
			agua.position = Vector3(wx, -3.95, wz)
			raiz.add_child(agua)

	# Entibados de madera y raíles + vagonetas.
	_construir_entibados_y_railes(nodos_chunk, raiz, origen, celdas_info, plan.get("raices_entibado", []), mat_madera, mat_metal, azar, es_ala)

	# Rocas CC0 en bordes y pilares naturales.
	_colocar_rocas_cc0(nodos_chunk, raiz, origen, celdas_info, simas, azar)

	# Partículas atmosféricas por bioma (polvo, humedad o brasas).
	_colocar_particulas_bioma(raiz, origen, plan.get("salas_centros", []), celdas_info, bioma)

	return {"aabb": aabb_total, "nodos_chunk": nodos_chunk}


static func _calcular_alturas_esquina(celdas_info: Dictionary, _simas: Dictionary, rampa_info: Dictionary) -> Dictionary:
	var sumas: Dictionary = {}
	var cuentas: Dictionary = {}
	for c: Vector2i in celdas_info:
		var h := float(celdas_info[c]["h0"])
		var dir_r := Vector2i.ZERO
		var h0 := h
		var h1 := h
		var es_r := rampa_info.has(c)
		if es_r:
			var ri: Dictionary = rampa_info[c]
			dir_r = ri["dir"]
			h0 = float(ri["h0"])
			h1 = float(ri["h1"])
		for ox in [0, 1]:
			for oz in [0, 1]:
				var k := Vector2i(c.x + ox, c.y + oz)
				var val := h
				if es_r:
					if dir_r.x > 0:
						val = h1 if ox == 1 else h0
					elif dir_r.x < 0:
						val = h0 if ox == 1 else h1
					elif dir_r.y > 0:
						val = h1 if oz == 1 else h0
					elif dir_r.y < 0:
						val = h0 if oz == 1 else h1
				# Las celdas planas tienen prioridad absoluta en las esquinas compartidas.
				if not es_r:
					sumas[k] = val * 1000.0
					cuentas[k] = 1000
				else:
					sumas[k] = float(sumas.get(k, 0.0)) + val
					cuentas[k] = int(cuentas.get(k, 0)) + 1
	var out: Dictionary = {}
	for k: Vector2i in sumas:
		out[k] = float(sumas[k]) / float(maxi(int(cuentas[k]), 1))
	return out


static func _vert_techo(v: Vector3, altura_sala: float) -> Vector3:
	var n := _ruido(v.x, v.z)
	var boveda := (0.45 if altura_sala > 6.5 else 0.18) * n
	return Vector3(v.x, v.y + boveda, v.z)


static func _ruido(x: float, z: float) -> float:
	return sin(x * 0.43 + cos(z * 0.37)) * 0.65 + cos(z * 0.51 - sin(x * 0.29)) * 0.35


static func _crear_array_mesh(caras: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in caras.size():
		var v := caras[i]
		st.set_uv(Vector2(v.x * 0.2, v.z * 0.2))
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _obtener_chunk(nodos_chunk: Dictionary, raiz: Node3D, wx: float, wz: float) -> Node3D:
	var cid := Vector2i(floori(wx / TAM_TROZO), floori(wz / TAM_TROZO))
	if nodos_chunk.has(cid):
		return nodos_chunk[cid] as Node3D
	var ch := Node3D.new()
	ch.name = "Trozo_%d_%d" % [cid.x, cid.y]
	raiz.add_child(ch)
	nodos_chunk[cid] = ch
	return ch


static func _construir_pasarela(padre: Node3D, centro: Vector3, por_x: bool, mat: Material) -> void:
	var raiz := StaticBody3D.new()
	raiz.name = "Pasarela"
	raiz.collision_layer = CAPA_MUNDO
	raiz.collision_mask = 0
	raiz.position = centro
	if not por_x:
		raiz.rotation.y = PI * 0.5
	padre.add_child(raiz)

	var largo := PASO
	var ancho := 2.28
	var tbl_mesh := BoxMesh.new()
	tbl_mesh.size = Vector3(largo, 0.14, ancho)
	var tablero := MeshInstance3D.new()
	tablero.mesh = tbl_mesh
	tablero.material_override = mat
	tablero.position = Vector3(0.0, -0.07, 0.0)
	tablero.visibility_range_end = 68.0
	raiz.add_child(tablero)

	var col_suelo := CollisionShape3D.new()
	var sh_suelo := BoxShape3D.new()
	sh_suelo.size = Vector3(largo, 0.18, ancho)
	col_suelo.shape = sh_suelo
	col_suelo.position = Vector3(0.0, -0.09, 0.0)
	raiz.add_child(col_suelo)

	# Barandillas laterales para mirar al abismo sin caerse por accidente.
	var cuerpo_bar := StaticBody3D.new()
	cuerpo_bar.collision_layer = CAPA_SOLO_JUGADOR | CAPA_MUNDO
	cuerpo_bar.collision_mask = 0
	raiz.add_child(cuerpo_bar)
	for sz: float in [-1.0, 1.0]:
		var z: float = sz * (ancho * 0.5 - 0.06)
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(largo, 0.08, 0.08)
		var pasamano := MeshInstance3D.new()
		pasamano.mesh = bar_mesh
		pasamano.material_override = mat
		pasamano.position = Vector3(0.0, 0.92, z)
		pasamano.visibility_range_end = 60.0
		raiz.add_child(pasamano)
		for px in [-0.95, 0.0, 0.95]:
			var poste := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.09, 0.96, 0.09)
			poste.mesh = pm
			poste.material_override = mat
			poste.position = Vector3(px, 0.46, z)
			poste.visibility_range_end = 60.0
			raiz.add_child(poste)
		var cs_b := CollisionShape3D.new()
		var bs_b := BoxShape3D.new()
		bs_b.size = Vector3(largo, 1.2, 0.14)
		cs_b.shape = bs_b
		cs_b.position = Vector3(0.0, 0.6, z)
		cuerpo_bar.add_child(cs_b)


static func _construir_entibados_y_railes(
	nodos_chunk: Dictionary, raiz: Node3D, origen: Vector2,
	celdas_info: Dictionary, raices_entibado: Array, mat_madera: Material,
	mat_metal: Material, azar: RandomNumberGenerator, es_ala: bool
) -> void:
	if es_ala:
		# Marco de madera del umbral x=434.0, z=-15.9.
		var ch_portal := _obtener_chunk(nodos_chunk, raiz, 434.0, -15.9)
		_crear_arco_entibado(ch_portal, Vector3(434.0, 0.0, -15.9), false, mat_madera, 3.3, 3.1)

	var puestos := 0
	var vagonetas := 0
	var escena_vag: PackedScene = null
	if ResourceLoader.exists(RUTA_VAGONETA):
		escena_vag = load(RUTA_VAGONETA) as PackedScene

	var vistos: Dictionary = {}
	for c_var in raices_entibado:
		var c := c_var as Vector2i
		if vistos.has(c) or not celdas_info.has(c):
			continue
		vistos[c] = true
		var info: Dictionary = celdas_info[c]
		var wx := origen.x + float(c.x) * PASO
		var wz := origen.y + float(c.y) * PASO
		var h := float(info["h0"])
		var ch := _obtener_chunk(nodos_chunk, raiz, wx, wz)

		var libre_x := celdas_info.has(c + Vector2i(1, 0)) and celdas_info.has(c + Vector2i(-1, 0)) and not celdas_info.has(c + Vector2i(0, 1)) and not celdas_info.has(c + Vector2i(0, -1))
		var libre_z := celdas_info.has(c + Vector2i(0, 1)) and celdas_info.has(c + Vector2i(0, -1)) and not celdas_info.has(c + Vector2i(1, 0)) and not celdas_info.has(c + Vector2i(-1, 0))
		if not libre_x and not libre_z:
			continue
		puestos += 1
		if puestos % 2 == 1:
			_crear_arco_entibado(ch, Vector3(wx, h, wz), libre_z, mat_madera, 2.35, 3.0)
		# Raíles en tramos rectos largos.
		if puestos % 2 == 0 or libre_x:
			_crear_tramo_railes(ch, Vector3(wx, h, wz), libre_z, mat_madera, mat_metal)
			if escena_vag != null and vagonetas < 2 and (puestos % 5 == 0) and azar.randf() < 0.7:
				vagonetas += 1
				var vag := escena_vag.instantiate() as Node3D
				if vag != null:
					vag.name = "Vagoneta_%d" % vagonetas
					vag.position = Vector3(wx, h + 0.06, wz)
					vag.rotation.y = (0.0 if libre_z else PI * 0.5)
					vag.scale = Vector3.ONE * 0.85
					ch.add_child(vag)


static func _crear_arco_entibado(padre: Node3D, pos: Vector3, eje_z: bool, mat: Material, luz_ancho: float, alto: float) -> void:
	var n := StaticBody3D.new()
	n.collision_layer = CAPA_SOLO_JUGADOR
	n.collision_mask = 0
	n.position = pos
	if not eje_z:
		n.rotation.y = PI * 0.5
	padre.add_child(n)

	var sep := luz_ancho * 0.5 - 0.12
	for sx in [-1.0, 1.0]:
		var poste := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.18, alto, 0.18)
		poste.mesh = pm
		poste.material_override = mat
		poste.position = Vector3(sx * sep, alto * 0.5, 0.0)
		poste.rotation.z = sx * 0.08
		poste.visibility_range_end = 56.0
		n.add_child(poste)
	var dintel := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(luz_ancho, 0.22, 0.22)
	dintel.mesh = dm
	dintel.material_override = mat
	dintel.position = Vector3(0.0, alto - 0.08, 0.0)
	dintel.visibility_range_end = 56.0
	n.add_child(dintel)


static func _crear_tramo_railes(padre: Node3D, pos: Vector3, eje_z: bool, mat_m: Material, mat_r: Material) -> void:
	var n := Node3D.new()
	n.position = pos
	if not eje_z:
		n.rotation.y = PI * 0.5
	padre.add_child(n)
	for dz in [-0.85, 0.0, 0.85]:
		var traviesa := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(1.1, 0.045, 0.13)
		traviesa.mesh = tm
		traviesa.material_override = mat_m
		traviesa.position = Vector3(0.0, 0.022, dz)
		traviesa.visibility_range_end = 44.0
		n.add_child(traviesa)
	for rx in [-0.36, 0.36]:
		var riel := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.055, 0.055, PASO)
		riel.mesh = rm
		riel.material_override = mat_r
		riel.position = Vector3(rx, 0.055, 0.0)
		riel.visibility_range_end = 48.0
		n.add_child(riel)


static func _colocar_rocas_cc0(nodos_chunk: Dictionary, raiz: Node3D, origen: Vector2, celdas_info: Dictionary, simas: Dictionary, azar: RandomNumberGenerator) -> void:
	var escenas: Array[PackedScene] = []
	for r in RUTA_ROCAS_CC0:
		if not _escenas_props.has(r) and ResourceLoader.exists(r):
			_escenas_props[r] = load(r)
		if _escenas_props.has(r) and _escenas_props[r] is PackedScene:
			escenas.append(_escenas_props[r] as PackedScene)
	if escenas.is_empty():
		return
	var puestas := 0
	var max_props := 34
	var orden: Array[Vector2i] = []
	for c: Vector2i in celdas_info:
		orden.append(c)
	orden.sort()
	for idx in range(0, orden.size(), 5):
		if puestas >= max_props:
			break
		var c := orden[idx]
		var info: Dictionary = celdas_info[c]
		if str(info["tipo"]) != "sala":
			continue
		# Solo contra muros sólidos (nunca en el centro ni junto a simas).
		var borde_dir := Vector2i.ZERO
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var vc: Vector2i = c + d
			if not celdas_info.has(vc) and not simas.has(vc):
				borde_dir = d
				break
		if borde_dir == Vector2i.ZERO:
			continue
		var wx := origen.x + (float(c.x) + float(borde_dir.x) * 0.44) * PASO
		var wz := origen.y + (float(c.y) + float(borde_dir.y) * 0.44) * PASO
		var h := float(info["h0"])
		var ch := _obtener_chunk(nodos_chunk, raiz, wx, wz)
		var sc: PackedScene = escenas[puestas % escenas.size()]
		var inst := sc.instantiate() as Node3D
		if inst == null:
			continue
		inst.position = Vector3(wx, h - 0.12, wz)
		inst.rotation.y = atan2(-float(borde_dir.x), -float(borde_dir.y)) + azar.randf_range(-0.3, 0.3)
		inst.scale = Vector3.ONE * azar.randf_range(0.65, 0.95)
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = 50.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		ch.add_child(inst)
		puestas += 1


static func _colocar_particulas_bioma(raiz: Node3D, origen: Vector2, salas_centros: Array, celdas_info: Dictionary, bioma: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var color := Color(0.95, 0.85, 0.60, 0.42)
	var grav := Vector3(0.0, 0.04, 0.0)
	match bioma:
		"humeda":
			color = Color(0.65, 0.90, 1.0, 0.36)
			grav = Vector3(0.0, -0.18, 0.0)
		"cristal":
			color = Color(0.75, 0.55, 1.0, 0.46)
			grav = Vector3(0.0, 0.08, 0.0)
		"magma":
			color = Color(1.0, 0.48, 0.16, 0.62)
			grav = Vector3(0.0, 0.32, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.6 if bioma == "magma" or bioma == "cristal" else 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = mat
	var max_s := mini(4, salas_centros.size())
	for i in max_s:
		var c: Vector2i = salas_centros[i]
		var h := float((celdas_info.get(c, {}) as Dictionary).get("h0", 0.0))
		var wp := origen + Vector2(c.x, c.y) * PASO
		var gp := GPUParticles3D.new()
		gp.name = "AtmosferaSala_%d" % i
		gp.amount = 24
		gp.lifetime = 3.2
		gp.visibility_range_end = 36.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(3.5, 2.2, 3.5)
		pm.gravity = grav
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.25
		gp.process_material = pm
		gp.draw_pass_1 = quad
		gp.position = Vector3(wp.x, h + 2.0, wp.y)
		raiz.add_child(gp)


## Crea un cofre de mineral / tesoro oculto interactuable (usa cofre_mina.glb).
static func crear_cofre(padre: Node3D, id_cofre: String, pos: Vector3, rot_y: float, nv: int, ya_abierto: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Cofre_" + id_cofre
	body.collision_layer = CAPA_SOLO_JUGADOR
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = rot_y
	padre.add_child(body)

	var tapa: Node3D = null
	if ResourceLoader.exists(RUTA_COFRE):
		var sc := load(RUTA_COFRE) as PackedScene
		if sc != null:
			var mod := sc.instantiate() as Node3D
			if mod != null:
				mod.scale = Vector3.ONE * 0.92
				body.add_child(mod)
				tapa = mod.find_child("Tapa", true, false) as Node3D
				if tapa != null and ya_abierto:
					tapa.rotation.x = deg_to_rad(-92.0)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.7, 0.55)
	cs.shape = bs
	cs.position = Vector3(0.0, 0.35, 0.0)
	body.add_child(cs)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.78, 0.30)
	luz.light_energy = 0.25 if ya_abierto else 0.95
	luz.omni_range = 4.2
	luz.shadow_enabled = false
	luz.set_meta("sin_sombra", true)
	luz.position = Vector3(0.0, 0.85, 0.0)
	body.add_child(luz)

	var p := Interactuable.new()
	p.name = "InteractuableCofre"
	p.verbo = "Abrir"
	p.nombre_objeto = "el cofre de minero"
	p.radio = 1.5
	p.altura_marca = 1.25
	p.mostrar_descripcion = false
	p.activo = not ya_abierto
	p.usado.connect(func(_j: Node3D) -> void:
		if not p.activo:
			return
		p.activo = false
		_registrar_estado_lista("cofres", id_cofre)
		Audio.reproducir_posicional("mina_cofre", body.global_position, padre, 0.0)
		luz.light_energy = 0.25
		if tapa != null:
			var tw := body.create_tween()
			tw.tween_property(tapa, "rotation:x", deg_to_rad(-92.0), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var botin := _otorgar_botin_cofre(nv)
		Interfaz.mensaje("Cofre abierto: %s" % botin)
	)
	body.add_child(p)
	return body


static func _otorgar_botin_cofre(nv: int) -> String:
	var piezas: Array[String] = []
	var oro := 18 + nv * 4
	Juego.dinero += oro
	piezas.append("%d monedas" % oro)
	var min_id := "cobre"
	var cant := 3
	if nv >= 16:
		min_id = "diamante" if nv >= 18 else "rubi"
		cant = 2
	elif nv >= 11:
		min_id = "amatista"
		cant = 2
	elif nv >= 6:
		min_id = "oro"
		cant = 3
	elif nv >= 3:
		min_id = "cuarzo"
		cant = 3
	Juego.anadir_objeto(min_id, cant)
	piezas.append("%d× %s" % [cant, min_id])
	if nv % 2 == 0:
		Juego.anadir_objeto("elixir_sierra", 1)
		piezas.append("1× elixir de la sierra")
	else:
		Juego.anadir_objeto("ambar_valle", 1)
		piezas.append("1× ámbar del valle")
	return ", ".join(piezas)


## Barricada interactuable que abre una ruta directa entre galerías profundas y la zona inicial.
static func crear_atajo(padre: Node3D, id_atajo: String, pos: Vector3, dir: Vector2i, ya_abierto: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Atajo_" + id_atajo
	body.collision_layer = 0 if ya_abierto else (CAPA_SOLO_JUGADOR | CAPA_MUNDO)
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = atan2(float(dir.x), float(dir.y))
	padre.add_child(body)

	var puerta := Node3D.new()
	puerta.name = "PortonAtajo"
	puerta.position = Vector3(-1.0, 0.0, 0.0)
	puerta.rotation.y = deg_to_rad(-88.0) if ya_abierto else 0.0
	body.add_child(puerta)

	var mat := _mat_viga()
	for i in 4:
		var liston := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(2.05, 0.18, 0.10)
		liston.mesh = lm
		liston.material_override = mat
		liston.position = Vector3(1.0, 0.35 + float(i) * 0.42, 0.0)
		liston.visibility_range_end = 56.0
		puerta.add_child(liston)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 2.2, 0.25)
	cs.shape = bs
	cs.position = Vector3(0.0, 1.1, 0.0)
	cs.disabled = ya_abierto
	body.add_child(cs)

	var p := Interactuable.new()
	p.name = "InteractuableAtajo"
	p.verbo = "Desbloquear"
	p.nombre_objeto = "el atajo de la mina"
	p.radio = 1.65
	p.altura_marca = 1.6
	p.mostrar_descripcion = false
	p.activo = not ya_abierto
	p.usado.connect(func(_j: Node3D) -> void:
		if not p.activo:
			return
		p.activo = false
		cs.disabled = true
		body.collision_layer = 0
		_registrar_estado_lista("atajos", id_atajo)
		Audio.reproducir_posicional("mina_atajo", body.global_position, padre, 0.0)
		var tw := body.create_tween()
		tw.tween_property(puerta, "rotation:y", deg_to_rad(-88.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		Interfaz.mensaje("¡Atajo desbloqueado! Conexión rápida abierta.")
	)
	body.add_child(p)
	return body


static func _registrar_estado_lista(clave: String, item: String) -> void:
	if not (Juego.estado_mapas.get("mina_interior", null) is Dictionary):
		Juego.estado_mapas["mina_interior"] = {}
	var est: Dictionary = Juego.estado_mapas["mina_interior"]
	if not (est.get(clave, null) is Array):
		est[clave] = []
	var arr: Array = est[clave]
	if not arr.has(item):
		arr.append(item)


static func estado_contiene(clave: String, item: String) -> bool:
	var est: Variant = Juego.estado_mapas.get("mina_interior", null)
	if not (est is Dictionary):
		return false
	var arr: Variant = (est as Dictionary).get(clave, null)
	return (arr is Array) and (arr as Array).has(item)
