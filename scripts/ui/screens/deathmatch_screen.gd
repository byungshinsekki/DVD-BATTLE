class_name DeathmatchScreen
extends Control

# Free-for-all setup (V1.5.1): 2–12 participants, one of three procedural maps
# (the seed decides the exact layout), kill target and time limit.
#
#   page header (actions + start status) · rule badges · config card
#   participants card | maps + roster | right tabs (character info / items)
#
# Hovering a roster card or a slot only updates the character detail; the
# right tab switches back to "캐릭터 정보" only on an explicit click.

const KILL_TARGETS := [5, 10, 15, 20, 30]
const TIME_LIMITS := [[180.0, "3분"], [300.0, "5분"], [420.0, "7분"], [600.0, "10분"]]
const ROLES := [["", "전체"], ["FRONTLINE", "전방"], ["DAMAGE", "공격"], ["CONTROL", "제어"], ["SUPPORT", "지원"]]
const SEED_MAX := 99999999
const LEFT_W := 296
const RIGHT_W := 344
const CARD_MIN_W := 158
const GRID_GAP := 8
const MAP_GAP := 12
# Column header height (section headers match the right TabBar so the cards line up).
const HEAD_H := 38
# Slot geometry, picked from the available height: two-line rows [height, gap] first,
# then single-line compact rows so 12 participants still fit at 1600x900.
const SLOT_TWO_LINE := [[48, 6], [45, 6], [42, 5]]
const SLOT_ONE_LINE := [[38, 4], [36, 4], [34, 3], [33, 3], [32, 3]]
const COUNT_COLORS := {"buildings": Color("#d9b98a"), "forests": Color("#7fd08a"), "items": Color("#f4c96b")}

var app: App
var players: Array = []
var size_n: int = 8
var map_id: String = DeathmatchMapData.ORDER[0]
var kill_target: int = 10
var time_limit: float = 420.0
var role_filter: String = ""
var search: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var size_seg: HBoxContainer
var kill_seg: HBoxContainer
var time_seg: HBoxContainer
var role_seg: HBoxContainer
var map_cards: Dictionary = {}
var map_row: HBoxContainer
var roster_cards: Array = []
var roster_scroll: ScrollContainer
var roster_grid: GridContainer
var roster_empty: Control
var slot_box: VBoxContainer
var slot_scroll: ScrollContainer
var slot_head: HBoxContainer
var count_holder: HBoxContainer
var comp_flow: VBoxContainer
var summary_l: Label
var seed_edit: LineEdit
var start_btn: Button
var start_hint: Label
var fill_btn: Button
var clear_btn: Button
var map_desc: Label
var detail: CharDetail
var right_tabs: TabBar
var detail_wrap: Control
var items_wrap: Control
var preview_seed: int = -1
var preview_timer: float = -1.0
var _slot_metrics: Array = []


func bind(a: App) -> void:
	app = a


func _ready() -> void:
	rng.randomize()
	var v: VBoxContainer = UITheme.vbox(UITheme.SP4)
	var root_margin: MarginContainer = UITheme.page_margin(v)
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_margin)

	var top: VBoxContainer = UITheme.vbox(UITheme.SP3)
	top.add_child(_build_header())
	top.add_child(_build_rules())
	v.add_child(top)
	v.add_child(_build_config())

	var main: HBoxContainer = UITheme.hbox(UITheme.SP4)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(main)
	main.add_child(_build_participants())
	main.add_child(_build_center())
	main.add_child(_build_right())

	_rebuild_maps(true)
	_set_player_count(8)
	_set_kills(10)
	_set_time(420.0)
	_randomize_all()
	detail.show_def(DB.char_def(players[0]) if not players.is_empty() else DB.characters[0])
	set_process(false)


# Debounced map preview rebuild after the seed changes (processing is off otherwise).
func _process(delta: float) -> void:
	if preview_timer < 0.0:
		set_process(false)
		return
	preview_timer -= delta
	if preview_timer < 0.0:
		set_process(false)
		_rebuild_maps(false)


func on_show(args: Dictionary) -> void:
	_refresh()
	if str(args.get("tab", "")) == "items":
		right_tabs.current_tab = 1


# Hover: update the detail only (never steals the item tab).
func _show_def(d: Defs.CharDef) -> void:
	if d != null:
		detail.show_def(d)


# Explicit click: show the character and bring the character tab forward.
func _focus_def(d: Defs.CharDef) -> void:
	_show_def(d)
	if right_tabs.current_tab != 0:
		right_tabs.current_tab = 0


