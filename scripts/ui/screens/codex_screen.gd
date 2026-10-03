class_name CodexScreen
extends Control
## 전투 도감 (V1.5.1). One page header with a segmented mode switch and four views:
##   chars     roster list (search + role filter) · CharDetail · SkillPreview (the only live simulation)
##   arenas    all 21 battlefields grouped 섬멸전 / 거점 장악 / 개인전 / 배틀그라운드 with hazards,
##             rules and notes (battleground previews are built on worker threads, cards added when ready)
##   items     deathmatch / battleground item compendium (rarity filter + search, ItemViews detail,
##             item rules, battleground ring odds)
##   glossary  status / rule terms by category with related heroes and items
## Views other than chars are built the first time their mode is shown; nothing is rebuilt per frame.
## Test contract: preview, detail, _select_character(id, entry), _mode(id), on_show(args), on_hide(),
## current_mode, current_character. _mode() always calls preview.set_active(screen_active and id == "chars"),
## so every other mode keeps the preview detached (no scenario, no sim on view/runner).


const MODES: = ["chars", "arenas", "items", "glossary"]
const LIST_W: = 284
const DETAIL_MIN_W: = 372
const ITEM_LIST_W: = 348
const RULES_MIN_W: = 330
const THUMB_W_ONE: = 380
const THUMB_W_TWO: = 316
const ARENA_TWO_COL_W: = 1700.0
const ITEM_RULES_SIDE_W: = 1200.0
const TERM_CARD_W: = 410.0
const HERO_DISC: = 26.0
const TERRAIN_LABELS: = {"wall": "벽", "pillar": "기둥", "ruin": "잔해", "lattice": "격자벽", "island": "중앙섬", "slab": "석판", "hedge": "산울타리", "tree": "나무 줄기"}
const ROLE_FILTERS: =[["", "전체"], ["FRONTLINE", "전방"], ["DAMAGE", "공격"], ["CONTROL", "제어"], ["SUPPORT", "지원"]]
const MODE_TIPS: = {
	"chars": "영웅의 능력치·스킬·교리를 보고 스킬을 시연합니다.",
	"arenas": "전장의 지형·환경 효과·규칙을 확인합니다.",
	"items": "데스매치·배틀그라운드 아이템의 효과와 숨은 규칙을 확인합니다.",
	"glossary": "스킬 설명에 나오는 상태 이상과 전투 규칙 용어를 찾아봅니다.",
}
const CATEGORY_HINTS: = {
	"군중 제어": "행동을 막거나 강제로 움직이게 하는 효과",
	"해로운 효과": "대상을 약하게 만드는 효과",
	"이로운 효과": "자신이나 아군을 보호하고 강화하는 효과",
	"표식·자원": "스킬 조건이 되는 표식과 누적 수치",
	"피해·규칙": "피해 종류와 전투 공통 규칙",
}
const GROUP_HINTS: = {
	"elimination": "상대 팀을 모두 쓰러뜨리면 승리합니다. 일부 전장에는 환경 효과가 있습니다.",
	"control": "거점 A·B·C를 점령해 300점을 먼저 모으면 승리합니다. 쓰러져도 다시 출전합니다.",
	"deathmatch": "최대 12명이 각자 싸우는 데스매치 전장입니다. 시드마다 배치가 달라집니다.",
	"battleground": "최대 30명이 줄어드는 자기장 안에서 끝까지 살아남는 배틀그라운드 전장입니다. 표준 전장의 약 30배 넓이이며 시드마다 배치가 달라집니다.",
}

var app: App
var detail: CharDetail
var preview: SkillPreview
var list_box: VBoxContainer
var arena_box: VBoxContainer
## [[mode id, Button], ...] (segmented mode buttons).
var mode_btns: Array = []
var mode_seg: HBoxContainer
var header: HBoxContainer
var char_view: Control
var arena_view: Control
var item_view: Control
var glossary_view: Control
var current_character: String = "swordsman"
var current_mode: String = "chars"
var current_item: String = ""
var screen_active: bool = false

# chars
var roster_cards: Dictionary = {}
var role_filter: String = ""
var char_search: LineEdit
var role_seg: HBoxContainer
var char_scroll: ScrollContainer
var char_empty: Control

# arenas
## arena id -> ArenaCard thumbnail (deathmatch maps are keyed by their preset id).
var arena_cards: Dictionary = {}
## arena id -> the arena's info card (PanelContainer).
var arena_panels: Dictionary = {}
var arena_scroll: ScrollContainer
var arena_jump: HBoxContainer
var _arena_sections: Array = []
var _arena_grids: Array = []
var _arena_rule_grids: Array = []
var _arena_thumb_cols: Array = []
var _arena_cols: int = 0
var _dm_pending: Array = []
var _dm_grid: GridContainer
var _dm_loading: Control
## Battleground maps whose preview (worker build) is not ready yet; their cards are added on arrival.
var _br_pending: Array = []
var _br_grid: GridContainer
var _br_loading: Control
var _pending_focus: String = ""

# items
var item_list: Control
var item_search: LineEdit
var rarity_seg: HBoxContainer
var rarity_filter: int = -1
var item_scroll: ScrollContainer
var item_list_scroll: ScrollContainer
var item_empty: Control
var item_detail_host: VBoxContainer
var rules_card: Control
var _rules_side: ScrollContainer
var _rules_below: VBoxContainer
var _rules_wide: int = -1

# glossary
## glossary key -> term card (PanelContainer).
var term_cards: Dictionary = {}
var glossary_search: LineEdit
var category_seg: HBoxContainer
var category_filter: String = ""
var glossary_scroll: ScrollContainer
var glossary_empty: Control
var _term_sections: Dictionary = {}
var _term_grids: Array = []
var _term_cols: int = 0
var _item_terms: Dictionary = {}

var _root: VBoxContainer
var _views: Dictionary = {}
var _highlight: PanelContainer
var _highlight_style: StyleBox
## ScrollContainer -> [Control, frames left, align top] (see _reveal_later()).
var _reveals: Dictionary = {}

static var _search_tex: Texture2D


func bind(a: App) -> void :
	app = a


func _ready() -> void :
	set_process(false)
	DB.ensure_loaded()
	_root = UITheme.vbox(UITheme.SP4)
	var mm: = UITheme.page_margin(_root)
	mm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mm)
	var opts: Array = [
		["chars", "캐릭터 %d" % DB.characters.size(), MODE_TIPS.chars],
		["arenas", "전장 %d" % _arena_total(), MODE_TIPS.arenas],
		["items", "아이템 %d" % ItemDefs.ORDER.size(), MODE_TIPS.items],
		["glossary", "용어 %d" % CodexData.STATUS.size(), MODE_TIPS.glossary]]
	mode_seg = UITheme.segmented(opts, "chars", func(id: Variant) -> void: _mode(str(id)), 104)
	var buttons: Dictionary = mode_seg.get_meta("buttons")
	for id in MODES:
		mode_btns.append([id, buttons[id]])
	header = UITheme.page_header("COMPENDIUM", "전투 도감", _subtitle("chars"), [mode_seg])
	_root.add_child(header)
	char_view = _build_chars()
	_views["chars"] = char_view
	_root.add_child(char_view)
	_select_character(DB.characters[0].id)
	_mode("chars")


# ================================================================== modes

