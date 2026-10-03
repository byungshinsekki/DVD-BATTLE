class_name BattleScreen
extends Control
## Live battle screen (V1.5.1): arena view, top scoreboard, grouped playback controls and the side
## panel. Side-panel tabs are rebuilt only when their signature changes (tab, selected unit,
## perspective, held items ...); in between, small updater callables refresh the values in place, so
## rows stay clickable, hover styles stay stable and tooltips can open. Colours, StyleBoxes and theme
## overrides are only touched when a value actually changes (UITheme.sbc for shared StyleBoxes).
## Test contract (tests/deathmatch_ui_15, control_ui_13, preview_ui_14): member and method names,
## DM tab titles, and the Labels "이게 나에게 필요한가" / "초째 유지" / "%d킬" inside tab_body.
## V2 battleground mode (DESIGN_V2 §3.8, when sim.is_battleground()): TeamChips on both sides, the
## clock, "생존 N/M · K팀" and the compact ZonePill in the centre, a Minimap at the bottom-right of the
## arena, a 6-line kill feed (▲다운 / ✚소생 / ☠ 탈락 / 자기장), the BrStanding rank tab, a downed /
## revive card in the unit tab and team perspectives (V / Shift+V). Widget data is pushed at most
## every BR_PUSH s and only when it changed (tests/battleground_ui_v2).


const TOP_H: = 78.0
const BOTTOM_H: = 58.0
const PANEL_W: = 392.0
const MID_W: = 252.0
const CHIP_GAP: = 2
const FEED_MAX: = 5
const LOG_KEEP: = 160
const LOG_CAP: = 400
## Buffs lasting longer than this are items or permanent growth ("영구 강화").
const PERMANENT_AFTER: = 900.0

## Every buff key the simulation applies -> Korean label. Keys ending in "Flat" are flat amounts,
## BUFF_FLAGS carry no number, "regen" is HP per second and everything else is a ratio of the base
## stat (see BattleSim.stat / buff_sum).
const BUFF_LABELS: = {
	"attackSpeed": "공격 속도", "moveSpeed": "이동 속도", "attackDamage": "공격력", "abilityPower": "주문력",
	"armor": "방어력", "magicResistance": "마법 저항력", "maxHealth": "최대 체력", "attackRange": "사거리",
	"attackDamageFlat": "공격력", "abilityPowerFlat": "주문력", "armorFlat": "방어력", "magicResistanceFlat": "마법 저항력",
	"maxHealthFlat": "최대 체력", "attackRangeFlat": "사거리", "moveSpeedFlat": "이동 속도", "attackSpeedFlat": "공격 속도",
	"damageDealt": "주는 피해", "damageTaken": "받는 피해", "healingReceived": "받는 회복", "regen": "체력 재생",
	"omnivamp": "모든 피해 흡혈", "basicDamage": "평타 피해", "nextBasicDamage": "다음 평타 피해",
	"projectileDamage": "투사체 피해", "projectileSpeed": "투사체 속도", "projectileGuard": "투사체 방어",
	"abilityCoefficient": "스킬 계수", "attackSpeedByMove": "이동 비례 공격 속도",
	"originStatSwap": "공격력·주문력 뒤바뀜", "originScent": "피냄새 추적", "originPredator": "상위 포식자",
	"originSniperRound": "취약 탄환 장전", "originPirateRound": "약탈 탄환 장전", "originTrajectory": "탄도 전환",
	"contactExplosion": "연쇄 자폭", "orbitPower": "세라프 회전 강화", "originOrbitSpeed": "회전 가속", "originRegenPool": "재생 샘",
	"soulHarvest": "영혼 수확", "arcConvert": "아크 프로텍터",
}
const BUFF_FLAGS: = ["originStatSwap", "originScent", "originPredator", "originSniperRound", "originPirateRound",
	"originTrajectory", "contactExplosion", "originRegenPool", "soulHarvest", "arcConvert"]
## Buffs where a positive amount hurts the holder.
const BUFF_INVERTED: = ["damageTaken"]
const RATIO_STATS: = ["attackSpeed", "moveSpeed", "attackDamage", "abilityPower", "armor", "magicResistance", "maxHealth", "attackRange"]
const BUFF_TIPS: = {
	"damageDealt": "주는 모든 피해가 이 비율만큼 늘거나 줄어듭니다.",
	"damageTaken": "받는 모든 피해가 이 비율만큼 늘거나 줄어듭니다.",
	"healingReceived": "받는 회복량이 이 비율만큼 달라집니다.",
	"regen": "초당 체력 재생량에 더해집니다.",
	"omnivamp": "입힌 모든 피해의 이 비율만큼 체력을 회복합니다. 보호막에 막힌 피해는 제외됩니다.",
	"basicDamage": "평타 피해가 이 비율만큼 늘어납니다.",
	"nextBasicDamage": "다음 평타 한 번의 피해가 이 비율만큼 늘어납니다.",
	"projectileDamage": "투사체로 주는 피해가 이 비율만큼 늘어납니다.",
	"projectileSpeed": "투사체가 이 비율만큼 더 빨리 날아갑니다.",
	"abilityCoefficient": "스킬의 공격력·주문력 계수가 이 비율만큼 커집니다.",
	"attackSpeedByMove": "이동 속도가 빠를수록 공격 속도가 더 오릅니다(상한 있음).",
	"attackRangeFlat": "평타 사거리가 이만큼 늘어납니다.",
	"originStatSwap": "공격력과 주문력이 서로 뒤바뀌어 계산됩니다.",
	"originOrbitSpeed": "궤도 회전 속도가 이 비율만큼 빨라집니다.",
	"soulHarvest": "하데스 주변의 보이는 적에게 주기적으로 피해를 주고, 준 체력 피해만큼 최대 체력이 잠시 늘어납니다.",
	"arcConvert": "받은 피해의 15%를 4초짜리 보호막으로 바꿉니다(최대 체력의 20%까지).",
	"orbitPower": "궤도 공격의 피해가 이 비율만큼 늘어납니다.",
}
## Statuses without a glossary entry (CodexData.STATUS covers the rest).
const STATUS_TIPS: = {
	"spawn_protection": "재출전 보호 — 부활 직후 잠시 보호받습니다. 적대 행동을 하면 풀리며, 보호 중에는 거점을 점령할 수 없습니다.",
	"nexus_seal": "스킬 봉인 — 봉인된 스킬을 쓸 수 없습니다.",
}
const RESOURCE_LABELS: = {"distrust": "상대 불신", "frustration": "좌절"}
## Event log filter categories (event type -> filter id).
## Public map events shown in every perspective (no team observes them first).
const PUBLIC_LOG: = ["CONTROL_CAPTURED", "CONTROL_NEUTRALIZED", "CONTROL_CONTESTED", "CONTROL_SCORE", "DM_KILL",
	"BR_ELIMINATED", "BR_TEAM_OUT", "BR_ZONE_ANNOUNCE", "BR_ZONE_SHRINK"]
const LOG_CATS: = {
	"DM_KILL": "kill", "DEATH": "kill", "EXECUTED": "kill", "RESPAWN_SCHEDULED": "kill", "HERO_RESPAWNED": "kill",
	"DM_REVIVE": "kill", "BATTLE_STARTED": "kill", "BATTLE_ENDED": "kill",
	"HEALTH_DAMAGED": "damage", "HEAL_APPLIED": "damage", "SHIELD_APPLIED": "damage", "ENV_HIT": "damage",
	"DM_ITEM_PICKED": "item", "DM_ITEM_DROPPED": "item", "DM_ITEM_PROC": "item",
	"CONTROL_CAPTURED": "objective", "CONTROL_NEUTRALIZED": "objective", "CONTROL_CONTESTED": "objective", "HEAL_ZONE_USED": "objective",
	"BR_DOWNED": "kill", "BR_REVIVE_START": "kill", "BR_REVIVE_CANCEL": "kill", "BR_REVIVED": "kill", "BR_BLED_OUT": "kill",
	"BR_ELIMINATED": "kill", "BR_TEAM_OUT": "kill", "BR_ITEM_SWAP": "item", "BR_ZONE_ANNOUNCE": "env", "BR_ZONE_SHRINK": "env",
}

var app: App
var runner: BattleRunner
var view: BattleView
var config: Dictionary = {}
var arena_area: Control
var top_bar: PanelContainer
var bottom_bar: PanelContainer
var side: PanelContainer
var side_visible: bool = true
var chips: Array = []
var op_labels: Array = []
var op_chips: Array = []
var chip_boxes: Array = []
var time_l: Label
var sub_l: Label
var score_l: Label
var blue_n: Label
var red_n: Label
var race_bars: Array = []
var mid_box: VBoxContainer
var mid_rows: Array = []
var leader_pill: PanelContainer
var leader_disc: GlyphDisc
var leader_name: Label
var leader_kills: Label
var leader_bar: ProgressBar
var objectives: ControlObjectives
var speed_btns: Array = []
var vision_btns: Array = []
var speed_seg: HBoxContainer
var vision_seg: HBoxContainer
var cam_seg: HBoxContainer
var cam_manual: Control
var pause_btn: Button
var toggles: Dictionary = {}
var perf_l: Label
var panel_btn: Button
var tabs: TabBar
var tab_body: VBoxContainer
var tab_scroll: ScrollContainer
var cur_tab: int = 0
var panel_timer: float = 0.0
var log_rt: RichTextLabel
var log_seen: int = 0
var log_filters: HBoxContainer
var log_filter: String = "all"
var feed_box: VBoxContainer
var feed_seen: int = 0
var banner: Control
var banner_t: float = -1.0
var banner_text: String = ""
var banner_sub: String = ""
var banner_col: Color = Color.WHITE
var ended: bool = false
var end_timer: float = -1.0
var end_result: Dictionary = {}
## "추적" camera segment (kept for older callers; the camera group is cam_seg).
var cam_btn: Button
var dragging: bool = false
# Deathmatch presentation
var dm: bool = false
var team_tags: Array = []
var dm_view_opt: OptionButton
var dm_chips: Array = []
const DM_TABS: = ["순위", "유닛", "이벤트", "AI 판단"]
const TEAM_TABS: = ["유닛", "AI 판단", "이벤트", "기여도"]
# Battleground presentation (V2). br is the mode (null outside the battleground); br_chips holds
# one TeamChip per team (index = team).
var br: BattlegroundMode
var br_chips: Array = []
var zone_pill: ZonePill
var alive_l: Label
var minimap: Minimap
var minimap_btn: Button
var br_standing: BrStanding
var _br_timer: float = 0.0
var _cam_timer: float = 0.0
var _br_keys: Dictionary = {}
## Widget pushes so far (tests check the BR_PUSH throttle).
var br_pushes: int = 0
## Battleground widget refresh period (s): chips, minimap dots, standing (only pushed on change).
const BR_PUSH: = 0.25
const BR_FEED_MAX: = 6
const BR_SQUAD_NAMES: = {1: "솔로", 2: "듀오", 3: "트리오"}
# Pinned selected-unit card
var sel_card: PanelContainer
var sel_disc: GlyphDisc
var sel_name: Label
var sel_side: PanelContainer
var sel_role: PanelContainer
var sel_hp_row: HBoxContainer
var sel_hp: HpBar
var sel_hp_l: Label
var sel_act: Label
var _sel_key: String = ""
# Floating pause / exit-confirm pill
var pause_pill: PanelContainer
var pause_pill_l: Label
var _esc_armed_until: int = -1
# Change trackers (avoid per-frame theme overrides)
var _last_paused: int = -1
var _time_warn: int = -1
var _hud_timer: float = 0.0
var _perf_timer: float = 0.0
var _lead_key: String = ""
var _tag_room: float = 58.0
var _log_lines: int = 0
var _suppress_settings: bool = false
# Side-panel body: signature + in-place updaters
var _body_sig: String = ""
var _updaters: Array = []
var _rank_rows: Array = []


func bind(a: App) -> void :
	app = a


func is_running() -> bool:
	return runner != null and runner.sim != null and not runner.done


func _ready() -> void :
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bgc: = ColorRect.new()
	bgc.color = Color("#05070b")
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)
	runner = BattleRunner.new()
	add_child(runner)
	runner.stepped.connect(_on_stepped)
	runner.finished.connect(_on_finished)
	arena_area = Control.new()
	arena_area.clip_contents = true
	arena_area.mouse_filter = Control.MOUSE_FILTER_STOP
	arena_area.gui_input.connect(_arena_input)
	add_child(arena_area)
	view = BattleView.new()
	arena_area.add_child(view)
	objectives = ControlObjectives.new()
	objectives.visible = false
	arena_area.add_child(objectives)
	feed_box = UITheme.vbox(5)
	feed_box.position = Vector2(14, 12)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_area.add_child(feed_box)
	minimap = Minimap.new()
	minimap.visible = false
	minimap.world_clicked.connect(_on_minimap_clicked)
	arena_area.add_child(minimap)
	banner = Control.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.draw.connect(_draw_banner)
	arena_area.add_child(banner)
	_build_pause_pill()
	_build_top()
	_build_bottom()
	_build_side()
	_layout()
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void :
	# Our own display toggles already set the view flag; skip the full static-layer redraw for them.
	if view and not _suppress_settings:
		view.apply_settings()


func _notification(what: int) -> void :
	if what == NOTIFICATION_RESIZED and arena_area:
		_layout()


func _layout() -> void :
	var sw: = PANEL_W if side_visible else 0.0
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(size.x, TOP_H)
	bottom_bar.position = Vector2(0, size.y - BOTTOM_H)
	bottom_bar.size = Vector2(size.x, BOTTOM_H)
	side.visible = side_visible
	side.position = Vector2(size.x - PANEL_W, TOP_H)
	side.size = Vector2(PANEL_W, size.y - TOP_H - BOTTOM_H)
	arena_area.position = Vector2(0, TOP_H)
	arena_area.size = Vector2(size.x - sw, size.y - TOP_H - BOTTOM_H)
	if objectives:
		objectives.position = Vector2(floorf((arena_area.size.x - ControlObjectives.W) * 0.5), arena_area.size.y - ControlObjectives.H - 12.0)
		objectives.size = Vector2(ControlObjectives.W, ControlObjectives.H)
	if minimap:
		var mm: = minimap.custom_minimum_size
		minimap.size = mm
		minimap.position = Vector2(arena_area.size.x - mm.x - 12.0, arena_area.size.y - mm.y - 12.0)
	if panel_btn:
		panel_btn.text = "패널 숨기기" if side_visible else "패널 보기"
	if view:
		view.fit(Rect2(Vector2(10, 8), arena_area.size - Vector2(20, 16)))


# ================================================================== top bar

func _build_top() -> void :
	var st: = UITheme.sb(Color(UITheme.BG2, 0.98), UITheme.LINE, 0, 0, 10, 6)
	st.border_width_bottom = 1
	top_bar = UITheme.styled_panel(st)
	add_child(top_bar)
	var h: = UITheme.hbox(8)
	top_bar.add_child(h)
	for t in 2:
		var box: = UITheme.hbox(CHIP_GAP)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_BEGIN if t == 0 else BoxContainer.ALIGNMENT_END
		chip_boxes.append(box)
	team_tags.append(_team_tag(0))
	h.add_child(team_tags[0])
	h.add_child(chip_boxes[0])
	h.add_child(_build_mid())
	h.add_child(chip_boxes[1])
	team_tags.append(_team_tag(1))
	h.add_child(team_tags[1])


## Centre block. Its children are re-arranged per ruleset by _arrange_mid (every node stays in the
## tree; unused ones are hidden).
func _build_mid() -> Control:
	mid_box = UITheme.vbox(0)
	mid_box.custom_minimum_size = Vector2(MID_W, 0)
	mid_box.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 2:
		var r: = UITheme.hbox(8 if i == 0 else 6)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		mid_box.add_child(r)
		mid_rows.append(r)
	blue_n = _score_num(UITheme.BLUE)
	red_n = _score_num(UITheme.RED)
	time_l = UITheme.label("0:00", "", 28, UITheme.TEXT)
	time_l.add_theme_font_override("font", DB.font_black)
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_l = UITheme.label("", "FaintLabel", 12)
	score_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_l.mouse_filter = Control.MOUSE_FILTER_PASS
	sub_l = UITheme.label("", "FaintLabel", 12)
	sub_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_l.mouse_filter = Control.MOUSE_FILTER_PASS
	for t in 2:
		# Score race: each team's bar fills toward the target in the middle.
		var bar: = UITheme.progress(0.0, 300.0, UITheme.team_color(t), 8)
		bar.custom_minimum_size.x = 48
		bar.add_theme_stylebox_override("background", UITheme.sbc(Color(UITheme.team_color(t), 0.14), UITheme.CLEAR, UITheme.R_XS, 0, 0, 0))
		if t == 1:
			bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		race_bars.append(bar)
	_build_leader_pill()
	alive_l = UITheme.label("", "BoldLabel", 15, UITheme.TEXT)
	alive_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alive_l.mouse_filter = Control.MOUSE_FILTER_PASS
	zone_pill = ZonePill.new(true)
	zone_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in _mid_nodes():
		(n as Control).visible = false
		(mid_rows[1] as Node).add_child(n)
	return mid_box


## Every node the centre block can show (the battleground adds the survivors label and zone pill).
func _mid_nodes() -> Array:
	return [blue_n, race_bars[0], score_l, race_bars[1], red_n, time_l, leader_pill, sub_l, alive_l, zone_pill]


func _score_num(col: Color) -> Label:
	var l: = UITheme.label("0", "", 24, col)
	l.add_theme_font_override("font", DB.font_black)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _build_leader_pill() -> void:
	leader_pill = PanelContainer.new()
	leader_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leader_pill.mouse_filter = Control.MOUSE_FILTER_PASS
	leader_pill.tooltip_text = UITheme.tip("현재 처치 1위입니다. 목표 처치 수에 먼저 도달하면 우승하고, 시간이 끝나면 처치 순위로 정합니다.")
	var h: = UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap: = UITheme.label("선두", "EyebrowLabel", 12, UITheme.GOLD)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap)
	leader_disc = GlyphDisc.new(null, 24, -1)
	leader_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(leader_disc)
	leader_name = UITheme.label("", "BoldLabel", 14)
	leader_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(leader_name)
	leader_kills = UITheme.label("", "BlackLabel", 15)
	leader_kills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(leader_kills)
	leader_bar = UITheme.progress(0.0, 10.0, UITheme.GOLD, 5)
	leader_bar.custom_minimum_size.x = 56
	leader_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	h.add_child(leader_bar)
	leader_pill.add_child(h)
	leader_pill.add_theme_stylebox_override("panel", UITheme.sbc(Color(UITheme.GOLD, 0.08), Color(UITheme.GOLD, 0.35), UITheme.R_PILL, 1, 12, 4))


func _place(n: Control, row: HBoxContainer, i: int) -> void:
	if n.get_parent() != row:
		n.get_parent().remove_child(n)
		row.add_child(n)
	row.move_child(n, i)
	n.visible = true


## kind: "elim" (survivors flank the clock), "control" (score race is the hero, clock below) or "dm"
## (clock + leader pill).
func _arrange_mid(kind: String) -> void:
	var a: HBoxContainer = mid_rows[0]
	var b: HBoxContainer = mid_rows[1]
	for n in _mid_nodes():
		(n as Control).visible = false
	var ra: Array = []
	var rb: Array = []
	var sep_a: = 8
	match kind:
		"br":
			# Battleground: elapsed time and survivors over the compact zone pill.
			time_l.add_theme_font_size_override("font_size", 24)
			ra = [time_l, alive_l]
			rb = [zone_pill]
			sep_a = 14
		"dm":
			time_l.add_theme_font_size_override("font_size", 26)
			ra = [time_l, leader_pill]
			rb = [sub_l]
			sep_a = 14
		"control":
			time_l.add_theme_font_size_override("font_size", 18)
			ra = [blue_n, race_bars[0], score_l, race_bars[1], red_n]
			rb = [time_l, sub_l]
		_:
			time_l.add_theme_font_size_override("font_size", 28)
			ra = [blue_n, time_l, red_n]
			rb = [score_l, sub_l]
			sep_a = 22
	a.add_theme_constant_override("separation", sep_a)
	for i in ra.size():
		_place(ra[i], a, i)
	for i in rb.size():
		_place(rb[i], b, i)
	# Hidden leftovers live at the end of row B.
	for n in _mid_nodes():
		if not (n as Control).visible and (n as Control).get_parent() != b:
			(n as Control).get_parent().remove_child(n)
			b.add_child(n)


func _team_tag(t: int) -> Control:
	var tc: = UITheme.team_color(t)
	var v: = UITheme.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(58, 0)
	var nl: = UITheme.label(DB.TEAM_NAMES[t], "", 14, tc)
	nl.add_theme_font_override("font", DB.font_black)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if t == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(nl)
	var chip: = PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.sbc(Color(tc, 0.1), Color(tc, 0.35), UITheme.R_PILL, 1, 7, 1))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if t == 0 else Control.SIZE_SHRINK_END
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.visible = false
	var ol: = UITheme.label("", "", 12, tc.lightened(0.4))
	ol.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ol.clip_text = true
	chip.add_child(ol)
	v.add_child(chip)
	op_labels.append(ol)
	op_chips.append(chip)
	return v


func _set_op(t: int, text: String) -> void:
	var ol: Label = op_labels[t]
	if ol.text == text:
		return
	ol.text = text
	var chip: PanelContainer = op_chips[t]
	chip.visible = text != ""
	if text == "":
		return
	var room: = maxf(24.0, _tag_room - 16.0)
	ol.custom_minimum_size.x = minf(DB.font_regular.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 1.0, room)
	chip.tooltip_text = "%s 작전 · %s" % [DB.TEAM_NAMES[t], text]


# ================================================================== bottom bar

