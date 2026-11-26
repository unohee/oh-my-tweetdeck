# Created: 2026-11-25
# Purpose: Emit a traced SVG of the omt logo (smooth bezier outlines + sampled gradients).
# Dependencies: numpy, scipy, Pillow
# Test Status: exploratory
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

src = Image.open("../omt-logo.jpg").convert("RGB")
im = np.asarray(src).astype(float)
hsv = np.asarray(src.convert("HSV")).astype(float)
sat, val = hsv[..., 1], hsv[..., 2]
H, W, _ = im.shape
yy, xx = np.mgrid[0:H, 0:W]
fig = np.load("/tmp/m_fig.npy")
dark = np.load("/tmp/m_dark.npy")

def biggest(m):
    l, n = ndi.label(m)
    return l == (1 + int(np.argmax(ndi.sum(m, l, range(1, n + 1)))))

# Colour arms: anything in the figure that is clearly not white-ish, split left/right.
col = fig & ((sat > 45) | (val < 200)) & ~dark
col = ndi.binary_opening(col, iterations=7)
def blobs(m, min_px=2500):
    l, n = ndi.label(m)
    sz = ndi.sum(m, l, range(1, n + 1))
    return np.isin(l, [i + 1 for i, z in enumerate(sz) if z >= min_px])
left = blobs(col & (xx < 512))
right = blobs(col & (xx >= 512))
left = ndi.binary_fill_holes(ndi.binary_closing(left, iterations=2))
right = ndi.binary_fill_holes(ndi.binary_closing(right, iterations=3))

def trace(mask):
    """Boundary of the largest blob as an ordered pixel loop (Moore tracing)."""
    m = np.pad(mask, 1)
    ys, xs = np.nonzero(m)
    start = (ys.min(), xs[ys == ys.min()].min())
    nb = [(-1,0),(-1,1),(0,1),(1,1),(1,0),(1,-1),(0,-1),(-1,-1)]
    pts = [start]; cur = start; d = 6
    while True:
        for k in range(8):
            i = (d + k) % 8
            ny, nx = cur[0] + nb[i][0], cur[1] + nb[i][1]
            if m[ny, nx]:
                cur = (ny, nx); d = (i + 6) % 8; break
        else:
            break
        if cur == start and len(pts) > 2: break
        pts.append(cur)
        if len(pts) > 200000: break
    return np.array([(x - 1, y - 1) for y, x in pts], float)

def smooth(p, k):
    n = len(p); out = np.zeros_like(p)
    for s in range(-k, k + 1):
        out += np.roll(p, s, axis=0)
    return out / (2 * k + 1)

def rdp(p, eps):
    if len(p) < 3: return p
    a, b = p[0], p[-1]
    ab = b - a; L = np.hypot(*ab)
    d = np.abs(np.cross(ab, p - a)) / L if L else np.hypot(*(p - a).T)
    i = int(np.argmax(d))
    if d[i] > eps:
        return np.vstack([rdp(p[:i + 1], eps)[:-1], rdp(p[i:], eps)])
    return np.array([a, b])

def bezier_path(mask, sm=6, eps=1.6):
    p = smooth(trace(mask), sm)
    # simplify the closed loop (split at farthest point from start)
    j = int(np.argmax(np.hypot(*(p - p[0]).T)))
    q = np.vstack([rdp(p[:j + 1], eps)[:-1], rdp(np.vstack([p[j:], p[:1]]), eps)[:-1]])
    n = len(q); d = [f"M{q[0][0]:.1f},{q[0][1]:.1f}"]
    for i in range(n):  # Catmull-Rom -> cubic bezier
        p0, p1, p2, p3 = q[i - 1], q[i], q[(i + 1) % n], q[(i + 2) % n]
        c1 = p1 + (p2 - p0) / 6; c2 = p2 - (p3 - p1) / 6
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    return " ".join(d) + "Z"

def multi_path(mask, sm=4, eps=1.6, min_px=2500):
    l, n = ndi.label(mask)
    parts = []
    for i in range(1, n + 1):
        b = l == i
        if b.sum() >= min_px: parts.append(bezier_path(b, sm=sm, eps=eps))
    return " ".join(parts)

def ellipse(mask):
    ys, xs = np.nonzero(mask)
    return xs.mean(), ys.mean(), (xs.max() - xs.min() + 1) / 2, (ys.max() - ys.min() + 1) / 2

