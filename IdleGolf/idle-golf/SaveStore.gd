extends RefCounted
## Checked, recoverable local saves. Only the primary file is a committed save.
## A complete pending write can be recovered if that primary is lost/damaged.

const VERSION := 3
const MarketLedger = preload("res://MarketLedger.gd")
const MAX_EXACT_INTEGER := 9007199254740991

var path: String
var blocked := true
var last_error := ""
var _defaults: ConfigFile
var _reset_requested := false

func _init(save_path: String, defaults: ConfigFile) -> void:
	path = save_path
	_defaults = defaults

func load_save(import_path: String = "") -> Dictionary:
	blocked = true
	last_error = ""
	var primary := _read(path)
	if primary.status == "ok":
		blocked = false
		return {"config": primary.config, "message": ""}
	if primary.status == "future":
		last_error = "This save was made by a newer version of Idle Golf. Update the game to use it. Saving is disabled to protect your progress."
		return {"config": null, "message": last_error}
	var found_file: bool = primary.status != "missing"
	for suffix in [".tmp", ".bak", ".bak.tmp"]:
		var candidate := _read(path + suffix)
		found_file = found_file or candidate.status != "missing"
		if candidate.status == "future":
			last_error = "A recovery save needs a newer version of Idle Golf. Update the game before saving. Your files have been left unchanged."
			return {"config": null, "message": last_error}
		if candidate.status == "ok":
			# Preserve recovery evidence before any later autosave reuses these paths.
			if _archive_existing() != OK:
				return {"config": candidate.config, "message": "Recovered progress, but could not preserve the damaged save files. Saving remains disabled. " + last_error}
			blocked = false
			return {"config": candidate.config, "message": "Recovered your progress from a previous or interrupted save. Some recent progress may be missing. The original files have been kept for recovery."}
	if found_file:
		last_error = "Your save could not be read, and no usable backup was found. Saving is disabled so the existing files stay safe. Restore a backup and restart, or use Reset Game to start again."
		return {"config": null, "message": last_error}
	if not import_path.is_empty():
		return _import_demo(import_path)
	blocked = false
	return {"config": null, "message": ""}

func _import_demo(import_path: String) -> Dictionary:
	# Read only: never rotate, archive, sanitize or write the other edition's
	# files. Called only when ALL destination save/recovery paths are absent.
	var found_file := false
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var candidate := _read(import_path + suffix)
		found_file = found_file or candidate.status != "missing"
		if candidate.status == "future":
			last_error = "Your demo progress needs a newer game version. Update before importing, or use Reset Game to start the full game fresh. The demo files have been left unchanged."
			return {"config": null, "message": last_error}
		if candidate.status == "ok":
			blocked = false
			var message := "Demo progress imported into the full game. Your demo save is unchanged; the two editions now save separately."
			if not suffix.is_empty():
				message += " A demo recovery file was used, so some recent progress may be missing."
			return {"config": candidate.config, "message": message, "imported": true}
	if found_file:
		last_error = "Demo progress could not be imported. Restore a demo backup and restart, or use Reset Game to start the full game fresh. Saving is disabled and the demo files have been left unchanged."
		return {"config": null, "message": last_error}
	blocked = false
	return {"config": null, "message": ""}

func write_save(config: ConfigFile) -> Error:
	if blocked:
		return ERR_FILE_CANT_WRITE
	var resetting := _reset_requested
	_reset_requested = false
	last_error = ""
	var problem := _validate_fields(config, true)
	if not problem.is_empty():
		return _fail("Progress contains an invalid value. Your previous save was kept. " + problem, ERR_INVALID_DATA)
	_stamp(config)
	# Recheck the primary: it may have been damaged/replaced since startup.
	var primary := _read(path)
	if primary.status == "future" and not resetting:
		blocked = true
		return _fail("A newer save was found. Update the game before saving; the file was not replaced.", ERR_INVALID_DATA)
	if primary.status == "invalid" and _archive(path) != OK:
		return ERR_FILE_CANT_WRITE
	if FileAccess.file_exists(path + ".tmp") and _archive(path + ".tmp") != OK:
		return ERR_FILE_CANT_WRITE
	var err := _write_config(config, path + ".tmp")
	if err != OK:
		return _fail("Could not write your progress. Check free disk space and folder permissions.", err)
	if _read(path + ".tmp").status != "ok":
		return _fail("The new save could not be verified. Your previous save was kept.", ERR_FILE_CORRUPT)
	# Prepare a verified backup before replacing the primary. Never rotate a
	# damaged primary over a usable backup, or delete the primary before rename.
	if resetting or primary.status == "ok" or _read(path + ".bak").status != "ok":
		var backup_source := path if primary.status == "ok" and not resetting else path + ".tmp"
		err = _copy_verified(backup_source, path + ".bak.tmp")
		if err != OK:
			return _fail("Could not prepare a backup. Your previous save was kept.", err)
		err = _rename_file(path + ".bak.tmp", path + ".bak")
		if err != OK:
			return _fail("Could not replace the backup. Your previous save was kept.", err)
	err = _rename_file(path + ".tmp", path)
	if err != OK:
		return _fail("Could not finish saving. Your previous save and pending progress were kept. Please retry.", err)
	return OK

func prepare_reset() -> Error:
	# Called only by the player's existing Reset Game confirmation. Keep even
	# unrecognized/newer files before explicitly replacing progress with a new game.
	var err := _archive_existing()
	if err == OK:
		blocked = false
		last_error = ""
		_reset_requested = true
	return err

