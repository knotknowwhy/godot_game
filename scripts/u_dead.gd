extends Node2D

@onready var button: Button = $Button
@onready var fade_rect: ColorRect = get_node_or_null("fade_layer/fade_rect")
var is_reloading: bool = false

func _ready() -> void:
	if not fade_rect or not is_instance_valid(fade_rect):
		fade_rect = _create_fade_overlay()
	
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.visible = true
	
	# Smooth fade-in from black when the death scene loads
	var tween = create_tween()
	tween.tween_interval(0.1)
	tween.tween_property(fade_rect, "color:a", 0.0, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if is_instance_valid(fade_rect):
			fade_rect.visible = false
	)

func _create_fade_overlay() -> ColorRect:
	var canvas = CanvasLayer.new()
	canvas.name = "fade_layer"
	canvas.layer = 100
	add_child(canvas)
	var rect = ColorRect.new()
	rect.name = "fade_rect"
	rect.color = Color(0, 0, 0, 1)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)
	return rect

func _on_button_pressed() -> void:
	if is_reloading:
		return
	is_reloading = true
	if button:
		button.disabled = true
	
	if not fade_rect or not is_instance_valid(fade_rect):
		fade_rect = _create_fade_overlay()
	
	fade_rect.visible = true
	var tween = create_tween()
	tween.tween_property(fade_rect, "color:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
