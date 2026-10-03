"""Pure S5 evaluation for tools/telemetry_v2/analyze.py schema 2.

evaluate({'balance': ..., 'nav_ring_thorn': ..., 'nav_links': ...}, baseline=None)
accepts parsed summaries, performs no I/O, and never mutates them. `baseline`
may be one combined C1 summary or a mapping with the same three suite names.
Optional summaries['expected_roster'] supplies a future full roster. Otherwise
the 22 Phase-1 IDs are the minimum roster and all additional observed IDs are
also checked. Wilson intervals are recomputed from battles_list, not rounded
summary win rates. Draws count as half a win, matching the official analyzer.
"""
from __future__ import annotations

from collections import defaultdict
import math
import re

ROSTER_22 = frozenset({"swordsman", "archer", "mage", "sniper", "werewolf", "giant", "aphrodite", "blood_mage",
    "fisherman", "baseball", "pirate", "joker", "metatron", "plague_doctor", "hive_mind", "nitro", "dimensionalist",
    "hermes", "world_tree", "torturer", "engineer", "politician"})
LINK_MAPS = frozenset({"dimensional_lattice", "rift_harbor", "furnace_basin", "gale_corridor"})


class EvidenceError(ValueError):
    pass


def need(condition, label):
    if not condition:
        raise EvidenceError(label)


def field(value, *path):
    current = value
    for name in path:
        need(isinstance(current, dict) and name in current, "Missing field: " + ".".join(map(str, path)))
        current = current[name]
    return current


def number(value, label, *, minimum=0, maximum=None, integer=False):
    need(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value), f"Not a finite number: {label}")
    need(value >= minimum and (maximum is None or value <= maximum), f"Out of range: {label}")
    need(not integer or value == int(value), f"Not an integer: {label}")
    return int(value) if integer else float(value)


def count(value, label, minimum=0):
    return number(value, label, minimum=minimum, integer=True)


def header(summary):
    need(isinstance(summary, dict), "Summary must be an object")
    need(field(summary, "schema") == 2, "Expected telemetry schema 2")
    need(field(summary, "partial_allowed") is False, "Partial/diagnostic runs cannot pass release gates")
    manifests = field(summary, "provenance")
    need(isinstance(manifests, list) and manifests, "Completed manifest provenance is required")
    need(all(isinstance(row, dict) and row.get("complete") is True for row in manifests), "Incomplete manifest provenance")


def wilson(wins, n, z=1.96):
    need(n > 0 and 0 <= wins <= n, "Wilson requires positive sample count and valid wins")
    p = wins / n
    divisor = 1 + z * z / n
    center = (p + z * z / (2 * n)) / divisor
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / divisor
    return [max(0.0, center - half), min(1.0, center + half)]


