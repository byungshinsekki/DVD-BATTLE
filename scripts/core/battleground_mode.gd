class_name BattlegroundMode
extends DeathmatchMode

# V2 battleground (DESIGN_V2 §3.1, §3.5). Solo / duo / trio squads, up to 30
# heroes on a ~30x map, a shrinking zone (BrZone), 80 field items placed once
# (BrItems), no respawn. The last team standing wins; placement is the reverse
# elimination order.
#
# It extends DeathmatchMode so the item system (slots, swaps, every item
# effect and proc, phoenix), the kill / assist bookkeeping helpers, vision
# bonuses and the out-of-combat regeneration run unchanged; sim.deathmatch and
# sim.battleground both point at this object. Everything that differs is an
# override here, so deathmatch itself is untouched.
#
# Duo / trio: lethal damage downs a hero instead of killing it while a
# teammate still stands. A downed hero has DOWNED_HP health of its own, crawls
# at x0.35, cannot attack or cast, keeps its items and dies when its downed
# health runs out or its bleed window (30 / 20 / 10 s on the 1st / 2nd / 3rd+
# down) ends. A downed hero takes x DOWNED_TAKEN damage from every source,
# the zone included (B-SQUAD: finishing it takes a few seconds, so its squad
# can contest the knock). Downed is not crowd control: it is a status no
# cleanse or tenacity touches. A teammate within REVIVE_RANGE px revives it with a 5 s
# channel (interrupted by enemy damage to the reviver, leaving the range or
# hard crowd control); the hero stands up with 25 % health, which is not a
# heal (heal block does not stop it). When every member of a team is downed
# or dead the team is out and its downed members die.
#
# Information (DESIGN_V2 §3.5): downed and revive events are seen only by
# observers (the emit visibility rule); hero deaths, team eliminations and the
# zone are public (every team's sv / gv set). AI reads the zone only through
# zone_view() = zone.public_view(sim.time).
#
# UI contract (§3.5): squad, team_count, team_members(), team_alive(),
# alive_team_count(), alive_hero_count(), placement, elim_time, winner_team,
# player_no(), team_label(), is_downed(), downed_info(), hstats, zone,
# zone_view(); inherited inventory, field and kill_feed. Kill feed entries
# carry "kind" (knock / kill / revive / team_out) and "public".

const MAX_HEROES := 30
const MAX_TIME := 600.0
const ITEM_COUNT := 80
# Downed health (B-SQUAD rule tuning; was 300).
const DOWNED_HP := 400.0
const DOWNED_SPEED := 0.35
# Share of incoming damage a downed hero takes (B-SQUAD rule tuning; was 1).
const DOWNED_TAKEN := 0.5
const BLEED_TIMES := [30.0, 20.0, 10.0]
const REVIVE_TIME := 5.0
# Edge-to-edge distance between the reviver's and the downed hero's bodies.
const REVIVE_RANGE := 60.0
const REVIVE_HP := 0.25
const ZONE_CREDIT_WINDOW := 10.0
# Crowd control that breaks a revive channel (slows, silences and roots do not).
const REVIVE_BREAK := [&"stun", &"airborne", &"suppression", &"sleep", &"charm", &"taunt", &"fear", &"control"]
const FORMATION := {
	1: [Vector2.ZERO],
	2: [Vector2(0.0, -40.0), Vector2(0.0, 40.0)],
	3: [Vector2(28.0, 0.0), Vector2(-26.0, -48.0), Vector2(-26.0, 48.0)],
}
const ZONE_HAZARD := {"id": "br_zone", "type": "br_zone", "school": "true", "no_combat": true, "color": "#7fb4ff"}
const SERIES_EVERY := 5.0
const PICK_CELL := 128.0

var squad: int = 1
var team_count: int = 0
var teams: Array = []              # team -> Array of hero idx (slot order)
var placement: Dictionary = {}     # team -> final rank (1 = winner)
var elim_time: Dictionary = {}     # team -> time it was eliminated
var winner_team: int = -1
var elim_order: Array = []         # teams in elimination order
var eliminated: Dictionary = {}    # team -> true
var zone: BrZone
var zone_speed: String = "normal"
var hstats: Dictionary = {}        # hero idx -> {kills, knocks, revives, damage, items_picked, survival, death_cause, ...}
var downed: Dictionary = {}        # hero idx -> downed info (see downed_info)
var reviving: Dictionary = {}      # reviver idx -> downed hero idx
var down_count: Dictionary = {}    # hero idx -> downs so far
var series: Array = []             # [t, alive teams, alive heroes]
var _wipe_queue: Array = []
var _detach_queue: Array = []
var _zone_tick_at: float = INF
var _zone_announced: int = 0
var _zone_shrunk: int = 0
var _zone_hitting: bool = false
var _next_series_at: float = 0.0
var _field_cells: Dictionary = {}
var _field_dirty: bool = true


func _init(s: BattleSim) -> void:
	super(s)
	kill_target = 999
	small_rules = false
	squad = clampi(int(s.cfg.get("squad", 1)), 1, 3)
	zone_speed = str(s.cfg.get("zone_speed", "normal"))
	if not BrZone.SPEEDS.has(zone_speed):
		zone_speed = "normal"


# ---------------------------------------------------------------- setup

