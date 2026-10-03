class_name BattleSim
extends RefCounted




const DT: = 1.0 / 30.0
const VISION: = 560.0
const ENTITY_VISION: = 320.0

enum {IDLE, RUNNING, PAUSED, FINISHED}

const S_AD: = &"attackDamage"
const S_AP: = &"abilityPower"
const S_ARMOR: = &"armor"
const S_MR: = &"magicResistance"
const S_MS: = &"moveSpeed"
const S_AS: = &"attackSpeed"
const S_RANGE: = &"attackRange"
const S_HP: = &"maxHealth"
const S_CRIT: = &"critChance"
const S_CRITM: = &"critMultiplier"
const S_TEN: = &"tenacity"

const HARD_BLOCK: = [&"stun", &"root", &"airborne", &"suppression", &"sleep"]
const ACTION_BREAK: = [&"stun", &"airborne", &"suppression", &"sleep"]
const NO_CAST: = [&"stun", &"airborne", &"suppression", &"sleep", &"silence", &"taunt", &"charm"]
const NO_BASIC: = [&"stun", &"airborne", &"suppression", &"sleep", &"disarm", &"charm"]
const CC_TYPES: = [&"slow", &"root", &"stun", &"silence", &"disarm", &"taunt", &"fear", &"airborne", &"grounded", &"sleep", &"suppression", &"charm", &"control"]
const LOG_TYPES: = ["HEALTH_DAMAGED", "HEAL_APPLIED", "SHIELD_APPLIED", "CC_APPLIED", "DEATH", "EXECUTED", "CAST_STARTED", "SUMMON_CREATED", "PASSIVE", "BATTLE_STARTED", "BATTLE_ENDED", "SKILLS_SEALED", "PROJECTILE_REFLECTED", "PROJECTILE_BLOCKED", "GARDEN_CLOSED", "ENV_HIT", "ENV_HASTE", "ENV_FOUNTAIN", "ENV_PORTAL", "ENV_GATE", "ENV_PUSHED", "ENV_ARTILLERY", "ENV_STRIKE", "ENV_JUMP", "ENV_RING", "CHAMBER_STARTED", "REVEAL", "POSITIONS_SWAPPED", "STAT_STOLEN", "CONTEMPLATION", "FAKE_NEWS", "DISTRUST_RESET", "DIVERSION", "PROPAGANDA", "INFO_REVEAL", "INFO_BLOCKED", "PRISON_CREATED", "PRISON_ENDED", "CONTROL_CAPTURED", "CONTROL_NEUTRALIZED", "CONTROL_CONTESTED", "CONTROL_SCORE", "HEAL_ZONE_USED", "RESPAWN_SCHEDULED", "HERO_RESPAWNED", "DM_KILL", "DM_ITEM_PICKED", "DM_ITEM_DROPPED", "DM_ITEM_PROC", "DM_REVIVE",
	"CLEANSED", "FRONT_BLOCKED", "TANK_DESTROYED", "OVERDRIVE", "HEAL_BLOCKED", "CHARIOT_KNOCK",
	"BR_DOWNED", "BR_REVIVE_START", "BR_REVIVE_CANCEL", "BR_REVIVED", "BR_BLED_OUT", "BR_ELIMINATED", "BR_TEAM_OUT", "BR_ZONE_ANNOUNCE", "BR_ZONE_SHRINK", "BR_ITEM_SWAP"]

var cfg: Dictionary = {}
var seed_value: int = 1
var rng: = RandomNumberGenerator.new()
# A gated map changes its obstacle masks during the battle, so assigning a
# shared DB arena that has gates stores a private battle copy instead. Every
# system (movement, projectiles, vision, AI, previews, lab) reads sim.arena.
var arena: Arena:
	set(value):
		if value != null and value.shared and not value.gates.is_empty():
			value = value.make_battle_copy()
		arena = value
# Brush/forest concealment switch (ArenaEnv keeps it in sync with the toggles).
var brush_on: bool = true
var state: int = IDLE
var time: float = 0.0
var tick: int = 0
# V1.5: units pinned against a wall slide instead of freezing (tests can
# switch it off to compare with 1.4 bit for bit).
static var wall_unpin: bool = true
var max_time: float = 150.0
var ruleset: String = "elimination"
var vision_range: float = VISION
var winner: int = -1
var finish_reason: String = ""

var units: Array[BUnit] = []
var heroes: Array[BUnit] = []
var entities: Array[BUnit] = []
var telegraphs: Array = []
var delayed: Array = []
var gardens: Array = []
var chambers: Array = []
var portal_pairs: Array = []
var seq: int = 0

var proj: ProjectileSystem
var zones: ZoneSystem
var kits: Kits
var env: ArenaEnv
var warfare: InformationWarfare
var domination: DominationMode
var deathmatch: DeathmatchMode
# V2 battleground (DESIGN_V2 §3.5): the same object as `deathmatch`, so the
# free-for-all item, kill and vision hooks run unchanged; null in every other mode.
var battleground: BattlegroundMode
# Teams: 2 for elimination and conquest, one per participant in deathmatch,
# one per squad in the battleground.
var team_count: int = 2
var respawns: bool = false

var controllers: Array = [null, null]


var seen: Array = [PackedByteArray(), PackedByteArray()]


var tick_events: Array = []
var ai_events: Array = []
var frame_events: Array = []
var collect_frame_events: bool = false
@warning_ignore("shadowed_global_identifier")
var log: Array = []
var log_limit: int = 3000
var history: Array = []


func _init(config: Dictionary) -> void :
	cfg = config
	seed_value = int(config.get("seed", 260816))
	if seed_value <= 0:
		seed_value = 1
	rng.seed = seed_value
	vision_range = float(config.get("vision_range", VISION))
	DB.ensure_loaded()
	var arena_id: String = str(config.get("arena_id", "classic"))
	var br_teams: Array = []
	if str(config.get("ruleset", "")) == "battleground" or BattlegroundMapData.is_battleground_id(arena_id):
		ruleset = "battleground"
		arena = DB.battleground_arena(arena_id, int(config.get("map_seed", seed_value)))
		br_teams = BattlegroundMode.normalize_teams(config)
	elif str(config.get("ruleset", "")) == "deathmatch" or DeathmatchMapData.is_deathmatch_id(arena_id):
		ruleset = "deathmatch"
		arena = DB.deathmatch_arena(arena_id, seed_value)
	else:
		arena = DB.arena(arena_id)
		ruleset = str(config.get("ruleset", arena.ruleset))
		if ruleset not in ["elimination", "control"]:
			ruleset = arena.ruleset
	respawns = ruleset != "elimination"
	var default_max: float = 150.0 if ruleset == "elimination" else (BattlegroundMode.MAX_TIME if ruleset == "battleground" else 480.0)
	max_time = maxf(DT, float(config.get("max_time", default_max)))
	proj = ProjectileSystem.new(self)
	zones = ZoneSystem.new(self)
	kits = Kits.new(self)
	env = ArenaEnv.new(self)
	if is_battleground():
		team_count = maxi(2, br_teams.size())
		controllers = []
		controllers.resize(team_count)
		seen = []
		for t in team_count:
			seen.append(PackedByteArray())
	elif is_deathmatch():
		var players: Array = config.get("players", ["swordsman", "archer"])
		team_count = maxi(2, players.size())
		controllers = []
		controllers.resize(team_count)
		seen = []
		for t in team_count:
			seen.append(PackedByteArray())
	warfare = InformationWarfare.new(self)
	if is_battleground():
		battleground = BattlegroundMode.new(self)
		deathmatch = battleground
		battleground.make_teams(br_teams)
	elif is_deathmatch():
		deathmatch = DeathmatchMode.new(self)
		deathmatch.make_players(config.get("players", ["swordsman", "archer"]))
	else:
		var blue: Array = config.get("blue", ["swordsman"])
		var red: Array = config.get("red", ["archer"])
		_make_team(0, blue)
		_make_team(1, red)
	domination = DominationMode.new(self)
	for t in team_count:
		seen[t] = PackedByteArray()
		seen[t].resize(units.size())


func dispose() -> void :
	if proj: proj.sim = null
	if zones: zones.sim = null
	if kits: kits.sim = null
	if env: env.sim = null
	if warfare: warfare.sim = null
	if domination: domination.sim = null
	if deathmatch: deathmatch.dispose()
	battleground = null
	for c in controllers:
		if c and c.has_method("dispose"):
			c.dispose()
	controllers = []
	controllers.resize(team_count)
	units.clear()
	heroes.clear()
	entities.clear()


func _make_team(team: int, ids: Array) -> void :
	var spawns: Array = arena.spawns.get(team, [])
	for i in ids.size():
		var d: Defs.CharDef = DB.char_def(str(ids[i]))
		if d == null:
			push_error("unknown character %s" % ids[i])
			continue
		var p: Vector2
		if i < spawns.size():
			p = spawns[i]
		else:
			# Extra heroes line up across the team's own spawn centroid,
			# perpendicular to the direction of the enemy spawns.
			var own: Vector2 = spawn_centroid(team)
			var toward: Vector2 = spawn_facing(team, own)
			var across: = Vector2( - toward.y, toward.x)
			if across.y < 0.0 or (absf(across.y) < 1e-6 and across.x < 0.0):
				across = - across
			p = own + across * ((i - (ids.size() - 1) * 0.5) * 100.0)
		p = arena.resolve_circle(p, d.stat("bodyRadius"))
		var u: = _new_unit(d, team, i, p)
		heroes.append(u)


func _new_unit(d: Defs.CharDef, team: int, slot: int, p: Vector2) -> BUnit:
	var u: = BUnit.new()
	u.idx = units.size()
	u.team = team
	u.slot = slot
	u.def = d
	u.is_hero = not d.is_entity
	u.name = d.name
	u.id = (("b%d_" if team == 0 else "r%d_") % slot if team_count == 2 else "p%d_" % team) + d.id
	u.pos = p
	u.spawn_pos = p
	u.prev_pos = p
	u.facing = spawn_facing(team, p)
	u.base_max_hp = d.stat("maxHealth")
	u.base_radius = maxf(4.0, d.stat("bodyRadius"))
	u.base_ms = d.stat("moveSpeed")
	u.base_as = d.stat("attackSpeed")
	u.base_range = d.stat("attackRange")
	u.hp = u.base_max_hp
	u.cooldowns.resize(d.abilities.size())
	for i in d.abilities.size():
		u.cooldowns[i] = 0.0
	u.next_decision_at = 0.1 + units.size() * 0.034
	u.setup_profile()
	units.append(u)
	if u.is_hero:
		kits.init_unit(u)
	return u


# Centroid of a team's authored spawn points (legacy edge column if none).
func spawn_centroid(team: int) -> Vector2:
	return arena.spawn_centroid(team)


# Opening and respawn facing: toward the enemy spawn centroid in team modes,
# toward the arena centre in free-for-all.
func spawn_facing(team: int, p: Vector2) -> Vector2:
	var goal: Vector2 = arena.center() if team_count > 2 else spawn_centroid(1 - team)
	var d: Vector2 = goal - p
	if d.length() <= 1.0:
		return Vector2.RIGHT if team % 2 == 0 else Vector2.LEFT
	return d.normalized()


func next_id() -> int:
	seq += 1
	return seq


func is_control_mode() -> bool:
	return ruleset == "control"


# True for deathmatch and the battleground: both are free-for-all item modes
# (field items, FFA intel and spawns, item hooks). What differs is asked of
# is_battleground() or overridden in BattlegroundMode (respawn, kill target,
# small-match rules, downed state).
func is_deathmatch() -> bool:
	return ruleset == "deathmatch" or ruleset == "battleground"


func is_battleground() -> bool:
	return ruleset == "battleground"


# DESIGN_V2 §3.5 names. Free-for-all item hooks (deathmatch, battleground).
func is_ffa_items() -> bool:
	return deathmatch != null


# Heroes come back after dying (conquest, control, deathmatch); never in the
# battleground (`respawns` stays on there for the dead-source rules only).
func has_respawn() -> bool:
	return respawns and not is_battleground()


# Every hero fights for itself: deathmatch and the solo battleground (duo /
# trio squads have teammates).
func fights_alone() -> bool:
	return ruleset == "deathmatch" or (battleground != null and battleground.squad <= 1)


# Respawn-mode spawn protection ends on a hostile action (conquest and deathmatch).
func break_protection(u: BUnit) -> void:
	if is_control_mode():
		domination.break_protection(u)
	elif deathmatch:
		deathmatch.break_protection(u)






func start() -> void :
	if state != IDLE:
		return
	state = RUNNING
	env.prepare()
	_scale_setup()
	prebuild_nav()
	_update_visibility()
	emit("BATTLE_STARTED", -1, -1, {"arena": arena.name, "seed": seed_value})
	for c in controllers:
		if c and c.has_method("on_start"):
			c.on_start(self)


func set_paused(p: bool) -> void :
	if state == RUNNING and p:
		state = PAUSED
	elif state == PAUSED and not p:
		state = RUNNING


func step() -> bool:
	if state != RUNNING:
		return false
	if profiling:
		return _step_profiled()
	time += DT
	tick += 1
	ai_events = tick_events
	tick_events = []
	if is_control_mode(): domination.pre_tick()
	elif deathmatch: deathmatch.pre_tick()
	_prune_entities()
	_update_visibility()
	_update_statuses(DT)
	warfare.update(DT)
	kits.update_passives(DT)
	for c in controllers:
		if c:
			c.pre_tick(self)
	for bu in heroes:
		if not bu.alive:
			continue
		bu.prev_pos = bu.pos
		var ctl = controllers[eteam(bu)]
		if bu.action and ctl and ctl.has_method("emergency") and ctl.emergency(bu):
			cancel_action(bu, "emergency")
		_update_action(bu)
		if ctl and bu.action == null and time >= bu.next_decision_at and not decision_blocked(bu):
			ctl.decide(bu)
			bu.decisions += 1
		_try_execute_command(bu)
		_update_movement(bu, DT)
	_resolve_collisions()
	proj.update(DT)
	zones.update(DT)
	kits.update_entities(DT)
	kits.update_contacts(DT)
	for body in bodies_alive():
		warfare.constrain(body, body.prev_pos)
	env.update(DT)
	kits.nexus_tick(DT)
	if is_control_mode(): domination.update(DT)
	elif deathmatch: deathmatch.update(DT)
	if tick % 15 == 0:
		_record_history()
	_check_end()
	return true



var profiling: = false
var prof: Dictionary = {}


func _pf(key: String, t0: int) -> int:
	var t1: = Time.get_ticks_usec()
	prof[key] = int(prof.get(key, 0)) + (t1 - t0)
	return t1


func _step_profiled() -> bool:
	time += DT
	tick += 1
	ai_events = tick_events
	tick_events = []
	var t: = Time.get_ticks_usec()
	if is_control_mode(): domination.pre_tick()
	elif deathmatch: deathmatch.pre_tick()
	_prune_entities()
	_update_visibility()
	t = _pf("visibility", t)
	_update_statuses(DT)
	warfare.update(DT)
	kits.update_passives(DT)
	t = _pf("status+passive", t)
	for c in controllers:
		if c:
			c.pre_tick(self)
	t = _pf("ai.pre_tick", t)
	for bu in heroes:
		if not bu.alive:
			continue
		bu.prev_pos = bu.pos
		var ctl = controllers[eteam(bu)]
		if bu.action and ctl and ctl.has_method("emergency") and ctl.emergency(bu):
			cancel_action(bu, "emergency")
		t = _pf("ai.emergency", t)
		_update_action(bu)
		t = _pf("action", t)
		if ctl and bu.action == null and time >= bu.next_decision_at and not decision_blocked(bu):
			ctl.decide(bu)
			bu.decisions += 1
		t = _pf("ai.decide", t)
		_try_execute_command(bu)
		t = _pf("execute", t)
		_update_movement(bu, DT)
		t = _pf("movement(+steer)", t)
	_resolve_collisions()
	t = _pf("collisions", t)
	proj.update(DT)
	t = _pf("projectiles", t)
	zones.update(DT)
	t = _pf("zones", t)
	kits.update_entities(DT)
	t = _pf("entities", t)
	kits.update_contacts(DT)
	for body in bodies_alive():
		warfare.constrain(body, body.prev_pos)
	env.update(DT)
	kits.nexus_tick(DT)
	if is_control_mode(): domination.update(DT)
	elif deathmatch: deathmatch.update(DT)
	t = _pf("contacts+env+nexus", t)
	if tick % 15 == 0:
		_record_history()
	_check_end()
	return true


