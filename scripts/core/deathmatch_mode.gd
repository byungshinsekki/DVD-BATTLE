class_name DeathmatchMode
extends RefCounted

# Free-for-all: every participant is its own team. Kills score, deaths respawn
# after a short delay at the safest spawn point, and up to 30 procedurally
# placed items lie on the field. Item positions and the scoreboard are public;
# which items a hero holds is visible only as far as the hero is seen.

const RESPAWN_DELAY := 6.0
const SPAWN_PROTECTION := 2.0
const MAX_FIELD_ITEMS := 30
const SLOTS := 3
const PICK_RADIUS := 24.0
const ASSIST_WINDOW := 8.0
# Free-for-all fights are one against one far more often than team fights,
# where focus fire ends them; hero-on-hero damage is raised so duels resolve
# instead of trading until both walk away to regenerate.
const BRAWL_DAMAGE := 1.3
# Two or three players: play on the inner region (about 2400x1500 of the
# 3600x2200 map) and respawn about 600 px from the nearest opponent.
const SMALL_MATCH_PLAYERS := 3
const SMALL_INNER_FRACTION := 0.68
const SMALL_RESPAWN_CAP := 600.0

var sim: BattleSim
var kill_target: int = 15
var kills: PackedInt32Array = PackedInt32Array()
var deaths: PackedInt32Array = PackedInt32Array()
var assists: PackedInt32Array = PackedInt32Array()
var streak: PackedInt32Array = PackedInt32Array()
var best_streak: PackedInt32Array = PackedInt32Array()
var items_picked: PackedInt32Array = PackedInt32Array()
var respawn_at: Dictionary = {}
var field: Array = []          # {"uid", "item", "pos", "t", "dropped"}
var inventory: Dictionary = {} # hero idx -> Array of item ids
var state: Dictionary = {}     # hero idx -> item runtime state
var recent_hits: Dictionary = {} # victim idx -> {attacker hero idx: time}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var next_item_at: float = 0.0
var uid_seq: int = 0
var declined: Dictionary = {}  # "hero:uid" -> time of last refusal
var kill_feed: Array = []
var kill_log: Array = []       # [time, killer team (-1 none), victim team] for the whole match
var winner_order: Array = []
var _pending_cleanup: Dictionary = {}
var _last_update_second: int = -1
var player_count: int = 0
var small_rules: bool = true


func _init(s: BattleSim) -> void:
	sim = s
	rng.seed = s.seed_value * 7919 + 101
	kill_target = clampi(int(s.cfg.get("kill_target", 15)), 1, 200)
	# Developer comparison: cfg "dm153" = false replays the V1.5.2 spawn rules.
	small_rules = bool(s.cfg.get("dm153", true))


func dispose() -> void:
	sim = null


func make_players(ids: Array) -> void:
	var n: int = ids.size()
	player_count = n
	for arr in [kills, deaths, assists, streak, best_streak, items_picked]:
		arr.resize(n)
		arr.fill(0)
	var spawns: Array = spawn_candidates()
	# Spread starting positions: greedy farthest point from a seeded first pick.
	var chosen: Array = []
	if not spawns.is_empty():
		chosen.append(rng.randi_range(0, spawns.size() - 1))
		while chosen.size() < mini(n, spawns.size()):
			var best: int = -1
			var best_d: float = -1.0
			for k in spawns.size():
				if chosen.has(k):
					continue
				var d: float = INF
				for c in chosen:
					d = minf(d, (spawns[k] as Vector2).distance_to(spawns[c]))
				if d > best_d:
					best_d = d
					best = k
			chosen.append(best)
	for i in n:
		var d: Defs.CharDef = DB.char_def(str(ids[i]))
		if d == null:
			d = DB.char_def("swordsman")
		var p: Vector2 = spawns[chosen[i % chosen.size()]] if not chosen.is_empty() else sim.arena.center()
		p = sim.arena.resolve_circle(p, d.stat("bodyRadius"))
		var u: BUnit = sim._new_unit(d, i, 0, p)
		sim.heroes.append(u)
		inventory[u.idx] = []
		state[u.idx] = {}
	# Opening supply: about two thirds of the field cap, spread out.
	var opening: int = mini(MAX_FIELD_ITEMS, 12 + n * 2)
	for k in opening:
		_spawn_item(true)
	next_item_at = 4.0
	# Build the path grids for every body size now: on this large map a grid
	# takes tens of milliseconds and would otherwise stall the match the
	# first time a hero of that size (or a shrinking giant) needs a route.
	# V2 (B-PERF): every bucket the roster needs, not a fixed 12/18/26 (a
	# full-health giant, radius 27.6, needs bucket 28 and built it mid-match).
	for b in sim.nav_buckets():
		Navigator.for_sim(sim, float(b))


