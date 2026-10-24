"""Package and verify an isolated all-golfer review using the exported full game."""
import argparse
from pathlib import Path
import shutil
import subprocess
from godot_checks import check_process, isolated_environment
from package_completion_test import LAUNCHER as COMPLETION_LAUNCHER


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds", type=Path, required=True)
    builds = parser.parse_args().builds.resolve()
    repo = Path(__file__).resolve().parents[1]
    folder = builds / "golfer-test"
    folder.mkdir(exist_ok=True)
    shutil.copy2(builds / "full/IdleGolf.exe", folder / "IdleGolf_GolferTest.exe")
    shutil.copy2(repo / "tests/golfer_playtest.gd", folder / "golfer_playtest.gd")
    launcher = COMPLETION_LAUNCHER.replace("COMPLETION", "GOLFER").replace("Completion", "Golfer").replace("completion", "golfer")
    (folder / "Launch Golfer Test.ps1").write_text(launcher, encoding="utf-8")
    (folder / "Test Golfers.cmd").write_text('@echo off\nstart "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch Golfer Test.ps1"\n')
    (folder / "READ ME.txt").write_text(
        "IDLE GOLF - GOLFER REVIEW\n\nDouble-click Test Golfers.cmd. Keep this folder together.\n"
        "All eight golfers are owned and level 30 is supplied in a separate test profile.\n"
        "Pick a golfer and click Swing, or enable Auto swings. Fast swings gives 60 fire-rate upgrades.\n"
        "Swap during windup: that swing cancels; the next swing uses your selection.\n"
        "Swap while a ball is airborne: the ball keeps its launch stats.\n"
        "Open Shop > Golfers to inspect every portrait and description.\n"
        "Close and reopen to test saving; normal saves and other test profiles are separate.\n"
        "This is a visual/mechanics test, not a normal progression balance run.\n"
        "Test saves: profile/appdata/IdleGolfGolferPlaytest/.\n")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        str(folder / "Launch Golfer Test.ps1"), "-Check", "review"], cwd=folder,
        env=isolated_environment(folder / ".launcher-validation"), capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    (folder / "verification-output.txt").write_text(output, encoding="utf-8")
    check_process(result.returncode, output, folder / "review.log")
    assert "GOLFER_LAUNCHER checks=10 failures=0" in output
    assert not (folder / "profile").exists()
    print(f"PASS: all eight exported golfers and isolated saving. {folder / 'Test Golfers.cmd'}", flush=True)


if __name__ == "__main__":
    main()
