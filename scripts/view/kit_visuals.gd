class_name KitVisuals
extends RefCounted






const DIM: = Color(0.19, 0.25, 0.32, 0.9)
const GOLD: = Color("#ffd37d")
const PLAGUE_BANK: = Color("#87e9b3")
# V2 hero colours.
const SOUL: = Color("#b4a8ff")
const FUEL: = Color("#ff8a3d")
const ARC: = Color("#6fd3ff")
const BRONZE: = Color("#d9a24f")
const EDICT: = Color("#f0c86a")


static func hi_of(c: Color) -> Color:
	return c.lightened(0.55)



static func pips(ci: CanvasItem, p: Vector2, value: int, total: int, rr: float, col: Color) -> void :
	var mx: = clampi(total, 1, 12)
	for i in mx:
		var a: = PI * 0.18 + (i + 0.5) / mx * PI * 0.64
		var on: = i < value
		ci.draw_arc(p, rr, a - 0.07, a + 0.07, 4, VfxStyle.hdr(col, 1.4) if on else DIM, 3.4 if on else 1.8, true)


static func dashed_ring(ci: CanvasItem, p: Vector2, rr: float, col: Color, w: float, n: int, phase: float) -> void :
	for k in n:
		var a0: = TAU * k / n + phase
		ci.draw_arc(p, rr, a0, a0 + TAU / n * 0.5, 4, col, w, true)



static func private_ok(v: BattleView, u: BUnit) -> bool:
	return v.perspective < 0 or v.sim.eteam(u) == v.perspective


static func out_of_combat(sim: BattleSim, u: BUnit) -> bool:
	var ooc: = u.def.rule("out_of_combat_speed")
	return not ooc.is_empty() and sim.time - u.last_combat_time >= float(ooc.get("delay", 2.5))






