extends SceneTree

# Check raw bundled faces, with both kinds of fallback disabled. Loading a
# fresh resource avoids DB.load_fonts' already-mutated fallback chains.
const FACES: Array[String] = ["res://assets/fonts/glyph_serif.otf", "res://assets/fonts/ui_black.otf", "res://assets/fonts/symbols.ttf"]
var passed: int = 0
var failed: Array[String] = []
var faces: Array[FontFile] = []
var checked: Dictionary = {}
var evidence: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FONTS_V2 " + label)


func glyph(label: String, text: String) -> void:
	check(not text.is_empty(), label + " has an explicit glyph")
	for character in text:
		var code: int = character.unicode_at(0)
		if code in [9, 10, 13, 32]:
			continue
		var key: String = "%s U+%04X %s" % [label, code, character]
		var containing: Array[String] = []
		for i in faces.size():
			if faces[i].has_char(code):
				containing.append(FACES[i])
		check(not containing.is_empty(), key + " exists in raw bundled cmap")
		checked[code] = true
		evidence[key] = containing


func _entity_kinds() -> Array[String]:
	# Defs currently keeps its kind->name and kind->glyph maps inside the
	# function. Derive keys from the source rather than freezing a seven-kind
	# list which would silently miss future entities after Claude's merge.
	var source: String = FileAccess.get_file_as_string("res://scripts/core/defs.gd")
	var expression: RegEx = RegEx.new()
	var status: Error = expression.compile("\"([a-z_][a-z_0-9]*)\"\\s*:\\s*\"[^\"]*\"")
	check(status == OK, "entity key collection expression compiles")
	var kinds: Array[String] = []
	if status != OK:
		return kinds
	for result: RegExMatch in expression.search_all(source):
		var kind: String = result.get_string(1)
		if not kinds.has(kind):
			kinds.append(kind)
	kinds.sort()
	return kinds


func _run() -> void:
	DB.ensure_loaded()
	for path in FACES:
		var resource: Resource = ResourceLoader.load(path, "FontFile", ResourceLoader.CACHE_MODE_IGNORE)
		check(resource is FontFile, "raw font loads: " + path)
		if resource is FontFile:
			var face: FontFile = resource as FontFile
			face.fallbacks = []
			face.allow_system_fallback = false
			check(face.fallbacks.is_empty() and not face.allow_system_fallback, "all fallbacks disabled: " + path)
			check(not face.has_char(0x10FFFF), "unassigned sentinel is not supplied through fallback: " + path)
			faces.append(face)
	check(faces.size() == FACES.size(), "all three required raw bundled faces loaded")
	if faces.size() != FACES.size():
		_finish()
		return
	for character: Defs.CharDef in DB.characters:
		glyph("hero:" + character.id, character.glyph)
		for ability: Defs.AbilityDef in character.abilities:
			glyph("skill:" + ability.id, VfxStyle.glyph_for(ability))
	for status in VfxStyle.STATUS_ICONS:
		glyph("status:" + str(status), str(VfxStyle.STATUS_ICONS[status][0]))
	for role in DB.ROLE_ICONS:
		glyph("role:" + str(role), str(DB.ROLE_ICONS[role]))
	var entity_kinds: Array[String] = _entity_kinds()
	check(not entity_kinds.is_empty(), "entity_def key coverage discovered from current source")
	for kind in entity_kinds:
		var definition: Defs.CharDef = Defs.entity_def(kind, DB.characters[0], 100.0, 18.0, 0.0)
		glyph("entity:" + kind, definition.glyph)
	for id in ItemDefs.ORDER:
		glyph("item:" + str(id), str(ItemDefs.get_def(id).glyph))
	for status in CodexData.STATUS:
		glyph("codex_status:" + str(status), str(CodexData.STATUS[status].icon))
	for hazard in CodexData.HAZARDS:
		glyph("codex_hazard:" + str(hazard), str(CodexData.HAZARDS[hazard].icon))
	glyph("codex_cover", str(CodexData.COVER.icon))
	for terrain in CodexData.LOW_TERRAIN:
		glyph("codex_terrain:" + str(terrain), str(CodexData.LOW_TERRAIN[terrain][1]))
	check(str(VfxStyle.OVERRIDES["torturer_2"][0]) == "默", "torturer silence uses traditional 默 instead of missing 黙")
	# These six previously missing characters must be in the actual serif
	# face, not merely rendered by the UI or a machine's system fallback.
	for required in "政報誘宣訊默":
		check(faces[0].has_char(required.unicode_at(0)), "serif face explicitly includes repaired glyph " + required)
	var serif_file: FileAccess = FileAccess.open(FACES[0], FileAccess.READ)
	check(serif_file != null and serif_file.get_length() <= 1500000, "serif subset is at most 1.5 MB")
	if serif_file != null:
		serif_file.close()
	_finish()


func _finish() -> void:
	var report: Dictionary = {"suite": "fonts_v2", "status": "PASS" if failed.is_empty() else "FAIL", "passed": passed, "failed": failed,
		"unique_codepoints": checked.size(), "faces": FACES, "coverage": evidence,
		"system_fallback": false, "resource_fallbacks": false}
	var report_path: String = "res://zz_work/measure/C7/fonts_v2.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.substr(9)
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("FONTS_V2 cannot write report: " + report_path)
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("FONTS_V2 ", "PASS" if failed.is_empty() else "FAIL", " passed=", passed, " failed=", failed.size(), " unique_codepoints=", checked.size())
	quit(0 if failed.is_empty() else 1)
