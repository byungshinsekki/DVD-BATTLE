class_name ArenaEnv
extends RefCounted

# Per-battle environment state. The Arena (shared DB definition or, for gated
# maps, a private battle copy) only holds authored data and pure time
# functions; cooldowns, artillery strikes and toggles live here.
#
# V1.5.3 public API
#   enabled                               developer "환경 기믹" switch (all types).
#   set_type_enabled(type, on)            per-type switch (default all on). Types:
#                                         Arena.TYPE_BITS keys (lava ... mud, brush, gate).
#   is_type_enabled(type) -> bool         per-type switch state only.
#   type_active(type) -> bool             enabled and is_type_enabled(type).
#   artillery_state() -> Array            pending strikes [{id, pos, radius, impact_t, warn_t}]
#                                         (shared read-only array, rebuilt on change). Strike
#                                         centres always lie inside the hazard's area shape and
#                                         the arena bounds, outside solid obstacles. Strikes fall
#                                         from the sky: walls give no cover from the blast.
#   nav_signature(t) -> int               navigation gate signature at t under the switches
#                                         (what arena.nav_sig holds once the battle runs).
#   hazard_penalty(p, t, r)               Arena.hazard_penalty with the toggles applied plus
#                                         announced artillery strike circles.
#   expected_hazard_damage(p, t, r, horizon, u = null)
#                                         same for damage; u gives the max HP for the ring.
#   portal_wait(u) / pad_wait(u) -> float seconds until u's own environment portal /
#                                         jump-pad cooldown ends (LINK_OFF when the type is off);
#                                         Navigator.unit_waypoint uses them as link costs.
#   state_snapshot() / public_fountains() / benefit_at(p, u)   public rows (no occupants).
#                                         Gate rows: {type "gate", id, group, open, warning,
#                                         remaining, center}; artillery rows add pending_strikes,
#                                         next_impact_t, strike_radius; ring rows safe_radius,
#                                         final_radius, start_time, end_time; jump_pad landing,
#                                         flight_time; mud slow.
# Events (all carry "hazard" and "hazard_type"): ENV_HIT, ENV_HASTE, ENV_FOUNTAIN,
# ENV_PORTAL, ENV_GATE (gate opened/closed), ENV_PUSHED (unit pushed out of a
# closing gate), ENV_ARTILLERY (salvo announced: points, impact_t), ENV_STRIKE
# (one strike landed), ENV_JUMP (jump-pad launch), ENV_RING (ring starts
# shrinking / reaches its final radius).

const PAD_COOLDOWN: = 2.0
const MUD_SLOW_DURATION: = 0.45
const STRIKE_BODY_FACTOR: = 0.3

var sim: BattleSim
var cooldowns: Dictionary = {}
var enabled: bool = true:
	set(value):
		enabled = value
		_on_toggle()
# OR of Arena.type_bit(type) for types switched off in the developer lab.
var disabled_mask: int = 0
# Pending artillery strikes: {hazard, h, pos, radius, warn_t, impact_t, cycle, tg}.
var strikes: Array = []
var _salvo_cycle: Dictionary = {}
var _ring_phase: Dictionary = {}
var _arena: Arena = null
var _gates_bound: bool = false
var _has_artillery: bool = false
var _has_ring: bool = false
var _art_state: Array = []


func _init(s: BattleSim) -> void :
	sim = s


func set_type_enabled(type: String, on: bool) -> void:
	var bit: int = Arena.type_bit(type)
	if bit == 0:
		return
	if on:
		disabled_mask &= ~bit
	else:
		disabled_mask |= bit
	_on_toggle()


func is_type_enabled(type: String) -> bool:
	return (disabled_mask & Arena.type_bit(type)) == 0


func type_active(type: String) -> bool:
	return enabled and (disabled_mask & Arena.type_bit(type)) == 0


# Effective skip mask for Arena helpers (everything when globally disabled).
func skip_mask() -> int:
	return disabled_mask if enabled else -1


func _on_toggle() -> void:
	if sim == null:
		return
	if not type_active("haste"):
		for u in sim.heroes:
			sim.remove_buffs_tag(u, "environment_haste")
	if not type_active("mud"):
		for u in sim.heroes:
			sim.remove_statuses_where(u, func(x): return x.type == &"slow" and bool(x.extra.get("mud", false)))
	if not type_active("artillery"):
		_cancel_strikes()
	sim.brush_on = type_active("brush")
	if sim.arena:
		_sync_gates()


# Called by BattleSim.start() so gates hold their t=0 state before any AI
# planning; also re-binds when a test swaps sim.arena.
func prepare() -> void:
	if sim == null or sim.arena == null:
		return
	if sim.arena != _arena:
		_bind()
	_sync_gates()


func _bind() -> void:
	_arena = sim.arena
	_gates_bound = false
	_has_artillery = false
	_has_ring = false
	for h in _arena.hazards:
		var typ: String = str(h.type)
		_has_artillery = _has_artillery or typ == "artillery"
		_has_ring = _has_ring or typ == "closing_ring"
	_cancel_strikes()
	_salvo_cycle.clear()
	_ring_phase.clear()
	sim.brush_on = type_active("brush")


