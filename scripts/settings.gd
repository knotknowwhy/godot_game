extends Node2D

const MENU_FONT = preload("res://assets/fonts/PressStart2P-Regular.ttf")

@onready var title_label: Label = get_node_or_null("ui/title_label")
@onready var difficulty_button: Button = $ui/difficulty_button
@onready var difficulty_info: Label = get_node_or_null("ui/difficulty_info")
@onready var back_button: Button = get_node_or_null("ui/back_button")

func _ready() -> void:
	_style_settings_ui()
	_update_difficulty_ui()
	_layout_settings_ui()
	if get_viewport() and not get_viewport().size_changed.is_connected(_layout_settings_ui):
		get_viewport().size_changed.connect(_layout_settings_ui)

func _style_settings_ui() -> void:
	if title_label:
		title_label.add_theme_font_override("font", MENU_FONT)
		title_label.add_theme_font_size_override("font_size", 32)
		title_label.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1.0))
		title_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 1.0))
		title_label.add_theme_constant_override("outline_size", 6)
	
	if difficulty_info:
		difficulty_info.add_theme_font_override("font", MENU_FONT)
		difficulty_info.add_theme_font_size_override("font_size", 14)
		difficulty_info.add_theme_color_override("font_color", Color(0.82, 0.84, 0.90, 1.0))
		difficulty_info.add_theme_constant_override("line_spacing", 10)
	
	for btn in [difficulty_button, back_button]:
		if not btn:
			continue
		btn.add_theme_font_override("font", MENU_FONT)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.7, 1.0))
		btn.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.08, 1.0))
		btn.add_theme_constant_override("outline_size", 4)
		btn.add_theme_stylebox_override("normal", _make_stone_style(Color(0.32, 0.33, 0.37, 0.94), Color(0.56, 0.58, 0.64, 1.0)))
		btn.add_theme_stylebox_override("hover", _make_stone_style(Color(0.38, 0.40, 0.48, 0.98), Color(0.76, 0.78, 0.84, 1.0)))
		btn.add_theme_stylebox_override("pressed", _make_stone_style(Color(0.22, 0.23, 0.27, 0.98), Color(0.42, 0.44, 0.50, 1.0)))
		btn.add_theme_stylebox_override("focus", _make_stone_style(Color(0.36, 0.38, 0.45, 0.96), Color(0.85, 0.78, 0.42, 1.0)))

func _make_stone_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.border_width_bottom = 5
	sb.set_corner_radius_all(2)
	return sb

func _layout_settings_ui() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1920.0, 1080.0)
	var cx: float = vp_size.x * 0.5
	var cy: float = vp_size.y * 0.5
	
	if title_label:
		title_label.size = Vector2(minf(520.0, vp_size.x - 40.0), 80.0)
		title_label.position = Vector2(cx - title_label.size.x * 0.5, cy - 290.0)
	if difficulty_button:
		difficulty_button.size = Vector2(minf(420.0, vp_size.x - 48.0), 76.0)
		difficulty_button.position = Vector2(cx - difficulty_button.size.x * 0.5, cy - 110.0)
	if difficulty_info:
		difficulty_info.size = Vector2(minf(680.0, vp_size.x - 32.0), 90.0)
		difficulty_info.position = Vector2(cx - difficulty_info.size.x * 0.5, cy - 10.0)
	if back_button:
		back_button.size = Vector2(minf(280.0, vp_size.x - 64.0), 70.0)
		back_button.position = Vector2(cx - back_button.size.x * 0.5, cy + 165.0)

func _on_difficulty_button_pressed() -> void:
	GameSettings.cycle_difficulty()
	_update_difficulty_ui()

func _update_difficulty_ui() -> void:
	var diff_name := GameSettings.get_difficulty_name()
	if difficulty_button:
		difficulty_button.text = "Difficulty: " + diff_name
	
	if difficulty_info:
		match GameSettings.current_difficulty:
			GameSettings.Difficulty.EASY:
				difficulty_info.text = "Player HP: x1.2 | Player DMG: x1.3\nEnemy HP: x0.8 | Enemy DMG: x0.7"
			GameSettings.Difficulty.MEDIUM:
				difficulty_info.text = "Player HP: x1.0 | Player DMG: x1.0\nEnemy HP: x1.0 | Enemy DMG: x1.0"
			GameSettings.Difficulty.HARD:
				difficulty_info.text = "Player HP: x0.8 | Player DMG: x0.8\nEnemy HP: x2.0 | Enemy DMG: x1.5"

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
