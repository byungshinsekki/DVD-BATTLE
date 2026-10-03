class_name DeveloperScreen
extends Control

const MODES: Array[String] = ["elimination", "control", "deathmatch", "battleground"]
const MODE_LABELS: Array[String] = ["섬멸전", "거점 장악", "데스매치", "배틀그라운드"]
## Battleground roster: up to 30 heroes (BattlegroundMode.MAX_HEROES) in squads of 1-3.
const ROSTER_SLOTS: int = 30
const SQUAD_LABELS: Array[String] = ["솔로", "듀오", "트리오"]
## Per-type environment switches (ArenaEnv.set_type_enabled keys = Arena.TYPE_BITS), lab order.
const TYPE_ORDER: Array[String] = ["gate", "artillery", "jump_pad", "closing_ring", "mud", "brush", "lava", "spikes", "eruption",
	"wind", "portal", "haste", "healing_fountain", "gravity", "shockwave"]
## Quick gimmick tests: [label, mode index, map id, ticks to advance (30 = 1 s)].
## Ring presets stop just before the ring starts (crossroads used to stop at 60 s,
## 20 s into the shrink, where a 5v5 case could already be over).
const GIMMICK_PRESETS: Array = [
	["개폐 성문 · 붕괴한 성문", 0, "ruined_gate", 60],
	["포격 · 쌍둥이 주조소", 0, "twin_foundry", 120],
	["도약 발판 · 용광로 분지", 0, "furnace_basin", 90],
	["결계 수축 · 환형 요새 (34초)", 0, "bastion_ring", 1020],
	["결계 수축 · 교차 회랑 (39초)", 0, "crossroads", 1170],
	["진흙·도약 · 풍향 협곡", 0, "gale_corridor", 90],
	["수풀 · 월영 정원", 0, "moon_garden", 120],
	["성문·포격 · 환상 요새 (거점)", 1, "control_citadel", 150],
	["진흙 · 갈라진 수로 (거점)", 1, "control_waterway", 90],
	["포격 · 폐허 도시 (개인전)", 2, "dm_ruined_town", 150],
	["진흙·숲 · 숲의 마을 (개인전)", 2, "dm_forest_village", 90],
	["도약 발판 · 바람의 초원 (개인전)", 2, "dm_open_steppe", 90],
	["자기장 1단계 수축 · 잿빛 대도시 (배틀그라운드 75초)", 3, "br_ashen_metropolis", 2250],
]
## Preset fast-forward budget: ticks per step_ticks call and wall-clock ms of
## stepping per frame (headless probe: frames every 40-85 ms, total time no
## longer than the old blocking loop).
const PRESET_CHUNK: int = 2
const PRESET_FRAME_MS: int = 30
var app: App
var runner: BattleRunner
var view: BattleView
var arena_area: Control
var mode_option: OptionButton
var map_option: OptionButton
var seed_input: SpinBox
var count_input: SpinBox
var squad_option: OptionButton
var squad_field: Control
var ai_options: Array[OptionButton] = []
var roster_options: Array[OptionButton] = []
var roster_labels: Array[Label] = []
var roster_box: VBoxContainer
var roster_button: Button
var roster_grid: GridContainer
var unit_option: OptionButton
var perspective_option: OptionButton
var inspector: RichTextLabel
var status_label: Label
var hint_label: Label
var run_button: Button
var environment_toggle: CheckButton
var speed_option: OptionButton
var map_ids: Array[String] = []
var last_config: Dictionary = {}
var interventions: Array = []
var selected_unit: int = 0
var refresh_left: float = 0.0
var cycle_offset: int = 0
var dragging: bool = false
var last_report_path: String = ""
var environment_initial: bool = true
var type_buttons: Dictionary = {}
var type_row: HFlowContainer
var type_initial: Dictionary = {}
var preset_option: OptionButton
## A gimmick preset is fast-forwarding (run_preset); preset_note is its progress line.
var preset_busy: bool = false
var preset_note: String = ""


func bind(owner_app: App) -> void:
	app = owner_app


