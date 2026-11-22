extends RefCounted
## Bit-exact stand-ins for libm log, exp, and cos.
## Windows UCRT and glibc do not agree in the last bits, and that was
## enough to change 73 of 1,000 B1 log hashes. These series use only + - * /.


const LN2 := 0.69314718055994530941723212145818
const PI := 3.1415926535897932384626433832795


static func ln(x: float) -> float:
	if x <= 0.0:
		return -1.0e300
	var e := 0
	while x >= 2.0:
		x *= 0.5
		e += 1
	while x < 1.0:
		x *= 2.0
		e -= 1
	var y := (x - 1.0) / (x + 1.0)
	var y2 := y * y
	var sum := 0.0
	var term := y
	var n := 1
	for _i in 40:
		sum += term / float(n)
		term *= y2
		n += 2
	return 2.0 * sum + float(e) * LN2


static func exp(x: float) -> float:
	if x > 700.0:
		return 1.0e300
	if x < -700.0:
		return 0.0
	var n := int(floor(x / LN2))
	var r := x - float(n) * LN2
	var sum := 1.0
	var term := 1.0
	for k in 30:
		term *= r / float(k + 1)
		sum += term
	var p := 1.0
	if n >= 0:
		for _i in n:
			p *= 2.0
	else:
		for _i in -n:
			p *= 0.5
	return sum * p


static func cos(x: float) -> float:
	var two_pi := PI * 2.0
	var turns := floor(x / two_pi)
	var r: float = x - turns * two_pi
	if r > PI:
		r -= two_pi
	# Taylor of cos on [-pi, pi]
	var r2: float = r * r
	var sum := 1.0
	var term := 1.0
	for k in 20:
		term *= -r2 / float((2 * k + 1) * (2 * k + 2))
		sum += term
	return sum
