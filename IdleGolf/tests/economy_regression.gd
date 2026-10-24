extends SceneTree
const Rules = preload("res://EconomyRules.gd")
const Ledger = preload("res://MarketLedger.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual-expected) <= maxf(0.000001, absf(expected)*0.00000001), message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var state = root.get_node("GameState")
	state.sfx_muted = true
	state.music_muted = true
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var shop = game.get_node("CanvasLayer")
	for key in state.upgrades:
		var previous := -1.0
		var limit: int = state.upgrades[key].get("max_level", 1500)
		var monotonic := true
		for level in range(limit+1):
			var cost: float = state.get_cost_for_level(key, level)
			monotonic = monotonic and is_finite(cost) and cost >= previous and cost > 0
			previous = cost
		check(monotonic, key + " prices stay finite, positive and nondecreasing after rounding")
		# Exercise real buy/refund callbacks, including both speed curve joints.
		for level in ([0, 59, 60, 61, 264, 265, 266, 534, 749] if key == "ball_speed" else [0, mini(2, limit-1)]):
			state.upgrades[key].level = level
			var cost: float = state.get_cost(key)
			state.money = cost if not state.upgrades[key].get("use_medals", false) else 0
			state.medals = cost if state.upgrades[key].get("use_medals", false) else 0
			var before_xp: float = state.lifetime_xp
			var before_money: float = state.lifetime_money
			check(shop._buy_one(key), "exact-price UI purchase: " + key)
			check(state.upgrades[key].level == level+1, "purchase grants one level")
			check(shop._refund_one(key), "UI refund succeeds: " + key)
			near(state.medals if state.upgrades[key].get("use_medals", false) else state.money, cost, "refund returns purchase price")
			near(state.lifetime_money, before_money, "refund creates no retirement earnings")
			near(state.lifetime_xp, before_xp, "refund creates no XP")
		state.upgrades[key].level = 0
		state.money = 0
		state.medals = 0
		check(not state.try_purchase(key), "insufficient funds rejected")
		if state.upgrades[key].has("max_level"):
			state.upgrades[key].level = limit
			state.money = 1e9
			state.medals = 1e9
			check(not state.try_purchase(key), "direct purchase respects cap")
	near(state.get_cost_for_level("multi_ball", 0), 100, "first extra ball affordable after a strong retirement")
	near(state.get_cost_for_level("multi_ball", 2), 250, "last extra ball has a reachable medal price")
	near(state.get_cost_for_level("consistency_mult", 9), 250, "last consistency upgrade fits medal scale")
	near(Rules.retirement_reward(1000, 0), 45, "first run reward preserved")
	near(Rules.retirement_reward(1000, 1000), 0, "repeating a record cannot farm medals")
	check(Rules.retirement_reward(2000, 1000) > 0, "new record earns medals")
	check(Rules.retirement_reward(1e30, 1) <= 250, "record payout stays bounded")
	var ledger := Ledger.new()
	for i in 20:
		var added: Dictionary = ledger.deposit("course1/test", {"money": 10.0, "xp": 2.0})
		near(added.money, 10.0 * mini(i+1, 10), "streak bonus capped without erasing streak history")
	check(ledger.streak_count == 20, "streak identity/count remains save compatible")
	var before: Dictionary = ledger.total()
	ledger.grow(3600)
	check(ledger.total().money > before.money and ledger.total().money <= before.money+18000.000001, "one-hour interest respects shared ceiling")
	near(ledger.total().xp / ledger.total().money, .2, "interest retains earned XP ratio")
	var long_tick := Ledger.new()
	var short_ticks := Ledger.new()
	for l in [long_tick, short_ticks]:
		l.deposit("course1/a", {"money": 20000.0, "xp": 4000.0})
	long_tick.grow(7200)
	for i in 7200:
		short_ticks.grow(1)
	near(long_tick.total().money, short_ticks.total().money, "interest invariant across tick sizes and growth boundary")
	var split := Ledger.new()
	split.deposit("course1/a", {"money": 10000.0, "xp": 2000.0})
	split.deposit("course1/b", {"money": 10000.0, "xp": 2000.0})
	split.grow(7200)
	near(split.total().money, long_tick.total().money, "splitting pots cannot multiply interest limit")
	var legacy := Ledger.new()
	legacy.pots = {"course1/a": {"money": 1e20, "xp": 1e19}}
	legacy.streak_key = "course1/a"
	legacy.streak_count = 1000
	check(Ledger.validate(legacy.pots, legacy.streak_key, legacy.streak_count).is_empty(), "large existing pots remain valid")
	legacy.grow(60)
	check(legacy.total().money >= 1e20, "existing accrued investment never reduced")
	near(legacy.deposit("course1/a", {"money": 1.0, "xp": .1}).money, 10, "old large streak gets bounded new deposit")
	state.IS_DEMO_BUILD = true
	state.medals = 10000
	state.upgrades.consistency_mult.level = 0
	check(not state.try_purchase("consistency_mult"), "demo cannot buy hidden medal upgrades")
	state.IS_DEMO_BUILD = false
	game.free()
	await process_frame
	print("ECONOMY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