# ------------------------------------------------------------------ build

func _build_header() -> Control:
	var rnd: Button = UITheme.button("↻ 무작위 참가자", "", _randomize_all, "지금 참가 인원만큼 참가자를 새로 무작위로 뽑습니다.")
	fill_btn = UITheme.button("빈 자리 채우기", "", _fill_rest, "비어 있는 자리만 무작위 영웅으로 채웁니다. 이미 고른 참가자는 그대로 둡니다.")
	clear_btn = UITheme.button("초기화", "GhostButton", _clear, "참가자를 모두 뺍니다. 전장과 경기 설정은 그대로 유지됩니다.")
	start_hint = UITheme.label("", "CaptionLabel")
	start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	start_hint.custom_minimum_size = Vector2(128, 0)
	start_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	start_btn = UITheme.button("전투 시작  ▶", "PrimaryButton", _start)
	start_btn.custom_minimum_size = Vector2(156, 44)
	return UITheme.page_header("FREE FOR ALL", "데스매치",
		"최대 12명이 각자 싸우는 개인전입니다. 참가자와 전장을 고른 뒤 전투를 시작하세요.",
		[rnd, fill_btn, clear_btn, start_hint, start_btn])


func _build_rules() -> Control:
	var h: HBoxContainer = UITheme.hbox(6)
	var cap: Label = UITheme.label("경기 규칙", "CaptionLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap)
	h.add_child(UITheme.spacer(2, 0))
	var brawl_pct: int = int(round((DeathmatchMode.BRAWL_DAMAGE - 1.0) * 100.0))
	var respawn: int = int(round(DeathmatchMode.RESPAWN_DELAY))
	var rules: Array = [
		["처치 +1점", "적 영웅을 쓰러뜨리면 1점을 얻습니다. 쓰러지기 전 %d초 안에 피해를 준 다른 영웅에게는 도움이 기록됩니다." % int(DeathmatchMode.ASSIST_WINDOW)],
		["%d초 뒤 재출전" % respawn, "쓰러지면 %d초 뒤 적에게서 먼 곳에서 다시 나오고, %d초 동안 보호받습니다. 공격하면 보호가 풀립니다." % [respawn, int(DeathmatchMode.SPAWN_PROTECTION)]],
		["영웅이 받는 피해 +%d%%" % brawl_pct, "영웅이 받는 피해가 %d%% 늘어나 1대1 교전이 빨리 끝납니다." % brawl_pct],
		["아이템 보유 %d칸" % DeathmatchMode.SLOTS, "영웅마다 아이템을 %d개까지 들 수 있고 같은 아이템은 겹쳐 가질 수 없습니다. 쓰러지면 가장 높은 등급 1개만 떨어뜨립니다." % DeathmatchMode.SLOTS],
		["필드 최대 %d개" % DeathmatchMode.MAX_FIELD_ITEMS, "필드에는 아이템이 최대 %d개까지 놓이고, 그보다 적으면 몇 초마다 새 아이템이 하나씩 생깁니다." % DeathmatchMode.MAX_FIELD_ITEMS],
	]
	for r in rules:
		var b: PanelContainer = UITheme.badge(str(r[0]), UITheme.TEXT_DIM, "soft", str(r[1]))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	var info: PanelContainer = UITheme.badge("ⓘ 규칙 자세히", UITheme.ACCENT, "outline", _rules_tooltip())
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_default_cursor_shape = Control.CURSOR_HELP
	h.add_child(info)
	return h


func _rules_tooltip() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"승리 — 목표 처치 수에 먼저 도달하면 우승합니다. 제한 시간이 끝나면 처치 순위로 정하며, 동률이면 사망이 적은 쪽, 그다음 피해를 많이 준 쪽이 앞섭니다.",
		"재출전 — 쓰러지면 %d초 뒤 적에게서 먼 곳에서 다시 나오고 %d초 동안 보호받습니다." % [int(DeathmatchMode.RESPAWN_DELAY), int(DeathmatchMode.SPAWN_PROTECTION)],
		"아이템 — %d칸까지 들 수 있습니다. 쓰러지면 가장 높은 등급 1개만 그 자리에 떨어지고 나머지는 사라집니다." % DeathmatchMode.SLOTS,
		"회복 — 7초 동안 피해를 주거나 받지 않으면 초당 최대 체력의 1.5%를 회복합니다.",
		"숲 — 숲 안의 영웅은 110 거리 안으로 다가오거나 교전하기 전까지 밖에서 보이지 않습니다.",
	])
	var out: PackedStringArray = PackedStringArray()
	for l in lines:
		out.append(UITheme.tip(l, 44))
	return "\n\n".join(out)


