class_name DeathmatchBrain
extends TacticianBrain

# Free-for-all brain for one hero. The inherited tactician still aims, dodges
# and chooses skills; this layer decides where the hero should be and what it
# is fighting for. Every option is priced in one currency, expected kills, so
# a field item, a duel, a chase and a retreat can be compared directly:
#   fight  = P(win)·(1 + items on the body) − P(lose)·(cost of dying)
#   evade  = P(caught)·(a worse fight)          — only worth it when P(win) is low
#   item   = how much this item improves THIS hero, minus the walk and danger
# P(win) compares time-to-kill in both directions, counting opponents who could
# join and range/speed matchups. The hero knows only what it observes, public
# facts (item positions, scoreboard, respawn notices) and the noise of fights
# within earshot.
#
# Every AI kind (tactician, tactician14, classic) plays deathmatch with this
# brain: AIFactory maps them all here, so comparing kinds in the developer lab
# compares identical AIs. To compare behaviour meaningfully use the config
# form, e.g. "tactician{dm153=0}" replays the V1.5.2 intent rules below
# (escape rule, threat handling, public noise, per-life reset, forest
# recovery hysteresis) against the default V1.5.3 rules.
#
# V1.5.3 rules (cfg "dm153", default 1):
#  * A pursuit counts shield-absorbed hits as progress, a landed hit clears an
#    "escaped" mark, and a target that stays in sight within reach+150 is never
#    marked escaped. The patience window is max(6 s, 2.5 attack intervals).
#  * Under close threat, walking to the fountain is dropped when the pursuer
#    kills us before we arrive, and ignoring the threat (roam, loot, listen,
#    recover) always scores below evading it.
#  * Public signals become "noises": an item vanishing from the public field,
#    an item appearing where a hero dropped it, a fountain's public ready time
#    jumping. They feed "listen" and the search for opponents (2-3 players
#    mostly search, not fight).
#  * Per-life memory (escape marks, pursuit timers, fight partners, last
#    attacker) is reset when this hero respawns; marks on an opponent are
#    dropped when the public kill feed reports its death.
#  * Hiding in a forest to regenerate keeps going until 80% health once begun.

const INTENT_INTERVAL := 0.5
const TRACK_TIME := 5.0
const HEAR_RANGE := 950.0
const KILL_VALUE := 100.0
const DEATH_COST := 0.4
const LABELS := {"loot": "보급", "hunt": "사냥", "chase": "추격", "evade": "회피", "recover": "회복", "roam": "탐색", "listen": "소음 추적", "dead": "재출전 대기"}
const ESCAPE_REACH_PAD := 150.0      # still in sight and this close: not escaped
const ESCAPE_CLEAR_PAD := 100.0      # an escaped target back inside reach+100 is hunted again
const FIGHT_NOISE_TTL := 3.0
const PUBLIC_NOISE_TTL := 12.0
const PUBLIC_NOISE_MAX := 12
const HIDE_UNTIL := 0.8              # forest recovery, once begun, lasts until this health

var hero: BUnit = null
var intent: Dictionary = {"mode": "roam", "goal": Vector2.INF, "since": -99.0, "score": 0.0, "reason": "", "target": -1, "uid": -1}
var next_intent_at: float = 0.0
var intent_log: Array = []
var roam_goal: Vector2 = Vector2.INF
var roam_until: float = 0.0
var last_pick_reason: String = ""
var hunt_track: Dictionary = {}   # target idx -> time the pursuit started
var last_attacker: int = -1
var last_attacked_at: float = -99.0
var last_hit_on: Dictionary = {}  # enemy idx -> time we last damaged it
var fight_with: Dictionary = {}   # enemy idx -> last damage exchanged either way
var escaped: Dictionary = {}      # target idx -> time until which it is not chased
var noises: Array = []            # {"pos", "t"} fights heard nearby
var public_noise: Array = []      # {"pos", "t", "kind"} public map signals (items, fountains)
var contact_on: Dictionary = {}   # pursued target idx -> last time it was seen within reach+150
const SWEEP_CELL := 400.0
var swept: Dictionary = {}        # Vector2i cell -> last time our own vision covered it
var _field_seen: Dictionary = {}  # public field: uid -> position at the last scan
var _field_scanned: bool = false
var _fountain_ready: Dictionary = {} # public fountain id -> ready time at the last scan
var _new_rules: int = -1          # cached cfg "dm153" (-1 = not read yet)


func _init(s: BattleSim, t: int) -> void:
	super(s, t)
	label = "데스매치 AI"
	for u in s.heroes:
		if u.team == t:
			hero = u
	rng.seed = s.seed_value * 29 + t * 11 + 3
	if not cfg.has("dm153"):
		cfg["dm153"] = 1.0


# V1.5.3 intent rules on (default) or the V1.5.2 rules for lab comparison.
func v153() -> bool:
	if _new_rules < 0:
		_new_rules = 1 if float(cfg.get("dm153", 1.0)) > 0.5 else 0
	return _new_rules == 1


# Patience for a pursuit that lands nothing: six seconds, or two and a half
# attack intervals for a slow attacker (the interval as kits.gd computes it).
func pursuit_window() -> float:
	if hero == null or not v153():
		return 6.0
	return maxf(6.0, 2.5 / maxf(0.2, sim.stat(hero, &"attackSpeed")))


# A new life starts without the grudges and timers of the previous one.
func reset_life_memory() -> void:
	escaped.clear()
	hunt_track.clear()
	fight_with.clear()
	last_hit_on.clear()
	contact_on.clear()
	last_attacker = -1
	last_attacked_at = -99.0
	roam_goal = Vector2.INF
	roam_until = 0.0
	next_intent_at = sim.time if sim else 0.0


func _hero_of(idx: int) -> BUnit:
	var u: BUnit = sim.u_at(idx)
	var guard: int = 0
	while u != null and not u.is_hero and guard < 6:
		u = sim.u_at(u.owner_idx)
		guard += 1
	return u


