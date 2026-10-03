class_name KitModel
extends RefCounted



const HARD_CC: = ["stun", "root", "airborne", "suppression", "sleep", "charm", "control", "taunt"]
static var _nominal: Dictionary = {}



static func stats_of_def(d: Defs.CharDef) -> Dictionary:
	return {"ad": d.stat("attackDamage"), "ap": d.stat("abilityPower"), "maxhp": d.stat("maxHealth"), 
		"armor": d.stat("armor"), "mr": d.stat("magicResistance"), "as": d.stat("attackSpeed"), 
		"ms": d.stat("moveSpeed"), "range": d.stat("attackRange"), "crit": d.stat("critChance"), 
		"critm": d.stat("critMultiplier"), "rscale": 1.0, "radius": d.stat("bodyRadius")}


static func stats_of_unit(sim: BattleSim, u: BUnit) -> Dictionary:
	return {"ad": sim.stat(u, &"attackDamage"), "ap": sim.stat(u, &"abilityPower"), "maxhp": sim.max_hp(u), 
		"armor": sim.stat(u, &"armor"), "mr": sim.stat(u, &"magicResistance"), "as": sim.stat(u, &"attackSpeed"), 
		"ms": sim.stat(u, &"moveSpeed"), "range": sim.stat(u, &"attackRange"), "crit": sim.stat(u, &"critChance"), 
		"critm": sim.stat(u, &"critMultiplier"), "rscale": sim.radius_scale(u), "radius": sim.radius(u), 
		"damage_mult": 1.0 + sim.buff_sum(u, &"damageDealt"), "coefficient": sim.ability_coefficient(u)}



# The value depends on the caster's stats as well as the ability, so the
# process-wide cache is keyed by both, and only for roster abilities. Keyed by
# the ability id alone, whichever caster asked first fixed the value for every
# later battle in the process: a telegraph whose source is gone (default
# stats), a borrowed ability cast by hermes, and per-battle virtual copies
# whose ids ("borrow_<n>", "") repeat across battles with other contents.
# fix_ai found a telemetry shard and a fresh process playing the same seed
# differently because of it (hard rule 1).
static func nominal_damage(a: Defs.AbilityDef, d: Defs.CharDef) -> float:
	if a == null:
		return 70.0
	var cacheable: bool = not a.virtual and a.id != ""
	var dk: String = d.id if d else ""
	var by_caster = _nominal.get(a.id) if cacheable else null
	if by_caster != null and (by_caster as Dictionary).has(dk):
		return float(by_caster[dk])
	var st: = stats_of_def(d) if d else {"ad": 70.0, "ap": 60.0, "maxhp": 1000.0, "rscale": 1.0}
	var out: = evaluate(a.effects, st, {"max_hp": 1000.0, "hp": 800.0})
	var v: = (float(out.phys) + float(out.magic)) * 0.77 + float(out.true_dmg)
	v = maxf(v, 25.0)
	if cacheable:
		if by_caster == null:
			by_caster = {}
			_nominal[a.id] = by_caster
		by_caster[dk] = v
	return v



static func evaluate(effects: Array, st: Dictionary, tgt: Dictionary, mult: float = 1.0) -> Dictionary:
	var out: = {"phys": 0.0, "magic": 0.0, "true_dmg": 0.0, "cc": {}, "slow": 0.0, "slow_dur": 0.0, "heal": 0.0,
		"shield": 0.0, "amp": 0.0, "execute": 0.0, "buffs": [], "summon": 0.0, "displace": 0.0, "mobility": 0.0,
		"guard": 0.0, "guard_dur": 0.0, "arc": 0.0, "arc_cap": 0.0, "resource_cost": 0.0, "cleanse": 0.0}
	_walk(effects, st, tgt, mult, out)
	return out


