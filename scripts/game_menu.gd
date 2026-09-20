extends Node

const FLOW := preload("res://scripts/game_flow.gd")

@onready var yandex: Node = get_node("/root/YandexService")
@onready var background_material: ShaderMaterial = $UI/Background.material as ShaderMaterial
@onready var title: Label = $UI/Layout/Title
@onready var subtitle: Label = $UI/Layout/Subtitle
@onready var story_button: Button = $UI/Layout/Story
@onready var progress_label: Label = $UI/Layout/AccountRow/Progress
@onready var cloud_button: Button = $UI/Layout/AccountRow/Cloud
@onready var story_row: Control = $UI/Layout/Story
@onready var challenge_heading: Label = $UI/Layout/ChallengeHeading
@onready var challenge_grid: GridContainer = $UI/Layout/ChallengeScroll/ChallengeGrid
@onready var footer: Label = $UI/Layout/Footer

var current_language := "ru"
var daily_button: Button = null
var daily_level := 0
var daily_refreshing := false
var background_clock := 0.0
var background_suspended := false

const TEXT := {
	"ru": {
		"title": "БЕЛЫЙ ПОЛДЕНЬ",
		"subtitle": "Двадцать один шаг навстречу неподвижному солнцу",
		"story": "НАЧАТЬ ИСТОРИЮ",
		"progress": "ПРОЙДЕНО ИСПЫТАНИЙ: %d / 20",
		"cloud_login": "ВОЙТИ В ЯНДЕКС ID — ОБЛАЧНЫЙ ПРОГРЕСС",
		"cloud_connected": "ЯНДЕКС ID • ОБЛАКО ПОДКЛЮЧЕНО",
		"cloud_loading": "СИНХРОНИЗАЦИЯ С ОБЛАКОМ...",
		"cloud_local": "ПРОГРЕСС СОХРАНЯЕТСЯ ЛОКАЛЬНО",
		"cloud_error": "ОБЛАКО НЕДОСТУПНО • СОХРАНЕНО ЛОКАЛЬНО",
		"daily": "ИСПЫТАНИЕ ДНЯ  •  %02d  %s",
		"daily_done": "ИСПЫТАНИЕ ДНЯ ПРОЙДЕНО  •  %02d  %s",
		"daily_streak": "  •  СЕРИЯ: %d",
		"daily_locked": "ИСПЫТАНИЕ ДНЯ ОТКРОЕТСЯ ПОСЛЕ СЮЖЕТА",
		"heading": "ИСПЫТАНИЯ  •  УРОВНИ 2–21",
		"locked": "ЗАКРЫТО",
		"locked_first": "Пройдите сюжет, чтобы открыть первое испытание",
		"locked_hint": "Пройдите уровень %d, чтобы открыть этот",
		"footer": "WASD — движение  •  Shift — бег  •  Мышь/свайп — обзор  •  E/Пробел — действие  •  Esc/кнопка паузы",
	},
	"en": {
		"title": "WHITE NOON",
		"subtitle": "Twenty-one steps toward the motionless sun",
		"story": "START THE STORY",
		"progress": "CHALLENGES COMPLETED: %d / 20",
		"cloud_login": "SIGN IN WITH YANDEX ID — CLOUD PROGRESS",
		"cloud_connected": "YANDEX ID • CLOUD CONNECTED",
		"cloud_loading": "SYNCING CLOUD PROGRESS...",
		"cloud_local": "PROGRESS IS SAVED LOCALLY",
		"cloud_error": "CLOUD UNAVAILABLE • SAVED LOCALLY",
		"daily": "CHALLENGE OF THE DAY  •  %02d  %s",
		"daily_done": "DAILY CHALLENGE CLEARED  •  %02d  %s",
		"daily_streak": "  •  STREAK: %d",
		"daily_locked": "THE DAILY CHALLENGE UNLOCKS AFTER THE STORY",
		"heading": "CHALLENGES  •  LEVELS 2–21",
		"locked": "LOCKED",
		"locked_first": "Finish the story to unlock the first challenge",
		"locked_hint": "Finish level %d to unlock this one",
		"footer": "WASD — move  •  Shift — run  •  Mouse/swipe — look  •  E/Space — action  •  Esc/pause button",
	},
}

