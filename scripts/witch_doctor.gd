extends CharacterBody2D

signal enemy_died(enemy)

enum State {
	IDLE,
	REPOSITION,
	CAST_WINDUP,
	CAST_RELEASE,
	HITSTUN,
	STAGGERED,
	COOLDOWN
}

@onready var animation: AnimatedSprite2D = $animation
@onready var ground_collision: CollisionShape2D = $ground_collision
@onready var hit_area: Area2D = $hit_area
@onready var hit_shape: CollisionShape2D = $hit_area/hit_shape
@onready var health_bar = $health_bar

const SPEED: float = 42.0
const PREFERRED_MIN_DIST: float = 58.0
const PREFERRED_MAX_DIST: float = 128.0

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const PROJECTILE_SCENE = preload("res://scenes/enemy_projectile.tscn")

@export var max_health: int = 80
@export var damage_per_hit: int = 35
@export var projectile_damage: int = 14
@export var projectile_speed: float = 110.0
@export var min_cast_cooldown: float = 1.6
@export var max_cast_cooldown: float = 2.3

var current_state: State = State.IDLE
var health: int = max_health
var player_target: Node2D = null
var facing_direction: Vector2 = Vector2.DOWN
var cast_direction: Vector2 = Vector2.DOWN

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var damage_tween: Tween = null
var cast_tween: Tween = null
var strafe_sign: float = 1.0
var wander_seed: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	max_health = int(round(max_health * GameSettings.get_enemy_health_multiplier()))
	projectile_damage = int(round(projectile_damage * GameSettings.get_enemy_damage_multiplier()))
	health = max_health
	if health_bar:
		health_bar.set_health(health, max_health)
	strafe_sign = -1.0 if randf() < 0.5 else 1.0
	wander_seed = randf_range(0.0, 100.0)
	_find_player_target()

func _find_player_target() -> void:
	if not player_target or not is_instance_valid(player_target):
		var p = get_tree().get_first_node_in_group("player")
		if p:
			player_target = p

func _get_separation_vector() -> Vector2:
	var push = Vector2.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		var diff = global_position - e.global_position
		var d = diff.length()
		if d < 0.001:
			push += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		elif d < 26.0:
			push += (diff / d) * (1.0 - d / 26.0)
	return push

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	_find_player_target()
	
	match current_state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.0)
			if player_target and is_instance_valid(player_target):
				current_state = State.REPOSITION
			_update_movement_animation()
			move_and_slide()
			
		State.REPOSITION, State.COOLDOWN:
			if player_target and is_instance_valid(player_target):
				var to_player = global_position.direction_to(player_target.global_position)
				var dist = global_position.distance_to(player_target.global_position)
				facing_direction = to_player
				
				if current_state == State.REPOSITION and can_attack and dist <= PREFERRED_MAX_DIST + 20.0 and dist >= 36.0:
					_start_cast()
					return
				
				wander_seed += delta * 2.0
				var sep = _get_separation_vector()
				var move_vec = Vector2.ZERO
				
				if dist < PREFERRED_MIN_DIST:
					# Kite away from player while weaving slightly
					var away = -to_player.rotated(sin(wander_seed) * 0.35)
					move_vec = (away + sep * 0.9).normalized() * SPEED
				elif dist > PREFERRED_MAX_DIST:
					# Approach into casting range, projecting sep to lateral if it opposes
					var forward_proj = sep.dot(to_player)
					if forward_proj < 0.0:
						var lateral = sep - to_player * forward_proj
						sep = lateral.normalized() * minf(sep.length(), 0.9)
					move_vec = (to_player + sep * 0.9).normalized() * SPEED
				else:
					# Strafe around player at range
					var tangent = to_player.rotated(PI * 0.5 * strafe_sign)
					move_vec = (tangent * 0.85 + sep * 0.9).normalized() * (SPEED * 0.72)
				
				velocity = move_vec
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
			_update_movement_animation()
			move_and_slide()
			
		State.CAST_WINDUP, State.CAST_RELEASE:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 3.0)
			move_and_slide()
			
		State.HITSTUN, State.STAGGERED:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0)
			move_and_slide()

func _get_dir_suffix(dir: Vector2) -> String:
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"

func _update_movement_animation() -> void:
	var suffix = _get_dir_suffix(facing_direction)
	if velocity.length() > 6.0:
		animation.play("walk_" + suffix)
	else:
		animation.play("idle_" + suffix)

func _start_cast() -> void:
	current_state = State.CAST_WINDUP
	can_attack = false
	velocity = Vector2.ZERO
	
	if player_target and is_instance_valid(player_target):
		cast_direction = global_position.direction_to(player_target.global_position)
		facing_direction = cast_direction
	
	var suffix = _get_dir_suffix(cast_direction)
	animation.play("cast_" + suffix)
	
	if cast_tween and cast_tween.is_running():
		cast_tween.kill()
	cast_tween = create_tween()
	
	# Necrotic emerald-violet spell charge glow
	cast_tween.tween_property(animation, "modulate", Color(1.5, 2.3, 1.6), 0.36)
	cast_tween.tween_callback(_release_spell)

