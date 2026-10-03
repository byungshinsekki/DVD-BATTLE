class_name BUnit
extends RefCounted


var idx: int = -1
var id: String = ""
var team: int = 0
var slot: int = 0
var def: Defs.CharDef
var is_hero: bool = true
var kind: String = ""
var owner_idx: int = -1
var name: String = ""

var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: float = 1.0
var alive: bool = true
var death_time: float = -1.0
var spawn_time: float = 0.0
var spawn_pos: Vector2 = Vector2.ZERO
var life_id: int = 0
var end_time: float = INF

var shields: Array[ST.Shield] = []
var statuses: Array[ST.Status] = []
var buffs: Array[ST.Buff] = []
var cooldowns: PackedFloat64Array = PackedFloat64Array()
var attack_ready_at: float = 0.0
var action: ST.Action = null
var motion: ST.Motion = null
var resources: Dictionary = {}
var last_damage_time: float = -999.0
var last_combat_time: float = -999.0
var ks: Dictionary = {}
var sealed: Array = []
var chamber: String = ""
var portal_until: float = 0.0
# Environment jump-pad re-use time (ArenaEnv; per hero, public own state).
var pad_until: float = 0.0


var base_max_hp: float = 1000.0
var base_radius: float = 17.0
var base_ms: float = 95.0
var base_as: float = 0.75
var base_range: float = 60.0


var mass: float = 1.0
var accel_time: float = 0.3
var brake_time: float = 0.2
var reverse_time: float = 0.4
var turn_rate: float = 8.0
var lateral_grip: float = 0.9


var attack_eff: Dictionary = {}
var interval: float = 1.0
var next_attack: float = 0.0
var move_speed_ent: float = 0.0
var on_hit_status: Dictionary = {}
var consume_on_hit: bool = false
var level: int = 1
var ent_range: float = 0.0
var next_pulse: float = 0.0
var structure: bool = false
var ctx: Dictionary = {}
var target_idx: int = -1


var command: Dictionary = {}
var next_decision_at: float = 0.0
var decisions: int = 0


var st_damage: float = 0.0
var st_taken: float = 0.0
var st_healing: float = 0.0
var st_shielding: float = 0.0
var st_mitigated: float = 0.0
var st_cc: float = 0.0
var st_kills: int = 0
var st_deaths: int = 0
var st_casts: int = 0
var st_basic_hits: int = 0
var st_dodges: int = 0
var st_health_cost: float = 0.0
var st_capture_time: float = 0.0
var st_captures: int = 0
var st_zone_healing: float = 0.0


func is_entity() -> bool:
	return not is_hero


func setup_profile() -> void :
	var r: = maxf(10.0, base_radius)
	var spd: = maxf(24.0, base_ms)
	var role_factor: float = {"FRONTLINE": 1.18, "DAMAGE": 0.96, "CONTROL": 1.02, "SUPPORT": 1.04}.get(def.role, 1.0)
	var mobility: = def.tags.has("MOBILITY")
	mass = clampf(pow(r / 17.0, 2.0) * role_factor, 0.58, 2.65)
	var agility: = clampf(spd / 110.0 / sqrt(mass), 0.52, 1.72)
	accel_time = clampf(0.39 * sqrt(mass) / agility - (0.045 if mobility else 0.0), 0.16, 0.62)
	brake_time = clampf(accel_time * (0.72 + mass * 0.055), 0.12, 0.48)
	reverse_time = clampf(accel_time * (1.2 + mass * 0.08), 0.24, 0.78)
	turn_rate = clampf(6.1 * agility + (1.25 if mobility else 0.0), 3.8, 12.8)
	lateral_grip = clampf(0.74 + agility * 0.22 - mass * 0.06, 0.58, 1.08)
