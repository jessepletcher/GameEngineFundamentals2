"""Capture the actual game economy/geometry using a fresh isolated Godot copy."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import time
import uuid
from godot_checks import isolated_environment, run_checked


def capture(godot):
    repo = Path(__file__).resolve().parents[1]
    run = repo / ".test-output/economy" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    project = run / "project"
    shutil.copytree(repo / "idle-golf", project, ignore=shutil.ignore_patterns(".godot", "builds", ".git"))
    shutil.copy2(repo / "tests/economy_snapshot.gd", project / "economy_snapshot.gd")
    settings = project / "project.godot"
    settings.write_text(settings.read_text().replace('edition="demo"', 'edition="full"'))
    env = isolated_environment(run)
    run_checked([str(godot), "--headless", "--path", str(project), "--import"], run, "import", env=env, editor=True)
    run_checked([str(godot), "--headless", "--path", str(project), "--script", "res://economy_snapshot.gd"], run, "snapshot", env=env)
    snapshot = run / "economy-snapshot.json"
    shutil.copy2(project / snapshot.name, snapshot)
    sources = {p.relative_to(project).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in project.rglob("*") if p.is_file() and p.suffix in {".gd", ".tscn", ".godot"}
               and ".godot" not in p.relative_to(project).parts}
    (run / "source-hashes.json").write_text(json.dumps(sources, indent=2))
    print(snapshot, flush=True)
    return snapshot


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    capture(parser.parse_args().godot.resolve())