static func _walk(effects: Array, st: Dictionary, tgt: Dictionary, mult: float, out: Dictionary) -> void :
	for f in effects:
		var ty: = str(f.get("type", ""))
		match ty:
			"damage":
				var coefficient: float = float(st.get("coefficient", 1.0))
				var v: = float(f.get("base", 0.0)) + (float(f.get("ad", 0.0)) * float(st.get("ad", 0.0)) + float(f.get("ap", 0.0)) * float(st.get("ap", 0.0))) * coefficient
				v += float(f.get("selfMaxHp", 0.0)) * float(st.get("maxhp", 1000.0)) * coefficient
				v += float(f.get("targetMaxHp", 0.0)) * float(tgt.get("max_hp", 1000.0))
				v += float(f.get("targetMissingHp", 0.0)) * maxf(0.0, float(tgt.get("max_hp", 1000.0)) - float(tgt.get("hp", 1000.0)))
				v += float(f.get("originCcAd", 0.0)) * float(st.get("ad", 0.0)) * (1.0 if tgt.get("cc", false) else 0.0)
				if f.has("perTargetStatusStack"):
					v += float(tgt.get("own_stacks", 0)) * float(f.perTargetStatusStack.amount)
				if f.get("scaleWithRadius", false):
					v *= float(st.get("rscale", 1.0))
				v *= mult * float(st.get("damage_mult", 1.0))
				match str(f.get("school", "physical")):
					"magic":
						out.magic += v
					"true":
						out.true_dmg += v
					_:
						out.phys += v
			"dot":
				var ticks: = floorf(float(f.get("duration", 3.0)) / maxf(0.1, float(f.get("interval", 1.0))))
				_walk([f.damageEffect], st, tgt, mult * ticks, out)
			"zone":
				if f.get("originCoins", false):
					_walk(f.get("effects", []), st, tgt, mult * 0.5, out)
					continue
				if f.get("originBanana", false):
					out.cc["stun"] = maxf(float(out.cc.get("stun", 0.0)), 0.65 * 0.35)
					continue
				var ticks2: = clampf(float(f.get("duration", 1.0)) / maxf(0.1, float(f.get("interval", 0.5))), 1.0, 20.0)
				# V2 rect strips (war_machine S4, originRect length x width) are
				# priced like circles: a free enemy steps out of the 90 px strip
				# about as fast as out of a circle, so 30% of the ticks.
				var stay: = 0.3 if str(f.get("filter", "enemy")) == "enemy" else 0.5
				# V2 oncePerUnit (torquemada S1): each unit is affected once.
				if f.get("triggerOnce", false) or f.get("oncePerUnit", false):
					ticks2 = 1.0
					stay = 1.0
				var sub: = evaluate(f.get("effects", []), st, tgt, mult * ticks2 * stay)
				out.phys += sub.phys
				out.magic += sub.magic
				out.true_dmg += sub.true_dmg
				out.heal += sub.heal
				out.shield += sub.shield
				out.amp += sub.amp
				out.summon += sub.summon
				out.cleanse += sub.cleanse
				out.execute = maxf(out.execute, sub.execute)
				out.displace = maxf(out.displace, sub.displace)
				out.mobility = maxf(out.mobility, sub.mobility)
				out.buffs.append_array(sub.buffs)
				for cc_type in sub.cc:
					# A repeated zone refreshes control; its duration is not the
					# sum of every tick's duration. Account for the chance to stay.
					out.cc[cc_type] = maxf(float(out.cc.get(cc_type, 0.0)), float(sub.cc[cc_type]) * stay)
				out.slow = maxf(out.slow, sub.slow)
				out.slow_dur = maxf(out.slow_dur, float(f.get("duration", 1.0)) * 0.4)
			"delayed_area":
				_walk(f.get("effects", []), st, tgt, mult, out)
			"status":
				var s: = str(f.get("status", ""))
				var dur: = float(f.get("duration", 0.0))
				if s == "slow":
					out.slow = maxf(out.slow, float(f.get("magnitude", 0.3)))
					out.slow_dur = maxf(out.slow_dur, dur)
				elif s in HARD_CC or s == "silence":
					out.cc[s] = maxf(float(out.cc.get(s, 0.0)), dur + float(f.get("originThenStun", 0.0)))
				elif s == "healReduction" and f.has("whenTargetHpBelow"):
					# V2 hades S2: a heal block that only lands when the target is
					# under the threshold after the hit (the brain judges that from
					# the target's health: HadesTactics.heal_block_value).
					out["heal_block"] = maxf(float(out.get("heal_block", 0.0)), dur * float(f.get("magnitude", 1.0)))
					out["heal_block_below"] = float(f.whenTargetHpBelow)
			"mark":
				out.amp += float(f.get("damageAmp", 0.0)) * float(f.get("stacks", 1))
			"execute":
				out.execute = float(f.get("threshold", 0.0))
			"heal":
				var missing: float = maxf(0.0, float(tgt.get("max_hp", 1000.0)) - float(tgt.get("hp", 1000.0)))
				out.heal += (float(f.get("base", 0.0)) + float(f.get("ap", 0.0)) * float(st.get("ap", 0.0)) * float(st.get("coefficient", 1.0)) + float(f.get("missingHp", 0.0)) * missing) * mult
			"shield":
				out.shield += (float(f.get("base", 0.0)) + float(f.get("ap", 0.0)) * float(st.get("ap", 0.0)) * float(st.get("coefficient", 1.0))) * mult
			"buff":
				out.buffs.append(f)
				if str(f.get("stat", "")) == "soulHarvest":
					# V2 hades S3 aura: its ticks over the duration, half of them
					# landing on an enemy; the HP drained returns as temporary max
					# HP (about the mitigated share of it).
					var ticks3: float = roundf(float(f.get("duration", 5.0)) / maxf(0.05, float(f.get("interval", 0.5))))
					var dealt0: float = float(out.phys) + float(out.magic) + float(out.true_dmg)
					_walk([f.get("damage", {})], st, tgt, mult * ticks3 * 0.5, out)
					out["drain"] = float(out.get("drain", 0.0)) + (float(out.phys) + float(out.magic) + float(out.true_dmg) - dealt0) * 0.75
				# V2 war_machine S3: damage-taken cut and its arc shield.
				match str(f.get("stat", "")):
					"damageTaken":
						if float(f.get("amount", 0.0)) < 0.0:
							out.guard = maxf(float(out.guard), - float(f.amount))
							out.guard_dur = maxf(float(out.guard_dur), float(f.get("duration", 3.0)))
					"arcConvert":
						out.arc = maxf(float(out.arc), float(f.get("amount", 0.0)))
						out.arc_cap = maxf(float(out.arc_cap), float(f.get("capRatio", 0.2)) * float(st.get("maxhp", 1000.0)))
			"summon":
				var atk: Dictionary = f.get("attack", {})
				var per: = float(atk.get("base", 0.0)) + float(atk.get("ap", 0.0)) * float(st.get("ap", 0.0)) + float(atk.get("ad", 0.0)) * float(st.get("ad", 0.0))
				# V2 escort summons (hades shades) hold a ring slot around the owner
				# and never chase: fewer bites land, and the bodies screen shots.
				var escort: bool = str(f.get("originMode", "")) == "escort"
				out.summon += per * float(f.get("count", 1)) * float(f.get("duration", 8.0)) / maxf(0.5, float(f.get("interval", 1.1))) * (0.15 if escort else 0.35)
				if escort:
					var body: float = float(f.get("hp", 90.0)) + float(f.get("hpAp", 0.0)) * float(st.get("ap", 0.0)) + float(f.get("hpSelfMaxHp", 0.0)) * float(st.get("maxhp", 1000.0))
					out["screen"] = float(out.get("screen", 0.0)) + body * float(f.get("count", 1))
				if f.has("knock"):
					AchillesTactics.walk_chariot(f, per, out)
			"front_guard", "roar":
				# V2 achilles S2 (frontal immunity cone) and S3 (tenacity loss
				# that may go below zero); read back by AchillesTactics.
				AchillesTactics.walk_effect(f, out)
			"displace":
				out.displace = maxf(out.displace, float(f.get("distance", 0.0)))
			"cleanse":
				# V2: allies cleansed (count); the brain values what it removes
				# from its own allies' statuses (TorquemadaTactics.unit_value).
				out.cleanse += mult
			"move_self":
				out.mobility = maxf(out.mobility, float(f.get("distance", 100.0)))
			"consume_resource":
				var bonus: = float(f.get("bonusDamage", 0.0)) + float(f.get("bonusDamagePerSpent", 0.0)) * float(f.get("amount", 1.0))
				out.phys += bonus * mult
				# V2 perProjectile costs (war_machine S2): one unit per shot fired;
				# tgt.charge carries the planned shot count.
				var spent: = float(f.get("amount", 1.0))
				if f.get("perProjectile", false):
					spent *= float(tgt.get("charge", 1))
				out.resource_cost += spent


