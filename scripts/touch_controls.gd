class_name TouchControls
extends Control

const DEADZONE: float = 0.22
const FONT_RES = preload("res://assets/fonts/PressStart2P-Regular.ttf")

var touch_enabled: bool = false
var _joy_touch_id: int = -1
var _joy_base_default: Vector2 = Vector2(170.0, 900.0)
var _joy_base_pos: Vector2 = Vector2(170.0, 900.0)
var _joy_knob_pos: Vector2 = Vector2(170.0, 900.0)
var _joy_radius: float = 82.0
var _joy_knob_radius: float = 34.0
var _ui_scale: float = 1.0

# Right-hand action buttons: id -> dictionary
var _buttons: Dictionary = {
	"attack": {
		"action": "Attack_sword",
		"label": "ATK",
		"pos": Vector2.ZERO,
		"radius": 68.0,
		"touch_id": -1,
		"pressed": false,
		"rim": Color(0.76, 0.22, 0.18, 0.92),
		"fill": Color(0.14, 0.08, 0.09, 0.78),
		"fill_active": Color(0.42, 0.13, 0.12, 0.92),
	},
	"dash": {
		"action": "Dodge",
		"label": "DASH",
		"pos": Vector2.ZERO,
		"radius": 52.0,
		"touch_id": -1,
		"pressed": false,
		"rim": Color(0.82, 0.68, 0.24, 0.92),
		"fill": Color(0.13, 0.11, 0.08, 0.78),
		"fill_active": Color(0.38, 0.31, 0.12, 0.92),
	},
	"block": {
		"action": "Block_sword",
		"label": "BLK",
		"pos": Vector2.ZERO,
		"radius": 52.0,
		"touch_id": -1,
		"pressed": false,
		"rim": Color(0.42, 0.60, 0.78, 0.92),
		"fill": Color(0.08, 0.11, 0.15, 0.78),
		"fill_active": Color(0.18, 0.28, 0.40, 0.92),
	},
}

var _move_actions_state: Dictionary = {
	"Left": false,
	"Right": false,
	"Up": false,
	"Down": false,
}

func _ready() -> void:
	name = "touch_controls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios")
	visible = touch_enabled
	
	_recalculate_layout()
	if get_viewport() and not get_viewport().size_changed.is_connected(_recalculate_layout):
		get_viewport().size_changed.connect(_recalculate_layout)
	
	if touch_enabled:
		_hide_keyboard_hints()

func _exit_tree() -> void:
	release_all_inputs()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all_inputs()

func _hide_keyboard_hints() -> void:
	var parent_hud := get_parent()
	if not parent_hud:
		return
	var hint := parent_hud.get_node_or_null("controls_hint")
	if hint:
		hint.visible = false

func _recalculate_layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1920.0, 1080.0)
	
	_ui_scale = clampf(minf(vp_size.x / 1600.0, vp_size.y / 900.0), 0.72, 1.15)
	_joy_radius = 84.0 * _ui_scale
	_joy_knob_radius = 35.0 * _ui_scale
	
	var margin_x: float = maxf(145.0 * _ui_scale, vp_size.x * 0.10)
	var margin_y: float = maxf(145.0 * _ui_scale, vp_size.y * 0.16)
	_joy_base_default = Vector2(margin_x, vp_size.y - margin_y)
	if _joy_touch_id == -1:
		_joy_base_pos = _joy_base_default
		_joy_knob_pos = _joy_base_default
	
	var atk_r: float = 68.0 * _ui_scale
	var sub_r: float = 52.0 * _ui_scale
	_buttons["attack"]["radius"] = atk_r
	_buttons["dash"]["radius"] = sub_r
	_buttons["block"]["radius"] = sub_r
	
	var atk_pos := Vector2(vp_size.x - maxf(138.0 * _ui_scale, vp_size.x * 0.085), vp_size.y - maxf(132.0 * _ui_scale, vp_size.y * 0.145))
	_buttons["attack"]["pos"] = atk_pos
	_buttons["dash"]["pos"] = atk_pos + Vector2(-152.0 * _ui_scale, 18.0 * _ui_scale)
	_buttons["block"]["pos"] = atk_pos + Vector2(-16.0 * _ui_scale, -148.0 * _ui_scale)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	
	if not touch_enabled:
		touch_enabled = true
		visible = true
		_recalculate_layout()
		_hide_keyboard_hints()
	
	if not is_visible_in_tree() or modulate.a <= 0.05:
		return
	
	var vp_size: Vector2 = get_viewport_rect().size
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var pos: Vector2 = _canvas_pos(st.position)
		if st.pressed:
			# 1. Check right-side action buttons first (with generous 1.25x hit radius per WCAG touch target guidelines)
			for b_key in _buttons.keys():
				var btn: Dictionary = _buttons[b_key]
				var hit_r: float = float(btn["radius"]) * 1.24
				if pos.distance_to(btn["pos"]) <= hit_r and int(btn["touch_id"]) == -1:
					btn["touch_id"] = st.index
					btn["pressed"] = true
					Input.action_press(btn["action"])
					queue_redraw()
					return
			
			# 2. Check left half of screen for virtual joystick
			if _joy_touch_id == -1 and pos.x <= vp_size.x * 0.48 and pos.y >= vp_size.y * 0.25:
				_joy_touch_id = st.index
				_joy_base_pos = Vector2(
					clampf(pos.x, _joy_radius + 24.0, vp_size.x * 0.42),
					clampf(pos.y, vp_size.y * 0.35, vp_size.y - _joy_radius - 24.0)
				)
				_update_joystick(pos)
				queue_redraw()
		else:
			# Touch released
			if st.index == _joy_touch_id:
				_reset_joystick()
				queue_redraw()
				return
			for b_key in _buttons.keys():
				var btn: Dictionary = _buttons[b_key]
				if int(btn["touch_id"]) == st.index:
					btn["touch_id"] = -1
					btn["pressed"] = false
					Input.action_release(btn["action"])
					queue_redraw()
					return
	
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_touch_id:
			var pos: Vector2 = _canvas_pos(sd.position)
			_update_joystick(pos)
			queue_redraw()

