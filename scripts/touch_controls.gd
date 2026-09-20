extends Control

signal move_changed(value: Vector2)
signal look_changed(delta: Vector2)
signal action_pressed
signal pause_pressed

## Кольцо джойстика всегда нарисовано в одном и том же месте, а палец задаёт
## только смещение от точки касания. Раньше точкой отсчёта было само касание,
## и кольцо телепортировалось через пол-экрана к пальцу — именно это читалось
## как «управление скачет».
const STICK_RADIUS := 84.0
const KNOB_RADIUS := 28.0
const STICK_TRAVEL := STICK_RADIUS - KNOB_RADIUS
const STICK_MARGIN := Vector2(112.0, 112.0)
## Без мёртвой зоны дрожание пальца превращалось в рывки персонажа.
const DEADZONE := 0.16
const PAUSE_CENTER_MARGIN := Vector2(48.0, 48.0)
const PAUSE_RADIUS := 29.0
const PAUSE_TOUCH_RADIUS := 46.0
const ACTION_CENTER_MARGIN := Vector2(92.0, 92.0)
const ACTION_RADIUS := 54.0
const ACTION_TOUCH_RADIUS := 74.0

var move_finger := -1
var look_finger := -1
var move_anchor := Vector2.ZERO
var move_offset := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()
	set_process_input(true)

func _stick_center() -> Vector2:
	var size := get_viewport_rect().size
	return Vector2(STICK_MARGIN.x, size.y - STICK_MARGIN.y)

func _pause_center() -> Vector2:
	var size := get_viewport_rect().size
	return Vector2(size.x - PAUSE_CENTER_MARGIN.x, PAUSE_CENTER_MARGIN.y)

func _action_center() -> Vector2:
	var size := get_viewport_rect().size
	return size - ACTION_CENTER_MARGIN

## Отклонение стика: 1.0 ровно тогда, когда шарик упирается в кольцо, поэтому
## то, что игрок видит, совпадает с тем, что получает персонаж. Раньше ввод
## нормировался на 70 px, шарик упирался на 62, а кольцо рисовалось радиусом 72.
func _stick_value() -> Vector2:
	var value := move_offset / STICK_TRAVEL
	var magnitude := value.length()
	if magnitude <= DEADZONE:
		return Vector2.ZERO
	# Плавный выход из мёртвой зоны: на её границе скорость 0, а не сразу 16%.
	var scaled := (minf(magnitude, 1.0) - DEADZONE) / (1.0 - DEADZONE)
	return value / magnitude * scaled

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var size := get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(_pause_center()) <= PAUSE_TOUCH_RADIUS:
				pause_pressed.emit()
			elif event.position.distance_to(_action_center()) <= ACTION_TOUCH_RADIUS:
				action_pressed.emit()
			elif move_finger < 0 and event.position.x < size.x * 0.45 and event.position.y > size.y * 0.42:
				move_finger = event.index
				move_anchor = event.position
				move_offset = Vector2.ZERO
				# Касание никогда не сдвигает персонажа: стик начинает с нуля,
				# куда бы в зону джойстика ни попал палец.
				move_changed.emit(Vector2.ZERO)
				queue_redraw()
			elif look_finger < 0:
				look_finger = event.index
		else:
			if event.index == move_finger:
				_release_stick()
			elif event.index == look_finger:
				look_finger = -1
	elif event is InputEventScreenDrag:
		if event.index == move_finger:
			move_offset = (event.position - move_anchor).limit_length(STICK_TRAVEL)
			move_changed.emit(_stick_value())
			queue_redraw()
		elif event.index == look_finger:
			look_changed.emit(event.relative)

func _release_stick() -> void:
	move_finger = -1
	move_offset = Vector2.ZERO
	move_changed.emit(Vector2.ZERO)
	queue_redraw()

## Ушли в фон или на паузу с зажатым пальцем — иначе персонаж продолжал бы
## бежать в ту же сторону после возвращения.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and move_finger >= 0:
		_release_stick()

func _draw() -> void:
	if not visible:
		return
	var pause_center := _pause_center()
	draw_circle(pause_center, PAUSE_RADIUS, Color(0.04, 0.02, 0.04, 0.46))
	draw_arc(pause_center, PAUSE_RADIUS, 0.0, TAU, 32, Color(1.0, 0.91, 0.65, 0.72), 2.0)
	draw_line(pause_center + Vector2(-7.0, -9.0), pause_center + Vector2(-7.0, 9.0), Color(1.0, 0.94, 0.76, 0.9), 4.0)
	draw_line(pause_center + Vector2(7.0, -9.0), pause_center + Vector2(7.0, 9.0), Color(1.0, 0.94, 0.76, 0.9), 4.0)
	var action_center := _action_center()
	draw_circle(action_center, ACTION_RADIUS, Color(0.95, 0.86, 0.35, 0.22))
	draw_arc(action_center, ACTION_RADIUS, 0.0, TAU, 40, Color(1.0, 0.94, 0.65, 0.7), 3.0)
	draw_circle(action_center, 13.0, Color(1.0, 0.82, 0.27, 0.92))
	for ray_index in range(8):
		var angle := float(ray_index) * TAU / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(action_center + direction * 19.0, action_center + direction * 31.0, Color(1.0, 0.93, 0.62, 0.9), 3.0)
	var center := _stick_center()
	var active := move_finger >= 0
	draw_circle(center, STICK_RADIUS, Color(1.0, 1.0, 1.0, 0.16 if active else 0.12))
	draw_arc(center, STICK_RADIUS, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.46 if active else 0.34), 3.0)
	# Мёртвая зона видна: пока шарик внутри тусклого кольца, персонаж стоит.
	draw_arc(center, STICK_TRAVEL * DEADZONE, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.16), 2.0)
	draw_circle(center + move_offset, KNOB_RADIUS, Color(1.0, 0.92, 0.62, 0.58 if active else 0.42))
