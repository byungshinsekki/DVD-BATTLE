class_name Doctrine
extends RefCounted







const PROFILE: = {
	"swordsman": {"title": "검흔 연계 돌파", "code": "SILENT BACKCUT", "roles": ["FINISHER", "FLANKER"], 
		"principles": ["검기 추적(S3) 없이는 배후 절단(S4)을 노리지 않는다", "추적이 끝나기 전에 배후 절단으로 회수", "검흔(S2)을 먼저 깔고 다른 액티브로 추가 피해", "세 번째 평타를 흘리지 않는다"], 
		"target": {"low": 1.15, "threat": 0.55, "backline": 1.1, "isolated": 0.75}, 
		"geometry": "flank", "combos": ["S3 침묵 추적 → S4 배후 절단", "S2 검흔 → S1·S3·S4 추가 피해"]}, 
	"archer": {"title": "질풍 사거리 순환", "code": "KITE LATTICE", "roles": ["CARRY", "FINISHER"], 
		"principles": ["평타 가동률 최우선", "후퇴 사격(S1)은 실제 진입에만", "처형(S3)은 18% 경계에서", "질풍 장전(S4)은 사격 창이 열릴 때"], 
		"target": {"low": 1.45, "threat": 0.45, "backline": 0.6, "isolated": 0.4}, 
		"geometry": "kite", "combos": ["S4 질풍 장전 → 연속 평타", "S3 처형은 체력 18% 이하에서만"]}, 
	"mage": {"title": "빙결 화염 구역 통제", "code": "FROSTFIRE GRID", "roles": ["CONTROLLER", "ZONE"], 
		"principles": ["속박(S1) 뒤 화염진(S2)으로 확정 적중", "자기 연소 표식(S3) 중복 금지", "공간 도약(S4)은 생존용으로 보존", "장판은 탈출 경로에"], 
		"target": {"low": 0.55, "threat": 1.2, "backline": 0.7, "isolated": 0.35}, 
		"geometry": "backline", "combos": ["S1 빙결 속박 → S2 낙화 화염진 → S3 연소"]}, 
	"sniper": {"title": "초장거리 표적 제거", "code": "GHOST FIRING LINE", "roles": ["CARRY", "MARKSMAN"], 
		"principles": ["근접전 거부 — 긴급 제압탄(S4)은 돌진 대응용으로 보존", "취약 탄환(S3) 뒤 평타로 낙인", "필중 사격(S1)은 제어 창·먼 거리에서", "유령 매복(S2)은 임박한 피해에만"], 
		"target": {"low": 0.95, "threat": 1.25, "backline": 0.85, "isolated": 0.75}, 
		"geometry": "max_range", "combos": ["S3 취약 탄환 → 평타 낙인 → S1 필중 사격"]}, 
	"werewolf": {"title": "혈향 추격 포식", "code": "BLOOD SCENT", "roles": ["DIVER", "HUNTER"], 
		"principles": ["저체력 냄새를 추적한다", "상위 포식자(S2)는 체력이 높은 적에게", "포효(S3)로 시전을 끊는다", "물어뜯기(S4)는 아군 후속 화력이 닿을 때"], 
		"target": {"low": 1.75, "threat": 0.35, "backline": 0.85, "isolated": 1.1}, 
		"geometry": "pursuit", "combos": ["S1 피냄새 → S4 제압 → S3 포효"]}, 
	"giant": {"title": "산맥 전선 고정", "code": "MOUNTAIN LINE", "roles": ["TANK", "ENGAGE", "GUARD"], 
		"principles": ["체력 우위를 전선 폭으로", "지각 강타(S1)는 다수·후열 위협에", "재생(S2)은 피해를 받은 직후", "후열 앞에서 몸으로 막는다"], 
		"target": {"low": 0.7, "threat": 1.05, "backline": 0.2, "isolated": 0.25}, 
		"geometry": "body_block", "combos": ["S1 에어본 → S3 산맥 투척"]}, 
	"aphrodite": {"title": "구출·짝수 강화", "code": "GOLDEN PAIR", "roles": ["SUPPORT", "PROTECTOR"], 
		"principles": ["치명 위험 아군을 먼저 구출(S3)", "침상(S2)은 두 명이 머물 곳에", "유혹(S1)으로 돌진자를 끊는다", "사과(S4)는 팀 진입 신호에 맞춰"], 
		"target": {"low": 0.35, "threat": 0.75, "backline": 0.45, "isolated": 0.3}, 
		"geometry": "guard_carry", "combos": ["S3 구출 → S2 짝 치유"]}, 
	"blood_mage": {"title": "혈량 투자·회수", "code": "CRIMSON ECONOMY", "roles": ["ZONE", "CARRY"], 
		"principles": ["체력 비용은 회수 경로가 있을 때만", "혈해(S2)로 다수 적중 성장", "흡혈 탄환(S3)으로 투자 회수", "체력 28% 아래에서는 파산 방지"], 
		"target": {"low": 0.75, "threat": 0.75, "backline": 0.6, "isolated": 0.45}, 
		"geometry": "backline", "combos": ["S2 혈해 → S3 흡혈 회수"]}, 
	"fisherman": {"title": "고립 낚시·사시미", "code": "HOOK AND FILLET", "roles": ["PICK", "FINISHER"], 
		"principles": ["후속 화력 없는 낚시(S1) 금지", "낚은 뒤 사시미(S4) 확정", "근접 돌진자를 우리 후열로 끌어오지 않는다", "미끼(S2)로 도주로 봉쇄"], 
		"target": {"low": 0.75, "threat": 0.7, "backline": 1.35, "isolated": 1.2}, 
		"geometry": "hook_lane", "combos": ["S1 큰낚시 → S4 사시미 결착"]}, 
	"baseball": {"title": "배트 반사·전선 수비", "code": "DIAMOND DEFENSE", "roles": ["GUARD", "PEEL"], 
		"principles": ["다가오는 투사체는 배트로 반사", "헬멧(S2)은 투사체가 올 때", "벤치 클리어링(S3)은 실제로 맞는 아군에게", "원거리 적과 우리 후열 사이에 선다"], 
		"target": {"low": 0.55, "threat": 1.1, "backline": 0.35, "isolated": 0.65}, 
		"geometry": "screen", "combos": ["수비 스윙 반사 → S1 변화구 견제"]}, 
	"pirate": {"title": "거리 전환 약탈", "code": "CUTLASS BROADSIDE", "roles": ["SKIRMISHER"], 
		"principles": ["약탈 탄환(S3) 뒤 평타 먼저", "칼 거리에서 고정 피해", "함포(S4)는 다수·이탈 동시에", "갈고리(S2)는 안전한 경로로"], 
		"target": {"low": 0.8, "threat": 1.05, "backline": 0.75, "isolated": 0.75}, 
		"geometry": "hybrid", "combos": ["S3 약탈 → 평타 → S4 함포 이탈"]}, 
	"joker": {"title": "혼란 스택·위치 교환", "code": "CHAOS SWITCH", "roles": ["DISRUPTOR", "FINISHER"], 
		"principles": ["혼란 누적 전 뒤집기(S3) 금지", "스택 4 이상이거나 만료 직전에 소비", "교환(S2)은 적을 우리 킬박스로", "바나나(S4)로 확정 제어"], 
		"target": {"low": 0.75, "threat": 0.9, "backline": 1.15, "isolated": 0.95}, 
		"geometry": "flank", "combos": ["S1·S4 혼란 누적 → S3 계수 뒤집기"]}, 
	"metatron": {"title": "쌍익 순환 수호", "code": "SERAPH ORBIT", "roles": ["SUPPORT", "PROTECTOR"], 
		"principles": ["날개가 아군과 적에 함께 닿는 궤도", "구원의 비행(S3)은 최저 체력 아군에게", "활공(S4)은 착지점 다수에", "회전(S1)은 날개 접촉이 있을 때"], 
		"target": {"low": 0.55, "threat": 0.85, "backline": 0.45, "isolated": 0.4}, 
		"geometry": "orbit", "combos": ["S3 구원 비행 → S4 활공 낙하"]}, 
	"plague_doctor": {"title": "역병 억제·회수", "code": "PLAGUE TRIAGE", "roles": ["CONTROLLER", "SUPPORT"], 
		"principles": ["회복형 적에게 역병 우선", "충분한 역병은 다른 적으로 분산", "힐 주머니(S2)는 실제 결손에", "독침(S3)으로 스택 유지"], 
		"target": {"low": 0.55, "threat": 0.8, "backline": 0.75, "isolated": 0.35}, 
		"geometry": "backline", "combos": ["S1 역병 분무 → S3 독침 → S2 회수 분사"]}, 
	"hive_mind": {"title": "공유 신경망 지휘", "code": "SYNAPTIC COMMAND", "roles": ["COMMANDER", "SUMMONER"], 
		"principles": ["감염(S2) 확보 후 조종(S3)", "조종은 화력이 큰 적에게", "조종 만료 직전이나 처치 가능할 때 자해(S4)", "소환물 뒤에서 지휘"], 
		"target": {"low": 0.65, "threat": 1.2, "backline": 0.8, "isolated": 0.6}, 
		"geometry": "summon_screen", "combos": ["S2 기생 감염 → S3 군체 조종 → S4 자해 명령"]}, 
	"nitro": {"title": "벽면 과급 충돌", "code": "WALL REDLINE", "roles": ["DIVER", "BRAWLER"], 
		"principles": ["스택 없이 폭쇄 구체(S1) 낭비 금지", "벽면 점화(S2)는 표적 방향 벽에서", "연쇄 자폭(S3)은 속도가 실린 접촉에", "벽 접촉으로 최대 스택 확장"], 
		"target": {"low": 0.7, "threat": 0.75, "backline": 0.9, "isolated": 0.8}, 
		"geometry": "wall", "combos": ["S2 벽면 질주 → S3 연쇄 자폭 → S1 폭쇄"]}, 
	"dimensionalist": {"title": "차원 자원·탄도 방어", "code": "RIFT ECONOMY", "roles": ["WARDEN", "FINISHER"], 
		"principles": ["균열(S1)은 실제 투사체에", "포탈을 지나 조각을 모은다", "30조각 칼날(S4)은 마무리에", "아군 원거리 탄이 있을 때 탄도 전환(S3)"], 
		"target": {"low": 0.9, "threat": 1.1, "backline": 0.85, "isolated": 0.55}, 
		"geometry": "portal", "combos": ["S2 쌍문 → 통과 조각 ×3 → S4 차원 칼날"]}, 
	"hermes": {"title": "초고속 정찰·CC 회수", "code": "TALARIA TEMPO", "roles": ["SCOUT", "FINISHER"], 
		"principles": ["투명(S1) 접근 뒤 재시전 기절", "수면(S2) 뒤에는 평타 대신 하르페(S3)", "하르페는 CC 중인 적에게만", "혼자 깊이 들어가지 않는다"], 
		"target": {"low": 0.9, "threat": 0.8, "backline": 1.15, "isolated": 1.0}, 
		"geometry": "flank", "combos": ["S2 수면 → S3 하르페", "S1 은신 접근 → 재시전 기절 → S3"]}, 
	"world_tree": {"title": "생명 폐곡선 수호", "code": "LIVING GROVE", "roles": ["SUPPORT", "ZONE"], 
		"principles": ["아군 곁에서 폐곡선을 닫아 재생 영역", "영역 안 적에게만 뿌리(S2)", "속박 뒤 가시(S3)", "꽃(S4)은 부상 아군의 이동선에"], 
		"target": {"low": 0.6, "threat": 0.9, "backline": 0.4, "isolated": 0.4}, 
		"geometry": "grove", "combos": ["폐곡선 영역 → S2 뿌리 → S3 가시의 계절"]}, 
	"torturer": {"title": "고통 누적·감금 수사", "code": "PAIN AND EVIDENCE", "roles": ["CONTROLLER", "DISRUPTOR"], 
		"principles": ["평타·채찍으로 고통을 갱신한다", "고통 3스택 후 재갈로 스킬을 막는다", "채찍 외연에서 2스택을 확보한다", "감금 뒤 필요한 정보 한 종류를 선택한다"], 
		"target": {"low": 0.9, "threat": 1.2, "backline": 0.9, "isolated": 0.8}, 
		"geometry": "whip_edge", "combos": ["S1 외연 → 평타 → S2 재갈", "S3 감금 → S4 정보 캐기 → 아군 집중"]},
	"politician": {"title": "관조·정보전 지휘", "code": "PUBLIC NARRATIVE", "roles": ["SUPPORT", "DISRUPTOR"],
		"principles": ["안전한 아군 후방에서 정지해 관조를 유지한다", "불신 10스택이면 가짜 뉴스를 아낀다", "건강하고 방어력이 높은 아군에게 시선을 돌린다", "아군 교전 직전에 선전으로 능력치를 강화한다"],
		"target": {"low": 0.2, "threat": 1.2, "backline": 0.6, "isolated": 0.2},
		"geometry": "backline", "combos": ["관조 → S3 선전 → S1 가짜 뉴스", "S2 화제 돌리기 → 불신 초기화 → S1"]},
	"engineer": {"title": "포탑 사선 요새", "code": "IRON WORKSHOP", "roles": ["ZONE", "SUMMONER"], 
		"principles": ["사선이 열린 곳에 포탑(S1)", "개조(S4)는 포탑 곁에서", "철거(S2)는 처치나 부서지기 직전 포탑으로", "드라이버(S3)는 적 뒤가 벽일 때"], 
		"target": {"low": 0.8, "threat": 1.0, "backline": 0.7, "isolated": 0.5}, 
		"geometry": "workshop", "combos": ["S1 포탑 → S4 현장 개조 → S2 비상 철거"]}, 
	"hades": {"title": "명계 매복 전선", "code": "UNDERWORLD AMBUSH", "roles": ["TANK", "AMBUSHER", "ANTI_HEAL"],
		"principles": ["체력이 낮으면 시야를 끊거나 수풀로 물러나 키네에로 회복", "은신 중 적이 450 안이면 망자 소환(S1)으로 선제, 가능하면 수풀 경유", "명계 위반(S2)은 15% 아래로 떨어뜨릴 회복형 적에게", "영혼 수확(S3)은 주변 적 수 × 남은 틱으로"],
		"target": {"low": 1.2, "threat": 0.8, "backline": 0.6, "isolated": 0.9},
		"geometry": "ambush", "combos": ["은신 → S1 망자 소환 → 접근 → S3 영혼 수확", "S2 명계 위반 15% 마무리 → 회복 불가"]},
	"war_machine": {"title": "연료 순환 돌격", "code": "FUEL CYCLE", "roles": ["DIVER", "BRAWLER", "ZONE"],
		"principles": ["제노사이드(S4)가 가까우면 연료 7을 비축한다", "유도폭격(S2)은 비축분을 뺀 연료로, 근접 위협 곁에서는 충전하지 않는다", "아크 프로텍터(S3)는 3초 예상 피해가 크거나 진입할 때", "탱크가 터지면 과열 폭주로 평타 올인, 부스터(S1)로 붙는다"],
		"target": {"low": 1.1, "threat": 0.8, "backline": 0.95, "isolated": 0.9},
		"geometry": "pursuit", "combos": ["평타 연료 7 → S4 제노사이드 → S2 유도폭격", "S1 부스터 진입 → S3 아크 프로텍터 → 평타", "탱크 파괴 → 과열 폭주 평타 + S1 추격"]},
	# V2 (TorquemadaTactics): cleanse value over own allies, peel and the
	# retaliatory root on enemies that controlled him.
	"torquemada": {"title": "이단 심판과 정화", "code": "INQUISITION", "roles": ["SUPPORT", "CLEANSER", "PEEL"],
		"principles": ["제어당한 아군을 아우토다페(S1) 불 하나에 모아 정화", "적 진입 신호에 제어가 아직 없으면 정화를 아낀다", "나를 제어한 적은 6초 안에 형사 절차 지침(S2)으로 속박", "아군을 위협하는 150 이내 근접 적은 알람브라 칙령(S3)으로 밀어낸다"],
		"target": {"low": 0.5, "threat": 1.15, "backline": 0.4, "isolated": 0.35},
		"geometry": "body_block", "combos": ["적의 제어 → S1 정화의 불 → S2 즉결 속박", "근접 돌진 → S3 칙령 정화·밀쳐내기"]},
	"achilles": {"title": "불사의 돌파", "code": "MYRMIDON BREACH", "roles": ["TANK", "ENGAGE", "DISRUPTOR"],
		"principles": ["정면으로 오는 투사체·돌진·폭딜에 방패(S2)를 위협 쪽으로 든다", "방패를 든 동안 주 위협을 정면에 둔다", "포효(S3)는 아군 제어가 6초 안에 들어갈 때나 전차 직전에", "전차(S4)는 보이는 적이 둘 이상일 때"],
		"target": {"low": 0.85, "threat": 1.1, "backline": 0.9, "isolated": 0.6},
		"geometry": "body_block", "combos": ["S3 포효 → S4 전차 → 아군 제어", "S1 관통 창으로 일렬 견제·고방어 적에 고정 피해"]},
}