func pre_tick(s: BattleSim) -> void:
	if hero:
		var fix: bool = v153()
		var codes: PackedByteArray = s.ai_event_codes(s.ai_events)
		for ei in s.ai_events.size():
			# Respawns, kills, health damage and shield hits only (B-PERF2 index).
			var code: int = codes[ei]
			if code != 1 and code != 20 and code != 15 and code != 16:
				continue
			var ev = s.ai_events[ei]
			var ty: String = str(ev.type)
			if fix and (ty == "HERO_RESPAWNED" or ty == "DM_KILL"):
				_on_life_event(ty, ev)
				continue
			# Damage a shield swallowed is still a landed hit (V1.5.2 ignored it).
			if ty != "HEALTH_DAMAGED" and not (fix and ty == "SHIELD_ABSORBED"):
				continue
			var src: BUnit = _hero_of(int(ev.s))
			var tgt: int = int(ev.g)
			if src == hero and tgt != hero.idx:
				var tu: BUnit = s.u_at(tgt)
				if tu and tu.is_hero:
					last_hit_on[tgt] = float(ev.t)
					fight_with[tgt] = float(ev.t)
					if fix:
						escaped.erase(tgt)
				continue
			if tgt == hero.idx:
				if src and src != hero and src.team != team and bool((ev.sv as Array)[team]):
					last_attacker = src.idx
					last_attacked_at = float(ev.t)
					fight_with[src.idx] = float(ev.t)
				continue
			# Somebody else's fight within earshot: a chance to arrive third.
			if hero.alive and ev.has("pos"):
				var np: Vector2 = ev.pos
				if np.distance_to(hero.pos) < HEAR_RANGE:
					noises.append({"pos": np, "t": float(ev.t)})
		if noises.size() > 24:
			noises = noises.slice(noises.size() - 24)
	super.pre_tick(s)


# Our own respawn starts a new life; an opponent's death in the public kill
# feed ends whatever pursuit or escape mark we held on it.
func _on_life_event(ty: String, ev: Dictionary) -> void:
	if ty == "HERO_RESPAWNED":
		if int(ev.g) == hero.idx:
			reset_life_memory()
		return
	var victim: int = int(ev.g)
	if victim == hero.idx:
		return
	escaped.erase(victim)
	hunt_track.erase(victim)
	contact_on.erase(victim)
	fight_with.erase(victim)


# Public map state that betrays a hero without showing it: an item vanished
# from the field (picked up), an item appeared that a hero dropped (swap or
# death), a public fountain's ready time jumped (somebody drank). Only the
# position and the time are used, never who it was.
func _scan_public_signals() -> void:
	var dm: DeathmatchMode = sim.deathmatch
	if dm == null:
		return
	var now: Dictionary = {}
	for it in dm.field:
		var uid: int = int(it.uid)
		var p: Vector2 = it.pos
		now[uid] = p
		# Our own drops (swap or death) betray nobody else.
		var dropper: int = int(it.get("dropped", -1))
		if _field_scanned and not _field_seen.has(uid) and dropper >= 0 and dropper != hero.idx and p.distance_to(hero.pos) > 90.0:
			_add_public_noise(p, "drop")
	if _field_scanned:
		for uid in _field_seen:
			if now.has(uid):
				continue
			var gone: Vector2 = _field_seen[uid]
			if gone.distance_to(hero.pos) > 90.0:
				_add_public_noise(gone, "item")
	_field_seen = now
	_field_scanned = true
	if sim.env and sim.env.enabled:
		for f: Dictionary in sim.env.public_fountains():
			var fid: String = str(f.id)
			var ready_at: float = float(f.ready_at)
			if _fountain_ready.has(fid) and ready_at > float(_fountain_ready[fid]) + 0.01 and (f.center as Vector2).distance_to(hero.pos) > float(f.radius) + 60.0:
				_add_public_noise(f.center, "fountain")
			_fountain_ready[fid] = ready_at
	var keep: int = 0
	for n in public_noise:
		if sim.time - float(n.t) <= PUBLIC_NOISE_TTL:
			public_noise[keep] = n
			keep += 1
	public_noise.resize(keep)


func _add_public_noise(p: Vector2, kind: String) -> void:
	public_noise.append({"pos": p, "t": sim.time, "kind": kind})
	if public_noise.size() > PUBLIC_NOISE_MAX:
		public_noise.pop_front()


func _plan() -> void:
	# V2 (B-PERF2): nothing _attention reads changes during a plan, so its
	# answers are memoised for the plan's duration (exact).
	_att_memo.clear()
	_att_vis.clear()
	_att_vis_ok = false
	_att_scope = true
	_plan_body()
	_att_scope = false
	_att_memo.clear()
	_att_vis.clear()
	_att_vis_ok = false


func _plan_body() -> void:
	plan.t = sim.time
	aprof.clear()
	eprof.clear()
	var allies: Array[BUnit] = []
	if hero and hero.alive:
		allies.append(hero)
		aprof[hero.idx] = _ally_profile(hero)
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.controlled_by_us:
			continue
		if hero and hero.alive and not eb.visible and eb.pos.distance_to(hero.pos) > 1150.0:
			continue
		var pr: Dictionary = _enemy_profile_lod(eb)
		var w: float = 1.0 if eb.visible else clampf(eb.confidence, 0.2, 0.7) * 0.6
		w *= _attention(eb)
		pr["w"] = w
		pr["b"] = eb
		# Same values as KitModel.stats_of_def(eb.def), cached per definition.
		var st: Dictionary = KitModel._enemy_base(eb.def).st
		pr["ehp"] = (eb.hp + eb.shield) * (1.0 + (float(st.armor) + float(st.mr)) * 0.5 / 100.0)
		pr["threat"] = float(pr.dps) * 6.0 + float(pr.burst) + float(pr.cc) * 60.0
		pr["contrib"] = float(pr.dps) + float(pr.burst) / 6.0 + float(pr.cc) * 25.0 + float(pr.support) * 1.2
		pr["worth"] = float(pr.contrib) / maxf(120.0, float(pr.ehp))
		eprof[eb.idx] = pr
	if allies.is_empty():
		intent = {"mode": "dead", "goal": Vector2.INF, "since": sim.time, "score": 0.0, "reason": "재출전 대기", "target": -1, "uid": -1}
		# Review 1.5.3: keep watching the public map while waiting to respawn,
		# so a pickup, drop or fountain use during the death gets the time it
		# really happened (the first scan of a new life stamped them all "now").
		if hero and v153() and sim.time >= next_intent_at:
			next_intent_at = sim.time + INTENT_INTERVAL
			_scan_public_signals()
		return
	_plan_core(allies, false)
	# Team-mode clocks (score lead, no-kill timer, time-limit gambles) do not
	# mean anything in a free-for-all; they only pushed heroes into feints.
	plan.pressure = 0.0
	plan.nokill = 0.0
	plan.gamble = false
	if sim.time >= next_intent_at:
		_update_intent()
	_apply_intent_to_plan()


