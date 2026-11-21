class_name PixelTelegraph
extends Node2D
## Reusable pixel-art attack warning.
##
## Usage:
##   var tel := PixelTelegraph.new()
##   world.add_child(tel)
##   tel.hit.connect(func(): if tel.contains_point(player.global_position): player.take_hit(spec.damage))
##   tel.start(spec, caster_node, player_node)
##
## Signals: warning_started -> locked -> hit -> finished.
## The shape is a set of integer world pixels. Drawing and contains_point() use
## the SAME set, so the warning always equals the hitbox.
## Everything is computed in GLOBAL (world) pixel coordinates; put the node
## anywhere in the world layer (no need to move it).

signal warning_started
signal locked
signal hit
signal finished

const BAYER: PackedInt32Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
enum { C_EDGE, C_MAIN, C_HI, C_FLASH, C_WHITE }
enum { K_INTERIOR, K_BORDER, K_INNER_BORDER }
## Default palettes for Category.MIXED / SUPPORT (color_role AUTO). Blue (CONTROL) is reserved and opt-in.
const PALETTE_MIXED: Array = [Color("1a0828"), Color("8e3ac5"), Color("c084e8"), Color("e8d2f6"), Color.WHITE]
const PALETTE_SUPPORT: Array = [Color("082418"), Color("2a9d6e"), Color("7dceb0"), Color("d2f0e4"), Color.WHITE]

var spec: PixelTelegraphSpec
## Optional nodes. If target is set, tracking reads target.global_position + target_offset.
var caster: Node2D
var target: Node2D
var caster_offset := Vector2.ZERO
var target_offset := Vector2.ZERO
## Current target position (updated from `target` each frame, or set it yourself).
var target_position := Vector2.ZERO
## Free the node after the hit frame has been shown.
var auto_free := true
## If false, time does not advance in _process; call step_to_frame() yourself.
var autoplay := true

var _active := false
var _t := 0.0
var _frame := 0
var _dur_f := 30
var _track_f := 0
var _locked := false
var _hit_fired := false
var _caster_px := Vector2i.ZERO
var _origin := Vector2i.ZERO
var _ang := 0.0
var _fill := PixelTelegraphSpec.FillMode.NONE
var _cols: Array = []
var _cache := {}
var _cur := {}
var _img: Image
var _tex: ImageTexture
var _drawn_key := ""


static func palette(role: PixelTelegraphSpec.ColorRole, custom: PackedColorArray = PackedColorArray()) -> Array:
	if role == PixelTelegraphSpec.ColorRole.CUSTOM and custom.size() >= 5:
		return [custom[0], custom[1], custom[2], custom[3], custom[4]]
	if role == PixelTelegraphSpec.ColorRole.CONTROL:
		return [Color("0a1830"), Color("3a7bd5"), Color("8ab8f0"), Color("d6e8ff"), Color.WHITE]
	return [Color("2b0a08"), Color("c0392b"), Color("e8705f"), Color("f6d2c4"), Color.WHITE]


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# ------------------------------------------------------------------ public API
func start(p_spec: PixelTelegraphSpec, p_caster: Node2D, p_target: Node2D = null) -> void:
	caster = p_caster
	target = p_target
	var cp := caster.global_position + caster_offset if caster else global_position
	var tp := target.global_position + target_offset if target else cp + Vector2.RIGHT
	_begin(p_spec, cp, tp)


func start_at(p_spec: PixelTelegraphSpec, caster_pos: Vector2, target_pos: Vector2) -> void:
	caster = null
	target = null
	_begin(p_spec, caster_pos, target_pos)


## Damage query. Call it in your `hit` handler with the victim's hit point (e.g. feet).
func contains_point(global_pos: Vector2) -> bool:
	return _cur.has("cells") and _cur.cells.has(Vector2i(floori(global_pos.x), floori(global_pos.y)))


func is_active() -> bool:
	return _active

func is_locked() -> bool:
	return _locked

func get_frame() -> int:
	return _frame

