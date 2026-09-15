extends CharacterBody3D

signal hit(damage: float)
signal charge_started
signal charge_evaded
signal attack_started
signal wail(origin: Vector3, radius: float)

## Виды врагов. Все они живут в одной сцене: скрипт ждёт узлы Model, Aura,
## AttackTell, ChargeTell и EyesGlow, поэтому отдельные сцены пришлось бы
## держать синхронными. Вид задаётся через apply_kind() уже после того, как
## уровень выставил базовые характеристики.
const KIND_WARDEN := "warden"     # Страж: как и был — патруль, рывок, удар
const KIND_HUSK := "husk"         # Ползун: мелкий, быстрый, рыскает зигзагом
const KIND_STALKER := "stalker"   # Соглядатай: на свету еле ползёт, в тени летит
const KIND_RINGER := "ringer"     # Плакальщица: медленная, бьёт криком по площади
const KIND_SENTINEL := "sentinel" # Сторож: не отходит от своего места, бьёт сильно

@export var sun_speed := 3.15
@export var shadow_speed := 4.8
@export var attack_damage := 24.0
@export var attack_interval := 1.15

const ATTACK_WINDUP_DURATION := 0.48
const CHARGE_WINDUP_DURATION := 0.82
const CHARGE_DURATION := 0.46
const CHARGE_SPEED := 12.5
const WAIL_WINDUP_DURATION := 1.05
const WAIL_INTERVAL := 6.4

var target: Node3D
var active := false
var trapped := false
var seals_found := 0
var player_in_shadow := false
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var start_position := Vector3.ZERO
var attack_cooldown := 0.0
var stun_time := 0.0
var attack_pulse := 0.0
var visual_time := 0.0
var hunt_time := 0.0
var attack_windup := 0.0
var rage_time := 0.0
var charge_windup := 0.0
var charge_time := 0.0
var charge_cooldown := 0.0
var charge_direction := Vector3.ZERO
var charge_has_hit := false
var charge_launched := false

var kind := KIND_WARDEN
var can_charge := true
var detection_range := 9.0
var leash_radius := INF
var wander_amount := 0.0
var post_position := Vector3.ZERO
var wail_range := 0.0
var wail_cooldown := 0.0
var wail_windup := 0.0
var sunlight_sluggish := 0.0
var kind_tint := Color(1, 1, 1)
var body_scale := Vector3.ONE

func _ready() -> void:
	start_position = global_position
	post_position = global_position

## Настраивает вид врага поверх уже выставленных уровнем характеристик.
func apply_kind(new_kind: String) -> void:
	kind = new_kind
	post_position = global_position
	match kind:
		KIND_HUSK:
			sun_speed *= 1.24
			shadow_speed *= 1.18
			attack_damage *= 0.55
			attack_interval *= 0.62
			can_charge = false
			detection_range = 7.0
			wander_amount = 2.6
			body_scale = Vector3(0.66, 0.62, 0.66)
			kind_tint = Color(0.86, 0.62, 0.20)
		KIND_STALKER:
			sun_speed *= 0.46
			shadow_speed *= 1.36
			attack_damage *= 0.9
			attack_interval *= 0.86
			can_charge = false
			detection_range = 17.0
			sunlight_sluggish = 1.0
			body_scale = Vector3(0.86, 1.16, 0.86)
			kind_tint = Color(0.52, 0.24, 0.86)
		KIND_RINGER:
			sun_speed *= 0.58
			shadow_speed *= 0.66
			attack_damage *= 0.8
			can_charge = false
			detection_range = 13.0
			wail_range = 9.5
			body_scale = Vector3(1.06, 1.22, 1.06)
			kind_tint = Color(0.62, 0.82, 1.0)
		KIND_SENTINEL:
			sun_speed *= 0.82
			shadow_speed *= 0.86
			attack_damage *= 1.4
			attack_interval *= 1.15
			detection_range = 11.0
			leash_radius = 9.5
			body_scale = Vector3(1.16, 1.14, 1.16)
			kind_tint = Color(0.58, 0.56, 0.48)
		_:
			kind = KIND_WARDEN
	_apply_kind_look()

