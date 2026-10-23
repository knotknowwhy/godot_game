extends Area2D

@export var target_wall_path: NodePath
@export var target_wall: CanvasItem
@export var fade_radius: float = 48.0
@export var fade_softness: float = 18.0
@export var min_alpha: float = 0.62
@export var fade_duration: float = 0.2

var _target: CanvasItem
var _mat: ShaderMaterial
var _tween: Tween
var _player: Node2D = null
var _is_player_inside: bool = false
var _current_fade: float = 0.0

func _ready() -> void:
	if target_wall != null:
		_target = target_wall
	elif not target_wall_path.is_empty():
		_target = get_node_or_null(target_wall_path) as CanvasItem
	
	if _target == null:
		for child in get_parent().get_children():
			if child is TileMapLayer and child != self:
				_target = child
				break
	
	if _target != null:
		# Attach dedicated radial fade shader material
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://shaders/radial_wall_fade.gdshader")
		_mat.set_shader_parameter("radius", fade_radius)
		_mat.set_shader_parameter("softness", fade_softness)
		_mat.set_shader_parameter("min_alpha", min_alpha)
		_mat.set_shader_parameter("fade_active", 0.0)
		_target.material = _mat
		_target.z_index = 0
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _is_player_inside and _player != null and _mat != null:
		_mat.set_shader_parameter("player_pos", _player.global_position)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D or body.is_in_group("player"):
		_is_player_inside = true
		_player = body
		if _target != null:
			_target.z_index = 2
		_fade_to(1.0)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D or body.is_in_group("player"):
		_is_player_inside = false
		_fade_to(0.0)

func _fade_to(target_value: float) -> void:
	if _mat == null:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(
		func(val: float):
			_current_fade = val
			if _mat != null:
				_mat.set_shader_parameter("fade_active", val),
		_current_fade,
		target_value,
		fade_duration
	)
	if target_value == 0.0:
		_tween.finished.connect(func():
			if not _is_player_inside and _target != null:
				_target.z_index = 0
		)
