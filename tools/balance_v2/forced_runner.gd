extends SceneTree

# V2 balance (H-BALANCE): plays forced-hero cases and records per-hero
# telemetry. Offline tool; it never touches user settings or records.
#
#   --cases=<path>          JSON array from tools/balance_v2/forced_cases.gd
#                           (tools/balance_runner.gd format)
#   --out=<path>            JSONL, one row per case
#   [--shard=i/K]           play only the cases whose index % K == i
#   [--variants=<path> --variant=<name>]
#                           apply a named set of number changes to the loaded
#                           hero data before the first battle (what-if runs;
#                           nothing is written back). The seeds and cases stay
#                           the same, so rows pair with the base run by case id.
#
# Battles are built and stepped exactly as tools/balance_runner.gd does
# (BattleSim.new(config), tactician on both sides, sim.step() until the end),
# and each row carries the same signature formula, so a case played here and by
# balance_runner gives the same winner and signature. Everything recorded here
# is read from the simulator's per-tick events and public unit fields after the
# step; nothing feeds back into the battle.
#
# Variant file: {"name": [[hero, path, op, value], ...], ...}
#   path: stats.<key> | behavior.<key> | preferredRange | rule.<type>.<key>...
#         | ab<slot>.<field or nested path, e.g. effects.0.base>
#   op:   "=" set, "*" multiply, "+" add, "append" (append the JSON value to
#         the array at path)

const DT: float = 1.0 / 30.0
# Ability data keys (char_data camelCase) mapped to Defs.AbilityDef fields.
const AB_FIELDS: Dictionary = {"cooldown": "cooldown", "castTime": "cast_time", "recovery": "recovery", "range": "range",
	"radius": "radius", "width": "width", "angle": "angle", "speed": "speed", "projectileCount": "count",
	"maxDistance": "max_distance", "effects": "effects", "condition": "condition", "flags": "flags", "ai": "ai",
	"pierce": "pierce", "spread": "spread"}

var args: Dictionary = {}
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var at: int = arg.find("=")
			args[arg.substr(2, at - 2)] = arg.substr(at + 1)
	DB.ensure_loaded()
	var variant: String = str(args.get("variant", ""))
	if variant != "" and variant != "base":
		if not _apply_variant(str(args.get("variants", "")), variant):
			quit(2)
			return
	var data = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("cases", ""))))
	if not data is Array:
		push_error("cases must be a JSON array: " + str(args.get("cases", "")))
		quit(2)
		return
	var shard: PackedStringArray = str(args.get("shard", "0/1")).split("/")
	var si: int = int(shard[0])
	var sk: int = maxi(1, int(shard[1]))
	var out: FileAccess = FileAccess.open(str(args.get("out", "user://forced.jsonl")), FileAccess.WRITE)
	if out == null:
		push_error("cannot write --out")
		quit(2)
		return
	var t0: int = Time.get_ticks_msec()
	var done: int = 0
	for ci in (data as Array).size():
		if ci % sk != si:
			continue
		var row: Dictionary = _play(data[ci])
		row["variant"] = variant if variant != "" else "base"
		out.store_line(JSON.stringify(row))
		out.flush()
		done += 1
		print("FORCED ", row.case_id, " winner=", row.winner, " forced_team=", row.forced_team, " t=", row.duration, " wall=", row.wall)
	out.close()
	print("FORCED_DONE cases=", done, " failures=", failures, " wall_seconds=", (Time.get_ticks_msec() - t0) / 1000.0)
	quit(0 if failures == 0 else 1)


# ------------------------------------------------------------------ variants

func _apply_variant(path: String, name: String) -> bool:
	var all = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not all is Dictionary or not (all as Dictionary).has(name):
		push_error("variant %s not found in %s" % [name, path])
		return false
	for m in all[name]:
		var hero: String = str(m[0])
		var c: Defs.CharDef = DB.char_def(hero)
		if c == null:
			push_error("variant: unknown hero " + hero)
			return false
		if not _apply_mod(c, str(m[1]), str(m[2]), m[3]):
			push_error("variant: cannot apply %s" % str(m))
			return false
		print("MOD ", hero, " ", m[1], " ", m[2], " ", JSON.stringify(m[3]))
	return true


