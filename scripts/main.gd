extends Node3D

enum Phase { INTRO, PLAYING, PAUSED, WON, LOST }

const GUARDIAN_SCENE := preload("res://scenes/guardian.tscn")
const SEAL_SCENE := preload("res://scenes/seal.tscn")
const MOUNTAIN_RING := preload("res://scripts/mountain_ring.gd")
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
const STRAW_DOLL := preload("res://models/straw_doll.glb")
const GATE := preload("res://models/ritual_gate.glb")
const GATE_DOOR := preload("res://models/ritual_gate_door.glb")
const TOTEM := preload("res://models/sun_totem.glb")
const FLOW := preload("res://scripts/game_flow.gd")
const RITUAL_SUN := preload("res://scripts/ritual_sun.gd")

@onready var player = $Player
@onready var yandex: Node = get_node("/root/YandexService")
@onready var audio = $ProceduralAudio
@onready var objective: Label = $UI/Objective
@onready var shade_label: Label = $UI/Shade
@onready var hint: Label = $UI/Hint
@onready var danger: ColorRect = $UI/Danger
@onready var intro: Control = $UI/Intro
@onready var end_screen: Control = $UI/End
@onready var end_title: Label = $UI/End/Center/Content/Title
@onready var end_text: Label = $UI/End/Center/Content/Text
@onready var pause_label: Label = $UI/Pause
@onready var touch_controls: Control = $UI/TouchControls
@onready var health_panel: Control = $UI/Health
@onready var health_bar: ProgressBar = $UI/Health/Bar
@onready var health_title: Label = $UI/Health/Title
@onready var health_value: Label = $UI/Health/Value
@onready var stamina_bar: ProgressBar = $UI/Health/StaminaBar
@onready var stamina_title: Label = $UI/Health/StaminaTitle
@onready var stamina_value: Label = $UI/Health/StaminaValue
@onready var pulse_label: Label = $UI/Pulse

var phase := Phase.INTRO
var seals_found := 0
var guardian: CharacterBody3D
var hint_serial := 0
var current_language := "ru"
var suspended_by_platform := false
var health := 100.0
var recovery_cooldown := 0.0
var damage_flash := 0.0
var wound_hint_shown := false
var gate_ward_rings: Array[MeshInstance3D] = []
var gate_blocker_collision: CollisionShape3D
var gate_doors: Array[Node3D] = []
var gate_doors_open := false
var cloud_layer: MultiMeshInstance3D
var sun_pulse_cooldown := 0.0
var totem_aura: Node3D
var totem_light: OmniLight3D
var totem_used := false
var player_near_totem := false
var seal_nodes: Array[Area3D] = []
var seal_beacon: Node3D
var exit_path: MultiMeshInstance3D
var exit_path_time := 0.0
var lighting_stage := 0
var lighting_tween: Tween
var charge_hint_shown := false
var escape_time_remaining := 0.0
var sunset_triggered := false
var watching_eyes: MultiMeshInstance3D
var ritual_sun_visual: Node3D
var next_challenge_button: Button
var death_reward_button: Button
var run_time := 0.0
var hits_taken := 0
var pulses_used := 0
var charges_dodged := 0

const MAX_HEALTH := 100.0
const SUN_RECOVERY_PER_SECOND := 5.0
const ESCAPE_WINDOW := 28.0

const TEXT := {
	"ru": {
		"death_title": "У ВАС ЗАБРАЛИ ЖИЗНЬ",
		"death_offer": "Белояр оставил вас у праздничной тропы. Посмотрите рекламу Яндекса, чтобы вернуться с полной жизнью и сохранить найденные печати.",
		"reward_life": "СМОТРЕТЬ РЕКЛАМУ — ВЕРНУТЬ ЖИЗНЬ",
		"reward_yandex_only": "ВОЗРОЖДЕНИЕ ДОСТУПНО В ЯНДЕКС ИГРАХ",
		"reward_loading": "ОТКРЫВАЕМ РЕКЛАМУ…",
		"reward_wait": "Просмотрите рекламу до конца — жизнь вернётся только после подтверждения Яндекса.",
		"reward_not_completed": "Просмотр не завершён. Жизнь не возвращена — можно попробовать ещё раз или начать заново.",
		"reward_revived": "Солнце вернуло вам жизнь. Найденные печати сохранены.",
		"title": "БЕЛЫЙ ПОЛДЕНЬ",
		"story": "Деревня Белояр встретила вас тишиной.\nНайдите три солнечные печати и уходите через северные ворота.\n\nСтраж медлителен на свету. В тени домов он почти неотвратим.",
		"controls": "WASD — идти  •  Shift — бежать  •  Мышь/свайп — обзор  •  E/Пробел — импульс  •  Esc/кнопка паузы",
		"start": "ВОЙТИ В ДЕРЕВНЮ",
		"restart": "НАЧАТЬ СНОВА",
		"next_challenge": "ПЕРВОЕ ИСПЫТАНИЕ",
		"menu": "К ВЫБОРУ УРОВНЕЙ",
		"pause": "ПАУЗА\nEsc или кнопка паузы — продолжить",
		"seals": "Печати: %d / 3",
		"health": "ЖИЗНЬ",
		"stamina": "СИЛЫ",
		"shade": "В ТЕНИ — СТРАЖ БЫСТРЕЕ, РАНЫ НЕ ЗАЖИВАЮТ",
		"intro_hint": "Три печати держат ворота закрытыми. E / Пробел — солнце укажет ближайшую.",
		"guardian_hint": "Страж проснулся. Держитесь солнечной тропы.",
		"guardian_charge": "Янтарный след — Страж готовит рывок. Уйдите в сторону!",
		"last_seal": "Последний запор снят. Дорога через перевал открыта!",
		"gate_open": "Ворота открыты — бегите на север!",
		"escape_timer": "ВОРОТА ОТКРЫТЫ • ЗАКАТ: %02d",
		"sunset_objective": "СОЛНЦЕ УШЛО • БЕГИТЕ К ВОРОТАМ!",
		"sunset_hint": "Солнце ушло. Раны больше не заживают, Страж не отступит!",
		"gate_locked": "На воротах три пустых солнечных гнезда.",
		"respawn": "Солнце вернуло вас к дороге.",
		"wounded": "Страж ранит вас. Выйдите на свет, чтобы восстановиться.",
		"seal_heal": "Печать вспыхнула: раны затянулись, Страж оглушён.",
		"pulse": "Солнечный импульс отбросил Стража.",
		"pulse_reveal": "Импульс указал ближайшую печать — %d м.",
		"pulse_locked": "Отбросить Стража можно только силой пробуждённой печати.",
		"pulse_far": "Страж слишком далеко для импульса.",
		"pulse_tired": "Не хватает сил для солнечного импульса.",
		"pulse_cooldown": "Солнечный импульс ещё не восстановился.",
		"pulse_ready": "ИМПУЛЬС: ГОТОВ",
		"pulse_wait": "ИМПУЛЬС: %.1f С",
		"pulse_no_stamina": "ИМПУЛЬС: НЕТ СИЛ",
		"pulse_no_seal": "ИМПУЛЬС: НЕТ ПЕЧАТИ",
		"totem_prompt": "E / Пробел — коснуться солнечного столба: восстановиться, но разгневать Стража.",
		"totem_used": "Солнечный столб отдал вам силу. Страж пришёл в ярость!",
		"result_stats": "ВРЕМЯ  %s   •   УДАРЫ  %d\nИМПУЛЬСЫ  %d   •   УКЛОНЕНИЯ  %d\nОЦЕНКА  %s",
		"win_title": "ВЫ УШЛИ ДО ЗАКАТА",
		"win_title_late": "ВЫ УШЛИ ПОСЛЕ ЗАКАТА",
		"lose_title": "ПРАЗДНИК НАЧАЛСЯ",
		"win_text": "За воротами солнце наконец стало садиться.",
		"win_text_late": "Вы выбрались в сумерках, когда Белояр уже проснулся.",
		"lose_text": "В Белояре всегда не хватало одного гостя."
	},
	"en": {
		"death_title": "YOUR LIFE WAS TAKEN",
		"death_offer": "Beloyar left you beside the festival path. Watch a Yandex ad to return with full health and keep the seals you found.",
		"reward_life": "WATCH AD — RESTORE LIFE",
		"reward_yandex_only": "REVIVAL IS AVAILABLE ON YANDEX GAMES",
		"reward_loading": "OPENING AD…",
		"reward_wait": "Watch the ad to the end. Your life returns only after Yandex confirms the reward.",
		"reward_not_completed": "The ad was not completed. No life was granted — try again or restart.",
		"reward_revived": "The sun restored your life. Your collected seals remain.",
		"title": "WHITE NOON",
		"story": "The village of Beloyar welcomed you with silence.\nFind three sun seals and escape through the northern gate.\n\nThe Guardian is slow in sunlight. In the houses' shadow, it is almost inevitable.",
		"controls": "WASD — move  •  Shift — run  •  Mouse/swipe — look  •  E/Space — pulse  •  Esc/pause button",
		"start": "ENTER THE VILLAGE",
		"restart": "START AGAIN",
		"next_challenge": "FIRST CHALLENGE",
		"menu": "LEVEL SELECT",
		"pause": "PAUSED\nEsc or pause button — continue",
		"seals": "Seals: %d / 3",
		"health": "HEALTH",
		"stamina": "STAMINA",
		"shade": "IN SHADOW — THE GUARDIAN IS FASTER, WOUNDS DO NOT HEAL",
		"intro_hint": "Three seals lock the gate. E / Space — the sun points to the nearest one.",
		"guardian_hint": "The Guardian is awake. Stay on the sunlit path.",
		"guardian_charge": "Amber trail — the Guardian is charging. Step aside!",
		"last_seal": "The last ward is gone. The road through the pass is open!",
		"gate_open": "The gate is open — run north!",
		"escape_timer": "GATE OPEN • SUNSET: %02d",
		"sunset_objective": "THE SUN IS GONE • RUN TO THE GATE!",
		"sunset_hint": "The sun is gone. Wounds no longer heal and the Guardian will not relent!",
		"gate_locked": "The gate has three empty sun sockets.",
		"respawn": "The sun returned you to the road.",
		"wounded": "The Guardian wounded you. Reach sunlight to recover.",
		"seal_heal": "The seal flared: wounds mended and the Guardian was stunned.",
		"pulse": "The sun pulse drove the Guardian back.",
		"pulse_reveal": "The pulse revealed the nearest seal — %d m.",
		"pulse_locked": "Only an awakened seal can repel the Guardian.",
		"pulse_far": "The Guardian is too far away for a pulse.",
		"pulse_tired": "Not enough stamina for a sun pulse.",
		"pulse_cooldown": "The sun pulse has not recovered yet.",
		"pulse_ready": "PULSE: READY",
		"pulse_wait": "PULSE: %.1f S",
		"pulse_no_stamina": "PULSE: LOW STAMINA",
		"pulse_no_seal": "PULSE: NO SEAL",
		"totem_prompt": "E / Space — touch the sun pillar: recover, but enrage the Guardian.",
		"totem_used": "The sun pillar gave you its strength. The Guardian is enraged!",
		"result_stats": "TIME  %s   •   HITS  %d\nPULSES  %d   •   DODGES  %d\nGRADE  %s",
		"win_title": "YOU LEFT BEFORE SUNSET",
		"win_title_late": "YOU LEFT AFTER SUNSET",
		"lose_title": "THE FESTIVAL HAS BEGUN",
		"win_text": "Beyond the gate, the sun finally began to set.",
		"win_text_late": "You escaped at twilight, as Beloyar finally awoke.",
		"lose_text": "Beloyar was always missing one guest."
	}
}

