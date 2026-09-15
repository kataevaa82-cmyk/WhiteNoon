extends SceneTree

## Замер расстановки: разброс печатей по карте и прежние гарантии аудита —
## никто не стоит в препятствии, объекты не липнут друг к другу. Автотест
## следит за разбросом, а проникновение и зазор измеряются здесь.

const FLOW := preload("res://scripts/game_flow.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("lvl | seals | near | far | max_gap° | penetration | min_gap | sector_miss | fallback")
	var worst_pen := 0.0
	var worst_gap := INF
	var worst_near := 0.0
	var misses := 0
	var fallbacks := 0
	for number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var level := (load(FLOW.challenge_path(number)) as PackedScene).instantiate()
		root.add_child(level)
		await process_frame
		await process_frame
		var nearest := INF
		var farthest := 0.0
		var angles: Array[float] = []
		for seal in level.seal_nodes:
			var point: Vector3 = seal.global_position
			var distance: float = point.distance_to(level.SPAWN_POINT)
			nearest = minf(nearest, distance)
			farthest = maxf(farthest, distance)
			angles.append(Vector2(point.x, point.z).angle())
		var widest := _widest_gap(angles)
		var placed := _placed_points(level)
		var pen := 0.0
		for point in placed:
			for circle in level.obstacle_circles:
				pen = maxf(pen, circle.z - Vector2(point.x - circle.x, point.z - circle.y).length())
		var gap := INF
		for i in range(placed.size()):
			for j in range(i + 1, placed.size()):
				gap = minf(gap, placed[i].distance_to(placed[j]))
		print("%3d | %5d | %4.1f | %4.1f | %8d | %11.2f | %7.2f | %11d | %8d" % [
			number, level.seals_required, nearest, farthest, int(widest),
			pen, gap, level.sector_misses, level.fallback_spots])
		worst_pen = maxf(worst_pen, pen)
		worst_gap = minf(worst_gap, gap)
		worst_near = maxf(worst_near, nearest)
		misses += level.sector_misses
		fallbacks += level.fallback_spots
		level.audio.stop_all()
		level.queue_free()
		for _f in range(3):
			await process_frame
	print("SUMMARY worst_penetration=%.2f min_object_gap=%.2f worst_nearest_seal=%.1f sector_misses=%d fallbacks=%d" % [
		worst_pen, worst_gap, worst_near, misses, fallbacks])
	await create_timer(0.25).timeout
	quit(0)

## Самый широкий пустой сектор: если печати сбились в кучу, где-то зияет дыра
## почти на полкруга — именно так выглядел сломанный второй уровень.
static func _widest_gap(angles: Array[float]) -> float:
	if angles.size() < 2:
		return 360.0
	var sorted: Array[float] = angles.duplicate()
	sorted.sort()
	var widest := 0.0
	for index in range(sorted.size()):
		var next: float = sorted[(index + 1) % sorted.size()]
		var gap: float = next - sorted[index]
		if index == sorted.size() - 1:
			gap += TAU
		widest = maxf(widest, rad_to_deg(gap))
	return widest

func _placed_points(level: Node) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for group in [level.seal_nodes, level.altar_nodes, level.curse_nodes, level.rift_nodes, level.enemies]:
		for node in group:
			if is_instance_valid(node):
				points.append((node as Node3D).global_position)
	points.append(level.totem_point)
	return points
