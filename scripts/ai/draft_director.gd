class_name DraftDirector
extends RefCounted





const VERSION: = "GD-DRAFT-2.0-HF1"
const SHIFT: = 1 << 32
const HARD_CC: = ["stun", "root", "airborne", "suppression", "charm", "sleep", "silence", "control", "taunt"]

var ids: Array = []
var index: Dictionary = {}
var feats: Array = []
var n: int = 0
var matrix: = PackedFloat32Array()
var pairs: = PackedFloat32Array()
var team_power: = PackedFloat32Array()
var mapf: Dictionary = {}
var hero_fit: = PackedFloat64Array()   # map_fit(feats[i], mapf), computed once per director
var arena_name: String = ""
var team_size: int = 1
var arena_id: String = "classic"
var ruleset: String = "elimination"
var seed_value: int = 1
var user_history: Dictionary = {}
var budget: int = 45000

var _q_cache: Dictionary = {}
var _v_cache: Dictionary = {}
var _f_cache: Dictionary = {}
var _members_cache: Dictionary = {}
var evals: int = 0
var nodes: int = 0
var last_decision: Dictionary = {}
var cache_misses: int = 0
var search_options: Dictionary = {}
var _job: RefCounted


func _init(options: Dictionary = {}) -> void :
	DB.ensure_loaded()
	team_size = clampi(int(options.get("team_size", 1)), 1, 5)
	arena_id = str(options.get("arena_id", "classic"))
	ruleset = str(options.get("ruleset", DB.arena(arena_id).ruleset))
	seed_value = int(options.get("seed", 1))
	user_history = options.get("user_history", {})
	search_options = options.duplicate(true)
	_prepare()
	budget = clampi(int(options.get("budget", 45000)), n, 200000)






static func _flatten(effects: Array, out: Array) -> void :
	for e in effects:
		if not (e is Dictionary):
			continue
		out.append(e)
		if e.has("effects"):
			_flatten(e.effects, out)
		if e.has("damageEffect") and e.damageEffect is Dictionary:
			_flatten([e.damageEffect], out)
		if e.has("attack") and e.attack is Dictionary:
			_flatten([e.attack], out)
		if e.has("originPayload") and e.originPayload is Array:
			_flatten(e.originPayload, out)


static func _weighted(effects: Array, weight: float, rows: Array, inherited: String) -> void :
	for e in effects:
		if not (e is Dictionary):
			continue
		var filter: = str(e.get("filter", inherited))
		rows.append({"e": e, "w": weight, "filter": filter})
		var max_t: = float(e.get("maxTriggers", 1000000000.0))
		var ticks: = maxf(1.0, minf(max_t, floorf(float(e.get("duration", 1.0)) / maxf(0.25, float(e.get("interval", 1.0))))))
		var ty: = str(e.get("type", ""))
		if e.has("effects"):
			# A one-shot zone payload is one application per recipient, even when
			# its trigger volume polls several times per second (Torquemada S1).
			var repeats: float = ticks * 0.55 if ty == "zone" and not bool(e.get("oncePerUnit", false)) else 1.0
			_weighted(e.effects, weight * repeats, rows, filter)
		if e.has("damageEffect") and e.damageEffect is Dictionary:
			_weighted([e.damageEffect], weight * (ticks if ty == "dot" else 1.0), rows, filter)
		if e.has("originPayload") and e.originPayload is Array:
			_weighted(e.originPayload, weight, rows, "")


