extends CharacterBody2D

@onready var player_animation: AnimatedSprite2D = $player_animation
@onready var block_shape: CollisionShape2D = $block_area_player/block_shape
@onready var attack_shape: CollisionShape2D = $attack_area_player/attack_shape_player
@onready var max_block_time: Timer = $max_block_time
@onready var health_bar = $hud/margin/hbox/player_health_bar
@onready var damage_vignette: ColorRect = $hud/damage_vignette
var vignette_tween: Tween = null

const SPEED = 100.0
const DODGE_SPEED: float = 220.0
const DODGE_DURATION: float = 0.22
const DODGE_COOLDOWN: float = 0.30
const PARRY_WINDOW: float = 0.22
const ATTACK_ACTIVE_WINDOW: float = 0.16
const ATTACK_MOVE_RESUME_WINDOW: float = 0.24

# Out-of-combat Natural Regeneration
const REGEN_DELAY: float = 4.5
const REGEN_INTERVAL: float = 0.5
const REGEN_AMOUNT: int = 2
var time_since_last_damage: float = 0.0
var regen_tick_timer: float = 0.0

# Boosts and Modifiers
var speed_boost_timer: float = 0.0
var speed_multiplier: float = 1.0
var damage_boost_timer: float = 0.0
var damage_multiplier: float = 1.0

# Permanent Upgrades from Loot Chests
var permanent_speed_bonus: float = 0.0
var permanent_damage_bonus: float = 0.0
var permanent_lifesteal: int = 0

@export var max_health: int = 100
var health: int = max_health

var isAttacking = false
var isBlocking = false
var isDodging = false
var can_dodge = true
var is_invulnerable: bool = false
var is_dead: bool = false
var damage_tween: Tween = null
var buff_tint_timer: float = 0.0

var attack_timer: float = 0.0
var attack_can_cancel: bool = false
var dodge_buffered: bool = false

var facing_direction: Vector2 = Vector2.DOWN
var dodge_direction: Vector2 = Vector2.DOWN
var block_start_time: float = 0.0
@onready var camera: Camera2D = get_node_or_null("Camera2D")

func _ready() -> void:
	add_to_group("player")
	health = max_health
	if health_bar:
		health_bar.set_health(health, max_health)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Process active buffs
	if speed_boost_timer > 0.0:
		speed_boost_timer = maxf(0.0, speed_boost_timer - delta)
		if speed_boost_timer == 0.0:
			speed_multiplier = 1.0
			
	if damage_boost_timer > 0.0:
		damage_boost_timer = maxf(0.0, damage_boost_timer - delta)
		if damage_boost_timer == 0.0:
			damage_multiplier = 1.0

	# Natural Out-of-Combat Regeneration (heals when avoiding damage)
	if health < max_health:
		time_since_last_damage += delta
		if time_since_last_damage >= REGEN_DELAY:
			regen_tick_timer += delta
			if regen_tick_timer >= REGEN_INTERVAL:
				regen_tick_timer = 0.0
				heal(REGEN_AMOUNT, false)

	# Determine if player has movement control
	var can_move := not isBlocking and not isDodging and (not isAttacking or attack_timer >= ATTACK_MOVE_RESUME_WINDOW)

	# get direction inputs
	var direction_x := 0.0
	if Input.is_action_pressed("Right") and can_move:
		direction_x += 1.0
	if Input.is_action_pressed("Left") and can_move:
		direction_x -= 1.0
	
	var direction_y := 0.0
	if Input.is_action_pressed("Down") and can_move:
		direction_y += 1.0
	if Input.is_action_pressed("Up") and can_move:
		direction_y -= 1.0
		
	var input_direction := Vector2(direction_x, direction_y)
	
	if input_direction != Vector2.ZERO:
		facing_direction = input_direction.normalized()
		# If walking out of attack recovery, smoothly resume walking
		if isAttacking and attack_timer >= ATTACK_MOVE_RESUME_WINDOW:
			isAttacking = false
			attack_shape.disabled = true
			attack_can_cancel = false
			dodge_buffered = false

	# Handle active attack timing and dodge canceling
	if isAttacking:
		attack_timer += delta
		if attack_timer >= ATTACK_ACTIVE_WINDOW:
			attack_shape.disabled = true
			attack_can_cancel = true
			if dodge_buffered and can_dodge and not isDodging:
				_cancel_attack_and_dodge(input_direction if input_direction != Vector2.ZERO else facing_direction)
				return
	
	# dodge roll / dash trigger (supports instant dodge cancel and input buffering during attack)
	if Input.is_action_just_pressed("Dodge"):
		if isAttacking:
			if attack_can_cancel and can_dodge and not isDodging:
				_cancel_attack_and_dodge(input_direction if input_direction != Vector2.ZERO else facing_direction)
				return
			else:
				dodge_buffered = true
		elif can_dodge and not isDodging and not isBlocking:
			_start_dodge(input_direction)
			return
	
	# If currently dodging, skip standard movement/input overrides
	if isDodging:
		velocity = dodge_direction * (DODGE_SPEED + permanent_speed_bonus * 1.35)
		move_and_slide()
		return
	
	# aply vel with active speed multiplier and permanent speed bonus
	var current_speed = (SPEED + permanent_speed_bonus) * speed_multiplier
	if direction_y:
		velocity.y = direction_y * current_speed
	else:
		velocity.y = move_toward(velocity.y, 0, current_speed)
		
	if direction_x:
		velocity.x = direction_x * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
	
	# walk and idle
	if input_direction != Vector2.ZERO and not isAttacking and not isBlocking:
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
	elif not isAttacking and not isBlocking:
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
	
	# attack animation trigger
	if Input.is_action_just_pressed("Attack_sword") and not isBlocking and not isDodging and not isAttacking:
		isAttacking = true
		attack_timer = 0.0
		attack_can_cancel = false
		dodge_buffered = false
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
	if Input.is_action_just_pressed("Block_sword") && isAttacking == false && isDodging == false:
		isBlocking = true
		block_start_time = Time.get_ticks_msec() / 1000.0
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

