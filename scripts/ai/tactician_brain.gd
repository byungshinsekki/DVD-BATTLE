class_name TacticianBrain
extends TeamController






var intel: TeamIntel
var rng: = RandomNumberGenerator.new()
var plan: Dictionary = {"t": -9.0, "stance": "POKE", "adv": 0.0, "focus": -1}
var eprof: Dictionary = {}
var aprof: Dictionary = {}
var mem: Dictionary = {}
var reserved: Dictionary = {}
var decisions_made: int = 0
var allies_cache: Array[BUnit] = []
var _danger_cache: Dictionary = {}
var _danger_cache_t: int = -1
var commitments: Dictionary = {}
var fountain_reservations: Dictionary = {} # public fountain id -> our own move order
var last_known_death: float = 0.0
var control_plan: ControlStrategy
# Squad plans (one fight plan per group of nearby allies) are only built with
# cfg.sq = 1 (debug kind "tactician{sq=1}"); shipped kinds plan team-wide.
var squad_plans: Dictionary = {}
var squad_of: Dictionary = {}


var cfg: Dictionary = {"share": 1.0, "worth": 1.0, "ew": 1.0, "pot": 1.0, "cover": 1.0, "front": 0.0,
	"unseen": 0.0, "disto": 1.0, "hitw": 1.0, "risk": 1.0, "dint": 1.0, 

	"doct": 1.0, "local": 1.0, "gate": 1.0, "punish": 1.0, "chain": 1.0, "peel2": 1.0, "comp": 1.0, "tmult": 1.0, 
	"coh": 1.0, "appr": 1.0, "hunt2": 1.0, "lead": 1.0, "surv": 1.0, "tl": 1.0, 
	"hyst": 1.0, "nk": 1.0, "fin": 1.0, "march": 1.0, 

	"haz": 1.0, 

	"v15": 1.0, "cmd15": 1.0, "sq": 0.0, "rt15": 1.0, "tp15": 1.0, "disc15": 1.0,
	# V1.5.3 gimmick AI lab switches (tactician{key=0} replays the Wave-I rule):
	# gfr front along the walking route, glk deliberate portal / pad links,
	# gsw trigger soft walls, ggl gimmick-safe move goals (ring, gates, links),
	# gmd mud cost, gbr brush ambush / caution, grg leave-the-ring points,
	# ggt leave a closing gate frame, ggw wait for a gate that opens soon.
	"gfr": 1.0, "glk": 1.0, "gsw": 1.0, "ggl": 1.0, "gmd": 1.0, "gbr": 1.0, "grg": 1.0, "ggt": 1.0, "ggw": 1.0}


func _init(s: BattleSim, t: int) -> void :
	super (s, t)
	label = "전술가 AI"
	intel = TeamIntel.new(s, t)
	if s.is_control_mode():
		control_plan = ConquestCommander.new(s, t, self)
	rng.seed = s.seed_value * 17 + t * 3 + 5


func dispose() -> void :
	if intel:
		intel.dispose()
	if control_plan:
		control_plan.dispose()
	sim = null


func on_start(_s: BattleSim) -> void :
	if control_plan is ConquestCommander and (float(cfg.get("v15", 1.0)) < 0.5 or float(cfg.get("cmd15", 1.0)) < 0.5):
		# The 1.4 comparison brain keeps the original objective planner.
		control_plan.dispose()
		control_plan = ControlStrategy.new(sim, team)
	intel.observe()
	intel.observe_fast()
	_analyze_comp()
	_plan()


func pre_tick(s: BattleSim) -> void :
	# Scale battles: the pass reads the simulator's pre-tick snapshot (B-PERF2).
	s.ai_pre_begin(team)
	intel.ingest(s.ai_events)
	var codes: PackedByteArray = s.ai_event_codes(s.ai_events)
	for ei in s.ai_events.size():
		# Only respawns, deaths and executions matter here (B-PERF2 index).
		var code: int = codes[ei]
		if code != 1 and code != 9 and code != 10:
			continue
		var event = s.ai_events[ei]
		if str(event.type) == "HERO_RESPAWNED":
			commitments.erase(int(event.g))
			mem.erase(int(event.g))
		if str(event.type) in ["DEATH", "EXECUTED"]:
			var victim: BUnit = s.u_at(int(event.g))
			if (event.gv as Array)[team] or (victim and victim.team == team):
				last_known_death = float(event.t)
	if s.scale_lod:
		_lod_pre_tick(s)
		s.ai_pre_end(team)
		return
	if s.tick % 3 == 0:
		intel.observe()
	intel.observe_fast()
	if s.time - float(plan.t) >= 0.25:
		_plan()






func _ally_profile(u: BUnit) -> Dictionary:
	var st: = KitModel.stats_of_unit(sim, u)
	var dps: = KitModel.basic_dps(st, u.def) * 100.0 / 130.0
	var burst: = 0.0
	var cc: = 0.0
	var reach: = float(st.range) + 30.0
	for i in u.def.abilities.size():
		var a: Defs.AbilityDef = u.def.abilities[i]
		if not a.hostile:
			continue
		var ready: = u.cooldowns[i] <= sim.time + 1.5 and not u.sealed.has(i)
		if not ready:
			continue
		var ev: = KitModel.evaluate(a.effects, st, {"max_hp": 1000.0, "hp": 800.0})
		burst += KitModel.mitigate(ev, 35.0, 30.0)
		cc += KitModel.cc_total(ev)
		reach = maxf(reach, a.range + 20.0)
	var ehp: = (u.hp + sim.shield_amount(u)) * (1.0 + (float(st.armor) + float(st.mr)) * 0.5 / 100.0)
	var backline: = u.def.preferred_range > 120.0 or (u.def.role == "SUPPORT" and u.def.preferred_range > 100.0)
	var support: = KitModel.support_rate(u.def)
	var contrib: = dps + burst / 6.0 + cc * 25.0 + support * 1.2
	return {"u": u, "st": st, "dps": dps, "burst": burst, "cc": cc, "reach": reach, "ehp": ehp, "backline": backline, 
		"support": support, "contrib": contrib, "worth": contrib / maxf(120.0, ehp), 
		"tank": u.def.role == "FRONTLINE" or sim.max_hp(u) >= 1400.0}


func _plan() -> void :
	plan.t = sim.time
	aprof.clear()
	var allies: Array[BUnit] = []
	for a0 in sim.allies_of(team):
		if a0.team == team:
			allies.append(a0)
	for a in allies:
		aprof[a.idx] = _ally_profile(a)
	eprof.clear()
	# D12: with only two teams a hidden enemy has nobody else to spend its
	# cooldowns on; a known-ready ability keeps at least this readiness.
	var hidden_floor: float = 0.0 if sim.is_deathmatch() else float(cfg.get("rpf", 0.6))
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.controlled_by_us:
			continue
		var pr: = KitModel.enemy_profile(intel, eb, hidden_floor)
		var w: = 1.0 if eb.visible else (clampf(eb.confidence, 0.2, 0.7) * 0.6 if cfg.unseen > 0.5 else clampf(eb.confidence + 0.35, 0.4, 1.0))
		pr["w"] = w
		pr["b"] = eb
		var st: Dictionary = KitModel._enemy_base(eb.def).st
		pr["ehp"] = (eb.hp + eb.shield) * (1.0 + (float(st.armor) + float(st.mr)) * 0.5 / 100.0)
		pr["threat"] = float(pr.dps) * 6.0 + float(pr.burst) + float(pr.cc) * 60.0
		pr["contrib"] = float(pr.dps) + float(pr.burst) / 6.0 + float(pr.cc) * 25.0 + float(pr.support) * 1.2
		pr["worth"] = float(pr.contrib) / maxf(120.0, float(pr.ehp))
		eprof[eb.idx] = pr
	_update_brush_threats()
	if _squad_mode():
		_plan_squads(allies)
		return
	_plan_core(allies, true)


# The fight-level plan for one group of allies against the enemies in eprof.
# Elimination (and the 1.4 comparison brain) runs it once for the whole team.
func _plan_core(allies: Array[BUnit], with_objectives: bool) -> void :
	var ac: = Vector2.ZERO
	for a in allies:
		ac += a.pos
	ac = ac / maxf(1, allies.size()) if not allies.is_empty() else sim.arena.center()
	var ec: = Vector2.ZERO
	var ecw: = 0.0
	var their_dps: = 0.0
	var their_ehp: = 0.0
	var n_their: = 0.0
	var any_visible: = false
	for k0 in eprof:
		var pr: Dictionary = eprof[k0]
		var eb: TeamIntel.EnemyBelief = pr.b
		var cw: = 1.0 if eb.visible else clampf(eb.confidence + 0.35, 0.4, 1.0)
		ec += eb.pos * cw
		ecw += cw
		their_dps += (float(pr.dps) + float(pr.burst) / 5.0) * cw
		their_ehp += float(pr.ehp)
		n_their += 1.0
		if eb.visible:
			any_visible = true
	ec = ec / ecw if ecw > 0.0 else sim.arena.center()
	var our_dps: = 0.0
	var our_ehp: = 0.0
	for a_own in allies:
		var k: int = a_own.idx
		our_dps += float(aprof[k].dps) + float(aprof[k].burst) / 5.0
		our_ehp += float(aprof[k].ehp)

	var ew_sum: = 0.0
	for k in eprof:
		ew_sum += float(eprof[k].worth)
	plan.ew_mean = ew_sum / maxf(1.0, float(eprof.size())) if not eprof.is_empty() else 0.08
	allies_cache = allies

	var our_sum: = 0.0
	var our_max: = 0.0
	for a in allies:
		our_sum += a.hp + sim.shield_amount(a)
		our_max += sim.max_hp(a)
	var their_sum: = 0.0
	for k in eprof:
		var ebk: TeamIntel.EnemyBelief = eprof[k].b
		their_sum += ebk.hp + ebk.shield
	var lead: = (our_sum - their_sum) / maxf(1.0, our_max)
	plan.lead = lead

	var last_fight: = 0.0
	for a in allies:
		last_fight = maxf(last_fight, a.last_combat_time)
	plan.stale = clampf((sim.time - last_fight - 10.0) / 15.0, 0.0, 1.0)

	var last_kill: = last_known_death
	plan.nokill = clampf((sim.time - last_kill - 35.0) / 40.0, 0.0, 1.0) if cfg.nk > 0.5 else 0.0
	plan.pressure = clampf( - lead * 2.5, 0.0, 1.0) * clampf(sim.time / 70.0, 0.25, 1.0)
	var adv: = 0.0
	if n_their > 0.0 and not allies.is_empty():
		adv = log(maxf(1.0, our_ehp * our_dps) / maxf(1.0, their_ehp * their_dps)) * 0.5
		adv += 0.12 * (allies.size() - n_their)
	plan.adv_global = adv

	allies_cache = allies
	plan.ally_c = ac
	_local_fight(allies)
	if cfg.local > 0.5 and bool(plan.get("contact", false)):

		var la: = float(plan.local_adv)
		adv = lerpf(adv, la, 0.65 if la > adv else 0.25)
	var stance: = "POKE"
	var why: = "우세 %+.2f ≤ 문턱 %+.2f → 견제"

	var eng_th: = 0.14 + float(plan.get("k_engage", 0.0))
	if cfg.tl > 0.5:
		eng_th -= 0.45 * float(plan.pressure)
		if lead > 0.03:
			eng_th += 0.08 * float(plan.stale)
		else:

			eng_th -= 0.25 * float(plan.stale)
			eng_th -= 0.22 * float(plan.nokill)
	plan.eng_th = eng_th
	var prev_raw: = str(plan.get("raw_stance", ""))
	if adv > eng_th:
		stance = "ENGAGE"
		why = "우세 %+.2f > 문턱 %+.2f → 진입"
	elif cfg.hyst > 0.5 and prev_raw == "ENGAGE" and adv > eng_th - 0.18 and adv >= -0.28:

		stance = "ENGAGE"
		why = "진입 유지 (우세 %+.2f, 문턱 %+.2f − 0.18 이력)"
	elif adv < -0.28:
		stance = "DISENGAGE"
		why = "열세 %+.2f (문턱 %+.2f) → 후퇴·재정비"
	why = why % [adv, eng_th]

	# Time-limit rules follow what actually decides the mode at the limit:
	# elimination compares health sums, control compares the public score,
	# deathmatch ranks by kills (no team clock rule at all, audit DM-5).
	var clock: String = "none" if sim.is_deathmatch() else ("score" if sim.is_control_mode() and sim.domination else "health")
	var score_lead: float = 0.0
	if clock == "score":
		score_lead = float(sim.domination.scores[team]) - float(sim.domination.scores[1 - team])
	if stance == "DISENGAGE":
		# D3: a fruitless 7 s retreat turns into a 4 s poke window kept in its
		# own field (the old code overwrote it on the very next plan).
		if cfg.disto > 0.5 and sim.time < float(plan.get("poke_until", -1.0)):
			stance = "POKE"
			why = "후퇴해도 전력비가 나아지지 않음 → 견제 유지"
		elif str(plan.get("stance", "")) != "DISENGAGE":
			plan.dis_since = sim.time
			plan.dis_adv = adv
		elif cfg.disto > 0.5 and sim.time - float(plan.get("dis_since", sim.time)) > 7.0 and adv <= float(plan.get("dis_adv", adv)) + 0.08:
			stance = "POKE"
			why = "후퇴해도 전력비가 나아지지 않음 → 견제"
			plan.poke_until = sim.time + 4.0

		if cfg.disto > 0.5 and sim.max_time - sim.time < 45.0:
			if clock == "health" and lead < -0.05:
				stance = "ENGAGE"
				why = "체력 합 열세 + 남은 시간 45초 미만 → 진입"
			elif clock == "score" and score_lead < -1.0:
				stance = "ENGAGE"
				why = "점수 열세 + 남은 시간 45초 미만 → 진입"

	if clock != "none" and sim.time > sim.max_time - 25.0 and n_their > 0.0:
		if clock == "score":
			stance = "POKE" if score_lead > 1.0 else "ENGAGE"
			why = "시간 판정 임박: 점수 우세 → 안전 견제" if stance == "POKE" else "시간 판정 임박: 점수 열세 → 결사 진입"
		else:
			var our_hp: = 0.0
			for a in allies:
				our_hp += a.hp
			var their_hp: = 0.0
			for k in eprof:
				their_hp += (eprof[k].b as TeamIntel.EnemyBelief).hp
			stance = "POKE" if our_hp > their_hp + 60.0 else "ENGAGE"
			why = "시간 판정 임박: 체력 합 우세 → 안전 견제" if stance == "POKE" else "시간 판정 임박: 체력 합 열세 → 결사 진입"

		if cfg.fin > 0.5 and stance == "POKE" and adv > eng_th + 0.35:
			stance = "ENGAGE"
			why = "시간 판정 임박이지만 교전 우세 압도 → 마무리"
	plan.raw_stance = stance
	if not any_visible and sim.time - float(plan.get("last_visible", 0.0)) > 1.6:
		if stance != "DISENGAGE":
			why = "보이는 적 없음 → 정찰 (본래 판단: %s)" % why
		stance = "SCOUT" if stance != "DISENGAGE" else stance
	plan.why = why
	if any_visible:
		plan.last_visible = sim.time
	plan.stance = stance
	plan.adv = adv
	plan.ally_c = ac
	plan.enemy_c = ec
	var to_enemy: = (ec - ac).normalized() if ec.distance_squared_to(ac) > 1.0 else (Vector2.RIGHT if team == 0 else Vector2.LEFT)
	plan.dir = to_enemy
	var gap: = ac.distance_to(ec)
	var adv_step: = 10.0
	match stance:
		"ENGAGE":
			adv_step = 90.0
		"SCOUT":
			adv_step = 90.0 if cfg.front > 0.5 else 10.0
		"POKE":
			adv_step = clampf(gap - 330.0, 0.0, 70.0) if cfg.front > 0.5 else 10.0
		"DISENGAGE":
			adv_step = -60.0
	plan.front = _front_point(ac, ec, to_enemy, adv_step) if float(cfg.get("gfr", 1.0)) > 0.5 else sim.arena.resolve_circle(ac + to_enemy * adv_step, 20.0)
	plan.adv_step = adv_step
	plan.retreat = sim.arena.resolve_circle(ac - to_enemy * 200.0, 20.0)
	_assign_roles(allies)
	_enemy_geometry()
	if cfg.hunt2 > 0.5:
		_predict_enemy_focus(allies)
	_assign_peel(allies)
	_find_punish(allies)
	_choose_focus(allies)
	_engage_signal(allies)
	_cc_claims(allies)
	_compute_reserved()
	_coordination_plan(allies)
	if control_plan and with_objectives:
		control_plan.update(intel.visible_enemies())
		plan.control = control_plan.summary
		var objective_urgency: float = float(control_plan.summary.get("urgency", 0.0))
		plan.risk_budget = clampf(0.36 + objective_urgency * 0.36, 0.2, 0.78)
		plan.gamble = objective_urgency > 0.6
	_label_operation()


# Mode hooks for subclasses (deathmatch strategy). No effect here.
func _mode_move_points(_u: BUnit, _ctx: Dictionary, _pts: Array) -> void:
	pass


func _mode_adjust(_u: BUnit, _ctx: Dictionary, _cands: Array) -> void:
	pass


func _squad_mode() -> bool:
	return control_plan != null and float(cfg.get("v15", 1.0)) > 0.5 and float(cfg.get("sq", 1.0)) > 0.5


# V1.5 conquest: allies are grouped by distance, and each group plans its own
# fight against the enemies that can reach it. A hero holding a far objective
# no longer retreats because of a fight on the other side of the map.
func _plan_squads(allies: Array[BUnit]) -> void:
	var team_plan: Dictionary = plan
	var eprof_all: Dictionary = eprof
	allies_cache = allies
	var global_stance: Dictionary = {}
	if float(cfg.get("sqst", 1.0)) > 0.5:
		# Team-wide stance first; squads inherit it and only localise geometry.
		_plan_core(allies, true)
		for sk in ["stance", "raw_stance", "adv", "go", "go_since", "engage_since", "eng_th", "why", "pressure", "lead", "stale", "nokill"]:
			if plan.has(sk):
				global_stance[sk] = plan[sk]
	else:
		control_plan.update(intel.visible_enemies())
	var urgency: float = float(control_plan.summary.get("urgency", 0.0))
	var groups: Array = _proximity_groups(allies, 460.0)
	var next_plans: Dictionary = {}
	squad_of.clear()
	for g in groups:
		var members: Array[BUnit] = []
		var key: int = 1 << 30
		for m in g:
			members.append(m)
			key = mini(key, (m as BUnit).idx)
		var sp: Dictionary = squad_plans.get(key, {})
		if sp.is_empty():
			sp = {"t": -9.0, "stance": "POKE", "adv": 0.0, "focus": -1}
		eprof = _local_enemies(eprof_all, members, 820.0)
		plan = sp
		plan.t = sim.time
		_plan_core(members, false)
		if not global_stance.is_empty():
			var local_stance: String = str(plan.stance)
			for gk in global_stance:
				plan[gk] = global_stance[gk]
			# Geometry stays local: front/retreat follow this group's own frame.
			var step: float = 90.0 if str(plan.stance) in ["ENGAGE", "SCOUT"] else (-60.0 if str(plan.stance) == "DISENGAGE" else 10.0)
			plan.front = _front_point(plan.ally_c, plan.enemy_c, plan.dir, step) if float(cfg.get("gfr", 1.0)) > 0.5 else sim.arena.resolve_circle((plan.ally_c as Vector2) + (plan.dir as Vector2) * step, 20.0)
			plan.adv_step = step
			plan.local_stance = local_stance
		plan.control = control_plan.summary
		plan.risk_budget = clampf(float(plan.get("risk_budget", 0.4)) * 0.5 + (0.36 + urgency * 0.36) * 0.5, 0.2, 0.78)
		plan.gamble = urgency > 0.6 or bool(plan.get("gamble", false))
		plan.squad = key
		next_plans[key] = sp
		for m in members:
			squad_of[m.idx] = key
	squad_plans = next_plans
	eprof = eprof_all
	allies_cache = allies
	plan = team_plan
	plan.t = sim.time
	plan.control = control_plan.summary
	var biggest: int = -1
	var size: int = 0
	for key2 in squad_plans:
		var n: int = 0
		for idx in squad_of:
			if int(squad_of[idx]) == int(key2):
				n += 1
		if n > size:
			size = n
			biggest = int(key2)
	if biggest >= 0:
		for k in ["stance", "adv", "why", "op", "focus"]:
			if squad_plans[biggest].has(k):
				plan[k] = squad_plans[biggest][k]


func _squad_plan_for(u: BUnit) -> Dictionary:
	if squad_of.has(u.idx):
		return squad_plans.get(int(squad_of[u.idx]), plan)
	# A hero that respawned since the last plan fights alone until the next one.
	var saved_e: Dictionary = eprof
	var saved_a: Array[BUnit] = allies_cache
	var sp: Dictionary = {"t": sim.time, "stance": "POKE", "adv": 0.0, "focus": -1}
	if not aprof.has(u.idx):
		aprof[u.idx] = _ally_profile(u)
	var solo: Array[BUnit] = [u]
	eprof = _local_enemies(saved_e, solo, 820.0)
	var saved_p: Dictionary = plan
	plan = sp
	_plan_core(solo, false)
	plan.control = control_plan.summary
	plan = saved_p
	eprof = saved_e
	allies_cache = saved_a
	var key: int = -1000 - u.idx
	squad_plans[key] = sp
	squad_of[u.idx] = key
	return sp


func _local_enemies(all: Dictionary, members: Array[BUnit], reach: float) -> Dictionary:
	var local: Dictionary = {}
	for k in all:
		var eb: TeamIntel.EnemyBelief = all[k].b
		for m in members:
			if m.pos.distance_to(eb.pos) <= reach + float(all[k].get("reach", 0.0)) * 0.5:
				local[k] = all[k]
				break
	return local


func _proximity_groups(units: Array[BUnit], link: float) -> Array:
	var groups: Array = []
	var seen: Dictionary = {}
	for u in units:
		if seen.has(u.idx):
			continue
		var group: Array = [u]
		seen[u.idx] = true
		var k: int = 0
		while k < group.size():
			var a: BUnit = group[k]
			for v in units:
				if not seen.has(v.idx) and a.pos.distance_to(v.pos) <= link:
					seen[v.idx] = true
					group.append(v)
			k += 1
		groups.append(group)
	return groups


func _choose_focus(allies: Array[BUnit]) -> void :
	var best: = -1
	var best_v: = - INF
	var prev: = int(plan.get("focus", -1))
	for k in eprof:
		var pr: Dictionary = eprof[k]
		var eb: TeamIntel.EnemyBelief = pr.b
		if not eb.visible and (eb.confidence < 0.5 or sim.time - eb.last_seen_t > 1.5):
			continue
		var reach_dps: = 0.0
		var burst_on: = 0.0
		for a in allies:
			var ap: Dictionary = aprof[a.idx]
			var d: = a.pos.distance_to(eb.pos)
			var f: = 1.0 if d <= float(ap.reach) + 60.0 else maxf(0.0, 1.0 - (d - float(ap.reach) - 60.0) / 320.0)
			reach_dps += float(ap.dps) * f
			burst_on += float(ap.burst) * f
		var ttk: = float(pr.ehp) / maxf(20.0, reach_dps + burst_on / 3.0)
		var v: = (float(pr.threat) + 250.0 + (130.0 if eb.def.role == "SUPPORT" else 0.0)) / (ttk + 0.6)
		if eb.hard_cc_remaining() > 0.2:
			v *= 1.3
		var iso: = float((plan.get("iso", {}) as Dictionary).get(int(k), INF))
		if iso > 280.0:
			v *= float(plan.get("k_iso", 1.2))
		if eb.def.preferred_range > 150.0:
			v *= 1.08
		if int(k) == prev:
			v *= 1.25

		if cfg.punish > 0.5:
			if reach_dps * 2.5 + burst_on * 0.8 >= float(pr.ehp):
				v *= 1.45
			if (plan.get("peel_threats", {}) as Dictionary).has(int(k)):
				v *= 1.0 + 0.3 * float(plan.get("k_peel", 1.0))
			if int(plan.get("punish", -1)) == int(k):
				v *= 1.6
		v *= 0.6 + 0.4 * (1.0 if eb.visible else eb.confidence)
		if v > best_v:
			best_v = v
			best = int(k)
	plan.focus = best


func _assign_peel(allies: Array[BUnit]) -> void :
	var peel: Dictionary = {}
	var hunted_idx: = int(plan.get("enemy_focus", -1)) if cfg.hunt2 > 0.5 else -1
	for a in allies:
		var ap: Dictionary = aprof[a.idx]
		if not ap.backline and a.idx != hunted_idx:
			continue
		var worst: = -1
		var wd: = INF
		for k in eprof:
			var eb: TeamIntel.EnemyBelief = eprof[k].b
			if not eb.visible or eb.def.preferred_range > 120.0:
				continue
			var d: = eb.pos.distance_to(a.pos)
			if d < 230.0 and d < wd:
				wd = d
				worst = int(k)
		if worst >= 0:
			peel[a.idx] = worst
	plan.peel = peel
	var threats: Dictionary = {}
	for victim in peel:
		threats[int(peel[victim])] = int(victim)
	plan.peel_threats = threats
	var protector: Dictionary = {}
	for victim in peel:
		var best: BUnit = null
		var bd: = INF
		for a in allies:
			if a.idx == int(victim) or (aprof[a.idx].backline and a.def.role != "SUPPORT"):
				continue
			if float(aprof[a.idx].cc) <= 0.0 and not a.def.tags.has("PEEL"):
				continue
			var d2: = a.pos.distance_to(sim.u_at(int(victim)).pos)
			if d2 < bd and d2 < 420.0:
				bd = d2
				best = a
		if best:
			protector[best.idx] = {"victim": int(victim), "threat": peel[victim]}
	plan.protector = protector


# V1.5.3 per-tick / per-decision caches (audit D5). All are derived from our
# own orders or public geometry; none survives a battle.
var _reserved_tick: int = -1
var _route_cache: Dictionary = {}    # hero idx -> {"goal", "from", "wp", "until"}
var _scout_cache: Dictionary = {}    # hero idx -> {"to", "path", "until"}
var _ability_flag_cache: Dictionary = {}
var _glide_to: Dictionary = {}       # hero idx -> enemy idx a glide was launched at (D10)
var _hazard_arena: Arena = null
var _hazard_damaging: bool = false


# Once per tick: every hero deciding in the same tick shares one computation.
# A deciding hero first releases its own previous pledge (see _decide) and
# _commit_decision adds the new one, so later deciders still see it.
func _compute_reserved() -> void :
	_reserved_tick = sim.tick
	reserved.clear()
	var claims: Dictionary = {}
	var support_claims: Dictionary = {}
	for ally in allies_cache:
		var act: ST.Action = ally.action
		if act == null or not act.windup or act.target_idx < 0:
			continue
		# An enemy our hive mind controls fights for us right now: damage
		# aimed at it is not a pledge on a kill (heroes-B follow-up 3).
		var tu0: BUnit = sim.u_at(act.target_idx)
		if tu0 and tu0.team != team and sim.eteam(tu0) == team:
			continue
		var target: TeamIntel.EnemyBelief = intel.enemies.get(act.target_idx)
		if target == null:
			var recipient: BUnit = sim.u_at(act.target_idx)
			if recipient and recipient.team == team and act.ability:
				var aid: Dictionary = KitModel.evaluate(act.ability.effects, KitModel.stats_of_unit(sim, ally), {})
				support_claims[act.target_idx] = float(support_claims.get(act.target_idx, 0.0)) + float(aid.heal) + float(aid.shield) * 0.5
			continue
		var st: Dictionary = KitModel.stats_of_unit(sim, ally)
		var damage: float = KitModel.basic_dps(st, ally.def) / maxf(0.2, float(st.as)) * 0.75
		if act.ability:
			var ev: Dictionary = KitModel.evaluate(act.ability.effects, st, {"hp": target.hp, "max_hp": target.max_hp})
			damage = KitModel.mitigate(ev, target.def.stat("armor"), target.def.stat("magicResistance")) * KitModel.delivery_hit(act.ability)
			var cc: float = KitModel.cc_total(ev)
			if cc > 0.0:
				claims[act.target_idx] = maxf(float(claims.get(act.target_idx, 0.0)), act.resolve_at + cc)
		reserved[act.target_idx] = float(reserved.get(act.target_idx, 0.0)) + damage
	for p in sim.proj.list:
		if p.team != team or p.dead:
			continue
		var tgt: = p.target_idx
		if tgt < 0:
			continue
		var tu1: BUnit = sim.u_at(tgt)
		if tu1 and tu1.team != team and sim.eteam(tu1) == team:
			continue
		var owner: BUnit = sim.u_at(p.source_idx)
		var target: TeamIntel.EnemyBelief = intel.enemies.get(tgt)
		if owner == null or target == null or p.pos.distance_to(target.pos) / maxf(50.0, p.speed) > 1.2:
			continue
		var ev: Dictionary = KitModel.evaluate(p.effects, KitModel.stats_of_unit(sim, owner), {"hp": target.hp, "max_hp": target.max_hp})
		var dmg: float = KitModel.mitigate(ev, target.def.stat("armor"), target.def.stat("magicResistance"))
		reserved[tgt] = float(reserved.get(tgt, 0.0)) + dmg * (0.9 if p.homing else 0.55)
	for idx in commitments.keys():
		var pledge: Dictionary = commitments[idx]
		var ally: BUnit = sim.u_at(int(idx))
		if ally == null or not ally.alive or float(pledge.until) <= sim.time:
			commitments.erase(idx)
			continue
		if ally.action != null:
			continue
		var target: int = int(pledge.target)
		var tu2: BUnit = sim.u_at(target)
		if tu2 and tu2.team != team and sim.eteam(tu2) == team:
			continue
		reserved[target] = float(reserved.get(target, 0.0)) + float(pledge.damage)
		if float(pledge.cc_until) > sim.time:
			claims[target] = maxf(float(claims.get(target, 0.0)), float(pledge.cc_until))
		if float(pledge.support) > 0.0:
			support_claims[target] = float(support_claims.get(target, 0.0)) + float(pledge.support)
	plan.cc_claims = claims
	plan.support_claims = support_claims


func _release_commitment(u: BUnit, pledge: Dictionary) -> void:
	if pledge.is_empty() or float(pledge.get("until", 0.0)) <= sim.time or u.action != null:
		return
	var target: int = int(pledge.target)
	if reserved.has(target):
		var left: float = float(reserved[target]) - float(pledge.damage)
		if left <= 0.001:
			reserved.erase(target)
		else:
			reserved[target] = left
	var support: Dictionary = plan.get("support_claims", {})
	if float(pledge.get("support", 0.0)) > 0.0 and support.has(target):
		support[target] = maxf(0.0, float(support[target]) - float(pledge.support))




const ARCH_LABEL: = {"DIVE": "돌진", "PICK": "낚아채기", "POKE": "견제·사거리", "FORTRESS": "요새·보호", "ZONE": "구역 장악", "SUSTAIN": "소모전"}
const PLAN_ORDERS: = {
	"DIVE": ["진입 신호에 맞춰 동시에 돌입", "처치 뒤 보호선으로 복귀"], 
	"PICK": ["고립된 적만 개전", "강제 이동 뒤 화력을 순서대로"], 
	"POKE": ["사거리와 전후열 간격 유지", "적 돌진기가 빠진 뒤 역공"], 
	"FORTRESS": ["주 화력을 중심으로 전선 고정", "보호선을 넘는 적에게 제어"], 
	"ZONE": ["장판과 제어로 탈출로 봉쇄", "밀집한 적에게 광역기"], 
	"SUSTAIN": ["회복으로 시간 우위", "적 회복 억제 우선"], 
}



static func comp_scores(defs: Array) -> Dictionary:
	var s: = {"DIVE": 0.0, "PICK": 0.0, "POKE": 0.0, "FORTRESS": 0.0, "ZONE": 0.0, "SUSTAIN": 0.0}
	for d0 in defs:
		var d: Defs.CharDef = d0
		var roles: Array = Doctrine.of(d.id).get("roles", [])
		var melee: = d.preferred_range < 120.0
		if d.tags.has("ENGAGE"):
			s.DIVE += 1.2
		if d.tags.has("MOBILITY") and melee:
			s.DIVE += 0.8
		if roles.has("DIVER") or roles.has("FLANKER"):
			s.DIVE += 1.0
		if roles.has("PICK") or roles.has("FINISHER"):
			s.PICK += 1.0
		if d.tags.has("CONTROL"):
			s.PICK += 0.5
			s.ZONE += 0.4
		if d.tags.has("RANGED"):
			s.POKE += 1.0
		if d.tags.has("DISENGAGE"):
			s.POKE += 0.8
		if d.preferred_range > 180.0:
			s.POKE += 0.6
		if d.role == "FRONTLINE":
			s.FORTRESS += 1.3
		if d.tags.has("PEEL"):
			s.FORTRESS += 1.0
		if d.tags.has("SHIELDING"):
			s.FORTRESS += 0.6
		if d.tags.has("AREA_DAMAGE"):
			s.ZONE += 1.0
		if d.tags.has("DAMAGE_OVER_TIME"):
			s.ZONE += 0.5
			s.SUSTAIN += 0.4
		if d.tags.has("HEALING"):
			s.SUSTAIN += 1.2
		if d.tags.has("SUMMONER"):
			s.ZONE += 0.4
			s.SUSTAIN += 0.4
	return s


static func _rank_arch(sc: Dictionary) -> Array:
	var ks: Array = sc.keys()
	ks.sort_custom( func(a, b): return float(sc[a]) > float(sc[b]) or (float(sc[a]) == float(sc[b]) and str(a) < str(b)))
	return ks



func _analyze_comp() -> void :
	var ours: Array = []
	var theirs: Array = []
	for u in sim.heroes:
		if u.team == team:
			ours.append(u.def)
		else:
			theirs.append(u.def)
	var so: = comp_scores(ours)
	var st: = comp_scores(theirs)
	var ro: = _rank_arch(so)
	var rt: = _rank_arch(st)
	var k_engage: = 0.0
	var k_coh: = 1.0
	var k_peel: = 1.0
	var k_spread: = 1.0
	var k_iso: = 1.2
	if cfg.comp > 0.5:
		match str(ro[0]):
			"DIVE":
				k_engage -= 0.04
			"POKE":
				k_engage += 0.05
				k_coh = 1.25
			"FORTRESS":
				k_coh = 1.3
			"PICK":
				k_iso = 1.4
		match str(rt[0]):
			"DIVE", "PICK":
				k_peel = 1.4
				k_coh *= 1.15
			"ZONE":
				k_spread = 1.6
			"POKE":
				k_engage -= 0.03
	var orders: Array = []
	orders.append_array(PLAN_ORDERS.get(str(ro[0]), []))
	if str(rt[0]) in ["DIVE", "PICK"]:
		orders.append("상대 %s 대비: 후열 곁 보호 유지" % ARCH_LABEL.get(str(rt[0]), ""))
	elif str(rt[0]) == "ZONE":
		orders.append("상대 광역기 대비: 산개")
	plan.comp = {"ours": so, "theirs": st, "primary": str(ro[0]), "secondary": str(ro[1]), "enemy_primary": str(rt[0]), "orders": orders}
	plan.k_engage = k_engage
	plan.k_coh = k_coh
	plan.k_peel = k_peel
	plan.k_spread = k_spread
	plan.k_iso = k_iso



func _assign_roles(allies: Array[BUnit]) -> void :
	var carry: = -1
	var cv: = - INF
	var engage: = -1
	var ev: = - INF
	var finisher: = -1
	var fv: = - INF
	var scout: = -1
	var sv: = - INF
	for a in allies:
		var ap: Dictionary = aprof[a.idx]
		var roles: Array = Doctrine.of(a.def.id).get("roles", [])
		var c: = float(ap.dps) + float(ap.burst) / 5.0
		if ap.backline:
			c *= 1.3
		if roles.has("CARRY") or roles.has("MARKSMAN"):
			c *= 1.25
		if a.def.role == "SUPPORT":
			c *= 0.6
		if c > cv:
			cv = c
			carry = a.idx
		var e: = (2.0 if a.def.role == "FRONTLINE" else 0.0) + (1.5 if a.def.tags.has("ENGAGE") else 0.0)\
		+ (1.2 if roles.has("ENGAGE") or roles.has("DIVER") else 0.0) + float(ap.cc) * 0.8 + sim.max_hp(a) / 1000.0
		if e > ev:
			ev = e
			engage = a.idx
		var f: = (2.0 if roles.has("FINISHER") else 0.0) + float(ap.burst) / 200.0
		if f > fv:
			fv = f
			finisher = a.idx
		var sc: = ((2.0 if roles.has("SCOUT") else 0.0) + float(ap.st.ms) / 100.0 + minf(1.2, float(ap.ehp) / 1800.0)) * (0.3 + 0.7 * sim.hp_ratio(a))
		if a.def.id == "politician":
			sc *= 0.2
		if sc > sv:
			sv = sc
			scout = a.idx
	var protectors: Array = []
	for a in allies:
		if a.idx == carry:
			continue
		var roles2: Array = Doctrine.of(a.def.id).get("roles", [])
		if roles2.has("PROTECTOR") or roles2.has("GUARD") or roles2.has("PEEL") or roles2.has("TANK") or a.def.role == "SUPPORT":
			protectors.append(a.idx)
	plan.carry = carry if allies.size() > 1 else -1
	plan.engage_lead = engage
	plan.finisher = finisher
	plan.scout = scout
	plan.protectors = protectors



