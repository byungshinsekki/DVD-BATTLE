extends SceneTree

# V1.5.1 data fingerprint. Builds a canonical JSON document of every data table the
# simulation reads (CharData.LIST, ItemDefs, ArenaData.LIST, ControlArenaData.all(),
# DeathmatchMapData presets, catalogue and generated maps) with the display-only
# fields removed, and prints its SHA-256:
#   DATA_FINGERPRINT_151 {"sha256": "...", "bytes": N, "counts": {...}}
# Two trees with the same fingerprint feed the simulation identical data; text such as
# skill descriptions, item names or arena notes may differ.
#
#   Godot --headless --path <project> --script res://tools/data_fingerprint_151.gd [-- --out=<file>]
#   Godot --headless --path <other project> --script D:/DVD_BATTLE_1.5.1/tools/data_fingerprint_151.gd -- --out=<file>
#
# The data scripts are loaded from the project given by --path (res://scripts/data/*),
# so the same file fingerprints another checkout (import that checkout once first:
# --headless --path <dir> --editor --quit). --out writes the canonical JSON; its
# SHA-256 is the printed value. Nothing else is written; user data is never touched.

# Display-only fields (DESIGN_151.md §0 rule 1). Everything else is kept.
const CHAR_DROP := ["summary", "doctrine"]
const BEHAVIOR_DROP := ["label"]
const NEXUS_DROP := ["identity", "skills"]
const ABILITY_DROP := ["description", "geometry", "timing"]
const PASSIVE_DROP := ["name", "description"]
const ITEM_DROP := ["name", "desc", "glyph"]
const ARENA_DROP := ["description", "subtitle", "tacticalNotes", "tags", "icon", "difficulty"]
# Deathmatch maps are generated from preset + seed; these seeds are the ones used by the
# tests, the screenshots and the demo arguments.
const DM_SEEDS := [20261001, 4242, 31, 777]
const DATA_DIR := "res://scripts/data/"


func _initialize() -> void:
	var out_path: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	var scripts: Dictionary = {}
	for name in ["char_data", "item_defs", "arena_data", "control_arena_data", "deathmatch_map_data"]:
		var script: Script = load(DATA_DIR + name + ".gd")
		if script == null:
			push_error("data_fingerprint_151: cannot load " + DATA_DIR + name + ".gd")
			quit(1)
			return
		scripts[name] = script
	var counts: Dictionary = {}
	var doc: Dictionary = {"format": "DVD_BATTLE data fingerprint v1 (display-only fields removed)"}

	var characters: Array = []
	var n_abilities: int = 0
	var n_passives: int = 0
	for c in _const(scripts.char_data, "LIST"):
		var d: Dictionary = (c as Dictionary).duplicate(true)
		_drop(d, CHAR_DROP)
		if d.get("behavior") is Dictionary:
			_drop(d.behavior, BEHAVIOR_DROP)
		if d.get("nexus") is Dictionary:
			_drop(d.nexus, NEXUS_DROP)
		for a in d.get("abilities", []):
			_drop(a, ABILITY_DROP)
			n_abilities += 1
		for p in d.get("passives", []):
			_drop(p, PASSIVE_DROP)
			if p.has("rules"):
				_drop_deep(p.rules, "description")
			n_passives += 1
		characters.append(d)
	doc["characters"] = characters
	counts["characters"] = characters.size()
	counts["abilities"] = n_abilities
	counts["passives"] = n_passives

	var item_defs: Dictionary = {}
	var defs: Dictionary = _const(scripts.item_defs, "DEFS")
	for id in defs:
		var item: Dictionary = (defs[id] as Dictionary).duplicate(true)
		_drop(item, ITEM_DROP)
		item_defs[id] = item
	doc["items"] = {"order": _const(scripts.item_defs, "ORDER"), "rarity_weights": _const(scripts.item_defs, "RARITY_WEIGHTS"),
		"defs": item_defs}
	counts["items"] = item_defs.size()

	doc["arenas"] = _arenas(_const(scripts.arena_data, "LIST"))
	counts["arenas"] = doc.arenas.size()
	doc["control_arenas"] = {"area_multiplier": _const(scripts.control_arena_data, "AREA_MULTIPLIER"),
		"maps": _arenas(scripts.control_arena_data.call("all"))}
	counts["control_arenas"] = doc.control_arenas.maps.size()

	var dm: GDScript = scripts.deathmatch_map_data
	var presets: Dictionary = {}
	var raw_presets: Dictionary = _const(dm, "PRESETS")
	for id in raw_presets:
		var preset: Dictionary = (raw_presets[id] as Dictionary).duplicate(true)
		_drop(preset, ARENA_DROP)
		presets[id] = preset
	var maps: Dictionary = {}
	for id in _const(dm, "ORDER"):
		for seed_value in DM_SEEDS:
			var built: Dictionary = dm.call("build", str(id), int(seed_value))
			_drop(built, ARENA_DROP)
			maps["%s/%d" % [id, seed_value]] = built
	doc["deathmatch"] = {"width": _const(dm, "WIDTH"), "height": _const(dm, "HEIGHT"), "margin": _const(dm, "MARGIN"),
		"order": _const(dm, "ORDER"), "presets": presets, "catalogue": _arenas(dm.call("catalogue")), "maps": maps}
	counts["deathmatch_presets"] = presets.size()
	counts["deathmatch_maps"] = maps.size()

	var text: String = canon(doc)
	var digest: String = text.sha256_text()
	if out_path != "":
		var file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			push_error("data_fingerprint_151: cannot write " + out_path)
			quit(1)
			return
		file.store_string(text)
		file.close()
	var line: Dictionary = {"sha256": digest, "bytes": text.to_utf8_buffer().size(), "counts": counts,
		"project": ProjectSettings.globalize_path("res://").trim_suffix("/")}
	print("DATA_FINGERPRINT_151 " + JSON.stringify(line, "", false))
	quit(0)


