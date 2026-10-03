class_name LivePreview
extends Control

## Looping AI-vs-AI 3v3 battle used as the home hero visual. Public API: set_active(), runner, view,
## info (arena name label). The top bar shows a drawn "● LIVE" dot, the arena and team-coloured
## rosters; corner_radius > 0 masks the corners with frame_color so the preview sits flush inside a
## rounded card.

var runner: BattleRunner
var view: BattleView
var info: Label
var blue_l: Label
var red_l: Label
var rng: = RandomNumberGenerator.new()
var restart_at: float = -1.0
var clock: float = 0.0
var active: bool = false
## Colour of the surface around the preview (used to mask the rounded corners).
var frame_color: Color = UITheme.PANEL2
## Corner radius of the rounded frame (0 = square, no mask).
var corner_radius: float = 0.0
const BAR_H: = 32.0

var _dot: LiveDot
var _frame: FrameMask
var _dot_acc: float = 0.0
static var _bar_style: StyleBoxFlat


func _ready() -> void :
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	runner = BattleRunner.new()
	add_child(runner)
	view = BattleView.new()
	view.sound = false
	view.show_names = false
	view.show_numbers = true
	add_child(view)

	if _bar_style == null:
		# Soft translucent bar with a single hairline at the bottom (shared by every preview).
		_bar_style = UITheme.sb(Color(UITheme.BG2, 0.78), Color(UITheme.LINE, 0.9), 0, 0, 14, 0)
		_bar_style.border_width_bottom = 1
	var bar: = UITheme.styled_panel(_bar_style)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, BAR_H)
	var h: = UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(h)

	_dot = LiveDot.new()
	h.add_child(_dot)
	var live: = UITheme.label("LIVE", "EyebrowLabel", 0, UITheme.RED.lightened(0.25))
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(live)
	h.add_child(_bar_sep())
	info = UITheme.label("", "", 13, UITheme.TEXT)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(info)
	h.add_child(UITheme.spacer())
	blue_l = UITheme.label("", "", 13, UITheme.BLUE.lightened(0.28))
	blue_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	blue_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(blue_l)
	var vs: = UITheme.label("vs", "FaintLabel", 12)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vs)
	red_l = UITheme.label("", "", 13, UITheme.RED.lightened(0.22))
	red_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(red_l)
	add_child(bar)

	_frame = FrameMask.new()
	_frame.owner_preview = self
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_frame)

	runner.stepped.connect( func(evs): view.on_step(evs))
	runner.finished.connect( func(_r): restart_at = clock + 2.5)
	rng.randomize()


func _bar_sep() -> Control:
	var c: = ColorRect.new()
	c.color = UITheme.LINE2
	c.custom_minimum_size = Vector2(1, 14)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func set_active(v: bool) -> void :
	active = v
	if runner:
		runner.paused = not v
	if v and (runner.sim == null):
		_new_battle()


func _new_battle() -> void :
	var ids: = DB.ids().duplicate()
	var blue: Array = []
	var red: Array = []
	for i in 3:
		blue.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
		red.append(ids.pop_at(rng.randi_range(0, ids.size() - 1)))
	var available: Array = DB.arenas_for("elimination")
	var arena: Arena = available[rng.randi_range(0, available.size() - 1)]
	runner.start({"seed": rng.randi_range(1, 999999), "blue": blue, "red": red, "arena_id": arena.id, "blue_ai": "tactician", "red_ai": "tactician"})
	runner.speed = 1.25
	view.setup(runner.sim, runner)
	view.quality = mini(1, int(Settings.get_v("vfx_quality", 2)))
	view.fx.quality = view.quality
	_fit()
	var bn: Array = []
	for id in blue:
		bn.append(DB.char_def(id).name)
	var rn: Array = []
	for id in red:
		rn.append(DB.char_def(id).name)
	info.text = arena.name
	blue_l.text = " · ".join(bn)
	red_l.text = " · ".join(rn)
	restart_at = -1.0


func _fit() -> void :
	if view:
		view.fit(Rect2(Vector2(0, BAR_H), size - Vector2(0, BAR_H)))


func _notification(what: int) -> void :
	if what == NOTIFICATION_RESIZED:
		_fit()
		if _frame:
			_frame.queue_redraw()


func _process(delta: float) -> void :
	clock += delta
	if active and restart_at > 0.0 and clock >= restart_at:
		_new_battle()
	# The LIVE dot breathes at ~15 Hz while the preview runs (one tiny redraw, no layout work).
	if active and _dot:
		_dot_acc += delta
		if _dot_acc >= 1.0 / 15.0:
			_dot_acc = 0.0
			_dot.t = clock
			_dot.queue_redraw()


func _draw() -> void :
	draw_rect(Rect2(Vector2.ZERO, size), Color(UITheme.BG, 0.55))


## Pulsing red "live" dot (drawn, so it never depends on a font glyph).
class LiveDot:
	extends Control
	var t: float = 0.0

	func _init() -> void :
		custom_minimum_size = Vector2(12, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void :
		var c: = size * 0.5
		var k: = 0.5 + 0.5 * sin(t * 4.0)
		draw_circle(c, 3.0 + 2.5 * k, Color(UITheme.RED, 0.10 + 0.22 * (1.0 - k)))
		draw_circle(c, 3.2, UITheme.RED.lightened(0.1))


## Top-most overlay: masks the corners with the surrounding colour and draws a hairline frame.
class FrameMask:
	extends Control
	var owner_preview: LivePreview

	func _init() -> void :
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void :
		if owner_preview == null or owner_preview.corner_radius <= 0.0:
			return
		var r: = minf(owner_preview.corner_radius, minf(size.x, size.y) * 0.5)
		var col: = owner_preview.frame_color
		var corners: = [[Vector2(0, 0), Vector2(r, r), PI], [Vector2(size.x, 0), Vector2(size.x - r, r), PI * 1.5],
			[Vector2(size.x, size.y), Vector2(size.x - r, size.y - r), 0.0], [Vector2(0, size.y), Vector2(r, size.y - r), PI * 0.5]]
		for cn in corners:
			var pts: = PackedVector2Array([cn[0]])
			for i in 9:
				var a: float = float(cn[2]) + PI * 0.5 * float(i) / 8.0
				pts.append(Vector2(cn[1]) + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, col)
		draw_style_box(UITheme.sbc(UITheme.CLEAR, UITheme.LINE, int(r), 1, 0, 0), Rect2(Vector2.ZERO, size))
