extends SceneTree
## Deterministic multi-level gameplay reel for Yandex Games.
## Godot Movie Maker records the real 1280x720 viewport at a fixed 30 FPS.
## Add `-- --en` to record English UI; Russian is the default.

const CLIP_FRAMES := 112
const FADE_IN_FRAMES := 9
const FADE_OUT_FRAMES := 7

var fade_rect: ColorRect


func _initialize() -> void:
	_create_fade_overlay()
	call_deferred("_capture")


func _capture() -> void:
	var language := "en" if OS.get_cmdline_user_args().has("--en") else "ru"
	var service := root.get_node_or_null("YandexService")
	if service != null:
		service.detected_language = language
	print("Recording Yandex promo in language: ", language)
	await _capture_story()
	await _capture_black_sun()
	await _capture_dolls()
	await _capture_night()
	await _capture_gates()
	await _wait_frames(2)
	quit(0)


func _capture_story() -> void:
	var game := await _load_scene("res://scenes/main.tscn")
	game._start_game()
	await _wait_frames(4)
	game.hint.text = ""
	game.player.rotation.y = 0.0
	game.player.pitch = deg_to_rad(-2.0)
	game.player.get_node("Head").rotation.x = game.player.pitch
	game.seals_found = 1
	game.objective.text = game._text("seals") % game.seals_found
	game.guardian.global_position = game.player.global_position + Vector3(1.4, 0.0, -9.6)
	game.guardian.awaken(2)
	game.guardian.stun(0.75)
	await _run_clip(game, Callable(self, "_story_frame"))
	await _release_scene(game)


func _story_frame(game: Node, frame: int) -> void:
	if frame < 42:
		game.player.set_touch_move(Vector2(0.26, -0.42))
	elif frame < 74:
		game.player.set_touch_move(Vector2(0.76, 0.04))
	else:
		game.player.set_touch_move(Vector2(-0.38, -0.24))
	if frame == 42:
		game.player.stamina = game.player.max_stamina
		game.sun_pulse_cooldown = 0.0
		game._try_sun_pulse()


func _capture_black_sun() -> void:
	var level := await _load_challenge("res://scenes/level_04_black_sun.tscn")
	level.player.rotation.y = deg_to_rad(4.0)
	level.seals_found = 2
	level.player.stamina = level.player.max_stamina
	level.pulse_cooldown = 0.0
	level._update_hud()
	_configure_enemy(level, 0, Vector3(-1.1, 0.0, -6.8), 3, 1.0)
	_configure_enemy(level, 1, Vector3(3.2, 0.0, -9.0), 3, 1.35)
	await _run_clip(level, Callable(self, "_black_sun_frame"))
	await _release_scene(level)


func _black_sun_frame(level: Node, frame: int) -> void:
	level.player.set_touch_move(Vector2(0.10, -0.68) if frame < 60 else Vector2(0.70, -0.22))
	if frame == 45:
		level.pulse_cooldown = 0.0
		level.player.stamina = level.player.max_stamina
		level._try_sun_pulse()


func _capture_dolls() -> void:
	var level := await _load_challenge("res://scenes/level_13_dolls.tscn")
	level.player.rotation.y = deg_to_rad(-6.0)
	level.seals_found = 4
	level.player.stamina = level.player.max_stamina
	level.pulse_cooldown = 0.0
	level._update_hud()
	_configure_enemy(level, 0, Vector3(-1.8, 0.0, -10.4), 5, 0.90)
	_configure_enemy(level, 1, Vector3(4.2, 0.0, -12.6), 5, 1.20)
	await _run_clip(level, Callable(self, "_dolls_frame"))
	await _release_scene(level)


func _dolls_frame(level: Node, frame: int) -> void:
	level.player.set_touch_move(Vector2(-0.48, -0.36) if frame < 58 else Vector2(0.68, -0.18))
	if frame == 50:
		level.pulse_cooldown = 0.0
		level.player.stamina = level.player.max_stamina
		level._try_sun_pulse()


