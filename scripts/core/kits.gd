class_name Kits
extends RefCounted



# "whip" is torturer information warfare (InformationWarfare.ACTIONS runs first).
const NEXUS_ACTIONS: = ["plantTree", "plantFlowers", "rootGarden", "thornGarden", "rapture", "cripple", "chamber", "turret", "upgrade", "detonate", "driver"]
const MOBILITY_ACTIONS: = ["glide", "cloak", "wallRun", "pointBlink", "rescuePull", "rescueFlight", "portalPair"]
const S_AD: = &"attackDamage"
const S_AP: = &"abilityPower"
const S_HP: = &"maxHealth"
const S_MS: = &"moveSpeed"
const S_AS: = &"attackSpeed"

var sim: BattleSim


func _init(s: BattleSim) -> void :
	sim = s






func init_unit(u: BUnit) -> void :
	var d: = u.def
	for p in d.passives:
		for r in p.get("rules", []):
			if r.has("resourceKey"):
				u.resources[str(r.resourceKey)] = 0.0
	var k: = u.ks
	k["fish"] = []
	k["fish_next"] = sim.time + 8.0
	k["borrow_next"] = sim.time + 12.0
	k["borrowed"] = {}
	k["rage_rem"] = 0.0
	k["rage_decay_at"] = 0.0
	k["wall_bonus"] = 0
	k["wall_near"] = false
	k["wall_until"] = -1.0
	k["wall_rearm"] = 0.0
	k["wing_angle"] = float(u.slot) * 0.7
	k["wing_cycles"] = [{}, {}]
	k["wing_hit_at"] = {}
	k["wing_mode"] = "orbit"
	k["wing_due"] = 0.0
	k["wing_pos"] = []
	k["portal_armed_until"] = 0.0
	k["portal_enhanced"] = false
	k["regen_hits"] = []
	k["growth_total"] = 0.0
	k["growth_next"] = 0.0
	k["growth_by_cast"] = {}
	k["cdr_keys"] = {}
	k["cdr_window"] = []
	k["blade_hits"] = {}
	k["cloak_until"] = 0.0
	k["cloak_ready_at"] = 0.0
	k["glide_until"] = 0.0
	k["reveal_at"] = sim.time + float(d.rule("reveal_cooldowns").get("interval", 7.0))
	k["seeds"] = []
	k["last_seed"] = null
	k["withdrawal_at"] = sim.time + 10.0
	k["pain_at"] = {}
	k["rapture_until"] = 0.0
	k["rapture_stacks"] = 0
	k["witness_at"] = -10.0
	k["frustration"] = 0
	k["explode_at"] = 0.0
	k["bat"] = {}
	k["apple"] = {}
	k["virtual"] = {}
	if d.id == "fisherman":
		u.resources["fish"] = 0.0
	if d.id == "nitro":
		u.resources["rage"] = 0.0
	if d.id == "dimensionalist":
		u.resources["shards"] = 0.0
	if d.id == "plague_doctor":
		u.resources["healBank"] = 0.0
	if d.id == "engineer":
		u.resources["frustration"] = 0.0
	if d.id == "politician":
		u.resources["distrust"] = 0.0
		k["contemplating"] = false
		k["contemplation_time"] = 0.0
		k["contemplation_pos"] = u.pos
	# V2 entity passives spawn lazily in update_passives (never here: respawn
	# modes call init_unit again and kill_unit may be iterating entities).
	if d.has_rule("companion"):
		k["pet_idx"] = -1
		k["pet_ready_at"] = 0.0
	if d.has_rule("fuel_tank"):
		k["tank_idx"] = -1
		k["tank_ready_at"] = 0.0
	# V2 torquemada S2 remembers who crowd-controlled this hero (self-knowledge).
	for a in d.abilities:
		if (a as Defs.AbilityDef).condition.has("ccSourceWithin"):
			k["cc_by"] = {}
			break


func virtual_abilities(u: BUnit) -> Array:
	if not u.is_hero:
		return []
	var out: Array = []
	var cache: Dictionary = u.ks.virtual
	var fish: Array = u.ks.fish
	if not fish.is_empty():
		var key: = "eat:" + str(fish[0].type)
		var a: Defs.AbilityDef = cache.get(key)
		if a == null:
			a = _virtual_base(u, "eat", "어획 섭취")
			a.description = "보관한 물고기 하나를 먹는다 (%s)." % {"attack": "공격력 +12%", "defense": "방어/마저 +16%", "health": "최대 체력 +10%"}.get(str(fish[0].type), "")
			a.cast_time = 0.12
			a.recovery = 0.16
			cache[key] = a
		out.append(a)
	var b: Dictionary = u.ks.borrowed
	if not b.is_empty() and float(b.expires) > sim.time:
		var key2: = "borrow:" + str(b.id)
		var a2: Defs.AbilityDef = cache.get(key2)
		if a2 == null:
			var src: Defs.AbilityDef = b.ability
			a2 = src.duplicate_def()
			a2.virtual = true
			a2.virtual_kind = "borrow"
			a2.name = "차용 · " + src.name
			a2.id = "borrow_%d" % int(b.id)
			a2.donor_idx = int(b.owner)
			a2.cooldown = 0.0
			cache.clear()
			cache[key2] = a2
		out.append(a2)
	if u.def.id == "baseball":
		var a3: Defs.AbilityDef = cache.get("parry")
		if a3 == null:
			a3 = _virtual_base(u, "parry", "수비 스윙")
			a3.target = "position"
			a3.range = 400.0
			a3.cast_time = 0.08
			a3.recovery = 0.16
			a3.description = "다가오는 투사체를 향해 배트를 휘둘러 반사한다."
			cache["parry"] = a3
		out.append(a3)
	return out


func _virtual_base(u: BUnit, kind: String, nm: String) -> Defs.AbilityDef:
	var a: = Defs.AbilityDef.new()
	a.virtual = true
	a.virtual_kind = kind
	a.id = "virtual_" + kind
	a.char_id = u.def.id
	a.slot = 0
	a.name = nm
	a.target = "self"
	a.delivery = "self"
	a.range = 0.0
	a.cooldown = 0.0
	a.color = u.def.accent
	return a


func virtual_ready(u: BUnit, a: Defs.AbilityDef) -> bool:
	match a.virtual_kind:
		"eat":
			return not (u.ks.fish as Array).is_empty() and sim.can_cast(u)
		"borrow":
			var b: Dictionary = u.ks.borrowed
			if b.is_empty() or float(b.expires) <= sim.time or not sim.can_cast(u):
				return false
			# The borrowed ability keeps its own self conditions (e.g. nitro's
			# wall ignition needs a wall) exactly like BattleSim.ability_ready.
			var c: Dictionary = a.condition
			if c.has("selfResource") and not sim.resource_waived(u, c.selfResource) and float(u.resources.get(str(c.selfResource.key), 0)) < float(c.selfResource.min):
				return false
			if c.get("nearWall", false) and sim.distance_to_wall(u.pos) > sim.radius(u) + 4.0:
				return false
			return extra_ready(u, a)
		"parry":
			return sim.can_basic(u)
	return false


func start_virtual(u: BUnit, _i: int, a: Defs.AbilityDef, _t: BUnit, _aim: Vector2) -> void :
	if a.virtual_kind == "borrow":
		u.ks.borrowed = {}
	elif a.virtual_kind == "parry":
		u.attack_ready_at = sim.time + 1.0 / maxf(0.2, sim.stat(u, S_AS))


func extra_ready(u: BUnit, a: Defs.AbilityDef) -> bool:
	# V2 war_machine overdrive locks every slot but S1.
	if a.slot != 1 and not u.statuses.is_empty() and sim.has_status(u, &"overdrive"):
		return false
	match a.action:
		"portalArming":
			for pp in sim.portal_pairs:
				if pp.source == u.idx and float(pp.end) > sim.time:
					return true
			return false
		"rootGarden", "thornGarden":
			for g in sim.gardens:
				if g.source == u.idx and float(g.end) > sim.time:
					return true
			return false
		"detonate":
			for tw in owned_entities(u, "turret"):
				if tw.pos.distance_to(u.pos) <= a.range:
					return true
			return false
		"upgrade":
			for tw in owned_entities(u, "turret"):
				if tw.level < 3 and tw.pos.distance_to(u.pos) <= 100.0:
					return true
			return false
	return true


func cooldown_for(u: BUnit, a: Defs.AbilityDef) -> float:
	var item_mult: float = sim.deathmatch.cooldown_mult(u) if sim.deathmatch else 1.0
	if a.action == "turret":
		var r: = u.def.rule("nexus_workshop")
		return maxf(float(r.get("minCooldown", 7.2)), a.cooldown - float(r.get("secondsPerStack", 0.8)) * int(u.ks.frustration)) * item_mult
	return a.cooldown * item_mult


# V2 charged cast (flag originCharge {min, max, base, perStep, slow}): the
# charge N comes from the command's extra.charge (AI-planned), default as much
# as the resource allows. Cast time = base + perStep * (N - min).
func charge_count(u: BUnit, a: Defs.AbilityDef, extra: Dictionary) -> int:
	var ch: Dictionary = a.flag("originCharge", {})
	if ch.is_empty():
		return maxi(1, a.count)
	var lo: = int(ch.get("min", 2))
	var hi: = int(ch.get("max", 6))
	var have: = hi
	var key: = str(ch.get("resource", ""))
	if key != "":
		have = int(floor(float(u.resources.get(key, 0)) + 1e-06))
	var n: = int(extra.get("charge", mini(hi, have)))
	return clampi(n, lo, hi)


func cast_time_for(u: BUnit, a: Defs.AbilityDef, extra: Dictionary) -> float:
	var ch: Dictionary = a.flag("originCharge", {})
	if ch.is_empty():
		return a.cast_time
	return float(ch.get("base", a.cast_time)) + float(ch.get("perStep", 0.3)) * (charge_count(u, a, extra) - int(ch.get("min", 2)))


# V2: the ability's own resource costs are free (originFreeInOverdrive).
func cost_waived(u: BUnit, a: Defs.AbilityDef) -> bool:
	return bool(a.flag("originFreeInOverdrive", false)) and sim.has_status(u, &"overdrive")


# V2 concealment (hades): invisible, standing in active brush, or no enemy body
# that u's team currently sees observes u. Team knowledge only (info-fair).
func concealed(u: BUnit) -> bool:
	if u == null or not u.alive:
		return false
	if sim.has_status(u, &"invisible"):
		return true
	if sim.brush_on and not sim.arena.forest_x.is_empty() and sim.arena.forest_at(u.pos) >= 0:
		return true
	var team: = sim.eteam(u)
	for e in sim.bodies_alive():
		if sim.eteam(e) != team and sim.is_seen(team, e) and sim.observes(e, u):
			return false
	return true


func validate_aim(u: BUnit, a: Defs.AbilityDef, _t: BUnit, aim: Vector2, extra: Dictionary) -> bool:
	var ch: Dictionary = a.flag("originCharge", {})
	if not ch.is_empty():
		var n: = int(extra.get("charge", charge_count(u, a, extra)))
		if n < int(ch.get("min", 2)) or n > int(ch.get("max", 6)):
			return false
		var key: = str(ch.get("resource", ""))
		if key != "" and not cost_waived(u, a) and float(u.resources.get(key, 0)) + 1e-06 < float(n):
			return false
	if a.action == "portalPair":
		var first: Vector2 = extra.get("portal_a", u.pos)
		var second: Vector2 = extra.get("portal_b", aim)
		if u.pos.distance_to(first) > a.range + 1e-06 or u.pos.distance_to(second) > a.range + 1e-06:
			return false
		var p: = sim.clamp_pos(first, 22.0)
		var q: = sim.clamp_pos(second, 22.0)
		if u.pos.distance_to(p) > a.range + 1e-06 or u.pos.distance_to(q) > a.range + 1e-06 or p.distance_to(q) < 140.0 - 1e-06:
			return false
	return true


func placement_legal(_u: BUnit, a: Defs.AbilityDef, p: Vector2) -> bool:
	if not (a.action in ["plantTree", "plantFlowers", "turret"]):
		return true
	var r: = 25.0 if a.action == "plantTree" else (9.0 if a.action == "plantFlowers" else 18.0)
	for c in sim.chambers:
		if c.ended:
			continue
		if sim.clamp_pos(p, r).distance_to(c.center) < 112.0 + r:
			return false
	return true


func owned_entities(u: BUnit, kind: String) -> Array[BUnit]:
	var out: Array[BUnit] = []
	for e in sim.entities:
		if e.alive and e.owner_idx == u.idx and e.kind == kind and e.end_time > sim.time:
			out.append(e)
	return out


func break_stealth(u: BUnit) -> void :
	u.last_combat_time = sim.time
	sim.remove_statuses_where(u, func(x): return x.type == &"invisible")
	u.ks.cloak_until = 0.0
	sim.remove_buffs_tag(u, "cloakSpeed")


func hermes_recast(u: BUnit, a: Defs.AbilityDef) -> void :
	sim.remove_statuses_where(u, func(x): return x.type == &"invisible" and x.source_idx == u.idx)
	sim.remove_buffs_tag(u, "cloakSpeed")
	u.ks.cloak_until = 0.0
	var ctx: = sim.context(u, a, {"recast": true})
	for e in sim.opponents(u):
		if u.pos.distance_to(e.pos) <= 90.0 + sim.radius(e) and sim.los(u.pos, e.pos, 1.0):
			sim.apply_status(u, e, {"status": "stun", "duration": 0.5, "originExactDuration": true}, ctx)
	sim.emit("ABILITY_RECAST", u.idx, -1, {"ability": a, "pos": u.pos})
	sim.fx("pulse", u.pos, {"radius": 90.0, "color": a.color, "ability": a})






func ability_radius(s: BUnit, a: Defs.AbilityDef) -> float:
	if _tree_has(a.effects, "scaleWithRadius"):
		return a.radius * sim.radius_scale(s)
	return a.radius


func _tree_has(effects: Array, key: String) -> bool:
	for f in effects:
		if f.get(key, false):
			return true
		if f.has("effects") and _tree_has(f.effects, key):
			return true
	return false