func get_progress() -> float:
	return clampf(float(_frame) / float(_dur_f), 0.0, 1.0)

func get_angle() -> float:
	return _ang

func get_caster_pixel() -> Vector2i:
	return _caster_px

func get_origin_pixel() -> Vector2i:
	return _origin

func get_cell_count() -> int:
	return _cur.cells.size() if _cur.has("cells") else 0

func has_cell(p: Vector2i) -> bool:
	return _cur.has("cells") and _cur.cells.has(p)

## World pixels of the current hit shape.
func get_cells() -> Array:
	return _cur.cells.keys() if _cur.has("cells") else []

## World-space bounding rect of the shape (pixels).
func get_pixel_rect() -> Rect2i:
	return _cur.rect if _cur.has("rect") else Rect2i()


## Paint one pixel of the current frame image. Clipped to the hit shape.
func paint_pixel(p: Vector2i, c: Color) -> void:
	if _img != null and _cur.cells.has(p):
		var r: Rect2i = _cur.rect
		_img.set_pixel(p.x - r.position.x, p.y - r.position.y, c)


## Advance to an absolute frame (0 = warning start). Used by _process and by tests.
func step_to_frame(f: int) -> void:
	if not _active:
		return
	var hit_was_fired := _hit_fired
	_frame = mini(f, _dur_f)
	if target != null and is_instance_valid(target):
		target_position = target.global_position + target_offset
	if not _locked:
		if f < _track_f:
			var a := _aim(target_position)
			if a != _ang:
				_ang = a
				_build()
		else:
			_locked = true
			locked.emit()
	queue_redraw()
	if f >= _dur_f and not _hit_fired:
		_hit_fired = true
		hit.emit()
	elif hit_was_fired and f > _dur_f:
		_active = false
		finished.emit()
		if auto_free:
			queue_free()


