extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var packed := load("res://scenes/game_menu.tscn") as PackedScene
	var menu := packed.instantiate()
	root.add_child(menu)
	for _frame in range(8):
		await process_frame
	var show_meadow := OS.get_cmdline_user_args().has("--meadow")
	if show_meadow:
		menu.background_suspended = true
		menu.background_material.set_shader_parameter("blend_value", 1.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var output_path := "res://build/game_menu_meadow.png" if show_meadow else "res://build/game_menu.png"
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save menu preview: %s" % error_string(error))
		quit(1)
	else:
		print("Saved preview: " + output_path)
		quit(0)