func _pay(s: BUnit, a: Defs.AbilityDef, ctx: Dictionary) -> bool:
	if not sim.can_pay(s, a):
		return false
	var bonus: = 0.0
	var free: = cost_waived(s, a)
	for f in a.effects:
		var ty: = str(f.get("type", ""))
		if free and ty == "consume_resource":
			continue
		if ty == "self_damage":
			var before: = s.hp
			s.hp = maxf(1.0, before - maxf(1.0, before * float(f.ratio)))
			var cost: = before - s.hp
			s.st_health_cost += cost
			sim.emit("HEALTH_COST", s.idx, s.idx, {"amount": cost, "pos": s.pos, "ability": a})
		elif ty == "consume_resource":
			var key: = str(f.key)
			var have: = float(s.resources.get(key, 0))
			var want: = float(f.amount)
			# V2: perProjectile costs scale with the charged projectile count.
			if f.get("perProjectile", false):
				want *= charge_count(s, a, ctx.get("extra", {}))
			var n: = minf(have, want)
			if not f.get("optional", false) and n < want:
				return false
			if key == "fish":
				var fish: Array = s.ks.fish
				if fish.size() < int(n):
					return false
				for _i in int(n):
					fish.pop_front()
				s.ks.fish = fish
				s.resources["fish"] = float(fish.size())
			else:
				s.resources[key] = have - n
			bonus += float(f.get("bonusDamage", 0.0)) * (1.0 if n > 0.0 else 0.0) + float(f.get("bonusDamagePerSpent", 0.0)) * n
			sim.emit("RESOURCE_CHANGED", s.idx, s.idx, {"key": key, "amount": - n, "value": s.resources.get(key, 0)})
	ctx["bonus"] = bonus
	return true


func execute_ability(s: BUnit, act: ST.Action) -> void :
	var a: = act.ability
	if a == null:
		return
	if a.action in InformationWarfare.ACTIONS:
		sim.warfare.execute(s, act)
		return
	if a.virtual:
		_execute_virtual(s, act)
		return
	if a.action in NEXUS_ACTIONS:
		_execute_nexus(s, act)
		return
	_execute_origin(s, act, a, s)


func _execute_origin(s: BUnit, act: ST.Action, a: Defs.AbilityDef, _caster: BUnit) -> void :
	var t: = sim.u_at(act.target_idx)
	var p: Vector2 = t.pos if (a.delivery == "direct" and t and t.alive) else act.target_pos
	var ctx: = sim.context(s, a, {"action_id": act.id, "target_pos": p, "team": act.source_team, "extra": act.extra, "resources": act.resources})
	if (a.target == "enemy" or a.target == "ally") and (t == null or not t.alive or not sim.target_legal(s, a, t)):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "target_changed"})
		return
	if not validate_aim(s, a, t, p, act.extra) or not sim.check_condition(s, t, a.condition) or not _pay(s, a, ctx):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "condition_changed"})
		return
	sim.emit("CAST_COMPLETED", s.idx, act.target_idx, {"ability": a, "pos": p, "from": s.pos})
	_on_cast_completed(s)
	var effects: Array = []
	for f in a.effects:
		var ty: = str(f.get("type", ""))
		if ty != "consume_resource" and ty != "self_damage":
			effects.append(f)
	sim.fx("cast", s.pos, {"ability": a, "to": p, "source": s.idx})
	match a.action:
		"contactDash":
			var dir: = (p - s.pos).normalized() if p.distance_squared_to(s.pos) > 1e-06 else s.facing
			var dist: = float(a.flag("originDistance", a.range))
			var hits: Array = []
			for f in effects:
				if str(f.get("type", "")) != "move_self":
					hits.append(f)
			begin_motion(s, s.pos + dir * dist, a.speed, "contactDash", ctx, {"hit_effects": hits, "unstoppable": bool(a.flag("originUnstoppable", false))})
			return
		"pointBlink":
			var delta: = p - s.pos
			var end: = sim.clamp_pos(s.pos + delta.normalized() * minf(a.range, delta.length()), sim.radius(s))
			var from: = s.pos
			s.pos = end
			sim.warfare.constrain(s, from)
			s.prev_pos = s.pos
			s.vel = Vector2.ZERO
			for f in effects:
				if str(f.get("type", "")) != "move_self":
					sim.apply_effect(s, s, f, ctx)
			sim.emit("BLINKED", s.idx, s.idx, {"from": from, "to": s.pos, "ability": a})
			return
		"bed":
			for prev in owned_entities(s, "bed"):
				prev.alive = false
				prev.end_time = sim.time
				for z in sim.zones.list:
					if z.data.get("entity", -1) == prev.idx:
						z.end = sim.time
			var bed: = create_entity(s, p, "bed", 300.0 + 0.8 * sim.stat(s, S_AP), 25.0, ctx, {"duration": 18.0, "armor": 20.0, "structure": true})
			bed.ks["bed"] = {"entries": {}, "pairs": {}, "odd": {}, "next_heal": sim.time}
			var z: = sim.zones.spawn(s, p, 90.0, 18.0, 0.25, [], "ally", ctx, "bed", {"entity": bed.idx})
			z.pattern = "loveBed"
			return
		"rescuePull":
			if t == null or t == s:
				return
			var dirp: = (t.pos - s.pos).normalized() if t.pos.distance_squared_to(s.pos) > 1e-06 else Vector2.RIGHT
			var endp: = s.pos + dirp * (sim.radius(s) + sim.radius(t) + 6.0)
			begin_motion(t, endp, 650.0, "rescuePull", ctx, {"invulnerable": true, "source": s.idx, "target": t.idx})
			return
		"rescueFlight":
			if t == null or t == s:
				return
			var dirf: = (s.pos - t.pos).normalized() if t.pos.distance_squared_to(s.pos) > 1e-06 else Vector2.LEFT
			begin_motion(s, t.pos + dirf * (sim.radius(s) + sim.radius(t) + 6.0), 620.0, "rescueFlight", ctx, {"flight": true, "target": t.idx})
			return
		"apple":
			if t == null:
				return
			var best: BUnit = null
			for e in sim.opponents(t):
				if e.is_hero and sim.observes(t, e):
					if best == null or e.hp < best.hp:
						best = e
			if best == null:
				return
			t.ks.apple = {"target": best.idx, "pos": best.pos, "until": sim.time + 3.0}
			sim.add_buff(t, S_MS, 0.9, 3.0, s.idx, {"tag": a.id})
			sim.apply_status(s, t, {"status": "frenzy", "duration": 3.0}, ctx)
			support_credit(s, t, t.base_ms * 0.9, ctx)
			return
		"bloodLink":
			for f in effects:
				sim.apply_effect(s, t, f, ctx)
			return
		"bait":
			var bz: = sim.zones.spawn(s, p, 90.0, 6.0, 0.1, [], "enemy", ctx, "bait", {"triggered": {}, "lure": {}})
			bz.pattern = "baitTrap"
			return
		"swapBox":
			var home: = s.pos
			for f in effects:
				if str(f.get("type", "")) != "zone":
					sim.apply_effect(s, t, f, ctx)
			sim.fx("box", home, {"color": a.color})
			return
		"consumeConfusion":
			var mark: = sim.owned_status(t, &"confusion", s.idx)
			if mark == null:
				return
			var c2: = ctx.duplicate()
			c2["consume"] = true
			c2["explicit_confusion"] = true
			var eff2: Array = []
			for f in effects:
				if str(f.get("type", "")) != "consume_status":
					eff2.append(f)
			for f in eff2:
				sim.apply_effect(s, t, f, c2)
			t.statuses.erase(mark)
			return
		"glide":
			s.ks.glide_until = sim.time + 1.2
			sim.add_buff(s, S_MS, 0.6, 1.2, s.idx, {"tag": a.id})
			sim.add_buff(s, &"armor", 0.3, 1.2, s.idx, {"tag": a.id})
			sim.add_buff(s, &"magicResistance", 0.3, 1.2, s.idx, {"tag": a.id})
			var land: Array = []
			for f in effects:
				if str(f.get("type", "")) != "buff":
					land.append(f)
			sim.schedule(1.2, {"kind": "land", "source": s.idx, "effects": land, "radius": 110.0, "ctx": ctx})
			return
		"plagueCone":
			var dirc: = (p - s.pos).normalized() if p.distance_squared_to(s.pos) > 1e-06 else s.facing
			var cz: Dictionary = {}
			var direct: Array = []
			for f in effects:
				if str(f.get("type", "")) == "zone":
					cz = f
				else:
					direct.append(f)
			var c3: = ctx.duplicate()
			c3["direction"] = dirc
			c3["area"] = true
			for e in sim.query_cone(s.pos, dirc, a.range, a.angle, sim.opponents(s)):
				sim.apply_effects(s, e, direct, c3)
			if not cz.is_empty():
				var z2: = sim.zones.spawn(s, s.pos, a.range, float(cz.get("duration", 3.0)), float(cz.get("interval", 0.75)), cz.get("effects", []), "enemy", c3, "cone", {})
				z2.shape = "cone"
				z2.dir = dirc
				z2.range = a.range
				z2.angle = a.angle
				z2.next_tick = sim.time + z2.interval
				z2.pattern = "plagueCloud"
			sim.fx("cone", s.pos, {"dir": dirc, "range": a.range, "angle": a.angle, "ability": a, "source": s.idx})
			return
		"healingMist":
			var q: = minf(float(s.resources.get("healBank", 0.0)), 360.0 + 2.0 * sim.stat(s, S_AP))
			if q <= 0.0:
				return
			s.resources["healBank"] = float(s.resources.get("healBank", 0.0)) - q
			var dirm: = (p - s.pos).normalized() if p.distance_squared_to(s.pos) > 1e-06 else s.facing
			var mz: = sim.zones.spawn(s, s.pos, a.radius, 3.0, 0.25, [], "ally", ctx, "mist", {"budget": q, "initial": q, "distance": 0.0, "range": a.range, "speed": a.speed, "healed": 0.0})
			mz.dir = dirm
			mz.next_tick = sim.time + 0.25
			mz.pattern = "mist"
			return
		"wallRun":
			var side_sgn: = -1.0 if sim.wall_tangent(s.pos).dot(s.facing) < 0.0 else 1.0
			s.ks.wall_run_until = sim.time + 1.2
			s.ks.wall_run_sign = side_sgn
			return
		"rift":
			var enhanced: = float(act.resources.get("shards", 0.0)) >= 30.0
			# A self-cast rift opens toward the commanded point when one was given
			# (aim != caster position at cast start); otherwise along the facing.
			var dirr: = s.facing
			var origin: Vector2 = act.extra.get("cast_origin", s.pos)
			if act.target_pos.is_finite() and act.target_pos.distance_to(origin) > 1.0:
				dirr = (act.target_pos - origin).normalized()
				s.facing = dirr
			var tang: = Vector2( - dirr.y, dirr.x)
			var center: = s.pos + dirr * (sim.radius(s) + 22.0)
			var rz: = sim.zones.spawn(s, center, 80.0, 3.0, 1.0, [], "enemy", ctx, "rift", {"a": center - tang * 80.0, "b": center + tang * 80.0, "reflect": 0.3 if enhanced else 0.0})
			rz.pattern = "rift"
			if enhanced and not a.virtual:
				s.cooldowns[a.index] = maxf(sim.time + 1.0, s.cooldowns[a.index] - 8.0)
			return
		"portalPair":
			var first: = sim.clamp_pos(act.extra.get("portal_a", s.pos), 22.0)
			var second: = sim.clamp_pos(act.extra.get("portal_b", p), 22.0)
			if first.distance_to(second) < 140.0:
				return
			var enh: = float(act.resources.get("shards", 0.0)) >= 20.0
			var keep: Array = []
			for pp in sim.portal_pairs:
				if pp.source == s.idx:
					for z in sim.zones.list:
						if z.data.get("pair", -1) == pp.id:
							z.end = sim.time
				else:
					keep.append(pp)
			var pair: = {"id": sim.next_id(), "source": s.idx, "team": act.source_team, "a": first, "b": second, "radius": 22.0, "end": sim.time + 10.0, "enhanced": enh, "ctx": ctx}
			keep.append(pair)
			sim.portal_pairs = keep
			for ends in [[first, second], [second, first]]:
				var pz: = sim.zones.spawn(s, ends[0], 22.0, 10.0, 1.0, [], "ally", ctx, "portal", {"pair": pair.id, "target": ends[1]})
				pz.pattern = "portal"
			if enh and not a.virtual:
				s.cooldowns[a.index] = maxf(sim.time + 1.0, s.cooldowns[a.index] - 4.0)
			return
		"portalArming":
			s.ks.portal_armed_until = sim.time + 5.0
			s.ks.portal_enhanced = float(act.resources.get("shards", 0.0)) >= 10.0
			return
		"cloak":
			s.ks.cloak_until = sim.time + 2.2
			s.ks.cloak_ready_at = sim.time + 0.25
			sim.apply_status(s, s, {"status": "invisible", "duration": 2.2}, ctx)
			sim.add_buff(s, S_MS, 0.35, 2.2, s.idx, {"tag": "cloakSpeed"})
			return
	if a.flag("originWing", false):
		s.ks.wing_mode = "outbound"
		s.ks.wing_due = sim.time + 2.6
	_deliver(s, t, p, a, effects, ctx)


