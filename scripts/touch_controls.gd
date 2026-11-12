class_name TouchControls
extends Control

const DEADZONE: float = 0.18

var touch_enabled: bool = false
var _mouse_bindings_stripped: bool = false
var _joy_touch_id: int = -1
var _joy_base_default: Vector2 = Vector2(260.0, 830.0)
var _joy_base_pos: Vector2 = Vector2(260.0, 830.0)
var _joy_knob_pos: Vector2 = Vector2(260.0, 830.0)
var _joy_radius: float = 138.0
var _joy_knob_radius: float = 58.0
var _ui_scale: float = 1.0

var _buttons: Dictionary = {
	"attack": {
		"action": "Attack_sword",
		"pos": Vector2.ZERO,
		"radius": 108.0,
		"touch_id": -1,
		"pressed": false,
	},
	"dash": {
		"action": "Dodge",
		"pos": Vector2.ZERO,
		"radius": 80.0,
		"touch_id": -1,
		"pressed": false,
	},
	"block": {
		"action": "Block_sword",
		"pos": Vector2.ZERO,
		"radius": 80.0,
		"touch_id": -1,
		"pressed": false,
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
	
	var is_touch_device := DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if is_touch_device:
		_enable_touch_mode()
	else:
		visible = false
	
	_recalculate_layout()
	if get_viewport() and not get_viewport().size_changed.is_connected(_recalculate_layout):
		get_viewport().size_changed.connect(_recalculate_layout)

func _enable_touch_mode() -> void:
	touch_enabled = true
	visible = true
	if not _mouse_bindings_stripped:
		_mouse_bindings_stripped = true
		# Prevent emulate_mouse_from_touch from firing Attack_sword (LMB) or Block_sword (RMB) on every screen tap
		for action_name in ["Attack_sword", "Block_sword"]:
			if InputMap.has_action(action_name):
				var events := InputMap.action_get_events(action_name)
				for ev in events:
					if ev is InputEventMouseButton:
						InputMap.action_erase_event(action_name, ev)
		Input.action_release("Attack_sword")
		Input.action_release("Block_sword")
	_hide_keyboard_hints()
	_recalculate_layout()

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
	
	var short_side: float = minf(vp_size.x, vp_size.y)
	_ui_scale = clampf(short_side / 1080.0, 0.80, 1.25)
	
	_joy_radius = 140.0 * _ui_scale
	_joy_knob_radius = 58.0 * _ui_scale
	
	var joy_margin_x: float = maxf(250.0 * _ui_scale, vp_size.x * 0.14)
	var joy_margin_y: float = maxf(235.0 * _ui_scale, vp_size.y * 0.23)
	_joy_base_default = Vector2(joy_margin_x, vp_size.y - joy_margin_y)
	if _joy_touch_id == -1:
		_joy_base_pos = _joy_base_default
		_joy_knob_pos = _joy_base_default
	
	var atk_r: float = 108.0 * _ui_scale
	var sub_r: float = 80.0 * _ui_scale
	_buttons["attack"]["radius"] = atk_r
	_buttons["dash"]["radius"] = sub_r
	_buttons["block"]["radius"] = sub_r
	
	var atk_pos := Vector2(
		vp_size.x - maxf(220.0 * _ui_scale, vp_size.x * 0.12),
		vp_size.y - maxf(205.0 * _ui_scale, vp_size.y * 0.20)
	)
	_buttons["attack"]["pos"] = atk_pos
	_buttons["dash"]["pos"] = atk_pos + Vector2(-232.0 * _ui_scale, 28.0 * _ui_scale)
	_buttons["block"]["pos"] = atk_pos + Vector2(-32.0 * _ui_scale, -228.0 * _ui_scale)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	
	if not touch_enabled:
		_enable_touch_mode()
	
	if not is_visible_in_tree() or modulate.a <= 0.05:
		return
	
	var vp_size: Vector2 = get_viewport_rect().size
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var pos: Vector2 = _to_local_canvas_pos(st.position)
		if st.pressed:
			# 1. Check right-side action buttons first (with generous 1.2x hit padding)
			var best_key: String = ""
			var best_dist: float = INF
			for b_key in _buttons.keys():
				var btn: Dictionary = _buttons[b_key]
				var hit_r: float = float(btn["radius"]) * 1.22
				var d: float = pos.distance_to(btn["pos"])
				if d <= hit_r and d < best_dist and int(btn["touch_id"]) == -1:
					best_dist = d
					best_key = b_key
			if best_key != "":
				var btn: Dictionary = _buttons[best_key]
				btn["touch_id"] = st.index
				btn["pressed"] = true
				Input.action_press(btn["action"])
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			
			# 2. Left half of screen controls the virtual joystick
			if _joy_touch_id == -1 and pos.x <= vp_size.x * 0.52 and pos.y >= vp_size.y * 0.18:
				_joy_touch_id = st.index
				_joy_base_pos = Vector2(
					clampf(pos.x, _joy_radius + 28.0, vp_size.x * 0.44),
					clampf(pos.y, vp_size.y * 0.28, vp_size.y - _joy_radius - 28.0)
				)
				_update_joystick(pos)
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
		else:
			if st.index == _joy_touch_id:
				_reset_joystick()
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			for b_key in _buttons.keys():
				var btn: Dictionary = _buttons[b_key]
				if int(btn["touch_id"]) == st.index:
					btn["touch_id"] = -1
					btn["pressed"] = false
					Input.action_release(btn["action"])
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
	
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_touch_id:
			var pos: Vector2 = _to_local_canvas_pos(sd.position)
			_update_joystick(pos)
			queue_redraw()
			get_viewport().set_input_as_handled()

func _to_local_canvas_pos(screen_pos: Vector2) -> Vector2:
	# Inside a CanvasLayer (follow_viewport_enabled = false), get_global_transform_with_canvas()
	# maps directly between Control local coordinates and screen/viewport event coordinates
	# without mixing in Camera2D world transform.
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

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
		Input.action_press(action, clampf(strength, 0.45, 1.0))
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
	
	# Unified sleek white-gray semi-transparent palette
	var joy_active: bool = (_joy_touch_id != -1)
	var base_fill := Color(0.86, 0.88, 0.92, 0.16 if joy_active else 0.10)
	var base_rim := Color(0.94, 0.95, 0.98, 0.44 if joy_active else 0.26)
	draw_circle(_joy_base_pos, _joy_radius, base_fill)
	draw_arc(_joy_base_pos, _joy_radius, 0.0, TAU, 64, base_rim, 2.2 * _ui_scale, true)
	
	var knob_fill := Color(0.95, 0.96, 0.98, 0.56 if joy_active else 0.34)
	var knob_rim := Color(1.0, 1.0, 1.0, 0.72 if joy_active else 0.45)
	draw_circle(_joy_knob_pos, _joy_knob_radius, knob_fill)
	draw_arc(_joy_knob_pos, _joy_knob_radius, 0.0, TAU, 48, knob_rim, 2.0 * _ui_scale, true)
	
	for b_key in _buttons.keys():
		var btn: Dictionary = _buttons[b_key]
		var is_down: bool = bool(btn["pressed"])
		var center: Vector2 = btn["pos"]
		var r: float = float(btn["radius"]) * (0.94 if is_down else 1.0)
		
		var btn_fill := Color(0.92, 0.94, 0.97, 0.32 if is_down else 0.13)
		var btn_rim := Color(0.96, 0.97, 1.0, 0.70 if is_down else 0.34)
		var icon_col := Color(0.98, 0.99, 1.0, 0.92 if is_down else 0.58)
		
		draw_circle(center, r, btn_fill)
		draw_arc(center, r, 0.0, TAU, 56, btn_rim, (2.6 if is_down else 2.0) * _ui_scale, true)
		
		# Sleek monochrome geometric icons (no noisy text or rainbow rims)
		if b_key == "attack":
			# Minimalist diagonal sword silhouette
			var s := r * 0.42
			var dir := Vector2(1.0, -1.0).normalized()
			var perp := Vector2(-dir.y, dir.x)
			# Blade
			draw_line(center - dir * (s * 0.45), center + dir * (s * 0.95), icon_col, 4.2 * _ui_scale, true)
			# Crossguard
			var guard_c := center - dir * (s * 0.32)
			draw_line(guard_c - perp * (s * 0.42), guard_c + perp * (s * 0.42), icon_col, 3.2 * _ui_scale, true)
			# Grip + pommel
			draw_line(guard_c, center - dir * (s * 0.85), icon_col, 3.0 * _ui_scale, true)
			draw_circle(center - dir * (s * 0.90), 2.8 * _ui_scale, icon_col)
		elif b_key == "dash":
			# Sleek twin forward chevrons
			var s := r * 0.34
			for ox in [-s * 0.38, s * 0.32]:
				var c := center + Vector2(ox, 0.0)
				var pts := PackedVector2Array([
					c + Vector2(-s * 0.36, -s * 0.62),
					c + Vector2(s * 0.36, 0.0),
					c + Vector2(-s * 0.36, s * 0.62),
				])
				draw_polyline(pts, icon_col, 3.2 * _ui_scale, true)
		elif b_key == "block":
			# Minimalist shield outline
			var s := r * 0.40
			var pts := PackedVector2Array([
				center + Vector2(0.0, -s * 0.88),
				center + Vector2(s * 0.78, -s * 0.56),
				center + Vector2(s * 0.68, s * 0.18),
				center + Vector2(0.0, s * 0.92),
				center + Vector2(-s * 0.68, s * 0.18),
				center + Vector2(-s * 0.78, -s * 0.56),
				center + Vector2(0.0, -s * 0.88),
			])
			draw_polyline(pts, icon_col, 3.0 * _ui_scale, true)
