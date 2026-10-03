class_name ItemValuation
extends RefCounted

# "Is this item what my hero needs?" Every item is scored per hero from how
# the hero's kit actually produces its damage and survives: AD/AP shares of
# its damage output, reliance on basic attacks versus abilities, range,
# durability role, mobility and self-sustain. The held inventory is compared
# with the same function, so swaps only happen for a real improvement.

const RARITY_BASE := [22.0, 36.0, 52.0, 70.0, 88.0]
# Share of each hero's damage to heroes that its basic attacks actually deal in
# deathmatch; the rest comes from abilities and their summons. Measured by
# tools/calibrate_items_15.gd (12 eleven-player matches of 150 s). The kit
# model alone assumes attacks never stop, and overrates basic attacks for
# casters (metatron: model 74%, measured 39%).
const BASIC_SHARE := {"aphrodite": 0.92, "archer": 0.67, "baseball": 0.49, "blood_mage": 0.33, "dimensionalist": 0.88,
	"engineer": 0.38, "fisherman": 0.5, "giant": 0.38, "hermes": 0.63, "hive_mind": 0.28, "joker": 0.41, "mage": 0.39,
	"metatron": 0.39, "nitro": 0.51, "pirate": 0.65, "plague_doctor": 0.42, "sniper": 0.64, "swordsman": 0.51,
	"torturer": 0.53, "werewolf": 0.8, "world_tree": 0.93, "politician": 0.0,
	# V2 (tools/calibrate_items_15.gd rounds 0-5; cerberus bites count as abilities)
	"hades": 0.41,
	# V2: calibrate_items_15 rounds 0-5 (6 matches with war_machine): 16988 / 20545.
	"war_machine": 0.83,
	# V2: torquemada's skills cleanse, root and push; calibration rounds 0-2
	# measured no ability damage at all.
	"torquemada": 1.0,
	# V2: same tool, rounds 0-5 with the 26-hero roster (thirteen-player matches).
	"achilles": 0.55}

static var _profiles: Dictionary = {}


static func profile(d: Defs.CharDef) -> Dictionary:
	if _profiles.has(d.id):
		return _profiles[d.id]
	var st: Dictionary = KitModel.stats_of_def(d)
	var basic: float = KitModel.basic_dps(st, d)
	var ab_total: float = 0.0
	var ab_ad: float = 0.0
	var ab_ap: float = 0.0
	var heals: float = 0.0
	for a in d.abilities:
		var ab: Defs.AbilityDef = a
		var cd: float = maxf(2.0, ab.cooldown)
		var ev: Dictionary = KitModel.evaluate(ab.effects, st, {"max_hp": 1100.0, "hp": 800.0})
		var dmg: float = float(ev.phys) + float(ev.magic) + float(ev.true_dmg)
		heals += (float(ev.heal) + float(ev.shield)) / cd
		if dmg <= 0.0:
			continue
		var st_ad: Dictionary = st.duplicate()
		st_ad.ad = float(st.ad) + 10.0
		var st_ap: Dictionary = st.duplicate()
		st_ap.ap = float(st.ap) + 10.0
		var ev_ad: Dictionary = KitModel.evaluate(ab.effects, st_ad, {"max_hp": 1100.0, "hp": 800.0})
		var ev_ap: Dictionary = KitModel.evaluate(ab.effects, st_ap, {"max_hp": 1100.0, "hp": 800.0})
		var d_ad: float = (float(ev_ad.phys) + float(ev_ad.magic) + float(ev_ad.true_dmg) - dmg) / 10.0 * float(st.ad)
		var d_ap: float = (float(ev_ap.phys) + float(ev_ap.magic) + float(ev_ap.true_dmg) - dmg) / 10.0 * float(st.ap)
		ab_total += dmg / cd
		ab_ad += maxf(0.0, d_ad) / cd
		ab_ap += maxf(0.0, d_ap) / cd
	var total: float = maxf(1.0, basic + ab_total)
	var basic_share: float = clampf(basic / total, 0.0, 1.0)
	if BASIC_SHARE.has(d.id):
		basic_share = float(BASIC_SHARE[d.id])
	if d.has_rule("no_basic") or d.id == "politician":
		basic_share = 0.0
	var ability_share: float = 1.0 - basic_share
	var ab_ad_frac: float = clampf(ab_ad / ab_total, 0.0, 1.0) if ab_total > 0.001 else 0.0
	var ab_ap_frac: float = clampf(ab_ap / ab_total, 0.0, 1.0) if ab_total > 0.001 else 0.0
	var p: Dictionary = {
		"ad": clampf(basic_share + ability_share * ab_ad_frac, 0.0, 1.0),
		"ap": clampf(ability_share * ab_ap_frac, 0.0, 1.0),
		"basic": basic_share,
		"ability": ability_share,
		"ranged": d.stat("attackRange") > 150.0,
		"melee": d.is_melee(),
		"tank": d.role == "FRONTLINE" or d.stat("maxHealth") >= 1300.0,
		"mobile": d.tags.has("MOBILITY"),
		"sustain": heals > 12.0 or d.tags.has("HEALING"),
		"burst": d.tags.has("BURST") or d.tags.has("EXECUTE"),
		"no_basic": d.has_rule("no_basic") or d.id == "politician",
	}
	_profiles[d.id] = p
	return p


