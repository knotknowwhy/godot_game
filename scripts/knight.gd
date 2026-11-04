extends CharacterBody2D

@onready var see_shape_knight: CollisionShape2D = $see_area_knight/see_shape_knight
@onready var ground_collisison_knight: CollisionShape2D = $ground_collisison_knight
@onready var hit_shape_knight: CollisionShape2D = $hit_area_knight/hit_shape_knight
@onready var attack_shape_knight: CollisionShape2D = $attack_area_knight/attack_shape_knight
@onready var animation: AnimatedSprite2D = $animation

func _physics_process(delta: float) -> void:
	move_and_slide()

func _on_see_area_knight_area_entered(area: Area2D) -> void:
	pass # Replace with function body.

func _on_see_area_knight_area_exited(area: Area2D) -> void:
	pass # Replace with function body.

func _on_hit_area_knight_area_entered(area: Area2D) -> void:
	pass # Replace with function body.

func _on_attack_area_knight_area_entered(area: Area2D) -> void:
	pass # Replace with function body.