# KitModel.enemy_profile, except in scale battles (B-PERF2): an enemy that is
# hidden now and was hidden when its profile was last built reuses that
# profile (a copy) for up to EPROF_HIDDEN_KEEP s. Readiness of a hidden enemy
# drifts slowly, and 30-hero battles re-plan against up to 29 such beliefs.
const EPROF_HIDDEN_KEEP := 1.0
var _eprof_hidden: Dictionary = {}   # enemy idx -> [time, profile]


func _enemy_profile_lod(eb: TeamIntel.EnemyBelief) -> Dictionary:
	if not sim.scale_lod:
		return KitModel.enemy_profile(intel, eb)
	if eb.visible:
		_eprof_hidden.erase(eb.idx)
		return KitModel.enemy_profile(intel, eb)
	var hit: Array = _eprof_hidden.get(eb.idx, [])
	if not hit.is_empty() and sim.time - float(hit[0]) < EPROF_HIDDEN_KEEP:
		return (hit[1] as Dictionary).duplicate()
	var pr: Dictionary = KitModel.enemy_profile(intel, eb)
	_eprof_hidden[eb.idx] = [sim.time, pr.duplicate()]
	return pr


# An opponent that is closer to a third party than to us is probably busy.
var _att_scope: bool = false
var _att_memo: Dictionary = {}    # enemy idx -> _attention during one plan
var _att_vis: Array = []          # intel.visible_enemies() during one plan
var _att_vis_ok: bool = false


func _attention(eb: TeamIntel.EnemyBelief) -> float:
	if _att_scope:
		var hit = _att_memo.get(eb.idx)
		if hit != null:
			return hit
		var a: float = _attention_raw(eb)
		_att_memo[eb.idx] = a
		return a
	return _attention_raw(eb)


func _attention_raw(eb: TeamIntel.EnemyBelief) -> float:
	if hero == null:
		return 1.0
	if sim.time - float(fight_with.get(eb.idx, -99.0)) < 2.0:
		return 1.0
	var mine: float = eb.pos.distance_to(hero.pos)
	if not _att_scope:
		_att_vis = intel.visible_enemies()
	elif not _att_vis_ok:
		_att_vis = intel.visible_enemies()
		_att_vis_ok = true
	for other in _att_vis:
		var ob: TeamIntel.EnemyBelief = other
		if ob == eb or not ob.is_hero:
			continue
		if ob.pos.distance_to(eb.pos) < mine - 80.0 and ob.pos.distance_to(eb.pos) < 480.0:
			return 0.62
	return 1.0


# [effective hp, damage per second] in the units KitModel uses.
func _numbers_self() -> Array:
	var ap: Dictionary = aprof.get(hero.idx, {})
	if ap.is_empty():
		return [maxf(1.0, hero.hp), 60.0]
	return [maxf(1.0, float(ap.ehp)), maxf(1.0, float(ap.dps) + float(ap.burst) / 5.0 + float(ap.cc) * 25.0 + float(ap.support) * 0.6)]


func _numbers_enemy(eb: TeamIntel.EnemyBelief) -> Array:
	var pr: Dictionary = eprof.get(eb.idx, {})
	if pr.is_empty():
		var st: Dictionary = KitModel.stats_of_def(eb.def)
		return [maxf(1.0, eb.hp), maxf(1.0, KitModel.basic_dps(st, eb.def) * 1.4)]
	return [maxf(1.0, float(pr.ehp)), maxf(1.0, float(pr.dps) + float(pr.burst) / 5.0 + float(pr.cc) * 25.0 + float(pr.get("support", 0.0)) * 0.6)]


func _power_self() -> float:
	var n: Array = _numbers_self()
	return sqrt(float(n[0]) * float(n[1]))


func _power_enemy(eb: TeamIntel.EnemyBelief) -> float:
	var n: Array = _numbers_enemy(eb)
	return sqrt(float(n[0]) * float(n[1]))


# Range and speed decide who can take or refuse a fight.
func _matchup(e: TeamIntel.EnemyBelief) -> float:
	var my_reach: float = _ctx_range(hero)
	var their_reach: float = maxf(e.def.stat("attackRange"), e.def.preferred_range)
	var my_ms: float = sim.stat(hero, &"moveSpeed")
	var their_ms: float = e.ms()
	if my_reach > their_reach + 80.0 and my_ms >= their_ms * 0.92:
		return 1.4
	if their_reach > my_reach + 80.0 and their_ms >= my_ms * 0.92:
		return 0.75
	return 1.0


# Chance to win a fight against e: time for us to kill it versus time for it
# (and anyone close enough to join) to kill us.
func _win_chance(e: TeamIntel.EnemyBelief, visible: Array) -> float:
	var me: Array = _numbers_self()
	var them: Array = _numbers_enemy(e)
	var t_die: float = time_to_die(e, visible)
	var t_kill: float = float(them[0]) / maxf(1.0, float(me[1]))
	var margin: float = t_die / maxf(0.01, t_kill) * _matchup(e)
	var mk: float = pow(maxf(0.001, margin), 1.2)
	return mk / (1.0 + mk)


# Seconds until e (and anyone close enough to join) would kill us.
func time_to_die(e: TeamIntel.EnemyBelief, visible: Array) -> float:
	var me: Array = _numbers_self()
	var dmg_in: float = float(_numbers_enemy(e)[1]) * maxf(0.55, _attention(e))
	for b in visible:
		var o: TeamIntel.EnemyBelief = b
		if o == e:
			continue
		var d: float = o.pos.distance_to(hero.pos)
		if d > 650.0:
			continue
		dmg_in += float(_numbers_enemy(o)[1]) * _attention(o) * clampf(1.25 - d / 650.0, 0.25, 1.0) * 0.8
	return float(me[0]) / maxf(1.0, dmg_in)


func _forest_near(p: Vector2, dist: float) -> bool:
	for k in sim.arena.forest_x.size():
		if Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k]).distance_to(p) < dist + sim.arena.forest_r[k]:
			return true
	return false


# Chance to get away from this opponent if we turn and run now.
func _escape_chance(e: TeamIntel.EnemyBelief) -> float:
	var my_ms: float = sim.stat(hero, &"moveSpeed")
	var q: float = 0.35 + (my_ms / maxf(1.0, e.ms()) - 1.0) * 1.6
	var their_reach: float = float(eprof.get(e.idx, {}).get("reach", 200.0))
	var d: float = e.pos.distance_to(hero.pos)
	if their_reach < 200.0 and d > their_reach + 30.0:
		q += 0.2
	if their_reach > 350.0:
		q -= 0.15
	if _forest_near(hero.pos, 260.0):
		q += 0.15
	if hero.def.tags.has("MOBILITY"):
		q += 0.1
	return clampf(q, 0.05, 0.9)


