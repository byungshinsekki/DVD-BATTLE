class_name BattlegroundSquadBrain
extends TacticianBrain

# V2 battleground duo / trio brain (DESIGN_V2 §3.6), one per team. The
# inherited tactician aims, dodges and picks skills; this layer chooses what
# the squad does every INTENT_INTERVAL s and gives each member a goal:
#   revive     a downed member with no standing enemy in sight near it: the
#              chosen member channels (at brush / cover within SPOT_REACH px
#              when a threat was seen lately; the downed one crawls there),
#              the others cover facing the last threat
#   contest    enemies stand over a downed member and the squad's odds are
#              decent: fight them off, body-block the finishers, then revive;
#              a trio may channel while the third member holds the enemy at
#              least COVER_GAP px away (covered revive)
#   engage     fight one visible enemy team (enemies are grouped by team; the
#              fight plan only sees that team and whoever is within 650 px,
#              never a centroid of every enemy, the measured clumping cause)
#   third      engage a team that is already trading blows with another
#   disengage  leave a fight the squad would lose (leaving a downed member
#              behind costs SAVE_VALUE), inward when the zone presses
#   rotate     move inside the next circle before the edge arrives; the
#              member with the least slack sets the urgency (ROTATE_SLACK)
#   loot       known items (team memory) near the leader, one member per item
#   hold       final circles: brush deep inside the safe circle, let others fight
#   regroup    the squad has spread past the leash
#   roam       explore inside the safe circle
# Pacing (B-SQUAD): in the loot phase a fight nobody started costs
# CALM_ENGAGE, in the final circles LATE_ENGAGE (third parties excepted), and
# a fight where the zone edge will be within EDGE_LOOK s pays the edge cost.
# Members keep within LEASH_MAX px of the leader (the first standing member)
# and loot only within that leash. A downed member crawls toward its squad and
# away from standing enemies (drag-away), to its revive spot when one is set,
# and holds still while it is revived. The knocking side weighs finishing a
# downed enemy against its standing teammates (standing enemies first while
# they are near; a reviver is always worth a hit). Zone math and shared
# helpers: BattlegroundSoloBrain. AI inputs are the team's own observations,
# the zone's public view and public events only.

const INTENT_INTERVAL := 0.5
const LEASH_MIN := 450.0
const LEASH_MAX := 600.0
const LOCAL_REACH := 1150.0
const ENGAGE_REACH := 1300.0
const LOOT_RANGE := 1500.0
const HEAR_RANGE := 950.0
const KILL_VALUE := 100.0
const SWEEP_CELL := 400.0
const ROTATE_SLACK := 45.0      # squads start rotating earlier than solo heroes (30 s)
const SAVE_VALUE := 0.9         # a downed teammate saved, in kills
const CONTEST_REACH := 700.0    # standing enemies this close to a downed member threaten it
const SAFE_REVIVE := 520.0      # no standing enemy in sight this close: revive now
const COVER_GAP := 380.0        # covered revive: the threat stays this far from the downed
const SPOT_REACH := 200.0       # crawl at most this far to brush / cover before a revive
const THREAT_MEMORY := 6.0      # s a threat seen near a downed member shapes its revive spot
const CALM_ENGAGE := 24.0       # loot phase: cost of a fight nobody started
const LATE_ENGAGE := 14.0       # final circles: cost of a fight nobody started
const BUSY_POWER := 0.62        # an enemy closer to a third party fights us at this share
const MODE_LABELS := {"revive": "소생", "contest": "소생 엄호 교전", "engage": "교전", "disengage": "이탈", "rotate": "자기장 이동",
	"loot": "보급", "roam": "탐색", "regroup": "집결", "third": "제3자 개입", "hold": "자리 잡기", "dead": "탈락"}

var members: Array[BUnit] = []
var squad_intent: Dictionary = {"mode": "roam", "reason": "", "since": 0.0, "target_team": -1}
var member_goal: Dictionary = {}   # member idx -> {"goal", "label", "reward", "role", "target", "uid"}
var known_items: Dictionary = {}   # uid -> {"pos", "item", "rarity", "t"} (seen by any member)
var claims: Dictionary = {}        # item uid -> member idx
var zone_state: Dictionary = {}
var leader: BUnit = null
var next_intent_at: float = 0.0
var roam_goal: Vector2 = Vector2.INF
var roam_until: float = 0.0
var hold_goal: Vector2 = Vector2.INF
var swept: Dictionary = {}
var fight_with: Dictionary = {}    # enemy hero idx -> last time it traded damage with us (seen)
var hit_by: Dictionary = {}        # enemy idx -> last time it damaged one of us (attacker seen)
var clash: Dictionary = {}         # enemy team -> last observed time it fought a third team
var enemy_revives: Dictionary = {} # observed downed idx -> observed reviver idx, or -1
var enemy_revive_until: Dictionary = {} # observed target -> publicly known channel end
var enemy_revivers: Dictionary = {} # observed reviver -> publicly known channel end
var threat_seen: Dictionary = {}   # downed member idx -> {"pos", "t"}: last standing enemy seen near it
var revive_spots: Dictionary = {}  # downed member idx -> spot chosen for its revive
var noises: Array = []
var intent_log: Array = []
var _timetable: Array = []
var _zv: Dictionary = {}
var _hd: float = 1.0

func _init(s: BattleSim, t: int) -> void:
	super(s, t)
	label = "배틀그라운드 분대 AI"
	for u in s.heroes:
		if u.team == t:
			members.append(u)
	rng.seed = s.seed_value * 41 + t * 13 + 7
	# Teams update their intent on staggered ticks (15 phases per interval),
	# not all on the same tick.
	next_intent_at = INTENT_INTERVAL * float(t % 15) / 15.0
	if s.battleground:
		_timetable = BrZone.schedule_rows(s.battleground.zone_speed)
	_hd = BattlegroundSoloBrain.half_diag(s)


func _standing() -> Array[BUnit]:
	var out: Array[BUnit] = []
	var br: BattlegroundMode = sim.battleground
	for m in members:
		if m.alive and not br.is_downed(m):
			out.append(m)
	return out


func _team_of(idx: int) -> int:
	var u: BUnit = sim.u_at(idx)
	var guard: int = 0
	while u != null and not u.is_hero and u.owner_idx >= 0 and guard < 6:
		u = sim.u_at(u.owner_idx)
		guard += 1
	return u.team if u else -1


# ---------------------------------------------------------------- events

func pre_tick(s: BattleSim) -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_expire_enemy_revives()
	var codes: PackedByteArray = s.ai_event_codes(s.ai_events)
	for ei in s.ai_events.size():
		var code: int = codes[ei]
		if code != 0 and code != 15 and code != 16:
			continue
		var ev: Dictionary = s.ai_events[ei]
		if code == 0:
			var ty: String = str(ev.type)
			match ty:
				"BR_ELIMINATED":
					var b: TeamIntel.EnemyBelief = intel.enemies.get(int(ev.g))
					if b:
						b.dead = true
						b.visible = false
					_forget_enemy_revive_target(int(ev.g))
					_forget_enemy_reviver(int(ev.g))
					fight_with.erase(int(ev.g))
					hit_by.erase(int(ev.g))
				"BR_REVIVE_START", "BR_REVIVE_CANCEL", "BR_REVIVED":
					_observe_enemy_revive(ev)
			continue
		var st: int = _team_of(int(ev.s))
		var gt: int = _team_of(int(ev.g))
		if st < 0 or gt < 0 or st == gt:
			continue
		var s_seen: bool = bool((ev.sv as Array)[team])
		var seen_ev: bool = s_seen or bool((ev.gv as Array)[team])
		if st == team:
			fight_with[int(ev.g)] = float(ev.t)
		elif gt == team:
			# Who hit us is known only when we see the attacker.
			if s_seen:
				fight_with[int(ev.s)] = float(ev.t)
				hit_by[int(ev.s)] = float(ev.t)
		elif seen_ev:
			# Two other teams trading blows in our sight: a third-party chance.
			clash[st] = float(ev.t)
			clash[gt] = float(ev.t)
		elif ev.has("pos"):
			for m in members:
				if m.alive and (ev.pos as Vector2).distance_to(m.pos) < HEAR_RANGE:
					noises.append({"pos": ev.pos, "t": float(ev.t)})
					break
	if noises.size() > 24:
		noises = noises.slice(noises.size() - 24)
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("events", t0)
	super.pre_tick(s)
	if s.time >= next_intent_at and s.battleground != null:
		var t1: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
		_update_squad_intent()
		if BattlegroundAIProfile.lprof_on:
			BattlegroundAIProfile.lp_add("intent", t1)


