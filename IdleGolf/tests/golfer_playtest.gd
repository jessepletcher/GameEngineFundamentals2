extends Node
## External review controls; never packed into the shipping game.
var state: Node
var game: Node
var ids: Array
var contacts := 0
var note: Label

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("IDLE_GOLF_GOLFER_TEST") != "1":
		get_tree().quit(1)
		return
	state = get_tree().root.get_node("GameState")
	state.window_mode = "windowed"
	state.window_size = "1600x900"
	state.has_clicked_help_button = true
	state.level = maxi(30, state.level)
	ids = state.golfers.keys()
	for id in ids:
		state.golfers[id].owned = true
	state.upgrades.fire_rate.level = 0
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	get_tree().current_scene = self
	game.shot_timer.stop()
	game.golfer.swung.connect(func(): contacts += 1)
	var layer := CanvasLayer.new()
	layer.layer = 20
	game.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(350, 115)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.04, .08, .12, .95)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "GOLFER REVIEW - all eight unlocked - separate test saves"
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var choice := OptionButton.new()
	for id in ids:
		choice.add_item(state.golfers[id].name)
	choice.select(ids.find(state.equipped_golfer))
	choice.item_selected.connect(func(index: int): _equip(ids[index]))
	row.add_child(choice)
	var swing := Button.new()
	swing.text = "Swing"
	swing.pressed.connect(func(): game.golfer.play_swing())
	row.add_child(swing)
	var auto := CheckButton.new()
	auto.text = "Auto swings"
	auto.toggled.connect(func(enabled: bool):
		if enabled:
			game.shot_timer.wait_time = 5.0 / state.get_fire_rate()
			game.shot_timer.start()
		else:
			game.shot_timer.stop())
	row.add_child(auto)
	var fast := CheckButton.new()
	fast.text = "Fast swings"
	fast.toggled.connect(func(enabled: bool): state.upgrades.fire_rate.level = 60 if enabled else 0)
	row.add_child(fast)
	note = Label.new()
	box.add_child(note)
	_equip(state.equipped_golfer)
	if not OS.get_environment("IDLE_GOLF_GOLFER_CHECK").is_empty():
		await _verify()

func _equip(id: String) -> void:
	state.equipped_golfer = id
	state.golfer_changed.emit()
	note.text = state.golfers[id].desc + "  Open the Shop to review portraits."

func _verify() -> void:
	var failures := 0
	if not ProjectSettings.globalize_path(state.SAVE_PATH).contains(".verification-profile") or state.IS_DEMO_BUILD:
		failures += 1
	for id in ids:
		_equip(id)
		var before := contacts
		game.golfer.play_swing()
		for i in 90:
			await get_tree().process_frame
		if contacts != before + 1 or game.golfer.sprite.frame != 0:
			failures += 1
	if not state.save() or not state.load_game() or state.equipped_golfer != ids.back():
		failures += 1
	print("GOLFER_LAUNCHER checks=10 failures=%d" % failures)
	game.free()
	get_tree().root.get_node("AudioManager").cleanup_audio()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
