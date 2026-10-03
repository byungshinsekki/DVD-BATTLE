extends Node

# Full-app codex flow (V1.5.1): the four codex modes (characters, arenas, items,
# glossary), deep links through on_show, cross links (item/glossary -> hero),
# the SkillPreview lifecycle across modes and the read-only player records.
# Needs an isolated QA project (custom user dir containing "QA").

var checks: int = 0
var failures: int = 0
var records: Array = []
var shots: Dictionary = {}
var measurements: Dictionary = {}


func _ready() -> void:
	var isolated: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not isolated or not directory.to_upper().contains("QA"):
		push_error("UI validation requires an isolated QA project with a custom QA user directory.")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):
			shots["dir"] = arg.substr(9)
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	records.append({"check": label, "passed": condition})
	if not condition:
		failures += 1
		push_error("FAIL " + label)
	else:
		checks += 1
		print("PASS ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if not shots.has("dir") or DisplayServer.get_name() == "headless":
		return
	await _frames(12)
	await RenderingServer.frame_post_draw
	var path: String = str(shots.dir).path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _find_text(node: Node, text: String) -> bool:
	if (node is Label and (node as Label).text.contains(text)) or (node is Button and (node as Button).text.contains(text)):
		return true
	for c in node.get_children():
		if _find_text(c, text):
			return true
	return false


func _find_rich(node: Node, text: String) -> bool:
	if node is RichTextLabel and (node as RichTextLabel).get_parsed_text().contains(text):
		return true
	for c in node.get_children():
		if _find_rich(c, text):
			return true
	return false


func _find_meta_button(node: Node, meta: String) -> Button:
	if node is Button and node.has_meta(meta):
		return node
	for c in node.get_children():
		var b: Button = _find_meta_button(c, meta)
		if b:
			return b
	return null


func _detached(preview: SkillPreview) -> bool:
	return preview.scenario == null and preview.view.sim == null and preview.runner.sim == null


func _visible_rows(rows: Dictionary) -> int:
	var n: int = 0
	for k in rows:
		if (rows[k] as Control).visible:
			n += 1
	return n


func _run() -> void:
	var records_before: String = JSON.stringify(Settings.records)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var app: App = scene.instantiate()
	get_tree().root.add_child(app)
	await _frames(3)
	_check(app.screens.codex is CodexScreen, "screens.codex is a CodexScreen")
	var codex: CodexScreen = app.screens.codex
	var preview: SkillPreview = codex.preview
	_check(preview != null and preview.scenario == null, "hidden codex builds the preview without a simulation")
	_check(codex.arena_view == null and codex.item_view == null and codex.glossary_view == null, "heavy codex views are built lazily")

	# ---------------------------------------------------------------- characters
	app.goto("codex")
	await _frames(3)
	_check(app.current == "codex" and codex.current_mode == "chars", "goto codex opens the character mode")
	_check(preview.scenario != null, "character mode runs the skill preview")
	_check(_find_text(codex.mode_seg, "캐릭터 26"), "mode switch shows 캐릭터 26")
	_check(_find_text(codex.mode_seg, "전장 21"), "mode switch shows 전장 21 (V2: 3 battleground maps)")
	_check(_find_text(codex.mode_seg, "아이템 28"), "mode switch shows 아이템 28")
	_check(_find_text(codex.mode_seg, "용어 %d" % CodexData.STATUS.size()), "mode switch shows 용어 count")
	_check(_find_text(codex.header, "전투 도감") and _find_text(codex.header, "COMPENDIUM"), "page header title and eyebrow")
	codex.char_search.text = "고문"
	codex._filter_roster()
	var shown: int = 0
	for id in codex.roster_cards:
		if (codex.roster_cards[id] as Control).visible:
			shown += 1
	_check(shown == 1 and (codex.roster_cards["torturer"] as Control).visible, "roster search finds 고문가")
	codex.char_search.text = ""
	codex.role_filter = "SUPPORT"
	codex._filter_roster()
	var support_ok: bool = true
	for id in codex.roster_cards:
		var rc: RosterCard = codex.roster_cards[id]
		if rc.visible != (rc.def.role == "SUPPORT"):
			support_ok = false
	_check(support_ok, "role filter shows only 지원 heroes")
	codex.role_filter = ""
	codex.char_search.text = "존재하지않는영웅"
	codex._filter_roster()
	_check(codex.char_empty.visible and not codex.char_scroll.visible, "roster search without results shows an empty state")
	await _shot("codex_empty_151")
	codex.char_search.text = ""
	codex._filter_roster()
	_check(not codex.char_empty.visible and codex.char_scroll.visible, "clearing the roster search restores the list")
	await _shot("codex_chars_151")

	# ---------------------------------------------------------------- items
	var t0: int = Time.get_ticks_usec()
	codex._mode("items")
	measurements["items_build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(2)
	_check(_detached(preview), "items mode detaches every preview simulation reference")
	_check(codex.item_view != null and codex.item_view.visible and not codex.char_view.visible, "items view replaces the character view")
	var rows: Dictionary = codex.item_list.get_meta("rows")
	var buttons: int = 0
	for k in rows:
		if rows[k] is Button:
			buttons += 1
	_check(rows.size() == 28 and buttons == 28, "28 selectable item rows")
	codex._select_item("l_heart")
	await _frames(2)
	_check(codex.current_item == "l_heart" and (rows["l_heart"] as Button).button_pressed, "l_heart row selected")
	_check(_find_text(codex.item_detail_host, "용의 심장") and _find_text(codex.item_detail_host, "전설"), "item detail shows 용의 심장 and 전설")
	var line: String = str(CodexData.item_details("l_heart")[0])
	_check(_find_rich(codex.item_detail_host, line), "item detail shows its hidden-rule lines")
	_check(_find_text(codex.item_view, "아이템 규칙"), "item rules card is present")
	codex.item_search.text = "심장"
	codex._filter_items()
	_check(_visible_rows(rows) == 1, "item search narrows the list")
	codex.item_search.text = ""
	codex.rarity_filter = 4
	codex._filter_items()
	_check(_visible_rows(rows) == 4, "rarity filter shows the 4 legendary items")
	codex.rarity_filter = -1
	codex._filter_items()
	_check(_visible_rows(rows) == 28, "clearing filters restores 28 rows")
	codex.item_search.text = "존재하지않는아이템"
	codex._filter_items()
	_check(codex.item_empty.visible and not codex.item_list_scroll.visible, "item search without results shows an empty state")
	codex.item_search.text = ""
	codex._filter_items()
	await _shot("codex_items_151")
	var hero_btn: Button = _find_meta_button(codex.item_detail_host, "hero_id")
	_check(hero_btn != null, "item detail lists clickable heroes")
	if hero_btn:
		var hid: String = str(hero_btn.get_meta("hero_id"))
		hero_btn.pressed.emit()
		await _frames(2)
		_check(codex.current_mode == "chars" and codex.detail.current == hid and codex.current_character == hid, "hero click opens that hero in the character mode")
		_check(preview.scenario != null and preview.character_id == hid, "preview follows the opened hero")

	# ---------------------------------------------------------------- arenas
	t0 = Time.get_ticks_usec()
	codex._mode("arenas")
	measurements["arenas_build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	# Deathmatch previews are generated one per frame after the view appears; battleground
	# previews (V2) on worker threads, added as they finish.
	var waited: int = 0
	while codex.arena_cards.size() < 21 and waited < 600:
		await get_tree().process_frame
		waited += 1
	measurements["arenas_complete_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	measurements["arenas_complete_frames"] = waited
	await _frames(2)
	_check(_detached(preview), "arena mode detaches every preview simulation reference")
	_check(codex.arena_cards.size() == 21, "21 arena cards (12 섬멸전 + 3 거점 + 3 개인전 + 3 배틀그라운드)")
	_check(codex.arena_cards.has("dm_forest_village") and codex.arena_cards.has("dm_ruined_town") and codex.arena_cards.has("dm_open_steppe"), "deathmatch maps are in the codex")
	_check(codex.arena_cards.has("br_ashen_metropolis") and codex.arena_cards.has("br_wildwood_frontier") and codex.arena_cards.has("br_highland_ruins"), "battleground maps are in the codex")
	var metro: Control = codex.arena_panels.get("br_ashen_metropolis")
	_check(metro != null and _find_text(metro, "아이템 자리") and _find_text(metro, "자기장") and _find_text(metro, "수풀"), "battleground maps show item spots, the zone and brush")
	_check(_find_text(codex.arena_view, "공통 규칙 · 배틀그라운드") and _find_text(codex.arena_view, "다운과 소생"), "battleground rules panel")
	var furnace: Control = codex.arena_panels.get("furnace_basin")
	_check(furnace != null and _find_text(furnace, "용암") and _find_text(furnace, "마법 34"), "furnace basin explains lava with exact numbers")
	var crossroads: Control = codex.arena_panels.get("control_crossroads")
	_check(crossroads != null and _find_text(crossroads, "거점") and _find_text(crossroads, "회복 구역"), "control maps explain points and heal zones")
	var village: Control = codex.arena_panels.get("dm_forest_village")
	_check(village != null and _find_text(village, "숲") and _find_text(village, "건물") and _find_text(village, "아이템 자리"), "deathmatch maps show forest, building and item-spot counts")
	_check(_find_text(codex.arena_view, "유형 · ") and not _find_text(codex.arena_view, "난도"), "arena category is labelled 유형, not 난도")
	codex._jump_arena_group("deathmatch")
	await _frames(1)
	_check(codex.arena_scroll.scroll_vertical > 0, "group jump scrolls to 개인전")
	codex._jump_arena_group("elimination")
	await _frames(1)
	await _shot("codex_arenas_151")

	# ---------------------------------------------------------------- glossary
	t0 = Time.get_ticks_usec()
	codex._mode("glossary")
	measurements["glossary_build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	await _frames(3)
	_check(_detached(preview), "glossary mode detaches every preview simulation reference")
	_check(_find_text(codex.glossary_view, "기절") and _find_text(codex.glossary_view, "강인함"), "glossary lists 기절 and 강인함")
	_check(codex.term_cards.size() == CodexData.STATUS.size(), "one card per glossary term")
	codex.glossary_search.text = "강인함"
	codex._filter_terms()
	_check((codex.term_cards["tenacity"] as Control).visible and not (codex.term_cards["charm"] as Control).visible, "glossary search filters cards")
	codex.glossary_search.text = "존재하지않는용어"
	codex._filter_terms()
	_check(codex.glossary_empty.visible and not codex.glossary_scroll.visible, "glossary search without results shows an empty state")
	codex.glossary_search.text = ""
	codex.category_filter = "군중 제어"
	codex._filter_terms()
	_check((codex.term_cards["stun"] as Control).visible and not (codex.term_cards["tenacity"] as Control).visible, "glossary category filter")
	codex.category_filter = ""
	codex._filter_terms()
	await _shot("codex_glossary_151")
	var term_hero: Button = _find_meta_button(codex.term_cards["stun"], "hero_id")
	_check(term_hero != null, "glossary card lists related heroes")
	if term_hero:
		var thid: String = str(term_hero.get_meta("hero_id"))
		term_hero.pressed.emit()
		await _frames(2)
		_check(codex.current_mode == "chars" and codex.detail.current == thid, "glossary hero click opens the character mode")

	# ---------------------------------------------------------------- deep links
	app.goto("codex", {"mode": "items", "item": "m_phoenix"})
	await _frames(2)
	_check(codex.current_mode == "items" and codex.current_item == "m_phoenix" and _find_text(codex.item_detail_host, "불사조 깃털"), "on_show(mode items, item m_phoenix) selects the phoenix")
	_check(_detached(preview), "deep link to items keeps the preview detached")
	codex._mode("chars")
	await _frames(1)
	_check(preview.scenario != null and preview.scenario.elapsed == 0.0, "back to characters restarts the preview")
	app.goto("codex", {"character": "torturer", "entry": "active:2"})
	await _frames(1)
	_check(codex.current_character == "torturer" and preview.entry_id == "active:2" and preview.scenario != null, "character deep link still opens the requested skill")
	app.goto("codex", {"mode": "glossary", "item": "stun"})
	await _frames(3)
	_check(codex.current_mode == "glossary" and _detached(preview), "glossary deep link keeps the preview detached")
	app.goto("codex", {"mode": "arenas", "item": "furnace_basin"})
	await _frames(3)
	_check(codex.current_mode == "arenas" and codex.arena_scroll.scroll_vertical > 0, "arena deep link scrolls to the arena")

	# ---------------------------------------------------------------- leaving
	app.goto("home")
	await _frames(2)
	_check(preview.scenario == null and not preview.view.visible, "leaving the codex disposes the preview")
	_check(JSON.stringify(Settings.records) == records_before, "codex browsing leaves player records unchanged")
	print("CODEX_UI_151 ", checks, " PASS / ", failures, " FAIL ", JSON.stringify(measurements))
	var report_path: String = "res://reports/codex_ui_151.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-report="):
			report_path = arg.substr(12)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"suite": "codex_ui_151", "status": "PASS" if failures == 0 else "FAIL", "passed": checks, "failed": failures,
			"measurements": measurements, "isolated_user_dir": ProjectSettings.get_setting("application/config/custom_user_dir_name"), "checks": records}, "  "))
	app.queue_free()
	await _frames(2)
	get_tree().quit(1 if failures else 0)
