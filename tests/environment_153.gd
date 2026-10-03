extends SceneTree

# V1.5.3 environment engine: six new gimmicks (brush, artillery, gate, jump pad,
# closing ring, mud), navigation links and hazard weights, map-format support
# (default bounds, opening facing, fallback spawns) and the engine bug fixes
# (summon float stall, rift direction, borrowed-skill conditions).

var passed: int = 0
var failed: Array[String] = []

const L: = 37.4
const DT: = BattleSim.DT


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("ENVIRONMENT_153: " + label)


func near(a: float, b: float, label: String, tol: float = 0.0001) -> void:
	check(absf(a - b) <= tol, "%s (%.5f vs %.5f)" % [label, a, b])


func base_data(id: String, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "name": id, "width": 1408, "height": 792, "obstacles": [], "hazards": [],
		"spawns": {"blue": [{"x": 165, "y": 396}, {"x": 198, "y": 273}, {"x": 198, "y": 519}, {"x": 141, "y": 194}, {"x": 141, "y": 598}],
			"red": [{"x": 1243, "y": 396}, {"x": 1210, "y": 273}, {"x": 1210, "y": 519}, {"x": 1267, "y": 194}, {"x": 1267, "y": 598}]}}
	d.merge(extra, true)
	return d


func fresh(data: Dictionary, blue: Array = ["swordsman"], red: Array = ["archer"], seed_v: int = 153171) -> BattleSim:
	var sim: BattleSim = BattleSim.new({"blue": blue, "red": red, "arena_id": "classic", "seed": seed_v, "max_time": 150.0})
	sim.arena = Arena.from_data(data)
	sim.start()
	for u in sim.heroes:
		u.vel = Vector2.ZERO
	return sim


func place(u: BUnit, p: Vector2, prev: Vector2 = Vector2.INF) -> void:
	u.pos = p
	u.prev_pos = p if prev == Vector2.INF else prev
	u.vel = Vector2.ZERO


func at(sim: BattleSim, t: float, dt: float = DT) -> void:
	sim.time = t
	sim.env.update(dt)


func events(sim: BattleSim, type: String) -> Array:
	var out: Array = []
	for ev in sim.log:
		if str(ev.type) == type:
			out.append(ev)
	return out


func artillery_hazard(extra: Dictionary = {}) -> Dictionary:
	var h: Dictionary = {"id": "art", "type": "artillery", "shape": "rect", "x": 300.0, "y": 200.0, "w": 800.0, "h": 400.0,
		"period": 4.0, "warningDuration": 1.5, "phase": 0.0, "count": 3, "radius": 60.0, "damage": 50.0, "school": "true", "spread": 40.0}
	h.merge(extra, true)
	return h


func gate_wall_obstacles(period: float = 6.0, open_d: float = 3.0, warn: float = 1.0) -> Array:
	return [
		{"id": "wall_n", "shape": "rect", "x": 690.0, "y": L, "w": 28.0, "h": 300.0},
		{"id": "gate_mid", "shape": "rect", "x": 690.0, "y": L + 300.0, "w": 28.0, "h": 120.0,
			"gate": {"group": "A", "period": period, "openDuration": open_d, "warningDuration": warn, "phase": 0.0}},
		{"id": "wall_s", "shape": "rect", "x": 690.0, "y": L + 420.0, "w": 28.0, "h": 754.6 - L - 420.0},
	]


func ring_hazard(extra: Dictionary = {}) -> Dictionary:
	var h: Dictionary = {"id": "ring", "type": "closing_ring", "x": 704.0, "y": 396.0, "startTime": 1.0, "endTime": 3.0,
		"startRadius": 700.0, "endRadius": 120.0, "damagePercent": 5.0, "tickInterval": 0.5}
	h.merge(extra, true)
	return h


