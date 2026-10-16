class_name InvasionMap
extends RefCounted

const WATER := -2
const NEUTRAL := -1
const PLAYER := 0
const TERRAIN_COST := [0.0, 1.0, 1.6, 2.6]
const NEUTRAL_TILE_COST := 2.0
const ENEMY_TILE_COST := 4.0
const SPAWN_RADIUS := 3
const ENEMY_START_FRACTION := 0.6
const BASE_TROOPS := 100.0
const TROOPS_PER_TILE := 15.0
const REGEN_RATE := 0.04
const AI_MIN_THINK := 2.0
const AI_MAX_THINK := 5.0
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

enum Terrain { WATER, PLAINS, FOREST, MOUNTAIN }

var width := 0
var height := 0
var owners := PackedInt32Array()
var terrain := PackedByteArray()
# nation: {name, color, troops, tiles, troop_mult, regen_mult, attack_mult, aggression, ai_timer}
var nations: Array = []
# attack: {attacker, target, troops, progress}
var attacks: Array = []
var rng := RandomNumberGenerator.new()


# enemies: [{name, color, troop_mult, aggression}]; player: {name, color, troops, troop_mult, regen_mult, attack_mult}
func generate(w: int, h: int, seed_value: int, player: Dictionary, enemies: Array) -> void:
	width = w
	height = h
	rng.seed = seed_value
	owners.resize(w * h)
	terrain.resize(w * h)
	_generate_terrain(seed_value)

	nations.clear()
	attacks.clear()
	nations.append(_make_nation(player, 0.0))
	for e in enemies:
		nations.append(_make_nation(e, e.get("aggression", 0.3)))

	var spawns: Array = [Vector2i(int(w * 0.15), h / 2)]
	for k in enemies.size():
		spawns.append(Vector2i(int(w * 0.85), int(h * (k + 1) / float(enemies.size() + 1))))
	for idx in spawns.size():
		spawns[idx] = _nearest_land(spawns[idx])
		_ensure_connected(spawns[0], spawns[idx])
		_claim_disc(spawns[idx], SPAWN_RADIUS, idx)
	_recount()
	for idx in range(1, nations.size()):
		nations[idx]["troops"] = max_troops(idx) * ENEMY_START_FRACTION


func _make_nation(data: Dictionary, aggression: float) -> Dictionary:
	return {
		"name": data["name"],
		"color": data["color"],
		"troops": float(data.get("troops", 0.0)),
		"tiles": 0,
		"troop_mult": float(data.get("troop_mult", 1.0)),
		"regen_mult": float(data.get("regen_mult", 1.0)),
		"attack_mult": float(data.get("attack_mult", 1.0)),
		"aggression": aggression,
		"ai_timer": rng.randf_range(AI_MIN_THINK, AI_MAX_THINK),
	}


func _generate_terrain(seed_value: int) -> void:
	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.frequency = 0.05
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 1
	detail.frequency = 0.15
	for y in height:
		for x in width:
			var i := y * width + x
			var nx := x / float(width) * 2.0 - 1.0
			var ny := y / float(height) * 2.0 - 1.0
			var edge := maxf(absf(nx), absf(ny))
			var e := shape.get_noise_2d(x, y) * 0.6 + 0.35 - pow(edge, 4.0) * 0.9
			if e < 0.0:
				terrain[i] = Terrain.WATER
				owners[i] = WATER
				continue
			owners[i] = NEUTRAL
			if e > 0.6:
				terrain[i] = Terrain.MOUNTAIN
			elif detail.get_noise_2d(x, y) > 0.15:
				terrain[i] = Terrain.FOREST
			else:
				terrain[i] = Terrain.PLAINS


func _nearest_land(p: Vector2i) -> Vector2i:
	var best := p
	var best_d := INF
	for y in height:
		for x in width:
			if terrain[y * width + x] != Terrain.WATER:
				var d := Vector2(x - p.x, y - p.y).length_squared()
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	if best_d == INF:
		_set_land(p)
	return best


func _set_land(p: Vector2i) -> void:
	var i := p.y * width + p.x
	if terrain[i] == Terrain.WATER:
		terrain[i] = Terrain.PLAINS
		owners[i] = NEUTRAL


# Carves a plains path when water would cut two spawns off from each other.
func _ensure_connected(a: Vector2i, b: Vector2i) -> void:
	if a == b or _reachable(a, b):
		return
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for s in steps + 1:
		var t := s / float(maxi(steps, 1))
		var p := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		_set_land(p)
		if p.y + 1 < height:
			_set_land(Vector2i(p.x, p.y + 1))


func _reachable(a: Vector2i, b: Vector2i) -> bool:
	var seen := PackedByteArray()
	seen.resize(width * height)
	var queue: Array[Vector2i] = [a]
	seen[a.y * width + a.x] = 1
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if p == b:
			return true
		for d in DIRS:
			var q: Vector2i = p + d
			if in_bounds(q) and seen[q.y * width + q.x] == 0 and terrain[q.y * width + q.x] != Terrain.WATER:
				seen[q.y * width + q.x] = 1
				queue.append(q)
	return false


func _claim_disc(center: Vector2i, radius: int, nation: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p - center).length() <= radius + 0.5 and terrain[y * width + x] != Terrain.WATER:
				owners[y * width + x] = nation


func _recount() -> void:
	for n in nations:
		n["tiles"] = 0
	for o in owners:
		if o >= 0:
			nations[o]["tiles"] += 1


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func owner_at(p: Vector2i) -> int:
	return owners[p.y * width + p.x] if in_bounds(p) else WATER


func max_troops(nation: int) -> float:
	var n: Dictionary = nations[nation]
	return (BASE_TROOPS + n["tiles"] * TROOPS_PER_TILE) * n["troop_mult"]


