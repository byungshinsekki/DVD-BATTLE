class_name BattlegroundSoloBrain
extends DeathmatchBrain

# V2 battleground, solo (DESIGN_V2 §3.6). One brain per hero. The deathmatch
# layer's currency (expected kills) stays, with battleground rules on top:
#  * Death is final, so the cost of dying is the placement it throws away:
#    with N teams and A still in, dying now ranks A while surviving is worth
#    about rank (A + 1) / 2 plus a share of the win (death_cost()).
#  * The zone replaces roaming: from public_view only, the hero computes when
#    the edge reaches it and how long the walk inside the next circle takes;
#    the difference (slack) sets the urgency of rotating, and every other
#    option whose goal lies outside the safe circle pays for it.
#  * Items are known only once seen (this hero's memory); only known items
#    within LOOT_RANGE px or inside the next circle are looted. An item's
#    disappearance is noticed only within sight or HEAR_RANGE.
#  * Hidden opponents' beliefs drift toward the safe circle (everyone else
#    rotates too).
#  * Third parties: the deathmatch _attention (an opponent busy with someone
#    else) and fight noise within earshot still apply.
#  * Pacing (B-SQUAD): during the loot phase (calm_factor, easing out over the
#    first shrink) a fight nobody started costs CALM_HUNT, chasing fight noise
#    and public signals costs more, and roaming sweeps nearby ground with no
#    pull toward the map centre: heroes loot and position for the announced
#    circle, and fight when attacked or when the odds are clearly good.
#  * Zone edge (B-SQUAD): a fight where the edge will be within EDGE_LOOK s
#    pays edge_cost; standing outside a damaging circle is always urgent.
#  * Final circles (late_factor) or few opponents left: hold brush
#    deep inside the safe circle and let others fight; a fight nobody started
#    costs LATE_HUNT unless the opponent is busy with a third party.
# Static zone helpers at the end are shared with BattlegroundSquadBrain.

const LOOT_RANGE := 1500.0
const ROTATE_SLACK := 40.0          # slack (s) below which rotating gets urgent (was 30)
const ZONE_INNER := 0.6             # rotate to this fraction of the safe radius
const DRIFT_RATE := 0.6             # hidden beliefs drift at this share of their speed
const CALM_HUNT := 28.0             # loot phase: cost of a fight nobody started
const CALM_LISTEN := 30.0           # loot phase: cost of walking to fight noise
const CALM_SIGNAL := 20.0           # loot phase: cost of walking to a public signal
const LATE_HUNT := 12.0             # final circles: cost of a fight nobody started
const EDGE_LOOK := 12.0             # s ahead the zone edge is read for fights
const EDGE_PAD := 220.0             # px inside that edge a fight is still clean
const SOLO_CALM := [1.0, 0.55, 0.3]  # solo calm floor by zone phase (loot, Z1, Z2)
const CALM_FIRST_SHOT := 50.0       # loot phase: cost of opening fire on an opponent that has not struck
const BR_LABELS := {"rotate": "자기장 이동", "loot": "보급", "hunt": "사냥", "chase": "추격", "evade": "회피",
	"recover": "회복", "roam": "탐색", "listen": "소음 추적", "hold": "자리 잡기", "dead": "탈락"}

var known_items: Dictionary = {}    # uid -> {"pos", "item", "rarity", "t"} (seen by this hero)
var zone_state: Dictionary = {}     # last zone reading: urgency, slack, safe circle, calm, late
var hold_goal: Vector2 = Vector2.INF
var _br_timetable: Array = []
var _zv: Dictionary = {}            # zone public view of the current intent update
var struck_by: Dictionary = {}      # opponent idx -> last time it damaged this hero (attacker seen)


func _init(s: BattleSim, t: int) -> void:
	super(s, t)
	label = "배틀그라운드 AI"
	if s.battleground:
		_br_timetable = BrZone.schedule_rows(s.battleground.zone_speed)


# Public deaths (the kill feed) end beliefs about that opponent; the generic
# intel only learns deaths it observed.
# Hits on this hero by an attacker it sees are remembered per attacker (the
# loot-phase rules tell "it struck us" from "we struck it").
func pre_tick(s: BattleSim) -> void:
	var codes: PackedByteArray = s.ai_event_codes(s.ai_events)
	for ei in s.ai_events.size():
		var code: int = codes[ei]
		if code == 15 or code == 16:
			var ev0: Dictionary = s.ai_events[ei]
			if hero != null and int(ev0.g) == hero.idx and bool((ev0.sv as Array)[team]):
				var src: BUnit = _hero_of(int(ev0.s))
				if src != null and src.team != team:
					struck_by[src.idx] = float(ev0.t)
			continue
		if code != 0:
			continue
		var ev: Dictionary = s.ai_events[ei]
		if str(ev.type) == "BR_ELIMINATED":
			var b: TeamIntel.EnemyBelief = intel.enemies.get(int(ev.g))
			if b:
				b.dead = true
				b.visible = false
			struck_by.erase(int(ev.g))
	super.pre_tick(s)


func _struck_by(idx: int, window: float = 3.0) -> bool:
	return sim.time - float(struck_by.get(idx, -99.0)) < window


# ---------------------------------------------------------------- valuation

# Placement value of a death (DESIGN_V2 §3.6), in the deathmatch unit (one
# kill = 1). With N teams and A still in, the expected placement value of
# surviving minus that of dying now, scaled so an even early fight is a
# loss and a likely win is still worth taking; carried items add to it.
func death_cost(held_count: int) -> float:
	var br: BattlegroundMode = sim.battleground
	var n: float = float(maxi(2, br.team_count))
	var a: float = float(maxi(1, br.alive_team_count()))
	var stake: float = (a - 1.0) * 0.5 / (n - 1.0) + 0.5 / a
	return 0.55 + 2.0 * stake + 0.12 * held_count


