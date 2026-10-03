class_name CodexData
extends RefCounted

# Codex knowledge layer (V1.5.1): the status/term glossary, item detail lines,
# deathmatch item rules, arena hazard explanations and mode rules. Pure display
# data and tiny lookups; nothing here is read by the simulation. Numbers were
# checked against sim.gd, kits.gd, deathmatch_mode.gd, arena_env.gd, zones.gd,
# domination_mode.gd and the data files (tests/codex_data_151.gd re-checks the
# item and hazard numbers against the live data).
#
# Glyphs are limited to the bundled fonts (ui_*.otf, glyph_serif.otf,
# symbols.ttf); render icons with DB.font_glyph.

const CATEGORIES := ["군중 제어", "해로운 효과", "이로운 효과", "표식·자원", "피해·규칙"]

# key -> {label, icon, color, category, desc, aliases}
# Keys are the engine status ids where one exists (DB.STATUS_LABELS), otherwise
# a short English id. Descriptions are complete polite sentences because they
# are shown as tooltips.
const STATUS := {
	# ---------------------------------------------------------------- 군중 제어
	"stun": {"label": "기절", "icon": "✦", "color": "#ffe066", "category": "군중 제어",
		"desc": "이동·평타·스킬을 모두 할 수 없고 준비 중인 시전이 취소됩니다.", "aliases": []},
	"root": {"label": "속박", "icon": "◎", "color": "#8fd46a", "category": "군중 제어",
		"desc": "걸어서 이동할 수 없습니다. 평타와 스킬(순간이동 포함)은 쓸 수 있지만 진행 중인 접촉 돌진은 멈춥니다.", "aliases": []},
	"silence": {"label": "침묵", "icon": "✕", "color": "#c49bff", "category": "군중 제어",
		"desc": "스킬을 쓸 수 없고 준비 중인 스킬이 취소됩니다. 이동과 평타는 할 수 있습니다.", "aliases": []},
	"airborne": {"label": "에어본", "icon": "↑", "color": "#e6f2ff", "category": "군중 제어",
		"desc": "공중에 떠 이동·평타·스킬을 모두 할 수 없고 시전이 취소됩니다. 강인함으로 줄어들지 않습니다.", "aliases": ["공중에 뜸"]},
	"suppression": {"label": "제압", "icon": "■", "color": "#ff7aa8", "category": "군중 제어",
		"desc": "이동·평타·스킬을 모두 할 수 없고 시전이 취소됩니다. 강인함으로 줄어들지 않습니다.", "aliases": []},
	"charm": {"label": "유혹", "icon": "♥", "color": "#ff8fbe", "category": "군중 제어",
		"desc": "평타와 스킬을 쓸 수 없고 유혹한 지점으로 걸어가거나 제자리에 멈춥니다. 이미 준비 중인 시전은 취소되지 않습니다.", "aliases": ["매혹"]},
	"taunt": {"label": "도발", "icon": "!", "color": "#ff9a5b", "category": "군중 제어",
		"desc": "스킬을 쓸 수 없고 진행 중인 시전과 돌진이 취소됩니다. 지정된 대상이 있으면 그 대상만 쫓아가 평타로 공격합니다.", "aliases": ["강제 도발", "하드 도발"]},
	"sleep": {"label": "수면", "icon": "z", "color": "#98e8e1", "category": "군중 제어",
		"desc": "이동·평타·스킬을 모두 할 수 없습니다. 체력 피해를 받으면 즉시 깨어납니다.", "aliases": []},
	"control": {"label": "조종", "icon": "◈", "color": "#b276e8", "category": "군중 제어",
		"desc": "지속 시간 동안 조종한 쪽 편으로 싸워 원래 아군을 공격하고 공격받습니다. 강인함으로 줄어들지 않습니다.", "aliases": ["조종권"]},
	"slow": {"label": "둔화", "icon": "↓", "color": "#7cc4ff", "category": "군중 제어",
		"desc": "이동 속도가 줄어듭니다. 여러 둔화가 겹치면 가장 강한 하나만 적용되며 최대 90%입니다.", "aliases": []},
	"disarm": {"label": "무장 해제", "icon": "⊘", "color": "#ffb45e", "category": "군중 제어",
		"desc": "평타를 쓸 수 없고 소환물은 공격하지 못합니다. 이동과 스킬은 할 수 있습니다.", "aliases": []},
	"knockback": {"label": "넉백", "icon": "⇥", "color": "#f2a65a", "category": "군중 제어",
		"desc": "지정된 방향으로 강제로 밀려나며 벽에 막히면 멈춥니다. 상태 이상이 아닌 강제 이동이라 성역의 방패로 막을 수 없고, 저지 불가·무적·관조 중에는 밀리지 않습니다.", "aliases": ["밀쳐내기", "밀쳐냄", "밀쳐낸다", "밀려난"]},
	"pull": {"label": "끌어당김", "icon": "牽", "color": "#8fc3ef", "category": "군중 제어",
		"desc": "시전자 쪽으로 강제로 끌려옵니다. 벽에 걸리면 도중에 멈추며 저지 불가·무적 대상은 끌리지 않습니다.", "aliases": ["끌어오기", "끌어온다", "끌어당긴다", "끌려온"]},
	# ---------------------------------------------------------------- 해로운 효과
	"healReduction": {"label": "치유 감소", "icon": "✚", "color": "#9dbd72", "category": "해로운 효과",
		"desc": "받는 회복량이 줄어듭니다(기본 35%). 역병과 겹치면 가장 강한 효과 하나만 적용되고, 100%가 되면 회복 불가입니다.", "aliases": ["받는 치유 감소", "받는 회복 감소"]},
	"healBlock": {"label": "회복 불가", "icon": "裂", "color": "#8f7cff", "category": "해로운 효과",
		"desc": "받는 회복이 100% 줄어 체력을 전혀 회복할 수 없습니다. 일부만 줄이는 치유 감소와 달리 회복이 하나도 들어가지 않으며, 보호막과 소생은 막지 않습니다. 하데스의 명계 위반이 타격 뒤 체력 15% 미만인 적에게 5초 동안 겁니다. 정화로 지울 수 있습니다.", "aliases": ["회복 차단"]},
	"damageAmp": {"label": "받는 피해 증가", "icon": "▲", "color": "#ff8a8a", "category": "해로운 효과",
		"desc": "받는 모든 피해가 늘어납니다. 같은 종류는 가장 강한 값만, 서로 다른 종류는 곱해서 적용됩니다.", "aliases": []},
	"sniperVulnerable": {"label": "취약 낙인", "icon": "印", "color": "#edb94f", "category": "해로운 효과",
		"desc": "저격수의 취약 탄환이 남기는 4초 표식입니다. 받는 모든 피해가 16% 늘어나며, 낙인을 건 평타 자체는 증폭되지 않습니다.", "aliases": ["취약"]},
	"confusion": {"label": "혼란", "icon": "?", "color": "#b88be9", "category": "해로운 효과",
		"desc": "중첩당 받는 피해 +3%, 강인함 −2.5%p입니다(최대 5중첩, 7초, 쌓일 때 갱신). 조커의 계수 뒤집기가 모두 소비합니다.", "aliases": []},
	"plague": {"label": "역병", "icon": "疫", "color": "#84bd72", "category": "해로운 효과",
		"desc": "중첩당 받는 회복 −10%입니다(최대 6중첩 −60%, 7초). 줄어든 회복량은 역병의사의 힐 주머니에 저장됩니다.", "aliases": []},
	"pain": {"label": "고통", "icon": "痛", "color": "#e789ba", "category": "해로운 효과",
		"desc": "중첩당 1초마다 2+0.035AD 물리 피해와 이동 속도 −4%를 받습니다(최대 6중첩). 5초 동안 새로 쌓이지 않으면 모두 사라집니다.", "aliases": []},
	"imprisoned": {"label": "감금", "icon": "獄", "color": "#c05a9a", "category": "해로운 효과",
		"desc": "고문가의 원통 벽에 3.5초 갇혀 방어력이 25% 줄어듭니다. 벽 안팎으로 이동·돌진·순간이동을 할 수 없고 안에서는 평타·스킬을 쓸 수 있습니다.", "aliases": []},
	"roar": {"label": "포효", "icon": "吼", "color": "#f0a548", "category": "해로운 효과",
		"desc": "아킬레우스의 포효로 6초 동안 강인함이 10% 낮아집니다. 포효만은 강인함을 0 아래(최저 -30%)로 내려 군중 제어 지속 시간을 늘릴 수 있고, 정화로 지울 수 있습니다.", "aliases": []},
	# ---------------------------------------------------------------- 이로운 효과
	"invulnerable": {"label": "무적", "icon": "◇", "color": "#ffd66b", "category": "이로운 효과",
		"desc": "모든 피해·해로운 효과·표식·강제 이동·처형을 받지 않습니다. 투사체는 맞고 사라집니다.", "aliases": []},
	"unstoppable": {"label": "저지 불가", "icon": "▶", "color": "#f4f7ff", "category": "이로운 효과",
		"desc": "군중 제어·해로운 효과와 넉백·끌어당김을 받지 않고 진행 중인 행동이 끊기지 않습니다. 피해는 그대로 받습니다.", "aliases": []},
	"untargetable": {"label": "대상 지정 불가", "icon": "◌", "color": "#dfe8ff", "category": "이로운 효과",
		"desc": "적의 대상 지정과 시야에서 빠져 지정 스킬과 평타의 목표가 될 수 없고 해로운 효과도 받지 않습니다.", "aliases": []},
	"invisible": {"label": "투명", "icon": "匿", "color": "#9fb4d6", "category": "이로운 효과",
		"desc": "적에게 보이지 않습니다. 적과 62 이내로 붙거나 피격 0.55초·교전 0.35초 이내에는 드러나며, 평타나 적 대상 스킬을 쓰면 풀립니다.", "aliases": []},
	"shield": {"label": "보호막", "icon": "盾", "color": "#cfe3ff", "category": "이로운 효과",
		"desc": "체력보다 먼저 피해를 흡수합니다. 지속 시간이 끝나면 남은 양은 사라집니다.", "aliases": []},
	"projectile_guard": {"label": "투사체 방어", "icon": "帽", "color": "#ffc19b", "category": "이로운 효과",
		"desc": "지속 시간 동안 받는 투사체 피해가 줄어듭니다(포수 헬멧 50%). 원거리 평타와 폭발탄에도 적용됩니다.", "aliases": []},
	"contemplation": {"label": "관조", "icon": "空", "color": "#ecd998", "category": "이로운 효과",
		"desc": "정치가가 0.45초 이상 제자리에 있으면 발동합니다. 스킬 계수 +30%, 모든 군중 제어 해제·무효, 넉백·위치 교환을 무시하며 움직이면 풀립니다.", "aliases": []},
	"frenzy": {"label": "광란", "icon": "狂", "color": "#ff706d", "category": "이로운 효과",
		"desc": "아프로디테의 불화의 사과로 3초 동안 이동 속도 +90%를 얻고, 볼 수 있는 가장 약한 적 영웅에게 강제로 달려갑니다(평타·스킬은 자유).", "aliases": []},
	"cleanse": {"label": "정화", "icon": "療", "color": "#ffd77a", "category": "이로운 효과",
		"desc": "모든 군중 제어와 해로운 효과(치유 감소·받는 피해 증가·취약 낙인·혼란·역병·고통·포효), 적이 건 지속 피해와 능력치 감소를 없앱니다. 감금·스킬 봉인·표식과 이로운 효과는 남습니다.", "aliases": []},
	"concealed": {"label": "암흑시야", "icon": "霧", "color": "#8f7cff", "category": "이로운 효과",
		"desc": "적에게 보이지 않는 위치에 있는 상태입니다. 투명하거나, 수풀 안에 있거나, 우리 팀이 보고 있는 적 중 나를 관측하는 적이 없으면 해당합니다. 하데스의 키네에(재생)와 망자 소환의 조건입니다.", "aliases": ["은신", "암흑 시야"]},
	"overdrive": {"label": "과열 폭주", "icon": "燃", "color": "#ff7a3a", "category": "이로운 효과",
		"desc": "전쟁 기계의 연료탱크가 파괴되면 10초 동안 공격 속도와 이동 속도가 1.5배가 되고 S1만 쓸 수 있습니다(S1은 연료 소모 없음). 정화로 지워지지 않습니다.", "aliases": []},
	"frontGuard": {"label": "전방 방패", "icon": "壁", "color": "#d9a24f", "category": "이로운 효과",
		"desc": "아킬레우스가 조준한 방향 120° 앞에서 오는 투사체·직접 피해·군중 제어·넉백을 막습니다(전방 무적). 장판·지속 피해와 옆·뒤에서 오는 공격은 막지 못하며, 방패를 든 동안 이동 속도가 35% 느려지고 바라보는 방향이 고정됩니다.", "aliases": ["전방 무적"]},
	# ---------------------------------------------------------------- 표식·자원
	"infection": {"label": "감염", "icon": "寄", "color": "#c26ed0", "category": "표식·자원",
		"desc": "기생충에게 물릴 때 쌓이는 표식입니다(최대 4, 8초). 자체 효과는 없고 하이브 마인드의 군체 조종 조건입니다.", "aliases": []},
	"hooked": {"label": "인양", "icon": "鉤", "color": "#67c8d8", "category": "표식·자원",
		"desc": "낚시꾼이 곁까지 끌어온 적에게 3초 동안 남는 표식입니다. 사시미 결착의 사용 조건입니다.", "aliases": ["인양 완료", "인양 표식"]},
	"bladeMark": {"label": "검흔", "icon": "月", "color": "#83c0ff", "category": "표식·자원",
		"desc": "검사의 초승달 낙인이 남기는 4초 표식입니다. 이 검사의 S1·S3·S4가 적중하면 16+0.18AD 추가 물리 피해를 줍니다(0.4초 간격).", "aliases": []},
	"bladeTrace": {"label": "검기 추적", "icon": "封", "color": "#89ddff", "category": "표식·자원",
		"desc": "검사의 침묵의 검기가 남기는 4초 표식입니다. 배후 절단의 사용 조건이며 자신이 건 추적만 쓸 수 있습니다.", "aliases": []},
	"fuel": {"label": "연료", "icon": "⚙", "color": "#ff8a3d", "category": "표식·자원",
		"desc": "전쟁 기계의 자원입니다(0~10). 등 뒤 연료탱크가 있을 때 적 영웅이나 소환물을 평타로 맞히면 2씩 차고, 스킬·장판 피해로는 차지 않습니다. 부스터 1, 유도폭격 1발마다 1, 제노사이드 7을 쓰며 탱크가 파괴되면 0이 됩니다.", "aliases": ["연료탱크"]},
	"distrust": {"label": "불신", "icon": "≠", "color": "#d6b979", "category": "표식·자원",
		"desc": "정치가의 가짜 뉴스가 쌓는 팀 단위 수치입니다(최대 10). 10이 되면 거짓 정보가 모두 풀리고, 화제 돌리기로 0이 됩니다.", "aliases": []},
	# ---------------------------------------------------------------- 피해·규칙
	"physical": {"label": "물리 피해", "icon": "刃", "color": "#ff9a6b", "category": "피해·규칙",
		"desc": "방어력으로 줄어드는 피해입니다. 받는 배율은 100÷(100+방어력)입니다.", "aliases": []},
	"magic": {"label": "마법 피해", "icon": "術", "color": "#b58cff", "category": "피해·규칙",
		"desc": "마법 저항력으로 줄어드는 피해입니다. 받는 배율은 100÷(100+마법 저항력)입니다.", "aliases": []},
	"true": {"label": "고정 피해", "icon": "◆", "color": "#eaf0fa", "category": "피해·규칙",
		"desc": "방어력과 마법 저항력을 무시하는 피해입니다. 보호막에는 흡수됩니다.", "aliases": []},
	"crit": {"label": "치명타", "icon": "★", "color": "#f4c96b", "category": "피해·규칙",
		"desc": "평타에만 발생합니다. 대부분의 영웅은 확률 8%, 피해 1.65배입니다.", "aliases": []},
	"dot": {"label": "지속 피해", "icon": "毒", "color": "#e6a36b", "category": "피해·규칙",
		"desc": "일정 간격으로 반복해서 들어오는 피해입니다. 같은 효과로 다시 맞히면 대부분 중첩 없이 지속 시간이 갱신됩니다.", "aliases": ["도트", "출혈"]},
	"execute": {"label": "처형", "icon": "斷", "color": "#ff6d79", "category": "피해·규칙",
		"desc": "체력이 기준 이하인 적을 보호막과 관계없이 즉시 쓰러뜨립니다. 무적 대상은 처형할 수 없습니다.", "aliases": []},
	"lifesteal": {"label": "흡혈", "icon": "吸", "color": "#ff8f9a", "category": "피해·규칙",
		"desc": "입힌 피해의 일부만큼 체력을 회복합니다. 보호막에 막힌 피해는 제외되고 치유 감소가 적용됩니다.", "aliases": ["피해 흡혈"]},
	"tenacity": {"label": "강인함", "icon": "巖", "color": "#e0a45f", "category": "피해·규칙",
		"desc": "군중 제어 지속 시간을 줄입니다(영웅 기본 5%, 최대 95%). 에어본·제압·조종에는 적용되지 않습니다.", "aliases": []},
	"cooldown": {"label": "재사용 대기시간", "icon": "↻", "color": "#a9b6cc", "category": "피해·규칙",
		"desc": "스킬을 다시 쓰기까지 기다려야 하는 시간입니다.", "aliases": ["쿨타임", "쿨다운", "대기시간", "CD"]},
	"zone": {"label": "장판", "icon": "◉", "color": "#f0b86b", "category": "피해·규칙",
		"desc": "바닥에 일정 시간 남아 안에 있는 대상에게 반복해서 효과를 주는 영역입니다.", "aliases": []},
	"charge": {"label": "차징", "icon": "⚡", "color": "#ffb36b", "category": "피해·규칙",
		"desc": "준비(충전) 시간을 늘릴수록 위력이 커지는 시전 방식입니다. 전쟁 기계의 유도폭격은 2발에 0.2초, 1발마다 0.3초씩 더 충전해 최대 6발(1.4초)을 쏩니다. 충전 중에는 이동 속도가 40% 느려지고, 기절 등으로 취소되면 연료를 쓰지 않습니다.", "aliases": ["충전"]},
	"basicResist": {"label": "평타 저항", "icon": "金", "color": "#c98b3a", "category": "피해·규칙",
		"desc": "평타로 받는 피해를 계산할 때만 방어력이 늘어납니다. 아킬레우스의 스틱스의 축복은 방어력을 30% 높여, 같은 물리 피해라도 평타로 받으면 스킬로 받을 때보다 적게 받습니다.", "aliases": ["평타 피해 저항", "평타로 받는 피해"]},
	"charmTenacity": {"label": "유혹 강인함", "icon": "♡", "color": "#ff8fbe", "category": "피해·규칙",
		"desc": "유혹에만 추가로 적용되는 강인함입니다. 일반 강인함과 곱으로 적용되어, 토르케마다(강인함 35%, 유혹 강인함 50%)는 유혹 지속 시간이 원래의 32.5%입니다.", "aliases": ["매혹 강인함", "유혹에 대한 강인함"]},
	"summon": {"label": "소환물", "icon": "群", "color": "#b6e36a", "category": "피해·규칙",
		"desc": "스킬로 만든 유닛입니다(뱀·새끼·기생충·포탑·나무·케르베로스·망자·전차 등). 소환물이 준 피해는 주인의 피해로 계산됩니다.", "aliases": ["소환"]},
	# V2 battleground (DESIGN_V2 §3.1 / §3.3; numbers from BattlegroundMode / BrZone).
	"downed": {"label": "다운", "icon": "▼", "color": "#ff8a8a", "category": "피해·규칙",
		"desc": "배틀그라운드 듀오·트리오에서 치명적인 피해를 받은 영웅은 바로 쓰러지지 않고 다운됩니다. 체력 400의 별도 체력으로 이동 속도 35%로 기어서만 움직이고 공격과 스킬을 쓸 수 없으며, 지닌 아이템은 그대로 둡니다. 다운된 동안 자기장을 포함한 모든 피해를 50%만 받습니다. 첫 다운은 30초, 두 번째는 20초, 그 뒤로는 10초가 지나거나 다운 체력이 0이 되면 사망합니다. 군중 제어가 아니어서 정화로 풀리지 않고, 팀원이 모두 다운되거나 쓰러지면 팀이 탈락합니다.", "aliases": ["기절(다운)", "다운 상태"]},
	"revive": {"label": "소생", "icon": "救", "color": "#6fe0a2", "category": "피해·규칙",
		"desc": "다운된 팀원 곁 60 거리 안에서 5초 동안 집중하면 그 팀원이 최대 체력 25%로 일어납니다. 소생하는 영웅이 적에게 피해를 받거나 60 거리를 벗어나거나 기절 같은 강한 군중 제어에 걸리면 끊깁니다. 회복이 아니므로 회복 불가의 영향을 받지 않습니다.", "aliases": []},
	"br_zone": {"label": "자기장", "icon": "⊙", "color": "#cf9bff", "category": "피해·규칙",
		"desc": "배틀그라운드에서 6단계에 걸쳐 줄어드는 안전 지대입니다. 다음 원은 수축이 시작되기 전에 미리 공개되고, 원 밖에 있으면 0.5초마다 최대 체력 비율의 고정 피해(1단계 초당 1%부터 6단계 초당 12%까지)를 받습니다. 자기장 피해는 수풀 은신을 드러내지 않고 전투 이탈 회복 타이머도 초기화하지 않지만, 피해가 들어오는 원 밖에서는 회복하지 않습니다. 결계 수축과는 다른 규칙입니다.", "aliases": ["자기장 피해"]},
}

