extends SceneTree

# V2.0 render layer for the four new heroes (H-VIS, DESIGN_V2 §2.8), headless:
# - dispatch tables cover every new hero, ability, passive, vfx pattern, entity
#   kind, status and log event (event fx families, motifs, signatures, passive
#   pulses, summon keys, status icons with font glyphs, battle view cases);
# - every new draw path runs through the real view classes (a live battle with
#   all four heroes, the V2 showcase states, synthesized V2 events, both
#   perspectives and the low quality setting) while layers actually draw;
# - the view never changes the battle (same signature with and without it);
# - the 22 V1.5.3 heroes keep their view tables (signature order, families).
# BattleView / KitVisuals / DevGallery use the Settings and Sfx autoloads, which a
# --script run registers only after start-up, so they are loaded at run time.

const NEW_IDS: Array = ["hades", "war_machine", "torquemada", "achilles"]
const NEW_KINDS: Array = ["cerberus", "shade", "fuel_tank", "chariot"]
const NEW_STATUSES: Array = ["roar", "overdrive", "frontGuard"]
const NEW_EVENTS: Array = ["CLEANSED", "FRONT_BLOCKED", "TANK_DESTROYED", "OVERDRIVE", "HEAL_BLOCKED", "CHARIOT_KNOCK"]
const NEW_PATTERNS: Array = ["shadeSpawn", "underworldCleave", "soulHarvest", "boosterDash", "missileBarrage", "arcShield", "genocideStrip",
	"autoDaFe", "edictBind", "alhambraEdict", "peliasSpear", "hephaestusShield", "warRoar", "chariotCharge"]