const ROLE_LABEL: = {"FINISHER": "마무리", "FLANKER": "측면", "CARRY": "주 화력", "MARKSMAN": "저격", "CONTROLLER": "제어", 
	"ZONE": "구역", "DIVER": "돌진", "HUNTER": "추격", "TANK": "탱커", "ENGAGE": "개전", "GUARD": "수비", "SUPPORT": "지원", 
	"PROTECTOR": "보호", "PICK": "낚아채기", "PEEL": "호위", "SKIRMISHER": "교전", "DISRUPTOR": "교란", "COMMANDER": "지휘", 
	"SUMMONER": "소환", "BRAWLER": "난전", "WARDEN": "탄도 방어", "SCOUT": "정찰",
	"AMBUSHER": "매복", "ANTI_HEAL": "회복 차단",
	"CLEANSER": "정화"}

const HARD: = ["stun", "root", "airborne", "suppression", "sleep", "charm", "control", "taunt"]


static func of(id: String) -> Dictionary:
	return PROFILE.get(id, {})







static func target_mult(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief) -> float:
	if e == null or not e.is_hero:
		return 1.0
	var w: Dictionary = PROFILE.get(u.def.id, {}).get("target", {})
	if w.is_empty():
		return 1.0
	var low: = 1.0 - e.hp / maxf(1.0, e.max_hp)
	var thr: = float(b.eprof.get(e.idx, {}).get("threat", 300.0)) / maxf(1.0, float(b.plan.get("max_threat", 600.0)))
	var back: = 1.0 if e.def.preferred_range > 150.0 else 0.0
	var iso: = clampf((float(b.plan.get("iso", {}).get(e.idx, 250.0)) - 200.0) / 300.0, 0.0, 1.0)
	var s: = float(w.get("low", 1.0)) * (low - 0.35) + float(w.get("threat", 1.0)) * (thr - 0.7)\
	+ float(w.get("backline", 1.0)) * (back - 0.5) + float(w.get("isolated", 1.0)) * (iso - 0.3)
	return clampf(1.0 + 0.2 * s, 0.78, 1.32)






static func _ab(_b: TacticianBrain, u: BUnit, slot: int) -> Defs.AbilityDef:
	if slot < 1 or slot > u.def.abilities.size():
		return null
	return u.def.abilities[slot - 1]


static func _ready(b: TacticianBrain, u: BUnit, slot: int) -> bool:
	var a: = _ab(b, u, slot)
	return a != null and b.sim.ability_ready(u, slot - 1, a)



static func _ready_in(b: TacticianBrain, u: BUnit, slot: int) -> float:
	if slot < 1 or slot > u.cooldowns.size() or u.sealed.has(slot - 1):
		return 99.0
	return maxf(0.0, u.cooldowns[slot - 1] - b.sim.time)


static func _own(b: TacticianBrain, u: BUnit, idx: int, status: StringName) -> ST.Status:
	var t: = b.sim.u_at(idx)
	if t == null or not t.alive or (t.team != u.team and not b.sim.is_seen(u.team, t)):
		return null
	return b.sim.owned_status(t, status, u.idx)