func _set_intent(next: Dictionary) -> void:
	var changed: bool = str(next.mode) != str(intent.get("mode", "")) or int(next.get("target", -1)) != int(intent.get("target", -1)) or int(next.get("uid", -1)) != int(intent.get("uid", -1))
	if changed:
		next["since"] = sim.time
		intent_log.append({"t": sim.time, "mode": str(next.mode), "reason": str(next.get("reason", ""))})
		if intent_log.size() > 8:
			intent_log.pop_front()
	else:
		next["since"] = float(intent.get("since", sim.time))
	intent = next


# Remember which parts of the map this hero has recently looked at, so a
# search for opponents sweeps unexplored ground instead of circling.
func _mark_swept() -> void:
	var vr: float = sim.sensor_range(hero) * 0.85
	var c0: Vector2i = Vector2i(int(floor((hero.pos.x - vr) / SWEEP_CELL)), int(floor((hero.pos.y - vr) / SWEEP_CELL)))
	var c1: Vector2i = Vector2i(int(floor((hero.pos.x + vr) / SWEEP_CELL)), int(floor((hero.pos.y + vr) / SWEEP_CELL)))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var center: Vector2 = Vector2((cx + 0.5) * SWEEP_CELL, (cy + 0.5) * SWEEP_CELL)
			if center.distance_to(hero.pos) <= vr:
				swept[Vector2i(cx, cy)] = sim.time


func _staleness(p: Vector2) -> float:
	var cell: Vector2i = Vector2i(int(floor(p.x / SWEEP_CELL)), int(floor(p.y / SWEEP_CELL)))
	return clampf(sim.time - float(swept.get(cell, -60.0)), 0.0, 60.0)


