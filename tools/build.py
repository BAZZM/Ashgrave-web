#!/usr/bin/env python3
"""Pack game/ into the data file the web page loads.

Writes game_<hash>.wasm (a Godot 4.4 pack, despite the extension) at the repo
root, points index.html at it, and removes the previous pack. The engine itself
(part0-2.wasm) is the stock Godot 4.4.1 web build and is not rebuilt here.

    python3 tools/build.py                # build the release pack
    python3 tools/build.py --check        # exit 1 if the committed pack is stale
    python3 tools/build.py --looktest     # a test pack that also holds the look-test-only textures and the rig (never commit its output)
    python3 tools/build.py --rig          # a test pack with the rig (R2: the hero as RigVisual behind --rig / ?rig=1) but not the look-test textures

The release pack holds only the textures the real game samples (SHIPPED_TEXTURES: the ground and water grain packs,
the ripple map and the tree grains). The other imported textures under game/assets/textures/ (walls, wood, bark, leaf, armour, banner,
the colour sources) are used only by the debug look-test scene; their .import files and imported forms are left out
unless --looktest is given, and the look test then falls back to flat (tex_kit.gd).

The rig (docs/RIG_PLAN.md stages R1 and R2) is left out of the release pack too: everything under assets/rig/ (remaps and
imported meshes, clips, atlas), the KayKit probe's imports under assets/kaykit/, and the rig scripts (RIG_SCRIPTS) are
left out unless --looktest or --rig is given (--rig keeps the look-test textures out). The game code that switches to the rig
(fighter_visual.gd) is in the release pack but loads nothing of it without the flag and the files. To ship the rig, make
rig_paths() return an empty set.
"""
import hashlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
INDEX = ROOT / "index.html"
GODOT_VERSION = (4, 4, 1)
ALIGN = 16
TEX_DIR = "assets/textures/"
SHIPPED_TEXTURES = {"packed/terrain_a", "packed/terrain_b", "packed/ripple", "packed/trees"}
RIG_DIRS = ("assets/rig/", "assets/kaykit/")  # the rig, and the KayKit probe's imports (lane p1, --looktest=wide|close|...)
RIG_SCRIPTS = {"scripts/rig_visual.gd", "scripts/rig_clips.gd", "scripts/rig_looks.gd", "scripts/rig_check.gd", "scripts/rig_looktest.gd", "scripts/rig_cycle.gd"}


def pad(n: int, to: int) -> int:
    return -n % to


def import_paths(imp: Path) -> set:
    out = {imp.relative_to(GAME).as_posix()}
    for m in re.finditer(r'res://([^"]+)', "\n".join(l for l in imp.read_text().splitlines() if l.startswith("path=") or l.startswith("dest_files="))):
        out.add(m.group(1))
    return out


def rig_paths(probe_only: bool = False) -> set:
    """Pack paths of the rig: the imported assets (remaps and imported forms), the KayKit probe's, and the rig scripts.
    probe_only: just the KayKit probe's imports (assets/kaykit/, 1.24 MB nothing but --looktest uses)."""
    out = set()
    for imp in [i for d in (RIG_DIRS[1:] if probe_only else RIG_DIRS) for i in (GAME / d).rglob("*.import")]:
        out |= import_paths(imp)
    return out if probe_only else out | RIG_SCRIPTS


def look_test_only() -> set:
    """Pack paths of the imported textures the real game does not use: their .import remap and imported (.ctex) files."""
    out = set()
    for imp in (GAME / TEX_DIR).rglob("*.import"):
        rel = imp.relative_to(GAME / TEX_DIR).as_posix()[: -len(".png.import")]
        if rel in SHIPPED_TEXTURES:
            continue
        out |= import_paths(imp)
    return out


def build_pack(with_looktest: bool = False, with_rig: bool = False) -> bytes:
    skip = (set() if with_looktest else look_test_only()) | (set() if with_looktest or with_rig else rig_paths())
    if with_rig and not with_looktest:
        skip |= rig_paths(probe_only=True)  # the rig pack leaves the probe's imports out
    files = sorted(
        (p.relative_to(GAME).as_posix(), p.read_bytes())
        for p in GAME.rglob("*")
        if p.is_file() and p.relative_to(GAME).as_posix() not in skip
    )
    names = [name.encode() + b"\0" * (pad(len(name.encode()), 4) or 4) for name, _ in files]
    dir_size = 4 + sum(4 + len(n) + 8 + 8 + 16 + 4 for n in names)
    header_size = 4 + 4 * 4 + 4 + 8 + 16 * 4
    base = header_size + dir_size
    base += pad(base, ALIGN)

    directory = struct.pack("<I", len(files))
    blob = b""
    for (_, data), name in zip(files, names):
        blob += b"\0" * pad(len(blob), ALIGN)
        directory += struct.pack("<I", len(name)) + name
        directory += struct.pack("<QQ", len(blob), len(data))
        directory += hashlib.md5(data).digest() + struct.pack("<I", 0)
        blob += data

    header = b"GDPC" + struct.pack("<4I", 2, *GODOT_VERSION)
    header += struct.pack("<IQ", 0, base) + b"\0" * 64
    head = header + directory
    return head + b"\0" * (base - len(head)) + blob


def main() -> int:
    pack = build_pack("--looktest" in sys.argv, "--rig" in sys.argv)
    name = "game_%s.wasm" % hashlib.sha1(pack).hexdigest()[:10]
    html = INDEX.read_text()
    current = re.search(r"game_[0-9a-f]{10}\.wasm", html).group(0)
    new_html = html.replace(current, name)
    new_html, n = re.subn(r'"index\.pck":\d+', '"index.pck":%d' % len(pack), new_html)
    assert n == 1, "index.html no longer has the pack size in GODOT_CONFIG"

    if "--check" in sys.argv:
        ok = current == name and (ROOT / name).is_file() and (ROOT / name).read_bytes() == pack
        print("up to date" if ok else "stale: run tools/build.py")
        return 0 if ok else 1

    for old in ROOT.glob("game_*.wasm"):
        if old.name != name:
            old.unlink()
    (ROOT / name).write_bytes(pack)
    INDEX.write_text(new_html)
    print("%s  %d bytes  (was %s)" % (name, len(pack), current))
    return 0


if __name__ == "__main__":
    sys.exit(main())