static func kit_features(d: Defs.CharDef) -> Dictionary:
	var hp: = d.stat("maxHealth")
	var ad: = d.stat("attackDamage")
	var ap: = d.stat("abilityPower")
	var basic: = ad * maxf(0.1, d.stat("attackSpeed")) * (1.0 + d.stat("critChance") * (maxf(1.0, d.stat("critMultiplier")) - 1.0))
	if d.has_rule("no_basic"):
		basic = 0.0
	var spell: = 0.0
	var magic: = 0.0
	var hard: = 0.0
	var aoe: = 0.0
	var heal: = 0.0
	var ally_heal: = 0.0
	var shield: = 0.0
	var ally_shield: = 0.0
	var ally_guard: = 0.0
	var mobility: = 0.0
	var projectile: = 0.0
	var self_invuln: = false
	var ally_only: = 0
	var cleanse_rate: float = 0.0
	var anti_heal_strength: float = 0.0
	var displacement: float = 0.0
	var retaliation: float = 0.0
	var charm: float = 0.0
	var types: Dictionary = {}
	var support_reach: = 1.0
	var support_interval: = 30.0
	for ab in d.abilities:
		var a: Defs.AbilityDef = ab
		var es: Array = []
		_flatten(a.effects, es)
		var ability_zone: bool = false
		for e in es:
			types[str(e.get("type", ""))] = true
			ability_zone = ability_zone or str(e.get("type", "")) == "zone"
		var cd: = maxf(0.25, a.cooldown)
		var gate: = 0.55 if not a.condition.is_empty() else (0.7 if a.action in ["detonate", "upgrade", "rootGarden", "thornGarden"] else 1.0)
		var other_ally: = bool(a.flag("originOtherAlly", false))
		var supports: = a.target in ["ally", "position_ally", "ally_area"] or other_ally
		# Area payloads dispatch heal/shield/cleanse to allies even when their
		# shared damage payload targets enemies (e.g. the Alhambra edict).
		var support_area: bool = a.delivery == "area" and a.tags.has("SUPPORT")
		supports = supports or support_area
		if a.condition.has("ccSourceWithin"):
			retaliation += float(a.condition.ccSourceWithin) / cd
		if supports:
			support_reach = maxf(support_reach, a.range + a.radius)
			support_interval = minf(support_interval, cd)
		if other_ally:
			ally_only += 1
		var damage: = 0.0
		var rows: Array = []
		_weighted(a.effects, 1.0, rows, "")
		for row in rows:
			var e: Dictionary = row.e
			var w: float = row.w
			var filter: String = row.filter
			var ty: = str(e.get("type", ""))
			match ty:
				"damage":
					var amount: = (float(e.get("base", 0.0)) + float(e.get("ad", 0.0)) * ad + float(e.get("ap", 0.0)) * ap + float(e.get("targetMaxHp", 0.0)) * 1100.0 + float(e.get("selfMaxHp", 0.0)) * hp) * w
					damage += amount
					if str(e.get("school", "")) == "magic":
						magic += amount * gate / cd
					heal += amount * float(e.get("sourceHealRatio", 0.0)) * gate / cd
				"heal":
					if filter != "both" and filter != "enemy":
						var h: = (float(e.get("base", 0.0)) + float(e.get("ad", 0.0)) * ad + float(e.get("ap", 0.0)) * ap) * gate * w / cd
						if a.action == "plantTree":
							# Trees pulse while alive, unlike a single ordinary heal.
							for summon in es:
								if str(summon.get("type", "")) == "summon":
									h *= minf(cd, float(summon.get("duration", cd))) / maxf(0.25, float(summon.get("interval", 1.0))) * 0.55
						if not other_ally:
							heal += h * (float(d.rule("nexus_seed_path").get("selfHealingRatio", 1.0)) if a.action in ["plantTree", "plantFlowers"] else 1.0)
						if supports or filter == "ally" or str(e.get("applyTo", "")) == "ally_area":
							ally_heal += h
							support_reach = maxf(support_reach, a.range + a.radius)
							support_interval = minf(support_interval, cd)
				"shield":
					if filter != "both" and filter != "enemy":
						var h2: = (float(e.get("base", 0.0)) + float(e.get("ad", 0.0)) * ad + float(e.get("ap", 0.0)) * ap) * gate * w / cd
						if not other_ally:
							shield += h2
						if supports or filter == "ally" or str(e.get("applyTo", "")) == "ally_area":
							ally_shield += h2
				"buff":
					if str(e.get("stat", "")) == "regen":
						heal += float(e.get("amount", 0.0)) * float(e.get("duration", 0.0)) / cd
				"status":
					var s: = str(e.get("status", ""))
					if s == "invulnerable":
						if supports:
							ally_guard += 0.35
						if not other_ally:
							self_invuln = true
					if s in HARD_CC:
						hard += minf(2.0, float(e.get("duration", 0.7)) + float(e.get("originThenStun", 0.0))) * gate / cd
					if s == "charm":
						charm += float(e.get("duration", 0.0)) * gate / cd
					if s == "healReduction":
						var threshold: float = float(e.get("whenTargetHpBelow", 1.0))
						anti_heal_strength += clampf(float(e.get("magnitude", 0.0)), 0.0, 1.0) * minf(1.0, float(e.get("duration", 0.0)) / cd) * threshold
				"cleanse":
					if filter != "enemy" and filter != "both":
						cleanse_rate += gate / cd
				"heal_bank":
					heal += 0.0
				"displace":
					if filter != "ally" and (not supports or support_area):
						hard += 0.35 * gate / cd
						displacement = maxf(displacement, float(e.get("distance", 0.0)) * minf(1.0, 10.0 / cd))
				"move_self", "blink", "dash":
					mobility += 0.4
		if a.delivery == "projectile":
			projectile += 1.0
		if a.delivery in ["dash", "blink"] or a.action in ["contactDash", "wallRun", "rescueFlight", "portalPair", "cloak"]:
			mobility += 0.4
		var area: = a.delivery in ["area", "cone", "line"] or ability_zone or a.pierce > 0
		if area and damage > 0.0:
			aoe += gate * 0.3
		spell += damage * gate / cd
	if d.id == "war_machine":
		# V2: 2-6 missile charge (S2), arc protector guard (S3), 2.5 s booster.
		var wm: Dictionary = WarMachineTactics.draft_features(d)
		spell += float(wm.spell)
		shield += float(wm.shield)
		mobility += float(wm.mobility)
	if d.has_rule("damage_heal"):
		heal += basic * float(d.rule("damage_heal").get("ratio", 0.0))
	if d.has_rule("regen"):
		heal += float(d.rule("regen").get("perSecond", 0.0))
	if d.has_rule("orbit_aura"):
		var orbit: Dictionary = d.rule("orbit_aura")
		var orbit_heal: Dictionary = orbit.get("allyHeal", {})
		var orbit_damage: Dictionary = orbit.get("enemyDamage", {})
		var contacts: float = 2.0 / maxf(0.35, float(orbit.get("interval", 2.0))) * 0.55
		var pulse: float = (float(orbit_heal.get("base", 0.0)) + ap * float(orbit_heal.get("ap", 0.0))) * contacts
		ally_heal += pulse
		var orbit_dps: float = (float(orbit_damage.get("base", 0.0)) + ap * float(orbit_damage.get("ap", 0.0)) + ad * float(orbit_damage.get("ad", 0.0))) * contacts
		spell += orbit_dps
		magic += orbit_dps if str(orbit_damage.get("school", "")) == "magic" else 0.0
		aoe += 0.25
	if d.has_rule("nexus_seed_path"):
		var garden: Dictionary = d.rule("nexus_seed_path")
		var per_second: float = minf(float(garden.get("rateCap", 0.0)), (float(garden.get("budgetBase", 0.0)) + ap * float(garden.get("budgetAp", 0.0))) / maxf(1.0, float(garden.get("duration", 14.0))))
		# One established, occupied garden; creating/retaining it is not certain.
		heal += per_second * float(garden.get("selfHealingRatio", 1.0)) * 0.55
		ally_heal += per_second * 0.55
	if d.id == "politician":
		ally_guard += 0.55
		hard += 0.1
		ally_only = 3
		support_reach = 440.0
	if d.id == "torturer":
		# Pain contributes sustained pressure; prison contributes control.
		spell += 6.0
		hard += 0.1
	if d.id == "hades":
		# V2 hades: Kynee regeneration, harvested max HP and harvest damage,
		# cerberus bites and the shade ring (HadesTactics.draft_features).
		var hf: Dictionary = HadesTactics.draft_features(d)
		heal += float(hf.heal)
		spell += float(hf.spell)
		magic += float(hf.get("magic", 0.0))
	if d.id == "achilles":
		# V2: chariot contacts and the roar's control amplification.
		var achilles_terms: Dictionary = AchillesTactics.draft_terms(d)
		spell += float(achilles_terms.spell)
		hard += float(achilles_terms.hard)
	var summons: = types.has("summon") or d.tags.has("SUMMONER")
	if summons:
		spell += {"engineer": 23.0, "hive_mind": 16.0, "blood_mage": 12.0}.get(d.id, 0.0)
	var durability: = hp * (1.0 + (d.stat("armor") + d.stat("magicResistance")) / 200.0) / 1400.0
	var healing: = clampf(heal / 22.0, 0.0, 2.0)
	var shielding: = clampf(shield / 14.0, 0.0, 1.5)
	var protection: = clampf(shielding + (0.45 if self_invuln else 0.0) + (0.35 if types.has("projectile_guard") or types.has("front_guard") else 0.0), 0.0, 1.7)
	var projectile_answer: = types.has("projectile_guard") or types.has("front_guard") or d.has_rule("projectile_reflect_arc") or d.has_rule("projectile_reflect") or d.has_rule("projectile_nullify")
	var anti_heal: = d.has_rule("plague_heal_reduction") or types.has("heal_reduction")
	if anti_heal:
		var plague: Dictionary = d.rule("plague_heal_reduction")
		var reduction: float = minf(float(plague.get("maxReduction", 1.0)), float(plague.get("perStack", 0.0)) * float(plague.get("maxStacks", 1)))
		anti_heal_strength = maxf(anti_heal_strength, reduction)
	var rng_: = d.stat("attackRange")
	var ms: = d.stat("moveSpeed")
	var movement: = clampf(mobility + maxf(0.0, ms - 90.0) / 90.0, 0.0, 1.5)
	var ranged: = rng_ >= 120.0
	var melee: = rng_ < 90.0
	return {
		"id": d.id, "range": rng_, "durability": durability, "healing": healing, "shielding": shielding, "protection": protection, 
		"move_speed": ms, "preferred_range": d.preferred_range, "support_reach": support_reach, "support_interval": support_interval, 
		"max_health": hp, "raw_damage": basic + spell, "ally_only": float(ally_only) / maxf(1.0, d.abilities.size()), 
		"ally_healing": clampf(ally_heal / 22.0, 0.0, 2.0), 
		"ally_protection": clampf(ally_shield / 14.0 + ally_guard + (0.3 if d.id == "dimensionalist" else 0.0), 0.0, 1.7), 
		"damage": clampf((basic + spell) / 85.0, 0.2, 2.0), "magic": clampf(magic / maxf(1.0, basic + spell), 0.0, 1.0), 
		"control": clampf(hard * 5.0 + (0.45 if d.has_rule("cone_basic") else 0.0), 0.0, 1.5), 
		"area": clampf(aoe, 0.0, 1.5), "mobility": movement, 
		"projectile": clampf(projectile / maxf(1.0, d.abilities.size()) + (0.4 if rng_ >= 120.0 else 0.0), 0.0, 1.0), 
		"projectile_answer": 1.0 if projectile_answer else 0.0, "anti_heal": 1.0 if anti_heal_strength > 0.0 else 0.0,
		"anti_heal_strength": clampf(anti_heal_strength, 0.0, 1.0),
		"summon": 1.0 if summons else 0.0, "ranged": ranged, "melee": melee, 
		"burst": clampf(spell / 30.0, 0.0, 1.5), "execute": 1.0 if types.has("execute") or d.id == "archer" else 0.0, 
		"disengage": movement * (1.0 if ranged else 0.3), "wall": 1.0 if d.has_rule("wall_mastery") or d.id in ["baseball", "engineer"] else (0.5 if d.id == "archer" else 0.0), 
		"stationary": 1.0 if d.id in ["world_tree", "engineer", "hive_mind", "politician"] else 0.0, 
		"portal": 1.0 if d.id == "dimensionalist" else 0.0, 
		"dive": movement * (1.0 if rng_ < 100.0 else 0.35), 
		"fragile": maxf(0.0, 1.0 - durability), 
		"cleanse": clampf(cleanse_rate * 8.0, 0.0, 1.0),
		"retaliation": clampf(retaliation, 0.0, 1.0), "displacement": displacement,
		"tenacity": clampf(d.stat("tenacity"), 0.0, 1.0), "charm": clampf(charm * 5.0, 0.0, 1.5),
		"charm_tenacity": clampf(float(d.rule("status_tenacity").get("charm", 0.0)), 0.0, 1.0),
		"basic_fraction": basic / maxf(1.0, basic + spell),
		"basic_guard": 1.0 - (100.0 + d.stat("armor")) / maxf(1.0, 100.0 + d.stat("armor") * (1.0 + float(d.rule("basic_armor_bonus").get("ratio", 0.0)))),
	}