func _update_intent() -> void:
	next_intent_at = sim.time + INTENT_INTERVAL
	if hero == null or not hero.alive:
		return
	_mark_swept()
	var fix: bool = v153()
	if fix:
		_scan_public_signals()
	var dm: DeathmatchMode = sim.deathmatch
	var hp_r: float = sim.hp_ratio(hero)
	var ms: float = maxf(40.0, sim.stat(hero, &"moveSpeed"))
	var held: Array = dm.held(hero) if dm else []
	var cur_mode: String = str(intent.get("mode", ""))
	var cur_target: int = int(intent.get("target", -1))
	var aggression: float = clampf(float(hero.def.behavior.get("aggression", 0.5)), 0.1, 0.95)
	var death_cost: float = DEATH_COST + 0.12 * held.size()
	var my_reach: float = _ctx_range(hero)
	var visible: Array = []
	var tracked: Array = []
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if not eb.is_hero or eb.controlled_by_us:
			continue
		if eb.visible:
			visible.append(eb)
		elif eb.ever_seen and sim.time - eb.last_seen_t < TRACK_TIME:
			tracked.append(eb)
	var options: Array = []
	# Who can hit us right now, and how would a fight with them go?
	var threat: TeamIntel.EnemyBelief = null
	var threat_p: float = 1.0
	var threat_close: float = 0.0
	var nearest_vis: float = INF
	for b in visible:
		var eb: TeamIntel.EnemyBelief = b
		var d: float = eb.pos.distance_to(hero.pos)
		nearest_vis = minf(nearest_vis, d)
		var reach: float = float(eprof.get(eb.idx, {}).get("reach", 200.0))
		var on_me: bool = sim.time - float(fight_with.get(eb.idx, -99.0)) < 3.0
		if d > reach + 160.0 and not on_me:
			continue
		var p0: float = _win_chance(eb, visible)
		if p0 < threat_p:
			threat_p = p0
			threat = eb
		threat_close = maxf(threat_close, 1.0 if on_me else clampf(1.0 - (d - reach) / 160.0, 0.0, 1.0))
	# How long we would last against whoever is on us, and what fighting it back
	# would be worth: both price the choice to ignore the threat.
	var threat_ttk: float = INF
	var threat_fight: float = 0.0
	if threat != null:
		threat_ttk = time_to_die(threat, visible)
		var tu0: BUnit = sim.u_at(threat.idx)
		var carried0: float = 0.15 * float(dm.held(tu0).size()) if dm and tu0 else 0.0
		threat_fight = KILL_VALUE * (threat_p * (1.0 + carried0) - (1.0 - threat_p) * death_cost)
	# Fights with visible opponents.
	for b in visible:
		var e: TeamIntel.EnemyBelief = b
		if float(escaped.get(e.idx, -1.0)) > sim.time:
			# Back inside our reach and in sight: it did not get away.
			if fix and e.pos.distance_to(hero.pos) <= my_reach + ESCAPE_CLEAR_PAD:
				escaped.erase(e.idx)
			else:
				continue
		var p: float = _win_chance(e, visible)
		var d2: float = e.pos.distance_to(hero.pos)
		var eu: BUnit = sim.u_at(e.idx)
		var carried: float = 0.15 * float(dm.held(eu).size()) if dm and eu else 0.0
		var ev: float = KILL_VALUE * (p * (1.0 + carried) - (1.0 - p) * death_cost)
		var gap: float = maxf(0.0, d2 - my_reach - 30.0)
		var score: float = ev - gap / ms * 6.0 + 8.0 * aggression
		var engaged: bool = sim.time - float(fight_with.get(e.idx, -99.0)) < 3.0
		var ehp_r: float = e.hp / maxf(1.0, e.max_hp)
		var busy: bool = _attention(e) < 0.9
		if engaged:
			score += 15.0
		if cur_mode == "hunt" and cur_target == e.idx:
			score += 10.0
		if busy and ehp_r < 0.7:
			score += 12.0
		var why: String = "승산 %d%% · 대상 체력 %d%%" % [int(p * 100.0), int(ehp_r * 100.0)]
		if engaged and e.idx == last_attacker and sim.time - last_attacked_at < 3.0:
			why = "교전 중 — 승산 %d%%" % int(p * 100.0)
		elif busy and ehp_r < 0.7:
			why = "다른 적과 교전 중 · 체력 %d%% → 개입" % int(ehp_r * 100.0)
		options.append({"mode": "hunt", "goal": e.pos, "score": score, "target": e.idx, "uid": -1, "p": p,
			"reason": "%s — %s" % [e.def.name, why]})
	# Opponents that just slipped out of sight: follow while the trail is warm.
	for b in tracked:
		var e2: TeamIntel.EnemyBelief = b
		if float(escaped.get(e2.idx, -1.0)) > sim.time:
			continue
		var ago: float = sim.time - e2.last_seen_t
		var goal: Vector2 = e2.pos if e2.confidence > 0.35 else e2.last_seen_pos
		var d3: float = goal.distance_to(hero.pos)
		if d3 > 1100.0:
			continue
		var p2: float = _win_chance(e2, visible)
		var catch_p: float = clampf(0.75 - ago / TRACK_TIME * 0.45 + (ms / maxf(1.0, e2.ms()) - 1.0) * 0.8, 0.1, 0.9)
		var ev2: float = KILL_VALUE * catch_p * (p2 - (1.0 - p2) * death_cost)
		var score2: float = ev2 - d3 / ms * 4.0
		if sim.time - float(fight_with.get(e2.idx, -99.0)) < 6.0:
			score2 += 10.0
		if cur_mode == "chase" and cur_target == e2.idx:
			score2 += 8.0
		options.append({"mode": "chase", "goal": goal, "score": score2, "target": e2.idx, "uid": -1, "p": p2,
			"reason": "%s — %.1f초 전 목격 · 체력 %d%% · 승산 %d%%" % [e2.def.name, ago, int(e2.hp / maxf(1.0, e2.max_hp) * 100.0), int(p2 * 100.0)]})
	# Running only pays when the fight is clearly lost and escape is likely.
	var ev_evade: float = -INF
	var evade_opt: Dictionary = {}
	var hide_opt: Dictionary = {}
	if threat != null:
		var q: float = _escape_chance(threat)
		var worse: float = threat_p * 0.5
		var ev_run: float = (1.0 - q) * KILL_VALUE * (worse - (1.0 - worse) * death_cost)
		ev_evade = ev_run
		if cur_mode == "evade":
			ev_run += 6.0
		# The escape and hide points (pure searches) are found only for the
		# option that wins, below (B-PERF2).
		evade_opt = {"mode": "evade", "goal": Vector2.INF, "score": ev_run, "target": -1, "uid": -1,
			"reason": "%s 상대 승산 %d%% · 탈출 %d%% → 이탈" % [threat.def.name, int(threat_p * 100.0), int(q * 100.0)]}
		options.append(evade_opt)
	# Ignoring an opponent that is on us is the worst of both: it costs at least
	# as much as the larger stake of fighting it or running from it.
	var exposed: float = 0.0
	if threat != null:
		exposed = threat_close * KILL_VALUE * (1.0 - threat_p) * death_cost * 0.8
		if fix:
			exposed += threat_close * maxf(absf(threat_fight), absf(ev_evade))
	# Recover out of combat: forests hide, idle heroes regenerate. Once hidden,
	# stay until health is well up instead of walking out at half health.
	var hiding: bool = cur_mode == "recover" and str(intent.get("sub", "")) == "hide"
	var hide_limit: float = HIDE_UNTIL if fix and hiding else 0.5
	if hp_r < hide_limit and nearest_vis > 650.0:
		var hide_score: float = 18.0 + (0.5 - hp_r) * 220.0 if hp_r < 0.5 else -INF
		if fix and hiding:
			hide_score = maxf(hide_score, 14.0 + (HIDE_UNTIL - hp_r) * 90.0)
		hide_opt = {"mode": "recover", "sub": "hide", "goal": Vector2.INF, "score": hide_score,
			"reason": "체력 %d%% · 숲에 숨어 회복" % int(hp_r * 100.0), "target": -1, "uid": -1}
		options.append(hide_opt)
	if sim.env.enabled and hp_r < 0.8:
		for fountain: Dictionary in sim.env.public_fountains():
			var distance: float = hero.pos.distance_to(fountain.center)
			var eta: float = distance / ms
			if distance > 1100.0 or float(fountain.ready_at) > sim.time + minf(eta, 3.0):
				continue
			# A pursuer that kills us before we arrive, or that stands nearer the
			# fountain than we do, turns the walk into a death march.
			if fix and threat != null and threat_close > 0.25:
				if threat_ttk < eta + 1.0 or threat.pos.distance_to(fountain.center) < distance - 40.0:
					continue
			var risk: float = danger_at(hero, fountain.center, 1.0) / maxf(1.0, hero.hp)
			var benefit: float = minf(1.0 - hp_r, float(fountain.heal_percent))
			var score: float = benefit * 320.0 + (1.0 - hp_r) * 60.0 - eta * 3.0 - risk * 90.0
			options.append({"mode": "recover", "sub": "fountain", "goal": fountain.center, "score": score,
				"reason": "공용 회복샘 · 공개 준비시간과 관측 위험 확인", "target": -1, "uid": -1})
	# Loot: value for THIS hero, discounted by walk, danger and a nearer rival.
	# V2 (B-PERF2): gains come from the exact memo, and a loot option's reason
	# text is written only if that option wins (below), not for every item.
	# Only one loot option can win: the first with the highest score after the
	# evade cap applied further down (the selection keeps the first maximum),
	# so only that one is added, at the loot options' place in the list.
	var loot_item: Dictionary = {}   # field uid -> item id
	if dm:
		var gains: Dictionary = {}
		var mine: float = maxf(1.0, _power_self())
		var menace: Dictionary = {}
		for b in visible:
			var eb5: TeamIntel.EnemyBelief = b
			menace[eb5.idx] = _power_enemy(eb5) * _attention(eb5) / mine
		var loot_cap: bool = fix and threat != null and threat_close >= 0.5 and ev_evade > -INF
		var loot_best: Dictionary = {}
		var loot_best_s: float = -INF
		for it in dm.field:
			var item_id: String = str(it.item)
			if not gains.has(item_id):
				gains[item_id] = ItemValuation.gain_cached(hero.def, item_id, held, DeathmatchMode.SLOTS)
			var g: float = gains[item_id]
			if g <= 0.0 or (held.size() >= DeathmatchMode.SLOTS and g < 10.0):
				continue
			var ipos: Vector2 = it.pos
			var dist: float = hero.pos.distance_to(ipos)
			var eta: float = dist * 1.2 / ms
			var danger: float = 0.0
			var rival: float = 1.0
			for b in visible:
				var eb2: TeamIntel.EnemyBelief = b
				var de: float = eb2.pos.distance_to(ipos)
				if de < 450.0:
					danger += float(menace[eb2.idx])
				if de < dist - 60.0:
					rival *= 0.55
			var score3: float = g * 0.95 * rival * (1.0 - clampf(danger * 0.45, 0.0, 0.8)) - eta * 1.9
			if cur_mode == "loot" and int(intent.get("uid", -1)) == int(it.uid):
				score3 += 10.0
			if dist > 80.0:
				score3 -= exposed
			var final3: float = minf(score3, ev_evade - 1.0) if loot_cap and dist > 80.0 else score3
			if final3 > loot_best_s:
				loot_best_s = final3
				loot_best = {"mode": "loot", "goal": ipos, "score": score3, "uid": int(it.uid), "target": -1, "reason": ""}
				loot_item[int(it.uid)] = item_id
		if not loot_best.is_empty():
			options.append(loot_best)
	# A fight heard nearby is a chance to arrive third.
	if visible.is_empty() and hp_r > 0.5:
		var best_n: Dictionary = {}
		var best_nd: float = INF
		for nz in noises:
			if sim.time - float(nz.t) > FIGHT_NOISE_TTL:
				continue
			var dn: float = (nz.pos as Vector2).distance_to(hero.pos)
			if dn < best_nd:
				best_nd = dn
				best_n = nz
		if not best_n.is_empty():
			var sc_n: float = 22.0 + 30.0 * (hp_r - 0.5) + 10.0 * aggression - best_nd / ms * 3.0
			if cur_mode == "listen":
				sc_n += 6.0
			options.append({"mode": "listen", "goal": best_n.pos, "score": sc_n, "target": -1, "uid": -1,
				"reason": "%d 거리에서 전투 소음 → 어부지리" % int(best_nd)})
		# Public signals: somebody just took an item, dropped one or drank from
		# a fountain there. With few opponents each signal almost certainly
		# points at one of them.
		if fix:
			var opponents: int = maxi(1, sim.heroes.size() - 1)
			var informative: float = clampf(3.0 / float(opponents), 0.25, 1.0)
			var best_p: Dictionary = {}
			var best_ps: float = -INF
			for pn in public_noise:
				var age: float = sim.time - float(pn.t)
				var dpn: float = (pn.pos as Vector2).distance_to(hero.pos)
				if age > PUBLIC_NOISE_TTL or dpn < 160.0:
					continue
				var sc_p: float = (14.0 + 24.0 * (hp_r - 0.5) + 10.0 * aggression) * informative + 10.0 * informative \
					- dpn * 1.15 / ms * 1.4 - age * 1.1
				if sc_p > best_ps:
					best_ps = sc_p
					best_p = pn
			if not best_p.is_empty():
				if cur_mode == "listen":
					best_ps += 6.0
				var what: String = {"item": "보급품 소실", "drop": "보급품 낙하", "fountain": "회복샘 사용"}.get(str(best_p.kind), "공개 신호")
				options.append({"mode": "listen", "goal": best_p.pos, "score": best_ps, "target": -1, "uid": -1,
					"reason": "%.0f초 전 %s — 적 위치 추정" % [sim.time - float(best_p.t), what]})
	# A pursuit that lands no damage for a while is abandoned for a while. A
	# target that stays in sight within reach has not escaped (V1.5.3).
	if cur_mode in ["hunt", "chase"]:
		var tgt_idx: int = cur_target
		if tgt_idx >= 0:
			if not hunt_track.has(tgt_idx):
				hunt_track[tgt_idx] = sim.time
			var started: float = float(hunt_track[tgt_idx])
			var last_hit: float = float(last_hit_on.get(tgt_idx, -99.0))
			var progress_at: float = maxf(started, last_hit)
			if fix:
				var tb: TeamIntel.EnemyBelief = intel.enemies.get(tgt_idx)
				if tb and tb.visible and tb.pos.distance_to(hero.pos) <= my_reach + ESCAPE_REACH_PAD:
					contact_on[tgt_idx] = sim.time
				progress_at = maxf(progress_at, float(contact_on.get(tgt_idx, -99.0)))
			if sim.time - progress_at > pursuit_window():
				escaped[tgt_idx] = sim.time + 12.0
				hunt_track.erase(tgt_idx)
				contact_on.erase(tgt_idx)
				for o in options:
					if str(o.mode) in ["hunt", "chase"] and int(o.target) == tgt_idx:
						o.score = -INF
	for key in hunt_track.keys():
		if not (cur_mode in ["hunt", "chase"]) or int(key) != cur_target:
			hunt_track.erase(key)
			contact_on.erase(key)
	# Roam: look for items and opponents instead of standing still.
	if roam_goal == Vector2.INF or hero.pos.distance_to(roam_goal) < 140.0 or sim.time > roam_until:
		roam_goal = _pick_roam_goal()
		roam_until = sim.time + 14.0
	options.append({"mode": "roam", "goal": roam_goal, "score": 8.0 - exposed, "reason": "적과 보급을 찾아 이동", "target": -1, "uid": -1})
	for o in options:
		if str(o.mode) == "recover" or str(o.mode) == "listen":
			o.score = float(o.score) - exposed
	# With an opponent on us, turning our back to walk, loot or listen is
	# strictly worse than running from it (fighting it may still be best).
	if fix and threat != null and threat_close >= 0.5 and ev_evade > -INF:
		for o in options:
			var m: String = str(o.mode)
			if m == "roam" or m == "listen" or m == "recover" or (m == "loot" and (o.goal as Vector2).distance_to(hero.pos) > 80.0):
				o.score = minf(float(o.score), ev_evade - 1.0)
	var best: Dictionary = {}
	var best_s: float = -INF
	for o in options:
		var sc: float = float(o.score)
		if str(o.mode) == cur_mode and str(o.mode) == "recover":
			sc += 6.0
		if sc > best_s:
			best_s = sc
			best = o
	if not evade_opt.is_empty() and is_same(best, evade_opt):
		best["goal"] = _escape_point(threat.pos)
	elif not hide_opt.is_empty() and is_same(best, hide_opt):
		best["goal"] = _hide_point()
	if str(best.get("mode", "")) == "loot" and loot_item.has(int(best.get("uid", -1))):
		var won: String = loot_item[int(best.uid)]
		var v: Dictionary = ItemValuation.value(hero.def, won, held)
		best["reason"] = "%s (%s) — %s" % [str(ItemDefs.get_def(won).name), ItemDefs.RARITY_NAMES[ItemDefs.rarity_of(won)], str(v.reason)]
	_set_intent(best)


