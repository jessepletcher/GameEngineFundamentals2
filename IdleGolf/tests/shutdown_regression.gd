extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func make_scene() -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene._set_spawning_disabled(true)
	scene._golden_timer.stop()
	return scene

func _run() -> void:
	var state = root.get_node("GameState")
	state.window_mode = "windowed"
	state.sfx_muted = true
	state.music_muted = true
	var game = make_scene()
	var emitted := [0]
	game.child_entered_tree.connect(func(child: Node):
		if child.scene_file_path == "res://scenes/FloatingText.tscn":
			emitted[0] += 1
	)
	for i in 8:
		game._text_queue.append({"money": 10.0, "yards": 3.0})
	game._process_text_queue()
	check(emitted[0] == 1 and game._text_queue.size() == 7, "first payout displays immediately")
	check(game._queue_processing, "queue stays busy between callbacks")
	await create_timer(0.85).timeout
	check(emitted[0] == 5, "burst displays four payouts and one summary")
	check(game._text_queue.is_empty() and not game._queue_processing, "queue returns to idle after summary")
	game._text_queue.append({"money": 20.0, "yards": 6.0})
	game._process_text_queue()
	check(emitted[0] == 6, "new payout restarts after completed burst")
	# Free during the pending callback, then reload; verbose log checks reject
	# orphaned timeout names as well as invalid calls into the freed scene.
	game.free()
	game = make_scene()
	await create_timer(0.25).timeout
	check(not game._queue_processing and game._text_queue.is_empty(), "reload has no pending old payouts")
	for i in 8:
		game._text_queue.append({"money": 10.0, "yards": 3.0})
	game._process_text_queue()
	print("SHUTDOWN_TESTS checks=%d failures=%d" % [checks, failures])
	# Also terminate the entire tree in the middle of a queued burst.
	quit(1 if failures else 0)