func _ready() -> void:
	runner = BattleRunner.new()
	add_child(runner)
	var page: VBoxContainer = UITheme.vbox(10)
	var margin: MarginContainer = UITheme.margin(page, 18, 16, 18, 14)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	page.add_child(UITheme.page_header(App.VERSION + " · DEVELOPER PLAY", "전장 실험실", "맵·시드·%d인 편성을 고르고 AI를 관찰합니다. 기믹을 종류별로 켜고 끌 수 있습니다. 실험은 일반 전적에 기록되지 않습니다." % DB.characters.size()))
	var config_row: HBoxContainer = UITheme.hbox(10)
	page.add_child(config_row)
	mode_option = OptionButton.new()
	for title in MODE_LABELS:
		mode_option.add_item(title)
	mode_option.select(1)
	mode_option.item_selected.connect(func(_index: int): _change_mode())
	config_row.add_child(_field("경기 규칙", mode_option))
	map_option = OptionButton.new()
	map_option.custom_minimum_size.x = 250
	map_option.item_selected.connect(func(_index: int): _map_hint())
	config_row.add_child(_field("전장", map_option))
	seed_input = SpinBox.new()
	seed_input.min_value = 1
	seed_input.max_value = 2147483647
	seed_input.step = 1
	seed_input.value = 152001
	seed_input.custom_minimum_size.x = 135
	config_row.add_child(_field("재현 시드", seed_input))
	count_input = SpinBox.new()
	count_input.min_value = 1
	count_input.max_value = 5
	count_input.step = 1
	count_input.value = 3
	count_input.value_changed.connect(func(_value: float): _roster_visibility())
	config_row.add_child(_field("팀당 인원 / 개인전 인원", count_input))
	# Battleground only: squad size (the count above is then the number of players / teams).
	squad_option = OptionButton.new()
	for label in SQUAD_LABELS:
		squad_option.add_item(label)
	squad_option.select(0)
	squad_option.tooltip_text = UITheme.tip("배틀그라운드 형식입니다. 솔로는 같은 영웅을 여러 명 넣을 수 있고, 듀오·트리오는 같은 팀 안에서만 중복할 수 없습니다.")
	squad_option.item_selected.connect(func(_index: int):
		_count_limits()
		_roster_visibility())
	squad_field = _field("배틀그라운드 형식", squad_option)
	config_row.add_child(squad_field)
	for side in 2:
		var option: OptionButton = OptionButton.new()
		for kind in AIFactory.ORDER:
			option.add_item(AIFactory.label(kind))
		option.custom_minimum_size.x = 165
		ai_options.append(option)
		config_row.add_child(_field("청 AI / 개인전 AI" if side == 0 else "홍 AI", option))
	var roster_row: HBoxContainer = UITheme.hbox(10)
	page.add_child(roster_row)
	roster_button = UITheme.button("영웅 편성 펼치기", "", func():
		roster_box.visible = not roster_box.visible
		roster_button.text = "영웅 편성 접기" if roster_box.visible else "영웅 편성 펼치기")
	roster_row.add_child(roster_button)
	roster_row.add_child(UITheme.button("다음 영웅 그룹", "", _cycle_roster, "%d명 전체를 순서대로 편성해 서로 다른 스킬 조합을 확인합니다." % DB.characters.size()))
	roster_row.add_child(UITheme.button("새 조건 시작", "PrimaryButton", start_case))
	roster_row.add_child(UITheme.button("같은 조건 재시작", "", restart_case))
	roster_row.add_child(UITheme.button("다음 시드", "", func(): seed_input.value = int(seed_input.value) + 1))
	preset_option = OptionButton.new()
	preset_option.add_item("기믹 테스트 프리셋…")
	for preset in GIMMICK_PRESETS:
		preset_option.add_item(str(preset[0]))
	preset_option.tooltip_text = "기믹이 있는 전장을 골라 바로 시작하고, 기믹이 처음 작동하는 시점까지 진행한 뒤 일시정지합니다."
	preset_option.item_selected.connect(func(index: int):
		if index > 0:
			run_preset(index - 1)
		preset_option.select(0))
	roster_row.add_child(preset_option)
	roster_box = UITheme.vbox(6)
	roster_box.visible = false
	page.add_child(roster_box)
	roster_grid = GridContainer.new()
	roster_grid.columns = 6
	roster_grid.add_theme_constant_override("h_separation", 8)
	roster_grid.add_theme_constant_override("v_separation", 6)
	roster_box.add_child(roster_grid)
	for index in ROSTER_SLOTS:
		var column: VBoxContainer = UITheme.vbox(2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title: Label = UITheme.label("", "CaptionLabel")
		roster_labels.append(title)
		column.add_child(title)
		var hero_option: OptionButton = OptionButton.new()
		for character in DB.characters:
			hero_option.add_item(character.name)
			hero_option.set_item_metadata(hero_option.item_count - 1, character.id)
		hero_option.select(index % DB.characters.size())
		hero_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(hero_option)
		roster_options.append(hero_option)
		roster_grid.add_child(column)
	hint_label = UITheme.label("", "CaptionLabel")
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint_label)
	var body: HBoxContainer = UITheme.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	arena_area = Control.new()
	arena_area.clip_contents = true
	arena_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_area.custom_minimum_size = Vector2(320, 220)
	body.add_child(arena_area)
	var floor_bg: ColorRect = ColorRect.new()
	floor_bg.color = Color("#060d16")
	floor_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena_area.add_child(floor_bg)
	view = BattleView.new()
	view.visible = false
	view.hud_readable = true
	view.hitstop_enabled = false
	view.shake_enabled = false
	arena_area.add_child(view)
	arena_area.resized.connect(_fit_view)
	arena_area.gui_input.connect(_arena_input)
	runner.stepped.connect(func(events: Array): view.on_step(events))
	runner.finished.connect(func(_result: Dictionary): _refresh_inspector())
	var detail: VBoxContainer = UITheme.vbox(8)
	detail.custom_minimum_size.x = 310
	body.add_child(detail)
	detail.add_child(UITheme.label("실시간 검사", "BoldLabel"))
	unit_option = OptionButton.new()
	unit_option.item_selected.connect(func(index: int):
		selected_unit = int(unit_option.get_item_metadata(index))
		view.selected = selected_unit
		_refresh_inspector())
	detail.add_child(unit_option)
	perspective_option = OptionButton.new()
	perspective_option.add_item("관찰자 전체 시야")
	perspective_option.item_selected.connect(func(index: int): view.set_perspective(index - 1))
	detail.add_child(perspective_option)
	inspector = RichTextLabel.new()
	inspector.bbcode_enabled = false
	inspector.selection_enabled = true
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_theme_font_size_override("normal_font_size", 13)
	detail.add_child(inspector)
	detail.add_child(UITheme.button("재현 정보 저장", "", save_report))
	detail.add_child(UITheme.button("저장 폴더 열기", "", func():
		DirAccess.make_dir_recursive_absolute("user://developer_reports")
		OS.shell_open(ProjectSettings.globalize_path("user://developer_reports"))))
	var playback: HBoxContainer = UITheme.hbox(8)
	page.add_child(playback)
	run_button = UITheme.button("재생 / 정지  Space", "", toggle_pause)
	playback.add_child(run_button)
	playback.add_child(UITheme.button("1틱  .", "", func(): advance_ticks(1)))
	playback.add_child(UITheme.button("1초 진행", "", func(): advance_ticks(30)))
	playback.add_child(UITheme.button("전체 보기", "", func(): view.set_cam_mode("full")))
	playback.add_child(UITheme.button("영웅 추적", "", func(): view.set_cam_mode("auto")))
	speed_option = OptionButton.new()
	for speed in [0.5, 1.0, 2.0, 4.0]:
		speed_option.add_item("%s×" % speed)
		speed_option.set_item_metadata(speed_option.item_count - 1, speed)
	speed_option.select(1)
	speed_option.item_selected.connect(func(index: int): runner.speed = float(speed_option.get_item_metadata(index)))
	playback.add_child(speed_option)
	environment_toggle = CheckButton.new()
	environment_toggle.text = "환경 기믹"
	environment_toggle.button_pressed = true
	environment_toggle.toggled.connect(set_environment_enabled)
	playback.add_child(environment_toggle)
	# Per-type switches: only the types present on the selected map are shown.
	type_row = HFlowContainer.new()
	type_row.add_theme_constant_override("h_separation", 6)
	type_row.add_theme_constant_override("v_separation", 4)
	type_row.add_child(UITheme.label("기믹별", "CaptionLabel"))
	for typ in TYPE_ORDER:
		var info: Dictionary = CodexData.hazard(typ)
		var b: Button = Button.new()
		b.toggle_mode = true
		b.button_pressed = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(info.get("label", typ))
		b.tooltip_text = UITheme.tip("%s 켜기/끄기 (sim.env.set_type_enabled)\n%s" % [str(info.get("label", typ)), str(info.get("desc", ""))])
		b.add_theme_font_size_override("font_size", 13)
		b.toggled.connect(func(on: bool): set_type_enabled(typ, on))
		type_buttons[typ] = b
		type_row.add_child(b)
	page.add_child(type_row)
	status_label = UITheme.label("전장과 편성을 선택한 뒤 새 조건 시작을 누르세요.", "CaptionLabel")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status_label)
	_change_mode()
	_fit_view.call_deferred()