static func draw_under(v: BattleView, ci: CanvasItem, u: BUnit, p: Vector2, r: float) -> void :
	var sim: = v.sim
	var t: = sim.time
	var k: = u.ks
	var col: = u.def.accent
	var hi: = hi_of(col)
	var an: = v.anim

	for b in u.buffs:
		if b.stat == &"damageDealt" and b.end > t and b.source_idx != u.idx:
			var src: = sim.u_at(b.source_idx)
			if src and src.alive and src.def.id == "blood_mage" and v.can_see(src):
				var sp: = v.upos(src)
				var bc: = Color("#ed6e8f")
				ci.draw_line(sp, p, Color(bc, 0.18), 7.0, true)
				ci.draw_line(sp, p, Color(bc.r * 1.4, bc.g * 1.2, bc.b * 1.2, 0.7), 1.6, true)
				for j in 3:
					var f: = fmod(an * 0.9 + j / 3.0, 1.0)
					ci.draw_circle(sp.lerp(p, f), 2.6, Color(1.6, 0.5, 0.6, 0.85))

	var orbit: = u.def.rule("orbit_aura")
	if not orbit.is_empty():
		var rad: = float(orbit.get("radius", 72.0))
		dashed_ring(ci, p, rad, Color(col, 0.22), 1.0, 30, an * 0.15)

	if float(k.get("glide_until", 0.0)) > t:
		ci.draw_arc(p, r + 12.0, 0, TAU, 40, Color(col, 0.55), 1.5, true)
		var flap: = 0.18 * sin(an * 9.0)
		for sg: float in [-1.0, 1.0]:
			var ang: = - PI * 0.5 + sg * (1.15 + flap)
			Motifs.draw(ci, "wing", p + Vector2.from_angle(ang) * (r + 8.0), ang + (PI * 0.5 if sg < 0 else - PI * 0.5) + PI, 14.0, Color(col, 0.75), hi, an)

	if out_of_combat(sim, u) or _buff_on(sim, u, &"moveSpeed") or float(k.get("scent_until", -1.0)) > t:
		for sg2: float in [1.0, -1.0]:
			var a0: = 0.05 if sg2 > 0 else PI
			ci.draw_arc(p, r + 6.0, a0, a0 + 0.55, 8, Color(col, 0.4), 1.4, true)
			ci.draw_arc(p, r + 10.0, a0 + 0.1, a0 + 0.45, 8, Color(col, 0.22), 1.0, true)

	if _buff_on(sim, u, &"attackSpeedByMove"):
		for j2 in 3:
			var a1: = an * 3.2 + j2 * TAU / 3.0
			ci.draw_arc(p, r + 9.0 + j2 * 2.0, a1, a1 + 1.1, 12, Color(hi, 0.5), 1.6, true)

	if _buff_on(sim, u, &"originPredator"):
		var pulse: = 0.5 + 0.5 * sin(an * 6.0)
		ci.draw_arc(p, r + 7.0 + pulse * 3.0, 0, TAU, 40, Color(1.5, 0.35, 0.4, 0.35 + 0.3 * pulse), 2.2, true)
		for j3 in 3:
			var a2: = an * 1.4 + j3 * TAU / 3.0
			Motifs.draw(ci, "claw", p + Vector2.from_angle(a2) * (r + 13.0), a2, 5.0, Color(1.2, 0.3, 0.35, 0.55), Color(1.6, 0.8, 0.8, 0.6), an, 0.7)

	if _buff_on(sim, u, &"originRegenPool") or _buff_on(sim, u, &"regen"):
		ci.draw_arc(p, r + 9.0, 0, TAU, 40, Color(0.55, 1.5, 0.75, 0.35), 2.0, true)
		for j4 in 2:
			var ph: = fmod(an * 0.8 + j4 * 0.5, 1.0)
			var cp: = p + Vector2((j4 * 2 - 1) * (r + 4.0), -4.0 - ph * 16.0)
			var cc: = Color(0.6, 1.6, 0.8, 1.0 - ph)
			ci.draw_line(cp - Vector2(3, 0), cp + Vector2(3, 0), cc, 2.0, true)
			ci.draw_line(cp - Vector2(0, 3), cp + Vector2(0, 3), cc, 2.0, true)

	if _buff_on(sim, u, &"contactExplosion"):
		var fl: = 0.6 + 0.4 * sin(an * 23.0)
		ci.draw_arc(p, r + 9.0, 0, TAU, 40, Color(1.8, 0.8, 0.35, 0.55 * fl), 2.0, true)
		ci.draw_arc(p, r + 13.0, an * 4.0, an * 4.0 + 1.4, 12, Color(1.8, 1.2, 0.5, 0.6), 1.5, true)

	if float(k.get("wall_until", -1.0)) > t:
		var back: = - (u.vel.normalized() if u.vel.length() > 5.0 else u.facing)
		for j5 in 5:
			var fp: = p + back * (r * 0.6 + j5 * 7.0) + back.orthogonal() * sin(an * 20.0 + j5) * 3.0
			ci.draw_circle(fp, maxf(1.5, 6.0 - j5), Color(1.8, 0.7 - j5 * 0.08, 0.25, 0.55 - j5 * 0.09))

	if u.def.id == "politician" and bool(k.get("contemplating", false)):
		var stance_col: = Color("#ecd998")
		Motifs.outline(ci, Motifs.ngon(r + 11.0, 6, PI / 6.0, p), Color(stance_col, 0.75), 1.8)
		ci.draw_arc(p, r + 15.0, -PI * 0.5, PI * 1.5, 48, Color(stance_col, 0.18 + 0.08 * sin(an * 2.0)), 4.0, true)
		for pillar in 3:
			var pa: = p + Vector2((pillar - 1) * 7.0, r + 6.0)
			ci.draw_line(pa, pa + Vector2(0, 5), Color(stance_col, 0.8), 1.2, true)

	if _buff_on(sim, u, &"abilityCoefficient"):
		var buff_col: = Color("#ecd998")
		for j7 in 3:
			var arc_start: = -PI * 0.5 + j7 * TAU / 3.0 + an * 0.3
			ci.draw_arc(p, r + 8.0, arc_start, arc_start + 0.35, 8, Color(buff_col, 0.7), 2.0, true)

	for status in u.statuses:
		if status.end <= t or status.type != &"taunt":
			continue
		var target_idx: = int(status.extra.get("forced_target", -1))
		var target: = sim.u_at(target_idx)
		if target and target.alive and v.can_see(target):
			var end: = v.upos(target)
			ci.draw_line(p, end, Color(1.7, 0.65, 0.28, 0.32), 1.6, true)
			var tip: = p.lerp(end, 0.66)
			var d: = (end - p).normalized()
			ci.draw_colored_polygon(PackedVector2Array([tip + d * 6.0, tip - d * 4.0 + d.orthogonal() * 3.5, tip - d * 4.0 - d.orthogonal() * 3.5]), Color("#e8a06f"))

	if sim.has_status(u, &"projectile_guard"):
		Motifs.outline(ci, Motifs.ngon(r + 9.0, 6, PI / 6.0, p), Color(1.7, 1.1, 0.8, 0.65), 1.8)

	if sim.has_status(u, &"unstoppable"):
		Motifs.outline(ci, Motifs.ngon(r + 8.0, 6, PI / 6.0, p), Color(0.77, 0.95, 1.4, 0.65), 1.7)

	if sim.has_status(u, &"invisible"):
		dashed_ring(ci, p, r + 5.0, Color(0.8, 0.95, 1.2, 0.3), 1.2, 10, an * 1.5)

	_draw_v2_under(v, ci, u, p, r)

	if float(k.get("scent_until", -1.0)) > t and k.has("scent_pos"):
		var goal: Vector2 = k.scent_pos
		var dirs: = (goal - p)
		if dirs.length() > 30.0:
			var n: = int(minf(dirs.length(), 260.0) / 18.0)
			for j6 in n:
				var q: = p + dirs.normalized() * (r + 8.0 + j6 * 18.0)
				ci.draw_circle(q, 1.8, Color(1.5, 0.3, 0.35, 0.5 * (1.0 - float(j6) / n)))
	draw_weapon(v, ci, u, p, r)


