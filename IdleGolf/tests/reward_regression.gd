extends SceneTree

const Rules = preload("res://RewardRules.gd")
# Independent release expectations, deliberately not read back from the catalog.
const BALLS = {
	"standard": [1.0, 1.0, 1.0], "homing_ball": [1.5, 1.0, 1.0],
	"pin_seeker": [1.0, 2.0, 1.0], "firework": [0.5, 1.0, 1.0],
	"market": [1.0, 1.5, 1.0], "wrecking": [1.0, 1.0, 2.0],
	"pinball": [0.7, 1.0, 1.0],
}
const GOLFERS = {"standard": 1.0, "power": 1.0, "speedy": 1.5,
	"Lion Trees": 1.25, "construction": 1.0, "golfer1": 1.0,
	"golfer2": 1.0, "golfer4": 1.15}
var checks := 0
var failures := 0
var state: Node
var game: Node3D

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s: got %s expected %s" % [message, actual, expected])

func reward_is(reward: Dictionary, money: float, xp_mult: float, label: String) -> void:
	near(reward.money, money, label + " money")
	near(reward.xp, money * 0.1 * xp_mult, label + " XP")

func configure(ball: String, golfer: String, upgraded: bool, revision: int = -1) -> Dictionary:
	state.equipped_ball = ball
	state.equipped_golfer = golfer
	state.upgrades.money_mult.level = 10 if upgraded else 0
	state.upgrades.xp_mult.level = 5 if upgraded else 0
	state.level_bonuses.money_mult = 0.25 if upgraded else 0.0
	state.level_bonuses.xp_mult = 0.2 if upgraded else 0.0
	return state.capture_shot_context(revision)

