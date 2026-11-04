extends CharacterBody2D

@onready var animation: AnimatedSprite2D = $animation
@onready var ground_collision: CollisionShape2D = $ground_collision
@onready var hit_area: Area2D = $hit_area
@onready var attack_area: Area2D = $attack_area_skelet
@onready var hit_shape: CollisionShape2D = $hit_area/hit_shape
@onready var attack_shape: CollisionShape2D = $attack_area_skelet/attack_shape
@onready var skeleton: CharacterBody2D = $"."
@onready var health_bar = $health_bar

const SPEED = 60.0
var facing_direction: Vector2 = Vector2.DOWN

@export var max_health: int = 100
@export var damage_per_hit: int = 35
@export var attack_damage: int = 20
@export var attack_range: float = 20.0
@export var attack_cooldown: float = 1.0

var health: int = max_health
var player_target: Node2D = null

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var damage_tween: Tween = null

func _ready() -> void:
	health = max_health
	if health_bar:
		health_bar.set_health(health, max_health)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	if player_target and is_instance_valid(player_target):
		var dist = global_position.distance_to(player_target.global_position)
		if dist <= attack_range:
			velocity = Vector2.ZERO
			_try_attack_player()
		else:
			velocity = global_position.direction_to(player_target.global_position) * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)
	
	if velocity != Vector2.ZERO:
		facing_direction = velocity.normalized()
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

func _try_attack_player() -> void:
	if not can_attack or is_dead:
		return
	can_attack = false
	if player_target and player_target.has_method("take_damage"):
		player_target.take_damage(attack_damage)
	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		if is_instance_valid(self):
			can_attack = true
	)

func _on_hit_area_area_entered(area: Area2D) -> void:
	if area.name == "attack_area_player" and not is_dead and not is_invulnerable:
		take_damage(damage_per_hit)

func take_damage(amount: int) -> void:
	if is_dead or is_invulnerable:
		return
	
	health = max(0, health - amount)
	print("Skeleton took damage! Current health: ", health)
	
	if health_bar:
		health_bar.set_health(health, max_health)
	
	if health <= 0:
		_die()
	else:
		_flash_red()

func _flash_red() -> void:
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.modulate = Color(1.0, 0.25, 0.25)
	damage_tween = create_tween()
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.2)
	damage_tween.tween_callback(func(): is_invulnerable = false)

func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	hit_shape.set_deferred("disabled", true)
	ground_collision.set_deferred("disabled", true)
	if attack_shape:
		attack_shape.set_deferred("disabled", true)
	
	if damage_tween:
		damage_tween.kill()
	
	if health_bar:
		var ht = create_tween()
		ht.tween_property(health_bar, "modulate:a", 0.0, 0.25)
	
	animation.modulate = Color(1.0, 0.25, 0.25)
	var death_tween = create_tween()
	death_tween.tween_property(animation, "modulate:a", 0.0, 0.25)
	death_tween.tween_callback(queue_free)

func _on_see_area_body_entered(body: Node2D) -> void:
	if body.name == "player" or body is CharacterBody2D:
		print("spotted body: ", body.name)
		player_target = body

func _on_see_area_body_exited(body: Node2D) -> void:
	if body == player_target:
		print("not interested")
		player_target = null

func _on_see_area_area_entered(area: Area2D) -> void:
	if area.owner and area.owner.name == "player":
		player_target = area.owner
	elif area.get_parent() and area.get_parent().name == "player":
		player_target = area.get_parent()

func _on_see_area_area_exited(area: Area2D) -> void:
	if player_target and (area.owner == player_target or area.get_parent() == player_target):
		player_target = null