func _build_bottom() -> void :
	var st: = UITheme.sb(Color(UITheme.BG2, 0.98), UITheme.LINE, 0, 0, 14, 8)
	st.border_width_top = 1
	bottom_bar = UITheme.styled_panel(st)
	add_child(bottom_bar)
	var h: = UITheme.hbox(14)
	bottom_bar.add_child(h)

	pause_btn = UITheme.button("❚❚", "", _toggle_pause, "일시정지하거나 이어서 봅니다 (Space)")
	pause_btn.custom_minimum_size = Vector2(40, 34)
	speed_seg = UITheme.segmented([[0.5, "0.5×", "0.5배속으로 봅니다 (1)"], [1.0, "1×", "기본 속도로 봅니다 (2)"],
		[2.0, "2×", "2배속으로 봅니다 (3)"], [4.0, "4×", "4배속으로 봅니다 (4)"]], 1.0, func(v): _set_speed(float(v)))
	var sb_btns: Dictionary = speed_seg.get_meta("buttons")
	for id in sb_btns:
		speed_btns.append([float(id), sb_btns[id]])
	h.add_child(_group("재생", [pause_btn, speed_seg]))
	h.add_child(_group_sep())

	vision_seg = UITheme.segmented([[-1, "전체", "관전자 시점: 모든 유닛과 정보를 봅니다. V 키로 시점을 순환합니다."],
		[0, "청 팀", "청 팀 시점: 청 팀이 실제로 본 것과 청 팀 AI의 추정만 표시합니다 (V)"],
		[1, "홍 팀", "홍 팀 시점: 홍 팀이 실제로 본 것과 홍 팀 AI의 추정만 표시합니다 (V)"]], -1, func(v): _set_vision(int(v)))
	var vb_btns: Dictionary = vision_seg.get_meta("buttons")
	for id in vb_btns:
		vision_btns.append([int(id), vb_btns[id]])
		if int(id) < 0:
			(vb_btns[id] as Button).custom_minimum_size.x = 56
	dm_view_opt = OptionButton.new()
	dm_view_opt.focus_mode = Control.FOCUS_NONE
	dm_view_opt.custom_minimum_size = Vector2(176, 34)
	dm_view_opt.clip_text = true
	dm_view_opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dm_view_opt.tooltip_text = UITheme.tip("참가자 시점: 그 참가자가 실제로 본 것과 그 AI가 추정한 적 위치만 표시합니다 (V로 순환)")
	dm_view_opt.item_selected.connect(func(i): _set_vision(i - 1))
	dm_view_opt.visible = false
	h.add_child(_group("시점", [vision_seg, dm_view_opt]))
	h.add_child(_group_sep())

	var shows: Array = []
	for row in [["ai", "AI 의도", "AI 의도: 영웅마다 이동 목표와 현재 판단을 전장에 표시합니다. 설정에 저장됩니다."],
			["tele", "시전 예고", "시전 예고: 스킬이 떨어질 범위를 미리 표시합니다. 설정에 저장됩니다."],
			["names", "이름", "이름: 영웅 이름표를 표시합니다. 설정에 저장됩니다."],
			["nums", "피해 숫자", "피해 숫자: 피해·회복 숫자를 띄웁니다. 설정에 저장됩니다."]]:
		var cb: = UITheme.button(row[1], "ChipButton", Callable(), row[2])
		cb.toggle_mode = true
		cb.custom_minimum_size = Vector2(0, 30)
		var key: String = row[0]
		cb.toggled.connect(func(on): _toggle(key, on))
		toggles[key] = cb
		shows.append(cb)
	minimap_btn = UITheme.button("미니맵", "ChipButton", Callable(), "미니맵: 전장 오른쪽 아래에 자기장과 보이는 영웅을 표시합니다. 누르면 그 위치로 카메라를 옮깁니다 (M).")
	minimap_btn.toggle_mode = true
	minimap_btn.custom_minimum_size = Vector2(0, 30)
	minimap_btn.button_pressed = true
	minimap_btn.visible = false
	minimap_btn.toggled.connect(func(on: bool) -> void:
		if minimap:
			minimap.visible = on and br != null)
	shows.append(minimap_btn)
	var show_row: = UITheme.hbox(4)
	for cb in shows:
		show_row.add_child(cb)
	h.add_child(_group("표시", [show_row]))
	h.add_child(_group_sep())

	cam_seg = UITheme.segmented([["auto", "추적", "추적: 교전이 벌어지는 곳을 자동으로 확대합니다 (C)"],
		["full", "전체", "전체: 전장 전체를 한눈에 봅니다 (C)"]], "auto", func(m): _set_cam(str(m)))
	cam_btn = (cam_seg.get_meta("buttons") as Dictionary)["auto"]
	cam_manual = UITheme.badge("수동", UITheme.WARN, "soft", "휠로 확대하거나 우클릭 드래그로 옮겨 수동 카메라가 되었습니다. 추적이나 전체를 누르면 돌아갑니다.")
	cam_manual.visible = false
	h.add_child(_group("카메라", [cam_seg, cam_manual]))

	h.add_child(UITheme.spacer())
	perf_l = UITheme.label("", "FaintLabel", 12)
	perf_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	perf_l.visible = false
	h.add_child(perf_l)
	panel_btn = UITheme.button("패널 숨기기", "GhostButton", _toggle_side, "오른쪽 정보 패널을 접거나 폅니다 (Tab)")
	panel_btn.custom_minimum_size = Vector2(0, 34)
	panel_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(panel_btn)
	var ex: = UITheme.button("나가기", "DangerButton", _exit, "전투를 멈추고 이전 화면으로 돌아갑니다. Esc 키는 두 번 눌러야 나갑니다.")
	ex.custom_minimum_size = Vector2(80, 34)
	ex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ex)


## Labelled control group: small tracked caption, then the controls.
func _group(caption: String, controls: Array) -> HBoxContainer:
	var g: = UITheme.hbox(8)
	var c: = UITheme.label(caption, "EyebrowLabel", 12, UITheme.TEXT_FAINT)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(c)
	for n in controls:
		(n as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(n)
	return g


func _group_sep() -> Control:
	var s: = UITheme.sep_line(true)
	s.custom_minimum_size = Vector2(1, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _build_pause_pill() -> void:
	pause_pill = PanelContainer.new()
	pause_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_pill.anchor_left = 0.5
	pause_pill.anchor_right = 0.5
	pause_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_pill.offset_top = 12
	pause_pill_l = UITheme.label("", "BoldLabel", 14, UITheme.WARN)
	pause_pill.add_child(pause_pill_l)
	pause_pill.visible = false
	arena_area.add_child(pause_pill)


# ================================================================== side panel

func _build_side() -> void :
	var st: = UITheme.sb(UITheme.PANEL, UITheme.LINE, 0, 0, 12, 12)
	st.set_border_width_all(0)
	st.border_width_left = 1
	side = UITheme.styled_panel(st)
	add_child(side)
	var v: = UITheme.vbox(10)
	side.add_child(v)
	sel_card = _build_sel_card()
	v.add_child(sel_card)
	var tw: = UITheme.vbox(0)
	tabs = TabBar.new()
	tabs.focus_mode = Control.FOCUS_NONE
	for t in TEAM_TABS:
		tabs.add_tab(t)
	tabs.tab_changed.connect( func(i): cur_tab = i;_refresh_panel(true))
	tw.add_child(tabs)
	tw.add_child(UITheme.sep_line())
	v.add_child(tw)
	tab_scroll = ScrollContainer.new()
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_body = UITheme.vbox(12)
	tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.add_child(tab_body)
	v.add_child(tab_scroll)
	log_filters = UITheme.hbox(0)
	log_filters.visible = false
	v.add_child(log_filters)
	log_rt = RichTextLabel.new()
	log_rt.bbcode_enabled = true
	log_rt.scroll_following = true
	log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rt.visible = false
	log_rt.selection_enabled = false
	log_rt.add_theme_font_size_override("normal_font_size", 13)
	log_rt.add_theme_font_size_override("bold_font_size", 13)
	log_rt.add_theme_constant_override("line_separation", 4)
	v.add_child(log_rt)


func _build_sel_card() -> PanelContainer:
	var card: = UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_M, 1, 12, 10))
	var h: = UITheme.hbox(12)
	card.add_child(h)
	sel_disc = GlyphDisc.new(null, 46, -1)
	sel_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sel_disc)
	var v: = UITheme.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var r1: = UITheme.hbox(6)
	sel_name = UITheme.ellipsize(UITheme.label("", "BlackLabel", 17))
	sel_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(sel_name)
	sel_side = UITheme.badge("", UITheme.BLUE)
	sel_side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(sel_side)
	sel_role = UITheme.badge("", UITheme.ACCENT, "outline")
	sel_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(sel_role)
	v.add_child(r1)
	sel_hp_row = UITheme.hbox(8)
	sel_hp = HpBar.new()
	sel_hp.custom_minimum_size = Vector2(0, 8)
	sel_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sel_hp_row.add_child(sel_hp)
	sel_hp_l = UITheme.label("", "", 12, UITheme.TEXT_DIM)
	sel_hp_l.add_theme_font_override("font", DB.font_bold)
	sel_hp_row.add_child(sel_hp_l)
	v.add_child(sel_hp_row)
	sel_act = UITheme.ellipsize(UITheme.label("", "CaptionLabel", 13), true)
	v.add_child(sel_act)
	return card


static func _badge_set(b: PanelContainer, text: String, col: Color) -> void:
	var l: Label = b.get_meta("label")
	l.text = text
	if not b.has_meta("col") or b.get_meta("col") != col:
		b.set_meta("col", col)
		b.add_theme_stylebox_override("panel", UITheme.sbc(Color(col, 0.12), Color(col, 0.38), UITheme.R_PILL, 1, 8, 2))
		l.add_theme_color_override("font_color", col.lightened(0.3))


## Sets a label colour only when it changes (theme overrides are not free).
static func _col(l: Label, c: Color) -> void:
	if not l.has_meta("_c") or l.get_meta("_c") != c:
		l.set_meta("_c", c)
		l.add_theme_color_override("font_color", c)


static func _tip(c: Control, text: String) -> void:
	if not c.has_meta("_t") or str(c.get_meta("_t")) != text:
		c.set_meta("_t", text)
		c.tooltip_text = UITheme.tip(text) if text != "" else ""


func _update_sel_card() -> void:
	var sim: = runner.sim
	var u: = sim.u_at(view.selected)
	if u == null or not u.is_hero:
		if _sel_key != "none":
			_sel_key = "none"
			sel_disc.set_def(null)
			sel_name.text = "선택한 유닛 없음"
			_col(sel_name, UITheme.TEXT_DIM)
			sel_side.visible = false
			sel_role.visible = false
			sel_hp_row.visible = false
			sel_act.text = "전장이나 상단 막대에서 유닛을 눌러 주세요."
		return
	var key: = "%d|%d" % [u.idx, view.perspective]
	if key != _sel_key:
		_sel_key = key
		sel_disc.set_def(u.def, u.team)
		sel_name.text = u.def.name
		_col(sel_name, UITheme.TEXT)
		sel_side.visible = true
		sel_role.visible = true
		sel_hp_row.visible = true
		_badge_set(sel_side, br.team_label(u.team) if br else (("P%d" % (u.team + 1)) if dm else DB.TEAM_NAMES[clampi(u.team, 0, 1)]), UITheme.team_color(u.team))
		_badge_set(sel_role, DB.role_label(u.def.role), UITheme.role_color(u.def.role))
	var mx: = maxf(1.0, sim.max_hp(u))
	var act: = ""
	if view.perspective >= 0 and sim.eteam(u) != view.perspective:
		var belief: TeamIntel.EnemyBelief = _belief_of(view.perspective, u.idx)
		if belief:
			var bh: = clampf(belief.hp / maxf(1.0, belief.max_hp), 0.0, 1.0) if not belief.dead else 0.0
			sel_disc.set_state(bh, 0.0, belief.dead)
			sel_hp.set_values(bh, 0.0, true)
			sel_hp_l.text = "추정 %d / %d" % [int(belief.hp), int(belief.max_hp)]
			act = "사망 관측" if belief.dead else ("현재 관측 중" if belief.visible else "미관측 · 마지막 목격 %.1f초 전" % maxf(0.0, sim.time - belief.last_seen_t))
		else:
			sel_disc.set_state(-1.0, 0.0, false)
			sel_hp.set_values(0.0, 0.0, false)
			sel_hp_l.text = "정보 없음"
			act = "이 시점의 팀은 아직 관측하지 못했습니다"
	elif view.perspective >= 0 and not view._vis(u):
		sel_disc.set_state(-1.0, 0.0, false)
		sel_hp.set_values(0.0, 0.0, false)
		sel_hp_l.text = "보이지 않음"
		act = "현재 시점에서는 보이지 않습니다"
	elif br and br.is_downed(u):
		# Downed: the separate 300 HP pool.
		var dh: = clampf(u.hp / BattlegroundMode.DOWNED_HP, 0.0, 1.0)
		sel_disc.set_state(dh, 0.0, false)
		sel_hp.set_values(dh, 0.0, true)
		sel_hp_l.text = "다운 %d / %d" % [int(u.hp), int(BattlegroundMode.DOWNED_HP)]
		act = _action_text(u)
	else:
		var hp: = u.hp / mx if u.alive else 0.0
		var sh: = sim.shield_amount(u)
		sel_disc.set_state(hp, sh / mx if u.alive else 0.0, not u.alive)
		sel_hp.set_values(hp, sh / mx if u.alive else 0.0, true)
		sel_hp_l.text = ("%d / %d" % [int(u.hp), int(mx)]) + (("  +%d" % int(sh)) if sh > 0.5 and u.alive else "")
		act = _action_text(u)
		var purpose: = str(u.command.get("purpose", ""))
		if purpose != "" and u.alive:
			act += " · AI: " + purpose
		if sim.eteam(u) != u.team:
			act += " · 조종당함"
	sel_act.text = act
	_tip(sel_act, act)


func _action_text(u: BUnit) -> String:
	var sim: = runner.sim
	if br:
		if not u.alive:
			var hs: Dictionary = br.hstats.get(u.idx, {})
			var why: String = {"zone": "자기장", "bleed": "출혈", "team_wipe": "팀 전멸", "hazard": "환경"}.get(str(hs.get("death_cause", "")), "처치됨")
			var place: int = int(br.placement.get(u.team, 0))
			return "탈락 · %s (%s)%s" % [why, UITheme.fmt_time(float(hs.get("death_time", u.death_time))), (" · 팀 %d위" % place) if place > 0 and br.squad > 1 else ((" · %d위" % place) if place > 0 else "")]
		if br.is_downed(u):
			var d: Dictionary = br.downed_info(u)
			return BrStanding.downed_text({"downed_left": float(d.bleed_at) - sim.time, "revive": float(d.revive_progress)})
		if br.is_reviving(u):
			var tgt: BUnit = sim.u_at(int(br.reviving[u.idx]))
			var td: Dictionary = br.downed_info(tgt) if tgt else {}
			return "소생 중 · %s %d%%" % [tgt.def.name if tgt else "", int(float(td.get("revive_progress", 0.0)) * 100.0)]
	if not u.alive:
		if sim.is_control_mode() and sim.domination.respawn_at.has(u.idx):
			return "쓰러짐 · 부활까지 %.1f초" % maxf(0.0, float(sim.domination.respawn_at[u.idx]) - sim.time)
		if dm and sim.deathmatch.respawn_at.has(u.idx):
			return "쓰러짐 · 부활까지 %.1f초" % maxf(0.0, float(sim.deathmatch.respawn_at[u.idx]) - sim.time)
		return "쓰러짐 (%s)" % UITheme.fmt_time(u.death_time)
	if u.action and u.action.kind == "ability" and u.action.ability:
		return "시전 중 · " + u.action.ability.name
	if u.action:
		return "기본 공격"
	return "대기"


func _belief_of(team: int, idx: int) -> TeamIntel.EnemyBelief:
	var sim: = runner.sim
	if team < 0 or team >= sim.controllers.size():
		return null
	var ctl = sim.controllers[team]
	if ctl == null or not ("intel" in ctl) or ctl.intel == null:
		return null
	return ctl.intel.enemies.get(idx)


# ================================================================== lifecycle

func on_show(args: Dictionary) -> void :
	if args.has("config"):
		_start(args.config)
	else:
		runner.paused = false


func on_hide() -> void :
	if runner and not runner.done:
		runner.paused = true


func _start(cfg: Dictionary) -> void :
	config = cfg.duplicate(true)
	runner.start(cfg)
	runner.speed = float(Settings.get_v("default_speed", 1.0))
	runner.paused = false
	ended = false
	end_timer = -1.0
	_esc_armed_until = -1
	view.setup(runner.sim, runner)
	view.apply_settings()
	view.set("hud_readable", true)
	view.selected = -1
	view.show_ai = bool(Settings.get_v("ai_overlay", true))
	view.set_perspective(-1)
	view.set_cam_mode("full" if runner.sim.is_control_mode() else "auto")
	view.cam_zoom = 1.0
	view.cam_center = runner.sim.arena.center()
	view.cam_center_t = view.cam_center
	dm = runner.sim.is_deathmatch()
	br = runner.sim.battleground
	if dm:
		view.set_cam_mode("auto")
	var control: = runner.sim.is_control_mode()
	objectives.sim = runner.sim
	objectives.visible = control
	config["ruleset"] = runner.sim.ruleset
	_sync_cam()
	for c in chip_boxes:
		for ch in (c as Container).get_children():
			(c as Container).remove_child(ch)
			ch.queue_free()
	chips.clear()
	dm_chips.clear()
	br_chips.clear()
	_br_keys.clear()
	_arrange_mid("br" if br else ("dm" if dm else ("control" if control else "elim")))
	_lead_key = ""
	for t in 2:
		(team_tags[t] as Control).visible = not dm
		(op_labels[t] as Label).text = "x"
		_set_op(t, "")
	for i in TEAM_TABS.size():
		tabs.set_tab_title(i, DM_TABS[i] if dm else TEAM_TABS[i])
	for row in vision_btns:
		(row[1] as Button).visible = not dm or int(row[0]) < 0
	dm_view_opt.visible = dm
	minimap_btn.visible = br != null
	minimap.visible = br != null and minimap_btn.button_pressed
	if br:
		_start_br()
	elif dm:
		dm_view_opt.clear()
		dm_view_opt.add_item("참가자 시점 선택")
		var half: int = int(ceil(runner.sim.heroes.size() / 2.0))
		for u in runner.sim.heroes:
			dm_view_opt.add_item("P%d %s" % [u.team + 1, u.def.name])
			var dchip: DmChip = DmChip.new(runner.sim, u.idx)
			var di: int = u.idx
			dchip.pressed.connect(func(): _select(di))
			(chip_boxes[0 if u.team < half else 1] as Container).add_child(dchip)
			dm_chips.append(dchip)
		dm_view_opt.select(0)
	else:
		var per_team: = [0, 0]
		for u in runner.sim.heroes:
			var chip: = UnitChip.new(runner.sim, u.idx)
			var ii: = u.idx
			chip.pressed.connect( func(): _select(ii))
			(chip_boxes[u.team] as Container).add_child(chip)
			chips.append(chip)
			per_team[clampi(u.team, 0, 1)] += 1
		# The operation chip under each team name may use what the chips leave (5v5 at 1600 px is the
		# tight case); the tag itself stays as narrow as its content.
		var n: = maxi(per_team[0], per_team[1])
		var chips_w: = n * UnitChip.CHIP_W + maxi(0, n - 1) * CHIP_GAP
		_tag_room = clampf(floorf((maxf(size.x, 1600.0) - 2.0 * chips_w - MID_W - 4.0 * 8.0 - 20.0) * 0.5), 58.0, 128.0)
	for c in feed_box.get_children():
		feed_box.remove_child(c)
		c.queue_free()
	feed_seen = 0
	_build_log_filters(control)
	log_rt.clear()
	log_seen = 0
	_log_lines = 0
	toggles.ai.set_pressed_no_signal(view.show_ai)
	toggles.tele.set_pressed_no_signal(view.show_telegraphs)
	toggles.names.set_pressed_no_signal(view.show_names)
	toggles.nums.set_pressed_no_signal(view.show_numbers)
	_last_paused = -1
	_time_warn = -1
	_sync_buttons()
	var a: = runner.sim.arena
	var seed_v: = int(cfg.get("seed", 0))
	if br:
		sub_l.text = ""
		var fmt: String = str(BR_SQUAD_NAMES.get(br.squad, "솔로"))
		var who: String = ("%d명" % runner.sim.heroes.size()) if br.squad <= 1 else ("%d팀 %d명" % [br.team_count, runner.sim.heroes.size()])
		_banner("배틀그라운드", "%s · %s · %s · 자기장 %s" % [fmt, who, a.name, str(BrZone.SPEED_LABELS.get(br.zone_speed, "보통"))], UITheme.GOLD)
		_tip(alive_l, "살아 있는 영웅 수 / 처음 인원%s. 탈락하면 다시 나오지 않습니다." % (" · 남은 팀 수" if br.squad > 1 else ""))
	elif dm:
		sub_l.text = "%s · %d명 개인전 · 목표 %d킬" % [a.name, runner.sim.heroes.size(), runner.sim.deathmatch.kill_target]
		_banner("데스매치", "%d명 개인전 · 목표 %d킬 · %s" % [runner.sim.heroes.size(), runner.sim.deathmatch.kill_target, a.name], UITheme.GOLD)
	elif control:
		var target: = float(runner.sim.domination.target_score)
		for bar in race_bars:
			(bar as ProgressBar).max_value = maxf(1.0, target)
			(bar as ProgressBar).value = 0.0
		score_l.text = "%d점" % int(target)
		_tip(score_l, "목표 점수입니다. 양쪽 막대가 가운데로 차오르며, 먼저 %d점에 닿는 팀이 승리합니다." % int(target))
		_tip(blue_n, "청 팀 점수")
		_tip(red_n, "홍 팀 점수")
		_banner("거점 장악", "거점 3곳 · %d점 선승 · %s초 뒤 부활" % [int(target), CodexData.num(DominationMode.RESPAWN_DELAY)], UITheme.GOLD)
	else:
		score_l.text = "생존 영웅"
		_tip(score_l, "양 팀에 살아 있는 영웅 수입니다.")
		_tip(blue_n, "청 팀 생존 영웅 수")
		_tip(red_n, "홍 팀 생존 영웅 수")
		sub_l.text = "· %s · %s 대 %s" % [a.name, AIFactory.label(str(cfg.get("blue_ai", "tactician"))).split(" ")[0], AIFactory.label(str(cfg.get("red_ai", "tactician"))).split(" ")[0]]
		_banner("전투 시작", "%d : %d · %s" % [cfg.blue.size(), cfg.red.size(), a.name], UITheme.GOLD)
	_tip(sub_l, "시드 %d · 같은 시드와 조합이면 전투가 똑같이 재현됩니다." % seed_v)
	_tip(time_l, ("경과 시간 · 시드 %d · %s에 남은 팀을 생존 인원과 체력으로 순위를 정합니다." % [seed_v, UITheme.fmt_time(runner.sim.max_time)]) if br else "")
	perf_l.visible = app != null and app._perf
	_hud_timer = 0.0
	_update_scoreboard()
	_clear_body()
	_body_sig = ""
	_sel_key = ""
	_layout()
	_select(runner.sim.heroes[0].idx)
	Sfx.play("start", 0.45)


func _on_stepped(evs: Array) -> void :
	view.on_step(evs)


func _on_finished(result: Dictionary) -> void :
	ended = true
	end_result = result
	_esc_armed_until = -1
	var w: = int(result.winner)
	var reason: = "전멸" if str(result.reason) == "elimination" else ("시간 종료 · 체력 합 판정" if str(result.reason) == "time_limit" else str(result.reason))
	if str(result.get("ruleset", "elimination")) == "control":
		var scores: Array = result.get("scores", [0, 0])
		reason = "%d : %d · %s" % [int(scores[0]), int(scores[1]), "목표 점수 달성" if maxf(float(scores[0]), float(scores[1])) >= float(result.get("target_score", 300)) else "시간 종료 · 점수 판정"]
	var mode: = str(config.get("mode", "composition"))
	var title: = "무승부"
	var col: = UITheme.GOLD
	if br:
		var wt: int = br.winner_team
		if wt >= 0:
			var members: Array = br.team_members(wt)
			title = ("%s %s 우승" % [br.team_label(wt), (members[0] as BUnit).def.name]) if br.squad <= 1 and not members.is_empty() else "%s 우승" % br.team_label(wt)
			col = UITheme.team_color(wt)
		reason = "마지막 생존 팀" if str(result.reason) == "battleground_last" else "시간 종료 · 생존 인원·체력 판정"
		# Knock times for the report chart (the result keeps counts only).
		var knocks: Array = []
		for ev in runner.sim.log:
			if str(ev.get("type", "")) == "BR_DOWNED":
				knocks.append([float(ev.get("t", 0.0)), int(ev.get("team", -1))])
		end_result["br_knocks"] = knocks
		w = -1
	elif dm:
		var ranking: Array = (result.get("deathmatch", {}) as Dictionary).get("ranking", [])
		if not ranking.is_empty():
			var top: Dictionary = ranking[0]
			title = "%s 우승" % DB.char_def(str(top.id)).name
			col = UITheme.team_color(int(top.team))
			reason = "%d킬 · %s" % [int(top.kills), "목표 처치 달성" if str(result.reason) == "deathmatch_kills" else "시간 종료 · 처치 순위"]
		w = -1
	elif w == 0 or w == 1:
		title = ("청 팀 승리" if w == 0 else "홍 팀 승리")
		col = UITheme.team_color(w)
		if mode == "draft":
			title = "승리!" if w == 0 else "AI 승리"
	_banner(title, reason, col, 2.4)
	Settings.records.battles = int(Settings.records.get("battles", 0)) + 1
	if mode == "draft":
		if w == 0:
			Settings.record_draft(true)
		elif w == 1:
			Settings.record_draft(false)
		else:
			Settings.save_all()
	else:
		Settings.save_all()
	Sfx.play("victory" if (mode != "draft" or w == 0) else "defeat", 0.6)
	end_timer = 2.6
	_sync_pause()


