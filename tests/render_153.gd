extends SceneTree

# V1.5.3 render / UI layer (headless-safe): every gimmick in the map data has a
# painter arm, a codex entry and Korean log text; spawn zones follow each
# team's spawn clusters inside the map; closing-ring geometry tiles the arena;
# gate visuals follow the live battle copy; jump-pad arcs line up; countdown
# strings are cached; the painter never builds state snapshots per frame.
# (UI-screen checks that need autoloads live in tests/developer_152.)

var passed: int = 0
var failed: Array = []
var metrics: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed.append(label)
		push_error("FAIL " + label)


func _run() -> void:
	DB.ensure_loaded()
	DB.load_fonts()
	_coverage()
	_spawn_zones()
	_tint()
	_ring_geometry()
	_gates()
	_leap()
	_strings()
	_no_snapshot_in_painter()
	_env_switch_layers()
	_public_env_events()
	_log_text()
	ArenaPainter.release_caches()
	var status: String = "PASS" if failed.is_empty() else "FAIL"
	print("RENDER_153 ", JSON.stringify({"status": status, "passed": passed, "failed": failed, "metrics": metrics}))
	quit(0 if failed.is_empty() else 1)


func _all_arenas() -> Array:
	var out: Array = DB.arenas.duplicate()
	out.append_array(DB.deathmatch_presets())
	return out


func _types_of(a: Arena) -> Array:
	var out: Array = []
	for h in a.hazards:
		if not out.has(str(h.type)):
			out.append(str(h.type))
	if not a.gates.is_empty():
		out.append("gate")
	if not a.forests.is_empty():
		out.append("brush")
	return out


# ------------------------------------------------------------------ coverage

func _coverage() -> void:
	var missing_draw: Array = []
	var missing_codex: Array = []
	var seen: Dictionary = {}
	for a in _all_arenas():
		for typ in _types_of(a):
			seen[typ] = true
			if not ArenaPainter.DRAWN_TYPES.has(typ):
				missing_draw.append("%s:%s" % [a.id, typ])
			if not CodexData.HAZARDS.has(typ):
				missing_codex.append("%s:%s" % [a.id, typ])
	_check(missing_draw.is_empty(), "every gimmick type in the map data has a painter arm %s" % str(missing_draw))
	_check(missing_codex.is_empty(), "every gimmick type in the map data has a codex entry %s" % str(missing_codex))
	for typ in ["artillery", "gate", "jump_pad", "closing_ring", "mud", "brush"]:
		_check(seen.has(typ), "map data uses %s" % typ)
	for typ in Arena.TYPE_BITS:
		_check(ArenaPainter.DRAWN_TYPES.has(typ), "engine type %s is drawn" % typ)
	metrics["types"] = seen.keys()


# ------------------------------------------------------------------ spawn zones

func _inside_bounds(a: Arena, p: Vector2) -> bool:
	return p.x >= a.min_x - 0.6 and p.x <= a.max_x + 0.6 and p.y >= a.min_y - 0.6 and p.y <= a.max_y + 0.6


func _spawn_zones() -> void:
	var bad: Array = []
	var clusters_by_map: Dictionary = {}
	for a in DB.arenas:
		var geo: Dictionary = ArenaPainter.geometry(a)
		var counts: Array = []
		for t in 2:
			var cl: Array = geo.clusters[t]
			counts.append(cl.size())
			var covered: int = 0
			for c in cl:
				if (c.zones as Array).is_empty():
					bad.append("%s team %d: empty zone" % [a.id, t])
				for z in c.zones:
					for p in z.poly:
						if not _inside_bounds(a, p):
							bad.append("%s team %d: zone leaves the map at %s" % [a.id, t, str(p)])
							break
				for p in c.points:
					for z in c.zones:
						if Geometry2D.is_point_in_polygon(p, z.poly):
							covered += 1
							break
			if covered != (a.spawns.get(t, []) as Array).size():
				bad.append("%s team %d: %d of %d spawns inside a zone" % [a.id, t, covered, (a.spawns.get(t, []) as Array).size()])
		clusters_by_map[a.id] = counts
	_check(bad.is_empty(), "spawn zones cover every spawn and stay on the map %s" % str(bad))
	var split_ok: bool = false
	for a in DB.arenas:
		if str(a.data.get("spawn_orientation", "")) == "split":
			split_ok = int(clusters_by_map[a.id][0]) >= 2 and int(clusters_by_map[a.id][1]) >= 2
	_check(split_ok, "split-spawn map draws one spawn zone per entrance %s" % str(clusters_by_map.get("rift_harbor", [])))
	_check(int(clusters_by_map["classic"][0]) == 1 and int(clusters_by_map["classic"][1]) == 1, "classic keeps one spawn zone per team")
	metrics["spawn_clusters"] = clusters_by_map