static func _fit(p: Dictionary, tag: String) -> Array:
	# [multiplier, reason]
	var melee: float = 1.0 if p.melee else 0.0
	var tank: float = 1.0 if p.tank else 0.0
	match tag:
		"ad":
			return [0.25 + 1.35 * float(p.ad), "공격력 계수 비중 %d%%" % int(float(p.ad) * 100.0)]
		"ap":
			return [0.25 + 1.35 * float(p.ap), "주문력 계수 비중 %d%%" % int(float(p.ap) * 100.0)]
		"as":
			if p.no_basic:
				return [0.05, "기본 공격을 쓰지 않음"]
			return [0.2 + 1.5 * float(p.basic), "기본 공격 의존 %d%%" % int(float(p.basic) * 100.0)]
		"range":
			if p.no_basic:
				return [0.05, "기본 공격을 쓰지 않음"]
			if p.ranged:
				return [0.6 + 1.1 * float(p.basic), "원거리 기본 공격 의존 %d%%" % int(float(p.basic) * 100.0)]
			return [0.3, "근접이라 사거리 효과가 작음"]
		"cdr":
			return [0.25 + 1.4 * float(p.ability), "스킬 피해 비중 %d%%" % int(float(p.ability) * 100.0)]
		"armor", "mr":
			return [0.65 + 0.55 * tank + 0.2 * melee, "전방 탱커 방어 보강" if p.tank else "방어 보강"]
		"hp":
			return [0.8 + 0.4 * tank, "체력 보강"]
		"ms":
			return [0.7 + 0.35 * melee + (0.0 if p.mobile else 0.25), "기동 수단 보강" if not p.mobile else "이동 보강"]
		"vision":
			return [0.55 + (0.35 if p.ranged else 0.0), "시야 확보"]
		"sustain":
			return [0.65 + (0.0 if p.sustain else 0.45), "자가 회복 수단 부족" if not p.sustain else "지속 교전 회복"]
		"dps":
			return [0.9, "지속 피해 증가"]
		"onhit":
			if p.no_basic:
				return [0.05, "기본 공격을 쓰지 않음"]
			return [0.2 + 1.5 * float(p.basic), "기본 공격 적중 효과 · 의존 %d%%" % int(float(p.basic) * 100.0)]
		"antitank", "antibasic":
			return [0.8, "상대 유형 대응"]
		"tank":
			return [0.35 + 0.9 * tank * (0.6 + 0.4 * melee), "근접 탱커 반격" if p.tank else "탱커가 아니라 효과 작음"]
		"burst", "finisher":
			return [0.8 + (0.35 if p.burst else 0.0), "마무리 피해"]
		"survive":
			return [0.95 + (0.0 if p.mobile else 0.2), "위기 생존"]
		"brawl":
			return [0.35 + 1.0 * melee * (0.4 + 0.6 * float(p.basic)), "근접 난전" if p.melee else "원거리라 효과 작음"]
		"snowball":
			return [1.0, "처치 연쇄 이득"]
		"magicpen":
			return [0.2 + 1.4 * float(p.ap), "마법 피해 관통 · 주문력 비중 %d%%" % int(float(p.ap) * 100.0)]
		"stealth":
			return [0.55 + 0.5 * melee + (0.25 if p.burst else 0.0), "숲 기습 진입" if p.melee else "숲 은신"]
		"area":
			return [0.9, "광역 피해"]
		"tenacity":
			return [0.9 + 0.2 * melee, "제어 무효"]
	return [0.8, ""]