# V1.5.3 (audit DR-2): every feature is a density (per playable area, relative
# to the 1408x792 baseline arena) saturated with 1 - e^(-x), so large or busy
# maps no longer pin at 1.0, and the new gimmicks are read by their DESIGN_153
# type names (brush = forests, artillery, gate obstacles, jump_pad,
# closing_ring, mud) even before an engine implements them.
const MAP_BASE_AREA: = 1333.2 * 717.2
const MAP_FEATURE_KEYS: = ["walls", "sight", "hazard", "wind", "portals", "haste", "fountain", "pull", "knockback",
	"concealment", "gates", "jump_pads", "artillery", "ring", "mud", "openness", "large", "small", "elongated",
	"approach", "flank", "split_spawns", "point_spread", "point_distance", "point_hazard", "point_push",
	"fire_lanes", "choke", "route_stretch", "point_shelter", "heal_supply", "point_heal"]


static func _sat(x: float) -> float:
	return 1.0 - exp(-maxf(0.0, x))


static func _shape_area(h: Dictionary) -> float:
	if str(h.get("shape", "circle")) == "rect":
		return maxf(0.0, float(h.get("w", 0.0))) * maxf(0.0, float(h.get("h", 0.0)))
	var r: float = maxf(0.0, float(h.get("radius", 0.0)))
	return PI * r * r


# Raw damage per second while standing in the hazard, averaged over its cycle.
static func hazard_dps(h: Dictionary) -> float:
	var typ: String = str(h.get("type", ""))
	var dmg: float = maxf(0.0, float(h.get("damage", 0.0)))
	var period: float = maxf(0.1, float(h.get("period", 1.0)))
	var tick: float = maxf(0.12, float(h.get("tickInterval", 0.5)))
	var duty: float = clampf(float(h.get("activeDuration", period)) / period, 0.0, 1.0)
	match typ:
		"lava":
			return dmg / tick * (1.0 if bool(h.get("alwaysActive", true)) else duty)
		"spikes", "gravity":
			return dmg / tick * duty
		"eruption", "shockwave":
			return dmg / period
		"artillery":
			# Aimed near heroes but telegraphed: about half the strikes connect.
			return dmg * maxf(1.0, float(h.get("count", 1.0))) / period * 0.5
		"closing_ring":
			return 0.0
	return dmg / tick * duty if dmg > 0.0 else 0.0


