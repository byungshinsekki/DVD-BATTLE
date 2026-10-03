class_name SkillPreviewScenario
extends RefCounted

# These are controlled training inputs, not alternative combat implementations.
# Every cast, projectile, contact, buff and passive resolves in BattleSim.
class PreviewController:
	extends TeamController
	func decide(u: BUnit) -> void:
		u.next_decision_at = sim.time + 1.0
	func steer(u: BUnit) -> Vector2:
		if str(u.command.get("kind", "")) != "move": return Vector2.ZERO
		var delta: Vector2 = u.command.get("pos", u.pos) - u.pos
		u.command["arrive"] = delta.length()
		return delta.normalized() * minf(1.0, delta.length() / 18.0) if delta.length() > 2.0 else Vector2.ZERO

## V2 hades concealment previews: brush patches of the private training arena
## (S1 starts inside the brush, Kynee walks into it). Enemies stay outside.
const BRUSH_SUMMON: = [{"x": 500, "y": 396, "radius": 74, "patch": 0}, {"x": 452, "y": 352, "radius": 50, "patch": 0}]
const BRUSH_REGEN: = [{"x": 392, "y": 300, "radius": 70, "patch": 0}, {"x": 352, "y": 340, "radius": 46, "patch": 0}]
const BRUSH_REGEN_CENTER: = Vector2(386, 306)

var sim: BattleSim
var actor: BUnit
var ally: BUnit
var target: BUnit
var secondary: BUnit
var char_id: String
var entry: Dictionary = {}
var instructions: String = ""
var elapsed: float = 0.0
var duration: float = 12.0
var focus_rect: Rect2 = Rect2(300, 180, 800, 440)
var cast_started: bool = false
var finished: bool = false
var events: Array[Dictionary] = []
var metrics: Dictionary = {}
var _jobs: Array = []
## Repeated basic attacks {u, victim (BUnit or Callable -> BUnit), from, to}.
var _attacks: Array = []
var _main_due: float = 0.8
var _next_attempt: float = 0.0
var _path: Array[Vector2] = []
var _path_index: int = 0
var _virtual_done: bool = false
var _reflect_started: bool = false
var _ability: Defs.AbilityDef
var _entry_id: String


static func entries(id: String) -> Array:
	DB.ensure_loaded()
	var d: Defs.CharDef = DB.char_def(id)
	var out: Array = []
	if d == null: return out
	for i in d.abilities.size():
		var a: Defs.AbilityDef = d.abilities[i]
		out.append({"id": "active:%d" % i, "kind": "active", "index": i,
			"label": "S%d · %s" % [a.slot, a.name], "description": a.description,
			"conditions": _conditions(d, a)})
	for i in d.passives.size():
		var p: Dictionary = d.passives[i]
		out.append({"id": "passive:%d" % i, "kind": "passive", "index": i,
			"label": "패시브 %d · %s" % [i + 1, str(p.get("name", ""))], "description": str(p.get("description", d.summary)),
			"conditions": "발동에 필요한 이동·공격·피해·치유 또는 대기 시간을 훈련 장면에서 제공합니다."})
	return out


static func _conditions(d: Defs.CharDef, a: Defs.AbilityDef) -> String:
	var details: Array[String] = ["적과 아군은 지정된 훈련 위치에서 시작합니다. 실제 전투의 수치·시전·충돌·쿨다운을 사용합니다."]
	if a.condition.has("selfResource"):
		var resource_key: String = str(a.condition.selfResource.key)
		var resource_label: String = {"healBank": "비축 치유량", "shards": "차원 조각", "rage": "분노", "fish": "물고기", "fuel": "연료"}.get(resource_key, resource_key)
		if resource_key == "fuel": details.append("시전에 필요한 연료를 미리 %d 채웁니다." % int(_resource_preset(a)))
		else: details.append("시전 조건인 %s 자원을 미리 준비합니다." % resource_label)
	if a.condition.has("targetStatus"): details.append("대상에게 시전자 소유의 %s 상태를 준비합니다." % DB.status_label(str(a.condition.targetStatus)))
	if a.condition.get("targetIsCC", false): details.append("대상에게 선행 군중제어를 준비합니다.")
	if a.condition.get("concealed", false): details.append("시전자를 수풀(암흑시야) 안에, 적을 수풀 밖에 둡니다.")
	if a.condition.has("ccSourceWithin"): details.append("대상이 먼저 시전자에게 기절을 겁니다. 이 대상에 대한 시전 기회는 제어를 건 뒤 %s초 동안 유지됩니다." % CodexData.num(float(a.condition.ccSourceWithin)))
	if a.condition.get("nearWall", false): details.append("시전자를 실제 벽 가까이에 배치합니다.")
	if a.action in ["upgrade", "detonate"]: details.append("먼저 실제 포탑 설치를 시전합니다.")
	if a.action in ["rootGarden", "thornGarden"]: details.append("먼저 실제 이동으로 씨앗 경로를 닫아 정원을 만듭니다.")
	if a.action == "portalArming": details.append("먼저 쌍문을 설치하고 아군 탄환을 입구로 발사합니다.")
	if a.action in ["rift"] or d.id == "baseball": details.append("상대의 실제 투사체를 발사해 방어 판정을 보여줍니다.")
	return " ".join(details)