func _ready() -> void:
	_prepare_environment()
	_apply_lighting_stage(0, true)
	_build_world()
	$UI/Intro/Center/Panel/Margin/Content/Start.pressed.connect(_start_game)
	$UI/Intro/Center/Panel/Margin/Content/Menu.pressed.connect(_return_to_menu)
	_build_next_challenge_button()
	_build_death_reward_button()
	$UI/End/Center/Content/Restart.pressed.connect(_restart)
	$UI/End/Center/Content/Menu.pressed.connect(_return_to_menu)
	_style_dialog_button($UI/Intro/Center/Panel/Margin/Content/Start, true)
	_style_dialog_button($UI/Intro/Center/Panel/Margin/Content/Menu, false)
	_style_dialog_button($UI/End/Center/Content/Restart, true)
	_style_dialog_button($UI/End/Center/Content/Menu, false)
	touch_controls.move_changed.connect(player.set_touch_move)
	touch_controls.look_changed.connect(player.add_touch_look)
	touch_controls.action_pressed.connect(_touch_action)
	touch_controls.pause_pressed.connect(_toggle_pause)
	player.stamina_changed.connect(_on_stamina_changed)
	player.footstep.connect(audio.play_step)
	yandex.language_detected.connect(_apply_language)
	yandex.platform_suspension_changed.connect(_on_platform_suspension_changed)
	player.set_controls_enabled(false)
	# Сам затемняющий слой кликов не ловит, поэтому клик мимо панели закрывает
	# вступление, а клик по панели с текстом и кнопками — нет.
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.visible = false
	health_panel.visible = false
	pulse_label.visible = false
	$UI/Crosshair.visible = false
	_update_health_ui()
	_on_stamina_changed(player.stamina, player.max_stamina)
	_apply_language(String(yandex.detected_language))
	yandex.mark_game_ready()

func _prepare_environment() -> void:
	var environment := $WorldEnvironment.environment.duplicate(true) as Environment
	$WorldEnvironment.environment = environment
	if environment.sky != null:
		environment.sky = environment.sky.duplicate(true) as Sky
		if environment.sky.sky_material != null:
			environment.sky.sky_material = environment.sky.sky_material.duplicate(true) as Material