func update(dt: float) -> void :
	if sim.arena != _arena:
		_bind()
	if not _arena.gates.is_empty():
		_sync_gates()
	if not enabled:
		return
	var hazards: Array = sim.arena.hazards
	if hazards.is_empty():
		return
	if _has_artillery:
		_update_artillery()
	if _has_ring:
		_update_ring_phases()
	# One charge is shared by both teams; collection is decided independently
	# of array iteration order and never stored in the shared Arena definition.
	# Rebuilt every tick (one pass over the hazards): tests and the lab may
	# edit a hazard in place.
	_index_hazards(hazards)
	if type_active("healing_fountain"):
		for hf in hazards.size():
			if _hz_kind[hf] == HK_FOUNTAIN:
				_update_fountain(hazards[hf])
	var mask: int = disabled_mask
	var nh: int = hazards.size()
	for u in sim.heroes:
		if not u.alive or u.chamber != "":
			continue
		var r: = sim.radius(u)
		# A jump-pad flight is above the ground: only the ring reaches it.
		var flying: bool = u.motion != null and u.motion.kind == "jump_pad"
		if not flying:
			_update_haste(u)
		var pad: float = r * 0.28 + 0.01
		for hi in nh:
			var h: Dictionary = hazards[hi]
			var kind: int = _hz_kind[hi]
			if mask != 0 and (mask & _hz_tbit[hi]) != 0:
				continue
			if kind == HK_RING:
				_update_ring_unit(u, h)
				continue
			if flying or kind == HK_ARTILLERY:
				continue
			# Every remaining type acts only inside its shape padded by 0.28 r
			# (jump pads unpadded); a shockwave sweeps, so it is always tested.
			if kind != HK_SHOCKWAVE and not Arena.index_off:
				var pp: float = 0.01 if kind == HK_JUMP else pad
				if u.pos.x < _hz_minx[hi] - pp or u.pos.x > _hz_maxx[hi] + pp or u.pos.y < _hz_miny[hi] - pp or u.pos.y > _hz_maxy[hi] + pp:
					continue
			var typ: = str(h.type)
			if typ == "jump_pad":
				if Arena.shape_contains(h, u.pos, 0.0) and _try_launch(u, h):
					flying = true
				continue
			if typ == "mud":
				if Arena.shape_contains(h, u.pos, r * 0.28):
					_apply_mud(u, h)
				continue
			if not Arena.hazard_effect_contains(h, u.pos, sim.time, r * 0.28, sim.time - dt, u.prev_pos):
				continue
			var key: = "%d:%s" % [u.idx, str(h.id)]
			if typ == "healing_fountain":
				continue
			if typ == "haste":
				continue
			if typ == "wind":
				var dir: = Arena.hazard_direction(h, sim.time)
				var impulse: = float(h.get("force", 0.0)) / maxf(0.55, u.mass) * dt
				u.vel += dir * impulse
				continue
			if typ == "portal":
				if sim.has_any(u, [&"grounded", &"suppression"]):
					continue
				var pk: = "portal:%d" % u.idx
				if sim.time < float(cooldowns.get(pk, 0.0)):
					continue
				var pair: Dictionary = {}
				for h2 in hazards:
					if str(h2.id) == str(h.get("pairId", "")):
						pair = h2
						break
				if pair.is_empty():
					continue
				var speed: = u.vel.length()
				if not sim.zones.prepare_transit(u):
					continue
				var facing: Vector2 = pair.get("exit", ((pair.center as Vector2) - (h.center as Vector2)).normalized())
				var exitp: = sim.clamp_pos((pair.center as Vector2) + facing * (float(pair.get("radius", 30.0)) + r + 8.0), r)
				var from: = u.pos
				u.pos = exitp
				u.vel = facing * speed
				u.facing = facing
				# Environment portals obey the same prison boundary as skill
				# portals before any objective, pickup or next AI tick sees us.
				sim.kits.constrain_chambers(u, from)
				sim.warfare.constrain(u, from)
				exitp = u.pos
				u.prev_pos = exitp
				u.portal_until = sim.time + maxf(0.1, float(h.get("cooldown", 2.5)))
				cooldowns[pk] = u.portal_until
				sim.emit("ENV_PORTAL", -1, u.idx, {"from": from, "to": exitp, "hazard": str(h.id), "hazard_type": "portal"})
				sim.fx("portal_jump", exitp, {"from": from, "color": Color(str(h.get("color", "#a98cff")))})
				sim.zones.grant_shards(u, "env:%s:%d" % [str(h.id), sim.tick])
				continue
			var clk: = Arena.hazard_clock(h, sim.time)
			if not clk.active and typ != "shockwave":
				continue
			if typ == "gravity" and _can_displace(u):
				var delta: Vector2 = (h.center as Vector2) - u.pos
				var distance: float = minf(delta.length(), maxf(0.0, float(h.get("force", 130.0))) * dt / maxf(0.55, u.mass))
				_displace(u, delta.normalized() * distance)
			var interval: = maxf(0.12, float(h.get("tickInterval", 0.5)))
			var st: Dictionary = cooldowns.get(key, {"ready": 0.0, "cycle": -99999})
			if typ in ["eruption", "shockwave"] and int(st.cycle) == int(clk.cycle):
				continue
			if sim.time + 1e-09 < float(st.ready):
				continue
			cooldowns[key] = {"ready": sim.time + interval, "cycle": int(clk.cycle) if typ in ["eruption", "shockwave"] else -99999}
			_env_damage(u, h)
			if not u.alive:
				continue
			if h.has("slow"):
				sim.apply_status(null, u, {"status": "slow", "duration": float(h.get("slowDuration", 0.8)), "magnitude": float(h.slow)}, {"source_type": "ENVIRONMENT"})
			if h.has("knockback") and _can_displace(u):
				var d: = u.pos - (h.center as Vector2)
				d = d.normalized() if d.length_squared() > 1e-06 else (Vector2.LEFT if u.team == 0 else Vector2.RIGHT)
				var endp: = sim.clamp_pos(u.pos + d * float(h.knockback), r)
				var dist: = u.pos.distance_to(endp)
				if dist > 1.0:
					sim.kits.begin_motion(u, endp, dist / 0.28, "environment", {"source_type": "ENVIRONMENT"})


