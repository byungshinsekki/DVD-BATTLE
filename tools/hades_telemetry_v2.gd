extends SceneTree

# V2 하데스 (hades) mini-telemetry (H-AI-hades). Plays the cases of a
# balance_runner JSON file exactly like tools/balance_runner.gd (tactician on
# both sides, same configs, same signature) and adds per-skill hades metrics:
# casts per minute alive versus the cooldown-limited maximum, the share of
# casts that hit or achieved their purpose, Kynee regeneration, cerberus bites
# and time spent stuck. One JSON line per case.
#   godot --headless --path . --script res://tools/hades_telemetry_v2.gd -- --cases=<json> --output=<jsonl>
# tools/hades_telemetry_v2_cases.json holds the wave 2 set: 30 seeded 3v3
# elimination matchups (hades + 2 random partners vs 3 random opponents from
# the 22 V1 heroes) on 6 maps, each mirrored by side (60 cases). The same file
# runs unchanged through tools/balance_runner.gd (identical signatures).

const HADES: = "hades"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	var data = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("cases", ""))))
	if not data is Array:
		push_error("cases must be a JSON array")
		quit(2)
		return
	var out: FileAccess = FileAccess.open(str(args.get("output", "user://hades_telemetry.jsonl")), FileAccess.WRITE)
	var failures: int = 0
	var n: int = 0
	for config in data:
		var row: Dictionary = _play(config)
		if str(row.get("invariant_error", "")) != "":
			failures += 1
		out.store_line(JSON.stringify(row))
		out.flush()
		n += 1
		print("CASE ", n, "/", data.size(), " ", row.case_id, " winner=", row.winner, " hades_team=", row.hades_team, " t=", snappedf(float(row.duration), 0.01))
	out.close()
	print("TELEMETRY done=", n, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _play(config: Dictionary) -> Dictionary:
	var sim: BattleSim = BattleSim.new(config)
	sim.controllers[0] = AIFactory.make(str(config.get("blue_ai", "tactician")), sim, 0)
	sim.controllers[1] = AIFactory.make(str(config.get("red_ai", "tactician")), sim, 1)
	sim.start()
	var h: BUnit = null
	for u in sim.heroes:
		if u.def.id == HADES:
			h = u
	var casts: Dictionary = {}
	var cast_log: Array = []
	var shades: Dictionary = {}
	var pet_ids: Dictionary = {}
	var s2_hits: Dictionary = {}
	var s3_hits: Dictionary = {}
	var s3_ticks: int = 0
	var heal_blocks: int = 0
	var shade_bite_hero: float = 0.0
	var shade_taken: float = 0.0
	var pet_bite_hero: float = 0.0
	var pet_deaths: int = 0
	var shade_kills: int = 0
	var pet_on_order: int = 0
	var pet_on_any: int = 0
	var regen: float = 0.0
	var concealed_t: float = 0.0
	var low_concealed_t: float = 0.0
	var low_t: float = 0.0
	var alive_t: float = 0.0
	var stuck_t: float = 0.0
	var stuck_why: Dictionary = {}
	var hide_t: float = 0.0
	var harvest_gain: float = 0.0
	var hist: Array = []
	var invariant: String = ""
	var cast_ctx: Array = []
	while sim.state == BattleSim.RUNNING:
		var hp0: float = h.hp
		var mx0: float = sim.max_hp(h)
		var quiet0: bool = h.alive and sim.time - h.last_damage_time >= 1.0 - 1e-9
		sim.step()
		var dt: float = BattleSim.DT
		for ev in sim.tick_events:
			var ty: String = str(ev.type)
			if ty == "CAST_STARTED" and int(ev.s) == h.idx:
				var slot: int = int(ev.get("slot", 0))
				casts[slot] = int(casts.get(slot, 0)) + 1
				cast_log.append([slot, sim.time])
				cast_ctx.append(_cast_context(sim, h, slot))
			elif ty == "SUMMON_CREATED" and int(ev.s) == h.idx:
				if str(ev.get("kind", "")) == "shade":
					shades[int(ev.g)] = cast_log.size() - 1
				elif str(ev.get("kind", "")) == "cerberus":
					pet_ids[int(ev.g)] = true
			elif ty == "HEALTH_DAMAGED" or ty == "SHIELD_ABSORBED":
				var g: BUnit = sim.u_at(int(ev.g))
				var amount: float = float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
				if shades.has(int(ev.g)):
					shade_taken += amount
					_mark(cast_log, int(shades[int(ev.g)]), "screen")
				if int(ev.s) != h.idx or g == null or not g.is_hero or g.team == h.team:
					continue
				var ab = ev.get("ability")
				var aid: String = (ab as Defs.AbilityDef).id if ab is Defs.AbilityDef else ""
				if str(ev.get("source_type", "")) == "SUMMON":
					if aid == "hades_1":
						shade_bite_hero += amount
						_mark_last(cast_log, 1, sim.time, 7.6, "bite")
					else:
						pet_bite_hero += amount
				elif aid == "hades_2":
					_mark_last(cast_log, 2, sim.time, 1.0, "hit")
				elif aid == "hades_3":
					s3_ticks += 1
					_mark_last(cast_log, 3, sim.time, 5.5, "hit")
			elif ty == "HEAL_BLOCKED" and int(ev.s) == h.idx:
				heal_blocks += 1
				_mark_last(cast_log, 2, sim.time, 1.0, "block")
			elif ty == "SUMMON_DESTROYED":
				if pet_ids.has(int(ev.g)):
					pet_deaths += 1
				elif shades.has(int(ev.g)):
					shade_kills += 1
		if h.alive:
			alive_t += dt
			var conc: bool = sim.kits.concealed(h)
			if conc:
				concealed_t += dt
			if hp0 / maxf(1.0, mx0) < 0.6:
				low_t += dt
				if conc:
					low_concealed_t += dt
				if str(h.command.get("purpose", "")).contains("은신 회복"):
					hide_t += dt
			if conc and quiet0 and h.hp > hp0 and is_equal_approx(sim.max_hp(h), mx0):
				regen += h.hp - hp0
			if sim.max_hp(h) > mx0 + 0.01:
				harvest_gain += sim.max_hp(h) - mx0
			# Stuck: alive, not acting, an order to move, and under 4 px of
			# progress in the last second.
			hist.append(h.pos)
			if hist.size() > 30:
				hist.pop_front()
			if hist.size() == 30 and h.action == null and str(h.command.get("kind", "")) == "move" \
					and (hist[0] as Vector2).distance_to(h.pos) < 4.0 and (h.command.get("goal", h.pos) as Vector2).distance_to(h.pos) > 24.0:
				stuck_t += dt
				var why: String = str(h.command.get("purpose", ""))
				stuck_why[why] = float(stuck_why.get(why, 0.0)) + dt
			for pid in pet_ids:
				var pet: BUnit = sim.u_at(int(pid))
				if pet and pet.alive and pet.target_idx >= 0:
					pet_on_any += 1
					if pet.target_idx == int(h.command.get("target", -2)):
						pet_on_order += 1
		if sim.tick % 30 == 0:
			for u in sim.units:
				if not is_finite(u.hp) or not u.pos.is_finite():
					invariant = "non-finite state: " + u.id
		if sim.tick > int(sim.max_time * 30.0) + 10:
			invariant = "simulation failed to terminate"
		if invariant != "":
			break
	var result: Dictionary = sim.result()
	var final_state: Array = []
	for u in sim.heroes:
		final_state.append([u.id, u.hp, u.pos.x, u.pos.y, u.st_damage, u.st_casts])
	var signature: String = JSON.stringify([result.winner, result.duration, final_state]).sha256_text()
	var purpose: Dictionary = {}
	for row in cast_log:
		var key: String = str(row[0])
		var p: Dictionary = purpose.get(key, {"casts": 0, "hit": 0, "block": 0, "bite": 0, "screen": 0, "achieved": 0})
		p.casts += 1
		var flags: Dictionary = row[2] if row.size() > 2 else {}
		for f in flags:
			p[f] = int(p.get(f, 0)) + 1
		if int(row[0]) == 1 and (flags.has("bite") or flags.has("screen")):
			p.achieved += 1
		elif int(row[0]) != 1 and flags.has("hit"):
			p.achieved += 1
		purpose[key] = p
	var hu: Dictionary = {}
	for r in result.units:
		if int(r.idx) == h.idx:
			hu = r
	var out: Dictionary = {"case_id": config.get("id", ""), "arena": config.get("arena_id", ""), "seed": config.get("seed", 0),
		"winner": result.winner, "reason": result.reason, "duration": result.duration, "hades_team": h.team,
		"timeout": str(result.reason) == "time_limit", "signature": signature, "alive_s": alive_t, "casts": casts, "purpose": purpose,
		"cast_context": cast_ctx, "heal_blocks": heal_blocks, "s3_ticks_on_heroes": s3_ticks, "shade_bites_on_heroes": shade_bite_hero,
		"shade_damage_taken": shade_taken, "shade_kills": shade_kills, "pet_bites_on_heroes": pet_bite_hero, "pet_deaths": pet_deaths,
		"cast_log": cast_log,
		"pet_on_order_share": float(pet_on_order) / maxf(1.0, float(pet_on_any)), "kynee_regen": regen,
		"concealed_s": concealed_t, "low_s": low_t, "low_concealed_s": low_concealed_t, "harvest_gain_hp": harvest_gain,
		"stuck_s": stuck_t, "stuck_why": stuck_why, "kynee_hide_order_s": hide_t, "hades": hu, "invariant_error": invariant}
	sim.dispose()
	return out


# Context of a cast: nearest seen enemy hero, enemies within 150, concealment.
func _cast_context(sim: BattleSim, h: BUnit, slot: int) -> Dictionary:
	var nearest: float = INF
	var in_aura: int = 0
	for e in sim.heroes:
		if not e.alive or e.team == h.team:
			continue
		var d: float = e.pos.distance_to(h.pos)
		if sim.is_seen(h.team, e):
			nearest = minf(nearest, d)
		if d <= 150.0 + sim.radius(e) and sim.observes(h, e):
			in_aura += 1
	var ctl = sim.controllers[h.team]
	var decided: float = -1.0
	if ctl is TacticianBrain and (ctl as TacticianBrain).mem.has(h.idx):
		decided = sim.time - float((ctl as TacticianBrain).mem[h.idx].get("t", sim.time))
	return {"slot": slot, "t": sim.time, "nearest_seen": nearest if nearest < INF else -1.0, "in_aura": in_aura,
		"concealed": sim.kits.concealed(h), "hpr": sim.hp_ratio(h), "decided_ago": decided, "purpose": str(h.command.get("purpose", ""))}


func _mark(log_: Array, index: int, flag: String) -> void:
	if index < 0 or index >= log_.size():
		return
	var row: Array = log_[index]
	if row.size() < 3:
		row.append({})
	(row[2] as Dictionary)[flag] = true


# Flags the latest cast of `slot` that started within `window` seconds.
func _mark_last(log_: Array, slot: int, now: float, window: float, flag: String) -> void:
	for i in range(log_.size() - 1, -1, -1):
		var row: Array = log_[i]
		if int(row[0]) != slot:
			continue
		if now - float(row[1]) <= window:
			_mark(log_, i, flag)
		return
