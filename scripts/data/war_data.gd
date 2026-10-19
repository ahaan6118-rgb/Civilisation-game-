class_name WarData
extends RefCounted

const BASE_ARMY := 300.0
const LEGACY_PER_TIER := 5
const NEIGHBOUR_RANGE := 0.42
# Neighbours declare war every DECLARE_MIN..DECLARE_MAX seconds while you play (once Warfare is known).
const DECLARE_MIN := 180.0
const DECLARE_MAX := 360.0
const DECLARE_WARNING := 20.0
# Every land you take scares the rest: they declare this much sooner each conquest (down to half).
const DECLARE_SPEEDUP_PER_CONQUEST := 0.1
# Nations this aggressive always join a war against you on their map.
const ALWAYS_JOIN_AGGRESSION := 0.5
# Most consumables you can use in one battle.
const BATTLE_ITEM_LIMIT := 3

# Each conquest makes this run permanently stronger; finishing a tier does more.
const CONQUEST_EFFECTS := [{"key": "job:all", "mult": 1.1}, {"key": "army:size", "mult": 1.15}]
const TIER_EFFECTS := [{"key": "job:all", "mult": 2.0}, {"key": "army:size", "mult": 1.5}]

# Map tiers, climbing the Kardashev scale. Positions are 0..1 on the world map; "home" is where you start.
#   strength:  enemy troops multiplier for the tier (each target's "power" scales it further)
#   style:     battle map look (land, space, void)
#   kardashev: [value at start, value when every target is conquered]
const TIERS := [
	{"id": "valley", "name": "The Valley", "requires": "clay", "style": "land", "unit": "warriors",
		"strength": 1.0, "kardashev": [0.0, 0.3], "home": [0.12, 0.5], "home_name": "Your Tribe",
		"targets": [
			{"id": "ugs_tribe", "name": "Ug's Tribe", "pos": [0.32, 0.32], "power": 0.6, "aggression": 0.2, "desc": "A small tribe next door that throws rocks."},
			{"id": "the_mudlands", "name": "The Mudlands", "pos": [0.32, 0.72], "power": 1.0, "aggression": 0.35, "desc": "A swampy people who really like mud."},
			{"id": "hill_folk", "name": "The Hill Folk", "pos": [0.55, 0.5], "power": 1.1, "aggression": 0.4, "desc": "They live on hills. They are smug about it."},
			{"id": "river_clans", "name": "River Clans", "pos": [0.75, 0.25], "power": 1.2, "aggression": 0.3, "desc": "Fishermen who fight with harpoons."},
			{"id": "cave_kings", "name": "The Cave Kings", "pos": [0.8, 0.72], "power": 1.5, "aggression": 0.5, "desc": "The biggest, angriest tribe in the valley."},
		]},
	{"id": "continent", "name": "The Continent", "requires": "bronze", "style": "land", "unit": "soldiers",
		"strength": 8.0, "kardashev": [0.3, 0.7], "home": [0.15, 0.55], "home_name": "Your Kingdom",
		"targets": [
			{"id": "copper_clans", "name": "Copper Hill Clans", "pos": [0.3, 0.3], "power": 0.7, "aggression": 0.4, "desc": "Two clans fighting over shiny hills."},
			{"id": "tin_league", "name": "The Tin Traders' League", "pos": [0.32, 0.78], "power": 0.9, "aggression": 0.25, "desc": "They own all the tin. Bronze needs tin."},
			{"id": "bronze_kingdom", "name": "The Bronze Kingdom", "pos": [0.52, 0.52], "power": 1.1, "aggression": 0.5, "desc": "A proper kingdom with a king and everything."},
			{"id": "horse_lords", "name": "The Horse Lords", "pos": [0.68, 0.22], "power": 1.2, "aggression": 0.6, "desc": "Fast riders from the endless steppe."},
			{"id": "ur_kesh", "name": "The Walled City of Ur-Kesh", "pos": [0.72, 0.75], "power": 1.3, "aggression": 0.3, "desc": "Behind very tall walls."},
			{"id": "iron_empire", "name": "The Iron Empire", "pos": [0.88, 0.48], "power": 1.8, "aggression": 0.6, "desc": "Iron-clad and hates everyone."},
		]},
	{"id": "world", "name": "The World", "requires": "steel", "style": "land", "unit": "armies",
		"strength": 120.0, "kardashev": [0.7, 1.0], "home": [0.18, 0.4], "home_name": "Your Nation",
		"targets": [
			{"id": "northern_federation", "name": "The Northern Federation", "pos": [0.35, 0.18], "power": 0.8, "aggression": 0.4, "desc": "Cold, stubborn and well armed."},
			{"id": "desert_caliphate", "name": "The Desert Caliphate", "pos": [0.38, 0.62], "power": 0.9, "aggression": 0.35, "desc": "Rich from sand-buried oil."},
			{"id": "island_shogunate", "name": "The Island Shogunate", "pos": [0.6, 0.35], "power": 1.1, "aggression": 0.4, "desc": "A nation of islands and very sharp swords."},
			{"id": "southern_republic", "name": "The Southern Republic", "pos": [0.55, 0.82], "power": 1.0, "aggression": 0.3, "desc": "They vote on everything, including war."},
			{"id": "great_khanate", "name": "The Great Khanate", "pos": [0.78, 0.6], "power": 1.3, "aggression": 0.6, "desc": "The largest land empire ever. So far."},
			{"id": "empire_of_the_sun", "name": "The Empire of the Sun", "pos": [0.85, 0.22], "power": 1.7, "aggression": 0.5, "desc": "The last great power standing between you and the planet."},
		]},
	{"id": "solar_system", "name": "The Solar System", "requires": "silicon", "style": "space", "unit": "fleets",
		"strength": 1500.0, "kardashev": [1.0, 2.0], "home": [0.12, 0.5], "home_name": "Earth",
		"targets": [
			{"id": "luna", "name": "Luna Colony", "pos": [0.28, 0.35], "power": 0.6, "aggression": 0.3, "desc": "The Moon declared independence. Rude."},
			{"id": "mars", "name": "Mars Colony", "pos": [0.38, 0.68], "power": 0.9, "aggression": 0.45, "desc": "Red planet, red tempers."},
			{"id": "venus", "name": "Venus Cloud Cities", "pos": [0.55, 0.3], "power": 1.0, "aggression": 0.3, "desc": "Floating cities above an acid ocean."},
			{"id": "jovian_moons", "name": "The Jovian Moons", "pos": [0.65, 0.65], "power": 1.2, "aggression": 0.4, "desc": "Four moons, one grudge."},
			{"id": "ring_miners", "name": "The Saturn Ring Miners", "pos": [0.8, 0.38], "power": 1.3, "aggression": 0.5, "desc": "They throw asteroids."},
			{"id": "neptune_deep", "name": "Neptune Deep", "pos": [0.9, 0.7], "power": 1.7, "aggression": 0.4, "desc": "Something lives under the ice."},
		]},
	{"id": "galaxy", "name": "The Galaxy", "requires": "antimatter", "style": "space", "unit": "armadas",
		"strength": 12000.0, "kardashev": [2.0, 3.0], "home": [0.15, 0.6], "home_name": "Sol",
		"targets": [
			{"id": "centauri_pact", "name": "The Alpha Centauri Pact", "pos": [0.3, 0.4], "power": 0.7, "aggression": 0.4, "desc": "Our nearest neighbours. Not friendly."},
			{"id": "vega_dominion", "name": "The Vega Dominion", "pos": [0.35, 0.78], "power": 0.9, "aggression": 0.5, "desc": "They want everything Vega-shaped."},
			{"id": "hive_of_cygnus", "name": "The Hive of Cygnus", "pos": [0.55, 0.25], "power": 1.1, "aggression": 0.7, "desc": "Billions of bugs with one mind."},
			{"id": "orion_hegemony", "name": "The Orion Hegemony", "pos": [0.6, 0.6], "power": 1.2, "aggression": 0.4, "desc": "An old empire of very tall aliens."},
			{"id": "perseus_arm", "name": "The Perseus Arm Collective", "pos": [0.8, 0.35], "power": 1.3, "aggression": 0.4, "desc": "A whole spiral arm, united."},
			{"id": "galactic_core", "name": "The Galactic Core AI", "pos": [0.85, 0.75], "power": 1.8, "aggression": 0.6, "desc": "It has been waiting for you."},
		]},
	{"id": "universe", "name": "The Universe", "requires": "dark_matter", "style": "space", "unit": "fleets of fleets",
		"strength": 40000.0, "kardashev": [3.0, 4.0], "home": [0.12, 0.45], "home_name": "The Milky Way",
		"targets": [
			{"id": "andromeda", "name": "Andromeda", "pos": [0.3, 0.3], "power": 0.8, "aggression": 0.5, "desc": "Was going to crash into us anyway."},
			{"id": "magellanic_clouds", "name": "The Magellanic Clouds", "pos": [0.3, 0.72], "power": 0.7, "aggression": 0.3, "desc": "Two small galaxies with big dreams."},
			{"id": "triangulum_swarm", "name": "The Triangulum Swarm", "pos": [0.52, 0.5], "power": 1.1, "aggression": 0.6, "desc": "A galaxy eaten by machines."},
			{"id": "void_leviathans", "name": "The Void Leviathans", "pos": [0.7, 0.25], "power": 1.3, "aggression": 0.5, "desc": "Creatures that swim between galaxies."},
			{"id": "quasar_lords", "name": "The Quasar Lords", "pos": [0.72, 0.75], "power": 1.4, "aggression": 0.4, "desc": "They live inside the brightest things in existence."},
			{"id": "great_attractor", "name": "The Great Attractor", "pos": [0.9, 0.5], "power": 1.8, "aggression": 0.5, "desc": "Everything gets pulled toward it. Now you know why."},
		]},
	{"id": "multiverse", "name": "The Multiverse", "requires": "dark_matter", "style": "void", "unit": "realities",
		"strength": 3e5, "kardashev": [4.0, 5.0], "home": [0.12, 0.5], "home_name": "Our Universe",
		"targets": [
			{"id": "cheese_universe", "name": "The Cheese Universe", "pos": [0.3, 0.3], "power": 0.6, "aggression": 0.2, "desc": "Everything is cheese. Everything."},
			{"id": "dinosaur_universe", "name": "The Universe Where Dinosaurs Won", "pos": [0.32, 0.72], "power": 1.0, "aggression": 0.6, "desc": "They have lasers now."},
			{"id": "paper_dimension", "name": "The Paper Dimension", "pos": [0.52, 0.5], "power": 0.9, "aggression": 0.3, "desc": "Flat, fragile, and furious."},
			{"id": "clockwork_cosmos", "name": "The Clockwork Cosmos", "pos": [0.7, 0.25], "power": 1.2, "aggression": 0.4, "desc": "Every star is a gear."},
			{"id": "mirror_universe", "name": "The Mirror Universe", "pos": [0.72, 0.75], "power": 1.4, "aggression": 0.5, "desc": "Everyone has a goatee here."},
			{"id": "evil_twin", "name": "Your Evil Twin's Universe", "pos": [0.9, 0.5], "power": 1.8, "aggression": 0.7, "desc": "They did everything you did, but meaner."},
		]},
	{"id": "omniverse", "name": "The Omniverse", "requires": "dark_matter", "style": "void", "unit": "concepts",
		"strength": 1.5e6, "kardashev": [5.0, 6.0], "home": [0.12, 0.5], "home_name": "The Multiverse",
		"targets": [
			{"id": "dream_realms", "name": "The Dream Realms", "pos": [0.3, 0.32], "power": 0.8, "aggression": 0.3, "desc": "Where everyone goes when they sleep."},
			{"id": "infinite_library", "name": "The Infinite Library", "pos": [0.32, 0.72], "power": 0.9, "aggression": 0.2, "desc": "Every book that could ever be written. Shh."},
			{"id": "realm_of_forms", "name": "The Realm of Forms", "pos": [0.52, 0.5], "power": 1.1, "aggression": 0.4, "desc": "The perfect version of every chair."},
			{"id": "timeless_expanse", "name": "The Timeless Expanse", "pos": [0.7, 0.25], "power": 1.3, "aggression": 0.4, "desc": "It has always been at war with you."},
			{"id": "the_static", "name": "The Static", "pos": [0.72, 0.75], "power": 1.4, "aggression": 0.6, "desc": "The noise between everything."},
			{"id": "last_light", "name": "The Last Light", "pos": [0.9, 0.5], "power": 1.8, "aggression": 0.5, "desc": "The final thing that will ever shine."},
		]},
	{"id": "beyond", "name": "Beyond", "requires": "dark_matter", "style": "void", "unit": "ideas",
		"strength": 5e6, "kardashev": [6.0, 7.0], "home": [0.15, 0.5], "home_name": "Everything",
		"targets": [
			{"id": "the_architects", "name": "The Architects", "pos": [0.45, 0.3], "power": 1.0, "aggression": 0.4, "desc": "The ones who built existence."},
			{"id": "the_writer", "name": "The Writer", "pos": [0.45, 0.72], "power": 1.3, "aggression": 0.3, "desc": "Someone is writing all of this down."},
			{"id": "the_void_itself", "name": "The Void Itself", "pos": [0.82, 0.5], "power": 2.0, "aggression": 0.6, "desc": "Conquer nothing, and you have conquered everything."},
		]},
]

