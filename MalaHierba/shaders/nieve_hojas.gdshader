// Mala Hierba · capa invernal sin alpha blending para tarjetas de agujas, helechos y hierba (T15).
// Se usa en next_pass sobre StandardMaterial3D para conservar intactos T18 y T19.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, depth_test_default;

global uniform float nieve_estacion;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool usa_alpha = true;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	VERTEX += NORMAL * 0.002;
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float ruido_val(vec2 p) {
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
	if (nieve_estacion < 0.05) {
		discard;
	}
	if (usa_alpha && texture(albedo_tex, UV).a < 0.5) {
		discard;
	}
	float r = 0.6 * ruido_val(pos_mundo.xz * 2.4 + pos_mundo.y * 1.1) + 0.4 * ruido_val(UV * 18.0);
	float cara_arriba = clamp(abs(normal_mundo.y) * 0.55 + normal_mundo.y * 0.35 + (1.0 - UV.y) * 0.35, 0.0, 1.0);
	if (cara_arriba + r * 0.45 < 0.72) {
		discard;
	}
	ALBEDO = mix(vec3(0.84, 0.89, 0.96), vec3(0.96, 0.98, 1.0), r);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