func make_ball(context: Dictionary, position: Vector3) -> RigidBody3D:
	var ball = load("res://scenes/Ball.tscn").instantiate()
	ball.shot_context = context
	ball.position = position
	game.add_child(ball)
	ball.freeze = true
	ball.set_physics_process(false)
	return ball

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	state = root.get_node("GameState")
	state.xp_to_next_level = 1.0e15
	state.sfx_muted = true
	state.music_muted = true
	state.window_mode = "windowed"
	check(state.balls.size() == BALLS.size() and state.golfers.size() == GOLFERS.size(), "matrix covers whole catalog")
	near(Rules.flag_bonus(200, 3, 0.5), 30, "accuracy and course flag multiplier")
	near(Rules.flag_bonus(200, 3, 0), 0, "flag boundary gives zero bonus")
	for upgraded in [false, true]:
		for ball_id in BALLS:
			for golfer_id in GOLFERS:
				var context := configure(ball_id, golfer_id, upgraded)
				var money_mult: float = BALLS[ball_id][0] * GOLFERS[golfer_id] * (2.375 if upgraded else 1.0)
				var xp_mult: float = 1.74 if upgraded else 1.0
				var flag_mult: float = BALLS[ball_id][1]
				var label := "%s/%s upgraded=%s" % [ball_id, golfer_id, upgraded]
				near(context.money_mult, money_mult, label + " combined multiplier")
				near(context.xp_mult, xp_mult, label + " XP multiplier")
				reward_is(Rules.landing(context, 100, 0, false), 7 * money_mult, xp_mult, label + " miss")
				reward_is(Rules.landing(context, 0, 0, false), 5 * money_mult, xp_mult, label + " zero distance")
				reward_is(Rules.landing(context, 100, 10, false), (7 + 10 * flag_mult) * money_mult, xp_mult, label + " near flag")
				reward_is(Rules.landing(context, 100, 20, true), (7 + 20 * flag_mult) * 2.5 * money_mult, xp_mult, label + " direct flag")
				reward_is(Rules.pinball(context, 20), 50 * flag_mult * money_mult, xp_mult, label + " chain")
				reward_is(Rules.golden(context, 20), 1000 * flag_mult * money_mult, xp_mult, label + " golden")
				reward_is(Rules.destructible_hit(context, 5, 100), 500 * BALLS[ball_id][2] * money_mult, xp_mult, label + " destructible")
				# Far fragments compensate 3 scoring particles with 2 at 1.5x each.
				reward_is(Rules.landing(context, 100, 20, true, 1.5), (7 + 20 * flag_mult) * 3.75 * money_mult, xp_mult, label + " compensated fragment")
				reward_is(Rules.golden(context, 20, 1.5), 1500 * flag_mult * money_mult, xp_mult, label + " fragment golden")
				var deposit := Rules.scale_reward(Rules.landing(context, 100, 20, true), 3.0)
				reward_is(Rules.scale_reward(deposit, 1.2), (7 + 20 * flag_mult) * 9.0 * money_mult, xp_mult, label + " streak/growth")

	# Real scene routing: golden/direct hits, fragments and destruction for each
	# ball, plus each golfer's miss payout. Expectations remain independent.
	state.equipped_course = "course1"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var flag = game.level1_flags.get_child(0)
	var bonus: float = flag.global_position.z * 0.1 * flag.distance_mult
	var target = get_nodes_in_group("destructibles")[0]
	target.hits_required = 1
	for ball_id in BALLS:
		var context := configure(ball_id, "speedy", true, game._course_revision)
		var money_mult: float = BALLS[ball_id][0] * 1.5 * 2.375
		var flag_mult: float = BALLS[ball_id][1]
		var ball = make_ball(context, flag.global_position)
		ball._payout_multiplier = 1.5 if ball_id == "firework" else 1.0
		var compensation: float = ball._payout_multiplier
		configure("standard", "standard", false, game._course_revision)
		flag.activate_golden()
		var before: float = state.money
		var lifetime_before: float = state.lifetime_money
		var xp_before: float = state.lifetime_xp
		game._text_queue.clear()
		game._queue_processing = true
		game._on_ball_landed(100, ball)
		# Market's ordinary reward is deferred; golden still credits immediately.
		var golden: float = bonus * flag_mult * 50 * money_mult * compensation
		if ball_id == "market":
			near(state.money - before, golden, "Market does not credit deposit early")
			game._cashout_all_investments()
		var expected: float = ((7 + bonus * flag_mult) * 2.5 + bonus * flag_mult * 50) * money_mult * compensation
		near(state.money - before, expected, ball_id + " actual direct/golden balance")
		near(state.lifetime_money - lifetime_before, expected, ball_id + " actual lifetime money")
		near(state.lifetime_xp - xp_before, expected * 0.174, ball_id + " actual XP")
		ball.cancel_shot()
		await process_frame
		game._golden_timer.stop()
		# Start a fresh target lifecycle for each ball, freeing bound animations.
		if ball_id != "standard":
			var replacement = load(target.scene_file_path).instantiate()
			var parent = target.get_parent()
			var transform = target.transform
			target.free()
			target = replacement
			parent.add_child(target)
			target.transform = transform
			target.hits_required = 1
			target.destroyed.connect(game._on_destructible_destroyed.bind(target))
		before = state.money
		xp_before = state.lifetime_xp
		game._text_queue.clear()
		target._take_hit(context)
		expected = target.money_per_hit * target.global_position.length() * 1.094 * BALLS[ball_id][2] * money_mult
		near(state.money - before, expected, ball_id + " actual destruction money")
		near(state.lifetime_xp - xp_before, expected * 0.174, ball_id + " actual destruction XP")
		target._take_hit(context)
		near(state.money - before, expected, ball_id + " destruction credits only once")
	for golfer_id in GOLFERS:
		var context := configure("homing_ball", golfer_id, true, game._course_revision)
		var ball = make_ball(context, Vector3(300, 10, 80))
		var before: float = state.money
		var xp_before: float = state.lifetime_xp
		game._text_queue.clear()
		game._on_ball_landed(100, ball)
		var expected: float = 7 * 1.5 * GOLFERS[golfer_id] * 2.375
		near(state.money - before, expected, golfer_id + " actual miss money")
		near(state.lifetime_xp - xp_before, expected * 0.174, golfer_id + " actual miss XP")
		ball.cancel_shot()
		await process_frame
	# A previously finalized reward must never pick up the currently equipped bonus.
	configure("homing_ball", "speedy", true)
	var before: float = state.money
	var xp_before: float = state.lifetime_xp
	state.credit_reward({"money": 10.0, "xp": 3.0})
	near(state.money - before, 10, "credit does not reapply money multipliers")
	near(state.lifetime_xp - xp_before, 3, "credit does not reapply XP multipliers")
	before = state.money
	xp_before = state.lifetime_xp
	state.add_money(10)
	near(state.money - before, 10 * 1.5 * 1.5 * 2.375, "legacy add_money delegates to rules")
	near(state.lifetime_xp - xp_before, 10 * 1.5 * 1.5 * 2.375 * 0.174, "legacy add_money XP")
	game.free()
	await process_frame
	print("REWARD_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
