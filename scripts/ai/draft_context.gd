class_name DraftContextV2
extends RefCounted

# Public, static battlefield evidence. No BattleSim, hidden unit state, random
# draws or navigation caches are touched while opening the draft screen.
const BODY := 20.0


static func route_estimate(a: Arena, start: Vector2, end: Vector2) -> float:
	var direct: float = start.distance_to(end)
	if not a.segment_blocked(start, end, BODY, Arena.MASK_UNITS):
		return direct
	var best: float = INF
	# Bounded visibility detours, not an exact combat path. Test both directions
	# around each obstacle; complex labyrinths use a conservative proxy below.
	for i in a.obs_count:
		if (a.obs_mask[i] & Arena.MASK_UNITS) == 0:
			continue
		var corners: Array[Vector2] = []
		if a.obs_circle[i] == 1:
			var center := Vector2(a.obs_x[i], a.obs_y[i])
			for k in 8:
				corners.append(center + Vector2.from_angle(k * TAU / 8.0) * (a.obs_r[i] + BODY + 8.0) / cos(PI / 8.0))
		else:
			var left: float = a.obs_x[i] - BODY - 2.0
			var top: float = a.obs_y[i] - BODY - 2.0
			var right: float = a.obs_x[i] + a.obs_w[i] + BODY + 2.0
			var bottom: float = a.obs_y[i] + a.obs_h[i] + BODY + 2.0
			corners.assign([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])
		for p in corners:
			if not a.is_walkable(p, BODY) or a.segment_blocked(start, p, BODY, Arena.MASK_UNITS):
				continue
			if not a.segment_blocked(p, end, BODY, Arena.MASK_UNITS):
				best = minf(best, start.distance_to(p) + p.distance_to(end))
			for q in corners:
				if p == q or not a.is_walkable(q, BODY):
					continue
				if not a.segment_blocked(p, q, BODY, Arena.MASK_UNITS) and not a.segment_blocked(q, end, BODY, Arena.MASK_UNITS):
					best = minf(best, start.distance_to(p) + p.distance_to(q) + q.distance_to(end))
	return best if is_finite(best) else direct * 1.5