# ---------------------------------------------------------------- intent

func _update_intent() -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_br_intent()
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("intent", t0)


func _br_intent() -> void:
	next_intent_at = sim.time + INTENT_INTERVAL
	if hero == null or not hero.alive:
		return
	var br: BattlegroundMode = sim.battleground
	_mark_swept()
	_remember_items([hero])
	_scan_public_signals()
	_zv = br.zone_view()
	var zs: Dictionary = zone_sense(_zv, hero.pos, maxf(40.0, sim.stat(hero, &"moveSpeed")), _br_timetable, sim.time)
	var calm: float = solo_calm(_zv, _br_timetable, sim.time)
	# Final circles, or few opponents left (public counts; 8 -> 3 of 30): play
	# for placement.
	var n_teams: float = float(maxi(2, br.team_count))
	var few: float = clampf((0.27 * n_teams - float(br.alive_team_count())) / (0.17 * n_teams), 0.0, 1.0)
	var late: float = maxf(late_factor(_zv, half_diag(sim)), 0.8 * few)
	zs["calm"] = calm
	zs["late"] = late
	zone_state = zs
	drift_beliefs(sim, intel, zs, INTENT_INTERVAL)
	var hp_r: float = sim.hp_ratio(hero)
	var ms: float = maxf(40.0, sim.stat(hero, &"moveSpeed"))
	var held: Array = br.held(hero)
	var cur_mode: String = str(intent.get("mode", ""))
	var cur_target: int = int(intent.get("target", -1))
	var aggression: float = clampf(float(hero.def.behavior.get("aggression", 0.5)), 0.1, 0.95)
	var d_cost: float = death_cost(held.size())
	var my_reach: float = _ctx_range(hero)
	var urgency: float = float(zs.urgency)
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
	# Who can hit us now, and how would that fight go?
	var threat: TeamIntel.EnemyBelief = null
	var threat_p: float = 1.0
	var threat_close: float = 0.0
	var struck: bool = false            # an opponent in reach traded blows with us lately
	var nearest_vis: float = INF
	for b in visible:
		var eb: TeamIntel.EnemyBelief = b
		var d: float = eb.pos.distance_to(hero.pos)
		nearest_vis = minf(nearest_vis, d)
		var reach: float = float(eprof.get(eb.idx, {}).get("reach", 200.0))
		var on_me: bool = sim.time - float(fight_with.get(eb.idx, -99.0)) < 3.0
		if d > reach + 160.0 and not on_me:
			continue
		struck = struck or _struck_by(eb.idx)
		var p0: float = _win_chance(eb, visible)
		if p0 < threat_p:
			threat_p = p0
			threat = eb
		threat_close = maxf(threat_close, 1.0 if on_me else clampf(1.0 - (d - reach) / 160.0, 0.0, 1.0))
	var threat_fight: float = 0.0
	if threat != null:
		var tu0: BUnit = sim.u_at(threat.idx)
		var carried0: float = 0.15 * float(br.held(tu0).size()) if tu0 else 0.0
		threat_fight = KILL_VALUE * (threat_p * (1.0 + carried0) - (1.0 - threat_p) * d_cost)
	# Fights with visible opponents (a busy one is a third-party chance).
	for b in visible:
		var e: TeamIntel.EnemyBelief = b
		if float(escaped.get(e.idx, -1.0)) > sim.time:
			if e.pos.distance_to(hero.pos) <= my_reach + ESCAPE_CLEAR_PAD:
				escaped.erase(e.idx)
			else:
				continue
		var p: float = _win_chance(e, visible)
		var d2: float = e.pos.distance_to(hero.pos)
		var eu: BUnit = sim.u_at(e.idx)
		var carried: float = 0.15 * float(br.held(eu).size()) if eu else 0.0
		var ev: float = KILL_VALUE * (p * (1.0 + carried) - (1.0 - p) * d_cost)
		var gap: float = maxf(0.0, d2 - my_reach - 30.0)
		var score: float = ev - gap / ms * 6.0 + 8.0 * aggression
		var engaged: bool = sim.time - float(fight_with.get(e.idx, -99.0)) < 3.0
		var hit_us: bool = _struck_by(e.idx)
		var ehp_r: float = e.hp / maxf(1.0, e.max_hp)
		var busy: bool = _attention(e) < 0.9
		if engaged:
			score += 15.0
		if cur_mode == "hunt" and cur_target == e.idx:
			score += 10.0
		if busy and ehp_r < 0.7:
			# A third-party chance; in the loot phase, not a reason to vulture.
			score += 14.0 * (1.0 - 0.6 * calm)
		score -= _outside_cost(zs, e.pos) + _edge_cost(e.pos)
		# Pacing: a fight it did not start waits for clearly good odds in the
		# loot phase; in the final circles third parties do the fighting.
		if not hit_us:
			score -= calm * CALM_HUNT
			if not (busy and ehp_r < 0.7):
				score -= late * LATE_HUNT
		var why: String = "승산 %d%% · 대상 체력 %d%%" % [int(p * 100.0), int(ehp_r * 100.0)]
		if engaged and e.idx == last_attacker and sim.time - last_attacked_at < 3.0:
			why = "교전 중 — 승산 %d%%" % int(p * 100.0)
		elif busy and ehp_r < 0.7:
			why = "다른 적과 교전 중 · 체력 %d%% → 개입" % int(ehp_r * 100.0)
		options.append({"mode": "hunt", "goal": e.pos, "score": score, "target": e.idx, "uid": -1, "p": p,
			"reason": "%s — %s" % [e.def.name, why]})
	# Opponents that just slipped out of sight.
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
		var score2: float = KILL_VALUE * catch_p * (p2 - (1.0 - p2) * d_cost) - d3 / ms * 4.0 - _outside_cost(zs, goal) - _edge_cost(goal)
		if sim.time - float(fight_with.get(e2.idx, -99.0)) < 6.0:
			score2 += 10.0
		else:
			score2 -= calm * CALM_HUNT + late * LATE_HUNT
		if cur_mode == "chase" and cur_target == e2.idx:
			score2 += 8.0
		options.append({"mode": "chase", "goal": goal, "score": score2, "target": e2.idx, "uid": -1, "p": p2,
			"reason": "%s — %.1f초 전 목격 · 승산 %d%%" % [e2.def.name, ago, int(p2 * 100.0)]})
	# Running only pays when the fight is clearly lost and escape is likely;
	# the escape leads inward when the zone presses.
	var ev_evade: float = -INF
	if threat != null:
		var q: float = _escape_chance(threat)
		var worse: float = threat_p * 0.5
		var ev_run: float = (1.0 - q) * KILL_VALUE * (worse - (1.0 - worse) * d_cost)
		ev_evade = ev_run
		if cur_mode == "evade":
			ev_run += 6.0
		# The escape point (a search) is found only if this option wins.
		options.append({"mode": "evade", "goal": Vector2.INF, "score": ev_run, "target": -1, "uid": -1, "from": threat.pos,
			"reason": "%s 상대 승산 %d%% · 탈출 %d%% → 이탈" % [threat.def.name, int(threat_p * 100.0), int(q * 100.0)]})
	var exposed: float = 0.0
	if threat != null:
		exposed = threat_close * KILL_VALUE * (1.0 - threat_p) * d_cost * 0.8 + threat_close * maxf(absf(threat_fight), absf(ev_evade))
	# Loot phase: an opponent in reach that has not struck is not a fight yet.
	# Stepping aside costs little, and ignoring it is only mildly exposed.
	var calm_gap: bool = threat != null and not struck and calm > 0.0
	if calm_gap:
		exposed *= 1.0 - 0.8 * calm
		var space: float = 2.0 + 8.0 * calm + (4.0 if cur_mode == "evade" and str(intent.get("sub", "")) == "space" else 0.0)
		options.append({"mode": "evade", "sub": "space", "goal": Vector2.INF, "score": space, "target": -1, "uid": -1, "from": threat.pos,
			"reason": "%s 접근 · 약탈 단계 → 거리 두기" % threat.def.name})
	# Recover: hide in brush inside the safe circle while health regenerates.
	var hiding: bool = cur_mode == "recover" and str(intent.get("sub", "")) == "hide"
	var hide_limit: float = HIDE_UNTIL if hiding else 0.5
	if hp_r < hide_limit and nearest_vis > 650.0 and urgency < 0.7:
		var hide_score: float = 18.0 + (0.5 - hp_r) * 220.0 if hp_r < 0.5 else -INF
		if hiding:
			hide_score = maxf(hide_score, 14.0 + (HIDE_UNTIL - hp_r) * 90.0)
		options.append({"mode": "recover", "sub": "hide", "goal": Vector2.INF, "score": hide_score,
			"reason": "체력 %d%% · 안전 구역 숲에서 회복" % int(hp_r * 100.0), "target": -1, "uid": -1})
	if sim.env.enabled and hp_r < 0.8:
		for fountain: Dictionary in sim.env.public_fountains():
			var distance: float = hero.pos.distance_to(fountain.center)
			var eta: float = distance / ms
			if distance > 1100.0 or float(fountain.ready_at) > sim.time + minf(eta, 3.0):
				continue
			if threat != null and threat_close > 0.25:
				continue
			var risk: float = danger_at(hero, fountain.center, 1.0) / maxf(1.0, hero.hp)
			var benefit: float = minf(1.0 - hp_r, float(fountain.heal_percent))
			var score_f: float = benefit * 320.0 + (1.0 - hp_r) * 60.0 - eta * 3.0 - risk * 90.0 - _outside_cost(zs, fountain.center)
			options.append({"mode": "recover", "sub": "fountain", "goal": fountain.center, "score": score_f,
				"reason": "공용 회복샘", "target": -1, "uid": -1})
	# Loot: known items only, near us or inside the next circle.
	var loot: Dictionary = _best_loot([hero], held, visible, ms, zs, cur_mode == "loot", int(intent.get("uid", -1)), exposed)
	if not loot.is_empty():
		options.append(loot)
	# Fight noise nearby: a chance to arrive third.
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
			var sc_n: float = 22.0 + 30.0 * (hp_r - 0.5) + 10.0 * aggression - best_nd / ms * 3.0 - _outside_cost(zs, best_n.pos) \
				- calm * CALM_LISTEN - _edge_cost(best_n.pos)
			if cur_mode == "listen":
				sc_n += 6.0
			options.append({"mode": "listen", "goal": best_n.pos, "score": sc_n, "target": -1, "uid": -1,
				"reason": "%d 거리에서 전투 소음 → 어부지리" % int(best_nd)})
		var best_p: Dictionary = {}
		var best_ps: float = -INF
		for pn in public_noise:
			var age: float = sim.time - float(pn.t)
			var dpn: float = (pn.pos as Vector2).distance_to(hero.pos)
			if age > PUBLIC_NOISE_TTL or dpn < 160.0:
				continue
			var sc_p: float = 6.0 + 18.0 * (hp_r - 0.5) + 8.0 * aggression - dpn * 1.15 / ms * 1.4 - age * 1.1 - _outside_cost(zs, pn.pos) \
				- calm * CALM_SIGNAL
			if sc_p > best_ps:
				best_ps = sc_p
				best_p = pn
		if not best_p.is_empty():
			if cur_mode == "listen":
				best_ps += 6.0
			options.append({"mode": "listen", "goal": best_p.pos, "score": best_ps, "target": -1, "uid": -1,
				"reason": "%.0f초 전 보급품 변화 — 적 위치 추정" % [sim.time - float(best_p.t)]})
	_pursuit_patience(options, cur_mode, cur_target, my_reach)
	# The zone: rotate inside before the edge arrives (the slack sets how urgently).
	if bool(zs.need_move):
		var rot_score: float = 10.0 + 125.0 * urgency * urgency + (40.0 if bool(zs.outside) else 0.0)
		if cur_mode == "rotate":
			rot_score += 5.0
		options.append({"mode": "rotate", "goal": zs.goal, "score": rot_score, "target": -1, "uid": -1,
			"reason": "자기장 %s — 여유 %s" % [str(zs.label), "없음" if float(zs.slack) <= 0.0 else ("%.0f초" % float(zs.slack)) if float(zs.slack) < 999.0 else "충분"]})
	# Final circles: hold brush or cover deep inside the safe circle.
	if late > 0.0:
		hold_goal = hold_spot(sim, intel, zs, hero.pos, hold_goal, sim.radius(hero))
		var hold_s: float = 6.0 + 22.0 * late - exposed - _outside_cost(zs, hold_goal)
		if cur_mode == "hold":
			hold_s += 6.0
		options.append({"mode": "hold", "goal": hold_goal, "score": hold_s, "target": -1, "uid": -1,
			"reason": "마지막 원 — %s에서 대기" % ("수풀" if sim.arena.forest_at(hold_goal) >= 0 else "안쪽")})
	# Roam: sweep unexplored ground inside the safe circle.
	if roam_goal == Vector2.INF or hero.pos.distance_to(roam_goal) < 140.0 or sim.time > roam_until or _outside_cost(zs, roam_goal) > 0.0:
		roam_goal = _pick_roam_goal()
		roam_until = sim.time + 14.0
	options.append({"mode": "roam", "goal": roam_goal, "score": 8.0 - 6.0 * late - exposed, "reason": "안전 구역 탐색", "target": -1, "uid": -1})
	for o in options:
		if str(o.mode) == "recover" or str(o.mode) == "listen":
			o.score = float(o.score) - exposed
	if threat != null and threat_close >= 0.5 and ev_evade > -INF and not calm_gap:
		for o in options:
			var m: String = str(o.mode)
			if m == "roam" or m == "listen" or m == "recover" or m == "hold" or (m == "loot" and (o.goal as Vector2).distance_to(hero.pos) > 80.0):
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
	if str(best.get("mode", "")) == "loot":
		_loot_reason(best, held)
	elif str(best.get("mode", "")) == "evade":
		best["goal"] = _br_escape_point(best.from, zs)
	elif str(best.get("mode", "")) == "recover" and str(best.get("sub", "")) == "hide":
		best["goal"] = _br_hide_point(zs)
	_set_intent(best)


