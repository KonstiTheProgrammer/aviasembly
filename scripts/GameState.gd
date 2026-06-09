## GameState.gd
## Zentraler Spielstand: Modus (Sandbox/Survival), Geld, freigeschaltete Teile,
## Upgrades, erledigte Missionen. Persistiert nach user://.
class_name GameState
extends Node

const SAVE_PATH := "user://aviassembly_progress.json"

enum GameMode { NONE, SANDBOX, SURVIVAL }

# Im Survival verfügbare Starter-Teile (Rest muss gekauft werden)
const STARTER := [
	"cockpit", "fuselage", "nose", "tailcone", "strut",
	"wing_straight", "h_stab", "v_stab", "prop_engine", "wheel", "wheel_light", "mg",
]
const START_MONEY := 2200            # etwas mehr Startkapital -> frühere Progression spürbar

var mode: int = GameMode.NONE
var money: int = 0
var unlocked: Dictionary = {}        # part_id -> true
var missions_done: Dictionary = {}   # mission_id -> true
var upgrades: Dictionary = {"thrust": 0, "wing": 0, "light": 0}
var flags: Dictionary = {}           # einmalige Merker (z. B. Steuer-Hinweis gesehen)

signal changed()   # Geld/Unlock/Upgrade hat sich geändert


func is_sandbox() -> bool:
	return mode == GameMode.SANDBOX


func start_mode(m: int) -> void:
	mode = m
	if m == GameMode.SANDBOX:
		# alles frei, Geld irrelevant
		unlocked.clear()
		for id in PartCatalog.all().keys():
			unlocked[id] = true
		money = 999999
	else:
		# Survival: nur Starter frei, Startgeld (falls frischer Stand)
		if unlocked.is_empty():
			for id in STARTER:
				unlocked[id] = true
		if money <= 0:
			money = START_MONEY
	save()
	changed.emit()


func is_unlocked(id: String) -> bool:
	if is_sandbox():
		return true
	return unlocked.get(id, false)


func can_afford(c: int) -> bool:
	return is_sandbox() or money >= c


func buy_part(id: String, cost: int) -> bool:
	if is_unlocked(id):
		return true
	if not can_afford(cost):
		return false
	if not is_sandbox():
		money -= cost
	unlocked[id] = true
	save()
	changed.emit()
	return true


func add_money(amount: int) -> void:
	if is_sandbox():
		return
	money += amount
	save()
	changed.emit()


func buy_upgrade(key: String, cost: int, max_lvl: int) -> bool:
	var lvl: int = upgrades.get(key, 0)
	if lvl >= max_lvl or not can_afford(cost):
		return false
	if not is_sandbox():
		money -= cost
	upgrades[key] = lvl + 1
	save()
	changed.emit()
	return true


func thrust_mult() -> float:
	return 1.0 + 0.15 * float(upgrades.get("thrust", 0))


func wing_mult() -> float:
	return 1.0 + 0.30 * float(upgrades.get("wing", 0))


func mass_mult() -> float:
	return 1.0 - 0.08 * float(upgrades.get("light", 0))


func mission_done(id: String) -> bool:
	return missions_done.get(id, false)


func complete_mission(id: String, reward: int) -> int:
	if missions_done.get(id, false):
		return 0
	missions_done[id] = true
	add_money(reward)
	return reward


# Einmalige Merker (persistiert), z. B. ob der Steuer-Hinweis schon gezeigt wurde.
func flag(id: String) -> bool:
	return bool(flags.get(id, false))


func set_flag(id: String, v := true) -> void:
	flags[id] = v
	save()


# --- Persistenz ------------------------------------------------------------
func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"mode": mode, "money": money, "unlocked": unlocked,
		"missions_done": missions_done, "upgrades": upgrades, "flags": flags,
	}))
	f.close()


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	mode = int(data.get("mode", GameMode.NONE))
	money = int(data.get("money", 0))
	unlocked = data.get("unlocked", {})
	missions_done = data.get("missions_done", {})
	flags = data.get("flags", {})
	var up = data.get("upgrades", {})
	for k in ["thrust", "wing", "light"]:
		upgrades[k] = int(up.get(k, 0))
