class_name TeamIntel
extends RefCounted







const N_PART: = 20
const PROP_INTERVAL: = 0.1


class EnemyBelief:
	extends RefCounted
	var idx: int = -1
	var def: Defs.CharDef
	var is_hero: bool = true
	var kind: String = ""
	var visible: bool = false
	var ever_seen: bool = false
	var controlled_by_us: bool = false
	var pos: Vector2
	var vel: Vector2
	var facing: Vector2 = Vector2.RIGHT
	var last_seen_t: float = -999.0
	var last_seen_pos: Vector2
	var spawn_prior: Vector2
	var life_started_at: float = 0.0
	var hp: float = 1.0
	var max_hp: float = 1.0
	var shield: float = 0.0
	var radius: float = 17.0
	var statuses: Array = []
	var statuses_at: float = 0.0
	var casting: Dictionary = {}
	var particles: PackedVector2Array = PackedVector2Array()
	var weights: PackedFloat32Array = PackedFloat32Array()
	var modes: PackedByteArray = PackedByteArray()
	var confidence: float = 1.0
	var spread: float = 0.0
	var dead: bool = false
	var cd_last: PackedFloat64Array = PackedFloat64Array()
	var cd_cdr: PackedFloat64Array = PackedFloat64Array()
	var cd_disc: PackedFloat64Array = PackedFloat64Array()
	var cd_disc_t: float = -999.0
	var cd_disc_until: float = -1.0
	var unseen_since: float = 0.0
	var invis_until: float = -1.0
	# V1.5.3 fish model: estimated inventory (0..2) plus the next public 8 s
	# grant. Overflow is auto-eaten by the engine, so the estimate never
	# exceeds two and later throws stay possible (audit D8).
	var fish: float = 0.0
	var fish_next: float = 8.0
	var fish_used: int = 0
	var rage: float = 0.0
	var rage_rem: float = 0.0
	# Nitro rage decays by 1/s once 4 s pass without damage and 5 s without
	# health damage (audit D9). Both clocks come from observed hit events.
	var rage_damage_t: float = -999.0
	var rage_decay_next: float = INF
	var shards: float = 0.0
	var heal_bank: float = 0.0
	# V2 war_machine fuel model: counted from observed basic hits and observed
	# spends only. An observed charge or genocide windup is pending until its
	# cast time has passed (a cancel seen meanwhile refunds it). The attached
	# tank's HP is public while the tank is seen; its destruction and the
	# overdrive are public events of a seen owner (or our own kill).
	var fuel: float = 0.0
	var fuel_pending: float = 0.0
	var fuel_pending_at: float = INF
	var tank_hp: float = -1.0
	var tank_max_hp: float = 300.0
	var tank_seen_t: float = -999.0
	var tank_down_until: float = -1.0
	var overdrive_until: float = -1.0
	# Owner of a seen summon/structure (the fuel tank rides on its owner).
	var owner_idx: int = -1
	var sealed: Array = []
	var dodge_hits: float = 1.0
	var dodge_miss: float = 1.0
	var pos_hist: Array = []
	# Battle-local estimates: only samples actually observed by this team count.
	var movement_samples: int = 0
	var aggression: float = 0.5
	var strafe_bias: float = 0.0
	var turn_rate: float = 0.0
	var learned_at: float = -1.0
	var learned_vel: Vector2 = Vector2.ZERO
	var focus_counts: Dictionary = {}
	var reports_until: float = -1.0
	var reported_cd: Array = []
	var revealed_position_until: float = -1.0
	var respawn_at: float = -1.0
	var prop_debt: float = 0.0
	# V2 scale battles: time this belief's particles were frozen (-1 = live)
	# and its spread at that moment.
	var frozen_at: float = -1.0
	var frozen_spread: float = 0.0
	# V2: an observed entity that cannot be targeted (achilles' chariot). It
	# stays a danger belief but never enters the target lists.
	var untargetable: bool = false

	var threat: float = 0.0
	var burst: float = 0.0
	var reach: float = 0.0
	var dps: float = 0.0
	var cc_pot: float = 0.0

	func dodge_rate() -> float:
		return dodge_miss / (dodge_hits + dodge_miss)

	func has_status(t: String) -> bool:
		for s in statuses:
			if str(s.type) == t:
				return true
		return false

	func age_statuses(now: float) -> void:
		# Only age our last observation. Looking up authoritative hidden
		# statuses here would turn memory decay into an information leak.
		var dt: float = maxf(0.0, now - statuses_at)
		statuses_at = now
		for i in range(statuses.size() - 1, -1, -1):
			var row: Dictionary = statuses[i]
			row["remaining"] = maxf(0.0, float(row.get("remaining", 0.35)) - dt)
			if float(row.remaining) <= 0.0:
				statuses.remove_at(i)

	func hard_cc_remaining() -> float:
		var best: = 0.0
		for s in statuses:
			if str(s.type) in ["stun", "root", "airborne", "suppression", "sleep", "charm", "taunt"]:
				best = maxf(best, float(s.get("remaining", 0.35)))
		return best

	func movement_lock_remaining() -> float:
		var best: float = 0.0
		for s in statuses:
			if str(s.type) in ["stun", "root", "airborne", "suppression", "sleep"]:
				best = maxf(best, float(s.get("remaining", 0.35)))
		return best

	func ms() -> float:
		var v: = def.stat("moveSpeed")
		var pain: int = 0
		for s in statuses:
			if str(s.type) == "slow":
				v *= 1.0 - clampf(float(s.get("magnitude", 0.3)), 0.0, 0.9)
			elif str(s.type) == "pain":
				pain = maxi(pain, int(s.get("stacks", 0)))
		if not has_status("contemplation") and not has_status("unstoppable"):
			v *= 1.0 - minf(0.24, pain * 0.04)
		return v


var sim: BattleSim
var team: int = 0
var enemies: Dictionary = {}
var entities: Dictionary = {}
var projectiles: Array = []
var telegraphs: Array = []
var zones: Array = []
var proj_info: Dictionary = {}
var last_prop: float = 0.0
var anonymous_hits: int = 0
var rng: = RandomNumberGenerator.new()
var disclosures: int = 0
var casts_observed: int = 0
var shots_observed: Dictionary = {}
var learning_observations: int = 0
# V2: knockbacks each enemy chariot dealt to our heroes (public to the team
# that took them): chariot entity idx -> {our hero idx: count}.
var chariot_knocks: Dictionary = {}
# Deathmatch: beliefs about opponents far away and long unseen are advanced
# in coarser steps (their particles are diffuse anyway). Off in team modes.
var slow_far: bool = false
# Particles per unseen enemy: 20 in team modes, fewer in a free-for-all where
# every hero tracks up to eleven opponents.
var n_part: int = N_PART


