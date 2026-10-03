class_name SkillPreview
extends VBoxContainer
## Codex skill preview: a real BattleSim scenario per skill, drawn by a BattleView on a 16:9 canvas.
##  heading -> skill tabs (P1.. then S1.., same order as CharDetail) -> canvas -> playback bar
##  (timeline, play/restart, speed, loop, sound) -> details card (title, rich description,
##  live readout badges, demo conditions).
## Playback is driven only by _process (tests step it manually); the runner never processes.
## Height budget: everything but the canvas is compact so the canvas keeps 16:9 and the whole
## preview fits the codex column at 1600x900 without scrolling (_resize_canvas shrinks the canvas).

signal entry_selected(kind: String, index: int)

const SPEEDS: = [0.5, 1.0, 2.0]
const RESTART_DELAY: = 0.85
const STATE_TEXT: = "시연마다 체력·자원·배치를 초기화합니다. 일반 경기와 전적에 영향을 주지 않습니다."
## First sentence of every active-skill condition text (scenario boilerplate) -> tooltip only.
const GENERIC_SETUP: = "적과 아군은 지정된 훈련 위치에서 시작합니다. 실제 전투의 수치·시전·충돌·쿨다운을 사용합니다."
const CONDITION_WORDS: = {"rage": "분노", "shards": "차원 조각", "healBank": "치유 비축량", "fish": "물고기", "fuel": "연료", "confusion": "혼란", "infection": "감염", "control": "조종", "imprisoned": "감금", "pain": "고통"}
const DAMAGE_COLOR: = Color("#ff9a6b")
const HEAL_COLOR: = Color("#6fe0a2")
const SHIELD_COLOR: = Color("#cfe3ff")
## Optional 4th readout (scenario.readout().extra): war machine fuel, hades' harvested max HP.
const EXTRA_COLOR: = Color("#f4c96b")

var character_id: String = ""
var entry_id: String = ""
var entries: Array = []
var scenario: SkillPreviewScenario
var runner: BattleRunner
var view: BattleView
var active: bool = false
var repeating: bool = true
var playback_speed: float = 1.0
var sound_enabled: bool = false
var accumulator: float = 0.0
var finished: bool = false
var restart_delay: float = 0.0
var loop_count: int = 0
## Holder of the skill tab strip (a UITheme.segmented control rebuilt per character).
var tabs: HBoxContainer
var tab_buttons: Dictionary = {}
var canvas: Control
var canvas_slot: Control
var playback_controls: HBoxContainer
var details_panel: PanelContainer
var title_label: Label
## Plain description (kept for callers/tests); the visible text is description_rich.
var description_label: Label
var description_rich: RichTextLabel
var condition_label: Label
## Reset/isolation note; shown as a tooltip (kept as a hidden Label for callers).
var state_label: Label
## "시연 피해 · 회복 · 보호막" text (hidden); the visible readout is readout_badges.
var readout_label: Label
var readout_badges: Dictionary = {}
var time_label: Label
var play_button: Button
var timeline: ProgressBar
var speed_control: HBoxContainer
var loop_button: Button
var sound_button: Button
var subtitle_label: Label
var title_tile: Label
var condition_row: HBoxContainer
var _segmented: HBoxContainer
var _readout_cache: Vector3 = Vector3(-1, -1, -1)
var _extra_cache: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var demo: PanelContainer = UITheme.badge("훈련 시연", UITheme.ACCENT, "soft", STATE_TEXT)
	add_child(UITheme.section_header("스킬 미리보기", "실제 전투 규칙으로 재생합니다", demo))
	tabs = UITheme.hbox(0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	canvas_slot = Control.new()
	canvas_slot.custom_minimum_size = Vector2(0, 280)
	canvas_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_slot.resized.connect(_queue_canvas_resize)
	canvas = Control.new()
	canvas.clip_contents = true
	canvas.resized.connect(_fit_view)
	var background: ColorRect = ColorRect.new()
	background.color = Color("#050b13")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	runner = BattleRunner.new()
	runner.set_process(false)
	add_child(runner)
	view = BattleView.new()
	view.sound = false
	view.show_ai = false
	view.shake_enabled = false
	view.hitstop_enabled = false
	canvas.add_child(view)
	# Hairline frame over the arena and a sunken letterbox behind it (visible on wide windows).
	var frame: Panel = Panel.new()
	frame.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.CLEAR, Color(1, 1, 1, 0.08), 0, 1, 0, 0))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(frame)
	var letterbox: Panel = Panel.new()
	letterbox.add_theme_stylebox_override("panel", UITheme.sbc(UITheme.BG2, UITheme.LINE, UITheme.R_M, 1, 0, 0))
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letterbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_slot.add_child(letterbox)
	canvas_slot.add_child(canvas)
	add_child(canvas_slot)
	add_child(_build_player_bar())
	details_panel = _build_details()
	add_child(details_panel)
	resized.connect(_resize_canvas)
	minimum_size_changed.connect(_queue_canvas_resize)
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_queue_canvas_resize)
	_resize_canvas.call_deferred()
	if character_id != "":
		_build_entries()
		if active:
			_start_scenario()