func _deliver(s: BUnit, t: BUnit, p: Vector2, a: Defs.AbilityDef, effects: Array, ctx: Dictionary) -> void :
	match a.delivery:
		"projectile":
			var impact: Array = []
			var source_fx: Array = []
			for f in effects:
				var ty: = str(f.get("type", ""))
				if f.get("selfOnly", false) or ty == "projectile_guard" or (ty == "move_self" and str(f.get("mode", "")) != "dashToImpact"):
					source_fx.append(f)
				else:
					impact.append(f)
			var c2: = ctx.duplicate()
			c2["hit_pos"] = p
			for f in source_fx:
				sim.apply_effect(s, s, f, c2)
			var opts: = {}
			var scale: = 1.0
			if a.flag("originScaledProjectile", false):
				scale = sim.radius_scale(s)
				opts["radius"] = float(a.flag("originProjectileRadius", 12.0)) * scale
				opts["impact_radius"] = a.radius * scale
			opts["explode"] = a.target in ["position", "position_ally"] or a.flag("originConeImpact", false) or a.flag("originCoins", false) or a.flag("originScaledProjectile", false) or s.def.id == "nitro"
			opts["wing"] = a.flag("originWing", false)
			var n: = maxi(1, a.count)
			if a.flags.has("originCharge"):
				n = charge_count(s, a, ctx.get("extra", {}))
			var base_dir: = (p - s.pos).normalized() if p.distance_squared_to(s.pos) > 1e-06 else s.facing
			var dist: = s.pos.distance_to(p)
			if dist < 1.0:
				dist = a.range
			for i in n:
				var dir: = base_dir.rotated((i - (n - 1) * 0.5) * a.spread)
				sim.proj.spawn(s, t, s.pos + dir * dist, a, impact, ctx, opts)
		"cone":
			var dirc: = (p - s.pos).normalized() if p.distance_squared_to(s.pos) > 1e-06 else s.facing
			var direct: Array = []
			var other: Array = []
			for f in effects:
				if str(f.get("type", "")) in ["zone", "move_self", "delayed_area"]:
					other.append(f)
				else:
					direct.append(f)
			var c3: = ctx.duplicate()
			c3["direction"] = dirc
			for e in sim.query_cone(s.pos, dirc, a.range, a.angle, sim.opponents(s)):
				var c4: = c3.duplicate()
				c4["hit_pos"] = e.pos
				c4["area"] = true
				sim.apply_effects(s, e, direct, c4)
			var c5: = c3.duplicate()
			c5["hit_pos"] = p
			for f in other:
				sim.apply_effect(s, t, f, c5)
			sim.fx("cone", s.pos, {"dir": dirc, "range": a.range, "angle": a.angle, "ability": a, "source": s.idx})
		"area":
			var center: Vector2 = s.pos if a.target == "self" else p
			sim.resolve_area(s, center, ability_radius(s, a), effects, ctx)
			sim.fx("area", center, {"radius": ability_radius(s, a), "ability": a, "source": s.idx})
		_:
			var c6: = ctx.duplicate()
			c6["hit_pos"] = p
			var tgt: BUnit = s if a.target == "self" else t
			sim.apply_effects(s, tgt, effects, c6)
			if a.target != "self" and tgt:
				sim.fx("direct", tgt.pos, {"ability": a, "from": s.pos, "source": s.idx})


func _on_cast_completed(s: BUnit) -> void :
	var r: = s.def.rule("on_cast_buff")
	if r.is_empty():
		return
	for b in r.get("buffs", []):
		sim.add_buff(s, StringName(str(b.stat)), float(b.amount), float(b.duration), s.idx, {"tag": "passive_cast"})
	sim.emit("PASSIVE", s.idx, s.idx, {"rule": "on_cast_buff", "detail": "시전 가속", "silent": true})


func _execute_virtual(s: BUnit, act: ST.Action) -> void :
	var a: = act.ability
	match a.virtual_kind:
		"eat":
			eat_fish(s, "decision")
			sim.emit("CAST_COMPLETED", s.idx, s.idx, {"ability": a, "pos": s.pos})
		"parry":
			var ctx: = sim.context(s, null, {"action_id": act.id, "basic": true, "source_type": "BASIC_ATTACK"})
			start_bat(s, act.target_pos - s.pos, ctx, sim.freeze_effects(s, null, [{"type": "damage", "school": "physical", "base": 0.0, "ad": 1.0}], true, false))
		"borrow":

			var fake: = act
			_execute_origin(s, fake, a, s)


func eat_fish(s: BUnit, reason: String) -> bool:
	var fish: Array = s.ks.fish
	if fish.is_empty():
		return false
	var f: Dictionary = fish.pop_front()
	s.ks.fish = fish
	s.resources["fish"] = float(fish.size())
	match str(f.type):
		"attack":
			sim.add_buff(s, S_AD, 0.12, 8.0, s.idx, {"tag": "fishAttack"})
		"defense":
			sim.add_buff(s, &"armor", 0.16, 8.0, s.idx, {"tag": "fishDefense"})
			sim.add_buff(s, &"magicResistance", 0.16, 8.0, s.idx, {"tag": "fishDefense"})
		"health":
			sim.add_buff(s, S_HP, 0.1, 8.0, s.idx, {"tag": "fishHealth"})
	sim.emit("PASSIVE", s.idx, s.idx, {"rule": "timed_random_buff", "detail": "물고기 섭취 (%s)" % {"attack": "공격", "defense": "방어", "health": "체력"}.get(str(f.type), ""), "reason": reason})
	sim.fx("fish_eat", s.pos, {"color": s.def.accent})
	return true






func _basic_effects(s: BUnit, t: BUnit, ctx: Dictionary) -> Dictionary:
	var nth: = s.def.rule("nth_basic_bonus")
	var hybrid: = s.def.rule("hybrid_basic")
	s.ks["basic_count"] = int(s.ks.get("basic_count", 0)) + 1
	var melee: = false
	if not hybrid.is_empty() and t:
		melee = s.pos.distance_to(t.pos) <= float(hybrid.meleeRange) + sim.radius(s) + sim.radius(t)
	var effects: Array = [{"type": "damage", "school": "physical", "base": 0.0, "ad": (1.12 if ( not hybrid.is_empty() and not melee) else 1.0), "ap": 0.0}]
	if not nth.is_empty() and int(s.ks.basic_count) % int(nth.get("every", 3)) == 0:
		effects.append((nth.damage as Dictionary).duplicate())
		sim.emit("PASSIVE", s.idx, t.idx if t else -1, {"rule": "nth_basic_bonus", "detail": "세 번째 검세", "pos": t.pos if t else s.pos})
	var crit: = sim.rng.randf() < sim.stat(s, &"critChance")
	ctx["crit"] = crit
	var is_proj: = not melee and sim.stat(s, &"attackRange") > 100.0
	effects = sim.freeze_effects(s, t, effects, true, is_proj)
	if crit:
		effects = sim.scale_damage(effects, sim.stat(s, &"critMultiplier"))
	if not hybrid.is_empty() and melee:
		effects.append({"type": "damage", "school": "true", "base": float(hybrid.get("trueBonus", 12.0)), "frozen": true})
	for key in [&"originSniperRound", &"originPirateRound"]:
		var b: = sim.get_buff(s, key)
		if b:
			for pl in b.extra.get("originPayload", []):
				effects.append((pl as Dictionary).duplicate(true))
			s.buffs.erase(b)
			ctx["primed"] = String(key)
	var keep: Array[ST.Buff] = []
	for b in s.buffs:
		if b.stat != &"nextBasicDamage":
			keep.append(b)
	s.buffs = keep
	return {"effects": effects, "melee": melee if not hybrid.is_empty() else sim.stat(s, &"attackRange") <= 100.0}


func execute_basic(s: BUnit, act: ST.Action) -> void :
	var t: = sim.u_at(act.target_idx)
	var ctx: = sim.context(s, null, {"action_id": act.id, "source_type": "BASIC_ATTACK", "basic": true, "snapshot": true})
	if s.def.id == "baseball":
		var b: = _basic_effects(s, t, ctx)
		start_bat(s, (t.pos - s.pos) if t else s.facing, ctx, b.effects)
		return
	if t == null or not t.alive or not sim.observes(s, t) or sim.eteam(t) == sim.eteam(s):
		sim.emit("MISS", s.idx, act.target_idx, {"reason": "basic_target_lost", "basic": true})
		return
	var b2: = _basic_effects(s, t, ctx)
	sim.emit("ATTACK_RELEASED", s.idx, t.idx, {"pos": t.pos, "from": s.pos, "melee": b2.melee})
	if b2.melee:
		if s.pos.distance_to(t.pos) > sim.stat(s, &"attackRange") + sim.radius(s) + sim.radius(t) + 6.0:
			return
		sim.apply_effects(s, t, b2.effects, ctx)
		sim.fx("strike", t.pos, {"from": s.pos, "color": s.def.accent, "source": s.idx, "crit": ctx.get("crit", false)})
	else:
		var d: = s.pos.distance_to(t.pos)
		var aim: = t.pos + t.vel * (d / 460.0 * 0.45)
		var pa: = Defs.AbilityDef.new()
		pa.speed = 460.0
		pa.range = sim.stat(s, &"attackRange")
		pa.width = 9.0
		pa.color = s.def.accent
		pa.pattern = "basic"
		pa.id = "basic"
		sim.proj.spawn(s, t, aim, pa, b2.effects, ctx, {"basic": true, "prefrozen": true})


func start_bat(s: BUnit, dir: Vector2, ctx: Dictionary, effects: Array) -> void :
	var d: = dir.normalized() if dir.length_squared() > 1e-06 else s.facing
	s.ks.bat = {"until": sim.time + 0.24, "dir": d, "hit": {}, "ctx": ctx, "effects": effects}
	s.facing = d
	sim.fx("bat", s.pos, {"dir": d, "range": 76.0, "angle": deg_to_rad(80.0), "color": s.def.accent, "source": s.idx})






func _execute_nexus(s: BUnit, act: ST.Action) -> void :
	var a: = act.ability
	var t: = sim.u_at(act.target_idx)
	var p: Vector2 = act.target_pos
	var ctx: = sim.context(s, a, {"action_id": act.id, "realm": s.chamber, "team": act.source_team})
	if not s.alive or ((a.target == "enemy" or a.target == "ally") and (t == null or not t.alive or not sim.target_legal(s, a, t))) or not sim.check_condition(s, t, a.condition) or not placement_legal(s, a, p):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "nexus_condition"})
		return
	if t and not sim.realm_allowed(s, t, ctx):
		sim.emit("MISS", s.idx, act.target_idx, {"ability": a, "reason": "isolated"})
		return
	sim.emit("CAST_COMPLETED", s.idx, act.target_idx, {"ability": a, "pos": p, "from": s.pos})
	sim.fx("cast", s.pos, {"ability": a, "to": p, "source": s.idx})
	match a.action:
		"plantTree":
			make_structure(s, a, sim.clamp_pos(p, 25.0), "tree")
		"plantFlowers":
			for i in 3:
				make_structure(s, a, sim.clamp_pos(p + Vector2(cos(i * TAU / 3.0), sin(i * TAU / 3.0)) * 25.0, 9.0), "flower")
		"rootGarden", "thornGarden":
			var gs: Array = []
			for g in sim.gardens:
				if g.source == s.idx and float(g.end) > sim.time:
					gs.append(g)
			if a.action == "thornGarden":
				for g in gs:
					g["thorn_until"] = sim.time + 4.0
					g["next_thorn"] = sim.time + 0.1
			else:
				for e in sim.opponents(s):
					for g in gs:
						if Geometry2D.is_point_in_polygon(e.pos, g.points):
							sim.apply_status(s, e, {"status": "root", "duration": 1.5}, ctx)
							break
			sim.fx("garden_" + a.action, s.pos, {"ability": a, "source": s.idx})
		"rapture":
			s.ks.rapture_until = sim.time + 5.0
			s.ks.rapture_stacks = 0
			s.ks.witness_at = -10.0
		"cripple":
			if t:
				sim.apply_damage(s, t, {"type": "damage", "school": "physical", "base": 52.0, "ad": 0.65}, ctx)
				if t.alive:
					sim.apply_status(s, t, {"status": "slow", "duration": 2.0, "magnitude": 0.65}, ctx)
		"chamber":
			_start_chamber(s, t, ctx)
		"turret":
			make_structure(s, a, sim.clamp_pos(p, 18.0), "turret")
		"upgrade":
			var best: BUnit = null
			for tw in owned_entities(s, "turret"):
				if tw.level < 3 and tw.pos.distance_to(s.pos) <= 100.0:
					if best == null or tw.level < best.level:
						best = tw
			if best:
				best.level += 1
				best.def.stats[&"maxHealth"] = float(best.def.stats.get(&"maxHealth", 260.0)) + 90.0
				best.hp += 90.0
				best.ent_range = 235.0 + 40.0 * (best.level - 1)
				sim.emit("TURRET_UPGRADED", s.idx, best.idx, {"level": best.level, "pos": best.pos})
				sim.fx("upgrade", best.pos, {"level": best.level, "color": s.def.accent})
		"detonate":
			var tower: BUnit = null
			for tw in owned_entities(s, "turret"):
				if tw.pos.distance_to(s.pos) <= 420.0:
					if tower == null or tw.pos.distance_to(p) < tower.pos.distance_to(p):
						tower = tw
			if tower:
				var at: = tower.pos
				var mult: = 1.0 + 0.25 * (tower.level - 1)
				sim.kill_unit(tower, s, {"ability": a, "demolition": true})
				for e in sim.opponents(s):
					if e.pos.distance_to(at) <= 115.0 + sim.radius(e) and sim.los(at, e.pos, 2.0):
						sim.apply_damage(s, e, {"type": "damage", "school": "magic", "base": 90.0 * mult, "ad": 0.4 * mult, "ap": 0.65 * mult}, ctx)
				sim.fx("explosion", at, {"radius": 115.0, "color": a.color, "ability": a, "source": s.idx})
		"driver":
			var pa: = a.duplicate_def()
			pa.pierce = 1
			sim.proj.spawn(s, t, p, pa, [{"type": "damage", "school": "physical", "base": 50.0, "ad": 0.55, "ap": 0.25}, {"type": "displace", "mode": "knockback", "distance": 95.0}], ctx, {"driver": true})


func make_structure(s: BUnit, a: Defs.AbilityDef, p: Vector2, kind: String) -> BUnit:
	var hp: = 1.0
	var r: = 9.0
	var dur: = 12.0
	var armor: = 20.0
	if kind == "tree":
		hp = 560.0 + sim.stat(s, S_AP)
		r = 25.0
		dur = 18.0
		armor = 32.0
	elif kind == "turret":
		hp = 260.0 + 0.6 * sim.stat(s, S_AP)
		r = 18.0
		dur = 22.0
	var ctx: = sim.context(s, a, {})
	var u: = create_entity(s, p, kind, hp, r, ctx, {"duration": dur, "armor": armor, "structure": true})
	u.level = 1
	u.next_pulse = sim.time + (s.def.arming_time if kind == "turret" else 0.5)
	if kind == "turret":
		u.ent_range = 235.0
	var cap: = 2 if kind == "tree" else (3 if kind == "turret" else 6)
	var prev: = owned_entities(s, kind)
	prev.erase(u)
	prev.sort_custom( func(x, y): return x.spawn_time < y.spawn_time)
	while prev.size() >= cap:
		var x: BUnit = prev.pop_front()
		x.alive = false
		x.end_time = sim.time
		sim.emit("STRUCTURE_REPLACED", s.idx, x.idx, {"kind": kind})
	sim.fx("construct", p, {"kind": kind, "color": s.def.accent})
	return u


