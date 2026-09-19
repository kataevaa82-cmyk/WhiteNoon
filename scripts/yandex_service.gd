extends Node

signal sdk_initialized
signal language_detected(language: String)
signal platform_suspension_changed(suspended: bool)
signal progress_changed(progress: Dictionary)
signal authorization_changed(authorized: bool)
signal cloud_status_changed(status: String)

const LOCAL_SAVE_PATH := "user://white_noon_progress.json"
const CLOUD_SAVE_KEY := "white_noon_progress"
const FIRST_CHALLENGE := 2
const LAST_CHALLENGE := 21

## ВАЖНО: должно совпадать с техническим именем лидерборда в консоли
## разработчика (Игра → Лидерборды). При несовпадении SDK вернёт ошибку,
## мы её проглотим и запишем предупреждение в консоль — на геймплей это
## не влияет.
const LEADERBOARD_NAME := "whitenoon"

## Очки для лидерборда: больше — лучше, поэтому сортировка по умолчанию
## подходит и не требует инверсии в консоли.
const SCORE_PER_LEVEL := 100
const SCORE_STORY_BONUS := 150
const GRADE_BONUS := {"S": 60, "A": 40, "B": 20, "C": 10}

const DEFAULT_PROGRESS := {
	"version": 1,
	"story_completed": false,
	"story_best_time": 0.0,
	"story_best_grade": "",
	"completed_levels": [],
	"best_times": {},
	"best_grades": {},
	"daily_day": 0,
	"daily_level": 0,
	"daily_done_day": 0,
	"daily_streak": 0,
	"updated_at": 0,
}

var initialized := false
var game_ready_requested := false
var detected_language := "ru"
var player_authorized := false
var cloud_status := "local"
var gameplay_active := false
var progress: Dictionary = DEFAULT_PROGRESS.duplicate(true)
var local_save_path := LOCAL_SAVE_PATH

var _ad_open_callback
var _ad_close_callback
var _reward_granted_callback
var _reward_close_callback
var _sdk_ready_callback
var _sdk_pause_callback
var _sdk_resume_callback
var _visibility_callback
var _player_callback
var _cloud_progress_callback
var _cloud_error_callback
var _save_callback
var _document_hidden := false
var _ad_open := false
var _sdk_paused := false
var _platform_suspended := false
var _gameplay_resume_requested := false
var _master_was_muted := false
var _pending_interstitial_callback := Callable()
var _interstitial_pending := false
var _pending_reward_callback := Callable()
var _reward_pending := false
var _reward_granted := false
var _review_prompt_requested := false
var _shortcut_prompt_requested := false
var _leaderboard_callback
var _shortcut_callback
var _submitted_score := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_local_progress()
	if OS.has_feature("web"):
		_setup_web_sdk()
	else:
		initialized = true
		cloud_status = "local"
		call_deferred("_emit_initial_state")

func _emit_initial_state() -> void:
	sdk_initialized.emit()
	language_detected.emit(detected_language)
	progress_changed.emit(progress.duplicate(true))
	authorization_changed.emit(player_authorized)
	cloud_status_changed.emit(cloud_status)

