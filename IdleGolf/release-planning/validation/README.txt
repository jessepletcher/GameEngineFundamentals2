IDLE GOLF AUDIT VALIDATION EVIDENCE
October 22, 2026

These files capture assessment probes, not a regression suite or fixes.
The project source and actual player saves were not modified.

Environment: Godot 4.6.stable.official.89cea1439, Windows, headless display/audio.
A copied project omitted .godot, builds and .git. In that copy only, the
GameState.gd SAVE_PATH value was replaced from user://idle_golf_demo_v0_1.cfg to
res://audit_save.cfg. A portable copy of Godot with an _sc_ marker isolated editor
settings. The standalone probe was then added to the copied project.

NEVER run the probe against a real project/save: it intentionally writes a
malformed audit save, changes runtime state, and saves afterward. Use the isolated
copy and redirected save path described above.

Commands, with paths to the isolated project and local log output:
godot --headless --path <copy> --import --log-file <import.log>
godot --headless --path <copy> --quit-after 120 --fixed-fps 60 --log-file <smoke.log>
godot --headless --path <copy> --import --log-file <repeat-import.log>
godot --headless --path <copy> --script res://audit_probe.gd --log-file <probe.log>

Rename audit_probe.gd.txt to audit_probe.gd only inside that isolated copy.

Evidence:
- import-output.txt: initial import emitted a GameState UID error, a related
  main.gd type-inference failure, and an editor user:// profiler-directory error.
- smoke-output.txt: subsequent 120-frame headless startup; exit 0, no script errors.
- repeat-import-output.txt: UID/type errors cleared; editor profiler path issue
  remained. This environment result is not an exported-build certification.
- probe-output.txt: catalog counts and reproduced quit/save/course/fragment issues.
  The ConfigFile parse error is expected: the probe deliberately corrupts its own
  isolated audit file to test the next-load/next-save behavior.
- audit_probe.gd.txt: exact probe source, retained as text outside the Godot project.

Probe flags that are true indicate reproduced defects, not successful fixes.
The close probe propagates the notification; native OS/Steam shutdown behavior
still requires end-to-end testing. Course/ball properties were directly adjusted
to exercise otherwise demo-locked behavior. Audio and visual quality were not
validated by these headless runs.