func _style_dialog_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("5e160f") if accent else Color("13110fe8")
	normal.border_color = Color("d6ad62") if accent else Color("8f7549c8")
	normal.set_border_width_all(2 if accent else 1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 20.0
	normal.content_margin_right = 20.0
	normal.content_margin_top = 11.0
	normal.content_margin_bottom = 11.0
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

func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.INTRO:
		_skip_intro_on_any_input(event)
		return
	if event.is_action_pressed("pause") and phase in [Phase.PLAYING, Phase.PAUSED]:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and phase == Phase.PLAYING:
		_try_sun_pulse()
		get_viewport().set_input_as_handled()

## Игрок уже нажал «начать историю» в меню — второй экран с тем же логотипом
## и текстом работает как лишний барьер. Кнопка осталась, но вступление теперь
## закрывается любым действием: клавишей, кликом по затемнению или касанием.
func _skip_intro_on_any_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		return
	# Сенсорная кнопка действия шлёт InputEventAction, а не касание экрана,
	# поэтому её проверяем отдельно — иначе на телефоне она бы не работала.
	var skip := event.is_action_pressed("interact")
	if event is InputEventKey:
		skip = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		skip = event.pressed
	elif event is InputEventScreenTouch:
		skip = event.pressed
	if skip and phase == Phase.INTRO:
		_start_game()
		get_viewport().set_input_as_handled()

func _try_sun_pulse() -> void:
	if not totem_used and player.global_position.distance_to(Vector3(0, 0, -2)) < 2.8:
		_use_totem()
		return
	if sun_pulse_cooldown > 0.0:
		_show_hint(_text("pulse_cooldown"), 1.5)
		return
	var guardian_close: bool = guardian.global_position.distance_to(player.global_position) <= 7.5
	var nearest_seal := _nearest_untaken_seal()
	# До первой печати солнце умеет только указывать дорогу. Раньше импульс
	# был заблокирован целиком, и первую печать приходилось искать вслепую —
	# ровно на этом игроки и уходили в первую минуту.
	if seals_found <= 0 and guardian_close:
		_show_hint(_text("pulse_locked"), 1.8)
		return
	if not guardian_close and nearest_seal == null:
		_show_hint(_text("gate_open"), 1.8)
		return
	if not player.spend_stamina(34.0):
		_show_hint(_text("pulse_tired"), 1.7)
		return
	pulses_used += 1
	sun_pulse_cooldown = 7.0
	_spawn_sun_pulse_visual()
	audio.play_event("pulse")
	if guardian_close:
		guardian.stun(1.25 + seals_found * 0.18)
		guardian.repel_from(player.global_position, 5.2)
		_show_hint(_text("pulse"), 1.6)
	else:
		_spawn_seal_beacon(nearest_seal)
		var distance := roundi(player.global_position.distance_to(nearest_seal.global_position))
		_show_hint(_text("pulse_reveal") % distance, 2.6)

func _nearest_untaken_seal() -> Area3D:
	var nearest: Area3D
	var nearest_distance := INF
	for seal in seal_nodes:
		if not is_instance_valid(seal) or seal.taken:
			continue
		var distance: float = player.global_position.distance_squared_to(seal.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = seal
	return nearest

func _spawn_seal_beacon(seal: Area3D, duration := 3.35) -> void:
	if is_instance_valid(seal_beacon):
		seal_beacon.queue_free()
	seal_beacon = Node3D.new()
	seal_beacon.name = "SealBeacon"
	add_child(seal_beacon)
	seal_beacon.global_position = seal.global_position + Vector3(0, -0.75, 0)
	seal_beacon.scale = Vector3(0.16, 0.16, 0.16)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.62, 0.08, 0.56)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.015)
	material.emission_energy_multiplier = 2.2
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.06
	beam_mesh.bottom_radius = 0.2
	beam_mesh.height = 8.0
	beam_mesh.radial_segments = 8
	beam.mesh = beam_mesh
	beam.position.y = 4.0
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seal_beacon.add_child(beam)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.82
	ring_mesh.outer_radius = 1.02
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 6
	ring.mesh = ring_mesh
	ring.rotation.x = PI * 0.5
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seal_beacon.add_child(ring)
	create_tween().tween_property(seal_beacon, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	for part in [beam, ring]:
		create_tween().tween_property(part, "transparency", 1.0, 2.5).set_delay(maxf(0.8, duration - 2.55))
	var life := create_tween()
	life.tween_interval(duration)
	life.tween_callback(seal_beacon.queue_free)

func _use_totem() -> void:
	if totem_used:
		return
	totem_used = true
	_change_health(48.0)
	player.restore_stamina(62.0)
	sun_pulse_cooldown = 0.0
	guardian.awaken(maxi(1, seals_found))
	guardian.enrage(12.0)
	_spawn_sun_pulse_visual()
	audio.play_event("totem")
	if is_instance_valid(totem_light):
		totem_light.light_energy = 3.2
		var light_tween := create_tween()
		light_tween.tween_property(totem_light, "light_energy", 0.12, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(totem_aura):
		var aura_tween := create_tween().set_parallel(true)
		for child in totem_aura.get_children():
			if child is MeshInstance3D:
				aura_tween.tween_property(child, "scale", Vector3.ONE * 2.8, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_show_hint(_text("totem_used"), 3.0)

func _spawn_sun_pulse_visual() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.55, 0.06, 0.72)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.16, 0.01)
	material.emission_energy_multiplier = 1.8
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 0.94
	mesh.rings = 24
	mesh.ring_segments = 5
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "SunPulse"
	ring.position = player.global_position + Vector3(0, 0.12, 0)
	ring.scale = Vector3.ONE * 0.25
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.mesh = mesh
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * 4.8, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)

func _build_world() -> void:
	_add_visual(GROUND, Vector3.ZERO)
	_add_visual(MOUNTAINS, Vector3.ZERO)
	_add_ritual_sun()
	_add_box_collider(Vector3(0, -0.2, 0), Vector3(60, 0.4, 60))
	_add_grass_details()
	_add_clouds()
	_add_road_details()
	_add_festival_bunting()

	var houses = [
		[HOUSE_GREEN, Vector3(-10, 0, 15), -0.24, Vector3(5.5, 3.2, 4.5)],
		[HOUSE_BLUE, Vector3(10, 0, 13), 0.22, Vector3(5.0, 3.7, 4.3)],
		[HOUSE_RED, Vector3(-12, 0, 4), -0.10, Vector3(7.8, 3.0, 4.1)],
		[HOUSE_OCHRE, Vector3(12, 0, 2), 0.14, Vector3(5.0, 3.3, 6.3)],
		[HOUSE_OCHRE, Vector3(-12, 0, -8), 0.08, Vector3(5.0, 3.3, 6.3)],
		[HOUSE_RED, Vector3(12, 0, -11), -0.12, Vector3(7.8, 3.0, 4.1)],
		[HOUSE_BLUE, Vector3(-9, 0, -20), 0.19, Vector3(5.0, 3.7, 4.3)],
		[HOUSE_GREEN, Vector3(9, 0, -21), -0.17, Vector3(5.5, 3.2, 4.5)],
	]
	for item in houses:
		_add_visual(item[0], item[1], item[2])
		var collider_size: Vector3 = item[3]
		_add_box_collider(item[1] + Vector3(0, collider_size.y / 2.0, 0), collider_size, item[2])
	_add_watching_eyes(houses)
	_add_ritual_effigies()

	_add_visual(TOTEM, Vector3(0, 0, -2))
	_add_totem_aura()
	_add_cylinder_collider(Vector3(0, 2.2, -2), 0.55, 4.4)
	_add_visual(GATE, Vector3(0, 0, -27))
	_add_gate_doors()
	_add_gate_ward()
	_add_exit_path()
	_add_exit_area()

	var tree_positions := [
		Vector3(-24,0,24), Vector3(-17,0,27), Vector3(18,0,27), Vector3(24,0,22),
		Vector3(-25,0,13), Vector3(24,0,11), Vector3(-25,0,1), Vector3(25,0,-2),
		Vector3(-24,0,-12), Vector3(24,0,-15), Vector3(-20,0,-25), Vector3(20,0,-25),
		Vector3(-17,0,10), Vector3(18,0,17), Vector3(-18,0,-3), Vector3(18,0,-5),
	]
	for index in range(tree_positions.size()):
		var pos: Vector3 = tree_positions[index]
		var tree_scale := 0.82 + float(index % 5) * 0.075
		_add_visual(TREE, pos, pos.x * 0.07, Vector3.ONE * tree_scale)
		_add_cylinder_collider(pos + Vector3(0, 1.6, 0), 0.35, 3.2)

	var fences = [
		[Vector3(-16,0,24),0.05], [Vector3(16,0,24),-0.05], [Vector3(-18,0,8),1.50],
		[Vector3(18,0,8),1.63], [Vector3(-18,0,-9),1.58], [Vector3(18,0,-8),1.56],
		[Vector3(-15,0,-25),0.08], [Vector3(15,0,-25),-0.08],
	]
	for data in fences:
		_add_visual(FENCE, data[0], data[1])
	var stones = [Vector3(-19,0,17), Vector3(18,0,-16), Vector3(-17,0,-15), Vector3(17,0,20), Vector3(-23,0,-25), Vector3(23,0,3)]
	for index in range(stones.size()):
		var pos: Vector3 = stones[index]
		var stone_scale := Vector3.ONE * (0.78 + float(index % 3) * 0.16)
		_add_visual(STONE, pos, pos.z * 0.13, stone_scale)
	var flower_positions = [
		Vector3(-6,0,22),Vector3(5,0,20),Vector3(-6,0,12),Vector3(6,0,9),
		Vector3(-5,0,2),Vector3(5,0,-2),Vector3(-6,0,-11),Vector3(6,0,-15),
		Vector3(-5,0,-23),Vector3(3,0,-24),Vector3(-15,0,20),Vector3(15,0,-19),
	]
	for index in range(flower_positions.size()):
		var pos: Vector3 = flower_positions[index]
		_add_visual(FLOWERS, pos, float(index) * 0.73, Vector3.ONE * (0.85 + float(index % 4) * 0.08))

	_add_boundaries()
	_spawn_seals()
	guardian = GUARDIAN_SCENE.instantiate()
	guardian.position = Vector3(0, 0.1, 5)
	add_child(guardian)
	var patrol: Array[Vector3] = [Vector3(-6,0,8), Vector3(7,0,-4), Vector3(-5,0,-15), Vector3(5,0,16)]
	guardian.configure(player, patrol)
	guardian.hit.connect(_on_guardian_hit)
	guardian.charge_started.connect(_on_guardian_charge_started)
	guardian.charge_evaded.connect(_on_guardian_charge_evaded)
	guardian.attack_started.connect(_on_guardian_attack_started)

