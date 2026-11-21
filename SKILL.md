---
name: pixel-attack-telegraph
description: Design and implement fair, reusable attack warnings ("telegraphs" - danger zones, AoE indicators, aim lines) and enemy attack rhythm for 2D pixel-art games. Use when adding or reworking enemy/boss attacks, their warning visuals or hitboxes, or the timing between attacks. Recommends a shape + style + timing per attack, asks the designer for customization, writes a spec, implements it with the bundled Godot 4 PixelTelegraph system (drawn warning == hitbox), adds attack cadence and a shared attack budget, and can render preview GIFs.
---

# Pixel Attack Telegraph

A reusable "warning language" for enemy attacks. Each attack is one small spec
(shape, size, timing, style); the **same spec draws the warning and decides the hit**,
so players are only ever hit where they were warned.

Bundled (paths relative to this skill folder):
- `godot/addons/pixel_telegraph/` - Godot 4 implementation (tested): `PixelTelegraphSpec`,
  `PixelTelegraph`, `PixelTelegraphOverlay`, `PixelTelegraphCrackOverlay`,
  `PixelAttackBudget`, `PixelAttackCadence`. Demo: `godot/demo/`. Tests: `godot/tests/run_tests.gd`.
- `tools/recommend_telegraph.py` - first-pass recommendation from a list of attacks.
- `tools/render_preview.py` - renders preview GIFs from a JSON spec (Ninja Adventure CC0 art).
- `references/design-guide.md` - why these rules (with sources).
- `references/parameters.md` - every parameter, JSON key and Godot property.
- `references/cadence-and-budget.md` - gaps between attacks and the shared attack budget.
- `examples/` - a complete worked example (a wooden training dummy with 4 attacks) + GIFs.

## Workflow

Follow these steps in order. Talk to the user in their language. Keep numbers in tiles
(1 tile = 16 px unless the project says otherwise) when talking to designers.

### 1. Collect the attacks
Read the project's enemy/boss code and design docs and list every attack: name, how it
hits (melee arc, projectile, dash, ground drop, self burst, ring, beam), current windup,
reach, and whether it is meant to be light or heavy. Also read any project style guide
(e.g. `docs/vfx-style.md`, `AGENTS.md`) and obey it. If the attacks are not in code yet,
ask the user to describe them (one line each is enough).

### 2. Recommend shape + style + timing
Use this table (or run `python tools/recommend_telegraph.py attacks.json`; input format
in `examples/attacks_input_example.json`):

| Attack | Shape | Style | Typical warning |
|---|---|---|---|
| Light melee swing | fan, 2-3 tiles, 45-75 deg | standard fill (outward from caster) | 0.6-1.0 s |
| Heavy melee / slam | fan, 3+ tiles, 90-140 deg | themed (standard + monster overlay, e.g. cracks) | 1.2-1.8 s + recovery window 0.4-0.6 s |
| Anything under 0.4 s | any | quick flash (outline + flashes, no fill) | 0.25-0.4 s (use sparingly) |
| Projectile / dash | ray (width 3 px) or rect | aim line; optional tracking then lock | 0.8-1.2 s, track ~60 % then lock |
| Drop at the player's feet | rect / circle, anchor = target | countdown (fill from shape centre) | 0.8-1.2 s |
| Self-centred burst | circle | standard (outward from caster) | 0.8-1.2 s |
| Donut (safe inside) | ring | countdown (inner -> outer) | 1.0-1.5 s |
| Beam / long line | rect | standard | 0.8-1.2 s |
| Cross, L-shape, multi-tile, hand-drawn area | **custom** (the 5 shapes above are only defaults) | standard or countdown | 0.8-1.2 s |

The 5 built-in shapes (fan, circle, ring, rect, ray) are **defaults**, not a closed list. If an
attack does not fit them, recommend a custom shape (see question 1 below).

Balance rule of thumb: **fast attacks are narrow, slow attacks are wide** (never fast + wide).
Present the recommendation as a short table and explain each choice in one line.