# The deathmatch pursuit patience: a pursuit that lands nothing is dropped
# for a while; a target staying in sight within reach has not escaped.
func _pursuit_patience(options: Array, cur_mode: String, cur_target: int, my_reach: float) -> void:
	if cur_mode in ["hunt", "chase"] and cur_target >= 0:
		if not hunt_track.has(cur_target):
			hunt_track[cur_target] = sim.time
		var progress_at: float = maxf(float(hunt_track[cur_target]), float(last_hit_on.get(cur_target, -99.0)))
		var tb: TeamIntel.EnemyBelief = intel.enemies.get(cur_target)
		if tb and tb.visible and tb.pos.distance_to(hero.pos) <= my_reach + ESCAPE_REACH_PAD:
			contact_on[cur_target] = sim.time
		progress_at = maxf(progress_at, float(contact_on.get(cur_target, -99.0)))
		if sim.time - progress_at > pursuit_window():
			escaped[cur_target] = sim.time + 12.0
			hunt_track.erase(cur_target)
			contact_on.erase(cur_target)
			for o in options:
				if str(o.mode) in ["hunt", "chase"] and int(o.target) == cur_target:
					o.score = -INF
	for key in hunt_track.keys():
		if not (cur_mode in ["hunt", "chase"]) or int(key) != cur_target:
			hunt_track.erase(key)
			contact_on.erase(key)