func _apply_mod(c: Defs.CharDef, path: String, op: String, value) -> bool:
	var keys: PackedStringArray = path.split(".")
	var head: String = keys[0]
	if head == "preferredRange":
		c.preferred_range = _combine(c.preferred_range, op, value)
		return true
	var holder = null
	var rest: Array = Array(keys.slice(1))
	var ab: Defs.AbilityDef = null
	# Hero data comes from CharData constants (read-only): what-ifs edit
	# writable deep copies instead.
	if head == "stats":
		holder = c.stats
	elif head == "behavior":
		if c.behavior.is_read_only():
			c.behavior = c.behavior.duplicate(true)
		holder = c.behavior
	elif head == "rule":
		var rkey: String = str(rest.pop_front())
		if not c.rules.has(rkey):
			return false
		if (c.rules[rkey] as Dictionary).is_read_only():
			c.rules[rkey] = (c.rules[rkey] as Dictionary).duplicate(true)
		holder = c.rules[rkey]
	elif head.begins_with("ab"):
		var slot: int = int(head.substr(2))
		for a in c.abilities:
			if (a as Defs.AbilityDef).slot == slot:
				ab = a
		if ab == null or rest.is_empty():
			return false
		var field: String = str(rest.pop_front())
		if not AB_FIELDS.has(field):
			return false
		var prop: String = AB_FIELDS[field]
		if rest.is_empty():
			if op == "append":
				ab.set(prop, (ab.get(prop) as Array).duplicate(true))
				(ab.get(prop) as Array).append(value)
			else:
				ab.set(prop, _combine(ab.get(prop), op, value))
			_refresh_ability(ab)
			return true
		holder = ab.get(prop)
		if (holder is Dictionary and (holder as Dictionary).is_read_only()) or (holder is Array and (holder as Array).is_read_only()):
			holder = holder.duplicate(true)
			ab.set(prop, holder)
	if holder == null:
		return false
	while rest.size() > 1:
		var k = rest.pop_front()
		holder = holder[int(k)] if holder is Array else holder.get(str(k))
		if holder == null:
			return false
	var last: String = str(rest[0])
	if holder is Array:
		var i: int = int(last)
		if op == "append":
			(holder[i] as Array).append(value)
		else:
			holder[i] = _combine(holder[i], op, value)
	else:
		if op == "append":
			(holder[last] as Array).append(value)
		else:
			holder[last] = _combine(holder.get(last), op, value)
	if ab != null:
		_refresh_ability(ab)
	return true


func _combine(old, op: String, value):
	match op:
		"*":
			return float(old) * float(value)
		"+":
			return float(old) + float(value)
	return value


# Fields Defs.ability_from derives from the effects at load time.
func _refresh_ability(a: Defs.AbilityDef) -> void:
	a.hostile = a.target in ["enemy", "position"] or (a.target == "self" and Defs._has_hostile_effect(a.effects))
	a.cc_types = []
	Defs._collect_cc(a.effects, a.cc_types)


# ------------------------------------------------------------------ battle

func _owner_hero(sim: BattleSim, idx: int) -> BUnit:
	var u: BUnit = sim.u_at(idx)
	var guard: int = 0
	while u != null and not u.is_hero and guard < 4:
		u = sim.u_at(u.owner_idx)
		guard += 1
	return u


func _cat(ev: Dictionary, sim: BattleSim) -> String:
	var src: BUnit = sim.u_at(int(ev.get("s", -1)))
	var pre: String = ""
	if src != null and not src.is_hero:
		pre = "ent:"
	if bool(ev.get("basic", false)):
		return pre + "basic"
	var ab = ev.get("ability")
	if ab is Defs.AbilityDef:
		var a: Defs.AbilityDef = ab
		return pre + ("S%d" % a.slot if not a.virtual else "V:" + a.id)
	return pre + str(ev.get("source_type", "?")).to_lower()