func _field(title: String, control: Control) -> VBoxContainer:
	var box: VBoxContainer = UITheme.vbox(3)
	box.add_child(UITheme.label(title, "CaptionLabel"))
	box.add_child(control)
	return box


func mode_key() -> String:
	return MODES[clampi(mode_option.selected, 0, MODES.size() - 1)]


func squad() -> int:
	return squad_option.selected + 1


func _change_mode() -> void:
	map_ids.clear()
	map_option.clear()
	var mode: String = mode_key()
	if mode == "battleground":
		# Generated per seed: the picker lists the presets (the hint builds the map for the seed).
		for c in DB.battleground_catalogue():
			map_ids.append(str(c.id))
			map_option.add_item("%s · %d×%d" % [str(c.name), int(c.width), int(c.height)])
	else:
		for arena in DB.arenas_for(mode):
			map_ids.append(str(arena.data.get("preset", arena.id)))
			map_option.add_item(map_item_text(arena))
	var ffa: bool = mode == "deathmatch" or mode == "battleground"
	_count_limits()
	ai_options[0].disabled = ffa
	ai_options[0].text = "생존·교전 AI (자동)" if ffa else AIFactory.label(AIFactory.ORDER[ai_options[0].selected])
	ai_options[1].disabled = ffa
	squad_field.visible = mode == "battleground"
	_roster_visibility()
	_map_hint()


