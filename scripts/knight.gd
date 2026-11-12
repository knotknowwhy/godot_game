extends CharacterBody2D

signal enemy_died(enemy)
signal health_changed(current_health: int, max_health: int)

enum State {
	SITTING,
	STANDING_UP,
	IDLE,
	CHASE,
	TELEGRAPH,
	STRIKE,
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

const SPEED: float = 48.0
const STRIKE_NUDGE_SPEED: float = 42.0
const BODY_CENTER_OFFSET: Vector2 = Vector2(0.0, 28.0)

var facing_direction: Vector2 = Vector2.DOWN
var attack_direction: Vector2 = Vector2.DOWN

const PICKUP_SCENE = preload("res://scenes/pickup.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@export var start_sitting: bool = true
@export var wake_up_distance: float = 120.0
@export var boss_title: String = "FALLEN KNIGHT"
@export var show_boss_health_bar: bool = true
@export var use_boss_room_rect: bool = false
@export var boss_room_rect: Rect2 = Rect2(242.0, -267.0, 304.0, 243.0)
@export var boss_room_trigger: NodePath

@export var max_health: int = 1000
@export var damage_per_hit: int = 35
@export var attack_damage: int = 20
@export var attack_range: float = 80.0
@export var strike_reach: float = 98.0
@export var min_attack_cooldown: float = 1.1
@export var max_attack_cooldown: float = 1.6
@export var post_hit_cooldown: float = 1.0

var current_state: State = State.SITTING
var health: int = max_health
var player_target: Node2D = null

var is_dead: bool = false
var is_invulnerable: bool = false
var can_attack: bool = true
var has_dealt_strike_damage: bool = false
var has_stood_up: bool = false
var is_boss_bar_visible: bool = false
var damage_tween: Tween = null
var attack_tween: Tween = null
var boss_bar_tween: Tween = null
var base_anim_scale: Vector2 = Vector2(3.0, 3.0)

# Organic AI personality parameters
var flank_offset_angle: float = 0.0
var wander_seed: float = 0.0
var speed_variance: float = 1.0

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
	
	if not boss_room_trigger.is_empty():
		var trigger_node = get_node_or_null(boss_room_trigger)
		if trigger_node and trigger_node is Area2D:
			trigger_node.body_entered.connect(_on_boss_room_trigger_body_entered)
			trigger_node.body_exited.connect(_on_boss_room_trigger_body_exited)
	
	# Automatically enable boss_room_rect check if the knight is placed inside the boss room
	if boss_room_rect.has_point(global_position):
		use_boss_room_rect = true
	
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
	
	# Assign unique approach characteristics
	flank_offset_angle = randf_range(-0.55, 0.55)
	wander_seed = randf_range(0.0, 100.0)
	speed_variance = randf_range(0.92, 1.08)
	
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

func _check_room_and_proximity() -> void:
	var p = _find_player_node()
	if not p or not is_instance_valid(p):
		return
	
	# Show/hide boss health bar when entering/leaving the boss room
	if use_boss_room_rect:
		var in_room = boss_room_rect.has_point(p.global_position)
		if in_room:
			_set_boss_bar_visible(true)
		elif is_boss_bar_visible:
			_set_boss_bar_visible(false)
	
	# Check if player is close enough to wake the boss from the throne
	var dist = _get_body_center().distance_to(p.global_position)
	if current_state == State.SITTING:
		if dist <= wake_up_distance:
			_start_stand_up(p)
	elif has_stood_up and not player_target and dist <= wake_up_distance:
		player_target = p
		_set_boss_bar_visible(true)

func _start_stand_up(target: Node2D = null) -> void:
	if current_state != State.SITTING or is_dead:
		return
	if target:
		player_target = target
	else:
		player_target = _find_player_node()
	
	current_state = State.STANDING_UP
	velocity = Vector2.ZERO
	_set_boss_bar_visible(true)
	
	if animation:
		animation.flip_h = false
		animation.play("sit_up")
	
	# sit_up has 4 frames at 8 FPS (0.5s total)
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.5)
	attack_tween.tween_callback(_finish_stand_up)

func _finish_stand_up() -> void:
	if is_dead:
		return
	has_stood_up = true
	if current_state == State.STANDING_UP:
		current_state = State.CHASE if (player_target and is_instance_valid(player_target)) else State.IDLE
		_update_idle_animation()

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
		elif d < 32.0:
			push += (diff / d) * (1.0 - d / 32.0)
	
