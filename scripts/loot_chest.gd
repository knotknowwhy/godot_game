extends StaticBody2D

signal chest_opened(upgrade_id: int)

@export var upgrade_id: int = 0
var is_opened: bool = false
var elapsed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var interact_area: Area2D = $interact_area

const RELIC_PICKUP_SCENE = preload("res://scenes/relic_pickup.tscn")

func _ready() -> void:
	if sprite:
		sprite.frame = 0
	
	# Spawn pop-in animation
	scale = Vector2(0.15, 0.15)
	modulate = Color(2.5, 2.1, 0.6)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color.WHITE, 0.4)
	
	if interact_area:
		interact_area.body_entered.connect(_on_body_entered)
		interact_area.area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_opened:
		return
	elapsed += delta
	if sprite:
		var glow = 1.0 + (sin(elapsed * 4.5) * 0.5 + 0.5) * 0.35
		sprite.modulate = Color(glow, glow, 1.0)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= 32.0:
			_open_chest()

func _on_body_entered(body: Node2D) -> void:
	if is_opened:
		return
	if body.is_in_group("player") or body.name == "player":
		_open_chest()

func _on_area_entered(area: Area2D) -> void:
	if is_opened:
		return
	if area.name == "attack_area_player":
		_open_chest()

func _open_chest() -> void:
	if is_opened:
		return
	is_opened = true
	
	if sprite:
		sprite.frame = 1
		sprite.modulate = Color(2.6, 2.2, 0.7)
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(sprite, "scale", Vector2(1.3, 0.8), 0.08)
		tw.chain().set_parallel(true)
		tw.tween_property(sprite, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.35)
	
	# Spawn relic reward that pops out and drops on the floor nearby
	if RELIC_PICKUP_SCENE and get_parent():
		var relic = RELIC_PICKUP_SCENE.instantiate()
		relic.global_position = global_position + Vector2(0, 4)
		relic.upgrade_id = upgrade_id
		relic.chest_source = self
		get_parent().add_child(relic)
		var drop_dir = Vector2(randf_range(-14, 14), randf_range(18, 26))
		relic.pop_out_drop(drop_dir)
	
	chest_opened.emit(upgrade_id)

func on_relic_claimed() -> void:
	# Fade away in a couple of seconds after user claims the relic
	get_tree().create_timer(2.0).timeout.connect(func():
		if not is_instance_valid(self):
			return
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		var ftw = create_tween()
		ftw.tween_property(self, "modulate:a", 0.0, 0.75)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
		ftw.tween_callback(queue_free)
	)
