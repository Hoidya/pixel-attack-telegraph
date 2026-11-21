# -*- coding: utf-8 -*-
"""Pixel-art attack telegraph reference implementation (Python + Pillow).

Core ideas:
  * One params dict drives BOTH the drawn warning and the damage hitbox: both come from Telegraph.cells (a pixel set).
  * shape: fan / circle / ring / rect / ray (defaults) or custom (tile mask, polygon, and/or union of default shapes).
  * style: standard fill / quick flash / aim line / countdown (fill from shape centre) / themed (standard + overlay).
  * Pixel rules: integer pixels, opaque colours only; fades use 4x4 Bayer ordered dither, never alpha gradients or blur.

Canvas protocol: any object with put(x, y, rgba) works as a canvas (rgba = 0-255 tuple, opaque).

Usage:
    tel = Telegraph(params, caster=(18, 40), target=(60, 41))
    for frame in range(n):
        t = frame / FPS
        events = tel.update(t, caster, target)   # -> ['warning_started'] / ['locked'] / ['hit']
        tel.draw(canvas, t, frame)
        if 'hit' in events: damage if tel.contains(player_feet)
"""
import math, random

FPS = 30
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

def hx(s, a=255):
    s = s.lstrip('#'); return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)

# Colour roles: damage = default red; control = blue (reserved for knockback / crowd control).
ROLE_COLORS = {
    'damage':  dict(edge_dark=hx('2b0a08'), main=hx('c0392b'), hi=hx('e8705f'), flash=hx('f6d2c4'), white=hx('ffffff')),
    'control': dict(edge_dark=hx('0a1830'), main=hx('3a7bd5'), hi=hx('8ab8f0'), flash=hx('d6e8ff'), white=hx('ffffff')),
}

# Palettes: damage = default red; control = reserved blue (opt-in, unused by the wooden-dummy example);
# mixed = purple; support = teal. color_role 'auto' (default) follows category; explicit
# damage/control/custom overrides it.
PALETTES = {
    'damage':  ROLE_COLORS['damage'],
    'control': ROLE_COLORS['control'],
    'mixed':   dict(edge_dark=hx('1a0828'), main=hx('8e3ac5'), hi=hx('c084e8'), flash=hx('e8d2f6'), white=hx('ffffff')),
    'support': dict(edge_dark=hx('082418'), main=hx('2a9d6e'), hi=hx('7dceb0'), flash=hx('d2f0e4'), white=hx('ffffff')),
}

def resolved_colors(p):
    """Pick a palette: custom_colors / explicit color_role win; otherwise category."""
    role = p.get('color_role') or 'auto'
    custom = p.get('custom_colors')
    if role == 'custom' and custom and len(custom) >= 5:
        def _c(v):
            return hx(v) if isinstance(v, str) else tuple(v)
        keys = ('edge_dark', 'main', 'hi', 'flash', 'white')
        return dict(zip(keys, (_c(v) for v in custom[:5])))
    if role in ('damage', 'control'):
        return PALETTES[role]
    cat = p.get('category') or 'damage'
    return PALETTES.get(cat, PALETTES['damage'])

DEFAULTS = dict(
    shape='fan',          # fan | circle | ring | rect | ray | custom
    radius=48,            # fan / circle / ring outer radius (px)
    inner_radius=0,       # ring inner radius (px)
    length=64,            # rect / ray length (px)
    width=16,             # rect / ray width (px)
    angle=60,             # fan opening angle (deg)
    direction=None,       # fixed facing (deg, 0=right, 90=down); None = face the target
    anchor='caster',      # caster: starts at caster | target: centred on target position (rounded) at warning start
    duration=1.0,         # warning time = start to hit (s)
    fill_mode=None,       # outward_from_caster | outward_from_shape_center | none ; None = style default
    style='standard',     # standard | quick | aim | countdown | themed
    track_time=0.0,       # >0: facing follows the target for track_time s, then locks
    color_role='auto',    # auto (follow category) | damage | control | custom
    category='damage',    # damage | control | mixed | support  (picks the default palette)
    custom_colors=None,   # optional 5 colours when color_role=custom: edge, main, hi, flash, white
    tile_mask=None,       # custom: list of strings, '#' filled, '.' empty, '@'/'o' filled origin cell
    tile_size=16,         # custom tile mask: pixels per tile
    tile_anchor=None,     # custom: origin in tile units from mask top-left; None + no '@' = mask centre
    custom_polygon=None,  # custom: list of [x,y] px relative to the origin, rotated by facing
    custom_union=None,    # custom: list of default-shape dicts, unioned (optional offset, direction)
    overlay=None,         # themed overlay object with draw(canvas, tel, prog, frame)
)
STYLE_FILL = dict(standard='outward_from_caster', themed='outward_from_caster',
                  countdown='outward_from_shape_center', quick='none', aim='none')

