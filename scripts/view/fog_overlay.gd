class_name FogOverlay
extends Node2D



const SCALE: = 0.25
const RAYS: = 88
## Largest SubViewport side (V2 battleground maps): bigger maps paint the mask at a lower scale.
const MAX_SIDE: = 2048

## Mask pixels per world unit for the current arena: SCALE, lowered only when a side would
## exceed MAX_SIDE (every map up to 8192 px keeps exactly ceil(side x 0.25)).
var scale_k: float = SCALE

var view: BattleView
var vp: SubViewport
var painter: Node2D
var sprite: Sprite2D
var polys: Array = []
var circles: Array = []
# Brush / forest circles the perspective team does not stand in: half fogged
# (units inside are hidden from outside observers). Multiplied over the mask.
var brush: PackedInt32Array = PackedInt32Array()
var brush_painter: Node2D
var timer: float = 0.0
var mat: ShaderMaterial


func _init() -> void :
	visible = false
	vp = SubViewport.new()
	vp.size = Vector2i(int(Arena.WIDTH * SCALE), int(Arena.HEIGHT * SCALE))
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	painter = Node2D.new()
	painter.draw.connect(_paint)
	vp.add_child(painter)
	brush_painter = Node2D.new()
	var mul: = CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	brush_painter.material = mul
	brush_painter.draw.connect(_paint_brush)
	vp.add_child(brush_painter)
	add_child(vp)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = vp.get_texture()
	sprite.scale = Vector2(1.0 / SCALE, 1.0 / SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/fog.gdshader")
	sprite.material = mat
	add_child(sprite)


func setup(v: BattleView) -> void :
	view = v
	# A new battle (possibly a new map): drop the previous map's sight shapes and brush indices.
	polys.clear()
	circles.clear()
	brush.clear()
	var longest: float = maxf(view.arena.width, view.arena.height)
	scale_k = SCALE if ceili(longest * SCALE) <= MAX_SIDE else float(MAX_SIDE) / longest
	vp.size = Vector2i(mini(ceili(view.arena.width * scale_k), MAX_SIDE), mini(ceili(view.arena.height * scale_k), MAX_SIDE))
	sprite.scale = Vector2(1.0 / scale_k, 1.0 / scale_k)
	force_update()


func force_update() -> void :
	timer = 0.0
	if view and view.sim and view.perspective >= 0:
		_compute()
	painter.queue_redraw()
	brush_painter.queue_redraw()


func tick(delta: float) -> void :
	timer -= delta
	mat.set_shader_parameter("t", view.anim if view else 0.0)
	if timer <= 0.0:
		timer = 1.0 / 15.0
		_compute()
		painter.queue_redraw()
		brush_painter.queue_redraw()


func _compute() -> void :
	polys.clear()
	circles.clear()
	var sim: = view.sim
	var arena: = sim.arena
	var team: = view.perspective
	brush.clear()
	if sim.brush_on and not arena.forest_x.is_empty():
		var own: Dictionary = {}
		for ob in sim.bodies_alive():
			if sim.eteam(ob) == team:
				var patch: int = arena.forest_at(ob.pos)
				if patch >= 0:
					own[patch] = true
		for k in arena.forest_x.size():
			if not own.has(arena.forest_patch[k]):
				brush.append(k)
	for b in sim.bodies_alive():
		if sim.eteam(b) != team:
			continue
		var r: = sim.sensor_range(b) + sim.radius(b)
		var c: = view.upos(b)

		var blocked: = false
		if arena.indexed:
			# Large generated maps (V2 battleground): only the obstacles in the uniform grid cells
			# around the sight circle, in the same index order as the full scan.
			for i in arena._candidates(c.x - r, c.y - r, c.x + r, c.y + r):
				if (arena.obs_mask[i] & Arena.MASK_VISION) == 0:
					continue
				if arena.obs_maxx[i] < c.x - r or arena.obs_minx[i] > c.x + r or arena.obs_maxy[i] < c.y - r or arena.obs_miny[i] > c.y + r:
					continue
				blocked = true
				break
		else:
			for i in arena.obs_count:
				if (arena.obs_mask[i] & Arena.MASK_VISION) == 0:
					continue
				if arena.obs_maxx[i] < c.x - r or arena.obs_minx[i] > c.x + r or arena.obs_maxy[i] < c.y - r or arena.obs_miny[i] > c.y + r:
					continue
				blocked = true
				break
		if not blocked:
			circles.append([c, r])
			continue
		var pts: = PackedVector2Array()
		for k in RAYS:
			var dir: = Vector2.from_angle(TAU * k / RAYS)
			var end: = c + dir * r
			var hit: = arena.segment_hit(c, end, 0.0, Arena.MASK_VISION)
			var d: = r
			if not hit.is_empty():
				d = float(hit.t) * r + 6.0
			pts.append(c + dir * d)
		polys.append([c, pts])


func _paint() -> void :
	painter.draw_rect(Rect2(Vector2.ZERO, Vector2(vp.size)), Color.BLACK)
	var k_s: float = scale_k
	for cr in circles:
		painter.draw_circle((cr[0] as Vector2) * k_s, float(cr[1]) * k_s, Color.WHITE)
	var white: = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	for row in polys:
		var c: Vector2 = (row[0] as Vector2) * k_s
		var pts: PackedVector2Array = row[1]
		var n: = pts.size()

		for k in n:
			var a: = pts[k] * k_s
			var b: = pts[(k + 1) % n] * k_s
			painter.draw_primitive(PackedVector2Array([c, a, b]), white, PackedVector2Array())


func _paint_brush() -> void:
	if view == null or view.sim == null or brush.is_empty():
		return
	var arena: Arena = view.sim.arena
	for k in brush:
		if k >= arena.forest_x.size():
			continue
		brush_painter.draw_circle(Vector2(arena.forest_x[k], arena.forest_y[k]) * scale_k, arena.forest_r[k] * scale_k, Color(0.5, 0.5, 0.5))