func _add_gate_ward() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.34, 0.035, 0.82)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.075, 0.005)
	material.emission_energy_multiplier = 2.0
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.39
	mesh.outer_radius = 0.49
	mesh.rings = 16
	mesh.ring_segments = 5
	mesh.material = material
	var ward := Node3D.new()
	ward.name = "SunWard"
	ward.position = Vector3(0, 0, -26.72)
	add_child(ward)
	for index in range(3):
		var ring := MeshInstance3D.new()
		ring.name = "Ward%d" % (index + 1)
		ring.position = Vector3(-1.22 + index * 1.22, 2.22, 0)
		ring.rotation.x = PI * 0.5
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.mesh = mesh
		ward.add_child(ring)
		gate_ward_rings.append(ring)
	var blocker := StaticBody3D.new()
	blocker.name = "GateWardBlocker"
	gate_blocker_collision = CollisionShape3D.new()
	var blocker_shape := BoxShape3D.new()
	blocker_shape.size = Vector3(4.1, 3.2, 0.55)
	gate_blocker_collision.shape = blocker_shape
	blocker.add_child(gate_blocker_collision)
	blocker.position = Vector3(0, 1.6, -27.0)
	add_child(blocker)

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
	if gate_doors_open or gate_doors.size() != 2:
		return
	gate_doors_open = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(gate_doors[0], "rotation:y", deg_to_rad(-102.0), 1.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(gate_doors[1], "rotation:y", deg_to_rad(102.0), 1.25).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)

func _release_gate_ward(index: int) -> void:
	if index < 0 or index >= gate_ward_rings.size():
		return
	var ring := gate_ward_rings[index]
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ZERO, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(ring, "position:y", ring.position.y + 0.55, 0.48)
	if index == gate_ward_rings.size() - 1:
		gate_blocker_collision.set_deferred("disabled", true)
		_open_gate_doors()

func _add_exit_path() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.48, 0.025, 0.68)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.14, 0.008)
	material.emission_energy_multiplier = 2.0
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.54
	ring_mesh.outer_radius = 0.66
	ring_mesh.rings = 14
	ring_mesh.ring_segments = 5
	ring_mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = ring_mesh
	multimesh.instance_count = 4
	for index in range(multimesh.instance_count):
		multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(0, 0.12, -29.2 - index * 2.8)))
	exit_path = MultiMeshInstance3D.new()
	exit_path.name = "ExitSunPath"
	exit_path.multimesh = multimesh
	exit_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	exit_path.visible = false
	add_child(exit_path)

func _reveal_exit_path() -> void:
	if is_instance_valid(exit_path):
		exit_path.visible = true
		exit_path_time = 0.0

func _lighting_target(stage: int) -> Dictionary:
	match stage:
		1:
			return {
				"rotation": Vector3(-35, 221, 0), "sun_color": Color(1.0, 0.84, 0.52), "sun_energy": 1.24,
				"ambient_color": Color(0.47, 0.57, 0.70), "ambient_energy": 0.45,
				"sky_top": Color(0.025, 0.11, 0.39), "sky_horizon": Color(0.34, 0.46, 0.60),
				"ground_horizon": Color(0.27, 0.34, 0.19), "fog_density": 0.0022
			}
		2:
			return {
				"rotation": Vector3(-30, 214, 0), "sun_color": Color(1.0, 0.69, 0.34), "sun_energy": 1.15,
				"ambient_color": Color(0.40, 0.43, 0.58), "ambient_energy": 0.43,
				"sky_top": Color(0.04, 0.07, 0.28), "sky_horizon": Color(0.53, 0.34, 0.40),
				"ground_horizon": Color(0.33, 0.27, 0.18), "fog_density": 0.0037
			}
		3:
			return {
				"rotation": Vector3(-24, 206, 0), "sun_color": Color(1.0, 0.61, 0.32), "sun_energy": 1.03,
				"ambient_color": Color(0.34, 0.39, 0.61), "ambient_energy": 0.39,
				"sky_top": Color(0.025, 0.028, 0.14), "sky_horizon": Color(0.62, 0.20, 0.28),
				"ground_horizon": Color(0.20, 0.20, 0.29), "fog_density": 0.0045
			}
		4:
			return {
				"rotation": Vector3(-14, 197, 0), "sun_color": Color(1.0, 0.42, 0.27), "sun_energy": 0.65,
				"ambient_color": Color(0.35, 0.42, 0.70), "ambient_energy": 0.54,
				"sky_top": Color(0.012, 0.018, 0.075), "sky_horizon": Color(0.28, 0.075, 0.20),
				"ground_horizon": Color(0.11, 0.14, 0.24), "fog_density": 0.0062
			}
	return {
		"rotation": Vector3(-40, 226, 0), "sun_color": Color(1.0, 0.91, 0.68), "sun_energy": 1.26,
		"ambient_color": Color(0.48, 0.61, 0.74), "ambient_energy": 0.47,
		"sky_top": Color(0.018, 0.12, 0.46), "sky_horizon": Color(0.18, 0.43, 0.63),
		"ground_horizon": Color(0.24, 0.35, 0.18), "fog_density": 0.0009
	}

func _apply_lighting_stage(stage: int, immediate := false) -> void:
	lighting_stage = clampi(stage, 0, 4)
	var target: Dictionary = _lighting_target(lighting_stage)
	var environment: Environment = $WorldEnvironment.environment
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material
	environment.fog_enabled = true
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if lighting_stage == 4 else Environment.AMBIENT_SOURCE_SKY
	if is_instance_valid(lighting_tween):
		lighting_tween.kill()
	if immediate:
		$Sun.rotation_degrees = target.rotation
		$Sun.light_color = target.sun_color
		$Sun.light_energy = target.sun_energy
		environment.ambient_light_color = target.ambient_color
		environment.ambient_light_energy = target.ambient_energy
		environment.fog_density = target.fog_density
		sky_material.sky_top_color = target.sky_top
		sky_material.sky_horizon_color = target.sky_horizon
		sky_material.ground_horizon_color = target.ground_horizon
		_update_watching_eyes()
		_update_ritual_sun()
		return
	lighting_tween = create_tween().set_parallel(true)
	lighting_tween.tween_property($Sun, "rotation_degrees", target.rotation, 2.8).set_trans(Tween.TRANS_SINE)
	lighting_tween.tween_property($Sun, "light_color", target.sun_color, 2.4)
	lighting_tween.tween_property($Sun, "light_energy", target.sun_energy, 2.4)
	lighting_tween.tween_property(environment, "ambient_light_color", target.ambient_color, 2.4)
	lighting_tween.tween_property(environment, "ambient_light_energy", target.ambient_energy, 2.4)
	lighting_tween.tween_property(environment, "fog_density", target.fog_density, 2.8)
	lighting_tween.tween_property(sky_material, "sky_top_color", target.sky_top, 2.8)
	lighting_tween.tween_property(sky_material, "sky_horizon_color", target.sky_horizon, 2.8)
	lighting_tween.tween_property(sky_material, "ground_horizon_color", target.ground_horizon, 2.8)
	_update_watching_eyes()
	_update_ritual_sun()

func _add_ritual_sun() -> void:
	# Солнце стоит ровно там, откуда светит DirectionalLight: один
	# билборд-диск с процедурной короной вместо прежней гранёной сферы.
	ritual_sun_visual = RITUAL_SUN.new()
	ritual_sun_visual.name = "RitualSun"
	add_child(ritual_sun_visual)
	ritual_sun_visual.setup($Sun)
	_update_ritual_sun()

