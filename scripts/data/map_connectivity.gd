class_name MapConnectivity
extends RefCounted

# Offline map validation, not a per-tick navigation service. Cost is
# O(radius_count * gate_states * width * height / step^2), with physical
# segment tests on at most eight neighbours per lattice point. At step=8 a
# 7712x4336 map has about 522k points per radius/state; use a coarser step for
# exploratory large-map checks, then the requested fine lattice for sign-off.
# Wall-clock timings are recorded by the test/telemetry caller, never here.
# Measured on the Phase-1 Windows host at step=8: ordinary maps 0.45-1.63s,
# all gate combinations up to 9.71s, generated deathmatch maps 4.27-5.01s
# for the six default radii. The 7712x4336 case is not yet measured.
# Large disconnected components use the specified PI*r^2 lattice threshold.
# Small circular-obstacle corner enclosures additionally require an exact
# geometric separation proof; a coarse lattice can miss them entirely.

const NEIGHBOURS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


static func check(data: Dictionary, radii: Array = [14, 16, 18, 20, 22, 24], step: float = 8.0) -> Array[String]:
	var problems: Array[String] = []
	if not is_finite(step) or step <= 0.0:
		problems.append("%s invalid lattice step %s" % [str(data.get("id", "map")), str(step)])
		return problems
	var groups: Array[String] = []
	for obstacle: Dictionary in data.get("obstacles", []):
		if obstacle.has("gate"):
			var group: String = str((obstacle.gate as Dictionary).get("group", "A"))
			if not groups.has(group):
				groups.append(group)
	groups.sort()
	# Enumerate all group states, not only all-open/all-closed/single-open.
	for state in (1 << groups.size()):
		var copy: Dictionary = data.duplicate(true)
		var obstacles: Array = []
		for obstacle: Dictionary in data.get("obstacles", []):
			if obstacle.has("gate"):
				var group: String = str((obstacle.gate as Dictionary).get("group", "A"))
				if (state & (1 << groups.find(group))) != 0:
					continue
			obstacles.append(obstacle.duplicate(true))
		copy["obstacles"] = obstacles
		var arena: Arena = Arena.from_data(copy)
		for radius_value in radii:
			var radius: float = float(radius_value)
			if not is_finite(radius) or radius < 0.0:
				problems.append("%s invalid body radius %s" % [arena.id, str(radius)])
				continue
			problems.append_array(_check_state(arena, radius, step, state, groups))
	return problems


