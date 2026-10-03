class_name BrZone
extends RefCounted

# Battleground shrinking zone (DESIGN_V2 §3.3). A pure function of match time:
# every phase circle is precomputed at construction from the zone's own seed
# stream hash([seed, "zone"]), so simulation, AI and UI read the same circles
# and nothing depends on how the match plays out.
#
# Phase k (1..6) shrinks the circle linearly from circle k - 1 to circle k
# during [shrink_start[k], shrink_end[k]]; circle 0 is the whole map (centre of
# the map, radius = half diagonal). The next centre lies within
# (r_prev - r_next) * 0.8 of the current one, on ground walkable for a 30 px
# body (gate frames count as wall, so the circles do not depend on the gate
# state of the arena passed in), and the edge speed (dr + dcentre) / shrink
# time never exceeds 45 px/s.
# Circles that fit the map are kept inside the bounds, so the last circle and
# the final point always lie inside the map.
#
# Damage outside the circle: max-HP fraction per second of the current phase
# (phase k from shrink_start[k] until the next shrink starts), true damage in
# TICK-second ticks (applied by the mode). Nothing before phase 1.
#
# Information: AI and UI read public_view(t) only. Circle k becomes public at
# announce_at[k]: phase 1 at 45 s (normal speed) during the loot phase, every
# later phase when the wait after the previous shrink begins. Circles after
# the next one are never readable through it.

const PHASES := 6
const SPEEDS := {"fast": 0.8, "normal": 1.0, "slow": 1.25}
const SPEED_LABELS := {"fast": "빠름", "normal": "보통", "slow": "느림"}
const BODY := 30.0
const MAX_EDGE_SPEED := 45.0
const SHIFT_RATIO := 0.8
const TICK := 0.5
# Normal-speed schedule per phase: [shrink start, shrink end, radius / half
# diagonal, damage (max-HP fraction per second)]. Fast x0.8, slow x1.25.
const SCHEDULE := [
	[75.0, 135.0, 0.52, 0.01],
	[195.0, 240.0, 0.32, 0.02],
	[280.0, 315.0, 0.19, 0.035],
	[345.0, 370.0, 0.11, 0.05],
	[390.0, 410.0, 0.054, 0.08],
	[425.0, 455.0, 0.0, 0.12],
]
const FIRST_ANNOUNCE := 45.0
# Circles keep at least this much centre freedom inside the bounds even when
# they are wider than the map (phase 1 on the metropolis).
const BOUNDS_SLACK := 96.0
const CENTRE_TRIES := 32

var speed: String = "normal"
var time_scale: float = 1.0
var half_diag: float = 0.0
var bounds: Rect2 = Rect2()
# Index 0 = the full circle at t = 0, k = 1..6 the circle phase k shrinks to.
var centers: PackedVector2Array = PackedVector2Array()
var radii: PackedFloat64Array = PackedFloat64Array()
# Index k = 1..6 (index 0 unused, 0.0).
var announce_at: PackedFloat64Array = PackedFloat64Array()
var shrink_start: PackedFloat64Array = PackedFloat64Array()
var shrink_end: PackedFloat64Array = PackedFloat64Array()
# Index k = damage while phase k is current (index 0 = loot, no damage).
var dps: PackedFloat64Array = PackedFloat64Array()


func _init(arena: Arena = null, data: Dictionary = {}, seed_value: int = 0, speed_id: String = "normal") -> void:
	if arena == null:
		return
	speed = speed_id if SPEEDS.has(speed_id) else "normal"
	time_scale = float(SPEEDS[speed])
	bounds = Rect2(arena.min_x, arena.min_y, arena.max_x - arena.min_x, arena.max_y - arena.min_y)
	var br: Dictionary = data.get("br", {})
	var c0: Vector2 = Vector2(arena.width * 0.5, arena.height * 0.5)
	if br.has("center"):
		c0 = Vector2(float(br.center.x), float(br.center.y))
	half_diag = float(br.get("half_diag", 0.5 * sqrt(arena.width * arena.width + arena.height * arena.height)))
	if not walkable(arena, c0):
		c0 = arena.resolve_circle(c0, BODY)
	centers.append(c0)
	radii.append(half_diag)
	announce_at.append(0.0)
	shrink_start.append(0.0)
	shrink_end.append(0.0)
	dps.append(0.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "zone"])
	for k in range(1, PHASES + 1):
		var row: Array = SCHEDULE[k - 1]
		var t0: float = float(row[0]) * time_scale
		var t1: float = float(row[1]) * time_scale
		var r_prev: float = radii[k - 1]
		var r_next: float = float(row[2]) * half_diag
		var dr: float = r_prev - r_next
		var max_shift: float = maxf(0.0, minf(SHIFT_RATIO * dr, MAX_EDGE_SPEED * (t1 - t0) - dr))
		var c_prev: Vector2 = centers[k - 1]
		var box: Rect2 = _center_box(r_next)
		var c_next: Vector2 = c_prev
		for _try in CENTRE_TRIES:
			var p: Vector2 = c_prev + Vector2.from_angle(rng.randf() * TAU) * max_shift * sqrt(rng.randf())
			p = Vector2(clampf(p.x, box.position.x, box.end.x), clampf(p.y, box.position.y, box.end.y))
			if p.distance_to(c_prev) <= max_shift and walkable(arena, p):
				c_next = p
				break
		centers.append(c_next)
		radii.append(r_next)
		shrink_start.append(t0)
		shrink_end.append(t1)
		announce_at.append(FIRST_ANNOUNCE * time_scale if k == 1 else shrink_end[k - 1])
		dps.append(float(row[3]))


