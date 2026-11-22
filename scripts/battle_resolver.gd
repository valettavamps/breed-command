extends RefCounted
## Pure resolve_battle. No clock, file IO, scene tree, or global RNG.
## Tables come from BalanceData. The battle seed constructs a local PCG32.
## Formation and unit logic uses ids. Display names are narration fills only.
## Counter multipliers are read from formations.matchup_damage_mult.

const HashUtil = preload("res://scripts/hash_util.gd")
const Narration = preload("res://scripts/narration.gd")
const Records = preload("res://scripts/records.gd")

var _d
var log_on = false
var seed_value = 0
var scenario = null
var scenario_id = null
var terrain_id = ""
var terr = {}
var dist = 0.0
var opening: Array = []
var emit_target: Array = []
var reveals: Array = []
var defender = null
var attacker = null
var loss_frac = 0.0
var hold_ticks = 0
var use_objective = false


func _init(balance) -> void:
	_d = balance


func round_half(x: float) -> int:
	if x >= 0.0:
		return int(floor(x + _d.half))
	return int(ceil(x - _d.half))


func resolve_battle(army_a: Dictionary, army_b: Dictionary, terrain: String, seed: int, scenario_in = null, record_log: bool = true) -> Dictionary:
	_begin(terrain, seed, scenario_in, record_log)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var side_a = _make_side(army_a, "A")
	var side_b = _make_side(army_b, "B")
	_bind_scenario(side_a, side_b)
	var gumbel_a = _draw_gumbels(rng)
	var gumbel_b = _draw_gumbels(rng)
	_choose_formation(side_a, side_b, gumbel_a)
	_choose_formation(side_b, side_a, gumbel_b)
	_finish_side(side_a)
	_finish_side(side_b)
	_build_packs(side_a, side_b)
	_build_packs(side_b, side_a)
	var ticks: Array = []
	var winner = ""
	var reason = ""
	var ended = false
	var last_tick = 0
	_opening(side_a, side_b)
	for tick in range(1, _d.max_ticks + 1):
		last_tick = tick
		emit_target = []
		_trigger_rash(side_a)
		_trigger_rash(side_b)
		_arrive(side_a, tick)
		_arrive(side_b, tick)
		_auto_reserve(side_a, tick)
		_auto_reserve(side_b, tick)
		_move(side_a, side_b)
		var va = rng.randf_range(_d.var_min, _d.var_max)
		var vb = rng.randf_range(_d.var_min, _d.var_max)
		var na = rng.randf_range(-_noise_amp(side_a), _noise_amp(side_a))
		var nb = rng.randf_range(-_noise_amp(side_b), _noise_amp(side_b))
		var hit_b = _combat(side_a, side_b, va)
		var hit_a = _combat(side_b, side_a, vb)
		_maybe_lucky(side_b, hit_b)
		_maybe_lucky(side_a, hit_a)
		var took_b = _apply_hits(side_b, side_a, hit_b)
		var took_a = _apply_hits(side_a, side_b, hit_a)
		if log_on:
			_emit_strikes(side_a, side_b, hit_b, took_b["lost"], _lost_head(took_a))
			_emit_strikes(side_b, side_a, hit_a, took_a["lost"], _lost_head(took_b))
		_flag_first_hits(side_b, took_b)
		_flag_first_hits(side_a, took_a)
		_morale(side_a, took_a, na)
		_morale(side_b, took_b, nb)
		_after_morale(side_a, tick)
		_after_morale(side_b, tick)
		_decay(side_a)
		_decay(side_b)
		_mark_rout(side_a)
		_mark_rout(side_b)
		var decision = _decide(tick, side_a, side_b)
		if not decision.is_empty():
			winner = str(decision["winner"])
			reason = str(decision["reason"])
			_on_objective_events(decision, tick, side_a, side_b)
			_pursuit_if_rout(winner, side_a, side_b)
			_closing(winner, reason, tick, side_a, side_b)
			_lost_messengers(side_a, side_b)
			if log_on:
				ticks.append(_tick_record(tick, side_a, side_b))
			ended = true
			break
		_consider_send(side_a, side_b, tick)
		_consider_send(side_b, side_a, tick)
		if log_on:
			ticks.append(_tick_record(tick, side_a, side_b))
	if not ended:
		var score_a = _timeout_score(side_a)
		var score_b = _timeout_score(side_b)
		var gap = score_a - score_b
		if abs(gap) < _d.draw_margin:
			winner = "draw"
		elif gap > 0.0:
			winner = "A"
		else:
			winner = "B"
		reason = "timeout"
		emit_target = []
		_closing(winner, reason, last_tick, side_a, side_b)
		_lost_messengers(side_a, side_b)
		if log_on and ticks.size() > 0:
			var last: Dictionary = ticks[ticks.size() - 1]
			for ev in emit_target:
				last["events"].append(ev)
	var result = _result(winner, reason, last_tick, side_a, side_b)
	var log = {}
	if log_on:
		log = _log(army_a, army_b, side_a, side_b, ticks, result)
	return {"result": result, "log": log}


func preview_strike(army_a: Dictionary, army_b: Dictionary, terrain: String, distance: float, variance: float) -> Dictionary:
	_begin(terrain, 0, null, true)
	var side_a = _make_side(army_a, "A")
	var side_b = _make_side(army_b, "B")
	side_a.formation = int(_d.formation_index[str(army_a["formation"])])
	side_b.formation = int(_d.formation_index[str(army_b["formation"])])
	_finish_side(side_a)
	_finish_side(side_b)
	_build_packs(side_a, side_b)
	_build_packs(side_b, side_a)
	dist = distance
	emit_target = []
	var hit = _combat(side_a, side_b, variance)
	var raw = 0.0
	for v in hit["total"]:
		raw += float(v)
	var applied = raw * float(hit["taken_m"])
	var took = _apply_hits(side_b, side_a, hit)
	var before = side_b.morale
	_morale(side_b, took, 0.0)
	return {
		"raw_strength": raw,
		"applied_raw": applied,
		"casualties": took["by_type"],
		"strength_removed": float(took["strength"]),
		"morale_loss": before - side_b.morale,
	}


func _begin(terrain: String, seed: int, scenario_in, record_log: bool) -> void:
	log_on = record_log
	seed_value = seed
	scenario = scenario_in
	scenario_id = null
	terrain_id = terrain
	terr = _d.terrains[terrain]
	dist = _d.start_dist
	opening = []
	emit_target = opening
	reveals = []
	defender = null
	attacker = null
	loss_frac = 0.0
	hold_ticks = 0
	use_objective = scenario_in != null


func _draw_gumbels(rng: RandomNumberGenerator) -> PackedFloat64Array:
	var g = PackedFloat64Array()
	g.resize(_d.formation_ids.size())
	for i in _d.formation_ids.size():
		var u = rng.randf()
		if u < _d.tiny:
			u = _d.tiny
		if u > 1.0 - _d.tiny:
			u = 1.0 - _d.tiny
		g[i] = -log(-log(u))
	return g