func _build_config() -> Control:
	var row: HBoxContainer = UITheme.hbox(0)
	var sizes: Array = []
	for n in range(2, 13):
		sizes.append([n, str(n)])
	size_seg = UITheme.segmented(sizes, size_n, func(id): _set_player_count(int(id)), 38)
	row.add_child(_field("참가 인원", size_seg, "함께 싸울 영웅 수입니다. 인원을 늘리면 빈 자리가 생기고, 줄이면 뒤쪽 참가자부터 빠집니다."))
	row.add_child(_vsep())
	var kills: Array = []
	for k in KILL_TARGETS:
		kills.append([k, str(k)])
	kill_seg = UITheme.segmented(kills, kill_target, func(id): _set_kills(int(id)), 38)
	row.add_child(_field("목표 처치", kill_seg, "이 처치 수에 먼저 도달한 참가자가 바로 우승합니다."))
	row.add_child(_vsep())
	var times: Array = []
	for t in TIME_LIMITS:
		times.append([float(t[0]), str(t[1])])
	time_seg = UITheme.segmented(times, time_limit, func(id): _set_time(float(id)), 44)
	row.add_child(_field("제한 시간", time_seg, "시간이 끝나면 처치 수로 순위를 정합니다(동률이면 사망이 적은 쪽, 그다음 피해가 많은 쪽)."))
	row.add_child(_vsep())

	var sd: HBoxContainer = UITheme.hbox(UITheme.SP2)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(124, 40)
	seed_edit.max_length = 9
	seed_edit.placeholder_text = "숫자 입력"
	seed_edit.text = str(rng.randi_range(1, SEED_MAX))
	seed_edit.tooltip_text = UITheme.tip("같은 시드·참가자·전장이면 지형·아이템·전투가 똑같이 재현됩니다. 숫자를 바꾸면 전장 미리보기가 바로 바뀝니다.")
	seed_edit.text_changed.connect(_on_seed_text)
	sd.add_child(seed_edit)
	var reroll: Button = UITheme.button("무작위", "", _reroll_seed, "새 시드를 뽑아 전장 배치를 바꿉니다.")
	reroll.custom_minimum_size = Vector2(0, 40)
	sd.add_child(reroll)
	row.add_child(_field("시드", sd, "전장 배치와 아이템 생성을 정하는 번호입니다."))
	var card: PanelContainer = UITheme.panel("CardPanel", UITheme.margin(row, 4, 2, 4, 2))
	return card


# Caption over a control (config fields).
func _field(caption: String, control: Control, tooltip: String) -> Control:
	var v: VBoxContainer = UITheme.vbox(6)
	var c: Label = UITheme.label(caption, "CaptionLabel")
	c.tooltip_text = UITheme.tip(tooltip)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(c)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(control)
	return v


# Hairline between config fields; the gaps share any spare width so the fields spread evenly.
func _vsep() -> Control:
	var line: Control = UITheme.sep_line(true)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var m: MarginContainer = UITheme.margin(line, UITheme.SP4, 4, UITheme.SP4, 4)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _build_participants() -> Control:
	var col: VBoxContainer = UITheme.vbox(UITheme.SP3)
	col.custom_minimum_size = Vector2(LEFT_W, 0)
	count_holder = UITheme.hbox(0)
	slot_head = UITheme.section_header("참가자", "", count_holder)
	slot_head.custom_minimum_size = Vector2(0, HEAD_H)
	col.add_child(slot_head)
	var v: VBoxContainer = UITheme.vbox(UITheme.SP3)
	slot_box = UITheme.vbox(6)
	slot_scroll = UITheme.scroll(slot_box)
	slot_scroll.resized.connect(_on_slot_area_resized)
	v.add_child(slot_scroll)
	v.add_child(UITheme.sep_line())
	comp_flow = UITheme.vbox(6)
	v.add_child(comp_flow)
	summary_l = UITheme.hint_label("모든 참가자는 데스매치 AI가 조종합니다.")
	summary_l.tooltip_text = UITheme.tip("참가자마다 자기 시야와 전투 소리만으로 적을 찾아 추적하고, 필드 아이템이 자기 영웅에게 맞는지 따져 필요할 때만 줍거나 교체합니다.")
	summary_l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(summary_l)
	var card: PanelContainer = UITheme.panel("CardPanel", v)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(card)
	return col


