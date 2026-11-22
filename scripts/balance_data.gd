extends RefCounted
## Loads every res://data/*.json table. Battle math reads the fields below.
## Ids are stable. Display names are for narration and UI text only.

const HashUtil = preload("res://scripts/hash_util.gd")

var parsed := {}
var hashes := {}
var paths := {}

var unit_ids: PackedStringArray = PackedStringArray()
var unit_index := {}
var unit_name := {}
var unit_narration := {}
var unit_plural := {}
var unit_legacy := {}
var cost: PackedInt32Array = PackedInt32Array()
var troops: PackedInt32Array = PackedInt32Array()
var toughness: PackedFloat64Array = PackedFloat64Array()
var firepower: PackedFloat64Array = PackedFloat64Array()
var melee_stat: PackedFloat64Array = PackedFloat64Array()
var unit_range: PackedFloat64Array = PackedFloat64Array()
var unit_reach: PackedFloat64Array = PackedFloat64Array()
var unit_morale: PackedFloat64Array = PackedFloat64Array()
var exposure: PackedFloat64Array = PackedFloat64Array()
var speed: PackedInt32Array = PackedInt32Array()
var fire_skill: PackedStringArray = PackedStringArray()
var melee_skill: PackedStringArray = PackedStringArray()

var formation_ids: PackedStringArray = PackedStringArray()
var formation_index := {}
var formation_name := {}
var formation_short := {}
var formation_legacy := {}
var form_fire: PackedFloat64Array = PackedFloat64Array()
var form_melee: PackedFloat64Array = PackedFloat64Array()
var form_taken: PackedFloat64Array = PackedFloat64Array()
var form_advance: PackedFloat64Array = PackedFloat64Array()
var form_morale: PackedFloat64Array = PackedFloat64Array()
var unit_melee_mult: Array = []
var matchup: Array = []
var comp_fit: Array = []
var beats := {}
var counter_reasons := {}

var stance_ids: PackedStringArray = PackedStringArray()
var stance_index := {}
var stance_name := {}
var stance_advance: PackedFloat64Array = PackedFloat64Array()
var stance_hold: PackedFloat64Array = PackedFloat64Array()
var stance_fire: PackedFloat64Array = PackedFloat64Array()
var stance_melee: PackedFloat64Array = PackedFloat64Array()
var stance_taken: PackedFloat64Array = PackedFloat64Array()
var stance_rout: PackedFloat64Array = PackedFloat64Array()
var stance_auto: PackedInt32Array = PackedInt32Array()
var stance_bias: Array = []

var terrain_ids: PackedStringArray = PackedStringArray()
var terrains := {}

var skill_ids: PackedStringArray = PackedStringArray()
var skill_index := {}
var innate_ids: PackedStringArray = PackedStringArray()
var innate_index := {}
var hidden_ids: PackedStringArray = PackedStringArray()
var hidden_index := {}

var rank_ids: PackedStringArray = PackedStringArray()
var rank_name := {}
var rank_budget := {}
var rank_command := {}
var command_size_note := ""

var trait_by_id := {}
var strength_ids: PackedStringArray = PackedStringArray()
var weakness_ids: PackedStringArray = PackedStringArray()
var hidden_trait_ids: PackedStringArray = PackedStringArray()

