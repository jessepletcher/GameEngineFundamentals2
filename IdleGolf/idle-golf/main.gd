extends Node3D
const RewardRules = preload("res://RewardRules.gd")

const Ball = preload("res://scenes/Ball.tscn")

@onready var shot_timer: Timer = $ShotTimer
@onready var tee_position: Marker3D = $TeePosition  # place this in your scene at tee location
@onready var money_label: Label = $CanvasLayer/LeftVBox/Money/MoneyLabel
@onready var golfer = $Golfer
@onready var shop = $CanvasLayer
@onready var aim_slider: HSlider = $CanvasLayer/AimSlider
@onready var level1_sprites = $Level1
@onready var level1_flags = $Level1Flags
@onready var level2_sprites = $Level2
@onready var level2_flags = $Level2Flags
@onready var level3_sprites = $Level3
@onready var level3_flags = $Level3Flags
@onready var open_shop_button: Button = $CanvasLayer/OpenShopButton
@onready var xp_progress: ProgressBar = $CanvasLayer/LeftVBox/XPBar/XPProgress
@onready var level_label: Label = $CanvasLayer/LeftVBox/XPBar/LevelLabel
@onready var retire_button: Button = $CanvasLayer/LeftVBox/LeftMenu/TopBar/RetireButton
@onready var retire_dialog = $CanvasLayer/RetireDialog
@onready var retire_info_label: Label = $CanvasLayer/RetireDialog/VBoxContainer/RetireInfoLabel
@onready var confirm_retire: Button = $CanvasLayer/RetireDialog/VBoxContainer/ConfirmRetireButton
@onready var cancel_retire: Button = $CanvasLayer/RetireDialog/VBoxContainer/CancelRetireButton
@onready var medals_label: Label = $CanvasLayer/LeftVBox/Medals/MedalsLabel
@onready var shot_control = $CanvasLayer/ShotControl
@onready var reset_button: Button = $CanvasLayer/ResetButton
@onready var reset_dialog = $CanvasLayer/ResetDialog
@onready var reset_info_label: Label = $CanvasLayer/ResetDialog/VBoxContainer/Label
@onready var confirm_reset: Button = $CanvasLayer/ResetDialog/VBoxContainer/ConfirmResetButton
@onready var cancel_reset: Button = $CanvasLayer/ResetDialog/VBoxContainer/CancelResetButton

const SHOT_INTERVAL := 5.0
const BALL_SPEED := 100
const ANGLE_SPREAD := 70.0
const BASE_SPEED := 10.0
const BASE_INTERVAL := 5.0
const BASE_SPREAD := 8.0
const FloatingText = preload("res://scenes/FloatingText.tscn")

var _floating_texts: Array = []
var _text_queue: Array = []
var _queue_processing: bool = false
var _queue_batch_remaining: int = -1
const TEXT_QUEUE_INTERVAL := 0.15
const MAX_INDIVIDUAL_TEXTS := 4  # show this many individually, then batch the rest
const HIDE_WITH_UI_GROUP := "hide_with_ui"
var _settings_panel: PanelContainer
var _help_panel: PanelContainer
var _help_page_label: Label
var _help_content: VBoxContainer
var _help_scroll: ScrollContainer
var _help_page_index := 0
var _help_pages: Array = []
var _help_button: TextureButton
var _help_button_base_scale := Vector2.ONE
var _help_wiggle_tween: Tween
var _help_wiggle_timer: Timer
var _ui_hidden := false
var _spawning_disabled := false
const DISPLAY_MODE_FULLSCREEN := "fullscreen"
const DISPLAY_MODE_WINDOWED := "windowed"
const DISPLAY_MODE_ORDER := [DISPLAY_MODE_FULLSCREEN, DISPLAY_MODE_WINDOWED]
const WINDOWED_RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

# hole-out combo
var _combo_count: int = 0
var _combo_timer: Timer
var _combo_banner: Control
var _combo_banner_tween: Tween
const COMBO_RESET_DELAY := 4.0

# money label animation
var _displayed_money: float = 0.0
var _money_count_tween: Tween
var _money_pulse_tween: Tween
var _money_label_base_color: Color = Color(0.082, 0.502, 0.098)
const MONEY_COUNT_UP_COLOR := Color(1.0, 0.95, 0.4)

# Market Ball: persistent values live in GameState; nodes are presentation only.
var _market_flags := {}  # stable course/flag key -> current scene flag
var _market_labels := {}  # flag node -> Label3D showing invested amount
var _market_label_displayed := {}  # flag node -> displayed counter value
var _market_label_color_tweens := {}  # flag node -> color pulse tween
var _market_label_hit_tweens := {}  # flag node -> scale/rotation impact tween
var _market_label_hit_scale := {}  # flag node -> active impact scale multiplier
var _market_label_hit_rotation := {}  # flag node -> active impact z rotation

# Golden Flag
var _golden_flag: Node3D = null
var _golden_timer: Timer
const GOLDEN_FLAG_INTERVAL_MIN := 20.0
const GOLDEN_FLAG_INTERVAL_MAX := 40.0

var _course_data := {
	"course1": {"sprites": null, "flags": null},
	"course2": {"sprites": null, "flags": null},
	"course3": {"sprites": null, "flags": null},
}
var _course_revision := 0

func _get_active_flags() -> Node3D:
	return _course_data[GameState.equipped_course]["flags"]

func _process(delta: float) -> void:
	GameState.market.grow(delta)
	for key in GameState.market.pots:
		_update_market_label(_market_flags.get(key))
	if retire_dialog.visible:
		_update_retire_preview()

func _market_key(flag: Node3D) -> String:
	# Authored course/flag names are save identities, independent of instance IDs.
	for course in _course_data:
		if flag.get_parent() == _course_data[course].flags:
			return course + "/" + str(flag.name)
	return ""

func _restore_market_labels() -> void:
	for key in GameState.market.pots:
		var flag = _market_flags.get(key)
		if not is_instance_valid(flag) or not flag.can_process():
			# Removed/renamed targets or a sanitized course must not strand money.
			_cashout_all_investments()
			return
	for key in GameState.market.pots:
		_update_market_label(_market_flags[key])

func _set_ui_hidden(hidden: bool) -> void:
	_ui_hidden = hidden
	$CanvasLayer.visible = not hidden
	if _shop_layer and is_instance_valid(_shop_layer):
		_shop_layer.visible = not hidden
	for node in get_tree().get_nodes_in_group(HIDE_WITH_UI_GROUP):
		_set_ui_node_visible(node, not hidden)
	for flag in _market_labels:
		if is_instance_valid(_market_labels[flag]):
			_set_ui_node_visible(_market_labels[flag], not hidden)
	for text in _floating_texts:
		if is_instance_valid(text):
			_set_ui_node_visible(text, not hidden)

func _register_hide_with_ui(node: Node) -> void:
	node.add_to_group(HIDE_WITH_UI_GROUP)
	_set_ui_node_visible(node, not _ui_hidden)

func _set_ui_node_visible(node: Node, visible: bool) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = visible
	elif node is Node3D:
		(node as Node3D).visible = visible
	elif node is CanvasLayer:
		(node as CanvasLayer).visible = visible

func _set_spawning_disabled(disabled: bool) -> void:
	_spawning_disabled = disabled
	if golfer and is_instance_valid(golfer):
		if golfer.has_method("set_spawn_disabled"):
			golfer.set_spawn_disabled(disabled)
		else:
			golfer.visible = not disabled
	if disabled:
		shot_timer.stop()
	else:
		shot_timer.wait_time = BASE_INTERVAL / GameState.get_fire_rate()
		shot_timer.start()

func _switch_course(cashout: bool = true) -> void:
	golfer.cancel_swing()
	_course_revision += 1
	# Course switches end outgoing shots immediately. Removing group membership
	# and collisions now also protects the frame before queue_free is processed.
	for ball in get_tree().get_nodes_in_group("shots"):
		if ball.has_method("cancel_shot"):
			ball.cancel_shot()
	# cash out any market investments before switching
	if cashout:
		_cashout_all_investments()
	# deactivate golden flag on course switch
	if _golden_flag and is_instance_valid(_golden_flag):
		_golden_flag.deactivate_golden()
		_golden_flag = null
	if _golden_timer:
		_start_golden_timer()
	for key in _course_data:
		var show = key == GameState.equipped_course
		for branch in [_course_data[key]["sprites"], _course_data[key]["flags"]]:
			branch.visible = show
			# Children inherit this state: scripts, animations and bound tweens
			# pause, and CollisionObject3D's REMOVE mode leaves the physics world.
			branch.process_mode = Node.PROCESS_MODE_INHERIT if show else Node.PROCESS_MODE_DISABLED
	_show_all_yardage()

func _scene_timer(seconds: float) -> Timer:
	# Delayed gameplay/UI work belongs to this scene. Free pending timers with
	# it on quit or reload, instead of retaining awaiting SceneTreeTimer states.
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	timer.timeout.connect(timer.queue_free)
	timer.start(seconds)
	return timer

