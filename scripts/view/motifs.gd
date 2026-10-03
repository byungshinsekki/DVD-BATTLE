class_name Motifs
extends RefCounted



const INK: = Color(0.024, 0.047, 0.086, 1.0)


const BASIC: = {
	"swordsman": "saber", "archer": "bow", "mage": "crystal", "sniper": "rifle", "werewolf": "claw", "giant": "fist", 
	"aphrodite": "heart", "blood_mage": "blood", "fisherman": "harpoon", "baseball": "bat", "pirate": "cutlass", 
	"joker": "dagger", "metatron": "feather", "plague_doctor": "needle", "hive_mind": "larva", "nitro": "gauntlet", 
	"dimensionalist": "prism", "hermes": "sickle", "world_tree": "leaf", "torturer": "whip", "engineer": "wrench", 
	"hades": "bident", "war_machine": "piston", "torquemada": "cross", "achilles": "spear", 
}

const BASIC_SHOT: = {
	"archer": "arrow", "mage": "crystal", "sniper": "bullet", "aphrodite": "heart", "blood_mage": "blood", 
	"plague_doctor": "needle", "hive_mind": "larva", "dimensionalist": "prism", "pirate": "bullet", "engineer": "bolt", 
	"world_tree": "leaf", "fisherman": "harpoon", "metatron": "feather", "torturer": "needle", 
}

const RANGED_HOLD: = ["archer", "sniper", "mage", "aphrodite", "blood_mage", "plague_doctor", "hive_mind", "dimensionalist", "engineer", "world_tree"]


static func quad(p0: Vector2, p1: Vector2, p2: Vector2, n: int = 10) -> PackedVector2Array:
	var out: = PackedVector2Array()
	for i in n + 1:
		var t: = float(i) / n
		out.append(p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + p2 * t * t)
	return out


static func cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n: int = 12) -> PackedVector2Array:
	var out: = PackedVector2Array()
	for i in n + 1:
		var t: = float(i) / n
		var u: = 1.0 - t
		out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return out


static func ngon(r: float, sides: int, rot: float = 0.0, c: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out: = PackedVector2Array()
	for i in sides:
		out.append(c + Vector2.from_angle(rot + TAU * i / sides) * r)
	return out


static func _fill(ci: CanvasItem, pts: PackedVector2Array, co: Color, edge: Color, w: float = 1.2) -> void :
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, co)
	if edge.a > 0.0 and pts.size() >= 2:
		var closed: = pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, edge, w, true)


static func outline(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void :
	var closed: = pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col, w, true)


static func heart_pts(r: float) -> PackedVector2Array:
	var pts: = PackedVector2Array()
	pts.append_array(cubic(Vector2(0, r * 0.8), Vector2( - r * 1.8, - r * 0.2), Vector2( - r * 0.3, - r * 1.5), Vector2(0, - r * 0.45), 10))
	pts.append_array(cubic(Vector2(0, - r * 0.45), Vector2(r * 0.3, - r * 1.5), Vector2(r * 1.8, - r * 0.2), Vector2(0, r * 0.8), 10))
	return pts


static func wing_pts(r: float) -> PackedVector2Array:
	var pts: = PackedVector2Array()
	pts.append_array(quad(Vector2(r * 1.4, 0), Vector2(r * 0.2, - r * 1.6), Vector2( - r * 1.7, - r * 0.85), 8))
	pts.append(Vector2( - r * 0.6, - r * 0.1))
	pts.append(Vector2( - r * 1.35, r * 0.65))
	pts.append_array(quad(Vector2( - r * 1.35, r * 0.65), Vector2(r * 0.6, r * 0.95), Vector2(r * 1.4, 0), 8))
	return pts