var neutral := 0.0
var half := 0.0
var tiny := 0.0
var stat_scale := 0.0
var ath_per := 0.0
var ada_per := 0.0
var eb_w_brv := 0.0
var eb_w_hid := 0.0
var eb_loss_per := 0.0
var eb_rout_per := 0.0
var wis_dmg_per := 0.0
var wis_insight := 0.0
var int_insight := 0.0
var bt_insight := 0.0
var skill_per := 0.0
var lead_morale_per := 0.0
var lead_loss_per := 0.0
var insp_rally_base := 0.0
var insp_rally_per := 0.0
var insp_regen_per := 0.0
var agg_melee_per := 0.0
var agg_taken_per := 0.0
var agg_bias: PackedFloat64Array = PackedFloat64Array()
var temp_noise_0 := 0.0
var temp_noise_99 := 0.0
var temp_ai_per := 0.0
var regen_base := 0.0
var morale_cap := 0.0
var morale_min := 0.0
var loss_k := 0.0
var melee_extra := 0.0
var rout_base := 0.0
var elim_frac := 0.0
var max_ticks := 0
var start_dist := 0.0
var var_min := 0.0
var var_max := 0.0
var timeout_w_str := 0.0
var timeout_w_mor := 0.0
var timeout_mor_div := 0.0
var draw_margin := 0.0
var pursuit_mult := 0.0
var canister_dist := 0.0
var canister_mult := 0.0
var ai_terrain_w := 0.0
var ai_counter_w := 0.0
var ai_temperature := 0.0
var ai_noise_base := 0.0
var ai_noise_insight := 0.0
var msg_delay := 0
var rally_frac := 0.0
var rally_loss_mult := 0.0
var rally_dur := 0
var res_mult := 0.0
var res_dur := 0
var auto_morale := 0.0
var stat_min := 0.0
var stat_cap := 0.0
var cannon_i := 0
var cavalry_i := 0
var infantry_i := 0
var idx_int := 0
var idx_ath := 0
var idx_ada := 0
var idx_brv := 0
var idx_naf := 0
var idx_lead := 0
var idx_bt := 0
var idx_insp := 0
var idx_agg := 0
var idx_temp := 0
var idx_hbrv := 0
var hidden_max := 0.0
var target_fire: Array = []
var target_melee: Array = []
var shaken_high := 0.0
var shaken_low := 0.0
var hb_below := 0.0
var temp_loss_frac := 0.0
var trig_insp := ""
var trig_agg := ""
var trig_temp := ""
var trig_hb := ""
var bands: Array = []
var templates := {}
var narration_placeholders := {}
var data_version := ""
var scenarios_loaded := true


static func create():
	var data = load("res://scripts/balance_data.gd").new()
	if not data._load():
		return null
	return data


func _load() -> bool:
	half = 1.0 / (1.0 + 1.0)
	var guard := "xxxxxxxxxxxxxxxxxxxx"
	tiny = 1.0
	for _i in guard.length():
		tiny = tiny / (1.0 + 1.0)
	var dir := DirAccess.open("res://data")
	if dir == null:
		push_error("data directory missing")
		return false
	var names: Array = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	if names.is_empty():
		push_error("no data tables")
		return false
	for name in names:
		var path := "res://data/%s" % name
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			push_error("empty data file %s" % name)
			return false
		var key := str(name).trim_suffix(".json")
		hashes[key] = HashUtil.sha256_bytes(bytes)
		paths[key] = path
		var text := bytes.get_string_from_utf8()
		var parsed_one = JSON.parse_string(text)
		if parsed_one == null or not (parsed_one is Dictionary):
			push_error("invalid json %s" % name)
			return false
		parsed[key] = parsed_one
	var required := [
		"attributes", "skills", "traits", "ranks", "units", "formations",
		"terrain", "stances", "messenger", "breeding", "economy",
		"narration", "scenarios", "campaign", "battle",
	]
	for req in required:
		if not parsed.has(req):
			push_error("missing table %s" % req)
			return false
	if not _assert_e7():
		return false
	if not _index():
		return false
	return true


func _assert_e7() -> bool:
	var eco = parsed["economy"]["daily_limits"]["ranked_battles_per_officer_per_day"]
	var cap = parsed["campaign"]["picking"]["max_assignments_per_officer_per_day"]
	if int(eco) != int(cap):
		push_error("E7 failed: ranked_battles_per_officer_per_day %s != max_assignments_per_officer_per_day %s" % [str(eco), str(cap)])
		return false
	return true


func _index() -> bool:
	data_version = str(parsed["battle"].get("version", ""))
	var neutrals: Array = []
	_walk_neutral(parsed, neutrals)
	if neutrals.is_empty():
		push_error("neutral point missing from key names")
		return false
	neutral = float(neutrals[0])
	for n in neutrals:
		if float(n) != neutral:
			push_error("mixed neutral points in key names")
			return false
	_index_units()
	_index_formations()
	_index_stances()
	_index_terrain()
	_index_skills()
	_index_attrs()
	_index_ranks()
	_index_traits()
	_index_battle()
	_index_text()
	scenarios_loaded = parsed.has("scenarios")
	return true