func _record_history() -> void :
	var row: = [time, 0.0, 0.0]
	if team_count > 2:
		row.resize(team_count + 1)
		row.fill(0.0)
		row[0] = time
	for u in heroes:
		if u.alive:
			row[1 + u.team] += u.hp
	history.append(row)


func _prune_entities() -> void :
	if entities.is_empty():
		return
	var keep: Array[BUnit] = []
	for e in entities:
		if e.alive and e.end_time > time:
			keep.append(e)
		elif e.alive:
			e.alive = false
			e.death_time = time
			emit("SUMMON_EXPIRED", e.owner_idx, e.idx, {"kind": e.kind})
	entities = keep


func _check_end() -> void :
	if is_control_mode():
		domination.check_end()
		return
	if deathmatch:
		deathmatch.check_end()
		return
	var alive: = [0, 0]
	for u in heroes:
		if u.alive:
			alive[u.team] += 1
	if alive[0] == 0 or alive[1] == 0:
		finish(0 if alive[0] > 0 else (1 if alive[1] > 0 else 2), "elimination")
		return
	if time >= max_time:
		var score: = [0.0, 0.0]
		for u in heroes:
			if u.alive:
				score[u.team] += u.hp + shield_amount(u)
		var w: = 2
		if absf(score[0] - score[1]) >= 1.0:
			w = 0 if score[0] > score[1] else 1
		finish(w, "time_limit")


func finish(w: int, reason: String) -> void :
	if state == FINISHED:
		return
	state = FINISHED
	winner = w
	finish_reason = reason
	for u in heroes:
		u.action = null
		u.command = {}
	_record_history()
	emit("BATTLE_ENDED", -1, -1, {"winner": w, "reason": reason, "duration": time})






func emit(type: String, s: int, g: int, data: Dictionary = {}) -> Dictionary:
	var ev: = data
	ev["type"] = type
	ev["t"] = time
	ev["s"] = s
	ev["g"] = g

	var sv: = [false, false]
	var gv: = [false, false]
	if team_count > 2:
		sv.resize(team_count)
		gv.resize(team_count)
		sv.fill(false)
		gv.fill(false)
	for team in team_count:
		if s >= 0 and s < units.size():
			var su: BUnit = units[s]
			sv[team] = eteam(su) == team or is_seen(team, su)
		if g >= 0 and g < units.size():
			var gu: BUnit = units[g]
			gv[team] = eteam(gu) == team or is_seen(team, gu)
	ev["sv"] = sv
	ev["gv"] = gv
	tick_events.append(ev)
	if collect_frame_events:
		frame_events.append(ev)
	if not data.get("silent", false) and type in LOG_TYPES:
		log.append(ev)
		if log.size() > log_limit:
			log = log.slice(log.size() - int(log_limit * 0.8))
	return ev


func fx(kind: String, pos: Vector2, data: Dictionary = {}) -> void :

	if not collect_frame_events:
		return
	data["type"] = "FX"
	data["kind"] = kind
	data["pos"] = pos
	data["t"] = time
	frame_events.append(data)


func drain_frame_events() -> Array:
	var out: = frame_events
	frame_events = []
	return out






func u_at(i: int) -> BUnit:
	if i < 0 or i >= units.size():
		return null
	return units[i]


func eteam(u: BUnit) -> int:
	for s in u.statuses:
		if s.type == &"control" and s.end > time:
			return int(s.extra.get("controller_team", 1 - u.team))
	return u.team


func bodies_alive() -> Array[BUnit]:
	var out: Array[BUnit] = []
	for u in heroes:
		if u.alive:
			out.append(u)
	for e in entities:
		if e.alive:
			out.append(e)
	return out


func opponents(u: BUnit) -> Array[BUnit]:
	var t: = eteam(u)
	var out: Array[BUnit] = []
	for o in heroes:
		if o.alive and o != u and eteam(o) != t and not has_status(o, &"untargetable"):
			out.append(o)
	for e in entities:
		# V2: an untargetable entity (achilles' chariot) is nobody's target.
		if e.alive and e.end_time > time and eteam(e) != t and not has_status(e, &"untargetable"):
			out.append(e)
	return out


func allies_of(team: int, include_entities: bool = false) -> Array[BUnit]:
	var out: Array[BUnit] = []
	for o in heroes:
		if o.alive and eteam(o) == team:
			out.append(o)
	if include_entities:
		for e in entities:
			if e.alive and eteam(e) == team:
				out.append(e)
	return out


func hp_ratio(u: BUnit) -> float:
	return u.hp / maxf(1.0, max_hp(u))


func max_hp(u: BUnit) -> float:
	return stat(u, S_HP)


func radius(u: BUnit) -> float:
	if u.is_hero and u.def.id == "giant":
		return u.base_radius * (0.85 + 0.3 * clampf(u.hp / maxf(1.0, stat(u, S_HP)), 0.0, 1.0))
	return u.base_radius


func radius_scale(u: BUnit) -> float:
	return radius(u) / maxf(1.0, u.base_radius)


func clamp_pos(p: Vector2, r: float = 0.0) -> Vector2:
	return arena.resolve_circle(p, r)


func los(a: Vector2, b: Vector2, pad: float = 2.0) -> bool:
	return arena.line_of_sight(a, b, pad)


func distance_to_wall(p: Vector2) -> float:
	return arena.distance_to_wall(p)


func wall_tangent(p: Vector2) -> Vector2:
	return arena.nearest_wall(p).tangent






func stat(u: BUnit, key: StringName) -> float:
	if u == null:
		return 0.0
	if key == &"bodyRadius":
		return radius(u)
	var k: = key
	if u.is_hero and (key == S_AD or key == S_AP):
		for b in u.buffs:
			if b.stat == &"originStatSwap" and b.end > time:
				k = S_AP if key == S_AD else S_AD
				break
	var base: = float(u.def.stats.get(String(k), 0.0))
	var ratio: = 0.0
	var flat: = 0.0
	var flat_key: = StringName(String(k) + "Flat")
	var propaganda: float = 0.0
	for b in u.buffs:
		if b.end <= time:
			continue
		if b.stat == k:
			if b.tag == "propaganda":
				propaganda = maxf(propaganda, b.amount)
			else:
				ratio += b.amount
		elif b.stat == flat_key:
			flat += b.amount
	var v: = base * (1.0 + ratio + propaganda) + flat
	if not u.is_hero:
		return maxf(0.0, v)
	if k == S_AS:
		var bm: = get_buff(u, &"attackSpeedByMove")
		if bm:
			v += base * minf(float(bm.extra.get("cap", 0.65)), bm.amount * stat(u, S_MS) / maxf(1.0, u.base_ms))
		v *= overdrive_mult(u)
	elif k == S_MS:
		var ooc: = u.def.rule("out_of_combat_speed")
		if not ooc.is_empty() and time - u.last_combat_time >= float(ooc.get("delay", 2.5)):
			v *= 1.0 + float(ooc.get("bonus", 1.2)) * clampf(time - u.last_combat_time - float(ooc.get("delay", 2.5)), 0.0, 1.0)
		var rage: = u.def.rule("rage_on_damage")
		if not rage.is_empty():
			v *= 1.0 + float(u.resources.get("rage", 0)) * float(rage.get("movePerStack", 0.03))
			if u.ks.get("wall_near", false) and u.vel.length_squared() > 4.0:
				if absf(u.vel.normalized().dot(wall_tangent(u.pos))) > 0.7:
					v *= 1.0 + float(u.def.rule("wall_mastery").get("speedBonus", 0.35))
		if float(u.ks.get("scent_until", -1.0)) > time and get_buff(u, &"originScent"):
			v *= 1.35
		var sl: = get_status(u, &"slow")
		if sl:
			v *= 1.0 - clampf(sl.magnitude, 0.0, 0.9)
		v *= 1.0 - warfare.pain_slow(u)
		v *= overdrive_mult(u)
		# V2 battleground: a downed hero crawls (x0.35, not a slow: no tenacity).
		if battleground != null and battleground.downed.has(u.idx):
			v *= BattlegroundMode.DOWNED_SPEED
	elif k == S_AD:
		if u.def.id == "nitro":
			v *= 1.0 + float(u.resources.get("rage", 0)) * float(u.def.rule("rage_on_damage").get("attackPerStack", 0.035))
	elif k == S_ARMOR or k == S_MR:
		if k == S_ARMOR and has_status(u, &"imprisoned"):
			v *= 0.75
		if u.def.id == "giant":
			v *= 1.0 + 0.25 * clampf(u.hp / maxf(1.0, stat(u, S_HP)), 0.0, 1.0)
		if float(u.ks.get("scent_until", -1.0)) > time and get_buff(u, &"originScent"):
			v *= 1.25
	elif k == S_TEN:
		var worst: = 0.0
		for s in u.statuses:
			if s.type == &"confusion" and s.end > time:
				worst = maxf(worst, float(s.extra.get("tenacityLoss", 0.025)) * s.stacks)
		v -= worst
		# V2 roar (achilles S3) is the only tenacity loss allowed below zero
		# (floor -0.3; negative tenacity lengthens crowd control). Confusion keeps
		# its floor at 0.
		var roar: = roar_loss(u)
		if roar > 0.0:
			return maxf(-0.3, maxf(0.0, v) - roar)
	return maxf(0.0, v)


# V2: true attack/move speed multiplier of war_machine's overdrive status.
func overdrive_mult(u: BUnit) -> float:
	for s in u.statuses:
		if s.type == &"overdrive" and s.end > time:
			return float(s.extra.get("mult", 1.5))
	return 1.0


func roar_loss(u: BUnit) -> float:
	var worst: = 0.0
	for s in u.statuses:
		if s.type == &"roar" and s.end > time:
			worst = maxf(worst, float(s.extra.get("tenacityLoss", 0.1)))
	return worst


func get_buff(u: BUnit, key: StringName) -> ST.Buff:
	for b in u.buffs:
		if b.stat == key and b.end > time:
			return b
	return null


func buff_sum(u: BUnit, key: StringName) -> float:
	var s: = 0.0
	for b in u.buffs:
		if b.stat == key and b.end > time:
			s += b.amount
	return s


func add_buff(u: BUnit, key: StringName, amount: float, duration: float, source_idx: int, extra: Dictionary = {}) -> void :
	if u == null or duration < 0.0:
		return
	var tag: = str(extra.get("tag", extra.get("ability_id", String(key))))
	var before_max: = stat(u, S_HP) if key == S_HP else 0.0
	for b in u.buffs:
		if b.stat == key and b.source_idx == source_idx and b.tag == tag and b.end > time:
			b.amount = amount
			b.end = time + duration
			b.extra = extra
			if key == S_HP and amount > 0.0:
				u.hp += maxf(0.0, stat(u, S_HP) - before_max)
			return
	var nb: = ST.Buff.new()
	nb.stat = key
	nb.amount = amount
	nb.end = time + duration
	nb.source_idx = source_idx
	nb.tag = tag
	nb.extra = extra
	u.buffs.append(nb)
	if key == S_HP and amount > 0.0:
		u.hp += maxf(0.0, stat(u, S_HP) - before_max)


func remove_buffs_tag(u: BUnit, tag: String) -> void :
	var keep: Array[ST.Buff] = []
	for b in u.buffs:
		if b.tag != tag:
			keep.append(b)
	u.buffs = keep


func get_status(u: BUnit, type: StringName) -> ST.Status:
	if type != &"slow":
		for s in u.statuses:
			if s.type == type and s.end > time:
				return s
		return null
	var best: ST.Status = null
	for s in u.statuses:
		if s.type == &"slow" and s.end > time:
			if best == null or s.magnitude > best.magnitude or (s.magnitude == best.magnitude and s.end > best.end):
				best = s
	return best


func has_status(u: BUnit, type: StringName) -> bool:
	for s in u.statuses:
		if s.type == type and s.end > time:
			return true
	return false


func has_any(u: BUnit, types: Array) -> bool:
	for s in u.statuses:
		if s.end > time and types.has(s.type):
			return true
	return false


func owned_status(u: BUnit, type: StringName, source_idx: int) -> ST.Status:
	if u == null:
		return null
	for s in u.statuses:
		if s.type == type and s.source_idx == source_idx and s.end > time:
			return s
	return null


func stacks(u: BUnit, type: StringName) -> int:
	var s: = get_status(u, type)
	return s.stacks if s else 0


func is_cc_type(t: StringName) -> bool:
	return CC_TYPES.has(t)


func is_crowd_controlled(u: BUnit) -> bool:
	for s in u.statuses:
		if s.end > time and s.type != &"slow" and CC_TYPES.has(s.type):
			return true
	return false


func shield_amount(u: BUnit) -> float:
	var total: = 0.0
	for sh in u.shields:
		if sh.end > time:
			total += maxf(0.0, sh.amount)
	return total


func decision_blocked(u: BUnit) -> bool:
	return u.chamber != "" or u.motion != null


func can_cast(u: BUnit) -> bool:
	if not u.alive or u.motion != null or u.chamber != "":
		return false
	if float(u.ks.get("glide_until", -1.0)) > time:
		return false
	# V2 battleground: downed heroes and revive channellers neither cast nor attack.
	if battleground != null and battleground.blocks_actions(u):
		return false
	return not has_any(u, NO_CAST)


func can_basic(u: BUnit) -> bool:
	if u.def.has_rule("no_basic"):
		return false
	if not u.alive or u.motion != null or u.chamber != "":
		return false
	if battleground != null and battleground.blocks_actions(u):
		return false
	if float(u.ks.get("glide_until", -1.0)) > time:
		return false
	return time >= u.attack_ready_at and not has_any(u, NO_BASIC)






func sensor_range(u: BUnit) -> float:
	if deathmatch and u.is_hero:
		return vision_range + deathmatch.vision_bonus(u)
	return vision_range if u.is_hero else ENTITY_VISION



func observes(s: BUnit, t: BUnit) -> bool:
	if s == null or t == null or not s.alive or not t.alive:
		return false
	if s == t:
		return true
	if eteam(s) == eteam(t):
		return true
	if s.chamber != t.chamber:
		return false
	# V2: an entity flagged visible_untargetable (achilles' chariot) can be
	# seen (and dodged) like any body; it still cannot be targeted.
	if has_status(t, &"untargetable") and not bool(t.ks.get("visible_untargetable", false)):
		return false
	var rs: = radius(s)
	var rt: = radius(t)
	var d: = s.pos.distance_to(t.pos)
	if d > sensor_range(s) + rs + rt:
		return false
	if has_status(t, &"invisible"):
		var close: = d <= rs + rt + 62.0
		var revealed: = time - t.last_damage_time <= 0.55 or time - t.last_combat_time <= 0.35
		if not close and not revealed:
			return false
	if brush_on and not arena.forest_x.is_empty():
		# Brush / canopy (all modes): a unit inside a patch is hidden from anyone
		# outside that patch until they come close or it fights.
		var tp: int = arena.forest_at(t.pos)
		if tp >= 0 and arena.forest_at(s.pos) != tp:
			var reveal: float = deathmatch.forest_reveal_range(s, t) if deathmatch and s.is_hero else 110.0
			if d > reveal + rs + rt and time - t.last_combat_time > 0.8:
				return false
		if arena.forest_occludes(s.pos, t.pos):
			return false
	return arena.line_of_sight(s.pos, t.pos, minf(8.0, rt * 0.18))


func _update_visibility() -> void :
	if not vis_exhaustive:
		var flat: PackedByteArray = _visibility_flat()
		var size: int = units.size()
		for team_i in team_count:
			seen[team_i] = flat.slice(team_i * size, team_i * size + size)
		return
	_update_visibility_exhaustive()