func _can_displace(u: BUnit) -> bool:
	return u.alive and u.chamber == "" and u.motion == null and not sim.has_any(u, [&"invulnerable", &"untargetable", &"unstoppable"]) and not sim.warfare.contemplating(u)


func _in_prison(u: BUnit) -> bool:
	for p in sim.warfare.prisons:
		if not bool(p.ended) and float(p.end) > sim.time and bool((p.inside as Dictionary).get(u.idx, false)):
			return true
	return false


func _update_haste(u: BUnit) -> void:
	if (disabled_mask & Arena.TYPE_BITS["haste"]) != 0:
		return
	var hazards: Array = sim.arena.hazards
	var indexed: bool = _hz_kind.size() == hazards.size() and not Arena.index_off
	if indexed and _hz_haste == 0:
		return
	var key: String = "haste:%d" % u.idx
	if sim.time + 1e-9 < float(cooldowns.get(key, 0.0)):
		return
	var strongest: Dictionary = {}
	var amount: float = 0.0
	var pad: float = sim.radius(u) * 0.28 + 0.01
	for hi in hazards.size():
		var h: Dictionary = hazards[hi]
		if indexed and (_hz_kind[hi] != HK_HASTE or u.pos.x < _hz_minx[hi] - pad or u.pos.x > _hz_maxx[hi] + pad or u.pos.y < _hz_miny[hi] - pad or u.pos.y > _hz_maxy[hi] + pad):
			continue
		if str(h.type) != "haste" or not Arena.shape_contains(h, u.pos, sim.radius(u) * 0.28):
			continue
		var bonus: float = clampf(float(h.get("speedMultiplier", 1.25)) - 1.0, 0.0, 1.0)
		if bonus > amount:
			amount = bonus
			strongest = h
	if strongest.is_empty():
		return
	var was_active: bool = false
	for buff in u.buffs:
		if buff.tag == "environment_haste" and buff.end > sim.time:
			was_active = true
	# One tag across all pads. A weaker pad cannot perpetually extend the
	# stronger bonus from a pad the unit has already left.
	sim.add_buff(u, BattleSim.S_MS, amount, maxf(0.1, float(strongest.get("duration", 1.6))), -1, {"tag": "environment_haste", "hazard": str(strongest.id)})
	cooldowns[key] = sim.time + maxf(0.1, float(strongest.get("refreshInterval", 0.5)))
	if not was_active:
		sim.emit("ENV_HASTE", -1, u.idx, {"hazard": str(strongest.id), "hazard_type": "haste", "multiplier": 1.0 + amount, "pos": u.pos})


func _displace(u: BUnit, delta: Vector2) -> void:
	if delta.length_squared() < 0.000001:
		return
	var start: Vector2 = u.pos
	var end: Vector2 = start + delta
	var radius: float = sim.radius(u)
	var hit: Dictionary = sim.arena.terrain_contact(start, end, radius, false)
	if not hit.is_empty():
		end = (hit.point as Vector2) + (hit.normal as Vector2) * 0.04
	u.pos = sim.arena.resolve_circle(end, radius)
	sim.kits.constrain_chambers(u, start)
	sim.warfare.constrain(u, start)


func _fountain_ready_at(h: Dictionary) -> float:
	return float(cooldowns.get("fountain:" + str(h.id), 0.0))


func _update_fountain(h: Dictionary) -> void:
	if sim.time + 1e-9 < _fountain_ready_at(h):
		return
	var selected: BUnit = null
	var lowest: float = 2.0
	for u in sim.heroes:
		if not u.alive or u.chamber != "" or sim.has_status(u, &"untargetable"):
			continue
		if not Arena.shape_contains(h, u.pos, sim.radius(u) * 0.28):
			continue
		var ratio: float = u.hp / maxf(1.0, sim.max_hp(u))
		if ratio > 1.0 - clampf(float(h.get("minMissingPercent", 0.05)), 0.001, 1.0):
			continue
		if ratio < lowest - 1e-9 or (absf(ratio - lowest) <= 1e-9 and (selected == null or u.idx < selected.idx)):
			selected = u
			lowest = ratio
	if selected == null:
		return
	var result: Dictionary = sim.apply_heal(selected, selected, {"base": sim.max_hp(selected) * clampf(float(h.get("healPercent", 0.16)), 0.0, 1.0)}, {"source_type": "ENVIRONMENT_FOUNTAIN", "proc": true})
	var amount: float = maxf(0.0, float(result.effective))
	if amount <= 0.0:
		return
	selected.st_zone_healing += amount
	var ready_at: float = sim.time + maxf(0.1, float(h.get("cooldown", 18.0)))
	cooldowns["fountain:" + str(h.id)] = ready_at
	sim.emit("ENV_FOUNTAIN", -1, selected.idx, {"hazard": str(h.id), "hazard_type": "healing_fountain", "amount": amount, "ready_at": ready_at, "pos": selected.pos})
	sim.fx("heal", selected.pos, {"color": Color(str(h.get("color", "#65ecc1")))})