## Count limits per mode: team size 1-5, deathmatch 2-12 players, battleground 2-30 players /
## 2-15 duos / 2-10 trios.
func _count_limits() -> void:
	match mode_key():
		"deathmatch":
			count_input.min_value = 2
			count_input.max_value = 12
		"battleground":
			count_input.min_value = 2
			count_input.max_value = floori(float(ROSTER_SLOTS) / float(squad()))
		_:
			count_input.min_value = 1
			count_input.max_value = 5


## Roster slots in use: team modes 2 x count, deathmatch count, battleground count x squad.
func roster_count() -> int:
	var count: int = int(count_input.value)
	match mode_key():
		"deathmatch":
			return count
		"battleground":
			return count * squad()
	return count * 2


func _roster_visibility() -> void:
	var mode: String = mode_key()
	var count: int = int(count_input.value)
	var used: int = roster_count()
	match mode:
		"deathmatch":
			roster_grid.columns = mini(count, 6)
		"battleground":
			roster_grid.columns = mini(used, 6)
		_:
			roster_grid.columns = count
	for i in roster_options.size():
		roster_options[i].get_parent().visible = i < used
		match mode:
			"deathmatch":
				roster_labels[i].text = "참가자 %d" % (i + 1)
			"battleground":
				var sq: int = squad()
				roster_labels[i].text = ("P%d" % (i + 1)) if sq <= 1 else ("%s %d" % [DB.team_name(floori(float(i) / float(sq)), sq), i % sq + 1])
			_:
				roster_labels[i].text = "%s %d" % ["청" if i < count else "홍", i % count + 1]


func _cycle_roster() -> void:
	cycle_offset = (cycle_offset + roster_count()) % DB.characters.size()
	for i in roster_options.size():
		roster_options[i].select((cycle_offset + i) % DB.characters.size())
	status_label.text = "편성을 변경했습니다. 새 조건 시작으로 적용합니다."


func _map_hint() -> void:
	if map_ids.is_empty():
		return
	var id: String = map_ids[map_option.selected]
	var mode: String = mode_key()
	var arena: Arena
	if mode == "battleground":
		# The map of this seed (DB keeps it, so the next start reuses it).
		arena = DB.battleground_arena(id, int(seed_input.value))
	else:
		arena = DB.deathmatch_preview(id) if mode == "deathmatch" else DB.arena(id)
	var facts: Array = []
	for f in (CodexData.arena_layout_facts(arena) if arena.ruleset != "deathmatch" else []):
		facts.append(str(f[0]))
	var gimmicks: Array = []
	for g in CodexData.arena_gimmicks(arena):
		var label: String = str(g.label) + (" ×%d" % int(g.count) if int(g.count) > 1 else "")
		if not gimmicks.has(label):
			gimmicks.append(label)
	if arena.ruleset == "deathmatch" and not arena.forests.is_empty():
		gimmicks.append(CodexData.BRUSH_DM_LABEL)
	if arena.ruleset == "battleground":
		facts.append("시드 %d 배치 · 자기장 %d단계 · 아이템 %d개" % [int(seed_input.value), BrZone.PHASES, BattlegroundMode.ITEM_COUNT])
	hint_label.text = "%s · %s%s\n기믹: %s\n설정 변경은 다음 시작에 적용됩니다. 휠 확대 · 오른쪽 드래그 이동 · 클릭 영웅 선택" % [arena.name, str(arena.data.get("subtitle", "")),
		(" · " + " · ".join(PackedStringArray(facts))) if not facts.is_empty() else "", ", ".join(PackedStringArray(gimmicks)) if not gimmicks.is_empty() else "없음"]
	_sync_type_buttons(arena)


## Map picker text: name · size · spawn orientation (team modes).
static func map_item_text(arena: Arena) -> String:
	if arena.ruleset == "deathmatch":
		return "%s · %d×%d" % [arena.name, int(arena.width), int(arena.height)]
	var orient: String = CodexData.orientation_label(arena)
	return "%s · %d×%d%s" % [arena.name, int(arena.width), int(arena.height), (" · %s" % orient) if orient != "" else ""]