func _play(config: Dictionary) -> Dictionary:
	var w0: int = Time.get_ticks_usec()
	var sim: BattleSim = BattleSim.new(config)
	sim.controllers[0] = AIFactory.make(str(config.get("blue_ai", "tactician")), sim, 0)
	sim.controllers[1] = AIFactory.make(str(config.get("red_ai", "tactician")), sim, 1)
	sim.start()
	var H: Dictionary = {}
	for u in sim.heroes:
		H[u.idx] = {"id": u.def.id, "team": u.team, "alive_s": 0.0, "dmg": {}, "taken": 0.0, "heal": {}, "heal_self": {},
			"shield": {}, "casts": {}, "deaths": 0}
	var wm: Dictionary = {}
	var wm_unit: BUnit = null
	for u in sim.heroes:
		if u.def.id == "war_machine":
			wm_unit = u
			wm = {"s4": 0, "s2_charges": [], "fuel_max": 0.0, "fuel_sum": 0.0, "overdrive_s": 0.0, "tanks_lost": 0}
	# Forced hero behaviour: time in basic reach of an enemy hero, basics
	# declared, and a histogram of its orders (kind + purpose head, every 0.5 s).
	var fu: BUnit = null
	for u in sim.heroes:
		if u.def.id == str(config.get("forced", "")) and u.team == int(config.get("forced_team", -1)):
			fu = u
	var beh: Dictionary = {"contact_s": 0.0, "basics": 0, "orders": {}}
	var limit: int = int(sim.max_time * 30.0) + 10
	var invariant_error: String = ""
	while sim.state == BattleSim.RUNNING:
		sim.step()
		for u in sim.heroes:
			if u.alive:
				H[u.idx].alive_s += DT
		if fu != null and fu.alive:
			var reach: float = sim.stat(fu, &"attackRange") + sim.radius(fu) + 30.0
			for e in sim.heroes:
				if e.alive and e.team != fu.team and fu.pos.distance_to(e.pos) - sim.radius(e) <= reach:
					beh.contact_s = float(beh.contact_s) + DT
					break
			if sim.tick % 15 == 0:
				var ok: String = str(fu.command.get("kind", "")) + ":" + str(fu.command.get("purpose", fu.command.get("label", ""))).get_slice(" (", 0).get_slice(" →", 0)
				beh.orders[ok] = int(beh.orders.get(ok, 0)) + 1
		if wm_unit != null and wm_unit.alive:
			var fuel: float = float(wm_unit.resources.get("fuel", 0.0))
			wm.fuel_max = maxf(float(wm.fuel_max), fuel)
			wm.fuel_sum = float(wm.fuel_sum) + fuel * DT
			if sim.has_status(wm_unit, &"overdrive"):
				wm.overdrive_s = float(wm.overdrive_s) + DT
		for ev: Dictionary in sim.tick_events:
			var typ: String = str(ev.type)
			if typ == "CAST_COMPLETED":
				var cs: int = int(ev.get("s", -1))
				var ab = ev.get("ability")
				if H.has(cs) and ab is Defs.AbilityDef and not (ab as Defs.AbilityDef).virtual and (ab as Defs.AbilityDef).char_id == str(H[cs].id):
					var key: String = str((ab as Defs.AbilityDef).slot)
					H[cs].casts[key] = int(H[cs].casts.get(key, 0)) + 1
					if wm_unit != null and cs == wm_unit.idx and (ab as Defs.AbilityDef).slot == 4:
						wm.s4 = int(wm.s4) + 1
			elif typ == "CAST_STARTED":
				if wm_unit != null and int(ev.get("s", -1)) == wm_unit.idx and int(ev.get("slot", 0)) == 2:
					(wm.s2_charges as Array).append(int(ev.get("charge", 0)))
			elif typ == "HEALTH_DAMAGED" or typ == "SHIELD_ABSORBED":
				var g: BUnit = sim.u_at(int(ev.get("g", -1)))
				var o: BUnit = _owner_hero(sim, int(ev.get("s", -1)))
				if g != null and g.is_hero and H.has(g.idx):
					H[g.idx].taken = float(H[g.idx].taken) + float(ev.get("amount", 0.0))
				if o != null and H.has(o.idx) and g != null and g.is_hero and sim.eteam(g) != sim.eteam(o):
					var c: String = _cat(ev, sim)
					H[o.idx].dmg[c] = float(H[o.idx].dmg.get(c, 0.0)) + float(ev.get("amount", 0.0)) + float(ev.get("absorbed", 0.0))
			elif typ == "HEAL_APPLIED":
				var g2: BUnit = sim.u_at(int(ev.get("g", -1)))
				var o2: BUnit = _owner_hero(sim, int(ev.get("s", -1)))
				if o2 != null and H.has(o2.idx) and g2 != null and g2.is_hero:
					var c2: String = _cat(ev, sim)
					var bucket: String = "heal_self" if g2 == o2 else "heal"
					H[o2.idx][bucket][c2] = float(H[o2.idx][bucket].get(c2, 0.0)) + float(ev.get("amount", 0.0))
			elif typ == "SHIELD_APPLIED":
				var g3: BUnit = sim.u_at(int(ev.get("g", -1)))
				var o3: BUnit = _owner_hero(sim, int(ev.get("s", -1)))
				if o3 != null and H.has(o3.idx) and g3 != null and g3.is_hero:
					var c3: String = _cat(ev, sim)
					H[o3.idx].shield[c3] = float(H[o3.idx].shield.get(c3, 0.0)) + float(ev.get("amount", 0.0))
			elif typ == "DEATH" or typ == "EXECUTED":
				if H.has(int(ev.get("g", -1))):
					H[int(ev.g)].deaths = int(H[int(ev.g)].deaths) + 1
			elif typ == "ATTACK_DECLARED":
				if fu != null and int(ev.get("s", -1)) == fu.idx:
					beh.basics = int(beh.basics) + 1
			elif typ == "TANK_DESTROYED":
				if wm_unit != null and int(ev.get("g", -1)) == wm_unit.idx:
					wm.tanks_lost = int(wm.tanks_lost) + 1
		if sim.tick > limit:
			invariant_error = "simulation failed to terminate"
			break
	var result: Dictionary = sim.result()
	var final_state: Array = []
	for u in sim.heroes:
		final_state.append([u.id, u.hp, u.pos.x, u.pos.y, u.st_damage, u.st_casts])
	var heroes: Array = []
	for ur in result.units:
		var h: Dictionary = H[int(ur.idx)]
		h["damage_total"] = ur.damage
		h["kills"] = ur.kills
		h["alive_end"] = ur.alive
		heroes.append(h)
	var row: Dictionary = {"case_id": config.get("id", ""), "set": config.get("set", ""), "forced": config.get("forced", ""),
		"forced_team": int(config.get("forced_team", -1)), "arena": config.get("arena_id", ""), "seed": config.get("seed", 0),
		"winner": result.winner, "reason": str(result.reason), "duration": snappedf(float(result.duration), 0.01), "heroes": heroes,
		"signature": JSON.stringify([result.winner, result.duration, final_state]).sha256_text(),
		"invariant_error": invariant_error, "wall": snappedf((Time.get_ticks_usec() - w0) / 1e6, 0.1)}
	if fu != null:
		row["behavior"] = beh
	if wm_unit != null:
		row["wm"] = wm
	if invariant_error != "":
		failures += 1
		push_error(str(row.case_id) + ": " + invariant_error)
	sim.dispose()
	return row
