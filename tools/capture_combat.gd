extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var service := root.get_node_or_null("YandexService")
	if service != null:
		service.detected_language = "en" if OS.get_cmdline_user_args().has("--en") else "ru"
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	var game := packed_scene.instantiate()
	root.add_child(game)
	await _wait_frames(10)
	game._start_game()
	game.seals_found = 1
	game.guardian.global_position = Vector3(0, 0.1, 20.5)
	game.guardian.awaken(1)
	var timeout := 0
	while game.guardian.attack_windup <= 0.0 and timeout < 240:
		await physics_frame
		timeout += 1
	await _wait_frames(9)
	await _save("res://build/combat_telegraph.png")
	game.player.stamina = game.player.max_stamina
	game.sun_pulse_cooldown = 0.0
	game._try_sun_pulse()
	await _wait_frames(4)
	await _save("res://build/sun_pulse.png")
	game.guardian.stun_time = 0.0
	game.guardian.attack_cooldown = 0.0
	game.guardian.charge_cooldown = 0.0
	game.guardian.global_position = Vector3(0, 0.1, 18.0)
	game.guardian.awaken(2)
	timeout = 0
	while game.guardian.charge_windup <= 0.0 and timeout < 240:
		await physics_frame
		timeout += 1
	await _wait_frames(8)
	await _save("res://build/charge_telegraph.png")
	game.guardian.reset_guardian()
	game.health = 20.0
	game._update_health_ui()
	game.hint.text = ""
	await _wait_frames(12)
	await _save("res://build/low_health_feedback.png")
	quit(0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	else:
		print("Saved preview: ", path)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
