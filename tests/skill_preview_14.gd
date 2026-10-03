extends SceneTree

var passed: int = 0
var failed: Array[String] = []
var results: Array = []
var active_count: int = 0
var passive_count: int = 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed.append(label)
		push_error("SKILL PREVIEW: " + label)

func fingerprint() -> String:
	var data: Array = []
	for d: Defs.CharDef in DB.characters:
		var abilities: Array = []
		for a: Defs.AbilityDef in d.abilities:
			var values: Dictionary = {}
			for property in a.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0: values[str(property.name)] = a.get(str(property.name))
			abilities.append(values)
		data.append({"id": d.id, "stats": d.stats.duplicate(true), "passives": d.passives.duplicate(true), "rules": d.rules.duplicate(true), "abilities": abilities})
	for arena: Arena in DB.arenas: data.append(arena.data.duplicate(true))
	return JSON.stringify(data)

func count(preview: SkillPreviewScenario, type: String, source: int = -99, rule: String = "") -> int:
	var total: int = 0
	for event in preview.events:
		if event.type == type and (source == -99 or int(event.s) == source) and (rule.is_empty() or str(event.rule) == rule): total += 1
	return total

func active_effect(preview: SkillPreviewScenario, ability: Defs.AbilityDef) -> bool:
	var m: Dictionary = preview.metrics
	if ability.char_id == "baseball" and ability.index == 1:
		var hits: Array[float] = []
		for event in preview.events:
			if event.type == "HEALTH_DAMAGED" and event.g == 0:
				hits.append(float(event.amount) / (preview.target.def.stat("critMultiplier") if bool(event.crit) else 1.0))
		return m.buffs.has("projectileGuard") and hits.size() == 2 and is_equal_approx(hits[0] * 2.0, hits[1])
	match ability.action:
		"fakeNews": return count(preview, "FAKE_NEWS", 0) > 0
		"diversion": return count(preview, "DIVERSION", 0) > 0 and m.statuses.has("taunt")
		"propaganda": return count(preview, "PROPAGANDA", 0) > 0 and m.buffs.has("abilityCoefficient")
		"interrogate": return count(preview, "INFO_REVEAL", 0) > 0
		"prison": return count(preview, "PRISON_CREATED", 0) > 0
		"upgrade": return int(m.max_turret_level) >= 2
		"detonate": return count(preview, "SUMMON_DESTROYED", 0) > 0 and float(m.damage) > 0
		"rootGarden": return m.statuses.has("root") and count(preview, "GARDEN_CLOSED", 0) > 0
		"thornGarden": return count(preview, "GARDEN_CLOSED", 0) > 0 and float(m.damage) > 0
		"portalPair": return count(preview, "PORTAL_USED", 0) > 0
		"portalArming": return count(preview, "PROJECTILE_PORTAL", 0) > 0
		"rift": return count(preview, "PROJECTILE_BLOCKED", 0) > 0 or count(preview, "PROJECTILE_REFLECTED", 0) > 0
		"wallRun": return float(m.actor_distance) > 15.0
		"prime": return count(preview, "HEALTH_DAMAGED", 0) > 0 and (m.statuses.has("sniperVulnerable") or count(preview, "STAT_STOLEN", 0) > 0)
		"cloak": return m.statuses.has("invisible") and count(preview, "ABILITY_RECAST", 0) > 0 and m.statuses.has("stun")
		"bed": return count(preview, "SUMMON_CREATED", 0) > 0 and float(m.healing) > 0
		"plantTree", "plantFlowers": return count(preview, "SUMMON_CREATED", 0) > 0 and float(m.healing) > 0
		"healingMist", "rescuePull": return float(m.healing) > 0
		"rescueFlight": return float(m.shielding) > 0 and float(m.actor_distance) > 20
		"apple": return m.statuses.has("frenzy")
	# Ordinary skills must produce a real state/effect event attributable to the
	# selected ability, never merely the cast animation or another passive.
	# V2 adds dashes, cleanses, guard blocks, heal blocks and chariot knocks.
	var effect_event: bool = false
	for event in preview.events:
		if event.ability_id == ability.id and event.type in ["HEALTH_DAMAGED", "HEAL_APPLIED", "SHIELD_APPLIED", "CC_APPLIED", "BUFF_APPLIED", "STATUS_APPLIED", "SUMMON_CREATED", "BLINKED", "STATS_SWAPPED",
				"DASH_STARTED", "CLEANSED", "FRONT_BLOCKED", "HEAL_BLOCKED", "CHARIOT_KNOCK"]:
			effect_event = true
			break
	if effect_event: return v2_active(preview, ability)
	if ability.action == "bloodLink": return m.buffs.has("maxHealth") and m.buffs.has("damageDealt")
	return false