static func _own_stacks(b: TacticianBrain, u: BUnit, idx: int, status: StringName) -> int:
	var s: = _own(b, u, idx, status)
	return s.stacks if s else 0


static func _own_rem(b: TacticianBrain, u: BUnit, idx: int, status: StringName) -> float:
	var s: = _own(b, u, idx, status)
	return maxf(0.0, s.end - b.sim.time) if s else 0.0



static func _enemy(b: TacticianBrain, idx: int) -> TeamIntel.EnemyBelief:
	if b.intel.enemies.has(idx):
		return b.intel.enemies[idx]
	if b.intel.entities.has(idx):
		return b.intel.entities[idx]
	return null



static func incoming(b: TacticianBrain, u: BUnit, horizon: float = 1.0) -> float:
	var r: = b.sim.radius(u)
	var total: = 0.0
	for pj in b.intel.projectiles:
		var v: Vector2 = pj.vel
		var sp: = v.length()
		if sp < 1.0:
			continue
		var rel: Vector2 = u.pos - (pj.pos as Vector2)
		if pj.homing:
			if int(pj.target) == u.idx and rel.length() / sp < horizon:
				total += float(pj.dmg)
			continue
		var along: = rel.dot(v) / sp
		if along <= 0.0 or along / sp > horizon:
			continue
		var closest: Vector2 = (pj.pos as Vector2) + v / sp * along
		if closest.distance_to(u.pos) < float(pj.radius) + r + 6.0:
			total += float(pj.dmg) * (1.5 if pj.cc else 1.0)
	for tg in b.intel.telegraphs:
		if float(tg.due) - b.sim.time < horizon and b._in_telegraph(u.pos, r, tg):
			total += float(tg.dmg) * (1.4 if tg.cc else 1.0)
	return total



static func attack_window(b: TacticianBrain, x: BUnit, e: TeamIntel.EnemyBelief, h: float = 2.0) -> float:
	var ap: Dictionary = b.aprof.get(x.idx, {})
	if ap.is_empty() or e == null:
		return 0.0
	var st: Dictionary = ap.st
	var gap: = maxf(0.0, x.pos.distance_to(e.pos) - float(st.range) - b.sim.radius(x) - e.radius)
	var approach: = gap / maxf(30.0, float(st.ms))
	return float(ap.dps) * maxf(0.0, h - approach)



static func team_window(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief, h: float = 2.0) -> float:
	var s: = 0.0
	for x in b.allies_cache:
		if x != u and x.alive:
			s += attack_window(b, x, e, h)
	return s


static func _nearest_enemy_d(_b: TacticianBrain, u: BUnit, ctx: Dictionary) -> float:
	var nd: = INF
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if e.is_hero:
			nd = minf(nd, u.pos.distance_to(e.pos) - e.radius - float(ctx.r))
	return nd


static func _melee_close(_b: TacticianBrain, u: BUnit, ctx: Dictionary, dist: float) -> int:
	var n: = 0
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if e.is_hero and e.def.preferred_range < 120.0 and u.pos.distance_to(e.pos) - e.radius - float(ctx.r) < dist:
			n += 1
	return n


static func _note(c: Dictionary, delta: float, text: String) -> void :
	if absf(delta) < 0.5:
		return
	c.value = float(c.value) + delta
	var notes: Array = c.get("notes", [])
	notes.append("%s %+.0f" % [text, delta])
	c["notes"] = notes


# V1.5.3: first enemy body (hero or visible summon/structure) that a straight
# dash or projectile from u toward e would touch before e. Allies are passed
# through by contact dashes and projectiles, so they never block (audit
# swordsman S1 / werewolf S4 / pirate S2 / homing shots).
static func path_blocker(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief, width: float) -> TeamIntel.EnemyBelief:
	var to: Vector2 = e.pos - u.pos
	var total: float = to.length()
	if total < 1.0:
		return null
	var best: TeamIntel.EnemyBelief = null
	var best_t: float = total - e.radius
	for t in b.intel.visible_enemies(true):
		var x: TeamIntel.EnemyBelief = t
		if x.idx == e.idx:
			continue
		var tu: BUnit = b.sim.u_at(x.idx)
		if tu == null or not tu.alive or b.sim.has_status(tu, &"untargetable"):
			continue
		var along: float = (x.pos - u.pos).dot(to / total)
		if along <= 0.0 or along >= best_t:
			continue
		var cp: Vector2 = u.pos + to / total * along
		if cp.distance_to(x.pos) < width + x.radius - 2.0:
			best = x
			best_t = along
	return best


# The prey rule of werewolf S1 exactly as the engine applies it: a hero this
# werewolf itself observes at or below 40% health (kits.gd scent tick).
static func scent_prey(b: TacticianBrain, u: BUnit, ctx: Dictionary) -> TeamIntel.EnemyBelief:
	var best: TeamIntel.EnemyBelief = null
	var bd: float = INF
	for t in ctx.targets:
		var e: TeamIntel.EnemyBelief = t
		if not e.is_hero or e.hp / maxf(1.0, e.max_hp) > 0.40:
			continue
		var tu: BUnit = b.sim.u_at(e.idx)
		if tu == null or not b.sim.observes(u, tu):
			continue
		var d: float = u.pos.distance_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best


# Pirate S4 (함포 반동) as the engine resolves it (projectiles.gd area_impact):
# the ball stops at the first enemy body on its path, a wall, or the aim point,
# then a forward cone (radius a.radius, angle a.angle) from that impact point
# hits every enemy inside with line of sight. Returns the impact point, the
# expected targets and their value. Call-site: _position_candidates.
static func cone_blast(b: TacticianBrain, u: BUnit, a: Defs.AbilityDef, aim: Vector2, ctx: Dictionary) -> Dictionary:
	var sim: BattleSim = b.sim
	var to: Vector2 = aim - u.pos
	var total: float = to.length()
	if total < 1.0:
		return {"impact": aim, "hits": 0, "value": 0.0}
	var dir: Vector2 = to / total
	var pr: float = a.width * 0.5
	var reach: float = total
	var wall: Dictionary = sim.arena.terrain_contact(u.pos, aim, pr, true)
	if not wall.is_empty():
		reach = u.pos.distance_to(wall.point)
	for t in ctx.targets:
		var x: TeamIntel.EnemyBelief = t
		var px: Vector2 = b.lead_point(u.pos, x, a.speed, a.cast_time, 0.7)
		var along: float = (px - u.pos).dot(dir)
		if along <= 0.0 or along - x.radius >= reach:
			continue
		var lat: float = (u.pos + dir * along).distance_to(px)
		var rr: float = x.radius + pr
		if lat < rr:
			var entry: float = along - sqrt(maxf(0.0, rr * rr - lat * lat))
			if entry < reach:
				reach = maxf(0.0, entry)
	var impact: Vector2 = u.pos + dir * reach
	var delay: float = a.cast_time + reach / maxf(50.0, a.speed)
	var ang: float = a.angle if a.angle > 0.0 else 1.4
	var hits: int = 0
	var value: float = 0.0
	for t2 in ctx.targets:
		var y: TeamIntel.EnemyBelief = t2
		var py: Vector2 = b.lead_point(impact, y, 0.0, delay, 0.7)
		var v: Vector2 = py - impact
		var dist: float = v.length()
		if dist > a.radius + y.radius or dist <= 0.001:
			continue
		if acos(clampf(v.normalized().dot(dir), -1.0, 1.0)) > ang * 0.5 + y.radius / maxf(1.0, dist):
			continue
		if not sim.arena.line_of_sight(impact, py, minf(6.0, y.radius * 0.15)):
			continue
		var margin: float = a.radius + y.radius - dist
		var esc: float = y.ms() * maxf(0.0, delay - 0.22 - y.hard_cc_remaining()) * (0.35 + 0.65 * y.dodge_rate())
		var hp: float = 0.9 if esc <= margin else clampf(margin / maxf(1.0, esc), 0.1, 0.9)
		value += float(b._enemy_value(u, a, y, ctx, hp).value)
		hits += 1
	return {"impact": impact, "hits": hits, "value": value}


# Torturer S3: the engine re-checks the 110 range (both radii) when the cast
# resolves. Distance the target can open during the wind-up.
static func prison_margin(u: BUnit, e: TeamIntel.EnemyBelief, a: Defs.AbilityDef) -> float:
	var away: Vector2 = (e.pos - u.pos).normalized() if e.pos.distance_squared_to(u.pos) > 1.0 else Vector2.RIGHT
	return clampf(6.0 + maxf(0.0, e.vel.dot(away)) * (a.cast_time + 0.06) + (8.0 if e.vel.length() < 1.0 and e.movement_lock_remaining() <= a.cast_time else 0.0), 6.0, 36.0)


# Our hermes keeps a slept enemy for its own harpe (S3): true while it is
# near with S3 ready. Allies then hold non-lethal damage (audit hermes S2).
static func hermes_sleep_claim(b: TacticianBrain, u: BUnit, e: TeamIntel.EnemyBelief) -> bool:
	if e == null or not e.is_hero or not e.has_status("sleep"):
		return false
	for x in b.allies_cache:
		if x == u or not x.alive or x.def.id != "hermes" or x.team != b.team:
			continue
		# Only while its own order still names the sleeper (the sleep it just
		# cast, or the harpe): a hermes that cloaks away must not freeze us.
		if int(x.command.get("target", -1)) != e.idx:
			continue
		if x.cooldowns.size() > 2 and x.cooldowns[2] <= b.sim.time + 0.35 and not x.sealed.has(2) and x.pos.distance_to(e.pos) <= 150.0:
			return true
	return false


# Our own damage already on its way to e (a shot in flight or one of our
# damage-over-time statuses) would wake a slept target before the harpe.
static func _sleep_breaker(b: TacticianBrain, e: TeamIntel.EnemyBelief) -> bool:
	for row in e.statuses:
		if bool(row.get("own", false)) and str(row.get("type", "")) in ["dot", "pain"]:
			return true
	for p in b.sim.proj.list:
		if p.dead or p.team != b.team:
			continue
		if p.target_idx == e.idx:
			return true
		var sp: float = p.vel.length()
		if sp < 1.0:
			continue
		var rel: Vector2 = e.pos - p.pos
		var along: float = rel.dot(p.vel) / sp
		if along > 0.0 and along / sp < 1.6 and (p.pos + p.vel / sp * along).distance_to(e.pos) < p.radius + e.radius + 6.0:
			return true
	return false