func _build_center() -> Control:
	var c: VBoxContainer = UITheme.vbox(UITheme.SP3)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = 1.8
	var mh: HBoxContainer = UITheme.section_header("전장", "")
	mh.custom_minimum_size = Vector2(0, HEAD_H)
	map_desc = mh.get_meta("hint")
	map_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(mh)
	map_row = UITheme.hbox(MAP_GAP)
	c.add_child(map_row)

	role_seg = UITheme.segmented(ROLES, role_filter, func(id): _set_role(str(id)))
	var se: LineEdit = LineEdit.new()
	se.placeholder_text = "이름·역할·태그 검색"
	se.clear_button_enabled = true
	se.custom_minimum_size = Vector2(176, 38)
	se.text_changed.connect(func(t): search = t.strip_edges().to_lower(); _refresh_roster())
	var tools: HBoxContainer = UITheme.hbox(UITheme.SP2)
	tools.add_child(role_seg)
	tools.add_child(se)
	var rh: HBoxContainer = UITheme.section_header("캐릭터", "눌러서 추가·제외", tools)
	c.add_child(UITheme.margin(rh, 0, 4, 0, 0))

	roster_grid = GridContainer.new()
	roster_grid.columns = 3
	roster_grid.add_theme_constant_override("h_separation", GRID_GAP)
	roster_grid.add_theme_constant_override("v_separation", GRID_GAP)
	roster_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for cd in DB.characters:
		var rc: RosterCard = RosterCard.new(cd)
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = cd.id
		rc.pressed.connect(func(): _on_roster_pressed(cid))
		rc.hovered_def.connect(_show_def)
		roster_cards.append(rc)
		roster_grid.add_child(rc)
	var rv: VBoxContainer = UITheme.vbox(0)
	rv.add_child(roster_grid)
	roster_empty = UITheme.empty_state("◎", "찾는 영웅이 없습니다", "다른 이름이나 역할로 검색하거나 역할 필터를 ‘전체’로 바꿔 보세요.")
	roster_empty.visible = false
	rv.add_child(UITheme.margin(roster_empty, 0, 40, 0, 0))
	roster_scroll = UITheme.scroll(rv)
	roster_scroll.resized.connect(_fit_roster_columns)
	c.add_child(roster_scroll)
	return c


