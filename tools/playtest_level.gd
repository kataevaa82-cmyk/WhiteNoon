extends SceneTree

var game: Node3D
var player: CharacterBody3D
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_playtest")


func _run_playtest() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	game = packed_scene.instantiate()
	root.add_child(game)
	await _wait_frames(8)
	player = game.get_node("Player")
	game._start_game()
	if not is_instance_valid(game.watching_eyes) or game.watching_eyes.multimesh.visible_instance_count != 2:
		_fail("The noon horror layer did not begin with one watching window")
	if not is_instance_valid(game.ritual_sun_visual) or game.ritual_sun_visual.get_node_or_null("SolsticeDisk") == null:
		_fail("The ritual solstice sun was not assembled")
	elif (game.ritual_sun_visual.global_position - game.get_node("Player/Head/Camera3D").global_position).normalized().dot(game._sun_direction()) < 0.98:
		# Диск должен стоять там, откуда падает свет, иначе тени идут не туда.
		_fail("The solstice disk does not sit in the sun's own direction")
	await _check_shadow_logic()
	var initial_sun_direction: Vector3 = game._sun_direction()
	Input.action_press("sprint")

	# A physics-driven route around buildings: no teleporting through blockers.
	var route := [
		Vector3(-5, 0.1, 25), Vector3(-16, 0.1, 22), Vector3(-16, 0.1, 17),
		Vector3(-21, 0.1, 14), Vector3(-21, 0.1, 3), Vector3(-21, 0.1, -11), Vector3(-14, 0.1, -20),
		Vector3(-8, 0.1, -27), Vector3(1, 0.1, -26), Vector3(10, 0.1, -25),
		Vector3(19, 0.1, -18), Vector3(19, 0.1, -11), Vector3(17, 0.1, -9),
		# (23, -23) — радиус 32.5, это внутри горы. Пока у гор не было коллайдера,
		# маршрут проходил сквозь склон; теперь идём вдоль подошвы.
		Vector3(23, 0.1, -13), Vector3(19, 0.1, -19), Vector3(11, 0.1, -27), Vector3(0, 0.1, -27),
	]

	for waypoint in route:
		if game.phase not in [game.Phase.PLAYING, game.Phase.WON]:
			_fail("Run ended before reaching %s (phase %s, health %.1f)" % [waypoint, game.phase, game.health])
			break
		if game.phase == game.Phase.WON:
			break
		await _move_to(waypoint, 8.0)
		var guardian_distance: float = game.guardian.global_position.distance_to(player.global_position)
		print("PLAYTEST waypoint=", waypoint, " seals=", game.seals_found,
			" health=", snappedf(game.health, 0.1), " stamina=", snappedf(player.stamina, 0.1),
			" guardian_distance=", snappedf(guardian_distance, 0.1), " guardian=", game.guardian.global_position)

	Input.action_release("sprint")
	player.set_touch_move(Vector2.ZERO)
	await _wait_frames(5)
	if game.seals_found != 3:
		_fail("Expected 3 seals, got %d" % game.seals_found)
	if not game.gate_blocker_collision.disabled:
		_fail("Gate blocker remained enabled after the third seal")
	if game.phase != game.Phase.WON:
		_fail("Expected a win at the northern exit, phase=%s" % game.phase)
	if game.sunset_triggered or game.escape_time_remaining <= 0.0:
		_fail("Physics route did not reach the gate before the final escape window elapsed")
	else:
		print("FINAL ESCAPE verified: seconds_remaining=", snappedf(game.escape_time_remaining, 0.1))
	if game.lighting_stage != 3 or not game.exit_path.visible:
		_fail("Third seal did not enable final lighting and the exit sun path")
	if game.watching_eyes.multimesh.visible_instance_count != 12:
		_fail("Watching windows did not escalate with the lighting stages")
	if game._sun_direction().angle_to(initial_sun_direction) < 0.2:
		_fail("Visual and physical sun direction did not advance with the seals")
	if not game.get_node("WorldEnvironment").environment.fog_enabled:
		_fail("Final atmospheric depth state was not enabled")
	else:
		print("LIGHTING progression verified: stage=", game.lighting_stage,
			" sun_angle_deg=", snappedf(rad_to_deg(game._sun_direction().angle_to(initial_sun_direction)), 0.1))

	await _run_combat_check()
	await _run_sunset_check()
	if is_instance_valid(game):
		game.audio.stop_all()
		await _wait_frames(4)
		game.queue_free()
		await _wait_frames(4)

	if failures.is_empty():
		print("PLAYTEST PASS: route, gate, combat, healing and defeat states verified")
		quit(0)
	else:
		for failure in failures:
			push_error("PLAYTEST FAIL: " + failure)
		quit(1)


