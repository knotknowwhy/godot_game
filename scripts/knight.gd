extends CharacterBody2D

signal enemy_died(enemy)
signal health_changed(current_health: int, max_health: int)

enum State {
	SITTING,
	STANDING_UP,
	IDLE,
	CHASE,
	# Move 1: Cleaving Greatsword Combo (2-hit in Phase 1, + 360 Whirlwind Cleave in Phase 2)
	SLASH_TELEGRAPH,
	SLASH_HIT_1,
	SLASH_RECOVER_1,
	SLASH_HIT_2,
	SLASH_SPIN_TELEGRAPH,
	SLASH_HIT_3,
	# Move 2: Impaling Line Lunge (+ Delayed Afterburn Fissure in Phase 2)
	THRUST_TELEGRAPH,
	THRUST_LUNGE,
	THRUST_RECOVERY,
	# Move 3: Abyssal Earthshaker (Inner Slam + Expanding Jump-Rope Shockwave Ring)
	SLAM_TELEGRAPH,
	SLAM_IMPACT,
	SLAM_RECOVERY,
	# Move 4: Sundering Ground Waves (1 Linear Wave in Phase 1, 3-Way Fan in Phase 2)
	WAVE_TELEGRAPH,
	WAVE_FIRE,
	WAVE_RECOVERY,
	# Move 5: Tactical Riposte Backstep
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

const BASE_SPEED: float = 52.0
const PHASE2_SPEED: float = 68.0
const BODY_CENTER_OFFSET: Vector2 = Vector2(0.0, 28.0)

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@export var start_sitting: bool = true
@export var wake_up_distance: float = 135.0
@export var boss_title: String = "FALLEN KNIGHT"
@export var show_boss_health_bar: bool = true
@export var use_boss_room_rect: bool = true
@export var boss_room_rect: Rect2 = Rect2(254.0, -246.0, 276.0, 208.0)
@export var boss_room_trigger: NodePath

@export var max_health: int = 750
@export var damage_per_hit: int = 35
@export var attack_damage: int = 18
@export var attack_range: float = 74.0
@export var strike_reach: float = 86.0
@export var min_attack_cooldown: float = 0.85
@export var max_attack_cooldown: float = 1.25
@export var post_hit_cooldown: float = 0.55

var facing_direction: Vector2 = Vector2.DOWN
var attack_direction: Vector2 = Vector2.DOWN

var current_state: State = State.SITTING
var health: int = max_health
var player_target: Node2D = null
var spawn_origin: Vector2 = Vector2.ZERO

var is_dead: bool = false
var is_invulnerable: bool = false
var is_exposed: bool = false
var can_attack: bool = true
var has_dealt_strike_damage: bool = false
var has_stood_up: bool = false
var is_boss_bar_visible: bool = false
var arena_doors_locked: bool = false

# Phase 2 Enrage
var is_phase_2: bool = false
var has_transitioned_phase_2: bool = false
var ember_accum: float = 0.0

# Combat AI tracking
var flank_offset_angle: float = 0.0
var wander_seed: float = 0.0
var speed_variance: float = 1.0
var consecutive_hits_taken: int = 0
var last_attack_type: String = ""
var damage_scale: float = 1.0

# Move 1: Slash Arc & Spin Visuals
var slash_arc_progress: float = 0.0
var slash_arc_alpha: float = 0.0
var slash_arc_dir: Vector2 = Vector2.DOWN
var slash_arc_radius: float = 64.0
var slash_arc_span: float = PI * 0.78
var spin_telegraph_progress: float = 0.0

# Move 2: Straight-Line Lunge & Delayed Fissure
var thrust_direction: Vector2 = Vector2.DOWN
var thrust_locked: bool = false
var thrust_origin_world: Vector2 = Vector2.ZERO
var thrust_length: float = 135.0
var thrust_progress: float = 0.0
var ghost_spawn_timer: float = 0.0
const THRUST_WIDTH: float = 26.0
var active_fissures: Array[Dictionary] = []

# Move 3: Circular AoE Earthshaker + Expanding Shockwave Ring
var slam_center_world: Vector2 = Vector2.ZERO
var slam_inner_radius: float = 70.0
var slam_progress: float = 0.0
var active_shockwave_rings: Array[Dictionary] = []

# Move 4: Sundering Ground Waves
var wave_aim_dirs: Array[Vector2] = []
var wave_telegraph_progress: float = 0.0
var active_ground_waves: Array[Dictionary] = []

# Dedicated telegraph & FX renderer positioned right above floor tiles (z=2, child 0)
var telegraph_canvas: Node2D = null

var damage_tween: Tween = null
var attack_tween: Tween = null
var boss_bar_tween: Tween = null
var base_anim_scale: Vector2 = Vector2(3.0, 3.0)

class BossTelegraphDrawer extends Node2D:
	var boss: CharacterBody2D = null
	
	func _draw() -> void:
		if not boss or not is_instance_valid(boss):
			return
		boss._draw_telegraph_visuals(self)

func _ready() -> void:
	add_to_group("enemies")
	spawn_origin = global_position
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
	
	if not boss_room_trigger.is_empty():
		var trigger_node = get_node_or_null(boss_room_trigger)
		if trigger_node and trigger_node is Area2D:
			trigger_node.body_entered.connect(_on_boss_room_trigger_body_entered)
			trigger_node.body_exited.connect(_on_boss_room_trigger_body_exited)
	
	# Place telegraph_canvas at child index 0 with z_index = 0 (effective z=2, above floor z=1, behind boss sprite)
	telegraph_canvas = BossTelegraphDrawer.new()
	telegraph_canvas.name = "telegraph_canvas"
	telegraph_canvas.z_index = 0
	telegraph_canvas.boss = self
	add_child(telegraph_canvas)
	move_child(telegraph_canvas, 0)
	
	if animation:
		base_anim_scale = animation.scale
	if attack_shape_knight:
		attack_shape_knight.disabled = true
	
	damage_scale = GameSettings.get_enemy_damage_multiplier()
	max_health = int(round(max_health * GameSettings.get_enemy_health_multiplier()))
	attack_damage = int(round(attack_damage * damage_scale))
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
	
