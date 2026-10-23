extends CharacterBody2D

@onready var player_animation: AnimatedSprite2D = $player_animation
@onready var block_shape: CollisionShape2D = $block_area/block_shape
@onready var attack_shape: CollisionShape2D = $attack_area/attack_shape
@onready var max_block_time: Timer = $max_block_time

const SPEED = 100.0

var isAttacking = false
var isBlocking = false

var facing_direction: Vector2 = Vector2.DOWN

func _physics_process(delta: float) -> void:
	
	# get direction inputs
	var direction_x := 0.0
	if Input.is_action_pressed("Right") && isAttacking == false && isBlocking == false:
		direction_x += 1.0
	if Input.is_action_pressed("Left") && isAttacking == false && isBlocking == false:
		direction_x -= 1.0
	
	var direction_y := 0.0
	if Input.is_action_pressed("Down") && isAttacking == false && isBlocking == false:
		direction_y += 1.0
	if Input.is_action_pressed("Up") && isAttacking == false && isBlocking == false:
		direction_y -= 1.0
		
	var input_direction := Vector2(direction_x, direction_y)
	
	if input_direction != Vector2.ZERO:
		facing_direction = input_direction.normalized()
	
	# aply vel
	if direction_y:
		velocity.y = direction_y * SPEED
	else:
		velocity.y = move_toward(velocity.y, 0, SPEED)
		
	if direction_x:
		velocity.x = direction_x * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
	
	# walk and idle
	if input_direction != Vector2.ZERO && isAttacking == false && isBlocking == false:
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				player_animation.play("walk_right")
			else:
				player_animation.play("walk_left")
		else:
			if facing_direction.y > 0:
				player_animation.play("walk_down")
			else:
				player_animation.play("walk_up")
	elif isAttacking == false && isBlocking == false:
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				player_animation.play("idle_right")
			else:
				player_animation.play("idle_left")
		else:
			if facing_direction.y > 0:
				player_animation.play("idle_down")
			else:
				player_animation.play("idle_up")
	
	# attack animation
	if Input.is_action_just_pressed("Attack_sword") && isBlocking == false:
		isAttacking = true
		attack_shape.disabled = false
		var capsule = attack_shape.shape as CapsuleShape2D
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				player_animation.play("attack_right")
				attack_shape.position = Vector2(15, 0)
				attack_shape.rotation = 1.5707963268
				capsule.radius = 13.0
				capsule.height = 38.0
			else:
				player_animation.play("attack_left")
				attack_shape.position = Vector2(-15, 0)
				attack_shape.rotation = 1.5707963268
				capsule.radius = 13.0
				capsule.height = 38.0
		else:
			if facing_direction.y > 0:
				player_animation.play("attack_down")
				attack_shape.position = Vector2(-1, 12)
				attack_shape.rotation = 1.5707963268
				capsule.radius = 15.0
				capsule.height = 38.0
			else:
				player_animation.play("attack_up")
				attack_shape.position = Vector2(-1, -7)
				attack_shape.rotation = 1.5707963268
				capsule.radius = 11.0
				capsule.height = 38.0
	
	# block animation
	if Input.is_action_just_pressed("Block_sword") && isAttacking == false:
		isBlocking = true
		block_shape.disabled = false
		max_block_time.start()
		
		if abs(facing_direction.x) > abs(facing_direction.y):
			if facing_direction.x > 0:
				player_animation.play("block_right")
				block_shape.position = Vector2(8, 1)
				(block_shape.shape as RectangleShape2D).size = Vector2(12, 17)
			else:
				player_animation.play("block_left")
				block_shape.position = Vector2(-9, 1.5)
				(block_shape.shape as RectangleShape2D).size = Vector2(12, 17)
		else:
			if facing_direction.y > 0:
				player_animation.play("block_down")
				block_shape.position = Vector2(0, 10.25)
				block_shape.rotation = 0.0 
				(block_shape.shape as RectangleShape2D).size = Vector2(12, 11.5)
			else:
				player_animation.play("block_up")
				block_shape.position = Vector2(0, -8)
				block_shape.rotation = 0.0
				(block_shape.shape as RectangleShape2D).size = Vector2(12, 11.5)
	
	
	if isBlocking and Input.is_action_just_released("Block_sword"):
		isBlocking = false
		block_shape.disabled = true
	
	move_and_slide()

func _on_player_animation_animation_finished() -> void:
	if player_animation.animation == "attack_right" or player_animation.animation == "attack_left" or player_animation.animation == "attack_up" or player_animation.animation == "attack_down":
		isAttacking = false
		attack_shape.disabled = true
	
	if player_animation.animation == "block_right" or player_animation.animation == "block_left" or player_animation.animation == "block_up" or player_animation.animation == "block_down":
		if not Input.is_action_pressed("Block_sword"):
			isBlocking = false
			block_shape.disabled = true


func _on_max_block_time_timeout() -> void:
	isBlocking = false
	block_shape.disabled = true