func _ready() -> void:
	_apply_saved_runtime_settings()
	_course_data["course1"]["sprites"] = level1_sprites
	_course_data["course1"]["flags"] = level1_flags
	_course_data["course2"]["sprites"] = level2_sprites
	_course_data["course2"]["flags"] = level2_flags
	_course_data["course3"]["sprites"] = level3_sprites
	_course_data["course3"]["flags"] = level3_flags
	for course in _course_data:
		for flag in _course_data[course].flags.get_children():
			_market_flags[_market_key(flag)] = flag
	_switch_course(false)
	GameState.course_changed.connect(_switch_course)
	_displayed_money = GameState.money
	money_label.text = GameState.format_number(GameState.money)
	_money_label_base_color = money_label.get_theme_color("font_color")
	level_label.text = "Level %d" % GameState.level
	xp_progress.max_value = GameState.xp_to_next_level
	xp_progress.value = GameState.xp
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.money_changed.connect(_on_money_changed)
	golfer.swung.connect(_on_golfer_swung)
	open_shop_button.pressed.connect(_on_open_shop_pressed)
	shot_timer.timeout.connect(_on_ShotTimer_timeout)
	shot_timer.wait_time = BASE_INTERVAL / GameState.get_fire_rate()
	shot_timer.start()
	retire_button.pressed.connect(_on_retire_pressed)
	confirm_retire.pressed.connect(_on_confirm_retire)
	cancel_retire.pressed.connect(_on_cancel_retire)
	_setup_retire_dialog_style()
	retire_dialog.visible = false
	GameState.medals_changed.connect(_on_medals_changed)
	medals_label.text = GameState.format_number(GameState.medals)

	# auto-save every 15 seconds
	var save_timer = Timer.new()
	save_timer.wait_time = 15.0
	save_timer.autostart = true
	save_timer.timeout.connect(GameState.save)
	add_child(save_timer)

	# reset button
	reset_button.visible = false  # hidden, moved to settings menu

	# music
	AudioManager.play_music($Music.stream)

	# nature ambience loop
	var ambience_stream = load("res://u_vr5icvkppa-nature-ambience-323729.mp3")
	AudioManager.play_ambience(ambience_stream, 20.0)
	confirm_reset.pressed.connect(_on_confirm_reset)
	cancel_reset.pressed.connect(_on_cancel_reset)
	_setup_reset_dialog_style()
	reset_dialog.visible = false

	# settings menu
	_setup_settings_menu()
	var completion_ui := preload("res://CompletionUI.gd").new()
	completion_ui.name = "CompletionUI"
	$CanvasLayer.add_child(completion_ui)

	# connect destructibles
	for obj in get_tree().get_nodes_in_group("destructibles"):
		obj.destroyed.connect(_on_destructible_destroyed.bind(obj))

	# connect golden flag signals on all courses' flags
	for key in _course_data:
		for flag in _course_data[key]["flags"].get_children():
			flag.golden_hit.connect(_on_golden_flag_hit)

	# golden flag timer
	_golden_timer = Timer.new()
	_golden_timer.one_shot = true
	_golden_timer.timeout.connect(_spawn_golden_flag)
	add_child(_golden_timer)
	_start_golden_timer()

	_show_all_yardage()
	_setup_combo_banner()
	_restore_market_labels()

func _show_all_yardage() -> void:
	for obj in get_tree().get_nodes_in_group("destructibles"):
		if is_instance_valid(obj) and obj.can_process():
			obj.show_yardage()

func _on_destructible_destroyed(reward: float, earned_xp: float, source: Node3D) -> void:
	# Signals can still run on disabled nodes, so verify the source as well.
	if not is_instance_valid(source) or not source.can_process():
		return
	GameState.credit_reward({"money": reward, "xp": earned_xp})
	var course_id: String = GameState.equipped_course
	if source.is_final_target and not source._is_alive and source._hits_taken >= source.hits_required:
		if _course_data[course_id].sprites.is_ancestor_of(source):
			GameState.record_course_completion(course_id, source.target_id)
	_text_queue.append({"money": reward, "yards": 0.0, "flag_hit": false, "direct_hit": true})
	if not _queue_processing:
		_process_text_queue()
	_show_target_destroyed_banner()

func _on_xp_changed(current_xp: float, required_xp: float) -> void:
	xp_progress.max_value = required_xp
	xp_progress.value = current_xp

func _on_confirm_retire() -> void:
	retire_dialog.visible = false
	if GameState.retire():
		get_tree().reload_current_scene()
	else:
		level_label.text = "Level %d" % GameState.level
		_restore_market_labels()

func _on_cancel_retire() -> void:
	retire_dialog.visible = false

func _on_medals_changed(amount: float) -> void:
	medals_label.text = " " + GameState.format_number(amount)

func _on_retire_pressed() -> void:
	_update_retire_preview()
	retire_dialog.visible = true

func _update_retire_preview() -> void:
	var medals = GameState.get_medal_reward()
	retire_info_label.text = "You will earn %s Medals!\n\nMarket investments cash out into this run before retirement.\nRetiring resets run money and cash upgrades. Levels, unlocks and course completion stay." % GameState.format_number(medals)

func _on_leveled_up(new_level: int, stat_boosted: String) -> void:
	level_label.text = "Level %d" % new_level
	_show_level_up_popup(new_level, stat_boosted)
	_show_stat_up_text(GameState.upgrades[stat_boosted]["label"])

func _show_level_up_popup(new_level: int, stat: String) -> void:
	var label = Label.new()
	label.text = "LEVEL UP! %d\n+5%% %s" % [new_level, GameState.upgrades[stat]["label"]]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$CanvasLayer.add_child(label)
	_register_hide_with_ui(label)
	label.position = Vector2(get_viewport().size.x / 2 - 100, get_viewport().size.y / 2)
	
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 100, 1.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)