# The config's teams as hero-id lists. Accepts "teams" ([[ids], ...]; a bare
# id counts as a one-hero team) or, for convenience, "players" (split into
# squads). Unknown ids and a hero repeated within its own team are dropped,
# teams are cut to the squad size and the roster to MAX_HEROES; at least two
# teams always play. Solo allows the same hero on several teams.
static func normalize_teams(config: Dictionary) -> Array:
	var sq: int = clampi(int(config.get("squad", 1)), 1, 3)
	var raw: Array = []
	if config.has("teams"):
		for entry in config.get("teams", []):
			raw.append(entry if entry is Array else [entry])
	else:
		var players: Array = config.get("players", [])
		var k: int = 0
		while k < players.size():
			raw.append(players.slice(k, k + sq))
			k += sq
	var out: Array = []
	var total: int = 0
	for entry in raw:
		var team: Array = []
		for id in entry:
			var sid: String = str(id)
			if team.size() >= sq or team.has(sid) or DB.char_def(sid) == null:
				continue
			team.append(sid)
		if team.is_empty():
			continue
		if total + team.size() > MAX_HEROES:
			break
		total += team.size()
		out.append(team)
	while out.size() < 2:
		out.append(["swordsman"])
	return out


# Problems that make a roster invalid for the setup screen (empty = valid).
static func validate(config: Dictionary) -> Array:
	var errors: Array = []
	var sq: int = int(config.get("squad", 1))
	if sq < 1 or sq > 3:
		errors.append("형식은 솔로·듀오·트리오만 가능합니다")
		sq = clampi(sq, 1, 3)
	var teams_in: Array = config.get("teams", [])
	var limit: int = floori(float(MAX_HEROES) / float(sq))
	if teams_in.size() < 2 or teams_in.size() > limit:
		errors.append("팀 수는 2–%d이어야 합니다" % limit)
	var total: int = 0
	for k in teams_in.size():
		var team: Array = teams_in[k] if teams_in[k] is Array else [teams_in[k]]
		total += team.size()
		if team.size() != sq:
			errors.append("%s 인원이 %d명이 아닙니다" % [DB.team_name(k, sq), sq])
		var seen_ids: Dictionary = {}
		for id in team:
			if DB.char_def(str(id)) == null:
				errors.append("알 수 없는 영웅 %s" % str(id))
			elif seen_ids.has(str(id)):
				errors.append("%s 안에 같은 영웅이 두 번 있습니다" % DB.team_name(k, sq))
			seen_ids[str(id)] = true
	if total > MAX_HEROES:
		errors.append("최대 %d명입니다" % MAX_HEROES)
	return errors


func make_players(ids: Array) -> void:
	var as_teams: Array = []
	for id in ids:
		as_teams.append([id])
	make_teams(as_teams)


# Builds the heroes (team by team, slot order), the zone, the 80 field items
# and every path grid the match can need.
func make_teams(team_ids: Array) -> void:
	team_count = team_ids.size()
	teams = []
	for arr in [kills, deaths, assists, streak, best_streak, items_picked]:
		arr.resize(maxi(team_count, sim.team_count))
		arr.fill(0)
	var spawns: Array = sim.arena.ffa_spawns
	# Team anchors: greedy farthest points from a seeded first pick.
	var chosen: Array = []
	if not spawns.is_empty():
		chosen.append(rng.randi_range(0, spawns.size() - 1))
		while chosen.size() < mini(team_count, spawns.size()):
			var best: int = -1
			var best_d: float = -1.0
			for k in spawns.size():
				if chosen.has(k):
					continue
				var d: float = INF
				for c in chosen:
					d = minf(d, (spawns[k] as Vector2).distance_to(spawns[c]))
				if d > best_d:
					best_d = d
					best = k
			chosen.append(best)
	for team in team_count:
		var ids: Array = team_ids[team]
		var anchor: Vector2 = spawns[chosen[team % chosen.size()]] if not chosen.is_empty() else sim.arena.center()
		var fwd: Vector2 = (sim.arena.center() - anchor).normalized() if sim.arena.center().distance_to(anchor) > 1.0 else Vector2.RIGHT
		var side: Vector2 = Vector2(-fwd.y, fwd.x)
		var shape: Array = FORMATION.get(ids.size(), FORMATION[3])
		var members: Array = []
		for slot in ids.size():
			var d2: Defs.CharDef = DB.char_def(str(ids[slot]))
			var off: Vector2 = shape[slot % shape.size()]
			var p: Vector2 = sim.arena.resolve_circle(anchor + fwd * off.x + side * off.y, d2.stat("bodyRadius"))
			var u: BUnit = sim._new_unit(d2, team, slot, p)
			sim.heroes.append(u)
			inventory[u.idx] = []
			state[u.idx] = {}
			down_count[u.idx] = 0
			hstats[u.idx] = {"kills": 0, "knocks": 0, "revives": 0, "damage": 0.0, "items_picked": 0,
				"survival": 0.0, "death_cause": "", "death_time": -1.0, "assists": 0, "downs": 0}
			members.append(u.idx)
		teams.append(members)
	player_count = sim.heroes.size()
	zone = BrZone.new(sim.arena, sim.arena.data, sim.seed_value, zone_speed)
	_zone_tick_at = zone.shrink_start[1]
	for row: Dictionary in BrItems.place(sim.arena.data, sim.seed_value, int(sim.cfg.get("items", ITEM_COUNT))):
		uid_seq += 1
		field.append({"uid": uid_seq, "item": str(row.item), "pos": row.pos, "t": 0.0, "dropped": -1, "ring": int(row.ring)})
		sim.emit("DM_ITEM_SPAWNED", -1, -1, {"uid": uid_seq, "item": str(row.item), "pos": row.pos, "rarity": int(row.rarity), "silent": true})
	_field_dirty = true
	next_item_at = INF
	_prebuild_nav()
	_sample_series()