func _run() -> void:
	DB.ensure_loaded()
	var classic_before: String = var_to_str(DB.arena("classic").data)
	clock_contract()
	geometry_contract()
	helper_contract()
	artillery_contract()
	gate_contract()
	jump_pad_contract()
	ring_contract()
	mud_contract()
	toggle_contract()
	brush_contract()
	navigator_links()
	navigator_weights()
	navigator_unit_routes()
	artillery_warning_guard()
	bounds_and_spawns()
	engine_fixes()
	all_gimmick_determinism()
	# V1.5.3 review fixes (zz_work/review153_result.json, engine key).
	artillery_area_clamp()
	navigator_mirror_snap()
	navigator_env_switches()
	navigator_unreachable_goal()
	navigator_link_exits_order_free()
	pad_flight_completes()
	draft_rollout_warmup()
	map_cache_determinism()
	check(classic_before == var_to_str(DB.arena("classic").data), "tests leave the shared classic definition unchanged")
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"coverage": ["gimmick clocks", "effect geometry", "penalty and expected damage", "artillery telegraphs and seeded strikes",
			"gates: masks, push-out, projectile block, nav signature, shared copy", "jump pads incl. CC and flight over hazards",
			"closing ring", "mud slow", "per-type toggles", "brush concealment in elimination", "navigator portal / jump-pad links",
			"hazard cell weights", "link rim / periodic shortcuts", "unit-aware link waits", "salvos keep their full warning", "default bounds", "opening facing and fallback spawns", "summon stall, rift direction, borrowed conditions",
			"26-hero all-gimmick determinism", "artillery strikes stay inside their area (walls give no cover)",
			"mirror-consistent nav snapping", "navigator follows the environment switches", "unreachable goals hold at the partial path end",
			"link exits independent of build order", "jump-pad flights cannot be displaced", "draft rollout warms the grids it uses",
			"same-seed / cache-warm / interleaved determinism on gate, portal, pad, artillery and ring maps"]}
	var file: FileAccess = FileAccess.open("res://reports/environment_153.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("ENVIRONMENT_153 ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ clocks
func clock_contract() -> void:
	var art: Dictionary = artillery_hazard({"period": 6.0})
	check(not bool(Arena.hazard_clock(art, 4.4).warning), "artillery idle before telegraph window")
	check(bool(Arena.hazard_clock(art, 4.6).warning), "artillery warning while salvo is in the air")
	check(bool(Arena.hazard_clock(art, 6.1).active), "artillery impact flash at cycle start")
	check(not bool(Arena.hazard_clock(art, 6.4).active), "artillery flash is short")
	near(Arena.artillery_impact_time(art, 0), 6.0, "artillery cycle 0 impact")
	near(Arena.artillery_impact_time(art, 1), 12.0, "artillery cycle 1 impact")
	near(Arena.artillery_impact_time(artillery_hazard({"period": 6.0, "phase": 2.0}), 0), 4.0, "artillery phase shifts impact")
	var obstacles: Array = gate_wall_obstacles(8.0, 4.0, 1.0)
	obstacles.append({"id": "gate_b", "shape": "rect", "x": 200.0, "y": 100.0, "w": 60.0, "h": 20.0, "gate": {"group": "B", "period": 8.0, "openDuration": 4.0, "warningDuration": 1.0}})
	var a: Arena = Arena.from_data(base_data("env153_clock", {"obstacles": obstacles}))
	check(a.gates.size() == 2 and a.obs_gate[1] == 0 and a.obs_gate[3] == 1 and a.obs_gate[0] == -1, "gate slots derived from obstacle entries")
	check(a.gate_open_at(1, 1.0) and not a.gate_open_at(1, 5.0), "group A open first half")
	check(not a.gate_open_at(3, 1.0) and a.gate_open_at(3, 5.0), "group B alternates by half a period")
	check(not a.gate_open_at(0, 1.0), "static wall is never open")
	check(bool(Arena.gate_clock(a.gates[0], 3.5).warning) and not bool(Arena.gate_clock(a.gates[0], 2.0).warning), "gate warning is the last seconds before closing")
	near(float(Arena.hazard_clock(a.gates[0], 1.0).remaining), 3.0, "gate clock counts down to closing")
	check(a.gate_bits_at(3.0) == 1 and a.gate_bits_at(3.0, 1.5) == 0 and a.gate_bits_at(5.0) == 2, "gate bits with closing margin")
	check(a.gate_bits == 0 and a.obs_mask[1] == 7, "authored gate starts as a wall")
	var ring: Dictionary = ring_hazard()
	near(Arena.ring_radius_at(ring, 0.0), 700.0, "ring start radius before start")
	near(Arena.ring_radius_at(ring, 2.0), 410.0, "ring shrinks linearly")
	near(Arena.ring_radius_at(ring, 9.0), 120.0, "ring holds final radius")
	check(bool(Arena.hazard_clock(ring, 0.5).warning) and not bool(Arena.hazard_clock(ring, 0.5).active), "ring countdown warning before start")
	check(bool(Arena.hazard_clock(ring, 1.5).active), "ring active after start")
	for type in ["jump_pad", "mud"]:
		check(bool(Arena.hazard_clock({"type": type}, 13.3).active), type + " is always active")


func geometry_contract() -> void:
	var centred: Dictionary = ring_hazard()
	centred.erase("x")
	centred.erase("y")
	var a: Arena = Arena.from_data(base_data("env153_geo", {"hazards": [centred]}))
	var ring: Dictionary = a.hazards[0]
	check((ring.center as Vector2).distance_to(a.center()) < 0.01, "ring centre defaults to arena centre")
	ring = Arena.from_data(base_data("env153_geo2", {"hazards": [ring_hazard()]})).hazards[0]
	check(not Arena.hazard_effect_contains(ring, Vector2(1300, 396), 0.5), "ring harmless before start")
	check(Arena.hazard_effect_contains(ring, Vector2(1300, 396), 1.5), "ring hurts outside after start")
	check(not Arena.hazard_effect_contains(ring, Vector2(704, 396), 9.0), "ring centre stays safe")
	check(Arena.hazard_effect_contains(ring, Vector2(704 + 110, 396), 9.0, 20.0), "ring padding widens the outside")
	var mud: Dictionary = {"type": "mud", "shape": "circle", "x": 600.0, "y": 400.0, "radius": 100.0}
	check(Arena.hazard_effect_contains(mud, Vector2(690, 400), 0.0) and not Arena.hazard_effect_contains(mud, Vector2(710, 400), 0.0), "mud uses its authored shape")


func helper_contract() -> void:
	var obstacles: Array = gate_wall_obstacles(6.0, 3.0, 1.0)
	var data: Dictionary = base_data("env153_helpers", {"obstacles": obstacles, "hazards": [ring_hazard({"startTime": 100.0, "endTime": 102.0}),
		{"id": "mud", "type": "mud", "shape": "circle", "x": 400.0, "y": 600.0, "radius": 60.0, "slow": 0.4},
		artillery_hazard({"x": 900.0, "y": 100.0, "w": 300.0, "h": 200.0})]})
	var a: Arena = Arena.from_data(data)
	check(a.hazard_penalty(Vector2(1300, 396), 101.0) >= 1.5, "outside the ring carries a high penalty")
	near(a.hazard_penalty(Vector2(704 + 600, 396), 90.0), 0.0, "ring penalty zero long before start")
	check(absf(a.hazard_penalty(Vector2(704 + 380, 396), 100.1) - 0.35) < 1e-6, "soon-outside ring zone asks to leave early")
	near(a.hazard_penalty(Vector2(400, 600), 0.2), 0.08, "mud is a mild steering cost")
	near(a.hazard_penalty(Vector2(400, 600), 0.2, 0.0, Arena.type_bit("mud")), 0.0, "skip mask excludes disabled types")
	var in_gate: Vector2 = Vector2(704, L + 360.0)
	near(a.gate_penalty(in_gate, 0.5), 0.0, "open gate frame is free")
	near(a.gate_penalty(in_gate, 2.5), 0.9, "closing gate frame should be left")
	near(a.gate_penalty(in_gate, 4.0), 2.0, "closed gate frame is a wall")
	var ticks: float = Arena.ring_expected_ticks(a.hazards[0], Vector2(1300, 396), 101.0, 1.0)
	near(ticks, 3.0, "ring forecast counts tick intervals")
	near(a.expected_hazard_damage(Vector2(1300, 396), 101.0, 0.0, 1.0, 0, 800.0), 3.0 * 0.05 * 800.0, "ring expected damage uses max HP percentage")
	check(a.expected_hazard_damage(Vector2(1000, 200), 1.0, 18.0, 3.0) > 0.0, "unannounced salvo inside the area has expected damage")
	near(a.expected_hazard_damage(Vector2(600, 200), 1.0, 18.0, 3.0), 0.0, "no artillery expectation outside its area")
	near(Arena.artillery_expected(a.hazards[2], Vector2(1000, 200), 3.0, 18.0, 0.9), 0.0, "announced salvo is left to public telegraphs")
	near(Arena.ring_damage_fraction({"damagePercent": 5.0}), 0.05, "damagePercent is a percentage of max HP")
	near(Arena.ring_damage_fraction({"damagePercent": 0.5}), 0.005, "fractional percentages stay percentages")


# ------------------------------------------------------------------ artillery
func _salvo_points(seed_v: int) -> String:
	var sim: BattleSim = fresh(base_data("env153_art_seed", {"hazards": [artillery_hazard()]}), ["swordsman"], ["archer"], seed_v)
	place(sim.heroes[0], Vector2(500, 400))
	place(sim.heroes[1], Vector2(900, 400))
	at(sim, 2.55)
	var pts: Array = []
	for s in sim.env.artillery_state():
		pts.append(s.pos)
	sim.dispose()
	return var_to_str(pts)


func artillery_contract() -> void:
	var sim: BattleSim = fresh(base_data("env153_art", {"hazards": [artillery_hazard()]}))
	var a: BUnit = sim.heroes[0]
	var b: BUnit = sim.heroes[1]
	place(a, Vector2(500, 400))
	place(b, Vector2(900, 400))
	var hp_a: float = a.hp
	var hp_b: float = b.hp
	at(sim, 2.4)
	check(sim.env.artillery_state().is_empty() and sim.telegraphs.is_empty(), "no salvo before telegraph time")
	at(sim, 2.5 + 0.01)
	var state: Array = sim.env.artillery_state()
	check(state.size() == 3, "salvo announces count strikes")
	var ok_rows: bool = true
	for row in state:
		ok_rows = ok_rows and row.has("id") and row.has("pos") and row.has("radius") and absf(float(row.impact_t) - 4.0) < 1e-6 and absf(float(row.warn_t) - 2.51) < 1e-6
		ok_rows = ok_rows and ((row.pos as Vector2).distance_to(a.pos) <= 40.5 or (row.pos as Vector2).distance_to(b.pos) <= 40.5)
	check(ok_rows, "artillery_state rows aim at heroes inside the area within spread")
	var env_tg: Array = []
	for tg in sim.telegraphs:
		if int(tg.source) == -1 and int(tg.team) == -1:
			env_tg.append(tg)
	check(env_tg.size() == 3, "public telegraphs pushed with source -1 and team -1")
	var shape_ok: bool = true
	for tg in env_tg:
		for key in ["id", "source", "team", "shape", "from", "to", "radius", "width", "range", "angle", "start", "end", "ability", "action_id", "cancelled", "dmg"]:
			shape_ok = shape_ok and tg.has(key)
		shape_ok = shape_ok and str(tg.shape) == "circle" and absf(float(tg.end) - 4.0) < 1e-6 and float(tg.dmg) == 50.0
	check(shape_ok, "telegraph dictionary matches BattleSim.add_telegraph shape")
	check(events(sim, "ENV_ARTILLERY").size() == 1, "salvo announcement logged once")
	var strike: Vector2 = state[0].pos
	check(sim.env.hazard_penalty(strike, 2.9, 18.0) > 1.0, "announced strike circle is a steering penalty")
	check(sim.env.expected_hazard_damage(strike, 2.6, 18.0, 2.0) >= 50.0, "announced strike counts in expected damage")
	# The AI reads environment telegraphs through its normal telegraph path.
	var brain: TacticianBrain = TacticianBrain.new(sim, 0)
	brain.on_start(sim)
	brain.pre_tick(sim)
	var seen: int = 0
	for tg in brain.intel.telegraphs:
		if str(tg.shape) == "circle" and absf(float(tg.due) - 4.0) < 1e-6:
			seen += 1
	check(seen >= 1, "team intel lists visible artillery telegraphs")
	var in_circle: bool = false
	for row in state:
		in_circle = in_circle or (row.pos as Vector2).distance_to(a.pos) <= 60.0 + sim.radius(a)
	if in_circle:
		check(brain._dodge_vector(a).length() > 0.0, "existing dodge code reacts to an artillery telegraph")
	var expected_a: float = 0.0
	var expected_b: float = 0.0
	for row in state:
		if a.pos.distance_to(row.pos) <= 60.0 + sim.radius(a) * 0.3:
			expected_a += 50.0
		if b.pos.distance_to(row.pos) <= 60.0 + sim.radius(b) * 0.3:
			expected_b += 50.0
	at(sim, 3.99)
	check(a.hp == hp_a and b.hp == hp_b, "no damage before impact")
	at(sim, 4.0)
	near(hp_a - a.hp, expected_a, "strikes hit once each (hero A)")
	near(hp_b - b.hp, expected_b, "strikes hit once each (hero B)")
	check(expected_a + expected_b > 0.0, "a salvo aimed at heroes lands on them")
	check(sim.env.artillery_state().is_empty() and events(sim, "ENV_STRIKE").size() == 3, "impacts resolved and logged")
	var hits_ok: bool = true
	for ev in events(sim, "ENV_HIT"):
		hits_ok = hits_ok and str(ev.hazard) == "art" and str(ev.hazard_type) == "artillery"
	check(hits_ok, "artillery ENV_HIT carries hazard id and type")
	var hp_after: float = a.hp
	at(sim, 4.3)
	check(a.hp == hp_after, "a strike never hits twice")
	sim.dispose()
	check(_salvo_points(153999) == _salvo_points(153999), "same seed draws identical strike points")
	check(_salvo_points(153999) != _salvo_points(154000), "another seed draws different strike points")
	var empty: BattleSim = fresh(base_data("env153_art_empty", {"hazards": [artillery_hazard({"spread": 0.0})]}))
	place(empty.heroes[0], Vector2(100, 100))
	place(empty.heroes[1], Vector2(1300, 700))
	var rng_state: int = empty.rng.state
	at(empty, 2.6)
	var inside: bool = true
	for row in empty.env.artillery_state():
		inside = inside and Rect2(300, 200, 800, 400).grow(1.0).has_point(row.pos)
	check(inside and empty.env.artillery_state().size() == 3, "no hero inside: strikes uniform in the area")
	check(empty.rng.state == rng_state, "artillery never draws from sim.rng")
	empty.dispose()


# ------------------------------------------------------------------ gates
func _gate_projectile(gate_on: bool) -> float:
	var sim: BattleSim = fresh(base_data("env153_gate_proj", {"obstacles": gate_wall_obstacles(6.0, 3.0, 1.0)}))
	if not gate_on:
		sim.env.set_type_enabled("gate", false)
	var s: BUnit = sim.heroes[1]
	var t: BUnit = sim.heroes[0]
	place(s, Vector2(400, L + 360.0))
	place(t, Vector2(1000, L + 360.0))
	sim.time = 2.5
	sim.env.update(DT)
	var pa: = Defs.AbilityDef.new()
	pa.speed = 460.0
	pa.range = 900.0
	pa.width = 9.0
	pa.id = "basic"
	var ctx: Dictionary = sim.context(s, null, {"source_type": "BASIC_ATTACK", "basic": true, "snapshot": true})
	sim.proj.spawn(s, t, t.pos, pa, [{"type": "damage", "school": "true", "base": 60.0, "frozen": true}], ctx, {"basic": true, "prefrozen": true})
	var hp: float = t.hp
	for i in 60:
		sim.step()
	var dealt: float = hp - t.hp
	sim.dispose()
	return dealt


func gate_contract() -> void:
	var data: Dictionary = base_data("env153_gate", {"obstacles": gate_wall_obstacles(6.0, 3.0, 1.0)})
	var shared: Arena = Arena.from_data(data)
	shared.shared = true
	var authored: String = var_to_str(shared.obs_mask)
	var sim: BattleSim = BattleSim.new({"blue": ["swordsman", "mage"], "red": ["archer"], "arena_id": "classic", "seed": 153201})
	sim.arena = shared
	check(sim.arena != shared and sim.arena.battle_copy and not sim.arena.shared, "assigning a shared gated arena stores a private battle copy")
	sim.start()
	var a: Arena = sim.arena
	var gate_i: int = 1
	check(a.obs_mask[gate_i] == 0 and a.gate_slot_open(0), "gate opens at battle start (t=0 schedule)")
	var left: Vector2 = Vector2(600, L + 360.0)
	var right: Vector2 = Vector2(820, L + 360.0)
	at(sim, 0.5)
	check(a.line_of_sight(left, right) and a.terrain_contact(left, right, 4.0, true).is_empty(), "open gate blocks neither vision nor projectiles")
	var n_open: Navigator = Navigator.get_for(a, 18.0)
	check(n_open.path_length(Vector2(300, 400), Vector2(1100, 400), 18.0) < 1000.0, "navigator routes through an open gate")
	var wall_open: float = a.distance_to_wall(Vector2(704, L + 360.0))
	at(sim, 1.6)
	check(a.obs_mask[gate_i] == 0 and a.nav_sig == 0, "gate closing within 1.5 s is closed for navigation only")
	var n_closing: Navigator = Navigator.get_for(a, 18.0)
	check(n_closing != n_open and n_closing.path_length(Vector2(300, 400), Vector2(1100, 400), 18.0) == INF, "closing-gate grid has no route (no fake partial length)")
	# Units standing in the gateway when it closes are pushed back to their side.
	var u: BUnit = sim.heroes[0]
	var w: BUnit = sim.heroes[1]
	place(u, Vector2(700, L + 350.0), Vector2(680, L + 350.0))
	place(w, Vector2(708, L + 380.0), Vector2(730, L + 380.0))
	at(sim, 3.0)
	check(a.obs_mask[gate_i] == 7 and not a.gate_slot_open(0), "gate closes on schedule")
	check(u.pos.x <= 690.0 - sim.radius(u) + 0.01 and not a.inside_obstacle(u.pos, sim.radius(u) - 0.05), "unit pushed out to its previous (left) side")
	check(w.pos.x >= 718.0 + sim.radius(w) - 0.01 and not a.inside_obstacle(w.pos, sim.radius(w) - 0.05), "unit pushed out to its previous (right) side")
	check(events(sim, "ENV_PUSHED").size() == 2 and events(sim, "ENV_GATE").size() == 1 and not bool(events(sim, "ENV_GATE")[0].open), "gate close and push-out events")
	check(not a.line_of_sight(left, right) and int(a.terrain_contact(left, right, 4.0, true).get("idx", -1)) == gate_i, "closed gate blocks vision and projectiles")
	check(a.distance_to_wall(Vector2(704, L + 360.0)) < wall_open, "wall queries are mask-aware")
	check(Navigator.get_for(a, 18.0).path_length(Vector2(300, 400), Vector2(1100, 400), 18.0) == INF, "closed gate grid has no route")
	at(sim, 6.0)
	check(a.obs_mask[gate_i] == 0 and events(sim, "ENV_GATE").size() == 2, "gate reopens next cycle")
	var rows: int = 0
	for row in sim.env.state_snapshot():
		if str(row.type) == "gate":
			rows += 1
			check(bool(row.open) and row.has("remaining") and str(row.group) == "A" and not row.has("target"), "gate snapshot row is public state")
	check(rows == 1, "one snapshot row per gate")
	check(var_to_str(shared.obs_mask) == authored and shared.gate_bits == 0, "shared arena masks never change")
	check(Navigator.get_for(shared, 18.0) != Navigator.get_for(a, 18.0), "shared and battle-copy navigator caches never mix")
	check(a.env_def("gate_mid").get("type", "") == "gate" and a.env_def("nope").is_empty(), "env_def resolves gate ids for ENV_* events")
	var sim2: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "classic", "seed": 153202})
	sim2.arena = shared
	sim2.start()
	check(sim2.arena != a, "each battle gets its own copy")
	check(Navigator.for_arena(sim2.arena, 18.0, 1) == Navigator.for_arena(a, 18.0, 1), "battle copies of one map share grids per gate signature")
	check(Navigator.for_arena(sim2.arena, 18.0, 1) != Navigator.for_arena(sim2.arena, 18.0, 0), "grids differ per gate signature")
	sim2.dispose()
	sim.dispose()
	check(_gate_projectile(false) > 0.0, "projectile passes when gates are switched off (open)")
	near(_gate_projectile(true), 0.0, "projectile in flight is blocked by a gate that closes")