# Revive events are private observations, unlike public eliminations. Seeing
# only one participant does not reveal the other participant's identity.
# Keep source and target knowledge separately and join them only when both
# are visible in the event snapshot. Hidden completion/cancellation cannot
# erase that memory; its known five-second deadline can expire normally.
func _observe_enemy_revive(ev: Dictionary) -> void:
	var source_seen: bool = bool((ev.sv as Array)[team]) and intel.enemies.has(int(ev.s))
	var target_seen: bool = bool((ev.gv as Array)[team]) and intel.enemies.has(int(ev.g))
	if not source_seen and not target_seen:
		return
	var source: int = int(ev.s)
	var target: int = int(ev.g)
	if str(ev.type) == "BR_REVIVE_START":
		var until: float = float(ev.t) + BattlegroundMode.REVIVE_TIME
		if source_seen:
			enemy_revivers[source] = until
		if target_seen:
			enemy_revives[target] = source if source_seen else -1
			enemy_revive_until[target] = until
		return
	if target_seen:
		_forget_enemy_revive_target(target)
	if source_seen:
		_forget_enemy_reviver(source)


func _forget_enemy_revive_target(target: int) -> void:
	# An already observed source/target association is knowledge we can use.
	var known_source: int = int(enemy_revives.get(target, -1))
	if known_source >= 0:
		enemy_revivers.erase(known_source)
	enemy_revives.erase(target)
	enemy_revive_until.erase(target)


func _forget_enemy_reviver(source: int) -> void:
	enemy_revivers.erase(source)
	for target in enemy_revives.keys():
		if int(enemy_revives[target]) == source:
			enemy_revives.erase(target)
			enemy_revive_until.erase(target)


func _expire_enemy_revives() -> void:
	for target in enemy_revive_until.keys():
		if sim.time >= float(enemy_revive_until[target]):
			_forget_enemy_revive_target(int(target))
	for source in enemy_revivers.keys():
		if sim.time >= float(enemy_revivers[source]):
			_forget_enemy_reviver(int(source))


# ---------------------------------------------------------------- plan

func _plan() -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_plan_body()
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("plan_total", t0)


func _plan_body() -> void:
	plan.t = sim.time
	aprof.clear()
	eprof.clear()
	var standing: Array[BUnit] = _standing()
	for a in standing:
		aprof[a.idx] = _ally_profile(a)
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.controlled_by_us:
			continue
		if not eb.visible:
			var near: bool = false
			for a2 in standing:
				if a2.pos.distance_to(eb.pos) <= LOCAL_REACH:
					near = true
					break
			if not near:
				continue
		var pr: Dictionary = KitModel.enemy_profile(intel, eb)
		var w: float = 1.0 if eb.visible else clampf(eb.confidence, 0.2, 0.7) * 0.6
		var down: bool = eb.visible and eb.has_status("downed")
		if down:
			# A downed hero fights no more: no threat, but it is still worth a kill.
			pr["dps"] = 0.0
			pr["burst"] = 0.0
			pr["cc"] = 0.0
		pr["w"] = w
		pr["b"] = eb
		var st: Dictionary = KitModel.stats_of_def(eb.def)
		pr["ehp"] = (eb.hp + eb.shield) * (1.0 + (float(st.armor) + float(st.mr)) * 0.5 / 100.0)
		pr["threat"] = float(pr.dps) * 6.0 + float(pr.burst) + float(pr.cc) * 60.0
		pr["contrib"] = float(pr.dps) + float(pr.burst) / 6.0 + float(pr.cc) * 25.0 + float(pr.support) * 1.2
		pr["worth"] = float(pr.contrib) / maxf(120.0, float(pr.ehp))
		pr["team"] = _team_of(eb.idx)
		pr["down"] = down
		eprof[eb.idx] = pr
	if standing.is_empty():
		plan.stance = "DISENGAGE"
		return
	# The fight plan sees the squad's target team plus anyone within 650 px.
	var local: Dictionary = eprof
	var tt: int = int(squad_intent.get("target_team", -1))
	var focus_set: Dictionary = {}
	for k in local:
		var pr2: Dictionary = local[k]
		var eb2: TeamIntel.EnemyBelief = pr2.b
		var close: bool = false
		for a3 in standing:
			if a3.pos.distance_to(eb2.pos) <= 650.0:
				close = true
				break
		if int(pr2.team) == tt or close:
			focus_set[k] = pr2
	eprof = focus_set
	var t1: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_plan_core(standing, false)
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("plan_core", t1)
	eprof = local
	plan.pressure = 0.0
	plan.nokill = 0.0
	plan.gamble = false
	if focus_set.is_empty():
		# No enemy to plan against: the "front" is the squad's own goal, not
		# the map centre the core plan falls back to.
		var g: Vector2 = _squad_goal()
		var ac: Vector2 = plan.get("ally_c", standing[0].pos)
		plan.enemy_c = g
		plan.dir = (g - ac).normalized() if g.distance_to(ac) > 1.0 else Vector2.RIGHT
		plan.front = sim.arena.resolve_circle(ac + (plan.dir as Vector2) * 10.0, 20.0)
		plan.retreat = sim.arena.resolve_circle(ac - (plan.dir as Vector2) * 200.0, 20.0)
	_apply_intent_to_plan()


func _squad_goal() -> Vector2:
	if leader != null and member_goal.has(leader.idx):
		return member_goal[leader.idx].goal
	return zone_state.get("goal", sim.arena.center())


func _apply_intent_to_plan() -> void:
	cfg["risk"] = 1.0
	var mode: String = str(squad_intent.get("mode", ""))
	match mode:
		"disengage":
			plan.stance = "DISENGAGE"
			plan.go = false
			cfg["risk"] = 1.35
		"engage", "third", "contest":
			# Contesting a knock holds the ground even at a slight disadvantage.
			var floor_adv: float = -0.35 if mode == "contest" else -0.2
			if str(plan.stance) != "ENGAGE" and float(plan.get("adv", 0.0)) > floor_adv:
				plan.stance = "ENGAGE"
				plan.go = true
			cfg["risk"] = 0.85 if mode == "contest" else 0.9
			var ft: int = int(squad_intent.get("focus", -1))
			if ft >= 0 and eprof.has(ft):
				plan.focus = ft
		"revive", "loot", "rotate", "roam", "regroup", "hold":
			if str(plan.stance) == "ENGAGE" and not bool(plan.get("fighting", false)):
				plan.stance = "POKE"
				plan.go = false


# ---------------------------------------------------------------- squad intent