## Preset for a selfResource condition: the generic training amounts, raised to
## the condition minimum (war_machine S4 needs fuel 7) and to a full charge of a
## charged cast paid with that resource (S2: 6 missiles).
static func _resource_preset(a: Defs.AbilityDef) -> float:
	var key: String = str(a.condition.selfResource.key)
	var need: float = float(a.condition.selfResource.get("min", 1))
	var charge: Dictionary = a.flag("originCharge", {})
	if not charge.is_empty() and str(charge.get("resource", "")) == key: need = maxf(need, float(charge.get("max", need)))
	return maxf(need, 400.0 if key == "healBank" else (30.0 if key == "shards" else 4.0))


## V2 hades: the concealment entries (S1 condition, Kynee regen) use brush.
static func _brush_for(d: Defs.CharDef, kind: String, index: int) -> Array:
	if d == null: return []
	if kind == "active":
		return BRUSH_SUMMON if index < d.abilities.size() and bool(d.abilities[index].condition.get("concealed", false)) else []
	var rules: Array = d.passives[index].get("rules", []) if index < d.passives.size() else []
	return BRUSH_REGEN if not rules.is_empty() and str(rules[0].get("type", "")) == "concealed_regen" else []


func _init(id: String, selection: String = "active:0") -> void:
	char_id = id
	_entry_id = selection
	restart()


func restart() -> void:
	dispose()
	focus_rect = Rect2(300, 180, 800, 440)
	entry = {}
	for candidate in entries(char_id):
		if str(candidate.id) == _entry_id: entry = candidate.duplicate(true)
	if entry.is_empty():
		finished = true
		instructions = "미리보기 항목을 찾을 수 없습니다."
		return
	elapsed = 0.0
	duration = 14.5 if char_id == "hermes" and entry.kind == "passive" and int(entry.index) == 0 else 12.0
	# V2 war_machine fuel tank: burst, 10 s of overdrive and the tank's return.
	if char_id == "war_machine" and entry.kind == "passive": duration = 15.0
	finished = false
	cast_started = false
	_virtual_done = false
	_reflect_started = false
	_path_index = 0
	_main_due = 0.8
	_next_attempt = 0.0
	metrics = {"damage": 0.0, "healing": 0.0, "shielding": 0.0, "actor_distance": 0.0,
		"events": {}, "resources": {}, "buffs": {}, "statuses": {}, "max_radius": 0.0, "min_radius": INF,
		"max_ms": 0.0, "max_ap": 0.0, "max_coefficient": 0.0, "max_turret_level": 0, "max_hp": 0.0, "entities": {}}
	var enemy_id: String = "hive_mind" if char_id == "politician" and entry.kind == "passive" and int(entry.index) == 1 else "archer"
	sim = BattleSim.new({"blue": [char_id, "sniper" if char_id == "dimensionalist" else "mage"], "red": [enemy_id, "swordsman", "giant"], "arena_id": "classic", "seed": 140014, "max_time": 60.0})
	# Arena.from_data creates a private arena; the shared DB arena is untouched.
	var arena_data: Dictionary = {"id": "skill_preview", "name": "스킬 훈련장", "width": 1408, "height": 792,
		"bounds": {"minX": 70, "maxX": 1338, "minY": 70, "maxY": 722}, "obstacles": [], "hazards": []}
	var brush: Array = _brush_for(DB.char_def(char_id), str(entry.kind), int(entry.index))
	if not brush.is_empty(): arena_data["forests"] = brush.duplicate(true)
	sim.arena = Arena.from_data(arena_data)
	sim.collect_frame_events = true
	sim.controllers = [PreviewController.new(sim, 0), PreviewController.new(sim, 1)]
	actor = sim.heroes[0]
	ally = sim.heroes[1]
	target = sim.heroes[2]
	secondary = sim.heroes[3]
	_place(actor, Vector2(500, 396))
	_place(ally, Vector2(500, 470))
	_place(target, Vector2(650, 396))
	_place(secondary, Vector2(670, 475))
	_place(sim.heroes[4], Vector2(1210, 660))
	ally.hp *= 0.45
	actor.hp *= 0.7
	instructions = str(entry.conditions)
	if entry.kind == "active":
		_ability = actor.def.abilities[int(entry.index)]
		_prepare_active()
	else:
		_ability = null
		_prepare_passive()
	sim.start()
	_sample()