func _make_side(army: Dictionary, id: String):
	var s = Side.new()
	s.id = id
	s.side_name = str(army.get("side_name", id))
	s.setup(_d.unit_ids.size(), _d.skill_ids.size(), _d.hidden_ids.size(), _d.formation_ids.size())
	s.ensure_attrs(_d.innate_ids.size())
	var officer: Dictionary = army.get("officer", {})
	var attrs: Dictionary = officer.get("attrs", officer.get("attributes", {}))
	var skills: Dictionary = officer.get("skills", {})
	var hidden: Dictionary = officer.get("hidden", {})
	for i in _d.innate_ids.size():
		s.attrs[i] = float(attrs.get(_d.innate_ids[i], _d.neutral))
	for i in _d.skill_ids.size():
		s.skills[i] = float(skills.get(_d.skill_ids[i], _d.neutral))
	for i in _d.hidden_ids.size():
		s.hidden_v[i] = float(hidden.get(_d.hidden_ids[i], _d.neutral))
	s.wisdom = float(officer.get("wisdom", _d.neutral))
	var rank_id = str(officer.get("rank_id", ""))
	var rank_nm = str(_d.rank_name.get(rank_id, rank_id))
	var person = str(officer.get("name", ""))
	if rank_nm != "" and person != "":
		s.officer_label = "%s %s" % [rank_nm, person]
	elif person != "":
		s.officer_label = person
	else:
		s.officer_label = rank_nm
	s.stance = int(_d.stance_index[str(army.get("stance", _d.stance_ids[0]))])
	var units = _counts(army.get("units", {}))
	var reserve = _counts(army.get("reserve", {}))
	s.s0 = 0.0
	for i in _d.unit_ids.size():
		var have = units[i]
		var hold = mini(reserve[i], have)
		s.front[i] = (have - hold) * int(_d.troops[i])
		s.reserve[i] = hold * int(_d.troops[i])
		s.s0 += float(have * int(_d.troops[i])) * _d.toughness[i]
		s.range_add[i] = float(terr["range_add"][i])
		s.reach_add[i] = float(terr["reach_add"][i])
	var forced = army.get("formation", null)
	s.forced = forced != null and str(forced) != ""
	if s.forced:
		s.formation = int(_d.formation_index[str(forced)])
	var traits: Dictionary = officer.get("traits", {})
	s.strength_id = _clean_id(traits.get("strength", ""))
	s.weakness_id = _clean_id(traits.get("weakness", ""))
	s.hidden_id = _clean_id(traits.get("hidden", ""))
	_apply_visible(s)
	_read_messenger(s, army.get("messenger", null))
	s.scen_fire = 1.0
	s.scen_taken = 1.0
	s.scen_morale = 1.0
	s.initial_front = s.front.duplicate()
	s.initial_reserve = s.reserve.duplicate()
	return s


func _clean_id(value) -> String:
	if value == null:
		return ""
	var text = str(value)
	if text == "none":
		return ""
	return text


func _counts(dict) -> PackedInt32Array:
	var c = PackedInt32Array()
	c.resize(_d.unit_ids.size())
	if dict == null:
		return c
	for i in _d.unit_ids.size():
		if dict.has(_d.unit_ids[i]):
			c[i] = int(dict[_d.unit_ids[i]])
	return c


func _apply_visible(s) -> void:
	s.trait_fire.resize(_d.unit_ids.size())
	s.trait_melee.resize(_d.unit_ids.size())
	for i in _d.unit_ids.size():
		s.trait_fire[i] = 1.0
		s.trait_melee[i] = 1.0
	s.trait_taken = 1.0
	s.trait_morale = 1.0
	s.cannon_loss_mult = 1.0
	s.pen_trait = 1.0
	s.bonus_scale = 1.0
	s.insight_add = 0.0
	s.start_add = 0.0
	s.rout_add = 0.0
	s.msg_delay = _d.msg_delay
	s.auto_tick = int(_d.stance_auto[s.stance])
	var override = false
	for tid in [s.strength_id, s.weakness_id]:
		var effect = _effect(tid)
		if effect.is_empty():
			continue
		if effect.has("morale_loss_mult"):
			s.trait_morale *= float(effect["morale_loss_mult"])
		if effect.has("damage_taken_mult"):
			s.trait_taken *= float(effect["damage_taken_mult"])
		if effect.has("morale_loss_from_cannon_mult"):
			s.cannon_loss_mult *= float(effect["morale_loss_from_cannon_mult"])
		if effect.has("ai_insight_bonus"):
			s.insight_add += float(effect["ai_insight_bonus"])
		if effect.has("start_morale_add"):
			s.start_add += float(effect["start_morale_add"])
		if effect.has("rout_threshold_add"):
			s.rout_add += float(effect["rout_threshold_add"])
		if effect.has("messenger_delay_add"):
			s.msg_delay += int(effect["messenger_delay_add"])
		if effect.has("auto_reserve_tick_override"):
			s.auto_tick = int(effect["auto_reserve_tick_override"])
			override = true
		if effect.has("auto_reserve_delay_add"):
			s.auto_tick += int(effect["auto_reserve_delay_add"])
		_mul_unit_map(s.trait_fire, effect.get("fire_mult", null))
		_mul_unit_map(s.trait_melee, effect.get("melee_mult", null))
		if effect.has("terrain_penalty_scale"):
			var pen: Dictionary = effect["terrain_penalty_scale"]
			if pen.has(terrain_id):
				s.pen_trait *= float(pen[terrain_id])
		if effect.has("terrain_bonus_mult"):
			var bon: Dictionary = effect["terrain_bonus_mult"]
			if bon.has(terrain_id):
				s.bonus_scale *= float(bon[terrain_id])
		if effect.has("ai_bias"):
			for fid in effect["ai_bias"].keys():
				if _d.formation_index.has(str(fid)):
					var fi = int(_d.formation_index[str(fid)])
					s.trait_bias[fi] = float(s.trait_bias[fi]) + float(effect["ai_bias"][fid])
	if not override:
		pass
	s.pen_scale = (1.0 + _d.ada_per * (s.attrs[_d.idx_ada] - _d.neutral)) * s.pen_trait


func _mul_unit_map(arr: PackedFloat64Array, mapping) -> void:
	if mapping == null or not (mapping is Dictionary):
		return
	for uid in mapping.keys():
		if _d.unit_index.has(str(uid)):
			var i = int(_d.unit_index[str(uid)])
			arr[i] = float(arr[i]) * float(mapping[uid])


func _effect(id: String) -> Dictionary:
	if id == "" or not _d.trait_by_id.has(id):
		return {}
	var row = _d.trait_by_id[id]
	if row.has("effect") and row["effect"] is Dictionary:
		return row["effect"]
	return {}


func _read_messenger(s, msg) -> void:
	s.has_standing = false
	s.live_tick = -1
	s.live_action = ""
	s.stand_action = ""
	s.stand_cond = ""
	s.stand_value = 0.0
	s.msg_used = false
	s.arrived = false
	s.send_tick = -1
	s.arrival = -1
	s.sent_action = ""
	if msg == null or not (msg is Dictionary):
		return
	var standing = msg.get("standing_order", null)
	if standing != null and standing is Dictionary:
		s.has_standing = true
		s.stand_action = str(standing.get("action", ""))
		s.stand_cond = str(standing.get("condition", ""))
		s.stand_value = float(standing.get("value", 0))
	var live = msg.get("live_send_tick", null)
	if live != null:
		s.live_tick = int(live)
		s.live_action = str(msg.get("live_action", ""))


