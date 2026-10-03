class_name BattleView
extends Node2D




var sim: BattleSim
var runner: BattleRunner
var arena: Arena
var perspective: int = -1
var selected: int = -1
var show_ai: bool = true
var show_names: bool = true
var show_numbers: bool = true
var show_telegraphs: bool = true
var shake_enabled: bool = true
var hitstop_enabled: bool = true
var quality: int = 2
var anim: float = 0.0
var fit_rect: Rect2 = Rect2(0, 0, 1408, 792)
var view_scale: float = 1.0

## Legible in-world HUD (the battle screen turns it on; SkillPreview/LivePreview keep the old
## world-scaled look). When on, names, kit labels, AI purpose, belief text, status glyphs, item
## captions, zone/bed/turret/objective labels and fx texts are drawn at a fixed screen size
## (VfxStyle.hud_px: never below a per-class minimum, snapped to a short size set), HP bars get a
## minimum on-screen size, and wide overviews (view_scale < 0.5) switch to compact labels.
var hud_readable: bool = false
## View scale used for HUD sizing: follows view_scale with an 8% dead band so text does not
## hop between sizes while the camera eases.
var hud_scale: float = 1.0
## Hero under the mouse (readable HUD only; -1 = none). Gets a full label in compact mode.
var hovered: int = -1
var _inv: float = 1.0
var _lod: bool = false
var _hover_item: int = -1
var _top: PackedInt32Array = PackedInt32Array([-1, -1, -1])
var _line_w: PackedFloat32Array = PackedFloat32Array()
var _line_px: PackedInt32Array = PackedInt32Array()

# Minimum screen sizes (px) per HUD text class.
const PX_NAME: = 12.0
const PX_SUB: = 11.0
const PX_ICON: = 10.0
const PX_CALL: = 13.0
const PX_MARK: = 14.0
# Minimum on-screen HP bar (heroes) and the compact-label threshold (with hysteresis).
const HP_MIN_W: = 34.0
const HP_MIN_H: = 5.0
const LOD_IN: = 0.47
const LOD_OUT: = 0.53

var static_layer: Node2D
var hazard_layer: Node2D
var objective_layer: Node2D
var zone_layer: Node2D
var unit_layer: Node2D
var proj_layer: Node2D
var proj_solid_layer: Node2D
var fx: FxSystem
var ev_fx: EventFx
var fog: FogOverlay
var overlay_layer: Node2D
var hud_layer: Node2D
var item_layer: Node2D
var canopy_layer: Node2D

var hp_chip: Dictionary = {}
var trails: Dictionary = {}
var death_t: Dictionary = {}
var kill_feed: Array = []
var _seen_cache: Dictionary = {}
var _seen_cache_frame: int = -1
var sound: bool = true
var swing_at: Dictionary = {}
var motion_trails: Dictionary = {}
var _pulse_at: Dictionary = {}
# ArenaPainter.static_env_sig the static floor / canopy layers were drawn with.
var _static_env_sig: int = 0

# V2 battleground (DESIGN_V2 §3.8): the mode (null in every other battle), the
# team the auto camera follows (-1 = the selected hero's team), recent fight
# spots for the camera director, the world rectangle overlays are culled to and
# the public zone view (re-read when the sim clock advances).
var br: BattlegroundMode
var follow_team: int = -1
var _heat: Array = []
var _heat_next: int = 0
var _cull: Rect2 = Rect2()
var _zone_view: Dictionary = {}
var _zone_at: float = -1.0
const HEAT_KEEP: = 48
const HEAT_WINDOW: = 4.0
# Battleground static map (~600 obstacles, ~190 brush circles): obstacles and canopy are drawn in
# BR_CHUNK-sized canvas items so the renderer culls what is off screen, and the whole static map
# is baked once into BR_BAKE-scale textures that replace them in the overview.
const BR_CHUNK: = 1024.0
const BR_BAKE: = 0.3
var _br_obs_root: Node2D
var _br_canopy_root: Node2D
var _br_bake: SubViewport
var _br_bake_canopy: SubViewport
var _br_overview: bool = false
## Below this view scale damage numbers are not spawned (battleground overview).
const NUMBERS_MIN_SCALE: = 0.3


const PASSIVE_MOTIF: = {
	"swordsman": "triple", "archer": "wind", "mage": "hourglass", "sniper": "reticle", "werewolf": "lifesteal", 
	"giant": "regen", "aphrodite": "aegis", "blood_mage": "growth", "fisherman": "fish", "baseball": "reflect", 
	"pirate": "dual", "joker": "confusion", "metatron": "wings", "plague_doctor": "bank", "hive_mind": "neural", 
	"nitro": "reactor", "dimensionalist": "shards", "hermes": "borrow", "world_tree": "grove", "torturer": "pain", 
	"engineer": "gear", "politician": "arcs", 
	"hades": "kynee", "war_machine": "fuel", "torquemada": "faith", "achilles": "styx", 
}


func _init() -> void :
	static_layer = _layer("Static")
	hazard_layer = _layer("Hazards")
	zone_layer = _layer("Zones")
	fog = FogOverlay.new()
	fog.name = "Fog"
	add_child(fog)
	objective_layer = _layer("Objectives")
	objective_layer.draw.connect(_draw_objectives)
	item_layer = _layer("Items")
	item_layer.draw.connect(_draw_items)
	ev_fx = EventFx.new()
	ev_fx.name = "Events"
	add_child(ev_fx)
	unit_layer = _layer("Units")
	proj_solid_layer = _layer("ProjectilesSolid")
	proj_layer = _layer("Projectiles", true)
	canopy_layer = _layer("Canopy")
	canopy_layer.draw.connect(_draw_canopy)
	fx = FxSystem.new()
	fx.name = "Fx"
	add_child(fx)
	overlay_layer = _layer("Overlay")
	hud_layer = _layer("Hud")
	static_layer.draw.connect(_draw_static)
	hazard_layer.draw.connect(_draw_hazards)
	zone_layer.draw.connect(_draw_zones)
	unit_layer.draw.connect(_draw_units)
	proj_layer.draw.connect(_draw_projectiles)
	proj_solid_layer.draw.connect(_draw_projectiles_solid)
	overlay_layer.draw.connect(_draw_overlay)
	hud_layer.draw.connect(_draw_hud)
	fx.unit_pos_cb = func(i: int) -> Vector2:
		var u: = sim.u_at(i) if sim else null
		return upos(u) if u and u.alive else Vector2.INF
	ev_fx.unit_pos_cb = fx.unit_pos_cb
	# Same array object every frame (cleared and refilled by _draw_hud): readable fx texts rise
	# above last frame's unit labels and hero head stacks (HP bar + status row) instead of
	# covering them.
	fx.obstacles = _fx_obst


func _layer(n: String, additive: bool = false) -> Node2D:
	var l: = Node2D.new()
	l.name = n
	if additive:
		var m: = CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		l.material = m
	add_child(l)
	return l


func setup(s: BattleSim, r: BattleRunner) -> void :
	sim = s
	runner = r
	arena = s.arena
	cam_center = arena.center()
	cam_center_t = cam_center
	base_scale = minf(fit_rect.size.x / arena.width, fit_rect.size.y / arena.height)
	hp_chip.clear()
	trails.clear()
	death_t.clear()
	kill_feed.clear()
	swing_at.clear()
	_pulse_at.clear()
	fx.clear_all()
	ev_fx.clear_all()
	motion_trails.clear()
	_label_side.clear()
	_garden_fill.clear()
	br = s.battleground
	follow_team = -1
	_heat.clear()
	_heat_next = 0
	_zone_view = {}
	_zone_at = -1.0
	_cull = Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))
	_br_static_setup()
	fog.setup(self)
	_static_env_sig = ArenaPainter.static_env_sig(s.env)
	static_layer.queue_redraw()
	canopy_layer.queue_redraw()
	item_layer.queue_redraw()


func apply_settings() -> void :
	quality = int(Settings.get_v("vfx_quality", 2))
	shake_enabled = bool(Settings.get_v("screen_shake", true))
	hitstop_enabled = bool(Settings.get_v("hit_stop", true))
	show_numbers = bool(Settings.get_v("damage_numbers", true))
	show_names = bool(Settings.get_v("show_names", true))
	show_telegraphs = bool(Settings.get_v("telegraphs", true))
	fx.quality = quality
	ev_fx.quality = quality
	static_layer.queue_redraw()
	canopy_layer.queue_redraw()
	_br_redraw_static()



func fit(rect: Rect2) -> void :
	fit_rect = rect
	base_scale = minf(rect.size.x / _arena_size().x, rect.size.y / _arena_size().y)
	_apply_camera(0.0)



var base_scale: float = 1.0
var cam_mode: String = "auto"
var cam_zoom: float = 1.0
var cam_center: Vector2 = Vector2(_arena_size().x * 0.5, _arena_size().y * 0.5)
var cam_zoom_t: float = 1.0
var cam_center_t: Vector2 = Vector2(_arena_size().x * 0.5, _arena_size().y * 0.5)
const EDGE_ROOM: = 48.0


func set_cam_mode(m: String) -> void :
	cam_mode = m
	if m == "full":
		cam_zoom_t = 1.0
		cam_center_t = Vector2(_arena_size().x * 0.5, _arena_size().y * 0.5)


func manual_zoom(factor: float, around_screen: Vector2) -> void :
	cam_mode = "manual"
	var wp: = to_world(around_screen)
	cam_zoom_t = clampf(cam_zoom_t * factor, 1.0, max_zoom())
	cam_zoom = cam_zoom_t

	var s: = base_scale * cam_zoom
	var screen_c: = fit_rect.position + fit_rect.size * 0.5
	cam_center_t = wp - (around_screen - screen_c) / s
	cam_center = cam_center_t
	_apply_camera(0.0)


## Manual zoom cap: 4 on deathmatch maps, 3 elsewhere; the battleground allows close-ups on its
## ~30x maps (absolute view scale 1.6, at least 4x).
func max_zoom() -> float:
	if br != null:
		return maxf(4.0, 1.6 / maxf(0.01, base_scale))
	return 4.0 if sim and sim.deathmatch else 3.0


func manual_pan(screen_delta: Vector2) -> void :
	cam_mode = "manual"
	cam_center_t -= screen_delta / (base_scale * cam_zoom)
	cam_center = cam_center_t
	_apply_camera(0.0)


func _update_camera(delta: float) -> void :
	if cam_mode == "auto" and br != null:
		_br_camera()
	elif cam_mode == "auto" and sim and sim.deathmatch:
		# Free-for-all spreads over a large map: follow the selected hero and
		# whoever it is fighting, otherwise show the whole field.
		var su: = sim.u_at(selected)
		if su and su.is_hero and su.alive and _vis(su):
			var mn2: = upos(su)
			var mx2: = mn2
			for u2 in sim.heroes:
				if u2 != su and u2.alive and _vis(u2) and upos(u2).distance_to(upos(su)) < 520.0:
					mn2 = mn2.min(upos(u2))
					mx2 = mx2.max(upos(u2))
			var sz2: = (mx2 - mn2 + Vector2(420, 320)).max(Vector2(900, 520))
			cam_zoom_t = clampf(minf(fit_rect.size.x / sz2.x, fit_rect.size.y / sz2.y) / base_scale, 1.0, 2.6)
			cam_center_t = (mn2 + mx2) * 0.5
		else:
			cam_zoom_t = 1.0
			cam_center_t = arena.center()
	elif cam_mode == "auto" and sim:
		var have: = false
		var mn: = Vector2(INF, INF)
		var mx: = Vector2( - INF, - INF)
		for u in sim.heroes:
			if not u.alive or not _vis(u):
				continue
			var p: = upos(u)
			mn = mn.min(p)
			mx = mx.max(p)
			have = true
		if have:
			var pad: = Vector2(190, 150)
			mn -= pad
			mx += pad
			var sz: = (mx - mn).max(Vector2(520, 300))
			var z: = minf(fit_rect.size.x / sz.x, fit_rect.size.y / sz.y) / base_scale
			cam_zoom_t = clampf(z, 1.0, 1.75)
			cam_center_t = (mn + mx) * 0.5
	var k: = 1.0 - exp( - delta * 2.2)
	cam_zoom = lerpf(cam_zoom, cam_zoom_t, k)
	cam_center = cam_center.lerp(cam_center_t, k)


## V2 battleground auto camera (DESIGN_V2 §3.8): frames the followed team (follow_team, else the
## selected hero's team) and the visible rivals near it; once that team is out (or nothing of it is
## visible) it cuts to the hottest recent fight seen in this perspective, then to the safe zone.
func _br_camera() -> void:
	var team: int = follow_team
	if team < 0:
		var su: = sim.u_at(selected)
		team = su.team if su and su.is_hero else -1
	var mn: = Vector2(INF, INF)
	var mx: = Vector2(-INF, -INF)
	var have: = false
	if team >= 0 and not br.is_eliminated(team):
		for u in br.team_members(team):
			if u.alive and _vis(u):
				mn = mn.min(upos(u))
				mx = mx.max(upos(u))
				have = true
		if have:
			var c0: = (mn + mx) * 0.5
			for u2 in sim.heroes:
				if u2.alive and u2.team != team and _vis(u2) and upos(u2).distance_to(c0) < 700.0:
					mn = mn.min(upos(u2))
					mx = mx.max(upos(u2))
	if not have:
		var hot: = hottest_fight()
		if hot != Vector2.INF:
			mn = hot - Vector2(300, 200)
			mx = hot + Vector2(300, 200)
			have = true
	if not have and not _zone_view.is_empty() and int(_zone_view.get("phase", 0)) > 0:
		var zc: Vector2 = _zone_view.center
		var zr: float = maxf(500.0, float(_zone_view.radius))
		mn = zc - Vector2(zr, zr)
		mx = zc + Vector2(zr, zr)
		have = true
	if not have:
		cam_zoom_t = 1.0
		cam_center_t = arena.center()
		return
	var sz: = (mx - mn + Vector2(560, 400)).max(Vector2(1400, 820))
	var target_c: = (mn + mx) * 0.5
	cam_zoom_t = clampf(minf(fit_rect.size.x / sz.x, fit_rect.size.y / sz.y) / base_scale, 1.0, minf(max_zoom(), 1.0 / maxf(0.01, base_scale)))
	# A new subject far away (followed team out, another team picked): cut instead of a long pan.
	if target_c.distance_to(cam_center_t) > 2400.0:
		cam_center = target_c
		cam_zoom = cam_zoom_t
	cam_center_t = target_c


## Where the most damage was seen in the last HEAT_WINDOW s (Vector2.INF = no fight).
func hottest_fight() -> Vector2:
	var best: = Vector2.INF
	var best_w: = 0.0
	for a in _heat:
		if sim.time - float(a[1]) > HEAT_WINDOW:
			continue
		var w: = 0.0
		var acc: = Vector2.ZERO
		for b in _heat:
			if sim.time - float(b[1]) > HEAT_WINDOW or (a[0] as Vector2).distance_to(b[0]) > 500.0:
				continue
			var k: = 1.0 - (sim.time - float(b[1])) / HEAT_WINDOW
			w += k
			acc += (b[0] as Vector2) * k
		if w > best_w:
			best_w = w
			best = acc / w
	return best


func _note_heat(p: Vector2) -> void:
	if _heat.size() < HEAT_KEEP:
		_heat.append([p, sim.time])
	else:
		_heat[_heat_next] = [p, sim.time]
		_heat_next = (_heat_next + 1) % HEAT_KEEP


func _apply_camera(shake_amt: float) -> void :
	var s: = base_scale * cam_zoom
	view_scale = s
	scale = Vector2(s, s)


	var half: = fit_rect.size * 0.5 / s
	var c: = cam_center
	var room: = EDGE_ROOM if cam_zoom > 1.01 else 0.0
	if half.x * 2.0 < _arena_size().x + room * 2.0:
		c.x = clampf(c.x, half.x - room, _arena_size().x - half.x + room)
	else:
		c.x = _arena_size().x * 0.5
	if half.y * 2.0 < _arena_size().y + room * 2.0:
		c.y = clampf(c.y, half.y - room, _arena_size().y - half.y + room)
	else:
		c.y = _arena_size().y * 0.5
	cam_center = c
	var screen_c: = fit_rect.position + fit_rect.size * 0.5
	position = screen_c - c * s
	if shake_amt > 0.05:
		position += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt * s


func set_perspective(p: int) -> void :
	if perspective != p:
		# Fight locations belong to the view that observed them, just like fog knowledge.
		_heat.clear()
		_heat_next = 0
	perspective = p
	fog.visible = p >= 0
	fog.force_update()
	canopy_layer.queue_redraw()
	_br_redraw_static(true)


func to_world(screen_p: Vector2) -> Vector2:
	return (screen_p - position) / view_scale


func pick_unit(world_p: Vector2) -> int:
	if sim == null:
		return -1
	var best: = -1
	var bd: = INF
	# Battleground overviews: 14 screen px whatever the zoom (14 world px is ~2 px at 0.15).
	var reach: = 14.0 / maxf(0.05, view_scale) if br != null else 14.0
	for u in sim.units:
		if not u.alive or not _vis(u):
			continue
		var d: = upos(u).distance_to(world_p) - sim.radius(u)
		if d < reach and d < bd:
			bd = d
			best = u.idx
	return best


func upos(u: BUnit) -> Vector2:
	if runner == null:
		return u.pos
	if u.prev_pos.distance_squared_to(u.pos) > 90000.0:
		return u.pos
	return u.prev_pos.lerp(u.pos, runner.alpha)


func _process(delta: float) -> void :
	# A disposed battleground sim (the mode drops its sim): nothing to show any more.
	if sim == null or (br != null and br.sim == null):
		return
	anim += delta
	fx.time_scale = 0.0 if (runner.paused) else clampf(runner.speed, 0.25, 2.0)
	fx.step(delta if not runner.paused else 0.0)
	ev_fx.extra_load = sim.proj.list.size()
	ev_fx.step(0.0 if runner.paused else delta * fx.time_scale)

	for u in sim.units:
		if not u.alive:
			continue
		var cur: float = hp_chip.get(u.idx, u.hp)
		if cur < u.hp:
			cur = u.hp
		else:
			cur = move_toward(cur, u.hp, maxf(40.0, (cur - u.hp) * 3.0) * delta)
		hp_chip[u.idx] = cur

	_update_camera(delta)
	_apply_camera(fx.shake if shake_enabled else 0.0)
	if br != null:
		# Overview (whole map on screen): the baked static map instead of the vector chunks.
		var ov: bool = view_scale <= BR_BAKE if not _br_overview else view_scale <= BR_BAKE * 1.12
		if ov != _br_overview:
			_br_overview = ov
			_br_obs_root.visible = not ov
			_br_canopy_root.visible = not ov
			static_layer.queue_redraw()
			canopy_layer.queue_redraw()
		# Overlays (HUD, items, downed marks) skip what is more than 100 screen px off screen.
		_cull = Rect2(to_world(fit_rect.position), fit_rect.size / maxf(0.01, view_scale)).grow(100.0 / maxf(0.01, view_scale))
		if sim.time != _zone_at:
			_zone_at = sim.time
			_zone_view = br.zone_view()
	# Brush / mud are baked into the static floor and canopy layers: redraw them
	# when a lab switch changes their state, not every frame.
	var env_sig: int = ArenaPainter.static_env_sig(sim.env)
	if env_sig != _static_env_sig:
		_static_env_sig = env_sig
		static_layer.queue_redraw()
		canopy_layer.queue_redraw()
		_br_redraw_static()
	fx.readable = hud_readable
	if hud_readable:
		_update_hud_metrics()
	if not arena.hazards.is_empty() or not arena.gates.is_empty():
		hazard_layer.queue_redraw()
	zone_layer.queue_redraw()
	objective_layer.queue_redraw()
	if sim.deathmatch:
		item_layer.queue_redraw()
	unit_layer.queue_redraw()
	proj_layer.queue_redraw()
	proj_solid_layer.queue_redraw()
	overlay_layer.queue_redraw()
	hud_layer.queue_redraw()
	if fog.visible:
		fog.tick(delta)



func on_step(evs: Array) -> void :
	if sim == null:
		return
	for p in sim.proj.list:
		if p.dead:
			continue
		var trail: Array = trails.get(p.id, [])
		trail.append(p.pos)
		if trail.size() > (9 if quality >= 2 else 5):
			trail.pop_front()
		trails[p.id] = trail
	if Engine.get_process_frames() % 30 == 0:
		var live: = {}
		for p in sim.proj.list:
			live[p.id] = true
		for k in trails.keys():
			if not live.has(k):
				trails.erase(k)
	for ev in evs:
		_handle_event(ev)






## Damage / heal numbers: off in a battleground overview (view scale below NUMBERS_MIN_SCALE).
func _numbers_ok() -> bool:
	return br == null or view_scale >= NUMBERS_MIN_SCALE


func _vis(u: BUnit) -> bool:
	if perspective < 0 or u == null:
		return true
	return sim.is_seen(perspective, u)


func can_see(u: BUnit) -> bool:
	return _vis(u)



func throttle(key: String, gap: float) -> bool:
	var last: = float(_pulse_at.get(key, -99.0))
	if sim.time - last < gap:
		return false
	_pulse_at[key] = sim.time
	return true


func _pt_vis(p: Vector2, team: int = -2) -> bool:
	if perspective < 0 or team == perspective:
		return true
	var f: = Engine.get_process_frames()
	if f != _seen_cache_frame:
		_seen_cache.clear()
		_seen_cache_frame = f
	var key: = Vector2i(int(p.x / 12.0), int(p.y / 12.0))
	if _seen_cache.has(key):
		return _seen_cache[key]
	var v: = sim.point_seen(perspective, p)
	_seen_cache[key] = v
	return v


func _ev_vis(ev: Dictionary) -> bool:
	var ty: String = str(ev.get("type", ""))
	if ty in ["CONTROL_CAPTURED", "CONTROL_NEUTRALIZED", "CONTROL_CONTESTED", "CONTROL_SCORE"]:
		return true
	if perspective < 0:
		return true
	# Public map events (gate open/close, salvo warnings and strikes, ring phases)
	# have no source hero, so their sight flags are all false; every team sees
	# them, as in the battle log (strike circles are already drawn publicly).
	if CodexText.ENV_PUBLIC_LOG.has(ty):
		return true
	if ev.has("sv"):
		return bool(ev.sv[perspective]) or bool(ev.gv[perspective])
	return _pt_vis(ev.get("pos", Vector2.ZERO))






func _draw_static() -> void :
	if arena == null:
		return
	if br != null and _br_overview and _br_bake != null:
		static_layer.draw_texture_rect(_br_bake.get_texture(), Rect2(Vector2.ZERO, _arena_size()), false)
		return
	# Brush and mud follow the live switches (redrawn by _process when they change).
	ArenaPainter.draw_floor(static_layer, arena, 1.0, Vector2.ZERO, 2 if quality >= 1 else 1, _env())
	if br != null:
		return  # battleground obstacles: culled chunks (_br_static_setup)
	# Gates are drawn every frame (hazard layer) from the live battle-copy state.
	ArenaPainter.draw_obstacles(static_layer, arena, 1.0, Vector2.ZERO, 2 if quality >= 1 else 1, true)


func _draw_hazards() -> void :
	if arena == null:
		return
	ArenaPainter.text_zoom = clampf(1.0 / maxf(0.05, view_scale), 1.0, 3.0)
	ArenaPainter.draw_hazards(hazard_layer, arena, 1.0, Vector2.ZERO, sim.time, quality, anim, sim.env, _cull if br != null else Rect2())
	ArenaPainter.draw_gates(hazard_layer, arena, 1.0, Vector2.ZERO, sim.time, quality, anim, sim.env)
	ArenaPainter.text_zoom = 1.0








func _garden_polys(g: Dictionary) -> Array:
	var gid: = int(g.get("id", -1))
	if _garden_fill.has(gid):
		return _garden_fill[gid]
	var pts: PackedVector2Array = g.points
	var out: Array = []
	if not Geometry2D.triangulate_polygon(pts).is_empty():
		out.append(pts)
	else:
		var parts: Array = Geometry2D.merge_polygons(pts, PackedVector2Array())

		var big: = -1.0
		var outer_cw: = false
		for part in parts:
			var ar: = absf(_signed_area(part))
			if ar > big:
				big = ar
				outer_cw = Geometry2D.is_polygon_clockwise(part)
		for part in parts:
			if part.size() >= 3 and Geometry2D.is_polygon_clockwise(part) == outer_cw and not Geometry2D.triangulate_polygon(part).is_empty():
				out.append(part)
	_garden_fill[gid] = out
	return out


static func _signed_area(ps: PackedVector2Array) -> float:
	var a: = 0.0
	var n: = ps.size()
	for i in n:
		a += ps[i].x * ps[(i + 1) % n].y - ps[(i + 1) % n].x * ps[i].y
	return a * 0.5