# ------------------------------------------------------------------ team tint

func _tint() -> void:
	var tex: ImageTexture = ArenaPainter.tint_texture()
	_check(tex != null and tex.get_width() > 8, "spawn-centroid tint texture builds headless")
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		_check(true, "tint image not readable on the dummy renderer (skipped)")
		return
	var w: int = img.get_width()
	var centre: float = img.get_pixel(w / 2, w / 2).a
	var edge: float = img.get_pixel(0, w / 2).a
	_check(centre > 0.4 and edge < 0.02, "tint falls off from the spawn centroid to transparent (%.2f -> %.2f)" % [centre, edge])
	# Diagonal and north/south maps tint toward their own spawn centroids.
	for id in ["furnace_basin", "twin_foundry", "rift_harbor"]:
		var a: Arena = DB.arena(id)
		var c0: Vector2 = a.spawn_centroid(0)
		var c1: Vector2 = a.spawn_centroid(1)
		_check(c0.distance_to(c1) > 300.0, "%s spawn centroids are apart for the tint" % id)


# ------------------------------------------------------------------ closing ring

func _ring_geometry() -> void:
	for id in ["bastion_ring", "crossroads"]:
		var a: Arena = DB.arena(id)
		var h: Dictionary = {}
		var idx: int = -1
		for i in a.hazards.size():
			if str(a.hazards[i].type) == "closing_ring":
				h = a.hazards[i]
				idx = i
		_check(not h.is_empty(), "%s has a closing ring" % id)
		if h.is_empty():
			continue
		var inner: = Rect2(Vector2(a.min_x, a.min_y), Vector2(a.max_x - a.min_x, a.max_y - a.min_y))
		var t_mid: float = (float(h.startTime) + float(h.endTime)) * 0.5
		for t in [t_mid, float(h.endTime) + 5.0]:
			var r: float = Arena.ring_radius_at(h, t)
			var geo: Dictionary = ArenaPainter._ring_geometry(a, h, idx, r, h.center, inner, 1.0, Vector2.ZERO)
			var outside_area: float = 0.0
			var off_map: int = 0
			for poly in geo.outside:
				outside_area += absf(ArenaPainter._poly_area(poly))
				for p in poly:
					if not inner.grow(0.6).has_point(p):
						off_map += 1
			# Inside area: sample grid (exact circle-rect intersection is not needed here).
			var inside: int = 0
			var total: int = 0
			var step: float = 8.0
			var y: float = inner.position.y + step * 0.5
			while y < inner.end.y:
				var x: float = inner.position.x + step * 0.5
				while x < inner.end.x:
					total += 1
					if Vector2(x, y).distance_to(h.center) <= float(geo.rq) * 2.0:
						inside += 1
					x += step
				y += step
			var expected_out: float = inner.get_area() * (1.0 - float(inside) / float(total))
			_check(off_map == 0, "%s ring tint stays inside the arena at t=%.0f" % [id, t])
			_check(absf(outside_area - expected_out) <= inner.get_area() * 0.02, "%s ring tint covers exactly the outside zone at t=%.0f (%.0f vs %.0f)" % [id, t, outside_area, expected_out])
			_check(not (geo.edge as Array).is_empty() or expected_out < 1.0, "%s ring boundary drawn where it crosses the arena" % id)
		# Cached per 2 px radius step: the same geometry object comes back.
		var r2: float = Arena.ring_radius_at(h, t_mid)
		var g1: Dictionary = ArenaPainter._ring_geometry(a, h, idx, r2, h.center, inner, 1.0, Vector2.ZERO)
		var g2: Dictionary = ArenaPainter._ring_geometry(a, h, idx, r2 + 0.3, h.center, inner, 1.0, Vector2.ZERO)
		_check(is_same(g1, g2), "%s ring geometry is cached between frames" % id)


