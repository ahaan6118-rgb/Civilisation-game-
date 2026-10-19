extends Node

signal structure_changed
signal message_posted(text: String)

const TICK := 0.1
const MAX_TICKS_PER_FRAME := 50
const BASE_POP_CAP := 5
const STARTING_POPULATION := 3
const STARTING_FOOD := 30.0
const FOOD_PER_PERSON := 0.3
const BASE_IQ := 50.0
const BASE_IQ_CAP := 60.0
const IQ_PER_ELDER := 0.02
const HAZARD_SCALE := 6.0
const START_MORALE := 50.0
const START_HEALTH := 60.0
const GRIEF_PER_DEATH := 4.0
const MAX_GRIEF := 40.0
const CRIME_BELOW_MORALE := 30.0
const ILLNESS_RATE := 0.15
const MAX_WELLBEING_BONUS := 40.0
# Births grow with the square root of the population (plus a trickle for tiny tribes) while old age
# kills each person after about LIFESPAN seconds, so every town settles where deaths catch up with
# births: about (LIFESPAN / BIRTH_TIME)^2 = 58 people at health 60, more with health, growth and lifespan.
const BIRTH_TIME := 55.0
const BASE_BIRTHS := 1.0 / 240.0
const LIFESPAN := 420.0
# Knowledge fades without Elders: IQ slides back toward BASE_IQ by this fraction of the gap per second.
const IQ_DECAY := 0.002
# Every age brings deadlier work (machines, mines, reactors): accidents x this per age.
const ERA_DANGER := 1.3
const FOOD_TO_GROW_PER_PERSON := 5.0
const STARVE_TIME := 4.0
# Decay, after the Kaizo Cookies mod at 75% of its strength: everything your people make slowly
# decays (corruption, rot, laziness) and decays faster the lower it gets. Clicking the big button halts it,
# discoveries, upgrades and blessings purify it, and leaving it alone builds momentum.
const DECAY_MIN_POW := 0.15
const DECAY_FLOOR := 0.01
const HALT_PER_CLICK := 1.0
const HALT_FALL := 0.33
const HALT_KEEP := 0.25
const HALT_OVERTIME_LIMIT := 4.0
const HALT_OVERTIME_POWER := 0.75
const MOMENTUM_GROWTH := 0.004
const MOMENTUM_MAX := 4.0
const MOMENTUM_CLICK_KEEP := 0.97
# Kaizo's progress scaling at 75% strength: decay starts almost harmless and grows with everything
# made this run (per digit), upgrades owned and time played (per doubling).
const DECAY_PER_DIGIT := 0.99775
const DECAY_PER_UPGRADE := 0.998
const DECAY_PER_TIME_DOUBLING := 0.9999
const DECAY_SCALING := 0.75
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
# maker id -> true while that maker is told to stop working.
var paused_makers: Dictionary = {}
var conquered: Dictionary = {}
var pending_war: Dictionary = {}
var incoming_war: Dictionary = {}
var _declare_timer := WarData.DECLARE_MAX
var iq := BASE_IQ
var run_deaths := 0
var morale := START_MORALE
var health := START_HEALTH
var grief := 0.0
var weariness := 0.0
var crime_rate := 0.0
# 1 = full production; falls toward DECAY_FLOOR.
var decay := 1.0
var decay_halt := 0.0
var decay_overtime := 0.0
var decay_momentum := 1.0
var decay_enabled := true
# Seconds played this run (online only).
var run_time := 0.0
# active event: {id, remaining (-1 = until fixed), target}
var events: Array = []
var events_enabled := true
var _event_timer := EventData.MAX_GAP
# These survive a rebirth.
var legacy := 0
var prestige: Dictionary = {}
var runs := 0
var total_deaths := 0

var _grow_progress := 0.0
var _age_progress := 0.0
var _starve_progress := 0.0
var _accum := 0.0
var _mods: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	reset()


# Wipes everything, including Legacy and prestige upgrades.
func reset() -> void:
	legacy = 0
	prestige.clear()
	runs = 0
	total_deaths = 0
	new_run()