func _bind_scenario(side_a, side_b) -> void:
	if scenario == null:
		return
	scenario_id = scenario.get("id", null)
	var def_key = str(scenario["defender"]["side"])
	defender = side_b if def_key == side_b.id else side_a
	attacker = side_a if defender == side_b else side_b
	var dblock: Dictionary = scenario["defender"]
	defender.holds = bool(dblock.get("holds_position", false))
	defender.scen_fire = float(dblock.get("fire_mult", 1.0))
	defender.scen_taken = float(dblock.get("damage_taken_mult", 1.0))
	defender.scen_morale = float(dblock.get("morale_loss_mult", 1.0))
	_add_bias(defender, dblock.get("ai_formation_bias", {}))
	_add_bias(attacker, scenario["attacker"].get("ai_formation_bias", {}))
	var obj: Dictionary = scenario.get("objective", {})
	loss_frac = float(obj.get("attacker_loss_fraction", 0.0))
	hold_ticks = int(obj.get("hold_ticks", _d.max_ticks))
	use_objective = true


func _add_bias(s, mapping) -> void:
	if mapping == null or not (mapping is Dictionary):
		return
	for fid in mapping.keys():
		if _d.formation_index.has(str(fid)):
			var fi = int(_d.formation_index[str(fid)])
			s.role_bias[fi] = float(s.role_bias[fi]) + float(mapping[fid])


func _choose_formation(s, enemy, gumbels: PackedFloat64Array) -> void:
	if s.forced:
		_note_formation_reveal(s)
		return
	var insight = _insight(s)
	var noise = _d.ai_noise_base + _d.ai_noise_insight * (1.0 - insight)
	noise += _d.temp_ai_per * max(0.0, _d.neutral - s.hidden_v[_d.idx_temp])
	var own = _comp_fit(s)
	var opp = _comp_fit(enemy)
	var tfit = _terrain_fit()
	var pred = _softmax(opp, tfit)
	var best_i = 0
	var best = -1.0
	var seen = false
	for fi in _d.formation_ids.size():
		var counter = 0.0
		for ej in _d.formation_ids.size():
			counter += pred[ej] * (float(_d.matchup[fi][ej]) - 1.0)
		var aggr = s.hidden_v[_d.idx_agg] - _d.neutral
		var score = own[fi] + tfit[fi] + float(_d.stance_bias[s.stance][fi])
		score += float(_d.agg_bias[fi]) * aggr + float(s.trait_bias[fi]) + float(s.role_bias[fi])
		score += _d.ai_counter_w * insight * counter + noise * gumbels[fi]
		if not seen or score > best:
			seen = true
			best = score
			best_i = fi
	s.formation = best_i
	_note_formation_reveal(s)


func _insight(s) -> float:
	var raw = _d.bt_insight * s.skills[_d.idx_bt]
	raw += _d.wis_insight * s.wisdom
	raw += _d.int_insight * s.attrs[_d.idx_int]
	raw = raw / _d.stat_scale + s.insight_add
	return _clamp(raw, 0.0, 1.0)


func _point_shares(s) -> PackedFloat64Array:
	var pts = PackedFloat64Array()
	pts.resize(_d.unit_ids.size())
	var tot = 0.0
	for i in _d.unit_ids.size():
		var men = s.front[i] + s.reserve[i]
		var companies = 0.0
		if int(_d.troops[i]) != 0:
			companies = float(men) / float(_d.troops[i])
		var p = companies * float(_d.cost[i])
		pts[i] = p
		tot += p
	if tot <= 0.0:
		tot = 1.0
	for i in pts.size():
		pts[i] = pts[i] / tot
	return pts


func _comp_fit(s) -> PackedFloat64Array:
	var sh = _point_shares(s)
	var out = PackedFloat64Array()
	out.resize(_d.formation_ids.size())
	for fi in _d.formation_ids.size():
		var acc = 0.0
		for ui in _d.unit_ids.size():
			acc += float(_d.comp_fit[fi][ui]) * sh[ui]
		out[fi] = acc
	return out


func _terrain_fit() -> PackedFloat64Array:
	var out = PackedFloat64Array()
	out.resize(_d.formation_ids.size())
	var fmult: PackedFloat64Array = terr["formation"]
	for fi in _d.formation_ids.size():
		out[fi] = (float(fmult[fi]) - 1.0) * _d.ai_terrain_w
	return out


func _softmax(comp: PackedFloat64Array, tfit: PackedFloat64Array) -> PackedFloat64Array:
	var n = comp.size()
	var mx = comp[0] + tfit[0]
	for i in range(1, n):
		var v = comp[i] + tfit[i]
		if v > mx:
			mx = v
	var ex = PackedFloat64Array()
	ex.resize(n)
	var z = 0.0
	for i in n:
		var e = exp((comp[i] + tfit[i] - mx) / _d.ai_temperature)
		ex[i] = e
		z += e
	if z <= 0.0:
		for i in n:
			ex[i] = 1.0 / float(n)
		return ex
	for i in n:
		ex[i] = ex[i] / z
	return ex


func _note_formation_reveal(s) -> void:
	var fid = _d.formation_ids[s.formation]
	if _d.trig_agg.contains("wedge") and fid.contains("wedge"):
		_reveal_attr(s, "aggression")
	if _d.trig_agg.contains("pincer") and fid.contains("pincer"):
		_reveal_attr(s, "aggression")


func _finish_side(s) -> void:
	var eb = _d.eb_w_brv * s.attrs[_d.idx_brv] + _d.eb_w_hid * s.hidden_v[_d.idx_hbrv]
	s.eb = eb
	var weighted = 0.0
	for i in _d.unit_ids.size():
		var block = float(s.front[i] + s.reserve[i]) * _d.toughness[i]
		weighted += block * _d.unit_morale[i]
	var base = 0.0
	if s.s0 > 0.0:
		base = weighted / s.s0
	base += _d.lead_morale_per * (s.skills[_d.idx_lead] - _d.neutral)
	base += float(_d.form_morale[s.formation]) + s.start_add
	s.morale = _clamp(base, _d.morale_min, _d.morale_cap)
	s.m0 = s.morale
	s.rout_thr = _d.rout_base + float(_d.stance_rout[s.stance])
	s.rout_thr += _d.eb_rout_per * (eb - _d.neutral) + s.rout_add
	s.loss_mult = 1.0 + _d.eb_loss_per * (eb - _d.neutral)
	s.loss_mult *= 1.0 + _d.lead_loss_per * (s.skills[_d.idx_lead] - _d.neutral)
	s.loss_mult *= s.trait_morale * s.scen_morale
	s.dmg_taken = float(_d.form_taken[s.formation]) * float(_d.stance_taken[s.stance])
	s.dmg_taken *= 1.0 + _d.agg_taken_per * (s.hidden_v[_d.idx_agg] - _d.neutral)
	s.dmg_taken *= s.trait_taken * s.scen_taken
	s.rash_taken_mult = 1.0
	s.rash_advance = 0.0
	s.lucky_mult = 1.0