func _release_spell() -> void:
	if is_dead or current_state != State.CAST_WINDUP:
		return
	current_state = State.CAST_RELEASE
	
	if player_target and is_instance_valid(player_target):
		cast_direction = global_position.direction_to(player_target.global_position)
		facing_direction = cast_direction
	
	_spawn_necro_bolt(cast_direction)
	
	if cast_tween and cast_tween.is_running():
		cast_tween.kill()
	cast_tween = create_tween()
	cast_tween.tween_property(animation, "modulate", Color.WHITE, 0.25)
	cast_tween.tween_callback(func():
		if is_dead or current_state == State.HITSTUN or current_state == State.STAGGERED:
			return
		current_state = State.COOLDOWN
		if randf() < 0.4:
			strafe_sign = -strafe_sign
		var cd = randf_range(min_cast_cooldown, max_cast_cooldown)
		get_tree().create_timer(cd).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				can_attack = true
				if current_state == State.COOLDOWN:
					current_state = State.REPOSITION
		)
	)

func _spawn_necro_bolt(dir: Vector2) -> void:
	if not PROJECTILE_SCENE or not get_parent():
		return
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + Vector2(0, 6) + dir * 10.0
	get_parent().add_child(proj)
	proj.setup(dir, 0, projectile_speed, projectile_damage, 0.75, self)

func stagger(duration: float = 1.2) -> void:
	if is_dead:
		return
	current_state = State.STAGGERED
	if cast_tween and cast_tween.is_running():
		cast_tween.kill()
	velocity = -facing_direction * 120.0
	animation.modulate = Color(2.4, 2.1, 0.3)
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.STAGGERED:
			animation.modulate = Color.WHITE
			current_state = State.COOLDOWN
			can_attack = true
	)

func _on_hit_area_area_entered(area: Area2D) -> void:
	if area.name == "attack_area_player" and not is_dead and not is_invulnerable:
		var kb_dir = (global_position - area.global_position).normalized()
		if kb_dir == Vector2.ZERO:
			kb_dir = -facing_direction
		var effective_damage = damage_per_hit
		if player_target and is_instance_valid(player_target) and "damage_multiplier" in player_target:
			effective_damage = int(damage_per_hit * player_target.get_total_damage_multiplier()) if player_target.has_method("get_total_damage_multiplier") else int(damage_per_hit * player_target.damage_multiplier)
		if player_target and is_instance_valid(player_target) and player_target.has_method("on_successful_sword_hit"):
			player_target.on_successful_sword_hit()
		take_damage(effective_damage, kb_dir)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_invulnerable:
		return
	var final_damage = amount * 2 if current_state == State.STAGGERED else amount
	var is_critical = (current_state == State.STAGGERED)
	
	health = max(0, health - final_damage)
	if health_bar:
		health_bar.set_health(health, max_health)
	
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
	
	if cast_tween and cast_tween.is_running():
		cast_tween.kill()
	current_state = State.HITSTUN
	can_attack = false
	velocity = knockback_dir * 115.0
	is_invulnerable = true
	
	if damage_tween:
		damage_tween.kill()
	animation.scale = Vector2(0.88, 1.15)
	animation.modulate = Color(2.2, 0.3, 0.3)
	damage_tween = create_tween()
	damage_tween.set_parallel(true)
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.22)
	damage_tween.tween_property(animation, "scale", Vector2.ONE, 0.22)
	
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.HITSTUN:
			is_invulnerable = false
			current_state = State.COOLDOWN
			get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.REPOSITION
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
	if damage_tween:
		damage_tween.kill()
	if cast_tween:
		cast_tween.kill()
	if health_bar:
		var ht = create_tween()
		ht.tween_property(health_bar, "modulate:a", 0.0, 0.25)
	_try_spawn_drop()
	animation.modulate = Color(0.5, 1.8, 0.7)
	var death_tween = create_tween()
	death_tween.tween_property(animation, "modulate:a", 0.0, 0.28)
	death_tween.tween_callback(queue_free)

func _try_spawn_drop() -> void:
	if not PICKUP_SCENE or randf() > 0.75:
		return
	var pickup = PICKUP_SCENE.instantiate()
	pickup.global_position = global_position
	var roll = randf()
	if roll < 0.45:
		pickup.pickup_type = 0
	elif roll < 0.72:
		pickup.pickup_type = 1
	else:
		pickup.pickup_type = 2
	get_parent().call_deferred("add_child", pickup)