func _update_ritual_sun() -> void:
	if not is_instance_valid(ritual_sun_visual):
		return
	var core_colors := [
		Color(1.0, 0.96, 0.86), Color(1.0, 0.90, 0.70), Color(1.0, 0.78, 0.46),
		Color(1.0, 0.62, 0.30), Color(0.98, 0.44, 0.26),
	]
	var ring_colors := [
		Color(1.0, 0.90, 0.66), Color(1.0, 0.80, 0.46), Color(1.0, 0.64, 0.30),
		Color(1.0, 0.46, 0.22), Color(0.98, 0.34, 0.34),
	]
	var corona_colors := [
		Color(1.0, 0.72, 0.34), Color(1.0, 0.58, 0.20), Color(1.0, 0.40, 0.12),
		Color(0.92, 0.24, 0.10), Color(0.72, 0.13, 0.24),
	]
	var eclipse_by_stage := [0.0, 0.14, 0.34, 0.58, 0.86]
	var stage := clampi(lighting_stage, 0, 4)
	ritual_sun_visual.set_look(
		core_colors[stage], ring_colors[stage], corona_colors[stage],
		eclipse_by_stage[stage], 10 + stage, float(stage) * 0.9
	)
	ritual_sun_visual.set_breath(0.36 + float(stage) * 0.05, 0.010 + float(stage) * 0.004)

func _add_grass_details() -> void:
	# Crossed low-poly blades: one tiny generated mesh and one draw call.
	# Keeping these procedural avoids textures and adds almost nothing to the build size.
	var blade_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var blade_offsets := [Vector3(-0.14, 0, -0.06), Vector3(0.14, 0, 0.03), Vector3(0, 0, 0.16)]
	for blade_index in range(blade_offsets.size()):
		var offset: Vector3 = blade_offsets[blade_index]
		var blade_height := 0.68 + float(blade_index) * 0.11
		vertices.append_array(PackedVector3Array([
			offset + Vector3(-0.075, 0, 0), offset + Vector3(0.075, 0, 0), offset + Vector3(0, blade_height, 0),
			offset + Vector3(0, 0, -0.075), offset + Vector3(0, 0, 0.075), offset + Vector3(0, blade_height, 0),
		]))
		normals.append_array(PackedVector3Array([
			Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
			Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0),
		]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	blade_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var grass_shader := Shader.new()
	grass_shader.code = """
shader_type spatial;
render_mode cull_disabled;
void vertex() {
	float phase = MODEL_MATRIX[3].x * 0.61 + MODEL_MATRIX[3].z * 0.37;
	VERTEX.x += sin(TIME * 1.55 + phase) * VERTEX.y * 0.055;
}
void fragment() {
	ALBEDO = vec3(0.24, 0.45, 0.055);
	ROUGHNESS = 1.0;
}
"""
	var grass_material := ShaderMaterial.new()
	grass_material.shader = grass_shader
	blade_mesh.surface_set_material(0, grass_material)

	var placements: Array[Vector3] = []
	for row in range(8):
		for column in range(14):
			var x := -27.0 + float(column) * 4.1 + sin(float(row * 11 + column * 7)) * 0.8
			var z := -27.0 + float(row) * 7.4 + cos(float(row * 5 + column * 13)) * 1.1
			# Keep the central road readable and let grass gather along its edges.
			if absf(x) > 5.0 + absf(z) * 0.035:
				placements.append(Vector3(x, 0.08, z))

	var grass := MultiMeshInstance3D.new()
	grass.name = "MeadowDetails"
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass.visibility_range_end = 52.0
	grass.visibility_range_end_margin = 7.0
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = blade_mesh
	multimesh.instance_count = placements.size()
	for index in range(placements.size()):
		var height := 0.62 + float((index * 17) % 9) * 0.045
		var width := 0.78 + float((index * 7) % 5) * 0.06
		var angle := float((index * 47) % 360) * PI / 180.0
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, height, width))
		multimesh.set_instance_transform(index, Transform3D(basis, placements[index]))
	grass.multimesh = multimesh
	add_child(grass)

func _add_clouds() -> void:
	# Low-poly cloud puffs share one mesh/material and stay cheaper than a sky texture.
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 14
	puff.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.85, 0.92)
	material.roughness = 1.0
	puff.material = material
	var positions := [
		Vector3(-35, 20, -18), Vector3(-31, 20.6, -17), Vector3(-27, 19.8, -18),
		Vector3(24, 23, -32), Vector3(28, 23.6, -31), Vector3(32, 22.8, -33),
		Vector3(-18, 25, 37), Vector3(-14, 25.4, 38), Vector3(-10, 24.7, 37),
		Vector3(36, 19, 14), Vector3(40, 19.5, 13), Vector3(44, 18.8, 15),
	]
	cloud_layer = MultiMeshInstance3D.new()
	cloud_layer.name = "SummerClouds"
	cloud_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = puff
	multimesh.instance_count = positions.size()
	for index in range(positions.size()):
		var scale_value := 2.3 + float(index % 3) * 0.55
		var basis := Basis.IDENTITY.scaled(Vector3(scale_value * 1.55, scale_value * 0.48, scale_value))
		multimesh.set_instance_transform(index, Transform3D(basis, positions[index]))
	cloud_layer.multimesh = multimesh
	add_child(cloud_layer)

func _add_road_details() -> void:
	# Two uneven wheel tracks give the broad road direction and depth with one draw call.
	var rut_mesh := BoxMesh.new()
	rut_mesh.size = Vector3(0.085, 0.012, 1.94)
	var rut_material := StandardMaterial3D.new()
	rut_material.albedo_color = Color(0.47, 0.335, 0.18)
	rut_material.roughness = 1.0
	rut_mesh.material = rut_material
	var rut_count := 68
	var rut_multimesh := MultiMesh.new()
	rut_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	rut_multimesh.mesh = rut_mesh
	rut_multimesh.instance_count = rut_count
	for index in range(rut_count):
		var row := index / 2
		var side := -1.0 if index % 2 == 0 else 1.0
		var z := 27.0 - float(row) * 1.78
		var x := side * (1.08 + sin(float(row) * 0.43) * 0.10)
		var angle := sin(float(row) * 0.37) * 0.035
		var width := 0.72 + float((row * 5 + index) % 7) * 0.055
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, 1.0, 1.0))
		rut_multimesh.set_instance_transform(index, Transform3D(basis, Vector3(x, 0.014, z)))
	var ruts := MultiMeshInstance3D.new()
	ruts.name = "RoadRuts"
	ruts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ruts.multimesh = rut_multimesh
	add_child(ruts)

	# Small edge stones break up the flat road/grass boundary without colliders.
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 0.15
	pebble_mesh.height = 0.16
	pebble_mesh.radial_segments = 10
	pebble_mesh.rings = 6
	var pebble_material := StandardMaterial3D.new()
	pebble_material.albedo_color = Color(0.50, 0.46, 0.35)
	pebble_material.roughness = 1.0
	pebble_mesh.material = pebble_material
	var pebble_count := 30
	var pebble_multimesh := MultiMesh.new()
	pebble_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	pebble_multimesh.mesh = pebble_mesh
	pebble_multimesh.instance_count = pebble_count
	for index in range(pebble_count):
		var side := -1.0 if index % 2 == 0 else 1.0
		var row := index / 2
		var z := 25.0 - float(row) * 3.55
		var x := side * (3.35 + sin(float(index) * 1.71) * 0.38)
		var size := 0.62 + float((index * 7) % 6) * 0.09
		var basis := Basis(Vector3.UP, float(index) * 1.37).scaled(Vector3(size * 1.25, size, size))
		pebble_multimesh.set_instance_transform(index, Transform3D(basis, Vector3(x, 0.085, z)))
	var pebbles := MultiMeshInstance3D.new()
	pebbles.name = "RoadEdgePebbles"
	pebbles.multimesh = pebble_multimesh
	add_child(pebbles)