func team_score(team: int) -> int:
	return kills[team] if team >= 0 and team < kills.size() else 0


# ---------------------------------------------------------------- lifecycle

func pre_tick() -> void:
	for idx in _pending_cleanup.keys():
		_clean_life(sim.u_at(int(idx)))
	_pending_cleanup.clear()
	for idx in respawn_at.keys():
		if sim.time + 0.000001 >= float(respawn_at[idx]):
			_respawn(sim.u_at(int(idx)))


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	if sim.time + 0.000001 >= next_item_at:
		if field.size() < MAX_FIELD_ITEMS:
			_spawn_item(false)
		next_item_at = sim.time + clampf(9.0 - sim.heroes.size() * 0.45, 3.0, 9.0) + rng.randf() * 2.0
	_pickups()
	var second: int = int(floor(sim.time * 4.0))
	if second != _last_update_second:
		_last_update_second = second
		_quarter_second_effects()


func check_end() -> void:
	for t in kills.size():
		if kills[t] >= kill_target:
			_finish("deathmatch_kills")
			return
	if sim.time >= sim.max_time:
		_finish("deathmatch_time")


func ranking() -> Array:
	var order: Array = []
	for u in sim.heroes:
		order.append(u)
	order.sort_custom(func(a: BUnit, b: BUnit):
		if kills[a.team] != kills[b.team]: return kills[a.team] > kills[b.team]
		if deaths[a.team] != deaths[b.team]: return deaths[a.team] < deaths[b.team]
		if absf(a.st_damage - b.st_damage) > 0.001: return a.st_damage > b.st_damage
		return a.idx < b.idx)
	return order


func _finish(reason: String) -> void:
	winner_order = []
	for u in ranking():
		winner_order.append(u.team)
	sim.finish(int(winner_order[0]) if not winner_order.is_empty() else 0, reason)


func result() -> Dictionary:
	var rows: Array = []
	var rank: int = 1
	for u in ranking():
		rows.append({"rank": rank, "idx": u.idx, "team": u.team, "id": u.def.id, "name": u.name,
			"kills": kills[u.team], "deaths": deaths[u.team], "assists": assists[u.team],
			"best_streak": best_streak[u.team], "items": items_picked[u.team], "damage": u.st_damage,
			"held": (inventory.get(u.idx, []) as Array).duplicate()})
		rank += 1
	return {"kill_target": kill_target, "ranking": rows, "field_items": field.size(), "kill_log": kill_log.duplicate(true),
		"players": sim.heroes.size(), "preset": str(sim.arena.data.get("preset", ""))}


func break_protection(u: BUnit) -> void:
	sim.remove_statuses_where(u, func(st): return bool(st.extra.get("respawn_protection", false)))


func _credited_hero(s: BUnit) -> BUnit:
	var guard: int = 0
	while s != null and not s.is_hero and guard < 6:
		s = sim.u_at(s.owner_idx)
		guard += 1
	return s if s != null and s.is_hero else null


