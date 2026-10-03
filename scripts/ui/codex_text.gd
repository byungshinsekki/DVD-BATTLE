class_name CodexText
extends RefCounted

# Text formatting for the codex (V1.5.1). Pure functions: no Nodes are made.
#
# rich_desc(text)      BBCode for a RichTextLabel: numbers bold, AD/AP ratios and
#                      "최대 HP n%" coloured, glossary terms coloured with a
#                      [hint] tooltip. Source '[' is escaped as [lb].
# terms_in(text)       glossary keys (CodexData.STATUS) in order of first appearance.
# ability_meta(ab)     chip data [{text, color, tip, kind}] for a skill header.
# passive_meta(p)      chip data for a passive.
# resource_cost(ab, k) what one use of the skill spends of resource k.
# clean_geometry(ab)   geometry text without fragments that repeat the range chip.

const AD_COLOR := "#ff9a6b"
const AP_COLOR := "#b58cff"
const HP_COLOR := "#5ad6c0"
const NUM_COLOR := "#eaf0fa"
const HINT_WIDTH := 34

const C_DIM := Color("#a9b6cc")
const C_WARN := Color("#ffb45e")
const C_GOLD := Color("#f4c96b")
const C_PASSIVE := Color("#a98cff")
const C_BAD := Color("#ff6d79")

# Actions whose structured `effects` are wrong, empty or ignored by the engine
# (map_effects_2 warning): their damage school is read from the text instead.
const UNRELIABLE_ORIGIN := ["swapBox", "rift", "wallRun", "glide", "rescueFlight", "portalArming"]

# V2: resources whose condition chip reads as a cost ("연료 1 소모"): the skill
# spends what it requires. Older resources keep their "조건: …" chips.
const COST_RESOURCES := ["fuel"]

const TARGET_LABELS := {"enemy": "적", "ally": "아군", "self": "자신", "position": "지점", "position_ally": "아군 지점"}
const TARGET_TIPS := {
	"enemy": "적 하나를 겨냥해 사용합니다.",
	"ally": "아군 하나를 지정해 사용합니다.",
	"self": "대상을 고르지 않고 자신에게 바로 사용합니다.",
	"position": "원하는 지점을 지정해 사용합니다.",
	"position_ally": "아군을 돕는 설치물이나 효과를 원하는 지점에 놓습니다.",
}
const SCHOOL_KEYS := {"physical": "physical", "magic": "magic", "true": "true"}
const SCHOOL_WORDS := {"물리": "physical", "마법": "magic", "고정": "true"}

static var _re: RegEx
static var _re_school: RegEx
static var _re_range_frag: RegEx
static var _surfaces: Dictionary = {}
static var _rich_cache: Dictionary = {}
static var _terms_cache: Dictionary = {}
static var _hint_cache: Dictionary = {}
static var _term_index: Dictionary = {}


static func _ensure() -> void:
	if _re != null:
		return
	for k in CodexData.STATUS:
		var d: Dictionary = CodexData.STATUS[k]
		_surfaces[str(d.label)] = k
		for a in d.get("aliases", []):
			if not _surfaces.has(str(a)):
				_surfaces[str(a)] = k
	var surf: Array = _surfaces.keys()
	surf.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length() or (a.length() == b.length() and a < b))
	var alts: PackedStringArray = PackedStringArray()
	for s in surf:
		alts.append(_re_escape(str(s)))
	var number: String = "(?:\\d{1,3}(?:,\\d{3})+|\\d+(?:\\.\\d+)?)"
	var pat: String = ""
	# Max-HP ratios: "최대 HP 3%", "대상 최대 체력 1.5%", "0.03Hmax", "Hmax×4%".
	pat += "(?<hp>\\+?(?:대상\\s?)?최대\\s?(?:HP|체력)\\s?\\d+(?:\\.\\d+)?%|\\+?\\d+(?:\\.\\d+)?\\s?Hmax|\\+?(?:대상\\s?)?Hmax\\s?×\\s?\\d+(?:\\.\\d+)?%)"
	pat += "|(?<ad>(?:\\+|(?<![A-Za-z0-9.]))\\d+(?:\\.\\d+)?\\s?AD(?![A-Za-z]))"
	pat += "|(?<ap>(?:\\+|(?<![A-Za-z0-9.]))\\d+(?:\\.\\d+)?\\s?AP(?![A-Za-z]))"
	pat += "|(?<term>" + "|".join(alts) + ")"
	pat += "|(?<num>(?:[+\\-−±×]|(?<![A-Za-z0-9.]))" + number + "(?:%p|%|초|°|명|회|스택|중첩|마리|개|그루|송이|발|단계|칸|번)?)"
	_re = RegEx.new()
	_re.compile(pat)
	_re_school = RegEx.new()
	_re_school.compile("(물리|마법|고정)\\s?(?:피해|투사체|탄환|탄)")
	_re_range_frag = RegEx.new()
	_re_range_frag.compile("^(?:사거리|지정|거리|아군 지정|아군|근접 지정|근거리)\\s*(\\d+(?:\\.\\d+)?)$")


