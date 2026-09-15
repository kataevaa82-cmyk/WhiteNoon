extends SceneTree

var failures: Array[String] = []
var interstitial_finished := false
var suspension_events: Array[bool] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := root.get_node_or_null("YandexService")
	if service == null:
		_fail("YandexService autoload is missing")
		_finish()
		return
	var original_progress: Dictionary = service.progress.duplicate(true)
	var original_save_path: String = service.local_save_path
	service.local_save_path = "res://build/platform_test_progress.json"
	service.record_level_result(21, 84.0, "A")
	service.record_level_result(21, 72.0, "S")
	if not service.is_level_completed(21):
		_fail("Local challenge progress was not recorded")
	if service.get_level_grade(21) != "S":
		_fail("Best challenge grade was not retained")
	if not FileAccess.file_exists(service.local_save_path):
		_fail("Local progress file was not created")
	var merged: Dictionary = service._merge_progress(
		{"completed_levels": [2], "best_times": {"2": 90.0}, "best_grades": {"2": "B"}},
		{"completed_levels": [3], "best_times": {"2": 70.0, "3": 80.0}, "best_grades": {"2": "A", "3": "S"}}
	)
	if merged.completed_levels != [2, 3] or float(merged.best_times["2"]) != 70.0 or String(merged.best_grades["2"]) != "A":
		_fail("Local/cloud progress merge is not monotonic")
	service.progress = original_progress
	service._save_local_progress()
	if FileAccess.file_exists(service.local_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(service.local_save_path))
	service.local_save_path = original_save_path

	service.platform_suspension_changed.connect(_on_suspension)
	service.gameplay_start()
	service._on_sdk_pause([])
	await process_frame
	if service.gameplay_active:
		_fail("SDK pause did not reset GameplayAPI state")
	service._on_sdk_resume([])
	await process_frame
	if suspension_events != [true, false]:
		_fail("SDK pause/resume events were not propagated")

	service.show_interstitial(_on_interstitial_finished)
	for _frame in range(3):
		await process_frame
	if not interstitial_finished:
		_fail("Interstitial fallback did not resume the requested action")

	var touch_script := load("res://scripts/touch_controls.gd") as Script
	var touch_controls: Object = touch_script.new()
	if not touch_controls.has_signal("pause_pressed"):
		_fail("Touch controls do not expose a pause gesture")
	touch_controls.free()
	_finish()

func _on_suspension(suspended: bool) -> void:
	suspension_events.append(suspended)

func _on_interstitial_finished(_was_shown: bool) -> void:
	interstitial_finished = true

func _finish() -> void:
	if failures.is_empty():
		print("PLATFORM PLAYTEST PASS: save merge, SDK pause, ad fallback and touch pause verified")
		quit(0)
	else:
		for failure in failures:
			push_error("PLATFORM PLAYTEST FAIL: " + failure)
		quit(1)

func _fail(message: String) -> void:
	failures.append(message)