func on_death(t: BUnit, s: BUnit, _ctx: Dictionary) -> void:
	if not t.is_hero or respawn_at.has(t.idx):
		return
	var killer: BUnit = _credited_hero(s)
	var assisters: Array = []
	for attacker_idx in (recent_hits.get(t.idx, {}) as Dictionary):
		var when: float = float(recent_hits[t.idx][attacker_idx])
		if sim.time - when <= ASSIST_WINDOW and (killer == null or int(attacker_idx) != killer.idx) and int(attacker_idx) != t.idx:
			assisters.append(int(attacker_idx))
	recent_hits.erase(t.idx)
	deaths[t.team] += 1
	streak[t.team] = 0
	if killer and killer != t:
		kills[killer.team] += 1
		streak[killer.team] += 1
		best_streak[killer.team] = maxi(best_streak[killer.team], streak[killer.team])
		_on_kill_items(killer)
	for a_idx in assisters:
		var a: BUnit = sim.u_at(a_idx)
		if a and a.is_hero:
			assists[a.team] += 1
	var entry: Dictionary = {"t": sim.time, "killer": killer.idx if killer and killer != t else -1, "victim": t.idx,
		"assists": assisters, "streak": streak[killer.team] if killer and killer != t else 0,
		"score": kills[killer.team] if killer and killer != t else 0}
	kill_feed.append(entry)
	kill_log.append([sim.time, killer.team if killer and killer != t else -1, t.team])
	if kill_feed.size() > 40:
		kill_feed.pop_front()
	sim.emit("DM_KILL", killer.idx if killer else -1, t.idx, entry.duplicate())
	_drop_on_death(t)
	inventory[t.idx] = []
	state[t.idx] = {}
	respawn_at[t.idx] = sim.time + RESPAWN_DELAY
	_clean_life(t)
	_pending_cleanup[t.idx] = true
	sim.emit("RESPAWN_SCHEDULED", t.idx, t.idx, {"team": t.team, "respawn_at": respawn_at[t.idx], "life_id": t.life_id})


func choose_spawn(u: BUnit) -> Vector2:
	var best: Vector2 = u.spawn_pos
	var best_v: float = -INF
	var few: bool = small_match()
	var cands: Array = spawn_candidates()
	for p in cands:
		var q: Vector2 = p
		var near: float = INF
		for o in sim.heroes:
			if o == u or not o.alive:
				continue
			near = minf(near, q.distance_to(o.pos))
		# Anything beyond 850 px of every opponent is safe enough; among those
		# the pick is random so a respawn does not always mean a long walk back.
		var v: float = minf(near, 850.0) + rng.randf() * 120.0
		if few:
			# Two or three players spend most of a match searching for each
			# other: respawn about 600 px out of reach, not across the map.
			v = minf(near, SMALL_RESPAWN_CAP) + rng.randf() * 120.0 - maxf(0.0, near - SMALL_RESPAWN_CAP - 400.0) * 0.15
		if v > best_v:
			best_v = v
			best = q
	return best


# Two or three players (V1.5.3, audit DM-3): the match is played on the inner
# part of the map, so the opening and every respawn start closer together.
func small_match() -> bool:
	return small_rules and maxi(player_count, sim.heroes.size()) <= SMALL_MATCH_PLAYERS


# Spawn points in play: the whole list, or for a small match the ones inside
# the inner region (all of them if fewer than four qualify).
func spawn_candidates() -> Array:
	var spawns: Array = sim.arena.ffa_spawns
	if not small_match() or spawns.size() < 4:
		return spawns
	var inner: Rect2 = inner_region()
	var out: Array = []
	for p in spawns:
		if inner.has_point(p):
			out.append(p)
	return out if out.size() >= 4 else spawns


