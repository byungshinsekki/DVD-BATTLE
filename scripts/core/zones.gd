class_name ZoneSystem
extends RefCounted


var sim: BattleSim
var list: Array[ST.Zone] = []


func _init(s: BattleSim) -> void :
	sim = s


func spawn(s: BUnit, pos: Vector2, r: float, duration: float, interval: float, effects: Array, filter: String, ctx: Dictionary, kind: String, data: Dictionary = {}) -> ST.Zone:
	var z: = ST.Zone.new()
	z.id = sim.next_id()
	z.kind = kind
	z.source_idx = s.idx
	z.team = int(ctx.get("team", sim.eteam(s)))
	z.pos = pos
	z.radius = r
	z.start = sim.time
	z.end = sim.time + duration
	z.interval = interval if interval > 0.0 else 0.25
	z.next_tick = sim.time
	z.effects = effects.duplicate(true)
	z.filter = filter
	z.ctx = ctx.duplicate()
	var ab = ctx.get("ability")
	z.color = (ab as Defs.AbilityDef).color if ab is Defs.AbilityDef else s.def.accent
	z.pattern = (ab as Defs.AbilityDef).pattern if ab is Defs.AbilityDef else ""
	z.data = data
	list.append(z)
	sim.emit("ZONE_SPAWNED", s.idx, -1, {"id": z.id, "kind": kind, "pos": pos, "radius": r, "duration": duration, "ability": ab})
	return z


func spawn_from_effect(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary) -> void :
	if f.get("originCoins", false):
		var p: Vector2 = ctx.get("hit_pos", ctx.get("target_pos", s.pos))
		for i in 6:
			var at: = sim.clamp_pos(p + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * (34.0 + (i % 2) * 17.0), 8.0)
			var cz: = spawn(s, at, 10.0, float(f.get("duration", 5.0)), 0.1, f.get("effects", []), "enemy", ctx, "coin")
			cz.pattern = "coin"
		return
	if f.get("originBanana", false):
		var bp: Vector2 = ctx.get("hit_pos", t.pos if t else s.pos)
		var bz: = spawn(s, bp, 30.0, float(f.get("duration", 7.0)), 0.1, [], "both", ctx, "banana", {"ignore_until": sim.time + 0.2})
		bz.pattern = "banana"
		return
	var p2: Vector2
	if f.get("atSourceOrigin", false):
		p2 = ctx.get("source_origin", s.pos)
	else:
		p2 = ctx.get("hit_pos", ctx.get("target_pos", t.pos if t else s.pos))
	var cone: bool = f.get("originCone", false)
	var ab0 = ctx.get("ability")
	# V2 originSingle: one live zone of this ability per caster (torquemada S1).
	if f.get("originSingle", false) and ab0 is Defs.AbilityDef:
		for old in list:
			if old.source_idx == s.idx and old.ctx.get("ability") == ab0 and not old.finished and old.end > sim.time:
				old.end = sim.time
	var rect: bool = f.get("originRect", false)
	var z: = spawn(s, p2, float(f.get("radius", 60.0)) if not rect else float(f.get("width", 60.0)) * 0.5, float(f.get("duration", 3.0)), float(f.get("interval", 0.25)), f.get("effects", []), str(f.get("filter", "enemy")), ctx, "cone" if cone else "zone")
	z.trigger_once = f.get("triggerOnce", false)
	z.once_per_unit = f.get("oncePerUnit", false)
	if rect:
		# V2 rectangle (war_machine S4): from the source origin along the aim for
		# `length`, `width` wide; a unit is inside when its distance to that
		# segment is at most width/2 + its radius.
		var aim: Vector2 = ctx.get("target_pos", p2 + s.facing)
		z.shape = "rect"
		z.dir = (aim - p2).normalized() if aim.distance_squared_to(p2) > 1e-06 else s.facing
		z.range = float(f.get("length", 300.0))
		z.width = float(f.get("width", 60.0))
		z.data["a"] = p2
		z.data["b"] = p2 + z.dir * z.range
	if cone:
		z.shape = "cone"
		z.dir = ctx.get("direction", s.facing)
		z.range = float(f.get("radius", 60.0))
		var ab = ctx.get("ability")
		z.angle = (ab as Defs.AbilityDef).angle if ab is Defs.AbilityDef else 1.3