func _subtitle(id: String) -> String:
	match id:
		"arenas":
			return "전장 %d곳의 지형, 환경 효과의 정확한 수치, 모드 규칙과 전술 메모를 정리했습니다." % _arena_total()
		"items":
			return "데스매치·배틀그라운드 필드 아이템 %d종의 효과와 숨은 규칙, 잘 맞는 영웅을 확인할 수 있습니다." % ItemDefs.ORDER.size()
		"glossary":
			return "스킬 설명에 나오는 용어 %d개를 분류별로 정리했습니다. 영웅을 누르면 캐릭터 도감으로 이동합니다." % CodexData.STATUS.size()
	return "영웅 %d명의 능력치·스킬·교리를 볼 수 있습니다. 스킬의 ▶를 누르면 오른쪽에서 실제 규칙으로 시연합니다." % DB.characters.size()


## Every battlefield: authored arenas plus the deathmatch and battleground presets.
static func _arena_total() -> int:
	return DB.arenas.size() + DeathmatchMapData.ORDER.size() + BattlegroundMapData.ORDER.size()


func _mode(id: String) -> void :
	if not id in MODES:
		id = "chars"
	current_mode = id
	preview.set_active(screen_active and id == "chars")
	_ensure_view(id)
	for key in _views:
		(_views[key] as Control).visible = key == id
	UITheme.segmented_select(mode_seg, id)
	var sub: Label = header.get_meta("subtitle")
	sub.text = _subtitle(id)
	sub.visible = true


func _ensure_view(id: String) -> void :
	if _views.has(id):
		return
	var v: Control
	match id:
		"arenas":
			arena_view = _build_arenas()
			v = arena_view
		"items":
			item_view = _build_items()
			v = item_view
		"glossary":
			glossary_view = _build_glossary()
			v = glossary_view
		_:
			return
	_views[id] = v
	_root.add_child(v)


func on_show(args: Dictionary) -> void:
	screen_active = true
	var mode: String = str(args.get("mode", ""))
	var target: String = str(args.get("item", ""))
	if str(args.get("character", "")) != "":
		mode = "chars"
		_select_character(str(args.character), str(args.get("entry", "")))
		_reveal_later(char_scroll, roster_cards.get(current_character))
	elif mode == "" and target != "" and ItemDefs.DEFS.has(target):
		mode = "items"
	if not mode in MODES:
		mode = current_mode
	_mode(mode)
	if target == "":
		return
	match mode:
		"items":
			_select_item(target)
		"arenas":
			_focus_arena(target)
		"glossary":
			_focus_term(target)


func on_hide() -> void:
	screen_active = false
	preview.set_active(false)


# ================================================================== shared helpers

## Magnifier icon for search boxes (generated once, 16 px logical at 2x).
static func _search_icon() -> Texture2D:
	if _search_tex:
		return _search_tex
	var ss: = 2
	var img: = Image.create_empty(16 * ss, 16 * ss, false, Image.FORMAT_RGBA8)
	var col: = UITheme.TEXT_FAINT
	for y in 16 * ss:
		for x in 16 * ss:
			var p: = Vector2((x + 0.5) / ss, (y + 0.5) / ss)
			var ring: = absf(p.distance_to(Vector2(6.8, 6.8)) - 4.4) - 0.75
			var ab: = Vector2(10.2, 10.2)
			var bb: = Vector2(13.6, 13.6)
			var t: = clampf((p - ab).dot(bb - ab) / (bb - ab).length_squared(), 0.0, 1.0)
			var handle: = p.distance_to(ab + (bb - ab) * t) - 0.95
			var cov: = clampf(0.5 - minf(ring, handle) * ss, 0.0, 1.0)
			img.set_pixel(x, y, Color(col, cov))
	var tex: = ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(16, 16))
	_search_tex = tex
	return tex


func _search_box(placeholder: String, cb: Callable) -> LineEdit:
	var e: = LineEdit.new()
	e.placeholder_text = placeholder
	e.clear_button_enabled = true
	e.right_icon = _search_icon()
	e.custom_minimum_size = Vector2(0, 36)
	e.text_changed.connect(func(_t: String) -> void: cb.call())
	return e