static func _buff_on(sim: BattleSim, u: BUnit, key: StringName) -> bool:
	var b: = sim.get_buff(u, key)
	return b != null and b.end > sim.time






static func draw_weapon(v: BattleView, ci: CanvasItem, u: BUnit, p: Vector2, r: float) -> void :
	if v.quality < 1:
		return
	var id: = u.def.id
	var m: = str(Motifs.BASIC.get(id, ""))
	if m == "":
		return
	var sim: = v.sim
	var t: = sim.time
	var act: = u.action
	var face: = u.facing if u.facing.length_squared() > 0.01 else Vector2.RIGHT
	if act:
		var tg: = sim.u_at(act.target_idx)
		var goal: Vector2 = tg.pos if tg else act.target_pos
		if goal.distance_squared_to(u.pos) > 4.0:
			face = (goal - u.pos).normalized()
	var progress: = 0.0
	if act and act.windup:
		progress = clampf((t - act.started_at) / maxf(0.001, act.resolve_at - act.started_at), 0.0, 1.0)
	var rel: = float(v.swing_at.get(u.idx, -9.0))
	var follow: = 1.0 - (t - rel) / 0.24 if t - rel >= 0.0 and t - rel < 0.24 else 0.0
	var col: = u.def.accent
	var hi: = hi_of(col)
	var alpha: = 0.35 if sim.has_status(u, &"invisible") else 0.9
	var fa: = face.angle()
	if id in Motifs.RANGED_HOLD:
		var at: = p + Vector2(r + 3.0 - follow * 3.0, r * 0.28).rotated(fa)
		match id:
			"archer":
				Motifs.draw(ci, "bow", at, fa, 10.0, col, hi, progress, alpha)
			"sniper":
				Motifs.draw(ci, "rifle", at, fa, 10.0, col, hi, 0.0, alpha)
			_:
				var a0: = at + Vector2(-6, -9).rotated(fa)
				var a1: = at + Vector2(4, 10).rotated(fa)
				ci.draw_line(a0, a1, Color(col.darkened(0.2), alpha), 2.4, true)
				Motifs.draw(ci, m, a0, fa, 4.5, col, hi, sim.time, alpha)
				if progress > 0.0:
					ci.draw_circle(a0, 6.0 + progress * 4.0, Color(hi, 0.18 * progress))
	else:
		var swing: = -0.65 * progress if progress > 0.0 else (0.65 * (1.0 - follow) if follow > 0.0 else 0.0)
		var ra: = fa + 0.45 + swing
		var at2: = p + Vector2(r + 7.0, 2.0).rotated(ra)
		Motifs.draw(ci, m, at2, ra, 5.5, col, hi, sim.time, alpha)






