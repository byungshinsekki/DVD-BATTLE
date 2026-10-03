class_name SetupScreen
extends Control
## 조합 대전: both teams are picked by hand, then two AIs fight it out.
## Layout: page header (status + actions) · settings card (victory rule / size / seed / AI) ·
## [team cards | arena strip + roster | character detail].
## The static helpers below (team slots, headers, composition chips, roster search) are shared with
## DraftScreen so both screens show teams the same way.

const ROSTER_MIN_W: = 158.0
const ROSTER_SEP: = 8
const ROLE_FILTERS: = [["", "전체"], ["FRONTLINE", "전방"], ["DAMAGE", "공격"], ["CONTROL", "제어"], ["SUPPORT", "지원"]]
const TEAM_NAMES: = ["청 팀", "홍 팀"]

var app: App
var size_n: int = 3
var arena_id: String = "classic"
var ruleset: String = "elimination"
var rules: RulesetSelector
var teams: Array = [[], []]
var active_team: int = 0
var role_filter: String = ""
var search: String = ""

var size_btns: Array = []
var size_seg: HBoxContainer
var arena_cards: Array = []
var arena_scroll: ScrollContainer
var arena_count: PanelContainer
var roster_cards: Array = []
var team_boxes: Array = []
var team_heads: Array = []
var team_cards: Array = []
var team_comp: Array = []
var summary_labels: Array = []
var seed_edit: LineEdit
var seed_btn: Button
var ai_opts: Array = []
var detail: CharDetail
var start_btn: Button
var status_l: Label
var arena_desc: Label
var roster_grid: GridContainer
var roster_scroll: ScrollContainer
var roster_hint: Label
var roster_empty: Control
var role_seg: HBoxContainer
var search_edit: LineEdit
var rng: = RandomNumberGenerator.new()
var _head_active: Array = [-1, -1]


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	rng.randomize()
	var v: = UITheme.vbox(UITheme.SP4)
	var pm: = UITheme.page_margin(v)
	pm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pm)

	# ---- page header
	status_l = UITheme.label("", "CaptionLabel")
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var rnd: = UITheme.button("무작위 편성", "", _randomize_all, "양 팀을 무작위 캐릭터로 모두 채웁니다.")
	var clr: = UITheme.button("초기화", "GhostButton", _clear, "양 팀을 모두 비웁니다.")
	start_btn = UITheme.button("전투 시작  ▶", "PrimaryButton", _start)
	start_btn.custom_minimum_size.x = 150
	v.add_child(UITheme.page_header("COMPOSITION", "조합 대전", "양 팀을 직접 편성하고 전장을 고른 뒤 전투를 시작하세요. 두 팀 모두 AI가 조종합니다.", [status_l, rnd, clr, start_btn]))

	# ---- settings card: rule row / size · seed · AI row
	var cfgv: = UITheme.vbox(UITheme.SP3)
	v.add_child(UITheme.panel("CardPanel", cfgv))
	rules = RulesetSelector.new()
	rules.changed.connect(_set_ruleset)
	cfgv.add_child(rules)
	cfgv.add_child(UITheme.sep_line())
	var cfg: = UITheme.hbox(UITheme.SP5)
	cfgv.add_child(cfg)
	var size_opts: Array = []
	for n in range(1, 6):
		size_opts.append([n, "%dv%d" % [n, n], "팀당 %d명" % n])
	size_seg = UITheme.segmented(size_opts, size_n, func(id): _set_team_size(int(id)), 50)
	var sb: Dictionary = size_seg.get_meta("buttons")
	for n in range(1, 6):
		size_btns.append(sb[n])
	cfg.add_child(field("전투 규모", size_seg))
	cfg.add_child(UITheme.sep_line(true))
	var sd: = UITheme.hbox(UITheme.SP2)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(118, 36)
	seed_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seed_edit.text = str(rng.randi_range(1, 99999999))
	seed_edit.tooltip_text = UITheme.tip("같은 시드와 같은 조합이면 전투가 똑같이 재현됩니다.")
	sd.add_child(seed_edit)
	seed_btn = UITheme.button("무작위", "", _roll_seed, "새 시드를 무작위로 정합니다.")
	seed_btn.custom_minimum_size = Vector2(0, 36)
	seed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sd.add_child(seed_btn)
	cfg.add_child(field("시드", sd))
	cfg.add_child(UITheme.sep_line(true))
	for t in 2:
		var ob: = OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for k in AIFactory.ORDER:
			ob.add_item(AIFactory.label(k))
		var key: String = "blue_ai" if t == 0 else "red_ai"
		ob.select(maxi(0, AIFactory.ORDER.find(str(Settings.get_v(key, AIFactory.ORDER[0])))))
		ob.custom_minimum_size = Vector2(200, 36)
		ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ob.tooltip_text = UITheme.tip("%s을 조종할 AI입니다. 고른 AI는 다음에도 유지됩니다." % TEAM_NAMES[t])
		# Remember the choice only when the user changes it (never on startup or navigation).
		ob.item_selected.connect(func(i: int) -> void:
			var kind: String = AIFactory.ORDER[clampi(i, 0, AIFactory.ORDER.size() - 1)]
			if str(Settings.get_v(key, "")) != kind:
				Settings.set_v(key, kind))
		ai_opts.append(ob)
		cfg.add_child(field("%s AI" % ("청" if t == 0 else "홍"), ob, UITheme.team_color(t)))

	# ---- main area
	var main: = UITheme.hbox(UITheme.SP4)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(main)

	var left: = UITheme.vbox(UITheme.SP3)
	for t in 2:
		left.add_child(_team_card(t))
	var left_col: = UITheme.vbox(UITheme.SP3)
	left_col.custom_minimum_size = Vector2(300, 0)
	left_col.add_child(UITheme.section_header("팀 편성", "편성할 팀을 눌러 고르세요"))
	var left_scroll: = UITheme.scroll(left)
	left_col.add_child(left_scroll)
	main.add_child(left_col)

	var center: = UITheme.vbox(UITheme.SP3)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_count = UITheme.badge("", UITheme.TEXT_DIM, "outline")
	var ah: = UITheme.section_header("전장", "", arena_count)
	arena_desc = ah.get_meta("hint")
	arena_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(ah)
	arena_scroll = ScrollContainer.new()
	arena_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	arena_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ahb: = UITheme.hbox(10)
	var card_h: = 0.0
	for a in DB.arenas:
		var card: = ArenaCard.new(a)
		var aid: String = a.id
		card.pressed.connect(func():
			if aid != arena_id:
				Sfx.play("click", 0.3)
			_set_arena(aid))
		arena_cards.append(card)
		ahb.add_child(card)
		card_h = maxf(card_h, card._get_minimum_size().y)
	arena_scroll.add_child(ahb)
	# Card height + horizontal scrollbar (6) + its separation (4) + slack: captions are never clipped.
	arena_scroll.custom_minimum_size = Vector2(0, card_h + 14.0)
	center.add_child(arena_scroll)

	role_seg = UITheme.segmented(ROLE_FILTERS, "", func(id): _set_role(str(id)))
	search_edit = search_box(func(t: String) -> void:
		search = t.strip_edges().to_lower()
		_refresh_roster())
	var trail: = UITheme.hbox(UITheme.SP2)
	trail.add_child(role_seg)
	trail.add_child(search_edit)
	var rh: = UITheme.section_header("캐릭터", "", trail)
	roster_hint = rh.get_meta("hint")
	center.add_child(rh)
	roster_grid = roster_grid_new()
	for c in DB.characters:
		var rc: = RosterCard.new(c)
		rc.custom_minimum_size.x = ROSTER_MIN_W
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = c.id
		rc.pressed.connect( func(): _pick(cid))
		rc.hovered_def.connect( func(d): detail.show_def(d))
		roster_cards.append(rc)
		roster_grid.add_child(rc)
	roster_empty = roster_empty_state(_clear_filters)
	var rbox: = UITheme.vbox(0)
	rbox.add_child(roster_grid)
	rbox.add_child(roster_empty)
	roster_scroll = UITheme.scroll(rbox)
	roster_scroll.resized.connect(func(): fit_roster_columns(roster_scroll, roster_grid))
	center.add_child(roster_scroll)
	main.add_child(center)

	var right: = UITheme.vbox(UITheme.SP3)
	right.custom_minimum_size = Vector2(360, 0)
	right.add_child(UITheme.section_header("캐릭터 정보", "카드에 마우스를 올려 보세요"))
	detail = CharDetail.new()
	var dp: = UITheme.panel("CardPanel", detail)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(dp)
	main.add_child(right)

	detail.show_def(DB.characters[0])
	_set_team_size(3)
	_set_ruleset("elimination")
	_randomize_all()