	if player_target and is_instance_valid(player_target):
		var p_diff = my_center - player_target.global_position
		var p_dist = p_diff.length()
		if p_dist < 24.0:
			var p_dir = (p_diff / p_dist) if p_dist > 0.001 else Vector2.UP
			push += p_dir * (1.0 - p_dist / 24.0) * 0.8
			
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
	
	match current_state:
		State.SITTING:
			velocity = Vector2.ZERO
			if animation and animation.animation != &"sit":
				animation.flip_h = false
				animation.play("sit")
			
		State.STANDING_UP:
			velocity = Vector2.ZERO
			
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.0)
			if player_target and is_instance_valid(player_target):
				if can_attack:
					current_state = State.CHASE
				else:
					facing_direction = my_center.direction_to(player_target.global_position)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.COOLDOWN:
			if player_target and is_instance_valid(player_target):
				var to_player = my_center.direction_to(player_target.global_position)
				var dist = my_center.distance_to(player_target.global_position)
				facing_direction = to_player
				var sep = _get_separation_vector()
				if dist < 36.0:
					velocity = (-to_player * 18.0 + sep * 20.0)
				else:
					var circle_sign = 1.0 if flank_offset_angle >= 0.0 else -1.0
					var circle_dir = to_player.rotated(PI * 0.45 * circle_sign)
					velocity = (circle_dir * 18.0 + sep * 18.0)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
			_update_animation_by_velocity()
			move_and_slide()
			
		State.CHASE:
			if player_target and is_instance_valid(player_target):
				var dist = my_center.distance_to(player_target.global_position)
				if dist <= attack_range and can_attack:
					_start_telegraph()
				else:
					wander_seed += delta * 2.2
					var sway = sin(wander_seed) * 0.18
					var to_player = my_center.direction_to(player_target.global_position)
					var approach_dir = to_player.rotated(flank_offset_angle + sway)
					var sep = _get_separation_vector()
					
					var forward_proj = sep.dot(approach_dir)
					if forward_proj < 0.0:
						var lateral = sep - approach_dir * forward_proj
						sep = lateral.normalized() * minf(sep.length(), 0.9)
					
					var move_dir = (approach_dir + sep * 0.95).normalized()
					velocity = move_dir * (SPEED * speed_variance)
					facing_direction = to_player
					_update_animation_by_velocity()
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
				current_state = State.IDLE
				_update_animation_by_velocity()
			move_and_slide()
			
		State.TELEGRAPH:
			velocity = Vector2.ZERO
			move_and_slide()
			
		State.STRIKE:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.5)
			move_and_slide()
			
		State.RECOVERY:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 3.0)
			_update_idle_animation()
			move_and_slide()
			
		State.HITSTUN:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 4.0)
			move_and_slide()
			
		State.STAGGERED:
			velocity = velocity.move_toward(Vector2.ZERO, SPEED * 2.5)
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

func _start_telegraph() -> void:
	current_state = State.TELEGRAPH
	can_attack = false
	velocity = Vector2.ZERO
	
	if player_target and is_instance_valid(player_target):
		attack_direction = _get_body_center().direction_to(player_target.global_position)
		facing_direction = attack_direction
	
	# Play the knight's actual attack animation directly without red/white flashing
	animation.offset = Vector2.ZERO
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale
	animation.modulate = Color.WHITE
	_play_attack_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.16)
	attack_tween.tween_callback(_start_strike)

