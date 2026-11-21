@tool
class_name PixelTelegraphCrackOverlay
extends PixelTelegraphOverlay
## Example THEMED layer: ground cracks that grow outward from the caster with the
## warning progress. Always clipped to the hit shape.

@export var crack_seed: int = 0
@export var main_cracks: int = 3
@export var dark: Color = Color("1c1d0e")
@export var lit: Color = Color("6b5a4a")

var _key: String = ""
var _pts: Dictionary = {}   # Vector2i -> distance from caster
var _maxd: float = 1.0


func paint(tel: PixelTelegraph, progress: float, _frame: int) -> void:
	_build(tel)
	var lim := 9.0 + (_maxd - 9.0) * progress
	for q in _pts:
		if _pts[q] <= lim:
			tel.paint_pixel(q, dark)
			var below: Vector2i = q + Vector2i(0, 1)
			if not _pts.has(below):
				tel.paint_pixel(below, lit)


func _build(tel: PixelTelegraph) -> void:
	var o: Vector2i = tel.get_caster_pixel()
	var key := "%s|%d|%d" % [o, roundi(rad_to_deg(tel.get_angle())), tel.get_cell_count()]
	if key == _key:
		return
	_key = key
	_pts.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed
	var spec := tel.spec
	var r := float(spec.radius_px) if spec.shape != PixelTelegraphSpec.Shape.RECT and spec.shape != PixelTelegraphSpec.Shape.RAY else float(spec.length_px)
	var half := deg_to_rad(spec.angle_deg) * 0.5 if spec.shape == PixelTelegraphSpec.Shape.FAN else PI
	var ang := tel.get_angle()
	for i in main_cracks:
		var k := 0.0 if main_cracks == 1 else (float(i) / float(main_cracks - 1) - 0.5)
		var a := ang + k * 2.0 * half * 0.75
		_walk(tel, rng, o, Vector2(o) + Vector2(cos(a), sin(a)) * 9.0, a, r - 9.0, 0)
	_maxd = 1.0
	for q in _pts:
		_maxd = maxf(_maxd, _pts[q])


func _walk(tel: PixelTelegraph, rng: RandomNumberGenerator, o: Vector2i, p: Vector2, a: float, length: float, depth: int) -> void:
	var steps := 0.0
	while steps < length:
		a += rng.randf_range(-0.35, 0.35)
		var n := p + Vector2(cos(a), sin(a)) * 2.0
		for q in PixelTelegraph.bresenham(p, n):
			if tel.has_cell(q) and not _pts.has(q):
				_pts[q] = Vector2(q - o).length()
		p = n
		steps += 2.0
		if depth < 1 and rng.randf() < 0.12:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			_walk(tel, rng, o, p, a + side * rng.randf_range(0.5, 0.9), float(rng.randi_range(5, 10)), depth + 1)
