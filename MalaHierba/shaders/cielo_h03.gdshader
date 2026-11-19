shader_type sky;

uniform sampler2D panorama_a : filter_linear, repeat_enable;
uniform sampler2D panorama_b : filter_linear, repeat_enable;
uniform sampler2D panorama_clima : filter_linear, repeat_enable;
uniform vec4 registro_a;
uniform vec4 registro_b;
uniform float transicion;
uniform float nubosidad;
uniform float luz_clima;
uniform float noche;
uniform vec3 astro;
uniform vec3 tinte_astro;

const float PI_LOCAL = 3.14159265;

vec2 esfera(vec3 direccion) {
	return vec2(atan(direccion.x, direccion.z) / (2.0 * PI_LOCAL) + 0.5,
		acos(clamp(direccion.y, -1.0, 1.0)) / PI_LOCAL);
}

vec3 fotografia(sampler2D foto, vec4 registro, vec2 uv, vec2 uv_astro) {
	// Registra el acimut y la elevación de la toma. El horizonte conserva su altura.
	vec2 coord = uv;
	coord.x += registro.x - uv_astro.x;
	float altura = max(0.0, 0.5 - uv.y);
	float altura_astro = clamp(0.5 - uv_astro.y, 0.018, 0.482);
	float altura_foto = 0.5 - registro.y;
	float latitud = altura < altura_astro
		? altura * altura_foto / altura_astro
		: mix(altura_foto, 0.5, (altura - altura_astro) / (0.5 - altura_astro));
	coord.y = mix(uv.y, 0.5 - latitud, registro.w * step(uv.y, 0.5));
	coord.y = clamp(coord.y, 0.0002, 0.9998);
	vec3 hdr = min(texture(foto, coord).rgb, vec3(75.0));
	// La luminaria se dibuja debajo con su diámetro angular, igual para todas las tomas.
	float brillo = max(hdr.r, max(hdr.g, hdr.b)) * registro.z;
	return hdr * registro.z / max(1.0, brillo / 3.6);
}

void sky() {
	vec2 uv = esfera(EYEDIR);
	vec3 color = vec3(0.0);
	if (nubosidad < 0.999) {
		vec2 uv_astro = esfera(astro);
		if (transicion < 0.001) {
			color = fotografia(panorama_a, registro_a, uv, uv_astro);
		} else if (transicion > 0.999) {
			color = fotografia(panorama_b, registro_b, uv, uv_astro);
		} else {
			vec3 a = fotografia(panorama_a, registro_a, uv, uv_astro);
			vec3 b = fotografia(panorama_b, registro_b, uv, uv_astro);
			color = mix(a, b, transicion);
		}
	}
	if (nubosidad > 0.001) {
		vec3 cubierto = texture(panorama_clima, vec2(uv.x, clamp(uv.y, 0.0002, 0.9998))).rgb * luz_clima;
		color = mix(color, cubierto, nubosidad);
	}
	if (!AT_CUBEMAP_PASS) {
		float angulo = dot(EYEDIR, astro);
		float halo = exp(-max(0.0, 1.0 - angulo) * 380.0);
		float disco = smoothstep(0.999984, 0.999992, angulo);
		color += tinte_astro * (disco * mix(14.0, 1.25, noche) + halo * mix(0.14, 0.012, noche))
			* (1.0 - nubosidad) * smoothstep(-0.015, 0.025, astro.y);
	}
	COLOR = color;
}
