extends CharacterBody2D

signal enemy_died(enemy)
signal health_changed(current_health: int, max_health: int)

enum State {
	SITTING,
	STANDING_UP,
	IDLE,
	CHASE,
	# Move 1: Slash Combo (2-hit standard, 3-hit in Phase 2)
	SLASH_TELEGRAPH,
	SLASH_HIT_1,
	SLASH_RECOVER_1,
	SLASH_HIT_2,
	SLASH_RECOVER_2,
	SLASH_HIT_3,
	# Move 2: Straight-Line Piercing Thrust
	THRUST_TELEGRAPH,
	THRUST_LUNGE,
	THRUST_RECOVERY,
	# Move 3: Abyssal Earthshaker (Circular AoE)
	SLAM_TELEGRAPH,
	SLAM_IMPACT,
	SLAM_RECOVERY,
	# Move 4: Tactical Backstep
	BACKSTEP,
	# Phase 2 Roar Transition
	PHASE_TRANSITION,
	# Hit reactions & recovery
	RECOVERY,
	HITSTUN,
	STAGGERED,
	COOLDOWN
}

@onready var see_area_knight: Area2D = $see_area_knight
@onready var see_shape_knight: CollisionShape2D = $see_area_knight/see_shape_knight
@onready var ground_collisison_knight: CollisionShape2D = $ground_collisison_knight
@onready var hit_area_knight: Area2D = $hit_area_knight
@onready var hit_shape_knight: CollisionShape2D = $hit_area_knight/hit_shape_knight
@onready var attack_area_knight: Area2D = $attack_area_knight
@onready var attack_shape_knight: CollisionShape2D = $attack_area_knight/attack_shape_knight
@onready var animation: AnimatedSprite2D = $animation
@onready var health_bar = get_node_or_null("health_bar")
@onready var boss_hud_container: Control = get_node_or_null("boss_hud/top_center_container")
@onready var boss_name_label: Label = get_node_or_null("boss_hud/top_center_container/boss_name_label")
@onready var boss_health_bar = get_node_or_null("boss_hud/top_center_container/boss_health_bar")

const BASE_SPEED: float = 48.0
const PHASE2_SPEED: float = 62.0
const BODY_CENTER_OFFSET: Vector2 = Vector2(0.0, 28.0)

# Exact walkable boundaries of the Boss Room floor
const ARENA_X_MIN: float = 252.0
const ARENA_X_MAX: float = 532.0
const ARENA_Y_MIN: float = -246.0
const ARENA_Y_MAX: float = -34.0

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@export var start_sitting: bool = true
@export var wake_up_distance: float = 120.0
@export var boss_title: String = "FALLEN KNIGHT"
@export var show_boss_health_bar: bool = true
@export var max_health: int = 1000
@export var damage_per_hit: int = 35
@export var attack_damage: int = 20

var facing_direction: Vector2 = Vector2.DOWN
var attack_direction: Vector2 = Vector2.DOWN

var current_state: State = State.SITTING
var health: int = max_health
var player_target: Node2D = null

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var has_dealt_strike_damage: bool = false
var has_stood_up: bool = false
var is_boss_bar_visible: bool = false

# Phase 2 Enrage
var is_phase_2: bool = false
var has_transitioned_phase_2: bool = false

# Combat AI tracking
var flank_offset_angle: float = 0.0
var wander_seed: float = 0.0
var speed_variance: float = 1.0
var consecutive_hits_taken: int = 0
var last_attack_type: String = ""

# Move 2: Straight-Line Thrust variables
var thrust_direction: Vector2 = Vector2.DOWN
var thrust_locked: bool = false
var thrust_telegraph_timer: float = 0.0
const THRUST_DISTANCE: float = 135.0
const THRUST_WIDTH: float = 26.0

# Move 3: Circular AoE Earthshaker variables
var slam_radius: float = 85.0
var slam_progress: float = 0.0
var is_shockwave_active: bool = false
var shockwave_radius: float = 0.0
var shockwave_alpha: float = 0.0

# Dedicated telegraph visual overlay
var telegraph_canvas: Node2D = null

var damage_tween: Tween = null
var attack_tween: Tween = null
var boss_bar_tween: Tween = null
var base_anim_scale: Vector2 = Vector2(3.0, 3.0)

# Inner class for rendering ARPG danger zones and shockwaves
class BossTelegraphDrawer extends Node2D:
	var boss: CharacterBody2D = null
	
	func _draw() -> void:
		if not boss or not is_instance_valid(boss):
			return
		boss._draw_telegraph_visuals(self)

