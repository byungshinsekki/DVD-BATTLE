class_name UITheme
extends RefCounted
## DVD BATTLE design system (V1.5.1).
##  - Tokens: colours, type scale (FS_*), radii (R_*), spacing (SP*), page padding (PAGE_*).
##  - build(): the cached Theme (label/panel/button variations, themed controls, generated icons).
##  - Static component helpers that return ready-to-add Controls (page_header, badge, segmented ...).
## Every pre-1.5.1 name and signature keeps working. Draw code must use sbc() (shared, cached
## StyleBoxFlat) instead of allocating a StyleBoxFlat per frame.


# ------------------------------------------------------------------ colour tokens

const BG: = Color("#070a10")
const BG2: = Color("#0b1019")
const PANEL: = Color("#0f1520")
const PANEL2: = Color("#141c2b")
const PANEL3: = Color("#1b2538")
const RAISED: = Color("#222e45")
const LINE: = Color("#293650")
const LINE2: = Color("#3a4b6e")
const TEXT: = Color("#eaf0fa")
const TEXT_DIM: = Color("#a9b6cc")
const TEXT_FAINT: = Color("#8593ae")
const TEXT_DISABLED: = Color("#5a6680")
const ACCENT: = Color("#6cb6ff")
const ACCENT_FILL: = Color("#2a6fd8")
const ACCENT_HOVER: = Color("#3a82ea")
## ACCENT.lightened(0.4): text on accent-tinted (selected) surfaces.
const ACCENT_TEXT: = Color("#a7d3ff")
const ACCENT2: = Color("#a98cff")
const GOLD: = Color("#f4c96b")
const GOOD: = Color("#6fe0a2")
const WARN: = Color("#ffb45e")
const BAD: = Color("#ff6d79")
const BLUE: = Color("#56a7ff")
const RED: = Color("#ff6d79")
const CLEAR: = Color(0, 0, 0, 0)
const TEAM: = [BLUE, RED]
# Deathmatch / battleground: one colour per participant or team (the first two keep the team
# colours). The first 12 are the V1.5 deathmatch set and must stay as they are (tests and older
# screens rely on them). V2 adds teal, magenta and royal blue for 15 battleground teams; each sits
# at least 0.12 OKLab away from every other entry. Teams 15+ reuse these hues lightened
# (FFA_LIGHTEN) and always show their label (team_needs_label).
const FFA: = [BLUE, RED, Color("#6fe08a"), Color("#f4c96b"), Color("#b58cff"), Color("#4fe3e0"),
	Color("#ff9a4d"), Color("#ff7fc8"), Color("#c8f06a"), Color("#8c9bff"), Color("#ece6d6"), Color("#d09a62"),
	Color("#14b8a6"), Color("#f23cc6"), Color("#4a6cff")]
const FFA_LIGHTEN: = 0.38
const TEAM_SOFT: = [Color("#56a7ff33"), Color("#ff6d7933")]
const ROLE_COLORS: = {"FRONTLINE": Color("#e0a45f"), "DAMAGE": Color("#ff7b86"), "CONTROL": Color("#a78bff"), "SUPPORT": Color("#6fe0a2")}
## Damage school colours (ability text, effect chips).
const SCHOOL_COLORS: = {"physical": Color("#ff9a6b"), "magic": Color("#b58cff"), "true": Color("#eaf0fa")}
const AD_COLOR: = Color("#ff9a6b")
const AP_COLOR: = Color("#b58cff")

# ------------------------------------------------------------------ type scale (logical px at 1600x900)

const FS_DISPLAY: = 36
const FS_TITLE: = 28
const FS_H1: = 20
const FS_H2: = 16
const FS_BODY: = 15
const FS_SM: = 14
const FS_CAPTION: = 13
const FS_MICRO: = 12
## Smallest text size anywhere; label()/wrap_label() clamp explicit sizes to it.
const MIN_FS: = 12

# ------------------------------------------------------------------ radii / spacing / page

const R_XS: = 4
const R_S: = 6
const R_M: = 10
const R_L: = 14
const R_XL: = 18
const R_PILL: = 99
const SP1: = 4
const SP2: = 8
const SP3: = 12
const SP4: = 16
const SP5: = 24
const SP6: = 32
const PAGE_X: = 32
const PAGE_TOP: = 28
const PAGE_BOTTOM: = 24

## Generated icons are rasterised at this supersampling factor and drawn at logical size.
const ICON_SS: = 2

static var theme: Theme
static var _icons: Dictionary = {}
static var _sbc_cache: Dictionary = {}
static var _locked_styles: Dictionary = {}


# ================================================================== theme

## Builds (once) and returns the app Theme. Assigned to the App root; popups/tooltips inherit it.
static func build() -> Theme:
	if theme:
		return theme
	DB.load_fonts()
	var t: = Theme.new()
	t.default_font = DB.font_regular
	t.default_font_size = FS_BODY
	_build_labels(t)
	_build_panels(t)
	_build_buttons(t)
	_build_inputs(t)
	_build_popups(t)
	_build_scroll_and_bars(t)
	_build_toggles(t)
	_build_tabs_and_text(t)
	theme = t
	return t


static func _variation(t: Theme, name: String, base: String) -> void:
	t.set_type_variation(name, base)


static func _build_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", CLEAR)
	var eyebrow: = FontVariation.new()
	eyebrow.base_font = DB.font_bold
	eyebrow.spacing_glyph = 1
	for v in [
			["DisplayLabel", FS_DISPLAY, DB.font_black, TEXT],
			["TitleLabel", FS_TITLE, DB.font_black, TEXT],
			["HeadLabel", FS_H1, DB.font_bold, TEXT],
			["SubheadLabel", FS_H2, DB.font_bold, TEXT],
			["BoldLabel", FS_BODY, DB.font_bold, TEXT],
			["BodyLabel", FS_BODY, DB.font_regular, TEXT],
			["BlackLabel", FS_BODY, DB.font_black, TEXT],
			["NumberLabel", 22, DB.font_black, TEXT],
			["DimLabel", FS_SM, DB.font_regular, TEXT_DIM],
			["CaptionLabel", FS_CAPTION, DB.font_regular, TEXT_DIM],
			["FaintLabel", FS_CAPTION, DB.font_regular, TEXT_FAINT],
			["EyebrowLabel", FS_MICRO, eyebrow, ACCENT],
			["BadgeLabel", FS_MICRO, DB.font_bold, TEXT]]:
		_variation(t, v[0], "Label")
		t.set_font_size("font_size", v[0], v[1])
		t.set_font("font", v[0], v[2])
		t.set_color("font_color", v[0], v[3])


