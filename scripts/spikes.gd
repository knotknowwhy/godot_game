extends Node2D

@onready var something_on_top: CollisionShape2D = $something_on_top/something_on_top
@onready var kill_zone: CollisionShape2D = $kill_zone/kill_zone
@onready var before_collision: Timer = $before_collision
@onready var after_collision: Timer = $after_collision
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass

func _on_before_collision_timeout() -> void:
	animated_sprite_2d.play("up")
	kill_zone.disabled = false
	something_on_top.disabled = true
	after_collision.start()

func _on_after_collision_timeout() -> void:
	animated_sprite_2d.play("down")
	kill_zone.disabled = true
	something_on_top.disabled = false

func _on_something_on_top_area_entered(area: Area2D) -> void:
	before_collision.start()