static func draw(ci: CanvasItem, m: String, at: Vector2, rot: float, r: float, co: Color, hi: Color, t: float = 0.0, alpha: float = 1.0) -> void :
	ci.draw_set_transform(at, rot, Vector2.ONE)
	co.a *= alpha
	hi.a *= alpha
	var ink: = Color(INK, 0.85 * alpha)
	match m:
		"dispatch", "diversion", "propaganda", "contemplation", "censorship":
			var sheet: = PackedVector2Array([Vector2(-r, -r * 0.7), Vector2(r * 0.7, -r * 0.7), Vector2(r, -r * 0.35), Vector2(r, r * 0.75), Vector2(-r, r * 0.75)])
			_fill(ci, sheet, ink, co, 1.5)
			for line_i in 3:
				ci.draw_line(Vector2(-r * 0.65, r * (-0.3 + line_i * 0.3)), Vector2(r * (0.5 if line_i < 2 else 0.1), r * (-0.3 + line_i * 0.3)), hi, 1.2, true)
			if m == "propaganda":
				ci.draw_arc(Vector2.ZERO, r * 1.45, -0.7, 0.7, 12, hi, 1.4, true)
				ci.draw_arc(Vector2.ZERO, r * 1.8, -0.6, 0.6, 12, co, 1.0, true)
			elif m == "censorship":
				ci.draw_line(Vector2(-r * 1.2, r), Vector2(r * 1.2, -r), hi, 2.4, true)
		"arrow", "fanarrow", "ricochet", "executeArrow":
			ci.draw_line(Vector2(-18, 0), Vector2(10, 0), co, 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(2, -4.5), Vector2(4, 0), Vector2(2, 4.5)]), hi)
			for sg: float in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-18, sg * 5), Vector2(-10, sg * 2), Vector2(-7, 0), Vector2(-17, 0)]), co)
			if m == "executeArrow":
				ci.draw_line(Vector2(3, -6), Vector2(8, 0), hi, 1.5, true)
				ci.draw_line(Vector2(3, 6), Vector2(8, 0), hi, 1.5, true)
			if m == "ricochet":
				ci.draw_arc(Vector2(-4, 0), 7.0, 0, TAU, 16, Color(co, 0.6 * alpha), 1.0, true)
		"bullet", "buckshot":
			var body: = quad(Vector2(12, 0), Vector2(8, -3), Vector2(-3, -3), 4)
			body.append(Vector2(-9, -2))
			body.append(Vector2(-9, 2))
			body.append_array(quad(Vector2(-3, 3), Vector2(8, 3), Vector2(12, 0), 4))
			_fill(ci, body, co, hi, 1.0)
			ci.draw_line(Vector2(-15, 0), Vector2(-9, 0), hi, 1.5, true)
		"bolt":
			_fill(ci, PackedVector2Array([Vector2(12, 0), Vector2(-4, -3), Vector2(-8, 0), Vector2(-4, 3)]), co, hi, 1.0)
			ci.draw_line(Vector2(-14, 0), Vector2(-8, 0), hi, 1.2, true)
		"crystal", "ice", "prism", "shards":
			var cr: = PackedVector2Array([Vector2(r * 1.55, 0), Vector2( - r * 0.3, - r * 0.65), Vector2( - r, r * 0.1), Vector2( - r * 0.2, r * 0.65)])
			_fill(ci, cr, co, hi, 1.1)
			ci.draw_line(Vector2( - r, 0), Vector2(r * 1.5, 0), hi, 1.0, true)
			ci.draw_line(Vector2( - r * 0.3, - r * 0.65), Vector2(r * 0.1, 0), hi, 1.0, true)
			if m == "ice":
				for sg: float in [-1.0, 1.0]:
					ci.draw_line(Vector2( - r * 0.4, sg * r * 0.8), Vector2( - r * 1.3, sg * r * 0.9), co, 1.4, true)
			if m == "prism":
				ci.draw_line(Vector2( - r, - r * 0.9), Vector2(r * 0.9, - r * 0.4), Color(hi, 0.65 * alpha), 1.0, true)
				ci.draw_line(Vector2( - r, r * 0.9), Vector2(r * 0.9, r * 0.4), Color(co, 0.6 * alpha), 1.0, true)
		"hook", "grapple", "harpoon":
			var hk: = PackedVector2Array([Vector2(-13, 0), Vector2(4, 0)])
			for i in 9:
				var a: = - PI * 0.5 + (PI * 1.38) * i / 8.0
				hk.append(Vector2(4, 6) + Vector2.from_angle(a) * 6.0)
			hk.append(Vector2(0, 3))
			ci.draw_polyline(hk, hi, 2.4, true)
			ci.draw_arc(Vector2(-14, 0), 2.0, 0, TAU, 10, co, 1.5, true)
			if m == "grapple":
				ci.draw_polyline(PackedVector2Array([Vector2(4, 0), Vector2(8, -6), Vector2(11, -3)]), hi, 2.0, true)
		"fish", "bait":
			_fill(ci, PackedVector2Array([Vector2(-8, 0), Vector2(-15, -6), Vector2(-15, 6)]), co, hi)
			var ell: = PackedVector2Array()
			for i in 16:
				var a2: = TAU * i / 16.0
				ell.append(Vector2(cos(a2) * 10.0, sin(a2) * 5.0))
			_fill(ci, ell, co, hi)
			ci.draw_circle(Vector2(5, -1.3), 1.4, ink)
			ci.draw_line(Vector2(-1, -4), Vector2(2, -7), hi, 1.4, true)
		"baseball":
			var br: = maxf(5.0, r)
			ci.draw_circle(Vector2.ZERO, br, Color(1.0, 0.97, 0.92, alpha))
			for sg: float in [-1.0, 1.0]:
				ci.draw_arc(Vector2(sg * br * 0.9, 0), br * 0.9, PI * 0.64 if sg > 0 else -1.1, PI * 1.36 if sg > 0 else 1.1, 10, Color(0.85, 0.41, 0.4, alpha), 1.3, true)
			ci.draw_arc(Vector2.ZERO, br, 0, TAU, 20, Color(ink, 0.6 * alpha), 1.0, true)
		"heart", "aegis":
			_fill(ci, heart_pts(maxf(5.0, r)), co, hi)
		"apple":
			var ap: = PackedVector2Array()
			for i in 16:
				ap.append(Vector2(cos(TAU * i / 16.0) * r, sin(TAU * i / 16.0) * r * 0.9))
			_fill(ci, ap, co, hi)
			ci.draw_line(Vector2(0, - r * 0.7), Vector2(3, - r - 5), hi, 1.7, true)
			ci.draw_circle(Vector2(5, - r - 3), 2.2, Color(0.68, 0.84, 0.6, alpha))
		"banana":
			ci.draw_set_transform(at, rot - 0.35, Vector2.ONE)
			var bn: = quad(Vector2(-12, -3), Vector2(0, 12), Vector2(13, -6), 8)
			bn.append_array(quad(Vector2(13, -6), Vector2(5, 15), Vector2(-6, 8), 8))
			bn.append_array(quad(Vector2(-6, 8), Vector2(-12, 6), Vector2(-12, -3), 4))
			_fill(ci, bn, Color(0.97, 0.85, 0.43, alpha), hi)
			ci.draw_line(Vector2(11, -5), Vector2(12, -9), Color(0.68, 0.53, 0.26, alpha), 2.0, true)
		"coinbag":
			var cb: = quad(Vector2(-4, - r * 0.8), Vector2( - r * 1.2, - r * 0.1), Vector2( - r * 0.6, r * 0.7), 6)
			cb.append_array(quad(Vector2( - r * 0.6, r * 0.7), Vector2(0, r * 1.15), Vector2(r * 0.7, r * 0.6), 6))
			cb.append_array(quad(Vector2(r * 0.7, r * 0.6), Vector2(r * 1.2, 0), Vector2(4, - r * 0.8), 6))
			_fill(ci, cb, Color(0.65, 0.49, 0.26, alpha), hi)
			ci.draw_line(Vector2(-5, - r * 0.7), Vector2(5, - r * 0.7), hi, 2.0, true)
		"cannon", "bomb":
			var cr2: = maxf(5.0, r)
			ci.draw_circle(Vector2.ZERO, cr2, Color(0.15, 0.19, 0.24, alpha) if m == "cannon" else Color(0.46, 0.22, 0.15, alpha))
			ci.draw_arc(Vector2( - cr2 * 0.2, - cr2 * 0.2), cr2 * 0.43, PI, TAU, 8, co, 1.0, true)
			ci.draw_line(Vector2(0, - cr2), Vector2(3, - cr2 - 4), hi, 1.5, true)
			ci.draw_circle(Vector2(3, - cr2 - 5), 1.8, Color(1.6, 1.4, 0.8, alpha))
		"boulder", "stone":
			ci.draw_set_transform(at, rot + t * 0.65, Vector2.ONE)
			_fill(ci, ngon(r, 7, 0.25), Color(0.46, 0.39, 0.33, alpha), Color(0.85, 0.74, 0.58, alpha))
			ci.draw_polyline(PackedVector2Array([Vector2( - r * 0.65, - r * 0.35), Vector2(0, - r * 0.12), Vector2(r * 0.35, r * 0.63)]), Color(0.85, 0.74, 0.58, alpha), 1.2, true)
		"blood", "flame", "meteor":
			var bl: = cubic(Vector2(r * 1.2, 0), Vector2( - r * 0.1, - r), Vector2( - r * 1.25, - r * 0.75), Vector2( - r * 1.45, 0), 8)
			bl.append_array(cubic(Vector2( - r * 1.45, 0), Vector2( - r * 1.25, r * 0.75), Vector2( - r * 0.1, r), Vector2(r * 1.2, 0), 8))
			_fill(ci, bl, co, Color(0, 0, 0, 0))
			ci.draw_circle(Vector2(r * 0.2, - r * 0.1), r * 0.35, hi)
			if m != "blood":
				ci.draw_line(Vector2( - r * 1.2, - r * 0.55), Vector2( - r * 2.2, - r * 0.3), co, 2.0, true)
				ci.draw_line(Vector2( - r * 1.2, r * 0.55), Vector2( - r * 1.8, r * 0.7), co, 1.5, true)
		"wing", "feather", "wings", "talaria":
			_fill(ci, wing_pts(r), co, hi, 1.0)
			for i in 4:
				ci.draw_line(Vector2(r * 0.8 - i * r * 0.35, 0), Vector2( - r * 0.1 - i * r * 0.43, - r * (0.55 + i * 0.12)), Color(hi, 0.8 * alpha), 0.8, true)
		"larva", "brood", "parasite", "serpent":
			var lv: = PackedVector2Array()
			for i in 14:
				var a3: = TAU * i / 14.0
				lv.append(Vector2(cos(a3) * r * 1.2, sin(a3) * r * 0.55))
			_fill(ci, lv, co, hi)
			for i: int in [-1, 0, 1]:
				var x: = float(i) * r * 0.6
				ci.draw_line(Vector2(x, - r * 0.35), Vector2(x - r * 0.3, - r * 0.9), co, 1.2, true)
				ci.draw_line(Vector2(x, r * 0.35), Vector2(x - r * 0.3, r * 0.9), co, 1.2, true)
			ci.draw_circle(Vector2(r * 0.65, -1), 1.4, hi)
		"swordwave", "crescent", "wave":
			var cw: = quad(Vector2( - r * 0.3, - r * 1.6), Vector2(r * 1.8, 0), Vector2( - r * 0.3, r * 1.6), 10)
			cw.append_array(quad(Vector2( - r * 0.3, r * 1.6), Vector2(r * 0.55, 0), Vector2( - r * 0.3, - r * 1.6), 10))
			_fill(ci, cw, co, hi)
		"sickle":
			var sk: = quad(Vector2(-11, -2), Vector2(13, -13), Vector2(13, 1), 8)
			sk.append_array(quad(Vector2(13, 1), Vector2(3, -3), Vector2(-8, 3), 8))
			_fill(ci, sk, co, hi)
			ci.draw_line(Vector2(-9, 0), Vector2(-16, 0), co, 3.0, true)
		"saber", "lunge", "execution", "cutlass", "dagger", "knife", "needle":
			var nw: = 1.7 if m == "needle" else (3.0 if m == "dagger" or m == "knife" else 4.0)
			var ln: = 16.0 if m != "saber" else 20.0
			_fill(ci, PackedVector2Array([Vector2(ln, 0), Vector2(-3, - nw), Vector2(-7, 0), Vector2(-3, nw)]), co, hi)
			if m == "cutlass":
				ci.draw_arc(Vector2(-7, 0), 5.0, PI * 0.5, PI * 1.5, 8, hi, 1.5, true)
			ci.draw_line(Vector2(-7, -4), Vector2(-7, 4), co, 2.0, true)
			ci.draw_line(Vector2(-8, 0), Vector2(-15, 0), co, 3.0, true)
		"bat":
			ci.draw_set_transform(at, rot - 0.4, Vector2.ONE)
			ci.draw_rect(Rect2(-16, -3, 10, 6), Color(0.54, 0.41, 0.28, alpha))
			var bt: = PackedVector2Array([Vector2(-8, -3), Vector2(16, -4.5), Vector2(19, 0), Vector2(16, 4.5), Vector2(-8, 3)])
			_fill(ci, bt, Color(0.95, 0.83, 0.66, alpha), hi)
		"claw", "fang", "bite":
			for i in 3:
				var y: = -8.0 + i * 8.0
				var cl: = quad(Vector2(-8, y), Vector2(13, y - 3), Vector2(9, y + 5), 6)
				cl.append(Vector2(4, y + 5))
				cl.append_array(quad(Vector2(4, y + 5), Vector2(10, y), Vector2(-8, y), 6))
				_fill(ci, cl, co, hi, 1.0)
		"fist", "gauntlet":
			var fc: = Color(0.67, 0.51, 0.37, alpha) if m == "fist" else Color(0.63, 0.33, 0.21, alpha)
			ci.draw_rect(Rect2(-9, -8, 21, 16), fc)
			ci.draw_rect(Rect2(-9, -8, 21, 16), hi, false, 1.2)
			for i in 3:
				ci.draw_line(Vector2(1 + i * 4, -5), Vector2(1 + i * 4, 3), co, 1.2, true)
		"bow":
			var bw: = quad(Vector2(0, -10), Vector2(13, 0), Vector2(0, 10), 10)
			ci.draw_polyline(bw, co, 2.2, true)
			var pull: = -5.0 * clampf(t, 0.0, 1.0)
			ci.draw_polyline(PackedVector2Array([Vector2(0, -10), Vector2(pull, 0), Vector2(0, 10)]), hi, 1.0, true)
		"rifle":
			ci.draw_rect(Rect2(-3, -3, 18, 6), Color(0.22, 0.25, 0.29, alpha))
			ci.draw_line(Vector2(0, -3), Vector2(14, -3), co, 1.5, true)
			ci.draw_line(Vector2(10, 0), Vector2(28, 0), hi, 2.0, true)
			ci.draw_line(Vector2(3, -5), Vector2(10, -5), co, 2.0, true)
		"whip":
			var wp: = PackedVector2Array()
			for i in 12:
				var x2: = -8.0 + i * 2.6
				wp.append(Vector2(x2, sin(i * 0.9 + t * 7.0) * 3.0 * (i / 11.0)))
			ci.draw_line(Vector2(-14, 0), Vector2(-8, 0), co, 3.0, true)
			ci.draw_polyline(wp, hi, 1.6, true)
		"wrench":
			ci.draw_line(Vector2(-12, 0), Vector2(6, 0), co, 3.0, true)
			ci.draw_arc(Vector2(9, 0), 4.5, PI * 0.25, PI * 1.75, 10, hi, 2.4, true)
		"gear":
			for i in 8:
				ci.draw_set_transform(at, rot + i * TAU / 8.0 + t * 0.25, Vector2.ONE)
				ci.draw_rect(Rect2(r * 0.6, - r * 0.12, r * 0.5, r * 0.24), co)
			ci.draw_set_transform(at, rot, Vector2.ONE)
			ci.draw_arc(Vector2.ZERO, r * 0.65, 0, TAU, 20, hi, 2.0, true)
			ci.draw_arc(Vector2.ZERO, r * 0.27, 0, TAU, 12, hi, 2.0, true)
		# V2 weapons and projectiles (fixed pixel sizes like the other held weapons).
		"bident":
			ci.draw_line(Vector2(-15, 0), Vector2(8, 0), Color(0.36, 0.3, 0.52, alpha), 2.4, true)
			ci.draw_line(Vector2(8, -4.5), Vector2(8, 4.5), hi, 2.0, true)
			for sg: float in [-1.0, 1.0]:
				ci.draw_line(Vector2(8, sg * 4.5), Vector2(15, sg * 4.5), hi, 1.8, true)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(19, sg * 4.5), Vector2(14.5, sg * 4.5 - 2.2), Vector2(14.5, sg * 4.5 + 2.2)]), hi)
			ci.draw_circle(Vector2(-15, 0), 2.0, co)
		"piston":
			ci.draw_rect(Rect2(-13, -3.5, 11, 7), Color(0.27, 0.29, 0.33, alpha))
			ci.draw_rect(Rect2(-13, -3.5, 11, 7), Color(co, 0.9 * alpha), false, 1.0)
			ci.draw_line(Vector2(-2, 0), Vector2(6, 0), Color(0.85, 0.88, 0.92, alpha), 2.6, true)
			_fill(ci, PackedVector2Array([Vector2(6, -6), Vector2(13, -5.5), Vector2(16, 0), Vector2(13, 5.5), Vector2(6, 6)]), co, hi, 1.0)
			ci.draw_line(Vector2(9, -4), Vector2(9, 4), Color(ink, 0.7 * alpha), 1.2, true)
		"cross":
			ci.draw_line(Vector2(-15, 0), Vector2(12, 0), Color(0.5, 0.37, 0.22, alpha), 2.2, true)
			ci.draw_line(Vector2(7, -5.5), Vector2(7, 5.5), hi, 2.2, true)
			ci.draw_line(Vector2(7, 0), Vector2(14, 0), hi, 2.2, true)
			ci.draw_circle(Vector2(7, 0), 2.2, co)
			var fl: = 3.0 + sin(t * 11.0) * 0.8
			ci.draw_colored_polygon(PackedVector2Array([Vector2(14, -2.2), Vector2(14 + fl * 1.6, 0), Vector2(14, 2.2)]), Color(1.7, 1.25, 0.45, 0.85 * alpha))
		"spear", "pierce":
			if m == "pierce":
				# Thrown spear: a long piercing wake behind the shaft.
				for k in 3:
					var wy: = (k - 1) * 3.2
					ci.draw_line(Vector2(-24, wy), Vector2(-24 - 26.0 + absf(wy) * 3.0, wy * 1.8), Color(hi, (0.55 - absf(wy) * 0.08) * alpha), 1.2 if k != 1 else 2.0, true)
				ci.draw_line(Vector2(-24, 0), Vector2(-62, 0), Color(co, 0.35 * alpha), 4.0, true)
			ci.draw_line(Vector2(-21, 0), Vector2(9, 0), Color(0.58, 0.42, 0.26, alpha), 2.0, true)
			ci.draw_line(Vector2(-24, 0), Vector2(-21, 0), hi, 1.6, true)
			_fill(ci, PackedVector2Array([Vector2(22, 0), Vector2(13, -3.4), Vector2(9, 0), Vector2(13, 3.4)]), co, hi, 1.0)
			ci.draw_line(Vector2(9, -2.2), Vector2(9, 2.2), hi, 1.5, true)
		"missile":
			var flame: = 5.0 + 2.5 * absf(sin(t * 37.0))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, -2.0), Vector2(-7 - flame, 0), Vector2(-7, 2.0)]), Color(2.0, 1.15, 0.4, 0.9 * alpha))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, -1.0), Vector2(-7 - flame * 0.5, 0), Vector2(-7, 1.0)]), Color(2.2, 2.0, 1.3, alpha))
			for sg: float in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, sg * 2.4), Vector2(-11, sg * 6.0), Vector2(-9.5, sg * 2.0)]), co)
			_fill(ci, PackedVector2Array([Vector2(8, -2.6), Vector2(-7, -2.6), Vector2(-7, 2.6), Vector2(8, 2.6)]), Color(0.86, 0.88, 0.9, alpha), Color(ink, 0.6 * alpha), 0.8)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(8, -2.6), Vector2(8, 2.6)]), co)
			ci.draw_line(Vector2(2, -2.6), Vector2(2, 2.6), co, 1.6, true)
		"leaf":
			var lf: = quad(Vector2( - r, 0), Vector2(0, - r * 0.9), Vector2(r * 1.2, 0), 8)
			lf.append_array(quad(Vector2(r * 1.2, 0), Vector2(0, r * 0.9), Vector2( - r, 0), 8))
			_fill(ci, lf, co, hi)
			ci.draw_line(Vector2( - r * 1.3, 0), Vector2(r * 1.1, 0), hi, 1.0, true)
		_:
			_fill(ci, ngon(maxf(5.0, r), 6, 0.3), Color(co, 0.3 * alpha), co)
			ci.draw_circle(Vector2.ZERO, 2.2, hi)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



