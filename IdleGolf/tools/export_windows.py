"""Export both Windows editions from a clean source snapshot with Godot 4.6."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

from godot_checks import run_checked, isolated_environment


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--templates", type=Path, default=Path(os.environ["APPDATA"]) / "Godot/export_templates/4.6.stable")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    tag = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]
    staging = repo / ".test-output/windows-export" / tag
    project = staging / "project"
    output = repo / "idle-golf/builds/windows" / tag
    output.mkdir(parents=True)
    template = args.templates.resolve() / "windows_release_x86_64.exe"
    assert template.is_file(), f"Missing Godot 4.6 Windows template: {template}"
    shutil.copytree(repo / "idle-golf", project,
                    ignore=shutil.ignore_patterns(".godot", "builds", ".git", "*.tmp"))
    sources = {p.relative_to(project).as_posix(): digest(p)
               for p in sorted(project.rglob("*")) if p.is_file()}
    # Resolve templates explicitly so the editor can use an isolated profile.
    presets = project / "export_presets.cfg"
    presets.write_text(presets.read_text(encoding="utf-8").replace(
        'custom_template/release=""', f'custom_template/release="{template.as_posix()}"'), encoding="utf-8")
    env = isolated_environment(staging)
    version = subprocess.check_output([str(args.godot), "--version"], env=env, text=True).strip()
    assert version.startswith("4.6.stable."), f"Expected Godot 4.6 stable, got {version}"

    def validate(label: str, command: list[str]) -> None:
        # Stream progress and retain evidence. A failed check prevents a success
        # manifest from being published, even if an executable already exists.
        with (staging / f"{label}.txt").open("w", encoding="utf-8") as capture:
            with subprocess.Popen(command, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, encoding="utf-8", errors="replace") as process:
                for line in process.stdout:
                    capture.write(line)
                    capture.flush()
                    print(line, end="", flush=True)
                if process.wait() != 0:
                    raise RuntimeError(f"{label} failed; see {staging / (label + '.txt')}")

    def verify_sources_unchanged() -> None:
        current = {p.relative_to(repo / "idle-golf").as_posix(): digest(p)
                   for p in (repo / "idle-golf").rglob("*")
                   if p.is_file() and not any(part in {".godot", "builds", ".git"}
                                              for part in p.relative_to(repo / "idle-golf").parts)
                   and not p.name.endswith(".tmp")}
        if current != sources:
            raise RuntimeError("Game sources changed during validation; rerun the export for a consistent snapshot")

    validate("source-checks", [sys.executable, str(repo / "tools/check_release.py"), "--godot", str(args.godot.resolve())])
    verify_sources_unchanged()

    def run(label: str, options: list[str]) -> None:
        run_checked([str(args.godot.resolve()), "--headless", "--path", str(project)] + options,
                    staging, label, env=env, timeout=240, editor=True)
        print(f"PASS: {label}", flush=True)

    run("import", ["--import"])
    for edition, filename in [("demo", "IdleGolf_Demo.exe"), ("full", "IdleGolf.exe")]:
        destination = output / edition / filename
        destination.parent.mkdir()
        run(edition, ["--export-release", "Windows " + edition.title(), str(destination)])
        assert destination.is_file()
    validate("runtime-checks", [sys.executable, str(repo / "tests/run_export_tests.py"), "--builds", str(output)])
    validate("completion-playtest", [sys.executable, str(repo / "tools/package_completion_test.py"), "--builds", str(output)])
    validate("balance-playtest", [sys.executable, str(repo / "tools/package_balance_playtest.py"), "--builds", str(output)])
    validate("golfer-playtest", [sys.executable, str(repo / "tools/package_golfer_test.py"), "--builds", str(output)])
    validate("sandbox-playtest", [sys.executable, str(repo / "tools/package_sandbox_test.py"), "--builds", str(output)])
    verify_sources_unchanged()
    manifest = {"engine": version, "engine_sha256": digest(args.godot),
                "template_sha256": digest(template), "source_sha256": sources,
                "artifacts": {p.relative_to(output).as_posix(): digest(p)
                              for p in sorted(output.rglob("*")) if p.is_file()},
                "logs": str(staging), "validation": {"source": "passed", "exported_runtime": "passed", "completion_playtest": "passed", "balance_playtest": "passed", "golfer_playtest": "passed", "sandbox_playtest": "passed"},
                "status": "Automated checks passed; manual platform/Steam QA still required"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"BUILDS: {output}", flush=True)


if __name__ == "__main__":
    main()
