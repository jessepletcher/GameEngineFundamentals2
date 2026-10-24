"""Package and verify an isolated, playable completion test beside a Windows build."""
from pathlib import Path
import argparse
import hashlib
import shutil
import subprocess

from godot_checks import isolated_environment

LAUNCHER = r'''param([string]$Check = "")
$ErrorActionPreference = "Stop"
$testRoot = $PSScriptRoot
$profileName = if ($Check) { ".verification-profile" } else { "profile" }
$env:APPDATA = Join-Path $testRoot "$profileName\appdata"
$env:LOCALAPPDATA = Join-Path $testRoot "$profileName\cache"
$env:TEMP = Join-Path $testRoot "$profileName\temp"
$env:TMP = $env:TEMP
$env:IDLE_GOLF_COMPLETION_TEST = "1"
$env:IDLE_GOLF_COMPLETION_CHECK = $Check
foreach ($folder in @($env:APPDATA, $env:LOCALAPPDATA, $env:TEMP)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
# Absolute scene/script paths are regenerated so this folder can be moved.
$driverPath = (Join-Path $testRoot "completion_playtest.gd").Replace('\', '/')
$scenePath = (Join-Path $testRoot "driver.tscn").Replace('\', '/')
$scene = "[gd_scene load_steps=2 format=3]`n[ext_resource type=`"Script`" path=`"$driverPath`" id=`"1`"]`n[node name=`"CompletionPlaytest`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
$override = "[application]`nrun/main_scene=`"$scenePath`"`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"IdleGolfCompletionPlaytest`"`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $testRoot "driver.tscn"), $scene, $utf8)
[System.IO.File]::WriteAllText((Join-Path $testRoot "override.cfg"), $override, $utf8)
$exe = Join-Path $testRoot "IdleGolf_CompletionTest.exe"
if ($Check) {
    & $exe --headless --fixed-fps 60 --max-fps 1000 --verbose --log-file (Join-Path $testRoot "$Check.log")
    exit $LASTEXITCODE
}
# The helper stays hidden; the game itself is the interactive test window.
Start-Process -FilePath $exe -WorkingDirectory $testRoot -WindowStyle Normal
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builds", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    folder = args.builds.resolve() / "completion-test"
    folder.mkdir(exist_ok=True)
    source = args.builds.resolve() / "full/IdleGolf.exe"
    exe = folder / "IdleGolf_CompletionTest.exe"
    shutil.copy2(source, exe)
    assert hashlib.sha256(exe.read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest()
    shutil.copy2(repo / "tests/completion_playtest.gd", folder / "completion_playtest.gd")
    (folder / "Launch Completion Test.ps1").write_text(LAUNCHER, encoding="utf-8")
    (folder / "Test Completion.cmd").write_text(
        '@echo off\nstart "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch Completion Test.ps1"\n',
        encoding="utf-8")
    (folder / "READ ME.txt").write_text(
        "IDLE GOLF - COMPLETION PLAYTEST\n\n"
        "Double-click Test Completion.cmd. Keep this folder's files together.\n"
        "This is the same full-game executable with external test controls.\n"
        "Your normal demo and full-game saves are not used or changed.\n\n"
        "1. Choose Big Piney, Desert, or Beach in the blue test panel.\n"
        "2. Click Set up final shot, then Shoot. Allow 15-25 seconds for the hit.\n"
        "3. Check the course-beaten message and the progress button at the top.\n"
        "4. Close and reopen this launcher to check saved completion.\n"
        "5. Beat all three to see Game complete. You can keep playing.\n"
        "6. Reset test progress clears this test profile only.\n\n"
        "Setup unlocks courses, supplies upgraded shot stats and leaves the final\n"
        "target one hit from destruction. It does not grant completion directly.\n"
        "The Shoot button uses the real launcher, physics and saving code.\n"
        "Partial target damage itself is not saved; set up again after restarting.\n"
        "Completion survives retirement. Reset Game clears completion.\n\n"
        "Test saves: profile/appdata/IdleGolfCompletionPlaytest/ in this folder.\n"
        "For normal progression, run ../full/IdleGolf.exe instead.\n", encoding="utf-8")
    # Prepare portable launcher paths, then exercise the actual exported driver
    # in four separate processes. These verification saves are not the user's
    # interactive test profile, which stays fresh for their first launch.
    env = isolated_environment(folder / ".launcher-validation")
    for mode in ["complete", "reload", "reset", "verify-reset"]:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
                                 "-File", str(folder / "Launch Completion Test.ps1"), "-Check", mode],
                                env=env, cwd=folder, capture_output=True, text=True, timeout=90)
        from godot_checks import check_process
        output = result.stdout + result.stderr
        (folder / f"{mode}-output.txt").write_text(output, encoding="utf-8")
        check_process(result.returncode, output, folder / f"{mode}.log")
        assert "COMPLETION_PLAYTEST" in output and "failures=0" in output, output
        print(f"PASS: completion playtest {mode}", flush=True)
    print(f"COMPLETION TEST: {folder / 'Test Completion.cmd'}", flush=True)


if __name__ == "__main__":
    main()
