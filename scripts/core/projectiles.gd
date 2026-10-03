class_name ProjectileSystem
extends RefCounted


var sim: BattleSim
var list: Array[ST.Projectile] = []
var volley_hits: Dictionary = {}

const PRIORITY: = {"rift": 0, "bat": 1, "terrain": 2, "portal": 3, "body": 4, "arrival": 5}


func _init(s: BattleSim) -> void :
	sim = s


func spawn(s: BUnit, t: BUnit, p: Vector2, a: Defs.AbilityDef, effects: Array, ctx: Dictionary, opts: Dictionary = {}) -> ST.Projectile:
	return spawn_from(s, s, t, p, a, effects, ctx, opts)


func spawn_from(shooter: BUnit, owner: BUnit, t: BUnit, p: Vector2, a: Defs.AbilityDef, effects: Array, ctx: Dictionary, opts: Dictionary = {}) -> ST.Projectile:
	var q: = ST.Projectile.new()
	q.id = sim.next_id()
	q.source_idx = owner.idx
	q.shooter_idx = shooter.idx
	q.team = int(ctx.get("team", sim.eteam(owner)))
	var dir: = (p - shooter.pos)
	dir = dir.normalized() if dir.length_squared() > 1e-09 else shooter.facing
	var speed: = a.speed * (1.0 + (sim.buff_sum(owner, &"projectileSpeed") if owner.is_hero else 0.0))
	q.pos = shooter.pos + dir * (sim.radius(shooter) + 4.0)
	q.prev_pos = shooter.pos
	q.launch_pos = shooter.pos
	q.vel = dir * speed
	q.speed = speed
	q.target_idx = t.idx if t else -1
	q.target_pos = p
	q.homing = a.homing
	q.radius = float(opts.get("radius", maxf(3.0, a.width * 0.5)))
	var rng_: = a.range if a.range > 0.0 else sim.stat(owner, &"attackRange")
	q.max_distance = a.max_distance if a.max_distance > 0.0 else rng_ + 80.0
	q.bounces = a.bounces
	q.pierce = a.pierce
	q.ability = a
	q.basic = opts.get("basic", false)
	q.source_type = str(ctx.get("source_type", "ABILITY"))
	var basic: bool = ctx.get("basic", false)
	q.effects = effects.duplicate(true) if opts.get("prefrozen", false) else sim.freeze_effects(owner, t, effects, basic, true)
	q.ctx = ctx.duplicate()
	q.ctx["snapshot"] = true
	q.ctx["src_hp"] = owner.hp
	q.ctx["src_max"] = sim.max_hp(owner)
	var bonus: = float(ctx.get("bonus", 0.0))
	if bonus > 0.0:
		for f in q.effects:
			if str(f.get("type", "")) == "damage":
				f["base"] = float(f.get("base", 0.0)) + bonus
				break
	q.explode_on_arrival = opts.get("explode", false)
	q.return_to_source = a.return_to_source
	q.wing = opts.get("wing", false)
	q.born_at = sim.time
	q.color = a.color
	q.pattern = a.pattern if a.pattern != "" else ("basic" if q.basic else "orb")
	q.realm = shooter.chamber
	q.turret = opts.get("turret", false)
	q.driver = opts.get("driver", false)
	q.ctx["impact_radius"] = float(opts.get("impact_radius", a.radius))
	list.append(q)
	sim.emit("PROJECTILE_CREATED", owner.idx, q.target_idx, {"id": q.id, "pos": q.pos, "to": p, "ability": a if not q.basic else null, "basic": q.basic, "turret": q.turret})
	return q


