// Mala Hierba · material estacional para suelos y tejados exteriores (T15).
// Conserva intactas las texturas horneadas en primavera/verano, aporta tono otoñal al suelo
// y acumula manto de nieve realista en invierno según normal vertical y camino pisado.
shader_type spatial;
render_mode cull_back;

global uniform float nieve_estacion;
global uniform float calidez_otono;
global uniform float humedad_h03;
global uniform int calidad_h03;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rug_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool usa_albedo = true;
uniform bool usa_normal = false;
uniform bool usa_rug = false;
uniform vec4 color_base : source_color = vec4(1.0);
uniform float rug_base = 0.65;
uniform float metalico = 0.0;
uniform bool es_suelo = false;
uniform bool es_tejado = false;
uniform bool recibe_lluvia = true;
uniform bool usa_normal_mundo = false;
uniform sampler2D normal_mundo_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float escala_normal_mundo = 2.2;
uniform float fuerza_normal_mundo = 0.65;
uniform bool usa_detalle = false;
uniform sampler2D detalle_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detalle_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detalle_rugosidad : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detalle_altura : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float ruido_suave(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 paralaje(vec2 uv, vec2 paso, vec2 dx, vec2 dy, int pasos) {
	float capa = 0.0;
	float inv_pasos = 1.0 / float(pasos);
	float altura = 1.0 - textureGrad(detalle_altura, uv, dx, dy).r;
	for (int i = 0; i < pasos; i++) {
		if (capa >= altura) {
			break;
		}
		uv -= paso;
		capa += inv_pasos;
		altura = 1.0 - textureGrad(detalle_altura, uv, dx, dy).r;
	}
	float anterior = 1.0 - textureGrad(detalle_altura, uv + paso, dx, dy).r - (capa - inv_pasos);
	float peso = clamp((capa - altura) / max(0.0001, capa - altura + anterior), 0.0, 1.0);
	return uv + paso * peso;
}

vec2 gotas_charco(vec2 mundo) {
	vec2 rejilla = mundo * 4.7;
	float semilla = fract(sin(dot(floor(rejilla), vec2(157.13, 311.7))) * 14795.63);
	vec2 centro = vec2(0.28 + 0.43 * semilla, 0.28 + 0.43 * fract(semilla * 17.3));
	vec2 punto = fract(rejilla) - centro;
	float r = length(punto);
	float edad = fract(TIME * (1.25 + semilla * 0.4) + semilla * 13.0);
	float anillo = sin((r - edad * 0.38) * 67.0) * exp(-abs(r - edad * 0.38) * 34.0);
	return punto / max(0.001, r) * anillo * (1.0 - edad) * smoothstep(0.015, 0.08, r)
		* (1.0 - smoothstep(0.15, 0.26, r));
}

void fragment() {
	vec3 col = color_base.rgb;
	if (usa_albedo) {
		col = texture(albedo_tex, UV).rgb;
	}
	vec3 orig = col;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	if (es_suelo) {
		col = mix(vec3(luma), col, 1.24) * 0.78;
		orig = col;
	} else if (es_tejado) {
		col = mix(vec3(luma), col, 1.18) * 0.84;
	}

	float dist = length(VERTEX);
	vec3 n = normalize(normal_mundo);
	vec3 relieve = n;
	float mezcla_detalle = 0.0;
	float rug_detalle = 0.85;
	if (usa_detalle) {
		float cobertura = smoothstep(0.38, 0.85, n.y) * (1.0 - smoothstep(13.0, 44.0, dist));
		vec2 detalle_uv = pos_mundo.xz * 0.67;
		vec2 dx = dFdx(detalle_uv);
		vec2 dy = dFdy(detalle_uv);
		if (cobertura > 0.001) {
			float variacion = ruido_suave(pos_mundo.xz * 0.54);
			if (calidad_h03 >= 2 && dist < 11.0) {
				vec3 cam = normalize(CAMERA_POSITION_WORLD - pos_mundo);
				float factor = (1.0 - smoothstep(5.0, 11.0, dist)) * cobertura * (1.0 - nieve_estacion * 0.8);
				if (factor > 0.02) {
					int pasos = calidad_h03 >= 3 ? 6 : 4;
					detalle_uv = paralaje(detalle_uv, cam.xz * (0.018 / (float(pasos) * max(0.28, abs(cam.y)))) * factor, dx, dy, pasos);
				}
			}
			float altura = textureGrad(detalle_altura, detalle_uv, dx, dy).r;
			mezcla_detalle = cobertura * smoothstep(0.12, 0.82, altura * 0.68 + variacion * 0.32);
			vec3 foto = textureGrad(detalle_color, detalle_uv, dx, dy).rgb;
			float brillo_foto = dot(foto, vec3(0.2126, 0.7152, 0.0722));
			col = mix(col, col * clamp(0.65 + brillo_foto * 2.8, 0.58, 1.34) + foto * 0.14, mezcla_detalle * 0.64);
			rug_detalle = textureGrad(detalle_rugosidad, detalle_uv, dx, dy).r;
			vec2 desvio = textureGrad(detalle_normal, detalle_uv, dx, dy).xy * 2.0 - 1.0;
			relieve = normalize(n + vec3(desvio.x, 0.0, -desvio.y) * mezcla_detalle * 0.68);
		}
	}

	if (calidez_otono > 0.01 && es_suelo) {
		// El verde de pradera vira hacia tonos dorados y ocre otoñales manteniendo caminos y rocas.
		float verdor = clamp((orig.g - max(orig.r, orig.b) * 0.85) * 4.5, 0.0, 1.0);
		vec3 otonal = mix(orig, orig * vec3(1.22, 0.88, 0.56), verdor * 0.85);
		col += (otonal - orig) * calidez_otono;
	}

	float nieve = 0.0;
	if (nieve_estacion > 0.01) {
		float ny = normal_mundo.y;
		float r_macro = ruido_suave(pos_mundo.xz * 0.35);
		float r_detalle = ruido_suave(pos_mundo.xz * 2.8);
		float r = 0.6 * r_macro + 0.4 * r_detalle;
		if (es_tejado) {
			nieve = smoothstep(0.18, 0.52, ny + (r - 0.5) * 0.18) * nieve_estacion;
			nieve *= smoothstep(0.12, 0.42, r + ny * 0.35);
		} else if (es_suelo) {
			float plano = smoothstep(0.48, 0.82, ny + (r - 0.5) * 0.22);
			// En los caminos de tierra cálida se apelmaza y deja entrever ligeramente el sendero.
			float sendero = clamp((orig.r - orig.b) * 2.5 - (orig.g - orig.b) * 0.8, 0.0, 1.0);
			float espesor = mix(0.95, 0.58, sendero * 0.75);
			nieve = plano * espesor * smoothstep(0.08, 0.45, r + plano * 0.45) * nieve_estacion;
		}
		vec3 tono_nieve = mix(vec3(0.80, 0.86, 0.95), vec3(0.95, 0.97, 1.0), r_detalle);
		col = mix(col, tono_nieve, nieve);
	}

	float mojado = recibe_lluvia ? humedad_h03 * (1.0 - nieve * 0.9) : 0.0;
	float charco = 0.0;
	if (es_suelo && mojado > 0.28 && n.y > 0.94) {
		float suelo = ruido_suave(pos_mundo.xz * 0.64) * 0.74 + ruido_suave(pos_mundo.xz * 2.26) * 0.26;
		charco = smoothstep(0.72, 0.88, suelo) * smoothstep(0.94, 0.997, n.y) * smoothstep(0.28, 0.85, mojado);
		vec2 onda = gotas_charco(pos_mundo.xz) * (1.0 - smoothstep(3.0, 16.0, dist));
		relieve = normalize(mix(relieve, vec3(onda.x * 0.20, 1.0, onda.y * 0.20), charco));
	}
	if (usa_normal_mundo && dist < 42.0) {
		vec2 uv_nm = pos_mundo.xz / escala_normal_mundo;
		vec3 tang_u = vec3(1.0, 0.0, 0.0);
		vec3 tang_v = vec3(0.0, 0.0, -1.0);
		if (abs(n.y) <= 0.55) {
			if (abs(n.x) > abs(n.z)) {
				uv_nm = pos_mundo.zy / escala_normal_mundo;
				tang_u = vec3(0.0, 0.0, 1.0);
			} else {
				uv_nm = pos_mundo.xy / escala_normal_mundo;
			}
			tang_v = vec3(0.0, 1.0, 0.0);
		}
		vec2 desvio_m = texture(normal_mundo_tex, uv_nm).xy * 2.0 - 1.0;
		float peso_nm = (1.0 - smoothstep(28.0, 42.0, dist)) * fuerza_normal_mundo * (1.0 - max(nieve, charco) * 0.8);
		relieve = normalize(relieve + (tang_u * desvio_m.x + tang_v * desvio_m.y) * peso_nm);
	}
	ALBEDO = col * (1.0 - mojado * 0.23 - charco * 0.22);
	float rug = usa_rug ? texture(rug_tex, UV).r : rug_base;
	rug = mix(clamp(rug, 0.78, 1.0), clamp(rug_detalle, 0.56, 0.96), mezcla_detalle * 0.65);
	ROUGHNESS = mix(mix(rug, rug * 0.62, mojado), 0.10, charco);
	ROUGHNESS = mix(ROUGHNESS, 0.86, nieve * 0.9);
	METALLIC = metalico * (1.0 - nieve);
	SPECULAR = mix(0.16, 0.37, max(mojado * 0.62, charco));
	NORMAL = normalize(mat3(VIEW_MATRIX) * mix(relieve, n, nieve * 0.8));

	if (usa_normal && dist < 42.0) {
		NORMAL_MAP = texture(normal_tex, UV).xyz;
		NORMAL_MAP_DEPTH = mix(1.0, 0.25, max(nieve, charco)) * (1.0 - smoothstep(28.0, 42.0, dist));
	}
}
