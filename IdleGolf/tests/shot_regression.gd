extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
var state: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s: got %s expected %s" % [message, actual, expected])

func _initialize() -> void:
	_run.call_deferred()

func settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func make_ball(context: Dictionary, position: Vector3 = Vector3(300, 10, 80)) -> RigidBody3D:
	var ball = load("res://scenes/Ball.tscn").instantiate()
	ball.shot_context = context
	ball.position = position
	game.add_child(ball)
	ball.freeze = true
	ball.set_physics_process(false)
	return ball

func configure(ball_id: String, golfer_id: String = "standard", money_level: int = 0, xp_level: int = 0) -> Dictionary:
	state.equipped_ball = ball_id
	state.equipped_golfer = golfer_id
	state.upgrades.money_mult.level = money_level
	state.upgrades.xp_mult.level = xp_level
	return state.capture_shot_context(game._course_revision)

func _run() -> void:
	state = root.get_node("GameState")
	state.equipped_course = "course1"
	state.window_mode = "windowed"
	state.xp_to_next_level = 1.0e12
	state.sfx_muted = true
	state.music_muted = true
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var flag = game.level1_flags.get_child(0)

	# Every catalog ball retains its launch identity and miss payout despite an
	# equipment swap. Both higher and lower later stats must have no effect.
	for id in state.balls:
		var context := configure(id, "speedy", 3, 4)
		var ball = make_ball(context)
		configure("standard" if id != "standard" else "pinball", "standard", 0, 0)
		check(ball._ball_id == id and ball.shot_context.is_read_only() and ball.shot_context.ball_data.is_read_only(), "frozen launch snapshot: " + id)
		var before: float = state.money
		var xp_before: float = state.lifetime_xp
		game._on_ball_landed(100.0, ball)
		near(state.money - before, 7.0 * context.money_mult, "landing money snapshot: " + id)
		near(state.lifetime_xp - xp_before, 0.7 * context.money_mult * context.xp_mult, "landing XP snapshot: " + id)
		game._on_ball_landed(100.0, ball)
		near(state.money - before, 7.0 * context.money_mult, "duplicate landing rejected: " + id)
		ball.free()

	# Flag bonuses and golden rewards use the launching ball/golfer, including
	# when the golden award itself causes a level-up before ordinary payout.
	var context := configure("pin_seeker", "speedy", 2, 3)
	var ball = make_ball(context, flag.global_position)
	configure("standard", "standard", 20, 20)
	var before: float = state.money
	var xp_before: float = state.lifetime_xp
	var bonus: float = flag.global_position.z * 0.1 * flag.distance_mult
	flag.activate_golden()
	state.xp_to_next_level = 1.0
	game._on_ball_landed(100.0, ball)
	var expected: float = ((7.0 + bonus * 2.0) * 2.5 + bonus * 2.0 * 50.0) * context.money_mult
	near(state.money - before, expected, "flag and golden rewards use launch stats")
	near(state.lifetime_xp - xp_before, expected * 0.1 * context.xp_mult, "golden level-up does not reprice landing XP")
	state.xp_to_next_level = 1.0e12
	await settle()
	for key in state.level_bonuses:
		state.level_bonuses[key] = 0.0

	# Swapping INTO pinball must not grant a chain to a standard shot; swapping
	# OUT must not remove the original pinball chain or change its later rewards.
	context = configure("standard")
	ball = make_ball(context, flag.global_position)
	configure("pinball")
	before = state.money
	game._on_ball_landed(100.0, ball)
	await settle(90)
	near(state.money - before, (7.0 + bonus) * 2.5, "standard cannot gain pinball after launch")
	context = configure("pinball", "speedy", 1, 2)
	ball = make_ball(context, flag.global_position)
	before = state.money
	xp_before = state.lifetime_xp
	game._on_ball_landed(100.0, ball)
	configure("standard", "standard", 30, 30)
	expected = (7.0 + bonus) * 2.5 * context.money_mult
	for next_flag in game.level1_flags.get_children():
		if next_flag != flag:
			expected += next_flag.global_position.z * 0.1 * next_flag.distance_mult * 2.5 * context.money_mult
	await settle(150)
	near(state.money - before, expected, "pinball chain retains launch money multipliers")
	near(state.lifetime_xp - xp_before, expected * 0.1 * context.xp_mult, "pinball chain retains launch XP multiplier")

	# Firework children (including cosmetic children for course cleanup) inherit
	# the exact parent context even when equipment changes before the explosion.
	context = configure("firework", "speedy", 2, 3)
	ball = make_ball(context)
	var fragments: Array = []
	ball.exploded.connect(func(children): fragments.append_array(children))
	ball.exploded.connect(game._on_ball_exploded)
	configure("market", "standard", 0, 0)
	ball._explode()
	check(fragments.size() == 3, "near-range firework creates expected scoring children")
	for child in get_nodes_in_group("shots"):
		if child == ball:
			continue
		check(child.shot_context == context and child._ball_id == "firework", "fragment preserves parent equipment and course")
		child.freeze = true
		child.set_physics_process(false)
	before = state.money
	xp_before = state.lifetime_xp
	for child in fragments:
		child.global_position = Vector3(300, 1, 80)
		game._on_ball_landed(100.0, child)
	near(state.money - before, 21.0 * context.money_mult, "firework rewards stay firework after swapping to Market")
	near(state.lifetime_xp - xp_before, 2.1 * context.money_mult * context.xp_mult, "fragments retain launch XP")
	state.equipped_course = "course2"
	state.course_changed.emit()
	check(get_nodes_in_group("shots").is_empty(), "switch removes all outgoing real and cosmetic balls immediately")
	for child in fragments:
		check(child._cancelled and child.collision_layer == 0 and child.collision_mask == 0, "cancelled fragments cannot collide before deletion")
	before = state.money
	game._on_ball_landed(999.0, fragments[0])
	fragments[0]._explode()
	state.equipped_course = "course1"
	state.course_changed.emit()
	game._on_ball_landed(999.0, fragments[0])
	near(state.money, before, "stale callbacks cannot reward after switch or away-and-back")
	await settle()
	check(not is_instance_valid(fragments[0]), "cancelled fragments are freed")
	game._golden_timer.stop()

	# Reduced distant fragment counts preserve the parent's payout compensation.
	context = configure("firework", "speedy", 2, 3)
	ball = make_ball(context, Vector3(300, 10, 700))
	ball._start_z = 0.0
	fragments.clear()
	ball.exploded.connect(func(children): fragments.append_array(children))
	ball.exploded.connect(game._on_ball_exploded)
	configure("pin_seeker", "standard", 0, 0)
	ball._explode()
	check(fragments.size() == 2, "distant firework reduces scoring fragments")
	before = state.money
	for child in fragments:
		child.freeze = true
		child.set_physics_process(false)
		child.global_position = Vector3(300, 1, 80)
		game._on_ball_landed(100.0, child)
	near(state.money - before, 21.0 * context.money_mult, "distant fragments preserve launch stats and payout compensation")
	state.equipped_course = "course2"
	state.course_changed.emit()
	state.equipped_course = "course1"
	state.course_changed.emit()
	await settle()
	game._golden_timer.stop()

	# Mixed-equipment damage keeps each hit's value, even across course visits.
	var target = get_nodes_in_group("destructibles")[0]
	target.hits_required = 2
	var first := configure("wrecking", "speedy", 2, 4)
	target._take_hit(first)
	state.equipped_course = "course2"
	state.course_changed.emit()
	state.equipped_course = "course1"
	state.course_changed.emit()
	var last := configure("standard", "construction", 0, 0)
	configure("wrecking", "speedy", 20, 20)
	before = state.money
	xp_before = state.lifetime_xp
	var unit: float = target.money_per_hit * target.global_position.length() * 1.094
	target._take_hit(last)
	near(state.money - before, unit * (2.0 * first.money_mult + last.money_mult), "destruction sums each hit's launch contribution")
	near(state.lifetime_xp - xp_before, unit * 0.1 * (2.0 * first.money_mult * first.xp_mult + last.money_mult * last.xp_mult), "destruction retains per-hit XP")
	near(target._respawn_multiplier, 0.5, "finishing shot's golfer determines respawn")

	# Market deposits carry their originating XP through growth and later cashout.
	context = configure("market", "speedy", 1, 2)
	ball = make_ball(context, flag.global_position)
	configure("standard", "standard", 0, 30)
	before = state.money
	game._on_ball_landed(100.0, ball)
	near(state.money, before, "market shot still invests after equipment change")
	var invested: float = (7.0 + bonus * 1.5) * 2.5 * context.money_mult
	near(state.market.pots[game._market_key(flag)].money, invested, "deposit uses original Market flag multiplier")
	var later := configure("market", "standard", 0, 0)
	ball = make_ball(later, flag.global_position)
	game._on_ball_landed(100.0, ball)
	var invested_later: float = (7.0 + bonus * 1.5) * 2.5 * later.money_mult * 2.0
	game._process(1.0)
	var pot: float = (invested + invested_later) * exp(0.0002)
	var pot_xp: float = (invested * context.xp_mult + invested_later * later.xp_mult) * 0.1 * exp(0.0002)
	var miss := configure("standard", "standard", 0, 7)
	ball = make_ball(miss)
	configure("market", "speedy", 20, 20)
	xp_before = state.lifetime_xp
	game._on_ball_landed(100.0, ball)
	near(state.money - before, pot + 7.0 * miss.money_mult, "standard shot cashes out despite swapping into Market")
	near(state.lifetime_xp - xp_before, pot_xp + 0.7 * miss.money_mult * miss.xp_mult, "cashout cannot reprice earlier deposits' XP")
	check(state.market.pots.is_empty() and state.market.streak_count == 0, "cashout clears money and XP once")
	ball.free()
	await settle()

	# Switching courses also cashes the existing pot with its original XP stats.
	context = configure("market", "speedy", 1, 2)
	ball = make_ball(context, flag.global_position)
	game._on_ball_landed(100.0, ball)
	pot = state.market.pots[game._market_key(flag)].money
	pot_xp = state.market.pots[game._market_key(flag)].xp
	configure("standard", "standard", 20, 30)
	before = state.money
	xp_before = state.lifetime_xp
	state.equipped_course = "course2"
	state.course_changed.emit()
	near(state.money - before, pot, "course switch cashes existing investment")
	near(state.lifetime_xp - xp_before, pot_xp, "course cashout retains deposit XP")
	state.equipped_course = "course1"
	state.course_changed.emit()
	near(state.lifetime_xp - xp_before, pot_xp, "repeat switching cannot duplicate investment XP")
	await settle()

	# The next real multiball swing captures the new equipment consistently.
	configure("homing_ball", "power", 2, 2)
	state.upgrades.multi_ball.level = 2
	game._spawning_disabled = false
	game._hit_ball()
	game._spawning_disabled = true
	var volley := get_nodes_in_group("balls")
	check(volley.size() == 3, "real launch creates upgraded multiball volley")
	for child in volley:
		check(child.shot_context.ball_id == "homing_ball" and child.shot_context.golfer_id == "power" and child.shot_context.course_revision == game._course_revision, "next volley captures new equipment and current course")
	state.equipped_course = "course3"
	state.course_changed.emit()
	await settle()
	check(get_nodes_in_group("balls").is_empty(), "course switch cancels entire volley")
	for id in state.balls:
		context = configure(id)
		ball = make_ball(context)
		before = state.money
		state.equipped_course = "course2"
		state.course_changed.emit()
		check(ball._cancelled and not ball.is_shot_active() and ball.collision_mask == 0, "course cancellation: " + id)
		ball._land()
		if id == "firework":
			ball._explode()
		game._on_ball_landed(1000, ball)
		near(state.money, before, "cancelled shot cannot pay: " + id)
		state.equipped_course = "course3"
		state.course_changed.emit()
		await settle()
		check(not is_instance_valid(ball), "cancelled shot released: " + id)
	game.free()
	await process_frame
	print("SHOT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