func dispose() -> void:
	_jobs.clear()
	_attacks.clear()
	_path.clear()
	events.clear()
	if sim: sim.dispose()
	sim = null
	actor = null
	ally = null
	target = null
	secondary = null
	_ability = null
	finished = true


func _place(u: BUnit, position: Vector2) -> void:
	u.pos = sim.arena.resolve_circle(position, sim.radius(u))
	u.prev_pos = u.pos
	u.vel = Vector2.ZERO
	u.facing = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
	u.command = {}


func _at(at: float, callback: Callable) -> void:
	_jobs.append({"at": at, "call": callback, "done": false})


func _move(u: BUnit, to: Vector2) -> void:
	u.command = {"kind": "move", "pos": to}


func _cast(u: BUnit, slot: int, victim: BUnit = null, point: Vector2 = Vector2.INF, extra: Dictionary = {}) -> bool:
	if not u.alive: return false
	var abilities: Array = sim.ability_list(u)
	if slot < 0 or slot >= abilities.size(): return false
	var a: Defs.AbilityDef = abilities[slot]
	var t: BUnit = victim
	if a.target == "self": t = u
	var aim: Vector2 = point if point.is_finite() else (t.pos if t else u.pos + Vector2(100, 0))
	return sim.start_ability(u, slot, t, aim, {"extra": extra})


func _basic(u: BUnit, victim: BUnit) -> void:
	sim.start_basic(u, victim)


## Keeps u attacking victim (a BUnit, or a Callable returning one) with real
## basic attacks whenever its attack is ready inside [from, to). With chase, u
## walks after a victim that leaves its attack range.
func _attack(u: BUnit, victim: Variant, from: float, to: float, chase: bool = false) -> void:
	_attacks.append({"u": u, "victim": victim, "from": from, "to": to, "chase": chase})


func _run_attacks() -> void:
	for job in _attacks:
		if sim.time + 0.000001 < float(job.from) or sim.time + 0.000001 >= float(job.to): continue
		var u: BUnit = job.u
		var victim: BUnit = (job.victim as Callable).call() if job.victim is Callable else job.victim
		if not u.alive or victim == null or not victim.alive: continue
		if bool(job.chase):
			var reach: float = sim.stat(u, &"attackRange") + sim.radius(u) + sim.radius(victim)
			if u.pos.distance_to(victim.pos) > reach - 4.0:
				_move(u, victim.pos)
				continue
			u.command = {}
		if u.action == null: sim.start_basic(u, victim)


func _garden_walk() -> void:
	_place(actor, Vector2(470, 300))
	_place(ally, Vector2(520, 370))
	_place(target, Vector2(550, 390))
	_place(secondary, Vector2(640, 490))
	_path.assign([Vector2(600, 300), Vector2(600, 440), Vector2(470, 440), Vector2(470, 300), Vector2(490, 300)])
	instructions += " 이동 경로가 닫히면 정원이 생기고 내부의 부상 아군이 회복합니다."


func _portals() -> void:
	_cast(actor, 1, ally, actor.pos + Vector2(245, 0), {"portal_a": actor.pos + Vector2(60, 0), "portal_b": actor.pos + Vector2(245, 0)})


