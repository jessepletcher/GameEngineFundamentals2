extends SceneTree
## Use the simulator's earned stats, without extra speed or partial damage.
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var state = root.get_node("GameState")
	state.sfx_muted = true
	state.music_muted = true
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://campaign.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	for course in fixture.courses:
		state.equipped_course = "course%d" % int(course.course)
		state.courses[state.equipped_course].owned = true
		state.equipped_ball = course.ball
		state.equipped_golfer = course.golfer
		state.course_changed.emit()
		game._golden_timer.stop()
		for key in course.upgrades:
			state.upgrades[key].level = int(course.upgrades[key])
		for key in course.bonuses:
			state.level_bonuses[key] = course.bonuses[key]
		var target: Node3D
		for candidate in get_nodes_in_group("destructibles"):
			if candidate.can_process() and candidate.is_final_target:
				target = candidate
		check(target != null, "authored final target is active")
		game.aim_slider.value = -rad_to_deg(course.aim) / 50.0
		game.shot_control.normalized_pos = Vector2(0, (.3 - course.loft) / .3)
		var shots: Array = []
		# Only center balls contribute to the model's expected target damage.
		# Keep actual fan balls and count their hits too; do not give extra stats.
		for sample in 32:
			seed(60000 + int(course.course) * 100 + sample)
			game._spawning_disabled = false
			game._hit_ball()
			game._spawning_disabled = true
		for ball in get_nodes_in_group("balls"):
			shots.append(ball)
		for ball in shots:
			for other in shots:
				if ball != other:
					ball.add_collision_exception_with(other)
		for frame in 2400:
			await physics_frame
			await process_frame
			if get_nodes_in_group("balls").is_empty():
				break
		var actual: float = target._hits_taken / 32.0
		print("ECONOMY_PHYSICS course=%s predicted=%.3f actual=%.3f hits=%d" % [state.equipped_course, course.hit_probability, actual, target._hits_taken])
		check(actual >= 0.75, "simulated affordable stats reliably hit " + target.target_name)
		check(absf(actual - course.hit_probability) <= 0.25, "predicted hit rate agrees with real physics")
		for ball in get_nodes_in_group("shots"):
			ball.cancel_shot()
		await process_frame
	game.free()
	await process_frame
	print("ECONOMY_PHYSICS_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