def balance_rows(summary, expected_roster):
    header(summary)
    matches = field(summary, "battles_list")
    need(isinstance(matches, list) and matches, "balance.battles_list is empty/missing")
    need(count(field(summary, "battles"), "balance.battles", 1) == len(matches), "Balance battle count does not match rows")
    supplied = field(summary, "hero")
    need(isinstance(supplied, list) and supplied, "Balance hero table is empty/missing")
    metadata = {}
    for row in supplied:
        hero = field(row, "hero")
        need(isinstance(hero, str) and hero and hero not in metadata, "Invalid/duplicate hero table ID")
        metadata[hero] = row
    need(set(expected_roster) <= set(metadata), "Missing roster heroes: " + ", ".join(sorted(set(expected_roster) - set(metadata))))
    totals = defaultdict(lambda: {"n_team": 0, "wins": 0, "losses": 0, "draws": 0})
    groups = defaultdict(lambda: {"battles": 0, "timeouts": 0})
    seen = set()
    for row in matches:
        group, arena, seed = field(row, "group"), field(row, "map"), field(row, "seed")
        need(isinstance(group, str) and re.fullmatch(r"(?:E|C|DM)\d+", group) is not None, "Unknown battle group")
        need(isinstance(arena, str) and arena, "Invalid map ID")
        count(seed, "battle.seed")
        comp = field(row, "comp")
        need(isinstance(comp, list) and all(isinstance(hero, str) and hero for hero in comp), "Invalid ordered composition")
        need(len(comp) == len(set(comp)), "Repeated hero in non-battleground telemetry composition")
        key = (group, arena, seed, tuple(comp))
        need(key not in seen, "Duplicate battle row")
        seen.add(key)
        reason = field(row, "reason")
        need(isinstance(reason, str) and reason, "Missing completion reason")
        groups[group]["battles"] += 1
        groups[group]["timeouts"] += int(reason == "time_limit")
        winner = field(row, "winner")
        if group.startswith("DM"):
            count(winner, "deathmatch winner")
            need(len(comp) == int(group[2:]), "Deathmatch group size differs from composition")
            continue
        size = int(group[1:])
        need(size > 0 and len(comp) == size * 2, "Team group size differs from composition")
        need(not isinstance(winner, bool) and winner in (0, 1, 2), "Invalid team winner")
        for index, hero in enumerate(comp):
            need(hero in metadata, "Battle hero missing from summary table: " + hero)
            team = 0 if index < size else 1
            values = totals[hero]
            values["n_team"] += 1
            values["draws" if winner == 2 else ("wins" if winner == team else "losses")] += 1
    supplied_groups = field(summary, "by_group")
    need(isinstance(supplied_groups, dict) and set(supplied_groups) == set(groups), "Group summary differs from battle rows")
    for group, exact in groups.items():
        for name in ("battles", "timeouts"):
            need(count(field(supplied_groups, group, name), group + "." + name) == exact[name], "Group counts disagree: " + group)
    heroes = {}
    for hero, meta in sorted(metadata.items()):
        values = totals[hero]
        n = values["n_team"]
        need(count(field(meta, "n_team"), hero + ".n_team") == n, "Hero sample count differs from battle rows: " + hero)
        need(n > 0, "No team sample for hero: " + hero)
        score_wins = values["wins"] + 0.5 * values["draws"]
        p = score_wins / n
        interval = wilson(score_wins, n)
        reported_p = number(field(meta, "win_rate"), hero + ".win_rate", maximum=1)
        reported_ci = field(meta, "ci95")
        need(isinstance(reported_ci, list) and len(reported_ci) == 2, "Missing Wilson interval: " + hero)
        need(abs(reported_p - round(p, 3)) < 1e-12, "Rounded hero win rate disagrees with exact rows: " + hero)
        for reported, exact in zip(reported_ci, interval):
            need(abs(number(reported, hero + ".ci95", maximum=1) - round(exact, 3)) < 1e-12,
                 "Reported Wilson interval disagrees with exact rows: " + hero)
        heroes[hero] = {"id": hero, "name": meta.get("name", hero), **values, "score_wins": score_wins,
                        "win_rate": p, "wilson95": interval, "low_interval_below_0_40": interval[1] < 0.40}
    timeouts = sum(row["timeouts"] for row in groups.values())
    return heroes, {"battles": len(matches), "timeouts": timeouts, "rate": timeouts / len(matches)}


def navigation(summary, suite):
    header(summary)
    nav = field(summary, "navigation")
    by_suite = nav.get("by_suite", {}) if isinstance(nav, dict) else {}
    if by_suite:
        need(suite in by_suite, "Missing navigation suite: " + suite)
        nav = by_suite[suite]
    sets = field(nav, "by_seed_set")
    need(isinstance(sets, dict) and set(sets) == {"1", "2"}, "Navigation requires exactly seed sets 1 and 2")
    return nav, sets