# --- Mud ---------------------------------------------------------------------
# A refreshed slow with no source: tenacity shortens it, the strongest slow
# wins (BattleSim.get_status). Entering emits one CC_APPLIED; standing in the
# mud extends it silently.
func _apply_mud(u: BUnit, h: Dictionary) -> void:
	var mag: float = clampf(float(h.get("slow", 0.3)), 0.0, 0.6)
	if mag <= 0.0:
		return
	if sim.has_any(u, [&"invulnerable", &"untargetable", &"unstoppable"]) or sim.warfare.contemplating(u):
		return
	for st in u.statuses:
		if st.type == &"slow" and st.source_idx == -1 and st.end > sim.time and absf(st.magnitude - mag) < 1e-6 and bool(st.extra.get("mud", false)):
			st.end = maxf(st.end, sim.time + MUD_SLOW_DURATION * (1.0 - clampf(sim.stat(u, BattleSim.S_TEN), 0.0, 0.95)))
			return
	sim.apply_status(null, u, {"status": "slow", "duration": MUD_SLOW_DURATION, "magnitude": mag, "mud": true, "hazard": str(h.id)}, {"source_type": "ENVIRONMENT"})


# --- Jump pads -----------------------------------------------------------------
func _try_launch(u: BUnit, h: Dictionary) -> bool:
	if u.motion != null or float(u.ks.get("wall_run_until", -1.0)) > sim.time:
		return false
	if sim.has_any(u, [&"root", &"stun", &"suppression", &"airborne", &"grounded", &"sleep", &"untargetable"]):
		return false
	if sim.warfare.contemplating(u) or _in_prison(u):
		return false
	if sim.time + 1e-9 < u.pad_until:
		return false
	var r: float = sim.radius(u)
	var landing: Vector2 = sim.arena.resolve_circle(h.get("landing", h.center), r)
	var flight: float = maxf(0.05, float(h.get("flightTime", 0.8)))
	var from: Vector2 = u.pos
	var dist: float = from.distance_to(landing)
	if dist < 1.0:
		return false
	u.pad_until = sim.time + maxf(0.1, float(h.get("cooldown", PAD_COOLDOWN)))
	if u.action:
		sim.cancel_action(u, "jump_pad")
	sim.kits.begin_motion(u, landing, dist / flight, "jump_pad", {"source_type": "ENVIRONMENT", "hazard": str(h.id)}, {"flight": true})
	sim.emit("ENV_JUMP", -1, u.idx, {"hazard": str(h.id), "hazard_type": "jump_pad", "from": from, "to": landing, "flight_time": flight, "pos": from})
	sim.fx("jump_pad", from, {"to": landing, "duration": flight, "color": Color(str(h.get("color", "#8fd3ff")))})
	return true


# --- Closing ring ----------------------------------------------------------------
func _update_ring_unit(u: BUnit, h: Dictionary) -> void:
	if not Arena.ring_outside(h, u.pos, sim.time, 0.0):
		return
	var key: String = "ring:%d:%s" % [u.idx, str(h.id)]
	if sim.time + 1e-9 < float(cooldowns.get(key, 0.0)):
		return
	cooldowns[key] = sim.time + maxf(0.2, float(h.get("tickInterval", 1.0)))
	_env_damage(u, h, sim.max_hp(u) * Arena.ring_damage_fraction(h))


func _update_ring_phases() -> void:
	for h in sim.arena.hazards:
		if str(h.type) != "closing_ring" or (disabled_mask & int(h.get("tbit", 0))) != 0:
			continue
		var phase: int = 0
		if Arena.ring_active(h, sim.time):
			phase = 2 if sim.time >= float(h.get("endTime", float(h.get("startTime", 60.0)) + 30.0)) else 1
		var id: String = str(h.id)
		if phase > int(_ring_phase.get(id, 0)):
			_ring_phase[id] = phase
			sim.emit("ENV_RING", -1, -1, {"hazard": id, "hazard_type": "closing_ring", "phase": "final" if phase == 2 else "shrink",
				"radius": Arena.ring_radius_at(h, sim.time), "final_radius": float(h.get("endRadius", 200.0)), "pos": h.center})


# --- Artillery -------------------------------------------------------------------
# At impact - warningDuration of each cycle the salvo's points are drawn with a
# private RNG (seed_value ^ hash(id) ^ cycle), announced as public telegraphs
# (source -1, team -1) and resolved at impact.
func _update_artillery() -> void:
	if not strikes.is_empty():
		_resolve_strikes()
	if (disabled_mask & Arena.TYPE_BITS["artillery"]) != 0:
		return
	for h in sim.arena.hazards:
		if str(h.type) != "artillery":
			continue
		var period: float = maxf(0.2, float(h.get("period", 8.0)))
		var cycle: int = int(floor((sim.time + float(h.get("phase", 0.0))) / period))
		var id: String = str(h.id)
		if int(_salvo_cycle.get(id, -2147483647)) >= cycle:
			continue
		var warn: float = Arena.artillery_warning(h)
		var announce_t: float = Arena.artillery_impact_time(h, cycle) - warn
		if sim.time + 1e-9 < announce_t:
			continue
		# A salvo is only fired with (almost) its full public warning: one whose
		# announcement fell before the battle started, or that was missed while
		# the type was switched off, is skipped instead of landing by surprise.
		if announce_t < -1e-9 or sim.time - announce_t > warn * 0.5:
			_salvo_cycle[id] = cycle
			continue
		_announce_salvo(h, cycle)


