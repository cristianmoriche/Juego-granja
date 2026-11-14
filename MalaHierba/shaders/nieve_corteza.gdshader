// Mala Hierba · capa invernal opaca sobre cortezas, tocones, rocas, vallas y parcelas (T15).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, depth_test_default;

global uniform float nieve_estacion;

uniform float umbral = 0.42;

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
	float r = 0.65 * ruido_val(pos_mundo.xz * 1.9 + pos_mundo.y * 0.7) + 0.35 * ruido_val(pos_mundo.xz * 7.5);
	if (normal_mundo.y + (r - 0.5) * 0.25 < umbral) {
		discard;
	}
	ALBEDO = mix(vec3(0.83, 0.88, 0.96), vec3(0.95, 0.97, 1.0), r);
	ROUGHNESS = 0.84;
	METALLIC = 0.0;
}
