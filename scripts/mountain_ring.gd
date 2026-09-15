extends RefCounted

## Кольцо гор — только модель, коллайдера у неё нет: игрок уходил в склон, а
## цели вставали внутрь горы. Профиль повторяет tools/build_models.py, чтобы
## стена встала ровно по подошве и не перегородила северный перевал, по
## которому уходит дорога.

const RINGS := [
	Vector2(28.0, -0.45),
	Vector2(31.5, 3.2),
	Vector2(36.0, 11.0),
	Vector2(40.5, 5.2),
	Vector2(47.0, 0.0),
]
const WALK_HEIGHT := 1.2 # выше этого склон уже не перешагнуть
const OPEN_RADIUS := 33.0 # дальше стену не ставим: это перевал

## Угол в системе генератора: Blender +Y смотрит в Godot -Z.
static func ring_point(index: int, angle: float) -> Vector2:
	var ring: Vector2 = RINGS[index]
	var ridge_noise := sin(angle * 7.0 + 0.8) * 1.7 + sin(angle * 13.0 - 0.4) * 0.9
	var pass_delta := absf(atan2(sin(angle - PI / 2.0), cos(angle - PI / 2.0)))
	var height := ring.y
	if index == 1 or index == 2 or index == 3:
		var full_height := ring.y + ridge_noise * (1.0 if index == 2 else 0.45)
		var pass_blend := minf(1.0, pass_delta / 0.42)
		pass_blend = pass_blend * pass_blend * (3.0 - 2.0 * pass_blend)
		var valley_height: float = [0.16, 0.34, 0.24][index - 1]
		height = valley_height + (full_height - valley_height) * pass_blend
	var jitter := sin(angle * 11.0 + float(index) * 1.9) * (0.25 if index == 0 or index == 4 else 0.65)
	return Vector2(ring.x + jitter, height)

static func surface(angle: float, radius: float) -> float:
	var points: Array[Vector2] = []
	for index in range(RINGS.size()):
		points.append(ring_point(index, angle))
	if radius <= points[0].x:
		return points[0].y
	for index in range(points.size() - 1):
		var near: Vector2 = points[index]
		var far: Vector2 = points[index + 1]
		if radius <= far.x:
			var span := maxf(1e-5, far.x - near.x)
			return near.y + (far.y - near.y) * (radius - near.x) / span
	return points[points.size() - 1].y

## Радиус, дальше которого в этом направлении склон уже не пройти.
## direction — угол в плоскости Godot: точка равна (cos a, sin a) по (x, z).
static func blocking_radius(direction: float) -> float:
	var angle := -direction
	if surface(angle, OPEN_RADIUS) < WALK_HEIGHT:
		return INF
	var low := 26.0
	var high := OPEN_RADIUS
	for _step in range(20):
		var mid := (low + high) * 0.5
		if surface(angle, mid) < WALK_HEIGHT:
			low = mid
		else:
			high = mid
	return low

## Стена по подошве: там, где склон пологий (перевал), сегмент не ставим —
## этот проход ограничивают обычные границы карты.
static func build_wall(into: Node3D) -> void:
	var segments := 96
	var step := TAU / float(segments)
	for index in range(segments):
		var direction := step * float(index)
		var radius := blocking_radius(direction)
		if is_inf(radius):
			continue
		var body := StaticBody3D.new()
		body.name = "MountainFoot%d" % index
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(radius * step * 1.6, 8.0, 1.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(cos(direction) * radius, 4.0, sin(direction) * radius)
		body.rotation.y = PI * 0.5 - direction
		into.add_child(body)
