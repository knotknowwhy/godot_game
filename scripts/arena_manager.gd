extends Node2D

signal arena_started
signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal arena_completed

@export var room_id: int = 1
@export var door_node: Node2D
@export var entrance_doors: Array[NodePath] = []
@export var unlock_doors: Array[NodePath] = []
@export var entities_container: Node
@export var countdown_seconds: int = 3
@export var wave_intermission_seconds: float = 1.6

const SKELETON_SCENE = preload("res://scenes/skeleton.tscn")
const WITCH_DOCTOR_SCENE = preload("res://scenes/witch_doctor.tscn")
const PYROMANCER_SCENE = preload("res://scenes/pyromancer.tscn")
const LOOT_CHEST_SCENE = preload("res://scenes/loot_chest.tscn")

@onready var hud_layer: CanvasLayer = $arena_hud
@onready var announcement_label: Label = $arena_hud/center_anchor/announcement_label

var waves: Array = []
var chest_spawn_pos: Vector2 = Vector2(8, 12)
var chest_upgrade_id: int = 0
var trigger_rect: Rect2 = Rect2()

var current_wave_index: int = 0
var active_enemies: Array[Node2D] = []
var is_arena_active: bool = false
var is_arena_cleared: bool = false
var has_triggered: bool = false
var current_tween: Tween = null

func _ready() -> void:
	if not entities_container:
		entities_container = get_parent().get_node_or_null("entities")
	if not door_node and room_id == 1:
		door_node = get_parent().get_node_or_null("sliding_door")
	
	if announcement_label:
		announcement_label.visible = false
	
	_configure_room()
	
	if room_id == 1:
		has_triggered = true
		get_tree().create_timer(0.8).timeout.connect(func():
			_start_wave_intro(current_wave_index)
		)

func _configure_room() -> void:
	match room_id:
		1:
			countdown_seconds = 5
			chest_spawn_pos = Vector2(8, 10)
			chest_upgrade_id = 0
			waves = [
				{
					"name": "Wave 1",
					"spawns": [
						{"pos": Vector2(-75, 25), "type": "skeleton"},
						{"pos": Vector2(85, 15), "type": "skeleton"}
					]
				},
				{
					"name": "Wave 2",
					"spawns": [
						{"pos": Vector2(-70, -15), "type": "skeleton"},
						{"pos": Vector2(85, -15), "type": "skeleton"},
						{"pos": Vector2(8, 48), "type": "witch_doctor"}
					]
				}
			]
		2:
			countdown_seconds = 3
			chest_spawn_pos = Vector2(4, -156)
			chest_upgrade_id = 1
			trigger_rect = Rect2(-155, -225, 295, 105)
			waves = [
				{
					"name": "Wave 1",
					"spawns": [
						{"pos": Vector2(-95, -142), "type": "skeleton"},
						{"pos": Vector2(92, -142), "type": "skeleton"},
						{"pos": Vector2(4, -198), "type": "witch_doctor"}
					]
				},
				{
					"name": "Wave 2",
					"spawns": [
						{"pos": Vector2(-102, -195), "type": "witch_doctor"},
						{"pos": Vector2(96, -195), "type": "pyromancer"},
						{"pos": Vector2(-40, -142), "type": "skeleton"}
					]
				}
			]
		3:
			countdown_seconds = 3
			chest_spawn_pos = Vector2(4, -346)
			chest_upgrade_id = 2
			trigger_rect = Rect2(-155, -418, 295, 122)
			waves = [
				{
					"name": "Wave 1",
					"spawns": [
						{"pos": Vector2(-98, -322), "type": "witch_doctor"},
						{"pos": Vector2(92, -322), "type": "witch_doctor"},
						{"pos": Vector2(4, -390), "type": "skeleton"}
					]
				},
				{
					"name": "Wave 2",
					"spawns": [
						{"pos": Vector2(-100, -390), "type": "pyromancer"},
						{"pos": Vector2(96, -390), "type": "skeleton"},
						{"pos": Vector2(-55, -322), "type": "skeleton"},
						{"pos": Vector2(65, -322), "type": "witch_doctor"}
					]
				}
			]
		4:
			countdown_seconds = 3
			chest_spawn_pos = Vector2(392, -376)
			chest_upgrade_id = 3
			trigger_rect = Rect2(268, -450, 250, 134)
			waves = [
				{
					"name": "Wave 1",
					"spawns": [
						{"pos": Vector2(305, -352), "type": "pyromancer"},
						{"pos": Vector2(475, -352), "type": "pyromancer"},
						{"pos": Vector2(392, -418), "type": "skeleton"}
					]
				},
				{
					"name": "Wave 2",
					"spawns": [
						{"pos": Vector2(300, -420), "type": "pyromancer"},
						{"pos": Vector2(480, -420), "type": "witch_doctor"},
						{"pos": Vector2(345, -348), "type": "skeleton"},
						{"pos": Vector2(440, -348), "type": "skeleton"}
					]
				}
			]

