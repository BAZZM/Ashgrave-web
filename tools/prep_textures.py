#!/usr/bin/env python3
"""Texture prep for Ashgrave (docs/TEXTURE_PLAN.md T1, docs/TEXTURE_PREP.md).

Turns the 18 raw AI-generated pack textures (+2 ripple normal maps) into seamless,
power-of-two, game-ready PNGs. Nothing here touches the repo's game/ folder and no
image is written inside the repo.

  python3 tools/prep_textures.py --src /home/claude/assets_src/_masters \
      --out /home/claude/assets_src --sheets /home/claude/screens/texprep [--only NAME ...]

Per texture: measure seam score -> crop -> seam fix (min-error-cut quilting, only if
needed) -> low-frequency brightness flattening -> periodic Lanczos resize in linear
light -> 8-bit PNG.  No colour grading.  Deterministic (no randomness is used; every
step is a pure function of the input pixels).
"""
import argparse
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

# --------------------------------------------------------------------------------------
# TABLE: one row per texture.  Add a texture = add a row.
#   name   : output file stem        src : file name somewhere under --src
#   group  : output folder           size: output edge in px (power of two)
#   kind   : tile | card | normal
#   ops (all optional):
#     crop=(l,t,r,b)      crop the master first (master pixels)
#     seam='auto'|'cut'|'none'   auto = fix when measured score > SEAM_TRIGGER; cut = always
#     overlap=0.2         cut overlap as a fraction of the (cropped) edge; bigger = more
#                         freedom for the cut path, but the master gets smaller by that much
#     flat=0.0..1.0       low-frequency brightness flattening strength (0 = off)
#     flat_sigma=0.15     blur radius for flattening as a fraction of the edge
# --------------------------------------------------------------------------------------
SEAM_TRIGGER = 1.3   # wrap-edge difference / interior-neighbour difference; ~1.0 means invisible
ROWS = [
    # name,             src,                                  group,    size, kind,    ops
    ("grass_lush",      "01_lush_grassland.png",              "ground", 512, "tile",   dict(flat=0.6)),
    ("grass_meadow",    "02_wild_meadow.png",                 "ground", 512, "tile",   dict(flat=0.6)),
    ("dirt_trail",      "03_grassy_dirt_trail.png",           "ground", 512, "tile",   dict(flat=0.5, overlap=0.15)),
    ("mud_wetland",     "04_muddy_wetland.png",               "ground", 512, "tile",   dict(flat=0.6, overlap=0.15)),
    ("forest_floor",    "07_forest_floor_dirt_leaves.png",    "ground", 512, "tile",   dict(flat=0.6)),
    ("cobblestone",     "05_mossy_cobblestone_road.png",      "ground", 512, "tile",   dict(flat=0.6)),
    ("water_shallow",   "05_shallow_riverbed.png",            "water",  256, "tile",   dict(flat=0.5)),
    ("water_deep",      "06_deep_lake_ripples.png",           "water",  512, "tile",   dict(flat=0.5)),
    ("ripple_normal_a", "water_ripple_normal_a.png",          "water",  256, "normal", dict()),
    ("ripple_normal_b", "water_ripple_normal_b.png",          "water",  256, "normal", dict()),
    ("bark_deciduous",  "07_mossy_deciduous_bark.png",        "bark",   256, "tile",   dict(flat=0.6, overlap=0.18)),
    ("bark_pine",       "08_reddish_pine_bark.png",           "bark",   256, "tile",   dict(flat=0.6, overlap=0.18)),
    ("leaf_broadleaf",  "09_green_broadleaf_card.png",        "foliage", 512, "card",  dict()),
    ("leaf_evergreen",  "10_evergreen_branch_card.png",       "foliage", 512, "card",  dict()),
    ("castle_stone",    "04_mossy_castle_stone_wall.png",     "walls",  512, "tile",   dict(flat=0.6, overlap=0.2)),
    ("planks",          "06_weathered_wood_planks.png",       "wood",   512, "tile",   dict(flat=0.6, overlap=0.2)),
    ("steel_plate",     "01_weathered_steel_plate_armor.png", "armour", 256, "tile",   dict(flat=0.5)),
    ("gambeson",        "02_quilted_gambeson_leather.png",    "armour", 256, "tile",   dict(flat=0.5)),
    ("chainmail",       "03_riveted_chainmail.png",           "armour", 256, "tile",   dict(crop=(97, 100, 1157, 1160), seam="cut", overlap=0.15, flat=0.5)),
    ("heraldic_cloth",  "08_crimson_gold_heraldic_fabric.png", "cloth", 512, "tile",   dict(flat=0.3, seam="none")),
]

