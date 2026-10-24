extends RigidBody3D

signal landed(distance_yards: float)
signal whiffed
signal exploded(fragments: Array)

const PARTICLE_DESPAWN_YARDS := 500.0
const MIN_WHIFF_CHANCE := 0.02
const MAX_WHIFF_CHANCE := 0.55
const WHIFF_CHANCE_SCALE := 0.32

var _start_z: float
var _has_landed := false
var _speed: float
var _spread: float
var _aim: float = 0.0  # -1.0 to 1.0
var _is_whiff := false
var _is_firework := false
var _is_fragment := false
var _is_fake := false
var _is_homing := false
var _target_flag: Node3D = null
var _has_peaked := false
var _prev_velocity_y := 0.0
var _initial_velocity_y := 0.0
var _homing_time := 0.0
var _launch_modifier := Vector2.ZERO  # x = curve, y = launch angle
var _ball_id := ""
var shot_context: Dictionary = {}
var _cancelled := false
var _landing_paid := false
var _trail_timer := 0.0
var _trail_phase := 0.0
var _pinball_afterimage_index := 0
var _last_zigzag_position := Vector3.ZERO
var _fragment_trail_color := Color.ORANGE
var _firework_glow: MeshInstance3D
var _firework_explode_velocity_ratio := 0.0
var _particles_disabled_for_distance := false
var _payout_multiplier := 1.0
@onready var sprite: Sprite3D = $Sprite3D
@onready var trail: GPUParticles3D = $GPUParticles3D

func launch(speed: float, angle_spread_deg: float, start_z: float) -> void:
	_start_z = start_z
	_speed = speed
	_spread = angle_spread_deg

func is_shot_active() -> bool:
	return not _cancelled and not is_queued_for_deletion() and shot_context.get("course_id", "") == GameState.equipped_course

func can_damage_targets() -> bool:
	return not _is_fake and is_shot_active()

func cancel_shot() -> void:
	_cancelled = true
	_is_homing = false
	_target_flag = null
	freeze = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	remove_from_group("balls")
	remove_from_group("shots")
	queue_free()

func _physics_process(delta: float) -> void:
	if not is_shot_active():
		cancel_shot()
		return
	var yards_from_tee: float = abs(global_position.z - _start_z) * 1.094
	if yards_from_tee > PARTICLE_DESPAWN_YARDS:
		_disable_distance_particles()

	if not _has_landed and global_position.y > 0.2:
		apply_central_force(Vector3(_curve * .5, 0, 0))
		if not _particles_disabled_for_distance:
			_update_ball_visuals(delta)
	
	# scale sprite
	var distance = abs(global_position.z - _start_z)
	var scale_factor = pow(distance * 0.05, 1.0)
	sprite.scale = Vector3(scale_factor, scale_factor, scale_factor)
	if _firework_glow:
		var apex_ratio = 0.0
		if _initial_velocity_y > 0.0:
			apex_ratio = clamp(1.0 - abs(linear_velocity.y / _initial_velocity_y), 0.0, 1.0)
		_firework_glow.scale = Vector3.ONE * lerp(0.5, 2.6, apex_ratio)

	# disable trail particles far from origin for performance
	var dist_from_origin = global_position.length()
	if trail.emitting and (dist_from_origin > 800.0 or _particles_disabled_for_distance):
		trail.emitting = false
	elif not trail.emitting and dist_from_origin < 800.0 and not _particles_disabled_for_distance:
		trail.emitting = true
	
	# Fireworks burst near the apex at the threshold chosen for this shot.
	if _is_firework and not _has_peaked and _initial_velocity_y > 0.0:
		if linear_velocity.y <= _initial_velocity_y * _firework_explode_velocity_ratio:
			_has_peaked = true
			_explode()
			return
	_prev_velocity_y = linear_velocity.y

	# homing
	if _is_homing and _target_flag:
		_homing_time += delta
		_home_toward_flag(delta)
	
	if not _has_landed and global_position.y < 1.0 and _prev_velocity_y < 0.0:
		_land()

func _disable_distance_particles() -> void:
	if _particles_disabled_for_distance:
		return
	_particles_disabled_for_distance = true
	trail.emitting = false
	if _firework_glow:
		_firework_glow.visible = false
		
