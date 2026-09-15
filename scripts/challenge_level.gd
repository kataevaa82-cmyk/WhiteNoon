extends Node3D

# Shared controller for the selectable challenge scenes.

enum RunState { INTRO, PLAYING, PAUSED, DOWNED, WON }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GUARDIAN_SCENE := preload("res://scenes/guardian.tscn")
const SEAL_SCENE := preload("res://scenes/seal.tscn")
const AUDIO_SCRIPT := preload("res://scripts/procedural_audio.gd")
const TOUCH_SCRIPT := preload("res://scripts/touch_controls.gd")
const FLOW := preload("res://scripts/game_flow.gd")
const CHALLENGE_TEXT := preload("res://scripts/challenge_text.gd")
const RITUAL_SUN := preload("res://scripts/ritual_sun.gd")
const MOUNTAIN_RING := preload("res://scripts/mountain_ring.gd")
const GUARDIAN_KIND := preload("res://scripts/guardian.gd")
const BRAND_LOGO := preload("res://assets/branding/white_noon_logo_mark.png")
const GROUND := preload("res://models/ground.glb")
const MOUNTAINS := preload("res://models/mountain_ring.glb")
const HOUSE_GREEN := preload("res://models/house_green.glb")
const HOUSE_BLUE := preload("res://models/house_blue.glb")
const HOUSE_RED := preload("res://models/house_red.glb")
const HOUSE_OCHRE := preload("res://models/house_ochre.glb")
const TREE := preload("res://models/birch_tree.glb")
const FENCE := preload("res://models/fence.glb")
const STONE := preload("res://models/standing_stone.glb")
const FLOWERS := preload("res://models/flower_patch.glb")
const HAYSTACK := preload("res://models/haystack.glb")
const BEEHIVE := preload("res://models/beehive.glb")
const BOULDER := preload("res://models/boulder.glb")
const OLD_WELL := preload("res://models/old_well.glb")
const BURNT_STUMP := preload("res://models/burnt_stump.glb")
const STRAW_DOLL := preload("res://models/straw_doll.glb")
const MILLSTONE := preload("res://models/millstone.glb")
const KURGAN := preload("res://models/kurgan.glb")
const SILENT_TOWER := preload("res://models/silent_tower.glb")
const CURSED_EFFIGY := preload("res://models/cursed_effigy.glb")
const SUN_TRAP := preload("res://models/sun_trap.glb")
const GATE := preload("res://models/ritual_gate.glb")
const GATE_DOOR := preload("res://models/ritual_gate_door.glb")
const TOTEM := preload("res://models/sun_totem.glb")
const BURIAL_ALTAR := preload("res://models/burial_altar.glb")

@export_range(2, 21) var level_number := 2
@export_range(4, 12) var seals_required := 4
@export_range(2, 10) var enemy_count := 2
@export_range(2, 8) var altar_required := 2

const MAX_HEALTH := 100.0
const PULSE_COST := 30.0

const HOUSE_SCENES := [HOUSE_GREEN, HOUSE_BLUE, HOUSE_RED, HOUSE_OCHRE]
const SPAWN_POINT := Vector3(0, 0, 25)
const GATE_POINT := Vector3(0, 0, -27)
const HALF_MAP := 27.0
const CELL_SIZE := 1.0
const GRID_SIZE := 55 # int(HALF_MAP * 2 / CELL_SIZE) + 1
const PLAYER_CLEARANCE := 0.7 # запас на радиус игрока при проверке проходимости
const NO_SPOT := Vector3(INF, INF, INF) # «свободной точки не нашлось»
# Кольцо гор начинается с радиуса 28, а сетка расстановки — квадрат ±27, углы
# которого уходят на радиус 38. Всё, что дальше подошвы, оказывалось внутри
# горы: печать было видно только сквозь склон. Держим объекты внутри круга,
# а по подошве ставим стену.
const PLAY_RADIUS := 26.0 # дальше не ставим ни печати, ни огни, ни стражей
const PROP_CLEARANCE := 1.3 # запас, чтобы печати и враги не влипали в стены
const CORRIDOR_HALF_WIDTH := 3.2
const BATCH_CHUNK := 18.0 # сторона клетки для группировки одинаковых моделей

var state := RunState.INTRO
var player: CharacterBody3D
var audio: Node
var sun: DirectionalLight3D
var environment: Environment
var objective: Label
var secondary_objective: Label
var status: Label
var hint: Label
var prompt: Label
var pulse_label: Label
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var danger_overlay: ColorRect
var intro_screen: Control
var end_screen: Control
var end_title: Label
var end_details: Label
var pause_label: Label
var touch_controls: Control
var yandex: Node
var suspended_by_platform := false
var current_language := "ru"
var intro_title_label: Label
var intro_story_label: Label
var intro_controls_label: Label
var intro_start_button: Button
var intro_menu_button: Button
var end_next_button: Button
var end_restart_button: Button
var end_menu_button: Button
var death_reward_button: Button

var health := MAX_HEALTH
var seals_found := 0
var altars_lit := 0
var curses_cleansed := 0
var curse_required := 0
var completed := false
var exit_open := false
var overtime := false
var pulse_cooldown := 0.0
var hurt_cooldown := 0.0
var rift_damage_flash := 0.0
var elapsed := 0.0
var escape_limit := 0.0
var escape_remaining := 0.0
var hits_taken := 0
var pulses_used := 0
var deaths := 0
var well_used := false
var hint_serial := 0
var current_interactable: Area3D
var nearby_interactables: Array[Area3D] = []

var enemies: Array[CharacterBody3D] = []
var seal_nodes: Array[Area3D] = []
var altar_nodes: Array[Area3D] = []
var curse_nodes: Array[Node3D] = []
var trap_zones: Array[Area3D] = []
var trapped_enemies := 0
var rift_nodes: Array[Node3D] = []
var gate_area: Area3D
var gate_blocker: CollisionShape3D
var gate_doors: Array[Node3D] = []
var well_area: Area3D
var eclipse_visual: Node3D  # scripts/ritual_sun.gd
var atmosphere_motes: MultiMeshInstance3D
var objective_beacon: Node3D
var exit_path: Node3D
var visual_time := 0.0

var rng := RandomNumberGenerator.new()
var layout_kind := "village"
var obstacle_circles: Array[Vector3] = [] # x, z, радиус
var reserved_circles: Array[Vector3] = [] # места, где не должно быть целей
var path_points: Array[Vector3] = []
var free_spots: Array[Vector3] = []
var taken_spots: Array[Vector3] = []
var fallback_spots := 0 # сколько раз пришлось встать на запасную точку маршрута
var sector_misses := 0 # сколько раз сектор пришлось отбросить ради свободного места
var totem_point := Vector3(0, 0, -1)
var prop_batches := {} # одинаковые модели рисуются одним MultiMesh

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	yandex = get_node("/root/YandexService")
	yandex.platform_suspension_changed.connect(_on_platform_suspension_changed)
	yandex.language_detected.connect(_apply_language)
	current_language = yandex.get_ui_language(String(yandex.detected_language))
	curse_required = _curse_count_for_level()
	escape_limit = _escape_time_for_level()
	_build_world()
	_build_hud()
	player.set_controls_enabled(false)
	_update_hud()
	_refresh_objective_beacon()
	yandex.gameplay_stop()
	yandex.mark_game_ready()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state in [RunState.PLAYING, RunState.PAUSED]:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and state == RunState.PLAYING:
		_handle_action()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	visual_time += delta
	_update_visuals(delta)
	if state != RunState.PLAYING:
		return
	elapsed += delta
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	rift_damage_flash = maxf(0.0, rift_damage_flash - delta * 1.7)
	var sunlight := _is_in_sunlight()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.player_in_shadow = not sunlight
	if sunlight and not overtime and health < MAX_HEALTH:
		_change_health(_healing_rate() * delta)
	var in_rift := _update_rifts(delta)
	if exit_open and escape_limit > 0.0 and not overtime:
		escape_remaining = maxf(0.0, escape_remaining - delta)
		if escape_remaining <= 0.0:
			_trigger_overtime()
	_update_status(sunlight, in_rift)
	_update_prompt()
	_update_danger(in_rift)
	_update_hud()
	if player.global_position.y < -3.0:
		_respawn_player(_tr("fall_respawn"))

func _build_world() -> void:
	_add_visual(GROUND, Vector3.ZERO)
	_add_visual(MOUNTAINS, Vector3.ZERO)
	_add_box_collider(Vector3(0, -0.2, 0), Vector3(60, 0.4, 60))
	_add_boundaries()
	_build_lighting()
	_build_eclipse()
	_build_atmosphere_motes()
	_build_set_dressing()
	_spawn_player_and_audio()
	_spawn_seals()
	_spawn_curses()
	_spawn_altars()
	_spawn_sun_well()
	_spawn_rifts()
	_spawn_enemies()
	_spawn_trap_zones()
	_build_exit()
	_build_objective_beacon()

func _build_lighting() -> void:
	var palette := _theme_palette()
	sun = DirectionalLight3D.new()
	sun.name = "LowSun"
	sun.rotation_degrees = RITUAL_SUN.light_rotation_for(_sun_azimuth(), _sun_elevation())
	sun.light_color = palette.sun
	sun.light_energy = maxf(0.58, 1.24 - float(level_number - 2) * 0.032)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 72.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = palette.sky_top
	sky_material.sky_horizon_color = palette.sky_horizon
	sky_material.ground_bottom_color = palette.ground_bottom
	sky_material.ground_horizon_color = palette.ground_horizon
	sky_material.sky_curve = 0.28
	sky_material.ground_curve = 0.22
	var sky := Sky.new()
	sky.sky_material = sky_material

	var world_environment := WorldEnvironment.new()
	world_environment.name = "ChallengeEnvironment"
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = palette.ambient
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.95
	environment.adjustment_contrast = 1.09
	environment.adjustment_saturation = 0.88
	environment.fog_enabled = true
	environment.fog_light_color = palette.fog
	environment.fog_light_energy = 0.45
	environment.fog_density = minf(0.014, 0.0028 + float(level_number - 2) * 0.00055)
	environment.fog_sky_affect = 0.22
	world_environment.environment = environment
	add_child(world_environment)

func _theme_palette() -> Dictionary:
	var tier := mini(4, int(float(level_number - 2) / 4.0))
	var palettes := [
		{"sun": Color(1.0, 0.84, 0.54), "sky_top": Color(0.025, 0.15, 0.48), "sky_horizon": Color(0.40, 0.48, 0.57), "ground_bottom": Color(0.055, 0.07, 0.045), "ground_horizon": Color(0.25, 0.27, 0.17), "ambient": Color(0.50, 0.55, 0.64), "fog": Color(0.42, 0.45, 0.50), "accent": Color(1.0, 0.50, 0.055), "ring": Color(1.0, 0.92, 0.72), "corona": Color(1.0, 0.63, 0.26)},
		{"sun": Color(1.0, 0.66, 0.34), "sky_top": Color(0.055, 0.08, 0.30), "sky_horizon": Color(0.52, 0.27, 0.30), "ground_bottom": Color(0.055, 0.035, 0.045), "ground_horizon": Color(0.30, 0.19, 0.13), "ambient": Color(0.43, 0.40, 0.55), "fog": Color(0.42, 0.20, 0.24), "accent": Color(1.0, 0.31, 0.035), "ring": Color(1.0, 0.80, 0.48), "corona": Color(1.0, 0.46, 0.14)},
		{"sun": Color(0.94, 0.42, 0.27), "sky_top": Color(0.028, 0.035, 0.15), "sky_horizon": Color(0.43, 0.12, 0.24), "ground_bottom": Color(0.025, 0.025, 0.045), "ground_horizon": Color(0.21, 0.13, 0.19), "ambient": Color(0.36, 0.34, 0.52), "fog": Color(0.31, 0.12, 0.22), "accent": Color(0.94, 0.13, 0.08), "ring": Color(1.0, 0.62, 0.30), "corona": Color(0.98, 0.30, 0.10)},
		{"sun": Color(0.71, 0.27, 0.39), "sky_top": Color(0.015, 0.018, 0.075), "sky_horizon": Color(0.25, 0.055, 0.18), "ground_bottom": Color(0.012, 0.014, 0.026), "ground_horizon": Color(0.12, 0.08, 0.16), "ambient": Color(0.30, 0.31, 0.50), "fog": Color(0.20, 0.075, 0.19), "accent": Color(0.76, 0.08, 0.18), "ring": Color(1.0, 0.48, 0.32), "corona": Color(0.86, 0.17, 0.14)},
		{"sun": Color(0.52, 0.20, 0.49), "sky_top": Color(0.008, 0.009, 0.035), "sky_horizon": Color(0.12, 0.025, 0.13), "ground_bottom": Color(0.006, 0.007, 0.016), "ground_horizon": Color(0.075, 0.045, 0.11), "ambient": Color(0.24, 0.27, 0.48), "fog": Color(0.12, 0.04, 0.16), "accent": Color(0.62, 0.055, 0.31), "ring": Color(0.98, 0.38, 0.46), "corona": Color(0.68, 0.11, 0.30)},
	]
	return palettes[tier]