func on_show(args: Dictionary) -> void :
	if args.has("ruleset"):
		_set_ruleset(str(args.ruleset))
	_refresh()


func _set_ruleset(key: String) -> void:
	ruleset = "control" if key == "control" else "elimination"
	rules.set_ruleset(ruleset)
	var available: Array = DB.arenas_for(ruleset)
	for c in arena_cards:
		(c as ArenaCard).visible = c.arena.ruleset == ruleset
	if not available.is_empty() and DB.arena(arena_id).ruleset != ruleset:
		arena_id = available[0].id
	(arena_count.get_meta("label") as Label).text = "%s %d종" % [CodexData.arena_kind_label(ruleset), available.size()]
	arena_scroll.scroll_horizontal = 0
	_set_arena(arena_id)


func _set_team_size(n: int) -> void :
	size_n = clampi(n, 1, 5)
	UITheme.segmented_select(size_seg, size_n)
	for t in 2:
		while teams[t].size() > size_n:
			teams[t].pop_back()
	_refresh()


## Selects an arena (no sound: programmatic calls come from _ready, _set_ruleset and on_show).
func _set_arena(id: String) -> void :
	arena_id = id
	var sel: ArenaCard = null
	for c in arena_cards:
		(c as ArenaCard).set_selected(c.arena.id == id)
		if c.arena.id == id:
			sel = c
	var a: = DB.arena(id)
	var desc: = str(a.data.get("description", ""))
	arena_desc.text = "%s · %s" % [a.name, desc] if desc != "" else a.name
	arena_desc.tooltip_text = UITheme.tip("%s\n%s" % [a.name, desc])
	if sel and is_inside_tree():
		arena_scroll.ensure_control_visible.call_deferred(sel)