func _draw_zones() -> void :
	var ci: = zone_layer
	for g in sim.gardens:
		if float(g.end) <= sim.time:
			continue
		if perspective >= 0 and int(g.team) != perspective and not _pt_vis(_poly_center(g.points)):
			continue
		var gc: = UITheme.team_color(int(g.team)).lerp(Color("#76ddb0"), 0.6)
		var thorn: = float(g.get("thorn_until", 0.0)) > sim.time
		var pts: PackedVector2Array = g.points
		if pts.size() >= 3:
			for fp in _garden_polys(g):
				ci.draw_colored_polygon(fp, Color(Color("#c7e36a") if thorn else gc, 0.16 + (0.06 * sin(anim * 3.0) if thorn else 0.0)))
			var closed: = pts.duplicate()
			closed.append(pts[0])
			ci.draw_polyline(closed, Color(gc, 0.7), 2.0, true)
			if thorn and quality >= 1:
				for k in pts.size():
					var a: Vector2 = pts[k]
					var b: Vector2 = pts[(k + 1) % pts.size()]
					var n: = int(a.distance_to(b) / 18.0)
					for j in n:
						var q: = a.lerp(b, (j + 0.5) / maxf(1, n))
						var nrm: = (b - a).orthogonal().normalized() * 6.0
						ci.draw_line(q - nrm, q + nrm, Color(0.9, 1.0, 0.5, 0.6), 1.5, true)

			if quality >= 1:
				var gcen: = _poly_center(pts)
				for w in 3:
					var rr: = fmod(anim * 18.0 + w * 26.0, 78.0)
					ci.draw_arc(gcen, rr, 0, TAU, 40, Color(gc, 0.14 * (1.0 - rr / 78.0)), 1.0, true)
			_text(ci, _poly_center(pts) + Vector2(0, 4), "%d / %d초" % [int(ceil(float(g.get("budget", 0.0)))), int(ceil(float(g.end) - sim.time))], Color(gc.lightened(0.35), 0.9), 10)

	for wt in sim.heroes:
		if not wt.alive or wt.def.id != "world_tree" or not _vis(wt):
			continue
		var seeds: Array = wt.ks.get("seeds", [])
		if seeds.is_empty():
			continue
		var wc: = wt.def.accent
		var path: = PackedVector2Array()
		for sp in seeds:
			path.append(sp as Vector2)
		path.append(upos(wt))
		for k2 in path.size() - 1:
			_dashed(ci, path[k2], path[k2 + 1], Color(wc, 0.45), 1.2, 5.0)
		for sp2 in seeds:
			ci.draw_circle(sp2 as Vector2, 2.6, VfxStyle.hdr(wc, 1.2))
		if seeds.size() >= 3:
			_dashed(ci, upos(wt), seeds[0] as Vector2, Color(wc, 0.18), 1.0, 4.0)
	for z in sim.zones.list:
		if z.finished or z.end <= sim.time:
			continue
		if not _pt_vis(z.pos, z.team):
			continue
		_draw_zone(ci, z)
	for pp in sim.portal_pairs:
		if float(pp.end) <= sim.time:
			continue
		var col: = UITheme.team_color(int(pp.team)).lerp(Color("#70d3ef"), 0.5)
		var a2: Vector2 = pp.a
		var b2: Vector2 = pp.b
		if perspective >= 0 and int(pp.team) != perspective and not (_pt_vis(a2) or _pt_vis(b2)):
			continue
		_dashed(ci, a2, b2, Color(col, 0.35), 2.0, 10.0)
		var owner_p: = sim.u_at(int(pp.get("source", -1)))
		var armed: = owner_p != null and float(owner_p.ks.get("portal_armed_until", 0.0)) > sim.time
		var prad: = float(pp.radius)
		for q in [a2, b2]:
			var qv: Vector2 = q
			var other: Vector2 = b2 if qv == a2 else a2
			_portal(ci, qv, prad, col)
			var dq: = (other - qv).normalized()
			ci.draw_line(qv + dq * (prad * 0.4), qv + dq * (prad + 12.0), Color(col.lightened(0.3), 0.7), 1.5, true)
			ci.draw_colored_polygon(PackedVector2Array([qv + dq * (prad + 16.0), qv + dq * (prad + 9.0) + dq.orthogonal() * 4.0, qv + dq * (prad + 9.0) - dq.orthogonal() * 4.0]), Color(col.lightened(0.3), 0.8))
			if armed:

				for i in 3:
					var aa: = i * TAU / 3.0 + anim * 0.8
					ci.draw_colored_polygon(Motifs.ngon(3.0, 3, aa, qv + Vector2.from_angle(aa) * (prad + 6.0)), VfxStyle.hdr(col, 1.6))
				ci.draw_arc(qv, prad + 3.0, 0, TAU, 32, Color(VfxStyle.hdr(col, 1.4), 0.6), 2.0, true)
			_text(ci, qv + Vector2(0, prad + _below(14.0, 9.0, PX_SUB)), "%.1f초" % maxf(0.0, float(pp.end) - sim.time), Color(col.lightened(0.3), 0.85), 9)
	for c in sim.chambers:
		if c.get("ended", false):
			continue
		var cc: Vector2 = c.center
		if not _pt_vis(cc):
			continue
		var rect: = Rect2(cc - Vector2(80, 56), Vector2(160, 112))
		ci.draw_rect(rect, Color(0.08, 0.02, 0.06, 0.7))
		ci.draw_rect(rect, Color(1.4, 0.5, 1.0, 0.9), false, 2.5)
		for k in 7:
			var x: = rect.position.x + rect.size.x * (k + 0.5) / 7.0
			ci.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.9, 0.45, 0.75, 0.35), 2.0)
		var rem: = float(c.end) - sim.time
		_text(ci, cc + Vector2(0, -56.0 - _above(10.0)), "밀실 %.1f" % maxf(0.0, rem), Color("#ff9ad0"), 13)

	for prison: Dictionary in sim.warfare.prisons:
		if bool(prison.get("ended", false)) or float(prison.end) <= sim.time:
			continue
		var center: Vector2 = prison.center
		if not _pt_vis(center):
			continue
		var radius: = float(prison.get("radius", 64.0))
		var left: = maxf(0.0, float(prison.end) - sim.time)
		var cage_col: = Color("#e789ba")
		var fade: = minf(1.0, left * 3.0)
		ci.draw_circle(center, radius, Color(cage_col, 0.08 * fade))
		ci.draw_arc(center, radius, 0, TAU, 64, Color(0.025, 0.015, 0.03, 0.92 * fade), 9.0, true)
		ci.draw_arc(center, radius, 0, TAU, 64, Color(cage_col, 0.88 * fade), 3.5, true)
		ci.draw_arc(center - Vector2(0, 20), radius, 0, TAU, 64, Color(cage_col, 0.55 * fade), 1.8, true)
		for bar in 16:
			var base: = center + Vector2.from_angle(TAU * bar / 16.0) * radius
			ci.draw_line(base, base - Vector2(0, 20), Color(cage_col, 0.55 * fade), 2.0, true)
		_text(ci, center + Vector2(0, radius + _below(17.0, 11.0, PX_SUB)), "감금 · 방어 감소 · %.1f초" % left, Color(cage_col.lightened(0.2), fade), 11)

	for j in sim.delayed:
		if str(j.get("kind", "")) != "area":
			continue
		var p: Vector2 = j.pos
		var src: = sim.u_at(int(j.get("source", -1)))
		if src and not _pt_vis(p, src.team):
			continue
		var total: = 0.8
		var left: = float(j.at) - sim.time
		var k2: = clampf(1.0 - left / total, 0.0, 1.0)
		var colj: = Color("#ff8d63")
		var ab = (j.get("ctx", {}) as Dictionary).get("ability")
		if ab is Defs.AbilityDef:
			colj = VfxStyle.color_for(ab)
		var r2: = float(j.radius)
		ci.draw_circle(p, r2, Color(colj, 0.1))
		ci.draw_circle(p, r2 * k2, Color(colj, 0.2))
		ci.draw_arc(p, r2, 0, TAU, 64, Color(colj, 0.85), 2.0, true)
	if show_telegraphs:
		for tg in sim.telegraphs:
			if tg.cancelled or float(tg.end) <= sim.time:
				continue
			# Environment strikes (artillery) are public map state drawn by the hazard layer.
			if bool(tg.get("env", false)):
				continue
			var src2: = sim.u_at(int(tg.source))
			if src2 and not _vis(src2):
				continue
			_draw_telegraph(ci, tg)


func _poly_center(pts: PackedVector2Array) -> Vector2:
	var c: = Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(1, pts.size())


func _draw_zone(ci: CanvasItem, z: ST.Zone) -> void :
	var life: = clampf((sim.time - z.start) / maxf(0.01, z.end - z.start), 0.0, 1.0)
	var fade: = minf(1.0, (z.end - sim.time) * 3.0) * minf(1.0, (sim.time - z.start) * 6.0)
	var edge: Color = EventFx.TEAM_TINT[clampi(z.team, 0, 1)]
	var ink: = Color(EventFx.INK, fade)
	match z.kind:
		"coin":

			var r: = 6.0 + sin(anim * 6.0 + z.id) * 0.6
			ci.draw_circle(z.pos, r + 3.0, Color(1.0, 0.8, 0.3, 0.16 * fade))
			ci.draw_circle(z.pos, r, Color(Color("#d4a953"), fade))
			ci.draw_arc(z.pos, r, 0, TAU, 16, Color(Color("#fff1b6"), fade), 1.2, true)
			ci.draw_line(z.pos + Vector2(0, -3), z.pos + Vector2(0, 3), Color(Color("#624920"), fade), 1.2, true)
		"banana":
			var bc: = Color("#f3db55")
			_origin_zone_base(ci, z, bc, edge, fade, life, 0.042, true)
			Motifs.draw(ci, "banana", z.pos, 0.0, 7.0, Color(bc, fade), Color(1.0, 0.97, 0.8, fade), anim)
			_text(ci, z.pos + Vector2(0, -14), "!", Color(bc.lightened(0.2), fade), 16)
		"bait":
			var bc2: = Color("#8fe1dd")
			_origin_zone_base(ci, z, bc2, edge, fade, life, 0.042, false)
			ci.draw_arc(z.pos, 18.0, 0, TAU, 28, Color(bc2, fade), 1.6, true)
			for i in 3:
				var d: = Vector2.from_angle(i * TAU / 3.0)
				ci.draw_line(z.pos + d * 30.0, z.pos + d * 23.0, Color(bc2, 0.45 * fade), 1.0, true)
			_text(ci, z.pos + Vector2(0, 4), "미끼", Color(bc2, fade), 9)
		"mist":
			var mc: = Color("#83deaf")
			for k in 4:
				var off: = Vector2.from_angle(anim * 0.8 + k * 1.57) * z.radius * 0.35
				ci.draw_circle(z.pos + off, z.radius * 0.6, Color(mc, 0.05 * fade))
			_origin_zone_base(ci, z, mc, edge, fade, life, 0.075, false)
			ci.draw_line(z.pos - Vector2(7, 0), z.pos + Vector2(7, 0), Color(mc, fade), 2.0, true)
			ci.draw_line(z.pos - Vector2(0, 7), z.pos + Vector2(0, 7), Color(mc, fade), 2.0, true)
			_text(ci, z.pos + Vector2(0, 7.0 + _below(16.0, 10.0, PX_SUB)), str(int(round(float(z.data.get("budget", 0.0))))), Color(mc.lightened(0.2), 0.95 * fade), 10)
		"rift":

			var a: Vector2 = z.data.get("a", z.pos)
			var b: Vector2 = z.data.get("b", z.pos)
			var rc: = Color("#82dbf2")
			ci.draw_line(a, b, ink, 13.0, true)
			ci.draw_line(a, b, Color(edge, 0.75 * fade), 9.0, true)
			ci.draw_line(a, b, Color(rc, 0.95 * fade), 2.4, true)
			var dr: = (b - a).normalized().orthogonal()
			for k4 in 7:
				var at: = a.lerp(b, (k4 + 0.5) / 7.0)
				var off2: = sin(anim * 2.0 + k4) * 2.0
				ci.draw_line(at - dr * (6.0 + off2), at + dr * (6.0 + off2), Color(Color("#e7fbff"), 0.55 * fade), 1.0, true)
			var refl: = float(z.data.get("reflect", 0.0))
			_plate(ci, a.lerp(b, 0.5) - Vector2(0, 16), "%d%% 반사" % int(round(refl * 100.0)) if refl > 0.0 else "투사체 무효화", rc, fade)
		"portal":
			_portal(ci, z.pos, maxf(22.0, z.radius), UITheme.team_color(z.team).lerp(Color("#70d3ef"), 0.5))
		"bed":
			var pc: = Color("#ed9fc6")
			_origin_zone_base(ci, z, pc, edge, fade, life, 0.042, false)
		"cone":
			_cone_zone(ci, z, edge, fade)
		_:
			if z.shape == "cone":
				_cone_zone(ci, z, edge, fade)
				return
			# V2: genocide strip (rect) and the auto-da-fe purification fire.
			if z.shape == "rect":
				_rect_zone(ci, z, life, fade, edge)
				return
			if z.pattern == "autoDaFe":
				_pyre_zone(ci, z, life, fade, edge)
				return
			_generic_zone(ci, z, life, fade, edge)



func _origin_zone_base(ci: CanvasItem, z: ST.Zone, col: Color, edge: Color, fade: float, life: float, fill: float, dashed: bool) -> void :
	var r: = maxf(1.0, z.radius)
	ci.draw_circle(z.pos, r, Color(col, fill * fade))
	ci.draw_arc(z.pos, r, 0, TAU, 56, Color(EventFx.INK, fade), 4.0, true)
	if dashed:
		var pts: = PackedVector2Array()
		for i in 49:
			pts.append(z.pos + Vector2.from_angle(TAU * i / 48.0) * r)
		_dashed_poly(ci, pts, Color(edge, 0.8 * fade), 1.6, 3.0, 5.0)
	else:
		ci.draw_arc(z.pos, r, 0, TAU, 56, Color(edge, 0.8 * fade), 1.6, true)
	ci.draw_arc(z.pos, maxf(1.0, r - 4.0), - PI * 0.5, - PI * 0.5 + TAU * (1.0 - life), 48, Color(col, 0.78 * fade), 2.0, true)



# V2 war machine S4: the rect strip (pos = segment start, data.a/b, width), with
# tick-synced bomb blasts, a cold slow wash and the remaining time along one edge.
func _rect_zone(ci: CanvasItem, z: ST.Zone, life: float, fade: float, edge: Color) -> void :
	var ab = z.ctx.get("ability")
	var a: Defs.AbilityDef = ab if ab is Defs.AbilityDef else null
	var sp: = EventFx.spec(EventFx.ability_key(a)) if a else {}
	var col: Color = sp.get("color", z.color)
	var pa: Vector2 = z.data.get("a", z.pos)
	var pb: Vector2 = z.data.get("b", z.pos + z.dir * z.range)
	var ln: = pa.distance_to(pb)
	var d: = (pb - pa) / ln if ln > 1.0 else z.dir
	var n: = d.orthogonal()
	var hw: = maxf(1.0, z.width * 0.5)
	var strip: = PackedVector2Array([pa + n * hw, pb + n * hw, pb - n * hw, pa - n * hw])
	ci.draw_colored_polygon(strip, Color(col, 0.11 * fade))
	# Scorch craters left by earlier ticks (fixed per zone).
	for i in (6 if quality >= 1 else 3):
		var cq: = pa + d * ln * ((i + 0.5) / 6.0) + n * hw * (EventFx.rnd(z.id, i) - 0.5) * 1.2
		var cr: = 5.0 + EventFx.rnd(z.id, i + 40) * 5.0
		ci.draw_circle(cq, cr, Color(0.07, 0.04, 0.02, 0.35 * fade))
		ci.draw_arc(cq, cr, 0, TAU, 14, Color(col, 0.3 * fade), 1.2, true)
	ci.draw_colored_polygon(PackedVector2Array([pa + n * hw * 0.55, pb + n * hw * 0.55, pb - n * hw * 0.55, pa - n * hw * 0.55]), Color(0.48, 0.77, 1.0, 0.05 * fade))
	var closed: = strip.duplicate()
	closed.append(strip[0])
	ci.draw_polyline(closed, Color(EventFx.INK, fade), 5.0, true)
	ci.draw_polyline(closed, Color(edge, 0.75 * fade), 2.0, true)
	if quality >= 1:
		var x: = fmod(anim * 26.0, 32.0) + 10.0
		while x < ln - 4.0:
			var c: = pa + d * x
			ci.draw_polyline(PackedVector2Array([c + n * hw * 0.78 - d * 9.0, c, c - n * hw * 0.78 - d * 9.0]), Color(col, 0.22 * fade), 2.2, true)
			x += 32.0
	ci.draw_line(pa + n * (hw - 3.5), pa + n * (hw - 3.5) + d * ln * (1.0 - life), Color(col, 0.85 * fade), 2.5, true)
	# Bombs land on every damage tick (ticks every z.interval from z.start).
	var interval: = maxf(0.05, z.interval)
	var ph: = clampf(1.0 - (z.next_tick - sim.time) / interval, 0.0, 1.0)
	var tick_i: = int(round((z.next_tick - z.start) / interval))
	var sd: = int(sp.get("seed", z.id)) + tick_i * 7919
	var bombs: = 5 if quality >= 1 else 3
	for i in bombs:
		var q: = pa + d * ln * ((i + EventFx.rnd(sd, i)) / bombs) + n * hw * (EventFx.rnd(sd, i + 17) - 0.5) * 1.3
		var k: = clampf(ph * 1.4 - i * 0.07, 0.0, 1.0)
		ci.draw_arc(q, 4.0 + k * 17.0, 0, TAU, 20, Color(VfxStyle.hdr(col, 1.4), 0.75 * (1.0 - k) * fade), 2.4 * (1.0 - k) + 0.6, true)
		if k < 0.25:
			ci.draw_circle(q, 5.5 * (1.0 - k / 0.25) + 0.5, Color(2.0, 1.55, 0.85, fade))
		else:
			ci.draw_circle(q, 2.5, Color(0.12, 0.08, 0.05, 0.45 * fade))


# V2 torquemada S1: the purification fire (ally zone) - a ring of flames around a
# warm floor, a cross sigil and the remaining time.
func _pyre_zone(ci: CanvasItem, z: ST.Zone, life: float, fade: float, edge: Color) -> void :
	var col: = z.color
	var r: = maxf(1.0, z.radius)
	var q: = z.pos
	ci.draw_circle(q, r, Color(col, 0.07 * fade))
	if quality >= 1 and FxSystem.soft_tex:
		var gr: = r * 1.05
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(q - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.72, 0.32, 0.13 * fade))
	ci.draw_arc(q, r, 0, TAU, 64, Color(EventFx.INK, fade), 5.0, true)
	ci.draw_arc(q, r, 0, TAU, 64, Color(edge, 0.7 * fade), 1.8, true)
	var count: = 20 if quality >= 1 else 12
	for i in count:
		var a: = i * TAU / count
		var base: = q + Vector2.from_angle(a) * (r - 1.5)
		var h: = 8.0 + 7.0 * absf(sin(anim * 6.5 + i * 2.3))
		var tip: = base + Vector2(0, - h) + Vector2.from_angle(a) * 2.5
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-4.2, 0), tip, base + Vector2(4.2, 0)]), Color(1.9, 0.92 + 0.15 * sin(i + anim * 3.0), 0.32, 0.7 * fade))
		ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-1.8, 0), base.lerp(tip, 0.55), base + Vector2(1.8, 0)]), Color(2.1, 1.85, 1.1, 0.8 * fade))
	for i in (8 if quality >= 1 else 4):
		var an: = EventFx.rnd(z.id, i) * TAU
		var rr: = sqrt(EventFx.rnd(z.id, i + 30)) * r * 0.8
		var rise: = fmod(anim * 18.0 + i * 9.0, 30.0)
		ci.draw_circle(q + Vector2(cos(an) * rr, sin(an) * rr - rise), 1.6, Color(2.0, 1.4, 0.6, 0.6 * (1.0 - rise / 30.0) * fade))
	ci.draw_line(q + Vector2(0, -13), q + Vector2(0, 11), Color(col.lightened(0.3), 0.8 * fade), 2.6, true)
	ci.draw_line(q + Vector2(-8, -5), q + Vector2(8, -5), Color(col.lightened(0.3), 0.8 * fade), 2.6, true)
	ci.draw_arc(q, r - 6.0, - PI * 0.5, - PI * 0.5 + TAU * (1.0 - life), 56, Color(col, 0.85 * fade), 2.5, true)


func _friendly_zone(z: ST.Zone, a: Defs.AbilityDef) -> bool:
	if z.filter == "ally" or (a and a.target == "position_ally"):
		return true
	for f in z.effects:
		if str((f as Dictionary).get("type", "")) == "heal" and not bool((f as Dictionary).get("enemyOnly", false)):
			return true
	return false




func _generic_zone(ci: CanvasItem, z: ST.Zone, life: float, fade: float, edge: Color) -> void :
	var ab = z.ctx.get("ability")
	var a: Defs.AbilityDef = ab if ab is Defs.AbilityDef else null
	var sp: = EventFx.spec(EventFx.ability_key(a)) if a else {}
	var heal: = _friendly_zone(z, a)
	var col: Color = EventFx.HEAL_COL if heal else (sp.get("color", z.color) as Color)
	var r: = maxf(1.0, z.radius)
	var q: = z.pos
	var fam: = str({"blood_mage": "blood", "plague_doctor": "plague", "hive_mind": "hive", "mage": "magic"}.get(str(sp.get("id", "")), ""))
	ci.draw_circle(q, r, Color(col, 0.065 * fade))
	ci.draw_arc(q, r, 0, TAU, 64, Color(EventFx.INK, fade), 5.0, true)
	ci.draw_arc(q, r, 0, TAU, 64, Color(edge, 0.75 * fade), 2.0, true)
	if heal:
		var o: = fmod(anim * 7.0, 26.0)
		var x: = - r + 20.0
		while x < r:
			var y: = - r + 20.0
			while y < r:
				if x * x + y * y < r * r * 0.64:
					var c: = q + Vector2(x, y - o * 0.2)
					ci.draw_line(c - Vector2(2.5, 0), c + Vector2(2.5, 0), Color(col, 0.16 * fade), 1.2, true)
					ci.draw_line(c - Vector2(0, 2.5), c + Vector2(0, 2.5), Color(col, 0.16 * fade), 1.2, true)
				y += 33.0
			x += 33.0
	elif fam in ["blood", "plague", "hive"]:
		for i in 9:
			var aa: = i * 2.399 + int(sp.get("variant", 0))
			var rr: = r * (0.26 + 0.07 * (i % 7))
			ci.draw_arc(q + Vector2.from_angle(aa) * rr, 2.0 + i % 3, 0, TAU, 10, Color(col, 0.22 * fade), 1.0, true)
	else:
		var ph: = fmod(anim * 0.35, 1.0)
		ci.draw_arc(q, r * (0.3 + ph * 0.65), 0, TAU, 48, Color(col, 0.15 * (1.0 - ph) * fade), 2.0, true)
	ci.draw_arc(q, maxf(1.0, r - 3.0), - PI * 0.5, - PI * 0.5 + TAU * (1.0 - life), 56, Color(col, 0.85 * fade), 2.5, true)
	for i in 4:
		_team_mark(ci, q + Vector2.from_angle(i * TAU / 4.0) * r, z.team, Color(edge, fade), 3.2)
	if heal:
		ci.draw_line(q - Vector2(7, 0), q + Vector2(7, 0), Color(col, 0.75 * fade), 2.5, true)
		ci.draw_line(q - Vector2(0, 7), q + Vector2(0, 7), Color(col, 0.75 * fade), 2.5, true)
	else:
		var cp: = Motifs.ngon(9.0, 6 if fam == "magic" else 4, int(sp.get("variant", 0)) * 0.2, q)
		cp.append(cp[0])
		ci.draw_polyline(cp, Color(col, 0.28 * fade), 1.0, true)

	if not sp.is_empty() and not bool(sp.clarity) and quality >= 1:
		var sd: = int(sp.seed)
		var count: = 9 if quality >= 2 else 4
		for i in count:
			var an: = EventFx.rnd(sd, i) * TAU
			var rr0: = sqrt(EventFx.rnd(sd, i + 30)) * r * 0.85
			var pp: = q + Vector2(cos(an) * rr0, sin(an) * rr0 + sin(anim * 0.9 + i) * 3.0)
			if str(sp.material) == "blood":
				ci.draw_set_transform(pp, 0.2, Vector2(1.0, (2.0 + i % 2) / (5.0 + i % 4)))
				ci.draw_circle(Vector2.ZERO, 5.0 + i % 4, Color(sp.color as Color, 0.16 * fade))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			elif str(sp.motif) == "meteor":
				ci.draw_line(pp, pp + Vector2(2, -4), Color(sp.color as Color, 0.3 * fade), 1.3, true)
			else:
				ci.draw_arc(pp, 1.3 + i % 3, 0, TAU, 10, Color(sp.color as Color, 0.24 * fade), 0.8, true)



