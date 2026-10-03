class_name DominationMode
extends RefCounted

# Objective state is public. Occupant identities and counts remain internal.
const RESPAWN_DELAY := 12.0
const SPAWN_PROTECTION := 2.0
const SCORE_RATE := 1.0
var sim: BattleSim
var points: Array[Dictionary] = []
var scores: Array[float] = [0.0, 0.0]
var heal_zones: Array[Dictionary] = []
var respawn_at: Dictionary = {}
var target_score: float = 300.0
var capture_time: float = 5.0
var history: Array = [[0.0, 0.0, 0.0]]
var _pending_cleanup: Dictionary = {}
var _next_score_event: float = 1.0


func _init(s: BattleSim) -> void:
	sim = s
	if not sim.is_control_mode():
		return
	for raw in sim.arena.control_points:
		points.append({"id": str(raw.id), "label": str(raw.get("label", raw.id)), "center": raw.center,
			"radius": maxf(1.0, float(raw.get("radius", 88.0))), "owner": -1, "progress": 0.0,
			"contested": false, "_capture_team": -1, "_elapsed": 0.0})
	for raw in sim.arena.heal_zones:
		heal_zones.append({"id": str(raw.id), "center": raw.center,
			"radius": maxf(1.0, float(raw.get("radius", 52.0))), "ready_at": 0.0,
			"cooldown": maxf(0.0, float(raw.get("cooldown", 25.0))),
			"heal_ratio": clampf(float(raw.get("heal_ratio", 0.35)), 0.0, 1.0)})


func public_points() -> Array:
	var out: Array = []
	for p in points:
		out.append({"id": p.id, "label": p.label, "center": p.center, "radius": p.radius,
			"owner": p.owner, "progress": p.progress, "contested": p.contested})
	return out


func eligible(u: BUnit) -> bool:
	return u.is_hero and u.alive and u.chamber.is_empty() and not sim.has_status(u, &"untargetable") and not sim.has_status(u, &"spawn_protection")


func _occupants(center: Vector2, radius: float) -> Array:
	var teams: Array = [[], []]
	for u in sim.heroes:
		if eligible(u) and u.pos.distance_squared_to(center) <= radius * radius:
			teams[sim.eteam(u)].append(u)
	return teams


func pre_tick() -> void:
	# Death may happen inside projectile/zone iteration. A second cleanup at the
	# next tick removes anything that that already-running iterator appended.
	for idx in _pending_cleanup.keys():
		_clean_life(sim.u_at(int(idx)))
	_pending_cleanup.clear()
	for idx in respawn_at.keys():
		if sim.time + 0.000001 >= float(respawn_at[idx]):
			_respawn(sim.u_at(int(idx)))


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	for p in points:
		_update_point(p, dt)
	for z in heal_zones:
		_update_heal_zone(z)
	if sim.time + 0.000001 >= _next_score_event:
		history.append([sim.time, scores[0], scores[1]])
		sim.emit("CONTROL_SCORE", -1, -1, {"scores": scores.duplicate(), "target_score": target_score})
		_next_score_event = floorf(sim.time + 0.000001) + 1.0


func _update_point(p: Dictionary, dt: float) -> void:
	var occupants: Array = _occupants(p.center, float(p.radius))
	var both: bool = not occupants[0].is_empty() and not occupants[1].is_empty()
	if both != bool(p.contested):
		p.contested = both
		sim.emit("CONTROL_CONTESTED", -1, -1, {"point_id": p.id, "contested": both})
	if both:
		return
	var team: int = 0 if not occupants[0].is_empty() else (1 if not occupants[1].is_empty() else -1)
	var owner: int = int(p.owner)
	# The owner scores until neutralization, including while empty. A contest
	# pauses progress and scoring; leaving a point resets unfinished progress.
	if team < 0 or team == owner:
		if owner >= 0: scores[owner] = minf(target_score, scores[owner] + dt * SCORE_RATE)
		_reset_progress(p)
		return
	if int(p._capture_team) != team:
		p._capture_team = team
		p._elapsed = 0.0
	var used: float = minf(dt, maxf(0.0, capture_time - float(p._elapsed)))
	if owner >= 0: scores[owner] = minf(target_score, scores[owner] + used * SCORE_RATE)
	p._elapsed = float(p._elapsed) + used
	p.progress = (float(p._elapsed) / capture_time) * (-1.0 if team == 0 else 1.0)
	for u: BUnit in occupants[team]:
		u.st_capture_time += used
	if float(p._elapsed) + 0.000001 < capture_time:
		return
	if owner >= 0:
		p.owner = -1
		sim.emit("CONTROL_NEUTRALIZED", -1, -1, {"point_id": p.id, "team": team, "previous_owner": owner, "scores": scores.duplicate()})
	else:
		p.owner = team
		for u: BUnit in occupants[team]:
			u.st_captures += 1
		sim.emit("CONTROL_CAPTURED", -1, -1, {"point_id": p.id, "team": team, "owner": team, "scores": scores.duplicate()})
	_reset_progress(p)
	# Carry the fractional remainder through the neutralization/capture boundary.
	if dt - used > 0.000001:
		_update_point(p, dt - used)


