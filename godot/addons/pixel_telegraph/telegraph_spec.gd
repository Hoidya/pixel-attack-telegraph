@tool
class_name PixelTelegraphSpec
extends Resource
## One attack warning ("telegraph") described as data.
## The SAME spec drives both the drawn warning and the damage hitbox
## (PixelTelegraph.contains_point), so what the player sees is exactly what hits.
## Units: pixels and seconds. 1 tile is usually 16 px.

enum Shape { FAN, CIRCLE, RING, RECT, RAY }
enum Style { STANDARD, QUICK_FLASH, AIM_LINE, COUNTDOWN, THEMED }
enum FillMode { AUTO, OUTWARD_FROM_CASTER, OUTWARD_FROM_SHAPE_CENTER, NONE }
enum Anchor { CASTER, TARGET }
enum ColorRole { DAMAGE, CONTROL, CUSTOM }

## Optional identifier, e.g. &"fast_sweep".
@export var id: StringName = &""

@export_group("Shape")
@export var shape: Shape = Shape.FAN
## FAN / CIRCLE / RING: outer radius in px (measured from the origin pixel centre).
@export var radius_px: int = 48
## RING only: inner radius in px (pixels at distance <= inner radius are NOT hit).
@export var inner_radius_px: int = 0
## FAN only: full opening angle in degrees.
@export_range(1.0, 360.0, 1.0) var angle_deg: float = 60.0
## RECT / RAY: length in px along the facing direction.
@export var length_px: int = 64
## RECT / RAY: width in px across the facing direction (RAY is usually 3).
@export var width_px: int = 16
## CASTER: shape starts at the caster. TARGET: shape is centred on the target's
## position (rounded to a pixel) at the moment the warning starts and never moves.
@export var anchor: Anchor = Anchor.CASTER
## If true the shape always faces fixed_direction_deg (0 = right, 90 = down).
## If false it faces the target (TARGET-anchored circle/ring/rect use 0 deg).
@export var use_fixed_direction: bool = false
@export var fixed_direction_deg: float = 0.0

@export_group("Timing")
## Seconds from warning start to the hit frame (the hit is checked exactly once).
@export var warning_time: float = 1.0
## > 0: for the first track_time seconds the facing follows the target, then it locks.
@export var track_time: float = 0.0
## Informational: vulnerable recovery after the hit (used by gameplay, not drawn).
@export var recovery_time: float = 0.2
## Telegraph animation is quantised to this frame rate (pixel-art friendly).
@export var fps: int = 30
## Fraction of the warning at the end during which the outline flashes.
@export_range(0.0, 0.5, 0.05) var end_flash_fraction: float = 0.2
## Number of bright flashes in that end window.
@export var end_flash_count: int = 3

@export_group("Look")
@export var style: Style = Style.STANDARD
## AUTO picks the style default: STANDARD/THEMED -> outward from caster,
## COUNTDOWN -> outward from shape centre, QUICK_FLASH/AIM_LINE -> none.
@export var fill_mode: FillMode = FillMode.AUTO
@export var color_role: ColorRole = ColorRole.DAMAGE
## Used when color_role == CUSTOM: [edge_dark, main, highlight, flash, white].
@export var custom_colors: PackedColorArray = PackedColorArray()
## THEMED style: monster-specific layer painted inside the shape (e.g. cracks).
@export var overlay: PixelTelegraphOverlay

@export_group("Gameplay")
@export var damage: int = 1
## Slots this attack takes from a shared PixelAttackBudget while it is active.
@export var budget_cost: int = 1


func resolved_fill_mode() -> FillMode:
	if fill_mode != FillMode.AUTO:
		return fill_mode
	match style:
		Style.STANDARD, Style.THEMED:
			return FillMode.OUTWARD_FROM_CASTER
		Style.COUNTDOWN:
			return FillMode.OUTWARD_FROM_SHAPE_CENTER
		_:
			return FillMode.NONE


func warning_frames() -> int:
	return maxi(1, roundi(warning_time * fps))


func track_frames() -> int:
	return maxi(0, roundi(track_time * fps))


## Build a spec from the same JSON keys used by the Python preview tool
## (shape, radius, inner_radius, angle, length, width, direction, anchor, duration,
## fill_mode, style, track_time, color_role, overlay) plus recovery/damage/budget_cost.
static func from_dict(t: Dictionary, extra: Dictionary = {}) -> PixelTelegraphSpec:
	var s := PixelTelegraphSpec.new()
	var shapes := {"fan": Shape.FAN, "circle": Shape.CIRCLE, "ring": Shape.RING, "rect": Shape.RECT, "ray": Shape.RAY}
	var styles := {"standard": Style.STANDARD, "quick": Style.QUICK_FLASH, "aim": Style.AIM_LINE,
		"countdown": Style.COUNTDOWN, "themed": Style.THEMED}
	var fills := {"outward_from_caster": FillMode.OUTWARD_FROM_CASTER,
		"outward_from_shape_center": FillMode.OUTWARD_FROM_SHAPE_CENTER, "none": FillMode.NONE}
	s.id = StringName(str(extra.get("id", "")))
	s.shape = shapes.get(t.get("shape", "fan"), Shape.FAN)
	s.radius_px = int(t.get("radius", 48))
	s.inner_radius_px = int(t.get("inner_radius", 0))
	s.angle_deg = float(t.get("angle", 60))
	s.length_px = int(t.get("length", 64))
	s.width_px = int(t.get("width", 3 if s.shape == Shape.RAY else 16))
	if t.get("direction") != null:
		s.use_fixed_direction = true
		s.fixed_direction_deg = float(t.direction)
	s.anchor = Anchor.TARGET if t.get("anchor", "caster") == "target" else Anchor.CASTER
	s.warning_time = float(t.get("duration", 1.0))
	s.track_time = float(t.get("track_time", 0.0))
	s.style = styles.get(t.get("style", "standard"), Style.STANDARD)
	if t.get("fill_mode") != null:
		s.fill_mode = fills.get(t.fill_mode, FillMode.AUTO)
	s.color_role = ColorRole.CONTROL if t.get("color_role", "damage") == "control" else ColorRole.DAMAGE
	if t.get("overlay") == "cracks":
		s.overlay = PixelTelegraphCrackOverlay.new()
	s.recovery_time = float(extra.get("recovery", 0.2))
	s.damage = int(extra.get("damage", 1))
	s.budget_cost = int(extra.get("budget_cost", 1))
	return s


## Loads every attack of a preview-tool JSON file: returns { id: PixelTelegraphSpec }.
static func load_json(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("PixelTelegraphSpec: cannot open " + path)
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for atk in data.get("attacks", []):
		out[StringName(str(atk.get("id", "")))] = from_dict(atk.get("telegraph", {}), atk)
	return out
