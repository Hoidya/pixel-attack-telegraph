# Attack cadence and the shared attack budget

## Timeline of one attack
`warning -> resolve (hit / projectile flight) -> recovery -> gap -> next attack`

- The **gap** starts when recovery ends (or when the enemy is interrupted), never at warning start.
  So a short gap can never eat a heavy attack's recovery (counter-attack) window.
- Recovery examples: light swing 0.2 s, heavy slam 0.45 s (counter window), projectile 0.2 s after firing, drop 0.25 s.

## Random gaps that still feel fair
Pure uniform random produces streaks (three shortest gaps in a row). Use tiers in a shuffle bag:

| Tier | Share | Default (range 1.0-3.0 s) |
|---|---|---|
| short | 25 % | 1.0-1.4 s |
| mid | 50 % | 1.6-2.4 s |
| long | 25 % | 2.5-3.0 s |

- Bag `[short, mid, mid, long]`, reshuffle when empty; never two `short` in a row for the same enemy.
- `PixelAttackCadence.set_gap_range(min, max)` derives the three tiers from any range.
- Pick attacks from a shuffle bag too, never the same attack twice in a row (`next_attack(ids)`).
- Note: a uniform 0.5-2.5 s gap averages 1.5 s - about 40 % faster than a fixed 2.5 s. Check difficulty.

## Shared attack budget ("attack tokens")
All enemies in an encounter share N slots (Doom 2016 / God of War style). An enemy must get
a slot **before** it starts a warning; if refused it waits (never start a warning and cancel it).

- Default capacity 2-3; each attack costs 1 (or heavy attacks cost 2 if you want weight-based limits, Kingdoms of Amalur style).
- Hold the slot from warning start to the end of recovery (projectiles: until they hit / break / expire).
- Release on: normal end, interrupt/stun, target lost, death/despawn, phase change. `PixelAttackBudget` also
  reclaims tickets of freed owners and after a timeout (safety net only).
- Optional extra rules (off by default; add only if playtests need them): max one projectile at a time,
  minimum stagger between enemies' starts, no overlapping ground drops, per-attack-type cooldown.
- Overlapping attacks are not combos. Real combos should be explicit sequences billed as one attack.

## Phase / encounter start
Give a reaction period (e.g. 3 s) at the start of each phase during which nobody requests slots.

## Tuning difficulty (in this order)
1. Budget capacity (2 easier, 4 harder).
2. Gap tiers (remove `short` to make it easier; lower `mid` by 0.3 s to make it harder).
3. Only then warning times.

## Acceptance checks
- ~50 logged attacks: tier ratio close to the chosen split, all gaps in range, no back-to-back short.
- With all enemies alive, active attacks never exceed the budget.
- After a heavy attack, the enemy never starts anything during its recovery.

## Sources
- AI of Doom 2016 (attack tokens): https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-
- Beyond the Kung-Fu Circle (weighted attack budget, Kingdoms of Amalur): https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter28_Beyond_the_Kung-Fu_Circle_A_Flexible_System_for_Managing_NPC_Attacks.pdf
- Anatomy of an attack: https://gdkeys.com/keys-to-combat-design-1-anatomy-of-an-attack/
- How enemy attack timing works: https://signalsandlight.substack.com/p/how-does-enemy-attack-timing-work
- Simultaneous enemy attacks: https://signalsandlight.substack.com/p/how-do-simultaneous-enemy-attacks