func _canvas_pos(raw_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if not vp:
		return raw_pos
	return vp.get_canvas_transform().affine_inverse() * raw_pos

func _update_joystick(touch_pos: Vector2) -> void:
	var delta: Vector2 = touch_pos - _joy_base_pos
	var dist: float = delta.length()
	if dist > _joy_radius:
		delta = (delta / dist) * _joy_radius
	_joy_knob_pos = _joy_base_pos + delta
	
	var norm: Vector2 = delta / maxf(1.0, _joy_radius)
	if norm.length() < DEADZONE:
		_set_move_action("Left", false, 0.0)
		_set_move_action("Right", false, 0.0)
		_set_move_action("Up", false, 0.0)
		_set_move_action("Down", false, 0.0)
		return
	
	_set_move_action("Right", norm.x > DEADZONE, absf(norm.x))
	_set_move_action("Left", norm.x < -DEADZONE, absf(norm.x))
	_set_move_action("Down", norm.y > DEADZONE, absf(norm.y))
	_set_move_action("Up", norm.y < -DEADZONE, absf(norm.y))

func _set_move_action(action: String, active: bool, strength: float) -> void:
	var prev: bool = bool(_move_actions_state.get(action, false))
	if active:
		Input.action_press(action, clampf(strength, 0.4, 1.0))
		_move_actions_state[action] = true
	elif prev:
		Input.action_release(action)
		_move_actions_state[action] = false

func _reset_joystick() -> void:
	_joy_touch_id = -1
	_joy_base_pos = _joy_base_default
	_joy_knob_pos = _joy_base_default
	for act in ["Left", "Right", "Up", "Down"]:
		_set_move_action(act, false, 0.0)

func release_all_inputs() -> void:
	_reset_joystick()
	for b_key in _buttons.keys():
		var btn: Dictionary = _buttons[b_key]
		if bool(btn["pressed"]) or int(btn["touch_id"]) != -1:
			btn["touch_id"] = -1
			btn["pressed"] = false
			Input.action_release(btn["action"])
	queue_redraw()

func _draw() -> void:
	if not touch_enabled:
		return
	
	# 1. Draw Left Virtual Joystick
	var joy_active: bool = (_joy_touch_id != -1)
	var base_fill := Color(0.06, 0.06, 0.09, 0.72 if joy_active else 0.52)
	var base_rim := Color(0.76, 0.64, 0.24, 0.85) if joy_active else Color(0.32, 0.33, 0.40, 0.68)
	draw_circle(_joy_base_pos, _joy_radius, base_fill)
	draw_arc(_joy_base_pos, _joy_radius, 0.0, TAU, 48, base_rim, 2.5, true)
	draw_arc(_joy_base_pos, _joy_radius * DEADZONE, 0.0, TAU, 24, Color(0.28, 0.29, 0.35, 0.38), 1.5, true)
	
	# Cardinal directional ticks on joystick ring
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var p0: Vector2 = _joy_base_pos + dir * (_joy_radius - 10.0 * _ui_scale)
		var p1: Vector2 = _joy_base_pos + dir * (_joy_radius - 3.0 * _ui_scale)
		draw_line(p0, p1, base_rim, 2.0)
	
	if joy_active and _joy_base_pos.distance_to(_joy_knob_pos) > 2.0:
		draw_line(_joy_base_pos, _joy_knob_pos, Color(0.84, 0.72, 0.30, 0.55), 3.0)
	
	var knob_fill := Color(0.84, 0.72, 0.28, 0.92) if joy_active else Color(0.22, 0.23, 0.29, 0.82)
	var knob_rim := Color(0.96, 0.90, 0.65, 0.95) if joy_active else Color(0.52, 0.54, 0.62, 0.85)
	draw_circle(_joy_knob_pos, _joy_knob_radius, knob_fill)
	draw_arc(_joy_knob_pos, _joy_knob_radius, 0.0, TAU, 32, knob_rim, 2.5, true)
	
	# 2. Draw Right Action Buttons
	for b_key in _buttons.keys():
		var btn: Dictionary = _buttons[b_key]
		var center: Vector2 = btn["pos"]
		var r: float = float(btn["radius"]) * (0.93 if bool(btn["pressed"]) else 1.0)
		var fill_col: Color = btn["fill_active"] if bool(btn["pressed"]) else btn["fill"]
		var rim_col: Color = btn["rim"]
		
		# Outer dark shadow ring + filled circle + crisp border
		draw_circle(center + Vector2(0, 3.0), r + 2.0, Color(0.02, 0.02, 0.04, 0.65))
		draw_circle(center, r, fill_col)
		draw_arc(center, r, 0.0, TAU, 40, rim_col, 3.0 if bool(btn["pressed"]) else 2.2, true)
		draw_arc(center, r - 5.0 * _ui_scale, 0.0, TAU, 36, Color(rim_col.r, rim_col.g, rim_col.b, 0.24), 1.2, true)
		
		# Draw crisp geometric weapon/action emblem
		var icon_center := center + Vector2(0.0, -7.0 * _ui_scale)
		var icon_col := Color(0.95, 0.94, 0.92, 0.96)
		if b_key == "attack":
			# Angled broadsword emblem
			var s := 18.0 * _ui_scale
			draw_line(icon_center + Vector2(-s * 0.75, s * 0.75), icon_center + Vector2(s * 0.85, -s * 0.85), icon_col, 3.6 * _ui_scale)
			draw_line(icon_center + Vector2(-s * 0.62, s * 0.12), icon_center + Vector2(-s * 0.12, s * 0.62), rim_col.lightened(0.25), 3.0 * _ui_scale)
		elif b_key == "dash":
			# Double forward chevron emblem
			var s := 11.0 * _ui_scale
			for ox in [-6.0 * _ui_scale, 5.0 * _ui_scale]:
				var c := icon_center + Vector2(ox, 0.0)
				draw_line(c + Vector2(-s * 0.5, -s * 0.7), c + Vector2(s * 0.45, 0.0), icon_col, 2.8 * _ui_scale)
				draw_line(c + Vector2(s * 0.45, 0.0), c + Vector2(-s * 0.5, s * 0.7), icon_col, 2.8 * _ui_scale)
		elif b_key == "block":
			# Heater shield outline emblem
			var s := 12.0 * _ui_scale
			var pts := PackedVector2Array([
				icon_center + Vector2(-s * 0.75, -s * 0.75),
				icon_center + Vector2(s * 0.75, -s * 0.75),
				icon_center + Vector2(s * 0.75, s * 0.05),
				icon_center + Vector2(0.0, s * 0.90),
				icon_center + Vector2(-s * 0.75, s * 0.05),
				icon_center + Vector2(-s * 0.75, -s * 0.75),
			])
			draw_polyline(pts, icon_col, 2.6 * _ui_scale)
		
		# Button label underneath icon
		if FONT_RES:
			var fsize: int = maxi(9, int(round(11.0 * _ui_scale)))
			var lbl: String = str(btn["label"])
			var tsize: Vector2 = FONT_RES.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
			var tpos := Vector2(center.x - tsize.x * 0.5, center.y + r * 0.56)
			draw_string_outline(FONT_RES, tpos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0.04, 0.04, 0.06, 0.95))
			draw_string(FONT_RES, tpos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.92, 0.92, 0.95, 0.95))
