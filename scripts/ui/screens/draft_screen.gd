class_name DraftScreen
extends Control
## AI 대전: the player and the drafting AI pick one character at a time (나 → AI → 나 ...).
## Layout: page header (status + actions) · settings card (rule / size / arena / seed, locked after
## the first pick) · [turn panel + teams + evaluation | roster | tabs "AI 분석 / 캐릭터 / 기록"].
## The AI search runs incrementally in _process (8 ms slices); tests drive _ai_think/_process directly.

const SIDE_TABS: = ["AI 분석", "캐릭터", "기록"]
const TAB_ANALYSIS: = 0
const TAB_DETAIL: = 1
const TAB_LOG: = 2
const PHASES: = {"prepare": "후보 준비", "seed": "전 후보 비교", "baseline": "전 후보 비교", "coverage": "전 후보 비교", "complete": "최종 선택", "cancelled": "탐색 중단", "search": "상대 응수 탐색", "deepening": "상대 응수 탐색", "rollout": "전투 시뮬레이션", "engine": "전투 시뮬레이션", "done": "최종 선택"}

var app: App
var size_n: int = 3
var arena_id: String = "classic"
var ruleset: String = "elimination"
var rules: RulesetSelector
var user: Array = []
var ai: Array = []
var turn: String = "user"
var log_rows: Array = []
var decision: Dictionary = {}
var director: DraftDirector
# Evaluation-only director for the balance bar: rebuilt only when team size, arena or
# ruleset change (building one costs 40-60 ms), and the value is cached per pick state.
var _eval_dir: DraftDirector = null
var _eval_dir_key: String = ""
var _eval_key: String = ""
var _eval_value: float = 0.0
var search_done: bool = false
var search_frame_ms: float = 0.0
var search_peak_ms: float = 0.0
var search_controls: VBoxContainer
var search_status: Label
var search_bar: ProgressBar
var search_button: Button
var think_started: float = 0.0
var clock: float = 0.0
var role_filter: String = ""
var query: String = ""
var auto_user: bool = false
var auto_at: float = 0.0

