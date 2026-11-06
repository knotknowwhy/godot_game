extends Node2D

signal arena_started
signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal arena_completed

@export var door_node: Node2D
@export var entities_container: Node
@export var enemy_scene: PackedScene = preload("res://scenes/skeleton.tscn")
@export var countdown_seconds: int = 5
@export var wave_intermission_seconds: float = 2.0

@onready var hud_layer: CanvasLayer = $arena_hud
@onready var announcement_label: Label = $arena_hud/center_anchor/announcement_label

var waves: Array = [
	{
		"name": "Wave 1",
		"spawns": [
			Vector2(50, 20),
			Vector2(-20, -10)
		]
	},
	{
		"name": "Wave 2",
		"spawns": [
			Vector2(-110, -15),
			Vector2(80, 45),
			Vector2(0, 30)
		]
	}
]

var current_wave_index: int = 0
var active_enemies: Array[Node2D] = []
var is_arena_active: bool = false
var is_arena_cleared: bool = false
var current_tween: Tween = null

func _ready() -> void:
	if not entities_container:
		entities_container = get_parent().get_node_or_null("entities")
	if not door_node:
		door_node = get_parent().get_node_or_null("sliding_door")
	
	if announcement_label:
		announcement_label.visible = false
	
	# Start countdown sequence after scene stabilization
	get_tree().create_timer(0.8).timeout.connect(func():
		_start_wave_intro(current_wave_index)
	)

func _start_wave_intro(wave_idx: int) -> void:
	is_arena_active = true
	arena_started.emit()
	
	var wave_num = wave_idx + 1
	var total_waves = waves.size()
	
	# Pure text pop-up: "Wave 1/2 starts"
	_pop_text("Wave %d/%d starts" % [wave_num, total_waves], Color.WHITE, 26, 1.2, func():
		_start_countdown(countdown_seconds, wave_idx)
	)

func _start_countdown(seconds_left: int, wave_idx: int) -> void:
	if seconds_left > 0:
		# Numbers "5", "4", "3", "2", "1" replacing each other
		_pop_text("%d" % seconds_left, Color.WHITE, 38, 0.85, func():
			_start_countdown(seconds_left - 1, wave_idx)
		)
	else:
		# Final short punch "FIGHT!" that fades and disappears
		_pop_text("FIGHT!", Color(1.0, 0.9, 0.45), 32, 0.45, func():
			_fade_out_announcement(func():
				_spawn_wave(wave_idx)
			)
		)

func _spawn_wave(wave_idx: int) -> void:
	var wave_data = waves[wave_idx]
	var wave_num = wave_idx + 1
	wave_started.emit(wave_num)
	
	var spawn_points: Array = wave_data["spawns"]
	active_enemies.clear()
	
	for spawn_pos in spawn_points:
		_spawn_enemy(spawn_pos)

func _spawn_enemy(pos: Vector2) -> void:
	if not enemy_scene or not entities_container:
		return
	
	var enemy = enemy_scene.instantiate() as CharacterBody2D
	enemy.global_position = pos
	
	# Visual flare (red summon flash + pop-in scale)
	enemy.scale = Vector2(0.2, 0.2)
	enemy.modulate = Color(2.5, 0.4, 0.4, 0.0)
	
	entities_container.add_child(enemy)
	active_enemies.append(enemy)
	
	var spawn_tween = create_tween()
	spawn_tween.set_parallel(true)
	spawn_tween.tween_property(enemy, "scale", Vector2.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	spawn_tween.tween_property(enemy, "modulate", Color.WHITE, 0.4)
	
	# Connect to death notification
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_defeated)
	else:
		enemy.tree_exited.connect(func(): _on_enemy_defeated(enemy))

func _on_enemy_defeated(enemy: Node2D) -> void:
	if enemy in active_enemies:
		active_enemies.erase(enemy)
	
	if active_enemies.is_empty():
		_on_wave_cleared()

func _on_wave_cleared() -> void:
	var wave_num = current_wave_index + 1
	wave_cleared.emit(wave_num)
	
	if current_wave_index + 1 < waves.size():
		# Show short wave cleared notice, then advance
		_pop_text("Wave %d Cleared!" % wave_num, Color(0.4, 1.0, 0.5), 26, 1.3, func():
			current_wave_index += 1
			_start_wave_intro(current_wave_index)
		)
	else:
		_on_all_waves_cleared()

func _on_all_waves_cleared() -> void:
	is_arena_cleared = true
	is_arena_active = false
	arena_completed.emit()
	
	# Open sliding door
	if door_node and door_node.has_method("open_door"):
		door_node.open_door()
	
	# "Room Cleared!" announcement that fades out cleanly
	_pop_text("Room Cleared!", Color(1.0, 0.9, 0.4), 30, 2.0, func():
		_fade_out_announcement()
	)

func _pop_text(msg: String, color: Color, font_size: int, duration: float, on_complete: Callable = Callable()) -> void:
	if not announcement_label:
		if on_complete.is_valid():
			on_complete.call()
		return
	
	announcement_label.text = msg
	announcement_label.add_theme_font_size_override("font_size", font_size)
	announcement_label.modulate = color
	announcement_label.visible = true
	
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	# Scale punch pop-in from center
	announcement_label.scale = Vector2(1.3, 1.3)
	current_tween = create_tween()
	current_tween.tween_property(announcement_label, "scale", Vector2.ONE, 0.15)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	
	if on_complete.is_valid():
		current_tween.tween_interval(duration)
		current_tween.tween_callback(on_complete)

func _fade_out_announcement(on_complete: Callable = Callable()) -> void:
	if not announcement_label:
		if on_complete.is_valid():
			on_complete.call()
		return
	
	if current_tween and current_tween.is_running():
		current_tween.kill()
	
	current_tween = create_tween()
	current_tween.tween_property(announcement_label, "modulate:a", 0.0, 0.25)
	current_tween.tween_callback(func():
		announcement_label.visible = false
		if on_complete.is_valid():
			on_complete.call()
	)