func _escape_point(threat_c: Vector2) -> Vector2:
	var best: Vector2 = hero.pos + (hero.pos - threat_c).normalized() * 320.0
	var best_v: float = -INF
	var cands: Array = []
	for k in 8:
		cands.append(hero.pos + Vector2.from_angle(k * TAU / 8.0) * 340.0)
	for k in sim.arena.forest_x.size():
		var c := Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k])
		if c.distance_to(hero.pos) < 900.0:
			cands.append(c)
	for c in cands:
		var p: Vector2 = sim.arena.resolve_circle(c, sim.radius(hero))
		var away: float = p.distance_to(threat_c) - hero.pos.distance_to(threat_c)
		var v: float = away - p.distance_to(hero.pos) * 0.35
		if sim.arena.forest_at(p) >= 0:
			v += 140.0
		for b in intel.visible_enemies():
			if (b as TeamIntel.EnemyBelief).pos.distance_to(p) < 260.0:
				v -= 200.0
		if v > best_v:
			best_v = v
			best = p
	return best


func _hide_point() -> Vector2:
	var best: Vector2 = hero.pos
	var best_v: float = -INF
	for k in sim.arena.forest_x.size():
		var c := Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k])
		var v: float = -c.distance_to(hero.pos)
		for b in intel.alive_enemies():
			var eb: TeamIntel.EnemyBelief = b
			if eb.confidence > 0.3 and eb.pos.distance_to(c) < 420.0:
				v -= 500.0
		if v > best_v:
			best_v = v
			best = c
	return sim.arena.resolve_circle(best, sim.radius(hero))