static func map_features(arena: Arena) -> Dictionary:
	var pw: float = maxf(1.0, arena.max_x - arena.min_x)
	var ph: float = maxf(1.0, arena.max_y - arena.min_y)
	var area: = pw * ph
	var scale: float = area / MAP_BASE_AREA
	var occupied: = 0.0
	var blockers: = 0
	var gates: = 0
	for i in arena.obs_count:
		occupied += PI * arena.obs_r[i] * arena.obs_r[i] if arena.obs_circle[i] == 1 else arena.obs_w[i] * arena.obs_h[i]
		var od: Dictionary = arena.obstacles[i] if i < arena.obstacles.size() else {}
		if od.has("gate"):
			gates += 1
		elif (arena.obs_mask[i] & Arena.MASK_VISION) != 0:
			blockers += 1
	var forest_area: = 0.0
	for k in arena.forest_x.size():
		forest_area += PI * arena.forest_r[k] * arena.forest_r[k]
	var harm: = 0.0
	var wind: = 0.0
	var portals: = 0.0
	var haste: = 0.0
	var fountain: = 0.0
	var pull: = 0.0
	var knock: = 0.0
	var pads: = 0.0
	var artillery: = 0.0
	var ring: = 0.0
	var mud: = 0.0
	for h in arena.hazards:
		var typ: String = str(h.get("type", ""))
		var cover: float = minf(1.0, _shape_area(h) / area)
		harm += hazard_dps(h) * cover
		match typ:
			"wind":
				wind += 0.6 + cover * 4.0
			"portal":
				portals += 0.5
			"haste":
				haste += 0.6 / scale
			"healing_fountain":
				fountain += float(h.get("healPercent", 0.16)) / maxf(1.0, float(h.get("cooldown", 18.0))) * 60.0 / scale
			"gravity":
				var gp: float = maxf(0.1, float(h.get("period", 9.0)))
				pull += float(h.get("force", 100.0)) / 100.0 * clampf(float(h.get("activeDuration", 2.0)) / gp, 0.0, 1.0) * sqrt(cover) * 4.0
			"eruption", "shockwave":
				knock += float(h.get("knockback", 0.0)) / 100.0 * sqrt(cover) * 2.0
			"jump_pad":
				pads += 0.4
			"artillery":
				artillery += float(h.get("damage", 0.0)) * maxf(1.0, float(h.get("count", 1.0))) / maxf(1.0, float(h.get("period", 12.0))) / 10.0
			"closing_ring":
				var r0: float = maxf(1.0, float(h.get("startRadius", 600.0)))
				ring += 0.8 + clampf((r0 - float(h.get("endRadius", r0 * 0.5))) / r0, 0.0, 1.0) * 1.5
			"mud":
				mud += cover * clampf(float(h.get("slow", 0.3)), 0.0, 0.6) * 12.0
	var own: Array = arena.spawns.get(0, [])
	var foe: Array = arena.spawns.get(1, [])
	var approach: = 0.0
	var flank: = 0.0
	var split: = 0.0
	if not own.is_empty() and not foe.is_empty():
		var c0: Vector2 = Vector2.ZERO
		var c1: Vector2 = Vector2.ZERO
		for p in own:
			c0 += p
		for p in foe:
			c1 += p
		c0 /= own.size()
		c1 /= foe.size()
		approach = _sat(maxf(0.0, c0.distance_to(c1) - 700.0) / 600.0)
		# Spawn orientation: room to the sides of the line between the teams.
		# Left/right on a wide map leaves little, top/bottom or a diagonal a lot.
		var axis: Vector2 = (c1 - c0).normalized() if c0.distance_to(c1) > 1.0 else Vector2.RIGHT
		var lateral: float = absf(axis.y) * pw + absf(axis.x) * ph
		flank = _sat(maxf(0.0, lateral / maxf(1.0, c0.distance_to(c1)) - 0.6) * 1.2)
		var spread: = 0.0
		for p in own:
			spread += (p as Vector2).distance_to(c0)
		for p in foe:
			spread += (p as Vector2).distance_to(c1)
		split = _sat(maxf(0.0, spread / (own.size() + foe.size()) - 120.0) / 250.0)
	var point_spread: = 0.0
	var point_distance: = 0.0
	var point_hazard: = 0.0
	var point_push: = 0.0
	var pts: Array = arena.control_points
	# Objective fights happen on the circles: hazards overlapping them count
	# far more in conquest than their share of the whole map suggests.
	for p in pts:
		var pr: float = maxf(1.0, float(p.get("radius", 88.0)))
		for h in arena.hazards:
			var hr: float = sqrt(_shape_area(h) / PI)
			var gap: float = (h.center as Vector2).distance_to(p.center)
			if gap > hr + pr:
				continue
			var overlap: float = clampf((hr + pr - gap) / (2.0 * minf(hr, pr) + 1.0), 0.0, 1.0)
			point_hazard += hazard_dps(h) * overlap / 3.0
			var typ: String = str(h.get("type", ""))
			if typ in ["eruption", "shockwave"]:
				point_push += float(h.get("knockback", 0.0)) / 100.0 * overlap
			elif typ == "gravity" and gap > pr:
				point_push += float(h.get("force", 100.0)) / 100.0 * overlap * 0.5
	if pts.size() >= 2:
		var pair_sum: = 0.0
		var pairs_n: = 0
		for a in pts.size():
			for b in range(a + 1, pts.size()):
				pair_sum += (pts[a].center as Vector2).distance_to(pts[b].center)
				pairs_n += 1
		point_spread = _sat(pair_sum / maxf(1.0, pairs_n) / 900.0)
		var reach_sum: = 0.0
		for side in [own, foe]:
			for p in pts:
				var near: = INF
				for s in side:
					near = minf(near, (s as Vector2).distance_to(p.center))
				reach_sum += near if near < INF else 0.0
		point_distance = _sat(reach_sum / maxf(1.0, pts.size() * 2.0) / 900.0)
	var aspect: float = maxf(pw / ph, ph / pw)
	var out: Dictionary = {"id": arena.id, "name": arena.name,
		"walls": _sat(occupied / area * 6.0 + arena.obs_count / scale * 0.07),
		"sight": _sat(blockers / scale * 0.15),
		"hazard": _sat(harm / 2.0), "wind": _sat(wind), "portals": _sat(portals * 2.0),
		"haste": _sat(haste), "fountain": _sat(fountain), "pull": _sat(pull), "knockback": _sat(knock),
		"concealment": _sat(forest_area / area * 8.0), "gates": _sat(gates * 0.5), "jump_pads": _sat(pads),
		"artillery": _sat(artillery), "ring": _sat(ring), "mud": _sat(mud),
		"openness": exp(-(occupied / area * 5.0 + blockers / scale * 0.08 + forest_area / area * 3.0)),
		"large": _sat(maxf(0.0, scale - 1.0) * 1.5), "small": _sat(maxf(0.0, 1.0 - scale) * 4.0),
		"elongated": _sat(maxf(0.0, aspect - 1.5) * 1.5), "approach": approach, "flank": flank, "split_spawns": split,
		"point_spread": point_spread, "point_distance": point_distance,
		"point_hazard": _sat(point_hazard), "point_push": _sat(point_push * 2.0),
		"control": 1.0 if arena.ruleset == "control" else 0.0}
	out.merge(DraftContextV2.geometry(arena))
	return out


static func _m(m: Dictionary, key: String) -> float:
	return float(m.get(key, 0.0))