# ------------------------------------------------------------------ jump pads
func jump_pad_contract() -> void:
	var data: Dictionary = base_data("env153_pad", {
		"obstacles": [{"id": "divider", "shape": "rect", "x": 690.0, "y": L, "w": 28.0, "h": 754.6 - L}],
		"hazards": [{"id": "pad_w", "type": "jump_pad", "shape": "circle", "x": 500.0, "y": 400.0, "radius": 30.0, "target": {"x": 900.0, "y": 400.0}, "flightTime": 0.6},
			{"id": "lava_e", "type": "lava", "shape": "circle", "x": 800.0, "y": 400.0, "radius": 40.0, "alwaysActive": true, "damage": 30.0, "tickInterval": 0.2, "school": "magic"}]})
	var sim: BattleSim = fresh(data)
	var u: BUnit = sim.heroes[0]
	place(u, Vector2(500, 400))
	place(sim.heroes[1], Vector2(1200, 700))
	var hp: float = u.hp
	sim.step()
	check(u.motion != null and u.motion.kind == "jump_pad" and u.motion.flight, "hero on a pad is launched in flight")
	check(events(sim, "ENV_JUMP").size() == 1 and str(events(sim, "ENV_JUMP")[0].hazard) == "pad_w", "ENV_JUMP carries the pad id")
	for i in 30:
		sim.step()
	check(u.motion == null and u.pos.distance_to(Vector2(900, 400)) < 2.0, "jump crosses the wall and lands on target")
	check(u.hp == hp, "flight passes over ground hazards")
	sim.dispose()
	sim = fresh(data)
	u = sim.heroes[0]
	place(u, Vector2(500, 400))
	sim.push_status(u, &"stun", u.idx, 5.0)
	for i in 5:
		sim.step()
	check(u.motion == null and u.pos.distance_to(Vector2(500, 400)) < 1.0 and events(sim, "ENV_JUMP").is_empty(), "stunned hero is not launched")
	sim.dispose()
	sim = fresh(data)
	sim.env.set_type_enabled("jump_pad", false)
	u = sim.heroes[0]
	place(u, Vector2(500, 400))
	sim.step()
	check(u.motion == null, "disabled pad type does not launch")
	sim.dispose()
	var a: Arena = Arena.from_data(data)
	var nav: Navigator = Navigator.get_for(a, 18.0)
	check(nav.links.size() == 1 and str(nav.links[0].kind) == "jump_pad", "jump pad becomes a one-way link")
	check(nav.direct_length(Vector2(300, 400), Vector2(1100, 400), 18.0) == INF, "divided map has no walking route")
	var via: float = nav.path_length(Vector2(300, 400), Vector2(1100, 400), 18.0)
	check(via < 800.0 and via > 300.0, "route through the pad has a finite link length (%.1f)" % via)
	check(nav.next_waypoint(Vector2(300, 400), Vector2(1100, 400), 18.0).distance_to(Vector2(500, 400)) < 1.0, "next waypoint heads to the pad")
	check(nav.path_length(Vector2(1100, 400), Vector2(300, 400), 18.0) == INF, "jump pad link is one-way")
	check(nav.path_length(Vector2(300, 400), Vector2(1100, 400), 18.0, 0.0, 0.0, 0.0, false) == INF, "use_links=false ignores pads")
	Navigator.forget(a)


# ------------------------------------------------------------------ closing ring
func ring_contract() -> void:
	var sim: BattleSim = fresh(base_data("env153_ring", {"hazards": [ring_hazard()]}))
	var a: BUnit = sim.heroes[0]
	var b: BUnit = sim.heroes[1]
	place(a, Vector2(704, 396))
	place(b, Vector2(1250, 396))
	var hp_a: float = a.hp
	for tick in range(1, 106):
		at(sim, float(tick) * DT)
		place(b, Vector2(1250, 396))
	var hits: Array = []
	for ev in events(sim, "ENV_HIT"):
		if int(ev.g) == b.idx and str(ev.hazard_type) == "closing_ring":
			hits.append(ev)
	check(hits.size() == 4, "ring ticks every interval outside (%d)" % hits.size())
	var amounts_ok: bool = true
	var spacing_ok: bool = true
	for i in hits.size():
		amounts_ok = amounts_ok and absf(float(hits[i].amount) - 0.05 * sim.max_hp(b)) < 1e-6 and str(hits[i].school) == "true"
		if i > 0:
			spacing_ok = spacing_ok and float(hits[i].t) - float(hits[i - 1].t) >= 0.5 - 1e-6
	check(amounts_ok and spacing_ok, "ring deals max-HP true damage per tick")
	check(float(hits[0].t) > 1.5 if not hits.is_empty() else false, "damage starts once the edge passes the unit")
	check(a.hp == hp_a, "inside the safe circle is harmless")
	var phases: Array = []
	for ev in events(sim, "ENV_RING"):
		phases.append(str(ev.phase))
	check(phases == ["shrink", "final"], "ring start and final events")
	var row_ok: bool = false
	for row in sim.env.state_snapshot():
		if str(row.type) == "closing_ring":
			row_ok = absf(float(row.safe_radius) - 120.0) < 1e-6 and float(row.final_radius) == 120.0
	check(row_ok, "ring snapshot exposes safe radius")
	sim.dispose()


# ------------------------------------------------------------------ mud
func mud_contract() -> void:
	var data: Dictionary = base_data("env153_mud", {"hazards": [{"id": "mud", "type": "mud", "shape": "circle", "x": 600.0, "y": 400.0, "radius": 120.0, "slow": 0.4}]})
	var sim: BattleSim = fresh(data)
	var u: BUnit = sim.heroes[0]
	place(u, Vector2(600, 400))
	var base: float = sim.stat(u, BattleSim.S_MS)
	for tick in range(1, 31):
		at(sim, float(tick) * DT)
	near(sim.stat(u, BattleSim.S_MS), base * 0.6, "mud slows by its authored amount")
	var applied: int = 0
	for ev in events(sim, "CC_APPLIED"):
		if int(ev.g) == u.idx:
			applied += 1
	check(applied == 1, "standing in mud refreshes silently (one CC_APPLIED)")
	sim.apply_status(sim.heroes[1], u, {"status": "slow", "duration": 3.0, "magnitude": 0.5})
	near(sim.stat(u, BattleSim.S_MS), base * 0.5, "strongest slow wins over mud")
	sim.dispose()
	sim = fresh(data)
	u = sim.heroes[0]
	place(u, Vector2(600, 400))
	base = sim.stat(u, BattleSim.S_MS)
	at(sim, 0.1)
	place(u, Vector2(100, 100))
	at(sim, 0.7)
	near(sim.stat(u, BattleSim.S_MS), base, "mud slow fades shortly after leaving")
	place(u, Vector2(600, 400))
	sim.push_status(u, &"unstoppable", u.idx, 3.0)
	at(sim, 0.8)
	near(sim.stat(u, BattleSim.S_MS), base, "unstoppable ignores mud")
	sim.dispose()
	var nav: Navigator = Navigator.for_arena(Arena.from_data(data), 18.0)
	var c: Vector2i = nav.cell_of(Vector2(600, 400))
	near(nav.weights[c.y * nav.cols + c.x], Navigator.W_MUD, "mud cells carry a x1.6 path weight")


# ------------------------------------------------------------------ toggles
func toggle_contract() -> void:
	var data: Dictionary = base_data("env153_toggle", {"obstacles": gate_wall_obstacles(6.0, 3.0, 1.0),
		"hazards": [ring_hazard(), artillery_hazard(), {"id": "mud", "type": "mud", "shape": "circle", "x": 400.0, "y": 650.0, "radius": 60.0, "slow": 0.4}]})
	var sim: BattleSim = fresh(data)
	check(sim.env.is_type_enabled("artillery") and sim.env.type_active("gate"), "all types enabled by default")
	place(sim.heroes[0], Vector2(500, 400))
	place(sim.heroes[1], Vector2(1300, 396))
	at(sim, 2.6)
	check(sim.env.artillery_state().size() == 3, "salvo pending before toggle")
	var pending: Array = []
	for tg in sim.telegraphs:
		pending.append(tg)
	sim.env.set_type_enabled("artillery", false)
	var cancelled: bool = not pending.is_empty()
	for tg in pending:
		cancelled = cancelled and bool(tg.cancelled)
	check(not sim.env.is_type_enabled("artillery") and sim.env.artillery_state().is_empty() and cancelled, "disabling artillery cancels pending strikes and telegraphs")
	at(sim, 4.0)
	check(events(sim, "ENV_STRIKE").is_empty(), "disabled artillery never strikes")
	sim.env.set_type_enabled("closing_ring", false)
	var hp: float = sim.heroes[1].hp
	at(sim, 5.0)
	check(sim.heroes[1].hp == hp, "disabled ring deals no damage")
	sim.env.set_type_enabled("closing_ring", true)
	at(sim, 5.6)
	check(sim.heroes[1].hp < hp, "re-enabled ring resumes")
	at(sim, 4.0 + 0.1)
	check(sim.arena.obs_mask[1] == 7, "gate closed by schedule")
	sim.env.set_type_enabled("gate", false)
	check(sim.arena.obs_mask[1] == 0 and sim.arena.nav_sig == sim.arena.all_gates_open_bits(), "disabled gates stand open for movement and navigation")
	sim.env.set_type_enabled("gate", true)
	check(sim.arena.obs_mask[1] == 7, "re-enabled gate follows the schedule again")
	sim.env.enabled = false
	check(sim.arena.obs_mask[1] == 0, "global environment switch opens gates")
	near(sim.env.hazard_penalty(Vector2(1300, 396), 5.0, 18.0), 0.0, "disabled environment has no AI penalty")
	var all_off: bool = true
	for row in sim.env.state_snapshot():
		all_off = all_off and not bool(row.enabled)
	check(all_off, "snapshot rows report disabled state")
	sim.dispose()


