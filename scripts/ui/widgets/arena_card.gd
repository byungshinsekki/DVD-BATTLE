class_name ArenaCard
extends Button
## Arena thumbnail card (custom drawn): mini-map, optional two-line caption, accent selection with a
## check badge. Disabled cards (e.g. the codex list) look normal but show no hover and no hand cursor.
## API: arena, selected, caption, set_selected(v), _get_minimum_size().


var arena: Arena
var selected: bool = false
var caption: bool = true

const CAPTION_H: = 52.0
const INSET: = 8.0


func _init(a: Arena) -> void :
	arena = a
	custom_minimum_size = Vector2(196, 150)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty: = StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, empty)
	tooltip_text = UITheme.tip(str(a.data.get("description", "")))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(_fit_height)


## Height the card needs at its current width (map aspect + caption). Button's C++ minimum size
## ignores this script virtual, so _fit_height() mirrors it into custom_minimum_size.y.
func _get_minimum_size() -> Vector2:
	var w: = maxf(size.x, custom_minimum_size.x)
	var mh: = maxf(0.0, w - INSET * 2.0) * arena.height / arena.width
	return Vector2(0.0, ceilf(INSET + mh + (CAPTION_H if caption else INSET)))


func _ready() -> void :
	_fit_height()


func _fit_height() -> void :
	var need: = _get_minimum_size().y
	if absf(custom_minimum_size.y - need) > 0.5:
		custom_minimum_size = Vector2(custom_minimum_size.x, need)


func set_selected(v: bool) -> void :
	selected = v
	queue_redraw()


func _draw() -> void :
	var interactive: = not disabled
	var cursor: = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
	if mouse_default_cursor_shape != cursor:
		mouse_default_cursor_shape = cursor
	var hover: = interactive and is_hovered()
	draw_style_box(_frame_style(hover, selected), Rect2(Vector2.ZERO, size))

	var mw: = size.x - INSET * 2.0
	var s: = mw / arena.width
	var mh: = arena.height * s
	var o: = Vector2(INSET, INSET)
	ArenaPainter.draw_floor(self, arena, s, o, 0)
	ArenaPainter.draw_hazards(self, arena, s, o, 0.0, 0, 0.0)
	ArenaPainter.draw_obstacles(self, arena, s, o, 0)
	ArenaPainter.draw_control_layout(self, arena, s, o)
	# Brush ("수풀", team modes) and forest canopy ("숲", deathmatch) in every mode.
	if not arena.forest_x.is_empty():
		ArenaPainter.draw_canopy(self, arena, s, o, 0.85, 0)
	if selected:
		draw_rect(Rect2(o, Vector2(mw, mh)), Color(UITheme.ACCENT, 0.7), false, 1.5)
		_draw_check(Vector2(o.x + mw - 13.0, o.y + 13.0))
	elif hover:
		draw_rect(Rect2(o, Vector2(mw, mh)), Color(1, 1, 1, 0.05))
	if not caption:
		return

	var y: = o.y + mh + 22.0
	var glyph: = str(arena.data.get("icon", "◎"))
	draw_string(DB.font_bold, Vector2(12, y), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, arena.accent)
	var name_w: = size.x - 34.0 - 10.0
	var name_col: = Color.WHITE if selected else UITheme.TEXT
	draw_string(DB.font_bold, Vector2(34, y), UITheme.fit_text(DB.font_bold, arena.name, 15, name_w), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_col)
	var sub: = str(arena.data.get("subtitle", ""))
	if sub != "":
		draw_string(DB.font_regular, Vector2(12, y + 19.0), UITheme.fit_text(DB.font_regular, sub, 13, size.x - 22.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)


## Card frame StyleBoxes, built once per (hover, selected) state and shared by every card.
static var _frames: Array = [null, null, null, null]


static func _frame_style(hover: bool, sel: bool) -> StyleBox:
	var k: int = (1 if hover else 0) + (2 if sel else 0)
	if _frames[k] == null:
		var bg: = UITheme.PANEL3 if hover else UITheme.PANEL2
		var border: = UITheme.LINE.lerp(UITheme.ACCENT, 0.5) if hover else UITheme.LINE
		if sel:
			bg = bg.lerp(UITheme.ACCENT, 0.08)
			border = UITheme.ACCENT
		_frames[k] = UITheme.sbc(bg, border, UITheme.R_L, 2 if sel else 1, 0, 0)
	return _frames[k]


func _draw_check(c: Vector2) -> void :
	draw_circle(c, 11.0, Color(UITheme.BG, 0.85), true, -1.0, true)
	draw_circle(c, 9.0, UITheme.ACCENT, true, -1.0, true)
	var pts: = PackedVector2Array([c + Vector2(-4.2, 0.2), c + Vector2(-1.2, 3.2), c + Vector2(4.4, -2.8)])
	draw_polyline(pts, UITheme.BG, 2.2, true)