func update(_dt: float) -> void :
	var dt: = BattleSim.DT

	if not sim.delayed.is_empty():
		var ready: Array = []
		var rest: Array = []
		for j in sim.delayed:
			if float(j.at) <= sim.time + 1e-09:
				ready.append(j)
			else:
				rest.append(j)
		sim.delayed = rest
		ready.sort_custom( func(a, b): return float(a.at) < float(b.at) or (float(a.at) == float(b.at) and int(a.seq) < int(b.seq)))
		for j in ready:
			var s: = sim.u_at(int(j.source))
			if s == null:
				continue
			var kind: = str(j.kind)
			if kind == "status":
				var t: = sim.u_at(int(j.target))
				if t and t.alive:
					sim.apply_status(s, t, j.effect, j.ctx)
			elif kind == "area" or (kind == "land" and s.alive):
				var p: Vector2 = s.pos if kind == "land" else j.pos
				var c: Dictionary = (j.ctx as Dictionary).duplicate()
				c["source_type"] = "DELAYED"
				c["cdr_key"] = c.get("action_id", 0)
				sim.resolve_area(s, p, float(j.radius), j.effects, c)
				var ab = c.get("ability")
				sim.fx("impact_area", p, {"radius": float(j.radius), "ability": ab, "color": (ab as Defs.AbilityDef).color if ab is Defs.AbilityDef else s.def.accent, "source": s.idx})

	for z in list:
		if z.end < sim.time - 1e-08 or z.finished:
			_finish(z)
			continue
		var s2: = sim.u_at(z.source_idx)
		if s2 == null:
			z.end = sim.time
			_finish(z)
			continue
		var c2: = z.ctx.duplicate()
		c2["source_type"] = "ZONE"
		c2["team"] = z.team
		c2["cdr_key"] = z.id
		c2["zone"] = z.id
		c2["area"] = true
		match z.kind:
			"bed":
				var bed: = sim.u_at(int(z.data.get("entity", -1)))
				if bed == null or not bed.alive:
					z.end = sim.time
				else:
					_tick_bed(z, bed)
				continue
			"portal", "rift":
				continue
			"mist":
				if float(z.data.distance) < float(z.data.range):
					var adv: = minf(float(z.data.speed) * dt, float(z.data.range) - float(z.data.distance))
					var a: = z.pos
					var b: = a + z.dir * adv
					var col: = sim.arena.terrain_contact(a, b, 10.0, false)
					z.pos = col.point if not col.is_empty() else b
					z.data.distance = float(z.data.distance) + adv
					if not col.is_empty():
						z.data.distance = z.data.range
		if sim.time + 1e-09 < z.next_tick:
			continue
		z.next_tick += z.interval
		var cands: Array[BUnit] = []
		if z.shape == "rect":
			for u in sim.bodies_alive():
				var near: = Geometry2D.get_closest_point_to_segment(u.pos, z.data.a, z.data.b)
				if u.pos.distance_to(near) <= z.width * 0.5 + sim.radius(u) and sim.los(near, u.pos, 1.0):
					cands.append(u)
		else:
			for u in sim.bodies_alive():
				if u.pos.distance_to(z.pos) <= z.radius + sim.radius(u) and sim.los(z.pos, u.pos, 1.0):
					cands.append(u)
		match z.kind:
			"mist":
				var quota: = minf(float(z.data.budget), float(z.data.initial) / 12.0)
				var left: = quota
				var allies: Array[BUnit] = []
				for u in cands:
					if u.is_hero and sim.eteam(u) == z.team and u.hp < sim.max_hp(u) - 0.001:
						allies.append(u)
				allies.sort_custom( func(x, y): return sim.hp_ratio(x) < sim.hp_ratio(y))
				for u in allies:
					if left < 0.001:
						break
					var attempted: = minf(left, sim.max_hp(u) - u.hp)
					var r: = sim.apply_heal(s2, u, {"base": attempted}, c2)
					var spent: = float(r.effective) + float(r.reduced)
					left -= spent
					z.data.budget = float(z.data.budget) - spent
					z.data.healed = float(z.data.healed) + float(r.effective)
				if float(z.data.budget) <= 1e-06:
					z.end = sim.time
			"bait":
				var trig: Dictionary = z.data.triggered
				var lure: Dictionary = z.data.lure
				for u in cands:
					if sim.eteam(u) == z.team or trig.has(u.idx):
						continue
					if u.pos.distance_to(z.pos) <= 18.0 + sim.radius(u):
						if sim.apply_status(s2, u, {"status": "stun", "duration": 0.8}, c2):
							trig[u.idx] = true
							var zid: = z.id
							sim.remove_statuses_where(u, func(x): return x.type == &"charm" and int(x.extra.get("bait_id", -1)) == zid)
							sim.fx("bait_snap", z.pos, {"color": z.color})
					else:
						if not lure.has(u.idx):
							lure[u.idx] = sim.time
						var el: = sim.time - float(lure[u.idx])
						if el < 1.2 - 1e-08:
							sim.apply_status(s2, u, {"status": "charm", "duration": minf(0.18, 1.2 - el), "bait_pos": z.pos, "bait_id": z.id}, c2)
					if trig.size() >= 2:
						z.end = sim.time
						break
			"banana":
				if sim.time < float(z.data.ignore_until):
					continue
				var best: BUnit = null
				for u in cands:
					if u.is_hero and (best == null or u.pos.distance_to(z.pos) < best.pos.distance_to(z.pos)):
						best = u
				if best:
					if sim.eteam(best) == z.team:
						sim.apply_status(s2, best, {"status": "stun", "duration": 0.3, "originExactDuration": true}, c2)
						sim.apply_heal(s2, best, {"base": 46.0, "ap": 0.25}, c2)
					else:
						sim.apply_status(s2, best, {"status": "stun", "duration": 0.65}, c2)
						sim.apply_mark(s2, best, {"status": "confusion", "duration": 7.0, "stacks": 1, "maxStacks": 5, "damageAmp": 0.03, "tenacityLoss": 0.025}, c2)
					z.end = sim.time
					sim.fx("banana_slip", z.pos, {"color": z.color})
			"coin":
				for u in cands:
					if sim.eteam(u) != z.team and u.is_hero:
						sim.apply_effects(s2, u, z.effects, c2)
						z.end = sim.time
						sim.emit("COIN_COLLECTED", s2.idx, u.idx, {"pos": z.pos})
						sim.fx("coin_pick", z.pos, {"color": z.color})
						break
			_:
				var allowed: Array[BUnit] = []
				for u in cands:
					var same: = sim.eteam(u) == z.team
					if z.filter == "both" or (z.filter == "ally" and same) or (z.filter == "enemy" and not same):
						allowed.append(u)
				var targets: Array[BUnit] = sim.query_cone(z.pos, z.dir, z.range, z.angle, allowed) if z.shape == "cone" else allowed
				for u in targets:
					if (z.trigger_once or z.once_per_unit) and z.hits.has(u.idx):
						continue
					sim.apply_effects(s2, u, z.effects, c2)
					z.hits[u.idx] = sim.time
				if z.trigger_once:
					z.end = sim.time
	var keep: Array[ST.Zone] = []
	for z in list:
		if z.finished or z.end <= sim.time + 1e-08:
			_finish(z)
		else:
			keep.append(z)
	list = keep
	_update_portals()
	sim.cleanup_telegraphs()


