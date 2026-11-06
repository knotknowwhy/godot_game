extends StaticBody2D

signal door_opened
signal door_closed

@onready var door_slot: Control = $door_slot
@onready var door_sprite: Sprite2D = $door_slot/door_sprite
@onready var collision_shape: CollisionShape2D = $collision_shape

@export var slide_distance: float = 36.0
@export var slide_duration: float = 1.0
@export var is_open: bool = false
@export var open_on_proximity: bool = false
@export var proximity_radius: float = 30.0
@export var is_locked: bool = false
@export var mist_nodes: Array[NodePath] = []

var tween: Tween = null

func _ready() -> void:
	_ensure_references()
	if is_open:
		if door_sprite:
			door_sprite.position.y = 18.0 - slide_distance
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		_reveal_mist(true)
	else:
		if door_sprite:
			door_sprite.position.y = 18.0
		if collision_shape:
			collision_shape.set_deferred("disabled", false)

func _physics_process(_delta: float) -> void:
	if is_open or not open_on_proximity or is_locked:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		var door_center = global_position + (collision_shape.position if collision_shape else Vector2.ZERO)
		if door_center.distance_to(player.global_position) <= proximity_radius:
			open_door()

func unlock_door() -> void:
	is_locked = false

func _ensure_references() -> void:
	if not door_slot:
		door_slot = get_node_or_null("door_slot")
	if not door_sprite:
		door_sprite = get_node_or_null("door_slot/door_sprite")
	if not collision_shape:
		collision_shape = get_node_or_null("collision_shape")

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
	_reveal_mist(false)
	
	if tween and tween.is_running():
		tween.kill()
	
	# Disable collision so player can pass through
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Smooth mechanical sliding animation
	if door_sprite and is_inside_tree():
		tween = create_tween()
		tween.tween_property(door_sprite, "position:y", 18.0 - slide_distance, slide_duration)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
		
		_screen_rumble()
		
		tween.tween_callback(func():
			door_opened.emit()
		)
	else:
		if door_sprite:
			door_sprite.position.y = 18.0 - slide_distance
		door_opened.emit()

func close_door() -> void:
	if not is_open:
		return
	is_open = false
	_ensure_references()
	
	if tween and tween.is_running():
		tween.kill()
		
	if door_sprite and is_inside_tree():
		tween = create_tween()
		tween.tween_property(door_sprite, "position:y", 18.0, 0.5)\
			.set_trans(Tween.TRANS_BOUNCE)\
			.set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if collision_shape:
				collision_shape.set_deferred("disabled", false)
			door_closed.emit()
		)
	else:
		if door_sprite:
			door_sprite.position.y = 18.0
		if collision_shape:
			collision_shape.set_deferred("disabled", false)
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
