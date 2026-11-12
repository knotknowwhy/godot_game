class_name BossHealthBar
extends Control

@export var bar_width: float = 360.0
@export var bar_height: float = 14.0
@export var border_color: Color = Color(0.05, 0.05, 0.07, 1.0)
@export var outer_trim_color: Color = Color(0.45, 0.36, 0.22, 0.9)
@export var bg_color: Color = Color(0.16, 0.03, 0.04, 0.92)
@export var fill_color: Color = Color(0.82, 0.10, 0.14, 1.0)
@export var ghost_color: Color = Color(0.95, 0.68, 0.18, 1.0)
@export var highlight_color: Color = Color(1.0, 0.38, 0.38, 0.7)

var current_ratio: float = 1.0
var ghost_ratio: float = 1.0
var ghost_tween: Tween = null
var is_enraged: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(bar_width + 8, bar_height + 8)
	queue_redraw()

func set_enraged(enraged: bool) -> void:
	is_enraged = enraged
	if is_enraged:
		outer_trim_color = Color(0.85, 0.28, 0.18, 0.95)
		fill_color = Color(0.95, 0.22, 0.12, 1.0)
		highlight_color = Color(1.0, 0.68, 0.32, 0.8)
	queue_redraw()

func _draw() -> void:
	var ox = 4.0
	var oy = 4.0
	# Outer metallic trim (1px) + dark border (3px)
	draw_rect(Rect2(ox - 4, oy - 4, bar_width + 8, bar_height + 8), outer_trim_color)
	draw_rect(Rect2(ox - 3, oy - 3, bar_width + 6, bar_height + 6), border_color)
	# Depleted background
	draw_rect(Rect2(ox, oy, bar_width, bar_height), bg_color)
	# Delayed damage trail (Souls-like ghost bar)
	if ghost_ratio > 0.0:
		draw_rect(Rect2(ox, oy, bar_width * ghost_ratio, bar_height), ghost_color)
	# Current health fill
	if current_ratio > 0.0:
		var fill_w = bar_width * current_ratio
		draw_rect(Rect2(ox, oy, fill_w, bar_height), fill_color)
		# Top specular highlight
		draw_rect(Rect2(ox, oy, fill_w, 3), highlight_color)
	# 50% Phase 2 threshold notch
	var mid_x = ox + bar_width * 0.5
	draw_rect(Rect2(mid_x - 1.0, oy, 2.0, bar_height), Color(0.05, 0.05, 0.07, 0.75))

func set_health(current: float, maximum: float) -> void:
	var target_ratio = clampf(current / maxf(1.0, maximum), 0.0, 1.0)
	current_ratio = target_ratio
	queue_redraw()
	
	if ghost_tween:
		ghost_tween.kill()
	
	ghost_tween = create_tween()
	ghost_tween.tween_interval(0.28)
	ghost_tween.tween_method(func(val: float):
		ghost_ratio = val
		queue_redraw()
	, ghost_ratio, target_ratio, 0.38)