func _prepare_active() -> void:
	var a: Defs.AbilityDef = _ability
	var distance: float = clampf(a.range * 0.65, 60.0, 230.0) if a.range > 0.0 else 65.0
	if a.action == "whip": distance = 190.0
	_place(target, actor.pos + Vector2(distance, 0))
	_place(secondary, actor.pos + Vector2(distance + 25, 55))
	if a.target == "ally": _place(ally, actor.pos + Vector2(minf(a.range * 0.6, 155.0), 65))
	if a.condition.has("selfResource"):
		var key: String = str(a.condition.selfResource.key)
		actor.resources[key] = _resource_preset(a)
		if key == "fish":
			actor.ks.fish = [{"id": sim.next_id(), "type": "attack"}]
			actor.resources[key] = 1.0
	if a.condition.has("targetStatus"):
		var status: String = str(a.condition.targetStatus)
		if status == "pain": sim.warfare.add_pain(actor, target, int(a.condition.get("minPain", 3)), {})
		elif status == "imprisoned":
			_place(target, actor.pos + Vector2(85, 0))
			_at(0.05, func(): _cast(actor, 2, target))
			_main_due = 0.9
		elif status == "control": sim.apply_status(actor, target, {"status": status, "duration": 10.0})
		else: sim.apply_mark(actor, target, {"status": status, "duration": 10.0, "stacks": 3, "maxStacks": 6})
	if a.condition.get("targetIsCC", false): sim.apply_status(actor, target, {"status": "root", "duration": 3.0})
	if a.condition.get("nearWall", false):
		_place(actor, Vector2(70 + sim.radius(actor) + 1.0, 340))
		_place(target, actor.pos + Vector2(130, 20))
		focus_rect = Rect2(60, 180, 900, 470)
		_at(1.0, func(): _move(actor, actor.pos + Vector2(0, 200)))
	match a.action:
		"rootGarden", "thornGarden": _garden_walk()
		"upgrade", "detonate":
			_at(0.05, func(): _cast(actor, 0, null, actor.pos + Vector2(70, 0)))
			_main_due = 1.0
			if a.action == "detonate":
				_place(target, actor.pos + Vector2(130, 0))
				_place(secondary, actor.pos + Vector2(145, 55))
		"portalArming":
			_at(0.05, _portals)
			_place(target, actor.pos + Vector2(300, 0))
			_place(ally, actor.pos + Vector2(-15, 0))
			_main_due = 0.85
			_at(1.5, func(): _basic(ally, target))
		"portalPair": _at(1.5, func(): _move(actor, Vector2(560, 396)))
		"prime": _at(1.5, func(): _basic(actor, target))
		"cloak": _at(1.6, func(): _cast(actor, 0, actor, actor.pos))
		"rift":
			_place(target, actor.pos + Vector2(220, 0))
			_at(1.4, func(): _basic(target, actor))
		"healingMist", "plantTree", "plantFlowers", "bed": _place(ally, actor.pos + Vector2(80, 30))
	if char_id == "archer" and int(entry.index) == 2:
		target.hp = sim.max_hp(target) * 0.17
		instructions += " 처형 조건을 보여주기 위해 대상 HP를 17%로 준비합니다."
	if char_id == "werewolf" and int(entry.index) == 0:
		target.hp = sim.max_hp(target) * 0.3
		_at(1.3, func(): _move(actor, target.pos))
	if char_id == "baseball":
		_at(1.4, func(): _basic(target, actor))
		if int(entry.index) == 1:
			_at(6.3, func(): _basic(target, actor))
			instructions += " 헬멧 유지 중과 만료 후 동일 상대의 투사체 피해를 비교합니다."
	if char_id == "nitro" and int(entry.index) == 2:
		_place(target, actor.pos + Vector2(65, 0))
		_at(1.2, func(): _move(actor, target.pos))
	_prepare_v2_active(int(entry.index))


