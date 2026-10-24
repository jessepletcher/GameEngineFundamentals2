Idle Golf - demo and full development builds (0.1.1)

Windows Demo and Windows Full are separate export presets. The full build
enables the existing full-game catalog; content and balance are still in progress.

The demo includes:
- Course 1: Big Piney
- Balls: Standard Ball, Pin Seeker, Firework Ball
- Golfers: Standard Golfer, Shop Keep, Lion Trees
- Cash upgrades, medal upgrades, XP levels, retirement/prestige, and the shop

Full game content visible in the shop is marked "Full Game" and cannot be purchased or equipped in this demo.
Full game item descriptions are hidden until the full game.
Some full-game medal upgrades are hidden in this demo.

Controls:
- The golfer swings automatically.
- Drag the shot control to adjust launch.
- Use the aim slider to adjust left/right aim.
- Open the shop to spend medals on demo-available balls and golfers.
- Use the settings button for window mode, resolution, VSync, SFX, music, reset, and exit.

Save data:
- No offline earnings: closing the game stops progression until you play again.
- Demo save: idle_golf_demo_v0_1.cfg (historical name retained for compatibility).
- Full save: idle_golf_full.cfg. Both names stay fixed across future releases.
- Windows folder: %APPDATA%\Godot\app_userdata\IdleGolf\.
- The full game imports demo progress once, only if no full save or recovery
  file exists. Import never modifies demo files. Subsequent progress is separate.
- Full saves and backups always take precedence over importing demo progress.
- A damaged/newer demo that cannot be imported is preserved; restore it or
  choose Reset Game in the full build to start fresh without altering the demo.
- Existing demo saves load automatically; the game keeps a backup when saving.
- If a save is damaged, the game attempts recovery and tells you what happened.
- If recovery is impossible, saving stays disabled to protect the original files.
- Failed exit saves offer Retry, Keep Playing, or Quit Without Saving.
- Reset Game affects only the running edition and does not reimport demo progress.
- Recovery copies are retained when resetting or recovering damaged saves.

Known demo notes:
- Art, balance, audio mix, and some shop item icons are work in progress.
- Courses 2 and 3 and several balls/golfers are intentionally locked for the full game.

Developer builds:
- game/edition defaults to demo in the editor. Set it to full to test full content.
- Export presets override edition through the demo/full feature tags.
- game/debug_tools is a separate opt-in for editor/debug builds only.
- F1 is disabled in both release exports, even if debug_tools is enabled.
- Keep application/config/name="IdleGolf": it is the permanent save-directory identity.
- Repeatable Windows exports: python tools/export_windows.py --godot <Godot-4.6.exe>
  Run from the repository root. See release-planning/BUILD_SEPARATION_UPDATE.txt.
