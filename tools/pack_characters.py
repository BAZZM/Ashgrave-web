#!/usr/bin/env python3
"""Pack KayKit characters for RigVisual (docs/RIG_PLAN.md R1): no clip or texture is loaded twice.

    python3 -I tools/pack_characters.py [--src DIR] [--out DIR] [--slot 256]

Reads the raw KayKit packs (default /home/claude/assets_src/kaykit, CC0, never committed) and writes
into assets_src/rig/ (git-ignored; tools/import_assets.py turns it into res://assets/rig/):

  <base>.glb   one per character: skeleton, the skinned body parts merged into two meshes ("Body" and
               "Head"), the gear meshes on their bone nodes; no animation, no image, no texture.
               UVs are moved into the character's slot of the shared atlas.
  anims.glb    the skeleton of Skeleton_Warrior (the superset of clip names) plus exactly the clips in
               CLIPS and no mesh: imported once, its AnimationLibrary is shared by every RigVisual.
  atlas.png    one atlas for every character: each pack texture (1024 px) scaled to SLOT px into its slot.

Also strips the sideways travel of root and hips (0.69 u) from Dodge_Left/Right (the duel tweens the node itself).
Prints sizes. Needs numpy and Pillow.
"""
import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ADV = "KayKit-Character-Pack-Adventures-1.0/addons/kaykit_character_pack_adventures/Characters/gltf/"
SKE = "KayKit-Character-Pack-Skeletons-1.0/addons/kaykit_character_pack_skeletons/Characters/gltf/"