func _power_of(pr: Dictionary) -> float:
	var ehp: float = maxf(1.0, float(pr.get("ehp", 1.0)))
	var dmg: float = maxf(1.0, float(pr.get("dps", 0.0)) + float(pr.get("burst", 0.0)) / 5.0 + float(pr.get("cc", 0.0)) * 25.0 + float(pr.get("support", 0.0)) * 0.6)
	return sqrt(ehp * dmg)


# An enemy's fighting power from its plan profile (or a fresh one when the
# plan has not seen it yet), with its believed health.
func _enemy_power(eb: TeamIntel.EnemyBelief) -> float:
	if eprof.has(eb.idx):
		return _power_of(eprof[eb.idx])
	var pr: Dictionary = KitModel.enemy_profile(intel, eb)
	var st: Dictionary = KitModel.stats_of_def(eb.def)
	pr["ehp"] = (eb.hp + eb.shield) * (1.0 + (float(st.armor) + float(st.mr)) * 0.5 / 100.0)
	return _power_of(pr)


func death_cost() -> float:
	var br: BattlegroundMode = sim.battleground
	var n: float = float(maxi(2, br.team_count))
	var a: float = float(maxi(1, br.alive_team_count()))
	return 0.55 + 2.0 * ((a - 1.0) * 0.5 / (n - 1.0) + 0.5 / a)


func _set_mode(next: Dictionary) -> void:
	if str(next.mode) != str(squad_intent.get("mode", "")) or int(next.get("target_team", -1)) != int(squad_intent.get("target_team", -1)):
		next["since"] = sim.time
		intent_log.append({"t": sim.time, "mode": str(next.mode), "reason": str(next.get("reason", ""))})
		if intent_log.size() > 8:
			intent_log.pop_front()
	else:
		next["since"] = float(squad_intent.get("since", sim.time))
	squad_intent = next


# Our standing power that can join a fight at p: members farther than 700 px
# count less (down to 30 % at 1500 px).
func _power_at(standing: Array[BUnit], p: Vector2) -> float:
	var total: float = 0.0
	for m in standing:
		var w: float = clampf(1.0 - (m.pos.distance_to(p) - 700.0) / 800.0, 0.3, 1.0)
		total += w * _power_of(aprof[m.idx] if aprof.has(m.idx) else _ally_profile(m))
	return total


static func _win_p(ours: float, theirs: float) -> float:
	var r: float = ours / maxf(1.0, theirs)
	return r * r / (1.0 + r * r)


# Visible enemies grouped by their team (team membership is public): units,
# standing power (an enemy closer to a third party than to us counts at
# BUSY_POWER), centre, downed members, nearest distance to a standing member
# and whether that team is trading blows with us or with a third team.
func _enemy_groups(standing: Array[BUnit]) -> Dictionary:
	var groups: Dictionary = {}
	var vis: Array = []
	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.is_hero:
			vis.append(eb)
	for eb in vis:
		var tm: int = _team_of(eb.idx)
		if not groups.has(tm):
			groups[tm] = {"team": tm, "units": [], "power": 0.0, "c": Vector2.ZERO, "down": [], "near": INF, "standing": 0,
				"hits_us": false}
		var g: Dictionary = groups[tm]
		(g.units as Array).append(eb)
		g.c = (g.c as Vector2) + eb.pos
		var mine: float = INF
		for m2 in standing:
			mine = minf(mine, m2.pos.distance_to(eb.pos))
		g.near = minf(float(g.near), mine)
		if sim.time - float(fight_with.get(eb.idx, -99.0)) < 3.0:
			g.hits_us = true
		if eb.has_status("downed"):
			(g.down as Array).append(eb)
			continue
		g.standing = int(g.standing) + 1
		var share: float = 1.0
		if sim.time - float(fight_with.get(eb.idx, -99.0)) >= 2.0:
			for ob in vis:
				var o: TeamIntel.EnemyBelief = ob
				if o == eb or _team_of(o.idx) == tm or o.has_status("downed"):
					continue
				var d_o: float = o.pos.distance_to(eb.pos)
				if d_o < 480.0 and d_o < mine - 80.0:
					share = BUSY_POWER
					break
		g.power = float(g.power) + share * _enemy_power(eb)
	for tm2 in groups:
		var g2: Dictionary = groups[tm2]
		g2.c = (g2.c as Vector2) / float((g2.units as Array).size())
		# Hidden teammates believed close by count half.
		for b2 in intel.alive_enemies():
			var hb: TeamIntel.EnemyBelief = b2
			if not hb.visible and hb.is_hero and hb.confidence > 0.3 and _team_of(hb.idx) == int(tm2) and hb.pos.distance_to(g2.c) < 600.0:
				g2.power = float(g2.power) + 0.5 * _enemy_power(hb)
	return groups


func _update_squad_intent() -> void:
	next_intent_at = sim.time + INTENT_INTERVAL
	var br: BattlegroundMode = sim.battleground
	var standing: Array[BUnit] = _standing()
	member_goal.clear()
	if standing.is_empty():
		leader = null
		_set_mode({"mode": "dead", "reason": "전원 다운·탈락", "target_team": -1})
		return
	leader = standing[0]
	var ms: float = INF
	for m in standing:
		ms = minf(ms, maxf(40.0, sim.stat(m, &"moveSpeed")))
		_mark_swept(m)
	_remember_items(standing)
	_zv = br.zone_view()
	# The member with the least slack sets the squad's zone urgency.
	var zs: Dictionary = BattlegroundSoloBrain.zone_sense(_zv, leader.pos, ms, _timetable, sim.time, ROTATE_SLACK)
	for m1 in standing:
		if m1 == leader:
			continue
		var z1: Dictionary = BattlegroundSoloBrain.zone_sense(_zv, m1.pos, ms, _timetable, sim.time, ROTATE_SLACK)
		if float(z1.urgency) > float(zs.urgency):
			zs.urgency = z1.urgency
			zs.slack = z1.slack
		zs.need_move = bool(zs.need_move) or bool(z1.need_move)
		zs.outside = bool(zs.outside) or bool(z1.outside)
	var calm: float = BattlegroundSoloBrain.calm_factor(_zv, _timetable, sim.time)
	var late: float = BattlegroundSoloBrain.late_factor(_zv, _hd)
	zs["calm"] = calm
	zs["late"] = late
	zone_state = zs
	BattlegroundSoloBrain.drift_beliefs(sim, intel, zs, INTENT_INTERVAL)
	var urgency: float = float(zs.urgency)
	var dc: float = death_cost()
	var groups: Dictionary = _enemy_groups(standing)
	var options: Array = []
	var cur: String = str(squad_intent.get("mode", ""))
	var abandon: Dictionary = {}   # enemy team -> a downed member of ours lies within its reach
	_downed_options(options, standing, groups, dc, cur, zs, abandon)
	_fight_options(options, standing, groups, dc, cur, zs, abandon)
	# The zone.
	if bool(zs.need_move):
		var rot: float = 10.0 + 125.0 * urgency * urgency + (40.0 if bool(zs.outside) else 0.0)
		if cur == "rotate":
			rot += 5.0
		options.append({"mode": "rotate", "score": rot, "target_team": -1, "reason": "자기장 %s — 여유 %s" % [str(zs.label),
			"없음" if float(zs.slack) <= 0.0 else ("%.0f초" % float(zs.slack)) if float(zs.slack) < 999.0 else "충분"]})
	# Loot near the leader.
	var loot_plan: Dictionary = _plan_loot(standing, zs, groups)
	if not loot_plan.is_empty():
		options.append({"mode": "loot", "score": float(loot_plan.score) + (6.0 if cur == "loot" else 0.0), "target_team": -1,
			"claims": loot_plan.claims, "reason": "보급 %d곳" % (loot_plan.claims as Dictionary).size()})
	# Final circles: hold brush deep inside the safe circle.
	if late > 0.0:
		hold_goal = BattlegroundSoloBrain.hold_spot(sim, intel, zs, leader.pos, hold_goal, 26.0)
		var hold_s: float = 6.0 + 22.0 * late - _outside(zs, hold_goal)
		if cur == "hold":
			hold_s += 6.0
		options.append({"mode": "hold", "score": hold_s, "target_team": -1,
			"reason": "마지막 원 — %s에서 대기" % ("수풀" if sim.arena.forest_at(hold_goal) >= 0 else "안쪽")})
	# Regroup when the squad has spread too far.
	var spread: float = 0.0
	for m4 in standing:
		spread = maxf(spread, m4.pos.distance_to(leader.pos))
	if spread > LEASH_MAX * 1.5:
		options.append({"mode": "regroup", "score": 30.0 + (spread - LEASH_MAX) * 0.03, "target_team": -1, "reason": "간격 %d → 집결" % int(spread)})
	if roam_goal == Vector2.INF or leader.pos.distance_to(roam_goal) < 160.0 or sim.time > roam_until or _outside(zs, roam_goal) > 0.0:
		roam_goal = _pick_roam_goal(zs)
		roam_until = sim.time + 14.0
	options.append({"mode": "roam", "score": 8.0 - 6.0 * late, "target_team": -1, "reason": "안전 구역 탐색"})
	# A losing fight within reach, or a downed member with enemies over it,
	# has to be answered (contest, leave, fight or regroup): looting, holding,
	# roaming and an unhurried rotation all score below the best answer.
	var pressing: float = -INF
	for o in options:
		if str(o.mode) in ["disengage", "contest"]:
			pressing = maxf(pressing, float(o.score))
	if pressing > -INF:
		for o2 in options:
			var m2: String = str(o2.mode)
			if m2 in ["loot", "roam", "hold"] or (m2 == "rotate" and urgency < 0.35 and not bool(zs.outside)):
				o2.score = minf(float(o2.score), pressing - 1.0)
	var best: Dictionary = {}
	var best_s: float = -INF
	for o3 in options:
		if float(o3.score) > best_s:
			best_s = float(o3.score)
			best = o3
	claims = best.get("claims", {}) if str(best.mode) == "loot" else {}
	_set_mode(best)
	_assign_goals(standing, zs, groups)


