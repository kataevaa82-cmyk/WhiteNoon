extends SceneTree
const FLOW := preload("res://scripts/game_flow.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	print("Подошва гор начинается с радиуса 28.0")
	print("лвл | объектов за R=28 | худший радиус | что именно")
	var total := 0
	for number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var level := (load(FLOW.challenge_path(number)) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		var bad := 0
		var worst := 0.0
		var names: Array[String] = []
		for group in [level.seal_nodes, level.altar_nodes, level.curse_nodes, level.enemies]:
			for node in group:
				if not is_instance_valid(node): continue
				var n := node as Node3D
				var r: float = Vector2(n.global_position.x, n.global_position.z).length()
				worst = maxf(worst, r)
				if r > 28.0:
					bad += 1
					if names.size() < 3: names.append("%s r=%.1f" % [n.name, r])
		total += bad
		print("%3d | %2d | %.1f | %s" % [number, bad, worst, ", ".join(names)])
		level.audio.stop_all(); level.queue_free()
		for _f in range(3): await process_frame
	print("ВСЕГО объектов внутри гор: ", total)
	quit(0)
	return
