class_name FactionNames
extends RefCounted

# Random names for the hundreds of minor factions on a battle map, by map style.
const SYLLABLES := ["ug", "ka", "mor", "tha", "zul", "ren", "bo", "gar", "ish", "ul", "dra", "ves", "ko", "nar",
	"pel", "sto", "ri", "ash", "gol", "tem", "ba", "ox", "fen", "lu", "mak", "dun", "sha", "or", "vil", "gru"]
const FORMATS := {
	"land": ["%s Clan", "%s Tribe", "The %s Folk", "House %s", "%s Raiders", "Free City of %s", "%s Horde",
		"The %s League", "Duchy of %s", "%s Brotherhood", "Kingdom of %s", "The %s Marches"],
	"space": ["%s Outpost", "%s Station", "The %s Syndicate", "%s Colony", "%s Mining Guild", "%s Swarm",
		"The %s Remnant", "%s Pirates", "Free Port %s", "%s Combine", "The %s Drift", "%s Hive"],
	"void": ["Shard of %s", "The %s Echo", "%s Paradox", "Dream of %s", "The %s Fold", "%s Unbeing",
		"The Last %s", "%s Recursion", "Whisper of %s", "The %s Loop", "%s Absence", "Hymn of %s"],
}


static func make(style: String, rng: RandomNumberGenerator) -> String:
	var word := ""
	for i in rng.randi_range(2, 3):
		word += SYLLABLES[rng.randi() % SYLLABLES.size()]
	word = word.capitalize()
	var formats: Array = FORMATS.get(style, FORMATS["land"])
	return formats[rng.randi() % formats.size()] % word