def frames_of(sec, fps=FPS):
    """seconds -> frames (rounded). All timing is frame-quantised."""
    return int(round(sec * fps))

# ---------------------------------------------------------------- geometry
def _wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi

def _on_segment(px, py, ax, ay, bx, by, eps=1e-6):
    """True if (px,py) lies on the segment a-b (inclusive)."""
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if abs(cross) > 1e-6:
        return False
    dot = (px - ax) * (bx - ax) + (py - ay) * (by - ay)
    if dot < -eps:
        return False
    length2 = (bx - ax) ** 2 + (by - ay) ** 2
    return dot - length2 <= eps

def point_in_polygon(px, py, verts):
    """Pixel-centre test: inside or on the boundary of a polygon (vertices [x,y] or (x,y))."""
    n = len(verts)
    if n < 3:
        return False
    j = n - 1
    inside = False
    for i in range(n):
        xi, yi = verts[i][0], verts[i][1]
        xj, yj = verts[j][0], verts[j][1]
        if _on_segment(px, py, xi, yi, xj, yj):
            return True
        if (yi > py) != (yj > py):
            xint = (xj - xi) * (py - yi) / (yj - yi) + xi
            if px < xint:
                inside = not inside
        j = i
    return inside

def parse_tile_mask(mask, tile_size=16, tile_anchor=None):
    """Return (tiles, anchor) where tiles is a list of (tx, ty) occupied cells and
    anchor is (ax, ay) in tile units from the top-left corner of the mask.
    '#' = filled, '.' or space = empty, '@' or 'o'/'O' = filled origin (cell centre).
    If no '@' is present, tile_anchor is used; if that is also None, the mask centre."""
    rows = list(mask or [])
    h = len(rows)
    w = max((len(r) for r in rows), default=0)
    tiles = []
    marked = None
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in ' .':
                continue
            tiles.append((x, y))
            if ch in '@oO' and marked is None:
                marked = (x + 0.5, y + 0.5)
    if marked is not None:
        anchor = marked
    elif tile_anchor is not None:
        ax, ay = (tile_anchor[0], tile_anchor[1]) if not isinstance(tile_anchor, (int, float)) else (tile_anchor, tile_anchor)
        anchor = (float(ax), float(ay))
    else:
        anchor = (w / 2.0, h / 2.0)
    return tiles, anchor, tile_size

def _cardinal_cs(ang):
    """Exact cos/sin for 0/90/180/270 (and 360==0) so tile masks stay stable."""
    d = math.fmod(math.degrees(ang), 360.0)
    if d < 0:
        d += 360.0
    if d < 1e-6 or d > 360.0 - 1e-6:
        return 1.0, 0.0
    if abs(d - 90.0) < 1e-6:
        return 0.0, 1.0
    if abs(d - 180.0) < 1e-6:
        return -1.0, 0.0
    if abs(d - 270.0) < 1e-6:
        return 0.0, -1.0
    return math.cos(ang), math.sin(ang)

def _in_half_open(lx, ly, x0, y0, x1, y1, eps=1e-9):
    return x0 <= lx + eps and lx < x1 and y0 <= ly + eps and ly < y1