func _exit() -> void :
	runner.paused = true
	_esc_armed_until = -1
	if ended:
		app.show_result(end_result, config)
	else:
		app.goto(app.battle_origin if app.battle_origin in ["setup", "draft", "home", "deathmatch", "battleground"] else "home")


# ================================================================== input

func _unhandled_key_input(event: InputEvent) -> void :
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_1:
			_set_speed(0.5)
		KEY_2:
			_set_speed(1.0)
		KEY_3:
			_set_speed(2.0)
		KEY_4:
			_set_speed(4.0)
		KEY_V:
			if br:
				_set_vision(_br_next_view(view.perspective, -1 if (event as InputEventKey).shift_pressed else 1))
			elif dm:
				var nxt: int = view.perspective + 1
				_set_vision(nxt if nxt < runner.sim.team_count else -1)
			else:
				_set_vision(((view.perspective + 2) % 3) - 1)
		KEY_M:
			if not br:
				return
			minimap_btn.button_pressed = not minimap_btn.button_pressed
		KEY_TAB:
			_toggle_side()
		KEY_C:
			_cycle_cam()
		KEY_ESCAPE:
			# Two-step exit so a stray Esc does not throw the battle away.
			if ended or _esc_armed():
				_exit()
			else:
				_esc_armed_until = Time.get_ticks_msec() + 2500
				_sync_pause()
		_:
			return
	get_viewport().set_input_as_handled()


func _esc_armed() -> bool:
	return _esc_armed_until > 0 and Time.get_ticks_msec() < _esc_armed_until


func _arena_input(event: InputEvent) -> void :
	if event is InputEventMouseButton:
		var mb: = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var wp: = view.to_world(mb.position)
			var idx: = view.pick_unit(wp)
			_select(idx)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			view.manual_zoom(1.12, mb.position)
			_sync_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			view.manual_zoom(1.0 / 1.12, mb.position)
			_sync_cam()
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = mb.pressed
	elif event is InputEventMouseMotion and dragging:
		view.manual_pan((event as InputEventMouseMotion).relative)
		_sync_cam()


func _toggle_side() -> void:
	side_visible = not side_visible
	_layout()
	if side_visible:
		_refresh_panel(true)


func _cycle_cam() -> void :
	_set_cam("full" if view.cam_mode == "auto" else "auto")


func _set_cam(m: String) -> void:
	view.set_cam_mode(m)
	_sync_cam()


func _sync_cam() -> void :
	UITheme.segmented_select(cam_seg, view.cam_mode)
	cam_manual.visible = view.cam_mode == "manual"


func _apply_select(idx: int) -> void:
	view.selected = idx
	for c in chips:
		(c as UnitChip).selected = (c as UnitChip).idx == idx
	for dc in dm_chips:
		(dc as DmChip).selected = (dc as DmChip).idx == idx
	if br:
		_br_timer = 0.0
	if dm and view.cam_mode == "full":
		view.set_cam_mode("auto")
		_sync_cam()


func _select(idx: int) -> void :
	_apply_select(idx)
	_refresh(false, true)


func _toggle_pause() -> void :
	if ended:
		return
	runner.paused = not runner.paused
	_sync_buttons()


func _set_speed(sp: float) -> void :
	runner.speed = sp
	runner.paused = false
	_sync_buttons()


func _set_vision(p: int) -> void :
	view.set_perspective(p)
	if br:
		view.follow_team = p
		dm_view_opt.select(p + 1)
		if p >= 0:
			var first: BUnit = _br_focus_member(p)
			if first:
				_apply_select(first.idx)
		_br_timer = 0.0
	elif dm:
		dm_view_opt.select(p + 1)
		if p >= 0:
			for u in runner.sim.heroes:
				if u.team == p:
					_apply_select(u.idx)
	_sync_buttons()
	_refresh(true, true)


func _toggle(key: String, on: bool) -> void :
	_suppress_settings = true
	match key:
		"ai":
			view.show_ai = on
			Settings.set_v("ai_overlay", on)
		"tele":
			view.show_telegraphs = on
			Settings.set_v("telegraphs", on)
		"names":
			view.show_names = on
			Settings.set_v("show_names", on)
		"nums":
			view.show_numbers = on
			Settings.set_v("damage_numbers", on)
	_suppress_settings = false


func _sync_buttons() -> void :
	UITheme.segmented_select(speed_seg, runner.speed)
	UITheme.segmented_select(vision_seg, view.perspective)
	_sync_pause()


func _sync_pause() -> void:
	var paused: = runner != null and runner.paused
	_last_paused = 1 if paused else 0
	pause_btn.text = "▶" if paused else "❚❚"
	var armed: = _esc_armed() and not ended
	pause_pill.visible = armed or (paused and not ended)
	if not pause_pill.visible:
		return
	var col: = UITheme.BAD if armed else UITheme.WARN
	pause_pill_l.text = "Esc를 한 번 더 누르면 전투를 나갑니다" if armed else "❚❚  일시정지 중 · Space를 누르면 이어서 봅니다"
	_col(pause_pill_l, col.lightened(0.15))
	pause_pill.add_theme_stylebox_override("panel", UITheme.sbc(Color(0.03, 0.045, 0.07, 0.92), Color(col, 0.6), UITheme.R_PILL, 1, 16, 6))


# ================================================================== per-frame

func _process(delta: float) -> void :
	if runner == null or runner.sim == null or not visible:
		return
	var sim: = runner.sim
	var remain: = sim.max_time - sim.time
	# Battleground: elapsed time (the zone pill has the countdown); red in the last 30 s of the cap.
	time_l.text = UITheme.fmt_time(sim.time if br else remain)
	var warn: = 1 if remain < (30.0 if br else 20.0) and not ended else 0
	if warn != _time_warn:
		_time_warn = warn
		time_l.add_theme_color_override("font_color", UITheme.BAD if warn == 1 else UITheme.TEXT)
	if (1 if runner.paused else 0) != _last_paused:
		_sync_pause()
	if _esc_armed_until > 0 and not _esc_armed():
		_esc_armed_until = -1
		_sync_pause()
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		_update_scoreboard()
	for c in chips:
		(c as UnitChip).perspective = view.perspective
		(c as UnitChip).refresh()
	for dc in dm_chips:
		(dc as DmChip).perspective = view.perspective
		(dc as DmChip).refresh()
	if br:
		zone_pill.set_time(sim.time)
		_br_timer -= delta
		if _br_timer <= 0.0:
			_br_timer = BR_PUSH
			_push_br()
		_cam_timer -= delta
		if _cam_timer <= 0.0 and minimap.visible:
			_cam_timer = 0.1
			minimap.set_camera_rect(_camera_world_rect())
	if perf_l.visible:
		_perf_timer -= delta
		if _perf_timer <= 0.0:
			_perf_timer = 0.5
			perf_l.text = "%d FPS · 시뮬 %.1fms" % [Engine.get_frames_per_second(), runner.step_ms]
	_update_feed()
	panel_timer -= delta
	if panel_timer <= 0.0:
		panel_timer = _panel_interval()
		_refresh(false, false)
	if banner_t >= 0.0:
		banner_t += delta
		banner.queue_redraw()
	if end_timer > 0.0:
		end_timer -= delta
		if end_timer <= 0.0:
			app.show_result(end_result, config)


## Scoreboard values (10 Hz). Text setters are no-ops for unchanged strings.
func _update_scoreboard() -> void:
	var sim: = runner.sim
	if br:
		var heroes: int = br.alive_hero_count()
		var text: String = ("생존 %d/%d명" % [heroes, sim.heroes.size()]) if br.squad <= 1 else ("생존 %d/%d · %d팀" % [heroes, sim.heroes.size(), br.alive_team_count()])
		if alive_l.text != text:
			alive_l.text = text
		return
	if dm:
		var order: Array = sim.deathmatch.ranking()
		var lead: BUnit = order[0] if not order.is_empty() else null
		if lead == null:
			return
		var kills: int = sim.deathmatch.kills[lead.team]
		var target: int = sim.deathmatch.kill_target
		var key: = "%d|%d|%d" % [lead.idx if kills > 0 else -1, kills, target]
		if key != _lead_key:
			_lead_key = key
			if kills <= 0:
				leader_disc.set_def(null)
				leader_name.text = "아직 처치 없음"
				_col(leader_name, UITheme.TEXT_DIM)
				leader_kills.text = "목표 %d킬" % target
				leader_bar.value = 0.0
				leader_pill.add_theme_stylebox_override("panel", UITheme.sbc(Color(UITheme.GOLD, 0.06), Color(UITheme.GOLD, 0.3), UITheme.R_PILL, 1, 12, 4))
			else:
				var tc: = UITheme.team_color(lead.team)
				leader_disc.set_def(lead.def, lead.team)
				leader_name.text = "P%d %s" % [lead.team + 1, lead.def.name]
				_col(leader_name, tc.lightened(0.3))
				leader_kills.text = "%d / %d킬" % [kills, target]
				leader_bar.max_value = maxf(1.0, float(target))
				leader_bar.value = float(kills)
				leader_pill.add_theme_stylebox_override("panel", UITheme.sbc(Color(tc, 0.12), Color(tc, 0.5), UITheme.R_PILL, 1, 12, 4))
		return
	var alive: = [0, 0]
	for u in sim.heroes:
		if u.alive and u.team < 2:
			alive[u.team] += 1
	if sim.is_control_mode():
		var scores: Array = sim.domination.scores
		blue_n.text = str(int(scores[0]))
		red_n.text = str(int(scores[1]))
		(race_bars[0] as ProgressBar).value = float(scores[0])
		(race_bars[1] as ProgressBar).value = float(scores[1])
		sub_l.text = "· %s · %s" % [sim.arena.name, ("생존 %d : %d" % [alive[0], alive[1]]) if view.perspective < 0 else ("아군 생존 %d" % alive[clampi(view.perspective, 0, 1)])]
	else:
		blue_n.text = str(alive[0])
		red_n.text = str(alive[1])
	for t in op_labels.size():
		var ctl = sim.controllers[t] if t < sim.controllers.size() else null
		var show_op: bool = ctl != null and "plan" in ctl and (view.perspective < 0 or view.perspective == t)
		_set_op(t, str(ctl.plan.get("op", "")) if show_op else "")


func _update_feed() -> void :
	var kf: Array = view.kill_feed
	var feed_max: int = BR_FEED_MAX if br else FEED_MAX
	while feed_seen < kf.size():
		var k: Dictionary = kf[feed_seen]
		feed_seen += 1
		var killer: = runner.sim.u_at(int(k.killer))
		var victim: = runner.sim.u_at(int(k.victim))
		var p: Control
		if br:
			# A zone shrink also gets the centre banner (phase, how long, damage outside).
			if str(k.get("kind", "")) == "zone" and str(k.get("state", "")) == "shrink" and not ended:
				_banner("자기장 수축", "%d/%d단계 · %s 동안 줄어듭니다 · 원 밖 %s" % [int(k.get("phase", 0)), BrZone.PHASES,
					UITheme.fmt_time(maxf(0.0, float(k.get("shrink_end", 0.0)) - float(k.get("t", 0.0)))), ZonePill.dps_text(float(k.get("dps_ratio", 0.0)))], Color("#cf9bff"))
			p = _br_feed_pill(k, killer, victim)
			if p == null:
				continue
		elif victim == null:
			continue
		else:
			p = _feed_pill(k, killer, victim)
		feed_box.add_child(p)
		# Node-bound tween: it dies with the pill (no callbacks into freed nodes).
		var tw: = p.create_tween()
		tw.tween_interval(6.0)
		tw.tween_property(p, "modulate:a", 0.0, 0.6)
		tw.tween_callback(p.queue_free)
		while feed_box.get_child_count() > feed_max:
			var old: = feed_box.get_child(0)
			feed_box.remove_child(old)
			old.queue_free()


func _feed_pill(k: Dictionary, killer: BUnit, victim: BUnit) -> Control:
	var h: = UITheme.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if killer:
		if killer.is_hero:
			h.add_child(_mini_disc(killer, false))
		h.add_child(_feed_name(killer.def.name, UITheme.team_color(killer.team)))
	else:
		h.add_child(_feed_name("환경", UITheme.WARN))
	var g: = UITheme.label("✂" if bool(k.get("execute", false)) else "⚔", "", 13, UITheme.GOLD)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(g)
	if victim.is_hero:
		h.add_child(_mini_disc(victim, true))
	h.add_child(_feed_name(victim.def.name, UITheme.team_color(victim.team)))
	if int(k.get("streak", 0)) >= 2:
		var sb: = UITheme.badge("%d연속" % int(k.streak), UITheme.GOLD, "strong")
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sb)
	if dm and killer:
		var kl: = UITheme.label("%d킬" % int(k.get("score", 0)), "", 12, UITheme.TEXT_DIM)
		kl.add_theme_font_override("font", DB.font_bold)
		kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(kl)
	var tl: = UITheme.label(UITheme.fmt_time(float(k.t)), "FaintLabel", 12)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	var p: = UITheme.styled_panel(UITheme.sbc(Color(0.03, 0.045, 0.07, 0.86), Color(1, 1, 1, 0.1), UITheme.R_PILL, 1, 10, 3), h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


func _feed_name(text: String, col: Color) -> Label:
	var l: = UITheme.label(text, "", 13, col.lightened(0.2))
	l.add_theme_font_override("font", DB.font_bold)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _mini_disc(u: BUnit, dead: bool) -> GlyphDisc:
	var d: = GlyphDisc.new(u.def, 20, u.team)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if dead:
		d.set_state(0.0, 0.0, true)
	return d


func _banner(title: String, sub: String, col: Color, _dur: float = 1.6) -> void :
	banner_text = title
	banner_sub = sub
	banner_col = col
	banner_t = 0.0


func _draw_banner() -> void :
	if banner_t < 0.0:
		return
	var dur: = 1.8 if not ended else 99.0
	var k: = banner_t / dur
	if k >= 1.0:
		banner_t = -1.0
		return
	var a: = minf(1.0, banner_t * 5.0) * (1.0 - maxf(0.0, (k - 0.75) / 0.25) if not ended else 1.0)
	var sz: = banner.size
	var cy: = sz.y * 0.42
	banner.draw_rect(Rect2(0, cy - 56, sz.x, 112), Color(0, 0, 0, 0.55 * a))
	banner.draw_rect(Rect2(0, cy - 56, sz.x, 2), Color(banner_col, 0.8 * a))
	banner.draw_rect(Rect2(0, cy + 54, sz.x, 2), Color(banner_col, 0.8 * a))
	var f: = DB.font_black
	var fs: = 52
	var scale_pop: = 1.0 + 0.25 * maxf(0.0, 1.0 - banner_t * 4.0)
	var w: = f.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * scale_pop)).x
	banner.draw_string(f, Vector2(sz.x * 0.5 - w * 0.5, cy + 12), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * scale_pop), Color(VfxStyle.hdr(banner_col, 1.25), a))
	var f2: = DB.font_bold
	var w2: = f2.get_string_size(banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	banner.draw_string(f2, Vector2(sz.x * 0.5 - w2 * 0.5, cy + 42), banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8 * a))


# ================================================================== side panel: routing

func _clear_body() -> void :
	# remove_child first so the freed rows never take part in this frame's layout.
	for c in tab_body.get_children():
		tab_body.remove_child(c)
		c.queue_free()
	_updaters.clear()
	_rank_rows.clear()


func _tab_kind() -> String:
	var i: = clampi(cur_tab, 0, 3)
	if br:
		return ["br_rank", "unit", "log", "br_ai"][i]
	if dm:
		return ["rank", "unit", "log", "dm_ai"][i]
	return ["unit", "ai", "log", "stats"][i]


func _panel_interval() -> float:
	match _tab_kind():
		"rank", "br_rank":
			return 0.25
		"unit", "log":
			return 0.2
	# AI tabs call explain() (not cheap) and rebuild; stats bars barely move.
	return 0.5


## Forced refresh (rebuild) — kept for callers and tests.
func _refresh_panel(force: bool) -> void :
	_refresh(force, true)


## force: rebuild even when the signature is unchanged. urgent: also run while paused.
func _refresh(force: bool, urgent: bool) -> void:
	if runner == null or runner.sim == null or not side_visible:
		return
	if runner.paused and not urgent:
		return
	_update_sel_card()
	var kind: = _tab_kind()
	var is_log: = kind == "log"
	log_rt.visible = is_log
	log_filters.visible = is_log
	tab_scroll.visible = not is_log
	if is_log:
		_panel_log(force)
		return
	var sig: = _panel_sig(kind)
	if force or sig != _body_sig:
		_clear_body()
		_body_sig = sig
		match kind:
			"rank":
				_panel_dm_rank()
			"unit":
				_panel_unit()
			"ai":
				_panel_ai()
			"stats":
				_panel_stats()
			"dm_ai":
				_panel_dm_ai()
			"br_rank":
				_panel_br_rank()
			"br_ai":
				_panel_br_ai()
	for f in _updaters:
		(f as Callable).call()


func _panel_sig(kind: String) -> String:
	match kind:
		"rank":
			return "rank|%d|%d" % [view.perspective, runner.sim.heroes.size()]
		"br_rank":
			return "br_rank|%d" % view.perspective
		"unit":
			return _unit_sig()
		"stats":
			return "stats|%d" % view.perspective
	# Reasoning tabs change shape constantly: rebuild on every (0.5 s) refresh.
	return "%s|%d" % [kind, Time.get_ticks_usec()]


# ================================================================== side panel: building blocks

## Section header: accent tick, 13 px title, optional faint hint, hairline divider below.
func _section(title: String, hint: String = "") -> Control:
	var v: = UITheme.vbox(5)
	var h: = UITheme.hbox(8)
	var bar: = Panel.new()
	bar.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.ACCENT, UITheme.CLEAR, 2, 0, 0, 0))
	bar.custom_minimum_size = Vector2(3, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var t: = UITheme.label(title, "BoldLabel", 13, UITheme.TEXT)
	h.add_child(t)
	if hint != "":
		var hl: = UITheme.ellipsize(UITheme.label(hint, "FaintLabel", 12), true)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(hl)
	v.add_child(h)
	v.add_child(UITheme.sep_line())
	v.set_meta("title", t)
	return v


## One-line faint hint; the longer explanation goes into its tooltip.
func _hint(text: String, more: String = "") -> Label:
	var l: = UITheme.wrap_label(text, "FaintLabel", 12)
	if more != "":
		l.tooltip_text = UITheme.tip(more)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _card(child: Control, tint: Color = UITheme.CLEAR) -> PanelContainer:
	if tint.a > 0.0:
		return UITheme.styled_panel(UITheme.sbc(Color(tint, 0.06), Color(tint, 0.3), UITheme.R_M, 1, 12, 10), child)
	return UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_M, 1, 12, 10), child)


## Caption/value row. Returns {"row", "value"}.
func _kv(caption: String, value: String, value_color: Color = UITheme.TEXT) -> Dictionary:
	var row: = UITheme.hbox(10)
	var c: = UITheme.label(caption, "FaintLabel", 12)
	c.custom_minimum_size = Vector2(60, 0)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(c)
	var v: = UITheme.wrap_label(value, "BodyLabel", 13, value_color)
	row.add_child(v)
	return {"row": row, "value": v}


## Tight list appended to tab_body: rows inside one section sit closer than the 12 px between sections.
func _list(sep: int = 6) -> VBoxContainer:
	var l: = UITheme.vbox(sep)
	tab_body.add_child(l)
	return l


func _flow(sep: int = 6) -> HFlowContainer:
	var f: = HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _empty(icon: String, title: String, hint: String = "") -> Control:
	var e: = UITheme.empty_state(icon, title, hint)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return UITheme.margin(e, 0, 24, 0, 8)