func _cone_zone(ci: CanvasItem, z: ST.Zone, edge: Color, fade: float) -> void :
	var ab = z.ctx.get("ability")
	var a: Defs.AbilityDef = ab if ab is Defs.AbilityDef else null
	var sp: = EventFx.spec(EventFx.ability_key(a)) if a else {}
	var col: Color = sp.get("color", z.color)
	var rng_: = z.radius if z.range <= 0.0 else z.range
	var pts: = PackedVector2Array([z.pos])
	var base: = z.dir.angle() - z.angle * 0.5
	for j in 21:
		pts.append(z.pos + Vector2.from_angle(base + z.angle * j / 20.0) * rng_)
	ci.draw_colored_polygon(pts, Color(col, 0.07 * fade))
	var closed: = pts.duplicate()
	closed.append(z.pos)
	ci.draw_polyline(closed, Color(EventFx.INK, fade), 4.0, true)
	ci.draw_polyline(closed, Color(edge, 0.8 * fade), 1.6, true)
	if not sp.is_empty() and quality >= 1:
		var sd: = int(sp.seed)
		for i in (9 if quality >= 2 else 4):
			var an: = base + EventFx.rnd(sd, i) * z.angle
			var rr0: = sqrt(EventFx.rnd(sd, i + 30)) * rng_ * 0.85
			var pp: = z.pos + Vector2.from_angle(an) * rr0 + Vector2(0, sin(anim * 0.9 + i) * 3.0)
			ci.draw_arc(pp, 1.3 + i % 3, 0, TAU, 10, Color(col, 0.3 * fade), 0.8, true)



func _plate(ci: CanvasItem, c: Vector2, s: String, col: Color, fade: float) -> void :
	var f: = DB.font_bold
	var fs: = 10
	if hud_readable and fs * hud_scale <= 28.5:
		# Whole plate in screen px around `c`.
		var px: = _px(10.0, PX_SUB)
		var tw: = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var pr: = Rect2(-(tw + 16.0) * 0.5, -(px + 8.0) * 0.5, tw + 16.0, px + 8.0)
		ci.draw_set_transform(c, 0.0, Vector2(_inv, _inv))
		_rounded(ci, pr, 5.0, Color(0.02, 0.043, 0.075, 0.96 * fade))
		_rounded_line(ci, pr, 5.0, Color(col, 0.42 * fade), 1.0)
		ci.draw_string(f, Vector2(-tw * 0.5, px * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(col, fade))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var w: = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
	var rect: = Rect2(c.x - w * 0.5, c.y - 10.0, w, 20.0)
	_rounded(ci, rect, 5.0, Color(0.02, 0.043, 0.075, 0.96 * fade))
	_rounded_line(ci, rect, 5.0, Color(col, 0.42 * fade), 1.0)
	ci.draw_string(f, Vector2(c.x - (w - 18.0) * 0.5, c.y + 4.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, fade))





func _draw_telegraph(ci: CanvasItem, tg: Dictionary) -> void :
	var k: = clampf((sim.time - float(tg.start)) / maxf(0.01, float(tg.end) - float(tg.start)), 0.0, 1.0)
	var ab = tg.get("ability")
	var a: Defs.AbilityDef = ab if ab is Defs.AbilityDef else null
	var team: = clampi(int(tg.team), 0, 1)
	var support: = a != null and a.target in ["ally", "position_ally"]
	var col: Color = EventFx.HEAL_COL if support else EventFx.TEAM_TINT[team]
	var src: = sim.u_at(int(tg.source))
	var shape: = str(tg.shape)
	var from: Vector2 = tg.from
	var to: Vector2 = tg.to
	var ink: = Color(EventFx.INK, 0.9)
	if shape == "target" or shape == "self":
		var q: = to
		var rr: = 18.0
		var tu: = src if shape == "self" else _telegraph_target(tg)
		if tu and tu.alive:
			q = upos(tu)
			rr = sim.radius(tu)
		rr += 8.0
		ci.draw_arc(q, rr, 0, TAU, 40, ink, 5.0, true)
		ci.draw_arc(q, rr, - PI * 0.5, - PI * 0.5 + TAU * k, 40, Color(col, 0.95), 2.2, true)
		for i in 4:
			var d: = Vector2.from_angle(i * TAU / 4.0 + PI * 0.25)
			ci.draw_line(q + d * (rr - 3.0), q + d * (rr + 4.0), col, 2.0, true)
	else:
		var dir: = (to - from).normalized() if to.distance_squared_to(from) > 1.0 else Vector2.RIGHT
		var rng_: = maxf(1.0, float(tg.range))
		var poly: = PackedVector2Array()
		var center: = to
		match shape:
			"circle":
				var rad: = maxf(1.0, float(tg.radius))
				for i in 40:
					poly.append(to + Vector2.from_angle(TAU * i / 40.0) * rad)
			"cone":
				center = from
				var ang: = float(tg.angle)
				poly.append(from)
				for i in 21:
					poly.append(from + Vector2.from_angle(dir.angle() - ang * 0.5 + ang * i / 20.0) * rng_)
			_:

				center = from
				var hw: = maxf(2.0, float(tg.width)) * 0.5
				var e: = from + dir * rng_
				var base: = dir.angle()
				for i in 9:
					poly.append(e + Vector2.from_angle(base - PI * 0.5 + PI * i / 8.0) * hw)
				for i in 9:
					poly.append(from + Vector2.from_angle(base + PI * 0.5 + PI * i / 8.0) * hw)
		if poly.size() < 3:
			return
		ci.draw_colored_polygon(poly, Color(col, 0.04 + 0.055 * k))
		var closed: = poly.duplicate()
		closed.append(poly[0])
		ci.draw_polyline(closed, Color(EventFx.INK, 0.75), 4.6, true)
		_dashed_poly(ci, closed, Color(col, 0.92), 2.0, 7.0, 5.0)
		if a and a.action == "whip" and shape == "cone":
			var sweet: = PackedVector2Array()
			var angle: = float(tg.angle)
			for i in 25:
				sweet.append(from + Vector2.from_angle(dir.angle() - angle * 0.5 + angle * i / 24.0) * rng_)
			for i in range(24, -1, -1):
				sweet.append(from + Vector2.from_angle(dir.angle() - angle * 0.5 + angle * i / 24.0) * rng_ * 0.75)
			ci.draw_colored_polygon(sweet, Color(Color("#e789ba"), 0.11 + 0.06 * k))
			ci.draw_arc(from, rng_ * 0.75, dir.angle() - angle * 0.5, dir.angle() + angle * 0.5, 25, Color(Color("#f5b0d4"), 0.75), 1.1, true)
		var reach: = maxf(rng_, float(tg.radius)) + 35.0

		if team == 1 and not support and quality >= 1:
			var hc: = Color(col, 0.06 + 0.035 * k)
			var x: = center.x - reach * 2.0
			while x < center.x + reach * 2.0:
				for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, center.y - reach), Vector2(x + reach * 2.0, center.y + reach)]), poly):
					ci.draw_polyline(seg, hc, 1.0, true)
				x += 22.0
		if shape == "circle":
			var rad2: = maxf(1.0, float(tg.radius))
			if k > 0.02:
				ci.draw_arc(to, rad2 * k, 0, TAU, 40, Color(col, 0.35), 1.2, true)
			ci.draw_arc(to, rad2, - PI * 0.5, - PI * 0.5 + TAU * k, 48, col, 3.0, true)
			_team_mark(ci, to, team, col, 5.0)
		else:
			var qk: = from + dir * rng_ * k
			var nrm: = dir.orthogonal()
			for seg2: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([qk - nrm * reach, qk + nrm * reach]), poly):
				ci.draw_polyline(seg2, Color(col, 0.45), 2.5, true)
			var tip: = from + dir * rng_
			ci.draw_polyline(PackedVector2Array([tip - dir * 10.0 + nrm * 5.0, tip - dir * 3.0, tip - dir * 10.0 - nrm * 5.0]), col, 2.0, true)

	if a and src and quality >= 1:
		var sp: = EventFx.spec(EventFx.ability_key(a))
		if not sp.is_empty() and not bool(sp.clarity):
			var rs: = sim.radius(src)
			var sc: Color = sp.color
			if FxSystem.soft_tex:
				var gr: = rs + 16.0
				ci.draw_texture_rect(FxSystem.soft_tex, Rect2(from - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(sc, 0.07 + k * 0.07))
			ci.draw_arc(from, rs + 4.0, - PI * 0.5, - PI * 0.5 + TAU * k, 32, Color(sc, 0.8), 1.8, true)
			var m: = str(sp.motif)
			if m in ["ice", "meteor", "flame", "crystal", "prism", "heart"]:
				var pp: = Motifs.ngon(rs + 8.0, 4 if m == "heart" else 6, k * 0.55, from)
				pp.append(pp[0])
				ci.draw_polyline(pp, Color(sc, 0.3 + k * 0.25), 1.0, true)



func _telegraph_target(tg: Dictionary) -> BUnit:
	var src: = sim.u_at(int(tg.source))
	if src and src.action and src.action.id == int(tg.get("action_id", -1)):
		return sim.u_at(src.action.target_idx)
	return null



func _team_mark(ci: CanvasItem, p: Vector2, team: int, col: Color, size: float) -> void :
	if team == 1:
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, - size), p + Vector2(size, size * 0.8), p + Vector2( - size, size * 0.8)]), col)
	else:
		ci.draw_circle(p, size * 0.8, col)


func _dashed_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float) -> void :
	var carry: = 0.0
	var on: = true
	for i in pts.size() - 1:
		var a0: = pts[i]
		var a1: = pts[i + 1]
		var L: = a0.distance_to(a1)
		if L < 0.01:
			continue
		var dir: = (a1 - a0) / L
		var t: = 0.0
		while t < L:
			var seg: = (dash if on else gap) - carry
			var t1: = minf(L, t + seg)
			if on:
				ci.draw_line(a0 + dir * t, a0 + dir * t1, col, w, true)
			if t + seg <= L:
				on = not on
				carry = 0.0
			else:
				carry += t1 - t
			t = t1






func _draw_units() -> void :
	var ci: = unit_layer
	_draw_motion_trails(ci)
	var cull: = br != null
	for e in sim.entities:
		if e.alive and e.kind != "chariot" and _vis(e) and not (cull and not _cull.has_point(e.pos)):
			_draw_entity(ci, e)
	for u in sim.heroes:
		if cull and not _cull.has_point(u.pos):
			continue
		if not u.alive:
			_draw_corpse(ci, u)
			continue
		if not _vis(u):
			continue
		if cull and br.downed.has(u.idx):
			_draw_downed(ci, u)
			continue
		_draw_hero(ci, u)
		if cull and br.reviving.has(u.idx):
			_draw_reviver(ci, u)
	# V2: the chariot (achilles S4) rides above the heroes it runs over.
	for e2 in sim.entities:
		if e2.alive and e2.kind == "chariot" and _vis(e2):
			_draw_entity(ci, e2)



func _draw_motion_trails(ci: CanvasItem) -> void :
	if quality <= 0:
		motion_trails.clear()
		return
	var t: = sim.time
	var live: = {}
	for u in sim.heroes:
		if not u.alive or not _vis(u):
			continue
		live[u.idx] = true
		var q: = upos(u)
		var active: = u.motion != null or float(u.ks.get("glide_until", 0.0)) > t
		var hist: Array = motion_trails.get(u.idx, [])
		if hist.is_empty() and not active:
			continue
		if not hist.is_empty() and (hist.back()[0] as Vector2).distance_to(q) > 95.0:
			hist.clear()
		if active and (hist.is_empty() or t > float(hist.back()[1]) + 1e-06):
			hist.append([q, t])
		while hist.size() > 7 or ( not hist.is_empty() and t - float(hist[0][1]) > 0.18):
			hist.pop_front()
		if hist.is_empty():
			motion_trails.erase(u.idx)
			continue
		motion_trails[u.idx] = hist
		var fam: Array = EventFx.FAMILIES.get(u.def.id, EventFx.NEXUS.get(u.def.id, []))
		var fc: = u.def.accent
		var fl: = u.def.accent.lightened(0.5)
		if fam.size() >= 5:
			fc = Color(str(fam[0]))
			fl = Color(str(fam[1]))
		elif fam.size() == 3:
			fc = Color(str(fam[1]))
			fl = Color(str(fam[2]))
		var r: = sim.radius(u)
		for i in range(1, hist.size()):
			var al: = clampf(1.0 - (t - float(hist[i][1])) / 0.18, 0.0, 1.0) * 0.23
			var p0: Vector2 = hist[i - 1][0]
			var p1: Vector2 = hist[i][0]
			ci.draw_line(p0, p1, Color(fc, al * 0.45), r * 0.85, true)
			ci.draw_line(p0, p1, Color(fl, al), 1.2, true)
			if i % 2 == 0:
				ci.draw_arc(p1, r * 0.82, 0, TAU, 24, Color(fc, al * 0.65), 1.0, true)
	for k in motion_trails.keys():
		if not live.has(k):
			motion_trails.erase(k)


func _status_lift(u: BUnit) -> float:
	if u.motion != null and u.motion.kind == "jump_pad":
		# Jump-pad flight: same arc as the pad preview and the flight trail.
		var m: ST.Motion = u.motion
		var dist: float = m.start.distance_to(m.end)
		var k: float = clampf((sim.time - BattleSim.DT * (1.0 - runner.alpha) - m.at) * m.speed / maxf(1.0, dist), 0.0, 1.0)
		return sin(PI * k) * ArenaPainter.leap_height(dist)
	if sim.has_status(u, &"airborne"):
		return 12.0 + 3.0 * sin(anim * 9.0)
	return 0.0


func _draw_hero(ci: CanvasItem, u: BUnit) -> void :
	var p: = upos(u)
	var r: = sim.radius(u)
	var tc: = UITheme.team_color(u.team)
	var acc: = u.def.accent
	var alpha: = 1.0
	var invis: = sim.has_status(u, &"invisible")
	if invis:
		alpha = 0.38 + 0.08 * sin(anim * 6.0)
	var lift: = _status_lift(u)
	var bp: = p - Vector2(0, lift)

	ci.draw_set_transform(p + Vector2(2, r * 0.62), 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, r * (1.05 + lift * 0.01), Color(0, 0, 0, 0.38 * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var controlled: = sim.eteam(u) != u.team

	if quality >= 1 and FxSystem.soft_tex:
		var hr: = r * 2.4
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(bp - Vector2(hr, hr), Vector2(hr, hr) * 2.0), false, Color(tc.r * 1.15, tc.g * 1.15, tc.b * 1.15, 0.22 * alpha))

	var hpr: = u.hp / maxf(1.0, sim.max_hp(u))
	if hpr < 0.25:
		var pulse: = 0.5 + 0.5 * sin(anim * 9.0)
		ci.draw_arc(bp, r + 7.0 + pulse * 3.0, 0, TAU, 40, Color(1.6, 0.35, 0.35, 0.35 + 0.4 * pulse), 2.0, true)

	KitVisuals.draw_under(self, ci, u, bp, r)

	ci.draw_circle(bp, r + 3.0, Color(tc, 0.95 * alpha))
	ci.draw_circle(bp, r, Color(acc.darkened(0.58), alpha))
	ci.draw_circle(bp, r * 0.84, Color(acc.darkened(0.28), alpha))
	ci.draw_circle(bp + Vector2( - r * 0.22, - r * 0.28), r * 0.5, Color(acc.lightened(0.35), 0.2 * alpha))
	var slow: = sim.get_status(u, &"slow")
	if slow:
		ci.draw_circle(bp, r * 0.84, Color(0.45, 0.7, 1.0, 0.18 * alpha))

	var since: = sim.time - u.last_damage_time
	if since < 0.12:
		ci.draw_circle(bp, r, Color(1, 1, 1, 0.55 * (1.0 - since / 0.12)))

	var fd: = u.facing if u.facing.length_squared() > 0.01 else Vector2.RIGHT
	ci.draw_colored_polygon(PackedVector2Array([bp + fd * (r + 8.0), bp + fd.rotated(0.42) * (r + 2.0), bp + fd.rotated(-0.42) * (r + 2.0)]), Color(tc.lightened(0.2), alpha))

	_glyph(ci, bp, u.def.glyph, Color(1, 1, 1, alpha), int(r * 1.05))

	var sh: = sim.shield_amount(u)
	if sh > 1.0:
		var k: = clampf(sh / maxf(1.0, sim.max_hp(u)) * 3.0, 0.2, 1.0)
		ci.draw_arc(bp, r + 6.0, 0, TAU, 40, Color(0.9, 0.95, 1.2, 0.55 * k * alpha), 2.0, true)
		ci.draw_circle(bp, r + 6.0, Color(0.8, 0.9, 1.0, 0.06 * k * alpha))
	if sim.has_status(u, &"invulnerable"):
		ci.draw_arc(bp, r + 9.0, anim * 2.0, anim * 2.0 + TAU * 0.8, 36, Color(1.6, 1.3, 0.5, 0.9), 2.5, true)
	if controlled:
		for k2 in 3:
			var st: = anim * 3.0 + k2 * TAU / 3.0
			ci.draw_arc(bp, r + 10.0, st, st + 1.2, 12, Color(0.8, 0.5, 1.4, 0.9), 2.5, true)

	var act: = u.action
	if act and act.kind == "ability" and act.ability and act.windup:
		var tot: = maxf(0.01, act.resolve_at - act.started_at)
		var pr: = clampf((sim.time - act.started_at) / tot, 0.0, 1.0)
		var cc: = VfxStyle.color_for(act.ability)
		ci.draw_arc(bp, r + 5.5, - PI * 0.5, - PI * 0.5 + TAU * pr, 40, VfxStyle.hdr(cc, 1.5), 3.0, true)

		if quality >= 1:
			Motifs.signature(ci, u.def.id, bp, anim * 0.4, (r + 13.0) * (0.7 + 0.2 * pr), Color(VfxStyle.hdr(u.def.accent, 1.2), 0.25 + 0.4 * pr), anim)

	if sim.has_status(u, &"stun"):
		for k3 in 3:
			var ang: = anim * 5.0 + k3 * TAU / 3.0
			_glyph(ci, bp + Vector2(cos(ang) * r * 0.9, - r - 8.0 + sin(ang) * 3.0), "✦", Color(1.8, 1.6, 0.6), 11)
	if sim.has_status(u, &"root"):
		ci.draw_arc(p, r + 4.0, 0, TAU, 24, Color(0.55, 0.85, 0.4, 0.9), 3.0, true)
	if sim.has_status(u, &"sleep"):
		_text(ci, bp + Vector2(r * 0.8, - r - 6.0 - fmod(anim * 10.0, 8.0)), "z", Color("#98e8e1"), 13, 0.0)
	if sim.has_status(u, &"charm"):
		_glyph(ci, bp + Vector2(0, - r - 10.0), "♥", Color(1.6, 0.6, 0.9), 13)
	if sim.has_status(u, &"suppression"):
		ci.draw_rect(Rect2(bp - Vector2(r + 4, r + 4), Vector2(r + 4, r + 4) * 2.0), Color(1.4, 0.5, 0.8, 0.7), false, 2.0)

	KitVisuals.draw_over(self, ci, u, bp, r)


func _draw_entity(ci: CanvasItem, e: BUnit) -> void :
	var p: = upos(e)
	var r: = sim.radius(e)
	var tc: = UITheme.team_color(e.team)
	var acc: = e.def.accent
	var own: = sim.u_at(e.owner_idx)
	var oc: = own.def.accent if own else acc
	match e.kind:
		"bed":

			var rect: = Rect2(p - Vector2(25, 18), Vector2(50, 36))
			_rounded(ci, Rect2(rect.position + Vector2(2, 3), rect.size), 7.0, Color(0, 0, 0, 0.35))
			_rounded(ci, rect, 7.0, Color("#231927"))
			_rounded_line(ci, rect, 7.0, tc, 2.0)
			_rounded(ci, Rect2(p + Vector2(-20, -13), Vector2(15, 10)), 3.0, Color("#f1afd1"))
			_rounded(ci, Rect2(p + Vector2(5, -13), Vector2(15, 10)), 3.0, Color("#f1afd1"))
			ci.draw_line(p + Vector2(-20, 1), p + Vector2(20, 1), Color("#d888b2", 0.65), 2.0, true)
			ci.draw_line(p + Vector2(-25, -18), p + Vector2(-25, 17), Color(1.6, 1.3, 1.45, 0.8), 2.0, true)
			ci.draw_line(p + Vector2(25, -18), p + Vector2(25, 17), Color(1.6, 1.3, 1.45, 0.8), 2.0, true)
			var bv: Dictionary = e.ks.get("bed_visual", {})
			var prs: Array = bv.get("pairs", [])
			for i in prs.size():
				var pr: Dictionary = prs[i]
				var y: = p.y + 22.0 + i * 5.0
				ci.draw_line(Vector2(p.x - 22, y), Vector2(p.x + 22, y), Color("#3b2835"), 3.0)
				ci.draw_line(Vector2(p.x - 22, y), Vector2(p.x - 22 + 44.0 * clampf(float(pr.progress), 0.0, 1.0), y), Color("#8bf0b9") if bool(pr.done) else Color("#ffafd0"), 3.0)
			var label: = "짝 체류 대기"
			if not prs.is_empty():
				var best: = 0.0
				var all_done: = true
				for pr2 in prs:
					if not bool((pr2 as Dictionary).done):
						all_done = false
						best = maxf(best, float((pr2 as Dictionary).progress))
				label = "짝 회복 완료" if all_done else "%.1f / 10초" % (best * 10.0)
			var ly: = p.y + 20.0 + prs.size() * 5.0 + _below(18.0, 10.0, PX_SUB)
			_text(ci, Vector2(p.x, ly), label, Color("#f4bad8"), 10)
			if int(bv.get("odd", -1)) >= 0:
				var step: = 13.0 if not hud_readable else maxf(13.0, (_px(9.0, PX_SUB) + 3.0) * _inv)
				_text(ci, Vector2(p.x, ly + step), "미배정 1명", Color("#ebc179"), 9)
		"snake":

			var f: = e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT
			var body: = PackedVector2Array()
			for i2 in 9:
				var lx: = - r * 1.7 + i2 * r * 0.28
				body.append(p + Vector2(lx, sin(i2 * 0.65 + anim * 6.0) * r * 0.22).rotated(f.angle()))
			ci.draw_polyline(body, Color("#8f2a3f"), r * 0.7, true)
			ci.draw_polyline(body, VfxStyle.hdr(Color("#ed6e8f"), 1.2), r * 0.45, true)
			var head: = p + Vector2(r * 0.6, 0).rotated(f.angle())
			ci.draw_circle(head, r * 0.5, Color("#ffd8de"))
			ci.draw_circle(head + Vector2(r * 0.2, - r * 0.15).rotated(f.angle()), 1.3, Motifs.INK)
			ci.draw_arc(p, r + 2.0, 0, TAU, 20, Color(tc, 0.7), 1.2, true)
		"brood", "parasite":

			var f2: = e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT
			var wig: = sin(anim * 9.0 + e.idx) * 0.15
			Motifs.draw(ci, "parasite" if e.kind == "parasite" else "larva", p, f2.angle() + wig, r * (0.62 if e.kind == "parasite" else 0.75), Color("#c792ef"), Color("#f1ddff"), anim)
			ci.draw_arc(p, r + 1.5, 0, TAU, 20, Color(tc, 0.75), 1.2, true)
		"turret":
			var rect2: = Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
			ci.draw_rect(Rect2(rect2.position + Vector2(2, 3), rect2.size), Color(0, 0, 0, 0.35))
			ci.draw_rect(rect2, acc.darkened(0.55))
			ci.draw_rect(rect2, tc, false, 2.0)
			Motifs.draw(ci, "gear", p, 0.0, r * 0.9, Color(oc, 0.9), oc.lightened(0.4), anim)
			var fdir: = e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT
			for i3 in e.level:
				var off: = (i3 - (e.level - 1) * 0.5) * 5.0
				var a0: = p + fdir.orthogonal() * off
				ci.draw_line(a0, a0 + fdir * (r + 6.0 + e.level * 3.0), Color("#d0f1ff"), 3.0, true)
			_text(ci, p + Vector2(0, r + _below(16.0, 11.0, PX_SUB)), ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(e.level - 1, 0, 2)], Color(oc.lightened(0.3), 0.95), 11)
			if e.idx == selected and e.ent_range > 0.0:
				ci.draw_arc(p, e.ent_range, 0, TAU, 64, Color(oc, 0.25), 1.0, true)
		"tree":
			ci.draw_arc(p, 125.0, 0, TAU, 72, Color(oc, 0.12), 1.0, true)
			ci.draw_circle(p + Vector2(2, 4), r, Color(0, 0, 0, 0.3))
			for i4 in 5:
				var lp: = p + Vector2((i4 - 2) * 9.0, -12.0 - absf(i4 - 2) * -3.0)
				Motifs.draw(ci, "leaf", lp, - PI * 0.5 + (i4 - 2) * 0.35, 6.0, Color(oc, 0.8), oc.lightened(0.4), anim)
			Motifs.signature(ci, "world_tree", p, 0.0, r * 0.95, VfxStyle.hdr(oc, 1.2), anim)
			ci.draw_arc(p, r + 1.5, 0, TAU, 24, Color(tc, 0.8), 1.5, true)
		"flower":
			for i5 in 5:
				var a5: = TAU * i5 / 5.0 + anim * 0.3
				var pp: = p + Vector2.from_angle(a5) * r * 0.7
				ci.draw_set_transform(pp, a5, Vector2(1.0, 0.6))
				ci.draw_circle(Vector2.ZERO, r * 0.6, Color(1.0, 0.7, 0.85, 0.9))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			ci.draw_circle(p, r * 0.35, Color("#fff0c6"))
			ci.draw_arc(p, r + 3.0, 0, TAU, 20, Color(tc, 0.6), 1.2, true)
		# V2 entity kinds.
		"cerberus":
			_draw_cerberus(ci, e, p, r, tc, oc)
		"shade":
			_draw_shade(ci, e, p, r, tc)
		"fuel_tank":
			_draw_fuel_tank(ci, e, p, r, tc, own)
		"chariot":
			_draw_chariot(ci, e, p, r, tc, oc)
		_:
			if e.structure:
				var rect3: = Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
				ci.draw_rect(rect3, acc.darkened(0.5))
				ci.draw_rect(rect3, tc, false, 2.0)
			else:
				ci.draw_circle(p, r + 1.5, tc)
				ci.draw_circle(p, r, acc.darkened(0.4))
			_glyph(ci, p, e.def.glyph, Color(1, 1, 1, 0.92), int(maxf(10.0, r * 1.15)))
	var since: = sim.time - e.last_damage_time
	if since < 0.1:
		ci.draw_circle(p, r, Color(1, 1, 1, 0.5))