func _init(s: BattleSim, t: int) -> void :
	sim = s
	team = t
	rng.seed = s.seed_value * 31 + t * 7 + 1
	if s.is_deathmatch():
		n_part = 10
		slow_far = true

	for u in s.heroes:
		if u.team == t:
			continue
		var b: = EnemyBelief.new()
		b.idx = u.idx
		b.def = u.def
		b.max_hp = u.def.stat("maxHealth")
		b.hp = b.max_hp
		b.radius = u.def.stat("bodyRadius")
		b.pos = u.pos
		b.last_seen_pos = u.pos
		b.spawn_prior = u.pos
		b.cd_last.resize(u.def.abilities.size())
		b.cd_cdr.resize(u.def.abilities.size())
		b.cd_disc.resize(u.def.abilities.size())
		for i in u.def.abilities.size():
			b.cd_last[i] = -999.0
			b.cd_cdr[i] = 0.0
			b.cd_disc[i] = -1.0
		b.particles.resize(n_part)
		b.weights.resize(n_part)
		b.modes.resize(n_part)
		b.fish_next = s.time + 8.0
		for i in n_part:
			b.particles[i] = u.pos
			b.weights[i] = 1.0 / n_part
			b.modes[i] = i % 4
		b.last_seen_t = 0.0
		enemies[u.idx] = b
	if s.is_deathmatch():
		# Free-for-all starts are seeded-random spawn picks: only the public
		# spawn list is known, never the opponent's actual start (audit DM-4).
		var own: Array = []
		for u in s.heroes:
			if u.team == t:
				own.append(u.pos)
		for k in enemies:
			var eb: EnemyBelief = enemies[k]
			_spread_over_spawns(eb, own)
			eb.last_seen_t = -10.0
			eb.ever_seen = false


func dispose() -> void :
	sim = null






func observe() -> void :
	var t: = sim.time
	# B-PERF2: effective teams from the pre-tick snapshot table when readable
	# (else eteam, once per body); is_seen inlined on the same value.
	var et: PackedInt32Array = sim.ai_et_table()
	var seen_arr: PackedByteArray = sim.seen[team]
	vis_heroes.clear()
	for u in sim.heroes:
		if u.team == team:
			continue
		var b: EnemyBelief = enemies.get(u.idx)
		if b == null or b.dead:
			continue
		if b.statuses.is_empty():
			b.statuses_at = t
		else:
			b.age_statuses(t)
		var ue: int = et[u.idx] if u.idx < et.size() and et[u.idx] != BattleSim.AI_ET_UNKNOWN else sim.ai_eteam(u)
		b.controlled_by_us = ue == team
		var seen: bool = (ue == team or (u.idx < seen_arr.size() and seen_arr[u.idx] == 1)) and u.alive
		if seen:
			var public: Dictionary = sim.warfare.observation(team, u)
			if not b.visible:
				b.pos_hist.clear()
			b.visible = true
			vis_heroes.append(b)
			b.ever_seen = true
			b.pos = public.get("pos", u.pos)
			b.facing = u.facing
			b.pos_hist.append([t, b.pos])
			if b.pos_hist.size() > 6:
				b.pos_hist.pop_front()
			b.vel = _est_vel(b)
			_learn_movement(b, t)
			b.last_seen_t = t
			b.last_seen_pos = b.pos
			b.hp = float(public.get("hp", u.hp))
			b.reported_cd = public.get("ready_at", [])
			b.reports_until = t + PROP_INTERVAL * 2.0 if not b.reported_cd.is_empty() else -1.0
			b.max_hp = sim.max_hp(u)
			b.shield = sim.shield_amount(u)
			b.radius = sim.radius(u)
			b.sealed = u.sealed.duplicate()
			b.statuses.clear()
			for s in u.statuses:
				if s.end <= t:
					continue
				var own: = false
				var src: = sim.u_at(s.source_idx)
				if src and sim.ai_eteam(src) == team:
					own = true
				var row: = {"type": String(s.type), "stacks": s.stacks, "own": own, "source": s.source_idx}
				if own:

					row["remaining"] = s.end - t
					row["magnitude"] = s.magnitude
				else:
					row["remaining"] = 0.35
					row["magnitude"] = 0.3
				b.statuses.append(row)
			if sim.get_buff(u, &"projectileGuard"):
				b.statuses.append({"type": "projectile_guard", "stacks": 1, "own": false})
			b.casting = {}
			if u.action and u.action.windup:
				var a: = u.action.ability

				var rem: = maxf(0.0, u.action.resolve_at - t)
				if a and not a.virtual and a.index < b.cd_last.size() and absf(b.cd_last[a.index] - u.action.started_at) > 0.05:
					rem = a.cast_time * 0.5
				b.casting = {"slot": a.slot if a else 0, "basic": u.action.kind == "basic", "pos": u.action.target_pos, 
					"target": u.action.target_idx, "remaining": rem, "ability": a}
			for i in n_part:
				b.particles[i] = b.pos
				b.weights[i] = 1.0 / n_part
			b.confidence = 1.0
			b.spread = 0.0
			b.unseen_since = t
			b.frozen_at = -1.0
		else:
			if b.visible:
				b.unseen_since = t
				_seed_particles(b)
			b.visible = false
			if not b.casting.is_empty():
				b.casting = {}

	var keep: Dictionary = {}
	# Remember only what this team observed. The authoritative entity list
	# prunes hidden deaths immediately, so it cannot be the memory's source.
	for idx in entities:
		var known: EnemyBelief = entities[idx]
		if t - known.last_seen_t < 2.0:
			known.visible = false
			keep[idx] = known
	for e in sim.entities:
		if not e.alive:
			continue
		var ee: int = et[e.idx] if e.idx < et.size() and et[e.idx] != BattleSim.AI_ET_UNKNOWN else sim.ai_eteam(e)
		if ee == team:
			continue
		# is_seen (its own-team case is excluded just above).
		if e.idx < seen_arr.size() and seen_arr[e.idx] == 1:
			var b2: EnemyBelief = entities.get(e.idx)
			if b2 == null:
				b2 = EnemyBelief.new()
				b2.idx = e.idx
				b2.def = e.def
				b2.is_hero = false
				b2.kind = e.kind
			b2.visible = true
			b2.pos = e.pos
			b2.vel = e.vel
			b2.hp = e.hp
			b2.max_hp = sim.max_hp(e)
			b2.radius = sim.radius(e)
			b2.untargetable = sim.has_status(e, &"untargetable")
			b2.last_seen_t = t
			b2.owner_idx = e.owner_idx
			keep[e.idx] = b2
			if e.kind == "fuel_tank":
				_tank_seen(b2, t)
	entities = keep

	zones.clear()
	_pv_ready = false
	for z in sim.zones.list:
		if z.team == team or z.end <= t:
			continue
		if z.kind in ["portal", "bed"]:
			continue
		if _point_visible_cached(z.pos):
			zones.append({"id": z.id, "kind": z.kind, "pos": z.pos, "radius": z.radius, "end": z.end, "shape": z.shape, "dir": z.dir, "range": z.range, "angle": z.angle, "harm": z.filter != "ally", "data_a": z.data.get("a", Vector2.ZERO), "data_b": z.data.get("b", Vector2.ZERO)})
	if t - last_prop >= (SCALE_PROP_INTERVAL if sim.scale_lod else PROP_INTERVAL):
		_propagate(t - last_prop)
		last_prop = t


func _est_vel(b: EnemyBelief) -> Vector2:
	if b.pos_hist.size() < 2:
		return Vector2.ZERO
	var a: Array = b.pos_hist[0]
	var c: Array = b.pos_hist[b.pos_hist.size() - 1]
	var dt: = float(c[0]) - float(a[0])
	if dt < 0.03:
		return Vector2.ZERO
	return (((c[1] as Vector2) - (a[1] as Vector2)) / dt).limit_length(b.ms() * 1.8)