func _ready() -> void:
	add_to_group("enemies")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if collision_layer == 1:
		collision_layer = 4096
		collision_mask = 2242
	if hit_area_knight and hit_area_knight.collision_layer == 1:
		hit_area_knight.collision_layer = 256
		hit_area_knight.collision_mask = 4
	if see_area_knight:
		see_area_knight.collision_layer = 256
		see_area_knight.collision_mask = 3
		if not see_area_knight.body_entered.is_connected(_on_see_area_knight_body_entered):
			see_area_knight.body_entered.connect(_on_see_area_knight_body_entered)
		if not see_area_knight.body_exited.is_connected(_on_see_area_knight_body_exited):
			see_area_knight.body_exited.connect(_on_see_area_knight_body_exited)
	if attack_area_knight:
		attack_area_knight.collision_layer = 256
		attack_area_knight.collision_mask = 3
		if not attack_area_knight.body_entered.is_connected(_on_attack_area_knight_body_entered):
			attack_area_knight.body_entered.connect(_on_attack_area_knight_body_entered)
	
	# Instantiate ground telegraph canvas beneath characters
	telegraph_canvas = BossTelegraphDrawer.new()
	telegraph_canvas.name = "telegraph_canvas"
	telegraph_canvas.z_index = -1
	telegraph_canvas.boss = self
	add_child(telegraph_canvas)
	
	if animation:
		base_anim_scale = animation.scale
	if attack_shape_knight:
		attack_shape_knight.disabled = true
	
	max_health = int(round(max_health * GameSettings.get_enemy_health_multiplier()))
	attack_damage = int(round(attack_damage * GameSettings.get_enemy_damage_multiplier()))
	health = max_health
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(health, max_health)
	if boss_name_label:
		boss_name_label.text = boss_title
	if boss_health_bar and boss_health_bar.has_method("set_health"):
		boss_health_bar.set_health(health, max_health)
	if boss_hud_container:
		boss_hud_container.visible = false
		boss_hud_container.modulate.a = 0.0
	health_changed.emit(health, max_health)
	
	flank_offset_angle = randf_range(-0.55, 0.55)
	wander_seed = randf_range(0.0, 100.0)
	speed_variance = randf_range(0.95, 1.05)
	
	if start_sitting:
		current_state = State.SITTING
		has_stood_up = false
		if animation:
			animation.flip_h = false
			animation.play("sit")
	else:
		current_state = State.IDLE
		has_stood_up = true
		_update_idle_animation()

func _get_body_center() -> Vector2:
	return global_position + BODY_CENTER_OFFSET

func _find_player_node() -> Node2D:
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		var players = get_tree().root.find_children("player", "CharacterBody2D", true, false)
		if players.size() > 0:
			p = players[0]
	return p

func is_player_in_boss_arena(p: Node2D) -> bool:
	if not p or not is_instance_valid(p) or p.get("is_dead"):
		return false
	var pos = p.global_position
	return pos.x >= ARENA_X_MIN and pos.x <= ARENA_X_MAX and pos.y >= ARENA_Y_MIN and pos.y <= ARENA_Y_MAX

func has_line_of_sight(target: Node2D) -> bool:
	if not target or not is_instance_valid(target) or not is_inside_tree():
		return false
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return false
	# Raycast from front of boss base to target position against walls and doors (mask 2241)
	var from_pos = global_position + Vector2(0.0, 45.0)
	var to_pos = target.global_position
	var query = PhysicsRayQueryParameters2D.create(from_pos, to_pos, 2241)
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	return res.is_empty()

func _set_boss_bar_visible(show_bar: bool) -> void:
	if not show_boss_health_bar or not boss_hud_container:
		return
	if is_boss_bar_visible == show_bar:
		return
	is_boss_bar_visible = show_bar
	if boss_bar_tween and boss_bar_tween.is_running():
		boss_bar_tween.kill()
	boss_bar_tween = create_tween()
	if show_bar:
		boss_hud_container.visible = true
		boss_bar_tween.tween_property(boss_hud_container, "modulate:a", 1.0, 0.35)
	else:
		boss_bar_tween.tween_property(boss_hud_container, "modulate:a", 0.0, 0.25)
		boss_bar_tween.tween_callback(func():
			if boss_hud_container and not is_boss_bar_visible:
				boss_hud_container.visible = false
		)

func _check_room_and_proximity() -> void:
	var p = _find_player_node()
	if not p or not is_instance_valid(p):
		if is_boss_bar_visible:
			_set_boss_bar_visible(false)
		return
	
	var in_arena = is_player_in_boss_arena(p)
	
	# Strict health bar & aggro scoping: only active when player is actually inside boss room
	if not in_arena:
		if is_boss_bar_visible:
			_set_boss_bar_visible(false)
		if player_target:
			player_target = null
			if current_state != State.SITTING and current_state != State.STANDING_UP and not is_dead:
				current_state = State.IDLE
		return
	
	# Player is inside boss arena
	if current_state == State.SITTING:
		var dist = _get_body_center().distance_to(p.global_position)
		if dist <= wake_up_distance and has_line_of_sight(p):
			_start_stand_up(p)
	elif has_stood_up:
		if not player_target and has_line_of_sight(p):
			player_target = p
		if player_target:
			_set_boss_bar_visible(true)