# Revive or contest for each downed member (B-SQUAD):
#  revive   no standing enemy in sight within SAFE_REVIVE px of it, none we
#           see hit one of us within 1.5 s, and the reviver arrives before it
#           bleeds out. The spot is brush / cover within SPOT_REACH px when a
#           threat was seen near it lately (it crawls there), else where it
#           lies. A revive outranks every fight but leaving a damaging zone.
#  contest  standing enemies within CONTEST_REACH px of it: fight them for
#           the teammate when the odds are decent. The win is worth a kill
#           plus SAVE_VALUE; the matching disengage pays for leaving it.
func _downed_options(options: Array, standing: Array[BUnit], groups: Dictionary, dc: float, cur: String, zs: Dictionary, abandon: Dictionary) -> void:
	var br: BattlegroundMode = sim.battleground
	# A standing enemy in sight hit one of us lately (damage over time and the
	# zone do not count).
	var under_fire: bool = false
	for tm0 in groups:
		for e0 in groups[tm0].units:
			var eb0: TeamIntel.EnemyBelief = e0
			if not eb0.has_status("downed") and sim.time - float(hit_by.get(eb0.idx, -99.0)) < 1.5:
				under_fire = true
	for k in revive_spots.keys():
		var du: BUnit = sim.u_at(int(k))
		if du == null or not br.is_downed(du):
			revive_spots.erase(k)
			threat_seen.erase(k)
	for m3 in members:
		if not m3.alive or not br.is_downed(m3):
			continue
		var info: Dictionary = br.downed_info(m3)
		var left: float = float(info.bleed_at) - sim.time
		var threat_teams: Array = []
		var threat_d: float = INF
		var threat_pos: Vector2 = Vector2.INF
		var finisher: int = -1
		for tm in groups:
			var g: Dictionary = groups[tm]
			for e in g.units:
				var eb: TeamIntel.EnemyBelief = e
				if eb.has_status("downed"):
					continue
				var d: float = eb.pos.distance_to(m3.pos)
				if d < CONTEST_REACH and not threat_teams.has(int(tm)):
					threat_teams.append(int(tm))
				if d < threat_d:
					threat_d = d
					threat_pos = eb.pos
					finisher = eb.idx
		if threat_pos.is_finite() and threat_d < 1100.0:
			threat_seen[m3.idx] = {"pos": threat_pos, "t": sim.time}
		var reviver: BUnit = _pick_reviver(standing, m3)
		if reviver == null:
			continue
		var r_ms: float = maxf(40.0, sim.stat(reviver, &"moveSpeed"))
		var eta: float = reviver.pos.distance_to(m3.pos) / r_ms + BattlegroundMode.REVIVE_TIME
		if threat_d > SAFE_REVIVE and not under_fire:
			if eta > left + 0.5:
				continue
			var spot: Vector2 = _revive_spot(m3, reviver, left)
			var score: float = 120.0 + 30.0 * (1.0 - left / maxf(1.0, float(info.bleed_total))) - _outside(zs, m3.pos)
			if cur == "revive":
				score += 8.0
			var where: String = "" if spot.distance_to(m3.pos) < 24.0 else (" · 수풀로" if sim.arena.forest_at(spot) >= 0 else " · 엄폐물 뒤로")
			options.append({"mode": "revive", "score": score, "target": m3.idx, "reviver": reviver.idx, "target_team": -1, "spot": spot,
				"reason": "%s 소생 — 출혈 %.0f초%s" % [m3.def.name, left, where]})
			continue
		if threat_teams.is_empty():
			continue
		var theirs: float = 0.0
		var downs: int = 0
		for tm2 in threat_teams:
			theirs += float(groups[tm2].power)
			downs += (groups[tm2].down as Array).size()
			abandon[tm2] = true
		var p: float = _win_p(_power_at(standing, m3.pos), theirs)
		var contest: float = KILL_VALUE * (p * (1.0 + 0.25 * float(downs) + SAVE_VALUE) - (1.0 - p) * dc) \
			- BattlegroundSoloBrain.edge_cost_at(_zv, _timetable, sim.time, m3.pos) - _outside(zs, m3.pos) * 0.5
		if cur == "contest" and int(squad_intent.get("target", -1)) == m3.idx:
			contest += 8.0
		# Trio: one member channels while the others hold the threat at least
		# COVER_GAP px away from the downed one.
		var covered: int = -1
		if standing.size() >= 2 and threat_d >= COVER_GAP and p >= 0.5 and eta < left - 0.5:
			covered = reviver.idx
			contest += 15.0
		var main_team: int = int(threat_teams[0])
		options.append({"mode": "contest", "score": contest, "target": m3.idx, "target_team": main_team, "focus": finisher,
			"reviver": covered, "p": p, "threat": threat_pos,
			"reason": "%s 다운 · %s 상대 승산 %d%% → 엄호%s" % [m3.def.name, br.team_label(main_team), int(p * 100.0), " · 엄호 소생" if covered >= 0 else ""]})


