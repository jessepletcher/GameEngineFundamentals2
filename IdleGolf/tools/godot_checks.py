"""Shared, fail-closed Godot process/log checks for local release validation."""
from __future__ import annotations

import os
from collections import Counter
from pathlib import Path
import re
import socket
import subprocess

# Existing runners also use assertions for fixture/content checks. Never allow
# Python optimization to silently disable them.
if not __debug__:
    raise RuntimeError("Release checks require Python without -O / PYTHONOPTIMIZE")


def editor_ports() -> list[str]:
    # The debugger URI rejects port 0; ask the OS for a free port first. LSP/DAP
    # accept 0 directly. A bind race still fails the diagnostic gate.
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    return ["--debug-server", f"tcp://127.0.0.1:{port}", "--lsp-port", "0", "--dap-port", "0"]


ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(
    r"\b(?:ERROR|WARNING|FAIL):|\bSCRIPT ERROR\b|\bParse Error\b|\bCompile Error\b|"
    r"\bleaked\b|^Orphan |\bunclaimed string names\b|\binvalid UID\b|"
    r"^Failed to (?:load|bind)|^Cannot open |\bcrashed\b|\bCrashHandler\b", re.I)
MALFORMED_SAVE = re.compile(
    r"ERROR: ConfigFile parse error at res://test-data/case-[0-9]+/save\.cfg"
    r"(?:\.bak\.tmp|\.bak|\.tmp)?:0: Unexpected EOF while parsing simple tag\.")
SAVE_WRITE_WARNING = "WARNING: Could not write your progress. Check free disk space and folder permissions."
SAVE_BLOCKED_WARNING = ("WARNING: Your save could not be read, and no usable backup was found. Saving is disabled "
                        "so the existing files stay safe. Restore a backup and restart, or use Reset Game to start again.")
SAVE_RECOVERY_WARNING = ("WARNING: Recovered your progress from a previous or interrupted save. Some recent progress "
                         "may be missing. The original files have been kept for recovery.")
DEMO_IMPORT_WARNING = ("WARNING: Demo progress imported into the full game. Your demo save is unchanged; "
                       "the two editions now save separately.")


def isolated_environment(root: Path, application: str = "IdleGolf") -> dict[str, str]:
    env = dict(os.environ)
    for key, folder in [("APPDATA", "profile"), ("LOCALAPPDATA", "cache"),
                        ("TEMP", "temp"), ("TMP", "temp")]:
        env[key] = str(root / folder)
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    # The editor profiler can request user:// before the game has ever run.
    (Path(env["APPDATA"]) / "Godot/app_userdata" / application).mkdir(parents=True, exist_ok=True)
    return env


def check_output(output: str, *, editor: bool = False, malformed_save: bool = False,
                 expected: tuple[str, ...] = ()) -> list[str]:
    """Return documented exceptions; raise for every unexpected diagnostic.

    Godot 4.6 stable's empty editor retains exactly one non-static Node name.
    Only that pair of verbose lines is tolerated, only for editor invocations.
    Extra references, other names, ObjectDB/RID leaks and runtime names fail.
    """
    lines = [ANSI.sub("", line).strip() for line in output.splitlines()]
    diagnostics = [line for line in lines if DIAGNOSTIC.search(line)]
    accepted = []
    if editor and "Godot Engine v4.6.stable.official.89cea1439 - https://godotengine.org" in lines:
        orphans = [line for line in diagnostics if line.startswith("Orphan StringName:")]
        summaries = [line for line in diagnostics if "unclaimed string names" in line]
        if len(orphans) == 1 and summaries == ["StringName: 1 unclaimed string names at exit."]:
            match = re.fullmatch(r"Orphan StringName: Node \(static: (\d+), total: (\d+)\)", orphans[0])
            if match and int(match[2]) - int(match[1]) == 1:
                accepted += orphans + summaries
    malformed = [line for line in diagnostics if MALFORMED_SAVE.fullmatch(line)]
    if malformed_save and len(malformed) <= 10:
        accepted += malformed
    budget = Counter(expected)
    for line in diagnostics:
        if budget[line] > 0:
            accepted.append(line)
            budget[line] -= 1
    remaining = Counter(diagnostics) - Counter(accepted)
    unexpected = list(remaining.elements())
    if unexpected:
        raise RuntimeError("Unexpected Godot diagnostics:\n" + "\n".join(unexpected))
    return accepted


def check_process(returncode: int, output: str, log: Path, **policy) -> None:
    if returncode != 0:
        raise RuntimeError(f"Godot exited with {returncode}; log: {log}\n{output[-8000:]}")
    if not log.is_file():
        raise RuntimeError(f"Godot did not produce its required log: {log}")
    try:
        accepted = check_output(output, **policy)
        check_output(log.read_text(encoding="utf-8", errors="replace"), **policy)
    except RuntimeError as error:
        raise RuntimeError(f"{log}: {error}") from error
    if accepted:
        print(f"NOTE: {log.stem}: {len(accepted)} documented diagnostic lines (see full log)", flush=True)


def run_checked(command: list[str], root: Path, label: str, *, env: dict[str, str],
                timeout: int = 90, editor: bool = False, malformed_save: bool = False,
                expected: tuple[str, ...] = ()) -> str:
    if editor and any((Path(command[0]).resolve().parent / marker).exists() for marker in ["_sc_", "._sc_"]):
        raise RuntimeError("Use a non-self-contained Godot editor; self-contained mode bypasses the isolated APPDATA profile")
    log = root / f"{label}.log"
    split = command.index("--") if "--" in command else len(command)
    command = (command[:split] + ["--verbose", "--log-file", str(log)]
               + (editor_ports() if editor else []) + command[split:])
    capture = root / f"{label}-output.txt"
    try:
        result = subprocess.run(command, env=env, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as error:
        output = b"".join(part if isinstance(part, bytes) else (part or "").encode()
                          for part in [error.stdout, error.stderr]).decode("utf-8", errors="replace")
        capture.write_text(output, encoding="utf-8")
        raise RuntimeError(f"{label} timed out after {timeout}s; output: {capture}") from error
    output = result.stdout + result.stderr
    capture.write_text(output, encoding="utf-8")
    check_process(result.returncode, output, log, editor=editor, malformed_save=malformed_save, expected=expected)
    return output
