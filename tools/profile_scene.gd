extends SceneTree


func _initialize() -> void:
	call_deferred("_profile")


func _profile() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	var game := packed_scene.instantiate()
	root.add_child(game)
	await _wait_frames(12)
	game._start_game()
	game.guardian.awaken(3)
	game._apply_lighting_stage(4, true)
	game._reveal_exit_path()
	await _wait_frames(180)
	print("PROFILE fps=", Performance.get_monitor(Performance.TIME_FPS))
	print("PROFILE draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("PROFILE primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("PROFILE nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("PROFILE static_memory_mb=", snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1))
	quit(0)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
