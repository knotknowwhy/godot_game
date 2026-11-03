extends CharacterBody2D

@onready var animation: AnimatedSprite2D = $animation
@onready var ground_collision: CollisionShape2D = $ground_collision
@onready var hit_area: Area2D = $hit_area
@onready var attack_area: Area2D = $attack_area_skelet
@onready var hit_shape: CollisionShape2D = $hit_area/hit_shape
@onready var attack_shape: CollisionShape2D = $attack_area_skelet/attack_shape
@onready var skeleton: CharacterBody2D = $"."

const SPEED = 60.0
var facing_direction: Vector2 = Vector2.DOWN

var health: int = 100
var player_target: Node2D = null

func _physics_process(delta: float) -> void:
	
	if player_target:
		velocity = global_position.direction_to(player_target.global_position) * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)
	
	if velocity != Vector2.ZERO:
		facing_direction = velocity.normalized()
	
	if velocity != Vector2.ZERO:
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				animation.play("walk_right")
			else:
				animation.play("walk_left")
		else:
			if facing_direction.y > 0:
				animation.play("walk_down")
			else:
				animation.play("walk_up")
	else:
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				animation.play("idle_right")
			else:
				animation.play("idle_left")
		else:
			if facing_direction.y > 0:
				animation.play("idle_down")
			else:
				animation.play("idle_up")
	move_and_slide()

func _on_hit_area_area_entered(area: Area2D) -> void:
	if area.name == "attack_area_player":
		health -= 35
		print("Skeleton took damage! Current health: ", health)
		
		if health <= 0:
			queue_free()

func _on_see_area_area_entered(area: Area2D) -> void:
	if area.name == "player":
		print("spotted")
		player_target = area

func _on_see_area_area_exited(area: Area2D) -> void:
	if area == player_target:
		print("not interested")
		player_target = null