const STYLES := {
	"land": {"colors": [Color(0.16, 0.3, 0.5), Color(0.47, 0.63, 0.32), Color(0.26, 0.45, 0.23), Color(0.52, 0.5, 0.47)],
		"names": ["Water", "Plains", "Forest", "Mountains"], "background": Color(0.1, 0.12, 0.16)},
	"space": {"colors": [Color(0.01, 0.01, 0.04), Color(0.08, 0.1, 0.22), Color(0.3, 0.12, 0.38), Color(0.42, 0.4, 0.4)],
		"names": ["Deep Void", "Open Space", "Nebula", "Asteroid Field"], "background": Color(0.0, 0.0, 0.02)},
	"void": {"colors": [Color(0.0, 0.0, 0.0), Color(0.1, 0.35, 0.35), Color(0.55, 0.2, 0.45), Color(0.9, 0.9, 0.85)],
		"names": ["Nothingness", "Reality", "Dreamstuff", "Paradox"], "background": Color(0.02, 0.0, 0.03)},
}

static var _targets: Dictionary = {}


static func find_target(id: String) -> Dictionary:
	if _targets.is_empty():
		for i in TIERS.size():
			for t in TIERS[i]["targets"]:
				var entry: Dictionary = t.duplicate()
				entry["tier"] = i
				_targets[t["id"]] = entry
	return _targets.get(id, {})


