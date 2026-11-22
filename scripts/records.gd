extends RefCounted
## Versioned save and battle records.
## Addendum E: officer and army records do not carry side or faction_id.
## Campaign hooks (campaign.sides, location controller, option.side, scope_id)
## stay in data and are not written onto those records in M1.

const SAVE_VERSION := 1


static func officer(fields: Dictionary) -> Dictionary:
	var o := fields.duplicate(true)
	o["v"] = SAVE_VERSION
	o.erase("side")
	o.erase("faction_id")
	return o


static func army(fields: Dictionary) -> Dictionary:
	var a := fields.duplicate(true)
	a["v"] = SAVE_VERSION
	a.erase("side")
	a.erase("faction_id")
	if a.has("officer") and a["officer"] is Dictionary:
		a["officer"] = officer(a["officer"])
	return a


static func save_file(clock_state: Dictionary, officers: Array, armies: Array) -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"clock": clock_state,
		"officers": officers,
		"armies": armies,
	}


static func battle_log_version() -> int:
	return SAVE_VERSION