static func _build_panels(t: Theme) -> void:
	var base: = sb(PANEL, LINE, R_L, 1, 10, 7)
	t.set_stylebox("panel", "PanelContainer", base)
	t.set_stylebox("panel", "Panel", base)
	# Cards: slightly raised surface with a small elevation shadow (ScrollContainers clip shadows).
	_variation(t, "CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", elevate(sb(PANEL2, LINE, R_L, 1, 12, 10), 1))
	_variation(t, "GlassPanel", "PanelContainer")
	t.set_stylebox("panel", "GlassPanel", sb(Color(0.06, 0.08, 0.12, 0.86), Color(1, 1, 1, 0.08), R_L, 1, 10))
	_variation(t, "FlatPanel", "PanelContainer")
	t.set_stylebox("panel", "FlatPanel", sb(CLEAR, CLEAR, 0, 0, 0))
	# Sunken well (inputs, segmented controls), inset tile (stats) and floating overlay (toasts).
	_variation(t, "SunkenPanel", "PanelContainer")
	t.set_stylebox("panel", "SunkenPanel", sb(BG2, LINE, R_M, 1, 10, 8))
	_variation(t, "SegmentedPanel", "PanelContainer")
	t.set_stylebox("panel", "SegmentedPanel", sb(BG2, LINE, R_M, 1, 3, 3))
	_variation(t, "InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", sb(Color(1, 1, 1, 0.025), LINE, R_M, 1, 10, 6))
	_variation(t, "OverlayPanel", "PanelContainer")
	t.set_stylebox("panel", "OverlayPanel", elevate(sb(Color("#0d1420f5"), LINE2, R_M, 1, 14, 10), 2))


static func _build_buttons(t: Theme) -> void:
	# Plain Button (also OptionButton): raised surface, accent on interaction.
	var bn: = sb(PANEL3, LINE2, R_M, 1, 14, 8)
	var bh: = sb(RAISED, LINE2.lerp(ACCENT, 0.35), R_M, 1, 14, 8)
	var bp: = sb(PANEL3.lerp(ACCENT, 0.16), ACCENT, R_M, 1, 14, 8)
	var bhp: = sb(RAISED.lerp(ACCENT, 0.16), ACCENT, R_M, 1, 14, 8)
	var bd: = sb(Color(PANEL3, 0.5), Color(LINE2, 0.45), R_M, 1, 14, 8)
	for type in ["Button", "OptionButton"]:
		_states(t, type, bn, bh, bp, bhp, bd, R_M)
		_fonts(t, type, TEXT, Color.WHITE, Color.WHITE, TEXT_DISABLED)
	t.set_icon("arrow", "OptionButton", _chevron_icon())
	t.set_constant("arrow_margin", "OptionButton", 12)
	t.set_constant("modulate_arrow", "OptionButton", 0)

	_variation(t, "PrimaryButton", "Button")
	var edge: = Color("#5aa6ff")
	_states(t, "PrimaryButton", sb(ACCENT_FILL, edge, R_M, 1, 14, 8), sb(ACCENT_HOVER, Color("#86c2ff"), R_M, 1, 14, 8),
		sb(ACCENT_FILL.darkened(0.12), edge, R_M, 1, 14, 8), sb(ACCENT_HOVER, Color("#86c2ff"), R_M, 1, 14, 8),
		sb(Color(ACCENT_FILL, 0.28), Color(edge, 0.22), R_M, 1, 14, 8), R_M)
	_fonts(t, "PrimaryButton", Color.WHITE, Color.WHITE, Color.WHITE, Color(1, 1, 1, 0.45))
	t.set_font("font", "PrimaryButton", DB.font_bold)

	_variation(t, "GhostButton", "Button")
	_states(t, "GhostButton", sb(CLEAR, LINE2, R_M, 1, 14, 8), sb(Color(1, 1, 1, 0.05), LINE2.lerp(ACCENT, 0.35), R_M, 1, 14, 8),
		sb(Color(ACCENT, 0.12), ACCENT, R_M, 1, 14, 8), sb(Color(ACCENT, 0.16), ACCENT, R_M, 1, 14, 8),
		sb(CLEAR, Color(LINE, 0.6), R_M, 1, 14, 8), R_M)
	_fonts(t, "GhostButton", TEXT_DIM, TEXT, Color.WHITE, TEXT_DISABLED)

	_variation(t, "DangerButton", "Button")
	var dfg: = Color("#ffd3d8")
	_states(t, "DangerButton", sb(Color("#3a1720"), Color("#7a2c3a"), R_M, 1, 14, 8), sb(Color("#4b1d29"), Color(BAD, 0.8), R_M, 1, 14, 8),
		sb(Color("#2e1119"), BAD, R_M, 1, 14, 8), sb(Color("#4b1d29"), BAD, R_M, 1, 14, 8),
		sb(Color("#3a172073"), Color("#7a2c3a66"), R_M, 1, 14, 8), R_M)
	_fonts(t, "DangerButton", dfg, Color.WHITE, Color.WHITE, Color(dfg, 0.4))

	# Toggle chip (filters, counts). Pressed = accent fill + accent border + light accent text.
	# Horizontal padding 10 (not 12) keeps the dense V1.5 chip rows (deathmatch config) inside 1600 px.
	_variation(t, "ChipButton", "Button")
	_states(t, "ChipButton", sb(Color(1, 1, 1, 0.03), LINE2, R_PILL, 1, 10, 5), sb(Color(1, 1, 1, 0.06), LINE2.lerp(ACCENT, 0.45), R_PILL, 1, 10, 5),
		sb(Color(ACCENT, 0.18), ACCENT, R_PILL, 1, 10, 5), sb(Color(ACCENT, 0.24), ACCENT, R_PILL, 1, 10, 5),
		sb(Color(1, 1, 1, 0.015), Color(LINE2, 0.45), R_PILL, 1, 10, 5), R_PILL)
	_fonts(t, "ChipButton", TEXT_DIM, TEXT, ACCENT_TEXT, TEXT_DISABLED, Color.WHITE)
	t.set_font_size("font_size", "ChipButton", FS_CAPTION)

	# Segment of a segmented control (see segmented()).
	_variation(t, "SegmentButton", "Button")
	_states(t, "SegmentButton", sb(CLEAR, CLEAR, R_S, 1, 12, 6), sb(Color(1, 1, 1, 0.045), CLEAR, R_S, 1, 12, 6),
		sb(PANEL3, ACCENT, R_S, 1, 12, 6), sb(RAISED, ACCENT, R_S, 1, 12, 6), sb(CLEAR, CLEAR, R_S, 1, 12, 6), R_S)
	_fonts(t, "SegmentButton", TEXT_DIM, TEXT, TEXT, TEXT_DISABLED, Color.WHITE)
	t.set_font_size("font_size", "SegmentButton", FS_SM)

	# Sidebar navigation item.
	_variation(t, "NavButton", "Button")
	_states(t, "NavButton", sb(CLEAR, CLEAR, R_M, 0, 12, 8), sb(Color(1, 1, 1, 0.04), CLEAR, R_M, 0, 12, 8),
		sb(Color(ACCENT, 0.12), CLEAR, R_M, 0, 12, 8), sb(Color(ACCENT, 0.16), CLEAR, R_M, 0, 12, 8),
		sb(CLEAR, CLEAR, R_M, 0, 12, 8), R_M)
	_fonts(t, "NavButton", TEXT_DIM, TEXT, TEXT, TEXT_DISABLED, TEXT)
	t.set_constant("h_separation", "NavButton", 10)

	# Selectable card (roster cards, mode cards). Pressed = faint accent fill + 2px accent border.
	_variation(t, "CardButton", "Button")
	_states(t, "CardButton", sb(PANEL2, LINE, R_L, 1, 10, 8), sb(PANEL3, LINE.lerp(ACCENT, 0.5), R_L, 1, 10, 8),
		sb(PANEL2.lerp(ACCENT, 0.08), ACCENT, R_L, 2, 10, 8), sb(PANEL3.lerp(ACCENT, 0.08), ACCENT, R_L, 2, 10, 8),
		sb(Color(PANEL2, 0.6), Color(LINE, 0.5), R_L, 1, 10, 8), R_L)
	_fonts(t, "CardButton", TEXT, Color.WHITE, Color.WHITE, TEXT_DISABLED)


