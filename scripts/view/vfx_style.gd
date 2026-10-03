class_name VfxStyle
extends RefCounted


const OVERRIDES: = {
	"world_tree_1": ["樹", "#76ddb0", "treePlant"], 
	"world_tree_2": ["根", "#8fd46a", "rootBind"], 
	"world_tree_3": ["棘", "#b6e36a", "thornField"], 
	"world_tree_4": ["花", "#ffb3d9", "flowerBloom"], 
	"torturer_1": ["鞭", "#e789ba", "whipCone"], 
	"torturer_2": ["默", "#ff9ad0", "gagBind"], 
	"torturer_3": ["獄", "#c05a9a", "prisonRing"], 
	"torturer_4": ["訊", "#d27aa9", "interrogate"], 
	"politician_1": ["報", "#d6b979", "fakeNews"], 
	"politician_2": ["誘", "#e8a06f", "diversion"], 
	"politician_3": ["宣", "#ecd998", "propaganda"], 
	"engineer_1": ["塔", "#79cbed", "turretDeploy"], 
	"engineer_2": ["爆", "#ff9a5b", "detonate"], 
	"engineer_3": ["釘", "#a8e0ff", "driverBolt"], 
	"engineer_4": ["改", "#9ff0c5", "upgradeTool"], 
}


const MELEE: = ["slash", "crescent", "blinkCut", "sashimi", "harpe", "biteDash", "whipCone", "cannonCone", "plagueSpray", "healSpray", "sleepStaff", "underworldCleave"]
const NOVA: = ["quake", "howl", "teamShout", "stonePulse", "wingSpin", "chainExplosion", "rootBind", "thornField", "fakeNews", "propaganda", "windAura", "predatorAura", "scent", "helmet", "angelDrop", "cloak", "cloakReveal", "riftGuard", "trajectoryGate", "steal", "upgradeTool",
	"soulHarvest", "arcShield", "alhambraEdict", "hephaestusShield", "warRoar"]
const BEAM: = ["hitscan", "goldTether", "bloodLink", "hook", "grapple", "mindControl", "rescueFlight", "swapBox", "statFlip", "goldApple", "selfRend", "gagBind", "interrogate", "diversion", "edictBind"]
const HEAVY: = ["explosiveOrb", "boulder", "meteorZone", "coinBurst", "cannonCone", "detonate", "fishThrow", "banana", "curveBall", "chainExplosion", "dimensionBlade", "finisher", "recoilShot", "quake", "genocideStrip"]
const SPAWN: = ["snakeSpawn", "broodSpawn", "parasiteSpawn", "turretDeploy", "treePlant", "flowerBloom", "loveBed", "baitTrap", "portalPair", "bloodPool", "shadeSpawn", "chariotCharge", "autoDaFe"]
# V2: dashes and single/charged shots that are not heavy (no per-hit screen shake).
const DASH: = ["boosterDash"]
const SHOT: = ["missileBarrage", "peliasSpear"]

# Status glyphs over heroes and in status pops. Every glyph exists in the bundled fonts
# (glyph_serif / ui_* subsets or symbols.ttf) and no two statuses share one: bladeTrace keeps 封
# (swordsman S3 and the codex glossary use it) while the skill seal uses 鎖; invisible 匿 (as in
# the codex) vs untargetable ◌; taunt ! vs fear 退; contemplation 空 (觀 is not in the fonts).
const STATUS_ICONS: = {
	"stun": ["✦", "#ffe066"], "root": ["◎", "#8fd46a"], "slow": ["↓", "#7cc4ff"], "silence": ["✕", "#c49bff"],
	"airborne": ["↑", "#e6f2ff"], "suppression": ["■", "#ff7aa8"], "charm": ["♥", "#ff8fbe"], "sleep": ["z", "#98e8e1"],
	"control": ["◈", "#b276e8"], "disarm": ["⊘", "#ffb45e"], "invulnerable": ["◇", "#ffd66b"], "untargetable": ["◌", "#dfe8ff"],
	"invisible": ["匿", "#9fb4d6"], "damageAmp": ["▲", "#ff8a8a"], "healReduction": ["✚", "#9dbd72"], "plague": ["疫", "#84bd72"],
	"confusion": ["?", "#b88be9"], "infection": ["寄", "#c26ed0"], "hooked": ["鉤", "#67c8d8"], "bladeTrace": ["封", "#89ddff"],
	"bladeMark": ["月", "#83c0ff"], "frenzy": ["狂", "#ff706d"], "reflect": ["反", "#ffc19b"], "unstoppable": ["▶", "#ffffff"],
	"sniperVulnerable": ["印", "#edb94f"], "pain": ["痛", "#e789ba"], "nexus_seal": ["鎖", "#f9bee7"], "grounded": ["⊥", "#ffb45e"],
	"fear": ["退", "#ffb45e"], "taunt": ["!", "#ff9a5b"], "projectile_guard": ["帽", "#ffc19b"],
	"imprisoned": ["獄", "#e789ba"], "contemplation": ["空", "#ecd998"], "spawn_protection": ["生", "#6fe0a2"],
	# V2 (same glyphs as the codex STATUS entries, all in the bundled glyph font).
	"roar": ["吼", "#f0a548"], "overdrive": ["燃", "#ff7a3a"], "frontGuard": ["壁", "#d9a24f"],
}
const HARD: = ["stun", "root", "airborne", "suppression", "charm", "sleep", "control", "taunt"]


static func glyph_for(a: Defs.AbilityDef) -> String:
	if OVERRIDES.has(a.id):
		return OVERRIDES[a.id][0]
	return a.vfx_glyph if a.vfx_glyph != "" else str(a.slot)


static func color_for(a: Defs.AbilityDef) -> Color:
	if a == null:
		return Color.WHITE
	if OVERRIDES.has(a.id):
		return Color(OVERRIDES[a.id][1])
	return a.color


static func pattern_for(a: Defs.AbilityDef) -> String:
	if a == null:
		return ""
	if OVERRIDES.has(a.id):
		return OVERRIDES[a.id][2]
	return a.pattern


static func hdr(c: Color, k: float = 1.6) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func status_icon(s: String) -> Array:
	return STATUS_ICONS.get(s, ["•", "#dfe8ff"])


# In-world HUD text is drawn at one of these screen sizes (px) when BattleView.hud_readable is on.
# The bundled fonts are not MSDF, so every distinct size is a separate glyph cache: snapping to a
# short fixed set keeps camera zooms from rasterising a new size every frame.
const HUD_SIZES: = [9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28]
static var _snap: PackedInt32Array = _build_snap()


static func _build_snap() -> PackedInt32Array:
	# Index = round(target px * 2); value = the nearest HUD size (ties go to the larger size).
	var out: = PackedInt32Array()
	out.resize(65)
	for i in 65:
		var t: = i * 0.5
		var best: int = HUD_SIZES[0]
		for s: int in HUD_SIZES:
			if absf(float(s) - t) <= absf(float(best) - t):
				best = s
		out[i] = best
	return out


## Screen px for HUD text of `world_size` seen at `scale` (screen px per world unit): never
## below `min_px`, snapped to HUD_SIZES.
static func hud_px(world_size: float, scale: float, min_px: float) -> int:
	var t: = maxf(world_size * scale, min_px)
	var px: int = _snap[clampi(int(t * 2.0 + 0.5), 0, 64)]
	while float(px) < min_px - 0.01 and px < 28:
		t += 0.5
		px = _snap[clampi(int(t * 2.0 + 0.5), 0, 64)]
	return px