static func draw_over(v: BattleView, ci: CanvasItem, u: BUnit, p: Vector2, r: float) -> void :
	var sim: = v.sim
	var t: = sim.time
	var k: = u.ks
	var col: = u.def.accent
	var hi: = hi_of(col)
	var id: = u.def.id

	var orbit: = u.def.rule("orbit_aura")
	if not orbit.is_empty():
		var rad: = float(orbit.get("radius", 72.0))
		var cr: = float(orbit.get("originContactRadius", 14.0))
		if str(k.get("wing_mode", "orbit")) == "orbit":
			var spd: = TAU / float(orbit.get("interval", 2.0)) * (1.0 + sim.buff_sum(u, &"originOrbitSpeed"))
			var alpha: = v.runner.alpha if v.runner else 1.0
			var base: = float(k.get("wing_angle", 0.0)) - spd * BattleSim.DT * (1.0 - alpha)
			var spin: = sim.buff_sum(u, &"originOrbitSpeed") > 0.0
			var tc: = UITheme.team_color(u.team)
			for j in 2:
				var a: = base + j * PI
				var wp: = p + Vector2.from_angle(a) * rad

				ci.draw_arc(p, rad, a - (0.9 if spin else 0.42), a, 12, Color(col, 0.12 if not spin else 0.2), 6.0, true)
				ci.draw_arc(p, rad, a - (0.5 if spin else 0.22), a, 10, Color(hi, 0.5), 1.3, true)

				ci.draw_circle(wp, cr, Color(col, 0.06))
				ci.draw_arc(wp, cr, 0, TAU, 20, Color(tc, 0.5), 1.0, true)
				Motifs.draw(ci, "wing", wp, a + PI * 0.5, 10.0, VfxStyle.hdr(col, 1.25 if spin else 1.05), col.darkened(0.45), t)
		else:
			ci.draw_arc(p, rad, -0.5, 0.5, 10, Color(col, 0.3), 1.3, true)

	if _buff_on(sim, u, &"originSniperRound") or _buff_on(sim, u, &"originPirateRound") or _buff_on(sim, u, &"nextBasicDamage"):
		var dp: = p + Vector2(0, r + 7.0)
		ci.draw_colored_polygon(Motifs.ngon(3.6, 4, 0.0, dp), Color(1.7, 1.45, 0.9))
		ci.draw_arc(dp, 5.5 + sin(v.anim * 8.0), 0, TAU, 12, Color(1.6, 1.3, 0.7, 0.5), 1.0, true)

	if sim.has_status(u, &"frenzy"):
		Motifs.draw(ci, "apple", p + Vector2(0, - r - 16.0 - 2.0 * sin(v.anim * 5.0)), 0.0, 5.0, Color(1.6, 1.25, 0.45), Color(1.8, 1.6, 1.0), t)
	# V2: full heal block (hades S2, healReduction 1.0) is a public status mark.
	for st in u.statuses:
		if st.type == &"healReduction" and st.end > t and st.magnitude >= 0.999:
			heal_block_mark(ci, p + Vector2(- r - 10.0, - r * 0.35), v.anim)
			break
	if not private_ok(v, u):
		return
	match id:
		"swordsman":
			pips(ci, p, int(k.get("basic_count", 0)) % 3, 3, r + 8.0, col)
		"nitro":
			var wb: = int(k.get("wall_bonus", 0))
			pips(ci, p, int(float(u.resources.get("rage", 0.0))), 8 + wb, r + 9.0, col)
			if wb > 0:
				ci.draw_arc(p, r + 13.0, PI * 0.15, PI * 0.85, 16, Color(GOLD, 0.7), 1.4, true)
		"dimensionalist":
			pips(ci, p, int(floor(float(u.resources.get("shards", 0.0)) / 10.0)), 4, r + 9.0, col)
		"blood_mage":
			var g: = float(k.get("growth_total", 0.0))
			if g > 0.0:
				pips(ci, p, mini(5, 1 + int(floor(g / 40.0))), 5, r + 8.0, col)
		"engineer":
			var fr: = int(float(u.resources.get("frustration", float(k.get("frustration", 0)))))
			if fr > 0:
				pips(ci, p, fr, 6, r + 8.0, col)
		"plague_doctor":
			var bank: = float(u.resources.get("healBank", 0.0))
			if bank > 0.0:
				ci.draw_arc(p, r + 7.0, PI * 0.18, PI * 0.18 + PI * 0.64 * clampf(bank / 1200.0, 0.02, 1.0), 16, VfxStyle.hdr(PLAGUE_BANK, 1.2), 2.2, true)
		"fisherman":
			var fish: Array = k.get("fish", [])
			for i in mini(2, fish.size()):
				var fp: = p + Vector2((-1.0 if i == 0 else 1.0) * (r + 12.0), 5.0)
				var ft: = str((fish[i] as Dictionary).get("type", ""))
				var fc: = {"attack": Color("#ff9a7a"), "defense": Color("#8fc8ff"), "health": Color("#8ff0b0")}.get(ft, col) as Color
				Motifs.draw(ci, "fish", fp, 0.0 if i == 1 else PI, 1.0, fc, hi_of(fc), t, 0.95)
		"hermes":
			var bw: Dictionary = k.get("borrowed", {})
			if not bw.is_empty() and float(bw.get("expires", 0.0)) > t:
				Motifs.draw(ci, "feather", p + Vector2(r + 12.0, -2.0), -0.5, 5.0, VfxStyle.hdr(col, 1.2), hi, t)
		"politician":
			pips(ci, p, int(u.resources.get("distrust", 0)), 10, r + 8.0, Color("#d6b979"))
		"war_machine":
			# Fuel 0-10 (private, like the other resource pips).
			pips(ci, p, int(floor(float(u.resources.get("fuel", 0.0)) + 1e-06)), 10, r + 8.0, FUEL)