func _build_right() -> Control:
	var r: VBoxContainer = UITheme.vbox(UITheme.SP3)
	r.custom_minimum_size = Vector2(RIGHT_W, 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_stretch_ratio = 1.0
	right_tabs = TabBar.new()
	right_tabs.focus_mode = Control.FOCUS_NONE
	right_tabs.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	right_tabs.add_tab("캐릭터 정보")
	right_tabs.add_tab("아이템 %d" % ItemDefs.ORDER.size())
	right_tabs.set_tab_tooltip(0, "마우스를 올리거나 누른 영웅의 능력치와 스킬을 봅니다.")
	right_tabs.set_tab_tooltip(1, "필드에 나오는 아이템 %d종과 등급별 출현 확률을 봅니다." % ItemDefs.ORDER.size())
	right_tabs.tab_changed.connect(_on_tab)
	# Hairline under the whole tab strip so the unselected tab still reads as a tab.
	var strip: StyleBoxFlat = StyleBoxFlat.new()
	strip.bg_color = UITheme.CLEAR
	strip.border_color = UITheme.LINE
	strip.border_width_bottom = 1
	var tabs_wrap: PanelContainer = UITheme.styled_panel(strip, right_tabs)
	tabs_wrap.custom_minimum_size = Vector2(0, HEAD_H)
	right_tabs.size_flags_vertical = Control.SIZE_SHRINK_END
	r.add_child(tabs_wrap)
	detail = CharDetail.new()
	var dp: PanelContainer = UITheme.panel("CardPanel", detail)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_wrap = dp
	r.add_child(dp)
	items_wrap = _build_item_codex()
	items_wrap.visible = false
	r.add_child(items_wrap)
	return r


func _on_tab(i: int) -> void:
	detail_wrap.visible = i == 0
	items_wrap.visible = i == 1


# Compact item codex (ItemViews) plus a link to the full item codex.
func _build_item_codex() -> Control:
	var v: VBoxContainer = UITheme.vbox(UITheme.SP3)
	var list: Control = ItemViews.codex_list(true)
	var sc: ScrollContainer = UITheme.scroll(UITheme.margin(list, 0, 0, 6, 0))
	v.add_child(sc)
	v.add_child(UITheme.sep_line())
	var link: Button = UITheme.button("전투 도감에서 자세히 보기  →", "GhostButton", _open_item_codex,
		"아이템마다 상세 규칙과 잘 맞는 영웅을 전투 도감의 아이템 탭에서 볼 수 있습니다.")
	link.custom_minimum_size = Vector2(0, 38)
	v.add_child(link)
	var p: PanelContainer = UITheme.panel("CardPanel", v)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


func _open_item_codex() -> void:
	if app:
		app.goto("codex", {"mode": "items"})


# ------------------------------------------------------------------ maps

func _seed_value() -> int:
	return int(seed_edit.text) if seed_edit.text.is_valid_int() else 1


# Digits only; the preview follows after a short pause.
func _on_seed_text(t: String) -> void:
	var clean: String = ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			clean += ch
	if clean != t:
		var caret: int = seed_edit.caret_column - (t.length() - clean.length())
		seed_edit.text = clean
		seed_edit.caret_column = clampi(caret, 0, clean.length())
	preview_timer = 0.45
	set_process(true)


func _reroll_seed() -> void:
	seed_edit.text = str(rng.randi_range(1, SEED_MAX))
	preview_timer = 0.05
	set_process(true)


func _rebuild_maps(force: bool) -> void:
	var sv: int = _seed_value()
	if sv == preview_seed and not force:
		return
	preview_seed = sv
	for c in map_row.get_children():
		map_row.remove_child(c)
		c.queue_free()
	map_cards.clear()
	for id in DeathmatchMapData.ORDER:
		var arena: Arena = DB.deathmatch_arena(id, sv)
		var cnt: Dictionary = CodexData.dm_counts(arena)
		var col: VBoxContainer = UITheme.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card: ArenaCard = ArenaCard.new(arena)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(180, card.custom_minimum_size.y)
		card.tooltip_text = UITheme.tip("%s\n시드 %d로 만든 실제 배치입니다. 누르면 이 전장을 고릅니다." % [str(arena.data.get("description", "")), sv])
		var mid: String = id
		card.pressed.connect(func(): _set_map(mid))
		map_cards[id] = card
		col.add_child(card)
		var chips: HFlowContainer = HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 4)
		chips.add_theme_constant_override("v_separation", 4)
		chips.add_child(UITheme.badge("건물 %d" % int(cnt.buildings), COUNT_COLORS.buildings, "soft",
			"벽이 이동·투사체·시야를 모두 막는 건물입니다. 건물 안에는 아이템 자리가 있습니다."))
		chips.add_child(UITheme.badge("숲 %d" % int(cnt.forests), COUNT_COLORS.forests, "soft",
			"숲 안의 영웅은 가까이 다가오거나 교전하기 전까지 밖에서 보이지 않습니다."))
		chips.add_child(UITheme.badge("아이템 위치 %d" % int(cnt.item_spots), COUNT_COLORS.items, "soft",
			"아이템이 생길 수 있는 지점 수입니다. 필드에는 한 번에 최대 %d개까지 놓입니다." % DeathmatchMode.MAX_FIELD_ITEMS))
		col.add_child(chips)
		map_row.add_child(col)
	_set_map(map_id)


func _set_map(id: String) -> void:
	map_id = id
	for k in map_cards:
		(map_cards[k] as ArenaCard).set_selected(k == id)
	var p: Dictionary = DeathmatchMapData.PRESETS.get(id, {})
	map_desc.text = "%s — %s" % [str(p.get("name", id)), str(p.get("description", ""))]
	map_desc.tooltip_text = UITheme.tip(map_desc.text)
	_refresh_start()


# ------------------------------------------------------------------ settings

func _set_player_count(n: int) -> void:
	size_n = clampi(n, 2, 12)
	UITheme.segmented_select(size_seg, size_n)
	while players.size() > size_n:
		players.pop_back()
	_refresh()


func _set_kills(k: int) -> void:
	kill_target = k
	UITheme.segmented_select(kill_seg, k)
	_refresh_start()


func _set_time(t: float) -> void:
	time_limit = t
	UITheme.segmented_select(time_seg, t)
	_refresh_start()


func _set_role(r: String) -> void:
	role_filter = r
	UITheme.segmented_select(role_seg, r)
	_refresh_roster()


# ------------------------------------------------------------------ roster

func _on_roster_pressed(id: String) -> void:
	_pick(id)
	_focus_def(DB.char_def(id))


func _pick(id: String) -> void:
	if players.has(id):
		players.erase(id)
	elif players.size() < size_n:
		players.append(id)
		Sfx.play("pick", 0.35)
	elif app:
		app.toast("참가 인원이 가득 찼습니다. 참가자를 한 명 빼거나 참가 인원을 늘려 주세요.", UITheme.WARN)
	_refresh()