	flank_offset_angle = randf_range(-0.45, 0.45)
	wander_seed = randf_range(0.0, 100.0)
	speed_variance = randf_range(0.96, 1.04)
	
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

func _scaled_dmg(base_val: int) -> int:
	return maxi(1, int(round(base_val * damage_scale)))

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
	if not use_boss_room_rect:
		return true
	return boss_room_rect.has_point(p.global_position)

func has_line_of_sight(target: Node2D) -> bool:
	if not target or not is_instance_valid(target) or not is_inside_tree():
		return false
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return false
	# While sitting on the throne at (393, -261), start ray just south of throne collider (y=-222);
	# once standing, raycast from actual body center against layer 1 (room_boundaries & doors).
	var from_pos = (global_position + Vector2(0.0, 45.0)) if (current_state == State.SITTING or current_state == State.STANDING_UP) else _get_body_center()
	var to_pos = target.global_position
	var query = PhysicsRayQueryParameters2D.create(from_pos, to_pos, 1)
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	return res.is_empty()

func _clamp_distance_to_walls(from_pos: Vector2, dir: Vector2, max_dist: float, margin: float = 16.0) -> float:
	if not is_inside_tree():
		return max_dist
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return max_dist
	var norm_dir = dir.normalized()
	var query = PhysicsRayQueryParameters2D.create(from_pos, from_pos + norm_dir * max_dist, 1)
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	var dist = max_dist
	if not res.is_empty():
		dist = maxf(18.0, from_pos.distance_to(res.position) - margin)
	# Also clamp to boss_room_rect interior so boss never lunges into doorways
	if use_boss_room_rect:
		var end_pt = from_pos + norm_dir * dist
		var safe_rect = boss_room_rect.grow(-14.0)
		if not safe_rect.has_point(end_pt):
			var clamped_pt = end_pt.clamp(safe_rect.position, safe_rect.end)
			dist = minf(dist, from_pos.distance_to(clamped_pt))
	return maxf(16.0, dist)

func _lock_arena_doors(lock: bool) -> void:
	if arena_doors_locked == lock or not is_inside_tree():
		return
	arena_doors_locked = lock
	var scene_root = get_tree().current_scene
	if not scene_root:
		scene_root = get_parent().get_parent() if get_parent() else null
	if not scene_root:
		return
	for door_name in ["room4_south_door", "hallway1_east_door"]:
		var d = scene_root.get_node_or_null(door_name)
		if d and is_instance_valid(d):
			if lock:
				if d.has_method("lock_and_close"):
					d.lock_and_close()
			else:
				if d.has_method("unlock_door"):
					d.unlock_door()
				if d.has_method("open_door"):
					d.open_door()

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
	
	# Strict zone isolation: never wake up, show bar, or target player outside the boss room
	if not in_arena:
		if is_boss_bar_visible:
			_set_boss_bar_visible(false)
		if player_target:
			player_target = null
			if current_state != State.SITTING and current_state != State.STANDING_UP and not is_dead:
				_cancel_active_attack()
				current_state = State.IDLE
		return
	
	var dist = _get_body_center().distance_to(p.global_position)
	if current_state == State.SITTING:
		if dist <= wake_up_distance and has_line_of_sight(p):
			_start_stand_up(p)
	elif has_stood_up:
		if not player_target and has_line_of_sight(p):
			player_target = p
		if player_target:
			_set_boss_bar_visible(true)

func _cancel_active_attack() -> void:
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	is_exposed = false
	slam_progress = 0.0
	thrust_progress = 0.0
	spin_telegraph_progress = 0.0
	wave_telegraph_progress = 0.0
	slash_arc_alpha = 0.0
	if animation:
		animation.speed_scale = 1.0
		animation.modulate = Color.WHITE
		animation.scale = base_anim_scale

func _start_stand_up(target: Node2D = null) -> void:
	if current_state != State.SITTING or is_dead:
		return
	
	var check_target = target if target else _find_player_node()
	if check_target and (not is_player_in_boss_arena(check_target) or not has_line_of_sight(check_target)):
		return
	
	current_state = State.STANDING_UP
	has_stood_up = true
	player_target = check_target
	
	_set_boss_bar_visible(true)
	# Seal boss room entrances once the player steps past the threshold
	if check_target and boss_room_rect.grow(-10.0).has_point(check_target.global_position):
		_lock_arena_doors(true)
	
	if animation:
		animation.flip_h = false
		animation.play("sit_up")
		if not animation.animation_finished.is_connected(_on_stand_up_finished):
			animation.animation_finished.connect(_on_stand_up_finished, CONNECT_ONE_SHOT)

func _on_stand_up_finished() -> void:
	if is_dead:
		return
	current_state = State.IDLE
	_update_idle_animation()
	get_tree().create_timer(0.35).timeout.connect(func():
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
		if p_dist < 24.0:
			var p_dir = (p_diff / p_dist) if p_dist > 0.001 else Vector2.UP
			push += p_dir * (1.0 - p_dist / 24.0) * 0.85
			
	return push

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	if player_target and is_instance_valid(player_target) and player_target.get("is_dead"):
		player_target = null
		_cancel_active_attack()
		current_state = State.IDLE
		velocity = Vector2.ZERO
	
	_check_room_and_proximity()
	if has_stood_up and not arena_doors_locked and player_target and is_instance_valid(player_target):
		if boss_room_rect.grow(-12.0).has_point(player_target.global_position):
			_lock_arena_doors(true)
	
	_update_active_hazards(delta)
	
	if is_phase_2:
		ember_accum += delta
		if ember_accum >= 0.14:
			ember_accum = 0.0
			_spawn_phase2_ambient_ember()
	
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
				if dist < 44.0:
					velocity = (-to_player * 28.0 + sep * 20.0)
				else:
					var circle_sign = 1.0 if flank_offset_angle >= 0.0 else -1.0
					var circle_dir = to_player.rotated(PI * 0.45 * circle_sign)
					velocity = (circle_dir * 26.0 + sep * 18.0)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, move_speed)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.CHASE:
			if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
				var dist = my_center.distance_to(player_target.global_position)
				var has_los = has_line_of_sight(player_target)
				
				if can_attack and has_los:
					if _try_decide_move(dist):
						return
				
				wander_seed += delta * 2.5
				var sway = sin(wander_seed) * 0.16
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
			
		State.SLASH_TELEGRAPH, State.SLAM_TELEGRAPH, State.SLASH_SPIN_TELEGRAPH, State.WAVE_TELEGRAPH:
			velocity = Vector2.ZERO
			move_and_slide()
			
		State.THRUST_TELEGRAPH:
			velocity = Vector2.ZERO
			if not thrust_locked and player_target and is_instance_valid(player_target):
				thrust_direction = my_center.direction_to(player_target.global_position)
				facing_direction = thrust_direction
				thrust_origin_world = my_center
				thrust_length = _clamp_distance_to_walls(my_center, thrust_direction, 145.0 if not is_phase_2 else 165.0)
			move_and_slide()
			
		State.THRUST_LUNGE:
			ghost_spawn_timer += delta
			if ghost_spawn_timer >= 0.045:
				ghost_spawn_timer = 0.0
				_spawn_afterimage_ghost(Color(1.0, 0.35, 0.35, 0.55) if is_phase_2 else Color(0.75, 0.85, 1.0, 0.5))
			move_and_slide()
			
		State.BACKSTEP:
			ghost_spawn_timer += delta
			if ghost_spawn_timer >= 0.05:
				ghost_spawn_timer = 0.0
				_spawn_afterimage_ghost(Color(0.8, 0.9, 1.0, 0.45))
			velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
			move_and_slide()
			
