"""Launch the exact exported game for native UI QA with disposable save data."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--builds", type=Path, required=True)
parser.add_argument("--edition", choices=["demo", "full"], default="full")
parser.add_argument("--profile", default="native-ui")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = (repo / ".test-output/export-ui").resolve()
profile = (root / args.profile).resolve()
assert profile.is_relative_to(root) and profile != root
saves = profile / "roaming/Godot/app_userdata/IdleGolf"
if not profile.exists():
    saves.mkdir(parents=True)
    (saves / "idle_golf_demo_v0_1.cfg").write_text(
        '[player]\nmoney=1234.5\nxp=42.0\nlevel=1\nxp_to_next_level=100.0\n'
        '[settings]\nwindow_mode="windowed"\nwindow_size="1280x720"\nsfx_muted=true\nmusic_muted=true\n'
        '[ui]\nhas_clicked_help_button=true\n')
for folder in ["cache", "temp"]:
    (profile / folder).mkdir(exist_ok=True)
env = dict(os.environ, APPDATA=str(profile / "roaming"), LOCALAPPDATA=str(profile / "cache"),
           TEMP=str(profile / "temp"), TMP=str(profile / "temp"))
exe = args.builds.resolve() / ("full/IdleGolf.exe" if args.edition == "full" else "demo/IdleGolf_Demo.exe")
tag = args.edition + "-" + time.strftime("%H%M%S")
log = profile / (tag + "-ui.log")
with (profile / (tag + "-output.txt")).open("w") as capture:
    process = subprocess.Popen([str(exe), "--verbose", "--log-file", str(log)], env=env,
                               stdout=capture, stderr=subprocess.STDOUT)
(profile / "process.json").write_text(json.dumps({"pid": process.pid, "edition": args.edition, "exe": str(exe), "save_folder": str(saves)}, indent=2))
print(f"Launched PID {process.pid}; isolated saves: {saves}", flush=True)
raise SystemExit(process.wait())