# Cost of a goal outside the safe circle: grows with zone urgency and damage.
func _outside_cost(zs: Dictionary, p: Vector2) -> float:
	if zs.is_empty() or not p.is_finite():
		return 0.0
	var over: float = p.distance_to(zs.safe_center) - float(zs.safe_radius)
	if over <= 0.0:
		return 0.0
	return (10.0 + over * 0.06) * (0.3 + 1.7 * float(zs.urgency)) + (60.0 if bool(zs.damaging) and p.distance_to(zs.center) > float(zs.radius) else 0.0)


# ---------------------------------------------------------------- items

# Items that heroes of this team see now enter the team's memory; a known
# item gone from the field is forgotten once we could notice (in sight or
# within earshot) and becomes a public-style noise.
func _remember_items(watchers: Array) -> void:
	var br: BattlegroundMode = sim.battleground
	var present: Dictionary = {}
	for it in br.field:
		present[int(it.uid)] = it
		if known_items.has(int(it.uid)):
			continue
		var p: Vector2 = it.pos
		for w in watchers:
			var u: BUnit = w
			if u.alive and u.pos.distance_to(p) <= sim.sensor_range(u) and sim.arena.line_of_sight(u.pos, p, 2.0):
				known_items[int(it.uid)] = {"pos": p, "item": str(it.item), "rarity": ItemDefs.rarity_of(str(it.item)), "t": sim.time}
				break
	for uid in known_items.keys():
		if present.has(int(uid)):
			continue
		var kp: Vector2 = known_items[uid].pos
		for w2 in watchers:
			var u2: BUnit = w2
			if not u2.alive:
				continue
			var d: float = u2.pos.distance_to(kp)
			if d <= HEAR_RANGE or (d <= sim.sensor_range(u2) and sim.arena.line_of_sight(u2.pos, kp, 2.0)):
				known_items.erase(uid)
				if d > 90.0:
					_add_public_noise(kp, "item")
				break


