class_name ST
extends RefCounted



class Status:
	extends RefCounted
	var type: StringName
	var source_idx: int = -1
	var start: float = 0.0
	var end: float = 0.0
	var duration: float = 0.0
	var stacks: int = 1
	var magnitude: float = 0.0
	var extra: Dictionary = {}

	var interval: float = 0.0
	var next_tick: float = 0.0
	var dmg: Dictionary = {}
	var ability: Defs.AbilityDef = null
	var ctx: Dictionary = {}


class Buff:
	extends RefCounted
	var stat: StringName
	var amount: float = 0.0
	var end: float = 0.0
	var source_idx: int = -1
	var tag: String = ""
	var extra: Dictionary = {}


class Shield:
	extends RefCounted
	var amount: float = 0.0
	var max_amount: float = 0.0
	var end: float = 0.0
	var source_idx: int = -1
	var affection: bool = false
	var seq: int = 0
	# V2: shield family for per-source caps (war_machine arc protector "arc").
	var tag: String = ""


class Motion:
	extends RefCounted
	var id: int = 0
	var kind: String = "dash"
	var start: Vector2
	var end: Vector2
	var speed: float = 500.0
	var at: float = 0.0
	var deadline: float = 0.0
	var source_idx: int = -1
	var target_idx: int = -1
	var ctx: Dictionary = {}
	var hit_effects: Array = []
	var unstoppable: bool = false
	var invulnerable: bool = false
	var flight: bool = false
	var hook: bool = false


class Action:
	extends RefCounted
	var id: int = 0
	var kind: String = "ability"
	var ability: Defs.AbilityDef = null
	var ability_index: int = -1
	var target_idx: int = -1
	var target_pos: Vector2
	var extra: Dictionary = {}
	var started_at: float = 0.0
	var resolve_at: float = 0.0
	var recover_at: float = 0.0
	var windup: bool = true
	var source_team: int = 0
	var resources: Dictionary = {}


class Projectile:
	extends RefCounted
	var id: int = 0
	var source_idx: int = -1
	var shooter_idx: int = -1
	var team: int = 0
	var pos: Vector2
	var prev_pos: Vector2
	var launch_pos: Vector2
	var vel: Vector2
	var speed: float = 400.0
	var target_idx: int = -1
	var target_pos: Vector2
	var homing: bool = false
	var radius: float = 5.0
	var distance: float = 0.0
	var max_distance: float = 400.0
	var bounces: int = 0
	var pierce: int = 0
	var hit_ids: Dictionary = {}
	var ability: Defs.AbilityDef = null
	var source_type: String = "ABILITY"
	var effects: Array = []
	var ctx: Dictionary = {}
	var explode_on_arrival: bool = false
	var return_to_source: bool = false
	var returning: bool = false
	var leg: int = 0
	var born_at: float = 0.0
	var reflection_count: int = 0
	var reflected: bool = false
	var wing: bool = false
	var portals_used: Array = []
	var portal_amplified: bool = false
	var seen_counts: Dictionary = {}
	var color: Color = Color.WHITE
	var pattern: String = "basic"
	var basic: bool = false
	var realm: String = ""
	var turret: bool = false
	var area_resolved: bool = false
	var driver: bool = false
	var dead: bool = false


class Zone:
	extends RefCounted
	var id: int = 0
	var kind: String = "zone"
	var source_idx: int = -1
	var team: int = 0
	var pos: Vector2
	var radius: float = 40.0
	var start: float = 0.0
	var end: float = 0.0
	var interval: float = 0.25
	var next_tick: float = 0.0
	var effects: Array = []
	var filter: String = "enemy"
	var ctx: Dictionary = {}
	var color: Color = Color.WHITE
	var shape: String = "circle"
	var dir: Vector2 = Vector2.RIGHT
	@warning_ignore("shadowed_global_identifier")
	var range: float = 0.0
	var angle: float = 1.0
	var trigger_once: bool = false
	# V2: each unit is affected at most once while the zone keeps ticking.
	var once_per_unit: bool = false
	# V2: rect zones (shape "rect") run from pos along dir for range, this wide.
	var width: float = 0.0
	var hits: Dictionary = {}
	var finished: bool = false
	var data: Dictionary = {}
	var pattern: String = ""