func _apply_kind_look() -> void:
	if kind == KIND_WARDEN:
		return
	_apply_body_scale()
	var overlay := StandardMaterial3D.new()
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	overlay.albedo_color = Color(kind_tint.r, kind_tint.g, kind_tint.b, 0.33)
	overlay.emission_enabled = true
	overlay.emission = kind_tint
	overlay.emission_energy_multiplier = 0.22
	for node in _model_meshes($Model):
		node.material_overlay = overlay
	var aura_material := ($Aura.mesh as TorusMesh).material.duplicate() as StandardMaterial3D
	aura_material.albedo_color = Color(kind_tint.r, kind_tint.g, kind_tint.b, 0.34)
	aura_material.emission = kind_tint
	var aura_mesh := ($Aura.mesh as TorusMesh).duplicate() as TorusMesh
	aura_mesh.material = aura_material
	$Aura.mesh = aura_mesh
	$EyesGlow.light_color = kind_tint
	match kind:
		KIND_RINGER:
			# Нимб плакальщицы: сразу видно, кто сейчас закричит.
			var halo_mesh := TorusMesh.new()
			halo_mesh.inner_radius = 0.62
			halo_mesh.outer_radius = 0.72
			halo_mesh.rings = 18
			halo_mesh.ring_segments = 6
			halo_mesh.material = aura_material
			var halo := MeshInstance3D.new()
			halo.name = "Halo"
			halo.position = Vector3(0, 3.1 * body_scale.y, 0)
			halo.rotation.x = PI * 0.5
			halo.mesh = halo_mesh
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(halo)
		KIND_SENTINEL:
			# Каменный воротник сторожа поля.
			var collar_material := StandardMaterial3D.new()
			collar_material.albedo_color = Color(0.30, 0.28, 0.26)
			collar_material.roughness = 0.95
			var collar_mesh := CylinderMesh.new()
			collar_mesh.top_radius = 0.86
			collar_mesh.bottom_radius = 1.15
			collar_mesh.height = 0.7
			collar_mesh.radial_segments = 8
			collar_mesh.material = collar_material
			var collar := MeshInstance3D.new()
			collar.name = "Collar"
			collar.position.y = 0.35 * body_scale.y
			collar.mesh = collar_mesh
			add_child(collar)
		KIND_HUSK:
			# Ползун — соломенная кукла на палке.
			var straw_material := StandardMaterial3D.new()
			straw_material.albedo_color = Color(0.62, 0.48, 0.18)
			straw_material.roughness = 1.0
			var arms_mesh := BoxMesh.new()
			arms_mesh.size = Vector3(1.9 * body_scale.x, 0.10, 0.10)
			arms_mesh.material = straw_material
			var arms := MeshInstance3D.new()
			arms.name = "Arms"
			arms.position = Vector3(0, 2.1 * body_scale.y, 0)
			arms.mesh = arms_mesh
			add_child(arms)

func _apply_body_scale() -> void:
	# Масштабируем модель и капсулу отдельно: неравномерный scale на самом
	# CharacterBody3D ломает форму столкновений.
	$Model.scale = body_scale
	$Aura.scale = Vector3(body_scale.x, 1.0, body_scale.z)
	$AttackTell.position.y = 2.05 * body_scale.y
	$ChargeTell.position.z = 2.7 * body_scale.z
	$EyesGlow.position = Vector3(0, 2.8 * body_scale.y, 0.35 * body_scale.z)
	var collision := $CollisionShape3D as CollisionShape3D
	var capsule := (collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = 0.62 * maxf(body_scale.x, body_scale.z)
	capsule.height = maxf(capsule.radius * 2.0 + 0.05, 2.6 * body_scale.y)
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5

func _model_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_model_meshes(child))
	return found

