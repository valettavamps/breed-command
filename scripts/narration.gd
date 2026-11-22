extends RefCounted
## Fills narration.json templates. Placeholders are substituted exactly.
## Plurals come from units.<id>.narration_plural. Formation lines already
## say "the {formation_name}"; the display name is formations.<id>.name.

const HashUtil = preload("res://scripts/hash_util.gd")

# Spec §16 feed cap. The integer collides with a balance value; it is not one.
const MAX_FEED_LINES := 4

const PRIORITY: Array = [
	["rout", "battle_end_win", "battle_end_draw", "scenario_held", "scenario_losses_reached", "pursuit"],
	["messenger_sent", "standing_order_cancelled", "live_click_ignored", "rally", "reserves_committed", "auto_reserves", "messenger_wasted", "messenger_lost", "trait_revealed", "hidden_attribute_revealed"],
	["charge"],
	["cannon", "canister"],
	["volley", "melee"],
	["advance", "hold", "formation_chosen", "battle_start", "morale_shaken"],
]


static func variant_index(seed: int, tick: int, event_index: int, count: int) -> int:
	if count <= 1:
		return 0
	return HashUtil.fnv32("%d|%d|%d" % [seed, tick, event_index]) % count


static func apply_template(template: String, fill: Dictionary) -> String:
	var line := template
	for k in fill.keys():
		line = line.replace("{%s}" % str(k), str(fill[k]))
	return line


static func has_unfilled(line: String) -> bool:
	return line.find("{") >= 0


static func narrate(templates: Dictionary, event: Dictionary, seed: int, tick: int, event_index: int) -> String:
	var kind := str(event.get("type", ""))
	if not templates.has(kind):
		return ""
	var list: Array = templates[kind]
	if list.is_empty():
		return ""
	var idx := variant_index(seed, tick, event_index, list.size())
	var fill: Dictionary = event.get("fill", {})
	return apply_template(str(list[idx]), fill)


static func fmt_number(x: float, places: int, half: float) -> String:
	var digits := "0123456789"
	var scale := 1
	for _i in places:
		scale *= digits.length()
	var n := 0
	if x >= 0.0:
		n = int(floor(x * float(scale) + half))
	else:
		n = int(ceil(x * float(scale) - half))
	var neg := ""
	if n < 0:
		neg = "-"
		n = -n
	var whole := int(n / scale)
	var frac := n % scale
	if frac == 0:
		return "%s%d" % [neg, whole]
	var width := str(scale).length() - 1
	var fs := str(frac)
	while fs.length() < width:
		fs = "0" + fs
	while fs.ends_with("0") and fs.length() > 1:
		fs = fs.substr(0, fs.length() - 1)
	if fs == "0":
		return "%s%d" % [neg, whole]
	return "%s%d.%s" % [neg, whole, fs]


static func feed_lines(lines_in_priority: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for group in lines_in_priority:
		for line in group:
			if out.size() >= MAX_FEED_LINES:
				return out
			out.append(str(line))
	return out


static func priority_bucket(kind: String) -> int:
	for i in PRIORITY.size():
		if PRIORITY[i].has(kind):
			return i
	return PRIORITY.size()