func _start_homing() -> void:
	_target_flag = null
	_is_homing = false
	if _is_fake or not is_shot_active():
		return
	var flags = get_tree().get_nodes_in_group("flags").filter(func(flag): return flag.can_process())
	if flags.size() == 0:
		return

	# estimate landing position using full velocity (including aim direction)
	var time_to_land = 0.0
	if linear_velocity.y > 0:
		time_to_land = (linear_velocity.y * 2.0) / 9.8
	var estimated_landing = global_position + Vector3(
		linear_velocity.x * time_to_land,
		0.0,
		linear_velocity.z * time_to_land
	)

	# sort flags by distance to estimated landing (closest to landing spot first)
	var sorted_flags = flags.duplicate()
	sorted_flags.sort_custom(func(a, b):
		var da = Vector2(a.global_position.x, a.global_position.z).distance_to(Vector2(estimated_landing.x, estimated_landing.z))
		var db = Vector2(b.global_position.x, b.global_position.z).distance_to(Vector2(estimated_landing.x, estimated_landing.z))
		return da < db
	)

	# pick the closest flag to where we'd naturally land, but only if reachable
	var flat_speed = Vector2(linear_velocity.x, linear_velocity.z).length()
	var max_range = flat_speed * time_to_land * 0.9  # conservative 90% of max distance
	var best_flag: Node3D = null
	for flag in sorted_flags:
		var flag_dist = Vector2(flag.global_position.x, flag.global_position.z).distance_to(Vector2(global_position.x, global_position.z))
		if flag_dist <= max_range:
			best_flag = flag
			break

	# fallback to nearest flag if none are in range
	if not best_flag:
		sorted_flags.sort_custom(func(a, b):
			return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
		)
		best_flag = sorted_flags[0]

	_target_flag = best_flag
	_is_homing = true

func _home_toward_flag(delta: float) -> void:
	# A previously selected flag can become inactive while this ball is airborne.
	if not is_instance_valid(_target_flag) or not _target_flag.can_process():
		_target_flag = null
		_is_homing = false
		return
	# give up after 5 seconds to prevent infinite orbiting
	if _homing_time > 5.0:
		_is_homing = false
		return

	var flat_pos = Vector3(global_position.x, 0, global_position.z)
	var flat_target = Vector3(_target_flag.global_position.x, 0, _target_flag.global_position.z)
	var flat_dist = flat_pos.distance_to(flat_target)

	if flat_dist < 3.0 and global_position.y < 2.0:
		_is_homing = false
		_land()
		return

	# steer toward flag — scales with ball speed so fast balls still turn
	var direction = (flat_target - flat_pos).normalized()
	var current_flat_vel = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var speed = current_flat_vel.length()
	var desired_vel = direction * speed
	var time_strength = clamp(_homing_time * 0.3, 0.05, 2.0)
	var speed_strength = clamp(speed * 0.1, 1.0, 5.0)
	var steer = (desired_vel - current_flat_vel) * time_strength * speed_strength
	apply_central_force(steer)
	