# V2 heroes: each preview builds the situation its mechanic needs (concealment,
# fuel, a target near death, an earlier CC on the caster, debuffed allies,
# attacks from the front and from behind); the simulation resolves the rest.
# These prerequisites are ready by 1.2 s (tests/ai_audit_152 plans from them).
func _prepare_v2_active(i: int) -> void:
	var giant: BUnit = sim.heroes[4]
	match char_id:
		"hades":
			if i == 0:
				_place(ally, actor.pos + Vector2(-70, 80))
				_place(target, actor.pos + Vector2(270, -10))
				_place(secondary, actor.pos + Vector2(290, 60))
				_at(1.5, func(): _move(target, actor.pos + Vector2(44, -6)))
				_at(1.7, func(): _move(secondary, actor.pos + Vector2(36, 40)))
				instructions += " 소환 뒤 다가온 적을 망자가 제자리에서 뭅니다."
			elif i == 1:
				target.hp = sim.max_hp(target) * 0.22
				secondary.hp = sim.max_hp(secondary) * 0.6
				_at(2.0, func(): sim.apply_heal(target, target, {"base": 250.0}); sim.apply_heal(secondary, secondary, {"base": 250.0}))
				instructions += " 대상 체력을 22%로 준비해 타격 뒤 15% 미만이 되게 합니다. 2초에 두 적이 같은 양(250)을 회복해 회복 불가를 비교합니다."
			elif i == 2:
				_place(target, actor.pos + Vector2(78, -24))
				_place(secondary, actor.pos + Vector2(96, 58))
				instructions += " 오라 반경 150 안에 적 둘을 둡니다."
		"war_machine":
			if i == 0:
				_place(target, actor.pos + Vector2(176, 0))
				_place(secondary, actor.pos + Vector2(205, 64))
				for at in [1.3, 2.45, 3.6]: _at(at, func(): _basic(actor, target))
				var tank_rule: Dictionary = actor.def.rule("fuel_tank")
				instructions += " 부스터로 거리를 좁힌 뒤 평타로 연료를 다시 채웁니다. 평타 적중마다 연료가 %s씩 차며 최대 %s입니다." % [CodexData.num(float(tank_rule.get("perBasic", 1.0))), CodexData.num(float(tank_rule.get("max", 10.0)))]
			elif i == 1:
				_place(target, actor.pos + Vector2(250, -30))
				_place(secondary, actor.pos + Vector2(270, 50))
				_at(0.85, func(): _move(actor, actor.pos + Vector2(0, -90)))
				instructions += " 6발을 충전(1.4초)하는 동안 이동해 40% 감속을 보여준 뒤 유도탄을 놓습니다."
			elif i == 2:
				_place(target, actor.pos + Vector2(170, -24))
				_place(secondary, actor.pos + Vector2(60, 12))
				_attack(target, actor, 0.9, 5.4)
				_attack(secondary, actor, 0.9, 5.4)
				instructions += " 두 적이 계속 평타를 쳐 3초 동안 줄어든 피해와 보호막 전환, 끝난 뒤의 원래 피해를 비교합니다."
			elif i == 3:
				_at(1.7, func(): _move(secondary, secondary.pos + Vector2(0, -150)))
				instructions += " 폭격 지대를 가로지르는 적이 둔화됩니다."
		"torquemada":
			if i == 0 or i == 2:
				_place(ally, actor.pos + (Vector2(150, 80) if i == 0 else Vector2(36, 76)))
				if i == 0:
					# One enemy shares the fire; another stays outside its radius.
					_place(target, ally.pos + Vector2(28, -68))
					_place(secondary, actor.pos + Vector2(340, 60))
				_at(0.2, func(): _debuff_ally())
				instructions += " 적이 먼저 아군에게 기절·둔화·치유 감소를 겁니다."
				if i == 0:
					instructions += " 정화된 아군은 한 번 회복하고, 같은 불 안의 적만 반복 피해를 받습니다."
				else:
					instructions += " 아군은 정화와 보호막을 받고, 적은 피해와 밀침을 받습니다."
			elif i == 1:
				_at(0.3, func(): sim.apply_status(target, actor, {"status": "stun", "duration": 1.0}))
				instructions += " 1초 기절은 강인함 35%로 0.65초만 걸리고, 풀린 뒤 그 적에게 피해를 주고 속박합니다."
		"achilles":
			if i == 0:
				_place(target, actor.pos + Vector2(118, 0))
				_place(secondary, actor.pos + Vector2(186, 6))
				instructions += " 일직선의 적 둘을 창이 모두 꿰뚫습니다."
			elif i == 1:
				_place(target, actor.pos + Vector2(230, -8))
				_place(giant, actor.pos + Vector2(84, -26))
				_place(secondary, actor.pos + Vector2(-64, 8))
				_attack(target, actor, 0.7, 2.8)
				_attack(giant, actor, 0.95, 2.8)
				_attack(secondary, actor, 1.05, 2.8)
				instructions += " 방패를 든 2초 동안 앞의 화살·평타는 막히고 뒤의 검사 평타는 들어갑니다."
			elif i == 2:
				_at(1.6, func(): sim.apply_status(ally, target, {"status": "stun", "duration": 1.0}))
				instructions += " 포효 뒤 아군이 대상에게 1초 기절을 겁니다(강인함 −5%로 1.05초)."
			elif i == 3:
				_place(target, actor.pos + Vector2(150, -120))
				_place(secondary, actor.pos + Vector2(190, 110))
				_place(giant, actor.pos + Vector2(330, 10))
				focus_rect = Rect2(300, 120, 880, 560)
				instructions += " 흩어진 적 셋을 전차가 넉백 횟수가 적은 순서로 쫓습니다(적마다 최대 2회)."


func _debuff_ally() -> void:
	sim.apply_status(target, ally, {"status": "stun", "duration": 3.0})
	sim.apply_status(secondary, ally, {"status": "slow", "magnitude": 0.4, "duration": 4.0})
	sim.apply_status(target, ally, {"status": "healReduction", "magnitude": 0.35, "duration": 6.0})