func create_entity(s: BUnit, p: Vector2, kind: String, hp: float, r: float, ctx: Dictionary, opts: Dictionary) -> BUnit:
	var d: = Defs.entity_def(kind, s.def, hp, r, float(opts.get("armor", 8.0)))
	var team: int = ctx.get("team", sim.eteam(s))
	var u: = sim._new_unit(d, team, 9000 + sim.seq, sim.clamp_pos(p, r))
	u.is_hero = false
	u.kind = kind
	u.owner_idx = s.idx
	u.id = "%s_%d" % [kind, u.idx]
	u.hp = hp
	u.spawn_time = sim.time
	u.end_time = sim.time + float(opts.get("duration", 9.0))
	u.ctx = ctx
	u.structure = opts.get("structure", false)
	u.attack_eff = opts.get("attack", {})
	u.interval = float(opts.get("interval", 1.0))
	u.next_attack = sim.time + 0.4
	u.move_speed_ent = float(opts.get("speed", 0.0))
	u.on_hit_status = opts.get("on_hit", {})
	u.consume_on_hit = opts.get("consume", false)
	u.facing = s.facing
	sim.entities.append(u)
	for t in sim.team_count:
		var arr: PackedByteArray = sim.seen[t]
		arr.resize(sim.units.size())
		sim.seen[t] = arr
	sim.emit("SUMMON_CREATED", s.idx, u.idx, {"kind": kind, "pos": u.pos, "hp": hp, "ability": ctx.get("ability")})
	return u


func spawn_summons(s: BUnit, f: Dictionary, ctx: Dictionary) -> void :
	var kind: = str(f.get("originEntity", ""))
	if kind == "":
		return
	var hp: = float(f.get("hp", 90.0)) + float(f.get("hpAp", 0.3)) * sim.stat(s, S_AP) + float(f.get("hpSelfMaxHp", 0.0)) * sim.max_hp(s)
	var frozen: Dictionary = sim.freeze_effects(s, null, [f.get("attack", {"type": "damage", "school": "magic", "base": 0.0})], false, false)[0]
	var n: = int(f.get("count", 1))
	var ring: = str(f.get("originFormation", "")) == "ring"
	var mode: = str(f.get("originMode", ""))
	var body_r: = float(f.get("radius", 10.0 if kind == "snake" else 9.0))
	var ring_r: = sim.radius(s) + float(f.get("ringPadding", 30.0))
	for i in n:
		var p: Vector2
		var slot_angle: = i * TAU / maxf(1.0, float(n))
		if ring:
			p = s.pos + Vector2.from_angle(slot_angle) * ring_r
		else:
			var ang: = (i - (n - 1) * 0.5) * 0.65
			var dir: = s.facing.rotated(ang)
			p = s.pos + dir * (sim.radius(s) + 18.0)
		var e: = create_entity(s, p, kind, hp, body_r, ctx, {
			"duration": float(f.get("duration", 9.0)), "armor": float(f.get("armor", 8.0)), "attack": frozen, 
			"speed": float(f.get("speed", 110.0)), "interval": float(f.get("interval", 1.1)), 
			"on_hit": f.get("onHitStatus", {}), "consume": kind == "parasite"})
		if mode == "":
			continue
		# V2 entity modes (Kits.update_entities): escort keeps a ring slot,
		# chariot hunts team-seen enemy heroes and is invulnerable/untargetable.
		e.ks["mode"] = mode
		match mode:
			"escort":
				e.ks["slot_angle"] = slot_angle
				e.ks["slot_radius"] = ring_r
				e.ks["reach"] = float(f.get("reach", 24.0))
				e.ks["speed_bonus"] = float(f.get("speedBonus", 60.0))
			"chariot":
				e.ks["nav_radius"] = float(f.get("navRadius", 18.0))
				e.ks["knocks"] = {}
				e.ks["hit_at"] = {}
				e.ks["max_knocks"] = int(f.get("maxKnocks", 2))
				e.ks["icd"] = float(f.get("hitInterval", 1.0))
				e.ks["knock"] = (f.get("knock", {"distance": 130.0, "speed": 600.0}) as Dictionary).duplicate()
				e.ks["range_ffa"] = float(f.get("rangeFfa", 900.0))
				# Seen (and dodged) by enemies, still untargetable (sim.observes).
				e.ks["visible_untargetable"] = true
				for st in [&"invulnerable", &"untargetable"]:
					sim.push_status(e, st, s.idx, float(f.get("duration", 5.0)), {"chariot": true})


func _start_chamber(s: BUnit, t: BUnit, ctx: Dictionary) -> void :
	if t == null or not t.alive or s.chamber != "" or t.chamber != "" or sim.has_status(t, &"invulnerable") or sim.has_status(t, &"untargetable"):
		return
	var cid: = "chamber_%d" % sim.next_id()
	var center: = sim.clamp_pos((s.pos + t.pos) * 0.5, 115.0)
	var c: = {"id": cid, "source": s.idx, "target": t.idx, "center": center, "source_return": s.pos, "target_return": t.pos, 
		"start": sim.time, "end": sim.time + 3.2, "next_pulse": sim.time + 0.4, "pulses": 0, "ctx": ctx, "ended": false}
	sim.chambers.append(c)
	for u in [s, t]:
		_clear_transit(u)
		u.chamber = cid
		u.action = null
	sim.remove_statuses_where(t, func(x): return x.type == &"pain" and x.source_idx == s.idx)
	s.pos = sim.clamp_pos(center + Vector2(-35, 0), s.base_radius)
	t.pos = sim.clamp_pos(center + Vector2(35, 0), t.base_radius)
	for u in [s, t]:
		u.vel = Vector2.ZERO
		u.prev_pos = u.pos
		sim.push_status(u, &"suppression", s.idx, 3.2, {"chamber": cid})
	sim.emit("CHAMBER_STARTED", s.idx, t.idx, {"duration": 3.2, "pos": center})
	sim.fx("chamber", center, {"color": s.def.accent, "id": cid})


func _end_chamber(c: Dictionary, success: bool) -> void :
	if c.ended:
		return
	c.ended = true
	var s: = sim.u_at(int(c.source))
	var t: = sim.u_at(int(c.target))
	if success and s and s.alive and t and t.alive:
		var slots: Array = []
		for i in t.def.abilities.size():
			if not t.sealed.has(i):
				slots.append(i)
		slots.sort_custom( func(x, y): return hash(str(c.id) + ":" + str(x)) < hash(str(c.id) + ":" + str(y)))
		var sealed: = slots.slice(0, 2)
		for i in sealed:
			t.sealed.append(i)
		sim.push_status(t, &"nexus_seal", s.idx, 1000000000.0, {"slots": sealed})
		sim.emit("SKILLS_SEALED", s.idx, t.idx, {"slots": sealed.map( func(i): return i + 1), "pos": t.pos})
		sim.fx("seal", t.pos, {"color": s.def.accent})
	for u in [s, t]:
		if u == null:
			continue
		_clear_transit(u)
		u.chamber = ""
		sim.remove_statuses_where(u, func(x): return x.extra.get("chamber", "") == str(c.id))
		u.action = null
		u.vel = Vector2.ZERO
		u.pos = sim.clamp_pos(c.source_return if u == s else c.target_return, u.base_radius)
		u.prev_pos = u.pos
		u.next_decision_at = sim.time
	sim.emit("CHAMBER_ENDED", s.idx if s else -1, t.idx if t else -1, {"completed": success})


func _clear_transit(u: BUnit) -> void :
	u.motion = null
	u.vel = Vector2.ZERO
	sim.remove_statuses_where(u, func(x): return x.extra.has("motion_id"))
	u.ks.wall_run_until = 0.0
	u.ks.glide_until = 0.0


func constrain_chambers(u: BUnit, start: Vector2) -> void :
	if sim.chambers.is_empty() or not u.alive or u.chamber != "":
		return
	for c in sim.chambers:
		if c.ended:
			continue
		var r: = 112.0 + sim.radius(u)
		var center: Vector2 = c.center
		if u.pos.distance_to(center) >= r:
			continue
		var delta: = start - center
		var dir: = delta.normalized() if delta.length_squared() > 0.01 else (Vector2.LEFT if u.team == 0 else Vector2.RIGHT)
		u.pos = sim.clamp_pos(center + dir * (r + 0.05), sim.radius(u))
		u.prev_pos = u.pos
		_clear_transit(u)






# A jump-pad flight is a committed arc above the ground (it crosses walls and
# chasms): nothing may replace it mid-air, so it always ends on its landing.
func in_pad_flight(u: BUnit) -> bool:
	return u != null and u.motion != null and u.motion.kind == "jump_pad"


func begin_motion(u: BUnit, end: Vector2, speed: float, kind: String, ctx: Dictionary, opts: Dictionary = {}) -> void :
	if in_pad_flight(u):
		return
	var m: = ST.Motion.new()
	m.id = sim.next_id()
	m.kind = kind
	m.start = u.pos
	m.end = end
	m.speed = maxf(1.0, speed)
	m.at = sim.time
	var dist: = u.pos.distance_to(end)
	m.deadline = sim.time + dist / m.speed + 0.1
	m.source_idx = int(opts.get("source", u.idx))
	m.target_idx = int(opts.get("target", -1))
	m.ctx = ctx
	m.hit_effects = opts.get("hit_effects", [])
	m.unstoppable = opts.get("unstoppable", false)
	m.invulnerable = opts.get("invulnerable", false)
	m.flight = opts.get("flight", false)
	m.hook = opts.get("hook", false)
	if dist < 1e-06:
		_finish_motion(u, m, null, false)
		return
	u.motion = m
	if m.unstoppable:
		sim.push_status(u, &"unstoppable", u.idx, m.deadline + 0.1 - sim.time, {"motion_id": m.id})
	if m.invulnerable:
		sim.push_status(u, &"invulnerable", m.source_idx, minf(0.65, dist / m.speed + 0.04), {"motion_id": m.id})
	sim.emit("DASH_STARTED", m.source_idx, u.idx, {"mode": kind, "from": m.start, "to": end, "ability": ctx.get("ability")})


func update_motion(u: BUnit, dt: float) -> void :
	var m: = u.motion
	if m == null:
		return
	if not u.alive:
		_finish_motion(u, m, null, true)
		return
	if m.kind == "contactDash" and not m.unstoppable and sim.has_any(u, [&"root", &"stun", &"airborne", &"sleep", &"suppression"]):
		_finish_motion(u, m, null, true)
		return
	var start: = u.pos
	var to_end: = m.end - start
	var dist: = to_end.length()
	var dir: = to_end / dist if dist > 1e-09 else u.facing
	var step: = minf(dist, m.speed * dt)
	var end: = start + dir * step
	var r: = sim.radius(u)
	var hit_t: = 2.0
	var hit_point: = end
	var hit_unit: BUnit = null
	var wall: = false
	if not m.flight:
		var h: = sim.arena.terrain_contact(start, end, r, false)
		if not h.is_empty():
			hit_t = float(h.t)
			hit_point = h.point
			wall = true
	if m.kind == "contactDash":
		for t in sim.opponents(u):
			if sim.has_status(t, &"untargetable"):
				continue
			var tt: = Arena.seg_circle_t(start, end, t.pos, r + sim.radius(t))
			if tt >= 0.0 and tt < hit_t:
				hit_t = tt
				hit_point = start.lerp(end, tt)
				hit_unit = t
				wall = false
	elif m.kind == "knockback":
		for t in sim.bodies_alive():
			if t == u or sim.eteam(t) != sim.eteam(u):
				continue
			var tt2: = Arena.seg_circle_t(start, end, t.pos, r + sim.radius(t))
			if tt2 >= 0.0 and tt2 < hit_t:
				hit_t = tt2
				hit_point = start.lerp(end, tt2)
				hit_unit = t
				wall = false
	u.pos = hit_point if hit_t <= 1.0 else end
	sim.warfare.constrain(u, start)
	if u.motion != m:
		return
	u.vel = (u.pos - start) / maxf(1e-09, dt)
	u.facing = dir
	if hit_unit and m.kind == "contactDash":
		var c: = m.ctx.duplicate()
		c["hit_pos"] = u.pos
		sim.apply_effects(u, hit_unit, m.hit_effects, c)
		sim.fx("dash_hit", hit_unit.pos, {"color": (m.ctx.get("ability") as Defs.AbilityDef).color if m.ctx.get("ability") else u.def.accent, "ability": m.ctx.get("ability")})
	var contact: = hit_unit != null or wall
	if hit_t <= 1.0 or u.pos.distance_to(m.end) < 0.2 or sim.time >= m.deadline:
		if m.flight:
			u.pos = sim.clamp_pos(u.pos, r)
		_finish_motion(u, m, hit_unit if hit_unit else (u if wall else null), false, contact)


func _finish_motion(u: BUnit, m: ST.Motion, contact: BUnit, interrupted: bool, had_contact: bool = false) -> void :
	if u.motion == m:
		u.motion = null
	sim.remove_statuses_where(u, func(x): return int(x.extra.get("motion_id", -1)) == m.id)
	u.vel = Vector2.ZERO
	var s: = sim.u_at(m.source_idx)
	if s == null:
		s = u
	if u.alive and not interrupted:
		match m.kind:
			"rescuePull":
				sim.apply_heal(s, u, {"base": 75.0, "ap": 0.65}, m.ctx)
			"rescueFlight":
				var t: = sim.u_at(m.target_idx)
				if t and t.alive and u.pos.distance_to(t.pos) <= sim.radius(u) + sim.radius(t) + 30.0:
					sim.apply_shield(u, t, {"base": 95.0, "ap": 0.75, "duration": 4.0}, m.ctx)
			"pull":
				if m.hook and s.alive and s.pos.distance_to(u.pos) <= 85.0 + sim.radius(s) + sim.radius(u):
					sim.apply_mark(s, u, {"status": "hooked", "duration": 3.0, "stacks": 1, "maxStacks": 1}, m.ctx)
			"knockback":
				if (had_contact or contact != null) and s.is_hero and s.def.has_rule("cone_basic"):
					sim.add_buff(s, &"nextBasicDamage", 0.35, 5.0, s.idx, {"tag": "batCollision"})
					sim.emit("PASSIVE", s.idx, u.idx, {"rule": "cone_basic", "detail": "충돌 후 다음 타격 강화", "pos": u.pos})
	sim.emit("DASH_ENDED", s.idx, u.idx, {"mode": m.kind, "contact": contact.idx if contact else -1, "pos": u.pos})


