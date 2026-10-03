class_name BattlegroundScreen
extends Control

# V2 battleground setup (DESIGN_V2 §3.8): format (솔로 / 듀오 / 트리오), scale presets per
# format, zone speed and seed; the team roster panel (solo: 2 columns of 26 px player rows,
# duo / trio: one row per team), three map cards with cached previews, the hero roster with
# duplicate counts and the right tabs (character info / item odds by ring / zone timetable).
# Start builds the DESIGN_V2 §3.5 config and opens the battle.
#
#   page header (actions + start status) · rule badges · config card
#   team roster | maps + hero roster | right tabs
#
# Map previews come from a small shared cache (preview(), also used by the codex): the map is
# generated, turned into an Arena and rasterised (Minimap.rasterize) on a WorkerThreadPool task;
# the main thread only uploads the texture. A seed edit rebuilds only the selected map, after a
# short pause; the other cards keep the layout they show (their seed is printed on the card).
#
# Picking: solo appends a hero to the first empty slot (the same hero may play several times,
# RosterCard.set_count shows "×n"; right click removes one copy). Duo / trio add to the active team
# (click a team row to make it active); a hero can be in a team only once, so picking it again
# there removes it.

const FORMATS := [[1, "솔로", "한 명이 한 팀입니다. 같은 영웅을 여러 명 넣을 수 있습니다."],
	[2, "듀오", "두 명이 한 팀입니다. 쓰러지면 먼저 다운되고 팀원이 소생할 수 있습니다."],
	[3, "트리오", "세 명이 한 팀입니다. 쓰러지면 먼저 다운되고 팀원이 소생할 수 있습니다."]]
const SCALES := {1: [10, 15, 20, 25, 30], 2: [5, 8, 10, 12, 15], 3: [4, 6, 8, 10]}
const DEFAULT_SCALE := {1: 20, 2: 10, 3: 8}
const SPEED_OPTS := [["fast", "빠름", "자기장 일정이 ×0.8로 빨라집니다. 경기가 짧고 교전이 일찍 몰립니다."],
	["normal", "보통", "기본 일정입니다. 75초부터 6단계에 걸쳐 줄어듭니다."],
	["slow", "느림", "자기장 일정이 ×1.25로 느려집니다. 약탈과 이동에 시간이 더 있습니다."]]
const ROLES := [["", "전체"], ["FRONTLINE", "전방"], ["DAMAGE", "공격"], ["CONTROL", "제어"], ["SUPPORT", "지원"]]
const SEED_MAX := 99999999
const LEFT_W := 320
const RIGHT_W := 344
const CARD_MIN_W := 158
const GRID_GAP := 8
const MAP_GAP := 12
const HEAD_H := 38
const ROW_H := 26
const ROW_GAP := 2
const TRIO_ROW_H := 34
## Preview cache: maps kept (LRU) and the seed of the first cards and the codex.
const PREVIEW_KEEP := 8
const PREVIEW_SEED := 20261001
const ZONE_COL := Color("#cf9bff")

var app: App
var squad: int = 1
var n_teams: int = 20
## Hero id per slot in team-major order (team k owns slots k*squad .. k*squad+squad-1); "" = empty.
var slots: Array = []
var active_team: int = 0
var map_id: String = BattlegroundMapData.ORDER[0]
var zone_speed: String = "normal"
var role_filter: String = ""
var search: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var format_seg: HBoxContainer
var scale_seg: HBoxContainer
var scale_holder: HBoxContainer
var speed_seg: HBoxContainer
var role_seg: HBoxContainer
var seed_edit: LineEdit
var map_row: HBoxContainer
var map_cards: Dictionary = {}
var map_desc: Label
var roster_cards: Array = []
var roster_grid: GridContainer
var roster_scroll: ScrollContainer
var roster_empty: Control
var roster_head: HBoxContainer
var team_box: VBoxContainer
var team_scroll: ScrollContainer
var count_holder: HBoxContainer
var comp_flow: VBoxContainer
var start_btn: Button
var start_hint: Label
var fill_btn: Button
var clear_btn: Button
var detail: CharDetail
var right_tabs: TabBar
var detail_wrap: Control
var items_wrap: Control
var zone_wrap: Control
var zone_table: VBoxContainer
var seed_timer: float = -1.0
## Seed each card was last asked to show (the card shows it once the build is done).
var _want: Dictionary = {}

# ---------------------------------------------------------------- preview cache (shared)

## "id:seed" -> {arena, image, texture, counts, ms}
static var _cache: Dictionary = {}
static var _order: Array = []
## "id:seed" -> {task, out}
static var _jobs: Dictionary = {}
## Completed builds since start (tests count rebuilds with it).
static var builds: int = 0


static func preview_key(id: String, seed_v: int) -> String:
	return "%s:%d" % [id, seed_v]


## Cached preview of a map, or {} while it is built (a worker task is started on the first ask).
static func preview(id: String, seed_v: int) -> Dictionary:
	var key: String = preview_key(id, seed_v)
	if _cache.has(key):
		_order.erase(key)
		_order.append(key)
		return _cache[key]
	if not _jobs.has(key):
		var out: Array = []
		var task: int = WorkerThreadPool.add_task(func() -> void: _build_job(id, seed_v, out), false, "battleground preview")
		_jobs[key] = {"task": task, "out": out}
	return {}


## Synchronous build (developer lab, tests): the same result as a finished preview().
static func preview_now(id: String, seed_v: int) -> Dictionary:
	var hit: Dictionary = preview(id, seed_v)
	if not hit.is_empty():
		return hit
	var key: String = preview_key(id, seed_v)
	var job: Dictionary = _jobs.get(key, {})
	if not job.is_empty():
		_collect_preview(key, job)
	poll_previews()
	return _cache.get(key, {})


static func previews_pending() -> bool:
	return not _jobs.is_empty()


## Waits for running builds and drops every cached preview. Called when the screen leaves the
## tree (app exit): textures must not outlive the rendering server in a static variable.
static func release_previews() -> void:
	for key in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(int(_jobs[key].task))
	_jobs.clear()
	_cache.clear()
	_order.clear()