func _build_packs(s, enemy) -> void:
	var fscale = _scale(float(terr["formation"][s.formation]), s.bonus_scale, s.pen_scale)
	var match = float(_d.matchup[s.formation][enemy.formation])
	var wis = 1.0 + _d.wis_dmg_per * (s.wisdom - _d.neutral)
	var ath = 1.0 + _d.ath_per * (s.attrs[_d.idx_ath] - _d.neutral)
	var agg = 1.0 + _d.agg_melee_per * (s.hidden_v[_d.idx_agg] - _d.neutral)
	for ui in _d.unit_ids.size():
		var tf = _scale(float(terr["fire"][ui]), s.bonus_scale, s.pen_scale)
		var tm = _scale(float(terr["melee"][ui]), s.bonus_scale, s.pen_scale)
		var fs = _skill_mult(s, _d.fire_skill[ui])
		var ms = _skill_mult(s, _d.melee_skill[ui])
		s.fire_pack[ui] = _d.firepower[ui] * float(_d.form_fire[s.formation]) * float(_d.stance_fire[s.stance])
		s.fire_pack[ui] *= fs * float(s.trait_fire[ui]) * wis * s.scen_fire * tf * fscale * match
		s.melee_pack[ui] = _d.melee_stat[ui] * float(_d.form_melee[s.formation]) * float(_d.unit_melee_mult[s.formation][ui])
		s.melee_pack[ui] *= float(_d.stance_melee[s.stance]) * ms * ath * agg * float(s.trait_melee[ui]) * wis * tm * fscale * match


func _scale(raw: float, bonus: float, pen: float) -> float:
	if raw > 1.0:
		return 1.0 + (raw - 1.0) * bonus
	if raw < 1.0:
		return 1.0 - (1.0 - raw) * pen
	return raw


func _skill_mult(s, skill_name: String) -> float:
	var idx = int(_d.skill_index[skill_name])
	return 1.0 + _d.skill_per * (s.skills[idx] - _d.neutral)


func _trigger_rash(s) -> void:
	if s.hidden_id == "" or s.hidden_on:
		return
	var row = _d.trait_by_id.get(s.hidden_id, null)
	if row == null or not row.has("trigger"):
		return
	if str(row["trigger"].get("type", "")) != "distance_below":
		return
	if dist < float(row["trigger"]["value"]):
		s.hidden_on = true
		var effect: Dictionary = row["effect"]
		s.rash_left = int(effect.get("duration_ticks", 0))
		s.rash_advance = float(effect.get("advance_add", 0.0))
		s.rash_taken_mult = float(effect.get("damage_taken_mult", 1.0))
		_reveal_trait(s, s.hidden_id)


func _arrive(s, tick: int) -> void:
	if not s.msg_used or s.arrived:
		return
	if tick != s.arrival:
		return
	s.arrived = true
	if s.sent_action == "rally":
		var gain = _d.rally_frac * max(0.0, s.m0 - s.morale)
		gain *= _d.insp_rally_base + _d.insp_rally_per * s.hidden_v[_d.idx_insp]
		var before = s.morale
		s.morale = _clamp(s.morale + gain, _d.morale_min, _d.morale_cap)
		s.rally_left = _d.rally_dur
		_emit_simple("rally", s, {
			"officer": s.officer_label,
			"side_name": s.side_name,
			"morale_gain": _fmt(s.morale - before),
			"morale": _fmt(s.morale),
		})
		if _d.trig_insp.contains("rally"):
			_reveal_attr(s, "inspiration")
	elif s.sent_action == "commit_reserves":
		if _reserve_men(s) <= 0:
			_emit_simple("messenger_wasted", s, {})
		else:
			var fresh = _commit(s, true)
			_emit_simple("reserves_committed", s, {
				"side_name": s.side_name,
				"officer": s.officer_label,
				"reserve_troops": str(fresh),
			})


func _auto_reserve(s, tick: int) -> void:
	if _reserve_men(s) <= 0:
		return
	if tick >= s.auto_tick or s.morale < _d.auto_morale:
		_commit(s, false)
		_emit_simple("auto_reserves", s, {"officer": s.officer_label})


func _commit(s, bonus: bool) -> int:
	var fresh = 0
	for i in _d.unit_ids.size():
		fresh += int(s.reserve[i])
		s.front[i] = int(s.front[i]) + int(s.reserve[i])
		s.reserve[i] = 0
	if bonus:
		s.res_left = _d.res_dur
	return fresh


func _reserve_men(s) -> int:
	var m = 0
	for i in _d.unit_ids.size():
		m += int(s.reserve[i])
	return m


func _move(side_a, side_b) -> void:
	var adv_a = _one_advance(side_a)
	var adv_b = _one_advance(side_b)
	dist = max(0.0, dist - adv_a["adv"] - adv_b["adv"])
	_log_move(side_a, adv_a)
	_log_move(side_b, adv_b)


func _one_advance(s) -> Dictionary:
	var adv = float(_d.stance_advance[s.stance]) + float(_d.form_advance[s.formation]) + float(terr["advance"])
	var holding = false
	var hold = float(_d.stance_hold[s.stance])
	if hold >= 0.0 and dist <= hold:
		adv = 0.0
		holding = true
	if s.holds:
		adv = 0.0
		holding = true
	if s.rash_left > 0 and not s.holds:
		adv += s.rash_advance
	if s.holds:
		adv = 0.0
	if adv < 0.0:
		adv = 0.0
	return {"adv": adv, "holding": holding}


func _log_move(s, info: Dictionary) -> void:
	if not log_on:
		return
	if float(info["adv"]) > 0.0:
		_emit_simple("advance", s, {"side_name": s.side_name, "distance": _fmt(dist)})
	elif bool(info["holding"]):
		_emit_simple("hold", s, {"side_name": s.side_name, "officer": s.officer_label})


func _noise_amp(s) -> float:
	var span = _d.hidden_max
	var t = s.hidden_v[_d.idx_temp]
	if span <= 0.0:
		return _d.temp_noise_0
	var u = t / span
	return _d.temp_noise_0 * (1.0 - u) + _d.temp_noise_99 * u


