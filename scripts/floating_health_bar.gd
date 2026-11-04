class_name FloatingHealthBar
extends Node2D

@export var bar_width: float = 20.0
@export var bar_height: float = 3.0
@export var border_color: Color = Color(0.06, 0.06, 0.08, 1.0)
@export var bg_color: Color = Color(0.18, 0.04, 0.04, 0.85)
@export var fill_color: Color = Color(0.85, 0.12, 0.12, 1.0)
@export var ghost_color: Color = Color(0.92, 0.65, 0.15, 1.0)

var current_ratio: float = 1.0
var ghost_ratio: float = 1.0
var ghost_tween: Tween = null

func _ready() -> void:
	z_index = 10
	queue_redraw()

func _draw() -> void:
	var half_w = bar_width / 2.0
	# 1px border
	draw_rect(Rect2(-half_w - 1, -1, bar_width + 2, bar_height + 2), border_color)
	# Depleted background
	draw_rect(Rect2(-half_w, 0, bar_width, bar_height), bg_color)
	# Ghost bar (delayed damage trail like in Souls games)
	if ghost_ratio > 0.0:
		draw_rect(Rect2(-half_w, 0, bar_width * ghost_ratio, bar_height), ghost_color)
	# Current health fill
	if current_ratio > 0.0:
		draw_rect(Rect2(-half_w, 0, bar_width * current_ratio, bar_height), fill_color)

func set_health(current: float, maximum: float) -> void:
	var target_ratio = clampf(current / maximum, 0.0, 1.0)
	current_ratio = target_ratio
	queue_redraw()
	
	if ghost_tween:
		ghost_tween.kill()
	
	ghost_tween = create_tween()
	ghost_tween.tween_interval(0.25)
	ghost_tween.tween_method(func(val: float):
		ghost_ratio = val
		queue_redraw()
	, ghost_ratio, target_ratio, 0.35)