func _build_player_bar() -> PanelContainer:
	var bar: VBoxContainer = UITheme.vbox(UITheme.SP2)
	var track: HBoxContainer = UITheme.hbox(UITheme.SP3)
	timeline = UITheme.progress(0.0, 12.0, UITheme.ACCENT, 6)
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(timeline)
	time_label = UITheme.label("0.0 / 0.0초", "CaptionLabel", UITheme.FS_CAPTION)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.custom_minimum_size.x = 92
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_child(time_label)
	bar.add_child(track)

	var controls: HBoxContainer = UITheme.hbox(UITheme.SP2)
	playback_controls = controls
	play_button = UITheme.button("❚❚ 일시정지", "", toggle_playback, "시연을 일시정지하거나 이어서 재생합니다.")
	play_button.custom_minimum_size = Vector2(112, 32)
	controls.add_child(play_button)
	var again: Button = UITheme.button("↻ 처음부터", "GhostButton", restart, "시연을 처음부터 다시 재생합니다.")
	again.custom_minimum_size.y = 32
	controls.add_child(again)
	controls.add_child(UITheme.spacer())
	var options: Array = []
	for v in SPEEDS:
		options.append([v, "%s×" % CodexData.num(v), "재생 속도 %s배" % CodexData.num(v)])
	speed_control = UITheme.segmented(options, playback_speed, func(v): set_speed(float(v)))
	speed_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for b in (speed_control.get_meta("buttons") as Dictionary).values():
		(b as Button).add_theme_font_size_override("font_size", UITheme.FS_CAPTION)
	controls.add_child(speed_control)
	loop_button = UITheme.button("반복", "ChipButton", Callable(), "켜 두면 시연이 끝난 뒤 자동으로 다시 재생합니다.")
	loop_button.toggle_mode = true
	loop_button.set_pressed_no_signal(repeating)
	loop_button.toggled.connect(func(value): repeating = value)
	loop_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	loop_button.custom_minimum_size = Vector2(52, 30)
	controls.add_child(loop_button)
	sound_button = UITheme.button("소리", "ChipButton", Callable(), "시연 효과음을 켜거나 끕니다.")
	sound_button.toggle_mode = true
	sound_button.set_pressed_no_signal(sound_enabled)
	sound_button.toggled.connect(func(value): sound_enabled = value; view.sound = value)
	sound_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sound_button.custom_minimum_size = Vector2(52, 30)
	controls.add_child(sound_button)
	bar.add_child(controls)
	return UITheme.styled_panel(UITheme.sbc(UITheme.BG2, UITheme.LINE, UITheme.R_M, 1, 12, 10), bar)