func _start_stand_up(target: Node2D = null) -> void:
	if current_state != State.SITTING or is_dead:
		return
	
	# Strict verification: do NOT wake up if target is outside arena or blocked by wall
	if target and (not is_player_in_boss_arena(target) or not has_line_of_sight(target)):
		return
	
	current_state = State.STANDING_UP
	has_stood_up = true
	player_target = target if target else _find_player_node()
	
	_set_boss_bar_visible(true)
	
	if animation:
		animation.flip_h = false
		animation.play("sit_up")
		animation.animation_finished.connect(_on_stand_up_finished, CONNECT_ONE_SHOT)

func _on_stand_up_finished() -> void:
	if is_dead:
		return
	current_state = State.IDLE
	_update_idle_animation()
	get_tree().create_timer(0.4).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.IDLE:
			can_attack = true
			current_state = State.CHASE
	)

func _get_separation_vector() -> Vector2:
	var push = Vector2.ZERO
	var my_center = _get_body_center()
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == self or not is_instance_valid(e):
			continue
		var diff = my_center - e.global_position
		var d = diff.length()
		if d < 0.001:
			push += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		elif d < 36.0:
			push += (diff / d) * (1.0 - d / 36.0)
	
	if player_target and is_instance_valid(player_target):
		var p_diff = my_center - player_target.global_position
		var p_dist = p_diff.length()
		if p_dist < 26.0:
			var p_dir = (p_diff / p_dist) if p_dist > 0.001 else Vector2.UP
			push += p_dir * (1.0 - p_dist / 26.0) * 0.9
			
	return push

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	if player_target and is_instance_valid(player_target) and player_target.get("is_dead"):
		player_target = null
		current_state = State.IDLE
		velocity = Vector2.ZERO
	
	_check_room_and_proximity()
	var my_center = _get_body_center()
	var move_speed = PHASE2_SPEED if is_phase_2 else BASE_SPEED
	
	if telegraph_canvas:
		telegraph_canvas.queue_redraw()
	
	match current_state:
		State.SITTING:
			velocity = Vector2.ZERO
			if animation and animation.animation != &"sit":
				animation.flip_h = false
				animation.play("sit")
			
		State.STANDING_UP, State.PHASE_TRANSITION:
			velocity = Vector2.ZERO
			
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.0)
			if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
				if can_attack:
					current_state = State.CHASE
				else:
					facing_direction = my_center.direction_to(player_target.global_position)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.COOLDOWN:
			if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
				var to_player = my_center.direction_to(player_target.global_position)
				var dist = my_center.distance_to(player_target.global_position)
				facing_direction = to_player
				var sep = _get_separation_vector()
				if dist < 38.0:
					velocity = (-to_player * 24.0 + sep * 20.0)
				else:
					var circle_sign = 1.0 if flank_offset_angle >= 0.0 else -1.0
					var circle_dir = to_player.rotated(PI * 0.45 * circle_sign)
					velocity = (circle_dir * 22.0 + sep * 18.0)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, move_speed)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.CHASE:
			if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
				var dist = my_center.distance_to(player_target.global_position)
				var has_los = has_line_of_sight(player_target)
				
				# Never attack without clean line-of-sight
				if can_attack and has_los:
					_decide_next_move(dist)
				else:
					wander_seed += delta * 2.4
					var sway = sin(wander_seed) * 0.18
					var to_player = my_center.direction_to(player_target.global_position)
					var approach_dir = to_player.rotated(flank_offset_angle + sway)
					var sep = _get_separation_vector()
					
					var forward_proj = sep.dot(approach_dir)
					if forward_proj < 0.0:
						var lateral = sep - approach_dir * forward_proj
						sep = lateral.normalized() * minf(sep.length(), 0.9)
					
					var move_dir = (approach_dir + sep * 0.95).normalized()
					velocity = move_dir * (move_speed * speed_variance)
					facing_direction = to_player
					_update_animation_by_velocity()
			else:
				velocity = velocity.move_toward(Vector2.ZERO, move_speed)
				current_state = State.IDLE
				_update_animation_by_velocity()
			move_and_slide()
			
		State.SLASH_TELEGRAPH, State.SLAM_TELEGRAPH:
			velocity = Vector2.ZERO
			move_and_slide()
			
		State.THRUST_TELEGRAPH:
			velocity = Vector2.ZERO
			if not thrust_locked and player_target and is_instance_valid(player_target):
				thrust_direction = my_center.direction_to(player_target.global_position)
				facing_direction = thrust_direction
			move_and_slide()
			
		State.THRUST_LUNGE:
			# Surge forward at high speed along locked thrust path
			velocity = thrust_direction * (370.0 if not is_phase_2 else 430.0)
			move_and_slide()
			
		State.BACKSTEP:
			velocity = velocity.move_toward(Vector2.ZERO, 380.0 * delta)
			move_and_slide()
			
		State.SLASH_HIT_1, State.SLASH_HIT_2, State.SLASH_HIT_3, State.SLAM_IMPACT:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.5)
			move_and_slide()
			
		State.SLASH_RECOVER_1, State.SLASH_RECOVER_2, State.SLAM_RECOVERY, State.THRUST_RECOVERY, State.RECOVERY:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 3.0)
			_update_idle_animation()
			move_and_slide()
			
		State.HITSTUN:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 4.0)
			move_and_slide()
			
		State.STAGGERED:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.5)
			move_and_slide()