func _walk_neutral(node, acc: Array) -> void:
	if node is Dictionary:
		for k in node.keys():
			var ks := str(k)
			if "_over_" in ks or "_under_" in ks:
				var n := _suffix_int(ks)
				if n >= 0:
					acc.append(n)
			_walk_neutral(node[k], acc)
	elif node is Array:
		for v in node:
			_walk_neutral(v, acc)


func _suffix_int(key: String) -> int:
	var digits := "0123456789"
	var i := key.length() - 1
	if i < 0 or digits.find(key.substr(i, 1)) < 0:
		return -1
	while i >= 0 and digits.find(key.substr(i, 1)) >= 0:
		i -= 1
	return int(key.substr(i + 1, key.length() - (i + 1)))


func _first_int(text: String) -> int:
	var digits := "0123456789"
	var i := 0
	while i < text.length():
		if digits.find(text.substr(i, 1)) >= 0:
			var j := i
			while j < text.length() and digits.find(text.substr(j, 1)) >= 0:
				j += 1
			return int(text.substr(i, j - i))
		i += 1
	return -1


func _nums_in(text: String) -> Array:
	var digits := "0123456789"
	var out: Array = []
	var i := 0
	while i < text.length():
		var ch := text.substr(i, 1)
		var neg := false
		if ch == "-" and i + 1 < text.length() and digits.find(text.substr(i + 1, 1)) >= 0:
			neg = true
			i += 1
			ch = text.substr(i, 1)
		if digits.find(ch) >= 0 or ch == ".":
			var buf := ""
			if neg:
				buf = "-"
			while i < text.length():
				var c2 := text.substr(i, 1)
				if digits.find(c2) >= 0 or c2 == ".":
					buf += c2
					i += 1
				else:
					break
			out.append(float(buf))
		else:
			i += 1
	return out


func _index_units() -> void:
	var units: Dictionary = parsed["units"]["units"]
	var n := 0
	for id in units.keys():
		unit_ids.append(str(id))
		unit_index[str(id)] = n
		var u: Dictionary = units[id]
		unit_name[str(id)] = str(u.get("name", id))
		unit_narration[str(id)] = str(u.get("narration_name", u.get("name", id)))
		unit_plural[str(id)] = str(u.get("narration_plural", ""))
		unit_legacy[str(id)] = u.get("legacy_names", [])
		cost.append(int(u["cost"]))
		troops.append(int(u["troops"]))
		toughness.append(float(u["toughness"]))
		firepower.append(float(u["firepower"]))
		melee_stat.append(float(u["melee"]))
		unit_range.append(float(u["range"]))
		unit_reach.append(float(u["melee_reach"]))
		unit_morale.append(float(u["morale"]))
		exposure.append(float(u["exposure"]))
		speed.append(int(u["speed"]))
		fire_skill.append(str(u["fire_skill"]))
		melee_skill.append(str(u["melee_skill"]))
		n += 1
	infantry_i = int(unit_index["infantry"])
	cavalry_i = int(unit_index["cavalry"])
	cannon_i = int(unit_index["cannon"])
	var modes := ["fire", "melee"]
	for mode in modes:
		var table: Array = []
		for a in unit_ids.size():
			var row := PackedFloat64Array()
			row.resize(unit_ids.size())
			var aid := unit_ids[a]
			for t in unit_ids.size():
				var tid := unit_ids[t]
				var pref = 1.0
				var block: Dictionary = parsed["units"]["targeting"][mode]
				if block.has(aid) and block[aid].has(tid):
					pref = float(block[aid][tid])
				row[t] = pref
			table.append(row)
		if mode == "fire":
			target_fire = table
		else:
			target_melee = table
	canister_dist = float(parsed["units"]["canister"]["max_distance"])
	canister_mult = float(parsed["units"]["canister"]["fire_mult"])