func _explode() -> void:
	if _is_fake or not is_shot_active():
		return
	var BallScene = preload("res://scenes/Ball.tscn")
	var fragments: Array = []
	var base_real_count := 3
	var yards_from_tee: float = abs(global_position.z - _start_z) * 1.094
	var distance_reduction := 0
	if yards_from_tee > PARTICLE_DESPAWN_YARDS:
		distance_reduction = int(floor((yards_from_tee - PARTICLE_DESPAWN_YARDS) / 100.0)) + 1
	var real_count = max(2, base_real_count - distance_reduction)
	var total_count = real_count + 2
	var fragment_payout_multiplier := float(base_real_count) / float(real_count)
	var fragment_colors := [
		Color(1.0, 0.15, 0.05),
		Color(1.0, 0.75, 0.1),
		Color(0.1, 0.85, 1.0),
		Color(0.8, 0.2, 1.0),
		Color(0.2, 1.0, 0.25),
		Color(1.0, 0.35, 0.8),
	]

	AudioManager.play_sfx("firework", randf_range(0.88, 1.12))
	_spawn_shockwave(global_position, Color(1.0, 0.45, 0.08), 0.18)

	for i in total_count:
		var angle = (TAU / float(total_count)) * i

		if i < real_count:
			# real fragment — earns money on landing
			var frag = BallScene.instantiate()
			frag._is_fragment = true
			frag.shot_context = shot_context
			frag._speed = 0
			frag._spread = 0
			frag._start_z = _start_z
			frag._ball_id = "firework"
			frag._fragment_trail_color = fragment_colors[i % fragment_colors.size()]
			frag._payout_multiplier = fragment_payout_multiplier
			get_parent().add_child(frag)
			frag.global_position = global_position
			frag.linear_velocity = Vector3(
				sin(angle) * randf_range(5.0, 15.0),
				randf_range(2.0, 6.0),
				cos(angle) * randf_range(5.0, 15.0)
			)
			fragments.append(frag)
		else:
			# fake particle — just visuals, no landing signal
			var fake = BallScene.instantiate()
			fake._is_fragment = true
			fake.shot_context = shot_context
			fake._is_fake = true
			fake._speed = 0
			fake._spread = 0
			fake._start_z = _start_z
			fake._ball_id = "firework"
			fake._fragment_trail_color = fragment_colors[i % fragment_colors.size()]
			get_parent().add_child(fake)
			fake.global_position = global_position
			fake.linear_velocity = Vector3(
				sin(angle) * randf_range(5.0, 15.0),
				randf_range(2.0, 6.0),
				cos(angle) * randf_range(5.0, 15.0)
			)

	exploded.emit(fragments)
	queue_free()

func _ready() -> void:
	if shot_context.is_empty():
		shot_context = GameState.capture_shot_context()
	# All shots share course cleanup, but only scoring balls participate in
	# gameplay queries. Cosmetic fragments keep gravity-driven visual motion.
	add_to_group("shots")
	if _is_fake:
		collision_layer = 0
		collision_mask = 0
		$CollisionShape3D.disabled = true
	else:
		add_to_group("balls")
	if _is_fragment:
		_start_z = _start_z  # already set by parent
		trail.draw_pass_1 = trail.draw_pass_1.duplicate()
		trail.process_material = trail.process_material.duplicate()
		var mat = trail.draw_pass_1.material.duplicate()
		if _is_fake:
			mat.albedo_color = _fragment_trail_color
			sprite.visible = false
			trail.amount = 12
		else:
			mat.albedo_color = _fragment_trail_color
			trail.amount = 18
		_configure_trail_material(mat)
		_set_trail_quad_size(0.25)
		trail.draw_pass_1.material = mat
		return

	_start_z = global_position.z

	_ball_id = shot_context.ball_id
	var ball_data: Dictionary = shot_context.ball_data
	trail.draw_pass_1 = trail.draw_pass_1.duplicate()
	var mat = trail.draw_pass_1.material.duplicate()
	mat.albedo_color = ball_data["trail_color"]
	trail.draw_pass_1.material = mat
	_apply_special_trail_material(mat)
	var ball_speed_mult = ball_data["speed_mult"]
	
	var spread_rad = deg_to_rad(randf_range(-_spread, _spread))
	var aim_angle = _aim * deg_to_rad(50.0) + spread_rad
	var consistency: float = shot_context.consistency
	var worst_possible = max(0.05, 1.0 - (1.0 / consistency))
	var distance_mult = randf_range(worst_possible, 1.0)
	var whiff_percent = clamp(WHIFF_CHANCE_SCALE / consistency, MIN_WHIFF_CHANCE, MAX_WHIFF_CHANCE)
	var whiff_threshold = worst_possible + (1.0 - worst_possible) * whiff_percent
	if distance_mult < whiff_threshold:
		distance_mult *= randf_range(0.08, 0.25)
		_is_whiff = true
	var horizontal_offset = abs(_launch_modifier.x)
	var distance_mult_from_curve = lerp(1.0, 0.5, horizontal_offset)
	var launch_angle = 0.3 + (_launch_modifier.y * -0.3)
	launch_angle = clamp(launch_angle, 0.05, 0.6)
	
	# convert flat yards to extra speed
	var flat_bonus: float = shot_context.flat_distance
	var curve = -_launch_modifier.x

	var total_horizontal_speed = _speed * distance_mult * ball_speed_mult * distance_mult_from_curve + flat_bonus
	linear_velocity = Vector3(
		sin(aim_angle) * total_horizontal_speed,
		_speed * launch_angle * ball_speed_mult,
		cos(aim_angle) * total_horizontal_speed
	)
	
	# check for negative velocity (ball going backwards)
	if linear_velocity.z < 0:
		_is_whiff = true

	# store curve for _process
	_curve = curve

	# start homing immediately if ball supports it
	if ball_data.get("can_home", false):
		_start_homing()

	_is_firework = ball_data.get("is_firework", false)
	_initial_velocity_y = linear_velocity.y
	_last_zigzag_position = global_position
	if _is_firework:
		_firework_explode_velocity_ratio = randf_range(-0.12, 0.25)
		_create_firework_glow()