# The hive mind of our team that controls this (enemy) unit right now.
static func _controller_hive(b: TacticianBrain, u: BUnit) -> BUnit:
	for st in u.statuses:
		if st.type == &"control" and st.end > b.sim.time:
			var h: BUnit = b.sim.u_at(st.source_idx)
			if h and h.alive and b.sim.eteam(h) == b.team:
				return h
	return null






static func move_points(b: TacticianBrain, u: BUnit, ctx: Dictionary, tgt: TeamIntel.EnemyBelief, pts: Array) -> void :
	_support_points(b, u, ctx, pts)
	var prof: Dictionary = PROFILE.get(u.def.id, {})
	if prof.is_empty():
		return
	var sim: = b.sim
	var r: float = ctx.r
	var geo: = str(prof.get("geometry", ""))
	var enemy_c: Vector2 = b.plan.get("enemy_c", u.pos)
	var ally_c: Vector2 = b.plan.get("ally_c", u.pos)
	match geo:
		"flank", "pursuit":
			if tgt and tgt.visible:

				var out: = (tgt.pos - enemy_c)
				var side: = Vector2( - (tgt.pos - u.pos).y, (tgt.pos - u.pos).x).normalized()
				if side.dot(u.pos - tgt.pos) < 0.0:
					side = - side
				var reach: = float(ctx.range) + r + tgt.radius - 6.0
				var behind: = out.normalized() if out.length() > 30.0 else side
				pts.append([tgt.pos + (behind * 0.6 + side * 0.8).normalized() * reach, "교리: 측면 진입", 6.0])
		"kite", "max_range":
			if tgt and tgt.visible:
				var reach2: = float(ctx.range) + r + tgt.radius - 8.0
				var away: = (u.pos - tgt.pos).normalized() if u.pos.distance_to(tgt.pos) > 1.0 else (ally_c - enemy_c).normalized()

				if u.pos.distance_to(tgt.pos) <= reach2 + 20.0 or str(b.plan.stance) == "ENGAGE":
					for sgn in [-1.0, 1.0]:
						pts.append([tgt.pos + away.rotated(0.35 * sgn) * reach2, "교리: 사거리선", 6.0])
		"body_block", "screen":

			var carry: = sim.u_at(int(b.plan.get("carry", -1)))
			var threat: TeamIntel.EnemyBelief = tgt
			if carry and carry != u and carry.alive:
				var best_d: = INF
				for t in ctx.targets:
					var e: TeamIntel.EnemyBelief = t
					if e.is_hero and e.pos.distance_to(carry.pos) < best_d:
						best_d = e.pos.distance_to(carry.pos)
						threat = e
				if threat:
					var along: = 0.45 if geo == "body_block" else 0.3
					pts.append([carry.pos.lerp(threat.pos, along), "교리: 몸막이", 10.0])
		"guard_carry", "orbit":
			var carry2: = sim.u_at(int(b.plan.get("carry", -1)))
			if carry2 and carry2 != u and carry2.alive:
				var dir: = (enemy_c - carry2.pos).normalized()
				if geo == "orbit" and tgt and tgt.visible and tgt.pos.distance_to(carry2.pos) < 260.0:

					var mid: = carry2.pos.lerp(tgt.pos, 0.5)
					pts.append([mid, "교리: 쌍익 교차 궤도", 12.0])
				else:
					pts.append([carry2.pos + dir * 70.0, "교리: 주 화력 곁 호위", 8.0])
		"whip_edge":
			if tgt and tgt.visible:
				var away3: = (u.pos - tgt.pos).normalized() if u.pos.distance_to(tgt.pos) > 1.0 else (ally_c - enemy_c).normalized()
				pts.append([tgt.pos + away3 * (190.0 + tgt.radius), "교리: 채찍 외연", 10.0])
		"summon_screen":
			if tgt and tgt.visible:
				var brood: = 0
				for e2 in sim.entities:
					if e2.alive and e2.owner_idx == u.idx and e2.kind in ["brood", "parasite"]:
						brood += 1
				if brood > 0:
					pts.append([tgt.pos + (u.pos - tgt.pos).normalized() * 240.0, "교리: 소환물 뒤 지휘", 8.0])
		"hook_lane":
			if tgt and tgt.visible and _ready(b, u, 1):
				var away4: = (u.pos - tgt.pos).normalized() if u.pos.distance_to(tgt.pos) > 1.0 else (ally_c - enemy_c).normalized()
				pts.append([tgt.pos + away4 * 250.0, "교리: 낚싯줄 사선", 8.0])
		"wall":
			_nitro_points(b, u, ctx, tgt, pts)
		"portal":
			_portal_points(b, u, ctx, pts)
		"workshop":
			var near_tw: BUnit = null
			for tw in sim.kits.owned_entities(u, "turret"):
				if near_tw == null or tw.pos.distance_to(u.pos) < near_tw.pos.distance_to(u.pos):
					near_tw = tw
			if near_tw and near_tw.level < 3 and _ready_in(b, u, 4) < 1.5:
				pts.append([near_tw.pos + (ally_c - enemy_c).normalized() * 50.0, "교리: 포탑 곁 개조 거리", 14.0])
		"hybrid":
			if tgt and tgt.visible:
				var away5: = (u.pos - tgt.pos).normalized() if u.pos.distance_to(tgt.pos) > 1.0 else (ally_c - enemy_c).normalized()
				pts.append([tgt.pos + away5 * (sim.radius(u) + tgt.radius + 55.0), "교리: 칼 거리", 4.0])

	match u.def.id:
		"swordsman":
			if _ready(b, u, 4):
				for t in ctx.targets:
					var e: TeamIntel.EnemyBelief = t
					if e.is_hero and _own_rem(b, u, e.idx, &"bladeTrace") > 0.3:
						var a4: = _ab(b, u, 4)
						if u.pos.distance_to(e.pos) > a4.range + r:
							pts.append([e.pos + (u.pos - e.pos).normalized() * (a4.range - 20.0), "교리: 추적 만료 전 접근", 30.0])
		"werewolf":
			for t in ctx.targets:
				var e2: TeamIntel.EnemyBelief = t
				if e2.is_hero and e2.hp / maxf(1.0, e2.max_hp) <= 0.4:
					var lead: = b.lead_point(u.pos, e2, 0.0, 0.45)
					pts.append([lead + (u.pos - lead).normalized() * (r + e2.radius + 20.0), "교리: 혈향 추격", 14.0 if sim.get_buff(u, &"originScent") else 6.0])
		"hermes":
			if float(u.ks.get("cloak_until", 0.0)) > sim.time and tgt and tgt.visible:
				pts.append([tgt.pos + (u.pos - tgt.pos).normalized() * (r + tgt.radius + 40.0), "교리: 은신 기절 거리 접근", 26.0])
		"hades":
			HadesTactics.move_points(b, u, ctx, tgt, pts)
	# Metatron S4, or a glide borrowed by hermes: keep a live landing target
	# (steer() flies at it).
	if float(u.ks.get("glide_until", 0.0)) > sim.time:
		_glide_retarget(b, u, ctx)


# V1.5.3 points shared by every hero: step into our own healing (bed, mist),
# and an enemy we control stays near the hive mind that must finish it.
static func _support_points(b: TacticianBrain, u: BUnit, ctx: Dictionary, pts: Array) -> void:
	var sim: BattleSim = b.sim
	if u.team != b.team:
		var hive: BUnit = _controller_hive(b, u)
		if hive:
			pts.append([hive.pos + (u.pos - hive.pos).limit_length(150.0), "조종 대상: 군체 곁", 60.0])
		return
	if float(ctx.hpr) >= 0.85 or u.chamber != "":
		return
	var missing: float = float(ctx.mx) - float(ctx.hp)
	for z in sim.zones.list:
		if z.team != b.team or z.end <= sim.time + 0.4:
			continue
		if z.kind == "bed":
			var d: float = u.pos.distance_to(z.pos)
			if d < 420.0 and d > z.radius * 0.6:
				pts.append([z.pos + (u.pos - z.pos).limit_length(z.radius * 0.45), "침상 회복", 16.0 + minf(missing, 400.0) * 0.1])
		elif z.kind == "mist" and float(z.data.get("budget", 0.0)) > 20.0:
			var d2: float = u.pos.distance_to(z.pos)
			if d2 >= 260.0:
				continue
			# A travelling mist outruns walkers: meet it where it will park.
			var park: Vector2 = z.pos + z.dir * maxf(0.0, float(z.data.get("range", 240.0)) - float(z.data.get("distance", 0.0)))
			var goal: Vector2 = z.pos if d2 < z.radius + 10.0 else (park if u.pos.distance_to(park) < d2 + 60.0 else z.pos)
			pts.append([goal, "회수 분사 안으로", 14.0 + minf(missing, float(z.data.get("budget", 0.0))) * 0.12])
	# Our world tree is walking a loop drawn around this injured ally: wait
	# inside it so the garden closes around us (plan lives in brain memory).
	for x in b.allies_cache:
		if x == u or not x.alive or x.def.id != "world_tree":
			continue
		var gp: Dictionary = (b.mem.get(x.idx, {}) as Dictionary).get("grove", {})
		if gp.is_empty() or not (gp.get("who", []) as Array).has(u.idx):
			continue
		var lc: Vector2 = gp.c
		var inner: float = float(gp.r) * 0.45
		var wait_at: Vector2 = u.pos if u.pos.distance_to(lc) <= inner else lc + (u.pos - lc).limit_length(inner * 0.6)
		pts.append([wait_at, "폐곡선 안에서 대기", 12.0 + minf(missing, 400.0) * 0.1])
	# World tree gardens heal allies standing inside the closed polygon.
	for g in sim.gardens:
		if int(g.team) != b.team or float(g.end) <= sim.time + 1.0 or float(g.budget) <= 20.0:
			continue
		var poly: PackedVector2Array = g.points
		if poly.is_empty() or Geometry2D.is_point_in_polygon(u.pos, poly):
			continue
		var gc: Vector2 = Vector2.ZERO
		for q in poly:
			gc += q
		gc /= poly.size()
		if gc.distance_to(u.pos) < 300.0 and Geometry2D.is_point_in_polygon(gc, poly):
			pts.append([gc, "재생 영역 안으로", 14.0 + minf(missing, float(g.budget)) * 0.1])