static func map_fit(f: Dictionary, m: Dictionary) -> float:
	var reach: float = minf(1.0, float(f.range) / 240.0)
	var long_reach: float = minf(1.0, float(f.range) / 320.0)
	var v: float = _m(m, "walls") * (0.22 * float(f.wall) + 0.1 * float(f.area) + 0.06 * float(f.stationary) - 0.13 * float(f.projectile))\
	+ (1.0 - _m(m, "sight")) * 0.09 * reach\
	+ _m(m, "hazard") * (0.09 * float(f.mobility) + 0.06 * float(f.healing) - 0.12 * float(f.stationary))\
	+ _m(m, "portals") * (0.22 * float(f.portal) + 0.07 * float(f.dive)) + _m(m, "wind") * 0.04 * float(f.durability)\
	+ _m(m, "control") * (0.12 * float(f.mobility) + 0.10 * float(f.durability) + 0.06 * float(f.healing) + 0.07 * float(f.control) + 0.06 * float(f.ally_protection) + 0.04 * float(f.ally_healing) - 0.05 * float(f.fragile))
	# V1.5.3 gimmicks and geometry.
	v += _m(m, "haste") * (0.05 * float(f.dive) + 0.03 * float(f.mobility))
	v += _m(m, "fountain") * (0.04 * float(f.durability) - 0.03 * minf(1.0, float(f.healing)) + 0.02 * float(f.mobility))
	v += _m(m, "pull") * (0.07 * float(f.area) + 0.04 * float(f.control) - 0.04 * float(f.fragile))
	v += _m(m, "knockback") * (0.05 * float(f.mobility) - 0.05 * float(f.stationary))
	v += _m(m, "concealment") * (0.08 * float(f.dive) + 0.05 * float(f.burst) - 0.07 * long_reach)
	v += _m(m, "gates") * (0.05 * float(f.wall) + 0.04 * float(f.mobility) - 0.03 * float(f.stationary))
	v += _m(m, "jump_pads") * (0.06 * float(f.dive) + 0.04 * float(f.mobility))
	v += _m(m, "artillery") * (0.07 * float(f.mobility) + 0.03 * float(f.healing) - 0.08 * float(f.stationary))
	v += _m(m, "ring") * (0.06 * float(f.durability) + 0.05 * float(f.area) - 0.04 * long_reach)
	v += _m(m, "mud") * (0.06 * reach - 0.06 * float(f.dive))
	v += _m(m, "openness") * (0.05 * long_reach - 0.03 * float(f.dive))
	v += _m(m, "large") * (0.05 * float(f.mobility) + 0.03 * long_reach - 0.04 * float(f.stationary))
	v += _m(m, "small") * (0.05 * float(f.dive) + 0.04 * float(f.area))
	v += _m(m, "elongated") * 0.03 * long_reach + _m(m, "approach") * (0.03 * long_reach + 0.02 * float(f.mobility))
	v += _m(m, "flank") * (0.04 * float(f.dive) + 0.03 * float(f.mobility) - 0.03 * float(f.stationary))
	v += _m(m, "split_spawns") * 0.03 * float(f.durability)
	v += _m(m, "control") * (_m(m, "point_spread") * (0.08 * float(f.mobility) - 0.05 * float(f.stationary))
		+ _m(m, "point_distance") * (0.04 * float(f.mobility) + 0.02 * float(f.durability))
		+ _m(m, "point_hazard") * (0.07 * float(f.durability) + 0.05 * minf(1.0, float(f.healing)) - 0.07 * float(f.fragile) - 0.05 * float(f.stationary))
		+ _m(m, "point_push") * (0.06 * reach + 0.04 * float(f.mobility) - 0.06 * float(f.stationary)))
	v += _m(m, "fire_lanes") * 0.08 * long_reach
	v += _m(m, "choke") * (0.08 * float(f.area) + 0.05 * float(f.control) - 0.04 * float(f.projectile))
	v += _m(m, "route_stretch") * (0.05 * float(f.mobility) + 0.05 * float(f.portal) - 0.04 * float(f.stationary))
	v += _m(m, "control") * (_m(m, "point_shelter") * (0.06 * float(f.area) - 0.06 * long_reach)
		+ _m(m, "point_heal") * (0.05 * float(f.durability) - 0.035 * minf(1.0, float(f.healing))))
	v += _m(m, "heal_supply") * 0.03 * float(f.mobility)
	return v


static func directed_counter(a: Dictionary, b: Dictionary) -> float:
	return 0.32 * float(a.get("anti_heal_strength", a.anti_heal)) * float(b.healing) + 0.25 * float(a.projectile_answer) * float(b.projectile)\
	+ 0.15 * float(a.area) * float(b.summon) + 0.09 * float(a.control) * float(b.mobility)\
	+ 0.13 * float(a.dive) * (1.0 if b.ranged else 0.0) * (1.0 + float(b.fragile))\
	+ 0.08 * float(a.disengage) * (1.0 if b.melee else 0.0)\
	+ 0.08 * float(a.protection) * float(b.burst) + 0.07 * float(a.execute) * float(b.healing)\
	+ 0.15 * float(a.get("cleanse", 0.0)) * float(b.control)\
	+ 0.08 * float(a.get("retaliation", 0.0)) * float(b.control)\
	+ 0.08 * float(a.get("tenacity", 0.0)) * float(b.control)\
	+ 0.08 * float(a.get("charm_tenacity", 0.0)) * float(b.get("charm", 0.0))\
	+ 0.25 * float(a.get("basic_guard", 0.0)) * float(b.get("basic_fraction", 0.0))


static func _power(f: Dictionary) -> float:
	return log(maxf(0.1, float(f.damage) * float(f.durability))) * 0.24 + float(f.healing) * 0.09 + float(f.control) * 0.07


static func mechanics_matchup(a: Dictionary, b: Dictionary, m: Dictionary) -> float:
	return clampf(_power(a) - _power(b) + directed_counter(a, b) - directed_counter(b, a) + map_fit(a, m) - map_fit(b, m), -1.0, 1.0)


static func support_delivery(a: Dictionary, b: Dictionary) -> float:
	var drift: = maxf(0.0, float(b.move_speed) - float(a.move_speed)) * float(a.support_interval) if float(a.stationary) > 0.0 and b.melee else 0.0
	return float(a.support_reach) / (float(a.support_reach) + drift + absf(float(a.preferred_range) - float(b.preferred_range)))


