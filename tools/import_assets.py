#!/usr/bin/env python3
"""Import source assets (.glb, .png, ...) from assets_src/ into game/ with headless Godot.

    python3 tools/import_assets.py [--godot PATH]      # default PATH: $GODOT or /home/claude/godot/...

Sources live in assets_src/<path> (git-ignored, never packed) and appear to the
engine as res://assets/<path>. The import runs in a throwaway copy of game/, so
Godot can never rewrite or delete the existing sounds, font, scenes, uid cache
or project.godot. Only these results are copied back into game/:
  game/assets/<path>.import            remap files the runtime needs (commit them)
  game/.godot/imported/<hash>.scn/.ctex  the imported forms (commit them)
  game/.godot/uid_cache.bin            original entries kept, res://assets/ entries merged in
Nothing is written when assets_src/ is empty. Re-run after any source change.
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
SRC = ROOT / "assets_src"
DEFAULT_GODOT = "/home/claude/godot/Godot_v4.4.1-stable_linux.x86_64"
RAW = {".glb", ".gltf", ".png", ".jpg", ".jpeg", ".webp", ".wav", ".ogg"}


def read_uids(path: Path):
    d = path.read_bytes()
    n, = struct.unpack_from("<I", d, 0)
    o, out = 4, []
    for _ in range(n):
        uid, ln = struct.unpack_from("<qi", d, o)
        o += 12
        out.append((uid, d[o:o + ln].decode()))
        o += ln
    return out


def write_uids(path: Path, entries):
    b = struct.pack("<I", len(entries))
    for uid, p in entries:
        e = p.encode()
        b += struct.pack("<qi", uid, len(e)) + e
    path.write_bytes(b)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    args = ap.parse_args()
    sources = sorted(p for p in SRC.rglob("*") if p.is_file() and p.suffix.lower() in RAW) if SRC.is_dir() else []
    if not sources:
        print("no sources in assets_src/; nothing to import")
        return 0

    with tempfile.TemporaryDirectory(prefix="ashgrave-import-") as tmp:
        stage = Path(tmp) / "game"
        shutil.copytree(GAME, stage)
        for s in sources:
            dst = stage / "assets" / s.relative_to(SRC)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, dst)
        # Re-import the sources from scratch. Leaving their old .import files (and uids) in the stage makes
        # Godot log "Invalid UID"/"Unrecognized UID" and sometimes fail to open the old output, so a second
        # run after a source change failed. Other assets (e.g. assets/test) are left alone.
        stems = {(s.parent, s.stem) for s in sources}
        gone = set()
        for imp in list((stage / "assets").rglob("*.import")):
            name = imp.name[:-len(".import")]
            own = (SRC / imp.relative_to(stage / "assets").parent / name).is_file()
            ext = any(name.startswith(stem + "_") and imp.parent == (stage / "assets" / par.relative_to(SRC)) for par, stem in stems)
            if own or ext:
                gone.add("res://" + imp.relative_to(stage).as_posix()[:-len(".import")])
                imp.unlink()
        stage_cache = stage / ".godot" / "uid_cache.bin"
        write_uids(stage_cache, [e for e in read_uids(stage_cache) if e[1] not in gone])
        r = subprocess.run([args.godot, "--headless", "--path", str(stage), "--import"],
                           capture_output=True, text=True, timeout=600)
        log = r.stdout + r.stderr
        # The dummy headless renderer logs one harmless "texture_2d_get ... null" error per imported texture.
        bad = [l for l in log.splitlines()
               if re.search(r"ERROR|Failed|failed", l) and "texture_2d_get" not in l and "Parameter \"t\" is null" not in l]
        if r.returncode != 0 or bad:
            print(log)
            print("godot import failed")
            return 1
        if (stage / "project.godot").read_bytes() != (GAME / "project.godot").read_bytes():
            shutil.copy2(stage / "project.godot", ROOT / "project.godot.wanted")
            print("Godot wanted to change project.godot; wrote project.godot.wanted, game/project.godot untouched")

        # Every .import under assets/ in the stage (sources plus files the importer extracted, e.g. glb textures).
        copied = []
        for imp in sorted((stage / "assets").rglob("*.import")):
            rel = imp.relative_to(stage)
            text = imp.read_text()
            dests = re.search(r'dest_files=\[(.*?)\]', text).group(1)
            files = re.findall(r'"res://([^"]+)"', dests)
            out = GAME / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(imp, out)
            for f in files:
                (GAME / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(stage / f, GAME / f)
            copied.append((rel.as_posix(), files))

        # uid cache: keep every original entry; only res://assets/ entries come from the stage.
        cache = GAME / ".godot" / "uid_cache.bin"
        old = read_uids(cache)
        new = [(u, p) for u, p in read_uids(stage / ".godot" / "uid_cache.bin") if p.startswith("res://assets/")]
        merged = [e for e in old if not e[1].startswith("res://assets/")] + new
        if merged != old:
            write_uids(cache, merged)
    for rel, files in copied:
        print(rel, "->", ", ".join(Path(f).name for f in files))
    print("imported %d file(s); uid cache has %d asset entries" % (len(copied), len(new)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
