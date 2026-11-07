class_name ControlsHint
extends Control

@export var initial_visible_duration: float = 10.0
@export var fade_in_duration: float = 0.25
@export var fade_out_duration: float = 0.45
@export var corner_trigger_margin: float = 40.0

@onready var panel: Control = $panel

var initial_timer: float = 0.0
var is_cursor_in_corner: bool = false
var is_visible_target: bool = true
var fade_tween: Tween = null

func _ready() -> void:
	initial_timer = initial_visible_duration
	modulate.a = 1.0

func _process(delta: float) -> void:
	if initial_timer > 0.0:
		initial_timer -= delta
	
	_check_cursor_in_corner()
	
	var should_be_visible := (initial_timer > 0.0) or is_cursor_in_corner
	
	if should_be_visible != is_visible_target:
		is_visible_target = should_be_visible
		_fade_to(1.0 if is_visible_target else 0.0, fade_in_duration if is_visible_target else fade_out_duration)

func _check_cursor_in_corner() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var mouse_pos: Vector2 = vp.get_mouse_position()
	
	if panel:
		var rect: Rect2 = panel.get_global_rect()
		var vp_size: Vector2 = get_viewport_rect().size
		# Generous corner trigger bounds encompassing the panel and screen margins
		var trigger_rect := Rect2(
			0.0,
			maxf(0.0, rect.position.y - corner_trigger_margin),
			rect.position.x + rect.size.x + corner_trigger_margin,
			maxf(rect.size.y + corner_trigger_margin * 2.0, vp_size.y - rect.position.y + corner_trigger_margin)
		)
		is_cursor_in_corner = trigger_rect.has_point(mouse_pos)
	else:
		var vp_size: Vector2 = get_viewport_rect().size
		var trigger_rect := Rect2(0.0, vp_size.y - 250.0, 300.0, 250.0)
		is_cursor_in_corner = trigger_rect.has_point(mouse_pos)

func _fade_to(target_alpha: float, duration: float) -> void:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", target_alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
