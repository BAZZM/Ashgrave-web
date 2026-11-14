#!/usr/bin/env python3
"""Fighter to ground luminance (linear) from the pairs tools/g3_shots.js writes: DIR/<mode>/<name>.png (fighters) and
DIR/<mode>/measure/<name>_empty.png (same frame, fighters hidden).

    python3 tools/g3_measure.py [DIR=/home/claude/screens/g3] [mode ...]

Fighter pixels: luminance differs by more than 0.04 between the two and the difference is not a plain darkening of the same hue
(a shadow on the ground). Ground: the empty frame's pixels in the same rows as the fighters' bounding box extended one box
height down, outside the fighters' box columns widened by 40%, and below the horizon (rows under 45% of the picture);
reported in linear light as Y(fighters) / Y(ground). Target: at least 1.5 (docs/TEXTURE_LOOK.md).
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
    base = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1] in ("before", "after") else Path("/home/claude/screens/g3")
    modes = [a for a in sys.argv[1:] if a in ("before", "after")] or ["before", "after"]
    for mode in modes:
        for f in sorted((base / mode / "measure").glob("*_empty.png")):
            name = f.name[: -len("_empty.png")]
            a = load(base / mode / (name + ".png"))
            b = load(f)
            la, lb = a @ W, b @ W
            r = (a + 1e-3) / (b + 1e-3)
            shadow = (r.max(-1) - r.min(-1) < 0.18) & (la < lb * 0.9)  # ground darkened by the fighters' shadow, same hue
            mask = (np.abs(la - lb) > 0.04) & ~shadow
            ys, xs = np.nonzero(mask)
            if len(ys) < 200:
                print(f"{mode:6s} {name:18s} fighters not found ({len(ys)} px)")
                continue
            y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
            H, Wd = la.shape
            h = y1 - y0
            gy0 = max(int(H * 0.45), y0)
            gy1 = min(H, y1 + h)
            ground = np.zeros_like(mask)
            ground[gy0:gy1, :] = True
            pad = int((x1 - x0) * 0.2)
            ground[:, max(0, x0 - pad): x1 + pad] = False
            ground &= ~mask
            # drop sky/background: keep pixels near the median luminance of the candidates' lower half
            g = lin(b)[ground] @ W
            fy = lin(a)[mask] @ W
            med = np.median(g)
            keep = (g > med * 0.5) & (g < med * 1.6)
            gl = g[keep].mean()
            print(f"{mode:6s} {name:18s} fighters {fy.mean():.3f} (px {mask.sum():6d})  ground {gl:.3f}  ratio {fy.mean() / gl:.2f}")


main()