func update(dt: float) -> void :
	if dt <= 0.0:
		return
	var processing: = list
	list = []
	var next: Array[ST.Projectile] = []
	for p in processing:
		var s: = sim.u_at(p.source_idx)
		if s == null:
			_end(p, "source_missing")
			continue
		if not sim.chambers.is_empty() and _chamber_blocked(p, dt):
			_end(p, "chamber")
			continue
		p.prev_pos = p.pos
		if p.wing and sim.time - p.born_at > 2.5:
			_end(p, "wing_timeout")
			continue
		if p.returning:
			if p.pos.distance_to(s.pos) <= sim.radius(s) + 10.0:
				_end(p, "returned")
				continue
			p.vel = (s.pos - p.pos).normalized() * p.speed
		elif p.homing:
			var tg: = sim.u_at(p.target_idx)
			if tg and tg.alive and not sim.has_status(tg, &"untargetable"):
				var dv: = tg.pos - p.pos
				if dv.length_squared() > 1e-06:
					p.vel = dv.normalized() * p.speed
		var a: = p.pos
		var step: = minf(p.speed * dt, maxf(0.0, p.max_distance - p.distance))
		var dirv: = p.vel.normalized() if p.vel.length_squared() > 1e-09 else Vector2.RIGHT
		var b: = a + dirv * step
		var pr: = p.radius if p.radius > 0.0 else 3.0
		var hits: Array = []
		var terr: = sim.arena.terrain_contact(a, b, pr, true)
		if not terr.is_empty():
			hits.append({"t": float(terr.t), "kind": "terrain", "normal": terr.normal})
		for z in sim.zones.list:
			if z.kind != "rift" or z.end <= sim.time or z.team == p.team:
				continue
			var rift_t: = sweep_capsule(a, b, z.data.a, z.data.b, pr + 5.0)
			if rift_t >= 0.0:
				hits.append({"t": rift_t, "kind": "rift", "zone": z})
		for u in sim.heroes:
			if not u.alive:
				continue
			var bat: Dictionary = u.ks.get("bat", {})
			if bat.is_empty() or float(bat.until) <= sim.time or sim.eteam(u) == p.team:
				continue
			if sim.has_any(u, [&"stun", &"sleep", &"airborne", &"suppression"]):
				continue
			var tb: = sector_entry(a, b, u.pos, 76.0, bat.dir, deg_to_rad(80.0), pr)
			if tb >= 0.0:
				hits.append({"t": tb, "kind": "bat", "unit": u})
		for pair in sim.portal_pairs:
			var owner: = sim.u_at(int(pair.source))
			if float(pair.end) <= sim.time or int(pair.team) != p.team or owner == null or float(owner.ks.get("portal_armed_until", 0.0)) <= sim.time or p.portals_used.has(pair.id):
				continue
			for ends in [[pair.a, pair.b], [pair.b, pair.a]]:
				var tp: = Arena.seg_circle_t(a, b, ends[0], float(pair.radius) + pr)
				if tp >= 0.0:
					hits.append({"t": tp, "kind": "portal", "pair": pair, "exit": ends[1]})
		for u in sim.bodies_alive():
			if sim.eteam(u) == p.team or p.hit_ids.has(u.idx) or sim.has_status(u, &"untargetable") or u.chamber != p.realm:
				continue
			var tu: = Arena.seg_circle_t(a, b, u.pos, sim.radius(u) + pr)
			if tu >= 0.0:
				hits.append({"t": tu, "kind": "body", "unit": u})
		if p.explode_on_arrival and not p.returning:
			var ta: = Arena.seg_circle_t(a, b, p.target_pos, maxf(3.0, pr * 0.5))
			if ta >= 0.0:
				hits.append({"t": ta, "kind": "arrival"})
		if hits.size() > 1:
			hits.sort_custom( func(x, y):
				if absf(float(x.t) - float(y.t)) > 1e-09:
					return float(x.t) < float(y.t)
				return int(PRIORITY[x.kind]) < int(PRIORITY[y.kind]))
		var consumed: = false
		var redirected: = false
		var fraction: = 1.0
		for h in hits:
			var at: = a.lerp(b, float(h.t))
			p.pos = at
			fraction = float(h.t)
			var kind: = str(h.kind)
			if kind == "rift":
				var z: ST.Zone = h.zone
				var defender: = sim.u_at(z.source_idx)
				if defender and float(z.data.get("reflect", 0.0)) > 0.0:
					reflect(p, defender, float(z.data.reflect))
				sim.emit("PROJECTILE_BLOCKED", z.source_idx, p.source_idx, {"reason": "rift", "pos": at})
				consumed = true
			elif kind == "bat":
				_bat_intercept(p, h.unit)
				consumed = true
			elif kind == "portal":
				var pair2: Dictionary = h.pair
				var exitp: Vector2 = h.exit
				p.pos = sim.clamp_pos(exitp + dirv * (float(pair2.radius) + pr + 2.0), pr)
				p.prev_pos = p.pos
				p.portals_used.append(pair2.id)
				var ow: = sim.u_at(int(pair2.source))
				if ow and ow.ks.get("portal_enhanced", false) and not p.portal_amplified:
					p.effects = sim.scale_damage(p.effects, 1.1)
					p.portal_amplified = true
				sim.emit("PROJECTILE_PORTAL", int(pair2.source), p.source_idx, {"pos": p.pos, "from": at})
				redirected = true
			elif kind == "terrain":
				sim.fx("proj_wall", at, {"color": p.color, "bounce": p.bounces > 0})
				if p.bounces > 0:
					var n: Vector2 = h.normal
					p.pos = at + n * 0.6
					p.vel = p.vel - n * 2.0 * p.vel.dot(n)
					p.bounces -= 1
					p.leg += 1
					if p.ability and p.ability.flag("originBounceRehit", false):
						p.hit_ids.clear()
					redirected = true
				else:
					for f in p.effects:
						if str(f.get("type", "")) == "move_self" and str(f.get("mode", "")) == "dashToImpact":
							var c: = p.ctx.duplicate()
							c["hit_pos"] = at
							sim.kits.move_self(s, null, f, c)
					if p.explode_on_arrival:
						area_impact(p, at)
					if p.return_to_source and not p.returning:
						p.pos = at + (h.normal as Vector2) * 0.8
						_return_leg(p)
						redirected = true
					else:
						consumed = true
			elif kind == "arrival":
				area_impact(p, at)
				consumed = true
			elif kind == "body":
				var tgt: BUnit = h.unit
				if tgt.alive:
					var dfn: = resolve_defense(p, tgt)
					if dfn.blocked:
						consumed = true
					elif p.explode_on_arrival:
						area_impact(p, at)
						consumed = true
					else:
						var c2: = p.ctx.duplicate()
						c2["hit_pos"] = tgt.pos
						c2["projectile"] = p.id
						c2["team"] = p.team
						c2["realm"] = p.realm
						var scale: float = dfn.scale
						if p.ability and p.ability.flag("originBounceRehit", false):
							if p.seen_counts.has(tgt.idx):
								scale *= 0.6
							p.seen_counts[tgt.idx] = int(p.seen_counts.get(tgt.idx, 0)) + 1
						var vf = p.ability.flag("originVolleyFalloff", null) if p.ability else null
						if vf != null:
							var key: = "%s:%d" % [str(p.ctx.get("action_id", p.id)), tgt.idx]
							if volley_hits.has(key):
								scale *= float(vf)
							volley_hits[key] = sim.time
						var effs: Array = p.effects if scale == 1.0 else sim.scale_damage(p.effects, scale)
						sim.apply_effects(s, tgt, effs, c2)
						p.hit_ids[tgt.idx] = true
						sim.fx("proj_hit", tgt.pos, {"color": p.color, "pattern": p.pattern, "basic": p.basic, "dir": dirv, "source": p.source_idx, "target": tgt.idx, "turret": p.turret, "ability": p.ability if not (p.basic or p.turret) else null})
						if p.pierce > 0:
							p.pierce -= 1
						else:
							consumed = true
			if consumed or redirected:
				break
		if consumed:
			_end(p, "hit")
			continue
		if not redirected:
			p.pos = b
		p.distance += step * (fraction if redirected else 1.0)
		if not redirected and p.distance >= p.max_distance - 1e-07:
			if p.return_to_source and not p.returning:
				_return_leg(p)
			else:
				if p.explode_on_arrival:
					area_impact(p, p.pos)
				_end(p, "range")
				continue
		next.append(p)
	next.append_array(list)
	list = next
	if sim.tick % 300 == 0 and not volley_hits.is_empty():
		var keep: Dictionary = {}
		for k in volley_hits:
			if sim.time - float(volley_hits[k]) < 30.0:
				keep[k] = volley_hits[k]
		volley_hits = keep


