"""Exercise real course transitions/physics using a clean, isolated Godot project."""
import argparse
import json
from pathlib import Path
import shutil
import time
import uuid
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import run_checked, isolated_environment, SAVE_WRITE_WARNING, SAVE_RECOVERY_WARNING

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
run = repo / ".test-output/course-tests" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
project = run / "project"
shutil.copytree(repo / "idle-golf", project, ignore=shutil.ignore_patterns(".godot", "builds", ".git"))
(project / "tests").mkdir()
shutil.copy2(repo / "tests/course_regression.gd", project / "tests/course_regression.gd")
shutil.copy2(repo / "tests/shot_regression.gd", project / "tests/shot_regression.gd")
shutil.copy2(repo / "tests/reward_regression.gd", project / "tests/reward_regression.gd")
shutil.copy2(repo / "tests/cosmetic_regression.gd", project / "tests/cosmetic_regression.gd")
shutil.copy2(repo / "tests/market_regression.gd", project / "tests/market_regression.gd")
shutil.copy2(repo / "tests/shutdown_regression.gd", project / "tests/shutdown_regression.gd")
shutil.copy2(repo / "tests/target_regression.gd", project / "tests/target_regression.gd")
shutil.copy2(repo / "tests/completion_regression.gd", project / "tests/completion_regression.gd")
shutil.copy2(repo / "tests/golfer_regression.gd", project / "tests/golfer_regression.gd")
settings = project / "project.godot"
settings.write_text(settings.read_text().replace('edition="demo"', 'edition="full"'))
env = isolated_environment(run)
stages = []
for label, options in [("import", ["--import"])] + [
    (course, ["--fixed-fps", "60", "--script", "res://tests/course_regression.gd", "--", course])
    for course in ["course1", "course2", "course3"]
] + [(label, ["--fixed-fps", "60", "--script", script]) for label, script in [
    ("shot-context", "res://tests/shot_regression.gd"),
    ("reward-rules", "res://tests/reward_regression.gd"),
    ("cosmetic-fragments", "res://tests/cosmetic_regression.gd"),
    ("market-persistence", "res://tests/market_regression.gd"),
    ("shutdown", "res://tests/shutdown_regression.gd"),
    ("course-targets", "res://tests/target_regression.gd"),
    ("completion", "res://tests/completion_regression.gd"),
    ("golfers", "res://tests/golfer_regression.gd"),
]]:
    # Long flights at uncapped headless speeds can exhaust Jolt's job queue.
    # Keep the real 60 Hz simulation; only pace the reachability harness.
    pacing = ["--max-fps", "1000"] if label == "course-targets" else []
    output = run_checked([str(args.godot.resolve()), "--headless", "--path", str(project)] + options + pacing,
        run, label, env=env, editor=label == "import",
        expected={"market-persistence": (SAVE_RECOVERY_WARNING, SAVE_WRITE_WARNING, SAVE_WRITE_WARNING),
                  "completion": (SAVE_WRITE_WARNING, SAVE_WRITE_WARNING)}.get(label, ()))
    if label != "import":
        assert "failures=0" in output, output
        print(next(line for line in output.splitlines() if line.startswith(("COURSE_TESTS", "SHOT_TESTS", "REWARD_TESTS", "COSMETIC_TESTS", "MARKET_TESTS", "SHUTDOWN_TESTS", "TARGET_TESTS", "COMPLETION_TESTS", "GOLFER_TESTS"))), flush=True)
    stages.append({"stage": label, "exit_code": 0})
(run / "summary.json").write_text(json.dumps({"result": "passed", "stages": stages}, indent=2))
print(f"PASS: course isolation suite. Logs: {run}", flush=True)