func _randomize_all() -> void:
	players.clear()
	_fill_rest()


func _fill_rest() -> void:
	var pool: Array = DB.ids().duplicate()
	for id in players:
		pool.erase(id)
	while players.size() < size_n and not pool.is_empty():
		players.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	_refresh()


func _clear() -> void:
	players.clear()
	_refresh()


func _refresh() -> void:
	if slot_box == null:
		return
	_rebuild_slots()
	var missing: int = size_n - players.size()
	for c in count_holder.get_children():
		count_holder.remove_child(c)
		c.queue_free()
	count_holder.add_child(UITheme.badge("%d / %d" % [players.size(), size_n], UITheme.GOOD if missing == 0 else UITheme.WARN, "soft"))
	_refresh_composition()
	start_btn.disabled = players.size() != size_n or players.size() < 2
	_refresh_start()
	fill_btn.disabled = missing <= 0
	fill_btn.tooltip_text = UITheme.tip("모든 자리가 찼습니다. 참가 인원을 늘리거나 참가자를 빼면 다시 쓸 수 있습니다." if fill_btn.disabled
		else "비어 있는 %d자리만 무작위 영웅으로 채웁니다. 이미 고른 참가자는 그대로 둡니다." % missing)
	clear_btn.disabled = players.is_empty()
	clear_btn.tooltip_text = UITheme.tip("뺄 참가자가 없습니다." if clear_btn.disabled
		else "참가자를 모두 뺍니다. 전장과 경기 설정은 그대로 유지됩니다.")
	_refresh_roster()


# Start status next to the start button: why it is disabled, or what will start.
func _refresh_start() -> void:
	if start_btn == null or start_hint == null:
		return
	var missing: int = size_n - players.size()
	var tip: String
	if start_btn.disabled:
		start_hint.text = "%d명 더 선택하세요" % missing
		start_hint.add_theme_color_override("font_color", UITheme.WARN)
		tip = "참가자를 %d명 더 선택해야 전투를 시작할 수 있습니다. ‘빈 자리 채우기’로 남은 자리를 한 번에 채울 수 있습니다." % missing
	else:
		start_hint.text = "%d명 준비 완료" % players.size()
		start_hint.add_theme_color_override("font_color", UITheme.GOOD)
		tip = "%d명이 %s에서 개인전을 시작합니다 · 목표 %d킬 · 제한 %s" % [players.size(), str((DeathmatchMapData.PRESETS.get(map_id, {}) as Dictionary).get("name", map_id)), kill_target, _time_label(time_limit)]
	start_btn.tooltip_text = UITheme.tip(tip)
	start_hint.tooltip_text = start_btn.tooltip_text


func _time_label(t: float) -> String:
	for row in TIME_LIMITS:
		if absf(float(row[0]) - t) < 0.5:
			return str(row[1])
	return UITheme.fmt_time(t)


# Role and range chips under the slot list (roles on the first row, range on the second).
func _refresh_composition() -> void:
	for c in comp_flow.get_children():
		comp_flow.remove_child(c)
		c.queue_free()
	if players.is_empty():
		comp_flow.add_child(UITheme.label("참가자를 고르면 역할 구성이 표시됩니다.", "FaintLabel"))
		return
	var roles: Dictionary = {}
	var melee: int = 0
	for id in players:
		var d: Defs.CharDef = DB.char_def(id)
		roles[d.role] = int(roles.get(d.role, 0)) + 1
		if d.is_melee():
			melee += 1
	var role_row: HBoxContainer = UITheme.hbox(6)
	role_row.add_child(_comp_caption("역할"))
	for r in ["FRONTLINE", "DAMAGE", "CONTROL", "SUPPORT"]:
		if roles.has(r):
			role_row.add_child(UITheme.badge("%s %d" % [DB.role_label(r), roles[r]], UITheme.role_color(r), "soft"))
	comp_flow.add_child(role_row)
	var range_row: HBoxContainer = UITheme.hbox(6)
	range_row.add_child(_comp_caption("사거리"))
	range_row.add_child(UITheme.badge("근접 %d" % melee, UITheme.TEXT_DIM, "outline", "기본 공격 사거리가 100 이하인 영웅 수입니다."))
	range_row.add_child(UITheme.badge("원거리 %d" % (players.size() - melee), UITheme.TEXT_DIM, "outline", "기본 공격 사거리가 100보다 긴 영웅 수입니다."))
	comp_flow.add_child(range_row)