func _set_role(r: String, _btn: Button = null) -> void :
	role_filter = r
	UITheme.segmented_select(role_seg, r)
	_refresh_roster()


func _clear_filters() -> void:
	search = ""
	search_edit.text = ""
	_set_role("")


func _set_active(t: int) -> void :
	active_team = t
	_refresh()


func _roll_seed() -> void:
	seed_edit.text = str(rng.randi_range(1, 99999999))


func _pick(id: String) -> void :
	var t: = active_team
	if teams[t].has(id):
		teams[t].erase(id)
	elif teams[t].size() < size_n:
		teams[t].append(id)
		Sfx.play("pick", 0.35)
		if teams[t].size() >= size_n and teams[1 - t].size() < size_n:
			active_team = 1 - t
	else:
		app.toast("%s이 가득 찼어요. 슬롯을 눌러 빼거나 다른 팀을 고르세요." % TEAM_NAMES[t], UITheme.WARN)
	_refresh()


func _remove(t: int, i: int) -> void :
	if i < teams[t].size():
		teams[t].remove_at(i)
		active_team = t
		_refresh()


func _slot_pressed(t: int, i: int) -> void :
	if i < teams[t].size():
		_remove(t, i)
	else:
		_set_active(t)


func _randomize_all() -> void :
	var ids: = DB.ids().duplicate()
	for t in 2:
		teams[t] = []
		for i in size_n:
			teams[t].append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	active_team = 0
	_refresh()


