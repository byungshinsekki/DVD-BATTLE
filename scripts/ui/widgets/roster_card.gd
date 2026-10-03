class_name RosterCard
extends Button
## Character pick card (theme variation "CardButton"). set_picked(team, text) marks a pick with a
## team-coloured border, a drawn left edge and a badge sized to its text ("청", "나", "P10" ...) while
## the card stays at full opacity. Unpicked disabled cards dim their content. Hover emits hovered_def.
## set_count(n) shows a "×n" badge in the top-right corner when a hero is picked more than once
## (battleground solo allows duplicates); n <= 1 hides it.


signal hovered_def(def: Defs.CharDef)

var def: Defs.CharDef
var disc: GlyphDisc
var name_l: Label
var role_l: Label
var badge: Label
var count_badge: Label
var count: int = 0
var picked_team: int = -1
var _content: HBoxContainer
var _dimmed: bool = false

const DISC_PX: = 44.0
const PAD_L: = 10.0

# Shared per-team-colour style sets (built once, reused by every card).
static var _picked_styles: Dictionary = {}


func _init(d: Defs.CharDef) -> void :
	def = d
	custom_minimum_size = Vector2(158, 66)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme_type_variation = "CardButton"
	_content = UITheme.hbox(10)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = PAD_L
	_content.offset_right = -8
	disc = GlyphDisc.new(d, DISC_PX)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_content.add_child(disc)
	var v: = UITheme.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l = UITheme.ellipsize(UITheme.label(d.name, "BoldLabel", 15))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var tag: String = DB.tag_label(d.tags[0]) if d.tags.size() > 0 else ""
	role_l = UITheme.ellipsize(UITheme.label("%s · %s" % [DB.role_label(d.role), tag] if tag != "" else DB.role_label(d.role), "", 12, UITheme.role_color(d.role)))
	role_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(role_l)
	_content.add_child(v)
	add_child(_content)
	badge = UITheme.label("", "BadgeLabel", 0, Color.WHITE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	add_child(badge)
	mouse_entered.connect( func(): hovered_def.emit(def))
	tooltip_text = UITheme.tip(d.summary)


## Marks the card as picked by `team` (-1 clears). label_text defaults to "청"/"홍".
func set_picked(team: int, label_text: String = "") -> void :
	var badge_text: = ""
	if team >= 0:
		badge_text = label_text if label_text != "" else ("청" if team == 0 else "홍")
	if team == picked_team and badge_text == badge.text:
		return
	picked_team = team
	badge.visible = team >= 0
	if team < 0:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			remove_theme_stylebox_override(st)
		badge.text = ""
	else:
		var col: = UITheme.team_color(team)
		var styles: Dictionary = _styles_for(col)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(st, styles[st])
		badge.text = badge_text
		badge.add_theme_stylebox_override("normal", styles["badge"])
		badge.add_theme_color_override("font_color", UITheme.BG if col.get_luminance() > 0.5 else Color.WHITE)
	_place_badge()
	queue_redraw()


## Shows "×n" in the top-right corner for n >= 2 (duplicate picks); n <= 1 hides the badge.
func set_count(n: int) -> void :
	if n == count:
		return
	count = n
	if n <= 1:
		if count_badge:
			count_badge.visible = false
		_content.offset_right = -8
		return
	if count_badge == null:
		count_badge = UITheme.label("", "BadgeLabel", 0, UITheme.TEXT)
		count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_badge.add_theme_stylebox_override("normal", UITheme.sbc(UITheme.ACCENT_FILL, Color(UITheme.BG, 0.85), UITheme.R_PILL, 1, 6, 0))
		count_badge.add_theme_color_override("font_color", Color.WHITE)
		add_child(count_badge)
	count_badge.text = "×%d" % n
	count_badge.visible = true
	_place_count()


# Top-right corner; the name and role lines end before the badge so they ellipsise instead of
# running under it.
func _place_count() -> void :
	if count_badge == null or not count_badge.visible:
		return
	count_badge.reset_size()
	var bs: = count_badge.get_combined_minimum_size()
	count_badge.size = bs
	count_badge.position = Vector2(roundf(size.x - bs.x - 6.0), 6.0)
	_content.offset_right = -(bs.x + 10.0)


static func _styles_for(col: Color) -> Dictionary:
	var key: = col.to_html()
	if _picked_styles.has(key):
		return _picked_styles[key]
	var base: = UITheme.PANEL2.lerp(col, 0.1)
	var styles: = {
		"normal": UITheme.sb(base, Color(col, 0.75), UITheme.R_L, 1, 10, 8),
		"hover": UITheme.sb(UITheme.PANEL3.lerp(col, 0.12), col, UITheme.R_L, 1, 10, 8),
		"pressed": UITheme.sb(base, col, UITheme.R_L, 2, 10, 8),
		"hover_pressed": UITheme.sb(UITheme.PANEL3.lerp(col, 0.12), col, UITheme.R_L, 2, 10, 8),
		"disabled": UITheme.sb(base, Color(col, 0.6), UITheme.R_L, 1, 10, 8),
		"badge": UITheme.sb(col, Color(UITheme.BG, 0.85), UITheme.R_PILL, 1, 6, 0),
	}
	_picked_styles[key] = styles
	return styles


func _place_badge() -> void :
	if not badge.visible:
		return
	badge.reset_size()
	var bs: = badge.get_combined_minimum_size()
	badge.size = bs
	var cx: = PAD_L + DISC_PX * 0.5
	var disc_bottom: = size.y * 0.5 + DISC_PX * 0.5
	badge.position = Vector2(roundf(cx - bs.x * 0.5), roundf(disc_bottom - bs.y + 5.0))


## V1.5 API: badge anchor (top-left) for the current size.
func _badge_pos() -> Vector2:
	return badge.position


func _notification(what: int) -> void :
	if (what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE) and badge:
		_place_badge()
		_place_count()


func _draw() -> void :
	# Unpicked disabled cards (e.g. while the AI drafts) dim their content; picked cards never dim.
	var want: = disabled and picked_team < 0
	if want != _dimmed:
		_dimmed = want
		_content.modulate = Color(1, 1, 1, 0.45) if want else Color.WHITE
	if picked_team >= 0:
		draw_style_box(UITheme.sbc(UITheme.team_color(picked_team), UITheme.CLEAR, 2, 0, 0, 0), Rect2(3, 12, 3, size.y - 24))
