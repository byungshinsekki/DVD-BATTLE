class_name SettingsScreen
extends Control

## Settings: section cards (연출 / 전투 / 화면 in the left column, 소리 / 기록 / 조작 / 정보 in the
## right) built from one aligned row helper (title + one-line description left, control right).
## Settings are written only from user interaction (never on show/navigation).

const PAGE_MAX_W: = 1400.0
const RESET_TEXT: = "전적 초기화"
const RESET_ARMED_TEXT: = "한 번 더 누르면 삭제돼요"
const RESET_ARM_SEC: = 3.0
## Battle controls, row-major for the two-pair key grid: [key cap, action].
const KEYS: = [["Space", "일시정지"], ["Esc", "나가기"], ["1~4", "배속 변경"], ["F11", "전체 화면"], ["V", "시야 전환"], ["클릭", "유닛 선택"],
	["C", "카메라 모드"], ["휠", "확대·축소"], ["Tab", "정보 패널"], ["우클릭 드래그", "화면 이동"]]

var app: App
## Row container of the section card being built (the _check/_choice/_slider builders append here).
var rows: VBoxContainer
var fs_check: CheckButton
var reset_btn: Button
var _reset_arm: int = 0
var rec_summary: Label
var _col: VBoxContainer
var _last_tick: int = 0
static var _row_style_cache: Array = []


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	var scroll: = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v: = UITheme.vbox(UITheme.SP5)
	scroll.add_child(UITheme.max_width(UITheme.page_margin(v), PAGE_MAX_W))
	var saved: = UITheme.badge("✓  자동 저장", UITheme.GOOD, "outline", "바꾼 설정은 바로 저장돼요. 따로 저장할 필요가 없어요.")
	v.add_child(UITheme.page_header("SETTINGS", "설정", "", [saved]))

	var cols: = UITheme.hbox(UITheme.SP4)
	v.add_child(cols)
	var left: = UITheme.vbox(UITheme.SP4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right: = UITheme.vbox(UITheme.SP4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_col = left
	_head("연출", "다음 전투부터 적용돼요")
	_choice("연출 품질", "vfx_quality", ["낮음", "보통", "높음"], [], "낮음은 입자·잔상 효과를 줄여 더 가볍게 실행돼요.")
	_check("화면 흔들림", "screen_shake", "강한 타격이나 폭발이 일어나면 화면이 흔들려요.")
	_check("타격 정지", "hit_stop", "처치·강타 순간 아주 짧게 멈춰 타격감을 살려요.")
	_head("전투", "다음 전투부터 적용돼요")
	_choice("기본 배속", "default_speed", ["0.5×", "1×", "2×", "4×"], [0.5, 1.0, 2.0, 4.0], "전투 중에는 1~4 키로 바꿀 수 있어요.")
	_check("피해 숫자 표시", "damage_numbers", "피해·회복 수치를 유닛 위에 띄워요.")
	_check("유닛 이름 표시", "show_names", "전장의 유닛마다 캐릭터 이름을 표시해요.")
	_check("시전 예고 범위 표시", "telegraphs", "스킬 시전 직전에 영향 범위를 미리 보여 줘요.")
	_check("AI 의도·위치 가설 표시", "ai_overlay", "전술가 AI가 추정한 적 위치와 의도를 겹쳐 보여 줘요.")
	_head("정보")
	_build_about()

	_col = right
	_head("화면")
	fs_check = CheckButton.new()
	fs_check.focus_mode = Control.FOCUS_NONE
	fs_check.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fs_check.button_pressed = bool(Settings.get_v("fullscreen", false))
	fs_check.toggled.connect( func(on):
		if app:
			app.set_fullscreen(on))
	_toggle_row(_row("전체 화면", "F11 키로도 전환할 수 있어요.", fs_check), fs_check)
	_head("소리", "바로 적용돼요")
	_slider("전체 음량", "master_volume", "게임의 모든 소리 크기예요.")
	_slider("효과음", "sfx_volume", "타격·스킬·버튼 효과음의 크기예요.")
	_head("기록")
	_build_reset_row()
	_head("조작", "전투 화면 단축키")
	_build_keys()


func on_show(_args: Dictionary) -> void :
	sync_fullscreen()
	_disarm_reset()
	_refresh_records()


func sync_fullscreen() -> void :
	if fs_check:
		fs_check.set_pressed_no_signal(bool(Settings.get_v("fullscreen", false)))


# ------------------------------------------------------------------ records reset

func _build_reset_row() -> void :
	var tv: = UITheme.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UITheme.label("전적 초기화", "BodyLabel"))
	rec_summary = UITheme.wrap_label("", "CaptionLabel", UITheme.FS_CAPTION)
	tv.add_child(rec_summary)
	tv.add_child(UITheme.hint_label("AI 대전 전적·연승·픽 기록과 관전 횟수가 모두 삭제되며 되돌릴 수 없어요."))
	reset_btn = UITheme.button(RESET_TEXT, "DangerButton", _on_reset)
	var f: Font = DB.font_regular
	var w: = maxf(f.get_string_size(RESET_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_BODY).x,
		f.get_string_size(RESET_ARMED_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FS_BODY).x)
	reset_btn.custom_minimum_size = Vector2(ceilf(w) + 32.0, 38)
	reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h: = UITheme.hbox(UITheme.SP4)
	h.add_child(tv)
	h.add_child(reset_btn)
	_add_row(h)


func _refresh_records() -> void :
	var r: Dictionary = Settings.records
	var wins: = int(r.get("draft_wins", 0))
	var losses: = int(r.get("draft_losses", 0))
	var battles: = int(r.get("battles", 0))
	var picks: Dictionary = r.get("pick_counts", {}) if r.get("pick_counts") is Dictionary else {}
	var empty: = wins + losses + battles + int(r.get("best_streak", 0)) + int(r.get("streak", 0)) == 0 and picks.is_empty()
	if rec_summary:
		if empty:
			rec_summary.text = "아직 저장된 기록이 없어요."
		else:
			rec_summary.text = "현재 기록: AI 대전 %d승 %d패 · 현재 연승 %d · 최고 연승 %d · 관전 %d회" % [wins, losses,
				int(r.get("streak", 0)), int(r.get("best_streak", 0)), battles]
			var pick_total: = 0
			for k in picks:
				pick_total += int(picks[k])
			if pick_total > 0:
				rec_summary.text += " · 픽 %d회" % pick_total
	if reset_btn:
		reset_btn.disabled = empty
		reset_btn.tooltip_text = UITheme.tip("초기화할 기록이 없어요.") if empty else ""
		reset_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW if empty else Control.CURSOR_POINTING_HAND


func _on_reset() -> void :
	if _reset_arm == 0:
		_reset_arm = Time.get_ticks_msec()
		var token: = _reset_arm
		reset_btn.text = RESET_ARMED_TEXT
		get_tree().create_timer(RESET_ARM_SEC).timeout.connect( func():
			if _reset_arm == token:
				_disarm_reset())
		return
	_disarm_reset()
	Settings.reset_records()
	_refresh_records()
	if app:
		app.toast("전적을 초기화했어요.", UITheme.WARN)


func _disarm_reset() -> void :
	_reset_arm = 0
	if reset_btn:
		reset_btn.text = RESET_TEXT


# ------------------------------------------------------------------ keys & about

func _build_keys() -> void :
	# Two key/action column pairs; key caps are right-aligned against their action text.
	var grid: = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UITheme.SP3)
	grid.add_theme_constant_override("v_separation", UITheme.SP2)
	for i in KEYS.size():
		var cap: = UITheme.kbd(str(KEYS[i][0]))
		cap.custom_minimum_size = Vector2(36, 26)
		cap.size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(cap)
		var act: = UITheme.label(str(KEYS[i][1]), "DimLabel")
		act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(act)
	_add_row(grid)


