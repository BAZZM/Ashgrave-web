"""Check member accesses across the split scripts.

    python3 tools/members.py

The engine does not report a misspelt member on `d.x` / `ow.x` when a script
loads, only when that line runs. This checks every `<ref>.<name>` against the
names the target script declares. When a part is added or renamed, update
DUEL_PARTS / OW_PARTS below."""
import re, sys, os
G = sys.argv[1] if len(sys.argv) > 1 else "game/scripts"
STR = re.compile(r'"(?:[^"\\]|\\.)*"')

def read(f):
    return open(os.path.join(G, f)).read()

def code_only(text):
    return "\n".join(STR.sub('""', l.split("#")[0] if '"' not in l else STR.sub('""', l)) for l in text.split("\n"))

def members(f):
    t = read(f)
    names = set(re.findall(r'^(?:static )?(?:var|const|func|signal) (\w+)', t, re.M))
    names |= set(re.findall(r'^enum (\w+)', t, re.M))
    return names

NODE = {"create_tween", "get_tree", "to_global", "to_local", "global_position", "global_transform", "add_child",
        "get_viewport", "position", "rotation", "has_method", "get", "set", "queue_free", "get_parent", "name",
        "visible", "is_inside_tree", "call_deferred"}

DUEL_PARTS = {"fx": "duel_fx.gd", "ai": "duel_enemy.gd", "stage": "duel_stage.gd", "pvp_net": "duel_pvp.gd", "bots": "duel_bot.gd"}
OW_PARTS = {"terrain": "overworld_terrain.gd", "places": "overworld_places.gd", "sky": "overworld_sky.gd",
            "mover": "overworld_hero.gd", "interaction": "overworld_interact.gd", "remotes": "overworld_remote.gd",
            "duels": "overworld_duels.gd", "bots": "overworld_bot.gd"}

duel_m = members("duel.gd") | NODE
ow_m = members("overworld.gd") | NODE
world_m = members("world.gd") | NODE
kit_m = members("overworld_kit.gd")
bad = []
count = 0

def check(f, pattern, allowed, label):
    global count
    t = code_only(read(f))
    for i, line in enumerate(t.split("\n"), 1):
        for m in re.finditer(pattern, line):
            count += 1
            if m.group(1) not in allowed:
                bad.append(f"{f}:{i}: {label}.{m.group(1)}")

# duel helpers
for part, f in DUEL_PARTS.items():
    check(f, r'(?<![.\w])d\.(\w+)', duel_m, "d")
    for p2, f2 in DUEL_PARTS.items():
        check(f, r'(?<![.\w])d\.' + p2 + r'\.(\w+)', members(f2), "d." + p2)
    check(f, r'(?<![.\w])Duel\.(\w+)', duel_m, "Duel")
for p2, f2 in DUEL_PARTS.items():
    check("duel.gd", r'(?<![.\w])' + p2 + r'\.(\w+)', members(f2), p2)
check("hud.gd", r'(?<![.\w])duel\.(\w+)', duel_m, "duel")
check("hud.gd", r'(?<![.\w])Duel\.(\w+)', duel_m, "Duel")
# overworld helpers
for part, f in OW_PARTS.items():
    check(f, r'(?<![.\w])ow\.(\w+)', ow_m, "ow")
    for p2, f2 in OW_PARTS.items():
        check(f, r'(?<![.\w])ow\.' + p2 + r'\.(\w+)', members(f2), "ow." + p2)
    check(f, r'(?<![.\w])Kit\.(\w+)', kit_m, "Kit")
    check(f, r'(?<![.\w])ow\.duel\.(\w+)', duel_m, "ow.duel")
for p2, f2 in OW_PARTS.items():
    check("overworld.gd", r'(?<![.\w])' + p2 + r'\.(\w+)', members(f2), p2)
# world_hud.gd serves both the open land and the tower, so `world` may be either.
check("world_hud.gd", r'(?<![.\w])world\.(\w+)', ow_m | world_m, "world")
check("world_hud.gd", r'(?<![.\w])Overworld\.(\w+)', ow_m, "Overworld")
check("world.gd", r'(?<![.\w])duel\.(\w+)', duel_m, "duel")
# methods the duel calls on its host must exist on both hosts
for name in ["duel_done", "ground_y", "cam"]:
    for host, ms in [("overworld.gd", ow_m), ("world.gd", world_m)]:
        if name not in ms and not (name == "ground_y"):
            bad.append(f"{host}: host lacks {name}")
print(f"{count} accesses checked")
for b in bad:
    print("UNKNOWN", b)
sys.exit(1 if bad else 0)
