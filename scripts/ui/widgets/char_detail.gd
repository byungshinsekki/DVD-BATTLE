class_name CharDetail
extends ScrollContainer
## Character detail panel (setup, draft, deathmatch and codex).
##  header (disc, name, role, 성향, tags) -> summary -> stat tiles (+ crit/tenacity and rule badges,
##  summon stat lines) -> skill cards (passives first, then S1..S4) -> AI doctrine and nexus cards.
## API: show_def(d), set_selected_skill(kind, index), signal skill_requested(kind, index),
## preview_enabled (codex: ▶ buttons + clickable cards), preview_buttons, selected_skill, current, body.
## Everything is built once per character; nothing here runs per frame.

signal skill_requested(kind: String, index: int)

const STAT_ROWS: = [
	["체력", "maxHealth", "%d"], ["공격력", "attackDamage", "%d"], ["주문력", "abilityPower", "%d"], ["방어", "armor", "%d"],
	["마법 저항", "magicResistance", "%d"], ["공격 속도", "attackSpeed", "%.2f"], ["이동 속도", "moveSpeed", "%d"], ["사거리", "attackRange", "%d"]]
## Glossary terms that are not "effects" (skipped in the 효과 chip row).
const NON_EFFECT_TERMS: = ["cooldown"]
const NO_BASIC_TIP: = "평타 없음 — 기본 공격을 하지 않습니다. 평타·치명타·적중 효과가 적용되지 않습니다."

var body: VBoxContainer
var current: String = ""
var preview_enabled: bool = false
var preview_buttons: Dictionary = {}
var selected_skill: String = ""
## "kind:index" -> skill card PanelContainer (for the selected/hover look).
var skill_cards: Dictionary = {}
var _hovered: String = ""
var _built_frame: int = -1