# The original team x target x sensor scan (B-PERF keeps it as the reference:
# BattleSim.vis_exhaustive = true runs it, tests compare it with the fast pass).
func _update_visibility_exhaustive() -> void :
	var n: = units.size()
	for team in team_count:
		var arr: PackedByteArray = seen[team]
		if arr.size() != n:
			arr.resize(n)
		arr.fill(0)
		seen[team] = arr
	var bodies: = bodies_alive()
	for team in team_count:
		var sensors: Array[BUnit] = []
		for b in bodies:
			if eteam(b) == team:
				sensors.append(b)
		var arr2: PackedByteArray = seen[team]
		for t in bodies:
			if eteam(t) == team:
				arr2[t.idx] = 1
				continue
			for s in sensors:
				if observes(s, t):
					arr2[t.idx] = 1
					break
		seen[team] = arr2


func is_seen(team: int, u: BUnit) -> bool:
	if u == null:
		return false
	if eteam(u) == team:
		return true
	var arr: PackedByteArray = seen[team]
	return u.idx < arr.size() and arr[u.idx] == 1


func point_seen(team: int, p: Vector2) -> bool:
	for b in bodies_alive():
		if eteam(b) != team:
			continue
		if b.pos.distance_to(p) <= sensor_range(b) and arena.line_of_sight(b.pos, p, 2.0):
			return true
	return false






func context(u: BUnit, a: Defs.AbilityDef, extra: Dictionary = {}) -> Dictionary:
	var c: = {"ability": a, "source_type": "ABILITY" if a else "BASIC_ATTACK", "action_id": next_id(), "source_origin": u.pos}
	for k in extra:
		c[k] = extra[k]
	return c


func outgoing_mult(s: BUnit, t: BUnit, basic: bool, projectile: bool) -> float:
	if not s.is_hero:
		return 1.0
	var m: = 1.0 + buff_sum(s, &"damageDealt")
	if basic:
		m *= 1.0 + buff_sum(s, &"basicDamage") + buff_sum(s, &"nextBasicDamage")
	if projectile:
		m *= 1.0 + buff_sum(s, &"projectileDamage")
	var dr: = s.def.rule("distance_damage")
	if not dr.is_empty() and t:
		m *= 1.0 + float(dr.maxBonus) * clampf((s.pos.distance_to(t.pos) - radius(s) - radius(t)) / float(dr.fullDistance), 0.0, 1.0)
	if s.def.id == "giant" and t and s.hp > t.hp:
		m *= 1.0 + 0.12 * clampf((s.hp - t.hp) / maxf(1.0, stat(s, S_HP)), 0.0, 1.0)
	return m


func ability_coefficient(u: BUnit) -> float:
	var bonus: float = 0.0
	for b in u.buffs:
		if b.stat == &"abilityCoefficient" and b.end > time:
			bonus = maxf(bonus, b.amount)
	if warfare.contemplating(u):
		bonus += 0.30
	return 1.0 + bonus


func forced_target(u: BUnit) -> BUnit:
	var taunt: ST.Status = get_status(u, &"taunt")
	if taunt and taunt.extra.has("forced_target"):
		var target: BUnit = u_at(int(taunt.extra.forced_target))
		var source: BUnit = u_at(taunt.source_idx)
		if target and target.alive and source and source.alive and eteam(target) != eteam(u):
			return target
	return null


func incoming_mult(t: BUnit) -> float:
	var by: Dictionary = {}
	for s in t.statuses:
		if s.end <= time or s.type == &"bladeMark":
			continue
		var r: = float(s.extra.get("damageAmp", 0.0))
		if s.type == &"confusion" and r == 0.0:
			r = 0.03
		if r == 0.0:
			continue
		by[s.type] = maxf(float(by.get(s.type, 0.0)), r * s.stacks)
	var m: = 1.0
	for k in by:
		m *= 1.0 + float(by[k])
	# V2: damageTaken ratio buffs (war_machine arc protector -0.4), floor 0.1x.
	var taken: = buff_sum(t, &"damageTaken")
	if taken != 0.0:
		m *= maxf(0.1, 1.0 + taken)
	return m


func resist_mult(r: float) -> float:
	return 100.0 / (100.0 + r) if r >= 0.0 else 2.0 - 100.0 / (100.0 - r)



func freeze_effects(s: BUnit, t: BUnit, effects: Array, basic: bool, projectile: bool) -> Array:
	var out: Array = []
	var coefficient: float = 1.0 if basic else ability_coefficient(s)
	for f0 in effects:
		var f: Dictionary = (f0 as Dictionary).duplicate()
		if str(f.get("type", "")) == "damage" and not f.get("frozen", false):
			var m: = 1.0 + buff_sum(s, &"damageDealt") if s.is_hero else 1.0
			if s.is_hero:
				if basic:
					m *= 1.0 + buff_sum(s, &"basicDamage") + buff_sum(s, &"nextBasicDamage")
				if projectile:
					m *= 1.0 + buff_sum(s, &"projectileDamage")
				var dr: = s.def.rule("distance_damage")
				if not dr.is_empty() and t:
					var bonus: = float(dr.maxBonus) * clampf((s.pos.distance_to(t.pos) - radius(s) - radius(t)) / float(dr.fullDistance), 0.0, 1.0)
					m *= 1.0 + bonus
			if f.get("scaleWithRadius", false):
				m *= radius_scale(s)
			var res_bonus: = 0.0
			if f.has("perSelfResource"):
				res_bonus = float(s.resources.get(str(f.perSelfResource.key), 0)) * float(f.perSelfResource.amount)
			f["base"] = (float(f.get("base", 0.0)) + (float(f.get("ad", 0.0)) * stat(s, S_AD) + float(f.get("ap", 0.0)) * stat(s, S_AP) + float(f.get("selfMaxHp", 0.0)) * stat(s, S_HP)) * coefficient + res_bonus) * m
			f["ad"] = 0.0
			f["ap"] = 0.0
			f["selfMaxHp"] = 0.0
			f["scaleWithRadius"] = false
			f.erase("perSelfResource")
			if f.has("targetMaxHp"): f["targetMaxHp"] = float(f.targetMaxHp) * m
			if f.has("targetMissingHp"): f["targetMissingHp"] = float(f.targetMissingHp) * m
			if f.has("perTargetStatusStack"):
				var pts: Dictionary = (f.perTargetStatusStack as Dictionary).duplicate()
				pts["amount"] = float(pts.amount) * m
				f["perTargetStatusStack"] = pts
			f["frozen"] = true
		if f.has("effects"):
			f["effects"] = freeze_effects(s, t, f.effects, basic, projectile)
		if f.has("damageEffect"):
			f["damageEffect"] = freeze_effects(s, t, [f.damageEffect], basic, projectile)[0]
		out.append(f)
	return out


func scale_damage(effects: Array, scale: float) -> Array:
	var out: Array = []
	for f0 in effects:
		var f: Dictionary = (f0 as Dictionary).duplicate()
		if str(f.get("type", "")) == "damage":
			f["base"] = float(f.get("base", 0.0)) * scale
			f["ad"] = float(f.get("ad", 0.0)) * scale
			f["ap"] = float(f.get("ap", 0.0)) * scale
			for k in ["selfMaxHp", "targetMaxHp", "targetMissingHp"]:
				if f.has(k):
					f[k] = float(f[k]) * scale
		if f.has("effects"):
			f["effects"] = scale_damage(f.effects, scale)
		if f.has("damageEffect"):
			f["damageEffect"] = scale_damage([f.damageEffect], scale)[0]
		out.append(f)
	return out






func realm_allowed(s: BUnit, t: BUnit, ctx: Dictionary) -> bool:
	if s == null or t == null:
		return t == null or t.chamber == ""
	var a: String = ctx.get("realm", s.chamber) if ctx.has("realm") else s.chamber
	return a == t.chamber



