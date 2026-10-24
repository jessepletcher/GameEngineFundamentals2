REQUIRED RELEASE CHECKS

python tools/check_release.py --godot "C:/path/to/Godot_v4.6-stable_win64.exe"

Runs diagnostic failure-injection tests, an empty-editor baseline, first/repeat
imports and 600-frame smoke
runs from fresh production-only copies of both editions, then the save, gameplay,
shutdown and real-mixer audio suites. No existing .godot cache is reused. Use the
non-self-contained Godot 4.6 stable editor; self-contained editors are rejected
because they bypass APPDATA isolation. Python -O/PYTHONOPTIMIZE is rejected too.

All automated runners use tools/godot_checks.py, --verbose, and independent checks
of stdout/stderr AND the engine log. Nonzero exits, missing logs, timeouts, script
errors, warnings, invalid UID fallbacks, failed assertions, ObjectDB/RID leaks and
orphan/unclaimed StringNames fail validation. Full output remains under
.test-output, including timeout output. Editor ports are isolated from open editors.

Exceptions are explicit and bounded: intentional malformed-save parser messages
(maximum ten, only the save-regression stage), exact save failure/recovery/import
notices in their corresponding fixtures, and the pinned official 4.6 editor's
single extra Node StringName plus its summary. That editor-only pair was reproduced
in an empty project; no runtime orphan report is accepted. Additional names,
references, warnings beyond the fixture count budget, or unrelated errors fail. See
release-planning/CLEAN_IMPORT_UPDATE.txt for reproduction evidence and limits.

SAVE AND QUIT REGRESSION TESTS

Run from the repository root with Python 3 and the Godot 4.6 editor:

python tests/run_save_tests.py --godot "C:/path/to/Godot_v4.6-stable_win64.exe"

The runner creates a disposable project under .test-output/save-tests, uses fresh
APPDATA/LOCALAPPDATA/temp directories, redirects BuildProfile save paths to that
project's test-data folder and changes the copied application name. It never reads
or writes actual IdleGolf player saves. A strict source-string assertion checks that the save-path
override was applied. Tests and fixtures are outside the shipping Godot project.

Do not run the GDScript probes directly against the live game project. Use the
runner: it deliberately writes malformed files and kills its isolated crash worker.

Coverage:
- Fresh saves; legacy fixture migration; settings/ownership/default preservation.
- Checksums, metadata-first layout, fractional/large balances and backup rotation.
- Corrupt and parseable-truncated files, invalid types, NaN/Infinity, future schemas.
- Recovery from .tmp/.bak/.bak.tmp and preservation of original recovery files.
- Failed writes, short writes, failed backup copies and failed replacements.
- Recovery/reset archiving failures, explicit reset and in-memory reset rollback.
- GameState validation, equipment fallback, upgrade caps and failure notices.
- Save-on-close notification, shared Exit handler, retry and explicit discard wiring.
- Real process termination after a checkpoint and recovery of the committed value.
- Main-scene startup after importing a clean source copy.
- One-time demo import, read-only source recovery, full-slot precedence and resets.
- Cross-process Market money/XP/streak persistence through close, Exit, failed-save
  retry, explicit discard and forced termination at a committed checkpoint.

Each run retains logs and a summary.json in its run directory. An intentionally
malformed fixture may produce ConfigFile parse errors; those are expected and
assertions verify recovery. SCRIPT ERROR, script load failures, nonzero exits,
failed assertions and unexpected diagnostics fail the suite. The prior user://
profiler error was fixed by correcting profile isolation and precreating the user
data directory; it is no longer allowed. No export is performed by this runner.

Manual release validation still includes native window X/Alt+F4, the on-screen
failure dialogs, real OS permission/locked-file behavior, supported exported builds
and Steam shutdown. Fault injection proves error handling, not every filesystem's
durability during sudden power loss. Concurrent game instances and Cloud/account
sync are separate release tasks.

WINDOWS RELEASE TESTS

python tools/export_windows.py --godot "C:/path/to/Godot_v4.6-stable_win64.exe"
python tests/run_export_tests.py --builds "idle-golf/builds/windows/<build-folder>"
python tests/launch_export_ui.py --builds "idle-golf/builds/windows/<build-folder>" --edition full --profile native-ui

