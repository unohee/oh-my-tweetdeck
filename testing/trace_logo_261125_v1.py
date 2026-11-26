# Created: 2026-11-25
# Purpose: Segment the omt logo JPEG into silhouette / colour regions for vector tracing.
# Dependencies: numpy, scipy, Pillow
# Test Status: exploratory
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

im = np.asarray(Image.open("../omt-logo.jpg").convert("RGB")).astype(float)
H, W, _ = im.shape
yy, xx = np.mgrid[0:H, 0:W]

# Tile = region that is not near-white page background.
white = im.min(axis=2) > 235
tile = ~white
tile = ndi.binary_opening(tile, iterations=3)
lab, n = ndi.label(tile)
sizes = ndi.sum(tile, lab, range(1, n + 1))
tile = lab == (1 + int(np.argmax(sizes)))
tile = ndi.binary_fill_holes(tile)
ys, xs = np.where(tile)
print("tile bbox", xs.min(), xs.max(), ys.min(), ys.max())

# Fit bg gradient from pixels in the tile far from the centre figure.
far = tile & (((xx - 512) ** 2 + (yy - 520) ** 2) > 400 ** 2)
far = ndi.binary_erosion(far, iterations=15)
A = np.stack([xx[far], yy[far], np.ones(far.sum())], 1)
coef = [np.linalg.lstsq(A, im[..., c][far], rcond=None)[0] for c in range(3)]
bg = np.stack([coef[c][0] * xx + coef[c][1] * yy + coef[c][2] for c in range(3)], -1)
print("bg corners", bg[100, 100], bg[900, 900])

dist = np.linalg.norm(im - bg, axis=2)
fig = (dist > 70) & ndi.binary_erosion(tile, iterations=6)
fig = ndi.binary_opening(fig, iterations=2)
lab, n = ndi.label(fig)
sizes = ndi.sum(fig, lab, range(1, n + 1))
fig = ndi.binary_fill_holes(lab == (1 + int(np.argmax(sizes))))
ys, xs = np.where(fig)
print("figure bbox", xs.min(), xs.max(), ys.min(), ys.max())

dark = fig & (im.max(axis=2) < 70)  # eyes / nose
Image.fromarray((fig * 255).astype(np.uint8)).save("/tmp/mask_fig.png")
Image.fromarray((tile * 255).astype(np.uint8)).save("/tmp/mask_tile.png")
Image.fromarray((dark * 255).astype(np.uint8)).save("/tmp/mask_dark.png")
np.save("/tmp/mask_fig.npy", fig); np.save("/tmp/mask_tile.npy", tile); np.save("/tmp/mask_dark.npy", dark)
