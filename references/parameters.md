# Parameter reference

One attack = one spec. JSON keys (Python tool) and Godot properties (`PixelTelegraphSpec`) map 1:1.
Units: pixels and seconds. 1 tile = 16 px by default. Animation is quantised to 30 fps
(`round(seconds * 30)` frames; e.g. 1.0 s = 30, 1.5 s = 45, 0.6 s = 18, 0.45 s = 14 frames).

## Shape

| JSON (`telegraph.*`) | Godot | Values | Notes |
|---|---|---|---|
| `shape` | `shape` | `fan` FAN, `circle` CIRCLE, `ring` RING, `rect` RECT, `ray` RAY | ray = thin rect, usually 3 px wide |
| `radius` | `radius_px` | px | fan / circle / ring outer radius, from the origin pixel centre |
| `inner_radius` | `inner_radius_px` | px | ring only; pixels at distance <= inner radius are safe |
| `angle` | `angle_deg` | degrees | fan full opening angle |
| `length` | `length_px` | px | rect / ray length along the facing |
| `width` | `width_px` | px | rect / ray width across the facing |
| `anchor` | `anchor` | `caster` CASTER, `target` TARGET | target: centred on the target's position (rounded) at warning start, never moves |
| `direction` | `use_fixed_direction` + `fixed_direction_deg` | degrees or null | null = face the target. 0 = right, 90 = down. Target-anchored circle/ring/rect use 0 |

Pixels are tested at their centres (x + 0.5, y + 0.5), so a shape is a deterministic set of
integer pixels. Facing is quantised to whole degrees.

## Timing

| JSON | Godot | Default | Notes |
|---|---|---|---|
| `duration` | `warning_time` | 1.0 | warning start -> hit frame. The hit is checked once, on that frame |
| `track_time` | `track_time` | 0 | > 0: facing follows the target for this long, then locks (`locked` signal) |
| attack `recovery` | `recovery_time` | 0.2 | informational for gameplay (vulnerable window after the hit) |
| - | `fps` | 30 | animation frame rate |
| - | `end_flash_fraction` / `end_flash_count` | 0.2 / 3 | outline flashes in the last 20 % |

## Look

| JSON | Godot | Values |
|---|---|---|
| `style` | `style` | `standard` STANDARD, `quick` QUICK_FLASH, `aim` AIM_LINE, `countdown` COUNTDOWN, `themed` THEMED |
| `fill_mode` | `fill_mode` | null/AUTO, `outward_from_caster`, `outward_from_shape_center`, `none` |
| `color_role` | `color_role` | `damage` (red, default), `control` (blue); Godot also CUSTOM + `custom_colors` [edge, main, highlight, flash, white] |
| `overlay` | `overlay` | `"cracks"` -> `PixelTelegraphCrackOverlay`; write your own by extending `PixelTelegraphOverlay` |

AUTO fill: standard/themed -> from caster; countdown -> from shape centre; quick/aim -> none.

| Style | Drawing | Use for |
|---|---|---|
| standard | outline + sparse dither, fill grows (bright front), last 20 % flashes, 1-frame hit flash | most melee and areas |
| quick | outline only, flashing (every 2 frames, then every frame) | attacks under ~0.4 s |
| aim | 1 px dashed line while tracking, 3 px bright line when locked, a dot runs to the tip | projectiles, dashes |
| countdown | like standard but fills from the shape centre (rect grows as a square, ring inner -> outer) | drops at the player's feet |
| themed | standard + overlay clipped to the hitbox | heavy / boss attacks |

## Gameplay (attack level)

| JSON | Godot | Notes |
|---|---|---|
| `damage` | `damage` | applied once on `hit` if `contains_point()` |
| `budget_cost` | `budget_cost` | slots taken from `PixelAttackBudget` |
| `projectile` `{time, turn_deg_per_s}` | (your projectile scene) | preview tool only; in game spawn your projectile on `hit` |
| `target.path` | - | preview tool only: how the dummy target walks |

## Godot runtime API

`PixelTelegraph` (Node2D)
- `start(spec, caster: Node2D, target: Node2D = null)`, `start_at(spec, caster_pos, target_pos)`
- `caster_offset`, `target_offset`, `target_position`, `auto_free` (true), `autoplay` (true)
- signals `warning_started`, `locked`, `hit`, `finished`
- `contains_point(global_pos) -> bool` (the hitbox), `get_cells()`, `get_pixel_rect()`, `get_progress()`,
  `is_locked()`, `step_to_frame(f)` (manual stepping), `render_frame_image(f)` (what `_draw` shows)
- `PixelTelegraph.compute_shape(spec, origin, angle)` - pure geometry

`PixelTelegraphSpec.from_dict(telegraph_dict, attack_dict)` / `PixelTelegraphSpec.load_json(path)`
read the same JSON as the Python tool.

`PixelAttackBudget` (Node): `capacity`, `default_timeout`, `try_acquire(owner, cost, timeout) -> ticket (0 = refused)`,
`release(ticket)`, `release_all_for(owner)`, `used()`, `available()`, signal `slots_changed`.

`PixelAttackCadence` (RefCounted): `set_gap_range(min, max)`, `next_gap()`, `next_attack(ids)`, `last_tier`,
`short_range` / `mid_range` / `long_range`, `tier_bag_template`.
