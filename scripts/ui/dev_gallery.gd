class_name DevGallery
extends RefCounted



const COMPS: = {
	1: [["metatron", "swordsman", "nitro", "dimensionalist", "blood_mage"], ["engineer", "plague_doctor", "fisherman", "hermes", "torturer"]], 
	2: [["archer", "sniper", "werewolf", "giant", "aphrodite"], ["pirate", "joker", "baseball", "hive_mind", "world_tree"]], 
	3: [["mage", "metatron", "torturer", "dimensionalist", "pirate"], ["joker", "blood_mage", "plague_doctor", "archer", "sniper"]], 
	4: [["swordsman", "archer", "mage"], ["giant", "baseball", "joker"]], 
	5: [["politician", "torturer", "giant"], ["archer", "hive_mind", "sniper"]], 
	6: [["hades", "war_machine", "torquemada"], ["achilles", "war_machine", "mage"]], 
}


static func config(variant: int) -> Dictionary:
	var c: Array = COMPS.get(variant, COMPS[1])
	return {"blue": c[0], "red": c[1], "arena_id": "classic", "seed": 4242, "blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}


static func _hero(sim: BattleSim, id: String, team: int) -> BUnit:
	for u in sim.heroes:
		if u.def.id == id and u.team == team:
			return u
	return null


static func _place(sim: BattleSim) -> void :
	for u in sim.heroes:
		var col: = u.slot
		u.pos = Vector2(260.0 + col * 230.0, 250.0 if u.team == 0 else 560.0)
		u.prev_pos = u.pos
		u.facing = Vector2.DOWN if u.team == 0 else Vector2.UP
		u.vel = Vector2.ZERO
		u.last_combat_time = -99.0


static func setup(sim: BattleSim, variant: int) -> void :
	_place(sim)
	if variant == 4:

		for u in sim.heroes:
			u.pos = Vector2(-2000.0 - u.idx * 40.0, -2000.0)
			u.prev_pos = u.pos
		return
	var t: = sim.time
	_states(sim, variant, t)

	for z in sim.zones.list:
		z.start = minf(z.start, t - 2.0)


static func _states(sim: BattleSim, variant: int, t: float) -> void :
	match variant:
		1:
			var meta: = _hero(sim, "metatron", 0)
			sim.add_buff(meta, &"originOrbitSpeed", 0.8, 99.0, meta.idx)
			var sw: = _hero(sim, "swordsman", 0)
			sw.ks["basic_count"] = 2
			var ni: = _hero(sim, "nitro", 0)
			ni.resources["rage"] = 6.0
			ni.ks["wall_bonus"] = 2
			ni.ks["wall_until"] = t + 99.0
			ni.vel = Vector2(80, 0)
			sim.add_buff(ni, &"contactExplosion", 1.0, 99.0, ni.idx)
			var dm: = _hero(sim, "dimensionalist", 0)
			dm.resources["shards"] = 30.0
			dm.ks["portal_armed_until"] = t + 99.0
			sim.portal_pairs.append({"id": 9001, "source": dm.idx, "team": 0, "a": dm.pos + Vector2(-60, 120), "b": dm.pos + Vector2(120, 120), "radius": 22.0, "end": t + 8.0, "enhanced": true, "ctx": {}})
			var bm: = _hero(sim, "blood_mage", 0)
			bm.ks["growth_total"] = 95.0
			sim.kits.create_entity(bm, bm.pos + Vector2(40, 60), "snake", 120.0, 10.0, {}, {"duration": 99.0})
			var en: = _hero(sim, "engineer", 1)
			en.resources["frustration"] = 3.0
			var tur: = sim.kits.make_structure(en, en.def.abilities[0], en.pos + Vector2(60, -70), "turret")
			if tur:
				tur.level = 3
			var pd: = _hero(sim, "plague_doctor", 1)
			pd.resources["healBank"] = 700.0
			sim.zones.spawn(pd, pd.pos + Vector2(0, -95), 60.0, 99.0, 0.25, [], "ally", {}, "mist", {"budget": 420.0, "initial": 420.0, "distance": 999.0, "range": 0.0, "speed": 0.0, "healed": 0.0})
			var fi: = _hero(sim, "fisherman", 1)
			fi.ks["fish"] = [{"id": 1, "type": "attack"}, {"id": 2, "type": "health"}]
			fi.resources["fish"] = 2.0
			sim.zones.spawn(fi, fi.pos + Vector2(70, -110), 90.0, 99.0, 0.1, [], "enemy", {}, "bait", {"triggered": {}, "lure": {}})
			var he: = _hero(sim, "hermes", 1)
			he.ks["borrowed"] = {"id": 1, "owner": meta.idx, "ability": meta.def.abilities[2], "expires": t + 24.0}
			var to: = _hero(sim, "torturer", 1)
			sim.apply_mark(to, ni, {"status": "pain", "stacks": 5, "maxStacks": 6, "duration": 5.0}, {})
		2:
			var ar: = _hero(sim, "archer", 0)
			sim.add_buff(ar, &"attackSpeedByMove", 0.3, 99.0, ar.idx)
			sim.add_buff(ar, &"moveSpeed", 0.3, 99.0, ar.idx)
			var sn: = _hero(sim, "sniper", 0)
			sim.add_buff(sn, &"originSniperRound", 1.0, 99.0, sn.idx)
			var ww: = _hero(sim, "werewolf", 0)
			sim.add_buff(ww, &"originPredator", 1.0, 99.0, ww.idx)
			sim.add_buff(ww, &"originScent", 1.0, 99.0, ww.idx)
			ww.ks["scent_pos"] = ww.pos + Vector2(40, 260)
			ww.ks["scent_seen"] = t
			ww.ks["scent_until"] = t + 99.0
			var gi: = _hero(sim, "giant", 0)
			sim.add_buff(gi, &"originRegenPool", 1.0, 99.0, gi.idx)
			var ap: = _hero(sim, "aphrodite", 0)
			var bed: = sim.kits.create_entity(ap, ap.pos + Vector2(-40, 110), "bed", 400.0, 25.0, {}, {"duration": 99.0, "structure": true})
			bed.ks["bed_visual"] = {"pairs": [{"ids": [ar.idx, sn.idx], "progress": 0.63, "done": false}], "odd": gi.idx, "occupants": 3}
			sim.apply_status(ap, ww, {"status": "frenzy", "duration": 99.0}, {})
			var pi: = _hero(sim, "pirate", 1)
			sim.add_buff(pi, &"originPirateRound", 1.0, 99.0, pi.idx)
			var jo: = _hero(sim, "joker", 1)
			sim.apply_mark(jo, ar, {"status": "confusion", "stacks": 3, "maxStacks": 5, "duration": 99.0}, {})
			sim.apply_mark(jo, gi, {"status": "confusion", "stacks": 4, "maxStacks": 5, "duration": 99.0}, {})
			var bb: = _hero(sim, "baseball", 1)
			sim.apply_status(bb, bb, {"status": "projectile_guard", "duration": 99.0}, {})
			var hv: = _hero(sim, "hive_mind", 1)
			sim.kits.create_entity(hv, hv.pos + Vector2(-50, -60), "brood", 90.0, 9.0, {}, {"duration": 99.0})
			sim.kits.create_entity(hv, hv.pos + Vector2(45, -70), "parasite", 60.0, 9.0, {}, {"duration": 99.0})
			var wt: = _hero(sim, "world_tree", 1)
			wt.ks["seeds"] = [wt.pos + Vector2(-120, -60), wt.pos + Vector2(-60, -130), wt.pos + Vector2(40, -120)]
			sim.kits.make_structure(wt, wt.def.abilities[0], wt.pos + Vector2(-130, 40), "tree")
			sim.kits.make_structure(wt, wt.def.abilities[3], wt.pos + Vector2(80, 30), "flower")
		3:
			var mg: = _hero(sim, "mage", 0)
			var tor: = _hero(sim, "torturer", 0)
			var jk: = _hero(sim, "joker", 1)
			sim.push_status(jk, &"silence", tor.idx, 3.0)
			var dm2: = _hero(sim, "dimensionalist", 0)
			var rz: = sim.zones.spawn(dm2, dm2.pos + Vector2(0, 150), 80.0, 99.0, 1.0, [], "enemy", {}, "rift", {"a": dm2.pos + Vector2(-80, 150), "b": dm2.pos + Vector2(80, 150), "reflect": 0.3})
			rz.pattern = "rift"
			var bz: = sim.zones.spawn(jk, jk.pos + Vector2(-90, -100), 26.0, 99.0, 0.1, [], "enemy", {}, "banana", {})
			bz.pattern = "banana"
			var ms: = sim.zones.spawn(mg, mg.pos + Vector2(40, 150), 70.0, 99.0, 0.5, [], "enemy", {"ability": mg.def.abilities[1]}, "zone", {})
			ms.pattern = "meteorZone"
			ms.color = mg.def.abilities[1].color
			var bmg: = _hero(sim, "blood_mage", 1)
			var bp: = sim.zones.spawn(bmg, bmg.pos + Vector2(0, -150), 70.0, 99.0, 0.5, [], "enemy", {"ability": bmg.def.abilities[1]}, "zone", {})
			bp.pattern = "bloodPool"
			bp.color = bmg.def.abilities[1].color
			var meta2: = _hero(sim, "metatron", 0)
			meta2.ks["glide_until"] = t + 99.0
			var pi2: = _hero(sim, "pirate", 0)
			sim.add_buff(pi2, &"nextBasicDamage", 0.35, 99.0, pi2.idx)
			var sn2: = _hero(sim, "sniper", 1)
			sim.apply_status(sn2, sn2, {"status": "invisible", "duration": 99.0}, {})
			sim.apply_status(sn2, sn2, {"status": "unstoppable", "duration": 99.0}, {})
		5:
			var politician: = _hero(sim, "politician", 0)
			var torturer: = _hero(sim, "torturer", 0)
			var giant: = _hero(sim, "giant", 0)
			var archer: = _hero(sim, "archer", 1)
			var hive: = _hero(sim, "hive_mind", 1)
			var sniper: = _hero(sim, "sniper", 1)
			var places: = [Vector2(400, 340), Vector2(710, 370), Vector2(710, 590), Vector2(805, 360), Vector2(960, 510), Vector2(960, 660)]
			var cast: = [politician, torturer, giant, archer, hive, sniper]
			for i in cast.size():
				cast[i].pos = places[i]
				cast[i].prev_pos = places[i]
			politician.ks["contemplating"] = true
			politician.resources["distrust"] = 6.0
			sim.add_buff(giant, &"armor", 0.3, 5.0, politician.idx, {"tag": "propaganda"})
			sim.add_buff(giant, &"abilityCoefficient", 0.2, 5.0, politician.idx, {"tag": "propaganda"})
			sim.warfare._create_prison(torturer, archer, {})
			sim.apply_mark(torturer, archer, {"status": "pain", "stacks": 6, "maxStacks": 6, "duration": 5.0}, {})
			sim.push_status(archer, &"silence", torturer.idx, 2.0)
			sim.push_status(hive, &"taunt", politician.idx, 1.6, {"forced_target": giant.idx})
		6:
			_v2_states(sim, t)



# V2 showcase: every persistent visual of the four new heroes at once. Blue is far
# enough from red (> vision 560) that hades counts as concealed.
static func _v2_states(sim: BattleSim, t: float) -> void :
	var hades: = _hero(sim, "hades", 0)
	var wm: = _hero(sim, "war_machine", 0)
	var torq: = _hero(sim, "torquemada", 0)
	var ach: = _hero(sim, "achilles", 1)
	var wm2: = _hero(sim, "war_machine", 1)
	var mage: = _hero(sim, "mage", 1)
	var cast: Array[BUnit] = [hades, wm, torq, ach, wm2, mage]
	var places: Array[Vector2] = [Vector2(250, 400), Vector2(330, 190), Vector2(330, 620), Vector2(1080, 300), Vector2(1180, 560), Vector2(1250, 180)]
	for i in cast.size():
		cast[i].pos = places[i]
		cast[i].prev_pos = places[i]
	wm.facing = Vector2.RIGHT
	ach.facing = Vector2.LEFT
	# Hades: harvest aura mid-pulse, kynee regen (hurt, quiet), cerberus and the shade ring.
	var h3: Defs.AbilityDef = hades.def.abilities[2]
	var harvest: Dictionary = (h3.effects[0] as Dictionary).duplicate()
	harvest["tag"] = h3.id
	sim.add_buff(hades, &"soulHarvest", 1.0, 3.2, hades.idx, harvest)
	hades.ks["harvest_next"] = t + 0.2
	hades.hp = sim.max_hp(hades) * 0.72
	hades.last_damage_time = t - 5.0
	sim.kits._ensure_companion(hades, hades.def.rule("companion"))
	var pet: = sim.u_at(int(hades.ks.get("pet_idx", -1)))
	if pet:
		pet.pos = hades.pos + Vector2(-80, 64)
		pet.prev_pos = pet.pos
		pet.facing = Vector2.RIGHT
	var h1: Defs.AbilityDef = hades.def.abilities[0]
	sim.kits.spawn_summons(hades, h1.effects[0], {"ability": h1, "team": 0, "source_type": "ABILITY"})
	# War machine (blue): tank on his back, fuel 7, arc protector, charging 5 missiles, genocide strip.
	sim.kits._ensure_tank(wm, wm.def.rule("fuel_tank"))
	wm.resources["fuel"] = 7.0
	sim.add_buff(wm, &"damageTaken", -0.4, 3.0, wm.idx, {"tag": "war_machine_3"})
	sim.add_buff(wm, &"arcConvert", 0.15, 3.0, wm.idx, {"tag": "war_machine_3"})
	var w2: Defs.AbilityDef = wm.def.abilities[1]
	var act: = ST.Action.new()
	act.ability = w2
	act.ability_index = 1
	act.extra = {"charge": 5}
	act.started_at = t - 0.62
	act.resolve_at = t + 0.48
	act.recover_at = act.resolve_at + w2.recovery
	act.target_pos = wm.pos + Vector2(300, 0)
	wm.action = act
	var w4: Defs.AbilityDef = wm.def.abilities[3]
	sim.zones.spawn_from_effect(wm, null, w4.effects[1], {"ability": w4, "team": 0, "source_origin": wm.pos + Vector2(40, 60), "target_pos": wm.pos + Vector2(440, 80)})
	# Torquemada: the purification fire on an ally spot.
	var q1: Defs.AbilityDef = torq.def.abilities[0]
	sim.zones.spawn_from_effect(torq, null, q1.effects[0], {"ability": q1, "team": 0, "hit_pos": torq.pos + Vector2(150, -40)})
	# Achilles: shield wedge toward blue, roar on blue, the chariot charging left.
	sim._front_guard(ach, {"duration": 2.0, "arcDegrees": 120.0, "moveSlow": 0.35}, {"target_pos": ach.pos + Vector2(-100, 30)})
	for b: BUnit in [hades, wm, torq]:
		sim.apply_status(ach, b, {"status": "roar", "duration": 6.0, "tenacityLoss": 0.1}, {})
	var a4: Defs.AbilityDef = ach.def.abilities[3]
	sim.kits.spawn_summons(ach, a4.effects[0], {"ability": a4, "team": 1, "source_type": "ABILITY"})
	for e in sim.entities:
		e.spawn_time = t - 1.0
		if e.kind == "chariot":
			e.pos = Vector2(820, 470)
			e.prev_pos = e.pos
			e.vel = Vector2(-290, -40)
			e.facing = e.vel.normalized()
	# War machine (red): tank burst, overdrive.
	sim.push_status(wm2, &"overdrive", wm2.idx, 10.0, {"mult": 1.5})
	wm2.ks["tank_ready_at"] = t + 6.5
	# Mage: torquemada's edict root and hades' heal block.
	sim.apply_status(torq, mage, {"status": "root", "duration": 1.25}, {"ability": torq.def.abilities[1]})
	sim.apply_status(hades, mage, {"status": "healReduction", "magnitude": 1.0, "duration": 5.0}, {"ability": hades.def.abilities[1]})


static func events(view: BattleView, p: float) -> void :
	var ev: = view.ev_fx
	ev.debug_p = p
	var ids: Array = EventFx.SIG_ORDER
	for i in ids.size():
		var id: = str(ids[i])
		var cx: = 110.0 + (i % 7) * 196.0
		var cy: = 118.0 + int(i / 7.0) * 258.0
		var d: = DB.char_def(id)
		ev.impact(id + ":basic", Vector2(cx - 58.0, cy - 60.0), 30.0, 0.35)
		for k in 4:
			var key: = "%s:skill:%d" % [id, k + 1]
			if EventFx.spec(key).is_empty():
				continue
			ev.impact(key, Vector2(cx + 2.0 + (k % 2) * 62.0, cy - 60.0 + int(k / 2.0) * 66.0), 40.0, 0.35)
		ev.strike(id + ":basic", Vector2(cx - 92.0, cy + 30.0), Vector2(cx - 52.0, cy + 8.0))
		ev.muzzle(id + ":basic", Vector2(cx - 80.0, cy + 70.0), Vector2(cx, cy + 70.0), 10.0)
		ev.status(id + ":skill:1", Vector2(cx - 2.0, cy + 110.0), 16.0, str(["stun", "root", "sleep", "silence"][i % 4]))
		ev.death(id + ":death", Vector2(cx + 64.0, cy + 110.0), 8.0)
		ev.sig(id, Vector2(cx - 58.0, cy + 118.0), 34.0, d.accent if d else Color.WHITE, 1, 1.0)