static func _check_state(arena: Arena, radius: float, step: float, state: int, groups: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var origin: Vector2 = Vector2(ceilf((arena.min_x + radius) / step) * step, ceilf((arena.min_y + radius) / step) * step)
	var cols: int = maxi(0, int(floor((arena.max_x - radius - origin.x) / step)) + 1)
	var rows: int = maxi(0, int(floor((arena.max_y - radius - origin.y) / step)) + 1)
	var count: int = cols * rows
	var label: String = "%s radius=%.1f gate_state=%d/%s" % [arena.id, radius, state, str(groups)]
	if count == 0:
		problems.append(label + " no lattice fits inside arena bounds")
		return problems
	var walkable: PackedByteArray = PackedByteArray()
	walkable.resize(count)
	for y in rows:
		for x in cols:
			if arena.is_walkable(origin + Vector2(x, y) * step, radius):
				walkable[y * cols + x] = 1
	var components: PackedInt32Array = PackedInt32Array()
	components.resize(count)
	components.fill(-1)
	var sizes: PackedInt32Array = PackedInt32Array()
	var samples: PackedVector2Array = PackedVector2Array()
	var queue: PackedInt32Array = PackedInt32Array()
	queue.resize(count)
	for start in count:
		if walkable[start] == 0 or components[start] >= 0:
			continue
		var component: int = sizes.size()
		var first_y: int = floori(float(start) / float(cols))
		var first_x: int = start % cols
		samples.append(origin + Vector2(first_x, first_y) * step)
		var head: int = 0
		var tail: int = 1
		queue[0] = start
		components[start] = component
		while head < tail:
			var index: int = queue[head]
			head += 1
			var y: int = floori(float(index) / float(cols))
			var x: int = index % cols
			var point: Vector2 = origin + Vector2(x, y) * step
			for offset: Vector2i in NEIGHBOURS:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
					continue
				var neighbour: int = ny * cols + nx
				if walkable[neighbour] == 0 or components[neighbour] >= 0:
					continue
				var next: Vector2 = origin + Vector2(nx, ny) * step
				if arena.segment_blocked(point, next, radius, Arena.MASK_UNITS):
					continue
				components[neighbour] = component
				queue[tail] = neighbour
				tail += 1
		sizes.append(tail)
	var anchors: Array[Vector2] = []
	for team in [0, 1]:
		for point: Vector2 in arena.spawns.get(team, []):
			anchors.append(point)
	for point: Vector2 in arena.ffa_spawns:
		anchors.append(point)
	var attached: PackedByteArray = PackedByteArray()
	attached.resize(sizes.size())
	if anchors.is_empty():
		problems.append(label + " no spawn anchors provided")
	for spawn_index in anchors.size():
		var spawn: Vector2 = anchors[spawn_index]
		if not arena.is_walkable(spawn, radius):
			problems.append(label + " unwalkable spawn=%d pos=%s" % [spawn_index, str(spawn)])
			continue
		var cx: int = int(round((spawn.x - origin.x) / step))
		var cy: int = int(round((spawn.y - origin.y) / step))
		var found: bool = false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x: int = cx + dx
				var y: int = cy + dy
				if x < 0 or y < 0 or x >= cols or y >= rows:
					continue
				var index: int = y * cols + x
				if components[index] < 0:
					continue
				var point: Vector2 = origin + Vector2(x, y) * step
				if not arena.segment_blocked(spawn, point, radius, Arena.MASK_UNITS):
					attached[components[index]] = 1
					found = true
		if not found:
			problems.append(label + " spawn=%d pos=%s cannot attach to lattice (step=%.1f)" % [spawn_index, str(spawn), step])
	for component in sizes.size():
		var area: float = float(sizes[component]) * step * step
		if attached[component] == 0 and area >= PI * radius * radius:
			problems.append(label + " disconnected area=%.1f threshold=%.1f sample=%s points=%d step=%.1f" % [area, PI * radius * radius, str(samples[component]), sizes[component], step])
	for pocket: Dictionary in _corner_enclosures(arena, radius):
		problems.append(label + " corner_enclosure obstacle=%s witness=%s gaps=(%.2f,%.2f) diameter=%.2f" % [pocket.obstacle, pocket.witness, pocket.wall_gap_x, pocket.wall_gap_y, radius * 2.0])
	return problems


# Conservative exact enclosure proof for the engine's axis-aligned boundary
# and circular solid obstacle geometry. This supplements, never changes, the
# lattice area threshold. dx<R and dy<R mean the body-expanded solid disk
# crosses both adjacent body-center boundary segments; an outside-disk point
# in the corner rectangle is separated by that arc from the main arena.
# A 0.1px inward witness and strict 0.08px margins avoid is_walkable's contact
# tolerance being mistaken for nonempty free space. Other obstacles can only
# shrink the sealed region. Any spawn inside the geometric region suppresses
# reporting conservatively, even if additional walls might separate it further.
# This is sufficient, not a complete detector of every small enclosure.
static func _corner_enclosures(arena: Arena, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var anchors: Array[Vector2] = []
	for team in [0, 1]:
		for point: Vector2 in arena.spawns.get(team, []):
			anchors.append(point)
	for point: Vector2 in arena.ffa_spawns:
		anchors.append(point)
	for i in arena.obs_count:
		if arena.obs_circle[i] != 1 or (arena.obs_mask[i] & Arena.MASK_UNITS) == 0:
			continue
		var center: Vector2 = Vector2(arena.obs_x[i], arena.obs_y[i])
		var expanded: float = arena.obs_r[i] + radius
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner: Vector2 = Vector2(arena.min_x + radius if sx < 0.0 else arena.max_x - radius,
					arena.min_y + radius if sy < 0.0 else arena.max_y - radius)
				var dx: float = sx * (corner.x - center.x)
				var dy: float = sy * (corner.y - center.y)
				if dx <= 0.08 or dy <= 0.08 or dx >= expanded - 0.08 or dy >= expanded - 0.08:
					continue
				var witness: Vector2 = corner - Vector2(sx, sy) * 0.1
				if witness.distance_to(center) <= expanded + 0.08 or not arena.is_walkable(witness, radius):
					continue
				var anchored: bool = false
				for spawn: Vector2 in anchors:
					if sx * (spawn.x - center.x) >= 0.0 and sy * (spawn.y - center.y) >= 0.0 and arena.is_walkable(spawn, radius):
						anchored = true
						break
				if not anchored:
					found.append({"obstacle": arena.obs_ids[i], "radius": radius, "witness": str(witness),
						"dx": dx, "dy": dy, "expanded_radius": expanded,
						"wall_gap_x": dx + radius - arena.obs_r[i], "wall_gap_y": dy + radius - arena.obs_r[i]})
	return found