func _reset_progress(p: Dictionary) -> void:
	p._capture_team = -1
	p._elapsed = 0.0
	p.progress = 0.0


func _update_heal_zone(z: Dictionary) -> void:
	if sim.time + 0.000001 < float(z.ready_at):
		return
	var occupants: Array = _occupants(z.center, float(z.radius))
	if not occupants[0].is_empty() and not occupants[1].is_empty():
		return
	var team: int = 0 if not occupants[0].is_empty() else (1 if not occupants[1].is_empty() else -1)
	if team < 0:
		return
	var selected: BUnit = null
	var lowest: float = 0.85
	for u: BUnit in occupants[team]:
		var ratio: float = u.hp / maxf(1.0, sim.max_hp(u))
		if ratio < lowest - 0.000001:
			selected = u
			lowest = ratio
	if selected == null:
		return
	var heal: Dictionary = sim.apply_heal(selected, selected,
		{"base": sim.max_hp(selected) * float(z.heal_ratio)}, {"source_type": "HEAL_ZONE", "proc": true})
	var amount: float = maxf(0.0, float(heal.effective))
	if amount <= 0.0:
		return
	selected.st_zone_healing += amount
	z.ready_at = sim.time + float(z.cooldown)
	sim.emit("HEAL_ZONE_USED", selected.idx, selected.idx,
		{"zone_id": z.id, "team": team, "amount": amount, "ready_at": z.ready_at})


func check_end() -> void:
	if scores[0] >= target_score - 0.000001 or scores[1] >= target_score - 0.000001:
		_finish("control_score")
	elif sim.time >= sim.max_time:
		_finish("control_time_limit")


func _finish(reason: String) -> void:
	var winning_team: int = 2 if absf(scores[0] - scores[1]) < 0.000001 else (0 if scores[0] > scores[1] else 1)
	if history.is_empty() or absf(float(history[-1][0]) - sim.time) > 0.000001:
		history.append([sim.time, scores[0], scores[1]])
	sim.finish(winning_team, reason)


func break_protection(u: BUnit) -> void:
	sim.remove_statuses_where(u, func(st): return bool(st.extra.get("respawn_protection", false)))


func hostile_ability(a: Defs.AbilityDef) -> bool:
	if a.target not in ["self", "ally", "position_ally"]:
		return true
	if a.action in ["fakeNews", "diversion", "glide", "rootGarden", "thornGarden", "detonate"]:
		return true
	return _hostile_effects(a.effects)


func _hostile_effects(effects: Array) -> bool:
	for f in effects:
		var kind: String = str(f.get("type", ""))
		if kind in ["damage", "execute", "dot", "mark", "summon", "displace", "steal_stat"]:
			return true
		if kind == "status" and sim.is_cc_type(StringName(str(f.get("status", "")))):
			return true
		if kind == "buff" and bool(f.get("originContact", false)):
			return true
		if f.has("effects") and _hostile_effects(f.effects):
			return true
	return false


func on_death(u: BUnit) -> void:
	if respawn_at.has(u.idx):
		return
	respawn_at[u.idx] = sim.time + RESPAWN_DELAY
	_clean_life(u)
	_pending_cleanup[u.idx] = true
	sim.emit("RESPAWN_SCHEDULED", u.idx, u.idx,
		{"team": u.team, "respawn_at": respawn_at[u.idx], "life_id": u.life_id})