func _ready() -> void:
	story_button.pressed.connect(_open_story)
	cloud_button.pressed.connect(yandex.open_auth_dialog)
	_style_menu_button(story_button, true)
	_style_menu_button(cloud_button, false)
	yandex.language_detected.connect(_apply_language)
	yandex.platform_suspension_changed.connect(_on_platform_suspension_changed)
	yandex.progress_changed.connect(_on_progress_changed)
	yandex.authorization_changed.connect(_on_authorization_changed)
	yandex.cloud_status_changed.connect(_on_cloud_status_changed)
	_build_daily_button()
	_build_challenge_buttons()
	_apply_language(String(yandex.detected_language))
	_update_progress_ui()
	_update_cloud_ui()
	yandex.gameplay_stop()
	yandex.mark_game_ready()

func _process(delta: float) -> void:
	if background_suspended or not is_instance_valid(background_material):
		return
	background_clock += delta
	background_material.set_shader_parameter("motion_value", background_clock)

## Возврат в игру должен быть виден сразу: «испытание дня» стоит прямо под
## кнопкой сюжета, а не в глубине списка из двадцати уровней.
func _build_daily_button() -> void:
	daily_button = Button.new()
	daily_button.name = "DailyChallenge"
	daily_button.custom_minimum_size = Vector2(0, 44)
	daily_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	daily_button.add_theme_font_size_override("font_size", 17)
	_style_menu_button(daily_button, true)
	daily_button.pressed.connect(_open_daily)
	$UI/Layout.add_child(daily_button)
	$UI/Layout.move_child(daily_button, story_row.get_index() + 1)

func _refresh_daily_button() -> void:
	# Закрепление испытания сохраняет прогресс, а сохранение снова дёргает
	# обновление UI. Без этого флага получилась бы лишняя рекурсия.
	if not is_instance_valid(daily_button) or daily_refreshing:
		return
	daily_refreshing = true
	_refresh_daily_button_inner()
	daily_refreshing = false

func _refresh_daily_button_inner() -> void:
	var strings: Dictionary = TEXT[current_language]
	daily_level = yandex.get_daily_level()
	if daily_level <= 0:
		# На сегодня ещё не выбрано — фиксируем выбор один раз за сутки.
		daily_level = yandex.pin_daily_challenge(FLOW.daily_challenge_level(yandex, yandex.current_day()))
	if daily_level <= 0:
		daily_button.text = String(strings.daily_locked)
		daily_button.disabled = true
		return
	daily_button.disabled = false
	var level_title := FLOW.challenge_title(daily_level, current_language)
	var done: bool = yandex.is_daily_done()
	daily_button.text = String(strings.daily_done if done else strings.daily) % [daily_level, level_title]
	var streak: int = yandex.get_daily_streak()
	if streak > 1:
		daily_button.text += String(strings.daily_streak) % streak

func _open_daily() -> void:
	if daily_level > 0:
		_open_challenge(daily_level)

func _build_challenge_buttons() -> void:
	for child in challenge_grid.get_children():
		child.queue_free()
	for level_number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var button := Button.new()
		button.name = "Level%02d" % level_number
		button.custom_minimum_size = Vector2(220, 56)
		button.add_theme_font_size_override("font_size", 16)
		_style_menu_button(button, false)
		button.set_meta("level_number", level_number)
		button.pressed.connect(_open_challenge.bind(level_number))
		challenge_grid.add_child(button)
	_update_challenge_labels()