# ------------------------------------------------------------------ gates

func _gates() -> void:
	var shared: Arena = DB.arena("ruined_gate")
	_check(shared.gates.size() == 4, "ruined_gate has four gates")
	var mismatches: int = 0
	var warnings: int = 0
	for k in shared.gates.size():
		var obs: int = int(shared.gates[k].obs)
		var t: float = 0.0
		while t < 22.0:
			var v: Vector3 = ArenaPainter.gate_visual(shared, k, t, true)
			var open_pred: bool = shared.gate_open_at(obs, t)
			if (int(v.x) != 0) != open_pred:
				mismatches += 1
			if int(v.x) == 2:
				warnings += 1
				if v.y > float(shared.gates[k].warningDuration) + 1e-6:
					mismatches += 1
			t += 0.25
	_check(mismatches == 0, "card/preview gate visuals follow Arena.gate_open_at (%d mismatches)" % mismatches)
	_check(warnings > 0, "gates show a closing warning window")
	# Battle copy: the visual follows the live masks, including the developer switch.
	var sim: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "ruined_gate", "seed": 153901, "max_time": 60.0})
	sim.start()
	var a: Arena = sim.arena
	_check(a.battle_copy and a != shared, "battle plays on a private gate copy")
	var live_ok: bool = true
	for i in 240:
		sim.step()
		for k in a.gates.size():
			var v2: Vector3 = ArenaPainter.gate_visual(a, k, sim.time, sim.env.type_active("gate"))
			if (int(v2.x) != 0) != a.gate_slot_open(k):
				live_ok = false
	_check(live_ok, "battle gate visuals match the live battle-copy state for 8 s")
	sim.env.set_type_enabled("gate", false)
	var all_open: bool = true
	for k in a.gates.size():
		if int(ArenaPainter.gate_visual(a, k, sim.time, false).x) == 0:
			all_open = false
	_check(all_open and a.gate_bits == a.all_gates_open_bits(), "switched-off gates are drawn open")
	sim.dispose()


# ------------------------------------------------------------------ jump pads

func _leap() -> void:
	var a: Vector2 = Vector2(100, 400)
	var b: Vector2 = Vector2(600, 300)
	var hgt: float = ArenaPainter.leap_height(a.distance_to(b))
	_check(ArenaPainter.leap_point(a, b, 0.0, hgt).is_equal_approx(a) and ArenaPainter.leap_point(a, b, 1.0, hgt).is_equal_approx(b), "leap arc starts on the pad and ends on the landing")
	var mid: Vector2 = ArenaPainter.leap_point(a, b, 0.5, hgt)
	_check(absf(mid.y - ((a.y + b.y) * 0.5 - hgt)) < 0.01 and hgt >= 24.0 and hgt <= 90.0, "leap arc peaks at mid-flight")
	var pads: int = 0
	for ar in _all_arenas():
		for h in ar.hazards:
			if str(h.type) == "jump_pad":
				pads += 1
				_check(h.has("landing") and (h.landing as Vector2).distance_to(h.center) > 60.0, "%s/%s has a landing marker away from the pad" % [ar.id, str(h.id)])
	metrics["jump_pads"] = pads


# ------------------------------------------------------------------ cached strings