func _learn_movement(b: EnemyBelief, t: float) -> void:
	if t - b.learned_at < 0.3 or b.vel.length() < 8.0:
		return
	var nearest: BUnit = null
	var distance: float = INF
	for a in sim.ai_allies(team, true):
		var d: float = a.pos.distance_squared_to(b.pos)
		if d < distance:
			distance = d
			nearest = a
	if nearest == null or distance > 650.0 * 650.0:
		return
	var approach: Vector2 = (nearest.pos - b.pos).normalized()
	var motion: Vector2 = b.vel.normalized()
	# A slow, bounded moving average adapts to changed behavior; prior samples
	# protect against declaring a tendency from one dodge or teleport.
	var alpha: float = 0.08
	b.aggression = lerpf(b.aggression, (motion.dot(approach) + 1.0) * 0.5, alpha)
	b.strafe_bias = lerpf(b.strafe_bias, approach.cross(motion), alpha)
	if b.learned_vel.length() > 8.0:
		b.turn_rate = lerpf(b.turn_rate, absf(b.learned_vel.angle_to(b.vel)) / PI, alpha)
	b.learned_vel = b.vel
	b.learned_at = t
	b.movement_samples = mini(10000, b.movement_samples + 1)
	learning_observations += 1


func _learn_focus(b: EnemyBelief, target_idx: int) -> void:
	var ally: BUnit = sim.u_at(target_idx)
	if ally == null or ally.team != team:
		return
	for k in b.focus_counts:
		b.focus_counts[k] = float(b.focus_counts[k]) * 0.92
	b.focus_counts[target_idx] = float(b.focus_counts.get(target_idx, 0.0)) + 1.0
	learning_observations += 1


func focus_evidence(target_idx: int) -> float:
	var evidence: float = 0.0
	for item in enemies.values():
		var b: EnemyBelief = item
		if b.dead:
			continue
		var total: float = 3.0
		for count in b.focus_counts.values():
			total += float(count)
		evidence += float(b.focus_counts.get(target_idx, 0.0)) / total
	return evidence



func observe_fast() -> void :
	projectiles.clear()
	var allies: = sim.ai_allies(team, true)
	var a_r2: PackedFloat64Array = PackedFloat64Array()
	if not sim.proj.list.is_empty():
		for a0 in allies:
			var sr: float = sim.ai_sensor_range(a0)
			a_r2.append(sr * sr)
	for p in sim.proj.list:
		if p.team == team or p.dead:
			continue
		var visible: = false
		for ai in allies.size():
			var a: BUnit = allies[ai]
			if a.pos.distance_squared_to(p.pos) <= a_r2[ai] and a.chamber == p.realm:
				if sim.arena.line_of_sight(a.pos, p.pos, 2.0):
					visible = true
					break
		if not visible:
			continue
		var info: Dictionary = proj_info.get(p.id, {})
		projectiles.append({"id": p.id, "pos": p.pos, "vel": p.vel, "radius": p.radius, "homing": p.homing, 
			"target": p.target_idx if p.homing else -1, "dmg": _proj_damage(p, info), "slot": int(info.get("slot", 0)), 
			"source": int(info.get("source", -1)), "explode": p.explode_on_arrival, "target_pos": p.target_pos, 
			"impact_r": float(p.ctx.get("impact_radius", 0.0)) if p.explode_on_arrival else 0.0, "cc": bool(info.get("cc", false))})
	telegraphs.clear()
	_pv_ready = false
	var env_on: bool = sim.env != null and sim.env.enabled
	for tg in sim.telegraphs:
		if tg.cancelled or tg.end <= sim.time or int(tg.team) == team:
			continue
		# V1.5.3 environment telegraphs (artillery salvos: source -1, team -1)
		# are public map state the moment they are announced (DESIGN_153 §0.2),
		# seen or not, and carry their real strike damage.
		if int(tg.source) < 0 and (int(tg.team) < 0 or bool(tg.get("env", false))):
			if not env_on:
				continue
			telegraphs.append({"shape": tg.shape, "from": tg.to, "to": tg.to, "radius": tg.radius, "width": tg.width,
				"range": tg.range, "angle": tg.angle, "due": tg.end, "dmg": float(tg.get("dmg", 90.0)), "cc": false, "source": -1, "env": true})
			continue
		var src: = sim.u_at(int(tg.source))
		var src_vis: = src != null and sim.ai_is_seen(team, src)
		if not src_vis and not (tg.shape == "circle" and _point_visible_cached(tg.to)):
			continue
		var ab = tg.ability
		var dmg: = 90.0
		var cc: = false
		if ab is Defs.AbilityDef:
			dmg = KitModel.nominal_damage(ab as Defs.AbilityDef, src.def if src else null)
			cc = not (ab as Defs.AbilityDef).cc_types.is_empty()
		elif tg.has("dmg"):
			dmg = float(tg.dmg)
		telegraphs.append({"shape": tg.shape, "from": tg.from if src_vis else tg.to, "to": tg.to, "radius": tg.radius, "width": tg.width,
			"range": tg.range, "angle": tg.angle, "due": tg.end, "dmg": dmg, "cc": cc, "source": tg.source if src_vis else -1, "env": false})


func _proj_damage(_p: ST.Projectile, info: Dictionary) -> float:

	if info.has("dmg"):
		return float(info.dmg)
	return 70.0


func _point_visible(p: Vector2) -> bool:
	for a in sim.ai_allies(team, true):
		if a.pos.distance_squared_to(p) <= sim.sensor_range(a) * sim.sensor_range(a) and not _forest_hides(a, p, 0.0) and sim.arena.line_of_sight(a.pos, p, 2.0):
			return true
	return false


# _point_visible for a run of points within one observe pass (B-PERF2): our
# bodies' positions, squared sensor ranges and radii are read once per pass
# (the same values, the same body order) instead of once per point.
var _pv_ready: bool = false
var _pv_pos: PackedVector2Array = PackedVector2Array()
var _pv_r2: PackedFloat64Array = PackedFloat64Array()
var _pv_rad: PackedFloat64Array = PackedFloat64Array()


func _point_visible_cached(p: Vector2) -> bool:
	if not _pv_ready:
		_pv_ready = true
		_pv_pos = PackedVector2Array()
		_pv_r2 = PackedFloat64Array()
		_pv_rad = PackedFloat64Array()
		for a in sim.ai_allies(team, true):
			_pv_pos.append(a.pos)
			var sr2: float = sim.ai_sensor_range(a)
			_pv_r2.append(sr2 * sr2)
			_pv_rad.append(sim.radius(a))
	for k in _pv_pos.size():
		var ap: Vector2 = _pv_pos[k]
		if ap.distance_squared_to(p) <= _pv_r2[k] and not brush_hides(ap, p, 0.0, _pv_rad[k]) and sim.arena.line_of_sight(ap, p, 2.0):
			return true
	return false


# Brush/forest concealment as the simulator applies it (sim.observes): a point
# inside a patch is hidden from an observer outside that patch beyond the
# 110 reveal range, and deep canopy between the two blocks the line (D13).
func _forest_hides(a: BUnit, p: Vector2, r: float) -> bool:
	return brush_hides(a.pos, p, r, sim.radius(a))