func _update_animation_by_velocity() -> void:
	if velocity.length() > 6.0:
		if abs(facing_direction.x) > abs(facing_direction.y):
			animation.flip_h = facing_direction.x < 0
			animation.play("walk_side")
		else:
			animation.flip_h = false
			if facing_direction.y > 0:
				animation.play("walk_down")
			else:
				animation.play("walk_up")
	else:
		_update_idle_animation()

func _update_idle_animation() -> void:
	if abs(facing_direction.x) > abs(facing_direction.y):
		animation.flip_h = facing_direction.x < 0
		animation.play("idle_side")
	else:
		animation.flip_h = false
		if facing_direction.y > 0:
			animation.play("idle_down")
		else:
			animation.play("idle_up")

func _play_attack_animation() -> void:
	if abs(attack_direction.x) > abs(attack_direction.y):
		animation.flip_h = attack_direction.x < 0
		animation.play("attack_side")
		if attack_shape_knight:
			attack_shape_knight.position = Vector2(-44.0 if attack_direction.x < 0 else 44.0, 26.0)
			attack_shape_knight.rotation = 0.0
	else:
		animation.flip_h = false
		if attack_direction.y > 0:
			animation.play("attack_down")
			if attack_shape_knight:
				attack_shape_knight.position = Vector2(0.0, 58.0)
				attack_shape_knight.rotation = PI * 0.5
		else:
			animation.play("attack_up")
			if attack_shape_knight:
				attack_shape_knight.position = Vector2(0.0, -4.0)
				attack_shape_knight.rotation = PI * 0.5

func _play_death_animation() -> void:
	if abs(facing_direction.x) > abs(facing_direction.y):
		animation.flip_h = facing_direction.x < 0
		animation.play("die_side")
	else:
		animation.flip_h = false
		if facing_direction.y > 0:
			animation.play("die_down")
		else:
			animation.play("die_up")

# AI Dynamic Attack Decision Logic
func _decide_next_move(dist: float) -> void:
	if not can_attack or is_dead:
		return
	
	# Anti-cheese: if player is continuously attacking boss in melee range, chance to tactical backstep
	if consecutive_hits_taken >= 3 or (dist < 42.0 and randf() < 0.25):
		consecutive_hits_taken = 0
		_start_backstep()
		return
	
	# Close Range (dist <= 68px)
	if dist <= 68.0:
		var roll = randf()
		if roll < 0.50 and last_attack_type != "slash":
			_start_slash_combo()
		elif roll < 0.85 and last_attack_type != "slam":
			_start_ground_slam()
		else:
			_start_thrust_attack()
		return
	
	# Mid Range (68px < dist <= 170px)
	if dist <= 170.0:
		var roll = randf()
		if roll < 0.65 and last_attack_type != "thrust":
			_start_thrust_attack()
		elif roll < 0.85:
			_start_ground_slam()
		else:
			_start_slash_combo()
		return

# MOVE 1: Melee Slash Combo (2-Hit / 3-Hit)
func _start_slash_combo() -> void:
	last_attack_type = "slash"
	can_attack = false
	current_state = State.SLASH_TELEGRAPH
	velocity = Vector2.ZERO
	
	if player_target and is_instance_valid(player_target):
		attack_direction = _get_body_center().direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	# Subtle blade shine
	animation.modulate = Color(1.3, 1.3, 1.3)
	_play_attack_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.20)
	attack_tween.tween_callback(_execute_slash_1)

func _execute_slash_1() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_1
	has_dealt_strike_damage = false
	velocity = attack_direction * 42.0
	animation.modulate = Color.WHITE
	
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", false)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.05)
	attack_tween.tween_callback(func():
		_deal_area_strike_damage(20)
	)
	attack_tween.tween_interval(0.22)
	attack_tween.tween_callback(_check_slash_followup)

func _check_slash_followup() -> void:
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	if is_dead or current_state == State.STAGGERED:
		return
	
	# If player is still within reach, chain into Hit 2
	var in_range = false
	if player_target and is_instance_valid(player_target):
		in_range = _get_body_center().distance_to(player_target.global_position) <= 74.0
	
	if in_range:
		current_state = State.SLASH_RECOVER_1
		velocity = Vector2.ZERO
		if attack_tween and attack_tween.is_running():
			attack_tween.kill()
		attack_tween = create_tween()
		attack_tween.tween_interval(0.14)
		attack_tween.tween_callback(_execute_slash_2)
	else:
		_finish_attack_cycle(0.3)

func _execute_slash_2() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_2
	has_dealt_strike_damage = false
	
	if player_target and is_instance_valid(player_target):
		attack_direction = _get_body_center().direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	velocity = attack_direction * 48.0
	_play_attack_animation()
	
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", false)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.05)
	attack_tween.tween_callback(func():
		_deal_area_strike_damage(18)
	)
	attack_tween.tween_interval(0.24)
	attack_tween.tween_callback(func():
		if attack_shape_knight:
			attack_shape_knight.set_deferred("disabled", true)
		if is_phase_2:
			_check_slash_finisher()
		else:
			_finish_attack_cycle(0.32)
	)