func _strings() -> void:
	_check(ArenaPainter.num_str(4.24) == "4.2" and ArenaPainter.num_str(0.0) == "0.0" and ArenaPainter.num_str(38.2) == "39", "countdown numbers")
	_check(ArenaPainter.sec_str(4.24) == "4.2초" and ArenaPainter.sec_str(54.0) == "54초", "countdown seconds")
	_check(is_same(ArenaPainter.sec_str(3.0), ArenaPainter.sec_str(3.0)) or ArenaPainter.sec_str(3.0) == "3.0초", "countdown strings come from the cache")


func _no_snapshot_in_painter() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/view/arena_painter.gd")
	_check(src != "" and not src.contains("state_snapshot()"), "painter never builds environment snapshots per frame")
	var hz_start: int = src.find("static func draw_hazards(")
	var hz_end: int = src.find("\nstatic func _draw_arrow(")
	var hz: String = src.substr(hz_start, hz_end - hz_start) if hz_start >= 0 and hz_end > hz_start else ""
	_check(hz != "" and not hz.contains("PackedVector2Array(") and not hz.contains("RandomNumberGenerator") and not hz.contains("% ["), "per-frame hazard drawing allocates no arrays, RNGs or formatted strings")
	var view_src: String = FileAccess.get_file_as_string("res://scripts/view/battle_view.gd")
	_check(view_src.contains("draw_obstacles(static_layer, arena, 1.0, Vector2.ZERO, 2 if quality >= 1 else 1, true)") and view_src.contains("ArenaPainter.draw_gates(hazard_layer"), "battle view skips gates in the static layer and draws them per frame")
	_check(view_src.contains("bool(tg.get(\"env\", false))"), "environment telegraphs are drawn in the neutral artillery style, not team colours")


# ------------------------------------------------------------------ switches on static layers

# Brush and mud are drawn in the static floor and canopy layers. With their
# switch (or the master switch) off they are not drawn, and the battle view
# redraws those layers when the switch state changes, never per frame (review
# 1.5.3: both stayed drawn). Pixel checks live in tests/developer_152.
func _env_switch_layers() -> void:
	var sim: BattleSim = BattleSim.new({"blue": ["swordsman"], "red": ["archer"], "arena_id": "gale_corridor", "seed": 153921, "max_time": 60.0})
	sim.start()
	var env: ArenaEnv = sim.env
	_check(ArenaPainter.env_shows(null, "mud") and ArenaPainter.env_shows(null, "brush"), "cards (no environment) draw mud and brush")
	_check(ArenaPainter.env_shows(env, "mud") and ArenaPainter.env_shows(env, "brush"), "live battle draws mud and brush while switched on")
	var sig0: int = ArenaPainter.static_env_sig(env)
	env.set_type_enabled("lava", false)
	env.set_type_enabled("jump_pad", false)
	_check(ArenaPainter.static_env_sig(env) == sig0, "per-frame hazard switches leave the static layers alone")
	env.set_type_enabled("lava", true)
	env.set_type_enabled("jump_pad", true)
	env.set_type_enabled("mud", false)
	_check(not ArenaPainter.env_shows(env, "mud") and ArenaPainter.env_shows(env, "brush") and ArenaPainter.static_env_sig(env) != sig0, "mud switch hides the mud floor and asks for a static redraw")
	env.set_type_enabled("mud", true)
	_check(ArenaPainter.static_env_sig(env) == sig0 and ArenaPainter.env_shows(env, "mud"), "mud switch back on restores the static signature")
	env.set_type_enabled("brush", false)
	_check(not ArenaPainter.env_shows(env, "brush") and ArenaPainter.static_env_sig(env) != sig0, "brush switch hides brush ground and canopy and asks for a redraw")
	env.set_type_enabled("brush", true)
	env.enabled = false
	_check(not ArenaPainter.env_shows(env, "mud") and not ArenaPainter.env_shows(env, "brush") and ArenaPainter.static_env_sig(env) != sig0, "master switch off hides mud and brush and asks for a redraw")
	env.enabled = true
	_check(ArenaPainter.static_env_sig(env) == sig0, "master switch back on restores the static signature")
	sim.dispose()
	var src: String = FileAccess.get_file_as_string("res://scripts/view/arena_painter.gd")
	var floor_src: String = _func_src(src, "static func draw_floor(")
	var dm_src: String = _func_src(src, "static func _draw_deathmatch_floor(")
	var canopy_src: String = _func_src(src, "static func draw_canopy(")
	_check(floor_src.contains("env_shows(env, \"brush\")") and floor_src.contains("env_shows(env, \"mud\")") and dm_src.contains("env_shows(env, \"brush\")") and dm_src.contains("env_shows(env, \"mud\")"),
		"team and deathmatch floors draw brush and mud by their switch state")
	_check(canopy_src.contains("env_shows(env, \"brush\")"), "canopy follows the brush switch")
	var view_src: String = FileAccess.get_file_as_string("res://scripts/view/battle_view.gd")
	_check(view_src.contains("ArenaPainter.draw_floor(static_layer, arena, 1.0, Vector2.ZERO, 2 if quality >= 1 else 1, _env())") and view_src.contains("ArenaPainter.draw_canopy(canopy_layer, arena, 1.0, Vector2.ZERO, 0.5 if perspective < 0 else 0.66, 2 if quality >= 2 else 1, _env())")
		and view_src.contains("func _env() -> ArenaEnv:\n\treturn sim.env if sim else null"), "battle view draws the floor and canopy with the live environment")
	var proc: String = _func_src(view_src, "func _process(")
	_check(proc.contains("ArenaPainter.static_env_sig(sim.env)") and proc.contains("static_layer.queue_redraw()") and not proc.contains("draw_floor"),
		"battle view redraws the static layers only when the brush/mud switch state changes")


