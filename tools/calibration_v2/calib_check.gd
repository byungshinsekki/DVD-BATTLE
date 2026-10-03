extends SceneTree

const Schema = preload("res://tools/calibration_v2/calibration_schema.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DB.ensure_loaded()
	var path: String = "res://scripts/data/draft_calibration.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			path = arg.substr(7)
	var script: GDScript = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name DraftCalibration", "")
	var err: int = script.reload()
	if err != OK:
		push_error("Calibration candidate failed to parse: " + path)
		quit(1)
		return
	var report: Dictionary = Schema.validate(script.get_script_constant_map(), DB.ids())
	print("CALIB_CHECK ", JSON.stringify(report))
	quit(0 if report.failed.is_empty() else 1)
