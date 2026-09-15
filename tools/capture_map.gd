extends SceneTree


func _initialize() -> void:
	call_deferred("_capture_map")


func _capture_map() -> void:
	var service := root.get_node_or_null("YandexService")
	if service != null:
		service.detected_language = "en" if OS.get_cmdline_user_args().has("--en") else "ru"
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	var game := packed_scene.instantiate()
	root.add_child(game)

	await _wait_frames(8)
	game._start_game()
	await _wait_frames(5)
	await RenderingServer.frame_post_draw
	var hud_image := root.get_viewport().get_texture().get_image()
	var hud_error := hud_image.save_png("res://build/gameplay_hud.png")
	if hud_error != OK:
		push_error("Could not save gameplay HUD: %s" % error_string(hud_error))
	game.seals_found = 3
	game._begin_final_escape()
	game.hint.text = game._text("last_seal")
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var escape_hud_image := root.get_viewport().get_texture().get_image()
	var escape_hud_error := escape_hud_image.save_png("res://build/final_escape_hud.png")
	if escape_hud_error != OK:
		push_error("Could not save final escape HUD: %s" % error_string(escape_hud_error))
	else:
		print("Saved preview: res://build/final_escape_hud.png")
	game.seals_found = 0
	game.escape_time_remaining = 0.0
	game.sunset_triggered = false
	game.guardian.reset_guardian()
	game.exit_path.visible = false
	game._update_objective_text()
	game.get_node("UI").visible = false
	game.get_node("Player/Head/Camera3D").current = false

	var camera := Camera3D.new()
	camera.fov = 57.0
	camera.far = 140.0
	game.add_child(camera)
	camera.current = true

	await _save_view(
		camera,
		Vector3(42.0, 37.0, 47.0),
		Vector3(0.0, 1.0, -2.0),
		"res://build/map_overview.png"
	)
	await _save_view(
		camera,
		Vector3(0.0, 4.2, 25.0),
		Vector3(0.0, 2.2, -8.0),
		"res://build/map_player_view.png"
	)
	await _save_view(
		camera,
		Vector3(0.0, 4.0, -16.0),
		Vector3(0.0, 1.9, -37.0),
		"res://build/gate_pass_view.png"
	)
	await _save_view(
		camera,
		Vector3(3.8, 2.8, 8.4),
		Vector3(0.0, 2.0, 5.0),
		"res://build/guardian_closeup.png"
	)
	await _save_view(
		camera,
		Vector3(4.8, 3.0, 2.5),
		Vector3(0.0, 2.0, -2.0),
		"res://build/totem_view.png"
	)
	game.seals_found = 1
	game.get_node("Player").stamina = game.get_node("Player").max_stamina
	game.sun_pulse_cooldown = 0.0
	game._try_sun_pulse()
	await _save_view(
		camera,
		Vector3(-5.0, 5.0, 24.0),
		Vector3(-16.0, 3.0, 17.0),
		"res://build/seal_beacon.png"
	)
	game._apply_lighting_stage(3, true)
	game._reveal_exit_path()
	for ward_index in range(3):
		game._release_gate_ward(ward_index)
	await create_timer(0.6).timeout
	await _save_view(
		camera,
		Vector3(36.0, 27.0, 39.0),
		Vector3(0.0, 1.0, -4.0),
		"res://build/final_lighting.png"
	)
	await _save_view(
		camera,
		Vector3(0.0, 4.0, -18.0),
		Vector3(0.0, 1.0, -38.0),
		"res://build/open_gate_path.png"
	)
	game.sunset_triggered = true
	game._apply_lighting_stage(4, true)
	await _save_view(
		camera,
		Vector3(33.0, 25.0, 38.0),
		Vector3(0.0, 1.0, -4.0),
		"res://build/twilight_overview.png"
	)
	await _save_view(
		camera,
		Vector3(0.0, 3.0, 24.0),
		Vector3(0.0, 1.5, -8.0),
		"res://build/twilight_player_view.png"
	)
	await _save_view(
		camera,
		Vector3(0.0, 3.8, -18.0),
		Vector3(0.0, 1.2, -38.0),
		"res://build/twilight_gate.png"
	)
	# Let the renderer release the temporary alternate ambient pipeline before
	# shutting down after a batch of screenshots.
	game._apply_lighting_stage(0, true)
	await _wait_frames(4)
	quit(0)


func _save_view(camera: Camera3D, position: Vector3, target: Vector3, path: String) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	await _wait_frames(8)
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