# AI valuation tags on items (ItemDefs.DEFS[*].tags) -> Korean chip labels.
const ITEM_TAG_LABELS := {
	"ad": "공격력", "ap": "주문력", "as": "공격 속도", "range": "사거리", "cdr": "스킬 가속",
	"armor": "방어", "mr": "마법 방어", "hp": "체력", "ms": "이동", "vision": "시야",
	"sustain": "회복", "dps": "지속 딜", "onhit": "적중 효과", "antitank": "탱커 대응",
	"antibasic": "평타 대응", "tank": "탱커", "burst": "폭발", "finisher": "마무리",
	"survive": "생존", "brawl": "근접 난전", "snowball": "연쇄 처치", "magicpen": "마법 관통",
	"stealth": "은신", "area": "광역", "tenacity": "제어 무효",
}

# item id -> short detail lines (hidden rules included). Verified against
# DeathmatchMode (_apply_item, outgoing_mult, incoming_mult, block_cc, on_heal,
# on_damage, try_revive, _on_kill_items, _quarter_second_effects).
const ITEM_DETAILS := {
	"c_blade": [
		"기본 공격력의 12%만큼 오릅니다(다른 % 증가와 합산).",
		"평타와 공격력 계수 스킬·포탑 피해가 모두 커집니다.",
	],
	"c_tome": [
		"기본 주문력의 12%만큼 오릅니다(다른 % 증가와 합산).",
		"주문력 계수가 붙은 피해·회복·보호막·소환물이 모두 강해집니다.",
	],
	"c_leather": [
		"방어력이 18 오릅니다(고정값).",
		"받는 물리 피해 배율은 100÷(100+방어력)입니다.",
	],
	"c_charm": [
		"마법 저항력이 18 오릅니다(고정값).",
		"받는 마법 피해 배율은 100÷(100+마법 저항력)이며 천둥 반지·가시 흉갑 같은 아이템 마법 피해에도 적용됩니다.",
	],
	"c_boots": [
		"기본 이동 속도의 8%만큼 빨라집니다(다른 % 증가와 합산).",
		"둔화는 늘어난 속도에 곱해서 적용됩니다.",
	],
	"c_belt": [
		"최대 체력이 160 오릅니다(고정값).",
		"주운 순간 현재 체력은 그대로이며 늘어난 만큼은 회복으로 채워야 합니다.",
	],
	"c_gloves": [
		"기본 공격 속도의 12%만큼 빨라집니다(다른 % 증가와 합산).",
		"평타를 쓰지 않는 영웅(정치가)에게는 효과가 없습니다.",
	],
	"c_spyglass": [
		"시야가 560에서 700으로 넓어집니다.",
		"숲에 숨은 적을 110이 아닌 170 거리에서 발견합니다(그림자 망토 착용자는 45 → 75).",
		"거리는 몸 가장자리 기준입니다.",
	],
	"r_fang": [
		"체력에 입힌 피해의 8%만큼 회복합니다(보호막에 막힌 피해는 제외).",
		"스킬·지속 피해·소환물·아이템 피해도 포함되며 치유 감소가 적용됩니다.",
		"혈석과 합산됩니다(최대 20%).",
	],
	"r_dagger": [
		"평타가 적중할 때마다 3초 동안 1초마다 대상 최대 체력 1%의 물리 피해를 줍니다(총 3%).",
		"중첩되지 않고 다시 맞히면 3초로 갱신됩니다.",
		"방어력으로 줄어들며 소환물에게도 적용됩니다.",
	],
	"r_hourglass": [
		"새로 시작하는 재사용 대기시간이 15% 짧아집니다.",
		"대기시간 감소는 합산되며 최대 40%입니다(현재 조합으로는 최대 25%).",
		"이미 돌고 있는 대기시간에는 적용되지 않습니다.",
	],
	"r_thorns": [
		"영웅의 평타로 받은 피해에만 발동합니다(스킬·소환물·포탑 제외).",
		"방어 적용 후 실제로 받은 피해(보호막 흡수 포함)의 20%를 마법 피해로 돌려줍니다.",
		"반사 피해는 공격자의 마법 저항력으로 다시 줄어듭니다.",
	],
	"r_moss": [
		"피해를 주거나 받지 않은 지 3초 뒤부터 초당 최대 체력 3%를 회복합니다.",
		"기본 전투 이탈 회복은 7초 뒤 초당 1.5%입니다.",
		"치유 감소가 적용됩니다.",
	],
	"r_axe": [
		"적중 직전 대상의 체력이 35% 미만이면 모든 피해가 1.18배가 됩니다.",
		"지속 피해·소환물·아이템 피해도 포함되며 소환물 대상에게도 적용됩니다.",
	],
	"e_string": [
		"원거리 영웅(기본 사거리 100 초과)은 평타 사거리 +60, 근접 영웅은 +20입니다.",
		"투사체 속도 +15%는 평타·스킬·포탑 탄환 모두에 적용됩니다.",
	],
	"e_guard": [
		"피해로 체력이 35% 미만이 되는 순간 최대 체력 25%의 보호막을 4초 동안 얻습니다.",
		"재사용 대기시간은 40초이며 사망하면 초기화됩니다.",
		"즉사 피해는 막지 못하고 아이템 효과 피해로는 발동하지 않습니다.",
	],
	"e_berserk": [
		"0.25초마다 체력을 확인해 50% 미만인 동안 공격 속도 +25%, 공격력 +12%(기본 수치 기준)를 얻습니다.",
		"체력이 50% 이상으로 회복되면 즉시 사라집니다.",
	],
	"e_instinct": [
		"영웅을 처치(막타)할 때마다 최대 체력 30%를 회복합니다(치유 감소 적용).",
		"4초 동안 이동 속도 +30%를 얻으며 연속 처치 시 중첩 없이 갱신됩니다.",
		"소환물·지속 피해로 한 처치도 포함되고 도움은 제외됩니다.",
	],
	"e_crystal": [
		"기본 주문력의 18%만큼 오릅니다.",
		"마법 피해를 줄 때 대상 마법 저항력의 30%를 무시합니다(소환물·천둥 반지·가시 흉갑 반사 포함).",
	],
	"e_shadow": [
		"숲에 숨어 있는 동안 적 영웅은 45 이내(망원경 착용자 75)로 와야 나를 발견합니다.",
		"숲에서 나온 뒤 3초 안에 주는 첫 피해 1회만 30% 커집니다(스킬·지속 피해 포함).",
		"교전 직후 0.8초 동안은 숲 안에서도 드러납니다.",
	],
	"m_phoenix": [
		"치명상(지속 피해 포함)을 입으면 한 번 쓰러지지 않고 최대 체력 40%로 되살아나 1.5초 무적이 됩니다.",
		"되살아날 때 모든 군중 제어가 풀리고 보호막은 유지되며 상대는 처치를 얻지 못합니다.",
		"사용하면 사라지며 떨어뜨리지 않습니다.",
	],
	"m_thunder": [
		"적중 4번마다 벼락이 떨어져 맞힌 대상 반경 80 안의 모든 적에게 60+0.35AD+0.35AP 마법 피해를 줍니다.",
		"적중은 평타·스킬 직접 피해·소환물과 포탑 공격 1회를 대상마다 셉니다.",
		"지속 피해·장판·아이템 피해는 세지 않으며, 대상이 바뀌어도 누적되고 사망 시 초기화됩니다.",
	],
	"m_bloodstone": [
		"입힌 피해의 12%만큼 회복합니다(흡혈 송곳니와 합산).",
		"모든 회복의 넘친 양이 6초짜리 보호막이 됩니다.",
		"이 보호막의 총량은 최대 체력 20%까지입니다.",
	],
	"m_chrono": [
		"새로 시작하는 재사용 대기시간이 10% 짧아집니다(모래시계와 합산 최대 25%).",
		"영웅을 처치하면 모든 스킬의 남은 대기시간이 즉시 절반이 됩니다.",
	],
	"l_heart": [
		"다섯 능력치 모두 기본 수치 기준으로 오르며 다른 % 증가와 합산됩니다.",
		"늘어난 최대 체력만큼 현재 체력도 즉시 오릅니다(활력의 허리띠와 다름).",
	],
	"l_crown": [
		"영웅을 처치(막타)할 때마다 1중첩, 중첩당 모든 피해가 7% 커집니다(최대 5중첩 1.35배).",
		"사망하거나 새로 주우면 0중첩부터 다시 시작합니다.",
	],
	"l_aegis": [
		"받는 모든 피해가 18% 줄어듭니다(고정 피해·소환물 피해 포함).",
		"20초마다 둔화를 제외한 적의 첫 군중 제어 1회를 무효로 합니다.",
		"넉백·끌어당김 같은 강제 이동은 막지 못합니다.",
	],
	"l_hammer": [
		"평타가 적중하면 주 대상에게 실제로 들어간 피해의 35%를 반경 90 안의 다른 적(소환물 포함)에게 물리 피해로 줍니다.",
		"주 대상과 주변 적 모두 1초 동안 20% 둔화됩니다.",
		"광역 피해에는 방어력이 한 번 더 적용됩니다.",
	],
}