func own_events(preview: SkillPreviewScenario, type: String, ability: Defs.AbilityDef) -> Array:
	var out: Array = []
	for event in preview.events:
		if event.type == type and event.ability_id == ability.id: out.append(event)
	return out

func distinct_targets(events: Array) -> int:
	var seen: Dictionary = {}
	for event in events: seen[int(event.g)] = true
	return seen.size()

func normalized_hit(preview: SkillPreviewScenario, event: Dictionary) -> float:
	var source: BUnit = preview.sim.u_at(int(event.s))
	return float(event.amount) / (source.def.stat("critMultiplier") if bool(event.crit) and source and source.is_hero else 1.0)

# V2 heroes (true for every other ability): the preview must show the mechanic
# itself, not only some effect event of the ability.
func v2_active(preview: SkillPreviewScenario, ability: Defs.AbilityDef) -> bool:
	var m: Dictionary = preview.metrics
	var actor: BUnit = preview.actor
	match "%s:%d" % [ability.char_id, ability.index]:
		"hades:0":
			# Concealed summon of 5 shades that bite the approaching enemies.
			return own_events(preview, "SUMMON_CREATED", ability).size() >= 5 and int(m.entities.get("shade", 0)) >= 5 and own_events(preview, "HEALTH_DAMAGED", ability).size() > 0
		"hades:1":
			# The hit leaves the target under 15%: heal block, then a real heal attempt fully blocked.
			var blocked_heal: bool = false
			for event in preview.sim.log:
				if str(event.type) == "HEAL_APPLIED" and int(event.g) == preview.target.idx and float(event.get("reduced", 0)) > 0 and float(event.amount) < 0.01: blocked_heal = true
			return own_events(preview, "HEAL_BLOCKED", ability).size() > 0 and blocked_heal
		"hades:2":
			return float(m.damage) > 0 and float(m.max_hp) > actor.def.stat("maxHealth") + 1.0
		"war_machine:0":
			# The dash spends 1 fuel; H-BALANCE basics refill by perBasic (2).
			# Keep the real dash and real basic-hit requirements unchanged.
			var basics: int = 0
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.s == 0 and bool(event.basic): basics += 1
			var tank_rule: Dictionary = actor.def.rule("fuel_tank")
			var expected: float = minf(float(tank_rule.get("max", 10.0)), SkillPreviewScenario._resource_preset(ability) - 1.0 + basics * float(tank_rule.get("perBasic", 1.0)))
			return own_events(preview, "DASH_STARTED", ability).size() > 0 and basics > 0 and absf(float(actor.resources.get("fuel", -1)) - expected) < 0.01
		"war_machine:1":
			var full_charge: bool = false
			for event in own_events(preview, "CAST_STARTED", ability): full_charge = full_charge or int(event.charge) == 6
			return full_charge and own_events(preview, "HEALTH_DAMAGED", ability).size() >= 6 and float(actor.resources.get("fuel", -1)) < 0.01 and m.buffs.has("moveSpeed")
		"war_machine:2":
			return m.buffs.has("damageTaken") and float(m.shielding) > 0
		"war_machine:3":
			return own_events(preview, "HEALTH_DAMAGED", ability).size() > 0 and m.statuses.has("slow") and float(actor.resources.get("fuel", -1)) < 0.01
		"torquemada:0", "torquemada:2":
			var cleansed_ally: bool = false
			for event in own_events(preview, "CLEANSED", ability): cleansed_ally = cleansed_ally or int(event.g) == preview.ally.idx
			var damaged_enemy: bool = false
			for event in own_events(preview, "HEALTH_DAMAGED", ability): damaged_enemy = damaged_enemy or (int(event.g) == preview.target.idx and float(event.amount) > 0.0)
			if ability.index == 0:
				var healed_ally: bool = false
				for event in own_events(preview, "HEAL_APPLIED", ability): healed_ally = healed_ally or (int(event.g) == preview.ally.idx and float(event.amount) > 0.0)
				return cleansed_ally and healed_ally and damaged_enemy
			var shielded_ally: bool = false
			for event in own_events(preview, "SHIELD_APPLIED", ability): shielded_ally = shielded_ally or (int(event.g) == preview.ally.idx and float(event.amount) > 0.0)
			return cleansed_ally and shielded_ally and damaged_enemy and own_events(preview, "DASH_STARTED", ability).size() > 0
		"torquemada:1":
			var damaged_target: bool = false
			for event in own_events(preview, "HEALTH_DAMAGED", ability): damaged_target = damaged_target or (int(event.g) == preview.target.idx and float(event.amount) > 0.0)
			for event in own_events(preview, "CC_APPLIED", ability):
				if event.status == "root" and int(event.g) == preview.target.idx: return damaged_target
			return false
		"achilles:0":
			return distinct_targets(own_events(preview, "HEALTH_DAMAGED", ability)) >= 2
		"achilles:1":
			# Front attacks are blocked while the guard is up; the one from behind passes.
			var guard: Array = own_events(preview, "STATUS_APPLIED", ability)
			if guard.is_empty(): return false
			var start: float = float(guard[0].t)
			var rear_hit: bool = false
			var front_hit: bool = false
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.g == 0 and float(event.t) > start and float(event.t) < start + 2.0:
					rear_hit = rear_hit or int(event.s) == preview.secondary.idx
					front_hit = front_hit or int(event.s) != preview.secondary.idx
			return count(preview, "FRONT_BLOCKED") >= 2 and rear_hit and not front_hit
		"achilles:2":
			for event in preview.events:
				if event.type == "CC_APPLIED" and int(event.g) == preview.target.idx and float(event.duration) > 1.0 + 0.001: return m.statuses.has("roar")
			return false
		"achilles:3":
			# Knocks are credited to achilles (the chariot entity carries no ability).
			var knocks: Array = []
			for event in preview.events:
				if event.type == "CHARIOT_KNOCK" and event.s == 0: knocks.append(event)
			return own_events(preview, "SUMMON_CREATED", ability).size() > 0 and distinct_targets(knocks) >= 2
	return true