func _setup_web_sdk() -> void:
	_ad_open_callback = JavaScriptBridge.create_callback(_on_ad_open)
	_ad_close_callback = JavaScriptBridge.create_callback(_on_ad_close)
	_reward_granted_callback = JavaScriptBridge.create_callback(_on_reward_granted)
	_reward_close_callback = JavaScriptBridge.create_callback(_on_reward_close)
	_sdk_ready_callback = JavaScriptBridge.create_callback(_on_sdk_ready)
	_sdk_pause_callback = JavaScriptBridge.create_callback(_on_sdk_pause)
	_sdk_resume_callback = JavaScriptBridge.create_callback(_on_sdk_resume)
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
	_player_callback = JavaScriptBridge.create_callback(_on_player_ready)
	_cloud_progress_callback = JavaScriptBridge.create_callback(_on_cloud_progress)
	_cloud_error_callback = JavaScriptBridge.create_callback(_on_cloud_error)
	_save_callback = JavaScriptBridge.create_callback(_on_cloud_save_result)
	_leaderboard_callback = JavaScriptBridge.create_callback(_on_leaderboard_result)
	_shortcut_callback = JavaScriptBridge.create_callback(_on_shortcut_result)
	var window = JavaScriptBridge.get_interface("window")
	window.whiteNoonAdOpen = _ad_open_callback
	window.whiteNoonAdClose = _ad_close_callback
	window.whiteNoonRewardGranted = _reward_granted_callback
	window.whiteNoonRewardClose = _reward_close_callback
	window.whiteNoonSdkReady = _sdk_ready_callback
	window.whiteNoonSdkPause = _sdk_pause_callback
	window.whiteNoonSdkResume = _sdk_resume_callback
	window.whiteNoonVisibility = _visibility_callback
	window.whiteNoonPlayerReady = _player_callback
	window.whiteNoonCloudProgress = _cloud_progress_callback
	window.whiteNoonCloudError = _cloud_error_callback
	window.whiteNoonSaveResult = _save_callback
	window.whiteNoonLeaderboardResult = _leaderboard_callback
	window.whiteNoonShortcutResult = _shortcut_callback
	cloud_status = "loading"
	cloud_status_changed.emit(cloud_status)
	JavaScriptBridge.eval("""
		(function () {
			window.whiteNoonSendGameReady = function () {
				if (!window.whiteNoonGameReadyRequested || !window.whiteNoonLoaderHidden || !window.ysdk || window.whiteNoonGameReadySent) {
					return false;
				}
				var loadingApi = window.ysdk.features && window.ysdk.features.LoadingAPI;
				if (!loadingApi || typeof loadingApi.ready !== 'function') {
					return false;
				}
				window.whiteNoonGameReadySent = true;
				window.ysdk.features.LoadingAPI.ready();
				return true;
			};
			if (!window.whiteNoonVisibilityInstalled) {
				window.whiteNoonVisibilityInstalled = true;
				document.addEventListener('visibilitychange', function () {
					if (window.whiteNoonVisibility) window.whiteNoonVisibility(document.hidden);
				});
			}
			window.whiteNoonSubmitScore = async function (name, score) {
				try {
					if (!window.ysdk) return;
					var board = window.whiteNoonLeaderboards;
					if (!board) {
						board = await window.ysdk.getLeaderboards();
						window.whiteNoonLeaderboards = board;
					}
					await board.setLeaderboardScore(name, score);
					if (window.whiteNoonLeaderboardResult) window.whiteNoonLeaderboardResult(true);
				} catch (error) {
					// Обычно это неавторизованный игрок или другое имя
					// лидерборда в консоли. На геймплей не влияет.
					console.warn('Yandex leaderboard:', error);
					if (window.whiteNoonLeaderboardResult) window.whiteNoonLeaderboardResult(false);
				}
			};
			window.whiteNoonOfferShortcut = async function () {
				try {
					if (!window.ysdk || !window.ysdk.shortcut) return;
					var can = await window.ysdk.shortcut.canShowPrompt();
					if (!can || !can.canShow) {
						if (window.whiteNoonShortcutResult) window.whiteNoonShortcutResult(false);
						return;
					}
					var result = await window.ysdk.shortcut.showPrompt();
					if (window.whiteNoonShortcutResult) window.whiteNoonShortcutResult(!!(result && result.outcome === 'accepted'));
				} catch (error) {
					console.warn('Yandex shortcut:', error);
					if (window.whiteNoonShortcutResult) window.whiteNoonShortcutResult(false);
				}
			};
			window.whiteNoonLoadPlayer = async function () {
				try {
					if (!window.ysdk) throw new Error('SDK is not initialized');
					window.whiteNoonPlayer = await window.ysdk.getPlayer();
					var authorized = !!window.whiteNoonPlayer.isAuthorized();
					if (window.whiteNoonPlayerReady) window.whiteNoonPlayerReady(authorized);
					var data = await window.whiteNoonPlayer.getData(['white_noon_progress']);
					var saved = data && data.white_noon_progress ? data.white_noon_progress : {};
					if (window.whiteNoonCloudProgress) window.whiteNoonCloudProgress(JSON.stringify(saved));
				} catch (error) {
					console.warn('Yandex Player:', error);
					if (window.whiteNoonCloudError) window.whiteNoonCloudError(String(error));
				}
			};
			var sdkInitializationStarted = false;
			var fallbackSent = false;
			var sendFallback = function (reason) {
				if (fallbackSent || window.ysdk) return;
				fallbackSent = true;
				var lang = (navigator.language || 'ru').split('-')[0];
				if (window.whiteNoonSdkReady) window.whiteNoonSdkReady(lang);
				if (window.whiteNoonCloudError) window.whiteNoonCloudError(String(reason));
			};
			var initializeSdk = async function () {
				if (sdkInitializationStarted || (!window.ysdk && !window.YaGames)) return;
				sdkInitializationStarted = true;
				try {
					if (!window.ysdk) window.ysdk = await YaGames.init();
					var lang = (window.ysdk.environment && window.ysdk.environment.i18n && window.ysdk.environment.i18n.lang) || 'ru';
					window.whiteNoonSdkLanguage = lang;
					if (!window.whiteNoonSdkEventsInstalled) {
						window.whiteNoonSdkEventsInstalled = true;
						window.whiteNoonPauseHandler = function () {
							if (window.whiteNoonSdkPause) window.whiteNoonSdkPause();
						};
						window.whiteNoonResumeHandler = function () {
							if (window.whiteNoonSdkResume) window.whiteNoonSdkResume();
						};
						window.ysdk.on('game_api_pause', window.whiteNoonPauseHandler);
						window.ysdk.on('game_api_resume', window.whiteNoonResumeHandler);
					}
					if (window.whiteNoonSdkReady) window.whiteNoonSdkReady(lang);
					window.whiteNoonSendGameReady();
					window.whiteNoonLoadPlayer();
				} catch (error) {
					sdkInitializationStarted = false;
					console.warn('Yandex SDK:', error);
					sendFallback(error);
				}
			};
			window.addEventListener('white-noon-sdk-loaded', initializeSdk);
			window.addEventListener('white-noon-sdk-failed', function () {
				sendFallback('SDK loader failed');
			}, {once: true});
			if (window.ysdk || window.YaGames) {
				initializeSdk();
			} else if (window.whiteNoonSdkLoadState === 'error') {
				sendFallback('SDK loader failed');
			}
			setTimeout(function () { sendFallback('SDK loader timeout'); }, 10000);
		})();
	""")