static func _states(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, hover_pressed: StyleBox, disabled: StyleBox, radius: int) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, hover_pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _focus_ring(radius))


static func _fonts(t: Theme, type: String, fg: Color, hover: Color, pressed: Color, disabled: Color, hover_pressed: Variant = null) -> void:
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, hover_pressed if hover_pressed != null else pressed)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, disabled)


static func _focus_ring(radius: int) -> StyleBoxFlat:
	var s: = sb(CLEAR, Color(ACCENT, 0.8), radius, 2, 0, 0)
	s.set_expand_margin_all(2)
	return s


## Legacy (pre-1.5.1) button variation builder, kept for compatibility.
static func _button_styles(t: Theme, type: String, bg: Color, border: Color, hover: Color, focus: Color, fg: Color, radius: int = 10, pad: int = 14) -> void:
	_states(t, type, sb(bg, border, radius, 1, pad, 8), sb(hover, border.lerp(focus, 0.35), radius, 1, pad, 8),
		sb(hover.darkened(0.1), focus, radius, 1, pad, 8), sb(hover, focus, radius, 1, pad, 8),
		sb(Color(bg, bg.a * 0.45), Color(border, 0.4), radius, 1, pad, 8), radius)
	_fonts(t, type, fg, fg.lightened(0.15), Color.WHITE, Color(fg, 0.35))