# Arena hazards: type -> {label, icon, color, short, desc}. `short` is a compact
# chip text; per-arena exact numbers come from hazard_summary(h).
const HAZARDS := {
	"lava": {"label": "용암", "icon": "火", "color": "#ff6b3a",
		"short": "활성 구역에서 지속 피해",
		"desc": "항상 활성 상태입니다. 안에 있는 동안 일정 간격으로 피해를 받습니다. 피해량과 간격은 전장별 표시 수치를 따릅니다."},
	"spikes": {"label": "가시 함정", "icon": "棘", "color": "#e1b45f",
		"short": "예고 후 가시·둔화",
		"desc": "주기적으로 예고 후 솟아오릅니다. 활성 구역에 머무르면 반복 피해와 둔화를 받습니다. 주기와 피해량은 전장별로 다릅니다."},
	"eruption": {"label": "분출구", "icon": "爆", "color": "#ffc166",
		"short": "예고 후 폭발·넉백",
		"desc": "예고 후 폭발해 주기마다 1회 피해를 주고 중심에서 바깥으로 밀쳐냅니다. 주기와 피해량은 전장별 표시 수치를 따릅니다."},
	"wind": {"label": "횡풍", "icon": "風", "color": "#6ae0dd",
		"short": "피해 없음 · 밀어냄",
		"desc": "피해는 없습니다. 주기적으로 방향이 바뀌며 영웅만 밀어내고, 가벼운 영웅일수록 크게 밀립니다. 투사체와 소환물은 영향을 받지 않습니다."},
	"portal": {"label": "포탈", "icon": "門", "color": "#a98cff",
		"short": "짝 포탈로 이동",
		"desc": "들어가면 짝 포탈 출구로 즉시 이동합니다(속도 유지, 돌진·넉백 취소). 영웅마다 재사용 대기시간이 있으며, 감금 경계를 넘거나 접지·제압 상태에서는 이용할 수 없습니다."},
	"haste": {"label": "가속 구역", "icon": "↑", "color": "#64e8f0", "short": "일시적인 이동 속도 증가",
		"desc": "지나가는 영웅에게 짧은 이동 속도 증가를 줍니다. 여러 가속 구역의 효과는 중첩되지 않으며, 벗어나면 남은 지속 시간 후 사라집니다."},
	"healing_fountain": {"label": "공용 회복 샘", "icon": "✚", "color": "#65ecc1", "short": "회복 후 모두에게 쿨타임",
		"desc": "범위 안에서 체력 비율이 가장 낮은 부상 영웅 한 명을 회복합니다. 적과 아군이 하나의 충전량을 공유합니다. 사용 후 재충전되며 치유 감소가 적용됩니다."},
	"gravity": {"label": "중력 우물", "icon": "◎", "color": "#b395ff", "short": "예고 후 끌어당김·지속 피해",
		"desc": "예고 후 활성 시간 동안 영웅을 중심으로 끌어당기고, 범위 안에 있는 동안 일정 간격으로 피해를 줍니다. 벽과 감금 경계를 통과할 수 없으며 무적·대상 지정 불가·저지 불가·관조 상태에서는 끌려가지 않습니다."},
	"shockwave": {"label": "확장 충격파", "icon": "◌", "color": "#f4ba76", "short": "퍼지는 고리 · 피해·넉백",
		"desc": "예고 후 중심에서 바깥으로 고리가 퍼집니다. 고리에 닿은 영웅은 주기마다 최대 한 번 피해를 받고 중심 바깥쪽으로 밀려납니다. 이미 지나간 내부 공간은 충격파에 맞지 않습니다."},
	"artillery": {"label": "포격", "icon": "砲", "color": "#ffb45e", "short": "예고 원 표시 후 착탄",
		"desc": "주기마다 포격 구역 안에 여러 발이 떨어집니다. 착탄 지점은 구역 안 영웅 근처로 정해지며, 떨어지기 전에 노란 예고 원과 남은 시간이 모두에게 공개됩니다. 착탄 순간 원 안에 있는 영웅은 한 발마다 한 번 피해를 받고, 도약 중인 영웅은 맞지 않습니다."},
	"gate": {"label": "개폐 성문", "icon": "▦", "color": "#d6a35e", "short": "정해진 주기로 열리고 닫힘",
		"desc": "닫힌 성문은 벽처럼 이동·투사체·시야를 모두 막고, 열린 성문은 아무것도 막지 않습니다. 같은 조의 성문은 함께 움직이며 A조와 B조는 반 주기씩 엇갈려 번갈아 열립니다. 닫히기 직전 경고 시간에는 성문이 깜박이고, 닫히는 성문 안에 있던 영웅은 들어온 쪽으로 밀려납니다."},
	"jump_pad": {"label": "도약 발판", "icon": "⇧", "color": "#7fe3ff", "short": "밟으면 착지 지점으로 도약",
		"desc": "영웅이 발판 중심에 들어서면 표시된 착지 지점으로 날아갑니다. 비행 중에는 벽을 넘고 지면 위험 지역과 포격에 맞지 않지만 대상으로 지정될 수 있습니다. 현재 행동은 취소되고, 영웅마다 재사용 대기시간이 있으며 기절·속박·제압·수면 상태에서는 도약하지 않습니다."},
	"closing_ring": {"label": "결계 수축", "icon": "界", "color": "#d98bff", "short": "안전 지대가 줄어듦 · 바깥은 피해",
		"desc": "정해진 시각부터 안전한 원이 일정한 속도로 줄어들고, 끝나면 최종 크기로 유지됩니다. 원 바깥에 있는 영웅은 일정 간격마다 최대 체력 비율의 고정 피해를 받습니다. 수축 전에는 최종 안전 지대와 남은 시간이 표시됩니다."},
	"mud": {"label": "진흙", "icon": "沼", "color": "#a07b4f", "short": "피해 없음 · 이동 둔화",
		"desc": "피해는 없습니다. 안에 있는 동안 이동 속도가 느려지며, 벗어나면 잠시 뒤 둔화가 풀립니다. 강인함이 둔화 시간을 줄이고, 더 강한 둔화가 있으면 그쪽이 적용됩니다."},
	"br_zone": {"label": "자기장", "icon": "⊙", "color": "#cf9bff", "short": "원 밖은 최대 체력 비율 고정 피해",
		"desc": "배틀그라운드의 안전 지대입니다. 6단계에 걸쳐 줄어들고, 원 밖의 영웅은 0.5초마다 최대 체력 비율의 고정 피해를 받습니다(단계마다 초당 1%·2%·3.5%·5%·8%·12%). 다음 원은 수축 전에 공개됩니다."},
	"brush": {"label": "수풀", "icon": "♣", "color": "#7fd08a", "short": "안에 있으면 보이지 않음",
		"desc": "수풀 안의 영웅은 같은 수풀에 있는 상대나 110 이내(몸 가장자리 기준)로 다가온 상대에게만 보입니다. 교전하면 0.8초 동안 드러납니다. 수풀 깊숙이 지나가는 시선도 가려집니다."},
}