static func label_for(v: BattleView, u: BUnit) -> Array:
	var sim: = v.sim
	if not u.sealed.is_empty():
		var parts: Array = []
		for i in u.sealed:
			parts.append("S%d" % (int(i) + 1))
		return ["봉인 " + "·".join(parts), Color("#f9bee7")]
	var pain: = 0
	var pain_end: = 0.0
	for st in u.statuses:
		if st.type == &"pain" and st.end > sim.time:
			pain = maxi(pain, st.stacks)
			pain_end = maxf(pain_end, st.end)
	if pain > 0:
		return ["고통 %d/6 · %.1f초" % [pain, pain_end - sim.time], Color("#ee9ec6") if pain < 6 else Color("#ff6fb5")]
	if u.def.id == "politician" and bool(u.ks.get("contemplating", false)):
		return ["관조 · CC 면역", Color("#ecd998")]
	if u.def.id == "war_machine":
		var od: = sim.get_status(u, &"overdrive")
		if od:
			return ["과열 폭주 · %.1f초" % maxf(0.0, od.end - sim.time), Color("#ff9a5b")]
	return []


# ------------------------------------------------------------------ V2 heroes

static func _draw_v2_under(v: BattleView, ci: CanvasItem, u: BUnit, p: Vector2, r: float) -> void :
	var sim: = v.sim
	var t: = sim.time
	var an: = v.anim
	var harvest: = sim.get_buff(u, &"soulHarvest")
	if harvest:
		soul_harvest(ci, u, p, r, harvest, t, an)
	if u.def.id == "hades" and private_ok(v, u) and sim.kits.concealed(u):
		var cr: = u.def.rule("concealed_regen")
		var regen: = not cr.is_empty() and u.hp < sim.max_hp(u) - 0.5 and t - u.last_damage_time >= float(cr.get("delay", 1.0))
		concealed_mark(ci, p, r, an, regen)
	var od: = sim.get_status(u, &"overdrive")
	if od:
		overdrive_flames(ci, p, r, clampf((od.end - t) / maxf(0.1, od.duration), 0.0, 1.0), an)
	if _buff_on(sim, u, &"arcConvert"):
		arc_shell(ci, p, r, an)
	var fg: = sim.get_status(u, &"frontGuard")
	if fg:
		var gd: Vector2 = fg.extra.get("dir", u.facing)
		front_guard(ci, p, r, gd.angle(), float(fg.extra.get("arc", deg_to_rad(120.0))), clampf((fg.end - t) / maxf(0.1, fg.duration), 0.0, 1.0))
	var act: = u.action
	if act and act.kind == "ability" and act.ability and act.windup and act.ability.flags.has("originCharge"):
		var n: = sim.kits.charge_count(u, act.ability, act.extra)
		var pr: = clampf((t - act.started_at) / maxf(0.01, act.resolve_at - act.started_at), 0.0, 1.0)
		# Shots load like the cast time grows: `min` after `base`, then one per `perStep`.
		var ch: Dictionary = act.ability.flag("originCharge", {})
		var e: = t - act.started_at
		var lo: = int(ch.get("min", 2))
		var base: = maxf(0.01, float(ch.get("base", 0.2)))
		var lit: = int(floor(lo * e / base)) if e < base else lo + int(floor((e - base) / maxf(0.01, float(ch.get("perStep", 0.3))) + 1e-06))
		charge_ring(ci, p, r, n, clampi(lit, 0, n), pr, private_ok(v, u), an)
	if u.motion:
		var mab = u.motion.ctx.get("ability")
		if mab is Defs.AbilityDef and VfxStyle.pattern_for(mab) in VfxStyle.DASH:
			var md: = u.motion.end - u.motion.start
			booster_jets(ci, p, r, md.normalized() if md.length_squared() > 1.0 else u.facing, an)
	for st in u.statuses:
		if st.type == &"root" and st.end > t and _edict_source(sim.u_at(st.source_idx)):
			edict_chains(ci, p, r, clampf((st.end - t) / maxf(0.1, st.duration), 0.0, 1.0), an)
			break


