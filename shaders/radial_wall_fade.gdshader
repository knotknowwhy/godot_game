shader_type canvas_item;

uniform vec2 player_pos = vec2(0.0);
uniform float radius : hint_range(10.0, 150.0) = 45.0;
uniform float softness : hint_range(1.0, 50.0) = 18.0;
uniform float min_alpha : hint_range(0.0, 1.0) = 0.62;
uniform float fade_active : hint_range(0.0, 1.0) = 0.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (fade_active > 0.001) {
		float dist = distance(world_pos, player_pos);
		float circle = smoothstep(radius - softness, radius, dist);
		float target_a = mix(min_alpha, 1.0, circle);
		col.a *= mix(1.0, target_a, fade_active);
	}
	COLOR = col;
}