# Every body-size bucket the roster needs under every gate signature the map
# can show (the metropolis gates open and close as one group), built now so
# no path grid is built mid-match.
func _prebuild_nav() -> void:
	var sigs: Array = gate_signatures()
	for b in sim.nav_buckets():
		if sigs.is_empty():
			Navigator.for_sim(sim, float(b))
		for sig in sigs:
			Navigator.for_sim(sim, float(b), int(sig))


# Distinct navigation gate signatures over two minutes of the gate schedule
# (with and without the closing margin) plus all-open (gates switched off).
func gate_signatures() -> Array:
	var a: Arena = sim.arena
	if a == null or a.gates.is_empty():
		return []
	var found: Dictionary = {a.all_gates_open_bits(): true}
	for step in 480:
		var t: float = step * 0.25
		found[a.gate_bits_at(t, Arena.NAV_CLOSING_MARGIN)] = true
		found[a.gate_bits_at(t)] = true
	var out: Array = found.keys()
	out.sort()
	return out


# ---------------------------------------------------------------- contract

func team_members(team: int) -> Array[BUnit]:
	var out: Array[BUnit] = []
	if team >= 0 and team < teams.size():
		for idx in teams[team]:
			out.append(sim.u_at(int(idx)))
	return out


# Members still in the match (standing or downed); 0 = the team is out.
func team_alive(team: int) -> int:
	if team < 0 or team >= teams.size() or eliminated.has(team):
		return 0
	var n: int = 0
	for idx in teams[team]:
		var u: BUnit = sim.u_at(int(idx))
		if u and u.alive:
			n += 1
	return n


# Members on their feet (alive and not downed).
func team_standing(team: int) -> int:
	if team < 0 or team >= teams.size():
		return 0
	var n: int = 0
	for idx in teams[team]:
		var u: BUnit = sim.u_at(int(idx))
		if u and u.alive and not downed.has(u.idx):
			n += 1
	return n


func alive_team_count() -> int:
	return team_count - eliminated.size()


func alive_hero_count() -> int:
	var n: int = 0
	for u in sim.heroes:
		if u.alive:
			n += 1
	return n


func player_no(u: BUnit) -> int:
	return sim.heroes.find(u) + 1 if u else 0


func team_label(team: int) -> String:
	return DB.team_name(team, squad)


func is_downed(u: BUnit) -> bool:
	return u != null and downed.has(u.idx)


# {since, bleed_at, bleed_total, hp, max_hp, revive_progress (0..1),
#  reviver_idx (-1 none), knocker (-1 none), count (downs so far)}; {} when
# the hero is not downed.
func downed_info(u: BUnit) -> Dictionary:
	if u == null or not downed.has(u.idx):
		return {}
	var d: Dictionary = downed[u.idx]
	return {"since": float(d.since), "bleed_at": float(d.bleed_at), "bleed_total": float(d.bleed_total),
		"hp": maxf(0.0, u.hp), "max_hp": DOWNED_HP, "revive_progress": float(d.revive_progress),
		"reviver_idx": int(d.reviver_idx), "knocker": int(d.knocker), "count": int(d.count)}


func zone_view() -> Dictionary:
	return zone.public_view(sim.time)


func is_reviving(u: BUnit) -> bool:
	return u != null and reviving.has(u.idx)


# Downed heroes and revive channellers can neither cast nor attack.
func blocks_actions(u: BUnit) -> bool:
	return downed.has(u.idx) or reviving.has(u.idx)


func is_eliminated(team: int) -> bool:
	return eliminated.has(team)


func team_score(team: int) -> int:
	return kills[team] if team >= 0 and team < kills.size() else 0


func small_match() -> bool:
	return false


# ---------------------------------------------------------------- lifecycle

func pre_tick() -> void:
	for idx in _pending_cleanup.keys():
		_clean_life(sim.u_at(int(idx)))
	_pending_cleanup.clear()
	_process_wipes()
	# Controllers of eliminated teams stop planning and observing (B-PERF).
	# Detached at the start of a tick, never inside a controller's own call.
	for team in _detach_queue:
		sim.detach_controller(int(team))
	_detach_queue.clear()


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	_update_zone()
	_update_downed()
	_pickups()
	var second: int = int(floor(sim.time * 4.0))
	if second != _last_update_second:
		_last_update_second = second
		_quarter_second_effects()
	_process_wipes()
	if sim.time + 1e-6 >= _next_series_at:
		_sample_series()


func check_end() -> void:
	if sim.state == BattleSim.FINISHED:
		return
	if alive_team_count() <= 1:
		_finish("battleground_last")
	elif sim.time >= sim.max_time:
		_finish("battleground_time")


