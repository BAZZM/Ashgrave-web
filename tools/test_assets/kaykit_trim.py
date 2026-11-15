#!/usr/bin/env python3
"""Copy a .glb keeping only the named animation clips (the rest of the file is untouched).

    python3 -I tools/test_assets/kaykit_trim.py IN.glb OUT.glb Idle Block Hit_A ...

KayKit character files carry 76-95 clips each (about 1.3-1.9 MB imported); a probe or a
shipped build only needs a few. Unreferenced accessors stay in the binary chunk, which
Godot ignores. Prints the clips kept and any name that was not found.
"""
import json
import struct
import sys


def main() -> int:
    src, dst, *keep = sys.argv[1:]
    d = open(src, "rb").read()
    jl, = struct.unpack_from("<I", d, 12)
    j = json.loads(d[20:20 + jl])
    rest = d[20 + jl:]
    by = {a["name"]: a for a in j.get("animations", [])}
    miss = [k for k in keep if k not in by]
    j["animations"] = [by[k] for k in keep if k in by]
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = d[:8] + struct.pack("<I", 12 + 8 + len(js) + len(rest)) + struct.pack("<I", len(js)) + b"JSON" + js + rest
    open(dst, "wb").write(out)
    print("kept", [a["name"] for a in j["animations"]], "missing", miss)
    return 1 if miss else 0


if __name__ == "__main__":
    sys.exit(main())