# Position form of the same rule, for hypothetical viewpoints (scouting): true
# when brush/forest would hide a body of radius r at p from an observer of
# radius from_r standing at from. Public: the scout gain uses it (D13).
func brush_hides(from: Vector2, p: Vector2, r: float = 0.0, from_r: float = 0.0) -> bool:
	var ar: Arena = sim.arena
	# The developer "brush" switch (ArenaEnv.set_type_enabled) turns concealment
	# off in sim.observes; the belief model follows it (engine follow-up).
	if ar.forest_x.is_empty() or not sim.brush_on:
		return false
	var patch: int = ar.forest_at(p)
	if patch >= 0 and ar.forest_at(from) != patch and from.distance_to(p) > 110.0 + from_r + r:
		return true
	return ar.forest_occludes(from, p)


# Public free-for-all spawn points in play (DeathmatchMode.spawn_candidates:
# the inner region in a 2-3 player match), farthest from the given (own)
# positions first. Small-match respawns follow the public rule of
# DeathmatchMode.choose_spawn instead: about SMALL_RESPAWN_CAP out of reach,
# not across the map (review 1.5.3: most particles sat on spawn points the
# mode never uses). Used for the opening prior and for respawns, never true
# positions; the RNG draws per particle are unchanged.
func _spread_over_spawns(b: EnemyBelief, avoid: Array, respawn: bool = false) -> void:
	var dm: DeathmatchMode = sim.deathmatch
	var spawns: Array = dm.spawn_candidates() if dm else sim.arena.ffa_spawns
	var small: bool = respawn and dm != null and dm.small_match()
	var ranked: Array = []
	for q in spawns:
		var near: float = 850.0
		for o in avoid:
			near = minf(near, (q as Vector2).distance_to(o))
		var score: float = near
		if small:
			var raw: float = INF
			for o2 in avoid:
				raw = minf(raw, (q as Vector2).distance_to(o2))
			if raw == INF:
				raw = 850.0
			score = minf(raw, DeathmatchMode.SMALL_RESPAWN_CAP) - maxf(0.0, raw - DeathmatchMode.SMALL_RESPAWN_CAP - 400.0) * 0.15
		ranked.append([score, q, near])
	ranked.sort_custom(func(x, y): return float(x[0]) > float(y[0]) or (float(x[0]) == float(y[0]) and ((x[1] as Vector2).x < (y[1] as Vector2).x or ((x[1] as Vector2).x == (y[1] as Vector2).x and (x[1] as Vector2).y < (y[1] as Vector2).y))))
	var usable: Array = []
	for row in ranked:
		if float(row[2]) > 260.0:
			usable.append(row[1])
	if usable.is_empty():
		for row in ranked:
			usable.append(row[1])
	if usable.is_empty():
		usable.append(sim.arena.center())
	b.frozen_at = -1.0
	for i in n_part:
		var q2: Vector2 = usable[i % usable.size()]
		b.particles[i] = sim.arena.resolve_circle(q2 + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)), b.radius)
		b.weights[i] = 1.0 / n_part
		b.modes[i] = i % 4
	var m: Vector2 = Vector2.ZERO
	for i in n_part:
		m += b.particles[i] / n_part
	var var_sum: float = 0.0
	for i in n_part:
		var_sum += b.particles[i].distance_squared_to(m) / n_part
	b.pos = m
	b.last_seen_pos = m
	b.vel = Vector2.ZERO
	b.spread = sqrt(var_sum)
	b.confidence = clampf(0.2 - b.spread / 3200.0, 0.05, 0.2)