# ------------------------------------------------------------------ brush
func brush_contract() -> void:
	var data: Dictionary = base_data("env153_brush", {"forests": [{"x": 900.0, "y": 400.0, "radius": 90.0, "patch": 0}]})
	var sim: BattleSim = fresh(data)
	check(sim.ruleset == "elimination", "brush test runs in elimination")
	var seer: BUnit = sim.heroes[0]
	var hidden: BUnit = sim.heroes[1]
	place(seer, Vector2(600, 400))
	place(hidden, Vector2(900, 400))
	hidden.last_combat_time = -99.0
	check(not sim.observes(seer, hidden), "hero inside brush is hidden in elimination")
	sim._update_visibility()
	check(not sim.is_seen(0, hidden), "team vision excludes the hidden hero")
	sim.env.set_type_enabled("brush", false)
	check(sim.observes(seer, hidden), "brush toggle off reveals")
	sim.env.set_type_enabled("brush", true)
	place(seer, Vector2(870, 400))
	check(sim.observes(seer, hidden), "same patch sees inside")
	place(seer, Vector2(600, 400))
	hidden.last_combat_time = sim.time
	check(sim.observes(seer, hidden), "fighting reveals for a moment")
	sim.dispose()


# ------------------------------------------------------------------ navigation
func navigator_links() -> void:
	var data: Dictionary = base_data("env153_links", {
		"obstacles": [{"id": "divider", "shape": "rect", "x": 690.0, "y": L, "w": 28.0, "h": 620.0}],
		"hazards": [{"id": "pa", "type": "portal", "shape": "circle", "x": 500.0, "y": 150.0, "radius": 30.0, "pairId": "pb", "exitFacing": {"x": -1, "y": 0}},
			{"id": "pb", "type": "portal", "shape": "circle", "x": 900.0, "y": 150.0, "radius": 30.0, "pairId": "pa", "exitFacing": {"x": 1, "y": 0}}]})
	var a: Arena = Arena.from_data(data)
	var nav: Navigator = Navigator.get_for(a, 18.0)
	check(nav.links.size() == 2, "portal pair gives links in both directions")
	var start: Vector2 = Vector2(400, 150)
	var goal: Vector2 = Vector2(1000, 150)
	var direct: float = nav.direct_length(start, goal, 18.0)
	var k: int = nav.route_link(start, goal, 18.0)
	check(direct > 1000.0 and k >= 0 and str(nav.links[k].hazard) == "pa", "shorter portal route is chosen")
	check(nav.next_waypoint(start, goal, 18.0).distance_to(Vector2(500, 150)) < 1.0, "next waypoint is the portal entry")
	check(nav.route_point(start, goal, 18.0) == nav.next_waypoint(start, goal, 18.0), "route_point alias")
	var via: float = nav.path_length(start, goal, 18.0)
	check(via < 300.0, "path length via portal (%.1f)" % via)
	check(nav.route_link(start, goal, 18.0, 150.0, 20.0) == -1, "long portal cooldown wait prefers walking")
	check(nav.path_length(start, goal, 18.0, 0.0, 0.0, 0.0, false) == direct, "use_links=false keeps the direct length")
	var back: int = nav.route_link(goal, start, 18.0)
	check(back >= 0 and str(nav.links[back].hazard) == "pb", "reverse direction uses the pair")
	var sim: BattleSim = fresh(data)
	var tc: TeamController = TeamController.new(sim, 0)
	# Review 1.5.3: route_point has no unit to cost a link with (own cooldowns, switches),
	# so it walks; unit-aware routing goes through Navigator.unit_waypoint.
	check(tc.route_point(start, goal, 18.0).distance_to(Vector2(500, 150)) >= 1.0, "unit-less controller route_point walks instead of taking links")
	# Units walking past a portal do not shortcut through it.
	var p1: Vector2 = Vector2(400, 150)
	var p2: Vector2 = Vector2(600, 150)
	check(nav.clear(p1, p2, 18.0) and not nav.safe_clear(p1, p2, 18.0), "safe shortcut avoids crossing a portal")
	check(nav.route_link(p1, p2, 18.0) == -1, "short hop never uses the portal")
	var wp: Vector2 = nav.next_waypoint(p1, p2, 18.0)
	check(Arena.seg_circle_t(p1, wp, Vector2(500, 150), 30.0 + 5.4) < 0.0, "walking waypoint steers around the portal")
	sim.dispose()
	Navigator.forget(a)
	# Unreachable goals report INF instead of a partial-path length.
	var boxed: Arena = Arena.from_data(base_data("env153_box", {"obstacles": [
		{"id": "b1", "shape": "rect", "x": 1000.0, "y": 300.0, "w": 200.0, "h": 20.0}, {"id": "b2", "shape": "rect", "x": 1000.0, "y": 480.0, "w": 200.0, "h": 20.0},
		{"id": "b3", "shape": "rect", "x": 1000.0, "y": 300.0, "w": 20.0, "h": 200.0}, {"id": "b4", "shape": "rect", "x": 1180.0, "y": 300.0, "w": 20.0, "h": 200.0}]}))
	var nb: Navigator = Navigator.get_for(boxed, 18.0)
	check(nb.path_length(Vector2(300, 400), Vector2(1100, 400), 18.0) == INF, "enclosed goal has no fake path length")
	check(nb.path_points(Vector2(300, 400), Vector2(1100, 400)).size() >= 2, "partial path still available for approaching")
	Navigator.forget(boxed)


func navigator_weights() -> void:
	var data: Dictionary = base_data("env153_lava", {"hazards": [
		{"id": "lava", "type": "lava", "shape": "circle", "x": 700.0, "y": 400.0, "radius": 90.0, "alwaysActive": true, "damage": 30.0, "tickInterval": 0.25, "school": "magic"},
		{"id": "spk", "type": "spikes", "shape": "rect", "x": 300.0, "y": 600.0, "w": 80.0, "h": 60.0, "period": 4.0, "activeDuration": 1.0, "warningDuration": 1.0, "damage": 10.0}]})
	var a: Arena = Arena.from_data(data)
	var nav: Navigator = Navigator.get_for(a, 18.0)
	var start: Vector2 = Vector2(450, 400)
	var goal: Vector2 = Vector2(950, 400)
	check(nav.clear(start, goal, 18.0), "physical clear() is unchanged by hazards")
	check(not nav.safe_clear(start, goal, 18.0), "routing shortcut refuses to cross always-on lava")
	var wp: Vector2 = nav.next_waypoint(start, goal, 18.0)
	check(wp != goal and Arena.seg_circle_t(start, wp, Vector2(700, 400), 90.0) < 0.0, "waypoint goes around the lava")
	var pts: PackedVector2Array = nav.path_points(start, goal)
	var dry: bool = pts.size() >= 2
	for q in pts:
		dry = dry and q.distance_to(Vector2(700, 400)) > 90.0
	check(dry, "weighted A* path avoids lava cells")
	var c: Vector2i = nav.cell_of(Vector2(700, 400))
	near(nav.weights[c.y * nav.cols + c.x], Navigator.W_ALWAYS_DAMAGE, "always-on damage cells weigh x8")
	var s: Vector2i = nav.cell_of(Vector2(340, 630))
	near(nav.weights[s.y * nav.cols + s.x], Navigator.W_PERIODIC, "periodic hazard cells weigh x2.5")
	# Shortcut memo per (start cell, goal cell) is history independent.
	var twin_a: Arena = Arena.from_data(data)
	var twin_b: Arena = Arena.from_data(data)
	var na: Navigator = Navigator.get_for(twin_a, 18.0)
	var nb: Navigator = Navigator.get_for(twin_b, 18.0)
	var q_goal: Vector2 = Vector2(955, 395)
	nb.next_waypoint(Vector2(452, 402), q_goal, 18.0)
	nb.next_waypoint(Vector2(459, 409), q_goal, 17.4)
	var same: bool = true
	for q in [Vector2(455, 405), Vector2(460, 397), Vector2(450, 410)]:
		same = same and na.next_waypoint(q, q_goal, 18.0) == nb.next_waypoint(q, q_goal, 18.0)
	check(same, "waypoint memo never depends on earlier queries")
	Navigator.forget(twin_a)
	Navigator.forget(twin_b)
	# The live hero loop: a straight command through lava is routed around it.
	var sim: BattleSim = fresh(data)
	var tc: TeamController = TeamController.new(sim, 0)
	check(tc.route_point(start, goal, 18.0) != goal, "controller route_point avoids the lava shortcut")
	sim.dispose()
	Navigator.forget(a)


