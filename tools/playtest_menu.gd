extends SceneTree

const FLOW := preload("res://scripts/game_flow.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if ProjectSettings.get_setting("application/run/main_scene") != FLOW.MENU_SCENE:
		_fail("The project does not start at the game menu")
	if not ResourceLoader.exists(FLOW.STORY_SCENE):
		_fail("The story scene route is missing")
	for level_number in range(FLOW.FIRST_CHALLENGE, FLOW.LAST_CHALLENGE + 1):
		var path := FLOW.challenge_path(level_number)
		if path.is_empty() or not ResourceLoader.exists(path):
			_fail("Missing route for challenge %d" % level_number)
	var packed := load(FLOW.MENU_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load the game menu")
	else:
		var menu := packed.instantiate()
		root.add_child(menu)
		await process_frame
		await process_frame
		var grid := menu.get_node_or_null("UI/Layout/ChallengeScroll/ChallengeGrid") as GridContainer
		if grid == null:
			_fail("The challenge grid is missing")
		elif grid.get_child_count() != 20:
			_fail("Expected 20 challenge buttons, got %d" % grid.get_child_count())
		else:
			for index in range(grid.get_child_count()):
				var button := grid.get_child(index) as Button
				var expected_level := FLOW.FIRST_CHALLENGE + index
				if button == null or int(button.get_meta("level_number", 0)) != expected_level:
					_fail("Challenge button order is broken at index %d" % index)
		var yandex := root.get_node("YandexService")
		_check_progression(menu, grid, yandex)
		yandex._on_sdk_ready(["en"])
		await process_frame
		if menu.get_node("UI/Layout/Title").text != "WHITE NOON":
			_fail("The menu did not apply the platform language")
		yandex._on_sdk_ready(["ru"])
		await process_frame
		menu.queue_free()
		await process_frame
	if FLOW.next_challenge_path(20) != FLOW.challenge_path(21):
		_fail("Level 20 does not lead to level 21")
	if FLOW.has_next_challenge(21) or not FLOW.next_challenge_path(21).is_empty():
		_fail("Level 21 is not marked as the final challenge")
	if failures.is_empty():
		print("MENU PLAYTEST PASS: story route, ad transition and the level chain verified")
		quit(0)
	else:
		for failure in failures:
			push_error("MENU PLAYTEST FAIL: " + failure)
		quit(1)

## Уровни должны открываться цепочкой: сюжет → 2 → 3 → … Прогресс здесь
## меняем только в памяти, чтобы не записать тестовые данные в сохранение.
func _check_progression(menu: Node, grid: GridContainer, yandex: Node) -> void:
	var story_completed: bool = bool(yandex.progress.get("story_completed", false))
	var completed_levels: Array = (yandex.progress.get("completed_levels", []) as Array).duplicate()

	yandex.progress["story_completed"] = false
	yandex.progress["completed_levels"] = []
	menu._update_challenge_labels()
	if not _button_for(grid, FLOW.FIRST_CHALLENGE).disabled:
		_fail("The first challenge is open before the story is finished")
	if not _button_for(grid, FLOW.FIRST_CHALLENGE + 1).disabled:
		_fail("Challenge %d is open before its predecessor" % (FLOW.FIRST_CHALLENGE + 1))

	yandex.progress["story_completed"] = true
	menu._update_challenge_labels()
	if _button_for(grid, FLOW.FIRST_CHALLENGE).disabled:
		_fail("Finishing the story did not unlock the first challenge")
	if not _button_for(grid, FLOW.FIRST_CHALLENGE + 1).disabled:
		_fail("Challenge %d unlocked too early" % (FLOW.FIRST_CHALLENGE + 1))

	yandex.progress["completed_levels"] = [FLOW.FIRST_CHALLENGE]
	menu._update_challenge_labels()
	if _button_for(grid, FLOW.FIRST_CHALLENGE + 1).disabled:
		_fail("Completing challenge %d did not unlock the next one" % FLOW.FIRST_CHALLENGE)
	if not _button_for(grid, FLOW.LAST_CHALLENGE).disabled:
		_fail("The final challenge is open without the whole chain")

	# Сохранение прежних версий: уровень пройден, а предыдущий — нет.
	yandex.progress["story_completed"] = false
	yandex.progress["completed_levels"] = [FLOW.FIRST_CHALLENGE + 3]
	menu._update_challenge_labels()
	if _button_for(grid, FLOW.FIRST_CHALLENGE + 3).disabled:
		_fail("An already completed challenge was locked back")

	# Реклама на переходе между уровнями обязательна для площадки.
	var level_source := FileAccess.get_file_as_string("res://scripts/challenge_level.gd")
	if not level_source.contains("func _open_next_level"):
		_fail("The next-level transition is missing")
	elif not level_source.split("func _open_next_level")[1].split("func ")[0].contains("show_interstitial"):
		_fail("The next-level transition does not show an interstitial ad")
	var story_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	if not story_source.contains("func _open_first_challenge"):
		_fail("The story does not lead into the first challenge")
	elif not story_source.split("func _open_first_challenge")[1].split("func ")[0].contains("show_interstitial"):
		_fail("The story transition does not show an interstitial ad")

	yandex.progress["story_completed"] = story_completed
	yandex.progress["completed_levels"] = completed_levels
	menu._update_challenge_labels()

func _button_for(grid: GridContainer, level_number: int) -> Button:
	for child in grid.get_children():
		if int(child.get_meta("level_number", 0)) == level_number:
			return child as Button
	_fail("No menu button for level %d" % level_number)
	return Button.new()

func _fail(message: String) -> void:
	failures.append(message)