static func _build_inputs(t: Theme) -> void:
	t.set_stylebox("normal", "LineEdit", sb(BG2, LINE2, R_M, 1, 10, 6))
	t.set_stylebox("focus", "LineEdit", sb(CLEAR, ACCENT, R_M, 1, 10, 6))
	t.set_stylebox("read_only", "LineEdit", sb(Color(1, 1, 1, 0.02), LINE, R_M, 1, 10, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_selected_color", "LineEdit", Color.WHITE)
	t.set_color("font_uneditable_color", "LineEdit", TEXT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	t.set_color("clear_button_color_pressed", "LineEdit", ACCENT)


static func _build_popups(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", elevate(sb(PANEL2, LINE2, R_M, 1, 6, 6), 2))
	t.set_stylebox("hover", "PopupMenu", sb(Color(ACCENT, 0.14), CLEAR, R_S, 0, 8, 4))
	var sep: = StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_font_size("font_size", "PopupMenu", FS_SM)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("h_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 12)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_DISABLED)
	t.set_color("font_separator_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_accelerator_color", "PopupMenu", TEXT_FAINT)
	t.set_icon("radio_checked", "PopupMenu", _radio_icon(true, false))
	t.set_icon("radio_unchecked", "PopupMenu", _radio_icon(false, false))
	t.set_icon("checked", "PopupMenu", _check_icon(true, false))
	t.set_icon("unchecked", "PopupMenu", _check_icon(false, false))

	t.set_stylebox("panel", "TooltipPanel", elevate(sb(Color("#0d1420f5"), LINE2, R_M, 1, 12, 8), 2))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", DB.font_regular)
	t.set_font_size("font_size", "TooltipLabel", FS_CAPTION)
	t.set_constant("line_spacing", "TooltipLabel", 2)


static func _build_scroll_and_bars(t: Theme) -> void:
	# Visible, slim scrollbars: the track's side margins set the bar thickness (6 px).
	var vtrack: = sb(Color(1, 1, 1, 0.025), CLEAR, R_XS, 0, 3, 2)
	var htrack: = sb(Color(1, 1, 1, 0.025), CLEAR, R_XS, 0, 2, 3)
	var grab: = sb(Color(1, 1, 1, 0.20), CLEAR, R_XS, 0, 3, 3)
	var grab_h: = sb(Color(1, 1, 1, 0.36), CLEAR, R_XS, 0, 3, 3)
	var grab_p: = sb(Color(ACCENT, 0.6), CLEAR, R_XS, 0, 3, 3)
	for pair in [["VScrollBar", vtrack], ["HScrollBar", htrack]]:
		t.set_stylebox("scroll", pair[0], pair[1])
		t.set_stylebox("scroll_focus", pair[0], pair[1])
		t.set_stylebox("grabber", pair[0], grab)
		t.set_stylebox("grabber_highlight", pair[0], grab_h)
		t.set_stylebox("grabber_pressed", pair[0], grab_p)
	t.set_constant("scrollbar_v_separation", "ScrollContainer", 4)
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 4)

	t.set_stylebox("background", "ProgressBar", sb(Color(1, 1, 1, 0.06), CLEAR, R_XS, 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", sb(ACCENT, CLEAR, R_XS, 0, 0, 0))
	t.set_font_size("font_size", "ProgressBar", FS_MICRO)
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("slider", "HSlider", sb(Color(1, 1, 1, 0.08), CLEAR, R_XS, 0, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", sb(ACCENT, CLEAR, R_XS, 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(ACCENT.lightened(0.15), CLEAR, R_XS, 0, 0, 3))
	t.set_icon("grabber", "HSlider", _knob_icon(0))
	t.set_icon("grabber_highlight", "HSlider", _knob_icon(1))
	t.set_icon("grabber_disabled", "HSlider", _knob_icon(2))

	var line: = StyleBoxLine.new()
	line.color = LINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline: = StyleBoxLine.new()
	vline.color = LINE
	vline.thickness = 1
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)


static func _build_toggles(t: Theme) -> void:
	var clear: = sb(CLEAR, CLEAR, 8, 0, 6)
	var hov: = sb(Color(1, 1, 1, 0.04), CLEAR, 8, 0, 6)
	for type in ["CheckButton", "CheckBox"]:
		for st in ["normal", "pressed", "focus", "disabled"]:
			t.set_stylebox(st, type, clear)
		t.set_stylebox("hover", type, hov)
		t.set_stylebox("hover_pressed", type, hov)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_DISABLED)
		t.set_constant("h_separation", type, 8)
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true))
	t.set_icon("checked", "CheckBox", _check_icon(true, false))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_icon("radio_checked", "CheckBox", _radio_icon(true, false))
	t.set_icon("radio_unchecked", "CheckBox", _radio_icon(false, false))
	t.set_icon("radio_checked_disabled", "CheckBox", _radio_icon(true, true))
	t.set_icon("radio_unchecked_disabled", "CheckBox", _radio_icon(false, true))


static func _build_tabs_and_text(t: Theme) -> void:
	# Underline tabs: the selected tab gets a 2px accent bottom border, others stay flat.
	var sel: = _tab_style(CLEAR, ACCENT, 0)
	var unsel: = _tab_style(CLEAR, CLEAR, 0)
	var hovered: = _tab_style(Color(1, 1, 1, 0.04), LINE2, R_S)
	t.set_stylebox("tab_selected", "TabBar", sel)
	t.set_stylebox("tab_unselected", "TabBar", unsel)
	t.set_stylebox("tab_hovered", "TabBar", hovered)
	t.set_stylebox("tab_disabled", "TabBar", unsel)
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", TEXT)
	t.set_color("font_unselected_color", "TabBar", TEXT_DIM)
	t.set_color("font_hovered_color", "TabBar", TEXT)
	t.set_color("font_disabled_color", "TabBar", TEXT_DISABLED)
	t.set_font_size("font_size", "TabBar", FS_SM)

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT, 0.35))
	t.set_font("normal_font", "RichTextLabel", DB.font_regular)
	t.set_font("bold_font", "RichTextLabel", DB.font_bold)
	t.set_font("italics_font", "RichTextLabel", DB.font_regular)
	t.set_font("bold_italics_font", "RichTextLabel", DB.font_bold)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		t.set_font_size(key, "RichTextLabel", FS_SM)
	t.set_constant("line_separation", "RichTextLabel", 2)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())


static func _tab_style(bg: Color, underline: Color, radius: int) -> StyleBoxFlat:
	var s: = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = underline
	s.border_width_bottom = 2
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


# ================================================================== generated icons (built once, cached)

static func _cached_icon(key: String, w: int, h: int, shade: Callable) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var s: = ICON_SS
	var img: = Image.create_empty(w * s, h * s, false, Image.FORMAT_RGBA8)
	for y in h * s:
		for x in w * s:
			img.set_pixel(x, y, shade.call(Vector2((x + 0.5) / s, (y + 0.5) / s)))
	var tex: = ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(w, h))
	_icons[key] = tex
	return tex


## Coverage (0..1) of a signed distance in logical px at the icon supersampling rate.
static func _cov(d: float) -> float:
	return clampf(0.5 - d * ICON_SS, 0.0, 1.0)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: = b - a
	var h: = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * h)


