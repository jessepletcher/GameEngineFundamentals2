extends Node3D
## One timeline drives all five poses and exactly one contact event.
signal swung
const Art = preload("res://GolferArt.gd")
const CONTACT_PROGRESS := 0.6
const SWING_SECONDS := 1.0
@onready var sprite: AnimatedSprite3D = $GolferSprite
var _shot_emitted_this_swing := true
var _spawn_disabled := false
var _swing_active := false
var _elapsed := 0.0
var _duration := 1.0
var _visual_golfer := ""

func _ready() -> void:
	_load_golfer_sprite()
	GameState.golfer_changed.connect(_load_golfer_sprite)

func play_swing() -> void:
	if _spawn_disabled or _swing_active:
		return
	_elapsed = 0.0
	_duration = minf(SWING_SECONDS / GameState.get_swing_speed(), 0.8 * 5.0 / GameState.get_fire_rate())
	_shot_emitted_this_swing = false
	_swing_active = true
	_show_frame(0)

func _process(delta: float) -> void:
	if not _swing_active or _spawn_disabled:
		return
	_elapsed += delta
	var progress := minf(1.0, _elapsed / _duration)
	_show_frame(mini(4, int(progress * 5.0)))
	if not _shot_emitted_this_swing and progress >= CONTACT_PROGRESS:
		_shot_emitted_this_swing = true
		swung.emit()
	if progress >= 1.0:
		_swing_active = false
		_show_frame(0)

func cancel_swing() -> void:
	_swing_active = false
	_shot_emitted_this_swing = true
	_elapsed = 0.0
	if is_instance_valid(sprite) and sprite.sprite_frames:
		_show_frame(0)

func set_spawn_disabled(disabled: bool) -> void:
	_spawn_disabled = disabled
	visible = not disabled
	if disabled:
		cancel_swing()

func _load_golfer_sprite() -> void:
	# Same-golfer selection and shop closure cannot restart an existing swing.
	if _visual_golfer == GameState.equipped_golfer:
		return
	cancel_swing()
	_visual_golfer = GameState.equipped_golfer
	var data: Dictionary = GameState.get_golfer_data()
	var sheet: Texture2D = load(data.spritesheet)
	var frames := SpriteFrames.new()
	frames.add_animation("swing")
	frames.set_animation_loop("swing", false)
	for i in 5:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.filter_clip = true
		atlas.region = Art.frame_region(_visual_golfer, i) if Art.SHEETS.has(_visual_golfer) else Rect2(i * 96, 0, 96, 96)
		frames.add_frame("swing", atlas)
	sprite.stop()
	sprite.sprite_frames = frames
	sprite.animation = "swing"
	sprite.pixel_size = Art.pixel_size(_visual_golfer)
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	_show_frame(0)

func _show_frame(frame: int) -> void:
	sprite.frame = frame
	sprite.offset = Art.frame_offset(_visual_golfer, frame)