## Renders frame f of the warning into an Image covering get_pixel_rect().
## _draw() shows exactly this image; tests compare it with contains_point().
func render_frame_image(f: int) -> Image:
	var r: Rect2i = _cur.rect
	if _img == null or _img.get_size() != r.size:
		_img = Image.create(maxi(r.size.x, 1), maxi(r.size.y, 1), false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	if f < 0 or f > _dur_f:
		return _img
	if f == _dur_f:
		_paint_hit()
		return _img
	var prog := float(f) / float(_dur_f)
	match spec.style:
		PixelTelegraphSpec.Style.AIM_LINE:
			_paint_aim(prog, f)
		PixelTelegraphSpec.Style.QUICK_FLASH:
			_paint_quick(prog, f)
		_:
			_paint_standard(prog, f)
			if spec.style == PixelTelegraphSpec.Style.THEMED and spec.overlay != null:
				spec.overlay.paint(self, prog, f)
	return _img


# ------------------------------------------------------------------ internals
func _begin(p_spec: PixelTelegraphSpec, cp: Vector2, tp: Vector2) -> void:
	assert(p_spec != null, "PixelTelegraph needs a PixelTelegraphSpec")
	spec = p_spec
	if spec.style == PixelTelegraphSpec.Style.AIM_LINE and spec.shape != PixelTelegraphSpec.Shape.RAY and spec.shape != PixelTelegraphSpec.Shape.RECT:
		push_warning("PixelTelegraph: AIM_LINE style needs RAY or RECT shape; drawing as STANDARD.")
	_cols = spec.resolved_palette()
	_dur_f = spec.warning_frames()
	_track_f = spec.track_frames()
	_caster_px = Vector2i(floori(cp.x), floori(cp.y))
	target_position = tp
	if spec.anchor == PixelTelegraphSpec.Anchor.TARGET:
		_origin = Vector2i(roundi(tp.x), roundi(tp.y))
	else:
		_origin = _caster_px
	_fill = spec.resolved_fill_mode()
	_ang = _aim(tp)
	_locked = _track_f <= 0
	_hit_fired = false
	_cache.clear()
	_build()
	_t = 0.0
	_frame = 0
	_drawn_key = ""
	_active = true
	queue_redraw()
	warning_started.emit()
	if _locked:
		locked.emit()


func _process(delta: float) -> void:
	if not _active or not autoplay:
		return
	_t += delta
	step_to_frame(roundi(_t * spec.fps))


func _draw() -> void:
	if spec == null or not _cur.has("rect"):
		return
	if not _active and not _hit_fired:
		return
	var key := "%d|%d|%s" % [_frame, roundi(rad_to_deg(_ang)), _locked]
	if key != _drawn_key:
		_drawn_key = key
		var img := render_frame_image(_frame)
		if _tex == null or Vector2i(_tex.get_size()) != img.get_size():
			_tex = ImageTexture.create_from_image(img)
		else:
			_tex.update(img)
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	draw_texture(_tex, Vector2(_cur.rect.position))


func _aim(tp: Vector2) -> float:
	if spec.use_fixed_direction:
		return deg_to_rad(spec.fixed_direction_deg)
	var s := spec.shape
	if spec.anchor == PixelTelegraphSpec.Anchor.TARGET and (s == PixelTelegraphSpec.Shape.CIRCLE or s == PixelTelegraphSpec.Shape.RING or s == PixelTelegraphSpec.Shape.RECT or s == PixelTelegraphSpec.Shape.CUSTOM):
		return 0.0
	return atan2(tp.y - _caster_px.y, tp.x - _caster_px.x)


func _build() -> void:
	# Facing is quantised to whole degrees: fewer rebuilds, no pixel shimmer.
	var key := roundi(rad_to_deg(_ang))
	if not _cache.has(key):
		_cache[key] = _prep(compute_shape(spec, _origin, deg_to_rad(key)))
	_cur = _cache[key]


## Pure geometry: the set of world pixels covered by `p_spec` at `origin` facing `ang`.
## A pixel (x, y) is tested at its centre (x + 0.5, y + 0.5).
## Returns { cells: Dictionary[Vector2i -> true], center: Vector2, geo: Dictionary }.
static func compute_shape(p_spec: PixelTelegraphSpec, origin: Vector2i, ang: float) -> Dictionary:
	var cells := {}
	var ca := cos(ang)
	var sa := sin(ang)
	var ox := origin.x
	var oy := origin.y
	var geo := {}
	var center := Vector2.ZERO
	var s := p_spec.shape
	if s == PixelTelegraphSpec.Shape.FAN or s == PixelTelegraphSpec.Shape.CIRCLE or s == PixelTelegraphSpec.Shape.RING:
		var r := float(p_spec.radius_px)
		var ri := float(p_spec.inner_radius_px) if s == PixelTelegraphSpec.Shape.RING else 0.0
		var bx := ox + 0.5
		var by := oy + 0.5
		var half := deg_to_rad(p_spec.angle_deg) / 2.0
		for y in range(int(oy - r - 2), int(oy + r + 3)):
			for x in range(int(ox - r - 2), int(ox + r + 3)):
				var dx := x + 0.5 - bx
				var dy := y + 0.5 - by
				var d := sqrt(dx * dx + dy * dy)
				if d > r + 0.01 or (s == PixelTelegraphSpec.Shape.RING and d <= ri):
					continue
				if s == PixelTelegraphSpec.Shape.FAN and d >= 1.5 and absf(_wrap(atan2(dy, dx) - ang)) > half + 1e-9:
					continue
				cells[Vector2i(x, y)] = true
		if s == PixelTelegraphSpec.Shape.FAN and cells.size() > 0:
			var acc := Vector2.ZERO
			for c in cells:
				acc += Vector2(c) + Vector2(0.5, 0.5)
			center = acc / cells.size()
		else:
			center = Vector2(bx, by)
		geo = {"kind": s, "base": Vector2(bx, by), "r": r, "ri": ri}
	elif s == PixelTelegraphSpec.Shape.CUSTOM:
		return _compute_custom(p_spec, origin, ang)
	else:
		var L := p_spec.length_px
		var Wd := p_spec.width_px
		var centered := p_spec.anchor == PixelTelegraphSpec.Anchor.TARGET
		var bx := ox + 0.5
		var by := oy + 0.5
		var nx := -sa
		var ny := ca
		if Wd % 2 == 0:
			bx -= nx * 0.5
			by -= ny * 0.5
		if centered and L % 2 == 0:
			bx -= ca * 0.5
			by -= sa * 0.5
		var u0 := -L / 2.0 if centered else 0.0
		var u1 := L / 2.0 if centered else float(L)
		var ext := L + Wd + 2
		for y in range(oy - ext, oy + ext + 1):
			for x in range(ox - ext, ox + ext + 1):
				var dx := x + 0.5 - bx
				var dy := y + 0.5 - by
				var u := dx * ca + dy * sa
				var v := dx * nx + dy * ny
				var inside_u: bool
				if not centered:
					inside_u = u0 - 1e-9 <= u and u < u1
				else:
					inside_u = absf(u) < L / 2.0 - 1e-9 or (absf(u) <= L / 2.0 and L % 2 == 1)
				var inside_v: bool
				if Wd % 2 == 0:
					inside_v = absf(v) < Wd / 2.0 - 1e-9
				else:
					inside_v = absf(v) <= Wd / 2.0
				if inside_u and inside_v:
					cells[Vector2i(x, y)] = true
		var um := (u0 + u1) / 2.0
		center = Vector2(bx + ca * um, by + sa * um)
		geo = {"kind": s, "base": Vector2(bx, by), "u0": u0, "u1": u1, "L": L, "W": Wd, "ca": ca, "sa": sa, "nx": nx, "ny": ny}
	return {"cells": cells, "center": center, "geo": geo}


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


static func _cardinal_cs(ang: float) -> Vector2:
	var d := fposmod(rad_to_deg(ang), 360.0)
	if d < 1e-6 or d > 360.0 - 1e-6:
		return Vector2(1, 0)
	if absf(d - 90.0) < 1e-6:
		return Vector2(0, 1)
	if absf(d - 180.0) < 1e-6:
		return Vector2(-1, 0)
	if absf(d - 270.0) < 1e-6:
		return Vector2(0, -1)
	return Vector2(cos(ang), sin(ang))


static func _on_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float, eps: float = 1e-6) -> bool:
	var cross := (px - ax) * (by - ay) - (py - ay) * (bx - ax)
	if absf(cross) > 1e-6:
		return false
	var dot := (px - ax) * (bx - ax) + (py - ay) * (by - ay)
	if dot < -eps:
		return false
	var length2 := (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
	return dot - length2 <= eps


static func point_in_polygon(px: float, py: float, verts: PackedVector2Array) -> bool:
	var n := verts.size()
	if n < 3:
		return false
	var j := n - 1
	var inside := false
	for i in n:
		var xi := verts[i].x
		var yi := verts[i].y
		var xj := verts[j].x
		var yj := verts[j].y
		if _on_segment(px, py, xi, yi, xj, yj):
			return true
		if (yi > py) != (yj > py):
			var xint := (xj - xi) * (py - yi) / (yj - yi) + xi
			if px < xint:
				inside = not inside
		j = i
	return inside


## Returns { tiles: Array[Vector2i], anchor: Vector2 }.
static func parse_tile_mask(mask: PackedStringArray, tile_size: int, tile_anchor: Vector2) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var marked := Vector2(INF, INF)
	var w := 0
	var h := mask.size()
	for y in h:
		var row := str(mask[y])
		w = maxi(w, row.length())
		for x in row.length():
			var ch := row[x]
			if ch == "." or ch == " ":
				continue
			tiles.append(Vector2i(x, y))
			if (ch == "@" or ch == "o" or ch == "O") and marked.x == INF:
				marked = Vector2(x + 0.5, y + 0.5)
	var anchor: Vector2
	if marked.x != INF:
		anchor = marked
	elif tile_anchor != Vector2(-1, -1):
		anchor = tile_anchor
	else:
		anchor = Vector2(w / 2.0, h / 2.0)
	return {"tiles": tiles, "anchor": anchor, "tile_size": tile_size}


static func _spec_from_union_part(part: Dictionary) -> PixelTelegraphSpec:
	return PixelTelegraphSpec.from_dict(part, {})


static func _compute_custom(p_spec: PixelTelegraphSpec, origin: Vector2i, ang: float) -> Dictionary:
	var cs := _cardinal_cs(ang)
	var ca := cs.x
	var sa := cs.y
	var ox := origin.x
	var oy := origin.y
	var cells := {}
	var ts := maxi(1, p_spec.tile_size)
	var parsed := parse_tile_mask(p_spec.tile_mask, ts, p_spec.tile_anchor)
	var tiles: Array = parsed.tiles
	var anchor: Vector2 = parsed.anchor
	var rects: Array = []  # [x0, y0, x1, y1]
	for t in tiles:
		var tx: int = t.x
		var ty: int = t.y
		rects.append([
			tx * ts - anchor.x * ts, ty * ts - anchor.y * ts,
			(tx + 1) * ts - anchor.x * ts, (ty + 1) * ts - anchor.y * ts
		])
	var poly: PackedVector2Array = p_spec.custom_polygon
	var xs: Array[float] = []
	var ys: Array[float] = []
	for r in rects:
		for pt in [Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])]:
			xs.append(ox + pt.x * ca - pt.y * sa)
			ys.append(oy + pt.x * sa + pt.y * ca)
	for v in poly:
		xs.append(ox + v.x * ca - v.y * sa)
		ys.append(oy + v.x * sa + v.y * ca)
	if xs.size() > 0:
		var minx := int(floor(xs.min())) - 2
		var maxx := int(ceil(xs.max())) + 2
		var miny := int(floor(ys.min())) - 2
		var maxy := int(ceil(ys.max())) + 2
		for y in range(miny, maxy + 1):
			for x in range(minx, maxx + 1):
				var dx := (x + 0.5) - (ox + 0.5)
				var dy := (y + 0.5) - (oy + 0.5)
				var lx := dx * ca + dy * sa
				var ly := -dx * sa + dy * ca
				var hit := false
				for r in rects:
					if r[0] <= lx + 1e-9 and lx < r[2] and r[1] <= ly + 1e-9 and ly < r[3]:
						hit = true
						break
				if not hit and poly.size() >= 3 and point_in_polygon(lx, ly, poly):
					hit = true
				if hit:
					cells[Vector2i(x, y)] = true
	for part in p_spec.custom_union:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		var sub := _spec_from_union_part(part)
		var off := Vector2.ZERO
		if part.get("offset") != null:
			var o: Variant = part.offset
			if typeof(o) == TYPE_VECTOR2:
				off = o
			else:
				off = Vector2(float(o[0]), float(o[1]))
		var ox2 := ox + off.x * ca - off.y * sa
		var oy2 := oy + off.x * sa + off.y * ca
		var part_ang := ang + deg_to_rad(float(part.get("direction", 0)))
		var sub_shp := compute_shape(sub, Vector2i(roundi(ox2), roundi(oy2)), part_ang)
		for c in sub_shp.cells:
			cells[c] = true
	var center := Vector2(ox + 0.5, oy + 0.5)
	var geo := {"kind": PixelTelegraphSpec.Shape.CUSTOM, "base": center}
	return {"cells": cells, "center": center, "geo": geo}


