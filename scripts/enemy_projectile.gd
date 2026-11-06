extends Area2D

enum ProjectileType {
	NECRO_BOLT = 0,
	FIREBALL = 1
}

@export var projectile_type: ProjectileType = ProjectileType.NECRO_BOLT
@export var speed: float = 115.0
@export var damage: int = 12
@export var lifetime: float = 3.0
@export var homing_strength: float = 0.0

var direction: Vector2 = Vector2.DOWN
var shooter: Node2D = null
var target: Node2D = null
var elapsed: float = 0.0
var is_impacted: bool = false

@onready var sprite: Sprite2D = $Sprite2D

const TEX_NECRO = preload("res://assets/sprites/projectile_necro.png")
const TEX_FIRE = preload("res://assets/sprites/projectile_fire.png")

func _ready() -> void:
	_apply_visuals()
	target = get_tree().get_first_node_in_group("player")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(dir: Vector2, p_type: ProjectileType, spd: float, dmg: int, homing: float = 0.0, from_shooter: Node2D = null) -> void:
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	projectile_type = p_type
	speed = spd
	damage = dmg
	homing_strength = homing
	shooter = from_shooter
	rotation = direction.angle()
	if is_node_ready():
		_apply_visuals()

func _apply_visuals() -> void:
	if not sprite:
		sprite = get_node_or_null("Sprite2D")
	if not sprite:
		return
	if projectile_type == ProjectileType.NECRO_BOLT:
		sprite.texture = TEX_NECRO
	else:
		sprite.texture = TEX_FIRE

func _physics_process(delta: float) -> void:
	if is_impacted:
		return
	
	elapsed += delta
	if elapsed >= lifetime:
		_impact_and_destroy()
		return
	
	if homing_strength > 0.0 and target and is_instance_valid(target):
		var desired = global_position.direction_to(target.global_position)
		direction = direction.lerp(desired, homing_strength * delta).normalized()
	
	global_position += direction * speed * delta
	
	if sprite:
		if projectile_type == ProjectileType.NECRO_BOLT:
			sprite.rotation += delta * 8.0
		else:
			rotation = direction.angle()
		var pulse = 1.0 + sin(elapsed * 18.0) * 0.12
		sprite.scale = Vector2(pulse, pulse)

func _on_body_entered(body: Node2D) -> void:
	if is_impacted or body == shooter:
		return
	if body.is_in_group("enemies"):
		return
	
	if body.is_in_group("player") or body.name == "player":
		if body.has_method("take_damage"):
			body.take_damage(damage, shooter)
		_impact_and_destroy()
	elif body is StaticBody2D or body is TileMapLayer:
		_impact_and_destroy()

func _on_area_entered(area: Area2D) -> void:
	if is_impacted:
		return
	if area.name == "attack_area_player" or area.name == "block_area_player":
		# Player slashed or blocked the spell projectile out of the air
		_impact_and_destroy(true)

func _impact_and_destroy(deflected: bool = false) -> void:
	if is_impacted:
		return
	is_impacted = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	if sprite:
		var tw = create_tween()
		tw.set_parallel(true)
		if deflected:
			sprite.modulate = Color(2.4, 2.2, 0.8)
			tw.tween_property(sprite, "scale", Vector2(1.8, 1.8), 0.14)
		else:
			sprite.modulate = Color(2.0, 1.6, 1.6)
			tw.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.12)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.14)
		tw.chain().tween_callback(queue_free)
	else:
		queue_free()