func _check_slash_finisher() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	var in_range = false
	if player_target and is_instance_valid(player_target):
		in_range = _get_body_center().distance_to(player_target.global_position) <= 76.0
	
	if in_range:
		current_state = State.SLASH_RECOVER_2
		velocity = Vector2.ZERO
		if attack_tween and attack_tween.is_running():
			attack_tween.kill()
		attack_tween = create_tween()
		attack_tween.tween_interval(0.15)
		attack_tween.tween_callback(_execute_slash_3)
	else:
		_finish_attack_cycle(0.28)

func _execute_slash_3() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_3
	has_dealt_strike_damage = false
	velocity = attack_direction * 65.0
	animation.modulate = Color(2.2, 0.4, 0.4)
	_play_attack_animation()
	
	_trigger_screen_shake(3.2, 0.18)
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", false)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.05)
	attack_tween.tween_callback(func():
		_deal_area_strike_damage(26)
	)
	attack_tween.tween_interval(0.30)
	attack_tween.tween_callback(func():
		if attack_shape_knight:
			attack_shape_knight.set_deferred("disabled", true)
		animation.modulate = Color.WHITE
		_finish_attack_cycle(0.38)
	)

# MOVE 2: Straight-Line Piercing Thrust ("then a straight line attack")
func _start_thrust_attack() -> void:
	last_attack_type = "thrust"
	can_attack = false
	current_state = State.THRUST_TELEGRAPH
	thrust_locked = false
	velocity = Vector2.ZERO
	
	if player_target and is_instance_valid(player_target):
		thrust_direction = _get_body_center().direction_to(player_target.global_position)
		facing_direction = thrust_direction
	
	# Crouch into thrust telegraph stance
	_update_idle_animation()
	animation.modulate = Color(2.0, 0.45, 0.45)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# 0.32s dynamic tracking, then 0.16s lock angle so player can dodge sideways
	attack_tween.tween_interval(0.32)
	attack_tween.tween_callback(func():
		thrust_locked = true
	)
	attack_tween.tween_interval(0.16)
	attack_tween.tween_callback(_execute_thrust_lunge)

func _execute_thrust_lunge() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.THRUST_LUNGE
	has_dealt_strike_damage = false
	attack_direction = thrust_direction
	_play_attack_animation()
	
	_spawn_thrust_dust_particles()
	
	if attack_shape_knight:
		attack_shape_knight.position = thrust_direction * 36.0
		attack_shape_knight.set_deferred("disabled", false)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Rapid straight lunge duration
	var lunge_time = 0.22 if not is_phase_2 else 0.25
	attack_tween.tween_interval(0.04)
	attack_tween.tween_callback(func():
		_deal_area_strike_damage(28 if not is_phase_2 else 34, 110.0)
	)
	attack_tween.tween_interval(lunge_time - 0.04)
	attack_tween.tween_callback(_recover_thrust)

func _recover_thrust() -> void:
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.THRUST_RECOVERY
	velocity = Vector2.ZERO
	animation.modulate = Color.WHITE
	_finish_attack_cycle(0.42 if not is_phase_2 else 0.30)

# MOVE 3: Abyssal Earthshaker (Circular AoE Ground Slam)
func _start_ground_slam() -> void:
	last_attack_type = "slam"
	can_attack = false
	current_state = State.SLAM_TELEGRAPH
	velocity = Vector2.ZERO
	slam_progress = 0.0
	slam_radius = 85.0 if not is_phase_2 else 105.0
	
	if player_target and is_instance_valid(player_target):
		facing_direction = _get_body_center().direction_to(player_target.global_position)
	
	animation.play("idle_up")
	animation.modulate = Color(2.4, 0.4, 0.5)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	# Expand circular telegraph decal over 0.55s
	var telegraph_time = 0.58 if not is_phase_2 else 0.48
	attack_tween.tween_method(func(val: float):
		slam_progress = val
	, 0.1, 1.0, telegraph_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_callback(_execute_ground_slam)

func _execute_ground_slam() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLAM_IMPACT
	slam_progress = 0.0
	
	# Slam animation
	animation.play("attack_down")
	animation.modulate = Color(2.8, 1.8, 1.8)
	
	# Trigger camera shake and shockwave wave
	_trigger_screen_shake(5.0, 0.26)
	_spawn_slam_dust_particles()
	_trigger_shockwave_visuals(slam_radius)
	
	# Damage any player caught in the circular radius
	_deal_circular_aoe_damage(slam_radius, 26 if not is_phase_2 else 32)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.18)
	attack_tween.tween_callback(func():
		current_state = State.SLAM_RECOVERY
		animation.modulate = Color.WHITE
		_finish_attack_cycle(0.48 if not is_phase_2 else 0.32)
	)