func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		# A directory at the save path is not a fresh installation.
		return {"status": "invalid" if DirAccess.dir_exists_absolute(file_path) else "missing"}
	var config := ConfigFile.new()
	if config.load(file_path) != OK:
		return {"status": "invalid"}
	var version: Variant = config.get_value("meta", "version", 0)
	if typeof(version) != TYPE_INT or version < 0:
		return {"status": "invalid"}
	if version > VERSION:
		return {"status": "future"}
	if version >= 1:
		var checksum: Variant = config.get_value("meta", "checksum", "")
		if typeof(checksum) != TYPE_STRING or checksum != _checksum(config):
			return {"status": "invalid"}
	elif config.has_section("meta"):
		return {"status": "invalid"}
	if not _validate_fields(config, version >= 1, version).is_empty():
		return {"status": "invalid"}
	# Version 1 had no persisted Market state. Always migrate to empty pots,
	# never copy investments from the current in-memory session/defaults.
	if version < 2:
		config.set_value("market", "pots", {})
		config.set_value("market", "streak_key", "")
		config.set_value("market", "streak_count", 0)
	# Older saves contain no evidence of final-target destruction. Never infer
	# completion from ownership, distance records, or the current session.
	if version < 3:
		for course in ["course1", "course2", "course3"]:
			config.set_value("completion", course, false)
	# Version 0 is the shipped unversioned demo. Missing optional fields are
	# migrated from fresh-game defaults, not the current in-memory play session.
	for section in _defaults.get_sections():
		for key in _defaults.get_section_keys(section):
			if not config.has_section_key(section, key):
				config.set_value(section, key, _defaults.get_value(section, key))
	return {"status": "ok", "config": config}

func _validate_fields(config: ConfigFile, require_all: bool, version: int = VERSION) -> String:
	# Require the original player's core fields even for legacy saves; an empty
	# or unrelated config must not be mistaken for valid zero progress.
	for key in ["money", "xp", "level", "xp_to_next_level"]:
		if not config.has_section_key("player", key):
			return "Missing player data."
	for section in _defaults.get_sections():
		if section == "market" and version < 2:
			continue
		if section == "completion" and version < 3:
			continue
		for key in _defaults.get_section_keys(section):
			if not config.has_section_key(section, key):
				if require_all:
					return "Missing save data."
				continue
			var expected: Variant = _defaults.get_value(section, key)
			var value: Variant = config.get_value(section, key)
			match typeof(expected):
				TYPE_FLOAT, TYPE_INT:
					if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
						return "Invalid number in %s/%s." % [section, key]
					if not is_finite(float(value)) or value < 0:
						return "Out-of-range number in %s/%s." % [section, key]
					if typeof(expected) == TYPE_INT and (float(value) != floor(float(value)) or value > MAX_EXACT_INTEGER):
						return "Invalid level in %s/%s." % [section, key]
				TYPE_BOOL:
					if typeof(value) != TYPE_BOOL:
						return "Invalid toggle in %s/%s." % [section, key]
				TYPE_STRING:
					if typeof(value) != TYPE_STRING:
						return "Invalid text in %s/%s." % [section, key]
	var player_level: float = float(config.get_value("player", "level"))
	if player_level < 1 or not is_finite(100.0 * pow(1.4, player_level - 1.0)):
		return "Invalid player level."
	if config.get_value("player", "xp_to_next_level") < 1:
		return "Invalid XP threshold."
	if version >= 2:
		return MarketLedger.validate(config.get_value("market", "pots", null), config.get_value("market", "streak_key", null), config.get_value("market", "streak_count", null))
	return ""

func _stamp(config: ConfigFile) -> void:
	var payload := ConfigFile.new()
	payload.parse(config.encode_to_text())
	config.clear()
	# Put the version/checksum FIRST. Otherwise a file cut off at a section
	# boundary before trailing metadata could masquerade as a legacy save.
	config.set_value("meta", "version", VERSION)
	config.set_value("meta", "checksum", _checksum(payload))
	for section in payload.get_sections():
		if section == "meta":
			continue
		for key in payload.get_section_keys(section):
			config.set_value(section, key, payload.get_value(section, key))

func _checksum(config: ConfigFile) -> String:
	var payload := ConfigFile.new()
	# Canonical ordering survives parsing/rewriting. Include unknown fields so
	# corruption in data not consumed by this version is still detected.
	var sections := config.get_sections()
	sections.sort()
	for section in sections:
		if section == "meta":
			continue
		var keys := config.get_section_keys(section)
		keys.sort()
		for key in keys:
			payload.set_value(section, key, config.get_value(section, key))
	return payload.encode_to_text().sha256_text()

func _archive_existing() -> Error:
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		var err := _archive(path + suffix)
		if err != OK:
			return err
	return OK

func _archive(source: String) -> Error:
	if not FileAccess.file_exists(source):
		if DirAccess.dir_exists_absolute(source):
			return _fail("The save path is a folder. It was left unchanged.", ERR_FILE_CANT_WRITE)
		return OK
	var destination := source + ".recovery-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	while FileAccess.file_exists(destination):
		destination += "-copy"
	var err := _copy_verified(source, destination)
	if err != OK:
		return _fail("Could not preserve an existing save file. It was left unchanged.", err)
	return OK

func _copy_verified(source: String, destination: String) -> Error:
	var err := _copy_file(source, destination)
	if err != OK:
		return err
	var digest := FileAccess.get_sha256(source)
	if digest.is_empty() or digest != FileAccess.get_sha256(destination):
		return ERR_FILE_CORRUPT
	return OK

# Small filesystem boundary also allows deterministic failure-injection tests.
func _write_config(config: ConfigFile, destination: String) -> Error:
	return config.save(destination)

func _copy_file(source: String, destination: String) -> Error:
	return DirAccess.copy_absolute(source, destination)

func _rename_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(source, destination)

func _fail(message: String, error: Error) -> Error:
	last_error = message
	return error
