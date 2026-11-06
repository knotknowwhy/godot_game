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

const MAGNETIC_RADIUS: float = 42.0
var magnet_speed: float = 75.0
var player_ref: Node2D = null
var bob_time: float = 0.0
var base_sprite_y: float = 0.0
var is_collected: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Detect player layer
	
	_update_texture()
	base_sprite_y = sprite.position.y
	bob_time = randf_range(0.0, TAU)
	
	# Spawn pop-in flare
	scale = Vector2(0.2, 0.2)
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	
	body_entered.connect(_on_body_entered)
	_find_player()

func _find_player() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")

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
	
	bob_time += delta * 4.0
	sprite.position.y = base_sprite_y + sin(bob_time) * 1.8
	
	_find_player()
	if player_ref and is_instance_valid(player_ref):
		var dist = global_position.distance_to(player_ref.global_position)
		if dist <= MAGNETIC_RADIUS:
			# Magnetic pull accelerating toward player
			magnet_speed = minf(magnet_speed + delta * 350.0, 260.0)
			global_position = global_position.move_toward(player_ref.global_position, magnet_speed * delta)

func _on_body_entered(body: Node2D) -> void:
	if is_collected:
		return
	if body.is_in_group("player") or body.name == "player":
		_collect(body)

func _collect(player: Node2D) -> void:
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
	if FLOATING_TEXT_SCENE:
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