static func pair_synergy(a: Dictionary, b: Dictionary) -> float:
	var v: = 0.09 * (float(a.ally_protection) * float(b.damage) + float(b.ally_protection) * float(a.damage))\
	+ 0.08 * (float(a.ally_healing) * float(b.durability) * support_delivery(a, b) + float(b.ally_healing) * float(a.durability) * support_delivery(b, a))\
	+ 0.09 * (float(a.control) * float(b.burst) + float(b.control) * float(a.burst))\
	+ 0.1 * minf(float(a.dive), float(b.dive)) + 0.09 * minf(float(a.stationary), float(b.stationary))\
	+ 0.05 * (float(a.portal) * (1.0 if b.melee else 0.0) + float(b.portal) * (1.0 if a.melee else 0.0))
	v -= 0.09 * maxf(0.0, float(a.ally_healing) + float(b.ally_healing) - 2.2)
	return v


static func composition(fs: Array) -> float:
	if fs.size() <= 1:
		return 0.0
	var nn: = float(fs.size())
	var damage: = 0.0
	var front: = 0.0
	var protection: = 0.0
	var fragile: = 0.0
	var heal: = 0.0
	for f in fs:
		damage += float(f.damage)
		front += clampf((float(f.durability) - 0.7) * 2.0, 0.0, 1.4) * (1.0 if f.melee else 0.45)
		protection += float(f.ally_protection) + float(f.control) * 0.45
		fragile += float(f.fragile) + (0.2 if f.ranged else 0.0)
		heal += float(f.ally_healing)
	return 0.17 * minf(1.5, front) + 0.12 * minf(1.5, heal) - 0.55 * maxf(0.0, 0.8 * nn - damage)\
	- 0.24 * maxf(0.0, fragile - front * 0.6 - protection) - 0.12 * maxf(0.0, heal - nn * 0.65)






func _prepare() -> void :
	ids = DB.ids().duplicate()
	ids.sort()
	n = ids.size()
	index.clear()
	feats.clear()
	for i in n:
		index[ids[i]] = i
		feats.append(kit_features(DB.char_def(ids[i])))
	var arena: = DB.arena(arena_id)
	var map_key: int = arena.get_instance_id()
	if not _map_cache.has(map_key):
		_map_cache[map_key] = map_features(arena)
	mapf = (_map_cache[map_key] as Dictionary).duplicate()
	mapf["control"] = 1.0 if ruleset == "control" else 0.0
	arena_name = arena.name
	var baseline: = {"walls": 0.0, "sight": 0.0, "hazard": 0.0, "portals": 0.0, "wind": 0.0}
	matrix.resize(n * n)
	pairs.resize(n * n)
	team_power.resize(n)
	hero_fit.resize(n)
	var base_fit: = PackedFloat64Array()
	base_fit.resize(n)
	for i in n:
		hero_fit[i] = map_fit(feats[i], mapf)
		base_fit[i] = map_fit(feats[i], baseline)
	var cal: Dictionary = _calibration()
	var duel: Dictionary = cal.get("duel", {})
	var team: Dictionary = cal.get("team_control" if ruleset == "control" else "team_elim", cal.get("team", {}))
	var map_team: Dictionary = (cal.get("map_team_control" if ruleset == "control" else "map_team_elim", {}) as Dictionary).get(arena_id, {}) if ruleset in ["elimination", "control"] else {}
	var map_duel: Dictionary = (cal.get("map_duel", {}) as Dictionary).get(arena_id, {}) if ruleset == "elimination" else {}
	for i in n:
		team_power[i] = float(team.get(ids[i], 0.0)) + float(map_team.get(ids[i], 0.0))
		for j in n:
			pairs[i * n + j] = pair_synergy(feats[i], feats[j]) if i != j else 0.0
			if i == j:
				matrix[i * n + j] = 0.0
				continue
			var mech: = clampf(_power(feats[i]) - _power(feats[j]) + directed_counter(feats[i], feats[j]) - directed_counter(feats[j], feats[i])
				+ hero_fit[i] - hero_fit[j], -1.0, 1.0)
			var a: String = ids[i]
			var b: String = ids[j]
			var key: = "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			if duel.has(key):
				var obs: = (float(duel[key]) + float(map_duel.get(key, 0.0))) * (1.0 if a < b else -1.0)

				var dep: = maxf(float(feats[i].ally_only), float(feats[j].ally_only)) if team_size > 1 else 0.0
				var m_adj: = (hero_fit[i] - hero_fit[j]) - (base_fit[i] - base_fit[j])
				# An elimination duel is weaker evidence for a respawning objective
				# battle. Matched-mode team priors and objective utility remain active.
				var obs_weight: float = 0.45 if ruleset == "control" else 0.78
				matrix[i * n + j] = obs * obs_weight * (1.0 - dep) + mech * (1.0 - obs_weight) + m_adj * 0.55
			else:
				matrix[i * n + j] = mech


static var _cal_cache: Dictionary = {}
static var _map_cache: Dictionary = {}


static func _calibration() -> Dictionary:
	if not _cal_cache.is_empty():
		return _cal_cache
	var path: = "res://scripts/data/draft_calibration.gd"
	if ResourceLoader.exists(path):
		var sc: GDScript = load(path)
		if sc:
			var consts: = sc.get_script_constant_map()
			var roster: Array = DB.ids()
			var legacy_team: Dictionary = _roster_team(consts.get("TEAM", {}), roster)
			_cal_cache = {"duel": _roster_duel(consts.get("DUEL", {}), roster), "team": legacy_team,
				"team_elim": _roster_team(consts.get("TEAM_ELIM", consts.get("TEAM", {})), roster),
				"team_control": _roster_team(consts.get("TEAM_CONTROL", consts.get("TEAM", {})), roster),
				"map_duel": _roster_maps(consts.get("MAP_DUEL", {}), roster, true),
				"map_team_elim": _roster_maps(consts.get("MAP_TEAM_ELIM", {}), roster, false),
				"map_team_control": _roster_maps(consts.get("MAP_TEAM_CONTROL", {}), roster, false),
				"map_team_elim_counts": _roster_maps(consts.get("MAP_TEAM_ELIM_COUNTS", {}), roster, false),
				"map_team_control_counts": _roster_maps(consts.get("MAP_TEAM_CONTROL_COUNTS", {}), roster, false),
				"sim_sha": consts.get("SIM_SHA", ""), "data_fingerprint": consts.get("DATA_FINGERPRINT", ""),
				"games": consts.get("GAMES", 0), "engine": consts.get("ENGINE", "")}
	if _cal_cache.is_empty():
		_cal_cache = {"duel": {}, "team": {}, "games": 0, "engine": ""}
	return _cal_cache


func calibration_games() -> int:
	return int(_calibration().get("games", 0))






func members(mask: int) -> PackedInt32Array:
	if _members_cache.has(mask):
		return _members_cache[mask]
	var out: = PackedInt32Array()
	for i in n:
		if mask & (1 << i):
			out.append(i)
	_members_cache[mask] = out
	return out