func _pick_roam_goal() -> Vector2:
	# Prefer where opponents were last believed to be and where items cluster.
	var best: Vector2 = sim.arena.center()
	var best_v: float = -INF
	var cands: Array = []
	for p in sim.arena.ffa_spawns:
		cands.append(p)
	var gx: int = int(ceil(sim.arena.width / SWEEP_CELL))
	var gy: int = int(ceil(sim.arena.height / SWEEP_CELL))
	for cx in gx:
		for cy in gy:
			var cc: Vector2 = Vector2((cx + 0.5) * SWEEP_CELL, (cy + 0.5) * SWEEP_CELL)
			if cc.x > sim.arena.min_x + 60.0 and cc.x < sim.arena.max_x - 60.0 and cc.y > sim.arena.min_y + 60.0 and cc.y < sim.arena.max_y - 60.0:
				cands.append(cc)
	var hunting: bool = sim.deathmatch == null or sim.deathmatch.held(hero).size() >= 2
	var alive: Array = intel.alive_enemies()
	for b in alive:
		var eb: TeamIntel.EnemyBelief = b
		if eb.ever_seen and eb.confidence > 0.2:
			cands.append(eb.pos)
			if hunting:
				cands.append(eb.pos)
	# Recent public signals (items taken, fountains used) mark where somebody
	# was; with few players a sweep toward them finds the opponent.
	var signal_w: float = 0.0
	if v153():
		signal_w = clampf(3.0 / float(maxi(1, sim.heroes.size() - 1)), 0.25, 1.0) * 45.0
		for pn in public_noise:
			if sim.time - float(pn.t) <= PUBLIC_NOISE_TTL:
				cands.append(pn.pos)
	# V2 (B-PERF): the per-candidate terms read packed copies made once here
	# (same values, same summation order) instead of rebuilding the enemy list
	# and reading dictionaries for every candidate (~200 on a large map).
	var e_pos: PackedVector2Array = PackedVector2Array()
	var e_add: PackedFloat64Array = PackedFloat64Array()
	for b2 in alive:
		var eb2: TeamIntel.EnemyBelief = b2
		if eb2.ever_seen:
			e_pos.append(eb2.pos)
			e_add.append(25.0 * clampf(eb2.confidence + 0.3, 0.0, 1.0) * (1.6 if hunting else 1.0))
	var n_pos: PackedVector2Array = PackedVector2Array()
	var n_fresh: PackedFloat64Array = PackedFloat64Array()
	if signal_w > 0.0:
		for pn2 in public_noise:
			var age0: float = sim.time - float(pn2.t)
			if age0 <= PUBLIC_NOISE_TTL:
				n_pos.append(pn2.pos)
				n_fresh.append(1.0 - age0 / PUBLIC_NOISE_TTL)
	var i_pos: PackedVector2Array = PackedVector2Array()
	if sim.deathmatch:
		for it in sim.deathmatch.field:
			i_pos.append(it.pos)
	for c in cands:
		var p: Vector2 = c
		var d: float = p.distance_to(hero.pos)
		if d < 250.0:
			continue
		var v: float = -absf(d - 900.0) * 0.05 + rng.randf() * 30.0 + _staleness(p) * 0.9
		for k in e_pos.size():
			if e_pos[k].distance_to(p) < 350.0:
				v += e_add[k]
		if signal_w > 0.0:
			var fresh: float = 0.0
			for k2 in n_pos.size():
				if n_pos[k2].distance_to(p) < 400.0:
					fresh = maxf(fresh, n_fresh[k2])
			v += signal_w * fresh
		for q in i_pos:
			if q.distance_to(p) < 500.0:
				v += 6.0
		if v > best_v:
			best_v = v
			best = p
	return sim.arena.resolve_circle(best, sim.radius(hero))


func _apply_intent_to_plan() -> void:
	cfg["risk"] = 1.0
	var mode: String = str(intent.get("mode", ""))
	match mode:
		"evade":
			plan.stance = "DISENGAGE"
			plan.go = false
			cfg["risk"] = 1.35
		"hunt", "chase":
			var target: TeamIntel.EnemyBelief = intel.enemies.get(int(intent.get("target", -1)))
			if target and target.visible and target.pos.distance_to(hero.pos) < 700.0:
				plan.stance = "ENGAGE"
				plan.go = true
				plan.focus = target.idx
				# A likely win is worth walking through some fire for.
				cfg["risk"] = clampf(1.2 - float(intent.get("p", 0.5)) * 0.7, 0.6, 1.0)
		"loot", "recover", "roam", "listen":
			var hit_recently: bool = hero != null and sim.time - hero.last_damage_time < 2.5
			if str(plan.stance) == "ENGAGE" and not bool(plan.get("fighting", false)):
				plan.stance = "POKE"
				plan.go = false
			elif str(plan.stance) == "DISENGAGE" and not hit_recently:
				plan.stance = "POKE"