func inner_region() -> Rect2:
	var w: float = sim.arena.max_x - sim.arena.min_x
	var h: float = sim.arena.max_y - sim.arena.min_y
	var iw: float = w * SMALL_INNER_FRACTION
	var ih: float = h * SMALL_INNER_FRACTION
	return Rect2(sim.arena.min_x + (w - iw) * 0.5, sim.arena.min_y + (h - ih) * 0.5, iw, ih)


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
	u.pos = sim.arena.resolve_circle(choose_spawn(u), u.base_radius)
	u.spawn_pos = u.pos
	u.prev_pos = u.pos
	u.vel = Vector2.ZERO
	u.facing = (sim.arena.center() - u.pos).normalized() if sim.arena.center().distance_to(u.pos) > 1.0 else Vector2.RIGHT
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
	for status: StringName in [&"spawn_protection", &"invulnerable"]:
		sim.push_status(u, status, u.idx, SPAWN_PROTECTION, {"respawn_protection": true})
	sim.emit("HERO_RESPAWNED", u.idx, u.idx, {"team": u.team, "life_id": u.life_id, "protected_until": sim.time + SPAWN_PROTECTION, "pos": u.pos})


func _clean_life(dead: BUnit) -> void:
	if dead == null:
		return
	var owned: Dictionary = {dead.idx: true}
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


# ---------------------------------------------------------------- items

func _spawn_item(opening: bool) -> Dictionary:
	var item_id: String = _roll_item()
	var pos: Vector2 = _pick_spot(opening)
	if pos == Vector2.INF:
		return {}
	uid_seq += 1
	var entry: Dictionary = {"uid": uid_seq, "item": item_id, "pos": pos, "t": sim.time, "dropped": -1}
	field.append(entry)
	sim.emit("DM_ITEM_SPAWNED", -1, -1, {"uid": uid_seq, "item": item_id, "pos": pos, "rarity": ItemDefs.rarity_of(item_id), "silent": opening})
	return entry


func _roll_item() -> String:
	var total: float = 0.0
	for w in ItemDefs.RARITY_WEIGHTS:
		total += float(w)
	var roll: float = rng.randf() * total
	var rarity: int = 0
	for r in ItemDefs.RARITY_WEIGHTS.size():
		roll -= float(ItemDefs.RARITY_WEIGHTS[r])
		if roll <= 0.0:
			rarity = r
			break
	var pool: Array = ItemDefs.by_rarity(rarity)
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func _pick_spot(opening: bool) -> Vector2:
	var spots: Array = sim.arena.item_spots
	if spots.is_empty():
		return Vector2.INF
	for attempt in 24:
		var spot: Dictionary = spots[rng.randi_range(0, spots.size() - 1)]
		var p: Vector2 = spot.pos
		var ok: bool = true
		for it in field:
			if (it.pos as Vector2).distance_to(p) < 150.0:
				ok = false
				break
		if ok and not opening:
			for u in sim.heroes:
				if u.alive and u.pos.distance_to(p) < 260.0:
					ok = false
					break
		if ok:
			var jitter: Vector2 = Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-24.0, 24.0))
			return sim.arena.resolve_circle(p + jitter, 14.0)
	return Vector2.INF


func held(u: BUnit) -> Array:
	return inventory.get(u.idx, [])


func has_item(u: BUnit, item_id: String) -> bool:
	return (inventory.get(u.idx, []) as Array).has(item_id)


func _items_with(u: BUnit, key: String) -> Array:
	var out: Array = []
	for id in inventory.get(u.idx, []):
		var d: Dictionary = ItemDefs.get_def(str(id))
		if d.has(key):
			out.append(d[key])
	return out