func _show_stat_up_text(stat_label: String) -> void:
	var label := Label.new()
	label.text = "%s Up" % stat_label
	label.add_theme_font_override("font", load("res://balatro.otf"))
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	label.add_theme_constant_override("outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(260, 42)
	$CanvasLayer.add_child(label)
	_register_hide_with_ui(label)
	label.position = Vector2(get_viewport().size.x / 2.0 - label.size.x / 2.0, get_viewport().size.y / 2.0 + 78.0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tween.chain().tween_callback(label.queue_free)

var _shop_instance: Control = null
var _shop_layer: CanvasLayer = null
var _transitioning := false
const TRANSITION_DURATION := 0.4

func _on_open_shop_pressed() -> void:
	GameState.save()
	if _shop_instance or _transitioning:
		return
	AudioManager.play_sfx("bell")
	_transitioning = true
	AudioManager.set_shop_open(true)

	var screen_w = get_viewport().get_visible_rect().size.x

	_shop_layer = CanvasLayer.new()
	_shop_layer.layer = 10
	add_child(_shop_layer)

	var shop_scene = load("res://Shop.tscn")
	_shop_instance = shop_scene.instantiate()
	_shop_layer.add_child(_shop_instance)
	_shop_instance.shop_closed.connect(_on_shop_close_requested)

	# shop starts offscreen right
	_shop_layer.offset = Vector2(screen_w, 0)

	var tween = create_tween().set_parallel(true)
	# slide main UI left
	tween.tween_property($CanvasLayer, "offset", Vector2(-screen_w, 0), TRANSITION_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# slide shop in from right
	tween.tween_property(_shop_layer, "offset", Vector2.ZERO, TRANSITION_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(func():
		_transitioning = false
	)

func _on_shop_close_requested() -> void:
	if _transitioning:
		return
	_transitioning = true
	var screen_w = get_viewport().get_visible_rect().size.x

	var tween = create_tween().set_parallel(true)
	# slide shop out to the right
	tween.tween_property(_shop_layer, "offset", Vector2(screen_w, 0), TRANSITION_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	# slide main UI back from left
	tween.tween_property($CanvasLayer, "offset", Vector2.ZERO, TRANSITION_DURATION).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(_on_shop_closed)

func _on_shop_closed() -> void:
	if _shop_layer:
		_shop_layer.queue_free()
		_shop_layer = null
		_shop_instance = null
	_transitioning = false
	AudioManager.set_shop_open(false)
	# reload golfer sprite in case player switched golfer
	golfer._load_golfer_sprite()
	_show_all_yardage()

func _on_golfer_swung() -> void:
	if _spawning_disabled:
		return
	_hit_ball()


func _on_money_changed(new_amount: float) -> void:
	if _money_count_tween and _money_count_tween.is_valid():
		_money_count_tween.kill()
	var gained := new_amount > _displayed_money
	_money_count_tween = create_tween()
	_money_count_tween.tween_method(_set_displayed_money, _displayed_money, new_amount, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if gained:
		_pulse_money_label()

func _set_displayed_money(v: float) -> void:
	_displayed_money = v
	money_label.text = GameState.format_number(v)

func _pulse_money_label() -> void:
	if _money_pulse_tween and _money_pulse_tween.is_valid():
		_money_pulse_tween.kill()
	money_label.pivot_offset = money_label.size / 2.0
	money_label.scale = Vector2(1.18, 1.18)
	money_label.add_theme_color_override("font_color", MONEY_COUNT_UP_COLOR)
	_money_pulse_tween = create_tween().set_parallel(true)
	_money_pulse_tween.tween_property(money_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_money_pulse_tween.tween_method(
		func(c: Color): money_label.add_theme_color_override("font_color", c),
		MONEY_COUNT_UP_COLOR,
		_money_label_base_color,
		0.3
	)

func _on_ShotTimer_timeout() -> void:
	if _spawning_disabled:
		return
	shot_timer.wait_time = BASE_INTERVAL / GameState.get_fire_rate()
	golfer.play_swing()


func _hit_ball() -> void:
	if _spawning_disabled:
		return
	AudioManager.play_sfx("hit")
	var context := GameState.capture_shot_context(_course_revision)
	var modifier = shot_control.get_launch_modifier()
	var ball_count: int = context.ball_count
	var multi_spread_step: float = context.multi_spread
	var consistency_mult := float(context.ball_data.get("consistency_mult", 1.0))
	var shot_spread: float = BASE_SPREAD / (context.consistency * consistency_mult)
	var shared_spread_degrees := randf_range(-shot_spread, shot_spread)
	var shot_balls: Array[RigidBody3D] = []
	for i in ball_count:
		var ball = Ball.instantiate()
		ball.shot_context = context
		ball._speed = BASE_SPEED * context.ball_speed
		ball._spread = 0.0
		var fan_offset_degrees := 0.0
		if i > 0:
			var fan_step := int((i + 1) / 2)
			var fan_side := -1.0 if i % 2 == 1 else 1.0
			fan_offset_degrees = fan_side * float(fan_step) * multi_spread_step
		ball._aim = -aim_slider.value + ((shared_spread_degrees + fan_offset_degrees) / 50.0)
		ball._launch_modifier = modifier
		ball.position = tee_position.global_position
		add_child(ball)
		for other_ball in shot_balls:
			if is_instance_valid(other_ball):
				ball.add_collision_exception_with(other_ball)
				other_ball.add_collision_exception_with(ball)
		shot_balls.append(ball)
		ball.landed.connect(_on_ball_landed.bind(ball))
		ball.exploded.connect(_on_ball_exploded)
		if ball._is_whiff:
			_on_ball_whiffed()

func _is_shot_current(ball: RigidBody3D) -> bool:
	return is_instance_valid(ball) and not ball._is_fake and ball.is_shot_active() and ball.shot_context.course_revision == _course_revision

func _on_ball_landed(yards: float, ball: RigidBody3D) -> void:
	if not _is_shot_current(ball) or ball._is_fake or ball._landing_paid:
		return
	ball._landing_paid = true
	var context: Dictionary = ball.shot_context
	var payout_multiplier: float = ball._payout_multiplier

	var best_bonus = 0.0
	var direct_hit = false
	var hit_flag: Node3D = null
	for flag in _get_active_flags().get_children():
		var result = flag.check_hit(ball.global_position, context, payout_multiplier)
		if result[0] > best_bonus:
			best_bonus = result[0]
		if result[1]:
			direct_hit = true
			hit_flag = flag

	if best_bonus > 0.0:
		AudioManager.play_sfx("flag")
	var reward := RewardRules.landing(context, yards, best_bonus, direct_hit, payout_multiplier)
	var is_market = context.ball_data.get("is_market", false)

	if direct_hit:
		_register_direct_hit()
	else:
		_register_miss()

	if is_market and direct_hit and hit_flag:
		var deposit := GameState.market.deposit(_market_key(hit_flag), reward)
		var pot_add: float = deposit.money
		_update_market_label(hit_flag, true)
		_text_queue.append({"money": pot_add, "yards": yards, "flag_hit": true, "direct_hit": true, "invested": true})
	else:
		# Any landing that does not make a Market deposit cashes out the pots.
		var cashout = _cashout_all_investments()
		GameState.credit_reward(reward)
		_text_queue.append({"money": reward.money + cashout, "yards": yards, "flag_hit": best_bonus > 0.0, "direct_hit": direct_hit, "cashout": cashout})
	if not _queue_processing:
		_process_text_queue()

	if yards > 500.0 and is_instance_valid(ball):
		ball.queue_free()
		return

	var is_pinball = context.ball_data.get("is_pinball", false)
	if is_pinball and direct_hit and hit_flag and is_instance_valid(ball):
		_pinball_chain(ball, hit_flag)
	elif direct_hit and is_instance_valid(ball):
		ball.queue_free()
	else:
		# Godot disconnects this target-bound callable if a course switch frees
		# the ball first; a lambda would retain an invalid captured object.
		_scene_timer(3.0).timeout.connect(ball.queue_free)


func _pinball_chain(ball: RigidBody3D, first_flag: Node3D) -> void:
	if not _is_shot_current(ball):
		return
	ball.freeze = true
	var remaining_flags: Array = []
	for flag in _get_active_flags().get_children():
		if flag != first_flag:
			remaining_flags.append(flag)
	remaining_flags.sort_custom(func(a, b):
		return a.global_position.distance_to(first_flag.global_position) < b.global_position.distance_to(first_flag.global_position)
	)
	_advance_pinball_chain(ball, remaining_flags, 0)

func _advance_pinball_chain(ball: RigidBody3D, flags: Array, index: int) -> void:
	if not _is_shot_current(ball):
		return
	if index >= flags.size() or not is_instance_valid(flags[index]) or not flags[index].can_process():
		ball.queue_free()
		return
	var flag: Node3D = flags[index]
	# A ball-bound tween and a signal callback can be safely freed on a course
	# switch. No suspended coroutine retains the cancelled shot's resources.
	var fly_tween = ball.create_tween()
	var travel_dist = ball.global_position.distance_to(flag.global_position)
	var fly_time = clampf(travel_dist * 0.003, 0.1, 0.4)
	var from_pos := ball.global_position
	var mid_point = (ball.global_position + flag.global_position) / 2.0
	mid_point.y += travel_dist * 0.15
	_spawn_pinball_beam(from_pos, flag.global_position, fly_time * 2.0)
	fly_tween.tween_property(ball, "global_position", mid_point, fly_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fly_tween.tween_property(ball, "global_position", flag.global_position, fly_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly_tween.finished.connect(_on_pinball_arrived.bind(ball, flags, index))

func _on_pinball_arrived(ball: RigidBody3D, flags: Array, index: int) -> void:
	if not _is_shot_current(ball) or not is_instance_valid(flags[index]) or not flags[index].can_process():
		return
	var flag: Node3D = flags[index]
	var context: Dictionary = ball.shot_context
	# cash this flag hit
	AudioManager.play_sfx("flag_stick")
	flag._wiggle()
	_spawn_pinball_bumper_flash(flag.global_position)
	_register_direct_hit()
	var flag_bonus := RewardRules.flag_bonus(flag.global_position.z, flag.distance_mult)
	var reward := RewardRules.pinball(context, flag_bonus)
	GameState.credit_reward(reward)

	var pin_yards = flag.global_position.distance_to(tee_position.global_position) * 1.094
	_text_queue.append({"money": reward.money, "yards": pin_yards, "flag_hit": true, "direct_hit": true})
	_spawn_pinball_score_pop(flag.global_position, reward.money)
	if not _queue_processing:
		_process_text_queue()

	# check golden flag
	if flag._is_golden:
		flag.golden_hit.emit(flag, flag_bonus, context, 1.0)
		flag.deactivate_golden()
	_advance_pinball_chain(ball, flags, index + 1)

func _cashout_all_investments() -> float:
	for key in GameState.market.pots:
		var flag = _market_flags.get(key)
		if is_instance_valid(flag):
			_spawn_cashout_particles_from_flag(flag, GameState.market.pots[key].money)
			_remove_market_label(flag)
	return GameState.cashout_market().money

func _update_market_label(flag: Node3D, pulse: bool = false) -> void:
	if not is_instance_valid(flag):
		return
	var amount: float = GameState.market.pots.get(_market_key(flag), {"money": 0.0}).money
	if flag not in _market_labels:
		var label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = _money_label_base_color
		label.no_depth_test = true
		label.render_priority = 10
		var f = load("res://balatro.otf")
		if f:
			label.font = f
		flag.add_child(label)
		_register_hide_with_ui(label)
		_market_labels[flag] = label
		_market_label_displayed[flag] = amount
		_market_label_hit_scale[flag] = 1.0
		_market_label_hit_rotation[flag] = 0.0
		label.text = "$" + GameState.format_number(amount)
	elif amount > float(_market_label_displayed.get(flag, 0.0)):
		_set_market_label_amount(amount, flag)
		if pulse:
			_pulse_market_label_color(flag)
			_pop_market_label_hit(flag)
		else:
			var shimmer := 0.45 + sin(Time.get_ticks_msec() * 0.009) * 0.25
			var label: Label3D = _market_labels[flag]
			label.modulate = _money_label_base_color.lerp(MONEY_COUNT_UP_COLOR, shimmer)
	else:
		_set_market_label_amount(amount, flag)
	# scale based on camera distance so it's readable from far away
	var cam = get_viewport().get_camera_3d()
	var distance = flag.global_position.distance_to(cam.global_position)
	var scale_factor = pow(distance * 0.05, 1.0) * 1.5
	var amount_scale = 1.0 + clamp(log(max(amount, 1.0)) / log(10.0) * 0.055, 0.0, 0.45)
	var hit_scale = float(_market_label_hit_scale.get(flag, 1.0))
	var label: Label3D = _market_labels[flag]
	label.scale = Vector3.ONE * scale_factor * amount_scale * hit_scale
	label.rotation.z = float(_market_label_hit_rotation.get(flag, 0.0))
	# position above the flag sprite
	label.position = Vector3(0, scale_factor * 1.5 * amount_scale, 0)

func _set_market_label_amount(value: float, flag: Node3D) -> void:
	if not is_instance_valid(flag) or flag not in _market_labels:
		return
	var label: Label3D = _market_labels[flag]
	if not is_instance_valid(label):
		return
	_market_label_displayed[flag] = value
	label.text = "$" + GameState.format_number(value)

func _pulse_market_label_color(flag: Node3D) -> void:
	if flag not in _market_labels or not is_instance_valid(_market_labels[flag]):
		return
	if flag in _market_label_color_tweens and _market_label_color_tweens[flag] and _market_label_color_tweens[flag].is_valid():
		_market_label_color_tweens[flag].kill()
	var label: Label3D = _market_labels[flag]
	label.modulate = MONEY_COUNT_UP_COLOR
	var tween := create_tween()
	_market_label_color_tweens[flag] = tween
	tween.tween_property(label, "modulate", _money_label_base_color, 0.22)

func _pop_market_label_hit(flag: Node3D) -> void:
	if flag not in _market_labels or not is_instance_valid(_market_labels[flag]):
		return
	if flag in _market_label_hit_tweens and _market_label_hit_tweens[flag] and _market_label_hit_tweens[flag].is_valid():
		_market_label_hit_tweens[flag].kill()
	var rotation_kick := deg_to_rad(randf_range(-24.0, 24.0))
	_market_label_hit_scale[flag] = 1.55
	_market_label_hit_rotation[flag] = rotation_kick
	var tween := create_tween().set_parallel(true)
	_market_label_hit_tweens[flag] = tween
	tween.tween_method(_set_market_hit_scale.bind(flag), 1.55, 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_market_hit_rotation.bind(flag), rotation_kick, 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_market_hit_scale(value: float, flag: Node3D) -> void:
	if is_instance_valid(flag):
		_market_label_hit_scale[flag] = value

func _set_market_hit_rotation(value: float, flag: Node3D) -> void:
	if is_instance_valid(flag):
		_market_label_hit_rotation[flag] = value

func _remove_market_label(flag: Node3D) -> void:
	if flag in _market_label_color_tweens and _market_label_color_tweens[flag] and _market_label_color_tweens[flag].is_valid():
		_market_label_color_tweens[flag].kill()
	if flag in _market_label_hit_tweens and _market_label_hit_tweens[flag] and _market_label_hit_tweens[flag].is_valid():
		_market_label_hit_tweens[flag].kill()
	if flag in _market_labels:
		if is_instance_valid(_market_labels[flag]):
			_market_labels[flag].queue_free()
	_market_labels.erase(flag)
	_market_label_displayed.erase(flag)
	_market_label_color_tweens.erase(flag)
	_market_label_hit_tweens.erase(flag)
	_market_label_hit_scale.erase(flag)
	_market_label_hit_rotation.erase(flag)

func _start_golden_timer() -> void:
	_golden_timer.wait_time = randf_range(GOLDEN_FLAG_INTERVAL_MIN, GOLDEN_FLAG_INTERVAL_MAX)
	_golden_timer.start()

func _spawn_golden_flag() -> void:
	# deactivate any existing golden flag
	if _golden_flag and is_instance_valid(_golden_flag):
		_golden_flag.deactivate_golden()

	var flags = _get_active_flags().get_children()
	if flags.size() == 0:
		_start_golden_timer()
		return

	# pick a random flag
	_golden_flag = flags[randi() % flags.size()]
	_golden_flag.activate_golden()

func _on_golden_flag_hit(flag: Node3D, bonus: float, context: Dictionary, payout_multiplier: float) -> void:
	if not is_instance_valid(flag) or not flag.can_process() or flag.get_parent() != _get_active_flags():
		return
	if context.get("course_revision", -1) != _course_revision or context.get("course_id", "") != GameState.equipped_course:
		return
	var reward := RewardRules.golden(context, bonus, payout_multiplier)
	GameState.credit_reward(reward)
	_golden_flag = null

	# show golden cashout text
	_text_queue.append({"money": reward.money, "yards": 0.0, "flag_hit": true, "direct_hit": true, "golden": true})
	if not _queue_processing:
		_process_text_queue()

	AudioManager.play_sfx("casino")
	_spawn_money_rain()
	_show_gold_flag_banner()

	# start timer for next golden flag
	_start_golden_timer()

func _get_dynamic_lifetime() -> float:
	# base 1.0s, shrinks as queue + active texts grow, minimum 0.3s
	var pressure = _text_queue.size() + _floating_texts.size()
	return clampf(1.0 - pressure * 0.1, 0.3, 1.0)

func _process_text_queue() -> void:
	# A scene-owned timer callback is cancelled with this scene. Suspending an
	# await here left a timeout StringName behind when quitting during payouts.
	if _text_queue.is_empty():
		_queue_processing = false
		_queue_batch_remaining = -1
		return
	_queue_processing = true
	if _queue_batch_remaining < 0 and _text_queue.size() > MAX_INDIVIDUAL_TEXTS:
		_queue_batch_remaining = MAX_INDIVIDUAL_TEXTS
	if _queue_batch_remaining == 0:
		var total_money := 0.0
		var hit_count := _text_queue.size()
		var any_flag := false
		var any_direct := false
		for data in _text_queue:
			total_money += data["money"]
			if data.get("direct_hit", false):
				any_direct = true
			elif data.get("flag_hit", false):
				any_flag = true
		_text_queue.clear()
		_spawn_summary_text(total_money, hit_count, any_flag, any_direct)
		_queue_batch_remaining = -1
	else:
		var data = _text_queue.pop_front()
		_spawn_floating_text(data["money"], data["yards"], data.get("flag_hit", false), data.get("direct_hit", false), data.get("invested", false), data.get("cashout", 0.0), data.get("golden", false))
		if _queue_batch_remaining > 0:
			_queue_batch_remaining -= 1
	_scene_timer(TEXT_QUEUE_INTERVAL).timeout.connect(_process_text_queue)


func _push_existing_texts_up() -> void:
	if _floating_texts.size() >= 10:
		var oldest = _floating_texts[0]
		if is_instance_valid(oldest):
			oldest.force_fade()

	for existing in _floating_texts:
		if is_instance_valid(existing):
			var shift_tween = create_tween()
			shift_tween.tween_property(existing, "global_position:y", existing.global_position.y + .1, 0.15)

func _spawn_floating_text(money: float, yards: float, flag_hit: bool = false, direct_hit: bool = false, invested: bool = false, cashout: float = 0.0, golden: bool = false) -> void:
	_push_existing_texts_up()

	var text = FloatingText.instantiate()
	add_child(text)
	_register_hide_with_ui(text)
	text.global_position = golfer.global_position + Vector3(0, 1.5, 0)
	if golden:
		text.setup_summary("GOLDEN FLAG! +$%s" % GameState.format_number(money), _get_dynamic_lifetime(), Color(1.0, 0.84, 0.0))
	elif invested:
		text.setup_summary("INVESTED $%s" % GameState.format_number(money), _get_dynamic_lifetime(), Color.CYAN)
	elif cashout > 0.0:
		text.setup_summary("CASHOUT! +$%s" % GameState.format_number(money), _get_dynamic_lifetime(), Color.GREEN)
	else:
		text.setup(money, yards, flag_hit, direct_hit, _get_dynamic_lifetime())
	_floating_texts.append(text)
	text.tree_exited.connect(func(): _floating_texts.erase(text))

func _spawn_summary_text(total_money: float, hit_count: int, any_flag: bool, any_direct: bool) -> void:
	_push_existing_texts_up()

	var text = FloatingText.instantiate()
	add_child(text)
	_register_hide_with_ui(text)
	text.global_position = golfer.global_position + Vector3(0, 1.5, 0)
	var summary = "+$%s (%d more hits)" % [GameState.format_number(total_money), hit_count]
	text.setup_summary(summary, _get_dynamic_lifetime())
	_floating_texts.append(text)
	text.tree_exited.connect(func(): _floating_texts.erase(text))


func _on_ball_exploded(fragments: Array) -> void:
	for frag in fragments:
		frag.landed.connect(_on_ball_landed.bind(frag))

func _on_ball_whiffed() -> void:
	var label = Label.new()
	label.text = "!!!"
	label.add_theme_color_override("font_color", Color.RED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$CanvasLayer.add_child(label)
	var golfer_screen_pos = get_viewport().get_camera_3d().unproject_position(golfer.global_position)
	label.position = golfer_screen_pos + Vector2(-40, -400)
	label.add_theme_font_size_override("font_size", 64)

	# use a custom font (load a .ttf or .otf file)
	var font = load("res://balatro.otf")
	label.add_theme_font_override("font", font)

	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 50, 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

func _on_reset_pressed() -> void:
	reset_dialog.move_to_front()
	reset_dialog.visible = true

func _on_confirm_reset() -> void:
	if not GameState.full_reset():
		reset_dialog.visible = false
		return
	get_tree().reload_current_scene()

func _on_cancel_reset() -> void:
	reset_dialog.visible = false

func _apply_saved_runtime_settings() -> void:
	GameState.window_mode = _normalize_window_mode(GameState.window_mode)
	if _get_window_size_index(GameState.window_size) == -1:
		GameState.window_size = _format_window_size(WINDOWED_RESOLUTIONS[1])
	AudioManager.set_sfx_muted(GameState.sfx_muted)
	AudioManager.set_music_muted(GameState.music_muted)
	AudioManager.set_shop_open(false)
	_apply_display_settings()

func _apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if GameState.vsync_enabled else DisplayServer.VSYNC_DISABLED)
	match _normalize_window_mode(GameState.window_mode):
		DISPLAY_MODE_FULLSCREEN:
			_apply_fullscreen()
		_:
			var window_size := _get_window_size(GameState.window_size)
			_apply_windowed_size(window_size)

func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	window.borderless = false
	window.mode = Window.MODE_FULLSCREEN

func _center_window(window_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var screen_position := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	get_window().position = screen_position + (screen_size - window_size) / 2

func _apply_windowed_size(window_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.borderless = false
	window.unresizable = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_finish_windowed_resize.call_deferred(window_size)
	_scene_timer(0.20).timeout.connect(_finish_windowed_resize.bind(window_size))

func _finish_windowed_resize(window_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.borderless = false
	window.unresizable = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(window_size)
	window.size = window_size
	_center_window(window_size)

func _normalize_window_mode(mode: String) -> String:
	if DISPLAY_MODE_ORDER.has(mode):
		return mode
	return DISPLAY_MODE_FULLSCREEN

func _next_window_mode(mode: String) -> String:
	var current := DISPLAY_MODE_ORDER.find(_normalize_window_mode(mode))
	return DISPLAY_MODE_ORDER[(current + 1) % DISPLAY_MODE_ORDER.size()]

func _window_mode_label(mode: String) -> String:
	match _normalize_window_mode(mode):
		DISPLAY_MODE_WINDOWED:
			return "Windowed"
		_:
			return "Fullscreen"

func _format_window_size(window_size: Vector2i) -> String:
	return "%dx%d" % [window_size.x, window_size.y]

func _get_window_size(size_key: String) -> Vector2i:
	var index := _get_window_size_index(size_key)
	if index == -1:
		return WINDOWED_RESOLUTIONS[1]
	return WINDOWED_RESOLUTIONS[index]

func _get_window_size_index(size_key: String) -> int:
	for i in range(WINDOWED_RESOLUTIONS.size()):
		if _format_window_size(WINDOWED_RESOLUTIONS[i]) == size_key:
			return i
	return -1

func _next_window_size(size_key: String) -> String:
	var index := _get_window_size_index(size_key)
	if index == -1:
		index = 0
	else:
		index = (index + 1) % WINDOWED_RESOLUTIONS.size()
	return _format_window_size(WINDOWED_RESOLUTIONS[index])

func _make_settings_button(text: String, font: Font) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(250, 34)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _make_help_text_button(text: String, font: Font, min_size: Vector2 = Vector2(96, 34)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _make_guide_button_style(bg_color: Color) -> StyleBoxFlat:
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = bg_color
	button_style.border_color = Color(0.32, 0.22, 0.16)
	button_style.border_width_left = 4
	button_style.border_width_top = 4
	button_style.border_width_right = 4
	button_style.border_width_bottom = 4
	button_style.expand_margin_top = 4.0
	button_style.expand_margin_bottom = 4.0
	return button_style

func _apply_guide_button_style(button: Button, font: Font, text: String = "") -> void:
	if not text.is_empty():
		button.text = text
	button.custom_minimum_size = Vector2(250, 36)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.70))
	button.add_theme_stylebox_override("normal", _make_guide_button_style(Color(0.49, 0.35, 0.26)))
	button.add_theme_stylebox_override("hover", _make_guide_button_style(Color(0.58, 0.42, 0.30)))
	button.add_theme_stylebox_override("pressed", _make_guide_button_style(Color(0.36, 0.24, 0.17)))

func _make_guide_panel_style() -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.08, 0.07, 0.96)
	panel_style.border_color = Color(0.45, 0.30, 0.24)
	panel_style.border_width_left = 4
	panel_style.border_width_top = 4
	panel_style.border_width_right = 4
	panel_style.border_width_bottom = 4
	panel_style.content_margin_left = 18
	panel_style.content_margin_top = 14
	panel_style.content_margin_right = 18
	panel_style.content_margin_bottom = 14
	return panel_style

func _setup_retire_dialog_style() -> void:
	var font: Font = load("res://balatro.otf")
	retire_dialog.anchor_left = 0.5
	retire_dialog.anchor_right = 0.5
	retire_dialog.anchor_top = 0.5
	retire_dialog.anchor_bottom = 0.5
	retire_dialog.offset_left = -360
	retire_dialog.offset_right = 360
	retire_dialog.offset_top = -135
	retire_dialog.offset_bottom = 135
	retire_dialog.add_theme_stylebox_override("panel", _make_guide_panel_style())
	retire_dialog.z_index = 20

	var vbox := retire_dialog.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", 8)

	retire_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retire_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retire_info_label.add_theme_font_override("font", font)
	retire_info_label.add_theme_font_size_override("font_size", 22)
	retire_info_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	retire_info_label.add_theme_constant_override("outline_size", 0)
	retire_info_label.custom_minimum_size = Vector2(650, 98)

	for button in [confirm_retire, cancel_retire]:
		button.custom_minimum_size = Vector2(250, 36)
		button.add_theme_font_override("font", font)
		button.add_theme_font_size_override("font_size", 18)

func _setup_reset_dialog_style() -> void:
	var font: Font = load("res://balatro.otf")
	reset_dialog.anchor_left = 0.5
	reset_dialog.anchor_right = 0.5
	reset_dialog.anchor_top = 0.5
	reset_dialog.anchor_bottom = 0.5
	reset_dialog.offset_left = -360
	reset_dialog.offset_right = 360
	reset_dialog.offset_top = -125
	reset_dialog.offset_bottom = 125
	reset_dialog.add_theme_stylebox_override("panel", _make_guide_panel_style())
	reset_dialog.z_index = 20
	reset_dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := reset_dialog.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox:
		vbox.anchor_left = 0.0
		vbox.anchor_right = 1.0
		vbox.anchor_top = 0.0
		vbox.anchor_bottom = 1.0
		vbox.offset_left = 18
		vbox.offset_right = -18
		vbox.offset_top = 14
		vbox.offset_bottom = -14
		vbox.add_theme_constant_override("separation", 8)

	reset_info_label.text = "Are you sure?\nThis will erase ALL progress."
	reset_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reset_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reset_info_label.add_theme_font_override("font", font)
	reset_info_label.add_theme_font_size_override("font_size", 22)
	reset_info_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	reset_info_label.add_theme_constant_override("outline_size", 0)
	reset_info_label.custom_minimum_size = Vector2(650, 84)

	_apply_guide_button_style(confirm_reset, font, "Confirm Reset")
	_apply_guide_button_style(cancel_reset, font, "Cancel")

func _setup_settings_menu() -> void:
	var font = load("res://balatro.otf")

	# settings button - top right
	var settings_btn = TextureButton.new()
	settings_btn.texture_normal = load("res://SettingsButton.png")
	settings_btn.stretch_mode = TextureButton.STRETCH_KEEP
	settings_btn.ignore_texture_size = false
	settings_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	settings_btn.anchor_left = 1.0
	settings_btn.anchor_right = 1.0
	settings_btn.anchor_top = 0.0
	settings_btn.anchor_bottom = 0.0
	var tex_size = settings_btn.texture_normal.get_size() if settings_btn.texture_normal else Vector2(32, 32)
	settings_btn.offset_right = -10
	settings_btn.offset_left = -10 - tex_size.x
	settings_btn.offset_top = 10
	settings_btn.offset_bottom = 10 + tex_size.y
	$CanvasLayer.add_child(settings_btn)
	_setup_help_menu(font, settings_btn)

	# settings panel
	_settings_panel = PanelContainer.new()
	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -150
	_settings_panel.offset_right = 150
	_settings_panel.offset_top = -175
	_settings_panel.offset_bottom = 175
	_settings_panel.visible = false
	_settings_panel.z_index = 20
	_settings_panel.add_theme_stylebox_override("panel", _make_guide_panel_style())
	$CanvasLayer.add_child(_settings_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_settings_panel.add_child(vbox)

	var window_mode_btn := _make_settings_button("", font)
	vbox.add_child(window_mode_btn)

	var resolution_btn := _make_settings_button("", font)
	vbox.add_child(resolution_btn)

	var vsync_btn := _make_settings_button("", font)
	vbox.add_child(vsync_btn)

	var sfx_btn := _make_settings_button("", font)
	vbox.add_child(sfx_btn)

	var music_btn := _make_settings_button("", font)
	vbox.add_child(music_btn)

	var reset_btn := _make_settings_button("Reset Game", font)
	vbox.add_child(reset_btn)

	var exit_btn := _make_settings_button("Exit Game", font)
	vbox.add_child(exit_btn)

	var refresh_buttons := func() -> void:
		window_mode_btn.text = "Window: %s" % _window_mode_label(GameState.window_mode)
		resolution_btn.text = "Resolution: %s" % GameState.window_size
		vsync_btn.text = "VSync: %s" % ("On" if GameState.vsync_enabled else "Off")
		sfx_btn.text = "SFX: %s" % ("Off" if AudioManager.sfx_muted else "On")
		music_btn.text = "Music: %s" % ("Off" if AudioManager.music_muted else "On")

	refresh_buttons.call()

	settings_btn.pressed.connect(func():
		_settings_panel.visible = !_settings_panel.visible
		if _settings_panel.visible:
			if _help_panel:
				_help_panel.visible = false
			refresh_buttons.call()
	)

	window_mode_btn.pressed.connect(func():
		GameState.window_mode = _next_window_mode(GameState.window_mode)
		_apply_display_settings()
		refresh_buttons.call()
		GameState.save()
	)

	resolution_btn.pressed.connect(func():
		GameState.window_size = _next_window_size(GameState.window_size)
		GameState.window_mode = DISPLAY_MODE_WINDOWED
		_apply_display_settings()
		refresh_buttons.call()
		GameState.save()
	)

	vsync_btn.pressed.connect(func():
		GameState.vsync_enabled = not GameState.vsync_enabled
		_apply_display_settings()
		refresh_buttons.call()
		GameState.save()
	)

	sfx_btn.pressed.connect(func():
		AudioManager.toggle_sfx_mute()
		GameState.sfx_muted = AudioManager.sfx_muted
		refresh_buttons.call()
		GameState.save()
	)

	music_btn.pressed.connect(func():
		AudioManager.toggle_music_mute()
		GameState.music_muted = AudioManager.music_muted
		refresh_buttons.call()
		GameState.save()
	)

	exit_btn.pressed.connect(GameState.request_quit)

	reset_btn.pressed.connect(func():
		_settings_panel.visible = false
		_on_reset_pressed()
	)

func _setup_help_menu(font: Font, settings_btn: TextureButton) -> void:
	_help_pages = _build_help_pages()

	var help_btn := TextureButton.new()
	help_btn.texture_normal = load("res://HelpButton.png")
	help_btn.stretch_mode = TextureButton.STRETCH_SCALE
	help_btn.ignore_texture_size = true
	help_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	help_btn.anchor_left = 1.0
	help_btn.anchor_right = 1.0
	help_btn.anchor_top = 0.0
	help_btn.anchor_bottom = 0.0
	var tex_size := help_btn.texture_normal.get_size() if help_btn.texture_normal else Vector2(32, 32)
	var help_button_scale := 5.0
	var help_button_size := tex_size * help_button_scale
	help_btn.custom_minimum_size = help_button_size
	help_btn.offset_left = settings_btn.offset_right - help_button_size.x
	help_btn.offset_right = settings_btn.offset_right
	help_btn.offset_top = settings_btn.offset_bottom + 8.0
	help_btn.offset_bottom = help_btn.offset_top + help_button_size.y
	$CanvasLayer.add_child(help_btn)
	_help_button = help_btn
	_help_button_base_scale = help_btn.scale

	_help_panel = PanelContainer.new()
	_help_panel.anchor_left = 0.5
	_help_panel.anchor_right = 0.5
	_help_panel.anchor_top = 0.5
	_help_panel.anchor_bottom = 0.5
	_help_panel.offset_left = -360
	_help_panel.offset_right = 360
	_help_panel.offset_top = -255
	_help_panel.offset_bottom = 255
	_help_panel.visible = false
	_help_panel.z_index = 20
	_help_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(_help_panel)

	_help_panel.add_theme_stylebox_override("panel", _make_guide_panel_style())

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_help_panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "PLAYER GUIDE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.70))
	title.add_theme_constant_override("outline_size", 0)
	header.add_child(title)

	var close_btn := _make_help_text_button("Close", font, Vector2(94, 34))
	header.add_child(close_btn)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)

	var prev_btn := _make_help_text_button("<", font, Vector2(52, 34))
	nav.add_child(prev_btn)

	_help_page_label = Label.new()
	_help_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_page_label.add_theme_font_override("font", font)
	_help_page_label.add_theme_font_size_override("font_size", 20)
	_help_page_label.add_theme_color_override("font_color", Color.WHITE)
	_help_page_label.add_theme_constant_override("outline_size", 0)
	nav.add_child(_help_page_label)

	var next_btn := _make_help_text_button(">", font, Vector2(52, 34))
	nav.add_child(next_btn)

	_help_scroll = ScrollContainer.new()
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help_scroll.custom_minimum_size = Vector2(650, 368)
	root.add_child(_help_scroll)

	_help_content = VBoxContainer.new()
	_help_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_content.add_theme_constant_override("separation", 10)
	_help_scroll.add_child(_help_content)

	close_btn.pressed.connect(func():
		_help_panel.visible = false
	)
	prev_btn.pressed.connect(func():
		_change_help_page(-1)
	)
	next_btn.pressed.connect(func():
		_change_help_page(1)
	)
	help_btn.pressed.connect(func():
		_mark_help_button_clicked()
		_help_panel.visible = !_help_panel.visible
		if _help_panel.visible:
			if _settings_panel:
				_settings_panel.visible = false
			_show_help_page(_help_page_index)
	)

	_show_help_page(0)
	_setup_help_button_wiggle()

func _setup_help_button_wiggle() -> void:
	if GameState.has_clicked_help_button or not is_instance_valid(_help_button):
		return
	_help_wiggle_timer = Timer.new()
	_help_wiggle_timer.wait_time = 4.5
	_help_wiggle_timer.one_shot = false
	_help_wiggle_timer.autostart = true
	_help_wiggle_timer.timeout.connect(_play_help_button_wiggle)
	add_child(_help_wiggle_timer)
	_scene_timer(0.7).timeout.connect(_play_help_button_wiggle)

func _mark_help_button_clicked() -> void:
	if GameState.has_clicked_help_button:
		return
	GameState.has_clicked_help_button = true
	GameState.save()
	_stop_help_button_wiggle()

func _stop_help_button_wiggle() -> void:
	if is_instance_valid(_help_wiggle_timer):
		_help_wiggle_timer.stop()
		_help_wiggle_timer.queue_free()
	_help_wiggle_timer = null
	if _help_wiggle_tween and _help_wiggle_tween.is_valid():
		_help_wiggle_tween.kill()
	_help_wiggle_tween = null
	if is_instance_valid(_help_button):
		_help_button.rotation_degrees = 0.0
		_help_button.scale = _help_button_base_scale

func _play_help_button_wiggle() -> void:
	if GameState.has_clicked_help_button or not is_instance_valid(_help_button):
		_stop_help_button_wiggle()
		return
	if _help_wiggle_tween and _help_wiggle_tween.is_valid() and _help_wiggle_tween.is_running():
		return
	_help_button.pivot_offset = _help_button.size * 0.5
	_help_button.rotation_degrees = 0.0
	_help_wiggle_tween = create_tween()
	_help_wiggle_tween.tween_property(_help_button, "rotation_degrees", -7.0, 0.06)
	_help_wiggle_tween.tween_property(_help_button, "rotation_degrees", 7.0, 0.09)
	_help_wiggle_tween.tween_property(_help_button, "rotation_degrees", -5.0, 0.08)
	_help_wiggle_tween.tween_property(_help_button, "rotation_degrees", 4.0, 0.07)
	_help_wiggle_tween.tween_property(_help_button, "rotation_degrees", 0.0, 0.08)
	_help_wiggle_tween.finished.connect(func():
		_help_wiggle_tween = null
	)

func _change_help_page(direction: int) -> void:
	if _help_pages.is_empty():
		return
	_help_page_index = (_help_page_index + direction + _help_pages.size()) % _help_pages.size()
	_show_help_page(_help_page_index)

func _show_help_page(page_index: int) -> void:
	if _help_pages.is_empty() or not _help_content:
		return
	_help_page_index = clampi(page_index, 0, _help_pages.size() - 1)
	for child in _help_content.get_children():
		child.queue_free()

	var page: Dictionary = _help_pages[_help_page_index]
	_help_page_label.text = "%s  %d/%d" % [str(page.get("title", "")), _help_page_index + 1, _help_pages.size()]
	var font: Font = load("res://balatro.otf")
	for section in page.get("sections", []):
		var section_data: Dictionary = section
		_add_help_section(str(section_data.get("category", "")), str(section_data.get("text", "")), font)

	if _help_scroll:
		_help_scroll.set_deferred("scroll_vertical", 0)

func _add_help_section(category_name: String, body: String, font: Font) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 2)
	_help_content.add_child(section)

	var category := Label.new()
	category.text = category_name
	category.add_theme_font_override("font", font)
	category.add_theme_font_size_override("font_size", 22)
	category.add_theme_color_override("font_color", Color(1.0, 0.78, 0.34))
	category.add_theme_constant_override("outline_size", 0)
	section.add_child(category)

	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("font", font)
	text.add_theme_font_size_override("font_size", 16)
	text.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	text.add_theme_constant_override("outline_size", 0)
	section.add_child(text)

func _build_help_pages() -> Array:
	var ball_rewards := PackedStringArray()
	for data in GameState.balls.values():
		ball_rewards.append("%s: %sx money, %sx flag bonus, %sx destructible money." % [data.name, data.money_mult, data.get("flag_mult", 1.0), data.get("destruct_mult", 1.0)])
	return [
		{
			"title": "Basics",
			"sections": [
				{"category": "Core Loop", "text": "Your golfer swings automatically. Each shot earns money from distance, flags, direct hits, and course objects."},
				{"category": "Aiming", "text": "The aim slider curves shots left or right. Center is straight, and stronger stats make shots travel farther."},
				{"category": "Spin Control", "text": "The bottom-right spin control changes the shot shape. Drag left or right to bend the ball in flight. Drag up for a higher launch or down for a flatter launch. Heavy side spin reduces forward distance."},
				{"category": "Money", "text": "Money buys run upgrades. Bigger shots, flag bonuses, special balls, and golfer passives all stack into the payout."},
				{"category": "XP And Level", "text": "Earning money also gives XP. Leveling grants stat bonuses and unlocks more shop items."},
			],
		},
		{
			"title": "Upgrades",
			"sections": [
				{"category": "Cash Upgrades", "text": "Most cash upgrades rise by 8% per level. Ball Speed uses a gentler late-game price curve; the shop shows the current price.\nBall Speed: total speed = (1 + level x 0.04) x level bonus x golfer speed.\nFire Rate: total fire rate = (1 + level x 0.03) x level bonus x golfer fire rate. Swing timer = 5 / total fire rate.\nMoney Multiplier: total money = (1 + level x 0.09) x level bonus x golfer money x ball money.\nXP Multiplier: total XP = (1 + level x 0.09) x level bonus. XP gained = final money x 0.1 x total XP.\nConsistency: total consistency = (0.5 + level x 0.1) x level bonus x medal bonus. Higher consistency tightens spread and lowers whiffs."},
				{"category": "Medal Upgrades", "text": "Flat Distance: +1 flat distance per level, added directly to horizontal shot speed. Cost starts at 8 medals and rises by 4 each level.\nMulti Ball: +1 ball per level. Ball count = 1 + level. Costs 100, 175, then 250 medals. Max level 3.\nMulti Ball Spread: reduces fan spread by 2 degrees per level. Spread = max(8, 20 - level x 2). Cost starts at 20 medals and rises by 10 each level. Max level 6.\nConsistency Mult: +50% consistency per level. Medal multiplier = 1 + level x 0.5. Cost starts at 25 medals and rises by 25 each level. Max level 10."},
				{"category": "How To Earn Medals?", "text": "Retire a strong run to turn progress into medals. The first medal payout scales with lifetime money. After that, medals are earned when the current run beats your best run money, with bigger improvements paying more and a soft cap toward 250 medals."},
				{"category": "Retirement", "text": "Retiring resets run money and cash upgrades. Levels, unlocks, balls, golfers, courses, and medal upgrades stay."},
			],
		},
		{
			"title": "Shop",
			"sections": [
				{"category": "Golf Balls", "text": "Balls change the rules of the shot. Standard is reliable, Pin Seeker boosts flags, and Firework splits into scoring fragments."},
				{"category": "Golfers", "text": "Golfers change passive stats. Standard Golfer is balanced, Shop Keep earns extra money, and Lion Trees adds money plus distance."},
				{"category": "Courses", "text": "Courses change the playable layout and targets. Switching courses clears balls still in play; rewards already earned are kept. Big Piney is the first course."},
				{"category": "Changing Equipment", "text": "Balls keep the equipment and upgrade bonuses they had at launch. Changing equipment or buying upgrades affects new shots."},
				{"category": "Market Investments", "text": "Market pots and streaks are saved. Deposit streak bonuses stop growing at 10x. Investments grow slowly, sharing a $5-per-second interest limit. Growth resumes while playing, with no growth while the game is closed. Switching courses cashes out your pots. Retirement cashes them out before calculating medals and run records."},
			],
		},
		{
			"title": "Bonus Money",
			"sections": [
				{"category": "Flags", "text": "Landing near a flag adds bonus money. A direct hit pays more and can trigger special ball effects."},
				{"category": "Golden Flags", "text": "A direct hit on a golden flag adds 50x its accuracy-adjusted flag bonus, including your ball's flag bonus and money multipliers. This is separate from the ordinary direct-hit payout."},
				{"category": "Ball Reward Multipliers", "text": "\n".join(ball_rewards)},
				{"category": "Hole-Out Combo", "text": "Back-to-back direct flag hits build a combo banner and celebrate clean accuracy."},
				{"category": "Destructibles", "text": "Some course objects take repeated hits, pay out when destroyed, and return after a respawn timer."},
				{"category": "Bonus Money", "text": "Base shot payout = yards^2 x 0.0002 + 5. Flag bonuses are added to that base, direct hits multiply the result by 2.5, and money multipliers apply last."},
			],
		},
	]

# ---------- hole-out combo ----------

func _setup_combo_banner() -> void:
	_combo_banner = Control.new()
	_combo_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_banner.anchor_left = 0.5
	_combo_banner.anchor_right = 0.5
	_combo_banner.anchor_top = 0.0
	_combo_banner.anchor_bottom = 0.0
	_combo_banner.offset_left = 0
	_combo_banner.offset_right = 0
	_combo_banner.offset_top = 160
	_combo_banner.offset_bottom = 160
	_combo_banner.modulate.a = 0.0
	$CanvasLayer.add_child(_combo_banner)
	_register_hide_with_ui(_combo_banner)

	_combo_timer = Timer.new()
	_combo_timer.one_shot = true
	_combo_timer.wait_time = COMBO_RESET_DELAY
	_combo_timer.timeout.connect(_on_combo_timeout)
	add_child(_combo_timer)

func _register_direct_hit() -> void:
	_combo_count += 1
	if _combo_count >= 2:
		_show_combo_banner(_combo_count)
	_combo_timer.start()

func _register_miss() -> void:
	_combo_count = 0
	_combo_timer.stop()

func _on_combo_timeout() -> void:
	_combo_count = 0

func _combo_color(combo: int) -> Color:
	if combo < 3:
		return Color.WHITE
	elif combo < 5:
		return Color(1.0, 0.95, 0.3)
	elif combo < 8:
		return Color(1.0, 0.55, 0.1)
	elif combo < 12:
		return Color(1.0, 0.25, 0.25)
	else:
		return Color(0.4, 0.9, 1.0)

func _show_combo_banner(combo: int) -> void:
	for child in _combo_banner.get_children():
		child.queue_free()

	var text := "HOLE OUT COMBO x%d" % combo
	var font: Font = load("res://balatro.otf")
	var font_size := int(64 + min(combo - 2, 10) * 4)
	var color := _combo_color(combo)

	var widths: Array = []
	var total_width := 0.0
	for c in text:
		var w: float = font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total_width += w

	var x := -total_width / 2.0
	for i in text.length():
		var c := text[i]
		var lbl := Label.new()
		lbl.text = c
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", color)
		lbl.position = Vector2(x, 0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_combo_banner.add_child(lbl)
		x += widths[i]

		var bounce := create_tween()
		bounce.tween_interval(i * 0.035)
		bounce.tween_property(lbl, "position:y", -30.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bounce.tween_property(lbl, "position:y", 0.0, 0.30).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	if _combo_banner_tween and _combo_banner_tween.is_valid():
		_combo_banner_tween.kill()
	_combo_banner.modulate = Color(1, 1, 1, 1)
	_combo_banner.scale = Vector2(1.3, 1.3)
	_combo_banner_tween = create_tween()
	_combo_banner_tween.tween_property(_combo_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_banner_tween.tween_interval(1.6)
	_combo_banner_tween.tween_property(_combo_banner, "modulate:a", 0.0, 0.5)

# ---------- shot juice ----------

func _spawn_cashout_particles_from_flag(flag: Node3D, amount: float) -> void:
	if not is_instance_valid(flag):
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var dollar_tex: Texture2D = load("res://DollarBill.png")
	var coin_tex: Texture2D = load("res://GoldCoin.png")
	var start := flag.global_position + Vector3.UP * 1.0
	var end := _get_money_counter_world_target(start)
	var count := clampi(int(amount / 1000.0) + 6, 6, 18)
	for i in count:
		var sprite := Sprite3D.new()
		sprite.texture = coin_tex if i % 2 == 0 else dollar_tex
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.render_priority = 12
		sprite.pixel_size = 0.024
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.95)
		add_child(sprite)
		_register_hide_with_ui(sprite)
		var start_offset := Vector3(randf_range(-0.35, 0.35), randf_range(-0.15, 0.45), randf_range(-0.25, 0.25))
		sprite.global_position = start + start_offset
		sprite.scale = Vector3.ONE * randf_range(0.75, 1.15)
		var target := end + Vector3(randf_range(-0.35, 0.35), randf_range(-0.22, 0.22), randf_range(-0.25, 0.25))
		var control := sprite.global_position.lerp(target, 0.45) + Vector3(randf_range(-0.5, 0.5), randf_range(1.4, 2.4), randf_range(-0.35, 0.35))
		var tween := sprite.create_tween().set_parallel(true)
		var delay := i * 0.035
		tween.tween_method(_move_cashout_sprite.bind(sprite, sprite.global_position, control, target), 0.0, 1.0, 0.62).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(sprite, "scale", Vector3.ONE * 0.18, 0.62).set_delay(delay)
		tween.tween_property(sprite, "rotation:z", randf_range(-TAU * 2.0, TAU * 2.0), 0.62).set_delay(delay)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.18).set_delay(delay + 0.48)
		tween.chain().tween_callback(sprite.queue_free)

func _get_money_counter_world_target(reference_pos: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return reference_pos
	var screen_pos := money_label.get_global_rect().get_center()
	var depth: float = maxf(4.0, camera.global_position.distance_to(reference_pos))
	return camera.project_position(screen_pos, depth)

func _move_cashout_sprite(progress: float, sprite: Sprite3D, start: Vector3, control: Vector3, end: Vector3) -> void:
	if not is_instance_valid(sprite):
		return
	var a := start.lerp(control, progress)
	var b := control.lerp(end, progress)
	sprite.global_position = a.lerp(b, progress)

func _spawn_pinball_beam(from_pos: Vector3, to_pos: Vector3, lifetime: float) -> void:
	_spawn_world_beam(from_pos, to_pos, Color(0.0, 0.95, 1.0, 0.9), 0.1, lifetime + 0.25)
	_spawn_world_beam(from_pos + Vector3.UP * 0.08, to_pos + Vector3.UP * 0.08, Color(1.0, 0.05, 0.95, 0.75), 0.055, lifetime + 0.2)

func _spawn_pinball_bumper_flash(pos: Vector3) -> void:
	_spawn_world_ring(pos + Vector3.UP * 0.4, Color(0.0, 0.95, 1.0, 0.9), 0.35, 4.0, 0.32)
	_spawn_world_ring(pos + Vector3.UP * 0.45, Color(1.0, 0.05, 0.95, 0.8), 0.18, 2.8, 0.28)

func _spawn_pinball_score_pop(pos: Vector3, amount: float) -> void:
	var effect_scale := _world_effect_scale(pos)
	var label := Label3D.new()
	label.text = "+$%s" % GameState.format_number(amount)
	label.font = load("res://balatro.otf")
	label.font_size = 34
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 0
	label.no_depth_test = true
	label.modulate = Color(0.0, 1.0, 1.0)
	add_child(label)
	_register_hide_with_ui(label)
	label.global_position = pos + Vector3.UP * 1.2
	label.scale = Vector3.ONE * 0.4 * effect_scale
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.4, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.chain().tween_callback(label.queue_free)

func _spawn_world_beam(from_pos: Vector3, to_pos: Vector3, color: Color, width: float, lifetime: float) -> void:
	var length := from_pos.distance_to(to_pos)
	if length < 0.01:
		return
	var effect_scale := _world_effect_scale((from_pos + to_pos) * 0.5)
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width * effect_scale, width * effect_scale, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	beam.material_override = mat
	add_child(beam)
	beam.global_position = (from_pos + to_pos) * 0.5
	beam.global_transform.basis = Basis.looking_at((to_pos - from_pos).normalized(), Vector3.UP)
	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.tween_callback(beam.queue_free)

func _spawn_world_ring(pos: Vector3, color: Color, start_scale: float, end_scale: float, lifetime: float) -> void:
	var effect_scale := _world_effect_scale(pos)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.04
	torus.outer_radius = 0.5
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	ring.material_override = mat
	add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * start_scale * effect_scale
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * end_scale * effect_scale, lifetime)
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(ring.queue_free)

func _world_effect_scale(pos: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return 1.0
	return clamp(pos.distance_to(camera.global_position) / 35.0, 0.25, 1.0)

# ---------- gold flag effects ----------

const MONEY_RAIN_COUNT := 35
const MONEY_RAIN_DURATION := 2.0

func _spawn_money_rain() -> void:
	var dollar_tex: Texture2D = load("res://DollarBill.png")
	var coin_tex: Texture2D = load("res://GoldCoin.png")

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_register_hide_with_ui(layer)

	var spawn_interval: float = MONEY_RAIN_DURATION / float(MONEY_RAIN_COUNT)
	for i in MONEY_RAIN_COUNT:
		var spawn_at: float = i * spawn_interval
		var spawn_tween := create_tween()
		spawn_tween.tween_interval(spawn_at)
		spawn_tween.tween_callback(_spawn_money_piece.bind(layer, dollar_tex, coin_tex))

	var cleanup := create_tween()
	cleanup.tween_interval(MONEY_RAIN_DURATION + 3.5)
	cleanup.tween_callback(layer.queue_free)

func _spawn_money_piece(layer: CanvasLayer, dollar_tex: Texture2D, coin_tex: Texture2D) -> void:
	if not is_instance_valid(layer):
		return
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var screen_h: float = get_viewport().get_visible_rect().size.y

	var sprite := TextureRect.new()
	var is_coin := randf() < 0.5
	sprite.texture = coin_tex if is_coin else dollar_tex
	if is_coin:
		AudioManager.play_sfx("coin")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz: float = randf_range(48.0, 96.0)
	sprite.custom_minimum_size = Vector2(sz, sz)
	sprite.size = Vector2(sz, sz)
	sprite.pivot_offset = Vector2(sz, sz) / 2.0
	var start_x: float = randf_range(-50.0, screen_w + 50.0)
	sprite.position = Vector2(start_x, -sz - randf_range(0.0, 100.0))
	sprite.rotation = randf_range(0.0, TAU)
	layer.add_child(sprite)

	var fall_dur: float = randf_range(1.1, 1.7)
	var end_y: float = screen_h + sz + 50.0
	var drift_x: float = sprite.position.x + randf_range(-80.0, 80.0)
	var spin: float = randf_range(-TAU * 2.0, TAU * 2.0)

	var t := create_tween().set_parallel(true)
	t.tween_property(sprite, "position:y", end_y, fall_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(sprite, "position:x", drift_x, fall_dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(sprite, "rotation", sprite.rotation + spin, fall_dur)

const GOLD_SHADES := [
	Color(1.0, 0.84, 0.0),
	Color(1.0, 0.9, 0.3),
	Color(1.0, 0.95, 0.55),
	Color(1.0, 1.0, 0.75),
]

func _show_gold_flag_banner() -> void:
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var screen_h: float = get_viewport().get_visible_rect().size.y

	var banner := Control.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.position = Vector2(screen_w / 2.0, screen_h / 2.0)
	$CanvasLayer.add_child(banner)

	var text := "GOLD FLAG"
	var font: Font = load("res://balatro.otf")
	var font_size := 128

	var widths: Array = []
	var total_width := 0.0
	for c in text:
		var w: float = font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total_width += w

	var x := -total_width / 2.0
	for i in text.length():
		var c := text[i]
		var lbl := Label.new()
		lbl.text = c
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", GOLD_SHADES[0])
		lbl.position = Vector2(x, -font_size / 2.0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(lbl)
		x += widths[i]

		var letter_idx := i
		var bounce := create_tween()
		bounce.tween_interval(letter_idx * 0.06)
		bounce.tween_callback(func():
			var shade: Color = GOLD_SHADES[letter_idx % GOLD_SHADES.size()]
			lbl.add_theme_color_override("font_color", shade)
		)
		bounce.parallel().tween_property(lbl, "position:y", -font_size / 2.0 - 50.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bounce.tween_property(lbl, "position:y", -font_size / 2.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		bounce.tween_callback(func():
			lbl.add_theme_color_override("font_color", GOLD_SHADES[GOLD_SHADES.size() - 1])
		)

	banner.scale = Vector2(1.3, 1.3)
	var pop := create_tween()
	pop.tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_interval(2.0)
	pop.tween_property(banner, "modulate:a", 0.0, 0.5)
	pop.tween_callback(banner.queue_free)

# ---------- TARGET DESTROYED banner ----------

const BRACKET_TRAVEL := 220.0
const SLAM_DELAY := 0.28

func _show_target_destroyed_banner() -> void:
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var screen_h: float = get_viewport().get_visible_rect().size.y

	var banner := Control.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.position = Vector2(screen_w / 2.0, screen_h / 2.0)
	$CanvasLayer.add_child(banner)

	var text := "TARGET DESTROYED"
	var font: Font = load("res://balatro.otf")
	var font_size := 88
	var red := Color(1.0, 0.25, 0.2)

	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := 40.0
	var half_w: float = text_size.x / 2.0 + pad
	var half_h: float = text_size.y / 2.0 + pad

	# main text label, centered, hidden until slam
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", red)
	lbl.size = text_size
	lbl.position = -text_size / 2.0
	lbl.pivot_offset = text_size / 2.0
	lbl.scale = Vector2(4.0, 4.0)
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(lbl)

	AudioManager.play_sfx("beep")
	_scene_timer(0.12).timeout.connect(func(): AudioManager.play_sfx("beep"))
	# 4 corner brackets — start offscreen direction, travel inward
	var bracket_chars := ["┌", "┐", "└", "┘"]
	var corners := [
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(-half_w, half_h),
		Vector2(half_w, half_h),
	]
	var travel_dirs := [
		Vector2(-1, -1),
		Vector2(1, -1),
		Vector2(-1, 1),
		Vector2(1, 1),
	]
	for i in 4:
		var br := Label.new()
		br.text = bracket_chars[i]
		br.add_theme_font_override("font", font)
		br.add_theme_font_size_override("font_size", 96)
		br.add_theme_color_override("font_color", red)
		br.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var br_size: Vector2 = font.get_string_size(bracket_chars[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 96)
		var final_pos: Vector2 = corners[i] - br_size / 2.0
		var start_pos: Vector2 = final_pos + travel_dirs[i] * BRACKET_TRAVEL
		br.position = start_pos
		banner.add_child(br)

		var bt := create_tween()
		bt.tween_property(br, "position", final_pos, SLAM_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# slam in the text after brackets converge
	var slam := create_tween()
	slam.tween_interval(SLAM_DELAY)
	slam.tween_callback(func():
		AudioManager.play_sfx("thud")
		_screen_shake(8.0, 0.18)
	)
	slam.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slam.parallel().tween_property(lbl, "modulate:a", 1.0, 0.06)

	# hold then fade
	slam.tween_interval(1.4)
	slam.tween_property(banner, "modulate:a", 0.0, 0.4)
	slam.tween_callback(banner.queue_free)

# ---------- screen shake ----------

var _shake_tween: Tween

func _screen_shake(amount: float, duration: float) -> void:
	if _transitioning:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	var base: Vector2 = $CanvasLayer.offset
	_shake_tween = create_tween()
	var steps := 8
	var step_dur: float = duration / float(steps)
	for i in steps:
		var falloff: float = 1.0 - float(i) / float(steps)
		var jitter := Vector2(randf_range(-amount, amount), randf_range(-amount, amount)) * falloff
		_shake_tween.tween_property($CanvasLayer, "offset", base + jitter, step_dur)
	_shake_tween.tween_property($CanvasLayer, "offset", base, step_dur)