		State.SLASH_HIT_1, State.SLASH_HIT_2, State.SLASH_HIT_3, State.SLAM_IMPACT, State.WAVE_FIRE:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.5)
			move_and_slide()
			
		State.SLASH_RECOVER_1, State.SLAM_RECOVERY, State.THRUST_RECOVERY, State.WAVE_RECOVERY, State.RECOVERY:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 3.0)
			move_and_slide()
			
		State.HITSTUN:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 4.0)
			move_and_slide()
			
		State.STAGGERED:
			velocity = velocity.move_toward(Vector2.ZERO, move_speed * 2.5)
			move_and_slide()

# Process independent world-anchored ground hazards (expanding shockwave rings, traveling crescent waves, delayed fissures)
func _update_active_hazards(delta: float) -> void:
	# 1. Expanding Jump-Rope Shockwave Rings
	for i in range(active_shockwave_rings.size() - 1, -1, -1):
		var ring = active_shockwave_rings[i]
		ring["elapsed"] += delta
		var t = clampf(ring["elapsed"] / ring["duration"], 0.0, 1.0)
		ring["current_r"] = lerpf(ring["start_r"], ring["end_r"], t)
		ring["alpha"] = 1.0 - pow(t, 1.8)
		
		# Check if player is intersecting the expanding ring band
		if not ring["has_hit"] and player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
			var p_dist = ring["center"].distance_to(player_target.global_position)
			var half_band = ring["thickness"] * 0.55
			if absf(p_dist - ring["current_r"]) <= half_band:
				if not player_target.get("is_invulnerable") and not player_target.get("isDodging"):
					ring["has_hit"] = true
					if player_target.has_method("take_damage"):
						# Pass null attacker so ground shockwave must be dodged/spaced, not trivially shield-turtled
						player_target.take_damage(_scaled_dmg(16), null)
		
		if t >= 1.0:
			active_shockwave_rings.remove_at(i)
	
	# 2. Traveling Crescent Ground Waves
	for i in range(active_ground_waves.size() - 1, -1, -1):
		var w = active_ground_waves[i]
		var step = w["dir"] * w["speed"] * delta
		var next_pos = w["pos"] + step
		w["traveled"] += step.length()
		
		# Stop wave if it hits a wall or leaves the boss arena
		if use_boss_room_rect and not boss_room_rect.grow(-8.0).has_point(next_pos):
			active_ground_waves.remove_at(i)
			continue
		
		w["pos"] = next_pos
		if not w["has_hit"] and player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
			if w["pos"].distance_to(player_target.global_position) <= w["radius"]:
				w["has_hit"] = true
				if player_target.has_method("take_damage"):
					player_target.take_damage(_scaled_dmg(18), self)
				active_ground_waves.remove_at(i)
				continue
		
		if w["traveled"] >= w["max_dist"]:
			active_ground_waves.remove_at(i)
	
	# 3. Phase 2 Delayed Line Fissures (erupt in boss's lunge wake)
	for i in range(active_fissures.size() - 1, -1, -1):
		var f = active_fissures[i]
		f["timer"] -= delta
		if not f["erupted"] and f["timer"] <= 0.0:
			f["erupted"] = true
			f["erupt_elapsed"] = 0.0
			_trigger_screen_shake(3.0, 0.16)
			_spawn_fissure_eruption_particles(f["start"], f["end"])
			# Check line segment distance to player
			if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
				var closest = Geometry2D.get_closest_point_to_segment(player_target.global_position, f["start"], f["end"])
				if closest.distance_to(player_target.global_position) <= f["width"] * 0.65:
					if player_target.has_method("take_damage"):
						player_target.take_damage(_scaled_dmg(20), null)
		elif f["erupted"]:
			f["erupt_elapsed"] += delta
			if f["erupt_elapsed"] >= 0.30:
				active_fissures.remove_at(i)

func _update_animation_by_velocity() -> void:
	animation.speed_scale = 1.0
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
	animation.speed_scale = 1.0
	if abs(facing_direction.x) > abs(facing_direction.y):
		animation.flip_h = facing_direction.x < 0
		animation.play("idle_side")
	else:
		animation.flip_h = false
		if facing_direction.y > 0:
			animation.play("idle_down")
		else:
			animation.play("idle_up")

func _get_attack_anim_name(dir: Vector2) -> StringName:
	if abs(dir.x) > abs(dir.y):
		animation.flip_h = dir.x < 0
		if attack_shape_knight:
			attack_shape_knight.position = Vector2(-44.0 if dir.x < 0 else 44.0, 26.0)
			attack_shape_knight.rotation = 0.0
		return &"attack_side"
	else:
		animation.flip_h = false
		if dir.y > 0:
			if attack_shape_knight:
				attack_shape_knight.position = Vector2(0.0, 58.0)
				attack_shape_knight.rotation = PI * 0.5
			return &"attack_down"
		else:
			if attack_shape_knight:
				attack_shape_knight.position = Vector2(0.0, -4.0)
				attack_shape_knight.rotation = PI * 0.5
			return &"attack_up"

func _pose_attack_windup(dir: Vector2, windup_frame: int = 1) -> void:
	var anim_name = _get_attack_anim_name(dir)
	animation.play(anim_name)
	animation.pause()
	animation.frame = windup_frame

func _play_attack_release(dir: Vector2, start_frame: int = 2, playback_speed: float = 1.55) -> void:
	var anim_name = _get_attack_anim_name(dir)
	animation.play(anim_name)
	animation.frame = start_frame
	animation.speed_scale = playback_speed

func _play_death_animation() -> void:
	animation.speed_scale = 1.0
	if abs(facing_direction.x) > abs(facing_direction.y):
		animation.flip_h = facing_direction.x < 0
		animation.play("die_side")
	else:
		animation.flip_h = false
		if facing_direction.y > 0:
			animation.play("die_down")
		else:
			animation.play("die_up")

# Dynamic Boss Move Selection
func _try_decide_move(dist: float) -> bool:
	if not can_attack or is_dead:
		return false
	
	# 1. Tactical Riposte Backstep when player spams 3+ melee hits on the boss
	if consecutive_hits_taken >= 3:
		consecutive_hits_taken = 0
		_start_backstep()
		return true
	
	# 2. Close Range (dist <= 68px): Slash Combo, Earthshaker AoE, or Tactical Backstep
	if dist <= 68.0:
		var roll = randf()
		if dist < 44.0 and roll < 0.38 and last_attack_type != "slam":
			_start_ground_slam()
			return true
		elif roll < 0.72 and last_attack_type != "slash":
			_start_slash_combo()
			return true
		elif roll < 0.88 and last_attack_type != "slam":
			_start_ground_slam()
			return true
		else:
			_start_backstep()
			return true
	
	# 3. Mid to Long Range (68px < dist <= 185px): Impaling Line Lunge or Sundering Ground Waves
	if dist <= 185.0:
		var roll = randf()
		if roll < 0.52 and last_attack_type != "thrust":
			_start_thrust_attack()
			return true
		elif roll < 0.86 and last_attack_type != "wave":
			_start_wave_attack()
			return true
		elif dist <= 92.0 and last_attack_type != "slam":
			_start_ground_slam()
			return true
	
	return false

