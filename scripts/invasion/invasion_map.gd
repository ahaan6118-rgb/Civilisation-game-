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
# You start small: each of your lands is a tiny foothold next to big, established enemies.
const PLAYER_SPAWN_RADIUS := 3
const ENEMY_SPAWN_RADIUS := 7
# Minor factions: lots of small tribes, clans and outposts filling the rest of the map.
const MINOR_MIN_RADIUS := 1
const MINOR_MAX_RADIUS := 3
const MINOR_MIN_GAP := 6
enum Team { PLAYER, HOSTILE, BYSTANDER }
# Hostile AIs hit you this often when they border you; bystanders join in when you look weak.
const GANG_UP_CHANCE := 0.8
const OPPORTUNIST_RATIO := 1.2
const EXPAND_FIRST := 0.8
const MINOR_COLORS := [Color(0.75, 0.55, 0.45), Color(0.55, 0.65, 0.5), Color(0.65, 0.6, 0.75), Color(0.8, 0.7, 0.5),
	Color(0.5, 0.6, 0.7), Color(0.7, 0.5, 0.6), Color(0.6, 0.7, 0.65), Color(0.75, 0.65, 0.65)]

enum Terrain { WATER, PLAINS, FOREST, MOUNTAIN }

var width := 0
var height := 0
var owners := PackedInt32Array()
var terrain := PackedByteArray()
# nation: {name, color, troops, tiles, troop_mult, regen_mult, attack_mult, aggression, ai_timer, team, id, objective,
#          minor, sum (total of tile positions, for the label)}
var nations: Array = []
# attack: {attacker, target, troops, progress, frontier: Array of tile indices}
var attacks: Array = []
# Factions that turned on you this battle (names), for the HUD.
var joined: Array = []
# Tiles whose colour changed since the view last looked; the view empties it.
var dirty := PackedInt32Array()
var rng := RandomNumberGenerator.new()
var _land := 0
# Land costs scale with the map's troop strength so strong tiers don't expand absurdly fast.
var cost_scale := 1.0
# nation -> {tile: true} for its tiles that touch anything else. Kept up to date on every capture,
# so nothing has to scan the whole map while the battle runs.
var _border: Array = []


# enemies: [{name, color, troop_mult, aggression, team?, id?, objective?, pos? [0..1, 0..1]}]
# player: {name, color, troops, troop_mult, regen_mult, attack_mult, spawns? [[x, y], ...] in 0..1}
# minors: how many small factions to scatter over the map, each with troop_mult minor_strength x 0.3..0.9.
func generate(w: int, h: int, seed_value: int, player: Dictionary, enemies: Array,
		minors := 0, minor_strength := 1.0, name_style := "land") -> void:
	width = w
	height = h
	cost_scale = maxf(1.0, minor_strength) if minors > 0 else 1.0
	rng.seed = seed_value
	owners.resize(w * h)
	terrain.resize(w * h)
	_generate_terrain(seed_value)
	var main_land := _keep_largest_landmass()

	nations.clear()
	attacks.clear()
	joined.clear()
	nations.append(_make_nation(player, 0.0))
	nations[PLAYER]["team"] = Team.PLAYER
	for e in enemies:
		nations.append(_make_nation(e, e.get("aggression", 0.3)))
	var big := enemies.size() > 2 or minors > 0

	var taken: Array = []
	var player_spots: Array = player.get("spawns", [[0.15, 0.5]])
	for p in player_spots:
		var spawn := _nearest_land(_to_tile(p))
		taken.append(spawn)
		_claim_disc(spawn, PLAYER_SPAWN_RADIUS if big else SPAWN_RADIUS, PLAYER)
	for k in enemies.size():
		var pos: Array = enemies[k].get("pos", [0.85, (k + 1) / float(enemies.size() + 1)])
		var spawn := _nearest_land(_to_tile(pos))
		taken.append(spawn)
		_claim_disc(spawn, ENEMY_SPAWN_RADIUS if big else SPAWN_RADIUS, k + 1)
	# Your footholds keep their centres even if a neighbour's land was drawn over them.
	for k in player_spots.size():
		var c: Vector2i = taken[k]
		owners[c.y * width + c.x] = PLAYER
	_spawn_minors(minors, minor_strength, name_style, main_land, taken)
	_recount()
	for idx in range(1, nations.size()):
		nations[idx]["troops"] = max_troops(idx) * ENEMY_START_FRACTION