func _clear() -> void :
	teams = [[], []]
	active_team = 0
	_refresh()


func _team_card(t: int) -> PanelContainer:
	var tv: = UITheme.vbox(UITheme.SP2)
	var th: = team_head_button(t, TEAM_NAMES[t])
	var tt: = t
	th.pressed.connect(func(): _set_active(tt))
	team_heads.append(th)
	tv.add_child(th)
	var box: = UITheme.vbox(6)
	team_boxes.append(box)
	tv.add_child(box)
	var comp: = comp_row()
	team_comp.append(comp)
	summary_labels.append(comp.get_meta("summary"))
	tv.add_child(comp)
	var card: = UITheme.styled_panel(team_card_style(t, false), tv)
	team_cards.append(card)
	return card


func _refresh() -> void :
	if team_boxes.is_empty():
		return
	for t in 2:
		var active: = active_team == t
		var box: VBoxContainer = team_boxes[t]
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		if _head_active[t] != int(active):
			_head_active[t] = int(active)
			(team_cards[t] as PanelContainer).add_theme_stylebox_override("panel", team_card_style(t, active))
		set_team_head(team_heads[t], teams[t].size(), size_n, "편성 중" if active else "", "눌러서 편성하세요" if not active else "")
		var slot_h: = 50 if size_n <= 3 else 44
		for i in size_n:
			box.add_child(_slot(t, i, slot_h))
		set_comp_row(team_comp[t], teams[t], "캐릭터를 골라 팀을 채우세요.")
	var is_ready: bool = teams[0].size() == size_n and teams[1].size() == size_n
	start_btn.disabled = not is_ready
	var need: int = (size_n - teams[0].size()) + (size_n - teams[1].size())
	if is_ready:
		status_l.text = "✓ 준비 완료"
		status_l.add_theme_color_override("font_color", UITheme.GOOD)
		start_btn.tooltip_text = UITheme.tip("지금 편성으로 %s 전투를 시작합니다." % CodexData.arena_kind_label(ruleset))
	else:
		status_l.text = "청 %d/%d · 홍 %d/%d · %d명 더 필요해요" % [teams[0].size(), size_n, teams[1].size(), size_n, need]
		status_l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		start_btn.tooltip_text = UITheme.tip("양 팀을 %d명씩 채워야 시작할 수 있어요. %d명 더 골라 주세요." % [size_n, need])
	_refresh_roster()


func _slot(t: int, i: int, h: int = 50) -> Control:
	var b: = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var filled: bool = i < teams[t].size()
	var next: bool = not filled and active_team == t and i == teams[t].size()
	var d: Defs.CharDef = null
	if filled:
		d = DB.char_def(teams[t][i])
	var styles: Dictionary = slot_styles(t, "filled" if filled else ("next" if next else "empty"))
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, styles[st])
	var trail: Control = null
	if filled:
		trail = UITheme.label("✕", "FaintLabel", 13)
		b.tooltip_text = "누르면 팀에서 뺍니다."
		b.mouse_entered.connect( func(): detail.show_def(d))
	else:
		b.tooltip_text = "캐릭터 목록에서 누르면 이 자리에 들어갑니다." if next else "눌러서 %s을 편성하세요." % TEAM_NAMES[t]
	var row: = slot_row(d, t, i, h, "캐릭터를 눌러 추가" if next else "빈 자리", next, trail)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	b.add_child(row)
	b.pressed.connect(_slot_pressed.bind(t, i))
	return b


