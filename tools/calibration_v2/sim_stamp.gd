extends RefCounted

const Fingerprint = preload("res://tools/calibration_v2/data_fingerprint.gd")


static func _collect(path: String, out: Dictionary) -> void:
	var files: PackedStringArray = DirAccess.get_files_at(path)
	files.sort()
	for name: String in files:
		if name.ends_with(".uid") or name.ends_with(".import"): continue
		var source: String = path.path_join(name)
		out[source.trim_prefix("res://")] = FileAccess.get_sha256(source)
	var dirs: PackedStringArray = DirAccess.get_directories_at(path)
	dirs.sort()
	for name: String in dirs:
		_collect(path.path_join(name), out)


static func compute() -> Dictionary:
	var data: Dictionary = Fingerprint.fingerprint()
	if not data.has("sha256"): return {}
	var files: Dictionary = {}
	_collect("res://scripts/core", files)
	_collect("res://scripts/ai", files)
	files["scripts/data/char_data.gd"] = FileAccess.get_sha256("res://scripts/data/char_data.gd")
	var payload: Dictionary = {"data_fingerprint": data.sha256, "sources": files}
	return {"algorithm": "DVD_BATTLE_SIM_SHA_v1", "sim_sha": JSON.stringify(payload, "", true).sha256_text(),
		"data_fingerprint": data.sha256, "files": files}