func passive_effect(preview: SkillPreviewScenario) -> bool:
	var m: Dictionary = preview.metrics
	var rule: String = str(preview.entry.rule)
	match rule:
		"nth_basic_bonus", "on_cast_buff", "on_cc_cdr", "lost_health_ap_on_skill_hit", "timed_random_buff", "projectile_reflect_arc", "borrow_mobility", "nexus_workshop": return count(preview, "PASSIVE", 0, rule) > 0
		"distance_damage":
			var hits: Array[float] = []
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.s == 0:
					hits.append(float(event.amount) / (preview.actor.def.stat("critMultiplier") if bool(event.crit) else 1.0))
			return hits.size() >= 2 and hits[0] > hits[1] * 1.1
		"damage_heal", "regen": return float(m.healing) > 0
		"health_size_scaling": return float(m.max_radius) > float(m.min_radius) + 1.0
		"on_ally_buff_shield": return count(preview, "SHIELD_APPLIED", 0) > 0 and float(m.shielding) > 0
		"cone_basic": return count(preview, "HEALTH_DAMAGED", 0) > 0 and m.statuses.has("stun")
		"hybrid_basic":
			var true_hit: bool = false
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.s == 0 and event.school == "true": true_hit = true
			return true_hit and count(preview, "PROJECTILE_CREATED", 0) > 0
		"confusion_on_damage": return int(m.statuses.get("confusion", 0)) > 0
		"orbit_aura": return float(m.damage) > 0 and float(m.healing) > 0
		"heal_reduction_bank": return float(m.resources.get("healBank", 0)) > 0
		"plague_heal_reduction":
			for event in preview.sim.log:
				if str(event.type) == "HEAL_APPLIED" and float(event.get("reduced", 0)) > 0: return true
			return false
		"reveal_cooldowns": return count(preview, "REVEAL", 0) > 0
		"rage_on_damage": return float(m.resources.get("rage", 0)) >= 4.0
		"wall_mastery": return count(preview, "PASSIVE", 0, rule) > 0 and float(m.actor_distance) > 20
		"portal_shards": return float(m.resources.get("shards", 0)) >= 10 and count(preview, "PORTAL_USED", 0) > 0
		"out_of_combat_speed": return float(m.max_ms) > preview.actor.def.stat("moveSpeed") * 1.5 and float(m.actor_distance) > 100
		"nexus_seed_path": return count(preview, "GARDEN_CLOSED", 0) > 0 and float(m.healing) > 0
		"pain_stacks": return int(m.statuses.get("pain", 0)) >= 2 and count(preview, "HEALTH_DAMAGED", 0) > 2
		"contemplation": return float(m.max_coefficient) >= 1.3 and count(preview, "CC_IMMUNE") > 0
		"media_control": return count(preview, "INFO_BLOCKED") > 0
		# V2 heroes
		"concealed_regen":
			# No regeneration in the open; it starts once hades is in the brush.
			var first_heal: float = INF
			for event in preview.events:
				if event.type == "HEAL_APPLIED" and event.s == 0 and event.g == 0 and float(event.amount) > 0: first_heal = minf(first_heal, float(event.t))
			return float(m.healing) > 0 and first_heal > 1.5
		"companion":
			var bites: int = 0
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.s == 0 and event.source_type == "SUMMON": bites += 1
			return int(m.entities.get("cerberus", 0)) == 1 and bites >= 2
		"fuel_tank":
			return float(m.resources.get("fuel", 0)) >= 1 and count(preview, "TANK_DESTROYED") > 0 and count(preview, "OVERDRIVE", 0) > 0 \
				and float(m.max_ms) >= preview.actor.def.stat("moveSpeed") * 1.45 and float(preview.actor.resources.get("fuel", -1)) < 0.01
		"faith_tenacity", "status_tenacity":
			# Same nominal CC on the actor and on the ally (and a stun after the charm).
			var lasted: Dictionary = {}
			for event in preview.events:
				if event.type == "CC_APPLIED" and (event.g == 0 or event.g == preview.ally.idx): lasted["%s:%d" % [event.status, event.g]] = float(event.duration)
			var ally_key: String = ":%d" % preview.ally.idx
			if rule == "faith_tenacity":
				return lasted.has("stun:0") and lasted.has("stun" + ally_key) and float(lasted["stun:0"]) < float(lasted["stun" + ally_key]) * 0.75
			return lasted.has("charm:0") and lasted.has("stun:0") and lasted.has("charm" + ally_key) \
				and float(lasted["charm:0"]) < float(lasted["stun:0"]) * 0.6 and float(lasted["charm:0"]) < float(lasted["charm" + ally_key]) * 0.5
		"basic_armor_bonus":
			var basic_hit: float = -1.0
			var skill_hit: float = -1.0
			for event in preview.events:
				if event.type == "HEALTH_DAMAGED" and event.g == 0 and int(event.s) == preview.secondary.idx:
					if bool(event.basic): basic_hit = normalized_hit(preview, event)
					else: skill_hit = normalized_hit(preview, event)
			return basic_hit > 0 and skill_hit > 0 and basic_hit < skill_hit * 0.95
	return false