func _combat(att, defn, variance: float) -> Dictionary:
	var n = _d.unit_ids.size()
	var events: Array = []
	var total = PackedFloat64Array()
	var melee = PackedFloat64Array()
	var cannon = PackedFloat64Array()
	var cannon_melee = PackedFloat64Array()
	total.resize(n)
	melee.resize(n)
	cannon.resize(n)
	cannon_melee.resize(n)
	var res_m = 1.0
	if att.res_left > 0:
		res_m = _d.res_mult
	var taken_m = defn.dmg_taken
	if defn.rash_left > 0:
		taken_m *= defn.rash_taken_mult
	for ui in n:
		var comp = 0.0
		if int(_d.troops[ui]) != 0:
			comp = float(att.front[ui]) / float(_d.troops[ui])
		if comp <= 0.0:
			continue
		var reach = _d.unit_reach[ui] + att.reach_add[ui]
		var rang = _d.unit_range[ui] + att.range_add[ui]
		var mode = ""
		var pack = 0.0
		var canister = false
		if dist <= reach:
			mode = "melee"
			pack = float(att.melee_pack[ui])
		elif dist <= rang and _d.firepower[ui] > 0.0:
			mode = "fire"
			pack = float(att.fire_pack[ui])
			if ui == _d.cannon_i and dist <= _d.canister_dist:
				pack *= _d.canister_mult
				canister = true
		else:
			continue
		var dmg = comp * pack * variance * res_m
		var prefs: PackedFloat64Array = _d.target_melee[ui] if mode == "melee" else _d.target_fire[ui]
		var wz = 0.0
		var weights = PackedFloat64Array()
		weights.resize(n)
		for ti in n:
			var w = float(defn.front[ti]) * _d.exposure[ti] * float(prefs[ti])
			weights[ti] = w
			wz += w
		if wz <= 0.0:
			continue
		var raw = PackedFloat64Array()
		raw.resize(n)
		for ti in n:
			var share = dmg * weights[ti] / wz
			raw[ti] = share
			total[ti] = float(total[ti]) + share
			if mode == "melee":
				melee[ti] = float(melee[ti]) + share
			if ui == _d.cannon_i:
				cannon[ti] = float(cannon[ti]) + share
				if mode == "melee":
					cannon_melee[ti] = float(cannon_melee[ti]) + share
		events.append({"ui": ui, "mode": mode, "canister": canister, "raw": raw})
		if mode == "melee":
			att.saw_melee = true
	return {
		"events": events,
		"total": total,
		"melee": melee,
		"cannon": cannon,
		"cannon_melee": cannon_melee,
		"taken_m": taken_m,
	}


func _maybe_lucky(defn, hit: Dictionary) -> void:
	var sum = 0.0
	for v in hit["total"]:
		sum += float(v)
	if sum <= 0.0:
		return
	var mult = 1.0
	if defn.lucky_left > 0:
		mult = defn.lucky_mult
	elif defn.hidden_id == "lucky" and not defn.hidden_on:
		defn.hidden_on = true
		var effect = _effect("lucky")
		defn.lucky_mult = float(effect.get("casualties_taken_mult", 1.0))
		defn.lucky_left = int(effect.get("duration_ticks", 0))
		mult = defn.lucky_mult
		_reveal_trait(defn, "lucky")
	if mult == 1.0:
		return
	_scale_hit(hit, mult)


func _scale_hit(hit: Dictionary, mult: float) -> void:
	for i in hit["total"].size():
		hit["total"][i] = float(hit["total"][i]) * mult
		hit["melee"][i] = float(hit["melee"][i]) * mult
		hit["cannon"][i] = float(hit["cannon"][i]) * mult
		hit["cannon_melee"][i] = float(hit["cannon_melee"][i]) * mult
	for ev in hit["events"]:
		for i in ev["raw"].size():
			ev["raw"][i] = float(ev["raw"][i]) * mult


func _apply_hits(defn, att, hit: Dictionary) -> Dictionary:
	var n = _d.unit_ids.size()
	var taken_m = float(hit["taken_m"])
	var lost = PackedInt32Array()
	lost.resize(n)
	var strength = 0.0
	var melee_s = 0.0
	var cannon_s = 0.0
	var cannon_melee_s = 0.0
	for i in n:
		var scaled = float(hit["total"][i]) * taken_m
		if scaled <= 0.0:
			continue
		var troops = mini(int(defn.front[i]), round_half(scaled / _d.toughness[i]))
		if troops < 0:
			troops = 0
		lost[i] = troops
		defn.front[i] = int(defn.front[i]) - troops
		var actual = float(troops) * _d.toughness[i]
		strength += actual
		var raw = float(hit["total"][i])
		if raw > 0.0:
			melee_s += actual * float(hit["melee"][i]) / raw
			cannon_s += actual * float(hit["cannon"][i]) / raw
			cannon_melee_s += actual * float(hit["cannon_melee"][i]) / raw
	defn.lost_strength += strength
	var by_type = {}
	for i in n:
		by_type[_d.unit_ids[i]] = int(lost[i])
	return {
		"strength": strength,
		"melee": melee_s,
		"cannon": cannon_s,
		"cannon_melee": cannon_melee_s,
		"lost": lost,
		"by_type": by_type,
	}


func _lost_head(took: Dictionary) -> int:
	var head = 0
	var lost: PackedInt32Array = took["lost"]
	for i in lost.size():
		head += int(lost[i])
	return head


func _emit_strikes(att, defn, hit: Dictionary, lost: PackedInt32Array, actor_lost: int) -> void:
	var events: Array = hit["events"]
	if events.is_empty():
		return
	var n = _d.unit_ids.size()
	var buckets: Array = []
	for _ei in events.size():
		var row = PackedInt32Array()
		row.resize(n)
		buckets.append(row)
	for ti in n:
		if int(lost[ti]) <= 0:
			continue
		var weights = PackedFloat64Array()
		weights.resize(events.size())
		for ei in events.size():
			weights[ei] = float(events[ei]["raw"][ti])
		var parts = _split_ints(int(lost[ti]), weights)
		for ei in parts.size():
			buckets[ei][ti] = int(parts[ei])
	for ei in events.size():
		var ev: Dictionary = events[ei]
		var cas = {}
		var head = 0
		for ti in n:
			cas[_d.unit_ids[ti]] = int(buckets[ei][ti])
			head += int(buckets[ei][ti])
		if head <= 0:
			continue
		var kind = _strike_kind(int(ev["ui"]), str(ev["mode"]), bool(ev["canister"]))
		var uid = _d.unit_ids[int(ev["ui"])]
		var fill = {
			"side_name": att.side_name,
			"officer": att.officer_label,
			"unit_name": str(_d.unit_narration[uid]),
			"unit_plural": str(_d.unit_plural[uid]),
			"casualties": str(head),
			"casualties_taken": str(actor_lost),
		}
		_emit({
			"type": kind,
			"side": att.id,
			"target": defn.id,
			"unit": uid,
			"casualties": cas,
			"fill": fill,
		})


func _strike_kind(ui: int, mode: String, canister: bool) -> String:
	if mode == "melee":
		if ui == _d.cavalry_i:
			return "charge"
		return "melee"
	if ui == _d.cannon_i:
		if canister:
			return "canister"
		return "cannon"
	return "volley"


func _split_ints(total: int, weights: PackedFloat64Array) -> PackedInt32Array:
	var n = weights.size()
	var out = PackedInt32Array()
	out.resize(n)
	var sumw = 0.0
	for w in weights:
		sumw += float(w)
	if total <= 0 or sumw <= 0.0:
		return out
	var frac = PackedFloat64Array()
	frac.resize(n)
	var given = 0
	for i in n:
		var exact = float(total) * float(weights[i]) / sumw
		var base = int(floor(exact))
		out[i] = base
		frac[i] = exact - float(base)
		given += base
	var left = total - given
	while left > 0:
		var best = 0
		for i in range(1, n):
			if float(frac[i]) > float(frac[best]):
				best = i
		out[best] = int(out[best]) + 1
		frac[best] = -1.0
		left -= 1
	return out