static func _border_of(cells: Dictionary) -> Dictionary:
	var out := {}
	for c in cells:
		if not cells.has(c + Vector2i(1, 0)) or not cells.has(c + Vector2i(-1, 0)) \
				or not cells.has(c + Vector2i(0, 1)) or not cells.has(c + Vector2i(0, -1)):
			out[c] = true
	return out


func _prep(shp: Dictionary) -> Dictionary:
	var cells: Dictionary = shp.cells
	var border := _border_of(cells)
	var rest := {}
	for c in cells:
		if not border.has(c):
			rest[c] = true
	var inner := _border_of(rest)
	var n := cells.size()
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var kind := PackedByteArray()
	var metric := PackedFloat32Array()
	xs.resize(n); ys.resize(n); kind.resize(n); metric.resize(n)
	var geo: Dictionary = shp.geo
	var center: Vector2 = shp.center
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lo := INF
	var hi := -INF
	var mn := Vector2i(1 << 30, 1 << 30)
	var mx := Vector2i(-(1 << 30), -(1 << 30))
	var i := 0
	for c in cells:
		xs[i] = c.x
		ys[i] = c.y
		kind[i] = K_BORDER if border.has(c) else (K_INNER_BORDER if inner.has(c) else K_INTERIOR)
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
		if _fill != PixelTelegraphSpec.FillMode.NONE:
			var p := Vector2(c) + Vector2(0.5, 0.5)
			var v := 0.0
			if _fill == PixelTelegraphSpec.FillMode.OUTWARD_FROM_CASTER:
				v = p.distance_to(Vector2(_caster_px) + Vector2(0.5, 0.5))
			elif geo.kind == PixelTelegraphSpec.Shape.RECT or geo.kind == PixelTelegraphSpec.Shape.RAY:
				var d := p - center
				v = maxf(absf(d.x * geo.ca + d.y * geo.sa) / (geo.L / 2.0), absf(d.x * geo.nx + d.y * geo.ny) / (geo.W / 2.0))
			elif geo.kind == PixelTelegraphSpec.Shape.RING:
				v = p.distance_to(center) - geo.ri
			else:
				v = p.distance_to(center)
			raw[i] = v
			lo = minf(lo, v)
			hi = maxf(hi, v)
		i += 1
	var front_w := 0.0
	if _fill != PixelTelegraphSpec.FillMode.NONE and n > 0:
		var span := maxf(hi - lo, 1e-6)
		for k in n:
			metric[k] = (raw[k] - lo) / span
		var px_span := span
		if _fill == PixelTelegraphSpec.FillMode.OUTWARD_FROM_SHAPE_CENTER and (geo.kind == PixelTelegraphSpec.Shape.RECT or geo.kind == PixelTelegraphSpec.Shape.RAY):
			px_span = minf(geo.L, geo.W) / 2.0
		front_w = 2.5 / maxf(px_span, 1.0)
	else:
		metric.fill(2.0)
	var rect := Rect2i(mn, mx - mn + Vector2i.ONE) if n > 0 else Rect2i(_origin, Vector2i.ONE)
	return {"cells": cells, "xs": xs, "ys": ys, "kind": kind, "metric": metric,
		"front_w": front_w, "center": center, "geo": geo, "rect": rect}