func _refresh_roster() -> void :
	var shown_n: = 0
	for rc in roster_cards:
		var card: RosterCard = rc
		var d: = card.def
		var shown: = roster_matches(d, role_filter, search)
		card.visible = shown
		if shown:
			shown_n += 1
		var in0: bool = teams[0].has(d.id)
		var in1: bool = teams[1].has(d.id)
		if in0 and in1:
			card.set_picked(0, "양")
		elif in0:
			card.set_picked(0)
		elif in1:
			card.set_picked(1)
		else:
			card.set_picked(-1)
	roster_grid.visible = shown_n > 0
	roster_empty.visible = shown_n == 0
	var filtered: = role_filter != "" or search != ""
	roster_hint.text = "%s에 추가 중%s" % [TEAM_NAMES[active_team], (" · %d명 표시" % shown_n) if filtered and shown_n > 0 else ""]
	roster_hint.add_theme_color_override("font_color", UITheme.team_color(active_team).lightened(0.2))


func _start() -> void :
	if teams[0].size() != size_n or teams[1].size() != size_n:
		return
	var seed_v: = int(seed_edit.text) if seed_edit.text.is_valid_int() else rng.randi_range(1, 99999999)
	seed_edit.text = str(seed_v)
	var cfg: = {"blue": teams[0].duplicate(), "red": teams[1].duplicate(), "arena_id": arena_id, "seed": seed_v,
		"blue_ai": AIFactory.ORDER[(ai_opts[0] as OptionButton).selected], "red_ai": AIFactory.ORDER[(ai_opts[1] as OptionButton).selected], "mode": "composition", "ruleset": ruleset}
	Sfx.play("start", 0.5)
	app.start_battle(cfg, "setup")


# ================================================================== shared builders (setup + draft)

## "caption  control" pair for the settings card (caption optionally tinted).
static func field(caption: String, control: Control, color: Variant = null) -> HBoxContainer:
	var h: = UITheme.hbox(UITheme.SP2)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l: = UITheme.label(caption, "CaptionLabel") if color == null else UITheme.label(caption, "BoldLabel", 14, color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	return h


## Roster search field (clear button, 36 px tall). cb receives the raw text.
static func search_box(cb: Callable) -> LineEdit:
	var se: = LineEdit.new()
	se.placeholder_text = "이름·역할·태그 검색"
	se.clear_button_enabled = true
	se.custom_minimum_size = Vector2(176, 36)
	se.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	se.tooltip_text = "이름, 역할(전방·공격·제어·지원), 태그로 찾을 수 있어요."
	se.text_changed.connect(cb)
	return se


static func roster_grid_new() -> GridContainer:
	var g: = GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", ROSTER_SEP)
	g.add_theme_constant_override("v_separation", ROSTER_SEP)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


## Resizes the roster grid to as many >= ROSTER_MIN_W columns as fit (runs on resize only).
static func fit_roster_columns(scroll: ScrollContainer, grid: GridContainer) -> void:
	var w: = scroll.size.x - 12.0
	var cols: = clampi(int(floor((w + ROSTER_SEP) / (ROSTER_MIN_W + ROSTER_SEP))), 1, 12)
	if grid.columns != cols:
		grid.columns = cols


static func roster_empty_state(on_clear: Callable) -> Control:
	var e: = UITheme.empty_state("◎", "검색 결과가 없어요", "다른 이름이나 역할로 찾아보세요.")
	var b: = UITheme.button("검색 초기화", "GhostButton", on_clear)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.add_child(b)
	var m: = UITheme.margin(e, 0, 40, 0, 0)
	m.visible = false
	return m


static func roster_matches(d: Defs.CharDef, role: String, query: String) -> bool:
	if role != "" and d.role != role:
		return false
	if query == "":
		return true
	var hay: = ("%s %s %s %s %s" % [d.name, DB.role_label(d.role), " ".join(Array(d.tags).map( func(x): return DB.tag_label(x))), str(d.behavior.get("label", "")), d.id]).to_lower()
	return hay.contains(query)


## Team card surface (flat, no shadow: it lives in a ScrollContainer). Active = team-coloured border.
static func team_card_style(t: int, active: bool) -> StyleBoxFlat:
	var tc: = UITheme.team_color(t)
	if active:
		return UITheme.sbc(UITheme.PANEL2.lerp(tc, 0.06), Color(tc, 0.75), UITheme.R_L, 1, 12, 12)
	return UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_L, 1, 12, 12)


