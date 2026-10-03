class_name Defs
extends RefCounted


const HARD_CC: = [&"stun", &"airborne", &"suppression", &"sleep", &"root", &"charm", &"taunt"]
const CC_TYPES: = [&"slow", &"root", &"stun", &"silence", &"disarm", &"taunt", &"fear", &"airborne", &"grounded", &"sleep", &"suppression", &"charm", &"control"]


class AbilityDef:
	extends RefCounted
	var id: String = ""
	var char_id: String = ""
	var slot: int = 1
	var index: int = 0
	var name: String = ""
	var description: String = ""
	var geometry: String = ""
	var timing: String = ""
	var cooldown: float = 7.0
	var cast_time: float = 0.25
	var recovery: float = 0.18
	@warning_ignore("shadowed_global_identifier")
	var range: float = 120.0
	var target: String = "enemy"
	var delivery: String = "direct"
	var shape: String = "single"
	var radius: float = 22.0
	var width: float = 24.0
	var angle: float = 0.9
	var speed: float = 330.0
	var count: int = 1
	var spread: float = 0.0
	var pierce: int = 0
	var bounces: int = 0
	var homing: bool = false
	var return_to_source: bool = false
	var max_distance: float = -1.0
	var effects: Array = []
	var condition: Dictionary = {}
	var ai: Dictionary = {}
	var tags: PackedStringArray = PackedStringArray()
	var color: Color = Color.WHITE
	var pattern: String = ""
	var vfx_glyph: String = ""
	var action: String = ""
	var flags: Dictionary = {}

	var is_mobility: bool = false
	var hostile: bool = true
	var cc_types: Array = []
	var virtual: bool = false
	var virtual_kind: String = ""
	var donor_idx: int = -1

	func flag(key: String, default_value = null):
		return flags.get(key, default_value)

	func has_tag(t: String) -> bool:
		return tags.has(t)

	func duplicate_def() -> AbilityDef:
		var a: = AbilityDef.new()
		for p in get_property_list():
			var n: String = p.name
			if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				var v = get(n)
				if v is Array or v is Dictionary:
					a.set(n, v.duplicate(true))
				else:
					a.set(n, v)
		return a


class CharDef:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var glyph: String = "·"
	var accent: Color = Color.WHITE
	var role: String = "DAMAGE"
	var tags: PackedStringArray = PackedStringArray()
	var summary: String = ""
	var stats: Dictionary = {}
	var preferred_range: float = 60.0
	var behavior: Dictionary = {}
	var doctrine: Dictionary = {}
	var nexus: Dictionary = {}
	var passives: Array = []
	var abilities: Array = []
	var rules: Dictionary = {}
	var arming_time: float = 0.5
	var is_entity: bool = false

	func stat(key: String) -> float:
		return float(stats.get(key, 0.0))

	func rule(t: String) -> Dictionary:
		return rules.get(t, {})

	func has_rule(t: String) -> bool:
		return rules.has(t)

	func is_melee() -> bool:
		return stat("attackRange") <= 100.0


static func ability_from(d: Dictionary, char_id: String, accent: Color) -> AbilityDef:
	var a: = AbilityDef.new()
	a.slot = int(d.get("slot", 1))
	a.index = a.slot - 1
	a.char_id = char_id
	a.id = "%s_%d" % [char_id, a.slot]
	a.name = str(d.get("name", ""))
	a.description = str(d.get("description", ""))
	a.geometry = str(d.get("geometry", ""))
	a.timing = str(d.get("timing", ""))
	a.cooldown = float(d.get("cooldown", 7.0))
	a.cast_time = float(d.get("castTime", 0.25))
	a.recovery = float(d.get("recovery", 0.18))
	a.range = float(d.get("range", 120.0))
	a.target = str(d.get("target", "enemy"))
	a.delivery = str(d.get("delivery", "direct"))
	a.shape = str(d.get("shape", "single"))
	a.radius = float(d.get("radius", 22.0))
	a.width = float(d.get("width", 24.0))
	a.angle = float(d.get("angle", 0.9))
	a.speed = float(d.get("speed", 330.0))
	a.count = int(d.get("projectileCount", 1))
	a.spread = float(d.get("spread", 0.0))
	a.pierce = int(d.get("pierce", 0))
	a.bounces = int(d.get("bounces", 0))
	a.homing = bool(d.get("homing", false))
	a.return_to_source = bool(d.get("returnToSource", false))
	a.max_distance = float(d.get("maxDistance", -1.0)) if d.get("maxDistance") != null else -1.0
	a.effects = (d.get("effects", []) as Array).duplicate(true)
	var cond = d.get("condition")
	a.condition = cond if cond is Dictionary else {}
	a.ai = d.get("ai", {})
	a.tags = PackedStringArray(d.get("tags", []))
	var vfx: Dictionary = d.get("vfx", {})
	a.color = Color(str(vfx.get("color", accent.to_html())))
	a.pattern = str(vfx.get("pattern", ""))
	a.vfx_glyph = str(vfx.get("glyph", str(a.slot)))
	a.action = str(d.get("action", ""))
	a.flags = d.get("flags", {})
	a.is_mobility = a.tags.has("MOBILITY")
	a.hostile = a.target in ["enemy", "position"] or (a.target == "self" and _has_hostile_effect(a.effects))
	a.cc_types = []
	_collect_cc(a.effects, a.cc_types)
	return a


