# Telegraph design guide

Condensed from a survey of how action games warn players (sources at the end).

## What a warning must say
1. **Where** - the exact area that will hurt. It must equal the hitbox, pixel for pixel.
2. **When** - how much time is left. Players should not need to count seconds.

## Seven common approaches

| # | Approach | Good at | Weak at | Use it as |
|---|---|---|---|---|
| 1 | Outline first, then fill inside (WildStar, Lost Ark, FFXIV) | fair, shows both where and when | very short attacks have no time to fill | default (`standard`) |
| 2 | Fill outward from the attacker (Mytheria, Hades II) | also shows where the attack comes from | - | default fill direction for melee |
| 3 | Outline flashes, faster near the hit (Enter the Gungeon sniper laser) | very short attacks | no progress info | `quick` for < 0.4 s |
| 4 | Colour ramps darker over time | cheap | timing unreadable, colour-blind unfriendly; WoW replaced its "swirlies" | accent only, never alone |
| 5 | Dither / hatch getting denser | pixel-art version of 1 and 2 | - | how fill is drawn here (Bayer 4x4) |
| 6 | Themed ground cues (cracks, roots, shadows) | monster identity | hard to align with the hitbox | `themed` = standard outline + overlay clipped to the hitbox |
| 7 | Animation only, no ground marker (Sekiro, Elden Ring) | immersion | ranges unreadable in top-down 2D | not alone in top-down games |

## The shared language used by this skill
- On start: dark outer outline + red inner outline + very sparse red dither (full area visible at once).
- Progress: dither fills from the caster (or from the shape centre for drops), with a bright 2-3 px front.
- Last 20 %: outline flashes 3 times. Hit frame: the whole area flashes for 1 frame, then the attack VFX takes over.
- Aim line: 1 px dashed line while tracking, 3 px bright line once locked, a dot runs from caster to tip; fire when it arrives.
- Countdown (drops at the player's feet): fills from the shape's own centre.
- Colours are *roles*: red = damage (default); add others (e.g. blue = control) only with a legend.
- Theme belongs in overlays (cracks, roots), never in the shared language, so every monster stays readable.

## Readability checklist
- Dark outline + light inner outline: readable on grass, stone and sand.
- Never colour-only; always a shape outline.
- Size in whole tiles where possible; anything under ~1 tile beyond the enemy's body feels like "no range".
- Fast = narrow, slow = wide. Fast + wide feels unfair.
- Target-anchored drops snap once (rounded pixel) and stay.
- Tracking aim lines must lock early enough to dodge (e.g. track 0.6 s, lock 0.4 s).

## Sources
- WildStar telegraph combat: https://www.greenyneko.com/2019/07/wildstars-legacy-telegraph-based-combat.html
- Telegraphing attacks in a pixel game (Mytheria): https://cobomakesgames.com/blog/telegraphing-attacks/
- Enter the Gungeon, Sniper Shell (laser before shot): https://enterthegungeon.wiki.gg/wiki/Sniper_Shell
- WoW replacing "swirlies" for readability: https://www.pcgamer.com/games/world-of-warcraft/wows-finally-upgrading-its-dreaded-swirlies-so-players-can-actually-tell-where-its-safe-to-stand/
- Hades II, Root-Stalker (aimed root spikes): https://game8.co/games/Hades-2/archives/454245
- Cult of the Lamb, Leshy (ground markings aligned with slams): https://www.dualshockers.com/cult-of-the-lamb-leshy-guide/
- Pixel melee attack animation: https://www.slynyrd.com/blog/2018/9/8/pixelblog-9-melee-attacks
- Anatomy of an attack (anticipation / active / recovery): https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/
