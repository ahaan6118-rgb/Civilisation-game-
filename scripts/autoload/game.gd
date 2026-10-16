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
var lifetime: Dictionary = {}
var clicks: int = 0
var revealed: Dictionary = {}
var items: Dictionary = {}
var consumables: Dictionary = {}
var crafts: Array = []
var crafted_count: Dictionary = {}
var conquered: Dictionary = {}
var pending_invasion := ""

var _grow_progress := 0.0
var _starve_progress := 0.0
var _accum := 0.0
var _mods: Dictionary = {}
var _rng := RandomNumberGenerator.new()


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
	lifetime.clear()
	clicks = 0
	revealed.clear()
	items.clear()
	consumables.clear()
	crafts.clear()
	crafted_count.clear()
	conquered.clear()
	pending_invasion = ""
	for r in GameData.RESOURCES:
		amounts[r["id"]] = 0.0
	for id in GameData.STARTING_RESOURCES:
		unlocked[id] = true
	amounts["food"] = STARTING_FOOD
	population = STARTING_POPULATION
	starving = false
	_grow_progress = 0.0
	_starve_progress = 0.0
	_changed()


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
	_run_crafts(dt)
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
			var made: float = produces[res] * workers * dt * ratio * m
			amounts[res] += made
			lifetime[res] = lifetime.get(res, 0.0) + made


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
		_changed()


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
	_changed()


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
	for it in GameData.ITEMS:
		var owned: int = items.get(it["id"], 0)
		if owned > 0:
			for e in it.get("effects", []):
				_apply_effect(e, owned)
	for syn in active_synergies():
		for e in syn["effects"]:
			_apply_effect(e, 1)
	for c in GameData.COUNTRIES:
		if conquered.has(c["id"]):
			for e in c["effects"]:
				_apply_effect(e, 1)


func _changed() -> void:
	rebuild_modifiers()
	structure_changed.emit()


func _apply_effect(effect: Dictionary, count: int) -> void:
	var key: String = effect["key"]
	var m: Dictionary = _mods.get(key, {"add": 0.0, "mult": 1.0})
	if effect.has("add"):
		m["add"] += float(effect["add"]) * count
	if effect.has("mult"):
		m["mult"] *= pow(float(effect["mult"]), count)
	if effect.has("per"):
		m["mult"] *= pow(1.0 + float(effect["pct"]) * count_of(effect["per"]), count)
	_mods[key] = m


# Counters used by "per" effects and unlock conditions: job:<id>, building:<id>, population, items.
func count_of(counter: String) -> int:
	if counter == "population":
		return population
	if counter == "items":
		return total_items()
	var parts := counter.split(":")
	if parts[0] == "job":
		return jobs.get(parts[1], 0)
	if parts[0] == "building":
		return buildings.get(parts[1], 0)
	return 0


func mult(key: String) -> float:
	return _mods.get(key, {}).get("mult", 1.0)


func add(key: String) -> float:
	return _mods.get(key, {}).get("add", 0.0)


func job_multiplier(job_id: String) -> float:
	return mult("job:" + job_id) * mult("job:all")


func food_per_second_per_person() -> float:
	return FOOD_PER_PERSON * mult("food_use")


# Ignores input shortages; used for click_cps so it doesn't flicker.
func production_per_second(resource_id: String) -> float:
	var total := 0.0
	for job in GameData.JOBS:
		var workers: int = jobs.get(job["id"], 0)
		if workers > 0 and job["produces"].has(resource_id):
			total += job["produces"][resource_id] * workers * job_multiplier(job["id"])
	return total


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
	return is_unlocked(job["requires"]) and (not job.has("requires_tech") or techs.has(job["requires_tech"]))


func building_available(b: Dictionary) -> bool:
	return is_unlocked(b["requires"])


# Once an upgrade's unlock conditions are met it stays revealed, like Cookie Clicker.
func upgrade_available(u: Dictionary) -> bool:
	if upgrades.has(u["id"]) or not is_unlocked(u["requires"]):
		return false
	if revealed.has(u["id"]):
		return true
	for c in u.get("unlock", []):
		if not condition_met(c):
			return false
	revealed[u["id"]] = true
	return true