## Candidate/score row: marker, label (ellipsised), mini bar and a right-aligned number.
func _score_row(first: bool, text: String, ratio: float, value_text: String, col: Color, tip: String = "") -> Control:
	var row: = UITheme.hbox(8)
	var mk: = UITheme.label("▶" if first else "", "", 12, UITheme.GOLD)
	mk.custom_minimum_size = Vector2(12, 0)
	row.add_child(mk)
	var nl: = UITheme.ellipsize(UITheme.label(text, "", 13, UITheme.TEXT if first else UITheme.TEXT_DIM))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nl)
	row.add_child(MiniBar.new(ratio, col))
	var sl: = UITheme.label(value_text, "", 13, col if first else UITheme.TEXT_DIM)
	sl.add_theme_font_override("font", DB.font_bold)
	sl.custom_minimum_size = Vector2(40, 0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(sl)
	if tip != "":
		row.tooltip_text = UITheme.tip(tip)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _item_row(item_id: String, note: String) -> Control:
	var d: Dictionary = ItemDefs.get_def(item_id)
	var r: = ItemDefs.rarity_of(item_id)
	var col: Color = ItemDefs.rarity_color(r)
	var row: HBoxContainer = UITheme.hbox(10)
	var g: = UITheme.item_tile(item_id, 32)
	g.tooltip_text = ItemViews.tooltip_text(item_id)
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(g)
	var tv: VBoxContainer = UITheme.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh: = UITheme.hbox(6)
	var nl: = UITheme.label(str(d.get("name", item_id)), "BoldLabel", 14, col.lightened(0.25))
	nh.add_child(nl)
	var rb: = UITheme.badge(UITheme.rarity_name(r), col, "outline")
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nh.add_child(rb)
	tv.add_child(nh)
	tv.add_child(UITheme.wrap_label(str(d.get("desc", "")), "CaptionLabel", 13))
	if note != "":
		tv.add_child(UITheme.wrap_label(note, "", 13, UITheme.GOLD))
	row.add_child(tv)
	return UITheme.styled_panel(UITheme.sbc(Color(col, 0.05), Color(col, 0.22), UITheme.R_M, 1, 10, 8), row)


# ================================================================== tab: unit

func _unit_branch(u: BUnit) -> String:
	if view.perspective >= 0 and runner.sim.eteam(u) != view.perspective:
		return "belief"
	if view.perspective >= 0 and not view._vis(u):
		return "hidden"
	return "own"


func _unit_sig() -> String:
	var sim: = runner.sim
	var u: = sim.u_at(view.selected)
	if u == null or not u.is_hero:
		return "unit|none"
	var branch: = _unit_branch(u)
	if branch == "belief":
		# Observed data changes shape (reveals, deaths): rebuild each refresh.
		return "unit|belief|%d|%d" % [u.idx, Time.get_ticks_usec()]
	var s: = "unit|%d|%d|%s" % [u.idx, view.perspective, branch]
	if dm:
		for held_id in sim.deathmatch.held(u):
			s += "|" + str(held_id)
	for k in u.resources:
		s += "|r:" + str(k)
	return s


func _panel_unit() -> void :
	var sim: = runner.sim
	var u: = sim.u_at(view.selected)
	if u == null or not u.is_hero:
		tab_body.add_child(_empty("◎", "선택한 유닛이 없습니다", "전장이나 상단 막대에서 유닛을 누르면 자세한 정보가 표시됩니다."))
		return
	match _unit_branch(u):
		"belief":
			_panel_enemy_belief(u)
			return
		"hidden":
			tab_body.add_child(_empty("?", "지금은 보이지 않는 유닛입니다", "이 팀이 아는 정보는 'AI 판단' 탭의 추정치에서 확인할 수 있습니다."))
			return
	var idx: = u.idx

	if u.def.id == "politician":
		var pv: = UITheme.vbox(3)
		var stance: = UITheme.wrap_label("", "BodyLabel", 13)
		var trust: = UITheme.wrap_label("", "CaptionLabel", 13)
		pv.add_child(stance)
		pv.add_child(trust)
		tab_body.add_child(_card(pv, Color("#ecd998")))
		_updaters.append(func() -> void:
			var pu: = runner.sim.u_at(idx)
			if pu == null:
				return
			var contemplating: = bool(pu.ks.get("contemplating", false))
			stance.text = "관조 중 · 스킬 계수 +30% · 군중 제어 면역 · 언론 통제" if contemplating else "이동 중 · 관조 해제"
			_col(stance, Color("#ecd998") if contemplating else UITheme.TEXT_DIM)
			var distrust: = int(pu.resources.get("distrust", 0))
			trust.text = "상대 불신 %d / 10%s · 기본 공격 없음" % [distrust, " · 가짜 뉴스 거부" if distrust >= 10 else ""])

	_hero_card(u)

	var prot: = UITheme.badge("부활 보호 중 · 적대 행동을 하면 풀립니다" + (" · 점령 불가" if sim.is_control_mode() else ""), UITheme.GOOD, "soft", str(STATUS_TIPS.spawn_protection))
	prot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab_body.add_child(prot)

	# Action and AI intent live in the pinned card above the tabs (_update_sel_card).
	_updaters.append(func() -> void:
		var au: = runner.sim.u_at(idx)
		if au != null:
			prot.visible = runner.sim.has_status(au, &"spawn_protection"))

	if br:
		_br_downed_card(idx)
		var btiles: = UITheme.hbox(6)
		var b_k: = UITheme.stat_tile("처치", "0", UITheme.GOLD, "이 영웅이 마무리한 처치 수입니다. 자기장 사망은 10초 안에 마지막으로 피해를 준 영웅에게 기록됩니다.")
		var b_n: = UITheme.stat_tile("다운시킴", "0", UITheme.TEXT, "듀오·트리오에서 적을 다운시킨 횟수입니다.")
		var b_r: = UITheme.stat_tile("소생", "0", UITheme.TEXT, "다운된 팀원을 일으킨 횟수입니다.")
		var b_d: = UITheme.stat_tile("피해", "0", UITheme.TEXT, "적 영웅에게 준 체력 피해의 합입니다.")
		for t in [b_k, b_n, b_r, b_d]:
			(t as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btiles.add_child(t)
		if br.squad <= 1:
			b_n.visible = false
			b_r.visible = false
		tab_body.add_child(btiles)
		_updaters.append(func() -> void:
			var hs: Dictionary = br.hstats.get(idx, {})
			(b_k.get_meta("value") as Label).text = str(int(hs.get("kills", 0)))
			(b_n.get_meta("value") as Label).text = str(int(hs.get("knocks", 0)))
			(b_r.get_meta("value") as Label).text = str(int(hs.get("revives", 0)))
			(b_d.get_meta("value") as Label).text = str(int(float(hs.get("damage", 0.0)))))
	elif dm:
		var dmm: DeathmatchMode = sim.deathmatch
		var tiles: = UITheme.hbox(6)
		var t_k: = UITheme.stat_tile("처치", "0", UITheme.GOLD, "처치 수 · 목표 %d킬" % dmm.kill_target)
		var t_d: = UITheme.stat_tile("사망", "0", UITheme.TEXT)
		var t_a: = UITheme.stat_tile("도움", "0", UITheme.TEXT)
		var t_s: = UITheme.stat_tile("연속 처치", "0", UITheme.TEXT)
		t_s.mouse_filter = Control.MOUSE_FILTER_PASS
		for t in [t_k, t_d, t_a, t_s]:
			(t as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tiles.add_child(t)
		tab_body.add_child(tiles)
		_updaters.append(func() -> void:
			var du: = runner.sim.u_at(idx)
			if du == null:
				return
			var m: DeathmatchMode = runner.sim.deathmatch
			(t_k.get_meta("value") as Label).text = str(m.kills[du.team])
			(t_d.get_meta("value") as Label).text = str(m.deaths[du.team])
			(t_a.get_meta("value") as Label).text = str(m.assists[du.team])
			(t_s.get_meta("value") as Label).text = str(m.streak[du.team])
			_tip(t_s, "지금 이어지는 연속 처치 수입니다. 최고 기록 %d" % m.best_streak[du.team]))

	tab_body.add_child(_section("상태 효과", "마우스를 올리면 설명이 보입니다"))
	var fx: = UITheme.vbox(8)
	tab_body.add_child(fx)
	var fx_state: Dictionary = {"key": "?", "labels": {}}
	_updaters.append(func() -> void: _update_effects(idx, fx, fx_state))

	tab_body.add_child(_section("능력치", "초록 강화 · 빨강 약화"))
	var grid: = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var stat_rows: Array = []
	for row in [["공격력", BattleSim.S_AD, "%d"], ["주문력", BattleSim.S_AP, "%d"], ["방어력", BattleSim.S_ARMOR, "%d"],
			["마법 저항력", BattleSim.S_MR, "%d"], ["공격 속도", BattleSim.S_AS, "%.2f"], ["이동 속도", BattleSim.S_MS, "%d"]]:
		var tile: = UITheme.stat_tile(row[0], "0")
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(tile)
		stat_rows.append([tile, row[1], row[2], row[0]])
	tab_body.add_child(grid)
	_updaters.append(func() -> void:
		var su: = runner.sim.u_at(idx)
		if su == null:
			return
		for sr in stat_rows:
			var base: = su.def.stat(String(sr[1]))
			var cur: = runner.sim.stat(su, sr[1])
			var vl: Label = (sr[0] as Control).get_meta("value")
			vl.text = str(sr[2]) % cur
			_col(vl, UITheme.GOOD if cur > base + 0.01 else (UITheme.BAD if cur < base - 0.01 else UITheme.TEXT))
			_tip(sr[0], "%s · 기본 %s → 현재 %s" % [sr[3], str(sr[2]) % base, str(sr[2]) % cur]))

	tab_body.add_child(_section("스킬 재사용"))
	var skl: = _list(8)
	var skill_rows: Array = []
	for i in u.def.abilities.size():
		var a: Defs.AbilityDef = u.def.abilities[i]
		var col: = VfxStyle.color_for(a)
		var h: = UITheme.hbox(10)
		var g: = UITheme.glyph_tile(VfxStyle.glyph_for(a), col, 30)
		g.tooltip_text = UITheme.tip("S%d %s · 재사용 대기시간 %s초" % [a.slot, a.name, CodexData.num(a.cooldown)])
		g.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(g)
		var nv: = UITheme.vbox(5)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var top: = UITheme.hbox(8)
		var nl: = UITheme.ellipsize(UITheme.label("S%d  %s" % [a.slot, a.name], "", 13, UITheme.TEXT))
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nl)
		var st: = UITheme.label("", "", 12, UITheme.TEXT_DIM)
		st.add_theme_font_override("font", DB.font_bold)
		top.add_child(st)
		nv.add_child(top)
		var bar: = UITheme.progress(1.0, 1.0, col, 5)
		nv.add_child(bar)
		h.add_child(nv)
		skl.add_child(h)
		skill_rows.append([i, bar, st, col])
	_updaters.append(func() -> void:
		var ku: = runner.sim.u_at(idx)
		if ku == null:
			return
		var silenced: = runner.sim.has_status(ku, &"silence")
		for sr in skill_rows:
			var i2: int = sr[0]
			var ab: Defs.AbilityDef = ku.def.abilities[i2]
			var rem: = maxf(0.0, ku.cooldowns[i2] - runner.sim.time) if i2 < ku.cooldowns.size() else 0.0
			var bar2: ProgressBar = sr[1]
			bar2.value = 1.0 - clampf(rem / maxf(0.1, ab.cooldown), 0.0, 1.0)
			var ready: = rem <= 0.0
			var fill_col: Color = sr[3] if ready else Color(sr[3], 0.45)
			if not bar2.has_meta("_f") or bar2.get_meta("_f") != fill_col:
				bar2.set_meta("_f", fill_col)
				bar2.add_theme_stylebox_override("fill", UITheme.sbc(fill_col, UITheme.CLEAR, UITheme.R_XS, 0, 0, 0))
			var txt: = "준비" if ready else "%.1f초" % rem
			var tc: = UITheme.GOOD if ready else UITheme.TEXT_DIM
			if ku.sealed.has(i2):
				txt = "봉인"
				tc = UITheme.BAD
			elif silenced:
				txt = "침묵"
				tc = UITheme.BAD
			(sr[2] as Label).text = txt
			_col(sr[2], tc))

	if dm:
		var held: Array = sim.deathmatch.held(u)
		tab_body.add_child(_section("보유 아이템", "%d / %d칸" % [held.size(), DeathmatchMode.SLOTS]))
		if br:
			if held.is_empty():
				tab_body.add_child(_hint("아직 아이템이 없습니다. 다운돼도 아이템은 그대로 지니고, 탈락하면 모두 그 자리에 떨어집니다."))
			elif held.size() >= DeathmatchMode.SLOTS:
				tab_body.add_child(_hint("%d칸이 찼습니다. 더 유용한 아이템을 만나면 가장 덜 유용한 것과 바꿉니다." % DeathmatchMode.SLOTS))
		elif held.is_empty():
			tab_body.add_child(_hint("아직 아이템이 없습니다. 쓰러지면 가장 높은 등급 아이템 하나만 떨어뜨리고 나머지는 사라집니다."))
		var hl: = _list(6)
		for held_id in held:
			hl.add_child(_item_row(str(held_id), ""))

	if not u.resources.is_empty():
		tab_body.add_child(_section("자원"))
		var rf: = _flow()
		tab_body.add_child(rf)
		var res_badges: Dictionary = {}
		for k in u.resources:
			var b: = UITheme.badge("", UITheme.ACCENT2, "soft")
			rf.add_child(b)
			res_badges[str(k)] = b
		_updaters.append(func() -> void:
			var ru: = runner.sim.u_at(idx)
			if ru == null:
				return
			for k2 in res_badges:
				var lbl: Label = (res_badges[k2] as Control).get_meta("label")
				lbl.text = "%s %s" % [_resource_label(str(k2)), str(snappedf(float(ru.resources.get(k2, 0)), 0.1))])


func _resource_label(k: String) -> String:
	if CodexData.RESOURCES.has(k):
		return str(CodexData.RESOURCES[k][0])
	return str(RESOURCE_LABELS.get(k, k))


# ---------------------------------------------------------------- effects (statuses + buffs)

func _collect_effects(u: BUnit) -> Array:
	var sim: = runner.sim
	var out: Array = []
	for s in u.statuses:
		# The battleground downed state has its own card (not an effect badge).
		if s.end <= sim.time or s.type == &"downed":
			continue
		var key: = String(s.type)
		out.append({"group": 0, "id": "s:" + key, "key": key, "stacks": s.stacks, "remain": s.end - sim.time})
	var timed: Dictionary = {}
	var perm: Dictionary = {}
	for b in u.buffs:
		if b.end <= sim.time:
			continue
		var stat: = String(b.stat)
		var remain: float = b.end - sim.time
		if remain >= PERMANENT_AFTER:
			if not perm.has(stat):
				perm[stat] = {"group": 2, "id": "p:" + stat, "stat": stat, "amount": 0.0, "sources": []}
			var e: Dictionary = perm[stat]
			e.amount = float(e.amount) + b.amount
			var src: = _buff_source(b.tag)
			if src != "" and not (e.sources as Array).has(src):
				(e.sources as Array).append(src)
		else:
			var k: = stat + "|" + b.tag
			if not timed.has(k):
				timed[k] = {"group": 1, "id": "b:" + k, "stat": stat, "amount": 0.0, "remain": 0.0, "tag": b.tag}
			var e2: Dictionary = timed[k]
			e2.amount = float(e2.amount) + b.amount
			e2.remain = maxf(float(e2.remain), remain)
	out.append_array(timed.values())
	out.append_array(perm.values())
	return out


func _update_effects(idx: int, box: VBoxContainer, st: Dictionary) -> void:
	var u: = runner.sim.u_at(idx)
	if u == null:
		return
	var ents: = _collect_effects(u)
	var ids: = PackedStringArray()
	for e in ents:
		ids.append(str(e.id))
	var key: = "|".join(ids)
	if key != str(st.key):
		st.key = key
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var labels: Dictionary = {}
		st.labels = labels
		if ents.is_empty():
			box.add_child(UITheme.label("적용 중인 효과가 없습니다.", "FaintLabel", 12))
		for g in 3:
			var group: Array = ents.filter(func(e2): return int(e2.group) == g)
			if group.is_empty():
				continue
			var gv: = UITheme.vbox(5)
			gv.add_child(UITheme.label(["상태", "강화 · 약화", "영구 강화 (아이템·성장)"][g], "FaintLabel", 12))
			var f: = _flow(5)
			for e in group:
				var b: = _effect_badge(e)
				f.add_child(b)
				labels[str(e.id)] = b.get_meta("label")
			gv.add_child(f)
			box.add_child(gv)
	var lbls: Dictionary = st.labels
	for e in ents:
		var l: Label = lbls.get(str(e.id))
		if l:
			l.text = _effect_text(e)


func _effect_badge(e: Dictionary) -> PanelContainer:
	var col: Color
	var tip: String
	if int(e.group) == 0:
		var key: = str(e.key)
		var icon: Array = VfxStyle.status_icon(key)
		col = CodexData.term_color(key, Color(str(icon[1])))
		tip = _status_tip(key)
	else:
		var stat: = str(e.stat)
		if stat in BUFF_FLAGS:
			col = UITheme.ACCENT2
		else:
			var good: = float(e.amount) >= 0.0
			if stat in BUFF_INVERTED:
				good = not good
			col = UITheme.GOOD if good else UITheme.BAD
		tip = _buff_tip(e)
	return UITheme.badge(_effect_text(e), col, "soft", tip)


func _effect_text(e: Dictionary) -> String:
	match int(e.group):
		0:
			var key: = str(e.key)
			var icon: String = str(VfxStyle.status_icon(key)[0])
			var remain: float = float(e.remain)
			return "%s %s%s%s" % [icon, DB.status_label(key), (" ×%d" % int(e.stacks)) if int(e.stacks) > 1 else "", (" %.1f초" % remain) if remain < PERMANENT_AFTER else ""]
		1:
			var amt: = _buff_amount(str(e.stat), float(e.amount))
			return "%s%s · %.1f초" % [_buff_label(str(e.stat)), (" " + amt) if amt != "" else "", float(e.remain)]
	var amt2: = _buff_amount(str(e.stat), float(e.amount))
	return "%s%s" % [_buff_label(str(e.stat)), (" " + amt2) if amt2 != "" else ""]


func _buff_label(stat: String) -> String:
	return str(BUFF_LABELS.get(stat, "고유 효과"))


## Ratio buffs -> "+12%", "...Flat" -> "+18", regen -> "초당 +14", flags -> "".
func _buff_amount(stat: String, amount: float) -> String:
	if stat in BUFF_FLAGS:
		return ""
	if stat == "regen":
		return "초당 %+.0f" % amount
	if stat == "projectileGuard":
		return "%d%%" % roundi(amount * 100.0)
	if stat.ends_with("Flat"):
		return "%+.0f" % amount
	return "%+.0f%%" % (amount * 100.0)


func _buff_tip(e: Dictionary) -> String:
	var stat: = str(e.stat)
	var text: String
	if stat == "projectileGuard":
		text = str(CodexData.status("projectile_guard").get("desc", "받는 투사체 피해가 줄어듭니다."))
	elif BUFF_TIPS.has(stat):
		text = str(BUFF_TIPS[stat])
	elif stat in BUFF_FLAGS:
		text = "고유 스킬 효과가 발동 중입니다. 자세한 내용은 전투 도감의 스킬 설명을 참고해 주세요."
	elif stat.ends_with("Flat"):
		text = "%s에 고정 수치로 더해지는 강화·약화입니다." % _buff_label(stat)
	elif stat in RATIO_STATS:
		text = "기본 %s에 비율로 더해지는 강화·약화입니다." % _buff_label(stat)
	else:
		text = "고유 효과입니다 (%s)." % stat
	var lines: = PackedStringArray([_buff_label(stat) + " — " + text])
	if int(e.group) == 2:
		if not (e.sources as Array).is_empty():
			lines.append("출처: " + ", ".join(PackedStringArray(e.sources)))
		lines.append("지속 시간 없이 계속 적용됩니다.")
	else:
		var src: = _buff_source(str(e.get("tag", "")))
		if src != "":
			lines.append("출처: " + src)
	return "\n".join(lines)


func _status_tip(key: String) -> String:
	if STATUS_TIPS.has(key):
		return str(STATUS_TIPS[key])
	var d: Dictionary = CodexData.status(key)
	if not d.is_empty():
		return "%s — %s" % [str(d.label), str(d.desc)]
	return "%s 상태입니다." % DB.status_label(key)


## Human-readable buff source from its tag (items, growth, abilities).
func _buff_source(tag: String) -> String:
	if tag.begins_with("item:"):
		return str(ItemDefs.get_def(tag.substr(5)).get("name", tag.substr(5)))
	if tag.begins_with("item_"):
		return "아이템 효과"
	match tag:
		"":
			return ""
		"permanentGrowth":
			return "영구 성장"
		"propaganda":
			return "선전"
		"passive_cast":
			return "패시브"
		"statSwap":
			return "능력치 뒤집기"
		"guard":
			return "투사체 방어"
	if tag.begins_with("theft:"):
		return "능력치 약탈"
	if tag.begins_with("bed"):
		return "사랑의 침대"
	for c in DB.characters:
		for a in (c as Defs.CharDef).abilities:
			if (a as Defs.AbilityDef).id == tag:
				return (a as Defs.AbilityDef).name
	return ""


# ---------------------------------------------------------------- enemy (observed) view

func _panel_enemy_belief(u: BUnit) -> void:
	var sim: = runner.sim
	var ctl = sim.controllers[view.perspective]
	tab_body.add_child(_section("상대 관측", "이 시점의 팀이 아는 정보"))
	tab_body.add_child(_hint("관측하거나 전달받은 정보만 표시합니다. 추정치는 오래되었거나 부정확할 수 있습니다.",
		"적의 현재 의도와 자원은 비공개입니다. 정보 취득 스킬로 확보한 항목은 취득 당시의 값만 표시합니다. 추론 과정은 'AI 판단' 탭에서 볼 수 있습니다."))
	if ctl == null or not ("intel" in ctl) or ctl.intel == null:
		tab_body.add_child(_empty("?", "관측 기록이 없습니다", "이 AI는 관측 기록을 제공하지 않습니다."))
		return
	var intel: TeamIntel = ctl.intel
	var b: TeamIntel.EnemyBelief = intel.enemies.get(u.idx)
	if b == null:
		tab_body.add_child(_empty("?", "아직 관측 정보가 없습니다", "이 팀은 아직 이 영웅을 보지 못했습니다."))
		return
	# Observation state ("현재 관측 중" / last seen) is shown in the pinned card above.
	var tiles: = UITheme.hbox(6)
	for t in [UITheme.stat_tile("추정 체력", "%d / %d" % [int(b.hp), int(b.max_hp)]), UITheme.stat_tile("위치 확신", "%d%%" % int(b.confidence * 100.0), UITheme.ACCENT)]:
		(t as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	tab_body.add_child(tiles)
	tab_body.add_child(_section("스킬 준비 추정", "준비 확률"))
	var sl: = _list()
	for i in b.def.abilities.size():
		var ability: Defs.AbilityDef = b.def.abilities[i]
		var p: = float(intel.ready_prob(b, i))
		sl.add_child(_score_row(false, "S%d  %s" % [ability.slot, ability.name], p, "%d%%" % int(p * 100.0), VfxStyle.color_for(ability)))
	for event_i in range(sim.log.size() - 1, -1, -1):
		var intel_event: Dictionary = sim.log[event_i]
		if sim.time - float(intel_event.get("t", 0.0)) > 10.0:
			break
		if str(intel_event.get("type", "")) != "INFO_REVEAL" or int(intel_event.get("g", -1)) != u.idx or int(intel_event.get("team", -1)) != view.perspective:
			continue
		if sim.time - float(intel_event.get("t", 0.0)) <= float(intel_event.get("duration", 5.0)):
			tab_body.add_child(_section("취득한 정보"))
			tab_body.add_child(UITheme.wrap_label(_disclosure_value(intel_event), "", 13, Color("#f5b0d4")))
			break


func _disclosure_value(ev: Dictionary) -> String:
	var field: = str(ev.get("field", ""))
	var value = ev.get("value")
	match field:
		"position":
			if value is Vector2:
				return "취득 당시 위치 (%.0f, %.0f)" % [value.x, value.y]
		"health":
			if value is Dictionary:
				return "취득 당시 체력 %d / %d" % [int(value.get("hp", 0)), int(value.get("max_hp", 0))]
		"cooldowns":
			if value is Array or value is PackedFloat64Array:
				var parts: Array = []
				for i in value.size():
					parts.append("S%d %.1f초" % [i + 1, maxf(0.0, float(value[i]) - float(ev.get("t", 0.0)))])
				return "취득 당시 재사용 · " + " / ".join(parts)
	return "정보 취득 기록"


# ================================================================== tab: team AI

func _stance_label(s: String) -> String:
	return {"ENGAGE": "진입", "POKE": "견제", "DISENGAGE": "후퇴", "SCOUT": "정찰"}.get(s, s)


func _panel_ai() -> void :
	var sim: = runner.sim
	var su: = sim.u_at(view.selected)
	var team: = view.perspective
	if team < 0:
		team = su.team if su else 0
	team = clampi(team, 0, sim.controllers.size() - 1)
	var ctl = sim.controllers[team]
	tab_body.add_child(_hint("%s AI의 판단입니다. 자기 시야와 관측한 사건만으로 적을 추정합니다." % DB.TEAM_NAMES[clampi(team, 0, 1)],
		"정확한 적 재사용 대기시간과 위치는 공개되지 않습니다. 시점을 바꾸면 그 팀이 실제로 아는 정보만 보입니다."))
	if ctl == null or not ctl.has_method("explain") or not ("plan" in ctl):
		tab_body.add_child(_empty("◈", "판단 설명이 없는 AI입니다", "기본 AI는 판단 과정을 기록하지 않습니다."))
		return
	var plan: Dictionary = ctl.plan
	if sim.is_control_mode():
		_panel_control_plan(plan.get("control", {}), su, team)
	var distrust: = int(sim.warfare.distrust[team])
	if distrust > 0:
		tab_body.add_child(UITheme.badge("정보 불신 %d / 10%s" % [distrust, " · 추가 가짜 뉴스 거부" if distrust >= 10 else ""], Color("#d6b979"), "soft", str(CodexData.status("distrust").get("desc", ""))))

	# Summary card: stance, advantage bar, pressure chips, reason.
	var stance: = str(plan.get("stance", ""))
	var adv: = float(plan.get("adv", 0.0))
	var cv: = UITheme.vbox(8)
	var sh: = UITheme.hbox(14)
	var sl: = UITheme.label(_stance_label(stance), "", 24, {"ENGAGE": UITheme.BAD, "POKE": UITheme.GOLD, "DISENGAGE": UITheme.ACCENT, "SCOUT": UITheme.GOOD}.get(stance, UITheme.TEXT))
	sl.add_theme_font_override("font", DB.font_black)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(sl)
	var sv: = UITheme.vbox(4)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sv.add_child(UITheme.label("교전 우세 %+.2f" % adv, "CaptionLabel", 12))
	var bar: = AdvBar.new()
	bar.value = adv
	bar.custom_minimum_size = Vector2(0, 8)
	bar.tooltip_text = UITheme.tip("가운데 선보다 오른쪽(초록)이면 우리 팀이 교전에서 유리하다고 판단합니다.")
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(bar)
	sh.add_child(sv)
	cv.add_child(sh)
	var chipf: = _flow(5)
	chipf.add_child(UITheme.badge("체력 합 %+.0f%%" % (float(plan.get("lead", 0.0)) * 100.0), UITheme.TEXT_DIM, "soft", "양 팀의 남은 체력 합 차이입니다."))
	chipf.add_child(UITheme.badge("시간 압박 %.0f%%" % (float(plan.get("pressure", 0.0)) * 100.0), UITheme.TEXT_DIM, "soft", "남은 시간이 줄수록 커지며, 높을수록 적극적으로 싸웁니다."))
	if float(plan.get("stale", 0.0)) > 0.05:
		chipf.add_child(UITheme.badge("교착 %.0f%%" % (float(plan.get("stale", 0.0)) * 100.0), UITheme.WARN, "soft", "결판이 나지 않는 시간이 길어질수록 커집니다."))
	if float(plan.get("nokill", 0.0)) > 0.05:
		chipf.add_child(UITheme.badge("무처치 %.0f%%" % (float(plan.get("nokill", 0.0)) * 100.0), UITheme.WARN, "soft", "처치 없이 흐른 시간이 길수록 커집니다."))
	cv.add_child(chipf)
	var why: = str(plan.get("why", ""))
	if why != "":
		cv.add_child(UITheme.wrap_label("판단 근거 · " + why, "FaintLabel", 12))
	tab_body.add_child(_card(cv))

	var op: = str(plan.get("op", ""))
	var opv: = UITheme.vbox(4)
	var op_row: Dictionary = _kv("작전", op, {"고립 적 집중": UITheme.BAD, "제어 연계 집중": UITheme.GOLD, "후열 보호": UITheme.ACCENT, "집결 대기": UITheme.TEXT_DIM, "진입": UITheme.BAD}.get(op, UITheme.TEXT))
	(op_row.value as Label).add_theme_font_override("font", DB.font_bold)
	opv.add_child(op_row.row)
	var ln: Array = plan.get("local_n", [0.0, 0.0])
	if bool(plan.get("contact", false)) and ln.size() == 2:
		opv.add_child((_kv("국지전", "%.1f 대 %.1f · 국지 우세 %+.2f" % [float(ln[0]), float(ln[1]), float(plan.get("local_adv", 0.0))], UITheme.TEXT_DIM)).row)
	var fu: = sim.u_at(int(plan.get("focus", -1)))
	if fu:
		opv.add_child((_kv("집중 대상", fu.def.name, UITheme.team_color(fu.team).lightened(0.2))).row)
	tab_body.add_child(opv)

	var comp: Dictionary = plan.get("comp", {})
	if not comp.is_empty():
		var al: Dictionary = TacticianBrain.ARCH_LABEL
		tab_body.add_child(_section("조합 계획", "상대: %s" % al.get(str(comp.enemy_primary), "")))
		var cl: = _list(3)
		cl.add_child(UITheme.wrap_label("%s + %s" % [al.get(str(comp.primary), ""), al.get(str(comp.secondary), "")], "BodyLabel", 13))
		for o in comp.get("orders", []):
			cl.add_child(UITheme.wrap_label("· " + str(o), "CaptionLabel", 13))

	if ctl.has_method("role_of"):
		var rf: = _flow(5)
		for a in sim.heroes:
			if a.alive and a.team == team:
				rf.add_child(UITheme.badge("%s · %s" % [a.def.name, ctl.role_of(a.idx)], UITheme.team_color(team), "soft"))
		if rf.get_child_count() > 0:
			tab_body.add_child(_section("역할"))
			tab_body.add_child(rf)

	if su and su.alive and sim.eteam(su) == team:
		var ex: Dictionary = ctl.explain(su)
		tab_body.add_child(_section("%s의 판단" % su.def.name, "현재 위치 위험도 %.0f" % float(ex.get("danger", 0.0))))
		var control_ex: Dictionary = ex.get("control", {})
		if str(control_ex.get("heal_target", "")) not in ["", "-1"]:
			tab_body.add_child(UITheme.wrap_label("회복 구역 판단 · " + str(control_ex.get("heal_reason", "")), "CaptionLabel", 13))
		var coordination: Dictionary = ex.get("coordination", {})
		if not coordination.is_empty():
			var committed = coordination.get("committed_damage", {})
			var committed_total: = 0.0
			if committed is Dictionary:
				for amount in committed.values():
					committed_total += float(amount)
			elif committed is float or committed is int:
				committed_total = float(committed)
			var cf: = _flow(5)
			cf.add_child(UITheme.badge("위험 예산 %.0f%%" % (float(coordination.get("risk_budget", 0.0)) * 100.0), UITheme.TEXT_DIM, "soft", "감수할 수 있는 위험의 크기입니다."))
			cf.add_child(UITheme.badge("불확실성 %.0f%%" % (float(coordination.get("uncertainty", 0.0)) * 100.0), UITheme.TEXT_DIM, "soft", "적 위치·쿨다운 추정이 얼마나 불확실한지입니다."))
			cf.add_child(UITheme.badge("팀 예약 피해 %.0f" % committed_total, UITheme.TEXT_DIM, "soft", "팀원들이 이미 맡기로 한 피해량입니다."))
			if bool(coordination.get("gamble", false)):
				cf.add_child(UITheme.badge("승부수 선택", UITheme.WARN, "strong"))
			if int(coordination.get("scout", -1)) == su.idx:
				cf.add_child(UITheme.badge("정찰 담당", UITheme.GOOD, "soft"))
			tab_body.add_child(cf)
		var learning: Dictionary = ex.get("learning", {})
		if not learning.is_empty():
			var bias: = float(learning.get("strafe_bias", 0.0))
			var tendency: = "중립" if absf(bias) < 0.12 else ("좌측" if bias < 0.0 else "우측")
			tab_body.add_child(UITheme.wrap_label("성향 학습 · 관측 %d회 · 적 공격성 %.0f%% · 회피 %s · 집중 대상 확신 %.0f%%" % [int(learning.get("observations", 0)), float(learning.get("aggression", 0.0)) * 100.0, tendency, float(learning.get("focus_confidence", 0.0)) * 100.0], "FaintLabel", 12))
		var doc: Dictionary = ex.get("doctrine", {})
		if not doc.is_empty():
			var dv: = UITheme.vbox(3)
			dv.add_child(UITheme.label("교리 · %s  %s" % [str(doc.get("code", "")), str(doc.get("title", ""))], "EyebrowLabel", 12, su.def.accent.lightened(0.3)))
			for pl in doc.get("principles", []):
				dv.add_child(UITheme.wrap_label("· " + str(pl), "CaptionLabel", 13))
			tab_body.add_child(_card(dv, su.def.accent))
		var top: Array = ex.get("top", [])
		if not top.is_empty():
			tab_body.add_child(_section("후보 행동", "가치 = HP 환산"))
			var best: = 1.0
			for c in top:
				best = maxf(best, absf(float(c.score)))
			var tl: = _list(8)
			for i in top.size():
				var c: Dictionary = top[i]
				var cv2: = UITheme.vbox(2)
				tl.add_child(cv2)
				cv2.add_child(_score_row(i == 0, str(c.label), absf(float(c.score)) / best, "%.0f" % float(c.score), UITheme.GOLD if i == 0 else UITheme.TEXT_DIM))
				var parts: Dictionary = c.get("parts", {})
				if not parts.is_empty() and i < 3:
					var ps: Array = []
					for k in parts:
						var pv = parts[k]
						if pv is float or pv is int:
							ps.append("%s %s" % [k, ("%.0f%%" % (float(pv) * 100.0)) if k == "명중" else ("%.0f" % float(pv))])
					cv2.add_child(UITheme.margin(UITheme.wrap_label(" · ".join(ps), "FaintLabel", 12), 20, 0, 0, 0))
				var notes: Array = c.get("notes", [])
				if not notes.is_empty() and i < 3:
					cv2.add_child(UITheme.margin(UITheme.wrap_label("↳ " + " · ".join(notes.slice(0, 4)), "", 12, UITheme.GOLD.darkened(0.1)), 20, 0, 0, 0))

	var intel: TeamIntel = ctl.intel
	tab_body.add_child(_section("적 추정", "팀 기억"))
	for k in intel.enemies:
		var b: TeamIntel.EnemyBelief = intel.enemies[k]
		var box: = UITheme.vbox(6)
		var hh: = UITheme.hbox(8)
		var d2: = GlyphDisc.new(b.def, 30, 1 - team)
		d2.set_state(b.hp / maxf(1.0, b.max_hp), 0.0, b.dead)
		hh.add_child(d2)
		var status: = "사망" if b.dead else ("보임" if b.visible else "%.1f초 전 목격 · 확신 %d%%" % [sim.time - b.last_seen_t, int(b.confidence * 100.0)])
		if b.controlled_by_us and not b.dead:
			status = "조종 중"
		var nv: = UITheme.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nv.add_child(UITheme.label(b.def.name, "BoldLabel", 13, UITheme.TEXT if b.visible else UITheme.TEXT_DIM))
		nv.add_child(UITheme.label(status, "FaintLabel", 12))
		hh.add_child(nv)
		var dodge: = UITheme.label("회피 %d%%" % int(b.dodge_rate() * 100.0), "FaintLabel", 12)
		dodge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hh.add_child(dodge)
		box.add_child(hh)
		if not b.dead:
			var cds: = UITheme.hbox(4)
			for i in b.def.abilities.size():
				var a: Defs.AbilityDef = b.def.abilities[i]
				var p: = float(intel.ready_prob(b, i))
				var cell: = ReadyPip.new()
				cell.prob = p
				cell.col = VfxStyle.color_for(a)
				cell.glyph = VfxStyle.glyph_for(a)
				cell.seen = b.cd_last[i] > -100.0
				cell.custom_minimum_size = Vector2(0, 22)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cell.tooltip_text = UITheme.tip("%s · 준비 확률 %d%%%s" % [a.name, int(p * 100.0), " (관측한 시전 기준)" if cell.seen else " (미관측: 도감 재사용 대기시간 가정)"])
				cds.add_child(cell)
			box.add_child(cds)
		tab_body.add_child(UITheme.styled_panel(UITheme.sbc(Color(1, 1, 1, 0.02), UITheme.LINE, UITheme.R_M, 1, 10, 8), box))
	tab_body.add_child(_hint("관측한 시전 %d · 익명 피격 추론 %d · 쿨다운 공개 %d" % [intel.casts_observed, intel.anonymous_hits, intel.disclosures]))


func _name_for(i: int, team_view: int) -> String:
	var u: = runner.sim.u_at(i)
	if u == null:
		return "환경"
	if team_view >= 0 and u.team != team_view and not runner.sim.is_seen(team_view, u):
		return "[color=#8593ae]보이지 않는 적[/color]"
	return "[color=#%s]%s[/color]" % [UITheme.team_color(u.team).lightened(0.25).to_html(false), u.def.name]


func _panel_control_plan(control: Dictionary, selected_unit: BUnit, team: int) -> void:
	if not bool(control.get("enabled", false)):
		return
	var box: VBoxContainer = UITheme.vbox(6)
	box.add_child(UITheme.label("거점 전략", "EyebrowLabel", 12, UITheme.GOLD))
	var scores: Array = control.get("score", [0, 0])
	box.add_child(UITheme.label("아군 %d : %d 상대 · 목표 %d점" % [int(scores[0]), int(scores[1]), int(control.get("target_score", 300))], "BoldLabel", 14, UITheme.GOLD))
	var eta: float = float(control.get("score_eta", INF))
	var enemy_eta: float = float(control.get("enemy_score_eta", INF))
	var scoring: Array = [0, 0]
	for p in control.get("points", []):
		if int(p.get("owner", -1)) >= 0 and not bool(p.get("contested", false)):
			scoring[int(p.owner)] += 1
	var ours: String = "득점 거점 필요" if scoring[team] == 0 or not is_finite(eta) or eta > 9999 else "%.0f초" % maxf(0, eta)
	var theirs: String = "득점 거점 없음" if scoring[1 - team] == 0 or not is_finite(enemy_eta) or enemy_eta > 9999 else "%.0f초" % maxf(0, enemy_eta)
	var eta_l: = UITheme.wrap_label("목표 도달 예상 · 아군 %s / 상대 %s" % [ours, theirs], "CaptionLabel", 13)
	eta_l.tooltip_text = UITheme.tip("현재 점령 상태가 유지된다고 가정한 예상 시간입니다.")
	eta_l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(eta_l)
	for point in control.get("points", []):
		var owner: int = int(point.get("owner", -1))
		var owner_text: String = "중립" if owner < 0 else ("아군" if owner == team else "상대")
		var row: = UITheme.hbox(8)
		var col: = UITheme.TEXT_FAINT if owner < 0 else UITheme.team_color(owner)
		row.add_child(UITheme.badge(str(point.get("label", point.get("id", ""))), col, "strong"))
		var pl: = UITheme.wrap_label("%s%s · 배정 %d명 / 관측 적 %d명" % [owner_text, " · 경합" if bool(point.get("contested", false)) else "", int(point.get("ours_assigned", 0)), int(point.get("enemy_observed", 0))], "CaptionLabel", 13)
		row.add_child(pl)
		box.add_child(row)
	var assignments: Dictionary = control.get("assignments", {})
	if selected_unit and selected_unit.team == team:
		var assignment: Dictionary = assignments.get(selected_unit.idx, {})
		if not assignment.is_empty():
			box.add_child(UITheme.wrap_label("%s → %s · %s" % [selected_unit.def.name, str(assignment.get("label", "")), str(assignment.get("role", ""))], "BodyLabel", 13))
			box.add_child(UITheme.wrap_label(str(assignment.get("reason", "")), "FaintLabel", 12))
	box.add_child(_hint("관측 적은 현재 시야로 확인한 인원입니다."))
	tab_body.add_child(_card(box, UITheme.GOLD))


# ================================================================== tab: event log

func _build_log_filters(control: bool) -> void:
	for c in log_filters.get_children():
		log_filters.remove_child(c)
		c.queue_free()
	var opts: Array = [["all", "전체", "모든 기록을 봅니다."], ["kill", "처치", "처치·사망·부활만 봅니다."],
		["skill", "스킬", "스킬 시전·군중 제어·정보전 기록만 봅니다."], ["damage", "피해", "피해·회복·보호막 기록만 봅니다."]]
	if dm:
		opts.append(["item", "아이템", "아이템 획득·드롭·발동만 봅니다."])
	elif control:
		opts.append(["objective", "거점", "거점 점령·경합·회복 구역 기록만 봅니다."])
	if _arena_has_env():
		opts.append(["env", "환경", "환경 기믹(성문·포격·결계·도약 발판 등) 기록만 봅니다."])
	log_filter = "all"
	var seg: = UITheme.segmented(opts, "all", func(id): log_filter = str(id); _panel_log(true))
	log_filters.add_child(seg)


func _arena_has_env() -> bool:
	var a: Arena = runner.sim.arena if runner and runner.sim else null
	return a != null and (not a.hazards.is_empty() or not a.gates.is_empty())


func _log_cat(ty: String) -> String:
	return str(LOG_CATS.get(ty, "skill"))


func _log_pass(ev: Dictionary, persp: int) -> bool:
	var ty: = str(ev.get("type", ""))
	if log_filter == "env":
		if not ty.begins_with("ENV_") and not ty.begins_with("BR_ZONE"):
			return false
	elif log_filter != "all" and _log_cat(ty) != log_filter:
		return false
	if persp >= 0 and ty not in PUBLIC_LOG and not CodexText.ENV_PUBLIC_LOG.has(ty) and ev.has("sv") and not (bool(ev.sv[persp]) or bool(ev.gv[persp])):
		return false
	return true


func _panel_log(force: bool) -> void :
	var sim: = runner.sim
	var persp: = view.perspective
	if force or _log_lines > LOG_CAP:
		log_rt.clear()
		_log_lines = 0
		# Start so that about LOG_KEEP matching events are shown.
		var start: = sim.log.size()
		var kept: = 0
		while start > 0 and kept < LOG_KEEP:
			start -= 1
			if _log_pass(sim.log[start], persp):
				kept += 1
		log_seen = start
	var fc: = UITheme.TEXT_FAINT.to_html(false)
	while log_seen < sim.log.size():
		var ev: Dictionary = sim.log[log_seen]
		log_seen += 1
		if not _log_pass(ev, persp):
			continue
		var line: = _fmt_event(ev, persp)
		if line != "":
			log_rt.append_text("[color=#%s]%s[/color]  %s\n" % [fc, UITheme.fmt_time(float(ev.t)), line])
			_log_lines += 1


func _fmt_event(ev: Dictionary, persp: int) -> String:
	var ty: = str(ev.type)
	var s: = int(ev.get("s", -1))
	var g: = int(ev.get("g", -1))
	if ty.begins_with("ENV_"):
		return CodexText.env_log(ev, _name_for(g, persp), runner.sim.deathmatch != null)
	var ab = ev.get("ability")
	var an: String = (ab as Defs.AbilityDef).name if ab is Defs.AbilityDef else ""
	match ty:
		"CONTROL_CAPTURED", "CONTROL_NEUTRALIZED":
			return "[color=#f4c96b]거점 %s · %s 팀 %s[/color]" % [str(ev.get("point_id", "")), "청" if int(ev.get("team", 0)) == 0 else "홍", "점령" if ty == "CONTROL_CAPTURED" else "중립화"]
		"CONTROL_CONTESTED":
			return "[color=#f4c96b]거점 %s · 경합 %s[/color]" % [str(ev.get("point_id", "")), "시작 · 득점 정지" if bool(ev.get("contested", false)) else "종료"]
		"RESPAWN_SCHEDULED":
			return "%s · %d초 뒤 전장 복귀" % [_name_for(g, persp), int(round(float(ev.get("respawn_at", float(ev.t) + 12.0)) - float(ev.t)))]
		"DM_KILL" when br != null:
			# Battleground: no kill score; the cause and (solo) the final place instead.
			var cause_text: String = {"zone": " · 자기장", "bleed": " · 출혈", "team_wipe": " · 팀 전멸", "hazard": " · 환경"}.get(str(ev.get("cause", "")), "")
			var place_text: String = (" · %d위" % int(br.placement[int(ev.get("team", -1))])) if br.squad <= 1 and br.placement.has(int(ev.get("team", -1))) else ""
			if int(ev.get("killer", -1)) < 0:
				return "[color=#ff6d79][b]✝ %s 사망[/b][/color]%s%s" % [_name_for(g, -1), cause_text, place_text]
			return "[color=#ff6d79][b]✝ %s → %s 처치[/b][/color]%s%s" % [_name_for(s, -1), _name_for(g, -1), cause_text, place_text]
		"BR_DOWNED":
			return "[color=#ff8a8a][b]▲ %s → %s 다운[/b][/color] · 출혈 %d초%s" % [_name_for(s, persp) if s >= 0 else "[color=#cf9bff]자기장[/color]" if bool(ev.get("zone", false)) else "환경", _name_for(g, persp), int(float(ev.get("bleed_total", 30.0))), (" · %d번째" % int(ev.get("count", 1))) if int(ev.get("count", 1)) > 1 else ""]
		"BR_REVIVE_START":
			return "%s → %s [color=#6fe0a2]소생 시작[/color]" % [_name_for(s, persp), _name_for(g, persp)]
		"BR_REVIVE_CANCEL":
			var why: String = {"damage": "피격", "range": "거리 이탈", "cc": "군중 제어", "reviver_down": "소생자 다운", "bled_out": "출혈 사망", "target_died": "대상 사망"}.get(str(ev.get("reason", "")), "중단")
			return "%s → %s [color=#a9b6cc]소생 끊김 · %s[/color]" % [_name_for(s, persp), _name_for(g, persp), why]
		"BR_REVIVED":
			return "[color=#6fe0a2][b]✚ %s → %s 소생[/b][/color]" % [_name_for(s, persp), _name_for(g, persp)]
		"BR_BLED_OUT":
			return "%s [color=#ff8a8a]출혈로 쓰러짐[/color]" % _name_for(g, persp)
		"BR_TEAM_OUT":
			if br == null or br.squad <= 1:
				return ""
			return "[color=#ff6d79][b]☠ %s 탈락[/b][/color] · %d위" % [br.team_label(int(ev.get("team", -1))), int(ev.get("place", 0))]
		"BR_ZONE_ANNOUNCE":
			return "[color=#cf9bff][b]◉ 자기장 %d/%d 예고[/b] · %s 뒤 수축 · %s[/color]" % [int(ev.get("phase", 0)), BrZone.PHASES, UITheme.fmt_time(maxf(0.0, float(ev.get("shrink_start", 0.0)) - float(ev.get("t", 0.0)))), ZonePill.dps_text(float(ev.get("dps_ratio", 0.0)))]
		"BR_ZONE_SHRINK":
			return "[color=#cf9bff][b]◉ 자기장 %d/%d 수축 시작[/b] · %s 동안 · %s[/color]" % [int(ev.get("phase", 0)), BrZone.PHASES, UITheme.fmt_time(maxf(0.0, float(ev.get("shrink_end", 0.0)) - float(ev.get("t", 0.0)))), ZonePill.dps_text(float(ev.get("dps_ratio", 0.0)))]
		"BR_ELIMINATED", "BR_ITEM_SWAP":
			return ""
		"DM_KILL":
			var streak_n: int = int(ev.get("streak", 0))
			var assists_n: int = (ev.get("assists", []) as Array).size()
			if int(ev.get("killer", -1)) < 0:
				return "[color=#ff6d79][b]✝ %s 사망[/b][/color]" % _name_for(g, -1)
			return "[color=#ff6d79][b]✝ %s → %s 처치[/b][/color] · %d킬%s%s" % [_name_for(s, -1), _name_for(g, -1), int(ev.get("score", 0)), (" · [color=#f4c96b]%d연속[/color]" % streak_n) if streak_n >= 2 else "", (" · 도움 %d" % assists_n) if assists_n > 0 else ""]
		"DM_ITEM_PICKED":
			var item_id: String = str(ev.get("item", ""))
			return "%s [color=#%s]획득 · %s[/color] — %s" % [_name_for(s, persp), ItemDefs.rarity_color(ItemDefs.rarity_of(item_id)).to_html(false), str(ItemDefs.get_def(item_id).get("name", item_id)), str(ev.get("reason", "")).get_slice(" — ", 1)]
		"DM_ITEM_DROPPED":
			var drop_id: String = str(ev.get("item", ""))
			return "%s [color=#%s]%s · %s[/color]" % [_name_for(s, persp), ItemDefs.rarity_color(ItemDefs.rarity_of(drop_id)).to_html(false), "사망 드롭" if str(ev.get("reason", "")) == "death" else "교체로 내려놓음", str(ItemDefs.get_def(drop_id).get("name", drop_id))]
		"DM_ITEM_PROC":
			var proc_id: String = str(ev.get("item", ""))
			var what: String = {"cleanse": "제어 무효", "splash": "광역 타격", "lightning": "벼락", "shield": "보호막", "hunt": "처치 회복·가속", "refund": "재사용 대기 감소"}.get(str(ev.get("kind", "")), "발동")
			return "%s [color=#%s]%s · %s[/color]" % [_name_for(s, persp), ItemDefs.rarity_color(ItemDefs.rarity_of(proc_id)).to_html(false), str(ItemDefs.get_def(proc_id).get("name", proc_id)), what]
		"DM_REVIVE":
			return "%s [color=#ffb08a][b]불사조 깃털 · 되살아남[/b][/color]" % _name_for(g, persp)
		"HERO_RESPAWNED":
			return "%s · 부활 · 2초 보호" % _name_for(g, persp)
		"HEAL_ZONE_USED":
			return "%s · 회복 구역 [color=#7dffb0]+%d[/color] · 공용 대기 25초" % [_name_for(g, persp), int(ev.get("amount", 0))]
		"HEALTH_DAMAGED":
			var amt: = float(ev.get("amount", 0.0))
			if amt < 1.0:
				return ""
			var sc: String = {"physical": "#ffd2a8", "magic": "#c9b3ff", "true": "#ffffff"}.get(str(ev.get("school", "physical")), "#ffffff")
			var how: = an if an != "" else ("기본 공격" if bool(ev.get("basic", false)) else "")
			return "%s → %s %s [color=%s][b]%d[/b][/color]%s" % [_name_for(s, persp), _name_for(g, persp), how, sc, int(amt), " [color=#f4c96b]치명[/color]" if ev.get("crit", false) else ""]
		"HEAL_APPLIED":
			var amt2: = float(ev.get("amount", 0.0))
			if amt2 < 5.0:
				return ""
			return "%s → %s [color=#7dffb0]+%d 회복[/color]" % [_name_for(s, persp), _name_for(g, persp), int(amt2)]
		"SHIELD_APPLIED":
			return "%s → %s [color=#dfe8ff]보호막 %d[/color]" % [_name_for(s, persp), _name_for(g, persp), int(float(ev.get("amount", 0.0)))]
		"CC_APPLIED":
			return "%s → %s [color=#ffb45e]%s %.1f초[/color]" % [_name_for(s, persp), _name_for(g, persp), DB.status_label(str(ev.get("status", ""))), float(ev.get("duration", 0.0))]
		"DEATH", "EXECUTED":
			return "[color=#ff6d79][b]✝ %s 처치[/b][/color] ← %s%s" % [_name_for(g, persp), _name_for(s, persp), " (처형)" if ty == "EXECUTED" else ""]
		"CAST_STARTED":
			if an == "" or (ab as Defs.AbilityDef).virtual:
				return ""
			return "%s [color=#%s]%s[/color]" % [_name_for(s, persp), VfxStyle.color_for(ab).to_html(false), an]
		"SUMMON_CREATED":
			return "%s 소환" % _name_for(s, persp)
		"PASSIVE":
			return "%s [color=#a9b6cc]패시브 · %s[/color]" % [_name_for(s, persp), str(ev.get("detail", ""))]
		"SKILLS_SEALED":
			return "%s → %s [color=#ff9ad0]스킬 봉인 %s[/color]" % [_name_for(s, persp), _name_for(g, persp), str(ev.get("slots", []))]
		"PROJECTILE_REFLECTED":
			return "%s [color=#bfe9ff]투사체 반사[/color]" % _name_for(s, persp)
		"PROJECTILE_BLOCKED":
			return "%s [color=#bfe9ff]투사체 차단[/color]" % _name_for(s, persp)
		"GARDEN_CLOSED":
			return "%s [color=#9ff0c5]재생 영역 완성[/color]" % _name_for(s, persp)
		"CHAMBER_STARTED":
			return "%s → %s [color=#ff9ad0]밀실 격리[/color]" % [_name_for(s, persp), _name_for(g, persp)]
		"PRISON_CREATED":
			return "%s → %s [color=#ff9ad0]감금 · 원통형 벽 생성[/color]" % [_name_for(s, persp), _name_for(g, persp)]
		"PRISON_ENDED":
			return "[color=#e789ba]감금 벽 소멸[/color]"
		"CONTEMPLATION":
			return "%s [color=#ecd998]관조 %s[/color]" % [_name_for(s, persp), "시작 · CC 면역" if bool(ev.get("active", false)) else "해제"]
		"FAKE_NEWS":
			var speaker: = runner.sim.u_at(s)
			if persp >= 0 and speaker and runner.sim.eteam(speaker) != persp:
				return "%s [color=#d6b979]정보 전달[/color]" % _name_for(s, persp)
			return "%s [color=#d6b979]가짜 뉴스 · 상대 불신 %d/10%s[/color]" % [_name_for(s, persp), int(ev.get("distrust", 0)), " · 불신으로 거부" if not bool(ev.get("believed", true)) else ""]
		"DISTRUST_RESET":
			if persp >= 0 and int(ev.get("team", -1)) != persp:
				return ""
			return "[color=#d6b979]화제 전환 · 불신 초기화[/color]"
		"DIVERSION":
			return "%s [color=#e8a06f]화제 돌리기 · 지정 아군 강제 도발[/color]" % _name_for(s, persp)
		"PROPAGANDA":
			return "%s [color=#ecd998]선전 · 아군 방어·계수 강화[/color]" % _name_for(s, persp)
		"INFO_REVEAL", "INFO_BLOCKED":
			if persp >= 0 and int(ev.get("team", -1)) != persp:
				return ""
			var field: String = {"position": "위치", "pos": "위치", "cooldowns": "스킬 쿨다운", "cooldown": "스킬 쿨다운", "health": "남은 체력", "hp": "남은 체력"}.get(str(ev.get("field", "")), "정보")
			if ty == "INFO_BLOCKED":
				return "%s [color=#ecd998]언론 통제 · %s 취득 차단[/color]" % [_name_for(s, persp), field]
			return "%s → %s [color=#f5b0d4]%s · %s[/color]" % [_name_for(s, persp), _name_for(g, persp), field, _disclosure_value(ev)]
		"REVEAL":
			var revealer: = runner.sim.u_at(s)
			if persp >= 0 and revealer and runner.sim.eteam(revealer) != persp:
				return ""
			return "%s [color=#d6b3ff]공유 신경망: %s 쿨다운 공개[/color]" % [_name_for(s, persp), _name_for(g, -1)]
		"POSITIONS_SWAPPED":
			return "%s ↔ %s 위치 교환" % [_name_for(s, persp), _name_for(g, persp)]
		"STAT_STOLEN":
			return "%s → %s [color=#f0c65c]능력치 약탈[/color]" % [_name_for(s, persp), _name_for(g, persp)]
		"BATTLE_STARTED":
			return "[color=#f4c96b][b]전투 시작[/b][/color] · %s" % str(ev.get("arena", ""))
		"BATTLE_ENDED":
			return "[color=#f4c96b][b]전투 종료[/b][/color]"
	return ""


# ================================================================== environment status (public)

## Order of the environment rows in the side panel.
const ENV_ORDER: = ["closing_ring", "gate", "artillery", "jump_pad", "brush", "mud", "lava", "spikes", "eruption", "gravity",
	"shockwave", "wind", "portal", "haste", "healing_fountain"]


## Public environment state: one row per gimmick type (gates per group), refreshed with the panel.
## Only public map information (timers, ring radius, announced strikes) is shown.
func _env_status() -> void:
	var sim: = runner.sim
	var a: Arena = sim.arena
	if a == null or (a.hazards.is_empty() and a.gates.is_empty() and a.forests.is_empty()):
		return
	# Deathmatch calls the brush "숲"; the battleground keeps "수풀" (DESIGN_V2 §3.2).
	var dm_mode: bool = sim.deathmatch != null and not sim.is_battleground()
	var present: Dictionary = {}
	for h in a.hazards:
		present[str(h.get("type", ""))] = true
	if not a.forests.is_empty():
		present["brush"] = true
	var keys: Array = []
	for typ in ENV_ORDER:
		if typ == "gate":
			var groups: Array = []
			for g in a.gates:
				if not groups.has(str(g.group)):
					groups.append(str(g.group))
			groups.sort()
			for gr in groups:
				keys.append("gate:" + str(gr))
		elif present.has(typ):
			keys.append(typ)
	if keys.is_empty():
		return
	tab_body.add_child(_section("전장 환경", "공개 정보 · 모두 볼 수 있습니다"))
	var list: = _list(5)
	var rows: Dictionary = {}
	if br:
		# The zone first: phase, what it is doing, the countdown and the damage outside it.
		var zrow: = UITheme.hbox(8)
		zrow.add_child(UITheme.glyph_tile("◉", Color("#cf9bff"), 22))
		var zn: = UITheme.label("자기장", "BodyLabel", 13)
		zn.custom_minimum_size = Vector2(92, 0)
		zrow.add_child(zn)
		var zv: = UITheme.ellipsize(UITheme.label("", "FaintLabel", 12), true)
		zv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		zrow.add_child(zv)
		zrow.tooltip_text = UITheme.tip(str(CodexData.hazard("br_zone").get("desc", "")))
		zrow.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(zrow)
		_updaters.append(func() -> void:
			var t: String = zone_pill.text()
			if zv.text != t:
				zv.text = t)
	for key in keys:
		var typ: String = str(key).split(":")[0]
		var info: Dictionary = CodexData.hazard(typ)
		var col: Color = Color(str(info.get("color", "#a9b6cc")))
		var row: = UITheme.hbox(8)
		row.add_child(UITheme.glyph_tile(str(info.get("icon", "•")), col, 22))
		var name_text: String = CodexData.hazard_label(typ, dm_mode)
		if typ == "gate":
			name_text += " %s조" % str(key).split(":")[1]
		var nm: = UITheme.label(name_text, "BodyLabel", 13)
		nm.custom_minimum_size = Vector2(92, 0)
		row.add_child(nm)
		var val: = UITheme.ellipsize(UITheme.label("", "FaintLabel", 12), true)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		row.tooltip_text = UITheme.tip(str(info.get("desc", "")))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(row)
		rows[key] = val
	_updaters.append(func() -> void: _update_env_rows(rows))


func _update_env_rows(rows: Dictionary) -> void:
	var sim: = runner.sim
	if sim == null or sim.arena == null:
		return
	var by_key: Dictionary = {}
	for row in sim.env.state_snapshot():
		var typ: String = str(row.get("type", ""))
		var key: String = ("gate:" + str(row.get("group", ""))) if typ == "gate" else typ
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(row)
	for key in rows:
		var l: Label = rows[key]
		var text: String = _env_row_text(str(key), by_key.get(key, []))
		if l.text != text:
			l.text = text


func _env_row_text(key: String, states: Array) -> String:
	var sim: = runner.sim
	var a: Arena = sim.arena
	var typ: String = key.split(":")[0]
	if typ == "brush":
		var patches: Dictionary = {}
		for p in a.forest_patch:
			patches[int(p)] = true
		if not sim.env.type_active("brush"):
			return "꺼짐"
		return "%d무리 · 안에 있으면 보이지 않습니다" % patches.size()
	if states.is_empty():
		return ""
	var first: Dictionary = states[0]
	if not bool(first.get("enabled", true)):
		return "꺼짐"
	match typ:
		"gate":
			var rem: float = float(first.get("remaining", 0.0))
			if bool(first.get("open", false)):
				if bool(first.get("warning", false)):
					return "곧 닫힘 · %.1f초" % rem
				return "열림 · %.1f초 후 닫힘" % rem
			return "닫힘 · %.1f초 후 열림" % rem
		"closing_ring":
			var t0: float = float(first.get("start_time", 0.0))
			var t1: float = float(first.get("end_time", 0.0))
			if sim.time < t0:
				return "%.0f초 후 수축 시작 · 최종 반경 %d" % [t0 - sim.time, int(float(first.get("final_radius", 0.0)))]
			if sim.time < t1:
				return "수축 중 · 반경 %d → %d · %.0f초" % [int(float(first.get("safe_radius", 0.0))), int(float(first.get("final_radius", 0.0))), t1 - sim.time]
			return "최종 결계 · 반경 %d" % int(float(first.get("final_radius", 0.0)))
		"artillery":
			var pending: int = 0
			var next_impact: float = INF
			var next_salvo: float = INF
			for st in states:
				pending += int(st.get("pending_strikes", 0))
				next_impact = minf(next_impact, float(st.get("next_impact_t", INF)))
			if pending > 0:
				return "%d발 착탄까지 %.1f초" % [pending, maxf(0.0, next_impact - sim.time)]
			for h in a.hazards:
				if str(h.get("type", "")) != "artillery":
					continue
				var period: float = maxf(0.2, float(h.get("period", 8.0)))
				var cycle: int = int(floor((sim.time + float(h.get("phase", 0.0))) / period))
				var warn: float = Arena.artillery_warning(h)
				for c in [cycle, cycle + 1]:
					var announce: float = Arena.artillery_impact_time(h, c) - warn
					if announce >= sim.time:
						next_salvo = minf(next_salvo, announce - sim.time)
						break
			return "다음 포격 예고 %.1f초" % next_salvo if next_salvo < INF else "대기"
		"healing_fountain":
			var ready: int = 0
			var soon: float = INF
			for st in states:
				var cd: float = float(st.get("cooldown_remaining", 0.0))
				if cd <= 0.0:
					ready += 1
				else:
					soon = minf(soon, cd)
			if ready == states.size():
				return "모두 준비됨" if states.size() > 1 else "준비됨"
			return "준비 %d/%d · 다음 %.0f초" % [ready, states.size(), soon]
		"spikes", "eruption", "gravity", "shockwave":
			var act: bool = false
			var warn2: bool = false
			var soonest: float = INF
			for st in states:
				act = act or bool(st.get("active", false))
				warn2 = warn2 or bool(st.get("warning", false))
				soonest = minf(soonest, float(st.get("to_active", INF)))
			if act:
				return "활성"
			if warn2:
				return "예고 중 · %.1f초 후 활성" % soonest
			return "%.1f초 후 활성" % soonest
		"jump_pad":
			return "%d개 · 비행 %s초" % [states.size(), CodexData.num(float(first.get("flight_time", 0.8)))]
		"mud":
			return "%d곳 · 둔화 %d%%" % [states.size(), int(roundf(float(first.get("slow", 0.3)) * 100.0))]
		"lava":
			return "%d곳 · 항상 활성" % states.size()
		"wind":
			return "%d곳 · 밀어냄 · 피해 없음" % states.size()
		"portal":
			return "%d개 · 짝 포탈로 이동" % states.size()
		"haste":
			return "%d곳 · 지나가면 가속" % states.size()
	return ""


# ================================================================== tab: team stats (기여도)

func _panel_stats() -> void :
	var sim: = runner.sim
	var head: = UITheme.label("", "CaptionLabel", 13)
	tab_body.add_child(head)
	_env_status()
	var cards: Array = []
	var persp: = view.perspective
	for t in 2:
		if persp >= 0 and t != persp:
			continue
		tab_body.add_child(_section(DB.TEAM_NAMES[t]))
		for u in sim.heroes:
			if u.team != t:
				continue
			var box: = UITheme.vbox(4)
			var hh: = UITheme.hbox(10)
			var d: = GlyphDisc.new(u.def, 30, t)
			hh.add_child(d)
			var nv: = UITheme.vbox(0)
			nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			nv.add_child(UITheme.label(u.def.name, "BoldLabel", 13))
			var sub: = UITheme.label("", "FaintLabel", 12)
			nv.add_child(sub)
			hh.add_child(nv)
			box.add_child(hh)
			var ctl_l: Label = null
			if sim.is_control_mode():
				ctl_l = UITheme.label("", "FaintLabel", 12)
				box.add_child(ctl_l)
			var bars: Array = []
			for row in [["피해", Color("#ff9a7a")], ["받은 피해", UITheme.TEXT_DIM], ["회복", Color("#7dffb0")], ["보호막", Color("#dfe8ff")], ["제어(초)", UITheme.WARN]]:
				var r: = StatBar.new()
				r.label = row[0]
				r.col = row[1]
				r.custom_minimum_size = Vector2(0, 18)
				box.add_child(r)
				bars.append(r)
			tab_body.add_child(UITheme.styled_panel(UITheme.sbc(Color(1, 1, 1, 0.02), UITheme.LINE, UITheme.R_M, 1, 10, 8), box))
			cards.append({"idx": u.idx, "disc": d, "sub": sub, "ctl": ctl_l, "bars": bars})
	_updaters.append(func() -> void:
		var s2: = runner.sim
		var mx: = [1.0, 1.0, 1.0, 1.0, 0.5]
		var totals: = [0.0, 0.0]
		for u2 in s2.heroes:
			totals[clampi(u2.team, 0, 1)] += u2.st_damage
			if persp >= 0 and u2.team != persp:
				continue
			var vals2: = [u2.st_damage, u2.st_taken, u2.st_healing, u2.st_shielding, u2.st_cc]
			for i in 5:
				mx[i] = maxf(mx[i], float(vals2[i]))
		head.text = ("팀 누적 피해 · 청 %d / 홍 %d" % [int(totals[0]), int(totals[1])]) if persp < 0 else ("아군 누적 피해 %d · 상대 실시간 통계는 비공개입니다" % int(totals[clampi(persp, 0, 1)]))
		for cd in cards:
			var u3: = s2.u_at(int(cd.idx))
			if u3 == null:
				continue
			(cd.disc as GlyphDisc).set_state(u3.hp / maxf(1.0, s2.max_hp(u3)), 0.0, not u3.alive)
			(cd.sub as Label).text = "처치 %d · 시전 %d" % [u3.st_kills, u3.st_casts]
			if cd.ctl:
				(cd.ctl as Label).text = "점령 기여 %.1f초 · 완료 %d회 · 구역 회복 %d" % [u3.st_capture_time, u3.st_captures, int(u3.st_zone_healing)]
			var vals: = [u3.st_damage, u3.st_taken, u3.st_healing, u3.st_shielding, u3.st_cc]
			for i in 5:
				var sbar: StatBar = cd.bars[i]
				sbar.visible = i == 0 or float(vals[i]) > 0.0
				sbar.set_values(float(vals[i]), float(mx[i])))


# ================================================================== tab: deathmatch ranking

func _panel_dm_rank() -> void:
	var sim: = runner.sim
	var dmm: DeathmatchMode = sim.deathmatch
	var head: = _flow(6)
	head.add_child(UITheme.badge("목표 %d킬" % dmm.kill_target, UITheme.GOLD, "soft", "먼저 이 처치 수에 도달한 참가자가 우승합니다."))
	var b_time: = UITheme.badge("", UITheme.ACCENT, "soft", "남은 시간입니다. 시간이 끝나면 처치 순위로 우승자를 정합니다.")
	head.add_child(b_time)
	var b_items: = UITheme.badge("", Color("#bc8cff"), "soft", "필드에 놓인 아이템 수 / 최대 개수입니다.")
	head.add_child(b_items)
	tab_body.add_child(head)
	_env_status()
	var list: = UITheme.vbox(4)
	tab_body.add_child(list)
	for i in sim.heroes.size():
		var row: = _rank_row(i)
		list.add_child(row.btn)
		_rank_rows.append(row)
	tab_body.add_child(_hint("순위는 처치 수, 같으면 적은 사망, 그다음 많은 피해 순입니다. 행을 누르면 그 참가자를 따라갑니다."))
	_updaters.append(func() -> void:
		var s2: = runner.sim
		(b_time.get_meta("label") as Label).text = "남은 시간 %s" % UITheme.fmt_time(s2.max_time - s2.time)
		(b_items.get_meta("label") as Label).text = "필드 아이템 %d / %d" % [s2.deathmatch.field.size(), DeathmatchMode.MAX_FIELD_ITEMS]
		_update_rank())


func _rank_row(i: int) -> Dictionary:
	var b: = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	# Select on press: a click can never be lost between mouse-down and mouse-up.
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.custom_minimum_size = Vector2(0, 50)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h: = UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -10
	b.add_child(h)
	var rl: = UITheme.label(str(i + 1), "", 16, UITheme.GOLD if i == 0 else UITheme.TEXT_DIM)
	rl.add_theme_font_override("font", DB.font_black)
	rl.custom_minimum_size = Vector2(22, 0)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rl)
	var disc: = GlyphDisc.new(null, 34, -1)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var nv: = UITheme.vbox(0)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl: = UITheme.ellipsize(UITheme.label("", "BoldLabel", 14))
	nv.add_child(nl)
	var sl: = UITheme.ellipsize(UITheme.label("", "DimLabel", 12))
	nv.add_child(sl)
	h.add_child(nv)
	var items: = UITheme.hbox(3)
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(items)
	var kd: = UITheme.vbox(0)
	kd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kd.alignment = BoxContainer.ALIGNMENT_CENTER
	kd.custom_minimum_size = Vector2(62, 0)
	var kl: = UITheme.label("0킬", "", 16, UITheme.TEXT)
	kl.add_theme_font_override("font", DB.font_black)
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kd.add_child(kl)
	var dl: = UITheme.label("", "FaintLabel", 12)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kd.add_child(dl)
	h.add_child(kd)
	var row: Dictionary = {"btn": b, "disc": disc, "name": nl, "status": sl, "items": items, "items_key": "?", "kills": kl, "kd": dl, "idx": -1, "style": ""}
	b.pressed.connect(func() -> void:
		if int(row.idx) >= 0:
			_select(int(row.idx)))
	return row


func _update_rank() -> void:
	var sim: = runner.sim
	var dmm: DeathmatchMode = sim.deathmatch
	var order: Array = dmm.ranking()
	var persp: = view.perspective
	for i in _rank_rows.size():
		var row: Dictionary = _rank_rows[i]
		var b: Button = row.btn
		if i >= order.size():
			b.visible = false
			continue
		var u: BUnit = order[i]
		var tc: = UITheme.team_color(u.team)
		var sel: = u.idx == view.selected
		var sk: = "%d|%s" % [u.team, sel]
		if str(row.style) != sk:
			row.style = sk
			b.add_theme_stylebox_override("normal", UITheme.sbc(Color(tc, 0.12 if sel else 0.035), Color(tc, 0.75 if sel else 0.18), UITheme.R_M, 1, 6))
			b.add_theme_stylebox_override("hover", UITheme.sbc(Color(tc, 0.14 if sel else 0.08), Color(tc, 0.8 if sel else 0.5), UITheme.R_M, 1, 6))
			b.add_theme_stylebox_override("pressed", UITheme.sbc(Color(tc, 0.16), tc, UITheme.R_M, 1, 6))
			b.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(tc, 0.16), tc, UITheme.R_M, 1, 6))
			_col(row.name, tc.lightened(0.3))
		if int(row.idx) != u.idx:
			row.idx = u.idx
			(row.disc as GlyphDisc).set_def(u.def, u.team)
			(row.name as Label).text = "P%d %s" % [u.team + 1, u.def.name]
			b.tooltip_text = "P%d %s — 누르면 이 참가자를 따라갑니다" % [u.team + 1, u.def.name]
		var hidden_hero: bool = persp >= 0 and u.team != persp and not sim.is_seen(persp, u)
		var hp: = clampf(u.hp / maxf(1.0, sim.max_hp(u)), 0.0, 1.0)
		(row.disc as GlyphDisc).set_state(-1.0 if hidden_hero and u.alive else (hp if u.alive else 0.0), 0.0, not u.alive)
		var status: String = "체력 %d%%" % int(hp * 100.0)
		if hidden_hero:
			status = "보이지 않음"
		if not u.alive:
			status = "부활까지 %.1f초" % maxf(0.0, float(dmm.respawn_at.get(u.idx, sim.time)) - sim.time)
		var ctl = sim.controllers[u.team]
		if u.alive and ctl and "intent" in ctl and (persp < 0 or persp == u.team):
			var mode_l: = str(DeathmatchBrain.LABELS.get(str(ctl.intent.get("mode", "")), ""))
			if mode_l != "":
				status += " · " + mode_l
		(row.status as Label).text = status
		var held: Array = [] if hidden_hero else dmm.held(u)
		var ik: = ",".join(PackedStringArray(held.map(func(x): return str(x))))
		if ik != str(row.items_key):
			row.items_key = ik
			var box: HBoxContainer = row.items
			for c in box.get_children():
				box.remove_child(c)
				c.queue_free()
			for held_id in held:
				var t: = UITheme.item_tile(str(held_id), 24)
				t.tooltip_text = ItemViews.tooltip_text(str(held_id))
				box.add_child(t)
		(row.kills as Label).text = "%d킬" % dmm.kills[u.team]
		(row.kd as Label).text = "%d사망 · %d도움" % [dmm.deaths[u.team], dmm.assists[u.team]]