def nav_values(summary, suite, seed):
    _, sets = navigation(summary, suite)
    row = sets[seed]
    maps = field(row, "by_map")
    expected = {"thorn_circuit", "bastion_ring"} if suite == "nav_ring_thorn" else LINK_MAPS
    need(isinstance(maps, dict) and set(maps) == set(expected), suite + " map set is incomplete")
    expected_per_map = 40 if suite == "nav_ring_thorn" else 24
    for name in sorted(expected):
        need(count(field(maps, name, "battles"), name + ".battles", 1) == expected_per_map,
             "Incomplete fixed-seed map sample: " + name)
    total = field(row, "total")
    battles = count(field(total, "battles"), suite + ".battles", 1)
    need(battles == expected_per_map * len(expected), "Navigation denominator differs from per-map counts")
    timeouts = count(field(total, "timeouts"), suite + ".timeouts")
    need(timeouts <= battles, "Timeout count exceeds battles")
    values = {"battles": battles, "timeouts": timeouts, "timeout_rate": timeouts / battles}
    if suite == "nav_ring_thorn":
        thorn, bastion = maps["thorn_circuit"], maps["bastion_ring"]
        values["thorn_strict_pocket_seconds"] = number(field(thorn, "strict_pocket_seconds"), "thorn.strict_pocket_seconds")
        values["thorn_pocket_region_seconds"] = number(field(thorn, "pocket_region_seconds"), "thorn.pocket_region_seconds")
        values["bastion_ring_out_seconds"] = number(field(bastion, "ring_out_seconds"), "bastion.ring_out_seconds")
        values["bastion_battles"] = count(field(bastion, "battles"), "bastion.battles", 1)
        values["bastion_ring_out_per_battle"] = values["bastion_ring_out_seconds"] / values["bastion_battles"]
    else:
        accidental = count(field(total, "accidental_against_goal"), "links.accidental_against_goal")
        values["accidental_against_goal"] = accidental
        values["accidental_against_per_battle"] = accidental / battles
        values["intentional_against_goal"] = total.get("intentional_against_goal")
        values["dropped_commit_trips"] = total.get("dropped_commit_trips")
    return values