func _to_tile(p: Array) -> Vector2i:
	return Vector2i(clampi(int(p[0] * width), 1, width - 2), clampi(int(p[1] * height), 1, height - 2))


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
		"team": int(data.get("team", Team.HOSTILE)),
		"id": String(data.get("id", "")),
		"objective": bool(data.get("objective", false)),
		"minor": bool(data.get("minor", false)),
		"sum": Vector2.ZERO,
	}


func _generate_terrain(seed_value: int) -> void:
	# Noise frequency follows the map size so a big map gets continents, not static.
	var scale := 96.0 / maxf(width, 1.0)
	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.frequency = 0.05 * scale
	shape.fractal_octaves = 5
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 1
	detail.frequency = 0.15 * scale
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


# Sinks every island but the biggest so every faction can reach every other. Returns that landmass's tiles.
func _keep_largest_landmass() -> PackedInt32Array:
	var label := PackedInt32Array()
	label.resize(width * height)
	label.fill(-1)
	var best := PackedInt32Array()
	var current := 0
	for start in owners.size():
		if terrain[start] == Terrain.WATER or label[start] != -1:
			continue
		var tiles := PackedInt32Array([start])
		label[start] = current
		var head := 0
		while head < tiles.size():
			var i := tiles[head]
			head += 1
			for j in _adjacent(i):
				if label[j] == -1 and terrain[j] != Terrain.WATER:
					label[j] = current
					tiles.append(j)
		if tiles.size() > best.size():
			best = tiles
		current += 1
	if best.is_empty():
		# No land at all: make a plain so the battle can still happen.
		for i in owners.size():
			terrain[i] = Terrain.PLAINS
			owners[i] = NEUTRAL
			best.append(i)
		return best
	var keep := label[best[0]]
	for i in owners.size():
		if terrain[i] != Terrain.WATER and label[i] != keep:
			terrain[i] = Terrain.WATER
			owners[i] = WATER
	return best


# Closest land tile, searching outward ring by ring.
func _nearest_land(p: Vector2i) -> Vector2i:
	for r in maxi(width, height):
		for y in range(p.y - r, p.y + r + 1):
			for x in range(p.x - r, p.x + r + 1):
				if maxi(absi(x - p.x), absi(y - p.y)) != r:
					continue
				if in_bounds(Vector2i(x, y)) and terrain[y * width + x] != Terrain.WATER:
					return Vector2i(x, y)
	return p


func _claim_disc(center: Vector2i, radius: int, nation: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p - center).length() <= radius + 0.5 and terrain[y * width + x] != Terrain.WATER:
				owners[y * width + x] = nation


func _spawn_minors(count: int, strength: float, style: String, land: PackedInt32Array, taken: Array) -> void:
	var tries := 0
	while count > 0 and tries < count * 20 and not land.is_empty():
		tries += 1
		var i := land[rng.randi() % land.size()]
		if owners[i] != NEUTRAL:
			continue
		var p := Vector2i(i % width, i / width)
		var crowded := false
		for t in taken:
			if Vector2(t - p).length() < MINOR_MIN_GAP:
				crowded = true
				break
		if crowded:
			continue
		taken.append(p)
		var idx := nations.size()
		var color: Color = MINOR_COLORS[rng.randi() % MINOR_COLORS.size()]
		nations.append(_make_nation({"name": FactionNames.make(style, rng), "minor": true, "team": Team.BYSTANDER,
			"color": color.lightened(rng.randf_range(-0.15, 0.15)),
			"troop_mult": strength * rng.randf_range(0.3, 0.9)}, rng.randf_range(0.1, 0.5)))
		_claim_disc(p, rng.randi_range(MINOR_MIN_RADIUS, MINOR_MAX_RADIUS), idx)
		count -= 1


# Rebuilds every count, border and label position from `owners`. Call after editing owners directly.
func _recount() -> void:
	_land = 0
	_border.clear()
	for n in nations:
		n["tiles"] = 0
		n["sum"] = Vector2.ZERO
		_border.append({})
	for i in owners.size():
		var o := owners[i]
		if o == WATER:
			continue
		_land += 1
		if o >= 0:
			nations[o]["tiles"] += 1
			nations[o]["sum"] += Vector2(i % width, i / width)
			if is_border(i):
				_border[o][i] = true
	for a in attacks:
		a["frontier"] = _build_frontier(a["attacker"], a["target"])


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func owner_at(p: Vector2i) -> int:
	return owners[p.y * width + p.x] if in_bounds(p) else WATER


