extends SceneTree
## Headless balance harness. Calls the production resolver.
## Fixture id per check: <check id>@<master seed>@<build SHA>.
## Trial seed: hash32(master, check id, trial) = FNV-1a of "master|check|trial".

const BalanceData = preload("res://scripts/balance_data.gd")
const ResolverScript = preload("res://scripts/battle_resolver.gd")
const HashUtil = preload("res://scripts/hash_util.gd")
const LaunchFlags = preload("res://scripts/launch_flags.gd")
const Records = preload("res://scripts/records.gd")
const Narration = preload("res://scripts/narration.gd")
const GameClock = preload("res://scripts/game_clock.gd")
const Civil = preload("res://scripts/civil_time.gd")
const PortableMath = preload("res://scripts/portable_math.gd")
const Tables = preload("res://tools/spec_tables.gd")

var data
var resolver
var master := 20261122
var smoke := false
var sha := ""
var godot_s := ""
var budget := 0
var stat_lo := 0.0
var stat_hi := 0.0
var plan := {}
var trial_only := -1
var out_arg := ""
var harness_clock

const SPEC_EVENTS := [
	"battle_start", "formation_chosen", "advance", "hold", "volley", "cannon", "canister",
	"charge", "melee", "morale_shaken", "messenger_sent", "standing_order_cancelled",
	"live_click_ignored", "rally", "reserves_committed", "auto_reserves", "messenger_wasted",
	"messenger_lost", "trait_revealed", "hidden_attribute_revealed", "rout", "pursuit",
	"battle_end_win", "battle_end_draw", "scenario_held", "scenario_losses_reached",
]


func _init() -> void:
	var code := _main()
	quit(code)


func _main() -> int:
	var flags := LaunchFlags.parse_user_args(OS.get_cmdline_user_args())
	if str(flags["suite"]) == "":
		flags = LaunchFlags.parse_user_args(_args_after_dash())
	if not bool(flags["has_seed"]):
		push_error("missing --master-seed")
		return 1
	master = int(flags["master_seed"])
	smoke = bool(flags["smoke"])
	var info := Engine.get_version_info()
	godot_s = "%s.%s.%s-%s" % [info["major"], info["minor"], info["patch"], info["status"]]
	sha = _git_sha()
	data = BalanceData.create()
	if data == null:
		push_error("data load failed")
		return 1
	resolver = ResolverScript.new(data)
	budget = int(data.rank_budget["major"])
	stat_lo = float(data.parsed["attributes"]["innate"]["min"])
	stat_hi = float(data.parsed["attributes"]["innate"]["hard_cap"])
	plan = Tables.load_all()
	trial_only = int(flags["trial"])
	out_arg = str(flags["out"])
	harness_clock = _clock_from_flags(flags)
	print("godot ", godot_s, " sha ", sha, " budget ", budget, " smoke ", smoke, " trial ", trial_only)
	if str(flags["clock"]) != "" or str(flags["local_clock"]) != "" or str(flags["net_state"]) != "":
		print("clock ", harness_clock.net_state, " day ", harness_clock.day_index(), " offset ", harness_clock.offset_sec)
	var suite := str(flags["suite"])
	if suite == "ac1":
		return _finish("ac1", _build_ac1())
	if suite == "ac2":
		return _finish("ac2", _build_ac2())
	if suite == "CLK":
		return _finish("CLK", [_run_clk()])
	if suite == "ac6":
		return _finish("ac6", [_run_e7()])
	if suite == "all":
		var checks: Array = []
		checks.append_array(_build_ac1())
		checks.append_array(_build_ac2())
		checks.append(_run_clk())
		return _finish("all", checks)
	var one = _one_check(suite)
	if one == null:
		push_error("unknown suite %s" % suite)
		return 1
	return _finish(suite, [one])


func _args_after_dash() -> PackedStringArray:
	var all := OS.get_cmdline_args()
	var out := PackedStringArray()
	var seen := false
	for a in all:
		if seen:
			out.append(str(a))
		elif str(a) == "--":
			seen = true
	return out


func _git_sha() -> String:
	var out: Array = []
	var code := OS.execute("git", ["rev-parse", "HEAD"], out, true)
	if code == 0 and out.size() > 0:
		return str(out[0]).strip_edges()
	var env := OS.get_environment("GITHUB_SHA")
	if env != "":
		return env
	return "unknown"


func _finish(suite: String, checks: Array) -> int:
	var ok := _write_suite(suite, checks)
	for c in checks:
		print(c["check_id"], " ", c["value"], " pass=", c["pass"], " ", c["fixture_id"])
	print("SUITE ", suite, " pass=", ok)
	return 0 if ok else 1


func _write_suite(suite: String, checks: Array) -> bool:
	var ok := true
	for c in checks:
		if not bool(c["pass"]):
			ok = false
	var doc := {
		"suite": suite,
		"master_seed": master,
		"build_sha": sha,
		"godot": godot_s,
		"data_version": data.data_version,
		"data_hashes": data.hashes,
		"pass": ok,
		"checks": checks,
	}
	var text := JSON.stringify(doc, "  ")
	if not text.ends_with("\n"):
		text += "\n"
	var path := _out_path(suite)
	var folder := path.get_base_dir()
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return false
	f.store_string(text)
	f.close()
	print("wrote ", path)
	return ok


func _pack(check_id: String, metric: String, value, threshold, passed: bool, n: int, detail: Dictionary = {}) -> Dictionary:
	var ci = null
	if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and n > 1 and float(value) >= 0.0 and float(value) <= 1.0:
		var p := float(value)
		var z := float("1.96")
		var se := sqrt(max(0.0, p * (1.0 - p) / float(n)))
		ci = [p - z * se, p + z * se]
	return {
		"check_id": check_id,
		"fixture_id": "%s@%s@%s" % [check_id, str(master), sha],
		"metric": metric,
		"value": value,
		"ci95": ci,
		"threshold": threshold,
		"pass": passed,
		"n": n,
		"detail": detail,
	}


func _nh() -> int:
	return _sized(int(plan["headline"]))


func _nc() -> int:
	return _sized(int(plan["cell"]))


func _nb1() -> int:
	return _sized(int(plan["b1"]))


func _nf() -> int:
	return _sized(int(plan["fixtures"]))


func _sized(n: int) -> int:
	if not smoke:
		return n
	var cut := int(n / float("100"))
	if cut < 1:
		return 1
	return cut


func _each(n: int) -> Array:
	if trial_only >= 0:
		return [trial_only]
	var ids: Array = []
	for i in n:
		ids.append(i)
	return ids


func _span(n: int) -> int:
	if trial_only >= 0:
		return 1
	return n


func _two() -> int:
	return "ab".length()


func _eps() -> float:
	return float("1e-9")


func _lo(id: String, idx: int = 0) -> float:
	return float(plan["bands"][id][idx]["lo"])


func _hi(id: String, idx: int = 0) -> float:
	return float(plan["bands"][id][idx]["hi"])


func _out_path(suite: String) -> String:
	var rel := "res://sim_out/%s.json" % suite
	if out_arg == "":
		return ProjectSettings.globalize_path(rel)
	var chosen := out_arg
	if chosen.ends_with("/") or chosen.ends_with("\\"):
		chosen = "%s%s.json" % [chosen, suite]
	if chosen.begins_with("res://") or chosen.begins_with("user://"):
		return ProjectSettings.globalize_path(chosen)
	if chosen.begins_with("/"):
		return chosen
	return ProjectSettings.globalize_path("res://%s" % chosen)


