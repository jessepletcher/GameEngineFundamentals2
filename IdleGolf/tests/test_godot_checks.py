"""Failure-injection tests for the release diagnostic gate (no engine required)."""
import os
from contextlib import contextmanager
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.godot_checks import check_output, check_process, run_checked

HEADER = "Godot Engine v4.6.stable.official.89cea1439 - https://godotengine.org\n"
EDITOR_NODE = "Orphan StringName: Node (static: 7, total: 8)\nStringName: 1 unclaimed string names at exit.\n"
BAD_SAVE = "ERROR: ConfigFile parse error at res://test-data/case-3/save.cfg:0: Unexpected EOF while parsing simple tag."


@contextmanager
def fixture_directory():
    parent = Path(__file__).resolve().parents[1] / ".test-output/diagnostic-tests"
    parent.mkdir(parents=True, exist_ok=True)
    # Preserve failure-injection logs with the other validation evidence.
    yield tempfile.mkdtemp(dir=parent)


class DiagnosticTests(unittest.TestCase):
    def test_diagnostics_fail_even_with_exit_zero(self):
        for diagnostic in ["ERROR: missing file", "SCRIPT ERROR: Parse Error: bad type",
                           "WARNING: invalid UID", "FAIL: wrong balance",
                           "WARNING: ObjectDB instances leaked at exit",
                           "Orphan StringName: timeout (static: 0, total: 1)",
                           "StringName: 2 unclaimed string names at exit.",
                           "Failed to bind socket. Error: 3.", "Failed to load script x",
                           "ERROR: 2 RID allocations leaked", "CrashHandler: program crashed",
                           "\x1b[33mWARNING: colored diagnostic\x1b[0m"]:
            with self.subTest(diagnostic=diagnostic), self.assertRaises(RuntimeError):
                check_output(diagnostic)

    def test_normal_verbose_class_names_are_not_errors(self):
        self.assertEqual(check_output("Class 'DependencyErrorDialog' is not exposed, skipping.\n"
                                      "Class 'OrphanResourcesDialog' is not exposed, skipping.\n"
                                      "SAVE_TESTS checks=166 failures=0"), [])

    def test_editor_exception_is_bounded_and_never_runtime(self):
        self.assertEqual(len(check_output(HEADER + EDITOR_NODE, editor=True)), 2)
        for output, editor in [(HEADER + EDITOR_NODE, False),
                               (EDITOR_NODE, True),
                               (HEADER.replace("4.6.stable", "4.7.stable") + EDITOR_NODE, True),
                               (HEADER + EDITOR_NODE.replace("total: 8", "total: 9"), True),
                               (HEADER + EDITOR_NODE.replace("Node (", "timeout ("), True),
                               (HEADER + EDITOR_NODE * 2, True),
                               (HEADER + EDITOR_NODE + "WARNING: ObjectDB instances leaked", True)]:
            with self.subTest(output=output, editor=editor), self.assertRaises(RuntimeError):
                check_output(output, editor=editor)

    def test_corruption_fixture_exception_is_narrow(self):
        self.assertEqual(check_output(BAD_SAVE, malformed_save=True), [BAD_SAVE])
        for output, allow in [(BAD_SAVE, False), (BAD_SAVE.replace("case-3", "player"), True),
                              (BAD_SAVE.replace("Unexpected EOF", "Other error"), True),
                              (BAD_SAVE + "\nSCRIPT ERROR: recovery failed", True)]:
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                check_output(output, malformed_save=allow)
        with self.assertRaises(RuntimeError):
            check_output((BAD_SAVE + "\n") * 11, malformed_save=True)

    def test_expected_warning_budget_does_not_hide_duplicates(self):
        warning = "WARNING: intentional fixture failure"
        self.assertEqual(check_output(warning, expected=(warning,)), [warning])
        with self.assertRaises(RuntimeError):
            check_output(warning + "\n" + warning, expected=(warning,))

    def test_exit_status_and_log_are_both_required(self):
        with fixture_directory() as folder:
            log = Path(folder) / "engine.log"
            with self.assertRaises(RuntimeError):
                check_process(0, "", log)
            log.write_text(HEADER)
            with self.assertRaises(RuntimeError):
                check_process(1, "", log)
            log.write_text("WARNING: only in engine log")
            with self.assertRaises(RuntimeError):
                check_process(0, "", log)

    def test_real_child_output_stderr_log_and_arguments(self):
        with fixture_directory() as folder:
            root = Path(folder)
            child = root / "child.py"
            child.write_text('''import sys
from pathlib import Path
args = sys.argv[1:]
split = args.index("--")
assert args[split+1:] == ["mode"]
assert "--verbose" in args[:split]
log = Path(args[args.index("--log-file") + 1])
log.write_text("Godot Engine fake\\n")
print("WARNING: stderr-only failure", file=sys.stderr)
''')
            with self.assertRaisesRegex(RuntimeError, "stderr-only"):
                run_checked([sys.executable, str(child), "--", "mode"], root, "stderr", env=dict(os.environ))
            self.assertIn("stderr-only", (root / "stderr-output.txt").read_text())
            child.write_text(child.read_text().replace('print("WARNING: stderr-only failure", file=sys.stderr)',
                                                       'log.write_text("ERROR: log-only failure")'))
            with self.assertRaisesRegex(RuntimeError, "log-only"):
                run_checked([sys.executable, str(child), "--", "mode"], root, "log", env=dict(os.environ))

    def test_timeout_preserves_diagnostics(self):
        with fixture_directory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                run_checked([sys.executable, "-u", "-c", "import time; print('checkpoint'); time.sleep(20)"],
                            root, "timeout", env=dict(os.environ), timeout=1)
            self.assertIn("checkpoint", (root / "timeout-output.txt").read_text())

    def test_self_contained_editor_cannot_bypass_profile_isolation(self):
        with fixture_directory() as folder:
            root = Path(folder)
            (root / "_sc_").touch()
            with self.assertRaisesRegex(RuntimeError, "bypasses the isolated"):
                run_checked([str(root / "Godot.exe"), "--import"], root, "import",
                            env=dict(os.environ), editor=True)

    def test_optimized_python_cannot_skip_checks(self):
        result = subprocess.run([sys.executable, "-O", "-c", "import tools.godot_checks"],
                                cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without -O", result.stderr)


if __name__ == "__main__":
    unittest.main()