# ==============================================================================
# MOVE 1: Cleaving Greatsword Combo (Parryable 2-Hit + Phase 2 360 Whirlwind)
# ==============================================================================
func _start_slash_combo() -> void:
	last_attack_type = "slash"
	can_attack = false
	is_exposed = false
	current_state = State.SLASH_TELEGRAPH
	velocity = Vector2.ZERO
	
	if player_target and is_instance_valid(player_target):
		attack_direction = _get_body_center().direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	# Hold on windup frame 1 with steel-gold parryable glint and floor arc preview
	_pose_attack_windup(attack_direction, 1)
	animation.modulate = Color(1.35, 1.32, 1.15)
	animation.scale = base_anim_scale * Vector2(1.06, 0.94)
	slash_arc_dir = attack_direction
	slash_arc_radius = 68.0
	slash_arc_span = PI * 0.78
	slash_arc_progress = 0.0
	slash_arc_alpha = 0.0
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	var windup_time = 0.30 if not is_phase_2 else 0.24
	attack_tween.tween_method(func(val: float):
		slash_arc_progress = val
	, 0.0, 1.0, windup_time)
	attack_tween.tween_callback(_execute_slash_1)

func _execute_slash_1() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_1
	has_dealt_strike_damage = false
	slash_arc_progress = 0.0
	slash_arc_alpha = 0.95
	velocity = attack_direction * 90.0
	animation.modulate = Color.WHITE
	animation.scale = base_anim_scale * Vector2(1.10, 0.92)
	_play_attack_release(attack_direction, 2, 1.65)
	
	_deal_cone_slash_damage(_scaled_dmg(18), 74.0, 0.25)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.set_parallel(true)
	attack_tween.tween_property(self, "slash_arc_alpha", 0.0, 0.20)
	attack_tween.tween_property(animation, "scale", base_anim_scale, 0.20)
	attack_tween.chain().tween_callback(_check_slash_followup)

func _check_slash_followup() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	
	var in_range = false
	if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
		in_range = _get_body_center().distance_to(player_target.global_position) <= 84.0
	
	if in_range:
		current_state = State.SLASH_RECOVER_1
		velocity = Vector2.ZERO
		if player_target and is_instance_valid(player_target):
			attack_direction = _get_body_center().direction_to(player_target.global_position)
			facing_direction = attack_direction
		_pose_attack_windup(attack_direction, 0)
		slash_arc_dir = attack_direction
		
		if attack_tween and attack_tween.is_running():
			attack_tween.kill()
		attack_tween = create_tween()
		var p_time = 0.22 if not is_phase_2 else 0.17
		attack_tween.tween_method(func(val: float):
			slash_arc_progress = val
		, 0.0, 1.0, p_time)
		attack_tween.tween_callback(_execute_slash_2)
	else:
		_finish_attack_cycle(0.32, false)

func _execute_slash_2() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_2
	has_dealt_strike_damage = false
	slash_arc_progress = 0.0
	slash_arc_alpha = 0.95
	velocity = attack_direction * 105.0
	_play_attack_release(attack_direction, 2, 1.75)
	
	_deal_cone_slash_damage(_scaled_dmg(16), 76.0, 0.20)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(self, "slash_arc_alpha", 0.0, 0.20)
	attack_tween.tween_callback(func():
		if is_phase_2 and player_target and is_instance_valid(player_target) and _get_body_center().distance_to(player_target.global_position) <= 88.0:
			_start_whirlwind_finisher()
		else:
			_finish_attack_cycle(0.35, false)
	)

func _start_whirlwind_finisher() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_SPIN_TELEGRAPH
	velocity = Vector2.ZERO
	spin_telegraph_progress = 0.0
	_pose_attack_windup(facing_direction, 1)
	animation.modulate = Color(2.2, 0.55, 0.35)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_method(func(val: float):
		spin_telegraph_progress = val
	, 0.0, 1.0, 0.28)
	attack_tween.tween_callback(_execute_whirlwind_finisher)

func _execute_whirlwind_finisher() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLASH_HIT_3
	spin_telegraph_progress = 0.0
	slash_arc_radius = 68.0
	slash_arc_span = TAU
	slash_arc_alpha = 1.0
	_play_attack_release(facing_direction, 2, 2.0)
	_trigger_screen_shake(3.4, 0.18)
	
	# 360 cleave around boss
	if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
		if _get_body_center().distance_to(player_target.global_position) <= 68.0:
			if player_target.has_method("take_damage"):
				player_target.take_damage(_scaled_dmg(22), self)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(self, "slash_arc_alpha", 0.0, 0.24)
	attack_tween.tween_callback(func():
		animation.modulate = Color.WHITE
		_finish_attack_cycle(0.45, true)
	)

# ==============================================================================
# MOVE 2: Impaling Line Lunge + Phase 2 Delayed Fissure
# ==============================================================================
func _start_thrust_attack() -> void:
	last_attack_type = "thrust"
	can_attack = false
	is_exposed = false
	current_state = State.THRUST_TELEGRAPH
	thrust_locked = false
	thrust_progress = 0.0
	velocity = Vector2.ZERO
	
	var my_center = _get_body_center()
	if player_target and is_instance_valid(player_target):
		thrust_direction = my_center.direction_to(player_target.global_position)
		facing_direction = thrust_direction
	thrust_origin_world = my_center
	thrust_length = _clamp_distance_to_walls(my_center, thrust_direction, 145.0 if not is_phase_2 else 165.0)
	
	_pose_attack_windup(thrust_direction, 1)
	animation.modulate = Color(1.9, 0.48, 0.42)
	animation.scale = base_anim_scale * Vector2(0.92, 1.08)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	var track_time = 0.32 if not is_phase_2 else 0.26
	var lock_time = 0.17
	attack_tween.tween_method(func(val: float):
		thrust_progress = val * 0.72
	, 0.0, 1.0, track_time)
	attack_tween.tween_callback(func():
		thrust_locked = true
		thrust_origin_world = _get_body_center()
		thrust_length = _clamp_distance_to_walls(thrust_origin_world, thrust_direction, 145.0 if not is_phase_2 else 165.0)
		animation.modulate = Color(2.6, 2.2, 0.9)
	)
	attack_tween.tween_method(func(val: float):
		thrust_progress = 0.72 + val * 0.28
	, 0.0, 1.0, lock_time)
	attack_tween.tween_callback(_execute_thrust_lunge)