# Returns true when a displacement motion actually started (V2 chariot counts
# only real knockbacks).
func displace(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary) -> bool:
	if t == null or not t.alive or t.kind == "bed" or t.structure or t.chamber != "":
		return false
	if sim.has_any(t, [&"unstoppable", &"invulnerable"]):
		return false
	if sim.warfare.contemplating(t):
		sim.emit("CC_IMMUNE", s.idx, t.idx, {"status": "displace", "reason": "contemplation"})
		return false
	if not sim.realm_allowed(s, t, ctx):
		return false
	# Knockbacks, pulls and hooks cannot cut a jump-pad flight short: the hero
	# would drop into the chasm or wall it is vaulting (it stays targetable).
	if in_pad_flight(t):
		sim.emit("CC_IMMUNE", s.idx, t.idx, {"status": "displace", "reason": "flight"})
		return false
	if sim.front_blocks(s, t, ctx):
		sim.emit("CC_IMMUNE", s.idx, t.idx, {"status": "displace", "reason": "front_guard"})
		sim.emit("FRONT_BLOCKED", s.idx, t.idx, {"kind": "displace", "ability": ctx.get("ability"), "pos": t.pos})
		return false
	var end: Vector2
	var kind: = "knockback"
	var mode: = str(f.get("mode", "knockback"))
	var dist: = float(f.get("distance", 50.0))
	if mode == "pullToSource":
		var delta: = t.pos - s.pos
		var sep: = sim.radius(s) + sim.radius(t) + 3.0
		end = s.pos + (delta.normalized() if delta.length_squared() > 1e-06 else Vector2.RIGHT) * sep
		kind = "pull"
	elif mode == "pullToPoint":
		end = ctx.get("hit_pos", ctx.get("target_pos", t.pos))
		kind = "pull"
	else:
		var dir: Vector2 = ctx.get("direction", Vector2.ZERO)
		if dir.length_squared() < 1e-06:
			dir = t.pos - s.pos
		dir = dir.normalized() if dir.length_squared() > 1e-06 else s.facing
		end = t.pos + dir * dist

		var ab = ctx.get("ability")
		if ab is Defs.AbilityDef and (ab as Defs.AbilityDef).action == "driver":
			var rr: = sim.radius(t)
			var wall: = sim.arena.segment_blocked(t.pos, end, rr, Arena.MASK_UNITS) or sim.clamp_pos(end, rr).distance_to(end) > 1.0
			if wall:
				t.ks["pending_pin"] = {"source": s.idx, "ability": ab, "until": sim.time + 0.75}
	if t.pos.distance_to(end) > dist:
		end = t.pos + (end - t.pos).normalized() * dist
	var prior: = t.motion
	begin_motion(t, end, float(f.get("speed", 450.0)), kind, ctx.merged({"source_idx": s.idx}), {"source": s.idx, "hook": f.get("originHook", false)})
	if t.motion == null or t.motion == prior:
		return false
	# Knockbacks and pulls count as crowd control for torquemada S2.
	_record_cc_source(s, t)
	return true


func move_self(s: BUnit, t: BUnit, f: Dictionary, ctx: Dictionary) -> void :
	if not s.alive:
		return
	var p: Vector2 = ctx.get("hit_pos", t.pos if t else ctx.get("target_pos", s.pos))
	var mode: = str(f.get("mode", "dash"))
	match mode:
		"blink":
			var dest: = p
			if f.get("behindTarget", false) and t:
				var tf: = t.facing if t.facing.length_squared() > 0.1 else (s.pos - t.pos).normalized()
				dest = t.pos - tf.normalized() * (float(f.get("distance", 28.0)) + sim.radius(t))
			var from: = s.pos
			s.pos = sim.clamp_pos(dest, sim.radius(s))
			sim.warfare.constrain(s, from)
			s.prev_pos = s.pos
			s.vel = Vector2.ZERO
			sim.emit("BLINKED", s.idx, t.idx if t else -1, {"from": from, "to": s.pos, "ability": ctx.get("ability")})
		"recoil":
			var aim: Vector2 = ctx.get("target_pos", p)
			var origin: Vector2 = ctx.get("source_origin", s.pos)
			var dir: = (aim - origin)
			dir = dir.normalized() if dir.length_squared() > 1e-06 else s.facing
			begin_motion(s, s.pos - dir * float(f.get("distance", 100.0)), float(f.get("speed", 480.0)), "recoil", ctx)
		"dashToImpact":
			begin_motion(s, p, float(f.get("speed", 580.0)), "grapple", ctx)
		"dash":
			var d2: = (p - s.pos)
			d2 = d2.normalized() if d2.length_squared() > 1e-06 else s.facing
			begin_motion(s, s.pos + d2 * float(f.get("distance", 100.0)), float(f.get("speed", 520.0)), "dash", ctx)


func update_wall_run(u: BUnit, dt: float) -> void :
	if sim.distance_to_wall(u.pos) > sim.radius(u) + 6.0:
		u.ks.wall_run_until = 0.0
		return
	var tang: Vector2 = sim.wall_tangent(u.pos) * float(u.ks.get("wall_run_sign", 1.0))
	var a: = u.pos
	var spd: = sim.stat(u, S_MS) * 4.0
	var b: = a + tang * spd * dt
	var hit: = sim.arena.terrain_contact(a, b, sim.radius(u), false)
	u.pos = hit.point if not hit.is_empty() else b
	u.pos = sim.clamp_pos(u.pos, sim.radius(u))
	u.vel = (u.pos - a) / dt
	u.facing = tang






func update_passives(dt: float) -> void :
	for u in sim.heroes:
		if not u.alive:
			continue
		var d: = u.def
		var k: = u.ks
		var b: Dictionary = k.borrowed
		if not b.is_empty() and float(b.expires) <= sim.time:
			k.borrowed = {}

		# V2 hades P1 (Kynee): concealed regeneration after a quiet delay. It goes
		# through apply_heal, so heal reduction and heal block apply.
		var cr: = d.rule("concealed_regen")
		if not cr.is_empty() and u.hp < sim.max_hp(u) and sim.time - u.last_damage_time >= float(cr.get("delay", 1.0)) - 1e-09 and concealed(u):
			sim.apply_heal(u, u, {"base": sim.max_hp(u) * float(cr.get("perSecondRatio", 0.02)) * dt}, {"source_type": "PASSIVE", "silent": true})
		if d.has_rule("companion"):
			_ensure_companion(u, d.rule("companion"))
		if d.has_rule("fuel_tank"):
			_ensure_tank(u, d.rule("fuel_tank"))

		if d.id == "giant":
			var hits: Array = []
			for h in k.regen_hits:
				if sim.time - float(h.at) <= 2.0:
					hits.append(h)
			k.regen_hits = hits
			if u.hp < sim.max_hp(u):
				var extra: = 0.0
				if sim.get_buff(u, &"originRegenPool"):
					var tot: = 0.0
					for h in hits:
						tot += float(h.amount)
					extra = minf(24.0, tot * 0.08)
				var rate: = float(d.rule("regen").get("perSecond", 6.0)) + sim.buff_sum(u, &"regen") + extra
				sim.apply_heal(u, u, {"base": rate * dt}, {"source_type": "PASSIVE", "silent": true})

		if d.id == "fisherman" and sim.time + 1e-08 >= float(k.fish_next):
			k.fish_next = float(k.fish_next) + 8.0
			var fish: Array = k.fish
			if fish.size() >= 2:
				eat_fish(u, "inventory_overflow")
				fish = k.fish
			var types: = ["attack", "defense", "health"]
			fish.append({"id": sim.next_id(), "type": types[sim.rng.randi_range(0, 2)]})
			k.fish = fish
			u.resources["fish"] = float(fish.size())
			sim.emit("PASSIVE", u.idx, u.idx, {"rule": "timed_random_buff", "detail": "물고기 획득", "silent": true})

		if d.id == "hive_mind" and sim.time + 1e-08 >= float(k.reveal_at):
			k.reveal_at = float(k.reveal_at) + float(d.rule("reveal_cooldowns").get("interval", 7.0))
			var target: = -1
			var ctl = sim.controllers[sim.eteam(u)]
			if ctl and ctl.has_method("reveal_choice"):
				target = ctl.reveal_choice(u)
			if target < 0:
				for e in sim.heroes:
					if e.alive and sim.eteam(e) != sim.eteam(u):
						target = e.idx
						break
			var tu: = sim.u_at(target)
			if tu:
				sim.warfare.reveal(u, tu, "cooldowns", 7.0)

		if d.id == "nitro":
			var dw: = sim.distance_to_wall(u.pos)
			var r: = sim.radius(u)
			if dw <= r + 3.0:
				k.wall_until = sim.time + 10.0
				if not k.wall_near and sim.time >= float(k.wall_rearm):
					k.wall_bonus = mini(4, int(k.wall_bonus) + 1)
					k.wall_rearm = sim.time + 0.35
					sim.emit("PASSIVE", u.idx, u.idx, {"rule": "wall_mastery", "detail": "벽 재접촉", "silent": true})
				k.wall_near = true
			elif dw > r + 16.0:
				k.wall_near = false
			if sim.time > float(k.wall_until) and int(k.wall_bonus) > 0:
				k.wall_bonus = 0
				u.resources["rage"] = minf(8.0, float(u.resources.get("rage", 0.0)))
			if sim.time - u.last_damage_time >= 4.0 and float(u.resources.get("rage", 0.0)) > 0.0 and sim.time >= float(k.rage_decay_at):
				u.resources["rage"] = float(u.resources.rage) - 1.0
				k.rage_decay_at = sim.time + 1.0

		if d.id == "hermes" and sim.time + 1e-08 >= float(k.borrow_next):
			k.borrow_next = float(k.borrow_next) + 12.0
			if (k.borrowed as Dictionary).is_empty():
				var pool: Array = []
				for ally in sim.heroes:
					if not ally.alive or ally == u or sim.eteam(ally) != sim.eteam(u):
						continue
					for ab in ally.def.abilities:
						if not ab.is_mobility or ab.condition.get("owned", false):
							continue
						# V2: never borrow a skill paid with the donor's resource.
						if uses_resource(ab):
							continue
						var ok: bool = ab.action in MOBILITY_ACTIONS
						for f in ab.effects:
							var ty: = str(f.get("type", ""))
							if ty in ["move_self", "force_charge", "portal_pair"] or (ty == "status" and str(f.get("status", "")) == "invisible"):
								ok = true
						if ok:
							pool.append({"owner": ally.idx, "ability": ab})
				if not pool.is_empty():
					var pick: Dictionary = pool[sim.rng.randi_range(0, pool.size() - 1)]
					k.borrowed = {"id": sim.next_id(), "owner": pick.owner, "ability": pick.ability, "expires": sim.time + 24.0}
					sim.emit("PASSIVE", u.idx, int(pick.owner), {"rule": "borrow_mobility", "detail": "이동기 차용: " + (pick.ability as Defs.AbilityDef).name})

		if d.id == "werewolf":
			if sim.get_buff(u, &"originScent"):
				var weak: BUnit = null
				for e in sim.opponents(u):
					if e.is_hero and sim.observes(u, e) and sim.hp_ratio(e) <= 0.4:
						if weak == null or e.hp < weak.hp:
							weak = e
				var goal = null
				if weak:
					goal = weak.pos
					k.scent_pos = weak.pos
					k.scent_seen = sim.time
				elif k.has("scent_pos") and sim.time - float(k.get("scent_seen", -9.0)) <= 1.0:
					goal = k.scent_pos
				var motion: = u.vel.normalized() if u.vel.length() > 2.0 else Vector2.ZERO
				if goal != null and motion != Vector2.ZERO and motion.dot(((goal as Vector2) - u.pos).normalized()) >= 0.5:
					k.scent_until = sim.time + 0.05
				else:
					k.scent_until = -1.0
			else:
				k.scent_until = -1.0

		if not (k.blade_hits as Dictionary).is_empty() and sim.tick % 60 == 0:
			var bh: Dictionary = {}
			for key in k.blade_hits:
				if sim.time - float(k.blade_hits[key]) <= 20.0:
					bh[key] = k.blade_hits[key]
			k.blade_hits = bh
			var ck: Dictionary = {}
			for key2 in k.cdr_keys:
				if sim.time - float(k.cdr_keys[key2]) <= 30.0:
					ck[key2] = k.cdr_keys[key2]
			k.cdr_keys = ck



# A resource condition or a resource cost (Hermes cannot pay the donor's fuel).
func uses_resource(ab: Defs.AbilityDef) -> bool:
	if ab.condition.has("selfResource"):
		return true
	for f in ab.effects:
		if str(f.get("type", "")) == "consume_resource":
			return true
	return false


# V2 hades P2: the permanent companion (cerberus) is created lazily here, again
# after its respawn delay, and after the owner's own respawn (init_unit).
func _ensure_companion(u: BUnit, r: Dictionary) -> void:
	var pet: = sim.u_at(int(u.ks.get("pet_idx", -1)))
	if pet and pet.alive and pet.end_time > sim.time:
		return
	if sim.time + 1e-09 < float(u.ks.get("pet_ready_at", 0.0)) or u.chamber != "":
		return
	var kind: = str(r.get("kind", "cerberus"))
	var pr: = float(r.get("radius", 14.0))
	var ctx: = {"source_type": "SUMMON", "team": u.team}
	var e: = create_entity(u, u.pos - u.facing * (sim.radius(u) + pr + 6.0), kind, float(r.get("hp", 420.0)), pr, ctx, {
		"duration": 1e9, "armor": float(r.get("armor", 30.0)), "interval": float(r.get("interval", 1.0)),
		"speed": maxf(float(r.get("speedMin", 110.0)), float(r.get("speedRatio", 1.2)) * sim.stat(u, S_MS))})
	e.ks["mode"] = "companion"
	u.ks["pet_idx"] = e.idx


