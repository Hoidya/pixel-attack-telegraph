extends SceneTree
## Headless tests. Run from the godot/ folder:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exit code 0 = all passed.

const S := preload("res://addons/pixel_telegraph/telegraph_spec.gd")

var _fails := 0
var _checks := 0


func _initialize() -> void:
	test_python_fixtures()
	test_draw_equals_hitbox()
	test_signals_and_tracking()
	test_budget()
	test_cadence()
	test_json_matches_tres()
	print("RESULT: %d checks, %d failures" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func _spec_from_fixture(c: Dictionary) -> PixelTelegraphSpec:
	var s := S.new()
	s.shape = {"fan": S.Shape.FAN, "circle": S.Shape.CIRCLE, "ring": S.Shape.RING, "rect": S.Shape.RECT, "ray": S.Shape.RAY}[c.shape]
	s.radius_px = int(c.radius)
	s.inner_radius_px = int(c.inner_radius)
	s.angle_deg = float(c.angle)
	s.length_px = int(c.length)
	s.width_px = int(c.width)
	s.anchor = S.Anchor.TARGET if c.anchor == "target" else S.Anchor.CASTER
	return s


## 1) GDScript geometry == Python reference geometry, pixel for pixel.
func test_python_fixtures() -> void:
	var f := FileAccess.open("res://tests/fixtures/python_masks.json", FileAccess.READ)
	check(f != null, "fixture file missing")
	if f == null:
		return
	var cases: Array = JSON.parse_string(f.get_as_text())
	for c in cases:
		var shp := PixelTelegraph.compute_shape(_spec_from_fixture(c), Vector2i(int(c.origin[0]), int(c.origin[1])), deg_to_rad(float(c.deg)))
		var want := {}
		for p in c.cells:
			want[Vector2i(int(p[0]), int(p[1]))] = true
		var got: Dictionary = shp.cells
		var missing := 0
		var extra := 0
		for p in want:
			if not got.has(p):
				missing += 1
		for p in got:
			if not want.has(p):
				extra += 1
		check(missing == 0 and extra == 0, "fixture %s: missing %d extra %d (python %d px)" % [c.name, missing, extra, want.size()])
	print("python fixtures: %d cases compared" % cases.size())


func _cases() -> Array:
	var out := []
	var shapes := [S.Shape.FAN, S.Shape.CIRCLE, S.Shape.RING, S.Shape.RECT, S.Shape.RAY]
	var styles := [S.Style.STANDARD, S.Style.QUICK_FLASH, S.Style.AIM_LINE, S.Style.COUNTDOWN, S.Style.THEMED]
	for sh in shapes:
		for st in styles:
			if st == S.Style.AIM_LINE and sh != S.Shape.RAY and sh != S.Shape.RECT:
				continue   # aim line is only meant for rays / rects
			for anchor in [S.Anchor.CASTER, S.Anchor.TARGET]:
				var s := S.new()
				s.shape = sh
				s.style = st
				s.anchor = anchor
				s.radius_px = 40
				s.inner_radius_px = 20
				s.angle_deg = 75
				s.length_px = 48 if sh == S.Shape.RECT else 80
				s.width_px = 16 if sh == S.Shape.RECT else 3
				s.warning_time = 0.5
				s.track_time = 0.2 if sh == S.Shape.RAY or sh == S.Shape.FAN else 0.0
				if st == S.Style.THEMED:
					s.overlay = PixelTelegraphCrackOverlay.new()
				out.append(s)
	# the wooden-dummy example attacks with final values
	out.append(load("res://examples/fast_sweep.tres"))
	out.append(load("res://examples/heavy_chop.tres"))
	out.append(load("res://examples/homing_thorn.tres"))
	out.append(load("res://examples/square_drop.tres"))
	return out


## 2) Every drawn frame stays inside the hitbox; the hit frame equals the hitbox;
##    contains_point() agrees with the drawn hit-frame mask pixel by pixel.
func test_draw_equals_hitbox() -> void:
	var n := 0
	for s in _cases():
		n += 1
		var tel := PixelTelegraph.new()
		tel.autoplay = false
		tel.auto_free = false
		get_root().add_child(tel)
		var caster := Vector2(100, 100)
		tel.start_at(s, caster, caster + Vector2(30, 10))
		var dur: int = s.warning_frames()
		for fr in range(0, dur + 1):
			# move the target so tracking specs actually rotate
			tel.target_position = caster + Vector2(30, 10).rotated(fr * 0.08)
			tel.step_to_frame(fr)
			var img := tel.render_frame_image(fr)
			var r := tel.get_pixel_rect()
			var painted := {}
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.0:
						painted[Vector2i(x, y) + r.position] = true
			var outside := 0
			for p in painted:
				if not tel.contains_point(Vector2(p) + Vector2(0.5, 0.5)):
					outside += 1
			check(outside == 0, "case %d frame %d: %d drawn px outside hitbox" % [n, fr, outside])
			if fr == dur:
				var mismatch := 0
				for y in range(r.position.y - 3, r.end.y + 3):
					for x in range(r.position.x - 3, r.end.x + 3):
						var p := Vector2i(x, y)
						if tel.contains_point(Vector2(x, y) + Vector2(0.37, 0.81)) != painted.has(p):
							mismatch += 1
				check(mismatch == 0 and painted.size() == tel.get_cell_count(),
					"case %d hit frame: %d mismatches, painted %d vs cells %d" % [n, mismatch, painted.size(), tel.get_cell_count()])
		tel.free()
	print("draw==hitbox: %d specs checked" % n)


func test_signals_and_tracking() -> void:
	var s: PixelTelegraphSpec = load("res://examples/homing_thorn.tres")
	var tel := PixelTelegraph.new()
	tel.autoplay = false
	tel.auto_free = false
	get_root().add_child(tel)
	var events := []
	tel.warning_started.connect(func(): events.append(["warning_started", tel.get_frame()]))
	tel.locked.connect(func(): events.append(["locked", tel.get_frame()]))
	tel.hit.connect(func(): events.append(["hit", tel.get_frame()]))
	tel.finished.connect(func(): events.append(["finished", tel.get_frame()]))
	tel.start_at(s, Vector2(50, 50), Vector2(100, 50))
	var angle_at_lock := 0.0
	for fr in range(0, 34):
		tel.target_position = Vector2(50, 50) + Vector2(50, 0).rotated(fr * 0.05)
		tel.step_to_frame(fr)
		if fr == 18:
			angle_at_lock = tel.get_angle()
	check(events.size() == 4, "signal count %d (%s)" % [events.size(), events])
	if events.size() == 4:
		check(events[0][0] == "warning_started" and events[1][0] == "locked" and events[2][0] == "hit" and events[3][0] == "finished", "signal order %s" % [events])
		check(events[1][1] == 18, "ray locks at frame 18 (0.6s @30fps), got %d" % events[1][1])
		check(events[2][1] == 30, "hit at frame 30 (1.0s), got %d" % events[2][1])
	check(absf(tel.get_angle() - angle_at_lock) < 1e-6, "angle frozen after lock")
	check(tel.get_angle() > 0.5, "angle tracked the target before locking")
	tel.free()


func test_budget() -> void:
	var b := PixelAttackBudget.new()
	b.capacity = 3
	var a := Node.new()
	var c := Node.new()
	var t1 := b.try_acquire(a, 1)
	var t2 := b.try_acquire(a, 1)
	var t3 := b.try_acquire(c, 1)
	check(t1 > 0 and t2 > 0 and t3 > 0, "3 slots acquired")
	check(b.try_acquire(c, 1) == 0, "4th slot refused")
	b.release(t2)
	check(b.available() == 1, "release frees one slot")
	b.release_all_for(a)
	check(b.used() == 1, "release_all_for owner")
	b.tick(100.0)
	check(b.used() == 0, "timeout reclaims leaked tickets")
	var t4 := b.try_acquire(c, 1, 1.0)
	c.free()
	b.tick(0.01)
	check(b.used() == 0 and t4 > 0, "freed owner releases its tickets")
	a.free()
	b.free()


func test_cadence() -> void:
	var cad := PixelAttackCadence.new(1234)
	cad.set_gap_range(1.0, 3.0)
	var counts := [0, 0, 0]
	var prev := -1
	var double_short := 0
	var out_of_range := 0
	var N := 4000
	for i in N:
		var g := cad.next_gap()
		var t := cad.last_tier
		counts[t] += 1
		if t == PixelAttackCadence.Tier.SHORT and prev == PixelAttackCadence.Tier.SHORT:
			double_short += 1
		prev = t
		if g < 1.0 or g > 3.0:
			out_of_range += 1
	check(out_of_range == 0, "all gaps within 1.0-3.0s")
	check(double_short == 0, "no two short gaps in a row")
	var ps := float(counts[0]) / N
	var pm := float(counts[1]) / N
	check(absf(ps - 0.25) < 0.03 and absf(pm - 0.5) < 0.03, "tier ratio ~25/50/25: %s" % [counts])
	var ids := ["fast", "heavy", "thorn", "square"]
	var last: Variant = null
	var repeats := 0
	for i in 2000:
		var a: Variant = cad.next_attack(ids)
		if a == last:
			repeats += 1
		last = a
	check(repeats == 0, "never the same attack twice in a row")
	print("cadence: tiers %s over %d gaps" % [counts, N])


## The JSON spec (shared with the Python preview tool) and the .tres presets agree.
func test_json_matches_tres() -> void:
	var specs := PixelTelegraphSpec.load_json("res://examples/wooden_dummy.json")
	check(specs.size() == 4, "4 attacks loaded from JSON")
	for id in [&"fast_sweep", &"heavy_chop", &"homing_thorn", &"square_drop"]:
		var a: PixelTelegraphSpec = specs.get(id)
		var b: PixelTelegraphSpec = load("res://examples/%s.tres" % id)
		check(a != null and b != null, "spec %s present" % id)
		if a == null or b == null:
			continue
		for prop in ["shape", "radius_px", "angle_deg", "length_px", "width_px", "anchor", "warning_time", "track_time", "style", "recovery_time", "damage", "budget_cost"]:
			check(a.get(prop) == b.get(prop), "%s.%s json=%s tres=%s" % [id, prop, a.get(prop), b.get(prop)])
		var ca := PixelTelegraph.compute_shape(a, Vector2i(40, 40), 0.3)
		var cb := PixelTelegraph.compute_shape(b, Vector2i(40, 40), 0.3)
		check(ca.cells.size() == cb.cells.size(), "%s same mask size" % id)