# Remaining teams at the end: more members still in the match first, then
# more total health (downed heroes count their downed health), then team id.
func _standing_order() -> Array:
	var rows: Array = []
	for team in team_count:
		if eliminated.has(team):
			continue
		var hp: float = 0.0
		for idx in teams[team]:
			var u: BUnit = sim.u_at(int(idx))
			if u and u.alive:
				hp += maxf(0.0, u.hp)
		rows.append([team, team_alive(team), hp])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]): return int(a[1]) > int(b[1])
		if absf(float(a[2]) - float(b[2])) > 0.001: return float(a[2]) > float(b[2])
		return int(a[0]) < int(b[0]))
	return rows


func _finish(reason: String) -> void:
	var rank: int = 1
	for row in _standing_order():
		placement[int(row[0])] = rank
		rank += 1
	winner_team = -1
	for team in placement:
		if int(placement[team]) == 1:
			winner_team = int(team)
	winner_order = []
	for r in range(1, team_count + 1):
		for team in placement:
			if int(placement[team]) == r:
				winner_order.append(int(team))
	for u in sim.heroes:
		if u.alive:
			hstats[u.idx]["survival"] = sim.time
	_sample_series()
	sim.finish(winner_team, reason)


# Heroes by their team's placement (teams still in play: by _standing_order),
# then heroes still alive, kills, damage dealt and index.
func ranking() -> Array:
	var team_rank: Dictionary = placement.duplicate()
	var next: int = 1
	for row in _standing_order():
		if not team_rank.has(int(row[0])):
			team_rank[int(row[0])] = next
		next += 1
	var order: Array = []
	for u in sim.heroes:
		order.append(u)
	order.sort_custom(func(a: BUnit, b: BUnit):
		var ra: int = int(team_rank.get(a.team, 999))
		var rb: int = int(team_rank.get(b.team, 999))
		if ra != rb: return ra < rb
		if a.alive != b.alive: return a.alive
		var ka: int = int(hstats[a.idx].kills)
		var kb: int = int(hstats[b.idx].kills)
		if ka != kb: return ka > kb
		var da: float = float(hstats[a.idx].damage)
		var db: float = float(hstats[b.idx].damage)
		if absf(da - db) > 0.001: return da > db
		return a.idx < b.idx)
	return order


func result() -> Dictionary:
	var rows: Array = []
	for u in ranking():
		var hs: Dictionary = hstats[u.idx]
		rows.append({"rank": int(placement.get(u.team, 0)), "idx": u.idx, "team": u.team, "id": u.def.id, "name": u.name,
			"kills": int(hs.kills), "knocks": int(hs.knocks), "revives": int(hs.revives), "deaths": 0 if u.alive else 1,
			"assists": int(hs.assists), "best_streak": 0, "items": int(hs.items_picked), "damage": float(hs.damage),
			"survival": float(hs.survival) if not u.alive or sim.state == BattleSim.FINISHED else sim.time,
			"death_cause": str(hs.death_cause), "held": (inventory.get(u.idx, []) as Array).duplicate()})
	return {"kill_target": kill_target, "ranking": rows, "field_items": field.size(), "kill_log": kill_log.duplicate(true),
		"players": sim.heroes.size(), "preset": str(sim.arena.data.get("preset", "")), "battleground": br_result()}


func br_result() -> Dictionary:
	var team_rows: Array = []
	for team in team_count:
		team_rows.append({"team": team, "label": team_label(team), "members": (teams[team] as Array).duplicate(),
			"place": int(placement.get(team, 0)), "elim_time": float(elim_time.get(team, -1.0))})
	return {"squad": squad, "team_count": team_count, "teams": team_rows, "placement": placement.duplicate(),
		"elim_time": elim_time.duplicate(), "elim_order": elim_order.duplicate(), "winner_team": winner_team,
		"zone_speed": zone_speed, "zone_final": zone.final_time(), "series": series.duplicate(true),
		"hstats": hstats.duplicate(true)}


func _sample_series() -> void:
	_next_series_at = sim.time + SERIES_EVERY
	var row: Array = [sim.time, alive_team_count(), alive_hero_count()]
	if not series.is_empty():
		var last: Array = series[series.size() - 1]
		if absf(float(last[0]) - sim.time) < 1e-6:
			series[series.size() - 1] = row
			return
	series.append(row)


# Public event: every team sees it (sim.emit computes observer visibility).
func _public(ev: Dictionary) -> Dictionary:
	var all: Array = []
	all.resize(sim.team_count)
	all.fill(true)
	ev["sv"] = all
	ev["gv"] = all.duplicate()
	ev["public"] = true
	return ev


func _feed(entry: Dictionary) -> void:
	kill_feed.append(entry)
	if kill_feed.size() > 60:
		kill_feed.pop_front()


