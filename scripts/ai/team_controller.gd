class_name TeamController
extends RefCounted


var sim: BattleSim
var team: int = 0
var label: String = "AI"


func _init(s: BattleSim, t: int) -> void :
	sim = s
	team = t


func on_start(_s: BattleSim) -> void :
	pass


func pre_tick(_s: BattleSim) -> void :
	pass


func decide(_u: BUnit) -> void :
	pass


func steer(_u: BUnit) -> Vector2:
	return Vector2.ZERO


func emergency(_u: BUnit) -> bool:
	return false


func reveal_choice(_u: BUnit) -> int:
	return -1


# Walking route only: without a unit there is no speed or portal / pad
# cooldown to price links with, and a link whose type is switched off would
# be routed into forever (heroes use Navigator.unit_waypoint instead).
func route_point(from: Vector2, goal: Vector2, r: float) -> Vector2:
	return navigator_for(r).next_waypoint(from, goal, r, 0.0, 0.0, 0.0, false)


# The one place controllers obtain a path grid, so grid selection (radius
# bucket, and any future dynamic-wall state) stays consistent everywhere.
func navigator_for(r: float) -> Navigator:
	return Navigator.for_sim(sim, r)


func dispose() -> void :
	sim = null



func explain(_u: BUnit) -> Dictionary:
	return {}
