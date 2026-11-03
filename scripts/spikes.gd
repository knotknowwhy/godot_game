extends Node2D

@onready var animations: AnimatedSprite2D = $animations
@onready var kill_zone: Area2D = $kill_zone
@onready var detect_area: Area2D = $detect_area
@onready var hit_shape: CollisionShape2D = $kill_zone/hit_shape
@onready var detect_shape: CollisionShape2D = $detect_area/detect_shape
@onready var before_spike_up: Timer = $before_spike_up
@onready var reset_after_spike_up: Timer = $reset_after_spike_up

func _ready() -> void:
	animations.play("down")
	hit_shape.disabled = true
	detect_shape.disabled = false

func _process(delta: float) -> void:
	pass

func _on_before_spike_up_timeout() -> void:
	animations.play("up")
	reset_after_spike_up.start()

func _on_detect_area_body_entered(body: Node2D) -> void:
	before_spike_up.start()

func _on_reset_after_spike_up_timeout() -> void:
	animations.play("down")

func _on_animations_animation_finished() -> void:
	if animations.animation == "up":
		hit_shape.disabled = false
		detect_shape.disabled = true
		reset_after_spike_up.start()
	if animations.animation == "down":
		hit_shape.disabled = true
		detect_shape.disabled = false
