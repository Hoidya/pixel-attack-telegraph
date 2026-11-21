"""Export reference pixel masks from the Python implementation so the Godot test
can check that the GDScript port produces exactly the same hit shapes.
Usage (from repo root):  python tools/make_godot_fixtures.py
"""
import json, math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from telegraph_lib import shape_cells, DEFAULTS

CASES = [
    dict(name='fan_r48_a60_e', shape='fan', radius=48, angle=60, origin=(100, 80), deg=0),
    dict(name='fan_r48_a120_se', shape='fan', radius=48, angle=120, origin=(37, 51), deg=30),
    dict(name='fan_r32_a90_nw', shape='fan', radius=32, angle=90, origin=(-5, 12), deg=-135),
    dict(name='circle_r28', shape='circle', radius=28, origin=(60, 60), deg=0),
    dict(name='ring_r40_ri22', shape='ring', radius=40, inner_radius=22, origin=(70, 41), deg=0),
    dict(name='rect_64x16_caster', shape='rect', length=64, width=16, origin=(20, 20), deg=0),
    dict(name='rect_32x32_target', shape='rect', length=32, width=32, anchor='target', origin=(90, 64), deg=0),
    dict(name='rect_33x15_target_45', shape='rect', length=33, width=15, anchor='target', origin=(50, 50), deg=45),
    dict(name='ray_96x3_17deg', shape='ray', length=96, width=3, origin=(10, 70), deg=17),
    dict(name='ray_96x3_200deg', shape='ray', length=96, width=3, origin=(120, 40), deg=200),
]

out = []
for c in CASES:
    p = dict(DEFAULTS); p.update({k: v for k, v in c.items() if k not in ('name', 'origin', 'deg')})
    cells, _, _ = shape_cells(p, c['origin'], math.radians(c['deg']))
    out.append(dict(name=c['name'], shape=p['shape'], radius=p['radius'], inner_radius=p['inner_radius'],
                    angle=p['angle'], length=p['length'], width=p['width'], anchor=p['anchor'],
                    origin=list(c['origin']), deg=c['deg'], cells=sorted([list(x) for x in cells])))
dst = os.path.join(HERE, '..', 'godot', 'tests', 'fixtures', 'python_masks.json')
with open(dst, 'w') as f:
    json.dump(out, f, separators=(',', ':'))
print('wrote', len(out), 'cases ->', os.path.relpath(dst))
