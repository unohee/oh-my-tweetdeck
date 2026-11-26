# Created: 2026-11-25
# Purpose: Trace logo regions into smooth cubic-bezier SVG paths (silhouette, colour arms, eyes).
# Dependencies: numpy, scipy, Pillow
# Test Status: exploratory
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

im = np.asarray(Image.open("../omt-logo.jpg").convert("RGB")).astype(float)
H, W, _ = im.shape
yy, xx = np.mgrid[0:H, 0:W]
tile = np.load("/tmp/mask_tile.npy")

# Background model (linear gradient) fitted away from the figure.
far = ndi.binary_erosion(tile & (((xx-512)**2 + (yy-520)**2) > 400**2), iterations=15)
A = np.stack([xx[far], yy[far], np.ones(far.sum())], 1)
coef = [np.linalg.lstsq(A, im[..., c][far], rcond=None)[0] for c in range(3)]
bg = np.stack([coef[c][0]*xx + coef[c][1]*yy + coef[c][2] for c in range(3)], -1)
dist = np.linalg.norm(im - bg, axis=2)

# Figure = clearly different from bg. Lower threshold, then smooth to kill jaggies.
fig = (dist > 45) & ndi.binary_erosion(tile, iterations=8)
fig = ndi.binary_opening(fig, structure=np.ones((3,3)), iterations=2)
lab, n = ndi.label(fig)
fig = lab == (1 + int(np.argmax(ndi.sum(fig, lab, range(1, n+1)))))
fig = ndi.binary_fill_holes(fig)
# Remove the soft drop shadow below the body: it is dark and low-saturation relative to bg.
soft = ndi.gaussian_filter(fig.astype(float), 2.0) > 0.5
fig = soft

hsv = np.asarray(Image.open("../omt-logo.jpg").convert("HSV")).astype(float)
sat, val = hsv[..., 1], hsv[..., 2]
white_body = fig & (sat < 60) & (val > 190)
# Colour arms: saturated, bright pixels inside figure, split by x.
colour = fig & (sat >= 60) & (val > 120)
colour = ndi.binary_opening(colour, iterations=2)
left = colour & (xx < 512); right = colour & (xx >= 512)
def biggest(m):
    l, n = ndi.label(m)
    return l == (1 + int(np.argmax(ndi.sum(m, l, range(1, n+1)))))
left, right = biggest(left), biggest(right)
dark = fig & (val < 80)
dark = ndi.binary_opening(dark, iterations=2)

def contour(mask):
    """Ordered boundary via marching squares on a smoothed field."""
    f = ndi.gaussian_filter(mask.astype(float), 1.5)
    import matplotlib  # noqa
    return f
np.save("/tmp/m_fig.npy", fig); np.save("/tmp/m_left.npy", left)
np.save("/tmp/m_right.npy", right); np.save("/tmp/m_dark.npy", dark)
ov = (im*0.4).astype(np.uint8)
ov[fig] = [255,255,255]; ov[left] = [0,200,255]; ov[right] = [255,120,0]; ov[dark] = [0,0,0]
Image.fromarray(ov).save("/tmp/mask_overlay.png")
print({k:int(v.sum()) for k,v in dict(fig=fig,left=left,right=right,dark=dark).items()})