func _comp_caption(text: String) -> Label:
	var l: Label = UITheme.label(text, "CaptionLabel")
	l.custom_minimum_size = Vector2(40, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# [height, gap, compact] for the slot rows that fit the visible list height.
func _slot_layout() -> Array:
	var avail: float = slot_scroll.size.y if slot_scroll != null and slot_scroll.size.y > 1.0 else 420.0
	var n: int = maxi(1, size_n)
	for m in SLOT_TWO_LINE:
		if n * int(m[0]) + (n - 1) * int(m[1]) <= avail:
			return [int(m[0]), int(m[1]), false]
	for m in SLOT_ONE_LINE:
		if n * int(m[0]) + (n - 1) * int(m[1]) <= avail:
			return [int(m[0]), int(m[1]), true]
	var last: Array = SLOT_ONE_LINE[SLOT_ONE_LINE.size() - 1]
	return [int(last[0]), int(last[1]), true]


func _rebuild_slots() -> void:
	var m: Array = _slot_layout()
	if _slot_metrics.is_empty() or int(_slot_metrics[1]) != int(m[1]):
		slot_box.add_theme_constant_override("separation", int(m[1]))
	_slot_metrics = m
	for c in slot_box.get_children():
		slot_box.remove_child(c)
		c.queue_free()
	for i in size_n:
		slot_box.add_child(_slot(i, int(m[0]), bool(m[2])))


# The list height changes with the window: re-pick the row size only when it differs.
func _on_slot_area_resized() -> void:
	if slot_box == null or _slot_metrics.is_empty():
		return
	if _slot_layout() != _slot_metrics:
		_rebuild_slots()


func _slot(i: int, h_px: int, compact: bool) -> Control:
	var filled: bool = i < players.size()
	var tc: Color = UITheme.team_color(i)
	var h: HBoxContainer = UITheme.hbox(10 if not compact else 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num: PanelContainer = UITheme.badge("P%d" % (i + 1), tc, "solid" if filled else "outline")
	num.custom_minimum_size = Vector2(36, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not filled:
		num.modulate = Color(1, 1, 1, 0.55)
	h.add_child(num)
	if not filled:
		var t: Label = UITheme.ellipsize(UITheme.label("빈 자리 — 오른쪽 목록에서 선택", "FaintLabel"))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		var p: PanelContainer = UITheme.styled_panel(UITheme.sbc(Color(0, 0, 0, 0.14), UITheme.CLEAR, UITheme.R_M, 0, 0, 0),
			UITheme.margin(h, 14, 0, 8, 0))
		p.custom_minimum_size = Vector2(0, h_px)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.tooltip_text = "오른쪽 캐릭터 목록에서 영웅을 누르면 이 자리에 들어갑니다."
		p.draw.connect(func(): _draw_dashed(p))
		return p

	var d: Defs.CharDef = DB.char_def(players[i])
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, h_px)
	b.add_theme_stylebox_override("normal", UITheme.sbc(Color(1, 1, 1, 0.03), UITheme.LINE, UITheme.R_M, 1, 0, 0))
	b.add_theme_stylebox_override("hover", UITheme.sbc(Color(1, 1, 1, 0.06), Color(tc, 0.7), UITheme.R_M, 1, 0, 0))
	b.add_theme_stylebox_override("pressed", UITheme.sbc(Color(1, 1, 1, 0.06), tc, UITheme.R_M, 1, 0, 0))
	b.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(1, 1, 1, 0.06), tc, UITheme.R_M, 1, 0, 0))
	b.add_theme_stylebox_override("focus", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, 0, 0, 0, 0))
	b.tooltip_text = UITheme.tip("%s · %s · %s\n누르면 오른쪽에 정보를 보여 줍니다. ✕를 누르면 참가자에서 뺍니다." % [d.name, DB.role_label(d.role), str(d.behavior.get("label", ""))])
	b.draw.connect(func(): b.draw_style_box(UITheme.sbc(tc, UITheme.CLEAR, 2, 0, 0, 0), Rect2(5, 9, 3, b.size.y - 18)))
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -6
	b.add_child(h)
	var disc: GlyphDisc = GlyphDisc.new(d, clampi(h_px - 12, 22, 34), i)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	# Two lines (name / role · 성향) when there is room, one line when compact.
	var nv: BoxContainer
	if compact:
		nv = UITheme.hbox(8)
	else:
		nv = UITheme.vbox(0)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.alignment = BoxContainer.ALIGNMENT_BEGIN if compact else BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm: Label = UITheme.label(d.name, "BoldLabel", 14 if compact else 15)
	if not compact:
		UITheme.ellipsize(nm)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nv.add_child(nm)
	var beh: String = str(d.behavior.get("label", ""))
	var sub: Label = UITheme.ellipsize(UITheme.label(DB.role_label(d.role) + (" · " + beh if beh != "" else ""), "", 12, UITheme.role_color(d.role)))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.custom_minimum_size = Vector2(10, 0)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if compact:
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(sub)
	h.add_child(nv)
	var pid: String = players[i]
	var rm: Button = Button.new()
	rm.text = "✕"
	rm.focus_mode = Control.FOCUS_NONE
	rm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rm.custom_minimum_size = Vector2(26, 26) if compact else Vector2(28, 28)
	rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rm.tooltip_text = "%s 빼기" % d.name
	rm.add_theme_font_size_override("font_size", 13)
	rm.add_theme_stylebox_override("normal", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("hover", UITheme.sbc(Color(UITheme.BAD, 0.16), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("pressed", UITheme.sbc(Color(UITheme.BAD, 0.26), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(UITheme.BAD, 0.26), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("focus", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, 0, 0, 0, 0))
	rm.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	rm.add_theme_color_override("font_hover_color", UITheme.BAD)
	rm.add_theme_color_override("font_pressed_color", UITheme.BAD)
	rm.add_theme_color_override("font_hover_pressed_color", UITheme.BAD)
	rm.pressed.connect(func(): _pick(pid))
	h.add_child(rm)
	b.mouse_entered.connect(func(): _show_def(d))
	b.pressed.connect(func(): _focus_def(d))
	return b


# Dashed rounded outline for empty slots (drawn only on redraw).
func _draw_dashed(ci: Control) -> void:
	var col: Color = Color(UITheme.LINE2, 0.9)
	var r: float = float(UITheme.R_M)
	var x0: float = 0.5
	var y0: float = 0.5
	var x1: float = ci.size.x - 0.5
	var y1: float = ci.size.y - 0.5
	ci.draw_dashed_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), col, 1.0, 5.0)
	ci.draw_dashed_line(Vector2(x0 + r, y1), Vector2(x1 - r, y1), col, 1.0, 5.0)
	ci.draw_dashed_line(Vector2(x0, y0 + r), Vector2(x0, y1 - r), col, 1.0, 5.0)
	ci.draw_dashed_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), col, 1.0, 5.0)
	ci.draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, 8, col, 1.0, true)
	ci.draw_arc(Vector2(x1 - r, y0 + r), r, PI * 1.5, TAU, 8, col, 1.0, true)
	ci.draw_arc(Vector2(x1 - r, y1 - r), r, 0.0, PI * 0.5, 8, col, 1.0, true)
	ci.draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, 8, col, 1.0, true)