func mask_of(team: Array) -> int:
	var m: = 0
	for id in team:
		if index.has(id):
			m |= 1 << int(index[id])
	return m


func mode_composition(fs: Array) -> float:
	var base: float = composition(fs)
	if fs.is_empty():
		return base
	if fs.size() == 1:
		# An ally-only kit cannot deliver its advertised protection in a duel.
		base -= 0.34 * float(fs[0].ally_only)
	if ruleset != "control":
		var magic_damage: float = 0.0
		var physical_damage: float = 0.0
		var opening: float = 0.0
		var followup: float = 0.0
		for f: Dictionary in fs:
			magic_damage += float(f.damage) * float(f.magic)
			physical_damage += float(f.damage) * (1.0 - float(f.magic))
			opening += float(f.control)
			followup += float(f.burst)
		return base + 0.06 * minf(magic_damage, physical_damage) / fs.size() + 0.05 * minf(opening, followup) / fs.size()
	# A majority gives a scoring lead. Value separate objective groups plus an
	# escort/rotation reserve; do not assume every healer reaches all circles.
	return base * 0.65 + DraftContextV2.control_team(fs, mapf, pair_synergy)


func team_quality(mask: int) -> float:
	if _q_cache.has(mask):
		return _q_cache[mask]
	var ms: = members(mask)
	var fs: Array = []
	var fit: = 0.0
	var power: = 0.0
	for i in ms:
		fs.append(feats[i])
		fit += hero_fit[i]
		power += team_power[i]
	var pv: = 0.0
	for x in ms.size():
		for y in range(x + 1, ms.size()):
			pv += pairs[ms[x] * n + ms[y]]
	var cnt: = maxf(1.0, ms.size())
	var cohesion: float = 0.65
	if ruleset == "control":
		cohesion = 0.42 / (1.0 + float(mapf.get("rotation_distance", 0.0)) / 1200.0)
	var v: = mode_composition(fs) + pv / maxf(1.0, ms.size() - 1) * cohesion + fit / cnt * 0.35

	if team_size > 1:
		v += power * 0.55
	_q_cache[mask] = v
	return v


func value(ai: int, user: int) -> float:
	if ai == user:
		return 0.0
	var key: = ai * SHIFT + user
	if _v_cache.has(key):
		return _v_cache[key]
	cache_misses += 1
	var as_: = members(ai)
	var us: = members(user)
	var cross: = 0.0
	for i in as_:
		for j in us:
			cross += matrix[i * n + j]
	var cover_a: = 0.0
	for j in us:
		var best: = -1.0
		for i in as_:
			best = maxf(best, matrix[i * n + j])
		if not as_.is_empty():
			cover_a += best
	var cover_u: = 0.0
	for i in as_:
		var best2: = -1.0
		for j in us:
			best2 = maxf(best2, matrix[j * n + i])
		if not us.is_empty():
			cover_u += best2
	var duel_w: = 3.2 if team_size <= 1 else 1.9
	var v: = cross / maxf(1.0, as_.size() * us.size()) * duel_w + team_quality(ai) - team_quality(user)
	v += 0.22 * (cover_a / maxf(1.0, us.size()) - cover_u / maxf(1.0, as_.size()))
	v -= 1.6 * (_exposure(as_, us) - _exposure(us, as_))
	_v_cache[key] = v
	_v_cache[user * SHIFT + ai] = - v
	return v



func _exposure(own: PackedInt32Array, foe: PackedInt32Array) -> float:
	var shooters: Array = []
	for j in foe:
		if feats[j].ranged:
			shooters.append(j)
	if own.size() <= 1 or shooters.size() < 2:
		return 0.0
	var total: = 0.0
	for i in own:
		total += float(feats[i].raw_damage)
	var out: = 0.0
	var screens: float = 0.0
	for i in own:
		screens += float(feats[i].projectile_answer) + float(feats[i].ally_protection) * 0.3
	# Corridors with interrupted sight lines permit staging behind cover. This
	# discount is bounded: it does not assume a wall makes the whole team safe.
	var firing: float = 0.35 + 0.65 * float(mapf.get("fire_lanes", 1.0))
	firing *= 1.0 - 0.25 * _m(mapf, "concealment")
	for i in own:
		var f: Dictionary = feats[i]
		if not f.melee:
			continue
		var crossing: = 0.0
		for j in shooters:
			var e: Dictionary = feats[j]
			crossing += float(e.raw_damage) * 0.32 * maxf(0.0, float(e.range) - float(f.range)) / maxf(1.0, float(f.move_speed))
		var entry: float = 1.0 / (1.0 + 0.65 * float(f.mobility) + 0.25 * float(f.protection) + 0.20 * screens)
		out += crossing * firing * entry / float(f.max_health) * float(f.raw_damage) / maxf(1.0, total)
	return out






func legal(ai: int, user: int) -> PackedInt32Array:
	var used: = ai | user
	var out: = PackedInt32Array()
	for i in n:
		if not (used & (1 << i)):
			out.append(i)
	return out


func ranked(ai: int, user: int, turn: int) -> Array:
	var rows: Array = []
	for i in legal(ai, user):
		var v: = value(ai | (1 << i), user) if turn == 1 else value(ai, user | (1 << i))
		rows.append([i, v])
	rows.sort_custom( func(a, b):
		var da: = float(a[1]) * turn
		var db: = float(b[1]) * turn
		if absf(da - db) > 1e-09:
			return da > db
		return String(ids[int(a[0])]) < String(ids[int(b[0])]))
	return rows


func begin(user_team: Array, ai_team: Array) -> void:
	cancel()
	evals = 0
	nodes = 0
	cache_misses = 0
	last_decision = {}
	_v_cache.clear()
	_q_cache.clear()
	_members_cache.clear()
	_job = preload("res://scripts/ai/draft_search.gd").new(self, user_team, ai_team)


func advance(max_work: int = 256) -> bool:
	return true if _job == null else _job.advance(max_work)


func advance_until(deadline_usec: int) -> bool:
	return true if _job == null else _job.advance_until(deadline_usec)


func progress() -> Dictionary:
	return {"done": true, "cancelled": false, "phase": "idle", "fraction": 0.0, "evals": 0, "budget": budget, "completed_depth": 0, "candidates": 0, "covered_candidates": 0} if _job == null else _job.progress()


func cancel() -> void:
	if _job and not bool(_job.done):
		_job.cancel()
	last_decision = {}


func result() -> Dictionary:
	return last_decision


func decide(user_team: Array, ai_team: Array) -> Dictionary:
	begin(user_team, ai_team)
	while not advance(1024):
		pass
	return result()


