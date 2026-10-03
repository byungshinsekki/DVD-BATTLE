extends Node


signal changed

const PATH: = "user://settings.cfg"

var data: Dictionary = {
	"vfx_quality": 2, 
	"screen_shake": true, 
	"hit_stop": true, 
	"damage_numbers": true, 
	"show_names": true, 
	"telegraphs": true, 
	"master_volume": 0.8, 
	"sfx_volume": 0.85, 
	"music_volume": 0.45, 
	"default_speed": 1.0, 
	"ai_overlay": true, 
	"fullscreen": false, 
	"blue_ai": "tactician", 
	"red_ai": "tactician", 
}
var records: Dictionary = {"draft_wins": 0, "draft_losses": 0, "streak": 0, "best_streak": 0, "battles": 0, "pick_counts": {}}


func _ready() -> void :
	load_all()


func get_v(key: String, default_value = null):
	return data.get(key, default_value)


func set_v(key: String, value) -> void :
	data[key] = value
	save_all()
	changed.emit()


func load_all() -> void :
	var cf: = ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in data.keys():
		data[k] = cf.get_value("settings", k, data[k])
	for k in records.keys():
		records[k] = cf.get_value("records", k, records[k])


func save_all() -> void :
	var cf: = ConfigFile.new()
	for k in data:
		cf.set_value("settings", k, data[k])
	for k in records:
		cf.set_value("records", k, records[k])
	cf.save(PATH)


func reset_records() -> void :
	records = {"draft_wins": 0, "draft_losses": 0, "streak": 0, "best_streak": 0, "battles": 0, "pick_counts": {}}
	save_all()
	changed.emit()


func record_draft(win: bool) -> void :
	if win:
		records.draft_wins += 1
		records.streak += 1
		records.best_streak = maxi(records.best_streak, records.streak)
	else:
		records.draft_losses += 1
		records.streak = 0
	save_all()