func is_border(i: int) -> bool:
	var o := owners[i]
	var p := Vector2i(i % width, i / width)
	for d in DIRS:
		var q: Vector2i = p + d
		if in_bounds(q) and owners[q.y * width + q.x] != o:
			return true
	return false


func neighbours_of(nation: int) -> Dictionary:
	var result := {}
	for i in owners.size():
		if owners[i] != nation:
			continue
		var p := Vector2i(i % width, i / width)
		for d in DIRS:
			var q: Vector2i = p + d
			if in_bounds(q):
				var o := owners[q.y * width + q.x]
				if o != nation and o != WATER:
					result[o] = true
	return result


func is_alive(nation: int) -> bool:
	return nations[nation]["tiles"] > 0


# --- actions -----------------------------------------------------------------

func send_attack(attacker: int, target: int, fraction: float) -> bool:
	if target == attacker or target == WATER or not is_alive(attacker):
		return false
	if not neighbours_of(attacker).has(target):
		return false
	var amount: float = nations[attacker]["troops"] * clampf(fraction, 0.0, 1.0)
	if amount < 1.0:
		return false
	nations[attacker]["troops"] -= amount
	for a in attacks:
		if a["attacker"] == attacker and a["target"] == target:
			a["troops"] += amount
			return true
	attacks.append({"attacker": attacker, "target": target, "troops": amount, "progress": 0.0})
	return true


func troops_attacking(nation: int) -> float:
	var total := 0.0
	for a in attacks:
		if a["attacker"] == nation:
			total += a["troops"]
	return total


# --- simulation --------------------------------------------------------------

func tick(dt: float) -> void:
	for idx in nations.size():
		var n: Dictionary = nations[idx]
		if not is_alive(idx):
			n["troops"] = 0.0
			continue
		var cap := max_troops(idx)
		if n["troops"] < cap:
			n["troops"] = minf(cap, n["troops"] + (cap - n["troops"]) * REGEN_RATE * n["regen_mult"] * dt + n["tiles"] * 0.05 * dt)
		else:
			n["troops"] -= (n["troops"] - cap) * 0.02 * dt
		if idx != PLAYER:
			n["ai_timer"] -= dt
			if n["ai_timer"] <= 0.0:
				n["ai_timer"] = rng.randf_range(AI_MIN_THINK, AI_MAX_THINK)
				_ai_think(idx)
	_process_attacks(dt)


func _process_attacks(dt: float) -> void:
	var finished: Array = []
	for a in attacks:
		if not is_alive(a["attacker"]):
			finished.append(a)
			continue
		a["progress"] += (4.0 + a["troops"] / 25.0) * dt
		if a["progress"] < 1.0:
			continue
		var frontier := _frontier(a["attacker"], a["target"])
		if frontier.is_empty():
			finished.append(a)
			continue
		var attacker: Dictionary = nations[a["attacker"]]
		for i in frontier:
			if a["progress"] < 1.0:
				break
			if owners[i] != a["target"]:
				continue
			var cost: float = _tile_cost(i, a["target"]) / attacker["attack_mult"]
			if a["troops"] < cost:
				a["troops"] = 0.0
				break
			a["troops"] -= cost
			a["progress"] -= 1.0
			if a["target"] >= 0:
				var defender: Dictionary = nations[a["target"]]
				defender["troops"] = maxf(0.0, defender["troops"] - cost * 0.6)
				defender["tiles"] -= 1
			owners[i] = a["attacker"]
			attacker["tiles"] += 1
		a["progress"] = minf(a["progress"], 1.0)
		if a["troops"] < 1.0:
			finished.append(a)
	for a in finished:
		attacks.erase(a)
		if is_alive(a["attacker"]):
			nations[a["attacker"]]["troops"] += a["troops"]
	for a in attacks.duplicate():
		if a["target"] >= 0 and not is_alive(a["target"]):
			attacks.erase(a)
			nations[a["attacker"]]["troops"] += a["troops"]


func _tile_cost(i: int, target: int) -> float:
	var terrain_cost: float = TERRAIN_COST[terrain[i]]
	if target == NEUTRAL:
		return NEUTRAL_TILE_COST * terrain_cost
	var defender: Dictionary = nations[target]
	var density: float = defender["troops"] / maxf(1.0, defender["tiles"])
	return (ENEMY_TILE_COST + density * 0.8) * terrain_cost


# Target tiles touching the attacker, shuffled so fronts spread organically.
func _frontier(attacker: int, target: int) -> Array:
	var result: Array = []
	for i in owners.size():
		if owners[i] != target:
			continue
		var p := Vector2i(i % width, i / width)
		for d in DIRS:
			var q: Vector2i = p + d
			if in_bounds(q) and owners[q.y * width + q.x] == attacker:
				result.append(i)
				break
	result.shuffle()
	return result


func _ai_think(idx: int) -> void:
	var n: Dictionary = nations[idx]
	if n["troops"] < max_troops(idx) * 0.3:
		return
	var targets := neighbours_of(idx)
	var rivals: Array = []
	for t in targets:
		if t >= 0:
			rivals.append(t)
	if not rivals.is_empty() and rng.randf() < n["aggression"]:
		send_attack(idx, rivals[rng.randi() % rivals.size()], 0.4 + n["aggression"] * 0.3)
	elif targets.has(NEUTRAL):
		send_attack(idx, NEUTRAL, 0.3)


func status() -> String:
	if not is_alive(PLAYER):
		return "lost"
	for idx in range(1, nations.size()):
		if is_alive(idx):
			return "playing"
	return "won"


func land_share(nation: int) -> float:
	var land := 0
	for t in terrain:
		if t != Terrain.WATER:
			land += 1
	return nations[nation]["tiles"] / float(maxi(land, 1))