func _end_flash_on(prog: float) -> bool:
	var frac := spec.end_flash_fraction
	if frac <= 0.0 or prog < 1.0 - frac:
		return false
	var k := int((prog - (1.0 - frac)) / frac * spec.end_flash_count * 2)
	return k % 2 == 0


func _put(i: int, c: Color) -> void:
	var r: Rect2i = _cur.rect
	_img.set_pixel(_cur.xs[i] - r.position.x, _cur.ys[i] - r.position.y, c)


func _paint_outline(flash_on: bool) -> void:
	var kind: PackedByteArray = _cur.kind
	for i in kind.size():
		if kind[i] == K_BORDER:
			_put(i, _cols[C_WHITE] if flash_on else _cols[C_EDGE])
		elif kind[i] == K_INNER_BORDER:
			_put(i, _cols[C_HI] if flash_on else _cols[C_MAIN])


func _paint_standard(prog: float, _f: int) -> void:
	var xs: PackedInt32Array = _cur.xs
	var ys: PackedInt32Array = _cur.ys
	var kind: PackedByteArray = _cur.kind
	var metric: PackedFloat32Array = _cur.metric
	var fw: float = _cur.front_w
	for i in xs.size():
		if kind[i] != K_INTERIOR:
			continue
		var b := BAYER[(ys[i] & 3) * 4 + (xs[i] & 3)]
		var m := metric[i]
		if m <= prog and m > prog - fw and prog < 1.0:
			if b < 12:
				_put(i, _cols[C_HI])      # advancing front: bright, dense
		elif m <= prog:
			if b < 7:
				_put(i, _cols[C_MAIN])    # filled: medium dither
		elif b < 2:
			_put(i, _cols[C_MAIN])        # not yet filled: very sparse dither
	_paint_outline(_end_flash_on(prog))