func _capture_night() -> void:
	var level := await _load_challenge("res://scenes/level_18_night.tscn")
	level.player.rotation.y = 0.0
	level.seals_found = 5
	level._update_hud()
	for index in range(1, level.enemies.size()):
		level.enemies[index].visible = false
		level.enemies[index].process_mode = Node.PROCESS_MODE_DISABLED
	var guardian: CharacterBody3D = level.enemies[0]
	guardian.global_position = level.player.global_position + Vector3(0.0, 0.0, -7.8)
	guardian.awaken(6)
	guardian.attack_cooldown = 0.0
	guardian.charge_cooldown = 0.0
	guardian._begin_charge()
	await _run_clip(level, Callable(self, "_night_frame"))
	await _release_scene(level)


func _night_frame(level: Node, frame: int) -> void:
	if frame < 20:
		level.player.set_touch_move(Vector2.ZERO)
	elif frame < 72:
		level.player.set_touch_move(Vector2(0.96, -0.10))
	else:
		level.player.set_touch_move(Vector2(-0.38, -0.80))


func _capture_gates() -> void:
	var level := await _load_challenge("res://scenes/level_21_gates.tscn")
	level.player.global_position = Vector3(0.0, 0.15, -17.0)
	level.player.rotation.y = 0.0
	level.player.pitch = deg_to_rad(-3.0)
	level.player.get_node("Head").rotation.x = level.player.pitch
	level.seals_found = level.seals_required
	level.curses_cleansed = level.curse_required
	level.altars_lit = level.altar_required
	level._update_hud()
	level.objective_beacon.visible = false
	for enemy in level.enemies:
		enemy.visible = false
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	await _run_clip(level, Callable(self, "_gates_frame"))
	await _release_scene(level)


func _gates_frame(level: Node, frame: int) -> void:
	if frame == 14:
		level._open_gate()
		level.set_meta("promo_gate_hint", level.hint.text)
	if frame >= 14 and level.has_meta("promo_gate_hint"):
		level.hint.text = str(level.get_meta("promo_gate_hint"))
	if frame < 48:
		level.player.set_touch_move(Vector2.ZERO)
	else:
		level.player.set_touch_move(Vector2(0.0, -0.92))


func _configure_enemy(level: Node, index: int, offset: Vector3, threat: int, stun_seconds: float) -> void:
	if index >= level.enemies.size():
		return
	var enemy: CharacterBody3D = level.enemies[index]
	enemy.global_position = level.player.global_position + offset
	enemy.awaken(threat)
	enemy.stun(stun_seconds)


func _load_challenge(path: String) -> Node:
	var level := await _load_scene(path)
	level._start_level()
	await _wait_frames(4)
	level.hint.text = ""
	return level


func _load_scene(path: String) -> Node:
	fade_rect.color.a = 1.0
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Could not load video scene: " + path)
		quit(1)
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	await _wait_frames(8)
	return scene


func _run_clip(scene: Node, updater: Callable) -> void:
	await _fade(1.0, 0.0, FADE_IN_FRAMES)
	for frame in range(CLIP_FRAMES):
		updater.call(scene, frame)
		await process_frame
	await _fade(0.0, 1.0, FADE_OUT_FRAMES)


func _release_scene(scene: Node) -> void:
	if is_instance_valid(scene) and "player" in scene and is_instance_valid(scene.player):
		scene.player.set_touch_move(Vector2.ZERO)
	scene.queue_free()
	await _wait_frames(3)


func _create_fade_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VideoFade"
	layer.layer = 1000
	root.add_child(layer)
	fade_rect = ColorRect.new()
	fade_rect.name = "Fade"
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.color = Color(0.02, 0.008, 0.006, 1.0)
	layer.add_child(fade_rect)


func _fade(from_alpha: float, to_alpha: float, frames: int) -> void:
	for index in range(frames):
		var weight := float(index + 1) / float(frames)
		fade_rect.color.a = lerpf(from_alpha, to_alpha, weight)
		await process_frame


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
