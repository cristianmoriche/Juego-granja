shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

global uniform float viento_h03;
global uniform float humedad_h03;
global uniform float nieve_estacion;
global uniform int calidad_h03;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rug_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tinte : source_color = vec4(1.0);
uniform bool usa_normal = false;
uniform bool usa_rug = false;
uniform float rug_base = 0.9;
uniform float flexion = 0.09;
uniform float transmision = 0.3;
uniform bool es_hierba = false;

varying vec3 posicion_mundo;
varying vec3 normal_mundo;
varying float dist_cam;

void vertex() {
	vec3 raiz = MODEL_MATRIX[3].xyz;
	bool es_persp = PROJECTION_MATRIX[3][3] < 0.5;
	float distancia = es_persp ? distance(raiz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) : 0.0;
	dist_cam = distancia;
	float cobertura = 1.0;
	if (es_hierba) {
		bool refuerzo = INSTANCE_CUSTOM.x > 0.5;
		// La foto cenital ortográfica conserva todas las matas originales.
		cobertura = refuerzo ? 0.0 : 1.0;
		if (es_persp) {
			if (refuerzo) {
				cobertura = (calidad_h03 >= 2) ? (1.0 - smoothstep(12.0, 25.0, distancia)) : 0.0;
			} else {
				cobertura = 1.0 - smoothstep(42.0, 65.0, distancia);
			}
		}
	}
	if (cobertura > 0.001) {
		if (es_hierba) {
			VERTEX = mix(raiz, VERTEX, cobertura);
		}
		float altura = max(0.0, VERTEX.y - raiz.y);
		vec2 viento = vec2(0.92074, 0.39018);
		float fase = dot(raiz.xz, viento);
		float rafaga = 0.56 * sin(TIME * 1.9 - fase * 0.54);
		if (!es_persp || distancia <= 40.0) {
			rafaga += 0.31 * sin(TIME * 3.1 - fase * 0.18 + VERTEX.y * 0.8);
			rafaga += 0.13 * sin(TIME * 5.3 + VERTEX.x * 1.6);
		}
		float respuesta = altura / (altura + 0.46);
		VERTEX.xz += viento * rafaga * respuesta * flexion * viento_h03;
		posicion_mundo = VERTEX;
		normal_mundo = normalize(NORMAL);
	} else {
		VERTEX = raiz;
		posicion_mundo = raiz;
		normal_mundo = vec3(0.0, 1.0, 0.0);
	}
}

void fragment() {
	vec4 hoja = texture(albedo_tex, UV) * tinte;
	ALPHA = hoja.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 color = hoja.rgb;
	float rugosidad = usa_rug ? texture(rug_tex, UV).r * rug_base : rug_base;
	float nieve = 0.0;
	if (nieve_estacion > 0.05) {
		vec3 n = normalize(normal_mundo);
		vec3 fase = posicion_mundo * vec3(6.3, 9.2, 7.1);
		float veteado = 0.5 + 0.26 * sin(fase.x + sin(fase.z)) * cos(fase.y - fase.z);
		float cara_superior = abs(n.y) * 0.55 + n.y * 0.35 + (1.0 - UV.y) * 0.35;
		nieve = smoothstep(0.68, 0.81, cara_superior + veteado * 0.45) * nieve_estacion;
		color = mix(color, mix(vec3(0.74, 0.81, 0.91), vec3(0.94, 0.97, 1.0), veteado), nieve);
	}
	float mojado = humedad_h03 * (1.0 - nieve);
	ALBEDO = color * (1.0 - 0.20 * mojado);
	ROUGHNESS = mix(rugosidad * (1.0 - 0.30 * mojado), 0.85, nieve);
	SPECULAR = 0.1 + 0.12 * mojado;
	BACKLIGHT = hoja.rgb * transmision * (1.0 - nieve);
	if (usa_normal && dist_cam < 28.0) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = (1.0 - 0.68 * nieve) * (1.0 - smoothstep(18.0, 28.0, dist_cam));
	}
}