func _execute_thrust_lunge() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.THRUST_LUNGE
	has_dealt_strike_damage = false
	thrust_progress = 0.0
	ghost_spawn_timer = 0.0
	attack_direction = thrust_direction
	facing_direction = thrust_direction
	
	animation.modulate = Color.WHITE
	animation.scale = base_anim_scale * Vector2(1.16, 0.88)
	_play_attack_release(thrust_direction, 2, 1.8)
	_spawn_thrust_dust_particles()
	
	var start_center = _get_body_center()
	var safe_dist = _clamp_distance_to_walls(start_center, thrust_direction, thrust_length)
	var lunge_duration = 0.20 if not is_phase_2 else 0.18
	velocity = thrust_direction * (safe_dist / lunge_duration)
	
	# Phase 2 leaves a delayed searing fissure along the lunge path
	if is_phase_2:
		active_fissures.append({
			"start": start_center,
			"end": start_center + thrust_direction * safe_dist,
			"width": THRUST_WIDTH,
			"timer": 0.45,
			"erupted": false,
			"erupt_elapsed": 0.0
		})
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_method(func(_t: float):
		if not has_dealt_strike_damage and player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
			var seg_pt = Geometry2D.get_closest_point_to_segment(player_target.global_position, start_center, _get_body_center() + thrust_direction * 18.0)
			if seg_pt.distance_to(player_target.global_position) <= THRUST_WIDTH * 0.72:
				if player_target.has_method("take_damage"):
					has_dealt_strike_damage = true
					player_target.take_damage(_scaled_dmg(22), self)
	, 0.0, 1.0, lunge_duration)
	attack_tween.tween_callback(_recover_thrust)

func _recover_thrust() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.THRUST_RECOVERY
	velocity = Vector2.ZERO
	animation.scale = base_anim_scale
	animation.modulate = Color.WHITE
	# Missing the lunge leaves the boss Exposed (+25% damage taken) during recovery
	_finish_attack_cycle(0.48 if not is_phase_2 else 0.38, not has_dealt_strike_damage)

# ==============================================================================
# MOVE 3: Abyssal Earthshaker (Inner Slam + Expanding Shockwave Ring)
# ==============================================================================
func _start_ground_slam() -> void:
	last_attack_type = "slam"
	can_attack = false
	is_exposed = false
	current_state = State.SLAM_TELEGRAPH
	velocity = Vector2.ZERO
	slam_progress = 0.0
	slam_inner_radius = 70.0 if not is_phase_2 else 78.0
	slam_center_world = _get_body_center()
	
	if player_target and is_instance_valid(player_target):
		facing_direction = slam_center_world.direction_to(player_target.global_position)
	
	# Pose with greatsword raised overhead
	_pose_attack_windup(Vector2.DOWN, 1)
	animation.modulate = Color(2.3, 0.42, 0.48)
	animation.scale = base_anim_scale * Vector2(0.94, 1.12)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	
	var telegraph_time = 0.62 if not is_phase_2 else 0.52
	attack_tween.tween_method(func(val: float):
		slam_progress = val
		slam_center_world = _get_body_center()
	, 0.08, 1.0, telegraph_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_callback(_execute_ground_slam)

func _execute_ground_slam() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.SLAM_IMPACT
	slam_progress = 0.0
	var impact_center = _get_body_center()
	
	_play_attack_release(Vector2.DOWN, 2, 1.7)
	animation.modulate = Color(2.6, 1.6, 1.4)
	animation.scale = base_anim_scale * Vector2(1.16, 0.86)
	
	_trigger_screen_shake(5.2, 0.28)
	_spawn_slam_dust_particles()
	
	# 1. Inner Slam Impact (unblockable ground eruption inside slam_inner_radius)
	if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
		if impact_center.distance_to(player_target.global_position) <= slam_inner_radius:
			if player_target.has_method("take_damage"):
				player_target.take_damage(_scaled_dmg(24), null)
	
	# 2. Spawn Expanding Jump-Rope Shockwave Ring from slam rim outward across the arena
	active_shockwave_rings.append({
		"center": impact_center,
		"start_r": slam_inner_radius * 0.85,
		"end_r": 168.0 if not is_phase_2 else 190.0,
		"current_r": slam_inner_radius * 0.85,
		"thickness": 18.0,
		"elapsed": 0.0,
		"duration": 0.55 if not is_phase_2 else 0.48,
		"alpha": 1.0,
		"has_hit": false
	})
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(animation, "scale", base_anim_scale, 0.18)
	attack_tween.tween_callback(func():
		current_state = State.SLAM_RECOVERY
		animation.modulate = Color.WHITE
		# Sword is wedged in the stone floor: Exposed punish window for players who dodge inward through the ring!
		_finish_attack_cycle(0.55 if not is_phase_2 else 0.44, true)
	)

# ==============================================================================
# MOVE 4: Sundering Ground Waves (Linear Crescent Projectile / Phase 2 3-Way Fan)
# ==============================================================================
func _start_wave_attack() -> void:
	last_attack_type = "wave"
	can_attack = false
	is_exposed = false
	current_state = State.WAVE_TELEGRAPH
	velocity = Vector2.ZERO
	wave_telegraph_progress = 0.0
	
	var my_center = _get_body_center()
	var base_dir = Vector2.DOWN
	if player_target and is_instance_valid(player_target):
		base_dir = my_center.direction_to(player_target.global_position)
		facing_direction = base_dir
	attack_direction = base_dir
	
	wave_aim_dirs.clear()
	if is_phase_2:
		wave_aim_dirs.append(base_dir.rotated(-0.38))
		wave_aim_dirs.append(base_dir)
		wave_aim_dirs.append(base_dir.rotated(0.38))
	else:
		wave_aim_dirs.append(base_dir)
	
	_pose_attack_windup(base_dir, 1)
	animation.modulate = Color(1.8, 0.65, 1.0)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	var windup = 0.40 if not is_phase_2 else 0.34
	attack_tween.tween_method(func(val: float):
		wave_telegraph_progress = val
	, 0.0, 1.0, windup)
	attack_tween.tween_callback(_execute_wave_fire)

func _execute_wave_fire() -> void:
	if is_dead or current_state == State.STAGGERED:
		return
	current_state = State.WAVE_FIRE
	wave_telegraph_progress = 0.0
	animation.modulate = Color.WHITE
	_play_attack_release(attack_direction, 2, 1.7)
	_trigger_screen_shake(2.8, 0.15)
	
	var origin = _get_body_center() + attack_direction * 18.0
	for d in wave_aim_dirs:
		active_ground_waves.append({
			"pos": origin,
			"dir": d.normalized(),
			"speed": 205.0 if not is_phase_2 else 235.0,
			"radius": 18.0,
			"traveled": 0.0,
			"max_dist": 210.0,
			"has_hit": false
		})
	wave_aim_dirs.clear()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.20)
	attack_tween.tween_callback(func():
		current_state = State.WAVE_RECOVERY
		_finish_attack_cycle(0.36 if not is_phase_2 else 0.28, false)
	)

