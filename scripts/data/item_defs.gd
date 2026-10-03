class_name ItemDefs
extends RefCounted

# Deathmatch field items. 28 items, every effect different:
# common 8, rare 6, epic 6, mythic 4, legendary 4. A hero holds up to three.
# "stats" are percentage buffs, "flat" are flat buffs; the other keys are
# special effects implemented by DeathmatchMode. "tags" feed the AI's
# per-hero valuation (see ItemValuation).

const RARITY_NAMES := ["일반", "레어", "에픽", "신화", "전설"]
const RARITY_COLORS := ["#c9d1d9", "#58a6ff", "#bc8cff", "#ff7b5c", "#ffd24a"]
const RARITY_WEIGHTS := [44.0, 26.0, 16.0, 9.0, 5.0]

const ORDER := [
	"c_blade", "c_tome", "c_leather", "c_charm", "c_boots", "c_belt", "c_gloves", "c_spyglass",
	"r_fang", "r_dagger", "r_hourglass", "r_thorns", "r_moss", "r_axe",
	"e_string", "e_guard", "e_berserk", "e_instinct", "e_crystal", "e_shadow",
	"m_phoenix", "m_thunder", "m_bloodstone", "m_chrono",
	"l_heart", "l_crown", "l_aegis", "l_hammer",
]

