extends RefCounted

# Synthetic battleground-scale map for the V2 performance tool (B-PERF; copied
# from the zz_work/v2probe/br feasibility probe): tiles DeathmatchMapData
# layouts (3600x2200 each) into nx x ny, offsetting every coordinate. Content
# density = deathmatch density. 2x2 = 7200x4400, about 28x the standard area.

const TW := 3600.0
const TH := 2200.0


static func _off(d: Dictionary, o: Vector2) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	if c.has("x"):
		c["x"] = float(c.x) + o.x
	if c.has("y"):
		c["y"] = float(c.y) + o.y
	if c.has("target"):
		c["target"] = {"x": float(c.target.x) + o.x, "y": float(c.target.y) + o.y}
	return c


static func build(seed_value: int, nx: int = 2, ny: int = 2) -> Dictionary:
	var presets: Array = ["dm_forest_village", "dm_ruined_town", "dm_open_steppe", "dm_forest_village", "dm_ruined_town", "dm_open_steppe", "dm_forest_village", "dm_ruined_town", "dm_open_steppe"]
	var obstacles: Array = []
	var forests: Array = []
	var buildings: Array = []
	var hazards: Array = []
	var spawns: Array = []
	var spots: Array = []
	var k: int = 0
	for ty in ny:
		for tx in nx:
			var o := Vector2(tx * TW, ty * TH)
			var d: Dictionary = DeathmatchMapData.build(str(presets[k % presets.size()]), seed_value + k * 13)
			var pre: String = "t%d_" % k
			for ob in d.obstacles:
				var c: Dictionary = _off(ob, o)
				c["id"] = pre + str(c.get("id", ""))
				obstacles.append(c)
			for f in d.forests:
				var c2: Dictionary = _off(f, o)
				c2["patch"] = int(f.get("patch", 0)) + k * 1000
				forests.append(c2)
			for b in d.buildings:
				var c3: Dictionary = _off(b, o)
				c3["id"] = pre + str(c3.get("id", ""))
				buildings.append(c3)
			for h in d.hazards:
				var c4: Dictionary = _off(h, o)
				c4["id"] = pre + str(c4.get("id", ""))
				hazards.append(c4)
			for p in d.ffa_spawns:
				spawns.append({"x": float(p.x) + o.x, "y": float(p.y) + o.y})
			for s in d.item_spots:
				var c5: Dictionary = _off(s, o)
				spots.append(c5)
			k += 1
	var w: float = TW * nx
	var h2: float = TH * ny
	var data: Dictionary = {"id": "br_synth_%d" % seed_value, "preset": "dm_forest_village", "name": "BR synthetic",
		"subtitle": "", "description": "", "ruleset": "deathmatch", "accent": "#7fd08a", "layout_id": "br_synth",
		"landmarks": [], "difficulty": "", "icon": "", "tags": [], "width": w, "height": h2,
		"bounds": {"minX": 40.0, "maxX": w - 40.0, "minY": 40.0, "maxY": h2 - 40.0},
		"floor": {"base": "#0c1a12", "blue": "#16435c", "red": "#542f4b", "grid": "#7fd08a"},
		"obstacles": obstacles, "forests": forests, "buildings": buildings, "hazards": hazards,
		"control_points": [], "heal_zones": [], "tacticalNotes": [], "ffa_spawns": spawns, "item_spots": spots}
	data["spawns"] = {"blue": [spawns[0]], "red": [spawns[1]]}
	return data
