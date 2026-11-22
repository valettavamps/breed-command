extends RefCounted
## Fills narration.json templates. Placeholders are substituted exactly.
## Plurals come from units.<id>.narration_plural. Formation lines already
## say "the {formation_name}"; the display name is formations.<id>.name.

const HashUtil = preload("res://scripts/hash_util.gd")


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