var size_btns: Array = []
var size_seg: HBoxContainer
var arena_opt: OptionButton
var seed_edit: LineEdit
var seed_btn: Button
var rec_l: Label
var lock_badge: PanelContainer
var lock_l: Label
var status_l: Label
var turn_panel: PanelContainer
var turn_l: Label
var turn_sub: Label
var turn_count: Label
var order_row: HBoxContainer
var slot_boxes: Array = []
var team_cards: Array = []
var team_heads: Array = []
var team_comp: Array = []
var eval_l: Label
var eval_value: Label
var eval_bar: TugBar
var roster_cards: Array = []
var roster_grid: GridContainer
var roster_scroll: ScrollContainer
var roster_hint: Label
var roster_note: PanelContainer
var roster_note_l: Label
var roster_empty: Control
var role_seg: HBoxContainer
var search_edit: LineEdit
var side_tabs: TabBar
var side_pages: Array = []
var analysis: VBoxContainer
var log_box: VBoxContainer
var start_btn: Button
var detail: CharDetail
var rng: = RandomNumberGenerator.new()
var _turn_style: String = ""


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	rng.randomize()
	DraftDirector._calibration()
	var v: = UITheme.vbox(UITheme.SP4)
	var mm: = UITheme.page_margin(v)
	mm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mm)

	# ---- page header
	status_l = UITheme.label("", "CaptionLabel")
	status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var reset_btn: = UITheme.button("초기화", "GhostButton", _reset, "지금까지의 픽을 모두 지우고 처음부터 다시 뽑습니다.")
	start_btn = UITheme.button("전투 시작  ▶", "PrimaryButton", _start)
	start_btn.custom_minimum_size.x = 150
	v.add_child(UITheme.page_header("AI DRAFT", "AI 대전", "AI와 한 명씩 번갈아 뽑습니다. 첫 픽 이후에는 규칙·규모·전장·시드가 고정됩니다.", [status_l, reset_btn, start_btn]))

	# ---- settings card
	var cfgv: = UITheme.vbox(UITheme.SP3)
	v.add_child(UITheme.panel("CardPanel", cfgv))
	var row1: = UITheme.hbox(UITheme.SP4)
	rules = RulesetSelector.new()
	rules.changed.connect(_set_ruleset)
	row1.add_child(rules)
	row1.add_child(UITheme.spacer())
	rec_l = UITheme.label("", "CaptionLabel")
	rec_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rec_l.tooltip_text = "AI 대전 결과로만 기록됩니다."
	rec_l.mouse_filter = Control.MOUSE_FILTER_PASS
	row1.add_child(rec_l)
	cfgv.add_child(row1)
	cfgv.add_child(UITheme.sep_line())
	var cfg: = UITheme.hbox(UITheme.SP4)
	cfgv.add_child(cfg)
	var size_opts: Array = []
	for n in range(1, 6):
		size_opts.append([n, "%dv%d" % [n, n], "팀당 %d명" % n])
	size_seg = UITheme.segmented(size_opts, size_n, func(id): _set_team_size(int(id)), 50)
	var sb: Dictionary = size_seg.get_meta("buttons")
	for n in range(1, 6):
		size_btns.append(sb[n])
	cfg.add_child(SetupScreen.field("전투 규모", size_seg))
	cfg.add_child(UITheme.sep_line(true))
	arena_opt = OptionButton.new()
	arena_opt.focus_mode = Control.FOCUS_NONE
	arena_opt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	arena_opt.custom_minimum_size = Vector2(210, 36)
	arena_opt.item_selected.connect(func(i):
		arena_id = str(arena_opt.get_item_metadata(i))
		_arena_tooltip())
	_set_ruleset("elimination")
	cfg.add_child(SetupScreen.field("전장", arena_opt))
	cfg.add_child(UITheme.sep_line(true))
	var sd: = UITheme.hbox(UITheme.SP2)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(118, 36)
	seed_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seed_edit.text = str(rng.randi_range(1, 99999999))
	sd.add_child(seed_edit)
	seed_btn = UITheme.button("무작위", "", _roll_seed)
	seed_btn.custom_minimum_size = Vector2(0, 36)
	seed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sd.add_child(seed_btn)
	cfg.add_child(SetupScreen.field("시드", sd))
	cfg.add_child(UITheme.spacer())
	var lk: = UITheme.hbox(UITheme.SP2)
	lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock_badge = UITheme.badge("고정됨", UITheme.WARN, "soft")
	lock_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lk.add_child(lock_badge)
	lock_l = UITheme.label("", "FaintLabel")
	lock_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lk.add_child(lock_l)
	cfg.add_child(lk)

	# ---- main area
	var main: = UITheme.hbox(UITheme.SP4)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(main)

	var left: = UITheme.vbox(UITheme.SP3)
	left.add_child(_build_turn_panel())
	left.add_child(_team_card(0))
	left.add_child(_team_card(1))
	var left_scroll: = UITheme.scroll(left)
	left_scroll.custom_minimum_size = Vector2(300, 0)
	left_scroll.size_flags_horizontal = Control.SIZE_FILL
	main.add_child(left_scroll)

	var center: = UITheme.vbox(UITheme.SP3)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_seg = UITheme.segmented(SetupScreen.ROLE_FILTERS, "", func(id): _set_role(str(id)))
	search_edit = SetupScreen.search_box(func(t: String) -> void:
		query = t.strip_edges().to_lower()
		_refresh_roster())
	search_edit.custom_minimum_size.x = 160
	var trail: = UITheme.hbox(UITheme.SP2)
	trail.add_child(role_seg)
	trail.add_child(search_edit)
	var rh: = UITheme.section_header("캐릭터", "", trail)
	roster_hint = rh.get_meta("hint")
	center.add_child(rh)
	roster_note_l = UITheme.label("", "BoldLabel", 14)
	roster_note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_note_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_note = UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_M, 1, 12, 8), roster_note_l)
	roster_note.visible = false
	center.add_child(roster_note)
	roster_grid = SetupScreen.roster_grid_new()
	for c in DB.characters:
		var rc: = RosterCard.new(c)
		rc.custom_minimum_size.x = SetupScreen.ROSTER_MIN_W
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = c.id
		rc.pressed.connect( func(): _user_pick(cid))
		rc.hovered_def.connect( func(d): detail.show_def(d))
		roster_cards.append(rc)
		roster_grid.add_child(rc)
	roster_empty = SetupScreen.roster_empty_state(_clear_filters)
	var rbox: = UITheme.vbox(0)
	rbox.add_child(roster_grid)
	rbox.add_child(roster_empty)
	roster_scroll = UITheme.scroll(rbox)
	roster_scroll.resized.connect(func(): SetupScreen.fit_roster_columns(roster_scroll, roster_grid))
	center.add_child(roster_scroll)
	main.add_child(center)

	var right: = UITheme.vbox(UITheme.SP2)
	right.custom_minimum_size = Vector2(372, 0)
	right.add_child(_build_eval())
	right.add_child(UITheme.spacer(0, 2))
	side_tabs = TabBar.new()
	side_tabs.focus_mode = Control.FOCUS_NONE
	side_tabs.clip_tabs = false
	for t in SIDE_TABS:
		side_tabs.add_tab(t)
	side_tabs.tab_changed.connect(_show_page)
	right.add_child(side_tabs)
	var pages: = UITheme.vbox(0)
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	analysis = UITheme.vbox(UITheme.SP3)
	var an_scroll: = UITheme.scroll(UITheme.margin(analysis, 2, 2, 10, 4))
	pages.add_child(an_scroll)
	detail = CharDetail.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(detail)
	log_box = UITheme.vbox(6)
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lg_scroll: = UITheme.scroll(UITheme.margin(log_box, 0, 0, 10, 4))
	pages.add_child(lg_scroll)
	side_pages = [an_scroll, detail, lg_scroll]
	var pp: = UITheme.panel("CardPanel", pages)
	pp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(pp)
	main.add_child(right)

	detail.show_def(DB.characters[0])
	_select_tab(TAB_DETAIL)
	_set_team_size(3)