func condition_met(c: Dictionary) -> bool:
	if c.has("job"):
		return jobs.get(c["job"], 0) >= c["count"]
	if c.has("building"):
		return buildings.get(c["building"], 0) >= c["count"]
	if c.has("lifetime"):
		return lifetime.get(c["lifetime"], 0.0) >= c["amount"]
	if c.has("clicks"):
		return clicks >= c["clicks"]
	if c.has("population"):
		return population >= c["population"]
	if c.has("items"):
		return total_items() >= c["items"]
	return false


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
	var gained := mult("click") * mult("click:" + resource_id) + add("click_cps") * production_per_second(resource_id)
	amounts[resource_id] += gained
	lifetime[resource_id] = lifetime.get(resource_id, 0.0) + gained
	clicks += 1
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
	_changed()


func buy_building(id: String) -> bool:
	var b := GameData.find("building", id)
	if b.is_empty() or not building_available(b) or not _pay(building_cost(id)):
		return false
	buildings[id] = buildings.get(id, 0) + 1
	_changed()
	return true


func buy_upgrade(id: String) -> bool:
	var u := GameData.find("upgrade", id)
	if u.is_empty() or not upgrade_available(u) or not _pay(u["cost"]):
		return false
	upgrades[id] = true
	post("Upgrade bought: %s" % u["name"])
	_changed()
	return true


func research(id: String) -> bool:
	var t := GameData.find("tech", id)
	if t.is_empty() or not tech_available(t) or not _pay(t["cost"]):
		return false
	techs[id] = true
	if t["unlocks"] != "":
		unlocked[t["unlocks"]] = true
	post("Discovered %s! %s" % [t["name"], t["desc"]])
	_changed()
	return true


# --- crafting ----------------------------------------------------------------

func maker_slots(maker_id: String) -> int:
	var maker := GameData.find("maker", maker_id)
	return buildings.get(maker["building"], 0)


func maker_busy(maker_id: String) -> int:
	var busy := 0
	for c in crafts:
		if c["maker"] == maker_id:
			busy += 1
	return busy


func commission_cost(maker_id: String) -> Dictionary:
	var maker := GameData.find("maker", maker_id)
	var done: int = crafted_count.get(maker_id, 0)
	var cost := {}
	for res in maker["cost"]:
		cost[res] = ceilf(maker["cost"][res] * pow(maker["cost_scale"], done))
	return cost


func commission_time(maker_id: String) -> float:
	return GameData.find("maker", maker_id)["time"]


func start_commission(maker_id: String) -> bool:
	if GameData.find("maker", maker_id).is_empty():
		return false
	if maker_busy(maker_id) >= maker_slots(maker_id) or not _pay(commission_cost(maker_id)):
		return false
	crafted_count[maker_id] = crafted_count.get(maker_id, 0) + 1
	var time := commission_time(maker_id)
	crafts.append({"maker": maker_id, "remaining": time, "total": time})
	structure_changed.emit()
	return true


func _run_crafts(dt: float) -> void:
	var speed := mult("craft_speed")
	var finished: Array = []
	for c in crafts:
		c["remaining"] -= dt * speed
		if c["remaining"] <= 0.0:
			finished.append(c)
	for c in finished:
		crafts.erase(c)
		_grant_item(roll_item(c["maker"]))
	if add("auto_craft") > 0.0:
		for maker in GameData.MAKERS:
			while maker_busy(maker["id"]) < maker_slots(maker["id"]) and start_commission(maker["id"]):
				pass


func roll_item(maker_id: String) -> String:
	var luck := mult("luck")
	var pool: Array = []
	var total := 0.0
	for it in GameData.ITEMS:
		if it["maker"] != maker_id:
			continue
		var w: float = GameData.RARITIES[it["rarity"]]["weight"]
		if it["rarity"] != "common":
			w *= luck
		pool.append([it["id"], w])
		total += w
	var pick := _rng.randf() * total
	for entry in pool:
		pick -= entry[1]
		if pick <= 0.0:
			return entry[0]
	return pool[-1][0]


func is_consumable(item_id: String) -> bool:
	return GameData.find("item", item_id).get("kind", "relic") == "consumable"