# V2 war_machine passive: the attached fuel tank (a structure with its own HP).
func _ensure_tank(u: BUnit, r: Dictionary) -> void:
	var tank: = sim.u_at(int(u.ks.get("tank_idx", -1)))
	if tank and tank.alive and tank.end_time > sim.time:
		return
	if sim.time + 1e-09 < float(u.ks.get("tank_ready_at", 0.0)) or u.chamber != "":
		return
	var tr: = float(r.get("tankRadius", 10.0))
	var ctx: = {"source_type": "SUMMON", "team": u.team}
	var e: = create_entity(u, u.pos - u.facing * (sim.radius(u) + tr + 2.0), "fuel_tank", float(r.get("tankHp", 300.0)), tr, ctx, {
		"duration": 1e9, "armor": float(r.get("tankArmor", 40.0)), "structure": true})
	e.ks["mode"] = "attach"
	e.ks["area_taken"] = float(r.get("areaTakenRatio", 0.5))
	_attach(e, u)
	u.ks["tank_idx"] = e.idx


func tank_attached(u: BUnit) -> bool:
	var tank: = sim.u_at(int(u.ks.get("tank_idx", -1)))
	return tank != null and tank.alive and tank.end_time > sim.time


func _tank_destroyed(owner: BUnit, tank: BUnit, killer: BUnit) -> void:
	var r: = owner.def.rule("fuel_tank")
	var key: = str(r.get("resourceKey", "fuel"))
	var old: = float(owner.resources.get(key, 0.0))
	owner.resources[key] = 0.0
	var dur: = float(r.get("overdrive", 10.0))
	sim.remove_statuses_where(owner, func(x): return x.type == &"overdrive")
	sim.push_status(owner, &"overdrive", owner.idx, dur, {"mult": float(r.get("overdriveMult", 1.5))})
	owner.ks["tank_ready_at"] = sim.time + float(r.get("respawn", 10.0))
	sim.emit("TANK_DESTROYED", killer.idx if killer else -1, owner.idx, {"tank": tank.idx, "fuel_lost": old, "pos": tank.pos})
	sim.emit("OVERDRIVE", owner.idx, owner.idx, {"duration": dur, "pos": owner.pos})
	if old > 0.0:
		sim.emit("RESOURCE_CHANGED", owner.idx, owner.idx, {"key": key, "amount": - old, "value": 0.0})


func _gain_fuel(s: BUnit, r: Dictionary) -> void:
	if not tank_attached(s):
		return
	var key: = str(r.get("resourceKey", "fuel"))
	var have: = float(s.resources.get(key, 0.0))
	var cap: = float(r.get("max", 10))
	if have >= cap:
		return
	s.resources[key] = minf(cap, have + float(r.get("perBasic", 1.0)))
	sim.emit("RESOURCE_CHANGED", s.idx, s.idx, {"key": key, "amount": float(s.resources[key]) - have, "value": s.resources[key]})


func on_damage_dealt(s: BUnit, t: BUnit, hp_dmg: float, absorbed: float, _f: Dictionary, ctx: Dictionary, target_hp_before: float) -> void :
	var st: = str(ctx.get("source_type", "ABILITY"))
	var proc: bool = ctx.get("proc", false)
	if s.is_hero:
		var d: = s.def
		if hp_dmg > 0.0:

			if d.id == "werewolf" and st != "PASSIVE" and s != t:
				var ratio: = 0.16
				if sim.get_buff(s, &"originPredator"):
					ratio += 0.12 * clampf((target_hp_before - s.hp) / maxf(1.0, sim.max_hp(s)), 0.0, 1.0)
				sim.apply_heal(s, s, {"base": hp_dmg * ratio}, {"source_type": "PASSIVE", "silent": true, "proc": true})

			if d.id == "joker" and t.alive and not ctx.get("explicit_confusion", false) and not ctx.get("consume", false) and not proc:
				sim.apply_mark(s, t, {"status": "confusion", "stacks": 1, "duration": 7.0, "maxStacks": 5, "damageAmp": 0.03, "tenacityLoss": 0.025}, {"proc": true})

			if d.id == "giant" and not proc and not (st in ["PASSIVE", "SUMMON", "PERSISTENT"]):
				(s.ks.regen_hits as Array).append({"at": sim.time, "amount": hp_dmg})

		if d.id == "torturer" and not proc and bool(ctx.get("basic", false)) and hp_dmg + absorbed > 0.0:
			sim.warfare.add_pain(s, t, 1, ctx)

		# V2 war_machine: +1 fuel per basic attack that damages an enemy hero or
		# a non-structure summon (missile, zone and DoT damage never refuel).
		if not proc and bool(ctx.get("basic", false)) and hp_dmg + absorbed > 0.0 and d.has_rule("fuel_tank"):
			if sim.eteam(t) != sim.eteam(s) and (t.is_hero or not t.structure):
				_gain_fuel(s, d.rule("fuel_tank"))

		if d.id == "blood_mage" and (hp_dmg + absorbed) > 0.0 and st != "PASSIVE" and not proc:
			var ab = ctx.get("ability")
			if ab is Defs.AbilityDef and (ab as Defs.AbilityDef).slot != 1 and (ab as Defs.AbilityDef).slot > 0:
				var r: = d.rule("lost_health_ap_on_skill_hit")
				if sim.time + 1e-09 >= float(s.ks.growth_next):
					var key: = str(ctx.get("action_id", (ab as Defs.AbilityDef).id))
					var gbc: Dictionary = s.ks.growth_by_cast
					var allowed: = maxf(0.0, float(r.get("originPerCastCap", 16.0)) - float(gbc.get(key, 0.0)))
					var missing: = maxf(0.0, sim.max_hp(s) - s.hp)
					var gain: = minf(allowed, minf(float(r.get("maxPerHit", 8.0)), missing * float(r.get("ratio", 0.01))) / (1.0 + float(s.ks.growth_total) / float(r.get("originDiminish", 120.0))))
					if gain > 1e-06:
						s.ks.growth_total = float(s.ks.growth_total) + gain
						s.ks.growth_next = sim.time + float(r.get("internalCooldown", 0.65))
						gbc[key] = float(gbc.get(key, 0.0)) + gain
						sim.add_buff(s, &"abilityPowerFlat", float(s.ks.growth_total), 99999.0, s.idx, {"tag": "permanentGrowth"})
						sim.emit("PASSIVE", s.idx, t.idx, {"rule": "lost_health_ap_on_skill_hit", "detail": "결손의 권능 +%.1f AP" % gain, "silent": true})

		if d.id == "swordsman" and hp_dmg > 0.0 and t.alive and not proc and st == "ABILITY":
			var ab2 = ctx.get("ability")
			var mark: = sim.owned_status(t, &"bladeMark", s.idx)
			if mark and ab2 is Defs.AbilityDef and (ab2 as Defs.AbilityDef).slot != 2 and mark.extra.has("originBladeBonus") and int(mark.extra.get("action_id", -1)) != int(ctx.get("action_id", -2)):
				var token: = "%s:%d" % [str(ctx.get("action_id", "")), t.idx]
				var last: = float(mark.extra.get("last_proc", -99.0))
				var bh: Dictionary = s.ks.blade_hits
				if not bh.has(token) and sim.time - last >= 0.4 - 1e-08:
					bh[token] = sim.time
					mark.extra["last_proc"] = sim.time
					var bonus: Dictionary = mark.extra.originBladeBonus
					sim.apply_damage(s, t, {"type": "damage", "school": "physical", "base": float(bonus.base), "ad": float(bonus.ad)}, {"proc": true, "source_type": "PASSIVE", "ability": ab2})

	if t.is_hero and t.def.id == "nitro" and hp_dmg > 0.0 and s != t:
		_rage_gain(t, hp_dmg)

	if hp_dmg > 0.0:
		for tor in sim.heroes:
			if not tor.alive or tor.def.id != "torturer" or sim.eteam(tor) == sim.eteam(t):
				continue
			var k: = tor.ks
			if float(k.rapture_until) <= sim.time or int(k.rapture_stacks) >= 8 or sim.time - float(k.witness_at) < 0.2:
				continue
			if not sim.is_seen(sim.eteam(tor), t):
				continue
			k.witness_at = sim.time
			k.rapture_stacks = int(k.rapture_stacks) + 1
			sim.add_buff(tor, S_AD, 0.04 * int(k.rapture_stacks), float(k.rapture_until) - sim.time, tor.idx, {"tag": "rapture"})


func _rage_gain(t: BUnit, amount: float) -> void :
	var r: = t.def.rule("rage_on_damage")
	var energy: = float(t.ks.rage_rem) + amount
	var per: = float(r.get("originDamagePerStack", 65.0))
	var n: = int(floor((energy + 1e-09) / per))
	t.ks.rage_rem = energy - n * per
	if n > 0:
		var cap: = float(r.get("maxStacks", 8)) + float(t.ks.wall_bonus)
		t.resources["rage"] = minf(cap, float(t.resources.get("rage", 0.0)) + n)
	t.ks.rage_decay_at = sim.time + float(r.get("decayDelay", 4.0)) + 1.0


func on_env_damage(t: BUnit, hp_dmg: float) -> void :
	if t.is_hero and t.def.id == "nitro" and hp_dmg > 0.0:
		_rage_gain(t, hp_dmg)


# V2: remember the enemy hero behind a crowd control (slow excluded); zone,
# bait and summon sources resolve to their owner hero.
func _record_cc_source(s: BUnit, t: BUnit) -> void:
	if t == null or not t.is_hero or not t.ks.has("cc_by"):
		return
	var src: = s
	var guard: = 0
	while src != null and not src.is_hero and guard < 6:
		src = sim.u_at(src.owner_idx)
		guard += 1
	if src == null or not src.is_hero or sim.eteam(src) == sim.eteam(t):
		return
	(t.ks.cc_by as Dictionary)[src.idx] = sim.time


func on_cc_applied(s: BUnit, t: BUnit, type: StringName, credit: float, _fresh: bool, ctx: Dictionary) -> void :
	if type != &"slow":
		_record_cc_source(s, t)
	if not s.is_hero or s.def.id != "mage" or credit <= 0.0:
		return
	var key: = "%s:%d:%s" % [str(ctx.get("cdr_key", ctx.get("action_id", "manual"))), t.idx, String(type)]
	var win: Array = []
	var used: = 0.0
	for w in s.ks.cdr_window:
		if sim.time - float(w.at) < 1.0 - 1e-09:
			win.append(w)
			used += float(w.value)
	s.ks.cdr_window = win
	var keys: Dictionary = s.ks.cdr_keys
	if keys.has(key):
		return
	keys[key] = sim.time
	var amount: = minf(0.45, maxf(0.0, 1.35 - used))
	if amount > 0.0:
		for i in s.cooldowns.size():
			s.cooldowns[i] = maxf(sim.time, s.cooldowns[i] - amount)
		win.append({"at": sim.time, "value": amount})
		sim.emit("PASSIVE", s.idx, t.idx, {"rule": "on_cc_cdr", "detail": "주문 환류 -%.2f초" % amount, "silent": true})



func support_credit(s: BUnit, t: BUnit, value: float, ctx: Dictionary) -> void :
	if s == null or not s.is_hero or s.def.id != "aphrodite" or s == t or value <= 0.0 or ctx.get("proc", false):
		return
	if sim.eteam(s) != sim.eteam(t):
		return
	var cur: = 0.0
	for sh in s.shields:
		if sh.affection and sh.end > sim.time:
			cur += sh.amount
	var gain: = minf(value * 0.2, maxf(0.0, sim.max_hp(s) * 0.2 - cur))
	if gain > 0.0:
		sim.apply_shield(s, s, {"base": gain, "duration": 3.0}, {"proc": true, "silent": true, "affection": true})


func on_kill(t: BUnit, s: BUnit, ctx: Dictionary) -> void :
	if t.structure and t.kind == "turret":
		var owner: = sim.u_at(t.owner_idx)
		if owner and owner.alive and owner.def.id == "engineer" and (ctx.get("demolition", false) or (s and sim.eteam(s) != sim.eteam(owner))):
			owner.ks.frustration = mini(6, int(owner.ks.frustration) + 1)
			owner.resources["frustration"] = float(owner.ks.frustration)
			owner.cooldowns[0] = maxf(sim.time, owner.cooldowns[0] - 0.8)
			sim.emit("PASSIVE", owner.idx, t.idx, {"rule": "nexus_workshop", "detail": "재건의 집념 %d" % int(owner.ks.frustration)})
	if t.chamber != "":
		for c in sim.chambers:
			if c.id == t.chamber:
				_end_chamber(c, false)
	if not t.is_hero and t.ks.has("mode"):
		var owner2: = sim.u_at(t.owner_idx)
		if owner2 and owner2.is_hero:
			if str(t.ks.mode) == "companion" and int(owner2.ks.get("pet_idx", -1)) == t.idx:
				owner2.ks["pet_ready_at"] = sim.time + float(owner2.def.rule("companion").get("respawn", 15.0))
			elif t.kind == "fuel_tank" and owner2.alive and int(owner2.ks.get("tank_idx", -1)) == t.idx:
				_tank_destroyed(owner2, t, s)
	if t.is_hero:

		for e in sim.entities:
			# V2: companions and escorts leave with their owner (like structures).
			if e.owner_idx == t.idx and (e.structure or str(e.ks.get("mode", "")) in ["companion", "escort"]):
				e.alive = false
				e.end_time = sim.time






