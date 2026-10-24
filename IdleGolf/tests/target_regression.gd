extends SceneTree
## Reachability uses the real launcher, legal slider values and real physics.
## Partial-damage fixtures leave two hits at the authored health threshold;
## this is a collision/destruction check, not a progression-time simulation.
var checks := 0
var failures := 0
var game: Node3D
var state: Node

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame

func _run() -> void:
	state = root.get_node("GameState")
	state.window_mode = "windowed"
	state.sfx_muted = true
	state.music_muted = true
	state.equipped_ball = "standard"
	state.equipped_golfer = "standard"
	for key in state.upgrades:
		state.upgrades[key].level = 0
	state.upgrades.consistency.level = 95
	state.upgrades.consistency_mult.level = 10
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._set_spawning_disabled(true)
	game._golden_timer.stop()
	await settle()
	var ids: Array[String] = []
	for course in ["course1", "course2", "course3"]:
		state.equipped_course = course
		state.course_changed.emit()
		game._golden_timer.stop()
		await settle()
		var targets: Array = get_nodes_in_group("destructibles").filter(func(t): return t.can_process())
		check(targets.size() == (2 if course == "course3" else 5), course + " retains only authored objects")
		var finals: Array = targets.filter(func(t): return t.is_final_target)
		check(finals.size() == 1, course + " has exactly one final target")
		if finals.size() == 1:
			for target in targets:
				check(target.position.z <= finals[0].position.z, "final target is furthest: " + str(target.name))
			if course == "course2":
				check(finals[0].target_name == "Pyramids", "desert ends at pyramids")
				check(game.get_node("Level2/ScaledSprite7").position.z > finals[0].position.z, "desert ground backdrop behind scenery")
				for name in ["Cactus", "TallCactus", "OilPump"]:
					var prop = game.get_node("Level2/" + name)
					var art = prop.scaled_sprite.sprite
					check(prop.position.z <= 100 and prop.scaled_sprite.pixel_offset == Vector2.ZERO, name + " foreground art retains authored registration")
					var local: Vector3 = art.to_local(prop.collision_shape.global_position)
					var texture: Texture2D = art.texture
					var px := int(texture.get_width() * .5 + local.x / art.pixel_size)
					var py := int(texture.get_height() * .5 - local.y / art.pixel_size)
					if art.flip_h:
						px = texture.get_width() - 1 - px
					var bitmap := texture.get_image()
					if bitmap.is_compressed():
						bitmap.decompress()
					check(px >= 0 and py >= 0 and px < bitmap.get_width() and py < bitmap.get_height() and bitmap.get_pixel(px, py).a > .5, name + " physical target is on visible art")
			if course == "course3":
				check(finals[0].target_id == "level3_cargoship", "Beach ends at cargo ship")
				var lighthouse = game.get_node("Level3/Lighthouse")
				check(not lighthouse.is_final_target and lighthouse.position.z >= 80 and lighthouse.position.z <= 100, "lighthouse is a near ordinary target")
				for name in ["PracticeTarget", "WaterTower", "Balloon"]:
					check(not game.has_node("Level3/" + name), "no added beach prop " + name)
		for target in targets:
			check(not target.target_id.is_empty() and target.target_id not in ids, "unique stable target ID")
			ids.append(target.target_id)
			await prove_reachable(target)
	game.free()
	await process_frame
	print("TARGET_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func prove_reachable(target: Node3D) -> void:
	# Keep authored health; each hitbox must receive two real shots.
	target._hits_taken = target.hits_required - 2 * target.hit_shapes.size()
	target.respawn_time = 0.05
	var balance: float = state.money
	for hit_shape in target.hit_shapes:
		await hit_with_normal_shots(target, hit_shape.global_position)
	check(not target._is_alive, "real shot destroys " + str(target.name))
	for hit_shape in target.hit_shapes:
		check(hit_shape.disabled, "destruction disables every hitbox")
	check(state.money > balance, "destruction pays " + str(target.name))
	await settle(210)
	check(target._is_alive and target._hits_taken == 0, "target respawns without damage")
	for hit_shape in target.hit_shapes:
		check(not hit_shape.disabled, "respawn restores every hitbox")

func hit_with_normal_shots(target: Node3D, point: Vector3) -> void:
	point.y = maxf(point.y, 1.1)
	var distance := Vector2(point.x, point.z).length()
	var aim := atan2(point.x, point.z)
	check(absf(rad_to_deg(aim)) <= 50.0, "aim is within player controls: " + str(target.name))
	# Solve the damped ballistic path for a legal upgrade level and loft.
	var upgrade := 0
	var loft := 1.0
	for candidate in range(1500):
		var speed := 10.0 * (1.0 + candidate * 0.04)
		var horizontal := speed * (1.0 - 0.5 / 60.0)
		if horizontal <= distance * 0.1:
			continue
		var flight_time := -log(1.0 - 0.1 * distance / horizontal) / 0.1
		var velocity_y: float = (point.y - game.tee_position.global_position.y + 98.0 * flight_time) / (distance / horizontal) - 98.0
		loft = velocity_y / speed
		if loft >= 0.07 and loft <= 0.52:
			upgrade = candidate
			break
	check(loft >= 0.05 and loft <= 0.6, "loft is within player controls: " + str(target.name))
	var start_hits: int = target._hits_taken
	var attempts := 0
	while target._hits_taken < start_hits + 2 and attempts < 12:
		attempts += 1
		for key in state.level_bonuses:
			state.level_bonuses[key] = 0.0
		state.upgrades.ball_speed.level = upgrade
		game.aim_slider.value = -rad_to_deg(aim) / 50.0
		game.shot_control.normalized_pos = Vector2(0, (.3 - loft) / .3)
		seed(1000 + attempts)
		game._spawning_disabled = false
		game._hit_ball()
		game._spawning_disabled = true
		var balls := get_nodes_in_group("balls")
		check(balls.size() == 1, "one normal shot launched")
		var before: int = target._hits_taken
		for frame in 2400:
			await settle(1)
			if target._hits_taken > before or get_nodes_in_group("balls").is_empty():
				break
			if is_instance_valid(balls[0]) and (balls[0]._has_landed or balls[0].global_position.z > point.z + 100.0):
				break
		for ball in get_nodes_in_group("shots"):
			ball.cancel_shot()
		await settle()
	check(target._hits_taken == start_hits + 2, "two real shots hit " + str(target.name))
	print("REACHABLE target=%s speed_upgrade=%d aim=%.3f loft=%.3f attempts=%d destroyed=%s" % [target.target_id, upgrade, -rad_to_deg(aim) / 50.0, loft, attempts, not target._is_alive])
