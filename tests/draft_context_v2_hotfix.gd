extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var evidence: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error(label)


func _run() -> void:
	DB.ensure_loaded()
	skill_semantics()
	map_semantics()
	context_semantics()
	prior_semantics()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed, "evidence": evidence}
	var file := FileAccess.open("res://reports/draft_context_v2_hotfix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("DRAFT_CONTEXT_V2_HOTFIX ", JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)


func skill_semantics() -> void:
	var source: Defs.CharDef = DB.char_def("torquemada")
	var fixture := Defs.CharDef.new()
	fixture.id = "fixture"
	fixture.stats = source.stats.duplicate(true)
	fixture.abilities = [source.abilities[0]]
	var f: Dictionary = DraftDirector.kit_features(fixture)
	var expected: float = (80.0 + source.stat("abilityPower")) / source.abilities[0].cooldown / 22.0
	check(is_equal_approx(float(f.ally_healing), expected), "TQ S1 one recipient receives one heal, not 6.6 heals")
	var once: Array = []
	var long_once: Array = []
	var periodic: Array = []
	DraftDirector._weighted([{"type": "zone", "oncePerUnit": true, "duration": 3.0, "interval": 0.2, "effects": [{"type": "heal"}]}], 1.0, once, "ally")
	DraftDirector._weighted([{"type": "zone", "oncePerUnit": true, "duration": 12.0, "interval": 0.2, "effects": [{"type": "heal"}]}], 1.0, long_once, "ally")
	DraftDirector._weighted([{"type": "zone", "duration": 12.0, "interval": 0.2, "effects": [{"type": "heal"}]}], 1.0, periodic, "ally")
	check(once[1].w == long_once[1].w and periodic[1].w > once[1].w, "extending a one-shot zone never invents repeated healing")
	var tq: Dictionary = DraftDirector.kit_features(source)
	check(tq.ally_protection > 0.0 and tq.cleanse > 0.0 and tq.displacement > 0.0, "mixed ally/enemy S3 retains shielding, cleanse and displacement")
	var no_cleanse: Dictionary = tq.duplicate(true)
	no_cleanse.cleanse = 0.0
	var cc: Dictionary = DraftDirector.kit_features(DB.char_def("mage"))
	var no_cc: Dictionary = cc.duplicate(true)
	no_cc.control = 0.0
	check(DraftDirector.directed_counter(tq, cc) > DraftDirector.directed_counter(no_cleanse, cc), "cleanse is relevant against a CC composition")
	check(is_equal_approx(DraftDirector.directed_counter(tq, no_cc), DraftDirector.directed_counter(no_cleanse, no_cc)), "cleanse gives no invented bonus against zero CC")
	var hades: Dictionary = DraftDirector.kit_features(DB.char_def("hades"))
	check(hades.anti_heal == 1.0 and hades.anti_heal_strength > 0.0 and hades.anti_heal_strength < 0.15, "Hades heal-block capability is preserved but its strength respects the execute threshold")
	check(hades.magic > 0.0 and hades.magic < 1.0, "Hades harvest and shades are magic while basic attacks and Cerberus are physical")
	var shade_fixture := Defs.CharDef.new()
	shade_fixture.id = "hades"
	shade_fixture.stats = DB.char_def("hades").stats.duplicate(true)
	shade_fixture.abilities = [DB.char_def("hades").abilities[0].duplicate_def()]
	var shade_magic: Dictionary = HadesTactics.draft_features(shade_fixture)
	check(shade_magic.spell > 0.0 and is_equal_approx(shade_magic.magic, shade_magic.spell), "shade-only fixture attributes all summon damage to its magic school")
	var shade_features: Dictionary = DraftDirector.kit_features(shade_fixture)
	check(is_equal_approx(shade_features.magic * shade_features.raw_damage, shade_magic.magic), "director preserves the helper's shade magic contribution")
	HadesTactics.shade_effect(shade_fixture.abilities[0]).attack.school = "physical"
	var shade_physical: Dictionary = HadesTactics.draft_features(shade_fixture)
	check(is_equal_approx(shade_physical.spell, shade_magic.spell) and shade_physical.magic == 0.0, "changing only shade school changes classification without changing total damage")
	var achilles: Dictionary = DraftDirector.kit_features(DB.char_def("achilles"))
	check(achilles.basic_guard > 0.0 and achilles.basic_guard < 0.15, "Achilles armor multiplier is not flat thirty percent damage reduction")
	check(tq.tenacity == source.stat("tenacity") and tq.charm_tenacity == 0.5, "Torquemada general and charm resistance come from current data")
	fixture.rules = {"orbit_aura": DB.char_def("metatron").rule("orbit_aura").duplicate(true)}
	fixture.abilities = []
	var orbit: Dictionary = DraftDirector.kit_features(fixture)
	check(orbit.healing == 0.0 and orbit.ally_healing > 0.0, "Metatron wings heal other allies, never the owner")
	var old_ally: float = orbit.ally_healing
	fixture.rules.orbit_aura.allyHeal.base *= 2.0
	check(DraftDirector.kit_features(fixture).ally_healing > old_ally, "passive features read actual latest payload values")
	evidence.skills = {"torquemada": tq, "hades": hades, "single_s1_heal": f.ally_healing}


func map_semantics() -> void:
	var raw: Dictionary = {"id": "fixture", "width": 1408.0, "height": 792.0, "spawns": {0: [Vector2(180, 396)], 1: [Vector2(1228, 396)]}, "obstacles": [], "hazards": []}
	# Arena data uses JSON-like [x,y] spawn arrays; use the public arena fields
	# for this isolated geometry fixture to avoid coupling to layout factories.
	var open: Arena = Arena.from_data(raw)
	open.spawns = {0: [Vector2(180, 396)], 1: [Vector2(1228, 396)]}
	var middle: Dictionary = raw.duplicate(true)
	middle.obstacles = [{"shape": "rect", "x": 680.0, "y": 120.0, "w": 48.0, "h": 550.0}]
	var wall: Arena = Arena.from_data(middle)
	wall.spawns = open.spawns.duplicate(true)
	var edge_raw: Dictionary = middle.duplicate(true)
	edge_raw.obstacles[0].x = 65.0
	var edge: Arena = Arena.from_data(edge_raw)
	edge.spawns = open.spawns.duplicate(true)
	var o: Dictionary = DraftDirector.map_features(open)
	var w: Dictionary = DraftDirector.map_features(wall)
	var e: Dictionary = DraftDirector.map_features(edge)
	check(is_equal_approx(float(w.walls), float(e.walls)), "equal area/count fixture preserves old density")
	check(w.fire_lanes < e.fire_lanes and w.choke > e.choke, "moving the same wall into the combat corridor changes actual lanes")
	check(DraftContextV2.route_estimate(wall, open.spawns[0][0], open.spawns[1][0]) > 1048.0, "blocking wall increases approach distance")
	check(is_equal_approx(DraftContextV2.route_estimate(wall, open.spawns[0][0], open.spawns[1][0]), DraftContextV2.route_estimate(wall, open.spawns[1][0], open.spawns[0][0])), "route proxy is symmetric across draft sides")
	var control: Arena = Arena.from_data({"id": "control_fixture", "ruleset": "control", "control_points": [{"id": "A", "x": 600, "y": 396, "radius": 75}], "heal_zones": [{"id": "heal", "x": 650, "y": 396, "radius": 40, "cooldown": 10, "heal_ratio": 0.35}]})
	var near: Dictionary = DraftDirector.map_features(control)
	control.heal_zones[0].cooldown = 40.0
	var slow: Dictionary = DraftDirector.map_features(control)
	control.heal_zones[0].center = Vector2(1200, 600)
	var far: Dictionary = DraftDirector.map_features(control)
	check(near.heal_supply > slow.heal_supply, "heal cooldown changes sustainable pickup supply")
	check(slow.point_heal > far.point_heal, "leaving an objective for a distant heal has a real opportunity cost")
	for a: Arena in DB.arenas_for("elimination") + DB.arenas_for("control"):
		var features: Dictionary = DraftDirector.map_features(a)
		for key in DraftDirector.MAP_FEATURE_KEYS:
			check(is_finite(features[key]) and features[key] >= 0.0 and features[key] <= 1.0, "%s normalized public feature %s" % [a.id, key])
	evidence.geometry = {"open": o, "wall": w, "edge": e, "heal_near": near, "heal_slow": slow, "heal_far": far}


func context_semantics() -> void:
	var d := DraftDirector.new({"team_size": 3, "arena_id": "classic", "rollout_enabled": false})
	var own: PackedInt32Array = d.members(d.mask_of(["werewolf", "swordsman", "torquemada"]))
	var enemy: PackedInt32Array = d.members(d.mask_of(["archer", "mage", "engineer"]))
	d.mapf.fire_lanes = 1.0
	var exposed: float = d._exposure(own, enemy)
	d.mapf.fire_lanes = 0.0
	check(d._exposure(own, enemy) < exposed, "same melee team has less incoming crossfire behind broken firing lanes")
	var c := DraftDirector.new({"team_size": 3, "arena_id": "control_citadel", "ruleset": "control", "rollout_enabled": false})
	var fs: Array = [c.feats[c.index.swordsman], c.feats[c.index.mage], c.feats[c.index.torquemada]]
	c.mapf.rotation_distance = 180.0
	var nearby: float = c.mode_composition(fs)
	c.mapf.rotation_distance = 1500.0
	check(c.mode_composition(fs) < nearby, "same team pays a rotation cost on separated objectives")
	for director: DraftDirector in [d, c]:
		for teams in [[["mage"], ["swordsman"]], [["torquemada", "engineer"], ["hades", "archer"]]]:
			var a: int = director.mask_of(teams[0])
			var b: int = director.mask_of(teams[1])
			check(is_equal_approx(director.value(a, b), -director.value(b, a)), "mode/context changes retain side antisymmetry")
	d.cancel()
	c.cancel()


func prior_semantics() -> void:
	var saved: Dictionary = DraftDirector._cal_cache
	DraftDirector._cal_cache = {"duel": {}, "team": {}, "team_elim": {"mage": 0.1}, "team_control": {"mage": -0.1},
		"map_team_elim": {"classic": {"mage": 0.04}}, "map_team_control": {"control_citadel": {"mage": -0.03}}, "games": 0}
	var elim := DraftDirector.new({"arena_id": "classic", "ruleset": "elimination"})
	var control := DraftDirector.new({"arena_id": "control_citadel", "ruleset": "control"})
	var unseen := DraftDirector.new({"arena_id": "classic", "ruleset": "deathmatch"})
	check(is_equal_approx(elim.team_power[elim.index.mage], 0.14), "matched elimination map prior supplements its own mode")
	check(is_equal_approx(control.team_power[control.index.mage], -0.13), "matched control map prior supplements its own mode")
	check(is_equal_approx(unseen.team_power[unseen.index.mage], 0.1), "unmeasured mode cannot borrow another mode's map residual")
	DraftDirector._cal_cache = saved