# The member that revives: the nearest one, with low health or being hit
# counting as extra distance; the current reviver keeps the job unless
# another is clearly closer.
func _pick_reviver(standing: Array[BUnit], down: BUnit) -> BUnit:
	var best: BUnit = null
	var best_d: float = INF
	var keep: int = int(squad_intent.get("reviver", -1)) if int(squad_intent.get("target", -1)) == down.idx else -1
	for s2 in standing:
		var d: float = s2.pos.distance_to(down.pos)
		if sim.hp_ratio(s2) < 0.3:
			d += 400.0
		if sim.time - s2.last_damage_time < 1.2:
			d += 300.0
		if s2.idx == keep:
			d *= 0.75
		if d < best_d:
			best_d = d
			best = s2
	return best


# Where a revive should happen: where the downed member lies, unless a
# standing enemy was seen near it within THREAT_MEMORY s; then the best brush
# (or the far side of a sight-blocking obstacle from that threat) within
# SPOT_REACH px it can crawl to with time to spare. Kept once chosen.
func _revive_spot(down: BUnit, reviver: BUnit, left: float) -> Vector2:
	var spot: Vector2 = down.pos
	if left < BattlegroundMode.REVIVE_TIME + 4.0:
		# No time left for a detour: revive where it lies.
		revive_spots[down.idx] = spot
		return spot
	var keep = revive_spots.get(down.idx)
	if keep is Vector2:
		return keep
	var ts: Dictionary = threat_seen.get(down.idx, {})
	if ts.is_empty() or sim.time - float(ts.t) > THREAT_MEMORY or sim.arena.forest_at(down.pos) >= 0:
		return spot
	# stat() already applies the downed crawl factor.
	var crawl: float = maxf(10.0, sim.stat(down, &"moveSpeed"))
	var r_ms: float = maxf(40.0, sim.stat(reviver, &"moveSpeed"))
	var threat: Vector2 = ts.pos
	var body: float = sim.radius(down)
	var a: Arena = sim.arena
	var best_v: float = 0.0
	var cands: Array = []
	for k in a.forest_x.size():
		var fc: Vector2 = Vector2(a.forest_x[k], a.forest_y[k])
		var edge: float = fc.distance_to(down.pos) - a.forest_r[k]
		if edge > SPOT_REACH or edge < 0.0:
			continue
		cands.append([down.pos + (fc - down.pos).normalized() * (edge + minf(a.forest_r[k] * 0.6, 40.0)), 100.0])
	for oi in a._candidates(down.pos.x - SPOT_REACH, down.pos.y - SPOT_REACH, down.pos.x + SPOT_REACH, down.pos.y + SPOT_REACH):
		if (a.obs_mask[oi] & Arena.MASK_VISION) == 0:
			continue
		var oc: Vector2 = Vector2(a.obs_x[oi] + a.obs_w[oi] * 0.5, a.obs_y[oi] + a.obs_h[oi] * 0.5) if a.obs_circle[oi] == 0 else Vector2(a.obs_x[oi], a.obs_y[oi])
		var ext: float = a.obs_r[oi] if a.obs_circle[oi] == 1 else maxf(a.obs_w[oi], a.obs_h[oi]) * 0.5
		cands.append([oc + (oc - threat).normalized() * (ext + body + 14.0), 70.0])
	for c in cands:
		var p: Vector2 = a.resolve_circle(c[0], body)
		var crawl_t: float = p.distance_to(down.pos) * 1.15 / crawl
		if p.distance_to(down.pos) > SPOT_REACH * 1.2 or maxf(crawl_t, reviver.pos.distance_to(p) / r_ms) + BattlegroundMode.REVIVE_TIME > left - 1.5:
			continue
		if p.distance_to(threat) < down.pos.distance_to(threat) - 40.0 or (float(c[1]) < 100.0 and a.line_of_sight(p, threat, 2.0)):
			continue
		var v: float = float(c[1]) - crawl_t * 8.0
		if v > best_v:
			best_v = v
			spot = p
	revive_spots[down.idx] = spot
	return spot


# Fights, one enemy team at a time.
func _fight_options(options: Array, standing: Array[BUnit], groups: Dictionary, dc: float, cur: String, zs: Dictionary, abandon: Dictionary) -> void:
	var br: BattlegroundMode = sim.battleground
	var calm: float = float(zs.calm)
	var late: float = float(zs.late)
	var bleeding: bool = false
	for m0 in members:
		if m0.alive and br.is_downed(m0):
			bleeding = true
	for tm4 in groups:
		var g4: Dictionary = groups[tm4]
		if float(g4.near) > ENGAGE_REACH:
			continue
		var r_ours: float = _power_at(standing, g4.c)
		var p: float = _win_p(r_ours, float(g4.power))
		var r: float = r_ours / maxf(1.0, float(g4.power))
		var finish: float = 0.25 * float((g4.down as Array).size())
		var deny: bool = false
		for dn in g4.down:
			if enemy_revives.has((dn as TeamIntel.EnemyBelief).idx):
				deny = true
		var score2: float = KILL_VALUE * (p * (1.0 + finish) - (1.0 - p) * dc) - maxf(0.0, float(g4.near) - 400.0) * 0.04
		var third: bool = sim.time - float(clash.get(int(tm4), -99.0)) < 2.5
		var hits_us: bool = bool(g4.hits_us)
		if third:
			score2 += 18.0
		if deny:
			score2 += 15.0
		if hits_us:
			score2 += 12.0
		if cur in ["engage", "third"] and int(squad_intent.get("target_team", -1)) == int(tm4):
			score2 += 10.0
		# Pacing: a fight nobody started waits for clearly good odds in the
		# loot phase; in the final circles other teams do the fighting.
		if not hits_us:
			score2 -= calm * CALM_ENGAGE
			if not third:
				score2 -= late * LATE_ENGAGE
		score2 -= _outside(zs, g4.c) * 0.5 + BattlegroundSoloBrain.edge_cost_at(_zv, _timetable, sim.time, g4.c)
		if int(g4.standing) == 0:
			# Only downed enemies in sight: a cheap kill, never worth more than a
			# revive or a real fight.
			score2 = minf(score2, 40.0 + 15.0 * float((g4.down as Array).size()) - maxf(0.0, float(g4.near) - 300.0) * 0.05)
		# A teammate bleeding out elsewhere: other fights wait unless they come to us.
		if bleeding and not hits_us and not abandon.has(int(tm4)):
			score2 -= 35.0
		var focus: int = -1
		var low: float = INF
		for e in g4.units:
			var eb3: TeamIntel.EnemyBelief = e
			var key: float = eb3.hp / maxf(1.0, eb3.max_hp)
			if eb3.has_status("downed"):
				# Downed enemies last: their team's standing members come first.
				key += 2.0 if int(g4.standing) > 0 else -0.5
			if enemy_revivers.has(eb3.idx):
				key -= 1.0
			if key < low:
				low = key
				focus = eb3.idx
		var why: String = "%s · 전력비 %.2f · 승산 %d%%" % [br.team_label(int(tm4)), r, int(p * 100.0)]
		if deny:
			why += " · 소생 저지"
		elif not (g4.down as Array).is_empty():
			why += " · 다운 마무리"
		options.append({"mode": "third" if third else "engage", "score": score2, "target_team": int(tm4), "focus": focus,
			"p": p, "reason": why})
		if float(g4.near) < 700.0 and p < 0.45 and int(g4.standing) > 0:
			var run: float = KILL_VALUE * (1.0 - p) * dc * 0.55
			if abandon.has(int(tm4)):
				run -= KILL_VALUE * SAVE_VALUE * 0.5
			if cur == "disengage":
				run += 6.0
			options.append({"mode": "disengage", "score": run, "target_team": int(tm4), "from": g4.c,
				"reason": "%s 상대 승산 %d%% → 이탈%s" % [br.team_label(int(tm4)), int(p * 100.0), " (다운 팀원 포기)" if abandon.has(int(tm4)) else ""]})