# ------------------------------------------------------------------ V2 entities

# Hades P2: the three-headed hound (top view, facing its heading), team ring.
func _draw_cerberus(ci: CanvasItem, e: BUnit, p: Vector2, r: float, tc: Color, oc: Color) -> void :
	var f: = e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT
	var gait: = sin(anim * 15.0 + e.idx) if e.vel.length_squared() > 25.0 else 0.0
	var bite: = clampf(1.0 - (sim.time - (e.next_attack - e.interval)) / 0.22, 0.0, 1.0)
	var fur: = Color("#3d3168")
	var fur_lo: = Color("#5d4f9c")
	var rim: = oc.lightened(0.35)
	var eye: = Color(2.2, 0.45, 0.3)
	ci.draw_set_transform(p + Vector2(2, r * 0.55), 0.0, Vector2(1.0, 0.42))
	ci.draw_circle(Vector2.ZERO, r * 1.25, Color(0, 0, 0, 0.32))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(p, r + 3.0, Color(tc, 0.18))
	ci.draw_arc(p, r + 3.0, 0, TAU, 28, Color(tc, 0.95), 1.8, true)
	var xf: = Transform2D(f.angle(), p)
	ci.draw_set_transform_matrix(xf)
	for lx: float in [-0.62, 0.15]:
		for sg: float in [-1.0, 1.0]:
			var sw: = gait * (1.0 if (lx > 0.0) == (sg > 0.0) else -1.0) * r * 0.22
			ci.draw_line(Vector2(lx * r, sg * r * 0.3), Vector2(lx * r + sw, sg * r * 0.7), fur_lo, 3.2, true)
	ci.draw_polyline(Motifs.quad(Vector2( - r * 0.8, 0), Vector2( - r * 1.2, sin(anim * 8.0 + e.idx) * r * 0.35), Vector2( - r * 1.42, - r * 0.12), 6), rim, 2.2, true)
	ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.62), 0.0, Vector2( - r * 0.22, 0)))
	ci.draw_circle(Vector2.ZERO, r * 0.82, fur)
	ci.draw_arc(Vector2.ZERO, r * 0.82, 0, TAU, 20, rim, 2.0, true)
	ci.draw_set_transform_matrix(xf)
	# Spiked collar.
	ci.draw_arc(Vector2(r * 0.12, 0), r * 0.4, -1.35, 1.35, 10, Color(1.7, 0.35, 0.4, 0.95), 2.4, true)
	# Necks first, then the outer heads and the middle one on top.
	for i in 3:
		var hn: = Vector2.from_angle((i - 1) * 0.86) * r * (0.74 + bite * (0.28 if i == 1 else 0.18))
		ci.draw_line(Vector2(r * 0.12, 0), hn, fur, r * 0.3, true)
	for i: int in [0, 2, 1]:
		var hd: = Vector2.from_angle((i - 1) * 0.86)
		var hp: = hd * r * (0.74 + bite * (0.28 if i == 1 else 0.18))
		var hs: = hd.orthogonal()
		ci.draw_circle(hp, r * 0.33 + 1.3, Color(0.05, 0.03, 0.09))
		ci.draw_circle(hp, r * 0.33, fur)
		ci.draw_arc(hp, r * 0.33, 0, TAU, 14, rim, 1.4, true)
		ci.draw_line(hp + hd * r * 0.12, hp + hd * r * 0.5, fur_lo, r * 0.2, true)
		ci.draw_circle(hp + hd * r * 0.52, r * 0.07, Color(0.06, 0.04, 0.1))
		for sg2: float in [-1.0, 1.0]:
			var eb: = hp - hd * r * 0.14 + hs * sg2 * r * 0.2
			ci.draw_colored_polygon(PackedVector2Array([eb - hs * sg2 * r * 0.1, eb - hd * r * 0.34 + hs * sg2 * r * 0.16, eb + hd * r * 0.1]), rim)
			ci.draw_circle(hp + hd * r * 0.1 + hs * sg2 * r * 0.13, 1.2, eye)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if quality >= 1 and FxSystem.soft_tex:
		var gq: = p + f * r * 0.75
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(gq - Vector2(10, 10), Vector2(20, 20)), false, Color(1.0, 0.25, 0.2, 0.16 + 0.32 * bite))


# Hades S1: a translucent shade hovering over a dashed team ring; fades in and out.
func _draw_shade(ci: CanvasItem, e: BUnit, p: Vector2, r: float, tc: Color) -> void :
	var fade: = clampf((e.end_time - sim.time) / 0.8, 0.0, 1.0) * clampf((sim.time - e.spawn_time) / 0.35, 0.15, 1.0)
	var q: = p + Vector2(0, sin(anim * 3.2 + e.idx * 1.7) * 2.0 - r * 0.25)
	var ghost: = Color(0.74, 0.68, 1.0)
	if quality >= 1 and FxSystem.soft_tex:
		var gr: = r * 2.4
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(q - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(0.5, 0.42, 1.0, 0.24 * fade))
	ci.draw_set_transform(p + Vector2(0, r * 0.6), 0.0, Vector2(1.0, 0.45))
	ci.draw_circle(Vector2.ZERO, r * 0.9, Color(0.05, 0.02, 0.12, 0.35 * fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_dashed_circle(ci, p, r + 2.0, Color(tc, 0.75 * fade), 1.3, 10)
	var pts: = PackedVector2Array()
	for i in 9:
		pts.append(q + Vector2.from_angle(PI + PI * i / 8.0) * r * 0.8)
	for i in 7:
		var x: = r * 0.8 - r * 1.6 * i / 6.0
		pts.append(q + Vector2(x, r * 0.62 + r * 0.3 * (0.5 + 0.5 * sin(i * PI + anim * 7.0 + e.idx))))
	ci.draw_colored_polygon(pts, Color(ghost, 0.5 * fade))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(VfxStyle.hdr(ghost, 1.2), 0.85 * fade), 1.2, true)
	var eye: = Color(0.06, 0.03, 0.14, 0.95 * fade)
	ci.draw_circle(q + Vector2( - r * 0.3, - r * 0.12), r * 0.16, eye)
	ci.draw_circle(q + Vector2(r * 0.3, - r * 0.12), r * 0.16, eye)
	ci.draw_circle(q + Vector2(0, r * 0.25), r * 0.11, eye)


# War machine passive: the fuel drum on his back (team outline, own-side fuel gauge,
# smoke when it is close to bursting). The HP bar is the generic entity bar.
func _draw_fuel_tank(ci: CanvasItem, e: BUnit, p: Vector2, r: float, tc: Color, own: BUnit) -> void :
	var f: = e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT
	var hl: = r * 1.25
	var ht: = r * 0.7
	var xf: = Transform2D(f.angle(), p)
	ci.draw_set_transform_matrix(Transform2D(f.angle(), p + Vector2(1.5, 2.5)))
	_rounded(ci, Rect2(- ht, - hl, ht * 2.0, hl * 2.0), ht * 0.9, Color(0, 0, 0, 0.35))
	ci.draw_set_transform_matrix(xf)
	_rounded(ci, Rect2(- ht - 1.8, - hl - 1.8, ht * 2.0 + 3.6, hl * 2.0 + 3.6), ht + 1.0, tc)
	_rounded(ci, Rect2(- ht, - hl, ht * 2.0, hl * 2.0), ht * 0.9, Color("#3b332d"))
	_rounded(ci, Rect2(- ht * 0.6, - hl * 0.9, ht * 0.75, hl * 1.8), ht * 0.35, Color("#6e5a47"))
	if own and KitVisuals.private_ok(self, own):
		var fr: = clampf(float(own.resources.get("fuel", 0.0)) / 10.0, 0.0, 1.0)
		var win: = Rect2(ht * 0.05, - hl * 0.72, ht * 0.5, hl * 1.44)
		ci.draw_rect(win, Color(0.05, 0.04, 0.03, 0.95))
		if fr > 0.0:
			ci.draw_rect(Rect2(win.position.x, win.end.y - win.size.y * fr, win.size.x, win.size.y * fr), VfxStyle.hdr(Color("#ff8a3d"), 1.25))
	for by: float in [- hl * 0.5, hl * 0.5]:
		ci.draw_line(Vector2(- ht, by), Vector2(ht, by), Color("#1b1714"), 2.0, true)
	ci.draw_rect(Rect2(- ht * 0.75, - hl - 1.0, ht * 1.5, 2.5), Color("#ff8a3d"))
	ci.draw_rect(Rect2(- ht * 0.75, hl - 1.5, ht * 1.5, 2.5), Color("#ff8a3d"))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(- ht, -3.0), Vector2(- ht - 5.0, -2.2), Vector2(- ht - 5.0, 2.2), Vector2(- ht, 3.0)]), Color("#2a2420"))
	ci.draw_line(Vector2(ht, 0), Vector2(ht + 3.0, 0), Color("#8a7a6a"), 2.2, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hpr: = e.hp / maxf(1.0, sim.max_hp(e))
	if hpr < 0.4 and quality >= 1:
		var blink: = 0.5 + 0.5 * sin(anim * 12.0)
		ci.draw_arc(p, hl + 3.0, 0, TAU, 24, Color(1.8, 0.4, 0.2, 0.25 + 0.45 * blink), 1.6, true)
		for j in 3:
			var ph: = fmod(anim * 0.9 + j / 3.0, 1.0)
			ci.draw_circle(p - f * (ht + 4.0) + Vector2(sin(j * 2.1 + anim) * 3.0, - ph * 22.0), 2.5 + ph * 4.0, Color(0.3, 0.28, 0.27, 0.45 * (1.0 - ph)))


# Achilles S4: Xanthos and Balios pulling the bronze chariot (r 30), drawn above the
# heroes, with speed lines, wheel dust, a team pennant and the invulnerable ring.
func _draw_chariot(ci: CanvasItem, e: BUnit, p: Vector2, r: float, tc: Color, oc: Color) -> void :
	var spd: = e.vel.length()
	var f: = e.vel / spd if spd > 2.0 else (e.facing if e.facing.length_squared() > 0.01 else Vector2.RIGHT)
	var moving: = spd > 20.0
	var fade: = clampf((e.end_time - sim.time) / 0.4, 0.0, 1.0) * clampf((sim.time - e.spawn_time) / 0.25, 0.3, 1.0)
	var xf: = Transform2D(f.angle(), p)
	var sd: = f.orthogonal()
	if moving and quality >= 1:
		for i in 6:
			var off: = (i - 2.5) * r * 0.3
			var ph: = fmod(anim * 3.2 + i * 0.37, 1.0)
			var a0: = p - f * r * (0.95 + ph * 0.7) + sd * off
			ci.draw_line(a0, a0 - f * (16.0 + spd * 0.07), Color(1.0, 0.95, 0.82, 0.4 * (1.0 - ph) * fade), 1.6, true)
		for sg: float in [-1.0, 1.0]:
			for j in 3:
				var ph2: = fmod(anim * 2.4 + j / 3.0 + (0.5 if sg > 0.0 else 0.0), 1.0)
				ci.draw_circle(p - f * r * (0.6 + ph2 * 0.9) + sd * sg * r * 0.62, 3.0 + ph2 * 6.0, Color(0.72, 0.62, 0.48, 0.32 * (1.0 - ph2) * fade))
	ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.55), 0.0, Vector2(r * 0.1, r * 0.3)))
	ci.draw_circle(Vector2.ZERO, r * 1.25, Color(0, 0, 0, 0.3 * fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_dashed_circle(ci, p, r + 5.0, Color(1.8, 1.45, 0.6, 0.45 * fade), 1.4, 16)
	ci.draw_arc(p, r + 8.0, - PI * 0.5, - PI * 0.5 + TAU * clampf((e.end_time - sim.time) / 5.0, 0.0, 1.0), 48, Color(tc, 0.7 * fade), 2.0, true)
	ci.draw_set_transform_matrix(xf)
	var gal: = anim * 17.0 if moving else 0.0
	var bronze: = Color(VfxStyle.hdr(Color("#d9a24f"), 1.1), fade)
	ci.draw_line(Vector2( - r * 0.2, 0), Vector2(r * 0.42, 0), Color(0.35, 0.24, 0.12, fade), 3.0, true)
	ci.draw_line(Vector2(r * 0.42, - r * 0.5), Vector2(r * 0.42, r * 0.5), bronze, 2.6, true)
	for hi in 2:
		var sg2: = -1.0 if hi == 0 else 1.0
		var hc: = Color(Color("#d0923e"), fade) if hi == 0 else Color(Color("#e4ddd0"), fade)
		var dark: = Color(hc.darkened(0.55), fade)
		var bob: = sin(gal + hi * 1.4) * 1.3
		var hy: = sg2 * r * 0.37
		var hx: = r * 0.72 + bob
		for lg in 4:
			var lx: = hx + (-0.32 + 0.21 * lg) * r
			var sw: = sin(gal + lg * 1.7 + hi) * r * 0.12
			var out: = -1.0 if lg % 2 == 0 else 1.0
			ci.draw_line(Vector2(lx, hy + out * r * 0.12), Vector2(lx + sw, hy + out * r * 0.3), dark, 2.6, true)
		ci.draw_polyline(Motifs.quad(Vector2(hx - r * 0.4, hy), Vector2(hx - r * 0.56, hy + sin(gal * 0.5 + hi) * r * 0.1), Vector2(hx - r * 0.68, hy + sg2 * r * 0.04), 4), dark, 3.0, true)
		ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.5), 0.0, Vector2(hx, hy)))
		ci.draw_circle(Vector2.ZERO, r * 0.44, hc)
		ci.draw_arc(Vector2.ZERO, r * 0.44, 0, TAU, 20, dark, 2.2, true)
		ci.draw_set_transform_matrix(xf)
		ci.draw_line(Vector2(hx + r * 0.25, hy), Vector2(hx + r * 0.52, hy), hc, r * 0.2, true)
		ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.62), 0.0, Vector2(hx + r * 0.6, hy)))
		ci.draw_circle(Vector2.ZERO, r * 0.2, hc)
		ci.draw_arc(Vector2.ZERO, r * 0.2, 0, TAU, 14, dark, 1.6, true)
		ci.draw_set_transform_matrix(xf)
		ci.draw_line(Vector2(hx + r * 0.05, hy), Vector2(hx + r * 0.55, hy), dark, 2.0, true)
		for sg5: float in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(hx + r * 0.52, hy + sg5 * r * 0.06), Vector2(hx + r * 0.44, hy + sg5 * r * 0.16), Vector2(hx + r * 0.58, hy + sg5 * r * 0.1)]), dark)
		if hi == 1:
			for k in 5:
				ci.draw_circle(Vector2(hx - r * 0.28 + k * r * 0.13, hy + (k % 2 - 0.5) * r * 0.14), 1.4, Color(0.55, 0.5, 0.44, 0.9 * fade))
		ci.draw_line(Vector2(hx + r * 0.6, hy), Vector2( - r * 0.3, sg2 * r * 0.18), Color(0.25, 0.16, 0.08, 0.8 * fade), 1.0, true)
	for sg4: float in [-1.0, 1.0]:
		var wc: = Vector2( - r * 0.5, sg4 * r * 0.62)
		ci.draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(1.0, 0.36), 0.0, wc))
		ci.draw_circle(Vector2.ZERO, r * 0.3, Color(0.12, 0.08, 0.04, 0.85 * fade))
		ci.draw_arc(Vector2.ZERO, r * 0.3, 0, TAU, 20, bronze, 2.6, true)
		var spin: = - anim * 9.0 if moving else 0.0
		for k2 in 3:
			var sa: = spin + k2 * PI / 3.0
			ci.draw_line(Vector2.from_angle(sa) * r * 0.28, - Vector2.from_angle(sa) * r * 0.28, Color(bronze, 0.8 * fade), 1.4, true)
		ci.draw_set_transform_matrix(xf)
	ci.draw_line(Vector2( - r * 0.5, - r * 0.62), Vector2( - r * 0.5, r * 0.62), Color(0.3, 0.2, 0.1, fade), 2.4, true)
	var car: = PackedVector2Array()
	for k3 in 11:
		car.append(Vector2( - r * 0.5, 0) + Vector2.from_angle( - PI * 0.5 + PI * k3 / 10.0) * Vector2(r * 0.42, r * 0.46))
	car.append(Vector2( - r * 0.82, r * 0.46))
	car.append(Vector2( - r * 0.82, - r * 0.46))
	ci.draw_colored_polygon(car, Color(Color("#4a3418"), fade))
	car.append(car[0])
	ci.draw_polyline(car, bronze, 2.4, true)
	ci.draw_circle(Vector2( - r * 0.32, 0), r * 0.13, Color(Color("#2d200f"), fade))
	ci.draw_arc(Vector2( - r * 0.32, 0), r * 0.13, 0, TAU, 12, bronze, 1.4, true)
	var wave: = sin(anim * 9.0) * r * 0.06
	ci.draw_line(Vector2( - r * 0.78, - r * 0.4), Vector2( - r * 0.78, - r * 0.95), Color(0.3, 0.2, 0.1, fade), 1.6, true)
	ci.draw_colored_polygon(PackedVector2Array([Vector2( - r * 0.78, - r * 0.95), Vector2( - r * 1.18, - r * 0.86 + wave), Vector2( - r * 0.78, - r * 0.72)]), Color(tc, fade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if quality >= 1 and FxSystem.soft_tex:
		var gr: = r * 1.6
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(oc, 0.08 * fade))


func _rounded_pts(rect: Rect2, rad: float) -> PackedVector2Array:
	var pts: = PackedVector2Array()
	var cs: = [rect.position + Vector2(rect.size.x - rad, rad), rect.position + Vector2(rect.size.x - rad, rect.size.y - rad), rect.position + Vector2(rad, rect.size.y - rad), rect.position + Vector2(rad, rad)]
	for k in 4:
		var c: Vector2 = cs[k]
		for j in 5:
			pts.append(c + Vector2.from_angle( - PI * 0.5 + k * PI * 0.5 + j * PI * 0.125) * rad)
	return pts


func _rounded(ci: CanvasItem, rect: Rect2, rad: float, col: Color) -> void :
	ci.draw_colored_polygon(_rounded_pts(rect, rad), col)


func _rounded_line(ci: CanvasItem, rect: Rect2, rad: float, col: Color, w: float) -> void :
	var pts: = _rounded_pts(rect, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w, true)


## V2 battleground downed hero (DESIGN_V2 §3.1): lying body in team colours, a red bleed-out ring
## that runs down with the bleed window and a green revive ring while a teammate channels.
func _draw_downed(ci: CanvasItem, u: BUnit) -> void:
	var p: = upos(u)
	var r: = sim.radius(u)
	var d: Dictionary = br.downed.get(u.idx, {})
	var tc: = UITheme.team_color(u.team)
	var px: = 1.0 / maxf(0.01, view_scale)
	var pulse: = 0.5 + 0.5 * sin(anim * 6.0)
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.66))
	ci.draw_circle(Vector2.ZERO, r + 4.0, Color(0, 0, 0, 0.4))
	ci.draw_circle(Vector2.ZERO, r + 2.0, Color(tc, 0.55))
	ci.draw_circle(Vector2.ZERO, r, u.def.accent.darkened(0.7))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_glyph(ci, p, u.def.glyph, Color(1, 1, 1, 0.45), int(r * 0.95))
	var total: = maxf(0.1, float(d.get("bleed_total", 30.0)))
	var left: = clampf((float(d.get("bleed_at", sim.time)) - sim.time) / total, 0.0, 1.0)
	var lw: = maxf(3.0, 2.2 * px)
	ci.draw_arc(p, r + 9.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45), lw + 1.5 * px, true)
	ci.draw_arc(p, r + 9.0, -PI * 0.5, -PI * 0.5 + TAU * left, 40, Color(1.5, 0.32, 0.32, 0.6 + 0.35 * pulse), lw, true)
	var rv: = float(d.get("revive_progress", 0.0))
	if rv > 0.0:
		ci.draw_arc(p, r + 9.0 + lw + 2.0 * px, -PI * 0.5, -PI * 0.5 + TAU * rv, 40, VfxStyle.hdr(UITheme.GOOD, 1.3), lw, true)
	# Down marker above the body.
	# Small polygon in local space: triangulation fails at large world coordinates.
	var ms: = maxf(6.0, 5.0 * px)
	ci.draw_set_transform(p + Vector2(0, -r - 10.0 - ms - 2.0 * pulse), 0.0, Vector2.ONE)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -ms), Vector2(ms * 0.9, ms * 0.6), Vector2(-ms * 0.9, ms * 0.6)]), Color(1.4, 0.4, 0.4, 0.9))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Revive channel: a green tether to the downed teammate and the channel progress on the reviver.
func _draw_reviver(ci: CanvasItem, u: BUnit) -> void:
	var t: = sim.u_at(int(br.reviving.get(u.idx, -1)))
	if t == null or not t.alive:
		return
	var d: Dictionary = br.downed.get(t.idx, {})
	var px: = 1.0 / maxf(0.01, view_scale)
	var col: = Color(UITheme.GOOD, 0.75)
	_dashed(ci, upos(u), upos(t), col, maxf(1.5, 1.4 * px), maxf(6.0, 5.0 * px))
	ci.draw_arc(upos(u), sim.radius(u) + 6.0, -PI * 0.5, -PI * 0.5 + TAU * float(d.get("revive_progress", 0.0)), 36, VfxStyle.hdr(UITheme.GOOD, 1.3), maxf(2.5, 2.0 * px), true)


func _draw_corpse(ci: CanvasItem, u: BUnit) -> void :
	var dt: = sim.time - u.death_time
	if dt > 2.5 or u.death_time < 0.0:
		return
	if perspective >= 0 and u.team != perspective and not _pt_vis(u.pos):
		return
	var a: = 1.0 - dt / 2.5
	var r: = sim.radius(u)
	ci.draw_circle(u.pos, r, Color(0.2, 0.22, 0.26, 0.5 * a))
	_glyph(ci, u.pos, u.def.glyph, Color(1, 1, 1, 0.25 * a), int(r))
	ci.draw_arc(u.pos, r + 2.0, 0, TAU, 28, Color(UITheme.team_color(u.team), 0.35 * a), 1.5, true)






