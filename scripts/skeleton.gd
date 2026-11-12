extends CharacterBody2D

signal enemy_died(enemy)

enum State {
	IDLE,
	CHASE,
	TELEGRAPH,
	STRIKE,
	RECOVERY,
	HITSTUN,
	STAGGERED,
	COOLDOWN
}

@onready var animation: AnimatedSprite2D = $animation
@onready var ground_collision: CollisionShape2D = $ground_collision
@onready var hit_area: Area2D = $hit_area
@onready var attack_area: Area2D = $attack_area_skelet
@onready var hit_shape: CollisionShape2D = $hit_area/hit_shape
@onready var attack_shape: CollisionShape2D = $attack_area_skelet/attack_shape
@onready var health_bar = $health_bar

const SPEED: float = 48.0
const STRIKE_NUDGE_SPEED: float = 38.0
var facing_direction: Vector2 = Vector2.DOWN
var attack_direction: Vector2 = Vector2.DOWN

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@export var max_health: int = 100
@export var damage_per_hit: int = 35
@export var attack_damage: int = 15
@export var attack_range: float = 28.0
@export var min_attack_cooldown: float = 1.1
@export var max_attack_cooldown: float = 1.6

var current_state: State = State.IDLE
var health: int = max_health
var player_target: Node2D = null

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var damage_tween: Tween = null
var attack_tween: Tween = null
var windup_shake_timer: float = 0.0

# Organic AI personality parameters
var flank_offset_angle: float = 0.0
var wander_seed: float = 0.0
var speed_variance: float = 1.0

func _ready() -> void:
	add_to_group("enemies")
	max_health = int(round(max_health * GameSettings.get_enemy_health_multiplier()))
	attack_damage = int(round(attack_damage * GameSettings.get_enemy_damage_multiplier()))
	health = max_health
	if health_bar:
		health_bar.set_health(health, max_health)
	
	# Assign unique approach characteristics so enemies don't mirror each other
	flank_offset_angle = randf_range(-0.55, 0.55)
	wander_seed = randf_range(0.0, 100.0)
	speed_variance = randf_range(0.92, 1.08)
	
	_find_player_target()

func _find_player_target() -> void:
	if player_target and is_instance_valid(player_target):
		if player_target.get("is_dead"):
			player_target = null
			current_state = State.IDLE
			velocity = Vector2.ZERO
		return
	
	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p) and not p.get("is_dead"):
		player_target = p

func _get_separation_vector() -> Vector2:
	var push = Vector2.ZERO
	# Mutual soft repulsion between enemies to prevent stacking
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == self or not is_instance_valid(e):
			continue
		var diff = global_position - e.global_position
		var d = diff.length()
		if d < 0.001:
			push += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		elif d < 26.0:
			push += (diff / d) * (1.0 - d / 26.0)
	
	# Gentle spacing from player when close to prevent gluing
	if player_target and is_instance_valid(player_target):
		var p_diff = global_position - player_target.global_position
		var p_dist = p_diff.length()
		if p_dist < 16.0:
			var p_dir = (p_diff / p_dist) if p_dist > 0.001 else Vector2.UP
			push += p_dir * (1.0 - p_dist / 16.0) * 0.8
			
	return push

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	_find_player_target()
	
	match current_state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.0)
			if player_target and is_instance_valid(player_target):
				if can_attack:
					current_state = State.CHASE
				else:
					facing_direction = global_position.direction_to(player_target.global_position)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.COOLDOWN:
			# During cooldown, maintain tactical spacing / circling rather than gluing
			if player_target and is_instance_valid(player_target):
				var to_player = global_position.direction_to(player_target.global_position)
				var dist = global_position.distance_to(player_target.global_position)
				facing_direction = to_player
				var sep = _get_separation_vector()
				if dist < 24.0:
					# Back off slightly
					velocity = (-to_player * 18.0 + sep * 20.0)
				else:
					# Gentle slow circle (flank offset determines clockwise vs counter-clockwise)
					var circle_sign = 1.0 if flank_offset_angle >= 0.0 else -1.0
					var circle_dir = to_player.rotated(PI * 0.45 * circle_sign)
					velocity = (circle_dir * 18.0 + sep * 18.0)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.CHASE:
			if player_target and is_instance_valid(player_target):
				var dist = global_position.distance_to(player_target.global_position)
				if dist <= attack_range and can_attack:
					_start_telegraph()
				else:
					wander_seed += delta * 2.2
					var sway = sin(wander_seed) * 0.18
					var to_player = global_position.direction_to(player_target.global_position)
					var approach_dir = to_player.rotated(flank_offset_angle + sway)
					var sep = _get_separation_vector()
					
					# Remove backward component of separation so trailing enemies flank rather than halt/reverse
					var forward_proj = sep.dot(approach_dir)
					if forward_proj < 0.0:
						var lateral = sep - approach_dir * forward_proj
						sep = lateral.normalized() * minf(sep.length(), 0.9)
					
					var move_dir = (approach_dir + sep * 0.95).normalized()
					velocity = move_dir * (SPEED * speed_variance)
					facing_direction = to_player
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
				current_state = State.IDLE
			_update_animation_by_velocity()
			move_and_slide()
			
		State.TELEGRAPH:
			# Completely stationary windup - commits to attack direction
			velocity = Vector2.ZERO
			windup_shake_timer += delta * 30.0
			animation.offset.x = sin(windup_shake_timer) * 1.2
			_update_idle_animation()
			move_and_slide()
			
		State.STRIKE:
			# Small forward step impact; velocity decays quickly
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.5)
			move_and_slide()
			
		State.RECOVERY:
			# Vulnerable pause after strike
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 3.0)
			_update_idle_animation()
			move_and_slide()
			
		State.HITSTUN:
			# Knockback decay from taking damage
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0)
			move_and_slide()
			
		State.STAGGERED:
			# Reeling backward from parry
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.5)
			move_and_slide()