func configure(player: Node3D, points: Array[Vector3]) -> void:
	target = player
	patrol_points = points

func awaken(found: int) -> void:
	if trapped:
		return
	seals_found = found
	active = true
	hunt_time = maxf(hunt_time, 7.0 + found * 1.5)
	$Aura.visible = true

func enrage(duration: float) -> void:
	if trapped:
		return
	active = true
	rage_time = maxf(rage_time, duration)
	hunt_time = maxf(hunt_time, duration)
	$Aura.visible = true

func stun(duration: float) -> void:
	stun_time = maxf(stun_time, duration)
	attack_cooldown = maxf(attack_cooldown, duration + 0.35)
	attack_windup = 0.0
	# Импульс прерывает и крик: иначе оглушённая плакальщица всё равно
	# доводила замах до конца, хотя все остальные приёмы сбивались.
	wail_windup = 0.0
	charge_windup = 0.0
	charge_time = 0.0
	charge_launched = false
	charge_cooldown = maxf(charge_cooldown, duration + 0.8)

func repel_from(source: Vector3, force: float) -> void:
	var direction := global_position - source
	direction.y = 0.0
	if direction.length_squared() > 0.01:
		direction = direction.normalized()
		velocity.x = direction.x * force
		velocity.z = direction.z * force

func capture_in_trap() -> void:
	trapped = true
	active = false
	velocity = Vector3.ZERO
	attack_windup = 0.0
	charge_windup = 0.0
	charge_time = 0.0
	wail_windup = 0.0
	$Aura.visible = false
	$AttackTell.visible = false
	$ChargeTell.visible = false
	$EyesGlow.light_energy = 0.0

func reset_guardian() -> void:
	global_position = start_position
	velocity = Vector3.ZERO
	active = false
	trapped = false
	seals_found = 0
	stun_time = 0.0
	attack_cooldown = 0.0
	hunt_time = 0.0
	attack_windup = 0.0
	rage_time = 0.0
	charge_windup = 0.0
	charge_time = 0.0
	charge_cooldown = 0.0
	charge_direction = Vector3.ZERO
	charge_has_hit = false
	charge_launched = false
	wail_cooldown = 0.0
	wail_windup = 0.0
	$Aura.visible = false
	$ChargeTell.visible = false
	$EyesGlow.light_energy = 0.0

func _process(delta: float) -> void:
	visual_time += delta
	attack_pulse = move_toward(attack_pulse, 0.0, delta * 3.8)
	var windup_progress := 1.0 - attack_windup / ATTACK_WINDUP_DURATION if attack_windup > 0.0 else 0.0
	var charge_progress := 1.0 - charge_windup / CHARGE_WINDUP_DURATION if charge_windup > 0.0 else 0.0
	$Model.position.y = sin(visual_time * (3.4 if active else 1.5)) * (0.045 if active else 0.018)
	$Model.position.z = attack_pulse * 0.22 - windup_progress * 0.15 - charge_progress * 0.24
	$Model.rotation.x = -windup_progress * 0.11 - charge_progress * 0.16
	$Model.rotation.z = sin(visual_time * 16.0) * 0.035 if stun_time > 0.0 else sin(visual_time * 1.7) * 0.012
	$Aura.rotation.y += delta * (1.7 + seals_found * 0.25 + (1.2 if rage_time > 0.0 else 0.0))
	var aura_pulse := 0.94 + sin(visual_time * 4.2) * 0.09
	if rage_time > 0.0:
		aura_pulse += 0.18 + sin(visual_time * 9.0) * 0.08
	$Aura.scale = Vector3(body_scale.x * aura_pulse * (0.72 if charge_time > 0.0 else 1.0), 1.0, body_scale.z * aura_pulse * (1.55 if charge_time > 0.0 else 1.0))
	$AttackTell.visible = attack_windup > 0.0
	$AttackTell.rotation.z += delta * 4.5
	var tell_scale := 1.28 + windup_progress * 0.38 + sin(visual_time * 18.0) * 0.06
	$AttackTell.scale = Vector3.ONE * tell_scale
	$ChargeTell.visible = charge_windup > 0.0
	var charge_length := 0.12 + charge_progress * 0.88
	$ChargeTell.scale = Vector3(0.72 + charge_progress * 0.42, 1.0, charge_length)
	$ChargeTell.position.z = 2.7 * charge_length
	$ChargeTell.transparency = 0.18 + sin(visual_time * 20.0) * 0.12
	var hot := Color(1.0, 0.30, 0.025) if kind == KIND_WARDEN else kind_tint.lerp(Color(1, 1, 1), 0.35)
	var calm := Color(1.0, 0.055, 0.012) if kind == KIND_WARDEN else kind_tint
	$EyesGlow.light_color = hot if charge_windup > 0.0 or charge_time > 0.0 or wail_windup > 0.0 else calm
	var wail_progress := 1.0 - wail_windup / WAIL_WINDUP_DURATION if wail_windup > 0.0 else 0.0
	$EyesGlow.light_energy = (0.28 + seals_found * 0.10 + sin(visual_time * 5.0) * 0.08 + windup_progress * 0.9 + charge_progress * 1.15 + wail_progress * 1.4 + (0.55 if rage_time > 0.0 else 0.0)) if active else 0.0
	_update_kind_visuals(delta, wail_progress)

