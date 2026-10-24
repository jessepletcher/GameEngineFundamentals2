extends Node3D
const RewardRules = preload("res://RewardRules.gd")

signal destroyed(reward: float, earned_xp: float)

@export var target_id: String = ""
@export var target_name: String = ""
@export var is_final_target: bool = false
## Optional artwork-top height for labels when the collider covers a lower part.
@export var yardage_height: float = 0.0
@export var yardage_offset: Vector3 = Vector3.ZERO
@export var hits_required: int = 10
@export var respawn_time: float = 15.0
@export var shake_factor: float = 1.0
@export var money_per_hit: float = 5.0

@onready var scaled_sprite: Node3D = $ScaledSprite
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D
@onready var hit_shapes: Array[Node] = static_body.get_children().filter(func(child): return child is CollisionShape3D)

var _hits_taken := 0
var _pending_reward := 0.0
var _pending_xp := 0.0
var _respawn_multiplier := 1.0
var _is_alive := true
var _hit_balls: Array = []  # track which balls already counted a hit
var _yardage_label: Label3D
var _yardage_tween: Tween

func _ready() -> void:
	add_to_group("destructibles")
	static_body.disable_mode = CollisionObject3D.DISABLE_MODE_REMOVE
	_create_yardage_label()
	static_body.mouse_entered.connect(func(): _yardage_label.visible = can_process() and _is_alive)
	static_body.mouse_exited.connect(func(): _yardage_label.visible = false)

func _create_yardage_label() -> void:
	_yardage_label = Label3D.new()
	var yards = global_position.length() * 1.094
	_yardage_label.text = "%s yds" % GameState.format_number(yards)
	if is_final_target:
		_yardage_label.text = "%s\nFinal target\n%s" % [target_name, _yardage_label.text]
	_yardage_label.font = load("res://balatro.otf")
	_yardage_label.font_size = 40
	_yardage_label.modulate = Color.WHITE
	_yardage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_yardage_label.outline_size = 0
	_yardage_label.no_depth_test = true
	_yardage_label.visible = false

	var ds = _get_distance_scale()
	_yardage_label.scale = Vector3(ds, ds, ds)

	# position above collision shape
	var shape_top_y = collision_shape.global_position.y
	var shape = collision_shape.shape
	if shape is BoxShape3D:
		shape_top_y += shape.size.y * 0.5
	elif shape is SphereShape3D:
		shape_top_y += shape.radius
	if yardage_height > 0.0:
		shape_top_y = global_position.y + yardage_height
	add_child(_yardage_label)
	_yardage_label.global_position = Vector3(collision_shape.global_position.x, shape_top_y + 0.5 * ds, collision_shape.global_position.z) + yardage_offset

func show_yardage() -> void:
	if not can_process() or not _is_alive or not _yardage_label or not is_instance_valid(_yardage_label):
		return
	# kill previous blink if still running
	if _yardage_tween and _yardage_tween.is_valid():
		_yardage_tween.kill()

	_yardage_label.modulate.a = 1.0

	# blink 5 times then hide
	_yardage_tween = create_tween()
	for i in 3:
		_yardage_tween.tween_callback(func():
			_yardage_label.visible = true
			AudioManager.play_sfx("blink")
		)
		_yardage_tween.tween_interval(0.6)
		_yardage_tween.tween_callback(func(): _yardage_label.visible = false)
		_yardage_tween.tween_interval(0.6)

func _physics_process(_delta: float) -> void:
	if not can_process() or not _is_alive:
		return
	for hit_shape in hit_shapes:
		if not hit_shape.disabled:
			_check_hits(hit_shape)

func _check_hits(hit_shape: CollisionShape3D) -> void:
	# use the collision shape's AABB for hit detection
	var shape = hit_shape.shape
	var shape_origin = hit_shape.global_position
	var half_extents: Vector3

	# pad the detection area so balls that bounce off the surface still register
	var padding := 1.0
	if shape is BoxShape3D:
		half_extents = shape.size * 0.5 + Vector3(padding, padding, padding)
	elif shape is SphereShape3D:
		half_extents = Vector3.ONE * (shape.radius + padding)
	else:
		half_extents = Vector3(3.0, 3.0, 3.0)

	for ball in get_tree().get_nodes_in_group("balls"):
		if not is_instance_valid(ball):
			continue
		if not ball.has_method("can_damage_targets") or not ball.can_damage_targets():
			continue
		if ball in _hit_balls:
			continue

		var dx = abs(ball.global_position.x - shape_origin.x)
		var dy = abs(ball.global_position.y - shape_origin.y)
		var dz = abs(ball.global_position.z - shape_origin.z)

		if dx < half_extents.x and dy < half_extents.y and dz < half_extents.z:
			_hit_balls.append(ball)
			_take_hit(ball.shot_context)

func _take_hit(shot_context: Dictionary = {}) -> void:
	if not can_process() or not _is_alive:
		return
	if shot_context.is_empty():
		shot_context = GameState.capture_shot_context()
	if shot_context.course_id != GameState.equipped_course:
		return
	_hits_taken += 1
	# Each hit carries its own launch stats; the finishing hit cannot reprice
	# earlier damage. The finishing golfer determines the next respawn delay.
	var distance := global_position.length() * 1.094
	var contribution := RewardRules.destructible_hit(shot_context, money_per_hit, distance)
	_pending_reward += contribution.money
	_pending_xp += contribution.xp
	_respawn_multiplier = shot_context.respawn_mult
	_shake()

	if _hits_taken >= hits_required:
		_crumble()