func _build_details() -> PanelContainer:
	var box: VBoxContainer = UITheme.vbox(UITheme.SP2)
	var head: HBoxContainer = UITheme.hbox(10)
	title_tile = UITheme.glyph_tile("·", UITheme.ACCENT, 34)
	head.add_child(title_tile)
	var tv: VBoxContainer = UITheme.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label = UITheme.ellipsize(UITheme.label("스킬을 선택해 주세요", "SubheadLabel", UITheme.FS_H2))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(title_label)
	subtitle_label = UITheme.ellipsize(UITheme.label("", "CaptionLabel", UITheme.FS_CAPTION))
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(subtitle_label)
	head.add_child(tv)
	var readout: HBoxContainer = UITheme.hbox(6)
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	readout.tooltip_text = UITheme.tip("이번 시연에서 시전자가 준 피해·회복·보호막 합계입니다.")
	readout.mouse_filter = Control.MOUSE_FILTER_PASS
	for spec in [["damage", "피해", DAMAGE_COLOR], ["healing", "회복", HEAL_COLOR], ["shielding", "보호막", SHIELD_COLOR]]:
		var b: PanelContainer = UITheme.badge("%s 0" % spec[1], spec[2], "soft")
		b.set_meta("caption", spec[1])
		readout_badges[spec[0]] = b
		readout.add_child(b)
	var extra: PanelContainer = UITheme.badge("", EXTRA_COLOR, "soft", "시전자의 현재 연료 또는 기본보다 늘어난 최대 체력입니다.")
	extra.visible = false
	readout_badges["extra"] = extra
	readout.add_child(extra)
	head.add_child(readout)
	box.add_child(head)
	description_label = UITheme.wrap_label("", "DimLabel", UITheme.FS_CAPTION)
	description_label.visible = false
	box.add_child(description_label)
	description_rich = UITheme.rich("", UITheme.FS_SM)
	description_rich.add_theme_color_override("default_color", UITheme.TEXT_DIM)
	box.add_child(description_rich)
	condition_row = UITheme.hbox(UITheme.SP2)
	condition_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var cb: PanelContainer = UITheme.badge("시연 조건", UITheme.GOLD, "soft")
	cb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	condition_row.add_child(cb)
	condition_label = UITheme.wrap_label("", "CaptionLabel", UITheme.FS_CAPTION)
	condition_label.mouse_filter = Control.MOUSE_FILTER_PASS
	condition_row.add_child(condition_label)
	box.add_child(condition_row)
	readout_label = UITheme.label("", "DimLabel", UITheme.FS_MICRO)
	readout_label.visible = false
	box.add_child(readout_label)
	state_label = UITheme.wrap_label(STATE_TEXT, "FaintLabel", UITheme.FS_MICRO)
	state_label.visible = false
	box.add_child(state_label)
	return UITheme.panel("CardPanel", box)


func select_character(id: String, requested: String = "") -> void:
	var changed: bool = character_id != id
	character_id = id
	if changed:
		entries = SkillPreviewScenario.entries(id)
		entry_id = str(entries[0].id) if not entries.is_empty() else ""
	if requested != "":
		for entry in entries:
			if str(entry.id) == requested:
				entry_id = requested
				break
	if not is_node_ready():
		return
	if changed:
		_build_entries()
	_sync_selection()
	if active:
		_start_scenario()
	else:
		_dispose_scenario()


func select_entry(id: String) -> void:
	if id == entry_id and scenario != null:
		return
	for entry in entries:
		if str(entry.id) != id:
			continue
		entry_id = id
		_sync_selection()
		if active:
			_start_scenario()
		entry_selected.emit(str(entry.kind), int(entry.index))
		return


## Tab order follows CharDetail: passives (P1..) first, then abilities (S1..).
func _ordered_entries() -> Array:
	var passives: Array = []
	var actives: Array = []
	for entry in entries:
		if str(entry.kind) == "passive":
			passives.append(entry)
		else:
			actives.append(entry)
	return passives + actives


func _tab_label(entry: Dictionary) -> String:
	var i: int = int(entry.index)
	var definition: Defs.CharDef = DB.char_def(character_id)
	if str(entry.kind) == "passive":
		var pname: String = ""
		if definition and i < definition.passives.size():
			pname = str((definition.passives[i] as Dictionary).get("name", ""))
		return "P%d · %s" % [i + 1, pname] if pname != "" else "P%d" % (i + 1)
	if definition and i < definition.abilities.size():
		var ab: Defs.AbilityDef = definition.abilities[i]
		return "S%d · %s" % [ab.slot, ab.name]
	return str(entry.get("label", "S%d" % (i + 1)))