# DeathmatchMode._quarter_second_effects (forest exit for the shadow cloak,
# out-of-combat regeneration, berserk) with one battleground rule: no
# regeneration while standing outside the circle during a damage phase. Zone
# damage never resets the out-of-combat timer, so regeneration resumes the
# moment the hero is back inside (DESIGN_V2 §3.3).
func _quarter_second_effects() -> void:
	var t: float = sim.time
	var zone_on: bool = zone.dps_ratio_at(t) > 0.0
	for u in sim.heroes:
		if not u.alive:
			continue
		var st: Dictionary = state.get(u.idx, {})
		var in_forest: bool = sim.arena.forest_at(u.pos) >= 0
		if bool(st.get("in_forest", false)) and not in_forest:
			st["forest_exit"] = sim.time
			st["ambush_used"] = false
		st["in_forest"] = in_forest
		var delay: float = 7.0
		var rate: float = 0.015
		for rg in _items_with(u, "regen"):
			delay = minf(delay, float(rg.delay))
			rate += float(rg.ratio)
		if sim.time - u.last_damage_time >= delay and sim.time - u.last_combat_time >= delay and u.hp < sim.max_hp(u) 				and not (zone_on and zone.outside(u.pos, t)):
			sim.apply_heal(u, u, {"base": sim.max_hp(u) * rate * 0.25}, {"source_type": "REGEN", "proc": true, "silent": true})
		for bz in _items_with(u, "berserk"):
			var low: bool = u.hp / maxf(1.0, sim.max_hp(u)) < float(bz.below)
			var on: bool = bool(st.get("berserk_on", false))
			if low and not on:
				sim.add_buff(u, &"attackSpeed", float(bz.as), INF, u.idx, {"tag": "item_berserk"})
				sim.add_buff(u, &"attackDamage", float(bz.ad), INF, u.idx, {"tag": "item_berserk"})
				st["berserk_on"] = true
			elif not low and on:
				sim.remove_buffs_tag(u, "item_berserk")
				st["berserk_on"] = false
		state[u.idx] = st


# ---------------------------------------------------------------- zone

func _update_zone() -> void:
	var t: float = sim.time
	while _zone_announced < BrZone.PHASES and t + 1e-6 >= zone.announce_at[_zone_announced + 1]:
		_zone_announced += 1
		var k: int = _zone_announced
		_public(sim.emit("BR_ZONE_ANNOUNCE", -1, -1, {"phase": k, "center": zone.centers[k], "radius": zone.radii[k],
			"shrink_start": zone.shrink_start[k], "shrink_end": zone.shrink_end[k], "dps_ratio": zone.dps[k]}))
	while _zone_shrunk < BrZone.PHASES and t + 1e-6 >= zone.shrink_start[_zone_shrunk + 1]:
		_zone_shrunk += 1
		var k2: int = _zone_shrunk
		_public(sim.emit("BR_ZONE_SHRINK", -1, -1, {"phase": k2, "center": zone.centers[k2], "radius": zone.radii[k2],
			"shrink_end": zone.shrink_end[k2], "dps_ratio": zone.dps[k2]}))
	if t + 1e-6 < _zone_tick_at:
		return
	_zone_tick_at += BrZone.TICK
	if _zone_tick_at <= t:
		_zone_tick_at = t + BrZone.TICK
	var ratio: float = zone.dps_ratio_at(t) * BrZone.TICK
	if ratio <= 0.0:
		return
	_zone_hitting = true
	for u in sim.heroes:
		if u.alive and zone.outside(u.pos, t):
			sim.env._env_damage(u, ZONE_HAZARD, sim.max_hp(u) * ratio * (DOWNED_TAKEN if downed.has(u.idx) else 1.0))
	_zone_hitting = false


# ---------------------------------------------------------------- downed / revive

func try_revive(t: BUnit, s: BUnit) -> bool:
	if downed.has(t.idx):
		return false
	return super.try_revive(t, s)


# Lethal damage on a squad hero with a teammate still standing: downed
# instead of dead (sim.kill_unit asks after the phoenix). False = the hero dies.
func try_down(t: BUnit, s: BUnit, ctx: Dictionary) -> bool:
	if squad <= 1 or downed.has(t.idx) or eliminated.has(t.team):
		return false
	if ctx.get("br_wipe", false) or ctx.get("br_bleed", false):
		return false
	var other_standing: bool = false
	for idx in teams[t.team]:
		var m: BUnit = sim.u_at(int(idx))
		if m != t and m.alive and not downed.has(m.idx):
			other_standing = true
			break
	if not other_standing:
		return false
	var knocker: BUnit = _credit_for(t, s, ctx)
	if reviving.has(t.idx):
		cancel_revive(int(reviving[t.idx]), "reviver_down")
	sim.reset_commitment(t, "downed")
	t.hp = DOWNED_HP
	t.shields.clear()
	down_count[t.idx] = int(down_count.get(t.idx, 0)) + 1
	var n: int = int(down_count[t.idx])
	var bleed: float = float(BLEED_TIMES[mini(n, BLEED_TIMES.size()) - 1])
	downed[t.idx] = {"since": sim.time, "bleed_at": sim.time + bleed, "bleed_total": bleed, "revive_progress": 0.0,
		"reviver_idx": -1, "revive_start": -1.0, "knocker": knocker.idx if knocker else -1, "count": n, "hp": DOWNED_HP}
	sim.push_status(t, &"downed", -1, INF, {"br_downed": true})
	hstats[t.idx]["downs"] = int(hstats[t.idx].downs) + 1
	if knocker:
		hstats[knocker.idx]["knocks"] = int(hstats[knocker.idx].knocks) + 1
	var data: Dictionary = {"team": t.team, "count": n, "bleed_at": sim.time + bleed, "bleed_total": bleed, "pos": t.pos,
		"knocker": knocker.idx if knocker else -1, "zone": _zone_hitting}
	sim.emit("BR_DOWNED", knocker.idx if knocker else -1, t.idx, data)
	_feed({"t": sim.time, "kind": "knock", "killer": knocker.idx if knocker else -1, "victim": t.idx, "team": t.team,
		"public": false, "assists": [], "streak": 0, "score": 0})
	return true


