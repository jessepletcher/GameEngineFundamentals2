"""Verify economy transactions, run a campaign model, and check its shots in Godot."""
import argparse
import csv
import json
import math
from pathlib import Path
import shutil
import sys

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
from capture_economy import capture
from godot_checks import isolated_environment, run_checked
from simulate_progression import Campaign, CASH


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    snapshot = capture(args.godot.resolve())
    data = json.loads(snapshot.read_text())
    run = snapshot.parent
    project = run / "project"
    env = isolated_environment(run)
    # Detect model drift if the live game changes stats or physics assumptions.
    assert data["gravity"] == 9.8 and data["damping"] == .1
    assert data["base_speed"] == 10 and data["base_interval"] == 5 and data["base_spread"] == 8
    probe = Campaign(data)
    for sample, expected in zip(data["reward_samples"], [(7,.7), (205,20.5), (500,50)]):
        assert math.isclose(sample["money"],expected[0]) and math.isclose(sample["xp"],expected[1])
    for pair, expected in zip([(1000,0), (1000,1000), (2000,1000), (1e9,1000)], data["retirement_samples"]):
        probe.run_money, probe.best = pair
        assert probe.medals_due() == expected
    for level, expected in data["stats"].items():
        for key in CASH:
            probe.upgrades[key] = int(level)
        speed, rate, money, consistency, xp = probe.stats()
        assert all(math.isclose(a,b,rel_tol=1e-8) for a,b in zip(
            [speed/data["base_speed"],rate*data["base_interval"],money,consistency,xp],expected)), level
    for script in ["economy_regression.gd", "economy_physics.gd"]:
        shutil.copy2(REPO / "tests" / script, project / script)
    output = run_checked([str(args.godot.resolve()), "--headless", "--path", str(project),
                          "--script", "res://economy_regression.gd"], run, "economy-regression", env=env)
    assert "failures=0" in output
    print(next(line for line in output.splitlines() if line.startswith("ECONOMY_TESTS")), flush=True)
    scenarios = []
    for policy, factor, cadence in [("balanced",1,60), ("speed",1,60), ("income",1,60),
                                    ("balanced",.75,60), ("balanced",1.5,60), ("balanced",1,300)]:
        result = Campaign(data, policy, factor, cadence).run()
        assert result["completed"], (policy, factor, cadence, result)
        scenarios.append(result)
        print(f"MODEL {policy} income={factor} cadence={cadence}: "
              + ", ".join(f"{c['course_hours']:.2f}h" for c in result["courses"])
              + f"; total={result['hours']:.2f}h", flush=True)
    reference = scenarios[0]
    assert 55 <= reference["hours"] <= 65, "Reference campaign outside design band"
    assert all(16 <= c["course_hours"] <= 24 for c in reference["courses"]), "Course outside design band"
    (run / "campaigns.json").write_text(json.dumps(scenarios, indent=2))
    (project / "campaign.json").write_text(json.dumps(reference))
    with (run / "campaigns.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["policy", "income_factor", "purchase_interval_seconds", "course1_hours", "course2_hours", "course3_hours", "total_hours"])
        for r in scenarios:
            writer.writerow([r["policy"], r["income_factor"], r["purchase_interval_seconds"]]
                            + [round(c["course_hours"],3) for c in r["courses"]] + [round(r["hours"],3)])
    output = run_checked([str(args.godot.resolve()), "--headless", "--path", str(project),
                          "--fixed-fps", "60", "--max-fps", "1000", "--script", "res://economy_physics.gd"],
                         run, "economy-physics", env=env, timeout=180)
    assert "failures=0" in output
    print("\n".join(l for l in output.splitlines() if l.startswith("ECONOMY_PHYSICS")), flush=True)
    (run / "summary.json").write_text(json.dumps({"result":"passed", "reference_hours":reference["hours"],
        "course_hours":[c["course_hours"] for c in reference["courses"]],
        "note":"Expected-value model and shot calibration; real player pacing remains C08/G04."}, indent=2))
    print(f"PASS: economy checks. Logs: {run}", flush=True)


if __name__ == "__main__":
    main()
