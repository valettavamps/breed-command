extends RefCounted
## FNV-1a 32-bit and SHA helpers. Not balance data.
## hash32(master, check_id, trial) is FNV-1a over the UTF-8 string "master|check|trial".
## The spec names hash32 and does not define the mix; this is the one used everywhere.

static var _mask := 0


static func mask32() -> int:
	if _mask != 0:
		return _mask
	var m := 0
	var bits := "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
	for _i in bits.length():
		m = (m << 1) | 1
	_mask = m
	return m


static func fnv32(text: String) -> int:
	var h := 2166136261
	var prime := 16777619
	var mask := mask32()
	for i in text.length():
		h = h ^ text.unicode_at(i)
		h = (h * prime) & mask
	return h


static func hash32(master: int, check_id: String, trial: int) -> int:
	return fnv32("%d|%s|%d" % [master, check_id, trial])


static func hex_bytes(buf: PackedByteArray) -> String:
	var digits := "0123456789abcdef"
	var nib := digits.length() - 1
	var shift := "xxxx".length()
	var out := ""
	for b in buf:
		var bv := int(b)
		out += digits[(bv >> shift) & nib]
		out += digits[bv & nib]
	return out


static func sha256_bytes(buf: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return hex_bytes(ctx.finish())


static func sha256_text(text: String) -> String:
	return sha256_bytes(text.to_utf8_buffer())


static func sha1_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(text.to_utf8_buffer())
	return hex_bytes(ctx.finish())


# full_precision is Grisu2, integer-only. The default printer calls libm log10
# and snprintf, and UCRT disagrees with glibc on the last digits. That changed
# 73 of 1,000 B1 log hashes on Windows while the battle math matched.
static func json_text(value) -> String:
	return JSON.stringify(value, "", true, true)
