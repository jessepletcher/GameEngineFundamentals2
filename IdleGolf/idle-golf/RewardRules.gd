extends RefCounted
## Pure reward calculations. Context contains launch-time multipliers only.
## Returned money/XP are final amounts: never multiply them again at credit time.

const XP_PER_MONEY := 0.1
const DIRECT_HIT_MULT := 2.5
const GOLDEN_MULT := 50.0

static func money_multiplier(upgrade_level: int, level_mult: float, golfer_mult: float, ball_mult: float) -> float:
	return (1.0 + upgrade_level * 0.09) * level_mult * golfer_mult * ball_mult

static func base_reward(context: Dictionary, base_money: float, payout_multiplier: float = 1.0) -> Dictionary:
	var money: float = base_money * context.money_mult * payout_multiplier
	return {"money": money, "xp": money * XP_PER_MONEY * context.xp_mult}

static func flag_bonus(forward_distance: float, distance_mult: float, accuracy: float = 1.0) -> float:
	return maxf(forward_distance, 0.0) * 0.1 * distance_mult * clampf(accuracy, 0.0, 1.0)

static func landing(context: Dictionary, yards: float, bonus: float, direct: bool, payout_multiplier: float = 1.0) -> Dictionary:
	var base := yards * yards * 0.0002 + 5.0
	base += bonus * float(context.ball_data.get("flag_mult", 1.0))
	if direct:
		base *= DIRECT_HIT_MULT
	return base_reward(context, base, payout_multiplier)

static func pinball(context: Dictionary, bonus: float) -> Dictionary:
	# Chain arrivals earn a direct flag bonus, without another distance/base award.
	return base_reward(context, bonus * float(context.ball_data.get("flag_mult", 1.0)) * DIRECT_HIT_MULT)

static func golden(context: Dictionary, bonus: float, payout_multiplier: float = 1.0) -> Dictionary:
	# Separate from ordinary landing/chain money; no second direct-hit multiplier.
	return base_reward(context, bonus * float(context.ball_data.get("flag_mult", 1.0)) * GOLDEN_MULT, payout_multiplier)

static func destructible_hit(context: Dictionary, money_per_hit: float, distance_yards: float) -> Dictionary:
	# Each physical hit contributes once. Fragment-count compensation applies to
	# landing/flag rewards, not damage or the number of hits needed to break a target.
	return base_reward(context, money_per_hit * distance_yards * float(context.ball_data.get("destruct_mult", 1.0)))

static func scale_reward(reward: Dictionary, factor: float) -> Dictionary:
	# Market streaks/growth scale both accrued amounts without consulting equipment.
	return {"money": reward.money * factor, "xp": reward.xp * factor}
