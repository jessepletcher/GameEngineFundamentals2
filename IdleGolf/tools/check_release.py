"""Required source validation before producing Windows release candidates."""
import argparse
from pathlib import Path
import subprocess
import sys

import godot_checks  # Reject optimized Python before running any fixture checks.

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
for script in ["test_godot_checks.py", "run_clean_checks.py", "run_save_tests.py",
               "run_course_tests.py", "run_audio_tests.py", "run_economy_tests.py"]:
    command = [sys.executable, str(repo / "tests" / script)]
    if script != "test_godot_checks.py":
        command += ["--godot", str(args.godot.resolve())]
    print(f"CHECK: {script}", flush=True)
    subprocess.run(command, cwd=repo, check=True)
print("PASS: all source release checks", flush=True)