func _enemy_geometry() -> void :
	var iso: Dictionary = {}
	var mt: = 1.0
	for k in eprof:
		var eb: TeamIntel.EnemyBelief = eprof[k].b
		mt = maxf(mt, float(eprof[k].threat))
		var d: = INF
		for k2 in eprof:
			if k2 != k:
				d = minf(d, eb.pos.distance_to((eprof[k2].b as TeamIntel.EnemyBelief).pos))
		iso[int(k)] = d
	plan.iso = iso
	plan.max_threat = mt



func _local_fight(allies: Array[BUnit]) -> void :
	var zone: Array = []
	var zc: = Vector2.ZERO
	var fighting: = false
	for k in eprof:
		var pr: Dictionary = eprof[k]
		var eb: TeamIntel.EnemyBelief = pr.b
		if not eb.visible:
			continue
		var in_zone: = false
		for a in allies:
			var d: = a.pos.distance_to(eb.pos)
			if d <= maxf(float(pr.reach), float(aprof[a.idx].reach)) + 120.0:
				in_zone = true

			if d <= minf(float(aprof[a.idx].reach), 320.0) + 60.0 or d <= float(pr.range) + sim.radius(a) + eb.radius + 60.0:
				fighting = true
		if in_zone:
			zone.append(int(k))
			zc += eb.pos
	plan.fighting = fighting
	plan.contact = not zone.is_empty()
	plan.zone = zone
	if zone.is_empty():
		plan.local_adv = float(plan.get("adv_global", 0.0))
		plan.local_n = [0.0, 0.0]
		return
	zc /= zone.size()
	plan.zone_c = zc
	var od: = 0.0
	var oe: = 0.0
	var on: = 0.0
	for a in allies:
		var ap: Dictionary = aprof[a.idx]
		if a.pos.distance_to(zc) <= float(ap.reach) + float(ap.st.ms) * 2.0 + 80.0:
			od += float(ap.dps) + float(ap.burst) / 5.0
			oe += float(ap.ehp)
			on += 1.0
	var td: = 0.0
	var te: = 0.0
	var tn: = 0.0
	for k in eprof:
		var pr2: Dictionary = eprof[k]
		var eb2: TeamIntel.EnemyBelief = pr2.b
		var w: = 1.0 if eb2.visible else clampf(eb2.confidence + 0.2, 0.3, 1.0)
		if eb2.pos.distance_to(zc) <= float(pr2.reach) + float(pr2.ms) * 2.0 + 80.0:
			td += (float(pr2.dps) + float(pr2.burst) / 5.0) * w
			te += float(pr2.ehp) * w
			tn += w
	plan.local_adv = log(maxf(1.0, oe * od) / maxf(1.0, te * td)) * 0.5 + 0.12 * (on - tn)
	plan.local_n = [on, tn]



func _predict_enemy_focus(allies: Array[BUnit]) -> void :
	var scores: Dictionary = {}
	var total: = 0.0
	var best: = -1
	var best_v: = 0.0
	for a in allies:
		var ap: Dictionary = aprof[a.idx]
		var reach_dps: = 0.0
		for k in eprof:
			var pr: Dictionary = eprof[k]
			var eb: TeamIntel.EnemyBelief = pr.b
			var d: = eb.pos.distance_to(a.pos)
			var f: = 1.0 if d <= float(pr.reach) + 80.0 else maxf(0.0, 1.0 - (d - float(pr.reach) - 80.0) / 360.0)
			reach_dps += (float(pr.dps) + float(pr.burst) / 3.0) * f * (1.0 if eb.visible else clampf(eb.confidence, 0.3, 1.0))
		var ttk: = float(ap.ehp) / maxf(20.0, reach_dps)
		var v: = (float(ap.contrib) * 4.0 + 250.0 + (130.0 if a.def.role == "SUPPORT" else 0.0)) / (ttk + 0.6)
		v *= 1.0 + minf(1.0, intel.focus_evidence(a.idx)) * 0.65
		scores[a.idx] = v
		total += v
		if v > best_v:
			best_v = v
			best = a.idx
	var hunted: Dictionary = {}
	if total > 0.0 and allies.size() > 1:
		for k2 in scores:

			var p: = float(scores[k2]) / total
			hunted[k2] = clampf((p - 1.0 / allies.size()) * 2.0 + (0.35 if int(k2) == best else 0.0), 0.0, 1.0)
	plan.hunted = hunted
	plan.enemy_focus = best



func _find_punish(allies: Array[BUnit]) -> void :
	plan.punish = -1
	if cfg.punish < 0.5 or not bool(plan.get("contact", false)):
		return
	var best: = -1
	var best_v: = 0.0
	for k in plan.zone:
		var pr: Dictionary = eprof.get(k, {})
		if pr.is_empty():
			continue
		var eb: TeamIntel.EnemyBelief = pr.b
		var support: = 0.0
		for k2 in eprof:
			if int(k2) == int(k):
				continue
			var e2: TeamIntel.EnemyBelief = eprof[k2].b
			if e2.pos.distance_to(eb.pos) < 340.0:
				support += 1.0 if e2.visible else e2.confidence
		var dmg: = 0.0
		var n: = 0
		for a in allies:
			var w: = Doctrine.attack_window(self, a, eb, 2.5)
			if w > 0.0:
				dmg += w + float(aprof[a.idx].burst) * 0.5
				n += 1
		if n >= 2 and support < 0.6:
			var v: = dmg / maxf(50.0, float(pr.ehp))
			if v > 0.6 and v > best_v:
				best_v = v
				best = int(k)
	plan.punish = best



func _engage_signal(allies: Array[BUnit]) -> void :
	var stance: = str(plan.stance)
	var fighting: = bool(plan.get("fighting", false))
	plan.grouped = true
	if stance == "SCOUT" and cfg.hyst > 0.5 and str(plan.get("raw_stance", "")) == "ENGAGE":

		return
	var go: = false
	if stance != "ENGAGE":
		plan.engage_since = -1.0
	elif cfg.gate < 0.5 or fighting:
		go = true
	else:
		if float(plan.get("engage_since", -1.0)) < 0.0:
			plan.engage_since = sim.time
		var ac: Vector2 = plan.ally_c
		var spread: = 0.0
		for a in allies:
			spread = maxf(spread, a.pos.distance_to(ac))
		var grouped: = spread <= 200.0
		plan.grouped = grouped
		go = grouped or sim.time - float(plan.engage_since) > 3.5
	if go and not bool(plan.get("go", false)):
		plan.go_since = sim.time
	plan.go = go



func _cc_claims(allies: Array[BUnit]) -> void :
	var claims: Dictionary = {}
	for a in allies:
		var act: = a.action
		if act == null or act.kind != "ability" or act.ability == null or not act.windup:
			continue
		var ab: = act.ability
		if ab.cc_types.is_empty() or act.target_idx < 0:
			continue
		var ccd: = KitModel.cc_total(KitModel.evaluate(ab.effects, {}, {}))
		if ccd <= 0.0:
			continue
		claims[act.target_idx] = maxf(float(claims.get(act.target_idx, 0.0)), act.resolve_at + ccd)
	plan.cc_claims = claims
	plan.burst = -1
	var f: = int(plan.get("focus", -1))
	if f >= 0 and intel.enemies.has(f):
		var fe: TeamIntel.EnemyBelief = intel.enemies[f]
		if fe.visible and (fe.hard_cc_remaining() >= 0.5 or float(claims.get(f, 0.0)) - sim.time >= 0.6):
			plan.burst = f


func _label_operation() -> void :
	var st: = str(plan.stance)
	var op: = "견제"
	match st:
		"SCOUT":
			op = "정찰"
		"DISENGAGE":
			op = "후퇴·재정비"
		"ENGAGE":
			if not bool(plan.get("fighting", false)):
				op = "진입" if bool(plan.get("go", false)) else "집결 대기"
			else:
				op = "교전"
	if st != "DISENGAGE":
		if int(plan.get("punish", -1)) >= 0:
			op = "고립 적 집중"
		elif int(plan.get("burst", -1)) >= 0:
			op = "제어 연계 집중"
		elif not (plan.get("peel_threats", {}) as Dictionary).is_empty():
			op = "후열 보호"
	plan.op = op



static func is_dive(a: Defs.AbilityDef) -> bool:
	if a.action in ["contactDash", "glide", "swapBox"]:
		return true
	if a.target != "enemy":
		return false
	for f in a.effects:
		if str(f.get("type", "")) == "move_self" and str(f.get("mode", "")) in ["dash", "blink", "dashToImpact"]:
			return true
	return false



func cohesion_allow(_u: BUnit, ctx: Dictionary) -> float:
	if control_plan:
		# Different objective assignments deliberately split the team.
		return INF
	var stance: = str(plan.stance)
	if cfg.gate < 0.5 or bool(ctx.engaged) or stance == "DISENGAGE":
		return INF
	var allow: = 90.0 if float(ctx.pref) < 100.0 else 60.0
	if ctx.backline:
		allow = -30.0
	if bool(plan.get("go", false)):
		allow += 60.0
		if cfg.march > 0.5:

			allow += clampf((sim.time - float(plan.get("go_since", sim.time))) * 60.0, 0.0, 260.0)
	if stance == "SCOUT":
		allow += 100.0
	if bool(plan.get("fighting", false)):
		allow += 40.0

	allow += 120.0 * float(plan.get("stale", 0.0)) + 100.0 * float(plan.get("nokill", 0.0))
	return allow



func leader_line(u: BUnit, ctx: Dictionary) -> Dictionary:
	if control_plan:
		return {}
	if cfg.lead < 0.5 or bool(ctx.engaged) or float(ctx.pref) >= 120.0:
		return {}
	if cfg.march > 0.5 and bool(plan.get("go", false)) and sim.time - float(plan.get("go_since", sim.time)) > 2.5:
		return {}
	var li: = int(plan.get("engage_lead", -1))
	if li < 0 or li == u.idx:
		return {}
	var lu: = sim.u_at(li)
	if lu == null or not lu.alive or not (lu.def.role == "FRONTLINE" or sim.max_hp(lu) >= 1200.0):
		return {}

	for b in intel.visible_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.pos.distance_to(lu.pos) <= float(aprof.get(li, {}).get("reach", 150.0)) + 40.0:
			return {}
	return {"pos": lu.pos}



func _team_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void :
	if cfg.gate < 0.5:
		return
	var go: = bool(plan.get("go", false))
	var engaged: = bool(ctx.engaged)
	var punish: = int(plan.get("punish", -1))
	var allow: = cohesion_allow(u, ctx)
	var coh_k: = float(plan.get("k_coh", 1.0))
	var ac: Vector2 = plan.ally_c
	var dir_e: Vector2 = plan.dir
	var ll: = leader_line(u, ctx)
	var abilities: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)

	var lethal: = float(ctx.danger) - float(ctx.ehp) * 0.45
	var cloaked: = sim.has_status(u, &"invisible")
	for c in cands:
		var cmd: Dictionary = c.cmd
		var kind: = str(cmd.get("kind", ""))
		if kind == "move":
			continue
		var kill: = float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0
		var ti: = int(cmd.get("target", -1))
		if cfg.surv > 0.5 and not kill and (kind == "basic" or (kind == "ability" and ti >= 0 and not sim.u_at(ti) == null and sim.eteam(sim.u_at(ti)) != team)):
			var dur: = 0.35
			if kind == "ability":
				var ixa: = int(cmd.get("index", -1))
				if ixa >= 0 and ixa < abilities.size():
					var aa: Defs.AbilityDef = abilities[ixa]
					dur = aa.cast_time + aa.recovery + 0.15
					if is_dive(aa) or bool(_ability_flags(aa).move_self):
						dur = 0.0
			if lethal > 0.0 and dur > 0.0:
				Doctrine._note(c, - lethal * float(ctx.risk_w) * clampf(dur, 0.3, 1.0), "생존 본능")

			if cloaked and float(ctx.danger) > float(ctx.ehp) * 0.25:
				Doctrine._note(c, - float(ctx.danger) * float(ctx.risk_w) * 0.6, "은신 유지")
		# A follow-up on a mark this hero owns (e.g. a blade trace) expires on
		# its own clock; formation and engage-signal gates would let it lapse.
		var follow_up: bool = false
		if kind == "ability":
			var ixf: = int(cmd.get("index", -1))
			if ixf >= 0 and ixf < abilities.size():
				var af: Defs.AbilityDef = abilities[ixf]
				follow_up = af.condition.has("targetStatus") and bool(af.condition.get("owned", false))
		# Hero-agent candidates flagged gate_exempt (swordsman S4 on its own
		# trace, hive S4 before a control expires) run on their own clock: the
		# engage signal, formation and front-line gates would let them lapse.
		var exempt: bool = bool(c.get("gate_exempt", false))
		if kind == "ability" and not go and not engaged and not follow_up and not exempt:
			var ix: = int(cmd.get("index", -1))
			if ix >= 0 and ix < abilities.size() and ti != punish and not kill:
				var ab: Defs.AbilityDef = abilities[ix]
				var offensive_cloak: = ab.action == "cloak" and float(ctx.danger) < float(ctx.ehp) * 0.25 and float(u.ks.get("cloak_until", 0.0)) <= sim.time
				if is_dive(ab) or offensive_cloak:
					Doctrine._note(c, - maxf(0.0, float(c.value)) * 0.45 - 20.0, "진입 신호 대기")

		if kind == "ability" and ti != punish and not kill:
			var tp: Vector2 = cmd.get("pos", u.pos)
			if ti >= 0 and intel.enemies.has(ti):
				tp = (intel.enemies[ti] as TeamIntel.EnemyBelief).pos
			var need: = float(cmd.get("need", 0.0))
			var d: = u.pos.distance_to(tp)
			if need > 1.0 and d > need + 10.0:
				var cast_pos: = tp + (u.pos - tp).normalized() * need
				if allow < INF and not follow_up and not exempt:
					var ahead: = (cast_pos - ac).dot(dir_e)
					if ahead > allow:
						Doctrine._note(c, - (ahead - allow) * 0.5 * coh_k * float(cfg.coh), "대형 유지")
				if not ll.is_empty() and not follow_up and not exempt:
					var ahead_l: = (cast_pos - (ll.pos as Vector2)).dot(dir_e)
					if ahead_l > 20.0:
						Doctrine._note(c, - (ahead_l - 20.0) * 0.4, "전열 우선 진입")
				if cfg.appr > 0.5:
					var dz: = danger_at(u, cast_pos, 1.0) - float(ctx.danger)
					if dz > 0.0:
						Doctrine._note(c, - dz * float(ctx.risk_w) * (0.25 if exempt else 0.5), "접근 위험")






func danger_at(u: BUnit, p: Vector2, horizon: float = 1.0, visible_only: bool = false) -> float:

	var ck: = Vector3i(u.idx, int(p.x / 6.0) * 4096 + int(p.y / 6.0), int(horizon * 10.0) + (1000 if visible_only else 0) + (2000 if sim.env.enabled else 0))
	if _danger_cache_t == sim.tick and _danger_cache.has(ck):
		return _danger_cache[ck]
	if _danger_cache_t != sim.tick:
		_danger_cache.clear()
		_danger_cache_t = sim.tick
	var dv: = _danger_raw(u, p, horizon, visible_only)
	_danger_cache[ck] = dv
	return dv


func _danger_raw(u: BUnit, p: Vector2, horizon: float, visible_only: bool = false) -> float:
	var r: = sim.radius(u)
	var d: = 0.0
	var hunted_p: = float((plan.get("hunted", {}) as Dictionary).get(u.idx, 0.0))
	# B-PERF2: per-profile constants come from _danger_table (the same values
	# in eprof's order).
	_danger_table()
	for ti in _dt_pr.size():
		var w: float = _dt_w[ti]
		var eb: TeamIntel.EnemyBelief = _dt_eb[ti]
		if w < 0.05 or (visible_only and not eb.visible):
			continue
		if eb.def.id == "hades":
			d += w * HadesTactics.aura_danger(self, u, eb, p, horizon) # V2 hades S3 aura
		var dist: = p.distance_to(eb.pos) - r - eb.radius
		var melee: = _dt_melee[ti] == 1
		var approach: = _dt_ms[ti] * horizon * (0.85 if melee else 0.45)
		if eb.movement_samples >= 8:
			approach *= 0.7 + eb.aggression * 0.6
		if dist > _dt_reach[ti] + approach + 40.0:
			continue
		var pr: Dictionary = _dt_pr[ti]
		var los_f: = 1.0
		if not melee and dist > 60.0 and not sim.arena.line_of_sight(eb.pos, p, 2.0):
			los_f = 0.35

		var dpe: = p.distance_to(eb.pos)
		var others: = 0.0
		for a in allies_cache:
			if a == u or not a.alive:
				continue
			var da: = a.pos.distance_to(eb.pos)
			if da <= dpe + 30.0 and da <= float(pr.reach) + 90.0:
				others += 1.0 if aprof.has(a.idx) and aprof[a.idx].tank else 0.7
		var share: = 1.0 / (1.0 + others) if cfg.share > 0.5 else 1.0

		share = lerpf(share, 1.0, hunted_p)
		var br: = float(pr.range)
		if dist <= br + approach:
			d += w * float(pr.dps) * horizon * clampf(1.0 - (dist - br) / (approach + 1.0), 0.15, 1.0) * los_f * share
		for ab in pr.abilities:
			if dist <= float(ab.range) + approach * 0.6 + 10.0:
				var hit: = float(ab.get("hit", 0.6)) if cfg.hitw > 0.5 else 0.7
				d += w * (float(ab.dmg) * hit * 0.85 + float(ab.cc) * hit * 50.0) * los_f * lerpf(share, 1.0, 0.35)

	for ek in intel.entities:
		var eb2: TeamIntel.EnemyBelief = intel.entities[ek]
		if not eb2.visible:
			continue
		var dd: = p.distance_to(eb2.pos)
		if eb2.kind == "turret" and dd < 250.0:
			d += 35.0 * horizon
		elif eb2.kind in ["snake", "brood"] and dd < 80.0:
			d += 18.0 * horizon
		elif eb2.kind in HadesTactics.SUMMON_KINDS:
			d += HadesTactics.entity_danger(self, u, eb2, p, horizon) # V2 hades pet / shades
		elif eb2.kind == "chariot":
			d += AchillesTactics.chariot_danger(self, u, eb2, p, horizon)

	for pj in intel.projectiles:
		var v: Vector2 = pj.vel
		var sp: = v.length()
		if sp < 1.0:
			continue
		var rel: Vector2 = p - (pj.pos as Vector2)
		if pj.homing:
			if int(pj.target) == u.idx and rel.length() / sp < horizon + 0.3:
				d += float(pj.dmg)
			continue
		var tca: = clampf(rel.dot(v) / (sp * sp), 0.0, horizon + 0.2)
		if rel.dot(v) <= 0.0:
			continue
		var closest: Vector2 = (pj.pos as Vector2) + v * tca
		if closest.distance_to(p) < float(pj.radius) + r + 4.0:
			d += float(pj.dmg) * (1.6 if pj.cc else 1.0)
		if pj.explode and (pj.target_pos as Vector2).distance_to(p) < float(pj.impact_r) + r:
			d += float(pj.dmg) * 0.8

	for tg in intel.telegraphs:
		if _in_telegraph(p, r, tg):
			d += float(tg.dmg) * (1.5 if tg.cc else 1.0)

	for z in intel.zones:
		if not z.harm:
			continue
		if z.kind == "rift":
			continue
		if str(z.shape) == "rect":
			d += WarMachineTactics.rect_zone_danger(z, p, r, horizon)
			continue
		if (z.pos as Vector2).distance_to(p) <= float(z.radius) + r:
			d += 22.0 * horizon if z.kind != "bait" else 60.0

	# Brush caution (D13 follow-up): brush the hidden enemies' particles sit in
	# is a possible ambush; its share of their threat is priced near it (the
	# belief mean alone smears an ambusher between brush and open ground).
	for bz: Dictionary in _brush_threats:
		if p.distance_to(bz.c) - r - float(bz.rad) * 0.5 <= float(bz.reach) + 30.0:
			d += float(bz.mass) * float(bz.threat) * horizon * 0.45

	if sim.env.enabled and _hazard_near(p, r + 2.0):
		# Switch-aware map costs (developer per-type toggles). Announced
		# artillery strikes enter through the public telegraphs above with
		# their real damage, so ArenaEnv's strike circles are not added twice.
		var mask: int = sim.env.disabled_mask
		d += sim.arena.expected_hazard_damage(p, sim.time, r, horizon, mask, sim.max_hp(u)) * 0.9
		# Non-damaging gravity and imminent shockwave rings still cost movement
		# and initiative. The shared public geometry supplies that risk.
		d += maxf(0.0, sim.arena.hazard_penalty(p, sim.time + minf(horizon, 0.5), r, mask)) * 20.0
	return d


func _in_telegraph(p: Vector2, r: float, tg: Dictionary) -> bool:
	match str(tg.shape):
		"circle":
			return (tg.to as Vector2).distance_to(p) <= float(tg.radius) + r + 4.0
		"line":
			var from: Vector2 = tg.from
			var dir: Vector2 = ((tg.to as Vector2) - from).normalized()
			var end: = from + dir * float(tg.range)
			return Geometry2D.get_closest_point_to_segment(p, from, end).distance_to(p) <= float(tg.width) * 0.5 + r + 4.0
		"cone":
			var from2: Vector2 = tg.from
			var v: = p - from2
			if v.length() > float(tg.range) + r:
				return false
			var dir2: Vector2 = ((tg.to as Vector2) - from2).normalized()
			return absf(dir2.angle_to(v)) <= float(tg.angle) * 0.5 + 0.15
		"self":
			return (tg.from as Vector2).distance_to(p) <= float(tg.radius) + r + 6.0
	return false






func _ctx(u: BUnit) -> Dictionary:
	var st: = KitModel.stats_of_unit(sim, u)
	var hp: = u.hp
	var mx: = sim.max_hp(u)
	var shield: = sim.shield_amount(u)
	# targets: everything the team sees (movement, danger, focus, areas).
	# strike: the subset this hero observes itself. The simulator voids any
	# order on an enemy its caster does not observe (sim._try_execute_command),
	# so unit-targeted attacks are only generated from `strike` (audit D1/X1).
	var targets: Array = []
	var strike: Array = []
	for b in intel.visible_enemies(true):
		var eb: TeamIntel.EnemyBelief = b
		if eb.controlled_by_us:
			continue
		var tu: = sim.u_at(eb.idx)
		if tu == null or not tu.alive or tu.chamber != u.chamber:
			continue
		targets.append(eb)
		if sim.observes(u, tu):
			strike.append(eb)
	var allies: Array[BUnit] = []
	for a in sim.allies_of(team):
		if a != u and a.team == team:
			allies.append(a)
	var stance: = str(plan.stance)
	var surv: = float(u.def.behavior.get("survival", 0.5))

	var worth: = float(aprof.get(u.idx, {}).get("worth", 0.08))
	var rel: = clampf(worth / maxf(0.005, float(plan.get("ew_mean", 0.08))), 0.45, 2.4)
	var risk_w: = rel * (0.8 + 0.4 * surv)
	if hp / mx < 0.3:
		risk_w *= 1.0 + (0.3 - hp / mx) * 2.5
	if cfg.worth < 0.5:
		risk_w = (0.55 + 0.9 * (1.0 - hp / mx)) * (0.75 + 0.5 * surv)
	risk_w *= float(cfg.risk)
	match stance:
		"ENGAGE":
			risk_w *= 0.75
		"DISENGAGE":
			risk_w *= 1.3
	risk_w *= 1.0 - 0.35 * float(plan.get("pressure", 0.0))
	risk_w *= 1.0 - 0.3 * float(plan.get("stale", 0.0))
	risk_w *= 1.0 + 0.25 * float((plan.get("hunted", {}) as Dictionary).get(u.idx, 0.0))
	var budget: float = clampf(float(plan.get("risk_budget", 0.4)) * (0.4 + 0.6 * hp / mx), 0.1, 0.8)
	risk_w *= 1.18 - budget * 0.48

	var pot: Array = []
	var abilities: = sim.ability_list(u)
	for i in abilities.size():
		var a: Defs.AbilityDef = abilities[i]
		if a.virtual or not a.hostile or not sim.ability_ready(u, i, a):
			continue
		var ev: = KitModel.evaluate(a.effects, st, {"max_hp": 1000.0, "hp": 800.0})
		var val: = KitModel.mitigate(ev, 40.0, 35.0) * KitModel.delivery_hit(a) + KitModel.cc_total(ev) * 60.0
		var rr: = a.range if a.target != "self" else a.radius
		if a.action == "contactDash":
			rr = float(a.flag("originDistance", a.range))
		pot.append({"range": rr, "value": val})
	var focus: TeamIntel.EnemyBelief = null
	var fidx: = int(plan.focus)
	if fidx >= 0 and intel.enemies.has(fidx):
		focus = intel.enemies[fidx]
	var danger: = danger_at(u, u.pos, 1.0)

	var engaged: = false
	var reach: = float(aprof.get(u.idx, {}).get("reach", float(st.range) + 30.0))
	for b in targets:
		var eb2: TeamIntel.EnemyBelief = b
		if eb2.is_hero and u.pos.distance_to(eb2.pos) <= maxf(float(st.range) + 90.0, minf(reach, 320.0)):
			engaged = true
			break
	return {"u": u, "st": st, "hp": hp, "mx": mx, "hpr": hp / mx, "ehp": hp + shield, "shield": shield,
		"r": sim.radius(u), "range": float(st.range), "pref": u.def.preferred_range, "ms": float(st.ms),
		"targets": targets, "strike": strike, "allies": allies, "stance": stance, "risk_w": risk_w, "focus": focus, "pot": pot,
		"danger": danger, "dps": KitModel.basic_dps(st, u.def), "backline": aprof.get(u.idx, {}).get("backline", false),
		"engaged": engaged, "risk_budget": budget, "abilities": abilities}


func decide(u: BUnit) -> void :
	if _v2_link_frozen(u):
		return
	if _squad_mode():
		var saved: Dictionary = plan
		plan = _squad_plan_for(u)
		_decide(u)
		plan = saved
		return
	_decide(u)


func _decide(u: BUnit) -> void :
	if sim.scale_lod and not sim.lod_admit(u):
		# Scale battles: over this tick's decision budget. The current order
		# stands and the hero stays due; the simulator's count is not raised.
		u.decisions -= 1
		return
	decisions_made += 1
	if _obey_forced_target(u):
		return
	var own_pledge: Dictionary = commitments.get(u.idx, {})
	commitments.erase(u.idx)
	if _reserved_tick != sim.tick:
		_compute_reserved()
	else:
		_release_commitment(u, own_pledge)
	var n: = sim.heroes.size()
	var ctx: = _ctx(u)
	var urgent: = float(ctx.danger) > float(ctx.ehp) * 0.35
	if sim.scale_lod:
		u.next_decision_at = sim.time + _lod_interval(u, ctx, urgent) + rng.randf() * 0.03
		if _lod_travel(u, ctx):
			return
	else:
		u.next_decision_at = sim.time + (0.09 if urgent else (0.15 + 0.012 * n if cfg.dint > 0.5 else 0.13 + 0.01 * n)) + rng.randf() * 0.03
	var cands: Array = []
	_ability_candidates(u, ctx, cands)
	_basic_candidates(u, ctx, cands)
	_move_candidates(u, ctx, cands)
	if cfg.doct > 0.5:
		Doctrine.adjust(self, u, ctx, cands)
	_team_adjust(u, ctx, cands)
	_coordination_adjust(u, ctx, cands)
	_gimmick_adjust(u, ctx, cands)
	if control_plan:
		_control_adjust(u, ctx, cands)
	_mode_adjust(u, ctx, cands)
	if cands.is_empty():
		u.command = {"kind": "move", "goal": u.pos, "purpose": "hold", "key": "hold"}
		return
	var m: Dictionary = mem.get(u.idx, {})
	var prev_key: = str(m.get("key", ""))
	# Stuck-order guard (audit D2 general form): an ability order that stays
	# ready, keeps winning and neither starts nor moves the hero for 0.6 s is
	# one the executor keeps refusing (failed condition, unpaid cost, ...).
	# Review 1.5.3: basic orders too. steer() holds at the believed distance
	# while start_basic measures the true one, so a misleading belief (fake
	# news: 100 px for 5 s) froze the attacker for the whole window. A basic
	# order stalls once the attack has been ready 0.6 s without starting and
	# the hero has not moved meanwhile; it is dropped for 1.5 s.
	var stall_key: String = str(m.get("stall_key", "")) if float(m.get("stall_until", -1.0)) > sim.time else ""
	var best: Dictionary = _select_best(cands, prev_key, stall_key)
	var best_kind: String = str(best.cmd.get("kind", ""))
	if (best_kind == "ability" or best_kind == "basic") and str(best.key) != stall_key:
		var basic: bool = best_kind == "basic"
		var mark: float = u.attack_ready_at if basic else float(u.st_casts)
		if str(best.key) != prev_key or str(best.key) != str(m.get("issue_key", "")) or float(m.get("issue_mark", -1.0)) != mark:
			m["issue_key"] = best.key
			m["issue_t"] = sim.time
			m["issue_pos"] = u.pos
			m["issue_mark"] = mark
		elif basic and (u.pos.distance_to(m.get("issue_pos", u.pos)) >= 8.0 or u.action != null or not sim.can_basic(u)):
			# Walking in, between hits or busy: not a stall (yet).
			m["issue_t"] = sim.time
			m["issue_pos"] = u.pos
		elif sim.time - maxf(float(m.issue_t), u.attack_ready_at if basic else -INF) >= 0.6 and u.pos.distance_to(m.get("issue_pos", u.pos)) < 8.0:
			stall_key = str(best.key)
			m["stall_key"] = stall_key
			m["stall_until"] = sim.time + (1.5 if basic else 2.0)
			m.erase("issue_key")
			best = _select_best(cands, prev_key, stall_key)
	else:
		m.erase("issue_key")
	var cmd: Dictionary = best.cmd
	cmd["key"] = best.key
	cmd["purpose"] = best.get("label", "")
	u.command = cmd
	_commit_decision(u, best, ctx)
	m["key"] = best.key
	m["t"] = sim.time
	# Debug list: partial selection of the six best, no full sort (audit D5).
	var ranked: Array = []
	for c1 in cands:
		var f1: float = float(c1.final)
		if ranked.size() == 6 and f1 <= float(ranked[5].final):
			continue
		var at: int = ranked.size()
		while at > 0 and float(ranked[at - 1].final) < f1:
			at -= 1
		ranked.insert(at, c1)
		if ranked.size() > 6:
			ranked.pop_back()
	var top: Array = []
	for c2: Dictionary in ranked:
		top.append({"label": c2.get("label", ""), "score": float(c2.final), "parts": c2.get("parts", {}), "notes": c2.get("notes", [])})
	m["top"] = top
	m["danger"] = ctx.danger
	m["stance"] = ctx.stance
	mem[u.idx] = m


# Argmax with the same-choice hysteresis; a stalled order key drops below
# every ordinary option for the guard's duration.
func _select_best(cands: Array, prev_key: String, stall_key: String) -> Dictionary:
	var best: Dictionary = {}
	var best_v: = - INF
	for c in cands:
		var v: = float(c.value)
		var key: String = str(c.key)
		if stall_key != "" and key == stall_key:
			v = - absf(v) - 200.0
		elif key == prev_key:
			v += absf(v) * 0.1 + 4.0
		c["final"] = v
		if v > best_v:
			best_v = v
			best = c
	return best




func _ability_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void :
	var abilities: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)
	for i in abilities.size():
		var a: Defs.AbilityDef = abilities[i]
		if a.virtual and a.virtual_kind == "parry":
			if cfg.doct > 0.5 and sim.ability_ready(u, i, a):
				_parry_candidate(u, i, a, ctx, out)
			continue
		if not sim.ability_ready(u, i, a):
			continue
		if a.action in ["fakeNews", "propaganda"]:
			_information_support_candidate(u, i, a, ctx, out)
			continue
		if a.virtual:
			_virtual_candidate(u, i, a, ctx, out)
			continue
		if u.def.id == "war_machine" and WarMachineTactics.candidates(self, u, i, a, ctx, out):
			continue
		match a.target:
			"enemy":
				_enemy_target_candidates(u, i, a, ctx, out)
			"position":
				_position_candidates(u, i, a, ctx, out)
			"self":
				_self_candidates(u, i, a, ctx, out)
			"ally":
				_ally_candidates(u, i, a, ctx, out)
			"position_ally":
				_placement_candidates(u, i, a, ctx, out)


func _enemy_value(u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, ctx: Dictionary, hit_p: float, mult: float = 1.0) -> Dictionary:
	if not e.is_hero and e.kind in HadesTactics.SUMMON_KINDS:
		return HadesTactics.summon_value(self, u, a, e, ctx, hit_p, mult) # V2 hades pet / shades
	var st: Dictionary = ctx.st
	var tu: = sim.u_at(e.idx)
	var own: = 0
	if a.effects.size() > 0 and tu:
		for f in a.effects:
			if f.has("perTargetStatusStack"):
				var os: = sim.owned_status(tu, StringName(str(f.perTargetStatusStack.status)), u.idx)
				own = os.stacks if os else 0
	var ev: = KitModel.evaluate(a.effects, st, {"max_hp": e.max_hp, "hp": e.hp, "cc": e.hard_cc_remaining() > 0.05, "own_stacks": own})
	if e.def.id == "torquemada":
		TorquemadaTactics.enemy_view(e, ev)
	# Base armor/MR from the cached definition profile (public, allocation free).
	var est: Dictionary = KitModel._enemy_base(e.def).st
	var dmg: = KitModel.mitigate(ev, float(est.armor), float(est.mr)) * hit_p * mult
	# Visible invulnerability voids damage; visible unstoppable voids control.
	var immune: bool = e.has_status("invulnerable")
	if immune:
		dmg = 0.0
	var ehp_e: = e.hp + e.shield
	if float(ev.execute) > 0.0 and e.hp / maxf(1.0, e.max_hp) <= float(ev.execute) and not immune:
		dmg = maxf(dmg, ehp_e * hit_p)
	# V2: a frontal hit on achilles' raised guard is wasted (AchillesTactics).
	var guard_k: float = AchillesTactics.guard_factor(self, u, a, e) if e.def.id == "achilles" else 1.0
	dmg *= guard_k
	var pr: Dictionary = eprof.get(e.idx, {})
	var threat: = float(pr.get("threat", 300.0)) if e.is_hero else 60.0
	var res: = float(reserved.get(e.idx, 0.0))
	var eff_dmg: = minf(dmg, maxf(0.0, ehp_e - res * 0.8))
	if res >= ehp_e:
		eff_dmg = dmg * 0.25
	var focus_mult: = 1.0
	if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == e.idx:
		focus_mult = 1.35
	if not e.is_hero:
		focus_mult *= 0.35 if e.kind != "turret" else 0.7
	var dmg_v: = eff_dmg * focus_mult * (_ew(e.idx) if e.is_hero else 1.0)
	var kill_v: = 0.0
	if e.is_hero and res < ehp_e * 0.95 and dmg + res >= ehp_e:
		kill_v = (threat * 0.6 + 220.0) * hit_p

	var impact: = a.cast_time + (u.pos.distance_to(e.pos) / maxf(50.0, a.speed) if a.delivery == "projectile" else 0.0)
	var claims: Dictionary = plan.get("cc_claims", {})
	var claim_rem: = float(claims.get(e.idx, 0.0)) - sim.time
	var ccr: = e.hard_cc_remaining()
	if cfg.chain > 0.5 and e.is_hero and dmg > 0.0:
		if e.has_status("sleep") and not (a.char_id == "hermes" and a.slot == 3) and kill_v <= 0.0:

			dmg_v *= 0.75
		elif ccr >= impact + 0.05 or claim_rem >= impact + 0.1:
			dmg_v *= 1.15
	if e.is_hero:
		if cfg.peel2 > 0.5 and (plan.get("peel_threats", {}) as Dictionary).has(e.idx):
			dmg_v *= 1.12
		if int(plan.get("punish", -1)) == e.idx:
			dmg_v *= 1.2
		if cfg.tmult > 0.5:
			dmg_v *= Doctrine.target_mult(self, u, e)
	var cc: = KitModel.cc_total(ev)
	if immune or e.has_status("unstoppable"):
		cc = 0.0
	var cc_v: = 0.0
	if cc > 0.0:
		var overlap: = ccr
		if cfg.chain > 0.5:

			overlap = maxf(0.0, maxf(ccr, claim_rem) - impact)
		var fresh: = maxf(0.0, cc - overlap)
		cc_v = fresh * (float(pr.get("dps", 60.0)) * 1.1 + float(pr.get("burst", 80.0)) * 0.25 + 40.0) * hit_p
		if cfg.chain > 0.5 and overlap <= 0.05 and maxf(ccr, claim_rem) > 0.0:
			cc_v *= 1.2
		if cfg.peel2 > 0.5 and (plan.get("peel_threats", {}) as Dictionary).has(e.idx):
			cc_v *= 1.0 + 0.5 * float(plan.get("k_peel", 1.0))
		if not e.casting.is_empty() and ("stun" in ev.cc or "silence" in ev.cc or "airborne" in ev.cc or "suppression" in ev.cc or "sleep" in ev.cc or "charm" in ev.cc):
			cc_v += 70.0 * hit_p

		var follow: = 0.0
		for a2: BUnit in ctx.allies:
			if a2.pos.distance_to(e.pos) < float(aprof.get(a2.idx, {}).get("reach", 200.0)):
				follow += float(aprof.get(a2.idx, {}).get("dps", 40.0))
		cc_v += follow * fresh * 0.45 * hit_p
	# X4: silence denies the casts the target is expected to make while it
	# lasts, not only an interrupt of a cast already in progress. The gag's own
	# readiness valuation lives in _special_enemy.
	var silence: float = KitModel.silence_total(ev)
	if silence > 0.0 and e.is_hero and not immune and not e.has_status("silence"):
		if a.action != "gag":
			var readiness: float = 0.0
			for slot in e.def.abilities.size():
				readiness += intel.ready_prob(e, slot)
			cc_v += readiness * 16.0 * clampf(silence / 1.2, 0.5, 1.5) * hit_p
		if not e.casting.is_empty():
			cc_v += 40.0 * hit_p
	var slow_v: = float(ev.slow) * float(ev.slow_dur) * 25.0 * hit_p
	var amp_v: = float(ev.amp) * 380.0 * hit_p
	if e.kind == "fuel_tank":
		dmg_v += WarMachineTactics.tank_hit_value(self, e, dmg)
	if guard_k < 1.0:
		cc_v *= guard_k
		slow_v *= guard_k
		amp_v *= guard_k
	return {"value": dmg_v + kill_v + cc_v + slow_v + amp_v, "dmg": dmg, "kill": kill_v, "cc": cc_v, "ev": ev}



