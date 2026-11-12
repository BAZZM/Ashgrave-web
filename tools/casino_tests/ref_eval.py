#!/usr/bin/env python3
"""Independent reference for the casino core.

1. Brute-force poker evaluator: scores all 21 five-card subsets of each exported
   7-card hand with a separate, textbook 5-card ranking, and checks that it puts
   the hands in exactly the same order (and the same categories) as the GDScript
   evaluator.
2. Re-implements the RNG (xoshiro128** seeded by splitmix32, rejection-sampled
   bounded draws, Fisher-Yates) and checks the GDScript stream bit for bit.

Usage: ref_eval.py <hands.tsv>   (hands.tsv.rng is read too). Exit 1 on mismatch.
"""
import sys
import time
from collections import Counter
from itertools import combinations

M = 0xFFFFFFFF


def eval5(cards):
    """(category, tiebreak tuple) for 5 cards; card = rank*4 + suit, rank 0=2..12=A."""
    ranks = sorted((c >> 2 for c in cards), reverse=True)
    suits = {c & 3 for c in cards}
    flush = len(suits) == 1
    uniq = sorted(set(ranks), reverse=True)
    straight_top = None
    if len(uniq) == 5:
        if uniq[0] - uniq[4] == 4:
            straight_top = uniq[0]
        elif uniq == [12, 3, 2, 1, 0]:
            straight_top = 3
    cnt = Counter(ranks)
    groups = sorted(cnt.items(), key=lambda kv: (kv[1], kv[0]), reverse=True)
    shape = [g[1] for g in groups]
    order = tuple(g[0] for g in groups)
    if straight_top is not None and flush:
        return (8, (straight_top,))
    if shape == [4, 1]:
        return (7, order)
    if shape == [3, 2]:
        return (6, order)
    if flush:
        return (5, tuple(ranks))
    if straight_top is not None:
        return (4, (straight_top,))
    if shape == [3, 1, 1]:
        return (3, order)
    if shape == [2, 2, 1]:
        return (2, order)
    if shape == [2, 1, 1, 1]:
        return (1, order)
    return (0, tuple(ranks))


def best7(cards):
    return max(eval5(c) for c in combinations(cards, 5))


# ---- RNG mirror
def mul32(a, b):
    return (a * b) & M


def rotl(x, k):
    return ((x << k) | (x >> (32 - k))) & M


class Rng:
    def __init__(self, seed):
        lo = seed & M
        hi = (seed >> 32) & M
        sm = (lo ^ mul32(hi, 0x85EBCA6B)) & M
        self.s = []
        for _ in range(4):
            sm = (sm + 0x9E3779B9) & M
            z = sm
            z = mul32(z ^ (z >> 16), 0x85EBCA6B)
            z = mul32(z ^ (z >> 13), 0xC2B2AE35)
            self.s.append((z ^ (z >> 16)) & M)
        if self.s == [0, 0, 0, 0]:
            self.s[0] = 1

    def next_u32(self):
        s0, s1, s2, s3 = self.s
        result = mul32(rotl(mul32(s1, 5), 7), 9)
        t = (s1 << 9) & M
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = rotl(s3, 11)
        self.s = [s0, s1, s2, s3]
        return result

    def next_below(self, n):
        if n <= 1:
            return 0
        threshold = (2**32 - n) % n
        while True:
            x = self.next_u32()
            if x >= threshold:
                return x % n

    def shuffle(self, a):
        for i in range(len(a) - 1, 0, -1):
            j = self.next_below(i + 1)
            a[i], a[j] = a[j], a[i]


def check_rng(path):
    bad = 0
    lines = open(path).read().split("\n")
    n = 0
    for line in lines:
        if not line.strip():
            continue
        seed, vals, bel, deck = line.split("\t")
        r = Rng(int(seed))
        want_vals = [r.next_u32() for _ in range(8)]
        want_bel = [r.next_below(k) for k in [1, 2, 3, 7, 10, 52, 37, 1000003, 0x80000001]]
        d = list(range(52))
        r.shuffle(d)
        got = ([int(x) for x in vals.split(",")], [int(x) for x in bel.split(",")], [int(x) for x in deck.split(",")])
        if got != (want_vals, want_bel, d):
            bad += 1
            print("RNG MISMATCH seed", seed)
        n += 1
    return n, bad


def main():
    path = sys.argv[1]
    t0 = time.time()
    n_rng, bad_rng = check_rng(path + ".rng")
    print(f"python rng: {n_rng} seeds checked (u32 stream, bounded draws, shuffle), {bad_rng} mismatches")
    rows = []
    for line in open(path):
        if not line.strip():
            continue
        cs, v, cat = line.rstrip("\n").split("\t")
        cards = [int(x) for x in cs.split()]
        rows.append((int(v), int(cat), best7(cards), cards))
    bad = 0
    for v, cat, ref, cards in rows:
        if ref[0] != cat:
            bad += 1
            if bad < 10:
                print("CATEGORY MISMATCH", cards, cat, ref)
    # Same total order: sort by the GDScript value; reference keys must be
    # non-decreasing, and equal exactly where the GDScript values are equal.
    rows.sort(key=lambda r: r[0])
    order_bad = 0
    for a, b in zip(rows, rows[1:]):
        if (a[0] == b[0]) != (a[2] == b[2]) or (a[0] < b[0] and not a[2] < b[2]):
            order_bad += 1
            if order_bad < 10:
                print("ORDER MISMATCH", a[3], a[0], a[2], "|", b[3], b[0], b[2])
    classes = len({r[0] for r in rows})
    print(f"python evaluator: {len(rows)} hands, {classes} distinct ranks, "
          f"{bad} category mismatches, {order_bad} ordering mismatches, {time.time() - t0:.1f} s")
    if len(rows) < 100000 or bad or order_bad or bad_rng or n_rng == 0:
        print("PYTHON CROSS-CHECK FAILED")
        sys.exit(1)
    print("PYTHON CROSS-CHECK OK")


if __name__ == "__main__":
    main()