func _build_about() -> void :
	var tv: = UITheme.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UITheme.label("DVD BATTLE " + App.VERSION + " · Godot 4.7.2", "BoldLabel"))
	tv.add_child(UITheme.hint_label("전략 자동 전투 시뮬레이터 · 설정과 전적은 이 PC에만 저장돼요."))
	var notes: = UITheme.button("업데이트 노트  →", "GhostButton", func():
		if app:
			app.goto("home", {"section": "notes"}), "홈 화면의 이번 버전 업데이트 노트로 이동해요.")
	notes.custom_minimum_size = Vector2(0, 36)
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h: = UITheme.hbox(UITheme.SP4)
	h.add_child(tv)
	h.add_child(notes)
	_add_row(h)


# ------------------------------------------------------------------ builders

## Starts a new section card (CardPanel + section header) in the current column; rows go below it.
func _head(t: String, hint: String = "") -> void :
	var v: = UITheme.vbox(UITheme.SP2)
	v.add_child(UITheme.section_header(t, hint))
	rows = UITheme.vbox(0)
	v.add_child(rows)
	var card: = UITheme.panel("CardPanel", UITheme.margin(v, 6, 6, 6, 2))
	if _col:
		_col.add_child(card)


## Aligned setting row: title (+ one-line description) on the left, control on the right.
func _row(title: String, desc: String, control: Control) -> Control:
	var h: = UITheme.hbox(UITheme.SP4)
	var tv: = UITheme.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UITheme.label(title, "BodyLabel"))
	if desc != "":
		tv.add_child(UITheme.hint_label(desc))
	h.add_child(tv)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	return _add_row(h)


