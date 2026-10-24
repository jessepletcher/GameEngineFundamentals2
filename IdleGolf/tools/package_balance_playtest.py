"""Package a fresh, isolated normal-progression launcher beside a Windows build."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
from godot_checks import check_process, isolated_environment

LAUNCHER = r'''param([switch]$Check)
$ErrorActionPreference = "Stop"
$playtestRoot = $PSScriptRoot
$profileName = if ($Check) { ".verification-profile-" + [guid]::NewGuid().ToString("N") } else { "profile" }
$env:APPDATA = Join-Path $playtestRoot "$profileName\appdata"
$env:LOCALAPPDATA = Join-Path $playtestRoot "$profileName\cache"
$env:TEMP = Join-Path $playtestRoot "$profileName\temp"
$env:TMP = $env:TEMP
foreach ($folder in @($env:APPDATA, $env:LOCALAPPDATA, $env:TEMP)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
$exe = Join-Path $playtestRoot "IdleGolf_BalancePlaytest.exe"
if ($Check) {
    # Release templates ignore --script. Supply an external scene temporarily.
    $scriptPath = (Join-Path $playtestRoot "verify.gd").Replace('\', '/')
    $scenePath = (Join-Path $playtestRoot "verify.tscn").Replace('\', '/')
    $scene = "[gd_scene format=3]`n[ext_resource type=`"Script`" path=`"$scriptPath`" id=`"1`"]`n[node name=`"Verify`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
    $baseConfig = "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"IdleGolfBalancePlaytest`"`n"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $overridePath = Join-Path $playtestRoot "override.cfg"
    [System.IO.File]::WriteAllText((Join-Path $playtestRoot "verify.tscn"), $scene, $utf8)
    try {
        [System.IO.File]::WriteAllText($overridePath, $baseConfig + "run/main_scene=`"$scenePath`"`n", $utf8)
        & $exe --headless --quit-after 600 --fixed-fps 60 --verbose --log-file (Join-Path $playtestRoot "verify.log") | Out-Host
    } finally {
        [System.IO.File]::WriteAllText($overridePath, $baseConfig, $utf8)
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $exe --headless --fixed-fps 60 --quit-after 600 --verbose --log-file (Join-Path $playtestRoot "normal-runtime.log") | Out-Host
    exit $LASTEXITCODE
}
Start-Process -FilePath $exe -WorkingDirectory $playtestRoot -WindowStyle Normal
'''

PROBE = '''extends Node
func _ready() -> void:
	verify.call_deferred()
func verify() -> void:
	var state = get_tree().root.get_node("GameState")
	var path := ProjectSettings.globalize_path(state.SAVE_PATH)
	if not path.contains(".verification-profile") or state.IS_DEMO_BUILD or state.money != 0:
		printerr("FAIL: isolated fresh full-game profile")
		get_tree().quit(1)
		return
	if state.get_cost_for_level("multi_ball", 0) != 100 or state.get_cost_for_level("ball_speed", 534) > 1e11:
		printerr("FAIL: balanced price schedule missing")
		get_tree().quit(1)
		return
	state.money = 17
	if not state.save() or not state.load_game() or state.money != 17:
		printerr("FAIL: isolated save round trip")
		get_tree().quit(1)
		return
	print("BALANCE_LAUNCHER checks=3 failures=0")
	get_tree().quit()
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--builds", type=Path, required=True)
    builds = p.parse_args().builds.resolve()
    folder = builds / "balance-playtest"
    folder.mkdir(exist_ok=True)
    source = builds / "full/IdleGolf.exe"
    exe = folder / "IdleGolf_BalancePlaytest.exe"
    shutil.copy2(source, exe)
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(exe.read_bytes()).digest()
    (folder / "override.cfg").write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="IdleGolfBalancePlaytest"\n')
    (folder / "Launch Balance Playtest.ps1").write_text(LAUNCHER)
    (folder / "Play Balance Test.cmd").write_text('@echo off\nstart "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch Balance Playtest.ps1"\n')
    (folder / "verify.gd").write_text(PROBE)
    (folder / "READ ME.txt").write_text(
        "IDLE GOLF - FRESH ECONOMY PLAYTEST\n\n"
        "Double-click Play Balance Test.cmd. Keep this folder together.\n"
        "This runs the normal full game from fresh, separate progress.\n"
        "There are no extra stats, free currency, automatic purchases or damaged targets.\n"
        "Close and reopen with the same launcher to continue this playtest.\n"
        "Your usual demo/full-game saves and the completion tester are separate.\n\n"
        "Goal: destroy the Mountain, Pyramids and Cargo Ship.\n"
        "The reference economy model estimates roughly 20 hours per course.\n"
        "That estimate assumes regular purchases, aiming at rewarding targets,\n"
        "and retirement to earn permanent upgrades. Actual playtime will vary.\n"
        "No earnings accrue while closed.\n\n"
        "Useful feedback: active playtime to first retirement, equipment/course unlocks,\n"
        "each completed course, and any long stretch with no worthwhile purchase.\n"
        "Reset Game clears only this launcher's test progress.\n"
        "Test saves: profile/appdata/IdleGolfBalancePlaytest/.\n")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        str(folder / "Launch Balance Playtest.ps1"), "-Check"], cwd=folder,
        env=isolated_environment(folder / ".launcher-validation"), capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    (folder / "verification-output.txt").write_text(output, encoding="utf-8")
    check_process(result.returncode, output, folder / "verify.log")
    check_process(result.returncode, output, folder / "normal-runtime.log")
    assert "BALANCE_LAUNCHER checks=3 failures=0" in output
    assert not (folder / "profile").exists()
    print(f"PASS: fresh balance launcher and normal runtime. {folder / 'Play Balance Test.cmd'}", flush=True)


if __name__ == "__main__":
    main()