# ================================================================== tab: deathmatch AI

func _panel_dm_ai() -> void:
	var sim: = runner.sim
	var su: = sim.u_at(view.selected)
	if su == null or not su.is_hero:
		tab_body.add_child(_empty("◈", "참가자를 선택해 주세요", "순위 탭이나 전장에서 참가자를 선택하면 그 AI의 판단이 보입니다."))
		return
	if view.perspective >= 0 and view.perspective != su.team:
		tab_body.add_child(_empty("?", "다른 참가자의 판단은 볼 수 없습니다", "시점을 '참가자 시점 선택'으로 되돌리거나 %s 시점으로 바꿔 주세요." % su.def.name))
		return
	var ctl = sim.controllers[su.team]
	if ctl == null or not (ctl is DeathmatchBrain):
		tab_body.add_child(_empty("◈", "데스매치 AI가 아닙니다", "이 참가자는 판단 기록을 남기지 않습니다."))
		return
	var brain: DeathmatchBrain = ctl
	var ex: Dictionary = brain.explain(su)
	var dmx: Dictionary = ex.get("deathmatch", {})
	var mode: String = str(dmx.get("mode", ""))
	var mode_col: Color = {"hunt": UITheme.BAD, "chase": UITheme.WARN, "evade": UITheme.ACCENT, "recover": UITheme.GOOD, "loot": UITheme.GOLD, "listen": Color("#c9b3ff"), "roam": UITheme.TEXT_DIM, "rotate": Color("#cf9bff")}.get(mode, UITheme.TEXT)
	tab_body.add_child(_hint("%s의 AI는 자기 시야·전투 소음·공개 정보만으로 판단합니다." % su.def.name,
		("공개 정보는 자기장, 생존 수와 탈락 소식입니다. 아이템은 직접 본 것만 압니다." if br else "공개 정보는 아이템 위치와 점수판입니다.") + " 모든 선택지를 '기대 처치'라는 같은 단위로 비교합니다."))
	var cv: = UITheme.vbox(6)
	var sh: HBoxContainer = UITheme.hbox(14)
	var mode_text: String = str(dmx.get("mode_label", mode))
	if br and mode_text == "":
		mode_text = str((ex.get("battleground", {}) as Dictionary).get("mode_label", mode))
	var ml: Label = UITheme.label(mode_text, "", 24, mode_col)
	ml.add_theme_font_override("font", DB.font_black)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(ml)
	var sv: VBoxContainer = UITheme.vbox(2)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sv.add_child(UITheme.wrap_label(str(dmx.get("reason", "")), "BodyLabel", 13))
	sv.add_child(UITheme.label("%.1f초째 유지" % maxf(0.0, sim.time - float(dmx.get("since", sim.time))), "FaintLabel", 12))
	sh.add_child(sv)
	cv.add_child(sh)
	tab_body.add_child(_card(cv, mode_col))
	var duels: Array = brain.duel_table()
	if not duels.is_empty():
		tab_body.add_child(_section("보이는 적과의 승산", "시간당 처치 비교 · 합류 위협 포함"))
		var dl: = _list(8)
		for dd in duels:
			var eu: BUnit = sim.u_at(int(dd.idx))
			var p: float = float(dd.p)
			var pc: = UITheme.GOOD if p >= 0.55 else (UITheme.BAD if p < 0.35 else UITheme.GOLD)
			var text: = "%s · 체력 %d%% · 거리 %d" % [str(dd.name), int(float(dd.hp) * 100.0), int(dd.dist)]
			var row: = _score_row(false, text, p, "%d%%" % int(p * 100.0), pc, "승산 %d%% · 탈출 가능성 %d%%%s" % [int(p * 100.0), int(float(dd.escape) * 100.0), " · 다른 적과 교전 중" if bool(dd.busy) else ""])
			if eu:
				_col(row.get_child(1) as Label, UITheme.team_color(eu.team).lightened(0.25))
			dl.add_child(row)
	var recent: Array = dmx.get("log", [])
	if not recent.is_empty():
		tab_body.add_child(_section("최근 결정", "최신 5개"))
		var rl: = _list(5)
		for i in range(recent.size() - 1, maxi(-1, recent.size() - 6), -1):
			var e: Dictionary = recent[i]
			var lr: = UITheme.hbox(8)
			var tl: = UITheme.label(UITheme.fmt_time(float(e.t)), "FaintLabel", 12)
			tl.custom_minimum_size = Vector2(36, 0)
			tl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			lr.add_child(tl)
			var labels: Dictionary = BattlegroundSoloBrain.BR_LABELS if br else DeathmatchBrain.LABELS
			lr.add_child(UITheme.wrap_label("%s · %s" % [str(labels.get(str(e.mode), str(e.mode))), str(e.reason)], "CaptionLabel", 13))
			rl.add_child(lr)
	tab_body.add_child(_section("아이템 판단 — \"이게 나에게 필요한가?\""))
	var items: Array = dmx.get("items", [])
	if items.is_empty():
		tab_body.add_child(_hint("아직 평가한 아이템이 없습니다. 아이템 위를 지나가면 필요도를 따져 봅니다."))
	var il: = _list(6)
	for iv in items:
		il.add_child(_item_row(str(iv.item), "가치 %.0f · %s" % [float(iv.value), str(iv.reason)]))
	var last_pick: String = str(dmx.get("last_pick", ""))
	if last_pick != "":
		tab_body.add_child(UITheme.wrap_label("마지막 줍기 판단 · " + last_pick, "", 13, UITheme.GOLD))
	var prof: Dictionary = ItemValuation.profile(su.def)
	tab_body.add_child(_section("영웅 분석", "아이템 가치 계산의 기준"))
	var pf: = _flow(5)
	pf.add_child(UITheme.badge("공격력 비중 %d%%" % int(float(prof.ad) * 100.0), UITheme.AD_COLOR, "soft"))
	pf.add_child(UITheme.badge("주문력 비중 %d%%" % int(float(prof.ap) * 100.0), UITheme.AP_COLOR, "soft"))
	pf.add_child(UITheme.badge("기본 공격 의존 %d%%" % int(float(prof.basic) * 100.0), UITheme.TEXT_DIM, "soft"))
	pf.add_child(UITheme.badge("원거리" if bool(prof.ranged) else "근접", UITheme.ACCENT, "soft"))
	if bool(prof.tank):
		pf.add_child(UITheme.badge("탱커", UITheme.role_color("FRONTLINE"), "soft"))
	if bool(prof.sustain):
		pf.add_child(UITheme.badge("자가 회복", UITheme.GOOD, "soft"))
	tab_body.add_child(pf)
	var top: Array = ex.get("top", [])
	if not top.is_empty():
		tab_body.add_child(_section("후보 행동", "가치 = HP 환산"))
		var best: = 1.0
		for c in top.slice(0, 6):
			best = maxf(best, absf(float(c.score)))
		var tl2: = _list(8)
		for i in mini(6, top.size()):
			var c: Dictionary = top[i]
			var cv3: = UITheme.vbox(2)
			tl2.add_child(cv3)
			cv3.add_child(_score_row(i == 0, str(c.label), absf(float(c.score)) / best, "%.0f" % float(c.score), UITheme.GOLD if i == 0 else UITheme.TEXT_DIM))
			var notes: Array = c.get("notes", [])
			if not notes.is_empty() and i < 3:
				cv3.add_child(UITheme.margin(UITheme.wrap_label("↳ " + " · ".join(notes.slice(0, 3)), "", 12, UITheme.GOLD.darkened(0.1)), 20, 0, 0, 0))