# V2 charged casts (flag originCharge {min, max, resource}): how many shots a
# cast fires. With the caster's resource known (have >= 0) it is the engine
# default min(max, have) clamped to the range; for an enemy whose resource is
# unknown it is the middle of the range.
static func charge_count(a: Defs.AbilityDef, have: float = -1.0) -> int:
	var ch: Dictionary = a.flag("originCharge", {})
	if ch.is_empty():
		return maxi(1, a.count)
	var lo: int = int(ch.get("min", 2))
	var hi: int = int(ch.get("max", 6))
	if have < 0.0:
		return int(roundf((lo + hi) * 0.5))
	return clampi(int(floor(have + 1e-06)), lo, hi)


# V2 damage-taken cut plus arc shield (war_machine S3) against `incoming`
# damage expected while it lasts: the cut part, plus the shield made from
# what still lands (capped).
static func guard_value(out: Dictionary, incoming: float) -> float:
	var g: float = clampf(float(out.get("guard", 0.0)), 0.0, 0.9)
	var saved: float = incoming * g
	var arc: float = minf(incoming * (1.0 - g) * float(out.get("arc", 0.0)), float(out.get("arc_cap", 0.0)))
	return saved + arc


static func mitigate(out: Dictionary, armor: float, mr: float) -> float:
	return float(out.phys) * 100.0 / (100.0 + maxf(0.0, armor)) + float(out.magic) * 100.0 / (100.0 + maxf(0.0, mr)) + float(out.true_dmg)