func _add_festival_bunting() -> void:
	# Empty festival decorations make the village feel inhabited, but abandoned.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var spans := [
		[Vector3(-7.0, 3.75, 10.1), Vector3(7.0, 3.68, 10.1)],
		[Vector3(-7.2, 3.55, -5.3), Vector3(7.2, 3.48, -5.3)],
		[Vector3(-6.6, 3.72, -17.0), Vector3(6.6, 3.62, -17.0)],
	]
	var flag_colors := [
		Color(0.82, 0.12, 0.045), Color(0.97, 0.60, 0.055),
		Color(0.10, 0.37, 0.52), Color(0.73, 0.76, 0.18),
	]
	for span_index in range(spans.size()):
		var start: Vector3 = spans[span_index][0]
		var finish: Vector3 = spans[span_index][1]
		var previous := start
		for segment in range(12):
			var t := float(segment + 1) / 12.0
			var point := start.lerp(finish, t)
			point.y -= sin(t * PI) * 0.34
			_append_colored_quad(vertices, normals, colors,
				previous + Vector3(0, 0.018, 0), previous - Vector3(0, 0.018, 0),
				point - Vector3(0, 0.018, 0), point + Vector3(0, 0.018, 0),
				Color(0.20, 0.105, 0.045))
			previous = point
		for flag_index in range(9):
			var t := float(flag_index + 1) / 10.0
			var top := start.lerp(finish, t)
			top.y -= sin(t * PI) * 0.34
			var half_width := 0.23
			var color: Color = flag_colors[(flag_index + span_index) % flag_colors.size()]
			_append_colored_triangle(vertices, normals, colors,
				top + Vector3(-half_width, -0.025, 0),
				top + Vector3(half_width, -0.025, 0),
				top + Vector3(0, -0.61, 0), color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var flag_shader := Shader.new()
	flag_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void vertex() {
	float hanging = clamp((3.58 - VERTEX.y) / 0.78, 0.0, 1.0);
	float wave = sin(TIME * 2.15 + VERTEX.x * 0.82 + VERTEX.y * 1.6);
	VERTEX.z += wave * 0.060 * hanging;
	VERTEX.x += sin(TIME * 1.35 + VERTEX.x * 0.55) * 0.016 * hanging;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.035;
	ROUGHNESS = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = flag_shader
	mesh.surface_set_material(0, material)
	var bunting := MeshInstance3D.new()
	bunting.name = "FestivalBunting"
	bunting.mesh = mesh
	add_child(bunting)

func _append_colored_triangle(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD]))
	colors.append_array(PackedColorArray([color, color, color]))

func _append_colored_quad(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_append_colored_triangle(vertices, normals, colors, a, b, c, color)
	_append_colored_triangle(vertices, normals, colors, a, c, d, color)

func _add_watching_eyes(houses: Array) -> void:
	# One pair is present at noon; more windows wake as the sun moves toward dusk.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.055
	eye_mesh.height = 0.11
	eye_mesh.radial_segments = 12
	eye_mesh.rings = 7
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.92, 0.11, 0.015)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.018, 0.002)
	material.emission_energy_multiplier = 2.8
	eye_mesh.material = material
	var order := [2, 3, 4, 5, 0, 1]
	var window_xs := [-1.55, 0.65, -1.65, -1.35, 1.35, -1.65, 1.55, 1.55]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = eye_mesh
	multimesh.instance_count = order.size() * 2
	for pair_index in range(order.size()):
		var house_index: int = order[pair_index]
		var house_data: Array = houses[house_index]
		var house_position: Vector3 = house_data[1]
		var house_rotation: float = house_data[2]
		var house_size: Vector3 = house_data[3]
		var facing := Basis(Vector3.UP, house_rotation)
		var local_x: float = window_xs[house_index]
		var center := house_position + facing * Vector3(local_x, 1.79, house_size.z * 0.5 + 0.19)
		var eye_basis := facing.scaled(Vector3(1.0, 0.72, 0.42))
		for side in range(2):
			var separation := -0.105 if side == 0 else 0.105
			var eye_position := center + facing * Vector3(separation, 0, 0)
			multimesh.set_instance_transform(pair_index * 2 + side, Transform3D(eye_basis, eye_position))
	watching_eyes = MultiMeshInstance3D.new()
	watching_eyes.name = "WatchingWindows"
	watching_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	watching_eyes.multimesh = multimesh
	add_child(watching_eyes)
	_update_watching_eyes()

func _update_watching_eyes() -> void:
	if not is_instance_valid(watching_eyes):
		return
	var visible_counts := [2, 4, 8, 12, 12]
	watching_eyes.multimesh.visible_instance_count = visible_counts[clampi(lighting_stage, 0, 4)]

func _add_ritual_effigies() -> void:
	var placements := [
		[Vector3(-6.2, 0, 9.0), -0.18, -0.08], [Vector3(6.5, 0, 5.0), 0.22, 0.10],
		[Vector3(-6.8, 0, -9.0), 0.14, 0.07], [Vector3(6.4, 0, -16.0), -0.20, -0.09],
		[Vector3(-19.0, 0, -3.0), 0.36, 0.12], [Vector3(19.0, 0, -19.0), -0.31, -0.11],
	]
	for index in range(placements.size()):
		var position: Vector3 = placements[index][0]
		var yaw: float = placements[index][1]
		var tilt: float = placements[index][2]
		var effigy := _add_visual(STRAW_DOLL, position, yaw, Vector3.ONE * 0.94)
		effigy.name = "RitualStrawDoll%d" % (index + 1)
		effigy.rotation.z = tilt

func _add_totem_aura() -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.47, 0.035, 0.48)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.10, 0.008)
	material.emission_energy_multiplier = 1.5
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.12
	ring_mesh.outer_radius = 1.20
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 5
	ring_mesh.material = material
	totem_aura = Node3D.new()
	totem_aura.name = "TotemAura"
	totem_aura.position = Vector3(0, 0, -2)
	add_child(totem_aura)
	for index in range(2):
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % (index + 1)
		ring.position.y = 0.45 + index * 0.72
		ring.rotation = Vector3(index * 0.22, 0, index * 0.18)
		ring.scale = Vector3.ONE * (0.82 + index * 0.18)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.mesh = ring_mesh
		totem_aura.add_child(ring)
	totem_light = OmniLight3D.new()
	totem_light.name = "TotemGlow"
	totem_light.position = Vector3(0, 2.3, 0)
	totem_light.light_color = Color(1.0, 0.35, 0.045)
	totem_light.light_energy = 0.58
	totem_light.omni_range = 4.8
	totem_light.shadow_enabled = false
	totem_aura.add_child(totem_light)

func _add_visual(scene: PackedScene, pos: Vector3, rotation_y := 0.0, model_scale := Vector3.ONE) -> Node3D:
	var instance := scene.instantiate()
	instance.position = pos
	instance.rotation.y = rotation_y
	instance.scale = model_scale
	add_child(instance)
	return instance

func _add_box_collider(pos: Vector3, size: Vector3, rotation_y := 0.0) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	body.rotation.y = rotation_y
	add_child(body)

func _add_cylinder_collider(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	body.position = pos
	add_child(body)

## Кольцо гор — только модель, коллайдера у неё нет: игрок уходил в склон.
## Ставим стену по подошве, оставляя проход на север к воротам.
func _add_boundaries() -> void:
	MOUNTAIN_RING.build_wall(self)
	_add_box_collider(Vector3(-30, 2, 0), Vector3(1, 4, 60))
	_add_box_collider(Vector3(30, 2, 0), Vector3(1, 4, 60))
	_add_box_collider(Vector3(0, 2, 30), Vector3(60, 4, 1))
	_add_box_collider(Vector3(-16, 2, -30), Vector3(28, 4, 1))
	_add_box_collider(Vector3(16, 2, -30), Vector3(28, 4, 1))

func _spawn_seals() -> void:
	for pos in [Vector3(-16, 1.0, 17), Vector3(17, 1.0, -9), Vector3(-14, 1.0, -20)]:
		var seal = SEAL_SCENE.instantiate()
		seal.position = pos
		add_child(seal)
		seal_nodes.append(seal)
		seal.collected.connect(_on_seal_collected)

func _add_exit_area() -> void:
	var area := Area3D.new()
	area.name = "NorthGate"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.2, 3.0, 2.0)
	collision.shape = shape
	area.add_child(collision)
	area.position = Vector3(0, 1.5, -27)
	add_child(area)
	area.body_entered.connect(_on_exit_entered)

func _start_game() -> void:
	run_time = 0.0
	hits_taken = 0
	pulses_used = 0
	charges_dodged = 0
	phase = Phase.PLAYING
	intro.visible = false
	objective.visible = true
	health_panel.visible = true
	pulse_label.visible = true
	$UI/Crosshair.visible = not DisplayServer.is_touchscreen_available()
	player.set_controls_enabled(true)
	yandex.gameplay_start()
	_show_hint(_text("intro_hint"), 4.0)
	# Деревня 60×60 м без единого ориентира: без стартового маяка новичок
	# не понимает, куда идти, и первая печать находится случайно.
	var first_seal := _nearest_untaken_seal()
	if first_seal != null:
		_spawn_seal_beacon(first_seal, 7.0)