# ================================================================== battleground (V2)

## Battleground setup of the screen (DESIGN_V2 §3.8): one TeamChip per team (first half on the
## left), the team perspective picker, the minimap and the zone pill.
func _start_br() -> void:
	var sim: = runner.sim
	dm_view_opt.clear()
	dm_view_opt.add_item("참가자 시점 선택" if br.squad <= 1 else "팀 시점 선택")
	var half: int = int(ceil(br.team_count / 2.0))
	for team in br.team_count:
		var names: PackedStringArray = PackedStringArray()
		for u in br.team_members(team):
			names.append(u.def.name)
		dm_view_opt.add_item("%s · %s" % [br.team_label(team), "·".join(names)])
		dm_view_opt.set_item_metadata(dm_view_opt.item_count - 1, team)
		var chip: TeamChip = TeamChip.new()
		var tt: int = team
		chip.pressed.connect(func() -> void: _on_team_chip(tt))
		(chip_boxes[0 if team < half else 1] as Container).add_child(chip)
		br_chips.append(chip)
	dm_view_opt.select(0)
	view.follow_team = -1
	minimap.set_arena(sim.arena)
	minimap.custom_minimum_size = Minimap.fit_size(sim.arena, Vector2(240, 170))
	zone_pill.set_view(br.zone_view())
	zone_pill.set_time(sim.time)
	_br_timer = 0.0
	_cam_timer = 0.0
	_push_br()