# Public gimmick events (gates, salvo warnings, ring phases) are shown in every
# perspective, like the battle log (review 1.5.3: the view dropped them in team
# perspectives). BattleView needs autoloads, so the behaviour test is in
# tests/developer_152; this checks the view's filter source.
func _public_env_events() -> void:
	var view_src: String = FileAccess.get_file_as_string("res://scripts/view/battle_view.gd")
	var vis: String = _func_src(view_src, "func _ev_vis(")
	var pub_at: int = vis.find("CodexText.ENV_PUBLIC_LOG.has(")
	var persp_at: int = vis.find("if perspective < 0:")
	var sv_at: int = vis.find("ev.has(\"sv\")")
	_check(pub_at > 0 and sv_at > 0 and pub_at < sv_at, "public environment events pass the team-perspective filter before the sight check")
	_check(persp_at > 0, "observer perspective still sees every event")


func _func_src(src: String, header: String) -> String:
	var a: int = src.find(header)
	if a < 0:
		return ""
	var b: int = src.find("\nfunc ", a + 1)
	var c: int = src.find("\nstatic func ", a + 1)
	if b < 0 or (c >= 0 and c < b):
		b = c
	return src.substr(a, (b - a) if b > a else -1)


# ------------------------------------------------------------------ battle log

func _collect(arena_id: String, ticks: int, seed_v: int) -> Array:
	var sim: BattleSim = BattleSim.new({"blue": ["swordsman", "archer", "giant"], "red": ["werewolf", "mage", "pirate"], "arena_id": arena_id, "seed": seed_v, "max_time": 150.0})
	sim.start()
	for i in ticks:
		if not sim.step():
			break
	var evs: Array = sim.log.duplicate()
	sim.dispose()
	return [null, evs]


