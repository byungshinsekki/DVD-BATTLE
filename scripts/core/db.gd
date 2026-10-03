class_name DB
extends RefCounted


const ROLE_LABELS: = {"FRONTLINE": "전방", "DAMAGE": "공격", "CONTROL": "제어", "SUPPORT": "지원"}
const ROLE_ICONS: = {"FRONTLINE": "盾", "DAMAGE": "刃", "CONTROL": "⌁", "SUPPORT": "✦"}
const TAG_LABELS: = {
	"MELEE": "근접", "RANGED": "원거리", "BURST": "폭발", "SUSTAINED_DAMAGE": "지속 공격", 
	"ENGAGE": "진입", "DISENGAGE": "후퇴", "PEEL": "보호", "AREA_DAMAGE": "광역", 
	"SINGLE_TARGET": "단일 대상", "HEALING": "회복", "SHIELDING": "보호막", "MOBILITY": "기동",
	"SUMMONER": "소환", "DAMAGE_OVER_TIME": "지속 피해", "CONTROL": "군중 제어", "EXECUTE": "처형", "SUPPORT": "지원", "INFORMATION": "정보전", "NO_BASIC": "평타 없음"
}
const STATUS_LABELS: = {
	"slow": "둔화", "root": "속박", "stun": "기절", "silence": "침묵", "airborne": "에어본",
	"suppression": "제압", "charm": "유혹", "sleep": "수면", "control": "조종", "disarm": "무장 해제", 
	"invulnerable": "무적", "untargetable": "대상 지정 불가", "invisible": "투명", "grounded": "이동기 봉쇄", 
	"damageAmp": "받는 피해 증가", "healReduction": "치유 감소", "plague": "역병", "confusion": "혼란", 
	"infection": "감염", "hooked": "인양", "bladeTrace": "검기 추적", "bladeMark": "검흔", "frenzy": "광란", 
	"reflect": "투사체 반사", "unstoppable": "저지 불가", "sniperVulnerable": "취약 낙인", "pain": "고통", 
	"nexus_seal": "스킬 봉인", "dot": "지속 피해", "imprisoned": "감금", "taunt": "도발",
	"fear": "공포", "projectile_guard": "투사체 방어", "contemplation": "관조", "distrust": "불신", "spawn_protection": "재출전 보호",
	"roar": "포효", "overdrive": "과열 폭주", "frontGuard": "전방 방패", "bg_downed": "다운"
}
const SCHOOL_LABELS: = {"physical": "물리", "magic": "마법", "true": "고정"}
const TEAM_NAMES: = ["청 팀", "홍 팀"]
const TEAM_COLORS: = [Color("#56a7ff"), Color("#ff6d79")]
const TEAM_COLORS_HDR: = [Color(0.42, 0.78, 1.55), Color(1.6, 0.48, 0.58)]

static var characters: Array = []
static var by_id: Dictionary = {}
static var arenas: Array = []
static var arena_by_id: Dictionary = {}
# Deathmatch maps are generated per seed; a few recent ones are cached.
static var dm_cache: Dictionary = {}
static var dm_cache_order: Array = []
static var dm_previews: Dictionary = {}
# Battleground maps (about 30x the standard area) are generated per seed; only
# the 2 most recently used stay cached (a battle adds ~35 MB of grids to each).
static var br_cache: Dictionary = {}
static var br_cache_order: Array = []

static var font_regular: Font
static var font_bold: Font
static var font_black: Font
static var font_glyph: Font


static func _load() -> void :
	if not characters.is_empty():
		return
	for d in CharData.LIST:
		var c: = Defs.char_from(d)
		characters.append(c)
		by_id[c.id] = c
	# DB arenas are shared by every battle, card and codex page: mark them so a
	# battle on a gated map plays on a private copy (BattleSim.arena setter).
	for d in ArenaData.LIST:
		var a: = Arena.from_data(d)
		a.shared = true
		arenas.append(a)
		arena_by_id[a.id] = a
	for d in ControlArenaData.all():
		var a: = Arena.from_data(d)
		a.shared = true
		arenas.append(a)
		arena_by_id[a.id] = a



static func ensure_loaded() -> void :
	_load()


static func char_def(id: String) -> Defs.CharDef:
	_load()
	return by_id.get(id)


static func arena(id: String) -> Arena:
	_load()
	return arena_by_id.get(id, arena_by_id.get("classic"))


