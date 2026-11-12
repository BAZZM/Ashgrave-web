#!/usr/bin/env python3
"""Generate a tiny rigged, animated, textured .glb (stdlib only, so no licence question).

    python3 tools/test_assets/make_test_glb.py assets_src/test/assettest.glb

A 4-sided tapering column with 2 bones (base, and a child 0.8 up), a 1 s looping
animation ("sway-loop") that swings both bones, and a 64x64 PNG base colour.
"""
import json
import math
import struct
import sys
import zlib
from pathlib import Path


def png(w, h, pixel):
    raw = b"".join(b"\0" + b"".join(bytes(pixel(x, y)) for x in range(w)) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def pixel(x, y):
    # Orange/teal checker (8px cells) with a white stripe on top rows: orientation is obvious.
    if y < 6:
        return (245, 245, 245)
    return (235, 120, 30) if ((x // 8) + (y // 8)) % 2 == 0 else (20, 150, 160)


def quat_z(a):
    return [0.0, 0.0, math.sin(a / 2), math.cos(a / 2)]


def main(out):
    # 3 rings of 5 verts (5th duplicates the 1st for the UV seam) + apex.
    rings = [(0.0, 0.30), (0.8, 0.22), (1.6, 0.14)]
    pos, nrm, uv, joints, weights = [], [], [], [], []
    wts = [(0, 1.0), (0, 0.5), (1, 1.0)]
    for r, (y, rad) in enumerate(rings):
        for i in range(5):
            a = (i % 4) * math.pi / 2 + math.pi / 4
            c, s = math.cos(a), math.sin(a)
            pos.append((c * rad, y, s * rad))
            nrm.append((c, 0.3, s))
            uv.append((i / 4, 1.0 - r / 2.5))
            if r == 1:
                joints.append((0, 1, 0, 0)); weights.append((0.5, 0.5, 0, 0))
            else:
                joints.append((wts[r][0], 0, 0, 0)); weights.append((1.0, 0, 0, 0))
    apex = len(pos)
    pos.append((0, 1.75, 0)); nrm.append((0, 1, 0)); uv.append((0.5, 0.0))
    joints.append((1, 0, 0, 0)); weights.append((1.0, 0, 0, 0))
    idx = []
    for r in range(2):
        for i in range(4):
            a, b = r * 5 + i, r * 5 + i + 1
            idx += [a, b, a + 5, b, b + 5, a + 5]
    for i in range(4):
        idx += [10 + i, 10 + i + 1, apex]

    buf = bytearray()
    views, accs = [], []

    def add(data, count, ctype, atype, target=None, mm=None):
        while len(buf) % 4:
            buf.append(0)
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), **({"target": target} if target else {})})
        buf.extend(data)
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": atype}
        if mm:
            a["min"], a["max"] = mm
        accs.append(a)
        return len(accs) - 1

    flat = lambda t: [v for p in t for v in p]
    xs, ys, zs = zip(*pos)
    A_POS = add(struct.pack(f"<{len(pos)*3}f", *flat(pos)), len(pos), 5126, "VEC3", 34962, ([min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]))
    A_NRM = add(struct.pack(f"<{len(nrm)*3}f", *flat(nrm)), len(nrm), 5126, "VEC3", 34962)
    A_UV = add(struct.pack(f"<{len(uv)*2}f", *flat(uv)), len(uv), 5126, "VEC2", 34962)
    A_J = add(struct.pack(f"<{len(joints)*4}B", *flat(joints)), len(joints), 5121, "VEC4", 34962)
    A_W = add(struct.pack(f"<{len(weights)*4}f", *flat(weights)), len(weights), 5126, "VEC4", 34962)
    A_I = add(struct.pack(f"<{len(idx)}H", *idx), len(idx), 5123, "SCALAR", 34963)
    ident = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ibm1 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -0.8, 0, 1]
    A_IBM = add(struct.pack("<32f", *(ident + ibm1)), 2, 5126, "MAT4")
    times = [0.0, 0.25, 0.5, 0.75, 1.0]
    A_T = add(struct.pack("<5f", *times), 5, 5126, "SCALAR", None, ([0.0], [1.0]))
    k0 = [0.0, 0.12, 0.0, -0.12, 0.0]
    k1 = [0.0, 0.9, 0.0, -0.9, 0.0]
    A_R0 = add(struct.pack("<20f", *flat(quat_z(a) for a in k0)), 5, 5126, "VEC4")
    A_R1 = add(struct.pack("<20f", *flat(quat_z(a) for a in k1)), 5, 5126, "VEC4")
    img = png(64, 64, pixel)
    while len(buf) % 4:
        buf.append(0)
    views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(img)})
    buf.extend(img)
    img_view = len(views) - 1

    gltf = {
        "asset": {"version": "2.0", "generator": "make_test_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, 3]}],
        "nodes": [
            {"name": "Armature", "children": [1]},
            {"name": "BoneBase", "children": [2]},
            {"name": "BoneTop", "translation": [0, 0.8, 0]},
            {"name": "TestBody", "mesh": 0, "skin": 0},
        ],
        "skins": [{"joints": [1, 2], "inverseBindMatrices": A_IBM, "skeleton": 0}],
        "meshes": [{"name": "TestBody", "primitives": [{"attributes": {"POSITION": A_POS, "NORMAL": A_NRM, "TEXCOORD_0": A_UV, "JOINTS_0": A_J, "WEIGHTS_0": A_W}, "indices": A_I, "material": 0}]}],
        "materials": [{"name": "TestMat", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}, "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"bufferView": img_view, "mimeType": "image/png", "name": "test_albedo"}],
        "animations": [{"name": "sway-loop",
                        "samplers": [{"input": A_T, "output": A_R0, "interpolation": "LINEAR"}, {"input": A_T, "output": A_R1, "interpolation": "LINEAR"}],
                        "channels": [{"sampler": 0, "target": {"node": 1, "path": "rotation"}}, {"sampler": 1, "target": {"node": 2, "path": "rotation"}}]}],
        "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(buf)}],
    }
    # Node rotation defaults are identity; animation channels override them.
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    bin_ = bytes(buf) + b"\0" * (-len(buf) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    data = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(bin_), b"BIN\0") + bin_
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_bytes(data)
    print("wrote", out, len(data), "bytes")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets_src/test/assettest.glb")