func _finish(z: ST.Zone) -> void :
	if z.finished:
		return
	z.finished = true
	sim.emit("ZONE_ENDED", z.source_idx, -1, {"id": z.id, "kind": z.kind, "pos": z.pos})


func _tick_bed(_z: ST.Zone, bed: BUnit) -> void :
	var s: = sim.u_at(bed.owner_idx)
	if s == null:
		return
	var b: Dictionary = bed.ks.bed
	var inside: Array[BUnit] = []
	for u in sim.heroes:
		if u.alive and u.team == bed.team and sim.eteam(u) == bed.team and u.pos.distance_to(bed.pos) <= 90.0 + sim.radius(u):
			inside.append(u)
	var ids: Dictionary = {}
	for u in inside:
		ids[u.idx] = true
	var entries: Dictionary = b.entries
	for key in entries.keys():
		if not ids.has(key):
			entries.erase(key)
	for u in inside:
		if not entries.has(u.idx):
			entries[u.idx] = {"at": sim.time, "order": sim.next_id()}
	var pairs: Dictionary = b.pairs
	for key in pairs.keys():
		var pr: Dictionary = pairs[key]
		if not (ids.has(pr.ids[0]) and ids.has(pr.ids[1])):
			pairs.erase(key)
	var assigned: Dictionary = {}
	for key in pairs:
		for i in pairs[key].ids:
			assigned[i] = true
	var remaining: Array[BUnit] = []
	for u in inside:
		if not assigned.has(u.idx):
			remaining.append(u)
	remaining.sort_custom( func(x, y): return int(entries[x.idx].order) < int(entries[y.idx].order))
	var i2: = 0
	while i2 + 1 < remaining.size():
		var pid: = "%d|%d" % [remaining[i2].idx, remaining[i2 + 1].idx]
		pairs[pid] = {"ids": [remaining[i2].idx, remaining[i2 + 1].idx], "at": sim.time, "done": false}
		assigned[remaining[i2].idx] = true
		assigned[remaining[i2 + 1].idx] = true
		i2 += 2
	var odd: BUnit = null
	for u in inside:
		if not assigned.has(u.idx):
			odd = u
			break
	if odd == null:
		b.odd = {}
	elif int((b.odd as Dictionary).get("id", -1)) != odd.idx:
		b.odd = {"id": odd.idx, "at": sim.time, "done": false}
	if sim.time + 1e-09 >= float(b.next_heal):
		b.next_heal = sim.time + 1.0
		for u in inside:
			sim.apply_heal(s, u, {"base": 8.0, "ap": 0.06}, {"source_type": "ZONE", "silent": true, "ability": bed.ctx.get("ability")})
	for key in pairs:
		var pr2: Dictionary = pairs[key]
		if not pr2.done and sim.time - float(pr2.at) >= 10.0 - 1e-08:
			pr2.done = true
			for uid in pr2.ids:
				var t: = sim.u_at(int(uid))
				sim.apply_heal(s, t, {"base": maxf(0.0, sim.max_hp(t) - t.hp)}, {"ability": bed.ctx.get("ability")})
				sim.add_buff(t, &"attackDamage", 0.2, 5.0, s.idx, {"tag": "bedPair"})
			sim.emit("PARITY_BED_RESOLVED", s.idx, -1, {"result": "paired", "pos": bed.pos})
			sim.fx("bed_pair", bed.pos, {"color": s.def.accent})
	var od: Dictionary = b.odd
	if not od.is_empty() and not od.done and sim.time - float(od.at) >= 10.0 - 1e-08:
		od.done = true
		var ou: = sim.u_at(int(od.id))
		if ou:
			sim.add_buff(ou, &"attackDamage", -0.15, 4.0, s.idx, {"tag": "bedOdd%d" % bed.idx})
			sim.emit("PARITY_BED_RESOLVED", s.idx, ou.idx, {"result": "isolated", "pos": ou.pos})
	var vis_pairs: Array = []
	for key in pairs:
		vis_pairs.append({"ids": pairs[key].ids, "progress": minf(1.0, (sim.time - float(pairs[key].at)) / 10.0), "done": pairs[key].done})
	bed.ks["bed_visual"] = {"pairs": vis_pairs, "odd": int(od.get("id", -1)), "occupants": inside.size()}


