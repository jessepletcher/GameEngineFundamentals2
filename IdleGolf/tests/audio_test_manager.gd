extends "res://AudioManager.gd"
## Test-only autoload: exercise real mixing through Dummy without speaker output.
func _is_headless() -> bool:
	return false