func _prepare_passive() -> void:
	var passive: Dictionary = actor.def.passives[int(entry.index)]
	var rules: Array = passive.get("rules", [])
	var rule: String = str(rules[0].get("type", "")) if not rules.is_empty() else ""
	entry["rule"] = rule
	var reach: float = clampf(sim.stat(actor, &"attackRange") * 0.65, 52.0, 220.0)
	_place(target, actor.pos + Vector2(reach, 0))
	match rule:
		"nth_basic_bonus":
			for at in [0.8, 2.5, 4.2]: _at(at, func(): _basic(actor, target))
		"on_cast_buff", "on_cc_cdr", "confusion_on_damage":
			if rule == "on_cc_cdr": actor.cooldowns[3] = 10.0
			if rule == "confusion_on_damage": _at(0.8, func(): _basic(actor, target))
			else: _at(0.8, func(): _cast(actor, 0, target))
		"distance_damage":
			_place(target, actor.pos + Vector2(330, 0))
			_at(0.8, func(): _basic(actor, target))
			_at(3.0, func(): _place(target, actor.pos + Vector2(90, 0)); _basic(actor, target))
			instructions += " 원거리 330과 근거리 90에서 실제 평타를 한 번씩 발사합니다."
		"damage_heal", "cone_basic", "pain_stacks":
			_place(target, actor.pos + Vector2(60, 0))
			_at(0.8, func(): _basic(actor, target))
			if rule == "pain_stacks": _at(2.3, func(): _basic(actor, target))
		"regen": actor.hp = sim.max_hp(actor) * 0.5
		"health_size_scaling":
			actor.hp = sim.max_hp(actor)
			_at(0.8, func(): _basic(actor, target))
			_at(3.0, func(): sim.apply_damage(target, actor, {"base": sim.max_hp(actor) * 0.5, "school": "true"}))
			instructions += " 완전한 체력과 피해를 받은 뒤의 몸집·방어 변화를 비교합니다."
		"on_ally_buff_shield": _at(0.8, func(): _cast(actor, 2, ally))
		"lost_health_ap_on_skill_hit": _at(0.8, func(): _cast(actor, 2, target))
		"timed_random_buff": instructions += " 실제 8초 어획을 기다린 뒤 얻은 생선을 섭취합니다."
		"projectile_reflect_arc":
			_place(target, actor.pos + Vector2(210, 0))
			_at(0.8, func(): _basic(target, actor))
		"hybrid_basic":
			_place(target, actor.pos + Vector2(60, 0))
			_at(0.8, func(): _basic(actor, target))
			_at(3.0, func(): _place(target, actor.pos + Vector2(180, 0)); _basic(actor, target))
		"orbit_aura":
			_place(target, actor.pos + Vector2(0, -72))
			_place(ally, actor.pos + Vector2(0, 72))
		"heal_reduction_bank", "plague_heal_reduction":
			_place(target, actor.pos + Vector2(100, 0))
			_at(0.8, func(): _cast(actor, 0, target))
			_at(2.0, func(): target.hp = minf(target.hp, sim.max_hp(target) * 0.4); sim.apply_heal(target, target, {"base": 300.0}))
		"reveal_cooldowns": target.cooldowns[0] = 20.0
		"rage_on_damage": _at(0.8, func(): sim.apply_damage(target, actor, {"base": 260.0, "school": "true"}))
		"wall_mastery":
			_place(actor, Vector2(70 + sim.radius(actor) + 1.0, 320))
			_at(0.8, func(): _move(actor, actor.pos + Vector2(0, 220)))
			focus_rect = Rect2(60, 150, 900, 480)
		"portal_shards":
			_at(0.8, _portals)
			_at(1.5, func(): _move(actor, Vector2(560, 396)))
		"borrow_mobility": instructions += " 실제 12초 차용 주기 뒤 아군 마법사의 이동기를 사용합니다."
		"out_of_combat_speed":
			actor.last_combat_time = 0.0
			_place(target, Vector2(1150, 650))
			_at(0.8, func(): _move(actor, Vector2(1100, 300)))
		"nexus_seed_path": _garden_walk()
		"nexus_workshop":
			_at(0.1, func(): _cast(actor, 0, null, actor.pos + Vector2(65, 0)))
			_at(2.0, func():
				var towers: Array[BUnit] = sim.kits.owned_entities(actor, "turret")
				if not towers.is_empty(): sim.apply_damage(target, towers[0], {"base": 5000.0, "school": "true"}))
		"contemplation":
			_at(1.0, func(): sim.apply_status(target, actor, {"status": "stun", "duration": 2.0}))
			_at(2.0, func(): _cast(actor, 2, actor))
		"media_control": instructions += " 정지한 정치가의 팀을 상대로 군체의 실제 정찰 패시브가 발동합니다."
		# ---------------------------------------------------------------- V2 heroes
		"concealed_regen":
			_place(actor, Vector2(560, 400))
			_place(ally, Vector2(540, 484))
			_place(target, Vector2(830, 392))
			_place(secondary, Vector2(850, 462))
			_at(1.5, func(): _move(actor, BRUSH_REGEN_CENTER))
			instructions += " 적의 시야 안에서는 회복하지 않고, 1.5초에 수풀(암흑시야)로 들어간 뒤부터 회복합니다."
		"companion":
			_place(target, actor.pos + Vector2(124, -12))
			_place(secondary, actor.pos + Vector2(320, 90))
			_at(6.5, func(): _move(actor, actor.pos + Vector2(-260, 0)))
			instructions += " 160 안의 적을 케르베로스가 뭅니다. 6.5초에 하데스가 물러나면 공격을 멈추고 뒤를 따라옵니다."
		"fuel_tank":
			# The tank rides behind the war machine (facing right): the swordsman
			# and the giant strike it from behind while it hits the archer in front.
			_place(target, actor.pos + Vector2(62, 0))
			_place(secondary, actor.pos + Vector2(-82, 6))
			_place(sim.heroes[4], actor.pos + Vector2(-58, 78))
			var tank: Callable = func() -> BUnit: return sim.u_at(int(actor.ks.get("tank_idx", -1)))
			_attack(secondary, tank, 0.3, 7.0)
			_attack(sim.heroes[4], tank, 0.3, 7.0)
			_attack(actor, target, 0.8, 8.8, true)
			_at(5.0, func(): _move(target, Vector2(1060, 330)))
			_at(8.8, func(): _path.assign([Vector2(560, 400)]); _path_index = 0)
			instructions += " 평타로 연료를 모으는 동안 검사·거인이 등 뒤 탱크를 터뜨리면, 과열 폭주로 달아나는 궁수를 쫓아 친 뒤 돌아옵니다."
		"faith_tenacity":
			_place(target, actor.pos + Vector2(210, -30))
			_place(ally, actor.pos + Vector2(0, 92))
			_at(0.8, func(): sim.apply_status(target, actor, {"status": "stun", "duration": 2.0}); sim.apply_status(target, ally, {"status": "stun", "duration": 2.0}))
			instructions += " 같은 2초 기절을 토르케마다(강인함 35%)와 아군 마법사(5%)에게 동시에 겁니다."
		"status_tenacity":
			_place(target, actor.pos + Vector2(210, -30))
			_place(ally, actor.pos + Vector2(0, 92))
			_at(0.8, func(): sim.apply_status(target, actor, {"status": "charm", "duration": 2.0}); sim.apply_status(target, ally, {"status": "charm", "duration": 2.0}))
			_at(3.5, func(): sim.apply_status(target, actor, {"status": "stun", "duration": 2.0}))
			instructions += " 2초 유혹을 토르케마다와 아군에게 걸고, 3.5초에 같은 2초 기절을 토르케마다에게 걸어 지속 시간을 비교합니다."
		"basic_armor_bonus":
			_place(target, actor.pos + Vector2(250, -70))
			_place(secondary, actor.pos + Vector2(64, 0))
			_at(0.8, func(): _basic(secondary, actor))
			_at(2.6, func(): sim.apply_damage(secondary, actor, {"base": sim.stat(secondary, &"attackDamage"), "school": "physical"}, {"source_type": "ABILITY"}))
			instructions += " 같은 검사가 평타와 같은 원래 피해(공격력 %d)의 스킬 피해를 한 번씩 줍니다. 평타 피해가 더 작습니다." % int(sim.stat(secondary, &"attackDamage"))


