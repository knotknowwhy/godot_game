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

var _logo_rect: TextureRect = null
var _splash_label: Label = null

func _ready() -> void:
	if player:
		player.position = MENU_PLAYER_POS
		player.is_controllable = false
		player.set_hud_visible(false)
		if player_anim:
			player_anim.play("idle_down")
	
	if camera:
		camera.zoom = _get_effective_menu_zoom()
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
	if get_viewport() and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	_play_scene_fade_in()

func _get_zoom_scale() -> float:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return 1.0
	return clampf(vp_size.x / 1480.0, 0.62, 1.0)

func _get_effective_menu_zoom() -> Vector2:
	return MENU_CAMERA_ZOOM * _get_zoom_scale()

func _get_effective_game_zoom() -> Vector2:
	return GAME_CAMERA_ZOOM * _get_zoom_scale()

func _on_viewport_size_changed() -> void:
	_layout_menu_ui()
	if camera and is_instance_valid(camera):
		if not intro_started:
			camera.zoom = _get_effective_menu_zoom()
		elif player and is_instance_valid(player) and player.is_controllable:
			camera.zoom = _get_effective_game_zoom()

func _setup_minecraft_menu() -> void:
	if not menu_hud:
		return
	var ui_root: Control = menu_hud.get_node_or_null("center")
	if not ui_root:
		return
	ui_root.offset_left = 0.0
	ui_root.offset_top = 0.0
	ui_root.offset_right = 0.0
	ui_root.offset_bottom = 0.0
	
	# Big Minecraft-style 3D stone-block TŘEBEŠÍN KNIGHT banner centered at top
	_logo_rect = TextureRect.new()
	_logo_rect.name = "trebesin_logo"
	_logo_rect.texture = MENU_LOGO_TEX
	_logo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(_logo_rect)
	
	# Classic tilted pulsing yellow Minecraft splash text with Czech diacritics
	_splash_label = Label.new()
	_splash_label.name = "splash_label"
	_splash_label.text = "Třebešín Edition!"
	_splash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_splash_label.add_theme_font_override("font", MENU_FONT)
	_splash_label.add_theme_font_size_override("font_size", 18)
	_splash_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.25, 1.0))
	_splash_label.add_theme_color_override("font_shadow_color", Color(0.18, 0.14, 0.0, 1.0))
	_splash_label.add_theme_constant_override("shadow_offset_x", 3)
	_splash_label.add_theme_constant_override("shadow_offset_y", 3)
	_splash_label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.02, 1.0))
	_splash_label.add_theme_constant_override("outline_size", 5)
	_splash_label.size = Vector2(360.0, 32.0)
	_splash_label.pivot_offset = _splash_label.size * 0.5
	_splash_label.rotation = -0.26
	ui_root.add_child(_splash_label)
	
	var splash_tw := create_tween().set_loops()
	splash_tw.tween_property(_splash_label, "scale", Vector2(1.07, 1.07), 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	splash_tw.tween_property(_splash_label, "scale", Vector2(0.96, 0.96), 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
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
	
	_layout_menu_ui()

func _layout_menu_ui() -> void:
	if not menu_hud:
		return
	var ui_root: Control = menu_hud.get_node_or_null("center")
	if not ui_root:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1920.0, 1080.0)
	
	var cx: float = vp_size.x * 0.5
	var logo_w: float = minf(756.0, vp_size.x * 0.84)
	var logo_h: float = logo_w * (54.0 / 126.0)
	var logo_y: float = clampf(vp_size.y * 0.042, 24.0, 56.0)
	if _logo_rect and is_instance_valid(_logo_rect):
		_logo_rect.size = Vector2(logo_w, logo_h)
		_logo_rect.position = Vector2(cx - logo_w * 0.5, logo_y)
	
	if _splash_label and is_instance_valid(_splash_label):
		var splash_x: float = minf(cx + logo_w * 0.22, vp_size.x - _splash_label.size.x * 0.88)
		var splash_y: float = logo_y + logo_h * 0.56
		_splash_label.position = Vector2(splash_x, splash_y)
	
	var vbox: VBoxContainer = ui_root.get_node_or_null("vbox")
	if vbox:
		var btn_w: float = minf(340.0, vp_size.x - 48.0)
		for btn in [start_button, settings_button]:
			if btn:
				btn.custom_minimum_size = Vector2(btn_w, 66.0)
		vbox.size = Vector2(btn_w, 160.0)
		vbox.position = Vector2(cx - btn_w * 0.5, clampf(vp_size.y * 0.64, 420.0, vp_size.y - 210.0))
		vbox.add_theme_constant_override("separation", 18)

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
		walk_tween.parallel().tween_property(camera, "zoom", _get_effective_game_zoom(), walk_duration)\
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
