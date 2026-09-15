extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game := scene.instantiate()
	root.add_child(game)
	for _frame in range(8):
		await process_frame
	game._start_game()
	game.run_time = 83.0
	game.hits_taken = 2
	game.pulses_used = 3
	game.charges_dodged = 1
	game._finish(true)
	for _frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png("res://build/result_screen.png")
	if error != OK:
		push_error("Could not save result screen: %s" % error_string(error))
		quit(1)
	else:
		print("Saved preview: res://build/result_screen.png")
		quit(0)