# Worker thread: generation, Arena and the thumbnail raster are pure functions of (id, seed).
static func _build_job(id: String, seed_v: int, out: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	var data: Dictionary = BattlegroundMapData.build(id, seed_v)
	if data.is_empty():
		return
	var a: Arena = Arena.from_data(data)
	a.shared = true
	var img: Image = Minimap.rasterize(a)
	out.append({"arena": a, "image": img, "ms": float(Time.get_ticks_usec() - t0) / 1000.0})


## Collects finished builds (main thread: texture upload, counts). Returns their keys.
static func poll_previews() -> Array:
	var done: Array = []
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if not WorkerThreadPool.is_task_completed(int(job.task)):
			continue
		if _collect_preview(key, job):
			done.append(key)
	return done


## Waiting retires a task ID; collect its output immediately so nobody polls that ID again.
static func _collect_preview(key: String, job: Dictionary) -> bool:
	WorkerThreadPool.wait_for_task_completion(int(job.task))
	_jobs.erase(key)
	var out: Array = job.out
	if out.is_empty():
		return false
	var r: Dictionary = out[0]
	r["texture"] = ImageTexture.create_from_image(r.image)
	r["counts"] = CodexData.br_counts(r.arena)
	_cache[key] = r
	_order.append(key)
	builds += 1
	while _order.size() > PREVIEW_KEEP:
		_cache.erase(_order.pop_front())
	return true


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
	main.add_child(_build_teams())
	main.add_child(_build_center())
	main.add_child(_build_right())
	_set_format(1)
	_randomize_all()
	for id in BattlegroundMapData.ORDER:
		_request(str(id))
	_set_map(map_id)
	detail.show_def(DB.char_def(str(slots[0])) if not slots.is_empty() and str(slots[0]) != "" else DB.characters[0])


func on_show(args: Dictionary) -> void:
	if args.has("format"):
		_set_format(int({"solo": 1, "duo": 2, "trio": 3}.get(str(args.format), 1)))
		if args.has("scale"):
			_set_scale(int(args.scale))
		_randomize_all()
	_refresh()
	if str(args.get("tab", "")) != "":
		right_tabs.current_tab = clampi(["chars", "items", "zone"].find(str(args.tab)), 0, 2)
	set_process(true)


func on_hide() -> void:
	set_process(previews_pending())


func _exit_tree() -> void:
	release_previews()


# Preview polling while builds run and the debounced seed rebuild; idle otherwise.
func _process(delta: float) -> void:
	if seed_timer >= 0.0:
		seed_timer -= delta
		if seed_timer < 0.0:
			_request(map_id)
	if previews_pending():
		poll_previews()
	# Home and codex share this cache and may collect completed jobs first. Refresh from the
	# cache even when this screen did not collect a job; otherwise cards can stay empty forever.
	_apply_previews()
	if seed_timer < 0.0 and not previews_pending():
		set_process(false)


func preview_ready(id: String, seed_v: int) -> bool:
	return _cache.has(preview_key(id, seed_v))


# ------------------------------------------------------------------ build

func _build_header() -> Control:
	var rnd: Button = UITheme.button("↻ 무작위", "", _randomize_all, "모든 자리를 무작위 영웅으로 새로 채웁니다.")
	fill_btn = UITheme.button("빈 자리 채우기", "", _fill_rest, "비어 있는 자리만 무작위 영웅으로 채웁니다. 이미 고른 참가자는 그대로 둡니다.")
	clear_btn = UITheme.button("초기화", "GhostButton", _clear, "참가자를 모두 뺍니다. 형식·규모·전장은 그대로 둡니다.")
	start_hint = UITheme.label("", "CaptionLabel")
	start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	start_hint.custom_minimum_size = Vector2(128, 0)
	start_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	start_btn = UITheme.button("전투 시작  ▶", "PrimaryButton", _start)
	start_btn.custom_minimum_size = Vector2(156, 44)
	return UITheme.page_header("BATTLEGROUND", "배틀그라운드",
		"최대 30명이 줄어드는 자기장 안에서 마지막까지 살아남는 생존전입니다. 형식과 참가자를 정한 뒤 시작하세요.",
		[rnd, fill_btn, clear_btn, start_hint, start_btn])


func _build_rules() -> Control:
	var h: HBoxContainer = UITheme.hbox(6)
	var cap: Label = UITheme.label("경기 규칙", "CaptionLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap)
	h.add_child(UITheme.spacer(2, 0))
	var by_key: Dictionary = {}
	for r in CodexData.BR_MAP_RULES:
		by_key[str(r.key)] = r
	for k in ["zone", "items", "down", "win", "format"]:
		var r: Dictionary = by_key.get(k, {})
		if r.is_empty():
			continue
		var title: String = str(r.title)
		if k == "down":
			title = "듀오·트리오 다운 → 소생"
		elif k == "format":
			title = "최대 %d명" % BattlegroundMode.MAX_HEROES
		var b: PanelContainer = UITheme.badge(title, UITheme.TEXT_DIM, "soft", str(r.text))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	var lines: PackedStringArray = PackedStringArray()
	for r in CodexData.BR_MAP_RULES:
		lines.append(UITheme.tip("%s — %s" % [str(r.title), str(r.text)], 44))
	var info: PanelContainer = UITheme.badge("ⓘ 규칙 자세히", UITheme.ACCENT, "outline", "")
	info.tooltip_text = "\n\n".join(lines)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_default_cursor_shape = Control.CURSOR_HELP
	h.add_child(info)
	return h


func _build_config() -> Control:
	var row: HBoxContainer = UITheme.hbox(0)
	format_seg = UITheme.segmented(FORMATS, squad, func(id): _set_format(int(id)); _refresh(), 64)
	row.add_child(_field("형식", format_seg, "팀당 인원입니다. 솔로는 개인전, 듀오·트리오는 분대전이며 분대전에서는 다운과 소생이 있습니다."))
	row.add_child(_vsep())
	scale_holder = UITheme.hbox(0)
	row.add_child(_field("규모", scale_holder, "참가 인원(솔로) 또는 팀 수(듀오·트리오)입니다. 최대 30명까지 참가합니다."))
	row.add_child(_vsep())
	speed_seg = UITheme.segmented(SPEED_OPTS, zone_speed, func(id): _set_speed(str(id)), 52)
	row.add_child(_field("자기장 속도", speed_seg, "자기장 일정 전체의 빠르기입니다. 단계 수와 원 크기, 피해는 같습니다."))
	row.add_child(_vsep())
	var sd: HBoxContainer = UITheme.hbox(UITheme.SP2)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(124, 40)
	seed_edit.max_length = 9
	seed_edit.placeholder_text = "숫자 입력"
	seed_edit.text = str(rng.randi_range(1, SEED_MAX))
	seed_edit.tooltip_text = UITheme.tip("같은 시드·참가자·전장이면 지형·아이템·자기장·전투가 똑같이 재현됩니다. 숫자를 바꾸면 선택한 전장의 미리보기만 다시 만듭니다.")
	seed_edit.text_changed.connect(_on_seed_text)
	sd.add_child(seed_edit)
	var reroll: Button = UITheme.button("무작위", "", _reroll_seed, "새 시드를 뽑아 전장 배치를 바꿉니다.")
	reroll.custom_minimum_size = Vector2(0, 40)
	sd.add_child(reroll)
	row.add_child(_field("시드", sd, "전장 배치, 아이템 배치와 자기장 원을 정하는 번호입니다."))
	return UITheme.panel("CardPanel", UITheme.margin(row, 4, 2, 4, 2))


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


func _vsep() -> Control:
	var line: Control = UITheme.sep_line(true)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var m: MarginContainer = UITheme.margin(line, UITheme.SP4, 4, UITheme.SP4, 4)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


func _build_teams() -> Control:
	var col: VBoxContainer = UITheme.vbox(UITheme.SP3)
	col.custom_minimum_size = Vector2(LEFT_W, 0)
	count_holder = UITheme.hbox(0)
	var head: HBoxContainer = UITheme.section_header("참가자", "", count_holder)
	head.custom_minimum_size = Vector2(0, HEAD_H)
	col.add_child(head)
	var v: VBoxContainer = UITheme.vbox(UITheme.SP3)
	team_box = UITheme.vbox(ROW_GAP)
	team_scroll = UITheme.scroll(team_box)
	team_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(team_scroll)
	v.add_child(UITheme.sep_line())
	comp_flow = UITheme.vbox(6)
	v.add_child(comp_flow)
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
	for id in BattlegroundMapData.ORDER:
		var card: BrMapCard = BrMapCard.new(str(id))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mid: String = str(id)
		card.pressed.connect(func(): _set_map(mid))
		map_cards[mid] = card
		map_row.add_child(card)
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
	roster_head = UITheme.section_header("캐릭터", "", tools)
	c.add_child(UITheme.margin(roster_head, 0, 4, 0, 0))
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
		rc.gui_input.connect(func(ev: InputEvent) -> void:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_remove_one(cid))
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
	right_tabs.add_tab("아이템 %d" % BattlegroundMode.ITEM_COUNT)
	right_tabs.add_tab("자기장")
	right_tabs.set_tab_tooltip(0, "마우스를 올리거나 누른 영웅의 능력치와 스킬을 봅니다.")
	right_tabs.set_tab_tooltip(1, "필드에 놓이는 아이템 %d개의 고리별 등급 확률과 아이템 %d종을 봅니다." % [BattlegroundMode.ITEM_COUNT, ItemDefs.ORDER.size()])
	right_tabs.set_tab_tooltip(2, "자기장 %d단계의 예고·수축 시각, 원 크기와 피해를 봅니다." % BrZone.PHASES)
	right_tabs.tab_changed.connect(_on_tab)
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
	items_wrap = _build_items()
	items_wrap.visible = false
	r.add_child(items_wrap)
	zone_wrap = _build_zone()
	zone_wrap.visible = false
	r.add_child(zone_wrap)
	return r


func _on_tab(i: int) -> void:
	detail_wrap.visible = i == 0
	items_wrap.visible = i == 1
	zone_wrap.visible = i == 2


func _build_items() -> Control:
	var v: VBoxContainer = UITheme.vbox(UITheme.SP3)
	var inner: VBoxContainer = UITheme.vbox(UITheme.SP3)
	inner.add_child(ItemViews.br_ring_table())
	inner.add_child(ItemViews.codex_list(true, Callable(), "battleground"))
	var sc: ScrollContainer = UITheme.scroll(UITheme.margin(inner, 0, 0, 6, 0))
	v.add_child(sc)
	v.add_child(UITheme.sep_line())
	var link: Button = UITheme.button("전투 도감에서 자세히 보기  →", "GhostButton", func(): if app: app.goto("codex", {"mode": "items"}),
		"아이템마다 상세 규칙과 잘 맞는 영웅을 전투 도감의 아이템 탭에서 볼 수 있습니다.")
	link.custom_minimum_size = Vector2(0, 38)
	v.add_child(link)
	var p: PanelContainer = UITheme.panel("CardPanel", v)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


func _build_zone() -> Control:
	var v: VBoxContainer = UITheme.vbox(UITheme.SP3)
	zone_table = UITheme.vbox(4)
	v.add_child(zone_table)
	v.add_child(UITheme.sep_line())
	for line in ["원 밖에서는 0.5초마다 최대 체력 비율의 고정 피해를 받습니다. 방어력·마법 저항력으로 줄지 않고 보호막이 먼저 흡수합니다.",
			"다음 원은 앞 단계의 수축이 끝나 대기가 시작될 때 공개됩니다. 첫 원만 약탈 시간 중에 예고됩니다.",
			"자기장 피해는 수풀 은신을 드러내지 않고 전투 이탈 회복 타이머를 초기화하지 않지만, 피해가 들어오는 원 밖에서는 회복하지 않습니다.",
			"다음 원의 중심은 지금 원 안쪽의 걸어갈 수 있는 곳이며, 가장자리는 초당 45 이하로 움직입니다."]:
		v.add_child(UITheme.wrap_label("· " + line, "CaptionLabel", 13))
	var sc: ScrollContainer = UITheme.scroll(UITheme.margin(v, 0, 0, 6, 0))
	var p: PanelContainer = UITheme.panel("CardPanel", sc)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p


## Zone timetable for the chosen speed (BrZone.schedule_rows): one row per phase.
func _refresh_zone_table() -> void:
	for c in zone_table.get_children():
		zone_table.remove_child(c)
		c.queue_free()
	zone_table.add_child(UITheme.section_header("자기장 일정", "%s · %s" % [str(BrZone.SPEED_LABELS.get(zone_speed, "보통")), "반경 = 전장 반대각선 대비"]))
	var hdr: HBoxContainer = UITheme.hbox(6)
	for col in [["단계", 40], ["예고", 48], ["수축", 92], ["원 크기", 56], ["피해", 0]]:
		var l: Label = UITheme.label(str(col[0]), "FaintLabel", UITheme.FS_MICRO)
		if int(col[1]) > 0:
			l.custom_minimum_size = Vector2(int(col[1]), 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hdr.add_child(l)
	zone_table.add_child(UITheme.margin(hdr, 8, 4, 8, 0))
	var rows: Array = BrZone.schedule_rows(zone_speed)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h: HBoxContainer = UITheme.hbox(6)
		var ph: Label = UITheme.label("Z%d" % int(r.phase), "BoldLabel", 13, ZONE_COL.lerp(UITheme.BAD, float(i) / float(maxi(1, rows.size() - 1))))
		ph.custom_minimum_size = Vector2(40, 0)
		h.add_child(ph)
		var an: Label = UITheme.label(UITheme.fmt_time(float(r.announce)), "", 13, UITheme.TEXT_DIM)
		an.custom_minimum_size = Vector2(48, 0)
		h.add_child(an)
		var sh: Label = UITheme.label("%s–%s" % [UITheme.fmt_time(float(r.shrink_start)), UITheme.fmt_time(float(r.shrink_end))], "", 13, UITheme.TEXT)
		sh.custom_minimum_size = Vector2(92, 0)
		h.add_child(sh)
		var rad: Label = UITheme.label("%d%%" % int(roundf(float(r.radius_ratio) * 100.0)) if float(r.radius_ratio) > 0.0 else "0", "", 13, UITheme.TEXT_DIM)
		rad.custom_minimum_size = Vector2(56, 0)
		h.add_child(rad)
		var dmg: Label = UITheme.label(ZonePill.dps_text(float(r.dps_ratio)), "BoldLabel", 13, UITheme.WARN.lerp(UITheme.BAD, float(i) / float(maxi(1, rows.size() - 1))))
		dmg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dmg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(dmg)
		var p: PanelContainer = UITheme.styled_panel(UITheme.sbc(Color(1, 1, 1, 0.03 if i % 2 == 0 else 0.0), UITheme.CLEAR, UITheme.R_S, 0, 8, 4), h)
		p.tooltip_text = UITheme.tip("%d단계 · %s에 예고 · %s부터 %s까지 줄어들어 반대각선의 %d%% 크기가 됩니다 · 원 밖 피해 %s" % [int(r.phase),
			UITheme.fmt_time(float(r.announce)), UITheme.fmt_time(float(r.shrink_start)), UITheme.fmt_time(float(r.shrink_end)), int(roundf(float(r.radius_ratio) * 100.0)), ZonePill.dps_text(float(r.dps_ratio))])
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		zone_table.add_child(p)
	var end_l: Label = UITheme.label("%s에 원이 사라지고, 경기는 늦어도 %s에 끝납니다." % [UITheme.fmt_time(float(rows.back().shrink_end)), UITheme.fmt_time(BattlegroundMode.MAX_TIME)], "FaintLabel", 12)
	zone_table.add_child(UITheme.margin(end_l, 8, 4, 8, 0))


# ------------------------------------------------------------------ settings

func _set_format(sq: int) -> void:
	sq = clampi(sq, 1, 3)
	var heroes: Array = _filled()
	squad = sq
	UITheme.segmented_select(format_seg, sq)
	# Scale presets of this format (rebuilt: a segmented control has fixed options).
	for c in scale_holder.get_children():
		scale_holder.remove_child(c)
		c.queue_free()
	var opts: Array = []
	for n in SCALES[sq]:
		opts.append([int(n), ("%d명" % int(n)) if sq == 1 else ("%d팀" % int(n)), ("%d명이 각자 싸웁니다." % int(n)) if sq == 1 else ("%d팀 · %d명" % [int(n), int(n) * sq])])
	scale_seg = UITheme.segmented(opts, int(DEFAULT_SCALE[sq]), func(id): _set_scale(int(id)), 50)
	scale_holder.add_child(scale_seg)
	n_teams = int(DEFAULT_SCALE[sq])
	_resize_slots()
	# Keep the heroes already picked, in order (repeats inside a team are dropped by _pack).
	_pack(heroes)
	active_team = 0
	roster_head.get_meta("hint").text = "눌러서 추가 · 우클릭으로 하나 빼기" if sq == 1 else "눌러서 선택한 팀에 추가·제외 · 팀 행을 눌러 선택"


func _set_scale(n: int) -> void:
	n_teams = clampi(n, 2, floori(float(BattlegroundMode.MAX_HEROES) / float(squad)))
	UITheme.segmented_select(scale_seg, n_teams)
	_resize_slots()
	active_team = mini(active_team, n_teams - 1)
	_refresh()


func _set_speed(id: String) -> void:
	zone_speed = id if BrZone.SPEEDS.has(id) else "normal"
	UITheme.segmented_select(speed_seg, zone_speed)
	_refresh_zone_table()
	_refresh_start()


func _set_role(r: String) -> void:
	role_filter = r
	UITheme.segmented_select(role_seg, r)
	_refresh_roster()


func _resize_slots() -> void:
	var want: int = n_teams * squad
	while slots.size() > want:
		slots.pop_back()
	while slots.size() < want:
		slots.append("")


func _filled() -> Array:
	return slots.filter(func(x): return str(x) != "")


## Lays heroes into the slots in order, skipping a repeat inside a team.
func _pack(heroes: Array) -> void:
	for i in slots.size():
		slots[i] = ""
	var team: int = 0
	for id in heroes:
		while team < n_teams and not _can_add(team, str(id)):
			team += 1
		if team >= n_teams:
			break
		slots[_free_slot(team)] = str(id)


func team_ids(team: int) -> Array:
	var out: Array = []
	for k in squad:
		var id: String = str(slots[team * squad + k])
		if id != "":
			out.append(id)
	return out


func _free_slot(team: int) -> int:
	for k in squad:
		if str(slots[team * squad + k]) == "":
			return team * squad + k
	return -1


func _can_add(team: int, id: String) -> bool:
	return _free_slot(team) >= 0 and (squad <= 1 or not team_ids(team).has(id))


# ------------------------------------------------------------------ maps

func _seed_value() -> int:
	return int(seed_edit.text) if seed_edit.text.is_valid_int() else 1


func _on_seed_text(t: String) -> void:
	var clean: String = ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			clean += ch
	if clean != t:
		var caret: int = seed_edit.caret_column - (t.length() - clean.length())
		seed_edit.text = clean
		seed_edit.caret_column = clampi(caret, 0, clean.length())
	seed_timer = 0.45
	set_process(true)


func _reroll_seed() -> void:
	seed_edit.text = str(rng.randi_range(1, SEED_MAX))
	seed_timer = 0.05
	set_process(true)


## Asks for the preview of map id at the current seed (cached, else a worker build).
func _request(id: String) -> void:
	var sv: int = _seed_value()
	_want[id] = sv
	preview(id, sv)
	_apply_previews()
	set_process(true)


## Cards show their wanted seed once built, else keep the layout they had.
func _apply_previews() -> void:
	for id in map_cards:
		var card: BrMapCard = map_cards[id]
		var sv: int = int(_want.get(id, -1))
		if _cache.has(preview_key(str(id), sv)):
			if card.shown_seed != sv or card.texture == null:
				card.set_preview(_cache[preview_key(str(id), sv)], sv)
		card.loading = not _cache.has(preview_key(str(id), sv))
	_update_map_desc()


func _set_map(id: String) -> void:
	map_id = id
	for k in map_cards:
		(map_cards[k] as BrMapCard).set_selected(k == id)
	if int(_want.get(id, -1)) != _seed_value():
		_request(id)
	_update_map_desc()
	_refresh_start()


func _update_map_desc() -> void:
	if map_desc == null:
		return
	var p: Dictionary = BattlegroundMapData.PRESETS.get(map_id, {})
	map_desc.text = "%s — %s" % [str(p.get("name", map_id)), str(p.get("description", ""))]
	map_desc.tooltip_text = UITheme.tip(map_desc.text)


# ------------------------------------------------------------------ roster

func _show_def(d: Defs.CharDef) -> void:
	if d != null:
		detail.show_def(d)


func _focus_def(d: Defs.CharDef) -> void:
	_show_def(d)
	if right_tabs.current_tab != 0:
		right_tabs.current_tab = 0


func _on_roster_pressed(id: String) -> void:
	pick(id)
	_focus_def(DB.char_def(id))


## Roster click: solo adds a copy to the first empty slot; duo / trio toggle the hero in the
## active team (a full team passes the pick on to the next team with room).
func pick(id: String) -> void:
	if squad <= 1:
		var free: int = slots.find("")
		if free < 0:
			_toast("모든 자리가 찼습니다. 참가자를 빼거나 규모를 늘려 주세요.")
			return
		slots[free] = id
		Sfx.play("pick", 0.35)
		_refresh()
		return
	var mine: Array = team_ids(active_team)
	if mine.has(id):
		for k in squad:
			if str(slots[active_team * squad + k]) == id:
				slots[active_team * squad + k] = ""
		_compact_team(active_team)
		_refresh()
		return
	for step in n_teams:
		var team: int = (active_team + step) % n_teams
		if _can_add(team, id):
			slots[_free_slot(team)] = id
			if _free_slot(team) < 0 and step == 0:
				active_team = _next_open_team(team)
			elif step > 0:
				active_team = team
			Sfx.play("pick", 0.35)
			_refresh()
			return
	_toast("이 영웅을 넣을 수 있는 자리가 없습니다. 같은 팀에는 같은 영웅을 넣을 수 없습니다.")


func _next_open_team(from: int) -> int:
	for step in range(1, n_teams + 1):
		var t: int = (from + step) % n_teams
		if _free_slot(t) >= 0:
			return t
	return from


## Right click on a roster card: removes the last copy of the hero.
func _remove_one(id: String) -> void:
	for i in range(slots.size() - 1, -1, -1):
		if str(slots[i]) == id:
			remove_slot(i)
			return


func remove_slot(i: int) -> void:
	if i < 0 or i >= slots.size():
		return
	slots[i] = ""
	if squad > 1:
		_compact_team(floori(float(i) / float(squad)))
	_refresh()


func _compact_team(team: int) -> void:
	var ids: Array = team_ids(team)
	for k in squad:
		slots[team * squad + k] = str(ids[k]) if k < ids.size() else ""


func set_active_team(team: int) -> void:
	active_team = clampi(team, 0, n_teams - 1)
	_refresh()


## Hero for a new pick: unused heroes first (solo, before anyone repeats); never one the team has.
func _draw_hero(team: int) -> String:
	var used: Dictionary = {}
	for id in slots:
		if str(id) != "":
			used[str(id)] = int(used.get(str(id), 0)) + 1
	var mine: Array = team_ids(team)
	var best: Array = []
	var best_n: int = 1 << 30
	for id in DB.ids():
		if squad > 1 and mine.has(id):
			continue
		var n: int = int(used.get(id, 0))
		if n < best_n:
			best_n = n
			best = [id]
		elif n == best_n:
			best.append(id)
	return str(best[rng.randi_range(0, best.size() - 1)]) if not best.is_empty() else "swordsman"


func _randomize_all() -> void:
	for i in slots.size():
		slots[i] = ""
	_fill_rest()


func _fill_rest() -> void:
	for i in slots.size():
		if str(slots[i]) == "":
			slots[i] = _draw_hero(floori(float(i) / float(squad)))
	_refresh()


func _clear() -> void:
	for i in slots.size():
		slots[i] = ""
	active_team = 0
	_refresh()


func _toast(text: String) -> void:
	if app:
		app.toast(text, UITheme.WARN)


func _refresh() -> void:
	if team_box == null:
		return
	_rebuild_teams()
	var filled: int = _filled().size()
	for c in count_holder.get_children():
		count_holder.remove_child(c)
		c.queue_free()
	count_holder.add_child(UITheme.badge("%d / %d" % [filled, slots.size()], UITheme.GOOD if filled == slots.size() else UITheme.WARN, "soft"))
	_refresh_composition()
	fill_btn.disabled = filled >= slots.size()
	clear_btn.disabled = filled == 0
	_refresh_start()
	_refresh_roster()
	if zone_table and zone_table.get_child_count() == 0:
		_refresh_zone_table()


# Start status next to the start button: why it is disabled, or what will start.
func _refresh_start() -> void:
	if start_btn == null or start_hint == null:
		return
	var missing: int = slots.size() - _filled().size()
	var errors: Array = BattlegroundMode.validate(build_config()) if missing == 0 else []
	start_btn.disabled = missing > 0 or not errors.is_empty()
	var tip: String
	if missing > 0:
		start_hint.text = "%d명 더 선택하세요" % missing
		start_hint.add_theme_color_override("font_color", UITheme.WARN)
		tip = "참가자를 %d명 더 선택해야 시작할 수 있습니다. ‘빈 자리 채우기’로 남은 자리를 한 번에 채울 수 있습니다." % missing
	elif not errors.is_empty():
		start_hint.text = "편성을 확인하세요"
		start_hint.add_theme_color_override("font_color", UITheme.BAD)
		tip = str(errors[0])
	else:
		start_hint.text = ("%d명 준비 완료" % slots.size()) if squad <= 1 else ("%d팀 %d명 준비" % [n_teams, slots.size()])
		start_hint.add_theme_color_override("font_color", UITheme.GOOD)
		tip = "%s · %s에서 시작합니다 · 자기장 %s" % [_format_text(), str((BattlegroundMapData.PRESETS.get(map_id, {}) as Dictionary).get("name", map_id)), str(BrZone.SPEED_LABELS.get(zone_speed, "보통"))]
	start_btn.tooltip_text = UITheme.tip(tip)
	start_hint.tooltip_text = start_btn.tooltip_text


func _format_text() -> String:
	var name: String = str(FORMATS[squad - 1][1])
	return ("%s %d명" % [name, n_teams]) if squad <= 1 else ("%s %d팀 %d명" % [name, n_teams, n_teams * squad])


func _refresh_composition() -> void:
	for c in comp_flow.get_children():
		comp_flow.remove_child(c)
		c.queue_free()
	var heroes: Array = _filled()
	if heroes.is_empty():
		comp_flow.add_child(UITheme.label("참가자를 고르면 역할 구성이 표시됩니다.", "FaintLabel"))
		return
	var roles: Dictionary = {}
	var melee: int = 0
	var repeats: int = 0
	var seen: Dictionary = {}
	for id in heroes:
		var d: Defs.CharDef = DB.char_def(str(id))
		roles[d.role] = int(roles.get(d.role, 0)) + 1
		if d.is_melee():
			melee += 1
		if seen.has(id):
			repeats += 1
		seen[id] = true
	var role_row: HBoxContainer = UITheme.hbox(6)
	role_row.add_child(_comp_caption("역할"))
	for r in ["FRONTLINE", "DAMAGE", "CONTROL", "SUPPORT"]:
		if roles.has(r):
			role_row.add_child(UITheme.badge("%s %d" % [DB.role_label(r), roles[r]], UITheme.role_color(r), "soft"))
	comp_flow.add_child(role_row)
	var info_row: HBoxContainer = UITheme.hbox(6)
	info_row.add_child(_comp_caption("구성"))
	info_row.add_child(UITheme.badge("근접 %d · 원거리 %d" % [melee, heroes.size() - melee], UITheme.TEXT_DIM, "outline", "기본 공격 사거리가 100 이하인 영웅을 근접으로 셉니다."))
	if repeats > 0:
		info_row.add_child(UITheme.badge("중복 %d" % repeats, UITheme.ACCENT, "outline", "같은 영웅이 여러 팀에 들어간 횟수입니다. 같은 팀 안에서는 중복될 수 없습니다."))
	comp_flow.add_child(info_row)


func _comp_caption(text: String) -> Label:
	var l: Label = UITheme.label(text, "CaptionLabel")
	l.custom_minimum_size = Vector2(32, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Team roster panel: solo = 2 columns of 26 px player rows; duo / trio = one row per team with
## a member chip per slot (the active team is outlined).
func _rebuild_teams() -> void:
	for c in team_box.get_children():
		team_box.remove_child(c)
		c.queue_free()
	if squad <= 1:
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", ROW_GAP)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Column-major: P1..P15 on the left, P16..P30 on the right.
		var rows: int = int(ceil(slots.size() / 2.0))
		for r in rows:
			for c2 in 2:
				var i: int = c2 * rows + r
				if i < slots.size():
					grid.add_child(_player_row(i))
				else:
					grid.add_child(Control.new())
		team_box.add_child(grid)
		return
	for team in n_teams:
		team_box.add_child(_team_row(team))


func _player_row(i: int) -> Control:
	var id: String = str(slots[i])
	var tc: Color = UITheme.team_color(i)
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_row_styles(b, tc, false, id == "")
	var h: HBoxContainer = UITheme.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 3
	h.offset_right = -1
	b.add_child(h)
	h.add_child(_label_pill(DB.team_name(i, 1), i, id != ""))
	if id == "":
		var t: Label = UITheme.ellipsize(UITheme.label("빈 자리", "FaintLabel", 12))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
		b.tooltip_text = "오른쪽 캐릭터 목록에서 영웅을 누르면 빈 자리에 들어갑니다."
		return b
	var d: Defs.CharDef = DB.char_def(id)
	var disc: GlyphDisc = GlyphDisc.new(d, 18, i)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(disc)
	var nm: Label = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel", 12))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	h.add_child(_remove_btn(i, d.name))
	b.tooltip_text = UITheme.tip("%s %s · %s\n누르면 오른쪽에 정보를 보여 줍니다. ✕를 누르면 뺍니다." % [DB.team_name(i, 1), d.name, DB.role_label(d.role)])
	b.mouse_entered.connect(func(): _show_def(d))
	b.pressed.connect(func(): _focus_def(d))
	return b


func _team_row(team: int) -> Control:
	var tc: Color = UITheme.team_color(team)
	var active: bool = team == active_team
	var row_h: int = TRIO_ROW_H if squad >= 3 else ROW_H
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, row_h)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_row_styles(b, tc, active, team_ids(team).is_empty())
	b.tooltip_text = UITheme.tip("%s%s · 누르면 이 팀이 선택되어, 캐릭터를 누를 때 이 팀에 추가됩니다. 영웅 칩을 누르면 뺍니다." % [DB.team_name(team, squad), " (선택됨)" if active else ""])
	b.pressed.connect(func(): set_active_team(team))
	var h: HBoxContainer = UITheme.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	h.offset_right = -4
	b.add_child(h)
	h.add_child(_label_pill(DB.team_name(team, squad), team, not team_ids(team).is_empty()))
	for k in squad:
		h.add_child(_member_chip(team * squad + k, tc, row_h - 6))
	return b


## A team member slot in a team row: disc + name (click removes), or an empty dashed slot.
func _member_chip(i: int, tc: Color, h_px: int) -> Control:
	var id: String = str(slots[i])
	var c: Button = Button.new()
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(0, h_px)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.clip_contents = true
	var hb: HBoxContainer = UITheme.hbox(4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 3
	hb.offset_right = -3
	c.add_child(hb)
	if id == "":
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			c.add_theme_stylebox_override(st, UITheme.sbc(Color(0, 0, 0, 0.16), Color(UITheme.LINE2, 0.5), UITheme.R_S, 1, 0, 0))
		var t: Label = UITheme.label("빈 자리", "FaintLabel", 12)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(t)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c
	var d: Defs.CharDef = DB.char_def(id)
	c.add_theme_stylebox_override("normal", UITheme.sbc(Color(tc, 0.1), Color(tc, 0.3), UITheme.R_S, 1, 0, 0))
	c.add_theme_stylebox_override("hover", UITheme.sbc(Color(UITheme.BAD, 0.14), Color(UITheme.BAD, 0.55), UITheme.R_S, 1, 0, 0))
	c.add_theme_stylebox_override("pressed", UITheme.sbc(Color(UITheme.BAD, 0.2), UITheme.BAD, UITheme.R_S, 1, 0, 0))
	c.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(UITheme.BAD, 0.2), UITheme.BAD, UITheme.R_S, 1, 0, 0))
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var disc: GlyphDisc = GlyphDisc.new(d, mini(18, h_px - 4), -1)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(disc)
	var nm: Label = UITheme.ellipsize(UITheme.label(d.name, "", 12, UITheme.TEXT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(nm)
	c.tooltip_text = "%s — 누르면 팀에서 뺍니다" % d.name
	c.mouse_entered.connect(func(): _show_def(d))
	c.pressed.connect(func(): remove_slot(i))
	return c


func _row_styles(b: Button, tc: Color, active: bool, empty: bool) -> void:
	var base: Color = Color(1, 1, 1, 0.015) if empty else Color(1, 1, 1, 0.03)
	var border: Color = tc if active else (Color(UITheme.LINE, 0.6) if empty else UITheme.LINE)
	b.add_theme_stylebox_override("normal", UITheme.sbc(Color(tc, 0.08) if active else base, border, UITheme.R_S, 2 if active else 1, 0, 0))
	b.add_theme_stylebox_override("hover", UITheme.sbc(Color(1, 1, 1, 0.06), Color(tc, 0.75), UITheme.R_S, 2 if active else 1, 0, 0))
	b.add_theme_stylebox_override("pressed", UITheme.sbc(Color(1, 1, 1, 0.06), tc, UITheme.R_S, 2, 0, 0))
	b.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(1, 1, 1, 0.06), tc, UITheme.R_S, 2, 0, 0))
	b.add_theme_stylebox_override("focus", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, 0, 0, 0, 0))


## Team / player number pill in the team colour (lighter shades carry the number anyway).
func _label_pill(text: String, team: int, filled: bool) -> Control:
	var tc: Color = UITheme.team_color(team)
	var l: Label = UITheme.label(text, "BadgeLabel", 0, UITheme.team_ink(team) if filled else tc.lightened(0.3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(31 if squad <= 1 else 38, 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_stylebox_override("normal", UITheme.sbc(tc if filled else Color(tc, 0.1), Color(tc, 0.8), UITheme.R_PILL, 1, 4, 0))
	return l


func _remove_btn(i: int, hero_name: String) -> Button:
	var rm: Button = Button.new()
	rm.text = "✕"
	rm.focus_mode = Control.FOCUS_NONE
	rm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rm.custom_minimum_size = Vector2(16, 20)
	rm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rm.tooltip_text = "%s 빼기" % hero_name
	rm.add_theme_font_size_override("font_size", 11)
	rm.add_theme_stylebox_override("normal", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("hover", UITheme.sbc(Color(UITheme.BAD, 0.16), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("pressed", UITheme.sbc(Color(UITheme.BAD, 0.26), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("hover_pressed", UITheme.sbc(Color(UITheme.BAD, 0.26), UITheme.CLEAR, UITheme.R_S, 0, 0, 0))
	rm.add_theme_stylebox_override("focus", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, 0, 0, 0, 0))
	rm.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	rm.add_theme_color_override("font_hover_color", UITheme.BAD)
	rm.pressed.connect(func(): remove_slot(i))
	return rm


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
		# Solo: the first player slot holding the hero; squads: the active team first.
		var count: int = 0
		var first: int = -1
		var teams_with: Array = []
		for i in slots.size():
			if str(slots[i]) == d.id:
				count += 1
				var t: int = floori(float(i) / float(squad))
				if first < 0:
					first = t
				if not teams_with.has(t):
					teams_with.append(t)
		if squad > 1 and teams_with.has(active_team):
			first = active_team
		card.set_picked(first, DB.team_name(first, squad) if first >= 0 else "")
		card.set_count(count)
	if roster_empty:
		roster_empty.get_parent().visible = shown_n == 0
		roster_empty.visible = shown_n == 0


func _fit_roster_columns() -> void:
	var w: float = roster_scroll.size.x - 12.0
	var cols: int = maxi(1, int(floor((w + GRID_GAP) / float(CARD_MIN_W + GRID_GAP))))
	if cols != roster_grid.columns:
		roster_grid.columns = cols


# ------------------------------------------------------------------ start

## The DESIGN_V2 §3.5 start config of the current setup.
func build_config() -> Dictionary:
	var teams: Array = []
	for team in n_teams:
		teams.append(team_ids(team))
	return {"ruleset": "battleground", "mode": "battleground", "arena_id": map_id, "seed": _seed_value(), "squad": squad,
		"teams": teams, "zone_speed": zone_speed, "max_time": BattlegroundMode.MAX_TIME, "ai": "tactician"}


func _start() -> void:
	if _filled().size() != slots.size():
		return
	if not seed_edit.text.is_valid_int():
		seed_edit.text = str(rng.randi_range(1, SEED_MAX))
	var cfg: Dictionary = build_config()
	var errors: Array = BattlegroundMode.validate(cfg)
	if not errors.is_empty():
		_toast(str(errors[0]))
		return
	Sfx.play("start", 0.5)
	app.start_battle(cfg, "battleground")


# ------------------------------------------------------------------ map card

## Battleground map card: the cached minimap raster (aspect kept, letterboxed), a loading
## spinner while the selected seed is built, the seed it shows, name, subtitle and a counts line.
## Custom drawn; redraws on hover / selection / new preview only (and while loading).
class BrMapCard:
	extends Button
	const THUMB_H := 118.0
	const INSET := 8.0
	const CAPTION_H := 62.0
	var id: String = ""
	var preset: Dictionary = {}
	var texture: Texture2D
	var shown_seed: int = -1
	var counts: Dictionary = {}
	var selected: bool = false
	var loading: bool = false:
		set(v):
			if v != loading:
				loading = v
				set_process(v)
				queue_redraw()
	var _spin: float = 0.0

	func _init(map_id: String) -> void:
		id = map_id
		preset = BattlegroundMapData.PRESETS.get(map_id, {})
		custom_minimum_size = Vector2(180, INSET + THUMB_H + CAPTION_H)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		tooltip_text = UITheme.tip("%s · %s\n%s\n건물·수풀(무리)·기믹(환경 효과) 수는 카드에 적힌 시드의 배치 기준입니다. 누르면 이 전장을 고릅니다." % [str(preset.get("name", map_id)), str(preset.get("subtitle", "")), str(preset.get("description", ""))])
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		set_process(false)

	func set_preview(p: Dictionary, seed_v: int) -> void:
		texture = p.get("texture")
		counts = p.get("counts", {})
		shown_seed = seed_v
		queue_redraw()

	func set_selected(v: bool) -> void:
		selected = v
		queue_redraw()

	func _process(delta: float) -> void:
		_spin += delta
		queue_redraw()

	func _draw() -> void:
		var hover: bool = is_hovered()
		draw_style_box(ArenaCard._frame_style(hover, selected), Rect2(Vector2.ZERO, size))
		var area: = Rect2(INSET, INSET, size.x - INSET * 2.0, THUMB_H)
		draw_rect(area, Color(0.02, 0.03, 0.05, 0.9))
		if texture:
			var ts: Vector2 = Vector2(texture.get_size())
			var k: float = minf(area.size.x / ts.x, area.size.y / ts.y)
			var tr: = Rect2(area.position + (area.size - ts * k) * 0.5, ts * k)
			draw_texture_rect(texture, tr, false)
			if selected:
				draw_rect(tr, Color(UITheme.ACCENT, 0.7), false, 1.5)
			elif hover:
				draw_rect(tr, Color(1, 1, 1, 0.05))
		var accent: Color = Color(str(preset.get("accent", "#6cb6ff")))
		if loading:
			draw_rect(area, Color(0, 0, 0, 0.45))
			var c: Vector2 = area.get_center() - Vector2(0, 8)
			draw_arc(c, 13.0, _spin * 5.0, _spin * 5.0 + PI * 1.4, 24, Color(accent, 0.9), 2.5, true)
			var lt: String = "지도 생성 중"
			var lw: float = DB.font_bold.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(DB.font_bold, Vector2(c.x - lw * 0.5, c.y + 32.0), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)
		elif shown_seed >= 0:
			var st: String = "시드 %d" % shown_seed
			var sw: float = DB.font_bold.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var pill: = Rect2(area.position + Vector2(6, 6), Vector2(sw + 12.0, 17.0))
			draw_style_box(UITheme.sbc(Color(0.02, 0.03, 0.05, 0.8), Color(1, 1, 1, 0.14), UITheme.R_PILL, 1, 0, 0), pill)
			draw_string(DB.font_bold, pill.position + Vector2(6, 12.5), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
		if selected:
			var cc: = Vector2(area.end.x - 13.0, area.position.y + 13.0)
			draw_circle(cc, 11.0, Color(UITheme.BG, 0.85), true, -1.0, true)
			draw_circle(cc, 9.0, UITheme.ACCENT, true, -1.0, true)
			draw_polyline(PackedVector2Array([cc + Vector2(-4.2, 0.2), cc + Vector2(-1.2, 3.2), cc + Vector2(4.4, -2.8)]), UITheme.BG, 2.2, true)
		var y: float = area.end.y + 20.0
		draw_string(DB.font_bold, Vector2(12, y), "◉", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, accent)
		draw_string(DB.font_bold, Vector2(32, y), UITheme.fit_text(DB.font_bold, str(preset.get("name", id)), 15, size.x - 44.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE if selected else UITheme.TEXT)
		var size_s: String = "%s×%s" % [CodexData.num(float(preset.get("width", 0.0))), CodexData.num(float(preset.get("height", 0.0)))]
		var l1: String = size_s
		var l2: String = "지도를 만드는 중입니다"
		if not counts.is_empty():
			l1 = "건물 %d · 수풀 %d · 기믹 %d" % [int(counts.buildings), int(counts.brush), int(counts.gimmicks)]
			l2 = "아이템 자리 %d · %s" % [int(counts.item_spots), size_s]
		draw_string(DB.font_regular, Vector2(12, y + 18.0), UITheme.fit_text(DB.font_regular, l1, 12, size.x - 22.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)
		draw_string(DB.font_regular, Vector2(12, y + 35.0), UITheme.fit_text(DB.font_regular, l2, 12, size.x - 22.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_FAINT)
