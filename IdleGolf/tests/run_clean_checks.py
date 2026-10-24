"""First-import and runtime checks for untouched production sources, both editions."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import isolated_environment, run_checked

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
run = repo / ".test-output/clean-checks" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
stages = []
# Keep the editor-only StringName exception independently reproducible without
# game scripts, assets, autoloads or an existing editor cache.
baseline = run / "engine-baseline"
baseline_project = baseline / "project"
baseline_project.mkdir(parents=True)
(baseline_project / "project.godot").write_text(
    'config_version=5\n[application]\nconfig/name="DiagnosticBaseline"\n', encoding="utf-8")
run_checked([str(args.godot.resolve()), "--headless", "--path", str(baseline_project), "--import"],
            baseline, "empty-editor", env=isolated_environment(baseline, "DiagnosticBaseline"), editor=True)
stages.append("empty-editor-baseline")
print("PASS: empty-editor-baseline", flush=True)
for edition in ["demo", "full"]:
    root = run / edition
    project = root / "project"
    shutil.copytree(repo / "idle-golf", project, ignore=shutil.ignore_patterns(".godot", "builds", ".git", "*.tmp"))
    settings = project / "project.godot"
    source = settings.read_text(encoding="utf-8")
    assert source.count('edition="demo"') == 1
    settings.write_text(source.replace('edition="demo"', f'edition="{edition}"'), encoding="utf-8")
    assert not (project / ".godot").exists()
    env = isolated_environment(root)
    base = [str(args.godot.resolve()), "--headless", "--path", str(project)]
    for label, options in [("first-import", ["--import"]),
                           ("repeat-import", ["--import"]),
                           ("runtime", ["--quit-after", "600", "--fixed-fps", "60"])]:
        run_checked(base + options, root, label, env=env, editor=label.endswith("import"))
        stages.append(edition + "-" + label)
        print("PASS: " + stages[-1], flush=True)
(run / "summary.json").write_text(json.dumps({"result": "passed", "stages": stages}, indent=2))
print(f"PASS: clean production copies. Logs: {run}", flush=True)