func _style_menu_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("5e160f") if accent else Color("13110fe8")
	normal.border_color = Color("d6ad62") if accent else Color("8f7549c8")
	normal.set_border_width_all(2 if accent else 1)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 9.0
	normal.content_margin_bottom = 9.0
	var hover := normal.duplicate()
	hover.bg_color = Color("84261a") if accent else Color("2b2119f2")
	hover.border_color = Color("ffe4a0")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("3c0e0a") if accent else Color("0b0908f5")
	var disabled := normal.duplicate()
	disabled.bg_color = Color("0e0d0c99")
	disabled.border_color = Color("5d524166")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("fff1c7"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffd477"))
	button.add_theme_color_override("font_disabled_color", Color("8e8678"))
	button.add_theme_color_override("font_outline_color", Color("120b08cc"))
	button.add_theme_constant_override("outline_size", 3)

func _apply_language(language: String) -> void:
	current_language = yandex.get_ui_language(language)
	var strings: Dictionary = TEXT[current_language]
	title.text = String(strings.title)
	subtitle.text = String(strings.subtitle)
	story_button.text = String(strings.story)
	challenge_heading.text = String(strings.heading)
	footer.text = String(strings.footer)
	_update_challenge_labels()
	_update_progress_ui()
	_update_cloud_ui()

func _update_challenge_labels() -> void:
	if not is_instance_valid(challenge_grid):
		return
	var strings: Dictionary = TEXT[current_language]
	for button in challenge_grid.get_children():
		var level_number := int(button.get_meta("level_number", 0))
		var unlocked: bool = FLOW.is_challenge_unlocked(level_number, yandex)
		button.disabled = not unlocked
		if not unlocked:
			# Название закрытого испытания не показываем: пусть остаётся
			# впереди, а подсказка объясняет, что для него нужно.
			button.text = "%02d  •  %s" % [level_number, String(strings.locked)]
			button.tooltip_text = String(strings.locked_first) if level_number <= FLOW.FIRST_CHALLENGE else String(strings.locked_hint) % (level_number - 1)
			continue
		var level_title := FLOW.challenge_title(level_number, current_language)
		var grade: String = yandex.get_level_grade(level_number)
		var marker: String = ((grade if not grade.is_empty() else "✓") + "  ") if yandex.is_level_completed(level_number) else ""
		button.text = "%s%02d  •  %s" % [marker, level_number, level_title]
		button.tooltip_text = ""

func _update_progress_ui() -> void:
	if not is_instance_valid(progress_label):
		return
	var strings: Dictionary = TEXT[current_language]
	_refresh_daily_button()
	progress_label.text = String(strings.progress) % yandex.get_completed_challenge_count()
	story_button.text = String(strings.story)
	if bool(yandex.progress.get("story_completed", false)):
		var grade: String = String(yandex.progress.get("story_best_grade", ""))
		story_button.text += "  •  ✓" + ("  " + grade if not grade.is_empty() else "")
	_update_challenge_labels()

func _update_cloud_ui() -> void:
	if not is_instance_valid(cloud_button):
		return
	var strings: Dictionary = TEXT[current_language]
	if not OS.has_feature("web"):
		cloud_button.text = String(strings.cloud_local)
		cloud_button.disabled = true
	elif yandex.player_authorized:
		cloud_button.text = String(strings.cloud_connected)
		cloud_button.disabled = true
	elif yandex.cloud_status in ["loading", "saving"]:
		cloud_button.text = String(strings.cloud_loading)
		cloud_button.disabled = true
	elif yandex.cloud_status == "error":
		cloud_button.text = String(strings.cloud_error)
		cloud_button.disabled = not yandex.initialized
	else:
		cloud_button.text = String(strings.cloud_login)
		cloud_button.disabled = not yandex.initialized

func _on_progress_changed(_progress: Dictionary) -> void:
	_update_progress_ui()

func _on_authorization_changed(_authorized: bool) -> void:
	_update_cloud_ui()

func _on_cloud_status_changed(_status: String) -> void:
	_update_cloud_ui()

func _open_story() -> void:
	_open_scene(FLOW.STORY_SCENE)

func _open_challenge(level_number: int) -> void:
	if not FLOW.is_challenge_unlocked(level_number, yandex):
		return
	_open_scene(FLOW.challenge_path(level_number))

func _open_scene(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Cannot open game scene: " + path)
		return
	yandex.gameplay_stop()
	get_tree().change_scene_to_file(path)

func _on_platform_suspension_changed(suspended: bool) -> void:
	background_suspended = suspended
	get_tree().paused = suspended