# Member goals for the chosen squad mode, with the leash on top.
func _assign_goals(standing: Array[BUnit], zs: Dictionary, groups: Dictionary) -> void:
	var mode: String = str(squad_intent.mode)
	var lp: Vector2 = leader.pos
	var base: Vector2 = lp
	var reward: float = 60.0
	match mode:
		"rotate":
			base = zs.goal
			reward = 70.0 + 110.0 * float(zs.urgency)
		"roam":
			base = roam_goal
			reward = 45.0
		"hold":
			base = hold_goal if hold_goal.is_finite() else zs.goal
			reward = 60.0
		"regroup":
			base = lp
			reward = 90.0
		"disengage":
			var from: Vector2 = squad_intent.get("from", lp)
			var away: Vector2 = (lp - from).normalized() if lp.distance_to(from) > 1.0 else Vector2.RIGHT
			var inward: Vector2 = ((zs.safe_center as Vector2) - lp).normalized() if lp.distance_to(zs.safe_center) > 1.0 else away
			base = sim.arena.resolve_circle(lp + (away * 0.7 + inward * 0.3).normalized() * 420.0, 20.0)
			reward = 120.0
		"engage", "third":
			var tg: Dictionary = groups.get(int(squad_intent.get("target_team", -1)), {})
			base = tg.get("c", lp)
			reward = 40.0
		"revive", "contest":
			var down0: BUnit = sim.u_at(int(squad_intent.target))
			base = down0.pos
			reward = 110.0
	for k in standing.size():
		var m: BUnit = standing[k]
		var off: Vector2 = Vector2.ZERO
		if k > 0:
			off = Vector2.from_angle(TAU * float(k) / float(standing.size()) + 0.6) * 70.0
		var g: Dictionary = {"goal": sim.arena.resolve_circle(base + off, sim.radius(m)), "label": "%s" % str(MODE_LABELS.get(mode, mode)),
			"reward": reward, "role": mode, "target": -1, "uid": -1}
		if mode == "revive":
			var target: BUnit = sim.u_at(int(squad_intent.target))
			var spot: Vector2 = squad_intent.get("spot", target.pos)
			if m.idx == int(squad_intent.reviver):
				g.goal = spot if spot.distance_to(target.pos) > 24.0 else target.pos
				g.role = "reviver"
				g.target = target.idx
				g.label = "소생: %s" % target.def.name
			else:
				# Cover: between the pair and the last threat seen near it.
				var ts: Dictionary = threat_seen.get(target.idx, {})
				var face: Vector2 = ((ts.pos as Vector2) - spot).normalized() if not ts.is_empty() and (ts.pos as Vector2).distance_to(spot) > 1.0 else (off.normalized() if off != Vector2.ZERO else Vector2.RIGHT)
				var side: float = 0.6 if k % 2 == 1 else -0.6
				g.goal = sim.arena.resolve_circle(spot + face.rotated(side) * 130.0, sim.radius(m))
				g.role = "cover"
				g.label = "소생 엄호"
				g.reward = 70.0
		elif mode == "contest":
			var target2: BUnit = sim.u_at(int(squad_intent.target))
			if m.idx == int(squad_intent.get("reviver", -1)):
				g.goal = target2.pos
				g.role = "reviver"
				g.target = target2.idx
				g.label = "엄호 소생: %s" % target2.def.name
			else:
				# Body-block: stand between the downed teammate and its finishers.
				var th: Vector2 = squad_intent.get("threat", target2.pos)
				var dd: float = th.distance_to(target2.pos)
				var guard: Vector2 = target2.pos + (th - target2.pos).normalized() * clampf(dd * 0.45, 60.0, 160.0) if dd > 1.0 else target2.pos
				g.goal = sim.arena.resolve_circle(guard + off * 0.6, sim.radius(m))
				g.role = "guard"
				g.target = int(squad_intent.get("focus", -1))
				g.label = "다운 팀원 보호"
				g.reward = 55.0
		elif mode == "loot":
			var uid: int = -1
			for cu in claims:
				if int(claims[cu]) == m.idx:
					uid = int(cu)
			if uid >= 0 and known_items.has(uid):
				g.goal = known_items[uid].pos
				g.uid = uid
				g.label = "보급: %s" % str(ItemDefs.get_def(str(known_items[uid].item)).name)
				g.reward = 95.0
			else:
				g.goal = sim.arena.resolve_circle(lp + off, sim.radius(m))
				g.label = "보급 엄호"
				g.reward = 35.0
		# Leash: never more than LEASH_MAX from the leader outside fights.
		if m != leader and not (mode in ["engage", "third", "revive", "contest"]) and m.pos.distance_to(lp) > LEASH_MAX:
			g.goal = sim.arena.resolve_circle(lp + off, sim.radius(m))
			g.label = "집결"
			g.reward = 100.0
		member_goal[m.idx] = g


# Greedy item claims: each standing member takes its best known item that
# lies within LOOT_RANGE of it and LEASH_MAX of the leader (the leader:
# within LOOT_RANGE or inside the safe circle); one member per item.
func _plan_loot(standing: Array[BUnit], zs: Dictionary, groups: Dictionary) -> Dictionary:
	if known_items.is_empty():
		return {}
	var br: BattlegroundMode = sim.battleground
	var taken: Dictionary = {}
	var total: float = 0.0
	var best_one: float = -INF
	for m in standing:
		var held: Array = br.held(m)
		var ms: float = maxf(40.0, sim.stat(m, &"moveSpeed"))
		var pick: int = -1
		var pick_s: float = -INF
		for uid in known_items:
			if taken.has(int(uid)):
				continue
			var k: Dictionary = known_items[uid]
			var ipos: Vector2 = k.pos
			var dist: float = m.pos.distance_to(ipos)
			if m == leader:
				if dist > LOOT_RANGE and ipos.distance_to(zs.safe_center) > float(zs.safe_radius):
					continue
			elif dist > LOOT_RANGE or ipos.distance_to(leader.pos) > LEASH_MAX:
				continue
			var gain: float = ItemValuation.gain_cached(m.def, str(k.item), held, DeathmatchMode.SLOTS)
			if gain <= 0.0 or (held.size() >= DeathmatchMode.SLOTS and gain < 10.0):
				continue
			var danger: float = 0.0
			for tm in groups:
				if ((groups[tm] as Dictionary).c as Vector2).distance_to(ipos) < 500.0:
					danger += 0.35
			var s: float = gain * 0.95 * (1.0 - clampf(danger, 0.0, 0.8)) - dist * 1.2 / ms * 1.9 - _outside(zs, ipos)
			if int(claims.get(int(uid), -1)) == m.idx:
				s += 8.0
			if s > pick_s:
				pick_s = s
				pick = int(uid)
		if pick >= 0 and pick_s > 0.0:
			taken[pick] = m.idx
			total += pick_s
			best_one = maxf(best_one, pick_s)
	if taken.is_empty():
		return {}
	return {"claims": taken, "score": best_one + 0.25 * (total - best_one)}


func _outside(zs: Dictionary, p: Vector2) -> float:
	if zs.is_empty() or not p.is_finite():
		return 0.0
	var over: float = p.distance_to(zs.safe_center) - float(zs.safe_radius)
	if over <= 0.0:
		return 0.0
	return (10.0 + over * 0.06) * (0.3 + 1.7 * float(zs.urgency))