func _start_strike() -> void:
	if is_dead or current_state == State.STAGGERED or current_state == State.HITSTUN:
		return
	
	current_state = State.STRIKE
	has_dealt_strike_damage = false
	velocity = attack_direction * STRIKE_NUDGE_SPEED
	
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", false)
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.04)
	attack_tween.tween_callback(_execute_strike_hit)
	attack_tween.tween_interval(0.36)
	attack_tween.tween_callback(_start_recovery)

func _execute_strike_hit() -> void:
	if is_dead or current_state != State.STRIKE or has_dealt_strike_damage:
		return
	
	if player_target and is_instance_valid(player_target):
		var my_center = _get_body_center()
		var dist = my_center.distance_to(player_target.global_position)
		if dist <= strike_reach:
			var to_player = my_center.direction_to(player_target.global_position)
			if attack_direction.dot(to_player) > 0.15:
				if player_target.has_method("take_damage"):
					has_dealt_strike_damage = true
					player_target.take_damage(attack_damage, self)

func _start_recovery() -> void:
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	if is_dead or current_state == State.STAGGERED or current_state == State.HITSTUN:
		return
	
	current_state = State.RECOVERY
	velocity = Vector2.ZERO
	_update_idle_animation()
	
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	attack_tween = create_tween()
	attack_tween.tween_interval(0.22)
	attack_tween.tween_callback(func():
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
			get_tree().create_timer(0.6).timeout.connect(func():
				if is_instance_valid(self) and not is_dead:
					can_attack = true
					if current_state == State.COOLDOWN:
						current_state = State.CHASE
			)
	)

func _on_boss_room_trigger_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
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
	if p:
		if current_state == State.SITTING:
			_start_stand_up(p)
		else:
			player_target = p
			if not use_boss_room_rect:
				_set_boss_bar_visible(true)

func _on_see_area_knight_area_exited(_area: Area2D) -> void:
	pass

func _on_see_area_knight_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if current_state == State.SITTING:
			_start_stand_up(body)
		else:
			player_target = body
			if not use_boss_room_rect:
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
	if is_dead or current_state != State.STRIKE or has_dealt_strike_damage:
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
	if is_dead or current_state != State.STRIKE or has_dealt_strike_damage:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		has_dealt_strike_damage = true
		body.take_damage(attack_damage, self)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if is_dead or is_invulnerable:
		return
	
	_set_boss_bar_visible(true)
	
	var final_damage = amount
	var is_critical = false
	
	if current_state == State.STAGGERED:
		final_damage = amount * 2
		is_critical = true
		print("CRITICAL COUNTER-ATTACK HIT! Dealt: ", final_damage)
	
	health = max(0, health - final_damage)
	print("Knight took damage! Current health: ", health)
	
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
	
	if current_state == State.SITTING:
		_start_stand_up()
		return
	if current_state == State.STANDING_UP:
		return
	
	_apply_hitstun(knockback_dir, is_critical)

func _apply_hitstun(knockback_dir: Vector2, is_critical: bool) -> void:
	if attack_tween and attack_tween.is_running():
		attack_tween.kill()
	if attack_shape_knight:
		attack_shape_knight.set_deferred("disabled", true)
	
	has_stood_up = true
	current_state = State.HITSTUN
	can_attack = false
	velocity = knockback_dir * 110.0
	
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	animation.position = Vector2.ZERO
	animation.scale = base_anim_scale * Vector2(0.88, 1.15)
	animation.modulate = Color(3.0, 2.6, 0.8) if is_critical else Color(2.2, 0.3, 0.3)
	
	damage_tween = create_tween()
	damage_tween.set_parallel(true)
	damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.22)
	damage_tween.tween_property(animation, "scale", base_anim_scale, 0.22)
	
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(self) and not is_dead and current_state == State.HITSTUN:
			is_invulnerable = false
			current_state = State.COOLDOWN
			get_tree().create_timer(post_hit_cooldown).timeout.connect(func():
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