## Statuses keep only their source unit: a root is an edict when its source has the
## edictBind ability (torquemada S2, his only root).
static func _edict_source(src: BUnit) -> bool:
	if src == null or not src.is_hero:
		return false
	for a in src.def.abilities:
		if VfxStyle.pattern_for(a) == "edictBind":
			return true
	return false


## Hades S3: the 150 px harvest aura. The pulse follows the real tick clock
## (ks.harvest_next): souls stream inward between ticks, a ring lands on each tick.
static func soul_harvest(ci: CanvasItem, u: BUnit, p: Vector2, r: float, b: ST.Buff, t: float, an: float) -> void :
	var rad: = float(b.extra.get("radius", 150.0))
	var interval: = maxf(0.05, float(b.extra.get("interval", 0.5)))
	var ph: = clampf(1.0 - (float(u.ks.get("harvest_next", t)) - t) / interval, 0.0, 1.0)
	var left: = clampf((b.end - t) / maxf(0.1, float(b.extra.get("duration", 5.0))), 0.0, 1.0)
	ci.draw_circle(p, rad, Color(0.33, 0.26, 0.7, 0.055 + 0.035 * (1.0 - ph)))
	ci.draw_arc(p, rad, 0, TAU, 72, Color(0.05, 0.03, 0.1, 0.55), 4.0, true)
	dashed_ring(ci, p, rad, Color(SOUL, 0.7), 1.6, 36, an * 0.25)
	ci.draw_arc(p, rad - 5.0, - PI * 0.5, - PI * 0.5 + TAU * left, 64, Color(SOUL, 0.55), 2.0, true)
	# Tick ring: snaps to the edge on a tick and closes in on hades.
	var pr: = rad - (rad - r - 4.0) * ph
	ci.draw_arc(p, pr, 0, TAU, 56, Color(VfxStyle.hdr(SOUL, 1.25), 0.4 * (1.0 - ph)), 2.4 - 1.4 * ph, true)
	for j in 10:
		var f: = fmod(ph + j * 0.1, 1.0)
		var a: = j * TAU / 10.0 + an * 0.35 + f * 0.9
		var q: = p + Vector2.from_angle(a) * lerpf(rad - 6.0, r + 4.0, f)
		var sz: = 2.6 * (1.0 - f * 0.5)
		var al: = sin(PI * f) * 0.85
		ci.draw_circle(q, sz, Color(1.35, 1.2, 2.0, al))
		ci.draw_line(q, q - Vector2.from_angle(a) * (6.0 + 5.0 * (1.0 - f)), Color(SOUL, al * 0.45), 1.2, true)


## Hades P1: dark-vision shimmer while concealed; a green tick while Kynee heals.
static func concealed_mark(ci: CanvasItem, p: Vector2, r: float, an: float, regen: bool) -> void :
	ci.draw_arc(p, r + 5.0, 0, TAU, 40, Color(0.16, 0.1, 0.34, 0.45), 4.0, true)
	dashed_ring(ci, p, r + 6.5, Color(0.75, 0.62, 1.5, 0.3 + 0.12 * sin(an * 3.0)), 1.2, 14, - an * 0.7)
	for j in 3:
		var a: = an * 0.9 + j * TAU / 3.0
		ci.draw_circle(p + Vector2.from_angle(a) * (r + 9.0), 1.4, Color(0.7, 0.55, 1.4, 0.5))
	if regen:
		var ph: = fmod(an * 0.8, 1.0)
		var cp: = p + Vector2(r + 7.0, -3.0 - ph * 14.0)
		var cc: = Color(0.6, 1.6, 0.8, 1.0 - ph)
		ci.draw_line(cp - Vector2(3.5, 0), cp + Vector2(3.5, 0), cc, 2.2, true)
		ci.draw_line(cp - Vector2(0, 3.5), cp + Vector2(0, 3.5), cc, 2.2, true)