func _build_turn_panel() -> PanelContainer:
	turn_panel = UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2.lerp(UITheme.BLUE, 0.14), UITheme.BLUE, UITheme.R_L, 1, 14, 12))
	var tpv: = UITheme.vbox(6)
	var top: = UITheme.hbox(UITheme.SP2)
	turn_sub = UITheme.ellipsize(UITheme.label("내 차례", "EyebrowLabel"))
	turn_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(turn_sub)
	turn_count = UITheme.label("", "CaptionLabel")
	top.add_child(turn_count)
	tpv.add_child(top)
	var title_row: = UITheme.hbox(UITheme.SP2)
	turn_l = UITheme.label("", "HeadLabel", 19)
	turn_l.add_theme_font_override("font", DB.font_black)
	turn_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(turn_l)
	# Shown with search_controls (AI turn / paused): stop or restart the search.
	search_button = UITheme.button("탐색 중단", "ChipButton", _search_button_pressed)
	search_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	search_button.visible = false
	title_row.add_child(search_button)
	tpv.add_child(title_row)
	order_row = UITheme.hbox(4)
	order_row.custom_minimum_size = Vector2(0, 6)
	tpv.add_child(order_row)
	search_controls = UITheme.vbox(6)
	search_bar = UITheme.progress(0.0, 100.0, UITheme.RED, 6)
	search_controls.add_child(search_bar)
	search_status = UITheme.wrap_label("", "CaptionLabel", 13)
	search_controls.add_child(search_status)
	search_controls.visible = false
	tpv.add_child(search_controls)
	turn_panel.add_child(tpv)
	return turn_panel


func _team_card(t: int) -> PanelContainer:
	var tv: = UITheme.vbox(6)
	var head: = SetupScreen.team_head_row(t, "내 팀" if t == 0 else "AI 팀")
	head.custom_minimum_size = Vector2(0, 26)
	team_heads.append(head)
	tv.add_child(head)
	var box: = UITheme.vbox(5)
	slot_boxes.append(box)
	tv.add_child(box)
	var comp: = SetupScreen.comp_row()
	team_comp.append(comp)
	tv.add_child(comp)
	var card: = UITheme.styled_panel(SetupScreen.team_card_style(t, false), tv)
	team_cards.append(card)
	return card


func _build_eval() -> PanelContainer:
	var ev: = UITheme.vbox(6)
	var top: = UITheme.hbox(UITheme.SP2)
	var cap: = UITheme.label("AI의 조합 평가", "EyebrowLabel")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cap)
	eval_value = UITheme.label("", "BoldLabel", 14)
	top.add_child(eval_value)
	ev.add_child(top)
	var bar: = UITheme.hbox(UITheme.SP2)
	var me: = UITheme.label("나", "BoldLabel", 13, UITheme.BLUE.lightened(0.2))
	bar.add_child(me)
	eval_bar = TugBar.new()
	eval_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(eval_bar)
	bar.add_child(UITheme.label("AI", "BoldLabel", 13, UITheme.RED.lightened(0.2)))
	ev.add_child(bar)
	eval_l = UITheme.wrap_label("", "CaptionLabel", 13)
	ev.add_child(eval_l)
	var p: = UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_L, 1, 12, 10), ev)
	p.tooltip_text = UITheme.tip("AI가 1:1 상성·팀 기여·연계·전장 적합성을 합쳐 계산한 추정치입니다. 표시가 오른쪽(AI)으로 갈수록 AI가 유리하다고 봅니다.")
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func on_show(args: Dictionary) -> void :
	if args.has("ruleset") and user.is_empty() and ai.is_empty():
		_set_ruleset(str(args.ruleset))
	_refresh()


func _set_ruleset(key: String) -> void:
	if not user.is_empty() or not ai.is_empty():
		rules.set_ruleset(ruleset)
		return
	ruleset = "control" if key == "control" else "elimination"
	rules.set_ruleset(ruleset)
	arena_opt.clear()
	var available: Array = DB.arenas_for(ruleset)
	for a in available:
		arena_opt.add_item("%s  %s" % [str(a.data.get("icon", "")), a.name])
		arena_opt.set_item_metadata(arena_opt.item_count - 1, a.id)
	if not available.is_empty():
		arena_id = available[0].id
		arena_opt.select(0)
	_arena_tooltip()


func _arena_tooltip() -> void:
	if arena_opt.disabled:
		arena_opt.tooltip_text = UITheme.tip("첫 픽 이후에는 전장을 바꿀 수 없어요. 초기화하면 다시 고를 수 있어요.")
		return
	var a: = DB.arena(arena_id)
	arena_opt.tooltip_text = UITheme.tip("%s\n%s" % [a.name, str(a.data.get("description", ""))])


func _set_team_size(n: int) -> void :
	if not user.is_empty() or not ai.is_empty():
		if app:
			app.toast("규모는 초기화한 뒤 바꿀 수 있어요.", UITheme.WARN)
		UITheme.segmented_select(size_seg, size_n)
		return
	size_n = clampi(n, 1, 5)
	UITheme.segmented_select(size_seg, size_n)
	_refresh()


func _set_role(r: String) -> void:
	role_filter = r
	UITheme.segmented_select(role_seg, r)
	_refresh_roster()


func _clear_filters() -> void:
	query = ""
	search_edit.text = ""
	_set_role("")


func _roll_seed() -> void:
	if not user.is_empty() or not ai.is_empty():
		return
	seed_edit.text = str(rng.randi_range(1, 99999999))


func _select_tab(i: int) -> void:
	if side_tabs.current_tab != i:
		side_tabs.current_tab = i
	_show_page(i)