def _custom_cells(p, origin, ang):
    """Custom shape: union of a tile mask, a polygon, and/or default shapes. Same pixel set
    is used for drawing and the hitbox. Countdown fill uses the origin (anchor) as centre."""
    ox, oy = origin
    ca, sa = _cardinal_cs(ang)
    cells = set()
    ts = int(p.get('tile_size') or 16)
    tiles, anchor, _ = parse_tile_mask(p.get('tile_mask') or [], ts, p.get('tile_anchor'))
    rects = []
    for tx, ty in tiles:
        rects.append((tx * ts - anchor[0] * ts, ty * ts - anchor[1] * ts,
                      (tx + 1) * ts - anchor[0] * ts, (ty + 1) * ts - anchor[1] * ts))
    poly = p.get('custom_polygon') or p.get('polygon') or []
    xs, ys = [], []
    for x0, y0, x1, y1 in rects:
        for lx, ly in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
            xs.append(ox + lx * ca - ly * sa)
            ys.append(oy + lx * sa + ly * ca)
    for v in poly:
        lx, ly = v[0], v[1]
        xs.append(ox + lx * ca - ly * sa)
        ys.append(oy + lx * sa + ly * ca)
    if xs:
        minx, maxx = int(math.floor(min(xs))) - 2, int(math.ceil(max(xs))) + 2
        miny, maxy = int(math.floor(min(ys))) - 2, int(math.ceil(max(ys))) + 2
        for y in range(miny, maxy + 1):
            for x in range(minx, maxx + 1):
                dx = (x + 0.5) - (ox + 0.5)
                dy = (y + 0.5) - (oy + 0.5)
                lx = dx * ca + dy * sa
                ly = -dx * sa + dy * ca
                hit = False
                for x0, y0, x1, y1 in rects:
                    if _in_half_open(lx, ly, x0, y0, x1, y1):
                        hit = True
                        break
                if not hit and poly and point_in_polygon(lx, ly, poly):
                    hit = True
                if hit:
                    cells.add((x, y))
    for part in (p.get('custom_union') or []):
        sub = dict(DEFAULTS)
        # do not inherit the parent custom fields
        for k in ('tile_mask', 'custom_polygon', 'polygon', 'custom_union', 'tile_anchor'):
            sub[k] = None
        sub.update({k: v for k, v in part.items() if k not in ('offset',)})
        off = part.get('offset') or (0, 0)
        ox2 = ox + off[0] * ca - off[1] * sa
        oy2 = oy + off[0] * sa + off[1] * ca
        part_ang = ang + math.radians(float(part.get('direction', 0) or 0))
        sub_cells, _, _ = shape_cells(sub, (int(round(ox2)), int(round(oy2))), part_ang)
        cells |= sub_cells
    center = (ox + 0.5, oy + 0.5)
    return cells, center, dict(kind='custom', base=center)

def shape_cells(p, origin, ang):
    """Return (cells, center, geo). cells: set of pixel coords; ang: facing (rad).
    Pixels are tested at their centre (x+.5, y+.5), so shapes are deterministic on the pixel grid."""
    if p.get('shape') == 'custom':
        return _custom_cells(p, origin, ang)
    ox, oy = origin
    shape = p['shape']
    cells = set()
    ca, sa = math.cos(ang), math.sin(ang)
    if shape in ('fan', 'circle', 'ring'):
        r = p['radius']; ri = p['inner_radius'] if shape == 'ring' else 0
        bx, by = ox + 0.5, oy + 0.5
        half = math.radians(p['angle']) / 2
        for y in range(int(oy - r - 2), int(oy + r + 3)):
            for x in range(int(ox - r - 2), int(ox + r + 3)):
                dx, dy = x + 0.5 - bx, y + 0.5 - by
                d = math.hypot(dx, dy)
                if d > r + 0.01 or (shape == 'ring' and d <= ri):
                    continue
                if shape == 'fan' and d >= 1.5 and abs(_wrap(math.atan2(dy, dx) - ang)) > half + 1e-9:
                    continue
                cells.add((x, y))
        if shape == 'fan':
            cx = sum(c[0] + 0.5 for c in cells) / len(cells); cy = sum(c[1] + 0.5 for c in cells) / len(cells)
            center = (cx, cy)
        else:
            center = (bx, by)
        geo = dict(kind=shape, base=(bx, by), r=r, ri=ri)
    else:  # rect / ray: oriented rectangle; a ray is a thin rect
        L, Wd = p['length'], p['width']
        centered = p['anchor'] == 'target'
        bx, by = ox + 0.5, oy + 0.5
        nx, ny = -sa, ca                      # perpendicular
        if Wd % 2 == 0: bx -= nx * 0.5; by -= ny * 0.5   # even width: centre line on a pixel edge
        if centered and L % 2 == 0: bx -= ca * 0.5; by -= sa * 0.5
        u0, u1 = (-L / 2, L / 2) if centered else (0, L)
        ext = L + Wd + 2
        for y in range(int(oy - ext), int(oy + ext + 1)):
            for x in range(int(ox - ext), int(ox + ext + 1)):
                dx, dy = x + 0.5 - bx, y + 0.5 - by
                u = dx * ca + dy * sa; v = dx * nx + dy * ny
                inside_u = (u0 - 1e-9 <= u < u1) if not centered else (abs(u) < L / 2 - 1e-9 or (abs(u) <= L / 2 and L % 2))
                inside_v = (abs(v) < Wd / 2 - 1e-9) if Wd % 2 == 0 else (abs(v) <= Wd / 2)
                if inside_u and inside_v:
                    cells.add((x, y))
        um = (u0 + u1) / 2
        center = (bx + ca * um, by + sa * um)
        geo = dict(kind=shape, base=(bx, by), u0=u0, u1=u1, L=L, W=Wd, ca=ca, sa=sa, nx=nx, ny=ny)
    return cells, center, geo