def hexc(c): return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)

def grad(mask, axis, stops=5):
    """Colour samples along the mask's principal axis, as SVG gradient stops."""
    mask = ndi.binary_erosion(mask, iterations=4)
    ys, xs = np.nonzero(mask)
    t = (xs - xs.mean()) * axis[0] + (ys - ys.mean()) * axis[1]
    lo, hi = t.min(), t.max()
    out = []
    for k in range(stops):
        a = lo + (hi - lo) * k / (stops - 1)
        sel = np.abs(t - a) < (hi - lo) / (2 * stops)
        out.append((k / (stops - 1), hexc(np.median(im[ys[sel], xs[sel]], axis=0))))
    cx, cy = xs.mean(), ys.mean()
    x1, y1 = cx + axis[0] * lo, cy + axis[1] * lo
    x2, y2 = cx + axis[0] * hi, cy + axis[1] * hi
    return (x1, y1, x2, y2), out

# Tile background: gradient corners + rounded-rect radius measured from the image.
tile = np.load("/tmp/mask_tile.npy")
ys, xs = np.nonzero(tile)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
row = tile[y0 + 2]; rx = np.nonzero(row)[0]
radius = int(round((rx.min() - x0) * 0 + 175))
bgc = lambda x, y: hexc(im[y - 6: y + 6, x - 6: x + 6].mean((0, 1)))
bg_a, bg_b = bgc(x0 + 170, y0 + 150), bgc(x1 - 150, y1 - 170)

ax_l = np.array([0.15, 0.99]); ax_r = np.array([0.8, 0.6])
gl, sl = grad(left, ax_l / np.hypot(*ax_l)); gr, sr = grad(right, ax_r / np.hypot(*ax_r))
# White body gradient (top-left bright -> bottom lavender)
body_top = hexc(im[260:300, 480:540].mean((0, 1))); body_bot = '#E6E4F5'

def stops(s): return "".join(f'<stop offset="{o:.2f}" stop-color="{c}"/>' for o, c in s)
eyes = [ellipse(biggest(dark & (xx < 512) & (yy < 520))),
        ellipse(biggest(dark & (xx >= 512) & (yy < 520))),
        ellipse(biggest(dark & (yy >= 520)))]
body_d, left_d, right_d = bezier_path(fig, sm=7), multi_path(left), multi_path(right)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="{x0}" y1="{y0}" x2="{x1}" y2="{y1}"><stop offset="0" stop-color="{bg_a}"/><stop offset="1" stop-color="{bg_b}"/></linearGradient>
<linearGradient id="body" gradientUnits="userSpaceOnUse" x1="512" y1="200" x2="540" y2="830"><stop offset="0" stop-color="{body_top}"/><stop offset="1" stop-color="{body_bot}"/></linearGradient>
<linearGradient id="left" gradientUnits="userSpaceOnUse" x1="{gl[0]:.0f}" y1="{gl[1]:.0f}" x2="{gl[2]:.0f}" y2="{gl[3]:.0f}">{stops(sl)}</linearGradient>
<linearGradient id="right" gradientUnits="userSpaceOnUse" x1="{gr[0]:.0f}" y1="{gr[1]:.0f}" x2="{gr[2]:.0f}" y2="{gr[3]:.0f}">{stops(sr)}</linearGradient>
<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#0B1460" flood-opacity="0.35"/></filter>
<clipPath id="clip"><path d="{body_d}"/></clipPath>
</defs>
<rect x="{x0}" y="{y0}" width="{x1-x0+1}" height="{y1-y0+1}" rx="{radius}" fill="url(#bg)"/>
<path d="{body_d}" fill="url(#body)" filter="url(#shadow)"/>
<g clip-path="url(#clip)"><path d="{left_d}" fill="url(#left)"/><path d="{right_d}" fill="url(#right)"/></g>
<g fill="#111114">{"".join(f'<ellipse cx="{a:.1f}" cy="{b:.1f}" rx="{c:.1f}" ry="{d:.1f}"/>' for a,b,c,d in eyes)}</g>
</svg>'''
open("../omt-logo.svg", "w").write(svg)
print(len(svg), "bytes", "tile", x0, y0, x1, y1, "r", radius, bg_a, bg_b)