# Starts a fresh civilisation, keeping Legacy and prestige upgrades.
func new_run() -> void:
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
	paused_makers.clear()
	conquered.clear()
	pending_war = {}
	incoming_war = {}
	_declare_timer = WarData.DECLARE_MAX
	run_deaths = 0
	morale = START_MORALE
	health = START_HEALTH
	grief = 0.0
	weariness = 0.0
	crime_rate = 0.0
	decay = 1.0
	decay_halt = 0.0
	decay_overtime = 0.0
	decay_momentum = 1.0
	run_time = 0.0
	events.clear()
	_event_timer = EventData.MAX_GAP
	for r in GameData.RESOURCES:
		amounts[r["id"]] = 0.0
	for id in GameData.STARTING_RESOURCES:
		unlocked[id] = true
	rebuild_modifiers()
	amounts["food"] = STARTING_FOOD + add("start_food")
	population = STARTING_POPULATION + int(add("start_pop"))
	iq = BASE_IQ + add("start_iq")
	starving = false
	_grow_progress = 0.0
	_age_progress = 0.0
	_starve_progress = 0.0
	for i in int(add("start_relic")):
		var relic := roll_item("artisan")
		while is_consumable(relic):
			relic = roll_item("artisan")
		items[relic] = items.get(relic, 0) + 1
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
	# A declared war drags you into battle wherever you are once the warning runs out.
	if not incoming_war.is_empty() and incoming_war["countdown"] <= 0.0 and pending_war.is_empty():
		start_war(incoming_war["target"], true)
		get_tree().change_scene_to_file("res://scenes/invasion.tscn")


# offline = true skips spoilage, starvation and growth, so idle time is never punished.
func simulate(dt: float, offline: bool) -> void:
	var before := amounts.duplicate()
	_run_jobs(dt)
	_teach(dt)
	_run_crafts(dt)
	_feed_population(dt, offline)
	if offline:
		return
	_forget(dt)
	_run_decay(dt)
	_run_accidents(dt)
	_update_wellbeing(dt)
	_run_illness(dt)
	_run_crime(dt)
	_run_events(dt)
	_run_war_declarations(dt)
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
	# Old age never stops; a sick tribe dies young.
	_age_progress += old_age_per_second() * dt
	while _age_progress >= 1.0:
		_age_progress -= 1.0
		if _kill_random(1) > 0:
			post("Someone died of old age.")
			_changed()
	# Babies only come when there's a real food stockpile, which spoilage keeps eating.
	if population <= 0 or population >= pop_cap() or amounts["food"] < population * FOOD_TO_GROW_PER_PERSON:
		_grow_progress = 0.0
		return
	_grow_progress += births_per_second() * dt
	var born := 0
	while _grow_progress >= 1.0 and population < pop_cap():
		_grow_progress -= 1.0
		population += 1
		born += 1
	if born > 0:
		_changed()


# Health 60 = normal lifespan; 100 = 1.4x as long, 0 = 0.4x.
func lifespan() -> float:
	return LIFESPAN * (0.4 + health / 100.0) * mult("lifespan")


func old_age_per_second() -> float:
	return population / maxf(1.0, lifespan())


# Growth upgrades have diminishing returns (4x growth = 2x babies) so births can't outrun death forever.
func births_per_second() -> float:
	var fertility := clampf(health / 60.0, 0.2, 1.4) * (0.5 + morale / 100.0)
	return (BASE_BIRTHS + sqrt(population) / BIRTH_TIME) * sqrt(mult("growth")) * fertility


func _teach(dt: float) -> void:
	var elders: int = jobs.get("elder", 0)
	if elders > 0 and iq < iq_cap():
		iq = minf(iq_cap(), iq + elders * IQ_PER_ELDER * mult("teaching") * dt)


# Only while you play, like spoilage: neglected schooling slowly undoes itself.
func _forget(dt: float) -> void:
	iq = maxf(BASE_IQ, iq - (iq - BASE_IQ) * IQ_DECAY * dt)


func iq_cap() -> float:
	return BASE_IQ_CAP + add("iq_cap")


# Smarter tribes have fewer accidents (IQ 100 is 2x safer than IQ 50), but every age is more dangerous.
func accident_multiplier(job_id: String) -> float:
	return HAZARD_SCALE * BASE_IQ / maxf(iq, 1.0) * pow(ERA_DANGER, maxi(0, era_index())) * mult("hazard") * mult("hazard:" + job_id)


func deaths_per_hour(job_id: String) -> float:
	if job_id == "idle":
		return idle() * GameData.IDLE_HAZARD * accident_multiplier("idle")
	var job := GameData.find("job", job_id)
	return jobs.get(job_id, 0) * job.get("hazard", 0.0) * accident_multiplier(job_id)


func _run_accidents(dt: float) -> void:
	for job in GameData.JOBS:
		if jobs.get(job["id"], 0) > 0 and _rng.randf() < deaths_per_hour(job["id"]) / 3600.0 * dt:
			var reasons: Array = job["deaths"]
			_kill(job["id"], "%s %s %s." % [_article(job["name"]), job["name"], reasons[_rng.randi() % reasons.size()]])
	if idle() > 0 and _rng.randf() < deaths_per_hour("idle") / 3600.0 * dt:
		var reasons: Array = GameData.IDLE_DEATHS
		_kill("", "An idle villager %s." % reasons[_rng.randi() % reasons.size()])


func _article(word: String) -> String:
	return "An" if word.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "A"