## Makes a segmented() control fill its row with equal-width segments.
func _stretch_segmented(seg: HBoxContainer) -> void:
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(seg.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buttons: Dictionary = seg.get_meta("buttons")
	for k in buttons:
		(buttons[k] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Opaque sunken surface for a scrolling list (keeps the backdrop from showing between rows).
func _well(child: Control) -> PanelContainer:
	var w: = UITheme.styled_panel(UITheme.sbc(UITheme.PANEL, UITheme.LINE, UITheme.R_L, 1, 8, 8), child)
	w.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return w


func _empty(title: String, hint: String) -> Control:
	var e: = UITheme.empty_state("◌", title, hint)
	e.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if e.get_child_count() > 2:
		(e.get_child(2) as Control).custom_minimum_size.x = 220
	e.visible = false
	return e


## Small tracked caption heading inside a card ("환경 효과", "전술 메모").
func _mini_head(text: String) -> Label:
	return UITheme.label(text, "EyebrowLabel", 0, UITheme.TEXT_FAINT)


func _bullet(text: String, color: Color) -> Control:
	var h: = UITheme.hbox(10)
	var dot: = ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(5, 5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dw: = UITheme.margin(dot, 1, 8, 0, 0)
	dw.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dw)
	h.add_child(UITheme.wrap_label(text, "DimLabel", 14))
	return h


## Icon tile + bold title (+ count badge) over a dim explanation line. tip -> tooltip.
func _fact_row(icon: String, color: Color, title: String, count: String, text: String, tip: String = "") -> Control:
	var h: = UITheme.hbox(UITheme.SP3)
	var g: = UITheme.glyph_tile(icon, color, 30)
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(g)
	var tv: = UITheme.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr: = UITheme.hbox(6)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl: = UITheme.label(title, "BoldLabel", 14)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(tl)
	if count != "":
		var b: = UITheme.badge(count, color, "soft")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.add_child(b)
	tv.add_child(tr)
	var dl: = UITheme.wrap_label(text, "DimLabel", 13)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(dl)
	h.add_child(tv)
	if tip != "":
		h.tooltip_text = UITheme.tip(tip)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


## Flat circular button around a GlyphDisc; opens that hero in chars mode.
func _hero_button(hid: String, px: float = HERO_DISC) -> Button:
	var d: Defs.CharDef = DB.char_def(hid)
	var b: = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(px + 4.0, px + 4.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var idle: = UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0)
	var hot: = UITheme.sbc(Color(UITheme.ACCENT, 0.16), UITheme.ACCENT, UITheme.R_PILL, 1, 0, 0)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("disabled", idle)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("hover_pressed", hot)
	b.add_theme_stylebox_override("focus", UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_PILL, 0, 0, 0))
	b.tooltip_text = "%s · %s\n누르면 캐릭터 도감에서 봅니다." % [d.name, DB.role_label(d.role)]
	var disc: = GlyphDisc.new(d, px)
	disc.position = Vector2(2, 2)
	disc.size = Vector2(px, px)
	b.add_child(disc)
	b.set_meta("hero_id", hid)
	b.pressed.connect(func() -> void: _open_hero(hid))
	return b


func _item_button(iid: String, px: int = 26) -> Button:
	var b: = Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(px + 4, px + 4)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var idle: = UITheme.sbc(UITheme.CLEAR, UITheme.CLEAR, UITheme.R_S, 0, 0, 0)
	var hot: = UITheme.sbc(Color(UITheme.ACCENT, 0.16), UITheme.ACCENT, UITheme.R_S, 1, 0, 0)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("disabled", idle)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("hover_pressed", hot)
	b.add_theme_stylebox_override("focus", idle)
	b.tooltip_text = ItemViews.tooltip_text(iid) + "\n누르면 아이템 도감에서 봅니다."
	var t: = UITheme.item_tile(iid, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.tooltip_text = ""
	t.position = Vector2(2, 2)
	t.size = Vector2(px, px)
	b.add_child(t)
	b.set_meta("item_id", iid)
	b.pressed.connect(func() -> void: _open_item(iid))
	return b


func _open_hero(hid: String) -> void:
	if DB.char_def(hid) == null:
		return
	var rc: RosterCard = roster_cards.get(hid)
	if rc and not rc.visible:
		char_search.text = ""
		role_filter = ""
		UITheme.segmented_select(role_seg, "")
		_filter_roster()
	_select_character(hid)
	_mode("chars")
	_reveal_later(char_scroll, rc)


func _open_item(iid: String) -> void:
	if not ItemDefs.DEFS.has(iid):
		return
	_mode("items")
	_select_item(iid)


## Scrolls c into view now: ensure-visible, or align its top with the viewport (deep links).
func _reveal(sc: ScrollContainer, c: Control, top: bool = false) -> void:
	if not (is_instance_valid(sc) and is_instance_valid(c) and c.is_visible_in_tree() and sc.is_visible_in_tree()):
		return
	if top:
		var offset: float = c.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical
		sc.scroll_vertical = maxi(0, int(offset) - 4)
	else:
		sc.ensure_control_visible(c)


## Scrolls c into view once the containers have laid out (two frames later). Uses a short-lived
## _process instead of coroutines so nothing resumes on a freed screen.
func _reveal_later(sc: ScrollContainer, c: Control, top: bool = false) -> void:
	if sc == null or c == null:
		return
	_reveals[sc] = [c, 2, top]
	set_process(true)


func _process(_delta: float) -> void:
	if not _dm_pending.is_empty():
		_build_next_dm_card()
	if not _br_pending.is_empty():
		_build_ready_br_cards()
	if _reveals.is_empty():
		if _dm_pending.is_empty() and _br_pending.is_empty():
			set_process(false)
		return
	for sc in _reveals.keys():
		var e: Array = _reveals[sc]
		e[1] = int(e[1]) - 1
		if int(e[1]) > 0:
			continue
		_reveals.erase(sc)
		if is_instance_valid(sc) and is_instance_valid(e[0]):
			_reveal(sc, e[0], bool(e[2]))
	if _reveals.is_empty() and _dm_pending.is_empty() and _br_pending.is_empty():
		set_process(false)


## Accent outline on one card (arena / term) opened through a deep link; the previous one is restored.
func _set_highlight(p: PanelContainer, color: Color, pad_h: int, pad_v: int) -> void:
	if is_instance_valid(_highlight) and _highlight_style:
		_highlight.add_theme_stylebox_override("panel", _highlight_style)
	_highlight = p
	if p == null:
		return
	_highlight_style = p.get_theme_stylebox("panel")
	p.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.PANEL2.lerp(color, 0.07), color, UITheme.R_L, 1, pad_h, pad_v))


# ================================================================== chars

func _build_chars() -> Control:
	var h: = UITheme.hbox(UITheme.SP4)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left: = UITheme.vbox(UITheme.SP2)
	left.custom_minimum_size = Vector2(LIST_W, 0)
	char_search = _search_box("이름·역할·특성으로 찾기", _filter_roster)
	left.add_child(char_search)
	role_seg = UITheme.segmented(ROLE_FILTERS, "", func(id: Variant) -> void:
		role_filter = str(id)
		_filter_roster())
	_stretch_segmented(role_seg)
	var rb: Dictionary = role_seg.get_meta("buttons")
	for r in ROLE_FILTERS:
		if str(r[0]) != "":
			(rb[r[0]] as Button).tooltip_text = "%s 역할 영웅만 봅니다." % str(r[1])
	left.add_child(UITheme.margin(role_seg, 0, 0, 0, 4))
	var wv: = UITheme.vbox(0)
	left.add_child(_well(wv))
	list_box = UITheme.vbox(6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_scroll = UITheme.scroll(UITheme.margin(list_box, 0, 0, 2, 0))
	wv.add_child(char_scroll)
	char_empty = _empty("찾는 영웅이 없습니다", "검색어를 지우거나 다른 역할을 고르면 다시 표시됩니다.")
	wv.add_child(char_empty)
	var group: = ButtonGroup.new()
	for c in DB.characters:
		var d: Defs.CharDef = c
		var rc: = RosterCard.new(d)
		rc.custom_minimum_size = Vector2(0, 62)
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rc.toggle_mode = true
		rc.button_group = group
		var cid: String = d.id
		rc.pressed.connect(func() -> void: _select_character(cid))
		list_box.add_child(rc)
		roster_cards[cid] = rc
	h.add_child(left)

	detail = CharDetail.new()
	detail.preview_enabled = true
	detail.skill_requested.connect(func(kind, index): preview.select_entry("%s:%d" % [kind, index]))
	var dp: = UITheme.panel("CardPanel", detail)
	dp.custom_minimum_size = Vector2(DETAIL_MIN_W, 0)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.size_flags_stretch_ratio = 0.42
	h.add_child(dp)

	# The preview's parent must stay a bounded-height ScrollContainer (preview_ui_14 layout contract):
	# SkillPreview sizes its 16:9 canvas from get_parent().size.y.
	preview = SkillPreview.new()
	preview.entry_selected.connect(func(kind, index): detail.set_selected_skill(kind, index))
	var preview_scroll: = ScrollContainer.new()
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview)
	h.add_child(preview_scroll)
	return h


func _filter_roster() -> void:
	var q: String = char_search.text.strip_edges().to_lower()
	var shown: int = 0
	for id in roster_cards:
		var rc: RosterCard = roster_cards[id]
		var d: Defs.CharDef = rc.def
		var ok: bool = role_filter == "" or d.role == role_filter
		if ok and q != "":
			var tags: Array = Array(d.tags).map(func(x): return DB.tag_label(str(x)))
			var hay: String = "%s %s %s %s %s" % [d.name, DB.role_label(d.role), " ".join(tags), d.id, str(d.behavior.get("label", ""))]
			ok = hay.to_lower().contains(q)
		rc.visible = ok
		if ok:
			shown += 1
	char_scroll.visible = shown > 0
	char_empty.visible = shown == 0


func _select_character(id: String, entry: String = "") -> void:
	if DB.char_def(id) == null:
		return
	current_character = id
	for key in roster_cards:
		(roster_cards[key] as RosterCard).set_pressed_no_signal(key == id)
	detail.show_def(DB.char_def(id))
	preview.select_character(id, entry)
	var selected: Dictionary = preview._selected_entry()
	if not selected.is_empty():
		detail.set_selected_skill(str(selected.kind), int(selected.index))


# ================================================================== arenas

