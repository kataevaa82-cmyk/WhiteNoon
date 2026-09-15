extends SceneTree

## Сверка «сколько обещано» и «сколько создано» по каждому типу объектов на
## всех двадцати уровнях, плюс связность: печать без сигнала не засчитается,
## два объекта в одной точке — это потерянная цель.

const FLOW := preload("res://scripts/game_flow.gd")

var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("лвл | печати | огни | чучела | разломы | стражи | колодец")
	var previous := {"seals": 0, "altars": 0, "enemies": 0}
	for number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var path := FLOW.challenge_path(number)
		var level := (load(path) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		var expected_rifts := clampi(int(float(number - 3) / 2.0), 0, 8)
		var seals := _count(level.seal_nodes)
		var altars := _count(level.altar_nodes)
		var curses := _count(level.curse_nodes)
		var rifts := _count(level.rift_nodes)
		var foes := _count(level.enemies)
		_expect(seals, level.seals_required, "печати", path)
		_expect(altars, level.altar_required, "огни", path)
		_expect(curses, level.curse_required, "чучела", path)
		_expect(rifts, expected_rifts, "разломы", path)
		_expect(foes, level.enemy_count, "стражи", path)
		# Печать без подключённого сигнала нельзя поднять — уровень встанет.
		for seal in level.seal_nodes:
			if not seal.collected.is_connected(level._on_seal_collected):
				problems.append("%s: %s без сигнала подъёма" % [path, seal.name])
		for altar in level.altar_nodes:
			if not altar.has_meta("lit"):
				problems.append("%s: огонь без метки lit" % path)
		for curse in level.curse_nodes:
			if not curse.has_meta("cleansed"):
				problems.append("%s: чучело без метки cleansed" % path)
		var well: Node = level.get_node_or_null("SunWell")
		_check_unique(level, path)
		# Сложность не должна проседать от уровня к уровню.
		if level.seals_required < previous.seals:
			problems.append("%s: печатей меньше, чем на прошлом уровне" % path)
		if level.altar_required < previous.altars:
			problems.append("%s: огней меньше, чем на прошлом уровне" % path)
		if level.enemy_count < previous.enemies:
			problems.append("%s: стражей меньше, чем на прошлом уровне" % path)
		previous = {"seals": level.seals_required, "altars": level.altar_required,
			"enemies": level.enemy_count}
		print("%3d | %2d/%-3d | %2d/%-2d | %2d/%-4d | %2d/%-5d | %2d/%-4d | %s" % [
			number, seals, level.seals_required, altars, level.altar_required,
			curses, level.curse_required, rifts, expected_rifts, foes, level.enemy_count,
			"есть" if well != null else "НЕТ"])
		if well == null:
			problems.append("%s: нет солнечного колодца" % path)
		level.audio.stop_all()
		level.queue_free()
		for _f in range(3):
			await process_frame
	await _audit_story()
	await create_timer(0.25).timeout
	if problems.is_empty():
		print("COUNT AUDIT PASS")
		quit(0)
		return
	for problem in problems:
		push_error("COUNT AUDIT FAIL: " + problem)
	quit(1)

## В сюжете три печати вписаны числом в шести местах — и в текст «Печати: %d / 3»,
## и в четыре сравнения. Список координат живёт отдельно, так что расхождение
## сделало бы уровень непроходимым молча.
func _audit_story() -> void:
	var story := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(story)
	await process_frame
	await process_frame
	var spawned: int = story.seal_nodes.size()
	if spawned != 3:
		problems.append("main.tscn: создано %d печатей, а логика ждёт 3" % spawned)
	var wording: String = story.TEXT["ru"]["seals"] % 0
	if not wording.ends_with("/ 3"):
		problems.append("main.tscn: счётчик в HUD обещает не 3 печати: " + wording)
	print("сюжет | печати %d/3 | HUD «%s»" % [spawned, wording])
	story.queue_free()
	for _f in range(3):
		await process_frame

func _count(nodes: Array) -> int:
	var alive := 0
	for node in nodes:
		if is_instance_valid(node):
			alive += 1
	return alive

func _expect(actual: int, wanted: int, what: String, path: String) -> void:
	if actual != wanted:
		problems.append("%s: %s — создано %d, обещано %d" % [path, what, actual, wanted])

## Две цели в одной точке читаются игроком как одна: счётчик никогда не сойдётся.
func _check_unique(level: Node, path: String) -> void:
	var points: Array[Vector3] = []
	for group in [level.seal_nodes, level.altar_nodes, level.curse_nodes]:
		for node in group:
			if is_instance_valid(node):
				points.append((node as Node3D).global_position)
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) < 1.5:
				problems.append("%s: две цели почти в одной точке (%.1f, %.1f)" % [
					path, points[i].x, points[i].z])