func apply_damage(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> float:
	if s == null or t == null or not t.alive:
		return 0.0
	if respawns and not s.alive:
		return 0.0
	if not realm_allowed(s, t, ctx):
		return 0.0
	# V2 battleground: a downed hero deals no damage of its own (damage over
	# time it applied before going down keeps ticking).
	if battleground != null and s != t and battleground.downed.has(s.idx) and str(ctx.get("source_type", "ABILITY")) != "PERSISTENT":
		return 0.0
	if respawns and eteam(s) != eteam(t):
		break_protection(s)
	if has_status(t, &"invulnerable"):
		emit("DAMAGE_IMMUNE", s.idx, t.idx, {"ability": ctx.get("ability")})
		return 0.0
	if front_blocks(s, t, ctx):
		emit("FRONT_BLOCKED", s.idx, t.idx, {"kind": "damage", "ability": ctx.get("ability"), "pos": t.pos})
		return 0.0
	var before: = t.hp
	var base: = float(f.get("base", 0.0))
	if f.has("originCcAd") and is_crowd_controlled(t):
		base += float(f.originCcAd) * stat(s, S_AD)
	var raw: = 0.0
	var frozen: bool = f.get("frozen", false) or ctx.get("snapshot", false)
	if frozen:
		raw = base
	else:
		raw = base + (float(f.get("ad", 0.0)) * stat(s, S_AD) + float(f.get("ap", 0.0)) * stat(s, S_AP) + float(f.get("selfMaxHp", 0.0)) * stat(s, S_HP)) * (1.0 if ctx.get("basic", false) else ability_coefficient(s))
		if f.has("perSelfResource"):
			raw += float(s.resources.get(str(f.perSelfResource.key), 0)) * float(f.perSelfResource.amount)
		if f.get("scaleWithRadius", false):
			raw *= radius_scale(s)
	raw += float(f.get("targetMaxHp", 0.0)) * stat(t, S_HP)
	raw += float(f.get("targetMissingHp", 0.0)) * maxf(0.0, stat(t, S_HP) - t.hp)
	if f.has("perTargetStatusStack"):
		var pts: Dictionary = f.perTargetStatusStack
		var own: = owned_status(t, StringName(str(pts.status)), s.idx)
		raw += (own.stacks if own else 0) * float(pts.amount)
	var mult: = float(ctx.get("damage_mult", 1.0))
	if not frozen:
		mult *= outgoing_mult(s, t, ctx.get("basic", false), ctx.has("projectile"))
	if ctx.get("basic", false) and get_buff(s, &"originPredator"):
		mult *= 1.0 + 0.4 * clampf((before - s.hp) / maxf(1.0, stat(s, S_HP)), 0.0, 1.0)
	if frozen and s.is_hero and s.def.id == "giant" and not ctx.get("reflected", false) and ctx.has("src_hp"):
		mult *= 1.0 + 0.12 * clampf((float(ctx.src_hp) - before) / maxf(1.0, float(ctx.get("src_max", stat(s, S_HP)))), 0.0, 1.0)
	raw *= mult * incoming_mult(t)
	if deathmatch:
		raw *= deathmatch.outgoing_mult(s, t, ctx) * deathmatch.incoming_mult(t)
	# V2: an entity with an area ratio (war_machine fuel tank) takes less from
	# area, zone and cone hits.
	if not t.is_hero and ctx.get("area", false) and t.ks.has("area_taken"):
		raw *= float(t.ks.area_taken)
	var critical: bool = ctx.get("crit", false)
	var school: = str(f.get("school", "physical"))
	var post: = raw
	if school == "magic":
		post = raw * resist_mult(stat(t, S_MR) * (1.0 - (deathmatch.mr_pen(s) if deathmatch and s.is_hero else 0.0)))
	elif school == "physical":
		var armor: = stat(t, S_ARMOR)
		# V2 achilles passive: armor x(1+ratio) against basic attacks only.
		if t.is_hero and ctx.get("basic", false) and armor > 0.0 and t.def.has_rule("basic_armor_bonus"):
			armor *= 1.0 + float(t.def.rule("basic_armor_bonus").get("ratio", 0.0))
		post = raw * resist_mult(armor)
	else:
		var rage: = t.def.rule("rage_on_damage") if t.is_hero else {}
		if not rage.is_empty():
			post *= 1.0 - minf(0.45, float(t.resources.get("rage", 0)) * float(rage.get("trueResistPerStack", 0.025)))
	var mitigated: = maxf(0.0, raw - post)
	var absorbed: = _absorb_shields(t, maxf(0.0, post))
	var remaining: = maxf(0.0, post) - absorbed
	var hpdmg: = minf(maxf(0.0, t.hp), remaining)
	t.hp -= hpdmg
	s.st_damage += hpdmg
	t.st_taken += hpdmg
	t.st_mitigated += mitigated
	if ctx.get("basic", false) and (hpdmg > 0.0 or absorbed > 0.0):
		s.st_basic_hits += 1
	# V2: bites of the new summon kinds (cerberus, shades) keep their owner's
	# combat timer, so the owner stays concealed; the body's own timer runs.
	var body: BUnit = u_at(int(ctx.summon_body)) if ctx.has("summon_body") else null
	if body:
		body.last_combat_time = time
	else:
		s.last_combat_time = time
	t.last_combat_time = time
	t.last_damage_time = time
	var ab = ctx.get("ability")
	emit("HEALTH_DAMAGED" if hpdmg > 0.0 else "SHIELD_ABSORBED", s.idx, t.idx, {
		"amount": hpdmg, "absorbed": absorbed, "school": school, "crit": critical, 
		"execute": ctx.get("execute", false), "ability": ab, "source_type": ctx.get("source_type", "ABILITY"), 
		"slot": (ab as Defs.AbilityDef).slot if ab is Defs.AbilityDef else 0, 
		"basic": ctx.get("basic", false), "projectile": ctx.get("projectile", -1), "pos": t.pos})
	if hpdmg > 0.0:
		var sl: = get_status(t, &"sleep")
		if sl and sl.extra.get("breaksOnDamage", false):
			t.statuses.erase(sl)
	kits.on_damage_dealt(s, t, hpdmg, absorbed, f, ctx, before)
	if deathmatch:
		deathmatch.on_damage(s, t, hpdmg, absorbed, ctx)
	if s.alive and f.has("sourceHealRatio") and hpdmg > 0.0:
		apply_heal(s, s, {"base": hpdmg * float(f.sourceHealRatio)}, {"source_type": "ABILITY", "ability": ab})
	var vamp: = buff_sum(s, &"omnivamp")
	if s.alive and vamp > 0.0 and hpdmg > 0.0:
		apply_heal(s, s, {"base": hpdmg * vamp}, {"source_type": "OMNIVAMP", "silent": true})
	if t.alive and t.hp > 0.0 and post > 0.0:
		_arc_convert(t, post)
	if t.hp <= 0.0 and t.alive:
		kill_unit(t, s, {"ability": ab, "execute": ctx.get("execute", false)})
	return hpdmg


# V2 war_machine arc protector: part of the mitigated damage taken becomes a
# shield on the victim (capped per buff; shields carry the "arc" tag).
func _arc_convert(t: BUnit, taken: float) -> void:
	var arc: = get_buff(t, &"arcConvert")
	if arc == null or arc.amount <= 0.0:
		return
	var cur: = 0.0
	for sh in t.shields:
		if sh.tag == "arc" and sh.end > time:
			cur += sh.amount
	var cap: = stat(t, S_HP) * float(arc.extra.get("capRatio", 0.2))
	var gain: = minf(taken * arc.amount, maxf(0.0, cap - cur))
	if gain > 0.01:
		apply_shield(t, t, {"base": gain, "duration": float(arc.extra.get("shieldDuration", 4.0))}, {"proc": true, "silent": true, "shield_tag": "arc"})


# V2 achilles front guard: true when an enemy's direct hit, crowd control or
# displacement comes from inside the guarded arc. Zone ticks, damage over time
# and pain ticks are not frontal and pass; ctx.attack_from (area centre, body
# of a summon or chariot) overrides the attacker's position.
func front_blocks(s: BUnit, t: BUnit, ctx: Dictionary) -> bool:
	if t == null or not t.is_hero or t.statuses.is_empty():
		return false
	var g: ST.Status = get_status(t, &"frontGuard")
	if g == null or s == null or eteam(s) == eteam(t):
		return false
	if str(ctx.get("source_type", "")) in ["ZONE", "PERSISTENT"] or ctx.get("pain_tick", false):
		return false
	var from: Vector2 = ctx.get("attack_from", s.pos)
	return guard_faces(g, t.pos, from)


func guard_faces(g: ST.Status, at: Vector2, from: Vector2) -> bool:
	var v: = from - at
	if v.length_squared() < 1e-06:
		return true
	var dir: Vector2 = g.extra.get("dir", Vector2.RIGHT)
	return v.normalized().dot(dir) >= cos(float(g.extra.get("arc", deg_to_rad(120.0))) * 0.5) - 1e-06


func _absorb_shields(t: BUnit, incoming: float) -> float:
	if t.shields.is_empty() or incoming <= 0.0:
		return 0.0
	t.shields.sort_custom( func(a, b): return a.end < b.end or (a.end == b.end and a.seq < b.seq))
	var remaining: = incoming
	var absorbed: = 0.0
	var keep: Array[ST.Shield] = []
	for sh in t.shields:
		if sh.end <= time or sh.amount <= 0.01:
			continue
		if remaining > 0.0:
			var take: = minf(sh.amount, remaining)
			sh.amount -= take
			remaining -= take
			absorbed += take
			var g: = u_at(sh.source_idx)
			if g:
				g.st_shielding += take
			if sh.amount <= 0.01:
				emit("SHIELD_BROKEN", sh.source_idx, t.idx, {"pos": t.pos})
				continue
		keep.append(sh)
	t.shields = keep
	return absorbed


func apply_heal(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var zero: = {"raw": 0.0, "effective": 0.0, "reduced": 0.0}
	if s == null or t == null or not t.alive:
		return zero
	if respawns and not s.alive:
		return zero
	# V2 battleground: downed health is a separate pool; only a revive restores it.
	if battleground != null and battleground.downed.has(t.idx):
		return zero
	if not realm_allowed(s, t, ctx):
		return zero
	var mx: = stat(t, S_HP)
	var missing: = maxf(0.0, mx - t.hp)
	var raw: = maxf(0.0, float(f.get("base", 0.0)) + float(f.get("ap", 0.0)) * stat(s, S_AP) * ability_coefficient(s) + float(f.get("missingHp", 0.0)) * missing)
	var received: = buff_sum(t, &"healingReceived")
	if received != 0.0:
		raw *= maxf(0.0, 1.0 + received)
	if raw <= 0.0:
		return zero
	var red: = 0.0
	var credit: ST.Status = null
	for st in t.statuses:
		if st.end <= time:
			continue
		var r: = 0.0
		if st.type == &"plague":
			r = minf(0.6, st.stacks * 0.1)
		elif st.type == &"healReduction":
			r = st.magnitude if st.magnitude > 0.0 else 0.35
		if r > red + 1e-09:
			red = r
			credit = st
	red = clampf(red, 0.0, 1.0)
	var after: = raw * (1.0 - red)
	var effective: = clampf(after, 0.0, missing)
	if deathmatch and after > effective + 0.5:
		deathmatch.on_heal(t, after - effective)
	var reduced_eff: = maxf(0.0, minf(raw, missing) - effective)
	t.hp += effective
	s.st_healing += effective
	var silent: bool = ctx.get("silent", false)
	emit("HEAL_APPLIED", s.idx, t.idx, {"amount": effective, "raw": raw, "reduced": raw - after, "silent": silent, "ability": ctx.get("ability"), "pos": t.pos, "source_type": ctx.get("source_type", "ABILITY")})
	if reduced_eff > 0.0 and credit:
		var owner: = u_at(credit.source_idx)
		if owner and owner.is_hero and owner.def.has_rule("heal_reduction_bank"):
			var old: = float(owner.resources.get("healBank", 0.0))
			var stored: = minf(reduced_eff, maxf(0.0, 1200.0 - old))
			owner.resources["healBank"] = old + stored
			if stored > 0.5:
				emit("PASSIVE", owner.idx, t.idx, {"rule": "heal_reduction_bank", "detail": "치유 차단 %d 저장" % int(stored), "silent": true})
	kits.support_credit(s, t, effective, ctx)
	return {"raw": raw, "effective": effective, "reduced": reduced_eff}


func apply_shield(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> float:
	if s == null or t == null or not t.alive:
		return 0.0
	if respawns and not s.alive:
		return 0.0
	if not realm_allowed(s, t, ctx):
		return 0.0
	if battleground != null and battleground.downed.has(t.idx):
		return 0.0
	var amount: = float(f.get("base", 0.0)) + float(f.get("ap", 0.0)) * stat(s, S_AP) * ability_coefficient(s)
	if amount <= 0.0:
		return 0.0
	var sh: = ST.Shield.new()
	sh.amount = amount
	sh.max_amount = amount
	sh.end = time + float(f.get("duration", 3.0))
	sh.source_idx = s.idx
	sh.affection = ctx.get("affection", false)
	sh.tag = str(ctx.get("shield_tag", ""))
	sh.seq = next_id()
	t.shields.append(sh)
	emit("SHIELD_APPLIED", s.idx, t.idx, {"amount": amount, "silent": ctx.get("silent", false), "ability": ctx.get("ability"), "pos": t.pos})
	if not ctx.get("proc", false) and eteam(s) == eteam(t) and s != t:
		kits.support_credit(s, t, amount, ctx)
	return amount






func apply_status(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> bool:
	if t == null or not t.alive:
		return false
	if respawns and s != null and not s.alive:
		return false
	if s and not realm_allowed(s, t, ctx):
		return false
	var type: = StringName(str(f.get("status", "")))
	var cc: = is_cc_type(type)
	if cc and warfare.contemplating(t):
		emit("CC_IMMUNE", s.idx if s else -1, t.idx, {"status": String(type), "reason": "contemplation"})
		return false
	var harmful: = cc or type == &"healReduction" or type == &"damageAmp" or type == &"roar"
	if t.kind == "bed" and cc:
		return false
	if t.structure and cc and type != &"stun":
		return false
	if harmful and (has_status(t, &"invulnerable") or has_status(t, &"untargetable")):
		emit("CC_IMMUNE", s.idx if s else -1, t.idx, {"status": String(type)})
		return false
	if harmful and has_status(t, &"unstoppable"):
		emit("CC_IMMUNE", s.idx if s else -1, t.idx, {"status": String(type)})
		return false
	if harmful and front_blocks(s, t, ctx):
		emit("CC_IMMUNE", s.idx, t.idx, {"status": String(type), "reason": "front_guard"})
		emit("FRONT_BLOCKED", s.idx, t.idx, {"kind": "status", "status": String(type), "ability": ctx.get("ability"), "pos": t.pos})
		return false
	if deathmatch and cc and s and eteam(s) != eteam(t) and deathmatch.block_cc(t, type):
		emit("CC_IMMUNE", s.idx, t.idx, {"status": String(type), "reason": "item"})
		return false
	var dur: = maxf(0.0, float(f.get("duration", 0.0)))
	if cc and not f.get("originExactDuration", false) and not (type in [&"airborne", &"suppression", &"control"]):
		# Only roar can push tenacity below zero (longer crowd control).
		dur *= 1.0 - clampf(stat(t, S_TEN), -0.3, 0.95)
		# V2 per-status tenacity (torquemada: charm +50%), multiplicative.
		if t.is_hero and t.def.has_rule("status_tenacity"):
			dur *= 1.0 - clampf(float(t.def.rule("status_tenacity").get(String(type), 0.0)), 0.0, 0.95)
	if dur <= 0.0:
		return false
	var src_idx: = s.idx if s else -1
	var prior: ST.Status = null
	if type == &"slow":
		for x in t.statuses:
			if x.type == &"slow" and x.end > time and x.source_idx == src_idx and absf(x.magnitude - float(f.get("magnitude", 0.0))) < 1e-06:
				prior = x
				break
	else:
		prior = get_status(t, type)
	var fresh: = prior == null
	var extra: Dictionary = f.duplicate()
	if type == &"control" and s:
		extra["controller_team"] = eteam(s)
		extra["controller_idx"] = s.idx
	var end_t: = time + dur
	var horizon: = time
	if type == &"slow":
		for x in t.statuses:
			if x.type == &"slow" and x.end > time:
				horizon = maxf(horizon, x.end)
	elif prior:
		horizon = maxf(time, prior.end)
	var credit: = maxf(0.0, end_t - horizon)
	if prior:
		prior.end = maxf(prior.end, end_t)
		for k in extra:
			prior.extra[k] = extra[k]
		prior.magnitude = maxf(prior.magnitude, float(f.get("magnitude", 0.0)))
		if type == &"control" or type == &"taunt":
			prior.source_idx = src_idx
	else:
		var ns: = ST.Status.new()
		ns.type = type
		ns.source_idx = src_idx
		ns.start = time
		ns.end = end_t
		ns.duration = dur
		ns.stacks = int(f.get("stacks", 1))
		ns.magnitude = float(f.get("magnitude", 0.0))
		ns.extra = extra
		t.statuses.append(ns)
	if type == &"control":
		reset_commitment(t, "control")
	if type == &"taunt":
		reset_commitment(t, "taunt")
		if t.action:
			cancel_action(t, "taunt")
		if t.motion and not t.motion.unstoppable:
			kits._clear_transit(t)
	var ab = ctx.get("ability")
	emit("CC_APPLIED" if cc else "STATUS_APPLIED", src_idx, t.idx, {"status": String(type), "duration": credit if cc else dur, "nominal": dur, "fresh": fresh, "ability": ab, "pos": t.pos})
	if cc and s:
		s.st_cc += credit
		kits.on_cc_applied(s, t, type, credit, fresh, ctx)
	if f.get("originThenStun", 0.0) and fresh and s:
		schedule(end_t - time, {"kind": "status", "source": s.idx, "target": t.idx, "effect": {"status": "stun", "duration": float(f.originThenStun)}, "ctx": ctx})
	if cc and t.action and t.action.windup and not has_status(t, &"unstoppable"):
		if type in ACTION_BREAK or (type == &"silence" and t.action.kind == "ability"):
			cancel_action(t, "cc")
	return true


func apply_mark(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> bool:
	if respawns and s != null and not s.alive:
		return false
	if s == null or t == null or not t.alive:
		return false
	if not realm_allowed(s, t, ctx):
		return false
	if has_status(t, &"invulnerable") or has_status(t, &"untargetable"):
		return false
	var type: = StringName(str(f.get("status", "")))
	var cap: = int(f.get("maxStacks", 0))
	if cap <= 0:
		cap = 5 if type == &"confusion" else (6 if type == &"plague" or type == &"pain" else (4 if type == &"infection" else 1))
	var dur: = float(f.get("duration", 4.0))
	var ex: = owned_status(t, type, s.idx)
	if ex:
		ex.stacks = mini(cap, ex.stacks + int(f.get("stacks", 1)))
		ex.end = time + dur
		for k in f:
			ex.extra[k] = f[k]
	else:
		var ns: = ST.Status.new()
		ns.type = type
		ns.source_idx = s.idx
		ns.start = time
		ns.end = time + dur
		ns.duration = dur
		ns.stacks = mini(cap, int(f.get("stacks", 1)))
		ns.extra = f.duplicate()
		ns.extra["action_id"] = ctx.get("action_id", 0)
		t.statuses.append(ns)
		ex = ns
	emit("STATUS_APPLIED", s.idx, t.idx, {"status": String(type), "stacks": ex.stacks, "duration": dur, "ability": ctx.get("ability"), "mark": true, "pos": t.pos})
	return true


func apply_dot(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary = {}) -> bool:
	if s == null or t == null or not t.alive or has_status(t, &"invulnerable"):
		return false
	if respawns and not s.alive:
		return false
	if not realm_allowed(s, t, ctx):
		return false
	var interval: = float(f.get("interval", 1.0))
	var dur: = float(f.get("duration", 3.0))
	if interval <= 0.0 or dur < 0.0:
		return false
	var ab = ctx.get("ability")
	if f.get("originRefresh", false):
		for x in t.statuses:
			if x.type == &"dot" and x.source_idx == s.idx and x.ability == ab and x.end > time:
				x.end = time + dur
				x.dmg = f.damageEffect
				return true
	var ns: = ST.Status.new()
	ns.type = &"dot"
	ns.source_idx = s.idx
	ns.start = time
	ns.end = time + dur
	ns.duration = dur
	ns.interval = interval
	ns.next_tick = time + interval
	ns.dmg = f.damageEffect
	ns.ability = ab
	ns.ctx = {"ability": ab, "source_type": "PERSISTENT", "realm": ctx.get("realm", s.chamber)}
	t.statuses.append(ns)
	emit("STATUS_APPLIED", s.idx, t.idx, {"status": "dot", "duration": dur, "ability": ab, "pos": t.pos})
	return true


func _update_statuses(_dt: float) -> void :
	var all_alive: Array[BUnit] = heroes.duplicate()
	all_alive.append_array(entities)
	for bu in all_alive:
		if not bu.alive:
			continue
		if not bu.buffs.is_empty():
			var kb: Array[ST.Buff] = []
			for b in bu.buffs:
				if b.end > time:
					kb.append(b)
			bu.buffs = kb
		if bu.statuses.is_empty():
			if not bu.shields.is_empty():
				_expire_shields(bu)
			# Max-health buffs can expire without an accompanying status effect.
			# The fast path must enforce the same health bound as the status path.
			bu.hp = minf(bu.hp, stat(bu, S_HP))
			if bu.hp <= 0.0:
				kill_unit(bu, null, {})
			continue
		for s in bu.statuses.duplicate():
			var st: ST.Status = s
			if not (st.type in [&"dot", &"pain"]) or st.interval <= 0.0:
				continue
			var deadline: = minf(time, st.end)
			while bu.alive and st.next_tick <= deadline + 1e-09:
				st.next_tick += st.interval
				var src: = u_at(st.source_idx)
				if src:
					if st.type == &"pain":
						apply_damage(src, bu, {"school": "physical", "base": 2.0 * st.stacks, "ad": 0.035 * st.stacks}, {"source_type": "PASSIVE", "proc": true, "pain_tick": true})
					else:
						apply_damage(src, bu, st.dmg, st.ctx)
		if not bu.alive:
			continue
		var keep: Array[ST.Status] = []
		for s in bu.statuses:
			if s.end > time:
				keep.append(s)
			elif s.type == &"control" or s.type == &"taunt":
				reset_commitment(bu, "control_expired")
		bu.statuses = keep
		_expire_shields(bu)
		var mx: = stat(bu, S_HP)
		if bu.hp > mx:
			bu.hp = mx
		if bu.hp <= 0.0 and bu.alive:
			kill_unit(bu, null, {})


func _expire_shields(u: BUnit) -> void :
	if u.shields.is_empty():
		return
	var keep: Array[ST.Shield] = []
	for sh in u.shields:
		if sh.end > time and sh.amount > 0.01:
			keep.append(sh)
	u.shields = keep


func consume_status(t: BUnit, type: StringName, source_idx: int = -1, count: int = 0) -> int:
	var removed: = 0
	var keep: Array[ST.Status] = []
	for x in t.statuses:
		if x.type == type and (source_idx < 0 or x.source_idx == source_idx) and x.end > time:
			removed += 1
			if count > 0 and x.stacks > count:
				x.stacks -= count
				keep.append(x)
			continue
		keep.append(x)
	t.statuses = keep
	return removed


func remove_statuses_where(u: BUnit, pred: Callable) -> void :
	var keep: Array[ST.Status] = []
	for x in u.statuses:
		if not pred.call(x):
			keep.append(x)
	u.statuses = keep


func push_status(u: BUnit, type: StringName, source_idx: int, duration: float, extra: Dictionary = {}) -> ST.Status:
	var ns: = ST.Status.new()
	ns.type = type
	ns.source_idx = source_idx
	ns.start = time
	ns.end = time + duration
	ns.duration = duration
	ns.extra = extra
	u.statuses.append(ns)
	return ns






func apply_effects(s: BUnit, t: BUnit, effects: Array, ctx: Dictionary) -> void :
	if respawns and s != null and not s.alive:
		return
	var scoped: = ctx.duplicate()
	if not scoped.has("source_origin"):
		scoped["source_origin"] = s.pos
	scoped["explicit_confusion"] = false
	for f in effects:
		if str(f.get("type", "")) == "mark" and str(f.get("status", "")) == "confusion":
			scoped["explicit_confusion"] = true
	for f in effects:
		var typ: = str(f.get("type", ""))
		if typ == "damage" and scoped.get("executed", false):
			continue
		if typ == "consume_status" and str(f.get("status", "")) == "infection" and scoped.get("control_failed", false):
			continue
		# V2 per-effect gate, judged after the earlier effects of this list
		# (hades S2: heal block only when the hit left the target under 15%).
		if f.has("whenTargetHpBelow") and (t == null or not t.alive or hp_ratio(t) >= float(f.whenTargetHpBelow)):
			continue
		apply_effect(s, t, f, scoped)


func apply_effect(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary) -> void :
	if s == null:
		return
	if respawns and not s.alive:
		return
	if f.get("selfOnly", false):
		t = s
	var typ: = str(f.get("type", ""))
	match typ:
		"damage":
			if t and t.alive:
				apply_damage(s, t, f, ctx)
		"heal":
			if t and t.alive:
				apply_heal(s, t, f, ctx)
		"shield":
			if t and t.alive:
				apply_shield(s, t, f, ctx)
		"status":
			if t and t.alive:
				var ok: = apply_status(s, t, f, ctx)
				if str(f.get("status", "")) == "control":
					ctx["control_failed"] = not ok
				if ok and f.has("whenTargetHpBelow") and str(f.get("status", "")) == "healReduction" and float(f.get("magnitude", 0.0)) >= 1.0:
					emit("HEAL_BLOCKED", s.idx, t.idx, {"duration": float(f.get("duration", 0.0)), "ability": ctx.get("ability"), "pos": t.pos})
		"mark":
			if t and t.alive:
				apply_mark(s, t, f, ctx)
		"dot":
			if t and t.alive:
				apply_dot(s, t, f, ctx)
		"buff":
			if t and t.alive:
				if f.has("resourceGate") and float(s.resources.get(str(f.resourceGate.key), 0)) < float(f.resourceGate.min):
					return
				var ab = ctx.get("ability")
				var before: = stat(t, StringName(str(f.stat)))
				var tag: = str((ab as Defs.AbilityDef).id) if ab is Defs.AbilityDef else str(f.stat)
				var ex: = f.duplicate()
				ex["tag"] = tag
				add_buff(t, StringName(str(f.stat)), float(f.amount), float(f.duration), s.idx, ex)
				emit("BUFF_APPLIED", s.idx, t.idx, {"stat": str(f.stat), "amount": float(f.amount), "duration": float(f.duration), "ability": ab})
				if eteam(t) == eteam(s) and t != s:
					kits.support_credit(s, t, absf(stat(t, StringName(str(f.stat))) - before), ctx)
		"execute":
			if t and t.alive and hp_ratio(t) <= float(f.get("threshold", 0.0)):
				if has_status(t, &"invulnerable"):
					emit("DAMAGE_IMMUNE", s.idx, t.idx, {"execute": true})
					return
				var rage: = t.def.rule("rage_on_damage") if t.is_hero else {}
				var resist: = 1.0 - minf(0.45, float(t.resources.get("rage", 0)) * float(rage.get("trueResistPerStack", 0.025))) if not rage.is_empty() else 1.0
				var base: = (t.hp + shield_amount(t) + 1.0) / maxf(0.01, resist * incoming_mult(t))
				var c2: = ctx.duplicate()
				c2["execute"] = true
				c2["damage_mult"] = 1.0
				c2["reflected"] = true
				apply_damage(s, t, {"type": "damage", "school": "true", "base": base, "frozen": true}, c2)
				ctx["executed"] = true
		"consume_status":
			if t:
				var n: = consume_status(t, StringName(str(f.status)), s.idx if f.get("originOwned", false) else -1, int(f.get("originCount", 0)))
				if n > 0:
					emit("STATUS_REMOVED", s.idx, t.idx, {"status": str(f.status)})
		"end_control":
			if t:
				var x: = owned_status(t, &"control", s.idx)
				if x:
					t.statuses.erase(x)
					reset_commitment(t, "control_ended")
					emit("CONTROL_ENDED", s.idx, t.idx, {})
		"steal_stat":
			if t and t.alive and not has_status(t, &"invulnerable"):
				var key: = str(f.get("stat", "attackDamage"))
				if key == "main":
					key = "attackDamage" if stat(t, S_AD) >= stat(t, S_AP) else "abilityPower"
				var token: = "theft:%d:%d" % [s.idx, t.idx]
				for b in t.buffs:
					if b.tag == token and b.end > time:
						return
				var amount: = stat(t, StringName(key)) * float(f.get("ratio", 0.15))
				add_buff(t, StringName(key + "Flat"), - amount, float(f.get("duration", 4.0)), s.idx, {"tag": token})
				add_buff(s, &"attackDamageFlat", amount, float(f.get("duration", 4.0)), s.idx, {"tag": token})
				emit("STAT_STOLEN", s.idx, t.idx, {"stat": key, "amount": amount, "pos": t.pos})
		"swap_stats":
			if t and t.alive and not has_status(t, &"invulnerable"):
				add_buff(t, &"originStatSwap", 1.0, float(f.get("duration", 4.0)), s.idx, {"tag": "statSwap"})
				emit("STATS_SWAPPED", s.idx, t.idx, {"pos": t.pos})
		"swap":
			if t and t.alive:
				if eteam(s) != eteam(t) and (warfare.contemplating(t) or has_any(t, [&"unstoppable", &"invulnerable"])):
					emit("CC_IMMUNE", s.idx, t.idx, {"status": "swap"})
					return
				var a: = s.pos
				var b2: = t.pos
				s.pos = clamp_pos(b2, radius(s))
				t.pos = clamp_pos(a, radius(t))
				warfare.constrain(s, a)
				warfare.constrain(t, b2)
				s.prev_pos = s.pos
				t.prev_pos = t.pos
				s.vel = Vector2.ZERO
				t.vel = Vector2.ZERO
				emit("POSITIONS_SWAPPED", s.idx, t.idx, {"from": a, "to": s.pos})
		"displace":
			kits.displace(s, t, f, ctx)
		"move_self":
			kits.move_self(s, t, f, ctx)
		"zone":
			zones.spawn_from_effect(s, t, f, ctx)
		"delayed_area":
			var at: Vector2 = ctx.get("hit_pos", ctx.get("target_pos", s.pos))
			schedule(float(f.get("delay", 0.5)), {"kind": "area", "source": s.idx, "pos": at, "radius": float(f.get("radius", 60.0)), "effects": f.get("effects", []), "ctx": ctx})
			add_telegraph(s, "circle", s.pos, at, float(f.get("radius", 60.0)), 0.0, 0.0, 0.0, float(f.get("delay", 0.5)), ctx.get("ability"), 0)
		"summon":
			kits.spawn_summons(s, f, ctx)
		"resource":
			s.resources[str(f.key)] = maxf(0.0, float(s.resources.get(str(f.key), 0)) + float(f.amount))
		"projectile_guard":
			add_buff(s, &"projectileGuard", float(f.get("reduction", 1.0)), float(f.get("duration", 3.0)), s.idx, {"tag": "guard", "reduction": float(f.get("reduction", 1.0)), "reflect": float(f.get("reflect", 0.0))})
			emit("DEFENSE_STATE", s.idx, s.idx, {"state": "projectileGuard", "duration": float(f.get("duration", 3.0))})
		"cleanse":
			if t and t.alive:
				cleanse(s, t, ctx)
		"front_guard":
			_front_guard(s, f, ctx)
		"roar":
			_roar(s, f, ctx)
		_:
			pass


# V2 cleanse (torquemada): removes crowd control, harmful statuses, enemy damage
# over time and enemy stat debuffs. Statuses tied to a chamber or a motion,
# imprisonment, seals, marks and own/allied effects stay.
const CLEANSE_HARMFUL: = [&"healReduction", &"damageAmp", &"sniperVulnerable", &"confusion", &"plague", &"pain", &"roar"]


func cleanse(s: BUnit, t: BUnit, ctx: Dictionary) -> int:
	if t == null or not t.alive:
		return 0
	var team: = eteam(t)
	var removed: Array = []
	var had_cc: = false
	var keep: Array[ST.Status] = []
	for x in t.statuses:
		var drop: = false
		if x.end > time and not x.extra.has("chamber") and not x.extra.has("motion_id"):
			if CC_TYPES.has(x.type):
				drop = true
				had_cc = had_cc or x.type != &"slow"
			elif CLEANSE_HARMFUL.has(x.type):
				drop = true
			elif x.type == &"dot":
				var src: = u_at(x.source_idx)
				drop = src != null and eteam(src) != team
		if drop:
			removed.append(String(x.type))
		else:
			keep.append(x)
	t.statuses = keep
	var kb: Array[ST.Buff] = []
	for b in t.buffs:
		var src2: = u_at(b.source_idx)
		var hostile: = src2 != null and eteam(src2) != team and b.end > time
		if hostile and (b.amount < 0.0 or b.stat == &"originStatSwap"):
			removed.append(String(b.stat))
		else:
			kb.append(b)
	t.buffs = kb
	if removed.is_empty():
		return 0
	if had_cc:
		# Like contemplation, a freed unit re-decides at once; its own cast in
		# progress survives unless a control or taunt had dictated it.
		if t.action == null or removed.has("control") or removed.has("taunt"):
			reset_commitment(t, "cleanse")
		else:
			t.command = {}
			t.next_decision_at = time
	emit("CLEANSED", s.idx if s else -1, t.idx, {"removed": removed, "ability": ctx.get("ability"), "pos": t.pos})
	return removed.size()


# V2 achilles S2: guard the aimed direction (ctx target point) for a while.
func _front_guard(s: BUnit, f: Dictionary, ctx: Dictionary) -> void:
	var aim: Vector2 = ctx.get("target_pos", s.pos)
	var dir: = (aim - s.pos).normalized() if aim.distance_squared_to(s.pos) > 1.0 else s.facing
	var dur: = float(f.get("duration", 2.0))
	remove_statuses_where(s, func(x): return x.type == &"frontGuard")
	push_status(s, &"frontGuard", s.idx, dur, {"dir": dir, "arc": deg_to_rad(float(f.get("arcDegrees", 120.0)))})
	s.facing = dir
	if float(f.get("moveSlow", 0.0)) > 0.0:
		add_buff(s, S_MS, - float(f.moveSlow), dur, s.idx, {"tag": "frontGuard"})
	emit("STATUS_APPLIED", s.idx, s.idx, {"status": "frontGuard", "duration": dur, "ability": ctx.get("ability"), "pos": s.pos})
	emit("DEFENSE_STATE", s.idx, s.idx, {"state": "frontGuard", "duration": dur, "dir": dir})


# V2 achilles S3: a harmful tenacity loss on every enemy hero in index order;
# global in team modes, within a radius in free-for-all modes.
func _roar(s: BUnit, f: Dictionary, ctx: Dictionary) -> void:
	var reach: = float(f.get("radiusFfa", 900.0)) if deathmatch else INF
	var st: = {"status": "roar", "duration": float(f.get("duration", 6.0)), "tenacityLoss": float(f.get("tenacityLoss", 0.1))}
	for e in heroes:
		if not e.alive or eteam(e) == eteam(s) or s.pos.distance_to(e.pos) > reach:
			continue
		apply_status(s, e, st, ctx)



func resolve_area(s: BUnit, center: Vector2, r: float, effects: Array, ctx: Dictionary) -> void :
	var team: int = ctx.get("team", eteam(s))
	var explicit: = false
	for f in effects:
		if str(f.get("type", "")) == "mark" and str(f.get("status", "")) == "confusion":
			explicit = true
	for f in effects:
		var typ: = str(f.get("type", ""))
		if typ in ["zone", "delayed_area", "move_self", "summon", "resource", "consume_resource", "self_damage", "portal_pair", "projectile_guard", "parity_bed", "front_guard", "roar"] or f.get("selfOnly", false):
			var c0: = ctx.duplicate()
			c0["hit_pos"] = center
			apply_effect(s, s, f, c0)
			continue
		var friendly: = typ in ["heal", "shield", "buff", "heal_bank", "cleanse"] and not (str(f.get("status", "")) in ["damageAmp", "healReduction"])
		var targets: Array[BUnit] = []
		if friendly:
			for a in allies_of(team):
				if a.pos.distance_to(center) <= r + radius(a) and los(center, a.pos, 1.0):
					targets.append(a)
		else:
			for b in bodies_alive():
				if eteam(b) != team and b.pos.distance_to(center) <= r + radius(b) and los(center, b.pos, 1.0):
					targets.append(b)
		for t in targets:
			var eff: Dictionary = f
			if ctx.get("projectile_area", false) and typ == "damage":
				var g: = get_buff(t, &"projectileGuard")
				if g:
					eff = scale_damage([f], 1.0 - clampf(float(g.extra.get("reduction", g.amount)), 0.0, 1.0))[0]
			var c1: = ctx.duplicate()
			c1["hit_pos"] = center
			c1["explicit_confusion"] = explicit
			c1["attack_from"] = center
			c1["area"] = true
			apply_effect(s, t, eff, c1)


func query_cone(origin: Vector2, dir: Vector2, rng_: float, ang: float, candidates: Array[BUnit]) -> Array[BUnit]:
	var out: Array[BUnit] = []
	var d: = dir.normalized() if dir.length_squared() > 1e-09 else Vector2.RIGHT
	for bu in candidates:
		var v: = bu.pos - origin
		var dist: = v.length()
		var r: = radius(bu)
		if dist > rng_ + r or dist <= 0.001:
			continue
		var a: = acos(clampf(v.normalized().dot(d), -1.0, 1.0))
		if a > ang * 0.5 + r / maxf(1.0, dist):
			continue
		if not los(origin, bu.pos, minf(6.0, r * 0.15)):
			continue
		out.append(bu)
	return out






func schedule(delay: float, job: Dictionary) -> void :
	job["at"] = time + maxf(0.0, delay)
	job["seq"] = next_id()
	delayed.append(job)


func add_telegraph(s: BUnit, shape: String, from: Vector2, to: Vector2, r: float, width: float, rng_: float, ang: float, duration: float, ab, action_id: int) -> Dictionary:
	var tg: = {"id": next_id(), "source": s.idx, "team": eteam(s), "shape": shape, "from": from, "to": to, 
		"radius": r, "width": width, "range": rng_, "angle": ang, "start": time, "end": time + duration, 
		"ability": ab, "action_id": action_id, "cancelled": false}
	telegraphs.append(tg)
	return tg


func cleanup_telegraphs() -> void :
	var keep: Array = []
	for tg in telegraphs:
		if tg.end > time and not tg.cancelled:
			keep.append(tg)
	telegraphs = keep






func reset_commitment(u: BUnit, reason: String) -> void :
	if u.action:
		cancel_action(u, reason)
	u.command = {}
	u.next_decision_at = time


func cancel_action(u: BUnit, reason: String) -> void :
	if u.action == null:
		return
	for tg in telegraphs:
		if tg.action_id == u.action.id:
			tg.cancelled = true
	emit("CAST_CANCELLED" if u.action.kind == "ability" else "ATTACK_CANCELLED", u.idx, u.action.target_idx, {"reason": reason, "ability": u.action.ability})
	if u.action.extra.has("charge"):
		remove_buffs_tag(u, "charge:%d" % u.action.id)
	u.action = null


func ability_list(u: BUnit) -> Array:

	var out: Array = u.def.abilities.duplicate()
	out.append_array(kits.virtual_abilities(u))
	return out


func ability_ready(u: BUnit, i: int, a: Defs.AbilityDef) -> bool:
	if a.virtual:
		return kits.virtual_ready(u, a)
	if u.sealed.has(i):
		return false
	if u.def.id == "hermes" and i == 0 and float(u.ks.get("cloak_until", -1.0)) > time:
		return can_cast(u) and time >= float(u.ks.get("cloak_ready_at", 0.0)) and u.action == null
	if not u.alive or u.cooldowns[i] > time or not can_cast(u):
		return false
	var c: = a.condition
	if c.has("selfResource") and not resource_waived(u, c.selfResource):
		if float(u.resources.get(str(c.selfResource.key), 0)) < float(c.selfResource.min):
			return false
	if c.get("nearWall", false) and distance_to_wall(u.pos) > radius(u) + 4.0:
		return false
	# V2 hades S1: only startable while concealed (not re-checked at resolve).
	if c.get("concealed", false) and not kits.concealed(u):
		return false
	return kits.extra_ready(u, a)


# V2: a resource condition marked originFreeInOverdrive is waived while the
# unit is in overdrive (war_machine booster after the fuel tank breaks).
func resource_waived(u: BUnit, sr: Dictionary) -> bool:
	return bool(sr.get("originFreeInOverdrive", false)) and has_status(u, &"overdrive")


func check_condition(s: BUnit, t: BUnit, c: Dictionary) -> bool:
	if c.is_empty():
		return true
	if c.has("targetStatus"):
		if t == null:
			return false
		var st: = StringName(str(c.targetStatus))
		if c.get("owned", false):
			if owned_status(t, st, s.idx) == null:
				return false
		elif not has_status(t, st):
			return false
	if c.get("targetIsCC", false) and (t == null or not is_crowd_controlled(t)):
		return false
	if c.has("selfResource") and not resource_waived(s, c.selfResource) and float(s.resources.get(str(c.selfResource.key), 0)) < float(c.selfResource.min):
		return false
	if c.get("nearWall", false) and distance_to_wall(s.pos) > radius(s) + 4.0:
		return false
	# V2 torquemada S2: the target crowd-controlled me within the window
	# (self-knowledge recorded by Kits.on_cc_applied / displace).
	if c.has("ccSourceWithin"):
		if t == null:
			return false
		var by: Dictionary = s.ks.get("cc_by", {})
		if not by.has(t.idx) or time - float(by[t.idx]) > float(c.ccSourceWithin) + 1e-09:
			return false
	if c.has("minPain"):
		if t == null or not t.is_hero:
			return false
		var p: = owned_status(t, &"pain", s.idx)
		if p == null or p.stacks < int(c.minPain):
			return false
	return true


func target_legal(s: BUnit, a: Defs.AbilityDef, t: BUnit) -> bool:
	if a.target == "enemy":
		if t == null or not t.alive or has_status(t, &"untargetable"):
			return false
		if eteam(t) == eteam(s):

			if not (a.condition.get("targetStatus", "") == "control" and owned_status(t, &"control", s.idx) != null):
				return false
		if t.kind == "bed" and not _has_damage(a.effects):
			return false
		if a.action == "chamber" and not t.is_hero:
			return false
		return true
	if a.target == "ally":
		if t == null or not t.alive or eteam(t) != eteam(s):
			return false
		if a.flag("originOtherAlly", false) and (t == s or not t.is_hero):
			return false
		return true
	return true


func _has_damage(effects: Array) -> bool:
	for f in effects:
		var ty: = str(f.get("type", ""))
		if ty == "damage" or ty == "dot":
			return true
	return false


func can_pay(u: BUnit, a: Defs.AbilityDef) -> bool:
	if kits.cost_waived(u, a):
		return true
	for f in a.effects:
		if str(f.get("type", "")) == "consume_resource" and not f.get("optional", false):
			if float(u.resources.get(str(f.key), 0)) < float(f.amount):
				return false
	return true



func _try_execute_command(u: BUnit) -> void :
	if not u.alive or u.action or u.motion:
		return
	var forced: BUnit = forced_target(u)
	if forced:
		u.command = {"kind": "basic", "target": forced.idx, "pos": forced.pos}
	elif u.command.is_empty():
		return
	var c: = u.command
	var kind: = str(c.get("kind", "move"))
	if kind == "move":
		return
	var t: = u_at(int(c.get("target", -1)))
	if t and eteam(t) != eteam(u) and not observes(u, t):
		u.command = {}
		u.next_decision_at = time
		return
	if kind == "ability":
		var abilities: = ability_list(u)
		var i: = int(c.get("index", -1))
		if i < 0 or i >= abilities.size():
			u.command = {}
			return
		var a: Defs.AbilityDef = abilities[i]
		if c.has("ability_id") and str(c.ability_id) != a.id:
			u.command = {}
			return
		if not ability_ready(u, i, a) or not check_condition(u, t, a.condition):
			return
		var aim: Vector2 = c.get("pos", t.pos if t else u.pos)
		var ctl = controllers[eteam(u)]
		if ctl and ctl.has_method("refine_aim"):
			aim = ctl.refine_aim(u, a, t, aim)
		if a.target != "self" and u.pos.distance_to(aim) > a.range + radius(u) + 8.0:
			return
		if start_ability(u, i, t, aim, c):
			u.command["started"] = true
	elif kind == "basic":
		if t == null or not t.alive or not can_basic(u):
			return
		if u.pos.distance_to(t.pos) <= stat(u, S_RANGE) + radius(u) + radius(t):
			start_basic(u, t)


func start_ability(u: BUnit, i: int, t: BUnit, aim: Vector2, cmd: Dictionary = {}) -> bool:
	if state != RUNNING or u.action or u.motion or not u.alive:
		return false
	var abilities: = ability_list(u)
	if i < 0 or i >= abilities.size():
		return false
	var a: Defs.AbilityDef = abilities[i]

	if not a.virtual and u.def.id == "hermes" and i == 0 and float(u.ks.get("cloak_until", -1.0)) > time:
		if not ability_ready(u, 0, a):
			return false
		if respawns: break_protection(u)
		kits.hermes_recast(u, a)
		return true
	if not ability_ready(u, i, a) or not check_condition(u, t, a.condition) or not target_legal(u, a, t) or not can_pay(u, a):
		return false
	if not (aim.is_finite()):
		return false
	var extra: Dictionary = cmd.get("extra", {})
	if not kits.validate_aim(u, a, t, aim, extra):
		return false
	if a.target != "self" and u.pos.distance_to(aim) > a.range + radius(u) + 8.0:
		return false
	if not kits.placement_legal(u, a, aim):
		return false
	if a.virtual:
		kits.start_virtual(u, i, a, t, aim)
	else:
		u.cooldowns[i] = time + kits.cooldown_for(u, a)
	u.st_casts += 1
	var act: = ST.Action.new()
	act.id = next_id()
	act.kind = "ability"
	act.ability = a
	act.ability_index = i
	act.target_idx = t.idx if t else -1
	act.target_pos = aim
	act.extra = extra.duplicate(true)
	if a.action == "rift":
		act.extra["cast_origin"] = u.pos
	# V2 charged casts (war_machine S2): the cast time follows extra.charge and
	# the caster is slowed while charging (removed again on cancel).
	var cast_time: = kits.cast_time_for(u, a, act.extra)
	act.started_at = time
	act.resolve_at = time + cast_time
	act.recover_at = time + cast_time + a.recovery
	act.windup = true
	act.source_team = eteam(u)
	act.resources = u.resources.duplicate()
	u.action = act
	var charge: Dictionary = a.flag("originCharge", {})
	if not charge.is_empty():
		act.extra["charge"] = kits.charge_count(u, a, act.extra)
		if float(charge.get("slow", 0.0)) > 0.0:
			add_buff(u, S_MS, - float(charge.slow), cast_time, u.idx, {"tag": "charge:%d" % act.id})
	if cast_time > 0.05:
		var shape: = "target"
		if a.delivery == "cone":
			shape = "cone"
		elif a.delivery == "area":
			shape = "circle"
		elif a.delivery == "projectile" or a.delivery == "line":
			shape = "line"
		if a.target == "self" and a.delivery == "self":
			shape = "self"
		shape = str(a.flag("originTelegraph", shape))
		var r: = a.radius * (radius_scale(u) if a.action == "" and u.def.id == "giant" else 1.0)
		add_telegraph(u, shape, u.pos, aim if a.target != "self" else u.pos, r, a.width, a.range, a.angle, cast_time, a, act.id)
	var hostile: = not (a.target in ["self", "ally", "position_ally"]) and a.action != "cloak" and not a.virtual
	if hostile:
		kits.break_stealth(u)
	if respawns and domination.hostile_ability(a):
		break_protection(u)
	var started: = {"ability": a, "slot": a.slot, "pos": aim, "from": u.pos, "virtual": a.virtual, "cast_time": cast_time}
	if act.extra.has("charge"):
		started["charge"] = int(act.extra.charge)
	emit("CAST_STARTED", u.idx, act.target_idx, started)
	return true


func start_basic(u: BUnit, t: BUnit) -> bool:
	var forced: BUnit = forced_target(u)
	if forced and t != forced:
		return false
	if u.action or u.motion or not u.alive or t == null or not t.alive or not can_basic(u):
		return false
	if eteam(u) == eteam(t) or not observes(u, t) or has_status(t, &"untargetable"):
		return false
	if u.pos.distance_to(t.pos) > stat(u, S_RANGE) + radius(u) + radius(t):
		return false
	var aspd: = maxf(0.2, stat(u, S_AS))
	var windup: = clampf(0.24 / sqrt(aspd), 0.1, 0.28)
	u.attack_ready_at = time + 1.0 / aspd
	var act: = ST.Action.new()
	act.id = next_id()
	act.kind = "basic"
	act.target_idx = t.idx
	act.target_pos = t.pos
	act.started_at = time
	act.resolve_at = time + windup
	act.recover_at = time + windup + 0.08
	act.source_team = eteam(u)
	u.action = act
	kits.break_stealth(u)
	if respawns: break_protection(u)
	emit("ATTACK_DECLARED", u.idx, t.idx, {"pos": t.pos, "from": u.pos, "windup": windup})
	return true


func _update_action(u: BUnit) -> void :
	var act: = u.action
	if act == null:
		return
	if not u.alive:
		u.action = null
		return
	var forced: BUnit = forced_target(u)
	if forced and (act.kind != "basic" or act.target_idx != forced.idx):
		cancel_action(u, "taunt")
		return
	if not has_status(u, &"unstoppable"):
		if has_any(u, ACTION_BREAK):
			cancel_action(u, "hard_cc")
			return
		if act.kind == "ability" and has_status(u, &"silence") and act.windup:
			cancel_action(u, "silence")
			return
	if act.windup and time >= act.resolve_at:
		act.windup = false
		if act.kind == "ability":
			kits.execute_ability(u, act)
		else:
			kits.execute_basic(u, act)
	if u.action and time >= act.recover_at:
		u.action = null






func _update_movement(u: BUnit, dt: float) -> void :
	if not u.alive:
		return
	if u.chamber != "":
		u.vel = Vector2.ZERO
		return
	var before: = u.pos
	if u.motion:
		kits.update_motion(u, dt)
	elif float(u.ks.get("wall_run_until", -1.0)) > time and not has_any(u, [&"root", &"stun", &"sleep", &"airborne", &"suppression", &"grounded"]):
		kits.update_wall_run(u, dt)
	else:
		_locomotion(u, dt)
	kits.constrain_chambers(u, before)
	warfare.constrain(u, before)


func _desired_steer(u: BUnit) -> Vector2:
	var forced: BUnit = forced_target(u)
	if forced:
		var reach: float = stat(u, S_RANGE) + radius(u) + radius(forced) - 4.0
		return (forced.pos - u.pos).normalized() if u.pos.distance_to(forced.pos) > reach else Vector2.ZERO

	for s in u.statuses:
		if s.type == &"charm" and s.end > time:
			if s.extra.has("bait_pos"):
				var bp: Vector2 = s.extra.bait_pos
				return (bp - u.pos).normalized() if u.pos.distance_squared_to(bp) > 4.0 else Vector2.ZERO
			if s.extra.get("originStationary", false):
				return Vector2.ZERO
	var apple: Dictionary = u.ks.get("apple", {})
	if not apple.is_empty() and float(apple.until) > time:
		var tgt: = u_at(int(apple.target))
		if tgt and tgt.alive and observes(u, tgt):
			apple["pos"] = tgt.pos
		var ap: Vector2 = apple.pos
		return (ap - u.pos).normalized()
	var ctl = controllers[eteam(u)]
	if ctl:
		return ctl.steer(u)
	return Vector2.ZERO


func _locomotion(u: BUnit, dt: float) -> void :
	var hard: = has_any(u, HARD_BLOCK)
	var soft: = false
	var desired: = Vector2.ZERO
	if not hard:
		desired = _desired_steer(u)
	if desired.length() > 1.0:
		desired = desired.normalized()
	var max_speed: = stat(u, S_MS)
	var cur_speed: = u.vel.length()
	var in_mag: = clampf(desired.length(), 0.0, 1.0)
	var in_dir: = desired.normalized() if in_mag > 1e-06 else (u.facing if u.facing.length_squared() > 0.1 else Vector2.RIGHT)
	var accel: = max_speed / maxf(0.08, u.accel_time)
	var brake: = max_speed / maxf(0.06, 0.075 if hard else u.brake_time)
	var reverse: = max_speed / maxf(0.1, u.reverse_time)
	var desired_speed: = 0.0 if (hard or soft) else max_speed * in_mag
	var arrive: float = u.command.get("arrive", -1.0)
	if arrive > 0.0 and desired_speed > 0.0:
		desired_speed = minf(desired_speed, sqrt(2.0 * brake * arrive) + minf(max_speed * 0.14, arrive * 1.1))
	var cur_dir: = u.vel / cur_speed if cur_speed > 1.2 else in_dir
	var ang: = cur_dir.angle_to(in_dir)
	var max_turn: = u.turn_rate * dt
	var face_dir: = in_dir if absf(ang) <= max_turn else cur_dir.rotated(signf(ang) * max_turn)
	var align: = cur_dir.dot(in_dir) if in_mag > 1e-06 else 1.0
	var reversing: = in_mag > 0.05 and cur_speed > max_speed * 0.08 and align < -0.15
	if reversing:
		desired_speed *= clampf((align + 1.0) * 0.36, 0.08, 0.38)
	var target_vel: = face_dir * desired_speed
	var dv: = target_vel - u.vel
	var fwd: = cur_dir if cur_speed > 2.0 else face_dir
	var lat: = Vector2( - fwd.y, fwd.x)
	var lon_err: = dv.dot(fwd)
	var lat_err: = dv.dot(lat)
	var lon_lim: = reverse if reversing else (accel if lon_err >= 0.0 else brake)
	var lat_lim: = accel * u.lateral_grip
	u.vel += fwd * clampf(lon_err, - lon_lim * dt, lon_lim * dt) + lat * clampf(lat_err, - lat_lim * dt, lat_lim * dt)
	if hard and u.vel.length() < max_speed * 0.08:
		u.vel = Vector2.ZERO
	var from_pos: = u.pos
	var end: = from_pos + u.vel * dt
	var r: = radius(u)
	var hit: = arena.segment_hit(from_pos, end, r + 0.3, Arena.MASK_UNITS)
	if wall_unpin and not hit.is_empty() and float(hit.t) <= 0.0:
		# Already resting against a wall (put there by a collision push or a
		# knockback): the padded sweep reports a hit at t=0 with no usable
		# normal and would freeze the unit. Sweep with the body radius so it
		# can slide along the wall or step away from it.
		hit = arena.segment_hit(from_pos, end, r - 0.5, Arena.MASK_UNITS)
	if not hit.is_empty():
		var n: Vector2 = hit.normal
		var tang: = Vector2( - n.y, n.x)
		var ts: = u.vel.dot(tang)
		var ns: = u.vel.dot(n)
		u.vel = tang * ts * 0.72 + n * maxf(0.0, ns) * 0.02
		end = (hit.point as Vector2) + n * 0.45 + u.vel * dt * maxf(0.0, 1.0 - float(hit.t))
	u.pos = arena.resolve_circle(end, r)
	# V2 front guard locks the facing on the guarded direction (backpedalling).
	var guard: ST.Status = get_status(u, &"frontGuard") if not u.statuses.is_empty() else null
	if guard:
		u.facing = guard.extra.get("dir", u.facing)
	elif u.vel.length() > 8.0:
		var want: = u.vel.normalized()
		var fa: = u.facing.angle_to(want)
		var ft: = u.turn_rate * 1.22 * dt
		u.facing = want if absf(fa) <= ft else u.facing.rotated(signf(fa) * ft)


func _resolve_collisions() -> void :
	if not collide_exhaustive:
		_resolve_collisions_fast()
		for body in bodies_alive():
			warfare.constrain(body, body.prev_pos)
		return
	var n: = heroes.size()
	for _it in 2:
		for i in n:
			var a: BUnit = heroes[i]
			if not a.alive or a.motion:
				continue
			for j in range(i + 1, n):
				var b: BUnit = heroes[j]
				if not b.alive or b.motion or a.chamber != b.chamber:
					continue
				var delta: = b.pos - a.pos
				var d: = delta.length()
				var ra: = radius(a)
				var rb: = radius(b)
				var mind: = ra + rb
				if d <= 0.001 or d >= mind:
					continue
				var nrm: = delta / d
				var overlap: = mind - d
				var ma: = ra * ra
				var mb: = rb * rb
				var tot: = ma + mb
				a.pos = arena.resolve_circle(a.pos - nrm * overlap * mb / tot, ra)
				b.pos = arena.resolve_circle(b.pos + nrm * overlap * ma / tot, rb)
	for body in bodies_alive():
		warfare.constrain(body, body.prev_pos)






func kill_unit(t: BUnit, s: BUnit, ctx: Dictionary) -> void :
	if not t.alive:
		return
	if deathmatch and t.is_hero and deathmatch.try_revive(t, s):
		return
	# V2 battleground squads: lethal damage downs the hero first (see BattlegroundMode).
	if battleground != null and t.is_hero and battleground.try_down(t, s, ctx):
		return
	if t.is_hero:
		reset_commitment(t, "death")
	t.shields.clear()
	t.alive = false
	t.hp = 0.0
	t.death_time = time
	t.action = null
	t.motion = null
	t.command = {}
	if t.is_hero:
		t.st_deaths += 1
		if s and s != t:
			s.st_kills += 1
		emit("EXECUTED" if ctx.get("execute", false) else "DEATH", s.idx if s else -1, t.idx, {"ability": ctx.get("ability"), "pos": t.pos})
	else:
		emit("SUMMON_DESTROYED", s.idx if s else -1, t.idx, {"kind": t.kind, "pos": t.pos})
	kits.on_kill(t, s, ctx)
	warfare.on_death(t)
	if is_control_mode() and t.is_hero:
		domination.on_death(t)
	elif deathmatch:
		deathmatch.on_death(t, s, ctx)






func result() -> Dictionary:
	var rows: Array = []
	for u in heroes:
		rows.append({"idx": u.idx, "id": u.def.id, "name": u.name, "team": u.team, "alive": u.alive, "hp": u.hp, 
			"max_hp": stat(u, S_HP), "damage": u.st_damage, "taken": u.st_taken, "healing": u.st_healing, 
			"shielding": u.st_shielding, "cc": u.st_cc, "kills": u.st_kills, "deaths": u.st_deaths, "casts": u.st_casts,
			"capture_time": u.st_capture_time, "captures": u.st_captures, "zone_healing": u.st_zone_healing})
	var out: Dictionary = {"winner": winner, "reason": finish_reason, "duration": time, "seed": seed_value, "arena": arena.id, "ruleset": ruleset, "units": rows, "history": history}
	if is_control_mode():
		out["scores"] = domination.scores.duplicate()
		out["target_score"] = domination.target_score
		out["control_history"] = domination.history.duplicate(true)
		out["control_points"] = domination.public_points()
	if deathmatch:
		out["deathmatch"] = deathmatch.result()
	if battleground != null:
		out["battleground"] = battleground.br_result()
	return out


# --- V2 scale (B-PERF) -------------------------------------------------------
# DESIGN_V2 §3.7. Battleground-scale battles have more than SCALE_HEROES
# heroes or a map larger than SCALE_AREA. Only those use the AI detail levels
# (decision budget below, staggered plans, frozen far beliefs), so every
# existing mode (at most 12 heroes; deathmatch maps are about 7x the standard
# area) keeps its exact behaviour. cfg "scale_lod" forces the switch either way.
# The visibility and collision passes in this section give results identical
# to the reference passes in every mode and are always on.
const SCALE_HEROES: = 12
const SCALE_AREA: = 12.0 * Arena.WIDTH * Arena.HEIGHT
const LOD_NON_URGENT_PER_TICK: = 4
const LOD_URGENT: = 0
const LOD_CONTACT: = 1
const LOD_CALM: = 2
const LOD_CONTACT_RANGE: = 1200.0
const LOD_PLANS_PER_TICK: = 3
const COLLIDE_GRID_MIN: = 16
const COLLIDE_MARGIN: = 8.0
const VIS_SWEEP_OFFSET: = 1000000.0
# Reference passes (tests compare the fast passes with them tick by tick).
static var vis_exhaustive: bool = false
static var collide_exhaustive: bool = false
var scale_lod: bool = false
# Class of each unit's last decision (LOD_*), written by the brains.
var lod_class: PackedByteArray = PackedByteArray()
var _lod_tick: int = -1
var _lod_left: int = 0
var _lod_state: PackedByteArray = PackedByteArray()
var vis_observe_calls: int = 0
var lod_deferred: int = 0
var lod_decisions: PackedInt32Array = PackedInt32Array([0, 0, 0])
# Most non-urgent decisions admitted in any one tick (tests read it).
var lod_max_nonurgent: int = 0
# Body-size buckets whose path grids start() built (free-for-all and scale battles).
var nav_prebuilt: Array = []
var perf_counters: Dictionary:
	get:
		return {"vis_observes": vis_observe_calls, "lod_deferred": lod_deferred,
			"lod_urgent": lod_decisions[0], "lod_contact": lod_decisions[1], "lod_calm": lod_decisions[2],
			"lod_max_nonurgent_per_tick": lod_max_nonurgent}


func _scale_setup() -> void:
	if cfg.has("scale_lod"):
		scale_lod = bool(cfg.scale_lod)
	else:
		scale_lod = heroes.size() > SCALE_HEROES or arena.width * arena.height > SCALE_AREA
	lod_class.resize(units.size())
	lod_class.fill(LOD_CONTACT)


# The battleground mode detaches an eliminated team's controller so it stops
# planning, observing and costing CPU; its slot stays empty afterwards.
func detach_controller(team: int) -> void:
	if team < 0 or team >= controllers.size():
		return
	var c = controllers[team]
	controllers[team] = null
	if c != null and c.has_method("dispose"):
		c.dispose()


func attach_controller(team: int, c) -> void:
	if team < 0 or team >= controllers.size():
		return
	if controllers[team] != null and controllers[team] != c:
		detach_controller(team)
	controllers[team] = c
	if c != null and state != IDLE and c.has_method("on_start"):
		c.on_start(self)


# Distance-first visibility: one pass over body pairs of different effective
# teams. A pair farther apart than sensor range + both radii (+1 px against
# float32 rounding) cannot pass observes(), which runs for every other pair
# (B-PERF2: through _observes_plain when the target is neither untargetable
# nor invisible), so `seen` equals the exhaustive pass exactly.
func _visibility_flat() -> PackedByteArray:
	var n: int = units.size()
	var flat: PackedByteArray = PackedByteArray()
	flat.resize(team_count * n)
	flat.fill(0)
	var bodies: Array[BUnit] = bodies_alive()
	var m: int = bodies.size()
	var et: PackedInt32Array = PackedInt32Array()
	var lim: PackedFloat64Array = PackedFloat64Array()
	var rad: PackedFloat64Array = PackedFloat64Array()
	var px: PackedFloat64Array = PackedFloat64Array()
	var py: PackedFloat64Array = PackedFloat64Array()
	et.resize(m)
	lim.resize(m)
	rad.resize(m)
	px.resize(m)
	py.resize(m)
	# B-PERF2: per-body inputs of observes() read once per pass.
	var sr: PackedFloat64Array = PackedFloat64Array()
	var plain: PackedByteArray = PackedByteArray()
	var fa: PackedInt32Array = PackedInt32Array()
	sr.resize(m)
	plain.resize(m)
	fa.resize(m)
	var forest: bool = brush_on and not arena.forest_x.is_empty()
	# Sweep along x: bodies sorted by floor(x) (key = floor(x + offset) * 1024
	# + body index), so a pair farther apart in x than any sensor reach ends
	# the inner scan. Each unordered pair is tested in both directions once.
	var keys: PackedInt64Array = PackedInt64Array()
	keys.resize(m)
	var max_lim: float = 0.0
	var max_rad: float = 0.0
	for i in m:
		var b: BUnit = bodies[i]
		var t: int = eteam(b)
		et[i] = t
		rad[i] = radius(b)
		sr[i] = sensor_range(b)
		lim[i] = sr[i] + rad[i] + 1.0
		plain[i] = 0 if has_status(b, &"untargetable") or has_status(b, &"invisible") else 1
		fa[i] = arena.forest_at(b.pos) if forest else -1
		px[i] = b.pos.x
		py[i] = b.pos.y
		max_lim = maxf(max_lim, lim[i])
		max_rad = maxf(max_rad, rad[i])
		keys[i] = int(floor(px[i] + VIS_SWEEP_OFFSET)) * 1024 + i
		if t >= 0 and t < team_count:
			flat[t * n + b.idx] = 1
	if m >= 1024:
		for i in m:
			keys[i] = i
	else:
		keys.sort()
	var span: int = int(ceil(max_lim + max_rad)) + 1
	for a in m:
		var i: int = int(keys[a] & 1023) if m < 1024 else a
		var ti: int = et[i]
		var ti_ok: bool = ti >= 0 and ti < team_count
		for c in range(a + 1, m):
			if m < 1024 and (keys[c] >> 10) - (keys[a] >> 10) > span:
				break
			var j: int = int(keys[c] & 1023) if m < 1024 else c
			var tj: int = et[j]
			if ti == tj:
				continue
			var dx: float = px[j] - px[i]
			var dy: float = py[j] - py[i]
			var d2: float = dx * dx + dy * dy
			if ti_ok:
				var la: float = lim[i] + rad[j]
				if d2 <= la * la:
					var k: int = ti * n + bodies[j].idx
					if flat[k] == 0:
						vis_observe_calls += 1
						if (_observes_plain(bodies[i], bodies[j], rad[i], rad[j], sr[i], fa[i], fa[j], forest) if plain[j] == 1 else observes(bodies[i], bodies[j])):
							flat[k] = 1
			if tj >= 0 and tj < team_count:
				var lb: float = lim[j] + rad[i]
				if d2 <= lb * lb:
					var k2: int = tj * n + bodies[i].idx
					if flat[k2] == 0:
						vis_observe_calls += 1
						if (_observes_plain(bodies[j], bodies[i], rad[j], rad[i], sr[j], fa[j], fa[i], forest) if plain[i] == 1 else observes(bodies[j], bodies[i])):
							flat[k2] = 1
	return flat


# observes(s, t) for two living bodies of different effective teams when t is
# neither untargetable nor invisible, with radius(), sensor_range(s) and
# forest_at() of both positions passed in from the same pass (B-PERF2). The
# remaining steps are observes()' own, in its order; keep the two in step
# (tests compare the fast pass with the exhaustive one).
func _observes_plain(s: BUnit, t: BUnit, rs: float, rt: float, sr_s: float, fs: int, ft: int, forest: bool) -> bool:
	if s.chamber != t.chamber:
		return false
	var d: = s.pos.distance_to(t.pos)
	if d > sr_s + rs + rt:
		return false
	if forest:
		if ft >= 0 and fs != ft:
			var reveal: float = deathmatch.forest_reveal_range(s, t) if deathmatch and s.is_hero else 110.0
			if d > reveal + rs + rt and time - t.last_combat_time > 0.8:
				return false
		if arena.forest_occludes(s.pos, t.pos):
			return false
	return arena.line_of_sight(s.pos, t.pos, minf(8.0, rt * 0.18))


# Test hook: entries where the fast pass and the exhaustive pass disagree
# right now (0 = identical). Leaves `seen` as the exhaustive pass sets it.
func debug_visibility_mismatch() -> int:
	var flat: PackedByteArray = _visibility_flat()
	_update_visibility_exhaustive()
	var n: int = units.size()
	var bad: int = 0
	for t in team_count:
		var arr: PackedByteArray = seen[t]
		for i in n:
			if arr[i] != flat[t * n + i]:
				bad += 1
	return bad


# Same pairs, same order and same arithmetic as the reference loop in
# _resolve_collisions; only pairs that cannot overlap are skipped. Radii are
# cached once (nothing here changes health, motion or chambers).
func _resolve_collisions_fast() -> void:
	var n: int = heroes.size()
	var rad: PackedFloat64Array = PackedFloat64Array()
	var live: PackedByteArray = PackedByteArray()
	rad.resize(n)
	live.resize(n)
	live.fill(0)
	var count: int = 0
	var rmax: float = 0.0
	for i in n:
		var h: BUnit = heroes[i]
		if h.alive and not h.motion:
			live[i] = 1
			rad[i] = radius(h)
			rmax = maxf(rmax, rad[i])
			count += 1
	if count < 2:
		return
	for _it in 2:
		if count >= COLLIDE_GRID_MIN:
			_collide_pass_grid(live, rad, rmax)
		else:
			_collide_pass(live, rad, 0, 1)


# Reference order from pair (i0, j0) on: (i0, j0..n-1), then (i, i+1..n-1).
func _collide_pass(live: PackedByteArray, rad: PackedFloat64Array, i0: int, j0: int) -> void:
	var n: int = heroes.size()
	for i in range(i0, n):
		if live[i] == 0:
			continue
		var a: BUnit = heroes[i]
		var ra: float = rad[i]
		for j in range(j0 if i == i0 else i + 1, n):
			if live[j] == 0:
				continue
			_collide_pair(a, heroes[j], ra, rad[j])


# Grid of cells 2 x largest radius + margin, built from the positions at the
# start of the pass; pairs are still visited in reference order (i, then j
# ascending). A skipped pair was more than one cell apart, so it cannot
# overlap while both bodies stay within half the margin of their start. When
# a push moves a body farther, the rest of the pass runs exhaustively.
func _collide_pass_grid(live: PackedByteArray, rad: PackedFloat64Array, rmax: float) -> void:
	var n: int = heroes.size()
	var cell: float = 2.0 * rmax + COLLIDE_MARGIN
	var guard: float = COLLIDE_MARGIN * 0.5 - 0.05
	var x0: PackedFloat64Array = PackedFloat64Array()
	var y0: PackedFloat64Array = PackedFloat64Array()
	var cx: PackedInt32Array = PackedInt32Array()
	var cy: PackedInt32Array = PackedInt32Array()
	x0.resize(n)
	y0.resize(n)
	cx.resize(n)
	cy.resize(n)
	var cells: Dictionary = {}
	for i in n:
		if live[i] == 0:
			continue
		var p: Vector2 = heroes[i].pos
		x0[i] = p.x
		y0[i] = p.y
		cx[i] = floori(p.x / cell)
		cy[i] = floori(p.y / cell)
		var key: Vector2i = Vector2i(cx[i], cy[i])
		var bucket: PackedInt32Array = cells.get(key, PackedInt32Array())
		bucket.append(i)
		cells[key] = bucket
	for i in n:
		if live[i] == 0:
			continue
		var cand: PackedInt32Array = PackedInt32Array()
		for gy in range(cy[i] - 1, cy[i] + 2):
			for gx in range(cx[i] - 1, cx[i] + 2):
				var key2: Vector2i = Vector2i(gx, gy)
				if not cells.has(key2):
					continue
				for j in (cells[key2] as PackedInt32Array):
					if j > i:
						cand.append(j)
		if cand.is_empty():
			continue
		cand.sort()
		var a: BUnit = heroes[i]
		for j in cand:
			var b: BUnit = heroes[j]
			if not _collide_pair(a, b, rad[i], rad[j]):
				continue
			if absf(a.pos.x - x0[i]) > guard or absf(a.pos.y - y0[i]) > guard or absf(b.pos.x - x0[j]) > guard or absf(b.pos.y - y0[j]) > guard:
				_collide_pass(live, rad, i, j + 1)
				return


# One pair of the reference loop; true when it pushed the bodies apart. The
# axis checks only skip pairs the reference `d >= mind` test skips as well.
func _collide_pair(a: BUnit, b: BUnit, ra: float, rb: float) -> bool:
	var mind: = ra + rb
	var lim: float = mind + 0.01
	var dx: float = b.pos.x - a.pos.x
	if dx > lim or dx < -lim:
		return false
	var dy: float = b.pos.y - a.pos.y
	if dy > lim or dy < -lim:
		return false
	if a.chamber != b.chamber:
		return false
	var delta: = b.pos - a.pos
	var d: = delta.length()
	if d <= 0.001 or d >= mind:
		return false
	var nrm: = delta / d
	var overlap: = mind - d
	var ma: = ra * ra
	var mb: = rb * rb
	var tot: = ma + mb
	a.pos = arena.resolve_circle(a.pos - nrm * overlap * mb / tot, ra)
	b.pos = arena.resolve_circle(b.pos + nrm * overlap * ma / tot, rb)
	return true


# Path grids for every body-size bucket the roster can need, built at match
# start instead of on first use mid-match (the giant's full-health radius
# 27.6 needs bucket 28: building that grid stalled the first ticks).
# Free-for-all and scale battles only; team maps are small.
func prebuild_nav() -> void:
	nav_prebuilt = []
	if not is_deathmatch() and not scale_lod:
		return
	for b in nav_buckets():
		Navigator.for_sim(self, float(b))
		nav_prebuilt.append(b)


# Buckets for every hero's radius range, moving summons (radius 9-10) and the
# 20 px probes the tactician routes with.
func nav_buckets() -> Array:
	var out: Array = []
	for h in heroes:
		var rb: Vector2 = radius_bounds(h)
		for b in Navigator.buckets_between(rb.x, rb.y):
			if not out.has(b):
				out.append(b)
	for b2 in [Navigator.bucket_for(10.0), Navigator.bucket_for(20.0)]:
		if not out.has(b2):
			out.append(b2)
	out.sort()
	return out


# Smallest and largest radius() this body can take (keep in sync with radius()).
func radius_bounds(u: BUnit) -> Vector2:
	if u.is_hero and u.def.id == "giant":
		return Vector2(u.base_radius * 0.85, u.base_radius * 1.15)
	return Vector2(u.base_radius, u.base_radius)


# Count-based decision budget for scale battles (never wall-clock): urgent
# heroes always decide; at most LOD_NON_URGENT_PER_TICK others per tick,
# contact before calm, then the longest wait, then unit index. Urgency is the
# decision's own test (danger above 35 % of health + shields), asked of the
# hero's controller (lod_urgent) before it decides. A deferred hero keeps its
# due time and is due again next tick. The brains ask before deciding.
func lod_admit(u: BUnit) -> bool:
	if not scale_lod:
		return true
	if _lod_tick != tick:
		_lod_plan_tick(u)
	var st: int = _lod_state[u.idx] if u.idx < _lod_state.size() else 0
	if st == 1:
		return true
	if st == 2:
		lod_deferred += 1
		return false
	# Became due during this tick (its action just ended).
	if _lod_urgent(u):
		return true
	if _lod_left > 0:
		_lod_take()
		return true
	lod_deferred += 1
	return false


func _lod_take() -> void:
	_lod_left -= 1
	lod_max_nonurgent = maxi(lod_max_nonurgent, LOD_NON_URGENT_PER_TICK - _lod_left)


func _lod_urgent(h: BUnit) -> bool:
	var et: int = eteam(h)
	if et < 0 or et >= controllers.size() or controllers[et] == null:
		return false
	var ctl = controllers[et]
	return ctl.has_method("lod_urgent") and bool(ctl.lod_urgent(h))


func lod_set_class(u: BUnit, c: int) -> void:
	if u.idx >= lod_class.size():
		var old: int = lod_class.size()
		lod_class.resize(u.idx + 1)
		for i in range(old, lod_class.size()):
			lod_class[i] = LOD_CONTACT
	lod_class[u.idx] = c
	lod_decisions[c] += 1


# Ordering class of a non-urgent hero: its last decision's class, raised from
# calm to contact when the team now sees an enemy within LOD_CONTACT_RANGE or
# after waiting 0.3 s past due (an urgent last decision counts as contact).
func lod_effective_class(u: BUnit) -> int:
	var c: int = lod_class[u.idx] if u.idx < lod_class.size() else LOD_CONTACT
	if c == LOD_URGENT:
		return LOD_CONTACT
	if c == LOD_CALM and (time - u.next_decision_at > 0.3 or enemy_seen_near(u, LOD_CONTACT_RANGE)):
		c = LOD_CONTACT
	return c


func _lod_plan_tick(current: BUnit) -> void:
	_lod_tick = tick
	_lod_left = LOD_NON_URGENT_PER_TICK
	_lod_state.resize(units.size())
	_lod_state.fill(0)
	var due: Array = []
	for h in heroes:
		if h != current and not (h.alive and h.action == null and time >= h.next_decision_at and not decision_blocked(h)):
			continue
		var et: int = eteam(h)
		if et < 0 or et >= controllers.size() or controllers[et] == null:
			continue
		if _lod_urgent(h):
			_lod_state[h.idx] = 1
			continue
		due.append([lod_effective_class(h), h.next_decision_at, h.idx])
	due.sort_custom(func(x: Array, y: Array) -> bool:
		if int(x[0]) != int(y[0]):
			return int(x[0]) < int(y[0])
		if float(x[1]) != float(y[1]):
			return float(x[1]) < float(y[1])
		return int(x[2]) < int(y[2]))
	for row in due:
		if _lod_left > 0:
			_lod_state[int(row[2])] = 1
			_lod_take()
		else:
			_lod_state[int(row[2])] = 2


# Per-tick budget for scheduled team plans (count-based; controllers ask in
# team order, and a plan that waited long enough no longer asks).
var _lod_plan_tick_at: int = -1
var _lod_plans_left: int = 0


func lod_plan_take() -> bool:
	if _lod_plan_tick_at != tick:
		_lod_plan_tick_at = tick
		_lod_plans_left = LOD_PLANS_PER_TICK
	if _lod_plans_left <= 0:
		return false
	_lod_plans_left -= 1
	return true


# True when u's own team currently sees an enemy hero within reach (team
# observations only).
func enemy_seen_near(u: BUnit, reach: float) -> bool:
	var t: int = u.team
	if t < 0 or t >= seen.size():
		return false
	var arr: PackedByteArray = seen[t]
	var r2: float = reach * reach
	for o in heroes:
		if o.alive and o.team != t and o.idx < arr.size() and arr[o.idx] == 1 and o.pos.distance_squared_to(u.pos) <= r2:
			return true
	return false


# --- V2 scale (B-PERF2): AI pre-tick snapshot ---
# During the controllers' pre_tick pass the simulation does not change (the
# brains only read it), yet every brain asked allies_of() and eteam() about
# every body several times: 30 brains x (heroes + entities) status scans per
# call in a 30-hero battle. In scale battles a brain's pre_tick is bracketed by
# ai_pre_begin / ai_pre_end; inside it TeamIntel reads each body's effective
# team and each team's ally list from one snapshot taken by the first brain
# of the pass. The snapshot is rebuilt whenever the tick, the event count or
# the controller order says anything could have changed, and is never read
# outside a bracket, so every answer equals the live one (ai_snapshot_check
# compares them in tests). Other battles never open the bracket.
const AI_ET_UNKNOWN: = -9999
static var ai_snapshot_check: bool = false
var ai_snapshot_mismatch: int = 0
var ai_snapshot_reads: int = 0      # counted in check mode only
var ai_snapshot_builds: int = 0
var _ai_snap_valid: bool = false
var _ai_snap_tick: int = -1
var _ai_snap_events: int = -1
var _ai_snap_next: int = 0
var _ai_snap_open: int = 0
var _ai_et: PackedInt32Array = PackedInt32Array()
var _ai_allies_ent: Array = []
var _ai_allies_h: Array = []
var _ai_own_h: Array = []
var _ai_sr: PackedFloat64Array = PackedFloat64Array()


func ai_pre_begin(team: int) -> void:
	if not scale_lod:
		return
	if not _ai_snap_valid or _ai_snap_tick != tick or _ai_snap_events != tick_events.size() or team < _ai_snap_next:
		_ai_snapshot_build()
	_ai_snap_open += 1


func ai_pre_end(team: int) -> void:
	if not scale_lod:
		return
	_ai_snap_open = maxi(0, _ai_snap_open - 1)
	_ai_snap_next = team + 1
	var last: int = controllers.size() - 1
	while last >= 0 and controllers[last] == null:
		last -= 1
	if team >= last:
		_ai_snap_valid = false


func _ai_snapshot_build() -> void:
	ai_snapshot_builds += 1
	_ai_snap_valid = true
	_ai_snap_tick = tick
	_ai_snap_events = tick_events.size()
	_ai_snap_next = 0
	_ai_et.resize(units.size())
	_ai_et.fill(AI_ET_UNKNOWN)
	_ai_sr.resize(units.size())
	_ai_sr.fill(-1.0)
	_ai_allies_ent = []
	_ai_allies_h = []
	_ai_own_h = []
	for t in team_count:
		var a1: Array[BUnit] = []
		var a2: Array[BUnit] = []
		var a3: Array[BUnit] = []
		_ai_allies_ent.append(a1)
		_ai_allies_h.append(a2)
		_ai_own_h.append(a3)
	for o in heroes:
		var et: int = _ai_eteam_snap(o)
		if o.alive and o.team >= 0 and o.team < team_count:
			var own: Array[BUnit] = _ai_own_h[o.team]
			own.append(o)
		if o.alive:
			if et >= 0 and et < team_count:
				var with_e: Array[BUnit] = _ai_allies_ent[et]
				var only_h: Array[BUnit] = _ai_allies_h[et]
				with_e.append(o)
				only_h.append(o)
	for e in entities:
		if e.alive:
			var et2: int = _ai_eteam_snap(e)
			if et2 >= 0 and et2 < team_count:
				var with_e2: Array[BUnit] = _ai_allies_ent[et2]
				with_e2.append(e)


func _ai_eteam_snap(u: BUnit) -> int:
	if u.idx < 0 or u.idx >= _ai_et.size():
		return eteam(u)
	var v: int = _ai_et[u.idx]
	if v == AI_ET_UNKNOWN:
		v = eteam(u)
		_ai_et[u.idx] = v
	return v


func _ai_snap_live() -> bool:
	return _ai_snap_open > 0 and _ai_snap_valid and _ai_snap_tick == tick and _ai_snap_events == tick_events.size()


# allies_of(team, include_entities) for TeamIntel inside a brain's pre_tick.
# The returned array is shared: callers only read it.
func ai_allies(team: int, include_entities: bool = false) -> Array[BUnit]:
	if not _ai_snap_live() or team < 0 or team >= _ai_allies_ent.size():
		return allies_of(team, include_entities)
	var out: Array[BUnit] = _ai_allies_ent[team] if include_entities else _ai_allies_h[team]
	if ai_snapshot_check:
		ai_snapshot_reads += 1
		if out != allies_of(team, include_entities):
			ai_snapshot_mismatch += 1
	return out


# Effective team per unit index while the snapshot is readable (every hero
# and living entity filled; AI_ET_UNKNOWN elsewhere), else empty. Check mode
# returns empty so every read goes through ai_eteam and is compared.
func ai_et_table() -> PackedInt32Array:
	if not _ai_snap_live() or ai_snapshot_check:
		return PackedInt32Array()
	return _ai_et


# Living heroes whose own (not effective) team is `team`, in hero order.
func ai_team_heroes(team: int) -> Array[BUnit]:
	var out: Array[BUnit] = []
	if _ai_snap_live() and team >= 0 and team < _ai_own_h.size() and not ai_snapshot_check:
		return _ai_own_h[team]
	for o in heroes:
		if o.alive and o.team == team:
			out.append(o)
	if ai_snapshot_check and _ai_snap_live() and team >= 0 and team < _ai_own_h.size():
		ai_snapshot_reads += 1
		if out != _ai_own_h[team]:
			ai_snapshot_mismatch += 1
	return out


func ai_eteam(u: BUnit) -> int:
	if not _ai_snap_live():
		return eteam(u)
	var v: int = _ai_eteam_snap(u)
	if ai_snapshot_check:
		ai_snapshot_reads += 1
		if v != eteam(u):
			ai_snapshot_mismatch += 1
	return v


# sensor_range(u) inside a brain's pre_tick: a body's items and statuses do
# not change during the pass, so the first answer of the pass is kept.
func ai_sensor_range(u: BUnit) -> float:
	if not _ai_snap_live() or u.idx < 0 or u.idx >= _ai_sr.size():
		return sensor_range(u)
	var v: float = _ai_sr[u.idx]
	if v < 0.0:
		v = sensor_range(u)
		_ai_sr[u.idx] = v
	elif ai_snapshot_check:
		ai_snapshot_reads += 1
		if v != sensor_range(u):
			ai_snapshot_mismatch += 1
	return v


# is_seen() with the snapshot's effective team.
func ai_is_seen(team: int, u: BUnit) -> bool:
	if u == null:
		return false
	if ai_eteam(u) == team:
		return true
	var arr: PackedByteArray = seen[team]
	return u.idx < arr.size() and arr[u.idx] == 1


# AI event index (B-PERF2): every brain scans the same ai_events list each
# tick. The type of each event is turned into a small code once per list;
# the brains' loops skip events whose type they never read without opening
# the event (same events, same order for the rest). 0 = no AI loop reads it.
const AI_EV_CODES: = {"HERO_RESPAWNED": 1, "RESPAWN_SCHEDULED": 2, "CAST_STARTED": 3, "PROJECTILE_CREATED": 4,
	"PROJECTILE_END": 5, "CC_APPLIED": 6, "REVEAL": 7, "INFO_REVEAL": 8, "DEATH": 9, "EXECUTED": 10,
	"SUMMON_DESTROYED": 11, "SUMMON_EXPIRED": 12, "STRUCTURE_REPLACED": 13, "ENV_HIT": 14, "HEALTH_DAMAGED": 15,
	"SHIELD_ABSORBED": 16, "HEAL_APPLIED": 17, "PORTAL_USED": 18, "ENV_PORTAL": 19, "DM_KILL": 20,
	"MISS": 21, "CAST_CANCELLED": 22, "TANK_DESTROYED": 23, "OVERDRIVE": 24, "CHARIOT_KNOCK": 25}
var _ev_codes_src: Array = []
var _ev_codes_n: int = -1
var _ev_codes: PackedByteArray = PackedByteArray()
# Per event of the same list (damage, shield and heal events only; else
# -9999 / 0 / -1): the target unit's own team, whether the target is a nitro
# hero, and the projectile id. TeamIntel.ingest skips a team's events these
# prove it would ignore.
var _ev_gteam: PackedInt32Array = PackedInt32Array()
var _ev_gnitro: PackedByteArray = PackedByteArray()
var _ev_pid: PackedInt64Array = PackedInt64Array()


func ai_event_codes(events: Array) -> PackedByteArray:
	if is_same(events, _ev_codes_src) and _ev_codes_n == events.size():
		return _ev_codes
	_ev_codes_src = events
	_ev_codes_n = events.size()
	_ev_codes = PackedByteArray()
	_ev_codes.resize(_ev_codes_n)
	_ev_gteam = PackedInt32Array()
	_ev_gteam.resize(_ev_codes_n)
	_ev_gnitro = PackedByteArray()
	_ev_gnitro.resize(_ev_codes_n)
	_ev_pid = PackedInt64Array()
	_ev_pid.resize(_ev_codes_n)
	for i in _ev_codes_n:
		var ev: Dictionary = events[i]
		var code: int = int(AI_EV_CODES.get(str(ev.get("type", "")), 0))
		_ev_codes[i] = code
		_ev_gteam[i] = -9999
		_ev_gnitro[i] = 0
		_ev_pid[i] = -1
		if code == 15 or code == 16 or code == 17:
			var g: BUnit = u_at(int(ev.get("g", -1)))
			if g != null:
				_ev_gteam[i] = g.team
				_ev_gnitro[i] = 1 if g.is_hero and g.def != null and g.def.id == "nitro" else 0
			_ev_pid[i] = int(ev.get("projectile", -1))
	return _ev_codes


# Companions of ai_event_codes for the list it was last asked about.
func ai_event_gteam() -> PackedInt32Array:
	return _ev_gteam


func ai_event_gnitro() -> PackedByteArray:
	return _ev_gnitro


func ai_event_pid() -> PackedInt64Array:
	return _ev_pid