## War machine overdrive: flames licking off the body and the remaining-time arc.
static func overdrive_flames(ci: CanvasItem, p: Vector2, r: float, frac: float, an: float) -> void :
	for j in 10:
		var a: = j * TAU / 10.0 + an * 0.5
		var out: = Vector2.from_angle(a)
		var dirf: = (out * 0.55 + Vector2(0, -1.0)).normalized()
		var base: = p + out * (r + 0.5)
		var ln: = 7.0 + 6.0 * absf(sin(an * 9.0 + j * 1.7))
		var side: = dirf.orthogonal() * 3.4
		ci.draw_colored_polygon(PackedVector2Array([base + side, base + dirf * ln, base - side]), Color(1.9, 0.62 + 0.22 * sin(j + an * 7.0), 0.2, 0.75))
		ci.draw_colored_polygon(PackedVector2Array([base + side * 0.45, base + dirf * ln * 0.55, base - side * 0.45]), Color(2.1, 1.7, 0.8, 0.8))
	ci.draw_arc(p, r + 3.5, 0, TAU, 40, Color(1.8, 0.55, 0.18, 0.45 + 0.2 * sin(an * 14.0)), 2.0, true)
	ci.draw_arc(p, r + 15.0, 0, TAU, 48, Color(0.1, 0.03, 0.0, 0.5), 3.4, true)
	ci.draw_arc(p, r + 15.0, - PI * 0.5, - PI * 0.5 + TAU * frac, 48, Color(1.9, 0.8, 0.3, 0.9), 2.2, true)


## War machine S3: hexagonal arc-protector shell with sparks crawling on its edges.
static func arc_shell(ci: CanvasItem, p: Vector2, r: float, an: float) -> void :
	var hx: = Motifs.ngon(r + 8.0, 6, PI / 6.0 + an * 0.25, p)
	ci.draw_colored_polygon(hx, Color(ARC, 0.09))
	Motifs.outline(ci, hx, Color(0.6, 1.4, 1.9, 0.75), 1.8)
	var tick: = int(an * 12.0)
	for j in 2:
		var i0: = (tick + j * 3) % 6
		var v0: Vector2 = hx[i0]
		var v1: Vector2 = hx[(i0 + 1) % 6]
		var out: = ((v0 + v1) * 0.5 - p).normalized()
		var m1: = v0.lerp(v1, 0.33) + out * (3.0 + 2.0 * sin(tick * 1.3 + j))
		var m2: = v0.lerp(v1, 0.66) - out * (1.5 + 1.5 * sin(tick * 0.7 + j))
		ci.draw_polyline(PackedVector2Array([v0, m1, m2, v1]), Color(1.4, 2.0, 2.4, 0.9), 1.3, true)


## Achilles S2: the 120 degree bronze shield wedge in the guard direction.
static func front_guard(ci: CanvasItem, p: Vector2, r: float, th: float, arc: float, frac: float) -> void :
	var reach: = r + 34.0
	var pts: = PackedVector2Array([p])
	for j in 15:
		pts.append(p + Vector2.from_angle(th - arc * 0.5 + arc * j / 14.0) * reach)
	ci.draw_colored_polygon(pts, Color(BRONZE, 0.1))
	for sg: float in [-1.0, 1.0]:
		var e: = Vector2.from_angle(th + sg * arc * 0.5)
		ci.draw_line(p + e * (r + 13.0), p + e * reach, Color(BRONZE, 0.4), 1.2, true)
	ci.draw_arc(p, reach, th - arc * 0.5, th + arc * 0.5, 24, Color(BRONZE, 0.25), 1.0, true)
	ci.draw_arc(p, r + 10.0, th - arc * 0.5, th + arc * 0.5, 28, Color(0.09, 0.06, 0.02, 0.92), 8.5, true)
	ci.draw_arc(p, r + 10.0, th - arc * 0.5, th + arc * 0.5, 28, VfxStyle.hdr(BRONZE, 1.15), 5.0, true)
	ci.draw_arc(p, r + 11.6, th - arc * 0.42, th + arc * 0.42, 24, Color(2.0, 1.7, 1.1, 0.75), 1.2, true)
	ci.draw_arc(p, r + 10.0, th - arc * 0.5, th - arc * 0.5 + arc * frac, 28, Color(1.0, 0.9, 0.6, 0.35), 1.0, true)
	ci.draw_circle(p + Vector2.from_angle(th) * (r + 10.0), 3.2, Color(2.0, 1.6, 0.9))
	for j in 4:
		var ra: = th + (j - 1.5) * arc / 4.6
		ci.draw_circle(p + Vector2.from_angle(ra) * (r + 10.0), 1.1, Color(0.2, 0.12, 0.04, 0.9))


