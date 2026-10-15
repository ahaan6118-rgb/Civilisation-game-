class_name NumFormat
extends RefCounted

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]


static func fmt(value: float) -> String:
	var sign := "-" if value < 0.0 else ""
	var a := absf(value)
	if a < 1000.0:
		if a < 100.0 and not is_equal_approx(a, floorf(a)):
			return sign + "%.1f" % a
		return sign + "%d" % int(floorf(a))
	var tier := int(floorf(log(a) / log(1000.0)))
	if a / pow(1000.0, tier) >= 1000.0:
		tier += 1
	if tier >= SUFFIXES.size():
		var exponent := int(floorf(log(a) / log(10.0)))
		return sign + "%.2fe%d" % [a / pow(10.0, exponent), exponent]
	return sign + "%.2f%s" % [a / pow(1000.0, tier), SUFFIXES[tier]]


static func duration(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]


static func cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in cost:
		parts.append("%s %s" % [fmt(cost[res]), GameData.resource_name(res)])
	return ", ".join(parts)