func _clean_life(dead: BUnit) -> void:
	if dead == null:
		return
	var owned: Dictionary = {dead.idx: true}
	# Include nested summons. Stable unit indices are never removed from units.
	for _pass in 4:
		for entity in sim.entities:
			if owned.has(entity.owner_idx):
				owned[entity.idx] = true
	var living_entities: Array[BUnit] = []
	for entity in sim.entities:
		if owned.has(entity.idx):
			if entity.alive:
				sim.emit("SUMMON_EXPIRED", dead.idx, entity.idx, {"kind": entity.kind, "reason": "owner_died"})
			entity.alive = false
			entity.hp = 0.0
			entity.death_time = sim.time
			entity.end_time = sim.time
			entity.action = null
			entity.motion = null
		else:
			living_entities.append(entity)
	sim.entities = living_entities
	for u in sim.units:
		var removed_control: bool = false
		var status_keep: Array[ST.Status] = []
		for st in u.statuses:
			if u == dead or owned.has(st.source_idx):
				removed_control = removed_control or sim.is_cc_type(st.type)
				if st.type == &"nexus_seal":
					for slot in st.extra.get("slots", []): u.sealed.erase(slot)
			else:
				status_keep.append(st)
		u.statuses = status_keep
		var buff_keep: Array[ST.Buff] = []
		for buff in u.buffs:
			if u != dead and not owned.has(buff.source_idx): buff_keep.append(buff)
		u.buffs = buff_keep
		var shield_keep: Array[ST.Shield] = []
		for shield in u.shields:
			if u != dead and not owned.has(shield.source_idx): shield_keep.append(shield)
		u.shields = shield_keep
		if u.motion and (owned.has(u.motion.source_idx) or u.motion.target_idx == dead.idx):
			u.motion = null
			u.vel = Vector2.ZERO
		if removed_control: sim.reset_commitment(u, "source_life_ended")
		if u.alive: u.hp = minf(u.hp, sim.max_hp(u))
	var projectile_keep: Array[ST.Projectile] = []
	for p in sim.proj.list:
		if owned.has(p.source_idx) or owned.has(p.shooter_idx) or p.target_idx == dead.idx:
			if not p.dead: sim.proj._end(p, "life_ended")
		else:
			projectile_keep.append(p)
	sim.proj.list = projectile_keep
	var zone_keep: Array[ST.Zone] = []
	for z in sim.zones.list:
		if owned.has(z.source_idx):
			z.finished = true
			z.end = sim.time
		else:
			zone_keep.append(z)
	sim.zones.list = zone_keep
	sim.delayed = sim.delayed.filter(func(job): return not owned.has(int(job.get("source", -1))) and int(job.get("target", -1)) != dead.idx)
	sim.gardens = sim.gardens.filter(func(g): return not owned.has(int(g.get("source", -1))))
	sim.portal_pairs = sim.portal_pairs.filter(func(pair): return not owned.has(int(pair.get("source", -1))))
	for chamber in sim.chambers:
		if owned.has(int(chamber.source)) or int(chamber.target) == dead.idx:
			sim.kits._end_chamber(chamber, false)
	sim.chambers = sim.chambers.filter(func(chamber): return not bool(chamber.ended))
	for tg in sim.telegraphs:
		if owned.has(int(tg.get("source", -1))): tg.cancelled = true
	sim.cleanup_telegraphs()
	for team in sim.team_count:
		for idx in sim.warfare.false_reports[team].keys():
			var report: Dictionary = sim.warfare.false_reports[team][idx]
			if int(idx) == dead.idx or owned.has(int(report.source)):
				sim.warfare.false_reports[team].erase(idx)
	sim.warfare.on_death(dead)
	dead.sealed.clear()
	dead.chamber = ""


# Reworked maps put teams top/bottom, on diagonals or on split entrances, so
# a respawned hero faces the enemy team's spawn centroid (V1.5.3), not a
# fixed left/right. Falls back to the arena centre, then to the old sides.
func respawn_facing(u: BUnit) -> Vector2:
	# One rule for the opening and every respawn (engine follow-up):
	# BattleSim.spawn_facing (enemy spawn centroid, arena centre in FFA).
	return sim.spawn_facing(u.team, u.pos)


func _respawn(u: BUnit) -> void:
	if u == null:
		return
	_clean_life(u)
	respawn_at.erase(u.idx)
	u.life_id += 1
	u.alive = true
	u.death_time = -1.0
	u.spawn_time = sim.time
	u.end_time = INF
	u.pos = sim.arena.resolve_circle(u.spawn_pos, u.base_radius)
	u.prev_pos = u.pos
	u.vel = Vector2.ZERO
	u.facing = respawn_facing(u)
	u.action = null
	u.motion = null
	u.command = {}
	u.next_decision_at = sim.time + 0.1
	u.last_damage_time = -999.0
	u.last_combat_time = -999.0
	u.portal_until = 0.0
	u.resources.clear()
	u.ks.clear()
	sim.kits.init_unit(u)
	u.hp = sim.max_hp(u)
	# Cooldowns retain their absolute deadlines: dying cannot reset an ultimate.
	for status: StringName in [&"spawn_protection", &"invulnerable"]:
		sim.push_status(u, status, u.idx, SPAWN_PROTECTION, {"respawn_protection": true})
	sim.emit("HERO_RESPAWNED", u.idx, u.idx,
		{"team": u.team, "life_id": u.life_id, "protected_until": sim.time + SPAWN_PROTECTION})