func _ew(idx: int) -> float:
	if cfg.ew < 0.5:
		return 1.0
	if not eprof.has(idx):
		return 0.5
	return clampf(float(eprof[idx].worth) / maxf(0.005, float(plan.get("ew_mean", 0.08))), 0.5, 1.9)


func _hit_prob(u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, aim: Vector2, delay_extra: float = 0.0) -> float:
	if a.delivery == "direct" or a.homing:
		var p: = 0.97 if a.delivery == "direct" else 0.92
		if e.has_status("projectile_guard") and a.delivery == "projectile":
			p *= 0.4
		return p
	var dist: = u.pos.distance_to(aim)
	var travel: = dist / maxf(50.0, a.speed) if a.delivery == "projectile" else 0.0
	var t: = a.cast_time + travel + delay_extra
	var cc: = e.movement_lock_remaining()
	if cc >= t - 0.05:
		return 0.96
	var skill: = 0.35 + 0.65 * e.dodge_rate()
	if e.movement_samples >= 6:
		skill *= 0.85 + e.turn_rate * 0.6
	var react: = 0.22
	var move_t: = maxf(0.0, t - react - cc)
	var reach: = e.ms() * move_t * skill
	var w: = a.width * 0.5 + e.radius
	if a.delivery == "area" or a.target == "position":
		w = maxf(a.radius, 20.0)
	elif a.delivery == "cone":
		w = maxf(40.0, a.range * sin(a.angle * 0.5))
	if reach <= 1.0:
		return 0.95
	var p2: = clampf(w / (reach + w * 0.6), 0.05, 0.95)
	if e.has_status("projectile_guard") and a.delivery == "projectile":
		p2 *= 0.45
	return p2


func lead_point(from: Vector2, e: TeamIntel.EnemyBelief, speed: float, cast: float, lead: float = 1.0, extra_delay: float = 0.0) -> Vector2:
	var p0: = e.pos
	var v: = e.vel * lead
	if e.movement_samples >= 8:
		v *= 1.0 - clampf(e.turn_rate * 0.8, 0.0, 0.35)
	if e.movement_lock_remaining() > cast + 0.2:
		v = Vector2.ZERO
	var t: = cast + extra_delay + (p0.distance_to(from) / maxf(50.0, speed) if speed > 0.0 else 0.0)
	var p: = p0
	for _k in 3:
		p = p0 + v * t
		t = cast + extra_delay + (p.distance_to(from) / maxf(50.0, speed) if speed > 0.0 else 0.0)
	if e.movement_samples >= 8 and e.movement_lock_remaining() <= cast:
		var radial: Vector2 = (from - p0).normalized()
		p += Vector2(-radial.y, radial.x) * e.strafe_bias * minf(16.0, t * 20.0)
	return sim.arena.resolve_circle(p, e.radius)


func _approach_factor(_u: BUnit, dist: float, need: float, ctx: Dictionary) -> float:
	if dist <= need:
		return 1.0
	var t: = (dist - need) / maxf(30.0, float(ctx.ms))
	return exp( - t / 1.1) if t < 2.5 else 0.0


# Generic ability geometry, cached per ability id (audit D5: no per-candidate
# lambdas). landing: where a move_self effect leaves the caster relative to its
# enemy target ("at" beside it, "behind" it, "dash" a fixed distance toward it).
func _ability_flags(a: Defs.AbilityDef) -> Dictionary:
	var cached: Dictionary = _ability_flag_cache.get(a.id, {})
	if not cached.is_empty():
		return cached
	var f: Dictionary = {"move_self": false, "recoil": false, "landing": "", "land_dist": 0.0}
	for fx in a.effects:
		if str(fx.get("type", "")) != "move_self":
			continue
		f.move_self = true
		match str(fx.get("mode", "")):
			"recoil":
				f.recoil = true
			"blink":
				f.landing = "behind" if bool(fx.get("behindTarget", false)) else "at"
				f.land_dist = float(fx.get("distance", 28.0))
			"dashToImpact":
				f.landing = "at"
			"dash":
				f.landing = "dash"
				f.land_dist = float(fx.get("distance", 100.0))
	_ability_flag_cache[a.id] = f
	return f


# Mirrors the "explode" projectile option of kits.gd: which projectiles burst
# in an area where they stop.
static func _explodes_on_impact(a: Defs.AbilityDef) -> bool:
	return a.target in ["position", "position_ally"] or bool(a.flag("originConeImpact", false)) or bool(a.flag("originCoins", false)) \
		or bool(a.flag("originScaledProjectile", false)) or a.char_id == "nitro"


# X3/X2: the first visible enemy body a delivery travelling from `from` to `to`
# touches before `target` (projectiles and contact dashes stop at the first
# body), or null when the intended target is reached first. Team knowledge
# only: visible heroes and visible summons/structures.
func _first_contact(from: Vector2, to: Vector2, pad: float, target: TeamIntel.EnemyBelief, ctx: Dictionary) -> TeamIntel.EnemyBelief:
	var limit: float = Arena.seg_circle_t(from, to, target.pos, target.radius + pad)
	if limit < 0.0:
		limit = 1.0
	var first: TeamIntel.EnemyBelief = null
	for b in ctx.targets:
		var o: TeamIntel.EnemyBelief = b
		if o == target or o.has_status("untargetable"):
			continue
		var t: float = Arena.seg_circle_t(from, to, o.pos, o.radius + pad)
		if t >= 0.0 and t < limit - 0.0001:
			limit = t
			first = o
	return first


# X5: where the caster ends up after a gap-closing ability, for the danger
# delta. INF when the ability does not move the caster onto the target.
func _landing_point(u: BUnit, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, aim: Vector2, r: float) -> Vector2:
	var dir: Vector2 = (aim - u.pos).normalized() if aim.distance_squared_to(u.pos) > 1.0 else u.facing
	if a.action == "contactDash":
		var contact: float = clampf(u.pos.distance_to(e.pos) - r - e.radius, 0.0, float(a.flag("originDistance", a.range)))
		return sim.arena.resolve_circle(u.pos + dir * contact, r)
	var f: Dictionary = _ability_flags(a)
	match str(f.landing):
		"behind":
			var away: Vector2 = (e.pos - u.pos).normalized() if e.pos.distance_squared_to(u.pos) > 1.0 else dir
			return sim.arena.resolve_circle(e.pos + away * (float(f.land_dist) + e.radius), r)
		"at":
			return sim.arena.resolve_circle(e.pos - dir * (r + e.radius), r)
		"dash":
			return sim.arena.resolve_circle(u.pos + dir * minf(float(f.land_dist), maxf(0.0, u.pos.distance_to(e.pos) - r - e.radius)), r)
	return Vector2.INF


# X8: the per-ability "ai" dictionaries (defs.gd) carry designer hints
# intent/weight/cluster/survival/combo. Only `cluster` is used, as the weight
# of extra enemies caught by an enemy-target projectile that bursts on impact
# (pierce uses _line_bonus). Cones are valued per victim once, in
# _special_enemy (line of sight and each victim's own hit chance; whip keeps
# its own secondary model there): review 1.5.3 found swordsman S2 and plague
# S1 counting every extra enemy twice when this bonus also covered cones.
# `weight` is deliberately ignored: a flat per-ability multiplier (0.9-1.8)
# would shift every hero's skill use against basics and movement, and values
# here are already computed from the real effects. intent/survival/combo are
# derived from effects and plan state instead.
func _cluster_bonus(u: BUnit, a: Defs.AbilityDef, aim: Vector2, primary: TeamIntel.EnemyBelief, ctx: Dictionary) -> float:
	var w: float = float(a.ai.get("cluster", 0.0))
	if w <= 0.0 or a.delivery == "cone" or a.pierce > 0:
		return 0.0
	if not (a.delivery == "projectile" and _explodes_on_impact(a)):
		return 0.0
	var total: float = 0.0
	for b in ctx.targets:
		var o: TeamIntel.EnemyBelief = b
		if o == primary or not o.is_hero:
			continue
		var p2: Vector2 = lead_point(u.pos, o, 0.0, a.cast_time, 0.8)
		if p2.distance_to(aim) > a.radius + o.radius:
			continue
		total += float(_enemy_value(u, a, o, ctx, 0.6).value)
	return total * w


func _enemy_target_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	var r: float = ctx.r
	if str(a.condition.get("targetStatus", "")) == "control":
		_controlled_target_candidates(u, i, a, ctx, out)
		return
	var projectile: bool = a.delivery == "projectile"
	var skillshot: bool = projectile and not a.homing
	var dash: bool = a.action == "contactDash"
	var proj_r: float = maxf(3.0, a.width * 0.5)
	var flags: Dictionary = _ability_flags(a)
	# D1/X1: unit-targeted orders only on enemies this hero observes itself.
	for b: TeamIntel.EnemyBelief in ctx.strike:
		var e: TeamIntel.EnemyBelief = b
		if not e.is_hero and not (a.effects.size() > 0 and _has_damage(a)):
			continue
		if a.action == "chamber" and not e.is_hero:
			continue
		var tu: = sim.u_at(e.idx)
		if tu == null or not sim.check_condition(u, tu, a.condition):
			continue
		if not sim.target_legal(u, a, tu):
			continue
		var dist: = u.pos.distance_to(e.pos)
		var rng_: = a.range
		if dash:
			rng_ = float(a.flag("originDistance", a.range))
		var need: = rng_ + r
		# gap: distance still to close before the delivery can land. The order is
		# kept so the hero approaches, but the aim is no longer clamped to the
		# maximum range, so the executor waits instead of firing short
		# (telemetry #3).
		var gap: = 0.0
		var aim: = e.pos
		var lead_t: = 0.0
		if skillshot:
			aim = lead_point(u.pos, e, a.speed, a.cast_time, 1.0 - 0.45 * e.dodge_rate())
			gap = maxf(0.0, maxf(u.pos.distance_to(aim) - (a.range + r + e.radius * 0.5), dist - (a.range + r + e.radius + 8.0)))
		elif a.delivery in ["cone", "line"]:
			aim = lead_point(u.pos, e, 0.0, a.cast_time, 0.8)
		elif dash:
			# X2: predicted contact point and the body-wide corridor the engine
			# sweeps at full radius (kits.update_motion).
			lead_t = a.cast_time + minf(rng_, dist) / maxf(50.0, a.speed)
			aim = lead_point(u.pos, e, 0.0, lead_t, 1.0)
			if sim.arena.segment_blocked(u.pos, aim, r, Arena.MASK_UNITS):
				continue
			var contact: float = rng_ + r + e.radius - 6.0
			gap = maxf(0.0, maxf(u.pos.distance_to(aim) - contact, dist - contact - 8.0))
		var eff_dist: = dist
		if skillshot or dash:
			eff_dist = need + gap if gap > 0.0 else minf(dist, need)
		var appr: = _approach_factor(u, eff_dist, need, ctx)
		if appr <= 0.02:
			continue
		var hp: = _hit_prob(u, a, e, aim)
		# X3: a projectile ends on the first wall or enemy body on its path and a
		# contact dash on the first enemy body; homing shots are no exception.
		var victim: TeamIntel.EnemyBelief = e
		if projectile and gap <= 0.0:
			var end: Vector2 = e.pos if a.homing else aim
			var start: Vector2 = u.pos + (end - u.pos).normalized() * minf(r + 4.0, u.pos.distance_to(end))
			if a.bounces == 0 and sim.arena.segment_blocked(start, end, proj_r, Arena.MASK_PROJECTILES):
				continue
			if a.pierce == 0:
				var first: TeamIntel.EnemyBelief = _first_contact(start, end, proj_r, e, ctx)
				if first != null:
					victim = first
		elif dash and gap <= 0.0:
			var first_body: TeamIntel.EnemyBelief = _first_contact(u.pos, aim, r, e, ctx)
			if first_body != null:
				victim = first_body
		var ev: Dictionary
		var v: float
		if victim == e:
			ev = _enemy_value(u, a, e, ctx, hp)
			v = float(ev.value)
			if a.pierce > 0 and projectile:
				v += _line_bonus(u, a, aim, e, ctx)
			var special: float = _special_enemy(u, i, a, e, aim, ctx, ev)
			if special > 0.0:
				# D6: flat bonuses follow the hit chance (relative to the
				# delivery's nominal rate) like the rest of the value does.
				special *= clampf(hp / maxf(0.05, KitModel.delivery_hit(a)), 0.0, 1.0)
			v += special
			v += _cluster_bonus(u, a, aim, e, ctx)
		else:
			ev = _enemy_value(u, a, victim, ctx, 0.9)
			v = float(ev.value)
		v *= appr
		# X5: price the danger increase at the real landing point, only when the
		# landing is worse than standing here.
		var land: Vector2 = _landing_point(u, a, victim, aim, r) if (dash or str(flags.landing) != "") else Vector2.INF
		if land.is_finite():
			v -= maxf(0.0, danger_at(u, land, 1.0) - float(ctx.danger)) * float(ctx.risk_w) * 0.6
		elif bool(flags.recoil):
			var back: = u.pos + (u.pos - e.pos).normalized() * 110.0
			v += (float(ctx.danger) - danger_at(u, back, 1.0)) * float(ctx.risk_w) * 0.6
		v -= _cost(u, a, ctx)
		var label: String = "%s → %s" % [a.name, e.def.name]
		if victim != e:
			label += " (선행 피격: %s)" % victim.def.name
		elif gap > 0.0:
			label += " (접근)"
		var cmd: Dictionary = {"kind": "ability", "index": i, "ability_id": a.id, "target": e.idx, "pos": aim, "need": need}
		if skillshot:
			# steer and refine_aim re-predict from the belief with the same model.
			cmd["lead"] = 1.0 - 0.45 * e.dodge_rate()
			cmd["speed"] = a.speed
			cmd["cast"] = a.cast_time
		elif dash:
			cmd["lead"] = 1.0
			cmd["speed"] = 0.0
			cmd["cast"] = lead_t
		if a.action == "interrogate":
			# Visible enemies' health and position are refreshed by observation
			# every tick; only cooldowns are new information.
			cmd["extra"] = {"info_kind": "cooldowns"}
		out.append({"value": v, "key": "a%d:%d" % [i, e.idx], "label": label,
			"parts": {"피해": ev.dmg, "처치": ev.kill, "제어": ev.cc, "명중": hp}, "cmd": cmd})



func _controlled_target_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	for k in intel.enemies:
		var e: TeamIntel.EnemyBelief = intel.enemies[k]
		if e.dead or not e.controlled_by_us:
			continue
		var tu: = sim.u_at(e.idx)
		if tu == null or not tu.alive or not sim.check_condition(u, tu, a.condition) or not sim.target_legal(u, a, tu):
			continue
		var dist: = u.pos.distance_to(tu.pos)
		var appr: = _approach_factor(u, dist, a.range + float(ctx.r), ctx)
		if appr <= 0.02:
			continue
		# Allies' pledged damage cannot land on a unit that fights for us now:
		# a kill estimate counting it fired too early (audit hive S4).
		var pledged = reserved.get(e.idx, null)
		reserved.erase(e.idx)
		var ev: = _enemy_value(u, a, e, ctx, 0.98)
		if pledged != null:
			reserved[e.idx] = pledged
		var rem: = 0.0
		for st in tu.statuses:
			if st.type == &"control":
				rem = maxf(rem, st.end - sim.time)
		# While control lasts the unit hits its own team, so early self-harm
		# wastes that; once the remainder only covers the wind-up plus one
		# decision, firing is mandatory or the control expires unused.
		var must: float = a.cast_time + 0.2 + 0.35
		var v: = float(ev.value)
		if float(ev.kill) > 0.0:
			v += 150.0
		elif rem <= must:
			v += 240.0
		elif rem <= 1.3:
			v += 60.0
		else:
			# Each remaining second of control is the unit's damage turned on
			# its own team plus the damage it does not deal to us.
			v -= (rem - 1.3) * (float(eprof.get(e.idx, {}).get("dps", 60.0)) * 2.0 + 60.0)
		v *= appr
		out.append({"value": v, "key": "a%d:%d" % [i, e.idx], "label": "%s → %s" % [a.name, e.def.name],
			"parts": {"피해": ev.dmg, "조종 잔여": rem}, "gate_exempt": true, "objective_exempt": true,
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "target": e.idx, "pos": tu.pos, "need": a.range + float(ctx.r)}})