func ingest(events: Array) -> void :
	# B-PERF2: types this match never reads are skipped by their tick code,
	# and so are damage / shield / heal events on another team's body that
	# can feed neither nitro rage nor one of our tracked shots (no effect here).
	var codes: PackedByteArray = sim.ai_event_codes(events)
	var gteam: PackedInt32Array = sim.ai_event_gteam()
	var gnitro: PackedByteArray = sim.ai_event_gnitro()
	var pids: PackedInt64Array = sim.ai_event_pid()
	for ei in events.size():
		var code: int = codes[ei]
		if code == 0:
			continue
		if code >= 15 and code <= 17 and gteam[ei] != team:
			if code == 17 or (gnitro[ei] == 0 and not shots_observed.has(pids[ei])):
				continue
		var ev = events[ei]
		var ty: = str(ev.type)
		var s: = int(ev.s)
		var g: = int(ev.g)
		var sv: bool = (ev.sv as Array)[team]
		var gv: bool = (ev.gv as Array)[team]
		match ty:
			"HERO_RESPAWNED":
				if enemies.has(g):
					var returning: EnemyBelief = enemies[g]
					returning.dead = false
					returning.visible = false
					returning.controlled_by_us = false
					returning.max_hp = returning.def.stat("maxHealth")
					returning.radius = returning.def.stat("bodyRadius")
					returning.hp = returning.max_hp
					returning.life_started_at = float(ev.t)
					returning.shield = 0.0
					returning.statuses.clear()
					returning.casting.clear()
					returning.pos_hist.clear()
					returning.sealed.clear()
					returning.reported_cd.clear()
					returning.reports_until = -1.0
					returning.cd_disc_until = -1.0
					returning.revealed_position_until = -1.0
					returning.invis_until = -1.0
					returning.rage = 0.0
					returning.rage_rem = 0.0
					returning.rage_damage_t = -999.0
					returning.rage_decay_next = INF
					returning.shards = 0.0
					returning.heal_bank = 0.0
					returning.fish_used = 0
					returning.fish = 0.0
					returning.fish_next = float(ev.t) + 8.0
					_fuel_reset(returning)
					# Public respawn fact gives a spawn-region prior, not a
					# fresh observation of the enemy's actual current position.
					returning.pos = returning.spawn_prior
					returning.last_seen_pos = returning.spawn_prior
					returning.last_seen_t = sim.time - 8.0
					returning.unseen_since = sim.time
					returning.vel = Vector2.ZERO
					returning.confidence = 0.2
					returning.spread = 80.0
					if sim.is_deathmatch():
						# Deathmatch respawns pick a public spawn point away from
						# every living hero (far in a big match, about 600 px out
						# of reach in a 2-3 player match): spread over those.
						var avoid: Array = []
						for a0 in sim.ai_allies(team):
							avoid.append(a0.pos)
						for other in enemies.values():
							var ob: EnemyBelief = other
							if ob != returning and ob.visible and not ob.dead:
								avoid.append(ob.pos)
						_spread_over_spawns(returning, avoid, true)
					else:
						returning.frozen_at = -1.0
						for n in n_part:
							returning.particles[n] = sim.arena.resolve_circle(returning.spawn_prior + Vector2.from_angle(n * TAU / n_part) * 90.0, returning.radius)
							returning.weights[n] = 1.0 / n_part
					# Observed prior-life cast times remain valid: respawn
					# preserves real cooldowns instead of resetting them.
			"RESPAWN_SCHEDULED":
				if enemies.has(g):
					(enemies[g] as EnemyBelief).dead = true
					(enemies[g] as EnemyBelief).visible = false
					(enemies[g] as EnemyBelief).respawn_at = float(ev.get("respawn_at", -1.0))
			"CAST_STARTED":
				if sv and enemies.has(s):
					var b: EnemyBelief = enemies[s]
					var slot: = int(ev.get("slot", 0))
					casts_observed += 1
					_learn_focus(b, g)
					if slot >= 1 and slot <= b.cd_last.size():
						b.cd_last[slot - 1] = float(ev.t)
						b.cd_cdr[slot - 1] = 0.0
						b.cd_disc[slot - 1] = -1.0
						var a: Defs.AbilityDef = b.def.abilities[slot - 1]
						_consume_resources(b, a, float(ev.t))
						if a.action == "cloak" or (a.char_id == "sniper" and a.slot == 2):
							b.invis_until = float(ev.t) + 2.4
						if b.def.id == "war_machine":
							_fuel_cast(b, a, ev)
					elif ev.get("virtual", false):
						var ab = ev.get("ability")
						if ab is Defs.AbilityDef and (ab as Defs.AbilityDef).virtual_kind == "eat":
							_fish_consume(b, float(ev.t))
			"PROJECTILE_CREATED":
				var shooter: BUnit = sim.u_at(s)
				var outgoing = ev.get("ability")
				if shooter and shooter.team == team and enemies.has(g) and gv and outgoing is Defs.AbilityDef:
					if not (outgoing as Defs.AbilityDef).homing:
						shots_observed[int(ev.id)] = {"target": g, "source": s, "at": float(ev.t), "hit": false}
				if sv and enemies.has(s):
					var ab2 = ev.get("ability")
					var b2: EnemyBelief = enemies[s]
					if ab2 is Defs.AbilityDef:
						var ad: = ab2 as Defs.AbilityDef
						proj_info[int(ev.id)] = {"slot": ad.slot, "source": s, "dmg": KitModel.nominal_damage(ad, b2.def), "cc": not ad.cc_types.is_empty()}
					elif ev.get("basic", false):
						proj_info[int(ev.id)] = {"slot": 0, "source": s, "dmg": b2.def.stat("attackDamage") * 0.8}
			"PROJECTILE_END":
				proj_info.erase(int(ev.id))
				var shot: Dictionary = shots_observed.get(int(ev.id), {})
				if not shot.is_empty():
					var observed: EnemyBelief = enemies.get(int(shot.target))
					if observed and observed.visible and not bool(shot.get("hit", false)) and str(ev.get("reason", "")) == "range":
						observed.dodge_miss = minf(30.0, observed.dodge_miss + 0.5)
						learning_observations += 1
					shots_observed.erase(int(ev.id))
			"CC_APPLIED":

				if sv and enemies.has(s):
					var b3: EnemyBelief = enemies[s]
					if b3.def.id == "mage" and ev.get("fresh", true):
						for i in b3.cd_cdr.size():
							b3.cd_cdr[i] = minf(b3.cd_cdr[i] + 0.45, 6.0)
			"REVEAL":
				if int(ev.get("team", -1)) == team and enemies.has(g):
					var b4: EnemyBelief = enemies[g]
					var ra: Array = ev.ready_at
					for i in mini(ra.size(), b4.cd_disc.size()):
						b4.cd_disc[i] = float(ra[i])
					b4.cd_disc_t = float(ev.t)
					b4.cd_disc_until = float(ev.t) + float(ev.get("duration", 5.0))
					disclosures += 1
			"INFO_REVEAL":
				if int(ev.get("team", -1)) == team and enemies.has(g):
					var disclosed: EnemyBelief = enemies[g]
					match str(ev.get("field", "")):
						"position":
							disclosed.pos = ev.value
							disclosed.last_seen_pos = disclosed.pos
							disclosed.last_seen_t = float(ev.t)
							disclosed.confidence = 0.9
							disclosed.revealed_position_until = float(ev.t) + float(ev.get("duration", 5.0))
							_seed_particles(disclosed)
						"health":
							var health: Dictionary = ev.get("value", {})
							disclosed.hp = float(health.get("hp", disclosed.hp))
							disclosed.max_hp = float(health.get("max_hp", disclosed.max_hp))
							# Cooldown disclosures also emit REVEAL, so count once.
					if str(ev.get("field", "")) != "cooldowns":
						disclosures += 1
			"DEATH", "EXECUTED":
				if enemies.has(g):
					var killer: = sim.u_at(s)
					if gv or (killer and killer.team == team):
						(enemies[g] as EnemyBelief).dead = true
			"SUMMON_DESTROYED", "SUMMON_EXPIRED", "STRUCTURE_REPLACED":
				var destroyer: BUnit = sim.u_at(s)
				if gv or (destroyer and destroyer.team == team):
					entities.erase(g)
			"ENV_HIT":
				if enemies.has(g) and gv and (enemies[g] as EnemyBelief).def.id == "nitro":
					_rage_hit(enemies[g], float(ev.t), float(ev.get("amount", 0.0)))
			"HEALTH_DAMAGED", "SHIELD_ABSORBED":
				var amount: = float(ev.get("amount", 0.0))
				if enemies.has(g) and gv:
					var b5: EnemyBelief = enemies[g]
					# Rage comes from health damage by someone else only (D9);
					# a fully absorbed hit still delays the decay clock.
					if b5.def.id == "nitro" and s != g:
						_rage_hit(b5, float(ev.t), amount)
				if sv and gv and enemies.has(s) and bool(ev.get("basic", false)) and (enemies[s] as EnemyBelief).def.id == "war_machine":
					_fuel_basic(enemies[s], g, ev)
				var tgt: = sim.u_at(g)
				if tgt and tgt.team == team and s >= 0 and not sv and ev.get("source_type", "") != "ENVIRONMENT":
					_anonymous_hit(tgt.pos)

				var projectile_id: int = int(ev.get("projectile", -1))
				var shot_hit: Dictionary = shots_observed.get(projectile_id, {})
				if enemies.has(g) and gv and not shot_hit.is_empty() and int(shot_hit.target) == g and int(shot_hit.source) == s and not bool(shot_hit.hit):
					shot_hit.hit = true
					(enemies[g] as EnemyBelief).dodge_hits = minf(30.0, (enemies[g] as EnemyBelief).dodge_hits + 0.5)
					learning_observations += 1
			"HEAL_APPLIED":
				var reduced: = float(ev.get("reduced", 0.0))
				var tgt2: = sim.u_at(g)
				if reduced > 0.0 and tgt2 and tgt2.team == team:
					for b6 in enemies.values():
						if (b6 as EnemyBelief).def.id == "plague_doctor":
							(b6 as EnemyBelief).heal_bank = minf(1200.0, (b6 as EnemyBelief).heal_bank + reduced * 0.8)
			"PORTAL_USED", "ENV_PORTAL":
				if enemies.has(g) and gv and (enemies[g] as EnemyBelief).def.id == "dimensionalist":
					var b7: EnemyBelief = enemies[g]
					b7.shards = minf(40.0, b7.shards + 10.0)
			"MISS":
				# Failed legality/conditions are not evidence of a dodge.
				pass
			"CAST_CANCELLED":
				if sv and enemies.has(s):
					_fuel_cancel(enemies[s])
			"TANK_DESTROYED":
				# s: the tank's killer, g: its owner. Public for a seen owner,
				# or when our own unit destroyed the tank.
				var breaker: BUnit = sim.u_at(s)
				if enemies.has(g) and (gv or (breaker and sim.eteam(breaker) == team)):
					var owner_b: EnemyBelief = enemies[g]
					var tank_rule: Dictionary = _fuel_rule(owner_b)
					owner_b.fuel = 0.0
					owner_b.fuel_pending = 0.0
					owner_b.fuel_pending_at = INF
					owner_b.tank_hp = 0.0
					owner_b.tank_down_until = float(ev.t) + float(tank_rule.get("respawn", TANK_RESPAWN))
					owner_b.overdrive_until = maxf(owner_b.overdrive_until, float(ev.t) + float(tank_rule.get("overdrive", TANK_RESPAWN)))
			"OVERDRIVE":
				if enemies.has(g) and gv:
					var od_b: EnemyBelief = enemies[g]
					od_b.overdrive_until = float(ev.t) + float(ev.get("duration", TANK_RESPAWN))
			"CHARIOT_KNOCK":
				var knocked: BUnit = sim.u_at(g)
				if knocked and knocked.team == team:
					var per: Dictionary = chariot_knocks.get(int(ev.get("entity", -1)), {})
					per[g] = maxi(int(per.get(g, 0)), int(ev.get("count", 1)))
					chariot_knocks[int(ev.get("entity", -1))] = per