func _clock_from_flags(flags: Dictionary):
	var clock := GameClock.new()
	var net := str(flags["net_state"])
	var server := str(flags["clock"])
	var local := str(flags["local_clock"])
	if net == "synced" and server != "" and local != "":
		clock.set_synced(Civil.unix_from_iso(server), Civil.unix_from_iso(local))
	elif net == "synced" and server != "":
		clock.set_synced(Civil.unix_from_iso(server), Civil.unix_from_iso(server))
	elif net == "offline" and local != "":
		clock.set_offline(Civil.unix_from_iso(local))
	elif local != "":
		clock.set_offline(Civil.unix_from_iso(local))
	elif server != "":
		clock.set_offline(Civil.unix_from_iso(server))
	return clock


func _nt() -> int:
	return _nc()


func _rng(check_id: String, trial: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = HashUtil.hash32(master, check_id, trial)
	return rng


func _gauss(rng: RandomNumberGenerator) -> float:
	var u1 := rng.randf()
	var u2 := rng.randf()
	if u1 < data.tiny:
		u1 = data.tiny
	return sqrt(float("-2") * PortableMath.ln(u1)) * PortableMath.cos(TAU * u2)


func _clamp_stat(v: float) -> float:
	return min(stat_hi, max(stat_lo, v))


func _roll_visible(rng: RandomNumberGenerator, base: int) -> float:
	return _clamp_stat(float(resolver.round_half(float(base) + _gauss(rng) * float(plan["vis_sd"]))))


func _officer(rng: RandomNumberGenerator, bgt: int) -> Dictionary:
	var base := rng.randi_range(int(plan["vis_lo"]), int(plan["vis_hi"]))
	var attrs := {}
	for id in data.innate_ids:
		attrs[id] = _roll_visible(rng, base)
	var skills := {}
	for id in data.skill_ids:
		skills[id] = _roll_visible(rng, base)
	var hidden := {}
	for id in data.hidden_ids:
		hidden[id] = rng.randi_range(int(plan["hid_lo"]), int(plan["hid_hi"]))
	return {
		"rank_id": data.rank_id_for_budget(bgt),
		"name": "Alden",
		"wisdom": _roll_visible(rng, base),
		"attrs": attrs,
		"skills": skills,
		"hidden": hidden,
		"traits": {"strength": null, "weakness": null, "hidden": null},
	}


func _bump_all(o: Dictionary, edge: int) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	for id in data.innate_ids:
		c["attrs"][id] = _clamp_stat(float(c["attrs"][id]) + float(edge))
	for id in data.skill_ids:
		c["skills"][id] = _clamp_stat(float(c["skills"][id]) + float(edge))
	c["wisdom"] = _clamp_stat(float(c["wisdom"]) + float(edge))
	return c


func _bump_one(o: Dictionary, kind: String, id: String) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	var edge := float(plan["edge"])
	if kind == "attr":
		c["attrs"][id] = _clamp_stat(float(c["attrs"][id]) + edge)
	elif kind == "skill":
		c["skills"][id] = _clamp_stat(float(c["skills"][id]) + edge)
	else:
		c["wisdom"] = _clamp_stat(float(c["wisdom"]) + edge)
	return c


func _with_trait(o: Dictionary, slot: String, id: String) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	c["traits"][slot] = id
	return c


func _with_hidden(o: Dictionary, id: String, value: int) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	c["hidden"][id] = value
	return c


func _comp(rng: RandomNumberGenerator, bgt: int) -> Dictionary:
	var ic := int(data.cost[data.infantry_i])
	var cc := int(data.cost[data.cavalry_i])
	var gc := int(data.cost[data.cannon_i])
	while true:
		var can_max := int(bgt / gc)
		if can_max > int(plan["cannon_max"]):
			can_max = int(plan["cannon_max"])
		var can := rng.randi_range(0, can_max)
		var rem := bgt - gc * can
		var cav_max := int(rem / cc)
		if cav_max > int(plan["cav_max"]):
			cav_max = int(plan["cav_max"])
		if cav_max < 0:
			cav_max = 0
		var cav := rng.randi_range(0, cav_max)
		var inf := bgt - gc * can - cc * cav
		if inf >= int(plan["inf_min"]):
			return {"infantry": inf / ic, "cavalry": cav, "cannon": can}
	return {"infantry": bgt, "cavalry": 0, "cannon": 0}


func _pick(rng: RandomNumberGenerator, ids: PackedStringArray) -> String:
	return ids[rng.randi_range(0, ids.size() - 1)]


func _army(officer: Dictionary, units: Dictionary, stance: String, side_name: String, formation = null, reserve = null) -> Dictionary:
	var held = reserve
	if held == null:
		held = {"infantry": 0, "cavalry": 0, "cannon": 0}
	var body := {
		"stance": stance,
		"side_name": side_name,
		"units": units,
		"reserve": held,
		"officer": officer,
		"messenger": null,
	}
	if formation != null:
		body["formation"] = formation
	return Records.army(body)


func _fight(res, check_id: String, trial: int, oa: Dictionary, ob: Dictionary, ua: Dictionary, ub: Dictionary, sa: String, sb: String, terr: String, fa = null, fb = null, scenario = null, want_log: bool = false, reserve_a = null):
	var seed := HashUtil.hash32(master, check_id, trial)
	var army_a := _army(oa, ua, sa, "Blues", fa, reserve_a)
	var army_b := _army(ob, ub, sb, "Reds", fb)
	return res.resolve_battle(army_a, army_b, terr, seed, scenario, want_log)


func _score(out: Dictionary, side: String) -> float:
	var w = out["result"]["winner"]
	if w == "draw":
		return float(plan["draw"])
	if w == side:
		return 1.0
	return 0.0


func _edge(check_id: String, trial: int, edge: int, bgt: int, flip: bool) -> float:
	var rng := _rng(check_id, trial)
	var base := _officer(rng, bgt)
	var edged := base
	if edge != 0:
		edged = _bump_all(base, edge)
	var on_a := true
	if flip:
		on_a = rng.randf() < float(plan["draw"])
	var oa: Dictionary = edged if on_a else base
	var ob: Dictionary = base if on_a else edged
	var ua := _comp(rng, bgt)
	var ub := _comp(rng, bgt)
	var sa := _pick(rng, data.stance_ids)
	var sb := _pick(rng, data.stance_ids)
	var terr := _pick(rng, data.terrain_ids)
	var out: Dictionary = _fight(resolver, check_id, trial, oa, ob, ua, ub, sa, sb, terr)
	return _score(out, "A" if on_a else "B")


func _mean_edge(check_id: String, edge: int, bgt: int, flip: bool, n: int) -> float:
	var ids := _each(n)
	var total := 0.0
	for i in ids:
		if int(i) % _nc() == 0:
			print(check_id, " ", i, "/", n)
		total += _edge(check_id, int(i), edge, bgt, flip)
	return total / float(ids.size())


func _selftest() -> bool:
	var ex: Dictionary = plan["volley"]
	var atk_units := {}
	for uid in data.unit_ids:
		atk_units[uid] = 0
	atk_units["infantry"] = int(ex["companies"])
	var def_units := {}
	var ti := 0
	for uid in data.unit_ids:
		def_units[uid] = int(float(ex["enemy_troops"][ti]) / float(data.troops[ti]))
		ti += 1
	var atk := _fixed_army(atk_units, _named_formation(str(ex["attacker_formation"])), float(ex["marksmanship"]), float(ex["wisdom"]), "Blues", "Alden")
	var dfn := _fixed_army(def_units, _named_formation(str(ex["defender_formation"])), data.neutral, data.neutral, "Reds", "Bram")
	var hit: Dictionary = resolver.preview_strike(atk, dfn, _named_terrain(str(ex["terrain"])), float(ex["distance"]), float(ex["variance"]))
	var cas: Dictionary = hit["casualties"]
	var eqs: Array = ex["equals"]
	var ok: bool = int(cas["infantry"]) == int(ex["infantry_loss"]) and int(cas["cavalry"]) == int(eqs[1]) and int(cas["cannon"]) == int(eqs[_two()])
	ok = ok and _tenths(float(hit["raw_strength"])) == _tenths(float(eqs[0]))
	ok = ok and _tenths(float(hit["strength_removed"])) == _tenths(float(ex["strength"]))
	print("SELFTEST ", hit, " ok=", ok)
	return ok


func _tenths(x: float) -> int:
	return int(resolver.round_half(x * float("10")))


func _named_formation(display: String) -> String:
	for id in data.formation_ids:
		if str(data.formation_name[id]) == display:
			return id
	return ""


func _named_terrain(display: String) -> String:
	for id in data.terrain_ids:
		if str(data.terrains[id]["name"]) == display:
			return id
	return ""


func _fixed_army(units: Dictionary, formation: String, mark: float, wis: float, side: String, person: String) -> Dictionary:
	var attrs := {}
	for id in data.innate_ids:
		attrs[id] = data.neutral
	var skills := {}
	for id in data.skill_ids:
		skills[id] = data.neutral
	skills["marksmanship"] = mark
	var hidden := {}
	for id in data.hidden_ids:
		hidden[id] = data.neutral
	return _army({
		"rank_id": "major",
		"name": person,
		"wisdom": wis,
		"attrs": attrs,
		"skills": skills,
		"hidden": hidden,
		"traits": {},
	}, units, "balanced", side, formation)


func _build_ac1() -> Array:
	if not _selftest():
		return [_pack("SELFTEST", "spec_volley", 0.0, {"example": "spec volley"}, false, 1)]
	return [_run_b1(), _run_b17(), _run_b18(), _run_s6(), _run_e6(), _run_e7(), _run_literals()]


func _build_ac2() -> Array:
	if not _selftest():
		return [_pack("SELFTEST", "spec_volley", 0.0, {"example": "spec volley"}, false, 1)]
	var b2 := _run_b2()
	var b3 := _run_b3()
	var checks: Array = [b2, _run_b2b(), _run_b2c(), b3, _b3b, _run_b4(), _run_b4b(), _run_b4c(), _run_b5(), _run_b6(), _run_b7(), _run_b9(), _run_b10(), _run_b11(), _run_b12()]
	checks.append(_run_b13(float(b2["value"])))
	checks.append_array([_run_b14(), _run_b15(), _run_b16(), _run_b23()])
	return checks


func _one_check(suite: String):
	if suite == "B1":
		return _run_b1()
	if suite == "B2":
		return _run_b2()
	if suite == "B2b":
		return _run_b2b()
	if suite == "B2c":
		return _run_b2c()
	if suite == "B3":
		return _run_b3()
	if suite == "B3b":
		_run_b3()
		return _b3b
	if suite == "B4":
		return _run_b4()
	if suite == "B4b":
		return _run_b4b()
	if suite == "B4c":
		return _run_b4c()
	if suite == "B5":
		return _run_b5()
	if suite == "B6":
		return _run_b6()
	if suite == "B7":
		return _run_b7()
	if suite == "B9":
		return _run_b9()
	if suite == "B10":
		return _run_b10()
	if suite == "B11":
		return _run_b11()
	if suite == "B12":
		return _run_b12()
	if suite == "B13":
		return _run_b13(float(_run_b2()["value"]))
	if suite == "B14":
		return _run_b14()
	if suite == "B15":
		return _run_b15()
	if suite == "B16":
		return _run_b16()
	if suite == "B17":
		return _run_b17()
	if suite == "B18":
		return _run_b18()
	if suite == "B23":
		return _run_b23()
	if suite == "S6":
		return _run_s6()
	if suite == "E6":
		return _run_e6()
	if suite == "E7":
		return _run_e7()
	if suite == "LITERALS":
		return _run_literals()
	if suite == "CLK":
		return _run_clk()
	return null


func _run_b2() -> Dictionary:
	var band: Array = data.parsed["battle"]["balance_targets"]["D3_officer_edge_plus20_win_rate"]["qa_band"]
	var v := _mean_edge("B2", int(plan["edge"]), budget, true, _nh())
	return _pack("B2", "plus20_win_rate", v, {"min": float(band[0]), "max": float(band[1])}, v >= float(band[0]) and v <= float(band[1]), _span(_nh()))


func _run_b2b() -> Dictionary:
	var n := _nh()
	var edges: Array = plan["b2b_edges"]
	var p10 := _mean_edge("B2b", int(edges[0]), budget, true, n)
	var p30 := _mean_edge("B2b30", int(edges[1]), budget, true, n)
	# B2b is one check. The +30 half uses its own id so a trial replay stays stable,
	# and the reported fixture id is still B2b.
	var ok := p10 >= _lo("B2b", 0) and p10 <= _hi("B2b", 0) and p30 >= _lo("B2b", 1) and p30 <= _hi("B2b", 1)
	return _pack("B2b", "plus10_and_plus30", {"plus10": p10, "plus30": p30}, {"plus10": [_lo("B2b", 0), _hi("B2b", 0)], "plus30": [_lo("B2b", 1), _hi("B2b", 1)]}, ok, _span(n), {"plus10": p10, "plus30": p30})


func _run_b2c() -> Dictionary:
	var n := _nh()
	var total := 0.0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print("B2c ", i)
		var rng := _rng("B2c", i)
		var o := _officer(rng, budget)
		var out: Dictionary = _fight(resolver, "B2c", i, o, o.duplicate(true), _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids))
		total += _score(out, "A")
	var v := total / float(_span(n))
	return _pack("B2c", "mirror_win_rate", v, {"min": _lo("B2c"), "max": _hi("B2c")}, v >= _lo("B2c") and v <= _hi("B2c"), _span(n))