## War machine S2 charge: one missile pip per charged shot, lit as the charge builds
## (the unlit total is shown to the owner's side only).
static func charge_ring(ci: CanvasItem, p: Vector2, r: float, n: int, lit: int, pr: float, own: bool, an: float) -> void :
	var rr: = r + 14.0
	ci.draw_arc(p, rr, - PI * 0.5, - PI * 0.5 + TAU * pr, 40, Color(FUEL, 0.5), 1.4, true)
	var slots: = n if own else lit
	var div: = float(n) if own else 6.0
	for i in slots:
		var a: = - PI * 0.5 + (i + 0.5) * TAU / maxf(1.0, div) + an * 0.4
		var d: = Vector2.from_angle(a)
		var q: = p + d * rr
		var on: = i < lit
		var chev: = PackedVector2Array([q + d * 6.5, q - d * 4.0 + d.orthogonal() * 4.4, q - d * 1.8, q - d * 4.0 - d.orthogonal() * 4.4])
		ci.draw_circle(q, 6.0, Color(0.03, 0.02, 0.01, 0.7))
		if on:
			ci.draw_colored_polygon(chev, Color(2.0, 1.15, 0.45, 0.95))
		else:
			Motifs.outline(ci, chev, Color(FUEL, 0.75), 1.2)


## War machine S1 booster: twin jets behind the dash.
static func booster_jets(ci: CanvasItem, p: Vector2, r: float, md: Vector2, an: float) -> void :
	for j in 2:
		var off: = md.orthogonal() * (j * 2 - 1) * r * 0.42
		var base: = p - md * (r + 3.0) + off
		var ln: = 16.0 + 7.0 * absf(sin(an * 40.0 + j))
		ci.draw_colored_polygon(PackedVector2Array([base + md.orthogonal() * 3.6, base - md * ln, base - md.orthogonal() * 3.6]), Color(2.0, 0.95, 0.3, 0.85))
		ci.draw_colored_polygon(PackedVector2Array([base + md.orthogonal() * 1.6, base - md * ln * 0.55, base - md.orthogonal() * 1.6]), Color(2.2, 2.0, 1.4, 0.95))


## Torquemada S2: golden chains staked around the rooted target.
static func edict_chains(ci: CanvasItem, p: Vector2, r: float, frac: float, an: float) -> void :
	var gold: = VfxStyle.hdr(EDICT, 1.15)
	for i in 4:
		var a: = PI * 0.25 + i * PI * 0.5
		var stake: = p + Vector2.from_angle(a) * (r + 20.0)
		var end: = p + Vector2.from_angle(a) * (r - 2.0)
		ci.draw_line(stake, end, Color(0.08, 0.05, 0.0, 0.7), 4.0, true)
		var n: = 4
		for k in n:
			var q: = stake.lerp(end, (k + 0.5) / n) + Vector2(0, sin(an * 6.0 + k + i) * 0.6)
			ci.draw_set_transform(q, a + (PI * 0.5 if k % 2 == 1 else 0.0), Vector2(1.0, 0.55))
			ci.draw_arc(Vector2.ZERO, 3.2, 0, TAU, 10, gold, 1.5, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ci.draw_rect(Rect2(stake - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.15, 0.1, 0.02, 0.95))
		ci.draw_rect(Rect2(stake - Vector2(2.5, 2.5), Vector2(5, 5)), gold, false, 1.2)
	ci.draw_arc(p, r + 20.0, - PI * 0.5, - PI * 0.5 + TAU * frac, 40, Color(EDICT, 0.45), 1.2, true)


## Hades S2 heal block (healReduction 1.0): a green cross struck through.
static func heal_block_mark(ci: CanvasItem, q: Vector2, an: float) -> void :
	var g: = Color(0.55, 1.4, 0.75, 0.95)
	ci.draw_circle(q, 6.5, Color(0.05, 0.03, 0.1, 0.75))
	ci.draw_line(q - Vector2(4, 0), q + Vector2(4, 0), g, 2.2, true)
	ci.draw_line(q - Vector2(0, 4), q + Vector2(0, 4), g, 2.2, true)
	ci.draw_line(q + Vector2(-5, 5), q + Vector2(5, -5), Color(1.5, 0.45, 1.6, 0.95 - 0.15 * sin(an * 5.0)), 2.0, true)
	ci.draw_arc(q, 6.5, 0, TAU, 14, Color(SOUL, 0.8), 1.0, true)