static func _round_rect_dist(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	var q: = (p - c).abs() - half + Vector2(r, r)
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - r


## Switch icon for CheckButton (36x20 logical). Kept name from V1.5.
static func _switch_icon(on: bool, disabled: bool = false) -> Texture2D:
	var track: = ACCENT_FILL if on else Color("#2b3650")
	var knob: = Color.WHITE if on else TEXT_DIM
	var k: = 0.45 if disabled else 1.0
	return _cached_icon("switch_%s_%s" % [on, disabled], 36, 20, func(p: Vector2) -> Color:
		var col: = Color(track, _cov(_seg_dist(p, Vector2(10, 10), Vector2(26, 10)) - 9.5) * k)
		var kc: = Vector2(26.0 if on else 10.0, 10.0)
		return col.blend(Color(knob, _cov(p.distance_to(kc) - 7.0) * k)))


static func _check_icon(on: bool, disabled: bool) -> Texture2D:
	var k: = 0.45 if disabled else 1.0
	return _cached_icon("check_%s_%s" % [on, disabled], 18, 18, func(p: Vector2) -> Color:
		var d: = _round_rect_dist(p, Vector2(9, 9), Vector2(8, 8), 4.0)
		if on:
			var col: = Color(ACCENT_FILL, _cov(d) * k)
			var m: = minf(_seg_dist(p, Vector2(4.6, 9.4), Vector2(7.7, 12.4)), _seg_dist(p, Vector2(7.7, 12.4), Vector2(13.4, 5.8)))
			return col.blend(Color(Color.WHITE, _cov(m - 1.05) * k))
		var fill: = Color(BG2, _cov(d) * k)
		return fill.blend(Color(LINE2.lightened(0.15), _cov(absf(d + 0.75) - 0.75) * k)))


static func _radio_icon(on: bool, disabled: bool) -> Texture2D:
	var k: = 0.45 if disabled else 1.0
	return _cached_icon("radio_%s_%s" % [on, disabled], 18, 18, func(p: Vector2) -> Color:
		var d: = p.distance_to(Vector2(9, 9)) - 8.0
		var col: = Color(BG2, _cov(d) * k)
		col = col.blend(Color(ACCENT if on else LINE2.lightened(0.15), _cov(absf(d + 0.75) - 0.75) * k))
		if on:
			col = col.blend(Color(ACCENT, _cov(p.distance_to(Vector2(9, 9)) - 4.0) * k))
		return col)


static func _chevron_icon() -> Texture2D:
	return _cached_icon("chevron", 12, 8, func(p: Vector2) -> Color:
		var d: = minf(_seg_dist(p, Vector2(2.5, 2.2), Vector2(6, 5.8)), _seg_dist(p, Vector2(6, 5.8), Vector2(9.5, 2.2)))
		return Color(TEXT_DIM, _cov(d - 0.85)))


## HSlider knob. state: 0 normal, 1 highlight, 2 disabled.
static func _knob_icon(state: int) -> Texture2D:
	var ring: Color = [ACCENT, ACCENT.lightened(0.2), TEXT_DISABLED][clampi(state, 0, 2)]
	return _cached_icon("knob_%d" % state, 18, 18, func(p: Vector2) -> Color:
		var d: = p.distance_to(Vector2(9, 9))
		var col: = Color(Color(0, 0, 0), _cov(d - 8.6) * 0.35)
		col = col.blend(Color(ring, _cov(d - 8.0)))
		return col.blend(Color(Color.WHITE if state != 2 else TEXT_DIM, _cov(d - (5.5 if state == 1 else 5.0)))))


# ================================================================== style primitives

## New StyleBoxFlat. Vertical padding defaults to max(4, pad - 3) (V1.5 behaviour).
static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, bw: int = 1, pad: int = 10, vpad: int = -1) -> StyleBoxFlat:
	var s: = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = vpad if vpad >= 0 else maxi(4, pad - 3)
	s.content_margin_bottom = vpad if vpad >= 0 else maxi(4, pad - 3)
	s.anti_aliasing = true
	return s


## Shared, cached StyleBoxFlat with the same arguments as sb(). Use it in _draw()/per-frame code and
## for repeated overrides. Never mutate the returned instance. Keep the argument set discrete.
static func sbc(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, bw: int = 1, pad: int = 10, vpad: int = -1) -> StyleBoxFlat:
	var key: = [bg, border, radius, bw, pad, vpad]
	var s: StyleBoxFlat = _sbc_cache.get(key)
	if s == null:
		if _sbc_cache.size() > 1024:
			_sbc_cache.clear()
		s = sb(bg, border, radius, bw, pad, vpad)
		_sbc_cache[key] = s
	return s


## Adds an elevation shadow in place and returns the style. level 1 = card, 2 = overlay/popup.
static func elevate(s: StyleBoxFlat, level: int = 1) -> StyleBoxFlat:
	if level >= 2:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 16
		s.shadow_offset = Vector2(0, 4)
	else:
		s.shadow_color = Color(0, 0, 0, 0.22)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 2)
	return s


## Clamp an explicit font size to the readable floor (for draw_string sites).
static func fs(px: int) -> int:
	return maxi(px, MIN_FS)


# ================================================================== basic builders (V1.5 API)

## Label with an optional theme variation, size (clamped to >= MIN_FS) and colour.
static func label(text: String, variation: String = "", size: int = 0, color: Variant = null) -> Label:
	var l: = Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", maxi(size, MIN_FS))
	if color != null:
		l.add_theme_color_override("font_color", color)
	return l


## Word-wrapping, horizontally expanding label. Prose sizes are clamped to >= 13 (12 for Faint/Eyebrow).
static func wrap_label(text: String, variation: String = "DimLabel", size: int = 0, color: Variant = null) -> Label:
	var floor_px: = MIN_FS if variation in ["FaintLabel", "EyebrowLabel"] else FS_CAPTION
	var l: = label(text, variation, maxi(size, floor_px) if size > 0 else 0, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Button with a theme variation (PrimaryButton, GhostButton, ChipButton, ...), hand cursor and no focus.
static func button(text: String, variation: String = "", cb: Callable = Callable(), tooltip: String = "") -> Button:
	var b: = Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if cb.is_valid():
		b.pressed.connect(cb)
	if tooltip != "":
		b.tooltip_text = tip(tooltip)
	return b


## VBoxContainer with the given separation.
static func vbox(sep: int = 8) -> VBoxContainer:
	var v: = VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


## HBoxContainer with the given separation.
static func hbox(sep: int = 8) -> HBoxContainer:
	var h: = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## MarginContainer around child (t/r default to l, b defaults to t).
static func margin(child: Control, l: int, t: int = -1, r: int = -1, b: int = -1) -> MarginContainer:
	var m: = MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t if t >= 0 else l)
	m.add_theme_constant_override("margin_right", r if r >= 0 else l)
	m.add_theme_constant_override("margin_bottom", b if b >= 0 else (t if t >= 0 else l))
	if child:
		m.add_child(child)
	return m


