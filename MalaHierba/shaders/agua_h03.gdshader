shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_schlick_ggx;

global uniform float viento_h03;
global uniform float humedad_h03;
global uniform float luz_agua_h03;
global uniform int calidad_h03;

uniform sampler2D escena : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D profundidad : hint_depth_texture, filter_nearest;
uniform sampler2D ondas : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool es_rio = false;
varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 vista_en(vec2 uv, float z, mat4 inversa) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	z = z * 2.0 - 1.0;
#endif
	vec4 punto = inversa * vec4(uv * 2.0 - 1.0, z, 1.0);
	return punto.xyz / max(punto.w, 0.00001);
}

// Un cruce con la profundidad opaca da el reflejo. Fuera de pantalla queda el reflejo del cielo.
vec4 reflejo_pantalla(vec3 origen, vec3 direccion, mat4 proyeccion, mat4 inversa, float rug) {
	float viaje = 0.30;
	for (int i = 0; i < 12; i++) {
		vec3 punto = origen + direccion * viaje;
		vec4 clip = proyeccion * vec4(punto, 1.0);
		if (clip.w <= 0.0) {
			break;
		}
		vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.01))) || any(greaterThan(uv, vec2(0.99)))) {
			break;
		}
		float z = textureLod(profundidad, uv, 0.0).r;
		float cruce = vista_en(uv, z, inversa).z - punto.z;
		if (z > 0.00001 && cruce > 0.02 && cruce < 0.22 + viaje * 0.09) {
			vec2 borde = smoothstep(vec2(0.01), vec2(0.12), min(uv, 1.0 - uv));
			return vec4(textureLod(escena, uv, rug * 5.0).rgb, borde.x * borde.y);
		}
		viaje = viaje * 1.36 + 0.14;
	}
	return vec4(0.0);
}

void fragment() {
	float z = textureLod(profundidad, SCREEN_UV, 0.0).r;
	vec3 fondo = vista_en(SCREEN_UV, z, INV_PROJECTION_MATRIX);
	float espesor = min(22.0, max(0.0, length(fondo) - length(VERTEX)));
	float metros = z > 0.00001 ? max(0.0, pos_mundo.y - (INV_VIEW_MATRIX * vec4(fondo, 1.0)).y) : 18.0;
	vec2 flujo = es_rio ? vec2(0.08, 0.026) : vec2(0.012, 0.008);
	vec2 uv = pos_mundo.xz;
	vec2 n1 = texture(ondas, uv * 0.24 - TIME * flujo).xy * 2.0 - 1.0;
	vec2 n2 = texture(ondas, uv * 0.82 + TIME * vec2(flujo.y, -flujo.x) * 1.6).xy * 2.0 - 1.0;
	vec2 olas = (n1 * 0.75 + n2 * 0.34) * (0.70 + viento_h03 * 0.55);
	vec3 n = normalize(mat3(VIEW_MATRIX) * vec3(olas.x, 1.0, olas.y));
	float incidencia = clamp(dot(n, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - incidencia, 5.0);
	float rug = 0.085 + viento_h03 * 0.025 + humedad_h03 * 0.045;
	vec2 uv_refractado = clamp(SCREEN_UV + olas * min(espesor, 1.4) * 0.015, vec2(0.001), vec2(0.999));
	float z_refractado = textureLod(profundidad, uv_refractado, 0.0).r;
	vec3 fondo_refractado = vista_en(uv_refractado, z_refractado, INV_PROJECTION_MATRIX);
	uv_refractado = mix(uv_refractado, SCREEN_UV, step(VERTEX.z, fondo_refractado.z));
	vec3 transmision = textureLod(escena, uv_refractado, min(2.0, espesor * 0.08)).rgb;
	vec3 absorcion = exp(-vec3(0.90, 0.31, 0.22) * espesor);
	vec3 dispersion = mix(vec3(0.035, 0.098, 0.076), vec3(0.016, 0.048, 0.065), smoothstep(0.1, 2.5, metros));
	// La cámara cenital usa la iluminación fija de mediodía del minimapa.
	float luz_dispersa = PROJECTION_MATRIX[3][3] > 0.5 ? 1.0 : luz_agua_h03;
	vec3 cuerpo = transmision * absorcion + dispersion * luz_dispersa * (1.0 - absorcion);
	float rotura = smoothstep(0.32, 0.65, n1.x * 1.3 + n2.y * 0.43 + 0.27);
	float espuma = (1.0 - smoothstep(0.045, 0.38, metros)) * rotura * (es_rio ? 0.47 : 0.30);
	vec4 reflexion = vec4(0.0);
	if (calidad_h03 >= 2 && incidencia < 0.85) {
		reflexion = reflejo_pantalla(VERTEX, reflect(-VIEW, n), PROJECTION_MATRIX, INV_PROJECTION_MATRIX, rug);
	}
	ALBEDO = mix(dispersion * 0.20, vec3(0.53, 0.61, 0.59), espuma);
	NORMAL = n;
	ROUGHNESS = mix(rug, 0.64, espuma);
	SPECULAR = 0.32 * (1.0 - reflexion.a * 0.75);
	EMISSION = (cuerpo * (1.0 - fresnel) + reflexion.rgb * reflexion.a * fresnel * 0.75) * (1.0 - espuma);
	ALPHA = 1.0;
}
