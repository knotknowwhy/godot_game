extends Area2D

signal relic_collected(upgrade_id: int)

@export var upgrade_id: int = 0
var chest_source: Node2D = null

var is_collected: bool = false
var can_collect: bool = false
var bob_time: float = 0.0
var base_sprite_y: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var halo_sprite: Sprite2D = $HaloSprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const TEX_HEART = preload("res://assets/sprites/relic_titan_heart.png")
const TEX_SWORD = preload("res://assets/sprites/relic_broadsword.png")
const TEX_BOOTS = preload("res://assets/sprites/relic_greaves.png")
const TEX_SOUL = preload("res://assets/sprites/relic_soulblade.png")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Player layer
	
	_apply_texture()
	base_sprite_y = sprite.position.y
	bob_time = randf_range(0.0, TAU)
	
	body_entered.connect(_on_body_entered)

func _apply_texture() -> void:
	if not sprite:
		sprite = $Sprite2D
	match upgrade_id:
		0:
			sprite.texture = TEX_HEART
			if halo_sprite:
				halo_sprite.modulate = Color(1.0, 0.35, 0.45, 0.55)
		1:
			sprite.texture = TEX_SWORD
			if halo_sprite:
				halo_sprite.modulate = Color(1.0, 0.88, 0.35, 0.55)
		2:
			sprite.texture = TEX_BOOTS
			if halo_sprite:
				halo_sprite.modulate = Color(0.35, 0.95, 1.0, 0.55)
		_:
			sprite.texture = TEX_SOUL
			if halo_sprite:
				halo_sprite.modulate = Color(1.0, 0.4, 0.85, 0.55)

func pop_out_drop(drop_offset: Vector2) -> void:
	can_collect = false
	var start_pos = global_position
	var end_pos = start_pos + drop_offset
	
	scale = Vector2(0.2, 0.2)
	modulate = Color(2.5, 2.2, 0.8)
	
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position:x", end_pos.x, 0.42)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.42)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color.WHITE, 0.42)
	
	var y_tw = create_tween()
	y_tw.tween_property(self, "global_position:y", start_pos.y - 18.0, 0.20)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	y_tw.tween_property(self, "global_position:y", end_pos.y, 0.22)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	# Gentle landing bounce
	y_tw.tween_property(self, "global_position:y", end_pos.y - 5.0, 0.08)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	y_tw.tween_property(self, "global_position:y", end_pos.y, 0.08)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	
	# Delay before pickup is allowed
	tw.chain().tween_callback(func():
		can_collect = true
		for b in get_overlapping_bodies():
			if b.is_in_group("player") or b.name == "player":
				_collect(b)
				break
	)

func _physics_process(delta: float) -> void:
	if is_collected:
		return
	
	bob_time += delta * 4.5
	if sprite:
		sprite.position.y = base_sprite_y + sin(bob_time) * 2.2
	if halo_sprite:
		var pulse = 0.85 + (sin(bob_time * 1.5) * 0.5 + 0.5) * 0.4
		halo_sprite.scale = Vector2(pulse, pulse)
		halo_sprite.modulate.a = 0.45 + (sin(bob_time * 1.5) * 0.5 + 0.5) * 0.35

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
	
	var info := {"title": "PERMANENT UPGRADE!", "color": Color(1.0, 0.88, 0.3)}
	if player and player.has_method("apply_permanent_upgrade"):
		info = player.apply_permanent_upgrade(upgrade_id)
	
	if FLOATING_TEXT_SCENE and get_parent():
		var ft = FLOATING_TEXT_SCENE.instantiate()
		ft.global_position = global_position + Vector2(0, -14)
		get_parent().add_child(ft)
		ft.spawn(info["title"], info["color"], 11, 24.0, 1.8)
	
	if chest_source and is_instance_valid(chest_source) and chest_source.has_method("on_relic_claimed"):
		chest_source.on_relic_claimed()
	
	relic_collected.emit(upgrade_id)
	
	# Collect burst animation
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.16)
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(queue_free)
