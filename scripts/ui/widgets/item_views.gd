class_name ItemViews
extends RefCounted

# Shared item codex widgets (V1.5.1): used by the deathmatch setup sidebar
# (compact) and the codex "items" mode. Static builders only; every StyleBox is
# cached, nothing is rebuilt per frame.
#
#   rarity_header(r, mode)           "전설 4종" + "출현 5% · 개별 1.3%" (battleground:
#                                    "필드 80개 중 약 4개")
#   list_row(id, compact)            read-only row (glyph tile, name, desc)
#   selectable_row(id, on_select)    toggle Button row for a codex list
#   codex_list(compact, on_select, mode)  all rarity groups (headers + rows); mode
#                                    "deathmatch" (default) or "battleground" picks the
#                                    slot / field note and the odds labels
#   br_ring_table()                  battleground rarity odds per item ring (V2)
#   detail(id, on_hero)              full item page (details, tags, hero fit)
#   rules_card()                     deathmatch item rules
#   tile(id, px)                     rarity-coloured glyph tile
#   select(list, id) / filter(list, query, rarity) / tooltip_text(id)

const ROW_H := 58
const HERO_ROW_H := 48
const FIT_COL_MIN := 250

static var _styles: Dictionary = {}


# ---------------------------------------------------------------- style helpers

static func _style(key: String, bg: Color, border: Color, radius: int, bw: int = 1, pad_h: int = 0, pad_v: int = 0) -> StyleBoxFlat:
	if _styles.has(key):
		return _styles[key]
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	_styles[key] = s
	return s


static func _empty_style() -> StyleBoxEmpty:
	if not _styles.has("empty"):
		_styles["empty"] = StyleBoxEmpty.new()
	return _styles["empty"]


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


static func _ellipsize(l: Label) -> Label:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	return l


static func _bar(color: Color, w: int = 3, h: int = 14) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(w, h)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _section(title: String, hint: String = "") -> HBoxContainer:
	var h: HBoxContainer = UITheme.hbox(8)
	h.add_child(_bar(UITheme.ACCENT))
	h.add_child(UITheme.label(title, "BoldLabel", 16, UITheme.TEXT))
	if hint != "":
		var f: Label = UITheme.label(hint, "FaintLabel", 12, UITheme.TEXT_FAINT)
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(f)
	return h


static func _rich(bbcode: String, font_size: int = 14, color: Color = Color(0, 0, 0, 0)) -> RichTextLabel:
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)
	r.add_theme_color_override("default_color", color if color.a > 0.0 else UITheme.TEXT_DIM.lerp(UITheme.TEXT, 0.35))
	r.text = bbcode
	return r


static func _pct1(v: float) -> String:
	return "%.1f" % snappedf(v, 0.1)


# ---------------------------------------------------------------- basic parts

# Rarity-coloured glyph tile (Label so it stays cheap; font = DB.font_glyph).
static func tile(id: String, px: int = 32) -> Label:
	DB.load_fonts()
	var d: Dictionary = ItemDefs.get_def(id)
	var r: int = ItemDefs.rarity_of(id)
	var col: Color = ItemDefs.rarity_color(r)
	var l: Label = Label.new()
	l.text = str(d.get("glyph", "?"))
	l.add_theme_font_override("font", DB.font_glyph)
	l.add_theme_font_size_override("font_size", maxi(12, int(round(px * 0.5))))
	l.add_theme_color_override("font_color", col.lightened(0.55))
	l.custom_minimum_size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var radius: int = 10 if px >= 48 else 6
	l.add_theme_stylebox_override("normal", _style("tile:%d:%d" % [r, radius], col.darkened(0.64), Color(col, 0.7), radius, 1))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# "이름 · 등급\n효과\n• 상세…" for rows and other screens' item tooltips.