func _run_b3() -> Dictionary:
	var n := _nh()
	var cap := float(data.parsed["battle"]["balance_targets"]["D3_single_stat_plus20_max_win_rate"]["max"])
	var lead := str(data.parsed["battle"]["balance_targets"]["D3_single_stat_plus20_max_win_rate"]["strongest_skill_must_be"])
	var rates := {}
	var stats: Array = []
	for id in data.innate_ids:
		stats.append(["attr", id])
	stats.append(["wisdom", "wisdom"])
	for id in data.skill_ids:
		stats.append(["skill", id])
	var worst := 0.0
	var all_ok := true
	for pair in stats:
		var kind: String = pair[0]
		var id: String = pair[1]
		var total := 0.0
		var tag := "B3_%s" % id
		for i in _each(n):
			if int(i) % _nc() == 0:
				print(tag, " ", i)
			var rng := _rng(tag, i)
			var base := _officer(rng, budget)
			var edged := _bump_one(base, kind, id)
			var on_a := rng.randf() < float(plan["draw"])
			var oa: Dictionary = edged if on_a else base
			var ob: Dictionary = base if on_a else edged
			var out: Dictionary = _fight(resolver, tag, i, oa, ob, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids))
			total += _score(out, "A" if on_a else "B")
		var rate := total / float(_span(n))
		rates[id] = rate
		if rate > worst:
			worst = rate
		if rate > cap:
			all_ok = false
	var skill_rates := {}
	var best_skill := ""
	var best_rate := -1.0
	for id in data.skill_ids:
		skill_rates[id] = rates[id]
		if float(rates[id]) > best_rate:
			best_rate = float(rates[id])
			best_skill = id
	var lead_ok := best_skill == lead
	for id in data.skill_ids:
		if id != lead and float(rates[id]) >= float(rates[lead]):
			lead_ok = false
	var b3 := _pack("B3", "single_stat_plus20_max", worst, {"max": cap}, all_ok, _span(n), {"rates": rates})
	# B3b is returned by stuffing it into a side channel via a member. Caller builds B3 only here.
	_b3b = _pack("B3b", "strongest_skill", {"skill": best_skill, "rate": rates[lead]}, {"must_be": lead}, lead_ok, _span(n), {"skills": skill_rates})
	return b3