# Starts a revive channel. The controller asks; false when the reviver or the
# target is not eligible (another channel, out of range, crowd controlled,
# busy). The channel then runs in _update_downed.
func start_revive(reviver: BUnit, target: BUnit) -> bool:
	if reviver == null or target == null or not reviver.alive or not target.alive:
		return false
	if downed.has(reviver.idx) or reviving.has(reviver.idx) or not downed.has(target.idx) or reviver.team != target.team:
		return false
	var d: Dictionary = downed[target.idx]
	if int(d.reviver_idx) >= 0:
		return false
	if not in_revive_range(reviver, target) or reviver.action != null or reviver.motion != null or sim.has_any(reviver, REVIVE_BREAK):
		return false
	d["reviver_idx"] = reviver.idx
	d["revive_start"] = sim.time
	d["revive_progress"] = 0.0
	reviving[reviver.idx] = target.idx
	reviver.command = {}
	# The target may still have a crawl order until its next 0.3 s decision.
	# Stop that voluntary motion now; forced motion remains interruptible.
	target.command = {}
	target.vel = Vector2.ZERO
	sim.emit("BR_REVIVE_START", reviver.idx, target.idx, {"team": target.team, "pos": target.pos, "ends": sim.time + REVIVE_TIME})
	return true


func in_revive_range(a: BUnit, b: BUnit) -> bool:
	return a.pos.distance_to(b.pos) - sim.radius(a) - sim.radius(b) <= REVIVE_RANGE


func cancel_revive(target_idx: int, reason: String) -> void:
	var d: Dictionary = downed.get(target_idx, {})
	if d.is_empty() or int(d.reviver_idx) < 0:
		return
	var reviver: int = int(d.reviver_idx)
	reviving.erase(reviver)
	var progress: float = float(d.revive_progress)
	d["reviver_idx"] = -1
	d["revive_start"] = -1.0
	d["revive_progress"] = 0.0
	var t: BUnit = sim.u_at(target_idx)
	sim.emit("BR_REVIVE_CANCEL", reviver, target_idx, {"reason": reason, "progress": progress, "pos": t.pos if t else Vector2.ZERO})


func _revive(t: BUnit) -> void:
	var d: Dictionary = downed[t.idx]
	var reviver: int = int(d.reviver_idx)
	reviving.erase(reviver)
	downed.erase(t.idx)
	sim.remove_statuses_where(t, func(st): return st.type == &"downed")
	# Not a heal: heal block and healing modifiers do not apply.
	t.hp = sim.max_hp(t) * REVIVE_HP
	t.command = {}
	t.next_decision_at = sim.time
	if hstats.has(reviver):
		hstats[reviver]["revives"] = int(hstats[reviver].revives) + 1
	sim.emit("BR_REVIVED", reviver, t.idx, {"team": t.team, "hp": t.hp, "pos": t.pos})
	_feed({"t": sim.time, "kind": "revive", "killer": reviver, "victim": t.idx, "team": t.team, "public": false,
		"assists": [], "streak": 0, "score": 0})


func _update_downed() -> void:
	if downed.is_empty():
		return
	var keys: Array = downed.keys()
	keys.sort()
	for k in keys:
		var idx: int = int(k)
		if not downed.has(idx):
			continue
		var u: BUnit = sim.u_at(idx)
		var d: Dictionary = downed[idx]
		if u == null or not u.alive:
			downed.erase(idx)
			continue
		# Downed health only goes down (a stray max-health buff cannot raise it).
		d["hp"] = minf(float(d.hp), u.hp)
		u.hp = float(d.hp)
		if not sim.has_status(u, &"downed"):
			sim.push_status(u, &"downed", -1, INF, {"br_downed": true})
		if sim.time + 1e-6 >= float(d.bleed_at):
			if int(d.reviver_idx) >= 0:
				cancel_revive(idx, "bled_out")
			sim.emit("BR_BLED_OUT", -1, idx, {"team": u.team, "pos": u.pos})
			sim.kill_unit(u, null, {"br_bleed": true})
			continue
		var r_idx: int = int(d.reviver_idx)
		if r_idx < 0:
			continue
		var r: BUnit = sim.u_at(r_idx)
		var why: String = ""
		if r == null or not r.alive or downed.has(r_idx):
			why = "reviver_down"
		elif not in_revive_range(r, u):
			why = "range"
		elif r.motion != null or sim.has_any(r, REVIVE_BREAK):
			why = "cc"
		if why != "":
			cancel_revive(idx, why)
			continue
		d["revive_progress"] = clampf((sim.time - float(d.revive_start)) / REVIVE_TIME, 0.0, 1.0)
		if float(d.revive_progress) >= 1.0 - 1e-6:
			_revive(u)


# ---------------------------------------------------------------- deaths

