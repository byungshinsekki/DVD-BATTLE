class_name HomeScreen
extends Control

## Play home: hero (slogan, primary "빠른 관전" CTA, computed facts, live AI-vs-AI preview), four
## play-mode cards plus the full-width battleground feature card (V2, "NEW"), library links into
## the codex, the player's records and the V2 preview notes.

const PAGE_MAX_W: = 1680.0
const HERO_BG: = UITheme.PANEL2
## Play-mode glyphs (match the sidebar icons); the hero fact row counts them as "모드".
const MODE_GLYPHS: = {"setup": "⚔", "draft": "◈", "control": "◎", "deathmatch": "✦", "battleground": "◉"}
const REC_HINT: = "AI 대전 전적과 관전한 전투"
const REC_EMPTY_HINT: = "아직 기록이 없어요 · AI 대전으로 시작해 보세요"

var app: App
var preview: LivePreview
var rec_labels: Dictionary = {}
var rate_label: Label
var rec_header: HBoxContainer
var modes_grid: GridContainer
var lib_grid: GridContainer
var notes_grid: GridContainer
var notes: VBoxContainer
var scroll: ScrollContainer
var cards: Array = []
var br_card: Control
var br_thumbs: Array = []
var _page: Control
static var _hero_style: StyleBoxFlat


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	# Map thumbnails are requested on show (on_show), not while the screen is hidden.
	set_process(false)
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v: = UITheme.vbox(UITheme.SP5)
	_page = UITheme.max_width(UITheme.page_margin(v), PAGE_MAX_W)
	scroll.add_child(_page)
	_page.resized.connect(_reflow)

	v.add_child(_build_hero())

	# Play modes.
	var n_elim: int = DB.arenas_for("elimination").size()
	var n_ctrl: int = DB.arenas_for("control").size()
	var n_items: int = ItemDefs.ORDER.size()
	# Descriptions carry an explicit line break: Korean wraps per syllable, which left orphan lines.
	modes_grid = _grid(4)
	modes_grid.add_child(_mode_card(MODE_GLYPHS.setup, "조합 대전", "양 팀을 직접 편성하고\n전술가 AI끼리의 전투를 관전해요.",
		["섬멸전", "1v1 ~ 5v5", "전장 %d종" % n_elim], UITheme.ACCENT, func(): _go("setup", {"ruleset": "elimination"})))
	modes_grid.add_child(_mode_card(MODE_GLYPHS.draft, "AI 대전", "한 명씩 번갈아 뽑으며\nAI의 카운터 드래프트에 맞서요.",
		["교대 선택", "미니맥스 탐색", "전적 기록"], UITheme.ACCENT2, func(): _go("draft")))
	modes_grid.add_child(_mode_card(MODE_GLYPHS.control, "거점 장악", "넓은 전장의 거점을 나눠 점령하고\n300점을 먼저 모으면 승리해요.",
		["300점 선승", "회복 구역", "전장 %d종" % n_ctrl], UITheme.GOLD, func(): _go("setup", {"ruleset": "control"})))
	modes_grid.add_child(_mode_card(MODE_GLYPHS.deathmatch, "데스매치", "최대 12명이 넓은 전장에서\n아이템을 모으며 각자 싸워요.",
		["최대 12명", "아이템 %d종" % n_items, "전장 %d종" % DeathmatchMapData.ORDER.size()], UITheme.GOOD, func(): _go("deathmatch")))
	var play: VBoxContainer = UITheme.vbox(UITheme.SP4)
	play.add_child(modes_grid)
	br_card = _br_feature_card()
	play.add_child(br_card)
	v.add_child(_section("플레이 모드", "원하는 방식을 골라 바로 시작하세요", play))

	# Library shortcuts into the codex (left) and the player's records (right).
	lib_grid = _grid(2)
	lib_grid.add_child(_link_card("★", "캐릭터 도감", "%d명 · 능력치·스킬·AI 운용" % DB.characters.size(), {"mode": "chars"}))
	lib_grid.add_child(_link_card("◆", "아이템 도감", "%d종 · 등급·확률·숨은 규칙" % n_items, {"mode": "items"}))
	lib_grid.add_child(_link_card("☰", "용어 사전", "%d개 · 상태 이상·피해 규칙" % CodexData.STATUS.size(), {"mode": "glossary"}))
	lib_grid.add_child(_link_card("▦", "전장 도감", "%d곳 · 환경 효과·전장 규칙" % _arena_total(), {"mode": "arenas"}))
	var lower: = UITheme.hbox(UITheme.SP5)
	var lib: = _section("라이브러리", "전투 도감 바로 가기", lib_grid)
	lib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib.size_flags_stretch_ratio = 1.2
	lower.add_child(lib)
	rec_header = UITheme.section_header("플레이 기록", REC_HINT)
	var recs: = UITheme.vbox(UITheme.SP3)
	recs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recs.add_child(rec_header)
	recs.add_child(_build_records())
	lower.add_child(recs)
	v.add_child(lower)

	# Preview notes describe the features available in this build.
	notes_grid = _grid(2)
	for n in [
		["★", UITheme.ACCENT, "새 영웅 4명 · 총 26명", "하데스, 전쟁 기계, 토르케마다, 아킬레우스가 합류했어요. 전투 도감에서 능력치와 스킬을 살펴보고 실제 스킬 시연을 재생해 보세요."],
		["◉", UITheme.GOLD, "배틀그라운드 · 대형 전장 3종", "솔로·듀오·트리오로 최대 30명이 싸워요. 80개의 아이템을 모으고 줄어드는 자기장 안에서 마지막까지 살아남으세요."],
		["✚", UITheme.ACCENT2, "분대 AI · 다운과 소생", "AI가 보급, 자기장 이동, 교전과 이탈을 판단해요. 듀오·트리오에서는 다운된 팀원을 소생시키고 엄호하며 함께 생존해요."],
		["⌘", UITheme.GOOD, "관전과 개발자 실험실", "팀별 시점, 미니맵, 생존 순위와 AI 판단을 확인하세요. 실험실에서 맵·시드·참가자를 정하고 일시정지와 단계 진행으로 전투를 검토할 수 있어요."],
	]:
		notes_grid.add_child(_note_card(n[0], n[1], n[2], n[3]))
	var notes_hdr: = UITheme.section_header("V2 프리뷰 · 26인 로스터 · 배틀그라운드", "새 기능을 먼저 플레이하는 프리뷰 버전입니다. 밸런스와 AI는 계속 조정됩니다.", UITheme.badge("업데이트 노트", UITheme.ACCENT, "outline"))
	notes = UITheme.vbox(UITheme.SP3)
	notes.add_child(notes_hdr)
	notes.add_child(notes_grid)
	# Extra breathing room: the play area (hero → records) reads as one block, the notes as another.
	v.add_child(UITheme.spacer(0, UITheme.SP4))
	v.add_child(notes)


