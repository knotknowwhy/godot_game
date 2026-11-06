extends CharacterBody2D

signal enemy_died(enemy)

enum State {
	IDLE,
	CHASE,
	TELEGRAPH,
	LUNGE,
	RECOVERY,
	STAGGERED,
	COOLDOWN
}

@onready var animation: AnimatedSprite2D = $animation
@onready var ground_collision: CollisionShape2D = $ground_collision
@onready var hit_area: Area2D = $hit_area
@onready var attack_area: Area2D = $attack_area_skelet
@onready var hit_shape: CollisionShape2D = $hit_area/hit_shape
@onready var attack_shape: CollisionShape2D = $attack_area_skelet/attack_shape
@onready var skeleton: CharacterBody2D = $"."
@onready var health_bar = $health_bar

const SPEED = 60.0
const LUNGE_SPEED = 175.0
var facing_direction: Vector2 = Vector2.DOWN
var attack_direction: Vector2 = Vector2.DOWN

@export var max_health: int = 100
@export var damage_per_hit: int = 35
@export var attack_damage: int = 20
@export var attack_range: float = 30.0
@export var attack_cooldown: float = 1.0

var current_state: State = State.IDLE
var health: int = max_health
var player_target: Node2D = null

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var damage_tween: Tween = null
var attack_tween: Tween = null
var windup_shake_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	if health_bar:
		health_bar.set_health(health, max_health)
	_find_player_target()

func _find_player_target() -> void:
	if not player_target or not is_instance_valid(player_target):
		var p = get_tree().get_first_node_in_group("player")
		if not p:
			var players = get_tree().root.find_children("player", "CharacterBody2D", true, false)
			if players.size() > 0:
				p = players[0]
		if p:
			player_target = p

func _get_separation_vector() -> Vector2:
	var push = Vector2.ZERO
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == self or not is_instance_valid(e):
			continue
		var diff = global_position - e.global_position
		var d = diff.length()
		if d > 0.001 and d < 22.0:
			push += (diff / d) * (1.0 - d / 22.0)
	return push

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	match current_state:
		State.IDLE, State.COOLDOWN:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.0)
			if player_target and is_instance_valid(player_target):
				if current_state != State.COOLDOWN and can_attack:
					current_state = State.CHASE
				else:
					# During cooldown, face the player while standing or recovering
					facing_direction = global_position.direction_to(player_target.global_position)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.CHASE:
			if player_target and is_instance_valid(player_target):
				var dist = global_position.distance_to(player_target.global_position)
				if dist <= attack_range and can_attack:
					_start_telegraph()
				else:
					var target_dir = global_position.direction_to(player_target.global_position)
					var sep = _get_separation_vector()
					var move_dir = (target_dir + sep * 0.85).normalized()
					velocity = move_dir * SPEED
					facing_direction = target_dir
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
				current_state = State.IDLE
			_update_animation_by_velocity()
			move_and_slide()
			
		State.TELEGRAPH:
			velocity = Vector2.ZERO
			# Anticipation tremble / shake
			windup_shake_timer += delta * 35.0
			animation.position.x = sin(windup_shake_timer) * 1.5
			# Lock facing direction toward target at start of windup
			if player_target and is_instance_valid(player_target):
				attack_direction = global_position.direction_to(player_target.global_position)
				facing_direction = attack_direction
			_update_idle_animation()
			move_and_slide()
			
		State.LUNGE:
			# Fast forward thrust toward target
			velocity = attack_direction * LUNGE_SPEED
			move_and_slide()
			
		State.RECOVERY:
			# Committed vulnerability pause after strike
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 3.0)
			_update_idle_animation()
			move_and_slide()
			
		State.STAGGERED:
			# Reeling backward from parry
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.5)
			move_and_slide()

func _update_animation_by_velocity() -> void:
	if velocity.length() > 5.0:
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
		_update_idle_animation()

func _update_idle_animation() -> void:
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

func _start_telegraph() -> void:
	current_state = State.TELEGRAPH
	can_attack = false
	velocity = Vector2.ZERO
	windup_shake_timer = 0.0
	
	if player_target and is_instance_valid(player_target):
		attack_direction = global_position.direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	_update_idle_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Windup Anticipation:
	# 1. Menacing glowing red tint
	# 2. Slight pull-back / squash in anticipation of the lunge
	var pull_back = -attack_direction * 4.0
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color(2.4, 0.35, 0.35), 0.45)
	attack_tween.tween_property(animation, "scale", Vector2(1.18, 0.82), 0.45)
	attack_tween.tween_property(animation, "position", pull_back, 0.45)
	
	# After 0.45s telegraph, release the strike lunge!
	attack_tween.chain().tween_callback(_start_lunge)