const DEFS := {
	# ---- common: plain stat bonuses
	"c_blade": {"name": "수련용 검", "rarity": 0, "glyph": "劍", "desc": "공격력 +12%",
		"stats": {"attackDamage": 0.12}, "tags": ["ad"]},
	"c_tome": {"name": "견습 마도서", "rarity": 0, "glyph": "術", "desc": "주문력 +12%",
		"stats": {"abilityPower": 0.12}, "tags": ["ap"]},
	"c_leather": {"name": "가죽 갑옷", "rarity": 0, "glyph": "衣", "desc": "방어력 +18",
		"flat": {"armor": 18.0}, "tags": ["armor"]},
	"c_charm": {"name": "결계 부적", "rarity": 0, "glyph": "印", "desc": "마법 저항력 +18",
		"flat": {"magicResistance": 18.0}, "tags": ["mr"]},
	"c_boots": {"name": "가벼운 장화", "rarity": 0, "glyph": "風", "desc": "이동 속도 +8%",
		"stats": {"moveSpeed": 0.08}, "tags": ["ms"]},
	"c_belt": {"name": "활력의 허리띠", "rarity": 0, "glyph": "生", "desc": "최대 체력 +160 (주운 순간 현재 체력은 늘지 않음)",
		"flat": {"maxHealth": 160.0}, "tags": ["hp"]},
	"c_gloves": {"name": "날렵한 장갑", "rarity": 0, "glyph": "連", "desc": "공격 속도 +12%",
		"stats": {"attackSpeed": 0.12}, "tags": ["as"]},
	"c_spyglass": {"name": "망원경", "rarity": 0, "glyph": "界", "desc": "시야 +140 · 숲 속 적을 60 더 멀리서 발견",
		"vision": 140.0, "forest_reveal": 60.0, "tags": ["vision"]},
	# ---- rare: one mechanic each
	"r_fang": {"name": "흡혈 송곳니", "rarity": 1, "glyph": "吸", "desc": "체력에 입힌 모든 피해의 8%만큼 회복 (스킬·지속 피해 포함)",
		"omnivamp": 0.08, "tags": ["sustain", "dps"]},
	"r_dagger": {"name": "톱날 단검", "rarity": 1, "glyph": "刃", "desc": "기본 공격 적중 시 3초간 매초 대상 최대 체력 1% 물리 피해 (중첩 없이 갱신)",
		"bleed": {"ratio": 0.03, "duration": 3.0}, "tags": ["onhit", "antitank"]},
	"r_hourglass": {"name": "시간의 모래시계", "rarity": 1, "glyph": "旋", "desc": "새로 도는 스킬 재사용 대기시간 -15%",
		"cdr": 0.15, "tags": ["cdr"]},
	"r_thorns": {"name": "가시 흉갑", "rarity": 1, "glyph": "棘", "desc": "영웅의 기본 공격으로 받은 피해의 20%를 마법 피해로 반사 (스킬 제외)",
		"thorns": 0.2, "tags": ["tank", "antibasic"]},
	"r_moss": {"name": "재생의 이끼", "rarity": 1, "glyph": "療", "desc": "피해를 주고받지 않은 지 3초 뒤부터 초당 최대 체력 3% 회복 (기본 7초·1.5%)",
		"regen": {"ratio": 0.015, "delay": 3.0}, "tags": ["sustain"]},
	"r_axe": {"name": "처형자의 도끼", "rarity": 1, "glyph": "斷", "desc": "체력 35% 미만 대상에게 주는 모든 피해 +18%",
		"execute": {"below": 0.35, "bonus": 0.18}, "tags": ["burst", "finisher"]},
	# ---- epic
	"e_string": {"name": "폭풍의 활시위", "rarity": 2, "glyph": "弓", "desc": "기본 공격 사거리 +60 (근접 +20) · 모든 투사체 속도 +15%",
		"range": {"ranged": 60.0, "melee": 20.0}, "stats": {"projectileSpeed": 0.15}, "tags": ["range"]},
	"e_guard": {"name": "수호석", "rarity": 2, "glyph": "巖", "desc": "피해로 체력이 35% 미만이 되면 4초간 최대 체력 25% 보호막 (40초마다, 즉사는 못 막음)",
		"guard": {"below": 0.35, "shield": 0.25, "duration": 4.0, "cooldown": 40.0}, "tags": ["survive"]},
	"e_berserk": {"name": "광전사의 피", "rarity": 2, "glyph": "狂", "desc": "체력 50% 미만일 때 공격 속도 +25%, 공격력 +12%",
		"berserk": {"below": 0.5, "as": 0.25, "ad": 0.12}, "tags": ["ad", "as", "brawl"]},
	"e_instinct": {"name": "사냥 본능", "rarity": 2, "glyph": "獵", "desc": "영웅 처치(막타) 시 최대 체력 30% 회복, 4초간 이동 속도 +30%",
		"hunter": {"heal": 0.3, "ms": 0.3, "duration": 4.0}, "tags": ["snowball", "sustain"]},
	"e_crystal": {"name": "비전 수정", "rarity": 2, "glyph": "球", "desc": "주문력 +18% · 마법 피해 시 대상 마법 저항력 30% 무시",
		"stats": {"abilityPower": 0.18}, "mr_pen": 0.3, "tags": ["ap", "magicpen"]},
	"e_shadow": {"name": "그림자 망토", "rarity": 2, "glyph": "匿", "desc": "숲 속에서 들킬 거리 110→45 · 숲에서 나온 뒤 3초 안의 첫 피해 1회 +30%",
		"shadow": {"reveal": 45.0, "ambush": 0.3, "window": 3.0}, "tags": ["stealth", "burst"]},
	# ---- mythic
	"m_phoenix": {"name": "불사조 깃털", "rarity": 3, "glyph": "翼", "desc": "치명상 1회를 버티고 최대 체력 40%로 되살아나 1.5초 무적 (사용 후 사라짐)",
		"revive": {"hp": 0.4, "invulnerable": 1.5}, "tags": ["survive"]},
	"m_thunder": {"name": "천둥 반지", "rarity": 3, "glyph": "震", "desc": "평타·스킬·소환물 적중 4번마다 벼락: 맞힌 대상 주변 80 적에게 60+0.35AD+0.35AP 마법 피해",
		"thunder": {"every": 4, "base": 60.0, "ad": 0.35, "ap": 0.35, "radius": 80.0}, "tags": ["dps", "area"]},
	"m_bloodstone": {"name": "혈석", "rarity": 3, "glyph": "血", "desc": "체력에 입힌 피해의 12% 회복 · 넘친 회복은 최대 체력 20%까지 보호막으로",
		"omnivamp": 0.12, "bloodstone": {"cap": 0.2}, "tags": ["sustain", "dps"]},
	"m_chrono": {"name": "시간 왜곡 장치", "rarity": 3, "glyph": "反", "desc": "스킬 재사용 대기시간 -10% · 영웅 처치 시 남은 대기시간 절반",
		"cdr": 0.1, "chrono": {"refund": 0.5}, "tags": ["cdr", "snowball"]},
	# ---- legendary
	"l_heart": {"name": "용의 심장", "rarity": 4, "glyph": "脈", "desc": "최대 체력 +30%, 공격력·주문력 +20%, 방어력·마법 저항력 +10%",
		"stats": {"maxHealth": 0.3, "attackDamage": 0.2, "abilityPower": 0.2, "armor": 0.1, "magicResistance": 0.1}, "tags": ["hp", "ad", "ap", "armor", "mr"]},
	"l_crown": {"name": "폭군의 왕관", "rarity": 4, "glyph": "奪", "desc": "영웅 처치(막타)마다 주는 피해 +7% (최대 5중첩, 사망 시 초기화)",
		"tyrant": {"per_kill": 0.07, "max": 5}, "tags": ["snowball", "dps"]},
	"l_aegis": {"name": "성역의 방패", "rarity": 4, "glyph": "盾", "desc": "받는 피해 -18% · 20초마다 둔화 외 군중 제어 1회 무효 (넉백은 못 막음)",
		"aegis": {"reduction": 0.18, "cleanse": 20.0}, "tags": ["tank", "survive", "tenacity"]},
	"l_hammer": {"name": "유성 망치", "rarity": 4, "glyph": "爆", "desc": "기본 공격 적중 시 대상이 받은 피해의 35%를 반경 90 다른 적에게 물리 피해로 · 1초간 20% 둔화",
		"meteor": {"splash": 0.35, "radius": 90.0, "slow": 0.2, "slow_duration": 1.0}, "tags": ["onhit", "area", "dps"]},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func rarity_of(id: String) -> int:
	return int(DEFS.get(id, {}).get("rarity", 0))


static func rarity_color(r: int) -> Color:
	return Color(RARITY_COLORS[clampi(r, 0, 4)])


static func by_rarity(r: int) -> Array:
	var out: Array = []
	for id in ORDER:
		if int(DEFS[id].rarity) == r:
			out.append(id)
	return out
