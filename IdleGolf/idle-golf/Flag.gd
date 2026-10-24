extends Node3D
const RewardRules = preload("res://RewardRules.gd")

signal golden_hit(flag: Node3D, bonus: float, shot_context: Dictionary, payout_multiplier: float)

@export var radius_x: float = 5.0     # hit detection width
@export var radius_z: float = 5.0     # hit detection depth
@export var direct_radius_x: float = 1.5  # direct hit width
@export var direct_radius_z: float = 1.5  # direct hit depth
@export var distance_mult: float = 1.0 # set this per flag based on how far it is
@export var flag_texture: Texture2D
@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var distance_label: Label3D = $DistanceLabel
@onready var sprite: Sprite3D = $Sprite3D

var _wiggle_tween: Tween
var _is_golden := false
var _golden_tween: Tween
var _original_modulate: Color

var _golden_letters: Array = []
var _golden_widths: Array = []
var _golden_total_width: float = 0.0
var _bounce_time: float = 0.0
const GOLDEN_FONT_SIZE := 24
const GOLDEN_BOUNCE_HEIGHT := 0.25
const GOLDEN_BOUNCE_FREQ := 0.8
const GOLDEN_LETTER_PHASE := 0.6

func _process(delta: float) -> void:
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return

	var distance = global_position.distance_to(camera.global_position)
	var scale_factor = pow(distance * 0.6, .6)
	sprite.scale = Vector3(scale_factor, scale_factor, scale_factor)
	var bob = sin(Time.get_ticks_msec() * 0.002) * 0.3
	var base_y: float = scale_factor * .7 + bob

	if _is_golden and _golden_letters.size() > 0:
		_bounce_time += delta
		var pixel_size := 0.01
		var cam_right_world: Vector3 = camera.global_transform.basis.x
		var cam_right_local: Vector3 = global_transform.basis.inverse() * cam_right_world
		cam_right_local.y = 0
		if cam_right_local.length() > 0.0001:
			cam_right_local = cam_right_local.normalized()
		else:
			cam_right_local = Vector3.RIGHT
		var cumulative: float = 0.0
		for i in _golden_letters.size():
			var lbl: Label3D = _golden_letters[i]
			if not is_instance_valid(lbl):
				continue
			lbl.scale = Vector3(scale_factor, scale_factor, scale_factor) * 0.8
			var letter_offset: float = cumulative + _golden_widths[i] / 2.0 - _golden_total_width / 2.0
			cumulative += _golden_widths[i]
			var phase: float = _bounce_time * GOLDEN_BOUNCE_FREQ * TAU - i * GOLDEN_LETTER_PHASE
			var s: float = sin(phase)
			var hop: float = (s * s if s > 0.0 else 0.0) * GOLDEN_BOUNCE_HEIGHT * scale_factor
			lbl.position = cam_right_local * (letter_offset * pixel_size * scale_factor) + Vector3(0, base_y + hop, 0)
	else:
		distance_label.scale = Vector3(scale_factor, scale_factor, scale_factor) * 0.8
		distance_label.position.y = base_y

func _ready() -> void:
	if flag_texture:
		sprite.texture = flag_texture
	_original_modulate = sprite.modulate
	var yards = global_position.length() * 1.094
	distance_label.text = "%s yds" % GameState.format_number(yards)
	distance_label.font = load("res://balatro.otf")

## Returns [bonus, is_direct_hit]
func check_hit(ball_position: Vector3, shot_context: Dictionary = {}, payout_multiplier: float = 1.0) -> Array:
	if not can_process():
		return [0.0, false]
	var dx = abs(ball_position.x - global_position.x)
	var dz = abs(ball_position.z - global_position.z)

	if dx > radius_x or dz > radius_z:
		return [0.0, false]

	var accuracy = 1.0 - max(dx / radius_x, dz / radius_z)
	var bonus := RewardRules.flag_bonus(global_position.z, distance_mult, accuracy)

	var direct = dx <= direct_radius_x and dz <= direct_radius_z
	if direct:
		AudioManager.play_sfx("flag_stick")
		_wiggle()
		if _is_golden:
			golden_hit.emit(self, bonus, shot_context, payout_multiplier)
			deactivate_golden()

	return [bonus, direct]

func activate_golden() -> void:
	if not can_process():
		return
	_is_golden = true
	if _golden_tween and _golden_tween.is_valid():
		_golden_tween.kill()
	_spawn_golden_letters()

func deactivate_golden() -> void:
	_is_golden = false
	if _golden_tween and _golden_tween.is_valid():
		_golden_tween.kill()
	_clear_golden_letters()
	distance_label.visible = true
	distance_label.modulate = Color.WHITE

func _spawn_golden_letters() -> void:
	_clear_golden_letters()
	distance_label.visible = false
	var text_str: String = distance_label.text
	var font: Font = load("res://balatro.otf")
	_golden_widths.clear()
	_golden_total_width = 0.0
	for c in text_str:
		var w: float = font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, GOLDEN_FONT_SIZE).x
		_golden_widths.append(w)
		_golden_total_width += w

	for i in text_str.length():
		var lbl := Label3D.new()
		lbl.text = text_str[i]
		lbl.font = font
		lbl.font_size = GOLDEN_FONT_SIZE
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.outline_size = 0
		lbl.no_depth_test = true
		lbl.pixel_size = 0.01
		lbl.modulate = Color(1.0, 0.85, 0.0)
		add_child(lbl)
		_golden_letters.append(lbl)

	_golden_tween = create_tween().set_loops().set_parallel(true)
	for lbl in _golden_letters:
		_golden_tween.tween_property(lbl, "modulate", Color(1.0, 1.0, 0.5, 1.0), 0.5)
	_golden_tween.chain()
	for lbl in _golden_letters:
		_golden_tween.tween_property(lbl, "modulate", Color(1.0, 0.85, 0.0, 1.0), 0.5)

func _clear_golden_letters() -> void:
	for lbl in _golden_letters:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_golden_letters.clear()
	_golden_widths.clear()
	_golden_total_width = 0.0

func _wiggle() -> void:
	if not can_process():
		return
	if _wiggle_tween and _wiggle_tween.is_valid():
		_wiggle_tween.kill()
	sprite.rotation.z = 0.0
	_wiggle_tween = create_tween()
	_wiggle_tween.tween_property(sprite, "rotation:z", deg_to_rad(15), 0.05)
	_wiggle_tween.tween_property(sprite, "rotation:z", deg_to_rad(-12), 0.07)
	_wiggle_tween.tween_property(sprite, "rotation:z", deg_to_rad(8), 0.06)
	_wiggle_tween.tween_property(sprite, "rotation:z", deg_to_rad(-5), 0.06)
	_wiggle_tween.tween_property(sprite, "rotation:z", deg_to_rad(2), 0.05)
	_wiggle_tween.tween_property(sprite, "rotation:z", 0.0, 0.05)
