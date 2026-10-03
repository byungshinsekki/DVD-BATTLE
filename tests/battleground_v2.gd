extends SceneTree

# V2 battleground rules (B-MODE, DESIGN_V2 §3.1 / §3.5): rosters and unit
# ids, spawns, items placed once, the downed state, revives, eliminations,
# item drops, the zone (damage, exemptions, credit, public events), the 600 s
# ranking, the UI contract, information fairness and determinism. Every rule
# is a deterministic micro-scenario on idle heroes except the AI checks at
# the end (determinism, a hidden-future differential and item knowledge).

const MAP := "br_highland_ruins"
const MAP_SEED := 7

# Stable high-level intent only: exercise the production pair decisions,
# steering, physics and channel updates in both BattleSim step paths.
class ReviveCrawlFixtureBrain extends BattlegroundSquadBrain:
	var target_idx: int = -1
	var reviver_idx: int = -1
	var attempted: bool = false

	func _init(s: BattleSim, t: int) -> void:
		super(s, t)

	func pre_tick(_s: BattleSim) -> void:
		# Keep this test's already chosen, safe revive intent stable. Low-level
		# pair decisions and steering below remain the production implementation.
		pass

	func decide(u: BUnit) -> void:
		if u.idx == reviver_idx:
			if attempted and not sim.battleground.is_reviving(u):
				u.command = {}
				u.next_decision_at = sim.time + 0.2
				return
			attempted = true
			super.decide(u)
		elif u.idx == target_idx and sim.battleground.is_downed(u):
			super.decide(u)
		else:
			u.command = {}
			u.next_decision_at = sim.time + 0.2

	func steer(u: BUnit) -> Vector2:
		return super.steer(u) if u.idx == target_idx or u.idx == reviver_idx else Vector2.ZERO


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


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _br(teams: Array, squad: int, seed_v: int = 4242, extra: Dictionary = {}) -> BattleSim:
	var cfg: Dictionary = {"ruleset": "battleground", "arena_id": MAP, "map_seed": MAP_SEED, "seed": seed_v, "squad": squad,
		"teams": teams, "zone_speed": "normal"}
	for k in extra:
		cfg[k] = extra[k]
	return BattleSim.new(cfg)


# Idle heroes, no field items, team t's members placed side by side at
# anchors[t] (open ground near the map centre unless given).
func _idle(teams: Array, squad: int, anchors: Array = [], seed_v: int = 4242, extra: Dictionary = {}) -> BattleSim:
	var sim: BattleSim = _br(teams, squad, seed_v, extra)
	var br: BattlegroundMode = sim.battleground
	br.field.clear()
	br._field_dirty = true
	var c: Vector2 = br.zone.centers[0]
	for t in br.team_count:
		var a: Vector2 = anchors[t] if t < anchors.size() else c + Vector2(-300.0 + 600.0 * t, 260.0 * (t % 2))
		var k: int = 0
		for u in br.team_members(t):
			u.pos = sim.arena.resolve_circle(a + Vector2(0.0, 70.0 * k), sim.radius(u))
			u.prev_pos = u.pos
			k += 1
	sim.start()
	return sim


func _kill_hit(sim: BattleSim, s: BUnit, t: BUnit) -> void:
	sim.apply_damage(s, t, {"school": "true", "base": 100000.0, "frozen": true}, {"source_type": "ABILITY"})


func _steps(sim: BattleSim, seconds: float) -> void:
	for i in int(round(seconds / BattleSim.DT)):
		sim.step()


func _events(sim: BattleSim, type: String) -> Array:
	var out: Array = []
	for ev in sim.log:
		if str(ev.type) == type:
			out.append(ev)
	return out


# Events of a type from the per-tick buffer of the last step.
func _tick_events(sim: BattleSim, type: String) -> Array:
	var out: Array = []
	for ev in sim.tick_events:
		if str(ev.type) == type:
			out.append(ev)
	return out