func _show_page(i: int) -> void:
	for k in side_pages.size():
		(side_pages[k] as Control).visible = k == i


func _reset() -> void :
	_cancel_search()
	user = []
	ai = []
	turn = "user"
	log_rows = []
	decision = {}
	if side_tabs and side_tabs.current_tab == TAB_ANALYSIS:
		_select_tab(TAB_DETAIL)
	_refresh()


func _user_pick(id: String) -> void :
	if turn != "user" or user.has(id) or ai.has(id) or user.size() >= size_n:
		return
	user.append(id)
	var pc: Dictionary = Settings.records.get("pick_counts", {})
	pc[id] = int(pc.get(id, 0)) + 1
	Settings.records["pick_counts"] = pc
	Settings.save_all()
	log_rows.append({"side": "user", "id": id, "note": "내 선택"})
	Sfx.play("pick", 0.4)
	_advance()


func _advance() -> void :
	if user.size() >= size_n and ai.size() >= size_n:
		turn = "done"
	elif ai.size() < user.size() or user.size() >= size_n:
		turn = "ai"
		_ai_think()
	else:
		turn = "user"
	_refresh()


func _ai_think() -> void :
	var opts: = {"team_size": size_n, "arena_id": arena_id, "ruleset": ruleset, "seed": int(seed_edit.text) if seed_edit.text.is_valid_int() else 1,
		"user_history": Settings.records.get("pick_counts", {}), "budget": 45000}
	_cancel_search()
	director = DraftDirector.new(opts)
	director.begin(user.duplicate(), ai.duplicate())
	search_done = false
	search_peak_ms = 0.0
	think_started = clock
	turn = "ai"
	_update_search_progress()


func _process(delta: float) -> void :
	clock += delta
	if not visible:
		return
	if auto_user and turn == "user" and clock > auto_at:
		auto_at = clock + 0.4
		var free: Array = []
		for c in DB.characters:
			if not user.has(c.id) and not ai.has(c.id):
				free.append(c.id)
		if not free.is_empty():
			_user_pick(free[rng.randi_range(0, free.size() - 1)])
	if turn == "ai" and director != null:
		if not search_done:
			var before: int = Time.get_ticks_usec()
			search_done = director.advance_until(before + 8000)
			search_frame_ms = (Time.get_ticks_usec() - before) / 1000.0
			search_peak_ms = maxf(search_peak_ms, search_frame_ms)
			_update_search_progress()
		if search_done and clock - think_started > 0.45:
			var dec: Dictionary = director.result()
			director = null
			if dec.is_empty():
				turn = "ai_paused"
				_refresh()
				return
			decision = dec
			ai.append(dec.id)
			log_rows.append({"side": "ai", "id": dec.id, "note": (dec.reasons as Array)[0] if not (dec.reasons as Array).is_empty() else "카운터 선택"})
			Sfx.play("ai_pick", 0.45)
			_select_tab(TAB_ANALYSIS)
			_advance()


func _update_search_progress() -> void:
	if director == null or search_bar == null:
		return
	var progress: Dictionary = director.progress()
	search_bar.value = clampf(float(progress.get("fraction", 0.0)), 0.0, 1.0) * 100.0
	var phase: String = str(progress.get("phase", "search"))
	turn_sub.text = "AI 차례 · " + str(PHASES.get(phase, "상대 응수 탐색"))
	var secs: = clock - think_started
	if phase == "rollout":
		search_status.text = "전투 검증 %s / %s 단계 · %.1f초" % [_num(int(progress.get("rollout_ticks", 0))), _num(int(progress.get("rollout_tick_budget", 0))), secs]
	else:
		search_status.text = "후보 %d/%d · 평가 %s회 · 깊이 %d · %.1f초" % [int(progress.get("covered_candidates", 0)), int(progress.get("candidates", 0)), _num(int(progress.get("evals", 0))), int(progress.get("completed_depth", 0)), secs]

func _cancel_search() -> void:
	if director:
		director.cancel()
	director = null
	search_done = false


func _search_button_pressed() -> void:
	if turn == "ai":
		_cancel_search()
		turn = "ai_paused"
	elif turn == "ai_paused":
		_ai_think()
	_refresh()


func on_hide() -> void:
	if turn == "ai":
		_cancel_search()
		turn = "ai_paused"
		_refresh()


func _exit_tree() -> void:
	_cancel_search()