func _kill(job_id: String, message: String) -> void:
	if _remove_person(job_id):
		post(message)
		_changed()


# The last survivor is spared so a run can always recover.
func _remove_person(job_id: String) -> bool:
	if population <= 1:
		return false
	population -= 1
	if job_id != "" and jobs.get(job_id, 0) > 0:
		jobs[job_id] -= 1
	elif idle() < 0:
		_drop_busiest_job()
	run_deaths += 1
	total_deaths += 1
	grief = minf(MAX_GRIEF, grief + GRIEF_PER_DEATH)
	return true


func _drop_busiest_job() -> void:
	var busiest := ""
	for id in jobs:
		if busiest == "" or jobs[id] > jobs[busiest]:
			busiest = id
	if busiest != "":
		jobs[busiest] -= 1


# Kills n random people (workers or idle) and returns how many actually died.
func _kill_random(n: int) -> int:
	var died := 0
	for i in n:
		var pick := _rng.randi() % maxi(1, population)
		var chosen := ""
		for id in jobs:
			if pick < jobs[id]:
				chosen = id
				break
			pick -= jobs[id]
		if not _remove_person(chosen):
			break
		died += 1
	return died


# --- morale, health, crime and illness -----------------------------------------

# Bonuses flatten out near MAX_WELLBEING_BONUS; penalties (events) always hit in full.
func _wellbeing_bonus(key: String) -> float:
	var total := add(key)
	return MAX_WELLBEING_BONUS * (1.0 - exp(-total / MAX_WELLBEING_BONUS)) if total > 0.0 else total


func morale_target() -> float:
	var t := START_MORALE + _wellbeing_bonus("morale") - grief - weariness
	if starving:
		t -= 25.0
	if population >= 5 and population >= pop_cap() * 0.9:
		t -= 10.0
	return clampf(t, 0.0, 100.0)


func health_target() -> float:
	var t := START_HEALTH + _wellbeing_bonus("health") - 25.0 * population / maxf(1.0, pop_cap())
	if starving:
		t -= 20.0
	return clampf(t, 0.0, 100.0)


# Miserable people work at 0.6x, happy ones at 1.4x.
func morale_factor() -> float:
	return 0.6 + 0.8 * morale / 100.0


func illness_per_hour() -> float:
	return population * HAZARD_SCALE * ILLNESS_RATE * pow((100.0 - health) / 50.0, 2.0)


func _update_wellbeing(dt: float) -> void:
	morale = move_toward(morale, morale_target(), 2.0 * dt)
	health = move_toward(health, health_target(), 1.0 * dt)
	grief = maxf(0.0, grief - 0.3 * dt)
	weariness = maxf(0.0, weariness - 0.05 * dt)


func _run_illness(dt: float) -> void:
	if _rng.randf() < illness_per_hour() / 3600.0 * dt and _kill_random(1) > 0:
		post("Someone died of illness." if not has_event("plague") else "The plague claimed another life.")
		_changed()


# Unhappy people steal: below 30 morale a slice of every stockpile (except food) disappears.
func _run_crime(dt: float) -> void:
	crime_rate = 0.0
	if morale >= CRIME_BELOW_MORALE:
		return
	crime_rate = (CRIME_BELOW_MORALE - morale) / CRIME_BELOW_MORALE * 0.004 * mult("crime")
	for id in unlocked:
		if id != "food":
			amounts[id] *= 1.0 - crime_rate * dt


# --- random events ---------------------------------------------------------------

func has_event(id: String) -> bool:
	for ev in events:
		if ev["id"] == id:
			return true
	return false


func _run_events(dt: float) -> void:
	var ended: Array = []
	for ev in events:
		if ev["remaining"] < 0.0:
			continue
		ev["remaining"] -= dt
		if ev["remaining"] <= 0.0:
			ended.append(ev)
	for ev in ended:
		_end_event(ev, "%s has ended." % EventData.find(ev["id"])["name"])
	if not events_enabled:
		return
	_event_timer -= dt
	if _event_timer > 0.0:
		return
	# Later ages are more crowded and more fragile: disasters come faster and hit harder.
	_event_timer = _rng.randf_range(EventData.MIN_GAP, EventData.MAX_GAP) / (1.0 + EventData.GAP_SHRINK_PER_ERA * maxi(0, era_index()))
	var pool: Array = []
	var total := 0.0
	for e in EventData.EVENTS:
		if not event_eligible(e):
			continue
		var w: float = e["weight"]
		if not e["good"]:
			w *= mult("bad_events")
		if e["id"] == "plague":
			w *= mult("plague_risk")
		pool.append([e, w])
		total += w
	var pick := _rng.randf() * total
	for entry in pool:
		pick -= entry[1]
		if pick <= 0.0:
			start_event(entry[0]["id"])
			return


