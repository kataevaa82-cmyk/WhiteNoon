class_name GameFlow
extends RefCounted

const MENU_SCENE := "res://scenes/game_menu.tscn"
const STORY_SCENE := "res://scenes/main.tscn"
const FIRST_CHALLENGE := 2
const LAST_CHALLENGE := 21

const CHALLENGE_TITLES := {
	2: "КУРГАННАЯ ТРОПА",
	3: "ПЕПЕЛЬНЫЙ ПОСАД",
	4: "ЧЁРНОЕ СОЛНЦЕ",
	5: "ТРЕСНУВШИЙ ЖЕРНОВ",
	6: "ДЫМНЫЙ ОВРАГ",
	7: "МЁРТВАЯ ПАСЕКА",
	8: "КРАСНЫЙ БРОД",
	9: "ТИХИЙ ПЕРЕВАЛ",
	10: "ДВЕНАДЦАТЬ КОСТРОВ",
	11: "КОЛОДЕЦ БЕЗ ДНА",
	12: "СОРОЧИЙ КРУГ",
	13: "ПОЛЕ КУКОЛ",
	14: "БЕЗЗВОННАЯ БАШНЯ",
	15: "ПЕПЕЛЬНЫЙ ХОРОВОД",
	16: "СЛЕПОЙ ЛЕС",
	17: "СОЛНЕЧНЫЙ ДОЛГ",
	18: "НОЧЬ БЕЗ ТЕНИ",
	19: "ПОСЛЕДНЯЯ ПЕЧАТЬ",
	20: "ЗЕРКАЛО ПОЛДНЯ",
	21: "ЗА ЧЁРНЫМИ ВОРОТАМИ",
}

const CHALLENGE_TITLES_EN := {
	2: "BURIAL MOUND PATH",
	3: "ASHEN VILLAGE",
	4: "BLACK SUN",
	5: "CRACKED MILLSTONE",
	6: "SMOKE RAVINE",
	7: "DEAD APIARY",
	8: "RED FORD",
	9: "SILENT PASS",
	10: "TWELVE FIRES",
	11: "BOTTOMLESS WELL",
	12: "MAGPIE CIRCLE",
	13: "FIELD OF DOLLS",
	14: "SILENT TOWER",
	15: "ASHEN ROUND DANCE",
	16: "BLIND FOREST",
	17: "SUN DEBT",
	18: "SHADOWLESS NIGHT",
	19: "FINAL SEAL",
	20: "NOON MIRROR",
	21: "BEYOND BLACK GATES",
}

const CHALLENGE_FILES := {
	2: "level_02_kurgans.tscn",
	3: "level_03_fires.tscn",
	4: "level_04_black_sun.tscn",
	5: "level_05_millstone.tscn",
	6: "level_06_ravine.tscn",
	7: "level_07_apiary.tscn",
	8: "level_08_ford.tscn",
	9: "level_09_pass.tscn",
	10: "level_10_fires.tscn",
	11: "level_11_well.tscn",
	12: "level_12_circle.tscn",
	13: "level_13_dolls.tscn",
	14: "level_14_chapel.tscn",
	15: "level_15_round.tscn",
	16: "level_16_forest.tscn",
	17: "level_17_debt.tscn",
	18: "level_18_night.tscn",
	19: "level_19_rite.tscn",
	20: "level_20_mirror.tscn",
	21: "level_21_gates.tscn",
}

static func challenge_path(level_number: int) -> String:
	var file := String(CHALLENGE_FILES.get(level_number, ""))
	return "res://scenes/" + file if not file.is_empty() else ""

static func challenge_title(level_number: int, language := "ru") -> String:
	var titles := CHALLENGE_TITLES if language == "ru" else CHALLENGE_TITLES_EN
	return String(titles.get(level_number, "ИСПЫТАНИЕ" if language == "ru" else "CHALLENGE"))

## Испытания открываются по цепочке: сначала сюжет, затем каждый следующий
## уровень после победы на предыдущем.
static func is_challenge_unlocked(level_number: int, service: Node) -> bool:
	if service == null:
		return true
	if service.is_level_completed(level_number):
		# Сохранения прежних версий открывали все испытания сразу, и там
		# уровень мог быть пройден без предыдущего. Отбирать его нельзя.
		return true
	if level_number <= FIRST_CHALLENGE:
		return bool(service.progress.get("story_completed", false))
	return service.is_level_completed(level_number - 1)

static func has_next_challenge(level_number: int) -> bool:
	return level_number >= FIRST_CHALLENGE and level_number < LAST_CHALLENGE

static func next_challenge_path(level_number: int) -> String:
	return challenge_path(level_number + 1) if has_next_challenge(level_number) else ""