func _parry_candidate(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	var r: float = ctx.r
	var best_v: = 0.0
	var best_p: = Vector2.ZERO
	for pj in intel.projectiles:
		var v: Vector2 = pj.vel
		var sp: = v.length()
		if sp < 1.0:
			continue
		if pj.homing and int(pj.target) != u.idx:
			continue
		var ppos: Vector2 = pj.pos
		var rel: = u.pos - ppos
		var along: = rel.dot(v) / sp
		if along <= 0.0:
			continue
		var closest: = ppos + v / sp * along
		if closest.distance_to(u.pos) > 70.0 + r * 0.5:
			continue

		var t_enter: = maxf(0.0, along - 76.0 - r) / sp
		if t_enter > 0.28 or along / sp < 0.05:
			continue
		var val: = float(pj.dmg) * 0.65 + (70.0 if pj.cc else 0.0)
		if val > best_v:
			best_v = val
			best_p = ppos + v * minf(0.1, along / sp)
	if best_v > 20.0:
		out.append({"value": best_v + 25.0, "key": "parry", "label": "수비 스윙 (투사체 반사)", "parts": {"반사": best_v}, 
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": best_p, "need": 0.0}, "notes": ["교리: 배트 반사"]})


func _has_damage(a: Defs.AbilityDef) -> bool:
	for f in a.effects:
		var ty: = str(f.get("type", ""))
		if ty in ["damage", "dot"]:
			return true
	return false


func _line_bonus(u: BUnit, a: Defs.AbilityDef, aim: Vector2, primary: TeamIntel.EnemyBelief, ctx: Dictionary) -> float:
	var dir: = (aim - u.pos).normalized()
	var end: = u.pos + dir * (a.range + 40.0)
	var bonus: = 0.0
	for b: TeamIntel.EnemyBelief in ctx.targets:
		var e: TeamIntel.EnemyBelief = b
		if e == primary:
			continue
		if Geometry2D.get_closest_point_to_segment(e.pos, u.pos, end).distance_to(e.pos) <= a.width * 0.5 + e.radius:
			bonus += float(_enemy_value(u, a, e, ctx, 0.6).value) * 0.8
	return bonus


func _cost(u: BUnit, a: Defs.AbilityDef, ctx: Dictionary) -> float:
	var c: = 6.0
	for f in a.effects:
		if str(f.get("type", "")) == "self_damage":
			c += u.hp * float(f.ratio) * (0.6 + 1.2 * (1.0 - float(ctx.hpr)))
	return c


func _special_enemy(u: BUnit, _i: int, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief, _aim: Vector2, ctx: Dictionary, ev: Dictionary) -> float:
	var v: = 0.0
	var dist: = u.pos.distance_to(e.pos)
	match a.action:
		"whip":
			var direction: Vector2 = (_aim - u.pos).normalized()
			if dist >= a.range * 0.75 and dist <= a.range + e.radius:
				v += (28.0 + 0.3 * float(ctx.st.ad)) * 100.0 / (100.0 + e.def.stat("armor")) * 0.75
			for other in ctx.targets:
				var secondary: TeamIntel.EnemyBelief = other
				if secondary.idx == e.idx:
					continue
				var projected: Vector2 = lead_point(u.pos, secondary, 0.0, a.cast_time, 0.8)
				var offset: Vector2 = projected - u.pos
				if offset.length() <= a.range + secondary.radius and absf(direction.angle_to(offset)) <= a.angle * 0.5:
					v += 32.0 * _hit_prob(u, a, secondary, projected)
		"prison":
			if not e.has_status("imprisoned"):
				v += 65.0 + minf(130.0, Doctrine.team_window(self, u, e, 2.0) * 0.4)
		"gag":
			var readiness: float = 0.0
			for slot in e.def.abilities.size():
				readiness += intel.ready_prob(e, slot)
			v += readiness * 16.0 + (55.0 if not e.casting.is_empty() else 0.0)
		"interrogate":
			var unknown: float = 0.0
			for slot in e.cd_last.size():
				if e.cd_last[slot] < -100.0:
					unknown += 1.0
			v += 30.0 + unknown * 9.0 + float(plan.get("uncertainty", 0.0)) * 35.0
			for item in intel.visible_enemies():
				var censor: TeamIntel.EnemyBelief = item
				if censor.def.id == "politician" and censor.has_status("contemplation"):
					v -= 130.0
		"chamber":

			var pr: Dictionary = eprof.get(e.idx, {})
			v += float(pr.get("threat", 300.0)) * 0.9 + 260.0
			if float(ctx.hpr) < 0.35:
				v -= 120.0
		"swapBox":

			var ally_near: = 0
			for a2: BUnit in ctx.allies:
				if a2.pos.distance_to(u.pos) < 260.0:
					ally_near += 1
			v += 60.0 * ally_near - danger_at(u, e.pos, 1.2) * float(ctx.risk_w) * 0.6
		"consumeConfusion":
			var tu: = sim.u_at(e.idx)
			var os: = sim.owned_status(tu, &"confusion", u.idx) if tu else null
			var n: = os.stacks if os else 0
			if n < 3 and float(ev.kill) <= 0.0:
				v -= 120.0
		"cripple":
			pass
	# V1.5.3: a cone hits every enemy inside it (swordsman S2, plague S1);
	# the base value only counts the aimed target (audit swordsman S2).
	if a.delivery == "cone" and a.action != "whip":
		var cdir: Vector2 = (_aim - u.pos).normalized() if _aim.distance_squared_to(u.pos) > 1.0 else (e.pos - u.pos).normalized()
		for other in ctx.targets:
			var sec: TeamIntel.EnemyBelief = other
			if sec.idx == e.idx:
				continue
			var sp: Vector2 = lead_point(u.pos, sec, 0.0, a.cast_time, 0.8)
			var off: Vector2 = sp - u.pos
			var od: float = off.length()
			if od < 1.0 or od > a.range + sec.radius:
				continue
			if absf(cdir.angle_to(off)) > a.angle * 0.5 + sec.radius / od:
				continue
			if not sim.arena.line_of_sight(u.pos, sp, 2.0):
				continue
			v += float(_enemy_value(u, a, sec, ctx, _hit_prob(u, a, sec, sp)).value) * 0.8
	if a.char_id == "fisherman" and a.slot == 1:

		var near_allies: = 0.0
		for a2: BUnit in ctx.allies:
			if a2.pos.distance_to(u.pos) < 280.0:
				near_allies += float(aprof.get(a2.idx, {}).get("dps", 40.0))
		# D6: the follow-up bonus only exists if the hook lands. The caller
		# scales every special bonus by the hit chance once (review 1.5.3: this
		# used to scale it a second time, ~(p/0.6)^2); only a blocked line is
		# priced here.
		var hook_line: float = 1.0 if sim.arena.line_of_sight(u.pos, _aim, maxf(2.0, a.width * 0.13)) else 0.15
		v += (near_allies * 1.2 + (80.0 if e.def.preferred_range > 150.0 else 20.0)) * hook_line
	if a.char_id == "joker" and a.slot == 1 and a.count > 1:
		# Four knives in a 32° fan: at close range several hit the same
		# target, each one damage + one confusion (audit joker S1).
		var lateral: float = e.radius + a.width * 0.5
		var knives: int = 0
		for kk in a.count:
			if absf(dist * sin((kk - (a.count - 1) * 0.5) * a.spread)) <= lateral:
				knives += 1
		if knives > 1:
			v += (float(ev.dmg) * _ew(e.idx) + 8.0) * (knives - 1)
	if a.homing and a.delivery == "projectile" and a.slot == 4 and (a.char_id == "joker" or a.char_id == "dimensionalist"):
		# Homing shots still die on walls and on the first enemy body in the
		# way (projectiles.gd); the blade also burns 30 shards (audit X2).
		var costly: bool = a.char_id == "dimensionalist"
		if not sim.arena.line_of_sight(u.pos, e.pos, minf(8.0, a.width * 0.5)):
			v -= maxf(0.0, float(ev.value)) + (90.0 if costly else 60.0)
		else:
			var blocker: TeamIntel.EnemyBelief = Doctrine.path_blocker(self, u, e, a.width * 0.5)
			if blocker:
				v -= maxf(0.0, float(ev.value)) * (0.5 if blocker.is_hero else 0.9) + (40.0 if costly else 15.0)
	if a.char_id == "archer" and a.slot == 3 and e.hp / maxf(1.0, e.max_hp) > 0.3:
		v -= 30.0
	if a.char_id == "sniper" and a.slot == 1 and float(ctx.danger) > float(ctx.ehp) * 0.3:
		v -= 80.0
	if a.char_id == "hermes" and a.slot == 2:

		if u.cooldowns[2] <= sim.time + 0.3:
			v += 90.0
	if a.char_id == "hive_mind" and a.slot == 3:
		var pr2: Dictionary = eprof.get(e.idx, {})
		v += float(pr2.get("dps", 60.0)) * 3.0 * 1.5 + 120.0
	if a.char_id == "swordsman" and a.slot == 3 and u.cooldowns[3] <= sim.time + 1.0 and cfg.doct < 0.5:
		v += 60.0
	if a.char_id == "werewolf" and a.slot == 4 and str(plan.stance) == "DISENGAGE":
		v -= 60.0
	if a.char_id == "torquemada" and a.slot == TorquemadaTactics.VERDICT:
		v += TorquemadaTactics.verdict_bonus(self, u, e, ctx)
	if a.char_id == "joker" and a.slot == 2 and dist < 90.0:
		v -= 40.0
	if a.char_id == "hades":
		v += HadesTactics.special_enemy(self, u, a, e, _aim, ctx) # V2 hades S2 heal block
	if a.char_id == "achilles":
		v += AchillesTactics.special_enemy(self, u, a, e, _aim, ctx, ev)
	return v




func _cluster_points(radius_: float, ctx: Dictionary) -> Array:
	var pts: Array = []
	var ts: Array = ctx.targets
	for b in ts:
		var e: TeamIntel.EnemyBelief = b
		if not e.is_hero:
			continue
		pts.append(e.pos)
		for b2 in ts:
			var e2: TeamIntel.EnemyBelief = b2
			if e2 != e and e2.is_hero and e.pos.distance_to(e2.pos) < radius_ * 2.0:
				pts.append((e.pos + e2.pos) * 0.5)
	return pts


func _area_value(u: BUnit, a: Defs.AbilityDef, center: Vector2, radius_: float, ctx: Dictionary, delay: float) -> Dictionary:
	var total: = 0.0
	var hits: = 0
	for b: TeamIntel.EnemyBelief in ctx.targets:
		var e: TeamIntel.EnemyBelief = b
		var pred: = lead_point(center, e, 0.0, a.cast_time, 0.8, delay)
		var d: = pred.distance_to(center)
		if d > radius_ + e.radius + 30.0:
			continue
		var hp: = 0.9
		var move_t: = maxf(0.0, a.cast_time + delay - 0.22 - e.hard_cc_remaining())
		var esc: = e.ms() * move_t * (0.35 + 0.65 * e.dodge_rate())
		var margin: = radius_ + e.radius - d
		if margin <= 0.0:
			hp = 0.15
		elif esc > margin:
			hp = clampf(margin / esc, 0.1, 0.9)
		total += float(_enemy_value(u, a, e, ctx, hp).value)
		hits += 1
	return {"value": total, "hits": hits}


func _position_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	var r: float = ctx.r
	match a.action:
		"pointBlink":
			_escape_candidate(u, i, a, ctx, out, a.range)
			return
		"detonate":
			for tw in sim.kits.owned_entities(u, "turret"):
				if tw.pos.distance_to(u.pos) > 420.0:
					continue
				var mult: = 1.0 + 0.25 * (tw.level - 1)
				var val: = 0.0
				for b: TeamIntel.EnemyBelief in ctx.targets:
					var e: TeamIntel.EnemyBelief = b
					if e.is_hero and e.pos.distance_to(tw.pos) <= 110.0 + e.radius:
						var est: Dictionary = KitModel._enemy_base(e.def).st
						var dmg: = (90.0 + 0.65 * float(ctx.st.ap) + 0.4 * float(ctx.st.ad)) * mult * 100.0 / (100.0 + float(est.mr))
						val += dmg * (1.35 if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == e.idx else 1.0)
						if dmg >= e.hp + e.shield:
							val += 250.0
				val -= 40.0 + 25.0 * tw.level
				if val > 0.0:
					out.append({"value": val, "key": "a%d:%d" % [i, tw.idx], "label": "%s (포탑 %d단계)" % [a.name, tw.level], 
						"parts": {"피해": val}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": tw.pos, "need": 420.0}})
			return
	if a.action == "" and a.char_id == "pirate" and a.slot == 4:
		_broadside_candidates(u, i, a, ctx, out)
		return
	var delay: = 0.0
	var radius_: = a.radius
	for f in a.effects:
		if str(f.get("type", "")) == "delayed_area":
			delay = float(f.get("delay", 0.5))
			radius_ = float(f.get("radius", radius_))
	if a.delivery == "projectile":
		radius_ = maxf(a.radius * (sim.radius_scale(u) if a.flag("originScaledProjectile", false) else 1.0), 30.0)
	var centers: = _cluster_points(radius_, ctx)
	for c in centers:
		var center: Vector2 = c
		var dist: = u.pos.distance_to(center)
		var appr: = _approach_factor(u, dist, a.range + r, ctx)
		if appr <= 0.02:
			continue
		var aim: = center
		if dist > a.range + r:
			aim = u.pos + (center - u.pos).normalized() * (a.range + r - 2.0)
		# X3: a thrown blast detonates on the first wall or enemy body it meets;
		# value the blast where it will actually go off.
		var impact: Vector2 = aim
		if a.delivery == "projectile":
			impact = _projectile_impact(u, a, aim, ctx)
			delay = u.pos.distance_to(impact) / maxf(50.0, a.speed)
		var av: = _area_value(u, a, impact, radius_, ctx, delay)
		if int(av.hits) == 0:
			continue
		var v: = float(av.value) * appr - _cost(u, a, ctx)
		out.append({"value": v, "key": "a%d:%d:%d" % [i, int(center.x / 20), int(center.y / 20)], "label": "%s (%d명)" % [a.name, av.hits], 
			"parts": {"범위": av.value}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": aim, "need": a.range + r}})


# Pirate S4 (heroes-A follow-up 4): the broadside goes off at the first body
# or wall on its line and fans a forward cone from there, so it is aimed at
# enemy bodies and valued with the cone model (Doctrine.cone_blast), not as a
# circle around a cluster centre. The recoil carries the pirate 120 back.
func _broadside_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var r: float = ctx.r
	# Aims: every enemy body (lead point), plus the cluster centres the circle
	# model proposed (kept so a "between two enemies" aim is visibly worth 0).
	var aims: Array = []
	for b in ctx.targets:
		var e: TeamIntel.EnemyBelief = b
		if not e.is_hero or e.has_status("untargetable"):
			continue
		aims.append([lead_point(u.pos, e, a.speed, a.cast_time, 0.7), "e%d" % e.idx, false])
	for c0 in _cluster_points(maxf(a.radius, 30.0), ctx):
		var cp: Vector2 = c0
		var dup: bool = false
		for row in aims:
			if (row[0] as Vector2).distance_to(cp) < 12.0:
				dup = true
				break
		if not dup:
			aims.append([cp, "%d:%d" % [int(cp.x / 20), int(cp.y / 20)], true])
	for row2 in aims:
		var aim: Vector2 = row2[0]
		var dist: float = u.pos.distance_to(aim)
		var appr: float = _approach_factor(u, dist, a.range + r, ctx)
		if appr <= 0.02:
			continue
		if dist > a.range + r:
			aim = u.pos + (aim - u.pos).normalized() * (a.range + r - 2.0)
		var cb: Dictionary = Doctrine.cone_blast(self, u, a, aim, ctx)
		if int(cb.hits) == 0 and not bool(row2[2]):
			continue
		var v: float = float(cb.value) * appr - _cost(u, a, ctx)
		var back: Vector2 = (u.pos - aim).normalized() if u.pos.distance_squared_to(aim) > 1.0 else -u.facing
		v += (float(ctx.danger) - danger_at(u, u.pos + back * 120.0, 1.0)) * float(ctx.risk_w) * 0.6
		if int(cb.hits) == 0:
			v = -_cost(u, a, ctx) - 10.0
		out.append({"value": v, "key": "a%d:%s" % [i, str(row2[1])], "label": "%s (%d명)" % [a.name, int(cb.hits)],
			"parts": {"범위": float(cb.value), "부채꼴": int(cb.hits)}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": aim, "need": a.range + r}})


# Where a position-targeted projectile stops: first projectile-blocking wall,
# then the first visible enemy body on the remaining path, else the aim.
func _projectile_impact(u: BUnit, a: Defs.AbilityDef, aim: Vector2, ctx: Dictionary) -> Vector2:
	var delta: Vector2 = aim - u.pos
	var spawn_off: float = float(ctx.r) + 4.0
	if delta.length() <= spawn_off + 1.0:
		return aim
	var pr: float = maxf(3.0, a.width * 0.5) * (sim.radius_scale(u) if a.flag("originScaledProjectile", false) else 1.0)
	var start: Vector2 = u.pos + delta.normalized() * spawn_off
	var end: Vector2 = aim
	var wall: Dictionary = sim.arena.terrain_contact(start, end, pr, true)
	if not wall.is_empty():
		end = wall.point
	var best_t: float = 2.0
	for b in ctx.targets:
		var o: TeamIntel.EnemyBelief = b
		if o.has_status("untargetable"):
			continue
		var t: float = Arena.seg_circle_t(start, end, o.pos, o.radius + pr)
		if t >= 0.0 and t < best_t:
			best_t = t
	if best_t <= 1.0:
		end = start.lerp(end, best_t)
	return end


func _escape_candidate(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array, dist_: float) -> void :
	var danger: float = ctx.danger
	if danger < float(ctx.ehp) * 0.18 and float(ctx.hpr) > 0.5:
		return
	var best_p: = u.pos
	var best_d: = danger
	var away: = (u.pos - (plan.enemy_c as Vector2)).normalized()
	for k in 10:
		var ang: = away.angle() + (k - 4.5) * 0.45
		var p: = sim.arena.resolve_circle(u.pos + Vector2.from_angle(ang) * dist_, ctx.r)
		if not _v2_escape_safe(u, p, float(ctx.r)):
			continue
		var d: = danger_at(u, p, 1.2)
		if d < best_d:
			best_d = d
			best_p = p
	var gain: = (danger - best_d) * float(ctx.risk_w) * 1.2
	var ev: = KitModel.evaluate(a.effects, ctx.st, {})
	gain += float(ev.shield) * minf(1.0, danger / maxf(1.0, float(ctx.ehp)) * 2.0)
	if gain > 25.0 and _v2_escape_safe(u, best_p, float(ctx.r)):
		out.append({"value": gain, "key": "a%d:esc" % i, "label": "%s (탈출)" % a.name, "parts": {"위험 감소": danger - best_d}, 
			"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": best_p, "need": dist_ + ctx.r}})




func _self_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	if u.def.id == "hades" and HadesTactics.self_candidate(self, u, i, a, ctx, out):
		return # V2 hades S1 shade ambush / S3 harvest
	if a.char_id == "torquemada" and a.slot == TorquemadaTactics.EDICT:
		TorquemadaTactics.edict_candidates(self, u, i, a, ctx, out)
		return
	# V2 achilles S2-S4 (AchillesTactics).
	if a.char_id == "achilles" and AchillesTactics.self_candidates(self, u, i, a, ctx, out):
		return
	var st: Dictionary = ctx.st
	var danger: float = ctx.danger
	var targets: Array = ctx.targets
	var nearest: = INF
	var near_count: = 0
	for b in targets:
		var e: TeamIntel.EnemyBelief = b
		if not e.is_hero:
			continue
		var d: = u.pos.distance_to(e.pos)
		nearest = minf(nearest, d)
		if d < 260.0:
			near_count += 1
	var v: = 0.0
	var lbl: = a.name
	var cmd_pos: Vector2 = u.pos
	var fighting: = nearest < float(ctx.range) + 120.0 or nearest < 260.0
	var ev: = KitModel.evaluate(a.effects, st, {})
	match a.action:
		"cloak":
			if u.def.id == "hermes" and float(u.ks.get("cloak_until", 0.0)) > sim.time:

				var cnt: = 0
				for b in targets:
					var ce: TeamIntel.EnemyBelief = b
					if ce.is_hero and u.pos.distance_to(ce.pos) <= 90.0 + ce.radius and sim.arena.line_of_sight(u.pos, ce.pos, 1.0):
						cnt += 1
				v = cnt * 140.0 - 20.0
				lbl = "클라미스 재사용 (기절 %d)" % cnt
			else:
				v = danger * float(ctx.risk_w) * 0.9 if danger > float(ctx.ehp) * 0.25 else 0.0
				if ctx.focus and str(plan.stance) != "DISENGAGE" and u.pos.distance_to((ctx.focus as TeamIntel.EnemyBelief).pos) < 380.0:
					v += 110.0
		"wallRun":
			v = danger * float(ctx.risk_w) * 0.5 if danger > float(ctx.ehp) * 0.3 else 0.0
			if ctx.focus:
				var tang: = sim.wall_tangent(u.pos) * (-1.0 if sim.wall_tangent(u.pos).dot(u.facing) < 0.0 else 1.0)
				if tang.dot(((ctx.focus as TeamIntel.EnemyBelief).pos - u.pos).normalized()) > 0.6:
					v += 70.0
		"glide":
			# V1.5.3 (D10): the landing (radius 110) happens where the metatron
			# is after 1.2 s at +60% speed; plan on predicted positions and keep
			# the chosen target in brain memory for the in-flight steering point.
			var reach_g: float = float(ctx.ms) * 1.6 * 1.2 + 40.0
			var best_g: float = -INF
			var best_t: TeamIntel.EnemyBelief = null
			for b in targets:
				var ge: TeamIntel.EnemyBelief = b
				if not ge.is_hero:
					continue
				var landing: Vector2 = lead_point(u.pos, ge, 0.0, a.cast_time + 1.2, 0.8)
				if u.pos.distance_to(landing) > reach_g:
					continue
				# The glide walks (no flight over walls): a landing behind cover
				# is reached by a detour that the 1.2 s cannot cover.
				if sim.arena.segment_blocked(u.pos, landing, float(ctx.r), Arena.MASK_UNITS):
					continue
				var hits: = 0
				for b2 in targets:
					var he: TeamIntel.EnemyBelief = b2
					if he.is_hero and lead_point(landing, he, 0.0, a.cast_time + 1.2, 0.6).distance_to(landing) < 110.0 + he.radius - 8.0:
						hits += 1
				var gv: float = hits * 130.0 - danger_at(u, landing, 1.2) * float(ctx.risk_w) * 0.4
				if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == ge.idx:
					gv += 20.0
				if gv > best_g:
					best_g = gv
					best_t = ge
			if best_t:
				v = best_g
				var gm: Dictionary = mem.get(u.idx, {})
				gm["glide_target"] = best_t.idx
				mem[u.idx] = gm
		"rift":
			# V1.5.3: the rift stands 22 in front of the caster across its
			# aim; face it toward the combined incoming fire (engine takes the
			# direction from target_pos) and count only shots it can stop.
			var face: Vector2 = Vector2.ZERO
			for pj in intel.projectiles:
				var rel: Vector2 = u.pos - (pj.pos as Vector2)
				var sp: float = (pj.vel as Vector2).length()
				if sp < 1.0 or rel.length() > 360.0 or rel.length() / sp < a.cast_time + 0.03:
					continue
				if pj.homing:
					if int(pj.target) != u.idx:
						continue
				elif rel.dot(pj.vel) <= 0.0:
					continue
				else:
					var along: float = rel.dot(pj.vel) / sp
					if ((pj.pos as Vector2) + (pj.vel as Vector2) / sp * along).distance_to(u.pos) > float(pj.radius) + float(ctx.r) + 30.0:
						continue
				face += -rel.normalized() * float(pj.dmg)
			for tg in intel.telegraphs:
				if str(tg.shape) == "line" and _in_telegraph(u.pos, ctx.r + 40.0, tg):
					face += ((tg.from as Vector2) - u.pos).normalized() * float(tg.dmg)
			if face.length_squared() < 1.0:
				v = -1.0
			else:
				var fd: Vector2 = face.normalized()
				var center: Vector2 = u.pos + fd * (float(ctx.r) + 22.0)
				var tang2: Vector2 = Vector2(-fd.y, fd.x)
				var ra: Vector2 = center - tang2 * 80.0
				var rb: Vector2 = center + tang2 * 80.0
				var blocked: float = 0.0
				for pj2 in intel.projectiles:
					var sp2: float = (pj2.vel as Vector2).length()
					var rel2: Vector2 = u.pos - (pj2.pos as Vector2)
					if sp2 < 1.0 or rel2.length() > 360.0 or rel2.length() / sp2 < a.cast_time + 0.03:
						continue
					if pj2.homing and int(pj2.target) != u.idx:
						continue
					var tail: Vector2 = pj2.pos
					var head: Vector2 = (pj2.pos as Vector2) + ((u.pos - tail).normalized() * (rel2.length() + 20.0) if pj2.homing else (pj2.vel as Vector2) / sp2 * (rel2.length() + 20.0))
					if Geometry2D.segment_intersects_segment(tail, head, ra, rb) != null:
						blocked += float(pj2.dmg)
				for tg2 in intel.telegraphs:
					if str(tg2.shape) == "line" and _in_telegraph(u.pos, ctx.r + 40.0, tg2) and ((tg2.from as Vector2) - u.pos).normalized().dot(fd) > 0.5:
						blocked += float(tg2.dmg)
				v = blocked * 1.1 - 40.0
				for b in targets:
					var e: TeamIntel.EnemyBelief = b
					if e.is_hero and e.def.preferred_range > 150.0 and u.pos.distance_to(e.pos) < 450.0 and (e.pos - u.pos).normalized().dot(fd) > 0.3:
						v += 25.0
				cmd_pos = u.pos + fd * 60.0
				lbl = "%s (차단 %.0f)" % [a.name, blocked]
		"portalArming":
			# V1.5.3: armed portals move allied shots that actually cross an
			# entrance; value only lines whose exit still points at an enemy.
			var pair: Dictionary = {}
			for pp in sim.portal_pairs:
				if int(pp.source) == u.idx and float(pp.end) > sim.time + 1.0:
					pair = pp
			if pair.is_empty():
				v = -1.0
			else:
				var good: = 0
				var bad: = 0
				for x in [u] + (ctx.allies as Array):
					var shooter: BUnit = x
					if shooter.def.preferred_range <= 150.0:
						continue
					var sreach: float = float(aprof.get(shooter.idx, {}).get("reach", 250.0)) + 60.0
					# Our ally's own order names what it shoots; else the focus,
					# else the nearest enemy hero in its reach.
					var aimed: TeamIntel.EnemyBelief = null
					var ct: int = int(shooter.command.get("target", -1))
					if shooter.action and shooter.action.target_idx >= 0:
						ct = shooter.action.target_idx
					if ct >= 0 and intel.enemies.has(ct) and (intel.enemies[ct] as TeamIntel.EnemyBelief).visible:
						aimed = intel.enemies[ct]
					elif ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).visible and shooter.pos.distance_to((ctx.focus as TeamIntel.EnemyBelief).pos) < sreach:
						aimed = ctx.focus
					else:
						var ad: float = sreach
						for b in targets:
							var te: TeamIntel.EnemyBelief = b
							if te.is_hero and shooter.pos.distance_to(te.pos) < ad:
								ad = shooter.pos.distance_to(te.pos)
								aimed = te
					if aimed == null:
						continue
					var dirv: Vector2 = (aimed.pos - shooter.pos).normalized()
					for ends in [[pair.a, pair.b], [pair.b, pair.a]]:
						var entry: Vector2 = ends[0]
						var exit_p: Vector2 = ends[1]
						var cp: Vector2 = Geometry2D.get_closest_point_to_segment(entry, shooter.pos, aimed.pos)
						if cp.distance_to(entry) > float(pair.radius) + 10.0 + 6.0:
							continue
						var left: float = sreach + 40.0 - shooter.pos.distance_to(entry)
						var onward: bool = false
						for b in targets:
							var oe: TeamIntel.EnemyBelief = b
							if not oe.is_hero:
								continue
							var along2: float = (oe.pos - exit_p).dot(dirv)
							if along2 > 0.0 and along2 <= left and (exit_p + dirv * along2).distance_to(oe.pos) <= oe.radius + 18.0:
								onward = true
								break
						if onward:
							good += 1
						else:
							bad += 1
						break
				v = good * 45.0 - bad * 30.0 + (15.0 if float(u.resources.get("shards", 0.0)) >= 10.0 else 0.0) - 15.0 if good > 0 else -1.0
		"rootGarden":
			var cnt2: = 0
			for g in sim.gardens:
				if g.source != u.idx:
					continue
				for b in targets:
					if (b as TeamIntel.EnemyBelief).is_hero and Geometry2D.is_point_in_polygon((b as TeamIntel.EnemyBelief).pos, g.points):
						cnt2 += 1
			v = cnt2 * 120.0 - 10.0
		"thornGarden":
			var cnt3: = 0
			for g in sim.gardens:
				if g.source != u.idx:
					continue
				for b in targets:
					if (b as TeamIntel.EnemyBelief).is_hero and Geometry2D.is_point_in_polygon((b as TeamIntel.EnemyBelief).pos, g.points):
						cnt3 += 1
			v = cnt3 * 95.0 - 10.0
		"rapture":
			v = 60.0 if fighting and near_count >= 1 else -10.0
		"upgrade":
			# The engine upgrades the lowest-level turret within 100.
			var tw_best: BUnit = null
			for tw in sim.kits.owned_entities(u, "turret"):
				if tw.level < 3 and tw.pos.distance_to(u.pos) <= 100.0 and (tw_best == null or tw.level < tw_best.level):
					tw_best = tw
			v = 70.0 + (40.0 if tw_best and tw_best.level == 1 else 10.0) if tw_best else -1.0
		_:

			if a.delivery == "area":
				var radius_: = a.radius * (sim.radius_scale(u) if u.def.id == "giant" else 1.0)
				var total: = 0.0
				var hits2: = 0
				for b in targets:
					var e2: TeamIntel.EnemyBelief = b
					var pred: = lead_point(u.pos, e2, 0.0, a.cast_time, 0.7)
					if pred.distance_to(u.pos) <= radius_ + e2.radius - 4.0:
						total += float(_enemy_value(u, a, e2, ctx, 0.85).value)
						hits2 += 1
				if not (ev.buffs as Array).is_empty():
					# X6: the caster is inside its own area buff (baseball S3).
					for x in [u] + (ctx.allies as Array):
						var ally: BUnit = x
						if ally != u and ally.pos.distance_to(u.pos) > radius_ + sim.radius(ally):
							continue
						var cx: Dictionary = ctx if ally == u else _ctx_lite(ally)
						for f in ev.buffs:
							total += _buff_value(ally, f, cx, fighting, nearest) * (1.0 if ally == u else 0.9)
				v = total
				lbl = "%s (%d명)" % [a.name, hits2] if hits2 > 0 else a.name
			else:
				v += float(ev.shield) * minf(1.0, danger / maxf(1.0, float(ctx.ehp)) * 1.6)
				# Summons only see 320 (ENTITY_VISION): cast them when an enemy
				# hero is within their sight and line (audit hive S1/S2).
				var in_sight: bool = false
				var struct_first: bool = false
				var hero_d: float = INF
				var other_d: float = INF
				for b in targets:
					var se: TeamIntel.EnemyBelief = b
					var sd: float = u.pos.distance_to(se.pos)
					if se.is_hero:
						hero_d = minf(hero_d, sd)
						if sd <= 290.0 and sim.arena.line_of_sight(u.pos, se.pos, 2.0):
							in_sight = true
					else:
						other_d = minf(other_d, sd)
				struct_first = other_d + 20.0 < hero_d
				v += float(ev.summon) * (1.0 if in_sight else 0.15)
				for f in a.effects:
					if str(f.get("type", "")) == "summon" and f.has("onHitStatus"):

						var cnt: = float(f.get("count", 1))
						var enable: = 0.0
						for j in u.def.abilities.size():
							var b2: Defs.AbilityDef = u.def.abilities[j]
							if str(b2.condition.get("targetStatus", "")) == str(f.onHitStatus.get("status", "")) and u.cooldowns[j] <= sim.time + 4.0:
								enable = 110.0
						v += (cnt * 26.0 + enable) * ((0.3 if struct_first else 1.0) if in_sight else 0.0)
				for f in ev.buffs:
					v += _buff_value(u, f, ctx, fighting, nearest)
				for f in a.effects:
					if str(f.get("type", "")) == "status":
						var stt: = str(f.get("status", ""))
						if stt in ["invisible", "invulnerable", "untargetable"]:
							v += danger * float(ctx.risk_w) * 0.85 if danger > float(ctx.ehp) * 0.2 else 0.0
					elif str(f.get("type", "")) == "projectile_guard":
						var inc: = 0.0
						for pj in intel.projectiles:
							var rel2: Vector2 = u.pos - (pj.pos as Vector2)
							if rel2.length() < 360.0 and rel2.dot(pj.vel) > 0.0:
								inc += float(pj.dmg)
						for b in targets:
							var e3: TeamIntel.EnemyBelief = b
							if e3.is_hero and e3.def.preferred_range > 150.0 and u.pos.distance_to(e3.pos) < 480.0:
								inc += 35.0
						v += inc * float(f.get("reduction", 0.5)) * 0.9
	v -= _cost(u, a, ctx)
	if v > 0.0:
		out.append({"value": v, "key": "a%d:self" % i, "label": lbl, "parts": {"가치": v}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": cmd_pos, "need": 0.0}})


func _buff_value(u: BUnit, f: Dictionary, ctx: Dictionary, fighting: bool, nearest: float) -> float:
	var stat: = str(f.get("stat", ""))
	var amt: = float(f.get("amount", 0.0))
	var dur: = float(f.get("duration", 3.0))
	var dps: float = ctx.dps
	match stat:
		"attackSpeed", "attackDamage", "basicDamage", "damageDealt", "attackSpeedByMove":
			return dps * amt * dur * (0.9 if fighting else 0.1)
		"moveSpeed":
			if not fighting and ctx.focus and u.def.preferred_range < 100.0 and nearest < 500.0:
				return 45.0 * amt / 0.3
			return 20.0 * amt if fighting else 3.0
		"armor", "magicResistance":
			return float(ctx.danger) * amt * 0.8
		"regen":
			return minf(amt * dur, sim.max_hp(u) - u.hp) * 0.8
		"omnivamp":
			return dps * amt * dur * 0.7 if fighting else 0.0
		"originScent":
			# Game rule (kits.gd): the speed/resist bonus runs toward any hero
			# this werewolf sees at <= 40% health, not the team focus under 45%.
			if not ctx.has("targets"):
				return 0.0
			var prey: TeamIntel.EnemyBelief = Doctrine.scent_prey(self, u, ctx)
			if prey == null:
				return 0.0
			var gap: float = maxf(0.0, u.pos.distance_to(prey.pos) - float(ctx.range) - float(ctx.r) - prey.radius)
			var chase: float = clampf(1.0 - gap / (float(ctx.ms) * 1.35 * dur * 0.8 + 1.0), 0.0, 1.0)
			var worth: float = float(eprof.get(prey.idx, {}).get("threat", 300.0)) * 0.6 + 220.0
			return (worth * 0.3 * chase + float(ctx.danger) * 0.25 * 0.5) * _ew(prey.idx)
		"originPredator":
			if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).hp > u.hp and nearest < 150.0:
				return dps * 0.3 * dur
			return 0.0
		"originRegenPool":
			return 40.0 if fighting else 0.0
		"orbitPower", "originOrbitSpeed":
			return 50.0 if nearest < 110.0 else 0.0
		"contactExplosion":
			# Aura reach is body + 20 (audit nitro S3): value the ticks that
			# can land within the 5 s after closing the edge gap.
			var edge: float = nearest - float(ctx.get("r", 17.0)) - 17.0
			if edge <= 30.0:
				return 140.0
			var close_t: float = (edge - 20.0) / maxf(30.0, float(ctx.ms) * 1.2 * 0.5)
			return 140.0 * clampf(1.0 - close_t / dur, 0.0, 1.0) * (1.0 if str(plan.stance) == "ENGAGE" else 0.6) if edge < 150.0 else 0.0
		"originSniperRound", "originPirateRound":
			return 60.0 if nearest < float(ctx.range) + 60.0 else 0.0
		"originTrajectory":
			return 10.0
		"soulHarvest":
			return float(HadesTactics.harvest_value(self, u, f, ctx).value) # V2 hades S3
		"damageTaken", "arcConvert":
			return WarMachineTactics.buff_value(self, u, f, fighting)
	return 5.0




func _ally_danger_ratio(a: BUnit) -> float:
	return danger_at(a, a.pos, 1.0) / maxf(1.0, a.hp + sim.shield_amount(a))


func _ally_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	var st: Dictionary = ctx.st
	var ev: = KitModel.evaluate(a.effects, st, {})
	var pool: Array[BUnit] = []
	pool.append(u)
	pool.append_array(ctx.allies)
	for t in pool:
		if not sim.target_legal(u, a, t):
			continue
		var dist: = u.pos.distance_to(t.pos)
		var appr: = _approach_factor(u, dist, a.range + float(ctx.r), ctx)
		if appr <= 0.05:
			continue
		var missing: = sim.max_hp(t) - t.hp
		var dr: = _ally_danger_ratio(t)
		var v: = 0.0
		var lbl: = "%s → %s" % [a.name, t.name]
		match a.action:
			"diversion":
				# Never the politician itself (it only makes the enemy dive the
				# caster), and the engine needs line of sight to the ally.
				if t == u or not sim.arena.line_of_sight(u.pos, t.pos, 1.0):
					continue
				var redirected: float = 0.0
				for item in ctx.targets:
					var enemy: TeamIntel.EnemyBelief = item
					if not enemy.is_hero or enemy.pos.distance_to(t.pos) > 450.0 or not sim.arena.line_of_sight(t.pos, enemy.pos, 1.0):
						continue
					redirected += float(eprof.get(enemy.idx, {}).get("dps", 40.0))
				var survivable: float = clampf((t.hp + sim.shield_amount(t)) / maxf(100.0, redirected * 2.5), 0.0, 1.3)
				var armor_factor: float = 1.0 + (sim.stat(t, &"armor") + sim.stat(t, &"magicResistance")) / 200.0
				v = redirected * 0.75 * survivable * armor_factor
				if sim.hp_ratio(t) < 0.4 or dr > 0.65:
					v *= 0.15
				if t.idx == int(plan.get("carry", -1)):
					v *= 0.4
				v += minf(40.0, float(sim.warfare.enemy_distrust(team)) * 5.0) * survivable
			"rescuePull":
				if dr > 0.35 or t.hp / sim.max_hp(t) < 0.35:
					v = minf(missing, 75.0 + 0.65 * float(st.ap)) + dr * 180.0 + (140.0 if dr > 0.8 else 0.0)
				v -= danger_at(u, u.pos, 1.0) * 0.2
				# Pulling an ally out of its own kill window costs that kill
				# (audit aphrodite S3: a 55% werewolf pulled off a 20% archer).
				if v > 0.0:
					var window: float = 0.0
					var t_reach: float = float(aprof.get(t.idx, {}).get("reach", 150.0))
					for item2 in ctx.targets:
						var prey: TeamIntel.EnemyBelief = item2
						if not prey.is_hero or t.pos.distance_to(prey.pos) > t_reach + 40.0:
							continue
						var burst: float = Doctrine.attack_window(self, t, prey, 2.0) + Doctrine.team_window(self, t, prey, 2.0) * 0.5 \
							+ float(reserved.get(prey.idx, 0.0)) * 0.8 + float(aprof.get(t.idx, {}).get("burst", 0.0)) * 0.5
						var share: float = clampf(burst / maxf(1.0, prey.hp + prey.shield), 0.0, 1.0)
						window = maxf(window, (float(eprof.get(prey.idx, {}).get("threat", 300.0)) * 0.6 + 220.0) * share * share)
					v -= window * (0.5 if dr > 1.0 else 1.0)
			"rescueFlight":
				# D7: judge each reachable ally on its own need instead of only
				# the one with the lowest absolute health anywhere on the map.
				if t == u or (dr < 0.35 and sim.hp_ratio(t) >= 0.45):
					continue
				v = (95.0 + 0.75 * float(st.ap)) * minf(1.0, dr * 1.8) + (120.0 if dr > 0.7 else 0.0)
				v -= danger_at(u, t.pos, 1.0) * float(ctx.risk_w) * 0.3
			"apple":
				if t.def.preferred_range > 110.0:
					continue
				# The frenzied ally charges the lowest-health enemy hero that it
				# can see itself (kits.gd apple), not the one our team sees.
				var low: TeamIntel.EnemyBelief = null
				for b: TeamIntel.EnemyBelief in ctx.targets:
					var e: TeamIntel.EnemyBelief = b
					if not e.is_hero or not sim.observes(t, sim.u_at(e.idx)):
						continue
					if low == null or e.hp < low.hp:
						low = e
				if low == null:
					continue
				var d2: = t.pos.distance_to(low.pos)
				v = float(aprof.get(t.idx, {}).get("dps", 50.0)) * 3.0 * (1.0 if d2 < 420.0 else 0.4)
				if low.hp / maxf(1.0, low.max_hp) < 0.45:
					v += 90.0
				if str(plan.stance) == "DISENGAGE":
					v *= 0.3
				# The 3 s forced charge ends inside the target's friends.
				v -= maxf(0.0, danger_at(t, low.pos, 1.0) - danger_at(t, t.pos, 1.0)) * 0.3
			"bloodLink":
				if t == u:
					# X6: the link may target the caster itself; use it on self
					# only when no other ally can take it.
					var other: bool = false
					for x2: BUnit in ctx.allies:
						if sim.target_legal(u, a, x2) and u.pos.distance_to(x2.pos) <= a.range + float(ctx.r) + 160.0:
							other = true
							break
					if other:
						continue
				var fight: = false
				for b: TeamIntel.EnemyBelief in ctx.targets:
					if t.pos.distance_to((b as TeamIntel.EnemyBelief).pos) < float(aprof.get(t.idx, {}).get("reach", 200.0)) + 60.0:
						fight = true
				var tp: Dictionary = aprof.get(t.idx, {})
				v = (float(tp.get("dps", 50.0)) + float(tp.get("burst", 0.0)) * 0.25) * 0.12 * 5.0 * (1.0 if fight else 0.2)
				if t == u:
					# On itself the +10% maximum health also raises current
					# health, so the 8% price (priced by _cost) comes back as
					# long as the 5 s bring that much incoming damage.
					var pay: float = u.hp * 0.08
					var used: float = minf(pay * 1.25, sim.max_hp(u) * 0.1 * minf(1.0, dr * 2.0))
					v += used * (0.6 + 1.2 * (1.0 - float(ctx.hpr))) + (sim.max_hp(u) * 0.1 - pay) * minf(1.0, dr) * 0.5
				else:
					v += sim.max_hp(t) * 0.1 * minf(1.0, dr)
			_:
				v = minf(missing, float(ev.heal)) * (1.0 + dr) + float(ev.shield) * minf(1.0, dr * 1.5)
				for f in ev.buffs:
					v += _buff_value(t, f, _ctx_lite(t), true, 120.0) * 0.8
		v = v * appr - _cost(u, a, ctx)
		if v > 5.0:
			out.append({"value": v, "key": "a%d:%d" % [i, t.idx], "label": lbl, "parts": {"지원": v}, 
				"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "target": t.idx, "pos": t.pos, "need": a.range + float(ctx.r)}})


func _ctx_lite(t: BUnit) -> Dictionary:
	var st: = KitModel.stats_of_unit(sim, t)
	return {"dps": KitModel.basic_dps(st, t.def), "danger": danger_at(t, t.pos, 1.0), "range": float(st.range), "focus": null,
		"ms": float(st.ms), "r": sim.radius(t)}


# Plague S2 mist model (zones.gd "mist"): spawned at the caster after the
# wind-up, it travels a.speed along d up to a.range or the first wall and heals
# injured allied heroes within a.radius + body every 0.25 s for 3 s, each tick
# at most budget/12, lowest health ratio first. The caster is modelled walking
# after it (Doctrine "회수 분사 안으로"); allies keep their current velocity briefly.
func _mist_heal_estimate(u: BUnit, a: Defs.AbilityDef, d: Vector2, budget: float, pool: Array) -> float:
	var start: Vector2 = u.pos
	var travel: float = a.range
	var wall: Dictionary = sim.arena.terrain_contact(start, start + d * a.range, 10.0, false)
	if not wall.is_empty():
		travel = start.distance_to(wall.point)
	var quota: float = budget / 12.0
	var left: float = budget
	var missing: PackedFloat32Array = PackedFloat32Array()
	missing.resize(pool.size())
	for j in pool.size():
		missing[j] = sim.max_hp(pool[j]) - (pool[j] as BUnit).hp
	var healed: float = 0.0
	var walk: float = sim.stat(u, &"moveSpeed") * 0.85
	var locked: float = a.cast_time + a.recovery
	for k in range(1, 13):
		var t: float = 0.25 * k
		var mp: Vector2 = start + d * minf(a.speed * t, travel)
		var q: float = minf(quota, left)
		for j in pool.size():
			if q <= 0.01:
				break
			if missing[j] <= 0.5:
				continue
			var x: BUnit = pool[j]
			var tt: float = a.cast_time + t
			var xp: Vector2 = x.pos + x.vel * minf(tt, 0.5)
			if x == u:
				xp = start + d * clampf(walk * (tt - locked), 0.0, minf(a.speed * t, travel))
			if xp.distance_to(mp) > a.radius + sim.radius(x) - 4.0:
				continue
			var h: float = minf(q, missing[j])
			missing[j] -= h
			q -= h
			left -= h
			healed += h
		if left <= 0.5:
			break
	return healed




func _placement_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	if a.char_id == "torquemada" and a.slot == TorquemadaTactics.FIRE:
		TorquemadaTactics.fire_candidates(self, u, i, a, ctx, out)
		return
	var st: Dictionary = ctx.st
	var ac: Vector2 = plan.ally_c
	var dir: Vector2 = plan.dir
	var targets: Array = ctx.targets
	var fighting: = false
	for b in targets:
		if (b as TeamIntel.EnemyBelief).is_hero and u.pos.distance_to((b as TeamIntel.EnemyBelief).pos) < 480.0:
			fighting = true
	match a.action:
		"turret":
			# V1.5.3: every mode scores turrets by the enemies they would
			# actually cover (audit engineer S1: 70 + 0 coverage was cast).
			if float(cfg.get("v15", 1.0)) > 0.5 and float(cfg.get("tp15", 1.0)) > 0.5:
				_turret_candidates_v15(u, i, a, ctx, out)
				return
			if not fighting and targets.is_empty():
				return
			var base_p: = u.pos + dir * 70.0
			for k in 3:
				var p: = sim.arena.resolve_circle(base_p + dir.rotated((k - 1) * 0.7) * 50.0, 20.0)
				if u.pos.distance_to(p) > a.range:
					continue
				var covered: = 0
				for b in targets:
					if (b as TeamIntel.EnemyBelief).is_hero and p.distance_to((b as TeamIntel.EnemyBelief).pos) < 250.0 and sim.arena.line_of_sight(p, (b as TeamIntel.EnemyBelief).pos, 2.0):
						covered += 1
				var v: = 70.0 + covered * 55.0 - danger_at(u, p, 1.0) * 0.15
				out.append({"value": v, "key": "a%d:t%d" % [i, k], "label": "%s 설치" % a.name, "parts": {"사선": covered}, 
					"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": p, "need": a.range}})
		"plantTree":
			var injured: = 0.0
			for x in [u] + (ctx.allies as Array):
				injured += sim.max_hp(x) - x.hp
			if injured < 120.0 and not fighting:
				return
			var p2: = sim.arena.resolve_circle(ac.lerp(u.pos, 0.3), 25.0)
			if u.pos.distance_to(p2) > a.range:
				p2 = u.pos + (p2 - u.pos).normalized() * (a.range - 5.0)
			var v2: = minf(injured, 250.0) * 0.6 + (60.0 if fighting else 0.0)
			out.append({"value": v2, "key": "a%d:tree" % i, "label": a.name, "parts": {"치유": v2}, 
				"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": p2, "need": a.range}})
		"plantFlowers":
			# The neediest ally the flowers can reach; the old rule skipped the
			# cast whenever the single lowest ally anywhere was out of range.
			var worst: BUnit = null
			for x in [u] + (ctx.allies as Array):
				var bx: BUnit = x
				if bx.hp / sim.max_hp(bx) > 0.8 or u.pos.distance_to(bx.pos + bx.vel * 0.5) > a.range:
					continue
				if worst == null or bx.hp / sim.max_hp(bx) < worst.hp / sim.max_hp(worst):
					worst = bx
			if worst == null:
				return
			var p3: = worst.pos + worst.vel * 0.5
			var v3: = minf(sim.max_hp(worst) - worst.hp, 3.0 * (45.0 + 0.35 * float(st.ap))) * 0.7
			out.append({"value": v3, "key": "a%d:fl" % i, "label": "%s → %s" % [a.name, worst.name], "parts": {"치유": v3}, 
				"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": p3, "need": a.range}})
		"bed":
			# V1.5.3 (audit aphrodite S2): the bed heals 8+0.06AP/s inside 90 and
			# only matters for injured heroes; place it where they are (or fall
			# back toward the retreat line), and on herself when alone.
			var alone: bool = ctx.allies.is_empty() or sim.fights_alone()
			var rate: float = 8.0 + 0.06 * float(st.ap)
			var stay: float = 3.5 if fighting else 7.0
			var anchor: Vector2 = Vector2.ZERO
			var weight: float = 0.0
			var injured: Array = []
			for x in [u] + (ctx.allies as Array):
				var bx: BUnit = x
				if alone and bx != u:
					continue
				var miss4: float = sim.max_hp(bx) - bx.hp
				if miss4 < sim.max_hp(bx) * 0.14 and _ally_danger_ratio(bx) < 0.35:
					continue
				if bx.pos.distance_to(u.pos) > a.range + 260.0:
					continue
				anchor += bx.pos * miss4
				weight += miss4
				injured.append(bx)
			if injured.is_empty() or weight <= 0.0:
				return
			anchor /= weight
			if alone:
				anchor = u.pos - dir * 30.0
			elif str(plan.stance) == "DISENGAGE" or float(ctx.danger) > float(ctx.ehp) * 0.45:
				anchor = anchor.lerp(plan.retreat, 0.45)
			var p4: = sim.arena.resolve_circle(anchor, 25.0)
			if u.pos.distance_to(p4) > a.range:
				p4 = sim.arena.resolve_circle(u.pos + (p4 - u.pos).normalized() * (a.range - 5.0), 25.0)
			var v4: float = 0.0
			var occupants: int = 0
			for y in injured:
				var by: BUnit = y
				var eta: float = maxf(0.0, by.pos.distance_to(p4) - 90.0) / maxf(30.0, sim.stat(by, &"moveSpeed"))
				if eta > 2.5:
					continue
				v4 += minf(sim.max_hp(by) - by.hp, rate * maxf(0.0, stay - eta)) * 0.9
				occupants += 1
			if occupants >= 2 and not fighting:
				v4 += 40.0
			v4 -= danger_at(u, p4, 1.0) * 0.1
			if v4 > 25.0:
				out.append({"value": v4, "key": "a%d:bed" % i, "label": "%s (%d명)" % [a.name, occupants], "parts": {"치유": v4},
					"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": p4, "need": a.range}})
		"healingMist":
			var bank: = float(u.resources.get("healBank", 0.0))
			if bank < 60.0:
				return
			# V1.5.3 (audit plague S2): simulate the mist (starts at the caster,
			# 180/s up to 240 or a wall, 12 ticks of budget/12 to injured allies
			# within 48 + body) against predicted positions; never self-aim.
			var budget: float = minf(bank, 360.0 + 2.0 * float(st.ap))
			var pool: Array = []
			for x in [u] + (ctx.allies as Array):
				var bx2: BUnit = x
				if sim.max_hp(bx2) - bx2.hp >= 30.0 and bx2.pos.distance_to(u.pos) < 520.0:
					pool.append(bx2)
			if pool.is_empty():
				return
			pool.sort_custom(func(x, y): return sim.hp_ratio(x) < sim.hp_ratio(y) or (sim.hp_ratio(x) == sim.hp_ratio(y) and (x as BUnit).idx < (y as BUnit).idx))
			var dirs: Array = []
			for x in pool:
				var bx3: BUnit = x
				if bx3 != u and bx3.pos.distance_to(u.pos) > 20.0:
					dirs.append((bx3.pos - u.pos).normalized())
			var away_m: Vector2 = (u.pos - (plan.enemy_c as Vector2)).normalized() if u.pos.distance_squared_to(plan.enemy_c) > 1.0 else -dir
			for k in 8:
				dirs.append(away_m.rotated(k * TAU / 8.0))
			var best_v: = 0.0
			var best_d: = Vector2.ZERO
			for dv in dirs:
				var healed: float = _mist_heal_estimate(u, a, dv, budget, pool)
				var score: float = healed * 0.85 + (dv as Vector2).dot(away_m) * 6.0
				if score > best_v:
					best_v = score
					best_d = dv
			if best_v > 40.0:
				out.append({"value": best_v, "key": "a%d:mist" % i, "label": a.name, "parts": {"치유": best_v},
					"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos + best_d * minf(a.range, 120.0), "need": a.range}})
		"portalPair":
			_portal_candidates(u, i, a, ctx, out)


func _v15_control() -> bool:
	return control_plan != null and float(cfg.get("v15", 1.0)) > 0.5


func _own_spawn_center() -> Vector2:
	var c: Vector2 = Vector2.ZERO
	var spawns: Array = sim.arena.spawns.get(team, [])
	for p in spawns:
		c += p
	return c / spawns.size() if not spawns.is_empty() else sim.arena.center()


# Conquest retreat: fall back only as far as the local threat reaches, toward
# the objective's staging ground or the nearest other group of allies, never
# all the way home by repeating a fixed step away from the enemy.
func _retreat_anchor(u: BUnit, ctx: Dictionary) -> Vector2:
	# Audit C-5: retreat from the local threat (visible heroes within 700), not
	# from the whole-map enemy centroid.
	var ec: Vector2 = plan.get("enemy_c", u.pos)
	var reach: float = 150.0
	var nearest: float = INF
	var local_c: Vector2 = Vector2.ZERO
	var local_n: int = 0
	for b in ctx.targets:
		var eb: TeamIntel.EnemyBelief = b
		if not eb.is_hero:
			continue
		var pr: Dictionary = eprof.get(eb.idx, {})
		reach = maxf(reach, float(pr.get("reach", 150.0)))
		var de: float = u.pos.distance_to(eb.pos)
		nearest = minf(nearest, de)
		if de <= 700.0:
			local_c += eb.pos
			local_n += 1
	if local_n > 0:
		ec = local_c / float(local_n)
	var order: Dictionary = control_plan.intent(u) if control_plan else {}
	if order.has("stage"):
		var stage: Vector2 = order.stage
		if stage.distance_to(ec) > u.pos.distance_to(ec) + 40.0:
			return stage
	var mine: int = int(squad_of.get(u.idx, -1))
	var best: BUnit = null
	var bd: float = 1100.0
	for a in sim.allies_of(team):
		if a == u or a.team != team or not a.is_hero or int(squad_of.get(a.idx, -2)) == mine:
			continue
		var d: float = a.pos.distance_to(u.pos)
		# An ally already beside us is the same fight, not a group to fall back to.
		if d < 250.0:
			continue
		if d < bd and a.pos.distance_to(ec) > u.pos.distance_to(ec) - 60.0:
			bd = d
			best = a
	if best:
		return sim.arena.resolve_circle(best.pos + (u.pos - best.pos).limit_length(60.0), sim.radius(u))
	var away: Vector2 = (u.pos - ec).normalized() if u.pos.distance_squared_to(ec) > 1.0 else (_own_spawn_center() - u.pos).normalized()
	var need: float = clampf(reach + 70.0 - nearest, 0.0, 200.0) if nearest < INF else 0.0
	return sim.arena.resolve_circle(u.pos + away * need, sim.radius(u))


# Conquest turret: built only where an objective fight is happening or about
# to happen, covering the capture circle, instead of on cooldown near spawn.
func _turret_candidates_v15(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var order: Dictionary = control_plan.intent(u) if control_plan else {}
	var fight_near: TeamIntel.EnemyBelief = null
	var fd: float = 470.0
	for b in ctx.targets:
		var eb: TeamIntel.EnemyBelief = b
		if eb.is_hero and u.pos.distance_to(eb.pos) < fd:
			fd = u.pos.distance_to(eb.pos)
			fight_near = eb
	if fight_near == null and u.pos.distance_to(_own_spawn_center()) < 520.0:
		return
	var anchors: Array = []
	if not order.is_empty() and str(order.get("heal_target", "")) == "":
		var center: Vector2 = order.center
		var threatened: bool = bool(order.get("fight", false)) or bool(order.get("enemy_capturing", false))
		for b in ctx.targets:
			var eb2: TeamIntel.EnemyBelief = b
			if eb2.is_hero and eb2.pos.distance_to(center) < 720.0:
				threatened = true
		if threatened and u.pos.distance_to(center) < float(order.radius) + 330.0:
			anchors.append(center)
	if fight_near:
		anchors.append(fight_near.pos.lerp(u.pos, 0.55))
	if anchors.is_empty():
		return
	var own_turrets: Array = []
	for e in sim.entities:
		if e.alive and e.owner_idx == u.idx and e.kind == "turret":
			own_turrets.append(e)
	var best_v: float = -INF
	var best_p: Vector2 = Vector2.ZERO
	var best_cov: int = 0
	for anchor in anchors:
		var base: Vector2 = anchor
		for ring in [0.0, 70.0, 130.0]:
			for k in (1 if ring == 0.0 else 6):
				var p: Vector2 = sim.arena.resolve_circle(base + Vector2.from_angle(k * TAU / 6.0 + 0.4) * ring, 20.0)
				if u.pos.distance_to(p) > a.range + 4.0:
					p = u.pos + (p - u.pos).normalized() * (a.range - 6.0)
					p = sim.arena.resolve_circle(p, 20.0)
				var covered: int = 0
				for b in ctx.targets:
					var eb3: TeamIntel.EnemyBelief = b
					if eb3.is_hero and p.distance_to(eb3.pos) < 230.0 and sim.arena.line_of_sight(p, eb3.pos, 2.0):
						covered += 1
				var v: float = 25.0 + covered * 55.0 - danger_at(u, p, 1.0) * 0.12
				if not order.is_empty() and p.distance_to(order.center) < 235.0 - float(order.radius) * 0.4:
					v += 30.0
				for tw in own_turrets:
					if (tw as BUnit).pos.distance_to(p) < 80.0:
						v -= 45.0
				if v > best_v:
					best_v = v
					best_p = p
					best_cov = covered
	if best_v < 45.0:
		return
	out.append({"value": best_v, "key": "a%d:tv" % i, "label": "%s 설치 (%s 화망)" % [a.name, "거점" if not order.is_empty() else "교전"], "parts": {"사선": best_cov},
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": best_p, "need": a.range}})


func _portal_candidates(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	var dir: Vector2 = plan.dir
	var stance: = str(plan.stance)
	var pa: = sim.arena.resolve_circle(u.pos + dir * 36.0, 22.0)
	var pb: Vector2
	var v: = 0.0
	var lbl: = "쌍문"
	if stance == "DISENGAGE" or float(ctx.danger) > float(ctx.ehp) * 0.45:
		pa = sim.arena.resolve_circle(u.pos + dir * 24.0, 22.0)
		pb = sim.arena.resolve_circle(u.pos - dir * 250.0, 22.0)
		v = float(ctx.danger) * 0.5 + 40.0
		lbl = "쌍문 (후퇴로)"
	elif stance == "ENGAGE" and ctx.focus:
		var f: TeamIntel.EnemyBelief = ctx.focus
		pb = sim.arena.resolve_circle(u.pos + (f.pos - u.pos).normalized() * minf(270.0, u.pos.distance_to(f.pos) - 40.0), 22.0)
		var melee: = 0
		for x: BUnit in ctx.allies:
			if x.def.preferred_range < 100.0:
				melee += 1
		v = 30.0 + melee * 40.0
		lbl = "쌍문 (진입로)"
	else:
		pb = sim.arena.resolve_circle(u.pos - dir.rotated(PI * 0.5) * 200.0, 22.0)
		v = 25.0 if float(u.resources.get("shards", 0.0)) < 30.0 else 5.0
		lbl = "쌍문 (조각 수급)"
	# Review 1.5.3: the exit is a zero-time move (the pair lasts 10 s and
	# carries allies too), so it obeys the same public gimmick rules as a walk
	# goal: inside the ring that is still safe after arrival (+2 s), off closing
	# gates, strikes and links, never in an always-on damage field. A retreat
	# exit must also actually be safer than standing here.
	if _gimmick_goals_live():
		var rr: float = float(ctx.r)
		pb = _gimmick_safe_goal(u, pb, rr, INF)
		if _static_damage_at(pb, rr):
			return
		# Travellers come out past the exit (zones.gd: radius + body + 3) and
		# the pair stays up 10 s: that landing must stay inside the ring for
		# most of the pair's life, or every later trip throws someone out.
		var ring: Dictionary = _ring_def()
		if not ring.is_empty() and pb.distance_squared_to(pa) > 1.0:
			var land: Vector2 = pb + (pb - pa).normalized() * (22.0 + rr + 3.0)
			if Arena.ring_outside(ring, land, sim.time + 6.0, rr * 0.3):
				return
		if lbl == "쌍문 (후퇴로)":
			var exit_danger: float = danger_at(u, pb, 1.0)
			if exit_danger > 0.0 and exit_danger >= float(ctx.danger) * 0.8:
				return
	if pa.distance_to(pb) < 145.0 or u.pos.distance_to(pb) > a.range - 4.0 or u.pos.distance_to(pa) > a.range - 4.0:
		return
	out.append({"value": v, "key": "a%d:portal" % i, "label": lbl, "parts": {"기동": v}, 
		"cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": pb, "need": a.range, "extra": {"portal_a": pa, "portal_b": pb}}})


func _virtual_candidate(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void :
	match a.virtual_kind:
		"eat":
			var fish: Array = u.ks.fish
			var v: = 0.0
			var fighting: = false
			for b: TeamIntel.EnemyBelief in ctx.targets:
				if u.pos.distance_to((b as TeamIntel.EnemyBelief).pos) < 250.0:
					fighting = true
			if fish.size() >= 2 and float(u.ks.fish_next) - sim.time < 1.5:
				v = 70.0
			elif fighting and float(ctx.hpr) < 0.6:
				v = 55.0
			elif fighting and u.cooldowns[2] > sim.time + 3.0:
				v = 35.0
			if v > 0.0:
				out.append({"value": v, "key": "eat", "label": a.name, "parts": {"강화": v}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})
		"borrow":
			# D2 (AI side): a borrowed skill keeps its own condition (e.g. nitro
			# wall run needs a wall); the virtual readiness check ignores it.
			if a.target == "self" and (not sim.check_condition(u, null, a.condition) or not sim.kits.extra_ready(u, a)):
				return
			var tmp: Array = []
			match a.target:
				"enemy":
					_enemy_target_candidates(u, i, a, ctx, tmp)
				"position":
					_position_candidates(u, i, a, ctx, tmp)
				"self":
					_self_candidates(u, i, a, ctx, tmp)
				"ally":
					_ally_candidates(u, i, a, ctx, tmp)
				"position_ally":
					_placement_candidates(u, i, a, ctx, tmp)
			for c in tmp:
				c.value = float(c.value) * 0.9
				out.append(c)




func _basic_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void :
	if u.def.has_rule("no_basic") or u.def.id == "politician":
		return
	var wait: = u.attack_ready_at - sim.time
	if wait > 0.3:
		return
	var st: Dictionary = ctx.st
	var r: float = ctx.r
	var rng_: = float(st.range)
	# D1/X1: basic attacks, like skills, only on enemies this hero observes.
	for b: TeamIntel.EnemyBelief in ctx.strike:
		var e: TeamIntel.EnemyBelief = b
		var dist: = u.pos.distance_to(e.pos)
		var need: = rng_ + r + e.radius
		var appr: = _approach_factor(u, dist, need - 4.0, ctx)
		if appr <= 0.05:
			continue
		var est: Dictionary = KitModel._enemy_base(e.def).st
		var per: = KitModel.basic_dps(st, u.def) / maxf(0.2, float(st. as )) * 100.0 / (100.0 + float(est.armor))
		var hitp: = 1.0 if rng_ <= 100.0 else 0.88
		var res: = float(reserved.get(e.idx, 0.0))
		var v: = minf(per * hitp, maxf(0.0, e.hp + e.shield - res * 0.8) + 1.0)
		if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == e.idx:
			v *= 1.35
		if e.is_hero:
			v *= _ew(e.idx)
		if e.is_hero and per >= e.hp + e.shield:
			v += 200.0
		if not e.is_hero:
			v *= 0.35 if e.kind != "turret" else 0.8

		if sim.get_buff(u, &"originSniperRound") or sim.get_buff(u, &"originPirateRound"):
			v += 40.0
		v *= appr

		if dist > need:
			var appr_pos: = e.pos + (u.pos - e.pos).normalized() * (need - 6.0)
			v -= maxf(0.0, danger_at(u, appr_pos, 1.0) - float(ctx.danger)) * float(ctx.risk_w) * 0.6
		out.append({"value": v, "key": "b:%d" % e.idx, "label": "기본 공격 → %s" % e.def.name, "parts": {"피해": per * hitp}, 
			"cmd": {"kind": "basic", "target": e.idx, "need": need}})




func _move_candidates(u: BUnit, ctx: Dictionary, out: Array) -> void :
	var r: float = ctx.r
	var pref: = maxf(float(ctx.range), float(ctx.pref))
	var targets: Array = ctx.targets
	var stance: = str(plan.stance)
	var pts: Array = []
	pts.append([u.pos, "위치 유지", 0.0])
	var tgt: TeamIntel.EnemyBelief = ctx.focus
	if tgt == null or not tgt.visible or u.pos.distance_to(tgt.pos) > 700.0:
		tgt = null
		var bd: = INF
		for b in targets:
			var e: TeamIntel.EnemyBelief = b
			if not e.is_hero:
				continue
			var d: = u.pos.distance_to(e.pos)
			if d < bd:
				bd = d
				tgt = e

	var prot: Dictionary = (plan.get("protector", {}) as Dictionary).get(u.idx, {})
	if not prot.is_empty():
		var victim: = sim.u_at(int(prot.victim))
		var threat_b: TeamIntel.EnemyBelief = intel.enemies.get(int(prot.threat))
		if victim and threat_b:
			var between: = victim.pos.lerp(threat_b.pos, 0.55)
			pts.append([between, "보호: %s" % victim.name, 70.0])
			tgt = threat_b

	# D1/X1: the team sees this target but this hero does not, so it cannot
	# strike it from here. Walk the route toward it to the first spot with a
	# line of sight instead of waiting behind the wall.
	if tgt and tgt.visible and (float(ctx.dps) > 0.0 or not (ctx.pot as Array).is_empty()):
		var tgt_unit: BUnit = sim.u_at(tgt.idx)
		if tgt_unit and not sim.observes(u, tgt_unit):
			var peek: Vector2 = _sight_point(u, tgt, r)
			if peek.is_finite():
				pts.append([peek, "시야 확보", 26.0])


	var assault: = 0.0
	if cfg.nk > 0.5 and stance == "ENGAGE" and bool(plan.get("go", false)):
		assault = clampf(float(plan.get("pressure", 0.0)) * 1.2 + 0.6 * float(plan.get("nokill", 0.0)), 0.0, 1.0)
	if tgt:
		var dir: = (u.pos - tgt.pos).normalized() if u.pos.distance_squared_to(tgt.pos) > 1.0 else - (plan.dir as Vector2)
		var ring: = pref + r + tgt.radius - (6.0 if pref < 100.0 else 18.0)
		for ang in [0.0, 0.5, -0.5, 1.05, -1.05]:
			pts.append([tgt.pos + dir.rotated(ang) * ring, "교전 위치" if assault < 0.25 else "강습", 70.0 * assault])
		if pref > 120.0:
			pts.append([tgt.pos + dir * (ring + 60.0), "사거리 유지", 0.0])

	var away: = (u.pos - (plan.enemy_c as Vector2)).normalized()
	pts.append([u.pos + away * 110.0, "후퇴", 0.0])

	pts.append([u.pos + away.rotated(0.8) * 100.0, "측면 이탈 (우)", 0.0])
	pts.append([u.pos + away.rotated(-0.8) * 100.0, "측면 이탈 (좌)", 0.0])
	if _v15_control() and float(cfg.get("rt15", 1.0)) > 0.5:
		var anchor: Vector2 = _retreat_anchor(u, ctx)
		var exposed: bool = float(ctx.danger) > float(ctx.ehp) * 0.08
		pts.append([anchor, "재집결", (30.0 if exposed else 6.0) if stance == "DISENGAGE" else 0.0])
	else:
		pts.append([plan.retreat, "재집결", 0.0 if stance != "DISENGAGE" else 30.0])

	var slot_off: = - (plan.dir as Vector2) * (110.0 if ctx.backline else 0.0)
	var join_bonus: = 10.0
	if stance in ["SCOUT", "ENGAGE"] and cfg.front > 0.5:
		join_bonus = 16.0 + 18.0 * float(plan.get("pressure", 0.0))
	elif cfg.front < 0.5:
		join_bonus = 10.0 if stance != "SCOUT" else 0.0
	var march_ok: bool = cfg.march > 0.5 and stance == "ENGAGE" and bool(plan.get("go", false)) and not bool(plan.get("fighting", false))
	if march_ok and cfg.march > 1.5 and tgt != null and u.pos.distance_to(tgt.pos) <= pref + r + tgt.radius + 140.0:

		march_ok = false
	if march_ok:

		slot_off = - (plan.dir as Vector2) * (40.0 if ctx.backline else 0.0)
		join_bonus = maxf(join_bonus, 20.0)
	# Engine follow-up (furnace_basin 156134): in POKE with the enemy close the
	# front IS the team centroid, and every hero "joining" it pinned its allies
	# into a corner. There is no front to join then.
	if not (stance == "POKE" and float(plan.get("adv_step", 10.0)) < 20.0 and u.pos.distance_to(plan.front) < 140.0):
		pts.append([(plan.front as Vector2) + slot_off, "전열 합류", join_bonus])

	var poked: = false
	if cfg.cover < 0.5:
		poked = true
	elif stance in ["POKE", "DISENGAGE"]:
		for b in targets:
			var eb0: TeamIntel.EnemyBelief = b
			if eb0.is_hero and eb0.def.preferred_range > 150.0 and u.pos.distance_to(eb0.pos) < 640.0:
				poked = true
				break
	var covers: Array = []
	for oi in (sim.arena.obs_count if poked else 0):
		if (sim.arena.obs_mask[oi] & Arena.MASK_VISION) == 0:
			continue
		var oc: Vector2 = Vector2(sim.arena.obs_x[oi] + sim.arena.obs_w[oi] * 0.5, sim.arena.obs_y[oi] + sim.arena.obs_h[oi] * 0.5) if sim.arena.obs_circle[oi] == 0 else Vector2(sim.arena.obs_x[oi], sim.arena.obs_y[oi])
		var od: = oc.distance_to(u.pos)
		if od > 320.0:
			continue
		var ext: = sim.arena.obs_r[oi] if sim.arena.obs_circle[oi] == 1 else maxf(sim.arena.obs_w[oi], sim.arena.obs_h[oi]) * 0.5
		covers.append([od, oc + ((oc - (plan.enemy_c as Vector2)).normalized()) * (ext + r + 16.0)])
	covers.sort_custom( func(x, y): return float(x[0]) < float(y[0]))
	for k in mini(3, covers.size()):
		pts.append([covers[k][1], "엄폐", 8.0])

	if stance == "SCOUT":
		var best_b: TeamIntel.EnemyBelief = null
		var best_s: = - INF
		for b in intel.alive_enemies():
			var eb: TeamIntel.EnemyBelief = b
			var sc: = eb.confidence - eb.hp / maxf(1.0, eb.max_hp) * 0.5 - u.pos.distance_to(eb.pos) / 1400.0
			if sc > best_s:
				best_s = sc
				best_b = eb
		if best_b:


			var reach_max: = 0.0
			for k in eprof:
				reach_max = maxf(reach_max, float(eprof[k].reach))
			var stop: = clampf(reach_max + 70.0, 320.0, 500.0)
			# Telemetry #2: scout goals follow the navigator route to the belief.
			# Straight-line steps into a wall were snapped onto its near face, so
			# both teams parked on opposite faces of the same wall for minutes.
			var route: PackedVector2Array = _cached_path(u, best_b.pos, r)
			var d_b: = _route_length(u.pos, best_b.pos, route)
			var step: = clampf(d_b - stop, 0.0, 240.0)
			if step <= 16.0 and best_b.confidence < 0.4:

				step = minf(d_b, 170.0)
			step *= 0.8 if ctx.backline else 1.0

			var ahead: = (u.pos - (plan.ally_c as Vector2)).dot((best_b.pos - u.pos).normalized())
			var stale: float = float(plan.get("stale", 0.0))
			var bonus: = 38.0 + 30.0 * stale + 20.0 * float(plan.get("pressure", 0.0))
			if int(plan.get("scout", -1)) != u.idx and allies_cache.size() > 1:
				bonus *= 0.45
			if ahead > 160.0:
				bonus *= 0.3
			if step > 16.0:
				for frac in [1.0, 0.5]:
					pts.append([_along_route(u.pos, best_b.pos, route, step * float(frac)), "정찰", bonus * (0.85 + 0.15 * frac), true])
				# Side sweeps only onto open ground; a point inside a wall would be
				# snapped to the wall face again.
				var dir0: = (_along_route(u.pos, best_b.pos, route, minf(step, 64.0)) - u.pos).normalized()
				for ang in [0.5, -0.5, 1.0, -1.0]:
					var toward: Vector2 = u.pos + dir0.rotated(float(ang)) * step
					if sim.arena.is_walkable(toward, r) and not sim.arena.segment_blocked(u.pos, toward, r, Arena.MASK_UNITS):
						pts.append([toward, "정찰", bonus * (1.0 - absf(ang) * 0.12), true])
			if stale >= 0.5:
				# Nobody has fought for a long time: head for the first point on the
				# route that actually sees the believed position.
				var vantage: Vector2 = _sight_point_at(u, best_b.pos, route, r, 640.0)
				if vantage.is_finite() and vantage.distance_to(u.pos) > 24.0:
					pts.append([vantage, "정찰 (시야 확보)", bonus * (0.9 + 0.6 * stale), true])

	if u.def.id == "world_tree":
		_grove_points(u, ctx, pts)

	if cfg.doct > 0.5:
		Doctrine.move_points(self, u, ctx, tgt, pts)
	if control_plan:
		var objective: Dictionary = control_plan.intent(u)
		if not objective.is_empty():
			var goal: Vector2 = objective.goal
			var arrived: bool = u.pos.distance_to(goal) < 12.0
			var inside: bool = u.pos.distance_to(objective.center) < float(objective.radius) * 0.72
			var reward: float = 95.0 + float(objective.urgency) * 45.0
			if inside and str(objective.heal_target) == "":
				reward = 25.0
			if str(objective.heal_target) != "":
				reward += (1.0 - float(ctx.hpr)) * 65.0
			pts.append([u.pos if arrived else goal, "거점 %s · %s" % [str(objective.label), str(objective.role)], reward])
			if inside and str(objective.heal_target) == "":
				pts.append([u.pos, "거점 점령 범위 유지", 30.0])

	_mode_move_points(u, ctx, pts)
	_environment_move_points(u, ctx, pts)
	_gimmick_move_points(u, ctx, pts)
	var punish_b: TeamIntel.EnemyBelief = intel.enemies.get(int(plan.get("punish", -1)))
	var burst_b: TeamIntel.EnemyBelief = intel.enemies.get(int(plan.get("burst", -1)))
	var collapse: TeamIntel.EnemyBelief = punish_b if punish_b else burst_b
	if collapse and collapse.visible and u.pos.distance_to(collapse.pos) < 560.0:
		var ring2: = pref + r + collapse.radius - (6.0 if pref < 100.0 else 16.0)
		pts.append([collapse.pos + (u.pos - collapse.pos).normalized() * ring2, "집중: %s" % collapse.def.name, 22.0 if punish_b else 14.0])
	if cfg.peel2 > 0.5 and int(plan.get("carry", -1)) == u.idx and (plan.get("peel_threats", {}) as Dictionary).values().has(u.idx):
		for pi in plan.get("protectors", []):
			var pu: = sim.u_at(int(pi))
			if pu and pu.alive and pu.pos.distance_to(u.pos) < 420.0:
				pts.append([pu.pos - (plan.dir as Vector2) * 60.0, "보호선으로 후퇴", 18.0])
				break

	var dodge: = _dodge_vector(u)
	if dodge.length() > 0.05:
		pts.append([u.pos + dodge.normalized() * 70.0, "회피", 30.0])
	var horizon: = 1.0

	var allow: = cohesion_allow(u, ctx)
	var cohesive: = allow < INF
	var coh_k: = float(plan.get("k_coh", 1.0))
	var ll: = leader_line(u, ctx)
	var ac: Vector2 = plan.ally_c
	var dir_e: Vector2 = plan.dir
	var crowd: = 40.0 * float(plan.get("k_spread", 1.0))
	# Telemetry #4: price damaging hazards along the way, not only at the goal,
	# and never park a goal inside an always-on damage field.
	var hazards_on: bool = _damaging_hazards()
	var gimmicks_on: bool = float(cfg.get("ggl", 1.0)) > 0.5 and _gimmick_goals_live()
	var kiting: bool = stance in ["POKE", "DISENGAGE"] or bool(ctx.backline)
	var ms: float = maxf(40.0, float(ctx.ms))
	# D1/X1: while this hero cannot see its target, an attack position next to
	# the target without a line of sight to it (the near face of the wall in
	# between) only parks the hero; such bonuses mostly lapse.
	var blind: bool = false
	if tgt and tgt.visible:
		var tgt_body: BUnit = sim.u_at(tgt.idx)
		blind = tgt_body != null and not sim.observes(u, tgt_body)
	var blind_reach: float = pref + r + (tgt.radius if tgt else 0.0) + 90.0
	for row in pts:
		var p: = sim.arena.resolve_circle(row[0] as Vector2, r)
		if hazards_on:
			p = _hazard_free_goal(u, p, r)
		var displaced: bool = false
		if gimmicks_on:
			var p_safe: Vector2 = _gimmick_safe_goal(u, p, r, ms)
			# A goal the ring / a gate / a trigger moved far no longer serves its
			# purpose (a fountain outside the ring, a scout point beyond it): keep
			# it as a plain position without its bonus.
			displaced = p_safe.distance_to(p) > 48.0 and str(row[1]) != "결계 안으로"
			p = p_safe
		p = _v2_move_goal(u, p, r, str(row[1]))
		if not p.is_finite():
			continue
		var vis_only: bool = row.size() > 3 and bool(row[3])
		var danger: = danger_at(u, p, horizon, false)
		if hazards_on:
			danger += _route_hazard_cost(u, p, r, ms)
		var off: = _offense_at(u, p, ctx, tgt)
		var dist: = u.pos.distance_to(p)
		var bonus: float = float(row[2])
		if displaced:
			bonus = minf(bonus, 0.0)
		var blind_spot: bool = blind and str(row[1]) != "엄폐" and p.distance_to(tgt.pos) <= blind_reach and not sim.arena.line_of_sight(p, tgt.pos, 3.0)
		if blind_spot:
			off *= 0.3
			if bonus > 0.0:
				bonus *= 0.35
		var v: = off - danger * float(ctx.risk_w) + bonus - dist * 0.02
		if gimmicks_on:
			v -= _mud_cost(u, p, r, kiting or str(row[1]) in ["후퇴", "측면 이탈 (우)", "측면 이탈 (좌)", "사거리 유지", "회피"])
		if vis_only and int(plan.get("scout", -1)) == u.idx:
			v += _scout_information_gain(u, p) * 42.0
		if assault > 0.0 and str(row[1]) == "강습":
			v += danger * float(ctx.risk_w) * 0.35 * assault

		if stance == "ENGAGE" and tgt and p.distance_to(tgt.pos) < u.pos.distance_to(tgt.pos) and not blind_spot:
			v += 12.0
		if stance == "DISENGAGE":
			v += (u.pos.distance_to(plan.enemy_c) - p.distance_to(plan.enemy_c)) * -0.08
		if cohesive:
			var ahead: = (p - ac).dot(dir_e)
			if ahead > allow:
				v -= (ahead - allow) * 0.3 * coh_k
		if not ll.is_empty():
			var ahead_l: = (p - (ll.pos as Vector2)).dot(dir_e)
			if ahead_l > 20.0:
				v -= (ahead_l - 20.0) * 0.4

		for x: BUnit in ctx.allies:
			var dd: = x.pos.distance_to(p)
			if dd < crowd:
				v -= (crowd - dd) * 0.35 * (40.0 / crowd)
		var move_command: Dictionary = {"kind": "move", "goal": p}
		if row.size() > 4:
			move_command["fountain_id"] = str(row[4])
		out.append({"value": v, "key": "m:%s:%d:%d" % [str(row[1]), int(p.x / 30.0), int(p.y / 30.0)], "label": str(row[1]), 
			"parts": {"공격": off, "위험": danger}, 
			"cmd": move_command})


func _offense_at(_u: BUnit, p: Vector2, ctx: Dictionary, tgt: TeamIntel.EnemyBelief) -> float:
	if tgt == null:
		return 0.0
	var dist: = p.distance_to(tgt.pos) - float(ctx.r) - tgt.radius
	var rng_: = float(ctx.range)
	var dps: float = ctx.dps
	var h: = 1.0
	var v: = 0.0
	if dist <= rng_:
		v = dps * h
	else:
		var gap: = dist - rng_
		v = dps * h * maxf(0.0, 1.0 - gap / (float(ctx.ms) * h + 1.0)) * 0.5
	var los: = true
	if dist > 60.0 and not sim.arena.line_of_sight(p, tgt.pos, 3.0):
		los = false
		if rng_ > 100.0 and dist <= rng_:
			v *= 0.2
	if tgt.is_hero:
		v *= _ew(tgt.idx)

	var best_pot: = 0.0
	for pt in ctx.pot:
		var need: = float(pt.range) + 6.0
		if dist <= need:
			best_pot = maxf(best_pot, float(pt.value))
		elif dist <= need + float(ctx.ms) * 0.6:
			best_pot = maxf(best_pot, float(pt.value) * 0.4)
	v += best_pot * (0.35 if los else 0.1) * float(cfg.pot)
	if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == tgt.idx:
		v *= 1.25
	return v


# Navigator route from the hero toward `to` as its corner points (empty when
# the straight segment is clear), cached per hero for 0.5 s while both ends
# hold.
func _cached_path(u: BUnit, to: Vector2, r: float) -> PackedVector2Array:
	var c: Dictionary = _scout_cache.get(u.idx, {})
	if not c.is_empty() and float(c.until) > sim.time and (c.to as Vector2).distance_squared_to(to) < 900.0 \
			and (c.from as Vector2).distance_squared_to(u.pos) < 1600.0:
		return c.path
	var nav: Navigator = navigator_for(r)
	var path: PackedVector2Array = PackedVector2Array() if nav.clear(u.pos, to, r) else _taut_path(nav, u.pos, to, nav.path_points(u.pos, to), r)
	_scout_cache[u.idx] = {"to": to, "from": u.pos, "path": path, "until": sim.time + 0.5}
	return path


# A grid path is a chain of cell centres whose zig-zag depends on the search's
# tie-breaking, so an east-bound and a west-bound search on a mirrored map give
# differently shaped routes (and scout points sampled along them favoured one
# side). Keep only the corners a straight walker needs: the last point still
# in clear line from the current corner, repeatedly.
func _taut_path(nav: Navigator, from: Vector2, to: Vector2, raw: PackedVector2Array, r: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = raw.size()
	var cur: Vector2 = from
	var i: int = 0
	while i < n and not nav.clear(cur, to, r):
		var j: int = i
		while j + 1 < n and nav.clear(cur, raw[j + 1], r):
			j += 1
		cur = raw[j]
		out.append(cur)
		i = j + 1
	return out


func _route_length(from: Vector2, to: Vector2, path: PackedVector2Array) -> float:
	if path.is_empty():
		return from.distance_to(to)
	var total: float = from.distance_to(path[0])
	for k in range(1, path.size()):
		total += path[k - 1].distance_to(path[k])
	return total + path[path.size() - 1].distance_to(to)


# The point `dist` along from -> path -> to.
func _along_route(from: Vector2, to: Vector2, path: PackedVector2Array, dist: float) -> Vector2:
	var prev: Vector2 = from
	var acc: float = 0.0
	for k in path.size() + 1:
		var nxt: Vector2 = path[k] if k < path.size() else to
		var seg: float = prev.distance_to(nxt)
		if acc + seg >= dist and seg > 0.001:
			return prev.lerp(nxt, (dist - acc) / seg)
		acc += seg
		prev = nxt
	return to


# First point along the route from which `at` is in line of sight (and the
# hero would not stand on it), searched up to `limit` px of walking.
func _sight_point_at(u: BUnit, at: Vector2, path: PackedVector2Array, r: float, limit: float) -> Vector2:
	var total: float = minf(limit, _route_length(u.pos, at, path))
	var d: float = 32.0
	while d <= total:
		var q: Vector2 = _along_route(u.pos, at, path, d)
		if q.distance_to(at) > r + 36.0 and sim.arena.line_of_sight(q, at, 3.0):
			return q
		d += 32.0
	return Vector2.INF


func _sight_point(u: BUnit, e: TeamIntel.EnemyBelief, r: float) -> Vector2:
	var path: PackedVector2Array = _cached_path(u, e.pos, r)
	var q: Vector2 = _sight_point_at(u, e.pos, path, r, 520.0)
	if q.is_finite():
		return q
	return _along_route(u.pos, e.pos, path, minf(240.0, _route_length(u.pos, e.pos, path)))


# Whether this arena has any hazard that can damage heroes (cached per arena).
func _damaging_hazards() -> bool:
	if not sim.env.enabled or sim.arena.hazards.is_empty():
		return false
	_refresh_hazard_bounds()
	return _hazard_damaging


# Bounding circles (x, y, radius) of the hazards that can cost a hero anything
# (damage, push, slow), rebuilt once per arena instance. Types with a known
# extent are bounded by their shape (+ ring width / strike radius); gates by
# their frame (Arena.gate_penalty). Two V1.5.3 types are dynamic and checked
# per call instead: the closing ring (a cost OUTSIDE a shrinking circle,
# bounded by its radius _RING_LOOK seconds ahead) and announced artillery
# strikes (sim.env.strikes, public telegraphs). Any other type disables the
# early-outs. Pure public geometry; lets per-tick hazard probes skip clear
# ground (D5).
const _BOUNDED_HAZARDS: = ["lava", "spikes", "eruption", "wind", "gravity", "shockwave", "mud", "jump_pad", "artillery"]
const _HARMLESS_HAZARDS: = ["haste", "healing_fountain", "portal"]
# Callers price hazards at most ~12 s ahead (ring penalty looks 4 s past the
# probe time, routes price arrival + 1 s); the ring bound looks further.
const _RING_LOOK: = 16.0
var _haz_bounds: PackedVector3Array = PackedVector3Array()
var _haz_unbounded: bool = false
var _haz_rings: Array = []


func _refresh_hazard_bounds() -> void:
	if _hazard_arena == sim.arena:
		return
	_hazard_arena = sim.arena
	_hazard_damaging = false
	_haz_unbounded = false
	_haz_bounds = PackedVector3Array()
	_haz_rings = []
	for h: Dictionary in sim.arena.hazards:
		if float(h.get("damage", 0.0)) > 0.0 or float(h.get("damagePercent", 0.0)) > 0.0:
			_hazard_damaging = true
		var typ: String = str(h.get("type", ""))
		if typ in _HARMLESS_HAZARDS:
			continue
		if typ == "closing_ring":
			_haz_rings.append(h)
			continue
		if not typ in _BOUNDED_HAZARDS or not h.has("x") or not h.has("y"):
			_haz_unbounded = true
			continue
		var c: Vector2 = Vector2(float(h.x), float(h.y))
		var ext: float = 0.0 if typ == "artillery" else float(h.get("radius", 0.0))
		if str(h.get("shape", "rect")) != "circle":
			var half: Vector2 = Vector2(float(h.get("w", 0.0)), float(h.get("h", 0.0))) * 0.5
			c += half
			ext = maxf(ext, half.length())
		elif typ == "artillery":
			ext = float(h.get("radius", 0.0))
		if h.has("center"):
			ext += (h.center as Vector2).distance_to(c)
		ext += maxf(1.0, float(h.get("ringWidth", 22.0))) if typ == "shockwave" else 0.0
		# Artillery: unannounced salvos are priced inside the area padded by the
		# strike radius (Arena.artillery_expected); announced ones are dynamic.
		if typ == "artillery":
			ext += maxf(1.0, float(h.get("radius", 60.0)))
		else:
			ext += float(h.get("spread", 0.0))
		_haz_bounds.append(Vector3(c.x, c.y, ext + 4.0))
	for g: Dictionary in sim.arena.gates:
		var rect: Rect2 = g.rect
		_haz_bounds.append(Vector3(rect.get_center().x, rect.get_center().y, rect.size.length() * 0.5 + 4.0))


# False only when no costly hazard can touch a body of padding `reach` at p.
func _hazard_near(p: Vector2, reach: float) -> bool:
	if not sim.env.enabled or (sim.arena.hazards.is_empty() and sim.arena.gates.is_empty()):
		return false
	_refresh_hazard_bounds()
	if _haz_unbounded:
		return true
	# Rect shapes are padded per axis (square corners): sqrt(2) * reach.
	var pad: float = reach * 1.415
	if _haz_bounds_near(p, pad):
		return true
	for h: Dictionary in _haz_rings:
		if p.distance_to(h.center) + reach >= Arena.ring_radius_at(h, sim.time + _RING_LOOK) - 4.0:
			return true
	for s: Dictionary in sim.env.strikes:
		var sr: float = float(s.radius) + reach + 4.0
		if p.distance_squared_to(s.pos) <= sr * sr:
			return true
	return false


# Same test for every point of the segment a-b.
func _hazard_near_segment(a: Vector2, b: Vector2, reach: float) -> bool:
	if not sim.env.enabled or (sim.arena.hazards.is_empty() and sim.arena.gates.is_empty()):
		return false
	_refresh_hazard_bounds()
	if _haz_unbounded:
		return true
	var pad: float = reach * 1.415
	if _haz_bounds_near_segment(a, b, pad):
		return true
	for h: Dictionary in _haz_rings:
		# The farthest point of a segment from a centre is one of its ends.
		var c2: Vector2 = h.center
		if maxf(a.distance_to(c2), b.distance_to(c2)) + reach >= Arena.ring_radius_at(h, sim.time + _RING_LOOK) - 4.0:
			return true
	for s: Dictionary in sim.env.strikes:
		var sp: Vector2 = s.pos
		if Geometry2D.get_closest_point_to_segment(sp, a, b).distance_to(sp) <= float(s.radius) + reach + 4.0:
			return true
	return false


# Always-on damage fields (lava and any hazard flagged alwaysActive).
func _static_damage_at(p: Vector2, r: float) -> bool:
	if not _hazard_near(p, r):
		return false
	for h: Dictionary in sim.arena.hazards:
		if float(h.get("damage", 0.0)) <= 0.0:
			continue
		if not (bool(h.get("alwaysActive", false)) or str(h.get("type", "")) == "lava"):
			continue
		if Arena.shape_contains(h, p, r):
			return true
	return false


const _GOAL_TURNS: = [0.0, 0.785, -0.785, 1.571, -1.571, 2.356, -2.356, 3.1416]
const _GOAL_RINGS: = [36.0, 72.0, 120.0, 180.0]


func _hazard_free_goal(u: BUnit, p: Vector2, r: float) -> Vector2:
	if not _static_damage_at(p, r):
		return p
	var base: float = (u.pos - p).angle() if u.pos.distance_squared_to(p) > 1.0 else 0.0
	for rad: float in _GOAL_RINGS:
		# Nearest dry spot to the hero on the smallest ring that has one; the
		# distance test keeps mirrored teams from preferring one turn direction.
		var best: Vector2 = Vector2.INF
		var best_d: float = INF
		for turn: float in _GOAL_TURNS:
			var q: Vector2 = sim.arena.resolve_circle(p + Vector2.from_angle(base + turn) * rad, r)
			if not _static_damage_at(q, r):
				var dq: float = q.distance_squared_to(u.pos)
				if dq < best_d - 0.01:
					best_d = dq
					best = q
		if best.is_finite():
			return best
	return p


# Expected hazard damage walking the straight segment to `p` (sampled at the
# time each part is crossed) plus a short stay at the goal on arrival.
func _route_hazard_cost(u: BUnit, p: Vector2, r: float, ms: float) -> float:
	if not _hazard_near_segment(u.pos, p, r + 2.0):
		return 0.0
	var env: ArenaEnv = sim.env
	var d: float = u.pos.distance_to(p)
	var cost: float = 0.0
	if d > 24.0:
		var n: int = clampi(int(d / 60.0), 1, 5)
		var seg_t: float = d / float(n) / ms
		for k in n:
			var f: float = (float(k) + 0.5) / float(n)
			cost += env.expected_hazard_damage(u.pos.lerp(p, f), sim.time + d * f / ms, r, seg_t, u)
	cost += env.expected_hazard_damage(p, sim.time + d / ms, r, 1.0, u) * 0.5
	return cost * 0.9


# World tree passive (kits.gd _seed): a seed every 24 walked; a loop closes when
# the newest segment crosses an earlier one or returns within 28 of seed 0.
# V1.5.3 (audit world_tree): the loop anchor is fixed when the loop starts, the
# waypoint advances by angular progress around it, and the walk overshoots its
# own start so the path crosses itself; the plan ends on a new garden, a path
# reset (dash) or a timeout. The circle is sized to the injured allies.
func _grove_points(u: BUnit, ctx: Dictionary, pts: Array) -> void :
	var m: Dictionary = mem.get(u.idx, {})
	var loop: Dictionary = m.get("grove", {})
	# Need that a garden here could serve: allies within 420 (self at 45%).
	var injured: = 0.0
	for x in [u] + (ctx.allies as Array):
		var bx0: BUnit = x
		if bx0 == u or bx0.pos.distance_to(u.pos) <= 420.0:
			injured += (sim.max_hp(bx0) - bx0.hp) * (0.45 if bx0 == u else 1.0)
	var gardens: = 0
	var newest: float = -1.0
	for g in sim.gardens:
		if g.source == u.idx and float(g.end) > sim.time:
			gardens += 1
			newest = maxf(newest, float(g.start))
	var seeds: Array = u.ks.get("seeds", [])
	if not loop.is_empty():
		var closed: bool = newest >= float(loop.t0)
		var expired: bool = sim.time - float(loop.t0) > float(loop.limit)
		var broken: bool = bool(loop.started) and seeds.size() <= 1 and sim.time - float(loop.start_t) > 0.6
		# The injured allies it was drawn around walked away before the first
		# half was done: a garden there would close empty.
		var deserted: bool = float(loop.get("prog", 0.0)) < PI and not (loop.get("who", []) as Array).is_empty()
		if deserted:
			for k in (loop.get("who", []) as Array):
				var wx: BUnit = sim.u_at(int(k))
				if wx and wx.alive and wx.pos.distance_to(loop.c) <= float(loop.r) + 180.0:
					deserted = false
					break
		if closed or expired or broken or deserted:
			loop = {}
	if loop.is_empty():
		loop = _grove_plan(u, ctx)
		if loop.is_empty():
			m.erase("grove")
			mem[u.idx] = m
			return
	var c: Vector2 = loop.c
	var lr: float = float(loop.r)
	var sgn: float = float(loop.sgn)
	var rel: Vector2 = u.pos - c
	var target: Vector2 = c + Vector2.from_angle(float(loop.a0)) * lr
	if not bool(loop.started):
		if u.pos.distance_to(target) <= 20.0 or (absf(rel.length() - lr) < 12.0 and u.pos.distance_to(target) < lr):
			loop.started = true
			loop.start_t = sim.time
			loop.prev = rel.angle()
			loop.prog = 0.0
			loop.a_start = rel.angle()
	if bool(loop.started):
		var ang: float = rel.angle() if rel.length_squared() > 1.0 else float(loop.prev)
		loop.prog = float(loop.prog) + wrapf(ang - float(loop.prev), -PI, PI) * sgn
		loop.prev = ang
		var lead: float = clampf(46.0 / lr, 0.45, 1.1)
		if float(loop.prog) >= TAU - lead:
			# Overshoot past the start so the last segment crosses the first.
			target = c + Vector2.from_angle(float(loop.a_start) + sgn * (TAU + 0.45)) * lr
		else:
			target = c + Vector2.from_angle(ang + sgn * lead) * lr
	m["grove"] = loop
	mem[u.idx] = m
	# Trees (S1) and flowers (S4) heal far more than a garden: the walk must
	# not outbid them or pull the tree away from the allies they need.
	# A half-walked loop is close to paying off: finishing it weighs more.
	var done: float = clampf(float(loop.get("prog", 0.0)) / TAU, 0.0, 1.0)
	var bonus: float = 12.0 + minf(injured, 500.0) * 0.1 + done * done * 64.0 - gardens * 10.0
	if float(ctx.danger) > float(ctx.ehp) * 0.4:
		bonus *= 0.5
	# A ready tree (S1) or flower (S4) with an injured ally near is worth
	# more than the walk: stay close enough to cast them first.
	var casts_ready: bool = false
	for si in [0, 3]:
		if si < u.def.abilities.size() and sim.ability_ready(u, si, u.def.abilities[si]):
			casts_ready = true
	if casts_ready:
		for x2 in ctx.allies:
			var ax: BUnit = x2
			if sim.hp_ratio(ax) < 0.8 and ax.pos.distance_to(u.pos) < 320.0:
				bonus *= 0.5
				break
	pts.append([target, "재생 폐곡선", bonus])


func _grove_plan(u: BUnit, ctx: Dictionary) -> Dictionary:
	var r: float = sim.radius(u)
	var c: Vector2 = Vector2.ZERO
	var w: float = 0.0
	var who: Array = []
	var self_in: bool = false
	for x in [u] + (ctx.allies as Array):
		var bx: BUnit = x
		if bx != u and bx.pos.distance_to(u.pos) > 420.0:
			continue
		var miss: float = sim.max_hp(bx) - bx.hp
		if miss < maxf(40.0, sim.max_hp(bx) * (0.12 if bx == u else 0.1)):
			continue
		if bx == u:
			self_in = true
			continue
		who.append(bx.idx)
		c += bx.pos * miss
		w += miss
	if w <= 0.0 and not self_in:
		# Nobody needs healing: a garden would only burn its 14 s.
		return {}
	var ec0: Vector2 = plan.get("enemy_c", u.pos)
	var away0: Vector2 = (u.pos - ec0).normalized() if u.pos.distance_squared_to(ec0) > 1.0 else Vector2.LEFT
	var base_r: float = 36.0
	if w > 0.0:
		# Around the injured allies, who step to the centre and wait there
		# (Doctrine "폐곡선 안에서 대기"). The tree keeps the steering separation
		# (bodies + 16) from them, so the circle must clear about 60.
		c /= w
		var spread: float = 0.0
		for k in who:
			spread = maxf(spread, sim.u_at(int(k)).pos.distance_to(c))
		base_r = clampf(60.0 + spread * 0.2, 60.0, 72.0)
	else:
		# Only the tree is hurt: a small, quick loop just behind itself (it
		# steps inside afterwards through the "재생 영역 안으로" point).
		c = u.pos + away0 * base_r
	var enemy_c: Vector2 = plan.get("enemy_c", c)
	# Hazard/wall-aware: the first circle whose sample points are walkable.
	var options: Array = [[c, base_r], [c, maxf(34.0, base_r * 0.85)], [c.lerp(u.pos, 0.5), maxf(34.0, base_r * 0.9)]]
	for opt in options:
		var oc: Vector2 = opt[0]
		var orr: float = opt[1]
		var bad: int = 0
		for k in 10:
			var p: Vector2 = oc + Vector2.from_angle(k * TAU / 10.0) * orr
			if not sim.arena.is_walkable(p, r) or (_env_live() and sim.env.hazard_penalty(p, sim.time + 2.0, r) > 0.25):
				bad += 1
		if bad <= 1:
			var a0: float = (u.pos - oc).angle() if u.pos.distance_squared_to(oc) > 1.0 else (oc - enemy_c).angle()
			# Walk the half of the circle that faces away from the enemy first.
			var sgn: float = -1.0 if (u.pos - oc).cross(enemy_c - oc) > 0.0 else 1.0
			var approach: float = maxf(0.0, u.pos.distance_to(oc) - orr)
			var ms: float = maxf(30.0, float(ctx.ms))
			return {"c": oc, "r": orr, "a0": a0, "sgn": sgn, "t0": sim.time, "started": false, "start_t": 0.0,
				"prev": a0, "prog": 0.0, "a_start": a0, "limit": (TAU * orr + approach) / ms + 3.5, "who": who, "self": self_in}
	return {}






# ------------------------------------------------------------ V1.5.3 gimmick AI
# DESIGN_153 §4 "Gimmick AI". Public map state only (gate clocks, the ring
# radius, announced artillery telegraphs, pad / portal / mud / brush geometry)
# plus this team's own belief particles for brush caution. Gates and links are
# routed in _route_waypoint / _link_soft_walls, artillery is dodged through the
# public telegraphs (intel.observe_fast -> danger_at / _dodge_vector).
var _gim_arena: Arena = null
var _gim_ring: Dictionary = {}
var _gim_mud: Array = []
var _gim_links: Array = []
var _gim_link_bounds: PackedVector3Array = PackedVector3Array()
# Brush the hidden enemies' particles sit in: [{c, rad, mass, idx, reach,
# threat}], rebuilt every plan (team modes; deathmatch forests are handled by
# DeathmatchBrain's hide / escape points).
var _brush_threats: Array = []
var _front_cache: Dictionary = {}


func _refresh_gimmicks() -> void:
	if _gim_arena == sim.arena:
		return
	_gim_arena = sim.arena
	_gim_ring = {}
	_gim_mud = []
	_gim_links = []
	_gim_link_bounds = PackedVector3Array()
	_front_cache.clear()
	for h: Dictionary in sim.arena.hazards:
		match str(h.get("type", "")):
			"closing_ring":
				if _gim_ring.is_empty():
					_gim_ring = h
			"mud":
				_gim_mud.append(h)
			"portal", "jump_pad":
				_gim_links.append(h)
				_gim_link_bounds.append(Vector3((h.center as Vector2).x, (h.center as Vector2).y, float(h.get("radius", 30.0))))


func _ring_def() -> Dictionary:
	_refresh_gimmicks()
	if _gim_ring.is_empty() or not sim.env.type_active("closing_ring"):
		return {}
	return _gim_ring


func _gimmick_goals_live() -> bool:
	if not sim.env.enabled:
		return false
	_refresh_gimmicks()
	return not _gim_ring.is_empty() or not _gim_mud.is_empty() or not _gim_links.is_empty() or not sim.arena.gates.is_empty() or not sim.env.strikes.is_empty()


# A move goal the gimmicks would spoil, moved to where it still works:
#  - closing ring: inside the circle that is still safe when the hero gets
#    there (+2 s), never outside it (fights stay inside, the outside is left
#    early);
#  - gate frames: off a gate that is closed or closes before the hero could
#    stand there for 2.5 s (never wait in a closing gate);
#  - portal / jump-pad triggers it is not deliberately taking: onto the rim.
func _gimmick_safe_goal(u: BUnit, p: Vector2, r: float, ms: float) -> Vector2:
	var q: Vector2 = p
	var eta: float = u.pos.distance_to(q) / maxf(40.0, ms)
	var ring: Dictionary = _ring_def()
	if not ring.is_empty():
		var at: float = sim.time + eta + 2.0
		if Arena.ring_active(ring, at + 2.0):
			var c: Vector2 = ring.center
			# Once the ring holds its final radius the edge no longer moves:
			# a thinner margin keeps the final zone usable (bastion_ring's
			# centre shockwave reaches almost to the final circle).
			var settled: bool = at + 2.0 >= float(ring.get("endTime", 0.0))
			var safe_r: float = maxf(0.0, Arena.ring_radius_at(ring, at + 2.0) - r * 0.3 - (10.0 if settled else 24.0))
			if q.distance_to(c) > safe_r:
				q = sim.arena.resolve_circle(c + (q - c).normalized() * safe_r if q.distance_squared_to(c) > 1.0 else c, r)
	if not sim.arena.gates.is_empty() and sim.env.type_active("gate"):
		for g: Dictionary in sim.arena.gates:
			var rect: Rect2 = (g.rect as Rect2).grow(r + 4.0)
			if not rect.has_point(q):
				continue
			var clk: Dictionary = Arena.gate_clock(g, sim.time + eta)
			if bool(clk.open) and float(clk.remaining) > 2.5:
				continue
			var gc: Vector2 = rect.get_center()
			if rect.size.x <= rect.size.y:
				q.x = (rect.position.x - 2.0) if u.pos.x < gc.x else (rect.end.x + 2.0)
			else:
				q.y = (rect.position.y - 2.0) if u.pos.y < gc.y else (rect.end.y + 2.0)
			q = sim.arena.resolve_circle(q, r)
	# Announced artillery strikes landing before the hero could leave the
	# goal again: the goal moves to the rim of the strike circle.
	for st: Dictionary in sim.env.strikes:
		var sp: Vector2 = st.pos
		var sr: float = float(st.radius) + r * ArenaEnv.STRIKE_BODY_FACTOR + 8.0
		var dq: float = q.distance_to(sp)
		if dq < sr and float(st.impact_t) <= sim.time + eta + 0.8:
			var sdir: Vector2 = (q - sp) / dq if dq > 0.5 else (u.pos - sp).normalized()
			q = sim.arena.resolve_circle(sp + sdir * sr, r)
	# Packed circles first (this runs for every move point of every decision).
	for k in _gim_link_bounds.size():
		var lb: Vector3 = _gim_link_bounds[k]
		var lc: Vector2 = Vector2(lb.x, lb.y)
		var trig: float = lb.z + r * 0.28 + Navigator.LINK_RIM
		var dl: float = q.distance_to(lc)
		if dl < trig:
			var h2: Dictionary = _gim_links[k]
			if str(h2.id) == str(_taking_link.get(u.idx, "")) or (sim.env.disabled_mask & int(h2.get("tbit", 0))) != 0:
				continue
			var dir: Vector2 = (q - lc) / dl if dl > 0.5 else (u.pos - lc).normalized()
			q = sim.arena.resolve_circle(lc + dir * trig, r)
	return q


# Mud (DESIGN_153 §1.6): the navigator weights mud cells x1.6 for routing; a
# goal reached through mud also loses tempo, and kiting through it (retreats,
# range keeping, sidesteps) hands the chaser free hits.
func _mud_cost(u: BUnit, p: Vector2, r: float, kiting: bool) -> float:
	if _gim_mud.is_empty() or not sim.env.type_active("mud") or float(cfg.get("gmd", 1.0)) < 0.5:
		return 0.0
	# V2 (B-PERF2): the samples lie on the segment u.pos -> p, so a mud patch
	# whose padded box misses the segment's box cannot contain any of them
	# (exact pre-test; shape_contains decides the rest unchanged).
	var pad: float = r * 0.28 + 1.0
	var lo: Vector2 = Vector2(minf(u.pos.x, p.x) - pad, minf(u.pos.y, p.y) - pad)
	var hi: Vector2 = Vector2(maxf(u.pos.x, p.x) + pad, maxf(u.pos.y, p.y) + pad)
	var boxes: PackedFloat64Array = _mud_boxes()
	var touch: PackedByteArray = PackedByteArray()
	touch.resize(_gim_mud.size())
	var any: bool = false
	for k in _gim_mud.size():
		if boxes[k * 4] <= hi.x and boxes[k * 4 + 1] >= lo.x and boxes[k * 4 + 2] <= hi.y and boxes[k * 4 + 3] >= lo.y:
			touch[k] = 1
			any = true
	if not any:
		return 0.0
	var slow: float = 0.0
	for f: float in [0.34, 0.67, 1.0]:
		var q: Vector2 = u.pos.lerp(p, f)
		var worst: float = 0.0
		for k2 in _gim_mud.size():
			if touch[k2] == 0:
				continue
			var h: Dictionary = _gim_mud[k2]
			if Arena.shape_contains(h, q, r * 0.28):
				worst = maxf(worst, clampf(float(h.get("slow", 0.3)), 0.0, 0.6))
		slow += worst
	if slow <= 0.0:
		return 0.0
	slow /= 3.0
	return slow * (u.pos.distance_to(p) * 0.08 + 14.0) * (2.0 if kiting else 1.0)


func _gimmick_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	if not sim.env.enabled or u.chamber != "":
		return
	if float(cfg.get("grg", 1.0)) > 0.5:
		_ring_points(u, ctx, pts)
	if not sim.is_deathmatch() and float(cfg.get("gbr", 1.0)) > 0.5:
		_brush_points(u, ctx, pts)


# Closing ring: leave the zone the ring will cover before it gets there.
# The walk is timed along the navigator route (bastion_ring: the way in is
# through four gaps in a stone circle), toward the circle that is still safe
# on arrival (+3 s). Urgent once the hero already takes ring damage.
func _ring_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	_v2_ring_points(u, ctx, pts)

# Absolute time at which the safe radius shrinks to `radius` (INF if never).
func _ring_time_reaching(ring: Dictionary, radius: float) -> float:
	var r0: float = float(ring.get("startRadius", 900.0))
	var r1: float = float(ring.get("endRadius", 200.0))
	var t0: float = float(ring.get("startTime", 60.0))
	var t1: float = maxf(t0, float(ring.get("endTime", t0 + 30.0)))
	if radius >= r0:
		return t0
	if radius <= r1 or r0 - r1 < 1e-6:
		return INF
	return t0 + (r0 - radius) / (r0 - r1) * (t1 - t0)


# Candidate notes for the gimmicks: fighting on from outside the ring (or
# from where it arrives within a second) costs ring damage every tick.
func _gimmick_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	if not sim.env.enabled or float(cfg.get("grg", 1.0)) < 0.5:
		return
	var ring: Dictionary = _ring_def()
	if ring.is_empty() or not Arena.ring_outside(ring, u.pos, sim.time + 1.0, -float(ctx.r) * 0.3):
		return
	var dps: float = Arena.ring_damage_fraction(ring) * float(ctx.mx) / maxf(0.2, float(ring.get("tickInterval", 1.0)))
	var r: float = float(ctx.r)
	var abilities: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)
	for item in cands:
		var c: Dictionary = item
		if str(c.cmd.get("kind", "")) == "move":
			continue
		if float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0:
			continue
		# Review 1.5.3: a blink, dash, glide or flight that lands back inside
		# the ring is the way out, not fighting on from outside (its danger
		# gain already prices the ring ticks it avoids).
		if str(c.cmd.get("kind", "")) == "ability":
			var dest: Vector2 = _relocation_dest(u, c.cmd, abilities, r)
			if dest.is_finite() and not Arena.ring_outside(ring, dest, sim.time + 1.0, r * 0.3):
				continue
		Doctrine._note(c, -dps * 1.2 * float(ctx.risk_w), "결계 밖 교전 자제")


# Where an ability order leaves the caster (INF when it does not move it, or
# the end point is not known in advance, e.g. a wall run).
func _relocation_dest(u: BUnit, cmd: Dictionary, abilities: Array, r: float) -> Vector2:
	var ix: int = int(cmd.get("index", -1))
	if ix < 0 or ix >= abilities.size():
		return Vector2.INF
	var a: Defs.AbilityDef = abilities[ix]
	var p: Vector2 = cmd.get("pos", u.pos)
	match a.action:
		"pointBlink":
			var delta: Vector2 = p - u.pos
			return u.pos + delta.limit_length(a.range) if delta.length_squared() > 1.0 else Vector2.INF
		"glide":
			var ge: TeamIntel.EnemyBelief = intel.enemies.get(int((mem.get(u.idx, {}) as Dictionary).get("glide_target", -1)))
			return ge.pos if ge and not ge.dead else Vector2.INF
		"rescueFlight":
			var ally: BUnit = sim.u_at(int(cmd.get("target", -1)))
			return ally.pos if ally and ally.alive and sim.eteam(ally) == team else Vector2.INF
		"portalPair":
			var extra: Dictionary = cmd.get("extra", {})
			return extra.get("portal_b", Vector2.INF)
	var tgt: int = int(cmd.get("target", -1))
	if a.action == "contactDash":
		return _landing_point(u, a, intel.enemies[tgt], p, r) if intel.enemies.has(tgt) else Vector2.INF
	var f: Dictionary = _ability_flags(a)
	if not bool(f.move_self) or bool(f.recoil):
		return Vector2.INF
	if str(f.landing) in ["at", "behind", "dash"] and intel.enemies.has(tgt):
		return _landing_point(u, a, intel.enemies[tgt], p, r)
	if str(f.landing) == "dash":
		return u.pos + (p - u.pos).normalized() * float(f.land_dist) if p.distance_squared_to(u.pos) > 1.0 else Vector2.INF
	return p if p.distance_squared_to(u.pos) > 1.0 else Vector2.INF


# Brush (수풀) in team modes:
#  - "수풀 확인": a sturdy hero (tank or the team scout) steps within reveal
#    range of brush the hidden enemies' particles sit in, instead of the
#    team walking past it (danger_at prices that brush meanwhile);
#  - "수풀 매복": brush on the side of an approaching enemy (not on top of it)
#    to wait in, mostly for melee heroes;
#  - "수풀 대기": hold an ambush while nobody has found us yet.
# Every bonus fades with plan.stale / plan.nokill, so two teams hiding in
# brush cannot run a battle into the time limit.
func _brush_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var ar: Arena = sim.arena
	if not sim.brush_on or ar.forest_x.is_empty():
		return
	var stance: String = str(plan.stance)
	if stance == "DISENGAGE":
		return
	var calm: float = (1.0 - float(plan.get("stale", 0.0))) * (1.0 - float(plan.get("nokill", 0.0)))
	if calm <= 0.2:
		return
	var r: float = ctx.r
	var sturdy: bool = bool(aprof.get(u.idx, {}).get("tank", false)) or int(plan.get("scout", -1)) == u.idx
	if sturdy and float(ctx.hpr) > 0.5:
		for bz: Dictionary in _brush_threats:
			var bc: Vector2 = bz.c
			var dc: float = u.pos.distance_to(bc)
			if dc > 620.0 or dc < 60.0:
				continue
			var look: Vector2 = bc + (u.pos - bc).normalized() * (float(bz.rad) + 70.0)
			pts.append([look, "수풀 확인", (10.0 + 26.0 * float(bz.mass)) * calm])
	var visible_close: bool = false
	var approach: TeamIntel.EnemyBelief = null
	var ad: float = INF
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if not eb.is_hero or eb.controlled_by_us:
			continue
		var de: float = u.pos.distance_to(eb.pos)
		if eb.visible and de < float(ctx.range) + r + eb.radius + 60.0:
			visible_close = true
		if (eb.visible or eb.confidence > 0.35) and de < ad:
			ad = de
			approach = eb
	if visible_close or approach == null or ad > 760.0:
		return
	var here: int = ar.forest_at(u.pos)
	if here >= 0 and stance in ["POKE", "SCOUT"]:
		pts.append([u.pos, "수풀 대기", 12.0 * calm])
	var melee: bool = float(ctx.pref) < 110.0
	var to_e: Vector2 = (approach.pos - u.pos).normalized()
	for k in ar.forest_x.size():
		if ar.forest_patch[k] == here:
			continue
		var fc: Vector2 = Vector2(ar.forest_x[k], ar.forest_y[k])
		if u.pos.distance_to(fc) > 340.0 or (fc - u.pos).dot(to_e) < -30.0:
			continue
		var fe: float = fc.distance_to(approach.pos)
		if fe > 560.0 or fe < ar.forest_r[k] + 120.0 or _brush_suspect(fc):
			continue
		pts.append([fc, "수풀 매복", (18.0 if melee else 9.0) * calm])


func _brush_suspect(p: Vector2) -> bool:
	for bz: Dictionary in _brush_threats:
		if float(bz.mass) > 0.25 and (bz.c as Vector2).distance_to(p) < 90.0:
			return true
	return false


# Once per plan: where the hidden enemies' particles (forest-aware filter,
# D13) concentrate inside brush. Only our own beliefs; nothing about the true
# positions.
func _update_brush_threats() -> void:
	_brush_threats.clear()
	var ar: Arena = sim.arena
	if not sim.brush_on or ar.forest_x.is_empty() or sim.is_deathmatch() or float(cfg.get("gbr", 1.0)) < 0.5:
		return
	var ac: Vector2 = Vector2.ZERO
	var n: int = 0
	for a in sim.allies_of(team):
		if a.team == team:
			ac += a.pos
			n += 1
	if n == 0:
		return
	ac /= float(n)
	for b in intel.alive_enemies():
		var eb: TeamIntel.EnemyBelief = b
		if eb.visible or eb.controlled_by_us or not eb.is_hero or eb.pos.distance_to(ac) > 1300.0:
			continue
		var mass: Dictionary = {}
		var cen: Dictionary = {}
		for i in range(0, intel.n_part, 2):
			var q: Vector2 = eb.particles[i]
			var patch: int = ar.forest_at(q)
			if patch < 0:
				continue
			var w: float = float(eb.weights[i]) * 2.0
			mass[patch] = float(mass.get(patch, 0.0)) + w
			cen[patch] = (cen.get(patch, Vector2.ZERO) as Vector2) + q * w
		if mass.is_empty():
			continue
		var pr: Dictionary = eprof.get(eb.idx, {})
		for patch in mass:
			var m: float = float(mass[patch])
			if m < 0.15:
				continue
			_brush_threats.append({"c": (cen[patch] as Vector2) / m, "rad": 50.0, "mass": minf(1.0, m), "idx": eb.idx,
				"reach": float(pr.get("reach", 200.0)), "threat": float(pr.get("dps", 60.0)) + float(pr.get("burst", 0.0)) * 0.35})


# Front goals follow the walking route toward the enemy (map-agent follow-up,
# furnace_basin 156117): a straight step parked both teams on either side of
# body-only barriers (chasms, hedges) out of range. Retreat steps stay
# straight back. Routes are straightened to corners (_taut_path) so mirrored
# teams get mirrored fronts.
func _front_point(ac: Vector2, ec: Vector2, to_enemy: Vector2, step: float) -> Vector2:
	var a: Vector2 = sim.arena.resolve_circle(ac, 20.0)
	if step <= 0.0 or a.distance_to(ec) < 24.0:
		return sim.arena.resolve_circle(ac + to_enemy * step, 20.0)
	var nav: Navigator = navigator_for(20.0)
	if nav.clear(a, ec, 20.0):
		return sim.arena.resolve_circle(a + (ec - a).normalized() * step, 20.0)
	_refresh_gimmicks()
	var key: Vector3i = Vector3i(int(a.x / 32.0) * 4096 + int(a.y / 32.0), int(ec.x / 32.0) * 4096 + int(ec.y / 32.0), sim.arena.nav_sig)
	var hit: Dictionary = _front_cache.get(key, {})
	var path: PackedVector2Array
	if not hit.is_empty() and float(hit.until) > sim.time:
		path = hit.path
	else:
		path = _taut_path(nav, a, ec, nav.path_points(a, ec), 20.0)
		if _front_cache.size() > 8:
			_front_cache.clear()
		_front_cache[key] = {"path": path, "until": sim.time + 1.0}
	return sim.arena.resolve_circle(_along_route(a, ec, path, step), 20.0)


# Called by the executor every tick an ability order waits. The returned aim
# decides whether the cast starts now (the executor refuses aims beyond range
# + 8), so "not yet" is expressed by an aim outside that range while steer
# keeps closing in.
func refine_aim(u: BUnit, a: Defs.AbilityDef, t: BUnit, aim: Vector2) -> Vector2:
	if t == null or a.target != "enemy":
		return aim
	var b: TeamIntel.EnemyBelief = intel.enemies.get(t.idx)
	if b == null or not b.visible:
		return aim
	# Keep the team's reported position; using the unit here would bypass
	# political misinformation despite the rest of the planner honoring it.
	var r: = sim.radius(u)
	var toward: Vector2 = (b.pos - u.pos).normalized() if b.pos.distance_squared_to(u.pos) > 1.0 else u.facing
	var wait_aim: Vector2 = u.pos + toward * (a.range + r + 60.0)
	if a.action == "contactDash":
		# X2: dash only when the predicted contact lies inside the dash and the
		# body-wide corridor is clear.
		var dash: float = float(a.flag("originDistance", a.range))
		var pred: Vector2 = lead_point(u.pos, b, 0.0, a.cast_time + minf(dash, u.pos.distance_to(b.pos)) / maxf(50.0, a.speed), 1.0)
		var pd: float = u.pos.distance_to(pred)
		var contact: float = dash + r + b.radius - 6.0
		# Both where the target will be and where it is now must be in reach:
		# a prediction that it walks into the dash alone was a 38% whiff.
		if pd > contact or u.pos.distance_to(b.pos) > contact + 8.0 or sim.arena.segment_blocked(u.pos, pred, r, Arena.MASK_UNITS):
			return wait_aim
		return u.pos + (pred - u.pos).normalized() * minf(pd, a.range + r + 4.0) if pd > 0.5 else pred
	if a.delivery != "projectile":
		if a.delivery in ["cone", "line"]:
			return lead_point(u.pos, b, 0.0, a.cast_time, 0.8)
		# Direct effects land on the unit; check range against where it is now.
		return b.pos
	var proj_r: float = maxf(3.0, a.width * 0.5)
	if a.homing:
		# X3: homing shots still die on walls on the way.
		if a.bounces == 0 and sim.arena.segment_blocked(u.pos + toward * (r + 4.0), b.pos, proj_r, Arena.MASK_PROJECTILES):
			return wait_aim
		return b.pos
	# Telemetry #3: fire a skillshot only at a predicted point it can reach.
	var p: = lead_point(u.pos, b, a.speed, a.cast_time, 1.0 - 0.45 * b.dodge_rate())
	var reach: float = a.range + r
	var pd2: float = u.pos.distance_to(p)
	# The predicted point must be reachable, and the target must not still be
	# beyond reach now (an approach prediction alone missed most such shots).
	if pd2 > reach + b.radius * 0.5 or u.pos.distance_to(b.pos) > reach + b.radius + 8.0:
		return wait_aim
	if a.bounces == 0 and pd2 > r + 4.0 and sim.arena.segment_blocked(u.pos + (p - u.pos).normalized() * (r + 4.0), p, proj_r, Arena.MASK_PROJECTILES):
		return wait_aim
	if pd2 > reach:
		p = u.pos + (p - u.pos).normalized() * reach
	return p


func steer(u: BUnit) -> Vector2:
	var forced: BUnit = sim.forced_target(u)
	if forced:
		var forced_need: float = sim.stat(u, &"attackRange") + sim.radius(u) + sim.radius(forced)
		return Vector2.ZERO if u.pos.distance_to(forced.pos) < forced_need * 0.9 else (forced.pos - u.pos).normalized()
	# V2 scale (B-PERF2): a calm walker far from its goal keeps last tick's
	# steering on every other tick (_lod_steer_reuse).
	if sim.scale_lod:
		var kept: Vector2 = _lod_steer_reuse(u)
		if kept.is_finite():
			return kept
	var c: = u.command
	var r: = sim.radius(u)
	var goal: = u.pos
	var kind: = str(c.get("kind", "move"))
	var hold: = false
	if c.is_empty():
		# The executor voided the order (its enemy is not observed by this
		# hero); a fresh decision follows next tick. Nothing is written into the
		# voided order (audit D14).
		hold = true
	elif kind == "move":
		goal = c.get("goal", u.pos)
	else:
		var tgt: = sim.u_at(int(c.get("target", -1)))
		var need: = float(c.get("need", 60.0))
		var tp: Vector2 = c.get("pos", u.pos)
		var sees: bool = true
		if tgt and sim.eteam(tgt) != team:
			# Team belief only; a target that died unseen is not detected here.
			var eb: TeamIntel.EnemyBelief = intel.enemies.get(tgt.idx, intel.entities.get(tgt.idx))
			if eb and not eb.dead:
				tp = eb.pos
				if c.has("lead") and eb.visible:
					tp = lead_point(u.pos, eb, float(c.get("speed", 0.0)), float(c.get("cast", 0.0)), float(c.lead))
			sees = sim.observes(u, tgt)
		elif tgt and tgt.alive:
			tp = tgt.pos
		var d: = u.pos.distance_to(tp)
		if not sees:
			# X1: walk on toward the target to regain sight; never hold behind cover.
			goal = tp
		elif need <= 1.0 or d <= need * 0.92:
			hold = true
			goal = u.pos
		else:
			goal = tp + (u.pos - tp).normalized() * (need * 0.85)
	# D10: during a glide (own kit clock) fly at the enemy it was launched at,
	# aimed where it will be when the glide lands (prediction refreshed every tick).
	if _glide_to.has(u.idx) and float(u.ks.get("glide_until", -1.0)) > sim.time:
		var gb: TeamIntel.EnemyBelief = _glide_target(u)
		if gb:
			hold = false
			goal = lead_point(u.pos, gb, 0.0, maxf(0.05, float(u.ks.get("glide_until", 0.0)) - sim.time), 0.8)
	var v: = Vector2.ZERO
	if not hold:
		var wp: = _route_waypoint(u, goal, r)
		var dv: = wp - u.pos
		var dist: = u.pos.distance_to(goal)
		if not c.is_empty():
			c["arrive"] = dist
		if dist > 4.0:
			v = dv.normalized() * clampf(dist / 40.0, 0.25, 1.0)
	else:
		_taking_link.erase(u.idx)

	var env_live: bool = _env_live()
	# Audit C-2 / mode follow-up: a capture holder the objective planner
	# exempts (small hazards, a well centred in its circle) neither probes
	# ahead nor gets pushed out of its circle by the hazard escape below.
	var holder: bool = env_live and _holding_objective(u, r)
	var dodge: = _dodge_vector(u)
	if not hold and not holder and cfg.haz > 0.0 and env_live and v.length_squared() > 0.01 and dodge.length_squared() <= 0.0025:
		v = _hazard_lookahead(u, v, r)
	if dodge.length_squared() > 0.0025:
		v = v * 0.35 + dodge * 1.35
		var mm: Dictionary = mem.get(u.idx, {})
		mm["dodging"] = sim.time
		mem[u.idx] = mm

	# Politician contemplation (heroes-B follow-up 6): the kit needs 0.45 s
	# perfectly still, so while it holds on purpose only real body overlap or
	# wall contact may move it.
	var still: bool = kind == "move" and u.def.id == "politician" and goal.distance_to(u.pos) < 8.0 and dodge.length_squared() <= 0.0025
	# V2 (B-PERF2): a body farther than any `want` it could have (radius()
	# stays within BattleSim.radius_bounds) is skipped before the team test
	# (a status scan). Same bodies, same order, same sum.
	var reach_max: float = r + _hero_radius_max() + 17.0
	var reach_max2: float = reach_max * reach_max
	var near_d2: float = INF
	for a in sim.heroes:
		if a == u or not a.alive:
			continue
		var ad2: float = u.pos.distance_squared_to(a.pos)
		near_d2 = minf(near_d2, ad2)
		if ad2 >= reach_max2 or sim.eteam(a) != team:
			continue
		var off: = u.pos - a.pos
		var dd: = off.length()
		var want: = r + sim.radius(a) + (0.5 if still else 16.0)
		if dd < want and dd > 0.01:
			v += off / dd * (want - dd) / want * 0.6

	if not still or sim.arena.distance_to_wall(u.pos) < r + 1.0:
		v += sim.arena.avoidance_vector(u.pos, r, 34.0) * 0.25
	if env_live and not holder and _hazard_near(u.pos, r + 62.0):
		var here: = sim.env.hazard_penalty(u.pos, sim.time + 0.4, r)
		if here > 0.1:
			var best: = Vector2.ZERO
			var best_pen: = here
			for k in 8:
				var q: = u.pos + Vector2.from_angle(k * TAU / 8.0) * 60.0
				# Never escape into a wall (a pillar nearer the ring centre has no
				# ring penalty); the r * 0.9 pad keeps tangents along a wall open.
				if not sim.arena.is_walkable(q, r) or sim.arena.segment_blocked(u.pos, q, r * 0.9, Arena.MASK_UNITS):
					continue
				var pen: = sim.env.hazard_penalty(q, sim.time + 0.5, r)
				if pen < best_pen - 0.05:
					best_pen = pen
					best = (q - u.pos).normalized()
			v += best * 1.1
	if env_live and sim.arena.has_links and float(cfg.get("gsw", 1.0)) > 0.5:
		v = _link_soft_walls(u, v, r, goal)
	if env_live and not sim.arena.gates.is_empty() and float(cfg.get("ggt", 1.0)) > 0.5:
		v = _gate_walls(u, v, r, goal)
	if sim.scale_lod:
		var plain: bool = kind == "move" and not hold and not still and dodge.length_squared() <= 0.0025 and not _glide_to.has(u.idx)
		_lod_steer_store(u, v.limit_length(1.0), goal, plain and near_d2 > (reach_max + LOD_STEER_PAD) * (reach_max + LOD_STEER_PAD))
	return v.limit_length(1.0)


# Gates (DESIGN_153 §1.3): never stand in an open gate frame that closes
# within NAV_CLOSING_MARGIN + 0.3 s. Whatever the order (an ability approach
# may stop right there), the hero leaves across the gate's thin axis on the
# nearer side (the goal's side when centred); the generic hazard escape probes
# 60 px around and could pick the far side or a shockwave ring instead. Before
# that, the frame of a gate closing within 2.3 s is a soft wall: once the grid
# reroutes (closing gates count as closed), a goal behind the gate makes the
# navigator walk straight at it, and locomotion inertia carried heroes in.
const GATE_SOFT_WINDOW: = 2.3


func _gate_walls(u: BUnit, v: Vector2, r: float, goal: Vector2) -> Vector2:
	if not sim.env.type_active("gate"):
		return v
	var spd: float = maxf(40.0, sim.stat(u, BattleSim.S_MS))
	var look: float = clampf(spd * 0.55, 45.0, 100.0)
	for g: Dictionary in sim.arena.gates:
		var clk: Dictionary = Arena.gate_clock(g, sim.time)
		# A closed gate is a wall (bodies touching it are fine); only an open
		# one about to close traps whoever overlaps its frame.
		if not bool(clk.open) or float(clk.remaining) > GATE_SOFT_WINDOW:
			continue
		var rect: Rect2 = (g.rect as Rect2).grow(r + 3.0)
		var q: Vector2 = Vector2(clampf(u.pos.x, rect.position.x, rect.end.x), clampf(u.pos.y, rect.position.y, rect.end.y))
		var d: float = u.pos.distance_to(q)
		if d <= 0.01:
			if float(clk.remaining) > Arena.NAV_CLOSING_MARGIN + 0.3:
				continue
			return _gate_exit_dir(u, rect, goal) + v * 0.2
		if d > look:
			continue
		var n: Vector2 = (u.pos - q) / d
		var f: float = clampf((look - d) / (look * 0.6), 0.0, 1.0)
		var inward: float = -v.dot(n)
		if inward > 0.0:
			v += n * inward * f
		var coming: float = -u.vel.dot(n) / spd
		if coming > 0.0:
			v += n * coming * f * 0.8
	return v


func _gate_exit_dir(u: BUnit, rect: Rect2, goal: Vector2) -> Vector2:
	var c: Vector2 = rect.get_center()
	if rect.size.x <= rect.size.y:
		var lo: float = u.pos.x - rect.position.x
		var hi: float = rect.end.x - u.pos.x
		var side: float = -1.0 if lo < hi - 2.0 else (1.0 if hi < lo - 2.0 else signf(goal.x - c.x))
		return Vector2(side if side != 0.0 else 1.0, 0.0)
	var top: float = u.pos.y - rect.position.y
	var bottom: float = rect.end.y - u.pos.y
	var side_y: float = -1.0 if top < bottom - 2.0 else (1.0 if bottom < top - 2.0 else signf(goal.y - c.y))
	return Vector2(0.0, side_y if side_y != 0.0 else 1.0)


# Environment on and any public map cost to price (hazards or gates).
func _env_live() -> bool:
	return sim.env.enabled and (not sim.arena.hazards.is_empty() or not sim.arena.gates.is_empty())


# V1.5.3 gimmick AI: portals and jump pads are taken on purpose only. The
# link route must save LINK_SAVE of the walk (LINK_KEEP once chosen for the
# same goal), or the goal must be unreachable on foot. Otherwise the hero
# walks, and the trigger circles are soft walls (_link_soft_walls): the
# remaining "against the goal" trips of the engine probe came from combat
# moves brushing a trigger, and every trip re-planned the whole fight.
const LINK_SAVE: = 0.30
const LINK_KEEP: = 0.18
const LINK_MIN_DIST: = 200.0
var _taking_link: Dictionary = {}    # hero idx -> hazard id of the link it walks into


# Waypoint toward `goal`, reusing the last grid search for 0.1 s while the
# goal and the walker have barely moved (audit D5: A* ran every tick for
# every blocked hero). Clear straight lines are not cached (cheap to test).
# The grid follows the current gate state (gates closing within 1.5 s count
# as closed, Arena.nav_sig); a cached waypoint is dropped when it changes.
func _route_waypoint(u: BUnit, goal: Vector2, r: float) -> Vector2:
	var rc: Dictionary = _route_cache.get(u.idx, {})
	var sig: int = sim.arena.nav_sig
	if not rc.is_empty() and float(rc.until) > sim.time and int(rc.get("sig", 0)) == sig and (rc.goal as Vector2).distance_squared_to(goal) < 144.0 \
			and (rc.from as Vector2).distance_squared_to(u.pos) < 256.0 and (rc.wp as Vector2).distance_squared_to(u.pos) > 196.0:
		return rc.wp
	if sim.scale_lod and not rc.is_empty():
		var kept: Vector2 = _lod_route_reuse(u, goal, rc, sig)
		if kept.is_finite():
			return kept
	var nav: Navigator = navigator_for(r)
	if not sim.arena.gates.is_empty() and float(cfg.get("ggw", 1.0)) > 0.5:
		nav = _gate_timing_nav(u, nav, goal, r)
	var link: int = -1
	var wp: Vector2
	if float(cfg.get("glk", 1.0)) < 0.5:
		# Lab switch: geometric link routing, still priced with this hero's own
		# cooldowns (switched-off link types cost LINK_OFF).
		wp = nav.next_waypoint(u.pos, goal, r, sim.stat(u, BattleSim.S_MS), sim.env.portal_wait(u), sim.env.pad_wait(u), u.is_hero and sim.env.enabled)
	elif nav.links.is_empty() or not u.is_hero or not sim.env.enabled:
		wp = nav.next_waypoint(u.pos, goal, r, 0.0, 0.0, 0.0, false)
	else:
		link = _v2_arm_link_choice(u, nav, _v2_keep_link_choice(u, nav, _link_choice(u, nav, goal, r, rc), r), r)
		if link >= 0:
			wp = nav.next_waypoint(u.pos, nav.links[link].entry, r, 0.0, 0.0, 0.0, false)
		else:
			wp = nav.next_waypoint(u.pos, nav.outside_links(u.pos, goal, r), r, 0.0, 0.0, 0.0, false)
	if link >= 0:
		_taking_link[u.idx] = str(nav.links[link].hazard)
	else:
		_taking_link.erase(u.idx)
	if rc.is_empty():
		_route_cache[u.idx] = rc
	rc["link"] = link
	rc["link_goal"] = goal
	if wp.distance_squared_to(goal) > 1.0:
		rc["goal"] = goal
		rc["from"] = u.pos
		rc["wp"] = wp
		rc["sig"] = sig
		# Deathmatch keeps its V1.5.2 0.2 s reuse (12 walkers on large maps).
		rc["until"] = sim.time + (0.2 if sim.is_deathmatch() else 0.1)
	else:
		rc["until"] = -1.0
	if sim.scale_lod:
		_lod_route_store(u, goal, wp, rc, sig)
	return wp


# Gate timing (DESIGN_153 §4): when a gate opens within GATE_WAIT seconds and
# the route through it, plus the wait, beats the way around by 15 %, walk to
# the gate on the grid of that future state (the closed gate is a wall, so the
# hero waits at its face) instead of taking the long detour.
const GATE_WAIT: = 2.5


func _gate_timing_nav(u: BUnit, nav: Navigator, goal: Vector2, r: float) -> Navigator:
	var a: Arena = sim.arena
	if not sim.env.type_active("gate") or u.pos.distance_to(goal) < 250.0:
		return nav
	var future: int = a.gate_bits_at(sim.time + GATE_WAIT, Arena.NAV_CLOSING_MARGIN)
	if future == a.nav_sig or (future & ~a.nav_sig) == 0:
		return nav
	var now_len: float = nav.direct_length(u.pos, goal, r)
	var fnav: Navigator = Navigator.for_arena(a, r, future, sim.env.skip_mask())
	var f_len: float = fnav.direct_length(u.pos, goal, r)
	if f_len == INF:
		return nav
	var wait: float = INF
	for k in a.gates.size():
		if ((future >> k) & 1) == 1 and ((a.nav_sig >> k) & 1) == 0:
			var clk: Dictionary = Arena.gate_clock(a.gates[k], sim.time)
			wait = minf(wait, 0.0 if bool(clk.open) else float(clk.remaining))
	var ms: float = maxf(40.0, sim.stat(u, BattleSim.S_MS))
	var arrive: float = f_len / ms
	var cost: float = f_len + maxf(0.0, wait - arrive) * ms
	return fnav if now_len == INF or cost < now_len * 0.85 else nav


# Index into nav.links of the link this hero deliberately takes toward goal
# (-1 = walk). Uses its speed and its OWN portal / pad cooldowns
# (ArenaEnv.portal_wait / pad_wait; switched-off types never qualify).
func _link_choice(u: BUnit, nav: Navigator, goal: Vector2, r: float, rc: Dictionary) -> int:
	if u.pos.distance_to(goal) < LINK_MIN_DIST:
		return -1
	var spd: float = sim.stat(u, BattleSim.S_MS)
	var pw: float = sim.env.portal_wait(u)
	var padw: float = sim.env.pad_wait(u)
	var direct: float = nav.direct_length(u.pos, goal, r)
	var k: int = nav.route_link(u.pos, goal, r, spd, pw, padw, direct)
	if k < 0:
		return -1
	if direct == INF:
		return k
	var total: float = nav._link_total(k, u.pos, goal, spd, pw, padw)
	var keep: bool = int(rc.get("link", -1)) == k and (rc.get("link_goal", Vector2.INF) as Vector2).distance_to(goal) < 80.0
	return k if total <= direct * (1.0 - (LINK_KEEP if keep else LINK_SAVE)) else -1


# Portal / jump-pad trigger circles as soft walls: the part of the steering
# that would carry the centre into a trigger it is not deliberately taking is
# removed, keeping the sideways part (and a slide around the rim toward the
# goal) so a walk past a portal never teleports the hero (engine follow-up).
# Locomotion has inertia (turn rate, braking), so the wall starts a braking
# distance out and also counters velocity already heading in.
func _link_soft_walls(u: BUnit, v: Vector2, r: float, goal: Vector2) -> Vector2:
	_refresh_gimmicks()
	# Braking look-ahead also expands the cheap near reject at high speed.
	var spd: float = maxf(40.0, sim.stat(u, BattleSim.S_MS))
	var look: float = maxf(clampf(spd * 0.55, 45.0, 100.0), _v2_stopping_distance(u) + 8.0)
	var near: bool = false
	for b: Vector3 in _gim_link_bounds:
		var rr: float = b.z + look + 4.0 + r
		if u.pos.distance_squared_to(Vector2(b.x, b.y)) < rr * rr:
			near = true
			break
	if not near:
		return v
	var taking: String = str(_taking_link.get(u.idx, ""))
	var mask: int = sim.env.disabled_mask
	for h: Dictionary in _gim_links:
		if (mask & int(h.get("tbit", 0))) != 0 or str(h.id) == taking:
			continue
		var c: Vector2 = h.center
		var trig: float = float(h.get("radius", 30.0)) + (r * 0.28 if str(h.type) == "portal" else 0.0) + 4.0
		var off: Vector2 = u.pos - c
		var d: float = off.length()
		if d > trig + look or d < 0.01:
			continue
		var n: Vector2 = off / d
		var f: float = clampf((trig + look - d) / (look * 0.6), 0.0, 1.0)
		var t: Vector2 = Vector2(-n.y, n.x)
		var side: float = signf(t.dot(goal - u.pos))
		if side == 0.0:
			side = 1.0 if (u.idx % 2) == 0 else -1.0
		var inward: float = -v.dot(n)
		if inward > 0.0:
			v += n * inward * f
			# Slide around the rim on the goal's side instead of stalling.
			v += t * side * inward * f * 0.6
		var coming: float = -u.vel.dot(n) / spd
		if coming > 0.0:
			v += n * coming * f * 1.6
		if d < trig + 3.0:
			v += n * 0.8
	return v


# Control-mode capture holders do not step out of their circle for a hazard
# the objective planner judges not worth leaving (ConquestCommander.hold_exempt:
# small damage, a gravity well centred in the circle; audit C-2). Leaving
# resets unfinished capture progress. Other planners keep the V1.5.3 rule
# (under 5% of max health per second).
func _holding_objective(u: BUnit, r: float) -> bool:
	if control_plan == null:
		return false
	if control_plan is ConquestCommander:
		return (control_plan as ConquestCommander).hold_exempt(u)
	var order: Dictionary = control_plan.intent(u)
	if order.is_empty() or str(order.get("heal_target", "")) != "" or not order.has("center"):
		return false
	if u.pos.distance_to(order.center) > float(order.get("radius", 0.0)) * 0.9:
		return false
	return sim.env.expected_hazard_damage(u.pos, sim.time, r, 1.0, u) < sim.max_hp(u) * 0.05


func _hazard_lookahead(u: BUnit, v: Vector2, r: float) -> Vector2:
	if not sim.env.enabled:
		return v
	# Every probe below stays within 130 px (+ body) of the hero.
	if not _hazard_near(u.pos, r + 134.0):
		return v
	var env: ArenaEnv = sim.env
	var spd: = maxf(40.0, sim.stat(u, &"moveSpeed"))
	var base: = v.normalized()
	var here: = env.hazard_penalty(u.pos, sim.time + 0.4, r)
	# Telemetry #4: probe the line ahead at three distances, each at the time
	# the hero would get there (the old single 72 px probe missed strips that
	# switch on a moment later and fields just beyond it).
	var ahead: = _line_penalty(u.pos, base, spd, r)
	if ahead <= 0.3 or ahead <= here + 0.1:
		return v
	var best_d: = Vector2.ZERO
	var best_s: = ahead
	var first: float = clampf(spd * float(_PROBE_TIMES[0]), 24.0, 130.0)
	for ang: float in _SIDE_TURNS:
		var d: = base.rotated(ang)
		# Review 1.5.3: a turn straight into a wall scored hazard-free (the line
		# probe stops at the first unwalkable point) and pinned heroes against
		# bastion_ring's pillars while the ring closed. Only open turns count.
		var q0: = u.pos + d * first
		if not sim.arena.is_walkable(q0, r) or sim.arena.segment_blocked(u.pos, q0, r * 0.9, Arena.MASK_UNITS):
			continue
		var sc: = _line_penalty(u.pos, d, spd, r) + (1.0 - cos(ang)) * 0.12
		if sc < best_s - 0.05:
			best_s = sc
			best_d = d
	if best_d != Vector2.ZERO and best_s < 0.25:
		return best_d * v.length()
	var tip: = u.pos + base * clampf(spd * 0.45, 30.0, 72.0)
	for dt: float in _WAIT_TIMES:
		if env.hazard_penalty(tip, sim.time + dt, r) < 0.2:
			return v * 0.12
	# Nothing ahead switches off soon (an always-on field): take the clearly
	# better side instead of walking on into it.
	if best_d != Vector2.ZERO and best_s < ahead - 0.2:
		return best_d * v.length()
	return v


const _PROBE_TIMES: = [0.3, 0.6, 1.0]
const _SIDE_TURNS: = [0.45, -0.45, 0.9, -0.9, 1.35, -1.35]
const _WAIT_TIMES: = [0.9, 1.6, 2.3]


func _line_penalty(from: Vector2, dir: Vector2, spd: float, r: float) -> float:
	var worst: = 0.0
	for tt: float in _PROBE_TIMES:
		var q: = from + dir * clampf(spd * tt, 24.0, 130.0)
		if not sim.arena.is_walkable(q, r):
			break
		worst = maxf(worst, sim.env.hazard_penalty(q, sim.time + tt + 0.15, r))
	return worst


func _environment_move_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	_prune_fountain_reservations()
	if not sim.env.enabled or u.chamber != "":
		return
	var destination: Vector2 = plan.get("front", u.pos)
	if control_plan:
		destination = control_plan.intent(u).get("goal", destination)
	elif self is DeathmatchBrain:
		destination = (self as DeathmatchBrain).intent.get("goal", destination)
	if not destination.is_finite():
		destination = u.pos
	var ring: Dictionary = _ring_def()
	for h: Dictionary in sim.arena.hazards:
		var type: String = str(h.type)
		if type not in ["haste", "healing_fountain"]:
			continue
		# Objective planners reserve shared fountains themselves. Avoid pulling
		# multiple defenders away from a capture through a separate local bonus.
		if type == "healing_fountain" and (control_plan or self is DeathmatchBrain):
			continue
		var p: Vector2 = h.center
		var distance: float = u.pos.distance_to(p)
		if distance > (600.0 if type == "healing_fountain" else 400.0):
			continue
		# A fountain / haste field the closing ring will cover on arrival is
		# not worth the walk (it would end at the ring edge, unused).
		if not ring.is_empty() and Arena.ring_outside(ring, p, sim.time + distance / maxf(40.0, float(ctx.ms)) + 2.0, -float(ctx.r)):
			continue
		var gain: float = sim.env.benefit_at(p, u)
		if gain <= 0.0:
			continue
		if type == "haste":
			var detour: float = distance + p.distance_to(destination) - u.pos.distance_to(destination)
			if detour > 100.0 or u.pos.distance_to(destination) < 80.0:
				continue
			pts.append([p, "가속 구역 경유", gain * 140.0 - detour * 0.12])
		elif float(ctx.hpr) < 0.8:
			var id: String = str(h.id)
			if fountain_reservations.has(id) and int(fountain_reservations[id].owner) != u.idx:
				continue
			pts.append([p, "공용 회복샘 접근", gain * 250.0 + (1.0 - float(ctx.hpr)) * 35.0, false, id])


func _prune_fountain_reservations() -> void:
	if not sim.env.enabled:
		fountain_reservations.clear()
		return
	if fountain_reservations.is_empty():
		return
	var ready: Dictionary = {}
	for pad: Dictionary in sim.env.public_fountains():
		if bool(pad.ready): ready[str(pad.id)] = true
	for id: String in fountain_reservations.keys():
		var reservation: Dictionary = fountain_reservations[id]
		var owner: BUnit = sim.u_at(int(reservation.owner))
		if not ready.has(id) or float(reservation.until) <= sim.time or owner == null or not owner.alive \
				or owner.chamber != "" or sim.hp_ratio(owner) >= 0.8 or str(owner.command.get("fountain_id", "")) != id:
			fountain_reservations.erase(id)


func _dodge_vector(u: BUnit) -> Vector2:
	var r: = sim.radius(u)
	var acc: = Vector2.ZERO
	for pj in intel.projectiles:
		var v: Vector2 = pj.vel
		var sp: = v.length()
		if sp < 1.0:
			continue
		var ppos: Vector2 = pj.pos
		var rel: = u.pos - ppos
		if pj.homing:
			continue
		if pj.explode:
			var tpos: Vector2 = pj.target_pos
			var ir: = float(pj.impact_r)
			if tpos.distance_to(u.pos) < ir + r + 6.0:
				var tt: = ppos.distance_to(tpos) / sp
				if tt < 1.4:
					acc += (u.pos - tpos).normalized() * (1.0 - tt / 1.4 + 0.3)
			continue
		var along: = rel.dot(v) / sp
		if along <= 0.0:
			continue
		var tca: = along / sp
		if tca > 1.3:
			continue
		var closest: = ppos + v * tca
		var miss: = closest.distance_to(u.pos)
		var need: = float(pj.radius) + r + 7.0
		if miss >= need:
			continue
		var perp: = Vector2( - v.y, v.x) / sp
		var side: = signf(perp.dot(u.pos - closest))
		if side == 0.0:
			side = 1.0 if (u.idx % 2) == 0 else -1.0

		var test: = u.pos + perp * side * 40.0
		if not sim.arena.is_walkable(test, r):
			side = - side
		var urg: = clampf(1.0 - tca / 1.3, 0.25, 1.0) * (0.6 + float(pj.dmg) / 140.0 + (0.8 if pj.cc else 0.0))
		acc += perp * side * urg
	for tg in intel.telegraphs:
		var due: = float(tg.due) - sim.time
		if due < 0.0 or not _in_telegraph(u.pos, r, tg):
			continue
		var esc: = Vector2.ZERO
		match str(tg.shape):
			"circle":
				esc = (u.pos - (tg.to as Vector2)).normalized()
			"self":
				esc = (u.pos - (tg.from as Vector2)).normalized()
			"line":
				var from: Vector2 = tg.from
				var dirl: Vector2 = ((tg.to as Vector2) - from).normalized()
				var perp2: = Vector2( - dirl.y, dirl.x)
				esc = perp2 * signf(perp2.dot(u.pos - from) + 0.01)
			"cone":
				var from2: Vector2 = tg.from
				var dirc: Vector2 = ((tg.to as Vector2) - from2).normalized()
				var p2: = Vector2( - dirc.y, dirc.x)
				esc = (p2 * signf(p2.dot(u.pos - from2) + 0.01) + dirc * 0.3).normalized()
		acc += esc * clampf(1.2 - due, 0.4, 1.3) * (0.8 + float(tg.dmg) / 150.0 + (0.6 if tg.cc else 0.0))

	for z in intel.zones:
		if not z.harm or z.kind in ["rift", "coin"]:
			continue
		var zp: Vector2 = z.pos
		if zp.distance_to(u.pos) < float(z.radius) + r:
			acc += (u.pos - zp).normalized() * 0.6
	return _v2_safe_dodge(u, (acc + _v2_skill_portal_avoidance(u)).limit_length(1.4))


# D11: the brain no longer cancels its own wind-ups. The cooldown is charged
# when a cast starts (sim.start_ability) and cancel_action refunds nothing, so
# every emergency cancel wasted the ability; the rule also never fired in 30
# audited matches. Escapes are chosen by decide() before committing instead.
func emergency(_u: BUnit) -> bool:
	return false


func reveal_choice(_u: BUnit) -> int:
	var best: = -1
	var best_v: = -1.0
	for k in intel.enemies:
		var b: TeamIntel.EnemyBelief = intel.enemies[k]
		if b.dead:
			continue
		var unknown: = 0.0
		for i in b.def.abilities.size():
			if (b.cd_disc_until < sim.time or b.cd_disc[i] < 0.0) and b.cd_last[i] < -100.0:
				unknown += 1.0
			elif b.cd_disc_t < b.cd_last[i]:
				unknown += 0.6
		var v: = unknown * float(eprof.get(k, {}).get("threat", 300.0))
		if v > best_v:
			best_v = v
			best = int(k)
	return best


func explain(u: BUnit) -> Dictionary:
	if _squad_mode() and squad_of.has(u.idx):
		var saved: Dictionary = plan
		plan = squad_plans.get(int(squad_of[u.idx]), plan)
		var out: Dictionary = _explain(u)
		plan = saved
		return out
	return _explain(u)


func _explain(u: BUnit) -> Dictionary:
	var m: Dictionary = mem.get(u.idx, {})
	var beliefs: Array = []
	for k in intel.enemies:
		var b: TeamIntel.EnemyBelief = intel.enemies[k]
		var cds: Array = []
		for i in b.def.abilities.size():
			cds.append({"name": (b.def.abilities[i] as Defs.AbilityDef).name, "p": intel.ready_prob(b, i), "seen": b.cd_last[i] > -100.0, "disc": b.cd_disc_until >= sim.time and b.cd_disc_t > b.cd_last[i] and b.cd_disc[i] >= 0.0})
		beliefs.append({"idx": b.idx, "name": b.def.name, "visible": b.visible, "dead": b.dead, "conf": b.confidence, 
			"pos": b.pos, "hp": b.hp, "max_hp": b.max_hp, "last_seen": b.last_seen_t, "cds": cds, "spread": b.spread, 
			"dodge": b.dodge_rate(), "particles": b.particles, "aggression": b.aggression, "strafe_bias": b.strafe_bias, "samples": b.movement_samples})
	var learned_aggression: float = 0.0
	var learned_strafe: float = 0.0
	var learned_count: int = 0
	for item in intel.enemies.values():
		var eb: TeamIntel.EnemyBelief = item
		if eb.movement_samples > 0:
			learned_aggression += eb.aggression
			learned_strafe += eb.strafe_bias
			learned_count += 1
	return {"stance": plan.get("stance", ""), "adv": plan.get("adv", 0.0), "focus": plan.get("focus", -1), 
		"top": m.get("top", []), "danger": m.get("danger", 0.0), "beliefs": beliefs, "label": label, 
		"purpose": u.command.get("purpose", ""), "casts_seen": intel.casts_observed, "anon": intel.anonymous_hits, "disc": intel.disclosures, 
		"doctrine": Doctrine.of(u.def.id), "role": role_of(u.idx), "control": control_plan.explain(u) if control_plan else {},
		"coordination": {"risk_budget": plan.get("risk_budget", 0.4), "uncertainty": plan.get("uncertainty", 0.0), "gamble": plan.get("gamble", false), "committed_damage": reserved.duplicate(), "scout": plan.get("scout", -1)},
		"learning": {"observations": intel.learning_observations, "focus_target": plan.get("learned_focus", -1), "focus_confidence": plan.get("focus_confidence", 0.0), "aggression": learned_aggression / maxf(1, learned_count), "strafe_bias": learned_strafe / maxf(1, learned_count)}}



func role_of(idx: int) -> String:
	var rs: Array = []
	if int(plan.get("carry", -1)) == idx:
		rs.append("주 화력")
	if int(plan.get("engage_lead", -1)) == idx:
		rs.append("개전")
	if (plan.get("protectors", []) as Array).has(idx):
		rs.append("보호")
	if int(plan.get("finisher", -1)) == idx:
		rs.append("마무리")
	if int(plan.get("scout", -1)) == idx:
		rs.append("정찰")
	return " · ".join(rs) if not rs.is_empty() else "화력 지원"


# The enemy an ongoing glide flies at (D10, review 1.5.3: one target, one
# steering path): the one it was launched at while it is alive, seen within
# the last second and still reachable before the landing; null otherwise
# (Doctrine._glide_retarget then picks a replacement at the next decision).
func _glide_target(u: BUnit) -> TeamIntel.EnemyBelief:
	var rem: float = float(u.ks.get("glide_until", -1.0)) - sim.time
	if rem <= 0.0 or not _glide_to.has(u.idx):
		return null
	var e: TeamIntel.EnemyBelief = intel.enemies.get(int(_glide_to[u.idx]))
	if e == null or e.dead or (not e.visible and sim.time - e.last_seen_t > 1.0):
		return null
	if u.pos.distance_to(e.pos) > maxf(40.0, sim.stat(u, BattleSim.S_MS)) * rem + 200.0:
		return null
	return e


# Shared commitments last less than one decision cycle plus reaction time.
# They describe our own orders, never the opponents' hidden commands.
func _commit_decision(u: BUnit, choice: Dictionary, ctx: Dictionary) -> void:
	var cmd: Dictionary = choice.cmd
	# Shared one-use healing is committed by movement, before the combat-only
	# target guard. A changed order releases it immediately for another ally.
	for id: String in fountain_reservations.keys():
		if int(fountain_reservations[id].owner) == u.idx:
			fountain_reservations.erase(id)
	if cmd.has("fountain_id"):
		fountain_reservations[str(cmd.fountain_id)] = {"owner": u.idx, "until": sim.time + 1.0}
	# D10: remember whom a glide is launched at: the target the glide candidate
	# planned its landing on (mem.glide_target, written by this decision), else
	# the team focus. steer() flies toward that enemy while the glide lasts; the
	# glide itself only raises speed, so without this the landing was chance.
	if str(cmd.get("kind", "")) == "ability":
		var gi: int = int(cmd.get("index", -1))
		var gl: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)
		if gi >= 0 and gi < gl.size() and (gl[gi] as Defs.AbilityDef).action == "glide":
			var gt: int = int((mem.get(u.idx, {}) as Dictionary).get("glide_target", -1))
			if gt < 0 and ctx.focus != null:
				gt = (ctx.focus as TeamIntel.EnemyBelief).idx
			if gt >= 0:
				_glide_to[u.idx] = gt
			else:
				_glide_to.erase(u.idx)
	var target: int = int(cmd.get("target", -1))
	if target < 0 or str(cmd.get("kind", "")) == "move":
		return
	var b: TeamIntel.EnemyBelief = intel.enemies.get(target)
	var target_pos: Vector2 = b.pos if b else (cmd.get("pos", u.pos) as Vector2)
	if u.pos.distance_to(target_pos) > float(cmd.get("need", 0.0)) + 6.0:
		return
	var parts: Dictionary = choice.get("parts", {})
	var damage: float = float(parts.get("피해", 0.0)) * 0.75
	var cc_until: float = 0.0
	var support: float = 0.0
	if str(cmd.kind) == "ability":
		var abilities: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)
		var i: int = int(cmd.get("index", -1))
		if i < 0 or i >= abilities.size():
			return
		var a: Defs.AbilityDef = abilities[i]
		var ev: Dictionary = KitModel.evaluate(a.effects, ctx.st, {})
		var cc: float = KitModel.cc_total(ev)
		if cc > 0.0:
			cc_until = sim.time + a.cast_time + cc
		if b == null:
			support = float(ev.heal) + float(ev.shield) * 0.5
	commitments[u.idx] = {"target": target, "damage": damage, "cc_until": cc_until, "support": support, "until": sim.time + 0.55}
	# Keep this tick's shared reservation current for allies deciding later in
	# the same tick (it is computed once per tick, see _compute_reserved).
	if _reserved_tick == sim.tick and u.action == null:
		reserved[target] = float(reserved.get(target, 0.0)) + damage
		if cc_until > sim.time:
			var claims: Dictionary = plan.get("cc_claims", {})
			claims[target] = maxf(float(claims.get(target, 0.0)), cc_until)
			plan.cc_claims = claims
		if support > 0.0:
			var supports: Dictionary = plan.get("support_claims", {})
			supports[target] = float(supports.get(target, 0.0)) + support
			plan.support_claims = supports


func _obey_forced_target(u: BUnit) -> bool:
	var target: BUnit = sim.forced_target(u)
	if target == null:
		return false
	commitments.erase(u.idx)
	var need: float = sim.stat(u, &"attackRange") + sim.radius(u) + sim.radius(target)
	u.command = {"kind": "basic", "target": target.idx, "pos": target.pos, "need": need, "purpose": "강제 도발", "key": "forced"}
	if u.def.has_rule("no_basic") or u.def.id == "politician":
		u.command = {"kind": "move", "goal": target.pos, "pos": target.pos, "purpose": "강제 도발", "key": "forced"}
	u.next_decision_at = sim.time + 0.12
	return true


func _coordination_plan(allies: Array[BUnit]) -> void:
	var uncertainty: float = 0.0
	var count: int = 0
	for item in intel.alive_enemies():
		var b: TeamIntel.EnemyBelief = item
		uncertainty += 0.0 if b.visible else 1.0 - b.confidence
		count += 1
	uncertainty /= maxf(1.0, count)
	var lead: float = float(plan.get("lead", 0.0))
	var clock_pressure: float = clampf(1.0 - (sim.max_time - sim.time) / 45.0, 0.0, 1.0)
	var losing: float = clampf(-lead, 0.0, 1.0)
	# Ahead teams protect their advantage. Behind teams can accept bounded
	# variance as the time limit approaches; uncertainty always costs budget.
	plan.uncertainty = uncertainty
	plan.risk_budget = clampf(0.42 + losing * (0.24 + clock_pressure * 0.2) - maxf(0.0, lead) * 0.18 - uncertainty * 0.2, 0.18, 0.78)
	plan.gamble = losing > 0.12 and (clock_pressure > 0.2 or float(plan.get("nokill", 0.0)) > 0.5)
	var most: int = -1
	var evidence: float = 0.0
	for ally in allies:
		var value: float = intel.focus_evidence(ally.idx)
		if value > evidence:
			evidence = value
			most = ally.idx
	plan.learned_focus = most
	plan.focus_confidence = clampf(evidence / maxf(1.0, count), 0.0, 1.0)


func _coordination_adjust(u: BUnit, ctx: Dictionary, cands: Array) -> void:
	for candidate in cands:
		var c: Dictionary = candidate
		var cmd: Dictionary = c.cmd
		var kind: String = str(cmd.get("kind", ""))
		var idx: int = int(cmd.get("target", -1))
		var e: TeamIntel.EnemyBelief = intel.enemies.get(idx)
		if kind == "move":
			continue
		if e and e.visible:
			var committed: float = float(reserved.get(idx, 0.0))
			if committed >= (e.hp + e.shield) * 1.05:
				Doctrine._note(c, - minf(120.0, maxf(0.0, float(c.value)) * 0.6), "아군 마무리 예약·과잉 화력 절약")
			if bool(plan.get("gamble", false)) and float(ctx.hpr) > 0.3 and float(ctx.risk_budget) > 0.4:
				var kill: float = float((c.get("parts", {}) as Dictionary).get("처치", 0.0))
				if kill > 0.0 and e.confidence >= 0.7:
					Doctrine._note(c, minf(55.0, kill * 0.12), "열세 탈출: 관측된 처치 기회에 위험 배분")
		if kind != "ability":
			continue
		var abilities: Array = ctx.abilities if ctx.has("abilities") else sim.ability_list(u)
		var i: int = int(cmd.get("index", -1))
		if i < 0 or i >= abilities.size():
			continue
		var a: Defs.AbilityDef = abilities[i]
		if e:
			var claim: float = float((plan.get("cc_claims", {}) as Dictionary).get(idx, 0.0)) - sim.time
			if claim > 0.0 and a.cooldown >= 7.0 and not a.homing and a.delivery in ["projectile", "line", "cone", "area"]:
				Doctrine._note(c, 18.0 * minf(1.0, claim), "아군 제어 창에 비확정기 연계")
			if e.has_status("contemplation") and not a.cc_types.is_empty():
				Doctrine._note(c, -float((c.get("parts", {}) as Dictionary).get("제어", 0.0)), "관조 중 CC 면역")
		elif idx >= 0:
			var claimed: float = float((plan.get("support_claims", {}) as Dictionary).get(idx, 0.0))
			if claimed > 0.0:
				Doctrine._note(c, -minf(claimed * 0.7, maxf(0.0, float(c.value)) * 0.7), "아군 회복 예약 반영")


func _scout_information_gain(u: BUnit, point: Vector2) -> float:
	var gain: float = 0.0
	var sense: float = sim.sensor_range(u)
	for item in intel.alive_enemies():
		var b: TeamIntel.EnemyBelief = item
		if b.visible or b.controlled_by_us:
			continue
		# Five evenly spaced particle samples bound work independently of
		# frame rate. Reward new coverage instead of reading actual location.
		for i in range(0, intel.n_part, 4):
			var p: Vector2 = b.particles[i]
			if point.distance_squared_to(p) < sense * sense and u.pos.distance_squared_to(p) >= sense * sense:
				# D13: a particle the brush would keep hidden from that point
				# is not new information (heroes-B follow-up 5).
				if sim.arena.line_of_sight(point, p, 2.0) and not intel.brush_hides(point, p, b.radius, float(sim.radius(u))):
					gain += float(b.weights[i]) * 4.0 * (0.3 + 0.7 * (1.0 - b.confidence))
	return minf(1.5, gain)


func _information_support_candidate(u: BUnit, i: int, a: Defs.AbilityDef, ctx: Dictionary, out: Array) -> void:
	var value: float = 0.0
	var allies: Array = [u]
	allies.append_array(ctx.allies)
	if a.action == "fakeNews":
		# At distrust 9 the cast itself reaches 10 and wipes every false report
		# (audit politician S1); and the 5 s reports only matter in a fight.
		if int(sim.warfare.enemy_distrust(team)) >= 9 or (ctx.targets as Array).is_empty():
			return
		var imminent: bool = false
		for item in ctx.targets:
			var foe: TeamIntel.EnemyBelief = item
			if not foe.is_hero:
				continue
			var foe_reach: float = float(eprof.get(foe.idx, {}).get("reach", 250.0)) + 180.0
			for ally in allies:
				if (ally as BUnit).pos.distance_to(foe.pos) <= foe_reach:
					imminent = true
					break
			if imminent:
				break
		if not imminent:
			return
		for ally in allies:
			var friend: BUnit = ally
			value += minf(50.0, danger_at(friend, friend.pos, 1.0) * 0.2)
		value += 25.0 + minf(35.0, (ctx.targets as Array).size() * 10.0)
	else:
		for ally in allies:
			var friend: BUnit = ally
			if friend.pos.distance_to(u.pos) > a.radius or sim.get_buff(friend, &"abilityCoefficient"):
				continue
			var profile: Dictionary = aprof.get(friend.idx, {})
			var fighting: bool = false
			for item in ctx.targets:
				var enemy: TeamIntel.EnemyBelief = item
				if friend.pos.distance_to(enemy.pos) < float(profile.get("reach", 250.0)) + 80.0:
					fighting = true
			if fighting:
				value += float(profile.get("burst", 0.0)) * 0.18 + danger_at(friend, friend.pos, 1.0) * 0.2 + 16.0
	if value <= 10.0:
		return
	out.append({"value": value - _cost(u, a, ctx), "key": "a%d:self" % i, "label": a.name,
		"parts": {"지원": value}, "cmd": {"kind": "ability", "index": i, "ability_id": a.id, "pos": u.pos, "need": 0.0}})


func _control_adjust(u: BUnit, ctx: Dictionary, candidates: Array) -> void:
	var order: Dictionary = control_plan.intent(u)
	if order.is_empty():
		return
	var goal: Vector2 = order.goal
	var center: Vector2 = order.center
	var radius: float = float(order.radius)
	var distance: float = u.pos.distance_to(goal)
	var inside: bool = u.pos.distance_to(center) < radius * 0.85
	var healing: bool = str(order.heal_target) != ""
	var danger: float = float(ctx.danger)
	# V1.5 objective discipline: an empty objective to take, or our own one
	# being taken, outranks a fight elsewhere that is not hitting this hero.
	var urgent_goal: bool = false
	if _v15_control() and float(cfg.get("disc15", 1.0)) > 0.5 and not healing and order.has("point"):
		var point: Dictionary = sim.domination.points[int(order.point)]
		var watched: int = 0
		for b in intel.visible_enemies():
			if (b as TeamIntel.EnemyBelief).is_hero and (b as TeamIntel.EnemyBelief).pos.distance_to(center) < radius + 220.0:
				watched += 1
		var capture_sign: float = -1.0 if team == 0 else 1.0
		var losing: bool = int(point.owner) == team and float(point.progress) * capture_sign < -0.05
		urgent_goal = (int(point.owner) != team and watched == 0) or losing
	for item in candidates:
		var c: Dictionary = item
		var cmd: Dictionary = c.cmd
		var kind: String = str(cmd.get("kind", ""))
		if kind == "move":
			var endpoint: Vector2 = cmd.get("goal", u.pos)
			var progress: float = distance - endpoint.distance_to(goal)
			var progress_bonus: float = clampf(progress * 0.14, -80.0, 100.0)
			if urgent_goal and not inside:
				progress_bonus = clampf(progress * 0.3, -130.0, 170.0)
			Doctrine._note(c, progress_bonus, "회복 구역 접근" if healing else ("빈 거점·점령 저지 우선" if urgent_goal else "득점 목표 접근"))
			if inside and not healing and endpoint.distance_to(center) > radius * 0.9 and danger < float(ctx.ehp) * (0.6 if urgent_goal else 0.4):
				Doctrine._note(c, -140.0 if urgent_goal else -90.0, "점령 범위 이탈 비용")
			continue
		# Hive S4 (objective_exempt): firing the controlled unit before the
		# control lapses is worth more than walking back to the objective.
		var obj_exempt: bool = bool(c.get("objective_exempt", false))
		if urgent_goal and not inside and not obj_exempt:
			var ti: int = int(cmd.get("target", -1))
			var foe: TeamIntel.EnemyBelief = intel.enemies.get(ti)
			if foe and foe.pos.distance_to(center) > radius + 150.0:
				var reach_f: float = float(eprof.get(ti, {}).get("reach", 160.0))
				if u.pos.distance_to(foe.pos) > reach_f + 40.0:
					Doctrine._note(c, -85.0, "빈 거점 점령 우선 · 교전 회피")
		var target_idx: int = int(cmd.get("target", -1))
		var enemy: TeamIntel.EnemyBelief = intel.enemies.get(target_idx)
		if enemy == null:
			continue
		var at_objective: bool = enemy.pos.distance_to(center) < radius + 150.0
		var immediate: bool = u.pos.distance_to(enemy.pos) < float(ctx.range) + float(ctx.r) + enemy.radius + 12.0
		if at_objective:
			Doctrine._note(c, 32.0 + float(order.urgency) * 28.0, "거점 교전·수비")
		elif not immediate and not obj_exempt and danger < float(ctx.ehp) * 0.4:
			Doctrine._note(c, -minf(150.0, 55.0 + distance * 0.08), "거점 밖 추격보다 점령 우선")
		if healing and float(ctx.hpr) < 0.4 and not at_objective:
			Doctrine._note(c, -70.0, "회복 중 불필요한 교전 제한")


# --- V2 scale (B-PERF) ---
# Detail levels for battleground-scale battles (BattleSim.scale_lod, DESIGN_V2
# §3.7); every other battle keeps the scheduling above unchanged. All rules
# count (never wall-clock):
#  * Teams observe on ticks staggered by team (every 3rd tick, a calm team
#    every 6th or at once on a new sighting) and start their plan clocks at
#    staggered phases, so 30 controllers never re-plan on the same tick. A
#    calm team (nothing within contact range) re-plans every 1.0 s (so a
#    free-for-all intent is refreshed once a second), a team in contact every
#    0.25 s, and at once (0.1 s) when contact begins. At most
#    BattleSim.LOD_PLANS_PER_TICK due plans run per tick; the rest wait (up to
#    LOD_PLAN_GRACE s) so plans do not pile up on one tick.
#  * Decision interval: urgent 0.09 s, calm 0.40 s, contact 0.15 s + 0.012 s
#    per hero within 1200 px (own allies plus enemies the team sees, at least
#    LOD_CONTACT_MIN_NEAR, B-PERF2) instead of per hero in the whole roster.
#    BattleSim.lod_admit caps non-urgent decisions per tick.
#  * A calm hero walking to a distant mode goal (loot, roam, listen) takes a
#    one-line travel order instead of a full candidate search.
const LOD_PLAN_CONTACT: = 0.25
const LOD_PLAN_CALM: = 1.0
const LOD_PLAN_WAKE: = 0.1
const LOD_PLAN_GRACE: = 0.15
const LOD_TRAVEL_MIN: = 320.0
const LOD_TRAVEL_LABELS: = {"loot": "보급", "roam": "탐색", "listen": "소음 추적"}
var _lod_phase_done: bool = false
var _lod_plan_calm: bool = false


func _lod_pre_tick(s: BattleSim) -> void:
	if not _lod_phase_done:
		_lod_phase_done = true
		plan.t = float(plan.t) - LOD_PLAN_CONTACT * float(team % 8) / 8.0
	# Observe every 3rd tick (phase by team); a calm team every 6th, or at once
	# when the team's sight picks up an enemy body its beliefs do not show.
	var phase: int = (s.tick + team) % 6
	if phase == 0 or (phase == 3 and not _lod_plan_calm) or (_lod_plan_calm and _lod_new_sighting(s)):
		intel.observe()
	intel.observe_fast()
	var calm: bool = _lod_team_calm()
	var since: float = s.time - float(plan.t)
	var interval: float = LOD_PLAN_CALM if calm else LOD_PLAN_CONTACT
	var wake: bool = _lod_plan_calm and not calm and since >= LOD_PLAN_WAKE
	# A plan that is due waits for the per-tick plan budget (BattleSim.
	# lod_plan_take); waking into contact or LOD_PLAN_GRACE s overdue never waits.
	if wake or since >= interval + LOD_PLAN_GRACE or (since >= interval and s.lod_plan_take()):
		_lod_plan_calm = calm
		_plan()


# The team's own sight (sim.seen) shows an enemy body its beliefs do not.
func _lod_new_sighting(s: BattleSim) -> bool:
	if team >= s.seen.size():
		return false
	var arr: PackedByteArray = s.seen[team]
	for o in s.heroes:
		if o.alive and o.team != team and o.idx < arr.size() and arr[o.idx] == 1:
			var eb: TeamIntel.EnemyBelief = intel.enemies.get(o.idx)
			if eb != null and not eb.visible:
				return true
	for e in s.entities:
		if e.alive and e.idx < arr.size() and arr[e.idx] == 1 and s.ai_eteam(e) != team:
			var known: TeamIntel.EnemyBelief = intel.entities.get(e.idx)
			if known == null or not known.visible:
				return true
	return false


# No enemy body the team sees, no seen projectile and no telegraph within
# contact range of any of our heroes.
func _lod_team_calm() -> bool:
	var r2: float = BattleSim.LOD_CONTACT_RANGE * BattleSim.LOD_CONTACT_RANGE
	var ours: Array[BUnit] = sim.ai_team_heroes(team)
	if ours.is_empty():
		return true
	# Same bodies as intel.visible_enemies(true), read in place (B-PERF2).
	for eb: TeamIntel.EnemyBelief in intel.vis_heroes:
		if not eb.visible or eb.dead or eb.controlled_by_us:
			continue
		for a2 in ours:
			if a2.pos.distance_squared_to(eb.pos) <= r2:
				return false
	for k2 in intel.entities:
		var en: TeamIntel.EnemyBelief = intel.entities[k2]
		if not en.visible:
			continue
		for a5 in ours:
			if a5.pos.distance_squared_to(en.pos) <= r2:
				return false
	for p in intel.projectiles:
		for a3 in ours:
			if a3.pos.distance_squared_to(p.pos) <= r2:
				return false
	for tg in intel.telegraphs:
		for a4 in ours:
			if a4.pos.distance_squared_to(tg.to) <= r2:
				return false
	return true


# _decide's urgency test (danger above 35 % of health + shields), asked by
# BattleSim.lod_admit before the decision so the per-tick budget never defers
# an urgent hero. danger_at is cached per tick, so _ctx reuses the value.
func lod_urgent(u: BUnit) -> bool:
	var saved: Dictionary = plan
	if _squad_mode():
		plan = _squad_plan_for(u)
	var urgent: bool = danger_at(u, u.pos, 1.0) > (u.hp + sim.shield_amount(u)) * 0.35
	plan = saved
	return urgent


# Decision interval and class (BattleSim.LOD_*) for this decision.
func _lod_interval(u: BUnit, ctx: Dictionary, urgent: bool) -> float:
	if urgent:
		sim.lod_set_class(u, BattleSim.LOD_URGENT)
		return 0.09
	var r2: float = BattleSim.LOD_CONTACT_RANGE * BattleSim.LOD_CONTACT_RANGE
	var near: int = 0
	var contact: bool = false
	for a in sim.heroes:
		if a != u and a.alive and a.team == team and a.pos.distance_squared_to(u.pos) <= r2:
			near += 1
	for b in ctx.targets:
		var eb: TeamIntel.EnemyBelief = b
		if eb.pos.distance_squared_to(u.pos) <= r2:
			contact = true
			if eb.is_hero:
				near += 1
	if not contact:
		for p in intel.projectiles:
			if (p.pos as Vector2).distance_squared_to(u.pos) <= r2:
				contact = true
				break
	if not contact:
		for tg in intel.telegraphs:
			if (tg.to as Vector2).distance_squared_to(u.pos) <= r2:
				contact = true
				break
	if not contact:
		sim.lod_set_class(u, BattleSim.LOD_CALM)
		return 0.40
	sim.lod_set_class(u, BattleSim.LOD_CONTACT)
	# B-PERF2: never more often than a hero of a 3v3 elimination decides
	# (0.15 + 0.012 x 6 heroes = 0.222 s); a duel used to re-decide every
	# 0.17 s, more often than any shipped mode.
	return 0.15 + 0.012 * maxi(near, LOD_CONTACT_MIN_NEAR)


# Calm travel: one move order straight to the mode goal (steer() routes it).
# Arrival, threats and anything urgent go through the full decision.
func _lod_travel(u: BUnit, ctx: Dictionary) -> bool:
	if u.idx >= sim.lod_class.size() or int(sim.lod_class[u.idx]) != BattleSim.LOD_CALM:
		return false
	if float(ctx.danger) > float(ctx.ehp) * 0.05:
		return false
	var goal: Vector2 = _lod_travel_goal(u)
	if not goal.is_finite() or u.pos.distance_to(goal) < LOD_TRAVEL_MIN:
		return false
	var r: float = float(ctx.r)
	var p: Vector2 = sim.arena.resolve_circle(goal, r)
	if _damaging_hazards():
		p = _hazard_free_goal(u, p, r)
	var label: String = _lod_travel_label(u)
	var choice: Dictionary = {"value": 0.0, "final": 0.0, "key": "m:%s:%d:%d" % [label, int(p.x / 30.0), int(p.y / 30.0)],
		"label": label, "parts": {}, "notes": ["원거리 이동 (간소 결정)"], "cmd": {"kind": "move", "goal": p}}
	var cmd: Dictionary = choice.cmd
	cmd["key"] = choice.key
	cmd["purpose"] = label
	u.command = cmd
	_commit_decision(u, choice, ctx)
	var m: Dictionary = mem.get(u.idx, {})
	m.erase("issue_key")
	m["key"] = choice.key
	m["t"] = sim.time
	m["top"] = [{"label": label, "score": 0.0, "parts": {}, "notes": choice.notes}]
	m["danger"] = ctx.danger
	m["stance"] = ctx.stance
	mem[u.idx] = m
	return true


# Mode goal a calm hero may simply walk to. Free-for-all brains keep it in
# `intent` (loot / roam / listen); other brains return INF (always decide in
# full) unless they override this.
func _lod_travel_goal(_u: BUnit) -> Vector2:
	var it = get("intent")
	if not (it is Dictionary):
		return Vector2.INF
	if not LOD_TRAVEL_LABELS.has(str((it as Dictionary).get("mode", ""))):
		return Vector2.INF
	var g = (it as Dictionary).get("goal", Vector2.INF)
	return g if g is Vector2 else Vector2.INF


func _lod_travel_label(_u: BUnit) -> String:
	var it = get("intent")
	if not (it is Dictionary):
		return "이동"
	var mode: String = str((it as Dictionary).get("mode", ""))
	return "%s: %s" % [str(LOD_TRAVEL_LABELS.get(mode, mode)), str((it as Dictionary).get("reason", "")).split(" — ")[0]]


# --- V2 scale (B-PERF2) ---
# Per-hero path reuse in scale battles only (BattleSim.scale_lod; every other
# battle keeps the exact 0.1 / 0.2 s reuse above). A routed waypoint stays the
# hero's target until it is reached, the goal moves more than LOD_ROUTE_MOVE px
# (12 px for a straight-line route, whose clear segment was checked for that
# goal), the hero is pushed more than LOD_ROUTE_OFF px off the segment it was
# walking, the gate signature changes, or LOD_ROUTE_KEEP s pass. Walking a
# checked clear segment keeps it clear, so this only delays finding a farther
# shortcut. Counted in time only, never wall-clock.
const LOD_ROUTE_KEEP: = 2.0
const LOD_CONTACT_MIN_NEAR: = 6
const LOD_ROUTE_MOVE: = 64.0
const LOD_ROUTE_OFF: = 24.0
var lod_route_hits: int = 0


func _lod_route_reuse(u: BUnit, goal: Vector2, rc: Dictionary, sig: int) -> Vector2:
	if float(rc.get("l_until", -1.0)) <= sim.time or int(rc.get("l_sig", -1)) != sig:
		return Vector2.INF
	var lwp: Vector2 = rc.l_wp
	var lfrom: Vector2 = rc.l_from
	var lgoal: Vector2 = rc.l_goal
	if bool(rc.l_direct):
		if lgoal.distance_squared_to(goal) >= 144.0:
			return Vector2.INF
		if Geometry2D.get_closest_point_to_segment(u.pos, lfrom, lgoal).distance_squared_to(u.pos) > LOD_ROUTE_OFF * LOD_ROUTE_OFF:
			return Vector2.INF
		lod_route_hits += 1
		return goal
	if lgoal.distance_squared_to(goal) >= LOD_ROUTE_MOVE * LOD_ROUTE_MOVE or lwp.distance_squared_to(u.pos) <= 196.0:
		return Vector2.INF
	if Geometry2D.get_closest_point_to_segment(u.pos, lfrom, lwp).distance_squared_to(u.pos) > LOD_ROUTE_OFF * LOD_ROUTE_OFF:
		return Vector2.INF
	lod_route_hits += 1
	return lwp


func _lod_route_store(u: BUnit, goal: Vector2, wp: Vector2, rc: Dictionary, sig: int) -> void:
	rc["l_wp"] = wp
	rc["l_from"] = u.pos
	rc["l_goal"] = goal
	rc["l_sig"] = sig
	rc["l_direct"] = wp.distance_squared_to(goal) <= 1.0
	rc["l_until"] = sim.time + LOD_ROUTE_KEEP


# Calm steering reuse (scale battles only; DESIGN_V2 3.7: cheaper steer
# paths when calm). A hero whose last decision was calm, walking a move order
# more than LOD_STEER_FAR px from its goal, with no other hero within its push
# reach + LOD_STEER_PAD px, no hazard, gate or link trigger near, no recent
# hit and no projectile or telegraph in its team's sight, steers with the
# vector it computed on the previous tick instead of recomputing it; the next
# tick computes it again. Locomotion turns and accelerates over several
# ticks, so one tick of a 1-3 px older direction does not show.
const LOD_STEER_FAR: = 160.0
const LOD_STEER_PAD: = 40.0
var lod_steer_hits: int = 0
var _lsteer: Dictionary = {}    # hero idx -> [tick, vector, command, goal, reusable]


func _lod_steer_reuse(u: BUnit) -> Vector2:
	var e: Array = _lsteer.get(u.idx, [])
	if e.is_empty() or int(e[0]) != sim.tick - 1 or not bool(e[4]):
		return Vector2.INF
	if u.idx >= sim.lod_class.size() or int(sim.lod_class[u.idx]) != BattleSim.LOD_CALM:
		return Vector2.INF
	if not is_same(u.command, e[2]) or (e[3] as Vector2).distance_squared_to(u.pos) <= LOD_STEER_FAR * LOD_STEER_FAR:
		return Vector2.INF
	if not intel.projectiles.is_empty() or not intel.telegraphs.is_empty() or sim.time - u.last_damage_time < 1.0:
		return Vector2.INF
	var r: float = sim.radius(u)
	if _hazard_near(u.pos, r + 90.0):
		return Vector2.INF
	if sim.arena.has_links:
		_refresh_gimmicks()
		for b: Vector3 in _gim_link_bounds:
			var rr: float = b.z + 140.0 + r
			if u.pos.distance_squared_to(Vector2(b.x, b.y)) < rr * rr:
				return Vector2.INF
	e[4] = false
	lod_steer_hits += 1
	return e[1]


func _lod_steer_store(u: BUnit, v: Vector2, goal: Vector2, reusable: bool) -> void:
	_lsteer[u.idx] = [sim.tick, v, u.command, goal, reusable]


# Unpadded bounding boxes [minx, maxx, miny, maxy] of the mud patches in
# _gim_mud (same order), rebuilt with the gimmick tables. _mud_cost uses them
# only to skip patches that cannot contain a sample (exact).
var _mud_box_arena: Arena = null
var _mud_box: PackedFloat64Array = PackedFloat64Array()


func _mud_boxes() -> PackedFloat64Array:
	_refresh_gimmicks()
	if _mud_box_arena == sim.arena and _mud_box.size() == _gim_mud.size() * 4:
		return _mud_box
	_mud_box_arena = sim.arena
	_mud_box = PackedFloat64Array()
	for h: Dictionary in _gim_mud:
		if str(h.get("shape", "rect")) == "circle":
			var cx: float = float(h.x)
			var cy: float = float(h.y)
			var rr: float = absf(float(h.get("radius", 0.0)))
			_mud_box.append_array([cx - rr, cx + rr, cy - rr, cy + rr])
		else:
			var x0: float = float(h.x)
			var y0: float = float(h.y)
			var x1: float = x0 + float(h.get("w", 0.0))
			var y1: float = y0 + float(h.get("h", 0.0))
			_mud_box.append_array([minf(x0, x1), maxf(x0, x1), minf(y0, y1), maxf(y0, y1)])
	return _mud_box


# Hazard bound buckets (B-PERF2): _hazard_near and _hazard_near_segment test
# every bounding circle in _haz_bounds, several hundred times per tick in a
# 30-hero battle. Each circle is listed in the HAZ_CELL buckets its radius +
# HAZ_PAD_MAX touches, so a probe with padding up to HAZ_PAD_MAX only tests the
# circles listed in the buckets it touches, with the unchanged test (larger
# paddings, far-off probes and long segments scan the full list). Exact.
const HAZ_CELL: = 256.0
const HAZ_PAD_MAX: = 256.0
const HAZ_SEG_CELLS_MAX: = 16
var _hz_arena: Arena = null
var _hz_n: int = -1
var _hz_cols: int = 0
var _hz_rows: int = 0
var _hz_cells: Array = []


func _hz_build() -> void:
	if _hz_arena == _hazard_arena and _hz_n == _haz_bounds.size():
		return
	_hz_arena = _hazard_arena
	_hz_n = _haz_bounds.size()
	_hz_cols = maxi(1, int(ceil(sim.arena.width / HAZ_CELL)))
	_hz_rows = maxi(1, int(ceil(sim.arena.height / HAZ_CELL)))
	_hz_cells = []
	_hz_cells.resize(_hz_cols * _hz_rows)
	for c in _hz_cells.size():
		_hz_cells[c] = PackedInt32Array()
	for i in _hz_n:
		var b: Vector3 = _haz_bounds[i]
		var ext: float = b.z + HAZ_PAD_MAX + 1.0
		var cx0: int = clampi(int(floor((b.x - ext) / HAZ_CELL)), 0, _hz_cols - 1)
		var cx1: int = clampi(int(floor((b.x + ext) / HAZ_CELL)), 0, _hz_cols - 1)
		var cy0: int = clampi(int(floor((b.y - ext) / HAZ_CELL)), 0, _hz_rows - 1)
		var cy1: int = clampi(int(floor((b.y + ext) / HAZ_CELL)), 0, _hz_rows - 1)
		for cy in range(cy0, cy1 + 1):
			for cx in range(cx0, cx1 + 1):
				var row: PackedInt32Array = _hz_cells[cy * _hz_cols + cx]
				row.append(i)
				_hz_cells[cy * _hz_cols + cx] = row


func _haz_bounds_near(p: Vector2, pad: float) -> bool:
	var cell: int = -1
	if pad <= HAZ_PAD_MAX:
		if _hz_arena != _hazard_arena or _hz_n != _haz_bounds.size():
			_hz_build()
		var cx: int = int(floor(p.x / HAZ_CELL))
		var cy: int = int(floor(p.y / HAZ_CELL))
		if cx >= 0 and cy >= 0 and cx < _hz_cols and cy < _hz_rows:
			cell = cy * _hz_cols + cx
	if cell < 0:
		for b: Vector3 in _haz_bounds:
			var rr: float = b.z + pad
			if p.distance_squared_to(Vector2(b.x, b.y)) <= rr * rr:
				return true
		return false
	for i in _hz_cells[cell]:
		var b2: Vector3 = _haz_bounds[i]
		var rr2: float = b2.z + pad
		if p.distance_squared_to(Vector2(b2.x, b2.y)) <= rr2 * rr2:
			return true
	return false


func _haz_bounds_near_segment(a: Vector2, b: Vector2, pad: float) -> bool:
	var ok: bool = pad <= HAZ_PAD_MAX
	var cx0: int = 0
	var cx1: int = -1
	var cy0: int = 0
	var cy1: int = -1
	if ok:
		_hz_build()
		cx0 = int(floor(minf(a.x, b.x) / HAZ_CELL))
		cx1 = int(floor(maxf(a.x, b.x) / HAZ_CELL))
		cy0 = int(floor(minf(a.y, b.y) / HAZ_CELL))
		cy1 = int(floor(maxf(a.y, b.y) / HAZ_CELL))
		ok = cx0 >= 0 and cy0 >= 0 and cx1 < _hz_cols and cy1 < _hz_rows and (cx1 - cx0 + 1) * (cy1 - cy0 + 1) <= HAZ_SEG_CELLS_MAX
	if not ok:
		for hb: Vector3 in _haz_bounds:
			var c: Vector2 = Vector2(hb.x, hb.y)
			if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) <= hb.z + pad:
				return true
		return false
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			for i in _hz_cells[cy * _hz_cols + cx]:
				var hb2: Vector3 = _haz_bounds[i]
				var c2: Vector2 = Vector2(hb2.x, hb2.y)
				if Geometry2D.get_closest_point_to_segment(c2, a, b).distance_to(c2) <= hb2.z + pad:
					return true
	return false


# Largest radius() any hero of this battle can take (BattleSim.radius_bounds),
# for exact distance pre-tests. Heroes never change during a battle.
var _rmax_sim: BattleSim = null
var _rmax: float = 0.0


func _hero_radius_max() -> float:
	if _rmax_sim != sim:
		_rmax_sim = sim
		_rmax = 0.0
		for h in sim.heroes:
			_rmax = maxf(_rmax, sim.radius_bounds(h).y)
	return _rmax


# _danger_raw's per-profile constants (B-PERF2): for each eprof entry, in
# eprof's iteration order, the profile, its belief, w, ms, reach and whether
# the enemy fights in melee. eprof is only ever rebuilt whole (_plan, squad
# subsets): every rebuild is a new dictionary or puts a new profile first, so
# the table is rebuilt whenever eprof is another dictionary, has another size
# or holds another first profile, and its values always equal what the loop
# would read from eprof itself.
var _dt_src: Dictionary = {}
var _dt_pr: Array = []
var _dt_eb: Array = []
var _dt_w: PackedFloat64Array = PackedFloat64Array()
var _dt_ms: PackedFloat64Array = PackedFloat64Array()
var _dt_reach: PackedFloat64Array = PackedFloat64Array()
var _dt_melee: PackedByteArray = PackedByteArray()


func _danger_table() -> void:
	if is_same(eprof, _dt_src) and eprof.size() == _dt_pr.size():
		if _dt_pr.is_empty():
			return
		for k in eprof:
			if is_same(eprof[k], _dt_pr[0]):
				return
			break
	_dt_src = eprof
	_dt_pr = []
	_dt_eb = []
	_dt_w = PackedFloat64Array()
	_dt_ms = PackedFloat64Array()
	_dt_reach = PackedFloat64Array()
	_dt_melee = PackedByteArray()
	for k2 in eprof:
		var pr: Dictionary = eprof[k2]
		var eb: TeamIntel.EnemyBelief = pr.b
		var w: float = pr.w
		_dt_pr.append(pr)
		_dt_eb.append(eb)
		_dt_w.append(w)
		_dt_ms.append(float(pr.ms))
		_dt_reach.append(float(pr.reach))
		_dt_melee.append(1 if eb.def.preferred_range < 100.0 else 0)


# --- V2 backlog fixes (Codex) ---

# Only physically valid, grid-free targets reach move scoring. The narrow
# legacy boulder pockets were physically standable but entirely grid-solid.
func _v2_move_goal(u: BUnit, p: Vector2, r: float, purpose: String) -> Vector2:
	var retreat: bool = purpose in ["후퇴", "측면 이탈 (우)", "측면 이탈 (좌)", "재집결", "보호선으로 후퇴"]
	var margin: float = 2.0 * r + 16.0
	if retreat:
		p = Vector2(clampf(p.x, sim.arena.min_x + margin, sim.arena.max_x - margin),
			clampf(p.y, sim.arena.min_y + margin, sim.arena.max_y - margin))
		p = sim.arena.resolve_circle(p, r)
	var nav: Navigator = navigator_for(r)
	var cell: Vector2i = nav.cell_of(p)
	if nav.grid.is_point_solid(cell):
		var snapped: Vector2i = nav._snap(p, u.pos)
		if nav.grid.is_point_solid(snapped):
			return Vector2.INF
		p = nav._cell_centre(snapped)
		if nav.direct_length(u.pos, p, r) == INF:
			return Vector2.INF
	if not sim.arena.is_walkable(p, r):
		return Vector2.INF
	if retreat and (p.x < sim.arena.min_x + margin or p.x > sim.arena.max_x - margin
			or p.y < sim.arena.min_y + margin or p.y > sim.arena.max_y - margin):
		return Vector2.INF
	return p


func _v2_escape_safe(u: BUnit, p: Vector2, r: float) -> bool:
	if not sim.arena.is_walkable(p, r):
		return false
	var nav: Navigator = navigator_for(r)
	if nav.grid.is_point_solid(nav.cell_of(p)) or _v2_link_entry(u, p, p, r):
		return false
	var ring: Dictionary = _ring_def()
	return ring.is_empty() or not Arena.ring_outside(ring, p, sim.time + 2.0, r * 0.3)


# Endpoint queries use from==to (blinks); continuous movement uses the whole
# segment. A body already in a trigger may leave it without a new entry.
func _v2_link_entry(u: BUnit, from: Vector2, to: Vector2, r: float) -> bool:
	if not sim.env.enabled or not sim.arena.has_links:
		return false
	_refresh_gimmicks()
	var taking: String = str(_taking_link.get(u.idx, ""))
	for h: Dictionary in _gim_links:
		if str(h.id) == taking or not sim.env.type_active(str(h.type)):
			continue
		var center: Vector2 = h.center
		var trigger: float = float(h.get("radius", 30.0)) + (r * 0.28 if str(h.type) == "portal" else 0.0) + 6.0
		var initial: float = from.distance_to(center)
		var final: float = to.distance_to(center)
		if from.distance_squared_to(to) <= 0.0001:
			if final < trigger:
				return true
			continue
		if initial < trigger and final > initial and (to - from).dot(from - center) >= 0.0:
			continue
		if Arena.seg_circle_t(from, to, center, trigger) >= 0.0:
			return true
	return false


func _v2_safe_dodge(u: BUnit, v: Vector2) -> Vector2:
	if v.length_squared() <= 0.0025:
		return v
	var r: float = sim.radius(u)
	var magnitude: float = v.length()
	var direction: Vector2 = v / magnitude
	var best: Vector2 = Vector2.ZERO
	var score: float = -INF
	for angle: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.45, -1.45]:
		var candidate: Vector2 = direction.rotated(angle)
		var point: Vector2 = u.pos + candidate * 40.0
		if not sim.arena.is_walkable(point, r) or sim.arena.segment_blocked(u.pos, point, r * 0.9, Arena.MASK_UNITS):
			continue
		if _v2_link_entry(u, u.pos, point, r):
			continue
		var value: float = cos(angle)
		if value > score + 0.000001:
			score = value
			best = candidate
	return best * magnitude * maxf(0.3, score) if best != Vector2.ZERO else Vector2.ZERO


# Timing is based on every physical route vertex, including outward detours.
# The cached geometry is invalidated by gates, body growth or switches.
# Giant HP changes its exact radius even inside one navigation bucket.
func _v2_ring_points(u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var ring: Dictionary = _ring_def()
	if ring.is_empty() or not Arena.ring_active(ring, sim.time + 30.0):
		return
	var center: Vector2 = ring.center
	var radius: float = float(ctx.r)
	var speed: float = maxf(40.0, float(ctx.ms))
	var distance: float = u.pos.distance_to(center)
	var margin: float = radius * 0.3 + 30.0
	var final_radius: float = maxf(0.0, float(ring.get("endRadius", 200.0)) - margin - 10.0)
	# Inside the final target, outward inertia can carry a new attack
	# approach back across the ring before the next scheduled decision.
	var coasting: bool = distance <= final_radius + 1.0
	var coast_slack: float = INF
	if coasting:
		var horizon: float = maxf(0.0, u.next_decision_at - sim.time)
		var projected: Vector2 = u.pos + u.vel * horizon
		coast_slack = _ring_time_reaching(ring, projected.distance_to(center) + margin) - (sim.time + horizon)
		if u.vel.dot(u.pos - center) <= 0.0 or coast_slack > 6.0:
			return
	# A braking route points materially inward, never toward an outer
	# final-radius endpoint or a nearby grid vertex beside the current body.
	var target_radius: float = maxf(0.0, distance - margin - 10.0) if coasting else final_radius
	var nav: Navigator = navigator_for(radius)
	var memory: Dictionary = mem.get(u.idx, {})
	var cache: Dictionary = memory.get("v2_ring_route", {})
	var path: PackedVector2Array = PackedVector2Array()
	if not coasting and not cache.is_empty() and not bool(cache.get("coasting", false)) and cache.get("nav") == nav and float(cache.get("radius", -1.0)) >= radius and float(cache.t) > sim.time - 0.5 and (cache.from as Vector2).distance_to(u.pos) < 24.0:
		path = cache.path
	else:
		var direction: Vector2 = (u.pos - center) / distance if distance > 1.0 else Vector2.RIGHT
		# Prefer the matching radial end; fixed-angle alternatives handle a
		# final point displaced into a wall or disconnected gate enclosure.
		for angle: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.4, -1.4, PI]:
			var endpoint: Vector2 = sim.arena.resolve_circle(center + direction.rotated(angle) * target_radius, radius)
			if endpoint.distance_to(center) > target_radius + 1.0 or not sim.arena.is_walkable(endpoint, radius):
				continue
			var route: PackedVector2Array = nav.path_points(u.pos, endpoint, false).duplicate()
			if route.is_empty() or not nav.clear(u.pos, route[0], radius) or not nav.clear(route[-1], endpoint, radius):
				continue
			route.append(endpoint)
			path = route
			break
		memory["v2_ring_route"] = {"t": sim.time, "from": u.pos, "path": path, "nav": nav, "radius": radius, "coasting": coasting}
		mem[u.idx] = memory
	if path.is_empty():
		return
	var timing: Dictionary = _v2_route_slacks(ring, u.pos, path, speed, margin, sim.time)
	var least: float = minf(float(timing.minimum), coast_slack)
	if least > 6.0:
		return
	var point: Vector2 = path[-1] if coasting else path[int(timing.pick)]
	var outside: bool = Arena.ring_outside(ring, u.pos, sim.time, 0.0)
	var dps: float = Arena.ring_damage_fraction(ring) * float(ctx.mx) / maxf(0.2, float(ring.get("tickInterval", 1.0)))
	var late: float = clampf(6.0 - least, 0.0, 8.0)
	var exposure: float = clampf(late + (2.0 if outside else 0.0), 0.5, 6.0)
	pts.append([point, "결계 안으로", 30.0 + dps * exposure * float(ctx.risk_w)])

func _v2_route_slacks(ring: Dictionary, start: Vector2, path: PackedVector2Array, speed: float, margin: float, now: float) -> Dictionary:
	var center: Vector2 = ring.center
	var previous: Vector2 = start
	var cumulative: float = 0.0
	var least: float = _ring_time_reaching(ring, start.distance_to(center) + margin) - now
	var slacks: PackedFloat64Array = PackedFloat64Array()
	for point in path:
		cumulative += previous.distance_to(point)
		previous = point
		var slack: float = _ring_time_reaching(ring, point.distance_to(center) + margin) - (now + cumulative / maxf(40.0, speed))
		slacks.append(slack)
		least = minf(least, slack)
	var suffix: PackedFloat64Array = PackedFloat64Array()
	suffix.resize(slacks.size())
	var running: float = INF
	for k in range(slacks.size() - 1, -1, -1):
		running = minf(running, slacks[k])
		suffix[k] = running
	var pick: int = maxi(0, path.size() - 1)
	for k in suffix.size():
		if suffix[k] >= 8.0:
			pick = k
			break
	return {"minimum": least, "pick": pick, "slacks": slacks, "suffix": suffix, "distance": cumulative}


# Friendly skill portals use full body radius. They are not environment
# links and must also be considered on maps whose has_links flag is false.
func _v2_skill_portal_avoidance(u: BUnit) -> Vector2:
	var ring: Dictionary = _ring_def()
	if ring.is_empty() or u.portal_until > sim.time or u.chamber != "":
		return Vector2.ZERO
	var radius: float = sim.radius(u)
	var speed: float = maxf(40.0, sim.stat(u, BattleSim.S_MS))
	var steering: Vector2 = Vector2.ZERO
	for pair: Dictionary in sim.portal_pairs:
		if int(pair.team) != team or float(pair.end) <= sim.time:
			continue
		for ends: Array in [[pair.a, pair.b], [pair.b, pair.a]]:
			var entry: Vector2 = ends[0]
			var exit_point: Vector2 = ends[1]
			var trigger: float = float(pair.radius) + radius
			var offset: Vector2 = u.pos - entry
			var distance: float = offset.length()
			var look: float = maxf(45.0, u.vel.length_squared() / (2.0 * maxf(1.0, speed / maxf(0.06, u.brake_time))) + 12.0)
			if distance > trigger + look:
				continue
			var eta: float = maxf(0.0, distance - trigger) / speed
			if float(pair.end) <= sim.time + eta:
				continue
			var destination: Vector2 = sim.clamp_pos(exit_point + (exit_point - entry).normalized() * (float(pair.radius) + radius + 3.0), radius)
			if not Arena.ring_outside(ring, destination, sim.time + eta + 1.0, radius * 0.3):
				continue
			var normal: Vector2 = offset / distance if distance > 0.01 else (entry - exit_point).normalized()
			if normal == Vector2.ZERO:
				normal = Vector2.RIGHT if u.idx % 2 == 0 else Vector2.LEFT
			steering += normal * clampf((trigger + look - distance) / look, 0.0, 1.0)
	return steering.limit_length(1.4)


func _v2_stopping_distance(u: BUnit) -> float:
	var braking: float = maxf(1.0, sim.stat(u, BattleSim.S_MS) / maxf(0.06, u.brake_time))
	return u.vel.length_squared() / (2.0 * braking)


# Repricing still runs in steer() while decide() is frozen. Keep the actual
# chosen hazard through that route refresh even if a different valid link
# wins repricing, when braking cannot prevent entry;
# an index from an older navigator is unsafe after gate/switch changes.
func _v2_keep_link_choice(u: BUnit, nav: Navigator, choice: int, r: float) -> int:
	var chosen: String = str(_taking_link.get(u.idx, ""))
	if chosen.is_empty() or not sim.env.enabled:
		return choice
	for k in nav.links.size():
		var link: Dictionary = nav.links[k]
		if str(link.hazard) != chosen or not sim.env.type_active(str(link.kind)):
			continue
		var portal: bool = str(link.kind) == "portal"
		if (sim.env.portal_wait(u) if portal else sim.env.pad_wait(u)) > 0.0:
			return choice
		var delta: Vector2 = (link.entry as Vector2) - u.pos
		var trigger: float = float(link.entry_r) + (r * 0.28 if portal else 0.0)
		return k if delta.length() - trigger <= _v2_stopping_distance(u) + 8.0 and u.vel.dot(delta) > 0.0 else choice
	return choice


# Freeze the command which chose the link, not merely its intent label.
func _v2_link_frozen(u: BUnit) -> bool:
	if not sim.env.enabled or str(u.command.get("kind", "")) != "move" or sim.forced_target(u) != null:
		return false
	var chosen: String = str(_taking_link.get(u.idx, ""))
	if chosen.is_empty() or u.vel.length_squared() < 0.01:
		return false
	_refresh_gimmicks()
	for hazard: Dictionary in _gim_links:
		if str(hazard.id) != chosen or not sim.env.type_active(str(hazard.type)):
			continue
		var portal: bool = str(hazard.type) == "portal"
		if (sim.env.portal_wait(u) if portal else sim.env.pad_wait(u)) > 0.0:
			return false
		var center: Vector2 = hazard.center
		var trigger: float = float(hazard.get("radius", 30.0)) + (sim.radius(u) * 0.28 if portal else 0.0)
		return u.pos.distance_to(center) - trigger <= _v2_stopping_distance(u) + 30.0 and u.vel.dot(center - u.pos) > 0.0
	return false


func _v2_arm_link_choice(u: BUnit, nav: Navigator, choice: int, r: float) -> int:
	var memory: Dictionary = mem.get(u.idx, {})
	if choice < 0 or choice >= nav.links.size():
		memory.erase("v2_link_arm")
		mem[u.idx] = memory
		return -1
	var link: Dictionary = nav.links[choice]
	var id: String = str(link.hazard)
	var armed: Dictionary = memory.get("v2_link_arm", {})
	if str(armed.get("id", "")) != id:
		var trigger: float = float(link.entry_r) + (r * 0.28 if str(link.kind) == "portal" else 0.0)
		armed = {"id": id, "at": sim.time, "near": u.pos.distance_to(link.entry) < trigger + 60.0}
		memory["v2_link_arm"] = armed
		mem[u.idx] = memory
	return -1 if bool(armed.near) and sim.time - float(armed.at) < 0.35 else choice
