// Mala Hierba · material estacional para suelos y tejados exteriores (T15).
// Conserva intactas las texturas horneadas en primavera/verano, aporta tono otoñal al suelo
// y acumula manto de nieve realista en invierno según normal vertical y camino pisado.
shader_type spatial;

global uniform float nieve_estacion;
global uniform float calidez_otono;

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

	if (calidez_otono > 0.01 && es_suelo) {
		// El verde de pradera vira hacia tonos dorados y ocre otoñales manteniendo caminos y rocas.
		float verdor = clamp((orig.g - max(orig.r, orig.b) * 0.85) * 4.5, 0.0, 1.0);
		vec3 otonal = mix(orig, orig * vec3(1.22, 0.88, 0.56), verdor * 0.85);
		col = mix(col, otonal, calidez_otono);
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

	ALBEDO = col;
	float rug = usa_rug ? texture(rug_tex, UV).r : rug_base;
	ROUGHNESS = mix(clamp(rug, 0.78, 1.0), 0.86, nieve * 0.9);
	METALLIC = metalico * (1.0 - nieve);
	SPECULAR = 0.16;

	if (usa_normal) {
		vec3 nt = texture(normal_tex, UV).xyz * 2.0 - 1.0;
		NORMAL_MAP = texture(normal_tex, UV).xyz;
		NORMAL_MAP_DEPTH = mix(1.0, 0.25, nieve);
	}
}