func _announce_salvo(h: Dictionary, cycle: int) -> void:
	var id: String = str(h.id)
	_salvo_cycle[id] = cycle
	var impact: float = Arena.artillery_impact_time(h, cycle)
	var rng: = RandomNumberGenerator.new()
	rng.seed = sim.seed_value ^ hash(id) ^ cycle
	var candidates: Array[BUnit] = []
	for u in sim.heroes:
		if u.alive and u.chamber == "" and Arena.shape_contains(h, u.pos, 0.0):
			candidates.append(u)
	var n: int = maxi(1, int(h.get("count", 3)))
	var spread: float = maxf(0.0, float(h.get("spread", 60.0)))
	var rad: float = maxf(4.0, float(h.get("radius", 60.0)))
	var dmg: float = maxf(0.0, float(h.get("damage", 0.0)))
	var points: Array = []
	for k in n:
		var p: Vector2
		if not candidates.is_empty():
			var pick: BUnit = candidates[rng.randi_range(0, candidates.size() - 1)]
			var ang: float = rng.randf() * TAU
			var off: float = sqrt(rng.randf()) * spread
			p = pick.pos + Vector2(cos(ang), sin(ang)) * off
		else:
			p = _uniform_in_shape(h, rng)
		p = _strike_point(h, p)
		points.append(p)
		var tg: Dictionary = {"id": sim.next_id(), "source": -1, "team": -1, "shape": "circle", "from": p, "to": p,
			"radius": rad, "width": 0.0, "range": 0.0, "angle": 0.0, "start": sim.time, "end": impact,
			"ability": null, "action_id": -1, "cancelled": false, "dmg": dmg, "env": true, "hazard": id, "hazard_type": "artillery"}
		sim.telegraphs.append(tg)
		strikes.append({"hazard": id, "h": h, "pos": p, "radius": rad, "warn_t": sim.time, "impact_t": impact, "cycle": cycle, "tg": tg})
	_rebuild_art_state()
	sim.emit("ENV_ARTILLERY", -1, -1, {"hazard": id, "hazard_type": "artillery", "points": points, "radius": rad, "impact_t": impact, "pos": h.center})


# Where a drawn strike point actually lands (DESIGN_153 §1.2): inside the
# hazard's area shape, inside the arena bounds and outside solid obstacles.
# The aimed point (hero ± spread) is first clamped into the area; when pushing
# it out of an obstacle that straddles the area edge leaves the area again,
# the point slides toward the area centre until it is both inside and clear.
# Pure function of the drawn point (no RNG draws, so salvos stay seeded).
const STRIKE_SLACK: = 0.5


func _strike_point(h: Dictionary, p: Vector2) -> Vector2:
	var a: Arena = sim.arena
	var q: Vector2 = clamp_into_shape(h, p)
	var res: Vector2 = a.resolve_circle(q, 2.0)
	if Arena.shape_contains(h, res, STRIKE_SLACK):
		return res
	var c: Vector2 = h.center
	for k in range(1, 9):
		res = a.resolve_circle(q.lerp(c, float(k) / 8.0), 2.0)
		if Arena.shape_contains(h, res, STRIKE_SLACK):
			return res
	return res


# Nearest point of the hazard's area shape (rect or circle) to p.
static func clamp_into_shape(h: Dictionary, p: Vector2) -> Vector2:
	if str(h.get("shape", "rect")) == "circle":
		var c: Vector2 = Vector2(float(h.x), float(h.y))
		return c + (p - c).limit_length(float(h.get("radius", 0.0)))
	return Vector2(clampf(p.x, float(h.x), float(h.x) + float(h.get("w", 0.0))), clampf(p.y, float(h.y), float(h.y) + float(h.get("h", 0.0))))


