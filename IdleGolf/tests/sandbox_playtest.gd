extends Node
## External full-game testing controls, excluded from shipping resources.
const CASH := 1.0e15
const MEDALS := 1000000.0
var state: Node
var game: Node
var keep_funds := true
var automatic := true
var elapsed := 0.0
var panel: PanelContainer
var body: VBoxContainer
var note: Label
var upgrade_choice: OptionButton
var upgrade_value: SpinBox
var level_value: SpinBox
var selectors: Dictionary = {}
var original_health: Dictionary = {}
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	state = get_tree().root.get_node("GameState")
	# Refuse to run cheats unless both the launcher and its private save directory
	# are present. Opening this script accidentally cannot modify normal progress.
	if OS.get_environment("IDLE_GOLF_SANDBOX_TEST") != "1" or state.IS_DEMO_BUILD or not ProjectSettings.globalize_path(state.SAVE_PATH).contains("IdleGolfSandboxPlaytest"):
		get_tree().quit(1)
		return
	state.window_mode = "windowed"
	state.window_size = "1600x900"
	state.has_clicked_help_button = true
	for catalog in [state.balls, state.golfers, state.courses]:
		for id in catalog:
			catalog[id].owned = true
	_set_level(maxi(30, state.level))
	_refill()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	get_tree().current_scene = self
	# Test balances are deliberately much larger than the normal starting HUD.
	game.money_label.add_theme_font_size_override("font_size", 20)
	game.medals_label.add_theme_font_size_override("font_size", 32)
	for target in get_tree().get_nodes_in_group("destructibles"):
		original_health[target] = target.hits_required
	_build_controls()
	if not OS.get_environment("IDLE_GOLF_SANDBOX_CHECK").is_empty():
		await _verify(OS.get_environment("IDLE_GOLF_SANDBOX_CHECK"))

func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	elapsed += delta
	if elapsed >= .5:
		elapsed = 0.0
		if keep_funds:
			_refill()
		for kind in selectors:
			var choice: OptionButton = selectors[kind]
			choice.select(state.get(kind).keys().find(state.get("equipped_" + kind.trim_suffix("s"))))
	# Leave the shop and settings fully accessible; controls return on closing.
	panel.visible = not is_instance_valid(game._shop_layer) and not game._settings_panel.visible
	if is_instance_valid(game._shop_instance):
		game._shop_instance.medals_label.add_theme_font_size_override("font_size", 32)

func _refill() -> void:
	if state.money < CASH:
		state.money = CASH
		state.money_changed.emit(state.money)
	if state.medals < MEDALS:
		state.medals = MEDALS
		state.medals_changed.emit(state.medals)

func _set_level(value: int) -> void:
	state.level = clampi(value, 30, 1000)
	state.xp = 0.0
	state.xp_to_next_level = 100.0 * pow(1.4, state.level - 1)
	state.xp_changed.emit(state.xp, state.xp_to_next_level)
	if is_instance_valid(game):
		game.level_label.text = "Level %d" % state.level

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _toggle(parent: Node, text: String, initial: bool, action: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = initial
	parent.add_child(toggle)
	toggle.toggled.connect(action)

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	game.add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(350, 115)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.04, .08, .12, .96)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var heading := _row(box)
	var label := Label.new()
	label.text = "FULL GAME SANDBOX - separate test saves"
	heading.add_child(label)
	_button(heading, "Show / hide controls", func(): body.visible = not body.visible; panel.reset_size())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	box.add_child(body)
	var equipment := _row(body)
	for kind in ["balls", "golfers", "courses"]:
		var choice := OptionButton.new()
		var catalog: Dictionary = state.get(kind)
		for id in catalog:
			choice.add_item(catalog[id].name)
		choice.select(catalog.keys().find(state.get("equipped_" + kind.trim_suffix("s"))))
		choice.item_selected.connect(func(index: int): _equip(kind, catalog.keys()[index]))
		equipment.add_child(choice)
		selectors[kind] = choice
	var resources := _row(body)
	_button(resources, "Refill money + medals", _refill)
	_toggle(resources, "Keep topped up", true, func(on: bool): keep_funds = on)
	level_value = SpinBox.new()
	level_value.min_value = 30
	level_value.max_value = 1000
	level_value.value = state.level
	resources.add_child(level_value)
	_button(resources, "Set player level", func(): _set_level(int(level_value.value)))
	var presets := _row(body)
	_button(presets, "Starter stats", func(): _preset(0))
	_button(presets, "Midgame stats", func(): _preset(1))
	_button(presets, "Endgame stats", func(): _preset(2))
	var upgrades := _row(body)
	upgrade_choice = OptionButton.new()
	for id in state.upgrades:
		upgrade_choice.add_item(state.upgrades[id].label)
	upgrades.add_child(upgrade_choice)
	upgrade_value = SpinBox.new()
	upgrade_value.custom_minimum_size.x = 100
	upgrades.add_child(upgrade_value)
	upgrade_choice.item_selected.connect(func(_index: int): _refresh_upgrade())
	_button(upgrades, "Set upgrade level", func():
		_set_upgrade(state.upgrades.keys()[upgrade_choice.selected], int(upgrade_value.value))
		note.text = "Upgrade set. Airborne shots retain their launch stats.")
	_refresh_upgrade()
	var actions := _row(body)
	_button(actions, "Swing", func(): game.golfer.play_swing())
	_toggle(actions, "Auto swings", true, _set_automatic)
	_toggle(actions, "One-hit targets", false, _one_hit)
	_button(actions, "Save test progress", func(): note.text = "Test progress saved." if state.save() else "Save failed. See the game notice.")
	note = Label.new()
	note.text = "Everything unlocked. Pick stats, equipment and a course to start testing."
	body.add_child(note)