# Items any standing member sees join the team memory; a known item gone from
# the field is forgotten once a member could notice (sight or earshot).
func _remember_items(watchers: Array[BUnit]) -> void:
	var br: BattlegroundMode = sim.battleground
	var present: Dictionary = {}
	for it in br.field:
		present[int(it.uid)] = true
		if known_items.has(int(it.uid)):
			continue
		var p: Vector2 = it.pos
		for u in watchers:
			if u.pos.distance_to(p) <= sim.sensor_range(u) and sim.arena.line_of_sight(u.pos, p, 2.0):
				known_items[int(it.uid)] = {"pos": p, "item": str(it.item), "rarity": ItemDefs.rarity_of(str(it.item)), "t": sim.time}
				break
	for uid in known_items.keys():
		if present.has(int(uid)):
			continue
		var kp: Vector2 = known_items[uid].pos
		for u2 in watchers:
			var d: float = u2.pos.distance_to(kp)
			if d <= HEAR_RANGE or (d <= sim.sensor_range(u2) and sim.arena.line_of_sight(u2.pos, kp, 2.0)):
				known_items.erase(uid)
				claims.erase(uid)
				break


func _mark_swept(m: BUnit) -> void:
	var c: Vector2i = Vector2i(int(floor(m.pos.x / SWEEP_CELL)), int(floor(m.pos.y / SWEEP_CELL)))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			swept[c + Vector2i(dx, dy)] = sim.time


# Unswept ground inside the safe circle; no pull toward the map centre during
# the loot phase (nearby ground first), a mild one afterwards.
func _pick_roam_goal(zs: Dictionary) -> Vector2:
	var c: Vector2 = zs.get("safe_center", sim.arena.center())
	var r: float = float(zs.get("safe_radius", 1e9))
	var mid: Vector2 = sim.arena.center()
	var half: float = 0.5 * Vector2(sim.arena.width, sim.arena.height).length()
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
			var d: float = p.distance_to(leader.pos)
			if d < 300.0:
				continue
			var age: float = clampf(sim.time - float(swept.get(Vector2i(cx, cy), -60.0)), 0.0, 60.0)
			var v: float = -absf(d - pref_d) * 0.05 + rng.randf() * 30.0 + age * 0.9 - p.distance_to(mid) / half * pull
			if v > best_v:
				best_v = v
				best = p
	return sim.arena.resolve_circle(best, 26.0)


# ---------------------------------------------------------------- decisions

func decide(u: BUnit) -> void:
	var br: BattlegroundMode = sim.battleground
	if br == null:
		super.decide(u)
		return
	if br.is_downed(u):
		var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
		_decide_downed(u)
		if BattlegroundAIProfile.lprof_on:
			BattlegroundAIProfile.lp_add("downed", t0)
		return
	if br.is_reviving(u):
		u.command = {"kind": "move", "goal": u.pos, "purpose": "소생 중", "key": "revive_hold"}
		u.next_decision_at = sim.time + 0.2
		return
	var g: Dictionary = member_goal.get(u.idx, {})
	if str(g.get("role", "")) == "reviver":
		var target: BUnit = sim.u_at(int(g.target))
		if target and br.is_downed(target):
			var spot: Vector2 = squad_intent.get("spot", target.pos) if str(squad_intent.get("mode", "")) == "revive" else target.pos
			# Revive at the chosen spot: wait there while the downed one crawls in.
			var at_spot: bool = spot.distance_to(target.pos) <= 40.0
			if br.in_revive_range(u, target) and (at_spot or not _threat_recent(target)):
				if u.action == null and sim.time - u.last_damage_time > 0.6 and _revive_clear(target) and br.start_revive(u, target):
					u.command = {"kind": "move", "goal": u.pos, "purpose": "소생 시작", "key": "revive_hold"}
					u.next_decision_at = sim.time + 0.2
					return
			elif not _enemy_close(u, 380.0):
				# Walk straight to the spot / the downed teammate (steer routes it).
				var to: Vector2 = target.pos if at_spot or u.pos.distance_to(spot) < 30.0 else spot
				u.command = {"kind": "move", "goal": to, "purpose": "소생: 이동", "key": "revive_walk"}
				u.next_decision_at = sim.time + 0.2
				return
	super.decide(u)


# No standing enemy in sight close enough to break a channel now: beyond
# SAFE_REVIVE for a plain revive, beyond COVER_GAP for a covered one.
func _revive_clear(target: BUnit) -> bool:
	var reach: float = COVER_GAP if str(squad_intent.get("mode", "")) == "contest" else SAFE_REVIVE * 0.8
	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.is_hero and not eb.has_status("downed") and eb.pos.distance_to(target.pos) < reach:
			return false
	return true


func _threat_recent(target: BUnit) -> bool:
	var ts: Dictionary = threat_seen.get(target.idx, {})
	return not ts.is_empty() and sim.time - float(ts.t) <= THREAT_MEMORY


func _standing_enemy_near(u: BUnit, enemy_team: int, reach: float) -> bool:
	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.is_hero and not eb.has_status("downed") and _team_of(eb.idx) == enemy_team and eb.pos.distance_to(u.pos) < reach:
			return true
	return false


func _enemy_close(u: BUnit, reach: float) -> bool:
	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.is_hero and not eb.has_status("downed") and eb.pos.distance_to(u.pos) < reach:
			return true
	return false


# A downed member holds still while a teammate channels its revive (crawling
# would break the 60 px range). With a revive planned it crawls to the spot
# (or toward the reviver); otherwise it drags itself away: toward its
# standing teammates, away from standing enemies within 650 px, inward when
# it lies outside the zone.
func _decide_downed(u: BUnit) -> void:
	u.next_decision_at = sim.time + 0.3
	var br: BattlegroundMode = sim.battleground
	var info0: Dictionary = br.downed_info(u)
	if int(info0.get("reviver_idx", -1)) >= 0:
		u.command = {"kind": "move", "goal": u.pos, "purpose": "다운 — 소생 받는 중", "key": "downed_hold"}
		return
	var outside: bool = BattlegroundSoloBrain.outside_zone_now(sim, u)
	var mode: String = str(squad_intent.get("mode", ""))
	if mode == "revive" and int(squad_intent.get("target", -1)) == u.idx and not outside:
		var spot: Vector2 = squad_intent.get("spot", u.pos)
		if spot.distance_to(u.pos) > 16.0:
			u.command = {"kind": "move", "goal": spot, "purpose": "다운 — 소생 자리로 이동", "key": "downed_crawl"}
			return
		var rv: BUnit = sim.u_at(int(squad_intent.get("reviver", -1)))
		if rv != null and rv.alive and not br.is_downed(rv) and not _threat_recent(u):
			var to: Vector2 = rv.pos if rv.pos.distance_to(u.pos) > 40.0 else u.pos
			u.command = {"kind": "move", "goal": sim.arena.resolve_circle(to, sim.radius(u)), "purpose": "다운 — 소생하러 오는 팀원에게", "key": "downed_crawl"}
			return
		u.command = {"kind": "move", "goal": u.pos, "purpose": "다운 — 소생 대기", "key": "downed_hold"}
		return
	var dir: Vector2 = Vector2.ZERO
	var sc: Vector2 = Vector2.ZERO
	var n: int = 0
	for m in _standing():
		sc += m.pos
		n += 1
	if n > 0:
		sc /= float(n)
		if sc.distance_to(u.pos) > 60.0:
			dir += (sc - u.pos).normalized()
	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if not eb.is_hero or eb.has_status("downed"):
			continue
		var d: float = eb.pos.distance_to(u.pos)
		if d < 650.0 and d > 1.0:
			dir += (u.pos - eb.pos).normalized() * 1.6 * (1.0 - d / 650.0)
	if outside:
		dir += ((zone_state.get("safe_center", sim.arena.center()) as Vector2) - u.pos).normalized() * 2.5
	if dir.length() < 0.05:
		u.command = {"kind": "move", "goal": u.pos, "purpose": "다운 — 대기", "key": "downed_hold"}
		return
	var goal: Vector2 = sim.arena.resolve_circle(u.pos + dir.normalized() * 120.0, sim.radius(u))
	u.command = {"kind": "move", "goal": goal, "purpose": "다운 — 팀 쪽으로 기어서 이동", "key": "downed_crawl"}


