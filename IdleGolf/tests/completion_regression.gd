extends SceneTree
const Store = preload("res://SaveStore.gd")
var checks := 0
var failures := 0
var celebrations := 0
var state: Node
var game: Node3D

class FailingStore extends "res://SaveStore.gd":
	var fail_write := true
	func _write_config(config: ConfigFile, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_config(config, destination)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func _run() -> void:
	state = root.get_node("GameState")
	state.completed_courses = {"course1": false, "course2": false, "course3": false}
	var defaults: ConfigFile = state._build_save_config()
	# Versions 0/1/2 must not invent completion, even with completed defaults.
	var dirty_defaults: ConfigFile = state._build_save_config()
	for course in state.COURSE_FINAL_TARGETS:
		dirty_defaults.set_value("completion", course, true)
	for version in [0, 1, 2]:
		var config := ConfigFile.new()
		config.parse(defaults.encode_to_text())
		config.erase_section("completion")
		if version < 2:
			config.erase_section("market")
		var path := "user://completion-v%d.cfg" % version
		var store := Store.new(path, dirty_defaults)
		if version > 0:
			config.set_value("meta", "version", version)
			config.set_value("meta", "checksum", store._checksum(config))
		config.save(path)
		var loaded := store.load_save()
		check(loaded.config != null, "legacy schema loads")
		for course in state.COURSE_FINAL_TARGETS:
			check(not loaded.config.get_value("completion", course), "legacy completion starts false")
		check(store.write_save(loaded.config) == OK, "legacy migrates to v3")
	var invalid := ConfigFile.new()
	invalid.parse(defaults.encode_to_text())
	var validation_store := Store.new("user://completion-validation.cfg", defaults)
	invalid.set_value("completion", "course1", "true")
	check(not validation_store._validate_fields(invalid, true).is_empty(), "completion requires booleans")
	invalid.erase_section_key("completion", "course1")
	check(not validation_store._validate_fields(invalid, true).is_empty(), "v3 requires all completion fields")
	state._save_store = Store.new("user://completion-live.cfg", defaults)
	state._save_store.load_save()
	state.window_mode = "windowed"
	state.sfx_muted = true
	state.music_muted = true
	for course in state.courses:
		state.courses[course].owned = true
	state.equipped_course = "course1"
	state.course_completed.connect(func(_course: String): celebrations += 1)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	await settle()
	var ui = game.get_node("CanvasLayer/CompletionUI")
	check(ui.status_button.text.contains("0 / 3"), "fresh HUD")
	var ordinary = game.get_node("Level1/Destructible4")
	ordinary._hits_taken = ordinary.hits_required - 1
	ordinary._take_hit()
	check(state.completed_course_count() == 0, "ordinary destruction is not completion")
	game.get_node("Level2/Pyramids").destroyed.emit(0, 0)
	check(state.completed_course_count() == 0, "inactive final signal is ignored")
	for course in state.COURSE_FINAL_TARGETS:
		state.equipped_course = course
		state.course_changed.emit()
		game._golden_timer.stop()
		await settle()
		if course == "course3":
			check(not state.record_course_completion(course, "level3_lighthouse"), "old lighthouse target cannot newly complete Beach")
			var lighthouse = game.get_node("Level3/Lighthouse")
			lighthouse._hits_taken = lighthouse.hits_required - 1
			lighthouse._take_hit()
			check(not state.completed_courses[course], "ordinary lighthouse destruction is not completion")
		var target: Node3D
		for obj in get_nodes_in_group("destructibles"):
			if obj.can_process() and obj.is_final_target:
				target = obj
		target.destroyed.emit(0, 0)
		check(not state.completed_courses[course], "alive final cannot emit a fake completion")
		target._hits_taken = target.hits_required - 2
		target._take_hit()
		check(not state.completed_courses[course], "partial final damage is not completion")
		target._take_hit()
		check(state.completed_courses[course], "final destruction completes current course")
		var saved := ConfigFile.new()
		check(saved.load(state._save_store.path) == OK and saved.get_value("completion", course), "milestone saved immediately")
		var count := celebrations
		target.destroyed.emit(0, 0)
		check(celebrations == count, "repeated destruction does not celebrate again")
		target._respawn()
		check(state.completed_courses[course], "respawn retains completion")
	check(state.is_game_complete() and celebrations == 3, "exactly three milestones complete game")
	check(ui.status_button.text.contains("3 / 3") and ui.title_label.text == "Game complete!", "game completion feedback")
	check(state.retire() and state.is_game_complete(), "retirement preserves completion")
	state.completed_courses = {"course1": false, "course2": false, "course3": false}
	state._apply_save_config(state._save_store.load_save().config)
	check(state.is_game_complete(), "disk reload restores all three")
	check(state.full_reset() and state.completed_course_count() == 0, "confirmed reset clears completion")
	check(not ui.status_button.text.contains("3 / 3"), "reset refreshes HUD")
	state._apply_save_config(state._save_store.load_save().config)
	check(not state.is_game_complete(), "reset remains cleared on disk")
	# Failed completion save retains earned progress for retry; no false saved UI.
	state.equipped_course = "course1"
	var failing := FailingStore.new("user://completion-failed.cfg", defaults)
	failing.load_save()
	state._save_store = failing
	check(state.record_course_completion("course1", "level1_destructible3"), "failed save retains new milestone")
	check(state.completed_courses.course1 and not state.save_notice.is_empty(), "failure is visible without losing earned completion")
	check(ui.save_label.text.contains("not be saved"), "UI does not claim save success")
	failing.fail_write = false
	check(state.save() and state.save_notice.is_empty(), "retry saves earned milestone")
	check(failing.load_save().config.get_value("completion", "course1"), "retry persisted milestone")
	# Reset rollback must also restore completion when the new save cannot commit.
	failing.fail_write = true
	check(not state.full_reset() and state.completed_courses.course1, "failed reset restores completion")
	failing.fail_write = false
	state.save()
	state.IS_DEMO_BUILD = true
	state.equipped_course = "course2"
	state.courses.course2.owned = true
	check(not state.record_course_completion("course2", "level2_pyramids"), "demo cannot complete paid courses")
	check(not state.record_course_completion("course1", "level1_destructible3"), "outgoing course cannot complete")
	game.free()
	await process_frame
	print("COMPLETION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