static func tooltip_text(id: String) -> String:
	var d: Dictionary = ItemDefs.get_def(id)
	if d.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s · %s · 개별 출현 %s%%" % [str(d.get("name", id)), ItemDefs.RARITY_NAMES[ItemDefs.rarity_of(id)], _pct1(CodexData.item_chance(id))])
	lines.append(CodexText.wrap_text(str(d.get("desc", "")), 40))
	for line in CodexData.item_details(id):
		lines.append(CodexText.wrap_text("• " + str(line), 40))
	return "\n".join(lines)


static func rarity_header(r: int, mode: String = "deathmatch") -> Control:
	DB.load_fonts()
	var col: Color = ItemDefs.rarity_color(r)
	var h: HBoxContainer = UITheme.hbox(8)
	h.set_meta("rarity", r)
	h.add_child(_bar(col, 3, 16))
	var t: Label = UITheme.label("%s %d종" % [ItemDefs.RARITY_NAMES[r], CodexData.rarity_count(r)], "", 15, col)
	t.add_theme_font_override("font", DB.font_black)
	h.add_child(t)
	var sp: Control = UITheme.spacer()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var chance: Label
	if mode == "battleground":
		# Battleground: 80 items placed once, odds by ring (br_ring_table): the expected count.
		chance = UITheme.label("필드 %d개 중 약 %s개" % [BattlegroundMode.ITEM_COUNT, _pct1(br_expected(r))], "FaintLabel", 12, UITheme.TEXT_FAINT)
		chance.tooltip_text = "배틀그라운드에서 시작할 때 놓이는 %d개 가운데 이 등급의 평균 개수입니다. 고리마다 확률이 다르며 중앙일수록 높은 등급이 많습니다." % BattlegroundMode.ITEM_COUNT
	else:
		chance = UITheme.label("출현 %d%% · 개별 %s%%" % [int(round(CodexData.rarity_chance(r))), _pct1(CodexData.rarity_chance(r) / maxf(1.0, float(CodexData.rarity_count(r))))], "FaintLabel", 12, UITheme.TEXT_FAINT)
		chance.tooltip_text = "등급 출현 확률 · 이 등급 아이템 하나의 출현 확률(등급 확률 ÷ %d종)" % CodexData.rarity_count(r)
	chance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chance.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(chance)
	return h


