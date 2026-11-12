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
const MENU_LOGO_TEX = preload("res://assets/sprites/menu_logo.png")
const MENU_FONT = preload("res://assets/fonts/PressStart2P-Regular.ttf")

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
	
	_setup_minecraft_menu()
	_play_scene_fade_in()

func _setup_minecraft_menu() -> void:
	if not menu_hud:
		return
	var ui_root: Control = menu_hud.get_node_or_null("center")
	if not ui_root:
		return
	
	# Big Minecraft-style 3D stone-block TŘEBEŠÍN KNIGHT banner centered at top (6x integer pixel scale)
	var logo_rect := TextureRect.new()
	logo_rect.name = "trebesin_logo"
	logo_rect.texture = MENU_LOGO_TEX
	logo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_size := Vector2(756.0, 324.0)
	logo_rect.position = Vector2(957.0 - logo_size.x * 0.5, 44.0)
	logo_rect.size = logo_size
	ui_root.add_child(logo_rect)
	
	# Classic tilted pulsing yellow Minecraft splash text with Czech diacritics
	var splash := Label.new()
	splash.name = "splash_label"
	splash.text = "Třebešín Edition!"
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash.add_theme_font_override("font", MENU_FONT)
	splash.add_theme_font_size_override("font_size", 18)
	splash.add_theme_color_override("font_color", Color(1.0, 1.0, 0.25, 1.0))
	splash.add_theme_color_override("font_shadow_color", Color(0.18, 0.14, 0.0, 1.0))
	splash.add_theme_constant_override("shadow_offset_x", 3)
	splash.add_theme_constant_override("shadow_offset_y", 3)
	splash.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.02, 1.0))
	splash.add_theme_constant_override("outline_size", 5)
	splash.size = Vector2(360.0, 32.0)
	splash.pivot_offset = splash.size * 0.5
	splash.position = Vector2(957.0 + 170.0, 226.0)
	splash.rotation = -0.26
	ui_root.add_child(splash)
	
	var splash_tw := create_tween().set_loops()
	splash_tw.tween_property(splash, "scale", Vector2(1.07, 1.07), 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	splash_tw.tween_property(splash, "scale", Vector2(0.96, 0.96), 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Style menu buttons like classic Minecraft stone menu bars
	var vbox: VBoxContainer = ui_root.get_node_or_null("vbox")
	if vbox:
		vbox.position = Vector2(957.0 - 170.0, 692.0)
		vbox.size = Vector2(340.0, 160.0)
		vbox.add_theme_constant_override("separation", 18)
	
	for btn in [start_button, settings_button]:
		if not btn:
			continue
		btn.custom_minimum_size = Vector2(340.0, 66.0)
		btn.add_theme_font_override("font", MENU_FONT)
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.7, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.88, 1.0))
		btn.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.08, 1.0))
		btn.add_theme_constant_override("outline_size", 4)
		btn.add_theme_stylebox_override("normal", _make_stone_button_style(Color(0.32, 0.33, 0.37, 0.94), Color(0.56, 0.58, 0.64, 1.0)))
		btn.add_theme_stylebox_override("hover", _make_stone_button_style(Color(0.38, 0.40, 0.48, 0.98), Color(0.76, 0.78, 0.84, 1.0)))
		btn.add_theme_stylebox_override("pressed", _make_stone_button_style(Color(0.22, 0.23, 0.27, 0.98), Color(0.42, 0.44, 0.50, 1.0)))
		btn.add_theme_stylebox_override("focus", _make_stone_button_style(Color(0.36, 0.38, 0.45, 0.96), Color(0.85, 0.78, 0.42, 1.0)))

func _make_stone_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.border_width_bottom = 5
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0.03, 0.03, 0.05, 0.85)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, 3)
	return sb

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
