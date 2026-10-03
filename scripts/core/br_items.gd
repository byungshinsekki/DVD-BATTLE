class_name BrItems
extends RefCounted

# Battleground field items (DESIGN_V2 §3.4): placed once at match start, never
# respawned. Ring counts 12 / 20 / 24 / 24 (centre to edge, scaled for other
# totals) on the map's item spots, at least 150 px from every other item. Each
# ring draws its rarities from its weights with a seeded stratified draw: the
# count of every rarity is within one of weight x ring count, so the trend
# "richer toward the centre" (public knowledge) holds on every seed. The item
# of a rarity is a seeded pick from ItemDefs.by_rarity. Deterministic: a pure
# function of (data, seed, count).

const RING_COUNTS := [12, 20, 24, 24]
# [common, rare, epic, mythic, legendary] per ring.
const RING_WEIGHTS := [
	[8.0, 20.0, 30.0, 24.0, 18.0],
	[25.0, 30.0, 25.0, 13.0, 7.0],
	[44.0, 30.0, 17.0, 7.0, 2.0],
	[60.0, 28.0, 9.0, 3.0, 0.0],
]
const MIN_GAP := 150.0


# Items per ring for count items: RING_COUNTS scaled, largest remainder.
static func ring_counts(count: int) -> Array:
	var total: int = 0
	for n in RING_COUNTS:
		total += int(n)
	var out: Array = []
	var rems: Array = []
	var used: int = 0
	for k in RING_COUNTS.size():
		var exact: float = float(RING_COUNTS[k]) * float(count) / float(total)
		out.append(int(floor(exact)))
		rems.append([exact - floor(exact), k])
		used += int(floor(exact))
	rems.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for i in count - used:
		var k2: int = int(rems[i % rems.size()][1])
		out[k2] = int(out[k2]) + 1
	return out


# Rarity of each of n items of a ring: systematic sampling of the ring's
# weights at offsets (u0 + i) / n, u0 in [0, 1).
static func rarities(ring: int, n: int, u0: float) -> Array:
	var w: Array = RING_WEIGHTS[clampi(ring, 0, RING_WEIGHTS.size() - 1)]
	var total: float = 0.0
	for x in w:
		total += float(x)
	var out: Array = []
	for i in n:
		var u: float = (u0 + float(i)) / float(n) * total
		var rarity: int = 0
		var acc: float = 0.0
		for r in w.size():
			acc += float(w[r])
			if u < acc:
				rarity = r
				break
		out.append(rarity)
	return out


# Expected rarity mix of a ring (public: "the centre is richer").
static func ring_weights(ring: int) -> Array:
	return (RING_WEIGHTS[clampi(ring, 0, RING_WEIGHTS.size() - 1)] as Array).duplicate()


static func place(data: Dictionary, seed_value: int, count: int = 80) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "items"])
	var br: Dictionary = data.get("br", {})
	var center: Vector2 = Vector2(float(data.get("width", 0.0)) * 0.5, float(data.get("height", 0.0)) * 0.5)
	if br.has("center"):
		center = Vector2(float(br.center.x), float(br.center.y))
	var half_diag: float = float(br.get("half_diag", center.length()))
	var by_ring: Array = [[], [], [], []]
	for spot: Dictionary in data.get("item_spots", []):
		if bool(spot.get("unreachable", false)):
			continue
		var p: Vector2 = Vector2(float(spot.x), float(spot.y))
		var ring: int = int(spot.ring) if spot.has("ring") else BattlegroundMapData.ring_of(p, center, half_diag)
		(by_ring[clampi(ring, 0, 3)] as Array).append(p)
	var counts: Array = ring_counts(count)
	var placed: Array[Vector2] = []
	var out: Array = []
	for ring in 4:
		var pool: Array = by_ring[ring]
		var order: Array = range(pool.size())
		for i in range(order.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		var chosen: Array[Vector2] = []
		for idx: int in order:
			if chosen.size() >= int(counts[ring]):
				break
			var p2: Vector2 = pool[idx]
			var far: bool = true
			for q in placed:
				if p2.distance_to(q) < MIN_GAP:
					far = false
					break
			if far:
				chosen.append(p2)
				placed.append(p2)
		if chosen.size() < int(counts[ring]):
			push_warning("BrItems: ring %d holds only %d of %d items" % [ring, chosen.size(), int(counts[ring])])
		var rar: Array = rarities(ring, chosen.size(), rng.randf())
		for i in range(rar.size() - 1, 0, -1):
			var j2: int = rng.randi_range(0, i)
			var tmp2 = rar[i]
			rar[i] = rar[j2]
			rar[j2] = tmp2
		for i in chosen.size():
			var rarity: int = int(rar[i])
			var ids: Array = ItemDefs.by_rarity(rarity)
			out.append({"item": str(ids[rng.randi_range(0, ids.size() - 1)]), "pos": chosen[i], "ring": ring, "rarity": rarity})
	return out