# Read-only row. compact = the 338 px deathmatch sidebar.
static func list_row(id: String, compact: bool = true, mode: String = "deathmatch") -> Control:
	var d: Dictionary = ItemDefs.get_def(id)
	var r: int = ItemDefs.rarity_of(id)
	var col: Color = ItemDefs.rarity_color(r)
	var row: HBoxContainer = UITheme.hbox(10)
	var g: Label = tile(id, 30 if compact else 34)
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(g)
	var tv: VBoxContainer = UITheme.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = UITheme.hbox(6)
	var nm: Label = _ellipsize(UITheme.label(str(d.get("name", id)), "BoldLabel", 14, UITheme.TEXT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	# Deathmatch: the spawn chance per roll; battleground: the expected copies among the placed items.
	var ch_text: String = "%s%%" % _pct1(CodexData.item_chance(id))
	if mode == "battleground":
		ch_text = "약 %s개" % _pct1(br_expected(r) / maxf(1.0, float(CodexData.rarity_count(r))))
	var ch: Label = UITheme.label(ch_text, "FaintLabel", 12, UITheme.TEXT_FAINT)
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ch)
	tv.add_child(top)
	tv.add_child(UITheme.wrap_label(str(d.get("desc", "")), "DimLabel", 13, UITheme.TEXT_DIM))
	row.add_child(tv)
	var pad_h: int = 9 if compact else 12
	var pad_v: int = 7 if compact else 9
	var p: PanelContainer = UITheme.styled_panel(_style("row:%d:%d" % [r, 1 if compact else 0], Color(col, 0.035), Color(col, 0.16), 8, 1, pad_h, pad_v), row)
	p.set_meta("item_id", id)
	p.tooltip_text = tooltip_text(id)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_ignore_mouse(row)
	return p


# Toggle row for a codex list; the name Label sits inside the Button.
static func selectable_row(id: String, on_select: Callable) -> Button:
	var d: Dictionary = ItemDefs.get_def(id)
	var r: int = ItemDefs.rarity_of(id)
	var col: Color = ItemDefs.rarity_color(r)
	var b: Button = Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("item_id", id)
	b.tooltip_text = tooltip_text(id)
	b.add_theme_stylebox_override("normal", _style("sel:n:%d" % r, Color(col, 0.03), Color(col, 0.14), 8))
	b.add_theme_stylebox_override("hover", _style("sel:h:%d" % r, Color(1, 1, 1, 0.05), Color(col, 0.32), 8))
	b.add_theme_stylebox_override("pressed", _style("sel:p", Color(UITheme.ACCENT, 0.13), UITheme.ACCENT, 8, 1))
	b.add_theme_stylebox_override("hover_pressed", _style("sel:hp", Color(UITheme.ACCENT, 0.18), UITheme.ACCENT.lightened(0.15), 8, 1))
	b.add_theme_stylebox_override("focus", _empty_style())
	b.add_theme_stylebox_override("disabled", _style("sel:n:%d" % r, Color(col, 0.03), Color(col, 0.14), 8))
	var m: MarginContainer = UITheme.margin(null, 10, 7, 10, 7)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row: HBoxContainer = UITheme.hbox(10)
	row.add_child(tile(id, 34))
	var tv: VBoxContainer = UITheme.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	var top: HBoxContainer = UITheme.hbox(6)
	var nm: Label = _ellipsize(UITheme.label(str(d.get("name", id)), "BoldLabel", 14, UITheme.TEXT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var ch: Label = UITheme.label("%s%%" % _pct1(CodexData.item_chance(id)), "FaintLabel", 12, UITheme.TEXT_FAINT)
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ch)
	tv.add_child(top)
	tv.add_child(_ellipsize(UITheme.label(str(d.get("desc", "")), "DimLabel", 13, UITheme.TEXT_DIM)))
	row.add_child(tv)
	m.add_child(row)
	b.add_child(m)
	_ignore_mouse(m)
	if on_select.is_valid():
		var iid: String = id
		b.pressed.connect(func(): on_select.call(iid))
	return b


# All rarity groups. With a valid on_select the rows are toggle Buttons in one
# ButtonGroup (codex list); otherwise read-only rows (deathmatch sidebar).
static func codex_list(compact: bool = true, on_select: Callable = Callable(), mode: String = "deathmatch") -> Control:
	var v: VBoxContainer = UITheme.vbox(6 if compact else 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.set_meta("item_list", true)
	if compact:
		var note: String = "영웅은 아이템을 %d개까지 들고 같은 아이템은 겹쳐 가질 수 없습니다. 필드에는 최대 %d개가 놓입니다. 행에 마우스를 올리면 상세 규칙을 볼 수 있습니다." % [DeathmatchMode.SLOTS, DeathmatchMode.MAX_FIELD_ITEMS]
		if mode == "battleground":
			note = "영웅은 아이템을 %d개까지 들고 더 유용한 아이템을 만나면 교체합니다. 필드에는 시작할 때 %d개가 놓이고 다시 생기지 않습니다. 행에 마우스를 올리면 상세 규칙을 볼 수 있습니다." % [DeathmatchMode.SLOTS, BattlegroundMode.ITEM_COUNT]
		v.add_child(UITheme.wrap_label(note, "FaintLabel", 12, UITheme.TEXT_FAINT))
	var group: ButtonGroup = ButtonGroup.new() if on_select.is_valid() else null
	var rows: Dictionary = {}
	for r in ItemDefs.RARITY_NAMES.size():
		var hdr: Control = rarity_header(r, mode)
		v.add_child(UITheme.margin(hdr, 2, 10 if r > 0 else 4, 2, 0))
		(hdr.get_parent() as Control).set_meta("rarity", r)
		for id in ItemDefs.by_rarity(r):
			var sid: String = str(id)
			var row: Control
			if group != null:
				var b: Button = selectable_row(sid, on_select)
				b.button_group = group
				row = b
			else:
				row = list_row(sid, compact, mode)
			rows[sid] = row
			v.add_child(row)
	v.set_meta("rows", rows)
	return v


# Mark one row selected without emitting (codex list built with on_select).
static func select(list: Control, id: String) -> void:
	if list == null or not list.has_meta("rows"):
		return
	var rows: Dictionary = list.get_meta("rows")
	for k in rows:
		var n: Variant = rows[k]
		if is_instance_valid(n) and n is Button:
			(n as Button).set_pressed_no_signal(str(k) == id)


# Show only rows matching the query (name, desc, tags) and rarity (-1 = all);
# rarity headers hide when their group is empty. Returns the visible count.
static func filter(list: Control, query: String = "", rarity: int = -1) -> int:
	if list == null or not list.has_meta("rows"):
		return 0
	var q: String = query.strip_edges().to_lower()
	var rows: Dictionary = list.get_meta("rows")
	var per: Dictionary = {}
	var shown: int = 0
	for k in rows:
		var n: Variant = rows[k]
		if not is_instance_valid(n) or not (n is Control):
			continue
		var id: String = str(k)
		var r: int = ItemDefs.rarity_of(id)
		var ok: bool = rarity < 0 or r == rarity
		if ok and q != "":
			var d: Dictionary = ItemDefs.get_def(id)
			var hay: String = "%s %s %s" % [str(d.get("name", "")), str(d.get("desc", "")), " ".join(Array(d.get("tags", [])).map(func(t): return CodexData.tag_label(str(t))))]
			ok = hay.to_lower().contains(q)
		(n as Control).visible = ok
		if ok:
			shown += 1
			per[r] = true
	for c in list.get_children():
		if c.has_meta("rarity"):
			(c as Control).visible = per.has(int(c.get_meta("rarity")))
	return shown


# ---------------------------------------------------------------- detail page

static func detail(id: String, on_hero: Callable = Callable()) -> Control:
	var d: Dictionary = ItemDefs.get_def(id)
	var v: VBoxContainer = UITheme.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.set_meta("item_id", id)
	if d.is_empty():
		v.add_child(UITheme.label("아이템을 선택하세요.", "DimLabel", 14, UITheme.TEXT_DIM))
		return v
	var r: int = ItemDefs.rarity_of(id)
	var col: Color = ItemDefs.rarity_color(r)

	# Header: big tile, name + rarity badge, chances, description.
	var head: HBoxContainer = UITheme.hbox(16)
	var big: Label = tile(id, 64)
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(big)
	var hv: VBoxContainer = UITheme.vbox(6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm_row: HBoxContainer = UITheme.hbox(10)
	var nm: Label = UITheme.label(str(d.get("name", id)), "", 24, UITheme.TEXT)
	nm.add_theme_font_override("font", DB.font_black)
	nm_row.add_child(nm)
	var badge: PanelContainer = UITheme.chip(str(ItemDefs.RARITY_NAMES[r]), col, true)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm_row.add_child(badge)
	hv.add_child(nm_row)
	hv.add_child(UITheme.label("등급 출현 %d%% · 개별 %s%%" % [int(round(CodexData.rarity_chance(r))), _pct1(CodexData.item_chance(id))], "DimLabel", 13, UITheme.TEXT_DIM))
	hv.add_child(UITheme.wrap_label(str(d.get("desc", "")), "", 15, UITheme.TEXT))
	head.add_child(hv)
	v.add_child(head)

	# Detail rules.
	var lines: Array = CodexData.item_details(id)
	if not lines.is_empty():
		var sec: VBoxContainer = UITheme.vbox(8)
		sec.add_child(_section("상세 규칙"))
		var list: VBoxContainer = UITheme.vbox(6)
		for line in lines:
			var lr: HBoxContainer = UITheme.hbox(10)
			var dot: ColorRect = ColorRect.new()
			dot.color = Color(col, 0.8)
			dot.custom_minimum_size = Vector2(5, 5)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot_wrap: MarginContainer = UITheme.margin(dot, 0, 8, 0, 0)
			dot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lr.add_child(dot_wrap)
			lr.add_child(_rich(CodexText.rich_desc(str(line)), 14))
			list.add_child(lr)
		sec.add_child(UITheme.margin(list, 4, 0, 0, 0))
		v.add_child(sec)

	# AI valuation tags.
	var tags: Array = d.get("tags", [])
	if not tags.is_empty():
		var tsec: VBoxContainer = UITheme.vbox(8)
		tsec.add_child(_section("특성", "AI가 영웅과의 궁합을 따질 때 쓰는 분류입니다."))
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for t in tags:
			flow.add_child(UITheme.chip(CodexData.tag_label(str(t)), UITheme.TEXT_DIM))
		tsec.add_child(UITheme.margin(flow, 4, 0, 0, 0))
		v.add_child(tsec)

	# Hero fit.
	v.add_child(_fit_block(id, on_hero))
	return v


static func _fit_block(id: String, on_hero: Callable) -> Control:
	DB.ensure_loaded()
	var rows: Array = []
	for c in DB.characters:
		var cd: Defs.CharDef = c
		var val: Dictionary = ItemValuation.value(cd, id, [])
		rows.append({"id": cd.id, "def": cd, "fit": float(val.get("fit", 0.0)), "reason": str(val.get("reason", ""))})
	rows.sort_custom(func(a, b): return float(a.fit) > float(b.fit) or (is_equal_approx(float(a.fit), float(b.fit)) and str(a.id) < str(b.id)))
	var hi: float = float(rows[0].fit) if not rows.is_empty() else 0.0
	var lo: float = float(rows[rows.size() - 1].fit) if not rows.is_empty() else 0.0

	var block: VBoxContainer = UITheme.vbox(10)
	# Two columns side by side when there is room, stacked when narrow.
	var cols: HFlowContainer = HFlowContainer.new()
	cols.add_theme_constant_override("h_separation", 18)
	cols.add_theme_constant_override("v_separation", 16)
	var left: VBoxContainer = UITheme.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(FIT_COL_MIN, 0)
	left.add_child(_section("잘 맞는 영웅 TOP 5"))
	var right: VBoxContainer = UITheme.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(FIT_COL_MIN, 0)
	right.add_child(_section("효과가 적은 영웅"))

	var flat: bool = rows.is_empty() or hi - lo < 0.05
	if flat:
		left.add_child(_note("모든 영웅에게 비슷하게 유용합니다 · 적합도 %d%%" % int(round(hi * 100.0))))
		right.add_child(_note("효과가 특히 적은 영웅이 없습니다."))
	else:
		var top_n: int = mini(5, rows.size())
		for k in top_n:
			left.add_child(_hero_row(rows[k], true, on_hero))
		var ties: int = 0
		for k in range(top_n, rows.size()):
			if absf(float(rows[k].fit) - float(rows[top_n - 1].fit)) < 0.005:
				ties += 1
		if ties > 0:
			left.add_child(_note("외 %d명도 같은 평가입니다." % ties))
		var low: Array = []
		for k in range(rows.size() - 1, -1, -1):
			if float(rows[k].fit) <= hi * 0.75 + 0.0001:
				low.append(rows[k])
		if low.is_empty():
			right.add_child(_note("효과가 특히 적은 영웅이 없습니다."))
		else:
			var low_n: int = mini(5, low.size())
			for k in low_n:
				right.add_child(_hero_row(low[k], false, on_hero))
			var lties: int = 0
			for k in range(low_n, low.size()):
				if absf(float(low[k].fit) - float(low[low_n - 1].fit)) < 0.005:
					lties += 1
			if lties > 0:
				right.add_child(_note("외 %d명도 같은 평가입니다." % lties))
	cols.add_child(left)
	cols.add_child(right)
	block.add_child(cols)
	var cap: Label = UITheme.wrap_label("적합도는 AI가 영웅의 피해 구성(공격력·주문력 비중, 평타 의존도), 사거리, 역할을 따져 계산한 값이며 100%가 보통입니다." + (" 영웅을 누르면 캐릭터 도감으로 이동합니다." if on_hero.is_valid() and not flat else ""), "FaintLabel", 12, UITheme.TEXT_FAINT)
	block.add_child(cap)
	return block


static func _note(text: String) -> Label:
	var l: Label = UITheme.wrap_label(text, "FaintLabel", 13, UITheme.TEXT_FAINT)
	return l


static func _hero_row(row: Dictionary, good: bool, on_hero: Callable) -> Control:
	var cd: Defs.CharDef = row.def
	var fit: float = float(row.fit)
	var h: HBoxContainer = UITheme.hbox(10)
	var disc: GlyphDisc = GlyphDisc.new(cd, 30.0)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var tv: VBoxContainer = UITheme.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(_ellipsize(UITheme.label(cd.name, "BoldLabel", 14, UITheme.TEXT)))
	var reason: String = str(row.reason)
	tv.add_child(_ellipsize(UITheme.label(reason if reason != "" else DB.role_label(cd.role), "DimLabel", 12, UITheme.TEXT_DIM)))
	h.add_child(tv)
	var pct: Label = UITheme.label("%d%%" % int(round(fit * 100.0)), "", 14, UITheme.GOOD if good else UITheme.WARN)
	pct.add_theme_font_override("font", DB.font_black)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pct.tooltip_text = "적합도 %d%% (100%% = 보통)" % int(round(fit * 100.0))
	h.add_child(pct)
	var tip: String = "%s · 적합도 %d%%\n%s" % [cd.name, int(round(fit * 100.0)), reason]
	if on_hero.is_valid():
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(0, HERO_ROW_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = tip + "\n누르면 캐릭터 도감에서 봅니다."
		b.add_theme_stylebox_override("normal", _style("hero:n", Color(1, 1, 1, 0.025), UITheme.LINE, 8))
		b.add_theme_stylebox_override("hover", _style("hero:h", Color(1, 1, 1, 0.06), UITheme.LINE2, 8))
		b.add_theme_stylebox_override("pressed", _style("hero:p", Color(UITheme.ACCENT, 0.12), UITheme.ACCENT, 8))
		b.add_theme_stylebox_override("hover_pressed", _style("hero:p", Color(UITheme.ACCENT, 0.12), UITheme.ACCENT, 8))
		b.add_theme_stylebox_override("focus", _empty_style())
		var m: MarginContainer = UITheme.margin(h, 8, 4, 10, 4)
		m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(m)
		_ignore_mouse(m)
		var hid: String = cd.id
		b.pressed.connect(func(): on_hero.call(hid))
		b.set_meta("hero_id", hid)
		return b
	var p: PanelContainer = UITheme.styled_panel(_style("hero:ro", Color(1, 1, 1, 0.025), UITheme.LINE, 8, 1, 8, 4), h)
	p.custom_minimum_size = Vector2(0, HERO_ROW_H)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.set_meta("hero_id", cd.id)
	_ignore_mouse(h)
	return p


# ---------------------------------------------------------------- rules card

## Expected number of rarity r among the battleground's placed items (ring counts x weights).
static func br_expected(r: int) -> float:
	var total: float = 0.0
	for ring in BrItems.RING_COUNTS.size():
		var w: Array = BrItems.ring_weights(ring)
		var sum: float = 0.0
		for x in w:
			sum += float(x)
		total += float(BrItems.RING_COUNTS[ring]) * float(w[r]) / maxf(1.0, sum)
	return total


## Battleground item odds per ring (DESIGN_V2 §3.4): one row per ring (centre to edge) with its
## item count and the rarity percentages; a ring that cannot hold a rarity shows "—".
static func br_ring_table() -> Control:
	DB.load_fonts()
	var v: VBoxContainer = UITheme.vbox(4)
	v.set_meta("ring_table", true)
	v.add_child(_section("고리별 등급 확률", "중앙일수록 높은 등급"))
	var hdr: HBoxContainer = UITheme.hbox(4)
	var cap: Label = UITheme.label("고리", "FaintLabel", 12, UITheme.TEXT_FAINT)
	cap.custom_minimum_size = Vector2(46, 0)
	hdr.add_child(cap)
	var cnt: Label = UITheme.label("개수", "FaintLabel", 12, UITheme.TEXT_FAINT)
	cnt.custom_minimum_size = Vector2(30, 0)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(cnt)
	for r in ItemDefs.RARITY_NAMES.size():
		var rl: Label = UITheme.label(str(ItemDefs.RARITY_NAMES[r]), "", 12, ItemDefs.rarity_color(r))
		rl.add_theme_font_override("font", DB.font_bold)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hdr.add_child(rl)
	v.add_child(UITheme.margin(hdr, 8, 0, 8, 0))
	for ring in BrItems.RING_COUNTS.size():
		var w: Array = BrItems.ring_weights(ring)
		var sum: float = 0.0
		for x in w:
			sum += float(x)
		var h: HBoxContainer = UITheme.hbox(4)
		var name_l: Label = UITheme.label(str(CodexData.BR_RING_LABELS[ring]), "BoldLabel", 13, UITheme.TEXT)
		name_l.custom_minimum_size = Vector2(46, 0)
		h.add_child(name_l)
		var n_l: Label = UITheme.label(str(int(BrItems.RING_COUNTS[ring])), "", 13, UITheme.TEXT_DIM)
		n_l.custom_minimum_size = Vector2(30, 0)
		n_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(n_l)
		for r in w.size():
			var pct: float = float(w[r]) / maxf(1.0, sum) * 100.0
			var pl: Label = UITheme.label(("%d%%" % int(roundf(pct))) if pct > 0.0 else "—", "", 13, ItemDefs.rarity_color(r).lerp(UITheme.TEXT, 0.35) if pct > 0.0 else UITheme.TEXT_FAINT)
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(pl)
		var row: PanelContainer = UITheme.styled_panel(_style("ring_row:%d" % (ring % 2), Color(1, 1, 1, 0.035 if ring % 2 == 0 else 0.0), UITheme.CLEAR, 6, 0, 8, 4), h)
		row.tooltip_text = UITheme.tip("%s 고리 · 아이템 %d개 · 전장 중심에서 반대각선의 %s 범위입니다." % [str(CodexData.BR_RING_LABELS[ring]), int(BrItems.RING_COUNTS[ring]),
			["0–20%", "20–45%", "45–70%", "70% 바깥"][ring]])
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(row)
	var total: Label = UITheme.wrap_label("시작할 때 모두 %d개를 놓고 다시 만들지 않습니다. 아이템끼리 %s 이상 떨어져 있고, 탈락한 영웅의 아이템은 그 자리에 모두 떨어집니다." % [BattlegroundMode.ITEM_COUNT, CodexData.num(BrItems.MIN_GAP)], "FaintLabel", 12, UITheme.TEXT_FAINT)
	v.add_child(UITheme.margin(total, 8, 2, 8, 0))
	return v


static func rules_card() -> Control:
	var v: VBoxContainer = UITheme.vbox(10)
	var head: HBoxContainer = _section("아이템 규칙", "데스매치 전용")
	v.add_child(head)
	var n: int = 0
	for rule in CodexData.ITEM_RULES:
		if n > 0:
			v.add_child(UITheme.sep_line())
		var rv: VBoxContainer = UITheme.vbox(2)
		rv.add_child(UITheme.label(str(rule.title), "BoldLabel", 14, UITheme.TEXT))
		rv.add_child(UITheme.wrap_label(str(rule.text), "DimLabel", 13, UITheme.TEXT_DIM))
		v.add_child(rv)
		n += 1
	var p: PanelContainer = UITheme.styled_panel(_style("rules", UITheme.PANEL2, UITheme.LINE, 12, 1, 16, 14), v)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p
