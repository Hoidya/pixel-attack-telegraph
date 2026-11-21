#!/usr/bin/env python3
"""Suggest a telegraph (shape + style + timing) for each attack of a monster.

    python tools/recommend_telegraph.py attacks.json            # prints a table + JSON
    python tools/recommend_telegraph.py attacks.json -o spec.json

Input JSON: {"attacks": [{"id": "bite", "kind": "melee", "windup": 0.8,
                          "reach_tiles": 2, "width_deg": 60, "weight": "light"}, ...]}
kind: melee | heavy_melee | projectile | dash | ground_drop | self_aoe | ring | line
      | custom | cross | plus | l_shape
Optional per attack: windup (s), reach_tiles, width_deg, size_tiles, homing (bool),
weight (light|heavy), tile_px (default 16), category (damage|control|mixed|support),
tile_mask (list of strings), tile_anchor, custom_polygon, custom_union, anchor, style.
The 5 shapes (fan, circle, ring, rect, ray) are only defaults; pass a tile_mask,
polygon, or custom_union (or kind custom/cross/plus/l_shape) for a custom shape.
The output uses the same keys as tools/render_preview.py, so you can preview it directly.
These are DEFAULTS to discuss with the designer, not final values.
"""
import argparse, json, sys

RULES = """decision table
- windup < 0.4 s                     -> quick_flash (outline + flashes, no fill)
- projectile / dash                  -> ray + aim line; aimed/homing: track 60% of windup then lock
- ground drop at the target's feet   -> rect/circle anchored on target + countdown (fill from shape centre)
- self-centred burst                 -> circle + standard (fill outward from caster)
- donut / safe-inside                -> ring + countdown
- heavy melee (windup >= 1.2 s)      -> fan + themed (standard fill + monster overlay), wide & slow
- normal melee                       -> fan + standard fill, narrow & fast
- long line / beam                   -> rect + standard fill from caster
- tile_mask / polygon / custom_union / kind custom|cross|plus|l_shape
                                     -> custom shape (same data drives warning and hitbox)

Ask the designer (the 5 built-in shapes are only defaults):
- Use a default shape, or define a custom one (tile mask, polygon, or union of defaults)?
- Category per attack: DAMAGE, CONTROL (knockback/slow/stun/root/pull), MIXED, or optional SUPPORT?
- Colours are customisable. Defaults: red = damage, blue = control (reserved, unused unless
  you opt in; the wooden-dummy example is red only), mixed = purple (or red fill + blue edge).
  Override per category or per skill if you want, but keep it consistent and readable."""