func _chamber_blocked(p: ST.Projectile, dt: float) -> bool:
	for c in sim.chambers:
		if c.ended or p.realm == str(c.id):
			continue
		var q: = p.pos + p.vel * dt
		var closest: = Geometry2D.get_closest_point_to_segment(c.center, p.pos, q)
		if closest.distance_to(c.center) < 112.0:
			return true
	return false


func _return_leg(p: ST.Projectile) -> void :
	p.returning = true
	p.leg += 1
	p.distance = 0.0
	p.hit_ids.clear()
	if p.wing:
		p.effects = sim.scale_damage(p.effects, 0.7)


func _end(p: ST.Projectile, reason: String) -> void :
	p.dead = true
	if p.wing:
		var u: = sim.u_at(p.source_idx)
		if u and u.is_hero:
			u.ks.wing_mode = "orbit" if reason == "returned" else "recovering"
			u.ks.wing_due = sim.time + (0.0 if reason == "returned" else 0.5)
	sim.emit("PROJECTILE_END", p.source_idx, p.target_idx, {"id": p.id, "reason": reason, "pos": p.pos})


func resolve_defense(p: ST.Projectile, t: BUnit) -> Dictionary:
	if not t.alive:
		return {"blocked": true, "scale": 0.0}
	# V2 achilles front guard: a projectile arriving inside the guarded arc
	# (it travels toward the guard, i.e. comes from -vel) is consumed.
	var fg: ST.Status = sim.get_status(t, &"frontGuard") if t.is_hero and not t.statuses.is_empty() else null
	if fg and p.team != sim.eteam(t) and p.vel.length_squared() > 1e-06 and sim.guard_faces(fg, t.pos, t.pos - p.vel.normalized() * 100.0):
		sim.emit("PROJECTILE_BLOCKED", t.idx, p.source_idx, {"reason": "front_guard", "pos": p.pos})
		sim.emit("FRONT_BLOCKED", p.source_idx, t.idx, {"kind": "projectile", "ability": p.ability if not p.basic else null, "pos": t.pos})
		return {"blocked": true, "scale": 0.0}
	var g: = sim.get_buff(t, &"projectileGuard")
	if g == null:
		return {"blocked": false, "scale": 1.0}
	var red: = clampf(float(g.extra.get("reduction", g.amount)), 0.0, 1.0)
	var refl: = float(g.extra.get("reflect", 0.0))
	if refl > 0.0:
		reflect(p, t, refl)
	if red >= 1.0:
		sim.emit("PROJECTILE_BLOCKED", t.idx, p.source_idx, {"reason": "guard", "pos": p.pos})
		return {"blocked": true, "scale": 0.0}
	return {"blocked": false, "scale": 1.0 - red}