## Deathmatch calls the same concealment patches "숲" (forest canopy).
const BRUSH_DM_LABEL := "숲"

const HAZARD_RULE := {"title": "환경 효과", "text": "환경 효과는 영웅에게만 적용되며 소환물과 투사체는 영향을 받지 않습니다. 방어력·마법 저항력·보호막·무적이 적용되고, 환경 피해로 쓰러지면 누구도 처치를 얻지 못합니다."}

const COVER := {"label": "투시 엄폐물", "icon": "▥", "color": "#9fb0c8", "short": "몸만 막음 · 시야·투사체 통과",
	"desc": "철책과 가시 덤불 같은 낮은 울타리, 용암 도랑·허공·수로·협곡 같은 꺼진 지형은 몸의 이동만 막습니다. 시야와 투사체는 그대로 통과하므로 건너편과 서로 보고 공격할 수 있습니다."}

## Body-only terrain kinds (blocksUnits only) shown in the codex: kind -> [label, icon, color].
const LOW_TERRAIN := {"lattice": ["철책", "▥", "#b6a37f"], "hedge": ["가시 덤불", "▤", "#8fb36a"], "chasm": ["꺼진 지형", "▧", "#7f8fd0"]}
const CHASM_MATERIALS := {"lava": "용암 도랑", "void": "허공", "water": "수로", "ravine": "협곡"}