func _assemble_decision(user_team: Array, ai_team: Array, candidates: Array, metrics: Dictionary) -> Dictionary:
	var am: int = mask_of(ai_team)
	var chosen: Dictionary = candidates[0]
	var ci: = int(index[chosen.id])
	var f: Dictionary = feats[ci]
	var reasons: Array = []

	var best_counter: = {"id": "", "v": - INF}
	for e in user_team:
		var v: = matrix[ci * n + int(index[e])]
		if v > float(best_counter.v):
			best_counter = {"id": e, "v": v}
	if float(best_counter.v) > 0.12:
		reasons.append("%s 상성 대응 (%+.2f)" % [DB.char_def(best_counter.id).name, float(best_counter.v)])
	var user_heal: = false
	var user_proj: = false
	var user_summon: = false
	for e in user_team:
		var ef: Dictionary = feats[int(index[e])]
		user_heal = user_heal or float(ef.healing) > 0.3
		user_proj = user_proj or float(ef.projectile) > 0.5
		user_summon = user_summon or float(ef.summon) > 0.0
	if float(f.anti_heal) > 0.0 and user_heal:
		reasons.append("상대 회복 차단")
	if float(f.projectile_answer) > 0.0 and user_proj:
		reasons.append("상대 투사체에 방어·반사 수단 확보")
	if float(f.area) > 0.3 and user_summon:
		reasons.append("소환물과 밀집 진형에 광역 대응")
	var team_gain: = team_quality(am | (1 << ci)) - team_quality(am)
	if not ai_team.is_empty() and team_gain > 0.15:
		reasons.append("아군의 제어·화력·생존 연계 보완")
	if team_size > 1 and team_power[ci] > 0.15:
		reasons.append("자기 대전 팀전 기여도 상위")
	if arena_id != "classic" and absf(map_fit(f, mapf)) > 0.04:
		reasons.append("%s의 지형·위험 구역 반영" % arena_name)
	if str(chosen.reply) != "":
		reasons.append("%s의 응수를 포함해 %d수까지 같은 깊이로 비교" % [DB.char_def(chosen.reply).name, int(metrics.completed_depth)])
	if int(metrics.completed_depth) >= 1 and not bool(metrics.search_complete):
		reasons.append("탐색 뒤 남은 슬롯은 합법적인 예상 픽으로 채워 완성 조합을 평가")
	elif bool(metrics.policy_completion.prefix_fallback):
		reasons.append("탐색 예산이 부족하여 모든 후보의 현재 조합 평가만 비교")
	if ruleset == "control":
		reasons.append("%d개 거점의 과반 확보·증원 이동·점령 방해 수단을 비교" % int(mapf.get("point_count", 3)))
		if _m(mapf, "heal_supply") > 0.0:
			reasons.append("치유 구역의 재사용 대기시간과 거점 이탈 거리 반영")
	elif bool(f.melee) and _m(mapf, "fire_lanes") < 0.65:
		reasons.append("엄폐로 끊기는 사격 통로를 고려해 근접 접근 위험 보정")
	if float(f.get("cleanse", 0.0)) > 0.0:
		for e in user_team:
			if float(feats[int(index[e])].control) > 0.4:
				reasons.append("상대 군중 제어에 대한 정화·대응 능력 반영")
				break
	if float(metrics.opponent_model.history_samples) > 0.0:
		reasons.append("이전 픽 선호와 강한 카운터 응수를 함께 고려")
	if int(metrics.rollout.games) > 0 and int(metrics.rollout.get("sides_per_finalist", 2)) == 1:
		reasons.append("최종 후보 2개를 실제 전투 엔진에서 같은 진영·같은 조건으로 60초씩 점검")
	elif int(metrics.rollout.games) > 0:
		reasons.append("최종 후보 2개를 실제 전투 엔진에서 진영을 바꿔 짧게 점검")
	elif str(metrics.rollout.get("skipped", "")) == "gap":
		reasons.append("최종 후보의 평가 차이가 커서 실제 엔진 점검 생략")
	if reasons.is_empty():
		reasons.append("남은 후보 중 상대 조합에 대한 평가가 가장 높음")
	var alts: Array = []
	var compared: int = mini(2 if int(metrics.rollout.games) > 0 else 4, candidates.size())
	for k in range(1, compared):
		alts.append({"id": candidates[k].id, "name": DB.char_def(candidates[k].id).name, "score": candidates[k].score,
			"score_basis": "search_and_engine" if bool(candidates[k].get("engine_finalist", false)) else "search",
			"search_score": candidates[k].get("search_score", candidates[k].score), "rollout_value": candidates[k].get("rollout_value", 0.0)})
	last_decision = {"id": chosen.id, "name": DB.char_def(chosen.id).name, "score": chosen.score, "reasons": reasons, 
		"score_basis": "search_and_engine" if bool(chosen.get("engine_finalist", false)) else "search",
		"search_score": chosen.get("search_score", chosen.score), "rollout_value": chosen.get("rollout_value", 0.0),
		"alternatives": alts, "forecast": chosen.line, "reply": chosen.reply, "version": VERSION, 
		"search": metrics, 
		"calibration_games": calibration_games(),
		"context": {"ruleset": ruleset, "arena_id": arena_id, "features": mapf.duplicate(),
			"data_fingerprint": _calibration().get("data_fingerprint", ""),
			"team_map_samples": ((_calibration().get("map_team_control_counts" if ruleset == "control" else "map_team_elim_counts", {}) as Dictionary).get(arena_id, {}) as Dictionary).get(chosen.id, 0) if ruleset in ["elimination", "control"] else 0}}
	return last_decision



func evaluate_state(user_team: Array, ai_team: Array) -> float:
	return value(mask_of(ai_team), mask_of(user_team))


# --- V2 calibration (Codex) ---
static func _roster_team(raw: Dictionary, roster: Array) -> Dictionary:
	var out: Dictionary = {}
	for id in roster:
		if raw.has(id): out[id] = raw[id]
	return out


static func _roster_duel(raw: Dictionary, roster: Array) -> Dictionary:
	var out: Dictionary = {}
	var ids_: Array = roster.duplicate()
	ids_.sort()
	for i in ids_.size():
		for j in range(i + 1, ids_.size()):
			var key: String = "%s|%s" % [ids_[i], ids_[j]]
			if raw.has(key): out[key] = raw[key]
	return out


static func _roster_maps(raw: Dictionary, roster: Array, duel: bool) -> Dictionary:
	var out: Dictionary = {}
	for arena in raw:
		if raw[arena] is Dictionary:
			out[arena] = _roster_duel(raw[arena], roster) if duel else _roster_team(raw[arena], roster)
	return out
