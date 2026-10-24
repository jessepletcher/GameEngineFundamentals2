extends RefCounted
## Save identities are permanent. Never include a release version in new paths.
## The historical demo filename is retained for existing players.

const DEMO_SAVE := "user://idle_golf_demo_v0_1.cfg"
const FULL_SAVE := "user://idle_golf_full.cfg"

static func is_demo() -> bool:
	return ProjectSettings.get_setting_with_override("game/edition") != "full"

static func save_path() -> String:
	return DEMO_SAVE if is_demo() else FULL_SAVE

static func demo_import_path() -> String:
	return "" if is_demo() else DEMO_SAVE

static func debug_tools_enabled() -> bool:
	# Content availability is independent of developer tools. Release templates
	# cannot enable these even if an editor setting was accidentally left on.
	return OS.is_debug_build() and bool(ProjectSettings.get_setting("game/debug_tools", false))