# Metatron S4: the landing airborne hits whoever is within 110 when the 1.2 s
# glide ends. TacticianBrain.steer is the one steering path (audit D10,
# review 1.5.3): it flies at the enemy the glide was launched at, on a
# prediction refreshed every tick, whatever the move order. Doctrine only
# replaces a target that is lost (dead, unseen for 1 s, out of reach) with the
# enemy whose landing catches the most heroes. The plan lives in brain
# memory, never in the simulator's kit state.
static func _glide_retarget(b: TacticianBrain, u: BUnit, ctx: Dictionary) -> void:
	if b._glide_target(u) != null:
		return
	var sim: BattleSim = b.sim
	var rem: float = maxf(0.05, float(u.ks.get("glide_until", 0.0)) - sim.time)
	var reach: float = float(ctx.ms) * rem + 60.0
	var e: TeamIntel.EnemyBelief = null
	var best_n: int = 0
	for t in ctx.targets:
		var x: TeamIntel.EnemyBelief = t
		if not x.is_hero:
			continue
		var lx: Vector2 = b.lead_point(u.pos, x, 0.0, rem, 0.8)
		if u.pos.distance_to(lx) > reach:
			continue
		var n: int = 1
		for t2 in ctx.targets:
			var y: TeamIntel.EnemyBelief = t2
			if y != x and y.is_hero and y.pos.distance_to(lx) < 110.0 + y.radius - 10.0:
				n += 1
		if n > best_n:
			best_n = n
			e = x
	var m: Dictionary = b.mem.get(u.idx, {})
	if e == null:
		b._glide_to.erase(u.idx)
		m.erase("glide_target")
	else:
		b._glide_to[u.idx] = e.idx
		m["glide_target"] = e.idx
	b.mem[u.idx] = m


static func _nitro_points(b: TacticianBrain, u: BUnit, _ctx: Dictionary, tgt: TeamIntel.EnemyBelief, pts: Array) -> void :
	var sim: = b.sim
	var wb: = int(u.ks.get("wall_bonus", 0))
	var dw: = sim.distance_to_wall(u.pos)

	if wb < 4 and not bool(u.ks.get("wall_near", false)) and dw < 200.0 and str(b.plan.stance) != "ENGAGE":
		var tang: = sim.wall_tangent(u.pos)
		var normal: = Vector2( - tang.y, tang.x)
		var probe: = u.pos + normal * dw
		if sim.distance_to_wall(probe) > dw * 0.5:
			probe = u.pos - normal * dw
		pts.append([probe, "교리: 벽 접촉 충전", 6.0])
	if tgt and tgt.visible and sim.get_buff(u, &"contactExplosion"):
		var dir: = (tgt.pos - u.pos).normalized()
		pts.append([b.lead_point(u.pos, tgt, 0.0, 0.35) + dir * 60.0, "교리: 충격 통과선", 24.0])


static func _portal_points(b: TacticianBrain, u: BUnit, _ctx: Dictionary, pts: Array) -> void :
	var sim: = b.sim
	var shards: = float(u.resources.get("shards", 0.0))
	if shards >= 30.0 or str(b.plan.stance) == "DISENGAGE":
		return
	for pp in sim.portal_pairs:
		if float(pp.end) <= sim.time + 0.6 or int(pp.team) != b.team:
			continue

		var a: Vector2 = pp.a
		var c: Vector2 = pp.b
		var near: = a if u.pos.distance_to(a) < u.pos.distance_to(c) else c
		if u.pos.distance_to(near) < 260.0:
			# Review 1.5.3: the walk ends at the FAR end; never farm shards
			# through a pair that lands outside the closing ring (still safe 2 s
			# after arrival) or in an always-on damage field.
			var far: Vector2 = c if near == a else a
			var ring: Dictionary = b._ring_def() if sim.env.enabled else {}
			var eta: float = u.pos.distance_to(near) / maxf(40.0, float(_ctx.ms))
			# The traveller comes out past the far end (radius + body + 3).
			var land: Vector2 = far + (far - near).normalized() * (float(pp.radius) + float(_ctx.r) + 3.0)
			if not ring.is_empty() and Arena.ring_outside(ring, land, sim.time + eta + 2.0, float(_ctx.r) * 0.3 + 10.0):
				continue
			if b._static_damage_at(far, float(_ctx.r)):
				continue
			pts.append([near, "교리: 포탈 통과 (조각 +10)", 26.0 + (30.0 - shards) * 0.6])






static func adjust(b: TacticianBrain, u: BUnit, ctx: Dictionary, cands: Array) -> void :
	var id: = u.def.id
	_team_notes(b, u, ctx, cands)
	HadesTactics.enemy_notes(b, u, ctx, cands) # V2: facing hades' pet and shades
	WarMachineTactics.enemy_notes(b, u, ctx, cands)
	# V2: every hero facing a raised achilles guard (AchillesTactics).
	AchillesTactics.enemy_notes(b, u, ctx, cands)
	if not PROFILE.has(id):
		return
	var abilities: = b.sim.ability_list(u)
	for c in cands:
		var cmd: Dictionary = c.cmd
		var kind: = str(cmd.get("kind", ""))
		var a: Defs.AbilityDef = null
		if kind == "ability":
			var ix: = int(cmd.get("index", -1))
			if ix >= 0 and ix < abilities.size():
				a = abilities[ix]
		var e: TeamIntel.EnemyBelief = null
		var ti: = int(cmd.get("target", -1))
		if ti >= 0:
			e = _enemy(b, ti)
		match id:
			"swordsman":
				_swordsman(b, u, ctx, c, kind, a, e)
			"archer":
				_archer(b, u, ctx, c, kind, a, e)
			"mage":
				_mage(b, u, ctx, c, kind, a, e)
			"sniper":
				_sniper(b, u, ctx, c, kind, a, e)
			"werewolf":
				_werewolf(b, u, ctx, c, kind, a, e)
			"giant":
				_giant(b, u, ctx, c, kind, a, e)
			"aphrodite":
				_aphrodite(b, u, ctx, c, kind, a, e)
			"blood_mage":
				_blood_mage(b, u, ctx, c, kind, a, e)
			"fisherman":
				_fisherman(b, u, ctx, c, kind, a, e)
			"baseball":
				_baseball(b, u, ctx, c, kind, a, e)
			"pirate":
				_pirate(b, u, ctx, c, kind, a, e)
			"joker":
				_joker(b, u, ctx, c, kind, a, e)
			"metatron":
				_metatron(b, u, ctx, c, kind, a, e)
			"plague_doctor":
				_plague(b, u, ctx, c, kind, a, e)
			"hive_mind":
				_hive(b, u, ctx, c, kind, a, e)
			"nitro":
				_nitro(b, u, ctx, c, kind, a, e)
			"dimensionalist":
				_dimensionalist(b, u, ctx, c, kind, a, e)
			"hermes":
				_hermes(b, u, ctx, c, kind, a, e)
			"world_tree":
				_world_tree(b, u, ctx, c, kind, a, e)
			"torturer":
				_torturer(b, u, ctx, c, kind, a, e)
			"politician":
				_politician(b, u, ctx, c, kind, a)
			"engineer":
				_engineer(b, u, ctx, c, kind, a, e)
			"hades":
				HadesTactics.adjust(b, u, ctx, c, kind, a, e)
			"war_machine":
				WarMachineTactics.adjust(b, u, ctx, c, kind, a, e)
			"torquemada":
				TorquemadaTactics.doctrine_adjust(b, u, ctx, c, kind, a, e)
			"achilles":
				AchillesTactics.adjust(b, u, ctx, c, kind, a, e)


static func _slot(a: Defs.AbilityDef) -> int:
	return a.slot if a and not a.virtual else 0


# V1.5.3 cross-hero coordination notes that apply to every hero's candidates.
static func _team_notes(b: TacticianBrain, u: BUnit, ctx: Dictionary, cands: Array) -> void:
	var sim: BattleSim = b.sim
	# An enemy unit our hive mind controls: stay within its self-harm range.
	if u.team != b.team:
		var hive: BUnit = _controller_hive(b, u)
		if hive:
			for c0 in cands:
				var cm: Dictionary = (c0 as Dictionary).cmd
				if str(cm.get("kind", "")) != "move":
					continue
				var g: Vector2 = cm.get("goal", u.pos)
				var far: float = g.distance_to(hive.pos) - 260.0
				if far > 0.0:
					_note(c0, -far * 0.6, "조종 대상: 군체 곁 유지")
		return
	# Enemies our hermes put to sleep and is about to harpe (usually none):
	# any non-lethal damage, aimed or area, would wake them (audit hermes).
	var claimed: Array = []
	for t in ctx.get("targets", []):
		var se: TeamIntel.EnemyBelief = t
		if se.is_hero and hermes_sleep_claim(b, u, se):
			claimed.append(se)
	if claimed.is_empty():
		return
	var abilities: Array = sim.ability_list(u)
	for c in cands:
		var cmd: Dictionary = (c as Dictionary).cmd
		var kind: String = str(cmd.get("kind", ""))
		if kind != "basic" and kind != "ability":
			continue
		if float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0:
			continue
		var a: Defs.AbilityDef = null
		if kind == "ability":
			var ix: int = int(cmd.get("index", -1))
			if ix < 0 or ix >= abilities.size():
				continue
			a = abilities[ix]
			if u.def.id == "hermes" and a.slot == 3 and not a.virtual:
				continue
			var damaging: bool = false
			for f in a.effects:
				if str(f.get("type", "")) in ["damage", "dot", "delayed_area"]:
					damaging = true
					break
			if not damaging:
				continue
		var ti: int = int(cmd.get("target", -1))
		var wakes: bool = false
		for x in claimed:
			var se2: TeamIntel.EnemyBelief = x
			if ti >= 0:
				wakes = wakes or ti == se2.idx
			elif a and a.target == "position":
				var p: Vector2 = cmd.get("pos", u.pos)
				wakes = wakes or p.distance_to(se2.pos) <= maxf(a.radius, 30.0) + se2.radius
		if wakes:
			_note(c, -maxf(0.0, float(c.value)) * 0.9 - 25.0, "헤르메스 수면 유지 → 하르페 대기")