func _paint_quick(prog: float, f: int) -> void:
	var period := 2 if prog < 0.5 else 1
	var on := (f / period) % 2 == 1
	_paint_outline(on)
	if on:
		var xs: PackedInt32Array = _cur.xs
		var ys: PackedInt32Array = _cur.ys
		var kind: PackedByteArray = _cur.kind
		for i in xs.size():
			if kind[i] == K_INTERIOR and BAYER[(ys[i] & 3) * 4 + (xs[i] & 3)] < 3:
				_put(i, _cols[C_MAIN])


func _paint_aim(prog: float, f: int) -> void:
	var g: Dictionary = _cur.geo
	if not g.has("L"):
		_paint_standard(prog, f)
		return
	var xs: PackedInt32Array = _cur.xs
	var ys: PackedInt32Array = _cur.ys
	var base: Vector2 = g.base
	var ca: float = g.ca
	var sa: float = g.sa
	var nx: float = g.nx
	var ny: float = g.ny
	var lock_flash := _locked and (f - _track_f == 0 or f - _track_f == 1)
	for i in xs.size():
		var dx := xs[i] + 0.5 - base.x
		var dy := ys[i] + 0.5 - base.y
		var u := dx * ca + dy * sa
		var v := dx * nx + dy * ny
		var core := absf(v) <= 0.5
		if not _locked:
			if core and posmod(int(u) - f, 4) < 2:   # 1px dashed line flowing forward
				_put(i, _cols[C_MAIN])
		elif core:
			_put(i, _cols[C_WHITE] if lock_flash else _cols[C_HI])
		else:
			_put(i, _cols[C_HI] if lock_flash else _cols[C_MAIN])
	# a bright dot travels from the caster to the tip over the whole warning
	var L: int = g.L
	var u_dot := prog * (L - 1)
	var dot_cols := [_cols[C_WHITE], _cols[C_WHITE], _cols[C_HI], _cols[C_HI], _cols[C_MAIN]]
	for k in 5:
		var uu := u_dot - k
		if uu < 0.0:
			break
		paint_pixel(Vector2i(floori(base.x + ca * uu), floori(base.y + sa * uu)), dot_cols[k])
	# small cross at the max range (clipped to the hitbox)
	var e := Vector2i(floori(base.x + ca * (L - 1)), floori(base.y + sa * (L - 1)))
	var tip: Color = _cols[C_HI] if _locked else _cols[C_MAIN]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		paint_pixel(e + d, tip)


func _paint_hit() -> void:
	var xs: PackedInt32Array = _cur.xs
	var ys: PackedInt32Array = _cur.ys
	var kind: PackedByteArray = _cur.kind
	for i in xs.size():
		if kind[i] == K_BORDER:
			_put(i, _cols[C_WHITE])
		elif (xs[i] + ys[i]) & 1 == 0:
			_put(i, _cols[C_FLASH])
		else:
			_put(i, _cols[C_HI])


## Integer Bresenham line between two points (floored), inclusive.
static func bresenham(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var x0 := floori(a.x)
	var y0 := floori(a.y)
	var x1 := floori(b.x)
	var y1 := floori(b.y)
	var pts: Array[Vector2i] = []
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		pts.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return pts