const ARENA_KIND_LABELS := {"elimination": "섬멸전", "control": "거점 장악", "deathmatch": "개인전", "battleground": "배틀그라운드"}
## Battleground item rings, centre to edge (BrItems / BattlegroundMapData.ring_of).
const BR_RING_LABELS := ["중앙", "안쪽", "바깥쪽", "외곽"]
# V1.5.3 map-format keys (arena_data spawn_orientation / symmetry / archetype).
const ORIENTATION_LABELS := {"west_east": "좌우", "north_south": "상하", "diagonal": "대각", "split": "분할"}
const ORIENTATION_TIPS := {"west_east": "두 팀이 서쪽과 동쪽에서 출발합니다.", "north_south": "두 팀이 북쪽과 남쪽에서 출발합니다.",
	"diagonal": "두 팀이 마주 보는 모서리에서 대각선으로 출발합니다.", "split": "팀마다 출발 지점이 두 입구로 나뉘어 엇갈려 출발합니다."}
const SYMMETRY_LABELS := {"point": "점대칭", "mirror_x": "좌우 대칭", "mirror_y": "상하 대칭", "mirror_anti": "대각선 대칭"}
const SYMMETRY_TIPS := {"point": "전장 중심을 기준으로 180도 돌리면 두 팀 진영이 정확히 겹칩니다.", "mirror_x": "가운데 세로선을 기준으로 좌우가 똑같습니다.",
	"mirror_y": "가운데 가로선을 기준으로 위아래가 똑같습니다.", "mirror_anti": "대각선을 기준으로 두 진영이 거울처럼 똑같습니다."}
const ARCHETYPE_LABELS := {"open_baseline": "개방형 기준", "gated_fortress": "개폐 성채", "loop_circuit": "순환로", "lava_bridges": "용암 다리",
	"wind_aperture": "회오리 성소", "portal_islands": "포탈 섬", "cover_maze": "엄폐 미로", "three_lanes": "세 갈래 길",
	"artillery_plaza": "포격 광장", "twisting_ravine": "굽이 협곡", "split_docks": "갈라진 부두", "closing_ring_arena": "수축 결계 전장",
	"triangle_objectives": "삼각 거점", "gated_keep_objectives": "성채 거점", "river_fords": "강 여울"}
# Header for arena_data.difficulty, which holds a category, not a difficulty.
const ARENA_TYPE_CAPTION := "유형"

# Resource keys used by ability conditions / passives -> [label, unit, glossary key]
const RESOURCES := {
	"fish": ["물고기", "마리", ""],
	"healBank": ["힐 주머니", "", ""],
	"rage": ["충격", "스택", ""],
	"shards": ["차원 조각", "", ""],
	"fuel": ["연료", "", "fuel"],
}

# Rule lists derived from engine constants (built once on first use).
static var ITEM_RULES: Array = _build_item_rules()
static var CONTROL_RULES: Array = _build_control_rules()
static var DM_MAP_RULES: Array = _build_dm_rules()
static var BR_MAP_RULES: Array = _build_br_rules()

static var _alias_index: Dictionary = {}


# ---------------------------------------------------------------- lookups

static func status(key: String) -> Dictionary:
	var k: String = term_for_label(key) if not STATUS.has(key) else key
	if k == "":
		return {}
	var d: Dictionary = (STATUS[k] as Dictionary).duplicate()
	d["key"] = k
	return d


static func has_term(key: String) -> bool:
	return STATUS.has(key)


static func term_label(key: String) -> String:
	return str((STATUS.get(key, {}) as Dictionary).get("label", key))


static func term_color(key: String, fallback: Color = Color("#a9b6cc")) -> Color:
	var d: Dictionary = STATUS.get(key, {})
	return Color(str(d.color)) if d.has("color") else fallback


