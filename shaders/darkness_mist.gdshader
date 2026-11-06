shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.02, 0.02, 0.035, 0.985);
uniform vec4 mist_highlight : source_color = vec4(0.09, 0.08, 0.14, 1.0);
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.35;
uniform float density : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 6.0;
	float t = TIME * swirl_speed;
	float n1 = fbm(uv + vec2(t * 0.6, -t * 0.4));
	float n2 = fbm(uv * 1.4 - vec2(t * 0.5, t * 0.7) + n1 * 1.2);
	float mist = smoothstep(0.25, 0.85, n2);
	
	vec3 col = mix(base_color.rgb, mist_highlight.rgb, mist * 0.55);
	
	// Softly feather the edges so mist blends smoothly into dungeon corridors
	float edge_x = smoothstep(0.0, 0.06, UV.x) * smoothstep(0.0, 0.06, 1.0 - UV.x);
	float edge_y = smoothstep(0.0, 0.06, UV.y) * smoothstep(0.0, 0.06, 1.0 - UV.y);
	float edge_alpha = edge_x * edge_y;
	
	COLOR = vec4(col, base_color.a * density * edge_alpha * COLOR.a);
}