# ------------------------------------------------------------------ hero

func _build_hero() -> Control:
	if _hero_style == null:
		# Opaque (the DVD backdrop must not bleed through) with the card elevation.
		_hero_style = UITheme.elevate(UITheme.sb(HERO_BG, UITheme.LINE, UITheme.R_XL, 1, 0, 0), 1)
	var hero: = UITheme.hbox(0)
	hero.custom_minimum_size = Vector2(0, 330)
	var panel: = UITheme.styled_panel(_hero_style, hero)

	var copy: = UITheme.vbox(0)
	copy.custom_minimum_size = Vector2(440, 0)
	var cm: = UITheme.margin(copy, 36, 30, 28, 28)
	cm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cm.size_flags_stretch_ratio = 0.72
	hero.add_child(cm)
	copy.add_child(UITheme.label("전략 자동 전투 시뮬레이터", "EyebrowLabel"))
	copy.add_child(UITheme.spacer(0, 8))
	copy.add_child(UITheme.label("전략을 고르고,", "DisplayLabel"))
	copy.add_child(UITheme.label("전투를 지켜봐.", "DisplayLabel", 0, UITheme.ACCENT))
	copy.add_child(UITheme.spacer(0, 12))
	copy.add_child(UITheme.wrap_label("팀을 직접 짜거나 AI와 번갈아 뽑아 보세요.\n전술가 AI는 자기 팀이 본 것만으로 적을 추론해 싸워요.", "DimLabel", UITheme.FS_BODY))
	copy.add_child(UITheme.spacer(0, 22))
	var cta: = UITheme.hbox(UITheme.SP2)
	var play: = UITheme.button("▶  빠른 관전", "PrimaryButton", _quick_match, "무작위 3대3 전투를 바로 시작해요. 전장과 영웅은 매번 새로 뽑혀요.")
	play.custom_minimum_size = Vector2(164, 44)
	cta.add_child(play)
	var codex: = UITheme.button("☰  전투 도감", "GhostButton", func(): _go("codex", {"mode": "chars"}), "캐릭터·아이템·용어·전장 정보를 살펴봐요.")
	codex.custom_minimum_size = Vector2(140, 44)
	cta.add_child(codex)
	copy.add_child(cta)
	copy.add_child(UITheme.expand(UITheme.spacer(0, 24), false, true))
	copy.add_child(_facts())

	var pv_wrap: = UITheme.vbox(0)
	preview = LivePreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.frame_color = HERO_BG
	preview.corner_radius = UITheme.R_M
	pv_wrap.add_child(preview)
	var pm: = UITheme.margin(pv_wrap, 0, 12, 12, 12)
	pm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_child(pm)
	return panel