func event_eligible(e: Dictionary) -> bool:
	if not is_unlocked(e["requires"]) or has_event(e["id"]):
		return false
	if e["duration"] != 0 and events.size() >= EventData.MAX_ACTIVE:
		return false
	var when: Dictionary = e.get("when", {})
	if population < when.get("min_pop", 0):
		return false
	if morale > when.get("max_morale", 101.0) or morale < when.get("min_morale", -1.0):
		return false
	if health > when.get("max_health", 101.0) or health < when.get("min_health", -1.0):
		return false
	if when.get("starving", false) and not starving:
		return false
	if when.get("mine", false) and _pick_mine() == "":
		return false
	return true


func _pick_mine() -> String:
	var options: Array = []
	for id in EventData.MINE_JOBS:
		if jobs.get(id, 0) > 0:
			options.append(id)
	return options[_rng.randi() % options.size()] if not options.is_empty() else ""


func start_event(id: String) -> void:
	var e := EventData.find(id)
	var target := _pick_mine() if e.get("when", {}).get("mine", false) else ""
	var start: Dictionary = e.get("start", {})
	var defense := disaster_severity() if not e["good"] else 1.0
	if start.get("raid", false):
		defense *= clampf(1.0 - jobs.get("warrior", 0) / maxf(1.0, population * 0.15), 0.2, 1.0)
	var notes: PackedStringArray = []
	for res in start.get("lose", {}):
		if amounts.has(res):
			amounts[res] *= 1.0 - minf(0.95, start["lose"][res] * defense)
	# "destroy" is a minimum; big cities lose a share of everything they built.
	var n_destroy := int(start.get("destroy", 0))
	if n_destroy > 0:
		n_destroy = maxi(n_destroy, ceili(_building_count() * n_destroy * EventData.DESTROY_SHARE * defense))
	var destroyed := _destroy_buildings(n_destroy)
	if destroyed > 0:
		notes.append("%d buildings destroyed" % destroyed)
	var to_kill := roundi(population * minf(0.75, start.get("kill", 0.0) * defense))
	if to_kill > 0:
		notes.append("%d died" % _kill_random(to_kill))
	var homeless := population - pop_cap()
	if homeless > 0:
		notes.append("%d left homeless wandered off" % _kill_random(homeless))
	if start.has("iq"):
		iq += start["iq"]
	if start.has("pop"):
		population = mini(pop_cap(), population + maxi(1, int(population * start["pop"])))
	if start.has("gift"):
		for res in unlocked:
			amounts[res] *= 1.0 + start["gift"]
	var duration: float = e["duration"]
	if duration != 0:
		events.append({"id": id, "remaining": duration, "target": target})
	if e["good"]:
		purify(1.5)
	var title := ("BLESSING: %s! " if e["good"] else "DISASTER: %s! ") % e["name"]
	post(title + e["desc"] + (" (" + ", ".join(notes) + ")" if not notes.is_empty() else ""))
	if start.get("relic", false):
		var relic := roll_item("artisan")
		while is_consumable(relic):
			relic = roll_item("artisan")
		_grant_item(relic)
	_changed()


# Disasters get worse every age: x1 in the Wood age, x1.12 in Stone, and so on.
func disaster_severity() -> float:
	return 1.0 + EventData.SEVERITY_PER_ERA * maxi(0, era_index())


func _building_count() -> int:
	var n := 0
	for id in buildings:
		if GameData.find("maker", id).is_empty():
			n += buildings[id]
	return n


# Destroys up to n random buildings (not item makers). Returns how many.
func _destroy_buildings(n: int) -> int:
	var destroyed := 0
	for i in n:
		var owned: Array = []
		for id in buildings:
			if buildings[id] > 0 and GameData.find("maker", id).is_empty():
				for k in buildings[id]:
					owned.append(id)
		if owned.is_empty():
			break
		var id: String = owned[_rng.randi() % owned.size()]
		buildings[id] -= 1
		destroyed += 1
	if destroyed > 0:
		rebuild_modifiers()
	return destroyed


func _end_event(ev: Dictionary, message: String) -> void:
	events.erase(ev)
	post(message)
	_changed()


func fix_cost(ev: Dictionary) -> Dictionary:
	var fix: Dictionary = EventData.find(ev["id"]).get("fix", {})
	var cost := {}
	for key in fix.get("pay", {}):
		var res: String = key
		if key == "top":
			res = _biggest_stockpile()
		elif key == "$target":
			res = GameData.find("job", ev["target"])["produces"].keys()[0]
		cost[res] = maxf(25.0, ceilf(amounts.get(res, 0.0) * fix["pay"][key]))
	return cost


func _biggest_stockpile() -> String:
	var best := "wood"
	for id in unlocked:
		if id != "food" and amounts[id] > amounts.get(best, 0.0):
			best = id
	return best


