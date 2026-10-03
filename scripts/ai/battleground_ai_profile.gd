class_name BattlegroundAIProfile
extends RefCounted

# Offline measurement shared by the solo and squad layers. Keep this leaf
# independent of both brains: their shared zone helpers otherwise create a
# strong script-resource cycle. No decision reads elapsed time or counters.
static var lprof_on: bool = false
static var lprof: Dictionary = {}


static func lp_add(key: String, t0: int) -> void:
	lprof[key] = int(lprof.get(key, 0)) + Time.get_ticks_usec() - t0
