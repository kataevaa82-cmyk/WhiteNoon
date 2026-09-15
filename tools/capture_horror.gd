extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	var game := packed_scene.instantiate()
	root.add_child(game)
	for _frame in range(8):
		await process_frame
	game._start_game()
	game.get_node("UI").visible = false
	game.get_node("Player/Head/Camera3D").current = false
	game._apply_lighting_stage(3, true)
	var camera := Camera3D.new()
	camera.fov = 54.0
	game.add_child(camera)
	camera.current = true
	await _save_view(camera, Vector3(-12.6, 2.25, 10.3), Vector3(-12.9, 1.75, 5.8), "res://build/horror_window.png")
	await _save_view(camera, Vector3(-1.8, 2.35, 14.0), Vector3(-6.2, 1.35, 9.0), "res://build/horror_effigy.png")
	game._apply_lighting_stage(0, true)
	for _frame in range(4):
		await process_frame
	quit(0)


func _save_view(camera: Camera3D, position: Vector3, target: Vector3, path: String) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	for _frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	else:
		print("Saved preview: ", path)