func _on_seal_collected(_seal: Area3D) -> void:
	if phase != Phase.PLAYING:
		return
	seals_found += 1
	seal_nodes.erase(_seal)
	_apply_lighting_stage(seals_found)
	audio.play_event("seal", 1.0 + seals_found * 0.035)
	objective.text = _text("seals") % seals_found
	guardian.awaken(seals_found)
	guardian.stun(2.2)
	_change_health(22.0)
	recovery_cooldown = 0.0
	_release_gate_ward(seals_found - 1)
	if seals_found < 3:
		_show_hint(_text("seal_heal") if seals_found > 1 else _text("guardian_hint"), 3.2)
	else:
		_begin_final_escape()
		_show_hint(_text("last_seal"), 4.0)

func _begin_final_escape(duration := ESCAPE_WINDOW) -> void:
	escape_time_remaining = maxf(0.05, duration)
	sunset_triggered = false
	_reveal_exit_path()
	guardian.enrage(6.0)
	audio.play_event("gate")
	_update_objective_text()

func _trigger_sunset() -> void:
	if sunset_triggered or phase != Phase.PLAYING:
		return
	sunset_triggered = true
	escape_time_remaining = 0.0
	_apply_lighting_stage(4)
	guardian.enrage(60.0)
	audio.play_event("sunset")
	_update_objective_text()
	_show_hint(_text("sunset_hint"), 4.2)

func _update_objective_text() -> void:
	if seals_found < 3:
		objective.text = _text("seals") % seals_found
	elif sunset_triggered:
		objective.text = _text("sunset_objective")
	else:
		objective.text = _text("escape_timer") % maxi(0, ceili(escape_time_remaining))

func _on_exit_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or phase != Phase.PLAYING:
		return
	if seals_found == 3:
		_finish(true)
	else:
		_show_hint(_text("gate_locked"), 2.5)

func _on_guardian_hit(amount: float) -> void:
	if phase != Phase.PLAYING:
		return
	hits_taken += 1
	player.apply_knockback(guardian.global_position, 4.8)
	_change_health(-amount)
	recovery_cooldown = 4.5
	damage_flash = 0.72
	audio.play_event("hit")
	if health <= 0.0:
		_finish(false)
	elif not wound_hint_shown:
		wound_hint_shown = true
		_show_hint(_text("wounded"), 3.0)

func _on_guardian_charge_started() -> void:
	audio.play_event("charge")
	if not charge_hint_shown and phase == Phase.PLAYING:
		charge_hint_shown = true
		_show_hint(_text("guardian_charge"), 2.8)

func _on_guardian_charge_evaded() -> void:
	if phase == Phase.PLAYING:
		charges_dodged += 1

func _on_guardian_attack_started() -> void:
	if phase == Phase.PLAYING:
		audio.play_event("attack")

func _change_health(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_HEALTH)
	_update_health_ui()

func _update_health_ui() -> void:
	health_bar.value = health
	health_value.text = "%d / %d" % [ceili(health), int(MAX_HEALTH)]
	health_panel.modulate = Color(1.0, 0.56, 0.48) if health <= 28.0 else Color.WHITE
	player.set_health_ratio(health / MAX_HEALTH)

func _on_stamina_changed(value: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = value
	stamina_value.text = "%d / %d" % [ceili(value), int(maximum)]
	stamina_bar.modulate = Color(0.75, 0.48, 0.30) if value <= 1.0 else Color.WHITE

func _result_summary(won: bool) -> String:
	return _text("result_stats") % [
		_format_run_time(run_time),
		hits_taken,
		pulses_used,
		charges_dodged,
		_result_grade(won),
	]

func _format_run_time(seconds: float) -> String:
	var total_seconds := maxi(0, roundi(seconds))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]

func _result_grade(won: bool) -> String:
	if not won:
		return "D"
	var score := 100.0
	score -= float(hits_taken) * 12.0
	score -= maxf(0.0, run_time - 70.0) * 0.45
	score += minf(float(charges_dodged) * 2.0, 6.0)
	if sunset_triggered:
		score -= 35.0
	if score >= 92.0:
		return "S"
	if score >= 78.0:
		return "A"
	if score >= 62.0:
		return "B"
	return "C"

func _finish(won: bool) -> void:
	phase = Phase.WON if won else Phase.LOST
	player.set_controls_enabled(false)
	yandex.gameplay_stop()
	end_screen.visible = true
	if won:
		death_reward_button.visible = false
		end_title.text = _text("win_title_late") if sunset_triggered else _text("win_title")
		end_text.text = (_text("win_text_late") if sunset_triggered else _text("win_text")) + "\n\n" + _result_summary(won)
	else:
		end_title.text = _text("death_title")
		end_text.text = _text("death_offer") + "\n\n" + _result_summary(won)
		death_reward_button.visible = true
		death_reward_button.disabled = not OS.has_feature("web") or not yandex.initialized
		death_reward_button.text = _text("reward_life") if not death_reward_button.disabled else _text("reward_yandex_only")
	$UI/Crosshair.visible = false
	_apply_end_screen_accent(won)
	if won:
		yandex.record_story_result(run_time, _result_grade(true))

func _process(delta: float) -> void:
	if is_instance_valid(cloud_layer):
		cloud_layer.rotation.y += delta * 0.0018
	if is_instance_valid(ritual_sun_visual):
		ritual_sun_visual.rotation.z += delta * (0.008 + float(lighting_stage) * 0.0025)
		var sun_pulse := 1.0 + sin(Time.get_ticks_msec() * 0.0011) * 0.012
		ritual_sun_visual.scale = Vector3.ONE * sun_pulse
	if is_instance_valid(exit_path) and exit_path.visible:
		exit_path_time += delta
		for index in range(exit_path.multimesh.instance_count):
			var pulse := 0.86 + sin(exit_path_time * 3.4 - index * 0.8) * 0.16
			var basis := Basis().scaled(Vector3.ONE * pulse)
			exit_path.multimesh.set_instance_transform(index, Transform3D(basis, Vector3(0, 0.12, -29.2 - index * 2.8)))
	if is_instance_valid(totem_aura) and not totem_used:
		totem_aura.rotation.y += delta * 0.55
		totem_light.light_energy = 0.52 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	if phase != Phase.PLAYING:
		return
	run_time += delta
	if not is_instance_valid(guardian):
		return
	if seals_found == 3 and not sunset_triggered:
		escape_time_remaining = maxf(0.0, escape_time_remaining - delta)
		if escape_time_remaining <= 0.0:
			_trigger_sunset()
		else:
			_update_objective_text()
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta * 1.8)
	sun_pulse_cooldown = maxf(0.0, sun_pulse_cooldown - delta)
	var in_shadow := _is_player_in_shadow()
	guardian.player_in_shadow = in_shadow
	shade_label.text = _text("shade") if in_shadow and guardian.active else ""
	_update_pulse_label()
	var near_totem: bool = player.global_position.distance_to(Vector3(0, 0, -2)) < 3.0
	if near_totem and not player_near_totem and not totem_used:
		_show_hint(_text("totem_prompt"), 3.2)
	player_near_totem = near_totem
	if not sunset_triggered and not in_shadow and recovery_cooldown <= 0.0 and health < MAX_HEALTH:
		_change_health(SUN_RECOVERY_PER_SECOND * delta)
	var distance := guardian.global_position.distance_to(player.global_position)
	var proximity: float = clampf((8.0 - distance) / 8.0, 0.0, 0.42) if guardian.active else 0.0
	var low_health_pulse := clampf((40.0 - health) / 40.0, 0.0, 0.26) * (0.72 + sin(Time.get_ticks_msec() * 0.006) * 0.28)
	var strength := maxf(maxf(proximity, damage_flash), low_health_pulse)
	danger.color = Color(0.48, 0.0, 0.0, strength)
	if player.global_position.y < -3.0:
		player.reset_to_spawn()
		_change_health(-16.0)
		recovery_cooldown = 3.0
		if health <= 0.0:
			_finish(false)
		else:
			_show_hint(_text("respawn"), 2.0)