func navigator_unit_routes() -> void:
	var data: Dictionary = base_data("env153_unit_links", {
		"obstacles": [{"id": "divider", "shape": "rect", "x": 690.0, "y": L, "w": 28.0, "h": 620.0}],
		"hazards": [{"id": "pa", "type": "portal", "shape": "circle", "x": 500.0, "y": 150.0, "radius": 30.0, "pairId": "pb", "exitFacing": {"x": -1, "y": 0}},
			{"id": "pb", "type": "portal", "shape": "circle", "x": 900.0, "y": 150.0, "radius": 30.0, "pairId": "pa", "exitFacing": {"x": 1, "y": 0}},
			{"id": "spk", "type": "spikes", "shape": "rect", "x": 300.0, "y": 420.0, "w": 120.0, "h": 120.0, "period": 4.0, "activeDuration": 1.0, "warningDuration": 1.0, "damage": 10.0}]})
	var sim: BattleSim = fresh(data)
	var u: BUnit = sim.heroes[0]
	place(u, Vector2(400, 150))
	var goal: Vector2 = Vector2(1000, 150)
	var entry: Vector2 = Vector2(500, 150)
	check(Navigator.unit_waypoint(sim, u, goal).distance_to(entry) < 1.0, "unit route uses a ready portal")
	near(sim.env.portal_wait(u), 0.0, "portal wait is zero when ready")
	u.portal_until = sim.time + 30.0
	near(sim.env.portal_wait(u), 30.0, "portal wait reads the hero's own cooldown")
	check(Navigator.unit_waypoint(sim, u, goal).distance_to(entry) > 1.0, "a long own portal cooldown makes the hero walk")
	u.portal_until = 0.0
	sim.env.set_type_enabled("portal", false)
	check(Navigator.unit_waypoint(sim, u, goal).distance_to(entry) > 1.0 and Navigator.unit_path_length(sim, u, goal) > 1000.0, "switched-off portals are never routed through")
	sim.env.set_type_enabled("portal", true)
	check(Navigator.unit_path_length(sim, u, goal) < 400.0, "unit path length includes the link")
	u.pad_until = sim.time + 3.0
	near(sim.env.pad_wait(u), 3.0, "pad wait reads the hero's own pad cooldown")
	# Walking goals inside a portal trigger stop at its rim (audit B1).
	var nav: Navigator = Navigator.get_for(sim.arena, 18.0)
	var inside_goal: Vector2 = Vector2(505, 160)
	var wp: Vector2 = nav.next_waypoint(Vector2(420, 260), inside_goal, 18.0)
	check(wp.distance_to(entry) >= 30.0 + 18.0 * 0.28 + Navigator.LINK_RIM - 0.5, "goal inside a portal is pulled back to the rim (%.1f)" % wp.distance_to(entry))
	check(nav.outside_links(Vector2(505, 150), inside_goal, 18.0) == inside_goal, "a hero already in the trigger keeps its goal")
	check(nav.outside_links(Vector2(420, 260), Vector2(600, 300), 18.0) == Vector2(600, 300), "goals away from links are unchanged")
	# Straight shortcuts keep clear of periodic damage unless an end is inside.
	check(nav.clear(Vector2(250, 480), Vector2(470, 480), 18.0) and not nav.safe_clear(Vector2(250, 480), Vector2(470, 480), 18.0), "shortcut does not cut across spikes")
	check(nav.safe_clear(Vector2(360, 480), Vector2(470, 480), 18.0), "leaving a periodic hazard is allowed")
	var around: Vector2 = nav.next_waypoint(Vector2(250, 480), Vector2(470, 480), 18.0)
	check(around != Vector2(470, 480) and Arena.seg_rect(Vector2(250, 480), around, 300.0, 420.0, 120.0, 120.0, 0.0).x < 0.0, "walking waypoint rounds the spikes")
	sim.dispose()
	# Forgetting a shared map also drops the grids its battle copies share.
	var gated: Arena = Arena.from_data(base_data("env153_forget", {"obstacles": gate_wall_obstacles()}))
	gated.shared = true
	var copy: Arena = gated.make_battle_copy()
	var g1: Navigator = Navigator.for_arena(copy, 18.0, 1)
	check(Navigator.for_arena(copy, 18.0, 1) == g1, "copy grid cached")
	Navigator.forget(gated)
	check(Navigator.for_arena(copy, 18.0, 1) != g1, "forget(shared) drops the copies' grids")
	Navigator.forget(copy)
	check(gated.spawn_centroid(0).distance_to(Vector2(168.6, 396.0)) < 0.5 and gated.spawn_centroid(1).x > 1200.0, "Arena.spawn_centroid for painters")


func artillery_warning_guard() -> void:
	# Phase 3: cycle 0 would be announced at -0.5 s (before the battle): skipped.
	var sim: BattleSim = fresh(base_data("env153_art_guard", {"hazards": [artillery_hazard({"phase": 3.0})]}))
	place(sim.heroes[0], Vector2(500, 400))
	place(sim.heroes[1], Vector2(900, 400))
	at(sim, 0.0)
	at(sim, 0.9)
	check(sim.env.artillery_state().is_empty() and events(sim, "ENV_STRIKE").is_empty(), "no surprise salvo at battle start")
	at(sim, 3.51)
	check(sim.env.artillery_state().size() == 3 and absf(float(sim.env.artillery_state()[0].impact_t) - 5.0) < 1e-6, "next salvo keeps its full warning")
	sim.dispose()
	# A salvo missed while the type was switched off is skipped, not fired late.
	sim = fresh(base_data("env153_art_guard2", {"hazards": [artillery_hazard()]}))
	place(sim.heroes[0], Vector2(500, 400))
	place(sim.heroes[1], Vector2(900, 400))
	sim.env.set_type_enabled("artillery", false)
	at(sim, 2.6)
	sim.env.set_type_enabled("artillery", true)
	at(sim, 3.5)
	check(sim.env.artillery_state().is_empty(), "late re-enable does not fire a short-warning salvo")
	at(sim, 4.2)
	check(events(sim, "ENV_STRIKE").is_empty(), "skipped salvo never lands")
	at(sim, 6.51)
	check(sim.env.artillery_state().size() == 3, "following salvo announced normally")
	sim.dispose()


# ------------------------------------------------------------------ bounds, facing, spawns
func bounds_and_spawns() -> void:
	var legacy: Arena = Arena.from_data({"id": "env153_legacy"})
	near(legacy.min_x, 37.4, "legacy default minX")
	near(legacy.max_x, 1370.6, "legacy default maxX")
	near(legacy.max_y, 754.6, "legacy default maxY")
	var square: Arena = Arena.from_data({"id": "env153_square", "width": 1100, "height": 1100})
	var m: float = 37.4 * 1100.0 / 792.0
	near(square.min_x, m, "square map margin scales with its short side")
	near(square.max_x, 1100.0 - m, "square map maxX derived from width")
	near(square.max_y, 1100.0 - m, "square map maxY derived from height")
	var explicit: Arena = Arena.from_data({"id": "env153_explicit", "width": 1800, "height": 700, "bounds": {"minX": 10, "maxX": 1790, "minY": 20, "maxY": 680}})
	check(explicit.min_x == 10.0 and explicit.max_y == 680.0, "explicit bounds win")
	var vertical: Dictionary = base_data("env153_vertical", {"width": 1100, "height": 1100, "spawns": {
		"blue": [{"x": 550, "y": 150}, {"x": 450, "y": 170}, {"x": 650, "y": 170}, {"x": 350, "y": 190}, {"x": 750, "y": 190}],
		"red": [{"x": 550, "y": 950}, {"x": 450, "y": 930}, {"x": 650, "y": 930}, {"x": 350, "y": 910}, {"x": 750, "y": 910}]}})
	var arena: Arena = Arena.from_data(vertical)
	DB.arena_by_id["env153_vertical"] = arena
	var sim: BattleSim = BattleSim.new({"arena_id": "env153_vertical", "blue": ["swordsman", "archer", "mage", "giant", "pirate", "joker", "hermes"], "red": ["sniper"], "seed": 153301})
	var red_c: Vector2 = Vector2(550, 950)
	var facing_ok: bool = true
	for u in sim.heroes:
		if u.team == 0:
			facing_ok = facing_ok and u.facing.dot((sim.spawn_centroid(1) - u.pos).normalized()) > 0.999
	check(facing_ok, "opening facing points at the enemy spawn centroid (top vs bottom)")
	check(sim.heroes[7].facing.dot(Vector2.UP) > 0.95, "red faces up toward blue")
	check(sim.spawn_centroid(1).distance_to(Vector2(550, 926)) < 0.01 and red_c.y > 900.0, "spawn centroid helper")
	var own: Vector2 = sim.spawn_centroid(0)
	var extra_ok: bool = true
	for i in [5, 6]:
		var p: Vector2 = sim.heroes[i].pos
		extra_ok = extra_ok and p.distance_to(own) < 420.0 and absf(p.y - own.y) < 40.0 and p.x > 200.0
	check(extra_ok, "fallback spawns line up across the own spawn centroid")
	near(sim.spawn_facing(0, Vector2(550, 150)).y, 1.0, "spawn_facing helper for respawns", 0.01)
	sim.dispose()
	DB.arena_by_id.erase("env153_vertical")
	var classic: BattleSim = BattleSim.new({"arena_id": "classic", "blue": ["swordsman"], "red": ["archer"], "seed": 1})
	check(classic.heroes[0].facing.x > 0.95 and classic.heroes[1].facing.x < -0.95, "left-right maps still open facing each other")
	classic.dispose()


# ------------------------------------------------------------------ engine fixes
class Idle:
	extends TeamController
	func decide(u: BUnit) -> void:
		u.next_decision_at = sim.time + 10.0
		u.command = {}


func engine_fixes() -> void:
	# Summon float stall (kits.update_entities): parasites must reach and bite.
	var sim: BattleSim = fresh(base_data("env153_summon"), ["hive_mind"], ["archer"], 152501)
	var h: BUnit = sim.heroes[0]
	var e: BUnit = sim.heroes[1]
	place(h, Vector2(400, 400))
	place(e, Vector2(700, 404))
	sim.controllers = [Idle.new(sim, 0), Idle.new(sim, 1)]
	check(sim.start_ability(h, 1, h, h.pos), "hive casts its parasites")
	var spawned: int = 0
	var bites: int = 0
	for i in 200:
		sim.step()
		for ev in sim.tick_events:
			if str(ev.type) == "SUMMON_CREATED":
				spawned += 1
			elif str(ev.type) == "SUMMON_CONSUMED":
				bites += 1
	check(spawned >= 1 and bites == spawned, "melee summons close the float gap and bite (spawned %d, bites %d)" % [spawned, bites])
	sim.dispose()
	# Dimensional rift opens toward the commanded point, not the facing.
	for aim_dir in [Vector2.RIGHT, Vector2.UP]:
		var rs: BattleSim = fresh(base_data("env153_rift"), ["dimensionalist"], ["archer"], 152501)
		var d: BUnit = rs.heroes[0]
		place(d, Vector2(600, 400))
		place(rs.heroes[1], Vector2(1200, 700))
		rs.controllers = [Idle.new(rs, 0), Idle.new(rs, 1)]
		d.facing = Vector2.LEFT
		var started: bool = rs.start_ability(d, 0, d, d.pos + aim_dir * 60.0)
		var center: Vector2 = Vector2.INF
		for i in 12:
			rs.step()
			for ev in rs.tick_events:
				if str(ev.type) == "ZONE_SPAWNED" and str(ev.get("kind", "")) == "rift":
					center = ev.pos
		check(started and center.is_finite() and (center - Vector2(600, 400)).normalized().dot(aim_dir) > 0.99, "rift opens toward the aim %s" % str(aim_dir))
		rs.dispose()
	var rf: BattleSim = fresh(base_data("env153_rift2"), ["dimensionalist"], ["archer"], 152501)
	var d2: BUnit = rf.heroes[0]
	place(d2, Vector2(600, 400))
	rf.controllers = [Idle.new(rf, 0), Idle.new(rf, 1)]
	d2.facing = Vector2.DOWN
	rf.start_ability(d2, 0, d2, d2.pos)
	var c2: Vector2 = Vector2.INF
	for i in 12:
		rf.step()
		for ev in rf.tick_events:
			if str(ev.type) == "ZONE_SPAWNED" and str(ev.get("kind", "")) == "rift":
				c2 = ev.pos
	check(c2.is_finite() and (c2 - Vector2(600, 400)).normalized().dot(Vector2.DOWN) > 0.99, "rift without an aim keeps the facing")
	rf.dispose()
	# Borrowed skill keeps its own condition (hermes borrowing nitro's wall ignition).
	var bs: BattleSim = fresh(base_data("env153_borrow"), ["hermes", "nitro"], ["sniper"], 153908)
	var hm: BUnit = bs.heroes[0]
	var nt: BUnit = bs.heroes[1]
	place(hm, Vector2(600, 400))
	var wall_ability: Defs.AbilityDef = null
	for ab in nt.def.abilities:
		if ab.condition.get("nearWall", false):
			wall_ability = ab
	check(wall_ability != null, "nitro has a near-wall ability")
	if wall_ability:
		hm.ks.borrowed = {"id": 777001, "owner": nt.idx, "ability": wall_ability, "expires": bs.time + 24.0}
		var list: Array = bs.ability_list(hm)
		var borrowed: Defs.AbilityDef = null
		for ab in list:
			if ab.virtual_kind == "borrow":
				borrowed = ab
		check(borrowed != null and not bs.kits.virtual_ready(hm, borrowed), "borrowed near-wall skill is not ready away from walls")
		place(hm, Vector2(L + bs.radius(hm) + 1.0, 400))
		check(borrowed != null and bs.kits.virtual_ready(hm, borrowed), "borrowed near-wall skill is ready at a wall")
	bs.dispose()


