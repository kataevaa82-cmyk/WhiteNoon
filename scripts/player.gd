extends CharacterBody3D

signal stamina_changed(value: float, maximum: float)
signal footstep(intensity: float)

@export var walk_speed := 4.2
@export var sprint_speed := 6.7
@export var mouse_sensitivity := 0.0022
@export var max_stamina := 100.0
@export var stamina_drain := 25.0
@export var stamina_recovery := 17.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var controls_enabled := false
var touch_move := Vector2.ZERO
var pitch := 0.0
var spawn_point := Vector3.ZERO
var planar_velocity := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
var hit_shake := 0.0
var stamina := 100.0
var exhausted := false
var health_ratio := 1.0
var step_time := 0.0
var bob_offset := Vector3.ZERO
var sprint_blend := 0.0
var fatigue_blend := 0.0
var distance_since_step := 0.0

func _ready() -> void:
	add_to_group("player")
	spawn_point = global_position
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)

func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if value and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_touch_move(value: Vector2) -> void:
	touch_move = value

func add_touch_look(delta: Vector2) -> void:
	if controls_enabled:
		_apply_look(delta * 0.0045)

func reset_to_spawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	planar_velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	bob_offset = Vector3.ZERO
	step_time = 0.0
	sprint_blend = 0.0
	fatigue_blend = 0.0
	distance_since_step = 0.0
	camera.position = Vector3.ZERO
	camera.fov = 76.0
	head.rotation.z = 0.0

func set_health_ratio(value: float) -> void:
	health_ratio = clampf(value, 0.0, 1.0)

func apply_knockback(source: Vector3, force: float) -> void:
	var direction := global_position - source
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.BACK
	knockback_velocity = direction.normalized() * force
	hit_shake = 1.0

func spend_stamina(amount: float) -> bool:
	if stamina + 0.01 < amount:
		return false
	stamina = maxf(0.0, stamina - amount)
	if stamina <= 0.0:
		exhausted = true
	stamina_changed.emit(stamina, max_stamina)
	return true

func restore_stamina(amount: float) -> void:
	stamina = minf(max_stamina, stamina + amount)
	if stamina >= 34.0:
		exhausted = false
	stamina_changed.emit(stamina, max_stamina)

func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * mouse_sensitivity)
	elif controls_enabled and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	pitch = clamp(pitch - delta.y, deg_to_rad(-72.0), deg_to_rad(72.0))
	head.rotation.x = pitch

func _physics_process(delta: float) -> void:
	hit_shake = move_toward(hit_shake, 0.0, delta * 2.8)
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 11.0 * delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2

	if not controls_enabled:
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, 20.0 * delta)
		velocity.x = planar_velocity.x + knockback_velocity.x
		velocity.z = planar_velocity.z + knockback_velocity.z
		move_and_slide()
		_update_camera_effects(delta, false, Vector2.ZERO)
		return

	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_vector := touch_move if touch_move.length() > keyboard.length() else keyboard
	var local_direction := Vector3(input_vector.x, 0.0, input_vector.y)
	var direction := (transform.basis * local_direction).normalized()
	var wants_sprint := Input.is_action_pressed("sprint") or (touch_move.length() > 0.82 and keyboard.length() < 0.1)
	if exhausted and stamina >= 34.0:
		exhausted = false
	var sprinting := wants_sprint and not exhausted and direction.length_squared() > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(max_stamina, stamina + stamina_recovery * delta)
	stamina_changed.emit(stamina, max_stamina)
	var speed := sprint_speed if sprinting else walk_speed
	if direction:
		planar_velocity = planar_velocity.move_toward(direction * speed, 22.0 * delta)
	else:
		planar_velocity = planar_velocity.move_toward(Vector3.ZERO, 17.0 * delta)
	velocity.x = planar_velocity.x + knockback_velocity.x
	velocity.z = planar_velocity.z + knockback_velocity.z
	move_and_slide()
	_update_camera_effects(delta, sprinting, input_vector)

func _update_camera_effects(delta: float, sprinting: bool, input_vector: Vector2) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var motion := clampf(planar_speed / walk_speed, 0.0, 1.0) if controls_enabled and is_on_floor() else 0.0
	sprint_blend = move_toward(sprint_blend, 1.0 if sprinting else 0.0, delta * 4.8)
	var fatigue_target := clampf((38.0 - stamina) / 38.0, 0.0, 1.0) if exhausted else clampf((18.0 - stamina) / 18.0, 0.0, 0.36)
	fatigue_blend = move_toward(fatigue_blend, fatigue_target, delta * 2.4)
	var target_bob := Vector3.ZERO
	if motion > 0.08:
		step_time += delta * lerpf(8.0, 11.2, sprint_blend)
		distance_since_step += planar_speed * delta
		var step_spacing := lerpf(1.65, 1.92, sprint_blend)
		if distance_since_step >= step_spacing:
			distance_since_step = fmod(distance_since_step, step_spacing)
			footstep.emit(lerpf(0.68, 1.0, sprint_blend))
		target_bob.x = sin(step_time * 0.5) * 0.014 * motion
		target_bob.y = absf(sin(step_time)) * 0.026 * motion
	else:
		distance_since_step = minf(distance_since_step, 0.8)
	bob_offset = bob_offset.lerp(target_bob, clampf(delta * 12.0, 0.0, 1.0))
	var low_health := pow(1.0 - health_ratio, 2.0)
	var breath_time := Time.get_ticks_msec() * 0.001
	var breath := sin(breath_time * lerpf(1.9, 3.1, fatigue_blend)) * (fatigue_blend * 0.012 + low_health * 0.016)
	var shake_time := Time.get_ticks_msec() * 0.035
	var shake := Vector3(sin(shake_time), cos(shake_time * 1.37), 0) * hit_shake * 0.032
	camera.position = bob_offset + Vector3(0, breath, 0) + shake
	var target_fov := 76.0 + sprint_blend * 3.2 - fatigue_blend * 0.7
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 7.0, 0.0, 1.0))
	var target_roll := -input_vector.x * motion * 0.018 + sin(breath_time * 1.35) * low_health * 0.006
	head.rotation.z = lerpf(head.rotation.z, target_roll, clampf(delta * 7.5, 0.0, 1.0))
