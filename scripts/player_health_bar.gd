class_name PlayerHealthBar
extends Control

@export var bar_width: float = 140.0
@export var bar_height: float = 10.0
@export var border_color: Color = Color(0.06, 0.06, 0.08, 1.0)
@export var bg_color: Color = Color(0.18, 0.04, 0.04, 0.9)
@export var fill_color: Color = Color(0.85, 0.12, 0.12, 1.0)
@export var ghost_color: Color = Color(0.92, 0.65, 0.15, 1.0)
@export var highlight_color: Color = Color(1.0, 0.35, 0.35, 0.75)

var current_ratio: float = 1.0
var ghost_ratio: float = 1.0
var ghost_tween: Tween = null

func _ready() -> void:
	custom_minimum_size = Vector2(bar_width + 4, bar_height + 4)
	queue_redraw()

func _draw() -> void:
	var ox = 2.0
	var oy = 2.0
	# 2px dark border
	draw_rect(Rect2(ox - 2, oy - 2, bar_width + 4, bar_height + 4), border_color)
	# Depleted background
	draw_rect(Rect2(ox, oy, bar_width, bar_height), bg_color)
	# Ghost bar (delayed damage trail like in Souls games)
	if ghost_ratio > 0.0:
		draw_rect(Rect2(ox, oy, bar_width * ghost_ratio, bar_height), ghost_color)
	# Current health fill
	if current_ratio > 0.0:
		var fill_w = bar_width * current_ratio
		draw_rect(Rect2(ox, oy, fill_w, bar_height), fill_color)
		# 2px top highlight for depth
		draw_rect(Rect2(ox, oy, fill_w, 2), highlight_color)

func set_health(current: float, maximum: float) -> void:
	var target_ratio = clampf(current / maximum, 0.0, 1.0)
	current_ratio = target_ratio
	queue_redraw()
	
	if ghost_tween:
		ghost_tween.kill()
	
	ghost_tween = create_tween()
	ghost_tween.tween_interval(0.3)
	ghost_tween.tween_method(func(val: float):
		ghost_ratio = val
		queue_redraw()
	, ghost_ratio, target_ratio, 0.35)