func _flag_first_hits(s, took: Dictionary) -> void:
	if float(took["strength"]) <= 0.0:
		return
	if s.hidden_id == "cool_under_fire" and not s.hidden_on:
		s.hidden_on = true
		s.cool_left = int(_effect("cool_under_fire").get("no_morale_loss_ticks", 0))
		_reveal_trait(s, "cool_under_fire")
	if s.hidden_id == "shaken_by_guns" and not s.hidden_on and float(took["cannon"]) > 0.0:
		s.hidden_on = true
		s.cannon_loss_mult *= float(_effect("shaken_by_guns").get("morale_loss_from_cannon_mult", 1.0))
		_reveal_trait(s, "shaken_by_guns")
	if _d.trig_agg.contains("melee") and s.saw_melee:
		_reveal_attr(s, "aggression")
	if float(s.lost_strength) >= _d.temp_loss_frac * s.s0:
		_reveal_attr(s, "temperament")


func _morale(s, took: Dictionary, noise: float) -> void:
	var strength = float(took["strength"])
	if strength <= 0.0:
		var regen = _d.regen_base + _d.insp_regen_per * (s.hidden_v[_d.idx_insp] - _d.neutral)
		s.morale = _clamp(s.morale + regen, _d.morale_min, _d.morale_cap)
		if _d.trig_insp.contains("recovery"):
			_reveal_attr(s, "inspiration")
	else:
		var loss = 0.0
		if s.cool_left <= 0 and s.s0 > 0.0:
			var part_c = (float(took["cannon"]) + _d.melee_extra * float(took["cannon_melee"])) / s.s0
			var other_s = strength - float(took["cannon"])
			var other_m = float(took["melee"]) - float(took["cannon_melee"])
			var part_o = (other_s + _d.melee_extra * other_m) / s.s0
			loss = (part_o + part_c * s.cannon_loss_mult) * _d.loss_k * _d.stat_scale
			loss *= s.loss_mult
			if s.rally_left > 0:
				loss *= _d.rally_loss_mult
			loss *= 1.0 + noise
		s.morale = _clamp(s.morale - loss, _d.morale_min, _d.morale_cap)
	if not s.shook_high and s.morale < _d.shaken_high:
		s.shook_high = true
		_emit_simple("morale_shaken", s, {"side_name": s.side_name, "morale": _fmt(s.morale)})
	if not s.shook_low and s.morale < _d.shaken_low:
		s.shook_low = true
		_emit_simple("morale_shaken", s, {"side_name": s.side_name, "morale": _fmt(s.morale)})
	if s.morale < _d.hb_below:
		_reveal_attr(s, "hidden_bravery")


func _after_morale(s, tick: int) -> void:
	if s.hidden_id == "" or s.hidden_on:
		_lion_panic_wind(s, tick)
		return
	var row = _d.trait_by_id.get(s.hidden_id, null)
	if row != null and row.has("trigger"):
		var kind = str(row["trigger"].get("type", ""))
		if kind == "morale_below" and s.morale < float(row["trigger"]["value"]):
			_fire_hidden_morale(s)
		elif kind == "tick_reached" and tick >= int(row["trigger"]["value"]):
			_fire_second_wind(s)
	_lion_panic_wind(s, tick)


func _fire_hidden_morale(s) -> void:
	s.hidden_on = true
	var effect = _effect(s.hidden_id)
	if effect.has("once_morale_add"):
		s.morale = _clamp(s.morale + float(effect["once_morale_add"]), _d.morale_min, _d.morale_cap)
	if effect.has("rout_threshold_add"):
		s.rout_thr += float(effect["rout_threshold_add"])
	_reveal_trait(s, s.hidden_id)


func _fire_second_wind(s) -> void:
	s.hidden_on = true
	var frac = float(_effect(s.hidden_id).get("restore_lost_morale_frac", 0.0))
	var lost = max(0.0, s.m0 - s.morale)
	s.morale = _clamp(s.morale + frac * lost, _d.morale_min, _d.morale_cap)
	_reveal_trait(s, s.hidden_id)


func _lion_panic_wind(s, _tick: int) -> void:
	# Morale-threshold hidden traits are applied in _fire_hidden_morale.
	# This hook stays so a later trait can stack after the reveal without a new draw.
	pass


func _decay(s) -> void:
	if s.rally_left > 0:
		s.rally_left -= 1
	if s.res_left > 0:
		s.res_left -= 1
	if s.rash_left > 0:
		s.rash_left -= 1
	if s.lucky_left > 0:
		s.lucky_left -= 1
	if s.cool_left > 0:
		s.cool_left -= 1


func _mark_rout(s) -> void:
	s.eliminated = _alive(s) < _d.elim_frac * s.s0
	s.routed = s.morale < s.rout_thr or s.eliminated


func _decide(tick: int, side_a, side_b) -> Dictionary:
	if use_objective and defender != null:
		if defender.routed:
			return {"winner": attacker.id, "reason": "eliminated" if defender.eliminated else "rout"}
		if attacker.routed:
			return {"winner": defender.id, "reason": "eliminated" if attacker.eliminated else "rout"}
		var loss_hit = _alive(attacker) < (1.0 - loss_frac) * attacker.s0
		var held = tick >= hold_ticks
		if loss_hit or held:
			return {"winner": defender.id, "reason": "objective", "loss": loss_hit, "held": held}
		return {}
	if side_a.routed or side_b.routed:
		if side_a.routed and side_b.routed:
			var ma = side_a.morale - side_a.rout_thr
			var mb = side_b.morale - side_b.rout_thr
			if ma == mb:
				return {"winner": "draw", "reason": "double_rout"}
			if ma > mb:
				return {"winner": "A", "reason": "double_rout"}
			return {"winner": "B", "reason": "double_rout"}
		if side_a.routed:
			return {"winner": "B", "reason": "eliminated" if side_a.eliminated else "rout"}
		return {"winner": "A", "reason": "eliminated" if side_b.eliminated else "rout"}
	return {}


func _on_objective_events(decision: Dictionary, tick: int, side_a, side_b) -> void:
	if str(decision.get("reason", "")) != "objective":
		return
	var win_s = side_a if str(decision["winner"]) == side_a.id else side_b
	var lose_s = side_b if win_s == side_a else side_a
	if bool(decision.get("loss", false)):
		var pct = 0.0
		if lose_s.s0 > 0.0:
			pct = _d.stat_scale * (1.0 - _alive(lose_s) / lose_s.s0)
		_emit_simple("scenario_losses_reached", lose_s, {
			"loser_name": lose_s.side_name,
			"loss_pct": str(round_half(pct)),
			"ticks": str(tick),
			"winner_name": win_s.side_name,
		})
	if bool(decision.get("held", false)):
		_emit_simple("scenario_held", win_s, {
			"ticks": str(tick),
			"winner_name": win_s.side_name,
		})


