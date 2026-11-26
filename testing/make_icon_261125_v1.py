# Created: 2026-11-25
# Purpose: Turn omt-logo-detailed.svg into a transparent macOS app icon (.icns).
# Dependencies: Pillow, numpy, macOS qlmanage + iconutil
# Test Status: exploratory
import subprocess, shutil, os, numpy as np
from PIL import Image, ImageDraw
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
subprocess.run(["qlmanage", "-t", "-s", "2048", "-o", "/tmp", "omt-logo-detailed.svg"], check=True, capture_output=True)
src = Image.open("/tmp/omt-logo-detailed.svg.png").convert("RGB")
k = src.width / 1024
x0, y0, x1, y1 = 76, 63, 947, 954          # tile bounds in the 1024 design space
tile = src.crop((round(x0*k), round(y0*k), round(x1*k), round(y1*k)))
S = 824 * 2                                  # Apple icon grid: 824pt tile in a 1024pt canvas (x2 supersample)
tile = tile.resize((S, S), Image.LANCZOS)
# rounded-rect alpha, supersampled
m = Image.new("L", (S * 2, S * 2), 0)
ImageDraw.Draw(m).rounded_rectangle((0, 0, S*2-1, S*2-1), radius=int(175 * S / 871 * 2), fill=255)
m = m.resize((S, S), Image.LANCZOS)
tile.putalpha(m)
canvas = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
off = (2048 - S) // 2
# soft drop shadow like system icons
sh = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
sh.paste((0, 0, 0, 110), (off, off + 24), m)
from PIL import ImageFilter
sh = sh.filter(ImageFilter.GaussianBlur(22))
canvas = Image.alpha_composite(canvas, sh)
canvas.alpha_composite(tile, (off, off))
master = canvas.resize((1024, 1024), Image.LANCZOS)
master.save("Resources/AppIcon-1024.png")
iset = "build/AppIcon.iconset"
shutil.rmtree(iset, ignore_errors=True); os.makedirs(iset)
for base in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base * scale
        master.resize((px, px), Image.LANCZOS).save(f"{iset}/icon_{base}x{base}{'@2x' if scale == 2 else ''}.png")
subprocess.run(["iconutil", "-c", "icns", iset, "-o", "Resources/AppIcon.icns"], check=True)
print("ok")