func _consume_resources(b: EnemyBelief, a: Defs.AbilityDef, at: float = -1.0) -> void :
	if at < 0.0:
		at = sim.time
	for f in a.effects:
		if str(f.get("type", "")) == "consume_resource":
			match str(f.key):
				"fish":
					_fish_consume(b, at)
				"rage":
					rage_now(b, at)
					b.rage = maxf(0.0, b.rage - float(f.amount))
				"shards":
					b.shards = maxf(0.0, b.shards - float(f.amount))
	if a.action == "healingMist":
		b.heal_bank = maxf(0.0, b.heal_bank - 520.0)


func _anonymous_hit(at: Vector2) -> void :

	anonymous_hits += 1
	for b in enemies.values():
		var eb: EnemyBelief = b
		if eb.visible or eb.dead:
			continue
		var reach: = eb.def.stat("attackRange") + 60.0
		for a in eb.def.abilities:
			reach = maxf(reach, (a as Defs.AbilityDef).range + 40.0)
		for i in n_part:
			if eb.particles[i].distance_to(at) <= reach:
				eb.weights[i] *= 2.2
			else:
				eb.weights[i] *= 0.55
		_normalize(eb)






func _seed_particles(b: EnemyBelief) -> void :
	b.frozen_at = -1.0
	for i in n_part:
		b.particles[i] = b.pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		b.weights[i] = 1.0 / n_part
		b.modes[i] = i % 4


func _propagate(dt: float) -> void :
	var ours: = sim.ai_allies(team, true)
	var our_c: = Vector2.ZERO
	for a in ours:
		our_c += a.pos
	our_c = our_c / maxf(1, ours.size()) if not ours.is_empty() else sim.arena.center()
	var their_c: = Vector2.ZERO
	var nth: = 0
	for b in enemies.values():
		var eb: EnemyBelief = b
		if not eb.dead:
			their_c += eb.pos
			nth += 1
	their_c = their_c / maxf(1, nth) if nth > 0 else sim.arena.center()
	var forested: bool = sim.brush_on and not sim.arena.forest_x.is_empty()
	var freeze: bool = sim.scale_lod
	# V2 (B-PERF): our bodies' positions, squared sensor ranges and radii,
	# read once per call instead of once per particle (same values).
	var o_pos: PackedVector2Array = PackedVector2Array()
	var o_r2: PackedFloat64Array = PackedFloat64Array()
	var o_rad: PackedFloat64Array = PackedFloat64Array()
	for a0 in ours:
		var sr: float = sim.ai_sensor_range(a0)
		o_pos.append(a0.pos)
		o_r2.append(sr * sr)
		o_rad.append(sim.radius(a0))
	var n_ours: int = o_pos.size()
	for b in enemies.values():
		var eb: EnemyBelief = b
		if eb.visible or eb.dead:
			continue
		if freeze:
			if sim.time - eb.last_seen_t > FREEZE_UNSEEN and _far_from_all(ours, eb.pos, FREEZE_RANGE):
				_freeze_step(eb, dt)
				continue
			if eb.frozen_at >= 0.0:
				_thaw(eb)
		var step_dt: float = dt
		if slow_far:
			eb.prop_debt += dt
			var near_any: bool = false
			for a in ours:
				if a.pos.distance_squared_to(eb.pos) < 760.0 * 760.0:
					near_any = true
					break
			# Scale battles (B-PERF2): mid-range beliefs step every SCALE_FAR_STEP s.
			if not near_any and sim.time - eb.last_seen_t > 1.5 and eb.prop_debt < (SCALE_FAR_STEP if freeze else 0.6):
				continue
			step_dt = eb.prop_debt
			eb.prop_debt = 0.0
		var spd: = eb.def.stat("moveSpeed")
		var r: = eb.radius
		var invis: = sim.time < eb.invis_until
		var total: = 0.0
		for i in n_part:
			var p: = eb.particles[i]
			var dir: = Vector2.ZERO
			match eb.modes[i]:
				0:
					dir = eb.vel.normalized() if eb.vel.length() > 5.0 else (our_c - p).normalized()
				1:
					dir = (our_c - p).normalized()
					if eb.movement_samples >= 8 and eb.aggression < 0.4:
						dir = -dir
				2:
					dir = (their_c - p).normalized()
					if eb.movement_samples >= 8 and absf(eb.strafe_bias) > 0.2:
						var toward: Vector2 = (our_c - p).normalized()
						dir = (dir + Vector2(-toward.y, toward.x) * eb.strafe_bias).normalized()
				_:
					dir = Vector2.from_angle(rng.randf() * TAU)
			if (p - our_c).length() < 120.0 and eb.modes[i] == 1:
				dir = Vector2.from_angle(rng.randf() * TAU)
			p = sim.arena.resolve_circle(p + dir * spd * step_dt * rng.randf_range(0.35, 1.0), r)
			eb.particles[i] = p

			var w: = eb.weights[i]
			for k in n_ours:
				var ap: Vector2 = o_pos[k]
				if ap.distance_squared_to(p) <= o_r2[k]:
					if invis and ap.distance_to(p) > o_rad[k] + r + 62.0:
						w *= 0.8
					elif forested and brush_hides(ap, p, r, o_rad[k]):
						# Brush hides a unit from this observer: no evidence.
						continue
					elif sim.arena.line_of_sight(ap, p, 2.0):
						w *= 0.04
						break
			eb.weights[i] = w
			total += w
		if total < 1e-06:

			for i in n_part:
				var ang: = rng.randf() * TAU
				var q: = sim.arena.resolve_circle(eb.last_seen_pos + Vector2.from_angle(ang) * rng.randf_range(80.0, 420.0), r)
				eb.particles[i] = q
				eb.weights[i] = 1.0 / n_part
				eb.modes[i] = i % 4
		else:
			_normalize(eb)
		_resample_if_needed(eb)
		_estimate(eb)


func _normalize(eb: EnemyBelief) -> void :
	var total: = 0.0
	for i in n_part:
		total += eb.weights[i]
	if total <= 0.0:
		return
	for i in n_part:
		eb.weights[i] /= total


