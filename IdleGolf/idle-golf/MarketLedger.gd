extends RefCounted
## Persistent, scene-independent accrued rewards. Keys are course/flag identities.
const Rules = preload("res://RewardRules.gd")
const GROWTH_RATE := 0.0002
const MAX_GROWTH_PER_SECOND := 5.0
const MAX_STREAK_MULTIPLIER := 10
const MAX_STREAK := 9007199254740991
var pots: Dictionary = {}
var streak_key := ""
var streak_count := 0

func deposit(key: String, reward: Dictionary) -> Dictionary:
	streak_count = mini(streak_count + 1, MAX_STREAK) if key == streak_key else 1
	streak_key = key
	var added := Rules.scale_reward(reward, float(mini(streak_count, MAX_STREAK_MULTIPLIER)))
	var pot: Dictionary = pots.get(key, {"money": 0.0, "xp": 0.0})
	pots[key] = {"money": pot.money + added.money, "xp": pot.xp + added.xp}
	return added

func grow(delta: float) -> void:
	if delta <= 0.0:
		return
	var principal: float = total().money
	if principal <= 0.0:
		return
	# A single shared ceiling prevents splitting pots to multiply interest.
	# Integrate exactly across the exponential/linear boundary, independent of FPS.
	var threshold := MAX_GROWTH_PER_SECOND / GROWTH_RATE
	var exponential_time := minf(delta, maxf(0.0, log(threshold / principal) / GROWTH_RATE))
	var grown := principal * exp(GROWTH_RATE * exponential_time) + MAX_GROWTH_PER_SECOND * (delta - exponential_time)
	var factor := grown / principal
	for key in pots:
		pots[key] = Rules.scale_reward(pots[key], factor)

func total() -> Dictionary:
	var reward := {"money": 0.0, "xp": 0.0}
	for pot in pots.values():
		reward.money += pot.money
		reward.xp += pot.xp
	return reward

func clear() -> void:
	pots.clear()
	streak_key = ""
	streak_count = 0

static func validate(pots_value: Variant, key: Variant, count: Variant) -> String:
	if typeof(pots_value) != TYPE_DICTIONARY or typeof(key) != TYPE_STRING or typeof(count) != TYPE_INT:
		return "Invalid Market data types."
	if count < 0 or count > MAX_STREAK or (key.is_empty() != (count == 0)):
		return "Invalid Market streak."
	if not key.is_empty() and not pots_value.has(key):
		return "Market streak has no investment."
	if pots_value.is_empty() != key.is_empty():
		return "Market investments and streak disagree."
	var sums := {"money": 0.0, "xp": 0.0}
	for id in pots_value:
		if typeof(id) != TYPE_STRING or id.split("/").size() != 2 or id.get_slice("/", 0).is_empty() or id.get_slice("/", 1).is_empty():
			return "Invalid Market target identity."
		var pot: Variant = pots_value[id]
		if typeof(pot) != TYPE_DICTIONARY or pot.size() != 2 or not pot.has("money") or not pot.has("xp"):
			return "Invalid Market investment."
		for field in ["money", "xp"]:
			var value: Variant = pot[field]
			if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or value < 0:
				return "Invalid Market reward."
			sums[field] += value
			if not is_finite(sums[field]):
				return "Market total is out of range."
	return ""