func _run_combat_check() -> void:
	game.queue_free()
	await _wait_frames(4)
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	game = packed_scene.instantiate()
	root.add_child(game)
	await _wait_frames(6)
	player = game.get_node("Player")
	game._start_game()
	var fresh_environment: Environment = game.get_node("WorldEnvironment").environment
	if game.lighting_stage != 0 or not fresh_environment.fog_enabled or fresh_environment.fog_density > 0.0011:
		_fail("A fresh run inherited the previous run's final lighting state")
		return
	if not await _check_audio_system():
		return
	if not await _check_camera_motion():
		return
	game.seals_found = 1
	player.stamina = player.max_stamina
	game.guardian.global_position = Vector3(0, 0.1, 5)
	game._try_sun_pulse()
	await _wait_frames(3)
	if not is_instance_valid(game.seal_beacon) or game.sun_pulse_cooldown <= 0.0 or player.stamina >= player.max_stamina:
		_fail("Sun pulse did not spend stamina and reveal a distant seal")
		return
	print("NAVIGATION pulse verified: stamina=", snappedf(player.stamina, 0.1))
	player.stamina = player.max_stamina
	game.sun_pulse_cooldown = 0.0
	game.guardian.global_position = Vector3(0, 0.1, 20.5)
	game.guardian.awaken(1)
	var elapsed := 0.0
	while game.guardian.attack_windup <= 0.0 and elapsed < 3.0:
		await physics_frame
		elapsed += 1.0 / 60.0
	if game.guardian.attack_windup <= 0.0:
		_fail("Guardian did not telegraph an attack from close range")
		return
	player.stamina = player.max_stamina
	game.sun_pulse_cooldown = 0.0
	game._try_sun_pulse()
	await _wait_seconds(0.7)
	if game.guardian.stun_time <= 0.0 or player.stamina >= player.max_stamina:
		_fail("Sun pulse did not stun the Guardian and spend stamina")
	elif game.health < game.MAX_HEALTH:
		_fail("Telegraphed attack still landed after being interrupted by the sun pulse")
	else:
		print("COMBAT telegraph interrupted: stamina=", snappedf(player.stamina, 0.1))
	elapsed = 0.0
	while game.health >= game.MAX_HEALTH and elapsed < 6.0:
		await physics_frame
		elapsed += 1.0 / 60.0
	if game.health >= game.MAX_HEALTH:
		_fail("Guardian did not land an attack after recovering from the pulse")
		return
	if game.phase != game.Phase.PLAYING:
		_fail("A single attack ended the game instead of reducing health")
		return
	var damaged_health: float = game.health
	print("COMBAT attack verified: health=", snappedf(damaged_health, 0.1), " elapsed=", snappedf(elapsed, 0.1))
	game.guardian.active = false
	game.guardian.stun(10.0)
	# Simulate the intended recovery choice: retreat from the fight to the known
	# sunlit spawn road. Knockback can otherwise leave the player under an eave.
	player.global_position = Vector3(0, 0.1, 24)
	player.velocity = Vector3.ZERO
	await _wait_frames(3)
	if game._is_player_in_shadow():
		_fail("Known sunlit recovery point became shadowed")
	game.recovery_cooldown = 0.0
	await create_timer(0.75).timeout
	if game.health <= damaged_health:
		_fail("Health did not recover in sunlight after combat")
	else:
		print("COMBAT sunlight recovery verified: health=", snappedf(game.health, 0.1))
	var charge_health: float = game.health
	_setup_charge_encounter()
	if not await _wait_for_charge_windup():
		_fail("Guardian did not prepare a clear-path charge after the second seal")
		return
	player.set_touch_move(Vector2(1, 0))
	for _frame in range(90):
		await physics_frame
	player.set_touch_move(Vector2.ZERO)
	if game.health < charge_health:
		_fail("Lateral movement did not evade the locked charge direction")
		return
	print("CHARGE dodge verified: health=", snappedf(game.health, 0.1), " lateral_x=", snappedf(player.global_position.x, 0.1))
	_setup_charge_encounter()
	if not await _wait_for_charge_windup():
		_fail("Guardian did not prepare a second charge for interruption")
		return
	player.stamina = player.max_stamina
	game.sun_pulse_cooldown = 0.0
	game._try_sun_pulse()
	for _frame in range(5):
		await physics_frame
	if game.guardian.stun_time <= 0.0 or game.guardian.charge_windup > 0.0 or game.guardian.charge_time > 0.0:
		_fail("Sun pulse did not interrupt the Guardian charge")
		return
	print("CHARGE interruption verified: stamina=", snappedf(player.stamina, 0.1))
	_setup_charge_encounter()
	var pre_charge_health: float = game.health
	game.recovery_cooldown = 10.0
	elapsed = 0.0
	while game.health >= pre_charge_health and elapsed < 3.0:
		await physics_frame
		elapsed += 1.0 / 60.0
	if game.health >= pre_charge_health:
		_fail("Guardian charge did not damage a stationary player")
		return
	print("CHARGE hit verified: health=", snappedf(game.health, 0.1), " elapsed=", snappedf(elapsed, 0.1))
	game.health = 42.0
	game._update_health_ui()
	player.stamina = 18.0
	player.global_position = Vector3(0, 0.1, -2)
	game.sun_pulse_cooldown = 4.0
	game._try_sun_pulse()
	await _wait_frames(5)
	if not game.totem_used:
		_fail("Totem interaction did not activate near the central shrine")
	elif game.health <= 42.0 or player.stamina <= 18.0:
		_fail("Totem did not restore health and stamina")
	elif game.sun_pulse_cooldown > 0.0 or game.guardian.rage_time <= 0.0:
		_fail("Totem did not recharge the pulse and enrage the Guardian")
	else:
		print("TOTEM risk/reward verified: health=", snappedf(game.health, 0.1),
			" stamina=", snappedf(player.stamina, 0.1), " rage=", snappedf(game.guardian.rage_time, 0.1))
	game._on_guardian_hit(200.0)
	await _wait_frames(3)
	if game.phase != game.Phase.LOST:
		_fail("Lethal damage did not enter the defeat state")
	else:
		print("COMBAT defeat state verified")