func _resample_if_needed(eb: EnemyBelief) -> void :
	var ess_den: = 0.0
	for i in n_part:
		ess_den += eb.weights[i] * eb.weights[i]
	var ess: = 1.0 / maxf(1e-09, ess_den)
	if ess >= n_part * 0.5:
		return
	var newp: = PackedVector2Array()
	newp.resize(n_part)
	var step: = 1.0 / n_part
	var u: = rng.randf() * step
	var c: = eb.weights[0]
	var j: = 0
	for i in n_part:
		var target: = u + i * step
		while target > c and j < n_part - 1:
			j += 1
			c += eb.weights[j]
		newp[i] = sim.arena.resolve_circle(eb.particles[j] + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)), eb.radius)
	eb.particles = newp
	for i in n_part:
		eb.weights[i] = 1.0 / n_part


func _estimate(eb: EnemyBelief) -> void :
	var m: = Vector2.ZERO
	for i in n_part:
		m += eb.particles[i] * eb.weights[i]
	var var_sum: = 0.0
	for i in n_part:
		var_sum += eb.weights[i] * eb.particles[i].distance_squared_to(m)
	eb.pos = m
	eb.spread = sqrt(var_sum)
	var age: = sim.time - eb.last_seen_t
	eb.confidence = clampf((1.0 - eb.spread / 320.0) * exp( - age * 0.06), 0.05, 0.95)







func ready_prob(b: EnemyBelief, i: int) -> float:
	if b.dead or i >= b.def.abilities.size():
		return 0.0
	if b.sealed.has(i):
		return 0.0
	var a: Defs.AbilityDef = b.def.abilities[i]
	var t: = sim.time
	# Reports are allowed to be deceptive. The strategist never asks the
	# simulation whether a particular report is true.
	if b.reports_until >= t and i < b.reported_cd.size():
		return 1.0 if float(b.reported_cd[i]) <= t else 0.0

	if b.cd_disc_until >= t and b.cd_disc[i] >= 0.0 and b.cd_disc_t > b.cd_last[i]:
		var rem: = b.cd_disc[i] - t - b.cd_cdr[i]
		return 1.0 if rem <= 0.0 else 0.0
	if not _resource_ok(b, a):
		return 0.0
	var hidden: = maxf(0.0, t - maxf(b.last_seen_t, b.unseen_since)) if not b.visible else 0.0
	var hostile: = a.target in ["enemy", "position"]
	var hidden_rate: = 0.06 if hostile else 0.12
	var hidden_keep: = exp( - hidden * hidden_rate)
	if b.cd_last[i] < -100.0:
		return 0.97 * hidden_keep + 0.03
	var cd: = a.cooldown
	var cd_min: = cd
	if a.action == "rift":
		cd_min = cd - 8.0
	elif a.action == "portalPair":
		cd_min = cd - 4.0
	elif a.action == "turret":
		cd_min = maxf(7.2, cd - 4.8)
	var ready_min: = b.cd_last[i] + cd_min - b.cd_cdr[i]
	var ready_max: = b.cd_last[i] + cd - b.cd_cdr[i]
	if b.def.id == "mage":
		ready_min -= 1.0
	var p: = 0.0
	if t >= ready_max:
		p = 1.0
	elif t > ready_min:
		p = (t - ready_min) / maxf(0.01, ready_max - ready_min)

	if p > 0.0 and not b.visible:
		var since_ready: = maxf(0.0, t - maxf(ready_min, maxf(b.last_seen_t, b.unseen_since)))
		p *= exp( - since_ready * hidden_rate)
	return clampf(p, 0.0, 1.0)


func ready_eta(b: EnemyBelief, i: int) -> float:
	if b.reports_until >= sim.time and i < b.reported_cd.size():
		return maxf(0.0, float(b.reported_cd[i]) - sim.time)
	if b.cd_disc_until >= sim.time and b.cd_disc[i] >= 0.0 and b.cd_disc_t > b.cd_last[i]:
		return maxf(0.0, b.cd_disc[i] - sim.time - b.cd_cdr[i])
	if b.cd_last[i] < -100.0:
		return 0.0
	var a: Defs.AbilityDef = b.def.abilities[i]
	return maxf(0.0, b.cd_last[i] + a.cooldown - b.cd_cdr[i] - sim.time)


func _resource_ok(b: EnemyBelief, a: Defs.AbilityDef) -> bool:
	var c: = a.condition
	if c.has("selfResource"):
		var key: = str(c.selfResource.key)
		var need: = float(c.selfResource.min)
		match key:
			"fish":
				return fish_now(b, sim.time) >= need
			"rage":
				return rage_now(b, sim.time) >= need
			"shards":
				return b.shards >= need
			"healBank":
				return b.heal_bank >= need
			"fuel":
				if not (bool(c.selfResource.get("originFreeInOverdrive", false)) and overdrive_believed(b)) and fuel_now(b) < need:
					return false
	# V2 war_machine: overdrive locks every slot but S1 (public status).
	if b.def.id == "war_machine" and a.slot != 1 and overdrive_believed(b):
		return false
	return true


# Fisherman inventory from the public 8 s grant clock: a grant at two fish is
# eaten by the engine (overflow), so inventory stays at two (audit D8).
func fish_now(b: EnemyBelief, t: float) -> float:
	var guard: int = 0
	while b.fish_next <= t + 1e-06 and guard < 64:
		b.fish = minf(2.0, b.fish + 1.0)
		b.fish_next += 8.0
		guard += 1
	return b.fish


func _fish_consume(b: EnemyBelief, t: float) -> void:
	fish_now(b, t)
	b.fish = maxf(0.0, b.fish - 1.0)
	b.fish_used += 1


# Observed damage on an enemy nitro. Health damage from someone else grants
# rage (65 per stack); any damage restarts the 4 s decay delay (audit D9).
func _rage_hit(b: EnemyBelief, t: float, hp_amount: float) -> void:
	rage_now(b, t)
	b.rage_damage_t = t
	if hp_amount > 0.0:
		var energy: float = b.rage_rem + hp_amount
		var n: float = floorf((energy + 1e-09) / 65.0)
		b.rage_rem = energy - n * 65.0
		b.rage = minf(12.0, b.rage + n)
		b.rage_decay_next = t + 5.0
	else:
		b.rage_decay_next = maxf(b.rage_decay_next if b.rage_decay_next < INF else 0.0, t + 4.0)


func rage_now(b: EnemyBelief, t: float) -> float:
	var guard: int = 0
	while b.rage > 0.0 and t + 1e-06 >= b.rage_decay_next and guard < 16:
		b.rage = maxf(0.0, b.rage - 1.0)
		b.rage_decay_next += 1.0
		guard += 1
	return b.rage


# ------------------------------------------------------------------ V2 fuel
# War machine fuel belief (DESIGN_V2 §2.3 정보 공정성): +1 per observed basic
# hit (HP or shield) on an observed enemy hero or non-structure summon while
# the tank is believed attached, minus observed spends. Never read from the
# unit's resources.

const TANK_RESPAWN: = 10.0


func fuel_now(b: EnemyBelief) -> float:
	if b.fuel_pending > 0.0 and sim.time + 1e-06 >= b.fuel_pending_at:
		b.fuel = maxf(0.0, b.fuel - b.fuel_pending)
		b.fuel_pending = 0.0
		b.fuel_pending_at = INF
	return b.fuel


func overdrive_believed(b: EnemyBelief) -> bool:
	if b.dead:
		return false
	return b.overdrive_until > sim.time or (b.visible and b.has_status("overdrive"))


func tank_down(b: EnemyBelief) -> bool:
	return b.tank_down_until > sim.time