func _run() -> void:
	DB.ensure_loaded()
	var t0: int = Time.get_ticks_msec()
	_rosters()
	_spawns_and_items()
	_gated_grids()
	_downed_state()
	_downed_zone()
	_revive()
	_revive_crawl_contract()
	_elimination()
	_items_rules()
	_zone_rules()
	_time_cap()
	_contract()
	_information()
	_determinism()
	metrics["suite_ms"] = Time.get_ticks_msec() - t0
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("BATTLEGROUND_V2 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	# Prints the result; writes a JSON report only with --report=<path>.
	var path: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			path = arg.substr(9)
	if path != "":
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"suite": "battleground_v2", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ rosters

func _rosters() -> void:
	# Solo: the same hero on several teams is allowed; unit ids stay unique.
	var solo: BattleSim = _br([["archer"], ["archer"], ["giant"], ["archer"]], 1)
	var br: BattlegroundMode = solo.battleground
	_check(solo.is_battleground() and solo.is_deathmatch() and solo.ruleset == "battleground", "ruleset battleground; deathmatch item paths on")
	_check(solo.deathmatch == br and br is BattlegroundMode, "sim.deathmatch and sim.battleground are the same mode object")
	_check(solo.heroes.size() == 4 and solo.team_count == 4 and br.team_count == 4 and br.squad == 1, "solo: four one-hero teams")
	var ids: Dictionary = {}
	for u in solo.heroes:
		ids[u.id] = true
	_check(ids.size() == 4, "solo duplicates get unique unit ids (%s)" % str(ids.keys()))
	_check(solo.heroes[0].id == "p0_archer" and solo.heroes[3].id == "p3_archer", "unit id rule p<team>_<hero>")
	_check(br.validate({"squad": 1, "teams": [["archer"], ["archer"]]}).is_empty(), "solo roster with a duplicate hero validates")
	# Duo: a hero twice in one team is rejected by validate and dropped by the sim.
	_check(not BattlegroundMode.validate({"squad": 2, "teams": [["archer", "archer"], ["giant", "mage"]]}).is_empty(), "duo: duplicate hero within a team is rejected")
	_check(BattlegroundMode.validate({"squad": 2, "teams": [["archer", "mage"], ["archer", "mage"]]}).is_empty(), "duo: the same heroes on different teams are fine")
	_check(not BattlegroundMode.validate({"squad": 3, "teams": [["archer", "mage"], ["giant", "mage", "nitro"]]}).is_empty(), "trio: a two-hero team is rejected")
	var big: Array = []
	for i in 31:
		big.append(["swordsman"])
	_check(not BattlegroundMode.validate({"squad": 1, "teams": big}).is_empty(), "31 solo players are rejected (max 30)")
	var norm: Array = BattlegroundMode.normalize_teams({"squad": 2, "teams": [["archer", "archer", "mage"], ["giant", "nope", "mage"]]})
	_check(norm.size() == 2 and (norm[0] as Array) == ["archer", "mage"] and (norm[1] as Array) == ["giant", "mage"], "normalize drops in-team duplicates and unknown ids (%s)" % str(norm))
	_check(BattlegroundMode.normalize_teams({"squad": 1, "teams": big}).size() == 30, "normalize caps the roster at 30 heroes")
	var duo: BattleSim = _br([["archer", "mage"], ["archer", "mage"], ["giant", "nitro"]], 2)
	var ids2: Dictionary = {}
	for u in duo.heroes:
		ids2[u.id] = true
	_check(duo.heroes.size() == 6 and ids2.size() == 6 and duo.battleground.squad == 2, "duo: six heroes, unique ids across teams")
	for t in duo.battleground.team_count:
		var m: Array = duo.battleground.team_members(t)
		_check(m.size() == 2 and (m[0] as BUnit).team == t and (m[1] as BUnit).team == t, "duo team %d has its two members" % t)
	# 30-hero solo lobby with repeated heroes: every id unique.
	var thirty: Array = []
	var pool: Array = DB.ids()
	for i in 30:
		thirty.append([pool[i % 8]])
	var s30: BattleSim = _br(thirty, 1, 99)
	var ids3: Dictionary = {}
	for u in s30.heroes:
		ids3[u.id] = true
	_check(s30.heroes.size() == 30 and ids3.size() == 30 and s30.team_count == 30, "30 solo heroes with repeats: 30 unique ids")
	metrics["solo30_controllers_slots"] = s30.controllers.size()
	solo.dispose()
	duo.dispose()
	s30.dispose()


# ------------------------------------------------------------------ spawns, items

func _spawns_and_items() -> void:
	var sim: BattleSim = _br([["archer", "mage", "giant"], ["nitro", "sniper", "metatron"], ["swordsman", "werewolf", "hermes"], ["engineer", "aphrodite", "joker"]], 3, 515)
	var br: BattlegroundMode = sim.battleground
	var centres: Array = []
	for t in br.team_count:
		var c: Vector2 = Vector2.ZERO
		var members: Array = br.team_members(t)
		for u in members:
			c += (u as BUnit).pos / members.size()
		var spread: float = 0.0
		for u in members:
			spread = maxf(spread, (u as BUnit).pos.distance_to(c))
		_check(spread < 120.0, "team %d spawns together in formation (spread %.0f)" % [t, spread])
		centres.append(c)
	var gap: float = INF
	for i in centres.size():
		for j in range(i + 1, centres.size()):
			gap = minf(gap, (centres[i] as Vector2).distance_to(centres[j]))
	_check(gap >= 800.0, "teams start apart at greedy-farthest spawns (min %.0f px)" % gap)
	metrics["trio4_min_team_gap"] = snappedf(gap, 0.1)
	_check(br.field.size() == BattlegroundMode.ITEM_COUNT, "80 items placed at t=0 (%d)" % br.field.size())
	var rings: Array = [0, 0, 0, 0]
	for it in br.field:
		rings[int(it.ring)] += 1
	_check(rings == [12, 20, 24, 24], "ring counts 12/20/24/24 (%s)" % str(rings))
	var placed: Array = BrItems.place(sim.arena.data, sim.seed_value)
	var same: bool = placed.size() == br.field.size()
	for i in mini(placed.size(), br.field.size()):
		same = same and str(placed[i].item) == str(br.field[i].item) and (placed[i].pos as Vector2) == (br.field[i].pos as Vector2)
	_check(same, "field items are BrItems.place(arena.data, seed)")
	# Move every hero away from items and wait: nothing respawns.
	sim.start()
	for u in sim.heroes:
		u.pos = sim.arena.resolve_circle(br.zone.centers[0] + Vector2(u.idx * 3.0, 0.0), sim.radius(u))
	br.field = br.field.filter(func(it): return (it.pos as Vector2).distance_to(br.zone.centers[0]) > 200.0)
	br._field_dirty = true
	var n0: int = br.field.size()
	_steps(sim, 20.0)
	_check(br.field.size() == n0 and br.next_item_at == INF, "no timed item respawn (%d -> %d)" % [n0, br.field.size()])
	# Navigation: every bucket under both gate signatures exists before tick 1
	# (checked on the gated metropolis), and nothing is built mid-match.
	var metro: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": "br_ashen_metropolis", "seed": 7, "squad": 1,
		"teams": [["giant"], ["archer"], ["mage"]]})
	var sigs: Array = metro.battleground.gate_signatures()
	_check(sigs.size() >= 2, "metropolis has both gate signatures (%s)" % str(sigs))
	var missing: int = 0
	for b in metro.nav_buckets():
		for sig in sigs:
			var key: String = "c%d:%d:%d:%d" % [metro.arena.source_uid, int(Navigator.bucket_for(float(b))), int(sig), Navigator.nav_skip_bits(metro.arena, metro.env.skip_mask())]
			if not Navigator._cache.has(key):
				missing += 1
	_check(missing == 0, "metropolis: every bucket x gate signature grid prebuilt (%d missing)" % missing)
	var before: Dictionary = {}
	for k in Navigator._cache.keys():
		before[k] = true
	for t in metro.team_count:
		metro.controllers[t] = AIFactory.make("tactician", metro, t)
	metro.start()
	_steps(metro, 30.0)
	var fresh: int = 0
	for k2 in Navigator._cache.keys():
		if not before.has(k2):
			fresh += 1
	_check(fresh == 0, "metropolis: no path grid built during 30 s of play (%d)" % fresh)
	metro.dispose()
	sim.dispose()


# Gated maps now build path grids per obstacle (the per-cell reference took
# ~50 s per grid on the metropolis): the solid sets must equal the reference
# on every shipped gated map, every bucket and both gate signatures.
func _gated_grids() -> void:
	var cases: int = 0
	var bad: int = 0
	for a0 in DB.arenas:
		var a: Arena = a0
		if a.gates.is_empty():
			continue
		for sig in [0, a.all_gates_open_bits()]:
			for b in [12.0, 18.0, 26.0, 28.0, 30.0]:
				var nav: Navigator = Navigator.new()
				nav.arena = a
				nav.bucket = b
				nav.sig = int(sig)
				nav.cols = int(ceil(a.width / Navigator.CELL))
				nav.rows = int(ceil(a.height / Navigator.CELL))
				bad += nav.debug_build_mismatch()
				cases += 1
	_check(cases >= 10 and bad == 0, "gated maps: per-obstacle grids equal the per-cell reference (%d grids, %d cells differ)" % [cases, bad])


# ------------------------------------------------------------------ downed