static func _re_escape(s: String) -> String:
	var out: String = ""
	for ch in s:
		if "\\.^$|?*+()[]{}".contains(ch):
			out += "\\" + ch
		else:
			out += ch
	return out


# '[' starts a BBCode tag; escape it so source text is shown verbatim.
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _kind(m: RegExMatch) -> String:
	for k in ["hp", "ad", "ap", "term", "num"]:
		if m.get_start(k) >= 0:
			return k
	return ""


# ---------------------------------------------------------------- rich text

static func rich_desc(text: String) -> String:
	if text == "":
		return ""
	if _rich_cache.has(text):
		return _rich_cache[text]
	_ensure()
	var out: String = ""
	var pos: int = 0
	for m in _re.search_all(text):
		var s: int = m.get_start()
		var e: int = m.get_end()
		if s < pos or e <= s:
			continue
		out += escape(text.substr(pos, s - pos))
		var tok: String = m.get_string()
		match _kind(m):
			"hp":
				out += "[color=%s][b]%s[/b][/color]" % [HP_COLOR, escape(tok)]
			"ad":
				out += "[color=%s][b]%s[/b][/color]" % [AD_COLOR, escape(tok)]
			"ap":
				out += "[color=%s][b]%s[/b][/color]" % [AP_COLOR, escape(tok)]
			"term":
				var key: String = str(_surfaces.get(tok, ""))
				if key == "":
					out += escape(tok)
				else:
					out += "[hint=%s][color=%s]%s[/color][/hint]" % [hint_text(key), str(CodexData.STATUS[key].color), escape(tok)]
			"num":
				out += "[color=%s][b]%s[/b][/color]" % [NUM_COLOR, escape(tok)]
			_:
				out += escape(tok)
		pos = e
	out += escape(text.substr(pos))
	if _rich_cache.size() > 800:
		_rich_cache.clear()
	_rich_cache[text] = out
	return out


# Tooltip text for a glossary term: "이름 — 정의", pre-wrapped, tag-safe.
static func hint_text(key: String) -> String:
	if _hint_cache.has(key):
		return _hint_cache[key]
	var d: Dictionary = CodexData.STATUS.get(key, {})
	if d.is_empty():
		return ""
	var t: String = wrap_text("%s — %s" % [str(d.label), str(d.desc)], HINT_WIDTH)
	t = t.replace("[", "(").replace("]", ")").replace("\"", "'")
	_hint_cache[key] = t
	return t


# Greedy word wrap for tooltips (Godot tooltips do not wrap by themselves).
static func wrap_text(text: String, max_chars: int = HINT_WIDTH) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for para in text.split("\n"):
		var line: String = ""
		for word in para.split(" ", false):
			if line == "":
				line = word
			elif line.length() + 1 + word.length() <= max_chars:
				line += " " + word
			else:
				lines.append(line)
				line = word
		lines.append(line)
	return "\n".join(lines)


# Glossary keys found in the text (aliases resolved), first appearance order.
# statuses_only skips the "피해·규칙" category (damage schools, cooldown, ...).
static func terms_in(text: String, statuses_only: bool = false) -> Array:
	if text == "":
		return []
	var ck: String = ("S|" if statuses_only else "A|") + text
	if _terms_cache.has(ck):
		return (_terms_cache[ck] as Array).duplicate()
	_ensure()
	var out: Array = []
	for m in _re.search_all(text):
		if m.get_start("term") < 0:
			continue
		var key: String = str(_surfaces.get(m.get_string(), ""))
		if key == "" or out.has(key):
			continue
		if statuses_only and str(CodexData.STATUS[key].category) == "피해·규칙":
			continue
		out.append(key)
	if _terms_cache.size() > 800:
		_terms_cache.clear()
	_terms_cache[ck] = out
	return out.duplicate()


