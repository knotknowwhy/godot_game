extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

const SPEED = 100.0

var isAttacking = false
var isBlocking = false

func _physics_process(delta: float) -> void:
	
	var direction_x := Input.get_axis("ui_left", "ui_right")
	var direction_y := Input.get_axis("ui_up", "ui_down")
	
	if direction_y:
		velocity.y = direction_y * SPEED
	elif not direction_y:
		velocity.y = move_toward(velocity.y, 0, SPEED)
	
	if direction_x:
		velocity.x = direction_x * SPEED
	elif not direction_x:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	move_and_slide()