func _mode_move_points(u: BUnit, _ctx: Dictionary, pts: Array) -> void:
	var goal: Vector2 = intent.get("goal", Vector2.INF)
	if goal == Vector2.INF or not goal.is_finite():
		return
	var mode: String = str(intent.get("mode", ""))
	var reward: float = {"loot": 95.0, "hunt": 40.0, "chase": 70.0, "evade": 130.0, "recover": 85.0, "roam": 45.0, "listen": 60.0}.get(mode, 40.0)
	if mode == "hunt" or mode == "chase":
		var target: TeamIntel.EnemyBelief = intel.enemies.get(int(intent.get("target", -1)))
		# Close in only; once in reach the tactician's own fight positions and attacks decide.
		if target and target.visible:
			if u.pos.distance_to(target.pos) < float(_ctx_range(u)) + 140.0:
				return
			goal = target.pos
	elif mode in ["loot", "roam", "recover", "listen"] and sim.time - last_attacked_at < 2.5:
		reward *= 0.35
	var label_text: String = "%s: %s" % [str(LABELS.get(mode, mode)), str(intent.get("reason", "")).split(" — ")[0]]
	pts.append([goal, label_text, reward])
	if mode != "hunt" and u.pos.distance_to(goal) > 200.0:
		# An intermediate step keeps progress while the path bends.
		pts.append([u.pos + (goal - u.pos).normalized() * 180.0, label_text, reward * 0.7])


func _mode_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var mode: String = str(intent.get("mode", ""))
	if mode == "" or mode == "dead":
		return
	var goal: Vector2 = intent.get("goal", Vector2.INF)
	var has_goal: bool = goal != Vector2.INF and goal.is_finite()
	var dist: float = u.pos.distance_to(goal) if has_goal else 0.0
	var hunt_target: int = int(intent.get("target", -1))
	for item in cands:
		var c: Dictionary = item
		var cmd: Dictionary = c.cmd
		var kind: String = str(cmd.get("kind", ""))
		if kind == "move":
			if has_goal and mode != "hunt" and (mode == "evade" or sim.time - last_attacked_at > 2.5):
				var endpoint: Vector2 = cmd.get("goal", u.pos)
				var progress: float = dist - endpoint.distance_to(goal)
				Doctrine._note(c, clampf(progress * 0.18, -80.0, 100.0), "%s 목표 접근" % str(LABELS.get(mode, mode)))
			if mode != "roam" and str(c.get("label", "")) == "정찰":
				Doctrine._note(c, -60.0, "정찰보다 현재 목표 우선")
			continue
		var ti: int = int(cmd.get("target", -1))
		var foe: TeamIntel.EnemyBelief = intel.enemies.get(ti)
		if foe == null:
			continue
		var kill: bool = float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0
		var reach: float = float(eprof.get(ti, {}).get("reach", 160.0))
		var threatening: bool = u.pos.distance_to(foe.pos) <= reach + 40.0
		match mode:
			"hunt", "chase":
				if ti == hunt_target:
					Doctrine._note(c, 35.0, "사냥 대상 집중")
				elif not threatening and not kill:
					Doctrine._note(c, -30.0, "사냥 대상 외 교전 절제")
			"evade":
				if not kill:
					Doctrine._note(c, -90.0 if not threatening else -35.0, "이탈 중 교전 회피")
			_:
				if not kill and not threatening:
					Doctrine._note(c, -70.0, "%s 우선 · 불필요한 교전 회피" % str(LABELS.get(mode, mode)))


# Long walks across the large map would otherwise run a grid search every
# tick. A waypoint stays valid for a few ticks while the goal and the walker
# have barely moved, and is dropped once reached.
var _wp_cache: Array = []   # {"from", "goal", "r", "wp", "until"}


func route_point(from: Vector2, goal: Vector2, r: float) -> Vector2:
	for c in _wp_cache:
		if float(c.until) >= sim.time and float(c.r) == r and (c.goal as Vector2).distance_squared_to(goal) < 400.0 \
				and (c.from as Vector2).distance_squared_to(from) < 1600.0 and (c.wp as Vector2).distance_squared_to(from) > 196.0:
			return c.wp
	var wp: Vector2 = super.route_point(from, goal, r)
	if wp.distance_squared_to(goal) > 1.0:
		_wp_cache.append({"from": from, "goal": goal, "r": r, "wp": wp, "until": sim.time + 0.2})
		if _wp_cache.size() > 4:
			_wp_cache.pop_front()
	return wp


func _ctx_range(u: BUnit) -> float:
	return maxf(sim.stat(u, &"attackRange"), u.def.preferred_range)


# Pickup decision under the hero's feet (DeathmatchMode asks this).
func item_choice(u: BUnit, item_id: String) -> Dictionary:
	var held: Array = sim.deathmatch.held(u) if sim.deathmatch else []
	var r: Dictionary = ItemValuation.decide(u.def, item_id, held, DeathmatchMode.SLOTS)
	last_pick_reason = str(r.reason)
	return r


# For the battle panel: how this hero rates a fight with each opponent it sees.
func duel_table() -> Array:
	var out: Array = []
	if hero == null or not hero.alive:
		return out
	var visible: Array = []
	for b in intel.visible_enemies():
		if (b as TeamIntel.EnemyBelief).is_hero:
			visible.append(b)
	for b in visible:
		var e: TeamIntel.EnemyBelief = b
		out.append({"idx": e.idx, "name": e.def.name, "p": _win_chance(e, visible), "dist": e.pos.distance_to(hero.pos),
			"hp": e.hp / maxf(1.0, e.max_hp), "busy": _attention(e) < 0.9, "escape": _escape_chance(e)})
	out.sort_custom(func(a, b): return float(a.dist) < float(b.dist))
	return out


func explain(u: BUnit) -> Dictionary:
	var out: Dictionary = super.explain(u)
	var held: Array = sim.deathmatch.held(u) if sim.deathmatch else []
	var values: Array = []
	for id in held:
		var others: Array = held.duplicate()
		others.erase(id)
		var v: Dictionary = ItemValuation.value(u.def, str(id), others)
		values.append({"item": id, "value": v.value, "reason": v.reason})
	out["deathmatch"] = {"mode": str(intent.get("mode", "")), "mode_label": str(LABELS.get(str(intent.get("mode", "")), "")),
		"reason": str(intent.get("reason", "")), "since": float(intent.get("since", 0.0)), "log": intent_log.duplicate(true),
		"items": values, "last_pick": last_pick_reason}
	return out
