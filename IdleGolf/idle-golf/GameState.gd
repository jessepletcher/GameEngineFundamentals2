extends Node

var _cursor_normal: Texture2D
var _cursor_pressed: Texture2D
var money: float = 0.0
var xp: float = 0.0
var level: int = 1
var xp_to_next_level: float = 100.0
var medals: float = 0.0
var lifetime_xp: float = 0.0  # total xp earned this run
var lifetime_money: float = 0.0  # total money earned this run
var best_run_xp: float = 0.0  # best xp from any run
var best_run_money: float = 0.0  # best money from any run
var window_mode: String = "fullscreen"
var window_size: String = "1600x900"
var vsync_enabled: bool = false
var sfx_muted: bool = false
var music_muted: bool = false
var has_clicked_help_button: bool = false
const COURSE_FINAL_TARGETS := {
	"course1": "level1_destructible3",
	"course2": "level2_pyramids",
	"course3": "level3_cargoship",
}
var completed_courses := {"course1": false, "course2": false, "course3": false}
signal completion_changed
signal course_completed(course_id: String)

const BuildProfile = preload("res://BuildProfile.gd")
const RewardRules = preload("res://RewardRules.gd")
const EconomyRules = preload("res://EconomyRules.gd")
const GolferArt = preload("res://GolferArt.gd")
const MarketLedger = preload("res://MarketLedger.gd")
var market := MarketLedger.new()
var IS_DEMO_BUILD := BuildProfile.is_demo()
const DEMO_LOCK_TEXT := "Full Game"

signal medals_changed(new_amount: float)
signal money_changed(new_amount: float)
signal leveled_up(new_level: int, stat_boosted: String)
signal xp_changed(current_xp: float, required_xp: float)
signal golfer_changed
signal course_changed