## Types present on an arena (hazards, gates, brush) in TYPE_ORDER.
static func arena_types(arena: Arena) -> Array:
	var present: Dictionary = {}
	for h in arena.hazards:
		present[str(h.get("type", ""))] = true
	if not arena.gates.is_empty():
		present["gate"] = true
	if not arena.forests.is_empty():
		present["brush"] = true
	var out: Array = []
	for typ in TYPE_ORDER:
		if present.has(typ):
			out.append(typ)
	return out


func _sync_type_buttons(arena: Arena) -> void:
	var types: Array = arena_types(arena)
	for typ in type_buttons:
		(type_buttons[typ] as Button).visible = types.has(typ)
	type_row.visible = not types.is_empty()


func set_type_enabled(typ: String, on: bool) -> void:
	if runner.sim:
		runner.sim.env.set_type_enabled(typ, on)
		interventions.append({"tick": runner.sim.tick, "type": typ, "enabled": on})
		# Brush / mud layers: the view redraws them when the switch state changes.
	_refresh_inspector()


## Quick gimmick test: picks the mode and map, starts a fresh case and advances to the
## first interesting moment (paused). A coroutine: the fast-forward (up to 1170
## ticks) runs in chunks of about PRESET_FRAME_MS per frame so the window keeps
## drawing and the status line shows progress; the step sequence is the same as
## manual stepping. Starting another case meanwhile stops it. Callers that need
## the result await it.
func run_preset(index: int) -> void:
	if index < 0 or index >= GIMMICK_PRESETS.size() or preset_busy:
		return
	var preset: Array = GIMMICK_PRESETS[index]
	mode_option.select(int(preset[1]))
	_change_mode()
	var map_index: int = map_ids.find(str(preset[2]))
	if map_index < 0:
		return
	map_option.select(map_index)
	_map_hint()
	if int(preset[1]) == 2:
		count_input.value = maxf(count_input.value, 6.0)
	elif int(preset[1]) == 3:
		squad_option.select(0)
		_count_limits()
		count_input.value = maxf(count_input.value, 12.0)
	var previous: BattleSim = runner.sim
	start_case()
	var sim: BattleSim = runner.sim
	if sim == null or sim == previous:
		return  # start_case refused the roster; its message stays on the status line
	var target: int = int(preset[3])
	var left: int = target
	if left > 0:
		preset_busy = true
		preset_option.disabled = true
		while left > 0 and runner.sim == sim and not runner.done:
			var started: int = Time.get_ticks_msec()
			while left > 0 and not runner.done and Time.get_ticks_msec() - started < PRESET_FRAME_MS:
				var n: int = runner.step_ticks(mini(left, PRESET_CHUNK))
				left = 0 if n == 0 else left - n
			# Only the status line per frame; _process refreshes the inspector every 0.25 s.
			preset_note = "기믹 테스트 진행 중: %s · %d / %d틱" % [str(preset[0]), sim.tick, target]
			status_label.text = preset_note
			if left > 0 and not runner.done and is_inside_tree():
				await get_tree().process_frame
		preset_busy = false
		preset_note = ""
		preset_option.disabled = false
		if runner.sim != sim:
			return  # another case was started meanwhile
	_refresh_inspector()
	status_label.text = "기믹 테스트: %s · %s" % [str(preset[0]), status_label.text]


func selected_config() -> Dictionary:
	var ruleset: String = MODES[mode_option.selected]
	var count: int = int(count_input.value)
	var ids: Array = []
	for i in roster_count():
		ids.append(roster_options[i].get_selected_metadata())
	if ruleset == "battleground":
		# DESIGN_V2 §3.5 start config: the visible slots split into squads in order.
		var sq: int = squad()
		var teams: Array = []
		for t in count:
			teams.append(ids.slice(t * sq, t * sq + sq))
		return {"ruleset": ruleset, "mode": "battleground", "arena_id": map_ids[map_option.selected], "seed": int(seed_input.value),
			"squad": sq, "teams": teams, "zone_speed": "normal", "max_time": BattlegroundMode.MAX_TIME, "ai": "tactician"}
	var config: Dictionary = {"ruleset": ruleset, "arena_id": map_ids[map_option.selected], "seed": int(seed_input.value),
		"max_time": 420.0 if ruleset == "deathmatch" else (480.0 if ruleset == "control" else 150.0),
		"blue_ai": AIFactory.ORDER[ai_options[0].selected], "red_ai": AIFactory.ORDER[ai_options[1].selected],
		"ai": AIFactory.ORDER[ai_options[0].selected], "kill_target": 10}
	if ruleset == "deathmatch":
		config["players"] = ids
	else:
		config["blue"] = ids.slice(0, count)
		config["red"] = ids.slice(count, count * 2)
	return config