# Hard control (movement / action loss). Silence is kept apart: it does not
# stop movement or basic attacks, so it must not feed chain claims or the
# per-second control value; see silence_total.
static func cc_total(out: Dictionary) -> float:
	var t: = 0.0
	for k in out.cc:
		if k != "silence":
			t = maxf(t, float(out.cc[k]))
	return t


# Silence duration of an evaluated effect list (audit X4). The brain values it
# by the target's expected casts during the silence, not only mid-cast.
static func silence_total(out: Dictionary) -> float:
	return float(out.cc.get("silence", 0.0))


# V2 (torquemada P1/P2): crowd control evaluated on a target whose public
# definition has another tenacity than the 0.05 base, or a per-status tenacity
# rule, lasts that much less (sim.apply_status: tenacity skips airborne,
# suppression and control; status tenacity multiplies). Heroes at the base
# value are left untouched; only torquemada's beliefs are routed here
# (TacticianBrain._enemy_value), so V1 valuations do not change.
static func apply_tenacity(out: Dictionary, d: Defs.CharDef) -> void:
	if d == null:
		return
	var ten: float = clampf(d.stat("tenacity"), -0.3, 0.95)
	var rule: Dictionary = d.rule("status_tenacity") if d.has_rule("status_tenacity") else {}
	if absf(ten - 0.05) < 1e-06 and rule.is_empty():
		return
	var base_k: float = (1.0 - ten) / 0.95
	for k in out.cc:
		if str(k) in ["airborne", "suppression", "control"]:
			continue
		out.cc[k] = float(out.cc[k]) * base_k * (1.0 - clampf(float(rule.get(str(k), 0.0)), 0.0, 0.95))
	out.slow_dur = float(out.slow_dur) * base_k * (1.0 - clampf(float(rule.get("slow", 0.0)), 0.0, 0.95))


static func basic_dps(st: Dictionary, d: Defs.CharDef) -> float:
	if d and (d.has_rule("no_basic") or d.id == "politician"):
		return 0.0
	var ad: = float(st.get("ad", 60.0))
	var aspd: = float(st.get("as", 0.7))
	var crit: = 1.0 + float(st.get("crit", 0.08)) * (float(st.get("critm", 1.65)) - 1.0)
	var per: = ad * crit
	if d:
		if d.id == "swordsman":
			per += (28.0 + 0.35 * ad) / 3.0
		elif d.id == "pirate":
			per += 12.0 * 0.4
		elif d.id == "baseball":
			per *= 1.15
	return per * aspd



static func delivery_hit(a: Defs.AbilityDef) -> float:
	if a.delivery == "direct" or a.homing:
		return 0.92
	if a.target == "self":
		return 0.72
	match a.delivery:
		"projectile":
			return 0.5 if a.width < 60.0 else 0.62
		"line":
			return 0.58
		"cone":
			return 0.66
		"area":
			return 0.6
	return 0.6


# V2: damage per second of a permanent companion entity (passive rule
# "companion", hades' cerberus) from public data; 0 for every other hero.
static func companion_dps(d: Defs.CharDef, ad: float) -> float:
	if d == null or not d.has_rule("companion"):
		return 0.0
	var r: Dictionary = d.rule("companion")
	var atk: Dictionary = r.get("attack", {})
	return (float(atk.get("base", 0.0)) + float(atk.get("ad", 0.0)) * ad) / maxf(0.25, float(r.get("interval", 1.0)))


static var _support: Dictionary = {}
# V2: nominal support value of one allied cleanse (crowd control and debuffs
# removed, in heal-equivalent points) and of the knockback peel an ability adds
# when it also cleanses allies (torquemada S3: allies cleansed, enemies pushed).
const CLEANSE_SUPPORT: = 110.0
const PEEL_SUPPORT: = 0.3