func _refresh() -> void :
	if slot_boxes.is_empty():
		return
	var rec: Dictionary = Settings.records
	rec_l.text = "AI 대전 전적 %d승 %d패 · 연승 %d · 최고 %d" % [int(rec.draft_wins), int(rec.draft_losses), int(rec.streak), int(rec.best_streak)]
	var locked: bool = not user.is_empty() or not ai.is_empty()
	arena_opt.disabled = locked
	_arena_tooltip()
	rules.set_locked(locked)
	UITheme.segmented_lock(size_seg, locked)
	for b in size_btns:
		(b as Button).tooltip_text = "첫 픽 이후에는 규모를 바꿀 수 없어요." if locked else ""
	seed_edit.editable = not locked
	seed_edit.tooltip_text = UITheme.tip("첫 픽 이후에는 시드를 바꿀 수 없어요." if locked else "같은 시드와 같은 조합이면 전투가 똑같이 재현됩니다.")
	seed_btn.disabled = locked
	seed_btn.tooltip_text = "첫 픽 이후에는 시드를 바꿀 수 없어요." if locked else "새 시드를 무작위로 정합니다."
	lock_badge.visible = locked
	lock_l.text = "초기화하면 다시 바꿀 수 있어요" if locked else "첫 픽을 고르면 설정이 고정돼요"

	var tc: = UITheme.BLUE
	var total: = size_n * 2
	var picked: = user.size() + ai.size()
	match turn:
		"user":
			turn_sub.text = "내 차례"
			turn_l.text = "%d번째 캐릭터를 골라 주세요" % (user.size() + 1)
		"ai":
			if not turn_sub.text.begins_with("AI 차례"):
				turn_sub.text = "AI 차례"
			turn_l.text = "AI가 고르는 중…"
			tc = UITheme.RED
		"ai_paused":
			turn_sub.text = "일시 정지"
			turn_l.text = "AI 탐색을 멈췄어요"
			search_status.text = "고른 캐릭터는 그대로 유지돼요. 다시 시작하면 처음부터 탐색합니다."
			tc = UITheme.GOLD
		"done":
			turn_sub.text = "드래프트 완료"
			turn_l.text = "전투를 시작할 수 있어요"
			tc = UITheme.GOOD
	turn_count.text = "픽 %d / %d" % [mini(picked, total), total]
	search_controls.visible = turn in ["ai", "ai_paused"]
	search_button.visible = search_controls.visible
	# The search progress bar takes the place of the pick-order pips while the AI works.
	order_row.visible = not search_controls.visible
	search_button.text = "다시 시작" if turn == "ai_paused" else "탐색 중단"
	search_button.tooltip_text = "AI 탐색을 처음부터 다시 시작합니다." if turn == "ai_paused" else "AI 탐색을 멈춥니다. 고른 캐릭터는 그대로 유지돼요."
	if _turn_style != turn:
		_turn_style = turn
		turn_panel.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.PANEL2.lerp(tc, 0.14), tc, UITheme.R_L, 1, 14, 12))
		turn_sub.add_theme_color_override("font_color", tc.lightened(0.15))
		search_bar.add_theme_stylebox_override("fill", UITheme.sbc(tc, UITheme.CLEAR, UITheme.R_XS, 0, 0, 0))
	_refresh_order()

	for t in 2:
		var arr: Array = user if t == 0 else ai
		var mine: bool = (turn == "user" and t == 0) or (turn in ["ai", "ai_paused"] and t == 1)
		(team_cards[t] as PanelContainer).add_theme_stylebox_override("panel", SetupScreen.team_card_style(t, mine))
		var pill: = ""
		if mine:
			pill = "내 차례" if t == 0 else ("일시 정지" if turn == "ai_paused" else "고르는 중")
		SetupScreen.set_team_head(team_heads[t], arr.size(), size_n, pill)
		var box: VBoxContainer = slot_boxes[t]
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var slot_h: = 42 if size_n <= 3 else 40
		for i in size_n:
			box.add_child(_slot(t, i, arr, mine and i == arr.size(), slot_h))
		SetupScreen.set_comp_row(team_comp[t], arr, "아직 고른 캐릭터가 없어요.")

	var is_done: = turn == "done"
	start_btn.disabled = not is_done
	var left_n: int = maxi(0, total - picked)
	if is_done:
		status_l.text = "✓ 준비 완료"
		status_l.add_theme_color_override("font_color", UITheme.GOOD)
		start_btn.tooltip_text = "완성된 두 조합으로 전투를 시작합니다."
	else:
		status_l.text = "남은 픽 %d개" % left_n
		status_l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		start_btn.tooltip_text = UITheme.tip("드래프트를 마치면 시작할 수 있어요. 남은 픽 %d개" % left_n)

	if not user.is_empty() and not ai.is_empty():
		var ev: = _evaluation()
		var verdict: = "AI 우세" if ev > 0.05 else ("내가 우세" if ev < -0.05 else "팽팽")
		eval_value.text = "%s · %.2f" % [verdict, absf(ev)]
		eval_value.add_theme_color_override("font_color", UITheme.RED.lightened(0.2) if ev > 0.05 else (UITheme.BLUE.lightened(0.2) if ev < -0.05 else UITheme.TEXT_DIM))
		eval_l.text = "상성·팀 기여·연계·전장 적합성을 합친 AI의 추정이에요."
		eval_bar.set_value(ev, true)
	else:
		eval_value.text = "평가 전"
		eval_value.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		eval_l.text = "첫 픽을 고르면 AI가 바로 카운터를 계산해요. 전장과 시드는 첫 픽 전에 정하세요."
		eval_bar.set_value(0.0, false)
	side_tabs.set_tab_title(TAB_LOG, "기록 %d" % log_rows.size() if not log_rows.is_empty() else "기록")
	_refresh_analysis()
	_refresh_log()
	_refresh_roster()


