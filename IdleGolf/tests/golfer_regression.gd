extends SceneTree

var checks := 0
var failures := 0
var contacts := 0
var state: Node
var game: Node
var golfer: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), "%s: %s != %s" % [message, actual, expected])

func equip(id: String) -> void:
	state.equipped_golfer = id
	state.golfer_changed.emit()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	state = root.get_node("GameState")
	state.sfx_muted = true
	state.music_muted = true
	state.equipped_course = "course1"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	golfer = game.golfer
	golfer.set_spawn_disabled(false)
	golfer.set_process(false) # Advance the real timeline deterministically below.
	golfer.swung.connect(func(): contacts += 1)
	var expected := {
		"standard": [1.0, 1.0, 1.0, 1.0], "power": [1.15, .95, 1.0, 1.0],
		"speedy": [1.0, 1.0, 1.5, 1.0], "Lion Trees": [1.2, 1.0, 1.25, 1.0],
		"construction": [1.0, 1.0, 1.0, .5], "golfer1": [1.1, 1.0, 1.0, 1.0],
		"golfer2": [1.0, 1.15, 1.0, 1.0], "golfer4": [1.0, 1.0, 1.15, 1.0],
	}
	check(state.golfers.size() == 8, "all eight retained golfers")
	var sheets := {}
	for id in expected:
		equip(id)
		state.equipped_ball = "standard"
		state.upgrades.ball_speed.level = 10
		state.upgrades.fire_rate.level = 10
		state.upgrades.money_mult.level = 0
		state.level_bonuses.ball_speed = .2
		state.level_bonuses.fire_rate = .3
		state.level_bonuses.money_mult = 0.0
		var values: Array = expected[id]
		near(state.get_ball_speed(), 1.4 * 1.2 * values[0], id + " launch strength")
		near(state.get_fire_rate(), 1.3 * 1.3 * values[1], id + " shot cadence")
		near(state.get_swing_speed(), 1.6 * 1.3 * values[1], id + " animation cadence")
		near(state.get_money_mult(), values[2], id + " money passive")
		var context: Dictionary = state.capture_shot_context()
		near(context.respawn_mult, values[3], id + " respawn passive")
		equip("standard" if id != "standard" else "construction")
		near(context.respawn_mult, values[3], id + " airborne respawn snapshot")
		near(context.money_mult, values[2], id + " airborne reward snapshot")
		equip(id)
		var data: Dictionary = state.golfers[id]
		check(not sheets.has(data.spritesheet), id + " distinct swing art")
		sheets[data.spritesheet] = true
		check(not data.texture.resource_path.contains("BallIcon"), id + " actual portrait")
		check(golfer.sprite.sprite_frames.get_frame_count("swing") == 5, id + " five poses")
		for frame in 5:
			var atlas: AtlasTexture = golfer.sprite.sprite_frames.get_frame_texture("swing", frame)
			check(Rect2(Vector2.ZERO, atlas.atlas.get_size()).encloses(atlas.region), id + " valid atlas region")
			golfer._show_frame(frame)
			check(golfer.sprite.offset.is_finite(), id + " registered pose")
		for upgrade in [0, 60, 534, 3000]:
			state.upgrades.fire_rate.level = upgrade
			golfer.cancel_swing()
			var before := contacts
			golfer.play_swing()
			var duration: float = golfer._duration
			check(duration < 5.0 / state.get_fire_rate(), id + " swing fits shot interval")
			golfer._process(duration * .59)
			check(contacts == before, id + " no premature launch")
			golfer.play_swing() # Repeated requests cannot restart the windup.
			golfer._load_golfer_sprite() # Shop closure cannot restart it either.
			golfer._process(duration * .02)
			check(contacts == before + 1 and golfer.sprite.frame == 3, id + " launches at contact pose")
			golfer._process(duration)
			golfer._process(duration)
			check(contacts == before + 1 and not golfer._swing_active and golfer.sprite.frame == 0, id + " exactly one shot then ready")
			golfer.play_swing()
			golfer._process(10.0) # A dropped frame crossing contact/end must still fire once.
			check(contacts == before + 2, id + " hitch cannot skip contact")
		# Changing equipment and courses during windup must cancel the old shot.
		var before := contacts
		golfer.play_swing()
		golfer._process(golfer._duration * .2)
		equip("standard" if id != "standard" else "golfer2")
		golfer._process(10)
		check(contacts == before and not golfer._swing_active, id + " equipment cancels windup")
		equip(id)
		golfer.play_swing()
		game._switch_course(false)
		golfer._process(10)
		check(contacts == before and not golfer._swing_active, id + " course cancels windup")
		golfer.play_swing()
		golfer.set_spawn_disabled(true)
		golfer.set_spawn_disabled(false)
		golfer._process(10)
		check(contacts == before, id + " disabled windup stays cancelled")
		golfer.play_swing()
		golfer._process(10)
		check(contacts == before + 1, id + " next swing still works")
	# Real Timer and process callbacks: all golfers release repeated upgraded
	# shots at the advertised rate instead of dropping requests between swings.
	golfer.swung.disconnect(game._on_golfer_swung)
	game._spawning_disabled = false
	for id in expected:
		equip(id)
		state.upgrades.fire_rate.level = 60
		state.level_bonuses.fire_rate = 0.0
		golfer.set_process(true)
		golfer.cancel_swing()
		game.shot_timer.wait_time = 5.0 / state.get_fire_rate()
		game.shot_timer.start()
		var before := contacts
		for frame in 1200:
			await process_frame
		game.shot_timer.stop()
		var estimate := floori(20.0 * state.get_fire_rate() / 5.0)
		check(absi(contacts - before - estimate) <= 1, id + " real timer cadence")
		golfer.set_process(false)
		golfer.cancel_swing()
	game._spawning_disabled = true
	# Blue Collar halves the post-fall wait of the finishing shot, including
	# when a different golfer is equipped before that shot destroys the target.
	var target: Node = get_nodes_in_group("destructibles").filter(func(t): return t.can_process() and not t.is_final_target)[0]
	target.respawn_time = 4.0
	for finisher in ["construction", "standard"]:
		equip(finisher)
		var finishing_context: Dictionary = state.capture_shot_context()
		equip("standard" if finisher == "construction" else "construction")
		target._hits_taken = target.hits_required - 1
		target._take_hit(finishing_context)
		for frame in 270:
			await process_frame
		check(target._is_alive == (finisher == "construction"), finisher + " actual respawn after 4.5 seconds")
		for frame in 120:
			await process_frame
		check(target._is_alive, finisher + " respawns by 6.5 seconds")
	check(state.golfers.golfer4.medal_cost < state.golfers.speedy.medal_cost and state.golfers.golfer4.unlock_level < state.golfers.speedy.unlock_level, "Money Daily is an earlier money specialist")
	game.free()
	await process_frame
	print("GOLFER_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