# Atlas slots (column, row). Slot 1,1 is the skeleton texture, shared by every skeleton.
TEXTURES = {
    "knight": (ADV + "knight_texture.png", (0, 0)),
    "barbarian": (ADV + "barbarian_texture.png", (1, 0)),
    "rogue": (ADV + "rogue_texture.png", (0, 1)),
    "skeleton": (SKE + "skeleton_texture.png", (1, 1)),
}
# base name -> (source file, texture, skinned parts merged into Body, part kept as Head)
BASES = {
    "knight": (ADV + "Knight.glb", "knight",
               ["Knight_Body", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight"], "Knight_Head"),
    "skeleton_warrior": (SKE + "Skeleton_Warrior.glb", "skeleton",
                         ["Skeleton_Warrior_Body", "Skeleton_Warrior_ArmLeft", "Skeleton_Warrior_ArmRight",
                          "Skeleton_Warrior_LegLeft", "Skeleton_Warrior_LegRight", "Skeleton_Warrior_Cloak",
                          "Skeleton_Warrior_Jaw", "Skeleton_Warrior_Eyes"], "Skeleton_Warrior_Head"),
}
ANIM_SOURCE = SKE + "Skeleton_Warrior.glb"
# Exactly the clips of RIG_PLAN section 3 that the contract actions and locomotion use.
CLIPS = ["Idle", "Walking_A", "Running_A", "1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop",
         "1H_Melee_Attack_Stab", "Blocking", "Block_Hit", "Hit_A", "Hit_B", "PickUp", "Death_A",
         "Dodge_Left", "Dodge_Right", "Taunt", "Cheer"]
NO_SIDEWAYS = {"Dodge_Left", "Dodge_Right"}

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    d = Path(path).read_bytes()
    jl, = struct.unpack_from("<I", d, 12)
    j = json.loads(d[20:20 + jl])
    bl, = struct.unpack_from("<I", d, 20 + jl)
    return j, d[28 + jl:28 + jl + bl]


def acc(j, b, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    dt = np.dtype(CT[a["componentType"]])
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    if stride and stride != n * dt.itemsize:
        rows = [np.frombuffer(b, dt, n, off + k * stride) for k in range(a["count"])]
        arr = np.array(rows)
    else:
        arr = np.frombuffer(b, dt, a["count"] * n, off).reshape(a["count"], n).copy()
    return arr, a


class Out:
    """Collects accessors into one binary chunk and writes a .glb."""

    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accs = []

    def add(self, arr, typ, ctype, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr.astype(CT[ctype]))
        while len(self.bin) % 4:
            self.bin.append(0)
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": arr.nbytes}
        if target:
            v["target"] = target
        self.bin += arr.tobytes()
        self.views.append(v)
        a = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.accs.append(a)
        return len(self.accs) - 1

    def copy(self, j, b, i, target=None):
        arr, a = acc(j, b, i)
        return self.add(arr, a["type"], a["componentType"], target, "min" in a, a.get("normalized", False))

    def write(self, j, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        j["buffers"] = [{"byteLength": len(self.bin)}]
        j["bufferViews"] = self.views
        j["accessors"] = self.accs
        js = json.dumps(j, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        body = struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(self.bin)) + b"BIN\0" + bytes(self.bin)
        Path(path).write_bytes(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)


def slot_uv(uv, slot, cols=2, rows=2):
    # glTF UV origin is the image's top-left, as is the atlas's.
    return np.stack([(uv[:, 0] + slot[0]) / cols, (uv[:, 1] + slot[1]) / rows], 1)


def pack_base(src, name, tex, body_parts, head_part, out_path):
    j, b = read_glb(src)
    slot = TEXTURES[tex][1]
    o = Out()
    by_name = {n.get("name"): i for i, n in enumerate(j["nodes"])}
    new_meshes = []
    mesh_map = {}

    def prim_arrays(mi):
        p = j["meshes"][mi]["primitives"][0]
        out = {k: acc(j, b, v)[0] for k, v in p["attributes"].items()}
        return out, acc(j, b, p["indices"])[0].reshape(-1)

    def emit(arrays, idx, name_):
        attrs = {}
        attrs["POSITION"] = o.add(arrays["POSITION"], "VEC3", 5126, 34962, True)
        attrs["NORMAL"] = o.add(arrays["NORMAL"], "VEC3", 5126, 34962)
        attrs["TEXCOORD_0"] = o.add(slot_uv(arrays["TEXCOORD_0"], slot), "VEC2", 5126, 34962)
        if "JOINTS_0" in arrays:
            attrs["JOINTS_0"] = o.add(arrays["JOINTS_0"], "VEC4", 5123, 34962)
            attrs["WEIGHTS_0"] = o.add(arrays["WEIGHTS_0"], "VEC4", 5126, 34962)
        ii = o.add(idx.reshape(-1, 1), "SCALAR", 5125 if idx.max() > 65535 else 5123, 34963)
        new_meshes.append({"name": name_, "primitives": [{"attributes": attrs, "indices": ii, "material": 0}]})
        return len(new_meshes) - 1

    # Merge the skinned body parts (same skin, same material) into one primitive.
    merged, idxs, base_v = {}, [], 0
    for part in body_parts:
        arrays, idx = prim_arrays(j["nodes"][by_name[part]]["mesh"])
        for k in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
            merged.setdefault(k, []).append(arrays[k].astype(np.float32) if k != "JOINTS_0" else arrays[k].astype(np.uint16))
        idxs.append(idx.astype(np.uint32) + base_v)
        base_v += arrays["POSITION"].shape[0]
    body = emit({k: np.concatenate(v) for k, v in merged.items()}, np.concatenate(idxs), "Body")
    head_arr, head_idx = prim_arrays(j["nodes"][by_name[head_part]]["mesh"])
    head = emit(head_arr, head_idx, "Head")

    # Rigid gear (children of bone nodes): one mesh each, UVs moved to the slot.
    for i, n in enumerate(j["nodes"]):
        if "mesh" in n and "skin" not in n:
            arrays, idx = prim_arrays(n["mesh"])
            mesh_map[i] = emit(arrays, idx, n["name"])

    nodes = []
    for i, n in enumerate(j["nodes"]):
        n = dict(n)
        if "mesh" in n:
            if "skin" in n:
                if n["name"] in body_parts[1:]:
                    n.pop("mesh")
                    n.pop("skin")
                else:
                    n["mesh"] = body if n["name"] == body_parts[0] else head
                    n["name"] = "Body" if n["name"] == body_parts[0] else "Head"
            else:
                n["mesh"] = mesh_map[i]
        nodes.append(n)
    # The emptied part nodes stay as empty children of Rig, so node indices (skin joints, scene) stay valid.
    skins = []
    for s in j["skins"]:
        s = dict(s)
        s["inverseBindMatrices"] = o.copy(j, b, s["inverseBindMatrices"])
        skins.append(s)
    nj = {"asset": {"version": "2.0", "generator": "ashgrave pack_characters.py"}, "scene": 0,
          "scenes": j["scenes"], "nodes": nodes, "meshes": new_meshes, "skins": skins,
          "materials": [{"name": "kaykit_shared", "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 0.6}}]}
    o.write(nj, out_path)
    return len(new_meshes)


def pack_anims(src, out_path):
    j, b = read_glb(src)
    o = Out()
    by = {a["name"]: a for a in j["animations"]}
    miss = [c for c in CLIPS if c not in by]
    if miss:
        raise SystemExit("clips missing from %s: %s" % (src, miss))
    travel = {i for i, n in enumerate(j["nodes"]) if n.get("name") in ("root", "hips")}
    anims = []
    for c in CLIPS:
        a = by[c]
        cache = {}
        samplers = []
        for s in a["samplers"]:
            if s["input"] not in cache:
                cache[s["input"]] = o.copy(j, b, s["input"])
            samplers.append({"input": cache[s["input"]], "interpolation": s.get("interpolation", "LINEAR"),
                             "output": None, "_out": s["output"]})
        for ch in a["channels"]:
            s = samplers[ch["sampler"]]
            arr, meta = acc(j, b, s["_out"])
            if c in NO_SIDEWAYS and ch["target"].get("node") in travel and ch["target"]["path"] == "translation":
                arr = arr.copy()
                arr[:, 0] = arr[0, 0]
                arr[:, 2] = arr[0, 2]
            s["output"] = o.add(arr, meta["type"], meta["componentType"])
        for s in samplers:
            s.pop("_out")
        anims.append({"name": c, "samplers": samplers, "channels": a["channels"]})
    # Keep every node (the skeleton) but no mesh: the skin alone makes Godot build the Skeleton3D.
    nodes = []
    for n in j["nodes"]:
        n = dict(n)
        n.pop("mesh", None)
        n.pop("skin", None)
        nodes.append(n)
    skins = []
    for s in j["skins"]:
        s = dict(s)
        s["inverseBindMatrices"] = o.copy(j, b, s["inverseBindMatrices"])
        skins.append(s)
    # Godot only builds a Skeleton3D for a skin that some mesh uses: keep one degenerate skinned triangle.
    first_joint = skins[0]["joints"][0]
    tri = {"POSITION": o.add(np.zeros((3, 3), np.float32), "VEC3", 5126, 34962, True),
           "JOINTS_0": o.add(np.zeros((3, 4), np.uint16), "VEC4", 5123, 34962),
           "WEIGHTS_0": o.add(np.tile(np.array([[1, 0, 0, 0]], np.float32), (3, 1)), "VEC4", 5126, 34962)}
    nodes.append({"name": "AnimAnchor", "mesh": 0, "skin": 0})
    rig = next(i for i, n in enumerate(nodes) if n.get("name") == "Rig")
    nodes[rig]["children"] = [c for c in nodes[rig].get("children", []) if "mesh" not in j["nodes"][c]] + [len(nodes) - 1]
    nj = {"asset": {"version": "2.0", "generator": "ashgrave pack_characters.py"}, "scene": 0,
          "scenes": j["scenes"], "nodes": nodes, "skins": skins, "animations": anims,
          "meshes": [{"name": "AnimAnchor", "primitives": [{"attributes": tri}]}]}
    o.write(nj, out_path)
    return len(anims)


def pack_atlas(src, out_path, slot_px):
    atlas = Image.new("RGBA", (slot_px * 2, slot_px * 2), (0, 0, 0, 255))
    for _, (path, (cx, cy)) in TEXTURES.items():
        im = Image.open(Path(src) / path).convert("RGBA").resize((slot_px, slot_px), Image.LANCZOS)
        atlas.paste(im, (cx * slot_px, cy * slot_px))
    atlas.convert("RGB").save(out_path, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="/home/claude/assets_src/kaykit")
    ap.add_argument("--out", default=str(ROOT / "assets_src" / "rig"))
    ap.add_argument("--slot", type=int, default=256, help="pixels per character texture in the atlas")
    ap.add_argument("--bases", default="knight,skeleton_warrior")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    src = Path(args.src)
    for name in args.bases.split(","):
        f, tex, body, head = BASES[name]
        n = pack_base(src / f, name, tex, body, head, out / (name + ".glb"))
        print("%-22s %8d B  %d meshes, no clips, no image  (raw %d B)" % (name + ".glb", (out / (name + ".glb")).stat().st_size, n, (src / f).stat().st_size))
    n = pack_anims(src / ANIM_SOURCE, out / "anims.glb")
    print("%-22s %8d B  %d clips" % ("anims.glb", (out / "anims.glb").stat().st_size, n))
    pack_atlas(src, out / "atlas.png", args.slot)
    print("%-22s %8d B  %dx%d" % ("atlas.png", (out / "atlas.png").stat().st_size, args.slot * 2, args.slot * 2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
