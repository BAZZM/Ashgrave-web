#!/usr/bin/env python3
"""Fighter to ground luminance (linear) from the pairs tools/g3_shots.js writes: DIR/<mode>/<name>.png (fighters) and
DIR/<mode>/measure/<name>_empty.png (same frame, fighters hidden).

    python3 tools/g3_measure.py [DIR=/home/claude/screens/g3] [mode ...]

Fighter pixels: luminance differs by more than 0.04 between the two, the difference is not a plain darkening of the same hue
(the fighters' shadow on the ground), and the pixel is not the glowing blade or gold trim (bright yellow). Ground: the empty
frame's pixels directly under and around the feet, including the columns the fighters stand in (the empty frame shows the ground
there): x over the fighters' box widened by 30%, y from 10% of the box height above its bottom to 25% below it. Reported in linear
light as Y(fighters) / Y(ground). Target: 1.45 or more (flat today: about 1.1; docs/TEXTURE_LOOK.md).
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

W = np.array([0.2126, 0.7152, 0.0722])


def lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0


def main():
    args = sys.argv[1:]
    base = Path(args[0]) if args and args[0] not in ("before", "after") else Path("/home/claude/screens/g3")
    modes = [a for a in args if a in ("before", "after")] or ["before", "after"]
    for mode in modes:
        for f in sorted((base / mode / "measure").glob("*_empty.png")):
            name = f.name[: -len("_empty.png")]
            a = load(base / mode / (name + ".png"))
            b = load(f)
            la, lb = a @ W, b @ W
            r = (a + 1e-3) / (b + 1e-3)
            shadow = (r.max(-1) - r.min(-1) < 0.18) & (la < lb * 0.9)
            glow = (a[..., 0] > 0.75) & (a[..., 1] > 0.62) & (a[..., 2] < 0.6) & (a[..., 0] - a[..., 2] > 0.25)
            mask = (np.abs(la - lb) > 0.04) & ~shadow & ~glow
            ys, xs = np.nonzero(mask)
            if len(ys) < 200:
                print(f"{mode:6s} {name:18s} fighters not found ({len(ys)} px)")
                continue
            y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
            H, Wd = la.shape
            h = y1 - y0
            pad = int((x1 - x0) * 0.3)
            ground = np.zeros(la.shape, bool)
            ground[max(0, y1 - int(h * 0.10)): min(H, y1 + int(h * 0.25)), max(0, x0 - pad): min(Wd, x1 + pad)] = True
            fy = lin(a)[mask] @ W
            gl = (lin(b)[ground] @ W).mean()
            print(f"{mode:6s} {name:18s} fighters {fy.mean():.3f} (px {mask.sum():6d})  ground {gl:.3f}  ratio {fy.mean() / gl:.2f}")


main()