func _is_player_in_shadow() -> bool:
	return _is_position_in_shadow(player.global_position)

func _sun_direction() -> Vector3:
	return $Sun.global_transform.basis.z.normalized()

func _is_position_in_shadow(position: Vector3) -> bool:
	var origin := position + Vector3(0, 1.0, 0)
	var toward_sun: Vector3 = _sun_direction()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + toward_sun * 55.0)
	query.exclude = [player.get_rid(), guardian.get_rid()]
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_pulse_label() -> void:
	if seals_found <= 0:
		pulse_label.text = _text("pulse_no_seal")
		pulse_label.add_theme_color_override("font_color", Color(0.76, 0.67, 0.51))
	elif sun_pulse_cooldown > 0.0:
		pulse_label.text = _text("pulse_wait") % sun_pulse_cooldown
		pulse_label.add_theme_color_override("font_color", Color(0.96, 0.59, 0.27))
	elif player.stamina < 34.0:
		pulse_label.text = _text("pulse_no_stamina")
		pulse_label.add_theme_color_override("font_color", Color(0.96, 0.34, 0.23))
	else:
		pulse_label.text = _text("pulse_ready")
		pulse_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.43))

func _toggle_pause() -> void:
	if suspended_by_platform:
		return
	if phase == Phase.PLAYING:
		phase = Phase.PAUSED
		get_tree().paused = true
		pause_label.visible = true
		player.set_controls_enabled(false)
		yandex.gameplay_stop()
	elif phase == Phase.PAUSED:
		get_tree().paused = false
		phase = Phase.PLAYING
		pause_label.visible = false
		player.set_controls_enabled(true)
		yandex.gameplay_start()

## После победы главное действие — идти дальше, после поражения — начать
## заново, поэтому оформление главной кнопки переезжает между ними.
func _apply_end_screen_accent(won: bool) -> void:
	var restart := $UI/End/Center/Content/Restart as Button
	if is_instance_valid(next_challenge_button):
		next_challenge_button.visible = won
	_style_dialog_button(restart, not won)
	if won:
		restart.add_theme_font_size_override("font_size", 16)
		restart.custom_minimum_size = Vector2(0, 44)
	else:
		restart.add_theme_font_size_override("font_size", 21)
		restart.custom_minimum_size = Vector2(0, 0)

## Кнопка появляется только после победы: сюжет открывает первое испытание.
func _build_next_challenge_button() -> void:
	var content := $UI/End/Center/Content as VBoxContainer
	var restart := $UI/End/Center/Content/Restart as Button
	next_challenge_button = Button.new()
	next_challenge_button.name = "NextChallenge"
	next_challenge_button.text = _text("next_challenge")
	next_challenge_button.custom_minimum_size = restart.custom_minimum_size
	next_challenge_button.visible = false
	# Главное действие после победы — идти дальше, поэтому забираем себе
	# оформление и размер шрифта прежней главной кнопки.
	next_challenge_button.add_theme_font_size_override("font_size", 21)
	_style_dialog_button(next_challenge_button, true)
	next_challenge_button.pressed.connect(_open_first_challenge)
	content.add_child(next_challenge_button)
	content.move_child(next_challenge_button, restart.get_index())

func _build_death_reward_button() -> void:
	var content := $UI/End/Center/Content as VBoxContainer
	var restart := $UI/End/Center/Content/Restart as Button
	death_reward_button = Button.new()
	death_reward_button.name = "RewardedLife"
	death_reward_button.text = _text("reward_life")
	death_reward_button.custom_minimum_size = Vector2(0, 54)
	death_reward_button.add_theme_font_size_override("font_size", 20)
	death_reward_button.visible = false
	_style_dialog_button(death_reward_button, true)
	death_reward_button.pressed.connect(_request_rewarded_life)
	content.add_child(death_reward_button)
	content.move_child(death_reward_button, restart.get_index())

func _request_rewarded_life() -> void:
	if phase != Phase.LOST or death_reward_button.disabled:
		return
	death_reward_button.disabled = true
	death_reward_button.text = _text("reward_loading")
	end_text.text = _text("reward_wait")
	yandex.show_rewarded_life(_on_rewarded_life_finished)

func _on_rewarded_life_finished(granted: bool) -> void:
	if phase != Phase.LOST:
		return
	if not granted:
		death_reward_button.disabled = not OS.has_feature("web") or not yandex.initialized
		death_reward_button.text = _text("reward_life") if not death_reward_button.disabled else _text("reward_yandex_only")
		end_text.text = _text("reward_not_completed")
		return
	end_screen.visible = false
	death_reward_button.visible = false
	player.reset_to_spawn()
	health = MAX_HEALTH
	_update_health_ui()
	player.restore_stamina(player.max_stamina)
	recovery_cooldown = 3.0
	damage_flash = 0.0
	if is_instance_valid(guardian):
		guardian.stun(2.8)
	phase = Phase.PLAYING
	player.set_controls_enabled(true)
	$UI/Crosshair.visible = not DisplayServer.is_touchscreen_available()
	yandex.gameplay_start()
	_show_hint(_text("reward_revived"), 3.0)

func _open_first_challenge() -> void:
	var path := FLOW.challenge_path(FLOW.FIRST_CHALLENGE)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("First challenge scene is missing: " + path)
		return
	get_tree().paused = false
	yandex.gameplay_stop()
	yandex.show_interstitial(_change_scene_after_interstitial.bind(path))

func _change_scene_after_interstitial(_was_shown: bool, path: String) -> void:
	get_tree().change_scene_to_file(path)

func _restart() -> void:
	get_tree().paused = false
	if phase in [Phase.WON, Phase.LOST]:
		yandex.show_interstitial(_reload_after_interstitial)
	else:
		get_tree().reload_current_scene()

func _reload_after_interstitial(_was_shown: bool) -> void:
	get_tree().reload_current_scene()

func _return_to_menu() -> void:
	get_tree().paused = false
	yandex.gameplay_stop()
	if phase in [Phase.WON, Phase.LOST]:
		yandex.show_interstitial(_menu_after_interstitial)
	else:
		get_tree().change_scene_to_file(FLOW.MENU_SCENE)

func _menu_after_interstitial(_was_shown: bool) -> void:
	get_tree().change_scene_to_file(FLOW.MENU_SCENE)

func _show_hint(text_value: String, duration: float) -> void:
	hint_serial += 1
	var serial := hint_serial
	hint.text = text_value
	await get_tree().create_timer(duration).timeout
	if serial == hint_serial:
		hint.text = ""

func _touch_action() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")

func _on_platform_suspension_changed(suspended: bool) -> void:
	if suspended:
		if phase == Phase.PLAYING and not get_tree().paused:
			suspended_by_platform = true
			get_tree().paused = true
			player.set_controls_enabled(false)
			yandex.gameplay_stop()
	elif suspended_by_platform:
		suspended_by_platform = false
		if phase == Phase.PLAYING:
			get_tree().paused = false
			player.set_controls_enabled(true)
			yandex.gameplay_start()

func _apply_language(language: String) -> void:
	current_language = yandex.get_ui_language(language)
	$UI/Intro/Center/Panel/Margin/Content/Title.text = _text("title")
	$UI/Intro/Center/Panel/Margin/Content/Story.text = _text("story")
	$UI/Intro/Center/Panel/Margin/Content/Controls.text = _text("controls")
	$UI/Intro/Center/Panel/Margin/Content/Start.text = _text("start")
	$UI/Intro/Center/Panel/Margin/Content/Menu.text = _text("menu")
	$UI/End/Center/Content/Restart.text = _text("restart")
	if is_instance_valid(next_challenge_button):
		next_challenge_button.text = _text("next_challenge")
	if is_instance_valid(death_reward_button):
		death_reward_button.text = _text("reward_life") if not death_reward_button.disabled else _text("reward_yandex_only")
	if phase == Phase.LOST:
		end_title.text = _text("death_title")
		end_text.text = _text("death_offer") + "\n\n" + _result_summary(false)
	$UI/End/Center/Content/Menu.text = _text("menu")
	health_title.text = _text("health")
	stamina_title.text = _text("stamina")
	pause_label.text = _text("pause")
	_update_objective_text()

func _text(key: String) -> String:
	return String(TEXT[current_language].get(key, key))