var _curve := 0.0

	
	# ... rest of your existing _process code
	
func _land() -> void:
	if _has_landed or not is_shot_active():
		return
	_has_landed = true
	if _is_fake:
		# No ground collider: stop at the visual landing threshold and let the
		# existing trail fade without emitting a gameplay landing signal.
		freeze = true
		linear_velocity = Vector3.ZERO
		trail.emitting = false
		set_physics_process(false)
		var tween = create_tween()
		tween.tween_interval(0.5)
		tween.tween_callback(queue_free)
		return
	var yards = (global_position.z - _start_z) * 1.094
	landed.emit(abs(yards))

func _apply_special_trail_material(mat: StandardMaterial3D) -> void:
	match _ball_id:
		"homing_ball":
			mat.albedo_color = Color(0.1, 1.0, 0.25)
			trail.amount = 96
		"pin_seeker":
			mat.albedo_color = Color(1.0, 0.82, 0.1)
			trail.amount = 80
		"firework":
			mat.albedo_color = Color(1.0, 0.22, 0.05)
			trail.amount = 128
			_configure_trail_material(mat)
			_set_trail_quad_size(0.05)
		"market":
			mat.albedo_color = Color(0.08235294, 0.5019608, 0.09803922)
			trail.amount = 70
			_set_trail_quad_size(0.045)
		"wrecking":
			mat.albedo_color = Color(0.08, 0.08, 0.08)
			trail.amount = 140
		"pinball":
			mat.albedo_color = Color(0.95, 0.0, 1.0)
			trail.amount = 96

func _update_ball_visuals(delta: float) -> void:
	_trail_timer += delta
	_trail_phase += delta * 12.0
	if _trail_timer < 0.045:
		return
	_trail_timer = 0.0

	if _is_fragment:
		return

	match _ball_id:
		"homing_ball":
			_emit_homing_helix()
		"pin_seeker":
			_spawn_beam(_last_zigzag_position, global_position, Color(1.0, 0.85, 0.08, 0.75), 0.04, 0.25)
			_last_zigzag_position = global_position
			_spawn_puff(global_position, Color(1.0, 0.85, 0.08), 0.12, 0.35)
			if randi() % 2 == 0:
				_spawn_puff(global_position + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1), randf_range(-0.2, 0.2)), Color.WHITE, 0.06, 0.2)
		"firework":
			_spawn_puff(global_position, Color(1.0, randf_range(0.2, 0.55), 0.02), randf_range(0.08, 0.18), 0.28)
		"market":
			_emit_market_spiral()
		"wrecking":
			_spawn_puff(global_position, Color(0.04, 0.04, 0.04, 0.85), randf_range(0.22, 0.4), 0.8)
			if randi() % 3 == 0:
				_spawn_puff(global_position, Color(1.0, 0.55, 0.08), 0.07, 0.25)
			_emit_destructible_warning_ring()
		"pinball":
			_emit_pinball_zigzag()

