class_name AIFactory
extends RefCounted


const KINDS: = {"tactician": "전술가 AI (V1.5.3)", "tactician14": "전술가 AI V1.4 (비교용)", "classic": "기본 AI (비교용)"}
const ORDER: = ["tactician", "tactician14", "classic"]


static func make(kind: String, sim: BattleSim, team: int) -> TeamController:
	if kind.begins_with("res://"):

		var script: GDScript = load(kind)
		return script.new(sim, team)
	if kind.begins_with("tactician{"):

		var brain: TacticianBrain = battleground_brain(sim, team) if sim.is_battleground() else (DeathmatchBrain.new(sim, team) if sim.is_deathmatch() else TacticianBrain.new(sim, team))
		var body: = kind.substr(10, kind.length() - 11)
		for pair in body.split(",", false):
			var kv: = pair.split("=")
			if kv.size() == 2:
				brain.cfg[kv[0].strip_edges()] = float(kv[1])
		return brain
	if sim.is_battleground():
		return battleground_brain(sim, team)
	if sim.is_deathmatch():
		return DeathmatchBrain.new(sim, team)
	match kind:
		"classic":
			return ClassicBrain.new(sim, team)
		"tactician14":
			# The V1.4 conquest planner and team-wide fight plan, for comparison.
			var old: = TacticianBrain.new(sim, team)
			old.cfg["v15"] = 0.0
			old.label = "전술가 AI V1.4"
			return old
		_:
			return TacticianBrain.new(sim, team)


static func label(kind: String) -> String:
	return str(KINDS.get(kind, kind))


# V2 battleground: every AI kind plays it with the battleground brains (as in
# deathmatch): one solo brain per hero, or one squad brain per duo / trio.
static func battleground_brain(sim: BattleSim, team: int) -> TacticianBrain:
	if sim.battleground != null and sim.battleground.squad > 1:
		return BattlegroundSquadBrain.new(sim, team)
	return BattlegroundSoloBrain.new(sim, team)