func booster_fuel_trace() -> void:
	var preview: SkillPreviewScenario = SkillPreviewScenario.new("war_machine", "active:0")
	var ability: Defs.AbilityDef = preview.actor.def.abilities[0]
	var rule: Dictionary = preview.actor.def.rule("fuel_tank")
	var fuel_now: float = SkillPreviewScenario._resource_preset(ability)
	var spend: float = 0.0
	var dash: float = 0.0
	for effect in ability.effects:
		if str(effect.get("type", "")) == "consume_resource": spend += float(effect.get("amount", 0.0))
		if str(effect.get("type", "")) == "move_self": dash = float(effect.get("distance", 0.0))
	# Resource deltas are frame events, not entries in BattleSim.LOG_TYPES.
	var frame_events: Array = []
	while preview.step(): frame_events.append_array(preview.sim.drain_frame_events())
	var spent: int = 0
	var refills: int = 0
	var valid: bool = true
	for event in frame_events:
		if str(event.type) != "RESOURCE_CHANGED" or int(event.s) != preview.actor.idx or str(event.get("key", "")) != "fuel": continue
		var amount: float = float(event.amount)
		if amount < 0.0:
			spent += 1
			valid = valid and is_equal_approx(amount, -spend) and refills == 0
		else:
			refills += 1
			valid = valid and is_equal_approx(amount, minf(float(rule.get("perBasic", 1.0)), float(rule.get("max", 10.0)) - fuel_now))
		fuel_now += amount
		valid = valid and is_equal_approx(float(event.value), fuel_now)
	check(valid and spent == 1 and refills == 3, "booster preview spends once then demonstrates three data-sized fuel refills")
	check(is_equal_approx(float(preview.actor.resources.fuel), fuel_now), "booster preview final fuel matches the complete resource-event ledger")
	check(dash > 0.0 and absf(float(preview.metrics.actor_distance) - dash) < 0.1, "booster preview demonstrates the complete actual dash distance")
	check(preview.instructions.contains("연료가 %s씩" % CodexData.num(float(rule.get("perBasic", 1.0)))), "booster preview instructions state the current fuel gain")
	preview.dispose()


