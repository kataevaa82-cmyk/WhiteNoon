extends Control

signal move_changed(value: Vector2)
signal look_changed(delta: Vector2)
signal action_pressed
signal pause_pressed

var move_finger := -1
var look_finger := -1
var move_origin := Vector2.ZERO
var move_position := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var size := get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x > size.x - 96.0 and event.position.y < 96.0:
				pause_pressed.emit()
			elif event.position.x < size.x * 0.45 and event.position.y > size.y * 0.45 and move_finger < 0:
				move_finger = event.index
				move_origin = event.position
				move_position = event.position
				queue_redraw()
			elif event.position.x > size.x * 0.76 and event.position.y > size.y * 0.68:
				action_pressed.emit()
			elif look_finger < 0:
				look_finger = event.index
		else:
			if event.index == move_finger:
				move_finger = -1
				move_changed.emit(Vector2.ZERO)
				queue_redraw()
			elif event.index == look_finger:
				look_finger = -1
	elif event is InputEventScreenDrag:
		if event.index == move_finger:
			move_position = event.position
			var offset := (move_position - move_origin) / 70.0
			move_changed.emit(offset.limit_length(1.0))
			queue_redraw()
		elif event.index == look_finger:
			look_changed.emit(event.relative)

func _draw() -> void:
	if not visible:
		return
	var size := get_viewport_rect().size
	var pause_center := Vector2(size.x - 48.0, 48.0)
	draw_circle(pause_center, 29.0, Color(0.04, 0.02, 0.04, 0.46))
	draw_arc(pause_center, 29.0, 0.0, TAU, 32, Color(1.0, 0.91, 0.65, 0.72), 2.0)
	draw_line(pause_center + Vector2(-7.0, -9.0), pause_center + Vector2(-7.0, 9.0), Color(1.0, 0.94, 0.76, 0.9), 4.0)
	draw_line(pause_center + Vector2(7.0, -9.0), pause_center + Vector2(7.0, 9.0), Color(1.0, 0.94, 0.76, 0.9), 4.0)
	var action_center := Vector2(size.x - 92.0, size.y - 92.0)
	draw_circle(action_center, 54.0, Color(0.95, 0.86, 0.35, 0.22))
	draw_arc(action_center, 54.0, 0.0, TAU, 40, Color(1.0, 0.94, 0.65, 0.7), 3.0)
	draw_circle(action_center, 13.0, Color(1.0, 0.82, 0.27, 0.92))
	for ray_index in range(8):
		var angle := float(ray_index) * TAU / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(action_center + direction * 19.0, action_center + direction * 31.0, Color(1.0, 0.93, 0.62, 0.9), 3.0)
	var center := move_origin if move_finger >= 0 else Vector2(105.0, size.y - 105.0)
	var knob := move_position if move_finger >= 0 else center
	knob = center + (knob - center).limit_length(62.0)
	draw_circle(center, 72.0, Color(1.0, 1.0, 1.0, 0.12))
	draw_arc(center, 72.0, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.38), 3.0)
	draw_circle(knob, 31.0, Color(1.0, 0.92, 0.62, 0.45))