func fix_event(index: int) -> bool:
	if index < 0 or index >= events.size():
		return false
	var ev: Dictionary = events[index]
	var fix: Dictionary = EventData.find(ev["id"]).get("fix", {})
	if fix.is_empty() or not _pay(fix_cost(ev)):
		return false
	_end_event(ev, "%s: %s is over." % [fix["label"], EventData.find(ev["id"])["name"]])
	return true


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
	run_deaths += 1
	total_deaths += 1
	grief = minf(MAX_GRIEF, grief + GRIEF_PER_DEATH)
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
				_apply_effect(e, owned, true)
	for syn in active_synergies():
		for e in syn["effects"]:
			_apply_effect(e, 1)
	for e in WarData.CONQUEST_EFFECTS:
		if not conquered.is_empty():
			_apply_effect(e, conquered.size())
	var tiers_done := completed_tiers()
	if tiers_done > 0:
		for e in WarData.TIER_EFFECTS:
			_apply_effect(e, tiers_done)
	for p in GameData.PRESTIGE:
		var level: int = prestige.get(p["id"], 0)
		if level > 0:
			for e in p["effects"]:
				_apply_effect(e, level)
	for ev in events:
		for e in EventData.find(ev["id"]).get("effects", []):
			var effect: Dictionary = e.duplicate()
			effect["key"] = String(effect["key"]).replace("$target", ev["target"])
			_apply_effect(effect, 1)


func _changed() -> void:
	rebuild_modifiers()
	structure_changed.emit()


# linear: duplicate copies add their bonus instead of compounding (1.3x twice = 1.6x),
# and reductions shrink with diminishing returns so they never reach zero.
func _apply_effect(effect: Dictionary, count: int, linear := false) -> void:
	var key: String = effect["key"]
	var m: Dictionary = _mods.get(key, {"add": 0.0, "mult": 1.0})
	if effect.has("add"):
		m["add"] += float(effect["add"]) * count
	if effect.has("mult"):
		var factor := float(effect["mult"])
		if not linear:
			m["mult"] *= pow(factor, count)
		elif factor >= 1.0:
			m["mult"] *= 1.0 + (factor - 1.0) * count
		else:
			m["mult"] /= 1.0 + (1.0 / factor - 1.0) * count
	if effect.has("per"):
		m["mult"] *= pow(1.0 + float(effect["pct"]) * count_of(effect["per"]), count)
	_mods[key] = m


# Counters used by "per" effects and unlock conditions: job:<id>, building:<id>, item:<id>, population, items.
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
	if parts[0] == "item":
		return items.get(parts[1], 0)
	return 0


func mult(key: String) -> float:
	return _mods.get(key, {}).get("mult", 1.0)


func add(key: String) -> float:
	return _mods.get(key, {}).get("add", 0.0)


func job_multiplier(job_id: String) -> float:
	return mult("job:" + job_id) * mult("job:all") * morale_factor() * decay


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
		cost[res] = ceilf(b["cost"][res] * pow(b["scale"], count) * mult("build_cost"))
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
	halt_decay(HALT_PER_CLICK)
	return gained


# --- decay -----------------------------------------------------------------------

# Base decay per second near full production, growing with how far the civilisation has come.
func decay_rate() -> float:
	var total := 0.0
	for id in lifetime:
		total += lifetime[id]
	var keep := pow(DECAY_PER_DIGIT, DECAY_SCALING * log(total + 1.0) / log(10.0))
	keep *= pow(DECAY_PER_UPGRADE, DECAY_SCALING * maxf(sqrt(upgrades.size()) - 5.0, 0.0))
	keep *= pow(DECAY_PER_TIME_DOUBLING, DECAY_SCALING * log(maxf(run_time * 1000.0 - 100000.0, 1.0)) / log(2.0))
	return (1.0 - keep) * mult("decay")


# How much the current halt holds decay back: 1 = fully stopped.
func decay_hold() -> float:
	return minf(pow(decay_halt + decay_overtime * HALT_OVERTIME_POWER, 0.5), 1.0)


# Decay speeds up as production falls (the power grows from DECAY_MIN_POW toward 1).
func decay_per_second() -> float:
	var rate := minf(0.95, decay_rate() * decay_momentum)
	return 1.0 - pow(1.0 - rate, maxf(1.0 - decay, DECAY_MIN_POW) * (1.0 - decay_hold()))


func _run_decay(dt: float) -> void:
	run_time += dt
	if not decay_enabled:
		return
	var hold := decay_hold()
	decay = maxf(DECAY_FLOOR, decay * pow(1.0 - decay_per_second(), dt))
	decay_momentum = minf(MOMENTUM_MAX, decay_momentum + MOMENTUM_GROWTH * (1.0 - hold) * dt)
	if decay_halt > 0.0:
		decay_halt = maxf(0.0, decay_halt - HALT_FALL * dt)
		decay_overtime = maxf(0.0, decay_overtime - HALT_FALL * 0.5 * dt)
	else:
		decay_overtime = maxf(0.0, decay_overtime - HALT_FALL * dt)