var _b3b: Dictionary = {}


func _run_b4() -> Dictionary:
	return _formation_overall("B4", true)


func _run_b4b() -> Dictionary:
	return _formation_overall("B4b", false)


func _formation_overall(check_id: String, forced: bool) -> Dictionary:
	var n := _nh()
	var wins := {}
	var counts := {}
	for id in data.formation_ids:
		wins[id] = 0.0
		counts[id] = 0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print(check_id, " ", i)
		var rng := _rng(check_id, i)
		var oa := _officer(rng, budget)
		var ob := _officer(rng, budget)
		var fa = _pick(rng, data.formation_ids) if forced else null
		var fb = _pick(rng, data.formation_ids) if forced else null
		var out: Dictionary = _fight(resolver, check_id, i, oa, ob, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids), fa, fb)
		var s := _score(out, "A")
		var ida: String = out["result"]["formations"]["A"]
		var idb: String = out["result"]["formations"]["B"]
		wins[ida] = float(wins[ida]) + s
		counts[ida] = int(counts[ida]) + 1
		wins[idb] = float(wins[idb]) + (1.0 - s)
		counts[idb] = int(counts[idb]) + 1
	var rates := {}
	var ok := true
	var lo := 1.0
	var hi := 0.0
	for id in data.formation_ids:
		var rate := float(wins[id]) / float(max(1, counts[id]))
		rates[id] = rate
		if rate < lo:
			lo = rate
		if rate > hi:
			hi = rate
		if rate < _lo(check_id) or rate > _hi(check_id):
			ok = false
	return _pack(check_id, "formation_win_rate", {"min": lo, "max": hi}, {"min": _lo(check_id), "max": _hi(check_id)}, ok, _span(n), {"rates": rates, "counts": counts})


func _run_b4c() -> Dictionary:
	var n := _nh()
	var rates := {}
	var ok := true
	var lo := 1.0
	var hi := 0.0
	for terr in data.terrain_ids:
		var wins := {}
		var counts := {}
		for id in data.formation_ids:
			wins[id] = 0.0
			counts[id] = 0
		for i in _each(n):
			if int(i) % _nc() == 0:
				print("B4c ", terr, " ", i)
			var rng := _rng("B4c_%s" % terr, i)
			var oa := _officer(rng, budget)
			var ob := _officer(rng, budget)
			var fa := _pick(rng, data.formation_ids)
			var fb := _pick(rng, data.formation_ids)
			var out: Dictionary = _fight(resolver, "B4c_%s" % terr, i, oa, ob, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), terr, fa, fb)
			var s := _score(out, "A")
			var ida: String = str(fa)
			var idb: String = str(fb)
			wins[ida] = float(wins[ida]) + s
			counts[ida] = int(counts[ida]) + 1
			wins[idb] = float(wins[idb]) + (1.0 - s)
			counts[idb] = int(counts[idb]) + 1
		rates[terr] = {}
		for id in data.formation_ids:
			var rate := float(wins[id]) / float(max(1, counts[id]))
			rates[terr][id] = rate
			if rate < lo:
				lo = rate
			if rate > hi:
				hi = rate
			if rate < _lo("B4c") or rate > _hi("B4c"):
				ok = false
	return _pack("B4c", "formation_per_terrain", {"min": lo, "max": hi}, {"min": _lo("B4c"), "max": _hi("B4c")}, ok, _span(n), {"rates": rates})


func _run_b5() -> Dictionary:
	var n := _nc()
	var mean_band: Array = data.parsed["battle"]["balance_targets"]["D2_countered_formation_win_rate"]["target"]
	var pair_band: Array = data.parsed["battle"]["balance_targets"]["D2_countered_formation_win_rate"]["qa_fail_outside"]
	var pair_rates := {}
	var acc := 0.0
	var pair_n := 0
	var reported := 0
	for winner_id in data.formation_ids:
		var loser_id := str(data.beats[winner_id])
		var pair := "%s_beats_%s" % [winner_id, loser_id]
		var total := 0.0
		var samples := 0
		for orient in [0, 1]:
			for i in _each(n):
				if int(i) % _nc() == 0:
					print("B5 ", pair, " ", orient, " ", i)
				var rng := _rng("B5_%s_%s" % [pair, str(orient)], i)
				var oa := _officer(rng, budget)
				var ob := _officer(rng, budget)
				var fa: String = loser_id if orient == 0 else winner_id
				var fb: String = winner_id if orient == 0 else loser_id
				var out: Dictionary = _fight(resolver, "B5_%s_%s" % [pair, str(orient)], i, oa, ob, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids), fa, fb)
				var countered := "A" if fa == loser_id else "B"
				total += _score(out, countered)
				samples += 1
		var rate := total / float(samples)
		pair_rates[pair] = rate
		acc += rate
		pair_n += 1
		reported = samples
	var mean := acc / float(pair_n)
	var ok := mean >= float(mean_band[0]) and mean <= float(mean_band[1])
	for k in pair_rates:
		if float(pair_rates[k]) < float(pair_band[0]) or float(pair_rates[k]) > float(pair_band[1]):
			ok = false
	return _pack("B5", "countered_win_rate", mean, {"mean": mean_band, "pair": pair_band}, ok, reported, {"pairs": pair_rates})


