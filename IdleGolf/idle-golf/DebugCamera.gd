extends Camera3D

var _active := false
var _velocity := Vector3.ZERO
var _mouse_delta := Vector2.ZERO
var _speed := 20.0
var _sensitivity := 0.003

func _ready() -> void:
	current = false
	if not GameState.BuildProfile.debug_tools_enabled():
		set_process(false)
		set_process_unhandled_input(false)

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.BuildProfile.debug_tools_enabled():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_active = !_active
		current = _active
		# hide/show all canvas layers
		for node in get_parent().get_children():
			if node is CanvasLayer:
				node.visible = !_active
		if _active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _active and event is InputEventMouseMotion:
		_mouse_delta = event.relative

func _process(delta: float) -> void:
	if not _active:
		return

	# rotation from mouse
	rotation.y -= _mouse_delta.x * _sensitivity
	rotation.x -= _mouse_delta.y * _sensitivity
	rotation.x = clamp(rotation.x, -PI / 2, PI / 2)
	_mouse_delta = Vector2.ZERO

	# movement
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_key_pressed(KEY_E):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_Q):
		input_dir.y -= 1

	var speed = _speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 3.0

	global_position += (basis * input_dir.normalized()) * speed * delta