# ==============================================================================
# MOVE 5: Tactical Riposte Backstep
# ==============================================================================
func _start_backstep() -> void:
	last_attack_type = "backstep"
	current_state = State.BACKSTEP
	can_attack = false
	is_exposed = false
	ghost_spawn_timer = 0.0
	
	var my_center = _get_body_center()
	if player_target and is_instance_valid(player_target):
		facing_direction = my_center.direction_to(player_target.global_position)
	
	# Choose best retreat direction that doesn't back into a wall
	var retreat_dir = -facing_direction
	var safe_back = _clamp_distance_to_walls(my_center, retreat_dir, 64.0)
	if safe_back < 28.0:
		var side_a = retreat_dir.rotated(PI * 0.45)
		var side_b = retreat_dir.rotated(-PI * 0.45)
		retreat_dir = side_a if _clamp_distance_to_walls(my_center, side_a, 64.0) > _clamp_distance_to_walls(my_center, side_b, 64.0) else side_b
	
	velocity = retreat_dir * 235.0
	thrust_direction = facing_direction
	_spawn_thrust_dust_particles()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_property(animation, "modulate", Color(0.75, 0.9, 1.3, 0.8), 0.10)
	attack_tween.tween_property(animation, "modulate", Color.WHITE, 0.12)
	attack_tween.tween_callback(func():
		velocity = Vector2.ZERO
		if is_dead or current_state == State.STAGGERED:
			return
		if randf() < 0.55:
			_start_wave_attack()
		else:
			_start_thrust_attack()
	)

# ==============================================================================
# PHASE 2 TRANSITION: Ashen Blood Knight at <= 50% HP
# ==============================================================================
func _trigger_phase_2_transition() -> void:
	has_transitioned_phase_2 = true
	is_phase_2 = true
	_cancel_active_attack()
	current_state = State.PHASE_TRANSITION
	can_attack = false
	velocity = Vector2.ZERO
	is_invulnerable = true
	
	_pose_attack_windup(Vector2.DOWN, 1)
	animation.modulate = Color(2.8, 0.35, 0.32)
	animation.scale = base_anim_scale * Vector2(1.12, 1.12)
	
	if boss_name_label:
		boss_name_label.text = "ASHEN FALLEN KNIGHT"
		boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	if boss_health_bar and boss_health_bar.has_method("set_enraged"):
		boss_health_bar.set_enraged(true)
	
	_trigger_screen_shake(5.8, 0.42)
	_spawn_slam_dust_particles()
	
	var center = _get_body_center()
	active_shockwave_rings.append({
		"center": center,
		"start_r": 24.0,
		"end_r": 140.0,
		"current_r": 24.0,
		"thickness": 16.0,
		"elapsed": 0.0,
		"duration": 0.42,
		"alpha": 1.0,
		"has_hit": true
	})
	
	attack_tween = create_tween()
	attack_tween.tween_interval(0.70)
	attack_tween.tween_callback(func():
		is_invulnerable = false
		animation.modulate = Color.WHITE
		animation.scale = base_anim_scale
		current_state = State.CHASE
		can_attack = true
		_start_ground_slam()
	)

func _finish_attack_cycle(recovery_delay: float, expose_during_recovery: bool = false) -> void:
	current_state = State.RECOVERY
	velocity = Vector2.ZERO
	is_exposed = expose_during_recovery
	_update_idle_animation()
	if is_exposed:
		animation.modulate = Color(1.25, 0.92, 0.72)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(recovery_delay)
	attack_tween.tween_callback(func():
		is_exposed = false
		animation.modulate = Color.WHITE
		if is_dead or current_state == State.STAGGERED:
			return
		current_state = State.COOLDOWN
		var min_cd = 0.55 if is_phase_2 else min_attack_cooldown
		var max_cd = 0.85 if is_phase_2 else max_attack_cooldown
		var cd = randf_range(min_cd, max_cd)
		get_tree().create_timer(cd).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				can_attack = true
				if current_state == State.COOLDOWN:
					current_state = State.CHASE
		)
	)

func _deal_cone_slash_damage(dmg: int, max_reach: float, min_dot: float = 0.20) -> void:
	if is_dead or has_dealt_strike_damage:
		return
	if player_target and is_instance_valid(player_target) and is_player_in_boss_arena(player_target):
		var my_center = _get_body_center()
		var dist = my_center.distance_to(player_target.global_position)
		if dist <= max_reach and has_line_of_sight(player_target):
			var to_player = my_center.direction_to(player_target.global_position)
			if attack_direction.dot(to_player) >= min_dot or dist <= 26.0:
				if player_target.has_method("take_damage"):
					has_dealt_strike_damage = true
					player_target.take_damage(dmg, self)