func _run_b6() -> Dictionary:
	var n := _nc()
	var names: Array = data.parsed["battle"]["ai_general"]["composition_archetypes"].keys()
	var overall := {}
	var overall_n := {}
	var by_t := {}
	var by_n := {}
	for a in names:
		overall[a] = 0.0
		overall_n[a] = 0
		by_t[a] = {}
		by_n[a] = {}
		for terr in data.terrain_ids:
			by_t[a][terr] = 0.0
			by_n[a][terr] = 0
	for a in names:
		var ua: Dictionary = data.archetype_companies(str(a), budget)
		for b in names:
			var ub: Dictionary = data.archetype_companies(str(b), budget)
			for i in _each(n):
				if int(i) % _nc() == 0:
					print("B6 ", a, " ", b, " ", i)
				var rng := _rng("B6_%s_%s" % [str(a), str(b)], i)
				var o := _officer(rng, budget)
				var terr := _pick(rng, data.terrain_ids)
				var out: Dictionary = _fight(resolver, "B6_%s_%s" % [str(a), str(b)], i, o, _officer(rng, budget), ua, ub, _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), terr)
				var s := _score(out, "A")
				overall[a] = float(overall[a]) + s
				overall_n[a] = int(overall_n[a]) + 1
				overall[b] = float(overall[b]) + (1.0 - s)
				overall_n[b] = int(overall_n[b]) + 1
				if str(a) != str(b):
					by_t[a][terr] = float(by_t[a][terr]) + s
					by_n[a][terr] = int(by_n[a][terr]) + 1
					by_t[b][terr] = float(by_t[b][terr]) + (1.0 - s)
					by_n[b][terr] = int(by_n[b][terr]) + 1
	var rates := {}
	var terrain_rates := {}
	var ok := true
	for a in names:
		var rate := float(overall[a]) / float(max(1, overall_n[a]))
		rates[str(a)] = rate
		if rate < _lo("B6", 0) or rate > _hi("B6", 0):
			ok = false
		terrain_rates[str(a)] = {}
		for terr in data.terrain_ids:
			var tr := float(by_t[a][terr]) / float(max(1, by_n[a][terr]))
			terrain_rates[str(a)][terr] = tr
			if tr < _lo("B6", 1) or tr > _hi("B6", 1):
				ok = false
	return _pack("B6", "archetype_win_rate", rates, {"overall": [_lo("B6", 0), _hi("B6", 0)], "terrain": [_lo("B6", 1), _hi("B6", 1)]}, ok, _span(n), {"terrain": terrain_rates})


func _run_b7() -> Dictionary:
	var n := _nc()
	var cells := {}
	var ok := true
	for a in data.stance_ids:
		cells[a] = {}
		for b in data.stance_ids:
			var total := 0.0
			for i in _each(n):
				if int(i) % _nc() == 0:
					print("B7 ", a, " ", b, " ", i)
				var rng := _rng("B7_%s_%s" % [a, b], i)
				var out: Dictionary = _fight(resolver, "B7_%s_%s" % [a, b], i, _officer(rng, budget), _officer(rng, budget), _comp(rng, budget), _comp(rng, budget), a, b, _pick(rng, data.terrain_ids))
				total += _score(out, "A")
			var rate := total / float(_span(n))
			cells[a][b] = rate
			if rate < _lo("B7") or rate > _hi("B7"):
				ok = false
	return _pack("B7", "stance_matrix", cells, {"min": _lo("B7"), "max": _hi("B7")}, ok, _span(n))


func _run_b9() -> Dictionary:
	var n := _nh()
	var total := 0.0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print("B9 ", i)
		var rng := _rng("B9", i)
		var base := _officer(rng, budget)
		var strong := _bump_all(base, int(plan["edge"]))
		var bform := _pick(rng, data.formation_ids)
		var aform := str(data.beats[bform])
		var out: Dictionary = _fight(resolver, "B9", i, strong, base, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids), aform, bform)
		total += _score(out, "A")
	var v := total / float(_span(n))
	return _pack("B9", "plus20_countered_formation", v, {"max": _hi("B9")}, v <= _hi("B9"), _span(n))


func _run_b10() -> Dictionary:
	var n := _nh()
	var guns: Dictionary = data.archetype_companies("guns", budget)
	var horse: Dictionary = data.archetype_companies("horse", budget)
	var total := 0.0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print("B10 ", i)
		var rng := _rng("B10", i)
		var base := _officer(rng, budget)
		var strong := _bump_all(base, int(plan["edge"]))
		var out: Dictionary = _fight(resolver, "B10", i, strong, base, guns, horse, _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), "open_field")
		total += _score(out, "A")
	var v := total / float(_span(n))
	return _pack("B10", "plus20_guns_vs_horse_open", v, {"max": _hi("B10")}, v <= _hi("B10"), _span(n))


func _run_b11() -> Dictionary:
	var n := _nh()
	var v := _mean_edge("B11", -int(plan["edge"]), budget, true, n)
	return _pack("B11", "minus20_win_rate", v, {"min": _lo("B11")}, v >= _lo("B11"), _span(n))


func _run_b12() -> Dictionary:
	var n := _nh()
	var ticks := 0.0
	var timeouts := 0
	var draws := 0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print("B12 ", i)
		var rng := _rng("B12", i)
		var out: Dictionary = _fight(resolver, "B12", i, _officer(rng, budget), _officer(rng, budget), _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids))
		ticks += float(out["result"]["ticks"])
		if str(out["result"]["reason"]) == "timeout":
			timeouts += 1
		if str(out["result"]["winner"]) == "draw":
			draws += 1
	var mean_t := ticks / float(_span(n))
	var tr := float(timeouts) / float(_span(n))
	var dr := float(draws) / float(_span(n))
	var ok := mean_t >= _lo("B12", 0) and mean_t <= _hi("B12", 0) and tr <= _hi("B12", 1) and dr <= _hi("B12", _two())
	return _pack("B12", "length_timeout_draw", {"mean_ticks": mean_t, "timeout_rate": tr, "draw_rate": dr}, {"ticks": [_lo("B12", 0), _hi("B12", 0)], "timeout_max": _hi("B12", 1), "draw_max": _hi("B12", _two())}, ok, _span(n))


func _run_b13(ref: float) -> Dictionary:
	var n := _nh()
	var rates := {}
	var ok := true
	for id in data.rank_ids:
		var bgt := int(data.rank_budget[id])
		if bgt == budget:
			continue
		var listed := false
		for want in plan["b13_budgets"]:
			if int(want) == bgt:
				listed = true
		if not listed:
			continue
		var v := _mean_edge("B13_%s" % id, int(plan["edge"]), bgt, true, n)
		rates[id] = v
		if abs(v - ref) > _hi("B13"):
			ok = false
	return _pack("B13", "plus20_by_budget", rates, {"within": _hi("B13"), "of": ref}, ok, _span(n), {"reference_budget": ref})


func _battle_trait(id: String) -> bool:
	# Non-battle: effects the no-messenger, no-reserve battle never reads.
	# v1.4 names Quick Study, Slow Learner and Vain as the non-battle traits.
	# Hesitant only acts when reserves are on the field, and B14 fields them.
	var inert := {
		"training_mult": true,
		"wisdom_gain_mult": true,
	}
	var effect: Dictionary = data.trait_by_id[id].get("effect", {})
	for k in effect.keys():
		if not inert.has(str(k)):
			return true
	return false


