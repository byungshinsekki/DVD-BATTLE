"""Head-to-head match inputs for the V1.5 conquest AI evaluation.

usage: h2h_specs_15.py OUT N_COMPS SIZES A_AI B_AI RULESET [SEED0] [mirror]

Every composition is played twice with the same seed, once with A's AI on
each side. The V1.5 release inputs (reports/ai_eval_15/h2h_specs_15.json):
  python tools/ai_eval_15/h2h_specs_15.py reports/ai_eval_15/h2h_specs_15.json 16 5,3 tactician tactician14 control 20260930
"""
import json
import random
import sys

ROSTER = ["swordsman", "archer", "mage", "sniper", "werewolf", "giant", "aphrodite", "blood_mage", "fisherman", "baseball", "pirate",
          "joker", "metatron", "plague_doctor", "hive_mind", "nitro", "dimensionalist", "hermes", "world_tree", "torturer", "engineer", "politician"]
CONTROL_ARENAS = ["control_crossroads", "control_citadel", "control_waterway"]
ELIMINATION_ARENAS = ["classic", "ruined_gate", "thorn_circuit", "furnace_basin", "wind_temple", "dimensional_lattice", "crossroads",
                      "moon_garden", "twin_foundry", "gale_corridor", "rift_harbor", "bastion_ring"]


def main():
    out, n, sizes, a_ai, b_ai, ruleset = sys.argv[1], int(sys.argv[2]), [int(x) for x in sys.argv[3].split(",")], sys.argv[4], sys.argv[5], sys.argv[6]
    seed0 = int(sys.argv[7]) if len(sys.argv) > 7 else 1000
    mirror = len(sys.argv) > 8 and sys.argv[8] == "mirror"
    arenas = CONTROL_ARENAS if ruleset == "control" else ELIMINATION_ARENAS
    specs = []
    for k in range(n):
        r = random.Random(seed0 + k)
        size = sizes[k % len(sizes)]
        pool = ROSTER[:]
        r.shuffle(pool)
        blue, red = pool[:size], pool[size:2 * size]
        if mirror:
            red = blue[:]
        arena = arenas[k % len(arenas)]
        for swap in (0, 1):
            cfg = {"ruleset": ruleset, "arena_id": arena, "seed": seed0 * 7 + k, "blue": blue, "red": red,
                   "blue_ai": b_ai if swap else a_ai, "red_ai": a_ai if swap else b_ai}
            if ruleset == "control":
                cfg["max_time"] = 480.0
            specs.append({"id": "%d_%d" % (k, swap), "config": cfg, "a_side": 1 if swap else 0})
    with open(out, "w", encoding="utf-8") as file:
        json.dump(specs, file)
    print(len(specs))


if __name__ == "__main__":
    main()