func _build_arenas() -> Control:
	var v: = UITheme.vbox(UITheme.SP3)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Deathmatch maps are generated (with a navigation check, ~0.2 s each) the first time they are
	# needed: already-cached previews are used at once, the rest are added one per frame (_process).
	var dm_ready: Array = []
	_dm_pending.clear()
	for id in DeathmatchMapData.ORDER:
		if DB.dm_previews.has(id) and _dm_pending.is_empty():
			dm_ready.append(DB.deathmatch_preview(str(id)))
		else:
			_dm_pending.append(str(id))
	# Battleground maps (~30x the standard area) are generated on worker threads (BattlegroundScreen's
	# preview cache); ready ones are used at once, the rest are added by _process when they arrive.
	var br_ready: Array = []
	_br_pending.clear()
	for id in BattlegroundMapData.ORDER:
		var pv: Dictionary = BattlegroundScreen.preview(str(id), BattlegroundScreen.PREVIEW_SEED)
		if not pv.is_empty() and _br_pending.is_empty():
			br_ready.append(pv.arena)
		else:
			_br_pending.append(str(id))
	var groups: Array = [
		["elimination", DB.arenas_for("elimination")],
		["control", DB.arenas_for("control")],
		["deathmatch", dm_ready],
		["battleground", br_ready]]
	var counts: Dictionary = {"deathmatch": DeathmatchMapData.ORDER.size(), "battleground": BattlegroundMapData.ORDER.size()}
	var opts: Array = []
	for g in groups:
		var n: int = int(counts.get(g[0], (g[1] as Array).size()))
		opts.append([g[0], "%s %d" % [CodexData.arena_kind_label(str(g[0])), n], str(GROUP_HINTS.get(g[0], ""))])
	arena_jump = UITheme.segmented(opts, "elimination", _jump_arena_group, 112)
	var bar: = UITheme.hbox(UITheme.SP3)
	bar.add_child(arena_jump)
	var hint: = UITheme.ellipsize(UITheme.label("지도에 색으로 표시된 영역이 환경 효과입니다. 항목에 마우스를 올리면 자세한 규칙을 볼 수 있습니다.", "FaintLabel"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(hint)
	v.add_child(bar)
	arena_box = UITheme.vbox(UITheme.SP6)
	arena_scroll = UITheme.scroll(UITheme.margin(arena_box, 0, 4, 6, 8))
	for g in groups:
		var sec: = _arena_group(str(g[0]), g[1], int(counts.get(g[0], (g[1] as Array).size())))
		arena_box.add_child(sec)
		_arena_sections.append([str(g[0]), sec])
	if not _dm_pending.is_empty():
		_dm_loading = UITheme.hint_label("개인전 전장 지도를 준비하고 있습니다.")
		_dm_grid.get_parent().add_child(_dm_loading)
		set_process(true)
	if not _br_pending.is_empty():
		_br_loading = UITheme.hint_label("배틀그라운드 전장 지도를 만들고 있습니다.")
		_br_grid.get_parent().add_child(_br_loading)
		set_process(true)
	arena_scroll.get_v_scroll_bar().value_changed.connect(_on_arena_scrolled)
	v.add_child(arena_scroll)
	arena_scroll.resized.connect(_relayout_arenas)
	return v


## Adds the battleground cards whose preview finished (in map order; called from _process).
func _build_ready_br_cards() -> void:
	if BattlegroundScreen.previews_pending():
		BattlegroundScreen.poll_previews()
	while not _br_pending.is_empty():
		var pv: Dictionary = BattlegroundScreen.preview(str(_br_pending[0]), BattlegroundScreen.PREVIEW_SEED)
		if pv.is_empty():
			return
		_br_pending.pop_front()
		_br_grid.add_child(_arena_card(pv.arena, "battleground"))
	if is_instance_valid(_br_loading):
		_br_loading.queue_free()
	_br_loading = null
	if _pending_focus != "" and _dm_pending.is_empty():
		var f: String = _pending_focus
		_pending_focus = ""
		_focus_arena(f)


## Builds one pending deathmatch preview card (called from _process, one per frame).
func _build_next_dm_card() -> void:
	var id: String = str(_dm_pending.pop_front())
	_dm_grid.add_child(_arena_card(DB.deathmatch_preview(id), "deathmatch"))
	if not _dm_pending.is_empty():
		return
	if is_instance_valid(_dm_loading):
		_dm_loading.queue_free()
	_dm_loading = null
	if _pending_focus != "" and _br_pending.is_empty():
		var f: String = _pending_focus
		_pending_focus = ""
		_focus_arena(f)


func _arena_group(kind: String, list: Array, total: int) -> Control:
	var sec: = UITheme.vbox(UITheme.SP3)
	var count: = UITheme.badge("%d곳" % total, UITheme.TEXT_DIM, "outline")
	sec.add_child(UITheme.section_header(CodexData.arena_kind_label(kind), str(GROUP_HINTS.get(kind, "")), count))
	var rules: Array = []
	match kind:
		"elimination":
			rules = [CodexData.HAZARD_RULE, {"title": str(CodexData.COVER.label), "text": str(CodexData.COVER.desc)}]
		"control":
			rules = CodexData.CONTROL_RULES
		"deathmatch":
			rules = CodexData.DM_MAP_RULES
		"battleground":
			rules = CodexData.BR_MAP_RULES
	if not rules.is_empty():
		sec.add_child(_rules_panel(rules, kind))
	var grid: = GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", UITheme.SP4)
	grid.add_theme_constant_override("v_separation", UITheme.SP4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in list:
		grid.add_child(_arena_card(a, kind))
	sec.add_child(grid)
	_arena_grids.append(grid)
	if kind == "deathmatch":
		_dm_grid = grid
	elif kind == "battleground":
		_br_grid = grid
	return sec


## Shared rules of one arena group as a compact grid of "title / text" cells.
func _rules_panel(rules: Array, kind: String) -> Control:
	var grid: = GridContainer.new()
	grid.columns = 2 if rules.size() <= 2 else 3
	grid.add_theme_constant_override("h_separation", UITheme.SP5)
	grid.add_theme_constant_override("v_separation", UITheme.SP3)
	grid.set_meta("n", rules.size())
	for r in rules:
		var cell: = UITheme.vbox(2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: = UITheme.hbox(6)
		var bar: = ColorRect.new()
		bar.color = Color(UITheme.ACCENT, 0.7)
		bar.custom_minimum_size = Vector2(2, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(bar)
		t.add_child(UITheme.label(str(r.title), "BoldLabel", 14))
		cell.add_child(t)
		cell.add_child(UITheme.wrap_label(str(r.text), "CaptionLabel", 13))
		grid.add_child(cell)
	_arena_rule_grids.append(grid)
	var v: = UITheme.vbox(UITheme.SP2)
	v.add_child(_mini_head({"elimination": "공통 규칙 · 환경", "control": "공통 규칙 · 거점 장악", "deathmatch": "공통 규칙 · 개인전 전장",
		"battleground": "공통 규칙 · 배틀그라운드"}.get(kind, "공통 규칙")))
	v.add_child(grid)
	return UITheme.styled_panel(UITheme.sbc(UITheme.PANEL, UITheme.LINE, UITheme.R_L, 1, 16, 12), v)


func _arena_card(a: Arena, kind: String) -> Control:
	var accent: Color = a.accent
	var key: String = str(a.data.get("preset", a.id)) if kind in ["deathmatch", "battleground"] else a.id
	var card: = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_L, 1, 16, 16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("arena_id", key)
	var row: = UITheme.hbox(UITheme.SP5)
	card.add_child(row)

	# Thumbnail + keyword badges.
	var tw: int = THUMB_W_TWO if _arena_cols == 2 else THUMB_W_ONE
	var tcol: = UITheme.vbox(UITheme.SP3)
	tcol.custom_minimum_size = Vector2(tw, 0)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var thumb: = ArenaCard.new(a)
	thumb.caption = false
	thumb.disabled = true
	thumb.tooltip_text = ""
	thumb.custom_minimum_size = Vector2(tw, 0)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tcol.add_child(thumb)
	var facts: = HFlowContainer.new()
	facts.add_theme_constant_override("h_separation", 6)
	facts.add_theme_constant_override("v_separation", 6)
	for f in _arena_facts(a, kind):
		facts.add_child(UITheme.badge(str(f[0]), UITheme.TEXT_DIM, "outline", str(f[1])))
	tcol.add_child(facts)
	row.add_child(tcol)
	arena_cards[key] = thumb
	arena_panels[key] = card
	_arena_thumb_cols.append(tcol)

	# Name + 유형, subtitle, description, effects, notes.
	var info: = UITheme.vbox(UITheme.SP4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head: = UITheme.vbox(6)
	var top: = UITheme.hbox(UITheme.SP2)
	top.add_child(UITheme.label(a.name, "HeadLabel"))
	var type_badge: = UITheme.badge("%s · %s" % [CodexData.ARENA_TYPE_CAPTION, str(a.data.get("difficulty", CodexData.arena_kind_label(kind)))], accent, "soft",
		"전장의 성격을 나타내는 분류입니다. 난이도가 아닙니다.")
	type_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(type_badge)
	head.add_child(top)
	var st: = str(a.data.get("subtitle", ""))
	if st != "":
		head.add_child(UITheme.label(st, "CaptionLabel", 0, accent.lerp(UITheme.TEXT, 0.3)))
	head.add_child(UITheme.wrap_label(str(a.data.get("description", "")), "BodyLabel", 14, UITheme.TEXT_DIM.lerp(UITheme.TEXT, 0.35)))
	info.add_child(head)

	# Effect rows flow two per line on wide cards; notes sit beside them when there is room.
	var body: = HFlowContainer.new()
	body.add_theme_constant_override("h_separation", UITheme.SP5)
	body.add_theme_constant_override("v_separation", UITheme.SP4)
	var notes: Array = _tactical_notes(a, kind)
	var eff: = UITheme.vbox(UITheme.SP2)
	eff.custom_minimum_size.x = 340
	eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows: Array = []
	match kind:
		"control":
			eff.add_child(_mini_head("거점 · 지형"))
			rows = _control_rows(a)
		"deathmatch":
			eff.add_child(_mini_head("지형 · 시야"))
			rows = _dm_rows(a)
		"battleground":
			eff.add_child(_mini_head("지형 · 아이템 · 환경"))
			rows = _br_rows(a)
		_:
			eff.add_child(_mini_head("환경 효과 · 지형"))
			rows = _hazard_rows(a)
	var flow: = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITheme.SP5)
	flow.add_theme_constant_override("v_separation", UITheme.SP3)
	for r in rows:
		var rc: Control = r
		rc.custom_minimum_size.x = 320
		rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_child(rc)
	eff.add_child(flow)
	body.add_child(eff)
	if not notes.is_empty():
		var nv: = UITheme.vbox(UITheme.SP2)
		nv.custom_minimum_size.x = 320
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(_mini_head("전술 메모"))
		for n in notes:
			nv.add_child(_bullet(str(n), accent))
		body.add_child(nv)
	info.add_child(body)
	row.add_child(info)
	return card


## [[badge text, tooltip], ...] under the thumbnail: the arena's keyword tags plus size facts.
func _arena_facts(a: Arena, kind: String) -> Array:
	var out: Array = []
	var ratio: float = a.width * a.height / (Arena.WIDTH * Arena.HEIGHT)
	if kind == "deathmatch" or kind == "battleground":
		for t in a.data.get("tags", []):
			out.append([str(t), ""])
		out.append(["%s×%s" % [CodexData.num(a.width), CodexData.num(a.height)], "전장 크기입니다. 기본 전장(1408×792)의 약 %s배 넓이입니다." % CodexData.num(snappedf(ratio, 0.1))])
		out.append(["예시 배치", "시드마다 배치가 달라집니다. 지도와 수치는 도감용 예시 시드 기준입니다."])
		return out
	# Layout facts first (size, spawn orientation, symmetry, structure), then the keyword tags.
	for f in CodexData.arena_layout_facts(a):
		out.append(f)
	for t in a.data.get("tags", []):
		var tag: String = str(t)
		if tag.ends_with("출발") or tag.begins_with("면적"):
			continue
		out.append([tag, ""])
	return out


## Solid terrain (blocks movement, projectiles and sight) summarised by kind: "벽 2 · 기둥 4".
func _terrain_row(a: Arena) -> Control:
	var counts: Dictionary = {}
	var order: Array = []
	var total: int = 0
	for o in a.obstacles:
		var od: Dictionary = o
		# Body-only terrain and timed gates have their own rows.
		if od.get("blocksVision", true) == false or od.has("gate"):
			continue
		var k: String = str(TERRAIN_LABELS.get(str(od.get("kind", "wall")), "벽"))
		if not counts.has(k):
			counts[k] = 0
			order.append(k)
		counts[k] = int(counts[k]) + 1
		total += 1
	if total == 0:
		# Only see-through cover (hedges) -> the cover row already describes the terrain.
		if not a.obstacles.is_empty():
			return null
		return _fact_row("◌", UITheme.TEXT_FAINT, "장애물 없음", "", "벽이나 기둥이 없는 열린 전장입니다.")
	var parts: Array = []
	for k in order:
		parts.append("%s %d" % [k, int(counts[k])])
	return _fact_row("▣", Color("#8fa3c4"), "지형 장애물", "×%d" % total, "%s · 이동·투사체·시야를 모두 막습니다." % " · ".join(parts),
		"벽·기둥 같은 단단한 지형은 이동과 투사체, 시야를 모두 막습니다.")


## Every gimmick (hazards, gate groups, brush) with exact numbers.
func _gimmick_rows(a: Arena) -> Array:
	var out: Array = []
	var gimmicks: Array = CodexData.arena_hazards(a) if a.ruleset == "deathmatch" else CodexData.arena_gimmicks(a)
	for h in gimmicks:
		var hd: Dictionary = h
		# The battleground brush has its own row (_br_rows).
		if a.ruleset == "battleground" and str(hd.type) == "brush":
			continue
		var cnt: int = int(hd.count)
		var rule: String = "" if str(hd.type) in ["gate", "brush"] else "\n" + str(CodexData.HAZARD_RULE.text)
		out.append(_fact_row(str(hd.icon), hd.color, str(hd.label), ("×%d" % cnt) if cnt > 1 else "", str(hd.summary), str(hd.desc) + rule))
	return out


## Body-only terrain (fences, sunken ground): blocks movement only, sight and projectiles pass.
func _low_terrain_rows(a: Arena) -> Array:
	var out: Array = []
	for t in CodexData.low_terrain(a):
		var td: Dictionary = t
		var what: String = ("%s · " % str(td.detail)) if str(td.detail) != "" else ""
		out.append(_fact_row(str(td.icon), td.color, str(td.label), "×%d" % int(td.count),
			"%s이동만 막습니다 · 시야와 투사체는 통과합니다." % what, str(CodexData.COVER.desc)))
	return out


func _hazard_rows(a: Arena) -> Array:
	var out: Array = _gimmick_rows(a)
	out.append_array(_low_terrain_rows(a))
	if out.is_empty():
		out.append(_fact_row("◌", UITheme.TEXT_FAINT, "환경 효과 없음", "", "피해를 주거나 밀어내는 위험 지역이 없습니다."))
	var terrain: Control = _terrain_row(a)
	if terrain:
		out.append(terrain)
	return out


func _control_rows(a: Arena) -> Array:
	var out: Array = []
	var rules: Dictionary = {}
	for r in CodexData.CONTROL_RULES:
		rules[str(r.key)] = str(r.text)
	if not a.control_points.is_empty():
		var cp: Dictionary = a.control_points[0]
		var names: Array = []
		for p in a.control_points:
			names.append(str((p as Dictionary).get("id", "")))
		out.append(_fact_row("據", UITheme.GOLD, "거점", "%d곳" % a.control_points.size(),
			"%s · 반경 %s · 한 팀만 5초 머물면 중립화, 5초 더 머물면 점령 · 거점마다 초당 %s점" % ["·".join(names), CodexData.num(roundf(float(cp.get("radius", 0.0)))), CodexData.num(DominationMode.SCORE_RATE)],
			"%s\n%s\n%s" % [rules.get("capture", ""), rules.get("score", ""), rules.get("contest", "")]))
	if not a.heal_zones.is_empty():
		var hz: Dictionary = a.heal_zones[0]
		out.append(_fact_row("癒", UITheme.GOOD, "회복 구역", "%d곳" % a.heal_zones.size(),
			"반경 %s · 한 팀만 있을 때 체력 85%% 미만 아군 중 가장 낮은 1명에게 최대 체력 %s%% 회복 · %s초마다 충전" % [CodexData.num(roundf(float(hz.get("radius", 0.0)))),
				CodexData.num(float(hz.get("heal_ratio", 0.35)) * 100.0), CodexData.num(float(hz.get("cooldown", 25.0)))],
			str(rules.get("heal_zone", ""))))
	out.append_array(_gimmick_rows(a))
	out.append_array(_low_terrain_rows(a))
	var terrain: Control = _terrain_row(a)
	if terrain:
		out.append(terrain)
	return out


func _dm_rows(a: Arena) -> Array:
	var out: Array = []
	var n: Dictionary = CodexData.dm_counts(a)
	var preset: Dictionary = DeathmatchMapData.PRESETS.get(str(a.data.get("preset", "")), {})
	var rules: Dictionary = {}
	for r in CodexData.DM_MAP_RULES:
		rules[str(r.key)] = str(r.text)
	var fr: Array = preset.get("forests", [])
	var br: Array = preset.get("buildings", [])
	out.append(_fact_row("林", Color("#7fd08a"), "숲", "%d곳" % int(n.forests),
		"숲 안의 영웅은 110 이내로 다가오거나 교전하기 전까지 보이지 않습니다%s." % ((" · 시드마다 %d~%d곳" % [int(fr[0]), int(fr[1])]) if fr.size() == 2 else ""),
		"%s\n%s" % [rules.get("forest", ""), rules.get("canopy", "")]))
	out.append(_fact_row("屋", Color("#e0b46e"), "건물", "%d채" % int(n.buildings),
		"벽이 이동·투사체·시야를 모두 막습니다%s." % ((" · 시드마다 %d~%d채" % [int(br[0]), int(br[1])]) if br.size() == 2 else ""),
		str(rules.get("building", ""))))
	var rocks: int = 0
	var trunks: int = 0
	for o in a.obstacles:
		match str((o as Dictionary).get("kind", "")):
			"pillar":
				rocks += 1
			"tree":
				trunks += 1
	out.append(_fact_row("岩", Color("#9fb0b0"), "바위 · 나무 줄기", "",
		"바위 %d개는 이동·투사체·시야를 모두 막고, 나무 줄기 %d개는 이동과 투사체만 막아 시야는 통과합니다." % [rocks, trunks],
		str(rules.get("obstacle", ""))))
	var spots: Dictionary = {"building": 0, "forest": 0, "field": 0}
	for s in a.item_spots:
		var sk: String = str((s as Dictionary).get("kind", "field"))
		spots[sk] = int(spots.get(sk, 0)) + 1
	out.append(_fact_row("寶", UITheme.GOLD, "아이템 자리", "%d곳" % int(n.item_spots),
		"건물 안 %d · 숲 %d · 들판 %d곳 · 필드에는 아이템이 최대 %d개까지 놓입니다." % [int(spots.building), int(spots.forest), int(spots.field), DeathmatchMode.MAX_FIELD_ITEMS],
		"새 아이템은 이 자리 중 한 곳에 생깁니다. 필드의 다른 아이템과 150, 살아 있는 영웅과 260 이상 떨어진 자리를 고르며, 시작 배치는 영웅 거리를 따지지 않습니다. 건물마다 안쪽에 최대 3곳이 있습니다."))
	out.append_array(_gimmick_rows(a))
	return out


## Battleground facts: buildings, brush, item spots by ring, spawns and landmarks, then every gimmick.
func _br_rows(a: Arena) -> Array:
	var out: Array = []
	var n: Dictionary = CodexData.br_counts(a)
	var rules: Dictionary = {}
	for r in CodexData.BR_MAP_RULES:
		rules[str(r.key)] = str(r.text)
	out.append(_fact_row("屋", Color("#e0b46e"), "건물", "%d채" % int(n.buildings),
		"벽이 이동·투사체·시야를 모두 막습니다. 건물 안에도 아이템 자리가 있습니다.", str(rules.get("map", ""))))
	out.append(_fact_row("♣", Color("#7fd08a"), "수풀", "%d무리" % int(n.brush),
		"수풀 원 %d개 · 안의 영웅은 110 이내로 다가오거나 교전하기 전까지 보이지 않습니다." % int(n.brush_circles), str(CodexData.HAZARDS.brush.desc)))
	var rings: Array = n.rings
	out.append(_fact_row("寶", UITheme.GOLD, "아이템 자리", "%d곳" % int(n.item_spots),
		"%s %d · %s %d · %s %d · %s %d곳 · 시작할 때 %d개가 놓입니다." % [CodexData.BR_RING_LABELS[0], int(rings[0]), CodexData.BR_RING_LABELS[1], int(rings[1]),
			CodexData.BR_RING_LABELS[2], int(rings[2]), CodexData.BR_RING_LABELS[3], int(rings[3]), BattlegroundMode.ITEM_COUNT],
		"아이템은 고리마다 정해진 개수(중앙 %d · 안쪽 %d · 바깥쪽 %d · 외곽 %d)가 이 자리 중에 놓이며 중앙일수록 높은 등급이 많습니다." % BrItems.RING_COUNTS))
	out.append(_fact_row("◎", UITheme.ACCENT, "출발 지점 · 랜드마크", "%d곳" % int(n.spawns),
		"팀마다 서로 가장 먼 출발 지점에서 시작합니다 · 이름 붙은 장소 %d곳" % int(n.landmarks),
		"출발 지점은 서로 800 이상 떨어져 있고 중앙 원 밖에 있습니다."))
	out.append(_fact_row("⊙", Color("#cf9bff"), "자기장", "%d단계" % BrZone.PHASES, str(rules.get("zone", "")), str(CodexData.HAZARDS.br_zone.desc)))
	out.append_array(_gimmick_rows(a))
	return out


func _tactical_notes(a: Arena, kind: String) -> Array:
	var notes: Array = a.data.get("tacticalNotes", [])
	if notes.is_empty() and kind == "deathmatch":
		var pid: String = str(a.data.get("preset", ""))
		for c in DeathmatchMapData.catalogue():
			if str((c as Dictionary).get("id", "")) == pid:
				notes = (c as Dictionary).get("tacticalNotes", [])
	return notes


func _relayout_arenas() -> void:
	if arena_scroll == null:
		return
	var cols: int = 2 if arena_scroll.size.x >= ARENA_TWO_COL_W else 1
	if cols == _arena_cols:
		return
	_arena_cols = cols
	for g in _arena_grids:
		(g as GridContainer).columns = cols
	var tw: int = THUMB_W_ONE if cols == 1 else THUMB_W_TWO
	for tc in _arena_thumb_cols:
		(tc as Control).custom_minimum_size.x = tw
	for key in arena_cards:
		(arena_cards[key] as Control).custom_minimum_size.x = tw
	for rg in _arena_rule_grids:
		var n: int = int((rg as GridContainer).get_meta("n", 3))
		(rg as GridContainer).columns = clampi(n, 1, 2 if n <= 2 else (3 if cols == 1 else 4))


func _jump_arena_group(id: Variant) -> void:
	for s in _arena_sections:
		if str(s[0]) == str(id):
			arena_scroll.scroll_vertical = int((s[1] as Control).position.y)
			return


func _on_arena_scrolled(value: float) -> void:
	var bar: VScrollBar = arena_scroll.get_v_scroll_bar()
	var pick: String = str(_arena_sections[0][0])
	if value >= bar.max_value - bar.page - 2.0:
		pick = str(_arena_sections[_arena_sections.size() - 1][0])
	else:
		for s in _arena_sections:
			if (s[1] as Control).position.y <= value + 60.0:
				pick = str(s[0])
	UITheme.segmented_select(arena_jump, pick)


func _focus_arena(id: String) -> void:
	var key: String = id
	if not arena_panels.has(key):
		for k in arena_panels:
			if id.begins_with(str(k)):
				key = str(k)
	var p: PanelContainer = arena_panels.get(key)
	if p == null:
		if not _dm_pending.is_empty() or not _br_pending.is_empty():
			_pending_focus = id
		return
	_set_highlight(p, UITheme.ACCENT, 16, 16)
	_reveal_later(arena_scroll, p, true)


# ================================================================== items

func _build_items() -> Control:
	var h: = UITheme.hbox(UITheme.SP4)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left: = UITheme.vbox(UITheme.SP2)
	left.custom_minimum_size = Vector2(ITEM_LIST_W, 0)
	var ropts: Array = [[-1, "전체", "모든 등급을 봅니다."]]
	for r in ItemDefs.RARITY_NAMES.size():
		ropts.append([r, str(ItemDefs.RARITY_NAMES[r]), "%s 등급 %d종 · 출현 확률 %s%%" % [ItemDefs.RARITY_NAMES[r], CodexData.rarity_count(r), CodexData.num(snappedf(CodexData.rarity_chance(r), 0.1))]])
	rarity_seg = UITheme.segmented(ropts, -1, func(r: Variant) -> void:
		rarity_filter = int(r)
		_filter_items())
	_stretch_segmented(rarity_seg)
	var rb: Dictionary = rarity_seg.get_meta("buttons")
	for r in ItemDefs.RARITY_NAMES.size():
		var col: Color = ItemDefs.rarity_color(r)
		var b: Button = rb[r]
		b.add_theme_color_override("font_color", col.lerp(UITheme.TEXT_DIM, 0.35))
		b.add_theme_color_override("font_hover_color", col.lightened(0.25))
		b.add_theme_color_override("font_pressed_color", col.lightened(0.4))
		b.add_theme_color_override("font_hover_pressed_color", col.lightened(0.4))
	left.add_child(rarity_seg)
	item_search = _search_box("이름·효과·특성으로 찾기", _filter_items)
	left.add_child(UITheme.margin(item_search, 0, 0, 0, 2))
	var wv: = UITheme.vbox(0)
	left.add_child(_well(wv))
	item_list = ItemViews.codex_list(false, _select_item)
	item_list_scroll = UITheme.scroll(UITheme.margin(item_list, 0, 0, 2, 4))
	wv.add_child(item_list_scroll)
	item_empty = _empty("찾는 아이템이 없습니다", "검색어를 지우거나 다른 등급을 고르면 다시 표시됩니다.")
	wv.add_child(item_empty)
	h.add_child(left)

	var dc: = UITheme.panel("CardPanel")
	dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner: = UITheme.vbox(UITheme.SP5)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_detail_host = UITheme.vbox(0)
	item_detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(item_detail_host)
	_rules_below = UITheme.vbox(0)
	inner.add_child(_rules_below)
	item_scroll = UITheme.scroll(UITheme.margin(inner, 10, 8, 16, 10))
	dc.add_child(item_scroll)
	h.add_child(dc)

	# Deathmatch item rules, then the battleground odds by ring (V2).
	rules_card = UITheme.vbox(UITheme.SP3)
	rules_card.add_child(ItemViews.rules_card())
	rules_card.add_child(UITheme.styled_panel(UITheme.sbc(UITheme.PANEL2, UITheme.LINE, 12, 1, 16, 14), ItemViews.br_ring_table()))
	_rules_side = UITheme.scroll()
	_rules_side.custom_minimum_size = Vector2(RULES_MIN_W, 0)
	_rules_side.size_flags_stretch_ratio = 0.4
	h.add_child(_rules_side)
	h.resized.connect(_relayout_items.bind(h))
	_rules_side.visible = false
	_relayout_items.call_deferred(h)
	_select_item(str(ItemDefs.by_rarity(0)[0]) if current_item == "" else current_item)
	return h


## Item rules sit in their own column when there is room, otherwise under the detail.
func _relayout_items(h: Control) -> void:
	var wide: int = 1 if h.size.x >= ITEM_RULES_SIDE_W else 0
	if wide == _rules_wide:
		return
	_rules_wide = wide
	if rules_card.get_parent():
		rules_card.get_parent().remove_child(rules_card)
	if wide == 1:
		_rules_side.visible = true
		_rules_side.add_child(rules_card)
		rules_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_rules_side.visible = false
		_rules_below.add_child(rules_card)


func _select_item(id: String) -> void:
	if not ItemDefs.DEFS.has(id) or item_list == null:
		return
	current_item = id
	var rows: Dictionary = item_list.get_meta("rows")
	var row: Control = rows.get(id)
	if row and not row.visible:
		item_search.text = ""
		rarity_filter = -1
		UITheme.segmented_select(rarity_seg, -1)
		_filter_items()
	ItemViews.select(item_list, id)
	for c in item_detail_host.get_children():
		item_detail_host.remove_child(c)
		c.queue_free()
	item_detail_host.add_child(ItemViews.detail(id, _open_hero))
	item_scroll.scroll_vertical = 0
	_reveal_later(item_list_scroll, row)


func _filter_items() -> void:
	var n: int = ItemViews.filter(item_list, item_search.text, rarity_filter)
	item_list_scroll.visible = n > 0
	item_empty.visible = n == 0


# ================================================================== glossary

func _build_glossary() -> Control:
	var v: = UITheme.vbox(UITheme.SP3)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var copts: Array = [["", "전체 %d" % CodexData.STATUS.size(), "모든 분류를 봅니다."]]
	for cat in CodexData.categories():
		copts.append([cat, "%s %d" % [cat, CodexData.terms_in_category(cat).size()], str(CATEGORY_HINTS.get(cat, ""))])
	category_seg = UITheme.segmented(copts, "", func(c: Variant) -> void:
		category_filter = str(c)
		_filter_terms())
	var bar: = UITheme.hbox(UITheme.SP3)
	bar.add_child(category_seg)
	bar.add_child(UITheme.spacer())
	glossary_search = _search_box("용어·정의로 찾기", _filter_terms)
	glossary_search.custom_minimum_size = Vector2(280, 36)
	glossary_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(glossary_search)
	v.add_child(bar)

	_index_item_terms()
	var box: = UITheme.vbox(UITheme.SP6)
	for cat in CodexData.categories():
		var sec: = UITheme.vbox(UITheme.SP3)
		var keys: Array = CodexData.terms_in_category(cat)
		sec.add_child(UITheme.section_header(cat, str(CATEGORY_HINTS.get(cat, "")), UITheme.badge("%d개" % keys.size(), UITheme.TEXT_DIM, "outline")))
		var grid: = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", UITheme.SP3)
		grid.add_theme_constant_override("v_separation", UITheme.SP3)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for key in keys:
			var card: = _term_card(str(key))
			term_cards[str(key)] = card
			grid.add_child(card)
		sec.add_child(grid)
		_term_grids.append(grid)
		_term_sections[cat] = sec
		box.add_child(sec)
	glossary_scroll = UITheme.scroll(UITheme.margin(box, 0, 4, 6, 8))
	v.add_child(glossary_scroll)
	glossary_empty = _empty("찾는 용어가 없습니다", "검색어를 줄이거나 다른 분류를 고르면 다시 표시됩니다.")
	v.add_child(glossary_empty)
	glossary_scroll.resized.connect(_relayout_glossary)
	return v


## term key -> item ids whose description or detail lines mention the term (built once).
func _index_item_terms() -> void:
	if not _item_terms.is_empty():
		return
	for iid in ItemDefs.ORDER:
		var d: Dictionary = ItemDefs.get_def(str(iid))
		var text: String = str(d.get("desc", "")) + " " + " ".join(CodexData.item_details(str(iid)))
		for k in CodexText.terms_in(text):
			if not _item_terms.has(k):
				_item_terms[k] = []
			(_item_terms[k] as Array).append(str(iid))


func _term_card(key: String) -> PanelContainer:
	var d: Dictionary = CodexData.STATUS[key]
	var col: = Color(str(d.color))
	var card: = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.PANEL2, UITheme.LINE, UITheme.R_L, 1, 14, 12))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("term", key)
	var v: = UITheme.vbox(UITheme.SP2)
	var top: = UITheme.hbox(UITheme.SP3)
	var tile: = UITheme.glyph_tile(str(d.icon), col, 36)
	top.add_child(tile)
	var tv: = UITheme.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(UITheme.label(str(d.label), "SubheadLabel", 0, col.lerp(UITheme.TEXT, 0.45)))
	var aliases: Array = d.get("aliases", [])
	if not aliases.is_empty():
		var al: = UITheme.ellipsize(UITheme.label("다른 표기 · " + ", ".join(aliases), "FaintLabel", 12), true)
		tv.add_child(al)
	top.add_child(tv)
	v.add_child(top)
	v.add_child(UITheme.wrap_label(str(d.desc), "DimLabel", 14))

	var heroes: Array = CodexText.heroes_for_term(key)
	var items: Array = _item_terms.get(key, [])
	if not heroes.is_empty() or not items.is_empty():
		var grow: = Control.new()
		grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(grow)
		v.add_child(UITheme.sep_line())
	if not heroes.is_empty():
		var hv: = UITheme.vbox(4)
		hv.add_child(UITheme.label("관련 영웅 %d" % heroes.size(), "FaintLabel", 12))
		var flow: = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 2)
		flow.add_theme_constant_override("v_separation", 2)
		for hid in heroes:
			flow.add_child(_hero_button(str(hid)))
		hv.add_child(flow)
		v.add_child(hv)
	if not items.is_empty():
		var iv: = UITheme.vbox(4)
		iv.add_child(UITheme.label("관련 아이템 %d" % items.size(), "FaintLabel", 12))
		var iflow: = HFlowContainer.new()
		iflow.add_theme_constant_override("h_separation", 2)
		iflow.add_theme_constant_override("v_separation", 2)
		for iid in items:
			iflow.add_child(_item_button(str(iid), 24))
		iv.add_child(iflow)
		v.add_child(iv)
	card.add_child(v)
	card.tooltip_text = ""
	return card


func _relayout_glossary() -> void:
	if glossary_scroll == null:
		return
	var cols: int = clampi(floori(glossary_scroll.size.x / TERM_CARD_W), 1, 5)
	if cols == _term_cols:
		return
	_term_cols = cols
	for g in _term_grids:
		(g as GridContainer).columns = cols


func _filter_terms() -> void:
	var q: String = glossary_search.text.strip_edges().to_lower()
	var total: int = 0
	for cat in _term_sections:
		var shown: int = 0
		var cat_ok: bool = category_filter == "" or category_filter == str(cat)
		for key in CodexData.terms_in_category(str(cat)):
			var card: Control = term_cards.get(str(key))
			if card == null:
				continue
			var ok: bool = cat_ok
			if ok and q != "":
				var d: Dictionary = CodexData.STATUS[str(key)]
				var hay: String = "%s %s %s %s" % [str(d.label), ", ".join(d.get("aliases", [])), str(d.desc), str(key)]
				ok = hay.to_lower().contains(q)
			card.visible = ok
			if ok:
				shown += 1
		(_term_sections[cat] as Control).visible = shown > 0
		total += shown
	glossary_scroll.visible = total > 0
	glossary_empty.visible = total == 0


func _focus_term(id: String) -> void:
	var key: String = id if term_cards.has(id) else CodexData.term_for_label(id)
	var card: PanelContainer = term_cards.get(key)
	if card == null:
		return
	var sec: Control = card.get_parent().get_parent() as Control
	if not card.visible or (sec and not sec.visible):
		glossary_search.text = ""
		category_filter = ""
		UITheme.segmented_select(category_seg, "")
		_filter_terms()
	_set_highlight(card, CodexData.term_color(key, UITheme.ACCENT), 14, 12)
	_reveal_later(glossary_scroll, card, true)