func _start_lunge() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	
	current_state = State.LUNGE
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Strike Flash:
	# Stretch forward in attack direction and flash bright white impact
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color(2.2, 2.2, 2.2), 0.08)
	attack_tween.tween_property(animation, "scale", Vector2(0.85, 1.25), 0.08)
	attack_tween.tween_property(animation, "position", attack_direction * 6.0, 0.08)
	
	# Execute hit at strike impact
	attack_tween.chain().tween_callback(_execute_strike_hit)
	
	# Finish lunge and transition to recovery
	attack_tween.chain().tween_interval(0.08)
	attack_tween.chain().tween_callback(_start_recovery)

func _execute_strike_hit() -> void:
	if is_dead or current_state != State.LUNGE:
		return
	
	if player_target and is_instance_valid(player_target):
		var dist = global_position.distance_to(player_target.global_position)
		const STRIKE_REACH: float = 38.0
		if dist <= STRIKE_REACH:
			if player_target.has_method("take_damage"):
				player_target.take_damage(attack_damage, self)

func _start_recovery() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	
	current_state = State.RECOVERY
	velocity = Vector2.ZERO
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Smoothly return to normal scale and color
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color.WHITE, 0.35)
	attack_tween.tween_property(animation, "scale", Vector2.ONE, 0.25)
	attack_tween.tween_property(animation, "position", Vector2.ZERO, 0.25)
	
	# Recovery window lasts 0.38s -> enter cooldown
	attack_tween.chain().tween_callback(func():
		if is_dead or current_state == State.STAGGERED:
			return
		current_state = State.COOLDOWN
		get_tree().create_timer(attack_cooldown).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				can_attack = true
				if current_state == State.COOLDOWN:
					current_state = State.CHASE
		)
	)

func stagger(duration: float = 1.2) -> void:
	if is_dead:
		return
	
	print("Skeleton was PARRIED and STAGGERED!")
	current_state = State.STAGGERED
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	
	# Knockback impulse away from player
	velocity = -attack_direction * 150.0
	
	# Stunned golden/lightning pulse
	animation.position = Vector2.ZERO
	animation.scale = Vector2(1.1, 0.9)
	animation.modulate = Color(2.4, 2.1, 0.3)
	
	attack_tween = create_tween()
	attack_tween.tween_property(animation, "modulate", Color(1.8, 1.5, 0.2), 0.3)
	attack_tween.tween_property(animation, "modulate", Color(2.5, 2.3, 0.5), 0.3)
	attack_tween.tween_property(animation, "modulate", Color(1.8, 1.5, 0.2), 0.3)
	attack_tween.tween_property(animation, "modulate", Color.WHITE, 0.3)
	attack_tween.tween_property(animation, "scale", Vector2.ONE, 0.2)
	
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.STAGGERED:
			animation.modulate = Color.WHITE
			animation.scale = Vector2.ONE
			current_state = State.COOLDOWN
			get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.CHASE
			)
	)

func _on_hit_area_area_entered(area: Area2D) -> void:
	if area.name == "attack_area_player" and not is_dead and not is_invulnerable:
		take_damage(damage_per_hit)

func take_damage(amount: int) -> void:
	if is_dead or is_invulnerable:
		return
	
	var final_damage = amount
	var is_critical = false
	
	# Counter-attack critical hit if enemy was staggered by a parry!
	if current_state == State.STAGGERED:
		final_damage = amount * 2
		is_critical = true
		print("CRITICAL COUNTER-ATTACK HIT! Dealt: ", final_damage)
	
	health = max(0, health - final_damage)
	print("Skeleton took damage! Current health: ", health)
	
	if health_bar:
		health_bar.set_health(health, max_health)
	
	if health <= 0:
		_die()
	else:
		if is_critical:
			_flash_critical()
		else:
			_flash_red()

func _flash_critical() -> void:
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.modulate = Color(3.0, 2.6, 0.8)
	damage_tween = create_tween()
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.3)
	damage_tween.tween_callback(func(): is_invulnerable = false)

func _flash_red() -> void:
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.modulate = Color(1.0, 0.25, 0.25)
	damage_tween = create_tween()
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.2)
	damage_tween.tween_callback(func(): is_invulnerable = false)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	enemy_died.emit(self)
	velocity = Vector2.ZERO
	hit_shape.set_deferred("disabled", true)
	ground_collision.set_deferred("disabled", true)
	if attack_shape:
		attack_shape.set_deferred("disabled", true)
	
	if damage_tween:
		damage_tween.kill()
	if attack_tween:
		attack_tween.kill()
	
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