# Targets (and "home") within NEIGHBOUR_RANGE of each other are neighbours; isolated ones link to their nearest.
static func neighbours(tier_index: int, node_id: String) -> Array:
	var tier: Dictionary = TIERS[tier_index]
	var nodes := {"home": Vector2(tier["home"][0], tier["home"][1])}
	for t in tier["targets"]:
		nodes[t["id"]] = Vector2(t["pos"][0], t["pos"][1])
	var me: Vector2 = nodes[node_id]
	var result: Array = []
	var nearest := ""
	for id in nodes:
		if id == node_id:
			continue
		var d := me.distance_to(nodes[id])
		if d <= NEIGHBOUR_RANGE:
			result.append(id)
		if nearest == "" or d < me.distance_to(nodes[nearest]):
			nearest = id
	if result.is_empty():
		result.append(nearest)
	return result


# Who fights you when you go to war with target_id: the target plus every unconquered neighbour of it
# (they gang up), and when you're the one attacked, every aggressive nation on the map as well.
static func coalition(target_id: String, conquered: Dictionary, defensive: bool) -> Array:
	var t := find_target(target_id)
	if t.is_empty():
		return []
	var result: Array = [target_id]
	for n in neighbours(t["tier"], target_id):
		if n != "home" and not conquered.has(n) and not result.has(n):
			result.append(n)
	if defensive:
		for other in TIERS[t["tier"]]["targets"]:
			if other["aggression"] >= ALWAYS_JOIN_AGGRESSION and not conquered.has(other["id"]) and not result.has(other["id"]):
				result.append(other["id"])
	return result
