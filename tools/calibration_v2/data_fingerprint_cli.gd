extends SceneTree

const Fingerprint = preload("res://tools/calibration_v2/data_fingerprint.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.substr(6)
	if output.is_empty():
		push_error("data_fingerprint_v2: explicit --out= is required")
		quit(1)
		return
	var data: Dictionary = Fingerprint.fingerprint(output)
	if not data.has("sha256"):
		push_error("data_fingerprint_v2: cannot produce canonical data fingerprint")
		quit(1)
		return
	data["project"] = ProjectSettings.globalize_path("res://").trim_suffix("/")
	print("DATA_FINGERPRINT_V2 " + JSON.stringify(data, "", false))
	quit(0)
