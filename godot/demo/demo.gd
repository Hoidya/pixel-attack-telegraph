extends Node2D
## Demo: top row = the 5 shapes, bottom row = the 5 styles.
## A target dot circles in every cell; it flashes when a hit lands on it.
## Every telegraph loops. Hits are decided ONLY by PixelTelegraph.contains_point().

const CELL := Vector2(128, 150)
const S := preload("res://addons/pixel_telegraph/telegraph_spec.gd")

var _slots: Array = []   # each: {spec, caster: Vector2, center: Vector2, label, tel, wait, flash, hits}
var _time := 0.0
var _total_hits := 0
var _total_warnings := 0


func _ready() -> void:
	var fan := _spec(S.Shape.FAN, S.Style.STANDARD)
	var circle := _spec(S.Shape.CIRCLE, S.Style.COUNTDOWN)
	circle.radius_px = 28
	circle.anchor = S.Anchor.TARGET
	var ring := _spec(S.Shape.RING, S.Style.COUNTDOWN)
	ring.radius_px = 40
	ring.inner_radius_px = 22
	ring.anchor = S.Anchor.TARGET
	var rect := _spec(S.Shape.RECT, S.Style.STANDARD)
	rect.length_px = 96
	rect.width_px = 16
	var ray := _spec(S.Shape.RAY, S.Style.AIM_LINE)
	ray.length_px = 96
	ray.width_px = 3
	ray.track_time = 0.6

	var quick := _spec(S.Shape.FAN, S.Style.QUICK_FLASH)
	quick.angle_deg = 90
	quick.warning_time = 0.4
	var aim := ray.duplicate()
	var countdown := _spec(S.Shape.RECT, S.Style.COUNTDOWN)
	countdown.length_px = 32
	countdown.width_px = 32
	countdown.anchor = S.Anchor.TARGET
	var themed := _spec(S.Shape.FAN, S.Style.THEMED)
	themed.angle_deg = 120
	themed.warning_time = 1.5
	themed.overlay = PixelTelegraphCrackOverlay.new()

	var row1 := [[fan, "fan"], [circle, "circle"], [ring, "ring"], [rect, "rect"], [ray, "ray"]]
	var row2 := [[fan.duplicate(), "standard"], [quick, "quick flash"], [aim, "aim line"], [countdown, "countdown"], [themed, "themed"]]
	for r in 2:
		var row: Array = row1 if r == 0 else row2
		for c in 5:
			var center := Vector2(CELL.x * c + CELL.x / 2.0, CELL.y * r + CELL.y / 2.0 + 14)
			var sp: PixelTelegraphSpec = row[c][0]
			var caster := (center + Vector2(-50, 0)).floor()
			if sp.anchor == S.Anchor.TARGET:
				caster = (center + Vector2(0, -52)).floor()
			_slots.append({"spec": sp, "caster": caster, "center": center, "label": row[c][1],
				"tel": null, "wait": 0.2 * c, "flash": 0.0, "hits": 0})
			var lab := Label.new()
			lab.text = row[c][1]
			lab.position = Vector2(CELL.x * c + 4, CELL.y * r + 2)
			lab.add_theme_font_size_override("font_size", 10)
			add_child(lab)


func _spec(shape: int, style: int) -> PixelTelegraphSpec:
	var s := PixelTelegraphSpec.new()
	s.shape = shape
	s.style = style
	s.radius_px = 48
	s.angle_deg = 60
	s.warning_time = 1.0
	return s


func _target_pos(slot: Dictionary) -> Vector2:
	var k: float = _time * 1.3 + slot.center.x * 0.05
	return (slot.center + Vector2(cos(k) * 26 + 6, sin(k) * 22)).floor()


func _process(delta: float) -> void:
	_time += delta
	for slot in _slots:
		slot.flash = maxf(0.0, slot.flash - delta)
		if slot.tel == null:
			slot.wait -= delta
			if slot.wait <= 0.0:
				_fire(slot)
		elif is_instance_valid(slot.tel):
			slot.tel.target_position = _target_pos(slot)
	queue_redraw()


func _fire(slot: Dictionary) -> void:
	var tel := PixelTelegraph.new()
	add_child(tel)
	slot.tel = tel
	_total_warnings += 1
	tel.hit.connect(func():
		if tel.contains_point(_target_pos(slot) + Vector2(0.5, 0.5)):
			slot.hits += 1
			slot.flash = 0.25
			_total_hits += 1)
	tel.finished.connect(func():
		slot.tel = null
		slot.wait = 0.5)
	tel.start_at(slot.spec, slot.caster, _target_pos(slot))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(640, 330)), Color("2e3a24"))
	for x in range(0, 640, 16):
		draw_line(Vector2(x, 0), Vector2(x, 330), Color("34422a"))
	for y in range(0, 330, 16):
		draw_line(Vector2(0, y), Vector2(640, y), Color("34422a"))
	for slot in _slots:
		var c: Vector2 = slot.caster
		draw_rect(Rect2(c - Vector2(4, 6), Vector2(9, 12)), Color("6b5a4a"))
		draw_rect(Rect2(c - Vector2(4, 6), Vector2(9, 12)), Color("3b2f27"), false)
		var t := _target_pos(slot)
		var col := Color.WHITE if slot.flash > 0.0 else Color("4fa3e0")
		draw_rect(Rect2(t - Vector2(2, 2), Vector2(5, 5)), col)


func get_stats() -> Dictionary:
	return {"warnings": _total_warnings, "hits": _total_hits}
