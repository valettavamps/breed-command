extends RefCounted
## Single parser for process flags.
## AC-8-PUBLIC-FLAGS-IGNORED: a public build will ignore --scope-id, --clock,
## --local-clock and --net-state unless a QA-build flag is set. That gate is
## deferred to M4. M1 reads the flags and threads them into GameClock.

const FLAG_SCOPE := "--scope-id"
const FLAG_CLOCK := "--clock"
const FLAG_LOCAL := "--local-clock"
const FLAG_NET := "--net-state"
const FLAG_SUITE := "--suite"
const FLAG_SEED := "--master-seed"
const FLAG_TRIAL := "--trial"
const FLAG_OUT := "--out"
const FLAG_SMOKE := "--smoke"


static func parse_user_args(args: PackedStringArray) -> Dictionary:
	var out := {
		"scope_id": "",
		"clock": "",
		"local_clock": "",
		"net_state": "",
		"suite": "",
		"master_seed": 0,
		"has_seed": false,
		"trial": -1,
		"out": "",
		"smoke": false,
	}
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == FLAG_SMOKE:
			out["smoke"] = true
			i += 1
			continue
		if i + 1 >= args.size():
			i += 1
			continue
		var val := str(args[i + 1])
		if a == FLAG_SCOPE:
			out["scope_id"] = val
		elif a == FLAG_CLOCK:
			out["clock"] = val
		elif a == FLAG_LOCAL:
			out["local_clock"] = val
		elif a == FLAG_NET:
			out["net_state"] = val
		elif a == FLAG_SUITE:
			out["suite"] = val
		elif a == FLAG_SEED:
			out["master_seed"] = int(val)
			out["has_seed"] = true
		elif a == FLAG_TRIAL:
			out["trial"] = int(val)
		elif a == FLAG_OUT:
			out["out"] = val
		i += 1
		i += 1
	return out