func _fuel_reset(b: EnemyBelief) -> void:
	b.fuel = 0.0
	b.fuel_pending = 0.0
	b.fuel_pending_at = INF
	b.tank_hp = -1.0
	b.tank_seen_t = -999.0
	b.tank_down_until = -1.0
	b.overdrive_until = -1.0


func _fuel_rule(b: EnemyBelief) -> Dictionary:
	return b.def.rule("fuel_tank") if b.def.has_rule("fuel_tank") else {}


func _fuel_basic(b: EnemyBelief, g: int, ev: Dictionary) -> void:
	var r: Dictionary = _fuel_rule(b)
	if r.is_empty() or tank_down(b):
		return
	if float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0)) <= 0.0:
		return
	var victim: BUnit = sim.u_at(g)
	if victim == null or sim.eteam(victim) == sim.eteam(sim.u_at(b.idx)):
		return
	if not victim.is_hero and victim.structure:
		return
	fuel_now(b)
	b.fuel = minf(float(r.get("max", 10.0)), b.fuel + float(r.get("perBasic", 1.0)))


# An observed cast: the booster pays at once (free in overdrive), a charge
# (N read from its public cast time) or genocide pays when its windup ends.
func _fuel_cast(b: EnemyBelief, a: Defs.AbilityDef, ev: Dictionary) -> void:
	var cost: float = 0.0
	for f in a.effects:
		if str(f.get("type", "")) == "consume_resource" and str(f.get("key", "")) == "fuel":
			cost += float(f.get("amount", 1.0))
	var ch: Dictionary = a.flag("originCharge", {})
	if not ch.is_empty():
		var per_step: float = maxf(0.01, float(ch.get("perStep", 0.3)))
		var cast_t: float = float(ev.get("cast_time", a.cast_time))
		var n: int = int(ch.get("min", 2)) + int(roundf((cast_t - float(ch.get("base", a.cast_time))) / per_step))
		cost = float(clampi(n, int(ch.get("min", 2)), int(ch.get("max", 6))))
	if cost <= 0.0:
		return
	if bool(a.flag("originFreeInOverdrive", false)) and overdrive_believed(b):
		return
	fuel_now(b)
	var cast_time: float = float(ev.get("cast_time", a.cast_time))
	if cast_time <= 0.1:
		b.fuel = maxf(0.0, b.fuel - cost)
		return
	b.fuel_pending = cost
	b.fuel_pending_at = float(ev.t) + cast_time


func _fuel_cancel(b: EnemyBelief) -> void:
	if b.fuel_pending > 0.0 and sim.time < b.fuel_pending_at:
		b.fuel_pending = 0.0
		b.fuel_pending_at = INF


func _tank_seen(tank: EnemyBelief, t: float) -> void:
	var owner: EnemyBelief = enemies.get(tank.owner_idx)
	if owner == null:
		return
	owner.tank_hp = tank.hp
	owner.tank_max_hp = tank.max_hp
	owner.tank_seen_t = t
	owner.tank_down_until = -1.0


func best_guess_pos(idx: int) -> Vector2:
	var b: EnemyBelief = enemies.get(idx)
	return b.pos if b else sim.arena.center()


func alive_enemies() -> Array:
	var out: Array = []
	for b in enemies.values():
		if not (b as EnemyBelief).dead:
			out.append(b)
	return out


func visible_enemies(include_entities: bool = false) -> Array:
	var out: Array = []
	for b in enemies.values():
		var eb: EnemyBelief = b
		if eb.visible and not eb.dead and not eb.controlled_by_us:
			out.append(eb)
	if include_entities:
		for b in entities.values():
			if (b as EnemyBelief).visible and not (b as EnemyBelief).untargetable:
				out.append(b)
	return out


# --- V2 scale (B-PERF) ---
# Scale battles only (BattleSim.scale_lod; never the 12-player deathmatch or
# the team modes): a belief about an enemy unseen for FREEZE_UNSEEN s whose
# believed position is FREEZE_RANGE px from every body of ours stops
# simulating its particles. Its uncertainty grows on a formula instead (a
# uniform disc of radius FREEZE_RATE x move speed x frozen time, combined with
# the spread it had), and when it comes back into range or is seen again the
# particles are scattered over that disc and the filter resumes.
const FREEZE_UNSEEN: = 3.0
const FREEZE_RANGE: = 1600.0
const FREEZE_RATE: = 0.5
const FREEZE_REACH_MAX: = 2400.0
var frozen_steps: int = 0


func _far_from_all(ours: Array, p: Vector2, reach: float) -> bool:
	var r2: float = reach * reach
	for a in ours:
		if (a as BUnit).pos.distance_squared_to(p) < r2:
			return false
	return true


func _freeze_reach(eb: EnemyBelief) -> float:
	return minf(FREEZE_REACH_MAX, eb.def.stat("moveSpeed") * maxf(0.0, sim.time - eb.frozen_at) * FREEZE_RATE)


func _freeze_step(eb: EnemyBelief, _dt: float) -> void:
	frozen_steps += 1
	if eb.frozen_at < 0.0:
		eb.frozen_at = sim.time
		eb.frozen_spread = eb.spread
		eb.prop_debt = 0.0
	# RMS distance of a uniform disc of radius R is R / sqrt(2).
	var grown: float = _freeze_reach(eb) * 0.7071
	eb.spread = sqrt(eb.frozen_spread * eb.frozen_spread + grown * grown)
	var age: float = sim.time - eb.last_seen_t
	eb.confidence = clampf((1.0 - eb.spread / 320.0) * exp(-age * 0.06), 0.05, 0.95)


func _thaw(eb: EnemyBelief) -> void:
	var reach: float = _freeze_reach(eb)
	eb.frozen_at = -1.0
	eb.prop_debt = 0.0
	# Weights are kept (sightings and hits while frozen still reweighted them).
	for i in n_part:
		var off: Vector2 = Vector2.from_angle(rng.randf() * TAU) * reach * sqrt(rng.randf())
		eb.particles[i] = sim.arena.resolve_circle(eb.particles[i] + off, eb.radius)
	_normalize(eb)
	_estimate(eb)


# --- V2 scale (B-PERF2) ---
# Scale battles only: an unseen belief with none of our bodies within 760 px
# (and not frozen) advances in steps of SCALE_FAR_STEP s instead of 0.6 s; its
# particles are diffuse at that range and the step is bounded by move speed.
const SCALE_FAR_STEP: = 1.2
# Scale battles advance the particle filter at most every SCALE_PROP_INTERVAL
# s (PROP_INTERVAL elsewhere): a team in contact observes every 0.1 s, so its
# hidden beliefs step on every other observe (0.19 absorbs clock rounding).
const SCALE_PROP_INTERVAL: = 0.19
# Hero beliefs the last observe() marked visible, in hero order. A belief turns
# visible only there (ingest only clears the flag), so every currently visible
# hero belief is in this list; readers re-check the flags.
var vis_heroes: Array[EnemyBelief] = []
# observe / observe_fast / ingest / _propagate ask the simulator through
# sim.ai_allies, ai_eteam and ai_is_seen. Inside a brain's pre_tick in a scale
# battle these read the simulator's pre-tick snapshot (one status scan per body
# per tick instead of one per brain and call); anywhere else they are exactly
# allies_of, eteam and is_seen. The answers are the same either way.