static func _const(script: Script, name: String) -> Variant:
	var constants: Dictionary = script.get_script_constant_map()
	if not constants.has(name):
		push_error("data_fingerprint_151: missing constant %s in %s" % [name, script.resource_path])
	return constants.get(name)


static func _arenas(list: Array) -> Array:
	var out: Array = []
	for arena in list:
		var d: Dictionary = (arena as Dictionary).duplicate(true)
		_drop(d, ARENA_DROP)
		out.append(d)
	return out


static func _drop(d: Dictionary, keys: Array) -> void:
	for key in keys:
		d.erase(key)


static func _drop_deep(value: Variant, key: String) -> void:
	if value is Dictionary:
		value.erase(key)
		for k in value:
			_drop_deep(value[k], key)
	elif value is Array:
		for v in value:
			_drop_deep(v, key)


# Canonical JSON: keys sorted by code point, no whitespace, ints as integers, floats in
# their shortest round-trip form with ".0" kept on whole numbers (so an int/float type
# change is visible), non-JSON values (Vector2, Color, ...) as their var_to_str text.
static func canon(value: Variant) -> String:
	var t: int = typeof(value)
	match t:
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f):
				return JSON.stringify(var_to_str(f))
			return var_to_str(f)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return JSON.stringify(str(value))
		TYPE_DICTIONARY:
			var by_key: Dictionary = {}
			for k in value:
				var ks: String = str(k) if typeof(k) in [TYPE_STRING, TYPE_STRING_NAME] else var_to_str(k)
				by_key[ks] = value[k]
			var keys: Array = by_key.keys()
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for ks in keys:
				parts.append(JSON.stringify(ks) + ":" + canon(by_key[ks]))
			return "{" + ",".join(parts) + "}"
	if t == TYPE_ARRAY or t >= TYPE_PACKED_BYTE_ARRAY:
		var items: PackedStringArray = PackedStringArray()
		for v in value:
			items.append(canon(v))
		return "[" + ",".join(items) + "]"
	return JSON.stringify(var_to_str(value))