func update_entities(dt: float) -> void :
	for u in sim.entities:
		if not u.alive or u.end_time <= sim.time:
			continue
		var s: = sim.u_at(u.owner_idx)
		if s == null:
			continue
		u.prev_pos = u.pos
		var mode: = str(u.ks.get("mode", "")) if not u.ks.is_empty() else ""
		if mode == "attach":
			_attach(u, s)
			continue
		if u.motion:
			update_motion(u, dt)
			continue
		if u.structure or u.kind == "bed":
			continue
		if sim.has_any(u, [&"root", &"stun", &"sleep", &"airborne", &"suppression", &"charm"]):
			u.vel = Vector2.ZERO
			continue
		if mode != "":
			# V2 entity modes: companion (cerberus), escort (shade ring), chariot.
			if mode == "companion":
				_companion_step(u, s, dt)
			elif mode == "escort":
				_escort_step(u, s, dt)
			elif mode == "chariot":
				_chariot_step(u, s, dt)
			continue
		var best: BUnit = null
		var bd: = INF
		for t in sim.opponents(u):
			if not sim.observes(u, t):
				continue
			var dd: = t.pos.distance_to(u.pos)
			if dd < bd:
				bd = dd
				best = t
		if best == null:
			u.vel = Vector2.ZERO
			u.target_idx = -1
			continue
		u.target_idx = best.idx
		var reach: = sim.radius(best) + sim.radius(u) + 10.0
		# Float32 positions cannot close the last ~1e-5 px to exactly `reach`:
		# approach to 0.5 px inside it and bite within reach + 1 (no stall).
		if bd > reach + 0.5:
			var goal: = best.pos
			var nav = sim.controllers[sim.eteam(u)]
			var wp: = goal
			if sim.arena.has_links:
				# Portals and jump pads only carry heroes; summons walk.
				wp = Navigator.for_sim(sim, u.base_radius).next_waypoint(u.pos, goal, u.base_radius, 0.0, 0.0, 0.0, false)
			elif nav and nav.has_method("route_point"):
				wp = nav.route_point(u.pos, goal, u.base_radius)
			var dir: = (wp - u.pos).normalized()
			var step: = minf(u.move_speed_ent * dt, bd - reach + 0.5)
			var endp: = u.pos + dir * step
			var hit: = sim.arena.terrain_contact(u.pos, endp, u.base_radius, false)
			u.pos = hit.point if not hit.is_empty() else endp
			u.vel = (u.pos - u.prev_pos) / dt
			u.facing = dir
		if bd <= reach + 1.0 and sim.time >= u.next_attack and not sim.has_any(u, [&"disarm"]):
			u.next_attack = sim.time + u.interval
			var c: = {"source_type": "SUMMON", "snapshot": true, "ability": u.ctx.get("ability"), "team": sim.eteam(u)}
			if not u.attack_eff.is_empty() and float(u.attack_eff.get("base", 0.0)) > 0.0:
				sim.apply_damage(s, best, u.attack_eff, c)
			if not u.on_hit_status.is_empty():
				var oh: Dictionary = u.on_hit_status.duplicate()
				sim.apply_mark(s, best, oh, c)
			sim.fx("bite", best.pos, {"color": s.def.accent, "kind": u.kind})
			if u.consume_on_hit:
				u.alive = false
				u.end_time = sim.time
				sim.emit("SUMMON_CONSUMED", s.idx, best.idx, {"kind": u.kind})


# V2 attach mode (fuel tank): rides behind the owner, pos - facing * (r_o+r_t+2).
func _attach(u: BUnit, s: BUnit) -> void:
	var back: = s.facing.normalized() if s.facing.length_squared() > 0.01 else Vector2.RIGHT
	u.pos = s.pos - back * (sim.radius(s) + sim.radius(u) + 2.0)
	u.prev_pos = u.pos
	u.vel = s.vel
	u.facing = back
	u.chamber = s.chamber


# Walks an entity toward goal and stops `stop` px short (summon navigation).
func _entity_walk(u: BUnit, goal: Vector2, speed: float, dt: float, stop: float, nav_radius: float = -1.0) -> void:
	var dist: = u.pos.distance_to(goal)
	if dist <= stop + 0.01:
		u.vel = Vector2.ZERO
		return
	var nr: = nav_radius if nav_radius > 0.0 else u.base_radius
	var wp: = goal
	var nav = sim.controllers[sim.eteam(u)]
	if sim.arena.has_links:
		wp = Navigator.for_sim(sim, nr).next_waypoint(u.pos, goal, nr, 0.0, 0.0, 0.0, false)
	elif nav and nav.has_method("route_point"):
		wp = nav.route_point(u.pos, goal, nr)
	var dir: = (wp - u.pos).normalized() if wp.distance_squared_to(u.pos) > 1e-09 else (goal - u.pos).normalized()
	var endp: = u.pos + dir * minf(speed * dt, dist - stop)
	var hit: = sim.arena.terrain_contact(u.pos, endp, nr, false)
	u.pos = hit.point if not hit.is_empty() else endp
	u.vel = (u.pos - u.prev_pos) / dt
	u.facing = dir


func _summon_bite(u: BUnit, s: BUnit, t: BUnit, eff: Dictionary) -> void:
	u.next_attack = sim.time + u.interval
	# summon_body: these bites do not refresh the owner's combat timer (E22).
	var c: = {"source_type": "SUMMON", "snapshot": true, "ability": u.ctx.get("ability"), "team": sim.eteam(u), "summon_body": u.idx, "attack_from": u.pos}
	if not eff.is_empty() and float(eff.get("base", 0.0)) > 0.0:
		sim.apply_damage(s, t, eff, c)
	sim.fx("bite", t.pos, {"color": s.def.accent, "kind": u.kind})


# V2 companion (cerberus): owner's command target (alive enemy the pet observes,
# within commandRange of the owner) > nearest observed enemy within guardRange
# of the owner while the pet is inside the leash > follow behind the owner.
func _companion_step(u: BUnit, s: BUnit, dt: float) -> void:
	var r: = s.def.rule("companion") if s.is_hero else {}
	var speed: = maxf(float(r.get("speedMin", 110.0)), float(r.get("speedRatio", 1.2)) * sim.stat(s, S_MS))
	var team: = sim.eteam(u)
	var best: BUnit = null
	var ct: = sim.u_at(int(s.command.get("target", -1))) if s.alive else null
	if ct and ct.alive and ct != u and sim.eteam(ct) != team and not sim.has_status(ct, &"untargetable") and sim.observes(u, ct) and ct.pos.distance_to(s.pos) <= float(r.get("commandRange", 280.0)):
		best = ct
	# Guarding only while the pet itself is inside the leash around the owner.
	if best == null and u.pos.distance_to(s.pos) <= float(r.get("leash", 150.0)):
		var bd: = INF
		for t in sim.opponents(u):
			if t.pos.distance_to(s.pos) > float(r.get("guardRange", 160.0)) or not sim.observes(u, t):
				continue
			var dd: = t.pos.distance_to(u.pos)
			if dd < bd:
				bd = dd
				best = t
	if best == null:
		u.target_idx = -1
		var back: = s.facing.normalized() if s.facing.length_squared() > 0.01 else Vector2.RIGHT
		_entity_walk(u, s.pos - back * float(r.get("followOffset", 40.0)), speed, dt, 2.0)
		return
	u.target_idx = best.idx
	var gap: = best.pos.distance_to(u.pos)
	var reach: = sim.radius(best) + sim.radius(u) + float(r.get("reach", 10.0))
	if gap > reach + 0.5:
		_entity_walk(u, best.pos, speed, dt, reach - 0.5)
	if gap <= reach + 1.0 and sim.time >= u.next_attack and not sim.has_any(u, [&"disarm"]):
		var eff: Dictionary = sim.freeze_effects(s, best, [r.get("attack", {"type": "damage", "school": "physical", "base": 14.0, "ad": 0.22})], false, false)[0]
		_summon_bite(u, s, best, eff)


# V2 escort (hades shades): hold the ring slot around the owner and bite only
# enemies within reach; never chase.
func _escort_step(u: BUnit, s: BUnit, dt: float) -> void:
	var slot: = s.pos + Vector2.from_angle(float(u.ks.get("slot_angle", 0.0))) * float(u.ks.get("slot_radius", 50.0))
	_entity_walk(u, slot, sim.stat(s, S_MS) + float(u.ks.get("speed_bonus", 60.0)), dt, 0.5)
	var reach: = float(u.ks.get("reach", 24.0))
	var best: BUnit = null
	var bd: = INF
	for t in sim.opponents(u):
		var dd: = t.pos.distance_to(u.pos)
		if dd > sim.radius(t) + sim.radius(u) + reach or dd >= bd or not sim.observes(u, t):
			continue
		bd = dd
		best = t
	u.target_idx = best.idx if best else -1
	if best and sim.time >= u.next_attack and not sim.has_any(u, [&"disarm"]):
		_summon_bite(u, s, best, u.attack_eff)


# V2 chariot (achilles S4): hunts the team-seen enemy hero with the fewest
# knockbacks (< max), nearest on ties; contact knocks back and damages each
# enemy at most max times (only real displacements count), 1 s per target.
func _chariot_step(u: BUnit, s: BUnit, dt: float) -> void:
	var team: = sim.eteam(u)
	var knocks: Dictionary = u.ks.knocks
	var hit_at: Dictionary = u.ks.hit_at
	var maxk: = int(u.ks.get("max_knocks", 2))
	var anchor: = s.pos if s.alive else u.pos
	var reach_ffa: = float(u.ks.get("range_ffa", 900.0)) if sim.deathmatch else INF
	var eligible: Array[BUnit] = []
	for e in sim.heroes:
		if not e.alive or sim.eteam(e) == team or sim.has_status(e, &"untargetable") or e.chamber != u.chamber:
			continue
		if not sim.is_seen(team, e) or anchor.distance_to(e.pos) > reach_ffa or int(knocks.get(e.idx, 0)) >= maxk:
			continue
		eligible.append(e)
	var best: BUnit = null
	var best_k: = 1 << 30
	var bd: = INF
	for e in eligible:
		var k: = int(knocks.get(e.idx, 0))
		var dd: = e.pos.distance_to(u.pos)
		if k < best_k or (k == best_k and dd < bd):
			best = e
			best_k = k
			bd = dd
	if best == null:
		u.vel = Vector2.ZERO
		u.target_idx = -1
		return
	u.target_idx = best.idx
	var reach: = sim.radius(u) + sim.radius(best)
	if bd > reach:
		_entity_walk(u, best.pos, u.move_speed_ent, dt, reach - 1.0, float(u.ks.get("nav_radius", 18.0)))
	var knock: Dictionary = u.ks.get("knock", {})
	for e in eligible:
		if not e.alive or e.pos.distance_to(u.pos) > sim.radius(u) + sim.radius(e) + 1.0:
			continue
		if sim.time - float(hit_at.get(e.idx, -99.0)) < float(u.ks.get("icd", 1.0)) - 1e-09:
			continue
		hit_at[e.idx] = sim.time
		var radial: = (e.pos - u.pos).normalized() if e.pos.distance_squared_to(u.pos) > 1e-06 else u.facing
		var heading: = u.vel.normalized() if u.vel.length_squared() > 1.0 else radial
		var dir: = (radial + heading).normalized() if (radial + heading).length_squared() > 1e-06 else radial
		var c: = {"source_type": "SUMMON", "snapshot": true, "ability": u.ctx.get("ability"), "team": team, "attack_from": u.pos, "direction": dir}
		if not u.attack_eff.is_empty() and float(u.attack_eff.get("base", 0.0)) > 0.0:
			sim.apply_damage(s, e, u.attack_eff, c)
		if e.alive and displace(s, e, {"mode": "knockback", "distance": float(knock.get("distance", 130.0)), "speed": float(knock.get("speed", 600.0))}, c):
			knocks[e.idx] = int(knocks.get(e.idx, 0)) + 1
			sim.emit("CHARIOT_KNOCK", s.idx, e.idx, {"count": int(knocks[e.idx]), "entity": u.idx, "pos": e.pos})
		sim.fx("bite", e.pos, {"color": s.def.accent, "kind": u.kind})



# V2 hades S3 aura: every interval it damages the enemies the caster observes
# within the radius; the HP damage dealt becomes temporary max HP (capped at
# capRatio of the base max HP) that lasts until `linger` s after the aura.
func _soul_harvest(s: BUnit, b: ST.Buff) -> void:
	var k: = s.ks
	if not is_equal_approx(float(k.get("harvest_end", -1.0)), b.end):
		k["harvest_end"] = b.end
		k["harvest_ticks"] = 0
		k["harvest_next"] = sim.time
	var interval: = maxf(0.05, float(b.extra.get("interval", 0.5)))
	var ticks: = int(round(float(b.extra.get("duration", 5.0)) / interval))
	var ab: Defs.AbilityDef = null
	for a in s.def.abilities:
		if (a as Defs.AbilityDef).id == b.tag:
			ab = a
	var dmg: Dictionary = b.extra.get("damage", {"type": "damage", "school": "magic", "base": 6.0})
	var r: = float(b.extra.get("radius", 150.0))
	while int(k.harvest_ticks) < ticks and sim.time + 1e-09 >= float(k.harvest_next) and s.alive:
		k["harvest_ticks"] = int(k.harvest_ticks) + 1
		k["harvest_next"] = float(k.harvest_next) + interval
		var c: = {"ability": ab, "source_type": "ABILITY", "action_id": "harvest:%d:%d" % [s.idx, int(k.harvest_ticks)], "area": true}
		var gained: = 0.0
		for t in sim.opponents(s):
			if t.pos.distance_to(s.pos) > r + sim.radius(t) or not sim.observes(s, t):
				continue
			gained += sim.apply_damage(s, t, dmg, c)
		sim.fx("pulse", s.pos, {"radius": r, "color": s.def.accent, "small": true})
		if gained <= 0.0 or not s.alive:
			continue
		var cap: = s.base_max_hp * float(b.extra.get("capRatio", 0.25))
		var cur: = 0.0
		for hb in s.buffs:
			if hb.stat == S_HP and hb.tag == "soulHarvest" and hb.end > sim.time:
				cur = hb.amount * s.base_max_hp
		var total: = minf(cap, cur + gained)
		if total > cur + 1e-06:
			sim.add_buff(s, S_HP, total / s.base_max_hp, b.end - sim.time + float(b.extra.get("linger", 8.0)), s.idx, {"tag": "soulHarvest"})