# MOVE 4: Tactical Backstep (Mobility & Spacing)
func _start_backstep() -> void:
	current_state = State.BACKSTEP
	can_attack = false
	
	if player_target and is_instance_valid(player_target):
		facing_direction = _get_body_center().direction_to(player_target.global_position)
	
	# Swift hop backwards
	velocity = -facing_direction * 220.0
	_spawn_thrust_dust_particles()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(animation, "modulate:a", 0.65, 0.1)
	attack_tween.tween_property(animation, "modulate:a", 1.0, 0.12)
	attack_tween.tween_callback(func():
		velocity = Vector2.ZERO
		if is_dead or current_state == State.STAGGERED:
			return
		# Immediately counterattack out of backstep
		if randf() < 0.65:
			_start_thrust_attack()
		else:
			_start_ground_slam()
	)

# PHASE 2 TRANSITION: Enraged Blood/Ashen Knight at <= 50% HP
func _trigger_phase_2_transition() -> void:
	has_transitioned_phase_2 = true
	is_phase_2 = true
	current_state = State.PHASE_TRANSITION
	can_attack = false
	velocity = Vector2.ZERO
	is_invulnerable = true
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	
	animation.play("idle_up")
	animation.modulate = Color(3.0, 0.3, 0.3)
	
	# Update Boss HUD Title
	if boss_name_label:
		boss_name_label.text = "ENRAGED FALLEN KNIGHT"
		boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.32))
	
	_trigger_screen_shake(6.0, 0.4)
	_trigger_shockwave_visuals(90.0)
	
	# Repel player back
	if player_target and is_instance_valid(player_target):
		var p_center = _get_body_center()
		var p_dist = p_center.distance_to(player_target.global_position)
		if p_dist < 90.0 and player_target is CharacterBody2D:
			var push_dir = p_center.direction_to(player_target.global_position)
			player_target.velocity = push_dir * 240.0
	
	attack_tween = create_tween()
	attack_tween.tween_interval(0.75)
	attack_tween.tween_callback(func():
		is_invulnerable = false
		animation.modulate = Color.WHITE
		current_state = State.CHASE
		can_attack = true
		_start_ground_slam()
	)

func _finish_attack_cycle(recovery_delay: float) -> void:
	current_state = State.RECOVERY
	velocity = Vector2.ZERO
	_update_idle_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(recovery_delay)
	attack_tween.tween_callback(func():
		if is_dead or current_state == State.STAGGERED:
			return
		current_state = State.COOLDOWN
		var min_cd = 0.55 if is_phase_2 else 0.90
		var max_cd = 0.85 if is_phase_2 else 1.35
		var cd = randf_range(min_cd, max_cd)
		get_tree().create_timer(cd).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				can_attack = true
				if current_state == State.COOLDOWN:
					current_state = State.CHASE
		)
	)

# Damage Dealing Helpers
func _deal_area_strike_damage(dmg: int, max_reach: float = 96.0) -> void:
	if is_dead or has_dealt_strike_damage:
		return
	if player_target and is_instance_valid(player_target):
		var my_center = _get_body_center()
		var dist = my_center.distance_to(player_target.global_position)
		if dist <= max_reach:
			var to_player = my_center.direction_to(player_target.global_position)
			if attack_direction.dot(to_player) > 0.10:
				if player_target.has_method("take_damage"):
					has_dealt_strike_damage = true
					player_target.take_damage(dmg, self)

func _deal_circular_aoe_damage(radius: float, dmg: int) -> void:
	if is_dead:
		return
	if player_target and is_instance_valid(player_target):
		var my_center = _get_body_center()
		var dist = my_center.distance_to(player_target.global_position)
		if dist <= radius:
			if player_target.has_method("take_damage"):
				player_target.take_damage(dmg, self)