# ---------------------------------------------------------------- chips

static func _chip(text: String, color: Color, tip: String, kind: String) -> Dictionary:
	return {"text": text, "color": color, "tip": tip, "kind": kind}


static func _term_tip(key: String) -> String:
	var d: Dictionary = CodexData.STATUS.get(key, {})
	return wrap_text("%s — %s" % [str(d.get("label", key)), str(d.get("desc", ""))], HINT_WIDTH + 8) if not d.is_empty() else ""


static func is_unreliable(ab: Defs.AbilityDef) -> bool:
	if ab == null:
		return true
	return ab.action in Kits.NEXUS_ACTIONS or ab.action in InformationWarfare.ACTIONS or ab.action in UNRELIABLE_ORIGIN


# "physical" / "magic" / "true" or "" when not reliably known. Structured
# effects decide for normal skills; unreliable actions and skills whose damage
# is implemented in code (no damage effect) fall back to the description.
static func school_of(ab: Defs.AbilityDef) -> String:
	if ab == null:
		return ""
	if is_unreliable(ab):
		return school_in_text(ab.description)
	var s: String = _first_school(ab.effects)
	return s if s != "" else school_in_text(ab.description)


static func school_in_text(text: String) -> String:
	_ensure()
	var m: RegExMatch = _re_school.search(text)
	if m == null:
		return ""
	return str(SCHOOL_WORDS.get(m.get_string(1), ""))


# A damage effect with every amount at 0 (e.g. parasites that only infect).
static func _deals_damage(d: Dictionary) -> bool:
	for k in d:
		if str(k) == "type" or str(k) == "school":
			continue
		var x: Variant = d[k]
		if (x is float or x is int) and absf(float(x)) > 0.000001:
			return true
	return false


static func _first_school(v: Variant) -> String:
	if v is Dictionary:
		var d: Dictionary = v
		if str(d.get("type", "")) == "damage" and d.has("school") and _deals_damage(d):
			return str(SCHOOL_KEYS.get(str(d.school), ""))
		for k in d:
			var s: String = _first_school(d[k])
			if s != "":
				return s
	elif v is Array:
		for x in v:
			var s2: String = _first_school(x)
			if s2 != "":
				return s2
	return ""


static func ability_meta(ab: Defs.AbilityDef) -> Array:
	var out: Array = []
	if ab == null:
		return out
	if ab.cooldown > 0.0:
		out.append(_chip("재사용 %s초" % CodexData.num(ab.cooldown), C_DIM,
			wrap_text("스킬을 쓴 뒤 %s초가 지나야 다시 쓸 수 있습니다." % CodexData.num(ab.cooldown), HINT_WIDTH + 8), "cooldown"))
	var charge: Dictionary = ab.flag("originCharge", {})
	if ab.cast_time >= 0.2 - 0.0001:
		var cast_text: String = CodexData.num(ab.cast_time)
		if not charge.is_empty():
			cast_text += "~" + CodexData.num(_charge_time(charge, int(charge.get("max", 2))))
		out.append(_chip("시전 %s초" % cast_text, C_WARN if ab.cast_time >= 0.5 else C_DIM,
			wrap_text("%s초 준비한 뒤 발동합니다. 준비 중 기절·에어본·제압·수면에 걸리면 취소되고 침묵도 스킬 준비를 취소합니다." % cast_text, HINT_WIDTH + 8), "cast"))
	if ab.range > 0.0 and ab.target != "self":
		out.append(_chip("사거리 %s" % CodexData.num(ab.range), C_DIM,
			wrap_text("%s 거리 안의 대상이나 지점에 사용할 수 있습니다." % CodexData.num(ab.range), HINT_WIDTH + 8), "range"))
	if TARGET_LABELS.has(ab.target):
		out.append(_chip("대상: %s" % str(TARGET_LABELS[ab.target]), C_DIM, str(TARGET_TIPS.get(ab.target, "")), "target"))
	out.append_array(condition_chips(ab))
	if not charge.is_empty():
		var lo: int = int(charge.get("min", 2))
		var hi: int = int(charge.get("max", 6))
		out.append(_chip("차징 %d~%d발" % [lo, hi], CodexData.term_color("charge", C_WARN),
			wrap_text("%d발은 %s초, 1발 늘 때마다 %s초씩 더 충전해 최대 %d발(%s초)을 쏩니다. 충전 중 이동 속도 −%s%%." % [lo, CodexData.num(_charge_time(charge, lo)),
				CodexData.num(float(charge.get("perStep", 0.3))), hi, CodexData.num(_charge_time(charge, hi)), CodexData.num(float(charge.get("slow", 0.0)) * 100.0)], HINT_WIDTH + 8)
			+ "\n" + _term_tip("charge"), "charge"))
	var owner: Defs.CharDef = DB.char_def(ab.char_id)
	if owner and owner.has_rule("fuel_tank"):
		# V2 war_machine: overdrive leaves only S1 usable (and S1 free).
		if bool(ab.flag("originFreeInOverdrive", false)):
			out.append(_chip("과열 폭주 중 무료", CodexData.term_color("overdrive", C_WARN), "과열 폭주 중에는 연료 없이 쓸 수 있습니다.\n" + _term_tip("overdrive"), "rule"))
		elif ab.slot != 1:
			out.append(_chip("과열 폭주 중 봉인", CodexData.term_color("overdrive", C_WARN), "과열 폭주 10초 동안은 쓸 수 없습니다(S1만 사용 가능).\n" + _term_tip("overdrive"), "rule"))
	var school: String = school_of(ab)
	if school != "":
		var sd: Dictionary = CodexData.STATUS[school]
		out.append(_chip(str(sd.label), Color(str(sd.color)), _term_tip(school), "school"))
	return out