# Battleground items are not public: only our own memory feeds the noise
# (_remember_items) and fountains keep their public ready time.
func _scan_public_signals() -> void:
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


# Best known item for one of `who` to fetch: gain for that hero minus the
# walk, nearby danger, a nearer rival and the zone. claims: uid -> member idx
# already taken by a teammate (squad brain). Returns an intent or {}.
func _best_loot(who: Array, held: Array, visible: Array, ms: float, zs: Dictionary, sticky: bool, cur_uid: int, exposed: float, claims: Dictionary = {}) -> Dictionary:
	var u: BUnit = who[0]
	var gains: Dictionary = {}
	var mine: float = maxf(1.0, _power_self()) if u == hero else 1.0
	var menace: Dictionary = {}
	for b in visible:
		var eb5: TeamIntel.EnemyBelief = b
		menace[eb5.idx] = (_power_enemy(eb5) * _attention(eb5) / mine) if u == hero else 0.6
	var best: Dictionary = {}
	var best_s: float = -INF
	for uid in known_items:
		if claims.has(int(uid)) and int(claims[uid]) != u.idx:
			continue
		var k: Dictionary = known_items[uid]
		var ipos: Vector2 = k.pos
		var dist: float = u.pos.distance_to(ipos)
		var inside_next: bool = not zs.is_empty() and ipos.distance_to(zs.safe_center) <= float(zs.safe_radius)
		if dist > LOOT_RANGE and not inside_next:
			continue
		var item_id: String = str(k.item)
		if not gains.has(item_id):
			gains[item_id] = ItemValuation.gain(u.def, item_id, held, DeathmatchMode.SLOTS)
		var g: float = gains[item_id]
		if g <= 0.0 or (held.size() >= DeathmatchMode.SLOTS and g < 10.0):
			continue
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
		var score: float = g * 0.95 * rival * (1.0 - clampf(danger * 0.45, 0.0, 0.8)) - eta * 1.9 - _outside_cost(zs, ipos)
		if sticky and cur_uid == int(uid):
			score += 10.0
		if dist > 80.0:
			score -= exposed
		if score > best_s:
			best_s = score
			best = {"mode": "loot", "goal": ipos, "score": score, "uid": int(uid), "target": -1, "item": item_id, "reason": ""}
	return best


func _loot_reason(o: Dictionary, held: Array) -> void:
	var item_id: String = str(o.get("item", ""))
	if item_id == "":
		return
	var v: Dictionary = ItemValuation.value(hero.def, item_id, held)
	o["reason"] = "%s (%s) — %s" % [str(ItemDefs.get_def(item_id).name), ItemDefs.RARITY_NAMES[ItemDefs.rarity_of(item_id)], str(v.reason)]


# ---------------------------------------------------------------- places

# Explore unswept ground inside the safe circle (inside the current circle
# before the next one is announced), leaning toward the map centre, where
# both the zone and the richer items are (public knowledge).
func _pick_roam_goal() -> Vector2:
	var zs: Dictionary = zone_state
	var c: Vector2 = zs.get("safe_center", sim.arena.center())
	var r: float = float(zs.get("safe_radius", 1e9))
	var mid: Vector2 = sim.arena.center()
	var half: float = 0.5 * Vector2(sim.arena.width, sim.arena.height).length()
	# Loot phase: sweep nearby ground, no pull toward the centre (B-SQUAD).
	var calm: float = float(zs.get("calm", 0.0))
	var pref_d: float = lerpf(900.0, 650.0, calm)
	var pull: float = 25.0 * (1.0 - calm)
	var best: Vector2 = c
	var best_v: float = -INF
	var gx: int = int(ceil(sim.arena.width / SWEEP_CELL))
	var gy: int = int(ceil(sim.arena.height / SWEEP_CELL))
	for cx in gx:
		for cy in gy:
			var p: Vector2 = Vector2((cx + 0.5) * SWEEP_CELL, (cy + 0.5) * SWEEP_CELL)
			if p.x < sim.arena.min_x + 60.0 or p.x > sim.arena.max_x - 60.0 or p.y < sim.arena.min_y + 60.0 or p.y > sim.arena.max_y - 60.0:
				continue
			if p.distance_to(c) > r * 0.85:
				continue
			var d: float = p.distance_to(hero.pos)
			if d < 250.0:
				continue
			var v: float = -absf(d - pref_d) * 0.05 + rng.randf() * 30.0 + _staleness(p) * 0.9 - p.distance_to(mid) / half * pull
			if v > best_v:
				best_v = v
				best = p
	return sim.arena.resolve_circle(best, sim.radius(hero))


func _br_hide_point(zs: Dictionary) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_v: float = -INF
	for k in sim.arena.forest_x.size():
		var c: Vector2 = Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k])
		var d: float = c.distance_to(hero.pos)
		if d > 1400.0:
			continue
		var v: float = -d - _outside_cost(zs, c) * 20.0
		for b in intel.alive_enemies():
			var eb: TeamIntel.EnemyBelief = b
			if eb.confidence > 0.3 and eb.pos.distance_to(c) < 420.0:
				v -= 500.0
		if v > best_v:
			best_v = v
			best = c
	if best == Vector2.INF:
		return zs.get("goal", hero.pos)
	return sim.arena.resolve_circle(best, sim.radius(hero))