FLAT_SIGMA = 0.15
ALPHA_LO, ALPHA_HI = 6 / 255, 246 / 255   # alpha clean-up ramp for the foliage cards
CARD_BORDER = 2                            # px at output size forced transparent
ALPHA_SPECK = 60                           # master-pixel components smaller than this are removed


# ------------------------------------------------------------------ colour helpers
def srgb_to_lin(a):
    a = np.asarray(a, np.float32)
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4).astype(np.float32)


def lin_to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055).astype(np.float32)


def load(path):
    im = Image.open(path)
    return np.asarray(im, np.float32) / 255.0


def to8(a):
    return np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)


def save_png(a, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = "RGBA" if a.shape[2] == 4 else "RGB"
    Image.fromarray(to8(a), mode).save(path, optimize=True, compress_level=9)


# ------------------------------------------------------------------ measuring
def seam_scores(a):
    """(horizontal, vertical) wrap-edge difference / mean interior neighbour difference."""
    a = a[..., :3]
    ih = np.abs(a[:, 1:] - a[:, :-1]).mean()
    iv = np.abs(a[1:] - a[:-1]).mean()
    h = np.abs(a[:, 0] - a[:, -1]).mean() / max(ih, 1e-6)
    v = np.abs(a[0] - a[-1]).mean() / max(iv, 1e-6)
    return float(h), float(v)


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def lowfreq(a, sigma_frac=FLAT_SIGMA):
    """std of the heavily blurred luminance, relative to mean luminance (blotchiness)."""
    y = lum(a)
    b = ndi.gaussian_filter(y, sigma_frac * y.shape[0], mode="wrap")
    return float(b.std() / max(y.mean(), 1e-6))


# ------------------------------------------------------------------ seam fixing
def _closed_or_open_path(E, closed):
    """Vertical min-cost path through E (rows x k). closed => path ends within 1 col of its
    start so it joins up across the wrap in the other axis."""
    n, k = E.shape
    stride = max(1, k // 48)
    starts = list(range(0, k, stride)) if closed else [None]
    S = len(starts)
    inf = np.float32(1e18)
    cost = np.full((S, k), inf, np.float32)
    if closed:
        for i, s in enumerate(starts):
            cost[i, s] = E[0, s]
    else:
        cost[0] = E[0]
    back = np.zeros((n, S, k), np.int8)
    for r in range(1, n):
        pad = np.pad(cost, ((0, 0), (1, 1)), constant_values=inf)
        stack = np.stack([pad[:, :-2], pad[:, 1:-1], pad[:, 2:]])   # came from col-1, col, col+1
        arg = stack.argmin(0)
        back[r] = arg.astype(np.int8) - 1
        cost = stack.min(0) + E[r]
    best, bi, bc = np.float32(inf), 0, 0
    for i in range(S):
        if closed:
            lo, hi = max(0, starts[i] - 1), min(k, starts[i] + 2)
            c = lo + int(cost[i, lo:hi].argmin())
        else:
            c = int(cost[i].argmin())
        if cost[i, c] < best:
            best, bi, bc = cost[i, c], i, c
    path = np.zeros(n, np.int32)
    c = bc
    for r in range(n - 1, -1, -1):
        path[r] = c
        c = c + int(back[r, bi, c])
    return path, float(best) / n


def fix_axis(a, k, closed):
    """Make `a` tile horizontally by a min-error cut through a k-px overlap of its right and
    left edges (image-quilting style). Output width is W-k."""
    H, W, C = a.shape
    A = a[:, W - k:]          # real right edge: continues into out[:, 0:k] on the left of the cut
    B = a[:, :k]
    E = ((A - B) ** 2).sum(2).astype(np.float32)
    E = ndi.gaussian_filter(E, 1.0)
    path, mean_cost = _closed_or_open_path(E, closed)
    xs = np.arange(k, dtype=np.float32)[None, :]
    # soft 5 px blend across the cut so it does not alias
    mB = np.clip((xs - path[:, None].astype(np.float32)) / 4.0 + 0.5, 0, 1)[..., None]
    mix = A * (1 - mB) + B * mB
    out = a[:, : W - k].copy()
    out[:, :k] = mix
    return out, mean_cost


def seam_fix(a, overlap):
    h, v = seam_scores(a)
    n = a.shape[0]
    k = int(round(overlap * min(a.shape[0], a.shape[1])))
    a, cx = fix_axis(a, k, closed=False)
    a = np.ascontiguousarray(np.swapaxes(a, 0, 1))
    a, cy = fix_axis(a, k, closed=True)
    a = np.ascontiguousarray(np.swapaxes(a, 0, 1))
    return a, (cx, cy)


# ------------------------------------------------------------------ flattening
def flatten(a, strength, sigma_frac=FLAT_SIGMA):
    """Subtract a heavily blurred (wrap-around) luminance, re-add the mean. Gentle."""
    if strength <= 0:
        return a
    y = lum(a)
    blur = ndi.gaussian_filter(y, sigma_frac * y.shape[0], mode="wrap")
    delta = (blur - blur.mean()) * strength
    return np.clip(a - delta[..., None], 0, 1)


# ------------------------------------------------------------------ resizing
def _lanczos_matrix(n_in, n_out, periodic, a=3):
    scale = n_in / n_out
    sup = a * max(scale, 1.0)
    M = np.zeros((n_out, n_in), np.float64)
    for i in range(n_out):
        c = (i + 0.5) * scale - 0.5
        j = np.arange(int(np.floor(c - sup)), int(np.ceil(c + sup)) + 1)
        x = (j - c) / max(scale, 1.0)
        w = np.where(np.abs(x) < a, np.sinc(x) * np.sinc(x / a), 0.0)
        jj = j % n_in if periodic else np.clip(j, 0, n_in - 1)
        np.add.at(M[i], jj, w)
    M /= M.sum(1, keepdims=True)
    return M.astype(np.float32)


def resize(a, n_out, periodic=True):
    """Separable Lanczos-3 resize; wrap-around taps when periodic so tiling survives."""
    H, W = a.shape[:2]
    My = _lanczos_matrix(H, n_out, periodic)
    Mx = _lanczos_matrix(W, n_out, periodic)
    t = np.tensordot(My, a, axes=(1, 0))            # (n_out, W, C)
    t = np.tensordot(Mx, t, axes=(1, 1))            # (n_out, n_out, C) with axes swapped
    return np.ascontiguousarray(np.swapaxes(t, 0, 1)).astype(np.float32)


def resize_color(a, n_out, periodic=True):
    return lin_to_srgb(resize(srgb_to_lin(a), n_out, periodic))


# ------------------------------------------------------------------ cards
def prep_card(a, n_out):
    """a: RGBA float master. Clean alpha, drop specks/border junk, resize premultiplied in
    linear light, then bleed colour into transparent pixels."""
    info = {}
    rgb, al = a[..., :3], a[..., 3]
    info["cov_before"] = float(al.mean())
    al = np.clip((al - ALPHA_LO) / (ALPHA_HI - ALPHA_LO), 0, 1)
    lab, n = ndi.label(al > 0.02)
    sizes = ndi.sum(al > 0.02, lab, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes >= ALPHA_SPECK
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    for b in border:
        keep[b] = False
    info["specks_removed"] = int((~keep[1:]).sum())
    info["border_components_removed"] = len(border)
    al = al * keep[lab]
    # colours of near-transparent master pixels are black (not real): replace by nearest solid colour
    solid = al > 0.9
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    lin = srgb_to_lin(rgb) * al[..., None]
    t = resize(np.dstack([lin, al]), n_out, periodic=False)
    alo = np.clip(t[..., 3], 0, 1)
    alo[:CARD_BORDER] = 0
    alo[-CARD_BORDER:] = 0
    alo[:, :CARD_BORDER] = 0
    alo[:, -CARD_BORDER:] = 0
    col = t[..., :3] / np.maximum(alo[..., None], 1e-4)
    col = np.clip(col, 0, 1)
    solid = alo > 0.9
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    bled = col[idx[0], idx[1]]
    colo = np.where((alo > 0.9)[..., None], col, bled)   # edge pixels take the interior colour: no pale/dark halo
    out = np.dstack([lin_to_srgb(colo), alo])
    # 8-bit: alpha 0 pixels keep bled colour (RGB is preserved in PNG RGBA)
    info["cov_after"] = float(alo.mean())
    info["opaque_after"] = float((alo > 0.5).mean())
    return out, info


# ------------------------------------------------------------------ normals
def prep_normal(a, n_out):
    v = a[..., :3] * 2 - 1
    ln = np.linalg.norm(v, axis=2)
    info = dict(
        len_mean=float(ln.mean()), len_min=float(ln.min()), len_max=float(ln.max()),
        blue_frac=float((v[..., 2] > np.abs(v[..., :2]).max(2)).mean()),
        z_min=float(v[..., 2].min()), mean_xy=(float(v[..., 0].mean()), float(v[..., 1].mean())),
    )
    info["seam_h"], info["seam_v"] = seam_scores(a)
    r = resize(v.astype(np.float32), n_out, periodic=True)
    r /= np.maximum(np.linalg.norm(r, axis=2, keepdims=True), 1e-6)
    out = (r + 1) / 2
    info["seam_after"] = seam_scores(out)
    return out, info


# ------------------------------------------------------------------ sheets
def tile_grid(a, n):
    rgb = a[..., :3] if a.shape[2] == 3 else a
    return np.tile(rgb, (n, n, 1))


def pil(a):
    return Image.fromarray(to8(a), "RGBA" if a.shape[2] == 4 else "RGB")


def checker(w, h, s=16):
    yy, xx = np.mgrid[:h, :w]
    c = (((yy // s) + (xx // s)) % 2).astype(np.float32) * 0.15 + 0.35
    return np.dstack([c, c, c])


def card_on_checker(a):
    bg = checker(a.shape[1], a.shape[0])
    al = a[..., 3:4]
    return bg * (1 - al) + a[..., :3] * al


def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8 + 7 * len(text), 14], fill=(0, 0, 0))
    d.text((4, 2), text, fill=(255, 255, 255))
    return im


def make_sheets(results, sheets):
    tiled = sheets / "tiled"
    tiled.mkdir(parents=True, exist_ok=True)
    cell = 384
    cols = 5
    rows = (len(results) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell + 8) + 8, rows * (cell + 8) + 8), (30, 30, 30))
    for i, r in enumerate(results):
        out = r["out"]
        if r["kind"] == "card":
            im = pil(card_on_checker(out))
            im = im.resize((cell, cell), Image.LANCZOS)
        else:
            t2 = tile_grid(out, 2)
            im = pil(t2).resize((cell, cell), Image.LANCZOS)
            pil(tile_grid(out, 3)).save(tiled / f"{r['name']}.png")
        label(im, f"{r['group']}/{r['name']} {out.shape[1]}px")
        sheet.paste(im, (8 + (i % cols) * (cell + 8), 8 + (i // cols) * (cell + 8)))
        if r.get("fixed"):
            ba = sheets / "before_after"
            ba.mkdir(exist_ok=True)
            t = 256
            bef = pil(tile_grid(resize_color(r["master_raw"], t, periodic=False), 3))
            aft = pil(tile_grid(resize_color(r["prepared"], t, periodic=True), 3))
            w = Image.new("RGB", (bef.width * 2 + 16, bef.height), (255, 0, 255))
            w.paste(label(bef, "BEFORE (raw master)"), (0, 0))
            w.paste(label(aft, "AFTER"), (bef.width + 16, 0))
            w.save(ba / f"{r['name']}.png")
    sheet.save(sheets / "contact.png")


# ------------------------------------------------------------------ main
def find_src(root, fname):
    hits = sorted(root.rglob(fname), key=lambda p: ("Original_1254" not in str(p) and "Shader_Extras" not in str(p), str(p)))
    if not hits:
        raise FileNotFoundError(f"{fname} not found under {root}")
    return hits[0]


def process(row, src_root, out_root):
    name, src, group, size, kind, ops = row
    path = find_src(src_root, src)
    a = load(path)
    r = dict(name=name, group=group, size=size, kind=kind, src=src, ops=[], master_raw=a)
    if kind == "card":
        out, info = prep_card(a, size)
        r.update(info=info, out=out, prepared=a, verdict_hint="card")
        r["ops"] = ["alpha clean", "colour bleed", "resize"]
        save_png(out, out_root / "textures" / group / f"{name}.png")
        # lossless prepared master: cleaned alpha at full size
        pm, _ = prep_card(a, a.shape[0])
        save_png(pm, out_root / "_prepared_masters" / group / f"{name}.png")
        return r
    if kind == "normal":
        out, info = prep_normal(a, size)
        r.update(info=info, out=out, prepared=a)
        r["ops"] = ["resize (periodic, renormalised)"]
        save_png(out, out_root / "textures" / group / f"{name}.png")
        save_png(a, out_root / "_prepared_masters" / group / f"{name}.png")
        return r

    ops = dict(ops)
    if "crop" in ops:
        l, t, rr, b = ops["crop"]
        a = a[t:b, l:rr]
        r["ops"].append(f"crop {rr - l}x{b - t}")
    r["master_scores"] = seam_scores(a)          # before, at master resolution
    mode = ops.get("seam", "auto")
    need = mode == "cut" or (mode == "auto" and max(r["master_scores"]) > SEAM_TRIGGER)
    r["fixed"] = bool(need)
    if need:
        ov = ops.get("overlap", 0.18)
        a, cost = seam_fix(a, ov)
        r["ops"].append(f"min-cut seam fix (overlap {int(ov * 100)}%)")
        r["cut_cost"] = cost
    r["lf_before"] = lowfreq(a)
    fs = ops.get("flat", 0.0)
    a = flatten(a, fs, ops.get("flat_sigma", FLAT_SIGMA))
    r["flat"] = fs
    r["lf_after"] = lowfreq(a)
    if fs > 0:
        r["ops"].append(f"flatten {fs}")
    a = np.asarray(to8(a), np.float32) / 255.0          # prepared master is 8-bit
    r["prepared"] = a
    r["prep_scores"] = seam_scores(a)
    out = to8(resize_color(a, size, periodic=True)).astype(np.float32) / 255.0
    r["ops"].append(f"resize {size}")
    r["out"] = out
    r["final_scores"] = seam_scores(out)
    save_png(out, out_root / "textures" / group / f"{name}.png")
    save_png(a, out_root / "_prepared_masters" / group / f"{name}.png")
    return r


def fmt(s):
    return f"{s[0]:.2f}/{s[1]:.2f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, type=Path, help="folder holding the unzipped packs")
    ap.add_argument("--out", required=True, type=Path, help="assets_src folder (writes textures/ and _prepared_masters/)")
    ap.add_argument("--sheets", required=True, type=Path, help="review sheet folder")
    ap.add_argument("--only", nargs="*", default=None, help="only these output names")
    args = ap.parse_args()

    rows = [r for r in ROWS if not args.only or r[0] in args.only]
    results = [process(r, args.src, args.out) for r in rows]

    print(f"{'name':16} {'size':>4} {'seam master before':>19} {'prepared after':>15} {'final':>9} {'lowfreq b->a':>13}  ops")
    mem = 0
    for r in results:
        sz = r["out"].shape[0]
        mem += sz * sz * 4 * 4 / 3
        if r["kind"] == "tile":
            print(f"{r['name']:16} {sz:4} {fmt(r['master_scores']):>19} {fmt(r['prep_scores']):>15} {fmt(r['final_scores']):>9} "
                  f"{r['lf_before']:.3f}->{r['lf_after']:.3f}  {', '.join(r['ops'])}")
        elif r["kind"] == "card":
            i = r["info"]
            print(f"{r['name']:16} {sz:4} alpha cov {i['cov_before']:.3f}->{i['cov_after']:.3f} (>0.5: {i['opaque_after']:.3f}), "
                  f"specks removed {i['specks_removed']}, border comps {i['border_components_removed']}")
        else:
            i = r["info"]
            print(f"{r['name']:16} {sz:4} seam {i['seam_h']:.2f}/{i['seam_v']:.2f}->{fmt(i['seam_after'])}  len {i['len_min']:.2f}..{i['len_max']:.2f} "
                  f"blue-dominant {i['blue_frac']:.3f} min z {i['z_min']:.2f} mean xy {i['mean_xy'][0]:+.3f},{i['mean_xy'][1]:+.3f}")
    print(f"memory (RGBA8 + mips): {mem / 1e6:.1f} MB for {len(results)} textures")

    make_sheets(results, args.sheets)

    h = hashlib.sha256()
    for p in sorted((args.out / "textures").rglob("*.png")):
        h.update(p.relative_to(args.out).as_posix().encode())
        h.update(p.read_bytes())
    print("sha256 of textures/:", h.hexdigest())


if __name__ == "__main__":
    sys.exit(main())