func max_troops(nation: int) -> float:
	var n: Dictionary = nations[nation]
	return (BASE_TROOPS + n["tiles"] * TROOPS_PER_TILE) * n["troop_mult"]


func is_border(i: int) -> bool:
	var o := owners[i]
	var x := i % width
	if x > 0 and owners[i - 1] != o:
		return true
	if x + 1 < width and owners[i + 1] != o:
		return true
	if i >= width and owners[i - width] != o:
		return true
	if i + width < owners.size() and owners[i + width] != o:
		return true
	return false


func _adjacent(i: int) -> PackedInt32Array:
	var x := i % width
	var result := PackedInt32Array()
	if x > 0:
		result.append(i - 1)
	if x + 1 < width:
		result.append(i + 1)
	if i >= width:
		result.append(i - width)
	if i + width < owners.size():
		result.append(i + width)
	return result


func neighbours_of(nation: int) -> Dictionary:
	var result := {}
	if nation < 0 or nation >= _border.size():
		return result
	for i in _border[nation]:
		for j in _adjacent(i):
			var o := owners[j]
			if o != nation and o != WATER:
				result[o] = true
	return result


func is_alive(nation: int) -> bool:
	return nations[nation]["tiles"] > 0


func is_hostile(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return true
	var ta: int = nations[a]["team"]
	var tb: int = nations[b]["team"]
	if ta == Team.PLAYER or tb == Team.PLAYER:
		return ta != tb and (ta == Team.HOSTILE or tb == Team.HOSTILE)
	# Enemies in the coalition don't fight each other; everyone else squabbles freely.
	return not (ta == Team.HOSTILE and tb == Team.HOSTILE)


# --- actions -----------------------------------------------------------------

func send_attack(attacker: int, target: int, fraction: float) -> bool:
	if target == attacker or target == WATER or not is_alive(attacker):
		return false
	if not neighbours_of(attacker).has(target):
		return false
	var amount: float = nations[attacker]["troops"] * clampf(fraction, 0.0, 1.0)
	if amount < 1.0:
		return false
	if target >= 0 and attacker == PLAYER and not is_hostile(PLAYER, target):
		# Attacking a bystander drags them into the war.
		_join_war(target)
	nations[attacker]["troops"] -= amount
	for a in attacks:
		if a["attacker"] == attacker and a["target"] == target:
			a["troops"] += amount
			return true
	attacks.append({"attacker": attacker, "target": target, "troops": amount, "progress": 0.0,
		"frontier": _build_frontier(attacker, target)})
	return true


func troops_attacking(nation: int) -> float:
	var total := 0.0
	for a in attacks:
		if a["attacker"] == nation:
			total += a["troops"]
	return total


# Target tiles touching the attacker.
func _build_frontier(attacker: int, target: int) -> Array:
	var seen := {}
	for i in _border[attacker]:
		for j in _adjacent(i):
			if owners[j] == target:
				seen[j] = true
	return seen.keys()


# --- simulation --------------------------------------------------------------

func tick(dt: float) -> void:
	for idx in nations.size():
		var n: Dictionary = nations[idx]
		if n["tiles"] <= 0:
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
		if not is_alive(a["attacker"]) or (a["target"] >= 0 and not is_alive(a["target"])):
			finished.append(a)
			continue
		a["progress"] += (4.0 + a["troops"] / 25.0) * dt
		var attacker: Dictionary = nations[a["attacker"]]
		var frontier: Array = a["frontier"]
		while a["progress"] >= 1.0 and not frontier.is_empty():
			# A random frontier tile, so fronts spread organically.
			var k := rng.randi() % frontier.size()
			var i: int = frontier[k]
			frontier[k] = frontier[frontier.size() - 1]
			frontier.pop_back()
			if owners[i] != a["target"] or not _touches(i, a["attacker"]):
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
			_capture(i, a["attacker"])
			for j in _adjacent(i):
				if owners[j] == a["target"]:
					frontier.append(j)
		a["progress"] = minf(a["progress"], 1.0)
		if frontier.is_empty():
			# The front may have moved (the target took land next to us); look once more.
			a["frontier"] = _build_frontier(a["attacker"], a["target"])
			if a["frontier"].is_empty():
				finished.append(a)
				continue
		if a["troops"] < 1.0:
			finished.append(a)
	for a in finished:
		attacks.erase(a)
		if is_alive(a["attacker"]):
			nations[a["attacker"]]["troops"] += a["troops"]


func _touches(i: int, nation: int) -> bool:
	for j in _adjacent(i):
		if owners[j] == nation:
			return true
	return false


func _capture(i: int, nation: int) -> void:
	var old := owners[i]
	var p := Vector2(i % width, i / width)
	if old >= 0:
		nations[old]["tiles"] -= 1
		nations[old]["sum"] -= p
		_border[old].erase(i)
	owners[i] = nation
	nations[nation]["tiles"] += 1
	nations[nation]["sum"] += p
	dirty.append(i)
	_refresh_tile(i)
	for j in _adjacent(i):
		_refresh_tile(j)
		dirty.append(j)


func _refresh_tile(i: int) -> void:
	var o := owners[i]
	if o < 0:
		return
	if is_border(i):
		_border[o][i] = true
	else:
		_border[o].erase(i)


func _tile_cost(i: int, target: int) -> float:
	var terrain_cost: float = TERRAIN_COST[terrain[i]]
	if target == NEUTRAL:
		return NEUTRAL_TILE_COST * cost_scale * terrain_cost
	var defender: Dictionary = nations[target]
	var density: float = defender["troops"] / maxf(1.0, defender["tiles"])
	return (ENEMY_TILE_COST * cost_scale + density * 0.8) * terrain_cost


func _join_war(idx: int) -> void:
	var n: Dictionary = nations[idx]
	if n["team"] != Team.BYSTANDER:
		return
	n["team"] = Team.HOSTILE
	n["aggression"] = maxf(n["aggression"], 0.6)
	joined.append(n["name"])


func _ai_think(idx: int) -> void:
	var n: Dictionary = nations[idx]
	if n["troops"] < max_troops(idx) * 0.3:
		return
	var targets := neighbours_of(idx)
	var you: Dictionary = nations[PLAYER]
	# Bystanders smell weakness: if you border them and they outnumber you, they may pile on.
	if n["team"] == Team.BYSTANDER and targets.has(PLAYER) and n["troops"] > you["troops"] * OPPORTUNIST_RATIO \
			and rng.randf() < n["aggression"] * 0.25:
		_join_war(idx)
	if n["team"] == Team.HOSTILE and targets.has(PLAYER) and rng.randf() < GANG_UP_CHANCE:
		send_attack(idx, PLAYER, 0.4 + n["aggression"] * 0.4)
		return
	# While there's free land, most factions grab it before picking fights (like openfront's bots).
	if targets.has(NEUTRAL) and rng.randf() < EXPAND_FIRST:
		send_attack(idx, NEUTRAL, 0.3)
		return
	var rivals: Array = []
	for t in targets:
		if t >= 0 and is_hostile(idx, t):
			rivals.append(t)
	if not rivals.is_empty() and rng.randf() < n["aggression"]:
		send_attack(idx, rivals[rng.randi() % rivals.size()], 0.4 + n["aggression"] * 0.3)
	elif targets.has(NEUTRAL):
		send_attack(idx, NEUTRAL, 0.3)


# Won when the nation you went to war over (the objective) falls, or when every hostile nation is gone.
func status() -> String:
	if not is_alive(PLAYER):
		return "lost"
	var any_hostile := false
	for idx in range(1, nations.size()):
		if nations[idx]["objective"] and not is_alive(idx):
			return "won"
		if nations[idx]["team"] == Team.HOSTILE and is_alive(idx):
			any_hostile = true
	return "playing" if any_hostile else "won"


func land_share(nation: int) -> float:
	return nations[nation]["tiles"] / float(maxi(_land, 1))


# Middle of a nation's land; if that spot belongs to someone else (land in several pieces),
# the nation's own border tile closest to it.
func label_pos(nation: int) -> Vector2:
	var n: Dictionary = nations[nation]
	var mid: Vector2 = n["sum"] / maxf(1.0, n["tiles"])
	if nation != PLAYER or owner_at(Vector2i(mid)) == nation:
		return mid + Vector2(0.5, 0.5)
	var best := mid
	var best_d := INF
	for i in _border[nation]:
		var p := Vector2(i % width, i / width)
		var d := p.distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = p
	return best + Vector2(0.5, 0.5)
