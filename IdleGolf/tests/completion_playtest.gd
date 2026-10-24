extends Node
## External playtest driver, never included in the shipping game's resources.
var state: Node
var game: Node3D
var tools_panel: PanelContainer
var note: Label
var selection: OptionButton
var fixture_target: Node3D
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("IDLE_GOLF_COMPLETION_TEST") != "1":
		get_tree().quit(1)
		return
	state = get_tree().root.get_node("GameState")
	state.window_mode = "windowed"
	state.window_size = "1600x900"
	state.has_clicked_help_button = true
	_build_game()
	var mode := OS.get_environment("IDLE_GOLF_COMPLETION_CHECK")
	if not mode.is_empty():
		await _automated_check(mode)

func _build_game() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	get_tree().current_scene = self
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var layer := CanvasLayer.new()
	layer.layer = 20
	game.add_child(layer)
	tools_panel = PanelContainer.new()
	tools_panel.position = Vector2(350, 810)
	tools_panel.custom_minimum_size = Vector2(650, 160)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.16, 0.96)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	tools_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(tools_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	tools_panel.add_child(box)
	var heading := Label.new()
	heading.text = "COMPLETION PLAYTEST - separate test saves"
	box.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	selection = OptionButton.new()
	for course in ["Big Piney", "Desert", "Beach"]:
		selection.add_item(course)
	selection.selected = ["course1", "course2", "course3"].find(state.equipped_course)
	row.add_child(selection)
	_button(row, "Set up final shot", _prepare)
	_button(row, "Shoot", _shoot)
	_button(row, "Reset test progress", _reset_test)
	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 610
	note.text = "Select a course, set up the final shot, then Shoot. Close and reopen to check that completion stays saved. Normal game saves are separate."
	box.add_child(note)
	state.course_completed.connect(_on_completed)

func _button(row: HBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	row.add_child(button)
	button.pressed.connect(action)

func _on_completed(_course: String) -> void:
	note.text = "Course beaten! Use Courses beaten at the top to review progress. Close and reopen to verify saving, or set up another course."

func _prepare() -> void:
	# Setup affects only this separate profile. Completion still requires the
	# production destruction callback and the normal launcher/physics path.
	var course: String = ["course1", "course2", "course3"][selection.selected]
	for id in state.courses:
		state.courses[id].owned = true
	for key in state.upgrades:
		state.upgrades[key].level = 0
	for key in state.level_bonuses:
		state.level_bonuses[key] = 0.0
	state.upgrades.consistency.level = 95
	state.upgrades.consistency_mult.level = 10
	state.equipped_ball = "standard"
	state.equipped_golfer = "standard"
	state.equipped_course = course
	state.course_changed.emit()
	game._golden_timer.stop()
	game._set_spawning_disabled(true)
	fixture_target = null
	for target in get_tree().get_nodes_in_group("destructibles"):
		if target.can_process() and target.is_final_target:
			fixture_target = target
	if not fixture_target._is_alive:
		note.text = "Wait for the target to respawn, then set up the shot again."
		return
	fixture_target._hits_taken = fixture_target.hits_required - 1
	var point: Vector3 = fixture_target.collision_shape.global_position
	var distance := Vector2(point.x, point.z).length()
	var aim := atan2(point.x, point.z)
	for upgrade in range(1500):
		var speed := 10.0 * (1.0 + upgrade * 0.04)
		var horizontal := speed * (1.0 - 0.5 / 60.0)
		if horizontal <= distance * 0.1:
			continue
		var flight_time := -log(1.0 - .1 * distance / horizontal) / .1
		var vertical: float = (point.y - game.tee_position.global_position.y + 98.0 * flight_time) / (distance / horizontal) - 98.0
		var loft := vertical / speed
		if loft >= .07 and loft <= .52:
			# Keep test-only upgrade prices within the existing HUD's number range.
			# Supply the remaining speed through a test XP bonus instead.
			state.upgrades.ball_speed.level = mini(upgrade, 100)
			state.level_bonuses.ball_speed = (1.0 + upgrade * .04) / (1.0 + state.upgrades.ball_speed.level * .04) - 1.0
			game.aim_slider.value = -rad_to_deg(aim) / 50.0
			game.shot_control.normalized_pos = Vector2(0, (.3 - loft) / .3)
			var control = game.shot_control
			control.drag_point.position = (control.normalized_pos + Vector2.ONE) * .5 * control.size - control.drag_point.size * .5
			break
	state.save()
	note.text = "Ready: %s has one hit left. Press Shoot and allow about 15-25 seconds for the ball to arrive." % fixture_target.target_name

func _shoot() -> void:
	if not is_instance_valid(fixture_target) or not fixture_target._is_alive:
		note.text = "Set up a live final target first."
		return
	for ball in get_tree().get_nodes_in_group("shots"):
		ball.cancel_shot()
	seed(1001)
	game._spawning_disabled = false
	game._hit_ball()
	game._spawning_disabled = true

func _reset_test() -> void:
	# This button is only in the explicitly isolated playtest copy.
	if not state.full_reset():
		return
	state.course_completed.disconnect(_on_completed)
	game.queue_free()
	await get_tree().process_frame
	state.window_mode = "windowed"
	state.has_clicked_help_button = true
	_build_game()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _automated_check(mode: String) -> void:
	await get_tree().process_frame
	if mode == "complete":
		_check(state.completed_course_count() == 0, "fresh isolated test profile")
		for index in 3:
			selection.selected = index
			_prepare()
			_shoot()
			for frame in 2400:
				await get_tree().physics_frame
				await get_tree().process_frame
				if not fixture_target._is_alive:
					break
			_check(state.completed_course_count() == index + 1, "exported real shot completes course")
			_check(game.get_node("CanvasLayer/CompletionUI").panel.visible, "completion feedback visible")
		_check(state.is_game_complete(), "exported game complete")
		_check(state.save(), "exported milestones committed")
	elif mode == "reload":
		_check(state.is_game_complete(), "new process retained all milestones")
		_check(game.get_node("CanvasLayer/CompletionUI").status_button.text.contains("3 / 3"), "loaded completion HUD")
		_check(state.retire() and state.is_game_complete(), "exported retirement retains completion")
	elif mode == "reset":
		_check(state.is_game_complete(), "completion survived retirement restart")
		await _reset_test()
		_check(not state.is_game_complete(), "exported reset clears completion")
		_check(is_instance_valid(tools_panel) and tools_panel.is_inside_tree(), "test controls remain usable after reset")
	elif mode == "verify-reset":
		_check(state.completed_course_count() == 0, "new process retained reset")
	get_tree().current_scene = null
	game.free()
	await get_tree().process_frame
	print("COMPLETION_PLAYTEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