static func signature(ci: CanvasItem, id: String, at: Vector2, rot: float, r: float, col: Color, t: float = 0.0) -> void :
	ci.draw_set_transform(at, rot, Vector2.ONE)
	var w: = 1.5
	match id:
		"swordsman", "werewolf", "hermes", "pirate":
			var count: = 3 if id == "werewolf" else (2 if id == "swordsman" else 1)
			for i in count:
				ci.draw_polyline(quad(Vector2( - r * 0.8, (i - 1) * r * 0.35), Vector2(r * 0.3, - r * (0.6 + 0.15 * i)), Vector2(r, (-0.4 + i * 0.25) * r), 8), col, w, true)
		"archer":
			for i in 3:
				var d: = Vector2.from_angle((i - 1) * 0.45)
				ci.draw_line( - d * r, d * r, col, 1.6, true)
				ci.draw_colored_polygon(PackedVector2Array([d * r, d * r * 0.5 + d.orthogonal() * r * 0.25, d * r * 0.5 - d.orthogonal() * r * 0.25]), col)
		"sniper":
			ci.draw_arc(Vector2.ZERO, r, 0, TAU, 28, col, 1.6, true)
			for i in 4:
				var d2: = Vector2.from_angle(i * PI * 0.5)
				ci.draw_line(d2 * r * 0.65, d2 * r * 1.25, col, 1.3, true)
		"mage", "dimensionalist":
			outline(ci, ngon(r, 6, t * 0.5), col, w)
			outline(ci, ngon(r * 0.65, 3, - t * 0.5), col, w)
			if id == "dimensionalist":
				ci.draw_arc(Vector2.ZERO, r * 1.3, 0.3, 5.6, 24, col, 1.0, true)
		"giant":
			outline(ci, ngon(r, 7, 0.2), col, w)
			for i in 4:
				var d3: = Vector2.from_angle(1.6 * (i + 1))
				ci.draw_line(d3 * r * 0.3, d3 * r * 1.4 + d3.orthogonal() * r * 0.2, col, 2.0, true)
		"aphrodite":
			outline(ci, heart_pts(r * 0.9), col, w)
		"blood_mage":
			for i in 3:
				var rot2: = i * TAU / 3.0 + t * 0.2
				var drop: = cubic(Vector2(0, - r), Vector2(r * 0.8, r * 0.3), Vector2(0, r * 0.8), Vector2(0, r * 0.4), 6)
				drop.append_array(cubic(Vector2(0, r * 0.4), Vector2( - r * 0.8, r * 0.3), Vector2(0, - r), Vector2(0, - r), 6))
				var rp: = PackedVector2Array()
				for q in drop:
					rp.append(q.rotated(rot2))
				ci.draw_polyline(rp, col, w, true)
		"fisherman":
			var fh: = PackedVector2Array([Vector2( - r, - r * 0.5), Vector2(r * 0.3, - r * 0.5)])
			for i in 9:
				fh.append(Vector2(r * 0.3, r * 0.2) + Vector2.from_angle( - PI * 0.5 + PI * 1.3 * i / 8.0) * r * 0.7)
			ci.draw_polyline(fh, col, w, true)
		"baseball":
			ci.draw_arc(Vector2.ZERO, r, 0, TAU, 24, col, 2.0, true)
			ci.draw_arc(Vector2(r, 0), r, 2.0, 4.2, 10, col, 1.2, true)
			ci.draw_arc(Vector2( - r, 0), r, 5.1, 7.2, 10, col, 1.2, true)
		"joker":
			for i in 4:
				var c: = Vector2.from_angle(i * TAU / 4.0) * r * 0.65
				outline(ci, ngon(r * 0.5, 4, t * 0.4, c), col, w)
		"metatron":
			for sg: float in [-1.0, 1.0]:
				for i in 4:
					ci.draw_polyline(quad(Vector2(0, r * 0.3), Vector2(sg * r * 0.7, - r * (0.6 - i * 0.12)), Vector2(sg * r * (1.3 - i * 0.16), - r * 0.6 + i * r * 0.35), 6), col, w, true)
		"plague_doctor":
			for i in 6:
				var a: = i * TAU / 6.0 + t * 0.3
				ci.draw_arc(Vector2(cos(a), sin(a)) * r * 0.7, r * 0.23, 0, TAU, 10, col, 1.2, true)
		"hive_mind":
			outline(ci, ngon(r * 0.5, 6), col, w)
			for i in 3:
				outline(ci, ngon(r * 0.4, 6, 0.0, Vector2.from_angle(i * TAU / 3.0) * r), col, w)
		"nitro":
			for i in 4:
				var rp2: = PackedVector2Array()
				for q in [Vector2( - r * 0.2, - r), Vector2(r * 0.4, - r * 0.1), Vector2.ZERO, Vector2(r * 0.2, r * 0.8)]:
					rp2.append((q as Vector2).rotated(TAU * i / 4.0))
				ci.draw_polyline(rp2, col, w, true)
		"world_tree":
			ci.draw_line(Vector2(0, r), Vector2(0, - r), col, 3.0, true)
			for i in 3:
				for sg: float in [-1.0, 1.0]:
					var y: = r * 0.3 - i * r * 0.4
					ci.draw_line(Vector2(0, y), Vector2(sg * r * (0.75 - i * 0.15), y - r * 0.5), col, 2.0, true)
		"politician":
			outline(ci, ngon(r, 6, PI / 6.0), col, w)
			ci.draw_line(Vector2(-r * 0.55, r * 0.55), Vector2(r * 0.55, r * 0.55), col, w)
			for i in 3:
				var x: = (i - 1) * r * 0.42
				ci.draw_line(Vector2(x, r * 0.45), Vector2(x, -r * 0.35), col, w)
			ci.draw_polyline(PackedVector2Array([Vector2(-r * 0.6, -r * 0.4), Vector2(0, -r * 0.8), Vector2(r * 0.6, -r * 0.4)]), col, w, true)
		"torturer":
			for i in range(-2, 3):
				var c2: = Vector2(i * r * 0.42, sin(t + i) * r * 0.15)
				var el: = PackedVector2Array()
				for k in 12:
					el.append(c2 + Vector2(cos(TAU * k / 12.0) * r * 0.3, sin(TAU * k / 12.0) * r * 0.18).rotated(i * 0.18))
				outline(ci, el, col, w)
		"engineer":
			draw(ci, "gear", at, rot, r, col, col, t)
			ci.draw_set_transform(at, rot, Vector2.ONE)
		"hades":
			# Bident over a bowl of three souls (cerberus heads).
			ci.draw_line(Vector2(0, r * 0.95), Vector2(0, - r * 0.2), col, w, true)
			for sg: float in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([Vector2(0, - r * 0.2), Vector2(sg * r * 0.5, - r * 0.42), Vector2(sg * r * 0.5, - r * 1.05)]), col, w, true)
			ci.draw_arc(Vector2(0, r * 0.05), r * 0.85, PI * 0.12, PI * 0.88, 12, col, w, true)
			for i in 3:
				ci.draw_arc(Vector2.from_angle(PI * 0.5 + (i - 1) * 0.7) * r * 1.05, r * 0.16, 0, TAU, 8, col, 1.2, true)
		"war_machine":
			outline(ci, ngon(r * 0.5, 6, t * 0.3), col, w)
			for i in 3:
				var dm: = Vector2.from_angle(i * TAU / 3.0 + t * 0.3)
				ci.draw_polyline(PackedVector2Array([dm * r * 0.72 + dm.orthogonal() * r * 0.24, dm * r * 1.08, dm * r * 0.72 - dm.orthogonal() * r * 0.24]), col, w, true)
				ci.draw_line(dm * r * 0.55, dm * r * 0.82, col, 1.2, true)
		"torquemada":
			ci.draw_line(Vector2(0, - r), Vector2(0, r * 0.8), col, w, true)
			ci.draw_line(Vector2( - r * 0.5, - r * 0.38), Vector2(r * 0.5, - r * 0.38), col, w, true)
			for i in 6:
				var fa: = i * TAU / 6.0 + t * 0.4
				ci.draw_polyline(quad(Vector2.from_angle(fa - 0.2) * r * 0.95, Vector2.from_angle(fa) * r * 1.35, Vector2.from_angle(fa + 0.2) * r * 0.95, 4), col, 1.2, true)
		"achilles":
			ci.draw_arc(Vector2.ZERO, r * 0.78, 0, TAU, 28, col, w, true)
			ci.draw_arc(Vector2.ZERO, r * 0.34, 0, TAU, 14, col, w, true)
			ci.draw_line(Vector2( - r * 1.25, r * 0.55), Vector2(r * 1.05, - r * 0.46), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(r * 1.35, - r * 0.6), Vector2(r * 0.95, - r * 0.6), Vector2(r * 1.12, - r * 0.28)]), col)
		_:
			outline(ci, ngon(r, 5, t * 0.2), col, w)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