func start_case() -> void:
	var config: Dictionary = selected_config()
	if str(config.get("ruleset", "")) == "battleground":
		# Solo may repeat a hero; a squad may not hold the same hero twice.
		var errors: Array = BattlegroundMode.validate(config)
		if not errors.is_empty():
			status_label.text = "같은 팀 안에 같은 영웅을 두 번 넣을 수 없습니다. 편성을 확인하세요. (%s)" % str(errors[0])
			return
	for team in ([] if str(config.get("ruleset", "")) == "battleground" else [config.get("players", []), config.get("blue", []), config.get("red", [])]):
		var unique: Dictionary = {}
		for id in team:
			if unique.has(id):
				status_label.text = "같은 팀 또는 개인전 참가자에 같은 영웅을 두 번 넣을 수 없습니다. 편성을 확인하세요."
				return
			unique[id] = true
	last_config = config.duplicate(true)
	environment_initial = environment_toggle.button_pressed
	type_initial.clear()
	for typ in type_buttons:
		type_initial[typ] = (type_buttons[typ] as Button).button_pressed
	_start_config(last_config)


func _start_config(config: Dictionary) -> void:
	view.visible = false
	view.sim = null
	view.runner = null
	runner.start(config)
	runner.paused = true
	runner.speed = float(speed_option.get_selected_metadata())
	runner.sim.env.enabled = environment_initial
	environment_toggle.set_pressed_no_signal(environment_initial)
	for typ in type_buttons:
		var on: bool = bool(type_initial.get(typ, true))
		(type_buttons[typ] as Button).set_pressed_no_signal(on)
		if not on:
			runner.sim.env.set_type_enabled(typ, false)
	interventions.clear()
	view.setup(runner.sim, runner)
	view.visible = true
	view.set_cam_mode("full")
	view.hitstop_enabled = false
	view.shake_enabled = false
	selected_unit = 0
	view.selected = selected_unit
	unit_option.clear()
	var br: BattlegroundMode = runner.sim.battleground
	for unit in runner.sim.heroes:
		var tag: String = br.team_label(unit.team) if br else ("P%d" % (unit.team + 1) if runner.sim.is_deathmatch() else DB.TEAM_NAMES[unit.team])
		unit_option.add_item("%s · %s" % [tag, unit.def.name])
		unit_option.set_item_metadata(unit_option.item_count - 1, unit.idx)
	perspective_option.clear()
	perspective_option.add_item("관찰자 전체 시야")
	for team in runner.sim.team_count:
		perspective_option.add_item(("%s의 시야" % br.team_label(team)) if br else ("AI %d팀의 시야" % (team + 1)))
	view.set_perspective(-1)
	_fit_view()
	_refresh_inspector()


func restart_case() -> void:
	if last_config.is_empty():
		start_case()
	else:
		_start_config(last_config)


func toggle_pause() -> void:
	if preset_busy:
		return  # the preset fast-forward owns the runner until it pauses on its tick
	if runner.sim == null:
		start_case()
	if runner.sim and not runner.done:
		runner.paused = not runner.paused
	_refresh_inspector()


func advance_ticks(ticks: int) -> void:
	if preset_busy:
		return
	if runner.sim == null:
		start_case()
	runner.step_ticks(ticks)
	_refresh_inspector()


func set_environment_enabled(enabled: bool) -> void:
	if runner.sim:
		runner.sim.env.enabled = enabled
		interventions.append({"tick": runner.sim.tick, "environment_enabled": enabled})
	_refresh_inspector()


func _fit_view() -> void:
	if view:
		view.fit(Rect2(Vector2.ZERO, arena_area.size))


func on_show(_args: Dictionary = {}) -> void:
	set_process(true)
	_fit_view.call_deferred()


func on_hide() -> void:
	runner.paused = true
	set_process(false)


func _process(delta: float) -> void:
	refresh_left -= delta
	if refresh_left <= 0.0:
		refresh_left = 0.25
		_refresh_inspector()