func halt_decay(amount: float) -> void:
	decay_halt = maxf(decay_halt, amount)
	decay_overtime = minf(decay_halt * HALT_OVERTIME_LIMIT, decay_overtime + amount * HALT_KEEP)
	decay_momentum = 1.0 + (decay_momentum - 1.0) * MOMENTUM_CLICK_KEEP


# Multiplies production back up (capped at full) and calms momentum.
func purify(factor: float) -> void:
	decay = minf(1.0, decay * factor)
	decay_momentum = 1.0 + (decay_momentum - 1.0) * 0.5


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


# Most buildings bought in one go when you ask for "Max".
const MAX_BULK := 100000


# Total cost of the next n copies of a building.
func building_cost_bulk(id: String, n: int) -> Dictionary:
	var b := GameData.find("building", id)
	var count: int = buildings.get(id, 0)
	var scale: float = b["scale"]
	var cost := {}
	for res in b["cost"]:
		var first: float = b["cost"][res] * pow(scale, count) * mult("build_cost")
		cost[res] = ceilf(first * (pow(scale, n) - 1.0) / (scale - 1.0)) if scale != 1.0 else ceilf(first * n)
	return cost


# How many more copies you could buy right now (up to limit).
func affordable_buildings(id: String, limit: int = MAX_BULK) -> int:
	var b := GameData.find("building", id)
	if b.is_empty() or not building_available(b):
		return 0
	var lo := 0
	var hi := limit
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if can_afford(building_cost_bulk(id, mid)):
			lo = mid
		else:
			hi = mid - 1
	return lo


# Buys up to n copies (all you can afford if fewer). Returns how many were bought.
func buy_buildings(id: String, n: int) -> int:
	var b := GameData.find("building", id)
	if b.is_empty() or not building_available(b):
		return 0
	var k := affordable_buildings(id, n)
	if k <= 0 or not _pay(building_cost_bulk(id, k)):
		return 0
	buildings[id] = buildings.get(id, 0) + k
	_changed()
	return k


func unassign_all() -> void:
	for id in jobs:
		jobs[id] = 0
	_changed()


# Fills up to n free slots of a maker. Returns how many commissions started.
func start_commissions(maker_id: String, n: int) -> int:
	var started := 0
	while started < n and start_commission(maker_id):
		started += 1
	return started


func buy_upgrade(id: String) -> bool:
	var u := GameData.find("upgrade", id)
	if u.is_empty() or not upgrade_available(u) or not _pay(u["cost"]):
		return false
	upgrades[id] = true
	purify(1.15)
	post("Upgrade bought: %s" % u["name"])
	_changed()
	return true


func research(id: String) -> bool:
	var t := GameData.find("tech", id)
	if t.is_empty() or not tech_available(t) or not _pay(t["cost"]):
		return false
	techs[id] = true
	purify(100.0)
	decay_momentum = 1.0
	if t["unlocks"] != "":
		unlocked[t["unlocks"]] = true
	post("Discovered %s! %s" % [t["name"], t["desc"]])
	var era := EraData.for_resource(t["unlocks"])
	if not era.is_empty():
		post("A new age dawns: %s, %s." % [era["name"], era["subtitle"]])
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
	if GameData.find("maker", maker_id).is_empty() or paused_makers.has(maker_id):
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
		if paused_makers.has(c["maker"]):
			continue
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


# Paused makers stop crafting (work in progress waits) and take no new commissions.
func set_maker_paused(maker_id: String, paused: bool) -> void:
	if paused:
		paused_makers[maker_id] = true
	else:
		paused_makers.erase(maker_id)
	structure_changed.emit()


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


# --- war -------------------------------------------------------------------------

const TROOPS_PER_WARRIOR := 50.0


func war_unlocked() -> bool:
	return techs.has("warfare")


func era_index() -> int:
	return EraData.ERAS.find(EraData.current(unlocked))


# Warriors get better weapons every age: 50 troops each in the Clay age, doubling every age after.
func troops_per_warrior() -> float:
	return TROOPS_PER_WARRIOR * pow(2.0, maxi(0, era_index() - 2))


func army_size() -> float:
	return (WarData.BASE_ARMY + jobs.get("warrior", 0) * troops_per_warrior()) * mult("army:size")


func tier_complete(i: int) -> bool:
	for t in WarData.TIERS[i]["targets"]:
		if not conquered.has(t["id"]):
			return false
	return true