## Team header row as a flat Button: dot · name · count badge · spacer · state pill.
## Metas: "count" (badge), "pill" (badge), "hint" (Label).
static func team_head_button(t: int, title: String) -> Button:
	var b: = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 32)
	var tc: = UITheme.team_color(t)
	b.add_theme_stylebox_override("normal", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 6, 4))
	b.add_theme_stylebox_override("hover", UITheme.sbc(Color(1, 1, 1, 0.045), UITheme.CLEAR, UITheme.R_S, 0, 6, 4))
	b.add_theme_stylebox_override("pressed", UITheme.sbc(Color(tc, 0.1), UITheme.CLEAR, UITheme.R_S, 0, 6, 4))
	b.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(tc, 0.1), UITheme.CLEAR, UITheme.R_S, 0, 6, 4))
	b.add_theme_stylebox_override("disabled", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 6, 4))
	var row: = team_head_row(t, title)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -2
	b.add_child(row)
	for k in ["count", "pill", "hint"]:
		b.set_meta(k, row.get_meta(k))
	return b


## Header content (mouse-transparent): dot · name · count badge · spacer · hint · pill.
static func team_head_row(t: int, title: String) -> HBoxContainer:
	var tc: = UITheme.team_color(t)
	var h: = UITheme.hbox(UITheme.SP2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot: = Panel.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", UITheme.sbc(tc, UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0))
	h.add_child(dot)
	var name_l: = UITheme.label(title, "SubheadLabel", 0, tc.lightened(0.15))
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_l)
	var count: = UITheme.badge("0/0", UITheme.TEXT_DIM, "outline")
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(count)
	h.add_child(UITheme.spacer())
	var hint: = UITheme.label("", "FaintLabel")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(hint)
	var pill: = UITheme.badge("", tc, "strong")
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pill)
	h.set_meta("count", count)
	h.set_meta("pill", pill)
	h.set_meta("hint", hint)
	return h


## Updates a team_head_button()/team_head_row(): "n/size" count (GOOD when full), state pill, hint.
static func set_team_head(head: Control, n: int, cap_n: int, pill_text: String, hint_text: String = "") -> void:
	var count: PanelContainer = head.get_meta("count")
	var cl: Label = count.get_meta("label")
	cl.text = "%d/%d" % [n, cap_n]
	var full: = n >= cap_n
	count.add_theme_stylebox_override("panel", UITheme.sbc(Color(UITheme.GOOD, 0.12) if full else UITheme.CLEAR, Color(UITheme.GOOD, 0.5) if full else Color(UITheme.TEXT_DIM, 0.45), UITheme.R_PILL, 1, 8, 2))
	cl.add_theme_color_override("font_color", UITheme.GOOD.lightened(0.2) if full else UITheme.TEXT_DIM)
	var pill: PanelContainer = head.get_meta("pill")
	pill.visible = pill_text != ""
	(pill.get_meta("label") as Label).text = pill_text
	var hint: Label = head.get_meta("hint")
	hint.text = hint_text
	hint.visible = hint_text != ""