func _grant_item(item_id: String) -> void:
	var it := GameData.find("item", item_id)
	var rarity: String = GameData.RARITIES[it["rarity"]]["name"]
	if is_consumable(item_id):
		consumables[item_id] = consumables.get(item_id, 0) + 1
		post("Crafted: %s (%s consumable) x%d" % [it["name"], rarity, consumables[item_id]])
		structure_changed.emit()
		return
	var before := active_synergies()
	items[item_id] = items.get(item_id, 0) + 1
	post("Crafted: %s (%s)%s" % [it["name"], rarity, "" if items[item_id] == 1 else " x%d" % items[item_id]])
	_changed()
	for syn in active_synergies():
		if not before.has(syn):
			post("SYNERGY! %s: %s" % [syn["name"], syn["desc"]])


# Removes one consumable and returns its "use" effects, or [] if none are owned.
func use_consumable(item_id: String) -> Array:
	if consumables.get(item_id, 0) <= 0:
		return []
	consumables[item_id] -= 1
	if consumables[item_id] == 0:
		consumables.erase(item_id)
	structure_changed.emit()
	return GameData.find("item", item_id)["use"]


func total_items() -> int:
	var n := 0
	for id in items:
		n += items[id]
	return n


func active_synergies() -> Array:
	var result: Array = []
	for syn in GameData.SYNERGIES:
		var complete := true
		for id in syn["items"]:
			if not items.has(id):
				complete = false
				break
		if complete:
			result.append(syn)
	return result


# --- invasions ----------------------------------------------------------------

const BASE_ARMY := 300.0
const TROOPS_PER_WARRIOR := 50.0


func invasion_unlocked() -> bool:
	return techs.has("warfare")


func army_size() -> float:
	return (BASE_ARMY + jobs.get("warrior", 0) * TROOPS_PER_WARRIOR) * mult("army:size")


# The first unconquered country, or {} when all are conquered. Check is_unlocked(country.requires) before launching.
func next_country() -> Dictionary:
	for c in GameData.COUNTRIES:
		if not conquered.has(c["id"]):
			return c
	return {}


func can_invade(country_id: String) -> bool:
	var c := next_country()
	return invasion_unlocked() and not c.is_empty() and c["id"] == country_id and is_unlocked(c["requires"]) and can_afford(c["cost"])


func start_invasion(country_id: String) -> bool:
	if not can_invade(country_id):
		return false
	_pay(GameData.find("country", country_id)["cost"])
	pending_invasion = country_id
	return true


func finish_invasion(won: bool) -> void:
	var c := GameData.find("country", pending_invasion)
	pending_invasion = ""
	if c.is_empty():
		return
	if not won:
		post("The invasion of %s failed. The supplies are gone." % c["name"])
		return
	conquered[c["id"]] = true
	for res in c["loot"]:
		amounts[res] = amounts.get(res, 0.0) + c["loot"][res]
	post("Conquered %s! Loot: %s. %s" % [c["name"], NumFormat.cost(c["loot"]), c["reward_desc"]])
	_changed()


const MESSAGE_HISTORY := 5
var recent_messages: PackedStringArray = []


func post(text: String) -> void:
	recent_messages.append(text)
	while recent_messages.size() > MESSAGE_HISTORY:
		recent_messages.remove_at(0)
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
		"lifetime": lifetime.duplicate(),
		"clicks": clicks,
		"revealed": revealed.keys(),
		"items": items.duplicate(),
		"crafts": crafts.duplicate(true),
		"crafted_count": crafted_count.duplicate(),
		"conquered": conquered.keys(),
		"consumables": consumables.duplicate(),
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
	var saved_lifetime: Dictionary = data.get("lifetime", {})
	for id in saved_lifetime:
		lifetime[id] = float(saved_lifetime[id])
	clicks = int(data.get("clicks", 0))
	for id in data.get("revealed", []):
		revealed[id] = true
	var saved_items: Dictionary = data.get("items", {})
	for id in saved_items:
		if not GameData.find("item", id).is_empty() and not is_consumable(id):
			items[id] = int(saved_items[id])
	for c in data.get("crafts", []):
		crafts.append({"maker": c["maker"], "remaining": float(c["remaining"]), "total": float(c["total"])})
	var saved_consumables: Dictionary = data.get("consumables", {})
	for id in saved_consumables:
		if is_consumable(id):
			consumables[id] = int(saved_consumables[id])
	for id in data.get("conquered", []):
		conquered[id] = true
	var saved_crafted: Dictionary = data.get("crafted_count", {})
	for id in saved_crafted:
		crafted_count[id] = int(saved_crafted[id])
	_changed()