func _pursuit_if_rout(winner: String, side_a, side_b) -> void:
	if winner != "A" and winner != "B":
		return
	var win_s = side_a if winner == side_a.id else side_b
	var lose_s = side_b if win_s == side_a else side_a
	if not lose_s.routed:
		return
	if int(win_s.front[_d.cavalry_i]) <= 0:
		return
	var comp = float(win_s.front[_d.cavalry_i]) / float(_d.troops[_d.cavalry_i])
	var dmg = comp * float(win_s.melee_pack[_d.cavalry_i]) * _d.pursuit_mult
	var taken_m = lose_s.dmg_taken
	if lose_s.rash_left > 0:
		taken_m *= lose_s.rash_taken_mult
	var prefs: PackedFloat64Array = _d.target_melee[_d.cavalry_i]
	var n = _d.unit_ids.size()
	var wz = 0.0
	var weights = PackedFloat64Array()
	weights.resize(n)
	for ti in n:
		var w = float(lose_s.front[ti]) * _d.exposure[ti] * float(prefs[ti])
		weights[ti] = w
		wz += w
	if wz <= 0.0 or dmg <= 0.0:
		return
	var lost = PackedInt32Array()
	lost.resize(n)
	for ti in n:
		var share = dmg * taken_m * weights[ti] / wz
		var troops = mini(int(lose_s.front[ti]), round_half(share / _d.toughness[ti]))
		if troops < 0:
			troops = 0
		lost[ti] = troops
		lose_s.front[ti] = int(lose_s.front[ti]) - troops
	var cas = {}
	var head = 0
	for ti in n:
		cas[_d.unit_ids[ti]] = int(lost[ti])
		head += int(lost[ti])
	if head <= 0:
		return
	_emit({
		"type": "pursuit",
		"side": win_s.id,
		"target": lose_s.id,
		"unit": _d.unit_ids[_d.cavalry_i],
		"casualties": cas,
		"fill": {"side_name": win_s.side_name, "casualties": str(head)},
	})


func _closing(winner: String, reason: String, tick: int, side_a, side_b) -> void:
	if winner == "draw":
		_emit_simple("battle_end_draw", side_a, {})
		return
	var win_s = side_a if winner == side_a.id else side_b
	var lose_s = side_b if win_s == side_a else side_a
	if lose_s.routed:
		_emit_simple("rout", lose_s, {"side_name": lose_s.side_name})
	_emit_simple("battle_end_win", win_s, {
		"winner_name": win_s.side_name,
		"ticks": str(tick),
		"winner_troops": str(_men(win_s)),
		"loser_troops": str(_men(lose_s)),
	})


func _lost_messengers(side_a, side_b) -> void:
	for s in [side_a, side_b]:
		if s.msg_used and not s.arrived:
			_emit_simple("messenger_lost", s, {"officer": s.officer_label})


func _consider_send(s, enemy, tick: int) -> void:
	if s.msg_used or s.routed or enemy.routed:
		return
	var live_now = s.live_tick == tick
	var stand_now = _standing_now(s, enemy, tick)
	if live_now:
		_send(s, s.live_action, "live_click", tick)
		if s.has_standing:
			_emit_simple("standing_order_cancelled", s, {})
	elif stand_now:
		_send(s, s.stand_action, "standing_order", tick)
		if s.live_tick >= 0:
			_emit_simple("live_click_ignored", s, {})


func _standing_now(s, enemy, tick: int) -> bool:
	if not s.has_standing:
		return false
	if s.stand_cond == "morale_below":
		return s.morale < s.stand_value
	if s.stand_cond == "strength_below_pct":
		return _alive(s) < (s.stand_value / _d.stat_scale) * s.s0
	if s.stand_cond == "enemy_morale_below":
		return enemy.morale < s.stand_value
	if s.stand_cond == "tick_reached":
		return float(tick) >= s.stand_value
	return false


func _send(s, action: String, source: String, tick: int) -> void:
	s.msg_used = true
	s.sent_action = action
	s.send_tick = tick
	s.arrival = tick + s.msg_delay
	_emit({
		"type": "messenger_sent",
		"side": s.id,
		"source": source,
		"action": action,
		"fill": {"officer": s.officer_label, "side_name": s.side_name},
	})


func _reveal_trait(s, id: String) -> void:
	var row = _d.trait_by_id.get(id, {})
	reveals.append({"kind": "trait", "id": id, "side": s.id})
	_emit_simple("trait_revealed", s, {
		"officer": s.officer_label,
		"trait_name": str(row.get("name", id)),
	})


func _reveal_attr(s, attr_id: String) -> void:
	if s.revealed.has(attr_id):
		return
	if not _d.hidden_index.has(attr_id):
		return
	s.revealed[attr_id] = true
	var value = float(s.hidden_v[int(_d.hidden_index[attr_id])])
	var band = _band(value)
	reveals.append({"kind": "hidden_attribute", "id": attr_id, "side": s.id, "band": band})
	_emit_simple("hidden_attribute_revealed", s, {
		"officer": s.officer_label,
		"attribute_name": attr_id,
		"band": band,
	})


func _band(value: float) -> String:
	var label = ""
	for b in _d.bands:
		label = str(b["label"])
		if value <= float(b["max"]):
			return label
	return label


func _alive(s) -> float:
	var total = 0.0
	for i in _d.unit_ids.size():
		total += float(s.front[i] + s.reserve[i]) * _d.toughness[i]
	return total


func _men(s) -> int:
	var m = 0
	for i in _d.unit_ids.size():
		m += int(s.front[i]) + int(s.reserve[i])
	return m


func _timeout_score(s) -> float:
	var strength_part = 0.0
	if s.s0 > 0.0:
		strength_part = _alive(s) / s.s0
	var morale_part = 0.0
	if _d.timeout_mor_div != 0.0:
		morale_part = s.morale / _d.timeout_mor_div
	return _d.timeout_w_str * strength_part + _d.timeout_w_mor * morale_part


func _clamp(x: float, lo: float, hi: float) -> float:
	return min(hi, max(lo, x))


func _fmt(x: float) -> String:
	return Narration.fmt_number(x, "xx".length(), _d.half)


func _emit(ev: Dictionary) -> void:
	if log_on:
		emit_target.append(ev)


func _emit_simple(kind: String, s, fill: Dictionary) -> void:
	_emit({"type": kind, "side": s.id, "fill": fill})


func _opening(side_a, side_b) -> void:
	emit_target = opening
	_emit({
		"type": "battle_start",
		"fill": {
			"terrain_name": str(terr["name"]),
			"a_officer": side_a.officer_label,
			"b_officer": side_b.officer_label,
			"a_troops": str(_men(side_a)),
			"b_troops": str(_men(side_b)),
		},
	})
	_emit({
		"type": "formation_chosen",
		"side": side_a.id,
		"formation": _d.formation_ids[side_a.formation],
		"fill": {
			"officer": side_a.officer_label,
			"formation_name": str(_d.formation_name[_d.formation_ids[side_a.formation]]),
		},
	})
	_emit({
		"type": "formation_chosen",
		"side": side_b.id,
		"formation": _d.formation_ids[side_b.formation],
		"fill": {
			"officer": side_b.officer_label,
			"formation_name": str(_d.formation_name[_d.formation_ids[side_b.formation]]),
		},
	})


