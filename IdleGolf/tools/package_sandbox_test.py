"""Add an isolated unrestricted full-game tester to a validated Windows build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid
from godot_checks import check_process, isolated_environment
from package_completion_test import LAUNCHER as COMPLETION_LAUNCHER


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds", type=Path, required=True)
    builds = parser.parse_args().builds.resolve()
    repo = Path(__file__).resolve().parents[1]
    source = builds / "full/IdleGolf.exe"
    base_manifest = builds / "manifest.json"
    if base_manifest.exists():
        assert digest(source) == json.loads(base_manifest.read_text())["artifacts"]["full/IdleGolf.exe"]
    folder = builds / "sandbox-test"
    folder.mkdir(exist_ok=True)
    exe = folder / "IdleGolf_SandboxTest.exe"
    shutil.copy2(source, exe)
    shutil.copy2(repo / "tests/sandbox_playtest.gd", folder / "sandbox_playtest.gd")
    launcher = COMPLETION_LAUNCHER.replace("COMPLETION", "SANDBOX").replace("Completion", "Sandbox").replace("completion", "sandbox")
    launcher = launcher.replace('".verification-profile"', '".verification-profile-' + uuid.uuid4().hex[:10] + '"')
    launcher = launcher.replace('"$Check.log")', '"$Check.log") | Out-Host')
    (folder / "Launch Sandbox Test.ps1").write_text(launcher, encoding="utf-8")
    (folder / "Test Full Game.cmd").write_text('@echo off\nstart "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch Sandbox Test.ps1"\n')
    (folder / "READ ME.txt").write_text(
        "IDLE GOLF - UNRESTRICTED FULL GAME TEST\n\n"
        "Double-click Test Full Game.cmd. Keep this folder together.\n"
        "Every ball, golfer and course is already owned. Player level starts at 30.\n"
        "Money starts at 1 quadrillion; medals start at 1 million. Keep topped up\n"
        "replenishes spent currency automatically. Turn it off to test spending.\n\n"
        "Use the panel to select equipment/courses, choose Starter/Midgame/Endgame\n"
        "stats, or set a specific upgrade level. Authored upgrade caps still apply.\n"
        "Endgame stats supply enough range to reach distant targets; aim/loft still matter.\n"
        "Auto swings can be paused; Swing releases a real shot through its animation.\n"
        "One-hit targets makes every destructible break with one real hit, including\n"
        "the Mountain, Pyramids and Cargo Ship. It does not grant completion directly.\n"
        "Show / hide controls collapses the panel. It hides while Shop/Settings are open.\n\n"
        "Save test progress, or quit normally. Equipment, upgrades, level and earned\n"
        "completion persist. All content is unlocked and funds refill on each launch.\n"
        "One-hit mode resets to OFF on launch; Auto swings/Keep topped up start ON.\n"
        "Use Settings > Reset Game to clear this test profile; relaunch for new unlocks.\n"
        "Test saves: profile/appdata/IdleGolfSandboxPlaytest/.\n"
        "Normal full/demo saves and other test profiles are separate.\n"
        "This tester skips progression; use the balance playtest to measure pacing.\n")
    results = []
    for mode in ["review", "reload"]:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            str(folder / "Launch Sandbox Test.ps1"), "-Check", mode], cwd=folder,
            env=isolated_environment(folder / ".launcher-validation"), capture_output=True, text=True, timeout=90)
        output = result.stdout + result.stderr
        (folder / f"{mode}-output.txt").write_text(output, encoding="utf-8")
        check_process(result.returncode, output, folder / f"{mode}.log")
        summary = next(line for line in output.splitlines() if line.startswith("SANDBOX_TESTS"))
        assert "failures=0" in summary
        results.append(summary)
        print(summary, flush=True)
    assert digest(source) == digest(exe)
    assert not (folder / "profile").exists(), "Verification must not touch the user's interactive profile"
    manifest = {"base_build": str(builds), "full_exe_sha256": digest(source), "validation": results,
        "artifacts": {p.name: digest(p) for p in folder.iterdir() if p.is_file() and p.name != "sandbox-manifest.json"}}
    (folder / "sandbox-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    # Keep the convenient repository launcher pointing at the latest tester.
    if folder.is_relative_to(repo):
        relative = str((folder / "Test Full Game.cmd").relative_to(repo)).replace("/", "\\")
        (repo / "Test Full Game.cmd").write_text('@echo off\ncall "%~dp0' + relative + '"\n')
    print(f"PASS: full-game sandbox. {folder / 'Test Full Game.cmd'}", flush=True)


if __name__ == "__main__":
    main()
