extends SceneTree

## Заливка по сетке доказывает только геометрию и не видит box-коллайдеры.
## Здесь игрок действительно идёт: capsule двигается move_and_collide, поэтому
## любая стена, невидимая для заливки, остановит проход и тест это покажет.

const FLOW := preload("res://scripts/game_flow.gd")
const MOUNTAIN_RING := preload("res://scripts/mountain_ring.gd")
const STEP := 0.09 # шаг капсулы, метры
const CAPSULE_CLEARANCE := 0.45 # радиус капсулы 0.36 плюс запас
const REACH := 1.2 # печати висят над землёй, поэтому меряем по горизонтали

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var path := FLOW.challenge_path(number)
		var level := (load(path) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		level._start_level()
		# Проверяем проходимость, а не бой: стражи только мешали бы замеру.
		for enemy in level.enemies:
			if is_instance_valid(enemy):
				enemy.queue_free()
		level.enemies.clear()
		await physics_frame
		var player: CharacterBody3D = level.player
		player.set_controls_enabled(false)
		var reached := 0
		var walked := 0.0
		var targets := _route(level)
		targets.remove_at(targets.size() - 1)
		for target in targets:
			var result := await _walk_to(player, level, target)
			walked += result.y
			if result.x > 0.0:
				reached += 1
			else:
				_fail("%s: не дошёл до (%.0f, %.0f), встал на (%.1f, %.1f), осталось %.1f м" % [
					path, target.x, target.z, player.global_position.x, player.global_position.z,
					_flat_distance(player.global_position, target)])
		# Ворота открывает только законченный ритуал, поэтому идём к ним последними.
		level.seals_found = level.seals_required
		level.curses_cleansed = level.curse_required
		for altar in level.altar_nodes:
			level._light_altar(altar)
		await physics_frame
		var gate := await _walk_to(player, level, level.GATE_POINT)
		walked += gate.y
		if gate.x > 0.0:
			reached += 1
		else:
			_fail("%s: не дошёл до ворот" % path)
		if reached == targets.size() + 1:
			print("WALK OK: %s цели=%d путь=%.0f м" % [path, reached, walked])
		level.audio.stop_all()
		level.queue_free()
		for _f in range(3):
			await process_frame
	await create_timer(0.25).timeout
	# quit() только просит движок выйти, выполнение идёт дальше — без return
	# успешный прогон доходил до quit(1) и рапортовал провал.
	if failures.is_empty():
		print("WALK PLAYTEST PASS")
		quit(0)
		return
	for failure in failures:
		push_error("WALK PLAYTEST FAIL: " + failure)
	quit(1)

## Игрок идёт жадно: каждый раз к ближайшей ещё не взятой цели, потом к воротам.
func _route(level: Node) -> Array[Vector3]:
	var pending: Array[Vector3] = []
	for seal in level.seal_nodes:
		pending.append(seal.global_position)
	for altar in level.altar_nodes:
		pending.append(altar.global_position)
	var ordered: Array[Vector3] = []
	var at: Vector3 = level.SPAWN_POINT
	while not pending.is_empty():
		var best := 0
		for index in range(1, pending.size()):
			if at.distance_to(pending[index]) < at.distance_to(pending[best]):
				best = index
		at = pending[best]
		ordered.append(at)
		pending.remove_at(best)
	ordered.append(level.GATE_POINT)
	return ordered

## Возвращает (дошёл, пройденное расстояние). Ведём капсулу по клеточному
## маршруту, но каждый шаг делаем через физику.
func _walk_to(player: CharacterBody3D, level: Node, target: Vector3) -> Vector2:
	var walked := 0.0
	for replan in range(6):
		var leg := await _walk_leg(player, level, target)
		walked += leg.y
		if leg.x > 0.0:
			return Vector2(1.0, walked)
	return Vector2(0.0, walked)

func _walk_leg(player: CharacterBody3D, level: Node, target: Vector3) -> Vector2:
	var waypoints := _grid_path(level, player.global_position, target)
	if waypoints.is_empty():
		print("   [диагноз] маршрут не построен из (%.1f, %.1f) в (%.0f, %.0f)" % [
			player.global_position.x, player.global_position.z, target.x, target.z])
		return Vector2(0.0, 0.0)
	var walked := 0.0
	var budget := 40000
	for waypoint in waypoints:
		var stuck := 0
		while budget > 0:
			budget -= 1
			var flat := Vector3(waypoint.x, player.global_position.y, waypoint.z)
			var delta := flat - player.global_position
			if delta.length() <= STEP:
				player.global_position = flat
				break
			var before := player.global_position
			var hit := player.move_and_collide(delta.normalized() * STEP)
			if hit != null:
				# Скользим вдоль стены — так же, как это делает move_and_slide.
				player.move_and_collide(hit.get_remainder().slide(hit.get_normal()))
			var moved := before.distance_to(player.global_position)
			walked += moved
			if moved < STEP * 0.25:
				stuck += 1
				# Вогнутый угол между двумя пряслами: скольжение по нормали
				# гасит шаг в ноль. Отходим вбок вдоль препятствия.
				if stuck % 12 == 0:
					var side := Vector3(delta.z, 0.0, -delta.x).normalized()
					if (stuck / 12) % 2 == 0:
						side = -side
					for _slide in range(10):
						player.move_and_collide(side * STEP)
				if stuck > 96:
					return Vector2(0.0, walked)
			else:
				stuck = 0
			if budget % 200 == 0:
				await physics_frame
		if _flat_distance(player.global_position, target) <= REACH:
			return Vector2(1.0, walked)
	await physics_frame
	return Vector2(1.0 if _flat_distance(player.global_position, target) <= REACH else 0.0, walked)

func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()

func _grid_path(level: Node, from: Vector3, to: Vector3) -> Array[Vector3]:
	var size: int = level.GRID_SIZE
	var blocked := PackedByteArray()
	blocked.resize(size * size)
	# PLAYER_CLEARANCE (0.7) — запас расстановки, он шире капсулы (радиус 0.36).
	# Игрок физически протискивается там, где эта сетка видит стену, и попадал
	# в «карман», из которого заливка не находила выхода. Планируем по реальному
	# габариту капсулы с небольшим запасом.
	for circle in level.obstacle_circles:
		level._stamp(blocked, circle, CAPSULE_CLEARANCE)
	# Стена по подошве гор — тоже box-коллайдеры: за неё ходу нет.
	for iz in range(size):
		var mz: float = level._grid_position(iz)
		for ix in range(size):
			var mx: float = level._grid_position(ix)
			var here := Vector2(mx, mz)
			if here.length() > MOUNTAIN_RING.blocking_radius(here.angle()) - 1.0:
				blocked[ix + iz * size] = 1
	# Заслон ворот — box-коллайдер, а обходятся только obstacle_circles: без
	# этого маршрут вёл сквозь запертые ворота и капсула упиралась в них.
	if not level.exit_open:
		for iz in range(size):
			var z: float = level._grid_position(iz)
			if z < -28.1 or z > -25.9:
				continue
			for ix in range(size):
				if absf(level._grid_position(ix)) <= 2.9:
					blocked[ix + iz * size] = 1
	var start := Vector2i(level._grid_index(from.x), level._grid_index(from.z))
	var goal := Vector2i(level._grid_index(to.x), level._grid_index(to.z))
	var came := {}
	var queue: Array[Vector2i] = [start]
	came[start] = start
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var head := 0
	var found := false
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == goal:
			found = true
			break
		for step in steps:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
				continue
			if came.has(next) or blocked[next.x + next.y * size] == 1:
				continue
			came[next] = cell
			queue.append(next)
	var route: Array[Vector3] = []
	if not found:
		# Цель может стоять вплотную к стене — идём к ближайшей достигнутой клетке.
		var best: Vector2i = start
		var best_distance := INF
		for cell in came.keys():
			var distance: float = Vector2(cell - goal).length()
			if distance < best_distance:
				best_distance = distance
				best = cell
		if best_distance > 2.5:
			return route
		goal = best
	var cursor: Vector2i = goal
	while cursor != start:
		route.push_front(Vector3(level._grid_position(cursor.x), 0.0, level._grid_position(cursor.y)))
		cursor = came[cursor]
	return route

func _fail(message: String) -> void:
	failures.append(message)