func tier_unlocked(i: int) -> bool:
	if not war_unlocked() or not is_unlocked(WarData.TIERS[i]["requires"]):
		return false
	return i == 0 or tier_complete(i - 1)


# The tier being fought over: the first unlocked, unfinished one (or the last unlocked one).
func current_tier() -> int:
	var best := 0
	for i in WarData.TIERS.size():
		if not tier_unlocked(i):
			break
		best = i
		if not tier_complete(i):
			return i
	return best


func kardashev() -> float:
	var value := 0.0
	for i in WarData.TIERS.size():
		var tier: Dictionary = WarData.TIERS[i]
		var done := 0
		for t in tier["targets"]:
			if conquered.has(t["id"]):
				done += 1
		if done > 0 or tier_unlocked(i):
			value = maxf(value, lerpf(tier["kardashev"][0], tier["kardashev"][1], float(done) / tier["targets"].size()))
	return value


func completed_tiers() -> int:
	var n := 0
	for i in WarData.TIERS.size():
		if tier_complete(i):
			n += 1
	return n


func can_attack(target_id: String) -> bool:
	var t := WarData.find_target(target_id)
	if t.is_empty() or conquered.has(target_id) or not pending_war.is_empty() or not tier_unlocked(t["tier"]):
		return false
	for n in WarData.neighbours(t["tier"], target_id):
		if n == "home" or conquered.has(n):
			return true
	return false


func war_cost() -> Dictionary:
	var cost := {"food": maxf(50.0, ceilf(amounts["food"] * 0.2))}
	var top := _biggest_stockpile()
	cost[top] = cost.get(top, 0.0) + maxf(50.0, ceilf(amounts.get(top, 0.0) * 0.1))
	return cost


# Starts a battle. Attacks you choose cost supplies; defending is free (and not optional).
func start_war(target_id: String, defensive := false) -> bool:
	if not defensive:
		if not can_attack(target_id) or not _pay(war_cost()):
			return false
		weariness += 10.0
	pending_war = {"target": target_id, "defensive": defensive}
	incoming_war = {}
	return true


# also: other nations wiped out in the same battle, conquered along with the target.
func finish_war(won: bool, also: Array = []) -> void:
	var t := WarData.find_target(pending_war.get("target", ""))
	var defensive: bool = pending_war.get("defensive", false)
	pending_war = {}
	if t.is_empty():
		return
	if not won:
		weariness += 25.0
		if defensive:
			for id in unlocked:
				amounts[id] *= 0.6
			var died := _kill_random(roundi(population * 0.25))
			var lost := _destroy_buildings(maxi(3, ceili(_building_count() * 0.1)))
			post("%s and their allies overran you. 40%% of every stockpile taken, %d dead, %d buildings burned." % [t["name"], died, lost])
		else:
			# They chase your broken army home.
			for id in unlocked:
				amounts[id] *= 0.85
			var died := _kill_random(roundi(population * 0.08))
			post("The war against %s failed. They followed you home: 15%% of every stockpile looted, %d dead." % [t["name"], died])
		_changed()
		return
	var tier_before := completed_tiers()
	conquered[t["id"]] = true
	for id in also:
		if not WarData.find_target(id).is_empty() and not conquered.has(id):
			conquered[id] = true
			post("%s fell in the same war. It's yours too." % WarData.find_target(id)["name"])
	var loot := {}
	for id in unlocked:
		var gain: float = production_per_second(id) * 180.0 + amounts[id] * 0.15
		if gain > 0.0:
			loot[id] = gain
			amounts[id] += gain
	post("Conquered %s! Loot: %s. Everything works 10%% harder and your army grows." % [t["name"], NumFormat.cost(loot)])
	if completed_tiers() > tier_before:
		var tier: Dictionary = WarData.TIERS[t["tier"]]
		post("You rule %s! Kardashev Type %.1f. Production doubles and the army grows 1.5x." % [tier["name"], tier["kardashev"][1]])
		if t["tier"] == WarData.TIERS.size() - 1:
			post("Kardashev Type VII. There is nothing left to conquer. You won.")
	_changed()


func _run_war_declarations(dt: float) -> void:
	if not war_unlocked() or not pending_war.is_empty():
		return
	if not incoming_war.is_empty():
		incoming_war["countdown"] -= dt
		return
	_declare_timer -= dt
	if _declare_timer > 0.0:
		return
	var speedup := maxf(0.5, 1.0 - WarData.DECLARE_SPEEDUP_PER_CONQUEST * conquered.size())
	_declare_timer = _rng.randf_range(WarData.DECLARE_MIN, WarData.DECLARE_MAX) * speedup
	var tier := current_tier()
	if not tier_unlocked(tier):
		return
	var pool: Array = []
	var total := 0.0
	for t in WarData.TIERS[tier]["targets"]:
		if not conquered.has(t["id"]) and can_attack(t["id"]):
			pool.append(t)
			total += t["aggression"]
	var pick := _rng.randf() * total
	for t in pool:
		pick -= t["aggression"]
		if pick <= 0.0:
			incoming_war = {"target": t["id"], "countdown": WarData.DECLARE_WARNING}
			var gang := WarData.coalition(t["id"], conquered, true).size() - 1
			post("WAR! %s has declared war on you%s! Their armies arrive in %d seconds." % [t["name"],
				" and %d others are joining them" % gang if gang > 0 else "", int(WarData.DECLARE_WARNING)])
			return


