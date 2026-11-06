extends Area2D

enum Type {
	HEALTH,
	SPEED,
	POWER
}

@export var pickup_type: Type = Type.HEALTH
@export var heal_amount: int = 25
@export var speed_boost_duration: float = 6.0
@export var speed_boost_multiplier: float = 1.38
@export var damage_boost_duration: float = 7.0
@export var damage_boost_multiplier: float = 1.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const TEX_HEALTH = preload("res://assets/sprites/pickup_health.png")
const TEX_SPEED = preload("res://assets/sprites/pickup_speed.png")
const TEX_POWER = preload("res://assets/sprites/pickup_power.png")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var bob_time: float = 0.0
var base_sprite_y: float = 0.0
var is_collected: bool = false
var can_collect: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Detect player layer
	
	_update_texture()
	base_sprite_y = sprite.position.y
	bob_time = randf_range(0.0, TAU)
	
	body_entered.connect(_on_body_entered)
	
	# Pop out and drop onto the floor nearby
	pop_out_drop(Vector2(randf_range(-14, 14), randf_range(6, 16)))

func pop_out_drop(drop_offset: Vector2) -> void:
	can_collect = false
	var start_pos = global_position
	var end_pos = start_pos + drop_offset
	
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.8
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position:x", end_pos.x, 0.35)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	
	var y_tw = create_tween()
	y_tw.tween_property(self, "global_position:y", start_pos.y - 12.0, 0.16)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	y_tw.tween_property(self, "global_position:y", end_pos.y, 0.19)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	# Subtle bounce on landing
	y_tw.tween_property(self, "global_position:y", end_pos.y - 4.0, 0.07)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	y_tw.tween_property(self, "global_position:y", end_pos.y, 0.07)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	
	# Only allow collection after landing
	tw.chain().tween_callback(func():
		can_collect = true
		for b in get_overlapping_bodies():
			if b.is_in_group("player") or b.name == "player":
				_collect(b)
				break
	)

func _update_texture() -> void:
	if not sprite:
		sprite = $Sprite2D
	match pickup_type:
		Type.HEALTH:
			sprite.texture = TEX_HEALTH
			modulate = Color(1.1, 1.0, 1.0)
		Type.SPEED:
			sprite.texture = TEX_SPEED
			modulate = Color(1.0, 1.15, 1.25)
		Type.POWER:
			sprite.texture = TEX_POWER
			modulate = Color(1.25, 1.15, 1.0)

func _physics_process(delta: float) -> void:
	if is_collected:
		return
	
	# Gentle floating bob on the floor
	bob_time += delta * 4.0
	if sprite:
		sprite.position.y = base_sprite_y + sin(bob_time) * 1.8

func _on_body_entered(body: Node2D) -> void:
	if not can_collect or is_collected:
		return
	if body.is_in_group("player") or body.name == "player":
		_collect(body)

func _collect(player: Node2D) -> void:
	if is_collected:
		return
	is_collected = true
	collision_shape.set_deferred("disabled", true)
	
	var text_msg = ""
	var text_col = Color.WHITE
	
	match pickup_type:
		Type.HEALTH:
			if player.has_method("heal"):
				player.heal(heal_amount, true)
			text_msg = "+%d HP" % heal_amount
			text_col = Color(0.35, 1.0, 0.45)
		Type.SPEED:
			if player.has_method("apply_speed_boost"):
				player.apply_speed_boost(speed_boost_duration, speed_boost_multiplier)
			text_msg = "+SPEED!"
			text_col = Color(0.25, 0.9, 1.0)
		Type.POWER:
			if player.has_method("apply_damage_boost"):
				player.apply_damage_boost(damage_boost_duration, damage_boost_multiplier)
			text_msg = "+POWER!"
			text_col = Color(1.0, 0.85, 0.25)
			
	# Spawn floating pickup label
	if FLOATING_TEXT_SCENE and get_parent():
		var ft = FLOATING_TEXT_SCENE.instantiate()
		ft.global_position = global_position + Vector2(0, -6)
		get_parent().add_child(ft)
		ft.spawn(text_msg, text_col, 10, 16.0, 0.55)
	
	# Quick collection flash and shrink
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.12)
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(queue_free)