func reflect(p: ST.Projectile, defender: BUnit, scale: float) -> void :
	if p.reflection_count >= 6:
		return
	var src: = sim.u_at(p.source_idx)
	if src == null:
		return
	var dir: = (src.pos - p.pos)
	dir = dir.normalized() if dir.length_squared() > 1e-06 else - p.vel.normalized()
	var q: = ST.Projectile.new()
	q.id = sim.next_id()
	q.source_idx = defender.idx
	q.shooter_idx = defender.idx
	q.team = sim.eteam(defender)
	q.pos = p.pos + dir * (p.radius + 1.0)
	q.prev_pos = p.pos
	q.launch_pos = p.pos
	q.vel = dir * p.speed
	q.speed = p.speed
	q.target_idx = src.idx
	q.target_pos = src.pos
	q.homing = true
	q.radius = p.radius
	q.max_distance = maxf(260.0, p.max_distance)
	q.bounces = 0
	q.pierce = 0
	q.ability = p.ability
	q.source_type = "REFLECTION"
	q.effects = sim.scale_damage(p.effects.duplicate(true), scale)
	q.ctx = p.ctx.duplicate()
	q.ctx["reflected"] = true
	q.ctx["proc"] = true
	q.ctx["basic"] = false
	q.ctx["source_type"] = "REFLECTION"
	q.ctx["team"] = q.team
	q.reflected = true
	q.reflection_count = p.reflection_count + 1
	q.color = p.color
	q.pattern = p.pattern
	q.born_at = sim.time
	q.realm = p.realm
	list.append(q)
	sim.emit("PROJECTILE_REFLECTED", defender.idx, src.idx, {"id": q.id, "pos": p.pos, "scale": scale})


func _bat_intercept(p: ST.Projectile, t: BUnit) -> void :
	var src: = sim.u_at(p.source_idx)
	var own: = 0.7 * (1.0 - clampf(float(sim.get_buff(t, &"projectileGuard").amount) if sim.get_buff(t, &"projectileGuard") else 0.0, 0.0, 1.0))
	var c: = p.ctx.duplicate()
	c["reflected"] = true
	c["proc"] = true
	c["source_type"] = "PROJECTILE_PARRY_COST"
	c["basic"] = false
	if src:
		for f in sim.scale_damage(_damage_only(p.effects), own):
			sim.apply_damage(src, t, f, c)
	reflect(p, t, 0.7)
	sim.emit("PASSIVE", t.idx, p.source_idx, {"rule": "projectile_reflect_arc", "detail": "배트 반사", "pos": p.pos})
	sim.fx("parry", p.pos, {"color": t.def.accent})


