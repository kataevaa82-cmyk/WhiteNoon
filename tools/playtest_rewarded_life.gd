extends SceneTree

var failures: Array[String] = []
var native_reward_result = null

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var yandex := root.get_node("YandexService")
	yandex.show_rewarded_life(_on_native_reward_result)
	await process_frame
	await process_frame
	if native_reward_result != false:
		_fail("Native fallback granted a rewarded life without an SDK reward")

	var challenge := (load("res://scenes/level_05_millstone.tscn") as PackedScene).instantiate()
	root.add_child(challenge)
	await process_frame
	await process_frame
	challenge._start_level()
	challenge._change_health(-challenge.MAX_HEALTH * 2.0)
	if challenge.state != challenge.RunState.DOWNED or not challenge.end_screen.visible:
		_fail("Challenge death did not open the rewarded-life screen")
	if not challenge.death_reward_button.visible or not challenge.death_reward_button.disabled:
		_fail("Challenge rewarded-life button did not expose the native/Yandex availability state")
	challenge._on_rewarded_life_finished(true)
	if challenge.state != challenge.RunState.PLAYING or challenge.health != challenge.MAX_HEALTH or challenge.end_screen.visible:
		_fail("Confirmed challenge reward did not restore the run")
	challenge.audio.stop_all()
	challenge.queue_free()
	await process_frame
	await process_frame

	var story := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(story)
	await process_frame
	await process_frame
	story._start_game()
	story._on_guardian_hit(story.MAX_HEALTH * 2.0)
	if story.phase != story.Phase.LOST or not story.end_screen.visible:
		_fail("Story death did not open the rewarded-life screen")
	if not story.death_reward_button.visible or not story.death_reward_button.disabled:
		_fail("Story rewarded-life button did not expose the native/Yandex availability state")
	story._on_rewarded_life_finished(true)
	if story.phase != story.Phase.PLAYING or story.health != story.MAX_HEALTH or story.end_screen.visible:
		_fail("Confirmed story reward did not restore the run")
	story.audio.stop_all()
	story.queue_free()
	await process_frame
	await process_frame
	yandex.gameplay_stop()
	await create_timer(0.25).timeout

	if failures.is_empty():
		print("REWARDED LIFE PLAYTEST PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("REWARDED LIFE PLAYTEST FAIL: " + failure)
		quit(1)

func _on_native_reward_result(granted: bool) -> void:
	native_reward_result = granted

func _fail(message: String) -> void:
	failures.append(message)