func _build_eclipse() -> void:
	var palette := _theme_palette()
	eclipse_visual = RITUAL_SUN.new()
	eclipse_visual.name = "SolsticeSun"
	add_child(eclipse_visual)
	eclipse_visual.setup(sun)
	eclipse_visual.set_look(palette.sun, palette.ring, palette.corona, _eclipse_amount(), 9 + level_number % 4, float(level_number) * 0.7)
	eclipse_visual.set_breath(0.34 + float(level_number) * 0.01, 0.010 + _eclipse_amount() * 0.012)

func _sun_azimuth() -> float:
	# Солнце всегда в передней полусфере, над перевалом, но у каждого
	# уровня своя точка неба.
	return sin(float(level_number) * 1.31 + 0.6) * 58.0

func _sun_elevation() -> float:
	return 43.0 - float(clampi(level_number, 2, 21) - 2) * 0.62 + sin(float(level_number) * 0.83) * 2.6

func _eclipse_amount() -> float:
	return clampf(0.12 + float(clampi(level_number, 2, 21) - 2) * 0.045, 0.0, 0.96)

func _build_atmosphere_motes() -> void:
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.035
	mote_mesh.height = 0.07
	mote_mesh.radial_segments = 6
	mote_mesh.rings = 4
	mote_mesh.material = _emissive_material(_theme_palette().accent, 1.3)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mote_mesh
	multimesh.instance_count = 54 + mini(level_number, 20) * 2
	for index in range(multimesh.instance_count):
		var angle := float(index) * 2.399 + level_number * 0.17
		var radius := 4.0 + float((index * 13) % 230) * 0.095
		var height := 0.5 + float((index * 17) % 70) * 0.075
		var position := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var scale_value := 0.65 + float(index % 5) * 0.12
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_value), position))
	atmosphere_motes = MultiMeshInstance3D.new()
	atmosphere_motes.name = "AshAndFireflies"
	atmosphere_motes.multimesh = multimesh
	atmosphere_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmosphere_motes)

func _build_set_dressing() -> void:
	# Планировка собирается заново для каждого уровня. Зерно зависит только от
	# номера, поэтому карта всегда одна и та же для данного уровня, но у соседних
	# уровней не совпадает ничего: ни дорога, ни застройка, ни расстановка целей.
	rng.seed = hash("whitenoon-layout-%d" % level_number)
	layout_kind = _layout_kind()
	obstacle_circles.clear()
	reserved_circles.clear()
	free_spots.clear()
	taken_spots.clear()
	_build_path_spine()
	_reserve(SPAWN_POINT, 4.2)
	_reserve(GATE_POINT, 5.2)
	_reserve(totem_point, 3.6)
	match layout_kind:
		"mounds": _layout_mounds()
		"burnt": _layout_burnt()
		"ring": _layout_ring()
		"mill": _layout_mill()
		"ravine": _layout_ravine()
		"apiary": _layout_apiary()
		"ford": _layout_ford()
		"pass": _layout_pass()
		"fires": _layout_fires()
		"wells": _layout_wells()
		"dolls": _layout_dolls()
		"tower": _layout_tower()
		"spiral": _layout_spiral()
		"forest": _layout_forest()
		"mirror": _layout_mirror()
		"gates": _layout_gates()
		_: _layout_village()
	if layout_kind != "forest":
		# В лесу опушка не нужна — чаща и так доходит до края карты.
		_build_tree_line()
	_scatter_ground_cover()
	_build_prop_batches()
	_collect_free_spots()

func _layout_kind() -> String:
	# Планировка подобрана под название уровня из game_flow.gd.
	match level_number:
		2: return "mounds"
		3: return "burnt"
		4: return "ring"
		5: return "mill"
		6: return "ravine"
		7: return "apiary"
		8: return "ford"
		9: return "pass"
		10: return "fires"
		11: return "wells"
		12: return "ring"
		13: return "dolls"
		14: return "tower"
		15: return "spiral"
		16: return "forest"
		17: return "village"
		18: return "forest"
		19: return "mounds"
		20: return "mirror"
		21: return "gates"
	return "village"

func _build_path_spine() -> void:
	# Тропа от спавна к воротам через солнечный колодец. Всё, что строится
	# дальше, обязано её обходить — так уровень гарантированно проходим.
	var sway := rng.randf_range(3.5, 6.5) * (1.0 if rng.randf() < 0.5 else -1.0)
	totem_point = Vector3(sway * 0.22, 0.0, rng.randf_range(-3.5, 3.0))
	path_points = [
		SPAWN_POINT,
		Vector3(sway * 0.62, 0.0, 15.0 + rng.randf_range(-2.5, 2.5)),
		totem_point,
		Vector3(-sway * 0.58, 0.0, -13.0 + rng.randf_range(-2.5, 2.5)),
		GATE_POINT,
	]

# --- Планировки -------------------------------------------------------------

func _layout_mounds() -> void:
	# Курганы: земляные насыпи с венцом камней, редкие избы по краю.
	_place_repeatedly(rng.randi_range(5, 7), 60, func(_index: int) -> bool:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(8.0, 21.0)
		var centre := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var mound_radius := rng.randf_range(3.0, 5.0)
		if not _place_mound(centre, mound_radius, rng.randf_range(1.8, 3.1)):
			return false
		var stones := rng.randi_range(4, 7)
		for stone_index in range(stones):
			var stone_angle := float(stone_index) * TAU / float(stones) + angle
			_place_stone(centre + Vector3(cos(stone_angle), 0.0, sin(stone_angle)) * (mound_radius + 1.6), rng.randf_range(0.7, 1.1))
		return true)
	_place_repeatedly(3, 24, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(15.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(14, 9.0, 25.0)

func _layout_burnt() -> void:
	# Пепельный посад: обгоревшие срубы, пни и старые кострища.
	var street := rng.randf_range(-3.0, 3.0)
	_place_repeatedly(7, 40, func(index: int) -> bool:
		var side := -1.0 if index % 2 == 0 else 1.0
		var position := Vector3(street + side * rng.randf_range(8.0, 15.0), 0.0, 21.0 - float(index % 8) * 6.2 + rng.randf_range(-1.5, 1.5))
		return _place_house(position, rng.randf_range(-0.4, 0.4) + (0.0 if side < 0.0 else PI), rng.randf_range(0.45, 0.78)))
	_place_repeatedly(16, 60, func(_index: int) -> bool:
		return _place_stump(Vector3(rng.randf_range(-24.0, 24.0), 0.0, rng.randf_range(-25.0, 25.0))))
	_sprinkle_trees(8, 18.0, 26.0)

func _layout_ring() -> void:
	# Сорочий круг: два-три кольца стоячих камней вокруг центра.
	var rings := rng.randi_range(2, 3)
	for ring_index in range(rings):
		var radius := 7.0 + float(ring_index) * rng.randf_range(5.0, 6.5)
		var count := 8 + ring_index * 5
		for index in range(count):
			var angle := float(index) * TAU / float(count) + float(ring_index) * 0.4
			_place_stone(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), rng.randf_range(0.8, 1.4))
	_place_repeatedly(4, 28, func(index: int) -> bool:
		var angle := PI * 0.25 + float(index) * PI * 0.5 + rng.randf_range(-0.35, 0.35)
		var radius := rng.randf_range(19.0, 23.0)
		return _place_house(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius * 0.9), angle + PI))
	_sprinkle_trees(12, 24.0, 26.5)

func _layout_mill() -> void:
	# Треснувший жернов: мельничный круг в центре, дворы и стога вокруг.
	_place_repeatedly(1, 40, func(_index: int) -> bool:
		return _place_millstone(Vector3(rng.randf_range(-17.0, 17.0), 0.0, rng.randf_range(-18.0, 12.0))))
	_place_repeatedly(4, 30, func(_index: int) -> bool:
		var corner := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 22.0))
		if not _place_house(corner, rng.randf() * TAU):
			return false
		var pen := 7.2
		_place_fence(corner + Vector3(-pen, 0, pen), corner + Vector3(pen, 0, pen))
		_place_fence(corner + Vector3(pen, 0, pen), corner + Vector3(pen, 0, -pen))
		return true)
	_place_repeatedly(9, 50, func(_index: int) -> bool:
		return _place_haystack(Vector3(rng.randf_range(-23.0, 23.0), 0.0, rng.randf_range(-24.0, 24.0))))
	_sprinkle_trees(10, 12.0, 26.0)

func _layout_ravine() -> void:
	# Дымный овраг: две скальные стены вдоль тропы и отнорки в стороны.
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for index in range(path_points.size() - 1):
		var from: Vector3 = path_points[index]
		var to: Vector3 = path_points[index + 1]
		var direction := (to - from).normalized()
		var normal := Vector3(-direction.z, 0.0, direction.x) * rng.randf_range(7.5, 9.0)
		_place_rock_wall(from + normal, to + normal, rng.randf_range(3.4, 5.0), 2.6)
		_place_rock_wall(from - normal, to - normal, rng.randf_range(3.4, 5.0), 2.6)
	for index in range(3):
		var start := Vector3(side * rng.randf_range(9.0, 12.0), 0.0, rng.randf_range(-20.0, 18.0))
		_place_rock_wall(start, start + Vector3(side * rng.randf_range(7.0, 11.0), 0.0, rng.randf_range(-5.0, 5.0)), 3.2, 2.2)
		side = -side
	_sprinkle_trees(12, 14.0, 26.0)

func _layout_apiary() -> void:
	# Мёртвая пасека: ряды колод, разделённые низкими пряслами.
	var rows := rng.randi_range(4, 5)
	for row in range(rows):
		var z := 18.0 - float(row) * rng.randf_range(8.0, 10.0)
		var offset := rng.randf_range(-4.0, 4.0)
		for index in range(6):
			_place_hive(Vector3(-20.0 + offset + float(index) * 7.2, 0.0, z + rng.randf_range(-1.2, 1.2)))
		if row < rows - 1:
			_place_fence(Vector3(-22.0, 0, z - 4.4), Vector3(-4.0, 0, z - 4.4))
			_place_fence(Vector3(4.0, 0, z - 4.4), Vector3(22.0, 0, z - 4.4))
	_place_repeatedly(2, 18, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(18.0, 24.0)), rng.randf() * TAU))
	_scatter_flowers(26)
	_sprinkle_trees(9, 20.0, 26.0)

func _layout_ford() -> void:
	# Красный брод: река поперёк карты, каменистые берега, переправа на тропе.
	var river_z := rng.randf_range(-6.0, 4.0)
	_place_water(Vector3(0.0, 0.02, river_z), Vector2(56.0, 7.5), Color(0.36, 0.045, 0.06, 0.72))
	for index in range(20):
		var x := -25.0 + float(index) * 2.6 + rng.randf_range(-0.8, 0.8)
		if absf(x - _path_x_at(river_z)) < 4.2:
			continue
		_place_stone(Vector3(x, 0.0, river_z + rng.randf_range(-3.4, 3.4)), rng.randf_range(0.45, 0.8))
	_place_repeatedly(4, 30, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-21.0, 21.0), 0.0, river_z + rng.randf_range(9.0, 20.0)), rng.randf() * TAU))
	_sprinkle_trees(20, 8.0, 26.0)