# ------------------------------------------------------------------ determinism
func all_gimmick_data() -> Dictionary:
	var obstacles: Array = [
		{"id": "div_n", "shape": "rect", "x": 690.0, "y": L, "w": 28.0, "h": 220.0},
		{"id": "gate_n", "shape": "rect", "x": 690.0, "y": L + 220.0, "w": 28.0, "h": 90.0, "gate": {"group": "A", "period": 8.0, "openDuration": 4.0, "warningDuration": 1.2}},
		{"id": "gate_s", "shape": "rect", "x": 690.0, "y": 754.6 - 310.0, "w": 28.0, "h": 90.0, "gate": {"group": "B", "period": 8.0, "openDuration": 4.0, "warningDuration": 1.2}},
		{"id": "div_s", "shape": "rect", "x": 690.0, "y": 754.6 - 220.0, "w": 28.0, "h": 220.0},
		{"id": "div_mid", "shape": "rect", "x": 690.0, "y": L + 310.0, "w": 28.0, "h": 754.6 - L - 620.0},
	]
	var hazards: Array = [
		artillery_hazard({"id": "plaza_art", "x": 520.0, "y": 280.0, "w": 368.0, "h": 232.0, "period": 5.0, "warningDuration": 1.4, "phase": 1.0, "damage": 30.0, "school": "magic"}),
		{"id": "pad_w", "type": "jump_pad", "shape": "circle", "x": 420.0, "y": 396.0, "radius": 26.0, "target": {"x": 820.0, "y": 150.0}, "flightTime": 0.7},
		{"id": "pad_e", "type": "jump_pad", "shape": "circle", "x": 988.0, "y": 396.0, "radius": 26.0, "target": {"x": 588.0, "y": 642.0}, "flightTime": 0.7},
		ring_hazard({"id": "ring", "startTime": 4.0, "endTime": 12.0, "startRadius": 820.0, "endRadius": 260.0, "damagePercent": 3.0, "tickInterval": 0.5}),
		{"id": "mud_w", "type": "mud", "shape": "rect", "x": 300.0, "y": 560.0, "w": 160.0, "h": 90.0, "slow": 0.35},
		{"id": "mud_e", "type": "mud", "shape": "rect", "x": 948.0, "y": 142.0, "w": 160.0, "h": 90.0, "slow": 0.35},
		{"id": "portal_w", "type": "portal", "shape": "circle", "x": 360.0, "y": 150.0, "radius": 28.0, "pairId": "portal_e"},
		{"id": "portal_e", "type": "portal", "shape": "circle", "x": 1048.0, "y": 642.0, "radius": 28.0, "pairId": "portal_w"},
		{"id": "lava_c", "type": "lava", "shape": "circle", "x": 560.0, "y": 150.0, "radius": 36.0, "alwaysActive": true, "damage": 18.0, "tickInterval": 0.3, "school": "magic"},
	]
	var forests: Array = [{"x": 250.0, "y": 300.0, "radius": 70.0, "patch": 0}, {"x": 1158.0, "y": 492.0, "radius": 70.0, "patch": 1}]
	return base_data("env153_all", {"obstacles": obstacles, "hazards": hazards, "forests": forests})


func _all_gimmick_run(seed_v: int, ids: Array) -> Dictionary:
	var sim: BattleSim = BattleSim.new({"arena_id": "env153_all", "blue": ids.slice(0, 13), "red": ids.slice(13, 26), "seed": seed_v, "max_time": 150.0})
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	var stuck: int = 0
	for i in 420:
		if not sim.step():
			break
		for u in sim.heroes:
			if u.alive and u.motion == null and u.chamber == "" and sim.arena.inside_obstacle(u.pos, sim.radius(u) - 1.5):
				stuck += 1
	var rows: Array = []
	for u in sim.heroes:
		rows.append([u.id, u.alive, u.hp, u.pos])
	var counts: Dictionary = {}
	var tagged: bool = true
	for ev in sim.log:
		var t: String = str(ev.type)
		if t.begins_with("ENV_"):
			counts[t] = int(counts.get(t, 0)) + 1
			tagged = tagged and str(ev.get("hazard", "")) != "" and str(ev.get("hazard_type", "")) != ""
	var copy: bool = sim.arena.battle_copy
	var strikes: Array = []
	for ev in sim.log:
		if str(ev.type) == "ENV_ARTILLERY":
			strikes.append(ev.points)
	var finite: bool = true
	for u in sim.heroes:
		finite = finite and u.pos.is_finite() and is_finite(u.hp)
	var out: Dictionary = {"signature": var_to_str([sim.tick, rows, counts, strikes, sim.log.size()]), "counts": counts, "tagged": tagged,
		"copy": copy, "stuck": stuck, "finite": finite, "strikes": var_to_str(strikes)}
	sim.dispose()
	return out


func all_gimmick_determinism() -> void:
	var ids: Array = DB.ids()
	check(ids.size() == 26, "26-hero roster")
	var shared: Arena = Arena.from_data(all_gimmick_data())
	shared.shared = true
	var authored: String = var_to_str(shared.obs_mask)
	DB.arena_by_id["env153_all"] = shared
	var a: Dictionary = _all_gimmick_run(153153, ids)
	var b: Dictionary = _all_gimmick_run(153153, ids)
	var c: Dictionary = _all_gimmick_run(153154, ids)
	DB.arena_by_id.erase("env153_all")
	Navigator.forget(shared)
	check(a.signature == b.signature, "26 heroes on the all-gimmick arena reproduce exactly")
	check(a.strikes != c.strikes, "another seed changes the artillery pattern")
	check(bool(a.copy) and var_to_str(shared.obs_mask) == authored, "battles play on private copies of the gated arena")
	check(bool(a.tagged), "every ENV_* event carries hazard id and type")
	check(bool(a.finite) and int(a.stuck) == 0, "no hero inside a wall or non-finite (stuck ticks %d)" % int(a.stuck))
	var counts: Dictionary = a.counts
	for t in ["ENV_ARTILLERY", "ENV_STRIKE", "ENV_GATE", "ENV_RING"]:
		check(int(counts.get(t, 0)) > 0, "all-gimmick battle produced " + t)
	print("ENVIRONMENT_153 all-gimmick events ", JSON.stringify(counts))


# ================================================================== V1.5.3 review fixes
# Artillery (review confirmed #4): strike centres stay inside the area shape and
# the bounds, outside obstacles, also when the aimed hero stands at the edge and
# when an obstacle straddles the area edge. Strikes come from the sky (walls do
# not block the blast; low #7 decision).
func _strike_rows(sim: BattleSim, art: Dictionary, cycles: int, keep: Array) -> Array:
	var rows: Array = []
	for cycle in cycles:
		var impact: float = Arena.artillery_impact_time(art, cycle)
		for k in sim.heroes.size():
			var u: BUnit = sim.heroes[k]
			u.hp = sim.max_hp(u)
			place(u, keep[k])
		at(sim, impact - Arena.artillery_warning(art) + 0.01)
		for row in sim.env.artillery_state():
			rows.append(row.pos)
		at(sim, impact + 0.01)
	return rows


func artillery_area_clamp() -> void:
	# Rect area, heroes 5 px inside a corner / an edge, spread 80.
	var sim: BattleSim = fresh(base_data("env153_art_clamp", {"hazards": [artillery_hazard({"spread": 80.0})]}))
	var art: Dictionary = sim.arena.hazards[0]
	var rows: Array = _strike_rows(sim, art, 10, [Vector2(305, 205), Vector2(1095, 400)])
	var inside: int = 0
	for p in rows:
		if Arena.shape_contains(art, p, 0.5) and not sim.arena.inside_obstacle(p, 1.9):
			inside += 1
	check(rows.size() == 30 and inside == rows.size(), "edge-aimed strikes land inside the rect area (%d / %d)" % [inside, rows.size()])
	sim.dispose()
	# Circle area.
	var circ: Dictionary = artillery_hazard({"id": "art_c", "shape": "circle", "x": 700.0, "y": 400.0, "radius": 150.0, "spread": 120.0})
	sim = fresh(base_data("env153_art_circle", {"hazards": [circ]}))
	art = sim.arena.hazards[0]
	rows = _strike_rows(sim, art, 8, [Vector2(845, 400), Vector2(700, 255)])
	inside = 0
	for p in rows:
		if Arena.shape_contains(art, p, 0.5):
			inside += 1
	check(rows.size() == 24 and inside == rows.size(), "edge-aimed strikes land inside the circle area (%d / %d)" % [inside, rows.size()])
	sim.dispose()
	# An obstacle straddling the west edge: pushing a strike out of it must not
	# leave the area (the point slides toward the area centre instead).
	var straddle: Dictionary = base_data("env153_art_straddle", {"hazards": [artillery_hazard({"spread": 80.0})],
		"obstacles": [{"id": "edge_wall", "shape": "rect", "x": 290.0, "y": 200.0, "w": 90.0, "h": 400.0}]})
	sim = fresh(straddle)
	art = sim.arena.hazards[0]
	rows = _strike_rows(sim, art, 10, [Vector2(400, 400), Vector2(400, 300)])
	inside = 0
	for p in rows:
		if Arena.shape_contains(art, p, 0.5) and not sim.arena.inside_obstacle(p, 1.9) and p.x >= sim.arena.min_x:
			inside += 1
	check(rows.size() == 30 and inside == rows.size(), "strikes pushed out of an edge obstacle stay in the area (%d / %d)" % [inside, rows.size()])
	sim.dispose()
	# Same seed, same clamped points (no extra RNG draws).
	var s1: BattleSim = fresh(straddle, ["swordsman"], ["archer"], 9001)
	var s2: BattleSim = fresh(straddle, ["swordsman"], ["archer"], 9001)
	check(var_to_str(_strike_rows(s1, s1.arena.hazards[0], 3, [Vector2(400, 400), Vector2(400, 300)])) == var_to_str(_strike_rows(s2, s2.arena.hazards[0], 3, [Vector2(400, 400), Vector2(400, 300)])), "clamped strikes stay seeded")
	s1.dispose()
	s2.dispose()
	# Unannounced-salvo pricing covers everything a clamped strike can reach:
	# area + strike radius + 0.3 x body radius (artillery_hazard: rect from
	# x = 300, strike radius 60; a 20 px body reaches 66 px out).
	var priced: Dictionary = artillery_hazard()
	check(Arena.artillery_expected(priced, Vector2(300.0 - 64.0, 400.0), 0.5, 20.0, 4.0) > 0.0, "unannounced salvos are priced up to the body-padded strike reach")
	near(Arena.artillery_expected(priced, Vector2(300.0 - 70.0, 400.0), 0.5, 20.0, 4.0), 0.0, "beyond the strike reach costs nothing")
	# Strikes fall from the sky: a wall between the strike and a hero gives no cover.
	var sky: Dictionary = base_data("env153_art_sky", {"hazards": [artillery_hazard({"count": 1, "spread": 0.0, "radius": 80.0})],
		"obstacles": [{"id": "bunker", "shape": "rect", "x": 530.0, "y": 300.0, "w": 15.0, "h": 200.0}]})
	sim = fresh(sky)
	var a: BUnit = sim.heroes[0]
	var b: BUnit = sim.heroes[1]
	place(a, Vector2(500, 400))
	place(b, Vector2(570, 400))
	var hp_a: float = a.hp
	var hp_b: float = b.hp
	at(sim, 2.51)
	at(sim, 4.01)
	check(sim.arena.segment_blocked(a.pos, b.pos, 0.0, Arena.MASK_PROJECTILES) and a.hp < hp_a and b.hp < hp_b, "artillery blast is not blocked by walls (strikes come from the sky)")
	sim.dispose()