## Hero, battlefield, item and mode counts come from the active catalogues.
func _facts() -> Control:
	var h: = UITheme.hbox(0)
	var facts: = [[DB.characters.size(), "캐릭터"], [_arena_total(), "전장"],
		[ItemDefs.ORDER.size(), "아이템"], [MODE_GLYPHS.size(), "모드"]]
	for i in facts.size():
		if i > 0:
			var sep: = UITheme.sep_line(true)
			sep.custom_minimum_size = Vector2(1, 18)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(UITheme.margin(sep, 16, 0, 16, 0))
		var f: = UITheme.hbox(6)
		var n: = UITheme.label(str(facts[i][0]), "NumberLabel")
		f.add_child(n)
		var l: = UITheme.label(str(facts[i][1]), "CaptionLabel")
		l.size_flags_vertical = Control.SIZE_SHRINK_END
		f.add_child(UITheme.margin(l, 0, 0, 0, 3))
		h.add_child(f)
	return h


## Every battlefield: the authored arenas plus the deathmatch and battleground presets.
static func _arena_total() -> int:
	return DB.arenas.size() + DeathmatchMapData.ORDER.size() + BattlegroundMapData.ORDER.size()


# ------------------------------------------------------------------ battleground feature

## Full-width V2 card under the mode grid: glyph, "NEW", the pitch, tags and the three maps
## (thumbnails from BattlegroundScreen's preview cache, filled in when their worker builds finish).
func _br_feature_card() -> Control:
	var col: Color = Color("#cf9bff")
	var h: HBoxContainer = UITheme.hbox(UITheme.SP5)
	var left: VBoxContainer = UITheme.vbox(UITheme.SP3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = UITheme.hbox(UITheme.SP3)
	top.add_child(UITheme.glyph_tile(MODE_GLYPHS.battleground, col, 44))
	var t: Label = UITheme.label("배틀그라운드", "HeadLabel")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(t)
	var nb: PanelContainer = UITheme.badge("NEW", UITheme.GOLD, "solid")
	nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(nb)
	var sp: Control = UITheme.spacer()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var go: Label = UITheme.label("→", "BoldLabel", 14, col.lightened(0.3))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(go)
	left.add_child(top)
	left.add_child(UITheme.wrap_label("최대 30명이 줄어드는 자기장 안에서 끝까지 살아남는 생존전이에요.\n듀오·트리오에서는 쓰러진 팀원을 소생하며, 중앙일수록 좋은 아이템이 기다려요.", "DimLabel", UITheme.FS_SM))
	var tags: HFlowContainer = HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	for tag in ["솔로·듀오·트리오", "최대 %d명" % BattlegroundMode.MAX_HEROES, "아이템 %d" % BattlegroundMode.ITEM_COUNT, "전장 %d종" % BattlegroundMapData.ORDER.size(), "자기장 %d단계" % BrZone.PHASES]:
		tags.add_child(UITheme.badge(str(tag), col))
	left.add_child(tags)
	h.add_child(left)
	var maps: HBoxContainer = UITheme.hbox(UITheme.SP2)
	maps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br_thumbs.clear()
	for id in BattlegroundMapData.ORDER:
		var th: MapThumb = MapThumb.new(str(id))
		maps.add_child(th)
		br_thumbs.append(th)
	h.add_child(maps)
	var card: HoverCard = HoverCard.new(h, go, "시작  →", Vector4(20, 18, 20, 18))
	card.tooltip_text = UITheme.tip("배틀그라운드 설정 화면을 엽니다. 형식·규모·자기장 속도와 참가자를 정한 뒤 시작해요.")
	card.pressed.connect(func():
		Sfx.play("click", 0.35)
		_go("battleground"))
	cards.append(card)
	return card


# Polls the preview cache while a thumbnail waits for its worker build (idle otherwise).
func _process(_delta: float) -> void:
	var waiting: bool = false
	if BattlegroundScreen.previews_pending():
		BattlegroundScreen.poll_previews()
	for th in br_thumbs:
		if not (th as MapThumb).refresh():
			waiting = true
	if not waiting:
		set_process(false)


# ------------------------------------------------------------------ sections

func _section(title: String, hint: String, body: Control) -> Control:
	var s: = UITheme.vbox(UITheme.SP3)
	s.add_child(UITheme.section_header(title, hint))
	s.add_child(body)
	return s


func _grid(cols: int) -> GridContainer:
	var g: = GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", UITheme.SP4)
	g.add_theme_constant_override("v_separation", UITheme.SP4)
	return g


## Adapts the card grids to the page width (runs on resize only).
func _reflow() -> void :
	if _page == null:
		return
	var w: = minf(_page.size.x, PAGE_MAX_W) - UITheme.PAGE_X * 2
	if modes_grid:
		modes_grid.columns = 4 if w >= 1080.0 else 2
	if notes_grid:
		notes_grid.columns = 4 if w >= 1500.0 else 2


## Play-mode card (CardButton): glyph tile + title, one-line description, badges and a hover
## "시작 →" affordance.
func _mode_card(glyph: String, title: String, desc: String, tags: Array, col: Color, cb: Callable) -> Control:
	var v: = UITheme.vbox(UITheme.SP3)
	var top: = UITheme.hbox(UITheme.SP3)
	top.add_child(UITheme.glyph_tile(glyph, col, 38))
	var t: = UITheme.label(title, "HeadLabel")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.ellipsize(t)
	top.add_child(t)
	var go: = UITheme.label("→", "BoldLabel", 14, col.lightened(0.3))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(go)
	v.add_child(top)
	v.add_child(UITheme.wrap_label(desc, "DimLabel", UITheme.FS_SM))
	v.add_child(UITheme.expand(Control.new(), false, true))
	var tags_h: = HFlowContainer.new()
	tags_h.add_theme_constant_override("h_separation", 6)
	tags_h.add_theme_constant_override("v_separation", 6)
	for tag in tags:
		tags_h.add_child(UITheme.badge(str(tag), col))
	v.add_child(tags_h)
	var card: = HoverCard.new(v, go, "시작  →", Vector4(20, 18, 20, 18))
	card.pressed.connect(func():
		Sfx.play("click", 0.35)
		cb.call())
	cards.append(card)
	return card


## Compact library link card: neutral glyph tile, title + caption, arrow.
func _link_card(glyph: String, title: String, caption: String, args: Dictionary) -> Control:
	var h: = UITheme.hbox(UITheme.SP3)
	h.add_child(UITheme.glyph_tile(glyph, Color("#6a7ea6"), 34))
	var tv: = UITheme.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UITheme.label(title, "BoldLabel"))
	tv.add_child(UITheme.ellipsize(UITheme.label(caption, "FaintLabel")))
	h.add_child(tv)
	var go: = UITheme.label("→", "BoldLabel", 14, UITheme.ACCENT_TEXT)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(go)
	var card: = HoverCard.new(h, go, "열기  →", Vector4(14, 12, 16, 12))
	card.pressed.connect(func():
		Sfx.play("click", 0.35)
		_go("codex", args))
	cards.append(card)
	return card