## Next perspective for V (dir 1) / Shift+V (dir -1): spectator, then every team still in play.
func _br_next_view(cur: int, dir: int) -> int:
	var n: int = br.team_count
	var p: int = cur
	for _i in n + 2:
		p += dir
		if p >= n:
			p = -1
		elif p < -1:
			p = n - 1
		if p == -1 or not br.is_eliminated(p):
			return p
	return -1


## The member the camera and the unit tab show for a team: standing first, then downed.
func _br_focus_member(team: int) -> BUnit:
	var fallback: BUnit = null
	for u in br.team_members(team):
		if u.alive and not br.is_downed(u):
			return u
		if fallback == null or (u.alive and not fallback.alive):
			fallback = u
	return fallback


func _on_team_chip(team: int) -> void:
	var u: BUnit = _br_focus_member(team)
	if u:
		_select(u.idx)


## Health and state of a hero as this perspective knows it (TeamChip / BrStanding member fields).
## Unseen rivals show no health and no downed state; deaths are public.
func _br_member(u: BUnit) -> Dictionary:
	var sim: = runner.sim
	var persp: int = view.perspective
	var known: bool = persp < 0 or u.team == persp or sim.is_seen(persp, u)
	var hs: Dictionary = br.hstats.get(u.idx, {})
	var m: Dictionary = {"glyph": u.def.glyph, "color": u.def.accent, "name": u.def.name, "kills": int(hs.get("kills", 0)),
		"knocks": int(hs.get("knocks", 0)), "revives": int(hs.get("revives", 0)), "damage": float(hs.get("damage", 0.0))}
	if not u.alive:
		m["state"] = "dead"
		m["hp"] = 0.0
		var cause: String = str(hs.get("death_cause", ""))
		if cause == "zone":
			m["note"] = "자기장 사망"
		elif cause == "bleed":
			m["note"] = "출혈 사망"
	elif known and br.is_downed(u):
		var d: Dictionary = br.downed_info(u)
		m["state"] = "downed"
		m["downed_left"] = maxf(0.0, float(d.bleed_at) - sim.time)
		m["downed_total"] = float(d.bleed_total)
		m["revive"] = float(d.revive_progress)
	else:
		m["state"] = "alive"
		m["hp"] = clampf(u.hp / maxf(1.0, sim.max_hp(u)), 0.0, 1.0) if known else -1.0
	return m


## One Dictionary per team in team order (TeamChip.set_data and BrStanding.set_teams fields).
func _br_team_rows() -> Array:
	var sel: BUnit = runner.sim.u_at(view.selected)
	var follow: int = view.perspective if view.perspective >= 0 else (sel.team if sel else -1)
	var out: Array = []
	for team in br.team_count:
		var members: Array = []
		for u in br.team_members(team):
			members.append(_br_member(u))
		out.append({"team": team, "label": br.team_label(team), "color": UITheme.team_color(team), "members": members,
			"eliminated": br.is_eliminated(team), "place": int(br.placement.get(team, 0)), "elim_time": float(br.elim_time.get(team, 0.0)),
			"selected": team == follow})
	return out


## Pushes chips, minimap and zone pill (every BR_PUSH s; each widget redraws only on change).
func _push_br() -> void:
	var sim: = runner.sim
	br_pushes += 1
	var rows: Array = _br_team_rows()
	for team in mini(rows.size(), br_chips.size()):
		(br_chips[team] as TeamChip).set_data(rows[team])
	_br_keys["rows"] = rows
	var zv: Dictionary = br.zone_view()
	zone_pill.set_view(zv)
	if not minimap.visible:
		return
	minimap.set_zone(zv)
	var persp: int = view.perspective
	var dots: Array = []
	for u in sim.heroes:
		if not u.alive:
			# Deaths are public: a fading mark for 20 s.
			if u.death_time >= 0.0 and sim.time - u.death_time < 20.0:
				dots.append({"pos": u.pos, "color": UITheme.team_color(u.team), "kind": "death"})
			continue
		if persp >= 0 and u.team != persp and not sim.is_seen(persp, u):
			continue
		dots.append({"pos": u.pos, "color": UITheme.team_color(u.team), "kind": "downed" if br.is_downed(u) else "hero"})
	# Only visible legendary items are marked in a team's perspective.
	for it in br.field:
		if ItemDefs.rarity_of(str(it.item)) >= 4 and view.field_item_visible(it.pos):
			dots.append({"pos": it.pos, "color": ItemDefs.rarity_color(4), "kind": "item"})
	if dots != _br_keys.get("dots", []):
		_br_keys["dots"] = dots
		minimap.set_dots(dots)


## World rectangle the battle view shows (minimap camera frame).
func _camera_world_rect() -> Rect2:
	var vs: float = maxf(0.01, view.view_scale)
	return Rect2(view.to_world(view.fit_rect.position), view.fit_rect.size / vs)


## Minimap click / drag: pan there (zooming in first when the whole map is on screen).
func _on_minimap_clicked(pos: Vector2) -> void:
	view.cam_mode = "manual"
	if view.view_scale < 0.4:
		view.cam_zoom_t = clampf(0.45 / maxf(0.01, view.base_scale), 1.0, view.max_zoom())
		view.cam_zoom = view.cam_zoom_t
	view.cam_center_t = pos
	view.cam_center = pos
	view._apply_camera(0.0)
	_sync_cam()
	_cam_timer = 0.0


## "P7 하데스" / "3팀 하데스" in the team colour.
func _br_name(u: BUnit) -> Label:
	return _feed_name("%s %s" % [br.team_label(u.team), u.def.name], UITheme.team_color(u.team))


func _feed_glyph(text: String, col: Color) -> Label:
	var g: = UITheme.label(text, "", 13, col)
	g.add_theme_font_override("font", DB.font_bold)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return g