# Requirements from ab.condition (every shape used in CharData) plus the
# action-based requirements the engine checks in Kits.extra_ready.
static func condition_chips(ab: Defs.AbilityDef) -> Array:
	var out: Array = []
	if ab == null:
		return out
	var c: Dictionary = ab.condition
	if c.has("targetStatus"):
		var st: String = str(c.targetStatus)
		var key: String = CodexData.term_for_label(st)
		var label: String = CodexData.term_label(key) if key != "" else DB.status_label(st)
		var col: Color = CodexData.term_color(key, C_GOLD) if key != "" else C_GOLD
		var owned: bool = bool(c.get("owned", false))
		var text: String = "조건: %s" % label
		var tip: String = ""
		if c.has("minPain"):
			text = "조건: %s %d중첩" % [label, int(c.minPain)]
			tip = "내가 쌓은 %s %d중첩 이상인 적 영웅에게만 사용할 수 있습니다." % [label, int(c.minPain)]
		elif st == "control":
			text = "조건: 조종 중인 대상"
			tip = "내가 조종 중인 대상에게만 사용할 수 있습니다."
		elif owned:
			tip = "대상에게 내가 건 %s 상태가 있어야 사용할 수 있습니다. 다른 영웅이 건 것은 쓸 수 없습니다." % label
		else:
			tip = "대상에게 %s 상태가 있어야 사용할 수 있습니다." % label
		if key != "":
			tip += "\n" + _term_tip(key)
		out.append(_chip(text, col, wrap_text(tip, HINT_WIDTH + 8), "condition"))
	elif c.has("minPain"):
		out.append(_chip("조건: 고통 %d중첩" % int(c.minPain), CodexData.term_color("pain", C_GOLD),
			wrap_text("내가 쌓은 고통 %d중첩 이상인 적 영웅에게만 사용할 수 있습니다." % int(c.minPain), HINT_WIDTH + 8), "condition"))
	if c.has("selfResource"):
		var sr: Dictionary = c.selfResource
		var rk: String = str(sr.get("key", ""))
		var mn: float = float(sr.get("min", 1))
		var info: Array = CodexData.RESOURCES.get(rk, [rk, "", ""])
		var rl: String = str(info[0])
		var unit: String = str(info[1])
		var text2: String = "조건: %s %s%s" % [rl, CodexData.num(mn), unit]
		var tip2: String = "자신에게 %s %s%s 이상이 있어야 사용할 수 있습니다." % [rl, CodexData.num(mn), unit]
		if rk == "healBank":
			text2 = "조건: %s 보유" % rl
			tip2 = "힐 주머니에 저장된 회복량이 있어야 사용할 수 있습니다."
		var col2: Color = C_GOLD
		var cost: Dictionary = resource_cost(ab, rk)
		if rk in COST_RESOURCES and not cost.is_empty():
			col2 = CodexData.term_color(str(info[2]), C_GOLD)
			if bool(cost.per_projectile):
				text2 = "%s %s~%s 소모" % [rl, CodexData.num(float(cost.low)), CodexData.num(float(cost.high))]
				tip2 = "쏘는 1발마다 %s를 %s 씁니다(%s~%s). %s가 %s 이상 있어야 하고, 시전이 취소되면 쓰지 않습니다." % [rl, CodexData.num(float(cost.amount)),
					CodexData.num(float(cost.low)), CodexData.num(float(cost.high)), rl, CodexData.num(mn)]
			else:
				text2 = "%s %s 소모" % [rl, CodexData.num(float(cost.amount))]
				tip2 = "쓸 때마다 %s를 %s 소모하며 %s가 %s 이상 있어야 사용할 수 있습니다." % [rl, CodexData.num(float(cost.amount)), rl, CodexData.num(mn)]
		if bool(sr.get("originFreeInOverdrive", false)):
			tip2 += " 과열 폭주 중에는 %s 없이 쓸 수 있습니다." % rl
		var term_tip: String = _term_tip(str(info[2])) if str(info[2]) != "" else ""
		out.append(_chip(text2, col2, wrap_text(tip2, HINT_WIDTH + 8) + ("\n" + term_tip if term_tip != "" else ""), "condition"))
	if bool(c.get("concealed", false)):
		out.append(_chip("암흑시야 전용", CodexData.term_color("concealed", C_GOLD),
			wrap_text("암흑시야(적에게 보이지 않는 위치)에서만 시작할 수 있습니다. 시전 중에 발각되어도 취소되지 않습니다.", HINT_WIDTH + 8) + "\n" + _term_tip("concealed"), "condition"))
	if c.has("ccSourceWithin"):
		var win: String = CodexData.num(float(c.ccSourceWithin))
		out.append(_chip("조건: CC 출처 %s초 이내" % win, C_GOLD,
			wrap_text("지난 %s초 안에 나에게 군중 제어(둔화 제외, 넉백·끌어당김 포함)를 건 적에게만 사용할 수 있습니다. 장판·미끼·소환물로 건 제어는 그 주인이 건 것으로 기록됩니다." % win, HINT_WIDTH + 8), "condition"))
	if bool(c.get("nearWall", false)):
		out.append(_chip("조건: 벽 접촉", C_GOLD, "벽에 붙어 있을 때만 사용할 수 있습니다.", "condition"))
	if bool(c.get("targetIsCC", false)):
		out.append(_chip("조건: 군중 제어된 적", C_GOLD,
			wrap_text("둔화를 제외한 군중 제어(기절·속박·침묵·수면 등)에 걸린 적에게만 사용할 수 있습니다.", HINT_WIDTH + 8), "condition"))
	match ab.action:
		"portalArming":
			out.append(_chip("조건: 내 포탈 쌍", C_GOLD, "내가 설치한 포탈 쌍이 있어야 사용할 수 있습니다.", "condition"))
		"rootGarden", "thornGarden":
			out.append(_chip("조건: 재생영역", C_GOLD, wrap_text("내 재생영역(생명의 폐곡선)이 하나 이상 있어야 사용할 수 있습니다.", HINT_WIDTH + 8), "condition"))
		"detonate":
			out.append(_chip("조건: 포탑 %s 이내" % CodexData.num(ab.range), C_GOLD,
				wrap_text("내 포탑이 %s 거리 안에 있어야 사용할 수 있습니다." % CodexData.num(ab.range), HINT_WIDTH + 8), "condition"))
		"upgrade":
			out.append(_chip("조건: 포탑 100 이내", C_GOLD,
				wrap_text("100 거리 안에 3단계 미만인 내 포탑이 있어야 사용할 수 있습니다.", HINT_WIDTH + 8), "condition"))
	return out


