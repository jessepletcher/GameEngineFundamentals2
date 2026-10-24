extends SceneTree
## Real scene/physics regression; run only through the isolated Python runner.
var checks := 0
var failures := 0
var game: Node3D
var state: Node

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

func switch_to(course: String) -> void:
	state.equipped_course = course
	state.course_changed.emit()

func make_ball() -> RigidBody3D:
	var ball = load("res://scenes/Ball.tscn").instantiate()
	ball.shot_context = state.capture_shot_context(game._course_revision)
	game.add_child(ball)
	ball.freeze = true
	ball.set_physics_process(false)
	return ball

func collides(target: Node3D, hit_shape: CollisionShape3D = null) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.02
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = (hit_shape if hit_shape else target.collision_shape).global_position
	for hit in game.get_world_3d().direct_space_state.intersect_shape(query, 64):
		if hit.collider == target.static_body:
			return true
	return false

func check_course(course: String) -> void:
	for key in game._course_data:
		for branch in [game._course_data[key].sprites, game._course_data[key].flags]:
			check(branch.visible == (key == course) and branch.can_process() == (key == course), "branch activity: " + key)
	for target in get_nodes_in_group("destructibles"):
		var active: bool = game._course_data[course].sprites.is_ancestor_of(target)
		check(target.can_process() == active, "destructible processing")
		for hit_shape in target.hit_shapes:
			check(collides(target, hit_shape) == (active and target._is_alive), "actual physics query excludes inactive destructible")
	check(game.get_node("Floor").can_process(), "shared ground remains active")

func _run() -> void:
	state = root.get_node("GameState")
	var initial := OS.get_cmdline_user_args()[0]
	state.equipped_course = initial
	state.window_mode = "windowed"
	state.sfx_muted = true
	state.music_muted = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	await settle()
	check_course(initial)
	for course in ["course2", "course3", "course1", "course3", "course2", "course1"]:
		switch_to(course)
		game._golden_timer.stop()
		await settle()
		check_course(course)

	var target = get_nodes_in_group("destructibles")[0]
	var flag = game.level1_flags.get_child(0)
	var probe := make_ball()
	probe.global_position = target.collision_shape.global_position
	await settle()
	check(target._hits_taken == 1, "active target registers a physical proximity hit")
	probe.free()
	switch_to("course2")
	game._golden_timer.stop()
	await settle()
	var hits: int = target._hits_taken
	var balance: float = state.money
	var experience: float = state.xp
	probe = make_ball()
	probe.global_position = target.collision_shape.global_position
	await settle(12)
	check(target._hits_taken == hits, "hidden targets do not scan nearby balls")
	target._physics_process(1.0)
	target._take_hit()
	target._crumble()
	target.destroyed.emit(1000.0, 100.0)
	flag.golden_hit.emit(flag, 1000.0, state.capture_shot_context(game._course_revision), 1.0)
	check(target._hits_taken == hits and target._is_alive, "disabled target rejects direct hit/crumble callbacks")
	check(state.money == balance and state.xp == experience, "disabled source signals cannot reward money or XP")
	check(flag.check_hit(flag.global_position) == [0.0, false], "hidden flag rejects hit test")
	flag.activate_golden()
	check(not flag._is_golden, "hidden flag cannot become golden")
	probe.free()

	# Homing must skip the nearest hidden flag and drop a retained target when
	# its course is disabled. Use the real Ball script without random launch.
	var ball = load("res://scenes/Ball.tscn").instantiate()
	game.add_child(ball)
	ball.freeze = true
	ball.set_physics_process(false)
	ball.global_position = flag.global_position + Vector3.UP * 4.0
	ball.linear_velocity = Vector3.ZERO
	ball._start_homing()
	check(ball._target_flag == game.level2_flags.get_child(0), "homing ignores nearer inactive flags")
	switch_to("course3")
	game._golden_timer.stop()
	ball._home_toward_flag(0.1)
	check(ball._target_flag == null and not ball._is_homing, "homing stops steering toward a disabled target")
	ball.free()
	ball = make_ball()
	ball._start_homing()
	check(ball._target_flag == game.level3_flags.get_child(0), "homing selects the newly active course")
	game.level3_flags.process_mode = Node.PROCESS_MODE_DISABLED
	ball._start_homing()
	check(ball._target_flag == null and not ball._is_homing, "no active flags leaves homing unset")
	ball.free()
	switch_to("course1")
	game._golden_timer.stop()
	check(target._hits_taken == hits, "switching back preserves partial damage")
	game._spawn_golden_flag()
	var golden = game._golden_flag
	check(golden.get_parent() == game.level1_flags and golden._is_golden, "golden selection uses current course")
	switch_to("course2")
	check(not golden._is_golden and game._golden_flag == null, "switch clears outgoing golden flag")

	# Bound crumble/respawn tweens freeze off-course; returning does not reset
	# damage or turn destroyed collision shapes back on early.
	switch_to("course1")
	game._golden_timer.stop()
	target.hits_required = hits + 1
	target.respawn_time = 0.05
	balance = state.money
	target._take_hit()
	check(not target._is_alive and state.money > balance, "active destruction rewards exactly on destruction")
	var after_reward: float = state.money
	target._take_hit()
	check(state.money == after_reward, "destroyed target cannot reward twice")
	switch_to("course2")
	game._golden_timer.stop()
	var before_position: Vector3 = target.scaled_sprite.position
	await settle(210)
	check(not target._is_alive and target.scaled_sprite.position == before_position, "inactive fall/respawn tween stays paused")
	check(not collides(target), "destroyed hidden target has no collider")
	switch_to("course1")
	game._golden_timer.stop()
	check(not target._is_alive and target.collision_shape.disabled, "reactivation does not revive a destroyed target early")
	await settle(210)
	check(target._is_alive and target._hits_taken == 0 and collides(target), "active respawn finishes and restores collision")

	# Pinball's awaited flight must not pay old-course flags after a rapid
	# A -> B -> A switch. A new chain on the active course must still pay.
	var pin := make_ball()
	pin.global_position = flag.global_position
	balance = state.money
	game._pinball_chain(pin, flag)
	switch_to("course2")
	switch_to("course1")
	game._golden_timer.stop()
	await settle(90)
	check(state.money == balance and not is_instance_valid(pin), "course change cancels pending pinball payouts even after returning")
	pin = make_ball()
	pin.global_position = flag.global_position
	game._pinball_chain(pin, flag)
	await settle(150)
	check(state.money > balance and not is_instance_valid(pin), "uninterrupted active pinball chain still rewards")
	game.free()
	await process_frame
	print("COURSE_TESTS initial=%s checks=%d failures=%d" % [initial, checks, failures])
	quit(1 if failures else 0)