func _layout_pass() -> void:
	# Тихий перевал: два скальных массива, между ними узкое горло.
	var throat_z := rng.randf_range(-6.0, 4.0)
	for index in range(6):
		var z := throat_z + 18.0 - float(index) * 7.2
		var gap := 5.5 + absf(z - throat_z) * 0.55
		_place_rock_wall(Vector3(-26.0, 0, z), Vector3(-gap, 0, z + rng.randf_range(-2.0, 2.0)), rng.randf_range(3.6, 5.6), 3.0)
		_place_rock_wall(Vector3(gap, 0, z + rng.randf_range(-2.0, 2.0)), Vector3(26.0, 0, z), rng.randf_range(3.6, 5.6), 3.0)
	for index in range(10):
		_place_stone(Vector3(rng.randf_range(-24.0, 24.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf_range(0.5, 1.0))
	_sprinkle_trees(8, 16.0, 26.0)

func _layout_fires() -> void:
	# Двенадцать костров: широкое кольцо кострищ в чистом поле.
	var radius := rng.randf_range(13.0, 17.0)
	for index in range(12):
		var angle := float(index) * TAU / 12.0 + rng.randf_range(-0.1, 0.1)
		var centre := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_place_stone(centre + Vector3(cos(angle), 0.0, sin(angle)) * 2.2, rng.randf_range(0.5, 0.9))
	_place_repeatedly(3, 24, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-23.0, 23.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(16, 20.0, 26.5)

func _layout_wells() -> void:
	# Колодец без дна: дворы, в каждом свой сруб.
	_place_repeatedly(5, 45, func(_index: int) -> bool:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(9.0, 21.0)
		var yard := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if not _place_well(yard):
			return false
		var size := rng.randf_range(4.5, 6.5)
		_place_fence(yard + Vector3(-size, 0, size), yard + Vector3(size, 0, size))
		_place_fence(yard + Vector3(size, 0, -size), yard + Vector3(-size, 0, -size))
		if rng.randf() < 0.6:
			_place_house(yard + Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0)), rng.randf() * TAU)
		return true)
	_sprinkle_trees(14, 12.0, 26.0)

func _layout_dolls() -> void:
	# Поле кукол: ряды соломенных чучел, между ними почти ничего.
	var rows := rng.randi_range(5, 7)
	for row in range(rows):
		var z := 20.0 - float(row) * rng.randf_range(7.0, 8.5)
		var count := rng.randi_range(7, 9)
		for index in range(count):
			var x := -23.0 + float(index) * (46.0 / float(count - 1)) + rng.randf_range(-1.0, 1.0)
			_place_doll(Vector3(x, 0.0, z + rng.randf_range(-1.5, 1.5)), rng.randf_range(1.9, 2.6))
	_place_repeatedly(2, 18, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(10, 20.0, 26.0)

func _layout_tower() -> void:
	# Беззвонная башня: башня, погост и ограда вокруг него.
	var tower := Vector3(rng.randf_range(-9.0, 9.0), 0.0, rng.randf_range(-16.0, -6.0))
	_place_tower(tower, rng.randf_range(9.0, 12.0))
	var yard := rng.randf_range(8.0, 10.5)
	_place_fence(tower + Vector3(-yard, 0, yard), tower + Vector3(yard, 0, yard))
	_place_fence(tower + Vector3(yard, 0, yard), tower + Vector3(yard, 0, -yard))
	_place_fence(tower + Vector3(yard, 0, -yard), tower + Vector3(-yard, 0, -yard))
	_place_fence(tower + Vector3(-yard, 0, -yard), tower + Vector3(-yard, 0, yard))
	for index in range(16):
		_place_stone(tower + Vector3(rng.randf_range(-yard + 1.0, yard - 1.0), 0.0, rng.randf_range(-yard + 1.0, yard - 1.0)), rng.randf_range(0.45, 0.75))
	_place_repeatedly(4, 30, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(8.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(12, 16.0, 26.0)

func _layout_spiral() -> void:
	# Пепельный хоровод: спираль из камней и кострищ, закрученная к центру.
	var turns := rng.randf_range(2.2, 2.8)
	var steps := 34
	for index in range(steps):
		var t := float(index) / float(steps - 1)
		var angle := t * TAU * turns + rng.randf_range(-0.05, 0.05)
		var radius := 24.0 - t * 20.0
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_place_stone(point, rng.randf_range(0.95, 1.5))
	_place_repeatedly(3, 24, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-23.0, 23.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(10, 24.0, 26.5)

func _layout_forest() -> void:
	# Слепой лес: чаща с редкими прогалинами.
	var clearings: Array[Vector3] = []
	for index in range(rng.randi_range(3, 5)):
		clearings.append(Vector3(rng.randf_range(-19.0, 19.0), 0.0, rng.randf_range(-22.0, 20.0)))
	for index in range(150):
		var point := Vector3(rng.randf_range(-26.0, 26.0), 0.0, rng.randf_range(-26.0, 26.0))
		var in_clearing := false
		for clearing in clearings:
			if point.distance_to(clearing) < rng.randf_range(5.0, 7.5):
				in_clearing = true
				break
		if in_clearing:
			continue
		_place_tree(point, rng.randf_range(0.7, 1.25))
	for index in range(6):
		_place_stump(Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(-22.0, 22.0)))
	if rng.randf() < 0.7:
		_place_house(Vector3(rng.randf_range(-16.0, 16.0), 0.0, rng.randf_range(-20.0, 20.0)), rng.randf() * TAU)

func _layout_mirror() -> void:
	# Зеркало полдня: карта строится на одной половине и отражается на другую.
	_place_water(Vector3(0.0, 0.02, 0.0), Vector2(3.6, 54.0), Color(0.62, 0.68, 0.78, 0.62))
	_place_repeatedly(4, 30, func(_index: int) -> bool:
		var position := Vector3(rng.randf_range(7.0, 21.0), 0.0, rng.randf_range(-22.0, 22.0))
		var turn := rng.randf() * TAU
		if not _place_house(position, turn):
			return false
		_place_house(Vector3(-position.x, 0.0, position.z), -turn)
		return true)
	for index in range(10):
		var stone := Vector3(rng.randf_range(5.0, 24.0), 0.0, rng.randf_range(-24.0, 24.0))
		var size := rng.randf_range(0.6, 1.2)
		_place_stone(stone, size)
		_place_stone(Vector3(-stone.x, 0.0, stone.z), size)
	for index in range(11):
		var tree := Vector3(rng.randf_range(5.0, 25.0), 0.0, rng.randf_range(-25.0, 25.0))
		var size := rng.randf_range(0.75, 1.2)
		_place_tree(tree, size)
		_place_tree(Vector3(-tree.x, 0.0, tree.z), size)

func _layout_gates() -> void:
	# За чёрными воротами: решётка из ворот и прясел, проходы только в арках.
	var rows := rng.randi_range(3, 4)
	for row in range(rows):
		var z := 16.0 - float(row) * (36.0 / float(rows))
		var gate_x := rng.randf_range(-14.0, 14.0)
		_place_gate_arch(Vector3(gate_x, 0.0, z), 0.0)
		_place_fence(Vector3(-27.0, 0, z), Vector3(gate_x - 3.2, 0, z))
		_place_fence(Vector3(gate_x + 3.2, 0, z), Vector3(27.0, 0, z))
	for index in range(6):
		_place_stone(Vector3(rng.randf_range(-24.0, 24.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf_range(0.7, 1.3))
	_place_repeatedly(2, 18, func(_index: int) -> bool:
		return _place_house(Vector3(rng.randf_range(-22.0, 22.0), 0.0, rng.randf_range(-24.0, 24.0)), rng.randf() * TAU))
	_sprinkle_trees(10, 20.0, 26.5)

func _layout_village() -> void:
	# Обычный посад: две линии изб вдоль дороги и сады за ними.
	_place_repeatedly(8, 44, func(index: int) -> bool:
		var side := -1.0 if index % 2 == 0 else 1.0
		var z := 20.0 - float(index % 9) * 5.4 + rng.randf_range(-1.2, 1.2)
		var position := Vector3(_path_x_at(z) + side * rng.randf_range(7.5, 12.0), 0.0, z)
		if not _place_house(position, (0.0 if side > 0.0 else PI) + rng.randf_range(-0.3, 0.3)):
			return false
		_place_fence(position + Vector3(-side * 7.4, 0, -4.8), position + Vector3(-side * 7.4, 0, 4.8))
		return true)
	_sprinkle_trees(24, 13.0, 26.0)
	_scatter_flowers(18)

# --- Кирпичики планировок ---------------------------------------------------

## Пробует ставить объект, пока не наберётся нужное количество: без этого
## половина изб и курганов молча терялась на отказах размещения.
func _place_repeatedly(target: int, attempts: int, action: Callable) -> int:
	var placed := 0
	for index in range(attempts):
		if placed >= target:
			break
		if action.call(index):
			placed += 1
	return placed

func _sprinkle_trees(count: int, min_radius: float, max_radius: float) -> void:
	for index in range(count * 3):
		if index >= count * 3:
			break
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(min_radius, max_radius)
		_place_tree(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), rng.randf_range(0.75, 1.2))

func _scatter_flowers(count: int) -> void:
	for index in range(count):
		var point := Vector3(rng.randf_range(-25.0, 25.0), 0.0, rng.randf_range(-25.0, 25.0))
		if _is_clear(point, 1.0):
			_batch_prop("Flowers", FLOWERS, point, rng.randf() * TAU, rng.randf_range(0.7, 1.15), false)

func _build_tree_line() -> void:
	# Опушка по краю карты — она есть всегда, чтобы граница не выглядела обрывом.
	var count := 30 + level_number
	for index in range(count):
		var angle := float(index) * TAU / float(count) + float(level_number) * 0.11
		var radius := 26.0 + rng.randf_range(0.0, 1.6)
		_place_tree(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius), rng.randf_range(0.8, 1.3), true)

func _scatter_ground_cover() -> void:
	var count := 10 + rng.randi_range(0, 8)
	for index in range(count):
		var point := Vector3(rng.randf_range(-24.0, 24.0), 0.0, rng.randf_range(-24.0, 24.0))
		if _is_clear(point, 1.2):
			_batch_prop("Flowers", FLOWERS, point, rng.randf() * TAU, rng.randf_range(0.6, 1.0), false)

## Деревья, камни, прясла и цветы повторяются десятками. Каждая такая
## модель — это 3-5 поверхностей, то есть столько же вызовов отрисовки на
## штуку; в лесу набегало под пятьсот. Собираем их в MultiMesh.
func _batch_prop(key: String, scene: PackedScene, position: Vector3, turn: float, size: float, shadows := true) -> void:
	# Пачки режутся на клетки: один MultiMesh во всю карту попадал бы во все
	# каскады теней сразу и рисовался бы по четыре раза за кадр.
	var chunk := "%s#%d.%d" % [key, int(floor((position.x + HALF_MAP) / BATCH_CHUNK)), int(floor((position.z + HALF_MAP) / BATCH_CHUNK))]
	if not prop_batches.has(chunk):
		prop_batches[chunk] = {"scene": scene, "shadows": shadows, "items": []}
	var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * size)
	prop_batches[chunk]["items"].append(Transform3D(basis, position))

func _batch_prop_scaled(key: String, scene: PackedScene, position: Vector3, rotation: Vector3, model_scale: Vector3, shadows := true) -> void:
	var chunk := "%s#%d.%d" % [key, int(floor((position.x + HALF_MAP) / BATCH_CHUNK)), int(floor((position.z + HALF_MAP) / BATCH_CHUNK))]
	if not prop_batches.has(chunk):
		prop_batches[chunk] = {"scene": scene, "shadows": shadows, "items": []}
	var basis := Basis.from_euler(rotation).scaled(model_scale)
	prop_batches[chunk]["items"].append(Transform3D(basis, position))

func _build_prop_batches() -> void:
	for key in prop_batches:
		var batch: Dictionary = prop_batches[key]
		var items: Array = batch["items"]
		if items.is_empty():
			continue
		var sample: Node = (batch["scene"] as PackedScene).instantiate()
		for part in _mesh_parts(sample, Transform3D.IDENTITY):
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = part["mesh"]
			multimesh.instance_count = items.size()
			for index in range(items.size()):
				multimesh.set_instance_transform(index, (items[index] as Transform3D) * (part["transform"] as Transform3D))
			var instance := MultiMeshInstance3D.new()
			instance.name = "Batch_%s" % key.replace("#", "_")
			instance.multimesh = multimesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if batch["shadows"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
		sample.free()
	prop_batches.clear()

func _mesh_parts(node: Node, parent_transform: Transform3D) -> Array:
	var parts: Array = []
	var here := parent_transform
	if node is Node3D:
		here = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		parts.append({"mesh": (node as MeshInstance3D).mesh, "transform": here})
	for child in node.get_children():
		parts.append_array(_mesh_parts(child, here))
	return parts

func _place_house(position: Vector3, turn: float, char_amount := 0.0) -> bool:
	if not _can_place(position, 4.2):
		return false
	var house := _add_visual(HOUSE_SCENES[rng.randi() % HOUSE_SCENES.size()], position, turn)
	if char_amount > 0.0:
		_char_model(house, char_amount)
	_add_box_collider(position + Vector3(0, 1.7, 0), Vector3(6.0, 3.4, 5.4), turn)
	_add_obstacle(position, 3.9)
	return true

## Обугливает готовую модель: у изб посада нет отдельной «сгоревшей» версии.
func _char_model(node: Node, amount: float) -> void:
	var soot := StandardMaterial3D.new()
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.albedo_color = Color(0.05, 0.042, 0.04, clampf(amount, 0.0, 1.0))
	soot.roughness = 1.0
	soot.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for mesh_node in _mesh_nodes(node):
		mesh_node.material_overlay = soot

func _mesh_nodes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_nodes(child))
	return found

func _place_tree(position: Vector3, size := 1.0, edge := false) -> bool:
	if not _can_place(position, 1.0):
		return false
	# Опушку по краю карты игрок только видит, тени от неё не нужны.
	_batch_prop("EdgeTrees" if edge else "Trees", TREE, position, rng.randf() * TAU, size, not edge)
	_add_cylinder_collider(position + Vector3(0, 1.6 * size, 0), 0.34 * size, 3.2 * size)
	_add_obstacle(position, 0.55 * size)
	return true

func _place_stone(position: Vector3, size := 1.0) -> bool:
	if not _can_place(position, 1.1):
		return false
	_batch_prop("Stones", STONE, position, rng.randf() * TAU, size)
	_add_cylinder_collider(position + Vector3(0, 1.5 * size, 0), 0.55 * size, 3.1 * size)
	_add_obstacle(position, 0.72 * size)
	return true

func _place_fence(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if length < 1.0:
		return
	var direction := span / length
	var turn := atan2(-direction.z, direction.x)
	var count := maxi(1, int(round(length / 4.7)))
	for index in range(count):
		var centre := from + direction * (length * (float(index) + 0.5) / float(count))
		if not _can_place(centre, 1.3):
			continue
		_batch_prop("Fences", FENCE, centre, turn, 1.0)
		_add_box_collider(centre + Vector3(0, 0.9, 0), Vector3(4.7, 1.8, 0.34), turn)
		_add_obstacle_line(centre - direction * 2.2, centre + direction * 2.2, 0.4)

func _place_mound(position: Vector3, radius: float, height: float) -> bool:
	if not _can_place(position, radius * 0.9):
		return false
	var rotation := Vector3(0.0, rng.randf() * TAU, 0.0)
	var model_scale := Vector3(radius * 2.0 / 2.066, height / 1.04, radius * 2.0 / 2.051)
	_batch_prop_scaled("Kurgans", KURGAN, position, rotation, model_scale)
	_add_cylinder_collider(position + Vector3(0, height * 0.5, 0), radius * 0.8, height)
	_add_obstacle(position, radius * 0.84)
	return true

func _place_rock_wall(from: Vector3, to: Vector3, height: float, width: float) -> void:
	var span := to - from
	var length := span.length()
	if length < 1.0:
		return
	var direction := span / length
	var turn := atan2(-direction.z, direction.x)
	var blocks := maxi(2, int(length / 2.4))
	for index in range(blocks):
		var centre := from + direction * (length * (float(index) + 0.5) / float(blocks))
		centre += Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		if not _place_boulder(centre, Vector3(2.4, height * rng.randf_range(0.7, 1.25), width), turn):
			continue

## Гранёный валун: то же низкополигональное дело, что и горы вокруг карты.
func _place_boulder(position: Vector3, size: Vector3, turn: float) -> bool:
	if not _can_place(position, maxf(size.x, size.z) * 0.5):
		return false
	var rotation := Vector3(rng.randf_range(-0.10, 0.10), turn + rng.randf_range(-0.42, 0.42), rng.randf_range(-0.10, 0.10))
	var model_scale := Vector3(size.x / 2.143, size.y / 1.695, size.z / 1.893)
	_batch_prop_scaled("Boulders", BOULDER, position, rotation, model_scale)
	_add_box_collider(position + Vector3(0, size.y * 0.4, 0), Vector3(size.x * 0.85, size.y * 0.85, size.z * 0.85), rotation.y)
	_add_obstacle(position, maxf(size.x, size.z) * 0.44)
	return true

func _place_stump(position: Vector3) -> bool:
	if not _can_place(position, 0.9):
		return false
	var size := rng.randf_range(0.67, 0.92)
	_batch_prop("BurntStumps", BURNT_STUMP, position, rng.randf() * TAU, size)
	var collider_height := 1.45 * size
	_add_cylinder_collider(position + Vector3(0, collider_height * 0.5, 0), 0.55 * size, collider_height)
	_add_obstacle(position, 0.6)
	return true

func _place_haystack(position: Vector3) -> bool:
	if not _can_place(position, 1.5):
		return false
	_batch_prop("Haystacks", HAYSTACK, position, rng.randf() * TAU, rng.randf_range(0.94, 1.06))
	_add_cylinder_collider(position + Vector3(0, 1.2, 0), 1.0, 2.4)
	_add_obstacle(position, 1.15)
	return true

func _place_hive(position: Vector3) -> bool:
	if not _can_place(position, 1.1):
		return false
	_batch_prop("Beehives", BEEHIVE, position, rng.randf() * TAU, rng.randf_range(0.94, 1.05))
	_add_cylinder_collider(position + Vector3(0, 0.79, 0), 0.58, 1.58)
	_add_obstacle(position, 0.68)
	return true

func _place_doll(position: Vector3, height: float) -> bool:
	if not _can_place(position, 0.9):
		return false
	var size := height / 2.44
	_batch_prop("StrawDolls", STRAW_DOLL, position, rng.randf() * TAU, size)
	_add_cylinder_collider(position + Vector3(0, height * 0.5, 0), 0.28, height)
	_add_obstacle(position, 0.42)
	return true

func _place_well(position: Vector3) -> bool:
	if not _can_place(position, 1.8):
		return false
	_batch_prop("OldWells", OLD_WELL, position, rng.randf() * TAU, rng.randf_range(0.96, 1.04))
	_add_cylinder_collider(position + Vector3(0, 0.45, 0), 1.25, 0.95)
	_add_obstacle(position, 1.35)
	return true

func _place_tower(position: Vector3, height: float) -> bool:
	if not _can_place(position, 3.4):
		return false
	var turn := rng.randf_range(-0.3, 0.3)
	var size := (height + 2.0) / 12.555
	_batch_prop("SilentTowers", SILENT_TOWER, position, turn, size)
	_add_box_collider(position + Vector3(0, height * 0.5, 0), Vector3(4.6, height, 4.6), turn)
	_add_obstacle(position, 3.2)
	return true

func _place_millstone(position: Vector3) -> bool:
	if not _can_place(position, 4.0):
		return false
	_batch_prop("Millstones", MILLSTONE, position, rng.randf() * TAU, 1.0)
	_add_cylinder_collider(position + Vector3(0, 0.45, 0), 3.7, 0.95)
	_add_obstacle(position, 3.6)
	return true

func _place_water(centre: Vector3, size: Vector2, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.06, size.y)
	var material := _transparent_emissive_material(color, 0.25)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.15
	material.metallic = 0.35
	mesh.material = material
	var water := MeshInstance3D.new()
	water.name = "StillWater"
	water.mesh = mesh
	water.position = centre
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _place_gate_arch(position: Vector3, turn: float) -> void:
	_add_visual(GATE, position, turn)
	var side := Vector3(cos(turn), 0.0, -sin(turn)) * 2.55
	for offset in [side, -side]:
		_add_box_collider(position + offset + Vector3(0, 1.7, 0), Vector3(0.8, 3.4, 0.9), turn)
		_add_obstacle(position + offset, 0.7)

func _solid_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material

# --- Проходимость и точки для объектов --------------------------------------

func _add_obstacle(position: Vector3, radius: float) -> void:
	obstacle_circles.append(Vector3(position.x, position.z, radius))

func _add_obstacle_line(from: Vector3, to: Vector3, radius: float) -> void:
	var steps := maxi(1, int(from.distance_to(to) / maxf(0.6, radius * 1.3)))
	for index in range(steps + 1):
		_add_obstacle(from.lerp(to, float(index) / float(steps)), radius)

func _reserve(position: Vector3, radius: float) -> void:
	reserved_circles.append(Vector3(position.x, position.z, radius))

## Можно ли поставить препятствие: не за краем карты и не поперёк тропы.
func _can_place(position: Vector3, radius: float) -> bool:
	if absf(position.x) > HALF_MAP - radius * 0.5 or absf(position.z) > HALF_MAP - radius * 0.5:
		return false
	if _distance_to_path(position) < radius + CORRIDOR_HALF_WIDTH:
		return false
	return _is_clear(position, radius)

## Свободна ли точка от уже поставленных препятствий.
func _is_clear(position: Vector3, radius: float) -> bool:
	for circle in obstacle_circles:
		if Vector2(position.x - circle.x, position.z - circle.y).length() < radius + circle.z:
			return false
	return true

func _distance_to_path(position: Vector3) -> float:
	var best := INF
	for index in range(path_points.size() - 1):
		best = minf(best, _distance_to_segment(position, path_points[index], path_points[index + 1]))
	return best

func _distance_to_segment(position: Vector3, from: Vector3, to: Vector3) -> float:
	var span := Vector2(to.x - from.x, to.z - from.z)
	var point := Vector2(position.x - from.x, position.z - from.z)
	var length_squared := span.length_squared()
	if length_squared < 0.0001:
		return point.length()
	var t := clampf(point.dot(span) / length_squared, 0.0, 1.0)
	return (point - span * t).length()

## Смещение тропы по X на заданной глубине — застройка идёт вдоль дороги.
func _path_x_at(z: float) -> float:
	for index in range(path_points.size() - 1):
		var from: Vector3 = path_points[index]
		var to: Vector3 = path_points[index + 1]
		if (z <= from.z and z >= to.z) or (z >= from.z and z <= to.z):
			var span := from.z - to.z
			if absf(span) < 0.001:
				return from.x
			var t := (from.z - z) / span
			return lerpf(from.x, to.x, t)
	return 0.0

## Заливкой от точки старта отбираем клетки, куда игрок действительно дойдёт.
func _collect_free_spots() -> void:
	var cells := GRID_SIZE * GRID_SIZE
	var blocked := PackedByteArray()
	blocked.resize(cells)
	var busy := PackedByteArray()
	busy.resize(cells)
	for circle in obstacle_circles:
		_stamp(blocked, circle, PLAYER_CLEARANCE)
		_stamp(busy, circle, PROP_CLEARANCE)
	for circle in reserved_circles:
		_stamp(busy, circle, 0.0)
	var visited := PackedByteArray()
	visited.resize(cells)
	var start := Vector2i(_grid_index(SPAWN_POINT.x), _grid_index(SPAWN_POINT.z))
	var queue: Array[Vector2i] = [start]
	visited[start.x + start.y * GRID_SIZE] = 1
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in steps:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= GRID_SIZE or next.y >= GRID_SIZE:
				continue
			var index := next.x + next.y * GRID_SIZE
			if visited[index] == 1 or blocked[index] == 1:
				continue
			visited[index] = 1
			queue.append(next)
	free_spots.clear()
	for iz in range(GRID_SIZE):
		for ix in range(GRID_SIZE):
			var index := ix + iz * GRID_SIZE
			if visited[index] == 0 or busy[index] == 1:
				continue
			var spot := Vector3(_grid_position(ix), 0.0, _grid_position(iz))
			if Vector2(spot.x, spot.z).length() > PLAY_RADIUS:
				continue
			free_spots.append(spot)
	_shuffle_spots()

func _stamp(field: PackedByteArray, circle: Vector3, margin: float) -> void:
	var radius: float = circle.z + margin
	var min_ix := maxi(0, _grid_index(circle.x - radius))
	var max_ix := mini(GRID_SIZE - 1, _grid_index(circle.x + radius))
	var min_iz := maxi(0, _grid_index(circle.y - radius))
	var max_iz := mini(GRID_SIZE - 1, _grid_index(circle.y + radius))
	for iz in range(min_iz, max_iz + 1):
		var z := _grid_position(iz)
		for ix in range(min_ix, max_ix + 1):
			if Vector2(_grid_position(ix) - circle.x, z - circle.y).length() <= radius:
				field[ix + iz * GRID_SIZE] = 1

func _grid_index(value: float) -> int:
	return clampi(int(round((value + HALF_MAP) / CELL_SIZE)), 0, GRID_SIZE - 1)

func _grid_position(index: int) -> float:
	return float(index) * CELL_SIZE - HALF_MAP

func _shuffle_spots() -> void:
	for index in range(free_spots.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var keep: Vector3 = free_spots[index]
		free_spots[index] = free_spots[swap]
		free_spots[swap] = keep

## Выдаёт свободную точку нужного пояса. Никогда не возвращает пустоту:
## иначе на уровне окажется меньше печатей или врагов, чем обещано.
## sector — пожелание по направлению от центра карты (середина и половина
## ширины в радианах). Направление уступает первым: пояс и запас между
## объектами важнее, чем красивый разброс.
func _take_spot(zone: String, min_gap: float, sector := Vector2.ZERO) -> Vector3:
	if sector.y > 0.0:
		for attempt in range(2):
			var aimed := _claim_spot(zone, min_gap * pow(0.6, float(attempt)), sector)
			if aimed != NO_SPOT:
				return aimed
		sector_misses += 1
	for attempt in range(3):
		var gap := min_gap * pow(0.5, float(attempt))
		var spot := _claim_spot("" if attempt >= 2 else zone, gap, Vector2.ZERO)
		if spot != NO_SPOT:
			return spot
	var fallback: Vector3 = path_points[(taken_spots.size() + 1) % path_points.size()]
	fallback_spots += 1
	taken_spots.append(fallback)
	return fallback

## Пустой zone означает «пояс не важен», нулевой sector — «направление не важно».
func _claim_spot(zone: String, gap: float, sector: Vector2) -> Vector3:
	for index in range(free_spots.size()):
		var candidate: Vector3 = free_spots[index]
		if not zone.is_empty() and not _spot_matches(candidate, zone):
			continue
		if sector.y > 0.0 and not _spot_in_sector(candidate, sector):
			continue
		if not _spot_apart(candidate, gap):
			continue
		free_spots.remove_at(index)
		taken_spots.append(candidate)
		return candidate
	return NO_SPOT

func _spot_in_sector(position: Vector3, sector: Vector2) -> bool:
	var angle := Vector2(position.x, position.z).angle()
	return absf(angle_difference(sector.x, angle)) <= sector.y

func _spot_matches(position: Vector3, zone: String) -> bool:
	var from_centre := Vector2(position.x, position.z).length()
	match zone:
		"rim":
			return from_centre > 11.0 and position.distance_to(SPAWN_POINT) > 7.0
		"mid":
			return from_centre > 5.0 and from_centre < 21.0
		"path":
			return _distance_to_path(position) < 8.0
		"near":
			var to_spawn := position.distance_to(SPAWN_POINT)
			return from_centre > 8.0 and to_spawn > 8.0 and to_spawn < 17.0
		"guard":
			return position.distance_to(SPAWN_POINT) > 11.0
	return true

func _spot_apart(position: Vector3, gap: float) -> bool:
	for taken in taken_spots:
		if taken.distance_to(position) < gap:
			return false
	return true

func _patrol_route() -> Array[Vector3]:
	var route: Array[Vector3] = []
	for index in range(4):
		route.append(_take_spot("mid", 8.0))
	return route

func _spawn_player_and_audio() -> void:
	audio = AUDIO_SCRIPT.new()
	audio.name = "ProceduralAudio"
	add_child(audio)
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, 0.1, 25)
	add_child(player)
	player.footstep.connect(func(intensity: float): audio.play_step(intensity))

## Печати игрок ищет сам, и одного «куда свободно» мало: на втором уровне все
## четыре выпадали в дальнюю полосу карты — до ближайшей было 43 м при том, что
## на остальных уровнях первая печать лежит в 8-16 м. Игрок обходил карту
## целиком, не понимая, куда идти. Теперь у каждой печати свой сектор вокруг
## центра: находки идут по всей карте, и хотя бы одна лежит недалеко от старта.
func _spawn_seals() -> void:
	var span := TAU / float(seals_required)
	var turn := rng.randf() * TAU
	# Печать того сектора, куда смотрит старт, держим в ближнем поясе: первую
	# находку игрок должен сделать быстро, иначе он не понимает, что ищет.
	var spawn_angle := Vector2(SPAWN_POINT.x, SPAWN_POINT.z).angle()
	var near_index := 0
	var near_delta := INF
	for index in range(seals_required):
		var delta := absf(angle_difference(spawn_angle, turn + span * float(index)))
		if delta < near_delta:
			near_delta = delta
			near_index = index
	for index in range(seals_required):
		var seal: Area3D = SEAL_SCENE.instantiate()
		var sector := Vector2(wrapf(turn + span * float(index), -PI, PI), span * 0.40)
		seal.position = _take_spot("near" if index == near_index else "rim", 7.5, sector) + Vector3(0, 1, 0)
		seal.name = "SunSeal%d" % (index + 1)
		add_child(seal)
		seal_nodes.append(seal)
		seal.collected.connect(_on_seal_collected)

func _spawn_curses() -> void:
	for index in range(curse_required):
		var curse := Area3D.new()
		curse.name = "CursedEffigy%d" % (index + 1)
		curse.position = _take_spot("mid", 6.0)
		curse.rotation.y = rng.randf() * TAU
		curse.set_meta("kind", "curse")
		curse.set_meta("cleansed", false)
		var model := CURSED_EFFIGY.instantiate()
		model.name = "RitualEffigyModel"
		curse.add_child(model)
		var shape := CylinderShape3D.new()
		shape.radius = 2.35
		shape.height = 3.2
		var collision := CollisionShape3D.new()
		collision.position.y = 1.6
		collision.shape = shape
		curse.add_child(collision)
		var light := OmniLight3D.new()
		light.name = "CurseLight"
		light.position.y = 1.6
		light.light_color = Color(0.72, 0.025, 0.22)
		light.light_energy = 0.85
		light.omni_range = 4.0
		light.shadow_enabled = false
		curse.add_child(light)
		curse.body_entered.connect(_on_interactable_entered.bind(curse))
		curse.body_exited.connect(_on_interactable_exited.bind(curse))
		add_child(curse)
		curse_nodes.append(curse)

func _spawn_altars() -> void:
	for index in range(altar_required):
		var altar := Area3D.new()
		altar.name = "BurialFire%d" % (index + 1)
		altar.position = _take_spot("path", 9.0)
		altar.set_meta("kind", "altar")
		altar.set_meta("lit", false)
		var shape := CylinderShape3D.new()
		shape.radius = 1.55
		shape.height = 2.4
		var collision := CollisionShape3D.new()
		collision.position.y = 1.2
		collision.shape = shape
		altar.add_child(collision)
		var visual := Node3D.new()
		visual.name = "Visual"
		altar.add_child(visual)
		var altar_model := BURIAL_ALTAR.instantiate()
		altar_model.name = "BurialAltarModel"
		visual.add_child(altar_model)
		var ember_bed := CylinderMesh.new()
		ember_bed.top_radius = 0.30
		ember_bed.bottom_radius = 0.34
		ember_bed.height = 0.055
		ember_bed.radial_segments = 12
		var material := _emissive_material(Color(0.16, 0.006, 0.003), 0.45)
		ember_bed.material = material
		var mesh := MeshInstance3D.new()
		mesh.name = "EmberBed"
		mesh.position.y = 0.70
		mesh.mesh = ember_bed
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(mesh)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.78
		ring_mesh.outer_radius = 0.90
		ring_mesh.rings = 18
		ring_mesh.ring_segments = 6
		ring_mesh.material = material
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.position.y = 0.10
		ring.rotation.x = PI * 0.5
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(ring)
		var light := OmniLight3D.new()
		light.name = "Light"
		light.position.y = 1.15
		light.light_color = Color(1.0, 0.16, 0.02)
		light.light_energy = 0.18
		light.omni_range = 4.2
		light.shadow_enabled = false
		visual.add_child(light)
		altar.set_meta("material", material)
		altar.body_entered.connect(_on_interactable_entered.bind(altar))
		altar.body_exited.connect(_on_interactable_exited.bind(altar))
		add_child(altar)
		altar_nodes.append(altar)

func _spawn_sun_well() -> void:
	_add_visual(TOTEM, totem_point)
	_add_cylinder_collider(totem_point + Vector3(0, 2.0, 0), 0.50, 4.0)
	well_area = Area3D.new()
	well_area.name = "SunWell"
	well_area.position = totem_point
	well_area.set_meta("kind", "well")
	var shape := CylinderShape3D.new()
	shape.radius = 2.35
	shape.height = 3.0
	var collision := CollisionShape3D.new()
	collision.position.y = 1.5
	collision.shape = shape
	well_area.add_child(collision)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.20
	ring_mesh.outer_radius = 1.30
	ring_mesh.rings = 22
	ring_mesh.ring_segments = 6
	ring_mesh.material = _emissive_material(Color(1.0, 0.42, 0.035), 1.7)
	var ring := MeshInstance3D.new()
	ring.name = "WellRing"
	ring.position.y = 0.16
	ring.rotation.x = PI * 0.5
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	well_area.add_child(ring)
	var light := OmniLight3D.new()
	light.name = "WellLight"
	light.position.y = 2.2
	light.light_color = Color(1.0, 0.42, 0.05)
	light.light_energy = 0.75
	light.omni_range = 5.0
	light.shadow_enabled = false
	well_area.add_child(light)
	well_area.body_entered.connect(_on_interactable_entered.bind(well_area))
	well_area.body_exited.connect(_on_interactable_exited.bind(well_area))
	add_child(well_area)

func _spawn_rifts() -> void:
	var rift_count := clampi(int(float(level_number - 3) / 2.0), 0, 8)
	for index in range(rift_count):
		var rift := Node3D.new()
		rift.name = "ShadowRift%d" % (index + 1)
		rift.position = _take_spot("any", 5.5) + Vector3(0, 0.05, 0)
		rift.set_meta("radius", 2.05 + float(level_number) * 0.025)
		var material := _transparent_emissive_material(Color(0.35, 0.015, 0.42, 0.52), 1.55)
		var pool_mesh := CylinderMesh.new()
		pool_mesh.top_radius = 1.85
		pool_mesh.bottom_radius = 2.12
		pool_mesh.height = 0.045
		pool_mesh.radial_segments = 24
		pool_mesh.material = material
		var pool := MeshInstance3D.new()
		pool.mesh = pool_mesh
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rift.add_child(pool)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 1.55
		ring_mesh.outer_radius = 1.86
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring_mesh.material = material
		var ring := MeshInstance3D.new()
		ring.name = "RiftRing"
		ring.position.y = 0.05
		ring.rotation.x = PI * 0.5
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rift.add_child(ring)
		add_child(rift)
		rift_nodes.append(rift)

func _spawn_enemies() -> void:
	var patrol := _patrol_route()
	for index in range(enemy_count):
		var guardian: CharacterBody3D = GUARDIAN_SCENE.instantiate()
		guardian.name = "Enemy%d" % (index + 1)
		guardian.position = _take_spot("guard", 8.0) + Vector3(0, 0.1, 0)
		guardian.sun_speed = minf(5.45, 3.15 + float(level_number - 2) * 0.11 + index * 0.035)
		guardian.shadow_speed = minf(7.55, 4.9 + float(level_number - 2) * 0.14 + index * 0.05)
		guardian.attack_damage = minf(25.0, 15.0 + level_number * 0.42 + index * 0.36)
		guardian.attack_interval = maxf(0.74, 1.18 - float(level_number - 2) * 0.018)
		add_child(guardian)
		guardian.apply_kind(_enemy_kind_for(index))
		guardian.configure(player, patrol)
		guardian.hit.connect(_on_enemy_hit.bind(guardian))
		guardian.charge_started.connect(_on_guardian_charge)
		guardian.wail.connect(_on_enemy_wail.bind(guardian))
		enemies.append(guardian)

## Состав врагов: чем дальше уровень, тем больше видов выходит на карту.
func _spawn_trap_zones() -> void:
	if level_number < 5:
		return
	var trap_count := 2 if level_number >= 14 else 1
	for index in range(trap_count):
		var trap := Area3D.new()
		trap.name = "SunSnare%d" % (index + 1)
		trap.position = _take_spot("path", 8.0)
		trap.rotation.y = rng.randf() * TAU
		trap.set_meta("armed", true)
		var shape := CylinderShape3D.new()
		shape.radius = 1.68
		shape.height = 2.6
		var collision := CollisionShape3D.new()
		collision.position.y = 1.30
		collision.shape = shape
		trap.add_child(collision)
		var model := SUN_TRAP.instantiate()
		model.name = "SunTrapModel"
		trap.add_child(model)
		var light := OmniLight3D.new()
		light.name = "TrapLight"
		light.position.y = 0.35
		light.light_color = Color(1.0, 0.44, 0.06)
		light.light_energy = 0.35
		light.omni_range = 3.5
		light.shadow_enabled = false
		trap.add_child(light)
		trap.body_entered.connect(_on_trap_body_entered.bind(trap))
		add_child(trap)
		trap_zones.append(trap)

func _on_trap_body_entered(body: Node3D, trap: Area3D) -> void:
	if state != RunState.PLAYING or not trap.get_meta("armed", false):
		return
	if not body.has_method("capture_in_trap") or not bool(body.get("active")) or bool(body.get("trapped")):
		return
	trap.set_meta("armed", false)
	trapped_enemies += 1
	body.capture_in_trap()
	body.set_deferred("global_position", Vector3(trap.global_position.x, body.global_position.y, trap.global_position.z))
	var light := trap.get_node_or_null("TrapLight") as OmniLight3D
	if light != null:
		light.light_color = Color(1.0, 0.80, 0.30)
		create_tween().tween_property(light, "light_energy", 1.6, 0.35)
	var model := trap.get_node_or_null("SunTrapModel") as Node3D
	if model != null:
		var overlay := _transparent_emissive_material(Color(1.0, 0.48, 0.05, 0.34), 1.4)
		for mesh in _mesh_nodes(model):
			mesh.material_overlay = overlay
		create_tween().tween_property(model, "scale", Vector3.ONE * 1.08, 0.28).set_trans(Tween.TRANS_BACK)
	audio.play_event("seal", 0.86)
	_show_hint(_tr("trap_caught") % trapped_enemies, 3.0)

func _enemy_kind_for(index: int) -> String:
	if index == 0:
		return GUARDIAN_KIND.KIND_WARDEN
	var roster: Array[String] = [GUARDIAN_KIND.KIND_WARDEN]
	if level_number >= 4:
		roster.append(GUARDIAN_KIND.KIND_HUSK)
	if level_number >= 6:
		roster.append(GUARDIAN_KIND.KIND_STALKER)
	if level_number >= 9:
		roster.append(GUARDIAN_KIND.KIND_RINGER)
	if level_number >= 12:
		roster.append(GUARDIAN_KIND.KIND_SENTINEL)
	return roster[(index + level_number) % roster.size()]

func _enemy_kinds_present() -> Array[String]:
	var kinds: Array[String] = []
	for index in range(enemy_count):
		var kind := _enemy_kind_for(index)
		if not kinds.has(kind):
			kinds.append(kind)
	return kinds

func _build_exit() -> void:
	_add_visual(GATE, Vector3(0, 0, -27))
	_add_gate_doors()
	var blocker := StaticBody3D.new()
	blocker.name = "GateWardBlocker"
	gate_blocker = CollisionShape3D.new()
	var blocker_shape := BoxShape3D.new()
	blocker_shape.size = Vector3(4.2, 3.5, 0.7)
	gate_blocker.shape = blocker_shape
	blocker.add_child(gate_blocker)
	blocker.position = Vector3(0, 1.75, -27)
	add_child(blocker)
	gate_area = Area3D.new()
	gate_area.name = "NorthGate"
	var exit_shape := BoxShape3D.new()
	exit_shape.size = Vector3(4.2, 3.0, 2.0)
	var exit_collision := CollisionShape3D.new()
	exit_collision.shape = exit_shape
	gate_area.add_child(exit_collision)
	gate_area.position = Vector3(0, 1.5, -28)
	gate_area.body_entered.connect(_on_gate_entered)
	add_child(gate_area)

	exit_path = Node3D.new()
	exit_path.name = "ExitSunPath"
	exit_path.visible = false
	add_child(exit_path)
	var path_material := _transparent_emissive_material(Color(1.0, 0.34, 0.035, 0.64), 2.0)
	for index in range(6):
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.48
		ring_mesh.outer_radius = 0.60
		ring_mesh.rings = 16
		ring_mesh.ring_segments = 5
		ring_mesh.material = path_material
		var ring := MeshInstance3D.new()
		ring.position = Vector3(0, 0.10, -25.0 - index * 1.3)
		ring.rotation.x = PI * 0.5
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		exit_path.add_child(ring)

func _add_gate_doors() -> void:
	gate_doors.clear()
	for index in range(2):
		var leaf := GATE_DOOR.instantiate() as Node3D
		leaf.name = "LeftGateDoor" if index == 0 else "RightGateDoor"
		leaf.position = Vector3(-2.02 if index == 0 else 2.02, 0.0, -27.0)
		if index == 1:
			leaf.scale.x = -1.0
		add_child(leaf)
		gate_doors.append(leaf)

func _open_gate_doors() -> void:
	if gate_doors.size() != 2:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(gate_doors[0], "rotation:y", deg_to_rad(-102.0), 1.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(gate_doors[1], "rotation:y", deg_to_rad(102.0), 1.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)

func _build_objective_beacon() -> void:
	objective_beacon = Node3D.new()
	objective_beacon.name = "ObjectiveBeacon"
	add_child(objective_beacon)
	var material := _transparent_emissive_material(Color(1.0, 0.48, 0.045, 0.42), 1.7)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.035
	beam_mesh.bottom_radius = 0.10
	beam_mesh.height = 6.0
	beam_mesh.radial_segments = 8
	beam_mesh.material = material
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	beam.position.y = 3.0
	beam.mesh = beam_mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objective_beacon.add_child(beam)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.75
	ring_mesh.outer_radius = 0.88
	ring_mesh.rings = 18
	ring_mesh.ring_segments = 5
	ring_mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.rotation.x = PI * 0.5
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objective_beacon.add_child(ring)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ChallengeUI"
	add_child(layer)
	danger_overlay = ColorRect.new()
	danger_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	danger_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_overlay.color = Color(0.42, 0.0, 0.04, 0.0)
	var danger_shader := Shader.new()
	danger_shader.code = "shader_type canvas_item; void fragment(){ vec2 p=UV*2.0-1.0; float e=smoothstep(0.48,1.02,length(p*vec2(0.72,1.0))); COLOR=vec4(COLOR.rgb,COLOR.a*e); }"
	var danger_material := ShaderMaterial.new()
	danger_material.shader = danger_shader
	danger_overlay.material = danger_material
	layer.add_child(danger_overlay)

	var hud_panel := Panel.new()
	hud_panel.position = Vector2(16, 14)
	hud_panel.size = Vector2(620, 160)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.035, 0.018, 0.035, 0.78)
	hud_style.border_width_left = 2
	hud_style.border_width_top = 2
	hud_style.border_width_right = 2
	hud_style.border_width_bottom = 2
	hud_style.border_color = Color(0.78, 0.38, 0.12, 0.62)
	hud_style.corner_radius_top_left = 7
	hud_style.corner_radius_top_right = 7
	hud_style.corner_radius_bottom_left = 7
	hud_style.corner_radius_bottom_right = 7
	hud_panel.add_theme_stylebox_override("panel", hud_style)
	layer.add_child(hud_panel)
	objective = _make_label(Vector2(28, 22), Vector2(900, 31), 21, Color(1.0, 0.91, 0.63))
	secondary_objective = _make_label(Vector2(28, 52), Vector2(890, 25), 15, Color(0.92, 0.69, 0.38))
	status = _make_label(Vector2(28, 78), Vector2(600, 25), 15, Color(1.0, 0.60, 0.24))
	pulse_label = _make_label(Vector2(280, 110), Vector2(320, 24), 14, Color(0.98, 0.72, 0.28))
	hint = _make_label(Vector2(140, 590), Vector2(1000, 64), 20, Color(1.0, 0.88, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt = _make_label(Vector2(340, 532), Vector2(600, 44), 18, Color(1.0, 0.93, 0.69))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for label in [objective, secondary_objective, status, pulse_label, hint, prompt]:
		layer.add_child(label)
	health_bar = _make_bar(Vector2(28, 111), Color(0.83, 0.14, 0.05))
	stamina_bar = _make_bar(Vector2(28, 137), Color(0.98, 0.58, 0.08))
	layer.add_child(health_bar)
	layer.add_child(stamina_bar)
	var crosshair := _make_label(Vector2.ZERO, Vector2(24, 24), 18, Color(1, 0.91, 0.68, 0.8))
	crosshair.name = "Crosshair"
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.position = Vector2(-12, -12)
	layer.add_child(crosshair)

	touch_controls = TOUCH_SCRIPT.new()
	touch_controls.name = "TouchControls"
	touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_controls.move_changed.connect(player.set_touch_move)
	touch_controls.look_changed.connect(player.add_touch_look)
	touch_controls.action_pressed.connect(_handle_action)
	touch_controls.pause_pressed.connect(_toggle_pause)
	layer.add_child(touch_controls)
	_build_intro(layer)
	_build_end_screen(layer)
	pause_label = _make_label(Vector2(0, 310), Vector2(1280, 100), 32, Color(1.0, 0.86, 0.46))
	pause_label.text = _tr("pause")
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.visible = false
	layer.add_child(pause_label)

func _build_intro(layer: CanvasLayer) -> void:
	intro_screen = ColorRect.new()
	intro_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_screen.color = Color(0.014, 0.011, 0.009, 0.92)
	layer.add_child(intro_screen)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 360)
	panel.add_theme_stylebox_override("panel", _dialog_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(0, 78)
	logo.texture = BRAND_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(logo)
	intro_title_label = _make_label(Vector2.ZERO, Vector2(640, 50), 31, Color(1.0, 0.93, 0.76))
	intro_title_label.text = _level_title()
	intro_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(intro_title_label)
	intro_story_label = _make_label(Vector2.ZERO, Vector2(640, 135), 18, Color(0.96, 0.86, 0.70))
	intro_story_label.text = _intro_description()
	intro_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(intro_story_label)
	intro_controls_label = _make_label(Vector2.ZERO, Vector2(640, 48), 16, Color(0.82, 0.67, 0.48))
	intro_controls_label.text = _tr("controls")
	intro_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(intro_controls_label)
	intro_start_button = Button.new()
	intro_start_button.text = _tr("start")
	intro_start_button.custom_minimum_size = Vector2(0, 55)
	intro_start_button.add_theme_font_size_override("font_size", 20)
	_style_dialog_button(intro_start_button, true)
	intro_start_button.pressed.connect(_start_level)
	content.add_child(intro_start_button)
	intro_menu_button = Button.new()
	intro_menu_button.text = _tr("menu")
	intro_menu_button.custom_minimum_size = Vector2(0, 45)
	intro_menu_button.add_theme_font_size_override("font_size", 16)
	_style_dialog_button(intro_menu_button, false)
	intro_menu_button.pressed.connect(_return_to_menu)
	content.add_child(intro_menu_button)

func _build_end_screen(layer: CanvasLayer) -> void:
	end_screen = ColorRect.new()
	end_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_screen.color = Color(0.014, 0.010, 0.009, 0.92)
	end_screen.visible = false
	layer.add_child(end_screen)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 300)
	panel.add_theme_stylebox_override("panel", _dialog_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(0, 68)
	logo.texture = BRAND_LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(logo)
	end_title = _make_label(Vector2.ZERO, Vector2(560, 50), 30, Color(1.0, 0.93, 0.76))
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(end_title)
	end_details = _make_label(Vector2.ZERO, Vector2(560, 115), 18, Color(0.95, 0.84, 0.68))
	end_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(end_details)
	if FLOW.has_next_challenge(level_number):
		end_next_button = Button.new()
		end_next_button.text = _tr("next")
		end_next_button.custom_minimum_size = Vector2(0, 52)
		end_next_button.add_theme_font_size_override("font_size", 19)
		_style_dialog_button(end_next_button, true)
		end_next_button.pressed.connect(_open_next_level)
		content.add_child(end_next_button)
	death_reward_button = Button.new()
	death_reward_button.text = _tr("reward_life")
	death_reward_button.custom_minimum_size = Vector2(0, 56)
	death_reward_button.add_theme_font_size_override("font_size", 19)
	death_reward_button.visible = false
	_style_dialog_button(death_reward_button, true)
	death_reward_button.pressed.connect(_request_rewarded_life)
	content.add_child(death_reward_button)
	end_restart_button = Button.new()
	end_restart_button.text = _tr("restart")
	end_restart_button.custom_minimum_size = Vector2(0, 52)
	end_restart_button.add_theme_font_size_override("font_size", 19)
	_style_dialog_button(end_restart_button, not FLOW.has_next_challenge(level_number))
	end_restart_button.pressed.connect(_restart_level)
	content.add_child(end_restart_button)
	end_menu_button = Button.new()
	end_menu_button.text = _tr("menu")
	end_menu_button.custom_minimum_size = Vector2(0, 45)
	end_menu_button.add_theme_font_size_override("font_size", 16)
	_style_dialog_button(end_menu_button, false)
	end_menu_button.pressed.connect(_return_to_menu)
	content.add_child(end_menu_button)

func _start_level() -> void:
	state = RunState.PLAYING
	intro_screen.visible = false
	player.set_controls_enabled(true)
	elapsed = 0.0
	yandex.gameplay_start()
	_show_hint(_tr("intro_hint"), 4.5)

func _handle_action() -> void:
	if state != RunState.PLAYING:
		return
	if _try_interaction():
		return
	_try_sun_pulse()

func _try_interaction() -> bool:
	_refresh_interactable()
	if not is_instance_valid(current_interactable):
		return false
	var kind := String(current_interactable.get_meta("kind", ""))
	if kind == "curse":
		if current_interactable.get_meta("cleansed", false):
			return true
		_try_sun_pulse(current_interactable)
		return true
	if kind == "well":
		_use_sun_well()
		return true
	if kind == "altar":
		if current_interactable.get_meta("lit", false):
			return true
		if seals_found < seals_required:
			_show_hint(_tr("fire_need_seals"), 2.2)
			return true
		if curses_cleansed < curse_required:
			_show_hint(_tr("fire_need_curses"), 2.2)
			return true
		_light_altar(current_interactable)
		return true
	return false

func _use_sun_well() -> void:
	if well_used:
		_show_hint(_tr("well_empty"), 1.6)
		return
	well_used = true
	_change_health(45.0)
	player.restore_stamina(70.0)
	pulse_cooldown = 0.0
	audio.play_event("totem")
	var light := well_area.get_node_or_null("WellLight") as OmniLight3D
	if light != null:
		light.light_energy = 3.0
		create_tween().tween_property(light, "light_energy", 0.08, 1.2)
	var ring := well_area.get_node_or_null("WellRing") as MeshInstance3D
	if ring != null:
		create_tween().tween_property(ring, "scale", Vector3.ONE * 2.5, 0.75)
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			enemy.enrage(8.0 + level_number * 0.25)
	_show_hint(_tr("well_used"), 3.2)

func _try_sun_pulse(forced_curse: Node3D = null) -> void:
	if seals_found == 0:
		_show_hint(_tr("pulse_locked"), 1.8)
		return
	if pulse_cooldown > 0.0:
		_show_hint(_tr("pulse_cooldown") % pulse_cooldown, 1.4)
		return
	if not player.spend_stamina(PULSE_COST):
		_show_hint(_tr("pulse_tired"), 1.5)
		return
	pulses_used += 1
	pulse_cooldown = maxf(3.1, 6.6 - float(level_number - 2) * 0.12)
	audio.play_event("pulse")
	_spawn_pulse_visual()
	var affected := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(player.global_position) < 8.0:
			enemy.stun(1.15 + float(seals_found) * 0.055)
			enemy.repel_from(player.global_position, 5.6)
			affected += 1
	var curse := forced_curse if is_instance_valid(forced_curse) and not forced_curse.get_meta("cleansed", false) and forced_curse.global_position.distance_to(player.global_position) <= 3.2 else _nearest_uncleansed_curse(8.5)
	var cleansed := false
	if curse != null:
		_cleanse_curse(curse)
		cleansed = true
	if cleansed:
		_show_hint(_tr("pulse_cleanse") % [curses_cleansed, curse_required, affected], 2.4)
	elif affected > 0:
		_show_hint(_tr("pulse_hit") % affected, 1.7)
	else:
		_show_hint(_tr("pulse_miss"), 1.7)

func _cleanse_curse(curse: Node3D) -> void:
	if curse.get_meta("cleansed", false):
		return
	curse.set_meta("cleansed", true)
	curses_cleansed += 1
	var tween := create_tween().set_parallel(true)
	tween.tween_property(curse, "scale", Vector3.ZERO, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(curse, "position:y", curse.position.y + 1.3, 0.55)
	tween.chain().tween_callback(curse.queue_free)
	audio.play_event("seal", 1.22)
	_update_hud()
	_refresh_objective_beacon()

func _light_altar(altar: Area3D) -> void:
	altar.set_meta("lit", true)
	altars_lit += 1
	var material: StandardMaterial3D = altar.get_meta("material")
	material.albedo_color = Color(1.0, 0.21, 0.025)
	material.emission = Color(1.0, 0.055, 0.004)
	material.emission_energy_multiplier = 3.4
	var light := altar.get_node_or_null("Visual/Light") as OmniLight3D
	if light != null:
		light.light_energy = 2.2
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			enemy.enrage(4.5 + level_number * 0.28)
	audio.play_event("totem")
	_show_hint(_tr("fire_lit") % [altars_lit, altar_required], 2.8)
	if altars_lit == altar_required:
		_open_gate()
	_update_hud()
	_refresh_objective_beacon()

func _open_gate() -> void:
	exit_open = true
	gate_blocker.set_deferred("disabled", true)
	_open_gate_doors()
	exit_path.visible = true
	escape_remaining = escape_limit
	audio.play_event("gate")
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.enrage(7.0 + level_number * 0.35)
	if escape_limit > 0.0:
		_show_hint(_tr("gate_timed") % int(escape_limit), 4.0)
	else:
		_show_hint(_tr("gate_open"), 4.0)

func _trigger_overtime() -> void:
	overtime = true
	audio.play_event("sunset")
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.enrage(60.0)
	_show_hint(_tr("overtime"), 4.0)

func _on_seal_collected(seal: Area3D) -> void:
	if state != RunState.PLAYING:
		return
	seals_found += 1
	seal_nodes.erase(seal)
	audio.play_event("seal", 1.0 + seals_found * 0.025)
	_change_health(12.0)
	var awaken_count := mini(seals_found, enemies.size())
	var threat_level := mini(8, seals_found + int(float(level_number - 2) / 5.0))
	for index in range(awaken_count):
		enemies[index].awaken(threat_level)
		enemies[index].stun(1.25)
	_show_hint(_tr("seal_found") % [seals_found, seals_required, awaken_count, enemy_count], 2.5)
	_update_hud()
	_refresh_objective_beacon()

func _on_enemy_hit(damage: float, guardian: CharacterBody3D) -> void:
	if state != RunState.PLAYING or hurt_cooldown > 0.0:
		return
	hurt_cooldown = 0.48
	hits_taken += 1
	_change_health(-damage)
	player.apply_knockback(guardian.global_position, 6.0)
	audio.play_event("hit")
	if health > 0.0:
		_show_hint(_tr("wounded"), 1.8)

func _on_guardian_charge() -> void:
	if state == RunState.PLAYING:
		_show_hint(_tr("charge"), 1.45)

## Крик плакальщицы: волна расходится по земле и будит всех, кого достала.
func _on_enemy_wail(origin: Vector3, radius: float, source: CharacterBody3D) -> void:
	if state != RunState.PLAYING:
		return
	_spawn_wail_visual(origin, radius)
	audio.play_event("charge", 0.58)
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy == source:
			continue
		if enemy.global_position.distance_to(origin) <= radius * 1.9:
			enemy.enrage(5.5)
	if player.global_position.distance_to(origin) <= radius:
		_show_hint(_tr("wail"), 1.6)

func _spawn_wail_visual(origin: Vector3, radius: float) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.86
	mesh.outer_radius = 1.0
	mesh.rings = 22
	mesh.ring_segments = 5
	mesh.material = _transparent_emissive_material(Color(0.62, 0.82, 1.0, 0.6), 1.8)
	var ring := MeshInstance3D.new()
	ring.position = origin + Vector3(0, 0.18, 0)
	ring.rotation.x = PI * 0.5
	ring.scale = Vector3.ONE * 0.3
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * radius, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)

func _on_gate_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or completed:
		return
	if not exit_open:
		_show_hint(_tr("gate_locked"), 2.0)
		return
	_finish_level()

func _finish_level() -> void:
	completed = true
	state = RunState.WON
	player.set_controls_enabled(false)
	var grade := _result_grade()
	objective.text = _tr("level_complete_objective") % level_number
	end_title.text = _tr("level_complete_title")
	end_details.text = _tr("result") % [_format_time(elapsed), hits_taken, pulses_used, deaths, grade]
	death_reward_button.visible = false
	if is_instance_valid(end_next_button):
		end_next_button.visible = true
	end_screen.visible = true
	yandex.gameplay_stop()
	yandex.record_level_result(level_number, elapsed, grade)
	audio.play_event("gate", 1.12)

func _respawn_player(message: String) -> void:
	deaths += 1
	player.reset_to_spawn()
	health = MAX_HEALTH
	player.set_health_ratio(1.0)
	player.restore_stamina(player.max_stamina)
	hurt_cooldown = 2.0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			enemy.stun(2.2)
	_show_hint(message, 2.8)

func _show_death_offer() -> void:
	if state != RunState.PLAYING:
		return
	deaths += 1
	state = RunState.DOWNED
	player.set_controls_enabled(false)
	yandex.gameplay_stop()
	end_title.text = _tr("death_title")
	end_details.text = _tr("death_offer")
	if is_instance_valid(end_next_button):
		end_next_button.visible = false
	death_reward_button.visible = true
	death_reward_button.disabled = not OS.has_feature("web") or not yandex.initialized
	death_reward_button.text = _tr("reward_life") if not death_reward_button.disabled else _tr("reward_yandex_only")
	end_restart_button.text = _tr("restart")
	_style_dialog_button(end_restart_button, false)
	end_screen.visible = true

func _request_rewarded_life() -> void:
	if state != RunState.DOWNED or death_reward_button.disabled:
		return
	death_reward_button.disabled = true
	death_reward_button.text = _tr("reward_loading")
	end_details.text = _tr("reward_wait")
	yandex.show_rewarded_life(_on_rewarded_life_finished)

func _on_rewarded_life_finished(granted: bool) -> void:
	if state != RunState.DOWNED:
		return
	if not granted:
		death_reward_button.disabled = not OS.has_feature("web") or not yandex.initialized
		death_reward_button.text = _tr("reward_life") if not death_reward_button.disabled else _tr("reward_yandex_only")
		end_details.text = _tr("reward_not_completed")
		return
	end_screen.visible = false
	health = MAX_HEALTH
	player.reset_to_spawn()
	player.set_health_ratio(1.0)
	player.restore_stamina(player.max_stamina)
	hurt_cooldown = 2.5
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			enemy.stun(2.8)
	state = RunState.PLAYING
	player.set_controls_enabled(true)
	yandex.gameplay_start()
	_show_hint(_tr("reward_revived"), 3.0)

func _change_health(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_HEALTH)
	player.set_health_ratio(health / MAX_HEALTH)
	if health <= 0.0:
		_show_death_offer()

func _update_rifts(delta: float) -> bool:
	var inside := false
	for rift in rift_nodes:
		if not is_instance_valid(rift):
			continue
		var radius: float = rift.get_meta("radius", 2.1)
		if player.global_position.distance_to(rift.global_position) < radius:
			inside = true
			_change_health(-(3.8 + level_number * 0.12) * delta)
			player.spend_stamina((3.0 + level_number * 0.08) * delta)
			rift_damage_flash = maxf(rift_damage_flash, 0.30)
	return inside

func _is_in_sunlight() -> bool:
	var origin := player.global_position + Vector3(0, 1.0, 0)
	var toward_sun := sun.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + toward_sun * 55.0)
	var exclusions: Array[RID] = [player.get_rid()]
	for enemy in enemies:
		if is_instance_valid(enemy):
			exclusions.append(enemy.get_rid())
	query.exclude = exclusions
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_status(sunlight: bool, in_rift: bool) -> void:
	var closest := INF
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			closest = minf(closest, enemy.global_position.distance_to(player.global_position))
	if in_rift:
		status.text = _tr("status_rift")
		status.add_theme_color_override("font_color", Color(0.95, 0.20, 0.72))
	elif closest < 5.0:
		status.text = _tr("status_guardian")
		status.add_theme_color_override("font_color", Color(1.0, 0.20, 0.12))
	elif overtime:
		status.text = _tr("status_overtime")
		status.add_theme_color_override("font_color", Color(0.86, 0.20, 0.52))
	else:
		status.text = _tr("status_sun") if sunlight else _tr("status_shadow")
		status.add_theme_color_override("font_color", Color(1.0, 0.79, 0.33) if sunlight else Color(1.0, 0.31, 0.18))

func _update_prompt() -> void:
	prompt.text = ""
	_refresh_interactable()
	if not is_instance_valid(current_interactable):
		return
	var kind := String(current_interactable.get_meta("kind", ""))
	if kind == "curse" and not current_interactable.get_meta("cleansed", false):
		prompt.text = _tr("prompt_curse")
	elif kind == "well":
		prompt.text = _tr("prompt_well") if not well_used else _tr("prompt_well_empty")
	elif kind == "altar" and not current_interactable.get_meta("lit", false):
		prompt.text = _tr("prompt_fire")

func _update_danger(in_rift: bool) -> void:
	var closest := INF
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.active:
			closest = minf(closest, enemy.global_position.distance_to(player.global_position))
	var proximity := clampf((7.0 - closest) / 7.0, 0.0, 0.30)
	var wounds := clampf((38.0 - health) / 38.0, 0.0, 0.26)
	var strength := maxf(maxf(proximity, wounds), rift_damage_flash if in_rift else 0.0)
	danger_overlay.color = Color(0.50 if not in_rift else 0.34, 0.0, 0.08 if not in_rift else 0.42, strength)

func _update_hud() -> void:
	if not is_instance_valid(objective):
		return
	if seals_found < seals_required:
		objective.text = _tr("objective_seals") % [seals_found, seals_required]
		secondary_objective.text = _tr("secondary_counts") % [curses_cleansed, curse_required, altars_lit, altar_required]
	elif curses_cleansed < curse_required:
		objective.text = _tr("objective_curses") % [curses_cleansed, curse_required]
		secondary_objective.text = _tr("secondary_curses")
	elif altars_lit < altar_required:
		objective.text = _tr("objective_fires") % [altars_lit, altar_required]
		secondary_objective.text = _tr("secondary_fires")
	else:
		objective.text = _tr("objective_exit")
		secondary_objective.text = _tr("eclipse_time") % int(ceil(escape_remaining)) if escape_limit > 0.0 and not overtime else (_tr("eclipse_full") if overtime else _tr("exit_clear"))
	health_bar.value = health
	stamina_bar.value = player.stamina
	if seals_found == 0:
		pulse_label.text = _tr("pulse_none")
	elif pulse_cooldown > 0.0:
		pulse_label.text = _tr("pulse_wait") % pulse_cooldown
	elif player.stamina < PULSE_COST:
		pulse_label.text = _tr("pulse_low")
	else:
		pulse_label.text = _tr("pulse_ready")

func _refresh_objective_beacon() -> void:
	if not is_instance_valid(objective_beacon):
		return
	var target: Node3D
	if seals_found < seals_required:
		target = _nearest_valid_node(seal_nodes)
	elif curses_cleansed < curse_required:
		target = _nearest_uncleansed_curse(INF)
	elif altars_lit < altar_required:
		var available: Array[Node3D] = []
		for altar in altar_nodes:
			if is_instance_valid(altar) and not altar.get_meta("lit", false):
				available.append(altar)
		target = _nearest_valid_node(available)
	else:
		target = gate_area
	objective_beacon.visible = is_instance_valid(target)
	if is_instance_valid(target):
		objective_beacon.global_position = target.global_position + Vector3(0, 0.08, 0)

func _nearest_valid_node(nodes: Array) -> Node3D:
	var nearest: Node3D
	var distance := INF
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var candidate := node as Node3D
		var squared := player.global_position.distance_squared_to(candidate.global_position)
		if squared < distance:
			distance = squared
			nearest = candidate
	return nearest

func _nearest_uncleansed_curse(max_distance: float) -> Node3D:
	var nearest: Node3D
	var distance := max_distance * max_distance
	for curse in curse_nodes:
		if not is_instance_valid(curse) or curse.get_meta("cleansed", false):
			continue
		var squared := player.global_position.distance_squared_to(curse.global_position)
		if squared <= distance:
			distance = squared
			nearest = curse
	return nearest

func _on_interactable_entered(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		if not nearby_interactables.has(area):
			nearby_interactables.append(area)
		_refresh_interactable()

func _on_interactable_exited(body: Node3D, area: Area3D) -> void:
	if body.is_in_group("player"):
		nearby_interactables.erase(area)
		_refresh_interactable()

func _refresh_interactable() -> void:
	current_interactable = null
	if not is_instance_valid(player):
		return
	var closest_distance := INF
	for index in range(nearby_interactables.size() - 1, -1, -1):
		var area := nearby_interactables[index]
		if not is_instance_valid(area):
			nearby_interactables.remove_at(index)
			continue
		if area.get_meta("kind", "") == "curse" and area.get_meta("cleansed", false):
			continue
		var distance := player.global_position.distance_squared_to(area.global_position)
		if distance < closest_distance:
			closest_distance = distance
			current_interactable = area

func _update_visuals(delta: float) -> void:
	if is_instance_valid(atmosphere_motes):
		atmosphere_motes.rotation.y += delta * 0.012
		atmosphere_motes.position.y = sin(visual_time * 0.22) * 0.12
	if is_instance_valid(objective_beacon) and objective_beacon.visible:
		var beacon_ring := objective_beacon.get_node_or_null("Ring") as MeshInstance3D
		if beacon_ring != null:
			beacon_ring.rotation.z += delta * 1.1
			beacon_ring.scale = Vector3.ONE * (0.92 + sin(visual_time * 3.2) * 0.10)
	for altar in altar_nodes:
		if not is_instance_valid(altar):
			continue
		var ring := altar.get_node_or_null("Visual/Ring") as MeshInstance3D
		var light := altar.get_node_or_null("Visual/Light") as OmniLight3D
		if ring != null:
			ring.rotation.z += delta * (0.38 if altar.get_meta("lit", false) else 0.16)
		if light != null and altar.get_meta("lit", false):
			light.light_energy = 1.8 + sin(visual_time * 4.0 + altar.position.z) * 0.35
	for curse in curse_nodes:
		if not is_instance_valid(curse) or curse.get_meta("cleansed", false):
			continue
		var ring := curse.get_node_or_null("CurseRing") as MeshInstance3D
		if ring != null:
			ring.rotation.z -= delta * 0.72
			ring.scale = Vector3.ONE * (0.94 + sin(visual_time * 3.5 + curse.position.z) * 0.08)
	for rift in rift_nodes:
		if is_instance_valid(rift):
			var ring := rift.get_node_or_null("RiftRing") as MeshInstance3D
			if ring != null:
				ring.rotation.z += delta * 0.42
				ring.scale = Vector3.ONE * (0.95 + sin(visual_time * 2.6 + rift.position.x) * 0.08)
	if is_instance_valid(well_area) and not well_used:
		var well_ring := well_area.get_node_or_null("WellRing") as MeshInstance3D
		if well_ring != null:
			well_ring.rotation.z += delta * 0.44
	if is_instance_valid(exit_path) and exit_path.visible:
		for index in range(exit_path.get_child_count()):
			var ring := exit_path.get_child(index) as MeshInstance3D
			var scale_value := 0.88 + sin(visual_time * 3.4 - index * 0.7) * 0.14
			ring.scale = Vector3.ONE * scale_value

func _spawn_pulse_visual() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 0.96
	mesh.rings = 24
	mesh.ring_segments = 5
	mesh.material = _transparent_emissive_material(Color(1.0, 0.48, 0.035, 0.72), 2.0)
	var ring := MeshInstance3D.new()
	ring.position = player.global_position + Vector3(0, 0.12, 0)
	ring.scale = Vector3.ONE * 0.22
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 5.2, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)

func _toggle_pause() -> void:
	if suspended_by_platform:
		return
	if state == RunState.PLAYING:
		state = RunState.PAUSED
		get_tree().paused = true
		player.set_controls_enabled(false)
		pause_label.visible = true
		yandex.gameplay_stop()
	elif state == RunState.PAUSED:
		get_tree().paused = false
		state = RunState.PLAYING
		pause_label.visible = false
		player.set_controls_enabled(true)
		yandex.gameplay_start()

func _restart_level() -> void:
	get_tree().paused = false
	yandex.gameplay_stop()
	if state == RunState.WON:
		yandex.show_interstitial(_reload_after_interstitial)
	else:
		get_tree().reload_current_scene()

func _reload_after_interstitial(_was_shown: bool) -> void:
	get_tree().reload_current_scene()

func _open_next_level() -> void:
	var path := FLOW.next_challenge_path(level_number)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Next challenge scene is missing: " + path)
		return
	get_tree().paused = false
	yandex.gameplay_stop()
	yandex.show_interstitial(_change_scene_after_interstitial.bind(path))

func _return_to_menu() -> void:
	get_tree().paused = false
	yandex.gameplay_stop()
	if state == RunState.WON:
		yandex.show_interstitial(_change_scene_after_interstitial.bind(FLOW.MENU_SCENE))
	else:
		get_tree().change_scene_to_file(FLOW.MENU_SCENE)

func _change_scene_after_interstitial(_was_shown: bool, path: String) -> void:
	get_tree().change_scene_to_file(path)

func _on_platform_suspension_changed(suspended: bool) -> void:
	if suspended:
		if state == RunState.PLAYING and not get_tree().paused:
			suspended_by_platform = true
			get_tree().paused = true
			player.set_controls_enabled(false)
			yandex.gameplay_stop()
	elif suspended_by_platform:
		suspended_by_platform = false
		if state == RunState.PLAYING:
			get_tree().paused = false
			player.set_controls_enabled(true)
			yandex.gameplay_start()

func _apply_language(language: String) -> void:
	current_language = yandex.get_ui_language(language)
	if is_instance_valid(pause_label):
		pause_label.text = _tr("pause")
	if is_instance_valid(intro_title_label):
		intro_title_label.text = _level_title()
		intro_story_label.text = _intro_description()
		intro_controls_label.text = _tr("controls")
		intro_start_button.text = _tr("start")
		intro_menu_button.text = _tr("menu")
	if is_instance_valid(end_next_button):
		end_next_button.text = _tr("next")
	if is_instance_valid(end_restart_button):
		end_restart_button.text = _tr("restart")
	if is_instance_valid(end_menu_button):
		end_menu_button.text = _tr("menu")
	if is_instance_valid(death_reward_button):
		death_reward_button.text = _tr("reward_life") if not death_reward_button.disabled else _tr("reward_yandex_only")
	if state == RunState.DOWNED and is_instance_valid(end_screen):
		end_title.text = _tr("death_title")
		end_details.text = _tr("death_offer")
	if completed and is_instance_valid(end_screen):
		objective.text = _tr("level_complete_objective") % level_number
		end_title.text = _tr("level_complete_title")
		end_details.text = _tr("result") % [_format_time(elapsed), hits_taken, pulses_used, deaths, _result_grade()]
	_update_hud()
	_update_prompt()

func _tr(key: String) -> String:
	return CHALLENGE_TEXT.get_text(key, current_language)

func _show_hint(message: String, duration: float) -> void:
	hint_serial += 1
	var serial := hint_serial
	hint.text = message
	await get_tree().create_timer(duration, true).timeout
	if serial == hint_serial:
		hint.text = ""

func _make_label(pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _make_bar(pos: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(230, 16)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.06, 0.02, 0.02, 0.86)
	back.border_width_left = 1
	back.border_width_top = 1
	back.border_width_right = 1
	back.border_width_bottom = 1
	back.border_color = Color(0.72, 0.38, 0.18, 0.72)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar

func _dialog_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.032, 0.024, 0.019, 0.97)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.77, 0.61, 0.32, 0.84)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _style_dialog_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("5e160f") if accent else Color("13110fe8")
	normal.border_color = Color("d6ad62") if accent else Color("8f7549c8")
	normal.set_border_width_all(2 if accent else 1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := normal.duplicate()
	hover.bg_color = Color("84261a") if accent else Color("2b2119f2")
	hover.border_color = Color("ffe4a0")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("3c0e0a") if accent else Color("0b0908f5")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("fff0c8"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("e5c783"))
	button.add_theme_color_override("font_outline_color", Color("100806dd"))
	button.add_theme_constant_override("outline_size", 2)

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _transparent_emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _emissive_material(color, energy)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _add_visual(scene: PackedScene, position: Vector3, rotation_y := 0.0, model_scale := Vector3.ONE) -> Node3D:
	var instance := scene.instantiate()
	instance.position = position
	instance.rotation.y = rotation_y
	instance.scale = model_scale
	add_child(instance)
	return instance

func _add_box_collider(position: Vector3, size: Vector3, rotation_y := 0.0) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	body.rotation.y = rotation_y
	add_child(body)

func _add_cylinder_collider(position: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child(body)

## Модель гор — только вид, коллайдера у неё нет. Без стены игрок уходил в
## склон, а цели вставали внутрь горы. Проход на север к воротам оставляем.
func _add_boundaries() -> void:
	MOUNTAIN_RING.build_wall(self)
	_add_box_collider(Vector3(-30, 2, 0), Vector3(1, 4, 60))
	_add_box_collider(Vector3(30, 2, 0), Vector3(1, 4, 60))
	_add_box_collider(Vector3(0, 2, 30), Vector3(60, 4, 1))
	_add_box_collider(Vector3(0, 2, -31), Vector3(60, 4, 1))

func _curse_count_for_level() -> int:
	return clampi(int(float(level_number - 2) / 3.0), 0, 6)

func _escape_time_for_level() -> float:
	if level_number < 14:
		return 0.0
	return maxf(34.0, 56.0 - float(level_number - 14) * 3.0)

func _healing_rate() -> float:
	return maxf(1.4, 4.4 - float(level_number - 2) * 0.14)

func _result_grade() -> String:
	var penalty := hits_taken * 2 + deaths * 8 + int(elapsed / 60.0)
	if penalty <= 5:
		return "S"
	if penalty <= 13:
		return "A"
	if penalty <= 24:
		return "B"
	return "C"

func _format_time(value: float) -> String:
	return "%02d:%02d" % [int(value / 60.0), int(value) % 60]

func _intro_description() -> String:
	var mechanics := _tr("intro_counts") % [seals_required, altar_required, enemy_count]
	if curse_required > 0:
		mechanics += _tr("intro_curses") % curse_required
	if level_number >= 5:
		mechanics += _tr("intro_rifts")
	if escape_limit > 0.0:
		mechanics += _tr("intro_eclipse")
	var kind_names: Array[String] = []
	for kind in _enemy_kinds_present():
		kind_names.append(_tr("enemy_%s" % kind))
	if kind_names.size() > 1:
		mechanics += _tr("intro_enemy_kinds") % ", ".join(kind_names)
	return mechanics + _tr("intro_well")

func _level_title() -> String:
	return _tr("level_title") % [level_number, FLOW.challenge_title(level_number, current_language)]