func _tick_record(tick: int, side_a, side_b) -> Dictionary:
	return {
		"t": tick,
		"distance": dist,
		"state": {"A": _state(side_a), "B": _state(side_b)},
		"events": emit_target.duplicate(true),
	}


func _state(s) -> Dictionary:
	return {
		"troops": _troop_map(s.front),
		"reserve": _troop_map(s.reserve),
		"morale": s.morale,
		"strength": _alive(s),
	}


func _troop_map(arr: PackedInt32Array) -> Dictionary:
	var out = {}
	for i in _d.unit_ids.size():
		out[_d.unit_ids[i]] = int(arr[i])
	return out


func _result(winner: String, reason: String, ticks: int, side_a, side_b) -> Dictionary:
	return {
		"winner": winner,
		"reason": reason,
		"scenario_id": scenario_id,
		"ticks": ticks,
		"formations": {
			"A": _d.formation_ids[side_a.formation],
			"B": _d.formation_ids[side_b.formation],
		},
		"final": {"A": _final(side_a), "B": _final(side_b)},
		"reveals": reveals.duplicate(true),
		"growth_inputs": {
			"units_fielded": {"A": _fielded(side_a), "B": _fielded(side_b)},
			"outcome": {
				"A": _outcome("A", winner),
				"B": _outcome("B", winner),
			},
		},
	}


func _final(s) -> Dictionary:
	var block = _state(s)
	block["routed"] = s.routed
	return block


func _fielded(s) -> Array:
	var ids: Array = []
	for i in _d.unit_ids.size():
		if int(s.front[i]) + int(s.reserve[i]) > 0:
			ids.append(_d.unit_ids[i])
	return ids


func _outcome(id: String, winner: String) -> String:
	if winner == "draw":
		return "draw"
	if winner == id:
		return "win"
	return "loss"


func _log(army_a: Dictionary, army_b: Dictionary, side_a, side_b, ticks: Array, result: Dictionary) -> Dictionary:
	var inputs = {
		"terrain": terrain_id,
		"seed": seed_value,
		"scenario": scenario_id,
		"A": _canon_army(army_a),
		"B": _canon_army(army_b),
	}
	return {
		"v": Records.battle_log_version(),
		"seed": seed_value,
		"terrain": terrain_id,
		"inputs_hash": HashUtil.sha1_text(JSON.stringify(inputs)),
		"scenario_id": scenario_id,
		"setup": {"A": _setup(side_a), "B": _setup(side_b)},
		"opening": opening.duplicate(true),
		"ticks": ticks,
		"result": {"winner": result["winner"], "reason": result["reason"], "ticks": result["ticks"]},
	}


func _setup(s) -> Dictionary:
	return {
		"formation": _d.formation_ids[s.formation],
		"stance": _d.stance_ids[s.stance],
		"start_morale": s.m0,
		"rout_threshold": s.rout_thr,
		"troops": _troop_map(s.initial_front),
		"reserve": _troop_map(s.initial_reserve),
	}


func _canon_army(army: Dictionary) -> Dictionary:
	var officer: Dictionary = army.get("officer", {})
	return {
		"v": Records.battle_log_version(),
		"stance": str(army.get("stance", "")),
		"formation": army.get("formation", null),
		"side_name": str(army.get("side_name", "")),
		"units": army.get("units", {}),
		"reserve": army.get("reserve", {}),
		"messenger": army.get("messenger", null),
		"officer": {
			"v": Records.battle_log_version(),
			"rank_id": str(officer.get("rank_id", "")),
			"name": str(officer.get("name", "")),
			"wisdom": float(officer.get("wisdom", 0.0)),
			"attrs": officer.get("attrs", officer.get("attributes", {})),
			"skills": officer.get("skills", {}),
			"hidden": officer.get("hidden", {}),
			"traits": officer.get("traits", {}),
		},
	}


class Side:
	extends RefCounted
	var id = ""
	var side_name = ""
	var officer_label = ""
	var stance = 0
	var formation = 0
	var forced = false
	var front: PackedInt32Array = PackedInt32Array()
	var reserve: PackedInt32Array = PackedInt32Array()
	var attrs: PackedFloat64Array = PackedFloat64Array()
	var skills: PackedFloat64Array = PackedFloat64Array()
	var hidden_v: PackedFloat64Array = PackedFloat64Array()
	var wisdom = 0.0
	var s0 = 0.0
	var morale = 0.0
	var m0 = 0.0
	var rout_thr = 0.0
	var eb = 0.0
	var loss_mult = 1.0
	var dmg_taken = 1.0
	var trait_taken = 1.0
	var trait_morale = 1.0
	var cannon_loss_mult = 1.0
	var trait_fire: PackedFloat64Array = PackedFloat64Array()
	var trait_melee: PackedFloat64Array = PackedFloat64Array()
	var trait_bias: PackedFloat64Array = PackedFloat64Array()
	var role_bias: PackedFloat64Array = PackedFloat64Array()
	var fire_pack: PackedFloat64Array = PackedFloat64Array()
	var melee_pack: PackedFloat64Array = PackedFloat64Array()
	var range_add: PackedFloat64Array = PackedFloat64Array()
	var reach_add: PackedFloat64Array = PackedFloat64Array()
	var pen_trait = 1.0
	var pen_scale = 1.0
	var bonus_scale = 1.0
	var insight_add = 0.0
	var start_add = 0.0
	var rout_add = 0.0
	var strength_id = ""
	var weakness_id = ""
	var hidden_id = ""
	var hidden_on = false
	var rash_left = 0
	var rash_advance = 0.0
	var rash_taken_mult = 1.0
	var lucky_left = 0
	var lucky_mult = 1.0
	var cool_left = 0
	var msg_delay = 0
	var auto_tick = 0
	var rally_left = 0
	var res_left = 0
	var has_standing = false
	var stand_action = ""
	var stand_cond = ""
	var stand_value = 0.0
	var live_tick = -1
	var live_action = ""
	var msg_used = false
	var arrived = false
	var send_tick = -1
	var arrival = -1
	var sent_action = ""
	var routed = false
	var eliminated = false
	var holds = false
	var scen_fire = 1.0
	var scen_taken = 1.0
	var scen_morale = 1.0
	var saw_melee = false
	var shook_high = false
	var shook_low = false
	var lost_strength = 0.0
	var revealed = {}
	var initial_front: PackedInt32Array = PackedInt32Array()
	var initial_reserve: PackedInt32Array = PackedInt32Array()

	func setup(nu: int, ns: int, nh: int, nf: int) -> void:
		front.resize(nu)
		reserve.resize(nu)
		skills.resize(ns)
		hidden_v.resize(nh)
		fire_pack.resize(nu)
		melee_pack.resize(nu)
		trait_fire.resize(nu)
		trait_melee.resize(nu)
		range_add.resize(nu)
		reach_add.resize(nu)
		trait_bias.resize(nf)
		role_bias.resize(nf)


	func ensure_attrs(n: int) -> void:
		attrs.resize(n)