func _draw_projectiles() -> void :

	var ci: = proj_layer
	if quality <= 0 or FxSystem.soft_tex == null:
		return
	var a: = runner.alpha if runner else 1.0
	for p in sim.proj.list:
		if p.dead or not _pt_vis(p.pos, p.team):
			continue
		var pos: = p.prev_pos.lerp(p.pos, a)
		var rad: = maxf(3.0, p.radius)
		var gr: = rad * 2.0 + 7.0
		var pat: = VfxStyle.pattern_for(p.ability) if (p.ability and not p.basic) else p.pattern
		var k: = 0.14 if p.basic else 0.22
		if pat in ["explosiveOrb", "meteorZone", "cannonCone"]:
			k = 0.3 + 0.1 * sin(anim * 20.0)
		if p.portal_amplified:
			k += 0.15
		ci.draw_texture_rect(FxSystem.soft_tex, Rect2(pos - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(p.color, k))



func _proj_spec(p: ST.Projectile) -> Dictionary:
	if p.turret:
		return EventFx.spec("engineer:skill:1")
	if p.basic:
		var src: = sim.u_at(p.source_idx)
		return EventFx.spec(src.def.id + ":basic") if src and src.is_hero else {}
	if p.ability:
		return EventFx.spec(EventFx.ability_key(p.ability))
	return {}


func _proj_motif(p: ST.Projectile, sp: Dictionary) -> String:
	if p.turret or p.driver:
		return "bolt"
	if sp.is_empty():
		return "hex"
	if p.basic and str(sp.get("id", "")) == "pirate":
		return "bullet"
	if bool(sp.get("clarity", false)) or str(sp.get("motif", "")) == "":

		return "bolt" if str(sp.get("family", "")) == "bullet" else "hex"
	return str(sp.motif)



func _draw_projectiles_solid() -> void :
	var ci: = proj_solid_layer
	var a: = runner.alpha if runner else 1.0
	for p in sim.proj.list:
		if p.dead or not _pt_vis(p.pos, p.team):
			continue
		var pos: = p.prev_pos.lerp(p.pos, a)
		var r: = maxf(2.0, p.radius)
		var dir: = p.vel.normalized() if p.vel.length_squared() > 1.0 else Vector2.RIGHT
		var theta: = dir.angle()
		var sp: = _proj_spec(p)
		var co: Color = sp.get("color", p.color)
		var hi: Color = sp.get("bright", p.color.lightened(0.5))
		var m: = _proj_motif(p, sp)

		var trail: Array = trails.get(p.id, [])
		if quality >= 1 and trail.size() >= 2:
			var pts: Array = trail.slice(maxi(0, trail.size() - 6), trail.size() - 1)
			pts.append(pos)
			var n: = pts.size()
			for i in range(1, n):
				var p0: Vector2 = pts[i - 1]
				var p1: Vector2 = pts[i]
				if p0.distance_to(p1) > 110.0:
					continue
				var al: = float(i) / n * 0.43
				ci.draw_line(p0, p1, Color(co, al * 0.32), minf(9.0, r * 0.6 + 2.0), true)
				ci.draw_line(p0, p1, Color(co, al), 1.3, true)

		ci.draw_circle(pos, r, Color(EventFx.INK, 0.6))
		ci.draw_arc(pos, r, 0, TAU, 20, Color(EventFx.TEAM_TINT[clampi(p.team, 0, 1)], 0.8), 1.1, true)
		if m == "hook" or m == "grapple":
			var src: = sim.u_at(p.source_idx)
			if src and src.alive:
				ci.draw_line(upos(src), pos, Color(EventFx.INK, 0.7), 3.0, true)
				ci.draw_line(upos(src), pos, Color(co, 0.65), 1.0, true)
		Motifs.draw(ci, m, pos, theta, clampf(r, 4.0, 18.0), co, hi, anim)
		if p.reflected:
			var rc: = Color("#bbecff")
			ci.draw_arc(pos, r + 5.0, theta - 1.3, theta + 1.3, 12, Color(rc, 0.95), 1.6, true)
			var back: = pos - dir * (r + 4.0)
			ci.draw_line(back + dir.orthogonal() * 4.0, pos - dir * (r + 8.0), rc, 1.4, true)
			ci.draw_line(pos - dir * (r + 8.0), back - dir.orthogonal() * 4.0, rc, 1.4, true)
		if p.returning:
			ci.draw_arc(pos, r + 4.0, theta + 1.8, theta + 4.5, 12, Color(co, 0.6), 1.2, true)






func _draw_overlay() -> void :
	var ci: = overlay_layer
	var su: = sim.u_at(selected)
	if su and su.alive and _vis(su):
		var p: = upos(su)
		var r: = sim.radius(su) + 11.0
		var col: = UITheme.team_color(su.team)
		for k in 4:
			var st: = anim * 1.4 + k * TAU / 4.0
			ci.draw_arc(p, r, st, st + 0.9, 10, Color(col.lightened(0.3), 0.95), 2.0, true)
		if show_ai and KitVisuals.private_ok(self, su):
			_draw_intent(ci, su)
	if show_ai and perspective >= 0:
		_draw_beliefs(ci, perspective)


func _draw_intent(ci: CanvasItem, u: BUnit) -> void :
	var c: = u.command
	if c.is_empty():
		return
	var p: = upos(u)
	var col: = UITheme.team_color(u.team).lightened(0.35)
	var kind: = str(c.get("kind", ""))
	var tgt: = sim.u_at(int(c.get("target", -1)))
	var goal: Vector2 = c.get("goal", c.get("pos", p))
	if tgt and tgt.alive and (perspective < 0 or _vis(tgt)):
		goal = upos(tgt)
	if kind == "move":
		_dashed(ci, p, goal, Color(col, 0.6), 1.5, 8.0)
		ci.draw_arc(goal, 6.0, 0, TAU, 16, Color(col, 0.8), 1.5, true)
	else:
		ci.draw_line(p, goal, Color(col, 0.55), 1.5, true)
		ci.draw_circle(goal, 4.0, Color(col, 0.8))



func _draw_beliefs(ci: CanvasItem, team: int) -> void :
	var ctl = sim.controllers[team]
	if ctl == null or not ("intel" in ctl) or ctl.intel == null:
		return
	var intel: TeamIntel = ctl.intel
	for k in intel.enemies:
		var b: TeamIntel.EnemyBelief = intel.enemies[k]
		if b.dead or b.visible or b.controlled_by_us:
			continue
		var col: = UITheme.team_color(1 - team)
		if sim.deathmatch and sim.u_at(b.idx):
			col = UITheme.team_color(sim.u_at(b.idx).team)

		if quality >= 1:
			for pi in b.particles.size():
				var w: = b.weights[pi] if pi < b.weights.size() else 0.05
				ci.draw_circle(b.particles[pi], 1.6 + w * 10.0, Color(col, 0.25 + minf(0.5, w * 3.0)))
		var conf: = clampf(b.confidence, 0.05, 1.0)
		var r: = b.radius + 2.0
		_dashed_circle(ci, b.pos, r + b.spread * 0.35, Color(col, 0.25 + 0.4 * conf), 1.5, 18)
		ci.draw_circle(b.pos, r, Color(col.darkened(0.5), 0.25 * conf))
		_glyph(ci, b.pos, b.def.glyph, Color(1, 1, 1, 0.25 + 0.35 * conf), int(r))
		if not hud_readable or not _lod or b.idx == selected:
			_text(ci, b.pos + Vector2(0, - r - _above(8.0)), "? %d%% · %.0f초 전" % [int(conf * 100.0), sim.time - b.last_seen_t], Color(col.lightened(0.3), 0.8), 11)






var name_rects: Array = []
var _label_obst: Array = []
var _fx_obst: Array = []
var _label_side: Dictionary = {}
var _garden_fill: Dictionary = {}
const LABEL_LINE: = 13.0


func _draw_hud() -> void :
	var ci: = hud_layer
	name_rects.clear()
	_label_obst.clear()
	_fx_obst.clear()
	var rd: = hud_readable
	var inv: = _inv if rd else 1.0
	var cull: = br != null
	for e in sim.entities:
		if not e.alive or not _vis(e) or e.kind == "chariot":
			continue
		if cull and not _cull.has_point(e.pos):
			continue
		var p0: = upos(e)
		var r0: = sim.radius(e)
		var w0: = maxf(22.0, r0 * 2.2)
		var h0: = 3.0
		var y0: = p0.y - r0 - 8.0
		if rd:
			w0 = maxf(w0, 20.0 * inv)
			h0 = maxf(h0, 3.0 * inv)
			y0 = p0.y - r0 - maxf(5.0, 2.0 * inv) - h0
		var hr0: = clampf(e.hp / maxf(1.0, sim.max_hp(e)), 0.0, 1.0)
		ci.draw_rect(Rect2(p0.x - w0 * 0.5, y0, w0, h0), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(p0.x - w0 * 0.5, y0, w0 * hr0, h0), UITheme.team_color(e.team))
		_label_obst.append([Rect2(p0.x - maxf(r0, w0 * 0.5), y0, maxf(r0 * 2.0, w0), p0.y + r0 - y0), e.idx])
	var label_reqs: Array = []
	var hover_req: Variant = null
	for u in sim.heroes:
		if not u.alive or not _vis(u):
			continue
		if cull and not _cull.has_point(u.pos):
			continue
		var p: = upos(u)
		var r: = sim.radius(u)
		var lift: = _status_lift(u)
		var mx: = maxf(1.0, sim.max_hp(u))
		# V2 battleground: a downed hero has its own 300 HP pool (separate red bar).
		var downed: = cull and br.downed.has(u.idx)
		if downed:
			mx = BattlegroundMode.DOWNED_HP
		var sh: = sim.shield_amount(u)
		var tot: = maxf(mx, u.hp + sh)
		var sel: = u.idx == selected
		var hov: = rd and u.idx == hovered
		# HP bar: world-sized, but never smaller than HP_MIN_W x HP_MIN_H px on screen when readable.
		var w: = maxf(44.0, r * 2.8)
		var h: = 6.0
		var gap: = 11.0
		var bd: = 1.5
		if rd:
			w = maxf(w, HP_MIN_W * inv)
			h = maxf(h, HP_MIN_H * inv)
			gap = maxf(gap, 4.0 * inv)
			bd = maxf(bd, 1.0 * inv)
		var x: = p.x - w * 0.5
		var y: = p.y - r - gap - h - lift
		var tc: = UITheme.team_color(u.team)
		ci.draw_rect(Rect2(x - bd, y - bd, w + bd * 2.0, h + bd * 2.0), Color(0, 0, 0, 0.7))
		var chip: float = hp_chip.get(u.idx, u.hp)
		ci.draw_rect(Rect2(x, y, w * clampf(chip / tot, 0.0, 1.0), h), Color(1.0, 0.95, 0.85, 0.85))
		ci.draw_rect(Rect2(x, y, w * clampf(u.hp / tot, 0.0, 1.0), h), Color("#ff5a5a") if downed else tc)
		if sh > 0.5:
			ci.draw_rect(Rect2(x + w * clampf(u.hp / tot, 0.0, 1.0), y, w * clampf(sh / tot, 0.0, 1.0), h), Color(0.93, 0.96, 1.0, 0.95))
		var right: = 0.0
		if sim.deathmatch:
			var held: Array = sim.deathmatch.held(u)
			if rd:
				# Held items as rarity pips in a small tray right of the bar (keeps the head stack short).
				if not held.is_empty():
					var hs: = 3.0 * inv
					var pitch_i: = hs * 2.0 + 1.5 * inv
					var tx0: = x + w + bd + 1.0 * inv
					var tray_w: = pitch_i * held.size() + 1.5 * inv
					ci.draw_rect(Rect2(tx0, y + h * 0.5 - hs - bd, tray_w, (hs + bd) * 2.0), Color(0, 0, 0, 0.6))
					var ix3: = tx0 + 1.5 * inv + hs
					for held_id in held:
						var icol3: = ItemDefs.rarity_color(ItemDefs.rarity_of(str(held_id)))
						var q3: = Vector2(ix3, y + h * 0.5)
						ci.draw_colored_polygon(PackedVector2Array([q3 + Vector2(0, -hs), q3 + Vector2(hs, 0), q3 + Vector2(0, hs), q3 + Vector2(-hs, 0)]), icol3)
						ix3 += pitch_i
					right = tray_w + bd + 1.0 * inv
			else:
				var ix2: = p.x - (held.size() - 1) * 5.0
				for held_id in held:
					var icol: = ItemDefs.rarity_color(ItemDefs.rarity_of(str(held_id)))
					var q: = Vector2(ix2, y + h + 5.5)
					ci.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -3.5), q + Vector2(3.5, 0), q + Vector2(0, 3.5), q + Vector2(-3.5, 0)]), icol)
					ix2 += 10.0

		if quality >= 1 and not (rd and _lod and not sel):
			var step: = 250.0
			var v: = step
			while v < tot:
				var gx: = x + w * v / tot
				# Readable: -1 = hairline primitive, 1 px on screen at any zoom.
				ci.draw_line(Vector2(gx, y), Vector2(gx, y + h * 0.6), Color(0, 0, 0, 0.55), -1.0 if rd else 1.0)
				v += step

		var icons: Array = []
		var stacks: = {}
		for st in u.statuses:
			var nm: = String(st.type)
			if st.end <= sim.time or nm in ["dot", "downed"]:
				continue
			if not stacks.has(nm):
				icons.append(nm)
				stacks[nm] = 0
			stacks[nm] = maxi(int(stacks[nm]), st.stacks)
		var n_ic: = mini(6, icons.size())
		var ir: = 6.0
		var pitch: = 14.0
		var icy: = y - 7.0
		var gpx: = 0
		var spx: = 0
		if rd:
			if _lod and not sel and not hov:
				n_ic = mini(4, n_ic)
			ir = maxf(6.0, 7.0 * inv)
			pitch = maxf(14.0, 15.0 * inv)
			icy = y - bd - 1.0 * inv - ir
			gpx = _px(9.0, PX_ICON)
			spx = _px(8.0, PX_ICON)
		var ix: = p.x - (n_ic - 1) * pitch * 0.5
		for i in n_ic:
			var nm2: String = icons[i]
			var ic: Array = VfxStyle.status_icon(nm2)
			var icol: = Color(str(ic[1]))
			ci.draw_circle(Vector2(ix, icy), ir, Color(0, 0, 0, 0.65))
			if rd:
				_glyph_px(ci, Vector2(ix, icy), str(ic[0]), icol, gpx)
			else:
				_glyph(ci, Vector2(ix, icy), str(ic[0]), icol, 9)
			var sk: = int(stacks[nm2])
			if sk > 1:
				if not rd:
					_text(ci, Vector2(ix + 5.0, y - 1.0), str(sk), Color(icol.lightened(0.3), 0.95), 8)
				elif not _lod or sel or hov:
					_text_px(ci, Vector2(ix + ir * 0.9, icy + ir + 1.0 * inv), str(sk), Color(icol.lightened(0.3), 0.95), spx)
			ix += pitch
		var icon_h: = 0.0
		if n_ic > 0:
			icon_h = (ir * 2.0 + 1.0 * inv) if rd else 14.0
		var top: = y - bd - icon_h
		var hw: = maxf(w * 0.5, r) + bd
		_label_obst.append([Rect2(p.x - hw, top, hw * 2.0 + right, p.y + r - top), u.idx])
		if rd:
			_fx_obst.append(Rect2(p.x - hw, top, hw * 2.0 + right, y + h + bd - top))

		var lines: Array = []
		if show_names or sel:
			var nm3: String
			if rd and _lod and not sel and not hov and not _is_top(u.idx):
				nm3 = _compact_tag(u)
			else:
				nm3 = u.def.name
				if sim.eteam(u) != u.team:
					nm3 += " (조종됨)"
				if br != null:
					# Battleground: the hero's own kills (a squad's team total means little per hero).
					var hk: int = int((br.hstats.get(u.idx, {}) as Dictionary).get("kills", 0))
					if hk > 0:
						nm3 += "  %d킬" % hk
				elif sim.deathmatch:
					nm3 += "  %d킬" % sim.deathmatch.kills[u.team]
			var ncol: = Color(tc.lightened(0.45), 0.85)
			if rd:
				# Readable: opaque names; the selected hero's name is brighter still.
				ncol = Color(tc.lightened(0.72), 1.0) if sel else Color(tc.lightened(0.45), 0.95)
			lines.append([nm3, ncol, 11, true, PX_NAME])
		if downed:
			lines.append([BrStanding.downed_text(_downed_row(u)), Color("#ff8a8a"), 10, false, PX_SUB])
		elif not rd or not _lod or sel or hov:
			var lab: Array = KitVisuals.label_for(self, u)
			if not lab.is_empty():
				lines.append([str(lab[0]), lab[1] as Color, 10, false, PX_SUB])
		if show_ai and KitVisuals.private_ok(self, u) and sel and not u.command.is_empty():
			var purpose: = str(u.command.get("purpose", ""))
			if purpose != "":
				lines.append([purpose, Color(tc.lightened(0.35), 0.95), 12, false, PX_NAME])
		if not lines.is_empty():
			var req: = {"u": u, "p": p, "r": r, "top": top, "lines": lines}
			if sel:
				label_reqs.push_front(req)
			elif hov:
				hover_req = req
			else:
				label_reqs.append(req)
	if hover_req != null:
		# Hovered hero is placed right after the selected one so it wins label collisions.
		var at: = 1 if not label_reqs.is_empty() and (label_reqs[0].u as BUnit).idx == selected else 0
		label_reqs.insert(at, hover_req)

	for req in label_reqs:
		_place_labels(ci, req)


## True when the hero is among the top-3 killers (deathmatch, readable compact mode).
func _is_top(idx: int) -> bool:
	return idx >= 0 and (_top[0] == idx or _top[1] == idx or _top[2] == idx)


## Compact overview tag: player number in deathmatch, otherwise the first two letters of the name.
func _compact_tag(u: BUnit) -> String:
	if br != null:
		return br.team_label(u.team)
	if sim.deathmatch:
		return "P%d" % (u.team + 1)
	return u.def.name.substr(0, 2)




func _place_labels(ci: CanvasItem, req: Dictionary) -> void :
	var u: BUnit = req.u
	var p: Vector2 = req.p
	var r: float = req.r
	var lines: Array = req.lines
	var rd: = hud_readable
	var inv: = _inv if rd else 1.0
	var f: = DB.font_bold
	for attempt in 2:
		if lines.is_empty():
			return
		var n: = lines.size()
		if _line_w.size() < n:
			_line_w.resize(n)
			_line_px.resize(n)
		var bw: = 0.0
		var bh: = 0.0
		for i in n:
			var ln: Array = lines[i]
			var fs: = _px(float(ln[2]), float(ln[4])) if rd else int(ln[2])
			var lw: = f.get_string_size(str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_line_w[i] = lw
			_line_px[i] = fs
			bw = maxf(bw, lw * inv)
			bh += (fs + 3.0) * inv if rd else LABEL_LINE
		var pad: = 3.0 * inv
		var below: = Rect2(p.x - bw * 0.5 - pad, p.y + r + 11.0, bw + pad * 2.0, bh + 2.0 * inv)
		var above: = Rect2(p.x - bw * 0.5 - pad, float(req.top) - 4.0 * inv - bh - 2.0 * inv, bw + pad * 2.0, bh + 2.0 * inv)
		var sb: = _label_score(below, u.idx)
		var sa: = _label_score(above, u.idx)

		var prev: Array = _label_side.get(u.idx, [0, -9.0])
		var side: = int(prev[0])
		var since: = anim - float(prev[1])
		if side == 0 and sa < sb and since > 0.35:
			side = 1
		elif side == 1 and (sb < sa or sb == 0) and since > 0.6:
			side = 0
		if side != int(prev[0]):
			_label_side[u.idx] = [side, anim]
		var rect: = below if side == 0 else above
		var score: = sb if side == 0 else sa
		if score >= 100 and u.idx != selected:
			if attempt == 0 and bool(lines[0][3]):

				lines = lines.slice(1)
				continue
			return
		if score > 0:
			_rounded(ci, rect.grow(1.0 * inv), 4.0 * inv, Color(0.02, 0.035, 0.07, 0.72))
		name_rects.append(rect)
		if rd:
			_fx_obst.append(rect)
			# One transform for the whole block; lines are laid out in screen px.
			ci.draw_set_transform(Vector2(p.x, rect.position.y), 0.0, Vector2(inv, inv))
			var yy: = 1.0
			for i in n:
				var ln2: Array = lines[i]
				var px: = _line_px[i]
				yy += px
				var s: = str(ln2[0])
				var col: Color = ln2[1]
				var at: = Vector2(_line_w[i] * -0.5, yy)
				ci.draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0, 0, 0, 0.8 * col.a))
				ci.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
				yy += 3.0
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var yy2: = rect.position.y + 11.0
			for ln in lines:
				_text(ci, Vector2(p.x, yy2), str(ln[0]), ln[1] as Color, int(ln[2]))
				yy2 += LABEL_LINE
		return



func _label_score(rect: Rect2, own_idx: int) -> int:
	var s: = 0
	for rr in name_rects:
		if (rr as Rect2).intersects(rect):
			s += 100
	for ob in _label_obst:
		if int(ob[1]) != own_idx and (ob[0] as Rect2).intersects(rect):
			s += 1
	return s







func _ev_key(ev: Dictionary, src: BUnit) -> String:
	var ab = ev.get("ability")
	return EventFx.key_for(src, ab if ab is Defs.AbilityDef else null, str(ev.get("source_type", "")))


func _unit_col(i: int) -> Color:
	var u: = sim.u_at(i)
	return u.def.accent if u else Color.WHITE