func _run() -> void:
	DB.ensure_loaded()
	var before: String = fingerprint()
	var coverage: Dictionary = {}
	for character: Defs.CharDef in DB.characters:
		var choices: Array = SkillPreviewScenario.entries(character.id)
		coverage[character.id] = choices.size()
		check(choices.size() == character.abilities.size() + character.passives.size(), character.id + " all skills and passives listed")
		for choice in choices:
			var preview: SkillPreviewScenario = SkillPreviewScenario.new(character.id, str(choice.id))
			var steps: int = 0
			while preview.step():
				preview.sim.drain_frame_events()
				steps += 1
				if steps > 600: break
			var meaningful: bool
			if choice.kind == "active":
				active_count += 1
				var ability: Defs.AbilityDef = character.abilities[int(choice.index)]
				var completed: bool = false
				for event in preview.events:
					if event.type == "CAST_COMPLETED" and event.s == 0 and event.ability_id == ability.id: completed = true
				check(preview.cast_started and completed, character.id + ":" + choice.id + " real cast completed")
				meaningful = active_effect(preview, ability)
			else:
				passive_count += 1
				meaningful = passive_effect(preview)
			check(meaningful, character.id + ":" + choice.id + " actual effect demonstrated")
			check(preview.finished and steps <= 600, character.id + ":" + choice.id + " bounded completion")
			results.append({"character": character.id, "entry": choice.id, "meaningful": meaningful,
				"cast_started": preview.cast_started, "duration": preview.elapsed, "metrics": preview.metrics.duplicate(true)})
			preview.dispose()
			check(preview.sim == null and not preview.step(), character.id + ":" + choice.id + " disposal stops safely")
	check(coverage.size() == 26, "all 26 characters covered")
	check(fingerprint() == before, "shared character AbilityDef and Arena definitions unchanged")
	booster_fuel_trace()
	var replay: SkillPreviewScenario = SkillPreviewScenario.new("mage", "active:0")
	for _i in 75: replay.step()
	var first_events: String = JSON.stringify(replay.events)
	replay.restart()
	for _i in 75: replay.step()
	check(first_events == JSON.stringify(replay.events), "restart is deterministic and isolated")
	replay.dispose()
	var invalid: SkillPreviewScenario = SkillPreviewScenario.new("missing_character", "passive:999")
	check(invalid.sim == null and not invalid.step(), "invalid selection safely remains stopped")
	invalid.dispose()
	var report: Dictionary = {"status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"entries": active_count + passive_count, "active": active_count, "passive": passive_count,
		"all22coverage": coverage, "evidence": results}
	var file: FileAccess = FileAccess.open("res://reports/skill_preview_14.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SKILL_PREVIEW_14 ", JSON.stringify({"status": report.status, "passed": passed, "failed": failed, "entries": report.entries}))
	quit(0 if failed.is_empty() else 1)
