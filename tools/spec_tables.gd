extends RefCounted
## Reads harness sample sizes, officer draws, and QA bands out of the spec
## tables. The numbers stay in those documents. This file does not copy them.


static func load_all() -> Dictionary:
	var plan := FileAccess.get_file_as_string("res://docs/spec/v1/sim-plan.md")
	var spec := FileAccess.get_file_as_string("res://docs/spec/v1/spec.md")
	var head := plan.split("## 2.")[0]
	var officer := _line(head, "base officer")
	var randints := _calls(officer, "randint")
	var normal := _calls(officer, "Normal")
	var sizes := _thousands(_numbers(_line(head, "Sample sizes")))
	var comp := _line(head, "composition")
	var rows := _rows(plan)
	var b1 := _numbers(_expand_k(rows["B1"]["setup"]))
	var out := {
		"headline": int(sizes[0]),
		"cell": int(sizes[1]),
		"b1": int(b1[0]),
		"fixtures": int(b1[1]),
		"vis_lo": int(randints[0][0]),
		"vis_hi": int(randints[0][1]),
		"vis_sd": float(normal[0][1]),
		"hid_lo": int(randints[1][0]),
		"hid_hi": int(randints[1][1]),
		"cannon_max": _labeled_hi(comp, "cannon"),
		"cav_max": _labeled_hi(comp, "cavalry"),
		"inf_min": _labeled_hi(comp, "at least"),
		"draw": _numbers(_line(head, "draw scores"))[0],
		"edge": _plus(rows["B2"]["setup"]),
		"rows": rows,
		"bands": _bands(rows),
		"volley": _volley(spec),
		"reserve_frac": _percent_in(rows["B14"]["setup"]),
	}
	out["b2b_edges"] = _pluses(rows["B2b"]["threshold"])
	out["b13_budgets"] = _numbers(_after_first(rows["B13"]["setup"], "budget"))
	out["b16_pair"] = _numbers(rows["B16"]["question"] + " " + rows["B16"]["setup"])
	return out


static func _percent_in(text: String) -> float:
	var at := text.find("%")
	if at < 0:
		return 0.0
	var nums: Array = _numbers(text.substr(0, at))
	if nums.is_empty():
		return 0.0
	return float(nums[nums.size() - 1]) / float("100")


static func _bands(rows: Dictionary) -> Dictionary:
	var bands := {}
	for id in rows.keys():
		bands[id] = _ranges(rows[id]["threshold"])
	return bands


static func _volley(spec: String) -> Dictionary:
	var at := spec.find("Example (one volley):")
	var para := spec.substr(at, spec.find("\n\n", at) - at)
	var troops_at := para.find("enemy front has")
	var troop_bits := para.substr(troops_at, para.find(".", troops_at) - troops_at)
	return {
		"companies": _before_phrase(para, "full infantry"),
		"marksmanship": _after_word(para, "Marksmanship"),
		"wisdom": _after_word(para, "Wisdom"),
		"attacker_formation": "Wide Line",
		"defender_formation": "Defensive Screen",
		"terrain": "Open Field",
		"distance": _after_word(para, "distance"),
		"variance": _after_word(para, "variance roll"),
		"equals": _equals(para),
		"infantry_loss": _before_phrase(_after_first(para, "Losses:"), "infantry"),
		"strength": _before_phrase(para, "strength in all"),
		"enemy_troops": _numbers(troop_bits.split("so the")[0]),
	}


static func _after_first(text: String, mark: String) -> String:
	var at := text.find(mark)
	if at < 0:
		return ""
	return text.substr(at + mark.length())


static func _before_phrase(text: String, phrase: String) -> float:
	var at := text.find(phrase)
	var back := text.substr(0, at)
	var nums := _numbers(back)
	return float(nums[nums.size() - 1])


static func _after_word(text: String, word: String) -> float:
	return _numbers(_after_first(text, word))[0]


static func _after_token(text: String, token: String) -> float:
	return _numbers(_after_first(text, token))[0]


static func _rows(plan: String) -> Dictionary:
	var rows := {}
	for line in plan.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		var two := "ab".length()
		if cells.size() < two * "abc".length():
			continue
		var id := str(cells[1]).strip_edges()
		if id == "ID" or id == "":
			continue
		rows[id] = {
			"question": str(cells[two]).strip_edges(),
			"setup": str(cells[two + 1]).strip_edges(),
			"threshold": str(cells[two + two]).strip_edges(),
		}
	return rows


static func _line(text: String, mark: String) -> String:
	for line in text.split("\n"):
		if line.find(mark) >= 0:
			return line
	return ""


static func _calls(text: String, name: String) -> Array:
	var found: Array = []
	var mark := name + "("
	var rest := text
	while true:
		var at := rest.find(mark)
		if at < 0:
			break
		rest = rest.substr(at + mark.length())
		var end := rest.find(")")
		found.append(_numbers(rest.substr(0, end)))
		rest = rest.substr(end)
	return found