static func geometry(a: Arena) -> Dictionary:
	var c0: Vector2 = a.spawn_centroid(0)
	var c1: Vector2 = a.spawn_centroid(1)
	var axis: Vector2 = (c1 - c0).normalized() if c0.distance_to(c1) > 1.0 else Vector2.RIGHT
	var lateral := Vector2(-axis.y, axis.x)
	var half_width: float = minf(a.max_x - a.min_x, a.max_y - a.min_y) * 0.32
	var shots: float = 0.0
	var clear_shots: float = 0.0
	var crossings: float = 0.0
	var blocked_crossings: float = 0.0
	# Sample the engagement corridor in map-relative coordinates. Moving a wall
	# out of that corridor now changes the answer even at identical wall density.
	for depth in [0.25, 0.5, 0.75]:
		for lane in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var center: Vector2 = c0.lerp(c1, depth) + lateral * half_width * lane
			var p: Vector2 = center - axis * 160.0
			var q: Vector2 = center + axis * 160.0
			if not a.is_walkable(p, BODY) or not a.is_walkable(q, BODY):
				continue
			shots += 1.0
			if not a.segment_blocked(p, q, 2.0, Arena.MASK_VISION | Arena.MASK_PROJECTILES) and not a.forest_occludes(p, q):
				clear_shots += 1.0
			crossings += 1.0
			if a.segment_blocked(p, q, BODY, Arena.MASK_UNITS):
				blocked_crossings += 1.0
	var pair_distance: float = 0.0
	var pair_count: int = 0
	var sheltered: float = 0.0
	var approach_distance: float = 0.0
	var radius: float = 0.0
	var point_heal: float = 0.0
	var heal_supply: float = 0.0
	for z: Dictionary in a.heal_zones:
		heal_supply += clampf(float(z.get("heal_ratio", 0.35)), 0.0, 1.0) * 60.0 / maxf(1.0, float(z.get("cooldown", 25.0)))
	for i in a.control_points.size():
		var p: Dictionary = a.control_points[i]
		radius += float(p.get("radius", 88.0))
		for spawn in [c0, c1]:
			approach_distance += route_estimate(a, spawn, p.center)
		for k in 8:
			var outer: Vector2 = p.center + Vector2.from_angle(k * TAU / 8.0) * 260.0
			if a.segment_blocked(p.center, outer, 2.0, Arena.MASK_VISION | Arena.MASK_PROJECTILES) or a.forest_occludes(p.center, outer):
				sheltered += 1.0 / 8.0
		var heal_near: float = 0.0
		for z: Dictionary in a.heal_zones:
			var distance: float = maxf(0.0, route_estimate(a, p.center, z.center) - float(p.get("radius", 88.0)) - float(z.get("radius", 52.0)))
			# Leaving an objective has a travel cost; a remote heal is not on-point
			# sustain. Cooldown also limits a single pickup shared by the team.
			var supply: float = clampf(float(z.get("heal_ratio", 0.35)), 0.0, 1.0) * 60.0 / maxf(1.0, float(z.get("cooldown", 25.0)))
			heal_near = maxf(heal_near, supply / (1.0 + distance / 180.0))
		point_heal += heal_near
		for j in range(i + 1, a.control_points.size()):
			pair_distance += route_estimate(a, p.center, a.control_points[j].center)
			pair_count += 1
	var count: float = maxf(1.0, a.control_points.size())
	var direct: float = maxf(1.0, c0.distance_to(c1))
	return {"fire_lanes": clear_shots / maxf(1.0, shots),
		"choke": blocked_crossings / maxf(1.0, crossings),
		"route_stretch": clampf(route_estimate(a, c0, c1) / direct - 1.0, 0.0, 1.0),
		"point_count": a.control_points.size(), "point_radius": radius / count,
		"rotation_distance": pair_distance / maxf(1.0, pair_count),
		"spawn_point_distance": approach_distance / (2.0 * count),
		"point_shelter": sheltered / count,
		"heal_supply": 1.0 - exp(-heal_supply), "point_heal": 1.0 - exp(-point_heal / count)}


static func control_team(fs: Array, m: Dictionary, synergy: Callable) -> float:
	if fs.is_empty():
		return 0.0
	var point_count: int = maxi(1, int(m.get("point_count", 3)))
	var needed: int = mini(fs.size(), point_count / 2 + 1)
	var distances: float = float(m.get("rotation_distance", 700.0))
	var travel: float = 0.0
	var holders: Array = []
	for i in fs.size():
		var f: Dictionary = fs[i]
		var speed: float = maxf(1.0, float(f.move_speed) * (1.0 + 0.25 * float(f.mobility)))
		var rotation: float = 1.0 / (1.0 + distances / speed / DominationMode.RESPAWN_DELAY)
		travel += rotation
		var reach: float = clampf(float(f.get("displacement", 0.0)) / maxf(1.0, float(m.get("point_radius", 88.0))), 0.0, 1.0)
		var strength: float = 0.25 * float(f.durability) + 0.20 * float(f.damage) + 0.13 * float(f.healing) + 0.10 * float(f.control)
		strength += 0.08 * reach + 0.10 * rotation - 0.14 * float(f.ally_only) - 0.10 * float(f.fragile)
		holders.append({"i": i, "v": strength})
	holders.sort_custom(func(a, b): return a.v > b.v if absf(a.v - b.v) > 1e-9 else a.i < b.i)
	var coverage: float = 0.0
	var weakest: float = INF
	for i in needed:
		coverage += float(holders[i].v)
		weakest = minf(weakest, float(holders[i].v))
	var escort: float = 0.0
	for i in range(needed, holders.size()):
		var support: Dictionary = fs[int(holders[i].i)]
		var best: float = 0.0
		for k in needed:
			var holder: Dictionary = fs[int(holders[k].i)]
			best = maxf(best, float(synergy.call(support, holder)))
		# Each extra ally supports one defending group, never all remote circles.
		escort += best + 0.10 * float(support.damage)
	return 0.24 * coverage / needed + 0.16 * weakest + 0.12 * travel / fs.size() + 0.12 * escort / fs.size()