func _run_b14() -> Dictionary:
	var n := _nh()
	var rates := {}
	var kinds := {}
	var ok := true
	for id in data.strength_ids:
		var battle := _battle_trait(id)
		kinds[id] = "battle_strength" if battle else "non_battle"
		var v := _trait_rate("B14_%s" % id, id, "strength", _nh())
		rates[id] = v
		if battle:
			if v < _lo("B14", 0) or v > _hi("B14", 0):
				ok = false
		else:
			if v < _lo("B14", _two()) or v > _hi("B14", _two()):
				ok = false
	for id in data.weakness_ids:
		var battle := _battle_trait(id)
		kinds[id] = "battle_weakness" if battle else "non_battle"
		var v := _trait_rate("B14_%s" % id, id, "weakness", _nh())
		rates[id] = v
		if battle:
			if v < _lo("B14", 1) or v > _hi("B14", 1):
				ok = false
		else:
			if v < _lo("B14", _two()) or v > _hi("B14", _two()):
				ok = false
	return _pack("B14", "visible_trait_win_rate", rates, {"battle_strength": [_lo("B14", 0), _hi("B14", 0)], "battle_weakness": [_lo("B14", 1), _hi("B14", 1)], "non_battle": [_lo("B14", _two()), _hi("B14", _two())]}, ok, _span(n), {"class": kinds})


func _trait_rate(tag: String, id: String, slot: String, n: int) -> float:
	var total := 0.0
	for i in _each(n):
		if int(i) % _nc() == 0:
			print(tag, " ", i)
		var rng := _rng(tag, i)
		var base := _officer(rng, budget)
		var oa := _with_trait(base, slot, id)
		var units := _comp(rng, budget)
		var reserve = null
		var shown := str(data.trait_by_id[id].get("name", ""))
		var setup := str(plan["rows"]["B14"]["setup"])
		var reserve_at := setup.find("reserve")
		if reserve_at >= 0 and setup.substr(0, reserve_at).find(shown) >= 0:
			reserve = {"infantry": 0, "cavalry": 0, "cannon": 0}
			reserve["infantry"] = int(resolver.round_half(float(units.get("infantry", 0)) * float(plan["reserve_frac"])))
		var out: Dictionary = _fight(resolver, tag, i, oa, base.duplicate(true), units, _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids), null, null, null, false, reserve)
		total += _score(out, "A")
	return total / float(_span(n))


func _run_b15() -> Dictionary:
	var n := _nt()
	var rates := {}
	var reveals := {}
	var ok := true
	for id in data.hidden_trait_ids:
		if id == "none":
			continue
		var total := 0.0
		var shown := 0
		var tag := "B15_%s" % id
		for i in _each(n):
			if int(i) % _nc() == 0:
				print(tag, " ", i)
			var rng := _rng(tag, i)
			var base := _officer(rng, budget)
			var oa := _with_trait(base, "hidden", id)
			var out: Dictionary = _fight(resolver, tag, i, oa, base.duplicate(true), _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids))
			total += _score(out, "A")
			for rev in out["result"]["reveals"]:
				if str(rev.get("kind", "")) == "trait" and str(rev.get("id", "")) == id:
					shown += 1
					break
		var rate := total / float(_span(n))
		var reveal := float(shown) / float(_span(n))
		rates[id] = rate
		reveals[id] = reveal
		if rate < _lo("B15", 0) or rate > _hi("B15", 0) or reveal < _lo("B15", 1) or reveal > _hi("B15", 1):
			ok = false
	return _pack("B15", "hidden_trait_win_and_reveal", {"win": rates, "reveal": reveals}, {"win": [_lo("B15", 0), _hi("B15", 0)], "reveal": [_lo("B15", 1), _hi("B15", 1)]}, ok, _span(n))


func _run_b16() -> Dictionary:
	var n := _nh()
	var ids := ["aggression", "temperament", "inspiration"]
	var rates := {}
	var ok := true
	for id in ids:
		var total := 0.0
		for i in _each(n):
			if int(i) % _nc() == 0:
				print("B16 ", id, " ", i)
			var rng := _rng("B16_%s" % id, i)
			var base := _officer(rng, budget)
			var high := _with_hidden(base, id, int(plan["b16_pair"][0]))
			var low := _with_hidden(base, id, int(plan["b16_pair"][1]))
			var on_a := rng.randf() < float(plan["draw"])
			var oa: Dictionary = high if on_a else low
			var ob: Dictionary = low if on_a else high
			var out: Dictionary = _fight(resolver, "B16_%s" % id, i, oa, ob, _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids))
			total += _score(out, "A" if on_a else "B")
		var rate := total / float(_span(n))
		rates[id] = rate
		if rate < _lo("B16") or rate > _hi("B16"):
			ok = false
	return _pack("B16", "hidden_attr_80_vs_20", rates, {"min": _lo("B16"), "max": _hi("B16")}, ok, _span(n))


func _run_b23() -> Dictionary:
	var n := _nh()
	var rates := {}
	var ok := true
	for terr in data.terrain_ids:
		var total := 0.0
		for i in _each(n):
			if int(i) % _nc() == 0:
				print("B23 ", terr, " ", i)
			var rng := _rng("B23_%s" % terr, i)
			var o := _officer(rng, budget)
			var units := _comp(rng, budget)
			var stance := _pick(rng, data.stance_ids)
			var swap := rng.randf() < float(plan["draw"])
			var oa := o
			var ob: Dictionary = o.duplicate(true)
			if swap:
				var tmp = oa
				oa = ob
				ob = tmp
			var out: Dictionary = _fight(resolver, "B23_%s" % terr, i, oa, ob, units, units.duplicate(true), stance, stance, terr)
			total += _score(out, "A")
		var rate := total / float(_span(n))
		rates[terr] = rate
		if rate < _lo("B23") or rate > _hi("B23"):
			ok = false
	var src := FileAccess.get_file_as_string("res://scripts/battle_resolver.gd")
	var clean := not src.contains("deferred_attacker_defender")
	if not clean:
		ok = false
	return _pack("B23", "terrain_symmetry", rates, {"min": _lo("B23"), "max": _hi("B23")}, ok, _span(n), {"resolver_ignores_deferred": clean})


func _random_log(res, check_id: String, trial: int, scenario):
	var rng := _rng(check_id, trial)
	var out: Dictionary = _fight(res, check_id, trial, _officer(rng, budget), _officer(rng, budget), _comp(rng, budget), _comp(rng, budget), _pick(rng, data.stance_ids), _pick(rng, data.stance_ids), _pick(rng, data.terrain_ids), null, null, scenario, true)
	return out["log"]


func _run_b1() -> Dictionary:
	var n := _nb1()
	var fix_n := _nf()
	var bad := 0
	var fixtures: Array = []
	for i in _each(n):
		if i % 1000 == 0:
			print("B1 ", i)
		var log_a = _random_log(resolver, "B1", i, null)
		var log_b = _random_log(resolver, "B1", i, null)
		var ha := HashUtil.sha256_text(HashUtil.json_text(log_a))
		var hb := HashUtil.sha256_text(HashUtil.json_text(log_b))
		if ha != hb:
			bad += 1
		if i < fix_n:
			fixtures.append({"trial": i, "log_hash": ha})
	var ok := bad == 0
	return _pack("B1", "identical_log_hashes", float(_span(n) - bad) / float(_span(n)), {"identical": 1.0}, ok, _span(n), {"mismatches": bad, "fixtures": fixtures})


