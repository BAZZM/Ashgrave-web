#!/usr/bin/env python3
"""Independent oracle for Hold'em pot distribution and blackjack settlement.

Deliberately simple and written separately from the GDScript engine: it sees
only what the property runs export (t_props.gd, one JSON line per hand or
round) and recomputes who should be paid what from first principles.

Hold'em (<hands.tsv>.pots, rebuilt from each hand's raw event log):
  * contribution = chips posted/committed minus chips returned as uncalled;
  * no seat may end a hand with chips nobody matched (the largest
    contribution equals the second largest);
  * pots are peeled off one layer at a time: take the smallest remaining
    contribution among live hands, everybody (folded or not) pays up to it,
    live hands that paid it are eligible; folded chips above every live hand
    would be an error;
  * each pot goes to the best hand among its eligible seats (7-card hands
    scored by ref_eval's brute-force evaluator), odd chips one at a time to
    winners clockwise from the seat left of the button; uncontested hands
    give everything to the last live seat.
Blackjack (<hands.tsv>.bj): 6-deck house rules from docs/CASINO_CORE.md:
  * totals: aces count 1, one ace becomes 11 if that does not bust;
  * natural = two cards, 21, not from a split; pays 3:2 rounded down; push
    against a dealer natural; a dealer natural beats everything else;
  * insurance at most half the original bet (rounded down), only under an
    ace, pays 2:1;
  * dealer stands on all 17s and draws nothing when every hand is bust or a
    natural; split aces get exactly one card; doubles get exactly one card;
  * at most four hands; the seat's stack change must equal the sum.

Usage: oracle.py <hands.tsv>   Exit 1 on any mismatch.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_eval import best7  # noqa: E402  (brute-force 7-card scoring, not the engine's)


# ------------------------------------------------------------------ Hold'em

def holdem_expected(h):
    """Returns (expected winnings by seat, list of problems)."""
    problems = []
    n = h["n"]
    button = h["button"]
    seats = sorted(int(k) for k in h["hole"])
    folded = set(h["folded"])
    contrib = {s: h["commit"].get(str(s), 0) - h["uncalled"].get(str(s), 0) for s in seats}
    live = [s for s in seats if s not in folded]
    amounts = sorted(contrib.values(), reverse=True)
    if len(amounts) >= 2 and amounts[0] != amounts[1]:
        problems.append("unmatched chips left in the pot: %s" % contrib)
    total = sum(contrib.values())
    if len(live) == 1:
        return {live[0]: total}, problems
    board = h["board"]
    if len(board) != 5:
        problems.append("showdown without a full board")
        return {}, problems
    score = {s: best7(h["hole"][str(s)] + board) for s in live}
    remaining = dict(contrib)
    won = {}
    while any(remaining[s] > 0 for s in live):
        step = min(remaining[s] for s in live if remaining[s] > 0)
        eligible = [s for s in live if remaining[s] > 0]
        pot = 0
        for s in seats:
            take = min(remaining[s], step)
            remaining[s] -= take
            pot += take
        best = max(score[s] for s in eligible)
        winners = [s for s in eligible if score[s] == best]
        # Clockwise from the seat left of the button.
        order = [(button + k) % n for k in range(1, n + 1)]
        winners.sort(key=order.index)
        share, odd = divmod(pot, len(winners))
        for k, s in enumerate(winners):
            won[s] = won.get(s, 0) + share + (1 if k < odd else 0)
    dead = sum(remaining.values())
    if dead:
        problems.append("%d folded chips above every live hand" % dead)
    return won, problems


def check_holdem(path):
    hands = bad = showdowns = multi = 0
    for line in open(path):
        if not line.strip():
            continue
        h = json.loads(line)
        hands += 1
        want, problems = holdem_expected(h)
        got = {int(k): v for k, v in h["won"].items() if v}
        want = {k: v for k, v in want.items() if v}
        if len([s for s in h["hole"] if int(s) not in set(h["folded"])]) > 1:
            showdowns += 1
            if len(set(h["commit"].get(s, 0) - h["uncalled"].get(s, 0) for s in h["hole"])) > 2:
                multi += 1
        if got != want or problems:
            bad += 1
            if bad <= 10:
                print("HOLDEM ORACLE MISMATCH", problems, "engine", got, "oracle", want, json.dumps(h))
    return hands, showdowns, multi, bad


# ------------------------------------------------------------------ Blackjack

def card_value(c):
    r = c >> 2
    if r == 12:
        return 1  # ace, low; promoted below
    return 10 if r >= 8 else r + 2


def bj_total(cards):
    t = sum(card_value(c) for c in cards)
    has_ace = any(c >> 2 == 12 for c in cards)
    if has_ace and t + 10 <= 21:
        return t + 10, True
    return t, False


def check_round(rd):
    problems = []
    dealer = rd["dealer"]
    dt = bj_total(dealer)[0]
    dealer_nat = len(dealer) == 2 and dt == 21
    up_is_ace = dealer[0] >> 2 == 12
    any_live = False
    for s in rd["seats"]:
        for hd in s["hands"]:
            nat = not hd["split"] and len(hd["cards"]) == 2 and bj_total(hd["cards"])[0] == 21
            if bj_total(hd["cards"])[0] <= 21 and not nat:
                any_live = True
    # Dealer drawing.
    if dealer_nat or not any_live:
        if len(dealer) != 2:
            problems.append("dealer drew with nothing to play for")
    else:
        for k in range(2, len(dealer)):
            if bj_total(dealer[:k])[0] >= 17:
                problems.append("dealer hit %d" % bj_total(dealer[:k])[0])
        if dt < 17:
            problems.append("dealer stood on %d" % dt)
    for s in rd["seats"]:
        orig = s["orig"]
        net = 0
        hands = s["hands"]
        if len(hands) > 4:
            problems.append("more than four hands")
        if s["ins"] > orig // 2:
            problems.append("insurance %d over half of %d" % (s["ins"], orig))
        if s["ins"] > 0 and not up_is_ace:
            problems.append("insurance without an ace up")
        if s["ins"] > 0:
            net += 2 * s["ins"] if dealer_nat else -s["ins"]
        for hd in hands:
            cards = hd["cards"]
            bet = hd["bet"]
            if bet != orig * (2 if hd["doubled"] else 1):
                problems.append("hand bet %d for original %d" % (bet, orig))
            if hd["doubled"] and len(cards) != 3:
                problems.append("double drew %d cards" % (len(cards) - 2))
            if hd["split_aces"] and (len(cards) != 2 or hd["doubled"]):
                problems.append("split ace played on")
            pt = bj_total(cards)[0]
            nat = not hd["split"] and len(cards) == 2 and pt == 21
            if nat:
                net += 0 if dealer_nat else (bet * 3) // 2
            elif dealer_nat or pt > 21:
                net -= bet
            elif dt > 21 or pt > dt:
                net += bet
            elif pt < dt:
                net -= bet
        if s["after"] - s["before"] != net:
            problems.append("seat %d stack moved %d, rules say %d" % (s["seat"], s["after"] - s["before"], net))
    return problems


def check_bj(path):
    rounds = bad = hands = 0
    for line in open(path):
        if not line.strip():
            continue
        rd = json.loads(line)
        rounds += 1
        hands += sum(len(s["hands"]) for s in rd["seats"])
        problems = check_round(rd)
        if problems:
            bad += 1
            if bad <= 10:
                print("BLACKJACK ORACLE MISMATCH", problems, json.dumps(rd))
    return rounds, hands, bad


def main():
    base = sys.argv[1]
    hands, showdowns, multi, bad_h = check_holdem(base + ".pots")
    print(f"python oracle holdem: {hands} hands, {showdowns} contested, {multi} with side pots, {bad_h} mismatches")
    rounds, bj_hands, bad_b = check_bj(base + ".bj")
    print(f"python oracle blackjack: {rounds} rounds, {bj_hands} hands, {bad_b} mismatches")
    if bad_h or bad_b or hands < 1000 or rounds < 1000:
        print("PYTHON ORACLE FAILED")
        sys.exit(1)
    print("PYTHON ORACLE OK")


if __name__ == "__main__":
    main()