func _cancel_attack_and_dodge(input_dir: Vector2) -> void:
	isAttacking = false
	attack_shape.disabled = true
	attack_can_cancel = false
	dodge_buffered = false
	_start_dodge(input_dir)

func _start_dodge(input_dir: Vector2) -> void:
	isDodging = true
	can_dodge = false
	is_invulnerable = true
	
	if input_dir != Vector2.ZERO:
		dodge_direction = input_dir.normalized()
	else:
		dodge_direction = facing_direction
		
	if abs(dodge_direction.x) > abs(dodge_direction.y):
		if dodge_direction.x > 0:
			player_animation.play("walk_right")
		else:
			player_animation.play("walk_left")
	else:
		if dodge_direction.y > 0:
			player_animation.play("walk_down")
		else:
			player_animation.play("walk_up")
			
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate:a", 0.45, 0.05)
	
	get_tree().create_timer(DODGE_DURATION).timeout.connect(func():
		if is_instance_valid(self) and not is_dead:
			isDodging = false
			is_invulnerable = false
			player_animation.modulate.a = 1.0
			get_tree().create_timer(DODGE_COOLDOWN).timeout.connect(func():
				if is_instance_valid(self):
					can_dodge = true
			)
	)

func take_damage(amount: int, attacker: Node2D = null) -> void:
	if is_dead or is_invulnerable:
		return
	
	if isBlocking:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - block_start_time
		if elapsed <= PARRY_WINDOW and attacker != null and attacker.has_method("stagger"):
			print("PARRY! Attack deflected!")
			_flash_parry()
			shake_camera(5.0, 0.25)
			attacker.stagger(1.2)
			return
		else:
			print("Player blocked the attack!")
			_flash_block()
			shake_camera(2.5, 0.15)
			return
	
	# Interrupt natural regeneration on taking damage
	time_since_last_damage = 0.0
	regen_tick_timer = 0.0
	
	health = max(0, health - amount)
	print("Player took damage! Current health: ", health)
	
	if health_bar:
		health_bar.set_health(health, max_health)
	
	shake_camera(4.5, 0.22)
	
	if health <= 0:
		_die()
	else:
		_flash_red()
		_trigger_damage_vignette(0.9)

func heal(amount: int, show_flash: bool = true) -> void:
	if is_dead:
		return
	var old_health = health
	health = mini(max_health, health + amount)
	if health_bar and health != old_health:
		health_bar.set_health(health, max_health)
	if show_flash:
		_flash_heal()

func apply_speed_boost(duration: float = 6.0, multiplier: float = 1.38) -> void:
	speed_boost_timer = maxf(speed_boost_timer, duration)
	speed_multiplier = multiplier
	_flash_speed_buff()

func apply_damage_boost(duration: float = 7.0, multiplier: float = 1.5) -> void:
	damage_boost_timer = maxf(damage_boost_timer, duration)
	damage_multiplier = multiplier
	_flash_power_buff()

func get_total_damage_multiplier() -> float:
	return (1.0 + permanent_damage_bonus) * damage_multiplier

func on_successful_sword_hit() -> void:
	if permanent_lifesteal > 0 and not is_dead:
		heal(permanent_lifesteal, false)

