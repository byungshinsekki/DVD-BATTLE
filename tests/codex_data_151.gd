extends SceneTree

# V1.5.1 codex knowledge layer: CodexData (glossary, item details, rules,
# hazards), CodexText (rich descriptions, glossary terms, skill chips) and the
# ItemViews builders. Numbers are cross-checked against the live item and arena
# data so the codex can never drift from the simulation.

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}
var _tag_re: RegEx


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _run() -> void:
	DB.ensure_loaded()
	DB.load_fonts()
	_tag_re = RegEx.new()
	_tag_re.compile("\\[(/?)([a-z]+)(?:=[^\\]]*)?\\]")
	_glossary()
	_glyphs()
	_items()
	_hazards()
	await _rich_text()
	_meta()
	_views()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("CODEX_DATA_151 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	var path: String = "res://reports/codex_data_151.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			path = arg.substr(9)
	if path != "":
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"suite": "codex_data_151", "status": status, "passed": passed, "failed": failed, "metrics": metrics}, "  "))
	quit(0 if failed.is_empty() else 1)


# ------------------------------------------------------------------ glossary

const REQUIRED_TERMS := ["stun", "root", "silence", "airborne", "suppression", "charm", "taunt", "sleep", "control",
	"slow", "disarm", "knockback", "pull", "invulnerable", "unstoppable", "untargetable", "invisible", "shield",
	"healReduction", "sniperVulnerable", "damageAmp", "confusion", "plague", "infection", "hooked", "pain",
	"imprisoned", "contemplation", "distrust", "bladeMark", "bladeTrace", "frenzy", "projectile_guard", "tenacity",
	"physical", "magic", "true", "crit", "dot", "execute", "lifesteal", "cooldown", "zone", "summon",
	# V2 heroes (DESIGN_V2 §2.8): 정화, 회복 불가, 전방 방패/무적, 연료, 과열 폭주, 차징, 암흑시야, 평타 저항, 유혹 강인함, 포효
	"cleanse", "healBlock", "frontGuard", "fuel", "overdrive", "charge", "concealed", "basicResist", "charmTenacity", "roar"]


func _glossary() -> void:
	var bad: Array = []
	for k in CodexData.STATUS:
		var d: Dictionary = CodexData.STATUS[k]
		var ok: bool = str(d.get("label", "")) != "" and str(d.get("desc", "")).length() >= 10 and str(d.get("icon", "")) != ""
		ok = ok and Color.html_is_valid(str(d.get("color", ""))) and CodexData.CATEGORIES.has(str(d.get("category", "")))
		ok = ok and d.get("aliases") is Array
		if not ok:
			bad.append(k)
		if str(d.get("desc", "")).contains("[") or str(d.get("desc", "")).contains("]"):
			bad.append(k + ":bracket")
	_check(bad.is_empty(), "every glossary entry has label, icon, colour, category, desc, aliases %s" % str(bad))
	var missing: Array = []
	for k in REQUIRED_TERMS:
		if not CodexData.STATUS.has(k):
			missing.append(k)
	_check(missing.is_empty(), "glossary covers every DESIGN §4 term %s" % str(missing))
	metrics["glossary_terms"] = CodexData.STATUS.size()
	var lookup_bad: Array = []
	for k in CodexData.STATUS:
		var d: Dictionary = CodexData.STATUS[k]
		if CodexData.term_for_label(str(d.label)) != k:
			lookup_bad.append(str(d.label))
		for a in d.aliases:
			if CodexData.term_for_label(str(a)) != k:
				lookup_bad.append(str(a))
	_check(lookup_bad.is_empty(), "term_for_label resolves every label and alias %s" % str(lookup_bad))
	_check(CodexData.term_for_label("공중에 뜸") == "airborne" and CodexData.term_for_label("강제 도발") == "taunt", "aliases 공중에 뜸 / 강제 도발")
	_check(CodexData.term_for_label("회복 불가") == "healBlock" and CodexData.term_for_label("치유 감소") == "healReduction" and CodexData.term_for_label("매혹") == "charm"
		and CodexData.term_for_label("매혹 강인함") == "charmTenacity" and CodexData.term_for_label("전방 무적") == "frontGuard" and CodexData.term_for_label("은신") == "concealed", "V2 terms: 회복 불가 distinct from 치유 감소, aliases 매혹 / 전방 무적 / 은신")
	_check(CodexData.term_for_label("stun") == "stun" and CodexData.term_for_label("없는 용어") == "", "term_for_label accepts keys and rejects unknown text")
	_check(CodexData.status("root").get("key", "") == "root" and CodexData.status("속박").get("key", "") == "root", "status() by key and by label")
	var cats: Array = CodexData.categories()
	_check(cats == ["군중 제어", "해로운 효과", "이로운 효과", "표식·자원", "피해·규칙"], "categories in DESIGN order")
	var empty_cat: Array = []
	for c in cats:
		if CodexData.terms_in_category(str(c)).is_empty():
			empty_cat.append(c)
	_check(empty_cat.is_empty(), "every category has terms %s" % str(empty_cat))
	_check(DB.status_label("airborne") == "에어본" and DB.status_label("taunt") == "도발", "DB status labels use glossary names")
	# Every status the character data applies has a glossary entry.
	var unknown: Array = []
	for c in DB.characters:
		for a in c.abilities:
			for st in _statuses_in(a.effects):
				if not CodexData.STATUS.has(st) and not unknown.has(st):
					unknown.append(st)
	_check(unknown.is_empty(), "every applied status is in the glossary %s" % str(unknown))
	_check(CodexData.ARENA_KIND_LABELS.get("elimination") == "섬멸전" and CodexData.ARENA_KIND_LABELS.get("control") == "거점 장악" and CodexData.ARENA_KIND_LABELS.get("deathmatch") == "개인전", "arena kind labels")