func _update_animation_by_velocity() -> void:
	if velocity.length() > 6.0:
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
		# Lock strike direction once at the start of windup (no aimbot tracking)
		attack_direction = global_position.direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	_update_idle_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Windup Anticipation:
	# Subtle pull-back and reddish telegraph tint
	var pull_back = -attack_direction * 3.5
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color(2.2, 0.4, 0.4), 0.38)
	attack_tween.tween_property(animation, "scale", Vector2(1.15, 0.85), 0.38)
	attack_tween.tween_property(animation, "position", pull_back, 0.38)
	
	# Release strike after telegraph
	attack_tween.chain().tween_callback(_start_strike)

func _start_strike() -> void:
	if is_dead or current_state == State.STAGGERED or current_state == State.HITSTUN:
		return
	
	animation.offset = Vector2.ZERO
	current_state = State.STRIKE
	# Minor forward nudge over 0.08s (never a full-screen homing rush)
	velocity = attack_direction * STRIKE_NUDGE_SPEED
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Strike Flash:
	# Crisp forward punch and bright white impact
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color(2.0, 2.0, 2.0), 0.08)
	attack_tween.tween_property(animation, "scale", Vector2(0.9, 1.2), 0.08)
	attack_tween.tween_property(animation, "position", attack_direction * 5.0, 0.08)
	
	# Execute damage at apex of strike
	attack_tween.chain().tween_callback(_execute_strike_hit)
	
	# Finish strike and enter recovery pause
	attack_tween.chain().tween_interval(0.06)
	attack_tween.chain().tween_callback(_start_recovery)

func _execute_strike_hit() -> void:
	if is_dead or current_state != State.STRIKE:
		return
	
	if player_target and is_instance_valid(player_target):
		var dist = global_position.distance_to(player_target.global_position)
		const STRIKE_REACH: float = 32.0
		# Reach and angle check (allows dodging / stepping back)
		if dist <= STRIKE_REACH:
			var to_player = global_position.direction_to(player_target.global_position)
			if attack_direction.dot(to_player) > 0.3:
				if player_target.has_method("take_damage"):
					player_target.take_damage(attack_damage, self)