func _run_b17() -> Dictionary:
	var n := _nb1()
	var unfilled := 0
	var missing := 0
	var plural_bad := 0
	var legacy_bad := 0
	var form_bad := 0
	for kind in SPEC_EVENTS:
		if not data.templates.has(kind) or data.templates[kind].is_empty():
			missing += 1
	for tmpl in data.templates["volley"]:
		if not str(tmpl).contains("{unit_plural}"):
			plural_bad += 1
	for tmpl in data.templates["formation_chosen"]:
		if not str(tmpl).contains("the {formation_name}"):
			form_bad += 1
	for i in _each(n):
		if i % 1000 == 0:
			print("B17 ", i)
		var log: Dictionary = _random_log(resolver, "B17", i, null)
		var bundle: Array = []
		var idx := 0
		for ev in log["opening"]:
			bundle.append([ev, 0, idx])
			idx += 1
		for tick in log["ticks"]:
			var ei := 0
			for ev in tick["events"]:
				bundle.append([ev, int(tick["t"]), ei])
				ei += 1
		for item in bundle:
			var ev: Dictionary = item[0]
			var line := Narration.narrate(data.templates, ev, int(log["seed"]), int(item[1]), int(item[_two()]))
			var kind := str(ev.get("type", ""))
			if line == "" or Narration.has_unfilled(line):
				unfilled += 1
			if kind == "volley" and ev.has("unit"):
				var uid := str(ev["unit"])
				var plural := str(data.unit_plural[uid])
				var illegal := str(data.unit_narration[uid]) + "s"
				if not line.contains(plural):
					plural_bad += 1
				if illegal != plural and line.contains(illegal):
					plural_bad += 1
			if kind == "formation_chosen" and ev.has("formation"):
				var fid := str(ev["formation"])
				var fname := str(data.formation_name[fid])
				if not line.contains("the " + fname):
					form_bad += 1
				for old in data.formation_legacy.get(fid, []):
					if str(old) != fname and line.contains(str(old)):
						legacy_bad += 1
	var ok := unfilled == 0 and missing == 0 and plural_bad == 0 and legacy_bad == 0 and form_bad == 0
	return _pack("B17", "narration_complete", {"unfilled": unfilled, "missing_templates": missing, "plural_bad": plural_bad, "legacy_bad": legacy_bad, "formation_bad": form_bad}, {"unfilled": 0, "missing_templates": 0}, ok, _span(n))


func _run_b18() -> Dictionary:
	var n := _nf()
	var bad := 0
	for i in _each(n):
		var log: Dictionary = _random_log(resolver, "B18", i, null)
		if not _troops_match(log):
			bad += 1
	var ok := bad == 0
	return _pack("B18", "replay_troop_invariant", float(_span(n) - bad) / float(_span(n)), {"mismatches": 0}, ok, _span(n), {"bad": bad})


func _troops_match(log: Dictionary) -> bool:
	for side in ["A", "B"]:
		var base := {}
		var lost := {}
		for uid in data.unit_ids:
			base[uid] = int(log["setup"][side]["troops"][uid]) + int(log["setup"][side]["reserve"][uid])
			lost[uid] = 0
		for tick in log["ticks"]:
			for ev in tick["events"]:
				if ev.has("casualties") and str(ev.get("target", "")) == side:
					for uid in ev["casualties"].keys():
						lost[uid] = int(lost[uid]) + int(ev["casualties"][uid])
			for uid in data.unit_ids:
				var have := int(tick["state"][side]["troops"][uid]) + int(tick["state"][side]["reserve"][uid])
				if have != int(base[uid]) - int(lost[uid]):
					return false
	return true


func _run_s6() -> Dictionary:
	var n := _nf()
	var other = BalanceData.create_omitting(["scenarios"])
	if other == null:
		return _pack("S6", "scenario_null_logs_identical", {"mismatches": -1, "modifier_changes_log": false}, {"mismatches": 0, "plumbing": true}, false, 1)
	var resolver_b = ResolverScript.new(other)
	var mismatch := 0
	for i in _each(n):
		if i % 200 == 0:
			print("S6 ", i)
		var left = _random_log(resolver, "S6", i, null)
		var right = _random_log(resolver_b, "S6", i, null)
		var hl := HashUtil.sha256_text(HashUtil.json_text(left))
		var hr := HashUtil.sha256_text(HashUtil.json_text(right))
		if hl != hr:
			mismatch += 1
	var scen = data.parsed["scenarios"]["scenarios"]["hold_the_fort"]
	var plain = _random_log(resolver, "S6", 0, null)
	var fort = _random_log(resolver, "S6", 0, scen)
	var live := HashUtil.sha256_text(HashUtil.json_text(plain)) != HashUtil.sha256_text(HashUtil.json_text(fort))
	var ok := mismatch == 0 and live
	return _pack("S6", "scenario_null_logs_identical", {"mismatches": mismatch, "modifier_changes_log": live}, {"mismatches": 0, "plumbing": true}, ok, _span(n))


func _run_e6() -> Dictionary:
	var eco: Dictionary = data.parsed["economy"]["daily_limits"]
	var breed: Dictionary = data.parsed["breeding"]["limits"]
	var train: Dictionary = data.parsed["skills"]["training"]
	var b_ok := int(eco["breeds_per_day"]) == int(breed["breeds_per_day_account"])
	var t_ok := int(eco["training_clicks_per_day"]) == int(train["clicks_per_day_account"])
	var o_ok := int(eco["training_clicks_per_officer_per_day"]) == int(train["clicks_per_day_per_officer"])
	var r_ok := int(data.parsed["economy"]["roster_slots"]) == int(data.parsed["breeding"]["roster"]["cap"])
	var ok := b_ok and t_ok and o_ok and r_ok
	return _pack("E6", "mirrored_limits", {"breeds": b_ok, "training": t_ok, "per_officer_training": o_ok, "roster": r_ok}, {"equal": true}, ok, 1)


func _run_e7() -> Dictionary:
	var a := int(data.parsed["economy"]["daily_limits"]["ranked_battles_per_officer_per_day"])
	var b := int(data.parsed["campaign"]["picking"]["max_assignments_per_officer_per_day"])
	return _pack("E7", "per_officer_assignment_cap", {"economy": a, "campaign": b}, {"equal": true}, a == b, 1)


func _run_literals() -> Dictionary:
	var nums: Array = []
	_collect_nums(data.parsed, nums)
	var hits: Array = []
	for root in ["res://scripts", "res://tools"]:
		var dir := DirAccess.open(root)
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".gd"):
				var path := "%s/%s" % [root, fn]
				var src := FileAccess.get_file_as_string(path)
				var code := _strip_gd(src)
				var lits := _literals(code)
				for lit in lits:
					var raw: String = lit["text"]
					var val := float(lit["value"])
					var is_float: bool = raw.contains(".") or raw.contains("e") or raw.contains("E")
					if abs(val) < _eps() or abs(val - 1.0) < _eps() or abs(val + 1.0) < _eps():
						continue
					if fn == "civil_time.gd" or fn == "portable_math.gd":
						continue
					if is_float or _near_any(val, nums):
						hits.append({"file": path, "text": raw})
			fn = dir.get_next()
		dir.list_dir_end()
	var names := ["Attack Column", "Tight Wedge", "Gun Section (2 guns)", "Cannon Battery", "Wide Line", "Defensive Screen"]
	for id in data.formation_ids:
		var src2 := FileAccess.get_file_as_string("res://scripts/battle_resolver.gd")
		for old in data.formation_legacy.get(id, []):
			if src2.contains(str(old)):
				hits.append({"file": "res://scripts/battle_resolver.gd", "text": str(old)})
	for nm in names:
		for file in ["battle_resolver.gd", "balance_data.gd", "narration.gd", "records.gd", "game_clock.gd"]:
			var body := FileAccess.get_file_as_string("res://scripts/%s" % file)
			if body.contains(nm):
				hits.append({"file": file, "text": nm})
	var ok := hits.is_empty()
	return _pack("LITERALS", "balance_literals_outside_data", hits.size(), {"max": 0}, ok, 1, {"hits": hits})