# The deathmatch escape point, but never deeper into the zone.
func _br_escape_point(threat_c: Vector2, zs: Dictionary) -> Vector2:
	var best: Vector2 = hero.pos + (hero.pos - threat_c).normalized() * 320.0
	var best_v: float = -INF
	var cands: Array = []
	for k in 8:
		cands.append(hero.pos + Vector2.from_angle(k * TAU / 8.0) * 340.0)
	for k in sim.arena.forest_x.size():
		var fc: Vector2 = Vector2(sim.arena.forest_x[k], sim.arena.forest_y[k])
		if fc.distance_to(hero.pos) < 700.0:
			cands.append(fc)
	for c in cands:
		var p: Vector2 = sim.arena.resolve_circle(c, sim.radius(hero))
		var v: float = p.distance_to(threat_c) - hero.pos.distance_to(threat_c) - p.distance_to(hero.pos) * 0.35 - _outside_cost(zs, p) * 3.0
		if sim.arena.forest_at(p) >= 0:
			v += 140.0
		for b in intel.visible_enemies():
			if (b as TeamIntel.EnemyBelief).pos.distance_to(p) < 260.0:
				v -= 200.0
		if v > best_v:
			best_v = v
			best = p
	return best


# Hidden opponents rotate too: belief particles outside the safe circle move
# toward it at DRIFT_RATE of the opponent's speed (deterministic). Shared
# with the squad brain (dt = its intent interval).
static func drift_beliefs(sim: BattleSim, intel: TeamIntel, zs: Dictionary, dt: float) -> void:
	if zs.is_empty() or not bool(zs.get("known", false)):
		return
	var c: Vector2 = zs.safe_center
	var r: float = float(zs.safe_radius)
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.visible or eb.controlled_by_us or not eb.is_hero:
			continue
		var step: float = eb.def.stat("moveSpeed") * dt * DRIFT_RATE
		var moved: bool = false
		var frozen: bool = eb.frozen_at >= 0.0
		for i in eb.particles.size():
			var p: Vector2 = eb.particles[i]
			var over: float = p.distance_to(c) - r * 0.9
			if over > 0.0:
				var q: Vector2 = p + (c - p).normalized() * minf(step, over)
				# Frozen particles are re-resolved when the belief thaws.
				eb.particles[i] = q if frozen else sim.arena.resolve_circle(q, eb.radius)
				moved = true
		if not moved:
			continue
		if frozen:
			var m: Vector2 = Vector2.ZERO
			for i in eb.particles.size():
				m += eb.particles[i] * eb.weights[i]
			eb.pos = m
		else:
			intel._estimate(eb)


# ---------------------------------------------------------------- tactics hooks

func _apply_intent_to_plan() -> void:
	super._apply_intent_to_plan()
	if str(intent.get("mode", "")) in ["rotate", "hold"]:
		var hit_recently: bool = hero != null and sim.time - hero.last_damage_time < 2.5
		if str(plan.stance) == "ENGAGE" and not bool(plan.get("fighting", false)):
			plan.stance = "POKE"
			plan.go = false
		elif str(plan.stance) == "DISENGAGE" and not hit_recently:
			plan.stance = "POKE"


func _mode_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_br_move_points(u, ctx, pts)
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("move_points", t0)


func _br_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var mode: String = str(intent.get("mode", ""))
	if mode == "hold":
		var hg: Vector2 = intent.get("goal", Vector2.INF)
		if hg.is_finite():
			var hold_label: String = "자리 잡기: %s" % str(intent.get("reason", "")).split(" — ")[-1]
			pts.append([hg, hold_label, 60.0])
			if u.pos.distance_to(hg) > 200.0:
				pts.append([u.pos + (hg - u.pos).normalized() * 180.0, hold_label, 42.0])
		return
	if mode != "rotate":
		super._mode_move_points(u, ctx, pts)
		return
	var goal: Vector2 = intent.get("goal", Vector2.INF)
	if not goal.is_finite():
		return
	var reward: float = 70.0 + 110.0 * float(zone_state.get("urgency", 0.0))
	var label_text: String = "자기장 이동: %s" % str(intent.get("reason", "")).split(" — ")[0]
	pts.append([goal, label_text, reward])
	if u.pos.distance_to(goal) > 200.0:
		pts.append([u.pos + (goal - u.pos).normalized() * 180.0, label_text, reward * 0.75])


func _mode_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	super._mode_adjust(u, ctx, cands)
	zone_move_adjust(sim, u, cands, zone_state)
	# Loot phase, not hunting: no first shot at an opponent that has not
	# struck (passing within reach while looting or rotating is not a fight).
	var calm: float = float(zone_state.get("calm", 0.0))
	if calm > 0.0 and not (str(intent.get("mode", "")) in ["hunt", "chase"]):
		for item in cands:
			var c: Dictionary = item
			var cmd: Dictionary = c.cmd
			if str(cmd.get("kind", "")) == "move":
				continue
			var ti: int = int(cmd.get("target", -1))
			var foe: TeamIntel.EnemyBelief = intel.enemies.get(ti)
			if foe == null or not foe.is_hero or _struck_by(ti) or float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0:
				continue
			Doctrine._note(c, -CALM_FIRST_SHOT * calm, "약탈 단계 · 먼저 공격하지 않음")
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("mode_adjust", t0)


# A calm hero walks straight to its loot / roam / listen / rotate goal.
func _lod_travel_goal(u: BUnit) -> Vector2:
	if str(intent.get("mode", "")) in ["rotate", "hold"]:
		var g = intent.get("goal", Vector2.INF)
		return g if g is Vector2 else Vector2.INF
	return super._lod_travel_goal(u)