func _physics_process(_delta: float) -> void:
	if has_triggered or is_arena_cleared or room_id == 1:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		if trigger_rect.has_point(player.global_position):
			has_triggered = true
			_lock_entrance_doors()
			_start_wave_intro(current_wave_index)

func _lock_entrance_doors() -> void:
	for d_path in entrance_doors:
		var d = get_node_or_null(d_path)
		if d:
			if "is_locked" in d:
				d.is_locked = true
			if d.has_method("close_door"):
				d.close_door()

func _start_wave_intro(wave_idx: int) -> void:
	is_arena_active = true
	arena_started.emit()
	
	var wave_num = wave_idx + 1
	var total_waves = waves.size()
	
	_pop_text("Wave %d/%d starts" % [wave_num, total_waves], Color.WHITE, 26, 1.0, func():
		_start_countdown(countdown_seconds, wave_idx)
	)

func _start_countdown(seconds_left: int, wave_idx: int) -> void:
	if seconds_left > 0:
		_pop_text("%d" % seconds_left, Color.WHITE, 38, 0.75, func():
			_start_countdown(seconds_left - 1, wave_idx)
		)
	else:
		_pop_text("FIGHT!", Color(1.0, 0.9, 0.45), 32, 0.4, func():
			_fade_out_announcement(func():
				_spawn_wave(wave_idx)
			)
		)

func _spawn_wave(wave_idx: int) -> void:
	var wave_data = waves[wave_idx]
	var wave_num = wave_idx + 1
	wave_started.emit(wave_num)
	
	var spawn_entries: Array = wave_data["spawns"]
	active_enemies.clear()
	
	for entry in spawn_entries:
		if entry is Dictionary:
			_spawn_enemy(entry["pos"], entry.get("type", "skeleton"))
		elif entry is Vector2:
			_spawn_enemy(entry, "skeleton")

func _spawn_enemy(pos: Vector2, enemy_type: String = "skeleton") -> void:
	if not entities_container:
		return
	
	var scene_to_spawn: PackedScene = SKELETON_SCENE
	if enemy_type == "witch_doctor":
		scene_to_spawn = WITCH_DOCTOR_SCENE
	elif enemy_type == "pyromancer":
		scene_to_spawn = PYROMANCER_SCENE
	
	var enemy = scene_to_spawn.instantiate() as CharacterBody2D
	enemy.global_position = pos
	
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
		_pop_text("Wave %d Cleared!" % wave_num, Color(0.4, 1.0, 0.5), 26, 1.2, func():
			current_wave_index += 1
			_start_wave_intro(current_wave_index)
		)
	else:
		_on_all_waves_cleared()

func _on_all_waves_cleared() -> void:
	is_arena_cleared = true
	is_arena_active = false
	arena_completed.emit()
	
	# Spawn Loot Chest with permanent character upgrade
	_spawn_loot_chest()
	
	# Re-open any entrance doors that locked when the encounter began
	for d_path in entrance_doors:
		var d = get_node_or_null(d_path)
		if d and d.has_method("open_door"):
			d.open_door()
	
	# Open primary room exit door
	if door_node and door_node.has_method("open_door"):
		door_node.open_door()
	
	# Unlock any proximity hallway doors connected to this room
	for d_path in unlock_doors:
		var d = get_node_or_null(d_path)
		if d and d.has_method("unlock_door"):
			d.unlock_door()
	
	_pop_text("Room Cleared! Chest Spawned!", Color(1.0, 0.9, 0.4), 26, 2.0, func():
		_fade_out_announcement()
	)

func _spawn_loot_chest() -> void:
	if not LOOT_CHEST_SCENE or not entities_container:
		return
	var chest = LOOT_CHEST_SCENE.instantiate()
	chest.global_position = chest_spawn_pos
	chest.upgrade_id = chest_upgrade_id
	entities_container.call_deferred("add_child", chest)

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