func _refresh_inspector() -> void:
	if runner == null or runner.sim == null:
		return
	var sim: BattleSim = runner.sim
	run_button.text = "재생  Space" if runner.paused else "일시정지  Space"
	status_label.text = "%s · 시드 %d · %.2f초 / %d틱 · %s · 시뮬 %.2fms · %d FPS" % [sim.arena.name, sim.seed_value, sim.time, sim.tick,
		"종료" if runner.done else ("일시정지" if runner.paused else "재생 중"), runner.step_ms, Engine.get_frames_per_second()]
	if preset_busy and preset_note != "":
		status_label.text = preset_note + " · " + status_label.text
	var lines: Array[String] = []
	lines.append("환경 기믹 — %s" % ("작동" if sim.env.enabled else "비활성"))
	for state in sim.env.state_snapshot():
		lines.append(env_state_line(sim, state))
	if not sim.arena.forests.is_empty():
		lines.append("%s  %s  무리 %d" % [CodexData.hazard_label("brush", sim.deathmatch != null and not sim.is_battleground()), "작동" if sim.env.type_active("brush") else "꺼짐", _patch_count(sim.arena)])
	if sim.battleground != null:
		lines.append_array(br_state_lines(sim))
	if sim.arena.hazards.is_empty() and sim.arena.gates.is_empty() and sim.arena.forests.is_empty():
		lines.append("이 전장은 환경 기믹이 없습니다.")
	var unit: BUnit = sim.u_at(selected_unit)
	if unit and unit.def:
		lines.append("\n%s · HP %.0f / %.0f" % [unit.def.name, unit.hp, sim.max_hp(unit)])
		lines.append("위치 %.0f, %.0f · 이동 %.0f" % [unit.pos.x, unit.pos.y, sim.stat(unit, &"moveSpeed")])
		for i in unit.def.abilities.size():
			lines.append("S%d %s · 쿨 %.1f" % [i + 1, unit.def.abilities[i].name, maxf(0.0, unit.cooldowns[i] - sim.time)])
		var controller: TeamController = sim.controllers[unit.team]
		var decision: Dictionary = controller.explain(unit) if controller else {}
		lines.append("\nAI 목적: %s" % decision.get("purpose", unit.command.get("purpose", "대기")))
		lines.append("전술: %s · 역할: %s" % [decision.get("stance", ""), decision.get("role", "")])
		for top in (decision.get("top", []) as Array).slice(0, 3):
			lines.append(JSON.stringify(top))
		lines.append("AI 적 관측/추정:")
		for belief in decision.get("beliefs", []):
			lines.append("%s · %s · 신뢰 %.0f%%" % [belief.get("name", ""), "현재 관측" if belief.get("visible", false) else "기억 추정", float(belief.get("conf", 0.0)) * 100.0])
	lines.append("\n최근 이벤트:")
	for event in sim.log.slice(maxi(0, sim.log.size() - 10)):
		lines.append("%.1f %s" % [float(event.get("time", event.get("t", sim.time))), str(event.get("type", ""))])
	inspector.text = "\n".join(lines)


static func _patch_count(a: Arena) -> int:
	var patches: Dictionary = {}
	for p in a.forest_patch:
		patches[int(p)] = true
	return patches.size()


## Battleground inspector rows: the public zone view, field items and who is still in.
static func br_state_lines(sim: BattleSim) -> Array:
	var br: BattlegroundMode = sim.battleground
	var v: Dictionary = br.zone_view()
	var state: String = {"loot": "약탈", "wait": "대기", "shrink": "수축 중", "final": "최종"}.get(str(v.state), str(v.state))
	var t_end: float = float(v.t_state_end)
	var out: Array = []
	out.append("자기장  %d/%d · %s%s · 반경 %d%s · %s" % [int(v.phase), int(v.phases_total), state, (" %.1fs 남음" % maxf(0.0, t_end - sim.time)) if is_finite(t_end) else "",
		int(float(v.radius)), (" → 다음 %d" % int(float(v.next_radius))) if bool(v.next_known) else "", ZonePill.dps_text(float(v.dps_ratio))])
	var by_rarity: Array = [0, 0, 0, 0, 0]
	for it in br.field:
		var r: int = clampi(ItemDefs.rarity_of(str(it.item)), 0, 4)
		by_rarity[r] = int(by_rarity[r]) + 1
	out.append("필드 아이템  %d개 · 등급별 %s" % [br.field.size(), "/".join(PackedStringArray(by_rarity.map(func(x): return str(x))))])
	out.append("생존  %d명 · %d팀 · 다운 %d명" % [br.alive_hero_count(), br.alive_team_count(), br.downed.size()])
	return out