func apply_permanent_upgrade(upgrade_id: int) -> Dictionary:
	shake_camera(3.5, 0.25)
	match upgrade_id:
		0:
			max_health += 35
			health = mini(max_health, health + 35)
			if health_bar:
				health_bar.custom_minimum_size.x += 28
				health_bar.set_health(health, max_health)
			_flash_heal()
			return {"title": "TITAN HEART (+35 MAX HP)", "color": Color(0.35, 1.0, 0.55)}
		1:
			permanent_damage_bonus += 0.40
			_flash_power_buff()
			return {"title": "RUNIC BROADSWORD (+40% DMG)", "color": Color(1.0, 0.85, 0.3)}
		2:
			permanent_speed_bonus += 22.0
			_flash_speed_buff()
			return {"title": "WINDWALKER GREAVES (+SPEED)", "color": Color(0.35, 0.9, 1.0)}
		_:
			permanent_damage_bonus += 0.30
			permanent_lifesteal += 5
			_flash_parry()
			return {"title": "VAMPIRIC SOULBLADE (+DMG & LIFESTEAL)", "color": Color(1.0, 0.45, 0.78)}

func shake_camera(intensity: float = 4.0, duration: float = 0.2) -> void:
	if not camera:
		camera = get_node_or_null("Camera2D")
	if not camera:
		return
	var tw = create_tween()
	tw.tween_method(func(val: float):
		camera.offset = Vector2(randf_range(-val, val), randf_range(-val, val))
	, intensity, 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _flash_heal() -> void:
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	player_animation.modulate = Color(0.4, 2.2, 0.6)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.28)

func _flash_speed_buff() -> void:
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	player_animation.modulate = Color(0.3, 1.8, 2.4)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.3)

func _flash_power_buff() -> void:
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	player_animation.modulate = Color(2.5, 1.8, 0.3)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.3)

func _trigger_damage_vignette(target_intensity: float = 0.9) -> void:
	if not damage_vignette or not damage_vignette.material:
		return
	var mat = damage_vignette.material as ShaderMaterial
	if not mat:
		return
	if vignette_tween and vignette_tween.is_running():
		vignette_tween.kill()
	
	mat.set_shader_parameter("intensity", target_intensity)
	vignette_tween = create_tween()
	vignette_tween.tween_method(func(val: float):
		mat.set_shader_parameter("intensity", val)
	, target_intensity, 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _flash_parry() -> void:
	if damage_tween and damage_tween.is_running():
		damage_tween.kill()
	player_animation.modulate = Color(2.6, 2.2, 0.4)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.18)

func _flash_block() -> void:
	if damage_tween:
		damage_tween.kill()
	player_animation.modulate = Color(0.7, 0.9, 1.5)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.15)

func _flash_red() -> void:
	is_invulnerable = true
	if damage_tween:
		damage_tween.kill()
	
	# Reddish damage tint
	player_animation.modulate = Color(1.0, 0.25, 0.25)
	damage_tween = create_tween()
	damage_tween.tween_property(player_animation, "modulate", Color.WHITE, 0.2)
	# Invulnerability blinking
	damage_tween.tween_property(player_animation, "modulate:a", 0.4, 0.1)
	damage_tween.tween_property(player_animation, "modulate:a", 1.0, 0.1)
	damage_tween.tween_property(player_animation, "modulate:a", 0.4, 0.1)
	damage_tween.tween_property(player_animation, "modulate:a", 1.0, 0.1)
	damage_tween.tween_callback(func(): is_invulnerable = false)

func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	if damage_tween:
		damage_tween.kill()
	
	if damage_vignette and damage_vignette.material:
		var mat = damage_vignette.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("intensity", 1.0)
	
	player_animation.modulate = Color(1.0, 0.25, 0.25)
	var death_tween = create_tween()
	death_tween.tween_property(player_animation, "modulate:a", 0.0, 0.6)
	death_tween.tween_interval(0.3)
	death_tween.tween_callback(func():
		if ResourceLoader.exists("res://scenes/u_dead.tscn"):
			get_tree().change_scene_to_file.call_deferred("res://scenes/u_dead.tscn")
		else:
			get_tree().reload_current_scene.call_deferred()
	)

func _on_player_animation_animation_finished() -> void:
	if player_animation.animation.begins_with("attack_"):
		isAttacking = false
		attack_shape.disabled = true
		attack_can_cancel = false
		dodge_buffered = false
	
	if player_animation.animation.begins_with("block_"):
		if not Input.is_action_pressed("Block_sword"):
			isBlocking = false
			block_shape.disabled = true

func _on_max_block_time_timeout() -> void:
	isBlocking = false
	block_shape.disabled = true