func _index_formations() -> void:
	var forms: Dictionary = parsed["formations"]["formations"]
	var n := 0
	for id in forms.keys():
		formation_ids.append(str(id))
		formation_index[str(id)] = n
		var f: Dictionary = forms[id]
		formation_name[str(id)] = str(f.get("name", id))
		formation_short[str(id)] = str(f.get("short_name", f.get("name", id)))
		formation_legacy[str(id)] = f.get("legacy_names", [])
		form_fire.append(float(f["fire_mult"]))
		form_melee.append(float(f["melee_mult"]))
		form_taken.append(float(f["damage_taken_mult"]))
		form_advance.append(float(f["advance_add"]))
		form_morale.append(float(f.get("start_morale_add", 0)))
		n += 1
	for fi in formation_ids.size():
		var row := PackedFloat64Array()
		row.resize(unit_ids.size())
		for ui in unit_ids.size():
			row[ui] = 1.0
		var spec: Dictionary = forms[formation_ids[fi]]
		if spec.has("unit_melee_mult"):
			for uid in spec["unit_melee_mult"].keys():
				if unit_index.has(str(uid)):
					row[int(unit_index[str(uid)])] = float(spec["unit_melee_mult"][uid])
		unit_melee_mult.append(row)
	var matrix: Dictionary = parsed["formations"]["matchup_damage_mult"]
	for fi in formation_ids.size():
		var row := PackedFloat64Array()
		row.resize(formation_ids.size())
		for fj in formation_ids.size():
			row[fj] = float(matrix[formation_ids[fi]][formation_ids[fj]])
		matchup.append(row)
	var fit: Dictionary = parsed["formations"]["ai"]["composition_fit"]
	for fi in formation_ids.size():
		var row := PackedFloat64Array()
		row.resize(unit_ids.size())
		for ui in unit_ids.size():
			row[ui] = float(fit[formation_ids[fi]][unit_ids[ui]])
		comp_fit.append(row)
	beats = parsed["formations"]["beats"]
	counter_reasons = parsed["formations"]["counter_reasons"]
	var ai: Dictionary = parsed["formations"]["ai"]
	ai_terrain_w = float(ai["terrain_fit_weight"])
	ai_counter_w = float(ai["counter_weight"])
	ai_temperature = float(ai["enemy_prediction_temperature"])
	ai_noise_base = float(ai["noise"]["base"])
	ai_noise_insight = float(ai["noise"]["insight_scaled"])


func _index_stances() -> void:
	var st: Dictionary = parsed["stances"]["stances"]
	for id in st.keys():
		stance_ids.append(str(id))
		stance_index[str(id)] = stance_ids.size() - 1
		var s: Dictionary = st[id]
		stance_name[str(id)] = str(s.get("name", id))
		stance_advance.append(float(s["advance"]))
		if s["hold_at_distance"] == null:
			stance_hold.append(-1.0)
		else:
			stance_hold.append(float(s["hold_at_distance"]))
		stance_fire.append(float(s["fire_mult"]))
		stance_melee.append(float(s["melee_mult"]))
		stance_taken.append(float(s["damage_taken_mult"]))
		stance_rout.append(float(s["rout_threshold_add"]))
		stance_auto.append(int(s["auto_reserve_tick"]))
		var bias := PackedFloat64Array()
		bias.resize(formation_ids.size())
		for fi in formation_ids.size():
			bias[fi] = float(s["ai_bias"].get(formation_ids[fi], 0))
		stance_bias.append(bias)


func _index_terrain() -> void:
	var terr: Dictionary = parsed["terrain"]["terrain"]
	for id in terr.keys():
		terrain_ids.append(str(id))
		var t: Dictionary = terr[id]
		var fire := PackedFloat64Array()
		var mel := PackedFloat64Array()
		var radd := PackedFloat64Array()
		var hadd := PackedFloat64Array()
		fire.resize(unit_ids.size())
		mel.resize(unit_ids.size())
		radd.resize(unit_ids.size())
		hadd.resize(unit_ids.size())
		for ui in unit_ids.size():
			var uid := unit_ids[ui]
			fire[ui] = float(t["fire_mult"][uid])
			mel[ui] = float(t["melee_mult"][uid])
			radd[ui] = float(t["range_add"].get(uid, 0))
			hadd[ui] = float(t["reach_add"].get(uid, 0))
		var fmult := PackedFloat64Array()
		fmult.resize(formation_ids.size())
		for fi in formation_ids.size():
			fmult[fi] = float(t["formation_mult"][formation_ids[fi]])
		terrains[str(id)] = {
			"name": str(t.get("name", id)),
			"advance": float(t["advance_add"]),
			"fire": fire,
			"melee": mel,
			"range_add": radd,
			"reach_add": hadd,
			"formation": fmult,
		}


