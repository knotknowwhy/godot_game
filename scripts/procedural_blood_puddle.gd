extends Node2D

# Procedural Blood Puddle that organically pools and expands across dungeon tiles.

@export var max_radius: float = 13.5
@export var growth_duration: float = 3.4
@export var segments: int = 64

var current_progress: float = 0.0 # 0.0 to 1.0
var is_growing: bool = true

# Harmonic noise parameters generated on init
var harmonics: Array = []
var lobes: Array = []
var droplets: Array = []

# Two-tone blood colors matching dungeon art style
var outer_color: Color = Color(0.18, 0.015, 0.025, 0.96) # Dark coagulated border
var inner_color: Color = Color(0.52, 0.045, 0.075, 0.95) # Fresh arterial crimson
var sheen_color: Color = Color(0.78, 0.18, 0.22, 0.35) # Glossy surface reflection

func _ready() -> void:
	z_index = 0 # Render at parent's z_index (above floor tilemap z=1) and behind parent's sprite via child index 0
	if get_parent():
		get_parent().move_child.call_deferred(self, 0)
	_generate_procedural_shape()

func _generate_procedural_shape() -> void:
	# Randomize harmonic frequencies and phases
	harmonics.clear()
	var freqs = [2, 3, 5, 7, 9, 11]
	for f in freqs:
		harmonics.append({
			"freq": f,
			"phase": randf_range(0.0, TAU),
			"amp": randf_range(0.04, 0.15)
		})
	
	# Randomize 3 to 5 creeping fluid lobes
	lobes.clear()
	var num_lobes = randi_range(3, 5)
	for i in range(num_lobes):
		lobes.append({
			"angle": randf_range(0.0, TAU),
			"width": randf_range(0.35, 0.68),
			"reach": randf_range(1.12, 1.32),
			"delay": randf_range(0.05, 0.25) # Reaches forward with slight fluid lag
		})
	
	# Randomize 4 to 7 satellite droplets around the periphery
	droplets.clear()
	var num_drops = randi_range(4, 7)
	for i in range(num_drops):
		var angle = randf_range(0.0, TAU)
		var dist_mult = randf_range(1.10, 1.32)
		var r = randf_range(0.7, 1.6)
		droplets.append({
			"angle": angle,
			"dist_mult": dist_mult,
			"radius": r,
			"delay": randf_range(0.2, 0.5)
		})

func _process(delta: float) -> void:
	if not is_growing:
		return
	
	current_progress += delta / growth_duration
	if current_progress >= 1.0:
		current_progress = 1.0
		is_growing = false
	
	queue_redraw()

func _draw() -> void:
	if current_progress <= 0.005:
		return
	
	# Viscous fluid expansion curve: initial burst, then steady organic creeping
	var base_t = 1.0 - pow(1.0 - current_progress, 2.2)
	
	var outer_points: PackedVector2Array = []
	var inner_points: PackedVector2Array = []
	
	for i in range(segments):
		var angle = (float(i) / float(segments)) * TAU
		
		# Base radius with harmonic deformation
		var r_mod = 1.0
		for h in harmonics:
			r_mod += h["amp"] * sin(float(h["freq"]) * angle + h["phase"])
		
		# Creeping fluid lobes
		for l in lobes:
			var angle_diff = abs(angle - l["angle"])
			if angle_diff > PI:
				angle_diff = TAU - angle_diff
			if angle_diff < l["width"]:
				var factor = cos((angle_diff / l["width"]) * (PI * 0.5))
				var lobe_t = clamp((current_progress - l["delay"]) / (1.0 - l["delay"]), 0.0, 1.0)
				var lobe_growth = 1.0 - pow(1.0 - lobe_t, 2.5)
				r_mod += (l["reach"] - 1.0) * factor * lobe_growth
		
		# Apply maximum radius and overall growth
		var r_outer = max_radius * max(0.2, r_mod) * base_t
		var r_inner = r_outer * 0.86 # Inner rich crimson body
		
		outer_points.append(Vector2(cos(angle), sin(angle)) * r_outer)
		inner_points.append(Vector2(cos(angle), sin(angle)) * r_inner)
	
	# Draw outer dark coagulated border polygon
	if outer_points.size() >= 3:
		draw_colored_polygon(outer_points, outer_color)
	
	# Draw inner rich arterial crimson puddle polygon
	if inner_points.size() >= 3:
		draw_colored_polygon(inner_points, inner_color)
	
	# Draw glossy surface sheen near center (subtle highlight)
	if base_t > 0.4:
		var sheen_scale = (base_t - 0.4) / 0.6
		var sheen_offset = Vector2(-max_radius * 0.18, -max_radius * 0.14) * sheen_scale
		draw_circle(sheen_offset, max_radius * 0.28 * sheen_scale, sheen_color)
	
	# Draw satellite droplets
	for d in droplets:
		if current_progress > d["delay"]:
			var drop_t = clamp((current_progress - d["delay"]) / (1.0 - d["delay"]), 0.0, 1.0)
			var drop_growth = 1.0 - pow(1.0 - drop_t, 2.0)
			var dist = max_radius * d["dist_mult"] * base_t
			var pos = Vector2(cos(d["angle"]), sin(d["angle"])) * dist
			var rad = d["radius"] * drop_growth
			draw_circle(pos, rad + 0.6, outer_color)
			draw_circle(pos, rad, inner_color)
