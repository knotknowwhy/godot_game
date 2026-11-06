extends StaticBody2D

signal door_opened
signal door_closed

@onready var door_slot: Control = $door_slot
@onready var door_sprite: Sprite2D = $door_slot/door_sprite
@onready var collision_shape: CollisionShape2D = $collision_shape

@export var slide_distance: float = 36.0
@export var slide_duration: float = 1.2
@export var is_open: bool = false

var tween: Tween = null

func _ready() -> void:
	_ensure_references()
	if is_open:
		if door_sprite:
			door_sprite.position.y = 18.0 - slide_distance
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
	else:
		if door_sprite:
			door_sprite.position.y = 18.0
		if collision_shape:
			collision_shape.set_deferred("disabled", false)

func _ensure_references() -> void:
	if not door_slot:
		door_slot = get_node_or_null("door_slot")
	if not door_sprite:
		door_sprite = get_node_or_null("door_slot/door_sprite")
	if not collision_shape:
		collision_shape = get_node_or_null("collision_shape")

func open_door() -> void:
	if is_open:
		return
	is_open = true
	_ensure_references()
	
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
			print("Sliding portcullis door opened!")
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
		tween.tween_property(door_sprite, "position:y", 18.0, 0.6)\
			.set_trans(Tween.TRANS_BOUNCE)\
			.set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if collision_shape:
				collision_shape.set_deferred("disabled", false)
			door_closed.emit()
			print("Sliding portcullis door closed!")
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
		for i in range(8):
			var shake = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			ct.tween_property(camera, "offset", orig_offset + shake, 0.04)
		ct.tween_property(camera, "offset", orig_offset, 0.05)
