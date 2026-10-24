extends RefCounted
## C05: one price schedule for buying, refunds, UI and progression analysis.
## Early speed prices retain the introductory curve. The middle stretch funds
## campaign progress; the linear tail keeps the furthest targets affordable.
const SPEED_KNEE := 60
const SPEED_TAIL := 265
const SPEED_POWER := 13.2
const SPEED_OFFSET := 50.0

static func upgrade_cost(key: String, base: float, level: int) -> float:
	var lv := maxi(0, level)
	match key:
		"ball_speed":
			if lv <= SPEED_KNEE:
				return floor(base * pow(1.08, lv))
			var middle := pow((minf(lv, SPEED_TAIL) + SPEED_OFFSET) / (SPEED_KNEE + SPEED_OFFSET), SPEED_POWER)
			var tail := maxf(1.0, (lv + SPEED_OFFSET) / (SPEED_TAIL + SPEED_OFFSET))
			return floor(base * pow(1.08, SPEED_KNEE) * middle * tail)
		"multi_ball":
			return base + 75.0 * lv
		"multi_ball_spread":
			return base + 10.0 * lv
		"consistency_mult":
			return base + 25.0 * lv
		"flat_distance":
			return base + 4.0 * lv
	return floor(base * pow(1.08, lv))

static func retirement_reward(run_money: float, best_run_money: float) -> float:
	if run_money <= 1.0 or (best_run_money > 0.0 and run_money <= best_run_money):
		return 0.0
	var raw := 16.67 * log(run_money) / log(10.0) if best_run_money <= 0.0 else 150.0 * log(run_money / best_run_money) / log(2.0)
	return floor(250.0 * (1.0 - exp(-raw / 250.0)))
