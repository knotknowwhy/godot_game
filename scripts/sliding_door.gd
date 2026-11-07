extends StaticBody2D

signal door_opened
signal door_closed

@onready var door_slot: Control = $door_slot
@onready var door_sprite: Sprite2D = $door_slot/door_sprite
@onready var collision_shape: CollisionShape2D = $collision_shape
@onready var fade_trigger: Area2D = get_node_or_null("fade_trigger")

@export var slide_distance: float = 36.0
@export var slide_duration: float = 1.0
@export var is_open: bool = false
@export var open_on_proximity: bool = false
@export var proximity_radius: float = 38.0
@export var is_locked: bool = false
@export var mist_nodes: Array[NodePath] = []

var tween: Tween = null
var initial_sprite_y: float = 18.0
var pulse_timer: float = 0.0

# Wall-fade shader setup for closed gate
var _fade_mat: ShaderMaterial = null
var _fade_tween: Tween = null
var _current_fade: float = 0.0
var _inside_bodies: Array[Node2D] = []

func _ready() -> void:
	_ensure_references()
	if door_sprite:
		initial_sprite_y = door_sprite.position.y
		_init_fade_shader()
	
	if fade_trigger:
		if not fade_trigger.body_entered.is_connected(_on_fade_body_entered):
			fade_trigger.body_entered.connect(_on_fade_body_entered)
		if not fade_trigger.body_exited.is_connected(_on_fade_body_exited):
			fade_trigger.body_exited.connect(_on_fade_body_exited)
	
	if is_open:
		z_index = 1
		if door_sprite:
			door_sprite.position.y = initial_sprite_y - slide_distance
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		_reveal_mist(true)
	else:
		z_index = 1
		if door_sprite:
			door_sprite.position.y = initial_sprite_y
		if collision_shape:
			collision_shape.set_deferred("disabled", false)

func _init_fade_shader() -> void:
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = preload("res://shaders/radial_wall_fade.gdshader")
	_fade_mat.set_shader_parameter("radius", 45.0)
	_fade_mat.set_shader_parameter("softness", 18.0)
	_fade_mat.set_shader_parameter("min_alpha", 0.42)
	_fade_mat.set_shader_parameter("fade_active", 0.0)
	_fade_mat.set_shader_parameter("player_pos", global_position)
	door_sprite.material = _fade_mat

func _on_fade_body_entered(body: Node2D) -> void:
	# Only player triggers gate fade when behind it, never enemies
	if (body.is_in_group("player") or body.name == "player") and not _inside_bodies.has(body):
		_inside_bodies.append(body)
	_update_fade_state()

func _on_fade_body_exited(body: Node2D) -> void:
	if _inside_bodies.has(body):
		_inside_bodies.erase(body)
	_update_fade_state()

func _update_fade_state() -> void:
	if is_open:
		z_index = 1
		_fade_to(0.0)
		return
	
	_inside_bodies = _inside_bodies.filter(func(b): return is_instance_valid(b))
	
	if not _inside_bodies.is_empty():
		z_index = 3
		_fade_to(1.0)
	else:
		z_index = 1
		_fade_to(0.0)

func _fade_to(target_val: float) -> void:
	if _fade_tween and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(func(val: float):
		_current_fade = val
		if _fade_mat:
			_fade_mat.set_shader_parameter("fade_active", val)
	, _current_fade, target_val, 0.2)

func _physics_process(delta: float) -> void:
	if is_open:
		return
	
	# Update radial fade position to the player
	if not _inside_bodies.is_empty() and _fade_mat:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player):
			_fade_mat.set_shader_parameter("player_pos", player.global_position)
	
	# Subtle golden invitation shimmer when a proximity gate is unlocked and ready to open
	if open_on_proximity and not is_locked and door_sprite and _inside_bodies.is_empty():
		pulse_timer += delta * 4.0
		var g = 1.0 + (sin(pulse_timer) * 0.5 + 0.5) * 0.35
		door_sprite.modulate = Color(g * 1.1, g * 1.05, 1.0)
	elif door_sprite and _inside_bodies.is_empty():
		door_sprite.modulate = Color.WHITE
	
	if not open_on_proximity or is_locked:
		return
	
	var p = get_tree().get_first_node_in_group("player")
	if p and is_instance_valid(p):
		var door_center = global_position + (collision_shape.position if collision_shape else Vector2.ZERO)
		if door_center.distance_to(p.global_position) <= proximity_radius:
			open_door()

func lock_door() -> void:
	is_locked = true

func unlock_door() -> void:
	is_locked = false

func lock_and_close() -> void:
	is_locked = true
	_ensure_references()
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	close_door()

func _ensure_references() -> void:
	if not door_slot:
		door_slot = get_node_or_null("door_slot")
	if not door_sprite:
		door_sprite = get_node_or_null("door_slot/door_sprite")
	if not collision_shape:
		collision_shape = get_node_or_null("collision_shape")
	if not fade_trigger:
		fade_trigger = get_node_or_null("fade_trigger")

func _reveal_mist(instant: bool = false) -> void:
	for path in mist_nodes:
		var mist = get_node_or_null(path)
		if mist and is_instance_valid(mist):
			if instant:
				mist.modulate.a = 0.0
				mist.visible = false
			else:
				var mt = create_tween()
				mt.tween_property(mist, "modulate:a", 0.0, 0.85)\
					.set_trans(Tween.TRANS_QUAD)\
					.set_ease(Tween.EASE_OUT)
				mt.tween_callback(func():
					if is_instance_valid(mist):
						mist.visible = false
				)

func open_door() -> void:
	if is_open:
		return
	is_open = true
	is_locked = false
	_ensure_references()
	if door_sprite:
		door_sprite.modulate = Color.WHITE
	_reveal_mist(false)
	_fade_to(0.0)
	
	if tween and tween.is_running():
		tween.kill()
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	if door_sprite and is_inside_tree():
		tween = create_tween()
		tween.tween_property(door_sprite, "position:y", initial_sprite_y - slide_distance, slide_duration)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
		
		_screen_rumble()
		
		tween.tween_callback(func():
			z_index = 1
			door_opened.emit()
		)
	else:
		if door_sprite:
			door_sprite.position.y = initial_sprite_y - slide_distance
		z_index = 1
		door_opened.emit()

func close_door() -> void:
	_ensure_references()
	_update_fade_state()
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	
	if not is_open:
		if door_sprite:
			door_sprite.position.y = initial_sprite_y
		_update_fade_state()
		return
	is_open = false
	
	if tween and tween.is_running():
		tween.kill()
		
	if door_sprite and is_inside_tree():
		tween = create_tween()
		tween.tween_property(door_sprite, "position:y", initial_sprite_y, 0.45)\
			.set_trans(Tween.TRANS_BOUNCE)\
			.set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if collision_shape:
				collision_shape.set_deferred("disabled", false)
			_update_fade_state()
			door_closed.emit()
		)
	else:
		if door_sprite:
			door_sprite.position.y = initial_sprite_y
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
		_update_fade_state()
		door_closed.emit()

func _screen_rumble() -> void:
	var viewport = get_viewport()
	if not viewport:
		return
	var camera = viewport.get_camera_2d()
	if camera:
		var ct = create_tween()
		var orig_offset = camera.offset
		for i in range(6):
			var shake = Vector2(randf_range(-1.2, 1.2), randf_range(-1.2, 1.2))
			ct.tween_property(camera, "offset", orig_offset + shake, 0.04)
		ct.tween_property(camera, "offset", orig_offset, 0.05)