func _run_sunset_check() -> void:
	game.queue_free()
	await _wait_frames(4)
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	game = packed_scene.instantiate()
	root.add_child(game)
	await _wait_frames(6)
	player = game.get_node("Player")
	game._start_game()
	game.seals_found = 3
	game.guardian.awaken(3)
	game.health = 50.0
	game._update_health_ui()
	game.recovery_cooldown = 0.0
	game._begin_final_escape(0.08)
	await create_timer(0.22).timeout
	if not game.sunset_triggered or game.lighting_stage != 4:
		_fail("Expired escape timer did not enter the twilight lighting state")
		return
	if game.guardian.rage_time < 50.0 or game.phase != game.Phase.PLAYING:
		_fail("Sunset did not enrage the Guardian while keeping the run playable")
		return
	var sunset_health: float = game.health
	await create_timer(0.7).timeout
	if game.health > sunset_health + 0.05:
		_fail("Health still recovered in sunlight after sunset")
		return
	game._on_exit_entered(player)
	await _wait_frames(2)
	if game.phase != game.Phase.WON or game.end_title.text != game._text("win_title_late"):
		_fail("A late escape did not produce the alternate twilight victory")
		return
	print("SUNSET overtime verified: healing_stopped health=", snappedf(game.health, 0.1), " late_win=true")
	# Let the asynchronous end-screen interstitial delay resolve before teardown.
	await create_timer(0.85).timeout


func _setup_charge_encounter() -> void:
	player.set_touch_move(Vector2.ZERO)
	player.global_position = Vector3(0, 0.1, 24)
	player.velocity = Vector3.ZERO
	player.planar_velocity = Vector3.ZERO
	game.guardian.reset_guardian()
	game.guardian.global_position = Vector3(0, 0.1, 18)
	game.guardian.awaken(2)
	game.guardian.attack_cooldown = 0.0
	game.guardian.charge_cooldown = 0.0