static func passive_meta(p: Dictionary) -> Array:
	var out: Array = [_chip("패시브 · 자동 발동", C_PASSIVE, "직접 사용하지 않고 조건이 맞으면 자동으로 적용됩니다.", "passive")]
	for r in p.get("rules", []):
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		match str(rd.get("type", "")):
			"rage_on_damage":
				out.append(_chip("충격 최대 %d스택" % int(rd.get("maxStacks", 8)), C_GOLD, "받은 피해로 쌓이는 자원입니다.", "resource"))
			"pain_stacks":
				out.append(_chip("고통 최대 %d중첩" % int(rd.get("maxStacks", 6)), CodexData.term_color("pain"), _term_tip("pain"), "resource"))
			"confusion_on_damage":
				out.append(_chip("혼란 최대 %d중첩" % int(rd.get("maxStacks", 5)), CodexData.term_color("confusion"), _term_tip("confusion"), "resource"))
			"plague_heal_reduction":
				out.append(_chip("역병 최대 %d중첩" % int(rd.get("maxStacks", 6)), CodexData.term_color("plague"), _term_tip("plague"), "resource"))
			"heal_reduction_bank":
				out.append(_chip("힐 주머니 최대 %d" % int(rd.get("originCap", 1200)), C_GOLD, "역병으로 줄어든 적의 회복량을 모아 두는 자원입니다.", "resource"))
			"portal_shards":
				out.append(_chip("차원 조각 최대 %d" % int(rd.get("max", 40)), C_GOLD, "포탈을 통과할 때마다 쌓이는 자원입니다.", "resource"))
			"nexus_workshop":
				out.append(_chip("빡침 최대 %d" % int(rd.get("maxStacks", 6)), C_GOLD, "포탑이 파괴될 때 쌓이며 줄어들지 않습니다.", "resource"))
			"wall_mastery":
				out.append(_chip("충격 최대치 +%d" % int(rd.get("bonusMaxStacks", 4)), C_GOLD, "벽에 새로 닿을 때마다 충격 최대치가 오릅니다.", "resource"))
			"nexus_seed_path":
				out.append(_chip("재생영역 최대 %d개" % int(rd.get("maxZones", 3)), C_GOLD, "초과하면 가장 오래된 재생영역이 사라집니다.", "resource"))
			"timed_random_buff":
				out.append(_chip("%s초마다 물고기" % CodexData.num(float(rd.get("interval", 8))), C_DIM, "무작위 물고기를 얻습니다(최대 2마리).", "interval"))
			"reveal_cooldowns":
				out.append(_chip("%s초마다 정보 공개" % CodexData.num(float(rd.get("interval", 7))), C_DIM, "적 1명의 재사용 대기시간을 팀에 공개합니다.", "interval"))
			"borrow_mobility":
				out.append(_chip("%s초마다 이동기 차용" % CodexData.num(float(rd.get("interval", 12))), C_DIM, "다른 아군의 이동 스킬 하나를 빌려 한 번 쓸 수 있습니다.", "interval"))
			"orbit_aura":
				out.append(_chip("%s초에 한 바퀴" % CodexData.num(float(rd.get("interval", 2))), C_DIM, "날개가 도는 주기입니다.", "interval"))
			"regen":
				out.append(_chip("초당 %s 재생" % CodexData.num(float(rd.get("perSecond", 0))), Color("#6fe0a2"), "치유 감소가 적용됩니다.", "stat"))
			"no_basic":
				out.append(_chip("평타 없음", C_BAD, "기본 공격을 하지 않습니다. 평타 관련 아이템 효과를 받지 못합니다.", "rule"))
			# V2 heroes
			"concealed_regen":
				out.append(_chip("암흑시야 중 초당 %s%% 재생" % CodexData.num(float(rd.get("perSecondRatio", 0.02)) * 100.0), Color("#6fe0a2"),
					wrap_text("마지막 피격 후 %s초가 지나면 최대 체력 비례로 회복합니다. 치유 감소와 회복 불가가 적용됩니다." % CodexData.num(float(rd.get("delay", 1.0))), HINT_WIDTH + 8) + "\n" + _term_tip("concealed"), "stat"))
			"companion":
				out.append(_chip("동반 소환물 · %s초 뒤 부활" % CodexData.num(float(rd.get("respawn", 15))), C_GOLD,
					"쓰러지면 다시 나타나고, 주인이 쓰러지면 함께 사라집니다.\n" + _term_tip("summon"), "rule"))
			"fuel_tank":
				out.append(_chip("연료 최대 %d" % int(rd.get("max", 10)), CodexData.term_color("fuel", C_GOLD), _term_tip("fuel"), "resource"))
				out.append(_chip("탱크 파괴 시 과열 폭주 %s초" % CodexData.num(float(rd.get("overdrive", 10))), CodexData.term_color("overdrive", C_WARN), _term_tip("overdrive"), "rule"))
			"faith_tenacity":
				out.append(_chip("강인함 %s%%" % CodexData.num(float(rd.get("total", 0.35)) * 100.0), CodexData.term_color("tenacity", C_GOLD), _term_tip("tenacity"), "stat"))
			"status_tenacity":
				for key in rd:
					if str(key) != "type":
						out.append(_chip("%s 강인함 +%s%%" % [DB.status_label(str(key)), CodexData.num(float(rd[key]) * 100.0)], CodexData.term_color(str(key), C_GOLD),
							"강인함과 곱으로 적용되어 이 상태 이상의 지속 시간만 더 줄어듭니다." + ("\n" + _term_tip("charmTenacity") if str(key) == "charm" else ""), "stat"))
			"basic_armor_bonus":
				out.append(_chip("평타 저항 · 방어 +%s%%" % CodexData.num(float(rd.get("ratio", 0.3)) * 100.0), CodexData.term_color("basicResist", C_GOLD), _term_tip("basicResist"), "stat"))
	return out