## Battleground kill feed line (view.kill_feed entry): kills (⚔, ☠ for zone / bleed / wipe), knocks
## (▲ 다운), revives (✚ 소생), squad eliminations (☠ n팀 탈락 · k위) and zone announcements. Null =
## nothing to show (a solo elimination is already on its kill line, with the place).
func _br_feed_pill(k: Dictionary, killer: BUnit, victim: BUnit) -> Control:
	var kind: String = str(k.get("kind", "kill"))
	# Nothing to show: decide before building any node (an unparented node would leak).
	if (kind == "team_out" and br.squad <= 1) or (kind not in ["zone", "team_out"] and victim == null):
		return null
	var h: = UITheme.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var zone_col: = Color("#cf9bff")
	match kind:
		"zone":
			var ph: int = int(k.get("phase", 0))
			h.add_child(_feed_glyph("◉", zone_col))
			var text: String
			if str(k.get("state", "")) == "announce":
				text = "자기장 %d/%d 예고 · %s 뒤 수축" % [ph, BrZone.PHASES, UITheme.fmt_time(maxf(0.0, float(k.get("shrink_start", 0.0)) - float(k.t)))]
			else:
				text = "자기장 %d/%d 수축 시작 · %s" % [ph, BrZone.PHASES, ZonePill.dps_text(float(k.get("dps_ratio", 0.0)))]
			h.add_child(_feed_name(text, zone_col))
		"team_out":
			var team: int = int(k.get("team", -1))
			h.add_child(_feed_glyph("☠", UITheme.BAD))
			h.add_child(_feed_name("%s 탈락" % br.team_label(team), UITheme.team_color(team)))
			var pl: = UITheme.badge("%d위" % int(k.get("place", 0)), UITheme.TEXT_DIM, "soft")
			pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pl)
		"knock", "revive":
			if killer:
				h.add_child(_mini_disc(killer, false))
				h.add_child(_br_name(killer))
			else:
				h.add_child(_feed_name("자기장" if bool(k.get("zone", false)) else "환경", zone_col if bool(k.get("zone", false)) else UITheme.WARN))
			if kind == "knock":
				h.add_child(_feed_glyph("▲ 다운", Color("#ff8a8a")))
			else:
				h.add_child(_feed_glyph("✚ 소생", UITheme.GOOD))
			h.add_child(_mini_disc(victim, kind == "knock"))
			h.add_child(_br_name(victim))
		_:
			var cause: String = str(k.get("cause", "kill"))
			if killer:
				h.add_child(_mini_disc(killer, false))
				h.add_child(_br_name(killer))
			elif cause == "zone":
				h.add_child(_feed_name("자기장", zone_col))
			else:
				h.add_child(_feed_name("환경", UITheme.WARN))
			h.add_child(_feed_glyph("☠" if cause in ["zone", "bleed", "team_wipe"] else "⚔", UITheme.GOLD))
			h.add_child(_mini_disc(victim, true))
			h.add_child(_br_name(victim))
			var tag: String = {"zone": "자기장", "bleed": "출혈", "team_wipe": "팀 전멸"}.get(cause, "")
			if killer and tag != "":
				var cb: = UITheme.badge(tag, UITheme.TEXT_DIM, "soft")
				cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(cb)
			if br.squad <= 1 and br.placement.has(victim.team):
				var pb: = UITheme.badge("%d위" % int(br.placement[victim.team]), UITheme.TEXT_DIM, "soft")
				pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(pb)
	var tl: = UITheme.label(UITheme.fmt_time(float(k.get("t", 0.0))), "FaintLabel", 12)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tl)
	var p: = UITheme.styled_panel(UITheme.sbc(Color(0.03, 0.045, 0.07, 0.86), Color(1, 1, 1, 0.1), UITheme.R_PILL, 1, 10, 3), h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


# ---------------------------------------------------------------- battleground: rank tab

func _panel_br_rank() -> void:
	var sim: = runner.sim
	var head: = _flow(6)
	var b_alive: = UITheme.badge("", UITheme.GOOD, "soft", "살아 있는 영웅 수(다운 포함)와 남은 팀 수입니다.")
	var b_time: = UITheme.badge("", UITheme.ACCENT, "soft", "경과 시간입니다. %s이 되면 남은 팀의 순위를 생존 인원, 그다음 체력 합으로 정합니다." % UITheme.fmt_time(sim.max_time))
	var b_items: = UITheme.badge("", Color("#bc8cff"), "soft", "필드에 놓인 아이템 수입니다. 시작할 때 %d개가 놓이고 다시 생기지 않으며, 탈락한 영웅의 아이템은 그 자리에 모두 떨어집니다." % BattlegroundMode.ITEM_COUNT)
	for b in [b_alive, b_time, b_items]:
		head.add_child(b)
	tab_body.add_child(head)
	_env_status()
	br_standing = BrStanding.new()
	br_standing.member_pressed.connect(func(team: int, member: int) -> void:
		var ms: Array = br.team_members(team)
		if member >= 0 and member < ms.size():
			_select((ms[member] as BUnit).idx))
	br_standing.team_pressed.connect(func(team: int) -> void:
		var f: BUnit = _br_focus_member(team)
		if f:
			_select(f.idx))
	tab_body.add_child(br_standing)
	tab_body.add_child(_hint("살아 있는 팀은 서 있는 인원, 다운 포함 인원, 처치 순으로 정렬합니다. 탈락한 팀은 순위와 탈락 시각으로 접힙니다. 행을 누르면 그 영웅을 따라갑니다."))
	var standing: BrStanding = br_standing
	_updaters.append(func() -> void:
		var s2: = runner.sim
		var heroes: int = br.alive_hero_count()
		(b_alive.get_meta("label") as Label).text = ("생존 %d/%d명" % [heroes, s2.heroes.size()]) if br.squad <= 1 else ("생존 %d/%d · %d팀" % [heroes, s2.heroes.size(), br.alive_team_count()])
		(b_time.get_meta("label") as Label).text = "경과 %s" % UITheme.fmt_time(s2.time)
		(b_items.get_meta("label") as Label).text = "필드 아이템 %d" % br.field.size()
		var rows: Array = _br_team_rows()
		if not standing.has_meta("rows") or standing.get_meta("rows") != rows:
			standing.set_meta("rows", rows)
			standing.set_teams(rows))


# ---------------------------------------------------------------- battleground: AI tab

func _panel_br_ai() -> void:
	var sim: = runner.sim
	var su: = sim.u_at(view.selected)
	if su == null or not su.is_hero:
		tab_body.add_child(_empty("◈", "영웅을 선택해 주세요", "순위 탭이나 전장에서 영웅을 선택하면 그 팀 AI의 판단이 보입니다."))
		return
	if view.perspective >= 0 and view.perspective != su.team:
		tab_body.add_child(_empty("?", "다른 팀의 판단은 볼 수 없습니다", "시점을 '%s'으로 되돌리거나 %s 시점으로 바꿔 주세요." % [dm_view_opt.get_item_text(0), br.team_label(su.team)]))
		return
	var ctl = sim.controllers[su.team] if su.team < sim.controllers.size() else null
	if ctl == null:
		tab_body.add_child(_empty("☠", "탈락한 팀입니다", "탈락한 팀의 AI는 더 이상 판단하지 않습니다."))
		return
	if ctl is DeathmatchBrain:
		_panel_dm_ai()
		var ex0: Dictionary = (ctl as DeathmatchBrain).explain(su)
		var zc: Control = _br_zone_card(ex0.get("battleground", {}).get("zone", {}))
		if zc:
			tab_body.add_child(zc)
			tab_body.move_child(zc, mini(2, tab_body.get_child_count() - 1))
		return
	if not ctl.has_method("explain"):
		tab_body.add_child(_empty("◈", "판단 설명이 없는 AI입니다", "이 AI는 판단 과정을 기록하지 않습니다."))
		return
	var ex: Dictionary = ctl.explain(su)
	var brx: Dictionary = ex.get("battleground", {})
	tab_body.add_child(_hint("%s AI는 팀원이 함께 본 것과 공개 정보(자기장·생존 수·탈락 소식)만으로 판단합니다." % br.team_label(su.team),
		"분대 의도(보급·자기장 이동·교전·이탈·소생 등)를 팀 단위로 정하고, 팀원마다 역할과 목표를 나눠 맡깁니다."))
	var mode: String = str(brx.get("mode", ""))
	var mode_col: Color = {"engage": UITheme.BAD, "third": UITheme.BAD, "disengage": UITheme.ACCENT, "revive": UITheme.GOOD, "rotate": Color("#cf9bff"),
		"loot": UITheme.GOLD, "regroup": UITheme.ACCENT2}.get(mode, UITheme.TEXT)
	var cv: = UITheme.vbox(6)
	var sh: HBoxContainer = UITheme.hbox(14)
	var ml: Label = UITheme.label(str(brx.get("mode_label", mode)) if str(brx.get("mode_label", "")) != "" else mode, "", 24, mode_col)
	ml.add_theme_font_override("font", DB.font_black)
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(ml)
	var sv: VBoxContainer = UITheme.vbox(2)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sv.add_child(UITheme.wrap_label(str(brx.get("reason", "")), "BodyLabel", 13))
	sv.add_child(UITheme.label("분대 의도 · %.1f초째 유지" % maxf(0.0, sim.time - float(brx.get("since", sim.time))), "FaintLabel", 12))
	sh.add_child(sv)
	cv.add_child(sh)
	tab_body.add_child(_card(cv, mode_col))
	var kv: = UITheme.vbox(4)
	if str(brx.get("role", "")) != "":
		kv.add_child(_kv("역할", str(brx.role), UITheme.TEXT).row)
	if str(brx.get("goal_label", "")) != "":
		kv.add_child(_kv("목표", str(brx.goal_label), UITheme.TEXT_DIM).row)
	var lead: BUnit = sim.u_at(int(brx.get("leader", -1)))
	if lead:
		kv.add_child(_kv("앵커", lead.def.name, UITheme.team_color(lead.team).lightened(0.2)).row)
	if kv.get_child_count() > 0:
		tab_body.add_child(kv)
	else:
		kv.free()
	var zc2: Control = _br_zone_card(brx.get("zone", {}))
	if zc2:
		tab_body.add_child(zc2)
	var recent: Array = brx.get("log", [])
	if not recent.is_empty():
		tab_body.add_child(_section("최근 분대 결정", "최신 5개"))
		var rl: = _list(5)
		for i in range(recent.size() - 1, maxi(-1, recent.size() - 6), -1):
			var e: Dictionary = recent[i]
			var lr: = UITheme.hbox(8)
			var tl: = UITheme.label(UITheme.fmt_time(float(e.get("t", 0.0))), "FaintLabel", 12)
			tl.custom_minimum_size = Vector2(36, 0)
			tl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			lr.add_child(tl)
			lr.add_child(UITheme.wrap_label("%s · %s" % [str(BattlegroundSquadBrain.MODE_LABELS.get(str(e.get("mode", "")), str(e.get("mode", "")))), str(e.get("reason", ""))], "CaptionLabel", 13))
			rl.add_child(lr)
	var top: Array = ex.get("top", [])
	if not top.is_empty():
		tab_body.add_child(_section("%s의 후보 행동" % su.def.name, "가치 = HP 환산"))
		var best: = 1.0
		for c in top.slice(0, 6):
			best = maxf(best, absf(float(c.score)))
		var tl2: = _list(8)
		for i in mini(6, top.size()):
			var c: Dictionary = top[i]
			var cv3: = UITheme.vbox(2)
			tl2.add_child(cv3)
			cv3.add_child(_score_row(i == 0, str(c.label), absf(float(c.score)) / best, "%.0f" % float(c.score), UITheme.GOLD if i == 0 else UITheme.TEXT_DIM))
			var notes: Array = c.get("notes", [])
			if not notes.is_empty() and i < 3:
				cv3.add_child(UITheme.margin(UITheme.wrap_label("↳ " + " · ".join(notes.slice(0, 3)), "", 12, UITheme.GOLD.darkened(0.1)), 20, 0, 0, 0))


## The AI's reading of the public zone (zone_sense): where it must be and how much time it has.
func _br_zone_card(zs: Dictionary) -> Control:
	if zs.is_empty():
		return null
	var v: = UITheme.vbox(4)
	v.add_child(UITheme.label("자기장 판단 · %s" % str(zs.get("label", "")), "EyebrowLabel", 12, Color("#cf9bff")))
	var slack: float = float(zs.get("slack", INF))
	var parts: PackedStringArray = PackedStringArray()
	parts.append("다음 원 공개" if bool(zs.get("known", false)) else "다음 원 미공개")
	if bool(zs.get("outside", false)):
		parts.append("지금 원 밖")
	if is_finite(slack):
		parts.append("여유 %.0f초" % slack if slack >= 0.0 else "늦음 %.0f초" % -slack)
	if bool(zs.get("need_move", false)):
		parts.append("이동 필요")
	v.add_child(UITheme.wrap_label(" · ".join(parts), "CaptionLabel", 13))
	var bar: = UITheme.progress(clampf(float(zs.get("urgency", 0.0)), 0.0, 1.0), 1.0, Color("#cf9bff"), 5)
	bar.tooltip_text = UITheme.tip("자기장 긴급도입니다. 가장자리가 닿기까지 남은 시간에서 안쪽까지 걸어가는 시간을 뺀 여유가 줄수록 커집니다.")
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(bar)
	return _card(v, Color("#cf9bff"))


# ---------------------------------------------------------------- battleground: unit tab parts

## Downed / revive card: bleed-out and revive progress of a downed hero, or the revive this hero
## is channelling. Hidden otherwise; refreshed in place.
func _br_downed_card(idx: int) -> void:
	var v: = UITheme.vbox(5)
	var title: = UITheme.label("", "BoldLabel", 14, Color("#ff8a8a"))
	v.add_child(title)
	var bleed: = UITheme.progress(1.0, 1.0, UITheme.BAD, 6)
	v.add_child(bleed)
	var revive: = UITheme.progress(0.0, 1.0, UITheme.GOOD, 6)
	v.add_child(revive)
	var note: = UITheme.wrap_label("", "FaintLabel", 12)
	v.add_child(note)
	var card: = _card(v, UITheme.BAD)
	card.tooltip_text = UITheme.tip("다운: 체력 %d의 별도 체력으로 기어서만 움직이고 공격·스킬을 쓸 수 없습니다. 자기장을 포함한 모든 피해를 %d%%만 받습니다. 첫 다운은 %d초, 두 번째 %d초, 그 뒤로는 %d초가 지나거나 다운 체력이 0이 되면 사망합니다. 팀원이 %d 거리 안에서 %d초 동안 소생하면 체력 %d%%로 일어납니다." % [
		int(BattlegroundMode.DOWNED_HP), int(BattlegroundMode.DOWNED_TAKEN * 100.0), int(BattlegroundMode.BLEED_TIMES[0]), int(BattlegroundMode.BLEED_TIMES[1]), int(BattlegroundMode.BLEED_TIMES[2]),
		int(BattlegroundMode.REVIVE_RANGE), int(BattlegroundMode.REVIVE_TIME), int(BattlegroundMode.REVIVE_HP * 100.0)])
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_body.add_child(card)
	_updaters.append(func() -> void:
		var sim: = runner.sim
		var u: = sim.u_at(idx)
		if u == null or br == null:
			card.visible = false
			return
		if br.is_downed(u):
			var d: Dictionary = br.downed_info(u)
			card.visible = true
			var left: float = maxf(0.0, float(d.bleed_at) - sim.time)
			title.text = "다운 · 출혈 %.0f초 · 다운 체력 %d / %d" % [ceilf(left), int(d.hp), int(d.max_hp)]
			_col(title, Color("#ff8a8a"))
			bleed.visible = true
			bleed.max_value = maxf(0.1, float(d.bleed_total))
			bleed.value = left
			var rv: float = float(d.revive_progress)
			var reviver: BUnit = sim.u_at(int(d.reviver_idx))
			revive.visible = rv > 0.0
			revive.value = rv
			note.text = ("%s 소생 중 · %d%%" % [reviver.def.name, int(rv * 100.0)]) if reviver and rv > 0.0 else "%d번째 다운 · 팀원이 %d 거리 안에서 %d초 소생하면 일어납니다" % [int(d.count), int(BattlegroundMode.REVIVE_RANGE), int(BattlegroundMode.REVIVE_TIME)]
		elif br.is_reviving(u):
			var target: BUnit = sim.u_at(int(br.reviving[u.idx]))
			var td: Dictionary = br.downed_info(target) if target else {}
			card.visible = not td.is_empty()
			if td.is_empty():
				return
			title.text = "소생 중 → %s" % target.def.name
			_col(title, UITheme.GOOD)
			bleed.visible = false
			revive.visible = true
			revive.value = float(td.revive_progress)
			note.text = "%d%% · 피격·이동·군중 제어에 끊깁니다" % int(float(td.revive_progress) * 100.0)
		else:
			card.visible = false)


## V2 hero cards (DESIGN_V2 §2.8, every mode): War Machine fuel pips, tank HP and overdrive timer;
## Hades soul-harvest max-HP gain and the cerberus target; Achilles shield guard.
func _hero_card(u: BUnit) -> void:
	var idx: int = u.idx
	match u.def.id:
		"war_machine":
			var v: = UITheme.vbox(5)
			var head: = UITheme.label("", "BodyLabel", 13)
			v.add_child(head)
			var pips: = FuelPips.new()
			pips.custom_minimum_size = Vector2(0, 12)
			v.add_child(pips)
			var tank: = UITheme.label("", "CaptionLabel", 13)
			v.add_child(tank)
			tab_body.add_child(_card(v, Color("#ff8a3d")))
			_updaters.append(func() -> void:
				var sim: = runner.sim
				var wu: = sim.u_at(idx)
				if wu == null:
					return
				var fuel: int = int(wu.resources.get("fuel", 0))
				pips.set_value(fuel, 10)
				var od: ST.Status = sim.get_status(wu, &"overdrive")
				head.text = ("과열 폭주 %.1f초 · S1만 사용 · 연료 소모 없음" % maxf(0.0, od.end - sim.time)) if od else "연료 %d / 10" % fuel
				_col(head, Color("#ff9a5b") if od else UITheme.TEXT)
				var tu: BUnit = sim.u_at(int(wu.ks.get("tank_idx", -1)))
				if tu and tu.alive:
					tank.text = "연료탱크 체력 %d / %d · 파괴되면 과열 폭주" % [int(tu.hp), int(sim.max_hp(tu))]
				else:
					tank.text = "연료탱크 없음 · %.0f초 뒤 다시 장착" % maxf(0.0, float(wu.ks.get("tank_ready_at", 0.0)) - sim.time))
		"hades":
			var hv: = UITheme.vbox(3)
			var gain: = UITheme.label("", "BodyLabel", 13)
			hv.add_child(gain)
			var dog: = UITheme.wrap_label("", "CaptionLabel", 13)
			hv.add_child(dog)
			tab_body.add_child(_card(hv, Color("#8f7cff")))
			_updaters.append(func() -> void:
				var sim: = runner.sim
				var hu: = sim.u_at(idx)
				if hu == null:
					return
				var harvested: float = 0.0
				for b in hu.buffs:
					if b.stat == BattleSim.S_HP and b.tag == "soulHarvest" and b.end > sim.time:
						harvested = maxf(harvested, b.amount * hu.base_max_hp)
				gain.text = ("영혼 수확 · 최대 체력 +%d" % int(harvested)) if harvested >= 1.0 else "영혼 수확 · 최대 체력 증가 없음"
				_col(gain, Color("#b9a8ff") if harvested >= 1.0 else UITheme.TEXT_DIM)
				var pet: BUnit = sim.u_at(int(hu.ks.get("pet_idx", -1)))
				if pet and pet.alive:
					var tgt: BUnit = sim.u_at(pet.target_idx)
					dog.text = "케르베로스 체력 %d / %d · %s" % [int(pet.hp), int(sim.max_hp(pet)), ("공격 대상 " + tgt.def.name) if tgt else "주인 곁을 지키는 중"]
				else:
					dog.text = "케르베로스 없음 · %.0f초 뒤 다시 나옴" % maxf(0.0, float(hu.ks.get("pet_ready_at", 0.0)) - sim.time))
		"achilles":
			var av: = UITheme.vbox(3)
			var guard: = UITheme.label("", "BodyLabel", 13)
			av.add_child(guard)
			tab_body.add_child(_card(av, Color("#d9a24f")))
			_updaters.append(func() -> void:
				var sim: = runner.sim
				var au: = sim.u_at(idx)
				if au == null:
					return
				var fg: ST.Status = sim.get_status(au, &"frontGuard")
				if fg:
					var dir: Vector2 = fg.extra.get("dir", au.facing)
					guard.text = "전방 방패 · %s · %.1f초 · 앞 120°의 직접 피해·제어 차단" % [_dir_arrow(dir), maxf(0.0, fg.end - sim.time)]
					_col(guard, Color("#e8b866"))
				else:
					guard.text = "방패 내림 · 스틱스의 축복(평타로 받는 피해 감소)"
					_col(guard, UITheme.TEXT_DIM))


## Compass word for a screen direction (y down): "동", "남동", ... "북동".
static func _dir_arrow(d: Vector2) -> String:
	var names: Array = ["동쪽", "남동쪽", "남쪽", "남서쪽", "서쪽", "북서쪽", "북쪽", "북동쪽"]
	return str(names[int(roundf(fposmod(d.angle(), TAU) / (TAU / 8.0))) % 8])


# ================================================================== widgets

## Deathmatch scoreboard chip: portrait with HP ring, kills, P-number and held-item diamonds.
## refresh() redraws only when what it shows changed; hover redraws via mouse signals.
class DmChip:
	extends Button
	var sim: BattleSim
	var idx: int = -1
	var selected: bool = false
	var perspective: int = -1
	var _key: PackedInt32Array = PackedInt32Array()

	func _init(s: BattleSim, i: int) -> void:
		sim = s
		idx = i
		var u: BUnit = s.u_at(i)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(74, 58)
		tooltip_text = "P%d %s — 누르면 이 참가자를 따라갑니다" % [u.team + 1, u.def.name]
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, empty)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _known(u: BUnit) -> bool:
		return perspective < 0 or u.team == perspective or sim.is_seen(perspective, u)

	func refresh() -> void:
		var u: BUnit = sim.u_at(idx)
		if u == null:
			return
		var known: bool = _known(u)
		var k: = PackedInt32Array([1 if u.alive else 0, 1 if known else 0, 1 if selected else 0, perspective,
			int(clampf(u.hp / maxf(1.0, sim.max_hp(u)), 0.0, 1.0) * 60.0), sim.deathmatch.kills[u.team]])
		if not u.alive:
			k.append(int(ceil(maxf(0.0, float(sim.deathmatch.respawn_at.get(u.idx, sim.time)) - sim.time))))
		if known:
			for h in sim.deathmatch.held(u):
				k.append(ItemDefs.rarity_of(str(h)))
		if k != _key:
			_key = k
			queue_redraw()

	func _draw() -> void:
		var u: BUnit = sim.u_at(idx)
		if u == null:
			return
		var tc: Color = UITheme.team_color(u.team)
		if selected or is_hovered():
			draw_style_box(UITheme.sbc(Color(tc, 0.12), Color(tc, 0.8 if selected else 0.4), UITheme.R_M, 1, 0), Rect2(Vector2.ZERO, size))
		var c: Vector2 = Vector2(23, 25)
		var r: float = 15.0
		# In a participant's view, health and items of unseen rivals stay hidden.
		var known: bool = _known(u)
		var hp: float = clampf(u.hp / maxf(1.0, sim.max_hp(u)), 0.0, 1.0) if u.alive else 0.0
		draw_circle(c, r + 3.0, Color(tc, 0.95 if u.alive else 0.35))
		draw_circle(c, r, u.def.accent.darkened(0.55 if u.alive else 0.8))
		if u.alive and known:
			draw_arc(c, r + 5.5, -PI * 0.5, -PI * 0.5 + TAU * hp, 28, UITheme.GOOD if hp > 0.5 else (UITheme.WARN if hp > 0.25 else UITheme.BAD), 2.0, true)
		elif u.alive:
			draw_arc(c, r + 5.5, 0, TAU, 28, Color(1, 1, 1, 0.18), 1.2, true)
		var f: Font = DB.font_glyph
		var g: String = u.def.glyph
		var gw: float = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, c + Vector2(-gw * 0.5, 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 1.0 if u.alive else 0.4))
		var k: String = str(sim.deathmatch.kills[u.team])
		draw_string(DB.font_black, Vector2(46, 27), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.TEXT)
		var sub: String = "P%d" % (u.team + 1)
		if not u.alive:
			sub = "%.0f초" % maxf(0.0, float(sim.deathmatch.respawn_at.get(u.idx, sim.time)) - sim.time)
		draw_string(DB.font_bold, Vector2(46, 44), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tc.lightened(0.3) if u.alive else UITheme.TEXT_FAINT)
		var held: Array = sim.deathmatch.held(u) if known else []
		for i in held.size():
			var col: Color = ItemDefs.rarity_color(ItemDefs.rarity_of(str(held[i])))
			var q: Vector2 = Vector2(12 + i * 11, size.y - 5)
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4), q + Vector2(4, 0), q + Vector2(0, 4), q + Vector2(-4, 0)]), col)


## Selected-unit HP bar (hp + shield ratios); redraws only on change.
class HpBar:
	extends Control
	var hp: float = -1.0
	var shield: float = 0.0
	var known: bool = true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(h: float, s: float, k: bool) -> void:
		if absf(h - hp) > 0.002 or absf(s - shield) > 0.002 or k != known:
			hp = h
			shield = s
			known = k
			queue_redraw()

	func _draw() -> void:
		var r: = Rect2(Vector2.ZERO, size)
		draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.07), UITheme.CLEAR, UITheme.R_XS, 0, 0, 0), r)
		if not known:
			return
		var ratio: = clampf(hp, 0.0, 1.0)
		var w: = size.x * ratio
		if w >= 2.0:
			var hc: = UITheme.GOOD if ratio > 0.5 else (UITheme.WARN if ratio > 0.25 else UITheme.BAD)
			draw_style_box(UITheme.sbc(hc, UITheme.CLEAR, UITheme.R_XS, 0, 0, 0), Rect2(0, 0, w, size.y))
		if shield > 0.005:
			var sw: = size.x * clampf(shield, 0.0, 1.0)
			draw_rect(Rect2(minf(w, size.x - sw), 0, sw, size.y), Color(0.93, 0.96, 1.0, 0.75))


## Tiny horizontal meter for score / probability columns.
class MiniBar:
	extends Control
	var value: float = 0.0
	var col: Color = Color.WHITE

	func _init(v: float = 0.0, c: Color = Color.WHITE, w: float = 52.0) -> void:
		value = clampf(v, 0.0, 1.0)
		col = c
		custom_minimum_size = Vector2(w, 5)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		if value > 0.0:
			draw_rect(Rect2(0, 0, size.x * value, size.y), Color(col, 0.9))


## War Machine fuel pips (0..max), redrawn only when the value changes.
class FuelPips:
	extends Control
	var value: int = -1
	var max_value: int = 10

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int, m: int) -> void:
		if v != value or m != max_value:
			value = v
			max_value = m
			queue_redraw()

	func _draw() -> void:
		var n: int = maxi(1, max_value)
		var gap: float = 3.0
		var w: float = (size.x - gap * float(n - 1)) / float(n)
		for i in n:
			var r: = Rect2(float(i) * (w + gap), 0.0, w, size.y)
			draw_style_box(UITheme.sbc(Color("#ff8a3d") if i < value else Color(1, 1, 1, 0.07), UITheme.CLEAR, UITheme.R_XS, 0, 0, 0), r)


class AdvBar:
	extends Control
	var value: = 0.0

	func _draw() -> void :
		var w: = size.x
		var h: = size.y
		draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.07))
		var mid: = w * 0.5
		var k: = clampf(value / 1.5, -1.0, 1.0)
		var col: = UITheme.GOOD if k >= 0.0 else UITheme.BAD
		if k >= 0.0:
			draw_rect(Rect2(mid, 0, mid * k, h), col)
		else:
			draw_rect(Rect2(mid + mid * k, 0, - mid * k, h), col)
		draw_line(Vector2(mid, -2), Vector2(mid, h + 2), Color(1, 1, 1, 0.6), 1.0)


class ReadyPip:
	extends Control
	var prob: = 0.0
	var col: = Color.WHITE
	var glyph: = ""
	var seen: = false

	func _draw() -> void :
		var r: = Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(0, 0, size.x * clampf(prob, 0.0, 1.0), size.y), Color(col, 0.55 if prob < 0.95 else 0.85))
		draw_rect(r, Color(col, 0.6 if seen else 0.25), false, 1.0)
		var f: = DB.font_glyph
		draw_string(f, Vector2(4, size.y * 0.5 + 6), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		var f2: = DB.font_bold
		var s: = "%d%%" % int(prob * 100.0)
		var w: = f2.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f2, Vector2(size.x - w - 4, size.y * 0.5 + 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.92))


class StatBar:
	extends Control
	var label: = ""
	var value: = 0.0
	var max_value: = 1.0
	var col: = Color.WHITE

	func set_values(v: float, m: float) -> void:
		if not is_equal_approx(v, value) or not is_equal_approx(m, max_value):
			value = v
			max_value = m
			queue_redraw()

	func _draw() -> void :
		var f: = DB.font_regular
		draw_string(f, Vector2(0, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)
		var x0: = 72.0
		var w: = size.x - x0 - 52.0
		draw_rect(Rect2(x0, 5, w, 8), Color(1, 1, 1, 0.06))
		draw_rect(Rect2(x0, 5, w * clampf(value / maxf(0.001, max_value), 0.0, 1.0), 8), col)
		var s: = ("%.1f" % value) if label == "제어(초)" else str(int(value))
		draw_string(DB.font_bold, Vector2(size.x - 46, 13), s, HORIZONTAL_ALIGNMENT_RIGHT, 46, 12, UITheme.TEXT)