# Drawing ARPG Danger Zones and Ground FX
func _draw_telegraph_visuals(canvas: Node2D) -> void:
	var my_center = BODY_CENTER_OFFSET
	var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
	
	# 1. Straight-Line Thrust Danger Strip
	if current_state == State.THRUST_TELEGRAPH:
		var dir = thrust_direction.normalized()
		var norm = Vector2(-dir.y, dir.x)
		var half_w = THRUST_WIDTH * 0.5
		var len_p = THRUST_DISTANCE
		
		var p1 = my_center - norm * half_w
		var p2 = my_center + norm * half_w
		var p3 = my_center + norm * half_w + dir * len_p
		var p4 = my_center - norm * half_w + dir * len_p
		
		var fill_col = Color(0.85, 0.08, 0.12, 0.22 + 0.12 * pulse)
		var edge_col = Color(1.0, 0.25, 0.25, 0.85 if thrust_locked else 0.55)
		
		canvas.draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), fill_col)
		canvas.draw_polyline(PackedVector2Array([p1, p2, p3, p4, p1]), edge_col, 2.0)
		
		# Center guidance line with arrowhead
		var tip = my_center + dir * len_p
		canvas.draw_line(my_center, tip, Color(1.0, 0.8, 0.3, 0.75), 1.5)
		canvas.draw_circle(tip, 4.0, Color(1.0, 0.25, 0.25, 0.9))
	
	# 2. Circular Ground Slam AoE Indicator
	if current_state == State.SLAM_TELEGRAPH:
		var current_r = slam_radius * clampf(slam_progress, 0.15, 1.0)
		var fill_col = Color(0.78, 0.06, 0.10, 0.18 + 0.10 * pulse)
		var edge_col = Color(1.0, 0.22, 0.26, 0.90)
		
		canvas.draw_circle(my_center, current_r, fill_col)
		canvas.draw_arc(my_center, current_r, 0.0, TAU, 36, edge_col, 2.5)
		
		# Pulsing inner ring
		var inner_r = current_r * (0.3 + 0.4 * pulse)
		canvas.draw_arc(my_center, inner_r, 0.0, TAU, 24, Color(1.0, 0.7, 0.2, 0.45), 1.5)
	
	# 3. Expanding Shockwave Ring
	if is_shockwave_active and shockwave_alpha > 0.01:
		var wave_col = Color(1.0, 0.65, 0.25, shockwave_alpha)
		canvas.draw_arc(my_center, shockwave_radius, 0.0, TAU, 36, wave_col, 3.5)
		
		if is_phase_2:
			# Cardinal shockwave spikes
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
				var spike_end = my_center + d * (shockwave_radius * 1.15)
				canvas.draw_line(my_center, spike_end, wave_col, 2.0)

func _trigger_shockwave_visuals(target_radius: float) -> void:
	is_shockwave_active = true
	shockwave_radius = 12.0
	shockwave_alpha = 1.0
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "shockwave_radius", target_radius, 0.26)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "shockwave_alpha", 0.0, 0.26)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		is_shockwave_active = false
	)

func _trigger_screen_shake(intensity: float, duration: float) -> void:
	var p = _find_player_node()
	if p and p.has_method("shake_camera"):
		p.shake_camera(intensity, duration)

func _spawn_thrust_dust_particles() -> void:
	var p = CPUParticles2D.new()
	p.amount = 16
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 0.85
	p.z_index = -1
	p.position = BODY_CENTER_OFFSET
	p.direction = -thrust_direction
	p.spread = 45.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 85.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(0.65, 0.62, 0.58, 0.65)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.45).timeout.connect(p.queue_free)

func _spawn_slam_dust_particles() -> void:
	var p = CPUParticles2D.new()
	p.amount = 24
	p.lifetime = 0.40
	p.one_shot = true
	p.explosiveness = 0.95
	p.z_index = -1
	p.position = BODY_CENTER_OFFSET
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.2
	p.color = Color(0.72, 0.68, 0.62, 0.75) if not is_phase_2 else Color(0.85, 0.25, 0.28, 0.8)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.50).timeout.connect(p.queue_free)

func stagger(duration: float = 1.2) -> void:
	if is_dead:
		return
	
	print("Knight was PARRIED and STAGGERED!")
	has_stood_up = true
	current_state = State.STAGGERED
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	
	velocity = -attack_direction * 140.0
	
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale * Vector2(1.1, 0.9)
	animation.modulate = Color(2.4, 2.1, 0.3)
	
	attack_tween = create_tween()
	attack_tween.tween_property(animation, "modulate", Color(1.8, 1.5, 0.2), 0.3)
	attack_tween.tween_property(animation, "modulate", Color(2.5, 2.3, 0.5), 0.3)
	attack_tween.tween_property(animation, "modulate", Color(1.8, 1.5, 0.2), 0.3)
	attack_tween.tween_property(animation, "modulate", Color.WHITE, 0.3)
	attack_tween.tween_property(animation, "scale", base_anim_scale, 0.2)
	
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.STAGGERED:
			animation.modulate = Color.WHITE
			animation.scale = base_anim_scale
			current_state = State.COOLDOWN
			get_tree().create_timer(0.5).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.CHASE
			)
	)

func _on_see_area_knight_area_entered(area: Area2D) -> void:
	var p: Node2D = null
	if area.owner and area.owner.is_in_group("player"):
		p = area.owner
	elif area.get_parent() and area.get_parent().is_in_group("player"):
		p = area.get_parent()
	if p:
		if is_player_in_boss_arena(p) and has_line_of_sight(p):
			if current_state == State.SITTING:
				_start_stand_up(p)
			else:
				player_target = p
				_set_boss_bar_visible(true)

func _on_see_area_knight_area_exited(_area: Area2D) -> void:
	pass

func _on_see_area_knight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if is_player_in_boss_arena(body) and has_line_of_sight(body):
			if current_state == State.SITTING:
				_start_stand_up(body)
			else:
				player_target = body
				_set_boss_bar_visible(true)

func _on_see_area_knight_body_exited(_body: Node2D) -> void:
	pass