func _mode_move_points(u: BUnit, _ctx: Dictionary, pts: Array) -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_squad_move_points(u, pts)
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("move_points", t0)


func _squad_move_points(u: BUnit, pts: Array) -> void:
	var g: Dictionary = member_goal.get(u.idx, {})
	if g.is_empty():
		return
	var goal: Vector2 = g.goal
	if not goal.is_finite():
		return
	var reward: float = float(g.reward)
	var mode: String = str(squad_intent.get("mode", ""))
	if mode in ["engage", "third"]:
		var near: float = INF
		for b in intel.visible_enemies():
			near = minf(near, (b as TeamIntel.EnemyBelief).pos.distance_to(u.pos))
		# Close in only; in reach, the tactician's own positions decide.
		if near < float(_ctx_range(u)) + 140.0:
			return
	elif str(g.role) == "guard":
		# In reach the guard spot still competes with the fight positions.
		var near2: float = INF
		for b2 in intel.visible_enemies():
			near2 = minf(near2, (b2 as TeamIntel.EnemyBelief).pos.distance_to(u.pos))
		if near2 < float(_ctx_range(u)) + 140.0:
			reward = 30.0
	elif sim.time - u.last_damage_time < 2.5 and mode in ["loot", "roam", "hold"]:
		reward *= 0.35
	pts.append([goal, str(g.label), reward])
	if u.pos.distance_to(goal) > 200.0:
		pts.append([u.pos + (goal - u.pos).normalized() * 180.0, str(g.label), reward * 0.7])


func _ctx_range(u: BUnit) -> float:
	return maxf(sim.stat(u, &"attackRange"), u.def.preferred_range)


func _mode_adjust(u: BUnit, _ctx: Dictionary, cands: Array) -> void:
	var t0: int = Time.get_ticks_usec() if BattlegroundAIProfile.lprof_on else 0
	_squad_adjust(u, cands)
	if BattlegroundAIProfile.lprof_on:
		BattlegroundAIProfile.lp_add("mode_adjust", t0)


func _squad_adjust(u: BUnit, cands: Array) -> void:
	var mode: String = str(squad_intent.get("mode", ""))
	var g: Dictionary = member_goal.get(u.idx, {})
	var goal: Vector2 = g.get("goal", Vector2.INF)
	var has_goal: bool = goal.is_finite()
	var dist: float = u.pos.distance_to(goal) if has_goal else 0.0
	var tt: int = int(squad_intent.get("target_team", -1))
	var focus: int = int(squad_intent.get("focus", -1))
	var fighting: bool = sim.time - u.last_damage_time < 2.5
	for item in cands:
		var c: Dictionary = item
		var cmd: Dictionary = c.cmd
		var kind: String = str(cmd.get("kind", ""))
		if kind == "move":
			if has_goal and (mode in ["rotate", "regroup", "disengage", "revive"] or not fighting):
				var endpoint: Vector2 = cmd.get("goal", u.pos)
				Doctrine._note(c, clampf((dist - endpoint.distance_to(goal)) * 0.18, -80.0, 100.0), "%s 목표 접근" % str(MODE_LABELS.get(mode, mode)))
			if mode != "roam" and str(c.get("label", "")) == "정찰":
				Doctrine._note(c, -60.0, "정찰보다 분대 목표 우선")
			continue
		var ti: int = int(cmd.get("target", -1))
		var foe: TeamIntel.EnemyBelief = intel.enemies.get(ti)
		if foe == null:
			continue
		var down: bool = foe.visible and foe.has_status("downed")
		var threatening: bool = u.pos.distance_to(foe.pos) <= float(eprof.get(ti, {}).get("reach", 160.0)) + 40.0
		var kill: bool = float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0
		if down:
			# Standing enemies first: a downed one dies with its team anyway, and
			# finishing it while its teammates (or anyone else standing close)
			# shoot back wastes the fight.
			if kind == "ability" and not kill:
				Doctrine._note(c, -45.0, "다운된 적에 기술 낭비 금지")
			elif _standing_enemy_near(u, _team_of(ti), 700.0) or _enemy_close(u, 450.0):
				Doctrine._note(c, -35.0, "서 있는 적 우선")
			else:
				Doctrine._note(c, 25.0, "다운된 적 마무리")
		if enemy_revivers.has(ti):
			Doctrine._note(c, 30.0, "소생 저지")
		match mode:
			"engage", "third":
				if _team_of(ti) == tt:
					Doctrine._note(c, 12.0, "목표 팀 집중")
				elif not threatening and not kill:
					Doctrine._note(c, -30.0, "목표 팀 외 교전 절제")
			"contest":
				if ti == focus and not down:
					Doctrine._note(c, 20.0, "다운 팀원을 노리는 적 견제")
				elif _team_of(ti) == tt:
					Doctrine._note(c, 10.0, "목표 팀 집중")
				elif not threatening and not kill:
					Doctrine._note(c, -30.0, "목표 팀 외 교전 절제")
			"disengage":
				if not kill:
					Doctrine._note(c, -90.0 if not threatening else -35.0, "이탈 중 교전 회피")
			_:
				if not kill and not threatening:
					Doctrine._note(c, -70.0, "%s 우선 · 불필요한 교전 회피" % str(MODE_LABELS.get(mode, mode)))
	BattlegroundSoloBrain.zone_move_adjust(sim, u, cands, zone_state)


func item_choice(u: BUnit, item_id: String) -> Dictionary:
	var held: Array = sim.battleground.held(u) if sim.battleground else []
	return ItemValuation.decide(u.def, item_id, held, DeathmatchMode.SLOTS)


func _lod_travel_goal(u: BUnit) -> Vector2:
	if not (str(squad_intent.get("mode", "")) in ["loot", "rotate", "roam", "regroup", "hold"]):
		return Vector2.INF
	var g: Dictionary = member_goal.get(u.idx, {})
	return g.get("goal", Vector2.INF)


func _lod_travel_label(u: BUnit) -> String:
	return str(member_goal.get(u.idx, {}).get("label", "이동"))


func lod_urgent(u: BUnit) -> bool:
	if super.lod_urgent(u):
		return true
	return BattlegroundSoloBrain.outside_zone_now(sim, u)


func explain(u: BUnit) -> Dictionary:
	var out: Dictionary = super.explain(u)
	var g: Dictionary = member_goal.get(u.idx, {})
	out["battleground"] = {"mode": str(squad_intent.get("mode", "")), "mode_label": str(MODE_LABELS.get(str(squad_intent.get("mode", "")), "")),
		"reason": str(squad_intent.get("reason", "")), "since": float(squad_intent.get("since", 0.0)), "log": intent_log.duplicate(true),
		"role": str(g.get("role", "")), "goal_label": str(g.get("label", "")), "zone": zone_state.duplicate(),
		"known_items": known_items.size(), "leader": leader.idx if leader else -1}
	return out