func _index_skills() -> void:
	var skills: Dictionary = parsed["skills"]["skills"]
	for id in skills.keys():
		skill_ids.append(str(id))
		skill_index[str(id)] = skill_ids.size() - 1
	skill_per = float(parsed["skills"]["unit_skill_mult_per_point_over_50"])
	lead_morale_per = float(parsed["skills"]["leadership"]["start_morale_per_point_over_50"])
	lead_loss_per = float(parsed["skills"]["leadership"]["morale_loss_scale_per_point_over_50"])
	bt_insight = float(parsed["skills"]["battlefield_theory"]["ai_insight_weight"])
	idx_lead = int(skill_index["leadership"])
	idx_bt = int(skill_index["battlefield_theory"])
	stat_min = float(parsed["skills"]["min"])
	stat_cap = float(parsed["attributes"]["innate"]["hard_cap"])


func _index_attrs() -> void:
	for id in parsed["attributes"]["innate"]["ids"]:
		innate_ids.append(str(id))
		innate_index[str(id)] = innate_ids.size() - 1
	for id in parsed["attributes"]["hidden"]["ids"]:
		hidden_ids.append(str(id))
		hidden_index[str(id)] = hidden_ids.size() - 1
	var be: Dictionary = parsed["attributes"]["innate"]["battle_effects"]
	ath_per = float(be["athleticism"]["melee_mult_per_point_over_50"])
	ada_per = float(be["adaptability"]["terrain_penalty_scale_per_point_over_50"])
	eb_w_brv = float(be["bravery"]["visible_weight_in_effective_bravery"])
	int_insight = float(be["intelligence"]["ai_insight_weight"])
	var eb: Dictionary = parsed["attributes"]["effective_bravery"]
	eb_loss_per = float(eb["morale_loss_scale_per_point_over_50"])
	eb_rout_per = float(eb["rout_threshold_shift_per_point_over_50"])
	var wis: Dictionary = parsed["attributes"]["wisdom"]["battle_effects"]
	wis_dmg_per = float(wis["damage_mult_per_point_over_50"])
	wis_insight = float(wis["ai_insight_weight"])
	var hid: Dictionary = parsed["attributes"]["hidden"]["battle_effects"]
	eb_w_hid = float(hid["hidden_bravery"]["visible_weight_in_effective_bravery"])
	insp_rally_base = float(hid["inspiration"]["rally_mult_base"])
	insp_rally_per = float(hid["inspiration"]["rally_mult_per_point"])
	insp_regen_per = float(hid["inspiration"]["morale_regen_per_tick_per_point_over_50"])
	agg_melee_per = float(hid["aggression"]["melee_mult_per_point_over_50"])
	agg_taken_per = float(hid["aggression"]["damage_taken_mult_per_point_over_50"])
	agg_bias.resize(formation_ids.size())
	for fi in formation_ids.size():
		agg_bias[fi] = float(hid["aggression"]["ai_bias_per_point_over_50"].get(formation_ids[fi], 0))
	temp_noise_0 = float(hid["temperament"]["morale_loss_noise_at_0"])
	temp_noise_99 = float(hid["temperament"]["morale_loss_noise_at_99"])
	temp_ai_per = float(hid["temperament"]["ai_noise_per_point_under_50"])
	idx_int = int(innate_index["intelligence"])
	idx_ath = int(innate_index["athleticism"])
	idx_ada = int(innate_index["adaptability"])
	idx_brv = int(innate_index["bravery"])
	idx_naf = int(innate_index["natural_affinity"])
	idx_insp = int(hidden_index["inspiration"])
	idx_agg = int(hidden_index["aggression"])
	idx_temp = int(hidden_index["temperament"])
	idx_hbrv = int(hidden_index["hidden_bravery"])
	hidden_max = float(parsed["attributes"]["hidden"]["max"])
	var triggers: Dictionary = parsed["attributes"]["hidden"]["reveal"]["triggers"]
	trig_insp = str(triggers["inspiration"])
	trig_agg = str(triggers["aggression"])
	trig_temp = str(triggers["temperament"])
	trig_hb = str(triggers["hidden_bravery"])
	hb_below = float(_first_int(trig_hb))
	var pct := float(_first_int(trig_temp))
	bands = parsed["attributes"]["hidden"]["reveal"]["bands"]
	stat_scale = float(parsed["battle"]["morale"]["cap"])
	temp_loss_frac = pct / stat_scale