func _lod_travel_label(u: BUnit) -> String:
	if str(intent.get("mode", "")) == "rotate":
		return "자기장 이동"
	if str(intent.get("mode", "")) == "hold":
		return "자리 잡기"
	return super._lod_travel_label(u)


# Standing in the zone while it deals damage is urgent even with no enemy near.
func lod_urgent(u: BUnit) -> bool:
	if super.lod_urgent(u):
		return true
	return outside_zone_now(sim, u)


func explain(u: BUnit) -> Dictionary:
	var out: Dictionary = super.explain(u)
	out["battleground"] = {"zone": zone_state.duplicate(), "known_items": known_items.size(),
		"death_cost": death_cost(sim.battleground.held(u).size()) if sim.battleground else 0.0,
		"mode_label": str(BR_LABELS.get(str(intent.get("mode", "")), ""))}
	return out


# ---------------------------------------------------------------- shared zone helpers

# Reading of the public zone view for a hero at p moving at ms:
#  known       next circle announced (else the safe circle is the current one)
#  safe_center / safe_radius   circle to be inside of
#  outside     p is outside the current circle; damaging: zone damage is on
#  t_out       when the edge reaches p (INF if p stays inside this phase)
#  travel      seconds to walk ZONE_INNER deep into the safe circle
#  slack       t_out - now - travel (<= 0: late)
#  urgency     0..1 from the slack; need_move / goal: whether and where to rotate
# Uses only public_view(t) and the public timetable (zone speed is a setting).
static func zone_sense(v: Dictionary, p: Vector2, ms: float, timetable: Array, now: float, rot_slack: float = ROTATE_SLACK) -> Dictionary:
	var c: Vector2 = v.center
	var r: float = float(v.radius)
	var known: bool = bool(v.next_known)
	var sc: Vector2 = v.next_center if known else c
	var sr: float = float(v.next_radius) if known else r
	var state: String = str(v.state)
	var damaging: bool = float(v.dps_ratio) > 0.0
	var outside: bool = int(v.phase) > 0 and p.distance_to(c) > r
	# When the edge reaches p: sample the coming (or running) shrink.
	var t_out: float = INF
	if outside:
		t_out = now
	elif known and p.distance_to(sc) > sr:
		var s0: float = now
		var s1: float = float(v.t_state_end)
		if state == "loot" or state == "wait":
			var k: int = int(v.phase) + 1
			if k >= 1 and k <= timetable.size():
				var row: Dictionary = timetable[k - 1]
				s0 = float(row.shrink_start)
				s1 = float(row.shrink_end)
		var c0: Vector2 = c
		var r0: float = r
		if state == "shrink":
			# Interpolate from now: the circle shrinks linearly to the next one.
			s0 = now
		for i in range(1, 13):
			var f: float = float(i) / 12.0
			var tc: Vector2 = c0.lerp(sc, f)
			var tr: float = lerpf(r0, sr, f)
			if p.distance_to(tc) > tr:
				t_out = lerpf(s0, s1, f)
				break
		if t_out == INF:
			t_out = s1
	var inner: float = sr * ZONE_INNER
	var d_in: float = maxf(0.0, p.distance_to(sc) - inner)
	var travel: float = d_in * 1.25 / maxf(40.0, ms)
	var slack: float = (t_out - now - travel) if t_out < INF else 9999.0
	var urgency: float = 0.0
	if outside and damaging:
		urgency = 1.0
	elif slack < 9999.0:
		urgency = clampf(1.0 - slack / rot_slack, 0.0, 1.0)
	elif known and p.distance_to(sc) > sr * 0.85:
		urgency = 0.08
	var need_move: bool = known and p.distance_to(sc) > inner or outside
	var goal: Vector2 = sc + (p - sc).normalized() * minf(p.distance_to(sc), inner) if p.distance_to(sc) > 1.0 else sc
	var label: String = "밖 — 즉시 진입" if outside else ("수축 중" if state == "shrink" else ("다음 원 공개" if known else "대기"))
	return {"known": known, "center": c, "radius": r, "safe_center": sc, "safe_radius": sr, "outside": outside,
		"damaging": damaging, "t_out": t_out, "travel": travel, "slack": slack, "urgency": urgency,
		"need_move": need_move, "goal": goal, "label": label, "phase": int(v.phase), "state": state}


static func outside_zone_now(sim: BattleSim, u: BUnit) -> bool:
	var br: BattlegroundMode = sim.battleground
	if br == null:
		return false
	var v: Dictionary = br.zone_view()
	return int(v.phase) > 0 and float(v.dps_ratio) > 0.0 and u.pos.distance_to(v.center) > float(v.radius)


# Move candidates ending outside the circle pay for it (more while it deals
# damage); stepping back in from outside earns a bonus.
static func zone_move_adjust(sim: BattleSim, u: BUnit, cands: Array, zs: Dictionary) -> void:
	if zs.is_empty() or int(zs.get("phase", 0)) <= 0 and not bool(zs.get("known", false)):
		return
	var c: Vector2 = zs.center
	var r: float = float(zs.radius)
	if str(zs.get("state", "")) == "shrink":
		r = lerpf(r, float(zs.safe_radius), 0.06)
	var dps: float = float(sim.battleground.zone_view().dps_ratio) if sim.battleground else 0.0
	var now_out: float = u.pos.distance_to(c) - r
	for item in cands:
		var cand: Dictionary = item
		var cmd: Dictionary = cand.cmd
		if str(cmd.get("kind", "")) != "move":
			continue
		var endpoint: Vector2 = cmd.get("goal", u.pos)
		var out: float = endpoint.distance_to(c) - r
		if out > 0.0:
			Doctrine._note(cand, -(25.0 + out * 0.12) * (1.0 + 40.0 * dps), "자기장 밖")
		if now_out > 0.0 and out < now_out:
			Doctrine._note(cand, minf(120.0, (now_out - out) * 0.5), "자기장 안으로")


