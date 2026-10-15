extends Node

signal structure_changed
signal message_posted(text: String)

const TICK := 0.1
const MAX_TICKS_PER_FRAME := 50
const BASE_POP_CAP := 5
const STARTING_POPULATION := 3
const STARTING_FOOD := 20.0
const FOOD_PER_PERSON := 0.25
const GROW_TIME := 10.0
const STARVE_TIME := 4.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0
const OFFLINE_CHUNK := 60.0

var amounts: Dictionary = {}
var unlocked: Dictionary = {}
var jobs: Dictionary = {}
var buildings: Dictionary = {}
var upgrades: Dictionary = {}
var techs: Dictionary = {}
var population: int = STARTING_POPULATION
var starving := false
var rates: Dictionary = {}
var spoil_rates: Dictionary = {}

var _grow_progress := 0.0
var _starve_progress := 0.0
var _accum := 0.0
var _mods: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	amounts.clear()
	unlocked.clear()
	jobs.clear()
	buildings.clear()
	upgrades.clear()
	techs.clear()
	rates.clear()
	spoil_rates.clear()
	for r in GameData.RESOURCES:
		amounts[r["id"]] = 0.0
	for id in GameData.STARTING_RESOURCES:
		unlocked[id] = true
	amounts["food"] = STARTING_FOOD
	population = STARTING_POPULATION
	starving = false
	_grow_progress = 0.0
	_starve_progress = 0.0
	rebuild_modifiers()
	structure_changed.emit()


func _process(delta: float) -> void:
	_accum += delta
	var steps := 0
	while _accum >= TICK and steps < MAX_TICKS_PER_FRAME:
		simulate(TICK, false)
		_accum -= TICK
		steps += 1
	if steps == MAX_TICKS_PER_FRAME:
		_accum = 0.0


# offline = true skips spoilage, starvation and growth, so idle time is never punished.
func simulate(dt: float, offline: bool) -> void:
	var before := amounts.duplicate()
	_run_jobs(dt)
	_feed_population(dt, offline)
	if offline:
		return
	_apply_spoilage(dt)
	_update_population(dt)
	for id in amounts:
		var per_sec: float = (amounts[id] - before[id]) / dt
		rates[id] = lerpf(rates.get(id, 0.0), per_sec, 0.3)


func _run_jobs(dt: float) -> void:
	for job in GameData.JOBS:
		var workers: int = jobs.get(job["id"], 0)
		if workers <= 0:
			continue
		var consumes: Dictionary = job.get("consumes", {})
		var ratio := 1.0
		for res in consumes:
			var need: float = consumes[res] * workers * dt
			ratio = minf(ratio, amounts[res] / need)
		if ratio <= 0.0:
			continue
		for res in consumes:
			amounts[res] = maxf(0.0, amounts[res] - consumes[res] * workers * dt * ratio)
		var m := job_multiplier(job["id"])
		var produces: Dictionary = job["produces"]
		for res in produces:
			amounts[res] += produces[res] * workers * dt * ratio * m


func _feed_population(dt: float, offline: bool) -> void:
	var need := population * food_per_second_per_person() * dt
	if amounts["food"] >= need:
		amounts["food"] -= need
		starving = false
	else:
		amounts["food"] = 0.0
		starving = not offline


func _apply_spoilage(dt: float) -> void:
	for r in GameData.RESOURCES:
		var base: float = r.get("spoil", 0.0)
		if base <= 0.0:
			continue
		var id: String = r["id"]
		var lost: float = amounts[id] * base * mult("spoil:" + id)
		spoil_rates[id] = lost
		amounts[id] = maxf(0.0, amounts[id] - lost * dt)


func _update_population(dt: float) -> void:
	if starving:
		_grow_progress = 0.0
		_starve_progress += dt / STARVE_TIME
		if _starve_progress >= 1.0:
			_starve_progress = 0.0
			_lose_person()
		return
	_starve_progress = 0.0
	if population <= 0 or population >= pop_cap() or amounts["food"] <= 0.0:
		_grow_progress = 0.0
		return
	# Bigger populations grow faster so late eras are reachable.
	_grow_progress += dt * mult("growth") * (1.0 + population * 0.02) / GROW_TIME
	if _grow_progress >= 1.0:
		_grow_progress = 0.0
		population += 1
		structure_changed.emit()


func _lose_person() -> void:
	# The last survivor never starves, so a run can't soft-lock at zero people.
	if population <= 1:
		return
	population -= 1
	if idle() < 0:
		var busiest := ""
		for id in jobs:
			if busiest == "" or jobs[id] > jobs[busiest]:
				busiest = id
		jobs[busiest] -= 1
	post("Someone starved to death.")
	structure_changed.emit()


# --- modifiers -------------------------------------------------------------

func rebuild_modifiers() -> void:
	_mods.clear()
	for b in GameData.BUILDINGS:
		var count: int = buildings.get(b["id"], 0)
		if count > 0:
			for e in b["effects"]:
				_apply_effect(e, count)
	for u in GameData.UPGRADES:
		if upgrades.has(u["id"]):
			for e in u["effects"]:
				_apply_effect(e, 1)