func _index_ranks() -> void:
	command_size_note = str(parsed["ranks"].get("command_size_note", ""))
	for row in parsed["ranks"]["ranks"]:
		var id := str(row["id"])
		rank_ids.append(id)
		rank_name[id] = str(row.get("name", id))
		rank_budget[id] = int(row["point_budget"])
		rank_command[id] = str(row.get("command_size", ""))


func _index_traits() -> void:
	for group in ["strengths", "weaknesses", "hidden"]:
		for row in parsed["traits"][group]:
			var id := str(row["id"])
			trait_by_id[id] = row
			if group == "strengths":
				strength_ids.append(id)
			elif group == "weaknesses":
				weakness_ids.append(id)
			else:
				hidden_trait_ids.append(id)
	for row in parsed["traits"]["hidden"]:
		if str(row["id"]) == "panic_prone" and row.has("trigger"):
			shaken_low = float(row["trigger"]["value"])
	shaken_high = float(parsed["messenger"]["auto_reserves"]["morale_below"])


func _index_battle() -> void:
	var b: Dictionary = parsed["battle"]
	max_ticks = int(b["max_ticks"])
	start_dist = float(b["start_distance"])
	var_min = float(b["damage_variance"]["min"])
	var_max = float(b["damage_variance"]["max"])
	regen_base = float(b["morale"]["regen_when_untouched_base"])
	morale_cap = float(b["morale"]["cap"])
	morale_min = float(b["morale"]["min"])
	loss_k = float(b["morale"]["loss_per_pct_troops_lost"])
	melee_extra = float(b["morale"]["melee_casualty_extra_weight"])
	rout_base = float(b["rout"]["base_threshold"])
	elim_frac = float(b["rout"]["eliminated_below_fraction_of_start"])
	draw_margin = float(b["timeout"]["draw_margin"])
	pursuit_mult = float(b["pursuit"]["winner_cavalry_melee_mult"])
	var nums: Array = _nums_in(str(b["timeout"]["score"]))
	timeout_w_str = float(nums[0])
	timeout_w_mor = float(nums[1])
	timeout_mor_div = float(nums[1 + 1])
	var msg: Dictionary = parsed["messenger"]
	msg_delay = int(msg["delay_ticks"])
	rally_frac = float(msg["actions"]["rally"]["restore_lost_morale_frac"])
	rally_loss_mult = float(msg["actions"]["rally"]["morale_loss_mult"])
	rally_dur = int(msg["actions"]["rally"]["duration_ticks"])
	res_mult = float(msg["actions"]["commit_reserves"]["reserve_damage_mult"])
	res_dur = int(msg["actions"]["commit_reserves"]["duration_ticks"])
	auto_morale = float(msg["auto_reserves"]["morale_below"])


func _index_text() -> void:
	templates = parsed["narration"]["templates"]
	narration_placeholders = parsed["narration"].get("placeholders", {})
	for id in rank_ids:
		if str(rank_command[id]) == "":
			push_error("empty command_size for %s" % id)
	for sid in parsed["scenarios"]["scenarios"].keys():
		var note = parsed["scenarios"]["scenarios"][sid].get("historical_odds_note", "")
		if str(note) == "":
			push_error("empty historical_odds_note for %s" % sid)


func rank_id_for_budget(budget: int) -> String:
	for id in rank_ids:
		if int(rank_budget[id]) == budget:
			return id
	return rank_ids[0]


func archetype_companies(arch: String, budget: int) -> Dictionary:
	var shares: Dictionary = parsed["battle"]["ai_general"]["composition_archetypes"][arch]
	var counts := {}
	var spent := 0
	for i in unit_ids.size():
		var id := unit_ids[i]
		var pts := int(floor(float(shares[id]) * float(budget)))
		var comp := int(floor(float(pts) / float(cost[i])))
		counts[id] = comp
		spent += comp * int(cost[i])
	var left := budget - spent
	var extra := int(floor(float(left) / float(cost[infantry_i])))
	counts["infantry"] = int(counts["infantry"]) + extra
	return counts


func drop_scenarios() -> void:
	scenarios_loaded = false
	parsed.erase("scenarios")
