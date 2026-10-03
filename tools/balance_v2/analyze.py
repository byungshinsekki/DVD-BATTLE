"""V2 balance (H-BALANCE): analyzer for forced-hero runs (tools/balance_v2/forced_runner.gd).

usage:
  py analyze.py summary <jsonl glob> [...]          forced-hero win rate, Wilson 95%, telemetry
  py analyze.py pair <base glob> <variant glob>     paired shift on the shared case ids
  py analyze.py roster <jsonl glob> [...]           every hero's win rate over all its appearances
  py analyze.py sig <forced jsonl glob> <balance_runner jsonl glob>
                                                    winner/signature agreement with balance_runner

A draw (winner 2) counts as half a win. The paired shift is the mean of the
per-case differences (variant - base) of the forced hero's result; its sigma is
the standard deviation of those differences over sqrt(n).
"""
import collections
import glob
import json
import math
import sys


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0, 1.0
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return p, c - h, c + h


def load(patterns):
    rows = {}
    for pat in patterns:
        for f in sorted(glob.glob(pat)):
            with open(f, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        r = json.loads(line)
                        rows[r["case_id"]] = r
    return rows


def score(r, team):
    if r["winner"] == 2:
        return 0.5
    return 1.0 if r["winner"] == team else 0.0


def forced_unit(r):
    for h in r["heroes"]:
        if h["id"] == r["forced"] and h["team"] == r["forced_team"]:
            return h
    return None


def summary(rows):
    by_hero = collections.defaultdict(list)
    for r in rows.values():
        by_hero[r["forced"]].append(r)
    for hero, rs in sorted(by_hero.items()):
        n = len(rs)
        w = sum(score(r, r["forced_team"]) for r in rs)
        p, lo, hi = wilson(w, n)
        to = sum(1 for r in rs if r["reason"] != "elimination")
        print("== %s  n=%d  win=%.3f  [%.3f, %.3f]  timeouts=%d  variant=%s" % (
            hero, n, p, lo, hi, to, ",".join(sorted(set(r.get("variant", "?") for r in rs)))))
        for key, name in (("set", "set"), ("forced_team", "side")):
            parts = collections.defaultdict(list)
            for r in rs:
                parts[r[key]].append(score(r, r["forced_team"]))
            print("   by %s: %s" % (name, "  ".join("%s %.3f (%d)" % (k, sum(v) / len(v), len(v)) for k, v in sorted(parts.items()))))
        maps = collections.defaultdict(list)
        for r in rs:
            maps[r["arena"]].append(score(r, r["forced_team"]))
        print("   by map: " + "  ".join("%s %.2f" % (k, sum(v) / len(v)) for k, v in sorted(maps.items())))
        units = [forced_unit(r) for r in rs]
        alive_min = sum(u["alive_s"] for u in units) / 60.0
        dur_min = sum(r["duration"] for r in rs) / 60.0
        dmg = collections.Counter()
        heal = collections.Counter()
        hs = collections.Counter()
        sh = collections.Counter()
        casts = collections.Counter()
        for u in units:
            for k, v in u["dmg"].items():
                dmg[k] += v
            for k, v in u["heal"].items():
                heal[k] += v
            for k, v in u["heal_self"].items():
                hs[k] += v
            for k, v in u["shield"].items():
                sh[k] += v
            for k, v in u["casts"].items():
                casts[k] += v
        print("   alive %.1f of %.1f min (%.0f%%); deaths/battle %.2f; kills/battle %.2f; mean duration %.1f s" % (
            alive_min, dur_min, 100 * alive_min / max(dur_min, 1e-9), sum(u["deaths"] for u in units) / n,
            sum(u["kills"] for u in units) / n, 60 * dur_min / n))
        print("   damage to heroes per battle %.0f (per alive min %.0f): %s" % (
            sum(dmg.values()) / n, sum(dmg.values()) / alive_min,
            ", ".join("%s %.0f" % (k, v / n) for k, v in dmg.most_common())))
        print("   taken per battle %.0f; ally heal/battle %.0f; self heal/battle %.0f (%s); shield/battle %.0f" % (
            sum(u["taken"] for u in units) / n, sum(heal.values()) / n, sum(hs.values()) / n,
            ", ".join("%s %.0f" % (k, v / n) for k, v in hs.most_common(3)), sum(sh.values()) / n))
        print("   casts per alive min: " + "  ".join("S%s %.2f" % (k, casts[k] / alive_min) for k in sorted(casts)))
        behs = [r["behavior"] for r in rs if "behavior" in r]
        if behs:
            orders = collections.Counter()
            for b in behs:
                orders.update(b["orders"])
            tot = max(1, sum(orders.values()))
            print("   in basic reach of an enemy hero %.0f%% of alive time; basics declared %.1f/battle" % (
                100 * sum(b["contact_s"] for b in behs) / max(1e-9, alive_min * 60), sum(b["basics"] for b in behs) / len(behs)))
            print("   orders: " + ", ".join("%s %.0f%%" % (k, 100 * v / tot) for k, v in orders.most_common(8)))
        wms = [r["wm"] for r in rs if "wm" in r and r["forced"] == "war_machine"]
        if wms:
            s4 = sum(x["s4"] for x in wms)
            with_s4 = sum(1 for x in wms if x["s4"] > 0)
            charges = collections.Counter(c for x in wms for c in x["s2_charges"])
            print("   war_machine S4: %d casts in %d battles (%.2f/battle, %.3f per alive min, %d battles with >=1 = %.0f%%)" % (
                s4, len(wms), s4 / len(wms), s4 / alive_min, with_s4, 100 * with_s4 / len(wms)))
            print("   war_machine S2 charges: %s; mean max fuel %.2f; mean fuel %.2f; overdrive %.0f s; tanks lost %d" % (
                dict(sorted(charges.items())), sum(x["fuel_max"] for x in wms) / len(wms),
                sum(x["fuel_sum"] for x in wms) / max(1e-9, alive_min * 60), sum(x["overdrive_s"] for x in wms),
                sum(x["tanks_lost"] for x in wms)))


def pair(base, var):
    keys = sorted(k for k in var if k in base)
    if not keys:
        print("no shared cases")
        return
    d = []
    for k in keys:
        b = base[k]
        v = var[k]
        d.append(score(v, v["forced_team"]) - score(b, b["forced_team"]))
    n = len(d)
    mean = sum(d) / n
    sd = math.sqrt(sum((x - mean) ** 2 for x in d) / max(1, n - 1))
    sigma = sd / math.sqrt(n)
    pb = sum(score(base[k], base[k]["forced_team"]) for k in keys) / n
    pv = sum(score(var[k], var[k]["forced_team"]) for k in keys) / n
    up = sum(1 for x in d if x > 0)
    down = sum(1 for x in d if x < 0)
    print("pair n=%d base %.3f -> variant %.3f  shift %+.3f +- %.3f (z=%+.2f)  flips up %d / down %d" % (
        n, pb, pv, mean, sigma, mean / sigma if sigma > 0 else 0.0, up, down))
    sets = collections.defaultdict(list)
    for k, x in zip(keys, d):
        sets[var[k].get("set", "?")].append(x)
    print("   by set: " + "  ".join("%s %+.3f (%d)" % (s, sum(v) / len(v), len(v)) for s, v in sorted(sets.items())))


def roster(rows):
    acc = collections.defaultdict(lambda: [0.0, 0])
    forced_acc = collections.defaultdict(lambda: [0.0, 0])
    for r in rows.values():
        seen = set()
        for h in r["heroes"]:
            key = (h["id"], h["team"])
            if key in seen:
                continue
            seen.add(key)
            s = score(r, h["team"])
            if h["id"] == r["forced"] and h["team"] == r["forced_team"]:
                forced_acc[h["id"]][0] += s
                forced_acc[h["id"]][1] += 1
            else:
                acc[h["id"]][0] += s
                acc[h["id"]][1] += 1
    print("%-15s %6s %5s %15s   %s" % ("hero", "win", "n", "95%", "(forced runs: win n)"))
    ids = sorted(set(acc) | set(forced_acc), key=lambda i: -(acc[i][0] / acc[i][1] if acc[i][1] else 0))
    for i in ids:
        w, n = acc[i]
        p, lo, hi = wilson(w, n)
        fw, fn = forced_acc.get(i, [0, 0])
        extra = "(forced %.3f %d)" % (fw / fn, fn) if fn else ""
        print("%-15s %6.3f %5d  [%.3f, %.3f]   %s" % (i, p, n, lo, hi, extra))


def sig(forced, runner):
    same = 0
    diff = []
    for k, r in forced.items():
        if k in runner:
            if r["signature"] == runner[k]["signature"] and r["winner"] == runner[k]["winner"]:
                same += 1
            else:
                diff.append(k)
    print("signature agreement: %d same, %d different %s" % (same, len(diff), diff[:10]))


def main():
    mode = sys.argv[1]
    if mode == "summary":
        summary(load(sys.argv[2:]))
    elif mode == "pair":
        pair(load([sys.argv[2]]), load([sys.argv[3]]))
    elif mode == "roster":
        roster(load(sys.argv[2:]))
    elif mode == "sig":
        sig(load([sys.argv[2]]), load([sys.argv[3]]))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