func _apply_effect(effect: Dictionary, count: int) -> void:
	var key: String = effect["key"]
	var m: Dictionary = _mods.get(key, {"add": 0.0, "mult": 1.0})
	if effect.has("add"):
		m["add"] += float(effect["add"]) * count
	if effect.has("mult"):
		m["mult"] *= pow(float(effect["mult"]), count)
	_mods[key] = m


func mult(key: String) -> float:
	return _mods.get(key, {}).get("mult", 1.0)


func add(key: String) -> float:
	return _mods.get(key, {}).get("add", 0.0)


func job_multiplier(job_id: String) -> float:
	return mult("job:" + job_id) * mult("job:all")


func food_per_second_per_person() -> float:
	return FOOD_PER_PERSON * mult("food_use")


func pop_cap() -> int:
	return BASE_POP_CAP + int(add("pop_cap"))


func idle() -> int:
	var busy := 0
	for id in jobs:
		busy += jobs[id]
	return population - busy


# --- availability ----------------------------------------------------------

func is_unlocked(resource_id: String) -> bool:
	return unlocked.has(resource_id)


func job_available(job: Dictionary) -> bool:
	return is_unlocked(job["requires"])


func building_available(b: Dictionary) -> bool:
	return is_unlocked(b["requires"])


func upgrade_available(u: Dictionary) -> bool:
	return not upgrades.has(u["id"]) and is_unlocked(u["requires"])


func tech_available(t: Dictionary) -> bool:
	if techs.has(t["id"]):
		return false
	return t["requires"] == "" or techs.has(t["requires"])


# --- costs and actions -----------------------------------------------------

func building_cost(id: String) -> Dictionary:
	var b := GameData.find("building", id)
	var count: int = buildings.get(id, 0)
	var cost := {}
	for res in b["cost"]:
		cost[res] = ceilf(b["cost"][res] * pow(b["scale"], count))
	return cost


func can_afford(cost: Dictionary) -> bool:
	for res in cost:
		if amounts.get(res, 0.0) < cost[res]:
			return false
	return true


func _pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res in cost:
		amounts[res] -= cost[res]
	return true


func click_gather(resource_id: String) -> float:
	var r := GameData.find("resource", resource_id)
	if r.is_empty() or not r.get("clickable", false) or not is_unlocked(resource_id):
		return 0.0
	var gained := mult("click") * mult("click:" + resource_id)
	amounts[resource_id] += gained
	return gained


func assign_job(job_id: String, delta: int) -> void:
	var job := GameData.find("job", job_id)
	if job.is_empty() or not job_available(job):
		return
	var current: int = jobs.get(job_id, 0)
	var change := clampi(delta, -current, idle())
	if change == 0:
		return
	jobs[job_id] = current + change
	structure_changed.emit()


func buy_building(id: String) -> bool:
	var b := GameData.find("building", id)
	if b.is_empty() or not building_available(b) or not _pay(building_cost(id)):
		return false
	buildings[id] = buildings.get(id, 0) + 1
	rebuild_modifiers()
	structure_changed.emit()
	return true


func buy_upgrade(id: String) -> bool:
	var u := GameData.find("upgrade", id)
	if u.is_empty() or not upgrade_available(u) or not _pay(u["cost"]):
		return false
	upgrades[id] = true
	rebuild_modifiers()
	post("Upgrade bought: %s" % u["name"])
	structure_changed.emit()
	return true


func research(id: String) -> bool:
	var t := GameData.find("tech", id)
	if t.is_empty() or not tech_available(t) or not _pay(t["cost"]):
		return false
	techs[id] = true
	unlocked[t["unlocks"]] = true
	post("Discovered %s! %s unlocked." % [t["name"], GameData.resource_name(t["unlocks"])])
	structure_changed.emit()
	return true


func post(text: String) -> void:
	message_posted.emit(text)


# --- offline progress ------------------------------------------------------

func apply_offline(seconds: float) -> Dictionary:
	seconds = minf(seconds, MAX_OFFLINE_SECONDS)
	var before := amounts.duplicate()
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(OFFLINE_CHUNK, remaining)
		simulate(step, true)
		remaining -= step
	var gains := {}
	for id in amounts:
		var diff: float = amounts[id] - before[id]
		if absf(diff) > 0.0:
			gains[id] = diff
	return gains


# --- save data -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"amounts": amounts.duplicate(),
		"unlocked": unlocked.keys(),
		"jobs": jobs.duplicate(),
		"buildings": buildings.duplicate(),
		"upgrades": upgrades.keys(),
		"techs": techs.keys(),
		"population": population,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var saved_amounts: Dictionary = data.get("amounts", {})
	for id in saved_amounts:
		if amounts.has(id):
			amounts[id] = float(saved_amounts[id])
	for id in data.get("unlocked", []):
		unlocked[id] = true
	for id in data.get("upgrades", []):
		upgrades[id] = true
	for id in data.get("techs", []):
		techs[id] = true
	var saved_jobs: Dictionary = data.get("jobs", {})
	for id in saved_jobs:
		jobs[id] = int(saved_jobs[id])
	var saved_buildings: Dictionary = data.get("buildings", {})
	for id in saved_buildings:
		buildings[id] = int(saved_buildings[id])
	population = int(data.get("population", STARTING_POPULATION))
	rebuild_modifiers()
	structure_changed.emit()