func _uniform_in_shape(h: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	if str(h.get("shape", "rect")) == "circle":
		var ang: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * float(h.get("radius", 0.0))
		return Vector2(float(h.x), float(h.y)) + Vector2(cos(ang), sin(ang)) * d
	var x: float = float(h.x) + rng.randf() * float(h.get("w", 0.0))
	var y: float = float(h.y) + rng.randf() * float(h.get("h", 0.0))
	return Vector2(x, y)


func _resolve_strikes() -> void:
	var due: bool = false
	for s in strikes:
		if float(s.impact_t) <= sim.time + 1e-9:
			due = true
			break
	if not due:
		return
	var keep: Array = []
	for s in strikes:
		if float(s.impact_t) > sim.time + 1e-9:
			keep.append(s)
			continue
		var pos: Vector2 = s.pos
		var rad: float = float(s.radius)
		for u in sim.heroes:
			if not u.alive or u.chamber != "" or (u.motion != null and u.motion.kind == "jump_pad"):
				continue
			if u.pos.distance_to(pos) <= rad + sim.radius(u) * STRIKE_BODY_FACTOR:
				_env_damage(u, s.h)
		var h: Dictionary = s.h
		sim.emit("ENV_STRIKE", -1, -1, {"hazard": str(s.hazard), "hazard_type": "artillery", "pos": pos, "radius": rad})
		sim.fx("artillery_impact", pos, {"radius": rad, "color": Color(str(h.get("color", "#ff9a5c")))})
	strikes = keep
	_rebuild_art_state()


func _cancel_strikes() -> void:
	if strikes.is_empty():
		return
	for s in strikes:
		(s.tg as Dictionary)["cancelled"] = true
	strikes = []
	_rebuild_art_state()
	if sim:
		sim.cleanup_telegraphs()


func _rebuild_art_state() -> void:
	_art_state = []
	for s in strikes:
		_art_state.append({"id": str(s.hazard), "pos": s.pos, "radius": float(s.radius), "impact_t": float(s.impact_t), "warn_t": float(s.warn_t)})


# Pending public strikes for rendering and tools. Do not modify the result.
func artillery_state() -> Array:
	return _art_state


# Seconds until u's own environment-portal / jump-pad cooldown ends (0 = ready).
# A switched-off type reports LINK_OFF so Navigator never routes through it.
const LINK_OFF: = 1.0e6


func portal_wait(u: BUnit) -> float:
	if u == null or not type_active("portal"):
		return LINK_OFF
	return maxf(0.0, u.portal_until - sim.time)


func pad_wait(u: BUnit) -> float:
	if u == null or not type_active("jump_pad"):
		return LINK_OFF
	return maxf(0.0, u.pad_until - sim.time)


# --- Gates -----------------------------------------------------------------------
# Navigation gate signature of sim.arena at time t under this battle's switches
# (gates closing within Arena.NAV_CLOSING_MARGIN count as closed; a switched-off
# gate type leaves every gate open). _sync_gates stores it in arena.nav_sig;
# code that warms Navigator grids before start() asks for it directly.
func nav_signature(t: float) -> int:
	var a: Arena = sim.arena if sim else null
	if a == null or a.gates.is_empty():
		return 0
	if type_active("gate"):
		return a.gate_bits_at(t, Arena.NAV_CLOSING_MARGIN)
	return a.all_gates_open_bits()


func _sync_gates() -> void:
	var a: Arena = sim.arena
	if a == null or a.gates.is_empty():
		return
	if a != _arena:
		_bind()
	var want: int = a.gate_bits_at(sim.time) if type_active("gate") else a.all_gates_open_bits()
	a.nav_sig = nav_signature(sim.time)
	if _gates_bound and want == a.gate_bits:
		return
	var old: int = a.gate_bits
	a.apply_gate_bits(want)
	if not _gates_bound:
		# Initial state of the battle: no events, but never leave anyone inside.
		_gates_bound = true
		_push_out_of_gates(~want & a.all_gates_open_bits(), false)
		return
	var changed: int = old ^ want
	for k in a.gates.size():
		if ((changed >> k) & 1) == 0:
			continue
		var g: Dictionary = a.gates[k]
		sim.emit("ENV_GATE", -1, -1, {"hazard": str(g.id), "hazard_type": "gate", "group": str(g.group), "open": ((want >> k) & 1) == 1, "pos": g.center})
	var closed_now: int = old & ~want
	if closed_now != 0:
		_push_out_of_gates(closed_now, true)


# Bodies overlapping a gate that just closed are moved to the side of the gate
# their previous position was on (never trapped inside the wall).
func _push_out_of_gates(bits: int, announce: bool) -> void:
	var a: Arena = sim.arena
	for k in a.gates.size():
		if ((bits >> k) & 1) == 0:
			continue
		var g: Dictionary = a.gates[k]
		var i: int = int(g.obs)
		for body in sim.bodies_alive():
			if body.chamber != "" or (body.motion != null and body.motion.flight):
				continue
			var r: float = sim.radius(body)
			if not _overlaps_obstacle(a, i, body.pos, r):
				continue
			var from: Vector2 = body.pos
			body.pos = _gate_exit(a, g, body, r)
			sim.kits.constrain_chambers(body, from)
			sim.warfare.constrain(body, from)
			body.pos = a.resolve_circle(body.pos, r)
			if announce and body.is_hero:
				sim.emit("ENV_PUSHED", -1, body.idx, {"hazard": str(g.id), "hazard_type": "gate", "from": from, "to": body.pos, "pos": body.pos})


func _overlaps_obstacle(a: Arena, i: int, p: Vector2, r: float) -> bool:
	if a.obs_circle[i] == 1:
		return p.distance_to(Vector2(a.obs_x[i], a.obs_y[i])) < a.obs_r[i] + r
	return p.x > a.obs_x[i] - r and p.x < a.obs_x[i] + a.obs_w[i] + r and p.y > a.obs_y[i] - r and p.y < a.obs_y[i] + a.obs_h[i] + r


func _gate_exit(a: Arena, g: Dictionary, body: BUnit, r: float) -> Vector2:
	var i: int = int(g.obs)
	var ref: Vector2 = body.prev_pos if body.prev_pos.is_finite() else body.pos
	if a.obs_circle[i] == 1:
		var c: Vector2 = Vector2(a.obs_x[i], a.obs_y[i])
		var dir: Vector2 = ref - c
		if dir.length_squared() < 1e-6:
			dir = body.pos - c
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector2.RIGHT
		return c + dir * (a.obs_r[i] + r + 0.5)
	var rect: Rect2 = g.rect
	var center: Vector2 = rect.get_center()
	# Push across the gate's thin axis, toward the side we came from.
	var along_x: bool = rect.size.x <= rect.size.y
	var side: float = signf((ref.x - center.x) if along_x else (ref.y - center.y))
	if side == 0.0:
		side = signf((body.pos.x - center.x) if along_x else (body.pos.y - center.y))
	if side == 0.0:
		side = 1.0
	var out: Array = []
	for s in [side, -side]:
		var p: Vector2 = body.pos
		if along_x:
			p.x = (rect.end.x + r + 0.5) if s > 0.0 else (rect.position.x - r - 0.5)
		else:
			p.y = (rect.end.y + r + 0.5) if s > 0.0 else (rect.position.y - r - 0.5)
		if a.is_walkable(p, r):
			return p
		out.append(p)
	return out[0]


# --- Public state ------------------------------------------------------------------
# Public map state only. These rows contain no occupants, hidden positions,
# health values or skill cooldowns, so spectator UI and AI can share them.
func state_snapshot() -> Array:
	var result: Array = []
	for h in sim.arena.hazards:
		var typ: String = str(h.type)
		var on: bool = type_active(typ)
		var row: Dictionary = Arena.hazard_clock(h, sim.time).duplicate()
		row.merge({"id": str(h.id), "type": typ, "label": str(h.get("label", h.id)), "center": h.center, "enabled": on, "cooldown_remaining": 0.0}, true)
		if typ == "healing_fountain":
			row.cooldown_remaining = maxf(0.0, _fountain_ready_at(h) - sim.time)
			row.active = row.cooldown_remaining <= 1e-9
			row.remaining = row.cooldown_remaining
		elif typ == "shockwave":
			row["wave_radius"] = Arena.shockwave_radius(h, sim.time)
		elif typ == "artillery":
			var pending: int = 0
			var next_impact: float = INF
			for s in strikes:
				if str(s.hazard) == str(h.id):
					pending += 1
					next_impact = minf(next_impact, float(s.impact_t))
			row["pending_strikes"] = pending
			row["next_impact_t"] = next_impact
			row["strike_radius"] = float(h.get("radius", 60.0))
		elif typ == "closing_ring":
			row["safe_radius"] = Arena.ring_radius_at(h, sim.time)
			row["final_radius"] = float(h.get("endRadius", 200.0))
			row["start_time"] = float(h.get("startTime", 60.0))
			row["end_time"] = float(h.get("endTime", float(h.get("startTime", 60.0)) + 30.0))
		elif typ == "jump_pad":
			row["landing"] = h.get("landing", h.center)
			row["flight_time"] = float(h.get("flightTime", 0.8))
		elif typ == "mud":
			row["slow"] = clampf(float(h.get("slow", 0.3)), 0.0, 0.6)
		if not on:
			row.active = false
			row.warning = false
		result.append(row)
	var a: Arena = sim.arena
	var gate_on: bool = type_active("gate")
	for k in a.gates.size():
		var g: Dictionary = a.gates[k]
		var grow: Dictionary = Arena.gate_clock(g, sim.time)
		var open_now: bool = a.gate_slot_open(k) if a == _arena and _gates_bound else bool(grow.open)
		grow.merge({"id": str(g.id), "type": "gate", "label": str(g.label) if str(g.label) != "" else str(g.id), "center": g.center,
			"group": str(g.group), "enabled": gate_on, "cooldown_remaining": 0.0}, true)
		grow["open"] = open_now
		grow["active"] = open_now
		if not gate_on:
			grow["warning"] = false
		result.append(grow)
	return result


func public_fountains() -> Array:
	var result: Array = []
	var on: bool = type_active("healing_fountain")
	for h in sim.arena.hazards:
		if str(h.type) != "healing_fountain":
			continue
		var ready_at: float = _fountain_ready_at(h)
		result.append({"id": str(h.id), "type": str(h.type), "center": h.center, "radius": float(h.get("radius", 40.0)), "ready": on and ready_at <= sim.time + 1e-9, "ready_at": ready_at, "cooldown_remaining": maxf(0.0, ready_at - sim.time), "heal_percent": float(h.get("healPercent", 0.16))})
	return result


func benefit_at(p: Vector2, u: BUnit) -> float:
	if not enabled or u == null or not u.alive or u.chamber != "":
		return 0.0
	var value: float = 0.0
	for h in sim.arena.hazards:
		if disabled_mask != 0 and (disabled_mask & int(h.get("tbit", 0))) != 0:
			continue
		if not Arena.shape_contains(h, p, sim.radius(u) * 0.28):
			continue
		if str(h.type) == "healing_fountain" and _fountain_ready_at(h) <= sim.time + 1e-9:
			var missing: float = clampf(1.0 - u.hp / maxf(1.0, sim.max_hp(u)), 0.0, 1.0)
			if missing >= float(h.get("minMissingPercent", 0.05)):
				value += minf(missing, float(h.get("healPercent", 0.16))) * 2.5
		elif str(h.type) == "haste":
			var current: float = 0.0
			for buff in u.buffs:
				if buff.tag == "environment_haste" and buff.end > sim.time + 0.5:
					current = maxf(current, buff.amount)
			value = maxf(value, maxf(0.0, float(h.get("speedMultiplier", 1.25)) - 1.0 - current) * 0.35)
	return value


# Toggle-aware penalty: authored geometry plus announced strike circles that
# have not landed by t. 0 when the environment is switched off.
func hazard_penalty(p: Vector2, t: float, r: float = 0.0) -> float:
	if not enabled:
		return 0.0
	var pen: float = sim.arena.hazard_penalty(p, t, r, disabled_mask)
	for s in strikes:
		if float(s.impact_t) >= t - 0.1 and p.distance_to(s.pos) <= float(s.radius) + r * STRIKE_BODY_FACTOR + 4.0:
			pen += 1.3
	return pen


func expected_hazard_damage(p: Vector2, t: float, r: float, horizon: float, u: BUnit = null) -> float:
	if not enabled:
		return 0.0
	var total: float = sim.arena.expected_hazard_damage(p, t, r, horizon, disabled_mask, sim.max_hp(u) if u else 1000.0)
	for s in strikes:
		var at: float = float(s.impact_t)
		if at >= t and at <= t + horizon and p.distance_to(s.pos) <= float(s.radius) + r * STRIKE_BODY_FACTOR:
			total += maxf(0.0, float((s.h as Dictionary).get("damage", 0.0)))
	return total


func _env_damage(t: BUnit, h: Dictionary, raw_override: float = -1.0) -> void :
	if not t.alive:
		return
	if sim.has_any(t, [&"invulnerable", &"untargetable"]):
		return
	var raw: = raw_override if raw_override >= 0.0 else maxf(0.0, float(h.get("damage", 0.0)))
	if raw <= 0.0:
		return
	var typ: String = str(h.get("type", ""))
	var school: = "true" if typ == "closing_ring" else str(h.get("school", "physical"))
	var post: = raw
	if school == "magic":
		post = raw * sim.resist_mult(sim.stat(t, &"magicResistance"))
	elif school == "physical":
		post = raw * sim.resist_mult(sim.stat(t, &"armor"))
	var absorbed: = sim._absorb_shields(t, post)
	var rem: = post - absorbed
	var hpd: = minf(maxf(0.0, t.hp), rem)
	t.hp -= hpd
	t.st_taken += hpd
	# V2 battleground zone (DESIGN_V2 §3.3): damage flagged "no_combat" neither
	# reveals a hero in brush or invisibility nor resets the out-of-combat
	# timer, and stays out of the battle log (two ticks a second per hero).
	var quiet: bool = bool(h.get("no_combat", false))
	if not quiet:
		t.last_combat_time = sim.time
		t.last_damage_time = sim.time
	var hit: Dictionary = {"amount": hpd, "absorbed": absorbed, "school": school, "hazard": str(h.get("id", "")), "hazard_type": typ, "pos": t.pos, "color": str(h.get("color", "#f5b36d"))}
	if quiet:
		hit["silent"] = true
	sim.emit("ENV_HIT", -1, t.idx, hit)
	if hpd > 0.0:
		var sl: = sim.get_status(t, &"sleep")
		if sl and sl.extra.get("breaksOnDamage", false):
			t.statuses.erase(sl)
	sim.kits.on_env_damage(t, hpd)
	if t.hp <= 0.0 and t.alive:
		sim.kill_unit(t, null, {"env": true})


# --- V2 scale (B-PERF) ---
# Per-hazard type codes, type bits and shape bounding boxes for the per-hero
# loop in update(): a hero outside a hazard's padded box skips it without a
# string compare or shape test. Effects and their order are unchanged.
const HK_OTHER: = 0
const HK_RING: = 1
const HK_ARTILLERY: = 2
const HK_JUMP: = 3
const HK_SHOCKWAVE: = 4
const HK_FOUNTAIN: = 5
const HK_HASTE: = 6
var _hz_kind: PackedInt32Array = PackedInt32Array()
var _hz_tbit: PackedInt32Array = PackedInt32Array()
var _hz_minx: PackedFloat64Array = PackedFloat64Array()
var _hz_maxx: PackedFloat64Array = PackedFloat64Array()
var _hz_miny: PackedFloat64Array = PackedFloat64Array()
var _hz_maxy: PackedFloat64Array = PackedFloat64Array()
var _hz_haste: int = 0


func _index_hazards(hazards: Array) -> void:
	var n: int = hazards.size()
	_hz_kind.resize(n)
	_hz_tbit.resize(n)
	_hz_minx.resize(n)
	_hz_maxx.resize(n)
	_hz_miny.resize(n)
	_hz_maxy.resize(n)
	_hz_haste = 0
	for i in n:
		var h: Dictionary = hazards[i]
		var typ: String = str(h.type)
		var kind: int = HK_OTHER
		match typ:
			"closing_ring":
				kind = HK_RING
			"artillery":
				kind = HK_ARTILLERY
			"jump_pad":
				kind = HK_JUMP
			"shockwave":
				kind = HK_SHOCKWAVE
			"healing_fountain":
				kind = HK_FOUNTAIN
			"haste":
				kind = HK_HASTE
				_hz_haste += 1
		_hz_kind[i] = kind
		_hz_tbit[i] = int(h.get("tbit", 0))
		# Arena.shape_contains: circle = centre (x, y) and radius; otherwise the
		# authored rect x, y, w, h.
		var x: float = float(h.get("x", 0.0))
		var y: float = float(h.get("y", 0.0))
		if str(h.get("shape", "rect")) == "circle":
			var r: float = float(h.get("radius", 0.0))
			_hz_minx[i] = x - r
			_hz_maxx[i] = x + r
			_hz_miny[i] = y - r
			_hz_maxy[i] = y + r
		else:
			_hz_minx[i] = x
			_hz_maxx[i] = x + float(h.get("w", 0.0))
			_hz_miny[i] = y
			_hz_maxy[i] = y + float(h.get("h", 0.0))