# What one use of the skill spends of resource `key` (consume_resource effects):
# {amount, per_projectile, low, high} or {} when it spends none. A per-projectile
# cost scales with the charge range of a charged cast (war_machine S2: 2~6).
static func resource_cost(ab: Defs.AbilityDef, key: String) -> Dictionary:
	if ab == null:
		return {}
	for f in ab.effects:
		if not (f is Dictionary) or str(f.get("type", "")) != "consume_resource" or str(f.get("key", "")) != key:
			continue
		var amount: float = float(f.get("amount", 1))
		var per: bool = bool(f.get("perProjectile", false))
		var charge: Dictionary = ab.flag("originCharge", {})
		var lo: float = float(charge.get("min", ab.count)) if per else 1.0
		var hi: float = float(charge.get("max", ab.count)) if per else 1.0
		return {"amount": amount, "per_projectile": per, "low": amount * lo, "high": amount * hi}
	return {}


static func _charge_time(charge: Dictionary, n: int) -> float:
	return float(charge.get("base", 0.2)) + float(charge.get("perStep", 0.3)) * (n - int(charge.get("min", 2)))


# ---------------------------------------------------------------- geometry

# Geometry without "사거리 0" and without fragments that only repeat the
# range already shown by the 사거리 chip (e.g. "지정 330", "사거리 230").
static func clean_geometry(ab: Defs.AbilityDef) -> String:
	if ab == null:
		return ""
	var shown: float = ab.range if (ab.range > 0.0 and ab.target != "self") else -1.0
	# The turret conditions ("조건: 포탑 N 이내") already carry the distance.
	if ab.action == "detonate" or ab.action == "upgrade":
		shown = ab.range
	return _filter_geometry(ab.geometry, shown)


