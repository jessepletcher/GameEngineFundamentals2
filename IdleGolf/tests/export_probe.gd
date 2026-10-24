extends SceneTree
## External test driver: never included in shipping exports.
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	var edition := args[1]
	var state = root.get_node("GameState")
	check(OS.get_user_data_dir().begins_with(OS.get_environment("APPDATA").replace("\\", "/")), "isolated user data")
	check(not OS.is_debug_build(), "release template")
	check(OS.has_feature(edition), "export feature tag")
	check(state.IS_DEMO_BUILD == (edition == "demo"), "edition selection")
	check(state.SAVE_PATH == ("user://idle_golf_demo_v0_1.cfg" if edition == "demo" else "user://idle_golf_full.cfg"), "stable edition save path")
	check(state.is_demo_locked(state.balls.homing_ball) == (edition == "demo"), "ball content gate")
	check(state.is_demo_locked(state.courses.course2) == (edition == "demo"), "course content gate")
	ProjectSettings.set_setting("game/debug_tools", true)
	check(not state.BuildProfile.debug_tools_enabled(), "release ignores debug opt-in")
	var camera = load("res://DebugCamera.gd").new()
	root.add_child(camera)
	var f1 := InputEventKey.new()
	f1.pressed = true
	f1.keycode = KEY_F1
	camera._unhandled_input(f1)
	check(not camera._active and not camera.is_processing_unhandled_input(), "F1 cannot enable release camera")
	camera.free()
	match mode:
		"inspect":
			check(is_equal_approx(state.money, float(args[2])), "expected saved money: " + str(state.money))
		"commit_recovery":
			check(is_equal_approx(state.money, float(args[2])), "recovered money before committing")
			check(state.save(), "recovered progress committed before normal launch")
		"paid":
			state.money = 9876.5
			state.balls.homing_ball.owned = true
			state.equipped_ball = "homing_ball"
			state.courses.course2.owned = true
			state.equipped_course = "course2"
			check(state.save(), "paid progress saved")
		"verify_paid":
			check(state.money == 9876.5 and state.balls.homing_ball.owned and state.equipped_ball == "homing_ball", "demo run preserves full ball and balance")
			check(state.courses.course2.owned and state.equipped_course == "course2", "demo run preserves full course")
		"reset":
			check(state.full_reset(), "reset full progress")
		"ui_prepare":
			state.window_mode = "windowed"
			state.window_size = "1280x720"
			state.music_muted = true
			state.sfx_muted = true
			state.has_clicked_help_button = true
			check(state.save(), "prepare isolated UI fixture")
	print("EXPORT_PROBE mode=%s edition=%s result=%s save=%s" % [mode, edition, "FAIL" if failed else "PASS", OS.get_user_data_dir()])
	quit(1 if failed else 0)