func _statuses_in(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			out.append_array(_statuses_in(x))
	elif v is Dictionary:
		if str(v.get("type", "")) in ["status", "mark"] and v.has("status"):
			out.append(str(v.status))
		for k in v:
			if v[k] is Array or v[k] is Dictionary:
				out.append_array(_statuses_in(v[k]))
	return out


# ------------------------------------------------------------------ glyphs

func _glyphs() -> void:
	var fonts: Array = []
	for p in ["res://assets/fonts/ui_regular.otf", "res://assets/fonts/ui_bold.otf", "res://assets/fonts/ui_black.otf",
			"res://assets/fonts/glyph_serif.otf", "res://assets/fonts/symbols.ttf"]:
		var f: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		if f is Font:
			fonts.append(f)
	_check(fonts.size() == 5, "bundled fonts load")
	var icons: Array = []
	for k in CodexData.STATUS:
		icons.append([k, str(CodexData.STATUS[k].icon)])
	for k in CodexData.HAZARDS:
		icons.append(["hazard:" + str(k), str(CodexData.HAZARDS[k].icon)])
	icons.append(["cover", str(CodexData.COVER.icon)])
	for k in CodexData.LOW_TERRAIN:
		icons.append(["terrain:" + str(k), str(CodexData.LOW_TERRAIN[k][1])])
	var missing: Array = []
	for pair in icons:
		for ch in str(pair[1]):
			var have: bool = false
			for f in fonts:
				if (f as Font).has_char(ch.unicode_at(0)):
					have = true
					break
			if not have:
				missing.append("%s(%s)" % [pair[0], ch])
	_check(missing.is_empty(), "every codex icon exists in a bundled font %s" % str(missing))
	var glyph_font_missing: Array = []
	for pair in icons:
		for ch in str(pair[1]):
			if not DB.font_glyph.has_char(ch.unicode_at(0)):
				glyph_font_missing.append(ch)
	_check(glyph_font_missing.is_empty(), "every codex icon renders through DB.font_glyph %s" % str(glyph_font_missing))
	metrics["icons_checked"] = icons.size()


# ------------------------------------------------------------------ items

func _n(v: float) -> String:
	return CodexData.num(v)


func _joined(id: String) -> String:
	return " ".join(CodexData.item_details(id))


func _items() -> void:
	var short: Array = []
	var long_lines: int = 0
	for id in ItemDefs.ORDER:
		var lines: Array = CodexData.item_details(str(id))
		if lines.size() < 2 or lines.size() > 4:
			short.append(id)
		for l in lines:
			if str(l).strip_edges() == "" or str(l).contains("["):
				short.append(str(id) + ":empty")
			if str(l).length() > 90:
				long_lines += 1
	_check(short.is_empty(), "every item has 2-4 detail lines %s" % str(short))
	_check(long_lines == 0, "detail lines stay short (<= 90 chars)")
	var extra: Array = []
	for k in CodexData.ITEM_DETAILS:
		if not ItemDefs.DEFS.has(k):
			extra.append(k)
	_check(extra.is_empty(), "no detail lines for unknown items %s" % str(extra))
	var tag_missing: Array = []
	for id in ItemDefs.ORDER:
		for t in ItemDefs.get_def(str(id)).get("tags", []):
			if not CodexData.ITEM_TAG_LABELS.has(str(t)) and not tag_missing.has(t):
				tag_missing.append(t)
	_check(tag_missing.is_empty(), "every item tag has a Korean label %s" % str(tag_missing))
	var sum: float = 0.0
	for id in ItemDefs.ORDER:
		sum += CodexData.item_chance(str(id))
	_check(absf(sum - 100.0) < 0.01, "per-item chances sum to 100%")
	_check(absf(CodexData.item_chance("c_blade") - 5.5) < 0.001 and absf(CodexData.item_chance("l_heart") - 1.25) < 0.001, "per-item chance = weight / count")
	_check(absf(CodexData.rarity_chance(0) - 44.0) < 0.001 and absf(CodexData.rarity_chance(4) - 5.0) < 0.001, "rarity chances 44..5")

	# Numbers in the detail lines come from the item data.
	var D: Dictionary = ItemDefs.DEFS
	var expect: Dictionary = {
		"c_blade": ["%s%%" % _n(D.c_blade.stats.attackDamage * 100.0)],
		"c_tome": ["%s%%" % _n(D.c_tome.stats.abilityPower * 100.0)],
		"c_leather": [_n(D.c_leather.flat.armor)],
		"c_charm": [_n(D.c_charm.flat.magicResistance)],
		"c_boots": ["%s%%" % _n(D.c_boots.stats.moveSpeed * 100.0)],
		"c_belt": [_n(D.c_belt.flat.maxHealth), "현재 체력은 그대로"],
		"c_gloves": ["%s%%" % _n(D.c_gloves.stats.attackSpeed * 100.0)],
		"c_spyglass": [_n(560.0 + D.c_spyglass.vision), _n(110.0 + D.c_spyglass.forest_reveal),
			_n(D.e_shadow.shadow.reveal), _n(D.e_shadow.shadow.reveal + D.c_spyglass.forest_reveal * 0.5)],
		"r_fang": ["%s%%" % _n(D.r_fang.omnivamp * 100.0)],
		"r_dagger": ["%s%%" % _n(D.r_dagger.bleed.ratio / D.r_dagger.bleed.duration * 100.0), "%s초" % _n(D.r_dagger.bleed.duration), "갱신"],
		"r_hourglass": ["%s%%" % _n(D.r_hourglass.cdr * 100.0), "40%", "%s%%" % _n((D.r_hourglass.cdr + D.m_chrono.cdr) * 100.0)],
		"r_thorns": ["%s%%" % _n(D.r_thorns.thorns * 100.0), "평타"],
		"r_moss": ["%s초" % _n(D.r_moss.regen.delay), "%s%%" % _n((0.015 + D.r_moss.regen.ratio) * 100.0)],
		"r_axe": ["%s%%" % _n(D.r_axe.execute.below * 100.0), "%s배" % _n(1.0 + D.r_axe.execute.bonus)],
		"e_string": ["+%s" % _n(D.e_string.range.ranged), "+%s" % _n(D.e_string.range.melee), "%s%%" % _n(D.e_string.stats.projectileSpeed * 100.0)],
		"e_guard": ["%s%%" % _n(D.e_guard.guard.below * 100.0), "%s%%" % _n(D.e_guard.guard.shield * 100.0),
			"%s초" % _n(D.e_guard.guard.duration), "%s초" % _n(D.e_guard.guard.cooldown)],
		"e_berserk": ["%s%%" % _n(D.e_berserk.berserk.below * 100.0), "+%s%%" % _n(D.e_berserk.berserk.as * 100.0), "+%s%%" % _n(D.e_berserk.berserk.ad * 100.0)],
		"e_instinct": ["%s%%" % _n(D.e_instinct.hunter.heal * 100.0), "+%s%%" % _n(D.e_instinct.hunter.ms * 100.0), "%s초" % _n(D.e_instinct.hunter.duration)],
		"e_crystal": ["%s%%" % _n(D.e_crystal.stats.abilityPower * 100.0), "%s%%" % _n(D.e_crystal.mr_pen * 100.0)],
		"e_shadow": [_n(D.e_shadow.shadow.reveal), "%s초" % _n(D.e_shadow.shadow.window), "%s%%" % _n(D.e_shadow.shadow.ambush * 100.0)],
		"m_phoenix": ["%s%%" % _n(D.m_phoenix.revive.hp * 100.0), "%s초" % _n(D.m_phoenix.revive.invulnerable)],
		"m_thunder": ["%d번" % int(D.m_thunder.thunder.every), _n(D.m_thunder.thunder.radius),
			"%s+%sAD+%sAP" % [_n(D.m_thunder.thunder.base), _n(D.m_thunder.thunder.ad), _n(D.m_thunder.thunder.ap)]],
		"m_bloodstone": ["%s%%" % _n(D.m_bloodstone.omnivamp * 100.0), "%s%%" % _n(D.m_bloodstone.bloodstone.cap * 100.0), "6초"],
		"m_chrono": ["%s%%" % _n(D.m_chrono.cdr * 100.0), "절반"],
		"l_heart": ["기본 수치", "현재 체력도 즉시"],
		"l_crown": ["%s%%" % _n(D.l_crown.tyrant.per_kill * 100.0), "%d중첩" % int(D.l_crown.tyrant.max), "%s배" % _n(1.0 + D.l_crown.tyrant.per_kill * D.l_crown.tyrant.max)],
		"l_aegis": ["%s%%" % _n(D.l_aegis.aegis.reduction * 100.0), "%s초" % _n(D.l_aegis.aegis.cleanse), "둔화를 제외"],
		"l_hammer": ["%s%%" % _n(D.l_hammer.meteor.splash * 100.0), _n(D.l_hammer.meteor.radius), "%s%%" % _n(D.l_hammer.meteor.slow * 100.0), "%s초" % _n(D.l_hammer.meteor.slow_duration)],
	}
	var wrong: Array = []
	for id in expect:
		var text: String = _joined(str(id))
		for tok in expect[id]:
			if not text.contains(str(tok)):
				wrong.append("%s:%s" % [id, tok])
	_check(wrong.is_empty(), "item detail numbers match ItemDefs %s" % str(wrong))
	_check(expect.size() == ItemDefs.ORDER.size(), "every item has a number cross-check")

	var rules: Array = CodexData.ITEM_RULES
	var rule_text: String = " ".join(CodexData.rule_lines(rules))
	_check(rules.size() >= 6, "item rules exist")
	_check(rule_text.contains("%d칸" % DeathmatchMode.SLOTS) and rule_text.contains("%d개" % DeathmatchMode.MAX_FIELD_ITEMS), "item rules use DeathmatchMode constants")
	_check(rule_text.contains("일반 44%") and rule_text.contains("전설 5%") and rule_text.contains("일반 5.5%") and rule_text.contains("전설 1.25%"), "item rules list rarity and per-item chances")
	_check(not CodexData.CONTROL_RULES.is_empty() and " ".join(CodexData.rule_lines(CodexData.CONTROL_RULES)).contains("%s초 뒤 부활" % CodexData.num(DominationMode.RESPAWN_DELAY)), "control rules use DominationMode constants")
	_check(not CodexData.DM_MAP_RULES.is_empty() and " ".join(CodexData.rule_lines(CodexData.DM_MAP_RULES)).contains("3600×2200"), "deathmatch map rules")


# ------------------------------------------------------------------ hazards

func _hazards() -> void:
	var types: Dictionary = {}
	var wrong: Array = []
	var all_arenas: Array = []
	all_arenas.append_array(ArenaData.LIST)
	all_arenas.append_array(ControlArenaData.all())
	for id in DeathmatchMapData.ORDER:
		all_arenas.append(DeathmatchMapData.build(str(id), 20261001))
	for ad in all_arenas:
		for h in (ad as Dictionary).get("hazards", []):
			var typ: String = str(h.get("type", ""))
			types[typ] = true
			if not CodexData.HAZARDS.has(typ):
				continue
			var desc: String = str(CodexData.HAZARDS[typ].desc)
			var summary: String = CodexData.hazard_summary(h)
			var toks: Array = []
			match typ:
				"lava":
					toks = [_n(h.damage), "%s초" % _n(h.tickInterval)]
				"spikes":
					toks = [_n(h.damage), "%s초" % _n(h.period), "%s초" % _n(h.warningDuration), "%s초" % _n(h.activeDuration),
						"%s초" % _n(h.tickInterval), "%s%%" % _n(float(h.slow) * 100.0)]
				"eruption":
					toks = [_n(h.damage), _n(h.knockback), "%s초" % _n(h.period), "%s초" % _n(h.warningDuration)]
				"wind":
					toks = ["%s초" % _n(float(h.period) * 0.5)]
				"portal":
					toks = ["%s초" % _n(float(h.get("cooldown", 2.5)))]
				"haste":
					toks = ["%s%%" % _n((float(h.speedMultiplier) - 1.0) * 100.0), "%s초" % _n(float(h.duration))]
				"healing_fountain":
					toks = ["%s%%" % _n(float(h.healPercent) * 100.0), "%s초" % _n(float(h.cooldown))]
				"gravity":
					# B4: the gravity summary names its damage per tick.
					toks = [_n(float(h.force)), "%s초" % _n(float(h.period)), "%s초" % _n(float(h.warningDuration)), "%s초" % _n(float(h.activeDuration)),
						"%s초마다" % _n(float(h.get("tickInterval", 0.5))), _n(float(h.damage))]
				"shockwave":
					# B4: the shockwave summary names its knockback.
					toks = [_n(float(h.damage)), "%s초" % _n(float(h.period)), "%s초" % _n(float(h.warningDuration)), "넉백 %s" % _n(float(h.get("knockback", 0.0)))]
				"artillery":
					toks = ["%s초 주기" % _n(float(h.period)), "%s초 예고" % _n(float(h.warningDuration)), "%s발" % _n(float(h.count)),
						"반경 %s" % _n(float(h.radius)), _n(float(h.damage)), "첫 착탄 %s초" % _n(CodexData.artillery_first_impact(h))]
				"jump_pad":
					toks = ["%s초 비행" % _n(float(h.flightTime)), "%s초 재사용" % _n(float(h.cooldown))]
				"closing_ring":
					# damagePercent is a percentage (engine Arena.ring_damage_fraction = value * 0.01).
					toks = ["%s초~%s초" % [_n(float(h.startTime)), _n(float(h.endTime))], "반경 %s → %s" % [_n(float(h.startRadius)), _n(float(h.endRadius))],
						"%s초마다" % _n(float(h.tickInterval)), "최대 체력 %s%%" % _n(float(h.damagePercent))]
					if absf(Arena.ring_damage_fraction(h) * 100.0 - float(h.damagePercent)) > 1e-6:
						wrong.append("%s ring percent semantics" % str(h.get("id", typ)))
				"mud":
					toks = ["-%s%%" % _n(float(h.slow) * 100.0)]
			for t in toks:
				# V1.5.2: descriptions explain rules; per-map summaries carry authored numbers.
				if not summary.contains(str(t)):
					wrong.append("%s summary:%s" % [h.get("id", typ), t])
		# Gates (obstacles with a schedule) and brush (forests) are gimmicks too.
		for o in (ad as Dictionary).get("obstacles", []):
			if (o as Dictionary).has("gate"):
				types["gate"] = true
		if not ((ad as Dictionary).get("forests", []) as Array).is_empty():
			types["brush"] = true
	var missing: Array = []
	for t in types:
		if not CodexData.HAZARDS.has(t):
			missing.append(t)
	# V1.5.3: no fixed type count; every type used anywhere in the map data needs a codex entry.
	_check(missing.is_empty(), "every gimmick type used in map data has a codex entry %s" % str(missing))
	for t in ["artillery", "gate", "jump_pad", "closing_ring", "mud", "brush"]:
		_check(types.has(t), "V1.5.3 gimmick %s is used by the map data" % t)
	_check(wrong.is_empty(), "hazard texts carry the exact arena numbers %s" % str(wrong))
	# B4: rule descriptions mention gravity damage and shockwave knockback.
	_check(str(CodexData.HAZARDS.gravity.desc).contains("피해") and str(CodexData.HAZARDS.gravity.short).contains("피해"), "gravity codex text mentions its damage")
	_check(str(CodexData.HAZARDS.shockwave.desc).contains("밀려") and str(CodexData.HAZARDS.shockwave.short).contains("넉백"), "shockwave codex text mentions its knockback")
	# Cover: body-only terrain (lattice / hedge / chasm) lets sight and projectiles through.
	var cover: String = str(CodexData.COVER.desc)
	_check(cover.contains("이동만") and cover.contains("시야와 투사체") and not cover.contains("투사체를 막"), "cover text matches body-only terrain")
	var body_only_ok: bool = true
	for ad2 in all_arenas:
		for o2 in (ad2 as Dictionary).get("obstacles", []):
			var od2: Dictionary = o2
			if str(od2.get("kind", "")) in ["lattice", "hedge", "chasm"] and (od2.get("blocksProjectiles", true) != false or od2.get("blocksVision", true) != false):
				body_only_ok = false
	_check(body_only_ok, "lattice / hedge / chasm obstacles block bodies only (codex cover rule)")
	var gate_rows: int = 0
	for row in CodexData.arena_gimmicks(DB.arena("ruined_gate")):
		if str(row.type) == "gate":
			gate_rows += 1
			_check(str(row.summary).contains("11초 주기") and str(row.summary).contains("4.5초 열림") and str(row.summary).contains("1.2초 전 경고"), "gate summary carries the schedule %s" % str(row.summary))
	_check(gate_rows == 2, "ruined_gate lists gate groups A and B")
	var brush_rows: int = 0
	for row in CodexData.arena_gimmicks(DB.arena("moon_garden")):
		if str(row.type) == "brush":
			brush_rows += 1
			_check(str(row.label) == "수풀" and str(row.summary).contains("110") and str(row.summary).contains("0.8초"), "brush row (team mode) is 수풀 with the reveal numbers")
	_check(brush_rows == 1, "moon_garden lists its brush")
	_check(CodexData.hazard_label("brush", true) == "숲" and CodexData.hazard_label("brush", false) == "수풀", "brush is 숲 in deathmatch, 수풀 in team modes")
	var facts_ok: Array = []
	for a in DB.arenas:
		var fs: Array = CodexData.arena_layout_facts(a)
		var joined: String = ""
		for f in fs:
			joined += str(f[0]) + "|"
		if not (joined.contains("%s×%s" % [_n(a.width), _n(a.height)]) and joined.contains("출발") and fs.size() >= 4):
			facts_ok.append(a.id)
	_check(facts_ok.is_empty(), "arena layout facts show size, orientation, symmetry and structure %s" % str(facts_ok))
	var low: Array = CodexData.low_terrain(DB.arena("furnace_basin"))
	_check(low.size() == 1 and str(low[0].kind) == "chasm" and str(low[0].detail).contains("용암"), "furnace chasm listed as sunken lava terrain")
	for k in CodexData.HAZARDS:
		var d: Dictionary = CodexData.hazard(str(k))
		_check(str(d.get("label", "")) != "" and str(d.get("desc", "")) != "" and Color.html_is_valid(str(d.get("color", ""))) and str(d.get("short", "")) != "", "hazard %s is complete" % k)
	var expected_cover: int = 0
	for ob in DB.arena("thorn_circuit").obstacles:
		if not bool(ob.get("blocksVision", true)): expected_cover += 1
	_check(CodexData.see_through_count(DB.arena("thorn_circuit")) == expected_cover, "see-through cover matches reworked map geometry")
	var hz: Array = CodexData.arena_hazards(DB.arena("thorn_circuit"))
	var cnt: int = 0
	for e in hz:
		cnt += int(e.count)
	var unique_summaries: Dictionary = {}
	for h in DB.arena("thorn_circuit").hazards:
		unique_summaries[str(h.type) + "|" + CodexData.hazard_summary(h)] = true
	_check(hz.size() == unique_summaries.size() and cnt == DB.arena("thorn_circuit").hazards.size(), "arena_hazards groups identical summaries and retains every reworked hazard")
	var dm: Dictionary = CodexData.dm_counts(DB.deathmatch_preview("dm_forest_village"))
	_check(int(dm.buildings) > 0 and int(dm.forests) > 0 and int(dm.item_spots) > 0, "deathmatch map counts")
	metrics["hazard_types"] = types.keys()


# ------------------------------------------------------------------ rich text

func _balanced(bb: String) -> bool:
	var stack: Array = []
	var pos: int = 0
	for m in _tag_re.search_all(bb):
		if bb.substr(pos, m.get_start() - pos).contains("["):
			return false
		pos = m.get_end()
		var tag: String = m.get_string(2)
		if tag == "lb" or tag == "rb":
			if m.get_string(1) != "":
				return false
			continue
		if m.get_string(1) == "":
			stack.push_back(tag)
		elif stack.is_empty() or str(stack.pop_back()) != tag:
			return false
	if bb.substr(pos).contains("["):
		return false
	return stack.is_empty()


func _rich_text() -> void:
	var rtl: RichTextLabel = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.size = Vector2(600, 400)
	root.add_child(rtl)
	await process_frame
	var texts: Array = []
	for c in DB.characters:
		for p in c.passives:
			texts.append(str(p.get("description", "")))
		for a in c.abilities:
			texts.append(str(a.description))
	texts.append("[b]굵게[/b] 60+0.65AD 기절 [x] 대상 최대 HP 1.5% [hint=a]")
	var unbalanced: Array = []
	var mismatched: Array = []
	var hinted: int = 0
	var t0: int = Time.get_ticks_usec()
	for t in texts:
		var bb: String = CodexText.rich_desc(str(t))
		if not _balanced(bb):
			unbalanced.append(str(t).substr(0, 24))
		rtl.text = bb
		if rtl.get_parsed_text() != str(t):
			mismatched.append(str(t).substr(0, 24))
		if bb.contains("[hint="):
			hinted += 1
	metrics["rich_desc_first_pass_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	rtl.queue_free()
	_check(unbalanced.is_empty(), "rich_desc output is balanced BBCode with every source '[' escaped %s" % str(unbalanced))
	_check(mismatched.is_empty(), "rich_desc shows exactly the source text %s" % str(mismatched))
	_check(float(hinted) >= texts.size() * 0.5, "most descriptions get glossary hints (%d/%d)" % [hinted, texts.size()])
	metrics["descriptions"] = texts.size()
	metrics["descriptions_with_hints"] = hinted
	var t1: int = Time.get_ticks_usec()
	for t in texts:
		CodexText.rich_desc(str(t))
	metrics["rich_desc_cached_ms"] = snappedf((Time.get_ticks_usec() - t1) / 1000.0, 0.01)

	var ad: String = CodexText.rich_desc("60+0.65AD 물리 피해")
	_check(ad.contains("[color=%s][b]+0.65AD[/b][/color]" % CodexText.AD_COLOR) and ad.contains("[b]60[/b]"), "AD ratio coloured, base number bold")
	_check(CodexText.rich_desc("48+0.5AP").contains("[color=%s][b]+0.5AP[/b][/color]" % CodexText.AP_COLOR), "AP ratio coloured")
	_check(CodexText.rich_desc("최대 HP 3% 피해").contains(CodexText.HP_COLOR) and CodexText.rich_desc("대상 최대 체력 1.5%").contains("[b]대상 최대 체력 1.5%[/b]"), "max-HP ratios coloured")
	_check(CodexText.rich_desc("(44+0.25AD+0.03Hmax)×s").contains("[b]+0.03Hmax[/b]"), "legacy Hmax ratio coloured")
	_check(not CodexText.rich_desc("S2~S4 적중").contains("[b]2"), "skill slot names are not numbers")
	var ut: String = CodexText.rich_desc("대상 지정 불가 상태")
	_check(ut.contains("]대상 지정 불가[/color]") and ut.count("[hint=") == 1, "longest glossary match wins")
	_check(CodexText.terms_in("대상 지정 불가 상태") == ["untargetable"], "terms_in longest match")
	_check(CodexText.terms_in("공중에 뜸 1초") == ["airborne"] and CodexText.terms_in("하드 도발 1.6초") == ["taunt"], "terms_in resolves aliases")
	_check(CodexText.terms_in("침묵 1초, 기절 2초, 다시 침묵") == ["silence", "stun"], "terms_in keeps first-appearance order without duplicates")
	_check(CodexText.terms_in("물리 피해와 기절", true) == ["stun"], "terms_in statuses_only skips rule terms")
	var miss_stun: Array = []
	for t in texts:
		if str(t).contains("기절") and not CodexText.terms_in(str(t)).has("stun"):
			miss_stun.append(str(t).substr(0, 20))
		if str(t).contains("속박") and not CodexText.terms_in(str(t)).has("root"):
			miss_stun.append(str(t).substr(0, 20))
	_check(miss_stun.is_empty(), "terms_in finds 기절/속박 wherever they appear %s" % str(miss_stun))


# ------------------------------------------------------------------ chips

func _find_ab(id: String) -> Defs.AbilityDef:
	for c in DB.characters:
		for a in c.abilities:
			if a.id == id:
				return a
	return null


func _texts(chips: Array) -> Array:
	var out: Array = []
	for c in chips:
		out.append(str(c.text))
	return out


func _meta() -> void:
	var empty: Array = []
	var bad_shape: Array = []
	var cond_missing: Array = []
	var chips_total: int = 0
	for c in DB.characters:
		for a in c.abilities:
			var ab: Defs.AbilityDef = a
			var chips: Array = CodexText.ability_meta(ab)
			chips_total += chips.size()
			if chips.is_empty():
				empty.append(ab.id)
			for ch in chips:
				if not (ch is Dictionary) or str(ch.get("text", "")) == "" or not (ch.get("color") is Color) or not ch.has("tip"):
					bad_shape.append(ab.id)
			var has_cond: bool = false
			for ch in chips:
				if str(ch.get("kind", "")) == "condition":
					has_cond = true
			if not ab.condition.is_empty() and not has_cond:
				cond_missing.append(ab.id)
			var has_cast: bool = _texts(chips).any(func(t): return str(t).begins_with("시전"))
			if has_cast != (ab.cast_time >= 0.2 - 0.0001):
				bad_shape.append(ab.id + ":cast")
			var has_range: bool = _texts(chips).any(func(t): return str(t).begins_with("사거리"))
			if has_range != (ab.range > 0.0 and ab.target != "self"):
				bad_shape.append(ab.id + ":range")
		for p in c.passives:
			if CodexText.passive_meta(p).is_empty():
				empty.append(c.id + ":passive")
	metrics["ability_chips"] = chips_total
	_check(empty.is_empty(), "every ability and passive gets chips %s" % str(empty))
	_check(bad_shape.is_empty(), "chips are {text, color, tip} with correct cast/range rules %s" % str(bad_shape))
	_check(cond_missing.is_empty(), "every ability condition becomes a chip %s" % str(cond_missing))
	var expect: Array = [
		["swordsman_4", "조건: 검기 추적"], ["fisherman_4", "조건: 인양"], ["joker_3", "조건: 혼란"], ["hive_mind_3", "조건: 감염"],
		["hive_mind_4", "조건: 조종 중인 대상"], ["torturer_2", "조건: 고통 3중첩"], ["torturer_4", "조건: 감금"],
		["fisherman_3", "조건: 물고기 1마리"], ["plague_doctor_2", "조건: 힐 주머니 보유"], ["nitro_1", "조건: 충격 2스택"],
		["dimensionalist_4", "조건: 차원 조각 30"], ["nitro_2", "조건: 벽 접촉"], ["hermes_3", "조건: 군중 제어된 적"],
		["dimensionalist_3", "조건: 내 포탈 쌍"], ["world_tree_2", "조건: 재생영역"], ["engineer_2", "조건: 포탑 420 이내"],
		["engineer_4", "조건: 포탑 100 이내"], ["sniper_1", "시전 0.8초"], ["swordsman_1", "사거리 150"],
		["swordsman_4", "고정 피해"], ["mage_1", "마법 피해"], ["torturer_1", "물리 피해"], ["engineer_2", "마법 피해"],
		["hades_1", "암흑시야 전용"], ["war_machine_1", "연료 1 소모"], ["war_machine_2", "연료 2~6 소모"], ["war_machine_2", "차징 2~6발"],
		["war_machine_2", "시전 0.2~1.4초"], ["war_machine_4", "연료 7 소모"], ["torquemada_2", "조건: CC 출처 8초 이내"],
	]
	var wrong: Array = []
	for pair in expect:
		var ab2: Defs.AbilityDef = _find_ab(str(pair[0]))
		if ab2 == null or not _texts(CodexText.ability_meta(ab2)).has(str(pair[1])):
			wrong.append("%s→%s" % [pair[0], pair[1]])
	_check(wrong.is_empty(), "condition, cast, range and school chips %s" % str(wrong))
	var no_school: Array = []
	for id in ["aphrodite_1", "politician_1", "torturer_2", "werewolf_3"]:
		var ab3: Defs.AbilityDef = _find_ab(id)
		if ab3 and CodexText.school_of(ab3) != "":
			no_school.append(id)
	_check(no_school.is_empty(), "no school chip for skills without damage %s" % str(no_school))
	_check(CodexText.clean_geometry(_find_ab("world_tree_1")) == "" and CodexText.clean_geometry(_find_ab("world_tree_2")) == "", "clean_geometry drops duplicate 사거리 and 사거리 0")
	_check(CodexText.clean_geometry(_find_ab("mage_2")) == "반경 82" and CodexText.clean_geometry(_find_ab("swordsman_3")) == "폭 26, 속도 420", "clean_geometry keeps other fragments")
	_check(CodexText.clean_geometry(_find_ab("engineer_4")) == "" and CodexText.dedupe_geometry([], "사거리 100, 반경 20") == "사거리 100, 반경 20", "clean_geometry keeps range fragments no chip repeats")
	_check(CodexText.school_of(_find_ab("nitro_3")) == "magic" and CodexText.school_of(_find_ab("hive_mind_2")) == "", "school falls back to text; zero-damage effects ignored")
	var sw4: Defs.AbilityDef = _find_ab("swordsman_4")
	_check(CodexText.dedupe_geometry(CodexText.ability_meta(sw4), sw4.geometry) == "", "dedupe_geometry uses the meta chips")
	var pm: Array = _texts(CodexText.passive_meta(DB.char_def("nitro").passives[0]))
	_check(pm.has("패시브 · 자동 발동") and pm.has("충격 최대 8스택"), "passive chips include resources")
	_check(_texts(CodexText.passive_meta(DB.char_def("politician").passives[0])).has("평타 없음"), "politician passive notes no basic attacks")
	var idx: Dictionary = CodexText.term_index()
	_check((idx.get("stun", []) as Array).has("sniper") and (idx.get("control", []) as Array).has("hive_mind") and (idx.get("imprisoned", []) as Array).has("torturer"), "term_index lists heroes per term")
	metrics["terms_used"] = idx.size()


# ------------------------------------------------------------------ views

func _find_text(n: Node, s: String) -> bool:
	if (n is Label and (n as Label).text.contains(s)) or (n is Button and (n as Button).text.contains(s)):
		return true
	for c in n.get_children():
		if _find_text(c, s):
			return true
	return false


func _count(n: Node, cls: String) -> int:
	var k: int = 1 if n.is_class(cls) else 0
	for c in n.get_children():
		k += _count(c, cls)
	return k


func _noop(_x: String) -> void:
	pass


func _views() -> void:
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var compact: Control = ItemViews.codex_list()
	_check(_find_text(compact, "용의 심장") and _find_text(compact, "전설 4종"), "compact codex_list has Labels 용의 심장 and 전설 4종")
	_check(_find_text(compact, "일반 8종") and _find_text(compact, "레어 6종"), "codex_list has every rarity header")
	compact.free()
	var sel: Control = ItemViews.codex_list(false, Callable(self, "_noop"))
	_check(_count(sel, "Button") == ItemDefs.ORDER.size(), "selectable codex_list has one Button per item")
	ItemViews.select(sel, "l_heart")
	var rows: Dictionary = sel.get_meta("rows")
	_check((rows["l_heart"] as Button).button_pressed and not (rows["c_blade"] as Button).button_pressed, "select() marks one row")
	_check(ItemViews.filter(sel, "심장") == 1 and ItemViews.filter(sel, "", 4) == 4 and ItemViews.filter(sel) == ItemDefs.ORDER.size(), "filter() by name and rarity")
	sel.free()
	var hdr: Control = ItemViews.rarity_header(4)
	_check(_find_text(hdr, "전설 4종") and _find_text(hdr, "개별 1.3%"), "rarity_header text")
	hdr.free()
	var bad: Array = []
	for id in ItemDefs.ORDER:
		var nm: String = str(ItemDefs.get_def(str(id)).name)
		var dv: Control = ItemViews.detail(str(id), Callable(self, "_noop"))
		if not _find_text(dv, nm) or not _find_text(dv, "잘 맞는 영웅 TOP 5") or not _find_text(dv, "효과가 적은 영웅"):
			bad.append(id)
		dv.free()
		var lr: Control = ItemViews.list_row(str(id), true)
		if not _find_text(lr, nm):
			bad.append(str(id) + ":row")
		lr.free()
		var sr: Button = ItemViews.selectable_row(str(id), Callable())
		if not _find_text(sr, nm):
			bad.append(str(id) + ":sel")
		sr.free()
	_check(bad.is_empty(), "detail/list_row/selectable_row build for all 28 items %s" % str(bad))
	var ro: Control = ItemViews.detail("c_gloves")
	_check(_count(ro, "Button") == 0 and _find_text(ro, "정치가"), "detail without on_hero is read-only and lists the least-fit hero")
	ro.free()
	var rc: Control = ItemViews.rules_card()
	_check(_find_text(rc, "아이템 규칙") and _find_text(rc, "보유 %d칸" % DeathmatchMode.SLOTS), "rules_card lists the item rules")
	rc.free()
	var after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	metrics["node_leak"] = after - before
	_check(after == before, "item views free cleanly (nodes %d -> %d)" % [before, after])