# Navigator snapping (review confirmed #5): a solid start / goal cell snaps to
# the nearest free cell, near-ties toward the other end, so mirrored queries
# give mirrored routes.
func navigator_mirror_snap() -> void:
	var rg: Arena = DB.arena("ruined_gate")
	var w: float = rg.width
	var nav: Navigator = Navigator.for_arena(rg, 18.0, 0)
	var snap_ok: bool = true
	var wp_ok: bool = true
	for pair in [[Vector2(682, 448), Vector2(300, 448)], [Vector2(680, 448), Vector2(300, 448)], [Vector2(682, 420), Vector2(300, 420)],
			[Vector2(682, 480), Vector2(300, 480)], [Vector2(682, 448), Vector2(790, 448)], [Vector2(690, 300), Vector2(300, 448)]]:
		var p: Vector2 = pair[0]
		var g: Vector2 = pair[1]
		var q: Vector2 = Vector2(w - p.x, p.y)
		var gq: Vector2 = Vector2(w - g.x, g.y)
		var pp: PackedVector2Array = nav.path_points(p, g)
		var pq: PackedVector2Array = nav.path_points(q, gq)
		snap_ok = snap_ok and pp.size() > 0 and pq.size() > 0 and absf(pp[0].x - (w - pq[0].x)) < 0.01 and absf(pp[0].y - pq[0].y) < 0.01
		var wp: Vector2 = nav.next_waypoint(p, g, 18.0)
		var wq: Vector2 = nav.next_waypoint(q, gq, 18.0)
		wp_ok = wp_ok and absf(wp.x - (w - wq.x)) < 0.5 and absf(wp.y - wq.y) < 0.5
	check(snap_ok, "closed gate frame: mirrored heroes snap to mirrored cells")
	check(wp_ok, "closed gate frame: mirrored heroes get mirrored waypoints")
	# Map centres inside an obstacle (and dimensional_lattice, whose centre and
	# both spawn centroids sit on a cell boundary): both teams get the same length.
	for id in ["furnace_basin", "gale_corridor", "rift_harbor", "dimensional_lattice"]:
		var ar: Arena = DB.arena(id)
		var n2: Navigator = Navigator.for_arena(ar, 18.0)
		var c: Vector2 = ar.center()
		var lb: float = n2.path_length(ar.spawn_centroid(0), c, 18.0, 0.0, 0.0, 0.0, false)
		var lr: float = n2.path_length(ar.spawn_centroid(1), c, 18.0, 0.0, 0.0, 0.0, false)
		check(lb < INF and lr < INF and absf(lb - lr) <= 0.03 * maxf(lb, lr), "%s: path to the obstacle-covered centre is fair (%.0f / %.0f)" % [id, lb, lr])
	# Synthetic: obstacle on the axis of a mirrored map, goal inside it.
	var sym: Arena = Arena.from_data(base_data("env153_sym", {"obstacles": [{"id": "core", "shape": "circle", "x": 704.0, "y": 396.0, "radius": 70.0}]}))
	var ns: Navigator = Navigator.get_for(sym, 18.0)
	var lb2: float = ns.path_length(Vector2(200, 300), Vector2(704, 396), 18.0)
	var lr2: float = ns.path_length(Vector2(1208, 300), Vector2(704, 396), 18.0)
	var wb: Vector2 = ns.next_waypoint(Vector2(200, 300), Vector2(704, 396), 18.0)
	var wr: Vector2 = ns.next_waypoint(Vector2(1208, 300), Vector2(704, 396), 18.0)
	check(absf(lb2 - lr2) < 0.5 and absf(wb.x - (1408.0 - wr.x)) < 0.5 and absf(wb.y - wr.y) < 0.5, "goal inside an axis obstacle: mirrored lengths and waypoints (%.1f / %.1f)" % [lb2, lr2])
	Navigator.forget(sym)
	Navigator.forget(rg)


# Environment switches (review confirmed #6 / low #4): switched-off hazards add
# no weights, shortcut blockers or links; grids never leak into other battles.
func navigator_env_switches() -> void:
	var a: Vector2 = Vector2(560, 420)
	var g: Vector2 = Vector2(784, 420)
	var sim: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "furnace_basin", "seed": 4242})
	sim.start()
	var u: BUnit = sim.heroes[0]
	var r: float = sim.radius(u)
	place(u, a)
	var on_wp: Vector2 = Navigator.unit_waypoint(sim, u, g)
	var on_nav: Navigator = Navigator.for_sim(sim, r)
	var lava_c: Vector2i = on_nav.cell_of(Vector2(672, 425))
	check(on_wp != g and on_nav.weights[lava_c.y * on_nav.cols + lava_c.x] == Navigator.W_ALWAYS_DAMAGE, "lava on: the route detours around the pool")
	check(Navigator.for_sim(sim, r) == Navigator.for_arena(sim.arena, r), "all switches on: battles share the default grid")
	sim.env.set_type_enabled("wind", false)
	sim.env.set_type_enabled("artillery", false)
	check(Navigator.for_sim(sim, r) == on_nav, "switches that do not shape the grid build no extra grid")
	sim.env.set_type_enabled("wind", true)
	sim.env.set_type_enabled("artillery", true)
	sim.env.enabled = false
	var off_nav: Navigator = Navigator.for_sim(sim, r)
	check(off_nav != on_nav and off_nav.weights[lava_c.y * off_nav.cols + lava_c.x] == 1.0 and off_nav.links.is_empty() and off_nav.safe_clear(a, g, r), "environment off: no hazard weights, blockers or links")
	check(Navigator.unit_waypoint(sim, u, g) == g and absf(Navigator.unit_path_length(sim, u, g) - a.distance_to(g)) < 0.01, "environment off: heroes walk straight over inert lava")
	sim.env.enabled = true
	sim.env.set_type_enabled("lava", false)
	check(Navigator.unit_waypoint(sim, u, g) == g, "lava switched off: straight line through the pool")
	var lava_off: Navigator = Navigator.for_sim(sim, r)
	check(not lava_off.links.is_empty(), "lava switched off: jump-pad links stay")
	sim.env.set_type_enabled("lava", true)
	check(Navigator.unit_waypoint(sim, u, g) == on_wp, "lava switched on again: the detour returns")
	# A later battle on the same map never sees the lab's grids.
	var other: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "furnace_basin", "seed": 4243})
	other.start()
	place(other.heroes[0], a)
	check(Navigator.for_sim(other, r) == on_nav and Navigator.unit_waypoint(other, other.heroes[0], g) == on_wp, "switch grids never leak into another battle")
	other.dispose()
	sim.dispose()
	# gale_corridor: jump pad and mud switched off.
	var gs: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "gale_corridor", "seed": 4242})
	gs.start()
	var gu: BUnit = gs.heroes[0]
	var gr: float = gs.radius(gu)
	var pad: Vector2 = Vector2(520, 170)
	place(gu, Vector2(400, 170))
	check(Navigator.unit_waypoint(gs, gu, pad) != pad, "pad on: walking goals stop at the pad rim")
	gs.env.set_type_enabled("jump_pad", false)
	var pnav: Navigator = Navigator.for_sim(gs, gr)
	var pc: Vector2i = pnav.cell_of(pad)
	check(pnav.links.is_empty() and pnav.weights[pc.y * pnav.cols + pc.x] == 1.0, "pad off: no link and no pad weight")
	check(Navigator.unit_waypoint(gs, gu, pad) == pad, "pad off: an inert pad is ordinary floor")
	gs.env.set_type_enabled("jump_pad", true)
	gs.env.set_type_enabled("mud", false)
	var mnav: Navigator = Navigator.for_sim(gs, gr)
	var mc: Vector2i = mnav.cell_of(Vector2(620, 570))
	var dnav: Navigator = Navigator.for_arena(gs.arena, gr)
	check(mnav.weights[mc.y * mnav.cols + mc.x] == 1.0 and absf(dnav.weights[mc.y * dnav.cols + mc.x] - Navigator.W_MUD) < 1e-4, "mud off: mire cells lose their weight (default grid keeps it)")
	gs.dispose()


# Unreachable goals (review low #8): next_waypoint gives the end of the partial
# path (the closest reachable cell on the traveller's side), never the goal.
func navigator_unreachable_goal() -> void:
	# The playable V2 keep now has permanent side passages. Preserve the
	# historical enclosed geometry privately so this still exercises a truly
	# unreachable goal, without depending on the current map's connectivity.
	var sealed_keep: Dictionary = DB.arena("ruined_gate").data.duplicate(true)
	sealed_keep.id = "env153_sealed_keep"
	var restored: int = 0
	for obstacle: Dictionary in sealed_keep.obstacles:
		if str(obstacle.id) in ["lattice_wn", "lattice_en"]:
			obstacle.y = 298.0
			obstacle.h = 95.0
			restored += 1
		elif str(obstacle.id) in ["lattice_ws", "lattice_es"]:
			obstacle.h = 95.0
			restored += 1
	check(restored == 4, "unreachable-goal fixture privately restores four keep walls")
	var sim: BattleSim = fresh(sealed_keep, ["swordsman"], ["archer"], 3)
	var t: float = 20.0
	while sim.arena.gate_bits_at(t, Arena.NAV_CLOSING_MARGIN) != 0:
		t += 0.01
	sim.time = t
	sim.env.update(DT)
	var nav: Navigator = Navigator.get_for(sim.arena, 18.0)
	var goal: Vector2 = Vector2(800, 448)
	var w: float = sim.arena.width
	check(sim.arena.nav_sig == 0 and nav.path_length(Vector2(560, 448), goal, 18.0) == INF, "keep is unreachable while every gate counts as closed")
	var ends: Array = []
	for start in [Vector2(560, 448), Vector2(w - 560.0, 448)]:
		var pts: PackedVector2Array = nav.path_points(start, goal)
		var e: Vector2 = pts[pts.size() - 1] if pts.size() > 0 else start
		ends.append(e)
		var hold: Vector2 = nav.next_waypoint(e, goal, 18.0)
		var near_hold: Vector2 = nav.next_waypoint(e + Vector2(2, -3), goal, 18.0)
		check(hold != goal and hold.distance_to(e) < 0.5 and near_hold.distance_to(e) < 0.5, "hero at the closest reachable cell holds there instead of pressing into the gate (%s)" % str(start))
	check(ends.size() == 2 and (ends[0] as Vector2).x < 668.0 and absf((ends[0] as Vector2).x - (w - (ends[1] as Vector2).x)) < 0.01, "partial paths end at each team's own gate (%s / %s)" % [str(ends[0]), str(ends[1])])
	sim.dispose()
	# Enclosed goal on a static map.
	var boxed: Arena = Arena.from_data(base_data("env153_box_hold", {"obstacles": [
		{"id": "b1", "shape": "rect", "x": 1000.0, "y": 300.0, "w": 200.0, "h": 20.0}, {"id": "b2", "shape": "rect", "x": 1000.0, "y": 480.0, "w": 200.0, "h": 20.0},
		{"id": "b3", "shape": "rect", "x": 1000.0, "y": 300.0, "w": 20.0, "h": 200.0}, {"id": "b4", "shape": "rect", "x": 1180.0, "y": 300.0, "w": 20.0, "h": 200.0}]}))
	var nb: Navigator = Navigator.get_for(boxed, 18.0)
	var inner: Vector2 = Vector2(1100, 400)
	var pb: PackedVector2Array = nb.path_points(Vector2(300, 400), inner)
	var eb: Vector2 = pb[pb.size() - 1]
	check(nb.next_waypoint(eb, inner, 18.0) != inner and nb.next_waypoint(Vector2(300, 400), inner, 18.0) != inner, "enclosed goal is never returned as a waypoint")
	Navigator.forget(boxed)