func _emit_homing_helix() -> void:
	var side := Vector3.RIGHT
	var up := Vector3.UP
	if linear_velocity.length() > 0.01:
		var forward := linear_velocity.normalized()
		side = forward.cross(Vector3.UP).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		up = side.cross(forward).normalized()
	for offset in [0.0, PI]:
		var radius := 0.35
		var p := global_position + side * cos(_trail_phase + offset) * radius + up * sin(_trail_phase + offset) * radius
		var color := Color(0.06 + randf_range(0.0, 0.12), 0.72 + randf_range(0.0, 0.28), 0.16 + randf_range(0.0, 0.18), 0.85)
		_spawn_puff(p, color, 0.11, 0.45)

func _emit_market_spiral() -> void:
	var side := Vector3.RIGHT
	var up := Vector3.UP
	if linear_velocity.length() > 0.01:
		var forward := linear_velocity.normalized()
		side = forward.cross(Vector3.UP).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		up = side.cross(forward).normalized()
	for offset in [0.0, PI]:
		var radius := 0.24
		var p := global_position + side * cos(_trail_phase * 0.9 + offset) * radius + up * sin(_trail_phase * 0.9 + offset) * radius
		_spawn_puff(p, Color(0.08235294, 0.5019608, 0.09803922, 0.75), 0.065, 0.35)

func _emit_pinball_zigzag() -> void:
	var color := Color(0.0, 0.95, 1.0) if _pinball_afterimage_index % 2 == 0 else Color(1.0, 0.05, 0.95)
	var start := global_position.lerp(_last_zigzag_position, 0.35)
	_spawn_beam(start, global_position, color, 0.04, 0.24)
	_spawn_puff(global_position, color, 0.12, 0.32)
	_last_zigzag_position = global_position + Vector3(randf_range(-0.18, 0.18), randf_range(-0.08, 0.14), 0.0)
	_pinball_afterimage_index += 1

func _emit_destructible_warning_ring() -> void:
	if randi() % 4 != 0:
		return
	for obj in get_tree().get_nodes_in_group("destructibles"):
		if is_instance_valid(obj) and obj.can_process() and global_position.distance_to(obj.global_position) < 3.5:
			_spawn_shockwave(obj.global_position + Vector3.UP * 0.4, Color(0.9, 0.9, 0.9, 0.7), 0.45)
			return

func _spawn_puff(pos: Vector3, color: Color, size: float, lifetime: float) -> void:
	var scale_factor := _effect_scale(pos)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size * scale_factor
	sphere.height = size * 2.0 * scale_factor
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material_override = mat
	get_tree().current_scene.add_child(mesh)
	mesh.global_position = pos
	var tween := mesh.create_tween().set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.25, lifetime)
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(mesh.queue_free)

func _spawn_beam(from_pos: Vector3, to_pos: Vector3, color: Color, width: float = 0.08, lifetime: float = 0.35) -> void:
	var length := from_pos.distance_to(to_pos)
	if length < 0.01:
		return
	var scale_factor := _effect_scale((from_pos + to_pos) * 0.5)
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width * scale_factor, width * scale_factor, length)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	beam.material_override = mat
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from_pos + to_pos) * 0.5
	beam.global_transform.basis = Basis.looking_at((to_pos - from_pos).normalized(), Vector3.UP)
	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.tween_callback(beam.queue_free)

func _spawn_shockwave(pos: Vector3, color: Color, start_scale: float = 0.25) -> void:
	var scale_factor := _effect_scale(pos)
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
	get_tree().current_scene.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * start_scale * scale_factor
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 5.0 * scale_factor, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(ring.queue_free)

func _create_firework_glow() -> void:
	_firework_glow = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	_firework_glow.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.38, 0.05, 0.45)
	_firework_glow.material_override = mat
	add_child(_firework_glow)

func _set_trail_quad_size(size: float) -> void:
	var quad := trail.draw_pass_1 as QuadMesh
	if quad:
		quad.size = Vector2(size, size)

func _configure_trail_material(mat: StandardMaterial3D) -> void:
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true

func _effect_scale(pos: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return 1.0
	return clamp(pos.distance_to(camera.global_position) / 35.0, 0.25, 1.0)

func _face_camera(node: Node3D) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	node.global_transform.basis = camera.global_transform.basis