# Same filter driven by already-built meta chips (DESIGN §4 name).
static func dedupe_geometry(meta: Array, geometry: String) -> String:
	var shown: float = -1.0
	for m in meta:
		if m is Dictionary and str(m.get("kind", "")) == "range":
			var t: String = str(m.get("text", "")).replace("사거리", "").strip_edges()
			if t.is_valid_float():
				shown = float(t)
	return _filter_geometry(geometry, shown)


static func _filter_geometry(geometry: String, shown_range: float) -> String:
	_ensure()
	var g: String = geometry.strip_edges()
	if g == "":
		return ""
	var keep: PackedStringArray = PackedStringArray()
	for frag in g.replace("/", ",").split(",", false):
		var f: String = frag.strip_edges()
		if f == "":
			continue
		var m: RegExMatch = _re_range_frag.search(f)
		if m != null:
			var v: float = float(m.get_string(1))
			if v <= 0.0:
				continue
			if shown_range > 0.0 and absf(v - shown_range) < 0.01:
				continue
		keep.append(f)
	return ", ".join(keep)


# ---------------------------------------------------------------- glossary index

# key -> Array of character ids that use the term (descriptions + reliable
# structured effects), in DB order. Cached; used for "사용 영웅" lists.
static func term_index() -> Dictionary:
	if not _term_index.is_empty():
		return _term_index
	DB.ensure_loaded()
	for c in DB.characters:
		var d: Defs.CharDef = c
		var found: Dictionary = {}
		for p in d.passives:
			for k in terms_in(str((p as Dictionary).get("description", ""))):
				found[k] = true
		for a in d.abilities:
			var ab: Defs.AbilityDef = a
			for k in terms_in(ab.description):
				found[k] = true
			if not is_unreliable(ab):
				_effect_terms(ab.effects, found)
		for k in found:
			if not _term_index.has(k):
				_term_index[k] = []
			(_term_index[k] as Array).append(d.id)
	return _term_index


static func heroes_for_term(key: String) -> Array:
	return (term_index().get(key, []) as Array).duplicate()