# Label, alias, engine key or DB.STATUS_LABELS text -> glossary key ("" if none).
static func term_for_label(text: String) -> String:
	var t: String = text.strip_edges()
	if t == "":
		return ""
	if STATUS.has(t):
		return t
	if _alias_index.is_empty():
		for k in STATUS:
			var d: Dictionary = STATUS[k]
			_alias_index[str(d.label)] = k
			for a in d.get("aliases", []):
				_alias_index[str(a)] = k
		for k in DB.STATUS_LABELS:
			if STATUS.has(k) and not _alias_index.has(str(DB.STATUS_LABELS[k])):
				_alias_index[str(DB.STATUS_LABELS[k])] = k
	return str(_alias_index.get(t, ""))


static func categories() -> Array:
	return CATEGORIES.duplicate()


static func terms_in_category(cat: String) -> Array:
	var out: Array = []
	for k in STATUS:
		if str(STATUS[k].category) == cat:
			out.append(k)
	return out


static func item_details(id: String) -> Array:
	return (ITEM_DETAILS.get(id, []) as Array).duplicate()


static func tag_label(tag: String) -> String:
	return str(ITEM_TAG_LABELS.get(tag, tag))


static func hazard(type: String) -> Dictionary:
	var d: Dictionary = (HAZARDS.get(type, {}) as Dictionary).duplicate()
	if not d.is_empty():
		d["type"] = type
	return d


static func arena_kind_label(ruleset: String) -> String:
	return str(ARENA_KIND_LABELS.get(ruleset, ruleset))


# Spawn chance of one rarity per roll, in percent.
static func rarity_chance(r: int) -> float:
	var total: float = 0.0
	for w in ItemDefs.RARITY_WEIGHTS:
		total += float(w)
	if total <= 0.0 or r < 0 or r >= ItemDefs.RARITY_WEIGHTS.size():
		return 0.0
	return float(ItemDefs.RARITY_WEIGHTS[r]) / total * 100.0


# Spawn chance of one specific item per roll, in percent (weight / count).
static func item_chance(id: String) -> float:
	if not ItemDefs.DEFS.has(id):
		return 0.0
	var r: int = ItemDefs.rarity_of(id)
	var n: int = ItemDefs.by_rarity(r).size()
	return rarity_chance(r) / maxf(1.0, float(n))


static func rarity_count(r: int) -> int:
	return ItemDefs.by_rarity(r).size()


# Short "12.5"-style number without trailing zeros.
static func num(v: float) -> String:
	if absf(v - roundf(v)) < 0.0005:
		return str(int(roundf(v)))
	var s: String = "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s


# ---------------------------------------------------------------- arenas

# Exact one-line summary for one hazard dictionary (arena data or Arena.hazards).
static func hazard_summary(h: Dictionary) -> String:
	var typ: String = str(h.get("type", ""))
	var school: String = "마법" if str(h.get("school", "physical")) == "magic" else "물리"
	match typ:
		"lava":
			return "항상 활성 · %s초마다 %s %s" % [num(float(h.get("tickInterval", 0.5))), school, num(float(h.get("damage", 0.0)))]
		"spikes":
			var s: String = "%s초 주기 · %s초 예고 후 %s초 솟음 · %s초마다 %s %s" % [num(float(h.get("period", 0.0))), num(float(h.get("warningDuration", 0.0))),
				num(float(h.get("activeDuration", 0.0))), num(float(h.get("tickInterval", 0.5))), school, num(float(h.get("damage", 0.0)))]
			if h.has("slow"):
				s += " · 둔화 %s%% %s초" % [num(float(h.slow) * 100.0), num(float(h.get("slowDuration", 0.8)))]
			return s
		"eruption":
			var e: String = "%s초 주기 · %s초 예고 · %s %s" % [num(float(h.get("period", 0.0))), num(float(h.get("warningDuration", 0.0))), school, num(float(h.get("damage", 0.0)))]
			if h.has("knockback"):
				e += " · 넉백 %s" % num(float(h.knockback))
			return e
		"wind":
			return "피해 없음 · %s초마다 방향 전환 · 영웅만 밀어냄" % num(float(h.get("period", 5.0)) * 0.5)
		"portal":
			return "짝 포탈로 즉시 이동 · 영웅마다 %s초 재사용" % num(float(h.get("cooldown", 2.5)))
		"haste":
			return "이동 속도 +%s%% · %s초 유지 · 중첩 없음" % [num((float(h.get("speedMultiplier", 1.25)) - 1.0) * 100.0), num(float(h.get("duration", 1.6)))]
		"healing_fountain":
			return "최대 체력 %s%% 회복 · 공용 쿨타임 %s초" % [num(float(h.get("healPercent", 0.16)) * 100.0), num(float(h.get("cooldown", 18.0)))]
		"gravity":
			var gs: String = "%s초 주기 · %s초 예고 · %s초 끌어당김 · 힘 %s" % [num(float(h.get("period", 0.0))), num(float(h.get("warningDuration", 0.0))), num(float(h.get("activeDuration", 0.0))), num(float(h.get("force", 130.0)))]
			if float(h.get("damage", 0.0)) > 0.0:
				gs += " · 활성 중 %s초마다 %s %s" % [num(float(h.get("tickInterval", 0.5))), school, num(float(h.get("damage", 0.0)))]
			return gs
		"shockwave":
			var ws: String = "%s초 주기 · %s초 예고 · 고리 적중 시 %s %s · 주기당 1회" % [num(float(h.get("period", 0.0))), num(float(h.get("warningDuration", 0.0))), school, num(float(h.get("damage", 0.0)))]
			if float(h.get("knockback", 0.0)) > 0.0:
				ws += " · 넉백 %s" % num(float(h.knockback))
			return ws
		"artillery":
			return "%s초 주기 · %s초 예고 · %s발 · 반경 %s · 한 발마다 %s %s · 첫 착탄 %s초" % [num(float(h.get("period", 8.0))), num(Arena.artillery_warning(h)),
				num(float(h.get("count", 3))), num(float(h.get("radius", 60.0))), school, num(float(h.get("damage", 0.0))), num(artillery_first_impact(h))]
		"jump_pad":
			var from: Vector2 = Vector2(float(h.get("x", 0.0)), float(h.get("y", 0.0)))
			var tgt: Dictionary = h.get("target", {})
			var to: Vector2 = Vector2(float(tgt.get("x", from.x)), float(tgt.get("y", from.y)))
			return "착지 지점까지 거리 %s · %s초 비행 · 영웅마다 %s초 재사용" % [num(roundf(from.distance_to(to))), num(float(h.get("flightTime", 0.8))), num(float(h.get("cooldown", 2.0)))]
		"closing_ring":
			var t0: float = float(h.get("startTime", 60.0))
			return "%s초~%s초 반경 %s → %s 수축 · 바깥은 %s초마다 최대 체력 %s%% 고정 피해" % [num(t0), num(maxf(t0, float(h.get("endTime", t0 + 30.0)))),
				num(float(h.get("startRadius", 900.0))), num(float(h.get("endRadius", 200.0))), num(float(h.get("tickInterval", 1.0))), num(clampf(float(h.get("damagePercent", 4.0)), 0.0, 100.0))]
		"mud":
			return "피해 없음 · 이동 속도 -%s%% · 벗어나면 %s초 뒤 해제" % [num(clampf(float(h.get("slow", 0.3)), 0.0, 0.6) * 100.0), num(ArenaEnv.MUD_SLOW_DURATION)]
	return str((HAZARDS.get(typ, {}) as Dictionary).get("short", typ))


# Layout facts of a team-mode arena: [[badge text, tooltip], ...] for size,
# spawn orientation, symmetry and structure (archetype).
static func arena_layout_facts(a: Arena) -> Array:
	var out: Array = []
	if a == null:
		return out
	var ratio: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
	out.append(["%s×%s" % [num(a.width), num(a.height)], "전장 크기입니다. 기본 전장(1408×792) 넓이의 %s배입니다." % num(snappedf(ratio, 0.01))])
	var orient: String = str(a.data.get("spawn_orientation", ""))
	if ORIENTATION_LABELS.has(orient):
		out.append(["%s 출발" % str(ORIENTATION_LABELS[orient]), str(ORIENTATION_TIPS.get(orient, ""))])
	var sym: String = str(a.data.get("symmetry", ""))
	if SYMMETRY_LABELS.has(sym):
		out.append([str(SYMMETRY_LABELS[sym]), str(SYMMETRY_TIPS.get(sym, "")) + " 장애물·기믹·출발 지점이 두 팀에 똑같이 배치됩니다."])
	var arch: String = str(a.data.get("archetype", ""))
	if ARCHETYPE_LABELS.has(arch):
		out.append(["구조 · %s" % str(ARCHETYPE_LABELS[arch]), "전장의 지형 구조입니다. 섬멸전 12개 전장은 모두 다른 구조를 가집니다."])
	return out


static func orientation_label(a: Arena) -> String:
	return str(ORIENTATION_LABELS.get(str(a.data.get("spawn_orientation", "")), "")) if a else ""


