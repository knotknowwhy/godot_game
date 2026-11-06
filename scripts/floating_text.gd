extends Node2D

@onready var label: Label = $Label

func spawn(text: String, color: Color = Color.WHITE, font_size: int = 10, rise_distance: float = 18.0, duration: float = 0.6) -> void:
	if not label:
		label = $Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	
	scale = Vector2(0.5, 0.5)
	modulate.a = 1.0
	
	var tw = create_tween()
	# Pop in scale punch
	tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Float upward smoothly
	tw.parallel().tween_property(self, "position:y", position.y - rise_distance, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade out near end of float
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)