func _update_kind_visuals(delta: float, wail_progress: float) -> void:
	match kind:
		KIND_RINGER:
			var halo := get_node_or_null("Halo") as MeshInstance3D
			if halo != null:
				halo.rotation.z += delta * (0.9 + wail_progress * 7.0)
				halo.scale = Vector3.ONE * (1.0 + wail_progress * 1.5 + sin(visual_time * 2.4) * 0.06)
				halo.visible = active
		KIND_STALKER:
			# На свету соглядатай густеет и еле ползёт, в тени почти растворяется.
			$Model.position.x = sin(visual_time * 1.1) * (0.0 if player_in_shadow else 0.05)
		KIND_HUSK:
			var arms := get_node_or_null("Arms") as MeshInstance3D
			if arms != null:
				arms.rotation.z = sin(visual_time * 9.0) * 0.28
				arms.rotation.y += delta * 0.6

func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	charge_cooldown = maxf(0.0, charge_cooldown - delta)
	wail_cooldown = maxf(0.0, wail_cooldown - delta)
	stun_time = maxf(0.0, stun_time - delta)
	hunt_time = maxf(0.0, hunt_time - delta)
	rage_time = maxf(0.0, rage_time - delta)
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	if not active or not is_instance_valid(target):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if stun_time > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		move_and_slide()
		return

	var distance := global_position.distance_to(target.global_position)
	if charge_time > 0.0:
		charge_time = maxf(0.0, charge_time - delta)
		velocity.x = charge_direction.x * CHARGE_SPEED
		velocity.z = charge_direction.z * CHARGE_SPEED
		rotation.y = lerp_angle(rotation.y, atan2(charge_direction.x, charge_direction.z), delta * 12.0)
		move_and_slide()
		distance = global_position.distance_to(target.global_position)
		if not charge_has_hit and distance < 1.8:
			charge_has_hit = true
			attack_pulse = 1.0
			hit.emit(30.0 + float(maxi(0, seals_found - 2)) * 2.0)
			charge_time = 0.0
		if charge_time <= 0.0 or _charge_hit_obstacle():
			_finish_charge()
		return
	if charge_windup > 0.0:
		charge_windup = maxf(0.0, charge_windup - delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		rotation.y = lerp_angle(rotation.y, atan2(charge_direction.x, charge_direction.z), delta * 9.0)
		if charge_windup <= 0.0:
			charge_time = CHARGE_DURATION
			charge_has_hit = false
			charge_launched = true
		move_and_slide()
		return
	if wail_windup > 0.0:
		wail_windup = maxf(0.0, wail_windup - delta)
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		if wail_windup <= 0.0:
			wail_cooldown = WAIL_INTERVAL
			attack_cooldown = maxf(attack_cooldown, 1.2)
			wail.emit(global_position, wail_range)
			if distance < wail_range:
				hit.emit(attack_damage * 0.62)
		move_and_slide()
		return
	if attack_windup > 0.0:
		attack_windup = maxf(0.0, attack_windup - delta)
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		if attack_windup <= 0.0:
			attack_cooldown = attack_interval
			if distance < 2.55:
				attack_pulse = 1.0
				hit.emit(attack_damage + float(seals_found - 1) * 2.0)
		move_and_slide()
		return
	var detection := detection_range + float(seals_found) * 4.0
	var chasing := hunt_time > 0.0 or distance < detection
	if chasing and leash_radius < INF and post_position.distance_to(target.global_position) > leash_radius:
		# Сторож поля не бросает свой участок: возвращается на пост.
		chasing = false
	var destination := target.global_position if chasing else _patrol_destination()
	var direction := destination - global_position
	direction.y = 0.0
	if wander_amount > 0.0 and direction.length() > 0.6:
		# Ползун не идёт по прямой — рыскает из стороны в сторону.
		var side := Vector3(-direction.z, 0.0, direction.x).normalized()
		direction += side * sin(visual_time * 3.1 + start_position.x) * wander_amount
	if direction.length() > 0.3:
		direction = direction.normalized()
		var speed := shadow_speed if player_in_shadow else sun_speed
		speed += seals_found * 0.28
		if hunt_time > 0.0:
			speed += 0.35
		if rage_time > 0.0:
			speed += 0.72
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 5.0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if distance >= detection and patrol_points.size() > 0:
			patrol_index = (patrol_index + 1) % patrol_points.size()
	move_and_slide()
	if wail_range > 0.0 and distance < wail_range and wail_cooldown <= 0.0 and attack_cooldown <= 0.0:
		wail_windup = WAIL_WINDUP_DURATION
		attack_started.emit()
	elif can_charge and (seals_found >= 2 or rage_time > 0.0) and distance > 4.4 and distance < 8.2 and charge_cooldown <= 0.0 and attack_cooldown <= 0.0 and _has_clear_charge_path():
		_begin_charge()
	elif distance < 2.35 and attack_cooldown <= 0.0:
		attack_windup = ATTACK_WINDUP_DURATION
		attack_started.emit()

func _begin_charge() -> void:
	charge_direction = target.global_position - global_position
	charge_direction.y = 0.0
	if charge_direction.length_squared() <= 0.01:
		return
	charge_direction = charge_direction.normalized()
	charge_windup = CHARGE_WINDUP_DURATION
	charge_has_hit = false
	charge_launched = false
	velocity.x = 0.0
	velocity.z = 0.0
	charge_started.emit()

func _finish_charge() -> void:
	if charge_launched and not charge_has_hit:
		charge_evaded.emit()
	charge_launched = false
	charge_time = 0.0
	charge_windup = 0.0
	charge_cooldown = 4.2
	attack_cooldown = maxf(attack_cooldown, 0.7)
	velocity.x *= 0.25
	velocity.z *= 0.25

func _charge_hit_obstacle() -> bool:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if absf(collision.get_normal().y) < 0.55:
			return true
	return false

func _has_clear_charge_path() -> bool:
	var origin := global_position + Vector3(0, 1.0, 0)
	var destination := target.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	var exclusions: Array[RID] = [get_rid()]
	var target_body := target as CollisionObject3D
	if target_body != null:
		exclusions.append(target_body.get_rid())
	query.exclude = exclusions
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _patrol_destination() -> Vector3:
	if leash_radius < INF:
		return post_position
	if patrol_points.is_empty():
		return global_position
	return patrol_points[patrol_index]