## PanelContainer with a theme variation (CardPanel, InsetPanel, SunkenPanel, OverlayPanel ...).
static func panel(variation: String = "", child: Control = null) -> PanelContainer:
	var p: = PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if child:
		p.add_child(child)
	return p


## PanelContainer drawing the given StyleBox (prefer a variation, or sbc() for shared styles).
static func styled_panel(style: StyleBox, child: Control = null) -> PanelContainer:
	var p: = PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	if child:
		p.add_child(child)
	return p


## Fixed-size gap, or a horizontally expanding filler when both sizes are 0.
static func spacer(w: int = 0, h: int = 0) -> Control:
	var c: = Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if w == 0 and h == 0:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Sets EXPAND_FILL on the requested axes and returns the control.
static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## 1 px hairline in LINE colour (horizontal by default).
static func sep_line(vertical: bool = false) -> Control:
	var c: = ColorRect.new()
	c.color = LINE
	c.custom_minimum_size = Vector2(1, 0) if vertical else Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Pill tag. Wrapper around badge(): filled -> "strong", otherwise "soft".
static func chip(text: String, color: Color, filled: bool = false) -> PanelContainer:
	return badge(text, color, "strong" if filled else "soft")


## Seconds -> "m:ss".
static func fmt_time(t: float) -> String:
	var s: = maxi(0, int(ceil(t)))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


## Team colour (0 blue, 1 red); deathmatch participants and battleground teams 2+ use FFA. Teams
## past the 15 FFA hues get the same hues lightened, so they need their label (team_needs_label).
static func team_color(team: int) -> Color:
	if team >= FFA.size():
		return (FFA[team % FFA.size()] as Color).lightened(FFA_LIGHTEN)
	if team >= 2:
		return FFA[team]
	return TEAM[clampi(team, 0, 1)]


## Battleground team label: "3팀" for duo/trio squads, "P7" for solo (team is 0-based).
static func team_label(team: int, squad: int = 1) -> String:
	return DB.team_name(team, squad)


## True when the team's colour repeats a lower team's hue (lighter shade), so colour alone cannot
## tell it apart: always draw its label or number next to it.
static func team_needs_label(team: int) -> bool:
	return team >= FFA.size()


## Team colour lifted for text and thin lines on the dark panels.
static func team_text_color(team: int) -> Color:
	return team_color(team).lightened(0.25)


## Ink for text on a filled team-colour surface: dark on light colours, white otherwise.
static func team_ink(team: int) -> Color:
	return BG if team_color(team).get_luminance() > 0.5 else Color.WHITE


## Role colour (FRONTLINE/DAMAGE/CONTROL/SUPPORT); ACCENT for unknown roles.
static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, ACCENT)


## Damage school colour ("physical" / "magic" / "true"); ACCENT for unknown schools.
static func school_color(school: String) -> Color:
	return SCHOOL_COLORS.get(school, ACCENT)


## Item rarity colour (0 common .. 4 legendary), delegated to ItemDefs.
static func rarity_color(r: int) -> Color:
	return ItemDefs.rarity_color(r)


## Item rarity name ("일반" .. "전설").
static func rarity_name(r: int) -> String:
	return str(ItemDefs.RARITY_NAMES[clampi(r, 0, ItemDefs.RARITY_NAMES.size() - 1)])


## Rarity colour of an item id.
static func item_color(item_id: String) -> Color:
	return ItemDefs.rarity_color(ItemDefs.rarity_of(item_id))


# ================================================================== text helpers

## Pre-wraps tooltip text (Godot tooltips never wrap): breaks at spaces so no line is wider than about
## max_chars * 10 px at the tooltip font (13 px), hard-breaking long unspaced runs. Keeps "\n".
## Idempotent. Every default tooltip is also wrapped automatically (see wrap_tooltip_node()).
static func tip(text: String, max_chars: int = 42) -> String:
	if text == "":
		return text
	DB.load_fonts()
	var font: Font = DB.font_regular
	var max_px: = float(max_chars) * 10.0
	var out: PackedStringArray = []
	var space_w: = font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, FS_CAPTION).x
	for para in text.split("\n"):
		if font.get_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_CAPTION).x <= max_px:
			out.append(para)
			continue
		var line: = ""
		var line_w: = 0.0
		for word in para.split(" ", false):
			var ww: = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_CAPTION).x
			if line != "" and line_w + space_w + ww <= max_px:
				line += " " + word
				line_w += space_w + ww
				continue
			if line != "":
				out.append(line)
			line = word
			line_w = ww
			if ww > max_px:
				# Long unspaced run: hard-break by characters.
				var chunk: = ""
				var cw: = 0.0
				for ch in word:
					var chw: = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_CAPTION).x
					if chunk != "" and cw + chw > max_px:
						out.append(chunk)
						chunk = ""
						cw = 0.0
					chunk += ch
					cw += chw
				line = chunk
				line_w = cw
		if line != "":
			out.append(line)
	return "\n".join(out)


## SceneTree.node_added hook target: wraps the built-in tooltip label (TooltipLabel) with tip().
## App connects it once; custom tooltips (_make_custom_tooltip) are left alone.
static func wrap_tooltip_node(n: Node) -> void:
	if n is Label and (n as Label).theme_type_variation == &"TooltipLabel":
		var l: = n as Label
		var w: = tip(l.text)
		if w != l.text:
			l.text = w


