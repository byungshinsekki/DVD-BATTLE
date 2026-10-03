extends RefCounted

# Shared timing table for the B-PERF profiling wrappers (tools only; never
# shipped). Keys are section labels, values are total microseconds / calls.

static var T: Dictionary = {}
static var N: Dictionary = {}


static func add(k: String, us: int) -> void:
	T[k] = int(T.get(k, 0)) + us
	N[k] = int(N.get(k, 0)) + 1


static func reset() -> void:
	T.clear()
	N.clear()