func _note_card(glyph: String, col: Color, title: String, body: String) -> Control:
	var h: = UITheme.hbox(UITheme.SP4)
	var tile: = UITheme.glyph_tile(glyph, col, 36)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tile)
	var tv: = UITheme.vbox(UITheme.SP1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UITheme.label(title, "SubheadLabel"))
	tv.add_child(_keep_all(UITheme.wrap_label(body, "DimLabel", UITheme.FS_SM)))
	h.add_child(tv)
	var p: = UITheme.panel("CardPanel", UITheme.margin(h, 6, 6, 6, 6))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


## Korean "keep-all" wrapping for a wrapped Label: Godot breaks Hangul between any two syllables, so
## the text is re-broken at spaces for the label's current width (on resize only). Autowrap stays on
## as a fallback while a narrower width has not been re-broken yet.
static func _keep_all(l: Label) -> Label:
	l.set_meta("keep_all_src", l.text)
	l.resized.connect(_rewrap.bind(l))
	return l


static func _rewrap(l: Label) -> void :
	var max_w: = l.size.x - 2.0
	if max_w <= 40.0:
		return
	var font: Font = l.get_theme_font("font")
	var px: = l.get_theme_font_size("font_size")
	var out: PackedStringArray = []
	for para in str(l.get_meta("keep_all_src", l.text)).split("\n"):
		var line: = ""
		for word in para.split(" ", false):
			var cand: = word if line == "" else line + " " + word
			if line != "" and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
				out.append(line)
				line = word
			else:
				line = cand
		out.append(line)
	var t: = "\n".join(out)
	if t != l.text:
		l.text = t


