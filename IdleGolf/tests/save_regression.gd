extends SceneTree

const Store = preload("res://SaveStore.gd")
var failures := 0
var checks := 0
var defaults: ConfigFile
var case_number := 0

class FaultyStore extends "res://SaveStore.gd":
	var fail_write := false
	var fail_copy := false
	var fail_destination := ""
	var truncate_write := false
	func _write_config(config: ConfigFile, destination: String) -> Error:
		if fail_write:
			return ERR_FILE_CANT_WRITE
		if truncate_write:
			var file := FileAccess.open(destination, FileAccess.WRITE)
			file.store_string("[player]\nmoney=1\n")
			file.close()
			return OK
		return super._write_config(config, destination)
	func _copy_file(source: String, destination: String) -> Error:
		if fail_copy:
			return ERR_FILE_CANT_WRITE
		return super._copy_file(source, destination)
	func _rename_file(source: String, destination: String) -> Error:
		if destination == fail_destination:
			return ERR_FILE_CANT_WRITE
		return super._rename_file(source, destination)

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func new_path() -> String:
	case_number += 1
	var folder := "res://test-data/case-%d" % case_number
	DirAccess.make_dir_recursive_absolute(folder)
	return folder + "/save.cfg"

func config_with_money(amount: float) -> ConfigFile:
	var config := ConfigFile.new()
	config.parse(defaults.encode_to_text())
	config.set_value("player", "money", amount)
	return config

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func has_archive(path: String, original: String) -> bool:
	for file in DirAccess.get_files_at(path.get_base_dir()):
		if file.begins_with(path.get_file() + ".recovery-"):
			if FileAccess.get_file_as_string(path.get_base_dir().path_join(file)) == original:
				return true
	return false

func seed_commits(store: Store) -> void:
	store.load_save()
	check(store.write_save(config_with_money(100.0)) == OK, "first save")
	check(store.write_save(config_with_money(200.0)) == OK, "second save")