static func support_rate(d: Defs.CharDef) -> float:
	if _support.has(d.id):
		return _support[d.id]
	var st: = stats_of_def(d)
	var v: = 0.0
	if d.id == "politician":
		# Team support value, not imaginary basic damage; no 1v1 power is added.
		v = 24.0
	for a in d.abilities:
		var ab: Defs.AbilityDef = a
		if ab.hostile and ab.target == "enemy":
			continue
		var ev: = evaluate(ab.effects, st, {"max_hp": 1000.0, "hp": 700.0})
		v += (float(ev.heal) + float(ev.shield)) / maxf(2.0, ab.cooldown)
		if float(ev.cleanse) > 0.0:
			v += (minf(1.0, float(ev.cleanse)) * CLEANSE_SUPPORT + float(ev.displace) * PEEL_SUPPORT) / maxf(2.0, ab.cooldown)
	_support[d.id] = v
	return v



static var _eprof_base: Dictionary = {}


# The static part of an enemy profile (hero definitions never change during a
# battle); only ready-probabilities and movement are recomputed per call.
static func _enemy_base(d: Defs.CharDef) -> Dictionary:
	var key: int = d.get_instance_id()
	if _eprof_base.has(key):
		return _eprof_base[key]
	var st: = stats_of_def(d)
	var rows: Array = []
	for i in d.abilities.size():
		var a: Defs.AbilityDef = d.abilities[i]
		var ev: = evaluate(a.effects, st, {"max_hp": 1000.0, "hp": 800.0})
		var rng_: = a.range
		if a.target == "self" and a.delivery == "area":
			rng_ = a.radius
		if a.action == "contactDash":
			rng_ = float(a.flag("originDistance", a.range))
		# V2 charged volleys: an enemy's charge is unknown, price a mid charge.
		var shots: float = float(charge_count(a)) if not a.flag("originCharge", {}).is_empty() else 1.0
		rows.append({"dmg": mitigate(ev, 35.0, 30.0) * shots, "cc": cc_total(ev), "range": rng_, "hostile": a.hostile, "slot": a.slot, "hit": delivery_hit(a)})
	# A permanent companion (hades' cerberus) bites beside its owner.
	var base: Dictionary = {"st": st, "dps": (basic_dps(st, d) + companion_dps(d, float(st.ad)) * 0.6) * 100.0 / 130.0, "rows": rows}
	_eprof_base[key] = base
	return base


# hidden_floor (audit D12): intel.ready_prob decays the readiness of an unseen
# enemy's abilities toward 0 the longer it is hidden. With two teams a hidden
# enemy has nobody else to spend them on, so an ability whose full cooldown has
# certainly elapsed keeps at least `hidden_floor`. 0 disables (deathmatch).
static func enemy_profile(intel: TeamIntel, b: TeamIntel.EnemyBelief, hidden_floor: float = 0.0) -> Dictionary:
	var base: Dictionary = _enemy_base(b.def)
	var st: Dictionary = base.st
	var dps: float = base.dps
	# V2 war_machine overdrive (public status / event): attack speed x1.5.
	if b.def.id == "war_machine" and intel.overdrive_believed(b):
		dps *= WarMachineTactics.OVERDRIVE_MULT
	var burst: = 0.0
	var cc: = 0.0
	var reach: = float(st.range) + 40.0
	var list: Array = []
	var rows: Array = base.rows
	for i in rows.size():
		var row: Dictionary = rows[i]
		var p: = intel.ready_prob(b, i)
		if hidden_floor > 0.0 and p > 0.0 and p < hidden_floor:
			p = maxf(p, hidden_floor * hidden_ready(intel, b, i))
		if row.hostile:
			var dmg: float = row.dmg
			var ccd: float = row.cc
			var rng_: float = row.range
			burst += dmg * p
			cc += ccd * p
			reach = maxf(reach, rng_ + 30.0)
			list.append({"range": rng_, "dmg": dmg * p, "cc": ccd * p, "slot": row.slot, "p": p, "hit": row.hit})
	return {"dps": dps, "burst": burst, "cc": cc, "reach": reach, "abilities": list, "ms": b.ms(), "range": st.range,
		"support": support_rate(b.def)}


# 1.0 when a hidden enemy's ability is certainly off cooldown by the public
# clock (never seen used, or a full cooldown since its last observed use) and
# no explicit report or disclosure says otherwise; else 0.0.
static func hidden_ready(intel: TeamIntel, b: TeamIntel.EnemyBelief, i: int) -> float:
	if b.visible or b.dead or i >= b.def.abilities.size() or b.sealed.has(i):
		return 0.0
	var now: float = intel.sim.time
	if b.reports_until >= now or (b.cd_disc_until >= now and b.cd_disc[i] >= 0.0):
		return 0.0
	if b.cd_last[i] < -100.0:
		return 1.0
	var a: Defs.AbilityDef = b.def.abilities[i]
	return 1.0 if now >= b.cd_last[i] + a.cooldown - b.cd_cdr[i] else 0.0