## Records: 3x2 stat tiles (AI 대전 승리/패배/승률, 현재/최고 연승, 관전한 전투). The section header hint
## doubles as the empty-state hint.
func _build_records() -> Control:
	var g: = _grid(3)
	g.add_theme_constant_override("h_separation", UITheme.SP3)
	g.add_theme_constant_override("v_separation", UITheme.SP3)
	for c in [["draft_wins", "AI 대전 승리", ""], ["draft_losses", "AI 대전 패배", ""], ["win_rate", "승률", "AI 대전 승리 ÷ (승리 + 패배)"],
			["streak", "현재 연승", "AI 대전에서 지금 이어 가고 있는 연승 수예요."], ["best_streak", "최고 연승", ""], ["battles", "관전한 전투", "끝까지 진행된 모든 전투 수예요."]]:
		var tile: = UITheme.stat_tile(str(c[1]), "0", UITheme.TEXT, str(c[2]))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size = Vector2(0, 58)
		var inner: = tile.get_child(0) as VBoxContainer
		if inner:
			inner.alignment = BoxContainer.ALIGNMENT_CENTER
		var n: Label = tile.get_meta("value")
		if c[0] == "win_rate":
			rate_label = n
		else:
			rec_labels[c[0]] = n
		g.add_child(tile)
	# On a card surface so the tiles sit on the same plane as the library cards beside them.
	return UITheme.panel("CardPanel", g)


# ------------------------------------------------------------------ actions

func _go(id: String, args: Dictionary = {}) -> void :
	if app:
		app.goto(id, args)


func _quick_match() -> void :
	var rng: = RandomNumberGenerator.new()
	rng.randomize()
	var ids: = DB.ids().duplicate()
	var blue: Array = []
	var red: Array = []
	for i in 3:
		blue.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
		red.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	var quick_arenas: Array = DB.arenas_for("elimination")
	var arena: Arena = quick_arenas[rng.randi_range(0, quick_arenas.size() - 1)]
	app.start_battle({"blue": blue, "red": red, "arena_id": arena.id, "seed": rng.randi_range(1, 99999999), "blue_ai": "tactician", "red_ai": "tactician", "mode": "composition"}, "home")


