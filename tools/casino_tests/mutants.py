#!/usr/bin/env python3
"""Mutation check for the casino rules engine.

Each mutant changes ONE line of a rule in a temporary copy of
game/scripts/casino + tools/casino_tests, then runs the suite there
(QUICK=1 FAILFAST=1 by default). A mutant is killed when the suite fails.
The repo itself is never modified.

Usage: mutants.py <godot> [name-substring ...]     Exit 1 if any survive.
Set FULL=1 to run each mutant against the full-size suite, SKIP=vectors to
see what the scenario tests, property runs and oracles catch without the
golden vectors. Mutants named [equivalent] are reported but not counted.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# (name, file under game/scripts/casino, exact line text, replacement)
MUTANTS = [
    # The review's four.
    ("raise_rights >= to >", "holdem.gd",
     "	return at < 0 or current_bet - at >= last_raise",
     "	return at < 0 or current_bet - at > last_raise"),
    ("folded chips all in main pot", "holdem.gd",
     "			amt += clampi(t, prev, lv) - prev",
     "			amt += (clampi(t, prev, lv) - prev) if _live(i) else (t if prev == 0 else 0)"),
    ("soft total while to if", "blackjack.gd",
     "	while t > 21 and aces > 0:",
     "	if t > 21 and aces > 0:"),
    ("insurance cap doubled", "blackjack.gd",
     '	var cap: int = s["hands"][0]["bet"] / 2',
     '	var cap: int = s["hands"][0]["bet"]'),
    # Reverting this round's fixes.
    ("revert: leaver forfeits uncalled", "holdem.gd",
     "	if top < 0:",
     "	if top < 0 or not _live(top):"),
    ("revert: roulette limit table-wide", "roulette.gd",
     '		if b0["seat"] == seat:',
     "		if true:"),
    ("revert: top-up ignores min buy-in", "holdem.gd",
     '	if amt == null or amt <= 0 or stack(seat) + amt > cfg["max_buy_in"] or stack(seat) + amt < cfg["min_buy_in"]:',
     '	if amt == null or amt <= 0 or stack(seat) + amt > cfg["max_buy_in"]:'),
    ("revert: one name many seats", "holdem.gd",
     '		if s["player"] == p:',
     "		if false:"),
    ("revert: next_below accepts n > 2^32", "rng.gd",
     "	if n < 1 or n > 0x100000000:",
     "	if n < 1:"),
    ("seed event sent to clients", "holdem.gd",
     '		if e.get("type", "") == "seed":',
     "		if false:"),
    ("holdem: only the first hand reseeds", "holdem.gd",
     "	rng.seed_128(words)",
     "	rng.seed_128(words if hand_no == 1 else [1, 2, 3, 4])"),
    ("roulette: spins continue one stream", "roulette.gd",
     "	rng.seed_128(words)",
     "	var _once: bool = rng.seed_128(words) if spins == 0 else true"),
    ("rng: word 3 ignored", "rng.gd",
     "		s[i] = _fmix32((int(w[i]) + GOLDEN * (i + 1)) & M32)",
     "		s[i] = _fmix32((int(w[i % 3]) + GOLDEN * (i + 1)) & M32)"),
    ("blackjack: shoe seed revealed at once", "blackjack.gd",
     '		pending_reveal.append([shoe_no, String(shoe["seed"])])',
     '		chips.log_event("seed_reveal", {"unit": "shoe", "shoe": shoe_no, "seed": String(shoe["seed"])})'),
    # Other rules.
    ("holdem: min raise needs more than last raise", "holdem.gd",
     "			var full := inc >= last_raise",
     "			var full := inc > last_raise"),
    ("holdem: short all-in reopens", "holdem.gd",
     "			if full:",
     "			if true:"),
    ("holdem: odd chip to the last winner", "holdem.gd",
     "			var got := share + (1 if k < odd else 0)",
     "			var got := share + (1 if k >= ordered.size() - odd else 0)"),
    ("holdem: uncalled off by one", "holdem.gd",
     '	var back: int = seats[top]["bet"] - second',
     '	var back: int = seats[top]["bet"] - second - 1'),
    ("holdem: heads-up big blind on button", "holdem.gd",
     "		sb_seat = button",
     "		sb_seat = _next(button, in_hand)"),
    ("blackjack: 3:2 rounds up", "blackjack.gd",
     "					win = bet * 3 / 2  # 3:2, rounded down to the chip",
     "					win = (bet * 3 + 1) / 2"),
    ("blackjack: dealer hits soft 17", "blackjack.gd",
     "	while total(dealer)[0] < 17:",
     "	while total(dealer)[0] < 17 or (total(dealer)[0] == 17 and total(dealer)[1]):"),
    ("blackjack: split aces play on", "blackjack.gd",
     "			if aces:",
     "			if false:"),
    ("blackjack: ten-values do not split together", "blackjack.gd",
     "		if card_value(cards[0]) == card_value(cards[1]) and seats[seat][\"hands\"].size() < MAX_HANDS \\",
     "		if cards[0] >> 2 == cards[1] >> 2 and seats[seat][\"hands\"].size() < MAX_HANDS \\"),
    # Equivalent (unreachable): split aces are marked done when dealt, so a
    # split-ace hand never gets a turn and the guard cannot be observed.
    ("blackjack: aces may resplit [equivalent]", "blackjack.gd",
     '				and not (h["split_aces"]):',
     "				and true:"),
    ("blackjack: no double after split", "blackjack.gd",
     '	if cards.size() == 2 and stack(seat) >= h["bet"]:',
     '	if cards.size() == 2 and stack(seat) >= h["bet"] and not h["split"]:'),
    ("blackjack: split 21 counts as natural", "blackjack.gd",
     '	return not h["split"] and (h["cards"] as Array).size() == 2 and total(h["cards"])[0] == 21',
     '	return (h["cards"] as Array).size() == 2 and total(h["cards"])[0] == 21'),
    ("roulette: zero wins outside bets", "roulette.gd",
     "	for n in range(1, 37):\n		var hit := false",
     "	for n in range(0, 37):\n		var hit := false"),
    ("roulette: basket 6:1 on European", "roulette.gd",
     '		"basket": return 6 if american() else 8',
     '		"basket": return 6'),
    ("roulette: split pays 18", "roulette.gd",
     '		"split": return 17',
     '		"split": return 18'),
]


def run_one(godot, name, fname, old, new, full):
    tmp = tempfile.mkdtemp(prefix="casino_mut_")
    try:
        shutil.copytree(os.path.join(REPO, "game", "scripts", "casino"), os.path.join(tmp, "game", "scripts", "casino"))
        shutil.copytree(HERE, os.path.join(tmp, "tools", "casino_tests"))
        path = os.path.join(tmp, "game", "scripts", "casino", fname)
        src = open(path).read()
        n = src.count(old)
        if n != 1:
            return "BAD (%d matches)" % n, 0.0
        open(path, "w").write(src.replace(old, new))
        env = dict(os.environ, FAILFAST="1")
        if not full:
            env["QUICK"] = "1"
        t0 = time.time()
        p = subprocess.run([os.path.join(tmp, "tools", "casino_tests", "run.sh"), godot], env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        dt = time.time() - t0
        out = p.stdout
        if p.returncode == 0:
            return "SURVIVED", dt
        fails = [l.strip() for l in out.splitlines() if "FAIL [" in l or "MISMATCH" in l or "SCRIPT ERROR" in l]
        return "killed: " + (fails[0][:110] if fails else out.strip().splitlines()[-1]), dt
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    godot = sys.argv[1]
    pick = sys.argv[2:]
    full = bool(os.environ.get("FULL"))
    killed = total = 0
    survivors = []
    for name, fname, old, new in MUTANTS:
        if pick and not any(p in name for p in pick):
            continue
        res, dt = run_one(godot, name, fname, old, new, full)
        print("%-48s %6.0fs  %s" % (name, dt, res), flush=True)
        if "[equivalent]" in name:
            continue
        total += 1
        if res.startswith("killed"):
            killed += 1
        else:
            survivors.append(name)
    print("mutants killed: %d/%d" % (killed, total))
    if survivors:
        print("survivors:", ", ".join(survivors))
        sys.exit(1)


if __name__ == "__main__":
    main()
