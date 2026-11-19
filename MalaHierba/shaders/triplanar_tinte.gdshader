// Mala Hierba · material triplanar con tinte y variación estacional (carril L1 / T15).
// Equivale a los `mat_pbr` de Blender: texturas PBR (albedo, normal GL, rugosidad) proyectadas en caja con
// coordenadas de mundo, mezcla con un color (tinte), multiplicación por un color (tinte_mult), rugosidad
// y acumulación sutil de nieve invernal sobre caras orientadas hacia arriba.
shader_type spatial;
render_mode cull_back;

global uniform float nieve_estacion;
global uniform float calidez_otono;
global uniform float humedad_h03;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rug_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool usa_normal = true;
uniform bool usa_rug = true;
uniform float escala = 2.0;             // metros del mundo por repetición de la textura
uniform vec3 tinte = vec3(1.0);         // color lineal con el que se mezcla la textura
uniform float fuerza_tinte : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tinte_mult = vec3(1.0);    // color lineal por el que se multiplica
uniform float rug_mult = 1.0;
uniform float rug_base = 0.8;           // rugosidad si no hay textura
uniform float nitidez = 6.0;            // cuanto mayor, más brusco el cambio entre las tres proyecciones
uniform float fuerza_normal = 1.0;
uniform bool recibe_lluvia = false;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 normal_tangente(vec4 t) {
	vec2 xy = (t.xy * 2.0 - 1.0) * fuerza_normal;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
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
	vec3 n = normalize(normal_mundo);
	vec3 w = pow(abs(n), vec3(nitidez));
	w /= (w.x + w.y + w.z);

	vec2 uvx = pos_mundo.zy / escala;
	vec2 uvy = pos_mundo.xz / escala;
	vec2 uvz = pos_mundo.xy / escala;
	vec2 dxx = dFdx(uvx);
	vec2 dxy = dFdy(uvx);
	vec2 dyx = dFdx(uvy);
	vec2 dyy = dFdy(uvy);
	vec2 dzx = dFdx(uvz);
	vec2 dzy = dFdy(uvz);

	vec3 col = vec3(0.0);
	if (w.x > 0.01) {
		col += textureGrad(albedo_tex, uvx, dxx, dxy).rgb * w.x;
	}
	if (w.y > 0.01) {
		col += textureGrad(albedo_tex, uvy, dyx, dyy).rgb * w.y;
	}
	if (w.z > 0.01) {
		col += textureGrad(albedo_tex, uvz, dzx, dzy).rgb * w.z;
	}
	col = mix(col, tinte, fuerza_tinte);
	col *= tinte_mult;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 1.14) * 0.86;

	if (calidez_otono > 0.01) {
		col = mix(col, col * vec3(1.06, 0.96, 0.84), calidez_otono * 0.4);
	}

	float factor_nieve = 0.0;
	if (nieve_estacion > 0.01 && n.y > 0.30) {
		float r = 0.65 * ruido_suave(pos_mundo.xz * 0.85) + 0.35 * ruido_suave(pos_mundo.xz * 3.1);
		factor_nieve = smoothstep(0.32, 0.68, n.y + (r - 0.5) * 0.25) * nieve_estacion;
		vec3 blanco_nieve = mix(vec3(0.82, 0.87, 0.94), vec3(0.95, 0.97, 1.0), r);
		col = mix(col, blanco_nieve, factor_nieve * 0.88);
	}
	float mojado = recibe_lluvia ? humedad_h03 * (0.60 + 0.40 * n.y * n.y) * (1.0 - factor_nieve) : 0.0;
	ALBEDO = col * (1.0 - mojado * 0.20);

	float rug = rug_base;
	if (usa_rug) {
		rug = 0.0;
		if (w.x > 0.01) {
			rug += textureGrad(rug_tex, uvx, dxx, dxy).r * w.x;
		}
		if (w.y > 0.01) {
			rug += textureGrad(rug_tex, uvy, dyx, dyy).r * w.y;
		}
		if (w.z > 0.01) {
			rug += textureGrad(rug_tex, uvz, dzx, dzy).r * w.z;
		}
	}
	ROUGHNESS = mix(clamp(rug * rug_mult, 0.68, 0.98) * (1.0 - mojado * 0.52), 0.84, factor_nieve);
	METALLIC = 0.0;
	SPECULAR = 0.20 + mojado * 0.11;

	float dist = length(VERTEX);
	if (usa_normal && dist < 48.0) {
		vec3 nm = vec3(0.0);
		if (w.x > 0.01) {
			vec3 tx = normal_tangente(textureGrad(normal_tex, uvx, dxx, dxy));
			tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
			nm += tx.zyx * w.x;
		}
		if (w.y > 0.01) {
			vec3 ty = normal_tangente(textureGrad(normal_tex, uvy, dyx, dyy));
			ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
			nm += ty.xzy * w.y;
		}
		if (w.z > 0.01) {
			vec3 tz = normal_tangente(textureGrad(normal_tex, uvz, dzx, dzy));
			tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
			nm += tz.xyz * w.z;
		}
		nm = normalize(nm);
		nm = mix(nm, n, factor_nieve * 0.75);
		float lod_n = smoothstep(32.0, 48.0, dist);
		nm = normalize(mix(nm, n, lod_n));
		NORMAL = normalize((VIEW_MATRIX * vec4(nm, 0.0)).xyz);
	}
}
