"""Exercise real Godot audio mixing with PCM captures in an isolated Dummy-driver run."""
import argparse
import json
from pathlib import Path
import shutil
import time
import uuid
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import run_checked, isolated_environment

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
run = repo / ".test-output/audio-tests" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
project = run / "project"
shutil.copytree(repo / "idle-golf", project, ignore=shutil.ignore_patterns(".godot", "builds", ".git"))
(project / "tests").mkdir()
for name in ["audio_test_manager.gd", "audio_regression.gd"]:
    shutil.copy2(repo / "tests" / name, project / "tests" / name)
settings = project / "project.godot"
original = 'AudioManager="*res://AudioManager.gd"'
source = settings.read_text()
assert source.count(original) == 1
settings.write_text(source.replace(original, 'AudioManager="*res://tests/audio_test_manager.gd"'))
env = isolated_environment(run)
stages = []
for label, options in [("import", ["--import"]), ("audio", ["--script", "res://tests/audio_regression.gd"])]:
    output = run_checked([str(args.godot.resolve()), "--headless", "--audio-driver", "Dummy", "--path", str(project)] + options,
        run, label, env=env, editor=label == "import")
    if label == "audio":
        assert "failures=0" in output, output
        print(next(line for line in output.splitlines() if line.startswith("AUDIO_TESTS")), flush=True)
    stages.append({"stage": label, "exit_code": 0})
(run / "summary.json").write_text(json.dumps({"result": "passed", "stages": stages}, indent=2))
print(f"PASS: audio PCM suite. Logs: {run}", flush=True)
