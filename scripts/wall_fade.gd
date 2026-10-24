extends Area2D

@export_group("Target Walls")
## Single target wall (primary target or legacy setup)
@export var target_wall: CanvasItem
@export var target_wall_path: NodePath
## Multiple target walls (if this fade trigger controls multiple independent layers)
@export var target_walls: Array[CanvasItem] = []
@export var target_wall_paths: Array[NodePath] = []

@export_group("Fade Settings")
@export var fade_radius: float = 48.0
@export var fade_softness: float = 18.0
@export var min_alpha: float = 0.62
@export var fade_duration: float = 0.2

var _targets: Array[CanvasItem] = []
var _original_z: Dictionary = {}
var _mat: ShaderMaterial
var _tween: Tween
var _player: Node2D = null
var _is_player_inside: bool = false
var _current_fade: float = 0.0

func _ready() -> void:
	_gather_targets()
	
	if not _targets.is_empty():
		# Create dedicated radial fade shader material instance for this trigger
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://shaders/radial_wall_fade.gdshader")
		_mat.set_shader_parameter("radius", fade_radius)
		_mat.set_shader_parameter("softness", fade_softness)
		_mat.set_shader_parameter("min_alpha", min_alpha)
		_mat.set_shader_parameter("fade_active", 0.0)
		
		for target in _targets:
			if target != null:
				_original_z[target] = target.z_index
				target.material = _mat
	
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _gather_targets() -> void:
	_targets.clear()
	
	# 1. Check direct target_wall
	if target_wall != null and not _targets.has(target_wall):
		_targets.append(target_wall)
	elif not target_wall_path.is_empty():
		var node = get_node_or_null(target_wall_path) as CanvasItem
		if node != null and not _targets.has(node):
			_targets.append(node)
	
	# 2. Check explicit array of target_walls
	for w in target_walls:
		if w != null and not _targets.has(w):
			_targets.append(w)
			
	for path in target_wall_paths:
		if not path.is_empty():
			var node = get_node_or_null(path) as CanvasItem
			if node != null and not _targets.has(node):
				_targets.append(node)
	
	# 3. Fallback: if nothing specified, auto-discover first sibling TileMapLayer
	if _targets.is_empty() and get_parent() != null:
		for child in get_parent().get_children():
			if child is TileMapLayer and child != self:
				_targets.append(child)
				break
	
	# 4. Auto-discover all child CanvasItems / TileMapLayers under any registered target
	var extra_children: Array[CanvasItem] = []
	for target in _targets:
		_collect_child_layers(target, extra_children)
	
	for child_layer in extra_children:
		if not _targets.has(child_layer):
			_targets.append(child_layer)

func _collect_child_layers(node: Node, result: Array[CanvasItem]) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			result.append(child)
			_collect_child_layers(child, result)

func _process(_delta: float) -> void:
	if _is_player_inside and _player != null and _mat != null:
		_mat.set_shader_parameter("player_pos", _player.global_position)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D or body.is_in_group("player"):
		_is_player_inside = true
		_player = body
		# Boost top-level targets to foreground (children with relative z follow automatically)
		for target in _targets:
			if target != null:
				var p = target.get_parent() as CanvasItem
				if p == null or not _targets.has(p):
					target.z_index = _original_z.get(target, 0) + 2
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
			if not _is_player_inside:
				for target in _targets:
					if target != null:
						var p = target.get_parent() as CanvasItem
						if p == null or not _targets.has(p):
							target.z_index = _original_z.get(target, 0)
		)