static func _labeled_hi(text: String, label: String) -> int:
	var nums: Array = _numbers(_after_first(text, label))
	var two := "ab".length()
	if nums.size() >= two:
		return int(max(nums[0], nums[1]))
	return int(nums[0])


static func _plus(text: String) -> int:
	return int(_pluses(text)[0])


static func _pluses(text: String) -> Array:
	var out: Array = []
	var i := 0
	while i < text.length():
		if text.substr(i, 1) == "+":
			var nums: Array = _numbers(text.substr(i))
			if nums.size() > 0:
				out.append(int(nums[0]))
				i += 1
				continue
		i += 1
	return out


static func _equals(text: String) -> Array:
	var out: Array = []
	var rest := text
	while true:
		var at := rest.find("=")
		if at < 0:
			break
		rest = rest.substr(at + 1)
		var nums: Array = _numbers(rest)
		if nums.size() > 0:
			out.append(float(nums[0]))
	return out


static func _expand_k(text: String) -> String:
	var digits := "0123456789"
	var out := ""
	var i := 0
	while i < text.length():
		if digits.find(text.substr(i, 1)) >= 0:
			var j := i
			while j < text.length() and digits.find(text.substr(j, 1)) >= 0:
				j += 1
			if j < text.length() and text.substr(j, 1) == "k":
				out += text.substr(i, j - i) + "000"
				i = j + 1
				continue
		out += text.substr(i, 1)
		i += 1
	return out


static func _numbers(text: String) -> Array:
	var digits := "0123456789"
	var out: Array = []
	var i := 0
	while i < text.length():
		var c := text.substr(i, 1)
		var neg := false
		if c == "-" and i + 1 < text.length() and digits.find(text.substr(i + 1, 1)) >= 0:
			var prev := ""
			if i > 0:
				prev = text.substr(i - 1, 1)
			if prev == "" or prev == " " or prev == "(" or prev == "," or prev == ":" or prev == "+":
				neg = true
				i += 1
				c = text.substr(i, 1)
		if digits.find(c) >= 0:
			var buf := ""
			if neg:
				buf = "-"
			while i < text.length():
				var d := text.substr(i, 1)
				if digits.find(d) >= 0:
					buf += d
					i += 1
					if i < text.length() and text.substr(i, 1) == ",":
						var nxt := ""
						if i + 1 < text.length():
							nxt = text.substr(i + 1, 1)
						if digits.find(nxt) >= 0:
							i += 1
							continue
					continue
				if d == "." and i + 1 < text.length() and digits.find(text.substr(i + 1, 1)) >= 0:
					buf += d
					i += 1
					continue
				break
			out.append(float(buf))
			continue
		i += 1
	return out


static func _ranges(text: String) -> Array:
	var digits := "0123456789"
	var hundred := float("100")
	var out: Array = []
	var i := 0
	while i < text.length():
		var c := text.substr(i, 1)
		var sided := ""
		if c == "≤" or c == "<":
			sided = "max"
		elif c == "≥" or c == ">":
			sided = "min"
		elif c == "±":
			sided = "pm"
		if sided != "":
			var rest := text.substr(i + 1)
			var nums: Array = _numbers(rest)
			if nums.size() > 0:
				var val := float(nums[0])
				var pct := _soon_percent(rest)
				if pct:
					val = val / hundred
				if sided == "pm" and text.substr(i).find("point") >= 0:
					val = float(nums[0]) / hundred
				out.append({"lo": val if sided != "max" else null, "hi": val if sided != "min" else null, "pm": sided == "pm", "value": val})
			i += 1
			continue
		if digits.find(c) >= 0:
			var nums2: Array = _numbers(text.substr(i))
			var span := _token_len(text.substr(i))
			var nxt := text.substr(i + span)
			if nxt.begins_with("-") or nxt.begins_with("–"):
				var hi_nums: Array = _numbers(nxt.substr(1))
				var hi_len := _token_len(nxt.substr(1))
				var pct2 := _soon_percent(nxt.substr(1 + hi_len))
				var lo := float(nums2[0])
				var hi := float(hi_nums[0])
				if pct2:
					lo = lo / hundred
					hi = hi / hundred
				out.append({"lo": lo, "hi": hi, "pm": false, "value": lo})
				i += span + 1 + hi_len
				continue
		i += 1
	return out


static func _thousands(nums: Array) -> Array:
	var out: Array = []
	var floor_v := float("1000")
	for n in nums:
		if float(n) >= floor_v:
			out.append(n)
	return out


static func _soon_percent(text: String) -> bool:
	var digits := "0123456789"
	var i := 0
	while i < text.length():
		var c := text.substr(i, 1)
		if c == "%":
			return true
		if c == " " or c == "." or c == "," or digits.find(c) >= 0:
			i += 1
			continue
		return false
	return false


static func _token_len(text: String) -> int:
	var digits := "0123456789"
	var i := 0
	var saw := false
	while i < text.length():
		var c := text.substr(i, 1)
		if digits.find(c) >= 0:
			saw = true
			i += 1
			continue
		if c == ",":
			i += 1
			continue
		if c == "." and saw:
			i += 1
			continue
		break
	return i
