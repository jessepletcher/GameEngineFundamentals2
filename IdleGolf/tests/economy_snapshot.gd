extends SceneTree
## Export live authored geometry and economy, without touching a player profile.
func _initialize() -> void:
	run.call_deferred()

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func run() -> void:
	var state = root.get_node("GameState")
	state.sfx_muted = true
	state.music_muted = true
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	var data := {"courses": {}, "upgrades": state.upgrades.duplicate(true),
		"balls": {}, "golfers": {}, "catalog": {}, "level_rewards": state.LEVEL_REWARDS,
		"tee": vec(game.tee_position.global_position), "base_speed": game.BASE_SPEED,
		"base_interval": game.BASE_INTERVAL, "base_spread": game.BASE_SPREAD,
		"gravity": ProjectSettings.get_setting("physics/3d/default_gravity", 9.8),
		"damping": ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1),
		"costs": {}, "stats": {}}
	for kind in ["balls", "golfers", "courses"]:
		var clean := {}
		for id in state.get(kind):
			clean[id] = {}
			for field in state.get(kind)[id]:
				var value = state.get(kind)[id][field]
				if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
					clean[id][field] = value
		data["catalog" if kind == "courses" else kind] = clean
	for key in state.upgrades:
		data.costs[key] = []
		for level in range(1501):
			data.costs[key].append(state.get_cost_for_level(key, level))
	for course in game._course_data:
		var targets := []
		for target in get_nodes_in_group("destructibles"):
			if not game._course_data[course].sprites.is_ancestor_of(target):
				continue
			var shapes := []
			for hit_shape in target.hit_shapes:
				var shape = hit_shape.shape
				var extents: Vector3 = shape.size * 0.5 if shape is BoxShape3D else Vector3.ONE * shape.radius
				shapes.append({"position": vec(hit_shape.global_position), "half": vec(extents + Vector3.ONE)})
			targets.append({"id": target.target_id, "name": target.target_name, "final": target.is_final_target,
				"hits": target.hits_required, "respawn": target.respawn_time + 2.0,
				"per_hit": target.money_per_hit, "yards": target.global_position.length() * 1.094, "shapes": shapes})
		var flags := []
		for flag in game._course_data[course].flags.get_children():
			flags.append({"position": vec(flag.global_position), "radius": [flag.radius_x, flag.radius_z],
				"direct": [flag.direct_radius_x, flag.direct_radius_z], "mult": flag.distance_mult})
		data.courses[course] = {"targets": targets, "flags": flags}
	# Independent runtime parity samples for the simulator's formulas.
	for value in [0, 1, 20, 60, 100, 300, 700]:
		for key in state.upgrades:
			state.upgrades[key].level = value if not state.upgrades[key].get("use_medals", false) else 0
		data.stats[str(value)] = [state.get_ball_speed(), state.get_fire_rate(), state.get_money_mult(), state.get_consistency(), state.get_xp_mult()]
	for key in state.upgrades:
		state.upgrades[key].level = 0
	var context: Dictionary = state.capture_shot_context()
	data["reward_samples"] = [state.RewardRules.landing(context, 100, 0, false),
		state.RewardRules.landing(context, 1000, 0, false), state.RewardRules.destructible_hit(context, 5, 100)]
	data["retirement_samples"] = []
	for pair in [[1000.0, 0.0], [1000.0, 1000.0], [2000.0, 1000.0], [1e9, 1000.0]]:
		state.lifetime_money = pair[0]
		state.best_run_money = pair[1]
		data.retirement_samples.append(state.get_medal_reward())
	var file := FileAccess.open("res://economy-snapshot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	game.free()
	await process_frame
	print("ECONOMY_SNAPSHOT complete")
	quit()
