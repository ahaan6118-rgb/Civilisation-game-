class_name EraData
extends RefCounted

# One age per resource on the ladder; the current age is the newest unlocked one.
# "assets" is the art checklist for that age (file names are the literal item name).
const ERAS := [
	{"resource": "wood", "name": "The Wood & Bone Age", "subtitle": "The Primordial Era",
		"time": "Before 2.5 Million Years Ago (Primal Hominids)",
		"concept": "Before humans figured out how to reliably chip flint or shape stone, they used what was easily available. Tools were made from fallen branches, sharp sticks, animal bones, and antlers.",
		"assets": ["Wooden Club", "Sharpened Digging Stick", "Bone Needle", "Thatched Lean-To", "Fire Pit"]},
	{"resource": "stone", "name": "The Stone Age", "subtitle": "The Paleolithic & Mesolithic",
		"time": "2.5 Million Years Ago to ~10,000 BCE",
		"concept": "Humanity learns the art of knapping: striking rocks together to create incredibly sharp edges. This is the era of the hunter-gatherer, transitioning slowly into early permanent settlements.",
		"assets": ["Flint Hand-Axe", "Stone-Tipped Spear", "Obsidian Scraper", "Cave Dwelling", "Leather Clothing"]},
	{"resource": "clay", "name": "The Clay & Agricultural Age", "subtitle": "The Neolithic",
		"time": "~10,000 BCE to 4,500 BCE",
		"concept": "The Neolithic Revolution. Humans discover how to bake clay into pottery, allowing them to store water and grain long-term. Settling down to farm and build mud-brick huts makes droughts and famines deadly.",
		"assets": ["Clay Pot", "Granary", "Mud-Brick House", "Stone Sickle", "Sheep", "Wheat", "Irrigation Ditch"]},
	{"resource": "copper", "name": "The Copper Age", "subtitle": "The Chalcolithic",
		"time": "~4,500 BCE to 3,300 BCE",
		"concept": "The transition between stone and true metalworking. Humans find pure copper nuggets on the surface and realize they can be melted and cast into shapes. Copper is soft, but it is the birth of metallurgy and advanced mining.",
		"assets": ["Smelting Pit", "Copper Dagger", "Mining Shaft", "Trade Dock"]},
	{"resource": "bronze", "name": "The Bronze Age", "subtitle": "The Rise of Empires",
		"time": "~3,300 BCE to 1,200 BCE",
		"concept": "Mixing soft copper with tin creates Bronze, a radically harder, deadlier alloy. This sparks massive trade routes (tin is rare) and leads to the first organized wars, walled cities, and writing systems.",
		"assets": ["Bronze Sword", "Chariot", "Stone City Wall", "Writing Tablet", "Trade Ship"]},
	{"resource": "iron", "name": "The Iron Age", "subtitle": "The Era of Mass Production",
		"time": "~1,200 BCE to 500 BCE",
		"concept": "Iron ore is everywhere, but it needs much hotter furnaces to melt. Once unlocked, iron democratizes tools and warfare because it is cheaper, stronger, and more abundant than bronze. Empires grow massive and populations skyrocket.",
		"assets": ["Blast Furnace", "Iron Plow", "Chainmail Armor", "Longsword", "Paved Stone Road"]},
	{"resource": "coal", "name": "The Coal & Steam Age", "subtitle": "The Industrial Revolution",
		"time": "~1760 CE to 1840 CE",
		"concept": "Coal burns hotter and longer than wood, and steam engines turn that heat into motion. Factories replace workshops, cities swell around the mines, and the air turns black with progress.",
		"assets": ["Steam Engine", "Coal Mine", "Factory", "Locomotive", "Pickaxe"]},
	{"resource": "steel", "name": "The Steel Age", "subtitle": "The Second Industrial Revolution",
		"time": "~1840 CE to 1900 CE",
		"concept": "New furnaces turn iron into cheap, strong steel. Railways cross continents, bridges span rivers, and skyscraper skeletons rise. Production is measured in tons, and so are the accidents.",
		"assets": ["Bessemer Converter", "Railway", "Steel Bridge", "Steel Beam", "Foundry"]},
	{"resource": "oil", "name": "The Oil Age", "subtitle": "The Age of Engines",
		"time": "~1860 CE to 1920 CE",
		"concept": "Black gold gushes from the ground. Oil lights lamps, fuels combustion engines, and powers ships and cars. Whoever controls the wells controls the world.",
		"assets": ["Oil Derrick", "Oil Barrel", "Combustion Engine", "Automobile", "Refinery"]},
	{"resource": "electricity", "name": "The Electric Age", "subtitle": "The Age of Power",
		"time": "~1880 CE to 1950 CE",
		"concept": "Power plants send energy down wires to every home. Night becomes day, factories run around the clock, and radios carry voices across the planet.",
		"assets": ["Power Plant", "Light Bulb", "Power Line", "Radio", "Battery"]},
	{"resource": "silicon", "name": "The Silicon Age", "subtitle": "The Information Age",
		"time": "~1950 CE to 2030 CE",
		"concept": "Purified sand becomes the microchip. Computers shrink from room-sized to pocket-sized, the world connects through networks, and information becomes the most valuable resource of all.",
		"assets": ["Microchip", "Computer", "Server Rack", "Smartphone", "Satellite"]},
	{"resource": "uranium", "name": "The Atomic Age", "subtitle": "The Fusion Frontier",
		"time": "~2030 CE to 2100 CE",
		"concept": "Splitting and fusing atoms unlocks almost limitless energy, and almost limitless danger. Reactors power megacities while everyone tries very hard not to think about the waste.",
		"assets": ["Nuclear Reactor", "Uranium Rod", "Hazmat Suit", "Fusion Core", "Cooling Tower"]},
	{"resource": "antimatter", "name": "The Antimatter Age", "subtitle": "The Interstellar Era",
		"time": "~2100 CE to 2300 CE",
		"concept": "Antimatter engines push ships between the stars. Colonies spread across the solar system, and a single gram of fuel can light a city or erase it.",
		"assets": ["Antimatter Trap", "Starship", "Space Station", "Particle Accelerator", "Colony Dome"]},
	{"resource": "dark_matter", "name": "The Dark Matter Age", "subtitle": "The Cosmic Era",
		"time": "~2300 CE and beyond",
		"concept": "Civilization learns to harvest the invisible mass that holds galaxies together. Reality itself becomes a building material, and the universe is the only limit left.",
		"assets": ["Dark Matter Collector", "Void Gate", "Dyson Sphere", "Reality Engine", "Cosmic Beacon"]},
]


static func current(unlocked: Dictionary) -> Dictionary:
	var best: Dictionary = ERAS[0]
	for era in ERAS:
		if unlocked.has(era["resource"]):
			best = era
	return best


static func for_resource(resource_id: String) -> Dictionary:
	for era in ERAS:
		if era["resource"] == resource_id:
			return era
	return {}