def border_of(cells):
    n4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
    return {c for c in cells if any((c[0] + dx, c[1] + dy) not in cells for dx, dy in n4)}

# ---------------------------------------------------------------- telegraph
class Telegraph:
    def __init__(self, params, caster, target=None):
        p = dict(DEFAULTS); p.update(params)
        if p['fill_mode'] is None: p['fill_mode'] = STYLE_FILL[p['style']]
        self.p = p
        self.col = resolved_colors(p)
        self.dur_f = frames_of(p['duration'])
        self.track_f = frames_of(p['track_time'])
        self.caster = caster
        self.origin = (int(round(target[0])), int(round(target[1]))) if p['anchor'] == 'target' else caster
        self.ang = self._aim(caster, target)
        self.locked = self.track_f <= 0
        self._cache = {}
        self._fired = set()
        self._build()

    # ---- direction / tracking
    def _aim(self, caster, target):
        if self.p['direction'] is not None:
            return math.radians(self.p['direction'])
        if target is None or self.p['anchor'] == 'target' and self.p['shape'] in ('circle', 'ring', 'rect', 'custom'):
            return 0.0
        return math.atan2(target[1] - caster[1], target[0] - caster[0])

    def _build(self):
        # quantise to 1 deg: fewer rebuilds, no pixel shimmer
        key = round(math.degrees(self.ang))
        if key not in self._cache:
            a = math.radians(key)
            cells, center, geo = shape_cells(self.p, self.origin, a)
            self._cache[key] = self._prep(cells, center, geo, a)
        self.cells, self.border, self.inner_border, self.metric, self.front_w, self.center, self.geo = self._cache[key]

    def _prep(self, cells, center, geo, a):
        bd = border_of(cells)
        ib = border_of(cells - bd)
        fm = self.p['fill_mode']
        metric = {}
        if fm != 'none':
            if fm == 'outward_from_caster':
                fx, fy = self.caster[0] + 0.5, self.caster[1] + 0.5
                raw = {c: math.hypot(c[0] + .5 - fx, c[1] + .5 - fy) for c in cells}
            else:
                cx, cy = center
                if geo['kind'] == 'rect':      # rect: grows from its centre as a square
                    hl, hw = geo['L'] / 2, geo['W'] / 2
                    def m(c):
                        dx, dy = c[0] + .5 - cx, c[1] + .5 - cy
                        return max(abs(dx * geo['ca'] + dy * geo['sa']) / hl, abs(dx * geo['nx'] + dy * geo['ny']) / hw)
                    raw = {c: m(c) for c in cells}
                elif geo['kind'] == 'ring':    # ring: from inner edge to outer edge
                    raw = {c: math.hypot(c[0] + .5 - cx, c[1] + .5 - cy) - geo['ri'] for c in cells}
                else:
                    raw = {c: math.hypot(c[0] + .5 - cx, c[1] + .5 - cy) for c in cells}
            lo, hi = min(raw.values()), max(raw.values())
            span = max(hi - lo, 1e-6)
            metric = {c: (v - lo) / span for c, v in raw.items()}
            # fill front is ~2.5 px wide (in 0..1 units)
            px_span = span if fm != 'outward_from_shape_center' or geo['kind'] != 'rect' else min(geo['L'], geo['W']) / 2
            front_w = 2.5 / max(px_span, 1)
        else:
            front_w = 0
        return cells, bd, ib, metric, front_w, center, geo

    # ---- per-frame
    def update(self, t, caster=None, target=None):
        """Advance; return events fired this frame: warning_started / locked / hit (each once)."""
        f = frames_of(t)
        ev = []
        def once(name):
            if name not in self._fired: self._fired.add(name); ev.append(name)
        if f >= 0: once('warning_started')
        if caster is not None and self.p['anchor'] == 'caster': self.caster = caster; self.origin = caster
        if not self.locked:
            if f < self.track_f and target is not None:
                self.ang = self._aim(self.caster, target); self._build()
            elif f >= self.track_f:
                self.locked = True; once('locked')
        if f >= self.dur_f: once('hit')
        return ev

    def contains(self, pt):
        """Hit test: uses the very same pixel set that is drawn."""
        return (int(math.floor(pt[0])), int(math.floor(pt[1]))) in self.cells

    def progress(self, t):
        return max(0.0, min(1.0, frames_of(t) / max(self.dur_f, 1)))

    def draw(self, cv, t, frame=None):
        f = frames_of(t)
        frame = f if frame is None else frame
        if f < 0 or f > self.dur_f:       # gone right after the hit frame
            return
        if f == self.dur_f:
            return self._draw_hit(cv)
        prog = f / self.dur_f
        st = self.p['style']
        if st == 'aim':
            return self._draw_aim(cv, prog, f)
        if st == 'quick':
            return self._draw_quick(cv, prog, f)
        self._draw_standard(cv, prog, f)
        if st == 'themed' and self.p['overlay'] is not None:
            self.p['overlay'].draw(cv, self, prog, f)

    # ---- styles
    def _outline(self, cv, flash_on):
        c = self.col
        for (x, y) in self.border:
            cv.put(x, y, c['white'] if flash_on else c['edge_dark'])
        for (x, y) in self.inner_border:
            cv.put(x, y, c['hi'] if flash_on else c['main'])

    def _end_flash(self, prog, f):
        """3 flashes during the last 20% (bright/dark alternate, frame-quantised)."""
        if prog < 0.8: return False
        k = int((prog - 0.8) / 0.2 * 6)
        return k % 2 == 0

    def _draw_standard(self, cv, prog, f):
        c = self.col
        skip = self.border | self.inner_border
        fw = self.front_w
        for (x, y) in self.cells:
            if (x, y) in skip: continue
            b = BAYER[y % 4][x % 4]
            m = self.metric.get((x, y), 2)
            if m <= prog and m > prog - fw and prog < 1:
                if b < 12: cv.put(x, y, c['hi'])          # advancing front: bright, dense
            elif m <= prog:
                if b < 7: cv.put(x, y, c['main'])         # filled: medium density
            else:
                if b < 2: cv.put(x, y, c['main'])         # not yet filled: very sparse dither
        self._outline(cv, self._end_flash(prog, f))

    def _draw_quick(self, cv, prog, f):
        c = self.col
        # outline + flashes only: every 2 frames in the first half, every frame after
        period = 2 if prog < 0.5 else 1
        on = (f // period) % 2 == 1
        self._outline(cv, on)
        if on:
            for (x, y) in self.cells:
                if (x, y) not in self.border and (x, y) not in self.inner_border and BAYER[y % 4][x % 4] < 3:
                    cv.put(x, y, c['main'])

    def _ray_uv(self, x, y):
        g = self.geo; dx, dy = x + .5 - g['base'][0], y + .5 - g['base'][1]
        return dx * g['ca'] + dy * g['sa'], dx * g['nx'] + dy * g['ny']

    def _draw_aim(self, cv, prog, f):
        c = self.col
        g = self.geo
        L = g['L']
        lock_flash = self.locked and f - self.track_f in (0, 1)
        for (x, y) in self.cells:
            u, v = self._ray_uv(x, y)
            core = abs(v) <= 0.5
            if not self.locked:
                # tracking: 1 px dashed line flowing forward
                if core and (int(u) - f) % 4 < 2:
                    cv.put(x, y, c['main'])
            else:
                # locked: thicker and brighter; 2-frame white flash on lock
                if core: cv.put(x, y, c['white'] if lock_flash else c['hi'])
                else: cv.put(x, y, c['hi'] if lock_flash else c['main'])
        # a bright dot travels from caster to tip over the whole warning
        u_dot = prog * (L - 1)
        bx, by = g['base']
        for i, col in ((0, c['white']), (1, c['white']), (2, c['hi']), (3, c['hi']), (4, c['main'])):
            uu = u_dot - i
            if uu < 0: break
            cv.put(int(math.floor(bx + g['ca'] * uu)), int(math.floor(by + g['sa'] * uu)), col)
        # small cross marks max range
        ex, ey = int(math.floor(bx + g['ca'] * (L - 1))), int(math.floor(by + g['sa'] * (L - 1)))
        tip = c['hi'] if self.locked else c['main']
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (ex + dx, ey + dy) in self.cells:      # only inside the hitbox
                cv.put(ex + dx, ey + dy, tip)

    def _draw_hit(self, cv):
        """Hit frame: whole area flashes for 1 frame, then disappears."""
        c = self.col
        for (x, y) in self.cells:
            if (x, y) in self.border: cv.put(x, y, c['white'])
            elif (x + y) % 2 == 0: cv.put(x, y, c['flash'])
            else: cv.put(x, y, c['hi'])

# ---------------------------------------------------------------- themed overlay
class CrackOverlay:
    """Example themed overlay: ground cracks grow from the caster with progress, clipped to the hitbox."""
    def __init__(self, seed=0, n_main=3, dark=hx('1c1d0e'), lit=hx('6b5a4a')):
        self.seed, self.n_main, self.dark, self.lit = seed, n_main, dark, lit
        self._pts = None; self._key = None

    def build(self, tel):
        key = (tuple(sorted(tel.cells))[:1], len(tel.cells), round(tel.ang, 3))
        if self._key == key: return self._pts
        rnd = random.Random(self.seed)
        ox, oy = tel.caster
        p = tel.p; r = p.get('radius', 48)
        half = math.radians(p.get('angle', 360)) / 2 if p['shape'] == 'fan' else math.pi
        pts = {}
        def walk(x, y, a, length, depth):
            d0 = math.hypot(x - ox, y - oy)
            steps = 0
            while steps < length:
                a += rnd.uniform(-0.35, 0.35)
                nx, ny = x + math.cos(a) * 2, y + math.sin(a) * 2
                for q in _line(x, y, nx, ny):
                    if q in tel.cells and q not in pts:
                        pts[q] = math.hypot(q[0] - ox, q[1] - oy)
                x, y = nx, ny; steps += 2
                if depth < 1 and rnd.random() < 0.12:
                    walk(x, y, a + rnd.choice([-1, 1]) * rnd.uniform(0.5, 0.9), rnd.randint(5, 10), depth + 1)
        for i in range(self.n_main):
            k = 0 if self.n_main == 1 else (i / (self.n_main - 1) - 0.5)
            a = tel.ang + k * 2 * half * 0.75
            walk(ox + math.cos(a) * 9, oy + math.sin(a) * 9, a, r - 9, 0)
        self._pts, self._key = pts, key
        self.maxd = max(pts.values()) if pts else 1
        return pts

    def draw(self, cv, tel, prog, frame, fade=0.0, full=False):
        pts = self.build(tel)
        lim = self.maxd if full else 9 + (self.maxd - 9) * prog
        for (x, y), d in pts.items():
            if d <= lim and BAYER[y % 4][x % 4] >= fade * 16:
                cv.put(x, y, self.dark)
                if (x, y + 1) not in pts: cv.put(x, y + 1, self.lit) if (x, y + 1) in tel.cells else None

def _line(x0, y0, x1, y1):
    x0, y0, x1, y1 = (int(math.floor(v)) for v in (x0, y0, x1, y1))
    pts = []; dx = abs(x1 - x0); dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1; sy = 1 if y0 < y1 else -1; err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1: break
        e2 = 2 * err
        if e2 >= dy: err += dy; x0 += sx
        if e2 <= dx: err += dx; y0 += sy
    return pts

# ---------------------------------------------------------------- self-check
class PixelRecorder:
    """Records drawn pixels to prove warning == hitbox."""
    def __init__(self): self.px = set()
    def put(self, x, y, c): self.px.add((int(x), int(y)))

def frames_within_mask(params, caster, target_fn):
    """Draw the whole warning; return number of pixels drawn outside the hitbox after lock (should be 0)."""
    tel = Telegraph(params, caster, target_fn(0)); bad = set()
    for f in range(tel.dur_f + 1):
        tel.update(f / FPS, caster, target_fn(f)); rec = PixelRecorder(); tel.draw(rec, f / FPS)
        if tel.locked: bad |= rec.px - tel.cells
    return len(bad)

def coverage_check(tel):
    """Draw the hit frame; return (extra pixels, missing pixels) vs. the hitbox."""
    rec = PixelRecorder(); tel._draw_hit(rec)
    return len(rec.px - tel.cells), len(tel.cells - rec.px)