func _main_cast() -> bool:
	var a: Defs.AbilityDef = _ability
	var victim: BUnit = ally if a.target in ["ally", "position_ally"] else target
	var aim: Vector2 = victim.pos
	var extra: Dictionary = {}
	if a.target == "self":
		victim = actor
		aim = actor.pos
	if a.action == "portalPair":
		aim = actor.pos + Vector2(245, 0)
		extra = {"portal_a": actor.pos + Vector2(60, 0), "portal_b": aim}
	if a.action == "interrogate": extra["info_kind"] = "cooldowns"
	if a.action == "upgrade": aim = actor.pos
	# V2: a full charge (war_machine S2), a guard raised toward the attackers in
	# front (achilles S2) and a dash aimed at the far target within its range.
	var charge: Dictionary = a.flag("originCharge", {})
	if not charge.is_empty(): extra["charge"] = int(charge.get("max", 2))
	if _has_effect(a, "front_guard"): aim = target.pos
	if a.target == "position" and _has_effect(a, "move_self") and actor.pos.distance_to(aim) > a.range + sim.radius(actor) + 8.0:
		aim = actor.pos + (aim - actor.pos).normalized() * a.range
	return _cast(actor, int(entry.index), victim, aim, extra)


func _has_effect(a: Defs.AbilityDef, type: String) -> bool:
	for f in a.effects:
		if f is Dictionary and str(f.get("type", "")) == type: return true
	return false


func step() -> bool:
	if sim == null or finished or sim.state != BattleSim.RUNNING:
		finished = true
		return false
	var previous_events: int = sim.tick_events.size()
	for job in _jobs:
		if not bool(job.done) and sim.time + 0.000001 >= float(job.at):
			job.done = true
			(job.call as Callable).call()
	if not _attacks.is_empty(): _run_attacks()
	if not _path.is_empty() and _path_index < _path.size():
		if actor.pos.distance_to(_path[_path_index]) < 12.0:
			_path_index += 1
		if _path_index < _path.size(): _move(actor, _path[_path_index])
		else: actor.command = {}
	if entry.kind == "active" and not cast_started and sim.time >= _main_due and sim.time >= _next_attempt:
		cast_started = _main_cast()
		_next_attempt = sim.time + 0.1
	if entry.kind == "passive": _passive_followup()
	for index in range(previous_events, sim.tick_events.size()): _record(sim.tick_events[index])
	var old_pos: Vector2 = actor.pos
	sim.step()
	elapsed = sim.time
	metrics.actor_distance = float(metrics.actor_distance) + actor.pos.distance_to(old_pos)
	for ev in sim.tick_events: _record(ev)
	_sample()
	finished = sim.time + 0.000001 >= duration or sim.state != BattleSim.RUNNING
	return true