func _refresh_roster() -> void:
	var shown_n: int = 0
	for rc in roster_cards:
		var card: RosterCard = rc
		var d: Defs.CharDef = card.def
		var shown: bool = role_filter == "" or d.role == role_filter
		if shown and search != "":
			var hay: String = ("%s %s %s %s" % [d.name, DB.role_label(d.role), " ".join(Array(d.tags).map(func(x): return DB.tag_label(x))), d.id]).to_lower()
			shown = hay.contains(search)
		card.visible = shown
		if shown:
			shown_n += 1
		var at: int = players.find(d.id)
		card.set_picked(at, "P%d" % (at + 1) if at >= 0 else "")
	if roster_empty:
		roster_empty.get_parent().visible = shown_n == 0
		roster_empty.visible = shown_n == 0


# Column count follows the available width so cards fill the row (no dead space).
func _fit_roster_columns() -> void:
	var w: float = roster_scroll.size.x - 12.0
	var cols: int = maxi(1, int(floor((w + GRID_GAP) / float(CARD_MIN_W + GRID_GAP))))
	if cols != roster_grid.columns:
		roster_grid.columns = cols


# ------------------------------------------------------------------ start

func _start() -> void:
	if players.size() != size_n or players.size() < 2:
		return
	var seed_v: int = int(seed_edit.text) if seed_edit.text.is_valid_int() else rng.randi_range(1, SEED_MAX)
	seed_edit.text = str(seed_v)
	var cfg: Dictionary = {"ruleset": "deathmatch", "mode": "deathmatch", "arena_id": map_id, "players": players.duplicate(),
		"seed": seed_v, "kill_target": kill_target, "max_time": time_limit, "ai": "tactician"}
	Sfx.play("start", 0.5)
	app.start_battle(cfg, "deathmatch")
