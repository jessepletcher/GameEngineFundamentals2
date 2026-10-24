"""Run real Godot save/quit regressions in a disposable project, never player saves."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time
import uuid
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import check_output, run_checked, isolated_environment, SAVE_WRITE_WARNING, SAVE_BLOCKED_WARNING


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True, help="Godot 4.6 editor executable")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    root = repo / ".test-output" / "save-tests"
    root.mkdir(parents=True, exist_ok=True)
    executable = args.godot.resolve()
    run = root / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    project = run / "project"
    shutil.copytree(repo / "idle-golf", project,
                    ignore=shutil.ignore_patterns(".godot", "builds", ".git"))
    shutil.copytree(repo / "tests", project / "tests",
                    ignore=shutil.ignore_patterns("__pycache__"))
    (project / "test-data").mkdir()
    state_file = project / "BuildProfile.gd"
    state_source = state_file.read_text(encoding="utf-8")
    original = 'const DEMO_SAVE := "user://idle_golf_demo_v0_1.cfg"'
    assert state_source.count(original) == 1, "Save isolation guard must be updated before running"
    state_file.write_text(state_source.replace(original,
        'const DEMO_SAVE := "res://test-data/game-state.cfg"').replace(
        'const FULL_SAVE := "user://idle_golf_full.cfg"',
        'const FULL_SAVE := "res://test-data/full.cfg"'), encoding="utf-8")
    # Distinguish incidental engine-generated user data as well.
    settings = project / "project.godot"
    settings.write_text(settings.read_text(encoding="utf-8").replace(
        'config/name="IdleGolf"', 'config/name="IdleGolfSaveTests"'), encoding="utf-8")
    base = [str(executable), "--headless", "--path", str(project)]
    env = isolated_environment(run, "IdleGolfSaveTests")
    stages: list[dict] = []

    def execute(label: str, options: list[str], timeout: int = 90) -> str:
        output = run_checked(base + options, run, label, env=env, timeout=timeout,
                             editor=label == "import", malformed_save=label == "save-regression",
                             expected={"save-regression": (SAVE_WRITE_WARNING, SAVE_BLOCKED_WARNING),
                                       "failed_close": (SAVE_WRITE_WARNING,), "discard": (SAVE_WRITE_WARNING,)}.get(label, ()))
        stages.append({"stage": label, "exit_code": 0})
        print(json.dumps(stages[-1]), flush=True)
        return output

    execute("import", ["--import"])
    output = execute("save-regression", ["--script", "res://tests/save_regression.gd"])
    assert "failures=0" in output, output
    print(next(line for line in output.splitlines() if line.startswith("SAVE_TESTS")), flush=True)
    for mode, expected in [("close", "147.25"), ("exit", "258.5"), ("failed_close", "369.75"), ("discard", "369.75")]:
        output = execute(mode, ["--script", "res://tests/quit_probe.gd", "--", mode], timeout=15)
        assert "ERROR:" not in output and "leaked" not in output, output
        saved = (project / "test-data" / "game-state.cfg").read_text(encoding="utf-8")
        assert f"money={expected}" in saved, (mode, saved)
        if mode == "failed_close":
            assert "QUIT_FAILURE_KEPT_SESSION" in output, output
        if mode == "discard":
            (project / "test-data" / "game-state.cfg.tmp").rmdir()
    crash_output = run / "crash-output.txt"
    with crash_output.open("w", encoding="utf-8") as capture:
        process = subprocess.Popen(base + ["--verbose", "--log-file", str(run / "crash.log"),
            "--script", "res://tests/quit_probe.gd", "--", "crash"],
            env=env, stdout=capture, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while "READY_FOR_FORCED_STOP" not in crash_output.read_text(encoding="utf-8"):
                if process.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("Crash fixture failed to reach its checkpoint")
                time.sleep(0.05)
            process.kill()
            process.wait(timeout=10)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    check_output(crash_output.read_text(encoding="utf-8"))
    check_output((run / "crash.log").read_text(encoding="utf-8"))
    output = execute("verify-crash", ["--script", "res://tests/quit_probe.gd", "--", "verify_crash"])
    assert "FORCED_STOP_RECOVERED_LAST_COMMIT" in output, output
    output = execute("game-smoke", ["--quit-after", "600", "--fixed-fps", "60"])
    assert "ERROR:" not in output, output
    (run / "summary.json").write_text(json.dumps({"stages": stages, "result": "passed"}, indent=2))
    print(f"PASS: save/quit suite. Logs: {run}", flush=True)


if __name__ == "__main__":
    main()
