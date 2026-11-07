class_name ControlsHint
extends Control

@export_enum("Bottom Left", "Bottom Right", "Top Right") var corner_placement: int = 0
@export var margin_offset: Vector2 = Vector2(24, 24)
@export var enable_toggle: bool = true
@export var toggle_key: Key = KEY_H

@onready var panel: PanelContainer = $panel
@onready var row_move: HBoxContainer = $panel/margin/vbox/row_move
@onready var row_dodge: HBoxContainer = $panel/margin/vbox/row_dodge
@onready var row_attack: HBoxContainer = $panel/margin/vbox/row_attack
@onready var row_block: HBoxContainer = $panel/margin/vbox/row_block

@onready var icon_move: TextureRect = $panel/margin/vbox/row_move/icon_box/icon
@onready var icon_dodge: TextureRect = $panel/margin/vbox/row_dodge/icon_box/icon
@onready var icon_attack: TextureRect = $panel/margin/vbox/row_attack/icon_box/icon
@onready var icon_block: TextureRect = $panel/margin/vbox/row_block/icon_box/icon

var is_hidden: bool = false
var fade_tween: Tween = null

const NORMAL_MODULATE := Color(1.0, 1.0, 1.0, 0.92)
const ACTIVE_MODULATE := Color(1.4, 1.4, 1.5, 1.0)
const ACCENT_GOLD := Color(1.4, 1.15, 0.5, 1.0)
const ACCENT_CYAN := Color(0.6, 1.25, 1.5, 1.0)
const ACCENT_GREEN := Color(0.6, 1.35, 0.85, 1.0)

func _ready() -> void:
	_apply_corner_anchors()
	# Subtle introductory fade-in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

func _apply_corner_anchors() -> void:
	# 0: Bottom Left, 1: Bottom Right, 2: Top Right
	match corner_placement:
		0: # Bottom Left
			set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			grow_horizontal = Control.GROW_DIRECTION_END
			grow_vertical = Control.GROW_DIRECTION_BEGIN
			position = Vector2(margin_offset.x, -margin_offset.y - size.y)
		1: # Bottom Right
			set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			grow_horizontal = Control.GROW_DIRECTION_BEGIN
			grow_vertical = Control.GROW_DIRECTION_BEGIN
			position = Vector2(-margin_offset.x - size.x, -margin_offset.y - size.y)
		2: # Top Right
			set_anchors_preset(Control.PRESET_TOP_RIGHT)
			grow_horizontal = Control.GROW_DIRECTION_BEGIN
			grow_vertical = Control.GROW_DIRECTION_END
			position = Vector2(-margin_offset.x - size.x, margin_offset.y)

func _unhandled_input(event: InputEvent) -> void:
	if enable_toggle and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == toggle_key:
			_toggle_visibility()

func _toggle_visibility() -> void:
	is_hidden = !is_hidden
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	var target_alpha = 0.0 if is_hidden else 1.0
	fade_tween.tween_property(self, "modulate:a", target_alpha, 0.25).set_trans(Tween.TRANS_QUAD)

func _process(_delta: float) -> void:
	if is_hidden:
		return
	_update_input_highlights()

func _update_input_highlights() -> void:
	# WASD Movement
	var is_moving := (
		Input.is_action_pressed("Left") or 
		Input.is_action_pressed("Right") or 
		Input.is_action_pressed("Up") or 
		Input.is_action_pressed("Down")
	)
	_animate_highlight(icon_move, is_moving, ACTIVE_MODULATE)
	
	# Shift / Space Dodge
	var is_dodging := Input.is_action_pressed("Dodge")
	_animate_highlight(icon_dodge, is_dodging, ACCENT_GREEN)
	
	# LMB Attack
	var is_attacking := Input.is_action_pressed("Attack_sword")
	_animate_highlight(icon_attack, is_attacking, ACCENT_GOLD)
	
	# RMB Block
	var is_blocking := Input.is_action_pressed("Block_sword")
	_animate_highlight(icon_block, is_blocking, ACCENT_CYAN)

func _animate_highlight(target: TextureRect, active: bool, active_color: Color) -> void:
	if not target:
		return
	var dest_color = active_color if active else NORMAL_MODULATE
	var dest_scale = Vector2(1.08, 1.08) if active else Vector2(1.0, 1.0)
	target.modulate = target.modulate.lerp(dest_color, 0.28)
	target.scale = target.scale.lerp(dest_scale, 0.28)