# ==============================================================================
# PROCEDURAL TELEGRAPH & HAZARD RENDERER (World-Anchored)
# ==============================================================================
func _draw_telegraph_visuals(canvas: Node2D) -> void:
	var my_local_center = BODY_CENTER_OFFSET
	var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.016)
	
	# 1. Melee Slash Combo Arc Preview & Active Blade Trail
	if (current_state == State.SLASH_TELEGRAPH or current_state == State.SLASH_RECOVER_1) and slash_arc_progress > 0.01:
		var base_ang = slash_arc_dir.angle()
		var half_span = slash_arc_span * 0.5
		var fill_r = slash_arc_radius * slash_arc_progress
		_draw_sector(canvas, my_local_center, fill_r, base_ang - half_span, base_ang + half_span, Color(1.0, 0.82, 0.35, 0.16))
		canvas.draw_arc(my_local_center, slash_arc_radius, base_ang - half_span, base_ang + half_span, 24, Color(1.0, 0.88, 0.45, 0.65), 2.0)
	
	if slash_arc_alpha > 0.02:
		var base_ang = slash_arc_dir.angle()
		var half_span = slash_arc_span * 0.5
		canvas.draw_arc(my_local_center, slash_arc_radius * 0.88, base_ang - half_span, base_ang + half_span, 28, Color(1.0, 0.95, 0.8, slash_arc_alpha), 5.0)
		canvas.draw_arc(my_local_center, slash_arc_radius, base_ang - half_span, base_ang + half_span, 28, Color(1.0, 0.45, 0.25, slash_arc_alpha * 0.8), 2.5)
	
	if current_state == State.SLASH_SPIN_TELEGRAPH and spin_telegraph_progress > 0.01:
		var r = 68.0
		canvas.draw_circle(my_local_center, r * spin_telegraph_progress, Color(1.0, 0.55, 0.25, 0.20))
		canvas.draw_arc(my_local_center, r, 0.0, TAU, 36, Color(1.0, 0.78, 0.35, 0.85), 2.2)
	
	# 2. Straight-Line Impaling Lunge Telegraph (Clamped to Walls)
	if current_state == State.THRUST_TELEGRAPH:
		var start_local = canvas.to_local(thrust_origin_world)
		var dir = thrust_direction.normalized()
		var norm = Vector2(-dir.y, dir.x)
		var half_w = THRUST_WIDTH * 0.5
		var len_p = thrust_length
		
		var p1 = start_local - norm * half_w
		var p2 = start_local + norm * half_w
		var p3 = start_local + norm * half_w + dir * len_p
		var p4 = start_local - norm * half_w + dir * len_p
		
		var fill_col = Color(0.92, 0.16, 0.18, 0.22 + 0.12 * pulse) if not thrust_locked else Color(1.0, 0.82, 0.32, 0.34)
		var edge_col = Color(1.0, 0.32, 0.28, 0.82) if not thrust_locked else Color(1.0, 0.94, 0.55, 0.98)
		
		canvas.draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), fill_col)
		canvas.draw_polyline(PackedVector2Array([p1, p2, p3, p4, p1]), edge_col, 2.0)
		
		# Progress fill & directional chevrons along the lane
		var fill_end = len_p * clampf(thrust_progress, 0.0, 1.0)
		var fp3 = start_local + norm * half_w + dir * fill_end
		var fp4 = start_local - norm * half_w + dir * fill_end
		canvas.draw_colored_polygon(PackedVector2Array([p1, p2, fp3, fp4]), Color(1.0, 0.38, 0.28, 0.22))
		
		var num_chevrons = int(len_p / 28.0)
		for c in range(1, num_chevrons + 1):
			var c_dist = float(c) * 26.0
			if c_dist < len_p - 6.0:
				var tip = start_local + dir * c_dist
				var left_w = tip - dir * 7.0 - norm * (half_w * 0.65)
				var right_w = tip - dir * 7.0 + norm * (half_w * 0.65)
				canvas.draw_polyline(PackedVector2Array([left_w, tip, right_w]), edge_col, 1.6)
	
	# 3. Abyssal Earthshaker Inner Slam + Outer Ring Preview
	if current_state == State.SLAM_TELEGRAPH:
		var center_local = canvas.to_local(slam_center_world)
		var fill_r = slam_inner_radius * clampf(slam_progress, 0.1, 1.0)
		var fill_col = Color(0.86, 0.10, 0.14, 0.20 + 0.12 * pulse)
		var edge_col = Color(1.0, 0.26, 0.28, 0.92)
		
		canvas.draw_circle(center_local, fill_r, fill_col)
		canvas.draw_arc(center_local, slam_inner_radius, 0.0, TAU, 40, edge_col, 2.5)
		# Preview dashed ring showing that a shockwave will expand outward after impact
		canvas.draw_arc(center_local, slam_inner_radius + 22.0, 0.0, TAU, 28, Color(1.0, 0.55, 0.25, 0.32 * slam_progress), 1.2)
		
		var rot_offset = Time.get_ticks_msec() * 0.003
		for i in range(12):
			var ang = rot_offset + float(i) * (TAU / 12.0)
			var dir_v = Vector2(cos(ang), sin(ang))
			canvas.draw_line(center_local + dir_v * (slam_inner_radius - 6.0), center_local + dir_v * (slam_inner_radius + 3.0), edge_col, 1.8)
	
	# 4. Sundering Ground Wave Aim Telegraphs
	if current_state == State.WAVE_TELEGRAPH and not wave_aim_dirs.is_empty():
		for d in wave_aim_dirs:
			var end_pt = my_local_center + d.normalized() * (145.0 * wave_telegraph_progress)
			canvas.draw_line(my_local_center, end_pt, Color(1.0, 0.55, 0.28, 0.78), 3.0)
			canvas.draw_arc(end_pt, 12.0, d.angle() - 0.8, d.angle() + 0.8, 12, Color(1.0, 0.82, 0.38, 0.9), 2.2)
	
	# 5. World-Anchored Expanding Shockwave Rings
	for ring in active_shockwave_rings:
		var c_local = canvas.to_local(ring["center"])
		var r = ring["current_r"]
		var a = ring["alpha"]
		canvas.draw_arc(c_local, r, 0.0, TAU, 48, Color(1.0, 0.42, 0.18, a * 0.85), ring["thickness"] * 0.65)
		canvas.draw_arc(c_local, r, 0.0, TAU, 48, Color(1.0, 0.88, 0.48, a), 3.0)
	
	# 6. World-Anchored Traveling Crescent Ground Waves
	for w in active_ground_waves:
		var w_local = canvas.to_local(w["pos"])
		var ang = w["dir"].angle()
		canvas.draw_arc(w_local, w["radius"], ang - 1.05, ang + 1.05, 16, Color(1.0, 0.35, 0.2, 0.85), 6.0)
		canvas.draw_arc(w_local, w["radius"] * 1.05, ang - 0.95, ang + 0.95, 16, Color(1.0, 0.9, 0.55, 0.95), 2.5)
	
	# 7. Phase 2 Delayed Line Fissures
	for f in active_fissures:
		var s_local = canvas.to_local(f["start"])
		var e_local = canvas.to_local(f["end"])
		var dir = (e_local - s_local).normalized()
		var norm = Vector2(-dir.y, dir.x)
		var hw = f["width"] * 0.45
		var poly = PackedVector2Array([s_local - norm * hw, s_local + norm * hw, e_local + norm * hw, e_local - norm * hw])
		if not f["erupted"]:
			var warn_t = 1.0 - clampf(f["timer"] / 0.45, 0.0, 1.0)
			canvas.draw_colored_polygon(poly, Color(0.95, 0.22, 0.12, 0.18 + 0.25 * warn_t))
			canvas.draw_line(s_local, e_local, Color(1.0, 0.65, 0.22, 0.55 + 0.4 * warn_t), 2.5)
		else:
			var fade = 1.0 - clampf(f["erupt_elapsed"] / 0.30, 0.0, 1.0)
			canvas.draw_colored_polygon(poly, Color(1.0, 0.45, 0.15, 0.65 * fade))
			canvas.draw_line(s_local, e_local, Color(1.0, 0.95, 0.65, 0.95 * fade), 5.0)

func _draw_sector(canvas: Node2D, center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color) -> void:
	var pts = PackedVector2Array([center])
	var steps = 20
	for i in range(steps + 1):
		var a = lerpf(angle_from, angle_to, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	canvas.draw_colored_polygon(pts, color)

func _spawn_afterimage_ghost(tint: Color) -> void:
	if not animation or not animation.sprite_frames or not get_parent():
		return
	var tex = animation.sprite_frames.get_frame_texture(animation.animation, animation.frame)
	if not tex:
		return
	var ghost = Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = animation.flip_h
	ghost.scale = base_anim_scale
	ghost.global_position = animation.global_position
	ghost.z_index = z_index - 1
	ghost.modulate = tint
	get_parent().add_child(ghost)
	var tw = ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)

func _spawn_phase2_ambient_ember() -> void:
	var p = CPUParticles2D.new()
	p.amount = 3
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.8
	p.z_index = 1
	p.position = BODY_CENTER_OFFSET + Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 10.0))
	p.direction = Vector2.UP
	p.spread = 35.0
	p.gravity = Vector2(0, -45)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.6
	p.color = Color(1.0, 0.36, 0.18, 0.8)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.65).timeout.connect(p.queue_free)

