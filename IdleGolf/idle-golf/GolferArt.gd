extends RefCounted
## Native atlas regions keep source artwork intact. Feet stay registered while
## sheets of different resolutions share the original golfer's world scale.
const SHEETS := {
	"power": preload("res://art/golfers/DysonSwing.png"),
	"construction": preload("res://art/golfers/BlueCollarSwing.png"),
	"golfer1": preload("res://art/golfers/ZoomerSwing.png"),
	"golfer2": preload("res://art/golfers/LambSwing.png"),
	"golfer4": preload("res://art/golfers/MoneyDailySwing.png"),
}
const BODY_HEIGHT := {"power": 379.0, "construction": 385.0, "golfer1": 415.0, "golfer2": 381.0, "golfer4": 411.0}
const FEET := {
	"power": [Vector2(190, 600), Vector2(195, 600), Vector2(186, 599), Vector2(201, 600), Vector2(183, 595)],
	"construction": [Vector2(190, 588), Vector2(235, 588), Vector2(206, 588), Vector2(160, 588), Vector2(213, 593)],
	"golfer1": [Vector2(211, 631), Vector2(211, 631), Vector2(186, 631), Vector2(178, 631), Vector2(187, 631)],
	"golfer2": [Vector2(200, 594), Vector2(231, 594), Vector2(223, 594), Vector2(212, 594), Vector2(188, 594)],
	"golfer4": [Vector2(193, 619), Vector2(215, 619), Vector2(180, 619), Vector2(130, 619), Vector2(190, 619)],
}
const PORTRAITS := {
	"power": Rect2(230, 205, 115, 115), "construction": Rect2(205, 190, 115, 115),
	"golfer1": Rect2(235, 205, 120, 120), "golfer2": Rect2(210, 195, 125, 125),
	"golfer4": Rect2(235, 195, 120, 120),
}

static func frame_region(id: String, frame: int) -> Rect2:
	var sheet: Texture2D = SHEETS[id]
	var left := roundi(frame * sheet.get_width() / 5.0)
	var right := roundi((frame + 1) * sheet.get_width() / 5.0)
	return Rect2(left, 0, right - left, sheet.get_height())

static func pixel_size(id: String) -> float:
	return 0.72 / BODY_HEIGHT[id] if SHEETS.has(id) else 0.01

static func frame_offset(id: String, frame: int) -> Vector2:
	if not SHEETS.has(id):
		return Vector2.ZERO
	var size := frame_region(id, frame).size
	var feet: Vector2 = FEET[id][frame]
	var unit := pixel_size(id)
	# Sprite3D's vertical offset is positive upward (texture pixels run down).
	return Vector2(-0.05 / unit - (feet.x - size.x * 0.5), (feet.y - size.y * 0.5) - 0.475 / unit)

static func portrait(id: String) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEETS[id]
	atlas.region = PORTRAITS[id]
	atlas.filter_clip = true
	return atlas