## Slot surface styles by state ("filled" / "next" / "empty"), all shared (sbc).
static func slot_styles(t: int, state: String) -> Dictionary:
	var tc: = UITheme.team_color(t)
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	match state:
		"filled":
			normal = UITheme.sbc(UITheme.PANEL3.lerp(tc, 0.05), Color(tc, 0.32), UITheme.R_M, 1, 8)
			hover = UITheme.sbc(UITheme.RAISED.lerp(tc, 0.06), Color(tc, 0.85), UITheme.R_M, 1, 8)
		"next":
			normal = UITheme.sbc(Color(tc, 0.07), Color(tc, 0.6), UITheme.R_M, 1, 8)
			hover = UITheme.sbc(Color(tc, 0.11), tc, UITheme.R_M, 1, 8)
		_:
			normal = UITheme.sbc(Color(0, 0, 0, 0.16), UITheme.LINE, UITheme.R_M, 1, 8)
			hover = UITheme.sbc(Color(1, 1, 1, 0.03), UITheme.LINE2, UITheme.R_M, 1, 8)
	return {"normal": normal, "hover": hover, "pressed": hover, "hover_pressed": hover}


## Slot content (mouse-transparent): pick number · disc · name + "역할 · 성향" · trailing control.
## d == null draws an empty slot with empty_text (team-tinted when highlight).
static func slot_row(d: Defs.CharDef, t: int, i: int, h: int, empty_text: String, highlight: bool = false, trailing: Control = null) -> HBoxContainer:
	var tc: = UITheme.team_color(t)
	var row: = UITheme.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num: = UITheme.label(str(i + 1), "CaptionLabel", 12, tc.lightened(0.1) if (d != null or highlight) else UITheme.TEXT_DISABLED)
	num.custom_minimum_size = Vector2(10, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num.add_theme_font_override("font", DB.font_black)
	row.add_child(num)
	var px: = clampi(h - 12, 28, 38)
	var disc: = GlyphDisc.new(d, px, t if d != null else -1)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(disc)
	var nv: = UITheme.vbox(0)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.custom_minimum_size = Vector2(10, 0)
	if d != null:
		var nl: = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel"))
		nl.custom_minimum_size = Vector2(10, 0)
		nv.add_child(nl)
		var beh: = str(d.behavior.get("label", ""))
		var sub: = UITheme.ellipsize(UITheme.label(DB.role_label(d.role) + (" · " + beh if beh != "" else ""), "", 12, UITheme.role_color(d.role)))
		sub.custom_minimum_size = Vector2(10, 0)
		nv.add_child(sub)
	else:
		var el: = UITheme.ellipsize(UITheme.label(empty_text, "FaintLabel", 13))
		if highlight:
			el.theme_type_variation = "BoldLabel"
			el.add_theme_color_override("font_color", tc.lightened(0.25))
		el.custom_minimum_size = Vector2(10, 0)
		nv.add_child(el)
	row.add_child(nv)
	if trailing:
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		trailing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(trailing)
	return row


## Composition row: role chips (flow) + "근접 n · 원거리 n" caption. Metas "chips" (HFlow), "summary" (Label).
static func comp_row() -> HBoxContainer:
	var h: = UITheme.hbox(UITheme.SP2)
	var flow: = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(flow)
	var s: = UITheme.label("", "CaptionLabel")
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	h.set_meta("chips", flow)
	h.set_meta("summary", s)
	return h


static func set_comp_row(row: HBoxContainer, ids: Array, empty_hint: String) -> void:
	var flow: HFlowContainer = row.get_meta("chips")
	for c in flow.get_children():
		flow.remove_child(c)
		c.queue_free()
	var s: Label = row.get_meta("summary")
	if ids.is_empty():
		flow.add_child(UITheme.label(empty_hint, "FaintLabel"))
		s.text = ""
		return
	var roles: = {}
	var melee: = 0
	for id in ids:
		var d: = DB.char_def(id)
		roles[d.role] = int(roles.get(d.role, 0)) + 1
		if d.is_melee():
			melee += 1
	for r in ["FRONTLINE", "DAMAGE", "CONTROL", "SUPPORT"]:
		if roles.has(r):
			flow.add_child(UITheme.badge("%s %d" % [DB.role_label(r), roles[r]], UITheme.role_color(r)))
	s.text = "근접 %d · 원거리 %d" % [melee, ids.size() - melee]
