extends SceneTree
## Captures landscape Yandex Games screenshots with the real mobile HUD enabled.
## Run: godot --path . --script res://tools/capture_mobile_promo.gd -- --en


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var language := "en" if OS.get_cmdline_user_args().has("--en") else "ru"
	var service := root.get_node_or_null("YandexService")
	if service != null:
		service.detected_language = language
	var output_dir := "res://promo/yandex/screenshots_mobile/%s" % language
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	await _capture_story(output_dir)
	await _capture_dolls(output_dir)
	await _capture_gates(output_dir)
	quit(0)


func _capture_story(output_dir: String) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await _wait_frames(10)
	game._start_game()
	game.get_node("UI/TouchControls").visible = true
	game.get_node("UI/TouchControls").queue_redraw()
	game.get_node("UI/Crosshair").visible = false
	game.seals_found = 1
	game.objective.text = game._text("seals") % game.seals_found
	game.guardian.global_position = game.player.global_position + Vector3(0.8, 0.1, -7.0)
	game.guardian.awaken(2)
	game.guardian.stun(1.8)
	await _wait_frames(8)
	await _save("%s/01_story_touch.png" % output_dir)
	game.queue_free()
	await _wait_frames(4)


func _capture_dolls(output_dir: String) -> void:
	var packed := load("res://scenes/level_13_dolls.tscn") as PackedScene
	var level := packed.instantiate()
	root.add_child(level)
	await _wait_frames(10)
	level._start_level()
	level.touch_controls.visible = true
	level.touch_controls.queue_redraw()
	level.get_node("ChallengeUI/Crosshair").visible = false
	level.seals_found = 3
	level.pulse_cooldown = 0.0
	level.player.stamina = level.player.max_stamina
	level._update_hud()
	if not level.enemies.is_empty():
		var enemy: CharacterBody3D = level.enemies[0]
		enemy.global_position = level.player.global_position + Vector3(-0.8, 0.1, -6.4)
		enemy.awaken(4)
		enemy.stun(1.8)
	level._try_sun_pulse()
	await _wait_frames(3)
	await _save("%s/02_dolls_pulse_touch.png" % output_dir)
	level.queue_free()
	await _wait_frames(4)


func _capture_gates(output_dir: String) -> void:
	var packed := load("res://scenes/level_21_gates.tscn") as PackedScene
	var level := packed.instantiate()
	root.add_child(level)
	await _wait_frames(10)
	level._start_level()
	level.touch_controls.visible = true
	level.touch_controls.queue_redraw()
	level.get_node("ChallengeUI/Crosshair").visible = false
	level.player.global_position = Vector3(0.0, 0.15, -17.0)
	level.player.rotation.y = 0.0
	level.player.pitch = deg_to_rad(-3.0)
	level.player.get_node("Head").rotation.x = level.player.pitch
	level.seals_found = level.seals_required
	level.curses_cleansed = level.curse_required
	level.altars_lit = level.altar_required
	level._update_hud()
	level.objective_beacon.visible = false
	for enemy in level.enemies:
		enemy.visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	level._open_gate()
	await _wait_frames(90)
	level.hint.text = ""
	await _wait_frames(2)
	await _save("%s/03_open_gate_touch.png" % output_dir)
	level.queue_free()
	await _wait_frames(4)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	else:
		print("Saved mobile promo: ", path)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