func _init() -> void :
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	body = UITheme.vbox(UITheme.SP4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = UITheme.margin(body, 2, 2, 8, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(m)


func show_def(d: Defs.CharDef) -> void :
	if d == null or d.id == current:
		return
	current = d.id
	_built_frame = Engine.get_process_frames()
	preview_buttons.clear()
	skill_cards.clear()
	_hovered = ""
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	body.add_child(_header(d))
	if d.summary != "":
		body.add_child(UITheme.wrap_label(d.summary, "BodyLabel", UITheme.FS_SM))
	body.add_child(_stats(d))
	body.add_child(_skills(d))
	var ai: Control = _ai_section(d)
	if ai:
		body.add_child(ai)
	scroll_vertical = 0


func set_selected_skill(kind: String, index: int) -> void:
	var key_now: String = "%s:%d" % [kind, index]
	var changed: bool = key_now != selected_skill
	selected_skill = key_now
	for key in preview_buttons:
		(preview_buttons[key] as Button).set_pressed_no_signal(key == selected_skill)
	for key in skill_cards:
		_style_card(key)
	# Follow a selection made elsewhere (the preview tabs), but not in the frame of a rebuild:
	# a freshly opened character always starts at its header.
	var card: Control = skill_cards.get(selected_skill)
	if changed and card != null and is_inside_tree() and Engine.get_process_frames() != _built_frame:
		ensure_control_visible(card)


# ------------------------------------------------------------------ header / stats

func _header(d: Defs.CharDef) -> Control:
	var head: HBoxContainer = UITheme.hbox(UITheme.SP3)
	var disc: GlyphDisc = GlyphDisc.new(d, 60)
	disc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(disc)
	var v: VBoxContainer = UITheme.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm: HBoxContainer = UITheme.hbox(UITheme.SP2)
	var name_l: Label = UITheme.label(d.name, "BlackLabel", 24)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(name_l)
	var role: PanelContainer = UITheme.badge(DB.role_label(d.role), UITheme.role_color(d.role), "strong")
	role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(role)
	v.add_child(nm)
	var beh: String = str(d.behavior.get("label", "")).strip_edges()
	# world_tree / engineer carry their summary sentence as the label: don't repeat it.
	if beh != "" and beh != d.summary.strip_edges():
		v.add_child(UITheme.wrap_label("성향 · " + beh, "CaptionLabel", UITheme.FS_CAPTION))
	if not d.tags.is_empty():
		var tags: HFlowContainer = _flow(4)
		for t in d.tags:
			tags.add_child(UITheme.badge(DB.tag_label(t), UITheme.TEXT_FAINT, "soft"))
		v.add_child(tags)
	head.add_child(v)
	return head


func _no_basic(d: Defs.CharDef) -> bool:
	return d.has_rule("no_basic") or d.id == "politician"


func _stats(d: Defs.CharDef) -> Control:
	var no_basic: bool = _no_basic(d)
	var v: VBoxContainer = UITheme.vbox(UITheme.SP2)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var tile_style: StyleBoxFlat = UITheme.sbc(Color(1, 1, 1, 0.025), UITheme.LINE, UITheme.R_M, 1, 8, 6)
	for row in STAT_ROWS:
		var key: String = row[1]
		var value: float = d.stat(key)
		var text: String = row[2] % value
		var color: Color = UITheme.TEXT
		if no_basic and key in ["attackSpeed", "attackRange"]:
			text = "—"
			color = UITheme.TEXT_FAINT
		var tile: PanelContainer = UITheme.stat_tile(row[0], text, color, _stat_tip(d, key, value, no_basic))
		tile.add_theme_stylebox_override("panel", tile_style)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
	v.add_child(grid)
	# Hidden combat numbers made visible: crit (basic attacks only) and tenacity.
	var extra: HFlowContainer = _flow(4)
	if no_basic:
		extra.add_child(UITheme.badge("평타 없음", UITheme.BAD, "soft", NO_BASIC_TIP))
	else:
		var cc: float = d.stat("critChance")
		var cm: float = d.stat("critMultiplier")
		extra.add_child(UITheme.badge("치명타 %s%% · %s배" % [CodexData.num(cc * 100.0), CodexData.num(cm)], CodexData.term_color("crit", UITheme.GOLD), "soft",
			"치명타 — 평타에만 발생합니다. 확률 %s%%, 피해 %s배입니다." % [CodexData.num(cc * 100.0), CodexData.num(cm)]))
	var ten: float = d.stat("tenacity")
	extra.add_child(UITheme.badge("강인함 %s%%" % CodexData.num(ten * 100.0), CodexData.term_color("tenacity", UITheme.WARN), "soft",
		"강인함 %s%% — %s" % [CodexData.num(ten * 100.0), str(CodexData.STATUS["tenacity"]["desc"])]))
	for b in _rule_badges(d):
		extra.add_child(b)
	v.add_child(extra)
	var summons: Control = _summon_lines(d)
	if summons:
		v.add_child(summons)
	return v


## V2 passive rules that change hidden combat numbers: status tenacity (charm),
## basic-attack armor and the fuel tank.
func _rule_badges(d: Defs.CharDef) -> Array:
	var out: Array = []
	var ten: float = d.stat("tenacity")
	for p in d.passives:
		for r in (p as Dictionary).get("rules", []):
			var rd: Dictionary = r
			match str(rd.get("type", "")):
				"status_tenacity":
					for key in rd:
						if str(key) == "type":
							continue
						var extra_ten: float = float(rd[key])
						var label: String = DB.status_label(str(key))
						out.append(UITheme.badge("%s 강인함 %s%%" % [label, CodexData.num(extra_ten * 100.0)], CodexData.term_color(str(key), UITheme.WARN), "soft",
							"%s 강인함 %s%% — 강인함 %s%%와 곱으로 적용되어 %s 지속 시간이 원래의 %s%%입니다." % [label, CodexData.num(extra_ten * 100.0), CodexData.num(ten * 100.0), label,
								CodexData.num(snappedf((1.0 - ten) * (1.0 - extra_ten) * 100.0, 0.1))]))
				"basic_armor_bonus":
					var armor: float = d.stat("armor")
					var ratio: float = float(rd.get("ratio", 0.3))
					var vs_basic: float = armor * (1.0 + ratio)
					var less: float = 100.0 - 100.0 * (100.0 + armor) / (100.0 + vs_basic)
					out.append(UITheme.badge("평타 피해 저항 · 방어 ×%s" % CodexData.num(1.0 + ratio), CodexData.term_color("basicResist", UITheme.GOLD), "soft",
						"평타로 받는 피해를 계산할 때 방어력이 %d에서 %d로 늘어 같은 물리 피해를 약 %d%% 덜 받습니다.\n%s" % [int(armor), int(round(vs_basic)), int(round(less)), str(CodexData.STATUS["basicResist"]["desc"])]))
				"fuel_tank":
					out.append(UITheme.badge("연료 탱크 체력 %d · 연료 %d" % [int(rd.get("tankHp", 300)), int(rd.get("max", 10))], CodexData.term_color("fuel", UITheme.GOLD), "soft",
						"등 뒤 연료탱크: 체력 %d, 방어·마법 저항 %d. 광역·장판·부채꼴 피해는 %d%%만 받고, 파괴되면 연료가 0이 되며 과열 폭주 %s초 뒤 다시 생깁니다.\n연료 — 최대 %d, 평타 적중마다 +%d." % [
							int(rd.get("tankHp", 300)), int(rd.get("tankArmor", 40)), int(round(float(rd.get("areaTakenRatio", 0.5)) * 100.0)), CodexData.num(float(rd.get("respawn", 10))),
							int(rd.get("max", 10)), int(rd.get("perBasic", 1))]))
	return out


## V2 summon stat lines: the permanent companion (passive rule) and the
## formation / chariot summons of the skills (summon effects with originMode).
func _summon_lines(d: Defs.CharDef) -> Control:
	var rows: Array = []
	for i in d.passives.size():
		var pas: Dictionary = d.passives[i]
		for r in pas.get("rules", []):
			var rd: Dictionary = r
			if str(rd.get("type", "")) != "companion":
				continue
			var speed: float = maxf(float(rd.get("speedMin", 110)), float(rd.get("speedRatio", 1.2)) * d.stat("moveSpeed"))
			var kind: String = str(rd.get("kind", ""))
			var pname: String = str(pas.get("name", ""))
			# "P2" alone when the passive is named after the summon (케르베로스).
			var head: String = "P%d" % (i + 1) if pname == Defs.entity_def(kind, d, 1.0, 1.0, 0.0).name else "P%d · %s" % [i + 1, pname]
			rows.append([kind, head,
				"체력 %d · 방어·마저 %d · 이동 %d · %s초마다 %s · %s초 뒤 부활" % [int(rd.get("hp", 0)), int(rd.get("armor", 0)), int(round(speed)),
					CodexData.num(float(rd.get("interval", 1.0))), _attack_text(rd.get("attack", {})), CodexData.num(float(rd.get("respawn", 15)))]])
	for a in d.abilities:
		var ab: Defs.AbilityDef = a
		for f in ab.effects:
			if not (f is Dictionary) or str(f.get("type", "")) != "summon" or str(f.get("originMode", "")) == "":
				continue
			var fd: Dictionary = f
			var kind: String = str(fd.get("originEntity", ""))
			var head: String = "S%d · %s" % [ab.slot, ab.name]
			var count: int = int(fd.get("count", 1))
			var dur: String = CodexData.num(float(fd.get("duration", 0)))
			if str(fd.originMode) == "chariot":
				var knock: Dictionary = fd.get("knock", {})
				rows.append([kind, head, "무적·대상 지정 불가 · 반지름 %d · 이동 %d · %s초 · 접촉 %s, 넉백 %d · 적마다 최대 %d회" % [int(fd.get("radius", 30)), int(fd.get("speed", 300)), dur,
					_attack_text(fd.get("attack", {})), int(knock.get("distance", 130)), int(fd.get("maxKnocks", 2))]])
			else:
				var hp: float = float(fd.get("hp", 0)) + float(fd.get("hpSelfMaxHp", 0)) * d.stat("maxHealth")
				rows.append([kind, head, "%d기 · 체력 %d · 방어·마저 %d · %s초 · %s초마다 %s(%d 안의 적)" % [count, int(hp), int(fd.get("armor", 0)), dur,
					CodexData.num(float(fd.get("interval", 1.0))), _attack_text(fd.get("attack", {})), int(fd.get("reach", 24))]])
	if rows.is_empty():
		return null
	var v: VBoxContainer = UITheme.vbox(4)
	for row in rows:
		var entity: Defs.CharDef = Defs.entity_def(str(row[0]), d, 1.0, 1.0, 0.0)
		var line: HBoxContainer = UITheme.hbox(UITheme.SP2)
		var tile: Label = UITheme.glyph_tile(entity.glyph, d.accent, 24)
		tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(tile)
		var text: VBoxContainer = UITheme.vbox(0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row: HBoxContainer = UITheme.hbox(6)
		name_row.add_child(UITheme.label(entity.name, "BoldLabel", UITheme.FS_CAPTION))
		name_row.add_child(UITheme.label(str(row[1]), "FaintLabel", UITheme.FS_MICRO))
		text.add_child(name_row)
		var stats: RichTextLabel = UITheme.rich(CodexText.rich_desc(str(row[2])), UITheme.FS_CAPTION)
		stats.add_theme_color_override("default_color", UITheme.TEXT_DIM)
		text.add_child(stats)
		line.add_child(text)
		v.add_child(line)
	return UITheme.styled_panel(UITheme.sbc(Color(d.accent, 0.04), Color(d.accent, 0.22), UITheme.R_M, 1, 10, 8), v)


func _attack_text(attack: Variant) -> String:
	if not (attack is Dictionary):
		return ""
	var at: Dictionary = attack
	var text: String = CodexData.num(float(at.get("base", 0)))
	if float(at.get("ad", 0)) > 0.0:
		text += "+%sAD" % CodexData.num(float(at.ad))
	if float(at.get("ap", 0)) > 0.0:
		text += "+%sAP" % CodexData.num(float(at.ap))
	return "%s %s 피해" % [text, str(DB.SCHOOL_LABELS.get(str(at.get("school", "physical")), ""))]


func _stat_tip(d: Defs.CharDef, key: String, value: float, no_basic: bool) -> String:
	match key:
		"maxHealth":
			return "최대 체력입니다.\n강인함 %s%% — 받는 군중 제어 지속 시간이 그만큼 줄어듭니다(에어본·제압·조종 제외)." % CodexData.num(d.stat("tenacity") * 100.0)
		"attackDamage":
			if no_basic:
				return "스킬의 AD 계수에 곱해지는 값입니다. 평타는 하지 않습니다."
			return "평타 피해와 스킬의 AD 계수에 곱해지는 값입니다.\n치명타(평타에만): 확률 %s%% · 피해 %s배" % [CodexData.num(d.stat("critChance") * 100.0), CodexData.num(d.stat("critMultiplier"))]
		"abilityPower":
			return "스킬의 AP 계수에 곱해지는 값입니다."
		"armor":
			return "받는 물리 피해를 약 %d%% 줄입니다(피해 ×100÷(100+방어))." % int(round(100.0 - 10000.0 / (100.0 + value)))
		"magicResistance":
			return "받는 마법 피해를 약 %d%% 줄입니다(피해 ×100÷(100+마법 저항))." % int(round(100.0 - 10000.0 / (100.0 + value)))
		"attackSpeed":
			return NO_BASIC_TIP if no_basic else "1초에 평타를 하는 횟수입니다."
		"moveSpeed":
			return "1초에 이동하는 거리입니다."
		"attackRange":
			return NO_BASIC_TIP if no_basic else "평타가 닿는 거리입니다."
	return ""


# ------------------------------------------------------------------ skills

func _skills(d: Defs.CharDef) -> Control:
	var v: VBoxContainer = UITheme.vbox(UITheme.SP2)
	var hint: String = "카드를 누르면 시연을 재생합니다" if preview_enabled else "패시브 %d · 스킬 %d" % [d.passives.size(), d.abilities.size()]
	v.add_child(UITheme.section_header("스킬", hint))
	for i in d.passives.size():
		var pas: Dictionary = d.passives[i]
		var p_desc: String = str(pas.get("description", ""))
		var p_title: String = "패시브 · %s" % str(pas.get("name", ""))
		v.add_child(_card("passive", i, "P%d" % (i + 1), Color(d.accent, 1.0), p_title, CodexText.passive_meta(pas), "", p_desc))
	for a in d.abilities:
		var ab: Defs.AbilityDef = a
		var geo: String = CodexText.clean_geometry(ab)
		if geo == "자신":
			geo = ""
		v.add_child(_card("active", ab.index, VfxStyle.glyph_for(ab), ab.color, "S%d  %s" % [ab.slot, ab.name], CodexText.ability_meta(ab), geo, ab.description))
	return v


func _card(kind: String, index: int, glyph: String, col: Color, title: String, meta: Array, geometry: String, desc: String) -> PanelContainer:
	var key: String = "%s:%d" % [kind, index]
	var card: PanelContainer = PanelContainer.new()
	var v: VBoxContainer = UITheme.vbox(UITheme.SP2)
	card.add_child(v)

	var head: HBoxContainer = UITheme.hbox(10)
	head.add_child(UITheme.glyph_tile(glyph, col, 34))
	var title_l: Label = UITheme.wrap_label(title, "BoldLabel", UITheme.FS_BODY)
	title_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title_l)
	if preview_enabled:
		var button: Button = UITheme.button("▶", "ChipButton", func(): _request(kind, index), "%s 시연을 재생합니다." % title.replace("  ", " "))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(34, 28)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.set_pressed_no_signal(key == selected_skill)
		preview_buttons[key] = button
		head.add_child(button)
	v.add_child(head)

	if not meta.is_empty():
		var chips: HFlowContainer = _flow(4)
		for m in meta:
			chips.add_child(UITheme.badge(str(m.text), m.color, "soft", str(m.get("tip", ""))))
		v.add_child(chips)
	if geometry != "":
		var geo: Label = UITheme.wrap_label("범위 · " + geometry.replace(", ", " · "), "FaintLabel", UITheme.FS_CAPTION)
		geo.tooltip_text = "스킬의 판정 범위와 투사체 정보입니다."
		geo.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(geo)
	if desc != "":
		var rich: RichTextLabel = UITheme.rich(CodexText.rich_desc(desc), UITheme.FS_SM)
		rich.add_theme_color_override("default_color", UITheme.TEXT_DIM)
		v.add_child(rich)
	var effects: Control = _effects_row(desc, meta)
	if effects:
		v.add_child(effects)

	skill_cards[key] = card
	if preview_enabled:
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(kind, index))
		card.mouse_entered.connect(_on_card_hover.bind(key, true))
		card.mouse_exited.connect(_on_card_hover.bind(key, false))
	_style_card(key)
	return card


## "효과" row: glossary terms of the description that the meta chips do not already show.
func _effects_row(desc: String, meta: Array) -> Control:
	var shown: String = ""
	for m in meta:
		shown += str(m.text) + "|"
	var keys: Array = []
	for k in CodexText.terms_in(desc):
		if k in NON_EFFECT_TERMS or shown.contains(CodexData.term_label(k)):
			continue
		keys.append(k)
	if keys.is_empty():
		return null
	var row: HFlowContainer = _flow(4)
	var cap: Label = UITheme.label("효과", "FaintLabel", UITheme.FS_MICRO)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.custom_minimum_size.x = 30
	row.add_child(cap)
	for k in keys:
		var st: Dictionary = CodexData.STATUS[k]
		row.add_child(UITheme.badge(str(st.label), CodexData.term_color(k), "soft", "%s — %s" % [str(st.label), str(st.desc)]))
	return row


func _request(kind: String, index: int) -> void:
	set_selected_skill(kind, index)
	skill_requested.emit(kind, index)


func _on_card_input(event: InputEvent, kind: String, index: int) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_request(kind, index)


func _on_card_hover(key: String, inside: bool) -> void:
	if inside:
		_hovered = key
	elif _hovered == key:
		_hovered = ""
	_style_card(key)


func _style_card(key: String) -> void:
	var card: PanelContainer = skill_cards.get(key)
	if card == null:
		return
	var style: StyleBoxFlat
	if key == selected_skill:
		style = UITheme.sbc(Color(UITheme.ACCENT, 0.075), UITheme.ACCENT, UITheme.R_M, 2, 12, 10)
	elif key == _hovered:
		style = UITheme.sbc(Color(1, 1, 1, 0.045), UITheme.LINE2.lerp(UITheme.ACCENT, 0.4), UITheme.R_M, 1, 12, 10)
	else:
		style = UITheme.sbc(Color(1, 1, 1, 0.022), UITheme.LINE, UITheme.R_M, 1, 12, 10)
	card.add_theme_stylebox_override("panel", style)


# ------------------------------------------------------------------ AI doctrine / nexus

func _ai_section(d: Defs.CharDef) -> Control:
	var prof: Dictionary = Doctrine.of(d.id)
	var has_doctrine: bool = not d.doctrine.is_empty() or not prof.is_empty()
	var nx: Dictionary = d.nexus
	if not has_doctrine and nx.is_empty():
		return null
	var v: VBoxContainer = UITheme.vbox(UITheme.SP2)
	v.add_child(UITheme.section_header("AI 전술", "전술가 AI가 이 영웅을 운용하는 방식"))
	if has_doctrine:
		v.add_child(_doctrine_card(d, prof))
	if not nx.is_empty():
		v.add_child(_nexus_card(d, nx))
	return v


func _doctrine_card(d: Defs.CharDef, prof: Dictionary) -> Control:
	var dv: VBoxContainer = UITheme.vbox(6)
	var code: String = str(prof.get("code", d.doctrine.get("code", "")))
	dv.add_child(UITheme.label("교리 · " + code if code != "" else "교리", "EyebrowLabel", 0, d.accent.lightened(0.35)))
	var title: String = str(prof.get("title", d.doctrine.get("title", "")))
	if title != "":
		dv.add_child(UITheme.wrap_label(title, "SubheadLabel", UITheme.FS_H2))
	var identity: String = str(d.doctrine.get("identity", ""))
	if identity != "" and identity.strip_edges() != d.summary.strip_edges():
		dv.add_child(UITheme.wrap_label(identity, "DimLabel", UITheme.FS_CAPTION))
	var roles: Array = prof.get("roles", [])
	if not roles.is_empty():
		var rf: HFlowContainer = _flow(4)
		for rr in roles:
			rf.add_child(UITheme.badge(str(Doctrine.ROLE_LABEL.get(rr, rr)), d.accent, "soft"))
		dv.add_child(rf)
	var principles: Array = prof.get("principles", [])
	if not principles.is_empty():
		var pv: VBoxContainer = UITheme.vbox(3)
		for pl in principles:
			pv.add_child(_bullet(str(pl)))
		dv.add_child(pv)
	var combos: Array = prof.get("combos", [])
	for cb in combos:
		var row: HBoxContainer = UITheme.hbox(UITheme.SP2)
		var b: PanelContainer = UITheme.badge("연계", d.accent, "outline")
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(b)
		row.add_child(UITheme.wrap_label(str(cb), "CaptionLabel", UITheme.FS_CAPTION))
		dv.add_child(row)
	return UITheme.styled_panel(UITheme.sbc(Color(d.accent, 0.06), Color(d.accent, 0.3), UITheme.R_M, 1, 12, 10), dv)


func _nexus_card(d: Defs.CharDef, nx: Dictionary) -> Control:
	var av: VBoxContainer = UITheme.vbox(6)
	av.add_child(UITheme.label("전술가 AI 운용", "EyebrowLabel"))
	var identity: String = str(nx.get("identity", ""))
	if identity != "" and identity.strip_edges() != d.summary.strip_edges():
		av.add_child(UITheme.wrap_label(identity, "DimLabel", UITheme.FS_CAPTION))
	var skills: Array = nx.get("skills", [])
	for i in skills.size():
		var row: HBoxContainer = UITheme.hbox(UITheme.SP2)
		# Label by slot only while the index is a real ability (politician has 3 skills, 4 notes).
		var tag: String = "S%d" % (i + 1) if i < d.abilities.size() else "운용"
		var b: PanelContainer = UITheme.badge(tag, UITheme.TEXT_DIM, "outline")
		b.custom_minimum_size.x = 42
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(b)
		row.add_child(UITheme.wrap_label(str(skills[i]), "CaptionLabel", UITheme.FS_CAPTION))
		av.add_child(row)
	return UITheme.styled_panel(UITheme.sbc(Color(1, 1, 1, 0.022), UITheme.LINE, UITheme.R_M, 1, 12, 10), av)


# ------------------------------------------------------------------ helpers

func _flow(sep: int) -> HFlowContainer:
	var f: HFlowContainer = HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


func _bullet(text: String) -> Control:
	var row: HBoxContainer = UITheme.hbox(6)
	var dot: Label = UITheme.label("·", "BoldLabel", UITheme.FS_CAPTION, UITheme.TEXT_FAINT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dot)
	row.add_child(UITheme.wrap_label(text, "BodyLabel", UITheme.FS_CAPTION))
	return row