# Who gets the credit for a down or a death: the attacker's hero; for the
# zone (and other source-less damage) the last enemy hero that hit the
# victim within ZONE_CREDIT_WINDOW s (feed and stats only).
func _credit_for(t: BUnit, s: BUnit, ctx: Dictionary) -> BUnit:
	var killer: BUnit = _credited_hero(s)
	if killer != null and (killer == t or killer.team == t.team):
		killer = null
	if killer == null or ctx.get("env", false):
		var best: int = -1
		var best_t: float = -INF
		var hits: Dictionary = recent_hits.get(t.idx, {})
		for a in hits:
			var when: float = float(hits[a])
			var au: BUnit = sim.u_at(int(a))
			if au == null or au.team == t.team or sim.time - when > ZONE_CREDIT_WINDOW:
				continue
			if when > best_t or (when == best_t and int(a) < best):
				best_t = when
				best = int(a)
		if best >= 0:
			killer = sim.u_at(best)
	return killer


func on_death(t: BUnit, s: BUnit, ctx: Dictionary) -> void:
	if not t.is_hero or str(hstats.get(t.idx, {}).get("death_cause", "x")) != "":
		return
	var info: Dictionary = downed.get(t.idx, {})
	if reviving.has(t.idx):
		cancel_revive(int(reviving[t.idx]), "reviver_down")
	if not info.is_empty() and int(info.reviver_idx) >= 0:
		cancel_revive(t.idx, "target_died")
	downed.erase(t.idx)
	var cause: String = "kill"
	var killer: BUnit = null
	var knocker: BUnit = sim.u_at(int(info.knocker)) if not info.is_empty() and int(info.knocker) >= 0 else null
	if ctx.get("br_bleed", false):
		cause = "bleed"
		killer = knocker
	elif ctx.get("br_wipe", false):
		cause = "team_wipe"
		killer = knocker
	else:
		killer = _credit_for(t, s, ctx)
		if ctx.get("env", false):
			cause = "zone" if _zone_hitting else "hazard"
		if killer == null and knocker != null:
			killer = knocker
	var assisters: Array = []
	var hits: Dictionary = recent_hits.get(t.idx, {})
	for attacker_idx in hits:
		var when: float = float(hits[attacker_idx])
		var au: BUnit = sim.u_at(int(attacker_idx))
		if au and au.team != t.team and sim.time - when <= ASSIST_WINDOW and (killer == null or int(attacker_idx) != killer.idx):
			assisters.append(int(attacker_idx))
	recent_hits.erase(t.idx)
	deaths[t.team] += 1
	streak[t.team] = 0
	if killer:
		kills[killer.team] += 1
		streak[killer.team] += 1
		best_streak[killer.team] = maxi(best_streak[killer.team], streak[killer.team])
		hstats[killer.idx]["kills"] = int(hstats[killer.idx].kills) + 1
		if cause == "kill":
			_on_kill_items(killer)
	for a_idx in assisters:
		var a: BUnit = sim.u_at(a_idx)
		if a and a.is_hero:
			assists[a.team] += 1
			hstats[a_idx]["assists"] = int(hstats[a_idx].assists) + 1
	var hs: Dictionary = hstats[t.idx]
	hs["death_cause"] = cause
	hs["death_time"] = sim.time
	hs["survival"] = sim.time
	var entry: Dictionary = {"t": sim.time, "kind": "kill", "killer": killer.idx if killer else -1, "victim": t.idx,
		"assists": assisters, "cause": cause, "team": t.team, "public": true,
		"streak": streak[killer.team] if killer else 0, "score": kills[killer.team] if killer else 0}
	_feed(entry)
	kill_log.append([sim.time, killer.team if killer else -1, t.team])
	_public(sim.emit("DM_KILL", killer.idx if killer else -1, t.idx, entry.duplicate()))
	_public(sim.emit("BR_ELIMINATED", killer.idx if killer else -1, t.idx, {"team": t.team, "cause": cause,
		"killer": killer.idx if killer else -1}))
	_drop_on_death(t)
	inventory[t.idx] = []
	state[t.idx] = {}
	_clean_life(t)
	_pending_cleanup[t.idx] = true
	_team_check(t.team)


func _team_check(team: int) -> void:
	if eliminated.has(team) or team_standing(team) > 0:
		return
	eliminated[team] = true
	var place: int = team_count - eliminated.size() + 1
	placement[team] = place
	elim_time[team] = sim.time
	elim_order.append(team)
	_public(sim.emit("BR_TEAM_OUT", -1, -1, {"team": team, "place": place}))
	_feed({"t": sim.time, "kind": "team_out", "killer": -1, "victim": -1, "team": team, "place": place, "public": true,
		"assists": [], "streak": 0, "score": 0})
	for idx in teams[team]:
		if downed.has(int(idx)):
			_wipe_queue.append(team)
			break
	_detach_queue.append(team)
	_sample_series()


# Downed members of an eliminated team die (outside the death callback that
# eliminated it, credited to whoever downed them).
func _process_wipes() -> void:
	while not _wipe_queue.is_empty():
		var team: int = int(_wipe_queue.pop_front())
		for idx in teams[team]:
			var u: BUnit = sim.u_at(int(idx))
			if u and u.alive and downed.has(u.idx):
				sim.kill_unit(u, null, {"br_wipe": true})