### 3. Ask for customization
Ask these in ONE message, each with the recommended default so the user can just say "ok":
1. **Shape: use one of the 5 default shapes (fan, circle, ring, rect, ray), or define a custom shape?**
   The 5 built-in shapes are only defaults. To describe a custom shape, pick one of:
   (a) **Tile mask** — a grid of characters in 16 px tiles, with an origin / anchor cell.
       `#` = filled, `.` or space = empty, `@` or `o` = filled cell whose centre is the origin.
       If there is no `@`, the origin defaults to the centre of the mask (or set `tile_anchor`
       in tile units from the mask's top-left; the centre of a 2x2 is `[1, 1]`).
       Example 2x2 square centred on the player: `["##", "##"]` with anchor `target`.
       Example plus / cross: `[".#.", "###", ".@."]`.
   (b) **Polygon** — vertices in pixels, relative to the caster or the target.
   (c) **Combination** — a union of default shapes (e.g. two rects making a cross, or a fan plus a circle).
   Also confirm: **anchor** (caster / the player's position at the moment of cast / a locked point)
   and **rotation** (faces the target, or a fixed angle; target-anchored custom shapes stay
   axis-aligned unless a direction is set).
   The same shape data must still drive both the warning drawing and the hitbox
   (warning == hitbox).
   Styles: all 5 work with custom shapes. Standard / themed fill grows outward from the caster
   (that is the fill origin). Countdown fills from the shape's centre / anchor. Quick flash
   only draws the outline. Aim line is meant for a long thin ray / rect and is usually a
   poor fit for a blob or tile-mask.
2. Reach / size per attack, in tiles (radius, length x width, square size, or mask size).
3. Fan angles (e.g. light 60 deg, heavy 120 deg), if using fans.
4. Warning time per attack (seconds) and recovery after heavy attacks.
5. Fill mode: from the caster, from the shape centre, or none.
6. Tracking: lock at start, or follow the player for N s then lock (aim lines).
7. Anchor: in front of the enemy, or at the player's feet.
8. **Skill category:** is each attack **DAMAGE**, **CONTROL** (knockback, slow, stun, root, pull),
   or **MIXED** (damage + control)? Optional: **SUPPORT** / other.
9. **Colours are customisable.** Defaults: red = damage; blue = control (a reserved interface
   colour, optional and unused by default — the wooden-dummy example only uses red);
   MIXED can use purple, or red fill + blue edge. Users may override any colour per category
   or per skill (e.g. to match a monster theme), but keep the mapping consistent within a
   game and readable against the background (dark outer + light inner outline, Bayer dither,
   never colour-only).
10. Rhythm: random gap range between attacks (default 1.0-3.0 s, tiers 25/50/25),
    no same attack twice in a row?
11. Attack budget: how many attacks may be active at once across all enemies (default 2-3)?
12. Optional rules: max one projectile at a time, staggered starts, no overlapping drops
    (default: off - only add them if the user wants them).
Explain trade-offs briefly when relevant (e.g. tracking makes dodging harder; a 0.5 s
minimum gap with budget 3 is much harder than a fixed 2.5 s gap).

### 4. Write the spec, then implement
1. Write a spec table (attack, shape — including custom mask/polygon/union if used — size
   px/tiles, anchor, warning, style, tracking, category, colour, recovery, damage, budget
   cost) into the project docs, and a JSON file in the format of `examples/wooden_dummy.json`
   (same keys as `tools/telegraph_lib.py` DEFAULTS).
2. Copy `godot/addons/pixel_telegraph/` into the project (`res://addons/pixel_telegraph/`).
   Create one `.tres` per attack (see `godot/examples/*.tres`) or load the JSON with
   `PixelTelegraphSpec.load_json(path)`.
3. Per attack:
   ```gdscript
   var ticket := budget.try_acquire(enemy, spec.budget_cost)
   if ticket == 0: return                     # no slot: wait and retry later, do not start a warning
   var tel := PixelTelegraph.new()
   world.add_child(tel)                       # unscaled world layer; coordinates are global pixels
   tel.target_offset = Vector2(0, 5)          # aim at the player's feet if that is the hurt point
   tel.hit.connect(func():
       if tel.contains_point(player.global_position + hurt_offset):
           player.take_hit(spec.damage))      # route through the existing damage / block / parry path
   tel.finished.connect(func():               # hit frame shown -> play recovery, then free the slot
       await get_tree().create_timer(spec.recovery_time).timeout
       budget.release(ticket))
   tel.start(spec, enemy, player)
   ```
   For projectiles, `hit` means "fire now": spawn the projectile on `hit`; damage comes from
   the projectile's own collision.
4. Rhythm: one `PixelAttackCadence` per enemy (`set_gap_range(min, max)`, `next_gap()`,
   `next_attack(ids)`), one shared `PixelAttackBudget` (`try_acquire` BEFORE the warning,
   release after recovery / projectile end / death / interrupt). If you make it an autoload,
   do not give the autoload the same name as the class.
5. Attack VFX (slashes, debris, projectiles) should be pre-made frames (`AnimatedSprite2D`),
   pixel-snapped and nearest-filtered. Only the telegraph is drawn procedurally.
6. Remove any old warning drawing and old hit shapes for these attacks: one source of truth.

### 5. Verify warning == hitbox
- Run the bundled tests: `godot --headless --path <skill>/godot -s res://tests/run_tests.gd`
  (exit code 0). After porting, run them inside the project too.
- In game, stand 1 px inside the warning edge -> hit; 1 px outside -> no hit.
- Check the project's own tests and a 60 s play session report 0 script errors.
- Log ~50 attacks: gaps within the range, tier ratio as chosen, budget never exceeded.

### 6. Optional: preview GIFs
`pip install -r tools/requirements.txt`, then
`python tools/render_preview.py your_spec.json -o previews/`. It renders one GIF per
attack + `all.gif`, and fails if anything is drawn outside the hitbox. Show the GIFs to
the user before or after implementing.

## Fairness rules (always)
- The warning **is** the hitbox: same data, checked once on the hit frame.
- Show the full area immediately (outline + faint dither), then show time with fill
  progress; flash in the last ~20 %. Never rely on colour alone: always a dark outline
  + light inner outline so it reads on any floor and for colour-blind players.
- Pixel style: integer pixels, opaque colours, Bayer dither instead of alpha gradients,
  no rotation of textures, no blur.
- Heavy attacks leave a recovery window that the rhythm never cuts short.
- Gaps start after recovery, not at warning start. Use tiers / shuffle bags, not pure
  uniform random, and avoid back-to-back shortest gaps.
- Limit simultaneous attacks with a shared budget; tune difficulty with budget and gaps
  first, warning time last.
- Target-anchored drops snap once at warning start and never follow the player.