func _get_distance_scale() -> float:
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return 1.0
	var dist = global_position.distance_to(cam.global_position)
	return max(dist * 0.15, 0.1)

func _shake() -> void:
	var tween = create_tween()
	var base_x = 0.0
	var intensity = 0.08 * _get_distance_scale() * shake_factor
	tween.tween_property(scaled_sprite, "position:x", base_x + intensity, 0.03)
	tween.tween_property(scaled_sprite, "position:x", base_x - intensity, 0.04)
	tween.tween_property(scaled_sprite, "position:x", base_x + intensity * 0.6, 0.03)
	tween.tween_property(scaled_sprite, "position:x", base_x - intensity * 0.4, 0.03)
	tween.tween_property(scaled_sprite, "position:x", base_x + intensity * 0.2, 0.02)
	tween.tween_property(scaled_sprite, "position:x", base_x, 0.02)

func _crumble() -> void:
	if not can_process() or not _is_alive:
		return
	_is_alive = false
	for hit_shape in hit_shapes:
		hit_shape.disabled = true

	var reward := _pending_reward
	destroyed.emit(reward, _pending_xp)
	_spawn_reward_text(reward)

	AudioManager.play_sfx("destroy")
	_spawn_break_pieces()

	var ds = _get_distance_scale()
	var fall_distance = 3.0 * ds

	# violent shake while falling
	var shake_tween = create_tween().set_loops(50)
	var shake_intensity = 0.12 * ds * shake_factor
	shake_tween.tween_property(scaled_sprite, "position:x", shake_intensity, 0.02)
	shake_tween.tween_property(scaled_sprite, "position:x", -shake_intensity, 0.02)

	# fall straight down and fade
	var fall_tween = create_tween().set_parallel(true)
	fall_tween.tween_property(scaled_sprite, "position:y", scaled_sprite.position.y - fall_distance, 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall_tween.tween_callback(_fade_sprite).set_delay(1.2)

	# after fall completes, stop shaking and respawn later
	fall_tween.set_parallel(false)
	fall_tween.tween_callback(func():
		shake_tween.kill()
		scaled_sprite.position.x = 0.0
	)
	fall_tween.tween_interval(respawn_time * _respawn_multiplier)
	fall_tween.tween_callback(_respawn)

var _reward_label: Label3D

func _spawn_reward_text(reward: float) -> void:
	# remove previous label if one exists
	if _reward_label and is_instance_valid(_reward_label):
		_reward_label.queue_free()

	_reward_label = Label3D.new()
	_reward_label.text = "+$%s" % GameState.format_number(reward)
	_reward_label.font = load("res://balatro.otf")
	_reward_label.font_size = 32
	_reward_label.modulate = Color(1.0, 0.84, 0.0)  # gold
	_reward_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reward_label.no_depth_test = true
	_reward_label.outline_size = 0

	var ds = _get_distance_scale()
	_reward_label.scale = Vector3(ds, ds, ds)

	add_child(_reward_label)
	# position above the collision shape
	var shape = collision_shape.shape
	var shape_top_y = collision_shape.global_position.y
	if shape is BoxShape3D:
		shape_top_y += shape.size.y * 0.5
	elif shape is SphereShape3D:
		shape_top_y += shape.radius
	_reward_label.global_position = Vector3(collision_shape.global_position.x, shape_top_y + 0.5 * ds, collision_shape.global_position.z)

	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_reward_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_reward_label.queue_free)

func _fade_sprite() -> void:
	var sprite_3d = scaled_sprite.get_node("Sprite3D")
	var fade_tween = create_tween()
	fade_tween.tween_property(sprite_3d, "modulate:a", 0.0, 0.3)

func _spawn_break_pieces() -> void:
	var sprite_3d: Sprite3D = scaled_sprite.get_node("Sprite3D")
	var base_color: Color = sprite_3d.modulate
	var effect_scale: float = clampf(_get_distance_scale() / 4.0, 0.25, 1.0)
	for i in 14:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		var sz: float = randf_range(0.12, 0.34) * effect_scale
		box.size = Vector3(sz, sz, sz)
		piece.mesh = box
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = base_color.lightened(randf_range(0.0, 0.25))
		mat.roughness = 0.8
		piece.material_override = mat
		get_tree().current_scene.add_child(piece)
		piece.global_position = collision_shape.global_position + Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.8), randf_range(-0.4, 0.4)) * effect_scale
		piece.rotation = Vector3(randf(), randf(), randf()) * TAU
		var scatter: Vector3 = Vector3(randf_range(-1.8, 1.8), randf_range(1.0, 3.2), randf_range(-1.4, 1.4)) * effect_scale
		var tween := piece.create_tween().set_parallel(true)
		tween.tween_property(piece, "global_position", piece.global_position + scatter, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, "rotation", piece.rotation + Vector3(randf(), randf(), randf()) * TAU * 2.0, 0.65)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.65).set_delay(0.25)
		tween.chain().tween_callback(piece.queue_free)

func _respawn() -> void:
	_hits_taken = 0
	_pending_reward = 0.0
	_pending_xp = 0.0
	_hit_balls.clear()
	_is_alive = true
	for hit_shape in hit_shapes:
		hit_shape.disabled = false
	scaled_sprite.scale = Vector3.ONE
	scaled_sprite.position = Vector3.ZERO
	var sprite_3d = scaled_sprite.get_node("Sprite3D")
	sprite_3d.modulate.a = 0.0

	var tween = create_tween()
	tween.tween_property(sprite_3d, "modulate:a", 1.0, 0.5)

func get_progress() -> String:
	if not _is_alive:
		return "DESTROYED"
	return "%d/%d" % [_hits_taken, hits_required]