func _check_camera_motion() -> bool:
	var camera: Camera3D = player.get_node("Head/Camera3D")
	var head: Node3D = player.get_node("Head")
	var audio_events_before: int = game.audio.event_play_count
	var max_fov := camera.fov
	var max_offset := 0.0
	var max_roll := 0.0
	Input.action_press("sprint")
	player.set_touch_move(Vector2(0.48, -1.0).normalized())
	for _frame in range(42):
		await physics_frame
		max_fov = maxf(max_fov, camera.fov)
		max_offset = maxf(max_offset, camera.position.length())
		max_roll = maxf(max_roll, absf(head.rotation.z))
	Input.action_release("sprint")
	player.set_touch_move(Vector2.ZERO)
	for _frame in range(80):
		await physics_frame
	if max_fov < 78.0 or max_offset < 0.008 or max_roll < 0.003:
		_fail("Sprint camera feedback did not produce FOV, bob and lean changes")
		return false
	if game.audio.event_play_count <= audio_events_before or game.audio.last_event != "step":
		_fail("Physical movement did not emit procedural footstep audio")
		return false
	if absf(camera.fov - 76.0) > 0.2 or camera.position.length() > 0.004 or absf(head.rotation.z) > 0.002:
		_fail("Camera motion did not settle back to its neutral transform")
		return false
	player.reset_to_spawn()
	print("CAMERA motion verified: peak_fov=", snappedf(max_fov, 0.1),
		" bob=", snappedf(max_offset, 0.001), " roll_deg=", snappedf(rad_to_deg(max_roll), 0.1))
	return true


func _check_audio_system() -> bool:
	var audio = game.audio
	if audio.sounds.size() != 9 or audio.voices.size() != audio.VOICE_COUNT:
		_fail("Procedural audio bank or fixed voice pool was not created")
		return false
	if audio.generated_sample_bytes < 200000:
		_fail("Procedural audio waveforms were not fully synthesized in memory")
		return false
	var child_count_before: int = audio.get_child_count()
	var events_before: int = audio.event_play_count
	for event_name in audio.sounds.keys():
		audio.play_event(event_name)
	await _wait_frames(3)
	if audio.get_child_count() != child_count_before or audio.event_play_count - events_before != audio.sounds.size():
		_fail("Audio playback created leaking nodes or skipped generated events")
		return false
	if audio.active_voice_count() > audio.VOICE_COUNT:
		_fail("Procedural audio exceeded its fixed voice budget")
		return false
	print("AUDIO bank verified: events=", audio.sounds.size(), " voices=", audio.voices.size(),
		" generated_kb=", snappedf(audio.generated_sample_bytes / 1024.0, 0.1))
	return true


func _wait_for_charge_windup() -> bool:
	var elapsed := 0.0
	while game.guardian.charge_windup <= 0.0 and elapsed < 2.0:
		await physics_frame
		elapsed += 1.0 / 60.0
	return game.guardian.charge_windup > 0.0


func _check_shadow_logic() -> void:
	if game._is_position_in_shadow(Vector3(0, 0.1, 24)):
		_fail("Spawn point is unexpectedly classified as shadow")
	var shadowed := 0
	var sunlit := 0
	for x in range(-17, -3, 2):
		for z in range(9, 23, 2):
			if game._is_position_in_shadow(Vector3(float(x), 0.1, float(z))):
				shadowed += 1
			else:
				sunlit += 1
	if shadowed == 0 or sunlit == 0:
		_fail("Physical shadow query did not produce both lit and shadowed samples (%d/%d)" % [sunlit, shadowed])
	else:
		print("SHADOW CHECK: sunlit=", sunlit, " shadowed=", shadowed)


func _move_to(target: Vector3, timeout: float) -> void:
	var elapsed := 0.0
	var last_distance := INF
	var stuck_time := 0.0
	while Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() > 0.72:
		if game.phase != game.Phase.PLAYING:
			return
		var delta_position := target - player.global_position
		delta_position.y = 0.0
		var local_direction := player.global_transform.basis.inverse() * delta_position.normalized()
		player.set_touch_move(Vector2(local_direction.x, local_direction.z))
		await physics_frame
		elapsed += 1.0 / 60.0
		var distance := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
		if distance >= last_distance - 0.002:
			stuck_time += 1.0 / 60.0
		else:
			stuck_time = 0.0
		last_distance = distance
		if stuck_time > 1.0:
			_fail("Blocked on route near %s while moving to %s" % [player.global_position, target])
			return
		if elapsed > timeout:
			_fail("Timed out moving to %s from %s" % [target, player.global_position])
			return
	player.set_touch_move(Vector2.ZERO)
	await _wait_frames(3)


func _fail(message: String) -> void:
	failures.append(message)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _wait_seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await process_frame
		elapsed += 1.0 / 60.0