func _handle_event(ev: Dictionary) -> void :
	var ty: = str(ev.get("type", ""))
	if ty == "HERO_RESPAWNED":
		var respawn_idx: int = int(ev.get("g", -1))
		death_t.erase(respawn_idx)
		hp_chip.erase(respawn_idx)
		trails.erase(respawn_idx)
		motion_trails.erase(respawn_idx)
	if not _ev_vis(ev):
		return
	var q: = quality
	match ty:
		"CONTROL_CAPTURED", "CONTROL_NEUTRALIZED":
			for point in sim.domination.points:
				if str(point.id) != str(ev.get("point_id", "")):
					continue
				var team: int = int(ev.get("team", -1))
				var col: Color = UITheme.team_color(team) if team >= 0 else UITheme.GOLD
				fx.ring(point.center, col, float(point.radius), float(point.radius) + 58.0, 0.75, 4.0)
				fx.banner(point.center + Vector2(0, -28), "%s · %s" % [str(point.label), "점령" if ty == "CONTROL_CAPTURED" else "중립화"], col, 24, 1.35)
				_sfx("capture", 0.4, 1.0 if ty == "CONTROL_CAPTURED" else 0.8)
		"HERO_RESPAWNED":
			var hero: BUnit = sim.u_at(int(ev.get("g", -1)))
			if hero:
				fx.ring(hero.pos, UITheme.team_color(hero.team), 8, 70, 0.6, 3)
				fx.text(hero.pos + Vector2(0, -44), "전장 복귀", Color.WHITE, 16, 1.1)
				_sfx("respawn", 0.25, 1.0)
		"DM_KILL", "DM_ITEM_PICKED", "DM_ITEM_DROPPED", "DM_ITEM_SKIPPED", "DM_ITEM_PROC", "DM_REVIVE", "DM_ITEM_SPAWNED":
			_deathmatch_event(ty, ev)
		"BR_DOWNED", "BR_REVIVED", "BR_REVIVE_START", "BR_REVIVE_CANCEL", "BR_TEAM_OUT", "BR_ZONE_ANNOUNCE", "BR_ZONE_SHRINK":
			_battleground_event(ty, ev)
		"HEAL_ZONE_USED":
			var healed: BUnit = sim.u_at(int(ev.get("g", -1)))
			if healed:
				fx.ring(healed.pos, UITheme.GOOD, 12, 84, 0.7, 3)
				fx.text(healed.pos + Vector2(0, -52), "회복 구역", UITheme.GOOD, 16, 1.2)
		"FX":
			_handle_fx(ev)
		"CAST_STARTED":
			var a = ev.get("ability")
			var su: = sim.u_at(int(ev.s))
			if a is Defs.AbilityDef and su and not a.virtual:
				var col: = VfxStyle.color_for(a)
				fx.glyph(su.pos + Vector2(0, - sim.radius(su) - 24.0), VfxStyle.glyph_for(a), VfxStyle.hdr(col, 1.3), 22.0 if VfxStyle.glyph_for(a).length() <= 1 else 16.0, 0.75)
				fx.ring(su.pos, VfxStyle.hdr(col, 1.4), sim.radius(su), sim.radius(su) + 16.0, 0.3, 2.0)
				if quality >= 1:

					ev_fx.sig(su.def.id, su.pos, sim.radius(su) + 10.0, su.def.accent, a.slot, maxf(0.28, a.cast_time + 0.18))
				_sfx("cast", 0.35, 0.9 + 0.05 * a.slot)
		"HEALTH_DAMAGED", "SHIELD_ABSORBED":
			var t: = sim.u_at(int(ev.g))
			if t == null:
				return
			var amt: = float(ev.get("amount", 0.0))
			var ab: = float(ev.get("absorbed", 0.0))
			var crit: = bool(ev.get("crit", false))
			var school: = str(ev.get("school", "physical"))
			var col2: = Color("#ffd9b0")
			if school == "magic":
				col2 = Color("#cbb6ff")
			elif school == "true":
				col2 = Color("#ffffff")
			if br != null and t.is_hero and amt >= 1.0:
				_note_heat(t.pos)
			if show_numbers and _numbers_ok() and t.is_hero and (amt >= 1.0 or ab >= 1.0):
				var s: = str(int(round(amt))) if amt >= 1.0 else "(%d)" % int(round(ab))
				if crit:
					s += "!"
				var size: = 14.0 + minf(12.0, amt / 22.0) + (5.0 if crit else 0.0)
				fx.text(t.pos + Vector2(0, - sim.radius(t) - 22.0), s, col2 if amt >= 1.0 else Color("#c9d6ea"), size, 0.85 if not crit else 1.05)
			if t.is_hero and amt > sim.max_hp(t) * 0.14:
				fx.add_shake(2.0 + amt / sim.max_hp(t) * 10.0)
			if amt > 0.0:
				var src: = sim.u_at(int(ev.s))
				var dir: = (t.pos - src.pos).normalized() if src else Vector2.UP
				fx.burst(t.pos, VfxStyle.hdr(col2, 1.2), 3 if not crit else 8, 60.0, 160.0, 2.0, 0.3, 4.0, 0.0, dir, 1.4, 1)

			if amt >= 1.0 or ab >= 1.0:
				var srcd: = sim.u_at(int(ev.s))
				var keyd: = _ev_key(ev, srcd)
				if keyd != "" and throttle("imp:%d:%s" % [t.idx, keyd], 0.12):
					var rt: = sim.radius(t)
					var fromd: = srcd.pos if srcd else t.pos - Vector2(1, 0)
					ev_fx.impact(keyd, t.pos, rt + 12.0, (t.pos - fromd).angle())
					if srcd and srcd.is_hero and quality >= 1:
						var abd = ev.get("ability")
						ev_fx.sig(srcd.def.id, t.pos, rt + 12.0, srcd.def.accent, (abd as Defs.AbilityDef).slot if abd is Defs.AbilityDef else 0, 0.58)
				if ty == "SHIELD_ABSORBED" and throttle("shh:%d" % t.idx, 0.3):
					ev_fx.shield(t.pos, sim.radius(t), true)
			if crit:
				_sfx("crit", 0.5, 1.0)
			elif amt > 0.0 and bool(ev.get("basic", false)):
				_sfx("hit", 0.22, randf_range(0.9, 1.15))
		"HEAL_APPLIED":
			var t2: = sim.u_at(int(ev.g))
			var amt2: = float(ev.get("amount", 0.0))
			if t2 and amt2 >= 6.0 and not bool(ev.get("silent", false)):
				if show_numbers and _numbers_ok():
					fx.text(t2.pos + Vector2(0, - sim.radius(t2) - 20.0), "+%d" % int(round(amt2)), Color("#7dffb0"), 14.0 + minf(8.0, amt2 / 30.0), 0.9)
				fx.burst(t2.pos, Color(0.5, 1.6, 0.8, 0.9), 6, 20.0, 60.0, 2.2, 0.8, 1.0, -60.0)
				if throttle("heal:%d" % t2.idx, 0.25):
					ev_fx.heal(t2.pos, sim.radius(t2))
				_sfx("heal", 0.3, 1.0)
		"SHIELD_APPLIED":
			var t3: = sim.u_at(int(ev.g))
			if t3 and not bool(ev.get("silent", false)):
				fx.ring(t3.pos, Color(1.3, 1.4, 1.6, 0.9), sim.radius(t3) + 2.0, sim.radius(t3) + 14.0, 0.35, 2.5, 0.25)
				ev_fx.shield(t3.pos, sim.radius(t3), false)
				_sfx("shield", 0.3, 1.0)
		"CC_APPLIED":
			var t4: = sim.u_at(int(ev.g))
			var st: = str(ev.get("status", ""))
			if t4 and (st in VfxStyle.HARD or st == "silence") and float(ev.get("duration", 0.0)) > 0.05:
				var ic: Array = VfxStyle.status_icon(st)
				fx.text(t4.pos + Vector2(0, - sim.radius(t4) - 40.0), DB.status_label(st), Color(str(ic[1])), 15.0, 1.0, 16.0, true, false)
				fx.ring(t4.pos, VfxStyle.hdr(Color(str(ic[1])), 1.4), sim.radius(t4), sim.radius(t4) + 22.0, 0.35, 3.0)
				ev_fx.status(_ev_key(ev, sim.u_at(int(ev.s))), t4.pos, sim.radius(t4), st)
				_sfx("cc", 0.4, 1.0)
		"DEATH", "EXECUTED":
			var t5: = sim.u_at(int(ev.g))
			if t5 == null:
				return
			var col5: = t5.def.accent
			if t5.is_hero:
				fx.flash(t5.pos, VfxStyle.hdr(col5, 1.8), 90.0, 0.35)
				fx.ring(t5.pos, VfxStyle.hdr(UITheme.team_color(t5.team), 1.5), 10.0, 120.0, 0.6, 5.0, 0.12)
				fx.burst(t5.pos, VfxStyle.hdr(col5, 1.6), 46, 80.0, 380.0, 3.2, 0.9, 2.6, 0.0, Vector2.ZERO, TAU, 2)
				fx.burst(t5.pos, Color(1.6, 1.6, 1.6), 18, 120.0, 420.0, 1.6, 0.5, 3.0, 0.0, Vector2.ZERO, TAU, 1)
				fx.glyph(t5.pos, t5.def.glyph, VfxStyle.hdr(col5, 1.5), 46.0, 1.1, false)
				ev_fx.death(t5.def.id + ":death", t5.pos, sim.radius(t5))
				fx.banner(t5.pos + Vector2(0, -58), "처형!" if ty == "EXECUTED" else "처치", Color("#ffe39a") if ty == "EXECUTED" else Color.WHITE, 22.0, 1.3)
				fx.add_shake(7.0)
				if hitstop_enabled and runner:
					runner.add_hitstop(0.09)
				var killer: = sim.u_at(int(ev.s))
				if sim.deathmatch == null:
					kill_feed.append({"t": sim.time, "killer": killer.idx if killer else -1, "victim": t5.idx, "execute": ty == "EXECUTED"})
				_sfx("death", 0.7, 1.0)
			else:
				fx.burst(t5.pos, VfxStyle.hdr(col5, 1.3), 12, 40.0, 160.0, 2.2, 0.5, 3.0)
		"BLINKED":
			var su2: = sim.u_at(int(ev.s))
			var from: Vector2 = ev.get("from", Vector2.ZERO)
			var to: Vector2 = ev.get("to", Vector2.ZERO)
			if su2:
				fx.afterimage(from, sim.radius(su2), su2.def.accent, 0.45)
				fx.streak(from, to, VfxStyle.hdr(su2.def.accent, 1.3), 12.0, 0.3)
				fx.flash(to, VfxStyle.hdr(su2.def.accent, 1.5), 40.0, 0.2)
				ev_fx.blink(_ev_key(ev, su2), from, to, sim.radius(su2))
				_sfx("blink", 0.4, 1.0)
		"DASH_STARTED":
			var su3: = sim.u_at(int(ev.g))
			if su3:
				var ab2 = ev.get("ability")
				var colD: Color = VfxStyle.color_for(ab2) if ab2 is Defs.AbilityDef else su3.def.accent
				fx.afterimage(ev.get("from", su3.pos), sim.radius(su3), colD, 0.35)
				fx.streak(ev.get("from", su3.pos), ev.get("to", su3.pos), VfxStyle.hdr(colD, 1.2), 10.0, 0.35)
				ev_fx.move(_ev_key(ev, sim.u_at(int(ev.s))), ev.get("from", su3.pos), su3.idx)
				_sfx("dash", 0.35, 1.0)
		"SUMMON_CREATED":
			var pos: Vector2 = ev.get("pos", Vector2.ZERO)
			var su4: = sim.u_at(int(ev.s))
			var colS: = su4.def.accent if su4 else Color.WHITE
			fx.burst(pos, VfxStyle.hdr(colS, 1.3), 10, 30.0, 110.0, 2.0, 0.5, 3.0)
			fx.ring(pos, VfxStyle.hdr(colS, 1.2), 4.0, 26.0, 0.35, 2.0)
		"PROJECTILE_REFLECTED", "PROJECTILE_BLOCKED":
			var pos2: Vector2 = ev.get("pos", Vector2.ZERO)
			fx.flash(pos2, Color(1.4, 1.6, 2.0), 30.0, 0.2)
			fx.text(pos2 + Vector2(0, -16), "반사" if ty == "PROJECTILE_REFLECTED" else "차단", Color("#bfe9ff"), 13.0, 0.7, 20.0, true, false)
		"POSITIONS_SWAPPED":
			var a3: = sim.u_at(int(ev.s))
			var b3: = sim.u_at(int(ev.g))
			if a3 and b3:
				fx.beam(a3.pos, b3.pos, Color(1.5, 0.8, 1.4), 4.0, 0.35)
				ev_fx.blink("joker:skill:2" if a3.def.id == "joker" else a3.def.id + ":basic", ev.get("from", b3.pos), a3.pos, sim.radius(a3))
				fx.flash(a3.pos, Color(1.5, 0.8, 1.4), 40.0)
				fx.flash(b3.pos, Color(1.5, 0.8, 1.4), 40.0)
		"SKILLS_SEALED":
			var t6: = sim.u_at(int(ev.g))
			if t6:
				fx.banner(t6.pos + Vector2(0, -50), "스킬 봉인", Color("#ff9ad0"), 18.0, 1.4)
		"STAT_STOLEN", "STATS_SWAPPED":
			var t7: = sim.u_at(int(ev.g))
			if t7:
				fx.text(t7.pos + Vector2(0, -44), "약탈" if ty == "STAT_STOLEN" else "능력치 뒤집기", Color("#f0c65c"), 14.0, 1.0, 18.0, true, false)
		"REVEAL":

			var su5: = sim.u_at(int(ev.s))
			var tg5: = sim.u_at(int(ev.g))
			if perspective >= 0 and su5 and sim.eteam(su5) != perspective:
				return
			if su5 and su5.alive and throttle("reveal:%d" % su5.idx, 3.0):
				fx.ring(su5.pos, Color(1.2, 0.8, 1.6), 10.0, 70.0, 0.6, 1.6)
				var who5: = tg5.def.name if tg5 and tg5.is_hero else ""
				var share_name: = "신경망" if su5.def.id == "hive_mind" else "정보 공유"
				fx.text(su5.pos + Vector2(0, - sim.radius(su5) - 34.0), "%s · %s 쿨다운" % [share_name, who5], Color("#d6b3ff"), 12.0, 1.1, 14.0, false, false)
		"ENV_HIT":
			var t8: = sim.u_at(int(ev.g))
			if t8:
				var colE: = Color(str(ev.get("color", "#f5b36d")))
				fx.burst(t8.pos, VfxStyle.hdr(colE, 1.4), 6, 40.0, 140.0, 2.0, 0.4, 3.0)
		"ENV_GATE":
			var gp: Vector2 = ev.get("pos", Vector2.ZERO)
			var opened: bool = bool(ev.get("open", false))
			var gc: Color = ArenaPainter.GATE_OPEN if opened else ArenaPainter.GATE_WARN
			fx.ring(gp, VfxStyle.hdr(gc, 1.2), 10.0, 70.0, 0.5, 2.5)
			if throttle("gate:%s" % str(ev.get("group", "")), 0.5):
				fx.text(gp + Vector2(0, -34), "성문 열림" if opened else "성문 닫힘", gc, 14.0, 1.1, 14.0, true, false)
		"ENV_PUSHED":
			var pu: = sim.u_at(int(ev.get("g", -1)))
			if pu:
				fx.text(pu.pos + Vector2(0, - sim.radius(pu) - 30.0), "성문에 밀려남", ArenaPainter.GATE_WARN, 12.0, 0.9, 14.0, false, false)
		"ENV_ARTILLERY":
			var ap: Vector2 = ev.get("pos", Vector2.ZERO)
			fx.text(ap + Vector2(0, -20), "포격 예고", ArenaPainter.ART_COL, 15.0, 1.2, 18.0, true, false)
			_sfx("cc", 0.18, 0.7)
		"ENV_RING":
			var rp: Vector2 = ev.get("pos", Vector2.ZERO)
			var rh: Dictionary = arena.env_def(str(ev.get("hazard", "")))
			var rc: Color = Color(str(rh.get("color", "#d98bff")))
			var final_phase: bool = str(ev.get("phase", "")) == "final"
			fx.banner(rp + Vector2(0, -40), "최종 결계 · 바깥은 계속 피해" if final_phase else "결계 수축 시작", rc.lightened(0.3), 22.0, 2.0)
			fx.ring(rp, VfxStyle.hdr(rc, 1.3), float(ev.get("radius", 300.0)) * 0.9, float(ev.get("radius", 300.0)), 0.8, 5.0)
			_sfx("cage", 0.3, 0.8)
		"MISS":
			if ev.get("ability") is Defs.AbilityDef and q >= 1:
				var su6: = sim.u_at(int(ev.s))
				if su6:
					fx.text(su6.pos + Vector2(0, -40), "빗나감", Color("#9aabc6"), 12.0, 0.7, 14.0, false, false)
		"PROJECTILE_CREATED":
			if not bool(ev.get("basic", false)):
				_sfx("shoot", 0.22, randf_range(0.95, 1.1))
		"GARDEN_CLOSED":
			var su7: = sim.u_at(int(ev.s))
			if su7:
				fx.banner(su7.pos + Vector2(0, -48), "재생 영역 완성", Color("#9ff0c5"), 16.0, 1.2)
		"CHAMBER_STARTED":
			var pos3: Vector2 = ev.get("pos", Vector2.ZERO)
			fx.flash(pos3, Color(1.6, 0.6, 1.2), 120.0, 0.4)
			fx.add_shake(4.0)
		"CONTEMPLATION":
			var speaker: = sim.u_at(int(ev.get("s", -1)))
			if speaker and bool(ev.get("active", false)) and throttle("contemplate:%d" % speaker.idx, 1.0):
				fx.ring(speaker.pos, Color("#ecd998"), sim.radius(speaker), sim.radius(speaker) + 18.0, 0.5, 2.0)
				fx.text(speaker.pos + Vector2(0, -44), "관조 · CC 면역", Color("#ecd998"), 12.0, 0.85, 12.0, false, false)
		"FAKE_NEWS":
			var speaker2: = sim.u_at(int(ev.get("s", -1)))
			if speaker2:
				var news_col: = Color("#d6b979")
				fx.ring(speaker2.pos, news_col, 24.0, 140.0, 0.7, 1.6, 0.1)
				for page_i in 5:
					fx.motif_fly(speaker2.pos, Vector2.from_angle(page_i * TAU / 5.0) * 115.0, "dispatch", news_col, 7.0, 0.75)
				if perspective < 0 or sim.eteam(speaker2) == perspective:
					fx.text(speaker2.pos + Vector2(0, -48), "가짜 뉴스 · 불신 %d/10" % int(ev.get("distrust", 0)), news_col, 12.0, 1.1, 14.0, false, false)
				_sfx("broadcast", 0.25, 1.0)
		"DIVERSION":
			var decoy: = sim.u_at(int(ev.get("ally", ev.get("g", -1))))
			if decoy and _vis(decoy):
				fx.banner(decoy.pos + Vector2(0, -50), "화제의 중심", Color("#e8a06f"), 15.0, 1.1)
				fx.ring(decoy.pos, Color("#e8a06f"), sim.radius(decoy), 70.0, 0.7, 2.2)
				_sfx("cc", 0.3, 0.85)
		"PROPAGANDA":
			var speaker3: = sim.u_at(int(ev.get("s", -1)))
			if speaker3:
				fx.ring(speaker3.pos, Color("#ecd998"), 24.0, 160.0, 0.8, 2.0, 0.08)
				fx.text(speaker3.pos + Vector2(0, -46), "선전 · 아군 강화", Color("#ecd998"), 13.0, 1.0, 14.0, false, false)
		"PRISON_CREATED":
			var cage_center: Vector2 = ev.get("pos", ev.get("center", Vector2.ZERO))
			fx.ring(cage_center, Color("#e789ba"), 3.0, float(ev.get("radius", 64.0)), 0.45, 4.0)
			fx.banner(cage_center + Vector2(0, -90), "감금", Color("#f5b0d4"), 16.0, 1.0)
			_sfx("cage", 0.35, 1.0)
		"INFO_REVEAL", "INFO_BLOCKED":
			if perspective >= 0 and int(ev.get("team", -1)) != perspective:
				return
			var interrogator: = sim.u_at(int(ev.get("s", -1)))
			if interrogator and _vis(interrogator):
				var field: String = {"position": "위치", "pos": "위치", "cooldowns": "쿨다운", "cooldown": "쿨다운", "health": "체력", "hp": "체력"}.get(str(ev.get("field", "")), "정보")
				fx.text(interrogator.pos + Vector2(0, -48), "언론 통제 · 취득 차단" if ty == "INFO_BLOCKED" else "정보 캐기 · " + field + " 취득", Color("#ecd998") if ty == "INFO_BLOCKED" else Color("#f5b0d4"), 12.0, 1.1, 14.0, false, false)
				_sfx("intel", 0.25, 0.85 if ty == "INFO_BLOCKED" else 1.0)
		"TURRET_UPGRADED":
			var pos4: Vector2 = ev.get("pos", Vector2.ZERO)
			fx.ring(pos4, Color(0.8, 1.6, 1.3), 6.0, 34.0, 0.4, 2.5)
			fx.sig(pos4, "engineer", Color(0.8, 1.6, 1.3), 30.0, 0.6)
		"PASSIVE":
			_passive_event(ev)
		"BUFF_APPLIED":
			var tg9: = sim.u_at(int(ev.g))
			var ab9 = ev.get("ability")
			if tg9 and tg9.alive and ab9 is Defs.AbilityDef and throttle("buff:%d:%s" % [tg9.idx, (ab9 as Defs.AbilityDef).id], 0.5):
				var c9: = VfxStyle.color_for(ab9)
				var r9: = sim.radius(tg9)
				fx.ring(tg9.pos, VfxStyle.hdr(c9, 1.4), r9, r9 + 30.0, 0.45, 2.5, 0.12)
				fx.burst(tg9.pos, VfxStyle.hdr(c9, 1.3), 8, 30.0, 110.0, 2.0, 0.55, 2.5, -50.0)
				var src9: = sim.u_at(int(ev.s))
				if src9 and src9 != tg9 and src9.alive:
					fx.beam(src9.pos, tg9.pos, VfxStyle.hdr(c9, 1.3), 2.5, 0.3)
		"STATUS_APPLIED":
			var t10: = sim.u_at(int(ev.g))
			var st10: = str(ev.get("status", ""))
			if t10 and t10.is_hero and st10 != "dot" and throttle("st:%d:%s" % [t10.idx, st10], 0.6):
				var ic10: Array = VfxStyle.status_icon(st10)
				var c10: = Color(str(ic10[1]))
				var r10: = sim.radius(t10)
				fx.glyph(t10.pos + Vector2(r10 + 16.0, -4.0), str(ic10[0]), VfxStyle.hdr(c10, 1.3), 16.0, 0.6)
				fx.ring(t10.pos, VfxStyle.hdr(c10, 1.2), r10, r10 + 14.0, 0.3, 2.0)
				ev_fx.status(_ev_key(ev, sim.u_at(int(ev.s))), t10.pos, r10, st10)
				var sk10: = int(ev.get("stacks", 1))
				if bool(ev.get("mark", false)) and sk10 > 1:
					fx.text(t10.pos + Vector2(r10 + 31.0, 0.0), "×%d" % sk10, c10.lightened(0.2), 12.0, 0.7, 14.0, true, false)
		"HEALTH_COST":
			var t11: = sim.u_at(int(ev.g))
			if t11:
				var amt11: = float(ev.get("amount", 0.0))
				var wd: = str(ev.get("reason", "")) == "withdrawal"
				if show_numbers and amt11 >= 1.0:
					fx.text(t11.pos + Vector2(0, - sim.radius(t11) - 22.0), "-%d" % int(round(amt11)), Color("#ff5d7a"), 14.0 + minf(8.0, amt11 / 40.0), 0.9)
				fx.burst(t11.pos, Color(1.4, 0.2, 0.3, 0.9), 10, 30.0, 110.0, 2.4, 0.6, 2.0, 120.0)
				if wd:
					fx.banner(t11.pos + Vector2(0, -56), "금단", Color("#ff6fb5"), 16.0, 1.0)
					fx.ring(t11.pos, Color(1.8, 0.4, 0.9), 8.0, 50.0, 0.45, 3.0)
		"SHIELD_BROKEN":
			var t12: = sim.u_at(int(ev.g))
			if t12:
				fx.ring(t12.pos, Color(1.2, 1.4, 1.8, 0.9), sim.radius(t12) + 6.0, sim.radius(t12) + 26.0, 0.3, 2.5)
				fx.burst(t12.pos, Color(1.1, 1.3, 1.7), 14, 80.0, 220.0, 2.2, 0.4, 3.0, 0.0, Vector2.ZERO, TAU, 2)
		"DAMAGE_IMMUNE", "CC_IMMUNE":
			var t13: = sim.u_at(int(ev.g))
			if t13 and t13.is_hero and throttle("imm:%d" % t13.idx, 0.7):
				fx.text(t13.pos + Vector2(0, - sim.radius(t13) - 30.0), "면역", Color("#bfe9ff"), 13.0, 0.7, 16.0, true, false)
		"CAST_CANCELLED":
			var su14: = sim.u_at(int(ev.s))
			if su14 and su14.alive:
				fx.ring(su14.pos, Color(0.7, 0.75, 0.85, 0.8), sim.radius(su14) + 10.0, sim.radius(su14) + 2.0, 0.25, 2.0)
				if throttle("cancel:%d" % su14.idx, 1.0):
					fx.text(su14.pos + Vector2(0, - sim.radius(su14) - 30.0), "취소", Color("#9aabc6"), 11.0, 0.6, 12.0, false, false)
		"PORTAL_USED", "PROJECTILE_PORTAL":
			var from15: Vector2 = ev.get("from", Vector2.ZERO)
			var to15: Vector2 = ev.get("to", ev.get("pos", Vector2.ZERO))
			var c15: = VfxStyle.hdr(Color("#70d3ef"), 1.6)
			fx.flash(from15, c15, 40.0, 0.25)
			fx.flash(to15, c15, 40.0, 0.25)
			fx.ring(to15, c15, 6.0, 40.0, 0.35, 2.5)
			if ty == "PORTAL_USED":
				fx.motif_fly(to15, Vector2(0, -40), "prism", Color(0.6, 1.4, 1.8), 5.0, 0.6)
		"ABILITY_RECAST":
			var su16: = sim.u_at(int(ev.s))
			var ab16 = ev.get("ability")
			if su16 and ab16 is Defs.AbilityDef:
				var c16: = VfxStyle.color_for(ab16)
				fx.glyph(su16.pos + Vector2(0, - sim.radius(su16) - 24.0), VfxStyle.glyph_for(ab16), VfxStyle.hdr(c16, 1.3), 20.0, 0.6)
				fx.ring(su16.pos, VfxStyle.hdr(c16, 1.4), sim.radius(su16), sim.radius(su16) + 40.0, 0.4, 3.0)
		"DEFENSE_STATE":
			var su17: = sim.u_at(int(ev.s))
			if su17:
				fx.passive_pulse(su17.idx, "helmet", Color(1.7, 1.1, 0.8), sim.radius(su17), 0.6)
		"ATTACK_RELEASED":
			var su18: = sim.u_at(int(ev.s))
			if su18:
				swing_at[su18.idx] = sim.time
				if not bool(ev.get("melee", true)) and su18.is_hero and quality >= 1:
					var from18: Vector2 = ev.get("from", su18.pos)
					var to18: Vector2 = ev.get("pos", su18.pos)
					fx.flash(from18 + (to18 - from18).normalized() * (sim.radius(su18) + 8.0), VfxStyle.hdr(su18.def.accent, 1.4), 12.0, 0.1)
					ev_fx.muzzle(su18.def.id + ":basic", from18, to18, sim.radius(su18))
		"CAST_COMPLETED":
			swing_at[int(ev.s)] = sim.time
		"ATTACK_DECLARED":

			var su22: = sim.u_at(int(ev.s))
			if su22 and su22.is_hero and quality >= 1 and throttle("adecl:%d" % su22.idx, 0.3):
				ev_fx.sig(su22.def.id, su22.pos, sim.radius(su22) + 8.0, su22.def.accent, 0, float(ev.get("windup", 0.2)) + 0.12)
		"SUMMON_DESTROYED", "SUMMON_EXPIRED", "SUMMON_CONSUMED":
			var e19: = sim.u_at(int(ev.g))
			if e19:
				fx.burst(e19.pos, VfxStyle.hdr(e19.def.accent, 1.2), 10, 30.0, 120.0, 2.0, 0.45, 3.0)
				fx.ring(e19.pos, VfxStyle.hdr(e19.def.accent, 1.1), 4.0, 22.0, 0.3, 1.5)
		"CONTROL_ENDED":
			var t20: = sim.u_at(int(ev.g))
			if t20:
				fx.burst(t20.pos, Color(1.2, 0.8, 1.6), 12, 40.0, 150.0, 2.2, 0.45, 3.0)
				fx.text(t20.pos + Vector2(0, - sim.radius(t20) - 30.0), "조종 해제", Color("#d6b3ff"), 12.0, 0.8, 14.0, false, false)
		# V2 hero events.
		"CLEANSED":
			var t30: = sim.u_at(int(ev.g))
			if t30 and t30.alive:
				var r30: = sim.radius(t30)
				var c30: = Color("#ffd77a")
				ev_fx.cleanse(t30.pos, r30, c30)
				fx.flash(t30.pos, Color(2.0, 1.75, 1.1), r30 + 26.0, 0.25)
				fx.burst(t30.pos, Color(1.9, 1.6, 0.9), 10, 30.0, 110.0, 2.0, 0.6, 2.5, -60.0)
				if throttle("cleanse:%d" % t30.idx, 0.8):
					fx.text(t30.pos + Vector2(0, - r30 - 34.0), "정화", c30, 13.0, 0.8, 16.0, true, false)
				_sfx("heal", 0.3, 1.25)
		"FRONT_BLOCKED":
			var t31: = sim.u_at(int(ev.g))
			if t31 and t31.alive:
				var r31: = sim.radius(t31)
				var fg31: = sim.get_status(t31, &"frontGuard")
				var ang31: = (fg31.extra.get("dir", t31.facing) as Vector2).angle() if fg31 else t31.facing.angle()
				var src31: = sim.u_at(int(ev.s))
				if src31 and src31 != t31 and src31.pos.distance_squared_to(t31.pos) > 1.0:
					ang31 = (src31.pos - t31.pos).angle()
				ev_fx.block(t31.pos, ang31, r31, Color("#d9a24f"))
				fx.burst(t31.pos + Vector2.from_angle(ang31) * (r31 + 10.0), Color(2.0, 1.6, 0.9), 8, 60.0, 180.0, 1.8, 0.3, 4.0, 0.0, Vector2.from_angle(ang31), 1.4, 1)
				if str(ev.get("kind", "")) != "projectile" and throttle("fblock:%d" % t31.idx, 0.6):
					fx.text(t31.pos + Vector2(0, - r31 - 30.0), "방패 막음", Color("#f0c27a"), 13.0, 0.7, 16.0, true, false)
				_sfx("shield", 0.3, 1.3)
		"TANK_DESTROYED":
			var tp32: Vector2 = ev.get("pos", Vector2.ZERO)
			fx.flash(tp32, Color(2.0, 1.2, 0.5), 70.0, 0.3)
			fx.ring(tp32, Color(2.0, 1.0, 0.35), 6.0, 72.0, 0.5, 4.0, 0.15)
			fx.burst(tp32, Color(2.0, 1.1, 0.4), 30, 80.0, 320.0, 2.8, 0.7, 2.5, 0.0, Vector2.ZERO, TAU, 2)
			fx.burst(tp32, Color(0.35, 0.32, 0.3, 0.7), 12, 20.0, 80.0, 6.0, 1.1, 1.2, -25.0)
			for k32 in 4:
				fx.motif_fly(tp32, Vector2.from_angle(k32 * TAU / 4.0 + 0.4) * 95.0, "bolt", Color(1.6, 0.9, 0.5), 5.0, 0.6, 9.0)
			fx.banner(tp32 + Vector2(0, -42), "연료탱크 파괴", Color("#ffb27a"), 16.0, 1.1)
			fx.add_shake(4.0)
			_sfx("boom", 0.5, 1.1)
		"OVERDRIVE":
			var w33: = sim.u_at(int(ev.g))
			if w33 and w33.alive:
				var r33: = sim.radius(w33)
				fx.ring(w33.pos, Color(2.0, 0.8, 0.3), r33, r33 + 46.0, 0.55, 3.0, 0.12)
				fx.burst(w33.pos, Color(2.0, 0.9, 0.3), 18, 40.0, 180.0, 2.4, 0.6, 2.0, -80.0)
				fx.banner(w33.pos + Vector2(0, -62), "과열 폭주 · %d초" % int(round(float(ev.get("duration", 10.0)))), Color("#ff9a5b"), 18.0, 1.3)
		"HEAL_BLOCKED":
			var t34: = sim.u_at(int(ev.g))
			if t34 and t34.alive:
				var r34: = sim.radius(t34)
				fx.ring(t34.pos, Color(1.2, 0.6, 1.8), r34 + 2.0, r34 + 26.0, 0.45, 3.0)
				fx.burst(t34.pos, Color(0.9, 0.5, 1.6), 10, 30.0, 120.0, 2.0, 0.5, 3.0)
				fx.text(t34.pos + Vector2(0, - r34 - 40.0), "회복 불가", Color("#c9b8ff"), 15.0, 1.1, 16.0, true, false)
				_sfx("cc", 0.35, 0.8)
		"CHARIOT_KNOCK":
			var t35: = sim.u_at(int(ev.g))
			if t35:
				var ch35: = sim.u_at(int(ev.get("entity", -1)))
				var from35: Vector2 = ch35.pos if ch35 else t35.pos
				var d35: = (t35.pos - from35).normalized() if t35.pos.distance_squared_to(from35) > 1.0 else Vector2.UP
				fx.flash(t35.pos, Color(2.0, 1.7, 1.0), 40.0, 0.2)
				fx.burst(t35.pos, Color(0.75, 0.62, 0.45, 0.8), 14, 40.0, 160.0, 3.0, 0.6, 2.0, 0.0, - d35, 2.2)
				fx.slash(t35.pos - d35 * 6.0, d35, Color(1.9, 1.4, 0.7), 30.0, 1.8, 0.22, 5.0)
				var max35: = int(ch35.ks.get("max_knocks", 2)) if ch35 else 2
				fx.text(t35.pos + Vector2(0, - sim.radius(t35) - 34.0), "전차 %d/%d" % [int(ev.get("count", 1)), max35], Color("#f0c27a"), 13.0, 0.9, 16.0, true, false)
				fx.add_shake(2.5)
				_sfx("boom", 0.35, 1.3)
		"PARITY_BED_RESOLVED":
			var pos21: Vector2 = ev.get("pos", Vector2.ZERO)
			if str(ev.get("result", "")) == "paired":
				fx.banner(pos21 + Vector2(0, -50), "짝 회복", Color("#ffb3d9"), 16.0, 1.2)
				fx.sig(pos21, "aphrodite", Color(1.7, 0.9, 1.3), 40.0, 0.8)
			else:
				fx.text(pos21 + Vector2(0, -40), "홀로 남음 · 공격력 −15%", Color("#ebc179"), 12.0, 1.0, 14.0, false, false)