func _pickups() -> void:
	if field.is_empty():
		return
	for u in sim.heroes:
		if not u.alive or u.chamber != "" or u.motion != null:
			continue
		var reach: float = PICK_RADIUS + sim.radius(u)
		for it in field.duplicate():
			if (it.pos as Vector2).distance_to(u.pos) > reach:
				continue
			var key: String = "%d:%d" % [u.idx, int(it.uid)]
			if declined.has(key) and sim.time - float(declined[key]) < 4.0:
				continue
			var choice: Dictionary = _decide_pickup(u, it)
			if not bool(choice.get("take", false)):
				declined[key] = sim.time
				sim.emit("DM_ITEM_SKIPPED", u.idx, u.idx, {"uid": it.uid, "item": it.item, "reason": str(choice.get("reason", "")), "silent": true})
				continue
			var drop_slot: int = int(choice.get("drop_slot", -1))
			var bag: Array = inventory.get(u.idx, [])
			if bag.size() >= SLOTS:
				if drop_slot < 0 or drop_slot >= bag.size():
					continue
				var old_id: String = str(bag[drop_slot])
				_remove_item(u, old_id)
				bag.remove_at(drop_slot)
				uid_seq += 1
				var dropped: Dictionary = {"uid": uid_seq, "item": old_id, "pos": sim.arena.resolve_circle(u.pos - u.facing * 30.0, 14.0), "t": sim.time, "dropped": u.idx}
				field.append(dropped)
				sim.emit("DM_ITEM_DROPPED", u.idx, u.idx, {"uid": uid_seq, "item": old_id, "pos": dropped.pos, "reason": "swap"})
			field.erase(it)
			bag.append(str(it.item))
			inventory[u.idx] = bag
			items_picked[u.team] += 1
			_apply_item(u, str(it.item))
			sim.emit("DM_ITEM_PICKED", u.idx, u.idx, {"uid": it.uid, "item": it.item, "pos": it.pos, "reason": str(choice.get("reason", "")),
				"rarity": ItemDefs.rarity_of(str(it.item)), "slots": bag.duplicate()})


func _decide_pickup(u: BUnit, it: Dictionary) -> Dictionary:
	var ctl = sim.controllers[sim.eteam(u)] if sim.eteam(u) < sim.controllers.size() else null
	if ctl and ctl.has_method("item_choice"):
		return ctl.item_choice(u, str(it.item))
	var bag: Array = inventory.get(u.idx, [])
	if bag.size() < SLOTS:
		return {"take": true, "reason": "빈 슬롯"}
	# Default: keep higher rarity.
	var worst: int = 0
	for k in bag.size():
		if ItemDefs.rarity_of(str(bag[k])) < ItemDefs.rarity_of(str(bag[worst])):
			worst = k
	if ItemDefs.rarity_of(str(it.item)) > ItemDefs.rarity_of(str(bag[worst])):
		return {"take": true, "drop_slot": worst, "reason": "더 높은 등급"}
	return {"take": false, "reason": "슬롯 가득"}


func _apply_item(u: BUnit, item_id: String) -> void:
	var d: Dictionary = ItemDefs.get_def(item_id)
	var tag: String = "item:" + item_id
	for key in d.get("stats", {}):
		sim.add_buff(u, StringName(str(key)), float(d.stats[key]), INF, u.idx, {"tag": tag})
	for key in d.get("flat", {}):
		sim.add_buff(u, StringName(str(key) + "Flat"), float(d.flat[key]), INF, u.idx, {"tag": tag})
	if d.has("omnivamp"):
		sim.add_buff(u, &"omnivamp", float(d.omnivamp), INF, u.idx, {"tag": tag})
	if d.has("range"):
		var add: float = float(d.range.melee) if u.def.is_melee() else float(d.range.ranged)
		sim.add_buff(u, &"attackRangeFlat", add, INF, u.idx, {"tag": tag})
	if d.has("tyrant"):
		(state[u.idx] as Dictionary)["tyrant"] = 0


func _remove_item(u: BUnit, item_id: String) -> void:
	sim.remove_buffs_tag(u, "item:" + item_id)
	if item_id == "e_berserk":
		sim.remove_buffs_tag(u, "item_berserk")
	u.hp = minf(u.hp, sim.max_hp(u))