## Returns text trimmed with "…" so it fits max_w at font/font_size (for draw_string code).
static func fit_text(font: Font, text: String, font_size: int, max_w: float) -> String:
	if max_w <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var ell: = "…"
	var room: = max_w - font.get_string_size(ell, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var n: = text.length()
	while n > 0 and font.get_string_size(text.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		n -= 1
	return text.substr(0, n).strip_edges(false, true) + ell


## Trims a label with an ellipsis instead of overflowing/clipping mid-glyph. with_tooltip shows the
## full text on hover. Returns the label.
static func ellipsize(l: Label, with_tooltip: bool = false) -> Label:
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	if with_tooltip:
		l.tooltip_text = tip(l.text)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Small faint wrapped hint/help line (FaintLabel 13).
static func hint_label(text: String) -> Label:
	return wrap_label(text, "FaintLabel", FS_CAPTION)


## BBCode text block: fit_content, smart autowrap, no scroll/selection, mouse PASS so [hint] tooltips work.
static func rich(bbcode: String, size: int = 14) -> RichTextLabel:
	var r: = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.scroll_active = false
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if size != FS_SM:
		var px: = maxi(size, MIN_FS)
		for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			r.add_theme_font_size_override(key, px)
	r.text = bbcode
	return r


# ================================================================== components

## Page padding wrapper: 32 left/right, 28 top, 24 bottom.
static func page_margin(child: Control) -> MarginContainer:
	return margin(child, PAGE_X, PAGE_TOP, PAGE_X, PAGE_BOTTOM)


## Screen header: eyebrow + TitleLabel (+ optional Dim 14 subtitle) on the left, actions right-aligned
## and vertically centred (Buttons get min height 40). Metas: "eyebrow", "title", "subtitle" (Labels,
## subtitle hidden when empty) and "actions" (HBoxContainer).
static func page_header(eyebrow: String, title: String, subtitle: String = "", actions: Array = []) -> HBoxContainer:
	var h: = hbox(SP4)
	var v: = vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var e: = label(eyebrow, "EyebrowLabel")
	e.visible = eyebrow != ""
	v.add_child(e)
	var t: = label(title, "TitleLabel")
	v.add_child(t)
	var s: = wrap_label(subtitle, "DimLabel", FS_SM)
	s.visible = subtitle != ""
	v.add_child(s)
	h.add_child(v)
	var ab: = hbox(SP2)
	ab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ab.alignment = BoxContainer.ALIGNMENT_END
	for a in actions:
		if a is Control:
			var c: Control = a
			if c is Button and c.custom_minimum_size.y < 40:
				c.custom_minimum_size.y = 40
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ab.add_child(c)
	h.add_child(ab)
	h.set_meta("eyebrow", e)
	h.set_meta("title", t)
	h.set_meta("subtitle", s)
	h.set_meta("actions", ab)
	return h


## Section header: 3x14 accent bar, SubheadLabel title, FaintLabel hint (ellipsised, takes the free
## space) and an optional trailing control. Metas: "title", "hint" (Labels).
static func section_header(title: String, hint: String = "", trailing: Control = null) -> HBoxContainer:
	var h: = hbox(SP2)
	var bar: = Panel.new()
	bar.add_theme_stylebox_override("panel", sbc(ACCENT, CLEAR, 2, 0, 0, 0))
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var t: = label(title, "SubheadLabel")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var hl: = ellipsize(label(hint, "FaintLabel"))
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hl)
	if trailing:
		trailing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(trailing)
	h.set_meta("title", t)
	h.set_meta("hint", hl)
	return h


## Pill badge (12 px bold). style: "soft" (tint), "strong" (denser tint), "outline", "solid" (filled,
## auto dark/white text). tooltip (optional) is pre-wrapped. mouse_filter is PASS so parent buttons
## keep working and tooltips show. Meta "label" -> the Label.
static func badge(text: String, color: Color, style: String = "soft", tooltip: String = "") -> PanelContainer:
	var bg: Color
	var border: Color
	var fg: Color
	match style:
		"strong":
			bg = Color(color, 0.24)
			border = Color(color, 0.62)
			fg = color.lightened(0.35)
		"outline":
			bg = CLEAR
			border = Color(color, 0.6)
			fg = color.lightened(0.25)
		"solid":
			bg = color
			border = color
			fg = BG if color.get_luminance() > 0.5 else Color.WHITE
		_:
			bg = Color(color, 0.12)
			border = Color(color, 0.38)
			fg = color.lightened(0.3)
	var p: = PanelContainer.new()
	p.add_theme_stylebox_override("panel", sbc(bg, border, R_PILL, 1, 8, 2))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var l: = Label.new()
	l.theme_type_variation = "BadgeLabel"
	l.text = text
	l.add_theme_color_override("font_color", fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	if tooltip != "":
		p.tooltip_text = tip(tooltip)
	p.set_meta("label", l)
	return p


## Stat tile: small caption over a black-weight value (18 px) on an inset surface. hint -> tooltip.
## Metas "caption" and "value" (Labels) for in-place updates.
static func stat_tile(caption: String, value: String, color: Color = TEXT, hint: String = "") -> PanelContainer:
	var p: = panel("InsetPanel")
	var v: = vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: = ellipsize(label(caption, "FaintLabel", FS_MICRO))
	v.add_child(c)
	var n: = label(value, "BlackLabel", 18, color)
	v.add_child(n)
	p.add_child(v)
	if hint != "":
		p.tooltip_text = tip(hint)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("caption", c)
	p.set_meta("value", n)
	return p


## Square glyph tile (CJK glyph font): fill color.darkened(0.55), border color, R_S (R_XS below 26 px).
static func glyph_tile(glyph: String, color: Color, px: int = 32) -> Label:
	var l: = Label.new()
	l.text = glyph
	l.custom_minimum_size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_override("font", DB.font_glyph)
	l.add_theme_font_size_override("font_size", maxi(MIN_FS, int(round(px * (0.52 if glyph.length() <= 1 else 0.36)))))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_stylebox_override("normal", sbc(color.darkened(0.55), color, R_S if px >= 26 else R_XS, 1, 0, 0))
	return l


## Item glyph tile in its rarity colour with tooltip "이름 · 등급\n효과" (mouse PASS).
static func item_tile(item_id: String, px: int = 28) -> Label:
	var d: Dictionary = ItemDefs.get_def(item_id)
	var r: = ItemDefs.rarity_of(item_id)
	var l: = glyph_tile(str(d.get("glyph", "?")), ItemDefs.rarity_color(r), px)
	l.tooltip_text = "%s · %s\n%s" % [str(d.get("name", item_id)), rarity_name(r), tip(str(d.get("desc", "")))]
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Segmented control (mutually exclusive SegmentButtons in a sunken container, ButtonGroup).
## options: [[id, label], ...] or [[id, label, tooltip], ...]. cb(id) fires only when the selection
## changes by a click; use segmented_select() for programmatic changes (no signal).
## Metas: "buttons" (Dictionary id -> Button), "selected" (current id).
static func segmented(options: Array, selected: Variant, cb: Callable, min_w: int = 0) -> HBoxContainer:
	var outer: = HBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	var pill: = panel("SegmentedPanel")
	var row: = hbox(2)
	pill.add_child(row)
	outer.add_child(pill)
	var group: = ButtonGroup.new()
	var buttons: Dictionary = {}
	for opt in options:
		var id: Variant = opt[0]
		var b: = button(str(opt[1]), "SegmentButton")
		b.toggle_mode = true
		b.button_group = group
		if min_w > 0:
			b.custom_minimum_size.x = min_w
		if opt.size() > 2 and str(opt[2]) != "":
			b.tooltip_text = tip(str(opt[2]))
		b.set_pressed_no_signal(_same(id, selected))
		b.pressed.connect(func() -> void:
			if _same(outer.get_meta("selected"), id):
				return
			outer.set_meta("selected", id)
			if cb.is_valid():
				cb.call(id))
		buttons[id] = b
		row.add_child(b)
	outer.set_meta("buttons", buttons)
	outer.set_meta("selected", selected)
	return outer


## Selects id in a segmented() control without calling its callback.
static func segmented_select(box: Control, id: Variant) -> void:
	if box == null or not box.has_meta("buttons"):
		return
	var buttons: Dictionary = box.get_meta("buttons")
	for k in buttons:
		(buttons[k] as Button).set_pressed_no_signal(_same(k, id))
	box.set_meta("selected", id)


## Locks/unlocks a segmented() control; the selected segment keeps a visible (dimmed) selected look.
static func segmented_lock(box: Control, locked: bool) -> void:
	if box == null or not box.has_meta("buttons"):
		return
	var buttons: Dictionary = box.get_meta("buttons")
	for k in buttons:
		var b: Button = buttons[k]
		b.disabled = locked
		lock_selected(b, locked and b.button_pressed)


static func _same(a: Variant, b: Variant) -> bool:
	var ta: = typeof(a)
	var tb: = typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	if ta == tb:
		return a == b
	return (ta == TYPE_STRING or ta == TYPE_STRING_NAME) and (tb == TYPE_STRING or tb == TYPE_STRING_NAME) and str(a) == str(b)


## Disabled-but-selected look: call after setting btn.disabled, e.g. lock_selected(b, b.button_pressed).
## on=true shows the pressed style (accent border at .5 alpha) while disabled; on=false removes it.
static func lock_selected(btn: Button, on: bool = true) -> void:
	if btn == null:
		return
	if not on:
		btn.remove_theme_stylebox_override("disabled")
		btn.remove_theme_color_override("font_disabled_color")
		return
	var t: = build()
	var v: = String(btn.theme_type_variation)
	if v == "" or not t.has_stylebox("pressed", v):
		v = "Button"
	var st: StyleBox = _locked_styles.get(v)
	if st == null:
		var base: StyleBox = t.get_stylebox("pressed", v)
		if base is StyleBoxFlat:
			var s: = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
			s.bg_color = Color(s.bg_color, s.bg_color.a * 0.6)
			s.border_color = Color(ACCENT, 0.5)
			st = s
		else:
			st = base
		_locked_styles[v] = st
	btn.add_theme_stylebox_override("disabled", st)
	var fc: = t.get_color("font_pressed_color", v) if t.has_color("font_pressed_color", v) else TEXT
	btn.add_theme_color_override("font_disabled_color", Color(fc, 0.62))


## Centered empty-state block: glyph in a faint circle, title and optional hint.
static func empty_state(icon: String, title: String, hint: String = "") -> VBoxContainer:
	var v: = vbox(SP2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var g: = label(icon, "", 22, TEXT_FAINT)
	g.custom_minimum_size = Vector2(52, 52)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.add_theme_stylebox_override("normal", sbc(Color(1, 1, 1, 0.04), LINE2, R_PILL, 1, 0, 0))
	v.add_child(g)
	var t: = label(title, "SubheadLabel", 0, TEXT_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if hint != "":
		var h: = label(hint, "FaintLabel")
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size = Vector2(300, 0)
		v.add_child(h)
	return v


## Keyboard key cap ("Space", "V", "Tab" ...).
static func kbd(key: String) -> PanelContainer:
	var st: StyleBoxFlat = _sbc_cache.get("__kbd")
	if st == null:
		st = sb(PANEL3, LINE2, R_XS, 1, 6, 0)
		st.border_width_bottom = 2
		_sbc_cache["__kbd"] = st
	var p: = styled_panel(st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l: = label(key, "BadgeLabel", 0, TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Themed, text-less progress bar (h px tall, pill ends) filled with color. Expands horizontally.
static func progress(value: float, max_value: float, color: Color = ACCENT, h: int = 6) -> ProgressBar:
	var pb: = ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = maxf(max_value, 0.0001)
	pb.value = value
	pb.custom_minimum_size = Vector2(0, h)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_PASS
	if color != ACCENT:
		pb.add_theme_stylebox_override("fill", sbc(color, CLEAR, R_XS, 0, 0, 0))
	return pb


## Vertical ScrollContainer that fills its parent (horizontal scrolling off unless requested).
static func scroll(child: Control = null, horizontal: bool = false) -> ScrollContainer:
	var s: = ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if child:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.add_child(child)
	return s


## Centers child and caps its width at max_w (keeps ultra-wide layouts readable). Returns the container.
static func max_width(child: Control, max_w: float = 1680.0) -> Container:
	var c: = MaxWidthBox.new()
	c.max_w = max_w
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if child:
		c.add_child(child)
	return c


## Container used by max_width(): lays every child out centred, at most max_w wide, full height.
class MaxWidthBox:
	extends Container
	var max_w: float = 1680.0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			var w: = minf(size.x, max_w)
			var x: = floorf((size.x - w) * 0.5)
			for c in get_children():
				if c is Control and (c as Control).visible:
					fit_child_in_rect(c, Rect2(x, 0.0, w, size.y))

	func _get_minimum_size() -> Vector2:
		var m: = Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = m.max((c as Control).get_combined_minimum_size())
		return m