static func _effect_terms(v: Variant, found: Dictionary) -> void:
	if v is Array:
		for x in v:
			_effect_terms(x, found)
		return
	if not (v is Dictionary):
		return
	var d: Dictionary = v
	var typ: String = str(d.get("type", ""))
	match typ:
		"status", "mark":
			var st: String = str(d.get("status", ""))
			if st == "healReduction" and float(d.get("magnitude", 0.0)) >= 1.0:
				found["healBlock"] = true
			elif CodexData.STATUS.has(st):
				found[st] = true
		"consume_resource":
			if CodexData.STATUS.has(str(d.get("key", ""))):
				found[str(d.key)] = true
		"damage":
			var sc: String = str(SCHOOL_KEYS.get(str(d.get("school", "")), ""))
			if sc != "" and _deals_damage(d):
				found[sc] = true
		"dot":
			found["dot"] = true
		"shield":
			found["shield"] = true
		"summon":
			found["summon"] = true
		"zone":
			found["zone"] = true
		"execute":
			found["execute"] = true
		"projectile_guard":
			found["projectile_guard"] = true
		"cleanse":
			found["cleanse"] = true
		"front_guard":
			found["frontGuard"] = true
		"roar":
			found["roar"] = true
		"displace":
			var mode: String = str(d.get("mode", ""))
			if mode == "knockback":
				found["knockback"] = true
			elif mode.begins_with("pull"):
				found["pull"] = true
	for k in d:
		var sub: Variant = d[k]
		if sub is Array or sub is Dictionary:
			_effect_terms(sub, found)



# ---------------------------------------------------------------- environment log

## Public map events (gates, announced salvos, impacts, the ring) that every
## perspective sees in the battle log.
const ENV_PUBLIC_LOG := ["ENV_GATE", "ENV_ARTILLERY", "ENV_STRIKE", "ENV_RING"]


## Korean BBCode battle-log line for an ENV_* event. target = the hero's display
## name (already coloured / hidden per perspective). Empty for other events.
static func env_log(ev: Dictionary, target: String, deathmatch: bool = false) -> String:
	var ty: String = str(ev.get("type", ""))
	var label: String = CodexData.hazard_label(str(ev.get("hazard_type", "")), deathmatch)
	match ty:
		"ENV_HIT":
			return "[color=#ffb45e]%s[/color] → %s [color=#ffb45e]%d[/color]" % [label, target, int(float(ev.get("amount", 0.0)))]
		"ENV_HASTE":
			return "%s [color=#64e8f0]가속 구역 · 이동 속도 +%d%%[/color]" % [target, int(roundf((float(ev.get("multiplier", 1.0)) - 1.0) * 100.0))]
		"ENV_FOUNTAIN":
			return "%s [color=#65ecc1]공용 회복 샘 +%d[/color]" % [target, int(float(ev.get("amount", 0.0)))]
		"ENV_PORTAL":
			return "%s [color=#a98cff]전장 포탈 이동[/color]" % target
		"ENV_GATE":
			var opened: bool = bool(ev.get("open", false))
			return "[color=#%s]개폐 성문 %s조 %s[/color]" % ["8fe3a0" if opened else "ffb45e", str(ev.get("group", "")), "열림" if opened else "닫힘"]
		"ENV_PUSHED":
			return "%s [color=#ffb45e]닫히는 성문에 밀려남[/color]" % target
		"ENV_ARTILLERY":
			return "[color=#ffd166]포격 예고 · %d발 · %.1f초 후 착탄[/color]" % [(ev.get("points", []) as Array).size(), maxf(0.0, float(ev.get("impact_t", 0.0)) - float(ev.get("t", 0.0)))]
		"ENV_STRIKE":
			return "[color=#ffd166]포격 착탄[/color]"
		"ENV_JUMP":
			return "%s [color=#7fe3ff]도약 발판으로 도약 · %.1f초 비행[/color]" % [target, float(ev.get("flight_time", 0.0))]
		"ENV_RING":
			if str(ev.get("phase", "")) == "final":
				return "[color=#d98bff][b]결계 수축 완료[/b] · 최종 반경 %d[/color]" % int(float(ev.get("final_radius", 0.0)))
			return "[color=#d98bff][b]결계 수축 시작[/b] · 최종 반경 %d까지 줄어듭니다[/color]" % int(float(ev.get("final_radius", 0.0)))
	if ty.begins_with("ENV_"):
		return "[color=#ffb45e]%s[/color] %s" % [label, target]
	return ""