func _drop_on_death(t: BUnit) -> void:
	var bag: Array = inventory.get(t.idx, [])
	if bag.is_empty() or field.size() >= MAX_FIELD_ITEMS:
		return
	var best: String = ""
	for id in bag:
		if best == "" or ItemDefs.rarity_of(str(id)) > ItemDefs.rarity_of(best):
			best = str(id)
	if best == "" or best == "m_phoenix":
		return
	uid_seq += 1
	var p: Vector2 = sim.arena.resolve_circle(t.pos, 14.0)
	field.append({"uid": uid_seq, "item": best, "pos": p, "t": sim.time, "dropped": t.idx})
	sim.emit("DM_ITEM_DROPPED", t.idx, t.idx, {"uid": uid_seq, "item": best, "pos": p, "reason": "death"})


# ---------------------------------------------------------------- item effects

func vision_bonus(u: BUnit) -> float:
	var v: float = 0.0
	for x in _items_with(u, "vision"):
		v += float(x)
	return v


func forest_reveal_range(observer: BUnit, target: BUnit) -> float:
	var r: float = 110.0
	for x in _items_with(observer, "forest_reveal"):
		r += float(x)
	for sh in _items_with(target, "shadow"):
		r = minf(r, float(sh.reveal) + (r - 110.0) * 0.5)
	return r


func cooldown_mult(u: BUnit) -> float:
	var cdr: float = 0.0
	for x in _items_with(u, "cdr"):
		cdr += float(x)
	return 1.0 - minf(0.4, cdr)


func mr_pen(u: BUnit) -> float:
	var pen: float = 0.0
	for x in _items_with(u, "mr_pen"):
		pen = maxf(pen, float(x))
	return pen


func outgoing_mult(s: BUnit, t: BUnit, _ctx: Dictionary) -> float:
	if t == null:
		return 1.0
	var m: float = BRAWL_DAMAGE if t.is_hero else 1.0
	if s == null or not s.is_hero:
		return m
	for ex in _items_with(s, "execute"):
		if t.hp / maxf(1.0, sim.max_hp(t)) < float(ex.below):
			m *= 1.0 + float(ex.bonus)
	var st: Dictionary = state.get(s.idx, {})
	if int(st.get("tyrant", 0)) > 0:
		for ty in _items_with(s, "tyrant"):
			m *= 1.0 + float(ty.per_kill) * int(st.tyrant)
	for sh in _items_with(s, "shadow"):
		var left: float = float(st.get("forest_exit", -99.0))
		if not bool(st.get("ambush_used", true)) and sim.time - left <= float(sh.window):
			m *= 1.0 + float(sh.ambush)
			st["ambush_used"] = true
	return m


func incoming_mult(t: BUnit) -> float:
	var m: float = 1.0
	for ae in _items_with(t, "aegis"):
		m *= 1.0 - float(ae.reduction)
	return m


func block_cc(t: BUnit, type: StringName) -> bool:
	if not t.is_hero or not sim.CC_TYPES.has(type) or type == &"slow":
		return false
	for ae in _items_with(t, "aegis"):
		var st: Dictionary = state.get(t.idx, {})
		if sim.time >= float(st.get("aegis_ready", 0.0)):
			st["aegis_ready"] = sim.time + float(ae.cleanse)
			state[t.idx] = st
			sim.emit("DM_ITEM_PROC", t.idx, t.idx, {"item": "l_aegis", "kind": "cleanse", "status": String(type), "pos": t.pos})
			return true
	return false


func on_heal(t: BUnit, overheal: float) -> void:
	if overheal <= 0.0:
		return
	for bs in _items_with(t, "bloodstone"):
		var cap: float = sim.max_hp(t) * float(bs.cap)
		var have: float = 0.0
		for sh in t.shields:
			if sh.affection == false and sh.source_idx == t.idx and sh.seq == -77 and sh.end > sim.time:
				have += sh.amount
		var add: float = minf(overheal, cap - have)
		if add > 1.0:
			var shield := ST.Shield.new()
			shield.amount = add
			shield.max_amount = add
			shield.end = sim.time + 6.0
			shield.source_idx = t.idx
			shield.seq = -77
			t.shields.append(shield)