static func format_number(value: float) -> String:
	var num_str = str(int(value))
	var result = ""
	var count = 0
	for i in range(num_str.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0 and num_str[i] != "-":
			result = "," + result
		result = num_str[i] + result
		count += 1
	return result

var SAVE_PATH := BuildProfile.save_path()
const SaveStore = preload("res://SaveStore.gd")

signal save_notice_changed(message: String)
var save_notice := ""
var _save_store: SaveStore
var _save_dialog: AcceptDialog
var _quit_dialog: ConfirmationDialog

const LEVEL_REWARDS = [
	"ball_speed",
	"money_mult",
	"fire_rate",
	"consistency",
	"fire_rate",
	"money_mult",
	"ball_speed",
	"consistency",
	"fire_rate",
	"money_mult",
]


var upgrades = {
	"ball_speed":   {"level": 0, "base_cost": 10.0,  "label": "Ball Speed"},
	"fire_rate":    {"level": 0, "base_cost": 15.0,  "label": "Fire Rate"},
	"money_mult":   {"level": 0, "base_cost": 20.0,  "label": "Money Multiplier"},
	"consistency":  {"level": 0, "base_cost": 12.0,  "label": "Consistency"},
	"xp_mult":      {"level": 0, "base_cost": 20.0,  "label": "XP Multiplier"},
	"flat_distance": {"level": 0, "base_cost": 8.0, "label": "Flat Distance", "use_medals": true},
	"multi_ball": {"level": 0, "base_cost": 100.0, "label": "Multi Ball", "use_medals": true, "max_level": 3},
	"multi_ball_spread": {"level": 0, "base_cost": 20.0, "label": "Multi Ball Spread", "use_medals": true, "max_level": 6, "demo_hidden": true},
	"consistency_mult": {"level": 0, "base_cost": 25.0, "label": "Consistency Mult", "use_medals": true, "max_level": 10, "demo_hidden": true},
}

var balls = {
	"standard": {"name": "Standard Ball", "desc": "Your trusty golf ball", "medal_cost": 0.0, "owned": true, "speed_mult": 1.0, "money_mult": 1.0, "can_home": false, "trail_color": Color.WHITE, "texture": preload("res://BallIcon.png"), "flag_mult": 1.0, "unlock_level": 1},
	"homing_ball": {"name": "Homing Ball", "desc": "Homes in on nearest flag", "medal_cost": 5, "owned": false, "speed_mult": 1.0, "money_mult": 1.5, "can_home": true, "trail_color": Color.LIME_GREEN, "texture": preload("res://HomingBalllIcon.png"), "flag_mult": 1.0, "unlock_level": 5, "demo_locked": true},
	"pin_seeker": {"name": "Pin Seeker", "desc": "2x flag bonus money", "medal_cost": 25, "owned": false, "speed_mult": 1.0, "money_mult": 1.0, "can_home": false, "trail_color": Color.GOLD, "texture": preload("res://PinSeekBalllIcon.png"), "flag_mult": 2.0, "unlock_level": 15},
	"firework": {"name": "Firework Ball", "desc": "Light up the course.", "medal_cost": 60, "owned": false, "speed_mult": 1.0, "money_mult": 0.5, "can_home": false, "trail_color": Color.ORANGE_RED, "texture": preload("res://FireWorksBalllIcon.png"), "flag_mult": 1.0, "is_firework": true, "unlock_level": 30},
	"market": {"name": "Market Ball", "desc": "Make your money grow.", "medal_cost": 40, "owned": false, "speed_mult": 1.0, "money_mult": 1.0, "can_home": false, "trail_color": Color.CYAN, "texture": preload("res://BallIcon.png"), "flag_mult": 1.5, "is_market": true, "unlock_level": 20, "consistency_mult": 1.5, "demo_locked": true},
	"wrecking": {"name": "Wrecking Ball", "desc": "Built for breaking things.", "medal_cost": 30, "owned": false, "speed_mult": 1.0, "money_mult": 1.0, "can_home": false, "trail_color": Color.DARK_GRAY, "texture": preload("res://BallIcon.png"), "flag_mult": 1.0, "destruct_mult": 2.0, "unlock_level": 12, "demo_locked": true},
	"pinball": {"name": "Pin Ball", "desc": "Keep the hits coming.", "medal_cost": 50, "owned": false, "speed_mult": 1.0, "money_mult": 0.7, "can_home": false, "trail_color": Color.MAGENTA, "texture": preload("res://BallIcon.png"), "flag_mult": 1.0, "consistency_mult": 10.5, "is_pinball": true, "unlock_level": 18, "demo_locked": true},
}

var golfers = {
	"standard":    {"name": "Standard Golfer", "desc": "A reliable swing",             "medal_cost": 0,  "owned": true,  "speed_mult": 1.0, "fire_rate_mult": 1.0, "money_mult": 1.0, "spritesheet": "res://GolfSwing-Sheet.png", "h_frames": 5, "frame_size": 96, "unlock_level": 1, "texture": preload("res://StandardGolferPortrait.png"), "icon_scale": 5.0},
	"power":       {"name": "Dyson",           "desc": "Stronger shots, slower swings.", "medal_cost": 5,  "owned": false, "speed_mult": 1.15, "fire_rate_mult": 0.95, "money_mult": 1.0, "spritesheet": "res://art/golfers/DysonSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 3, "texture": GolferArt.portrait("power"), "icon_scale": 40.0 / GolferArt.PORTRAITS["power"].size.x, "demo_locked": true},
	"speedy":      {"name": "Shop Keep",       "desc": "+50% money",                   "medal_cost": 20, "owned": false, "speed_mult": 1.0, "fire_rate_mult": 1.0, "money_mult": 1.5, "spritesheet": "res://ShopKeepSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 10, "texture": preload("res://ShopKeepPortrait.png"), "icon_scale": 5.0},
	"Lion Trees":      {"name": "Lion Trees",   "desc": "Stronger shots and more money.",   "medal_cost": 50, "owned": false, "speed_mult": 1.2, "fire_rate_mult": 1.0, "money_mult": 1.25, "spritesheet": "res://LionTreesSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 25, "texture": preload("res://LionTreesPortrait.png"), "icon_scale": 5.0},
	"construction":    {"name": "Blue Collar", "desc": "Targets return sooner.", "medal_cost": 15, "owned": false, "speed_mult": 1.0, "fire_rate_mult": 1.0, "money_mult": 1.0, "respawn_mult": 0.5, "spritesheet": "res://art/golfers/BlueCollarSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 7, "texture": GolferArt.portrait("construction"), "icon_scale": 40.0 / GolferArt.PORTRAITS["construction"].size.x, "demo_locked": true},
	"golfer1": {"name": "Zoomer", "desc": "Stronger shots.", "medal_cost": 8, "owned": false, "speed_mult": 1.1, "fire_rate_mult": 1.0, "money_mult": 1.0, "spritesheet": "res://art/golfers/ZoomerSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 4, "texture": GolferArt.portrait("golfer1"), "icon_scale": 40.0 / GolferArt.PORTRAITS["golfer1"].size.x, "demo_locked": true},
	"golfer2": {"name": "Lamb", "desc": "Faster swings.", "medal_cost": 18, "owned": false, "speed_mult": 1.0, "fire_rate_mult": 1.15, "money_mult": 1.0, "spritesheet": "res://art/golfers/LambSwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 9, "texture": GolferArt.portrait("golfer2"), "icon_scale": 40.0 / GolferArt.PORTRAITS["golfer2"].size.x, "demo_locked": true},
	"golfer4": {"name": "Money Daily", "desc": "More money from each shot.", "medal_cost": 12, "owned": false, "speed_mult": 1.0, "fire_rate_mult": 1.0, "money_mult": 1.15, "spritesheet": "res://art/golfers/MoneyDailySwing.png", "h_frames": 5, "frame_size": 96, "unlock_level": 6, "texture": GolferArt.portrait("golfer4"), "icon_scale": 40.0 / GolferArt.PORTRAITS["golfer4"].size.x, "demo_locked": true},
}

var courses = {
	"course1": {"name": "Big Piney", "desc": "The classic range", "medal_cost": 0, "owned": true, "unlock_level": 1, "texture": preload("res://Course1Icon.png"), "icon_scale": 5.0},
	"course2": {"name": "Course 2", "desc": "A new challenge", "medal_cost": 10, "owned": false, "unlock_level": 8, "texture": preload("res://BallIcon.png"), "demo_locked": true},
	"course3": {"name": "Course 3", "desc": "A longer course with tighter payouts", "medal_cost": 25, "owned": false, "unlock_level": 15, "texture": preload("res://BallIcon.png"), "demo_locked": true},
}


var equipped_ball: String = "standard"
var equipped_golfer: String = "standard"
var equipped_course: String = "course1"

var level_bonuses = {
	"ball_speed": 0.0,
	"fire_rate": 0.0,
	"money_mult": 0.0,
	"consistency": 0.0,
	"xp_mult": 0.0,
}

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	load_game()

	# custom mouse cursor
	_cursor_normal = load("res://Mouse.png")
	_cursor_pressed = load("res://MousePressed.png")
	Input.set_custom_mouse_cursor(_cursor_normal)

	# global button press sound hookup
	get_tree().node_added.connect(_on_node_added)
	_connect_existing_buttons.call_deferred()

func _connect_existing_buttons() -> void:
	_connect_buttons_recursive(get_tree().root)

func _exit_tree() -> void:
	# The OS cursor keeps a texture reference beyond scene teardown unless it is
	# explicitly cleared while the rendering server is still alive.
	Input.set_custom_mouse_cursor(null)
	_cursor_normal = null
	_cursor_pressed = null

func _connect_buttons_recursive(node: Node) -> void:
	if node is BaseButton:
		if not node.pressed.is_connected(_play_button_sound):
			node.pressed.connect(_play_button_sound)
	for child in node.get_children():
		_connect_buttons_recursive(child)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		if not node.pressed.is_connected(_play_button_sound):
			node.pressed.connect(_play_button_sound)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			Input.set_custom_mouse_cursor(_cursor_pressed)
		else:
			Input.set_custom_mouse_cursor(_cursor_normal)

func _play_button_sound() -> void:
	AudioManager.play_sfx("button")
	
func get_flat_distance() -> float:
	return upgrades["flat_distance"]["level"] * 1.0

func is_demo_locked(data: Dictionary) -> bool:
	return IS_DEMO_BUILD and bool(data.get("demo_locked", false))

func get_demo_lock_text(data: Dictionary) -> String:
	return str(data.get("demo_lock_text", DEMO_LOCK_TEXT))

func is_demo_hidden_upgrade(upgrade_key: String) -> bool:
	return IS_DEMO_BUILD and upgrades.has(upgrade_key) and bool(upgrades[upgrade_key].get("demo_hidden", false))

func get_medal_reward(include_market: bool = true) -> float:
	var run_money: float = lifetime_money + (market.total().money if include_market else 0.0)
	return EconomyRules.retirement_reward(run_money, best_run_money)

func cashout_market() -> Dictionary:
	var reward := market.total()
	# Clear before emitting reward signals so callbacks cannot cash the pot twice.
	market.clear()
	if reward.money > 0.0 or reward.xp > 0.0:
		credit_reward(reward)
	return reward

func retire() -> bool:
	var previous := _build_save_config()
	cashout_market()
	var earned_medals = get_medal_reward()
	medals += earned_medals

	# update high scores if this run beat them
	best_run_xp = max(best_run_xp, lifetime_xp)
	best_run_money = max(best_run_money, lifetime_money)
	
	# reset run stats
	lifetime_xp = 0.0
	lifetime_money = 0.0
	money = 0.0
	
	# reset upgrades (keep medal upgrades)
	for key in upgrades:
		if not upgrades[key].get("use_medals", false):
			upgrades[key]["level"] = 0
	
	if not save():
		_apply_save_config(previous)
		money_changed.emit(money)
		xp_changed.emit(xp, xp_to_next_level)
		medals_changed.emit(medals)
		return false
	medals_changed.emit(medals)
	return true
	
func full_reset() -> bool:
	_ensure_save_store()
	if _save_store.prepare_reset() != OK:
		_set_save_notice(_save_store.last_error)
		return false
	# Keep the current session intact if the confirmed reset cannot be saved.
	var previous := _build_save_config()
	market.clear()
	money = 0.0
	xp = 0.0
	level = 1
	xp_to_next_level = 100.0
	medals = 0.0
	lifetime_xp = 0.0
	lifetime_money = 0.0
	best_run_xp = 0.0
	best_run_money = 0.0
	equipped_ball = "standard"
	equipped_golfer = "standard"
	equipped_course = "course1"
	has_clicked_help_button = false
	for course in COURSE_FINAL_TARGETS:
		completed_courses[course] = false

	for key in upgrades:
		upgrades[key]["level"] = 0

	for key in level_bonuses:
		level_bonuses[key] = 0.0

	for key in balls:
		balls[key]["owned"] = (key == "standard")

	for key in golfers:
		golfers[key]["owned"] = (key == "standard")

	for key in courses:
		courses[key]["owned"] = (key == "course1")

	money_changed.emit(money)
	medals_changed.emit(medals)
	xp_changed.emit(xp, xp_to_next_level)
	if not save():
		_apply_save_config(previous)
		money_changed.emit(money)
		medals_changed.emit(medals)
		xp_changed.emit(xp, xp_to_next_level)
		return false
	completion_changed.emit()
	return true

func completed_course_count() -> int:
	var count := 0
	for course in COURSE_FINAL_TARGETS:
		if completed_courses[course]:
			count += 1
	return count

func is_game_complete() -> bool:
	# Derive this from the three saved milestones, so flags cannot disagree.
	return completed_course_count() == COURSE_FINAL_TARGETS.size()

func record_course_completion(course_id: String, target_id: String) -> bool:
	if course_id != equipped_course or not COURSE_FINAL_TARGETS.has(course_id):
		return false
	if target_id != COURSE_FINAL_TARGETS[course_id] or completed_courses[course_id]:
		return false
	if not courses[course_id].owned or (IS_DEMO_BUILD and course_id != "course1"):
		return false
	completed_courses[course_id] = true
	# Keep an earned milestone in memory if disk writes fail. The normal save
	# warning, autosave retry and protected quit flow apply; don't claim it saved.
	save()
	completion_changed.emit()
	course_completed.emit(course_id)
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Notifications traverse a locked tree; defer so a save-failure dialog can
		# safely be attached before asking the player whether to retry or discard.
		request_quit.call_deferred()
	

func _ensure_save_store() -> void:
	if _save_store == null:
		_save_store = SaveStore.new(SAVE_PATH, _build_save_config())

func save() -> bool:
	_ensure_save_store()
	var err := _save_store.write_save(_build_save_config())
	if err != OK:
		_set_save_notice(_save_store.last_error)
		return false
	_set_save_notice("")
	return true

func request_quit() -> void:
	if save():
		get_tree().quit()
		return
	# Never silently discard an unsaved session just because the OS asked to close.
	# Build the same choices in headless tests, but only show a window to players.
	if _save_dialog:
		_save_dialog.hide()
	if _quit_dialog == null:
		_quit_dialog = ConfirmationDialog.new()
		_quit_dialog.title = "Progress could not be saved"
		_quit_dialog.ok_button_text = "Retry save and exit"
		_quit_dialog.cancel_button_text = "Keep playing"
		_quit_dialog.add_button("Quit without saving", false, "discard")
		_quit_dialog.confirmed.connect(request_quit.call_deferred)
		_quit_dialog.custom_action.connect(func(action: StringName):
			if action == &"discard":
				get_tree().quit()
		)
		add_child(_quit_dialog)
		_quit_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_quit_dialog.get_label().custom_minimum_size.x = 600
	_quit_dialog.dialog_text = save_notice + "\n\nRetry saving, keep playing, or quit without saving your latest progress."
	if DisplayServer.get_name() != "headless":
		_quit_dialog.popup_centered(Vector2i(650, 220))

func _set_save_notice(message: String) -> void:
	if message == save_notice:
		return
	save_notice = message
	save_notice_changed.emit(message)
	if not message.is_empty():
		push_warning(message)
		_show_save_notice.call_deferred()
	elif _save_dialog:
		_save_dialog.hide()

func _show_save_notice() -> void:
	if save_notice.is_empty() or DisplayServer.get_name() == "headless":
		return
	if _quit_dialog and _quit_dialog.visible:
		return
	if _save_dialog == null:
		_save_dialog = AcceptDialog.new()
		_save_dialog.title = "Save status"
		add_child(_save_dialog)
		_save_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_save_dialog.get_label().custom_minimum_size.x = 600
	_save_dialog.dialog_text = save_notice
	_save_dialog.popup_centered(Vector2i(650, 200))

func _build_save_config() -> ConfigFile:
	var config = ConfigFile.new()
	
	config.set_value("player", "money", money)
	config.set_value("player", "xp", xp)
	config.set_value("player", "level", level)
	config.set_value("player", "xp_to_next_level", xp_to_next_level)
	config.set_value("player", "equipped_ball", equipped_ball)
	config.set_value("player", "equipped_golfer", equipped_golfer)
	config.set_value("player", "equipped_course", equipped_course)
	config.set_value("player", "medals", medals)
	config.set_value("player", "lifetime_xp", lifetime_xp)
	config.set_value("player", "lifetime_money", lifetime_money)
	config.set_value("player", "best_run_xp", best_run_xp)
	config.set_value("player", "best_run_money", best_run_money)
	config.set_value("market", "pots", market.pots.duplicate(true))
	config.set_value("market", "streak_key", market.streak_key)
	config.set_value("market", "streak_count", market.streak_count)
	
	for key in upgrades:
		config.set_value("upgrades", key, upgrades[key]["level"])

	for key in level_bonuses:
		config.set_value("level_bonuses", key, level_bonuses[key])

	for key in balls:
		config.set_value("balls", key, balls[key]["owned"])
	
	for key in golfers:
		config.set_value("golfers", key, golfers[key]["owned"])

	for key in courses:
		config.set_value("courses", key, courses[key]["owned"])
	for course in COURSE_FINAL_TARGETS:
		config.set_value("completion", course, completed_courses[course])

	config.set_value("settings", "window_mode", window_mode)
	config.set_value("settings", "window_size", window_size)
	config.set_value("settings", "vsync_enabled", vsync_enabled)
	config.set_value("settings", "sfx_muted", sfx_muted)
	config.set_value("settings", "music_muted", music_muted)
	config.set_value("ui", "has_clicked_help_button", has_clicked_help_button)

	return config

func load_game() -> bool:
	_ensure_save_store()
	var result := _save_store.load_save(BuildProfile.demo_import_path())
	_set_save_notice(result.message)
	if result.config == null:
		return not _save_store.blocked
	_apply_save_config(result.config)
	if result.get("imported", false):
		# Commit once before gameplay starts. Failure leaves imported progress in
		# memory for retry, while the demo source remains completely untouched.
		if not save():
			return false
		_set_save_notice(result.message)
	return true

func _apply_save_config(config: ConfigFile) -> void:
	money = config.get_value("player", "money", 0.0)
	xp = config.get_value("player", "xp", 0.0)
	level = config.get_value("player", "level", 1)
	xp_to_next_level = config.get_value("player", "xp_to_next_level", 100.0)
	equipped_ball = config.get_value("player", "equipped_ball", "standard")
	equipped_golfer = config.get_value("player", "equipped_golfer", "standard")
	equipped_course = config.get_value("player", "equipped_course", "course1")
	medals = config.get_value("player", "medals", 0.0)
	lifetime_xp = config.get_value("player", "lifetime_xp", 0.0)
	lifetime_money = config.get_value("player", "lifetime_money", 0.0)
	best_run_xp = config.get_value("player", "best_run_xp", 0.0)
	best_run_money = config.get_value("player", "best_run_money", 0.0)
	market.pots = config.get_value("market", "pots", {}).duplicate(true)
	market.streak_key = config.get_value("market", "streak_key", "")
	market.streak_count = config.get_value("market", "streak_count", 0)
	window_mode = config.get_value("settings", "window_mode", "fullscreen")
	window_size = config.get_value("settings", "window_size", "1600x900")
	vsync_enabled = config.get_value("settings", "vsync_enabled", false)
	sfx_muted = config.get_value("settings", "sfx_muted", false)
	music_muted = config.get_value("settings", "music_muted", false)
	has_clicked_help_button = config.get_value("ui", "has_clicked_help_button", false)
	
	for key in upgrades:
		upgrades[key]["level"] = config.get_value("upgrades", key, 0)

	for key in level_bonuses:
		level_bonuses[key] = config.get_value("level_bonuses", key, 0.0)

	for key in balls:
		balls[key]["owned"] = config.get_value("balls", key, balls[key].get("owned", false))
	
	for key in golfers:
		golfers[key]["owned"] = config.get_value("golfers", key, golfers[key].get("owned", false))

	for key in courses:
		courses[key]["owned"] = config.get_value("courses", key, courses[key].get("owned", false))
	for course in COURSE_FINAL_TARGETS:
		completed_courses[course] = config.get_value("completion", course, false)

	_sanitize_progress()
	completion_changed.emit()

func add_xp(amount: float, launch_multiplier: float = -1.0) -> void:
	var gained = amount * (get_xp_mult() if launch_multiplier < 0.0 else launch_multiplier)
	xp += gained
	lifetime_xp += gained
	while xp >= xp_to_next_level:
		xp -= xp_to_next_level
		_level_up()
	xp_changed.emit(xp, xp_to_next_level)

func add_level(amount: int = 1) -> void:
	for i in maxi(1, amount):
		_level_up()
	xp_changed.emit(xp, xp_to_next_level)
	save()

func _level_up() -> void:
	level += 1
	xp_to_next_level = floor(100.0 * pow(1.4, level - 1))
	var reward_index = (level - 2) % LEVEL_REWARDS.size()
	var stat = LEVEL_REWARDS[reward_index]
	level_bonuses[stat] += 0.05  # +5% multiplier per level
	leveled_up.emit(level, stat)
	money_changed.emit(money)

func get_level_mult(stat: String) -> float:
	return 1.0 + level_bonuses.get(stat, 0.0)

func get_swing_speed() -> float:
	return (1.0 + upgrades["fire_rate"]["level"] * 0.06) * get_level_mult("fire_rate") * get_golfer_data()["fire_rate_mult"]

func add_money(amount: float) -> void:
	credit_reward(RewardRules.base_reward(capture_shot_context(), amount))

func credit_reward(reward: Dictionary) -> void:
	# RewardRules (or an accrued pot) has already applied every multiplier.
	# Refunds/purchases are balance transfers and intentionally do not use this.
	money += float(reward.money)
	lifetime_money += float(reward.money)
	add_xp(float(reward.xp), 1.0)
	money_changed.emit(money)

func get_ball_count() -> int:
	return 1 + upgrades["multi_ball"]["level"]

func get_multi_ball_spread_degrees() -> float:
	return max(8.0, 20.0 - upgrades["multi_ball_spread"]["level"] * 2.0)

func get_cost_for_level(upgrade: String, level: int) -> float:
	return EconomyRules.upgrade_cost(upgrade, upgrades[upgrade]["base_cost"], level)

func get_cost(upgrade: String) -> float:
	var level = int(upgrades[upgrade]["level"])
	return get_cost_for_level(upgrade, level)

func try_purchase(upgrade: String) -> bool:
	if not upgrades.has(upgrade) or is_demo_hidden_upgrade(upgrade):
		return false
	var data: Dictionary = upgrades[upgrade]
	if data.get("max_level", -1) >= 0 and data.level >= data.max_level:
		return false
	var cost = get_cost(upgrade)
	if data.get("use_medals", false):
		if medals < cost:
			return false
		medals -= cost
		data.level += 1
		medals_changed.emit(medals)
		return true
	if money >= cost:
		money -= cost
		upgrades[upgrade]["level"] += 1
		money_changed.emit(money)
		return true
	return false

func get_golfer_data() -> Dictionary:
	return golfers[equipped_golfer]

func capture_shot_context(course_revision: int = -1) -> Dictionary:
	# Only launch captures live equipment/stats. Freeze dictionaries so fragments
	# and delayed callbacks can share this snapshot without changing each other.
	var ball_data: Dictionary = balls[equipped_ball].duplicate(true)
	ball_data.make_read_only()
	var context := {
		"ball_id": equipped_ball, "golfer_id": equipped_golfer,
		"course_id": equipped_course, "course_revision": course_revision,
		"ball_data": ball_data, "money_mult": get_money_mult(),
		"xp_mult": get_xp_mult(), "respawn_mult": get_golfer_data().get("respawn_mult", 1.0),
		"ball_speed": get_ball_speed(), "consistency": get_consistency(),
		"flat_distance": get_flat_distance(), "ball_count": get_ball_count(),
		"multi_spread": get_multi_ball_spread_degrees(),
	}
	context.make_read_only()
	return context

func get_ball_speed() -> float:
	return (1.0 + upgrades["ball_speed"]["level"] * 0.04) * get_level_mult("ball_speed") * get_golfer_data()["speed_mult"]

func get_fire_rate() -> float:
	return (1.0 + upgrades["fire_rate"]["level"] * 0.03) * get_level_mult("fire_rate") * get_golfer_data()["fire_rate_mult"]

func get_money_mult() -> float:
	return RewardRules.money_multiplier(upgrades["money_mult"]["level"], get_level_mult("money_mult"), get_golfer_data()["money_mult"], balls[equipped_ball]["money_mult"])

func get_consistency() -> float:
	var medal_mult = 1.0 + upgrades["consistency_mult"]["level"] * 0.5
	return (0.5 + upgrades["consistency"]["level"] * .1) * get_level_mult("consistency") * medal_mult

func get_xp_mult() -> float:
	return (1.0 + upgrades["xp_mult"]["level"] * 0.09) * get_level_mult("xp_mult")

func _sanitize_progress() -> void:
	level = max(1, int(level))
	xp_to_next_level = max(1.0, float(xp_to_next_level))
	money = max(0.0, float(money))
	xp = max(0.0, float(xp))
	medals = max(0.0, float(medals))
	lifetime_xp = max(0.0, float(lifetime_xp))
	lifetime_money = max(0.0, float(lifetime_money))
	best_run_xp = max(0.0, float(best_run_xp))
	best_run_money = max(0.0, float(best_run_money))

	for key in upgrades:
		var level_value: int = max(0, int(upgrades[key].get("level", 0)))
		var max_level: int = int(upgrades[key].get("max_level", -1))
		if max_level >= 0:
			level_value = min(level_value, max_level)
		if is_demo_hidden_upgrade(key):
			level_value = 0
		upgrades[key]["level"] = level_value

	balls["standard"]["owned"] = true
	golfers["standard"]["owned"] = true
	courses["course1"]["owned"] = true

	if IS_DEMO_BUILD:
		for key in balls:
			if is_demo_locked(balls[key]):
				balls[key]["owned"] = false
		for key in golfers:
			if is_demo_locked(golfers[key]):
				golfers[key]["owned"] = false
		for key in courses:
			if is_demo_locked(courses[key]):
				courses[key]["owned"] = false

	if not balls.has(equipped_ball) or not balls[equipped_ball].get("owned", false):
		equipped_ball = "standard"
	if not golfers.has(equipped_golfer) or not golfers[equipped_golfer].get("owned", false):
		equipped_golfer = "standard"
	if not courses.has(equipped_course) or not courses[equipped_course].get("owned", false):
		equipped_course = "course1"
