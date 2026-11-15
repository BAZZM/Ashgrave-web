#!/usr/bin/env python3
"""Derive the texture forms the three look treatments need (docs/TEXTURE_LOOK.md).

    python3 tools/pack_textures.py [--src assets_src/textures] [--check]

Reads the 20 prepped PNGs (assets_src/textures/<group>/, docs/TEXTURE_PREP.md) and writes
channel-packed greyscale GRAIN maps into assets_src/textures/packed/ (Art Bible section 2.1):
luminance only, 98th percentile clipped, 5th-95th percentile stretched to 0.10-0.90, resized to the
pack size with wrap-around so seams stay closed, four grains per RGBA texture.

    terrain_a 512  R lush grass   G wild meadow    B dirt trail     A muddy wetland
    terrain_b 512  R forest floor G shallow riverbed (256 up) B deep lake  A cobblestone
    build     512  R castle stone G planks         B pine bark (256 up) A deciduous bark (256 up)
    detail    256  R steel plate  G chainmail      B gambeson       A heraldic cloth (512 down)
    foliage   256  R broadleaf luminance G evergreen luminance B broadleaf alpha A evergreen alpha
    ripple    256  R,G ripple normal A (x, y)      B,A ripple normal B (x, y)

The SOURCE treatment uses the colour files as they are (no derived file). The importer
(tools/import_assets.py) then imports everything. Also prints the mean colour (as stored, not linearised) of every colour
texture (opaque pixels only): the SOURCE shader normalises by it (the TEX_MEAN table in tex_kit.gd).
Deterministic: two runs give identical files.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

PACKS = {
    "terrain_a": (512, ["ground/grass_lush", "ground/grass_meadow", "ground/dirt_trail", "ground/mud_wetland"]),
    "terrain_b": (512, ["ground/forest_floor", "water/water_shallow", "water/water_deep", "ground/cobblestone"]),
    "build": (512, ["walls/castle_stone", "wood/planks", "bark/bark_pine", "bark/bark_deciduous"]),
    "detail": (256, ["armour/steel_plate", "armour/chainmail", "armour/gambeson", "cloth/heraldic_cloth"]),
}


def load(src: Path, name: str) -> np.ndarray:
    return np.asarray(Image.open(src / (name + ".png")), dtype=np.float32) / 255.0


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def wrap_resize(a: np.ndarray, size: int) -> np.ndarray:
    """Resize a single-channel float image keeping it periodic (tile 3x3, resize, take the middle)."""
    h = a.shape[0]
    if h == size:
        return a
    t = np.tile(a, (3, 3))
    im = Image.fromarray(t, mode="F").resize((size * 3, size * 3), Image.LANCZOS if size < h else Image.BICUBIC)
    r = np.asarray(im)
    return r[size:2 * size, size:2 * size].copy()


def grain(lum: np.ndarray, weight: np.ndarray | None = None) -> np.ndarray:
    """Clip above the 98th percentile, stretch the 5th-95th percentile to 0.10-0.90."""
    v = lum if weight is None else lum[weight > 0.5]
    hi = np.percentile(v, 98)
    lum = np.minimum(lum, hi)
    v = np.minimum(v, hi)
    p5, p95 = np.percentile(v, 5), np.percentile(v, 95)
    out = 0.10 + (lum - p5) / max(p95 - p5, 1e-4) * 0.80
    return np.clip(out, 0.0, 1.0)


def lin(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def save_rgba(path: Path, chans: list[np.ndarray]) -> None:
    arr = np.stack([np.round(c * 255.0).astype(np.uint8) for c in chans], axis=-1)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, mode="RGBA").save(path, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(ROOT / "assets_src" / "textures"))
    ap.add_argument("--check", action="store_true", help="print statistics only, write nothing")
    args = ap.parse_args()
    src = Path(args.src)
    out = src / "packed"
    print("# mean colour of each colour texture, as stored (the engine samples them undecoded in the Compatibility renderer): TEX_MEAN")
    for f in sorted(src.glob("*/*.png")):
        if f.parent.name == "packed" or "ripple" in f.name:
            continue
        im = np.asarray(Image.open(f).convert("RGBA"), dtype=np.float32) / 255.0
        m = im[..., 3] > 0.5
        mean = im[..., :3][m].mean(axis=0)
        print('\t"%s": Color(%.4f, %.4f, %.4f),' % (f.stem, *mean))
    print("# grain packs")
    for name, (size, parts) in PACKS.items():
        chans = []
        for p in parts:
            rgb = load(src, p)[..., :3]
            lum = wrap_resize(luminance(rgb), size)
            g = grain(lum)
            blur = np.asarray(Image.fromarray(g, mode="F").resize((8, 8), Image.BOX))
            print("  %-10s %-22s %d  mean %.3f  lowfreq range %.3f" % (name, p, size, g.mean(), blur.max() - blur.min()))
            chans.append(g)
        if not args.check:
            save_rgba(out / (name + ".png"), chans)
    # foliage: luminance and alpha of the two cards, 512 -> 256
    lum_c, alp_c = [], []
    for p in ("foliage/leaf_broadleaf", "foliage/leaf_evergreen"):
        im = load(src, p)
        a = im[..., 3]
        lum = luminance(im[..., :3])
        g = grain(lum, a)
        lum_c.append(wrap_resize(g, 256) if False else np.asarray(Image.fromarray(g, mode="F").resize((256, 256), Image.LANCZOS)))
        alp_c.append(np.clip(np.asarray(Image.fromarray(a, mode="F").resize((256, 256), Image.LANCZOS)), 0, 1))
        print("  foliage    %-22s 256  cover %.2f" % (p, (a > 0.5).mean()))
    if not args.check:
        save_rgba(out / "foliage.png", [lum_c[0], lum_c[1], alp_c[0], alp_c[1]])
        ra = load(src, "water/ripple_normal_a")
        rb = load(src, "water/ripple_normal_b")
        save_rgba(out / "ripple.png", [ra[..., 0], ra[..., 1], rb[..., 0], rb[..., 1]])
        print("wrote", ", ".join(sorted(p.name for p in out.glob("*.png"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