# Shared grids (review low #3): link exits are placed under the grid's own gate
# signature, whatever gate state the arena instance showed when it was built.
func navigator_link_exits_order_free() -> void:
	var d: Dictionary = base_data("env153_linksig", {"obstacles": [{"id": "g1", "shape": "rect", "x": 700.0, "y": 300.0, "w": 40.0, "h": 200.0,
		"gate": {"group": "A", "period": 10.0, "openDuration": 5.0, "warningDuration": 1.0, "phase": 0.0}}],
		"hazards": [{"id": "pad", "type": "jump_pad", "shape": "circle", "x": 300.0, "y": 400.0, "radius": 30.0, "target": {"x": 720.0, "y": 400.0}, "flightTime": 0.8, "cooldown": 2.0}]})
	var a: Arena = Arena.from_data(d)
	var rows: Array = []
	for build_bits in [0, 1]:
		Navigator.forget(a)
		a.apply_gate_bits(build_bits)
		var nav: Navigator = Navigator.for_arena(a, 18.0, 1)
		a.apply_gate_bits(1)
		rows.append([nav.links[0].exit if not nav.links.is_empty() else Vector2.INF, nav.path_length(Vector2(150, 400), Vector2(760, 400), 18.0)])
	check(var_to_str(rows[0]) == var_to_str(rows[1]) and (rows[0][0] as Vector2).distance_to(Vector2(720, 400)) < 0.01, "a grid's link exits do not depend on the gate state at build time (%s / %s)" % [var_to_str(rows[0]), var_to_str(rows[1])])
	near(a.resolve_circle_sig(Vector2(720, 400), 18.0, 0).x, 700.0 - 18.0 - 0.02, "resolve_circle_sig treats a closed-signature gate as a wall", 0.01)
	Navigator.forget(a)


# Jump-pad flights (review lows #2 / #5): knockbacks, pulls and hooks cannot
# cut a flight short over a chasm; the hero always lands on the target.
func pad_flight_completes() -> void:
	var data: Dictionary = base_data("env153_pad_trench", {
		"obstacles": [{"id": "trench", "shape": "rect", "x": 600.0, "y": L, "w": 200.0, "h": 754.6 - L, "blocksProjectiles": false, "blocksVision": false}],
		"hazards": [{"id": "pad_w", "type": "jump_pad", "shape": "circle", "x": 500.0, "y": 400.0, "radius": 30.0, "target": {"x": 900.0, "y": 400.0}, "flightTime": 0.6}]})
	for mode in ["knockback", "pullToSource"]:
		var sim: BattleSim = fresh(data, ["swordsman"], ["baseball"])
		var u: BUnit = sim.heroes[0]
		var foe: BUnit = sim.heroes[1]
		place(u, Vector2(500, 400))
		place(foe, Vector2(450, 600))
		sim.env.update(DT)
		check(u.motion != null and u.motion.kind == "jump_pad", "pad launches the hero (%s case)" % mode)
		var guard: int = 0
		while u.motion != null and u.pos.x < 700.0 and guard < 40:
			sim.kits.update_motion(u, DT)
			sim.time += DT
			guard += 1
		var mid: Vector2 = u.pos
		sim.kits.displace(foe, u, {"mode": mode, "distance": 95.0, "speed": 450.0}, {"direction": Vector2.LEFT})
		# CC_IMMUNE / DASH_ENDED are not LOG_TYPES: read the tick event buffer
		# (no sim.step() runs here, so it holds everything since the launch).
		var immune: bool = false
		for ev in sim.tick_events:
			immune = immune or (str(ev.type) == "CC_IMMUNE" and int(ev.g) == u.idx and str(ev.get("reason", "")) == "flight")
		check(sim.arena.inside_obstacle(mid, 0.0) and u.motion != null and u.motion.kind == "jump_pad" and immune, "%s over the trench is refused mid-flight (CC_IMMUNE flight)" % mode)
		for i in 40:
			if u.motion == null:
				break
			sim.kits.update_motion(u, DT)
			sim.time += DT
		var modes: Array = []
		for ev in sim.tick_events:
			if str(ev.type) == "DASH_ENDED" and int(ev.g) == u.idx:
				modes.append(str(ev.mode))
		check(u.motion == null and u.pos.distance_to(Vector2(900, 400)) < 2.0 and not sim.arena.inside_obstacle(u.pos, sim.radius(u) - 0.5) and modes == ["jump_pad"], "%s: the flight completes on its landing (%s, %s)" % [mode, str(u.pos), str(modes)])
		sim.dispose()


# Draft rollouts (review low #1): the stage-1 warm-up builds exactly the grids
# the started rollout battle routes with (gated maps included).
class FakeDirector:
	extends RefCounted
	var budget: int = 1
	var search_options: Dictionary = {}
	var ruleset: String = "elimination"
	var team_size: int = 3
	var seed_value: int = 7
	var arena_id: String = "classic"
	func mask_of(_ids: Array) -> int:
		return 0
	func legal(_a: int, _u: int) -> PackedInt32Array:
		return PackedInt32Array()


func draft_rollout_warmup() -> void:
	for cfg in [["ruined_gate", "elimination"], ["control_citadel", "control"]]:
		Navigator._cache.clear()
		var fd: FakeDirector = FakeDirector.new()
		fd.arena_id = str(cfg[0])
		fd.ruleset = str(cfg[1])
		var ds: DraftSearch14 = DraftSearch14.new(fd, [], [])
		ds.director = fd
		ds.rollout_jobs = [{"id": "probe", "ours": ["swordsman", "giant", "archer"], "theirs": ["mage", "werewolf", "pirate"], "side": 0}]
		ds.rollout_cursor = 0
		ds._rollout_step()
		var guard: int = 0
		while ds.rollout_stage == 1 and not ds.rollout_warm.is_empty() and guard < 16:
			ds._rollout_step()
			guard += 1
		var warmed: Array = Navigator._cache.values()
		var sim: BattleSim = ds.rollout_sim
		ds._rollout_step()
		var used: bool = sim != null and sim.state == BattleSim.RUNNING
		if sim != null:
			for u in sim.heroes:
				used = used and warmed.has(Navigator.get_for(sim.arena, sim.radius(u)))
		check(warmed.size() > 0 and used, "%s: rollout warm-up builds the grids the started battle uses" % str(cfg[0]))
		ds.cancel()


# Determinism on the shipped gimmick maps: the same seed twice, cold vs warm
# navigation cache, and with other battles (one of them a lab run with the
# switches off) interleaved, all reproduce the battle exactly.
func _map_run(map_id: String, seed_v: int, ticks: int, env_on: bool = true, kick: String = "") -> String:
	var a0: Arena = DB.arena(map_id)
	var sim: BattleSim = BattleSim.new({"ruleset": a0.ruleset, "arena_id": map_id, "seed": seed_v, "max_time": 150.0,
		"blue": ["swordsman", "hive_mind", "baseball"], "red": ["archer", "dimensionalist", "giant"]})
	sim.controllers[0] = AIFactory.make("tactician", sim, 0)
	sim.controllers[1] = AIFactory.make("tactician", sim, 1)
	sim.start()
	if not env_on:
		sim.env.enabled = false
	if kick != "":
		# Start one hero on the first link of that type so the run surely uses it.
		for h in sim.arena.hazards:
			if str(h.type) == kick:
				place(sim.heroes[0], h.center)
				break
	for i in ticks:
		if not sim.step():
			break
	var rows: Array = []
	for u in sim.heroes:
		rows.append([u.id, u.alive, u.hp, u.pos])
	var counts: Dictionary = {}
	for ev in sim.log:
		var t: String = str(ev.type)
		if t.begins_with("ENV_") or t == "DEATH" or t == "HEALTH_DAMAGED":
			counts[t] = int(counts.get(t, 0)) + 1
	var out: String = var_to_str([sim.tick, rows, counts, sim.log.size()])
	_last_counts = counts
	sim.dispose()
	return out


var _last_counts: Dictionary = {}


func map_cache_determinism() -> void:
	# [map, ticks (30 per second), label, event that must occur, link type to start on]
	var cases: Array = [["ruined_gate", 450, "gate", "ENV_GATE", ""], ["rift_harbor", 450, "portal", "ENV_PORTAL", "portal"],
		["furnace_basin", 450, "jump_pad", "ENV_JUMP", "jump_pad"], ["twin_foundry", 450, "artillery", "ENV_STRIKE", ""],
		["bastion_ring", 1080, "ring", "ENV_RING", ""], ["control_citadel", 450, "gate+artillery", "ENV_STRIKE", ""]]
	for c in cases:
		var id: String = str(c[0])
		var ticks: int = int(c[1])
		var kick: String = str(c[4])
		Navigator._cache.clear()
		var cold: String = _map_run(id, 153501, ticks, true, kick)
		var counts: Dictionary = _last_counts
		var warm: String = _map_run(id, 153501, ticks, true, kick)
		Navigator._cache.clear()
		_map_run(id, 153777, 120, false)
		_map_run(id, 153778, 80)
		var mixed: String = _map_run(id, 153501, ticks, true, kick)
		check(cold == warm and cold == mixed, "%s (%s): same seed reproduces cold, warm and interleaved" % [id, str(c[2])])
		if str(c[3]) != "":
			check(int(counts.get(str(c[3]), 0)) > 0, "%s determinism run exercises its gimmick (%s)" % [id, str(c[3])])
		print("ENVIRONMENT_153 determinism %s %s" % [id, JSON.stringify(counts)])