# Walkable for a BODY-sized hero whatever the gates show right now: a gate
# frame always counts as wall, so the shared arena and a battle copy whose
# gates are open give the same circles.
static func walkable(arena: Arena, p: Vector2) -> bool:
	for g: Dictionary in arena.gates:
		if (g.rect as Rect2).grow(BODY).has_point(p):
			return false
	return arena.is_walkable(p, BODY)


# Centre range that keeps a circle of radius r inside the bounds (or as far
# inside as a wider circle can be, leaving BOUNDS_SLACK of freedom).
func _center_box(r: float) -> Rect2:
	var ix: float = minf(r, bounds.size.x * 0.5 - BOUNDS_SLACK)
	var iy: float = minf(r, bounds.size.y * 0.5 - BOUNDS_SLACK)
	return Rect2(bounds.position + Vector2(ix, iy), bounds.size - Vector2(ix, iy) * 2.0)


# 0 during the loot phase, k from shrink_start[k] until the next shrink starts.
func phase_at(t: float) -> int:
	var k: int = 0
	for i in range(1, PHASES + 1):
		if t >= shrink_start[i]:
			k = i
	return k


func state_at(t: float) -> String:
	var k: int = phase_at(t)
	if k == 0:
		return "loot"
	if t < shrink_end[k]:
		return "shrink"
	return "final" if k == PHASES else "wait"


func center_at(t: float) -> Vector2:
	var k: int = phase_at(t)
	if k == 0:
		return centers[0]
	if t >= shrink_end[k]:
		return centers[k]
	return centers[k - 1].lerp(centers[k], _progress(k, t))


func radius_at(t: float) -> float:
	var k: int = phase_at(t)
	if k == 0:
		return radii[0]
	if t >= shrink_end[k]:
		return radii[k]
	return lerpf(radii[k - 1], radii[k], _progress(k, t))


func _progress(k: int, t: float) -> float:
	return clampf((t - shrink_start[k]) / maxf(0.001, shrink_end[k] - shrink_start[k]), 0.0, 1.0)


# Max-HP fraction per second taken outside the circle at t.
func dps_ratio_at(t: float) -> float:
	return dps[phase_at(t)]


func outside(p: Vector2, t: float) -> bool:
	if phase_at(t) == 0:
		return false
	return p.distance_to(center_at(t)) > radius_at(t)


func final_time() -> float:
	return shrink_end[PHASES]


func announce_time(k: int) -> float:
	return announce_at[clampi(k, 1, PHASES)]


# Everything a participant may know at t. next_* is the circle the current or
# coming shrink ends on, from its announce time; before that (and once the
# zone has closed) next_known is false and next_* repeat the current circle.
# t_state_end: end of the current state (INF in the final state).
func public_view(t: float) -> Dictionary:
	var k: int = phase_at(t)
	var st: String = state_at(t)
	var c: Vector2 = center_at(t)
	var r: float = radius_at(t)
	var target: int = -1
	var t_end: float = INF
	match st:
		"loot":
			target = 1
			t_end = shrink_start[1]
		"shrink":
			target = k
			t_end = shrink_end[k]
		"wait":
			target = k + 1
			t_end = shrink_start[k + 1]
	var known: bool = target > 0 and t >= announce_at[target]
	return {"phase": k, "phases_total": PHASES, "state": st, "center": c, "radius": r,
		"next_center": centers[target] if known else c, "next_radius": radii[target] if known else r,
		"next_known": known, "t_state_end": t_end, "dps_ratio": dps[k]}


# Public timetable for setup screens (no circle positions):
# [{phase, announce, shrink_start, shrink_end, radius_ratio, dps_ratio}].
static func schedule_rows(speed_id: String = "normal") -> Array:
	var sc: float = float(SPEEDS.get(speed_id, 1.0))
	var out: Array = []
	for k in range(1, PHASES + 1):
		var row: Array = SCHEDULE[k - 1]
		var announce: float = FIRST_ANNOUNCE * sc if k == 1 else float(SCHEDULE[k - 2][1]) * sc
		out.append({"phase": k, "announce": announce, "shrink_start": float(row[0]) * sc, "shrink_end": float(row[1]) * sc,
			"radius_ratio": float(row[2]), "dps_ratio": float(row[3])})
	return out