func _run() -> void:
	defaults = root.get_node("GameState")._build_save_config()
	var path := new_path()
	var store := Store.new(path, defaults)
	var result := store.load_save()
	check(result.config == null and not store.blocked, "missing save starts a writable new game")
	check(not FileAccess.file_exists(path), "loading a new game does not write")
	check(store.write_save(config_with_money(12.345678901234567)) == OK, "fractional values survive checksum roundtrip")
	check(FileAccess.file_exists(path + ".bak"), "first save also has a verified backup")
	check(FileAccess.get_file_as_string(path).begins_with("[meta]"), "integrity header precedes payload")
	result = Store.new(path, defaults).load_save()
	check(is_equal_approx(result.config.get_value("player", "money"), 12.345678901234567), "saved value reloads")
	check(store.write_save(config_with_money(1.0e200)) == OK, "large finite idle-game balances are not arbitrarily capped")

	path = new_path()
	var legacy := FileAccess.get_file_as_string("res://tests/fixtures/legacy_save.cfg")
	write_text(path, legacy)
	store = Store.new(path, defaults)
	result = store.load_save()
	check(result.config.get_value("player", "money") == 1234.5, "legacy money preserved")
	check(result.config.get_value("balls", "pin_seeker"), "legacy ownership preserved")
	check(result.config.get_value("upgrades", "multi_ball_spread") == 0, "new legacy fields default safely")
	check(result.config.get_value("settings", "music_muted") == false, "absent legacy settings default safely")
	check(FileAccess.get_file_as_string(path) == legacy, "legacy load does not mutate disk")
	check(store.write_save(result.config) == OK, "legacy migrates on successful save")
	check(FileAccess.get_file_as_string(path + ".bak") == legacy, "original legacy bytes retained in backup")
	var migrated := ConfigFile.new()
	migrated.load(path)
	check(migrated.get_value("meta", "version") == Store.VERSION, "migrated schema is versioned")
	check(str(migrated.get_value("meta", "checksum")).length() == 64, "migrated payload has checksum")

	for damage in ["malformed", "truncated", "section_boundary", "changed_value"]:
		path = new_path()
		store = Store.new(path, defaults)
		seed_commits(store)
		if damage == "malformed":
			write_text(path, "[invalid")
		elif damage == "section_boundary":
			write_text(path, FileAccess.get_file_as_string(path).split("[upgrades]")[0])
		else:
			var corrupt := ConfigFile.new()
			corrupt.load(path)
			if damage == "truncated":
				corrupt.erase_section("settings")
			else:
				corrupt.set_value("player", "money", 999.0)
			corrupt.save(path)
		var damaged_bytes := FileAccess.get_file_as_string(path)
		store = Store.new(path, defaults)
		result = store.load_save()
		check(result.config != null and result.config.get_value("player", "money") == 100.0, damage + " recovers previous commit")
		check(not result.message.is_empty(), damage + " informs player of recovery")
		check(has_archive(path, damaged_bytes), damage + " preserves original bytes")
		check(store.write_save(config_with_money(300.0)) == OK, damage + " recovered session can save")
		var backup := Store.new(path + ".bak", defaults).load_save()
		check(backup.config.get_value("player", "money") == 100.0, damage + " does not rotate bad primary into backup")

	path = new_path()
	var blocked_recovery := FaultyStore.new(path, defaults)
	seed_commits(blocked_recovery)
	write_text(path, "[damaged")
	blocked_recovery.fail_copy = true
	result = blocked_recovery.load_save()
	check(result.config.get_value("player", "money") == 100 and blocked_recovery.blocked, "archive failure allows reading backup but blocks writes")
	check(blocked_recovery.write_save(config_with_money(400)) != OK, "archive failure does not allow overwrite")
	check(blocked_recovery.prepare_reset() != OK, "reset cannot discard files it could not archive")
	check(FileAccess.get_file_as_string(path) == "[damaged", "archive failure preserves primary bytes")

	for suffix in [".tmp", ".bak", ".bak.tmp"]:
		path = new_path()
		store = Store.new(path, defaults)
		store.load_save()
		var candidate := config_with_money(77.0)
		store._stamp(candidate)
		candidate.save(path + suffix)
		result = store.load_save()
		check(result.config != null and result.config.get_value("player", "money") == 77.0, "recover interrupted artifact " + suffix)
		check(store.write_save(result.config) == OK, "resume after " + suffix + " recovery")

	for invalid_value in ["not a number", true, -1.0, NAN, INF]:
		path = new_path()
		var invalid := config_with_money(0)
		invalid.set_value("player", "money", invalid_value)
		invalid.save(path)
		var original := FileAccess.get_file_as_string(path)
		store = Store.new(path, defaults)
		result = store.load_save()
		check(result.config == null and store.blocked, "invalid numeric save is blocked: " + str(invalid_value))
		check(store.write_save(config_with_money(1)) != OK, "blocked autosave fails")
		check(FileAccess.get_file_as_string(path) == original, "blocked autosave leaves original untouched")

	for field in [["player", "level", 0], ["player", "level", 1.5], ["player", "level", 3000], ["player", "xp_to_next_level", 0], ["upgrades", "fire_rate", "bad"], ["settings", "music_muted", 1], ["player", "equipped_ball", []]]:
		path = new_path()
		var invalid := config_with_money(0)
		invalid.set_value(field[0], field[1], field[2])
		invalid.save(path)
		store = Store.new(path, defaults)
		check(store.load_save().config == null and store.blocked, "invalid field rejected: " + str(field))

	for invalid_text in ["", "[player]\nmoney=1\n", "[other]\nvalue=1\n"]:
		path = new_path()
		write_text(path, invalid_text)
		store = Store.new(path, defaults)
		check(store.load_save().config == null and store.blocked, "empty/incomplete/unrelated config is not a new game")

	path = new_path()
	store = Store.new(path, defaults)
	seed_commits(store)
	var future := config_with_money(999)
	future.set_value("meta", "version", Store.VERSION + 1)
	future.save(path)
	var future_bytes := FileAccess.get_file_as_string(path)
	store = Store.new(path, defaults)
	check(store.load_save().config == null and store.blocked, "future primary never falls back to an older backup")
	check(store.write_save(config_with_money(5)) != OK and FileAccess.get_file_as_string(path) == future_bytes, "future save cannot be downgraded")
	check(store.prepare_reset() == OK, "explicit reset can archive future save")
	check(store.write_save(config_with_money(0)) == OK, "explicit reset can start fresh")
	check(has_archive(path, future_bytes), "explicit reset retains original future save")

	for failure in ["write", "short_write", "backup_copy", "backup_rename", "primary_rename"]:
		path = new_path()
		var faulty := FaultyStore.new(path, defaults)
		seed_commits(faulty)
		var committed := FileAccess.get_file_as_string(path)
		faulty.fail_write = failure == "write"
		faulty.truncate_write = failure == "short_write"
		faulty.fail_copy = failure == "backup_copy"
		if failure == "backup_rename":
			faulty.fail_destination = path + ".bak"
		elif failure == "primary_rename":
			faulty.fail_destination = path
		check(faulty.write_save(config_with_money(300)) != OK, "reported " + failure)
		check(FileAccess.get_file_as_string(path) == committed, failure + " leaves committed save intact")
		result = Store.new(path, defaults).load_save()
		check(result.config.get_value("player", "money") == 200.0, failure + " restart prefers committed primary")
		faulty.fail_write = false
		faulty.truncate_write = false
		faulty.fail_copy = false
		faulty.fail_destination = ""
		check(faulty.write_save(config_with_money(400)) == OK, failure + " retry succeeds")

	path = new_path()
	store = Store.new(path + "/missing/save.cfg", defaults)
	store.load_save()
	check(store.write_save(config_with_money(1)) != OK, "real unavailable directory fails without fake success")
	check(not store.last_error.is_empty(), "real filesystem failure has a player-facing message")
	path = new_path()
	DirAccess.make_dir_absolute(path)
	store = Store.new(path, defaults)
	check(store.load_save().config == null and store.blocked, "directory at save path is protected")
	check(store.prepare_reset() != OK, "reset does not destroy a directory at save path")

	# GameState integration: legacy loading, business-rule sanitization, a failed
	# reset retaining the session, and recovery from unreadable data with no backup.
	var state = root.get_node("GameState")
	path = new_path()
	var invalid_equipment := config_with_money(456)
	invalid_equipment.set_value("player", "equipped_ball", "removed_item")
	invalid_equipment.set_value("upgrades", "multi_ball", 99)
	invalid_equipment.save(path)
	state._save_store = Store.new(path, defaults)
	check(state.load_game(), "GameState loads validated legacy progress")
	check(state.money == 456 and state.equipped_ball == "standard" and state.upgrades.multi_ball.level == 3, "GameState applies equipment fallback and level cap")
	check(state.save(), "GameState save returns success")
	var failing_reset := FaultyStore.new(path, defaults)
	failing_reset.load_save()
	failing_reset.fail_write = true
	state._save_store = failing_reset
	check(not state.full_reset() and state.money == 456, "failed reset preserves in-memory progress")
	check(not state.save_notice.is_empty(), "failed save is visible to the player")
	failing_reset.fail_write = false
	check(state.full_reset() and state.money == 0, "confirmed reset succeeds after filesystem recovery")
	check(Store.new(path + ".bak", defaults).load_save().config.get_value("player", "money") == 0, "reset backup cannot automatically resurrect pre-reset progress")
	check(state.save_notice.is_empty(), "successful retry clears error status")
	path = new_path()
	write_text(path, "[unreadable")
	state._save_store = Store.new(path, defaults)
	check(not state.load_game(), "no-backup corruption blocks GameState saves")
	check(not state.save(), "GameState autosave respects block")
	check(FileAccess.get_file_as_string(path) == "[unreadable", "GameState does not overwrite unreadable save")
	check(state.full_reset(), "confirmed reset recovers from blocked state")
	check(has_archive(path, "[unreadable"), "confirmed reset archives unreadable save")
	# Demo/full migration is a read-only import into an absent destination.
	var demo_path := new_path()
	var demo := Store.new(demo_path, defaults)
	demo.load_save()
	check(demo.write_save(config_with_money(123)) == OK, "seed demo progress")
	var demo_bytes := FileAccess.get_file_as_string(demo_path)
	var demo_backup := FileAccess.get_file_as_string(demo_path + ".bak")
	path = new_path()
	store = Store.new(path, defaults)
	result = store.load_save(demo_path)
	check(result.get("imported", false) and result.config.get_value("player", "money") == 123, "full imports demo on first launch")
	check(store.write_save(result.config) == OK, "import committed to full slot")
	check(FileAccess.get_file_as_string(demo_path) == demo_bytes and FileAccess.get_file_as_string(demo_path + ".bak") == demo_backup, "import preserves demo bytes and backup")
	check(store.write_save(config_with_money(999)) == OK, "full progresses independently")
	check(demo.write_save(config_with_money(234)) == OK, "demo progresses independently")
	result = Store.new(path, defaults).load_save(demo_path)
	check(not result.get("imported", false) and result.config.get_value("player", "money") == 999, "full always wins over demo on subsequent launches")
	check(Store.new(demo_path, defaults).load_save().config.get_value("player", "money") == 234, "full writes never reach demo")
	store = Store.new(path, defaults)
	store.load_save(demo_path)
	check(store.prepare_reset() == OK and store.write_save(config_with_money(0)) == OK, "full reset commits a new full save")
	result = Store.new(path, defaults).load_save(demo_path)
	check(result.config.get_value("player", "money") == 0 and not result.get("imported", false), "reset cannot reimport demo")
	# Destination corruption/recovery must never silently replace paid progress
	# with demo progress, including when only a pending or backup file remains.
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		path = new_path()
		write_text(path + suffix, "[broken")
		store = Store.new(path, defaults)
		check(store.load_save(demo_path).config == null and store.blocked, "damaged full " + suffix + " blocks demo import")
		path = new_path()
		config_with_money(555).save(path + suffix)
		result = Store.new(path, defaults).load_save(demo_path)
		check(result.config.get_value("player", "money") == 555 and not result.get("imported", false), "existing full " + suffix + " takes precedence")
	# Read-only source recovery and unsupported source versions.
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		demo_path = new_path()
		config_with_money(321).save(demo_path + suffix)
		var before := DirAccess.get_files_at(demo_path.get_base_dir())
		var source_bytes := FileAccess.get_file_as_string(demo_path + suffix)
		result = Store.new(new_path(), defaults).load_save(demo_path)
		check(result.get("imported", false) and result.config.get_value("player", "money") == 321, "legacy demo import from " + suffix)
		check(before == DirAccess.get_files_at(demo_path.get_base_dir()) and source_bytes == FileAccess.get_file_as_string(demo_path + suffix), "source import creates no files: " + suffix)
	demo_path = new_path()
	future.save(demo_path)
	config_with_money(321).save(demo_path + ".bak")
	store = Store.new(new_path(), defaults)
	check(store.load_save(demo_path).config == null and store.blocked, "future demo primary cannot import an older backup")
	demo_path = new_path()
	write_text(demo_path, "[broken")
	store = Store.new(new_path(), defaults)
	check(store.load_save(demo_path).config == null and store.blocked, "unreadable demo offers explicit fresh start instead of silent loss")
	check(store.prepare_reset() == OK and store.write_save(config_with_money(0)) == OK, "explicit full reset resolves failed import")
	check(FileAccess.get_file_as_string(demo_path) == "[broken", "full reset leaves damaged demo unchanged")
	store = Store.new(new_path(), defaults)
	result = store.load_save(new_path())
	check(result.config == null and not store.blocked, "full without demo starts fresh")
	print("SAVE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