static func _swordsman(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind == "basic":

		if int(u.ks.get("basic_count", 0)) % 3 == 2:
			_note(c, 16.0, "세 번째 검세")
		return
	if kind != "ability" or e == null:
		return
	var kill: bool = float((c.get("parts", {}) as Dictionary).get("처치", 0.0)) > 0.0
	# S2 cone reach on this target (for the mark-first ordering below).
	var a2: Defs.AbilityDef = _ab(b, u, 2)
	var in_s2: bool = a2 != null and _ready(b, u, 2) and u.pos.distance_to(e.pos) <= a2.range + float(ctx.r) + e.radius - 4.0 \
		and _own(b, u, e.idx, &"bladeMark") == null
	match s:
		1:
			# The dash stops at the first enemy body; allies are passed through.
			var blocker: TeamIntel.EnemyBelief = path_blocker(b, u, e, b.sim.radius(u))
			if blocker:
				_note(c, -45.0 if not blocker.is_hero else -20.0, "대시 경로가 막힘" if not blocker.is_hero else "다른 적이 먼저 닿음")
			if in_s2 and not kill:
				_note(c, -minf(40.0, maxf(0.0, float(c.value)) * 0.3) - 8.0, "검흔 먼저")
		2:
			if _own(b, u, e.idx, &"bladeMark"):
				_note(c, -20.0, "검흔 중복")
			else:
				# Each follow-up active that lands while the mark lasts procs it.
				var follow: int = 0
				for sl in [1, 3, 4]:
					if _ready_in(b, u, sl) < 1.2 and (sl != 4 or _own(b, u, e.idx, &"bladeTrace") != null or _ready_in(b, u, 3) < 1.2):
						follow += 1
				if follow > 0:
					var proc: float = (16.0 + 0.18 * float(ctx.st.ad)) * 100.0 / (100.0 + e.def.stat("armor"))
					_note(c, 14.0 + 12.0 * follow + proc * follow * 0.8, "검흔 → 연계 추가 피해")
		3:
			if _own(b, u, e.idx, &"bladeTrace") == null and _ready_in(b, u, 4) < 2.5:
				var s4: = _ab(b, u, 4)
				var ev: = KitModel.evaluate(s4.effects, ctx.st, {})
				_note(c, KitModel.mitigate(ev, 0.0, 0.0) * 0.55 * float(b._ew(e.idx)), "침묵 추적 → 배후 절단 예약")
			if in_s2 and not kill:
				_note(c, -minf(40.0, maxf(0.0, float(c.value)) * 0.3) - 8.0, "검흔 먼저")
		4:
			# Trace expiry urgency (audit swordsman S4): the closer the 4 s
			# trace is to expiring, the more of the backcut's value is lost.
			var rem: = _own_rem(b, u, e.idx, &"bladeTrace")
			var urgency: float = (1.0 - clampf(rem / 4.0, 0.0, 1.0)) * maxf(0.0, float(c.value))
			if rem < 1.2:
				urgency = maxf(urgency, 60.0)
			_note(c, 24.0 + urgency, "추적 만료 전 회수")
			if in_s2 and rem > 1.0 and not kill:
				_note(c, -minf(30.0, maxf(0.0, float(c.value)) * 0.2), "검흔 먼저")
			# Own trace = own engage window: the team gates must not hold it.
			c["gate_exempt"] = true



static func _archer(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			if _melee_close(b, u, ctx, 150.0) == 0 and incoming(b, u, 1.0) < 40.0:
				_note(c, -60.0, "후퇴 사격은 실제 진입에 보존")
		3:
			if e:
				var hpr: = e.hp / maxf(1.0, e.max_hp)
				var res: = float(b.reserved.get(e.idx, 0.0))
				if hpr <= 0.18 or (e.hp - res * 0.8) / maxf(1.0, e.max_hp) <= 0.18:
					_note(c, 60.0, "처형 경계")
				elif float(c.parts.get("처치", 0.0)) <= 0.0:
					# Above 18% at impact the arrow only chips: keep the execute
					# for the threshold instead of spending a 16 s cooldown.
					_note(c, -maxf(0.0, float(c.value)) - 30.0, "처형 보존")
		4:
			var window: = false
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and u.pos.distance_to(x.pos) <= float(ctx.range) + float(ctx.r) + x.radius + 70.0:
					window = true
			_note(c, 24.0 if window else -30.0, "질풍 장전 사격 창")



static func _mage(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			if e and e.hard_cc_remaining() < 0.3 and _ready_in(b, u, 2) < 0.6:
				_note(c, 34.0, "속박 → 화염진 예약")
		2:

			var p: Vector2 = c.cmd.pos
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and x.pos.distance_to(p) < 82.0 + x.radius and x.hard_cc_remaining() >= 0.75:
					_note(c, 28.0, "제어 위 화염진")
					break
		3:
			if e:
				var tu: = b.sim.u_at(e.idx)
				if tu:
					for st in tu.statuses:
						if st.type == &"dot" and st.source_idx == u.idx and st.end - b.sim.time > 1.2:
							_note(c, -30.0, "연소 중복")
							break



static func _sniper(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	var primed: = b.sim.get_buff(u, &"originSniperRound") != null
	if kind == "basic":
		if primed and e and e.is_hero:
			_note(c, 30.0, "취약 낙인 평타")
		return
	if kind != "ability":
		return
	var close: = _melee_close(b, u, ctx, 170.0)
	match s:
		1:
			if primed and u.attack_ready_at <= b.sim.time + 0.3 and e and float(c.parts.get("처치", 0.0)) <= 0.0:
				_note(c, -30.0, "낙인 평타 먼저")
			if e and e.hard_cc_remaining() >= 0.8:
				_note(c, 26.0, "제어 창 필중")
			if e and _own(b, u, e.idx, &"sniperVulnerable"):
				_note(c, 18.0, "취약 낙인 사격")
		2:
			if incoming(b, u, 0.9) < maxf(60.0, u.hp * 0.12) and close == 0:
				_note(c, -70.0, "매복은 임박한 피해에 보존")
		3:
			var shoot: = false
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and u.pos.distance_to(x.pos) <= float(ctx.range) + float(ctx.r) + x.radius + 40.0:
					shoot = true
			_note(c, 26.0 if shoot else -40.0, "평타 발사 가능한 낙인 준비")
		4:
			var kill: = float(c.parts.get("처치", 0.0)) > 0.0
			if close == 0 and not kill and (e == null or e.casting.is_empty()):
				_note(c, -75.0, "제압탄은 근접 돌입 대응용")
			elif close > 0:
				_note(c, 30.0, "돌진 대응 제압")



static func _werewolf(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			# Game rule: a hero this werewolf itself sees at <= 40% health.
			var prey: TeamIntel.EnemyBelief = scent_prey(b, u, ctx)
			_note(c, 30.0 if prey else -80.0, "추격 가능한 저체력 먹잇감")
		2:
			var gain: = 0.0
			for t in ctx.targets:
				var x2: TeamIntel.EnemyBelief = t
				if x2.is_hero and x2.hp > u.hp:
					gain = maxf(gain, attack_window(b, u, x2, 2.0) * (x2.hp - u.hp) / maxf(1.0, b.sim.max_hp(u)))
			_note(c, minf(45.0, gain * 0.6) - (25.0 if gain <= 0.0 else 0.0), "체력차 포식")
		3:
			var casting: = 0
			for t in ctx.targets:
				var x3: TeamIntel.EnemyBelief = t
				if x3.is_hero and not x3.casting.is_empty() and u.pos.distance_to(x3.pos) <= 100.0 + x3.radius + float(ctx.r):
					casting += 1
			if casting > 0:
				_note(c, 40.0 * casting, "포효로 시전 차단")
		4:
			if e:
				var follow: = team_window(b, u, e, 1.3)
				_note(c, minf(40.0, follow * 0.25), "제압 중 아군 후속 화력")
				# The bite suppresses the first enemy body on its line.
				var blocker: TeamIntel.EnemyBelief = path_blocker(b, u, e, b.sim.radius(u))
				if blocker:
					if blocker.is_hero:
						_note(c, -maxf(0.0, float(c.value)) * 0.35, "다른 적이 먼저 닿음")
					else:
						_note(c, -maxf(0.0, float(c.value)) * 0.8 - 25.0, "소환물이 돌진 경로를 막음")



static func _giant(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:

			var carry: = b.sim.u_at(int(b.plan.get("carry", -1)))
			if carry and carry != u:
				var rad: = a.radius * b.sim.radius_scale(u)
				for t in ctx.targets:
					var x: TeamIntel.EnemyBelief = t
					if x.is_hero and x.pos.distance_to(u.pos) <= rad + x.radius and x.pos.distance_to(carry.pos) < 150.0:
						_note(c, 35.0, "후열 위협 에어본")
						break
		2:
			var hpr: = u.hp / b.sim.max_hp(u)
			if hpr > 0.92 and float(ctx.danger) < 30.0:
				_note(c, -60.0, "과잉 회복 방지")
			elif hpr < 0.65:
				_note(c, 18.0, "피해 직후 재생")



static func _aphrodite(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			if e and (b.plan.get("peel_threats", {}) as Dictionary).has(e.idx):
				_note(c, 40.0, "후열 돌진자 유혹")
		2:
			# Alone (deathmatch, solo battleground or last hero) the bed is a personal heal spot.
			var alone: bool = b.sim.fights_alone()
			if not alone:
				alone = true
				for x0 in b.allies_cache:
					if x0 != u and x0.alive:
						alone = false
						break
			if not alone:
				var p: Vector2 = c.cmd.pos
				var occ: = 0
				for x in b.allies_cache:
					if x.alive and x.pos.distance_to(p) <= 110.0:
						occ += 1
				if occ < 2:
					_note(c, -25.0, "두 명이 머물 침상 아님")
		4:
			var tgt_u: = b.sim.u_at(int(c.cmd.get("target", -1)))
			if tgt_u and tgt_u.hp / b.sim.max_hp(tgt_u) < 0.5:
				_note(c, -40.0, "저체력 아군 강제 추격 금지")

			if not bool(b.plan.get("go", false)) and int(b.plan.get("punish", -1)) < 0:
				_note(c, - maxf(0.0, float(c.value)) - 40.0, "진입 신호 전 강제 돌진 금지")



static func _blood_mage(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability" or s == 0:
		return
	var hpr: = u.hp / b.sim.max_hp(u)
	if s != 3 and hpr < 0.28:
		_note(c, -45.0, "체력 파산 방지")
	match s:
		3:
			if hpr < 0.6 and e:
				_note(c, 22.0, "흡혈 회수")
		4:
			var snakes: = 0
			for x in b.sim.kits.owned_entities(u, "snake"):
				if x.end_time - b.sim.time > 4.0:
					snakes += 1
			if snakes > 0:
				_note(c, -12.0 * snakes, "뱀 생존 중")



static func _fisherman(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability" or e == null:
		return
	match s:
		1:

			var dest: = u.pos + (e.pos - u.pos).normalized() * (b.sim.radius(u) + e.radius + 8.0)
			var fake: = TeamIntel.EnemyBelief.new()
			fake.pos = dest
			fake.radius = e.radius
			var follow: = 0.0
			for x in b.allies_cache:
				if x != u and x.alive:
					follow += attack_window(b, x, fake, 1.5)
			var bonus: = minf(30.0, follow * 0.1)
			if _ready_in(b, u, 4) < 0.8:
				bonus += 45.0
			# D6: the kill box only exists if the hook actually lands.
			if bonus > 0.0:
				bonus *= clampf(float(c.parts.get("명중", 0.6)) / 0.6, 0.0, 1.0)
			if e.def.preferred_range < 120.0:
				for x2 in b.allies_cache:
					if x2 != u and x2.alive and x2.pos.distance_to(dest) < 170.0 and b.aprof.get(x2.idx, {}).get("backline", false):
						bonus -= 45.0
						break
			_note(c, bonus, "낚시 킬박스")
		4:
			var rem: = _own_rem(b, u, e.idx, &"hooked")
			_note(c, 26.0 + (26.0 if rem < 1.0 else 0.0), "인양 표식 확정")



static func _baseball(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		2:
			if incoming(b, u, 1.0) <= 0.0:
				var ranged: = 0
				for t in ctx.targets:
					var x: TeamIntel.EnemyBelief = t
					if x.is_hero and x.def.preferred_range > 150.0 and u.pos.distance_to(x.pos) < 420.0:
						ranged += 1
				if ranged == 0:
					_note(c, -45.0, "헬멧은 투사체에 예약")
		3:
			var hit: = 0.0
			for x2 in b.allies_cache:
				if x2.alive and x2.pos.distance_to(u.pos) < 130.0 + b.sim.radius(x2):
					hit += b.danger_at(x2, x2.pos, 1.0)
			if hit < 40.0:
				_note(c, -35.0, "실제 공격받는 아군이 없음")
			else:
				_note(c, minf(40.0, hit * 0.08), "벤치 클리어링 방어")



static func _pirate(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	var primed: = b.sim.get_buff(u, &"originPirateRound") != null
	if kind == "basic":
		if primed and e and e.is_hero:
			_note(c, 28.0, "약탈 평타")
		if e and u.pos.distance_to(e.pos) <= 70.0 + b.sim.radius(u) + e.radius:
			_note(c, 8.0, "커틀러스 고정 피해")
		return
	if kind != "ability":
		return
	match s:
		1, 4:
			if primed and u.attack_ready_at <= b.sim.time + 0.3 and float(c.parts.get("처치", 0.0)) <= 0.0:
				_note(c, -26.0, "약탈 평타 먼저")
			if s == 4 and not (c.parts as Dictionary).has("부채꼴"):
				# The broadside is a forward cone from the impact point (first
				# body / wall / aim), not a circle around the aim (audit S4).
				var aim: Vector2 = c.cmd.get("pos", u.pos)
				var cb: Dictionary = cone_blast(b, u, a, aim, ctx)
				var appr: float = b._approach_factor(u, u.pos.distance_to(aim), a.range + float(ctx.r), ctx)
				_note(c, (float(cb.value) - float(c.parts.get("범위", 0.0))) * appr, "함포 부채꼴 %d명" % int(cb.hits))
				c.parts["부채꼴"] = int(cb.hits)
				c["label"] = "%s (%d명)" % [a.name, int(cb.hits)]
		2:
			if e:
				# The grapple flies to the first body it touches and lands there.
				var blocker: TeamIntel.EnemyBelief = path_blocker(b, u, e, a.width * 0.5)
				if blocker and not blocker.is_hero:
					_note(c, -maxf(0.0, float(c.value)) * 0.8 - 20.0, "갈고리 경로를 소환물이 막음")
				var land_on: TeamIntel.EnemyBelief = blocker if blocker else e
				var land: Vector2 = land_on.pos + (u.pos - land_on.pos).normalized() * (float(ctx.r) + land_on.radius + 4.0)
				var dz: float = maxf(0.0, b.danger_at(u, land, 1.0) - float(ctx.danger))
				if dz > 0.0:
					_note(c, -dz * float(ctx.risk_w) * 0.6, "갈고리 착지 위험")
					if float(ctx.hpr) < 0.4 and float(c.parts.get("처치", 0.0)) <= 0.0:
						_note(c, -30.0, "저체력 갈고리 진입 금지")
		3:
			var shoot: = false
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and u.pos.distance_to(x.pos) <= float(ctx.range) + float(ctx.r) + x.radius + 50.0:
					shoot = true
			_note(c, 24.0 if shoot else -36.0, "약탈 사용 창")



static func _joker(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability" or e == null:
		return
	var n: = _own_stacks(b, u, e.idx, &"confusion")
	match s:
		1, 4:
			if n < 4:
				_note(c, 12.0, "혼란 누적")
		3:
			var rem: = _own_rem(b, u, e.idx, &"confusion")
			if n >= 4:
				_note(c, 30.0, "혼란 %d스택 폭발" % n)
			elif rem < 0.8:
				_note(c, 16.0, "만료 전 소비")
			elif float(c.parts.get("처치", 0.0)) <= 0.0:
				_note(c, -30.0, "누적 대기")



static func _metatron(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			if str(u.ks.get("wing_mode", "orbit")) != "orbit":
				_note(c, -45.0, "날개 비행 중")
		3:
			var t: = b.sim.u_at(int(c.cmd.get("target", -1)))
			if t and t.hp / b.sim.max_hp(t) < 0.5:
				_note(c, 26.0, "최저 체력 아군 구조")



static func _plague(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability" or e == null:
		return
	if s == 1 or s == 3:
		var sup: = KitModel.support_rate(e.def)
		if sup > 4.0:
			_note(c, minf(30.0, sup * 2.2), "회복형 적 역병")
		var n: = _own_stacks(b, u, e.idx, &"plague")
		if n >= 4 and _own_rem(b, u, e.idx, &"plague") > 2.0:
			_note(c, -20.0, "충분한 역병 — 분산")



static func _hive(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1, 2:
			# Keep the hive free for the self-harm order while a control runs
			# out (audit hive S4: most controls expired with the hive busy).
			if _ready_in(b, u, 4) < 0.5:
				for k in b.intel.enemies:
					var ce: TeamIntel.EnemyBelief = b.intel.enemies[k]
					if ce.dead or not ce.controlled_by_us:
						continue
					var cu: BUnit = b.sim.u_at(ce.idx)
					var st: ST.Status = b.sim.owned_status(cu, &"control", u.idx) if cu else null
					if st and st.end - b.sim.time < 1.3:
						_note(c, -maxf(0.0, float(c.value)) - 40.0, "자해 명령 대기")
						break
		3:
			if e:
				_note(c, minf(25.0, team_window(b, u, e, 2.0) * 0.08), "조종 중 아군 화력")



static func _nitro(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	var rage: = float(u.resources.get("rage", 0.0))
	match s:
		1:
			if rage <= 2.0 and float(c.parts.get("처치", 0.0)) <= 0.0:
				_note(c, -24.0, "최소 스택 보존")
			elif rage >= 6.0:
				_note(c, 20.0, "과급 폭발")
		3:
			# The aura only reaches body + 20: an edge gap beyond ~120 means
			# most of the 5 s ticks are spent walking (audit nitro S3).
			var near: = _nearest_enemy_d(b, u, ctx)
			if near < 80.0 and u.vel.length() > 60.0:
				_note(c, 28.0, "속도 실린 접촉")
			elif near > 120.0:
				_note(c, -35.0 - minf(40.0, (near - 120.0) * 0.25), "접촉 창 없음")



static func _dimensionalist(b: TacticianBrain, u: BUnit, _ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			if incoming(b, u, 1.2) < 50.0:
				_note(c, -40.0, "균열은 실제 탄도에")
		4:
			if e and float(c.parts.get("처치", 0.0)) > 0.0:
				_note(c, 40.0, "차원 칼날 확정 마감")



static func _hermes(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	# While cloaked the recast stun (radius 90) opens the combo; a basic or an
	# enemy-target cast only breaks stealth without it (audit hermes S1).
	var recast_ready: bool = float(u.ks.get("cloak_until", 0.0)) > b.sim.time and float(u.ks.get("cloak_ready_at", 0.0)) <= b.sim.time + 0.05
	var recast_hits: int = 0
	if recast_ready:
		for t in ctx.targets:
			var x: TeamIntel.EnemyBelief = t
			if x.is_hero and u.pos.distance_to(x.pos) <= 90.0 + x.radius - 2.0:
				recast_hits += 1
	if kind == "basic":

		if e and e.is_hero and e.has_status("sleep") and _ready_in(b, u, 3) < 0.6 and float(c.value) < 200.0:
			_note(c, -30.0, "수면 유지 → 하르페")
		if recast_hits > 0 and float(c.parts.get("처치", 0.0)) <= 0.0:
			_note(c, -maxf(0.0, float(c.value)) * 0.7 - 20.0, "은신 재시전 기절 먼저")
		return
	if kind != "ability":
		return
	match s:
		1:
			if recast_ready and recast_hits > 0 and _ready_in(b, u, 3) < 0.6:
				_note(c, 30.0, "은신 기절 → 하르페 연계")
		2:
			if e and e.hard_cc_remaining() > 0.7:
				_note(c, -25.0, "제어 중복")
			if e and _sleep_breaker(b, e):
				_note(c, -maxf(0.0, float(c.value)) * 0.6 - 20.0, "아군 탄·지속 피해가 수면을 깸")
			if recast_hits > 0 and float(c.parts.get("처치", 0.0)) <= 0.0:
				_note(c, -maxf(0.0, float(c.value)) * 0.7 - 20.0, "은신 재시전 기절 먼저")
		3:
			if e and e.hard_cc_remaining() > 0.15:
				_note(c, 40.0, "CC 회수")



static func _world_tree(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, _e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	if s == 3:

		var rooted: = 0
		for g in b.sim.gardens:
			if g.source != u.idx:
				continue
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and x.hard_cc_remaining() > 0.5 and Geometry2D.is_point_in_polygon(x.pos, g.points):
					rooted += 1
		if rooted > 0:
			_note(c, 28.0 * rooted, "속박 뒤 가시")




static func _torturer(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void:
	var slot: int = _slot(a)
	if e == null or not e.is_hero:
		return
	var stacks: int = _own_stacks(b, u, e.idx, &"pain")
	var remaining: float = _own_rem(b, u, e.idx, &"pain")
	if kind == "basic" or (kind == "ability" and slot == 1):
		if stacks > 0:
			_note(c, 8.0 + minf(18.0, stacks * 3.0), "고통 갱신 %d/6" % stacks)
		if stacks > 0 and remaining < 1.4:
			_note(c, 24.0, "고통 소멸 전 갱신")
	if kind != "ability":
		return
	match slot:
		1:
			var distance: float = u.pos.distance_to(e.pos)
			if distance >= a.range * 0.7 and distance <= a.range + e.radius:
				_note(c, 24.0, "채찍 외연: 추가 피해·고통 2스택")
			if stacks == 1 or stacks == 2:
				_note(c, 15.0, "재갈 조건 3스택 준비")
		2:
			if stacks < 3:
				_note(c, -500.0, "재갈 조건 미충족")
			elif e.has_status("silence") and e.casting.is_empty():
				_note(c, -35.0, "침묵 중복 보존")
			else:
				_note(c, 20.0, "고통 3스택: 확정 침묵")
		3:
			if e.has_status("imprisoned"):
				_note(c, -140.0, "감금 중복 보존")
			else:
				_note(c, minf(40.0, team_window(b, u, e, 2.0) * 0.15), "감금 방어력 감소에 아군 연계")
			# The engine re-checks 110 + both radii when the 0.32 s wind-up
			# resolves (audit torturer S3). Start the cast only close enough
			# for the target's escape: aim beyond it and shorten the approach.
			var r: float = float(ctx.r)
			var m: float = prison_margin(u, e, a)
			var dir: Vector2 = (e.pos - u.pos).normalized() if e.pos.distance_squared_to(u.pos) > 1.0 else u.facing
			c.cmd["pos"] = e.pos + dir * m
			c.cmd["need"] = maxf(40.0, a.range + r - m)
			var lim: float = 110.0 + r + e.radius - 6.0
			if u.pos.distance_to(e.pos) + m <= a.range + r + 8.0:
				var pred: Vector2 = b.lead_point(u.pos, e, 0.0, a.cast_time)
				if u.pos.distance_to(pred) > lim:
					_note(c, -maxf(0.0, float(c.value)) - 60.0, "감금 해제 거리 예측")
		4:
			if _own_rem(b, u, e.idx, &"imprisoned") <= a.cast_time:
				_note(c, -200.0, "감금 만료 전 정보 수집 불가")
			# Health and position of a visible prisoner are already observed
			# every tick; only the cooldowns are new team information.
			var extra: Dictionary = c.cmd.get("extra", {})
			extra["info_kind"] = "cooldowns"
			c.cmd["extra"] = extra


static func _politician(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef) -> void:
	if kind == "move":
		var goal: Vector2 = c.cmd.get("goal", u.pos)
		var safe: bool = float(ctx.danger) < float(ctx.ehp) * 0.12 and (not b.sim.env.enabled or b.sim.env.hazard_penalty(u.pos, b.sim.time + 0.6, float(ctx.r)) < 0.1)
		var nearby: int = 0
		for ally in ctx.allies:
			if (ally as BUnit).pos.distance_to(u.pos) < 420.0:
				nearby += 1
		var seen: bool = not (ctx.targets as Array).is_empty()
		if not safe or not seen:
			return
		var ec: Vector2 = b.plan.get("enemy_c", u.pos)
		if goal.distance_to(u.pos) < 8.0:
			# Contemplation needs 0.45 s standing still; it is the kit's core
			# (coefficient, CC immunity, information shield). V1.5.3: +80 while
			# safe and in play (an ally within 420, or a visible enemy within
			# its 350 working range), instead of the +32 that every rally,
			# ring or front-join move outbid; +32 when left alone.
			var in_play: bool = nearby > 0
			if not in_play:
				for t0 in ctx.targets:
					var x0: TeamIntel.EnemyBelief = t0
					if x0.is_hero and u.pos.distance_to(x0.pos) <= u.def.preferred_range + 60.0:
						in_play = true
						break
			_note(c, 80.0 if in_play else 32.0, "관조 유지: 계수 강화·CC 면역·정보 보호")
			return
		var label: String = str(c.get("label", ""))
		if label.begins_with("회피") or label.begins_with("후퇴") or label.contains("위험"):
			return
		if goal.distance_to(u.pos) < 60.0 and nearby > 0:
			# A short shuffle while safe restarts the 0.45 s settle for no gain.
			_note(c, -25.0, "관조 중 소폭 이동 자제")
		elif goal.distance_to(ec) > u.pos.distance_to(ec) + 20.0:
			# Outside every visible enemy's reach + 100 there is nothing to
			# retreat from: stepping back only breaks contemplation.
			var outside: bool = true
			for t in ctx.targets:
				var x: TeamIntel.EnemyBelief = t
				if x.is_hero and u.pos.distance_to(x.pos) <= float(b.eprof.get(x.idx, {}).get("reach", 250.0)) + 100.0:
					outside = false
					break
			if outside:
				_note(c, -40.0, "사거리 밖: 이동 대신 관조")
		return
	if kind != "ability" or a == null:
		return
	if b.sim.warfare.contemplating(u):
		_note(c, 15.0, "관조 계수 강화 활용")
	# Casting at distrust 9 raises it to 10, which wipes every active false
	# report (information_warfare._fake_news): the guard starts at 9.
	if a.action == "fakeNews" and int(b.sim.warfare.enemy_distrust(u.team)) >= 9:
		_note(c, -500.0, "불신 9스택 이상: 정보 조작 보존")

static func _engineer(b: TacticianBrain, u: BUnit, ctx: Dictionary, c: Dictionary, kind: String, a: Defs.AbilityDef, e: TeamIntel.EnemyBelief) -> void :
	var s: = _slot(a)
	if kind != "ability":
		return
	match s:
		1:
			var towers: = b.sim.kits.owned_entities(u, "turret").size()
			if towers >= 3:
				_note(c, -20.0, "기존 포탑 교체 손실")
			var p: Vector2 = c.cmd.pos
			if p.distance_to(u.pos) <= 100.0 and _ready_in(b, u, 4) < 2.0:
				_note(c, 16.0, "즉시 개조 거리")
		2:
			# Emergency demolition resolves after the 0.28 s wind-up and needs
			# line of sight from the turret (kits.gd detonate): re-score the
			# blast at predicted positions (audit engineer S2).
			var aim: Vector2 = c.cmd.get("pos", u.pos)
			var tower: BUnit = null
			for tw in b.sim.kits.owned_entities(u, "turret"):
				if tw.pos.distance_to(u.pos) <= 420.0 and (tower == null or tw.pos.distance_to(aim) < tower.pos.distance_to(aim)):
					tower = tw
			if tower:
				var mult: float = 1.0 + 0.25 * (tower.level - 1)
				var val: float = 0.0
				for t in ctx.targets:
					var x: TeamIntel.EnemyBelief = t
					if not x.is_hero:
						continue
					var px: Vector2 = b.lead_point(tower.pos, x, 0.0, a.cast_time, 0.8)
					var margin: float = 115.0 + x.radius - px.distance_to(tower.pos)
					if margin <= 0.0 or not b.sim.arena.line_of_sight(tower.pos, px, 2.0):
						continue
					var esc: float = x.ms() * maxf(0.0, a.cast_time - 0.18 - x.hard_cc_remaining()) * (0.35 + 0.65 * x.dodge_rate())
					var hp: float = 1.0 if esc <= margin else clampf(margin / maxf(1.0, esc), 0.2, 1.0)
					var dmg: float = (90.0 + 0.65 * float(ctx.st.ap) + 0.4 * float(ctx.st.ad)) * mult * 100.0 / (100.0 + x.def.stat("magicResistance"))
					val += dmg * hp * (1.35 if ctx.focus and (ctx.focus as TeamIntel.EnemyBelief).idx == x.idx else 1.0)
					if dmg >= x.hp + x.shield:
						val += 250.0 * hp
				val -= 40.0 + 25.0 * tower.level
				var old: float = float((c.get("parts", {}) as Dictionary).get("피해", c.value))
				_note(c, val - old, "철거 시점 예측·시야")
		3:
			if e:

				var dir: = (e.pos - u.pos).normalized()
				var back: = e.pos + dir * 95.0
				if not b.sim.arena.is_walkable(back, e.radius) or b.sim.distance_to_wall(back) < e.radius + 4.0:
					_note(c, 45.0, "벽 충돌 고정")