## args: {"section": "notes"} scrolls to the update notes (settings → 정보 → 업데이트 노트).
func on_show(args: Dictionary) -> void :
	var r: Dictionary = Settings.records
	var wins: = int(r.get("draft_wins", 0))
	var games: = wins + int(r.get("draft_losses", 0))
	var empty: = games == 0 and int(r.get("battles", 0)) == 0
	for k in rec_labels:
		var l: Label = rec_labels[k]
		var n: = int(r.get(k, 0))
		l.text = str(n)
		var col: Color = UITheme.TEXT
		if n == 0:
			col = UITheme.TEXT_FAINT
		elif k == "draft_wins" or k == "streak":
			col = UITheme.GOOD
		elif k == "best_streak":
			col = UITheme.GOLD
		l.add_theme_color_override("font_color", col)
	if rate_label:
		rate_label.text = ("%d%%" % roundi(100.0 * wins / games)) if games > 0 else "—"
		rate_label.add_theme_color_override("font_color", UITheme.ACCENT_TEXT if games > 0 else UITheme.TEXT_FAINT)
	if rec_header:
		var hl: Label = rec_header.get_meta("hint")
		hl.text = REC_EMPTY_HINT if empty else REC_HINT
		hl.add_theme_color_override("font_color", UITheme.ACCENT_TEXT if empty else UITheme.TEXT_FAINT)
	if preview:
		preview.set_active(true)
	for th in br_thumbs:
		(th as MapThumb).request()
	set_process(not br_thumbs.is_empty())
	if str(args.get("section", "")) == "notes":
		_scroll_to_notes()


func _scroll_to_notes() -> void :
	# Let the container sort that follows the visibility change settle, then jump to the notes.
	for i in 2:
		await get_tree().process_frame
	if scroll and notes and is_visible_in_tree():
		scroll.scroll_vertical = maxi(0, int(notes.global_position.y - _page.global_position.y) - UITheme.PAGE_TOP)


func on_hide() -> void :
	if preview:
		preview.set_active(false)
	for c in cards:
		(c as HoverCard).set_hot(false)


## Small battleground map thumbnail (preview cache raster, aspect kept) with the map name.
class MapThumb:
	extends Control
	const W := 132.0
	const H := 86.0
	var id: String = ""
	var texture: Texture2D

	func _init(map_id: String) -> void:
		id = map_id
		custom_minimum_size = Vector2(W, H + 20.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func request() -> void:
		if texture == null:
			BattlegroundScreen.preview(id, BattlegroundScreen.PREVIEW_SEED)

	## True once the texture is shown.
	func refresh() -> bool:
		if texture != null:
			return true
		var p: Dictionary = BattlegroundScreen.preview(id, BattlegroundScreen.PREVIEW_SEED)
		if p.is_empty():
			return false
		texture = p.get("texture")
		queue_redraw()
		return true

	func _draw() -> void:
		var area: = Rect2(0, 0, W, H)
		draw_style_box(UITheme.sbc(Color(0.02, 0.03, 0.05, 0.9), UITheme.LINE, UITheme.R_S, 1, 0, 0), area)
		if texture:
			var ts: Vector2 = Vector2(texture.get_size())
			var k: float = minf((W - 6.0) / ts.x, (H - 6.0) / ts.y)
			draw_texture_rect(texture, Rect2(area.get_center() - ts * k * 0.5, ts * k), false)
		var name: String = str((BattlegroundMapData.PRESETS.get(id, {}) as Dictionary).get("name", id))
		var f: Font = DB.font_bold
		var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2((W - w) * 0.5, H + 15.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)


## CardButton whose height follows its content; the trailing label switches between "→" and the
## hover text ("시작 →") on hover (event driven, no per-frame work).
class HoverCard:
	extends Button
	var body: MarginContainer
	var arrow: Label
	var hot_text: String
	var idle_text: String

	func _init(content: Control, arrow_label: Label, hover_text: String, pad: Vector4) -> void :
		theme_type_variation = "CardButton"
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arrow = arrow_label
		idle_text = arrow_label.text
		hot_text = hover_text
		body = UITheme.margin(content, int(pad.x), int(pad.y), int(pad.z), int(pad.w))
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(body)
		_ignore_mouse(body)
		arrow.modulate = Color(1, 1, 1, 0.55)
		body.minimum_size_changed.connect(_sync_height)
		mouse_entered.connect(set_hot.bind(true))
		mouse_exited.connect(set_hot.bind(false))

	func _ready() -> void :
		_sync_height()

	func _sync_height() -> void :
		var h: = body.get_combined_minimum_size().y
		if absf(custom_minimum_size.y - h) > 0.5:
			custom_minimum_size.y = h

	func set_hot(on: bool) -> void :
		if arrow == null:
			return
		arrow.text = hot_text if on else idle_text
		arrow.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)

	static func _ignore_mouse(n: Node) -> void :
		if n is Control:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for c in n.get_children():
			_ignore_mouse(c)