static func deathmatch_arena(id: String, seed_value: int) -> Arena:
	var preset: String = id if DeathmatchMapData.is_deathmatch_id(id) else DeathmatchMapData.ORDER[0]
	var key: String = "%s:%d" % [preset, seed_value]
	if dm_cache.has(key):
		return dm_cache[key]
	var a: Arena = Arena.from_data(DeathmatchMapData.build(preset, seed_value))
	a.shared = true
	dm_cache[key] = a
	dm_cache_order.append(key)
	while dm_cache_order.size() > 4:
		var old_key: String = dm_cache_order.pop_front()
		var old: Arena = dm_cache.get(old_key)
		dm_cache.erase(old_key)
		if old:
			Navigator.forget(old)
	return a


# One stable sample layout per preset for cards and the codex.
static func deathmatch_preview(id: String) -> Arena:
	if not dm_previews.has(id):
		var preview: Arena = Arena.from_data(DeathmatchMapData.build(id, 20261001))
		preview.shared = true
		dm_previews[id] = preview
	return dm_previews[id]


static func deathmatch_presets() -> Array:
	var out: Array = []
	for id in DeathmatchMapData.ORDER:
		out.append(deathmatch_preview(id))
	return out


static func is_battleground_id(id: String) -> bool:
	return BattlegroundMapData.is_battleground_id(id)


# Battleground preset entries for setup screens and the codex (no geometry).
static func battleground_catalogue() -> Array:
	return BattlegroundMapData.catalogue()


# Shared arena of a battleground preset and seed (an unknown id falls back to
# the first preset). Least recently used maps beyond 2 are dropped together
# with their navigation grids.
static func battleground_arena(id: String, seed_value: int) -> Arena:
	var preset: String = id if BattlegroundMapData.is_battleground_id(id) else str(BattlegroundMapData.ORDER[0])
	var key: String = "%s:%d" % [preset, seed_value]
	if br_cache.has(key):
		br_cache_order.erase(key)
		br_cache_order.append(key)
		return br_cache[key]
	var a: Arena = Arena.from_data(BattlegroundMapData.build(preset, seed_value))
	a.shared = true
	br_cache[key] = a
	br_cache_order.append(key)
	while br_cache_order.size() > 2:
		var old_key: String = br_cache_order.pop_front()
		var old: Arena = br_cache.get(old_key)
		br_cache.erase(old_key)
		if old:
			Navigator.forget(old)
	return a


static func arenas_for(ruleset: String) -> Array:
	_load()
	if ruleset == "deathmatch":
		return deathmatch_presets()
	var result: Array = []
	for a in arenas:
		if a.ruleset == ruleset:
			result.append(a)
	return result


static func ids() -> Array:
	_load()
	var out: Array = []
	for c in characters:
		out.append(c.id)
	return out


static func _font_file(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	return null


static func load_fonts() -> void :
	if font_regular != null:
		return
	var sys: = SystemFont.new()
	sys.font_names = PackedStringArray(["Malgun Gothic", "Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR", "NanumGothic", "Microsoft YaHei", "PingFang SC", "sans-serif"])
	var sys_bold: = SystemFont.new()
	sys_bold.font_names = sys.font_names
	sys_bold.font_weight = 700
	font_regular = _font_file("res://assets/fonts/ui_regular.otf")
	font_bold = _font_file("res://assets/fonts/ui_bold.otf")
	font_black = _font_file("res://assets/fonts/ui_black.otf")
	font_glyph = _font_file("res://assets/fonts/glyph_serif.otf")
	if font_regular == null: font_regular = sys
	if font_bold == null: font_bold = sys_bold
	if font_black == null: font_black = font_bold
	if font_glyph == null: font_glyph = font_black

	var symbols: = _font_file("res://assets/fonts/symbols.ttf")
	var chain: Array[Font] = []
	if symbols:
		chain.append(symbols)
	chain.append(sys)
	for f in [font_regular, font_bold, font_black]:
		if f is FontFile:
			(f as FontFile).fallbacks = chain
	if font_glyph is FontFile:
		var gchain: Array[Font] = chain.duplicate()
		gchain.insert(0, font_black)
		(font_glyph as FontFile).fallbacks = gchain


## Battleground team name (team is 0-based): "3팀" for duo/trio squads, "P7" for solo, where a
## team is one hero. Two-team modes keep TEAM_NAMES.
static func team_name(team: int, squad: int) -> String:
	return ("P%d" if squad <= 1 else "%d팀") % (team + 1)


static func role_label(r: String) -> String:
	return ROLE_LABELS.get(r, r)


static func status_label(s: String) -> String:
	return STATUS_LABELS.get(s, s)


static func tag_label(t: String) -> String:
	return TAG_LABELS.get(t, t)