func _passive_event(ev: Dictionary) -> void :
	var su: = sim.u_at(int(ev.s))
	if su == null or not su.alive:
		return
	var rule: = str(ev.get("rule", ""))
	var col: = VfxStyle.hdr(su.def.accent, 1.3)
	var r: = sim.radius(su)
	if throttle("pp:%d:%s" % [su.idx, rule], 0.45):
		fx.passive_pulse(su.idx, str(PASSIVE_MOTIF.get(su.def.id, "arcs")), col, r, 0.7)
	var tp: Vector2 = ev.get("pos", su.pos)
	var other: = sim.u_at(int(ev.g))
	match rule:
		"nth_basic_bonus":

			var d: = (tp - su.pos).normalized() if tp.distance_squared_to(su.pos) > 1.0 else su.facing
			fx.slash(tp - d * 6.0, d, VfxStyle.hdr(su.def.accent, 1.8), 34.0, 2.6, 0.26, 6.0)
			fx.burst(tp, col, 12, 80.0, 240.0, 2.2, 0.35, 3.5, 0.0, d, 1.4, 1)
		"cone_basic":
			fx.passive_pulse(su.idx, "reflect", col, r, 0.5)
		"borrow_mobility":
			if other and other.alive:
				fx.beam(other.pos, su.pos, Color(0.6, 1.5, 1.4), 2.0, 0.4)
				fx.motif_fly(other.pos, (su.pos - other.pos) * 1.6, "feather", Color(0.6, 1.5, 1.4), 5.0, 0.6)
		"timed_random_buff":
			fx.motif_fly(su.pos + Vector2(0, - r - 8.0), Vector2(0, -50), "fish", Color(0.55, 1.4, 1.5), 1.0, 0.7, 0.0)
		"portal_shards":
			for i in 3:
				fx.motif_fly(su.pos, Vector2.from_angle( - PI * 0.5 + (i - 1) * 0.7) * 70.0, "shards", Color(0.6, 1.5, 1.9), 4.0, 0.55)
		"wall_mastery":
			fx.burst(su.pos, Color(1.8, 1.1, 0.4), 12, 60.0, 180.0, 2.2, 0.35, 3.0)
		"heal_reduction_bank":
			if other and other.alive and throttle("bank:%d" % su.idx, 0.4):
				fx.beam(other.pos, su.pos, Color(0.55, 1.5, 0.9, 0.7), 1.5, 0.35)
		"lost_health_ap_on_skill_hit":
			fx.burst(su.pos, Color(1.5, 0.35, 0.5), 6, 20.0, 60.0, 2.0, 0.6, 2.0, -40.0)
		"nexus_workshop":
			fx.sig(su.pos, "engineer", col, r + 18.0, 0.55)
	if not bool(ev.get("silent", false)) and str(ev.get("detail", "")) != "" and throttle("ptext:%d" % su.idx, 0.8):
		fx.text(su.pos + Vector2(0, - r - 36.0), str(ev.detail), su.def.accent.lightened(0.35), 12.0, 1.0, 16.0, false, false)


func _handle_fx(ev: Dictionary) -> void :
	var kind: = str(ev.get("kind", ""))
	var pos: Vector2 = ev.get("pos", Vector2.ZERO)
	var ab = ev.get("ability")
	var a: Defs.AbilityDef = ab if ab is Defs.AbilityDef else null
	var col: = Color.WHITE
	if a:
		col = VfxStyle.color_for(a)
	else:
		var cv = ev.get("color", null)
		if cv is Color:
			col = cv
		elif cv != null:
			col = Color(str(cv))
	var hdr: = VfxStyle.hdr(col, 1.5)
	var pat: = VfxStyle.pattern_for(a) if a else str(ev.get("pattern", ""))
	var src_fx: = sim.u_at(int(ev.get("source", -1)))

	if a and quality >= 1 and kind in ["explosion", "impact_area"]:
		ev_fx.sig(src_fx.def.id if src_fx and src_fx.is_hero else a.char_id, pos, float(ev.get("radius", 40.0)), src_fx.def.accent if src_fx else col, a.slot, 0.65)
	match kind:
		"cast":
			var src: = src_fx
			var to: Vector2 = ev.get("to", pos)
			if pat in VfxStyle.BEAM:
				fx.beam(pos, to, hdr, 3.5, 0.28)
			fx.flash(pos, hdr, 28.0, 0.15)
			if a and src:

				var rs: = sim.radius(src)
				var q: = to
				if a.delivery == "self" or a.target == "self" or a.delivery == "projectile":
					q = pos
				if a.delivery != "cone":
					ev_fx.release(a, pos, to, q, a.radius, rs, src.idx, float(src.ks.get("glide_until", 0.0)) > sim.time)

				if quality >= 1 and (a.delivery in ["self", "direct", "projectile"] or EventFx.NEXUS.has(a.char_id)):
					ev_fx.sig(src.def.id if src.is_hero else a.char_id, q, a.radius, src.def.accent, a.slot, float({"self": 0.9, "direct": 0.75, "projectile": 0.45}.get(a.delivery, 0.8)))

				if a.target == "self" or pat in VfxStyle.NOVA:
					fx.ring(src.pos, VfxStyle.hdr(col, 1.3), rs, rs + 48.0, 0.5, 2.5, 0.1)
					fx.burst(src.pos, hdr, 14, 40.0, 160.0, 2.2, 0.55, 2.5)
		"area":
			var r: = float(ev.get("radius", 60.0))
			var heavy: = pat in VfxStyle.HEAVY
			fx.flash(pos, hdr, r * 0.9, 0.22)
			fx.ring(pos, hdr, r * 0.3, r, 0.42, 4.0 if heavy else 3.0, 0.18)
			fx.burst(pos, hdr, 22 if heavy else 12, 60.0, 260.0 if heavy else 170.0, 2.6, 0.55, 3.0, 0.0, Vector2.ZERO, TAU, 2 if heavy else 0)
			if pat in VfxStyle.NOVA:
				fx.ring(pos, VfxStyle.hdr(col, 1.1), r * 0.1, r * 1.1, 0.6, 2.0)
			if heavy:
				fx.add_shake(3.5 + r / 60.0)
				_sfx("boom", 0.55, 1.0)
			else:
				_sfx("area", 0.4, 1.0)
		"cone":
			var dir: Vector2 = ev.get("dir", Vector2.RIGHT)
			var rng_: = float(ev.get("range", 100.0))
			var ang: = float(ev.get("angle", 1.0))
			if a:

				ev_fx.cone(EventFx.ability_key(a), pos, dir, rng_, ang, sim.eteam(src_fx) if src_fx else 0)
			else:
				fx.cone(pos, dir, rng_, ang, hdr, 0.3)
				fx.slash(pos, dir, hdr, rng_ * 0.85, ang, 0.26, 6.0)
			fx.burst(pos + dir * rng_ * 0.5, hdr, 10, 80.0, 220.0, 2.2, 0.4, 3.0, 0.0, dir, ang, 1)
			_sfx("swing", 0.4, 1.0)
		"strike":
			var from: Vector2 = ev.get("from", pos)
			var d2: = (pos - from).normalized()
			var crit: = bool(ev.get("crit", false))
			if src_fx and src_fx.is_hero:

				ev_fx.strike(src_fx.def.id + ":basic", from, pos)
			else:
				fx.slash(pos - d2 * 8.0, d2, VfxStyle.hdr(col, 1.4), 22.0, 1.6, 0.18, 4.0)
			fx.burst(pos, VfxStyle.hdr(col, 1.4), 4 if not crit else 12, 80.0, 200.0, 1.8, 0.25, 4.0, 0.0, d2, 1.2, 1)
			if crit:
				fx.slash(pos - d2 * 8.0, d2, VfxStyle.hdr(col, 2.0), 32.0, 1.6, 0.18, 6.0)
				fx.add_shake(2.5)
		"direct":
			var from2: Vector2 = ev.get("from", pos)
			if pat in VfxStyle.BEAM or pat in ["hitscan"]:
				fx.beam(from2, pos, hdr, 3.0 if pat != "hitscan" else 4.0, 0.25)
			fx.flash(pos, hdr, 36.0, 0.18)
			fx.burst(pos, hdr, 10, 60.0, 200.0, 2.2, 0.4, 3.0)
		"explosion":
			var r2: = float(ev.get("radius", 80.0))
			fx.flash(pos, VfxStyle.hdr(col, 2.0), r2, 0.3)
			fx.ring(pos, VfxStyle.hdr(col, 1.6), r2 * 0.2, r2 * 1.1, 0.5, 5.0, 0.2)
			fx.burst(pos, VfxStyle.hdr(col, 1.6), 34, 90.0, 380.0, 3.0, 0.7, 2.4, 0.0, Vector2.ZERO, TAU, 2)
			fx.burst(pos, Color(0.4, 0.38, 0.36, 0.55), 12, 20.0, 90.0, 6.0, 1.2, 1.2, -20.0)
			if a:
				ev_fx.impact(EventFx.ability_key(a), pos, r2, 0.0)
			fx.add_shake(4.0 + r2 / 40.0)
			if hitstop_enabled and runner and r2 >= 100.0:
				runner.add_hitstop(0.04)
			_sfx("boom", 0.6, 0.95)
		"proj_hit":
			var dir2: Vector2 = ev.get("dir", Vector2.RIGHT)
			var basic: = bool(ev.get("basic", false))
			fx.burst(pos, VfxStyle.hdr(col, 1.5), 4 if basic else 10, 70.0, 220.0, 1.8 if basic else 2.4, 0.3, 4.0, 0.0, dir2, 1.6, 1)
			if not basic:
				fx.flash(pos, VfxStyle.hdr(col, 1.6), 26.0, 0.16)

				if a and throttle("imp:%d:%s" % [int(ev.get("target", -1)), EventFx.ability_key(a)], 0.12):
					ev_fx.impact(EventFx.ability_key(a), pos, 32.0, dir2.angle())
				if pat in VfxStyle.HEAVY:
					fx.ring(pos, VfxStyle.hdr(col, 1.4), 6.0, 42.0, 0.3, 3.0)
					fx.add_shake(2.0)
		"proj_wall":
			fx.burst(pos, VfxStyle.hdr(col, 1.3), 6, 50.0, 160.0, 1.8, 0.3, 4.0, 0.0, Vector2.ZERO, TAU, 1)
		"impact_area":
			var r3: = float(ev.get("radius", 60.0))
			if a:
				ev_fx.impact(EventFx.ability_key(a), pos, r3, 0.0)
			fx.ring(pos, hdr, r3 * 0.3, r3, 0.4, 3.0, 0.15)
			fx.burst(pos, hdr, 14, 60.0, 200.0, 2.4, 0.5, 3.0)
			_sfx("area", 0.4, 1.0)
		"pulse":
			var r4: = float(ev.get("radius", 80.0))
			fx.ring(pos, hdr, r4 * 0.4, r4, 0.4 if bool(ev.get("small", false)) else 0.55, 2.0 if bool(ev.get("small", false)) else 3.0)
		"dash_hit":
			fx.flash(pos, hdr, 34.0, 0.18)
			fx.burst(pos, hdr, 12, 80.0, 260.0, 2.2, 0.35, 3.5, 0.0, Vector2.ZERO, TAU, 1)
			fx.add_shake(2.0)
		"bite":
			fx.slash(pos, Vector2.from_angle(randf() * TAU), hdr, 14.0, 2.0, 0.18, 3.0)
		"bat":

			var dirb: Vector2 = ev.get("dir", Vector2.RIGHT)
			ev_fx.cone("baseball:basic", pos, dirb, float(ev.get("range", 76.0)), float(ev.get("angle", 1.4)), sim.eteam(src_fx) if src_fx else 0, true)
		"jump_pad":
			var land: Vector2 = ev.get("to", pos)
			fx.leap(pos, land, hdr, float(ev.get("duration", 0.8)))
			fx.ring(pos, hdr, 6.0, 46.0, 0.35, 3.0)
			fx.burst(pos, hdr, 10, 40.0, 150.0, 2.2, 0.4, 3.0)
			_sfx("dash", 0.25, 1.2)
		"artillery_impact":
			var ar: float = float(ev.get("radius", 70.0))
			fx.flash(pos, Color(1.8, 1.45, 0.75), ar * 1.15, 0.3)
			fx.ring(pos, Color(1.7, 1.35, 0.6), ar * 0.3, ar * 1.15, 0.45, 4.0, 0.15)
			fx.burst(pos, Color(1.5, 1.05, 0.55), 22, 60.0, 260.0, 2.6, 0.55, 3.0, 0.0, Vector2.ZERO, TAU, 1)
			fx.burst(pos, Color(0.42, 0.37, 0.33, 0.8), 12, 20.0, 90.0, 4.0, 0.9, 1.5, -20.0)
			fx.add_shake(3.5)
			_sfx("boom", 0.32, randf_range(0.9, 1.1))
		"portal_jump":
			var from3: Vector2 = ev.get("from", pos)
			fx.flash(from3, hdr, 40.0, 0.25)
			fx.flash(pos, hdr, 40.0, 0.25)
			fx.ring(pos, hdr, 6.0, 40.0, 0.35, 2.5)
		"garden", "garden_rootGarden", "garden_thornGarden":
			fx.ring(pos, Color(0.7, 1.7, 0.9), 10.0, 120.0, 0.6, 3.0, 0.1)
			fx.burst(pos, Color(0.6, 1.6, 0.8), 18, 40.0, 180.0, 2.4, 0.7, 2.5)
		"tree_pulse":

			fx.ring(pos, Color(0.55, 1.5, 0.8, 0.6), 20.0, 125.0, 0.9, 1.5, 0.05)
			fx.motif_fly(pos + Vector2(randf_range(-10, 10), -14), Vector2(randf_range(-20, 20), -30), "leaf", Color(0.55, 1.4, 0.75), 5.0, 0.8, 2.0)
		"construct", "upgrade", "flower", "bed_pair", "box":
			fx.ring(pos, hdr, 4.0, 34.0, 0.4, 2.5)
			fx.burst(pos, hdr, 8, 30.0, 110.0, 2.0, 0.5, 3.0)
		"seal", "withdrawal", "chamber_pulse":
			fx.ring(pos, Color(1.6, 0.6, 1.2), 6.0, 38.0, 0.35, 2.5)
		"chamber":
			fx.flash(pos, Color(1.4, 0.5, 1.1), 100.0, 0.35)
		"wall_pin":
			fx.burst(pos, hdr, 14, 60.0, 200.0, 2.4, 0.4, 3.0, 0.0, Vector2.ZERO, TAU, 2)
			fx.add_shake(3.0)
		"parry":
			fx.flash(pos, Color(1.8, 1.8, 1.8), 34.0, 0.16)
			fx.text(pos + Vector2(0, -30), "반격", Color("#ffc19b"), 14.0, 0.8, 16.0, true, false)
		"fish_eat":
			fx.burst(pos, Color(0.6, 1.5, 1.5), 8, 20.0, 70.0, 2.0, 0.6, 2.0, -40.0)
		"coin_pick":
			fx.burst(pos, Color(1.7, 1.3, 0.5), 8, 30.0, 120.0, 1.8, 0.4, 3.0)
			_sfx("coin", 0.3, randf_range(1.0, 1.2))
		"wing_hit":

			var ally: = bool(ev.get("ally", false))
			var cw: = Color(0.6, 1.6, 0.9) if ally else VfxStyle.hdr(col, 1.5)
			if not ally:
				fx.slash(pos, Vector2.from_angle(randf() * TAU), cw, 16.0, 2.2, 0.2, 3.0)
			fx.motif_fly(pos, Vector2.from_angle(randf() * TAU) * 50.0, "feather", cw, 4.0, 0.5, 6.0)
			fx.burst(pos, cw, 5, 30.0, 90.0, 2.0, 0.35, 3.0)
		"banana_slip", "bait_snap":
			fx.ring(pos, hdr, 4.0, 40.0, 0.35, 3.0)
			fx.burst(pos, hdr, 10, 40.0, 150.0, 2.2, 0.4, 3.0)






func _sfx(n: String, v: float = 0.5, p: float = 1.0) -> void :
	if sound:
		Sfx.play(n, v, p)


func _glyph(ci: CanvasItem, c: Vector2, g: String, col: Color, size: int) -> void :
	var f: = DB.font_glyph
	size = maxi(6, size)
	var w: = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc: = f.get_ascent(size)
	var desc: = f.get_descent(size)
	ci.draw_string(f, Vector2(c.x - w * 0.5, c.y + (asc - desc) * 0.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Label text centred on `c` (world, at the baseline). With the readable HUD it is drawn at a
## screen size of at least `min_px` (0 = keep world scaling, e.g. for unit art such as "z").
func _text(ci: CanvasItem, c: Vector2, s: String, col: Color, size: int, min_px: float = PX_SUB) -> void :
	if hud_readable and min_px > 0.0 and size * hud_scale <= 28.5:
		_text_px(ci, c, s, col, _px(size, min_px))
		return
	var f: = DB.font_bold
	var w: = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p: = Vector2(c.x - w * 0.5, c.y)
	ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.75 * col.a))
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---- Readable HUD helpers (only used when hud_readable) ----

## Screen px for HUD text of world size `size`, never below `min_px`.
func _px(size: float, min_px: float) -> int:
	return VfxStyle.hud_px(size, hud_scale, min_px)


## World offset from an edge down to the baseline of a caption below it: the old offset, or
## enough room for the caption at its screen size.
func _below(offset: float, size: float, min_px: float) -> float:
	if not hud_readable:
		return offset
	return maxf(offset, (3.0 + _px(size, min_px) * 0.82) * _inv)


## World offset from an edge up to the baseline of a caption above it.
func _above(offset: float) -> float:
	if not hud_readable:
		return offset
	return maxf(offset, 4.0 * _inv)