## One inspector line per public environment row (ArenaEnv.state_snapshot), with the
## V1.5.3 fields: gate group/open, artillery strikes, ring radius, pad landing, mud slow.
static func env_state_line(sim: BattleSim, state: Dictionary) -> String:
	var typ: String = str(state.get("type", ""))
	var label: String = "%s(%s)" % [CodexData.hazard_label(typ, sim.deathmatch != null and not sim.is_battleground()), str(state.get("id", ""))]
	if not bool(state.get("enabled", true)):
		return "%s  꺼짐" % label
	var phase: String = "예고" if bool(state.get("warning", false)) else ("작동" if bool(state.get("active", false)) else "대기")
	match typ:
		"gate":
			return "%s  %s조 %s  %.1fs 남음" % [label, str(state.get("group", "")), ("닫히는 중" if bool(state.get("warning", false)) else "열림") if bool(state.get("open", false)) else "닫힘",
				float(state.get("remaining", 0.0))]
		"artillery":
			var pending: int = int(state.get("pending_strikes", 0))
			if pending > 0:
				return "%s  예고 %d발 · 착탄 %.1fs 후 · 반경 %d" % [label, pending, maxf(0.0, float(state.get("next_impact_t", 0.0)) - sim.time), int(float(state.get("strike_radius", 0.0)))]
			return "%s  대기 · 반경 %d" % [label, int(float(state.get("strike_radius", 0.0)))]
		"closing_ring":
			var t0: float = float(state.get("start_time", 0.0))
			var t1: float = float(state.get("end_time", 0.0))
			var stage: String = "수축 전 %.1fs" % (t0 - sim.time) if sim.time < t0 else ("수축 중 %.1fs" % (t1 - sim.time) if sim.time < t1 else "최종")
			return "%s  %s · 안전 반경 %d → %d" % [label, stage, int(float(state.get("safe_radius", 0.0))), int(float(state.get("final_radius", 0.0)))]
		"jump_pad":
			var land: Vector2 = state.get("landing", Vector2.ZERO)
			return "%s  작동 · 착지 %d,%d · 비행 %.2fs" % [label, int(land.x), int(land.y), float(state.get("flight_time", 0.0))]
		"mud":
			return "%s  작동 · 둔화 %d%%" % [label, int(roundf(float(state.get("slow", 0.0)) * 100.0))]
		"healing_fountain":
			return "%s  %s  쿨 %.1fs" % [label, "준비" if float(state.get("cooldown_remaining", 0.0)) <= 0.0 else "충전", float(state.get("cooldown_remaining", 0.0))]
	return "%s  %s  %.1fs" % [label, phase, float(state.get("remaining", 0.0))]


func snapshot() -> Dictionary:
	if runner.sim == null:
		return {}
	var sim: BattleSim = runner.sim
	var units: Array = []
	for unit in sim.heroes:
		var controller: TeamController = sim.controllers[unit.team]
		units.append({"idx": unit.idx, "id": unit.def.id, "team": unit.team, "alive": unit.alive,
			"position": [unit.pos.x, unit.pos.y], "health": unit.hp, "cooldowns": Array(unit.cooldowns),
			"decision": controller.explain(unit) if controller else {}})
	return {"version": App.VERSION, "config": last_config.duplicate(true), "tick": sim.tick, "time": sim.time,
		"environment_initial": environment_initial, "environment_types_initial": type_initial.duplicate(), "interventions": interventions.duplicate(true),
		"environment": sim.env.state_snapshot(), "units": units, "events": sim.log.duplicate(true),
		"note": "관찰자용 진단 자료입니다. AI 입력에 추가 정보를 주지 않습니다. 동일 config로 시작하고 기록된 tick에서 환경 토글을 재현하십시오."}


## Report values JSON can carry: non-finite floats (e.g. a battleground artillery with no salvo
## pending reports next_impact_t = INF) become the strings "INF" / "-INF" / "NAN".
static func json_safe(v: Variant) -> Variant:
	if v is float and not is_finite(v):
		return "NAN" if is_nan(v) else ("INF" if v > 0.0 else "-INF")
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(json_safe(x))
		return a
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v:
			d[k] = json_safe(v[k])
		return d
	return v


func save_report() -> void:
	if runner.sim == null:
		status_label.text = "먼저 실험을 시작하세요."
		return
	DirAccess.make_dir_recursive_absolute("user://developer_reports")
	last_report_path = "user://developer_reports/case_%d_%d_%d.json" % [runner.sim.seed_value, runner.sim.tick, int(Time.get_unix_time_from_system())]
	var file: FileAccess = FileAccess.open(last_report_path, FileAccess.WRITE)
	if file == null:
		status_label.text = "재현 정보 저장 실패: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(json_safe(snapshot()), "\t"))
	file.close()
	status_label.text = "저장 완료: " + ProjectSettings.globalize_path(last_report_path)
	refresh_left = 6.0


func _arena_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and runner.sim:
			var index: int = view.pick_unit(view.to_world(mouse.position))
			if index >= 0 and runner.sim.u_at(index).def != null:
				selected_unit = index
				view.selected = index
				for i in unit_option.item_count:
					if int(unit_option.get_item_metadata(i)) == index:
						unit_option.select(i)
				_refresh_inspector()
		elif mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			view.manual_zoom(1.12 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, mouse.position)
		elif mouse.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = mouse.pressed
	elif event is InputEventMouseMotion and dragging:
		view.manual_pan((event as InputEventMouseMotion).relative)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_PERIOD: advance_ticks(1)
		KEY_R: restart_case()
		KEY_F8: save_report()
		_: return
	get_viewport().set_input_as_handled()