func on_damage(s: BUnit, t: BUnit, hp_dmg: float, absorbed: float, ctx: Dictionary) -> void:
	var src: BUnit = _credited_hero(s)
	if t.is_hero and src and src != t:
		var hits: Dictionary = recent_hits.get(t.idx, {})
		hits[src.idx] = sim.time
		recent_hits[t.idx] = hits
	if bool(ctx.get("item_proc", false)):
		return
	var dealt: float = hp_dmg + absorbed
	# Attacker-side procs.
	if s and s.is_hero and s.alive and dealt > 0.0 and sim.eteam(s) != sim.eteam(t):
		var basic: bool = bool(ctx.get("basic", false))
		if basic:
			for bl in _items_with(s, "bleed"):
				var per_tick: float = sim.max_hp(t) * float(bl.ratio) / maxf(1.0, float(bl.duration))
				sim.apply_dot(s, t, {"interval": 1.0, "duration": float(bl.duration), "originRefresh": true,
					"damageEffect": {"type": "damage", "school": "physical", "base": per_tick, "frozen": true}}, {"source_type": "ITEM", "item_proc": true})
			for mt in _items_with(s, "meteor"):
				for e in sim.opponents(s):
					if e == t or not e.alive or e.pos.distance_to(t.pos) > float(mt.radius) + sim.radius(e):
						continue
					sim.apply_damage(s, e, {"school": "physical", "base": dealt * float(mt.splash), "frozen": true}, {"source_type": "ITEM", "item_proc": true, "snapshot": true})
					sim.apply_status(s, e, {"status": "slow", "magnitude": float(mt.slow), "duration": float(mt.slow_duration)}, {"source_type": "ITEM", "item_proc": true})
				sim.apply_status(s, t, {"status": "slow", "magnitude": float(mt.slow), "duration": float(mt.slow_duration)}, {"source_type": "ITEM", "item_proc": true})
				sim.emit("DM_ITEM_PROC", s.idx, t.idx, {"item": "l_hammer", "kind": "splash", "pos": t.pos})
		var counted: bool = str(ctx.get("source_type", "ABILITY")) in ["ABILITY", "BASIC_ATTACK", "SUMMON"] or basic
		for th in (_items_with(s, "thunder") if counted else []):
			var st: Dictionary = state.get(s.idx, {})
			st["thunder"] = int(st.get("thunder", 0)) + 1
			state[s.idx] = st
			if int(st.thunder) >= int(th.every):
				st["thunder"] = 0
				var dmg: Dictionary = {"school": "magic", "base": float(th.base), "ad": float(th.ad), "ap": float(th.ap)}
				for e in sim.opponents(s):
					if e.alive and e.pos.distance_to(t.pos) <= float(th.radius) + sim.radius(e):
						sim.apply_damage(s, e, dmg, {"source_type": "ITEM", "item_proc": true})
				sim.emit("DM_ITEM_PROC", s.idx, t.idx, {"item": "m_thunder", "kind": "lightning", "pos": t.pos, "radius": float(th.radius)})
	# Victim-side procs.
	if t.is_hero and t.alive:
		if s and s.alive and bool(ctx.get("basic", false)) and sim.eteam(s) != sim.eteam(t):
			for tr in _items_with(t, "thorns"):
				sim.apply_damage(t, s, {"school": "magic", "base": dealt * float(tr), "frozen": true}, {"source_type": "ITEM", "item_proc": true, "snapshot": true})
		for gd in _items_with(t, "guard"):
			var st2: Dictionary = state.get(t.idx, {})
			if t.hp / maxf(1.0, sim.max_hp(t)) < float(gd.below) and sim.time >= float(st2.get("guard_ready", 0.0)):
				st2["guard_ready"] = sim.time + float(gd.cooldown)
				state[t.idx] = st2
				sim.apply_shield(t, t, {"base": sim.max_hp(t) * float(gd.shield), "duration": float(gd.duration), "frozen": true}, {"source_type": "ITEM", "item_proc": true})
				sim.emit("DM_ITEM_PROC", t.idx, t.idx, {"item": "e_guard", "kind": "shield", "pos": t.pos})