## AI balance estimate of the current picks. The director is reused across refreshes and
## the value cached per (size, arena, ruleset, picks); identical result to a fresh director.
func _evaluation() -> float:
	var dkey: String = "%d|%s|%s" % [size_n, arena_id, ruleset]
	if _eval_dir == null or _eval_dir_key != dkey:
		_eval_dir = DraftDirector.new({"team_size": size_n, "arena_id": arena_id, "ruleset": ruleset})
		_eval_dir_key = dkey
		_eval_key = ""
	var ekey: String = "%s|%s/%s" % [dkey, ",".join(PackedStringArray(user)), ",".join(PackedStringArray(ai))]
	if ekey != _eval_key:
		_eval_value = _eval_dir.evaluate_state(user, ai)
		_eval_key = ekey
	return _eval_value


## Pick-order pips (나 → AI → 나 ...): done = solid team colour, current = outlined, pending = faint.
func _refresh_order() -> void:
	for c in order_row.get_children():
		order_row.remove_child(c)
		c.queue_free()
	var current: = -1
	if turn in ["user", "ai", "ai_paused"]:
		current = user.size() * 2 if turn == "user" else ai.size() * 2 + 1
	for k in size_n * 2:
		var side: = k % 2
		var n: = int(k / 2.0)
		var done: bool = n < (user.size() if side == 0 else ai.size())
		var col: = UITheme.team_color(side)
		var st: StyleBoxFlat
		if done:
			st = UITheme.sbc(col, UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0)
		elif k == current:
			st = UITheme.sbc(Color(col, 0.35), col, UITheme.R_PILL, 1, 0, 0)
		else:
			st = UITheme.sbc(Color(1, 1, 1, 0.08), UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0)
		var pip: = Panel.new()
		pip.custom_minimum_size = Vector2(0, 6)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", st)
		order_row.add_child(pip)


func _slot(t: int, i: int, arr: Array, next: bool, h: int) -> Control:
	var d: Defs.CharDef = null
	if i < arr.size():
		d = DB.char_def(arr[i])
	var styles: Dictionary = SetupScreen.slot_styles(t, "filled" if d != null else ("next" if next else "empty"))
	# Fixed-height Panel (content anchored inside) so every slot is exactly h tall, like setup's slots.
	var p: = Panel.new()
	p.add_theme_stylebox_override("panel", styles.normal)
	p.custom_minimum_size = Vector2(0, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty_text: = "빈 자리"
	if next:
		empty_text = "목록에서 한 명을 골라 주세요" if t == 0 else ("AI가 고르는 중…" if turn == "ai" else "AI 탐색이 멈춰 있어요")
	var row: = SetupScreen.slot_row(d, t, i, h, empty_text, next)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	p.add_child(row)
	if d != null:
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.mouse_entered.connect(func(): detail.show_def(d))
		p.tooltip_text = UITheme.tip(d.summary)
	return p


func _sub(text: String, hint: String = "") -> Control:
	var h: = UITheme.hbox(UITheme.SP2)
	var l: = UITheme.label(text, "EyebrowLabel")
	h.add_child(l)
	if hint != "":
		var hl: = UITheme.ellipsize(UITheme.label(hint, "FaintLabel", 12))
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(hl)
	return UITheme.margin(h, 0, 6, 0, 0)


func _refresh_analysis() -> void :
	for c in analysis.get_children():
		analysis.remove_child(c)
		c.queue_free()
	if decision.is_empty():
		var e: = UITheme.empty_state("◈", "아직 AI가 고르지 않았어요", "첫 픽을 고르면 AI가 %d명 전체 후보에 같은 탐색 기회를 주고, 내 다음 선택과 이후 조합 전개까지 비교해요." % DB.characters.size())
		analysis.add_child(UITheme.margin(e, 0, 24, 0, 8))
		analysis.add_child(_sub("AI가 고려하는 것"))
		var f: = HFlowContainer.new()
		f.add_theme_constant_override("h_separation", 6)
		f.add_theme_constant_override("v_separation", 6)
		for k in ["상성", "역할", "시너지", "선택 이력", "승리 규칙", "전장 적합성"]:
			f.add_child(UITheme.badge(k, UITheme.ACCENT))
		analysis.add_child(f)
		return
	var d: = DB.char_def(decision.id)
	var h: = UITheme.hbox(UITheme.SP3)
	var disc: = GlyphDisc.new(d, 52, 1)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var hv: = UITheme.vbox(3)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UITheme.label("AI의 %d번째 선택" % ai.size(), "EyebrowLabel", 0, UITheme.RED.lightened(0.25)))
	hv.add_child(UITheme.ellipsize(UITheme.label(d.name, "HeadLabel")))
	var bh: = UITheme.hbox(6)
	bh.add_child(UITheme.badge("강건 점수 %+.2f" % float(decision.score), UITheme.GOLD, "soft", "상대의 가장 강한 응수와 예상 응수를 함께 반영한 탐색 점수입니다. 높을수록 AI가 이 픽을 유리하다고 봅니다."))
	bh.add_child(_basis_badge(str(decision.get("score_basis", "search"))))
	hv.add_child(bh)
	h.add_child(hv)
	analysis.add_child(h)

	analysis.add_child(_sub("선택 근거"))
	for r in decision.reasons:
		var rr: = UITheme.hbox(UITheme.SP2)
		var dot: = UITheme.label("•", "BoldLabel", 14, Color(UITheme.RED, 0.85))
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		rr.add_child(dot)
		rr.add_child(UITheme.wrap_label(str(r), "BodyLabel", 14))
		analysis.add_child(rr)

	var fc: Array = decision.get("forecast", [])
	if not fc.is_empty():
		var has_policy: = false
		for s in fc:
			has_policy = has_policy or bool(s.get("policy", false))
		analysis.add_child(_sub("예상 진행", "AI가 예상한 이후 픽 순서"))
		var flow: = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 6)
		for k in fc.size():
			var s: Dictionary = fc[k]
			if k > 0:
				var arrow: = UITheme.label("→", "FaintLabel", 12)
				arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				flow.add_child(arrow)
			var is_ai: = str(s.get("side", "")) == "ai"
			var policy: = bool(s.get("policy", false))
			var step: = UITheme.hbox(4)
			step.add_child(UITheme.badge("AI" if is_ai else "나", UITheme.team_color(1 if is_ai else 0), "outline" if policy else "strong"))
			var nm: = UITheme.label(DB.char_def(str(s.id)).name, "CaptionLabel" if policy else "BodyLabel", 13)
			nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			step.add_child(nm)
			flow.add_child(step)
		analysis.add_child(flow)
		if has_policy:
			analysis.add_child(UITheme.hint_label("테두리만 있는 칩은 탐색 깊이 이후를 합법 선택 정책으로 채운 예상이에요."))

	var alts: Array = decision.get("alternatives", [])
	if not alts.is_empty():
		analysis.add_child(_sub("차선 후보"))
		for a in alts.slice(0, 3):
			var ar: = UITheme.hbox(UITheme.SP2)
			var ad: = DB.char_def(str(a.id))
			var ag: = GlyphDisc.new(ad, 28, -1)
			ag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.add_child(ag)
			var an: = UITheme.ellipsize(UITheme.label(ad.name, "BoldLabel", 14))
			an.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			an.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.add_child(an)
			var sc: = UITheme.label("%+.2f" % float(a.score), "BlackLabel", 14, UITheme.TEXT_DIM)
			sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.add_child(sc)
			var bb: = _basis_badge(str(a.get("score_basis", "search")))
			bb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ar.add_child(bb)
			analysis.add_child(ar)

	var st: Dictionary = decision.get("search", {})
	analysis.add_child(_sub("탐색 통계"))
	var grid: = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for cell in [["평가", "%s회" % _num(int(st.get("evals", 0))), "후보 조합을 평가한 횟수입니다."],
			["완료 깊이", "%d수" % int(st.get("completed_depth", st.get("depth", 0))), "모든 후보를 같은 깊이까지 비교한 수입니다."],
			["후보", "%d명" % int(st.get("candidates", 0)), "이번 픽에서 비교한 후보 수입니다."]]:
		var tile: = UITheme.stat_tile(cell[0], cell[1], UITheme.TEXT, cell[2])
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
	analysis.add_child(grid)
	var model: Dictionary = st.get("opponent_model", {})
	if not model.is_empty():
		analysis.add_child(UITheme.wrap_label("상대 응수 · 강한 카운터 %.0f%% + 예상 선택 %.0f%% (선택 이력은 보조 근거)" % [float(model.get("worst_weight", 0)) * 100, float(model.get("expected_weight", 0)) * 100], "CaptionLabel", 13))
	var rollout: Dictionary = st.get("rollout", {})
	if int(rollout.get("games", 0)) > 0:
		var sides: String = "같은 진영에서" if int(rollout.get("sides_per_finalist", 2)) == 1 else "진영을 바꿔"
		analysis.add_child(UITheme.wrap_label("전투 검증 · %s %d회 · 회당 최대 %.0f초 · 최종 보조 가중치 %.0f%%" % [sides, int(rollout.games), float(rollout.get("horizon_ticks", 0)) * BattleSim.DT, float(rollout.get("weight", 0)) * 100], "CaptionLabel", 13))


