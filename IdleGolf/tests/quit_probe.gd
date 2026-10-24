extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func seed_market(state: Node, amount: float) -> void:
	state.market.pots = {"course1/BlackFlag": {"money": amount, "xp": amount * 0.1}}
	state.market.streak_key = "course1/BlackFlag"
	state.market.streak_count = 2

func _run() -> void:
	var state = root.get_node("GameState")
	var mode := OS.get_cmdline_user_args()[0]
	var previous_pot := {"exit": 12.5, "failed_close": 25.0, "discard": 37.5, "crash": 37.5, "verify_crash": 77.7}
	if previous_pot.has(mode):
		var expected: float = previous_pot[mode]
		if not is_equal_approx(state.market.total().money, expected) or not is_equal_approx(state.market.total().xp, expected * 0.1) or state.market.streak_count != 2:
			push_error("Market money/XP/streak did not survive previous process: " + mode)
			quit(1)
			return
	match mode:
		"close":
			seed_market(state, 12.5)
			state.money = 147.25
			root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		"exit":
			seed_market(state, 25.0)
			state.money = 258.5
			state.request_quit()
		"failed_close":
			seed_market(state, 37.5)
			state.money = 369.75
			# A real directory at the pending-write path makes saving fail.
			DirAccess.make_dir_absolute(state.SAVE_PATH + ".tmp")
			root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
			await create_timer(0.05).timeout
			if state.save_notice.is_empty():
				push_error("Failed quit did not report its save failure")
				quit(1)
				return
			print("QUIT_FAILURE_KEPT_SESSION")
			DirAccess.remove_absolute(state.SAVE_PATH + ".tmp")
			# Exercise the actual failure dialog's retry signal connection.
			state._quit_dialog.confirmed.emit()
		"discard":
			seed_market(state, 99.9)
			state.money = 999.0
			DirAccess.make_dir_absolute(state.SAVE_PATH + ".tmp")
			state.request_quit()
			state._quit_dialog.custom_action.emit(&"discard")
		"crash":
			seed_market(state, 77.7)
			state.money = 777.0
			if not state.save():
				quit(1)
				return
			state.money = 888.0
			seed_market(state, 88.8)
			print("READY_FOR_FORCED_STOP")
			# The runner kills this process without another save/quit handler.
		"verify_crash":
			if state.money != 777.0:
				push_error("Last committed progress was not recovered after forced stop")
				quit(1)
				return
			print("FORCED_STOP_RECOVERED_LAST_COMMIT")
			quit()
