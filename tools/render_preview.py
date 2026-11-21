#!/usr/bin/env python3
"""Render pixel-art preview GIFs of attack telegraphs from a JSON spec.

    python tools/render_preview.py examples/wooden_dummy.json -o out/
    python tools/render_preview.py examples/wooden_dummy.json -o out/ --only fast_sweep

Every attack gets its own GIF plus one combined GIF. The script also checks,
frame by frame, that nothing is drawn outside the hit shape (warning == hitbox)
and exits with code 1 if it is violated.

Spec format (JSON):
{
  "canvas": {"width": 160, "height": 96, "scale": 3},
  "caster": {"sprite": "wooden_dummy", "x": 48, "y": 48},
  "attacks": [
    {"id": "fast_sweep", "label": "fast sweep  fan 48px 60deg  1.0s",
     "telegraph": {"shape": "fan", "radius": 48, "angle": 60, "duration": 1.0, "style": "standard"},
     "recovery": 0.2,
     "projectile": null,
     "target": {"path": [[96, 40], [96, 60]]}}
  ]
}
telegraph keys = tools/telegraph_lib.py DEFAULTS (shape including custom, radius, inner_radius,
length, width, angle, direction, anchor, duration, fill_mode, style, track_time, color_role,
category, tile_mask, custom_polygon, custom_union) plus
"overlay": "cracks" for the themed style.
"projectile": {"time": 0.4, "turn_deg_per_s": 270} makes an aim-line attack fire a homing
projectile after the warning (damage then comes from the projectile, not the line).
"target.path": list of points the target walks through during the attack (linear).
Assets: Ninja Adventure (CC0) tiles shipped in assets/ninja-adventure/.
"""
import argparse, json, math, os, random, sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import telegraph_lib as T  # noqa: E402

FPS = T.FPS
ASSETS = os.path.join(REPO, 'assets', 'ninja-adventure')
WOOD = [T.hx('3b2f27'), T.hx('6b5a4a'), T.hx('9c8a72'), T.hx('c9b79c')]
WHITE = T.hx('ffffff')

DUMMY_ROWS = [
    "....oooooooo....", "...ohhhhhhhho...", "...ohlmmmmlho...", "...ohlmhhmlho...",
    "...ohhllllhho...", "...ommhhhhmmo...", "...olmmlmmmdo...", "...olmmlmmmdo...",
    "...olmommomdo...", "...olmmlmdmdo...", "...olmmlmmmdo...", "...olmmmmdmdo...",
    "...olmdmmlmdo...", "...olmmmmlmdo...", "...olmmdmlmdo...", "...olmmmmlmdo...",
    "...olmmlmmmdo...", "...olmmlmdmdo...", "..oolmmlmmmdoo..", "..odlmmmmmmddo..",
    ".odddmmmmmmdddo.", ".oooddddddddooo.",
]
CMAP = {'o': WOOD[0], 'd': WOOD[0], 'm': WOOD[1], 'l': WOOD[2], 'h': WOOD[3]}


def dummy_sprite():
    im = Image.new('RGBA', (16, 22))
    for y, row in enumerate(DUMMY_ROWS):
        for x, c in enumerate(row):
            if c != '.':
                im.putpixel((x, y), CMAP[c])
    return im


def silhouette(spr, col):
    out = Image.new('RGBA', spr.size)
    px, po = spr.load(), out.load()
    for y in range(spr.height):
        for x in range(spr.width):
            if px[x, y][3] > 0:
                po[x, y] = col
    return out


class Canvas:
    """Opaque pixel canvas implementing the telegraph_lib canvas protocol: put(x, y, rgba)."""
    def __init__(self, bg):
        self.im = bg.copy()
        self.drawn = set()      # telegraph pixels of this frame (for the warning==hitbox check)
        self.track = False

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.im.width and 0 <= y < self.im.height:
            self.im.putpixel((x, y), c)
        if self.track:
            self.drawn.add((x, y))

    def blit(self, spr, x, y):
        tmp = Image.new('RGBA', self.im.size)
        tmp.paste(spr, (int(round(x)), int(round(y))))
        self.im.alpha_composite(tmp)