func _build_entries() -> void:
	if _segmented:
		tabs.remove_child(_segmented)
		_segmented.queue_free()
		_segmented = null
	tab_buttons.clear()
	var options: Array = []
	for entry in _ordered_entries():
		var label: String = _tab_label(entry)
		options.append([str(entry.id), label, "%s — 눌러서 시연을 봅니다." % label])
	if options.is_empty():
		return
	_segmented = UITheme.segmented(options, entry_id, func(id): select_entry(str(id)))
	_segmented.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pill: Control = _segmented.get_child(0)
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(pill.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_buttons = (_segmented.get_meta("buttons") as Dictionary).duplicate()
	for id in tab_buttons:
		var button: Button = tab_buttons[id]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.custom_minimum_size = Vector2(52, 32)
	tabs.add_child(_segmented)
	_sync_selection()


func _selected_entry() -> Dictionary:
	for entry in entries:
		if str(entry.id) == entry_id:
			return entry
	return {}


func _sync_selection() -> void:
	if _segmented:
		UITheme.segmented_select(_segmented, entry_id)
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return
	var definition: Defs.CharDef = DB.char_def(character_id)
	var passive: bool = str(entry.kind) == "passive"
	var color: Color = definition.accent
	var glyph: String = "P%d" % (int(entry.index) + 1)
	if not passive and int(entry.index) < definition.abilities.size():
		var ab: Defs.AbilityDef = definition.abilities[int(entry.index)]
		color = ab.color
		glyph = VfxStyle.glyph_for(ab)
	title_label.text = _tab_label(entry)
	title_label.add_theme_color_override("font_color", color.lightened(0.35))
	subtitle_label.text = "%s · %s" % [definition.name, "패시브" if passive else "액티브 스킬"]
	title_tile.text = glyph
	title_tile.add_theme_font_size_override("font_size", maxi(UITheme.MIN_FS, int(round(34 * (0.52 if glyph.length() <= 1 else 0.36)))))
	title_tile.add_theme_stylebox_override("normal", UITheme.sbc(color.darkened(0.55), color, UITheme.R_S, 1, 0, 0))
	var description: String = str(entry.get("description", ""))
	description_label.text = description
	description_rich.text = CodexText.rich_desc(description)
	var conditions = entry.get("conditions", "")
	_set_conditions(" · ".join(conditions) if conditions is Array else str(conditions))
	state_label.text = STATE_TEXT


func _set_conditions(text: String) -> void:
	var shown: String = text.strip_edges()
	var generic: bool = shown.begins_with(GENERIC_SETUP)
	if generic:
		shown = shown.substr(GENERIC_SETUP.length()).strip_edges()
	if shown == "":
		shown = "지정된 훈련 배치에서 실제 전투 수치로 재생합니다."
	condition_label.text = shown
	var tip: String = (GENERIC_SETUP + "\n" if generic else "") + STATE_TEXT
	condition_row.tooltip_text = UITheme.tip(tip)
	condition_label.tooltip_text = condition_row.tooltip_text


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not is_node_ready():
		return
	if active and entry_id != "":
		_start_scenario()
	else:
		_dispose_scenario()


func _start_scenario() -> void:
	_dispose_scenario()
	if character_id == "" or entry_id == "":
		return
	scenario = SkillPreviewScenario.new(character_id, entry_id)
	runner.sim = scenario.sim
	runner.paused = false
	runner.speed = playback_speed
	runner.alpha = 1.0
	runner.set_process(false)
	view.setup(scenario.sim, runner)
	view.apply_settings()
	view.show_ai = false
	view.show_names = true
	view.show_numbers = true
	view.show_telegraphs = true
	view.shake_enabled = false
	view.hitstop_enabled = false
	view.sound = sound_enabled
	view.set_perspective(-1)
	view.visible = true
	view.set_process(true)
	view.on_step(scenario.sim.drain_frame_events())
	accumulator = 0.0
	finished = false
	restart_delay = 0.0
	if scenario.instructions != "":
		_set_conditions(_condition_text(scenario.instructions))
	_fit_view()
	_sync_controls()


func restart() -> void:
	if active:
		_start_scenario()


func set_speed(value: float) -> void:
	playback_speed = clampf(value, 0.5, 2.0)
	if runner:
		runner.speed = playback_speed
	if speed_control:
		var best: float = SPEEDS[0]
		for v in SPEEDS:
			if absf(float(v) - playback_speed) < absf(best - playback_speed):
				best = v
		UITheme.segmented_select(speed_control, best)


func toggle_playback() -> void:
	if not active:
		return
	if finished or scenario == null:
		_start_scenario()
	else:
		runner.paused = not runner.paused
	_sync_controls()


func _sync_controls() -> void:
	if play_button:
		play_button.text = "▶ 다시 재생" if finished else ("▶ 재생" if runner.paused else "❚❚ 일시정지")
	if scenario:
		time_label.text = "%.1f / %.1f초" % [minf(scenario.elapsed, scenario.duration), scenario.duration]
		timeline.max_value = scenario.duration
		timeline.value = scenario.elapsed
		var values: Dictionary = scenario.readout()
		var now: Vector3 = Vector3(int(values.get("damage", 0)), int(values.get("healing", 0)), int(values.get("shielding", 0)))
		if now != _readout_cache:
			_readout_cache = now
			readout_label.text = "시연 피해 %d · 회복 %d · 보호막 %d" % [int(now.x), int(now.y), int(now.z)]
			_set_badge("damage", int(now.x))
			_set_badge("healing", int(now.y))
			_set_badge("shielding", int(now.z))
		var extra_text: String = str(values.get("extra", ""))
		if extra_text != _extra_cache:
			_extra_cache = extra_text
			var extra: PanelContainer = readout_badges["extra"]
			(extra.get_meta("label") as Label).text = extra_text
			extra.visible = extra_text != ""


func _set_badge(key: String, value: int) -> void:
	var b: PanelContainer = readout_badges.get(key)
	if b == null:
		return
	(b.get_meta("label") as Label).text = "%s %d" % [str(b.get_meta("caption")), value]


func _process(delta: float) -> void:
	if not active or scenario == null:
		return
	if finished:
		if repeating:
			restart_delay += delta
			if restart_delay >= RESTART_DELAY:
				loop_count += 1
				_start_scenario()
		return
	if runner.paused:
		return
	accumulator += minf(delta, 0.1) * playback_speed
	var steps: int = 0
	while accumulator >= BattleSim.DT and steps < 8:
		accumulator -= BattleSim.DT
		steps += 1
		var stepped: bool = scenario.step()
		view.on_step(scenario.sim.drain_frame_events())
		if not stepped or scenario.elapsed + 0.0001 >= scenario.duration:
			finished = true
			runner.paused = true
			accumulator = 0.0
			break
	runner.alpha = 1.0
	_sync_controls()


func _resize_canvas() -> void:
	if canvas == null or size.x < 1.0:
		return
	var available_height: float = (get_parent() as Control).size.y if get_parent() is Control else get_viewport_rect().size.y
	var reserved_height: float = 8.0
	var visible_controls: int = 0
	for child in get_children():
		if child is Control and child.visible:
			visible_controls += 1
			if child != canvas_slot:
				reserved_height += child.get_combined_minimum_size().y
	reserved_height += get_theme_constant("separation") * maxi(0, visible_controls - 1)
	# Keep playback and conditions on screen. The enclosing scroll remains the
	# fallback if the window cannot fit even a small preview with its text.
	var canvas_height: float = minf(size.x * 9.0 / 16.0, maxf(160.0, available_height - reserved_height))
	var target_size: Vector2 = Vector2(canvas_height * 16.0 / 9.0, canvas_height)
	if not is_equal_approx(canvas_slot.custom_minimum_size.y, canvas_height):
		canvas_slot.custom_minimum_size.y = canvas_height
	canvas.size = target_size
	canvas.position = Vector2(maxf(0.0, (size.x - target_size.x) * 0.5), 0.0)
	_fit_view()


func _queue_canvas_resize() -> void:
	_resize_canvas.call_deferred()


func _fit_view() -> void:
	if view == null or scenario == null or canvas.size.x < 1:
		return
	view.fit(Rect2(Vector2(7, 7), canvas.size - Vector2(14, 14)))
	var focus: Rect2 = scenario.focus_rect
	if focus.size.x > 0 and focus.size.y > 0:
		var scale_to_focus: float = minf((canvas.size.x - 24) / focus.size.x, (canvas.size.y - 24) / focus.size.y)
		view.cam_mode = "manual"
		view.cam_center = focus.get_center()
		view.cam_center_t = view.cam_center
		view.cam_zoom = maxf(1.0, scale_to_focus / maxf(0.001, view.base_scale))
		view.cam_zoom_t = view.cam_zoom
		view._apply_camera(0.0)


func _dispose_scenario() -> void:
	if view:
		view.set_process(false)
		view.visible = false
		view.sim = null
		view.fx.clear_all()
		view.ev_fx.clear_all()
	if runner:
		runner.sim = null
		runner.paused = true
	if scenario:
		scenario.dispose()
	scenario = null
	accumulator = 0.0
	finished = false
	_readout_cache = Vector3(-1, -1, -1)
	_extra_cache = ""
	if readout_badges.has("extra"):
		(readout_badges["extra"] as Control).visible = false


func _exit_tree() -> void:
	_dispose_scenario()


func _condition_text(text: String) -> String:
	for key in CONDITION_WORDS:
		text = text.replace(key, CONDITION_WORDS[key])
	return text
