extends SceneTree

# V2.0 battleground world (DESIGN_V2 §3.2-§3.4), every preset at three seeds:
# map generation (determinism, size, content ranges, spawns, item spots and
# rings, connectivity for every body bucket, build time, an independent
# Navigator cross-check), the shrinking zone (schedule per speed, monotone
# radius, edge speed, walkable centres, final circle inside the map, damage,
# public_view never revealing a phase before its announce time), the 80-item
# placement (ring counts, rarity trend, spacing) and the DB cache.
#
# Build times are printed and kept in metrics; the only time check is a
# generous 5 s guard against pathological generation (the target is 1.5 s).

const SEEDS := [7, 4242, 20261001]
const SIZES := {"br_ashen_metropolis": Vector2(7712.0, 4336.0), "br_wildwood_frontier": Vector2(7040.0, 4752.0),
	"br_highland_ruins": Vector2(5792.0, 5776.0)}
const VIEW_KEYS := ["phase", "phases_total", "state", "center", "radius", "next_center", "next_radius", "next_known", "t_state_end", "dps_ratio"]
const TIME_GUARD_MS := 5000

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _run() -> void:
	DB.ensure_loaded()
	_catalogue()
	var maps: Array = []
	for id in BattlegroundMapData.ORDER:
		for sv in SEEDS:
			var data: Dictionary = _map(str(id), int(sv))
			if not data.is_empty():
				maps.append({"id": str(id), "seed": int(sv), "data": data})
	for m: Dictionary in maps:
		if int(m.seed) == int(SEEDS[0]):
			_navigator_cross_check(m.data)
	var zone_seen: Dictionary = {}
	for m: Dictionary in maps:
		var arena: Arena = Arena.from_data(m.data)
		for speed in ["fast", "normal", "slow"]:
			_zone(m, arena, str(speed))
		zone_seen[str(m.id)] = (zone_seen.get(str(m.id), []) as Array) + [BrZone.new(arena, m.data, int(m.seed)).centers]
		_items(m)
	for id in zone_seen:
		var c: Array = zone_seen[id]
		_check(c.size() < 2 or c[0] != c[1], "zone: different seeds move %s's circles differently" % id)
	_items_aggregate(maps)
	_db_cache()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("BATTLEGROUND_WORLD_V2 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--report="):
			var f: FileAccess = FileAccess.open(str(arg).substr(9), FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify({"suite": "battleground_world_v2", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ catalogue

func _korean(s: String) -> bool:
	for i in s.length():
		var code: int = s.unicode_at(i)
		if code >= 0xAC00 and code <= 0xD7A3:
			return true
	return false


func _catalogue() -> void:
	var cat: Array = BattlegroundMapData.catalogue()
	_check(cat.size() == 3, "catalogue: 3 presets")
	var dm_keys: Array = (DeathmatchMapData.catalogue()[0] as Dictionary).keys()
	for i in cat.size():
		var e: Dictionary = cat[i]
		_check(str(e.id) == str(BattlegroundMapData.ORDER[i]), "catalogue: order %d" % i)
		for key in dm_keys:
			_check(e.has(key), "catalogue %s: has %s" % [e.id, key])
		_check(str(e.ruleset) == "battleground" and str(e.kind) == "battleground", "catalogue %s: battleground kind" % e.id)
		for key in ["name", "subtitle", "description"]:
			_check(_korean(str(e[key])), "catalogue %s: Korean %s" % [e.id, key])
		_check((e.tacticalNotes as Array).size() >= 3, "catalogue %s: tactical notes" % e.id)
		for note in e.tacticalNotes:
			_check(_korean(str(note)), "catalogue %s: Korean note" % e.id)
		for tag in e.tags:
			_check(_korean(str(tag)), "catalogue %s: Korean tag %s" % [e.id, tag])
		var size: Vector2 = SIZES[str(e.id)]
		_check(float(e.width) == size.x and float(e.height) == size.y, "catalogue %s: size" % e.id)
	_check(DB.battleground_catalogue() == cat, "DB.battleground_catalogue matches")
	for id in BattlegroundMapData.ORDER:
		_check(DB.is_battleground_id(str(id)), "DB.is_battleground_id(%s)" % id)
	_check(not DB.is_battleground_id("classic") and not DB.is_battleground_id("dm_forest_village"), "DB.is_battleground_id rejects other maps")


# ------------------------------------------------------------------ maps

func _map(id: String, sv: int) -> Dictionary:
	var label: String = "%s/%d" % [id, sv]
	var t0: int = Time.get_ticks_usec()
	var data: Dictionary = BattlegroundMapData.build(id, sv)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	var t1: int = Time.get_ticks_usec()
	var again: Dictionary = BattlegroundMapData.build(id, sv)
	var ms2: float = (Time.get_ticks_usec() - t1) / 1000.0
	print("BUILD_MS %s seed=%d first=%.0f second=%.0f attempt=%d" % [id, sv, ms, ms2, int(data.get("generation_attempt", -1))])
	var times: Dictionary = metrics.get("build_ms", {})
	times[label] = snappedf(ms, 1.0)
	metrics["build_ms"] = times
	metrics["build_ms_max"] = maxf(float(metrics.get("build_ms_max", 0.0)), ms)
	_check(not data.is_empty(), label + ": build succeeds")
	if data.is_empty():
		return {}
	_check(ms <= TIME_GUARD_MS, label + ": build under the pathological guard (%.0f ms)" % ms)
	_check(JSON.stringify(data).sha256_text() == JSON.stringify(again).sha256_text(), label + ": deterministic (identical data hash)")
	_check(not data.has("generation_fallback"), label + ": no canonical fallback needed")
	# Size and area.
	var size: Vector2 = SIZES[id]
	var w: float = float(data.width)
	var h: float = float(data.height)
	_check(w == size.x and h == size.y, label + ": size %dx%d" % [int(w), int(h)])
	_check(fmod(w, 16.0) == 0.0 and fmod(h, 16.0) == 0.0, label + ": 16 px grid")
	var ratio: float = w * h / (Arena.WIDTH * Arena.HEIGHT)
	_check(ratio >= 29.0 and ratio <= 31.0, label + ": area %.2fx standard" % ratio)
	_check(str(data.kind) == "battleground" and str(data.ruleset) == "battleground" and str(data.preset) == id, label + ": kind/ruleset")
	_check(str(data.id) == "%s_%d" % [id, sv], label + ": id")
	var arena: Arena = Arena.from_data(data)
	_check(arena.width == w and arena.obs_count == (data.obstacles as Array).size() and arena.ffa_spawns.size() == (data.ffa_spawns as Array).size(), label + ": Arena.from_data accepts it")
	# br block.
	var br: Dictionary = data.br
	var center: Vector2 = Vector2(float(br.center.x), float(br.center.y))
	var half_diag: float = float(br.half_diag)
	_check(center == Vector2(w, h) * 0.5 and absf(half_diag - 0.5 * sqrt(w * w + h * h)) < 0.01, label + ": br centre and half diagonal")
	_check((br.landmarks as Array).size() == (data.landmarks as Array).size(), label + ": br landmarks")
	# Content ranges.
	var patches: Dictionary = {}
	for f: Dictionary in data.forests:
		patches[int(f.patch)] = true
	var counts: Dictionary = {"obstacles": (data.obstacles as Array).size(), "brush": (data.forests as Array).size(),
		"patches": patches.size(), "hazards": (data.hazards as Array).size(), "landmarks": (data.landmarks as Array).size()}
	for key in BattlegroundMapData.LIMITS:
		var lim: Array = BattlegroundMapData.LIMITS[key]
		_check(int(counts[key]) >= int(lim[0]) and int(counts[key]) <= int(lim[1]), label + ": %s %d in %d-%d" % [key, int(counts[key]), int(lim[0]), int(lim[1])])
	var per: Dictionary = metrics.get("content", {})
	per[label] = counts
	metrics["content"] = per
	for hz: Dictionary in data.hazards:
		_check(Arena.HAZARD_TYPES.has(str(hz.type)), label + ": supported hazard type " + str(hz.type))
	var features: Dictionary = BattlegroundMapData.feature_counts(data)
	for req: Array in BattlegroundMapData.REQUIRED[id]:
		var n: int = int(features.get(str(req[0]), 0))
		_check(n >= int(req[1]) and n <= int(req[2]), label + ": %s %d in %d-%d" % [str(req[0]), n, int(req[1]), int(req[2])])
	var names: Dictionary = {}
	for mark: Dictionary in data.landmarks:
		_check(_korean(str(mark.label)) and not names.has(str(mark.label)), label + ": landmark name " + str(mark.label))
		names[str(mark.label)] = true
	# Spawns.
	var spawns: Array = data.ffa_spawns
	var core: float = minf(w, h) * 0.18
	_check(spawns.size() >= 40, label + ": spawns %d >= 40" % spawns.size())
	var min_gap: float = INF
	var min_core: float = INF
	for i in spawns.size():
		var p: Vector2 = Vector2(float(spawns[i].x), float(spawns[i].y))
		min_core = minf(min_core, p.distance_to(center))
		_check(p.x >= arena.min_x and p.x <= arena.max_x and p.y >= arena.min_y and p.y <= arena.max_y, label + ": spawn %d inside the bounds" % i)
		for j in range(i + 1, spawns.size()):
			min_gap = minf(min_gap, p.distance_to(Vector2(float(spawns[j].x), float(spawns[j].y))))
	_check(min_gap >= 800.0, label + ": spawns >= 800 px apart (min %.0f)" % min_gap)
	_check(min_core >= core, label + ": spawns outside the central circle r=%.0f (min %.0f)" % [core, min_core])
	# Item spots and rings.
	var spots: Array = data.item_spots
	var rings: Array = [0, 0, 0, 0]
	var ring_ok: bool = true
	for s: Dictionary in spots:
		var p2: Vector2 = Vector2(float(s.x), float(s.y))
		var d: float = p2.distance_to(center) / half_diag
		var want: int = 0 if d < 0.2 else (1 if d < 0.45 else (2 if d < 0.7 else 3))
		ring_ok = ring_ok and int(s.ring) == want and s.has("kind")
		rings[int(s.ring)] += 1
	_check(spots.size() >= 240, label + ": item spots %d >= 240" % spots.size())
	_check(ring_ok, label + ": every spot's ring follows the distance rule")
	for k in 4:
		_check(int(rings[k]) >= int(BattlegroundMapData.RING_SPOT_MIN[k]), label + ": ring %d populated (%d)" % [k, int(rings[k])])
	# Connectivity for every body bucket (one flood fill per bucket).
	var conn: Array = BattlegroundMapData.connectivity(data, arena)
	_check(conn.size() == 4, label + ": four buckets checked")
	for row: Dictionary in conn:
		var b: int = int(row.bucket)
		_check((row.anchors_bad as Array).is_empty(), label + ": bucket %d spawns/hazards/centre in the main component %s" % [b, str(row.anchors_bad)])
		_check((row.spots_bad as Array).is_empty(), label + ": bucket %d every item spot in the main component" % b)
		var share: Dictionary = metrics.get("main_share", {})
		share["%s/%d" % [label, b]] = snappedf(float(row.main_size) / maxf(1.0, float(row.free)), 0.001)
		metrics["main_share"] = share
	return data


# The run-length grid must be exactly Navigator's solid map, and real A* must
# reach a sample of anchors from the first spawn.
func _navigator_cross_check(data: Dictionary) -> void:
	var label: String = "%s nav" % str(data.preset)
	var arena: Arena = Arena.from_data(data)
	var nav: Navigator = Navigator.new()
	nav.arena = arena
	nav.bucket = 30.0
	nav._build()
	var grid: Dictionary = BattlegroundMapData.run_grid(data, 30.0)
	var mismatch: int = 0
	for y in nav.rows:
		for x in nav.cols:
			if nav.grid.is_point_solid(Vector2i(x, y)) != (BattlegroundMapData.comp_at(grid, x, y) < 0):
				mismatch += 1
	_check(mismatch == 0, label + ": run grid equals Navigator's bucket-30 solid map (%d mismatches)" % mismatch)
	var first: Vector2 = Vector2(float(data.ffa_spawns[0].x), float(data.ffa_spawns[0].y))
	var targets: Array = []
	var spawns: Array = data.ffa_spawns
	for k in [int(spawns.size() * 0.25), int(spawns.size() * 0.5), spawns.size() - 1]:
		targets.append(Vector2(float(spawns[k].x), float(spawns[k].y)))
	var spots: Array = data.item_spots
	for k in 6:
		var s: Dictionary = spots[int(float(k * spots.size()) / 6.0)]
		targets.append(Vector2(float(s.x), float(s.y)))
	targets.append(Vector2(float(data.width), float(data.height)) * 0.5)
	for p: Vector2 in targets:
		_check(nav.path_length(first, p, 30.0, 0.0, 0.0, 0.0, false) < INF, label + ": A* reaches %s" % str(p))


# ------------------------------------------------------------------ zone

func _zone(m: Dictionary, arena: Arena, speed: String) -> void:
	var data: Dictionary = m.data
	var sv: int = int(m.seed)
	var label: String = "%s/%d zone %s" % [m.id, sv, speed]
	var z: BrZone = BrZone.new(arena, data, sv, speed)
	var z2: BrZone = BrZone.new(arena, data, sv, speed)
	_check(z.centers == z2.centers and z.radii == z2.radii, label + ": deterministic")
	var f: float = float(BrZone.SPEEDS[speed])
	_check(z.centers.size() == BrZone.PHASES + 1 and z.radii.size() == BrZone.PHASES + 1, label + ": 6 phases")
	var hd: float = float(data.br.half_diag)
	_check(absf(z.radii[0] - hd) < 0.01 and z.centers[0] == Vector2(float(data.width), float(data.height)) * 0.5, label + ": starts as the whole map from the centre")
	for k in range(1, BrZone.PHASES + 1):
		var row: Array = BrZone.SCHEDULE[k - 1]
		_check(absf(z.shrink_start[k] - float(row[0]) * f) < 1e-6 and absf(z.shrink_end[k] - float(row[1]) * f) < 1e-6, label + ": phase %d shrink window" % k)
		_check(absf(z.radii[k] - float(row[2]) * hd) < 0.01, label + ": phase %d radius" % k)
		var announce: float = 45.0 * f if k == 1 else z.shrink_end[k - 1]
		_check(absf(z.announce_at[k] - announce) < 1e-6, label + ": phase %d announced at %.1f" % [k, announce])
		var dr: float = z.radii[k - 1] - z.radii[k]
		var dc: float = z.centers[k].distance_to(z.centers[k - 1])
		var span: float = z.shrink_end[k] - z.shrink_start[k]
		_check((dr + dc) / span <= BrZone.MAX_EDGE_SPEED + 1e-6, label + ": phase %d edge speed %.2f <= 45 px/s" % [k, (dr + dc) / span])
		_check(dc <= 0.8 * dr + 1e-3, label + ": phase %d centre shift %.0f <= 0.8 x %.0f" % [k, dc, dr])
		_check(arena.is_walkable(z.centers[k], 30.0), label + ": phase %d centre walkable for a 30 px body" % k)
		if z.radii[k] * 2.0 <= minf(arena.max_x - arena.min_x, arena.max_y - arena.min_y) - 2.0 * BrZone.BOUNDS_SLACK:
			var c: Vector2 = z.centers[k]
			var r: float = z.radii[k]
			_check(c.x - r >= arena.min_x - 1e-3 and c.x + r <= arena.max_x + 1e-3 and c.y - r >= arena.min_y - 1e-3 and c.y + r <= arena.max_y + 1e-3,
				label + ": phase %d circle inside the map" % k)
	var final_c: Vector2 = z.centers[BrZone.PHASES]
	_check(z.radii[BrZone.PHASES] == 0.0 and final_c.x >= arena.min_x and final_c.x <= arena.max_x and final_c.y >= arena.min_y and final_c.y <= arena.max_y,
		label + ": final circle inside the map")
	_check(absf(z.final_time() - 455.0 * f) < 1e-6, label + ": final time")
	# Damage schedule.
	_check(z.dps_ratio_at(0.0) == 0.0 and z.dps_ratio_at(z.shrink_start[1] - 0.01) == 0.0, label + ": no damage while looting")
	for k in range(1, BrZone.PHASES + 1):
		var want: float = float(BrZone.SCHEDULE[k - 1][3])
		var t_last: float = (z.shrink_start[k + 1] - 0.01) if k < BrZone.PHASES else z.final_time() + 60.0
		_check(z.dps_ratio_at(z.shrink_start[k] + 0.01) == want and z.dps_ratio_at(t_last) == want, label + ": phase %d damage %.3f/s" % [k, want])
	# Scan: monotone radius, states, outside(), public view contract and no leak.
	var prev_r: float = INF
	var mono: bool = true
	var leak: bool = false
	var keys_ok: bool = true
	var states_ok: bool = true
	var outside_ok: bool = true
	var t: float = 0.0
	while t <= z.final_time() + 20.0:
		var r2: float = z.radius_at(t)
		mono = mono and r2 <= prev_r + 1e-6
		prev_r = r2
		var v: Dictionary = z.public_view(t)
		keys_ok = keys_ok and v.size() == VIEW_KEYS.size() and v.has_all(VIEW_KEYS)
		var k2: int = z.phase_at(t)
		var st: String = str(v.state)
		states_ok = states_ok and int(v.phase) == k2 and int(v.phases_total) == 6 and float(v.dps_ratio) == z.dps_ratio_at(t) \
			and v.center == z.center_at(t) and float(v.radius) == r2
		var target: int = 1 if st == "loot" else (k2 if st == "shrink" else (k2 + 1 if st == "wait" else -1))
		if bool(v.next_known):
			leak = leak or target < 1 or z.announce_at[target] > t or v.next_center != z.centers[target] or float(v.next_radius) != z.radii[target]
		else:
			leak = leak or v.next_center != v.center or float(v.next_radius) != float(v.radius)
			leak = leak or (target >= 1 and z.announce_at[target] <= t)
		if k2 > 0:
			var c2: Vector2 = z.center_at(t)
			outside_ok = outside_ok and z.outside(c2 + Vector2(r2 + 5.0, 0.0), t) and (r2 < 1.0 or not z.outside(c2, t))
		else:
			outside_ok = outside_ok and not z.outside(Vector2(arena.min_x, arena.min_y), t)
		t += 0.25
	_check(mono, label + ": radius never grows")
	_check(keys_ok, label + ": public_view has exactly the contract keys")
	_check(states_ok, label + ": public_view phase/state/circle/damage agree with the zone")
	_check(not leak, label + ": public_view never reveals a circle before its announce time")
	_check(outside_ok, label + ": outside() matches the circle")
	_check(z.state_at(1.0) == "loot" and z.state_at(z.shrink_start[2] + 1.0) == "shrink" and z.state_at(z.shrink_end[2] + 1.0) == "wait" and z.state_at(z.final_time() + 1.0) == "final",
		label + ": states loot/shrink/wait/final")
	_check(not bool(z.public_view(44.0 * f).next_known) and bool(z.public_view(45.0 * f + 0.01).next_known), label + ": phase 1 announced at 45 s x speed")
	var rows: Array = BrZone.schedule_rows(speed)
	_check(rows.size() == 6 and absf(float(rows[0].announce) - 45.0 * f) < 1e-6 and absf(float(rows[5].shrink_end) - 455.0 * f) < 1e-6, label + ": public schedule rows")
	if speed == "normal":
		_zone_differential(m, arena, z)
		if arena.has_gates():
			# A battle copy whose gates are open at t = 0 must give the same circles.
			var copy: Arena = arena.make_battle_copy()
			copy.apply_gate_bits(copy.all_gates_open_bits())
			var zc: BrZone = BrZone.new(copy, data, sv, speed)
			_check(zc.centers == z.centers and zc.radii == z.radii, label + ": circles do not depend on the gate state")


# Changing every circle from phase j on must not change anything public_view
# shows before phase j's announce time (and must show right after it).
func _zone_differential(m: Dictionary, arena: Arena, z: BrZone) -> void:
	var label: String = "%s/%d zone" % [m.id, int(m.seed)]
	for j in range(1, BrZone.PHASES + 1):
		var other: BrZone = BrZone.new(arena, m.data, int(m.seed), "normal")
		for k in range(j, BrZone.PHASES + 1):
			other.centers[k] = other.centers[k] + Vector2(53.0, -41.0)
			other.radii[k] = other.radii[k] * 0.97
		var same: bool = true
		var t: float = 0.0
		while t < z.announce_at[j]:
			same = same and z.public_view(t) == other.public_view(t)
			t += 0.25
		_check(same, label + ": nothing of phase %d is public before %.1f s" % [j, z.announce_at[j]])
		_check(z.public_view(z.announce_at[j] + 0.01) != other.public_view(z.announce_at[j] + 0.01), label + ": phase %d becomes public at its announce time" % j)


# ------------------------------------------------------------------ items

func _items(m: Dictionary) -> void:
	var data: Dictionary = m.data
	var sv: int = int(m.seed)
	var label: String = "%s/%d items" % [m.id, sv]
	var items: Array = BrItems.place(data, sv)
	_check(items.size() == 80, label + ": 80 items (%d)" % items.size())
	_check(var_to_str(items) == var_to_str(BrItems.place(data, sv)), label + ": deterministic")
	_check(var_to_str(items) != var_to_str(BrItems.place(data, sv + 1)), label + ": seed changes the placement")
	var spot_ring: Dictionary = {}
	for s: Dictionary in data.item_spots:
		spot_ring[Vector2(float(s.x), float(s.y))] = int(s.ring)
	var per_ring: Array = [0, 0, 0, 0]
	var hist: Array = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	var min_gap: float = INF
	var on_spots: bool = true
	var defs_ok: bool = true
	for i in items.size():
		var it: Dictionary = items[i]
		var p: Vector2 = it.pos
		on_spots = on_spots and spot_ring.has(p) and int(spot_ring[p]) == int(it.ring)
		defs_ok = defs_ok and ItemDefs.DEFS.has(str(it.item)) and ItemDefs.rarity_of(str(it.item)) == int(it.rarity)
		per_ring[int(it.ring)] += 1
		hist[int(it.ring)][int(it.rarity)] += 1
		for j in range(i + 1, items.size()):
			min_gap = minf(min_gap, p.distance_to(items[j].pos))
	_check(per_ring == [12, 20, 24, 24], label + ": ring counts 12/20/24/24 (%s)" % str(per_ring))
	_check(min_gap >= 150.0, label + ": items >= 150 px apart (min %.0f)" % min_gap)
	_check(on_spots, label + ": every item stands on an item spot of its ring")
	_check(defs_ok, label + ": item ids and rarities from ItemDefs")
	var means: Array = []
	for ring in 4:
		var n: int = int(per_ring[ring])
		var w: Array = BrItems.RING_WEIGHTS[ring]
		var total: float = 0.0
		for x in w:
			total += float(x)
		var sum: float = 0.0
		for r in 5:
			var expect: float = float(w[r]) / total * float(n)
			_check(absf(float(hist[ring][r]) - expect) < 1.0 + 1e-6, label + ": ring %d rarity %d count %d ~ %.2f" % [ring, r, int(hist[ring][r]), expect])
			sum += float(r) * float(hist[ring][r])
		means.append(sum / maxf(1.0, float(n)))
	_check(int(hist[3][4]) == 0, label + ": no legendary in the outer ring")
	_check(float(means[0]) > float(means[1]) and float(means[1]) > float(means[2]) and float(means[2]) > float(means[3]),
		label + ": mean rarity rises toward the centre %s" % str(means))
	var all: Dictionary = metrics.get("rarity_hist", {})
	all["%s/%d" % [m.id, sv]] = hist
	metrics["rarity_hist"] = all


func _items_aggregate(maps: Array) -> void:
	_check(BrItems.ring_counts(80) == [12, 20, 24, 24], "items: ring_counts(80)")
	var sum: int = 0
	for n in BrItems.ring_counts(37):
		sum += int(n)
	_check(sum == 37, "items: ring_counts scales to any total")
	_check(maps.size() == 9, "items: nine maps placed")


# ------------------------------------------------------------------ DB cache

func _db_cache() -> void:
	var ids: Array = BattlegroundMapData.ORDER
	var a0: Arena = DB.battleground_arena(str(ids[0]), 11)
	_check(a0 != null and a0.shared and str(a0.data.kind) == "battleground" and a0.id == "%s_11" % str(ids[0]), "db: battleground arena built and shared")
	_check(DB.battleground_arena(str(ids[0]), 11) == a0, "db: same preset and seed reuse the cached arena")
	var a1: Arena = DB.battleground_arena(str(ids[1]), 11)
	_check(DB.battleground_arena(str(ids[0]), 11) == a0, "db: two maps fit in the cache")
	var a2: Arena = DB.battleground_arena(str(ids[2]), 11)
	_check(DB.br_cache.size() == 2 and DB.br_cache_order.size() == 2, "db: cache keeps the 2 most recent maps")
	_check(DB.battleground_arena(str(ids[0]), 11) == a0 and DB.battleground_arena(str(ids[2]), 11) == a2, "db: recently used maps stay cached")
	_check(DB.battleground_arena(str(ids[1]), 11) != a1, "db: the least recently used map was evicted")
	var fallback: Arena = DB.battleground_arena("no_such_map", 5)
	_check(str(fallback.data.preset) == str(ids[0]), "db: unknown id falls back to the first preset")