class Scene:
    def __init__(self, spec):
        cv = spec.get('canvas', {})
        self.W, self.H = cv.get('width', 160), cv.get('height', 96)
        self.scale = cv.get('scale', 3)
        self.grass = Image.open(os.path.join(ASSETS, 'grass_tiles.png')).convert('RGBA')
        self.ninja = Image.open(os.path.join(ASSETS, 'ninja_blue.png')).convert('RGBA')
        self.shadow = Image.open(os.path.join(ASSETS, 'shadow.png')).convert('RGBA')
        c = spec.get('caster', {})
        self.caster = (int(c.get('x', 48)), int(c.get('y', self.H // 2)))
        sp = c.get('sprite', 'wooden_dummy')
        if sp == 'wooden_dummy':
            self.caster_img = dummy_sprite()
        else:  # path to a 16x16 sprite sheet (first frame used), relative to the spec file
            self.caster_img = Image.open(sp).convert('RGBA').crop((0, 0, 16, 16))
        self.bg = self._bg()
        try:
            self.font = ImageFont.load_default(size=10)
        except TypeError:
            self.font = ImageFont.load_default()

    def _bg(self):
        rnd = random.Random(7)
        tiles = [self.grass.crop((i * 16, 0, i * 16 + 16, 16)) for i in range(5)]
        bg = Image.new('RGBA', (self.W, self.H))
        for ty in range(0, self.H, 16):
            for tx in range(0, self.W, 16):
                bg.paste(tiles[0] if rnd.random() < 0.55 else rnd.choice(tiles[1:]), (tx, ty))
        px = bg.load()   # darken + desaturate so red warnings read clearly
        for y in range(self.H):
            for x in range(self.W):
                r, g, b, a = px[x, y]
                m = (r + g + b) / 3
                px[x, y] = tuple(int((v * .6 + m * .4) * .55) for v in (r, g, b)) + (255,)
        return bg

    def draw_caster(self, cv, flash=False):
        x, y = self.caster
        cv.blit(self.shadow, x - 6, y + 6)
        spr = silhouette(self.caster_img, WHITE) if flash else self.caster_img
        cv.blit(spr, x - spr.width // 2, y - spr.height + 9)

    def draw_target(self, cv, pos, flash=False, row=0):
        x, y = pos
        cv.blit(self.shadow, x - 6, y + 4)
        spr = self.ninja.crop((0, row * 16, 16, row * 16 + 16))
        if flash:
            spr = silhouette(spr, WHITE)
        cv.blit(spr, x - 8, y - 9)

    def finish(self, cv, lines):
        big = cv.im.convert('RGB').resize((self.W * self.scale, self.H * self.scale), Image.NEAREST)
        bar = Image.new('RGB', (big.width, 30), (18, 16, 14))
        d = ImageDraw.Draw(bar)
        for i, (txt, col) in enumerate(lines):
            d.text((6, 3 + i * 13), txt, fill=col, font=self.font)
        out = Image.new('RGB', (big.width, big.height + bar.height))
        out.paste(big, (0, 0))
        out.paste(bar, (0, big.height))
        return out


def lerp_path(path, k):
    if not path:
        return None
    if len(path) == 1:
        return tuple(path[0])
    k = max(0.0, min(1.0, k)) * (len(path) - 1)
    i = min(int(k), len(path) - 2)
    f = k - i
    (x0, y0), (x1, y1) = path[i], path[i + 1]
    return (int(round(x0 + (x1 - x0) * f)), int(round(y0 + (y1 - y0) * f)))


def render_attack(scene, atk):
    tp = dict(atk['telegraph'])
    if tp.get('overlay') == 'cracks':
        tp['overlay'] = T.CrackOverlay(seed=3)
    elif 'overlay' in tp:
        tp.pop('overlay')
    label = atk.get('label', atk.get('id', 'attack'))
    path = atk.get('target', {}).get('path', [[scene.caster[0] + 40, scene.caster[1]]])
    idle_f, rec_f = 9, max(T.frames_of(atk.get('recovery', 0.2)), 6)
    proj = atk.get('projectile')
    proj_f = T.frames_of(proj.get('time', 0.4)) if proj else 0
    dur_f = T.frames_of(tp.get('duration', 1.0))
    total = idle_f + dur_f + 1 + proj_f + rec_f + 6
    tgt0 = lerp_path(path, 0)
    feet = lambda p: (p[0], p[1] + 5)
    tel = None
    frames, outside, hit_flash, hit_count = [], 0, 0, 0
    thorn = None
    for f in range(total):
        k = f / max(total - 1, 1)
        tgt = lerp_path(path, k)
        cv = Canvas(scene.bg)
        phase, col = 'idle', (150, 150, 150)
        lf = f - idle_f
        if 0 <= lf <= dur_f:
            if tel is None:
                tel = T.Telegraph(tp, scene.caster, tgt)
            ev = tel.update(lf / FPS, scene.caster, tgt)
            cv.track = True
            tel.draw(cv, lf / FPS, lf)
            cv.track = False
            if tel.locked:
                outside += len(cv.drawn - tel.cells)
            phase, col = ('warning', (232, 112, 95)) if lf < dur_f else ('HIT', (255, 255, 255))
            if 'hit' in ev:
                if proj:
                    thorn = dict(x=scene.caster[0] + .5, y=scene.caster[1] + .5, a=tel.ang, left=proj_f,
                                 step=tel.p['length'] / max(proj_f, 1), turn=math.radians(proj.get('turn_deg_per_s', 270)) / FPS)
                elif tel.contains(feet(tgt)):
                    hit_flash, hit_count = 6, hit_count + 1
        elif lf > dur_f:
            phase, col = ('recovery', (241, 196, 15))
        if thorn and thorn['left'] > 0:
            want = math.atan2(tgt[1] - thorn['y'], tgt[0] - thorn['x'])
            d = T._wrap(want - thorn['a'])
            thorn['a'] += max(-thorn['turn'], min(thorn['turn'], d))
            thorn['x'] += math.cos(thorn['a']) * thorn['step']
            thorn['y'] += math.sin(thorn['a']) * thorn['step']
            thorn['left'] -= 1
            for i in range(4):
                cv.put(thorn['x'] - math.cos(thorn['a']) * i, thorn['y'] - math.sin(thorn['a']) * i, WOOD[3] if i < 2 else WOOD[1])
            if math.hypot(tgt[0] - thorn['x'], tgt[1] + 2 - thorn['y']) < 5:
                hit_flash, hit_count, thorn['left'] = 6, hit_count + 1, 0
            phase, col = 'projectile', (255, 255, 255)
        scene.draw_caster(cv, flash=(lf == dur_f))
        scene.draw_target(cv, tgt, flash=hit_flash > 0 and hit_flash % 2 == 0)
        hit_flash = max(0, hit_flash - 1)
        t_txt = f't={max(lf, 0) / FPS:.2f}s' if lf >= 0 else 't=0.00s'
        frames.append(scene.finish(cv, [(f'{label}', (201, 183, 156)), (f'{phase}  {t_txt}  hits={hit_count}', col)]))
    return frames, outside


def save_gif(frames, path):
    # one shared palette for the whole GIF (pixel art has few colours) -> small files, no flicker
    step = max(1, len(frames) // 12)
    sample = frames[::step]
    sheet = Image.new('RGB', (sample[0].width, sample[0].height * len(sample)))
    for i, fr in enumerate(sample):
        sheet.paste(fr, (0, i * fr.height))
    pal = sheet.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = [fr.quantize(palette=pal, dither=Image.Dither.NONE) for fr in frames]
    out[0].save(path, save_all=True, append_images=out[1:], duration=33, loop=0, optimize=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('spec', help='JSON spec file')
    ap.add_argument('-o', '--out', default='preview_out', help='output folder')
    ap.add_argument('--only', help='render only this attack id')
    a = ap.parse_args()
    with open(a.spec, encoding='utf-8') as fh:
        spec = json.load(fh)
    os.makedirs(a.out, exist_ok=True)
    scene = Scene(spec)
    allf, bad = [], 0
    for atk in spec['attacks']:
        if a.only and atk.get('id') != a.only:
            continue
        frames, outside = render_attack(scene, atk)
        dst = os.path.join(a.out, f"{atk.get('id', 'attack')}.gif")
        save_gif(frames, dst)
        allf += frames
        bad += outside
        print(f"{dst}: {len(frames)} frames, pixels drawn outside hitbox after lock = {outside}")
    if len(allf) and not a.only:
        save_gif(allf, os.path.join(a.out, 'all.gif'))
        print(os.path.join(a.out, 'all.gif'))
    if bad:
        print('ERROR: warning drawn outside the hitbox', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
