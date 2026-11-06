extends Area2D

signal chest_opened(upgrade_id: int)

@export var upgrade_id: int = 0
var is_opened: bool = false
var elapsed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

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
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_opened:
		return
	elapsed += delta
	if sprite:
		var glow = 1.0 + (sin(elapsed * 4.5) * 0.5 + 0.5) * 0.35
		sprite.modulate = Color(glow, glow, 1.0)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		if global_position.distance_to(player.global_position) <= 22.0:
			_open_chest(player)

func _on_body_entered(body: Node2D) -> void:
	if is_opened:
		return
	if body.is_in_group("player") or body.name == "player":
		_open_chest(body)

func _on_area_entered(area: Area2D) -> void:
	if is_opened:
		return
	if area.name == "attack_area_player":
		var player = get_tree().get_first_node_in_group("player")
		if player:
			_open_chest(player)

func _open_chest(player: Node2D) -> void:
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
	
	var info := {"title": "PERMANENT UPGRADE!", "color": Color(1.0, 0.88, 0.3)}
	if player and player.has_method("apply_permanent_upgrade"):
		info = player.apply_permanent_upgrade(upgrade_id)
	
	if FLOATING_TEXT_SCENE and get_parent():
		var ft = FLOATING_TEXT_SCENE.instantiate()
		ft.global_position = global_position + Vector2(0, -16)
		get_parent().add_child(ft)
		ft.spawn(info["title"], info["color"], 11, 24.0, 1.6)
	
	chest_opened.emit(upgrade_id)