static func _has_hostile_effect(effects: Array) -> bool:
	for e in effects:
		var t: = str(e.get("type", ""))
		if t == "damage" or (t == "status" and str(e.get("status", "")) in ["stun", "silence", "root", "airborne", "suppression", "slow"]):
			return true
		if e.has("effects") and _has_hostile_effect(e.effects):
			return true
	return false


static func _collect_cc(effects: Array, out: Array) -> void :
	for e in effects:
		var t: = str(e.get("type", ""))
		if t == "status":
			var s: = StringName(str(e.get("status", "")))
			if s in CC_TYPES and s != &"slow" and not out.has(s):
				out.append(s)
		if e.has("effects"):
			_collect_cc(e.effects, out)


static func char_from(d: Dictionary) -> CharDef:
	var c: = CharDef.new()
	c.id = str(d.id)
	c.name = str(d.name)
	c.glyph = str(d.glyph)
	c.accent = Color(str(d.accent))
	c.role = str(d.role)
	c.tags = PackedStringArray(d.get("tags", []))
	c.summary = str(d.get("summary", ""))
	c.stats = {}
	var st: Dictionary = d.get("stats", {})
	for k in st:
		c.stats[k] = float(st[k])
	c.preferred_range = float(d.get("preferredRange", c.stat("attackRange")))
	c.behavior = d.get("behavior", {})
	c.doctrine = d.get("doctrine", {})
	c.nexus = d.get("nexus", {})
	c.passives = d.get("passives", [])
	c.arming_time = float(d.get("armingTime", 0.5))
	for p in c.passives:
		for r in p.get("rules", []):
			c.rules[str(r.get("type", ""))] = r
	for ad in d.get("abilities", []):
		c.abilities.append(ability_from(ad, c.id, c.accent))
	return c



static func entity_def(kind: String, owner: CharDef, hp: float, radius: float, armor: float) -> CharDef:
	var c: = CharDef.new()
	c.is_entity = true
	c.id = "entity_" + kind
	c.name = {"bed": "짝의 침상", "snake": "혈사", "brood": "새끼", "parasite": "기생충", "tree": "수호수", "turret": "자동 포탑", "flower": "봄꽃",
		"cerberus": "케르베로스", "shade": "망자", "fuel_tank": "연료탱크", "chariot": "쌍마 전차"}.get(kind, kind)
	c.glyph = {"bed": "床", "snake": "蛇", "brood": "幼", "parasite": "寄", "tree": "樹", "turret": "砲", "flower": "✿",
		"cerberus": "犬", "shade": "亡", "fuel_tank": "油", "chariot": "車"}.get(kind, "·")
	c.accent = owner.accent
	c.role = "FRONTLINE"
	c.stats = {"maxHealth": hp, "attackDamage": 0.0, "abilityPower": 0.0, "armor": armor, "magicResistance": armor, 
		"moveSpeed": 0.0, "attackSpeed": 0.0, "attackRange": 0.0, "critChance": 0.0, "critMultiplier": 1.0, 
		"tenacity": 0.0, "bodyRadius": radius}
	c.behavior = owner.behavior
	return c
