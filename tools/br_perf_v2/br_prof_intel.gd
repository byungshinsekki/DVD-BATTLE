extends TeamIntel

# Timing wrapper around TeamIntel (B-PERF tool only). Calls the unchanged
# implementation and records how long each phase took.

const P := preload("res://tools/br_perf_v2/br_prof.gd")


func observe() -> void:
	var t0: int = Time.get_ticks_usec()
	super.observe()
	P.add("intel.observe(incl propagate)", Time.get_ticks_usec() - t0)


func _propagate(dt: float) -> void:
	var t0: int = Time.get_ticks_usec()
	super._propagate(dt)
	P.add("intel._propagate", Time.get_ticks_usec() - t0)


func observe_fast() -> void:
	var t0: int = Time.get_ticks_usec()
	super.observe_fast()
	P.add("intel.observe_fast", Time.get_ticks_usec() - t0)


func ingest(events: Array) -> void:
	var t0: int = Time.get_ticks_usec()
	super.ingest(events)
	P.add("intel.ingest", Time.get_ticks_usec() - t0)
