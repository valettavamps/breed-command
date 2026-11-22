extends RefCounted
## Gregorian UTC conversion. Calendar constants live here, not in the battle math.
## day_index is whole days since 2026-01-01 00:00 UTC (spec §22).


static func days_from_civil(y: int, m: int, d: int) -> int:
	# Howard Hinnant, public domain. Returns days since 1970-01-01.
	var yy := y
	if m <= 2:
		yy -= 1
	var era := 0
	if yy >= 0:
		era = int(yy / 400)
	else:
		era = int((yy - 399) / 400)
	var yoe := yy - era * 400
	var mp := m + 9
	if m > 2:
		mp = m - 3
	var doy := int((153 * mp + 2) / 5) + d - 1
	var doe := yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
	return era * 146097 + doe - 719468


static func to_unix(y: int, m: int, d: int, h: int, mi: int, s: int) -> int:
	return days_from_civil(y, m, d) * 86400 + h * 3600 + mi * 60 + s


static func epoch_unix() -> int:
	return to_unix(2026, 1, 1, 0, 0, 0)


static func day_index_from_unix(unix_sec: int) -> int:
	var delta := unix_sec - epoch_unix()
	var span := 86400
	if delta >= 0:
		return int(delta / span)
	if delta % span == 0:
		return int(delta / span)
	return int(delta / span) - 1


static func parse_iso(text: String) -> Dictionary:
	var raw := text.strip_edges()
	if raw.ends_with("Z"):
		raw = raw.substr(0, raw.length() - 1)
	var halves := raw.split("T")
	var date := halves[0].split("-")
	var clock := halves[1].split(":")
	var sec := clock[2].split(".")[0]
	return {
		"y": int(date[0]),
		"m": int(date[1]),
		"d": int(date[2]),
		"h": int(clock[0]),
		"mi": int(clock[1]),
		"s": int(sec),
	}


static func unix_from_iso(text: String) -> int:
	var p := parse_iso(text)
	return to_unix(int(p["y"]), int(p["m"]), int(p["d"]), int(p["h"]), int(p["mi"]), int(p["s"]))