func _damage_only(effects: Array) -> Array:
	var out: Array = []
	for f in effects:
		if str(f.get("type", "")) == "damage":
			out.append(f)
	return out


func area_impact(p: ST.Projectile, at: Vector2) -> void :
	if p.area_resolved:
		return
	p.area_resolved = true
	var s: = sim.u_at(p.source_idx)
	if s == null:
		return
	var a: = p.ability
	var r: = float(p.ctx.get("impact_radius", 0.0))
	if r <= 0.0:
		r = maxf(35.0, p.radius * 2.0)
	var c: = p.ctx.duplicate()
	c["hit_pos"] = at
	c["projectile_area"] = true
	c["team"] = p.team
	c["source_type"] = p.source_type
	if a and a.flag("originConeImpact", false):
		var dir: = p.vel.normalized() if p.vel.length_squared() > 1e-06 else Vector2.RIGHT
		var cands: Array[BUnit] = []
		for u in sim.bodies_alive():
			if sim.eteam(u) != p.team:
				cands.append(u)
		var effs: Array = []
		for f in p.effects:
			if not (str(f.get("type", "")) in ["zone", "move_self"]):
				effs.append(f)
		for t in sim.query_cone(at, dir, r, a.angle if a.angle > 0.0 else 1.4, cands):
			var g: = sim.get_buff(t, &"projectileGuard")
			var scale: = 1.0 - clampf(float(g.extra.get("reduction", g.amount)) if g else 0.0, 0.0, 1.0)
			sim.apply_effects(s, t, sim.scale_damage(effs, scale), c)
		sim.fx("cone", at, {"dir": dir, "range": r, "angle": a.angle, "ability": a, "impact": true, "source": p.source_idx})
	else:
		sim.resolve_area(s, at, r, p.effects, c)
	sim.fx("explosion", at, {"radius": r, "color": p.color, "ability": a, "pattern": p.pattern, "source": p.source_idx})
	sim.emit("PROJECTILE_IMPACT", p.source_idx, -1, {"id": p.id, "pos": at, "radius": r})




static func sweep_capsule(a: Vector2, b: Vector2, c: Vector2, d: Vector2, r: float) -> float:
	if Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a) <= r:
		return 0.0
	var v: = d - c
	var ln: = v.length()
	if ln < 1e-09:
		return Arena.seg_circle_t(a, b, c, r)
	var n: = Vector2( - v.y, v.x) / ln
	var best: = 2.0
	for cand in [Arena.seg_circle_t(a, b, c, r), Arena.seg_circle_t(a, b, d, r)]:
		if cand >= 0.0 and cand < best:
			best = cand
	for sgn in [-1.0, 1.0]:
		var o: Vector2 = n * r * sgn
		var hit = Geometry2D.segment_intersects_segment(a, b, c + o, d + o)
		if hit != null:
			var tt: = ((hit as Vector2) - a).length() / maxf(1e-09, (b - a).length())
			if tt < best:
				best = tt
	return best if best <= 1.0 else -1.0


static func sector_entry(a: Vector2, b: Vector2, center: Vector2, r: float, heading: Vector2, ang: float, pad: float) -> float:
	var inside: = func(pt: Vector2) -> bool:
		var v: = pt - center
		var d: = v.length()
		if d > r + pad:
			return false
		if d <= pad:
			return true
		return v.normalized().dot(heading) >= cos(ang * 0.5 + asin(minf(1.0, pad / maxf(d, 1.0))))
	if inside.call(a):
		return 0.0
	var half: = ang * 0.5
	var cands: Array = []
	for x in [Arena.seg_circle_t(a, b, center, r + pad), sweep_capsule(a, b, center, center + heading.rotated(half) * r, pad), sweep_capsule(a, b, center, center + heading.rotated( - half) * r, pad), 1.0]:
		if float(x) >= 0.0:
			cands.append(float(x))
	cands.sort()
	for tt in cands:
		var pt: = a.lerp(b, minf(1.0, tt + 1e-07))
		if inside.call(pt):
			return tt
	return -1.0
