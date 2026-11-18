shader_type canvas_item;
render_mode unshaded;

uniform float intensidad : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float borde = smoothstep(0.59, 1.18, length(p));
	COLOR = vec4(0.41, 0.018, 0.021, borde * intensidad);
}
