shader_type spatial;
// Pasada de brillo para los enemigos de la mina (E1): se añade como next_pass al material del modelo.
// Los .glb del compañero no traen mapa de emisión, así que el brillo (lava, cristal, babosa, polilla) se saca de
// los píxeles claros y saturados de su propia textura de color. No cambia el aspecto del modelo, solo lo hace brillar.
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform sampler2D tex_color : source_color, filter_linear_mipmap, repeat_enable;
uniform float umbral_luz = 0.5;
uniform float umbral_sat = 0.5;
uniform float fuerza = 1.2;
uniform vec3 tinte : source_color = vec3(1.0);
uniform float pulso = 0.0;

void fragment() {
	vec3 c = texture(tex_color, UV).rgb;
	float mx = max(max(c.r, c.g), c.b);
	float mn = min(min(c.r, c.g), c.b);
	float sat = (mx - mn) / max(mx, 0.001);
	float m = smoothstep(umbral_luz - 0.12, umbral_luz + 0.12, mx) * smoothstep(umbral_sat - 0.15, umbral_sat + 0.15, sat);
	float vibra = 1.0 + pulso * sin(TIME * 2.6);
	ALBEDO = c * m * fuerza * vibra * tinte;
}