## Text at `px` screen pixels, centred on `c` (world, at the baseline).
func _text_px(ci: CanvasItem, c: Vector2, s: String, col: Color, px: int) -> void :
	var f: = DB.font_bold
	var w: = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p: = Vector2(w * -0.5, 0.0)
	ci.draw_set_transform(c, 0.0, Vector2(_inv, _inv))
	ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0, 0, 0, 0.8 * col.a))
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Glyph at `px` screen pixels, centred on `c` (world).
func _glyph_px(ci: CanvasItem, c: Vector2, g: String, col: Color, px: int) -> void :
	var f: = DB.font_glyph
	var w: = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var asc: = f.get_ascent(px)
	var desc: = f.get_descent(px)
	ci.draw_set_transform(c, 0.0, Vector2(_inv, _inv))
	ci.draw_string(f, Vector2(w * -0.5, (asc - desc) * 0.5), g, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Per-frame HUD state for the readable mode: sizing scale (dead-banded), px->world factor,
## compact-label switch (with hysteresis), hover target and deathmatch top-3.
func _update_hud_metrics() -> void :
	var vs: = maxf(0.02, view_scale)
	if absf(vs - hud_scale) > hud_scale * 0.08:
		hud_scale = vs
	_inv = 1.0 / vs
	if _lod and vs > LOD_OUT:
		_lod = false
	elif not _lod and vs < LOD_IN:
		_lod = true
	fx.hud_scale = hud_scale
	fx.inv_scale = _inv
	_update_hover()
	_update_top()


func _update_hover() -> void :
	hovered = -1
	_hover_item = -1
	if fit_rect.size.x <= 0.0 or fit_rect.size.y <= 0.0:
		return
	var wp: = get_local_mouse_position()
	if not fit_rect.has_point(position + wp * view_scale):
		return
	var best: = 10.0 * _inv
	for u in sim.heroes:
		if not u.alive or not _vis(u):
			continue
		var d: = upos(u).distance_to(wp) - sim.radius(u)
		if d < best:
			best = d
			hovered = u.idx
	if sim.deathmatch and show_names:
		var bi: = 14.0 * _inv
		for it in sim.deathmatch.field:
			if not field_item_visible(it.pos):
				continue
			var d2: = (it.pos as Vector2).distance_to(wp)
			if d2 < bi:
				bi = d2
				_hover_item = int(it.uid)


func _update_top() -> void :
	_top[0] = -1
	_top[1] = -1
	_top[2] = -1
	if not _lod or sim.deathmatch == null:
		return
	if br != null:
		_update_top_br()
		return
	# Same order as DeathmatchMode.ranking() (kills, deaths, damage, idx) without sorting or
	# allocating; heroes without a kill never count as leaders.
	for u in sim.heroes:
		if int(sim.deathmatch.kills[u.team]) <= 0:
			continue
		var c: BUnit = u
		for slot in 3:
			var cur: BUnit = sim.u_at(_top[slot]) if _top[slot] >= 0 else null
			if cur == null:
				_top[slot] = c.idx
				break
			if _ranks_before(c, cur):
				_top[slot] = c.idx
				c = cur


## Battleground: the three heroes with the most kills of their own (then damage, index).
func _update_top_br() -> void:
	for u in sim.heroes:
		var hs: Dictionary = br.hstats.get(u.idx, {})
		if int(hs.get("kills", 0)) <= 0:
			continue
		var c: BUnit = u
		for slot in 3:
			var cur: BUnit = sim.u_at(_top[slot]) if _top[slot] >= 0 else null
			if cur == null:
				_top[slot] = c.idx
				break
			if _br_ranks_before(c, cur):
				_top[slot] = c.idx
				c = cur


func _br_ranks_before(a: BUnit, b: BUnit) -> bool:
	var ha: Dictionary = br.hstats.get(a.idx, {})
	var hb: Dictionary = br.hstats.get(b.idx, {})
	if int(ha.get("kills", 0)) != int(hb.get("kills", 0)):
		return int(ha.get("kills", 0)) > int(hb.get("kills", 0))
	var da: float = float(ha.get("damage", 0.0))
	var db: float = float(hb.get("damage", 0.0))
	if absf(da - db) > 0.001:
		return da > db
	return a.idx < b.idx


## BrStanding / TeamChip style downed fields of a hero ({} when not downed).
func _downed_row(u: BUnit) -> Dictionary:
	var d: Dictionary = br.downed.get(u.idx, {}) if br != null else {}
	if d.is_empty():
		return {}
	return {"downed_left": maxf(0.0, float(d.get("bleed_at", sim.time)) - sim.time), "downed_total": float(d.get("bleed_total", 30.0)),
		"revive": float(d.get("revive_progress", 0.0))}


func _ranks_before(a: BUnit, b: BUnit) -> bool:
	var dm: = sim.deathmatch
	if dm.kills[a.team] != dm.kills[b.team]:
		return dm.kills[a.team] > dm.kills[b.team]
	if dm.deaths[a.team] != dm.deaths[b.team]:
		return dm.deaths[a.team] < dm.deaths[b.team]
	if absf(a.st_damage - b.st_damage) > 0.001:
		return a.st_damage > b.st_damage
	return a.idx < b.idx


func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void :
	var d: = b - a
	var L: = d.length()
	if L < 1.0:
		return
	var dir: = d / L
	var t: = 0.0
	while t < L:
		ci.draw_line(a + dir * t, a + dir * minf(L, t + dash), col, w, true)
		t += dash * 2.0


func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float, n: int) -> void :
	for k in n:
		var a0: = TAU * k / n + anim * 0.3
		ci.draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, w, true)


func _wedge(ci: CanvasItem, from: Vector2, dir: Vector2, rng_: float, ang: float, fill: Color, edge: Color) -> void :
	if rng_ <= 1.0:
		return
	var pts: = PackedVector2Array([from])
	var n: = 16
	var base: = dir.angle() - ang * 0.5
	for j in n + 1:
		pts.append(from + Vector2.from_angle(base + ang * j / n) * rng_)
	if fill.a > 0.0:
		ci.draw_colored_polygon(pts, fill)
	if edge.a > 0.0:
		pts.append(from)
		ci.draw_polyline(pts, edge, 1.5, true)


func _portal(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void :
	ci.draw_circle(p, r, Color(col.darkened(0.6), 0.85))
	for k in 3:
		var rr: = r * (0.4 + 0.22 * k)
		var st: = anim * (2.2 - k * 0.5) + k
		ci.draw_arc(p, rr, st, st + PI * 1.25, 20, VfxStyle.hdr(col, 1.2 - k * 0.2), 2.0, true)
	ci.draw_arc(p, r, 0, TAU, 32, VfxStyle.hdr(col, 1.3), 2.0, true)


func _draw_canopy() -> void:
	if arena == null or arena.forest_x.is_empty():
		return
	if br != null:
		# Battleground: culled chunks, or the baked canopy in the overview.
		if _br_overview and _br_bake_canopy != null:
			canopy_layer.draw_texture_rect(_br_bake_canopy.get_texture(), Rect2(Vector2.ZERO, _arena_size()), false)
		return
	ArenaPainter.draw_canopy(canopy_layer, arena, 1.0, Vector2.ZERO, 0.5 if perspective < 0 else 0.66, 2 if quality >= 2 else 1, _env())


## Battleground static map: obstacle and canopy chunks (one canvas item per BR_CHUNK cell, so
## the renderer culls everything off screen) and the two baked overview textures. Other modes
## keep the single static and canopy layers.
func _br_static_setup() -> void:
	for n in [_br_obs_root, _br_canopy_root, _br_bake, _br_bake_canopy]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_br_obs_root = null
	_br_canopy_root = null
	_br_bake = null
	_br_bake_canopy = null
	_br_overview = false
	if br == null or arena == null:
		return
	_br_obs_root = Node2D.new()
	_br_obs_root.name = "BrObstacleChunks"
	static_layer.add_child(_br_obs_root)
	_br_canopy_root = Node2D.new()
	_br_canopy_root.name = "BrCanopyChunks"
	canopy_layer.add_child(_br_canopy_root)
	var cols: int = maxi(1, ceili(arena.width / BR_CHUNK))
	var rows: int = maxi(1, ceili(arena.height / BR_CHUNK))
	var obs: Array = []
	var forest: Array = []
	for k in cols * rows:
		obs.append(PackedInt32Array())
		forest.append(PackedInt32Array())
	# Each item goes to the chunk holding its centre (a chunk's canvas rect covers what it draws).
	for i in arena.obs_count:
		if i < arena.obs_gate.size() and arena.obs_gate[i] >= 0:
			continue
		var c: = Vector2((arena.obs_minx[i] + arena.obs_maxx[i]) * 0.5, (arena.obs_miny[i] + arena.obs_maxy[i]) * 0.5)
		var ck: int = clampi(int(c.x / BR_CHUNK), 0, cols - 1) + clampi(int(c.y / BR_CHUNK), 0, rows - 1) * cols
		(obs[ck] as PackedInt32Array).append(i)
	for k2 in arena.forest_x.size():
		var fk: int = clampi(int(arena.forest_x[k2] / BR_CHUNK), 0, cols - 1) + clampi(int(arena.forest_y[k2] / BR_CHUNK), 0, rows - 1) * cols
		(forest[fk] as PackedInt32Array).append(k2)
	for ck2 in cols * rows:
		var ol: PackedInt32Array = obs[ck2]
		if not ol.is_empty():
			var on: = Node2D.new()
			on.draw.connect(func() -> void: ArenaPainter.draw_obstacle_list(on, arena, ol, 1.0, Vector2.ZERO, 2 if quality >= 1 else 1))
			_br_obs_root.add_child(on)
		var fl: PackedInt32Array = forest[ck2]
		if not fl.is_empty():
			var fn: = Node2D.new()
			fn.draw.connect(func() -> void:
				if ArenaPainter.env_shows(_env(), "brush"):
					ArenaPainter.draw_canopy_list(fn, arena, fl, 1.0, Vector2.ZERO, 0.5 if perspective < 0 else 0.66, 2 if quality >= 2 else 1))
			_br_canopy_root.add_child(fn)
	_br_bake = _br_bake_viewport(false, func(ci: CanvasItem) -> void:
		ArenaPainter.draw_floor(ci, arena, BR_BAKE, Vector2.ZERO, 2, _env())
		for i2 in arena.obs_count:
			ArenaPainter.draw_obstacle(ci, arena, i2, BR_BAKE, Vector2.ZERO, 2, true))
	_br_bake_canopy = _br_bake_viewport(true, func(ci: CanvasItem) -> void:
		ArenaPainter.draw_canopy(ci, arena, BR_BAKE, Vector2.ZERO, 0.5 if perspective < 0 else 0.66, 1, _env()))


## A SubViewport that renders paint(canvas item) once at BR_BAKE scale (re-rendered on request).
func _br_bake_viewport(transparent: bool, paint: Callable) -> SubViewport:
	var vp: = SubViewport.new()
	vp.size = Vector2i(ceili(arena.width * BR_BAKE), ceili(arena.height * BR_BAKE))
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var n: = Node2D.new()
	n.draw.connect(func() -> void: paint.call(n))
	vp.add_child(n)
	add_child(vp)
	return vp


## Re-renders the battleground chunks and bakes (switches, quality, perspective: canopy only).
func _br_redraw_static(canopy_only: bool = false) -> void:
	if br == null or _br_obs_root == null:
		return
	var roots: Array = [_br_canopy_root] if canopy_only else [_br_obs_root, _br_canopy_root]
	for root in roots:
		for c in (root as Node).get_children():
			(c as CanvasItem).queue_redraw()
	var bakes: Array = [_br_bake_canopy] if canopy_only else [_br_bake, _br_bake_canopy]
	for vp in bakes:
		(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
		((vp as SubViewport).get_child(0) as CanvasItem).queue_redraw()


func _env() -> ArenaEnv:
	return sim.env if sim else null


## Deathmatch items are public; battleground team views share the team's current sight only.
func field_item_visible(p: Vector2) -> bool:
	return br == null or perspective < 0 or sim.point_seen(perspective, p)


# The same sight boundary is used by the world, hover and minimap.
func _draw_items() -> void:
	if sim == null or sim.deathmatch == null:
		return
	var ci: = item_layer
	var cull: = br != null
	for it in sim.deathmatch.field:
		if cull and not _cull.has_point(it.pos):
			continue
		if not field_item_visible(it.pos):
			continue
		var id: String = str(it.item)
		var d: Dictionary = ItemDefs.get_def(id)
		var rar: int = ItemDefs.rarity_of(id)
		var col: Color = ItemDefs.rarity_color(rar)
		var p: Vector2 = it.pos
		var pop: float = clampf((sim.time - float(it.t)) * 3.0, 0.0, 1.0)
		var c: = p + Vector2(0, sin(anim * 2.4 + float(it.uid)) * 2.0 - 3.0)
		if quality >= 1 and FxSystem.soft_tex:
			var gr: = 24.0 + rar * 6.0
			ci.draw_texture_rect(FxSystem.soft_tex, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, (0.22 + 0.07 * rar) * pop))
		ci.draw_set_transform(p + Vector2(0, 10), 0.0, Vector2(1.0, 0.4))
		ci.draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.35 * pop))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var r: = (11.0 + rar * 1.3) * pop
		if hud_readable:
			# Keep the pickup diamond big enough on screen for its glyph to read.
			r = maxf(r, (8.0 + rar * 0.8) * _inv * pop)
		var pts: = PackedVector2Array([c + Vector2(0, - r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2( - r, 0)])
		ci.draw_colored_polygon(pts, Color(col.darkened(0.6), 0.95))
		pts.append(pts[0])
		ci.draw_polyline(pts, VfxStyle.hdr(col, 1.15 + 0.1 * rar), 2.0, true)
		if rar >= 3:
			var st: = anim * 1.6 + float(it.uid)
			ci.draw_arc(c, r + 6.0, st, st + PI * 1.1, 18, Color(VfxStyle.hdr(col, 1.3), 0.8), 1.6, true)
		if hud_readable:
			_glyph_px(ci, c, str(d.get("glyph", "?")), Color(1, 1, 1, 0.95 * pop), _px(12.0, PX_ICON))
			# Names: rarity >= 3 or hovered; everything once zoomed in (not in the compact overview).
			if show_names and (rar >= 3 or int(it.uid) == _hover_item or (cam_zoom > 1.35 and not _lod)):
				_text(ci, c + Vector2(0, r + _below(13.0, 10.0, PX_SUB)), str(d.get("name", id)), Color(col.lightened(0.25), 0.9 * pop), 10)
			continue
		_glyph(ci, c, str(d.get("glyph", "?")), Color(1, 1, 1, 0.95 * pop), 12)
		if show_names and (cam_zoom > 1.35 or rar >= 3):
			_text(ci, c + Vector2(0, r + 13.0), str(d.get("name", id)), Color(col.lightened(0.25), 0.85 * pop), 10)


func _deathmatch_event(ty: String, ev: Dictionary) -> void:
	match ty:
		"DM_KILL":
			var killer: BUnit = sim.u_at(int(ev.get("killer", -1)))
			var victim: BUnit = sim.u_at(int(ev.get("victim", -1)))
			kill_feed.append({"t": sim.time, "killer": killer.idx if killer else -1, "victim": victim.idx if victim else -1, "execute": false,
				"streak": int(ev.get("streak", 0)), "score": int(ev.get("score", 0)), "assists": (ev.get("assists", []) as Array).size()})
			if br != null:
				(kill_feed.back() as Dictionary).merge({"kind": "kill", "cause": str(ev.get("cause", "kill")), "team": int(ev.get("team", -1))})
			# Battleground squads count streaks per team, not per hero: no streak banner there.
			if killer and killer.alive and int(ev.get("streak", 0)) >= 2 and (br == null or br.squad <= 1):
				var tag: String = {2: "2연속 처치", 3: "3연속 처치!", 4: "4연속 처치!!"}.get(int(ev.streak), "%d연속 · 학살!" % int(ev.streak))
				fx.banner(killer.pos + Vector2(0, -64), tag, VfxStyle.hdr(UITheme.team_color(killer.team), 1.3), 20.0, 1.4)
		"DM_ITEM_PICKED":
			var hero: BUnit = sim.u_at(int(ev.s))
			var id: String = str(ev.get("item", ""))
			if hero:
				var col: Color = ItemDefs.rarity_color(ItemDefs.rarity_of(id))
				fx.ring(hero.pos, VfxStyle.hdr(col, 1.4), 10.0, 52.0, 0.5, 2.5)
				fx.text(hero.pos + Vector2(0, -46), "+ " + str(ItemDefs.get_def(id).get("name", id)), col.lightened(0.2), 15, 1.3)
				if ItemDefs.rarity_of(id) >= 3:
					fx.burst(hero.pos, VfxStyle.hdr(col, 1.5), 22, 60.0, 220.0, 2.4, 0.7, 2.6)
				_sfx("coin", 0.3, 1.0 + 0.06 * ItemDefs.rarity_of(id))
		"DM_ITEM_SKIPPED":
			var h2: BUnit = sim.u_at(int(ev.s))
			if h2 and h2.idx == selected and throttle("skip:%d" % h2.idx, 2.0):
				fx.text(h2.pos + Vector2(0, -44), str(ev.get("reason", "")).split(" — ")[0], Color(0.8, 0.84, 0.9, 0.85), 12, 1.4)
		"DM_ITEM_DROPPED":
			var p: Vector2 = ev.get("pos", Vector2.ZERO)
			var col2: Color = ItemDefs.rarity_color(ItemDefs.rarity_of(str(ev.get("item", ""))))
			fx.ring(p, col2, 4.0, 30.0, 0.45, 2.0)
		"DM_ITEM_PROC":
			var h3: BUnit = sim.u_at(int(ev.s))
			var p3: Vector2 = ev.get("pos", h3.pos if h3 else Vector2.ZERO)
			var col3: Color = ItemDefs.rarity_color(ItemDefs.rarity_of(str(ev.get("item", ""))))
			fx.ring(p3, VfxStyle.hdr(col3, 1.5), 6.0, float(ev.get("radius", 40.0)), 0.35, 2.5)
			if str(ev.get("item", "")) == "m_thunder":
				fx.flash(p3, Color(1.4, 1.4, 2.0), 70.0, 0.2)
		"DM_REVIVE":
			var h4: BUnit = sim.u_at(int(ev.g))
			if h4:
				fx.ring(h4.pos, VfxStyle.hdr(Color("#ff7b5c"), 1.6), 10.0, 110.0, 0.8, 4.0)
				fx.banner(h4.pos + Vector2(0, -60), "불사조 부활!", Color("#ffb08a"), 22.0, 1.4)
		"DM_ITEM_SPAWNED":
			if not bool(ev.get("silent", false)):
				var p5: Vector2 = ev.get("pos", Vector2.ZERO)
				fx.ring(p5, ItemDefs.rarity_color(int(ev.get("rarity", 0))), 2.0, 26.0, 0.5, 2.0)


## V2 battleground events (DESIGN_V2 §3.5; already filtered by _ev_vis: knocks and revives only
## for observers, team-outs and the zone for everyone): kill feed entries and world effects.
func _battleground_event(ty: String, ev: Dictionary) -> void:
	var src: BUnit = sim.u_at(int(ev.get("s", -1)))
	var tgt: BUnit = sim.u_at(int(ev.get("g", -1)))
	match ty:
		"BR_DOWNED":
			kill_feed.append({"t": sim.time, "kind": "knock", "killer": src.idx if src else -1, "victim": tgt.idx if tgt else -1,
				"team": int(ev.get("team", -1)), "zone": bool(ev.get("zone", false)), "streak": 0, "score": 0})
			if tgt:
				fx.ring(tgt.pos, Color(1.6, 0.4, 0.4), 10.0, 70.0, 0.5, 3.0)
				fx.banner(tgt.pos + Vector2(0, -58), "다운", Color("#ff8a8a"), 20.0, 1.2)
				_sfx("cc", 0.35, 0.8)
		"BR_REVIVED":
			kill_feed.append({"t": sim.time, "kind": "revive", "killer": src.idx if src else -1, "victim": tgt.idx if tgt else -1,
				"team": int(ev.get("team", -1)), "streak": 0, "score": 0})
			if tgt:
				fx.ring(tgt.pos, VfxStyle.hdr(UITheme.GOOD, 1.5), 8.0, 90.0, 0.7, 4.0)
				fx.banner(tgt.pos + Vector2(0, -58), "소생!", UITheme.GOOD, 22.0, 1.3)
				_sfx("heal", 0.35, 1.1)
		"BR_REVIVE_START":
			if tgt:
				fx.ring(tgt.pos, Color(UITheme.GOOD, 0.8), 6.0, 40.0, 0.4, 2.0)
		"BR_REVIVE_CANCEL":
			if tgt and str(ev.get("reason", "")) in ["damage", "cc", "range"]:
				fx.text(tgt.pos + Vector2(0, -44), "소생 끊김", Color(0.85, 0.88, 0.95, 0.9), 13, 1.1)
		"BR_TEAM_OUT":
			kill_feed.append({"t": sim.time, "kind": "team_out", "killer": -1, "victim": -1, "team": int(ev.get("team", -1)),
				"place": int(ev.get("place", 0)), "streak": 0, "score": 0})
		"BR_ZONE_ANNOUNCE", "BR_ZONE_SHRINK":
			kill_feed.append({"t": sim.time, "kind": "zone", "killer": -1, "victim": -1, "phase": int(ev.get("phase", 0)),
				"state": "announce" if ty == "BR_ZONE_ANNOUNCE" else "shrink", "shrink_start": float(ev.get("shrink_start", sim.time)),
				"shrink_end": float(ev.get("shrink_end", sim.time)), "dps_ratio": float(ev.get("dps_ratio", 0.0)), "streak": 0, "score": 0})


func _arena_size() -> Vector2:
	return Vector2(arena.width, arena.height) if arena else Vector2(1408, 792)


func _draw_objectives() -> void:
	if br != null:
		# V2 battleground zone (public): tint outside, edge, next circle.
		ArenaPainter.draw_br_zone(objective_layer, arena, _zone_view, 1.0 / maxf(0.01, view_scale), anim)
		return
	if sim == null or not sim.is_control_mode() or sim.domination == null:
		return
	var ci: CanvasItem = objective_layer
	for point in sim.domination.points:
		var center: Vector2 = point.center
		var radius: float = float(point.radius)
		var owner: int = int(point.owner)
		var contested: bool = bool(point.contested)
		var col: Color = UITheme.team_color(owner) if owner >= 0 else Color("#b0ad95")
		var edge: Color = UITheme.GOLD if contested else col
		ci.draw_circle(center, radius, Color(col, 0.075))
		ci.draw_arc(center, radius, 0, TAU, 80, Color(edge, 0.8), 2.2, true)
		ci.draw_arc(center, radius - 7.0, 0, TAU, 80, Color(col, 0.2), 1.2, true)
		for k in 12:
			var a: float = TAU * float(k) / 12.0
			var direction: Vector2 = Vector2.from_angle(a)
			ci.draw_line(center + direction * (radius - 2), center + direction * (radius + 7), Color(edge, 0.65), 2, true)
		var progress: float = float(point.progress)
		if absf(progress) > 0.001:
			ci.draw_arc(center, radius + 4, -PI * 0.5, -PI * 0.5 + TAU * absf(progress), 64, UITheme.BLUE if progress < 0 else UITheme.RED, 5, true)
		var lr: = 19.0
		if hud_readable:
			lr = maxf(lr, 12.0 * _inv)
		var label_pos: Vector2 = center + Vector2(0, -radius - 9.0 - lr)
		ci.draw_circle(label_pos, lr, Color(0.025, 0.04, 0.06, 0.94))
		ci.draw_arc(label_pos, lr, 0, TAU, 32, edge, 1.8, true)
		if hud_readable and 23.0 * hud_scale <= 28.5:
			var mpx: = _px(23.0, PX_MARK)
			_text_px(ci, label_pos + Vector2(0, mpx * 0.36 * _inv), str(point.id), edge, mpx)
		else:
			_text(ci, label_pos + Vector2(0, 7), str(point.id), edge, 23)
		if contested:
			_text(ci, center + Vector2(0, radius + _below(28.0, 19.0, PX_CALL)), "경합 · 득점 정지", UITheme.GOLD, 19, PX_CALL)
	for zone in sim.domination.heal_zones:
		var center: Vector2 = zone.center
		var radius: float = float(zone.radius)
		var remaining: float = maxf(0.0, float(zone.ready_at) - sim.time)
		var ready: bool = remaining <= 0.0
		var col: Color = UITheme.GOOD if ready else Color("#667b83")
		ci.draw_circle(center, radius, Color(col, 0.055 if ready else 0.025))
		ci.draw_arc(center, radius, 0, TAU, 48, Color(col, 0.48), 1.7, true)
		ci.draw_circle(center, 22, Color(0.025, 0.045, 0.06, 0.84))
		ci.draw_line(center - Vector2(11, 0), center + Vector2(11, 0), Color(col, 0.95), 5, true)
		ci.draw_line(center - Vector2(0, 11), center + Vector2(0, 11), Color(col, 0.95), 5, true)
		if not ready:
			var fraction: float = clampf(1.0 - remaining / maxf(0.1, float(zone.get("cooldown", 25.0))), 0.0, 1.0)
			ci.draw_arc(center, radius + 3, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, Color(UITheme.GOOD, 0.75), 3.0, true)
		_text(ci, center + Vector2(0, radius + _below(25.0, 18.0, PX_NAME)), "회복 가능" if ready else "회복 %.0f초" % ceilf(remaining), col, 18, PX_NAME)
	for hero in sim.heroes:
		if hero.alive and _vis(hero) and sim.has_status(hero, &"spawn_protection"):
			ci.draw_arc(upos(hero), sim.radius(hero) + 10, anim * 2.0, anim * 2.0 + TAU * 0.85, 40, Color(UITheme.GOOD, 0.7), 3, true)