func _passive_followup() -> void:
	var rule: String = str(entry.get("rule", ""))
	if rule in ["timed_random_buff", "borrow_mobility"] and not _virtual_done:
		var after: float = 8.5 if rule == "timed_random_buff" else 12.5
		if sim.time >= after:
			var abilities: Array = sim.ability_list(actor)
			if abilities.size() > actor.def.abilities.size():
				var a: Defs.AbilityDef = abilities[-1]
				_virtual_done = _cast(actor, abilities.size() - 1, actor if a.target == "self" else target, actor.pos if a.target == "self" else actor.pos + Vector2(100, 0))
	if rule == "projectile_reflect_arc" and not _reflect_started:
		for p in sim.proj.list:
			if p.team != actor.team and p.pos.distance_to(actor.pos) < 100.0:
				_reflect_started = _cast(actor, sim.ability_list(actor).size() - 1, null, target.pos)
				break


func _record(ev: Dictionary) -> void:
	var a = ev.get("ability")
	var item: Dictionary = {"type": str(ev.type), "t": float(ev.t), "s": int(ev.s), "g": int(ev.g),
		"ability_id": (a as Defs.AbilityDef).id if a is Defs.AbilityDef else "", "rule": str(ev.get("rule", "")),
		"amount": float(ev.get("amount", 0.0)), "crit": bool(ev.get("crit", false)), "school": str(ev.get("school", "")), "status": str(ev.get("status", "")),
		"source_type": str(ev.get("source_type", "")), "basic": bool(ev.get("basic", false)), "kind": str(ev.get("kind", "")),
		"duration": float(ev.get("duration", 0.0)), "charge": int(ev.get("charge", 0))}
	events.append(item)
	var counts: Dictionary = metrics.events
	counts[item.type] = int(counts.get(item.type, 0)) + 1
	if item.s == actor.idx:
		if item.type == "HEALTH_DAMAGED": metrics.damage = float(metrics.damage) + item.amount
		if item.type == "HEAL_APPLIED": metrics.healing = float(metrics.healing) + item.amount
		if item.type == "SHIELD_APPLIED": metrics.shielding = float(metrics.shielding) + item.amount


func _sample() -> void:
	metrics.max_radius = maxf(float(metrics.max_radius), sim.radius(actor))
	metrics.min_radius = minf(float(metrics.min_radius), sim.radius(actor))
	metrics.max_ms = maxf(float(metrics.max_ms), sim.stat(actor, &"moveSpeed"))
	metrics.max_ap = maxf(float(metrics.max_ap), sim.stat(actor, &"abilityPower"))
	metrics.max_coefficient = maxf(float(metrics.max_coefficient), sim.ability_coefficient(actor))
	metrics.max_hp = maxf(float(metrics.max_hp), sim.max_hp(actor))
	for key in actor.resources: metrics.resources[key] = maxf(float(metrics.resources.get(key, 0.0)), float(actor.resources[key]))
	var owned: Dictionary = {}
	for u in sim.units:
		for b in u.buffs:
			if b.source_idx == actor.idx: metrics.buffs[str(b.stat)] = true
		for st in u.statuses:
			if st.source_idx == actor.idx: metrics.statuses[str(st.type)] = maxi(int(metrics.statuses.get(str(st.type), 0)), st.stacks)
		if u.owner_idx == actor.idx and u.kind == "turret": metrics.max_turret_level = maxi(int(metrics.max_turret_level), u.level)
		if u.owner_idx == actor.idx and u.alive and not u.is_hero: owned[u.kind] = int(owned.get(u.kind, 0)) + 1
	# Live entities the actor owns, by kind (cerberus, shades, fuel tank, chariot, ...).
	for kind in owned: metrics.entities[kind] = maxi(int(metrics.entities.get(kind, 0)), int(owned[kind]))


func readout() -> Dictionary:
	return {"cast_started": cast_started, "damage": float(metrics.get("damage", 0)), "healing": float(metrics.get("healing", 0)),
		"shielding": float(metrics.get("shielding", 0)), "resources": metrics.get("resources", {}).duplicate(), "finished": finished,
		"extra": _extra_readout()}


## Live state worth a badge: the war machine's fuel, or max HP above the base
## (hades' soul harvest). Empty when there is nothing to show.
func _extra_readout() -> String:
	if actor == null or sim == null: return ""
	if actor.resources.has("fuel"): return "연료 %d" % int(floor(float(actor.resources.fuel) + 0.000001))
	var bonus: float = sim.max_hp(actor) - actor.def.stat("maxHealth")
	return "최대 체력 +%d" % int(bonus) if bonus >= 1.0 else ""
