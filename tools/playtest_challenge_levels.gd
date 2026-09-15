extends SceneTree

const FLOW := preload("res://scripts/game_flow.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var paths := _challenge_paths()
	if paths.size() != FLOW.LAST_CHALLENGE - FLOW.FIRST_CHALLENGE + 1:
		_fail("Expected 20 challenge scenes, got %d" % paths.size())
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("Could not load " + path)
			continue
		var level := packed.instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		if level.seal_nodes.size() != level.seals_required:
			_fail("Seal count mismatch in " + path)
		if level.altar_nodes.size() != level.altar_required:
			_fail("Altar count mismatch in " + path)
		if level.enemies.size() != level.enemy_count:
			_fail("Enemy count mismatch in " + path)
		# Чучела раньше не сверялись: тест пользовался curse_required, но ни разу
		# не проверил, что столько же их и создано.
		if level.curse_nodes.size() != level.curse_required:
			_fail("Curse count mismatch in " + path)
		var expected_traps := 0 if level.level_number < 5 else (2 if level.level_number >= 14 else 1)
		if level.trap_zones.size() != expected_traps:
			_fail("Trap count mismatch in " + path)
		if FLOW.challenge_path(level.level_number) != path:
			_fail("Level routing mismatch in " + path)
		if level.level_number < FLOW.LAST_CHALLENGE and FLOW.next_challenge_path(level.level_number).is_empty():
			_fail("Next-level routing is missing in " + path)
		if level.level_number == FLOW.LAST_CHALLENGE and FLOW.has_next_challenge(level.level_number):
			_fail("Final challenge unexpectedly has a successor in " + path)
		var expected_rifts := clampi(int(float(level.level_number - 3) / 2.0), 0, 8)
		if level.rift_nodes.size() != expected_rifts:
			_fail("Rift progression mismatch in " + path)
		_check_layout(level, path)
		level._start_level()
		if level.state != level.RunState.PLAYING:
			_fail("Level did not enter PLAYING state in " + path)
		if level.level_number == FLOW.FIRST_CHALLENGE:
			level._apply_language("en")
			if not level.intro_title_label.text.begins_with("LEVEL "):
				_fail("English challenge title was not applied in " + path)
			if not level.objective.text.begins_with("SEALS"):
				_fail("English challenge HUD was not applied in " + path)
			level._apply_language("ru")
		if level.curse_required > 0:
			level.seals_found = 1
			level.player.stamina = level.player.max_stamina
			var curse := level.curse_nodes[0] as Area3D
			level.player.global_position = curse.global_position
			level._on_interactable_entered(level.player, curse)
			level._handle_action()
			await process_frame
			if level.curses_cleansed != 1:
				_fail("E interaction did not cleanse a nearby curse in " + path)
		if not level.trap_zones.is_empty():
			var enemy = level.enemies[0]
			enemy.awaken(1)
			level._on_trap_body_entered(enemy, level.trap_zones[0])
			await process_frame
			if not enemy.trapped or level.trap_zones[0].get_meta("armed", true):
				_fail("Sun trap did not capture a Guardian in " + path)
		level.seals_found = level.seals_required
		level.curses_cleansed = level.curse_required
		for altar in level.altar_nodes:
			level._light_altar(altar)
		await process_frame
		if not level.exit_open or not level.gate_blocker.disabled:
			_fail("Final ritual did not open the exit in " + path)
		print("CHALLENGE OK: ", path, " seals=", level.seals_required,
			" curses=", level.curse_required, " altars=", level.altar_required,
			" rifts=", level.rift_nodes.size(), " enemies=", level.enemy_count)
		level.audio.stop_all()
		level.queue_free()
		for _frame in range(4):
			await process_frame
	# Give the headless dummy audio driver one final mix cycle so the last
	# generated WAV playbacks release before SceneTree shutdown.
	await create_timer(0.25).timeout
	if failures.is_empty():
		print("CHALLENGE PLAYTEST PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("CHALLENGE PLAYTEST FAIL: " + failure)
		quit(1)

func _fail(message: String) -> void:
	failures.append(message)

## Планировка у каждого уровня своя, поэтому счётчиков мало: проверяем ещё и
## то, что от точки старта действительно можно дойти до ворот и до каждой цели.
func _check_layout(level: Node, path: String) -> void:
	var unreachable := 0
	var targets: Array[Vector3] = [level.GATE_POINT, level.totem_point]
	for seal in level.seal_nodes:
		targets.append(seal.global_position)
	for altar in level.altar_nodes:
		targets.append(altar.global_position)
	for curse in level.curse_nodes:
		targets.append(curse.global_position)
	for enemy in level.enemies:
		targets.append(enemy.global_position)
	for trap in level.trap_zones:
		targets.append(trap.global_position)
	for target in targets:
		if not _walkable_from_spawn(level, target):
			unreachable += 1
	if unreachable > 0:
		_fail("%d objectives are walled off in %s" % [unreachable, path])
	if level.free_spots.size() < 60:
		_fail("Layout left only %d free spots in %s" % [level.free_spots.size(), path])
	# Запасная точка маршрута не проверяется на препятствия — если до неё дошло,
	# объект мог встать внутрь пряслы или дерева.
	if level.fallback_spots > 0:
		_fail("%d objects fell back to route points in %s" % [level.fallback_spots, path])
	_check_seal_spread(level, path)

## Печати игрок ищет сам, без карты и компаса. Второй уровень когда-то развесил
## все четыре в дальней полосе — до ближайшей было 43 м, и уровень читался как
## непроходимый. Держим первую печать близко и требуем разброса по кругу.
##
## Меряем самый широкий пустой сектор, а не попадание в фиксированные четверти:
## сектора расстановки повёрнуты на случайный угол, поэтому две соседние печати
## законно попадают в одну четверть, и такая проверка врала.
func _check_seal_spread(level: Node, path: String) -> void:
	var nearest := INF
	var angles: Array[float] = []
	for seal in level.seal_nodes:
		nearest = minf(nearest, seal.global_position.distance_to(level.SPAWN_POINT))
		angles.append(Vector2(seal.global_position.x, seal.global_position.z).angle())
	if nearest > 18.0:
		_fail("Nearest seal is %.1f m from spawn in %s" % [nearest, path])
	angles.sort()
	var widest := 0.0
	for index in range(angles.size()):
		var next: float = angles[(index + 1) % angles.size()]
		var gap: float = next - angles[index]
		if index == angles.size() - 1:
			gap += TAU
		widest = maxf(widest, rad_to_deg(gap))
	var allowed := 360.0 / float(level.seals_required) + 60.0
	if widest > allowed:
		_fail("Seals leave a %.0f° empty arc (allowed %.0f°) in %s" % [widest, allowed, path])

func _walkable_from_spawn(level: Node, target: Vector3) -> bool:
	# Уровень уже посчитал заливку от спавна — берём его же сетку препятствий.
	var size: int = level.GRID_SIZE
	var blocked := PackedByteArray()
	blocked.resize(size * size)
	for circle in level.obstacle_circles:
		level._stamp(blocked, circle, level.PLAYER_CLEARANCE)
	var visited := PackedByteArray()
	visited.resize(size * size)
	var start := Vector2i(level._grid_index(level.SPAWN_POINT.x), level._grid_index(level.SPAWN_POINT.z))
	var goal := Vector2i(level._grid_index(target.x), level._grid_index(target.z))
	var queue: Array[Vector2i] = [start]
	visited[start.x + start.y * size] = 1
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if cell == goal:
			return true
		for step in steps:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
				continue
			var index: int = next.x + next.y * size
			if visited[index] == 1 or blocked[index] == 1:
				continue
			visited[index] = 1
			queue.append(next)
	# Цель может стоять вплотную к стене — считаем достижимой, если рядом
	# есть свободная клетка, до которой заливка дошла.
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var near: Vector2i = goal + offset
		if near.x < 0 or near.y < 0 or near.x >= size or near.y >= size:
			continue
		if visited[near.x + near.y * size] == 1:
			return true
	return false

func _challenge_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at("res://scenes"):
		if not file.begins_with("level_") or not file.ends_with(".tscn"):
			continue
		var number := int(file.substr(6, 2))
		if number >= FLOW.FIRST_CHALLENGE and number <= FLOW.LAST_CHALLENGE:
			paths.append("res://scenes/" + file)
	paths.sort()
	return paths
