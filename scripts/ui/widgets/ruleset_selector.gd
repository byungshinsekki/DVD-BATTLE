class_name RulesetSelector
extends HBoxContainer
## Victory-rule picker shared by the setup and draft screens:
##   caption "승리 규칙" · segmented [섬멸전 | 거점 장악] · compact rule badges · "i" badge (full rules tooltip).
## set_locked() keeps the chosen segment visibly selected (UITheme.segmented_lock / lock_selected) and
## explains the lock in the segment tooltips.
## API (kept from V1.5): signal changed(ruleset), value, buttons {key: Button}, description (the "i"
## badge Label; its tooltip holds the full rules), set_ruleset(key), set_locked(locked).

signal changed(ruleset: String)

const OPTIONS: = [["elimination", "섬멸전"], ["control", "거점 장악"]]
const LOCK_TIP: = "첫 픽 이후에는 승리 규칙을 바꿀 수 없어요. 초기화하면 다시 고를 수 있어요."
const OPTION_TIPS: = {
	"elimination": "상대 팀을 모두 쓰러뜨리면 이기는 기본 규칙입니다.",
	"control": "넓은 전장의 거점 3곳을 차지해 먼저 300점을 모으는 규칙입니다.",
}

var value: String = "elimination"
var buttons: Dictionary = {}
var description: Label
var seg: HBoxContainer
var badge_row: HBoxContainer
var locked: bool = false


func _init() -> void:
	add_theme_constant_override("separation", UITheme.SP3)
	var cap: = UITheme.label("승리 규칙", "CaptionLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(cap)
	var opts: Array = []
	for row in OPTIONS:
		opts.append([row[0], row[1], OPTION_TIPS[row[0]]])
	seg = UITheme.segmented(opts, value, _on_pick, 92)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons = seg.get_meta("buttons")
	add_child(seg)
	badge_row = UITheme.hbox(6)
	badge_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(badge_row)
	description = UITheme.label("i", "BadgeLabel", 0, UITheme.TEXT_DIM)
	description.custom_minimum_size = Vector2(20, 20)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	description.add_theme_stylebox_override("normal", UITheme.sbc(Color(1, 1, 1, 0.04), UITheme.LINE2, UITheme.R_PILL, 1, 0, 0))
	description.mouse_filter = Control.MOUSE_FILTER_PASS
	description.mouse_default_cursor_shape = Control.CURSOR_HELP
	add_child(description)
	set_ruleset(value)


func _on_pick(key: Variant) -> void:
	if locked:
		return
	set_ruleset(str(key))
	changed.emit(value)


func set_ruleset(key: String) -> void:
	value = "control" if key == "control" else "elimination"
	UITheme.segmented_select(seg, value)
	if locked:
		UITheme.segmented_lock(seg, true)
	for c in badge_row.get_children():
		badge_row.remove_child(c)
		c.queue_free()
	for b in _badges(value):
		badge_row.add_child(UITheme.badge(b[0], b[1], "soft", b[2]))
	description.tooltip_text = UITheme.tip(_full_rules(value), 46)


## Disables the segments but keeps the chosen one visibly selected; reason becomes their tooltip.
func set_locked(on: bool, reason: String = LOCK_TIP) -> void:
	locked = on
	UITheme.segmented_lock(seg, on)
	for k in buttons:
		(buttons[k] as Button).tooltip_text = UITheme.tip(reason if on else str(OPTION_TIPS.get(k, "")))


## [text, colour, tooltip] rows for the compact rule badges.
static func _badges(key: String) -> Array:
	if key == "control":
		return [
			["300점 선승", UITheme.GOLD, "보유한 거점마다 초당 %s점을 얻고, 300점을 먼저 모은 팀이 이깁니다." % CodexData.num(DominationMode.SCORE_RATE)],
			["거점 3곳", UITheme.TEXT_DIM, "한 팀만 5초 머물면 적 거점을 중립화하고, 다시 5초 머물면 점령합니다. 양 팀이 함께 있으면 점령과 득점이 멈춥니다."],
			["제한 8분", UITheme.TEXT_DIM, "8분이 지나면 점수가 높은 팀이 이기고, 같으면 무승부입니다."],
			["부활 %s초" % CodexData.num(DominationMode.RESPAWN_DELAY), UITheme.TEXT_DIM, "쓰러진 영웅은 %s초 뒤 부활하고 %s초 동안 보호받습니다." % [CodexData.num(DominationMode.RESPAWN_DELAY), CodexData.num(DominationMode.SPAWN_PROTECTION)]],
		]
	return [
		["전멸 시 승리", UITheme.GOLD, "상대 팀 영웅을 모두 쓰러뜨리면 이깁니다."],
		["제한 2분 30초", UITheme.TEXT_DIM, "2분 30초가 지나면 살아 있는 영웅의 체력과 보호막 합이 더 큰 팀이 이깁니다."],
		["전장 %d종" % DB.arenas_for("elimination").size(), UITheme.TEXT_DIM, "섬멸전 전용 전장 가운데 하나를 고릅니다."],
	]


static func _full_rules(key: String) -> String:
	if key == "control":
		var lines: Array = ["거점 장악 · 기본 전장보다 2.5배 넓은 전장에서 싸웁니다."]
		for r in CodexData.CONTROL_RULES:
			lines.append("%s · %s" % [str(r.title), str(r.text)])
		lines.append("제한 시간 · 8분이 지나면 점수가 높은 팀이 이기고, 같으면 무승부입니다.")
		return "\n".join(lines)
	return "\n".join([
		"섬멸전 · 상대 팀 영웅을 모두 쓰러뜨리면 이깁니다.",
		"제한 시간 · 2분 30초가 지나면 살아 있는 영웅의 체력과 보호막 합이 더 큰 팀이 이깁니다. 차이가 거의 없으면 무승부입니다.",
		"전장 · 섬멸전 전용 전장 %d종 가운데 하나에서 싸웁니다." % DB.arenas_for("elimination").size(),
	])
