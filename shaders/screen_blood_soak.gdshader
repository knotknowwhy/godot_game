shader_type canvas_item;

// Fullscreen procedural blood soak shader for cinematic death sequence

uniform float blood_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 blood_color : source_color = vec4(0.48, 0.03, 0.06, 0.96);
uniform vec4 coagulated_color : source_color = vec4(0.15, 0.01, 0.02, 0.98);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = rot * p * 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	if (blood_progress <= 0.001) {
		COLOR = vec4(0.0);
		discard;
	}
	
	vec2 uv = UV;
	
	// 1. Organic edge soak creeping inward from all 4 borders
	float edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float edge_noise = fbm(uv * 7.5 + vec2(0.0, TIME * 0.03));
	float soak_reach = blood_progress * 0.72;
	float soak = 1.0 - smoothstep(soak_reach * 0.35, soak_reach + 0.01, edge_dist + (edge_noise - 0.5) * 0.32);
	
	// 2. Heavy drips streaming down from the top edge
	float col_id = floor(uv.x * 16.0);
	float col_hash = hash(vec2(col_id, 3.1415));
	float drip_trigger = step(0.32, col_hash); // only certain columns drip
	float drip_max_y = col_hash * 0.95 * blood_progress * 1.45;
	
	// Drip body
	float col_x_fract = fract(uv.x * 16.0);
	float drip_width = (1.0 - smoothstep(0.0, drip_max_y, uv.y)) * 0.38 + 0.14;
	float in_drip_x = 1.0 - smoothstep(drip_width * 0.5, drip_width, abs(col_x_fract - 0.5));
	float in_drip_y = 1.0 - smoothstep(drip_max_y - 0.08, drip_max_y, uv.y);
	float drip = in_drip_x * in_drip_y * drip_trigger;
	
	// Bulbous droplet head at the tip
	float tip_dist = length(vec2(col_x_fract - 0.5, (uv.y - drip_max_y) * 2.2));
	float drip_head = (1.0 - smoothstep(0.12, 0.24, tip_dist)) * drip_trigger * step(0.04, drip_max_y);
	
	// 3. Dynamic blood splatters across the screen
	vec2 splat_grid = uv * 6.5;
	vec2 splat_cell = floor(splat_grid);
	vec2 splat_uv = fract(splat_grid);
	float splat_hash = hash(splat_cell);
	float splat_rad = splat_hash * 0.44 * smoothstep(0.08, 0.75, blood_progress);
	vec2 splat_center = vec2(hash(splat_cell + 1.2), hash(splat_cell + 3.7)) * 0.6 + 0.2;
	float splat_dist = length(splat_uv - splat_center);
	float splat_noise = fbm(splat_uv * 8.0);
	float splat = (1.0 - smoothstep(splat_rad * 0.6, splat_rad, splat_dist + (splat_noise - 0.5) * 0.16)) * step(0.42, splat_hash);
	
	// 4. Center vignette soak closing in at high progress
	float center_dist = length(uv - vec2(0.5));
	float center_soak = smoothstep(0.68 - blood_progress * 0.5, 1.15 - blood_progress * 0.4, center_dist);
	
	// Combine all blood masks
	float total_mask = clamp(soak * 1.15 + drip * 1.25 + drip_head * 1.4 + splat * 1.2 + center_soak * blood_progress * 1.2, 0.0, 1.0);
	
	if (total_mask <= 0.005) {
		COLOR = vec4(0.0);
		discard;
	}
	
	// Two-tone blood: coagulated dark maroon at borders, rich arterial crimson in thickest parts
	float core_factor = smoothstep(0.35, 0.82, total_mask);
	vec3 final_rgb = mix(coagulated_color.rgb, blood_color.rgb, core_factor);
	
	// Subtle specular gloss highlight on the wet blood surface
	float wet_spec = pow(max(0.0, 1.0 - abs(total_mask - 0.72) * 4.0), 3.0) * 0.24;
	final_rgb += vec3(wet_spec);
	
	float alpha = smoothstep(0.02, 0.16, total_mask) * mix(0.86, 0.99, blood_progress);
	COLOR = vec4(final_rgb, alpha);
}
