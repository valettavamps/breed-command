extends RefCounted
## Pure daily clock. No Steam calls and no read of the machine clock.
##
## Boundary is 00:00 UTC. While synced, authoritative time is the injected
## server time. Offline, authoritative time is local time plus the last
## offset (server - local) learned while synced. Before the first sync the
## offset is 0. day_index never goes backwards on an account.

const Civil = preload("res://scripts/civil_time.gd")

var net_state := "offline"
var server_unix := 0
var local_unix := 0
var offset_sec := 0
var has_synced := false
var has_day := false
var highest_day := 0


func authoritative_unix() -> int:
	if net_state == "synced":
		return server_unix
	if has_synced:
		return local_unix + offset_sec
	return local_unix


func day_index() -> int:
	var day := Civil.day_index_from_unix(authoritative_unix())
	if not has_day:
		has_day = true
		highest_day = day
		return day
	if day > highest_day:
		highest_day = day
		return day
	return highest_day


func set_synced(server: int, local: int) -> void:
	net_state = "synced"
	server_unix = server
	local_unix = local
	offset_sec = server_unix - local_unix
	has_synced = true
	day_index()


func set_server(server: int) -> void:
	server_unix = server
	if net_state == "synced":
		offset_sec = server_unix - local_unix
		has_synced = true
	day_index()


func set_local(local: int) -> void:
	local_unix = local
	if net_state == "synced":
		offset_sec = server_unix - local_unix
		has_synced = true
	day_index()


func set_offline(local: int) -> void:
	# Freeze the offset learned at the last sync.
	local_unix = local
	net_state = "offline"
	day_index()


func to_record() -> Dictionary:
	return {
		"v": 1,
		"net_state": net_state,
		"offset_sec": offset_sec,
		"has_synced": has_synced,
		"has_day": has_day,
		"highest_day": highest_day,
	}


func load_record(rec: Dictionary) -> void:
	net_state = str(rec.get("net_state", "offline"))
	offset_sec = int(rec.get("offset_sec", 0))
	has_synced = bool(rec.get("has_synced", false))
	has_day = bool(rec.get("has_day", false))
	highest_day = int(rec.get("highest_day", 0))


static func roll_account_day(account: Dictionary, clock: RefCounted) -> bool:
	# Returns true when the UTC day advanced and daily counters should reset.
	var day: int = clock.day_index()
	var prev := int(account.get("day_index", day))
	account["day_index"] = day
	account["clock"] = clock.to_record()
	return day > prev