func _spawn_fissure_eruption_particles(start_w: Vector2, end_w: Vector2) -> void:
	var p = CPUParticles2D.new()
	p.amount = 20
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 0.92
	p.z_index = 2
	p.global_position = (start_w + end_w) * 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(start_w.distance_to(end_w) * 0.45, 6.0)
	p.rotation = (end_w - start_w).angle()
	p.direction = Vector2.UP
	p.spread = 60.0
	p.gravity = Vector2(0, 60)
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 75.0
	p.scale_amount_min = 1.8
	p.scale_amount_max = 3.5
	p.color = Color(1.0, 0.42, 0.16, 0.9)
	get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(0.45).timeout.connect(p.queue_free)

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
	p.z_index = 0
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
	p.amount = 26
	p.lifetime = 0.42
	p.one_shot = true
	p.explosiveness = 0.95
	p.z_index = 0
	p.position = BODY_CENTER_OFFSET
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 115.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.2
	p.color = Color(0.72, 0.68, 0.62, 0.78) if not is_phase_2 else Color(0.95, 0.32, 0.22, 0.85)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.50).timeout.connect(p.queue_free)

func stagger(duration: float = 1.2) -> void:
	if is_dead:
		return
	
	has_stood_up = true
	_cancel_active_attack()
	current_state = State.STAGGERED
	is_exposed = true
	
	velocity = -attack_direction * 135.0
	
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
			is_exposed = false
			animation.modulate = Color.WHITE
			animation.scale = base_anim_scale
			current_state = State.COOLDOWN
			get_tree().create_timer(0.45).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.CHASE
			)
	)

func _on_boss_room_trigger_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and is_player_in_boss_arena(body):
		_set_boss_bar_visible(true)

func _on_boss_room_trigger_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_set_boss_bar_visible(false)

func _on_see_area_knight_area_entered(area: Area2D) -> void:
	var p: Node2D = null
	if area.owner and area.owner.is_in_group("player"):
		p = area.owner
	elif area.get_parent() and area.get_parent().is_in_group("player"):
		p = area.get_parent()
	if p and is_player_in_boss_arena(p) and has_line_of_sight(p):
		if current_state == State.SITTING:
			_start_stand_up(p)
		else:
			player_target = p
			_set_boss_bar_visible(true)

func _on_see_area_knight_area_exited(_area: Area2D) -> void:
	pass

func _on_see_area_knight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and is_player_in_boss_arena(body) and has_line_of_sight(body):
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
		if player_target and not is_player_in_boss_arena(player_target):
			return
		var kb_dir = (_get_body_center() - area.global_position).normalized()
		if kb_dir == Vector2.ZERO:
			kb_dir = -facing_direction
		
		var effective_damage = damage_per_hit
		if player_target and is_instance_valid(player_target):
			if player_target.has_method("get_total_damage_multiplier"):
				effective_damage = int(round(damage_per_hit * player_target.get_total_damage_multiplier()))
			elif "damage_multiplier" in player_target:
				effective_damage = int(round(damage_per_hit * player_target.damage_multiplier))
			if player_target.has_method("on_successful_sword_hit"):
				player_target.on_successful_sword_hit()
			
		take_damage(effective_damage, kb_dir)

func _on_attack_area_knight_area_entered(_area: Area2D) -> void:
	pass

func _on_attack_area_knight_body_entered(_body: Node2D) -> void:
	pass

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_invulnerable:
		return
	
	_set_boss_bar_visible(true)
	consecutive_hits_taken += 1
	
	var final_damage = amount
	var is_critical = false
	var is_punish = false
	
	if current_state == State.STAGGERED:
		final_damage = amount * 2
		is_critical = true
	elif is_exposed:
		final_damage = int(round(amount * 1.25))
		is_punish = true
	
	health = max(0, health - final_damage)
	
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(health, max_health)
	if boss_health_bar and boss_health_bar.has_method("set_health"):
		boss_health_bar.set_health(health, max_health)
	health_changed.emit(health, max_health)
	
	if FLOATING_TEXT_SCENE and get_parent():
		var ft = FLOATING_TEXT_SCENE.instantiate()
		ft.global_position = global_position + Vector2(randf_range(-6, 6), -14)
		get_parent().add_child(ft)
		if is_critical:
			ft.spawn("%d CRIT!" % final_damage, Color(1.0, 0.88, 0.25), 11, 22.0, 0.6)
		elif is_punish:
			ft.spawn("%d PUNISH!" % final_damage, Color(1.0, 0.62, 0.22), 10, 19.0, 0.55)
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
	
	# Boss poise: during committed attack animations or exposed punish recovery, flash hit feedback without cancelling
	var has_poise = is_exposed or current_state in [
		State.SLASH_TELEGRAPH, State.SLASH_HIT_1, State.SLASH_RECOVER_1, State.SLASH_HIT_2,
		State.SLASH_SPIN_TELEGRAPH, State.SLASH_HIT_3,
		State.THRUST_TELEGRAPH, State.THRUST_LUNGE,
		State.SLAM_TELEGRAPH, State.SLAM_IMPACT,
		State.WAVE_TELEGRAPH, State.WAVE_FIRE,
		State.BACKSTEP
	]
	
	if has_poise or current_state == State.STAGGERED:
		_flash_poise_hit()
	else:
		_apply_hitstun(knockback_dir, is_critical)

func _flash_poise_hit() -> void:
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	var restore_col = Color(1.25, 0.92, 0.72) if is_exposed else Color.WHITE
	animation.modulate = Color(2.4, 0.55, 0.55)
	damage_tween = create_tween()
	damage_tween.tween_property(animation, "modulate", restore_col, 0.14)

func _apply_hitstun(knockback_dir: Vector2, is_critical: bool) -> void:
	_cancel_active_attack()
	has_stood_up = true
	current_state = State.HITSTUN
	can_attack = false
	velocity = knockback_dir * 85.0
	
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale * Vector2(0.92, 1.10)
	animation.modulate = Color(3.0, 2.6, 0.8) if is_critical else Color(2.2, 0.3, 0.3)
	
	damage_tween = create_tween()
	damage_tween.set_parallel(true)
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.18)
	damage_tween.tween_property(animation, "scale", base_anim_scale, 0.18)
	
	get_tree().create_timer(0.18).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.HITSTUN:
			if consecutive_hits_taken >= 3:
				consecutive_hits_taken = 0
				_start_backstep()
				return
			current_state = State.COOLDOWN
			get_tree().create_timer(0.35 if is_phase_2 else post_hit_cooldown).timeout.connect(func():
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
	_cancel_active_attack()
	active_shockwave_rings.clear()
	active_ground_waves.clear()
	active_fissures.clear()
	if telegraph_canvas:
		telegraph_canvas.queue_redraw()
	
	_lock_arena_doors(false)
	enemy_died.emit(self)
	velocity = Vector2.ZERO
	hit_shape_knight.set_deferred("disabled", true)
	ground_collisison_knight.set_deferred("disabled", true)
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	if attack_tween and attack_tween.is_running():
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