func mark_game_ready() -> void:
	if game_ready_requested:
		return
	game_ready_requested = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			window.whiteNoonGameReadyRequested = true;
			if (window.whiteNoonSendGameReady) window.whiteNoonSendGameReady();
		""")

func gameplay_start() -> void:
	if gameplay_active:
		return
	if _platform_suspended:
		_gameplay_resume_requested = true
		return
	_gameplay_resume_requested = false
	gameplay_active = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.ysdk && window.ysdk.features && window.ysdk.features.GameplayAPI){window.ysdk.features.GameplayAPI.start();}")

func gameplay_stop() -> void:
	_gameplay_resume_requested = false
	if not gameplay_active:
		return
	gameplay_active = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.ysdk && window.ysdk.features && window.ysdk.features.GameplayAPI){window.ysdk.features.GameplayAPI.stop();}")

func show_interstitial(after_closed := Callable()) -> void:
	if _interstitial_pending:
		if after_closed.is_valid():
			after_closed.call_deferred(false)
		return
	_interstitial_pending = true
	_pending_interstitial_callback = after_closed
	gameplay_stop()
	if not OS.has_feature("web") or not initialized:
		call_deferred("_complete_interstitial", false)
		return
	JavaScriptBridge.eval("""
		if (window.ysdk && window.ysdk.adv) {
			window.ysdk.adv.showFullscreenAdv({callbacks: {
				onOpen: function () {
					if (window.whiteNoonAdOpen) window.whiteNoonAdOpen();
				},
				onClose: function (wasShown) {
					if (window.whiteNoonAdClose) window.whiteNoonAdClose(!!wasShown);
				},
				onError: function (error) {
					console.warn('Yandex fullscreen ad:', error);
					if (window.whiteNoonAdClose) window.whiteNoonAdClose(false);
				}
			}});
		} else if (window.whiteNoonAdClose) {
			window.whiteNoonAdClose(false);
		}
	""")

## Rewarded video is always opt-in. The caller receives true only after the SDK's
## onRewarded callback, never merely because the ad window opened or closed.
func show_rewarded_life(after_closed := Callable()) -> void:
	if _reward_pending:
		if after_closed.is_valid():
			after_closed.call_deferred(false)
		return
	_reward_pending = true
	_reward_granted = false
	_pending_reward_callback = after_closed
	gameplay_stop()
	if not OS.has_feature("web") or not initialized:
		call_deferred("_complete_rewarded", false)
		return
	JavaScriptBridge.eval("""
		(function () {
			if (!window.ysdk || !window.ysdk.adv) {
				if (window.whiteNoonRewardClose) window.whiteNoonRewardClose(false);
				return;
			}
			var finished = false;
			var finish = function (wasShown) {
				if (finished) return;
				finished = true;
				if (window.whiteNoonRewardClose) window.whiteNoonRewardClose(!!wasShown);
			};
			window.ysdk.adv.showRewardedVideo({callbacks: {
				onOpen: function () {
					if (window.whiteNoonAdOpen) window.whiteNoonAdOpen();
				},
				onRewarded: function () {
					if (window.whiteNoonRewardGranted) window.whiteNoonRewardGranted();
				},
				onClose: function (wasShown) {
					finish(wasShown);
				},
				onError: function (error) {
					console.warn('Yandex rewarded ad:', error);
					finish(false);
				}
			}});
		})();
	""")

func open_auth_dialog() -> void:
	if not OS.has_feature("web") or not initialized or player_authorized:
		return
	cloud_status = "loading"
	cloud_status_changed.emit(cloud_status)
	JavaScriptBridge.eval("""
		if (window.ysdk && window.ysdk.auth) {
			window.ysdk.auth.openAuthDialog()
				.then(function () { return window.whiteNoonLoadPlayer(); })
				.catch(function (error) {
					console.warn('Yandex auth:', error);
					if (window.whiteNoonCloudError) window.whiteNoonCloudError(String(error));
				});
		}
	""")

func get_ui_language(language := "") -> String:
	var locale := String(language if not String(language).is_empty() else detected_language).to_lower().replace("_", "-")
	var code := locale.get_slice("-", 0)
	return "ru" if code in ["ru", "be", "kk", "uk", "uz"] else "en"

func request_review_if_available() -> void:
	if _review_prompt_requested or not OS.has_feature("web") or not initialized or not player_authorized:
		return
	_review_prompt_requested = true
	JavaScriptBridge.eval("""
		if (window.ysdk && window.ysdk.feedback) {
			window.ysdk.feedback.canReview()
				.then(function (result) {
					if (result && result.value) return window.ysdk.feedback.requestReview();
				})
				.catch(function (error) { console.warn('Yandex review:', error); });
		}
	""")

## Общий счёт игрока: чем больше, тем лучше. Ровно его мы и кладём в
## лидерборд, поэтому инвертировать сортировку в консоли не нужно.
func get_total_score() -> int:
	var score := 0
	if bool(progress.get("story_completed", false)):
		score += SCORE_STORY_BONUS + int(GRADE_BONUS.get(String(progress.get("story_best_grade", "")), 0))
	for level_number in progress.completed_levels:
		score += SCORE_PER_LEVEL + int(GRADE_BONUS.get(get_level_grade(int(level_number)), 0))
	return score

func submit_score_if_possible() -> void:
	if not OS.has_feature("web") or not initialized or not player_authorized:
		return
	var score := get_total_score()
	if score <= 0 or score == _submitted_score:
		return
	_submitted_score = score
	JavaScriptBridge.eval("if (window.whiteNoonSubmitScore) window.whiteNoonSubmitScore('%s', %d);" % [LEADERBOARD_NAME, score])

## Предлагаем ярлык на домашний экран один раз за сессию и только на приятной
## ноте — после победы, а не на входе в игру.
func offer_shortcut_if_available() -> void:
	if _shortcut_prompt_requested or not OS.has_feature("web") or not initialized:
		return
	_shortcut_prompt_requested = true
	JavaScriptBridge.eval("if (window.whiteNoonOfferShortcut) window.whiteNoonOfferShortcut();")

## Номер текущих суток в UTC: у всех игроков «испытание дня» совпадает.
func current_day() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)

## Испытание дня фиксируется в прогрессе, чтобы выбор не «уехал» после того,
## как игрок откроет новый уровень прямо в этой же сессии.
func pin_daily_challenge(level_number: int) -> int:
	var today := current_day()
	if int(progress.get("daily_day", 0)) == today and int(progress.get("daily_level", 0)) > 0:
		return int(progress.daily_level)
	if level_number <= 0:
		return 0
	progress.daily_day = today
	progress.daily_level = level_number
	_commit_progress()
	return level_number

func get_daily_level() -> int:
	return int(progress.daily_level) if int(progress.get("daily_day", 0)) == current_day() else 0

func is_daily_done() -> bool:
	return int(progress.get("daily_done_day", 0)) == current_day()

## Серия обрывается, если игрок пропустил вчера и сегодня ещё не играл.
func get_daily_streak() -> int:
	var last_done := int(progress.get("daily_done_day", 0))
	return int(progress.get("daily_streak", 0)) if last_done >= current_day() - 1 else 0

func _register_daily_completion(level_number: int) -> void:
	var today := current_day()
	var previous := int(progress.get("daily_done_day", 0))
	if get_daily_level() != level_number or previous == today:
		return
	progress.daily_streak = int(progress.get("daily_streak", 0)) + 1 if previous == today - 1 else 1
	progress.daily_done_day = today

func record_story_result(elapsed: float, grade: String) -> void:
	progress.story_completed = true
	progress.story_best_time = _best_time(float(progress.get("story_best_time", 0.0)), elapsed)
	progress.story_best_grade = _best_grade(String(progress.get("story_best_grade", "")), grade)
	_commit_progress()
	submit_score_if_possible()
	# Финал сюжета — лучший момент и для отзыва, и для ярлыка на экране.
	call_deferred("request_review_if_available")
	call_deferred("offer_shortcut_if_available")

func record_level_result(level_number: int, elapsed: float, grade: String) -> void:
	if level_number < FIRST_CHALLENGE or level_number > LAST_CHALLENGE:
		return
	var completed: Array = progress.completed_levels
	if not completed.has(level_number):
		completed.append(level_number)
		completed.sort()
	progress.completed_levels = completed
	var key := str(level_number)
	var times: Dictionary = progress.best_times
	times[key] = _best_time(float(times.get(key, 0.0)), elapsed)
	progress.best_times = times
	var grades: Dictionary = progress.best_grades
	grades[key] = _best_grade(String(grades.get(key, "")), grade)
	progress.best_grades = grades
	_register_daily_completion(level_number)
	_commit_progress()
	submit_score_if_possible()
	if get_completed_challenge_count() >= 3:
		call_deferred("request_review_if_available")

func is_level_completed(level_number: int) -> bool:
	return progress.completed_levels.has(level_number)

func get_level_grade(level_number: int) -> String:
	return String(progress.best_grades.get(str(level_number), ""))

func get_completed_challenge_count() -> int:
	return progress.completed_levels.size()

func get_progress() -> Dictionary:
	return progress.duplicate(true)

func _commit_progress() -> void:
	progress.updated_at = int(Time.get_unix_time_from_system())
	_save_local_progress()
	progress_changed.emit(progress.duplicate(true))
	_save_cloud_progress()

func _load_local_progress() -> void:
	if OS.has_feature("web"):
		var stored = JavaScriptBridge.eval("""
			(function () {
				try { return window.localStorage.getItem('white_noon_progress') || ''; }
				catch (error) { console.warn('Local progress load:', error); return ''; }
			})()
		""")
		var parsed_web = JSON.parse_string(String(stored)) if stored != null and String(stored) != "" else null
		progress = _merge_progress(DEFAULT_PROGRESS.duplicate(true), parsed_web if parsed_web is Dictionary else {})
		return
	if not FileAccess.file_exists(local_save_path):
		progress = DEFAULT_PROGRESS.duplicate(true)
		return
	var file := FileAccess.open(local_save_path, FileAccess.READ)
	if file == null:
		progress = DEFAULT_PROGRESS.duplicate(true)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	progress = _merge_progress(DEFAULT_PROGRESS.duplicate(true), parsed if parsed is Dictionary else {})

func _save_local_progress() -> void:
	if OS.has_feature("web"):
		var payload := JSON.stringify(progress)
		JavaScriptBridge.eval("""
			(function () {
				try {
					window.localStorage.setItem('white_noon_progress', JSON.stringify(%s));
					return true;
				} catch (error) {
					console.warn('Local progress save:', error);
					return false;
				}
			})()
		""" % payload)
		return
	var file := FileAccess.open(local_save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write local progress: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(progress))

func _save_cloud_progress() -> void:
	if not OS.has_feature("web") or not initialized:
		return
	cloud_status = "saving"
	cloud_status_changed.emit(cloud_status)
	var payload := JSON.stringify(progress)
	JavaScriptBridge.eval("""
		(function () {
			var payload = %s;
			if (!window.whiteNoonPlayer) {
				if (window.whiteNoonSaveResult) window.whiteNoonSaveResult(false);
				return;
			}
			window.whiteNoonPlayer.setData({white_noon_progress: payload}, true)
				.then(function () {
					if (window.whiteNoonSaveResult) window.whiteNoonSaveResult(true);
				})
				.catch(function (error) {
					console.warn('Yandex save:', error);
					if (window.whiteNoonSaveResult) window.whiteNoonSaveResult(false);
				});
		})();
	""" % payload)

func _merge_progress(base: Dictionary, incoming: Dictionary) -> Dictionary:
	var merged := DEFAULT_PROGRESS.duplicate(true)
	for source in [base, incoming]:
		if not source is Dictionary:
			continue
		merged.story_completed = bool(merged.story_completed) or bool(source.get("story_completed", false))
		merged.story_best_time = _best_time(float(merged.story_best_time), float(source.get("story_best_time", 0.0)))
		merged.story_best_grade = _best_grade(String(merged.story_best_grade), String(source.get("story_best_grade", "")))
		var completed: Array = merged.completed_levels
		var source_completed = source.get("completed_levels", [])
		if source_completed is Array:
			for raw_level in source_completed:
				var level_number := int(raw_level)
				if level_number >= FIRST_CHALLENGE and level_number <= LAST_CHALLENGE and not completed.has(level_number):
					completed.append(level_number)
		completed.sort()
		merged.completed_levels = completed
		var source_times = source.get("best_times", {})
		if source_times is Dictionary:
			for raw_key in source_times:
				var key := str(raw_key)
				var level_number := int(key)
				if level_number >= FIRST_CHALLENGE and level_number <= LAST_CHALLENGE:
					merged.best_times[key] = _best_time(float(merged.best_times.get(key, 0.0)), float(source_times[raw_key]))
		var source_grades = source.get("best_grades", {})
		if source_grades is Dictionary:
			for raw_key in source_grades:
				var key := str(raw_key)
				var level_number := int(key)
				if level_number >= FIRST_CHALLENGE and level_number <= LAST_CHALLENGE:
					merged.best_grades[key] = _best_grade(String(merged.best_grades.get(key, "")), String(source_grades[raw_key]))
		merged.daily_streak = maxi(int(merged.daily_streak), int(source.get("daily_streak", 0)))
		merged.daily_done_day = maxi(int(merged.daily_done_day), int(source.get("daily_done_day", 0)))
		# Испытание дня берём у более свежей записи, иначе два устройства
		# будут спорить, какой уровень сегодняшний.
		if int(source.get("daily_day", 0)) >= int(merged.daily_day):
			merged.daily_day = int(source.get("daily_day", 0))
			merged.daily_level = int(source.get("daily_level", 0))
		merged.updated_at = maxi(int(merged.updated_at), int(source.get("updated_at", 0)))
	return merged

func _best_time(current: float, candidate: float) -> float:
	if candidate <= 0.0:
		return current
	if current <= 0.0:
		return candidate
	return minf(current, candidate)

func _best_grade(current: String, candidate: String) -> String:
	var rank := {"": 0, "C": 1, "B": 2, "A": 3, "S": 4}
	return candidate if int(rank.get(candidate, 0)) > int(rank.get(current, 0)) else current

func _on_ad_open(_args: Array) -> void:
	_ad_open = true
	_update_platform_suspension()

func _on_ad_close(args: Array) -> void:
	_ad_open = false
	_update_platform_suspension()
	var was_shown := not args.is_empty() and bool(args[0])
	_complete_interstitial(was_shown)

func _on_reward_granted(_args: Array) -> void:
	if _reward_pending:
		_reward_granted = true

func _on_reward_close(_args: Array) -> void:
	_ad_open = false
	_update_platform_suspension()
	_complete_rewarded(_reward_granted)

func _complete_rewarded(granted: bool) -> void:
	if not _reward_pending:
		return
	_reward_pending = false
	_reward_granted = false
	var callback := _pending_reward_callback
	_pending_reward_callback = Callable()
	if callback.is_valid():
		callback.call(granted)

func _complete_interstitial(was_shown: bool) -> void:
	if not _interstitial_pending:
		return
	_interstitial_pending = false
	var callback := _pending_interstitial_callback
	_pending_interstitial_callback = Callable()
	if callback.is_valid():
		callback.call(was_shown)

func _on_sdk_ready(args: Array) -> void:
	initialized = OS.has_feature("web") and JavaScriptBridge.eval("!!window.ysdk")
	var language := "ru"
	if not args.is_empty():
		language = String(args[0]).to_lower()
	detected_language = language
	sdk_initialized.emit()
	language_detected.emit(detected_language)

func _on_player_ready(args: Array) -> void:
	player_authorized = not args.is_empty() and bool(args[0])
	authorization_changed.emit(player_authorized)
	if player_authorized:
		# Игрок мог набрать очки гостем: отправляем накопленное сразу.
		call_deferred("submit_score_if_possible")

func _on_cloud_progress(args: Array) -> void:
	var incoming: Dictionary = {}
	if not args.is_empty():
		var parsed = JSON.parse_string(String(args[0]))
		if parsed is Dictionary:
			incoming = parsed
	progress = _merge_progress(progress, incoming)
	_save_local_progress()
	progress_changed.emit(progress.duplicate(true))
	_save_cloud_progress()

func _on_cloud_error(_args: Array) -> void:
	cloud_status = "error"
	cloud_status_changed.emit(cloud_status)

func _on_cloud_save_result(args: Array) -> void:
	cloud_status = "synced" if not args.is_empty() and bool(args[0]) else "error"
	cloud_status_changed.emit(cloud_status)

func _on_leaderboard_result(args: Array) -> void:
	if not (not args.is_empty() and bool(args[0])):
		# Разрешаем повторную попытку после следующей победы: игрок мог
		# авторизоваться уже после первой отправки.
		_submitted_score = -1

func _on_shortcut_result(_args: Array) -> void:
	pass

func _on_sdk_pause(_args: Array) -> void:
	_sdk_paused = true
	# The platform stops GameplayAPI markup together with this event. Keep the
	# local guard in sync so the active scene can send start() after resume.
	gameplay_active = false
	_update_platform_suspension()

func _on_sdk_resume(_args: Array) -> void:
	_sdk_paused = false
	_update_platform_suspension()

func _on_visibility_changed(args: Array) -> void:
	_document_hidden = not args.is_empty() and bool(args[0])
	_update_platform_suspension()

func _update_platform_suspension() -> void:
	var suspended := _document_hidden or _ad_open or _sdk_paused
	if suspended == _platform_suspended:
		return
	_platform_suspended = suspended
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		if suspended:
			_master_was_muted = AudioServer.is_bus_mute(master_bus)
			AudioServer.set_bus_mute(master_bus, true)
		else:
			AudioServer.set_bus_mute(master_bus, _master_was_muted)
	platform_suspension_changed.emit(suspended)
	if not suspended and _gameplay_resume_requested:
		call_deferred("gameplay_start")
