class_name GameSettings
extends RefCounted

enum Difficulty {
	EASY = 0,
	MEDIUM = 1,
	HARD = 2
}

static var current_difficulty: Difficulty = Difficulty.MEDIUM

static func set_difficulty(diff: Difficulty) -> void:
	current_difficulty = diff

static func cycle_difficulty() -> Difficulty:
	current_difficulty = ((int(current_difficulty) + 1) % 3) as Difficulty
	return current_difficulty

static func get_difficulty_name() -> String:
	match current_difficulty:
		Difficulty.EASY:
			return "Easy"
		Difficulty.MEDIUM:
			return "Medium"
		Difficulty.HARD:
			return "Hard"
	return "Medium"

static func get_player_health_multiplier() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 1.2
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 0.8
	return 1.0

static func get_player_damage_multiplier() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 1.3
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 0.8
	return 1.0

static func get_enemy_health_multiplier() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 0.8
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 2.0
	return 1.0

static func get_enemy_damage_multiplier() -> float:
	match current_difficulty:
		Difficulty.EASY:
			return 0.7
		Difficulty.MEDIUM:
			return 1.0
		Difficulty.HARD:
			return 1.5
	return 1.0
