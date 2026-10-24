extends SceneTree
const Store = preload("res://SaveStore.gd")
var checks := 0
var failures := 0
var state: Node
var game: Node3D
var defaults: ConfigFile
var case_number := 0

class FailingStore extends "res://SaveStore.gd":
	var fail_write := true
	func _write_config(config: ConfigFile, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_config(config, destination)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), "%s: got %s expected %s" % [label, actual, expected])

func new_path() -> String:
	case_number += 1
	return "user://market-case-%d.cfg" % case_number

func fresh() -> void:
	state._apply_save_config(defaults)
	state.xp_to_next_level = 1.0e12
	state.balls.market.owned = true
	state.equipped_ball = "market"
	state.money = 100
	state.lifetime_money = 100
	state.window_mode = "windowed"
	state.sfx_muted = true
	state.music_muted = true
	state._save_store = Store.new(new_path(), defaults)
	state._save_store.load_save()

func scene() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	game.set_process(false)

func hit(flag: Node3D) -> void:
	var ball = load("res://scenes/Ball.tscn").instantiate()
	ball.shot_context = state.capture_shot_context(game._course_revision)
	ball.position = flag.global_position
	game.add_child(ball)
	ball.freeze = true
	ball.set_physics_process(false)
	game._on_ball_landed(100, ball)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	state = root.get_node("GameState")
	defaults = state._build_save_config()
	# Schema 1 migration verifies its original checksum and preserves original bytes.
	var old := ConfigFile.new()
	old.parse(defaults.encode_to_text())
	old.erase_section("market")
	old.set_value("meta", "version", 1)
	var path := new_path()
	var store := Store.new(path, defaults)
	old.set_value("meta", "checksum", store._checksum(old))
	old.save(path)
	var old_bytes := FileAccess.get_file_as_string(path)
	var loaded := store.load_save()
	check(loaded.config != null and not store.blocked, "v1 checksum save migrates")
	check(loaded.config.get_value("market", "pots").is_empty(), "v1 starts without invented pots")
	check(FileAccess.get_file_as_string(path) == old_bytes, "migration read preserves v1 bytes")
	check(store.write_save(loaded.config) == OK, "migrated save commits as v2")
	check(FileAccess.get_file_as_string(path + ".bak") == old_bytes, "v1 retained as migration backup")
	old.erase_section("settings")
	old.set_value("meta", "checksum", store._checksum(old))
	old.save(new_path())
	check(Store.new("user://market-case-%d.cfg" % case_number, defaults).load_save().config == null, "v1 migration still rejects missing required fields")

	# Malformed signed v2 records must be rejected, not silently zeroed.
	var invalid_cases := [
		[[], "", 0], [{"course1/BlackFlag": {"money": -1.0, "xp": 1.0}}, "course1/BlackFlag", 1],
		[{"course1/BlackFlag": {"money": INF, "xp": 1.0}}, "course1/BlackFlag", 1],
		[{"course1/BlackFlag": {"money": 1.0, "xp": NAN}}, "course1/BlackFlag", 1],
		[{"course1/BlackFlag": {"money": 1.0, "xp": true}}, "course1/BlackFlag", 1],
		[{"course1/BlackFlag": {"money": 1.0}}, "course1/BlackFlag", 1],
		[{"bad-key": {"money": 1.0, "xp": 1.0}}, "bad-key", 1],
		[{}, "course1/BlackFlag", 1], [{"course1/BlackFlag": {"money": 1.0, "xp": 1.0}}, "", 0],
		[{"course1/BlackFlag": {"money": 1.0, "xp": 1.0}}, "course1/BlackFlag", 1.5],
	]
	for invalid in invalid_cases:
		var config := ConfigFile.new()
		config.parse(defaults.encode_to_text())
		config.set_value("market", "pots", invalid[0])
		config.set_value("market", "streak_key", invalid[1])
		config.set_value("market", "streak_count", invalid[2])
		path = new_path()
		store = Store.new(path, defaults)
		store.load_save()
		check(store.write_save(config) != OK, "invalid Market write rejected")
		store._stamp(config)
		config.save(path)
		check(store.load_save().config == null and store.blocked, "invalid signed Market load protected")

	fresh()
	scene()
	var flag = game.level1_flags.get_child(0)
	var key: String = game._market_key(flag)
	hit(flag)
	hit(flag)
	var base: float = state.market.pots[key].money / 3.0
	game._process(1.0)
	var pot: Dictionary = state.market.pots[key].duplicate(true)
	check(state.market.streak_count == 2 and state.money == 100, "real deposits accumulate without premature credit")
	check(state.save(), "save live investments")
	var committed: String = state._save_store.path
	var snapshot: ConfigFile = state._build_save_config()
	game.free()
	await process_frame
	state.market.clear()
	check(state.load_game(), "reload investments from disk")
	near(state.market.pots[key].money, pot.money, "reload exact accrued money without offline growth")
	near(state.market.pots[key].xp, pot.xp, "reload original XP")
	scene()
	flag = game.level1_flags.get_child(0)
	check(game._market_labels.has(flag), "new scene restores pot label on stable flag identity")
	check(state.market.streak_count == 2 and state.money == 100, "scene startup preserves pot and streak")
	hit(flag)
	near(state.market.pots[key].money, pot.money + 3 * base, "same-flag streak continues after reload")
	pot = state.market.total()
	var xp_before: float = state.lifetime_xp
	state.equipped_course = "course2"
	state.course_changed.emit()
	near(state.money, 100 + pot.money, "course switch cashes full restored pot")
	near(state.lifetime_xp - xp_before, pot.xp, "course switch cashes original XP")
	check(state.market.pots.is_empty() and state.market.streak_count == 0, "cashout clears persistent pots/streak")
	game._cashout_all_investments()
	near(state.money, 100 + pot.money, "second cashout does not duplicate money")
	check(state.save() and state.load_game(), "cashout persists")
	check(state.market.pots.is_empty(), "reloading cashed-out save cannot revive pots")
	game.free()
	await process_frame

	# Recovery preserves both sides of a transaction from the same committed save.
	store = Store.new(committed, defaults)
	var recovered := store.load_save()
	check(recovered.config.get_value("market", "pots").is_empty(), "committed cashout and empty ledger agree")
	var file := FileAccess.open(committed, FileAccess.WRITE)
	file.store_string("[player]\nmoney=7\n")
	file.close()
	state._save_store = Store.new(committed, defaults)
	check(state.load_game(), "corrupt primary recovers prior Market commit")
	near(state.money, 100, "recovery restores pre-cashout balance")
	near(state.market.pots[key].money, snapshot.get_value("market", "pots")[key].money, "recovery restores corresponding pre-cashout pot")

	# Removed targets and unavailable courses cash out safely rather than lose data.
	fresh()
	state.market.deposit("removed-course/missing-flag", {"money": 42.0, "xp": 13.0})
	scene()
	near(state.money, 142, "missing target cashed at scene restore")
	near(state.lifetime_xp, 13, "missing target retains XP")
	check(state.market.pots.is_empty(), "missing target cannot cash twice")
	game.free()
	await process_frame

	# Multiple flags retain independent amounts/XP and the last flag's streak.
	fresh()
	state.market.deposit("course1/BlackFlag", {"money": 40.0, "xp": 4.0})
	state.market.deposit("course1/BlueFlag", {"money": 150.0, "xp": 30.0})
	check(state.save(), "save multi-flag pots")
	state.market.clear()
	check(state.load_game() and state.market.pots.size() == 2, "reload both independent pots")
	scene()
	check(game._market_labels.size() == 2, "restore labels for every saved pot")
	check(state.market.streak_key == "course1/BlueFlag" and state.market.streak_count == 1, "restore last flag streak identity")
	state.market.deposit("course1/BlueFlag", {"money": 50.0, "xp": 5.0})
	near(state.market.pots["course1/BlueFlag"].money, 250, "restored streak scales only the new deposit")
	near(state.market.pots["course1/BlackFlag"].money, 40, "other flag pot is unchanged")
	state.upgrades.xp_mult.level = 20
	game._cashout_all_investments()
	near(state.money, 390, "multi-pot cashout credits their sum")
	near(state.lifetime_xp, 44, "multi-pot cashout preserves per-deposit XP")
	game.free()
	await process_frame
	fresh()
	state.market.deposit("course2/Flag", {"money": 21.0, "xp": 2.0})
	scene()
	near(state.money, 121, "inactive-course restored pot safely cashes out")
	check(state.market.pots.is_empty(), "inactive-course pot is cleared after credit")
	game.free()
	await process_frame

	# Retirement previews include uncashed money, and confirmed retirement credits
	# XP/records before resetting the run. Failed writes restore the whole session.
	fresh()
	state.market.deposit(key, {"money": 900.0, "xp": 50.0})
	state.xp_to_next_level = 1.0 # exercise level/bonus rollback on failed retirement
	var preview: float = state.get_medal_reward()
	check(preview > state.get_medal_reward(false), "medal preview includes pot")
	check(state.save(), "checkpoint pre-retirement pot")
	var original: String = state._build_save_config().encode_to_text()
	var faulty := FailingStore.new(state._save_store.path, defaults)
	faulty.load_save()
	state._save_store = faulty
	check(not state.retire(), "retirement reports save failure")
	check(state._build_save_config().encode_to_text() == original, "failed retirement restores pot/money/XP/levels/upgrades/records")
	check(not state.save_notice.is_empty(), "failed retirement explains saving problem")
	faulty.fail_write = false
	check(state.retire(), "retirement retries successfully")
	near(state.medals, preview, "confirmed medals match pot-inclusive preview")
	near(state.best_run_money, 1000, "retirement record includes Market money")
	near(state.best_run_xp, 50, "retirement record includes Market XP")
	check(state.money == 0 and state.lifetime_money == 0 and state.market.pots.is_empty(), "retirement clears run balance and pots together")
	check(state.level > 1 and state.load_game() and state.market.pots.is_empty(), "retirement retains levels and persists empty pot")
	# Reset follows the existing rollback/backup guarantees too.
	state.market.deposit(key, {"money": 33.0, "xp": 4.0})
	faulty.fail_write = true
	check(not state.full_reset() and state.market.total().money == 33, "failed reset retains investment")
	faulty.fail_write = false
	check(state.full_reset() and state.market.pots.is_empty(), "successful reset clears investment")
	check(Store.new(faulty.path + ".bak", defaults).load_save().config.get_value("market", "pots").is_empty(), "reset backup cannot resurrect investment")
	print("MARKET_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
