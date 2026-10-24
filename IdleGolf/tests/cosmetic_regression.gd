extends SceneTree
## Real Firework children, gameplay callbacks and physics-space overlap queries.
var checks := 0
var failures := 0
var state: Node
var game: Node3D
var landing_signals := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s: got %s expected %s" % [message, actual, expected])

func settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func collides(ball: RigidBody3D) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = ball.global_position
	query.collision_mask = 0xFFFFFFFF
	for hit in game.get_world_3d().direct_space_state.intersect_shape(query, 64):
		if hit.collider == ball:
			return true
	return false

func on_cosmetic_landed(_yards: float) -> void:
	landing_signals += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	state = root.get_node("GameState")
	state.equipped_course = "course1"
	state.equipped_ball = "firework"
	state.equipped_golfer = "standard"
	state.sfx_muted = true
	state.music_muted = true
	state.window_mode = "windowed"
	state.xp_to_next_level = 1.0e15
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var targets := get_nodes_in_group("destructibles")
	var flag = game.level1_flags.get_child(0)
	for variant in 2:
		var parent = load("res://scenes/Ball.tscn").instantiate()
		parent.shot_context = state.capture_shot_context(game._course_revision)
		parent.position = Vector3(300, 10, 80 if variant == 0 else 700)
		game.add_child(parent)
		parent._start_z = 0
		var scoring: Array = []
		var cosmetic: Array = []
		parent.exploded.connect(func(children): scoring.append_array(children))
		parent.exploded.connect(game._on_ball_exploded)
		parent._explode()
		for child in get_nodes_in_group("shots"):
			if child == parent:
				continue
			child.freeze = true
			child.set_physics_process(false)
			if child._is_fake:
				cosmetic.append(child)
		check(scoring.size() == (3 if variant == 0 else 2) and cosmetic.size() == 2, "real explosion preserves scoring and cosmetic counts")
		await settle()
		for child in cosmetic:
			check(child.is_in_group("shots") and not child.is_in_group("balls"), "cosmetic has cleanup membership only")
			check(child.collision_layer == 0 and child.collision_mask == 0 and child.get_node("CollisionShape3D").disabled, "cosmetic physics disabled")
			check(not collides(child), "actual physics query cannot hit cosmetic fragment")
			check(not child.can_damage_targets() and not game._is_shot_current(child), "cosmetic rejected by damage/reward entry points")
		for child in scoring:
			check(child.is_in_group("balls") and child.can_damage_targets(), "scoring fragment remains gameplay-capable")
			check(collides(child), "actual physics query still hits scoring fragment")
		var target = targets[variant]
		target.hits_required = 1
		var before: float = state.money
		var xp_before: float = state.lifetime_xp
		for child in cosmetic:
			child.global_position = target.collision_shape.global_position
		target._physics_process(0)
		check(target._hits_taken == 0 and target._is_alive, "cosmetics overlapping target cause no damage")
		# Defense in depth: even accidental gameplay group membership cannot damage.
		cosmetic[0].add_to_group("balls")
		target._physics_process(0)
		check(target._hits_taken == 0 and target._hit_balls.is_empty(), "damage guard rejects misgrouped cosmetic")
		cosmetic[0].remove_from_group("balls")
		near(state.money, before, "cosmetic target overlap pays no money")
		near(state.lifetime_xp, xp_before, "cosmetic target overlap pays no XP")
		flag.activate_golden()
		for child in cosmetic:
			child.global_position = flag.global_position
			game._on_ball_landed(100, child)
			game._pinball_chain(child, flag)
			child._start_homing()
			check(not child._is_homing and child._target_flag == null, "cosmetic cannot home")
			var count := get_nodes_in_group("shots").size()
			child._explode()
			check(get_nodes_in_group("shots").size() == count, "cosmetic cannot spawn scoring children")
		check(flag._is_golden and state.market.pots.is_empty(), "cosmetic landing cannot consume golden flag or invest")
		near(state.money, before, "cosmetic callbacks pay no money")
		near(state.lifetime_xp, xp_before, "cosmetic callbacks pay no XP")
		flag.deactivate_golden()
		# Cosmetic motion still uses gravity without collisions, then fades on landing.
		var effect = cosmetic[0]
		effect.global_position = Vector3(300, 10, 80)
		effect.linear_velocity = Vector3.ZERO
		effect.freeze = false
		effect.set_physics_process(true)
		await settle(10)
		check(effect.global_position.y < 10 and effect.trail.emitting, "cosmetic retains falling trail motion")
		effect.landed.connect(on_cosmetic_landed)
		effect._land()
		effect._land()
		await settle(8)
		check(effect.freeze and not effect.trail.emitting and not effect.is_physics_processing(), "cosmetic landing stops motion and trail emissions")
		check(landing_signals == 0, "cosmetic never emits scoring landing signal")
		await settle(30)
		check(not is_instance_valid(effect), "cosmetic frees itself after fading")
		# Scoring fragments still damage once and receive their B08 rewards.
		var real = scoring[0]
		real.global_position = target.collision_shape.global_position
		before = state.money
		xp_before = state.lifetime_xp
		target._physics_process(0)
		var expected: float = target.money_per_hit * target.global_position.length() * 1.094 * 0.5
		check(not target._is_alive and target._hits_taken == 1, "scoring fragment destroys target")
		near(state.money - before, expected, "scoring fragment retains destruction money")
		near(state.lifetime_xp - xp_before, expected * 0.1, "scoring fragment retains destruction XP")
		before = state.money
		for child in scoring:
			child.global_position = Vector3(300, 1, 80)
			game._on_ball_landed(100, child)
		near(state.money - before, 10.5, "real Firework landing compensation unchanged")
		var remaining_effect = cosmetic[1]
		state.equipped_course = "course2"
		state.course_changed.emit()
		check(remaining_effect._cancelled and get_nodes_in_group("shots").is_empty(), "course switch cancels cosmetic and scoring shots synchronously")
		state.equipped_course = "course1"
		state.course_changed.emit()
		game._golden_timer.stop()
		await settle()
		check(not is_instance_valid(remaining_effect), "course switch frees cosmetic fragment")
	game.free()
	await process_frame
	print("COSMETIC_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
