extends Node2D

@onready var difficulty_button: Button = $ui/difficulty_button
@onready var difficulty_info: Label = get_node_or_null("ui/difficulty_info")

func _ready() -> void:
	_update_difficulty_ui()

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
