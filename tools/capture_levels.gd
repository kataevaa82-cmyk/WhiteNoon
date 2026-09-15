extends SceneTree
## Снимает обзорные кадры уровней: небо с солнцем и планировку карты.
## Запуск: godot --path . --script tools/capture_levels.gd -- 2 6 13 21

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var levels: Array[int] = []
	var want_main := false
	for arg in args:
		if arg == "main":
			want_main = true
		elif arg.is_valid_int():
			levels.append(int(arg))
	if levels.is_empty() and not want_main:
		want_main = true
		levels = [2, 6, 13, 21]
	if want_main:
		await _capture_main()
	for level in levels:
		await _capture_challenge(level)
	quit(0)

func _capture_main() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await _wait_frames(10)
	game._start_game()
	await _wait_frames(6)
	game.get_node("UI").visible = false
	game.get_node("Player/Head/Camera3D").current = false
	var camera := _make_camera(game)
	await _save_view(camera, Vector3(0.0, 3.4, 22.0), Vector3(0.0, 24.0, -40.0), "res://build/level_01_sky.png")
	await _save_view(camera, Vector3(40.0, 34.0, 44.0), Vector3(0.0, 1.0, -4.0), "res://build/level_01_map.png")
	game.queue_free()
	await _wait_frames(4)

func _capture_challenge(level: int) -> void:
	var path := "res://scenes/%s" % _scene_name(level)
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("No scene for level %d" % level)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_frames(10)
	scene._start_level()
	await _wait_frames(6)
	scene.get_node("ChallengeUI").visible = false
	scene.player.get_node("Head/Camera3D").current = false
	var camera := _make_camera(scene)
	await _save_view(camera, Vector3(0.0, 3.4, 23.0), Vector3(0.0, 24.0, -40.0), "res://build/level_%02d_sky.png" % level)
	await _save_view(camera, Vector3(0.0, 46.0, 34.0), Vector3(0.0, 0.0, -6.0), "res://build/level_%02d_map.png" % level)
	await _save_view(camera, Vector3(1.5, 1.7, 19.0), Vector3(0.0, 1.7, -8.0), "res://build/level_%02d_eye.png" % level)
	scene.queue_free()
	await _wait_frames(4)

func _make_camera(parent: Node) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 66.0
	camera.near = 0.08
	camera.far = 260.0
	parent.add_child(camera)
	camera.current = true
	return camera

func _scene_name(level: int) -> String:
	var names := {
		2: "level_02_kurgans.tscn", 3: "level_03_fires.tscn", 4: "level_04_black_sun.tscn",
		5: "level_05_millstone.tscn", 6: "level_06_ravine.tscn", 7: "level_07_apiary.tscn",
		8: "level_08_ford.tscn", 9: "level_09_pass.tscn", 10: "level_10_fires.tscn",
		11: "level_11_well.tscn", 12: "level_12_circle.tscn", 13: "level_13_dolls.tscn",
		14: "level_14_chapel.tscn", 15: "level_15_round.tscn", 16: "level_16_forest.tscn",
		17: "level_17_debt.tscn", 18: "level_18_night.tscn", 19: "level_19_rite.tscn",
		20: "level_20_mirror.tscn", 21: "level_21_gates.tscn",
	}
	return names.get(level, "level_02_kurgans.tscn")

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