def evaluate(summaries, baseline=None):
    """Return {status, gates, heroes, observations, errors, ...}; missing evidence fails."""
    result = {"status": "FAIL", "gates": [], "heroes": [], "observations": [], "errors": [], "warnings": [],
              "external_checks": [{"metric": "map_connectivity_v2", "stage": "S2", "status": "EXTERNAL",
                  "note": "Navigation samples do not prove map connectivity; the dedicated test is required."}],
              "definitions": {"timeouts": "reason == time_limit, matching telemetry_v2/analyze.py",
                  "team_win_rate": "(wins + 0.5 * draws) / n_team; deathmatch appearances excluded",
                  "wilson95": "Wilson score interval, z=1.96, same draw scoring as analyzer",
                  "strict_pocket": "40px around documented sealed endpoints; broad approach region is diagnostic only"}}

    def gate(metric, observed, threshold, passed, *, before=None, **details):
        result["gates"].append({"metric": metric, "observed": observed, "threshold": threshold,
                                "status": "PASS" if passed else "FAIL", "baseline": before, **details})

    def failure(metric, exc):
        message = str(exc)
        result["errors"].append({"metric": metric, "error": message})
        gate(metric, None, "complete and consistent schema-2 evidence", False, error=message)

    def older(suite):
        if not isinstance(baseline, dict): return None
        return baseline.get(suite) if suite in baseline else baseline

    if not isinstance(summaries, dict):
        failure("telemetry.input", "Expected a mapping of suite summaries")
        return result
    expected = summaries.get("expected_roster", sorted(ROSTER_22))
    if not isinstance(expected, list) or not expected or any(not isinstance(hero, str) or not hero for hero in expected) or len(set(expected)) != len(expected):
        failure("telemetry.expected_roster", "Expected a nonempty list of distinct hero IDs")
        return result
    prior_heroes, prior_balance = {}, None
    if older("balance") is not None:
        try:
            prior_heroes, prior_balance = balance_rows(older("balance"), [])
        except (EvidenceError, TypeError, ValueError) as exc:
            result["warnings"].append("Baseline balance cannot be compared exactly: " + str(exc))
    try:
        heroes, balance = balance_rows(field(summaries, "balance"), expected)
        gate("balance.time_limit_rate", balance["rate"], "<= 0.05", balance["rate"] <= .05,
             before=prior_balance["rate"] if prior_balance else None,
             numerator=balance["timeouts"], denominator=balance["battles"], unit="fraction")
        for hero, row in heroes.items():
            old = prior_heroes.get(hero)
            row["baseline"] = old
            row["delta_win_rate"] = row["win_rate"] - old["win_rate"] if old else None
            row["sample_status"] = "PASS" if row["n_team"] >= 200 else "FAIL"
            result["heroes"].append(row)
            gate("hero." + hero + ".n_team", row["n_team"], ">= 200", row["n_team"] >= 200,
                 before=old["n_team"] if old else None, hero=hero, unit="appearances")
        for hero in ("metatron", "world_tree"):
            need(hero in heroes, "Missing target hero: " + hero)
            row = heroes[hero]
            gate("hero." + hero + ".team_win_rate", row["win_rate"], "0.45 <= value <= 0.60", .45 <= row["win_rate"] <= .60,
                 before=prior_heroes.get(hero, {}).get("win_rate"), hero=hero, n_team=row["n_team"], wilson95=row["wilson95"], unit="fraction")
    except (EvidenceError, TypeError, ValueError) as exc:
        failure("balance.evidence", exc)
    for suite in ("nav_ring_thorn", "nav_links"):
        for seed in ("1", "2"):
            before = None
            if older(suite) is not None:
                try:
                    before = nav_values(older(suite), suite, seed)
                except (EvidenceError, TypeError, ValueError):
                    pass  # A C1 probe-only baseline has no navigation comparison.
            try:
                values = nav_values(field(summaries, suite), suite, seed)
                prefix = f"{suite}.seed_set_{seed}"
                gate(prefix + ".time_limit_rate", values["timeout_rate"], "<= 0.05", values["timeout_rate"] <= .05,
                     before=before["timeout_rate"] if before else None, seed_set=int(seed), numerator=values["timeouts"], denominator=values["battles"], unit="fraction")
                if suite == "nav_ring_thorn":
                    gate(prefix + ".thorn_strict_pocket_seconds", values["thorn_strict_pocket_seconds"], "== 0", values["thorn_strict_pocket_seconds"] == 0,
                         before=before["thorn_strict_pocket_seconds"] if before else None, seed_set=int(seed), map="thorn_circuit", unit="seconds")
                    gate(prefix + ".bastion_ring_out_seconds_per_battle", values["bastion_ring_out_per_battle"], "<= 0.6", values["bastion_ring_out_per_battle"] <= .6,
                         before=before["bastion_ring_out_per_battle"] if before else None, seed_set=int(seed), map="bastion_ring",
                         numerator=values["bastion_ring_out_seconds"], denominator=values["bastion_battles"], unit="seconds/battle")
                    result["observations"].append({"metric": prefix + ".thorn_pocket_region_seconds", "observed": values["thorn_pocket_region_seconds"],
                        "baseline": before["thorn_pocket_region_seconds"] if before else None, "gated": False,
                        "note": "Broad approach region; not the strict sealed-pocket criterion."})
                else:
                    gate(prefix + ".unintended_reverse_trips_per_battle", values["accidental_against_per_battle"], "<= 0.25", values["accidental_against_per_battle"] <= .25,
                         before=before["accidental_against_per_battle"] if before else None, seed_set=int(seed), numerator=values["accidental_against_goal"], denominator=values["battles"], unit="trips/battle")
                    result["observations"].append({"metric": prefix + ".link_causes", "gated": False,
                        "intentional_against_goal": values["intentional_against_goal"], "dropped_commit_trips": values["dropped_commit_trips"]})
            except (EvidenceError, TypeError, ValueError) as exc:
                failure(f"{suite}.seed_set_{seed}.evidence", exc)
    result["status"] = "PASS" if result["gates"] and all(row["status"] == "PASS" for row in result["gates"]) else "FAIL"
    result["passed_gates"] = sum(row["status"] == "PASS" for row in result["gates"])
    result["failed_gates"] = sum(row["status"] == "FAIL" for row in result["gates"])
    return result
