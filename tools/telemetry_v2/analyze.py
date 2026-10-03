# -*- coding: utf-8 -*-
"""V2 telemetry analysis; retains the V1.5.3 probe metric formulas.

Usage:
  py tools/telemetry_v2/analyze.py <run_dir> [...] --out=<dir> --label=<name>

Reads every *.jsonl in the given directories, writes
  <out>/summary_<label>.json   machine-readable aggregates + ranked anomalies
  <out>/summary_<label>_KO.md  Korean human summary
Optional: --compare=<older summary json>  adds a before/after delta section.
"""
import json
import math
import os
import re
import statistics as stats
import sys
from collections import defaultdict

RETREAT = {"후퇴", "측면 이탈 (우)", "측면 이탈 (좌)", "재집결", "보호선으로 후퇴"}


def wilson(k, n, z=1.96):
    if n <= 0:
        return (0.0, 0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (p, max(0.0, c - h), min(1.0, c + h))


def med(xs):
    xs = [x for x in xs if x is not None]
    return stats.median(xs) if xs else 0.0


def q(xs, p):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return 0.0
    k = (len(xs) - 1) * p
    f = math.floor(k)
    c = min(len(xs) - 1, f + 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def norm_map(m):
    return re.sub(r"_\d+$", "", m) if m.startswith("dm_") else m


def group_of(b):
    if b["mode"] == "elimination":
        return "E%d" % (len(b["comp"]) // 2)
    if b["mode"] == "control":
        return "C%d" % (len(b["comp"]) // 2)
    return "DM%d" % len(b["comp"])


def purpose_cat(label):
    if label.startswith("ability:"):
        return "ability"
    if label == "basic":
        return "basic"
    if label in RETREAT:
        return "retreat"
    if label == "none":
        return "none"
    base = label.split(":")[0].split("·")[0].strip()
    return base


def summarize_probe(battles, roster, label, dirs):
    meta = {}
    for h in roster.values():
        for a in h["abilities"]:
            meta[a["key"]] = a
    for b in battles:
        for k, m in b.get("ability_meta", {}).items():
            meta.setdefault(k, m)

    # ------------------------------------------------------------ battles
    groups = defaultdict(list)
    for b in battles:
        b["group"] = group_of(b)
        b["mapn"] = norm_map(b["map"])
        groups[b["group"]].append(b)

    # ------------------------------------------------------------ heroes
    H = defaultdict(lambda: defaultdict(float))
    HG = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))  # group -> hero -> metric
    purposes = defaultdict(lambda: defaultdict(float))
    idle_purpose = defaultdict(lambda: defaultdict(float))
    stuck_purpose = defaultdict(lambda: defaultdict(float))
    unobs_kind = defaultdict(lambda: defaultdict(float))
    A = defaultdict(lambda: defaultdict(float))
    A_miss = defaultdict(lambda: defaultdict(int))
    A_cancel = defaultdict(lambda: defaultdict(int))
    A_alive = defaultdict(float)  # alive minutes of hero appearances (per ability owner)
    maps = defaultdict(lambda: defaultdict(float))
    map_haz = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))
    haz_tot = defaultdict(lambda: defaultdict(float))
    stuck_spots = defaultdict(lambda: defaultdict(float))
    side = defaultdict(lambda: [0, 0, 0, 0])  # group -> [blue wins, red wins, draws, n]
    battle_rows = []

    for b in battles:
        g = b["group"]
        n_team = len(b["comp"]) // 2
        dur = b["duration"]
        winner = b["winner"]
        timeout = b["reason"] in ("time_limit",)
        mk = (g, b["mapn"])
        M = maps[mk]
        M["battles"] += 1
        M["duration"] += dur
        M["timeouts"] += 1 if timeout else 0
        M["draws"] += 1 if winner == 2 else 0
        M["blue_wins"] += 1 if winner == 0 else 0
        M["first_damage"] += max(0.0, b.get("first_damage", 0.0))
        M["first_kill"] += b["first_kill"] if b.get("first_kill", -1) >= 0 else dur
        M["max_lull"] += b.get("max_lull", 0.0)
        M["wall"] += b.get("wall_seconds", 0.0)
        if b["mode"] != "deathmatch":
            s = side[g]
            s[3] += 1
            if winner == 0:
                s[0] += 1
            elif winner == 1:
                s[1] += 1
            else:
                s[2] += 1
        for sl in b.get("stuck_log", []):
            cell = (int(sl["pos"][0] // 64) * 64, int(sl["pos"][1] // 64) * 64)
            stuck_spots[(g, b["mapn"])][cell] += sl["dur"]
        battle_rows.append({"group": g, "map": b["mapn"], "seed": b["seed"], "winner": winner, "reason": b["reason"],
                            "duration": round(dur, 2), "first_damage": round(b.get("first_damage", -1), 2),
                            "first_kill": round(b.get("first_kill", -1), 2), "max_lull": round(b.get("max_lull", 0), 2),
                            "comp": b["comp"], "wall": round(b.get("wall_seconds", 0), 1)})
        n_players = len(b["heroes"])
        for h in b["heroes"]:
            hid = h["id"]
            alive_min = max(1e-6, h["alive_s"] / 60.0)
            # outcome
            if b["mode"] == "deathmatch":
                rank = h.get("dm", {}).get("rank", n_players)
                win = 1.0 if rank == 1 else 0.0
                score = 1.0 - (rank - 1) / max(1, n_players - 1)
            else:
                win = 1.0 if winner == h["team"] else (0.5 if winner == 2 else 0.0)
                score = win
            for tgt in (H[hid], HG[g][hid]):
                tgt["n"] += 1
                if b["mode"] == "deathmatch":
                    tgt["dm_n"] += 1
                    tgt["dm_top1"] += win
                    tgt["dm_score"] += score
                else:
                    tgt["n_team"] += 1
                    tgt["wins"] += win
                tgt["score"] += score
                tgt["alive_min"] += alive_min
                tgt["battle_min"] += dur / 60.0
                for k in ("damage", "taken", "healing", "shielding", "kills", "deaths", "casts", "basic_hits", "walk_px", "burst_px",
                          "stuck_s", "jitter_s", "wall_s", "idle_in_range_s", "idle_static_in_range_s", "idle_target_in_range_s",
                          "cc_s", "casting_s", "decisions", "retreats", "target_switches", "attack_orders", "unobserved_orders",
                          "voided_same_tick", "voided_later", "voided_cc", "void_stall_s", "env_deaths", "env_assisted_deaths",
                          "null_deaths", "self_kills", "stuck_episodes", "health_cost", "capture_time", "zone_healing", "cc_dealt",
                          "unattributed", "mitigated"):
                    tgt[k] += float(h.get(k, 0.0))
                tgt["env_dmg"] += sum(h.get("haz_dmg", {}).values())
                tgt["haz_avoidable_s"] += sum(h.get("haz_avoidable_s", {}).values())
                tgt["survived"] += 1 if h.get("alive_end") else 0
                tgt["void_streaks_1s"] += h.get("void_streaks_1s", 0)
                tgt["void_streaks_3t"] += h.get("void_streaks_3t", 0)
                tgt["void_streak_max_s"] = max(tgt["void_streak_max_s"], h.get("void_streak_max_s", 0.0))
            for k, v in h.get("purpose", {}).items():
                purposes[hid][purpose_cat(k)] += v
            for k, v in h.get("idle_purpose", {}).items():
                idle_purpose[hid][purpose_cat(k)] += v
            for k, v in h.get("stuck_purpose", {}).items():
                stuck_purpose[hid][purpose_cat(k)] += v
            for k, v in h.get("unobserved_by_kind", {}).items():
                unobs_kind[hid][k] += v
            M["hero_min"] += alive_min
            M["env_dmg"] += sum(h.get("haz_dmg", {}).values())
            M["env_deaths"] += h.get("env_deaths", 0)
            M["env_assisted"] += h.get("env_assisted_deaths", 0)
            M["deaths"] += h.get("deaths", 0)
            M["stuck_s"] += h.get("stuck_s", 0)
            M["jitter_s"] += h.get("jitter_s", 0)
            M["void_stall_s"] += h.get("void_stall_s", 0)
            M["wall_s"] += h.get("wall_s", 0)
            M["idle_s"] += h.get("idle_in_range_s", 0)
            for ht, v in h.get("haz_s", {}).items():
                map_haz[mk][ht]["time_s"] += v
                haz_tot[ht]["time_s"] += v
            for ht, v in h.get("haz_avoidable_s", {}).items():
                map_haz[mk][ht]["avoidable_s"] += v
                haz_tot[ht]["avoidable_s"] += v
            for ht, v in h.get("haz_dmg", {}).items():
                map_haz[mk][ht]["dmg"] += v
                haz_tot[ht]["dmg"] += v
            for ht, v in h.get("haz_hits", {}).items():
                map_haz[mk][ht]["hits"] += v
                haz_tot[ht]["hits"] += v
            for gk, v in h.get("gimmick", {}).items():
                M["g_" + gk] += v
            # abilities of this appearance
            owned = [a["key"] for a in roster[hid]["abilities"]] if hid in roster else []
            for key in owned:
                A_alive[key] += alive_min
            for key, st in h.get("abilities", {}).items():
                if key not in owned:
                    A_alive.setdefault(key, 0.0)
                    if key.endswith("|V:borrow") or "|V:" in key:
                        pass
                a = A[key]
                for k, v in st.items():
                    if isinstance(v, (int, float)):
                        a[k] += v
                for k, v in st.get("miss", {}).items():
                    A_miss[key][k] += v
                for k, v in st.get("cancel", {}).items():
                    A_cancel[key][k] += v
                if key not in owned:
                    A_alive[key] += alive_min

    # ------------------------------------------------------------ hero table
    def hero_row(hid, d):
        n = d["n"]
        am = max(1e-6, d["alive_min"])
        # team-mode win rate only (deathmatch rank-1 has a 1/8 base rate; reported separately)
        p, lo, hi = wilson(d["wins"], d["n_team"])
        alive_s = am * 60
        return {
            "hero": hid, "name": roster.get(hid, {}).get("name", hid), "role": roster.get(hid, {}).get("role", ""), "n": int(n), "n_team": int(d["n_team"]),
            "dm_n": int(d["dm_n"]), "dm_top1_rate": round(d["dm_top1"] / d["dm_n"], 3) if d["dm_n"] else None,
            "dm_rank_score": round(d["dm_score"] / d["dm_n"], 3) if d["dm_n"] else None,
            "win_rate": round(p, 3), "ci95": [round(lo, 3), round(hi, 3)], "score": round(d["score"] / max(1, n), 3),
            "survival_rate": round(d["survived"] / max(1, n), 3),
            "alive_frac": round(d["alive_min"] / max(1e-6, d["battle_min"]), 3),
            "dmg_pm": round(d["damage"] / am, 1), "taken_pm": round(d["taken"] / am, 1), "heal_pm": round(d["healing"] / am, 1),
            "shield_pm": round(d["shielding"] / am, 1), "kills_pb": round(d["kills"] / n, 2), "deaths_pb": round(d["deaths"] / n, 2),
            "casts_pm": round(d["casts"] / am, 2), "basic_hits_pm": round(d["basic_hits"] / am, 2),
            "walk_px_pm": round(d["walk_px"] / am, 0),
            "stuck_pct": round(100 * d["stuck_s"] / alive_s, 2), "jitter_pct": round(100 * d["jitter_s"] / alive_s, 2),
            "wall_pct": round(100 * d["wall_s"] / alive_s, 1), "idle_in_range_pct": round(100 * d["idle_in_range_s"] / alive_s, 2),
            "idle_static_pct": round(100 * d["idle_static_in_range_s"] / alive_s, 2),
            "idle_target_in_range_pct": round(100 * d["idle_target_in_range_s"] / alive_s, 2),
            "void_stall_pct": round(100 * d["void_stall_s"] / alive_s, 2),
            "unobserved_order_pct": round(100 * d["unobserved_orders"] / max(1, d["attack_orders"]), 1),
            "voided_pm": round((d["voided_same_tick"] + d["voided_later"] - d["voided_cc"]) / am, 2),
            "decisions_pm": round(d["decisions"] / am, 1), "retreats_pm": round(d["retreats"] / am, 2),
            "target_switch_pm": round(d["target_switches"] / am, 2), "cc_taken_pct": round(100 * d["cc_s"] / alive_s, 1),
            "casting_pct": round(100 * d["casting_s"] / alive_s, 1),
            "env_dmg_pm": round(d["env_dmg"] / am, 1), "env_deaths": int(d["env_deaths"]), "env_assisted_deaths": int(d["env_assisted_deaths"]),
            "haz_avoidable_pct": round(100 * d["haz_avoidable_s"] / alive_s, 2), "self_kills": int(d["self_kills"]),
            "null_deaths": int(d["null_deaths"]), "health_cost_pm": round(d["health_cost"] / am, 1),
            "void_streaks_1s_pb": round(d["void_streaks_1s"] / n, 2), "void_loops_pm": round(d["void_streaks_3t"] / am, 2),
            "void_streak_max_s": round(d["void_streak_max_s"], 2),
        }

    hero_all = sorted((hero_row(h, d) for h, d in H.items()), key=lambda r: -r["win_rate"])
    hero_by_group = {g: sorted((hero_row(h, d) for h, d in hs.items()), key=lambda r: -r["win_rate"]) for g, hs in HG.items()}
    for r in hero_all:
        pc = purposes[r["hero"]]
        tot = max(1.0, sum(pc.values()))
        r["purpose_mix"] = {k: round(100 * v / tot, 1) for k, v in sorted(pc.items(), key=lambda kv: -kv[1])[:8]}
        r["idle_purpose"] = {k: round(v, 1) for k, v in sorted(idle_purpose[r["hero"]].items(), key=lambda kv: -kv[1])[:4]}
        r["stuck_purpose"] = {k: round(v, 1) for k, v in sorted(stuck_purpose[r["hero"]].items(), key=lambda kv: -kv[1])[:4]}
        r["unobserved_by_kind"] = dict(sorted(unobs_kind[r["hero"]].items(), key=lambda kv: -kv[1])[:4])

    # ------------------------------------------------------------ ability table
    ab_rows = []
    for key in sorted(set(list(meta.keys()) + list(A.keys()))):
        m = meta.get(key, {"key": key, "name": key, "category": "?", "cooldown": 0})
        hid = key.split("|")[0].rsplit("_", 1)[0] if "|" not in key else key.split("|")[0]
        a = A.get(key, defaultdict(float))
        casts = a.get("casts", 0.0)
        am = max(1e-6, A_alive.get(key, 0.0))
        valid = max(1.0, casts - a.get("cancelled", 0.0))
        cd = float(m.get("cooldown", 0) or 0)
        theo = (60.0 / cd) if cd > 0 else None
        row = {
            "key": key, "hero": hid, "name": m.get("name", ""), "category": m.get("category", "?"), "deploy": m.get("deploy", False),
            "target": m.get("target", ""), "action": m.get("action", ""), "cooldown": cd,
            "casts": int(casts), "alive_min": round(am, 1), "casts_pm": round(casts / am, 3),
            "cd_utilization": round((casts / am) / theo, 3) if theo else None,
            "whiff_pct": round(100 * a.get("whiff", 0) / valid, 1),
            "no_enemy_pct": round(100 * a.get("no_enemy", 0) / valid, 1),
            "late_enemy_pct": round(100 * a.get("late_enemy", 0) / valid, 1),
            "enemy_pct": round(100 * a.get("enemy", 0) / valid, 1), "ally_pct": round(100 * a.get("ally", 0) / valid, 1),
            "self_pct": round(100 * a.get("self", 0) / valid, 1), "deploy_pct": round(100 * a.get("deploy", 0) / valid, 1),
            "special_pct": round(100 * a.get("special", 0) / valid, 1), "blocked_pct": round(100 * a.get("blocked", 0) / valid, 1),
            "cancel_pct": round(100 * a.get("cancelled", 0) / max(1, casts), 1),
            "miss": dict(A_miss.get(key, {})), "cancel": dict(A_cancel.get(key, {})),
            "avg_dist": round(a.get("dist_sum", 0) / a["dist_n"], 1) if a.get("dist_n") else None,
            "range_ratio": round(a.get("range_ratio_sum", 0) / a["range_ratio_n"], 2) if a.get("range_ratio_n") else None,
            "over_range_pct": round(100 * a.get("over_range", 0) / max(1, a.get("range_ratio_n", 0)), 1) if a.get("range_ratio_n") else None,
            "near_enemy": round(a.get("near_enemy_sum", 0) / a["near_enemy_n"], 0) if a.get("near_enemy_n") else None,
            "no_enemy_near_pct": round(100 * a.get("no_enemy_near", 0) / max(1, casts), 1),
            "no_visible_enemy_pct": round(100 * a.get("no_visible_enemy", 0) / max(1, casts), 1),
            "target_immune_pct": round(100 * a.get("target_immune", 0) / max(1, casts), 1),
            "target_immune_resolve_pct": round(100 * a.get("target_immune_resolve", 0) / max(1, casts), 1),
            "self_cost_per_cast": round(a.get("self_cost", 0) / max(1, casts), 1),
            "dmg_per_cast": round(a.get("dmg", 0) / max(1, casts), 1), "heal_per_cast": round(a.get("heal", 0) / max(1, casts), 1),
            "overheal_pct": round(100 * (1 - a.get("heal", 0) / a["heal_raw"]), 1) if a.get("heal_raw") else None,
            "shield_per_cast": round(a.get("shield", 0) / max(1, casts), 1),
            "ready_opp_pct": round(100 * a.get("ready_opp_s", 0) / (am * 60), 1),
            "ready_pct": round(100 * a.get("ready_s", 0) / (am * 60), 1),
            "kills": int(a.get("kills", 0)),
            "completed_pct": round(100 * a.get("completed", 0) / max(1, casts), 1),
            "over_range_casts": int(a.get("over_range_done", 0)),
            "over_range_miss_pct": round(100 * a.get("over_range_miss", 0) / a["over_range_done"], 1) if a.get("over_range_done") else None,
            "in_range_miss_pct": round(100 * a.get("in_range_miss", 0) / a["in_range_done"], 1) if a.get("in_range_done") else None,
        }
        # the intent-appropriate failure rate
        cat = row["category"]
        if cat == "hostile":
            row["fail_pct"] = row["no_enemy_pct"] if not row["deploy"] else round(max(0.0, row["no_enemy_pct"] - row["late_enemy_pct"]), 1)
        elif key.endswith("|V:eat"):
            row["fail_pct"] = 0.0  # eating applies a buff through add_buff() without an event
        elif "|V:" in key:
            row["fail_pct"] = row["whiff_pct"]
        elif cat == "self":
            # self kits often change private state without an event; completion is the effect.
            row["fail_pct"] = round(100 - row["completed_pct"], 1)
        else:
            row["fail_pct"] = row["whiff_pct"]
        ab_rows.append(row)

    # ------------------------------------------------------------ maps
    map_rows = []
    for (g, mp), M in sorted(maps.items()):
        n = M["battles"]
        hm = max(1e-6, M["hero_min"])
        row = {"group": g, "map": mp, "battles": int(n), "avg_duration": round(M["duration"] / n, 1),
               "timeouts": int(M["timeouts"]), "draws": int(M["draws"]), "blue_win_rate": round(M["blue_wins"] / n, 2),
               "first_damage": round(M["first_damage"] / n, 1), "first_kill": round(M["first_kill"] / n, 1),
               "max_lull": round(M["max_lull"] / n, 1),
               "env_dmg_per_hero_min": round(M["env_dmg"] / hm, 1), "env_deaths": int(M["env_deaths"]),
               "env_assisted_deaths": int(M["env_assisted"]), "deaths": int(M["deaths"]),
               "env_death_share": round(M["env_deaths"] / max(1, M["deaths"]), 3),
               "stuck_pct": round(100 * M["stuck_s"] / (hm * 60), 2), "jitter_pct": round(100 * M["jitter_s"] / (hm * 60), 2),
               "void_stall_pct": round(100 * M["void_stall_s"] / (hm * 60), 2), "wall_pct": round(100 * M["wall_s"] / (hm * 60), 1),
               "idle_in_range_pct": round(100 * M["idle_s"] / (hm * 60), 2), "wall_seconds_avg": round(M["wall"] / n, 1),
               "gimmick_uses": {k[2:]: int(v) for k, v in M.items() if k.startswith("g_")},
               "hazards": {ht: {"time_pct": round(100 * v["time_s"] / (hm * 60), 2), "avoidable_pct": round(100 * v["avoidable_s"] / (hm * 60), 2),
                                "dmg_per_hero_min": round(v["dmg"] / hm, 1), "hits": int(v["hits"])} for ht, v in map_haz[(g, mp)].items()},
               "stuck_hotspots": [{"cell": list(c), "sec": round(s, 1)} for c, s in sorted(stuck_spots[(g, mp)].items(), key=lambda kv: -kv[1])[:4]]}
        map_rows.append(row)

    haz_rows = {ht: {"time_s": round(v["time_s"], 1), "avoidable_s": round(v["avoidable_s"], 1), "dmg": round(v["dmg"], 0), "hits": int(v["hits"]),
                     "dmg_per_hit": round(v["dmg"] / max(1, v["hits"]), 1)} for ht, v in haz_tot.items()}

    # ------------------------------------------------------------ anomalies
    anomalies = []

    def add(sev, kind, subject, metric, value, typical, note=""):
        anomalies.append({"severity": round(sev, 2), "kind": kind, "subject": subject, "metric": metric, "value": value, "typical": typical, "note": note})

    FLOOR = {"env_death_share": 0.03, "stuck_pct": 0.2, "void_stall_pct": 0.3, "idle_target_in_range_pct": 0.2, "idle_static_pct": 0.3,
             "jitter_pct": 0.2, "unobserved_order_pct": 5.0, "env_dmg_pm": 10.0, "haz_avoidable_pct": 0.3, "wall_pct": 1.0,
             "target_switch_pm": 0.5, "retreats_pm": 1.0, "casts_pm": 1.0, "env_dmg_per_hero_min": 10.0, "max_lull": 3.0, "first_kill": 5.0}

    def robust(rows, field, hi=True, min_n=8, thr=2.5, weight=1.0, kind="hero", nkey="n"):
        vals = [r[field] for r in rows if r.get(field) is not None and r.get(nkey, 0) >= min_n]
        if len(vals) < 5:
            return
        m = med(vals)
        iqr = max(q(vals, 0.75) - q(vals, 0.25), FLOOR.get(field, 1e-6), 0.25 * abs(m))
        for r in rows:
            v = r.get(field)
            if v is None or r.get(nkey, 0) < min_n:
                continue
            z = (v - m) / iqr if hi else (m - v) / iqr
            if z >= thr:
                add(z * weight, kind, r.get("hero", r.get("key", r.get("map"))) if kind != "map" else "%s/%s" % (r["group"], r["map"]),
                    field, v, round(m, 3), "IQR=%.3g" % iqr)

    for field, hi, w in (("stuck_pct", True, 1.2), ("void_stall_pct", True, 1.2), ("void_streaks_1s_pb", True, 0.8), ("idle_target_in_range_pct", True, 1.0),
                         ("idle_static_pct", True, 0.8), ("unobserved_order_pct", True, 1.0), ("jitter_pct", True, 0.7),
                         ("env_dmg_pm", True, 0.8), ("haz_avoidable_pct", True, 0.8), ("wall_pct", True, 0.5),
                         ("target_switch_pm", True, 0.5), ("retreats_pm", True, 0.4), ("casts_pm", False, 0.6)):
        robust(hero_all, field, hi, weight=w)
    # win-rate outliers: CI excludes 50%
    for r in hero_all:
        if r["n_team"] >= 15 and (r["ci95"][0] > 0.5 or r["ci95"][1] < 0.5):
            add(3.0 + abs(r["win_rate"] - 0.5) * 10, "hero", r["hero"], "win_rate", r["win_rate"], 0.5, "95%% CI %s, n_team=%d" % (r["ci95"], r["n_team"]))
    # abilities
    for r in ab_rows:
        if r["casts"] == 0 and r["alive_min"] > 10 and "|V:" not in r["key"]:
            add(6.0, "ability", r["key"], "casts", 0, "-", "never cast in %.0f alive-minutes (%s)" % (r["alive_min"], r["name"]))
        elif r["cd_utilization"] is not None and r["cd_utilization"] < 0.08 and r["alive_min"] > 10 and "|V:" not in r["key"]:
            add(4.0 + (0.08 - r["cd_utilization"]) * 20, "ability", r["key"], "cd_utilization", r["cd_utilization"], ">=0.3 typical",
                "%.2f casts/min vs cooldown %.1fs; ready with enemy in reach %.0f%% of alive time" % (r["casts_pm"], r["cooldown"], r["ready_opp_pct"]))
        if r["casts"] >= 15 and r["fail_pct"] >= 45:
            add(2.5 + r["fail_pct"] / 25, "ability", r["key"], "fail_pct", r["fail_pct"], "<25",
                "%s cat=%s whiff=%.0f%% noEnemy=%.0f%% cancel=%.0f%% nearEnemy=%s" % (r["name"], r["category"], r["whiff_pct"], r["no_enemy_pct"], r["cancel_pct"], r["near_enemy"]))
        if r["casts"] >= 15 and r["target_immune_pct"] + r["target_immune_resolve_pct"] >= 8:
            add(2.5, "ability", r["key"], "target_immune", r["target_immune_pct"] + r["target_immune_resolve_pct"], "~0", r["name"])
        if r["casts"] >= 15 and r["cancel_pct"] >= 20:
            add(2.5 + r["cancel_pct"] / 20, "ability", r["key"], "cancel_pct", r["cancel_pct"], "<8", str(r["cancel"]))
        if r["casts"] >= 15 and r["over_range_pct"] and r["over_range_pct"] >= 10 and r["over_range_miss_pct"] is not None:
            add(2.0 + r["over_range_pct"] / 20 + max(0.0, (r["over_range_miss_pct"] - (r["in_range_miss_pct"] or 0)) / 40), "ability", r["key"], "over_range_pct", r["over_range_pct"], "~0",
                "%s: 사거리 밖 시전 %d회 적중실패 %.0f%% vs 사거리 안 %.0f%%" % (r["name"], r["over_range_casts"], r["over_range_miss_pct"], r["in_range_miss_pct"] or 0))
        if r["category"] == "self" and r["casts"] >= 15 and r["no_enemy_near_pct"] >= 35:
            add(2.0 + r["no_enemy_near_pct"] / 40, "ability", r["key"], "self_cast_no_enemy_near_pct", r["no_enemy_near_pct"], "<15", r["name"] + " (적 700px 밖에서 자기 강화)")
        if r["casts"] >= 15 and r["overheal_pct"] is not None and r["overheal_pct"] >= 60:
            add(2.0 + r["overheal_pct"] / 50, "ability", r["key"], "overheal_pct", r["overheal_pct"], "<35", r["name"])
        if r["casts"] >= 15 and r["no_visible_enemy_pct"] >= 30 and r["category"] == "hostile":
            add(2.0 + r["no_visible_enemy_pct"] / 30, "ability", r["key"], "no_visible_enemy_pct", r["no_visible_enemy_pct"], "~0", r["name"])
    for field, hi, w in (("stuck_pct", True, 1.0), ("void_stall_pct", True, 1.0), ("env_dmg_per_hero_min", True, 1.0),
                         ("env_death_share", True, 1.2), ("max_lull", True, 0.6), ("first_kill", True, 0.5)):
        robust(map_rows, field, hi, min_n=3, thr=2.0, weight=w, kind="map", nkey="battles")
    for r in map_rows:
        if r["group"].startswith("E") and r["battles"] >= 4 and r["timeouts"] / r["battles"] >= 0.25:
            add(3.0 + 4 * r["timeouts"] / r["battles"], "map", "%s/%s" % (r["group"], r["map"]), "timeout_rate", round(r["timeouts"] / r["battles"], 2), "<0.1", "")
    for g, s in side.items():
        p, lo, hi = wilson(s[0] + 0.5 * s[2], s[3])
        if s[3] >= 20 and (lo > 0.5 or hi < 0.5):
            add(3.0, "mode", g, "blue_win_rate", round(p, 3), 0.5, "CI [%.2f, %.2f] n=%d" % (lo, hi, s[3]))
    anomalies.sort(key=lambda a: -a["severity"])

    summary = {
        "label": label, "dirs": dirs, "battles": len(battles),
        "by_group": {g: {"battles": len(bs), "avg_duration": round(sum(b["duration"] for b in bs) / len(bs), 1),
                         "timeouts": sum(1 for b in bs if b["reason"] in ("time_limit",)),
                         "reasons": {r: sum(1 for b in bs if b["reason"] == r) for r in set(b["reason"] for b in bs)},
                         "side": {"blue": side[g][0], "red": side[g][1], "draw": side[g][2]} if g in side else None,
                         "wall_seconds_total": round(sum(b.get("wall_seconds", 0) for b in bs), 1)} for g, bs in groups.items()},
        "hero": hero_all, "hero_by_group": hero_by_group, "ability": ab_rows, "maps": map_rows, "hazards": haz_rows,
        "anomalies": anomalies, "battles_list": battle_rows,
        "roster_medians": {f: med([r[f] for r in hero_all]) for f in ("stuck_pct", "void_stall_pct", "idle_in_range_pct", "idle_target_in_range_pct",
                                                                        "unobserved_order_pct", "wall_pct", "casts_pm", "target_switch_pm", "retreats_pm",
                                                                        "decisions_pm", "env_dmg_pm", "jitter_pct")},
    }
    return summary


def compare(old, new):
    out = {"hero": [], "ability": [], "maps": []}
    oh = {r["hero"]: r for r in old["hero"]}
    for r in new["hero"]:
        o = oh.get(r["hero"])
        if o:
            out["hero"].append({"hero": r["hero"], **{k: [o[k], r[k]] for k in ("win_rate", "stuck_pct", "void_stall_pct", "idle_target_in_range_pct", "unobserved_order_pct", "env_dmg_pm", "casts_pm")}})
    oa = {r["key"]: r for r in old["ability"]}
    for r in new["ability"]:
        o = oa.get(r["key"])
        if o:
            out["ability"].append({"key": r["key"], **{k: [o[k], r[k]] for k in ("casts_pm", "fail_pct", "cancel_pct", "cd_utilization")}})
    om = {(r["group"], r["map"]): r for r in old["maps"]}
    for r in new["maps"]:
        o = om.get((r["group"], r["map"]))
        if o:
            out["maps"].append({"map": "%s/%s" % (r["group"], r["map"]), **{k: [o[k], r[k]] for k in ("timeouts", "avg_duration", "env_dmg_per_hero_min", "env_deaths", "stuck_pct", "void_stall_pct")}})
    return out


def markdown(s):
    L = []
    L.append("# V2 AI 텔레메트리 프로브 요약 (%s)\n" % s["label"])
    L.append("- 전투 수: **%d** (디렉터리: %s)" % (s["battles"], ", ".join(os.path.basename(os.path.normpath(d)) for d in s["dirs"])))
    for g, v in sorted(s["by_group"].items()):
        L.append("- %s: %d전, 평균 %.1f초, 종료 사유 %s, 진영 %s" % (g, v["battles"], v["avg_duration"], v["reasons"], v["side"]))
    L.append("\n## 주요 이상 징후 (심각도순 상위 40)\n")
    L.append("| # | 심각도 | 종류 | 대상 | 지표 | 값 | 일반값 | 비고 |")
    L.append("|---|---|---|---|---|---|---|---|")
    for i, a in enumerate(s["anomalies"][:40], 1):
        L.append("| %d | %.1f | %s | %s | %s | %s | %s | %s |" % (i, a["severity"], a["kind"], a["subject"], a["metric"], a["value"], a["typical"], a["note"]))
    L.append("\n## 영웅별 (전 모드 합산, 승률순)\n")
    L.append("| 영웅 | n(팀전) | 팀전 승률 | 95% CI | 생존율 | 피해/분 | 시전/분 | 끼임% | 무효명령정지% | 1초+정지/전 | 최장정지s | 사거리내대기% | 명령대상사거리내대기% | 비관측대상명령% | 벽근접% | 환경피해/분 | 표적전환/분 | 후퇴/분 |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in s["hero"]:
        L.append("| %s(%s) | %d | %.2f | %s | %.2f | %.0f | %.2f | %.2f | %.2f | %.2f | %.1f | %.2f | %.2f | %.1f | %.1f | %.1f | %.2f | %.2f |" % (
            r["name"], r["hero"], r["n_team"], r["win_rate"], r["ci95"], r["survival_rate"], r["dmg_pm"], r["casts_pm"], r["stuck_pct"], r["void_stall_pct"], r["void_streaks_1s_pb"], r["void_streak_max_s"],
            r["idle_in_range_pct"], r["idle_target_in_range_pct"], r["unobserved_order_pct"], r["wall_pct"], r["env_dmg_pm"], r["target_switch_pm"], r["retreats_pm"]))
    for g, rows in sorted(s["hero_by_group"].items()):
        L.append("\n### 모드 %s 영웅 승률\n" % g)
        L.append("| 영웅 | n | 승률(DM=1위율) | 95% CI | 점수(DM=순위점수) |")
        L.append("|---|---|---|---|---|")
        for r in rows:
            if g.startswith("DM"):
                L.append("| %s | %d | %.2f | - | %.2f |" % (r["hero"], r["dm_n"], r["dm_top1_rate"] or 0.0, r["dm_rank_score"] or 0.0))
            else:
                L.append("| %s | %d | %.2f | %s | %.2f |" % (r["hero"], r["n_team"], r["win_rate"], r["ci95"], r["score"]))
    L.append("\n## 스킬별 (시전/분, 쿨다운 활용도, 실패율)\n")
    L.append("실패율(fail): 적대 스킬은 적에게 1.5초 안에 효과 없음(설치형은 6초 내 지연 효과 제외), 비적대 스킬은 아무 효과 없음 비율.\n")
    L.append("| 스킬 | 이름 | 분류 | 시전 | 시전/분 | 쿨활용 | 실패% | 무효과% | 취소% | 평균거리 | 사거리비 | 사거리밖% | 사거리밖실패% | 사거리안실패% | 적근접 | 대상무적% | 준비+적사거리내% | 과치유% |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in s["ability"]:
        L.append("| %s | %s | %s%s | %d | %.2f | %s | %.0f | %.0f | %.0f | %s | %s | %s | %s | %s | %s | %.1f | %.0f | %s |" % (
            r["key"], r["name"], r["category"], "/설치" if r["deploy"] else "", r["casts"], r["casts_pm"], r["cd_utilization"], r["fail_pct"], r["whiff_pct"],
            r["cancel_pct"], r["avg_dist"], r["range_ratio"], r["over_range_pct"], r["over_range_miss_pct"], r["in_range_miss_pct"], r["near_enemy"],
            r["target_immune_pct"] + r["target_immune_resolve_pct"], r["ready_opp_pct"], r["overheal_pct"]))
    L.append("\n## 맵별\n")
    L.append("| 모드/맵 | 전투 | 평균시간 | 시간초과 | 무승부 | 청승률 | 첫피해 | 첫킬 | 최대소강 | 환경피해/영웅분 | 환경사망 | 환경관여사망 | 끼임% | 무효명령정지% | 벽근접% |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in s["maps"]:
        L.append("| %s/%s | %d | %.1f | %d | %d | %.2f | %.1f | %.1f | %.1f | %.1f | %d | %d | %.2f | %.2f | %.1f |" % (
            r["group"], r["map"], r["battles"], r["avg_duration"], r["timeouts"], r["draws"], r["blue_win_rate"], r["first_damage"], r["first_kill"], r["max_lull"],
            r["env_dmg_per_hero_min"], r["env_deaths"], r["env_assisted_deaths"], r["stuck_pct"], r["void_stall_pct"], r["wall_pct"]))
    L.append("\n### 맵별 기믹/위험지대\n")
    for r in s["maps"]:
        if r["hazards"] or r["gimmick_uses"]:
            L.append("- %s/%s: %s; 사용 %s; 끼임 지점 %s" % (r["group"], r["map"], json.dumps(r["hazards"], ensure_ascii=False), r["gimmick_uses"], r["stuck_hotspots"]))
    L.append("\n## 위험지대 유형 합계\n")
    for ht, v in sorted(s["hazards"].items()):
        L.append("- %s: 체류 %.0f초 (회피 가능 %.0f초), 피해 %.0f, 적중 %d회, 적중당 %.1f" % (ht, v["time_s"], v["avoidable_s"], v["dmg"], v["hits"], v["dmg_per_hit"]))
    L.append("\n## 영웅별 결정 목적 분포 (상위)\n")
    for r in s["hero"]:
        L.append("- %s: %s | 대기 중 목적 %s | 끼임 목적 %s | 비관측 대상 명령 %s" % (r["hero"], r["purpose_mix"], r["idle_purpose"], r["stuck_purpose"], r["unobserved_by_kind"]))
    if "compare" in s:
        L.append("\n## 이전 대비 변화\n")
        for sec in ("hero", "ability", "maps"):
            L.append("\n### %s\n" % sec)
            for row in s["compare"][sec]:
                L.append("- " + json.dumps(row, ensure_ascii=False))
    return "\n".join(L) + "\n"


def read_inputs(paths, allow_partial=False):
    """Reject incomplete manifests, malformed rows and duplicate battles."""
    from pathlib import Path
    try:
        from .run import sha256, validate_rows
    except ImportError:
        from run import sha256, validate_rows
    rows, roster, manifests, seen = [], {}, [], set()
    for value in paths:
        path = Path(value)
        manifest_path = path / "run_manifest.json"
        files = []
        metadata = {}
        if path.is_dir() and manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if not manifest.get("complete") and not allow_partial:
                raise ValueError(f"Incomplete run: {path}")
            manifests.append({"path": str(manifest_path), "complete": manifest.get("complete", False),
                              "source_sha256": manifest["config"]["source_sha256"], "suite": manifest["config"]["suite"]})
            for task in manifest["config"]["tasks"]:
                result = manifest["results"].get(task["name"], {})
                if result.get("status") != "complete":
                    if allow_partial:
                        continue
                    raise ValueError(f"Incomplete shard: {task['name']}")
                file = path / result["output"]
                if sha256(file) != result["sha256"]:
                    raise ValueError(f"Changed shard: {file}")
                validate_rows(file, task)
                files.append(file)
                metadata[file] = {"_seed_set": task["seed_set"], "_suite": manifest["config"]["suite"],
                                  "_source_sha256": manifest["config"]["source_sha256"]}
        elif path.is_dir():
            files = sorted(path.glob("*.jsonl"))
        elif path.is_file():
            files = [path]
        else:
            raise ValueError(f"Missing input: {path}")
        roster_path = (path if path.is_dir() else path.parent) / "roster_meta.json"
        if roster_path.exists():
            if path.is_dir() and manifest_path.exists() and sha256(roster_path) != manifest.get("roster", {}).get("sha256"):
                raise ValueError(f"Changed roster metadata: {roster_path}")
            for hero in json.loads(roster_path.read_text(encoding="utf-8")):
                if hero["id"] in roster and roster[hero["id"]] != hero:
                    raise ValueError("Input roster metadata differs; compare separately generated summaries")
                roster[hero["id"]] = hero
        for file in files:
            for line_no, line in enumerate(file.read_text(encoding="utf-8").splitlines(), 1):
                if not line.strip():
                    continue
                row = json.loads(line)
                if not all(k in row for k in ("map", "seed", "comp", "winner", "reason", "duration", "heroes")):
                    raise ValueError(f"Malformed battle: {file}:{line_no}")
                kind = "nav" if "ring_out_s" in row and "trips" in row else "probe"
                key = (kind, row.get("mode", "elimination"), row["map"], row["seed"], tuple(row["comp"]))
                if key in seen:
                    raise ValueError(f"Duplicate battle: {file}:{line_no} {key[:4]}")
                seen.add(key)
                row.update(metadata.get(file, {}))
                row["_file"] = str(file)
                row["_kind"] = kind
                rows.append(row)
    for row in rows:
        if row["_kind"] != "probe":
            continue
        for hero in row["heroes"]:
            if hero["id"] not in roster:
                abilities = []
                for key, ability in row.get("ability_meta", {}).items():
                    if key.startswith(hero["id"] + "|") and "|V:" not in key:
                        abilities.append({**ability, "key": key})
                roster[hero["id"]] = {"id": hero["id"], "name": hero["id"], "abilities": abilities}
    if not rows:
        raise ValueError("No completed battle rows")
    source_shas = {m["source_sha256"] for m in manifests}
    if len(source_shas) > 1:
        raise ValueError("Different source snapshots must be analyzed separately and compared with --compare")
    return rows, roster, manifests


def stuck_cause(row, episode):
    """Fixed spatial proxies, identical before/after (not a physics diagnosis).

    thorn pocket: NE/SW 180 x 212 px outer rectangles, including approaches.
    strict_pocket: 40 px around the two documented sealed endpoints.
    corner: within 100 px of both an inner horizontal and vertical map bound.
    """
    x, y = episode["pos"]
    width, height = row.get("arena_size", [1296, 912] if row["map"] == "thorn_circuit" else [1408, 792])
    if row["map"] == "thorn_circuit" and ((x < 180 and y > height - 212) or (x > width - 180 and y < 212)):
        return "pocket_region"
    margin = 37.4 * min(width, height) / 792
    x0, y0, x1, y1 = row.get("arena_bounds", [margin, margin, width - margin, height - margin])
    if min(x - x0, x1 - x) <= 100 and min(y - y0, y1 - y) <= 100:
        return "corner"
    return "other"


def strict_pocket(row, episode):
    if row["map"] != "thorn_circuit":
        return False
    x, y = episode["pos"]
    return min(math.hypot(x - 1212.6, y - 59.1), math.hypot(x - 83.4, y - 852.9)) <= 40


def nav_row(rows):
    n = len(rows)
    trips = [trip for row in rows for trip in row["trips"]]
    causes = defaultdict(lambda: {"total": 0, "against": 0})
    for trip in trips:
        causes[trip["cause"]]["total"] += 1
        causes[trip["cause"]]["against"] += int(trip["against"])
    durations = {"pocket_region": 0.0, "corner": 0.0, "other": 0.0}
    legacy, censored, strict, episodes = 0.0, 0.0, 0.0, 0
    for row in rows:
        for field in ("stuck", "censored_stuck"):
            for episode in row.get(field, []):
                duration = episode["dur"]
                durations[stuck_cause(row, episode)] += duration
                strict += duration if strict_pocket(row, episode) else 0
                if field == "stuck":
                    legacy += duration
                else:
                    censored += duration
                episodes += 1
    outside = sum(r["ring_out_s"] for r in rows)
    damage = sum(r["ring_dmg"] for r in rows)
    intentional = [t for t in trips if t["cause"] == "taken"]
    against = sum(bool(t["against"]) for t in trips)
    intentional_against = sum(bool(t["against"]) for t in intentional)
    return {"battles": n, "geometry_observed_battles": sum("arena_size" in r and "arena_bounds" in r for r in rows),
            "censored_observed_battles": sum("censored_stuck" in r for r in rows),
            "timeouts": sum(r["reason"] == "time_limit" for r in rows),
            "ring_out_seconds": round(outside, 4), "ring_out_seconds_per_battle": round(outside / n, 4),
            "ring_damage": round(damage, 3), "ring_damage_per_battle": round(damage / n, 3),
            "ring_episodes_1_5s": sum(e["dur"] >= 1.5 for r in rows for h in r["heroes"] for e in h.get("eps", [])),
            "stuck_seconds": round(legacy + censored, 4), "stuck_seconds_per_battle": round((legacy + censored) / n, 4),
            "legacy_stuck_seconds": round(legacy, 4), "censored_stuck_seconds": round(censored, 4),
            "stuck_episodes": episodes, "stuck_seconds_by_cause": {k: round(v, 4) for k, v in durations.items()},
            "pocket_region_seconds": round(durations["pocket_region"], 4),
            "strict_pocket_seconds": round(strict, 4), "trips": len(trips), "intentional_trips": len(intentional),
            "against_goal_trips": against, "intentional_against_goal": intentional_against,
            "accidental_against_goal": against - intentional_against,
            "accidental_against_per_battle": round((against - intentional_against) / n, 5),
            "dropped_commit_trips": causes.get("dropped_commit", {}).get("total", 0),
            "trips_by_cause": dict(sorted(causes.items())), "wall_seconds_total": round(sum(r.get("wall", 0) for r in rows), 2)}


def summarize_nav(rows, include_suites=True):
    if not rows:
        return {"battles": 0, "by_map": {}, "by_seed_set": {}}
    by_map, by_set = defaultdict(list), defaultdict(list)
    for row in rows:
        by_map[row["map"]].append(row)
        by_set[str(row.get("_seed_set", "unknown"))].append(row)
    result = {"battles": len(rows), "total": nav_row(rows),
            "by_map": {key: nav_row(value) for key, value in sorted(by_map.items())},
            "by_seed_set": {key: {"total": nav_row(value), "by_map": {
                map_id: nav_row([r for r in value if r["map"] == map_id])
                for map_id in sorted({r["map"] for r in value})}} for key, value in sorted(by_set.items())},
            "classification": {"pocket_region": "thorn NE/SW 180x212px regions (includes boulder approaches)",
                               "strict_pocket": "40px around (1212.6,59.1) and (83.4,852.9)",
                               "corner": "within 100px of one horizontal and one vertical inner map bound",
                               "censored": "open death/end episodes included; legacy closed-only total retained",
                               "intentional": "cause == taken, preserving original analysis classification"}}
    if include_suites:
        suites = sorted({row.get("_suite", "unknown") for row in rows})
        result["by_suite"] = {suite: summarize_nav([r for r in rows if r.get("_suite", "unknown") == suite], False) for suite in suites}
    return result


def regression_metrics(rows):
    result = {}
    groups = defaultdict(list)
    for row in rows:
        groups[group_of(row)].append(row)
        groups["ALL"].append(row)
    for group, battles in sorted(groups.items()):
        heroes = [h for row in battles for h in row["heroes"]]
        alive_s = sum(h["alive_s"] for h in heroes)
        result[group] = {"battles": len(battles), "timeouts": sum(r["reason"] == "time_limit" for r in battles),
                         "timeout_pct": 100 * sum(r["reason"] == "time_limit" for r in battles) / len(battles),
                         "unobserved_order_pct": 100 * sum(h.get("unobserved_orders", 0) for h in heroes) / max(1, sum(h.get("attack_orders", 0) for h in heroes)),
                         "stuck_pct": 100 * sum(h.get("stuck_s", 0) for h in heroes) / max(1e-6, alive_s),
                         "void_stall_pct": 100 * sum(h.get("void_stall_s", 0) for h in heroes) / max(1e-6, alive_s),
                         "env_dmg_per_hero_min": sum(sum(h.get("haz_dmg", {}).values()) for h in heroes) / max(1e-6, alive_s / 60)}
    return result


def compare_nav(old, new):
    keys = ("ring_out_seconds_per_battle", "ring_damage_per_battle", "ring_episodes_1_5s", "stuck_seconds_per_battle",
            "strict_pocket_seconds", "accidental_against_per_battle", "intentional_against_goal", "dropped_commit_trips", "timeouts")
    return {map_id: {key: {"before": prior[key], "after": row[key], "delta": round(row[key] - prior[key], 5)} for key in keys}
            for map_id, row in new.get("by_map", {}).items() if (prior := old.get("by_map", {}).get(map_id))}


def paired_navigation(old_rows, new_rows):
    """Pair exact map/seed/ordered composition; report unmatched evidence."""
    def key(row):
        return row["map"], row["seed"], tuple(row["comp"])
    old = {key(row): row for row in old_rows}
    new = {key(row): row for row in new_rows}
    common = sorted(old.keys() & new.keys())
    fields = ("ring_out_seconds", "ring_damage", "ring_episodes_1_5s", "stuck_seconds",
              "pocket_region_seconds", "strict_pocket_seconds", "accidental_against_goal",
              "intentional_against_goal", "dropped_commit_trips", "timeouts")
    groups = defaultdict(list)
    for case in common:
        groups[case[0]].append(case)
    result = {"matched": len(common), "only_before": len(old.keys() - new.keys()),
              "only_after": len(new.keys() - old.keys()), "by_map": {}}
    for map_id, cases in sorted(groups.items()):
        metrics = {}
        for field in fields:
            differences = [new[case]["metrics"][field] - old[case]["metrics"][field] for case in cases]
            mean = stats.mean(differences)
            se = stats.stdev(differences) / math.sqrt(len(differences)) if len(differences) > 1 else None
            metrics[field] = {"mean_delta": round(mean, 6), "standard_error": round(se, 6) if se is not None else None,
                              "approx_ci95": [round(mean - 1.96 * se, 6), round(mean + 1.96 * se, 6)] if se is not None else None}
        result["by_map"][map_id] = {"pairs": len(cases), "metrics": metrics}
    return result


def nav_markdown(nav, title="이동 관측 (종료·사망 시 열린 끼임 포함)"):
    if len(nav.get("by_suite", {})) > 1:
        return "\n".join(nav_markdown(value, "이동 관측: " + suite) for suite, value in nav["by_suite"].items())
    lines = ["\n## " + title + "\n",
             "| 시드 집합 | 맵 | 경기 | 결계 밖 초/전 | 피해/전 | 1.5초+ | 끼임 초/전 | 주머니 초 | 엄격 주머니 초 | 역방향/전 | 의도적 역방향 | 링크 중도 포기 | 시간초과 |",
             "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for seed_set, data in nav.get("by_seed_set", {}).items():
        for map_id, row in data["by_map"].items():
            lines.append("| %s | %s | %d | %.4f | %.2f | %d | %.4f | %.2f | %.2f | %.4f | %d | %d | %d |" % (
                seed_set, map_id, row["battles"], row["ring_out_seconds_per_battle"], row["ring_damage_per_battle"],
                row["ring_episodes_1_5s"], row["stuck_seconds_per_battle"], row["stuck_seconds_by_cause"]["pocket_region"],
                row["strict_pocket_seconds"], row["accidental_against_per_battle"], row["intentional_against_goal"],
                row["dropped_commit_trips"], row["timeouts"]))
    lines.append("\n원인 분류: " + json.dumps(nav.get("classification", {}), ensure_ascii=False))
    for map_id, row in nav.get("by_map", {}).items():
        lines.append("\n- %s: 끼임 %s; 종료/사망 보완 %.2f초; 링크 %s" % (
            map_id, json.dumps(row["stuck_seconds_by_cause"], ensure_ascii=False), row["censored_stuck_seconds"],
            json.dumps(row["trips_by_cause"], ensure_ascii=False)))
    return "\n".join(lines) + "\n"


def main(argv=None):
    import argparse
    from pathlib import Path
    try:
        from .run import safe_output, write_json, PROJECT
    except ImportError:
        from run import safe_output, write_json, PROJECT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--label", default="telemetry_v2")
    parser.add_argument("--compare", type=Path)
    parser.add_argument("--allow-partial", action="store_true", help="Diagnostic only; never acceptance evidence")
    options = parser.parse_args(argv)
    out = (options.out or Path(options.inputs[0])).resolve()
    safe_output(out, PROJECT)
    out.mkdir(parents=True, exist_ok=True)
    rows, roster, manifests = read_inputs(options.inputs, options.allow_partial)
    probe = [r for r in rows if r["_kind"] == "probe"]
    nav = [r for r in rows if r["_kind"] == "nav"]
    result = summarize_probe(probe, roster if probe else {}, options.label, options.inputs)
    result.update({"navigation": summarize_nav(nav), "regression": regression_metrics(probe),
                   "provenance": manifests, "partial_allowed": options.allow_partial,
                   "total_battles": len(rows), "schema": 2,
                   "navigation_matches": [{"map": r["map"], "seed": r["seed"], "comp": r["comp"],
                                            "seed_set": r.get("_seed_set"), "metrics": nav_row([r])} for r in nav]})
    result["decision_observer_complete"] = all(r.get("probe_args", {}).get("ai") == "tactician" for r in probe)
    result["observation_notes"] = [] if result["decision_observer_complete"] else [
        "Custom AI paths use AIFactory directly in unchanged ai_probe_153; decision-time metrics are not acceptance evidence."]
    if options.compare:
        previous = json.loads(options.compare.read_text(encoding="utf-8"))
        result["compare"] = compare(previous, result)
        result["compare_navigation"] = compare_nav(previous.get("navigation", {}), result["navigation"])
        result["paired_navigation"] = paired_navigation(previous.get("navigation_matches", []), result["navigation_matches"])
    write_json(out / f"summary_{options.label}.json", result)
    report = markdown(result) if probe else "# V2 이동 관측 요약 (%s)\n" % options.label
    report += "\n일반 AI 관측 %d전 + 이동 관측 %d전 = 총 %d전.\n" % (len(probe), len(nav), len(rows))
    if nav:
        report += nav_markdown(result["navigation"])
    if "compare_navigation" in result:
        report += "\n## 이동 전후 차이\n\n" + json.dumps(result["compare_navigation"], ensure_ascii=False, indent=2) + "\n"
    with (out / f"summary_{options.label}_KO.md").open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(report)
    print(f"ANALYZED probe={len(probe)} nav={len(nav)} output={out}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as exc:
        print("ANALYSIS_ERROR " + str(exc), file=sys.stderr)
        raise SystemExit(2)