func _start_recovery() -> void:
	if is_dead or current_state == State.STAGGERED or current_state == State.HITSTUN:
		return
	
	current_state = State.RECOVERY
	velocity = Vector2.ZERO
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Smoothly return to normal scale and color
	attack_tween.set_parallel(true)
	attack_tween.tween_property(animation, "modulate", Color.WHITE, 0.22)
	attack_tween.tween_property(animation, "scale", Vector2.ONE, 0.22)
	attack_tween.tween_property(animation, "position", Vector2.ZERO, 0.22)
	
	# Recovery pause -> enter cooldown
	attack_tween.chain().tween_callback(func():
		if is_dead or current_state == State.STAGGERED or current_state == State.HITSTUN:
			return
		current_state = State.COOLDOWN
		var cd = randf_range(min_attack_cooldown, max_attack_cooldown)
		get_tree().create_timer(cd).timeout.connect(func():
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
	velocity = -attack_direction * 140.0
	
	# Stunned golden pulse
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
		var kb_dir = (global_position - area.global_position).normalized()
		if kb_dir == Vector2.ZERO:
			kb_dir = -facing_direction
		
		# Factor in player's active and permanent damage boosts if applicable
		var effective_damage = damage_per_hit
		if player_target and is_instance_valid(player_target):
			if player_target.has_method("get_total_damage_multiplier"):
				effective_damage = int(damage_per_hit * player_target.get_total_damage_multiplier())
			elif "damage_multiplier" in player_target:
				effective_damage = int(damage_per_hit * player_target.damage_multiplier)
			if player_target.has_method("on_successful_sword_hit"):
				player_target.on_successful_sword_hit()
			
		take_damage(effective_damage, kb_dir)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
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
	
	# Spawn floating combat damage number
	if FLOATING_TEXT_SCENE:
		var ft = FLOATING_TEXT_SCENE.instantiate()
		ft.global_position = global_position + Vector2(randf_range(-6, 6), -14)
		get_parent().add_child(ft)
		if is_critical:
			ft.spawn("%d CRIT!" % final_damage, Color(1.0, 0.88, 0.25), 11, 22.0, 0.6)
		else:
			ft.spawn("%d" % final_damage, Color.WHITE, 10, 16.0, 0.5)
	
	if health <= 0:
		_die()
		return
	
	# Apply hit-stun and knockback so player is rewarded for landing hits
	_apply_hitstun(knockback_dir, is_critical)

func _apply_hitstun(knockback_dir: Vector2, is_critical: bool) -> void:
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	
	current_state = State.HITSTUN
	can_attack = false
	
	# Knockback impulse
	velocity = knockback_dir * 110.0
	
	# Hit flinch visual
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.position = Vector2.ZERO
	animation.scale = Vector2(0.88, 1.15)
	animation.modulate = Color(3.0, 2.6, 0.8) if is_critical else Color(2.2, 0.3, 0.3)
	
	damage_tween = create_tween()
	damage_tween.set_parallel(true)
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.22)
	damage_tween.tween_property(animation, "scale", Vector2.ONE, 0.22)
	
	# Hit-stun duration (0.22s) -> transition to brief cooldown
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.HITSTUN:
			is_invulnerable = false
			current_state = State.COOLDOWN
			get_tree().create_timer(0.55).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.CHASE
			)
	)

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
	
	_try_spawn_drop()
	
	animation.modulate = Color(1.0, 0.25, 0.25)
	var death_tween = create_tween()
	death_tween.tween_property(animation, "modulate:a", 0.0, 0.25)
	death_tween.tween_callback(queue_free)

func _try_spawn_drop() -> void:
	if not PICKUP_SCENE:
		return
	# 70% chance of dropping a boost or potion
	if randf() > 0.70:
		return
	
	var pickup = PICKUP_SCENE.instantiate()
	pickup.global_position = global_position
	
	var roll = randf()
	if player_target and is_instance_valid(player_target) and "health" in player_target and "max_health" in player_target and player_target.health <= player_target.max_health * 0.5:
		# Increase health drop probability if player is injured
		if roll < 0.60:
			pickup.pickup_type = 0 # Type.HEALTH
		elif roll < 0.80:
			pickup.pickup_type = 1 # Type.SPEED
		else:
			pickup.pickup_type = 2 # Type.POWER
	else:
		if roll < 0.45:
			pickup.pickup_type = 0 # Type.HEALTH
		elif roll < 0.72:
			pickup.pickup_type = 1 # Type.SPEED
		else:
			pickup.pickup_type = 2 # Type.POWER
	
	get_parent().call_deferred("add_child", pickup)

func _on_see_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_target = body

func _on_see_area_body_exited(_body: Node2D) -> void:
	# Retain active engagement in arena combat
	pass

func _on_see_area_area_entered(area: Area2D) -> void:
	if area.owner and area.owner.is_in_group("player"):
		player_target = area.owner
	elif area.get_parent() and area.get_parent().is_in_group("player"):
		player_target = area.get_parent()

func _on_see_area_area_exited(_area: Area2D) -> void:
	pass