# Value of one item for this hero (0..~140) and the main reason.
static func value(d: Defs.CharDef, item_id: String, held: Array = []) -> Dictionary:
	var item: Dictionary = ItemDefs.get_def(item_id)
	if item.is_empty():
		return {"value": 0.0, "reason": ""}
	var p: Dictionary = profile(d)
	var tags: Array = item.get("tags", [])
	var fit_sum: float = 0.0
	var best_reason: String = ""
	var best_fit: float = -1.0
	var worst_reason: String = ""
	var worst_fit: float = 99.0
	for tag in tags:
		var f: Array = _fit(p, str(tag))
		fit_sum += float(f[0])
		if float(f[0]) > best_fit:
			best_fit = float(f[0])
			best_reason = str(f[1])
		if float(f[0]) < worst_fit:
			worst_fit = float(f[0])
			worst_reason = str(f[1])
	var fit: float = fit_sum / maxf(1.0, tags.size()) if not tags.is_empty() else 0.8
	# Overlapping effects saturate (cooldown reduction caps, stacked stats).
	for other in held:
		if str(other) == item_id:
			continue
		var other_tags: Array = ItemDefs.get_def(str(other)).get("tags", [])
		for tag in tags:
			if other_tags.has(tag):
				fit *= 0.88
				break
	var v: float = float(RARITY_BASE[int(item.rarity)]) * fit
	return {"value": v, "reason": best_reason if fit >= 0.7 else worst_reason, "fit": fit}


# Pickup decision for an item under the hero's feet.
static func decide(d: Defs.CharDef, item_id: String, held: Array, slots: int) -> Dictionary:
	var name: String = str(ItemDefs.get_def(item_id).get("name", item_id))
	if held.has(item_id):
		return {"take": false, "reason": "%s 무시 — 이미 보유 (효과 중첩 없음)" % name, "value": 0.0}
	var new_v: Dictionary = value(d, item_id, held)
	if held.size() < slots:
		if float(new_v.value) < 6.0:
			return {"take": false, "reason": "%s 무시 — %s" % [name, new_v.reason], "value": new_v.value}
		return {"take": true, "reason": "%s 획득 — %s" % [name, new_v.reason], "value": new_v.value}
	var worst: int = -1
	var worst_v: float = INF
	for k in held.size():
		var others: Array = held.duplicate()
		others.remove_at(k)
		var hv: float = float(value(d, str(held[k]), others).value)
		if hv < worst_v:
			worst_v = hv
			worst = k
	var others2: Array = held.duplicate()
	if worst >= 0:
		others2.remove_at(worst)
	var swap_v: float = float(value(d, item_id, others2).value)
	if worst >= 0 and swap_v > worst_v * 1.15 + 3.0:
		var old_name: String = str(ItemDefs.get_def(str(held[worst])).get("name", ""))
		return {"take": true, "drop_slot": worst, "reason": "%s ↔ %s 교체 — %s" % [name, old_name, new_v.reason], "value": swap_v, "gain": swap_v - worst_v}
	return {"take": false, "reason": "%s 무시 — 보유품이 더 유용 (%s)" % [name, new_v.reason], "value": swap_v}


# Improvement this item would bring to the current inventory (0 if none).
static func gain(d: Defs.CharDef, item_id: String, held: Array, slots: int) -> float:
	var r: Dictionary = decide(d, item_id, held, slots)
	if not bool(r.take):
		return 0.0
	return float(r.get("gain", r.value))


# --- V2 scale (B-PERF2): caching wrapper ---
# gain() is a pure function of (hero definition, item, held inventory in
# order, slots): profile() is already cached per hero id, and value() /
# decide() read only that profile and the static item table. The deathmatch
# loot scan asks the same question for every field item at every intent
# update, so the answer is memoised under that key. A cached answer is the
# exact answer; the memo is simply dropped when it grows past MEMO_LIMIT.
const MEMO_LIMIT := 4096
static var _gain_memo: Dictionary = {}


static func gain_cached(d: Defs.CharDef, item_id: String, held: Array, slots: int) -> float:
	var key: String = "%s|%s|%d|%s" % [d.id, item_id, slots, str(held)]
	var hit = _gain_memo.get(key)
	if hit != null:
		return hit
	var g: float = gain(d, item_id, held, slots)
	if _gain_memo.size() >= MEMO_LIMIT:
		_gain_memo.clear()
	_gain_memo[key] = g
	return g
