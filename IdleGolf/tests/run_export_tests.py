"""Test the actual Windows release executables using isolated APPDATA profiles."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import time
import uuid
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import check_output, run_checked, SAVE_WRITE_WARNING, SAVE_RECOVERY_WARNING, DEMO_IMPORT_WARNING


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds", type=Path, required=True, help="Timestamped folder containing demo/ and full/")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    run = repo / ".test-output/export-tests" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    run.mkdir(parents=True)
    stages = []
    builds = args.builds.resolve()
    exes = {"demo": builds / "demo/IdleGolf_Demo.exe", "full": builds / "full/IdleGolf.exe"}
    originals = dict(exes)
    # Release templates ignore --script. Use an external scene override beside
    # byte-identical executable copies; no test resources enter the release PCK.
    for edition, original in originals.items():
        folder = run / edition
        folder.mkdir()
        exes[edition] = folder / original.name
        shutil.copy2(original, exes[edition])
        assert hashlib.sha256(original.read_bytes()).digest() == hashlib.sha256(exes[edition].read_bytes()).digest()

    def driver(edition: str, script: str | None) -> None:
        folder = exes[edition].parent
        override = folder / "override.cfg"
        if script is None:
            override.unlink(missing_ok=True)
            return
        source = (repo / "tests" / script).read_text(encoding="utf-8")
        source = source.replace("extends SceneTree", "extends Node").replace("func _initialize()", "func _ready()")
        source = source.replace("root.", "get_tree().root.").replace("await create_timer(", "await get_tree().create_timer(")
        source = source.replace("\tquit(", "\tget_tree().quit(")
        (folder / "driver.gd").write_text(source, encoding="utf-8")
        scene = folder / "driver.tscn"
        scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="' +
            (folder / "driver.gd").as_posix() + '" id="1"]\n[node name="Driver" type="Node"]\nscript = ExtResource("1")\n')
        override.write_text('[application]\nrun/main_scene="' + scene.as_posix() + '"\n')

    def environment(profile: str) -> dict:
        env = dict(os.environ, APPDATA=str(run / profile), LOCALAPPDATA=str(run / (profile + "-cache")),
                   TEMP=str(run / "temp"), TMP=str(run / "temp"))
        for key in ["APPDATA", "LOCALAPPDATA", "TEMP"]:
            Path(env[key]).mkdir(exist_ok=True)
        return env

    def execute(label: str, edition: str, script: str | None, params: list[str], profile: str = "shared", extra: list[str] | None = None) -> str:
        command = [str(exes[edition]), "--headless"]
        driver(edition, script)
        command += extra or []
        if params:
            command += ["--"] + params
        expected = ()
        if label == "import-full":
            # load_game reports migration, save clears the notice, then the
            # successful import restores it for the player (two log emissions).
            expected = (DEMO_IMPORT_WARNING, DEMO_IMPORT_WARNING)
        elif label.endswith(("-failed_close", "-discard")):
            expected = (SAVE_WRITE_WARNING,)
        elif label.endswith(("-backup-recovery", "-recovery-commit")):
            expected = (SAVE_RECOVERY_WARNING,)
        output = run_checked(command, run, label, env=environment(profile), timeout=25, expected=expected)
        stages.append(label)
        print("PASS: " + label, flush=True)
        return output

    def probe(label: str, edition: str, mode: str, value: str = "0", profile: str = "shared") -> None:
        output = execute(label, edition, "export_probe.gd", [mode, edition, value], profile)
        assert "result=PASS" in output, output

    saves = run / "shared/Godot/app_userdata/IdleGolf"
    saves.mkdir(parents=True)
    demo = saves / "idle_golf_demo_v0_1.cfg"
    full = saves / "idle_golf_full.cfg"
    legacy = (repo / "tests/fixtures/legacy_save.cfg").read_bytes()
    demo.write_bytes(legacy)
    probe("legacy-demo", "demo", "inspect", "1234.5")
    probe("import-full", "full", "inspect", "1234.5")
    assert full.is_file() and demo.read_bytes() == legacy
    probe("paid-progress", "full", "paid")
    execute("demo-close", "demo", "quit_probe.gd", ["close"])
    execute("demo-exit", "demo", "quit_probe.gd", ["exit"])
    probe("full-after-demo", "full", "verify_paid")
    probe("full-reset", "full", "reset")
    probe("full-reset-does-not-reimport", "full", "inspect", "0")
    probe("fresh-full-first", "full", "inspect", "0", "full-first")
    probe("full-first-paid", "full", "paid", profile="full-first")
    probe("demo-after-full", "demo", "inspect", "0", "full-first")
    probe("full-first-preserved", "full", "verify_paid", profile="full-first")
    for edition in exes:
        save = demo if edition == "demo" else full
        for mode, value in [("close", "147.25"), ("exit", "258.5"), ("failed_close", "369.75"), ("discard", "369.75")]:
            execute(edition + "-" + mode, edition, "quit_probe.gd", [mode])
            assert f"money={value}" in save.read_text()
            if mode == "discard":
                save.with_suffix(".cfg.tmp").rmdir()
        crash = run / (edition + "-crash.txt")
        driver(edition, "quit_probe.gd")
        with crash.open("w") as capture:
            process = subprocess.Popen([str(exes[edition]), "--headless", "--verbose", "--log-file", str(run / (edition + "-crash.log")),
                "--", "crash"], env=environment("shared"), stdout=capture, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while "READY_FOR_FORCED_STOP" not in crash.read_text():
                    assert process.poll() is None and time.monotonic() < deadline, crash.read_text()
                    time.sleep(0.05)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=10)
        check_output(crash.read_text())
        check_output((run / (edition + "-crash.log")).read_text())
        execute(edition + "-verify-crash", edition, "quit_probe.gd", ["verify_crash"])
        # Parseable corruption must recover the known-good previous commit.
        backup = save.with_suffix(".cfg.bak").read_bytes()
        save.write_text("[broken]\n")
        probe(edition + "-backup-recovery", edition, "inspect", "369.75")
        assert save.with_suffix(".cfg.bak").read_bytes() == backup
        probe(edition + "-recovery-commit", edition, "commit_recovery", "369.75")
        execute(edition + "-main-scene", edition, None, [], extra=["--quit-after", "600", "--fixed-fps", "60"])
    (run / "summary.json").write_text(json.dumps({"result": "passed", "builds": str(builds), "stages": stages}, indent=2))
    print(f"PASS: exported Windows suite. Logs: {run}", flush=True)


if __name__ == "__main__":
    main()
