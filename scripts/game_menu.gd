extends Node

const FLOW := preload("res://scripts/game_flow.gd")

@onready var yandex: Node = get_node("/root/YandexService")
@onready var background_material: ShaderMaterial = $UI/Background.material as ShaderMaterial
@onready var title: Label = $UI/Layout/Title
@onready var subtitle: Label = $UI/Layout/Subtitle
@onready var story_button: Button = $UI/Layout/Story
@onready var progress_label: Label = $UI/Layout/AccountRow/Progress
@onready var cloud_button: Button = $UI/Layout/AccountRow/Cloud
@onready var music_toggle: Button = $UI/Layout/AccountRow/MusicToggle
@onready var menu_music: AudioStreamPlayer = $MenuMusic
@onready var challenge_heading: Label = $UI/Layout/ChallengeHeading
@onready var challenge_grid: GridContainer = $UI/Layout/ChallengeScroll/ChallengeGrid
@onready var footer: Label = $UI/Layout/Footer

var current_language := "ru"
var music_enabled := true
var menu_music_started := false
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
	music_toggle.pressed.connect(_toggle_music)
	_style_menu_button(story_button, true)
	_style_menu_button(cloud_button, false)
	_style_menu_button(music_toggle, false)
	yandex.language_detected.connect(_apply_language)
	yandex.platform_suspension_changed.connect(_on_platform_suspension_changed)
	yandex.progress_changed.connect(_on_progress_changed)
	yandex.authorization_changed.connect(_on_authorization_changed)
	yandex.cloud_status_changed.connect(_on_cloud_status_changed)
	_build_challenge_buttons()
	_apply_language(String(yandex.detected_language))
	_update_progress_ui()
	_update_cloud_ui()
	_update_music_ui()
	yandex.gameplay_stop()
	yandex.mark_game_ready()
	if not OS.has_feature("web"):
		_start_menu_music()

func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") or menu_music_started or not music_enabled:
		return
	var user_activated := false
	if event is InputEventKey:
		user_activated = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		user_activated = event.pressed
	elif event is InputEventScreenTouch:
		user_activated = event.pressed
	if user_activated:
		_start_menu_music()

func _process(delta: float) -> void:
	if background_suspended or not is_instance_valid(background_material):
		return
	background_clock += delta
	background_material.set_shader_parameter("motion_value", background_clock)

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
	_update_music_ui()

func _toggle_music() -> void:
	music_enabled = not music_enabled
	if music_enabled:
		_start_menu_music()
	else:
		menu_music_started = false
		menu_music.stop()
	_update_music_ui()

func _start_menu_music() -> void:
	menu_music_started = true
	if not menu_music.playing:
		menu_music.play()

func _update_music_ui() -> void:
	if not is_instance_valid(music_toggle):
		return
	music_toggle.text = ("МУЗЫКА: ВКЛ" if music_enabled else "МУЗЫКА: ВЫКЛ") if current_language == "ru" else ("MUSIC: ON" if music_enabled else "MUSIC: OFF")

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