# Half the map diagonal (public: the map size), the zone's starting radius.
static func half_diag(sim: BattleSim) -> float:
	return 0.5 * Vector2(sim.arena.width, sim.arena.height).length()


# 1 during the loot phase (no circle shrinking yet), easing to 0 over the
# first shrink, then 0 (public view and timetable only).
static func calm_factor(v: Dictionary, timetable: Array, now: float) -> float:
	var ph: int = int(v.phase)
	if ph <= 0:
		return 1.0
	if ph == 1 and str(v.state) == "shrink" and not timetable.is_empty():
		var row: Dictionary = timetable[0]
		var dur: float = maxf(1.0, float(row.shrink_end) - float(row.shrink_start))
		return clampf((float(v.t_state_end) - now) / dur, 0.0, 1.0)
	return 0.0


# Solo pacing: the loot-phase calm, then a milder one through the first two
# circles (with 30 heroes in a free-for-all the field otherwise thins out
# long before the zone does): at least SOLO_CALM[phase].
static func solo_calm(v: Dictionary, timetable: Array, now: float) -> float:
	var c: float = calm_factor(v, timetable, now)
	var ph: int = int(v.phase)
	if ph >= 1 and ph < SOLO_CALM.size():
		c = maxf(c, float(SOLO_CALM[ph]))
	return c


# 0 while the safe circle is wide, 1 in the final circles: from the radius of
# the circle we must be inside (the next one once announced) over the half
# diagonal, 0.24 -> 0 ... 0.12 -> 1 (Z3 ~0.4, Z4 on 1).
static func late_factor(v: Dictionary, hd: float) -> float:
	var sr: float = float(v.next_radius) if bool(v.next_known) else float(v.radius)
	return clampf((0.24 - sr / maxf(1.0, hd)) / 0.12, 0.0, 1.0)


# [centre, radius] of the circle dt seconds from now, from the public view
# and the public timetable: the current circle until a known shrink starts,
# then linear toward the announced one.
static func circle_at(v: Dictionary, timetable: Array, now: float, dt: float) -> Array:
	var c: Vector2 = v.center
	var r: float = float(v.radius)
	var st: String = str(v.state)
	if st == "final" or not bool(v.next_known):
		return [c, r]
	var nc: Vector2 = v.next_center
	var nr: float = float(v.next_radius)
	var t_end: float = float(v.t_state_end)
	if st == "shrink":
		var f: float = clampf(dt / maxf(0.001, t_end - now), 0.0, 1.0)
		return [c.lerp(nc, f), lerpf(r, nr, f)]
	var t: float = now + dt
	if t <= t_end:
		return [c, r]
	var k: int = int(v.phase) + 1
	if k < 1 or k > timetable.size():
		return [c, r]
	var row: Dictionary = timetable[k - 1]
	var f2: float = clampf((t - float(row.shrink_start)) / maxf(0.001, float(row.shrink_end) - float(row.shrink_start)), 0.0, 1.0)
	return [c.lerp(nc, f2), lerpf(r, nr, f2)]


# Cost of fighting at p while the zone closes: p lies less than EDGE_PAD px
# inside the circle as it will be EDGE_LOOK s from now (0 deep inside, about
# 22 on that edge, up to 45 beyond it).
static func edge_cost_at(v: Dictionary, timetable: Array, now: float, p: Vector2) -> float:
	if not p.is_finite() or (int(v.phase) <= 0 and not bool(v.next_known)):
		return 0.0
	var circ: Array = circle_at(v, timetable, now, EDGE_LOOK)
	var margin: float = float(circ[1]) - p.distance_to(circ[0])
	if margin >= EDGE_PAD:
		return 0.0
	return clampf((EDGE_PAD - margin) * 0.1, 0.0, 45.0)


func _edge_cost(p: Vector2) -> float:
	return edge_cost_at(_zv, _br_timetable, sim.time, p) if not _zv.is_empty() else 0.0


# A place to wait out the final circles: brush deep inside the safe circle
# near `from`, away from believed opponents; the previous spot is kept while
# it stays deep inside and quiet. Without brush, the zone goal.
static func hold_spot(sim: BattleSim, intel: TeamIntel, zs: Dictionary, from: Vector2, prev: Vector2, body_r: float) -> Vector2:
	var c: Vector2 = zs.get("safe_center", sim.arena.center())
	var r: float = float(zs.get("safe_radius", 1e9))
	var quiet: bool = true
	if prev.is_finite():
		for b in intel.alive_enemies():
			var eb0: TeamIntel.EnemyBelief = b
			if eb0.is_hero and eb0.confidence > 0.3 and eb0.pos.distance_to(prev) < 380.0:
				quiet = false
				break
		if quiet and prev.distance_to(c) <= r * 0.75:
			return prev
	var best: Vector2 = Vector2.INF
	var best_v: float = -INF
	var a: Arena = sim.arena
	for k in a.forest_x.size():
		var fc: Vector2 = Vector2(a.forest_x[k], a.forest_y[k])
		if fc.distance_to(c) > r * 0.7:
			continue
		var d: float = fc.distance_to(from)
		if d > 1400.0:
			continue
		var v: float = -d * 0.5 - fc.distance_to(c) / maxf(1.0, r) * 80.0
		for b2 in intel.alive_enemies():
			var eb: TeamIntel.EnemyBelief = b2
			if eb.is_hero and eb.confidence > 0.3 and eb.pos.distance_to(fc) < 420.0:
				v -= 500.0
		if v > best_v:
			best_v = v
			best = fc
	if best == Vector2.INF:
		return zs.get("goal", c)
	return a.resolve_circle(best, body_r)