# A final death drops every held item around the body (downed heroes keep theirs).
func _drop_on_death(t: BUnit) -> void:
	var bag: Array = inventory.get(t.idx, [])
	for k in bag.size():
		var id: String = str(bag[k])
		uid_seq += 1
		var off: Vector2 = Vector2.from_angle(TAU * float(k) / float(maxi(1, bag.size())) + 0.4) * (26.0 if bag.size() > 1 else 0.0)
		var p: Vector2 = sim.arena.resolve_circle(t.pos + off, 14.0)
		field.append({"uid": uid_seq, "item": id, "pos": p, "t": sim.time, "dropped": t.idx})
		sim.emit("DM_ITEM_DROPPED", t.idx, t.idx, {"uid": uid_seq, "item": id, "pos": p, "reason": "death"})
	_field_dirty = true


# Item reductions (aegis), then the downed share (DOWNED_TAKEN).
func incoming_mult(t: BUnit) -> float:
	var m: float = super.incoming_mult(t)
	if downed.has(t.idx):
		m *= DOWNED_TAKEN
	return m


func on_damage(s: BUnit, t: BUnit, hp_dmg: float, absorbed: float, ctx: Dictionary) -> void:
	super.on_damage(s, t, hp_dmg, absorbed, ctx)
	if not t.is_hero or hp_dmg + absorbed <= 0.0:
		return
	var src: BUnit = _credited_hero(s)
	if src and src.team != t.team and hstats.has(src.idx):
		hstats[src.idx]["damage"] = float(hstats[src.idx].damage) + hp_dmg
	if reviving.has(t.idx) and s != null and sim.eteam(s) != sim.eteam(t):
		cancel_revive(int(reviving[t.idx]), "damage")


# ---------------------------------------------------------------- items

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / PICK_CELL)), int(floor(p.y / PICK_CELL)))


func _rebuild_field_cells() -> void:
	_field_cells.clear()
	for it in field:
		var c: Vector2i = _cell_of(it.pos)
		if not _field_cells.has(c):
			_field_cells[c] = []
		(_field_cells[c] as Array).append(it)
	_field_dirty = false


# Field items within reach of p, in field order.
func _items_near(p: Vector2, reach: float) -> Array:
	if _field_dirty:
		_rebuild_field_cells()
	var out: Array = []
	var c0: Vector2i = _cell_of(p - Vector2(reach, reach))
	var c1: Vector2i = _cell_of(p + Vector2(reach, reach))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for it in _field_cells.get(Vector2i(cx, cy), []):
				if (it.pos as Vector2).distance_to(p) <= reach:
					out.append(it)
	if out.size() > 1:
		out.sort_custom(func(a, b): return int(a.uid) < int(b.uid))
	return out


# DeathmatchMode._pickups with a spatial grid, per-hero stats and the swap
# event; downed heroes and revive channellers pick nothing up.
func _pickups() -> void:
	if field.is_empty():
		return
	for u in sim.heroes:
		if not u.alive or u.chamber != "" or u.motion != null or downed.has(u.idx) or reviving.has(u.idx):
			continue
		var reach: float = PICK_RADIUS + sim.radius(u)
		for it in _items_near(u.pos, reach):
			if not field.has(it):
				continue
			var key: String = "%d:%d" % [u.idx, int(it.uid)]
			if declined.has(key) and sim.time - float(declined[key]) < 4.0:
				continue
			var choice: Dictionary = _decide_pickup(u, it)
			if not bool(choice.get("take", false)):
				declined[key] = sim.time
				sim.emit("DM_ITEM_SKIPPED", u.idx, u.idx, {"uid": it.uid, "item": it.item, "reason": str(choice.get("reason", "")), "silent": true})
				continue
			var drop_slot: int = int(choice.get("drop_slot", -1))
			var bag: Array = inventory.get(u.idx, [])
			var swapped: String = ""
			if bag.size() >= SLOTS:
				if drop_slot < 0 or drop_slot >= bag.size():
					continue
				swapped = str(bag[drop_slot])
				_remove_item(u, swapped)
				bag.remove_at(drop_slot)
				uid_seq += 1
				var dropped: Dictionary = {"uid": uid_seq, "item": swapped, "pos": sim.arena.resolve_circle(u.pos - u.facing * 30.0, 14.0), "t": sim.time, "dropped": u.idx}
				field.append(dropped)
				sim.emit("DM_ITEM_DROPPED", u.idx, u.idx, {"uid": uid_seq, "item": swapped, "pos": dropped.pos, "reason": "swap"})
			field.erase(it)
			_field_dirty = true
			bag.append(str(it.item))
			inventory[u.idx] = bag
			items_picked[u.team] += 1
			hstats[u.idx]["items_picked"] = int(hstats[u.idx].items_picked) + 1
			_apply_item(u, str(it.item))
			sim.emit("DM_ITEM_PICKED", u.idx, u.idx, {"uid": it.uid, "item": it.item, "pos": it.pos, "reason": str(choice.get("reason", "")),
				"rarity": ItemDefs.rarity_of(str(it.item)), "slots": bag.duplicate()})
			if swapped != "":
				sim.emit("BR_ITEM_SWAP", u.idx, u.idx, {"took": str(it.item), "dropped": swapped, "slot": drop_slot, "pos": u.pos, "slots": bag.duplicate()})