func try_revive(t: BUnit, _s: BUnit) -> bool:
	if not has_item(t, "m_phoenix"):
		return false
	var d: Dictionary = ItemDefs.get_def("m_phoenix").revive
	var bag: Array = inventory.get(t.idx, [])
	bag.erase("m_phoenix")
	inventory[t.idx] = bag
	_remove_item(t, "m_phoenix")
	t.hp = sim.max_hp(t) * float(d.hp)
	t.action = null
	t.motion = null
	sim.remove_statuses_where(t, func(st): return sim.is_cc_type(st.type))
	sim.push_status(t, &"invulnerable", t.idx, float(d.invulnerable), {"phoenix": true})
	sim.emit("DM_REVIVE", t.idx, t.idx, {"item": "m_phoenix", "pos": t.pos, "hp": t.hp})
	return true


func _on_kill_items(killer: BUnit) -> void:
	if not killer.alive:
		return
	for hu in _items_with(killer, "hunter"):
		sim.apply_heal(killer, killer, {"base": sim.max_hp(killer) * float(hu.heal)}, {"source_type": "ITEM", "proc": true})
		sim.add_buff(killer, &"moveSpeed", float(hu.ms), float(hu.duration), killer.idx, {"tag": "item_hunter"})
		sim.emit("DM_ITEM_PROC", killer.idx, killer.idx, {"item": "e_instinct", "kind": "hunt", "pos": killer.pos})
	for ch in _items_with(killer, "chrono"):
		for i in killer.cooldowns.size():
			var rem: float = killer.cooldowns[i] - sim.time
			if rem > 0.0:
				killer.cooldowns[i] = sim.time + rem * (1.0 - float(ch.refund))
		sim.emit("DM_ITEM_PROC", killer.idx, killer.idx, {"item": "m_chrono", "kind": "refund", "pos": killer.pos})
	for ty in _items_with(killer, "tyrant"):
		var st: Dictionary = state.get(killer.idx, {})
		st["tyrant"] = mini(int(ty.max), int(st.get("tyrant", 0)) + 1)
		state[killer.idx] = st


func _quarter_second_effects() -> void:
	for u in sim.heroes:
		if not u.alive:
			continue
		var st: Dictionary = state.get(u.idx, {})
		# Forest exit time for the shadow cloak ambush window.
		var in_forest: bool = sim.arena.forest_at(u.pos) >= 0
		if bool(st.get("in_forest", false)) and not in_forest:
			st["forest_exit"] = sim.time
			st["ambush_used"] = false
		st["in_forest"] = in_forest
		# Out-of-combat recovery is the deathmatch's only natural sustain.
		var delay: float = 7.0
		var rate: float = 0.015
		for rg in _items_with(u, "regen"):
			delay = minf(delay, float(rg.delay))
			rate += float(rg.ratio)
		if sim.time - u.last_damage_time >= delay and sim.time - u.last_combat_time >= delay and u.hp < sim.max_hp(u):
			sim.apply_heal(u, u, {"base": sim.max_hp(u) * rate * 0.25}, {"source_type": "REGEN", "proc": true, "silent": true})
		for bz in _items_with(u, "berserk"):
			var low: bool = u.hp / maxf(1.0, sim.max_hp(u)) < float(bz.below)
			var on: bool = bool(st.get("berserk_on", false))
			if low and not on:
				sim.add_buff(u, &"attackSpeed", float(bz.as), INF, u.idx, {"tag": "item_berserk"})
				sim.add_buff(u, &"attackDamage", float(bz.ad), INF, u.idx, {"tag": "item_berserk"})
				st["berserk_on"] = true
			elif not low and on:
				sim.remove_buffs_tag(u, "item_berserk")
				st["berserk_on"] = false
		state[u.idx] = st