func _on_hit_area_knight_area_entered(area: Area2D) -> void:
	if area.name == "attack_area_player" and not is_dead and not is_invulnerable:
		if not player_target:
			player_target = _find_player_node()
		var kb_dir = (_get_body_center() - area.global_position).normalized()
		if kb_dir == Vector2.ZERO:
			kb_dir = -facing_direction
		
		var effective_damage = damage_per_hit
		if player_target and is_instance_valid(player_target):
			if player_target.has_method("get_total_damage_multiplier"):
				effective_damage = int(damage_per_hit * player_target.get_total_damage_multiplier())
			elif "damage_multiplier" in player_target:
				effective_damage = int(damage_per_hit * player_target.damage_multiplier)
			if player_target.has_method("on_successful_sword_hit"):
				player_target.on_successful_sword_hit()
			
		take_damage(effective_damage, kb_dir)

func _on_attack_area_knight_area_entered(area: Area2D) -> void:
	if is_dead or has_dealt_strike_damage:
		return
	var target: Node = null
	if area.owner and area.owner.is_in_group("player"):
		target = area.owner
	elif area.get_parent() and area.get_parent().is_in_group("player"):
		target = area.get_parent()
	if target and target.has_method("take_damage"):
		has_dealt_strike_damage = true
		target.take_damage(attack_damage, self)

func _on_attack_area_knight_body_entered(body: Node2D) -> void:
	if is_dead or has_dealt_strike_damage:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		has_dealt_strike_damage = true
		body.take_damage(attack_damage, self)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_invulnerable:
		return
	
	_set_boss_bar_visible(true)
	consecutive_hits_taken += 1
	
	var final_damage = amount
	var is_critical = false
	
	if current_state == State.STAGGERED:
		final_damage = amount * 2
		is_critical = true
	
	health = max(0, health - final_damage)
	
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(health, max_health)
	if boss_health_bar and boss_health_bar.has_method("set_health"):
		boss_health_bar.set_health(health, max_health)
	health_changed.emit(health, max_health)
	
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
	
	# Phase 2 Trigger at <= 50% HP
	if health <= int(max_health * 0.50) and not has_transitioned_phase_2:
		_trigger_phase_2_transition()
		return
	
	if current_state == State.SITTING:
		_start_stand_up()
		return
	if current_state == State.STANDING_UP or current_state == State.PHASE_TRANSITION:
		return
	
	# Super armor / poise during heavy attack telegraphs and execution
	var is_heavy_move = (
		current_state == State.THRUST_TELEGRAPH or 
		current_state == State.THRUST_LUNGE or 
		current_state == State.SLAM_TELEGRAPH or 
		current_state == State.SLAM_IMPACT
	)
	
	if not is_heavy_move and current_state != State.STAGGERED:
		_apply_hitstun(knockback_dir, is_critical)

func _apply_hitstun(knockback_dir: Vector2, is_critical: bool) -> void:
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	
	has_stood_up = true
	current_state = State.HITSTUN
	can_attack = false
	velocity = knockback_dir * 95.0
	
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale * Vector2(0.92, 1.10)
	animation.modulate = Color(3.0, 2.6, 0.8) if is_critical else Color(2.2, 0.3, 0.3)
	
	damage_tween = create_tween()
	damage_tween.set_parallel(true)
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.20)
	damage_tween.tween_property(animation, "scale", base_anim_scale, 0.20)
	
	get_tree().create_timer(0.20).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.HITSTUN:
			is_invulnerable = false
			current_state = State.COOLDOWN
			get_tree().create_timer(0.40 if is_phase_2 else 0.65).timeout.connect(func():
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
	hit_shape_knight.set_deferred("disabled", true)
	ground_collisison_knight.set_deferred("disabled", true)
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	
	if damage_tween:
		damage_tween.kill()
	if attack_tween:
		attack_tween.kill()
	
	if health_bar:
		var ht = create_tween()
		ht.tween_property(health_bar, "modulate:a", 0.0, 0.25)
	_set_boss_bar_visible(false)
	
	_try_spawn_drop()
	
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale
	animation.modulate = Color.WHITE
	_play_death_animation()
	
	var death_tween = create_tween()
	death_tween.tween_interval(0.9)
	death_tween.tween_property(animation, "modulate:a", 0.0, 0.3)
	death_tween.tween_callback(queue_free)

func _try_spawn_drop() -> void:
	if not PICKUP_SCENE:
		return
	if randf() > 0.70:
		return
	
	var pickup = PICKUP_SCENE.instantiate()
	pickup.global_position = _get_body_center()
	
	var roll = randf()
	if player_target and is_instance_valid(player_target) and "health" in player_target and "max_health" in player_target and player_target.health <= player_target.max_health * 0.5:
		if roll < 0.60:
			pickup.pickup_type = 0
		elif roll < 0.80:
			pickup.pickup_type = 1
		else:
			pickup.pickup_type = 2
	else:
		if roll < 0.45:
			pickup.pickup_type = 0
		elif roll < 0.72:
			pickup.pickup_type = 1
		else:
			pickup.pickup_type = 2
	
	get_parent().call_deferred("add_child", pickup)