const DEMO: Dictionary = {"blue": ["hades", "war_machine", "torquemada"], "red": ["achilles", "swordsman", "mage"], "arena_id": "moon_garden",
	"seed": 20260923, "blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}
var draws: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _run() -> void:
	DB.ensure_loaded()
	DB.load_fonts()
	var bv: GDScript = load("res://scripts/view/battle_view.gd")
	_tables(bv)
	_status_icons()
	_old_tables()
	await _live_battle(bv)
	await _war_machine_live(bv)
	await _showcase(bv)
	_view_is_passive()
	# Every visual assertion has run with sound enabled. Stop autoload voices
	# before immediate headless exit so AudioServer can release playback refs.
	var sfx: Node = root.get_node("Sfx")
	for player: AudioStreamPlayer in sfx.get("_players"):
		player.stop()
		player.stream = null
	sfx.get("_cache").clear()
	await _frames(3)
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("RENDER_V2 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	quit(0 if failed.is_empty() else 1)


func _func_src(src: String, header: String) -> String:
	var a: int = src.find(header)
	if a < 0:
		return ""
	var b: int = src.find("\nfunc ", a + 1)
	var c: int = src.find("\nstatic func ", a + 1)
	if b < 0 or (c >= 0 and c < b):
		b = c
	return src.substr(a, (b - a) if b > a else -1)


func _union(lists: Array) -> Array:
	var out: Array = []
	for l in lists:
		out.append_array(l)
	return out


# ------------------------------------------------------------------ tables

func _tables(bv: GDScript) -> void:
	var consts: Dictionary = bv.get_script_constant_map()
	var passive_motif: Dictionary = consts.get("PASSIVE_MOTIF", {})
	var motifs_src: String = FileAccess.get_file_as_string("res://scripts/view/motifs.gd")
	var draw_src: String = _func_src(motifs_src, "static func draw(")
	var sig_src: String = _func_src(motifs_src, "static func signature(")
	var fx_src: String = FileAccess.get_file_as_string("res://scripts/view/fx_system.gd")
	var pulse_src: String = _func_src(fx_src, "func _passive_pulse(")
	var view_src: String = FileAccess.get_file_as_string("res://scripts/view/battle_view.gd")
	var entity_src: String = _func_src(view_src, "func _draw_entity(")
	var event_src: String = _func_src(view_src, "func _handle_event(")
	var zone_src: String = _func_src(view_src, "func _draw_zone(")
	var patterns: Array = _union([VfxStyle.MELEE, VfxStyle.NOVA, VfxStyle.BEAM, VfxStyle.HEAVY, VfxStyle.SPAWN, VfxStyle.DASH, VfxStyle.SHOT])
	var data_patterns: Array = []
	for id: String in NEW_IDS:
		var d: Defs.CharDef = DB.char_def(id)
		_check(d != null, "%s is in the roster" % id)
		if d == null:
			continue
		var fam: Array = EventFx.FAMILIES.get(id, [])
		_check(fam.size() == 6, "%s has an event fx family" % id)
		if fam.size() == 6:
			_check((fam[3] as Array).size() == d.passives.size(), "%s family has one passive motif per passive (%d)" % [id, d.passives.size()])
			_check((fam[4] as Array).size() == d.abilities.size(), "%s family has one skill motif per active (%d)" % [id, d.abilities.size()])
		_check(EventFx.SIG_ORDER.has(id), "%s is in the signature order" % id)
		_check(sig_src.contains("\"%s\":" % id), "%s has its own cast signature" % id)
		var basic: String = str(Motifs.BASIC.get(id, ""))
		_check(basic != "" and draw_src.contains("\"%s\"" % basic), "%s holds a drawn weapon motif (%s)" % [id, basic])
		_check(not EventFx.spec(id + ":basic").is_empty() and not EventFx.spec(id + ":death").is_empty(), "%s basic and death fx specs" % id)
		for i in d.passives.size():
			var pk: String = id + ":passive" + ("" if i == 0 else ":%d" % (i + 1))
			_check(not EventFx.spec(pk).is_empty(), "fx spec %s" % pk)
		var pm: String = str(passive_motif.get(id, ""))
		_check(pm != "" and pulse_src.contains("\"%s\"" % pm), "%s passive pulse motif %s has a drawing" % [id, pm])
		for a: Defs.AbilityDef in d.abilities:
			var key: String = EventFx.ability_key(a)
			var sp: Dictionary = EventFx.spec(key)
			_check(not sp.is_empty() and str(sp.get("motif", "")) != "", "fx spec %s" % key)
			var pat: String = VfxStyle.pattern_for(a)
			data_patterns.append(pat)
			_check(pat in patterns, "pattern %s of %s is classified in VfxStyle" % [pat, key])
			if a.delivery == "projectile" and not sp.is_empty():
				_check(draw_src.contains("\"%s\"" % str(sp.motif)), "projectile motif %s of %s is drawn" % [str(sp.motif), key])
	for pat: String in NEW_PATTERNS:
		_check(pat in data_patterns, "data uses the vfx pattern %s" % pat)
	for kind: String in NEW_KINDS:
		_check(entity_src.contains("\"%s\":" % kind), "battle view draws the %s entity" % kind)
		_check(not EventFx.spec(str(EventFx.SUMMON_KEY.get(kind, ""))).is_empty(), "summon key for %s" % kind)
		_check(Defs.entity_def(kind, DB.char_def("hades"), 10.0, 10.0, 0.0).name != kind, "%s has an entity name" % kind)
	for ev: String in NEW_EVENTS:
		_check(event_src.contains("\"%s\":" % ev), "battle view handles %s" % ev)
		_check(BattleSim.LOG_TYPES.has(ev), "%s is a logged event" % ev)
	_check(zone_src.contains("z.shape == \"rect\"") and zone_src.contains("\"autoDaFe\""), "battle view draws rect and auto-da-fe zones")
	_check(view_src.contains("e2.kind == \"chariot\""), "the chariot is drawn after (above) the heroes")
	var app_src: String = FileAccess.get_file_as_string("res://scripts/ui/app.gd")
	_check(app_src.contains("ca.begins_with(\"--demo-comp=\") and ca.contains(\"|\")"), "--demo-comp=<blue>|<red> feeds --demo-battle")
	metrics["patterns"] = data_patterns


func _has_glyph(f: Font, ch: String) -> bool:
	if f == null:
		return false
	var code: int = ch.unicode_at(0)
	if f.has_char(code):
		return true
	if f is FontFile:
		for fb: Font in (f as FontFile).fallbacks:
			if fb.has_char(code):
				return true
	return false


func _status_icons() -> void:
	var owners: Dictionary = {}
	for st: String in VfxStyle.STATUS_ICONS:
		var g: String = str(VfxStyle.STATUS_ICONS[st][0])
		owners[g] = int(owners.get(g, 0)) + 1
	for st: String in NEW_STATUSES:
		_check(VfxStyle.STATUS_ICONS.has(st), "status icon for %s" % st)
		if not VfxStyle.STATUS_ICONS.has(st):
			continue
		var g2: String = str(VfxStyle.STATUS_ICONS[st][0])
		_check(int(owners.get(g2, 0)) == 1, "%s glyph %s is unique" % [st, g2])
		_check(_has_glyph(DB.font_glyph, g2), "%s glyph %s is in the bundled glyph font" % [st, g2])
		_check(DB.STATUS_LABELS.has(st), "%s has a Korean status label" % st)
	var dup: Array = []
	for g3: String in owners:
		if int(owners[g3]) > 1:
			dup.append(g3)
	_check(dup.is_empty(), "no two statuses share a glyph %s" % str(dup))


func _old_tables() -> void:
	var order: Array = EventFx.SIG_ORDER
	var head: Array = ["swordsman", "archer", "mage", "sniper", "werewolf", "giant", "aphrodite", "blood_mage", "fisherman",
		"baseball", "pirate", "joker", "metatron", "plague_doctor", "hive_mind", "nitro", "dimensionalist", "hermes",
		"world_tree", "torturer", "engineer", "politician"]
	_check(order.slice(0, 22) == head, "the 22 V1.5.3 heroes keep their signature order (aurora counts)")
	_check(order.size() == 26 and order.slice(22) == NEW_IDS, "the new heroes are appended to the signature order")
	for id: String in head:
		_check(EventFx.FAMILIES.has(id) or EventFx.NEXUS.has(id), "%s keeps its event fx family" % id)
	for id2: String in NEW_IDS:
		_check(not EventFx.NEXUS.has(id2), "%s uses the full fx style (not the nexus clarity style)" % id2)


# ------------------------------------------------------------------ draw paths

func _view(bv: GDScript, runner: BattleRunner) -> Variant:
	var view = bv.new()
	root.add_child(view)
	view.setup(runner.sim, runner)
	view.fit(Rect2(0, 0, 1408, 792))
	for layer: String in ["unit_layer", "zone_layer", "hud_layer", "proj_solid_layer"]:
		var n: Node2D = view.get(layer)
		n.draw.connect(func() -> void: draws[layer] = int(draws.get(layer, 0)) + 1)
	(view.get("fx") as Node2D).draw.connect(func() -> void: draws["fx"] = int(draws.get("fx", 0)) + 1)
	(view.get("ev_fx") as Node2D).draw.connect(func() -> void: draws["ev_fx"] = int(draws.get("ev_fx", 0)) + 1)
	return view


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# The demo battle (the --demo-battle --demo-comp shot) with every frame's events fed
# to the view, drawing every other tick. Records which V2 kinds, events and states
# the drawn frames contained.
func _live_battle(bv: GDScript) -> void:
	var runner: = BattleRunner.new()
	root.add_child(runner)
	runner.start(DEMO)
	runner.paused = true
	var sim: BattleSim = runner.sim
	var view = _view(bv, runner)
	var kinds: Dictionary = {}
	var evs_seen: Dictionary = {}
	var states: Dictionary = {}
	draws.clear()
	var ticks: int = 0
	while sim.state == BattleSim.RUNNING and sim.time < 62.0:
		sim.step()
		ticks += 1
		var evs: Array = sim.drain_frame_events()
		for ev in evs:
			var ty: String = str(ev.get("type", ""))
			if ty in NEW_EVENTS:
				evs_seen[ty] = true
			# Missiles fired point-blank can land within the tick they spawn in.
			if ty == "FX" and str(ev.get("kind", "")) == "proj_hit" and ev.get("ability") is Defs.AbilityDef and VfxStyle.pattern_for(ev.ability) in VfxStyle.SHOT:
				states[VfxStyle.pattern_for(ev.ability)] = true
		for p in sim.proj.list:
			if p.ability and not p.basic and VfxStyle.pattern_for(p.ability) in VfxStyle.SHOT:
				states[VfxStyle.pattern_for(p.ability)] = true
		view.on_step(evs)
		# Fx age with the battle clock (the runner is paused; the test steps it).
		(view.get("fx") as FxSystem).step(BattleSim.DT)
		(view.get("ev_fx") as EventFx).step(BattleSim.DT)
		if ticks % 2 == 0:
			for e in sim.entities:
				if e.alive and e.kind in NEW_KINDS:
					kinds[e.kind] = true
			for u in sim.heroes:
				if not u.alive:
					continue
				if sim.has_status(u, &"overdrive"):
					states["overdrive"] = true
				if u.action and u.action.ability and u.action.windup and u.action.ability.flags.has("originCharge"):
					states["charge"] = true
				if u.def.id == "hades" and sim.kits.concealed(u):
					states["concealed"] = true
			await process_frame
	for kind: String in NEW_KINDS:
		_check(kinds.has(kind), "the demo battle draws a live %s" % kind)
	# The fuel tank may survive this AI match, and a tactician may never choose
	# missiles. Their five required live render assertions are exercised by
	# _war_machine_live through real casts and damage, independently of this
	# incidental opening. Keep this match and its complete observation metrics.
	for ev2: String in ["CHARIOT_KNOCK"]:
		_check(evs_seen.has(ev2), "the demo battle shows %s" % ev2)
	for st: String in ["concealed", "peliasSpear"]:
		_check(states.has(st), "the demo battle draws the %s state" % st)
	_check(float(draws.get("unit_layer", 0)) >= float(ticks) * 0.5 - 2.0 and int(draws.get("zone_layer", 0)) > 0 and int(draws.get("ev_fx", 0)) > 0 and int(draws.get("proj_solid_layer", 0)) > 0,
		"view layers drew headless %s" % str(draws))
	metrics["live"] = {"ticks": ticks, "kinds": kinds.keys(), "events": evs_seen.keys(), "states": states.keys(), "draws": draws.duplicate()}
	view.queue_free()
	runner.queue_free()
	await _frames(2)


func _fixture_place(unit: BUnit, pos: Vector2) -> void:
	unit.pos = pos
	unit.prev_pos = pos
	unit.vel = Vector2.ZERO


# A controlled input scenario, not synthetic FX: the normal start_ability,
# projectile and basic-attack paths produce every event and state observed here.
# Initial fuel is a scenario input; no status, projectile or event is injected.
func _war_machine_live(bv: GDScript) -> void:
	var runner: = BattleRunner.new()
	root.add_child(runner)
	runner.start({"blue": ["war_machine"], "red": ["giant"], "arena_id": "classic", "seed": 20261003})
	runner.paused = true
	var sim: BattleSim = runner.sim
	for team: int in sim.team_count:
		sim.detach_controller(team)
	var wm: BUnit = sim.heroes[0]
	var foe: BUnit = sim.heroes[1]
	_fixture_place(wm, Vector2(400, 400))
	_fixture_place(foe, Vector2(700, 400))
	wm.facing = Vector2.RIGHT
	foe.facing = Vector2.LEFT
	wm.resources["fuel"] = 5.0
	var view = _view(bv, runner)
	var evidence: Dictionary = {"events": {}, "states": {}, "projectiles": 0, "missile_hits": 0, "ticks": 0}
	draws.clear()
	await _fixture_steps(sim, view, wm, evidence, 3)
	var tanks: Array[BUnit] = sim.kits.owned_entities(wm, "fuel_tank")
	_check(tanks.size() == 1, "live war-machine fixture creates its fuel tank through the kit")
	if tanks.size() != 1:
		view.queue_free()
		runner.queue_free()
		await _frames(2)
		return
	var tank: BUnit = tanks[0]
	var started: bool = sim.start_ability(wm, 1, foe, foe.pos, {"extra": {"charge": 5}})
	_check(started, "live war-machine fixture starts a legal five-missile cast")
	await _fixture_steps(sim, view, wm, evidence, 120)
	_check(int(evidence.projectiles) == 5 and int(evidence.missile_hits) == 5,
		"live war-machine cast creates and lands five real missiles (%d / %d)" % [int(evidence.projectiles), int(evidence.missile_hits)])
	# Attack the attached tank from behind using legal basic attacks. Bounds
	# prevent a broken damage/destruction path from hanging the test.
	_fixture_place(foe, Vector2(330, 400))
	await _fixture_steps(sim, view, wm, evidence, 2)
	var attacks: int = 0
	while tank.alive and attacks < 20 and sim.state == BattleSim.RUNNING:
		var attack_started: bool = sim.start_basic(foe, tank)
		_check(attack_started, "live tank destruction accepts basic attack %d" % (attacks + 1))
		if not attack_started:
			break
		attacks += 1
		var wait_ticks: int = int(ceil(maxf(0.5, foe.attack_ready_at - sim.time) / BattleSim.DT)) + 1
		await _fixture_steps(sim, view, wm, evidence, wait_ticks)
	_check(not tank.alive and wm.alive and foe.alive, "real basic attacks destroy only the fuel tank")
	for event: String in ["TANK_DESTROYED", "OVERDRIVE"]:
		_check(evidence.events.has(event), "the controlled live battle shows %s" % event)
	for state_name: String in ["overdrive", "charge", "missileBarrage"]:
		_check(evidence.states.has(state_name), "the controlled live battle draws the %s state" % state_name)
	_check(int(draws.get("unit_layer", 0)) >= int(evidence.ticks) - 2 and int(draws.get("proj_solid_layer", 0)) > 0
		and int(draws.get("ev_fx", 0)) > 0, "controlled live battle draws all unit, projectile and event layers")
	evidence["attacks"] = attacks
	evidence["draws"] = draws.duplicate()
	metrics["war_machine_live"] = evidence
	view.queue_free()
	runner.queue_free()
	await _frames(2)


func _fixture_steps(sim: BattleSim, view: Variant, wm: BUnit, evidence: Dictionary, count: int) -> void:
	for _i in count:
		if sim.state != BattleSim.RUNNING:
			break
		sim.step()
		evidence.ticks = int(evidence.ticks) + 1
		var events: Array = sim.drain_frame_events()
		for event: Dictionary in events:
			var ty: String = str(event.get("type", ""))
			if ty in NEW_EVENTS:
				evidence.events[ty] = true
			var ability: Defs.AbilityDef = event.get("ability") as Defs.AbilityDef
			if ability != null and ability.id == "war_machine_2":
				if ty == "PROJECTILE_CREATED":
					evidence.projectiles = int(evidence.projectiles) + 1
				if ty == "HEALTH_DAMAGED":
					evidence.missile_hits = int(evidence.missile_hits) + 1
		for projectile in sim.proj.list:
			if projectile.ability and not projectile.basic and VfxStyle.pattern_for(projectile.ability) == "missileBarrage":
				evidence.states["missileBarrage"] = true
		if wm.action and wm.action.ability and wm.action.windup and wm.action.ability.flags.has("originCharge"):
			evidence.states["charge"] = true
		if sim.has_status(wm, &"overdrive"):
			evidence.states["overdrive"] = true
		view.on_step(events)
		(view.get("fx") as FxSystem).step(BattleSim.DT)
		(view.get("ev_fx") as EventFx).step(BattleSim.DT)
		await process_frame


func _hero(sim: BattleSim, id: String, team: int) -> BUnit:
	for u in sim.heroes:
		if u.def.id == id and u.team == team:
			return u
	return null


# The dev gallery's V2 showcase (variant 6: every persistent V2 visual at once),
# drawn in both perspectives and at quality 0, then every new event synthesized.
func _showcase(bv: GDScript) -> void:
	var dg = load("res://scripts/ui/dev_gallery.gd")
	var runner: = BattleRunner.new()
	root.add_child(runner)
	runner.start(dg.config(6))
	runner.paused = true
	var sim: BattleSim = runner.sim
	dg.setup(sim, 6)
	var view = _view(bv, runner)
	var hades: BUnit = _hero(sim, "hades", 0)
	var wm: BUnit = _hero(sim, "war_machine", 0)
	var torq: BUnit = _hero(sim, "torquemada", 0)
	var ach: BUnit = _hero(sim, "achilles", 1)
	var wm2: BUnit = _hero(sim, "war_machine", 1)
	var mage: BUnit = _hero(sim, "mage", 1)
	var kinds: Dictionary = {}
	for e in sim.entities:
		if e.alive:
			kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
	_check(int(kinds.get("cerberus", 0)) == 1 and int(kinds.get("shade", 0)) == 5 and int(kinds.get("fuel_tank", 0)) == 1 and int(kinds.get("chariot", 0)) == 1,
		"showcase has cerberus, 5 shades, the fuel tank and the chariot %s" % str(kinds))
	_check(sim.get_buff(hades, &"soulHarvest") != null and sim.kits.concealed(hades), "showcase: harvest aura on a concealed hades")
	_check(sim.get_buff(wm, &"arcConvert") != null and wm.action != null and sim.kits.charge_count(wm, wm.action.ability, wm.action.extra) == 5, "showcase: arc shell and a 5-missile charge")
	_check(sim.has_status(wm2, &"overdrive") and sim.has_status(ach, &"frontGuard") and sim.has_status(hades, &"roar"), "showcase: overdrive, front guard and roar")
	var root_st: ST.Status = sim.get_status(mage, &"root")
	var hb: ST.Status = sim.get_status(mage, &"healReduction")
	_check(root_st != null and root_st.source_idx == torq.idx and hb != null and hb.magnitude >= 0.999, "showcase: edict root and heal block on the mage")
	var zshapes: Array = []
	for z in sim.zones.list:
		zshapes.append(z.shape + ":" + z.pattern)
	_check(zshapes.has("rect:genocideStrip") and zshapes.has("circle:autoDaFe"), "showcase: genocide strip and purification fire %s" % str(zshapes))
	draws.clear()
	await _frames(3)
	var base: Dictionary = draws.duplicate()
	_check(int(base.get("unit_layer", 0)) > 0 and int(base.get("zone_layer", 0)) > 0 and int(base.get("hud_layer", 0)) > 0, "showcase layers drew %s" % str(base))
	# Private kit info (fuel gauge and pips, the charge total, the concealed shimmer)
	# switches off in the enemy perspective; drawing must not fail either way.
	var kv = load("res://scripts/view/kit_visuals.gd")
	view.set_perspective(1)
	_check(not kv.private_ok(view, wm) and kv.private_ok(view, ach), "red perspective hides blue private kit visuals")
	await _frames(2)
	view.set_perspective(0)
	_check(kv.private_ok(view, wm), "blue perspective shows its own kit visuals")
	await _frames(2)
	view.set_perspective(-1)
	var lab: Array = kv.label_for(view, wm2)
	_check(not lab.is_empty() and str(lab[0]).begins_with("과열 폭주"), "overdrive label %s" % str(lab))
	# Synthesized V2 events (the AI does not use every skill yet).
	var fx: FxSystem = view.get("fx")
	var ev_fx: EventFx = view.get("ev_fx")
	var tank: BUnit = null
	var chariot: BUnit = null
	for e2 in sim.entities:
		if e2.kind == "fuel_tank":
			tank = e2
		elif e2.kind == "chariot":
			chariot = e2
	var syn: Array = [
		{"type": "CLEANSED", "s": torq.idx, "g": hades.idx, "removed": ["root", "roar"], "pos": hades.pos},
		{"type": "FRONT_BLOCKED", "s": wm.idx, "g": ach.idx, "kind": "damage", "pos": ach.pos},
		{"type": "FRONT_BLOCKED", "s": wm.idx, "g": ach.idx, "kind": "projectile", "pos": ach.pos},
		{"type": "TANK_DESTROYED", "s": ach.idx, "g": wm.idx, "tank": tank.idx if tank else -1, "fuel_lost": 7.0, "pos": tank.pos if tank else wm.pos},
		{"type": "OVERDRIVE", "s": wm.idx, "g": wm.idx, "duration": 10.0, "pos": wm.pos},
		{"type": "HEAL_BLOCKED", "s": hades.idx, "g": mage.idx, "duration": 5.0, "pos": mage.pos},
		{"type": "CHARIOT_KNOCK", "s": ach.idx, "g": torq.idx, "count": 1, "entity": chariot.idx if chariot else -1, "pos": torq.pos}]
	for ev in syn:
		var n0: int = fx.items.size() + fx.texts.size() + fx.p_count + ev_fx.items.size()
		view._handle_event(ev)
		var n1: int = fx.items.size() + fx.texts.size() + fx.p_count + ev_fx.items.size()
		_check(n1 > n0, "%s (%s) adds visible fx (%d -> %d)" % [ev.type, str(ev.get("kind", "")), n0, n1])
	# Cast releases of every new ability through the FX path (cast flourish, cones, areas).
	for h: BUnit in [hades, wm, torq, ach]:
		for a: Defs.AbilityDef in h.def.abilities:
			var to: Vector2 = h.pos + Vector2(120, 30)
			view._handle_fx({"type": "FX", "kind": "cast", "pos": h.pos, "to": to, "ability": a, "source": h.idx})
			if a.delivery == "cone":
				view._handle_fx({"type": "FX", "kind": "cone", "pos": h.pos, "dir": Vector2.RIGHT, "range": a.range, "angle": a.angle, "ability": a, "source": h.idx})
			elif a.delivery == "area":
				view._handle_fx({"type": "FX", "kind": "area", "pos": to, "radius": a.radius, "ability": a, "source": h.idx})
	var kinds_fx: Dictionary = {}
	for it in ev_fx.items:
		kinds_fx[str(it.k)] = true
	for k: String in ["wave", "strip", "cleanse", "block", "cone", "tether", "soft", "flash"]:
		_check(kinds_fx.has(k), "event fx item %s is produced" % k)
	draws.clear()
	view.set("quality", 2)
	await _frames(4)
	_check(int(draws.get("fx", 0)) > 0 and int(draws.get("ev_fx", 0)) > 0, "fx layers drew the V2 events %s" % str(draws))
	# Low quality path.
	view.set("quality", 0)
	fx.quality = 0
	ev_fx.quality = 0
	draws.clear()
	await _frames(2)
	_check(int(draws.get("unit_layer", 0)) > 0, "quality 0 draws the V2 visuals")
	metrics["showcase"] = {"kinds": kinds, "zones": zshapes, "fx_items": kinds_fx.keys()}
	view.queue_free()
	runner.queue_free()
	await _frames(2)


# The view only reads the battle: the demo battle with the view attached (above)
# and without one end in the same state.
func _sig(sim: BattleSim) -> String:
	var parts: Array = []
	for u in sim.units:
		parts.append("%d:%.3f,%.3f:%.3f:%s" % [u.idx, u.pos.x, u.pos.y, u.hp, str(u.alive)])
	return "%d|%.3f|%s" % [sim.units.size(), sim.time, ",".join(parts)]


func _view_is_passive() -> void:
	var sigs: Array = []
	for with_view in [false, true]:
		var runner: = BattleRunner.new()
		root.add_child(runner)
		runner.start(DEMO)
		runner.paused = true
		var sim: BattleSim = runner.sim
		var view = null
		var kv = load("res://scripts/view/kit_visuals.gd")
		if with_view:
			view = (load("res://scripts/view/battle_view.gd") as GDScript).new()
			root.add_child(view)
			view.setup(sim, runner)
		while sim.state == BattleSim.RUNNING and sim.time < 50.0:
			sim.step()
			var evs: Array = sim.drain_frame_events()
			if view:
				view.on_step(evs)
				# Exercise the per-frame readers the draws use on the live state.
				for u in sim.heroes:
					if u.alive:
						kv.label_for(view, u)
						if u.def.id == "hades":
							sim.kits.concealed(u)
						if u.action and u.action.ability and u.action.ability.flags.has("originCharge"):
							sim.kits.charge_count(u, u.action.ability, u.action.extra)
		sigs.append(_sig(sim))
		if view:
			view.free()
		runner.free()
	_check(sigs[0] == sigs[1], "the view never changes the battle (same state after 50 s with and without it)")