func prepare_transit(u: BUnit) -> bool:
	if not u.alive or u.portal_until > sim.time:
		return false
	u.portal_until = sim.time + 2.5
	if u.motion:
		var m: = u.motion
		u.motion = null
		sim.remove_statuses_where(u, func(x): return int(x.extra.get("motion_id", -1)) == m.id)
	u.ks["wall_run_until"] = 0.0
	return true


func grant_shards(u: BUnit, key: String) -> void :
	if not u.is_hero or u.def.id != "dimensionalist" or not u.alive:
		return
	if str(u.ks.get("last_portal_grant", "")) == key:
		return
	u.ks["last_portal_grant"] = key
	var r: = u.def.rule("portal_shards")
	u.resources["shards"] = minf(float(r.get("max", 40)), float(u.resources.get("shards", 0.0)) + float(r.get("originGainPerUse", 10)))
	sim.emit("PASSIVE", u.idx, u.idx, {"rule": "portal_shards", "detail": "차원 조각 %d" % int(u.resources.shards), "silent": true})


func _update_portals() -> void :
	if sim.portal_pairs.is_empty():
		return
	var keep: Array = []
	for pair in sim.portal_pairs:
		if float(pair.end) > sim.time:
			keep.append(pair)
	sim.portal_pairs = keep
	for pair in sim.portal_pairs:
		var owner: = sim.u_at(int(pair.source))
		if owner == null:
			continue
		for u in sim.bodies_alive():
			if u.structure or u.chamber != "" or u.kind == "bed" or sim.eteam(u) != int(pair.team) or u.portal_until > sim.time:
				continue
			if sim.has_any(u, [&"grounded", &"suppression"]):
				continue
			for ends in [[pair.a, pair.b], [pair.b, pair.a]]:
				var from: Vector2 = ends[0]
				var to: Vector2 = ends[1]
				if u.pos.distance_to(from) > float(pair.radius) + sim.radius(u):
					continue
				if not prepare_transit(u):
					continue
				var dir: = (to - from).normalized()
				var src: Vector2 = u.pos
				u.pos = sim.clamp_pos(to + dir * (float(pair.radius) + sim.radius(u) + 3.0), sim.radius(u))
				sim.warfare.constrain(u, src)
				u.prev_pos = u.pos
				u.vel = Vector2.ZERO
				if pair.enhanced:
					sim.apply_shield(owner, u, {"base": 60.0, "ap": 0.5, "duration": 3.0}, pair.ctx)
				sim.emit("PORTAL_USED", owner.idx, u.idx, {"from": src, "to": u.pos})
				grant_shards(u, "%d:%d" % [int(pair.id), sim.tick])
				break