func update_contacts(dt: float) -> void :
	for s in sim.heroes:
		if not s.alive:
			continue
		var k: = s.ks

		var harvest: = sim.get_buff(s, &"soulHarvest")
		if harvest:
			_soul_harvest(s, harvest)

		var ce: = sim.get_buff(s, &"contactExplosion")
		if ce and sim.time >= float(k.explode_at):
			var interval: = float(ce.extra.get("interval", 0.5))
			k.explode_at = sim.time + interval
			var spd: = s.vel.length()
			var base: = float(ce.extra.get("base", 24.0)) + float(ce.extra.get("speedRatio", 0.12)) * spd + float(ce.extra.get("rageRatio", 5.0)) * float(s.resources.get("rage", 0.0))
			var r: = sim.radius(s) + float(ce.extra.get("originContactPadding", 20.0))
			var c: = {"ability": s.def.abilities[2] if s.def.abilities.size() > 2 else null, "source_type": "ABILITY", "action_id": "contact:%d:%d" % [s.idx, int(sim.time / interval)], "area": true}
			for t in sim.opponents(s):
				if t.pos.distance_to(s.pos) <= r + sim.radius(t) and sim.los(s.pos, t.pos, 1.0):
					sim.apply_damage(s, t, {"type": "damage", "school": "magic", "base": base, "frozen": true}, c)
			sim.fx("pulse", s.pos, {"radius": r, "color": s.def.accent, "small": true})

		var orbit: = s.def.rule("orbit_aura")
		if not orbit.is_empty():
			if str(k.wing_mode) != "orbit" and sim.time >= float(k.wing_due):
				k.wing_mode = "orbit"
			if str(k.wing_mode) == "orbit":
				var before: = float(k.wing_angle)
				var adv: = TAU / float(orbit.get("interval", 2.0)) * (1.0 + sim.buff_sum(s, &"originOrbitSpeed")) * dt
				k.wing_angle = before + adv
				var wp: Array = []
				var orad: = float(orbit.get("radius", 72.0))
				var cr: = float(orbit.get("originContactRadius", 14.0))
				for j in 2:
					var oa: = before + j * PI
					var na: = float(k.wing_angle) + j * PI
					var cycle: = int(floor(na / TAU))
					var p0: = s.prev_pos + Vector2(cos(oa), sin(oa)) * orad
					var p1: = s.pos + Vector2(cos(na), sin(na)) * orad
					wp.append(p1)
					for t in sim.bodies_alive():
						if t == s:
							continue
						var cyc: Dictionary = k.wing_cycles[j]
						var hitkey: = "%d:%d" % [j, t.idx]
						if int(cyc.get(t.idx, -999)) == cycle or float(k.wing_hit_at.get(hitkey, -99.0)) > sim.time - 0.35:
							continue
						if Arena.seg_circle_t(p0, p1, t.pos, cr + sim.radius(t)) < 0.0 or not sim.los(s.pos, t.pos, 1.0):
							continue
						cyc[t.idx] = cycle
						k.wing_hit_at[hitkey] = sim.time
						var mult: = 1.0 + sim.buff_sum(s, &"orbitPower")
						var c2: = {"source_type": "PASSIVE", "proc": true, "wing": true}
						if sim.eteam(t) == sim.eteam(s):
							if t.hp < sim.max_hp(t):
								sim.apply_heal(s, t, {"base": float(orbit.allyHeal.base) * mult, "ap": float(orbit.allyHeal.ap) * mult}, c2)
								sim.fx("wing_hit", p1, {"color": s.def.accent, "ally": true})
						elif not sim.has_status(t, &"untargetable"):
							sim.apply_damage(s, t, sim.scale_damage([orbit.enemyDamage], mult)[0], c2)
							sim.fx("wing_hit", p1, {"color": s.def.accent, "ally": false})
				k.wing_pos = wp
			else:
				k.wing_pos = []

		var bat: Dictionary = k.bat
		if not bat.is_empty():
			if float(bat.until) > sim.time and not sim.has_any(s, [&"stun", &"sleep", &"airborne", &"suppression"]):
				var hitset: Dictionary = bat.hit
				for t in sim.query_cone(s.pos, bat.dir, 76.0, deg_to_rad(80.0), sim.opponents(s)):
					if hitset.has(t.idx) or not t.alive:
						continue
					hitset[t.idx] = true
					sim.apply_effects(s, t, bat.effects, bat.ctx)
					if t.alive:
						sim.apply_status(s, t, {"status": "stun", "duration": 0.3}, bat.ctx)
						var c3: Dictionary = (bat.ctx as Dictionary).duplicate()
						c3["direction"] = bat.dir
						displace(s, t, {"mode": "knockback", "distance": 50.0}, c3)
			else:
				k.bat = {}






func nexus_tick(dt: float) -> void :
	for u in sim.heroes:
		if not u.alive:
			continue
		if u.def.id == "world_tree":
			_seed(u)
		if u.ks.has("pending_pin"):
			var pin: Dictionary = u.ks.pending_pin
			if sim.time > float(pin.until):
				u.ks.erase("pending_pin")
			elif u.motion == null and sim.distance_to_wall(u.pos) <= sim.radius(u) + 8.0:
				var src: = sim.u_at(int(pin.source))
				if src and src.alive:
					sim.apply_status(src, u, {"status": "stun", "duration": 1.1}, sim.context(src, pin.ability, {}))
					sim.fx("wall_pin", u.pos, {"color": src.def.accent})
				u.ks.erase("pending_pin")

	if not sim.gardens.is_empty():
		var by_src: Dictionary = {}
		for g in sim.gardens:
			if float(g.end) > sim.time and float(g.budget) > 0.0:
				if not by_src.has(g.source):
					by_src[g.source] = []
				by_src[g.source].append(g)
		for src_idx in by_src:
			var s: = sim.u_at(int(src_idx))
			if s == null or not s.alive:
				continue
			var gs: Array = by_src[src_idx]
			gs.sort_custom( func(a, b): return float(a.rate) > float(b.rate))
			var allies: = sim.allies_of(sim.eteam(s))
			allies.sort_custom( func(a, b): return sim.hp_ratio(a) < sim.hp_ratio(b))
			for a in allies:
				if not sim.realm_allowed(s, a, {}):
					continue
				var covers: Array = []
				for g in gs:
					if float(g.budget) > 0.0 and Geometry2D.is_point_in_polygon(a.pos, g.points):
						covers.append(g)
				if covers.is_empty():
					continue
				var allowance: = float(covers[0].rate) * dt * (float(s.def.rule("nexus_seed_path").get("selfHealingRatio", 0.65)) if a == s else 1.0)
				for g in covers:
					if allowance <= 1e-09:
						break
					var amount: = minf(float(g.budget), minf(allowance, maxf(0.0, sim.max_hp(a) - a.hp)))
					if amount <= 0.0:
						continue
					var r: = sim.apply_heal(s, a, {"base": amount}, {"source_type": "PASSIVE", "silent": true})
					var spent: = float(r.effective) + float(r.reduced)
					g.budget = maxf(0.0, float(g.budget) - spent)
					allowance = maxf(0.0, allowance - spent)
		var thorned: Dictionary = {}
		for g in sim.gardens:
			if float(g.end) <= sim.time or float(g.get("thorn_until", 0.0)) <= sim.time or sim.time < float(g.get("next_thorn", 0.0)):
				continue
			g.next_thorn = sim.time + 0.65
			var s2: = sim.u_at(int(g.source))
			if s2 == null or not s2.alive:
				continue
			for x in sim.opponents(s2):
				var key: = "%d:%d" % [s2.idx, x.idx]
				if not thorned.has(key) and Geometry2D.is_point_in_polygon(x.pos, g.points):
					thorned[key] = true
					sim.apply_damage(s2, x, {"type": "damage", "school": "magic", "base": 16.0, "ap": 0.18}, sim.context(s2, s2.def.abilities[2], {}))
		var keepg: Array = []
		for g in sim.gardens:
			var so: = sim.u_at(int(g.source))
			if float(g.end) > sim.time and so and so.alive:
				keepg.append(g)
		sim.gardens = keepg

	for tw in sim.entities:
		if not tw.alive or not tw.structure or tw.kind == "bed" or tw.kind == "fuel_tank":
			continue
		var owner: = sim.u_at(tw.owner_idx)
		if owner == null or not owner.alive:
			tw.alive = false
			tw.end_time = sim.time
			continue
		if tw.kind == "flower":
			var best: BUnit = null
			for a in sim.heroes:
				if a.alive and sim.eteam(a) == sim.eteam(owner) and a.hp < sim.max_hp(a) - 0.01 and a.pos.distance_to(tw.pos) <= 18.0 + sim.radius(a) and sim.realm_allowed(owner, a, {}):
					if best == null or sim.hp_ratio(a) < sim.hp_ratio(best):
						best = a
			if best:
				var flower_heal_ratio: float = float(owner.def.rule("nexus_seed_path").get("selfHealingRatio", 0.45)) if best == owner else 1.0
				sim.apply_heal(owner, best, {"base": 45.0 * flower_heal_ratio, "ap": 0.35 * flower_heal_ratio}, tw.ctx)
				tw.alive = false
				tw.end_time = sim.time
				sim.fx("flower", tw.pos, {"color": owner.def.accent})
			continue
		if sim.has_any(tw, [&"stun", &"suppression", &"sleep"]) or owner.chamber != "" or sim.time < tw.next_pulse:
			continue
		tw.next_pulse = sim.time + (1.0 if tw.kind == "tree" else 0.9)
		if tw.kind == "tree":
			for a in sim.heroes:
				if a.alive and sim.eteam(a) == sim.eteam(owner) and a.pos.distance_to(tw.pos) <= 125.0 + sim.radius(a) and sim.los(tw.pos, a.pos, 2.0):
					var tree_heal_ratio: float = float(owner.def.rule("nexus_seed_path").get("selfHealingRatio", 0.45)) if a == owner else 1.0
					sim.apply_heal(owner, a, {"base": 14.0 * tree_heal_ratio, "ap": 0.12 * tree_heal_ratio}, tw.ctx.merged({"silent": true}))
			sim.fx("tree_pulse", tw.pos, {"color": owner.def.accent})
		elif tw.kind == "turret":
			var tgt: BUnit = null
			var bd: = INF
			for t in sim.opponents(tw):
				if not sim.observes(tw, t):
					continue
				var dd: = t.pos.distance_to(tw.pos)
				if dd <= tw.ent_range + sim.radius(t) and dd < bd and sim.los(tw.pos, t.pos, 2.0):
					bd = dd
					tgt = t
			if tgt == null:
				continue
			tw.facing = (tgt.pos - tw.pos).normalized()
			var mult: = 1.0 + 0.3 * (tw.level - 1)
			var base: = (20.0 + 0.25 * sim.stat(owner, S_AD) + 0.25 * sim.stat(owner, S_AP)) * mult
			var pa: = Defs.AbilityDef.new()
			pa.speed = 520.0
			pa.range = tw.ent_range
			pa.width = 8.0
			pa.color = owner.def.accent
			pa.pattern = "turret"
			pa.id = "turret_shot"
			var ctx: = {"source_type": "SUMMON", "team": sim.eteam(owner), "ability": owner.def.abilities[0]}
			sim.proj.spawn_from(tw, owner, tgt, tgt.pos, pa, [{"type": "damage", "school": "physical", "base": base, "frozen": true}], ctx, {"turret": true, "prefrozen": true})

	if not sim.chambers.is_empty():
		for c in sim.chambers:
			if c.ended:
				continue
			var s3: = sim.u_at(int(c.source))
			var t3: = sim.u_at(int(c.target))
			if s3 == null or t3 == null or not s3.alive or not t3.alive:
				_end_chamber(c, false)
				continue
			while int(c.pulses) < 5 and sim.time >= float(c.next_pulse):
				c.pulses = int(c.pulses) + 1
				c.next_pulse = float(c.next_pulse) + 0.55
				var cc: Dictionary = (c.ctx as Dictionary).duplicate()
				cc["realm"] = c.id
				sim.apply_damage(s3, t3, {"type": "damage", "school": "physical", "base": 18.0, "ad": 0.22}, cc)
				sim.fx("chamber_pulse", t3.pos, {"color": s3.def.accent})
				if not t3.alive:
					break
			if sim.time >= float(c.end):
				_end_chamber(c, s3.alive and t3.alive and int(c.pulses) == 5)
		var keepc: Array = []
		for c in sim.chambers:
			if not c.ended:
				keepc.append(c)
		sim.chambers = keepc


func _seed(s: BUnit) -> void :
	var k: = s.ks
	var p: = s.pos
	if s.motion != null:
		k.seeds = [p]
		k.last_seed = p
		return
	if k.last_seed == null:
		k.last_seed = p
		k.seeds = [p]
		return
	var last: Vector2 = k.last_seed
	var moved: = p.distance_to(last)
	if moved < 24.0:
		return
	if moved > 85.0:
		k.seeds = [p]
		k.last_seed = p
		return
	var ps: Array = k.seeds
	var loop: Array = []
	if ps.size() >= 4:
		for i in ps.size() - 2:
			var hit = Geometry2D.segment_intersects_segment(last, p, ps[i], ps[i + 1])
			if hit != null:
				var shape: Array = [hit]
				shape.append_array(ps.slice(i + 1))
				if _poly_area(shape) >= 900.0:
					loop = shape
					break
		if loop.is_empty() and p.distance_to(ps[0]) < 28.0:
			var closed: Array = ps.duplicate()
			closed.append(p)
			if _poly_area(closed) >= 900.0:
				loop = closed
	if not loop.is_empty() and _close_garden(s, loop):
		k.seeds = [p]
	else:
		ps.append(p)
		if ps.size() > 48:
			ps.pop_front()
		k.seeds = ps
	k.last_seed = p


func _poly_area(ps: Array) -> float:
	var a: = 0.0
	var n: = ps.size()
	for i in n:
		var p: Vector2 = ps[i]
		var q: Vector2 = ps[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _close_garden(s: BUnit, points: Array) -> bool:
	var ar: = _poly_area(points)
	var rule: Dictionary = s.def.rule("nexus_seed_path")
	if points.size() < 3 or ar < float(rule.get("minArea", 900.0)) or ar > float(rule.get("maxArea", 90000.0)):
		return false
	var budget: float = float(rule.get("budgetBase", 480.0)) + float(rule.get("budgetAp", 1.6)) * sim.stat(s, S_AP)
	var pts: = PackedVector2Array()
	for p in points:
		pts.append(p)
	var g: = {"id": sim.next_id(), "source": s.idx, "team": sim.eteam(s), "points": pts, "area": ar, "budget": budget, 
		"initial": budget, "rate": minf(float(rule.get("rateCap", 58.0)), float(rule.get("rateArea", 420000.0)) / ar), "start": sim.time, "end": sim.time + float(rule.get("duration", 14.0)), "thorn_until": 0.0, "next_thorn": sim.time}
	var mine: Array = []
	for x in sim.gardens:
		if x.source == s.idx and float(x.end) > sim.time:
			mine.append(x)
	if mine.size() >= int(rule.get("maxZones", 3)):
		mine[0].end = sim.time
	sim.gardens.append(g)
	sim.emit("GARDEN_CLOSED", s.idx, -1, {"area": ar, "budget": budget, "pos": s.pos})
	sim.fx("garden", s.pos, {"color": s.def.accent})
	return true