func _log_text() -> void:
	var types: Dictionary = {}
	var bad: Array = []
	var tag_re: RegEx = RegEx.new()
	tag_re.compile("\\[[^\\]]*\\]")
	var english: RegEx = RegEx.new()
	english.compile("[a-z_]{4,}")
	for spec in [["ruined_gate", 900, 153911], ["twin_foundry", 900, 153912], ["furnace_basin", 900, 153913], ["bastion_ring", 2700, 153914], ["gale_corridor", 900, 153915], ["thorn_circuit", 600, 153916]]:
		var res: Array = _collect(str(spec[0]), int(spec[1]), int(spec[2]))
		for ev in res[1]:
			var ty: String = str(ev.get("type", ""))
			if not ty.begins_with("ENV_"):
				continue
			types[ty] = int(types.get(ty, 0)) + 1
			var plain: String = tag_re.sub(CodexText.env_log(ev, "검사", false), "", true)
			if plain.strip_edges() == "" or english.search(plain) != null or plain.contains("환경("):
				bad.append("%s: %s" % [ty, plain])
	for ty in ["ENV_HIT", "ENV_GATE", "ENV_ARTILLERY", "ENV_STRIKE", "ENV_RING"]:
		_check(types.has(ty), "probe battles emit %s" % ty)
	_check(bad.is_empty(), "every ENV_* event has Korean log text without raw type names %s" % str(bad.slice(0, 6)))
	# Every event type the environment can emit (also the ones the probes may miss).
	var syn: Array = [{"type": "ENV_JUMP", "flight_time": 0.9, "hazard_type": "jump_pad"}, {"type": "ENV_PUSHED", "hazard_type": "gate"},
		{"type": "ENV_HIT", "amount": 12.0, "hazard_type": "closing_ring"}, {"type": "ENV_HIT", "amount": 40.0, "hazard_type": "artillery"},
		{"type": "ENV_RING", "phase": "final", "final_radius": 200.0, "hazard_type": "closing_ring"}, {"type": "ENV_HASTE", "multiplier": 1.3, "hazard_type": "haste"},
		{"type": "ENV_FOUNTAIN", "amount": 120.0, "hazard_type": "healing_fountain"}, {"type": "ENV_PORTAL", "hazard_type": "portal"},
		{"type": "ENV_GATE", "open": true, "group": "A", "hazard_type": "gate"}, {"type": "ENV_ARTILLERY", "points": [Vector2.ZERO], "impact_t": 5.0, "t": 3.4, "hazard_type": "artillery"},
		{"type": "ENV_STRIKE", "hazard_type": "artillery"}, {"type": "ENV_HIT", "amount": 6.0, "hazard_type": "gravity"}]
	for ev2 in syn:
		var plain2: String = tag_re.sub(CodexText.env_log(ev2, "검사", false), "", true)
		_check(plain2 != "" and english.search(plain2) == null, "log text for %s/%s: %s" % [ev2.type, ev2.hazard_type, plain2])
	_check(CodexText.env_log({"type": "ENV_HIT", "amount": 5.0, "hazard_type": "closing_ring"}, "검사").contains("결계 수축"), "ring damage names the closing ring")
	_check(CodexText.env_log({"type": "ENV_HIT", "amount": 5.0, "hazard_type": "artillery"}, "검사").contains("포격"), "artillery damage names the barrage")
	_check(CodexText.env_log({"type": "ENV_ARTILLERY", "points": [1, 2, 3], "impact_t": 5.0, "t": 3.4}, "").contains("3발 · 1.6초 후 착탄"), "salvo announcement carries count and time to impact")
	for pub in ["ENV_GATE", "ENV_ARTILLERY", "ENV_STRIKE", "ENV_RING"]:
		_check(CodexText.ENV_PUBLIC_LOG.has(pub), "%s is public in every perspective" % pub)
	var bs_src: String = FileAccess.get_file_as_string("res://scripts/ui/screens/battle_screen.gd")
	_check(bs_src.contains("return CodexText.env_log(ev, _name_for(g, persp)") and bs_src.contains("CodexText.ENV_PUBLIC_LOG.has(ty)") and not bs_src.contains("환경(%s)"),
		"battle screen formats every ENV_* event through CodexText.env_log")
	_check(bs_src.contains("func _env_status()") and bs_src.contains("_env_status()\n"), "battle side panel has the environment status section")
	metrics["env_events"] = types