func _basis_badge(basis: String) -> PanelContainer:
	if basis in ["search_and_engine", "rollout"]:
		return UITheme.badge("전투 검증", UITheme.GOOD, "soft", "탐색 점수에 실제 전투 엔진의 짧은 검증 결과를 더한 점수입니다.")
	return UITheme.badge("탐색", UITheme.ACCENT, "soft", "조합 평가 탐색만으로 계산한 점수입니다.")


func _refresh_log() -> void :
	for c in log_box.get_children():
		log_box.remove_child(c)
		c.queue_free()
	if log_rows.is_empty():
		log_box.add_child(UITheme.margin(UITheme.empty_state("☰", "아직 기록이 없어요", "먼저 한 명을 고르면 AI가 번갈아 응수합니다."), 0, 32, 0, 0))
		return
	for i in log_rows.size():
		var r: Dictionary = log_rows[i]
		var side: = int(r.side == "ai")
		var tc: = UITheme.team_color(side)
		var d: = DB.char_def(r.id)
		var h: = UITheme.hbox(10)
		var bar: = Panel.new()
		bar.custom_minimum_size = Vector2(3, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("panel", UITheme.sbc(tc, UITheme.CLEAR, 2, 0, 0, 0))
		h.add_child(bar)
		var num: = UITheme.label("%d" % (i + 1), "CaptionLabel", 12)
		num.custom_minimum_size = Vector2(14, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(num)
		var disc: = GlyphDisc.new(d, 30, side)
		disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(disc)
		var nv: = UITheme.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.custom_minimum_size = Vector2(10, 0)
		nv.alignment = BoxContainer.ALIGNMENT_CENTER
		var nl: = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel", 14))
		nl.custom_minimum_size = Vector2(10, 0)
		nv.add_child(nl)
		var note_text: = str(r.note)
		if side == 0:
			var beh: = str(d.behavior.get("label", ""))
			note_text = DB.role_label(d.role) + (" · " + beh if beh != "" else "")
		var note: = UITheme.label(note_text, "CaptionLabel", 12)
		note.custom_minimum_size = Vector2(10, 0)
		UITheme.ellipsize(note, true)
		nv.add_child(note)
		h.add_child(nv)
		var sb: = UITheme.badge("AI" if side == 1 else "나", tc, "strong")
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sb)
		var row: = UITheme.styled_panel(UITheme.sbc(Color(1, 1, 1, 0.025), UITheme.LINE, UITheme.R_M, 1, 8, 6), h)
		log_box.add_child(row)


func _refresh_roster() -> void :
	var shown_n: = 0
	for rc in roster_cards:
		var card: RosterCard = rc
		var shown: = SetupScreen.roster_matches(card.def, role_filter, query)
		card.visible = shown
		if shown:
			shown_n += 1
		if user.has(card.def.id):
			card.set_picked(0, "나")
		elif ai.has(card.def.id):
			card.set_picked(1, "AI")
		else:
			card.set_picked(-1)
		card.disabled = turn != "user" or user.has(card.def.id) or ai.has(card.def.id)
	roster_grid.visible = shown_n > 0
	roster_empty.visible = shown_n == 0
	var filtered: = role_filter != "" or query != ""
	var count_txt: = (" · %d명 표시" % shown_n) if filtered and shown_n > 0 else ""
	var note: = ""
	var note_col: = UITheme.TEXT_DIM
	match turn:
		"user":
			roster_hint.text = "눌러서 추가" + count_txt
			roster_hint.add_theme_color_override("font_color", UITheme.BLUE.lightened(0.2))
		"ai":
			roster_hint.text = "AI 차례" + count_txt
			note = "AI가 고르는 중… 선택이 끝나면 다시 고를 수 있어요."
			note_col = UITheme.RED
		"ai_paused":
			roster_hint.text = "일시 정지" + count_txt
			note = "AI 탐색이 멈춰 있어요. 왼쪽의 ‘다시 시작’을 누르면 AI가 다시 고릅니다."
			note_col = UITheme.GOLD
		"done":
			roster_hint.text = "드래프트 완료" + count_txt
			note = "드래프트가 끝났어요. 오른쪽 위의 ‘전투 시작’을 눌러 주세요."
			note_col = UITheme.GOOD
	if turn != "user":
		roster_hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	roster_note.visible = note != ""
	if note != "":
		roster_note_l.text = note
		roster_note_l.add_theme_color_override("font_color", note_col.lightened(0.25))
		roster_note.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.PANEL2.lerp(note_col, 0.1), Color(note_col, 0.45), UITheme.R_M, 1, 12, 8))


