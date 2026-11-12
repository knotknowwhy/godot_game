extends Node2D

@onready var player: CharacterBody2D = $player/player
@onready var player_anim: AnimatedSprite2D = $player/player/player_animation
@onready var camera: Camera2D = $player/player/Camera2D
@onready var entrance_door: Node2D = $entrance_door
@onready var arena_manager_room1: Node2D = $arena_manager
@onready var menu_hud: CanvasLayer = $menu_ui
@onready var start_button: Button = $menu_ui/center/vbox/start_game
@onready var settings_button: Button = $menu_ui/center/vbox/settings

var intro_started: bool = false

const MENU_PLAYER_POS = Vector2(10, 157)
const ROOM1_PLAYER_POS = Vector2(10, 36)
const MENU_CAMERA_ZOOM = Vector2(6.8, 6.8)
const GAME_CAMERA_ZOOM = Vector2(4.98, 4.98)

func _ready() -> void:
	if player:
		player.position = MENU_PLAYER_POS
		player.is_controllable = false
		player.set_hud_visible(false)
		if player_anim:
			player_anim.play("idle_down")
	
	if camera:
		camera.zoom = MENU_CAMERA_ZOOM
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 6.0

	if entrance_door:
		if entrance_door.has_method("lock_door"):
			entrance_door.lock_door()

	if start_button and not start_button.pressed.is_connected(_on_start_game_pressed):
		start_button.pressed.connect(_on_start_game_pressed)
	if settings_button and not settings_button.pressed.is_connected(_on_settings_pressed):
		settings_button.pressed.connect(_on_settings_pressed)
	
	_play_scene_fade_in()

func _play_scene_fade_in() -> void:
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 100
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)
	
	var tw = create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fade_layer.queue_free)

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings.tscn")

func _on_start_game_pressed() -> void:
	if intro_started:
		return
	intro_started = true
	
	if start_button:
		start_button.disabled = true
	if settings_button:
		settings_button.disabled = true
		
	# Smoothly fade out the menu UI
	if menu_hud:
		var fade_tween = create_tween()
		var ui_root = menu_hud.get_node_or_null("center")
		if ui_root:
			fade_tween.tween_property(ui_root, "modulate:a", 0.0, 0.35)
		else:
			menu_hud.visible = false
	
	# Open entrance portcullis door
	if entrance_door and entrance_door.has_method("open_door"):
		entrance_door.open_door()
	
	# Brief pause for gate opening rumble, then walk through into Room 1
	get_tree().create_timer(0.45).timeout.connect(_start_character_walk)

func _start_character_walk() -> void:
	if not player or not is_instance_valid(player):
		return
	
	if player_anim:
		player_anim.play("walk_up")
	
	var walk_duration: float = 1.6
	var walk_tween = create_tween()
	
	# Move character from menu room through the gate into Room 1
	walk_tween.tween_property(player, "position", ROOM1_PLAYER_POS, walk_duration)\
		.set_trans(Tween.TRANS_LINEAR)
	
	# Smoothly zoom camera back to default gameplay zoom
	if camera:
		walk_tween.parallel().tween_property(camera, "zoom", GAME_CAMERA_ZOOM, walk_duration)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
			
	walk_tween.tween_callback(_on_walk_finished)

func _on_walk_finished() -> void:
	if not player or not is_instance_valid(player):
		return
	
	# Stop walking animation
	if player_anim:
		player_anim.play("idle_up")
	
	# Lock and close entrance portcullis door behind the player
	if entrance_door and entrance_door.has_method("lock_and_close"):
		entrance_door.lock_and_close()
		
	# Hand over control to player and reveal player HUD
	player.is_controllable = true
	player.set_hud_visible(true)
	
	if menu_hud:
		menu_hud.visible = false
		
	# Start wave countdown for Room 1
	if arena_manager_room1 and arena_manager_room1.has_method("start_arena"):
		arena_manager_room1.start_arena()