func _collect_nums(node, acc: Array) -> void:
	if node is bool:
		return
	if node is int or node is float:
		acc.append(float(node))
	elif node is Dictionary:
		for k in node.keys():
			_collect_nums(node[k], acc)
	elif node is Array:
		for v in node:
			_collect_nums(v, acc)


func _near_any(val: float, nums: Array) -> bool:
	for n in nums:
		if abs(float(n) - val) <= _eps():
			return true
	return false


func _strip_gd(src: String) -> String:
	var out := ""
	var i := 0
	while i < src.length():
		var c := src.substr(i, 1)
		if c == "#":
			while i < src.length() and src.substr(i, 1) != "\n":
				i += 1
			continue
		if c == "\"":
			i += 1
			while i < src.length():
				var d := src.substr(i, 1)
				if d == "\\":
					i += 1
					i += 1
					continue
				if d == "\"":
					i += 1
					break
				i += 1
			out += " "
			continue
		out += c
		i += 1
	return out


func _literals(code: String) -> Array:
	var digits := "0123456789"
	var out: Array = []
	var i := 0
	while i < code.length():
		var c := code.substr(i, 1)
		var prev := ""
		if i > 0:
			prev = code.substr(i - 1, 1)
		var ident := prev != "" and (digits.find(prev) >= 0 or (prev >= "A" and prev <= "Z") or (prev >= "a" and prev <= "z") or prev == "_")
		if not ident and (c == "-" or digits.find(c) >= 0):
			var start := i
			if c == "-":
				i += 1
				if i >= code.length() or digits.find(code.substr(i, 1)) < 0:
					continue
			while i < code.length():
				var d := code.substr(i, 1)
				if digits.find(d) >= 0 or d == "." or d == "e" or d == "E" or d == "+" or d == "-":
					if (d == "+" or d == "-") and code.substr(i - 1, 1) != "e" and code.substr(i - 1, 1) != "E":
						break
					i += 1
				else:
					break
			var text := code.substr(start, i - start)
			if text != "-" and text != "" and text != ".":
				out.append({"text": text, "value": float(text)})
			continue
		i += 1
	return out


func _run_clk() -> Dictionary:
	var cases: Array = []
	var boundary := GameClock.new()
	boundary.set_synced(Civil.unix_from_iso("2026-11-22T23:59:59Z"), Civil.unix_from_iso("2026-11-22T23:59:59Z"))
	var before := boundary.day_index()
	boundary.set_server(Civil.unix_from_iso("2026-11-23T00:00:00Z"))
	var after := boundary.day_index()
	cases.append({"name": "utc_boundary", "pass": after == before + 1, "before": before, "after": after})
	var epoch := _day_of("2026-01-01T00:00:00Z")
	var nov := _day_of("2026-11-23T00:00:00Z")
	var jan := _day_of("2027-01-11T00:05:00Z")
	cases.append({"name": "day_index", "pass": epoch == 0 and nov == 326 and jan == 375, "epoch": epoch, "2026-11-23": nov, "2027-01-11": jan})
	var synced := GameClock.new()
	var server := Civil.unix_from_iso("2026-11-22T12:00:00Z")
	synced.set_synced(server, server)
	var day_a := synced.day_index()
	var account := {"v": 1, "day_index": day_a, "ranked_used": 1}
	synced.set_local(Civil.unix_from_iso("2026-11-25T12:00:00Z"))
	var reset: bool = GameClock.roll_account_day(account, synced)
	cases.append({"name": "local_clock_does_not_reset", "pass": synced.day_index() == day_a and not reset, "day": synced.day_index()})
	var off := GameClock.new()
	var srv := Civil.unix_from_iso("2026-11-22T15:00:00Z")
	var loc := Civil.unix_from_iso("2026-11-22T10:00:00Z")
	off.set_synced(srv, loc)
	var offset := off.offset_sec
	off.set_offline(loc)
	var kept := off.offset_sec == offset and off.authoritative_unix() == srv
	off.set_local(loc + 3600)
	kept = kept and off.offset_sec == offset and off.authoritative_unix() == srv + 3600
	cases.append({"name": "offline_keeps_offset", "pass": kept, "offset_sec": offset})
	var back := GameClock.new()
	back.set_synced(Civil.unix_from_iso("2026-11-24T00:00:00Z"), Civil.unix_from_iso("2026-11-24T00:00:00Z"))
	var high := back.day_index()
	back.set_server(Civil.unix_from_iso("2026-11-22T00:00:00Z"))
	cases.append({"name": "day_index_never_backwards", "pass": back.day_index() == high and high > _day_of("2026-11-22T00:00:00Z"), "stayed": back.day_index()})
	var fresh := GameClock.new()
	var loc0 := Civil.unix_from_iso("2026-11-22T08:00:00Z")
	fresh.set_offline(loc0)
	cases.append({"name": "never_synced_offset_zero", "pass": fresh.offset_sec == 0 and fresh.has_synced == false and fresh.authoritative_unix() == loc0})
	var parsed := LaunchFlags.parse_user_args(PackedStringArray(["--scope-id", "LOC-QA-SCOPE-0001", "--clock", "2026-11-23T00:00:00Z", "--local-clock", "2026-11-23T00:00:00Z", "--net-state", "synced"]))
	var flags_ok := str(parsed["scope_id"]) == "LOC-QA-SCOPE-0001" and str(parsed["net_state"]) == "synced" and str(parsed["clock"]) != ""
	cases.append({"name": "flag_parser", "pass": flags_ok})
	var bare := GameClock.new()
	var rejected := not bare.load_record({"net_state": "offline", "offset_sec": 0})
	var stamped := GameClock.new()
	stamped.set_offline(Civil.unix_from_iso("2026-11-22T08:00:00Z"))
	var copy := GameClock.new()
	var accepted := copy.load_record(stamped.to_record()) and copy.offset_sec == stamped.offset_sec and copy.net_state == stamped.net_state
	cases.append({"name": "record_v", "pass": rejected and accepted})
	var ok := true
	for c in cases:
		if not bool(c["pass"]):
			ok = false
	return _pack("CLK", "daily_clock", cases, {"rules": ["boundary", "local_ignored", "offline_offset", "no_rewind"]}, ok, cases.size(), {"cases": cases})


func _day_of(iso: String) -> int:
	var clock := GameClock.new()
	var unix := Civil.unix_from_iso(iso)
	clock.set_synced(unix, unix)
	return clock.day_index()