# Korean label of an environment type; brush is "숲" in deathmatch.
static func hazard_label(type: String, deathmatch: bool = false) -> String:
	if type == "brush" and deathmatch:
		return BRUSH_DM_LABEL
	return str((HAZARDS.get(type, {}) as Dictionary).get("label", "환경"))


# First impact time of an artillery hazard (its first salvo announced at t >= 0).
static func artillery_first_impact(h: Dictionary) -> float:
	var period: float = maxf(0.2, float(h.get("period", 8.0)))
	var warn: float = Arena.artillery_warning(h)
	var c: int = int(floor(float(h.get("phase", 0.0)) / period)) - 2
	for i in 6:
		var impact: float = Arena.artillery_impact_time(h, c + i)
		if impact - warn >= 0.0:
			return impact
	return period


# One gate group's schedule from an Arena gate definition (phase includes the B shift).
static func gate_summary(g: Dictionary) -> String:
	var period: float = float(g.get("period", 12.0))
	var open_now: bool = Arena.gate_def_open(g, 0.0)
	return "%s조 · %s초 주기 · %s초 열림 · 닫히기 %s초 전 경고 · 시작 시 %s" % [str(g.get("group", "A")), num(period), num(float(g.get("openDuration", period * 0.5))),
		num(float(g.get("warningDuration", 1.5))), "열림" if open_now else "닫힘"]


# Brush summary (team modes): patch count and the concealment rule numbers.
static func brush_summary(a: Arena) -> String:
	var patches: Dictionary = {}
	for p in a.forest_patch:
		patches[int(p)] = true
	return "%d무리 · 수풀 밖 상대에게는 110 이내에서만 보임 · 교전하면 0.8초 노출" % patches.size()


# Hazards of an arena merged by identical summary:
# [{type, label, icon, color, count, summary, desc}]
static func arena_hazards(a: Arena) -> Array:
	var out: Array = []
	var by_key: Dictionary = {}
	if a == null:
		return out
	for h in a.hazards:
		var typ: String = str(h.get("type", ""))
		var summary: String = hazard_summary(h)
		var key: String = typ + "|" + summary
		if by_key.has(key):
			(out[int(by_key[key])] as Dictionary)["count"] = int(out[int(by_key[key])].count) + 1
			continue
		var base: Dictionary = HAZARDS.get(typ, {"label": typ, "icon": "•", "color": "#a9b6cc", "desc": ""})
		by_key[key] = out.size()
		out.append({"type": typ, "label": str(base.label), "icon": str(base.icon), "color": Color(str(base.color)),
			"count": 1, "summary": summary, "desc": str(base.get("desc", ""))})
	return out


# Every gimmick of an arena for the codex and the developer lab: hazards
# (arena_hazards), one row per gate group and the brush row (team modes; the
# deathmatch codex lists its forests separately).
static func arena_gimmicks(a: Arena) -> Array:
	var out: Array = arena_hazards(a)
	if a == null:
		return out
	var groups: Array = []
	var counts: Dictionary = {}
	var defs: Dictionary = {}
	for g in a.gates:
		var gr: String = str(g.group)
		if not counts.has(gr):
			groups.append(gr)
			counts[gr] = 0
			defs[gr] = g
		counts[gr] = int(counts[gr]) + 1
	groups.sort()
	var gb: Dictionary = HAZARDS.gate
	for gr in groups:
		out.append({"type": "gate", "label": "%s %s조" % [str(gb.label), gr], "icon": str(gb.icon), "color": Color(str(gb.color)),
			"count": int(counts[gr]), "summary": gate_summary(defs[gr]), "desc": str(gb.desc)})
	if not a.forests.is_empty() and a.ruleset != "deathmatch":
		var bb: Dictionary = HAZARDS.brush
		out.append({"type": "brush", "label": str(bb.label), "icon": str(bb.icon), "color": Color(str(bb.color)),
			"count": 1, "summary": brush_summary(a), "desc": str(bb.desc)})
	return out


# Body-only terrain of an arena (lattice / hedge / chasm), grouped by kind:
# [{kind, label, icon, color, count, detail}] (detail lists chasm materials).
static func low_terrain(a: Arena) -> Array:
	var out: Array = []
	if a == null or a.ruleset == "deathmatch":
		return out
	var counts: Dictionary = {}
	var mats: Dictionary = {}
	for o in a.obstacles:
		var od: Dictionary = o
		var kind: String = str(od.get("kind", "wall"))
		if not LOW_TERRAIN.has(kind) or od.get("blocksVision", true) != false:
			continue
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind == "chasm":
			mats[str(CHASM_MATERIALS.get(str(od.get("material", "")), "꺼진 지형"))] = true
	for kind in ["lattice", "hedge", "chasm"]:
		if not counts.has(kind):
			continue
		var info: Array = LOW_TERRAIN[kind]
		out.append({"kind": kind, "label": str(info[0]), "icon": str(info[1]), "color": Color(str(info[2])), "count": int(counts[kind]),
			"detail": "·".join(PackedStringArray(mats.keys())) if kind == "chasm" else ""})
	return out


# Obstacles that block movement but not sight (body-only terrain).
static func see_through_count(a: Arena) -> int:
	var n: int = 0
	if a == null or a.ruleset == "deathmatch":
		return 0
	for o in a.obstacles:
		if (o as Dictionary).get("blocksVision", true) == false:
			n += 1
	return n


# Deathmatch map counts: {buildings, forests (canopy patches), item_spots}.
static func dm_counts(a: Arena) -> Dictionary:
	var patches: Dictionary = {}
	if a == null:
		return {"buildings": 0, "forests": 0, "item_spots": 0}
	for p in a.forest_patch:
		patches[int(p)] = true
	return {"buildings": (a.data.get("buildings", []) as Array).size(), "forests": patches.size(),
		"item_spots": a.item_spots.size()}


# ---------------------------------------------------------------- rule lists

static func _build_item_rules() -> Array:
	var tiers: Array = []
	var per: Array = []
	for r in ItemDefs.RARITY_NAMES.size():
		tiers.append("%s %s%%" % [ItemDefs.RARITY_NAMES[r], num(rarity_chance(r))])
		var ids: Array = ItemDefs.by_rarity(r)
		var one: float = rarity_chance(r) / maxf(1.0, float(ids.size()))
		per.append("%s %s%%" % [ItemDefs.RARITY_NAMES[r], num(snappedf(one, 0.01))])
	var opening_base: int = 12
	return [
		{"key": "slots", "title": "보유 %d칸" % DeathmatchMode.SLOTS,
			"text": "영웅마다 아이템을 %d개까지 들 수 있고 같은 아이템은 중복으로 가질 수 없습니다(효과가 겹치지 않음)." % DeathmatchMode.SLOTS},
		{"key": "pickup", "title": "줍기와 교체",
			"text": "아이템 위를 지나가면 AI가 필요도를 평가합니다. 빈 칸이 있으면 쓸모 있는 아이템을 줍고, 가득 차 있으면 확실히 더 유용할 때만 가장 덜 유용한 아이템과 바꿉니다."},
		{"key": "swap_drop", "title": "교체한 아이템",
			"text": "교체로 내려놓은 아이템은 영웅 바로 뒤에 떨어져 다른 영웅이 주울 수 있습니다."},
		{"key": "death", "title": "사망 시",
			"text": "가장 높은 등급 아이템 1개만 그 자리에 떨어지고 나머지는 사라집니다(필드가 가득 차 있으면 떨어지지 않음). 불사조 깃털은 떨어지지 않습니다."},
		{"key": "field", "title": "필드 최대 %d개" % DeathmatchMode.MAX_FIELD_ITEMS,
			"text": "시작할 때 %d+참가자×2개(최대 %d개)가 놓이고, 이후 필드에 %d개 미만이면 새 아이템이 생깁니다." % [opening_base, DeathmatchMode.MAX_FIELD_ITEMS, DeathmatchMode.MAX_FIELD_ITEMS]},
		{"key": "interval", "title": "생성 간격",
			"text": "4초부터 (9 − 0.45×참가자 수)초(3~9초)에 0~2초를 더한 간격으로 1개씩 생기며, 살아 있는 영웅과 260 이상 떨어진 곳에만 놓입니다."},
		{"key": "rarity", "title": "등급 확률",
			"text": "%s. 등급을 먼저 정한 뒤 그 등급 안에서 고르게 뽑습니다." % " · ".join(tiers)},
		{"key": "per_item", "title": "개별 확률",
			"text": "아이템 하나의 확률은 등급 확률 ÷ 등급 안 개수입니다(%s)." % " · ".join(per)},
		{"key": "regen", "title": "전투 이탈 회복",
			"text": "7초 동안 피해를 주거나 받지 않으면 초당 최대 체력 1.5%를 회복합니다(재생의 이끼로 강화)."},
	]