# --- rebirth -------------------------------------------------------------------

func legacy_gain() -> int:
	var gain := 0
	for id in unlocked:
		gain += GameData.ERA_LEGACY.get(id, 0)
	gain += conquered.size() * GameData.LEGACY_PER_CONQUEST + completed_tiers() * WarData.LEGACY_PER_TIER
	gain += deaths_legacy()
	return gain


# Grows with the number of digits: 100 deaths = 2 Legacy, 10,000 = 4, a million = 6.
func deaths_legacy() -> int:
	return int(log(run_deaths + 1.0) / log(10.0)) if run_deaths >= 10 else 0


func rebirth() -> int:
	var gain := legacy_gain()
	if gain <= 0:
		return 0
	legacy += gain
	runs += 1
	new_run()
	post("Your civilisation is reborn. +%d Legacy (%d total). Run %d begins." % [gain, legacy, runs + 1])
	return gain


func prestige_cost(id: String) -> int:
	var p := GameData.find("prestige", id)
	return int(p["cost"] * pow(p["growth"], prestige.get(id, 0)))


func can_buy_prestige(id: String) -> bool:
	var p := GameData.find("prestige", id)
	return not p.is_empty() and prestige.get(id, 0) < p["max"] and legacy >= prestige_cost(id)


func buy_prestige(id: String) -> bool:
	if not can_buy_prestige(id):
		return false
	legacy -= prestige_cost(id)
	prestige[id] = prestige.get(id, 0) + 1
	_changed()
	return true


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
		"paused_makers": paused_makers.keys(),
		"conquered": conquered.keys(),
		"consumables": consumables.duplicate(),
		"iq": iq,
		"run_deaths": run_deaths,
		"total_deaths": total_deaths,
		"legacy": legacy,
		"prestige": prestige.duplicate(),
		"runs": runs,
		"morale": morale,
		"decay": decay,
		"decay_momentum": decay_momentum,
		"run_time": run_time,
		"health": health,
		"grief": grief,
		"weariness": weariness,
		"events": events.duplicate(true),
		"event_timer": _event_timer,
		"incoming_war": incoming_war.duplicate(),
		"declare_timer": _declare_timer,
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
	iq = float(data.get("iq", BASE_IQ))
	morale = float(data.get("morale", START_MORALE))
	decay = clampf(float(data.get("decay", 1.0)), DECAY_FLOOR, 1.0)
	decay_momentum = clampf(float(data.get("decay_momentum", 1.0)), 1.0, MOMENTUM_MAX)
	run_time = float(data.get("run_time", 0.0))
	health = float(data.get("health", START_HEALTH))
	grief = float(data.get("grief", 0.0))
	weariness = float(data.get("weariness", 0.0))
	_event_timer = float(data.get("event_timer", EventData.MAX_GAP))
	_declare_timer = float(data.get("declare_timer", WarData.DECLARE_MAX))
	var saved_war: Dictionary = data.get("incoming_war", {})
	if not WarData.find_target(String(saved_war.get("target", ""))).is_empty():
		incoming_war = {"target": String(saved_war["target"]), "countdown": float(saved_war.get("countdown", WarData.DECLARE_WARNING))}
	for ev in data.get("events", []):
		if not EventData.find(String(ev.get("id", ""))).is_empty():
			events.append({"id": String(ev["id"]), "remaining": float(ev["remaining"]), "target": String(ev.get("target", ""))})
	run_deaths = int(data.get("run_deaths", 0))
	total_deaths = int(data.get("total_deaths", 0))
	legacy = int(data.get("legacy", 0))
	runs = int(data.get("runs", 0))
	var saved_prestige: Dictionary = data.get("prestige", {})
	for id in saved_prestige:
		if not GameData.find("prestige", id).is_empty():
			prestige[id] = int(saved_prestige[id])
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
		if not WarData.find_target(String(id)).is_empty():
			conquered[String(id)] = true
	var saved_crafted: Dictionary = data.get("crafted_count", {})
	for id in saved_crafted:
		crafted_count[id] = int(saved_crafted[id])
	for id in data.get("paused_makers", []):
		paused_makers[String(id)] = true
	_changed()