func _downed_state() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"], ["nitro", "sniper"]], 2,
		[], 4242)
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	var far: BUnit = br.team_members(2)[0]
	# Team 2 stands far away and sees nothing of team 0.
	for u in br.team_members(2):
		u.pos = sim.arena.resolve_circle(u.pos + Vector2(0.0, 1800.0), sim.radius(u))
	sim._update_visibility()
	var ms0: float = sim.stat(a1, &"moveSpeed")
	b1.pos = sim.arena.resolve_circle(a1.pos + Vector2(80.0, 0.0), sim.radius(b1))
	sim._update_visibility()
	_kill_hit(sim, b1, a1)
	_check(a1.alive and br.is_downed(a1), "lethal damage with a standing teammate downs the hero")
	_check(_near(a1.hp, BattlegroundMode.DOWNED_HP, 0.01) and BattlegroundMode.DOWNED_HP == 400.0, "downed health is 400 (%.1f)" % a1.hp)
	_check(sim.has_status(a1, &"downed") and sim.get_status(a1, &"downed").end == INF, "downed status, no expiry")
	_check(not sim.can_cast(a1) and not sim.can_basic(a1), "downed: no abilities, no basic attacks")
	_check(_near(sim.stat(a1, &"moveSpeed"), ms0 * 0.35, 0.01), "downed move speed x0.35 (%.1f of %.1f)" % [sim.stat(a1, &"moveSpeed"), ms0])
	var info: Dictionary = br.downed_info(a1)
	for key in ["since", "bleed_at", "bleed_total", "hp", "max_hp", "revive_progress", "reviver_idx"]:
		_check(info.has(key), "downed_info has %s" % key)
	_check(_near(float(info.bleed_total), 30.0, 0.001) and _near(float(info.bleed_at) - float(info.since), 30.0, 0.001), "first down bleeds out in 30 s")
	_check(int(br.hstats[b1.idx].knocks) == 1 and int(br.hstats[b1.idx].kills) == 0, "a knock is counted apart from kills")
	var dev: Array = _tick_events(sim, "BR_DOWNED")
	_check(dev.size() == 1 and bool(dev[0].gv[0]) and bool(dev[0].gv[1]) and not bool(dev[0].gv[2]), "BR_DOWNED visible to the own team and observers only (%s)" % str(dev[0].gv if not dev.is_empty() else []))
	var knock_feed: Array = br.kill_feed.filter(func(e): return str(e.kind) == "knock")
	_check(knock_feed.size() == 1 and not bool(knock_feed[0].public), "kill feed: knock entry, not public")
	# Heal and shields do not touch the downed pool; cleanse keeps the state.
	var healed: Dictionary = sim.apply_heal(a2, a1, {"base": 500.0}, {})
	_check(float(healed.effective) == 0.0 and _near(a1.hp, BattlegroundMode.DOWNED_HP, 0.01), "heal does not restore downed health")
	_check(sim.apply_shield(a2, a1, {"base": 200.0, "duration": 3.0}, {}) == 0.0, "no shields on a downed hero")
	sim.cleanse(a2, a1, {})
	_check(br.is_downed(a1) and sim.has_status(a1, &"downed"), "cleanse does not remove downed (not crowd control)")
	sim.apply_status(b1, a1, {"status": "stun", "duration": 1.0}, {})
	_check(sim.get_status(a1, &"downed").end == INF, "tenacity and CC do not change the downed state")
	# A downed hero deals no damage.
	var hp_b: float = b1.hp
	var dealt: float = sim.apply_damage(a1, b1, {"school": "true", "base": 50.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
	_check(dealt == 0.0 and b1.hp == hp_b, "a downed hero deals no damage")
	# Downed hero keeps its items.
	# Bleed-out: 30 s, then death credited to the knocker.
	_steps(sim, 29.5)
	_check(a1.alive and br.is_downed(a1), "still downed at 29.5 s")
	_steps(sim, 1.0)
	_check(not a1.alive and not br.is_downed(a1), "bleeds out at 30 s")
	_check(str(br.hstats[a1.idx].death_cause) == "bleed" and int(br.hstats[b1.idx].kills) == 1, "bleed-out death credited to the knocker")
	_check(not _events(sim, "BR_BLED_OUT").is_empty(), "BR_BLED_OUT event")
	var elim: Array = _events(sim, "BR_ELIMINATED")
	_check(not elim.is_empty() and bool(elim[0].public) and bool(elim[0].gv[2]), "BR_ELIMINATED is public")
	_check(not br.is_eliminated(0) and br.team_alive(0) == 1, "team 0 stays in with one standing member")
	sim.dispose()
	# Repeat downs: 30 / 20 / 10 / 10 s; downed health reaching 0 kills.
	var sim2: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br2: BattlegroundMode = sim2.battleground
	var c1: BUnit = br2.team_members(0)[0]
	var c2: BUnit = br2.team_members(0)[1]
	var e1: BUnit = br2.team_members(1)[0]
	var windows: Array = []
	for k in 4:
		_kill_hit(sim2, e1, c1)
		windows.append(float(br2.downed_info(c1).get("bleed_total", -1.0)))
		br2.downed[c1.idx]["reviver_idx"] = c2.idx
		br2.downed[c1.idx]["revive_start"] = sim2.time - BattlegroundMode.REVIVE_TIME
		br2.reviving[c2.idx] = c1.idx
		c2.pos = sim2.arena.resolve_circle(c1.pos + Vector2(40.0, 0.0), sim2.radius(c2))
		sim2.step()
	_check(windows == [30.0, 20.0, 10.0, 10.0], "bleed windows 30/20/10/10 on repeated downs (%s)" % str(windows))
	_kill_hit(sim2, e1, c1)
	_check(br2.is_downed(c1), "downed again")
	# Hero-on-hero damage carries the free-for-all brawl factor (x1.3); a
	# downed hero takes x DOWNED_TAKEN of it (B-SQUAD: 0.5).
	_check(_near(BattlegroundMode.DOWNED_TAKEN, 0.5, 0.0001), "downed heroes take x0.5 damage")
	sim2.apply_damage(e1, c1, {"school": "true", "base": 100.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(_near(c1.hp, BattlegroundMode.DOWNED_HP - 100.0 * DeathmatchMode.BRAWL_DAMAGE * BattlegroundMode.DOWNED_TAKEN, 0.01), "a downed hero takes half damage (%.1f left)" % c1.hp)
	sim2.apply_damage(e1, c1, {"school": "true", "base": (c1.hp - 1.0) / (DeathmatchMode.BRAWL_DAMAGE * BattlegroundMode.DOWNED_TAKEN), "frozen": true}, {"source_type": "ABILITY"})
	_check(c1.alive and _near(c1.hp, 1.0, 0.01), "downed health takes damage (1 left)")
	var standing_hp: float = c2.hp
	sim2.apply_damage(e1, c2, {"school": "true", "base": 100.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(_near(standing_hp - c2.hp, 100.0 * DeathmatchMode.BRAWL_DAMAGE, 0.01), "a standing hero takes full damage (control)")
	sim2.apply_damage(e1, c1, {"school": "true", "base": 5.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(not c1.alive and str(br2.hstats[c1.idx].death_cause) == "kill", "downed health at 0 kills (finish)")
	sim2.dispose()


# Zone damage on a downed hero is halved as well (DOWNED_TAKEN).
func _downed_zone() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br: BattlegroundMode = sim.battleground
	var z: BrZone = br.zone
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	_kill_hit(sim, b1, a1)
	sim.time = z.shrink_end[1] + 1.0
	var out: Vector2 = Vector2.INF
	for k in 16:
		var p: Vector2 = z.centers[1] + Vector2.from_angle(TAU * float(k) / 16.0) * (z.radii[1] + 220.0)
		if sim.arena.is_walkable(p, 30.0) and sim.arena.resolve_circle(p, sim.radius(a1)).distance_to(z.centers[1]) > z.radii[1] + 100.0:
			out = sim.arena.resolve_circle(p, sim.radius(a1))
			break
	_check(out != Vector2.INF, "found a spot outside the first circle")
	a1.pos = out
	a2.pos = sim.arena.resolve_circle(z.centers[1], sim.radius(a2))
	b1.pos = sim.arena.resolve_circle(z.centers[1] + Vector2(300.0, 0.0), sim.radius(b1))
	br.downed[a1.idx]["bleed_at"] = sim.time + 30.0
	var hp0: float = a1.hp
	_steps(sim, 2.0)
	var expect: float = sim.max_hp(a1) * z.dps[1] * 2.0 * BattlegroundMode.DOWNED_TAKEN
	_check(br.is_downed(a1) and _near(hp0 - a1.hp, expect, sim.max_hp(a1) * z.dps[1] * 0.3), "zone damage on a downed hero is halved (lost %.1f, expected ~%.1f)" % [hp0 - a1.hp, expect])
	sim.dispose()


# ------------------------------------------------------------------ revive

func _revive() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	_kill_hit(sim, b1, a1)
	# Heal block on the downed hero must not stop the revive.
	sim.apply_status(b1, a1, {"status": "healReduction", "magnitude": 1.0, "duration": 30.0}, {})
	a2.pos = sim.arena.resolve_circle(a1.pos + Vector2(sim.radius(a1) + sim.radius(a2) + 70.0, 0.0), sim.radius(a2))
	_check(not br.start_revive(a2, a1), "no revive from 70 px (range 60)")
	a2.pos = sim.arena.resolve_circle(a1.pos + Vector2(sim.radius(a1) + sim.radius(a2) + 40.0, 0.0), sim.radius(a2))
	_check(not br.start_revive(b1, a1), "an enemy cannot revive")
	_check(br.start_revive(a2, a1), "teammate within 60 px starts the revive")
	_check(not sim.can_cast(a2) and not sim.can_basic(a2), "the reviver channels (no casts or attacks)")
	var rs: Array = _tick_events(sim, "BR_REVIVE_START")
	_check(not rs.is_empty() and bool(rs[0].gv[0]), "BR_REVIVE_START event")
	_steps(sim, 2.5)
	_check(_near(float(br.downed_info(a1).revive_progress), 0.5, 0.02), "revive progress ~0.5 at 2.5 s (%.3f)" % float(br.downed_info(a1).get("revive_progress", -1.0)))
	_steps(sim, 2.6)
	_check(a1.alive and not br.is_downed(a1), "revived after 5 s")
	_check(_near(a1.hp, sim.max_hp(a1) * 0.25, 0.5), "revived at 25%% health despite heal block (%.1f of %.1f)" % [a1.hp, sim.max_hp(a1)])
	_check(int(br.hstats[a2.idx].revives) == 1 and not br.is_reviving(a2) and sim.can_cast(a1), "revive counted; both act again")
	_check(not _events(sim, "BR_REVIVED").is_empty(), "BR_REVIVED event")
	# Interruptions: damage to the reviver, leaving the range, hard CC.
	for why in ["damage", "range", "cc"]:
		_kill_hit(sim, b1, a1)
		a2.pos = sim.arena.resolve_circle(a1.pos + Vector2(sim.radius(a1) + sim.radius(a2) + 30.0, 0.0), sim.radius(a2))
		a2.motion = null
		sim.remove_statuses_where(a2, func(st): return sim.is_cc_type(st.type))
		var ok: bool = br.start_revive(a2, a1)
		_steps(sim, 1.0)
		match why:
			"damage":
				sim.apply_damage(b1, a2, {"school": "true", "base": 10.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
			"range":
				a2.pos = sim.arena.resolve_circle(a1.pos + Vector2(260.0, 0.0), sim.radius(a2))
			"cc":
				sim.apply_status(b1, a2, {"status": "stun", "duration": 0.6}, {})
		sim.step()
		var cancels: Array = _events(sim, "BR_REVIVE_CANCEL").filter(func(e): return str(e.reason) == why)
		_check(ok and int(br.downed_info(a1).get("reviver_idx", 0)) == -1 and not cancels.is_empty() and float(br.downed_info(a1).revive_progress) == 0.0,
			"revive interrupted by %s" % why)
		# Leave the hero downed with a fresh bleed window for the next case.
		br.downed[a1.idx]["bleed_at"] = sim.time + 30.0
		a2.pos = sim.arena.resolve_circle(a1.pos + Vector2(sim.radius(a1) + sim.radius(a2) + 30.0, 0.0), sim.radius(a2))
		_steps(sim, 0.7)
		sim.remove_statuses_where(a2, func(st): return sim.is_cc_type(st.type))
		br.start_revive(a2, a1)
		_steps(sim, 5.1)
	_check(int(br.hstats[a2.idx].revives) == 4, "three more revives after the interruptions (%d)" % int(br.hstats[a2.idx].revives))
	# The phoenix revives instantly instead of a down.
	var bag: Array = br.inventory.get(a1.idx, [])
	bag.append("m_phoenix")
	br.inventory[a1.idx] = bag
	br._apply_item(a1, "m_phoenix")
	_kill_hit(sim, b1, a1)
	_check(a1.alive and not br.is_downed(a1) and not br.has_item(a1, "m_phoenix") and not _tick_events(sim, "DM_REVIVE").is_empty(), "phoenix: instant revive instead of downed")
	sim.dispose()


# ------------------------------------------------------ revive crawl contract

func _revive_crawl_contract() -> void:
	metrics["revive_crawl_contract"] = []
	for target_first in [false, true]:
		for moving in [false, true]:
			for profiled in [false, true]:
				_revive_crawl_case(target_first, moving, profiled)
	for why in ["damage", "cc", "target_forced_motion", "target_existing_motion"]:
		_revive_crawl_interrupt_case(why)


func _revive_crawl_open_spot(sim: BattleSim) -> Vector2:
	var a: Arena = sim.arena
	var c: Vector2 = sim.battleground.zone.centers[0]
	for ring in 30:
		var n: int = maxi(1, ring * 6)
		for k in n:
			var p: Vector2 = c + Vector2.from_angle(TAU * float(k) / float(n)) * 90.0 * float(ring)
			if not a.is_walkable(p, 30.0) or a.forest_at(p) >= 0:
				continue
			var ok: bool = true
			for d in 8:
				var q: Vector2 = p + Vector2.from_angle(TAU * float(d) / 8.0) * 370.0
				if not a.is_walkable(q, 30.0) or a.forest_at(q) >= 0 or a.segment_blocked(p, q, 30.0, Arena.MASK_UNITS) \
						or not a.line_of_sight(p, q, 2.0) or a.forest_occludes(p, q):
					ok = false
					break
			if ok:
				return p
	return Vector2.INF


func _revive_crawl_sim() -> BattleSim:
	var sim: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": "br_highland_ruins", "map_seed": 7,
		"seed": 20261003, "squad": 3, "teams": [["archer", "mage", "giant"], ["swordsman", "nitro", "sniper"]], "zone_speed": "normal"})
	_check(sim.heroes.size() == 6 and sim.battleground.team_members(0).size() == 3, "fixture has two valid trio rosters")
	sim.battleground.field.clear()
	sim.battleground._field_dirty = true
	var o: Vector2 = _revive_crawl_open_spot(sim)
	_check(o.is_finite(), "fixture has an open, deterministic site")
	if not o.is_finite():
		o = sim.battleground.zone.centers[0]
	for u in sim.heroes:
		u.pos = sim.arena.resolve_circle(o + Vector2(0.0, 300.0 + 200.0 * float(u.idx)), sim.radius(u))
		u.prev_pos = u.pos
		u.command = {}
		u.vel = Vector2.ZERO
	for t in sim.team_count:
		sim.controllers[t] = TeamController.new(sim, t)
	sim.time = 10.0
	# Keep the deterministic site in fixture metadata without changing AI data.
	sim.heroes[0].pos = o
	return sim


func _revive_crawl_events(sim: BattleSim, kind: String, victim: int) -> Array:
	var out: Array = []
	for ev in sim.log:
		if str(ev.type) == kind and int(ev.g) == victim:
			out.append(ev.duplicate(true))
	return out


func _revive_crawl_point(p: Vector2) -> Array:
	return [p.x, p.y]


func _revive_crawl_sample(sim: BattleSim, target: BUnit, reviver: BUnit) -> Dictionary:
	return {"tick": sim.tick, "time": sim.time, "target_pos": _revive_crawl_point(target.pos), "target_vel": _revive_crawl_point(target.vel),
		"reviver_pos": _revive_crawl_point(reviver.pos), "surface_gap": target.pos.distance_to(reviver.pos) - sim.radius(target) - sim.radius(reviver),
		"target_command": target.command.duplicate(true), "target_next_decision": target.next_decision_at,
		"downed": sim.battleground.is_downed(target), "reviving": sim.battleground.is_reviving(reviver)}


func _revive_crawl_case(target_first: bool, already_moving: bool, profiled: bool) -> void:
	var label: String = "crawl order=%s moving=%s profile=%s" % [str(target_first), str(already_moving), str(profiled)]
	var sim: BattleSim = _revive_crawl_sim()
	var br: BattlegroundMode = sim.battleground
	var o: Vector2 = sim.heroes[0].pos
	var target: BUnit = sim.heroes[0 if target_first else 1]
	var reviver: BUnit = sim.heroes[1 if target_first else 0]
	var enemy: BUnit = br.team_members(1)[0]
	sim.apply_damage(enemy, target, {"school": "true", "base": 100000.0, "frozen": true}, {"source_type": "ABILITY"})
	var speed: float = sim.stat(target, &"moveSpeed")
	var first_move: float = speed * BattleSim.DT if already_moving else speed / maxf(0.08, target.accel_time) * BattleSim.DT * BattleSim.DT
	# With target-first order it moves before the channel starts. Account for
	# exactly that first movement so BOTH orders legally start at the same edge.
	var gap: float = BattlegroundMode.REVIVE_RANGE - 0.05 - (first_move if target_first else 0.0)
	reviver.pos = o
	target.pos = o + Vector2(sim.radius(target) + sim.radius(reviver) + gap, 0.0)
	target.prev_pos = target.pos
	reviver.prev_pos = reviver.pos
	target.vel = Vector2.RIGHT * speed if already_moving else Vector2.ZERO
	target.command = {"kind": "move", "goal": target.pos + Vector2(120.0, 0.0), "key": "downed_crawl", "purpose": "fixture: prior crawl"}
	target.next_decision_at = sim.time + 0.3
	reviver.next_decision_at = sim.time
	var brain: ReviveCrawlFixtureBrain = ReviveCrawlFixtureBrain.new(sim, 0)
	brain.target_idx = target.idx
	brain.reviver_idx = reviver.idx
	brain.squad_intent = {"mode": "revive", "target": target.idx, "reviver": reviver.idx, "spot": target.pos, "since": sim.time}
	brain.member_goal[reviver.idx] = {"role": "reviver", "target": target.idx, "goal": target.pos, "reward": 120.0, "label": "fixture revive"}
	sim.controllers[0] = brain
	sim.profiling = profiled
	sim.start()
	var trace: Array = [_revive_crawl_sample(sim, target, reviver)]
	for i in 16:
		sim.step()
		trace.append(_revive_crawl_sample(sim, target, reviver))
	var starts: Array = _revive_crawl_events(sim, "BR_REVIVE_START", target.idx)
	var cancels: Array = _revive_crawl_events(sim, "BR_REVIVE_CANCEL", target.idx)
	_check(starts.size() == 1, label + ": exactly one real AI channel start")
	_check(cancels.is_empty(), label + ": cached crawl never cancels the channel")
	_check(br.is_reviving(reviver), label + ": channel remains active beyond 0.3s decision delay")
	for i in 150:
		sim.step()
	var done: Array = _revive_crawl_events(sim, "BR_REVIVED", target.idx)
	_check(done.size() == 1 and target.alive and not br.is_downed(target), label + ": full 5s channel completes")
	if done.size() == 1 and starts.size() == 1:
		_check(float(done[0].t) - float(starts[0].t) >= BattlegroundMode.REVIVE_TIME - 0.000001, label + ": never completes early")
	(metrics["revive_crawl_contract"] as Array).append({"label": label, "initial_gap": gap, "initial_speed": speed if already_moving else 0.0,
		"trace": trace, "starts": starts, "cancels": _revive_crawl_events(sim, "BR_REVIVE_CANCEL", target.idx), "completions": done})
	sim.dispose()


func _revive_crawl_interrupt_case(why: String) -> void:
	var sim: BattleSim = _revive_crawl_sim()
	var br: BattlegroundMode = sim.battleground
	var target: BUnit = sim.heroes[0]
	var reviver: BUnit = sim.heroes[1]
	var enemy: BUnit = sim.heroes[3]
	reviver.pos = target.pos + Vector2(sim.radius(target) + sim.radius(reviver) + 20.0, 0.0)
	sim.start()
	sim.apply_damage(enemy, target, {"school": "true", "base": 100000.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(br.start_revive(reviver, target), why + ": start succeeds")
	for i in 30:
		sim.step()
	match why:
		"damage":
			sim.apply_damage(enemy, reviver, {"school": "true", "base": 10.0, "frozen": true}, {"source_type": "BASIC_ATTACK", "basic": true})
		"cc":
			sim.apply_status(enemy, reviver, {"status": "stun", "duration": 0.6}, {})
		"target_forced_motion":
			sim.kits.begin_motion(target, target.pos + Vector2(-260.0, 0.0), 900.0, "knockback", {"source": enemy.idx})
		"target_existing_motion":
			br.cancel_revive(target.idx, "fixture_restart")
			sim.kits.begin_motion(target, target.pos + Vector2(-260.0, 0.0), 900.0, "knockback", {"source": enemy.idx})
			var prior: ST.Motion = target.motion
			_check(br.start_revive(reviver, target) and target.motion == prior, why + ": starting never erases forced motion")
	for i in 12:
		sim.step()
	var reason: String = "range" if why.begins_with("target_") else why
	var found: bool = false
	for ev in _revive_crawl_events(sim, "BR_REVIVE_CANCEL", target.idx):
		if str(ev.reason) == reason:
			found = true
	_check(found and not br.is_reviving(reviver) and br.is_downed(target), why + ": legitimate interruption still cancels")
	(metrics["revive_crawl_contract"] as Array).append({"label": why, "cancels": _revive_crawl_events(sim, "BR_REVIVE_CANCEL", target.idx)})
	sim.dispose()


# ------------------------------------------------------------------ elimination

func _elimination() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"], ["nitro", "sniper"]], 2)
	var br: BattlegroundMode = sim.battleground
	var probes: Array = []
	for t in sim.team_count:
		var c: TeamController = TeamController.new(sim, t)
		sim.controllers[t] = c
		probes.append(c)
	var a1: BUnit = br.team_members(0)[0]
	var a2: BUnit = br.team_members(0)[1]
	var b1: BUnit = br.team_members(1)[0]
	_kill_hit(sim, b1, a1)
	_kill_hit(sim, b1, a2)
	_check(not a2.alive and not br.is_downed(a2), "the last standing member dies (no down)")
	_check(br.is_eliminated(0) and int(br.placement.get(0, 0)) == 3 and br.elim_time.has(0), "team out with placement 3 of 3")
	var out_ev: Array = _tick_events(sim, "BR_TEAM_OUT")
	_check(out_ev.size() == 1 and int(out_ev[0].team) == 0 and int(out_ev[0].place) == 3 and bool(out_ev[0].public) and bool(out_ev[0].gv[2]), "BR_TEAM_OUT{team, place} is public")
	sim.step()
	_check(not a1.alive and str(br.hstats[a1.idx].death_cause) == "team_wipe", "downed member dies when the team is eliminated")
	_check(int(br.hstats[b1.idx].kills) == 2 and int(br.hstats[b1.idx].knocks) == 1, "knocker credited for the wiped member (2 kills, 1 knock)")
	_check(sim.controllers[0] == null and sim.controllers[1] != null, "eliminated team's controller detached")
	_steps(sim, 8.0)
	_check(not a1.alive and not a2.alive, "no respawn")
	_check(br.alive_team_count() == 2 and br.alive_hero_count() == 4, "2 teams / 4 heroes left")
	# The next elimination ends the match: last team standing wins.
	for u in br.team_members(2):
		_kill_hit(sim, b1, u)
	sim.step()
	_check(sim.state == BattleSim.FINISHED and br.winner_team == 1 and sim.winner == 1 and int(br.placement[1]) == 1 and int(br.placement[2]) == 2,
		"last team standing wins; placements 1/2/3 (%s)" % str(br.placement))
	_check(sim.finish_reason == "battleground_last", "finish reason battleground_last")
	var res: Dictionary = sim.result()
	_check(res.has("battleground") and res.has("deathmatch") and (res.deathmatch.ranking as Array).size() == 6, "result has battleground and ranking rows")
	_check(int((res.deathmatch.ranking as Array)[0].team) == 1, "ranking starts with the winning team")
	sim.dispose()
	# Solo: death = elimination, never downed.
	var solo: BattleSim = _idle([["archer"], ["giant"], ["mage"]], 1)
	var sb: BattlegroundMode = solo.battleground
	var v: BUnit = sb.team_members(0)[0]
	_kill_hit(solo, sb.team_members(1)[0], v)
	_check(not v.alive and not sb.is_downed(v) and sb.is_eliminated(0) and int(sb.placement[0]) == 3, "solo: death eliminates at once (placement 3)")
	_check(sb.team_label(6) == "P7" and sb.player_no(sb.team_members(2)[0]) == 3, "solo labels P<n>; player numbers 1..N")
	solo.dispose()


# ------------------------------------------------------------------ items

func _items_rules() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br: BattlegroundMode = sim.battleground
	var a1: BUnit = br.team_members(0)[0]
	var b1: BUnit = br.team_members(1)[0]
	for id in ["c_blade", "r_fang", "e_guard"]:
		var bag: Array = br.inventory.get(a1.idx, [])
		bag.append(id)
		br.inventory[a1.idx] = bag
		br._apply_item(a1, id)
	_kill_hit(sim, b1, a1)
	_check((br.inventory[a1.idx] as Array).size() == 3, "a downed hero keeps its items")
	var before: int = br.field.size()
	sim.apply_damage(b1, a1, {"school": "true", "base": 1000.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(not a1.alive and br.field.size() == before + 3 and (br.inventory[a1.idx] as Array).is_empty(), "final death drops all 3 items (%d -> %d)" % [before, br.field.size()])
	var dropped: Array = br.field.filter(func(it): return int(it.dropped) == a1.idx)
	_check(dropped.size() == 3, "dropped items carry the dead hero's index")
	# Pickups: 3 slots, a better item swaps (default rule without a controller).
	var a2: BUnit = br.team_members(0)[1]
	br.field.clear()
	br._field_dirty = true
	for id in ["c_blade", "c_boots", "c_belt"]:
		var bag2: Array = br.inventory.get(a2.idx, [])
		bag2.append(id)
		br.inventory[a2.idx] = bag2
		br._apply_item(a2, id)
	br.uid_seq += 1
	br.field.append({"uid": br.uid_seq, "item": "l_aegis", "pos": a2.pos, "t": sim.time, "dropped": -1})
	br._field_dirty = true
	sim.step()
	_check(br.has_item(a2, "l_aegis") and (br.inventory[a2.idx] as Array).size() == 3, "pickup into a full bag swaps (3 slots)")
	_check(not _tick_events(sim, "BR_ITEM_SWAP").is_empty() and br.field.size() == 1, "BR_ITEM_SWAP; the swapped item lies on the field")
	_check(int(br.hstats[a2.idx].items_picked) == 1, "hstats counts the pickup")
	sim.dispose()
	# A downed hero picks nothing up (its teammate still stands).
	var sim3: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br3: BattlegroundMode = sim3.battleground
	var d1: BUnit = br3.team_members(0)[0]
	_kill_hit(sim3, br3.team_members(1)[0], d1)
	br3.uid_seq += 1
	br3.field.append({"uid": br3.uid_seq, "item": "l_heart", "pos": d1.pos, "t": sim3.time, "dropped": -1})
	br3._field_dirty = true
	_steps(sim3, 0.5)
	_check(br3.is_downed(d1) and br3.field.size() == 1 and int(br3.hstats[d1.idx].items_picked) == 0, "no pickups while downed")
	sim3.dispose()


# ------------------------------------------------------------------ zone

func _zone_rules() -> void:
	var sim: BattleSim = _idle([["archer"], ["giant"], ["mage"]], 1)
	var br: BattlegroundMode = sim.battleground
	var z: BrZone = br.zone
	var h: BUnit = br.team_members(0)[0]
	var e: BUnit = br.team_members(1)[0]
	var m: BUnit = br.team_members(2)[0]
	# A brush patch outside the first circle for h; e stands just outside it.
	var spot: Vector2 = Vector2.INF
	var watch: Vector2 = Vector2.INF
	for k in sim.arena.forest_x.size():
		var fc: Vector2 = Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k])
		if fc.distance_to(z.centers[1]) < z.radii[1] + 250.0 or not sim.arena.is_walkable(fc, 20.0):
			continue
		var patch: int = sim.arena.forest_at(fc)
		for a in 16:
			var q: Vector2 = fc + Vector2.from_angle(TAU * a / 16.0) * (sim.arena.forest_r[k] + 240.0)
			if sim.arena.is_walkable(q, 30.0) and sim.arena.forest_at(q) < 0 and sim.arena.line_of_sight(q, fc, 4.0) and not sim.arena.forest_occludes(q, fc) and patch >= 0:
				spot = fc
				watch = q
				break
		if spot != Vector2.INF:
			break
	_check(spot != Vector2.INF, "found a brush patch outside the first circle")
	h.pos = spot
	e.pos = watch
	m.pos = sim.arena.resolve_circle(z.centers[1], sim.radius(m))
	h.last_combat_time = -999.0
	h.last_damage_time = -999.0
	sim.time = z.announce_at[1] - 0.05
	sim.step()
	sim.step()
	var ann: Array = _tick_events(sim, "BR_ZONE_ANNOUNCE")
	ann.append_array(_events(sim, "BR_ZONE_ANNOUNCE"))
	_check(not ann.is_empty() and int(ann[0].phase) == 1 and bool(ann[0].public) and bool(ann[0].gv[0]), "BR_ZONE_ANNOUNCE{phase 1} at the announce time, public")
	sim.time = z.shrink_end[1] - 0.04
	h.hp = sim.max_hp(h)
	var hp0: float = h.hp
	sim._update_visibility()
	var hidden_before: bool = not sim.observes(e, h)
	_steps(sim, 2.0)
	var lost: float = hp0 - h.hp
	var expect: float = sim.max_hp(h) * z.dps[1] * 2.0
	_check(_near(lost, expect, sim.max_hp(h) * z.dps[1] * 0.55), "zone: 1%%/s true damage of max HP in 0.5 s ticks (lost %.1f, expected ~%.1f)" % [lost, expect])
	_check(h.last_combat_time < 0.0 and h.last_damage_time < 0.0, "zone damage resets neither the combat nor the damage timer")
	sim._update_visibility()
	_check(hidden_before and not sim.observes(e, h), "zone damage does not reveal a hero in brush")
	var sh: Array = _events(sim, "BR_ZONE_SHRINK")
	_check(not sh.is_empty() and bool(sh[0].public), "BR_ZONE_SHRINK is public")
	# Positive control: ordinary environment damage does reveal.
	sim.env._env_damage(h, {"type": "lava", "damage": 1.0, "school": "true", "id": "probe"})
	sim._update_visibility()
	_check(sim.observes(e, h), "control: ordinary hazard damage reveals (test sensitivity)")
	# Out-of-combat regeneration keeps running in the zone (timers untouched).
	# Regeneration pauses outside the circle and resumes at once inside it
	# (the out-of-combat timer was never reset by the zone).
	h.last_combat_time = -999.0
	h.last_damage_time = -999.0
	var regen_out: int = 0
	var regen_in: int = 0
	for i in 60:
		if i == 30:
			h.pos = sim.arena.resolve_circle(z.centers[1] + Vector2(60.0, 0.0), sim.radius(h))
		sim.step()
		for ev in sim.tick_events:
			if str(ev.type) == "HEAL_APPLIED" and int(ev.g) == h.idx and str(ev.get("source_type", "")) == "REGEN":
				if i < 30:
					regen_out += 1
				else:
					regen_in += 1
	_check(regen_out == 0, "no regeneration outside the circle during a damage phase (%d)" % regen_out)
	_check(h.last_combat_time < 0.0 and regen_in >= 3, "regeneration resumes at once back inside the circle (%d ticks in 1 s)" % regen_in)
	h.pos = spot
	var regen: int = regen_in
	# Zone death credit: the last enemy damager within 10 s.
	sim.apply_damage(e, h, {"school": "true", "base": 10.0, "frozen": true}, {"source_type": "ABILITY"})
	h.hp = 1.0
	_steps(sim, 0.6)
	_check(not h.alive and str(br.hstats[h.idx].death_cause) == "zone", "zone death (cause zone)")
	_check(int(br.hstats[e.idx].kills) == 1, "zone death credits the last damager within 10 s")
	var feed: Array = br.kill_feed.filter(func(f): return str(f.kind) == "kill" and int(f.victim) == h.idx)
	_check(feed.size() == 1 and int(feed[0].killer) == e.idx and str(feed[0].cause) == "zone", "kill feed: zone death with credit")
	# Without a recent damager: no credit.
	m.pos = e.pos
	e.pos = spot
	e.hp = 1.0
	br.recent_hits.erase(e.idx)
	_steps(sim, 0.6)
	_check(not e.alive and str(br.hstats[e.idx].death_cause) == "zone" and int(br.hstats[m.idx].kills) == 0, "zone death without a recent damager credits nobody")
	metrics["zone_tick_loss"] = snappedf(lost, 0.01)
	metrics["zone_regen_ticks"] = regen
	sim.dispose()


# ------------------------------------------------------------------ 600 s cap

func _time_cap() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"], ["nitro", "sniper"]], 2, [], 4242, {"max_time": 3.0})
	var br: BattlegroundMode = sim.battleground
	var dflt: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": MAP, "map_seed": MAP_SEED, "seed": 3, "teams": [["archer"], ["mage"]]})
	_check(dflt.max_time == 600.0, "default time cap 600 s")
	dflt.dispose()
	# Team 0: one member downed (2 in play). Team 1: both up, lower health.
	# Team 2: one dead (1 in play, full health).
	_kill_hit(sim, br.team_members(1)[0], br.team_members(0)[0])
	for u in br.team_members(1):
		u.hp = sim.max_hp(u) * 0.2
	_kill_hit(sim, br.team_members(0)[1], br.team_members(2)[0])
	sim.apply_damage(br.team_members(0)[1], br.team_members(2)[0], {"school": "true", "base": 1000.0, "frozen": true}, {"source_type": "ABILITY"})
	_check(not br.team_members(2)[0].alive and br.team_alive(2) == 1, "setup: team 2 has one member left")
	var hp0: float = 0.0
	var hp1: float = 0.0
	for u in br.team_members(0):
		hp0 += u.hp
	for u in br.team_members(1):
		hp1 += u.hp
	_steps(sim, 3.2)
	_check(sim.state == BattleSim.FINISHED and sim.finish_reason == "battleground_time", "the cap ends the match")
	var expect_first: int = 0 if hp0 > hp1 else 1
	_check(int(br.placement[expect_first]) == 1 and int(br.placement[1 - expect_first]) == 2 and int(br.placement[2]) == 3,
		"cap ranking: alive heroes, then total health (%s; hp %.0f vs %.0f)" % [str(br.placement), hp0, hp1])
	_check(br.winner_team == expect_first, "cap winner is placement 1")
	sim.dispose()


# ------------------------------------------------------------------ contract

func _contract() -> void:
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"]], 2)
	var br: BattlegroundMode = sim.battleground
	for key in ["squad", "team_count", "placement", "elim_time", "winner_team", "hstats", "zone", "inventory", "field", "kill_feed"]:
		_check(key in br, "contract field %s" % key)
	for fn in ["team_members", "team_alive", "alive_team_count", "alive_hero_count", "player_no", "team_label", "is_downed", "downed_info", "zone_view"]:
		_check(br.has_method(fn), "contract function %s" % fn)
	var keys: Array = br.hstats[br.team_members(0)[0].idx].keys()
	for k in ["kills", "knocks", "revives", "damage", "items_picked", "survival", "death_cause"]:
		_check(keys.has(k), "hstats has %s" % k)
	var view: Dictionary = br.zone_view()
	_check(view.keys().size() == br.zone.public_view(sim.time).keys().size() and view.has("next_known"), "zone_view() is zone.public_view(sim.time)")
	_check(br.team_label(2) == "3팀" and br.team_alive(0) == 2 and br.alive_team_count() == 2 and br.alive_hero_count() == 4, "labels and counts (duo)")
	_check(br.downed_info(br.team_members(0)[0]).is_empty() and not br.is_downed(br.team_members(0)[0]), "downed_info is empty for a standing hero")
	sim.dispose()
	# The battle runner starts the battleground from the §3.5 config.
	var runner: BattleRunner = BattleRunner.new()
	runner.start({"ruleset": "battleground", "mode": "battleground", "arena_id": MAP, "seed": 31, "squad": 2,
		"teams": [["archer", "mage"], ["giant", "nitro"]], "zone_speed": "fast", "max_time": 600, "ai": "tactician"})
	_check(runner.sim != null and runner.sim.is_battleground() and runner.sim.battleground.zone.speed == "fast", "BattleRunner starts the battleground config")
	_check(runner.sim.controllers[0] is BattlegroundSquadBrain and runner.sim.controllers[1] is BattlegroundSquadBrain, "duo teams get the squad brain")
	runner.warp(5.0)
	_check(runner.sim.time >= 5.0 and runner.sim.state == BattleSim.RUNNING, "runner plays the battleground")
	runner.dispose_sim()
	runner.free()
	var solo: BattleSim = _br([["archer"], ["giant"]], 1)
	for t in solo.team_count:
		solo.controllers[t] = AIFactory.make("tactician", solo, t)
	_check(solo.controllers[0] is BattlegroundSoloBrain, "solo heroes get the solo brain")
	solo.dispose()


# ------------------------------------------------------------------ information

func _information() -> void:
	# Static scan: the brains read the zone only through zone_view().
	for path in ["res://scripts/ai/battleground_brain.gd", "res://scripts/ai/battleground_squad_brain.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		var leaks: Array = []
		for pat in ["zone.centers", "zone.radii", "zone.center_at", "zone.radius_at", "zone.outside(", ".announce_at", "zone.shrink_", "zone.dps["]:
			if src.contains(pat):
				leaks.append(pat)
		_check(leaks.is_empty(), "%s reads the zone only via zone_view (%s)" % [path.get_file(), str(leaks)])
	# Differential: change only circles 2+ (never public before ~195 s) and
	# the AI plays the first 60 s identically.
	var sig_a: Array = _ai_trace(6, 1, 61, 60.0, false)
	var sig_b: Array = _ai_trace(6, 1, 61, 60.0, true)
	_check(sig_a == sig_b, "hidden future circles do not change AI play (first 60 s)")
	# Downed info is not leaked: a far team's intel has no downed status.
	var sim: BattleSim = _idle([["archer", "mage"], ["swordsman", "giant"], ["nitro", "sniper"]], 2)
	var br: BattlegroundMode = sim.battleground
	for u in br.team_members(2):
		u.pos = sim.arena.resolve_circle(u.pos + Vector2(0.0, 2000.0), sim.radius(u))
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	sim._update_visibility()
	var a1: BUnit = br.team_members(0)[0]
	var k: int = 0
	for u in br.team_members(1):
		u.pos = sim.arena.resolve_circle(a1.pos + Vector2(120.0 + 60.0 * k, 40.0), sim.radius(u))
		k += 1
	sim._update_visibility()
	_kill_hit(sim, br.team_members(1)[0], a1)
	sim._update_visibility()
	for t2 in sim.team_count:
		(sim.controllers[t2] as BattlegroundSquadBrain).intel.observe()
	var far_brain: BattlegroundSquadBrain = sim.controllers[2]
	var far_belief: TeamIntel.EnemyBelief = far_brain.intel.enemies.get(a1.idx)
	_check(far_belief != null and not far_belief.visible and not far_belief.has_status("downed"), "a team that does not see the hero learns nothing of its down")
	var near_brain: BattlegroundSquadBrain = sim.controllers[1]
	var near_belief: TeamIntel.EnemyBelief = near_brain.intel.enemies.get(a1.idx)
	_check(near_belief != null and near_belief.visible and near_belief.has_status("downed"), "an observing team sees the down")
	# Item knowledge: a brain knows only items it has seen.
	var s2: BattleSim = _br([["archer"], ["giant"], ["mage"], ["nitro"]], 1, 77)
	for t in s2.team_count:
		s2.controllers[t] = AIFactory.make("tactician", s2, t)
	s2.start()
	_steps(s2, 3.0)
	var unseen_known: int = 0
	var total_known: int = 0
	for t in s2.team_count:
		var b: BattlegroundSoloBrain = s2.controllers[t]
		var hero: BUnit = b.hero
		for uid in b.known_items:
			total_known += 1
			var p: Vector2 = b.known_items[uid].pos
			if p.distance_to(hero.pos) > s2.sensor_range(hero) + 3.0 * 140.0:
				unseen_known += 1
	_check(unseen_known == 0, "solo brains know only items they have seen (%d of %d known items out of sight range)" % [unseen_known, total_known])
	_check(total_known < s2.battleground.field.size() * s2.team_count, "item positions are not all public")
	metrics["known_items_after_3s"] = total_known
	sim.dispose()
	s2.dispose()


# Per-second signature of an AI match: unit states and the event count.
func _ai_trace(n: int, squad: int, seed_v: int, secs: float, alter_future: bool) -> Array:
	var teams: Array = []
	var pool: Array = DB.ids()
	for i in n:
		var team: Array = []
		for k in squad:
			team.append(pool[(i * 3 + k * 7 + seed_v) % pool.size()])
		teams.append(team)
	var sim: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": MAP, "map_seed": MAP_SEED, "seed": seed_v, "squad": squad,
		"teams": teams, "zone_speed": "fast"})
	if alter_future:
		var z: BrZone = sim.battleground.zone
		for k in range(2, BrZone.PHASES + 1):
			z.centers[k] = z.centers[1]
	for t in sim.team_count:
		sim.controllers[t] = AIFactory.make("tactician", sim, t)
	sim.start()
	var out: Array = []
	var events: int = 0
	while sim.time < secs and sim.state == BattleSim.RUNNING:
		sim.step()
		events += sim.tick_events.size()
		if sim.tick % 30 == 0:
			var row: String = "%d:%d" % [sim.tick, events]
			for u in sim.heroes:
				row += "|%d,%.2f,%.2f,%.1f" % [int(u.alive), u.pos.x, u.pos.y, u.hp]
			out.append(row.sha256_text())
	sim.dispose()
	return out


# ------------------------------------------------------------------ determinism

func _signature(sim: BattleSim) -> String:
	var row: String = "%d" % sim.tick
	for u in sim.units:
		row += "|%s,%d,%.3f,%.3f,%.3f" % [u.id, int(u.alive), u.pos.x, u.pos.y, u.hp]
	row += "|%d|%s" % [sim.battleground.field.size(), str(sim.battleground.placement)]
	return row.sha256_text()


func _determinism() -> void:
	var runs: Array = []
	for rep in 2:
		var t0: int = Time.get_ticks_msec()
		var teams: Array = [["archer", "mage"], ["giant", "nitro"], ["sniper", "aphrodite"], ["werewolf", "hermes"]]
		var sim: BattleSim = BattleSim.new({"ruleset": "battleground", "arena_id": MAP, "map_seed": MAP_SEED, "seed": 2026,
			"squad": 2, "teams": teams, "zone_speed": "fast"})
		for t in sim.team_count:
			sim.controllers[t] = AIFactory.make("tactician", sim, t)
		sim.start()
		var sigs: Dictionary = {}
		while sim.state == BattleSim.RUNNING:
			sim.step()
			if sim.tick == 1800 or sim.tick == 3600:
				sigs[sim.tick] = _signature(sim)
		runs.append({"sigs": sigs, "placement": sim.battleground.placement.duplicate(), "time": sim.time, "winner": sim.winner,
			"hstats": JSON.stringify(sim.battleground.hstats), "ms": Time.get_ticks_msec() - t0})
		sim.dispose()
	_check(runs[0].sigs.has(1800) and runs[0].sigs.get(1800) == runs[1].sigs.get(1800), "same seed: identical state at t=60")
	_check(runs[0].sigs.get(3600, "a") == runs[1].sigs.get(3600, "b"), "same seed: identical state at t=120")
	_check(str(runs[0].placement) == str(runs[1].placement) and runs[0].time == runs[1].time and runs[0].winner == runs[1].winner, "same seed: identical placements and finish (%s at %.1f s)" % [str(runs[0].placement), runs[0].time])
	_check(runs[0].hstats == runs[1].hstats, "same seed: identical per-hero stats")
	_check(int(runs[0].placement.size()) == 4, "the reduced duo match ranks all 4 teams")
	metrics["determinism_match_s"] = snappedf(float(runs[0].time), 0.1)
	metrics["determinism_run_ms"] = [runs[0].ms, runs[1].ms]
