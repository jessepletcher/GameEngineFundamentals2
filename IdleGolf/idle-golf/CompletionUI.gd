extends Control
## Persistent progress access plus one-time feedback for a newly beaten course.
const COURSE_NAMES := {"course1": "Big Piney", "course2": "Desert", "course3": "Beach"}
const TARGET_NAMES := {"course1": "Mountain", "course2": "Pyramids", "course3": "Cargo Ship"}
var status_button: Button
var panel: PanelContainer
var title_label: Label
var progress_label: Label
var save_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := preload("res://balatro.otf")
	status_button = Button.new()
	status_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_button.position = Vector2(-160, 18)
	status_button.size = Vector2(320, 42)
	status_button.add_theme_font_override("font", font)
	status_button.add_theme_font_size_override("font_size", 22)
	add_child(status_button)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -200)
	panel.custom_minimum_size = Vector2(660, 400)
	panel.z_index = 30
	var style := StyleBoxFlat.new()
	style.bg_color = Color("382a22")
	style.border_color = Color("cba966")
	style.set_border_width_all(4)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	title_label = _label(box, font, 30)
	progress_label = _label(box, font, 22)
	save_label = _label(box, font, 18)
	var keep_playing := Button.new()
	keep_playing.text = "Keep playing"
	keep_playing.custom_minimum_size.y = 44
	keep_playing.add_theme_font_override("font", font)
	keep_playing.add_theme_font_size_override("font_size", 22)
	box.add_child(keep_playing)
	keep_playing.pressed.connect(func(): panel.hide())
	status_button.pressed.connect(func():
		title_label.text = "Game complete!" if GameState.is_game_complete() else "Course progress"
		panel.show()
	)
	GameState.completion_changed.connect(_refresh)
	GameState.save_notice_changed.connect(func(_message: String): _refresh())
	GameState.course_completed.connect(_celebrate)
	_refresh()
	panel.hide()

func _label(box: VBoxContainer, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff0ce"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label

func _refresh() -> void:
	status_button.text = "Game complete!  3 / 3" if GameState.is_game_complete() else "Courses beaten: %d / 3" % GameState.completed_course_count()
	var lines: PackedStringArray = []
	for course in GameState.COURSE_FINAL_TARGETS:
		var progress: String = "Beaten" if GameState.completed_courses[course] else "Destroy the " + TARGET_NAMES[course]
		if GameState.IS_DEMO_BUILD and course != "course1":
			progress = "Full game"
		lines.append("%s: %s" % [COURSE_NAMES[course], progress])
	progress_label.text = "\n\n".join(lines)
	save_label.text = "All three courses beaten. Keep playing as long as you like!" if GameState.is_game_complete() else "Beat all three courses to complete the game."
	if not GameState.save_notice.is_empty():
		save_label.text = "Progress may not be saved. Check the save warning."

func _celebrate(course: String) -> void:
	title_label.text = "Game complete!" if GameState.is_game_complete() else COURSE_NAMES[course] + " beaten!"
	panel.show()