def recommend(a, tile=16):
    kind = a.get('kind', 'melee')
    w = float(a.get('windup', 1.0))
    reach = float(a.get('reach_tiles', 3))
    why = []
    t = dict(duration=round(w, 2))
    # custom shape: tile mask, polygon, union of default shapes, or a named kind
    custom_keys = a.get('tile_mask') or a.get('custom_polygon') or a.get('polygon') or a.get('custom_union')
    if kind in ('custom', 'cross', 'plus', 'l_shape') or custom_keys:
        t.update(shape='custom', style=a.get('style', 'countdown' if a.get('anchor') == 'target' else 'standard'))
        if a.get('anchor'):
            t['anchor'] = a['anchor']
        if a.get('tile_mask'):
            t['tile_mask'] = a['tile_mask']
            t['tile_size'] = int(a.get('tile_size', tile))
            if a.get('tile_anchor') is not None:
                t['tile_anchor'] = a['tile_anchor']
        elif kind in ('cross', 'plus'):
            t['tile_mask'] = ['.#.', '###', '.@.']
            t['tile_size'] = tile
            why.append('plus/cross as a custom tile mask (origin = @ cell)')
        elif kind == 'l_shape':
            t['tile_mask'] = ['#.', '#.', '##']
            t['tile_size'] = tile
            why.append('L-shape as a custom tile mask (origin = mask centre)')
        if a.get('custom_polygon') or a.get('polygon'):
            t['custom_polygon'] = a.get('custom_polygon') or a.get('polygon')
        if a.get('custom_union'):
            t['custom_union'] = a['custom_union']
        if not t.get('tile_mask') and not t.get('custom_polygon') and not t.get('custom_union'):
            why.append('custom shape requested — ask the designer for a tile mask, a polygon, or a union of default shapes')
        else:
            why.append('custom shape: the same data draws the warning and is the hitbox')
    elif kind in ('projectile', 'dash'):
        t.update(shape='ray', length=int(reach * tile) if 'reach_tiles' in a else 96, width=3, style='aim')
        if a.get('homing') or a.get('aimed', True):
            t['track_time'] = round(w * 0.6, 2)
            why.append('aim line follows the target for 60% of the windup, then locks')
    elif kind == 'ground_drop':
        size = int(float(a.get('size_tiles', 2)) * tile)
        shape = a.get('shape', 'rect')
        t.update(shape=shape, anchor='target', style='countdown')
        if shape == 'circle':
            t['radius'] = size // 2
        else:
            t.update(length=size, width=size)
        why.append("placed at the target's feet when the warning starts, fills from its centre")
    elif kind == 'self_aoe':
        t.update(shape='circle', radius=int(reach * tile), style='standard')
    elif kind == 'ring':
        t.update(shape='ring', radius=int(reach * tile), inner_radius=int(float(a.get('inner_tiles', reach / 2)) * tile),
                 style='countdown')
    elif kind == 'line':
        t.update(shape='rect', length=int(reach * tile), width=int(float(a.get('size_tiles', 1)) * tile), style='standard')
    else:
        heavy = kind == 'heavy_melee' or a.get('weight') == 'heavy' or w >= 1.2
        t.update(shape='fan', radius=int(reach * tile), angle=float(a.get('width_deg', 120 if heavy else 60)),
                 style='themed' if heavy else 'standard')
        if heavy:
            t['overlay'] = 'cracks'
        why.append('heavy: wide + slow + recovery window' if heavy else 'light: narrow + fast')
    if w < 0.4 and t.get('style') != 'aim':
        t['style'] = 'quick'
        why.append('windup < 0.4 s: no time to read a fill, flash the outline instead')
    if w < 0.5:
        why.append('WARNING: < 0.5 s is hard to react to; consider >= 0.6 s')
    if t.get('anchor') == 'target' and w < 0.8:
        why.append('WARNING: target-anchored drops usually need >= 0.8 s to walk out')
    rec = a.get('recovery', 0.45 if t.get('style') == 'themed' else 0.2)
    cat = a.get('category', 'damage')
    t['category'] = cat
    return dict(id=a.get('id', kind), telegraph=t, recovery=rec, budget_cost=a.get('budget_cost', 1),
                damage=a.get('damage', 1), category=cat), why


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('attacks')
    ap.add_argument('-o', '--out')
    ap.add_argument('--tile', type=int, default=16)
    a = ap.parse_args()
    with open(a.attacks, encoding='utf-8') as fh:
        src = json.load(fh)
    out = dict(canvas=dict(width=160, height=96, scale=3), caster=dict(sprite='wooden_dummy', x=44, y=48), attacks=[])
    print(RULES + '\n')
    for atk in src['attacks']:
        r, why = recommend(atk, a.tile)
        r['label'] = f"{r['id']} | {r['telegraph']['shape']} | {r['telegraph']['duration']}s {r['telegraph']['style']}"
        out['attacks'].append(r)
        print(f"{r['id']:<16} {json.dumps(r['telegraph'])}")
        for w in why:
            print(f"{'':<16}   - {w}")
    txt = json.dumps(out, indent=2, ensure_ascii=False)
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as fh:
            fh.write(txt + '\n')
        print('\nwrote', a.out)
    else:
        print('\n' + txt)


if __name__ == '__main__':
    sys.exit(main())