func _equip(kind: String, id: String) -> void:
	state.set("equipped_" + kind.trim_suffix("s"), id)
	if kind == "golfers":
		state.golfer_changed.emit()
	elif kind == "courses":
		state.course_changed.emit()
	note.text = "Selected " + state.get(kind)[id].name + "."

func _upgrade_limit(id: String) -> int:
	# Keep exponential-price HUD values representable; authored caps still apply.
	return int(state.upgrades[id].get("max_level", 1500 if id == "ball_speed" else 200))

func _set_upgrade(id: String, value: int) -> void:
	state.upgrades[id].level = clampi(value, 0, _upgrade_limit(id))
	state.money_changed.emit(state.money)
	state.medals_changed.emit(state.medals)
	if automatic:
		game.shot_timer.wait_time = 5.0 / state.get_fire_rate()

func _refresh_upgrade() -> void:
	var id: String = state.upgrades.keys()[upgrade_choice.selected]
	upgrade_value.max_value = _upgrade_limit(id)
	upgrade_value.value = state.upgrades[id].level

func _preset(index: int) -> void:
	for id in state.upgrades:
		state.upgrades[id].level = 0
	for id in state.level_bonuses:
		state.level_bonuses[id] = 0.0
	if index > 0:
		_set_upgrade("ball_speed", 200 if index == 1 else 800)
		_set_upgrade("fire_rate", 30 if index == 1 else 60)
		_set_upgrade("consistency", 40 if index == 1 else 95)
		_set_upgrade("money_mult", 20)
		_set_upgrade("xp_mult", 20)
		_set_upgrade("consistency_mult", 5 if index == 1 else 10)
	state.money_changed.emit(state.money)
	state.medals_changed.emit(state.medals)
	_refresh_upgrade()
	note.text = ["Starter", "Midgame", "Endgame"][index] + " stats applied. Adjust aim and loft for your target."

func _set_automatic(on: bool) -> void:
	automatic = on
	game.golfer.cancel_swing()
	if on:
		game.shot_timer.wait_time = 5.0 / state.get_fire_rate()
		game.shot_timer.start()
	else:
		game.shot_timer.stop()

func _one_hit(on: bool) -> void:
	for target in original_health:
		if is_instance_valid(target):
			target.hits_required = 1 if on else original_health[target]
			target._hits_taken = 0
	note.text = "One-hit targets %s. Completion still requires hitting the final target." % ("enabled" if on else "disabled")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _verify(mode: String) -> void:
	_set_automatic(false)
	_check(ProjectSettings.globalize_path(state.SAVE_PATH).contains(".verification-profile"), "isolated verification save")
	for catalog in [state.balls, state.golfers, state.courses]:
		for id in catalog:
			_check(catalog[id].owned, "unlocked " + id)
	_check(state.money >= CASH and state.medals >= MEDALS and state.level >= 30, "no resource grind")
	if mode == "reload":
		_check(state.equipped_course == "course3" and state.equipped_golfer == "golfer2" and state.equipped_ball == "wrecking", "equipment survives restart")
		_check(state.upgrades.ball_speed.level == 800 and state.upgrades.multi_ball.level == 3 and state.level == 45, "stats survive restart")
		_check(state.completed_courses.course3 and state.completed_course_count() == 1, "earned completion survives restart")
	else:
		_check(state.completed_course_count() == 0, "unlocking does not grant completion")
		var records: float = state.lifetime_money
		state.money = 0
		state.medals = 0
		_refill()
		_check(state.money == CASH and state.medals == MEDALS and state.lifetime_money == records, "refills do not fabricate earnings records")
		_check(state.try_purchase("multi_ball"), "normal purchases work")
		_preset(1)
		_check(state.upgrades.ball_speed.level == 200, "midgame preset")
		_preset(0)
		_check(state.upgrades.ball_speed.level == 0 and state.upgrades.multi_ball.level == 0, "starter preset")
		_preset(2)
		_set_upgrade("multi_ball", 999)
		_check(state.upgrades.multi_ball.level == 3, "authored upgrade cap")
		_set_level(45)
		_equip("golfers", "golfer2")
		_equip("balls", "wrecking")
		_equip("courses", "course3")
		var active_targets: Array = get_tree().get_nodes_in_group("destructibles").filter(func(t): return t.can_process())
		_check(active_targets.size() == 2, "Beach has its two original destructible objects")
		_one_hit(true)
		for target in original_health:
			_check(target.hits_required == 1, "one-hit target")
		var final_target: Node = active_targets.filter(func(t): return t.is_final_target)[0]
		_check(final_target.target_name == "Cargo Ship", "Beach completion uses cargo ship")
		final_target._take_hit(state.capture_shot_context())
		_check(state.completed_courses.course3 and state.completed_course_count() == 1, "one hit earns real completion")
		_one_hit(false)
		for target in original_health:
			_check(target.hits_required == original_health[target], "authored health restored")
		game.golfer.play_swing()
		for i in 45:
			await get_tree().process_frame
		_check(not get_tree().get_nodes_in_group("balls").is_empty(), "real swing launches balls")
		_check(state.save(), "save sandbox progress")
	print("SANDBOX_TESTS mode=%s checks=%d failures=%d" % [mode, checks, failures])
	game.free()
	get_tree().root.get_node("AudioManager").cleanup_audio()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