static func _build_control_rules() -> Array:
	return [
		{"key": "capture", "title": "거점 점령",
			"text": "한 팀만 5초 머물면 적 거점을 중립화하고, 다시 5초 머물면 점령합니다. 도중에 벗어나면 진행이 초기화됩니다."},
		{"key": "score", "title": "득점",
			"text": "보유한 거점마다 초당 %s점을 얻으며(비어 있어도) 300점을 먼저 모은 팀이 승리합니다." % num(DominationMode.SCORE_RATE)},
		{"key": "contest", "title": "경합",
			"text": "양 팀이 함께 있으면 그 거점의 점령과 득점이 멈춥니다."},
		{"key": "heal_zone", "title": "회복 구역",
			"text": "한 팀만 있을 때 체력 85% 미만 아군 중 가장 낮은 1명에게 최대 체력 35%를 회복시키고 25초 뒤 다시 충전됩니다(양 팀 공유)."},
		{"key": "respawn", "title": "부활",
			"text": "쓰러지면 %s초 뒤 부활하고 %s초 동안 보호받습니다." % [num(DominationMode.RESPAWN_DELAY), num(DominationMode.SPAWN_PROTECTION)]},
	]


static func _build_dm_rules() -> Array:
	return [
		{"key": "map", "title": "전장",
			"text": "%s×%s 크기의 개인전 전장이며 시드마다 건물·숲·바위 배치가 달라집니다." % [num(DeathmatchMapData.WIDTH), num(DeathmatchMapData.HEIGHT)]},
		{"key": "forest", "title": "숲",
			"text": "숲 안의 영웅은 110 이내(몸 가장자리 기준)로 다가오거나 교전한 지 0.8초가 지나기 전까지 밖에서 보이지 않습니다. 숲 안에서는 밖이 보입니다."},
		{"key": "canopy", "title": "두꺼운 숲",
			"text": "시선이 다른 숲을 120 넘게 가로지르면 시야가 가려집니다."},
		{"key": "building", "title": "건물",
			"text": "벽이 이동·투사체·시야를 모두 막으며 건물마다 아이템 자리가 3곳 있습니다."},
		{"key": "obstacle", "title": "나무·바위",
			"text": "나무 줄기는 이동과 투사체만 막고 시야는 통과시키며, 바위는 모두 막습니다."},
		{"key": "respawn", "title": "부활",
			"text": "쓰러지면 %s초 뒤 적에게서 먼 지점에서 부활하고 %s초 동안 보호받습니다(적대 행동 시 해제)." % [num(DeathmatchMode.RESPAWN_DELAY), num(DeathmatchMode.SPAWN_PROTECTION)]},
		{"key": "brawl", "title": "난전 보정",
			"text": "영웅이 받는 피해가 %s배가 되어 1대1 교전이 빨리 끝납니다." % num(DeathmatchMode.BRAWL_DAMAGE)},
	]


# V2 battleground rules (DESIGN_V2 §3.1-§3.4), numbers from the mode, zone and item constants.
static func _build_br_rules() -> Array:
	var sc: Array = BrZone.SCHEDULE
	var bleed: Array = BattlegroundMode.BLEED_TIMES
	var dps: PackedStringArray = PackedStringArray()
	for row in sc:
		dps.append(num(float(row[3]) * 100.0) + "%")
	return [
		{"key": "format", "title": "솔로 · 듀오 · 트리오",
			"text": "솔로는 2–%d명(같은 영웅 중복 가능), 듀오는 2–%d팀, 트리오는 2–%d팀이 겨룹니다. 같은 팀 안에는 같은 영웅을 둘 수 없고, 모든 참가자를 AI가 조종합니다." % [BattlegroundMode.MAX_HEROES, floori(BattlegroundMode.MAX_HEROES / 2.0), floori(BattlegroundMode.MAX_HEROES / 3.0)]},
		{"key": "win", "title": "마지막 생존 팀",
			"text": "마지막까지 남은 팀이 우승하고 순위는 탈락한 역순입니다. 다시 출전하지 않으며, %s이 지나면 남은 팀을 생존 인원, 그다음 체력 합으로 정합니다." % UITheme.fmt_time(BattlegroundMode.MAX_TIME)},
		{"key": "zone", "title": "자기장 %d단계" % BrZone.PHASES,
			"text": "%s초부터 원이 %d단계에 걸쳐 줄어들고, 원 밖은 0.5초마다 초당 최대 체력의 %s 고정 피해를 받습니다. 다음 원은 수축 전에 공개되며, 속도는 빠름 ×%s · 보통 · 느림 ×%s입니다." % [num(float(sc[0][0])), BrZone.PHASES, "·".join(dps), num(float(BrZone.SPEEDS.fast)), num(float(BrZone.SPEEDS.slow))]},
		{"key": "down", "title": "다운과 소생",
			"text": "듀오·트리오에서 쓰러지면 먼저 다운됩니다(체력 %d, 출혈 %s·%s·%s초). 다운 중에는 자기장을 포함한 모든 피해를 %d%%만 받습니다. 팀원이 %s 거리 안에서 %s초 소생하면 체력 %d%%로 일어나고, 팀원이 모두 다운·사망하면 팀이 탈락합니다." % [int(BattlegroundMode.DOWNED_HP),
				num(float(bleed[0])), num(float(bleed[1])), num(float(bleed[2])), int(BattlegroundMode.DOWNED_TAKEN * 100.0), num(BattlegroundMode.REVIVE_RANGE), num(BattlegroundMode.REVIVE_TIME), int(BattlegroundMode.REVIVE_HP * 100.0)]},
		{"key": "items", "title": "아이템 %d개 · %d칸" % [BattlegroundMode.ITEM_COUNT, DeathmatchMode.SLOTS],
			"text": "시작할 때 필드에 %d개를 놓고 다시 만들지 않습니다. 중앙에 가까울수록 높은 등급이 많습니다. 영웅마다 %d칸까지 들고 더 좋은 아이템을 만나면 교체하며, 탈락하면 지닌 아이템을 모두 떨어뜨립니다." % [BattlegroundMode.ITEM_COUNT, DeathmatchMode.SLOTS]},
		{"key": "map", "title": "전장 %d종" % BattlegroundMapData.ORDER.size(),
			"text": "표준 전장의 약 30배 넓이이며 시드마다 건물·수풀·기믹 배치가 달라집니다. 수풀 안의 영웅은 가까이 다가오거나 교전하기 전까지 밖에서 보이지 않습니다."},
		{"key": "regen", "title": "전투 이탈 회복",
			"text": "7초 동안 피해를 주거나 받지 않으면 초당 최대 체력 1.5%를 회복합니다. 자기장 피해는 이 타이머를 초기화하지 않지만, 피해가 들어오는 원 밖에서는 회복하지 않습니다."},
		{"key": "credit", "title": "처치 기록",
			"text": "다운시킨 횟수와 처치를 따로 셉니다. 자기장·환경으로 쓰러지면 %s초 안에 마지막으로 피해를 준 적 영웅에게 처치가 기록됩니다." % num(BattlegroundMode.ZONE_CREDIT_WINDOW)},
	]


# Battleground map counts: {buildings, brush (patches), brush_circles, gimmicks (hazards + gates),
# item_spots, rings (item spots per ring 0..3), landmarks, spawns}.
static func br_counts(a: Arena) -> Dictionary:
	var out: Dictionary = {"buildings": 0, "brush": 0, "brush_circles": 0, "gimmicks": 0, "item_spots": 0, "rings": [0, 0, 0, 0], "landmarks": 0, "spawns": 0}
	if a == null:
		return out
	var patches: Dictionary = {}
	for p in a.forest_patch:
		patches[int(p)] = true
	var rings: Array = [0, 0, 0, 0]
	for spot in a.data.get("item_spots", []):
		var r: int = clampi(int((spot as Dictionary).get("ring", 3)), 0, 3)
		rings[r] = int(rings[r]) + 1
	var gate_groups: Dictionary = {}
	for g in a.gates:
		gate_groups[str(g.group)] = true
	out["buildings"] = (a.data.get("buildings", []) as Array).size()
	out["brush"] = patches.size()
	out["brush_circles"] = a.forest_x.size()
	out["gimmicks"] = a.hazards.size() + gate_groups.size()
	out["item_spots"] = (a.data.get("item_spots", []) as Array).size()
	out["rings"] = rings
	out["landmarks"] = ((a.data.get("br", {}) as Dictionary).get("landmarks", []) as Array).size()
	out["spawns"] = a.ffa_spawns.size()
	return out


# "title · text" strings for callers that want plain lines.
static func rule_lines(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		out.append("%s · %s" % [str(r.title), str(r.text)])
	return out