## Appends a row (with a hairline between rows) to the current section; returns the row wrapper.
func _add_row(content: Control) -> Control:
	if rows.get_child_count() > 0:
		rows.add_child(UITheme.sep_line())
	var m: = UITheme.margin(content, 2, 7, 2, 7)
	var row: = UITheme.styled_panel(_row_styles()[0], m)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_child(row)
	return row


## [idle, hover] row backgrounds (shared). The hover tint bleeds 8 px past the text column.
static func _row_styles() -> Array:
	if _row_style_cache.is_empty():
		var idle: = StyleBoxEmpty.new()
		var hot: = UITheme.sb(Color(1, 1, 1, 0.035), UITheme.CLEAR, UITheme.R_M, 0, 0, 0)
		hot.expand_margin_left = 8
		hot.expand_margin_right = 8
		_row_style_cache = [idle, hot]
	return _row_style_cache


## Makes the whole row toggle its switch (bigger hit area than the switch alone, with a hover tint).
## The switch loses its side padding so its right edge lines up with the other controls.
func _toggle_row(row: Control, cb: CheckButton) -> void :
	var flat: = UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 0, 2)
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		cb.add_theme_stylebox_override(st, flat)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", _row_styles()[1]))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", _row_styles()[0]))
	row.gui_input.connect( func(e: InputEvent):
		var mb: = e as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not cb.disabled:
			cb.button_pressed = not cb.button_pressed
			row.accept_event())


func _check(label: String, key: String, desc: String = "") -> void :
	var cb: = CheckButton.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cb.button_pressed = bool(Settings.get_v(key, true))
	cb.toggled.connect( func(on): Settings.set_v(key, on))
	_toggle_row(_row(label, desc, cb), cb)


func _choice(label: String, key: String, names: Array, values: Array = [], desc: String = "") -> void :
	var opts: Array = []
	for i in names.size():
		opts.append([values[i] if not values.is_empty() else i, names[i]])
	var cur = Settings.get_v(key)
	var sel: Variant = opts[0][0]
	if cur != null:
		for o in opts:
			if absf(float(cur) - float(o[0])) < 0.001:
				sel = o[0]
	var seg: = UITheme.segmented(opts, sel, func(id): Settings.set_v(key, id), 52)
	_row(label, desc, seg)


func _slider(label: String, key: String, desc: String = "") -> void :
	var h: = UITheme.hbox(UITheme.SP3)
	var s: = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_v(key, 0.8))
	s.focus_mode = Control.FOCUS_NONE
	s.scrollable = false
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.custom_minimum_size = Vector2(200, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl: = UITheme.label(_pct(s.value), "DimLabel")
	vl.custom_minimum_size = Vector2(48, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect( func(x):
		Settings.set_v(key, x)
		vl.text = _pct(x)
		_tick())
	h.add_child(s)
	h.add_child(vl)
	_row(label, desc, h)


func _pct(x: float) -> String:
	return "음소거" if x <= 0.001 else "%d%%" % roundi(x * 100.0)


## Slider feedback click, throttled so dragging does not machine-gun the sound.
func _tick() -> void :
	var now: = Time.get_ticks_msec()
	if now - _last_tick >= 110:
		_last_tick = now
		Sfx.play("click", 0.5)