func _start() -> void :
	if turn != "done":
		return
	var seed_v: = int(seed_edit.text) if seed_edit.text.is_valid_int() else rng.randi_range(1, 99999999)
	var cfg: = {"blue": user.duplicate(), "red": ai.duplicate(), "arena_id": arena_id, "ruleset": ruleset, "seed": seed_v, "blue_ai": "tactician", "red_ai": "tactician", "mode": "draft"}
	Sfx.play("start", 0.5)
	app.start_battle(cfg, "draft")

	user = []
	ai = []
	turn = "user"
	log_rows = []
	decision = {}
	seed_edit.text = str(rng.randi_range(1, 99999999))
	_select_tab(TAB_DETAIL)


## 12345 -> "12,345".
static func _num(n: int) -> String:
	var s: = str(absi(n))
	var out: = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## "나 ◀──●──▶ AI" evaluation bar: the marker moves right when the AI's evaluation favours the AI.
## Redraws only when the value changes; styles come from the shared sbc() cache.
class TugBar:
	extends Control
	var value: float = 0.0
	var active: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float, on: bool) -> void:
		if is_equal_approx(v, value) and on == active:
			return
		value = v
		active = on
		queue_redraw()

	func _draw() -> void:
		var w: = size.x
		var cy: = size.y * 0.5
		var th: = 6.0
		draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.07), UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0), Rect2(0, cy - th * 0.5, w, th))
		var cx: = w * 0.5
		draw_rect(Rect2(cx - 1.0, cy - 6.0, 2.0, 12.0), UITheme.LINE2)
		if not active:
			return
		# Soft saturation: 0.35 -> half way, never touching the ends.
		var t: = value / (absf(value) + 0.35)
		var mx: = cx + t * (w * 0.5 - 8.0)
		var col: = UITheme.RED if value > 0.0 else UITheme.BLUE
		if absf(value) <= 0.05:
			col = UITheme.TEXT_DIM
		if absf(mx - cx) > 1.0:
			draw_style_box(UITheme.sbc(Color(col, 0.75), UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0), Rect2(minf(cx, mx), cy - th * 0.5, absf(mx - cx), th))
		draw_circle(Vector2(mx, cy), 7.0, UITheme.BG, true, -1.0, true)
		draw_circle(Vector2(mx, cy), 5.5, col, true, -1.0, true)
