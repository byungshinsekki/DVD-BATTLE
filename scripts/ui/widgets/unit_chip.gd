class_name UnitChip
extends Button
## Top-bar hero chip (team modes): portrait disc with an HP ring, the hero name and one cooldown pip
## per skill. refresh() is cheap enough to call every frame: the pips and the selection frame only
## redraw when something visible changed, and every StyleBox comes from the shared UITheme cache.


var sim: BattleSim
var idx: int = -1
var disc: GlyphDisc
var name_l: Label
var cd_bar: Control
var selected: bool = false
var perspective: int = -1
const NAME_W: = 66.0
const CHIP_W: = 116.0
const CHIP_H: = 56.0
const PIP_H: = 7.0
const PIP_GAP: = 3.0

var _cd_key: PackedInt32Array = PackedInt32Array()
var _tip_persp: int = -99
var _drawn_sel: bool = false


func _init(s: BattleSim, i: int) -> void :
	sim = s
	idx = i
	var u: = s.u_at(i)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	var empty: = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", UITheme.sbc(Color(1, 1, 1, 0.05), UITheme.CLEAR, UITheme.R_M, 0, 0))
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("hover_pressed", empty)
	add_theme_stylebox_override("focus", empty)
	var h: = UITheme.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	h.offset_right = -2
	add_child(h)
	disc = GlyphDisc.new(u.def, 40, u.team)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(disc)
	var v: = UITheme.vbox(5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	# 13 px when the name fits, otherwise 12 px with an ellipsis (the tooltip keeps the full name).
	var fs: = 13 if DB.font_bold.get_string_size(u.def.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= NAME_W else UITheme.MIN_FS
	name_l = UITheme.label(u.def.name, "", fs, UITheme.TEXT)
	name_l.add_theme_font_override("font", DB.font_bold)
	UITheme.ellipsize(name_l)
	name_l.custom_minimum_size = Vector2(NAME_W, 0)
	v.add_child(name_l)
	cd_bar = Control.new()
	cd_bar.custom_minimum_size = Vector2(NAME_W, PIP_H + 1.0)
	cd_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_bar.draw.connect(_draw_cd)
	v.add_child(cd_bar)
	h.add_child(v)


## Updates the disc, pips and tooltip. Only redraws what changed.
func refresh() -> void :
	var u: = sim.u_at(idx)
	if u == null:
		return
	var mx: = maxf(1.0, sim.max_hp(u))
	var enemy_view: = perspective >= 0 and sim.eteam(u) != perspective
	if enemy_view:
		var belief: = _belief()
		if belief:
			disc.set_state(clampf(belief.hp / maxf(1.0, belief.max_hp), 0.0, 1.0) if not belief.dead else 0.0, belief.shield / maxf(1.0, belief.max_hp), belief.dead)
			_set_modulate(disc, 1.0 if belief.visible else 0.5)
		else:
			disc.set_state(-1.0, 0.0, false)
			_set_modulate(disc, 0.5)
		_set_modulate(name_l, 1.0)
	else:
		disc.set_state(u.hp / mx if u.alive else 0.0, sim.shield_amount(u) / mx if u.alive else 0.0, not u.alive)
		_set_modulate(disc, 1.0)
		_set_modulate(name_l, 1.0 if u.alive else 0.45)
	if disc.highlight != selected:
		disc.highlight = selected
		disc.queue_redraw()
	var key: = _cd_state(u, enemy_view)
	if key != _cd_key:
		_cd_key = key
		cd_bar.queue_redraw()
	if selected != _drawn_sel:
		_drawn_sel = selected
		queue_redraw()
	if perspective != _tip_persp:
		_tip_persp = perspective
		tooltip_text = "%s — %s" % [u.def.name, "팀이 추정한 체력과 스킬 준비 확률입니다" if enemy_view else "누르면 자세한 정보를 봅니다"]


static func _set_modulate(c: CanvasItem, a: float) -> void:
	if not is_equal_approx(c.modulate.a, a):
		c.modulate = Color(1, 1, 1, a)


## Compact snapshot of what the pips show; the pips redraw only when it changes.
func _cd_state(u: BUnit, enemy_view: bool) -> PackedInt32Array:
	var k: = PackedInt32Array([1 if u.alive else 0, 1 if enemy_view else 0])
	if not u.alive and sim.is_control_mode() and not enemy_view:
		k.append(int(ceil(maxf(0.0, float(sim.domination.respawn_at.get(idx, sim.time)) - sim.time) * 10.0)))
		return k
	var belief: TeamIntel.EnemyBelief = _belief() if enemy_view else null
	for i in u.def.abilities.size():
		if enemy_view:
			k.append(int(float(sim.controllers[perspective].intel.ready_prob(belief, i)) * 24.0) if belief else -1)
			continue
		var a: Defs.AbilityDef = u.def.abilities[i]
		var rem: = u.cooldowns[i] - sim.time if i < u.cooldowns.size() else 0.0
		if u.sealed.has(i):
			k.append(-2)
		elif rem <= 0.0:
			k.append(99)
		else:
			k.append(int((1.0 - clampf(rem / maxf(0.1, a.cooldown), 0.0, 1.0)) * 24.0))
	return k


func _belief() -> TeamIntel.EnemyBelief:
	if perspective < 0 or perspective >= sim.controllers.size():
		return null
	var ctl = sim.controllers[perspective]
	if ctl == null or not ("intel" in ctl) or ctl.intel == null:
		return null
	return ctl.intel.enemies.get(idx)


func _draw_cd() -> void :
	var u: = sim.u_at(idx)
	if u == null:
		return
	if not u.alive and sim.is_control_mode() and (perspective < 0 or sim.eteam(u) == perspective):
		var remaining: float = maxf(0.0, float(sim.domination.respawn_at.get(idx, sim.time)) - sim.time)
		cd_bar.draw_string(DB.font_bold, Vector2(0, PIP_H + 1.0), "부활 %.1f초" % remaining, HORIZONTAL_ALIGNMENT_LEFT, NAME_W, UITheme.MIN_FS, UITheme.GOLD)
		return
	var n: = u.def.abilities.size()
	if n <= 0:
		return
	var w: = minf(16.0, (NAME_W - PIP_GAP * (n - 1)) / float(n))
	var enemy_view: = perspective >= 0 and sim.eteam(u) != perspective
	var belief: TeamIntel.EnemyBelief = _belief() if enemy_view else null
	for i in n:
		var a: Defs.AbilityDef = u.def.abilities[i]
		var col: = VfxStyle.color_for(a)
		var rect: = Rect2(i * (w + PIP_GAP), 0, w, PIP_H)
		cd_bar.draw_rect(rect, Color(0, 0, 0, 0.5))
		if enemy_view:
			if belief:
				var probability: = float(sim.controllers[perspective].intel.ready_prob(belief, i))
				cd_bar.draw_rect(Rect2(rect.position, Vector2(w * probability, PIP_H)), Color(col, 0.5))
			cd_bar.draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)
			continue
		var rem: = u.cooldowns[i] - sim.time if i < u.cooldowns.size() else 0.0
		if u.sealed.has(i):
			cd_bar.draw_rect(rect, Color(0.78, 0.32, 0.55, 0.9))
		elif rem <= 0.0:
			cd_bar.draw_rect(rect, Color(col, 0.95 if u.alive else 0.3))
		else:
			var k: = 1.0 - clampf(rem / maxf(0.1, a.cooldown), 0.0, 1.0)
			cd_bar.draw_rect(Rect2(rect.position, Vector2(w * k, PIP_H)), Color(col, 0.38))
			cd_bar.draw_rect(rect, Color(col, 0.35), false, 1.0)


func _draw() -> void :
	if not selected:
		return
	var u: = sim.u_at(idx) if sim else null
	if u == null:
		return
	draw_style_box(UITheme.sbc(Color(1, 1, 1, 0.06), Color(UITheme.team_color(u.team), 0.8), UITheme.R_M, 1, 0), Rect2(Vector2.ZERO, size))
