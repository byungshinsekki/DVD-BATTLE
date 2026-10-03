

class_name CharData

const LIST: Array = [
	{
		"id": "swordsman",
		"name": "검사",
		"glyph": "劍",
		"accent": "#65a7ff",
		"role": "DAMAGE",
		"tags": [
			"MELEE",
			"BURST",
			"ENGAGE",
			"MOBILITY",
			"SINGLE_TARGET",
			"CONTROL"
		],
		"summary": "표식을 쌓고 검기로 경로를 연 뒤 배후로 파고드는 근접 연계 공격수.",
		"stats": {
			"maxHealth": 1100,
			"attackDamage": 73,
			"abilityPower": 24,
			"armor": 34,
			"magicResistance": 28,
			"moveSpeed": 108,
			"attackSpeed": 0.78,
			"attackRange": 46,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 18
		},
		"preferredRange": 48,
		"behavior": {
			"aggression": 0.77,
			"survival": 0.34,
			"focusLowHealth": 0.72,
			"focusHighThreat": 0.47,
			"protectAllies": 0.2,
			"preferBackline": 0.72,
			"preferCluster": 0.3,
			"riskTolerance": 0.66,
			"flank": 0.65,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "연계 추격형"
		},
		"doctrine": {
			"title": "검흔 연계 돌파",
			"code": "SILENT BACKCUT",
			"roles": [
				"FINISHER",
				"FLANKER",
				"SECONDARY_ENGAGE"
			],
			"identity": "검기로 진입 허가를 만든 뒤 배후 절단으로 마무리하는 연계 결투가."
		},
		"nexus": {
			"title": "검흔 연쇄 돌파",
			"role": "FLANK",
			"risk": 0.72,
			"teamwork": 0.78,
			"gamble": 0.45,
			"information": 0.54,
			"combo": [
				2,
				3,
				4,
				1
			],
			"skills": [
				"접촉 대시의 빗나감 비용을 반영",
				"검흔을 먼저 깔아 후속 피해 증폭",
				"침묵·추적으로 배후 진입권 확보",
				"자기 추적만 소비하고 고립위험 평가"
			],
			"identity": "사선 제압 뒤 측면에서 표식 연계로 단일 대상을 제거한다."
		},
		"passives": [
			{
				"name": "삼중 검세",
				"description": "평타 3회마다 28+0.35AD 추가 물리 피해를 줍니다(치명타 적용). 대상이 멀어져 빗나간 평타도 횟수에 포함됩니다.",
				"rules": [
					{
						"type": "nth_basic_bonus",
						"every": 3,
						"damage": {
							"type": "damage",
							"school": "physical",
							"base": 28,
							"ad": 0.35,
							"ap": 0
						}
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "파고드는 일격",
				"description": "지정 방향으로 150 돌진해 처음 닿은 적에게 60+0.65AD 물리 피해를 주고 멈춥니다. 벽에 막히거나 아무도 닿지 않으면 피해가 없고, 돌진 중 속박·기절 등에 걸리면 중단됩니다.",
				"cooldown": 7,
				"castTime": 0.12,
				"recovery": 0.18,
				"range": 150,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 32,
				"angle": 0.9,
				"speed": 520,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "move_self",
						"mode": "dash",
						"distance": 150,
						"towardTarget": true,
						"speed": 520
					},
					{
						"type": "damage",
						"school": "physical",
						"base": 60,
						"ad": 0.65,
						"ap": 0
					}
				],
				"condition": null,
				"ai": {
					"intent": "engage",
					"weight": 1.15,
					"cluster": 0,
					"survival": 0,
					"combo": 0.3
				},
				"tags": [
					"MOBILITY",
					"ENGAGE"
				],
				"action": "contactDash",
				"vfx": {
					"color": "#5c9fff",
					"pattern": "slash",
					"glyph": "突"
				},
				"geometry": "돌진 150, 폭 32, 속도 520",
				"timing": "7 / 0.12",
				"flags": {
					"originDistance": 150
				}
			},
			{
				"slot": 2,
				"name": "초승달 낙인",
				"description": "전방 부채꼴(반경 100, 75°)의 모든 적에게 64+0.65AD 물리 피해와 4초 검흔을 남깁니다. 검흔이 있는 적을 이 검사의 S1·S3·S4로 맞히면 16+0.18AD 추가 물리 피해를 줍니다(시전·대상당 1회, 0.4초 간격). 평타와 S2는 검흔을 터뜨리지 않습니다.",
				"cooldown": 9.5,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 100,
				"target": "enemy",
				"delivery": "cone",
				"shape": "cone",
				"radius": 22,
				"width": 24,
				"angle": 1.308997,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "damage",
						"school": "physical",
						"base": 64,
						"ad": 0.65,
						"ap": 0
					},
					{
						"type": "mark",
						"status": "bladeMark",
						"duration": 4,
						"stacks": 1,
						"maxStacks": 1,
						"originOwned": true,
						"originBladeBonus": {
							"base": 16,
							"ad": 0.18
						}
					}
				],
				"condition": null,
				"ai": {
					"intent": "damage",
					"weight": 1.05,
					"cluster": 0.55,
					"survival": 0,
					"combo": 0.65
				},
				"tags": [
					"AREA_DAMAGE"
				],
				"action": "",
				"vfx": {
					"color": "#83c0ff",
					"pattern": "crescent",
					"glyph": "月"
				},
				"geometry": "부채꼴 75°",
				"timing": "9.5 / 0.25"
			},
			{
				"slot": 3,
				"name": "침묵의 검기",
				"description": "직선 검기가 최대 2명을 관통해 58+0.5AD 물리 피해, 침묵 1초, 4초 검기 추적을 남깁니다. 검기 추적은 배후 절단의 사용 조건입니다.",
				"cooldown": 12,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 270,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "line",
				"radius": 22,
				"width": 26,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 1,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "damage",
						"school": "physical",
						"base": 58,
						"ad": 0.5,
						"ap": 0
					},
					{
						"type": "status",
						"status": "silence",
						"duration": 1,
						"magnitude": 0
					},
					{
						"type": "mark",
						"status": "bladeTrace",
						"duration": 4,
						"stacks": 1,
						"maxStacks": 1,
						"originOwned": true
					}
				],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.15,
					"cluster": 0,
					"survival": 0,
					"combo": 0.8
				},
				"tags": [
					"RANGED",
					"CONTROL"
				],
				"action": "",
				"vfx": {
					"color": "#89ddff",
					"pattern": "wave",
					"glyph": "封"
				},
				"geometry": "폭 26, 속도 420",
				"timing": "12 / 0.25"
			},
			{
				"slot": 4,
				"name": "배후 절단",
				"description": "내 검기 추적이 남은 적의 등 뒤(30)로 순간이동해 80+0.45AD 고정 피해를 주고 추적을 소비합니다. 다른 검사가 남긴 추적으로는 쓸 수 없습니다.",
				"cooldown": 17.5,
				"castTime": 0.1,
				"recovery": 0.18,
				"range": 330,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "move_self",
						"mode": "blink",
						"distance": 30,
						"behindTarget": true
					},
					{
						"type": "damage",
						"school": "true",
						"base": 80,
						"ad": 0.45,
						"ap": 0
					},
					{
						"type": "consume_status",
						"status": "bladeTrace",
						"originOwned": true
					}
				],
				"condition": {
					"targetStatus": "bladeTrace",
					"owned": true
				},
				"ai": {
					"intent": "execute",
					"weight": 1.35,
					"cluster": 0,
					"survival": 0,
					"combo": 1
				},
				"tags": [
					"MOBILITY",
					"BURST"
				],
				"action": "",
				"vfx": {
					"color": "#d5f4ff",
					"pattern": "blinkCut",
					"glyph": "斷"
				},
				"geometry": "",
				"timing": "17.5 / 0.1"
			}
		]
	}, 
	{
		"id": "archer", 
		"name": "궁수", 
		"glyph": "弓", 
		"accent": "#6fd0a3", 
		"role": "DAMAGE", 
		"tags": ["RANGED", "SUSTAINED_DAMAGE", "DISENGAGE", "MOBILITY", "EXECUTE"], 
		"summary": "스킬을 쓸수록 빨라지며, 거리를 유지하다 약해진 적을 처형하는 기동형 원거리 딜러.", 
		"stats": {
			"maxHealth": 870, 
			"attackDamage": 70, 
			"abilityPower": 22, 
			"armor": 20, 
			"magicResistance": 20, 
			"moveSpeed": 120, 
			"attackSpeed": 0.62, 
			"attackRange": 220, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 15
		}, 
		"preferredRange": 200, 
		"behavior": {
			"aggression": 0.72, 
			"survival": 0.79, 
			"focusLowHealth": 0.9, 
			"focusHighThreat": 0.5, 
			"protectAllies": 0.2, 
			"preferBackline": 0.96, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.2, 
			"flank": 0.42, 
			"minimumCommitTime": 0.4, 
			"switchThreshold": 0.09, 
			"label": "거리 유지형"
		}, 
		"doctrine": {
			"title": "질풍 사거리 순환", 
			"code": "KITE LATTICE", 
			"roles": ["RANGED_CARRY", "FINISHER", "KITE_ANCHOR"], 
			"identity": "공격속도와 이동속도를 순환 자원으로 쓰는 장거리 카이터."
		}, 
		"nexus": {
			"title": "반사각 거리 지배", 
			"role": "CARRY", 
			"risk": 0.39, 
			"teamwork": 0.74, 
			"gamble": 0.25, 
			"information": 0.7, 
			"combo": [4, 2, 1, 3], 
			"skills": ["후퇴 후 안전거리와 보호막을 함께 평가", "벽 반사 재적중 경로 활용", "관측 체력 18% 처형 경계만 사용", "공격 전 가속해 지속 화력 확보"], 
			"identity": "벽과 탄도 반사로 공격선을 늘리고 후퇴 자원을 보존한다."
		}, 
		"passives": [
			{
				"name": "바람의 장전", 
				"description": "스킬 시전을 마칠 때마다 2.5초 동안 공격 속도 +18%, 이동 속도 +14%를 얻습니다(중첩 없이 갱신). 대상이 사라지는 등 발동에 실패한 시전은 제외됩니다.", 
				"rules": [
					{
						"type": "on_cast_buff", 
						"buffs": [
							{"stat": "attackSpeed", "amount": 0.18, "duration": 2.5}, 
							{"stat": "moveSpeed", "amount": 0.14, "duration": 2.5}
						]
					}
				]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "후퇴 사격", 
				"description": "화살 3발을 부채꼴(총 25°)로 쏘아 화살당 34+0.4AD 물리 피해를 줍니다. 같은 적이 여러 발 맞으면 둘째 발부터 35%입니다. 쏘는 즉시 조준 반대쪽으로 100 물러나고 64+0.2AP 보호막을 2.8초 얻습니다(명중과 무관).", 
				"cooldown": 14, 
				"castTime": 0.18, 
				"recovery": 0.18, 
				"range": 230, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 3, 
				"spread": 0.218166, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 34, "ad": 0.4, "ap": 0}, 
					{"type": "move_self", "mode": "recoil", "distance": 100}, 
					{"type": "shield", "base": 64, "ap": 0.2, "duration": 2.8, "selfOnly": true}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.22, "cluster": 0, "survival": 1, "combo": 0}, 
				"tags": ["MOBILITY", "SHIELDING", "DISENGAGE"], 
				"action": "", 
				"vfx": {"color": "#6fd0a3", "pattern": "fanArrow", "glyph": "退"}, 
				"geometry": "3발, 총 25°", 
				"timing": "14 / 0.18", 
				"flags": {"originVolleyFalloff": 0.35}
			}, 
			{
				"slot": 2, 
				"name": "반향 관통화살", 
				"description": "모든 적을 관통하는 화살로 66+0.7AD 물리 피해를 줍니다. 벽에서 최대 2번 튕기며(총 비행 거리 950), 튕긴 뒤에는 이미 맞은 적도 다시 맞힐 수 있지만 재적중 피해는 60%입니다.", 
				"cooldown": 11, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 400, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 18, 
				"angle": 0.9, 
				"speed": 500, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 999, 
				"bounces": 2, 
				"homing": false, 
				"returnToSource": false, 
				"maxDistance": 950, 
				"effects": [{"type": "damage", "school": "physical", "base": 66, "ad": 0.7, "ap": 0}], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.05, "cluster": 0.45, "survival": 0, "combo": 0}, 
				"tags": ["RANGED", "AREA_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#91e5bd", "pattern": "ricochet", "glyph": "反"}, 
				"geometry": "비행 거리 950, 폭 18, 속도 500", 
				"timing": "11 / 0.25", 
				"flags": {"originBounceRehit": true}
			}, 
			{
				"slot": 3, 
				"name": "끝맺는 화살", 
				"description": "적중 순간 대상의 체력이 최대 체력의 18% 이하면 보호막과 관계없이 즉시 처형합니다. 그보다 높으면 68+0.6AD 물리 피해만 주며, 이 피해로 18% 이하가 되어도 처형하지 않습니다. 무적 대상은 처형할 수 없습니다.", 
				"cooldown": 16, 
				"castTime": 0.35, 
				"recovery": 0.18, 
				"range": 340, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 580, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "execute", "threshold": 0.18}, 
					{"type": "damage", "school": "physical", "base": 68, "ad": 0.6, "ap": 0}
				], 
				"condition": null, 
				"ai": {"intent": "execute", "weight": 1.4, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["EXECUTE", "BURST"], 
				"action": "", 
				"vfx": {"color": "#dcffd9", "pattern": "finisher", "glyph": "終"}, 
				"geometry": "속도 580", 
				"timing": "16 / 0.35", 
				"flags": {"originPreExecute": 0.18}
			}, 
			{
				"slot": 4, 
				"name": "질풍 장전", 
				"description": "4.5초 동안 이동 속도 +30%, 공격 속도 +30%×(현재 이동 속도÷기본 이동 속도)(최대 +65%)를 얻습니다. 빨라질수록 공격 속도가 오르고, 둔화되면 함께 줄어듭니다.", 
				"cooldown": 20, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "buff", "stat": "moveSpeed", "amount": 0.3, "duration": 4.5}, 
					{
						"type": "buff", 
						"stat": "attackSpeedByMove", 
						"amount": 0.3, 
						"duration": 4.5, 
						"originByMove": true, 
						"cap": 0.65
					}
				], 
				"condition": null, 
				"ai": {"intent": "buff", "weight": 1.04, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["MOBILITY", "SUSTAINED_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#b5ffd7", "pattern": "windAura", "glyph": "風"}, 
				"geometry": "지속 4.5초", 
				"timing": "20 / 0.1"
			}
		]
	}, 
	{
		"id": "mage", 
		"name": "마법사", 
		"glyph": "術", 
		"accent": "#9a8cff", 
		"role": "CONTROL", 
		"tags": ["RANGED", "CONTROL", "AREA_DAMAGE", "DAMAGE_OVER_TIME", "MOBILITY"], 
		"summary": "속박과 둔화 장판으로 전장을 자르고, CC 적중으로 주문 순환을 가속하는 제어 마법사.", 
		"stats": {
			"maxHealth": 1000, 
			"attackDamage": 42, 
			"abilityPower": 90, 
			"armor": 18, 
			"magicResistance": 22, 
			"moveSpeed": 84, 
			"attackSpeed": 0.65, 
			"attackRange": 220, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 16
		}, 
		"preferredRange": 200, 
		"behavior": {
			"aggression": 0.52, 
			"survival": 0.67, 
			"focusLowHealth": 0.46, 
			"focusHighThreat": 0.72, 
			"protectAllies": 0.2, 
			"preferBackline": 0.93, 
			"preferCluster": 0.94, 
			"riskTolerance": 0.21, 
			"flank": 0.2, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "영역 통제형"
		}, 
		"doctrine": {
			"title": "빙결 화염 구역 통제", 
			"code": "FROSTFIRE GRID", 
			"roles": ["CONTROLLER", "ZONE_ANCHOR", "COMBO_OPENER"], 
			"identity": "속박과 화염 장판으로 현재 위치와 탈출 경로를 함께 봉쇄한다."
		}, 
		"nexus": {
			"title": "제어 환류 봉쇄", 
			"role": "CONTROL", 
			"risk": 0.34, 
			"teamwork": 0.91, 
			"gamble": 0.27, 
			"information": 0.82, 
			"combo": [1, 2, 3, 4], 
			"skills": ["다음 광역기까지 제어가 겹치지 않게 예약", "낙하 시점의 예상 밀집도 사용", "관측 내구도 높은 적에 연소", "안전지점 점멸을 탈출 자원으로 보존"], 
			"identity": "새 제어 적중과 아군 후속 공격을 묶어 통로를 봉쇄한다."
		}, 
		"passives": [
			{
				"name": "주문 환류", 
				"description": "적에게 군중 제어(속박·둔화 등)를 새로 걸거나 늘릴 때마다 모든 스킬의 남은 재사용 대기시간이 0.45초 줄어듭니다. 같은 시전·대상·종류는 1회(장판은 대상당 1회), 1초에 최대 1.35초까지입니다.", 
				"rules": [{"type": "on_cc_cdr", "seconds": 0.45, "originWindow": 1, "originCap": 1.35}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "빙결 직선", 
				"description": "직선 얼음탄이 최대 2명을 관통해 52+0.65AP 마법 피해와 속박 1.2초를 줍니다. 속박된 적은 걸어서 움직일 수 없지만 평타와 스킬은 쓸 수 있습니다.", 
				"cooldown": 8, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 290, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 28, 
				"angle": 0.9, 
				"speed": 390, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 1, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "magic", "base": 52, "ad": 0, "ap": 0.65}, 
					{"type": "status", "status": "root", "duration": 1.2, "magnitude": 0}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.2, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["CONTROL"], 
				"action": "", 
				"vfx": {"color": "#70cfff", "pattern": "iceLine", "glyph": "氷"}, 
				"geometry": "폭 28, 속도 390", 
				"timing": "8 / 0.25"
			}, 
			{
				"slot": 2, 
				"name": "낙화 화염진", 
				"description": "지정 위치(반경 82)에 0.65초 뒤 운석이 떨어져 58+0.6AP 마법 피해를 줍니다. 이후 4초간 불타는 장판이 남아 안의 적을 30% 둔화시킵니다(벗어나도 0.4초 유지). 장판 자체는 피해가 없습니다.", 
				"cooldown": 11, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 290, 
				"target": "position", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 82, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "delayed_area", 
						"delay": 0.65, 
						"radius": 82, 
						"effects": [
							{"type": "damage", "school": "magic", "base": 58, "ad": 0, "ap": 0.6}, 
							{
								"type": "zone", 
								"radius": 82, 
								"duration": 4, 
								"interval": 0.25, 
								"effects": [{"type": "status", "status": "slow", "duration": 0.4, "magnitude": 0.3}], 
								"filter": "enemy", 
								"originCdrOnce": true
							}
						]
					}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.2, "cluster": 1, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "DAMAGE_OVER_TIME", "CONTROL"], 
				"action": "meteor", 
				"vfx": {"color": "#ff8d63", "pattern": "meteorZone", "glyph": "火"}, 
				"geometry": "반경 82", 
				"timing": "11 / 0.25"
			}, 
			{
				"slot": 3, 
				"name": "연소 표식", 
				"description": "유도 화염탄이 적중하면 4초간 1초마다 10+0.12AP+대상 최대 체력 1.5% 마법 피해를 줍니다(총 4회). 다시 맞히면 중첩 없이 갱신됩니다. 벽·차원 균열·배트 반사에 막히면 연소도 없습니다.", 
				"cooldown": 12, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 260, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 520, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": true, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "dot", 
						"duration": 4, 
						"interval": 1, 
						"damageEffect": {"type": "damage", "school": "magic", "base": 10, "ad": 0, "ap": 0.12, "targetMaxHp": 0.015}, 
						"originRefresh": true
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.05, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["DAMAGE_OVER_TIME", "SINGLE_TARGET"], 
				"action": "", 
				"vfx": {"color": "#ffb064", "pattern": "burnMark", "glyph": "燃"}, 
				"geometry": "유도 탄속 520", 
				"timing": "12 / 0.22"
			}, 
			{
				"slot": 4, 
				"name": "공간 도약", 
				"description": "원하는 위치(최대 160)로 순간이동하고 3초간 80+0.45AP 보호막을 얻습니다. 속박 중에도 쓸 수 있습니다.", 
				"cooldown": 24, 
				"castTime": 0.08, 
				"recovery": 0.18, 
				"range": 160, 
				"target": "position", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "move_self", "mode": "blink", "distance": 160, "towardTargetPosition": true}, 
					{"type": "shield", "base": 80, "ap": 0.45, "duration": 3, "selfOnly": true}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.35, "cluster": 0, "survival": 1, "combo": 0}, 
				"tags": ["MOBILITY", "SHIELDING", "DISENGAGE"], 
				"action": "pointBlink", 
				"vfx": {"color": "#c7b7ff", "pattern": "arcaneBlink", "glyph": "空"}, 
				"geometry": "", 
				"timing": "24 / 0.08"
			}
		]
	}, 
	{
		"id": "sniper", 
		"name": "저격수", 
		"glyph": "準", 
		"accent": "#efc867", 
		"role": "DAMAGE", 
		"tags": ["RANGED", "BURST", "SINGLE_TARGET", "DISENGAGE", "CONTROL"], 
		"summary": "거리가 멀수록 강해진다. 필중 사격과 취약 낙인으로 한 대상을 제거하는 초장거리 딜러.", 
		"stats": {
			"maxHealth": 780, 
			"attackDamage": 78, 
			"abilityPower": 15, 
			"armor": 16, 
			"magicResistance": 18, 
			"moveSpeed": 94, 
			"attackSpeed": 0.52, 
			"attackRange": 310, 
			"critChance": 0.14, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 14
		}, 
		"preferredRange": 290, 
		"behavior": {
			"aggression": 0.64, 
			"survival": 0.86, 
			"focusLowHealth": 0.74, 
			"focusHighThreat": 0.84, 
			"protectAllies": 0.2, 
			"preferBackline": 1, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.12, 
			"flank": 0.25, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "초장거리 제거형"
		}, 
		"doctrine": {
			"title": "초장거리 표적 제거", 
			"code": "GHOST FIRING LINE", 
			"roles": ["PRIMARY_CARRY", "MARKSMAN", "BACKLINE_ANCHOR"], 
			"identity": "거리 배율과 취약 표식을 팀 화력에 결합하는 저격수."
		}, 
		"nexus": {
			"title": "증거 기반 사선 저격", 
			"role": "CARRY", 
			"risk": 0.22, 
			"teamwork": 0.78, 
			"gamble": 0.31, 
			"information": 0.96, 
			"combo": [3, 1, 4, 2], 
			"skills": ["긴 선딜의 탄착 확률과 사선 위험 비교", "생존 위기에서 무적 창 사용", "팀 집중표적에게 취약 낙인 선행", "근접 위협을 밀어내 사선 복원"], 
			"identity": "보이지 않는 적을 확정 조준하지 않고 노출된 집중표적을 멀리서 마무리한다."
		}, 
		"passives": [
			{
				"name": "거리 보정", 
				"description": "대상과의 거리(몸 가장자리 기준)가 멀수록 모든 피해가 커져 거리 330 이상에서 최대 +26%입니다. 투사체 피해는 발사 순간의 거리로 고정됩니다.", 
				"rules": [{"type": "distance_damage", "maxBonus": 0.26, "fullDistance": 330}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "필중 사격", 
				"description": "0.8초 조준한 뒤 유도 탄환을 쏘아 64+0.75AD 물리 피해를 줍니다. 조준 중 기절·침묵 등에 걸리면 취소되며, 벽이나 앞을 가로막은 적·차원 균열에 막힐 수 있습니다.", 
				"cooldown": 12, 
				"castTime": 0.8, 
				"recovery": 0.18, 
				"range": 390, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 12, 
				"angle": 0.9, 
				"speed": 700, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": true, 
				"returnToSource": false, 
				"effects": [{"type": "damage", "school": "physical", "base": 64, "ad": 0.75, "ap": 0}], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.1, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["SINGLE_TARGET"], 
				"action": "", 
				"vfx": {"color": "#f5d478", "pattern": "hitscan", "glyph": "必中"}, 
				"geometry": "유도 탄속 700", 
				"timing": "12 / 0.8"
			}, 
			{
				"slot": 2, 
				"name": "유령 매복", 
				"description": "2.4초 동안 투명과 이동 속도 +35%를 얻고 처음 0.65초는 무적입니다. 평타나 적 대상 스킬을 쓰면 투명만 풀리고 이동 속도는 유지됩니다. 투명 중에도 적과 62 이내로 붙거나 피격 직후에는 드러납니다.", 
				"cooldown": 23, 
				"castTime": 0.08, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "status", "status": "invisible", "duration": 2.4, "magnitude": 0}, 
					{"type": "status", "status": "invulnerable", "duration": 0.65, "magnitude": 0}, 
					{"type": "buff", "stat": "moveSpeed", "amount": 0.35, "duration": 2.4}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.35, "cluster": 0, "survival": 1, "combo": 0}, 
				"tags": ["MOBILITY", "DISENGAGE"], 
				"action": "", 
				"vfx": {"color": "#fff0ad", "pattern": "cloak", "glyph": "匿"}, 
				"geometry": "", 
				"timing": "23 / 0.08"
			}, 
			{
				"slot": 3, 
				"name": "취약 탄환", 
				"description": "5초 안에 쏘는 다음 평타를 강화합니다. 적중하면 대상에 4초 취약 낙인을 남겨 받는 모든 피해가 16% 늘어납니다(낙인을 건 평타 자체는 제외). 빗나가면 강화만 사라집니다.", 
				"cooldown": 10, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "buff", 
						"stat": "originSniperRound", 
						"amount": 1, 
						"duration": 5, 
						"originPayload": [
							{
								"type": "mark", 
								"status": "sniperVulnerable", 
								"duration": 4, 
								"stacks": 1, 
								"maxStacks": 1, 
								"damageAmp": 0.16, 
								"originOwned": true
							}
						]
					}
				], 
				"condition": null, 
				"ai": {"intent": "debuff", "weight": 1.08, "cluster": 0, "survival": 0, "combo": 0.8}, 
				"tags": ["SINGLE_TARGET"], 
				"action": "prime", 
				"vfx": {"color": "#edb94f", "pattern": "markShot", "glyph": "印"}, 
				"geometry": "다음 평타", 
				"timing": "10 / 0.1"
			}, 
			{
				"slot": 4, 
				"name": "긴급 제압탄", 
				"description": "쏘는 즉시 140 뒤로 물러나고, 탄환이 처음 맞힌 적에게 54+0.5AD 물리 피해와 기절 1초를 줍니다.", 
				"cooldown": 21, 
				"castTime": 0.18, 
				"recovery": 0.18, 
				"range": 240, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 28, 
				"angle": 0.9, 
				"speed": 440, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 54, "ad": 0.5, "ap": 0}, 
					{"type": "status", "status": "stun", "duration": 1, "magnitude": 0}, 
					{"type": "move_self", "mode": "recoil", "distance": 140}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.3, "cluster": 0, "survival": 0.95, "combo": 0}, 
				"tags": ["CONTROL", "DISENGAGE", "MOBILITY"], 
				"action": "", 
				"vfx": {"color": "#ffe198", "pattern": "recoilShot", "glyph": "退"}, 
				"geometry": "폭 28, 속도 440", 
				"timing": "21 / 0.18"
			}
		]
	}, 
	{
		"id": "werewolf", 
		"name": "웨어 울프", 
		"glyph": "狼", 
		"accent": "#d16d78", 
		"role": "DAMAGE", 
		"tags": ["MELEE", "SUSTAINED_DAMAGE", "ENGAGE", "MOBILITY", "CONTROL"], 
		"summary": "피 냄새를 따라 약한 적을 추격하고, 피해 기반 회복과 제압으로 전투를 길게 끌수록 강해진다.", 
		"stats": {
			"maxHealth": 1060, 
			"attackDamage": 80, 
			"abilityPower": 20, 
			"armor": 34, 
			"magicResistance": 30, 
			"moveSpeed": 124, 
			"attackSpeed": 1, 
			"attackRange": 43, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 18
		}, 
		"preferredRange": 42, 
		"behavior": {
			"aggression": 0.88, 
			"survival": 0.43, 
			"focusLowHealth": 1, 
			"focusHighThreat": 0.22, 
			"protectAllies": 0.2, 
			"preferBackline": 0.72, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.78, 
			"flank": 0.62, 
			"minimumCommitTime": 0.48, 
			"switchThreshold": 0.12, 
			"label": "저체력 사냥형"
		}, 
		"doctrine": {
			"title": "혈향 추격 포식", 
			"code": "BLOOD SCENT", 
			"roles": ["HUNTER", "DIVER", "EXECUTION_CHASER"], 
			"identity": "저체력 표적을 추격하고 높은 체력 적에게서 흡혈 효율을 뽑는 포식자."
		}, 
		"nexus": {
			"title": "체력차 포식 추격", 
			"role": "DIVER", 
			"risk": 0.83, 
			"teamwork": 0.53, 
			"gamble": 0.62, 
			"information": 0.45, 
			"combo": [1, 2, 4, 3], 
			"skills": ["관측 저체력의 실제 추격 방향 요구", "자신보다 HP가 높은 적에 강화", "적 후속 시전을 끊을 때 포효", "동료 후속 사거리 안에서 제압 진입"], 
			"identity": "체력차 흡혈과 제압 시간을 겹쳐 위험을 회복으로 상쇄한다."
		}, 
		"passives": [
			{
				"name": "포식 회복", 
				"description": "평타와 스킬로 체력에 입힌 피해의 16%만큼 흡혈합니다(치유 감소 적용). 보호막에 막힌 피해는 제외됩니다.", 
				"rules": [{"type": "damage_heal", "ratio": 0.16}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "피냄새 추적", 
				"description": "4초 동안, 볼 수 있는 체력 40% 이하 적 영웅 쪽(±60°)으로 움직이면 이동 속도 +35%, 방어력·마법 저항력 +25%를 얻습니다. 다른 방향이나 후퇴 중에는 효과가 없고, 대상을 놓쳐도 1초간은 마지막 위치 기준으로 유지됩니다.", 
				"cooldown": 9, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "buff", "stat": "originScent", "amount": 1, "duration": 4}], 
				"condition": null, 
				"ai": {"intent": "engage", "weight": 1, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["MOBILITY", "ENGAGE"], 
				"action": "", 
				"vfx": {"color": "#e87984", "pattern": "scent", "glyph": "嗅"}, 
				"geometry": "지속 4초", 
				"timing": "9 / 0.1"
			}, 
			{
				"slot": 2, 
				"name": "상위 포식자", 
				"description": "5초 동안 나보다 현재 체력이 많은 적에게는 평타 피해가 최대 40%, 흡혈 비율이 최대 12%p 늘어납니다(체력 차이÷내 최대 체력에 비례). 체력이 나 이하인 적에게는 보너스가 없습니다.", 
				"cooldown": 12, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "buff", "stat": "originPredator", "amount": 1, "duration": 5}], 
				"condition": null, 
				"ai": {"intent": "buff", "weight": 0.95, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["SUSTAINED_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#ff9b95", "pattern": "predatorAura", "glyph": "獵"}, 
				"geometry": "지속 5초", 
				"timing": "12 / 0.1"
			}, 
			{
				"slot": 3, 
				"name": "달의 포효", 
				"description": "주변 반경 100의 적을 1.3초 침묵시킵니다(스킬 사용 불가, 준비 중인 스킬 취소). 피해는 없습니다.", 
				"cooldown": 10, 
				"castTime": 0.2, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 100, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "status", "status": "silence", "duration": 1.3, "magnitude": 0}], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.12, "cluster": 0.8, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "CONTROL"], 
				"action": "", 
				"vfx": {"color": "#c66fdf", "pattern": "howl", "glyph": "吼"}, 
				"geometry": "반경 100", 
				"timing": "10 / 0.2"
			}, 
			{
				"slot": 4, 
				"name": "불굴의 물어뜯기", 
				"description": "대상 방향으로 200 돌진하며 돌진 중에는 군중 제어·넉백에 면역입니다. 처음 닿은 적에게 80+0.8AD 물리 피해와 제압 1.3초(강인함 무시)를 줍니다. 벽에 막히거나 아무도 닿지 않으면 효과가 없습니다.", 
				"cooldown": 14, 
				"castTime": 0.16, 
				"recovery": 0.18, 
				"range": 200, 
				"target": "enemy", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 36, 
				"angle": 0.9, 
				"speed": 600, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "move_self", "mode": "dash", "distance": 200, "towardTarget": true, "speed": 600}, 
					{"type": "damage", "school": "physical", "base": 80, "ad": 0.8, "ap": 0}, 
					{"type": "status", "status": "suppression", "duration": 1.3, "magnitude": 0}
				], 
				"condition": null, 
				"ai": {"intent": "engage", "weight": 1.35, "cluster": 0, "survival": 0, "combo": 0.6}, 
				"tags": ["MOBILITY", "ENGAGE", "CONTROL"], 
				"action": "contactDash", 
				"vfx": {"color": "#ff706d", "pattern": "biteDash", "glyph": "噬"}, 
				"geometry": "돌진 200, 폭 36, 속도 600", 
				"timing": "14 / 0.16", 
				"flags": {"originDistance": 200, "originUnstoppable": true}
			}
		]
	}, 
	{
		"id": "giant", 
		"name": "거인", 
		"glyph": "巨", 
		"accent": "#c89163", 
		"role": "FRONTLINE", 
		"tags": ["MELEE", "AREA_DAMAGE", "CONTROL", "SUSTAINED_DAMAGE", "PEEL"], 
		"summary": "현재 체력에 따라 몸집과 방어력이 달라지며, 넓은 공중 제어와 체력 비례 피해로 전선을 만든다.", 
		"stats": {
			"maxHealth": 1290, 
			"attackDamage": 58, 
			"abilityPower": 25, 
			"armor": 42, 
			"magicResistance": 38, 
			"moveSpeed": 76, 
			"attackSpeed": 0.5, 
			"attackRange": 68, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 24
		}, 
		"preferredRange": 58, 
		"behavior": {
			"aggression": 0.47, 
			"survival": 0.86, 
			"focusLowHealth": 0.33, 
			"focusHighThreat": 0.84, 
			"protectAllies": 0.76, 
			"preferBackline": 0.5, 
			"preferCluster": 0.96, 
			"riskTolerance": 0.4, 
			"flank": 0.2, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "전선 고정형"
		}, 
		"doctrine": {
			"title": "산맥 전선 고정", 
			"code": "MOUNTAIN LINE", 
			"roles": ["MAIN_TANK", "PRIMARY_ENGAGE", "FRONT_GUARD"], 
			"identity": "현재 체력과 몸집을 전선 폭으로 바꾸는 체력 기반 탱커."
		}, 
		"nexus": {
			"title": "재생 전선 고정", 
			"role": "ANCHOR", 
			"risk": 0.55, 
			"teamwork": 0.96, 
			"gamble": 0.22, 
			"information": 0.43, 
			"combo": [2, 1, 3], 
			"skills": ["진입군을 공중에 묶어 후열 보호", "피해 이력이 높을 때 재생 전환", "현재 몸집으로 투사체 범위 추정"], 
			"identity": "몸집과 재생을 전열 자원으로 써 아군에게 공격 시간을 제공한다."
		}, 
		"passives": [
			{"name": "거인의 재생", "description": "초당 체력 6을 재생합니다(치유 감소 적용).", "rules": [{"type": "regen", "perSecond": 6}]}, 
			{
				"name": "살아 있는 산맥", 
				"description": "현재 체력 비율에 따라 몸집이 85%~115%로 변하고 방어력·마법 저항력이 최대 +25%(체력이 가득할수록 큼)입니다. 나보다 체력이 적은 적에게 주는 피해는 최대 +12%(체력 차이÷내 최대 체력 비례)이며, 몸집이 클수록 S1·S3의 범위와 피해도 커집니다.", 
				"rules": [
					{
						"type": "health_size_scaling", 
						"armorBonus": 0.25, 
						"radiusBonus": 0.3, 
						"lowerHpDamage": 0.12, 
						"originRadiusBase": 0.85
					}
				]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "지각 강타", 
				"description": "주변 반경 118×몸집의 적에게 (44+0.25AD+내 최대 체력 3%)×몸집 물리 피해와 에어본 1초(강인함 무시)를 줍니다. 몸집은 발동 순간 값입니다.", 
				"cooldown": 12, 
				"castTime": 0.35, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 118, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "damage", 
						"school": "physical", 
						"base": 44, 
						"ad": 0.25, 
						"ap": 0, 
						"selfMaxHp": 0.03, 
						"scaleWithRadius": true
					}, 
					{"type": "status", "status": "airborne", "duration": 1, "magnitude": 0}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.35, "cluster": 1, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "CONTROL"], 
				"action": "", 
				"vfx": {"color": "#c89163", "pattern": "quake", "glyph": "震"}, 
				"geometry": "반경 118×몸집", 
				"timing": "12 / 0.35"
			}, 
			{
				"slot": 2, 
				"name": "폭식 재생", 
				"description": "5초 동안 초당 재생이 14 늘고, 최근 2초간 직접 입힌 체력 피해의 8%가 초당 재생에 더해집니다(추가분 초당 최대 24). 체력이 가득하면 재생하지 않습니다.", 
				"cooldown": 17.5, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "buff", "stat": "regen", "amount": 14, "duration": 5}, 
					{"type": "buff", "stat": "originRegenPool", "amount": 1, "duration": 5}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.15, "cluster": 0, "survival": 0.9, "combo": 0}, 
				"tags": ["SUSTAINED_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#dab086", "pattern": "stonePulse", "glyph": "生"}, 
				"geometry": "지속 5초", 
				"timing": "17.5 / 0.1"
			}, 
			{
				"slot": 3, 
				"name": "산맥 투척", 
				"description": "지정 위치로 바위를 던져 적·벽에 닿거나 도착하면 반경 75×몸집 폭발로 (62+0.3AD+내 최대 체력 5.5%)×몸집 물리 피해를 1회 줍니다. 몸집은 던지는 순간 값입니다.", 
				"cooldown": 11.5, 
				"castTime": 0.35, 
				"recovery": 0.18, 
				"range": 270, 
				"target": "position", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 75, 
				"width": 88, 
				"angle": 0.9, 
				"speed": 300, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "damage", 
						"school": "physical", 
						"base": 62, 
						"ad": 0.3, 
						"ap": 0, 
						"selfMaxHp": 0.055, 
						"scaleWithRadius": true
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1, "cluster": 0.9, "survival": 0, "combo": 0}, 
				"tags": ["RANGED", "AREA_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#a87d58", "pattern": "boulder", "glyph": "巖"}, 
				"geometry": "탄속 300, 탄 반경 12×몸집", 
				"timing": "11.5 / 0.35", 
				"flags": {"originScaledProjectile": true, "originProjectileRadius": 12}
			}
		]
	}, 
	{
		"id": "aphrodite",
		"name": "아프로디테",
		"glyph": "愛",
		"accent": "#ef83b1",
		"role": "SUPPORT",
		"tags": [
			"RANGED",
			"HEALING",
			"SHIELDING",
			"CONTROL",
			"PEEL",
			"MOBILITY"
		],
		"summary": "유혹과 강제 이동으로 흐름을 비틀고, 아군 둘이 함께 버틸수록 강해지는 조합 중심 지원가.",
		"stats": {
			"maxHealth": 1000,
			"attackDamage": 36,
			"abilityPower": 90,
			"armor": 18,
			"magicResistance": 24,
			"moveSpeed": 90,
			"attackSpeed": 0.6,
			"attackRange": 220,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 16
		},
		"preferredRange": 190,
		"behavior": {
			"aggression": 0.25,
			"survival": 0.72,
			"focusLowHealth": 0.42,
			"focusHighThreat": 0.68,
			"protectAllies": 0.96,
			"preferBackline": 0.9,
			"preferCluster": 0.7,
			"riskTolerance": 0.18,
			"flank": 0.2,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "구출 지휘형"
		},
		"doctrine": {
			"title": "구출·짝수 강화",
			"code": "GOLDEN PAIR",
			"roles": [
				"PRIMARY_SUPPORT",
				"RESCUE_CONTROLLER",
				"PROTECTOR"
			],
			"identity": "위험 아군을 구조하고 짝수 군집을 강화하는 팀 중심 지원가."
		},
		"nexus": {
			"title": "짝 보존 구조망",
			"role": "SUPPORT",
			"risk": 0.19,
			"teamwork": 1,
			"gamble": 0.18,
			"information": 0.76,
			"combo": [
				2,
				3,
				1,
				4
			],
			"skills": [
				"추격자를 순차 제어로 차단",
				"짝이 머무를 수 있는 거점에 침상",
				"낮은 HP 아군을 아군 사선으로 구조",
				"아군의 돌입 생존성과 집중표적을 확인"
			],
			"identity": "짧은 구조와 10초 체류의 가치 중 더 유효한 지원을 선택한다."
		},
		"passives": [
			{
				"name": "되돌아오는 애정",
				"description": "다른 아군에게 준 치유·보호막·버프 수치의 20%만큼 3초 보호막을 얻습니다. 이 보호막은 합계 최대 체력 20%까지 쌓입니다.",
				"rules": [
					{
						"type": "on_ally_buff_shield",
						"ratio": 0.2,
						"originShieldCap": 0.2
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "황홀의 심판",
				"description": "유도 하트탄이 적중한 적을 유혹 0.6초(제자리 정지, 평타·스킬 불가) 뒤 이어서 기절 0.8초에 빠뜨립니다. 이미 유혹된 적에게는 기절이 이어지지 않으며 피해는 없습니다.",
				"cooldown": 10.5,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 260,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 520,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": true,
				"returnToSource": false,
				"effects": [
					{
						"type": "status",
						"status": "charm",
						"duration": 0.6,
						"magnitude": 0,
						"originStationary": true,
						"originThenStun": 0.8
					}
				],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.25,
					"cluster": 0,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"CONTROL"
				],
				"action": "",
				"vfx": {
					"color": "#ff8fbe",
					"pattern": "heartBolt",
					"glyph": "♡"
				},
				"geometry": "유도 탄속 520",
				"timing": "10.5 / 0.25"
			},
			{
				"slot": 2,
				"name": "짝의 침상",
				"description": "침상(체력 300+0.8AP, 방어·마저 20, 파괴 가능)을 18초간 1개만 설치합니다. 반경 90의 아군 영웅은 초당 8+0.06AP 회복하며, 들어온 순서로 2명씩 10초 머물면 체력을 모두 회복하고 공격력 +20%(5초)를 얻습니다. 짝 없는 1명은 10초 뒤 공격력이 4초간 15% 줄어듭니다.",
				"cooldown": 24,
				"castTime": 0.35,
				"recovery": 0.18,
				"range": 220,
				"target": "position_ally",
				"delivery": "area",
				"shape": "single",
				"radius": 90,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "zone",
						"radius": 90,
						"duration": 18,
						"interval": 1,
						"effects": [
							{
								"type": "heal",
								"base": 8,
								"ap": 0.06
							}
						],
						"filter": "ally",
						"originBed": true,
						"hp": 300,
						"hpAp": 0.8,
						"armor": 20,
						"stayTime": 10
					}
				],
				"condition": null,
				"ai": {
					"intent": "support",
					"weight": 1.25,
					"cluster": 0.8,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"HEALING",
					"AREA_DAMAGE"
				],
				"action": "bed",
				"vfx": {
					"color": "#ffafd0",
					"pattern": "loveBed",
					"glyph": "床"
				},
				"geometry": "반경 90",
				"timing": "24 / 0.35"
			},
			{
				"slot": 3,
				"name": "황금 견인",
				"description": "다른 아군 영웅을 내 옆으로 빠르게 끌어옵니다(이동 중 최대 0.65초 무적). 도착하면 75+0.65AP 회복시키며, 벽에 막혀 멈춰도 회복합니다.",
				"cooldown": 13,
				"castTime": 0.12,
				"recovery": 0.18,
				"range": 300,
				"target": "ally",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "status",
						"status": "invulnerable",
						"duration": 0.65,
						"magnitude": 0
					},
					{
						"type": "displace",
						"mode": "pullToSource",
						"distance": 999
					},
					{
						"type": "heal",
						"base": 75,
						"ap": 0.65
					}
				],
				"condition": null,
				"ai": {
					"intent": "support",
					"weight": 1.4,
					"cluster": 0,
					"survival": 0.85,
					"combo": 0
				},
				"tags": [
					"HEALING",
					"PEEL",
					"MOBILITY"
				],
				"action": "rescuePull",
				"vfx": {
					"color": "#ffd27c",
					"pattern": "goldTether",
					"glyph": "牽"
				},
				"geometry": "",
				"timing": "13 / 0.12",
				"flags": {
					"originOtherAlly": true
				}
			},
			{
				"slot": 4,
				"name": "불화의 사과",
				"description": "아군 하나를 3초간 광란 상태로 만듭니다. 그 아군은 이동 속도 +90%를 얻고 자신이 볼 수 있는, 현재 체력이 가장 낮은 적 영웅에게 강제로 달려갑니다(평타·스킬은 자유). 보이는 적이 없으면 효과가 없습니다.",
				"cooldown": 18,
				"castTime": 0.2,
				"recovery": 0.18,
				"range": 260,
				"target": "ally",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "force_charge",
						"duration": 3,
						"speedBonus": 0.9
					}
				],
				"condition": null,
				"ai": {
					"intent": "engage_support",
					"weight": 1.15,
					"cluster": 0,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"MOBILITY",
					"ENGAGE"
				],
				"action": "apple",
				"vfx": {
					"color": "#f4ca5e",
					"pattern": "goldApple",
					"glyph": "果"
				},
				"geometry": "",
				"timing": "18 / 0.2"
			}
		]
	}, 
	{
		"id": "blood_mage", 
		"name": "혈법사", 
		"glyph": "血", 
		"accent": "#b94664", 
		"role": "DAMAGE", 
		"tags": ["RANGED", "DAMAGE_OVER_TIME", "HEALING", "SUMMONER", "AREA_DAMAGE"], 
		"summary": "자신의 체력을 주문 자원으로 바꾸고, 잃은 체력을 발판 삼아 전투 내내 주문력이 성장하는 위험형 마법사.", 
		"stats": {
			"maxHealth": 1000, 
			"attackDamage": 42, 
			"abilityPower": 84, 
			"armor": 20, 
			"magicResistance": 24, 
			"moveSpeed": 83, 
			"attackSpeed": 0.62, 
			"attackRange": 215, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 17
		}, 
		"preferredRange": 185, 
		"behavior": {
			"aggression": 0.58, 
			"survival": 0.55, 
			"focusLowHealth": 0.58, 
			"focusHighThreat": 0.5, 
			"protectAllies": 0.42, 
			"preferBackline": 0.86, 
			"preferCluster": 0.76, 
			"riskTolerance": 0.5, 
			"flank": 0.2, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "체력 투자형"
		}, 
		"doctrine": {
			"title": "혈량 투자·회수", 
			"code": "CRIMSON ECONOMY", 
			"roles": ["ZONE_DAMAGE", "ATTRITION_CARRY", "TEAM_BUFFER"], 
			"identity": "자신의 체력을 팀 화력과 영구 AP로 환전하되 파산을 피하는 혈법사."
		}, 
		"nexus": {
			"title": "결손 성장 자원전", 
			"role": "SUSTAIN", 
			"risk": 0.63, 
			"teamwork": 0.81, 
			"gamble": 0.51, 
			"information": 0.57, 
			"combo": [2, 4, 3, 1], 
			"skills": ["버프받을 아군 화력과 자신의 체력비용 비교", "교전 지속 구역에서 성장 횟수 확보", "손실 체력을 회수할 확률 우선", "소환 생존 시간과 사선 압박을 계산"], 
			"identity": "체력 비용·흡혈·AP 성장의 순환을 끊기지 않게 유지한다."
		}, 
		"passives": [
			{
				"name": "결손의 권능", 
				"description": "S2~S4가 적중할 때마다(장판 피해·뱀 공격 포함) 잃은 체력의 1%(최대 8)만큼 주문력을 전투가 끝날 때까지 얻습니다. 누적될수록 획득량이 줄어들며(÷(1+누적/120)), 0.65초에 한 번·한 시전당 최대 16까지 얻습니다. S1과 평타는 제외됩니다.", 
				"rules": [
					{
						"type": "lost_health_ap_on_skill_hit", 
						"ratio": 0.01, 
						"excludeSlot": 1, 
						"maxPerHit": 8, 
						"internalCooldown": 0.65, 
						"maxBattleBonus": null, 
						"originPerCastCap": 16, 
						"originDiminish": 120
					}
				]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "혈맥 증폭", 
				"description": "현재 체력 8%를 소모해 아군 하나(자신 포함)에게 5초간 주는 피해 +12%, 최대 체력 +10%를 줍니다. 늘어난 만큼 현재 체력도 오르고, 끝나면 최대치를 넘는 체력은 사라집니다.", 
				"cooldown": 12, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 240, 
				"target": "ally", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "self_damage", "ratio": 0.08}, 
					{"type": "buff", "stat": "damageDealt", "amount": 0.12, "duration": 5}, 
					{"type": "buff", "stat": "maxHealth", "amount": 0.1, "duration": 5}
				], 
				"condition": null, 
				"ai": {"intent": "support", "weight": 0.9, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["SUPPORT"], 
				"action": "bloodLink", 
				"vfx": {"color": "#cf5f75", "pattern": "bloodLink", "glyph": "脈"}, 
				"geometry": "", 
				"timing": "12 / 0.22"
			}, 
			{
				"slot": 2, 
				"name": "핏빛 범람", 
				"description": "현재 체력 7%를 소모해 지정 위치(반경 95)에 5초간 혈지대를 만듭니다. 0.5초마다 안의 적에게 9+0.1AP 마법 피해와 30% 둔화(0.7초)를 줍니다.", 
				"cooldown": 10, 
				"castTime": 0.3, 
				"recovery": 0.18, 
				"range": 270, 
				"target": "position", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 95, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "self_damage", "ratio": 0.07}, 
					{
						"type": "zone", 
						"radius": 95, 
						"duration": 5, 
						"interval": 0.5, 
						"effects": [
							{"type": "damage", "school": "magic", "base": 9, "ad": 0, "ap": 0.1}, 
							{"type": "status", "status": "slow", "duration": 0.7, "magnitude": 0.3}
						], 
						"filter": "enemy"
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.15, "cluster": 1, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "DAMAGE_OVER_TIME", "CONTROL"], 
				"action": "", 
				"vfx": {"color": "#9d314d", "pattern": "bloodPool", "glyph": "沼"}, 
				"geometry": "반경 95", 
				"timing": "10 / 0.3"
			}, 
			{
				"slot": 3, 
				"name": "흡혈 탄환", 
				"description": "현재 체력 5%를 소모해 탄환을 쏩니다. 적중하면 64+0.65AP 마법 피해를 주고 체력에 입힌 피해의 50%를 흡혈합니다. 빗나가도 소모한 체력은 돌아오지 않습니다.", 
				"cooldown": 7, 
				"castTime": 0.2, 
				"recovery": 0.18, 
				"range": 290, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 22, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "self_damage", "ratio": 0.05}, 
					{"type": "damage", "school": "magic", "base": 64, "ad": 0, "ap": 0.65, "sourceHealRatio": 0.5}
				], 
				"condition": null, 
				"ai": {"intent": "damage_heal", "weight": 1.12, "cluster": 0, "survival": 0.45, "combo": 0}, 
				"tags": ["HEALING"], 
				"action": "", 
				"vfx": {"color": "#e15c75", "pattern": "bloodBolt", "glyph": "吸"}, 
				"geometry": "폭 22, 속도 420", 
				"timing": "7 / 0.2"
			}, 
			{
				"slot": 4, 
				"name": "혈사 소환", 
				"description": "현재 체력 10%를 소모해 뱀 3마리를 9초간 소환합니다. 뱀(체력 95+0.45AP, 방어·마저 12, 이동 속도 125)은 가장 가까운 적을 쫓아 1.1초마다 14+0.15AP 마법 피해를 줍니다. 능력치는 소환 순간 고정되며 기절·속박 등에 걸리면 멈춥니다.", 
				"cooldown": 17, 
				"castTime": 0.35, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "self_damage", "ratio": 0.1}, 
					{
						"type": "summon", 
						"count": 3, 
						"duration": 9, 
						"attack": {"type": "damage", "school": "magic", "base": 14, "ad": 0, "ap": 0.15}, 
						"hp": 95, 
						"hpAp": 0.45, 
						"armor": 12, 
						"speed": 125, 
						"interval": 1.1, 
						"glyph": "蛇", 
						"originEntity": "snake"
					}
				], 
				"condition": null, 
				"ai": {"intent": "summon", "weight": 1.1, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["SUMMONER", "SUSTAINED_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#d64f6f", "pattern": "snakeSpawn", "glyph": "蛇"}, 
				"geometry": "자신 주변 3마리", 
				"timing": "17 / 0.35"
			}
		]
	}, 
	{
		"id": "fisherman",
		"name": "낚시꾼",
		"glyph": "釣",
		"accent": "#56b7c9",
		"role": "CONTROL",
		"tags": [
			"MELEE",
			"CONTROL",
			"SINGLE_TARGET",
			"BURST",
			"RANGED"
		],
		"summary": "낚시로 적을 고립시키고, 미끼와 사시미 연계로 끌려온 대상을 확실하게 마무리한다.",
		"stats": {
			"maxHealth": 1100,
			"attackDamage": 80,
			"abilityPower": 15,
			"armor": 32,
			"magicResistance": 28,
			"moveSpeed": 100,
			"attackSpeed": 0.72,
			"attackRange": 52,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 18
		},
		"preferredRange": 58,
		"behavior": {
			"aggression": 0.7,
			"survival": 0.57,
			"focusLowHealth": 0.68,
			"focusHighThreat": 0.68,
			"protectAllies": 0.45,
			"preferBackline": 0.5,
			"preferCluster": 0.25,
			"riskTolerance": 0.52,
			"flank": 0.2,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "고립 포획형"
		},
		"doctrine": {
			"title": "고립 낚시·사시미",
			"code": "HOOK AND FILLET",
			"roles": [
				"PICK_OPENER",
				"DISPLACEMENT_CONTROL",
				"MELEE_FINISHER"
			],
			"identity": "후열 하나를 낚아 팀 킬박스로 끌어오고 사시미로 확정 마감한다."
		},
		"nexus": {
			"title": "인양 살상구역",
			"role": "PICK",
			"risk": 0.58,
			"teamwork": 0.88,
			"gamble": 0.51,
			"information": 0.67,
			"combo": [
				2,
				1,
				4,
				3
			],
			"skills": [
				"아군 사거리로 실제 인양 가능할 때 발사",
				"좁은 퇴로에 미끼 설치",
				"먹기와 투척의 배타적 기회비용 비교",
				"자기 인양이 확인된 적만 결착"
			],
			"identity": "후퇴로를 미끼로 제한하고 아군의 집중사격 안으로 인양한다."
		},
		"passives": [
			{
				"name": "오늘의 어획",
				"description": "8초마다 공격·방어·체력 물고기 중 하나를 무작위로 얻습니다(최대 2마리, 넘치면 가장 오래된 것을 자동으로 먹음). '어획 섭취'로 먹으면 8초간 공격력 +12% / 방어력·마법 저항력 +16% / 최대 체력 +10% 중 해당 효과를 얻고, S3로 던질 수도 있습니다.",
				"rules": [
					{
						"type": "timed_random_buff",
						"interval": 8,
						"choices": [
							{
								"stat": "attackDamage",
								"amount": 0.12
							},
							{
								"stat": "armor",
								"amount": 0.16
							},
							{
								"stat": "maxHealth",
								"amount": 0.1
							}
						],
						"duration": 8,
						"resourceKey": "fish",
						"originInventory": 2
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "큰낚시",
				"description": "갈고리가 처음 맞힌 적에게 68+0.75AD 물리 피해를 주고 내 앞으로 끌어당깁니다. 벽에 걸리면 도중에 멈추고 저지 불가·무적 대상은 끌리지 않습니다. 내 곁까지 끌려온 적에게는 3초 인양 표식(S4 조건)이 남습니다.",
				"cooldown": 10.5,
				"castTime": 0.3,
				"recovery": 0.18,
				"range": 280,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 20,
				"angle": 0.9,
				"speed": 380,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "damage",
						"school": "physical",
						"base": 68,
						"ad": 0.75,
						"ap": 0
					},
					{
						"type": "displace",
						"mode": "pullToSource",
						"distance": 999,
						"originHook": true
					}
				],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.3,
					"cluster": 0,
					"survival": 0,
					"combo": 0.9
				},
				"tags": [
					"CONTROL",
					"RANGED"
				],
				"action": "",
				"vfx": {
					"color": "#67c8d8",
					"pattern": "hook",
					"glyph": "鉤"
				},
				"geometry": "폭 20, 속도 380",
				"timing": "10.5 / 0.3"
			},
			{
				"slot": 2,
				"name": "미끼 구덩이",
				"description": "지정 위치에 6초간 미끼(반경 90)를 놓습니다. 범위에 들어온 적은 최대 1.2초간 중심으로 걸어가고(유혹: 평타·스킬 불가), 중심(반경 18)에 닿으면 기절 0.8초에 빠집니다. 적마다 한 번만 걸리며 2명이 걸리면 사라집니다.",
				"cooldown": 12,
				"castTime": 0.28,
				"recovery": 0.18,
				"range": 240,
				"target": "position",
				"delivery": "area",
				"shape": "single",
				"radius": 90,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "zone",
						"radius": 90,
						"duration": 6,
						"interval": 0.1,
						"effects": [
							{
								"type": "status",
								"status": "charm",
								"duration": 1.2,
								"magnitude": 0
							},
							{
								"type": "status",
								"status": "stun",
								"duration": 0.8,
								"magnitude": 0
							}
						],
						"filter": "enemy",
						"originBait": true,
						"innerRadius": 18,
						"maxTriggers": 2
					}
				],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.2,
					"cluster": 0.8,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"CONTROL",
					"AREA_DAMAGE"
				],
				"action": "bait",
				"vfx": {
					"color": "#8fe1dd",
					"pattern": "baitTrap",
					"glyph": "餌"
				},
				"geometry": "유혹 반경 90, 중심 반경 18",
				"timing": "12 / 0.28"
			},
			{
				"slot": 3,
				"name": "어획 투척",
				"description": "가장 오래된 물고기 1마리를 던져 90+0.8AD 물리 피해를 줍니다. 물고기가 없으면 쓸 수 없고, 던진 물고기는 먹을 수 없습니다.",
				"cooldown": 6,
				"castTime": 0.18,
				"recovery": 0.18,
				"range": 270,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "consume_resource",
						"key": "fish",
						"amount": 1
					},
					{
						"type": "damage",
						"school": "physical",
						"base": 90,
						"ad": 0.8,
						"ap": 0
					}
				],
				"condition": {
					"selfResource": {
						"key": "fish",
						"min": 1
					}
				},
				"ai": {
					"intent": "damage",
					"weight": 0.95,
					"cluster": 0,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"RANGED"
				],
				"action": "",
				"vfx": {
					"color": "#a3e8dd",
					"pattern": "fishThrow",
					"glyph": "魚"
				},
				"geometry": "속도 420",
				"timing": "6 / 0.18"
			},
			{
				"slot": 4,
				"name": "사시미 결착",
				"description": "내가 남긴 인양 표식이 있는 근처 적에게 90+0.45AD 고정 피해를 주고 표식을 소비합니다. 다른 낚시꾼의 표식으로는 쓸 수 없습니다.",
				"cooldown": 15,
				"castTime": 0.15,
				"recovery": 0.18,
				"range": 85,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "damage",
						"school": "true",
						"base": 90,
						"ad": 0.45,
						"ap": 0
					},
					{
						"type": "consume_status",
						"status": "hooked",
						"originOwned": true
					}
				],
				"condition": {
					"targetStatus": "hooked",
					"owned": true
				},
				"ai": {
					"intent": "execute",
					"weight": 1.35,
					"cluster": 0,
					"survival": 0,
					"combo": 1
				},
				"tags": [
					"BURST",
					"SINGLE_TARGET"
				],
				"action": "",
				"vfx": {
					"color": "#d5fff4",
					"pattern": "sashimi",
					"glyph": "刺"
				},
				"geometry": "",
				"timing": "15 / 0.15"
			}
		]
	}, 
	{
		"id": "baseball", 
		"name": "야구맨", 
		"glyph": "球", 
		"accent": "#e36e4b", 
		"role": "FRONTLINE", 
		"tags": ["MELEE", "CONTROL", "PEEL", "RANGED", "AREA_DAMAGE"], 
		"summary": "배트의 넉백과 투사체 반사로 아군 앞을 지키며, 벽 충돌을 강한 후속 타격으로 바꾸는 수비형 전사.", 
		"stats": {
			"maxHealth": 1080, 
			"attackDamage": 74, 
			"abilityPower": 12, 
			"armor": 50, 
			"magicResistance": 40, 
			"moveSpeed": 84, 
			"attackSpeed": 0.76, 
			"attackRange": 58, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 19
		}, 
		"preferredRange": 62, 
		"behavior": {
			"aggression": 0.43, 
			"survival": 0.82, 
			"focusLowHealth": 0.5, 
			"focusHighThreat": 0.72, 
			"protectAllies": 0.68, 
			"preferBackline": 0.5, 
			"preferCluster": 0.75, 
			"riskTolerance": 0.4, 
			"flank": 0.2, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "투사체 차단형"
		}, 
		"doctrine": {
			"title": "배트 반사·충돌 제압", 
			"code": "DIAMOND DEFENSE", 
			"roles": ["PROJECTILE_PEEL", "FRONT_GUARD", "TEAM_BUFFER"], 
			"identity": "부채꼴 배트와 투사체 반사로 전선을 밀어내는 반응형 수비수."
		}, 
		"nexus": {
			"title": "반격 수비벽", 
			"role": "PEEL", 
			"risk": 0.45, 
			"teamwork": 0.97, 
			"gamble": 0.36, 
			"information": 0.71, 
			"combo": [2, 1, 3], 
			"skills": ["추격자를 둔화해 수비 스윙 거리 유지", "관측 투사체가 접근할 때 헬멧", "공격받는 아군이 함께 있을 때 방어 강화"], 
			"identity": "공격과 투사체 반사를 같은 스윙 창으로 묶어 후열을 지킨다."
		}, 
		"passives": [
			{
				"name": "수비 타석", 
				"description": "평타 대신 0.24초간 전방 부채꼴(반경 76, 80°)을 휘둘러 범위의 모든 적에게 1.0AD 물리 피해, 기절 0.3초, 넉백 50을 줍니다. 밀려난 적이 벽이나 다른 적에 부딪히면 5초 안의 다음 스윙 피해가 35% 커집니다. 다가오는 투사체를 향해 '수비 스윙'도 합니다(평타 간격 공유).", 
				"rules": [
					{
						"type": "cone_basic", 
						"angle": 1.396263, 
						"radius": 76, 
						"knockback": 50, 
						"stun": 0.3, 
						"collisionBonus": 0.35, 
						"bonusDuration": 5, 
						"originWindow": 0.24
					}
				]
			}, 
			{
				"name": "되받아치기", 
				"description": "스윙 중(0.24초) 배트 앞쪽에 닿은 적 투사체를 되받아칩니다. 나는 원래 피해의 70%만 받고, 원래 피해 70%의 유도탄을 쏜 적에게 돌려보냅니다. 뒤에서 온 탄은 막지 못합니다.", 
				"rules": [{"type": "projectile_reflect_arc", "reduction": 0.3, "reflect": 0.7}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "변화구", 
				"description": "유도 공이 적중하면 52+0.6AD 물리 피해와 30% 둔화(1.6초)를 줍니다.", 
				"cooldown": 5.5, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 250, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 480, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": true, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 52, "ad": 0.6, "ap": 0}, 
					{"type": "status", "status": "slow", "duration": 1.6, "magnitude": 0.3}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["RANGED", "CONTROL"], 
				"action": "", 
				"vfx": {"color": "#f1855f", "pattern": "curveBall", "glyph": "球"}, 
				"geometry": "유도 탄속 480", 
				"timing": "5.5 / 0.22"
			}, 
			{
				"slot": 2, 
				"name": "포수 헬멧", 
				"description": "4초간 투사체 방어 상태가 되어 받는 투사체 피해가 50% 줄어듭니다(원거리 평타·폭발탄 포함). 배트로 되받아칠 때 내가 받는 몫도 절반(원래 피해의 35%)이 되며, 돌려보내는 탄의 위력(70%)은 그대로입니다.", 
				"cooldown": 13, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "projectile_guard", "duration": 4, "reduction": 0.5, "reflect": 0}], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.1, "cluster": 0, "survival": 0.8, "combo": 0}, 
				"tags": ["PEEL"], 
				"action": "", 
				"vfx": {"color": "#ffab80", "pattern": "helmet", "glyph": "帽"}, 
				"geometry": "지속 4초", 
				"timing": "13 / 0.1"
			}, 
			{
				"slot": 3, 
				"name": "벤치 클리어링", 
				"description": "주변 반경 130의 아군 영웅(자신 포함)에게 5초간 방어력·마법 저항력 +25%를 줍니다. 다시 쓰면 중첩 없이 갱신됩니다.", 
				"cooldown": 14, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 130, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "buff", "stat": "armor", "amount": 0.25, "duration": 5, "applyTo": "ally_area"}, 
					{"type": "buff", "stat": "magicResistance", "amount": 0.25, "duration": 5, "applyTo": "ally_area"}
				], 
				"condition": null, 
				"ai": {"intent": "support", "weight": 1.15, "cluster": 0.8, "survival": 0, "combo": 0}, 
				"tags": ["SUPPORT", "AREA_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#ffc19b", "pattern": "teamShout", "glyph": "集"}, 
				"geometry": "반경 130", 
				"timing": "14 / 0.22"
			}
		]
	}, 
	{
		"id": "pirate", 
		"name": "해적", 
		"glyph": "☠", 
		"accent": "#d7a852", 
		"role": "DAMAGE", 
		"tags": ["MELEE", "RANGED", "BURST", "MOBILITY", "AREA_DAMAGE"], 
		"summary": "근거리 칼과 원거리 화기를 오가며 능력치를 약탈하고 반동까지 이동 수단으로 쓰는 혼합 공격수.", 
		"stats": {
			"maxHealth": 1000, 
			"attackDamage": 72, 
			"abilityPower": 18, 
			"armor": 22, 
			"magicResistance": 24, 
			"moveSpeed": 98, 
			"attackSpeed": 0.76, 
			"attackRange": 175, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 17
		}, 
		"preferredRange": 110, 
		"behavior": {
			"aggression": 0.69, 
			"survival": 0.48, 
			"focusLowHealth": 0.72, 
			"focusHighThreat": 0.54, 
			"protectAllies": 0.2, 
			"preferBackline": 0.62, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.52, 
			"flank": 0.58, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "중거리 약탈형"
		}, 
		"doctrine": {
			"title": "거리 전환 약탈", 
			"code": "CUTLASS BROADSIDE", 
			"roles": ["HYBRID_SKIRMISHER", "STAT_THIEF", "ANGLE_BREAKER"], 
			"identity": "근거리 고정 피해와 원거리 포격 사이 경계를 능동적으로 오가는 약탈자."
		}, 
		"nexus": {
			"title": "능력 약탈 측면전", 
			"role": "FLANK", 
			"risk": 0.68, 
			"teamwork": 0.62, 
			"gamble": 0.61, 
			"information": 0.62, 
			"combo": [3, 2, 1, 4], 
			"skills": ["이동 경로에 동전을 흩뿌려 퇴로 압박", "벽 갈고리를 측면 진입·이탈로 사용", "약탈 평타 후 화력기 사용", "후퇴 후 적을 폭발 부채꼴에 유지"], 
			"identity": "약탈로 순간 공격력을 확보한 뒤 사거리를 전환한다."
		}, 
		"passives": [
			{
				"name": "칼과 화약", 
				"description": "적이 62 이내면 칼로 1.0AD 물리 피해+12 고정 피해를 주고(투사체 방어 무시), 더 멀면 권총으로 1.12AD 물리 탄환을 쏩니다(사거리 175). 공격이 나가는 순간의 거리로 정해지며 고정 피해분에는 치명타가 적용되지 않습니다.", 
				"rules": [{"type": "hybrid_basic", "meleeRange": 62, "trueBonus": 12, "rangedAdBonus": 0.12}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "약탈금 투척", 
				"description": "돈자루를 던져 적·벽에 닿거나 도착하면 반경 70 폭발로 48+0.55AD 물리 피해를 줍니다. 주변에 동전 6개가 5초간 흩어지고, 적 영웅이 밟으면 3초간 0.75초마다 6+0.06AD 물리 피해를 받습니다(총 4회, 여러 개 밟아도 갱신).", 
				"cooldown": 10, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 280, 
				"target": "position", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 70, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 360, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 48, "ad": 0.55, "ap": 0}, 
					{
						"type": "zone", 
						"radius": 70, 
						"duration": 5, 
						"interval": 0.25, 
						"effects": [
							{
								"type": "dot", 
								"duration": 3, 
								"interval": 0.75, 
								"damageEffect": {"type": "damage", "school": "physical", "base": 6, "ad": 0.06, "ap": 0}, 
								"originRefresh": true
							}
						], 
						"filter": "enemy", 
						"originCoins": true, 
						"count": 6
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.05, "cluster": 0.8, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "DAMAGE_OVER_TIME"], 
				"action": "", 
				"vfx": {"color": "#e4bc65", "pattern": "coinBurst", "glyph": "金"}, 
				"geometry": "탄속 360, 폭발 반경 70", 
				"timing": "10 / 0.25", 
				"flags": {"originCoins": true}
			}, 
			{
				"slot": 2, 
				"name": "갈고리 항로", 
				"description": "갈고리가 처음 맞힌 적에게 44+0.45AD 물리 피해를 주고 그 적에게 날아갑니다(속도 580). 벽에 걸리면 벽으로 이동하고, 아무것도 맞히지 못하면 이동하지 않습니다.", 
				"cooldown": 9, 
				"castTime": 0.18, 
				"recovery": 0.18, 
				"range": 290, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 18, 
				"angle": 0.9, 
				"speed": 460, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 44, "ad": 0.45, "ap": 0}, 
					{"type": "move_self", "mode": "dashToImpact", "distance": 999, "speed": 580}
				], 
				"condition": null, 
				"ai": {"intent": "engage", "weight": 1.05, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["MOBILITY", "ENGAGE"], 
				"action": "", 
				"vfx": {"color": "#bf8b3f", "pattern": "grapple", "glyph": "鉤"}, 
				"geometry": "폭 18, 탄속 460", 
				"timing": "9 / 0.18"
			}, 
			{
				"slot": 3, 
				"name": "검은 깃발 약탈", 
				"description": "5초 안의 다음 평타가 적중하면 대상의 공격력·주문력 중 높은 쪽의 15%를 4초간 빼앗아 내 공격력에 더합니다(대상은 그만큼 감소). 약탈이 끝나기 전에는 같은 대상을 다시 약탈할 수 없습니다.", 
				"cooldown": 14, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "buff", 
						"stat": "originPirateRound", 
						"amount": 1, 
						"duration": 5, 
						"originPayload": [{"type": "steal_stat", "stat": "main", "ratio": 0.15, "duration": 4}]
					}
				], 
				"condition": null, 
				"ai": {"intent": "debuff", "weight": 1.12, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["SINGLE_TARGET"], 
				"action": "prime", 
				"vfx": {"color": "#f0c65c", "pattern": "steal", "glyph": "奪"}, 
				"geometry": "다음 평타 5초", 
				"timing": "14 / 0.1"
			}, 
			{
				"slot": 4, 
				"name": "함포 반동", 
				"description": "포탄을 쏘는 즉시 120 뒤로 물러납니다. 포탄이 적·벽에 닿거나 도착한 지점에서 진행 방향 부채꼴(반경 95, 80°)로 폭발해 74+0.7AD 물리 피해를 줍니다.", 
				"cooldown": 15, 
				"castTime": 0.32, 
				"recovery": 0.18, 
				"range": 260, 
				"target": "position", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 95, 
				"width": 24, 
				"angle": 1.396263, 
				"speed": 380, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 74, "ad": 0.7, "ap": 0}, 
					{"type": "move_self", "mode": "recoil", "distance": 120}
				], 
				"condition": null, 
				"ai": {"intent": "disengage_damage", "weight": 1.2, "cluster": 0.7, "survival": 0.45, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "MOBILITY", "DISENGAGE"], 
				"action": "", 
				"vfx": {"color": "#ff9f57", "pattern": "cannonCone", "glyph": "砲"}, 
				"geometry": "속도 380", 
				"timing": "15 / 0.32", 
				"flags": {"originConeImpact": true}
			}
		]
	}, 
	{
		"id": "joker", 
		"name": "조커", 
		"glyph": "J", 
		"accent": "#a978df", 
		"role": "CONTROL", 
		"tags": ["MELEE", "BURST", "CONTROL", "MOBILITY", "RANGED"], 
		"summary": "혼란 스택으로 적의 저항과 계수를 망가뜨린 뒤 위치 교환과 기절을 연쇄하는 변칙 제어자.", 
		"stats": {
			"maxHealth": 860, 
			"attackDamage": 72, 
			"abilityPower": 56, 
			"armor": 18, 
			"magicResistance": 20, 
			"moveSpeed": 118, 
			"attackSpeed": 0.88, 
			"attackRange": 52, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 15
		}, 
		"preferredRange": 68, 
		"behavior": {
			"aggression": 0.78, 
			"survival": 0.44, 
			"focusLowHealth": 0.65, 
			"focusHighThreat": 0.62, 
			"protectAllies": 0.2, 
			"preferBackline": 0.5, 
			"preferCluster": 0.54, 
			"riskTolerance": 0.58, 
			"flank": 0.88, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "변칙 교란형"
		}, 
		"doctrine": {
			"title": "혼란 스택·위치 교환", 
			"code": "CHAOS SWITCH", 
			"roles": ["DISRUPTOR", "STACK_BURSTER", "POSITION_SWAPPER"], 
			"identity": "혼란 스택과 위치 교환으로 상대 대형의 의미를 무너뜨리는 교란자."
		}, 
		"nexus": {
			"title": "혼란 신념 교란", 
			"role": "DISRUPT", 
			"risk": 0.8, 
			"teamwork": 0.73, 
			"gamble": 0.9, 
			"information": 0.89, 
			"combo": [1, 4, 2, 3], 
			"skills": ["서로 다른 칼 적중으로 혼란 축적", "교환 후 자신의 생존과 아군 사거리 평가", "최대 혼란에 근접할수록 소비 가치 상승", "껍질의 아군 제어 비용까지 반영"], 
			"identity": "단순 돌진 대신 위치교환과 혼란 소비로 상대의 대응 순서를 무너뜨린다."
		}, 
		"passives": [
			{
				"name": "혼란 누적", 
				"description": "피해를 줄 때마다 대상에게 혼란 1을 쌓습니다(최대 5, 7초, 쌓일 때 갱신). 스택당 받는 모든 피해 +3%, 강인함 −2.5%p이며 평타·상자 교환으로도 쌓입니다. 네 장의 칼·바나나 판결은 정해진 수만 쌓고, 여러 조커의 혼란은 가장 높은 값만 적용됩니다.", 
				"rules": [{"type": "confusion_on_damage", "maxStacks": 5, "damageAmpPerStack": 0.03, "tenacityLossPerStack": 0.025}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "네 장의 칼", 
				"description": "칼 4개를 부채꼴(총 32°)로 던집니다. 칼마다 처음 맞힌 적에게 22+0.26AD 물리 피해와 혼란 1(7초)을 줍니다. 가까운 적은 여러 개를 맞아 한 번에 최대 4스택까지 쌓입니다.", 
				"cooldown": 8.5, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 250, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 400, 
				"projectileCount": 4, 
				"spread": 0.186168, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 22, "ad": 0.26, "ap": 0}, 
					{
						"type": "mark", 
						"status": "confusion", 
						"duration": 7, 
						"stacks": 1, 
						"maxStacks": 5, 
						"damageAmp": 0.03, 
						"tenacityLoss": 0.025, 
						"originOwned": true
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.05, "cluster": 0.65, "survival": 0, "combo": 0}, 
				"tags": ["RANGED"], 
				"action": "", 
				"vfx": {"color": "#b88be9", "pattern": "knifeFan", "glyph": "♠"}, 
				"geometry": "4발, 총 32°, 탄속 400", 
				"timing": "8.5 / 0.22"
			}, 
			{
				"slot": 2, 
				"name": "장난감 상자 교환", 
				"description": "적과 위치를 맞바꿉니다(원래 자리의 상자는 연출). 대상에게 48+0.5AP 마법 피해와 속박 1.1초, 패시브로 혼란 1을 줍니다. 관조·저지 불가·무적 대상과는 위치가 바뀌지 않습니다.", 
				"cooldown": 13.5, 
				"castTime": 0.3, 
				"recovery": 0.18, 
				"range": 220, 
				"target": "enemy", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "swap"}, 
					{"type": "damage", "school": "magic", "base": 48, "ad": 0, "ap": 0.5}, 
					{"type": "status", "status": "root", "duration": 1.1, "magnitude": 0}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.25, "cluster": 0, "survival": 0, "combo": 0.55}, 
				"tags": ["MOBILITY", "CONTROL"], 
				"action": "swapBox", 
				"vfx": {"color": "#dd77cc", "pattern": "swapBox", "glyph": "箱"}, 
				"geometry": "", 
				"timing": "13.5 / 0.3"
			}, 
			{
				"slot": 3, 
				"name": "계수 뒤집기", 
				"description": "내 혼란이 있는 적에게만 씁니다. 혼란을 모두 소비해 50+0.35AP에 스택당 18을 더한 마법 피해를 주고, 4초간 대상의 최종 공격력과 주문력을 맞바꿉니다. 이 피해는 혼란을 쌓지 않으며 무적 대상은 바뀌지 않습니다.", 
				"cooldown": 15, 
				"castTime": 0.22, 
				"recovery": 0.18, 
				"range": 190, 
				"target": "enemy", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "damage", 
						"school": "magic", 
						"base": 50, 
						"ad": 0, 
						"ap": 0.35, 
						"perTargetStatusStack": {"status": "confusion", "amount": 18}
					}, 
					{"type": "swap_stats", "duration": 4}, 
					{"type": "consume_status", "status": "confusion", "originOwned": true}
				], 
				"condition": {"targetStatus": "confusion", "owned": true}, 
				"ai": {"intent": "burst", "weight": 1.35, "cluster": 0, "survival": 0, "combo": 1}, 
				"tags": ["BURST", "SINGLE_TARGET"], 
				"action": "consumeConfusion", 
				"vfx": {"color": "#8f68d6", "pattern": "statFlip", "glyph": "↕"}, 
				"geometry": "", 
				"timing": "15 / 0.22"
			}, 
			{
				"slot": 4, 
				"name": "바나나 판결", 
				"description": "유도 바나나가 적중하면 36+0.3AP 마법 피해, 기절 0.8초, 혼란 2를 주고 7초간 껍질(반경 30)을 남깁니다. 0.2초 뒤부터 처음 밟은 영웅 1명에게 발동해 적은 기절 0.65초와 혼란 1, 아군은 기절 0.3초와 46+0.25AP 회복을 받습니다.", 
				"cooldown": 16.5, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 270, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 380, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": true, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "magic", "base": 36, "ad": 0, "ap": 0.3}, 
					{"type": "status", "status": "stun", "duration": 0.8, "magnitude": 0}, 
					{
						"type": "mark", 
						"status": "confusion", 
						"duration": 7, 
						"stacks": 2, 
						"maxStacks": 5, 
						"damageAmp": 0.03, 
						"tenacityLoss": 0.025, 
						"originOwned": true
					}, 
					{
						"type": "zone", 
						"radius": 28, 
						"duration": 7, 
						"interval": 0.1, 
						"effects": [
							{"type": "status", "status": "stun", "duration": 0.65, "magnitude": 0}, 
							{"type": "heal", "base": 46, "ap": 0.25}
						], 
						"filter": "both", 
						"originBanana": true, 
						"trap": true, 
						"maxTriggers": 1
					}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.3, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["CONTROL", "HEALING"], 
				"action": "", 
				"vfx": {"color": "#f3db55", "pattern": "banana", "glyph": "蕉"}, 
				"geometry": "유도 탄속 380", 
				"timing": "16.5 / 0.25"
			}
		]
	}, 
	{
		"id": "metatron",
		"name": "메타트론",
		"glyph": "翼",
		"accent": "#e8d98d",
		"role": "SUPPORT",
		"tags": [
			"MELEE",
			"HEALING",
			"SHIELDING",
			"MOBILITY",
			"CONTROL",
			"DAMAGE_OVER_TIME"
		],
		"summary": "회전하는 두 날개가 적과 아군을 동시에 건드리며, 전장 사이를 날아다니는 공격형 수호자.",
		"stats": {
			"maxHealth": 1040,
			"attackDamage": 52,
			"abilityPower": 64,
			"armor": 38,
			"magicResistance": 36,
			"moveSpeed": 116,
			"attackSpeed": 0.76,
			"attackRange": 58,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 18
		},
		"preferredRange": 72,
		"behavior": {
			"aggression": 0.53,
			"survival": 0.66,
			"focusLowHealth": 0.5,
			"focusHighThreat": 0.67,
			"protectAllies": 0.86,
			"preferBackline": 0.5,
			"preferCluster": 0.86,
			"riskTolerance": 0.46,
			"flank": 0.2,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "순환 수호형"
		},
		"doctrine": {
			"title": "쌍익 순환 수호",
			"code": "SERAPH ORBIT",
			"roles": [
				"MOBILE_GUARDIAN",
				"ORBIT_SUPPORT",
				"PROTECTOR"
			],
			"identity": "쌍익 궤도에 적과 아군을 동시에 걸어 피해와 회복을 병행한다."
		},
		"nexus": {
			"title": "쌍익 교차 구조",
			"role": "SUPPORT",
			"risk": 0.4,
			"teamwork": 0.99,
			"gamble": 0.25,
			"information": 0.73,
			"combo": [
				1,
				3,
				4,
				2
			],
			"skills": [
				"날개 접촉이 예상될 때 회전 강화",
				"비행 중 궤도 치유 포기 비용 반영",
				"현재 HP 최소 아군의 구조를 우선",
				"착지 위치에서 제어 후 아군과 재합류"
			],
			"identity": "날개 궤적을 아군·적군 사이에 놓고 위기 아군에게 비행한다."
		},
		"passives": [
			{
				"name": "쌍익 궤도",
				"description": "반경 72에서 180° 떨어진 날개 2개가 2초에 한 바퀴 돕니다. 닿은 적은 10+0.11AP 마법 피해, 다친 아군은 8+0.08AP 회복을 받습니다(날개·대상마다 한 바퀴 1회, 최소 0.35초 간격). 벽 너머에는 닿지 않고 단익 부메랑이 날아가 있는 동안 멈춥니다.",
				"rules": [
					{
						"type": "orbit_aura",
						"interval": 2,
						"radius": 72,
						"enemyDamage": {
							"type": "damage",
							"school": "magic",
							"base": 10,
							"ad": 0,
							"ap": 0.11
						},
						"allyHeal": {
							"type": "heal",
							"base": 8,
							"ap": 0.08
						},
						"originContactRadius": 14
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "세라프 회전",
				"description": "4초 동안 날개 회전 속도 +80%, 쌍익 궤도의 피해·회복 +25%를 얻습니다. 평타 공격 속도는 오르지 않습니다.",
				"cooldown": 12,
				"castTime": 0.12,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "buff",
						"stat": "orbitPower",
						"amount": 0.25,
						"duration": 4
					},
					{
						"type": "buff",
						"stat": "originOrbitSpeed",
						"amount": 0.8,
						"duration": 4
					}
				],
				"condition": null,
				"ai": {
					"intent": "buff",
					"weight": 1,
					"cluster": 0,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"HEALING",
					"SUSTAINED_DAMAGE"
				],
				"action": "",
				"vfx": {
					"color": "#fff1a7",
					"pattern": "wingSpin",
					"glyph": "旋"
				},
				"geometry": "지속 4초",
				"timing": "12 / 0.12"
			},
			{
				"slot": 2,
				"name": "단익 부메랑",
				"description": "두 날개를 합쳐 던집니다. 경로의 모든 적에게 가는 길 41+0.45AP, 돌아오는 길 70% 마법 피해(각 1회)와 3초간 0.75초마다 5+0.07AP 지속 피해(갱신)를 줍니다. 날아가 있는 동안(최대 2.5초) 궤도 날개가 사라집니다.",
				"cooldown": 10,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 320,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 34,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 999,
				"bounces": 0,
				"homing": false,
				"returnToSource": true,
				"maxDistance": 320,
				"effects": [
					{
						"type": "damage",
						"school": "magic",
						"base": 41,
						"ad": 0,
						"ap": 0.45
					},
					{
						"type": "dot",
						"duration": 3,
						"interval": 0.75,
						"damageEffect": {
							"type": "damage",
							"school": "magic",
							"base": 5,
							"ad": 0,
							"ap": 0.07
						},
						"originRefresh": true
					}
				],
				"condition": null,
				"ai": {
					"intent": "damage",
					"weight": 1.05,
					"cluster": 0.7,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"RANGED",
					"DAMAGE_OVER_TIME",
					"AREA_DAMAGE"
				],
				"action": "",
				"vfx": {
					"color": "#f2de88",
					"pattern": "boomerangWing",
					"glyph": "翼"
				},
				"geometry": "폭 34, 속도 420, 왕복",
				"timing": "10 / 0.25",
				"flags": {
					"originWing": true
				}
			},
			{
				"slot": 3,
				"name": "구원의 비행",
				"description": "다른 아군 영웅에게 날아가(장애물 위 통과) 도착하면 그 아군에게 95+0.75AP 보호막을 4초 줍니다.",
				"cooldown": 11,
				"castTime": 0.12,
				"recovery": 0.18,
				"range": 340,
				"target": "ally",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "move_self",
						"mode": "blinkToAlly",
						"distance": 999,
						"speed": 620
					},
					{
						"type": "shield",
						"base": 95,
						"ap": 0.75,
						"duration": 4
					}
				],
				"condition": null,
				"ai": {
					"intent": "support",
					"weight": 1.4,
					"cluster": 0,
					"survival": 0.8,
					"combo": 0
				},
				"tags": [
					"MOBILITY",
					"SHIELDING"
				],
				"action": "rescueFlight",
				"vfx": {
					"color": "#fff3bd",
					"pattern": "rescueFlight",
					"glyph": "救"
				},
				"geometry": "비행 속도 620",
				"timing": "11 / 0.12",
				"flags": {
					"originOtherAlly": true,
					"originLowestHp": true
				}
			},
			{
				"slot": 4,
				"name": "강림 활공",
				"description": "1.2초 활공하며 이동 속도 +60%, 방어력·마법 저항력 +30%를 얻습니다(활공 중 평타·스킬 불가). 착지 지점 반경 110의 적에게 50+0.45AP 마법 피해와 에어본 0.5초(강인함 무시)를 줍니다.",
				"cooldown": 16,
				"castTime": 0.2,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "area",
				"shape": "single",
				"radius": 110,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "buff",
						"stat": "moveSpeed",
						"amount": 0.6,
						"duration": 1.2
					},
					{
						"type": "buff",
						"stat": "armor",
						"amount": 0.3,
						"duration": 1.2
					},
					{
						"type": "buff",
						"stat": "magicResistance",
						"amount": 0.3,
						"duration": 1.2
					},
					{
						"type": "damage",
						"school": "magic",
						"base": 50,
						"ad": 0,
						"ap": 0.45
					},
					{
						"type": "status",
						"status": "airborne",
						"duration": 0.5,
						"magnitude": 0
					}
				],
				"condition": null,
				"ai": {
					"intent": "engage_support",
					"weight": 1.25,
					"cluster": 0.9,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"MOBILITY",
					"CONTROL",
					"AREA_DAMAGE"
				],
				"action": "glide",
				"vfx": {
					"color": "#ffe08d",
					"pattern": "angelDrop",
					"glyph": "降"
				},
				"geometry": "활공 1.2초, 착지 반경 110",
				"timing": "16 / 0.2"
			}
		]
	}, 
	{
		"id": "plague_doctor", 
		"name": "역병의사", 
		"glyph": "疫", 
		"accent": "#78a86f", 
		"role": "CONTROL", 
		"tags": ["RANGED", "CONTROL", "DAMAGE_OVER_TIME", "HEALING", "AREA_DAMAGE"], 
		"summary": "치유 감소량을 주머니에 모아 아군 회복으로 되돌리고, 역병 스택으로 적의 유지력을 해체한다.", 
		"stats": {
			"maxHealth": 1040, 
			"attackDamage": 44, 
			"abilityPower": 82, 
			"armor": 20, 
			"magicResistance": 24, 
			"moveSpeed": 102, 
			"attackSpeed": 0.7, 
			"attackRange": 205, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 16
		}, 
		"preferredRange": 185, 
		"behavior": {
			"aggression": 0.53, 
			"survival": 0.62, 
			"focusLowHealth": 0.5, 
			"focusHighThreat": 0.72, 
			"protectAllies": 0.82, 
			"preferBackline": 0.9, 
			"preferCluster": 0.82, 
			"riskTolerance": 0.24, 
			"flank": 0.2, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "회복 억제형"
		}, 
		"doctrine": {
			"title": "역병 억제·회수", 
			"code": "PLAGUE TRIAGE", 
			"roles": ["ANTI_HEAL_CONTROLLER", "TRIAGE_SUPPORT", "ATTRITION_BACKLINE"], 
			"identity": "적 회복을 역병으로 차단하고 차단량을 아군 회복으로 되돌리는 전투 의사."
		}, 
		"nexus": {
			"title": "회복 차단 재분배", 
			"role": "CONTROL", 
			"risk": 0.3, 
			"teamwork": 0.96, 
			"gamble": 0.28, 
			"information": 0.86, 
			"combo": [3, 1, 2], 
			"skills": ["부채꼴에 오래 머물 적에게 역병 분무", "실제 저장 예산과 접촉 아군만 치유", "독침으로 역병 유지하고 도트 중복 낭비 억제"], 
			"identity": "관측된 치유를 막아 얻은 예산만 아군에게 재분배한다."
		}, 
		"passives": [
			{
				"name": "힐 주머니", 
				"description": "내 역병 때문에 줄어든 적의 실제 회복량(넘치는 회복 제외)을 힐 주머니에 저장합니다(최대 1200). 회수 분사가 이 주머니를 씁니다.", 
				"rules": [{"type": "heal_reduction_bank", "resourceKey": "healBank", "originCap": 1200}]
			}, 
			{
				"name": "역병 누적", 
				"description": "역병 1스택마다 받는 회복이 10% 줄어듭니다(최대 6스택 −60%, 7초, 쌓일 때 갱신). 치유 감소가 겹치면 가장 강한 하나만 적용되며, 내 역병이 가장 강할 때만 주머니에 저장됩니다.", 
				"rules": [{"type": "plague_heal_reduction", "perStack": 0.1, "maxStacks": 6, "maxReduction": 0.6}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "역병 분무", 
				"description": "전방 75° 부채꼴의 적에게 38+0.4AP 마법 피해와 역병 1을 줍니다. 그 자리에 3초간 안개가 남아 0.75초마다(최대 4회) 6+0.07AP 마법 피해와 역병 1을 줍니다.", 
				"cooldown": 8, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 180, 
				"target": "enemy", 
				"delivery": "cone", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 1.308997, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "magic", "base": 38, "ad": 0, "ap": 0.4}, 
					{"type": "mark", "status": "plague", "duration": 7, "stacks": 1, "maxStacks": 6, "originOwned": true}, 
					{
						"type": "zone", 
						"radius": 180, 
						"duration": 3, 
						"interval": 0.75, 
						"effects": [
							{"type": "damage", "school": "magic", "base": 6, "ad": 0, "ap": 0.07}, 
							{"type": "mark", "status": "plague", "duration": 7, "stacks": 1, "maxStacks": 6, "originOwned": true}
						], 
						"filter": "enemy", 
						"originCone": true
					}
				], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.15, "cluster": 0.8, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "DAMAGE_OVER_TIME"], 
				"action": "plagueCone", 
				"vfx": {"color": "#84bd72", "pattern": "plagueSpray", "glyph": "霧"}, 
				"geometry": "부채꼴 75°", 
				"timing": "8 / 0.25"
			}, 
			{
				"slot": 2, 
				"name": "회수 분사", 
				"description": "주머니에서 최대 360+2AP를 꺼내 치유 안개를 뿜습니다. 안개는 240까지 나아가며 3초간 0.25초마다 닿은 다친 아군 영웅을 체력 비율이 낮은 순으로 회복합니다(1회 최대 예산의 1/12). 남은 양은 사라지고, 주머니가 비면 쓸 수 없습니다.", 
				"cooldown": 10, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 240, 
				"target": "position_ally", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 48, 
				"width": 24, 
				"angle": 1.047198, 
				"speed": 180, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "heal_bank", "ratio": 1, "originBudget": true}], 
				"condition": {"selfResource": {"key": "healBank", "min": 1}}, 
				"ai": {"intent": "support", "weight": 1.25, "cluster": 0.7, "survival": 0, "combo": 0}, 
				"tags": ["HEALING", "AREA_DAMAGE"], 
				"action": "healingMist", 
				"vfx": {"color": "#a7db8b", "pattern": "healSpray", "glyph": "療"}, 
				"geometry": "접촉 반경 48, 속도 180", 
				"timing": "10 / 0.25"
			}, 
			{
				"slot": 3, 
				"name": "독침", 
				"description": "30+0.32AP 마법 피해와 역병 1을 주고, 3초간 0.75초마다 7+0.08AP 마법 피해(총 4회)를 줍니다. 다시 맞히면 중첩 없이 갱신되며 지속 피해는 역병을 쌓지 않습니다.", 
				"cooldown": 3.6, 
				"castTime": 0.18, 
				"recovery": 0.18, 
				"range": 280, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 16, 
				"angle": 0.9, 
				"speed": 450, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "magic", "base": 30, "ad": 0, "ap": 0.32}, 
					{"type": "mark", "status": "plague", "duration": 7, "stacks": 1, "maxStacks": 6, "originOwned": true}, 
					{
						"type": "dot", 
						"duration": 3, 
						"interval": 0.75, 
						"damageEffect": {"type": "damage", "school": "magic", "base": 7, "ad": 0, "ap": 0.08}, 
						"originRefresh": true
					}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1.065, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["DAMAGE_OVER_TIME"], 
				"action": "", 
				"vfx": {"color": "#a2c96f", "pattern": "poisonKnife", "glyph": "毒"}, 
				"geometry": "폭 16, 속도 450", 
				"timing": "3.6 / 0.18"
			}
		]
	}, 
	{
		"id": "hive_mind",
		"name": "하이브 마인드",
		"glyph": "群",
		"accent": "#a16fc4",
		"role": "CONTROL",
		"tags": [
			"RANGED",
			"SUMMONER",
			"CONTROL",
			"SUSTAINED_DAMAGE",
			"SINGLE_TARGET"
		],
		"summary": "새끼와 기생충으로 감염을 쌓고, 감염된 적의 행동 자체를 빼앗아 팀의 집중 공격을 지휘한다.",
		"stats": {
			"maxHealth": 1160,
			"attackDamage": 46,
			"abilityPower": 86,
			"armor": 18,
			"magicResistance": 24,
			"moveSpeed": 68,
			"attackSpeed": 0.55,
			"attackRange": 230,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 23
		},
		"preferredRange": 205,
		"behavior": {
			"aggression": 0.39,
			"survival": 0.8,
			"focusLowHealth": 0.5,
			"focusHighThreat": 0.96,
			"protectAllies": 0.55,
			"preferBackline": 0.98,
			"preferCluster": 0.67,
			"riskTolerance": 0.12,
			"flank": 0.2,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "팀 지휘형"
		},
		"doctrine": {
			"title": "공유 신경망 지휘",
			"code": "SYNAPTIC COMMAND",
			"roles": [
				"INFORMATION_COMMANDER",
				"SUMMON_BACKLINE",
				"CONTROL_EXECUTOR",
				"SHOT_CALLER"
			],
			"identity": "불완전 정보를 쿨다운 공개와 소환 정찰로 줄이고 감염된 적을 조종한다."
		},
		"nexus": {
			"title": "감염 지휘권 전환",
			"role": "COMMAND",
			"risk": 0.26,
			"teamwork": 0.95,
			"gamble": 0.5,
			"information": 0.99,
			"combo": [
				1,
				2,
				3,
				4
			],
			"skills": [
				"새끼가 진입할 안전한 압박선 유지",
				"접촉 가능한 적에게 기생충 접근 유도",
				"3초 동안 아군이 활용할 감염 적 선택",
				"조종 종료의 기회비용과 마무리 가치 비교"
			],
			"identity": "정보 공개 표본과 감염을 팀의 제어 창으로 바꾼다."
		},
		"passives": [
			{
				"name": "공유 신경망",
				"description": "7초마다 정보 가치가 높은 적 1명을 골라 모든 스킬의 남은 재사용 대기시간을 7초간 팀에 공개합니다(시야 밖도 가능, 위치·체력은 미공개). 그 적의 팀에 관조 중인 정치가가 있으면 막힙니다.",
				"rules": [
					{
						"type": "reveal_cooldowns",
						"interval": 7
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "산란 명령",
				"description": "새끼 3마리를 9초간 소환합니다. 새끼(체력 90+0.3AP, 방어·마저 10, 이동 속도 120)는 가장 가까운 적을 쫓아 1.1초마다 10+0.1AP 물리 피해를 줍니다. 능력치는 소환 순간 고정됩니다.",
				"cooldown": 12,
				"castTime": 0.35,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "summon",
						"count": 3,
						"duration": 9,
						"attack": {
							"type": "damage",
							"school": "physical",
							"base": 10,
							"ad": 0,
							"ap": 0.1
						},
						"hp": 90,
						"hpAp": 0.3,
						"armor": 10,
						"speed": 120,
						"interval": 1.1,
						"glyph": "幼",
						"originEntity": "brood"
					}
				],
				"condition": null,
				"ai": {
					"intent": "summon",
					"weight": 1.05,
					"cluster": 0,
					"survival": 0,
					"combo": 0
				},
				"tags": [
					"SUMMONER"
				],
				"action": "",
				"vfx": {
					"color": "#b985d4",
					"pattern": "broodSpawn",
					"glyph": "卵"
				},
				"geometry": "자신 주변 3마리",
				"timing": "12 / 0.35"
			},
			{
				"slot": 2,
				"name": "기생 침투",
				"description": "기생충 2마리를 8초간 소환합니다(체력 55+0.15AP, 방어·마저 5, 이동 속도 150). 적에게 닿으면 감염 1(8초, 최대 4)을 남기고 사라집니다. 피해는 없으며 감염은 군체 조종의 조건입니다.",
				"cooldown": 12,
				"castTime": 0.3,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "summon",
						"count": 2,
						"duration": 8,
						"attack": {
							"type": "damage",
							"school": "magic",
							"base": 0,
							"ad": 0,
							"ap": 0
						},
						"hp": 55,
						"hpAp": 0.15,
						"armor": 5,
						"speed": 150,
						"interval": 1.1,
						"glyph": "寄",
						"originEntity": "parasite",
						"onHitStatus": {
							"status": "infection",
							"duration": 8,
							"stacks": 1,
							"maxStacks": 4,
							"originOwned": true
						}
					}
				],
				"condition": null,
				"ai": {
					"intent": "summon",
					"weight": 1.12,
					"cluster": 0,
					"survival": 0,
					"combo": 0.7
				},
				"tags": [
					"SUMMONER",
					"CONTROL"
				],
				"action": "",
				"vfx": {
					"color": "#c26ed0",
					"pattern": "parasiteSpawn",
					"glyph": "寄"
				},
				"geometry": "자신 주변 2마리",
				"timing": "12 / 0.3"
			},
			{
				"slot": 3,
				"name": "군체 조종",
				"description": "내 감염이 있는 적을 3초간 조종합니다(강인함 무시). 조종된 적은 이쪽 편이 되어 원래 아군을 공격하고 공격받습니다. 성공하면 감염 1을 소비하며, 관조·저지 불가·무적 대상에게는 실패하고 감염도 남습니다.",
				"cooldown": 16,
				"castTime": 0.35,
				"recovery": 0.18,
				"range": 270,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "status",
						"status": "control",
						"duration": 3,
						"magnitude": 0,
						"originController": true
					},
					{
						"type": "consume_status",
						"status": "infection",
						"originOwned": true,
						"originCount": 1
					}
				],
				"condition": {
					"targetStatus": "infection",
					"owned": true
				},
				"ai": {
					"intent": "control",
					"weight": 1.4,
					"cluster": 0,
					"survival": 0,
					"combo": 1
				},
				"tags": [
					"CONTROL",
					"SINGLE_TARGET"
				],
				"action": "",
				"vfx": {
					"color": "#b276e8",
					"pattern": "mindControl",
					"glyph": "操"
				},
				"geometry": "",
				"timing": "16 / 0.35"
			},
			{
				"slot": 4,
				"name": "자해 명령",
				"description": "내가 조종 중인 대상에게 70+0.45AP+대상 최대 체력 4% 고정 피해를 주고 조종을 끝냅니다. 무적으로 피해가 막혀도 조종은 끝납니다.",
				"cooldown": 14,
				"castTime": 0.2,
				"recovery": 0.18,
				"range": 320,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "damage",
						"school": "true",
						"base": 70,
						"ad": 0,
						"ap": 0.45,
						"targetMaxHp": 0.04
					},
					{
						"type": "end_control"
					}
				],
				"condition": {
					"targetStatus": "control",
					"owned": true
				},
				"ai": {
					"intent": "execute",
					"weight": 1.45,
					"cluster": 0,
					"survival": 0,
					"combo": 1
				},
				"tags": [
					"BURST",
					"SINGLE_TARGET"
				],
				"action": "",
				"vfx": {
					"color": "#df7af0",
					"pattern": "selfRend",
					"glyph": "自"
				},
				"geometry": "",
				"timing": "14 / 0.2"
			}
		]
	}, 
	{
		"id": "nitro", 
		"name": "니트로", 
		"glyph": "爆", 
		"accent": "#f06a47", 
		"role": "FRONTLINE", 
		"tags": ["MELEE", "MOBILITY", "SUSTAINED_DAMAGE", "AREA_DAMAGE", "ENGAGE"], 
		"summary": "맞을수록 가속하고 벽을 타며 한계치를 늘린다. 축적한 폭발 스택을 이동과 충돌 피해로 환전하는 돌진형 탱커.", 
		"stats": {
			"maxHealth": 970, 
			"attackDamage": 72, 
			"abilityPower": 35, 
			"armor": 64, 
			"magicResistance": 56, 
			"moveSpeed": 104, 
			"attackSpeed": 0.9, 
			"attackRange": 45, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 17
		}, 
		"preferredRange": 44, 
		"behavior": {
			"aggression": 0.82, 
			"survival": 0.61, 
			"focusLowHealth": 0.48, 
			"focusHighThreat": 0.7, 
			"protectAllies": 0.2, 
			"preferBackline": 0.5, 
			"preferCluster": 0.78, 
			"riskTolerance": 0.78, 
			"flank": 0.72, 
			"minimumCommitTime": 0.48, 
			"switchThreshold": 0.12, 
			"label": "벽면 충돌형"
		}, 
		"doctrine": {
			"title": "벽면 과급 충돌", 
			"code": "WALL REDLINE", 
			"roles": ["WALL_DIVER", "CHAOS_TANK", "AREA_BRAWLER"], 
			"identity": "피격과 벽 접촉을 과급 자원으로 바꿔 최고속 몸통박치기를 만든다."
		}, 
		"nexus": {
			"title": "벽면 에너지 돌파", 
			"role": "DIVER", 
			"risk": 0.89, 
			"teamwork": 0.57, 
			"gamble": 0.82, 
			"information": 0.49, 
			"combo": [2, 3, 1], 
			"skills": ["필수 2충전과 후속 접촉 강화량 비교", "벽 접선에서만 점화의 기동값 인정", "실제 이동 속도를 유지한 접촉 경로 선택"], 
			"identity": "벽면 재접촉과 충격 스택을 이용해 밀집 전열을 가로지른다."
		}, 
		"passives": [
			{
				"name": "충격 축적", 
				"description": "받은 체력 피해(환경 피해 포함, 보호막 흡수분 제외) 65마다 충격 1스택을 얻습니다(최대 8, 벽면 과급으로 최대 12). 스택당 이동 속도 +3%, 공격력 +3.5%, 받는 고정 피해 −2.5%입니다. 4초간 피해를 받지 않으면 1초마다 1스택씩 줄어듭니다.", 
				"rules": [
					{
						"type": "rage_on_damage", 
						"resourceKey": "rage", 
						"maxStacks": 8, 
						"decayDelay": 4, 
						"movePerStack": 0.03, 
						"attackPerStack": 0.035, 
						"trueResistPerStack": 0.025, 
						"originDamagePerStack": 65
					}
				]
			}, 
			{
				"name": "벽면 과급", 
				"description": "벽에 새로 닿을 때마다 충격 최대치가 1 늘어납니다(최대 +4). 벽을 따라 움직이면 이동 속도가 35% 빨라집니다. 마지막으로 벽에 닿은 지 10초가 지나면 늘어난 최대치가 사라지고 8을 넘는 스택은 잘립니다.", 
				"rules": [{"type": "wall_mastery", "bonusMaxStacks": 4, "speedBonus": 0.35, "linger": 10}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "폭쇄 구체", 
				"description": "충격 2스택을 소비해 구체를 던집니다. 처음 닿은 적·벽이나 목표 지점에서 폭발해 반경 66의 적에게 116+0.65AD+0.2AP 물리 피해(64+2스택×26)를 줍니다. 충격이 2 미만이면 쓸 수 없습니다.", 
				"cooldown": 6.5, 
				"castTime": 0.25, 
				"recovery": 0.18, 
				"range": 260, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 66, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 380, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "consume_resource", "key": "rage", "amount": 2, "bonusDamagePerSpent": 26}, 
					{"type": "damage", "school": "physical", "base": 64, "ad": 0.65, "ap": 0.2}
				], 
				"condition": {"selfResource": {"key": "rage", "min": 2}}, 
				"ai": {"intent": "damage", "weight": 1.18, "cluster": 0.75, "survival": 0, "combo": 0}, 
				"tags": ["RANGED", "AREA_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#ff744d", "pattern": "explosiveOrb", "glyph": "炸"}, 
				"geometry": "속도 380, 폭발 반경 66", 
				"timing": "6.5 / 0.25"
			}, 
			{
				"slot": 2, 
				"name": "벽면 점화", 
				"description": "벽에 붙어 있을 때만 씁니다. 1.2초간 벽을 따라 이동 속도 +300%로 질주하며 모서리에서 방향을 바꿉니다. 벽에서 떨어지면 끝나고, 속박·기절 등에 걸린 동안은 멈춥니다.", 
				"cooldown": 11, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "buff", "stat": "moveSpeed", "amount": 3, "duration": 1.2}], 
				"condition": {"nearWall": true}, 
				"ai": {"intent": "mobility", "weight": 1.32, "cluster": 0, "survival": 0.55, "combo": 0}, 
				"tags": ["MOBILITY"], 
				"action": "wallRun", 
				"vfx": {"color": "#ff9a5b", "pattern": "wallRun", "glyph": "壁"}, 
				"geometry": "지속 1.2초", 
				"timing": "11 / 0.1", 
				"flags": {"originDuration": 1.2}
			}, 
			{
				"slot": 3, 
				"name": "연쇄 자폭", 
				"description": "5초 동안 이동 속도 +20%, 0.5초마다 몸 주변(몸+20)의 적에게 24+0.12×현재 이동 속도+5×충격 스택만큼 마법 피해를 줍니다. 멈춰 있으면 속도 몫은 0입니다.", 
				"cooldown": 11.5, 
				"castTime": 0.12, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "buff", 
						"stat": "contactExplosion", 
						"amount": 1, 
						"duration": 5, 
						"radius": 37, 
						"base": 24, 
						"speedRatio": 0.12, 
						"rageRatio": 5, 
						"interval": 0.5, 
						"originContact": true, 
						"originContactPadding": 20
					}, 
					{"type": "buff", "stat": "moveSpeed", "amount": 0.2, "duration": 5}
				], 
				"condition": null, 
				"ai": {"intent": "engage", "weight": 1.3, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["AREA_DAMAGE", "SUSTAINED_DAMAGE"], 
				"action": "", 
				"vfx": {"color": "#f0523f", "pattern": "chainExplosion", "glyph": "連"}, 
				"geometry": "지속 5초, 몸+20 접촉", 
				"timing": "11.5 / 0.12"
			}
		]
	}, 
	{
		"id": "dimensionalist", 
		"name": "차원술사", 
		"glyph": "門", 
		"accent": "#59b7dd", 
		"role": "SUPPORT", 
		"tags": ["MELEE", "SHIELDING", "MOBILITY", "RANGED", "CONTROL", "BURST"], 
		"summary": "차원 조각을 모아 투사체 방어와 포탈 지원을 강화하고, 끝에는 방어를 무시하는 차원 칼날을 쏜다.", 
		"stats": {
			"maxHealth": 1080, 
			"attackDamage": 82, 
			"abilityPower": 98, 
			"armor": 36, 
			"magicResistance": 36, 
			"moveSpeed": 82, 
			"attackSpeed": 0.85, 
			"attackRange": 60, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 17
		}, 
		"preferredRange": 76, 
		"behavior": {
			"aggression": 0.52, 
			"survival": 0.8, 
			"focusLowHealth": 0.5, 
			"focusHighThreat": 0.86, 
			"protectAllies": 0.91, 
			"preferBackline": 0.5, 
			"preferCluster": 0.62, 
			"riskTolerance": 0.2, 
			"flank": 0.2, 
			"minimumCommitTime": 0.48, 
			"switchThreshold": 0.12, 
			"label": "투사체 대응형"
		}, 
		"doctrine": {
			"title": "차원 자원·탄도 방어", 
			"code": "RIFT ECONOMY", 
			"roles": ["PROJECTILE_WARDEN", "PORTAL_COORDINATOR", "RESOURCE_FINISHER"], 
			"identity": "투사체 무효화와 포탈 이동으로 차원 조각을 만들고 차원 칼날에 투자한다."
		}, 
		"nexus": {
			"title": "연결점 탄도 재설계", 
			"role": "SUPPORT", 
			"risk": 0.36, 
			"teamwork": 0.94, 
			"gamble": 0.57, 
			"information": 0.94, 
			"combo": [2, 3, 1, 4], 
			"skills": ["관측 탄도에 균열을 배치", "안전한 입구와 유효 출구를 함께 고름", "실제 포탈 쌍과 아군 사격량 평가", "30조각 소비 후 방어 강화 상실도 반영"], 
			"identity": "위치와 탄도 자원을 공유하되 조각 임계값을 보존한다."
		}, 
		"passives": [
			{
				"name": "차원 조각", 
				"description": "포탈(내 포탈·아군 포탈·전장 포탈)을 직접 통과할 때마다 차원 조각을 10 얻습니다(최대 40). 점멸·돌진은 제외되며, 같은 영웅은 포탈을 쓴 뒤 2.5초간 다시 쓸 수 없습니다. 조각은 차원 칼날만 소비합니다.", 
				"rules": [{"type": "portal_shards", "resourceKey": "shards", "max": 40, "gainOnMobility": 0, "originGainPerUse": 10}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "차원 균열", 
				"description": "앞에 길이 160의 균열을 3초간 세워 닿는 적 투사체를 모두 없앱니다. 시전할 때 조각이 30 이상이면(소비 없음) 재사용 대기시간이 18초가 되고, 막은 탄을 원래 피해 30%의 유도탄으로 쏜 적에게 되돌립니다.", 
				"cooldown": 26, 
				"castTime": 0.15, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "projectile_guard", 
						"duration": 3, 
						"reduction": 1, 
						"reflect": 0.3, 
						"enhancedAtResource": {"key": "shards", "min": 30}, 
						"originRift": true, 
						"enhancedCooldown": 18
					}
				], 
				"condition": null, 
				"ai": {"intent": "survival", "weight": 1.35, "cluster": 0, "survival": 1, "combo": 0}, 
				"tags": ["PEEL"], 
				"action": "rift", 
				"vfx": {"color": "#62c7eb", "pattern": "riftGuard", "glyph": "裂"}, 
				"geometry": "길이 160, 지속 3초", 
				"timing": "26 / 0.15", 
				"flags": {"originRiftLength": 160}
			}, 
			{
				"slot": 2, 
				"name": "쌍문", 
				"description": "내 주변 300 안의 두 지점(140 이상 간격)에 파괴되지 않는 포탈 한 쌍을 10초간 설치합니다(이전 쌍은 제거). 아군이 닿으면 반대편으로 이동합니다. 시전 시 조각 20 이상이면(소비 없음) 재사용 대기시간이 11초가 되고, 이용한 아군(나 포함)은 60+0.5AP 보호막을 3초 얻습니다.", 
				"cooldown": 15, 
				"castTime": 0.3, 
				"recovery": 0.18, 
				"range": 300, 
				"target": "position_ally", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "portal_pair", 
						"duration": 10, 
						"shieldAtResource": {"key": "shards", "min": 20, "base": 60, "ap": 0.5}, 
						"originPortals": true, 
						"enhancedCooldown": 11
					}
				], 
				"condition": null, 
				"ai": {"intent": "support", "weight": 1.35, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["MOBILITY", "SHIELDING"], 
				"action": "portalPair", 
				"vfx": {"color": "#70d3ef", "pattern": "portalPair", "glyph": "門"}, 
				"geometry": "두 지점, 140 이상 간격", 
				"timing": "15 / 0.3"
			}, 
			{
				"slot": 3, 
				"name": "탄도 전환", 
				"description": "5초 동안 아군 투사체(평타 포함)가 내 포탈에 닿으면 반대편 포탈로 옮겨져 같은 방향으로 계속 날아갑니다(탄마다 1회). 시전 시 조각 10 이상이면 통과한 탄의 피해가 10% 커집니다. 내 포탈 쌍이 있어야 씁니다.", 
				"cooldown": 11, 
				"castTime": 0.12, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "buff", 
						"stat": "originTrajectory", 
						"amount": 1, 
						"duration": 5, 
						"resourceGate": {"key": "shards", "min": 10}, 
						"originDamageBonus": 0.1
					}
				], 
				"condition": null, 
				"ai": {"intent": "support", "weight": 1.18, "cluster": 0.75, "survival": 0, "combo": 0}, 
				"tags": ["SUPPORT"], 
				"action": "portalArming", 
				"vfx": {"color": "#8be3f4", "pattern": "trajectoryGate", "glyph": "軌"}, 
				"geometry": "지속 5초", 
				"timing": "11 / 0.12", 
				"flags": {"originDuration": 5}
			}, 
			{
				"slot": 4, 
				"name": "차원 칼날", 
				"description": "조각 30을 소비해 유도 칼날을 쏘아 130+1.15AP 고정 피해를 줍니다. 벽·앞을 가로막은 적·차원 균열에 막힐 수 있으며 막혀도 조각은 돌아오지 않습니다.", 
				"cooldown": 16, 
				"castTime": 0.35, 
				"recovery": 0.18, 
				"range": 350, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 620, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": true, 
				"returnToSource": false, 
				"effects": [
					{"type": "consume_resource", "key": "shards", "amount": 30}, 
					{"type": "damage", "school": "true", "base": 130, "ad": 0, "ap": 1.15}
				], 
				"condition": {"selfResource": {"key": "shards", "min": 30}}, 
				"ai": {"intent": "execute", "weight": 1.58, "cluster": 0, "survival": 0, "combo": 0}, 
				"tags": ["BURST", "SINGLE_TARGET"], 
				"action": "", 
				"vfx": {"color": "#b3f4ff", "pattern": "dimensionBlade", "glyph": "界"}, 
				"geometry": "유도 탄속 620", 
				"timing": "16 / 0.35"
			}
		]
	}, 
	{
		"id": "hermes", 
		"name": "헤르메스", 
		"glyph": "翼", 
		"accent": "#66d1d8", 
		"role": "DAMAGE", 
		"tags": ["MELEE", "MOBILITY", "CONTROL", "BURST", "ENGAGE"], 
		"summary": "비전투 이동과 아군 이동기 차용으로 끊임없이 각도를 바꾸고, 수면과 하르페로 CC 연계를 마무리한다.", 
		"stats": {
			"maxHealth": 900, 
			"attackDamage": 90, 
			"abilityPower": 38, 
			"armor": 20, 
			"magicResistance": 20, 
			"moveSpeed": 136, 
			"attackSpeed": 1, 
			"attackRange": 45, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05, 
			"bodyRadius": 14
		}, 
		"preferredRange": 44, 
		"behavior": {
			"aggression": 0.795, 
			"survival": 0.69, 
			"focusLowHealth": 0.76, 
			"focusHighThreat": 0.62, 
			"protectAllies": 0.2, 
			"preferBackline": 0.72, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.445, 
			"flank": 0.81, 
			"minimumCommitTime": 0.37, 
			"switchThreshold": 0.078, 
			"label": "초고속 연계형"
		}, 
		"doctrine": {
			"title": "초고속 정찰·CC 회수", 
			"code": "TALARIA TEMPO", 
			"roles": ["SCOUT", "CC_FINISHER", "MOBILE_GUARDIAN"], 
			"identity": "전투 전 속도로 정보를 갱신하고 투명 진입 뒤 CC 대상에 하르페를 꽂는다."
		}, 
		"nexus": {
			"title": "수면 창 기동 암살", 
			"role": "FLANK", 
			"risk": 0.77, 
			"teamwork": 0.69, 
			"gamble": 0.78, 
			"information": 0.83, 
			"combo": [1, 2, 3], 
			"skills": ["투명 재사용 기절은 적 접근을 확인", "CC 중복 대신 하르페 창으로 수면", "CC 확인 후 추가 150%AD를 사용"], 
			"identity": "차용 이동기의 사용권·탈출선을 남기고 짧은 제어창에서 공격한다."
		}, 
		"passives": [
			{
				"name": "신들의 전령", 
				"description": "차용 스킬이 없을 때 12초마다 살아 있는 다른 아군의 이동 스킬 하나를 무작위로 빌립니다. 24초 안에 재사용 대기시간 없이 한 번 쓸 수 있으며, 피해·보호막은 헤르메스의 공격력·주문력으로 계산됩니다.", 
				"rules": [{"type": "borrow_mobility", "interval": 12, "maxHold": 24}]
			}, 
			{
				"name": "탈라리아", 
				"description": "마지막 전투 행동 2.5초 뒤부터 1초에 걸쳐 이동 속도가 최대 +120%까지 오릅니다. 피해를 주거나 받거나, 평타·적 대상 스킬을 쓰면 즉시 사라집니다.", 
				"rules": [{"type": "out_of_combat_speed", "bonus": 1.2, "delay": 2.5}]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "클라미스", 
				"description": "최대 2.2초 투명해지고 이동 속도 +35%를 얻습니다. 0.25초 뒤 다시 쓰면 투명을 풀고 반경 90의 적을 기절 0.5초(강인함 무시)에 빠뜨립니다. 평타·적 대상 스킬로 풀리거나 시간이 끝나면 기절은 없습니다.", 
				"cooldown": 12, 
				"castTime": 0.1, 
				"recovery": 0.18, 
				"range": 0, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "status", "status": "invisible", "duration": 2.2, "magnitude": 0}, 
					{"type": "buff", "stat": "moveSpeed", "amount": 0.35, "duration": 2.2}
				], 
				"condition": null, 
				"ai": {"intent": "engage", "weight": 1.395, "cluster": 0, "survival": 0.4, "combo": 0.625}, 
				"tags": ["MOBILITY", "CONTROL"], 
				"action": "cloak", 
				"vfx": {"color": "#71dce2", "pattern": "cloakReveal", "glyph": "衣"}, 
				"geometry": "투명 2.2초, 재시전 반경 90", 
				"timing": "12 / 0.1"
			}, 
			{
				"slot": 2, 
				"name": "카두세우스", 
				"description": "가까운 적을 1.8초 재웁니다(수면: 행동 불가, 체력 피해를 받으면 즉시 깸). 피해는 없습니다.", 
				"cooldown": 8.8, 
				"castTime": 0.15, 
				"recovery": 0.18, 
				"range": 80, 
				"target": "enemy", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "status", "status": "sleep", "duration": 1.8, "magnitude": 0, "breaksOnDamage": true}], 
				"condition": null, 
				"ai": {"intent": "control", "weight": 1.555, "cluster": 0, "survival": 0, "combo": 1}, 
				"tags": ["CONTROL"], 
				"action": "", 
				"vfx": {"color": "#98e8e1", "pattern": "sleepStaff", "glyph": "眠"}, 
				"geometry": "", 
				"timing": "8.8 / 0.15"
			}, 
			{
				"slot": 3, 
				"name": "하르페", 
				"description": "둔화를 제외한 군중 제어에 걸린 적만 찌를 수 있습니다. 24+0.35AD+1.5AD 물리 피해를 한 번에 줍니다(수면 중인 적에게도 추가 피해 적용).", 
				"cooldown": 6.3, 
				"castTime": 0.15, 
				"recovery": 0.18, 
				"range": 75, 
				"target": "enemy", 
				"delivery": "direct", 
				"shape": "single", 
				"radius": 22, 
				"width": 24, 
				"angle": 0.9, 
				"speed": 420, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "damage", "school": "physical", "base": 24, "ad": 0.35, "ap": 0, "originCcAd": 1.5}], 
				"condition": {"targetIsCC": true}, 
				"ai": {"intent": "burst", "weight": 1.79, "cluster": 0, "survival": 0, "combo": 1}, 
				"tags": ["BURST", "SINGLE_TARGET"], 
				"action": "", 
				"vfx": {"color": "#d2fff2", "pattern": "harpe", "glyph": "刃"}, 
				"geometry": "", 
				"timing": "6.3 / 0.15", 
				"flags": {"originHarpe": true}
			}
		]
	}, 
	{
		"id": "world_tree",
		"name": "세계수",
		"glyph": "樹",
		"accent": "#76ddb0",
		"role": "SUPPORT",
		"tags": [
			"MELEE",
			"HEALING",
			"CONTROL",
			"AREA_DAMAGE",
			"SUMMONER"
		],
		"summary": "이동 경로를 닫아 재생의 숲을 만들고 나무·꽃·뿌리로 아군의 전투 공간을 설계한다.",
		"stats": {
			"maxHealth": 1260,
			"attackDamage": 42,
			"abilityPower": 76,
			"armor": 40,
			"magicResistance": 38,
			"moveSpeed": 74,
			"attackSpeed": 0.58,
			"attackRange": 58,
			"bodyRadius": 23,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05
		},
		"preferredRange": 58,
		"behavior": {
			"aggression": 0.42,
			"survival": 0.82,
			"focusLowHealth": 0.33,
			"focusHighThreat": 0.84,
			"protectAllies": 0.76,
			"preferBackline": 0.5,
			"preferCluster": 0.96,
			"riskTolerance": 0.4,
			"flank": 0.2,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "이동 경로를 닫아 재생의 숲을 만들고 나무·꽃·뿌리로 아군의 전투 공간을 설계한다."
		},
		"doctrine": {
			"title": "세계수 · 독립 교리",
			"code": "WORLD_TREE_NEXUS",
			"roles": [
				"MAIN_TANK",
				"PRIMARY_ENGAGE",
				"FRONT_GUARD"
			],
			"identity": "이동 경로를 닫아 재생의 숲을 만들고 나무·꽃·뿌리로 아군의 전투 공간을 설계한다."
		},
		"nexus": {
			"title": "폐곡선 생태 거점",
			"role": "ANCHOR",
			"risk": 0.25,
			"teamwork": 1,
			"gamble": 0.24,
			"information": 0.79,
			"combo": [
				1,
				4,
				2,
				3
			],
			"skills": [
				"아군 체류선에 파괴 가능한 나무 분산",
				"자기 다각형 안 적에게만 속박 예약",
				"제어된 재생영역에 가시를 겹침",
				"부상 아군의 이동선에 소비 꽃 배치"
			],
			"identity": "보행으로 실제 폐곡선을 만들고 면적 대비 치유 예산을 최적화한다."
		},
		"passives": [
			{
				"name": "생명의 폐곡선",
				"description": "걸어간 경로에 24마다 씨앗을 남기고, 경로가 닫히면(면적 900~90,000) 그 안이 14초간 재생영역이 됩니다. 안의 아군 영웅은 초당 420000÷면적(최대 58)만큼 회복하며(자신은 45%) 영역당 총량은 480+1.6AP입니다. 최대 3개(초과 시 오래된 것 제거)이고 세계수가 쓰러지면 사라지며, 점멸·돌진은 경로를 끊습니다.",
				"rules": [
					{
						"name": "생명의 폐곡선",
						"type": "nexus_seed_path",
						"description": "걸어간 경로에 24마다 씨앗을 남기고, 경로가 닫히면(면적 900~90,000) 그 안이 14초간 재생영역이 됩니다. 안의 아군 영웅은 초당 420000÷면적(최대 58)만큼 회복하며(자신은 45%) 영역당 총량은 480+1.6AP입니다. 최대 3개(초과 시 오래된 것 제거)이고 세계수가 쓰러지면 사라지며, 점멸·돌진은 경로를 끊습니다.",
						"seedDistance": 24,
						"minArea": 900,
						"maxArea": 90000,
						"duration": 14,
						"maxZones": 3,
						"budgetBase": 480,
						"budgetAp": 1.6,
						"rateArea": 420000,
						"rateCap": 58,
						"selfHealingRatio": 0.45
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "수호수 식재",
				"description": "나무(체력 560+1.0AP, 방어·마저 32)를 18초간 심습니다. 1초마다 반경 125 안 아군 영웅을 14+0.12AP 회복시킵니다(자신은 45%). 최대 2그루(초과 시 오래된 나무 제거)이며, 기절하면 치유를 멈추고 세계수가 쓰러지면 사라집니다.",
				"cooldown": 16,
				"castTime": 0.28,
				"recovery": 0.2,
				"range": 230,
				"target": "position_ally",
				"delivery": "area",
				"shape": "single",
				"radius": 125,
				"width": 24,
				"angle": 1.319469,
				"speed": 460,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "summon",
						"count": 1,
						"duration": 18,
						"interval": 1,
						"attack": {
							"type": "damage",
							"school": "magic",
							"base": 0,
							"ad": 0,
							"ap": 0
						}
					},
					{
						"type": "heal",
						"base": 14,
						"ap": 0.12
					}
				],
				"condition": null,
				"ai": {
					"intent": "heal",
					"weight": 1.3
				},
				"tags": [
					"HEALING",
					"SUMMONER"
				],
				"action": "plantTree",
				"vfx": {
					"color": "#76ddb0",
					"pattern": "nova",
					"glyph": "1"
				},
				"geometry": "",
				"timing": "16 / 0.28"
			},
			{
				"slot": 2,
				"name": "뿌리의 경계",
				"description": "내 재생영역 안의 모든 적(소환물 포함)을 1.5초 속박합니다. 영역이 겹쳐도 한 번만 적용되며, 재생영역이 없으면 쓸 수 없습니다.",
				"cooldown": 12,
				"castTime": 0.28,
				"recovery": 0.2,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 70,
				"width": 24,
				"angle": 1.319469,
				"speed": 460,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "status",
						"status": "root",
						"duration": 1.5,
						"magnitude": 0
					}
				],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.3
				},
				"tags": [
					"CONTROL"
				],
				"action": "rootGarden",
				"vfx": {
					"color": "#76ddb0",
					"pattern": "nova",
					"glyph": "2"
				},
				"geometry": "",
				"timing": "12 / 0.28"
			},
			{
				"slot": 3,
				"name": "가시의 계절",
				"description": "4초 동안 내 모든 재생영역이 가시숲이 되어 0.65초마다 안의 적에게 16+0.18AP 마법 피해를 줍니다(겹쳐도 1회). 재생영역이 없으면 쓸 수 없습니다.",
				"cooldown": 15,
				"castTime": 0.28,
				"recovery": 0.2,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 70,
				"width": 24,
				"angle": 1.319469,
				"speed": 460,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "zone",
						"radius": 100,
						"duration": 4,
						"interval": 0.65,
						"effects": [
							{
								"type": "damage",
								"school": "magic",
								"base": 16,
								"ad": 0,
								"ap": 0.18
							}
						]
					}
				],
				"condition": null,
				"ai": {
					"intent": "damage",
					"weight": 1,
					"cluster": 0.5,
					"combo": 0.5,
					"survival": 0.4
				},
				"tags": [
					"AREA_DAMAGE"
				],
				"action": "thornGarden",
				"vfx": {
					"color": "#76ddb0",
					"pattern": "nova",
					"glyph": "3"
				},
				"geometry": "",
				"timing": "15 / 0.28"
			},
			{
				"slot": 4,
				"name": "봄의 선물",
				"description": "지정 위치 주변에 꽃 3송이를 12초간 심습니다. 다친 아군 영웅이 꽃(반경 18)에 닿으면 꽃 하나가 사라지며 45+0.35AP 회복합니다(자신은 45%). 최대 6송이(초과 시 오래된 꽃 제거)입니다.",
				"cooldown": 10,
				"castTime": 0.28,
				"recovery": 0.2,
				"range": 240,
				"target": "position_ally",
				"delivery": "area",
				"shape": "single",
				"radius": 45,
				"width": 24,
				"angle": 1.319469,
				"speed": 460,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "heal",
						"base": 45,
						"ap": 0.35
					}
				],
				"condition": null,
				"ai": {
					"intent": "heal",
					"weight": 1.2
				},
				"tags": [
					"HEALING"
				],
				"action": "plantFlowers",
				"vfx": {
					"color": "#76ddb0",
					"pattern": "nova",
					"glyph": "4"
				},
				"geometry": "꽃 3송이",
				"timing": "10 / 0.28"
			}
		]
	}, 
	{
		"id": "torturer",
		"name": "고문가",
		"glyph": "鎖",
		"accent": "#e789ba",
		"role": "CONTROL",
		"tags": [
			"RANGED",
			"CONTROL",
			"DAMAGE_OVER_TIME",
			"INFORMATION",
			"SINGLE_TARGET"
		],
		"summary": "평타와 채찍으로 고통을 유지하고 재갈·원통형 감금·정보 취득을 팀의 공격에 연결한다.",
		"stats": {
			"maxHealth": 900,
			"attackDamage": 70,
			"abilityPower": 40,
			"armor": 23,
			"magicResistance": 24,
			"moveSpeed": 102,
			"attackSpeed": 0.82,
			"attackRange": 155,
			"bodyRadius": 16,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05
		},
		"preferredRange": 155,
		"behavior": {
			"aggression": 0.62,
			"survival": 0.59,
			"focusLowHealth": 0.65,
			"focusHighThreat": 0.62,
			"protectAllies": 0.57,
			"preferBackline": 0.5,
			"preferCluster": 0.54,
			"riskTolerance": 0.45,
			"flank": 0.55,
			"minimumCommitTime": 0.55,
			"switchThreshold": 0.12,
			"label": "고통 유지·감금 연계형"
		},
		"doctrine": {
			"title": "고통 유지와 정보 심문",
			"code": "TORTURER_122",
			"roles": [
				"DISRUPTOR",
				"SETUP",
				"INFORMATION"
			],
			"identity": "평타와 채찍으로 고통을 유지하고 재갈·원통형 감금·정보 취득을 팀의 공격에 연결한다."
		},
		"nexus": {
			"title": "고통·재갈·감금·심문",
			"role": "PICK",
			"risk": 0.55,
			"teamwork": 0.85,
			"gamble": 0.42,
			"information": 0.9,
			"combo": [
				1,
				2,
				3,
				4
			],
			"skills": [
				"채찍 외연으로 고통 2스택",
				"자신의 고통 3 이상 대상 침묵",
				"아군 추격권을 열도록 근거리 감금",
				"감금된 적의 필요한 정보 한 가지만 취득"
			],
			"identity": "평타와 채찍으로 고통을 유지하고 재갈·원통형 감금·정보 취득을 팀의 공격에 연결한다."
		},
		"passives": [
			{
				"name": "고통",
				"description": "평타 적중 시 고통 1, 가시 채찍질 안쪽 1·외곽 2를 쌓습니다(고문가마다 최대 6, 마지막 부여 5초 뒤 모두 사라짐). 1초마다 스택당 2+0.035AD 물리 피해를 주고 이동 속도를 4%씩 늦춥니다(최대 −24%, 다른 둔화와 따로 곱해짐). 저지 불가·관조 중에는 둔화가 무시됩니다.",
				"rules": [
					{
						"type": "pain_stacks",
						"maxStacks": 6,
						"duration": 5,
						"slowPerStack": 0.04,
						"tick": 1
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "가시 채찍질",
				"action": "whip",
				"description": "조준 방향으로 90° 부채꼴 채찍을 휘두릅니다. 안쪽 적은 38+0.45AD 물리 피해와 고통 1, 외곽(165~220) 적은 66+0.75AD 물리 피해와 고통 2를 받습니다. 시전 0.3초 동안 피할 수 있으며 벽 뒤는 맞지 않습니다.",
				"cooldown": 6.5,
				"castTime": 0.3,
				"recovery": 0.18,
				"range": 220,
				"target": "enemy",
				"delivery": "cone",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [
					{
						"type": "damage",
						"school": "physical",
						"base": 38,
						"ad": 0.45
					}
				],
				"condition": null,
				"ai": {
					"intent": "damage",
					"weight": 1.05,
					"cluster": 0.6,
					"combo": 0.7
				},
				"tags": [
					"CONTROL"
				],
				"vfx": {
					"color": "#e789ba",
					"pattern": "nova",
					"glyph": "1"
				},
				"geometry": "부채꼴 90°, 외곽 165~220",
				"timing": "6.5 / 0.30"
			},
			{
				"slot": 2,
				"name": "재갈 물리기",
				"action": "gag",
				"description": "내 고통 3스택 이상인 적 영웅을 2.1초 침묵시킵니다(스킬 불가, 이동·평타 가능). 강인함으로 줄어들고 군중 제어 면역에 막힙니다.",
				"cooldown": 10,
				"castTime": 0.22,
				"recovery": 0.18,
				"range": 235,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [
					{
						"type": "status",
						"status": "silence",
						"duration": 2.1
					}
				],
				"condition": {
					"targetStatus": "pain",
					"owned": true,
					"minPain": 3
				},
				"ai": {
					"intent": "control",
					"weight": 1.4,
					"combo": 0.9
				},
				"tags": [
					"CONTROL"
				],
				"vfx": {
					"color": "#e789ba",
					"pattern": "nova",
					"glyph": "2"
				},
				"geometry": "",
				"timing": "10 / 0.22"
			},
			{
				"slot": 3,
				"name": "감금",
				"action": "prison",
				"description": "가까운 적을 중심으로 반경 64의 원통 벽을 3.5초 세웁니다. 생성 순간 안에 있던 유닛은 나갈 수 없고 밖의 유닛은 들어올 수 없습니다(돌진·순간이동 포함). 대상은 감금되어 방어력이 25% 줄어듭니다. 시전자나 대상이 쓰러지면 풀립니다.",
				"cooldown": 17,
				"castTime": 0.32,
				"recovery": 0.18,
				"range": 110,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [],
				"condition": null,
				"ai": {
					"intent": "control",
					"weight": 1.3,
					"combo": 0.8
				},
				"tags": [
					"CONTROL"
				],
				"vfx": {
					"color": "#e789ba",
					"pattern": "nova",
					"glyph": "3"
				},
				"geometry": "원통 반경 64",
				"timing": "17 / 0.32"
			},
			{
				"slot": 4,
				"name": "정보 캐기",
				"action": "interrogate",
				"description": "내 감금에 갇힌 적에게만 씁니다. 위치·스킬 재사용 대기시간·남은 체력 중 하나를 골라 5초간 팀에 공개합니다. 대상 팀에 관조 중인 정치가가 있으면 막힙니다.",
				"cooldown": 8,
				"castTime": 0.22,
				"recovery": 0.18,
				"range": 320,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [],
				"condition": {
					"targetStatus": "imprisoned",
					"owned": true
				},
				"ai": {
					"intent": "information",
					"weight": 1.0,
					"combo": 0.5
				},
				"tags": [
					"INFORMATION"
				],
				"vfx": {
					"color": "#e789ba",
					"pattern": "nova",
					"glyph": "4"
				},
				"geometry": "",
				"timing": "8 / 0.22"
			}
		]
	}, 
	{
		"id": "engineer", 
		"name": "엔지니어", 
		"glyph": "工", 
		"accent": "#79cbed", 
		"role": "CONTROL", 
		"tags": ["RANGED", "SUMMONER", "AREA_DAMAGE", "CONTROL"], 
		"summary": "파괴 가능한 3단계 포탑으로 사선을 구축하고 파괴·폭파·재건을 순환한다.", 
		"stats": {
			"maxHealth": 980, 
			"attackDamage": 64, 
			"abilityPower": 74, 
			"armor": 20, 
			"magicResistance": 22, 
			"moveSpeed": 80, 
			"attackSpeed": 0.64, 
			"attackRange": 235, 
			"bodyRadius": 17, 
			"critChance": 0.08, 
			"critMultiplier": 1.65, 
			"tenacity": 0.05
		}, 
		"preferredRange": 220, 
		"behavior": {
			"aggression": 0.42, 
			"survival": 0.82, 
			"focusLowHealth": 0.74, 
			"focusHighThreat": 0.84, 
			"protectAllies": 0.2, 
			"preferBackline": 1, 
			"preferCluster": 0.3, 
			"riskTolerance": 0.12, 
			"flank": 0.25, 
			"minimumCommitTime": 0.55, 
			"switchThreshold": 0.12, 
			"label": "파괴 가능한 3단계 포탑으로 사선을 구축하고 파괴·폭파·재건을 순환한다."
		}, 
		"doctrine": {
			"title": "엔지니어 · 독립 교리", 
			"code": "ENGINEER_NEXUS", 
			"roles": ["PRIMARY_CARRY", "MARKSMAN", "BACKLINE_ANCHOR"], 
			"identity": "파괴 가능한 3단계 포탑으로 사선을 구축하고 파괴·폭파·재건을 순환한다."
		}, 
		"nexus": {
			"title": "삼단 화망 재건", 
			"role": "CONTROL", 
			"risk": 0.31, 
			"teamwork": 0.92, 
			"gamble": 0.46, 
			"information": 0.9, 
			"combo": [1, 4, 3, 2], 
			"skills": ["아군 퇴로에 서로 겹치는 포탑 사선 구축", "즉시 폭파 이익과 잔여 포탑 화력 비교", "적 뒤 실제 벽에 드라이버 각도 정렬", "가까운 저단계 포탑을 3단계까지 개조"], 
			"identity": "설치·강화·벽 고정·폭파를 순환하며 파괴 손실을 재건 속도로 환원한다."
		}, 
		"passives": [
			{
				"name": "재건의 집념", 
				"description": "포탑이 적에게 파괴되거나 비상 철거로 폭파되면 빡침을 1 얻습니다(최대 6, 줄지 않음). 스택당 자동화 전초기지 재사용 대기시간 −0.8초(최소 7.2초)이며 남은 대기시간도 0.8초 줄어듭니다. 시간이 다 되거나 개수 초과로 교체된 포탑은 제외됩니다.", 
				"rules": [
					{
						"name": "재건의 집념", 
						"type": "nexus_workshop", 
						"description": "포탑이 적에게 파괴되거나 비상 철거로 폭파되면 빡침을 1 얻습니다(최대 6, 줄지 않음). 스택당 자동화 전초기지 재사용 대기시간 −0.8초(최소 7.2초)이며 남은 대기시간도 0.8초 줄어듭니다. 시간이 다 되거나 개수 초과로 교체된 포탑은 제외됩니다.", 
						"maxStacks": 6, 
						"secondsPerStack": 0.8, 
						"minCooldown": 7.2
					}
				]
			}
		], 
		"abilities": [
			{
				"slot": 1, 
				"name": "자동화 전초기지", 
				"description": "포탑(체력 260+0.6AP, 방어·마저 20)을 22초간 설치합니다(최대 3개, 초과 시 오래된 것 제거). 1.1초 준비 후 사거리 235 안의 보이는 가장 가까운 적에게 0.9초마다 20+0.25AD+0.25AP 물리 탄을 쏩니다. 기절하면 멈추고 엔지니어가 쓰러지면 사라집니다.", 
				"cooldown": 12, 
				"castTime": 0.28, 
				"recovery": 0.2, 
				"range": 210, 
				"target": "position_ally", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 24, 
				"width": 24, 
				"angle": 1.319469, 
				"speed": 460, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{
						"type": "summon", 
						"count": 1, 
						"duration": 22, 
						"interval": 0.9, 
						"attack": {"type": "damage", "school": "physical", "base": 20, "ad": 0.25, "ap": 0.25}
					}
				], 
				"condition": null, 
				"ai": {"intent": "summon", "weight": 1.2}, 
				"tags": ["SUMMONER"], 
				"action": "turret", 
				"vfx": {"color": "#79cbed", "pattern": "nova", "glyph": "1"}, 
				"geometry": "", 
				"timing": "12 / 0.28", 
				"flags": {"armingTime": 1.1}
			}, 
			{
				"slot": 2, 
				"name": "비상 철거", 
				"description": "내 주변 420 안의 포탑 중 지정 위치에 가장 가까운 것을 폭파합니다. 반경 115의 적에게 (90+0.4AD+0.65AP)×단계 배율(1/1.25/1.5) 마법 피해를 주고 빡침을 1 얻습니다. 포탑이 없으면 쓸 수 없습니다.", 
				"cooldown": 12, 
				"castTime": 0.28, 
				"recovery": 0.2, 
				"range": 420, 
				"target": "position", 
				"delivery": "area", 
				"shape": "single", 
				"radius": 115, 
				"width": 24, 
				"angle": 1.319469, 
				"speed": 460, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "damage", "school": "magic", "base": 90, "ad": 0.4, "ap": 0.65}], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1, "cluster": 0.5, "combo": 0.5, "survival": 0.4}, 
				"tags": ["AREA_DAMAGE"], 
				"action": "detonate", 
				"vfx": {"color": "#79cbed", "pattern": "nova", "glyph": "2"}, 
				"geometry": "폭발 반경 115", 
				"timing": "12 / 0.28"
			}, 
			{
				"slot": 3, 
				"name": "관통 드라이버", 
				"description": "직선 탄이 최대 2명에게 50+0.55AD+0.25AP 물리 피해를 주고 엔지니어 반대쪽으로 95 넉백합니다. 밀려나는 경로가 벽에 막히면 기절 1.1초에 빠집니다.", 
				"cooldown": 9, 
				"castTime": 0.28, 
				"recovery": 0.2, 
				"range": 280, 
				"target": "enemy", 
				"delivery": "projectile", 
				"shape": "single", 
				"radius": 70, 
				"width": 22, 
				"angle": 1.319469, 
				"speed": 540, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 1, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [
					{"type": "damage", "school": "physical", "base": 50, "ad": 0.55, "ap": 0.25}, 
					{"type": "displace", "mode": "knockback", "distance": 95}
				], 
				"condition": null, 
				"ai": {"intent": "damage", "weight": 1, "cluster": 0.5, "combo": 0.5, "survival": 0.4}, 
				"tags": ["CONTROL"], 
				"action": "driver", 
				"vfx": {"color": "#79cbed", "pattern": "nova", "glyph": "3"}, 
				"geometry": "폭 22, 속도 540", 
				"timing": "9 / 0.28"
			}, 
			{
				"slot": 4, 
				"name": "현장 개조", 
				"description": "주변 100 안의 내 포탑 중 단계가 가장 낮은 포탑을 1단계 강화합니다(최대 3단계). 단계당 포탑 피해 +30%, 사거리 +40, 최대·현재 체력 +90입니다. 강화할 포탑이 없으면 쓸 수 없습니다.", 
				"cooldown": 8, 
				"castTime": 0.28, 
				"recovery": 0.2, 
				"range": 100, 
				"target": "self", 
				"delivery": "self", 
				"shape": "single", 
				"radius": 70, 
				"width": 24, 
				"angle": 1.319469, 
				"speed": 460, 
				"projectileCount": 1, 
				"spread": 0, 
				"pierce": 0, 
				"bounces": 0, 
				"homing": false, 
				"returnToSource": false, 
				"effects": [{"type": "buff", "stat": "attackDamage", "amount": 0.3, "duration": 22}], 
				"condition": null, 
				"ai": {"intent": "buff", "weight": 1.1}, 
				"tags": ["SUMMONER"], 
				"action": "upgrade", 
				"vfx": {"color": "#79cbed", "pattern": "nova", "glyph": "4"}, 
				"geometry": "", 
				"timing": "8 / 0.28"
			}
		], 
		"armingTime": 1.1
	},
	{
		"id": "politician",
		"name": "정치가",
		"glyph": "政",
		"accent": "#d8ba65",
		"role": "SUPPORT",
		"tags": [
			"SUPPORT",
			"CONTROL",
			"INFORMATION",
			"NO_BASIC"
		],
		"summary": "낮은 생존력과 기동력을 감수하고 관조·가짜 정보·도발·선전으로 팀의 판단과 연계를 바꾸는 정보 지원가.",
		"stats": {
			"maxHealth": 760,
			"attackDamage": 24,
			"abilityPower": 92,
			"armor": 14,
			"magicResistance": 18,
			"moveSpeed": 78,
			"attackSpeed": 0,
			"attackRange": 0,
			"bodyRadius": 16,
			"critChance": 0,
			"critMultiplier": 1.5,
			"tenacity": 0
		},
		"preferredRange": 350,
		"behavior": {
			"aggression": 0.25,
			"survival": 0.9,
			"focusLowHealth": 0.35,
			"focusHighThreat": 0.8,
			"protectAllies": 0.95,
			"preferBackline": 1,
			"preferCluster": 0.65,
			"riskTolerance": 0.25,
			"flank": 0.15,
			"minimumCommitTime": 0.75,
			"switchThreshold": 0.15,
			"label": "관조·정보 조작 지원형"
		},
		"doctrine": {
			"title": "관조와 여론전",
			"code": "POLITICIAN_122",
			"roles": [
				"SUPPORT",
				"DISRUPTOR",
				"INFORMATION"
			],
			"identity": "안전한 후방에서 정지해 아군 정보를 보호하고 전열에 화제를 집중시킨다."
		},
		"nexus": {
			"title": "정보 불신과 화제 전환",
			"role": "SUPPORT",
			"risk": 0.32,
			"teamwork": 0.96,
			"gamble": 0.56,
			"information": 1,
			"combo": [
				3,
				1,
				2
			],
			"skills": [
				"안전할 때 정지하여 관조 유지",
				"불신 10 이전에 정보 혼란 활용",
				"견딜 수 있는 아군에게만 화제 전환",
				"교전 시작에 선전 계수 버프 동기화"
			],
			"identity": "가짜 정보·위험 분산·계수 지원을 순환한다."
		},
		"passives": [
			{
				"name": "관조",
				"description": "0.45초 이상 제자리에 있으면 관조 상태가 됩니다. 스킬 계수 +30%(선전 강화), 모든 군중 제어를 즉시 풀고 새 군중 제어·넉백·위치 교환을 무시합니다. 움직이면 풀리며 평타가 없습니다.",
				"rules": [
					{
						"type": "contemplation",
						"stationaryDelay": 0.45,
						"coefficient": 0.3
					},
					{
						"type": "no_basic"
					}
				]
			},
			{
				"name": "언론 통제",
				"description": "관조 중에는 아군 전체에 대한 적의 정보 취득(하이브 마인드의 공유 신경망, 고문가의 정보 캐기)을 막습니다. 직접 보는 시야는 막지 못합니다.",
				"rules": [
					{
						"type": "media_control"
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "가짜 뉴스 뿌리기",
				"action": "fakeNews",
				"description": "5초 동안 적 팀에 아군 전원의 가짜 체력(최대 체력의 ±35%)·재사용 대기시간·위치(100 어긋남)를 보여 줍니다(실제 값은 그대로). 쓸 때마다 적 팀 불신이 1 오르고, 10이 되면 거짓 정보가 모두 풀리고 더는 믿지 않습니다. 불신은 화제 돌리기로만 초기화됩니다.",
				"cooldown": 7,
				"castTime": 0.22,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [],
				"condition": null,
				"ai": {
					"intent": "information",
					"weight": 1.05
				},
				"tags": [
					"INFORMATION"
				],
				"vfx": {
					"color": "#d8ba65",
					"pattern": "nova",
					"glyph": "1"
				},
				"geometry": "",
				"timing": "7 / 0.22"
			},
			{
				"slot": 2,
				"name": "화제 돌리기",
				"action": "diversion",
				"description": "아군 1명을 화제로 지정합니다. 그 아군 주변 450 안에서 우리 팀에 보이는 적 영웅은 1.6초간 도발되어 그 아군만 쫓아가 평타로 공격합니다. 적 팀 불신이 0이 되며 강인함·군중 제어 면역이 적용됩니다.",
				"cooldown": 15,
				"castTime": 0.22,
				"recovery": 0.18,
				"range": 400,
				"target": "ally",
				"delivery": "direct",
				"shape": "single",
				"radius": 64,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [
					{
						"type": "status",
						"status": "taunt",
						"duration": 1.6
					}
				],
				"condition": null,
				"ai": {
					"intent": "protect",
					"weight": 1.1,
					"survival": 0.8
				},
				"tags": [
					"CONTROL"
				],
				"vfx": {
					"color": "#d8ba65",
					"pattern": "nova",
					"glyph": "2"
				},
				"geometry": "도발 반경 450",
				"timing": "15 / 0.22"
			},
			{
				"slot": 3,
				"name": "선전",
				"action": "propaganda",
				"description": "주변 440 안의 아군(자신 포함)에게 5초간 방어력 +(18+0.12AP)%(마법 저항력 제외), 스킬 계수 +(8+0.1AP)%(최대 30%)를 줍니다. 관조 중이면 주문력 몫이 30% 커지고, 여러 선전은 가장 강한 것만 적용됩니다.",
				"cooldown": 12,
				"castTime": 0.22,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 440,
				"width": 24,
				"angle": 1.5707963,
				"speed": 460,
				"effects": [
					{
						"type": "buff",
						"stat": "armor",
						"amount": 0.29,
						"duration": 5
					},
					{
						"type": "buff",
						"stat": "abilityCoefficient",
						"amount": 0.17,
						"duration": 5
					}
				],
				"condition": null,
				"ai": {
					"intent": "buff",
					"weight": 1.2,
					"cluster": 0.7
				},
				"tags": [
					"CONTROL"
				],
				"vfx": {
					"color": "#d8ba65",
					"pattern": "nova",
					"glyph": "3"
				},
				"geometry": "반경 440",
				"timing": "12 / 0.22"
			}
		]
	},
	{
		"id": "hades",
		"name": "하데스",
		"glyph": "冥",
		"accent": "#8f7cff",
		"role": "FRONTLINE",
		"tags": ["MELEE", "SUMMONER", "ENGAGE", "AREA_DAMAGE", "SUSTAINED_DAMAGE"],
		"summary": "시야에서 사라지면 몸을 회복하고 망자를 불러내는 명계의 왕. 케르베로스와 함께 전열을 붙잡고, 쓰러지기 직전의 적에게서 회복을 빼앗는다.",
		"stats": {
			"maxHealth": 1220,
			"attackDamage": 68,
			"abilityPower": 24,
			"armor": 35,
			"magicResistance": 32,
			"moveSpeed": 82,
			"attackSpeed": 0.68,
			"attackRange": 62,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 19
		},
		"preferredRange": 60,
		"behavior": {
			"aggression": 0.6,
			"survival": 0.72,
			"focusLowHealth": 0.62,
			"focusHighThreat": 0.6,
			"protectAllies": 0.55,
			"preferBackline": 0.4,
			"preferCluster": 0.74,
			"riskTolerance": 0.52,
			"flank": 0.45,
			"minimumCommitTime": 0.6,
			"switchThreshold": 0.14,
			"label": "은신 매복 전열형"
		},
		"doctrine": {
			"title": "명계 매복 전선",
			"code": "UNDERWORLD AMBUSH",
			"roles": ["MAIN_TANK", "AMBUSHER", "ANTI_HEAL"],
			"identity": "시야를 끊어 회복하고 망자 포위로 교전을 여는 명계의 전열."
		},
		"nexus": {
			"title": "은신 회복·망자 포위",
			"role": "ANCHOR",
			"risk": 0.5,
			"teamwork": 0.78,
			"gamble": 0.42,
			"information": 0.64,
			"combo": [1, 3, 2],
			"skills": ["은신 상태에서 망자 포위로 교전 선제", "주변 적 수와 남은 틱으로 영혼 수확 시점 계산", "15% 근처 적과 회복 보유 팀에 회복 불가 마무리", "케르베로스를 공격 명령 대상에 붙임"],
			"identity": "시야를 끊어 회복하고, 망자와 케르베로스로 적을 묶어 전열을 유지한다."
		},
		"passives": [
			{
				"name": "키네에",
				"description": "은신 상태(투명, 수풀 안, 또는 우리 팀이 보고 있는 적 중 나를 관측하는 적이 없음)이고 마지막으로 피해를 받은 지 1초가 지나면 초당 최대 체력의 2%를 회복합니다. 회복이므로 치유 감소와 회복 불가가 적용됩니다.",
				"rules": [
					{"type": "concealed_regen", "perSecondRatio": 0.02, "delay": 1.0}
				]
			},
			{
				"name": "케르베로스",
				"description": "머리 셋 달린 개 케르베로스(체력 420, 방어·마저 30, 이동 속도는 110과 내 이동 속도 1.2배 중 큰 값)가 늘 곁을 따릅니다. 1초마다 14+0.22AD 물리 피해로 무는데, 내가 공격 명령을 내린 적(나와 280 이내)을 먼저 노리고, 없으면 나와 160 이내에서 가장 가까운 적을 뭅니다. 적이 없거나 나와 150보다 멀어지면 내 뒤 40 거리로 돌아옵니다. 쓰러지면 15초 뒤 다시 나타나고 내가 쓰러지면 함께 사라집니다. 케르베로스의 공격은 내 은신을 깨지 않습니다.",
				"rules": [
					{
						"type": "companion",
						"kind": "cerberus",
						"hp": 420,
						"armor": 30,
						"radius": 14,
						"speedMin": 110,
						"speedRatio": 1.2,
						"attack": {"type": "damage", "school": "physical", "base": 14, "ad": 0.22, "ap": 0},
						"interval": 1.0,
						"reach": 10,
						"commandRange": 280,
						"guardRange": 160,
						"leash": 150,
						"followOffset": 40,
						"respawn": 15
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "망자 소환",
				"description": "은신 상태에서만 시작할 수 있습니다. 내 주위에 원형으로 망자 5기를 7초간 불러냅니다. 망자(체력 110+내 최대 체력 5%, 방어·마저 15)는 대열의 자기 자리를 지키며 24 거리 안의 적만 1초마다 8+0.12AD 마법 피해로 물고 추격하지 않습니다. 망자의 몸은 적의 투사체를 막고, 망자의 공격은 내 은신을 깨지 않습니다.",
				"cooldown": 18,
				"castTime": 0.35,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "summon",
						"originEntity": "shade",
						"originFormation": "ring",
						"originMode": "escort",
						"count": 5,
						"duration": 7,
						"hp": 110,
						"hpAp": 0,
						"hpSelfMaxHp": 0.05,
						"armor": 15,
						"radius": 10,
						"ringPadding": 30,
						"reach": 24,
						"speedBonus": 60,
						"attack": {"type": "damage", "school": "magic", "base": 8, "ad": 0.12, "ap": 0},
						"interval": 1.0,
						"glyph": "亡"
					}
				],
				"condition": {"concealed": true},
				"ai": {"intent": "summon", "weight": 1.05, "cluster": 0.6, "survival": 0, "combo": 0},
				"tags": ["SUMMONER", "ENGAGE"],
				"action": "",
				"vfx": {"color": "#a99cff", "pattern": "shadeSpawn", "glyph": "亡"},
				"geometry": "자신 주위 원형 5기",
				"timing": "18 / 0.35"
			},
			{
				"slot": 2,
				"name": "명계 위반",
				"description": "전방 부채꼴(반경 115, 100°)의 적에게 58+0.7AD 물리 피해를 줍니다. 이 타격 뒤 체력이 15% 미만인 적은 5초간 회복 불가(받는 회복 100% 감소)가 됩니다. 보호막은 막지 않습니다.",
				"cooldown": 9,
				"castTime": 0.3,
				"recovery": 0.18,
				"range": 115,
				"target": "enemy",
				"delivery": "cone",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 1.75,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "damage", "school": "physical", "base": 58, "ad": 0.7, "ap": 0},
					{"type": "status", "status": "healReduction", "magnitude": 1.0, "duration": 5, "whenTargetHpBelow": 0.15}
				],
				"condition": null,
				"ai": {"intent": "damage", "weight": 1.1, "cluster": 0.5, "survival": 0, "combo": 0},
				"tags": ["BURST", "AREA_DAMAGE"],
				"action": "",
				"vfx": {"color": "#7d6bff", "pattern": "underworldCleave", "glyph": "禁"},
				"geometry": "부채꼴 115, 100°",
				"timing": "9 / 0.3"
			},
			{
				"slot": 3,
				"name": "영혼 수확",
				"description": "5초 동안 반경 150 오라를 켭니다. 0.5초마다 오라 안에서 내가 볼 수 있는 적에게 4+0.04AD+최대 체력 0.5% 마법 피해를 주고, 체력에 입힌 피해만큼 임시 최대 체력을 얻습니다(현재 체력도 함께 오르며 기본 최대 체력의 15%까지). 임시 체력은 오라가 끝나고 8초 뒤 사라지며, 그때 최대치를 넘는 체력도 사라집니다.",
				"cooldown": 17,
				"castTime": 0.1,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 150,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "buff",
						"stat": "soulHarvest",
						"amount": 1,
						"duration": 5,
						"radius": 150,
						"interval": 0.5,
						"damage": {"type": "damage", "school": "magic", "base": 4, "ad": 0.04, "ap": 0, "selfMaxHp": 0.005},
						"capRatio": 0.15,
						"linger": 8
					}
				],
				"condition": null,
				"ai": {"intent": "damage", "weight": 1.0, "cluster": 0.8, "survival": 0.4, "combo": 0},
				"tags": ["AREA_DAMAGE", "SUSTAINED_DAMAGE"],
				"action": "",
				"vfx": {"color": "#b4a8ff", "pattern": "soulHarvest", "glyph": "魂"},
				"geometry": "반경 150 오라",
				"timing": "17 / 0.1"
			}
		]
	},
	{
		"id": "war_machine",
		"name": "전쟁 기계",
		"glyph": "機",
		"accent": "#ff8a3d",
		"role": "DAMAGE",
		"tags": ["MELEE", "BURST", "MOBILITY", "AREA_DAMAGE", "SUSTAINED_DAMAGE"],
		"summary": "등에 멘 연료탱크로 평타를 연료로 바꿔 미사일·방어막·폭격을 쓰는 돌격형 근접 딜러. 탱크가 터지면 10초 동안 과열 폭주로 몰아친다.",
		"stats": {
			"maxHealth": 1020,
			"attackDamage": 105,
			"abilityPower": 15,
			"armor": 24,
			"magicResistance": 24,
			"moveSpeed": 116,
			"attackSpeed": 0.92,
			"attackRange": 45,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 18
		},
		"preferredRange": 44,
		"behavior": {
			"aggression": 0.78,
			"survival": 0.5,
			"focusLowHealth": 0.6,
			"focusHighThreat": 0.55,
			"protectAllies": 0.3,
			"preferBackline": 0.25,
			"preferCluster": 0.55,
			"riskTolerance": 0.66,
			"flank": 0.4,
			"minimumCommitTime": 0.5,
			"switchThreshold": 0.12,
			"label": "연료 순환 돌격형"
		},
		"doctrine": {
			"title": "연료 순환 돌격",
			"code": "FUEL CYCLE",
			"roles": ["MELEE_CARRY", "DIVER", "ZONE_DAMAGE"],
			"identity": "평타로 연료를 모아 미사일과 폭격으로 바꾸고, 탱크가 터지면 과열 폭주로 몰아치는 돌격 기계."
		},
		"nexus": {
			"title": "연료 비축·과열 폭주",
			"role": "CARRY",
			"risk": 0.66,
			"teamwork": 0.6,
			"gamble": 0.58,
			"information": 0.45,
			"combo": [1, 2, 4, 3],
			"skills": ["짧은 부스터로 접근과 회피", "제노사이드 비축분을 뺀 연료로 미사일 충전", "받는 피해가 몰릴 때 아크 프로텍터", "연료 7 이상에서 직선 폭격으로 전선 차단"],
			"identity": "평타로 연료 0~10을 채워 스킬로 순환하고, 탱크가 터지면 평타로 올인한다."
		},
		"passives": [
			{
				"name": "연료탱크",
				"description": "등 뒤에 연료탱크(체력 300, 방어·마저 40)를 메고 다닙니다. 적 영웅이나 소환물(구조물 제외)을 평타로 맞힐 때마다 연료 2를 얻습니다(최대 10, 탱크가 있을 때만, 스킬·장판 피해로는 얻지 않음). 탱크는 뒤에서 오는 투사체를 먼저 맞고 광역·장판·부채꼴 피해는 50%만 받습니다. 탱크가 파괴되면 연료가 0이 되고 10초간 과열 폭주(공격 속도·이동 속도 1.5배, S1만 사용 가능, S1은 연료 소모 없음) 상태가 되며, 10초 뒤 탱크가 다시 생깁니다.",
				"rules": [
					{
						"type": "fuel_tank",
						"resourceKey": "fuel",
						"max": 10,
						"perBasic": 2,
						"tankHp": 300,
						"tankArmor": 40,
						"tankRadius": 10,
						"areaTakenRatio": 0.5,
						"overdrive": 10,
						"overdriveMult": 1.5,
						"respawn": 10
					}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "부스터",
				"description": "조준 방향으로 110 거리를 빠르게 돌진합니다(속도 700). 연료 1을 소모하며, 과열 폭주 중에는 연료 없이 쓸 수 있습니다.",
				"cooldown": 2.5,
				"castTime": 0.05,
				"recovery": 0.1,
				"range": 110,
				"target": "position",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 700,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "move_self", "mode": "dash", "distance": 110, "speed": 700},
					{"type": "consume_resource", "key": "fuel", "amount": 1}
				],
				"condition": {"selfResource": {"key": "fuel", "min": 1, "originFreeInOverdrive": true}},
				"ai": {"intent": "mobility", "weight": 0.8, "cluster": 0, "survival": 0.5, "combo": 0},
				"tags": ["MOBILITY", "ENGAGE"],
				"action": "",
				"flags": {"originFreeInOverdrive": true},
				"vfx": {"color": "#ffb36b", "pattern": "boosterDash", "glyph": "推"},
				"geometry": "돌진 110, 속도 700",
				"timing": "2.5 / 0.05"
			},
			{
				"slot": 2,
				"name": "유도폭격",
				"description": "연료를 2~6 충전한 만큼 유도 미사일을 쏩니다. 2발은 0.2초, 1발 늘 때마다 0.3초씩 더 충전하며(6발 1.4초) 충전 중에는 이동 속도가 40% 느려집니다. 미사일은 대상을 쫓아가 각각 24+0.3AD 물리 피해를 주고(속도 460, 최대 비행 760), 발마다 연료 1을 씁니다. 충전 중 기절 등으로 취소되면 연료를 쓰지 않습니다.",
				"cooldown": 9,
				"castTime": 0.2,
				"recovery": 0.18,
				"range": 420,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 14,
				"angle": 0.9,
				"speed": 460,
				"projectileCount": 6,
				"spread": 0.3,
				"pierce": 0,
				"bounces": 0,
				"homing": true,
				"returnToSource": false,
				"maxDistance": 760,
				"effects": [
					{"type": "damage", "school": "physical", "base": 24, "ad": 0.3, "ap": 0},
					{"type": "consume_resource", "key": "fuel", "amount": 1, "perProjectile": true}
				],
				"condition": {"selfResource": {"key": "fuel", "min": 2}},
				"ai": {"intent": "damage", "weight": 1.1, "cluster": 0, "survival": 0, "combo": 0},
				"tags": ["BURST", "SINGLE_TARGET"],
				"action": "",
				"flags": {"originCharge": {"min": 2, "max": 6, "base": 0.2, "perStep": 0.3, "slow": 0.4, "resource": "fuel"}},
				"vfx": {"color": "#ff9d4a", "pattern": "missileBarrage", "glyph": "彈"},
				"geometry": "유도 2~6발, 속도 460",
				"timing": "9 / 0.2~1.4"
			},
			{
				"slot": 3,
				"name": "아크 프로텍터",
				"description": "3초 동안 받는 피해가 40% 줄고, 줄어든 뒤 받은 피해의 15%를 보호막(4초)으로 바꿉니다. 이 보호막은 최대 체력의 20%까지 쌓입니다. 연료를 쓰지 않습니다.",
				"cooldown": 15,
				"castTime": 0.05,
				"recovery": 0.12,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "buff", "stat": "damageTaken", "amount": -0.4, "duration": 3},
					{"type": "buff", "stat": "arcConvert", "amount": 0.15, "duration": 3, "shieldDuration": 4, "capRatio": 0.2}
				],
				"condition": null,
				"ai": {"intent": "survival", "weight": 0.95, "cluster": 0, "survival": 1.0, "combo": 0},
				"tags": ["SHIELDING"],
				"action": "",
				"vfx": {"color": "#6fd3ff", "pattern": "arcShield", "glyph": "甲"},
				"geometry": "",
				"timing": "15 / 0.05"
			},
			{
				"slot": 4,
				"name": "제노사이드",
				"description": "연료 7을 소모합니다. 0.6초 동안 전방 직선을 예고한 뒤, 내 앞으로 길이 380, 폭 90의 직사각형 폭격 지대를 4초간 깝니다. 0.5초마다 안의 적에게 12+0.15AD 물리 피해와 둔화 35%(0.6초)를 줍니다.",
				"cooldown": 22,
				"castTime": 0.6,
				"recovery": 0.18,
				"range": 380,
				"target": "position",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 90,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "consume_resource", "key": "fuel", "amount": 7},
					{
						"type": "zone",
						"originRect": true,
						"atSourceOrigin": true,
						"length": 380,
						"width": 90,
						"duration": 4,
						"interval": 0.5,
						"filter": "enemy",
						"effects": [
							{"type": "damage", "school": "physical", "base": 12, "ad": 0.15, "ap": 0},
							{"type": "status", "status": "slow", "duration": 0.6, "magnitude": 0.35}
						]
					}
				],
				"condition": {"selfResource": {"key": "fuel", "min": 7}},
				"ai": {"intent": "damage", "weight": 1.2, "cluster": 1, "survival": 0, "combo": 0},
				"tags": ["AREA_DAMAGE", "DAMAGE_OVER_TIME", "CONTROL"],
				"action": "",
				"flags": {"originTelegraph": "line"},
				"vfx": {"color": "#ff6a2a", "pattern": "genocideStrip", "glyph": "滅"},
				"geometry": "직사각형 380×90",
				"timing": "22 / 0.6"
			}
		]
	},
	{
		"id": "torquemada",
		"name": "토르케마다",
		"glyph": "審",
		"accent": "#e0b04a",
		"role": "SUPPORT",
		"tags": ["MELEE", "SUPPORT", "CONTROL", "PEEL"],
		"summary": "강한 신앙으로 군중 제어를 버티며, 정화의 불과 칙령으로 아군의 제어를 풀고 자신을 묶은 적을 즉시 속박하는 심판관.",
		"stats": {
			"maxHealth": 1140,
			"attackDamage": 62,
			"abilityPower": 30,
			"armor": 41,
			"magicResistance": 40,
			"moveSpeed": 90,
			"attackSpeed": 0.9,
			"attackRange": 56,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.35,
			"bodyRadius": 17
		},
		"preferredRange": 58,
		"behavior": {
			"aggression": 0.4,
			"survival": 0.5,
			"focusLowHealth": 0.4,
			"focusHighThreat": 0.7,
			"protectAllies": 0.92,
			"preferBackline": 0.55,
			"preferCluster": 0.86,
			"riskTolerance": 0.42,
			"flank": 0.12,
			"minimumCommitTime": 0.6,
			"switchThreshold": 0.14,
			"label": "정화 보호 지원형"
		},
		"doctrine": {
			"title": "이단 심판과 정화",
			"code": "INQUISITION",
			"roles": ["SUPPORT", "CLEANSER", "PEEL"],
			"identity": "아군이 받은 제어를 불로 정화하고, 자신을 제어한 적에게 즉결 속박을 돌려주는 심판관."
		},
		"nexus": {
			"title": "정화·보복 속박",
			"role": "SUPPORT",
			"risk": 0.4,
			"teamwork": 0.92,
			"gamble": 0.3,
			"information": 0.55,
			"combo": [1, 3, 2],
			"skills": ["제어당한 아군 중심에 정화의 불", "나를 제어한 적에게 8초 안에 즉결 속박", "아군을 위협하는 가까운 적을 칙령으로 밀쳐냄", "높은 강인함으로 전열 곁에서 버팀"],
			"identity": "아군의 제어 시간을 지우고 제어를 건 적에게 보복한다."
		},
		"passives": [
			{
				"name": "신앙",
				"description": "강인함이 30% 높습니다(기본 5%와 합쳐 35%). 군중 제어 지속 시간이 그만큼 줄어듭니다.",
				"rules": [
					{"type": "faith_tenacity", "amount": 0.3, "total": 0.35}
				]
			},
			{
				"name": "금욕",
				"description": "유혹에 대한 강인함이 50% 더 높습니다. 강인함과 곱으로 적용되어 유혹 지속 시간이 원래의 32.5%(1-0.35에 1-0.5를 곱함)가 됩니다.",
				"rules": [
					{"type": "status_tenacity", "charm": 0.5}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "아우토다페",
				"description": "사거리 240 안의 지점에 반경 90의 정화의 불을 3초간 지핍니다. 0.2초마다 불 안의 아군을 확인해 한 명당 한 번 정화하고 80+1AP만큼 회복시킵니다. 첫 정화와 회복은 즉시 일어납니다. 같은 불 안의 적에게는 처음부터 0.5초마다 20+0.5AP 마법 피해를 줍니다. 내 불은 하나만 유지됩니다. 정화는 모든 군중 제어와 해로운 효과(치유 감소·받는 피해 증가·취약 낙인·혼란·역병·고통·포효), 적이 건 지속 피해와 능력치 감소를 없앱니다.",
				"cooldown": 13,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 240,
				"target": "position_ally",
				"delivery": "area",
				"shape": "single",
				"radius": 90,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "zone", "radius": 90, "duration": 3, "interval": 0.2, "filter": "ally", "oncePerUnit": true, "originSingle": true, "effects": [{"type": "cleanse"}, {"type": "heal", "base": 80, "ad": 0, "ap": 1.0}]},
					{"type": "zone", "radius": 90, "duration": 3, "interval": 0.5, "filter": "enemy", "effects": [{"type": "damage", "school": "magic", "base": 20, "ad": 0, "ap": 0.5}]}
				],
				"condition": null,
				"ai": {"intent": "support", "weight": 1.1, "cluster": 0.6, "survival": 0.3, "combo": 0},
				"tags": ["SUPPORT", "PEEL"],
				"action": "",
				"vfx": {"color": "#ffc65c", "pattern": "autoDaFe", "glyph": "焚"},
				"geometry": "반경 90",
				"timing": "13 / 0.25"
			},
			{
				"slot": 2,
				"name": "형사 절차 지침",
				"description": "지난 8초 안에 나에게 군중 제어(둔화 제외, 넉백·끌어당김 포함)를 건 적에게만 쓸 수 있습니다. 사거리 420 안의 대상에게 50+0.8AD 물리 피해를 주고 즉시 1.25초 속박합니다. 장판·미끼·소환물로 건 제어는 그 주인이 건 것으로 기록됩니다.",
				"cooldown": 9,
				"castTime": 0.05,
				"recovery": 0.15,
				"range": 420,
				"target": "enemy",
				"delivery": "direct",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "damage", "school": "physical", "base": 50, "ad": 0.8, "ap": 0},
					{"type": "status", "status": "root", "duration": 1.25}
				],
				"condition": {"ccSourceWithin": 8.0},
				"ai": {"intent": "control", "weight": 1.15, "cluster": 0, "survival": 0, "combo": 0},
				"tags": ["CONTROL", "SINGLE_TARGET"],
				"action": "",
				"vfx": {"color": "#f0c86a", "pattern": "edictBind", "glyph": "縛"},
				"geometry": "",
				"timing": "9 / 0.05"
			},
			{
				"slot": 3,
				"name": "알람브라 칙령",
				"description": "내 주변 반경 150의 아군을 정화하고 3초간 90+1.5AP 보호막을 줍니다. 적에게는 60+0.8AD 물리 피해를 주고 중심에서 바깥으로 140 밀쳐냅니다(속도 520).",
				"cooldown": 17,
				"castTime": 0.25,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "area",
				"shape": "single",
				"radius": 150,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "cleanse"},
					{"type": "shield", "base": 90, "ad": 0, "ap": 1.5, "duration": 3},
					{"type": "damage", "school": "physical", "base": 60, "ad": 0.8, "ap": 0},
					{"type": "displace", "mode": "knockback", "distance": 140, "speed": 520}
				],
				"condition": null,
				"ai": {"intent": "protect", "weight": 1.1, "cluster": 0.7, "survival": 0.5, "combo": 0},
				"tags": ["PEEL", "SUPPORT", "CONTROL"],
				"action": "",
				"vfx": {"color": "#ffd77a", "pattern": "alhambraEdict", "glyph": "勅"},
				"geometry": "반경 150",
				"timing": "17 / 0.25"
			}
		]
	},
	{
		"id": "achilles",
		"name": "아킬레우스",
		"glyph": "槍",
		"accent": "#c98b3a",
		"role": "FRONTLINE",
		"tags": ["MELEE", "ENGAGE", "CONTROL", "PEEL", "BURST"],
		"summary": "평타에 강한 스틱스의 몸으로 전열을 서며, 꿰뚫는 창·전방 방패·전장의 포효·불사의 전차로 적의 진형을 흔드는 영웅.",
		"stats": {
			"maxHealth": 1220,
			"attackDamage": 70,
			"abilityPower": 15,
			"armor": 48,
			"magicResistance": 40,
			"moveSpeed": 82,
			"attackSpeed": 0.72,
			"attackRange": 62,
			"critChance": 0.08,
			"critMultiplier": 1.65,
			"tenacity": 0.05,
			"bodyRadius": 19
		},
		"preferredRange": 60,
		"behavior": {
			"aggression": 0.66,
			"survival": 0.66,
			"focusLowHealth": 0.5,
			"focusHighThreat": 0.72,
			"protectAllies": 0.62,
			"preferBackline": 0.45,
			"preferCluster": 0.8,
			"riskTolerance": 0.58,
			"flank": 0.25,
			"minimumCommitTime": 0.6,
			"switchThreshold": 0.12,
			"label": "방패 돌파 전열형"
		},
		"doctrine": {
			"title": "불사의 돌파",
			"code": "MYRMIDON BREACH",
			"roles": ["MAIN_TANK", "PRIMARY_ENGAGE", "DISRUPTOR"],
			"identity": "방패로 정면을 막고 포효와 전차로 적 진형을 흩는 전열 영웅."
		},
		"nexus": {
			"title": "정면 차단·진형 붕괴",
			"role": "ANCHOR",
			"risk": 0.6,
			"teamwork": 0.82,
			"gamble": 0.4,
			"information": 0.5,
			"combo": [3, 4, 1, 2],
			"skills": ["직선 관통 창으로 후열 견제", "정면 투사체·돌진을 방패로 차단", "아군 제어가 6초 안에 들어갈 때 포효", "보이는 적이 많을 때 전차로 넉백 순회"],
			"identity": "정면을 막아 전열을 지키고, 포효와 전차로 적의 제어 저항과 진형을 무너뜨린다."
		},
		"passives": [
			{
				"name": "스틱스의 축복",
				"description": "평타로 받는 피해를 계산할 때 방어력이 30% 높아집니다.",
				"rules": [
					{"type": "basic_armor_bonus", "ratio": 0.3}
				]
			}
		],
		"abilities": [
			{
				"slot": 1,
				"name": "펠리온의 창",
				"description": "직선으로 창을 던져 닿는 모든 적에게 75+0.35AD 고정 피해를 줍니다(관통, 폭 30, 속도 1000, 최대 220 거리).",
				"cooldown": 9,
				"castTime": 0.2,
				"recovery": 0.18,
				"range": 210,
				"target": "enemy",
				"delivery": "projectile",
				"shape": "single",
				"radius": 22,
				"width": 30,
				"angle": 0.9,
				"speed": 1000,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 999,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"maxDistance": 220,
				"effects": [
					{"type": "damage", "school": "true", "base": 75, "ad": 0.35, "ap": 0}
				],
				"condition": null,
				"ai": {"intent": "damage", "weight": 1.1, "cluster": 0.4, "survival": 0, "combo": 0},
				"tags": ["BURST"],
				"action": "",
				"vfx": {"color": "#e6b067", "pattern": "peliasSpear", "glyph": "貫"},
				"geometry": "관통, 폭 30, 속도 1000",
				"timing": "9 / 0.2"
			},
			{
				"slot": 2,
				"name": "헤파이스토스의 방패",
				"description": "2초 동안 조준 방향 120° 앞에서 오는 투사체(소멸), 직접 피해, 군중 제어, 넉백을 모두 막습니다. 장판·지속 피해와 옆·뒤에서 오는 공격은 막지 못합니다. 방패를 든 동안 이동 속도가 35% 느려지고 바라보는 방향이 고정됩니다(뒷걸음 가능).",
				"cooldown": 14,
				"castTime": 0.05,
				"recovery": 0.12,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 2.0944,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "front_guard", "duration": 2, "arcDegrees": 120, "moveSlow": 0.35}
				],
				"condition": null,
				"ai": {"intent": "survival", "weight": 1.0, "cluster": 0, "survival": 1.0, "combo": 0},
				"tags": ["PEEL"],
				"action": "",
				"vfx": {"color": "#d9a24f", "pattern": "hephaestusShield", "glyph": "盾"},
				"geometry": "전방 120°",
				"timing": "14 / 0.05"
			},
			{
				"slot": 3,
				"name": "포효",
				"description": "6초 동안 적의 강인함을 10% 낮춥니다. 섬멸·거점 모드는 전장의 모든 적 영웅, 개인전·배틀그라운드는 반경 900 안의 적 영웅에게 겁니다. 포효만은 강인함을 0 아래(최저 -30%)로 내려 군중 제어 지속 시간을 늘릴 수 있습니다. 해로운 효과라 정화되며 무적·대상 지정 불가·저지 불가 상태에는 걸리지 않습니다.",
				"cooldown": 16,
				"castTime": 0.3,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 22,
				"width": 24,
				"angle": 0.9,
				"speed": 420,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{"type": "roar", "duration": 6, "tenacityLoss": 0.1, "radiusFfa": 900}
				],
				"condition": null,
				"ai": {"intent": "debuff", "weight": 0.95, "cluster": 0.5, "survival": 0, "combo": 1},
				"tags": ["CONTROL"],
				"action": "",
				"vfx": {"color": "#f0a548", "pattern": "warRoar", "glyph": "吼"},
				"geometry": "전장 전체(개인전 반경 900)",
				"timing": "16 / 0.3"
			},
			{
				"slot": 4,
				"name": "크산토스와 발리오스",
				"description": "쌍마 전차(반지름 30, 속도 300, 무적·대상 지정 불가)를 5초간 소환합니다. 전차는 우리 팀이 보고 있는 적 영웅 중 넉백을 가장 적게 당한 적(같으면 가장 가까운 적)을 쫓아, 닿으면 30+0.3AD 물리 피해를 주고 130 밀쳐냅니다(속도 600). 같은 적은 1초에 한 번, 최대 2회까지만 밀려나며 개인전·배틀그라운드에서는 나와 900 이내의 적만 노립니다. 모두 2회 밀려나면 남은 시간 동안 멈춰 섭니다.",
				"cooldown": 45,
				"castTime": 0.5,
				"recovery": 0.18,
				"range": 0,
				"target": "self",
				"delivery": "self",
				"shape": "single",
				"radius": 30,
				"width": 24,
				"angle": 0.9,
				"speed": 300,
				"projectileCount": 1,
				"spread": 0,
				"pierce": 0,
				"bounces": 0,
				"homing": false,
				"returnToSource": false,
				"effects": [
					{
						"type": "summon",
						"originEntity": "chariot",
						"originMode": "chariot",
						"count": 1,
						"duration": 5,
						"hp": 1,
						"hpAp": 0,
						"armor": 0,
						"radius": 30,
						"navRadius": 18,
						"speed": 300,
						"attack": {"type": "damage", "school": "physical", "base": 30, "ad": 0.3, "ap": 0},
						"knock": {"distance": 130, "speed": 600},
						"hitInterval": 1.0,
						"maxKnocks": 2,
						"rangeFfa": 900,
						"glyph": "車"
					}
				],
				"condition": null,
				"ai": {"intent": "engage", "weight": 1.2, "cluster": 0.8, "survival": 0, "combo": 0},
				"tags": ["ENGAGE", "CONTROL", "SUMMONER"],
				"action": "",
				"vfx": {"color": "#e8b45a", "pattern": "chariotCharge", "glyph": "車"},
				"geometry": "전차 반지름 30, 속도 300",
				"timing": "45 / 0.5"
			}
		]
	}
]