tools/export_windows.py now REQUIRES the complete source checks before export and
the packaged-runtime suite after export; no skip-checks option exists. It checks
that source hashes did not change during validation. manifest.json is written
only after both editions pass, with source/artifact/engine hashes and log paths.
A failed attempt may leave executables, but no successful validation manifest.
This is a local release gate, not a server-side branch/Steam upload restriction.

The export runner tests identical executable copies using external test-scene
overrides, since release templates ignore --script. It also runs the packaged
main scene with overrides removed. Both editions share one isolated APPDATA to
exercise migration and isolation. A second profile covers full-first launch order.
The UI launcher runs the original executable with isolated data, keeps the parent
alive until exit, and records a PID and timestamped verbose logs. Do not ship its
test data or any override.cfg. See release-planning/BUILD_SEPARATION_UPDATE.txt for
the earlier native Windows QA results. CLEAN_IMPORT_UPDATE.txt records the latest
automatically checked B01-B12 builds; native/device/Steam QA must use those builds.

COURSE ISOLATION, SHOT, REWARD, COSMETIC AND MARKET TESTS

python tests/run_course_tests.py --godot "C:/path/to/Godot_v4.6-stable_win64.exe"

Creates a clean project snapshot with full content enabled and isolated Windows
APPDATA/LOCALAPPDATA/temp directories under .test-output/course-tests. Runs the
actual main scene from each of the three starting courses. Tests physical shape
queries against all five destructibles, repeated switching, hidden hit/reward
callbacks, homing selection/invalidation, golden flags, preserved damage,
paused/resumed crumble/respawn tweens, and interrupted/normal pinball chains.
Then runs the airborne-shot regression scene: all seven ball snapshots, equipment
and upgrade swaps, duplicate landing callbacks, golden rewards during level-up,
pinball continuity, near/distant firework fragments, immediate course cancellation,
mixed destructible contributions, Market deposit XP through growth/cashout/course
switching, and real multiball launches.
Also runs reward_regression.gd: independent expected multipliers for every
ball/golfer combination with zero and nonzero upgrades/level bonuses, all reward
types, fragment compensation, Market streak/growth, actual scene payouts and
single-credit money/lifetime/XP accounting. B08 expectations include catalog ball
money factors and ball flag factors on golden bonuses. The matrix deliberately
uses literal expected factors rather than deriving them from the production code.
cosmetic_regression.gd exercises actual near/distant Firework explosions: cosmetic
fragments are absent from physics queries, cannot damage (even if misgrouped),
reward, home, explode or consume golden flags. Gravity/trail motion, fade cleanup,
and course cancellation remain functional. Real scoring fragments retain physical
collision, destructible damage, landing money/XP and distant-fragment compensation.
market_regression.gd tests v1 checksum migration to v2, strict malformed Market
record rejection, live deposit/save/reload, restored labels/streaks, multi-flag
pots, cashout/reload without duplication, corrupted-primary recovery, missing or
inactive targets, pot-inclusive retirement previews/records, failed-retirement
rollback (including level-ups), retry, and reset/backup behavior. The legacy v0
fixture and general file-recovery cases remain in the save suite.
shutdown_regression.gd verifies payout burst batching, idle/restart, scene reload
while a callback is pending, and process shutdown during a payout burst. The
verbose gate rejects orphaned timer names; gameplay payout tests also exercise
mid-queue scene teardown.
Unexpected engine diagnostics and failed checks fail the run.
The shared ground remains active. All test saves remain inside the disposable copy.

AUDIO MIXER TESTS

python tests/run_audio_tests.py --godot "C:/path/to/Godot_v4.6-stable_win64.exe"

Creates an isolated project/profile under .test-output/audio-tests. A test-only
AudioManager subclass overrides the headless playback skip so the actual manager
logic and real AudioStreamPlayers run through Godot's Dummy audio driver. Capture
effects read separate music, ambience and SFX PCM buses; generated tones provide
stable expectations and the real game assets/scene exercise integration. There is
no speaker output or microphone recording. Never run the probe against live saves.

Checks saved mute startup, initial unmute, active mute/resume, shop pause combined
with mute, playback-position trim looping, short-stream natural completion,
active pooled/overflow SFX stop/release, no stale SFX replay, SFX-only ducking,
real shop transitions, scene reload while the shop is open, and stream cleanup.
PCM checks allow 150 ms for in-flight mixer buffers before sampling a fresh window.
Unexpected engine errors, leaked-instance warnings or failed assertions fail the
runner. Physical device output, subjective sound quality and native/exported audio
QA remain separate release checks.
