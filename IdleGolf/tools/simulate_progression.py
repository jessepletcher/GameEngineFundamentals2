"""Deterministic expected-value campaign model; see ECONOMY_BALANCE_UPDATE.txt.

Consumes a Godot snapshot of live stats, prices and target hitboxes. This is a
planning model, not a substitute for real fresh-save player/physics testing.
No player saves, game clock, completion flags or progression timers are edited.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass, field
import json
import math
from pathlib import Path

CASH = ["ball_speed", "fire_rate", "money_mult", "consistency", "xp_mult"]


def flight(speed, loft, height, damping=.1, gravity=9.8):
    """Continuous linear-drag solution, landing at Ball.gd's y=1 threshold."""
    terminal = gravity / damping
    lo, hi = .001, max(5, 2 * speed * loft / gravity + 5)
    for _ in range(24):
        t = (lo + hi) / 2
        y = height + (speed * loft + terminal) * (-math.expm1(-damping*t)) / damping - terminal*t
        if y > 1:
            lo = t
        else:
            hi = t
    return (lo + hi) / 2


@dataclass
class Campaign:
    data: dict
    policy: str = "balanced"
    income_factor: float = 1.0
    cadence: float = 60.0
    max_hours: float = 120.0
    price_override: tuple | None = None
    time: float = 0
    money: float = 0
    run_money: float = 0
    best: float = 0
    medals: float = 0
    xp: float = 0
    level: int = 1
    required: float = 100
    course: int = 1
    upgrades: dict = field(default_factory=dict)
    bonuses: dict = field(default_factory=lambda: dict.fromkeys(CASH, 0.0))
    golfer: str = "standard"
    ball: str = "standard"
    owned: set = field(default_factory=set)
    milestones: list = field(default_factory=list)
    finished: list = field(default_factory=list)
    targets: dict = field(default_factory=dict)
    retirements: int = 0
    first_purchase: float | None = None

    def __post_init__(self):
        self.upgrades = dict.fromkeys(self.data["upgrades"], 0)
        self.targets = {t["id"]: {"hits": 0, "pot": 0, "xp": 0, "cooldown": 0}
                        for c in self.data["courses"].values() for t in c["targets"]}
        self.owned = {"course1", "standard"}

    def cost(self, key):
        lv = self.upgrades[key]
        if self.price_override and key == "ball_speed" and lv > 60:
            exponent, scale = self.price_override
            return math.floor(10 * 1.08**60 * ((lv + scale) / (60 + scale))**exponent)
        return self.data["costs"][key][min(lv, 1500)]

    def stats(self):
        u, b, g = self.upgrades, self.bonuses, self.data["golfers"][self.golfer]
        speed = self.data["base_speed"] * (1 + .04*u["ball_speed"]) * (1+b["ball_speed"]) * g["speed_mult"]
        rate = (1 + .03*u["fire_rate"]) * (1+b["fire_rate"]) * g["fire_rate_mult"] / self.data["base_interval"]
        money = (1 + .09*u["money_mult"]) * (1+b["money_mult"]) * g["money_mult"] * self.data["balls"][self.ball]["money_mult"]
        consistency = (.5 + .1*u["consistency"]) * (1+b["consistency"]) * (1+.5*u["consistency_mult"])
        xp = (1+.09*u["xp_mult"]) * (1+b["xp_mult"])
        return speed, rate, money, consistency, xp

    def earn(self, money, xp):
        self.money += money
        self.run_money += money
        self.xp += xp
        while self.xp >= self.required:
            self.xp -= self.required
            self.level += 1
            self.required = math.floor(100*1.4**(self.level-1))
            self.bonuses[self.data["level_rewards"][(self.level-2) % 10]] += .05

    def medals_due(self):
        if self.run_money <= 1 or (self.best > 0 and self.run_money <= self.best):
            return 0
        raw = 16.67*math.log10(self.run_money) if self.best == 0 else 150*math.log2(self.run_money/self.best)
        return math.floor(250*(-math.expm1(-raw/250)))

    def retire(self):
        earned = self.medals_due()
        if earned < 5:
            return
        self.medals += earned
        self.best = max(self.best, self.run_money)
        self.run_money = self.money = 0
        for k in CASH:
            self.upgrades[k] = 0
        # Reloading the scene loses partial target damage, as in the real game.
        for t in self.targets.values():
            t.update(hits=0, pot=0, xp=0, cooldown=0)
        self.retirements += 1
        self.milestones.append({"event": "retirement", "hours": self.time/3600, "medals": earned})

    def shop(self):
        # Save for course access before optional items; later courses may be
        # purchased early but the model finishes them sequentially.
        for id in ["course2", "course3"]:
            item = self.data["catalog"][id]
            if id not in self.owned and self.level >= item["unlock_level"] and self.medals >= item["medal_cost"]:
                self.medals -= item["medal_cost"]
                self.owned.add(id)
                self.milestones.append({"event": "unlock " + id, "hours": self.time/3600})
        for id in ["power", "speedy", "Lion Trees"]:
            item = self.data["golfers"][id]
            if id not in self.owned and self.level >= item["unlock_level"] and self.medals >= item["medal_cost"]:
                self.medals -= item["medal_cost"]
                self.owned.add(id)
                self.milestones.append({"event": "unlock " + id, "hours": self.time/3600})
        self.golfer = next((g for g in ["Lion Trees", "power", "speedy"] if g in self.owned), "standard")
        item = self.data["balls"]["wrecking"]
        if "wrecking" not in self.owned and self.level >= item["unlock_level"] and self.medals >= item["medal_cost"]:
            self.medals -= item["medal_cost"]
            self.owned.add("wrecking")
        self.ball = "wrecking" if "wrecking" in self.owned else "standard"
        reserve = sum(self.data["catalog"][id]["medal_cost"] for id in ["course2", "course3"] if id not in self.owned)
        if "Lion Trees" not in self.owned:
            reserve += self.data["golfers"]["Lion Trees"]["medal_cost"]
        for key in ["consistency_mult", "multi_ball", "flat_distance", "multi_ball_spread"]:
            cap = min(3, self.data["upgrades"][key].get("max_level", 3))
            while self.upgrades[key] < cap and self.medals-reserve >= self.cost(key):
                self.medals -= self.cost(key)
                self.upgrades[key] += 1

    def buy(self):
        # Marginal utility per dollar. Speed includes access to new targets;
        # XP is indirect future income. No future rewards or free currency.
        weights = {"balanced": [3.0, 1, 1, .7, .25], "speed": [5, .7, .7, .5, .15],
                   "income": [1.5, 1.5, 1.5, .7, .4]}[self.policy]
        slopes = [.04, .03, .09, .2, .09]
        for _ in range(2000):
            key = max(CASH, key=lambda k: weights[CASH.index(k)] * slopes[CASH.index(k)] /
                      (1+slopes[CASH.index(k)]*self.upgrades[k]) / max(1, self.cost(k)))
            cost = self.cost(key)
            if self.money < cost or self.upgrades[key] >= 1499:
                break
            self.money -= cost
            self.upgrades[key] += 1
            if self.first_purchase is None:
                self.first_purchase = self.time/60

    def shot(self, target=None):
        speed, rate, mult, consistency, xp = self.stats()
        worst = max(.05, 1-1/consistency)
        whiff = min(.55, max(.02, .32/consistency))
        # Integrate the surviving uniform distance distribution. Whiffs earn
        # short-landing money and never count as a long target hit.
        low = worst + (1-worst)*whiff
        mean_distance = (low+1)/2
        horizontal = speed*mean_distance + self.upgrades["flat_distance"]
        aim, loft, valid = 0.0, .6, True
        if target:
            # Pyramids' three colliders share one damage pool. Choose a legal
            # aim, then integrate hits against the union of all its colliders.
            shape = min(target["shapes"], key=lambda s: math.hypot(s["position"][0], s["position"][2]))
            x, y, z = shape["position"]
            distance = math.hypot(x, z)
            aim = math.atan2(x, z)
            if horizontal <= distance*.1:
                valid = False
            else:
                t = -math.log1p(-.1*distance/horizontal)/.1
                loft = (max(1.1, y)-self.data["tee"][1]+98*t)/(distance/horizontal)/speed-98/speed
                valid = .05 <= loft <= .6 and abs(aim) <= math.radians(50)
        if not valid:
            return None
        duration = flight(speed, loft, self.data["tee"][1])
        drag_time = -math.expm1(-.1*duration)/.1
        spread = math.radians(self.data["base_spread"]/consistency)
        hit, landing = 0.0, 0.0
        samples = 24
        for i in range(samples):
            d = low+(1-low)*(i+.5)/samples
            v = speed*d + self.upgrades["flat_distance"]
            yards = v*drag_time*math.cos(aim)*1.094
            chance = 0.0
            if target:
                intervals = []
                for s in target["shapes"]:
                    x,y,z = s["position"]
                    hx,hy,hz = s["half"]
                    # Test near face, center, far face for the padded AABB.
                    intersects = False
                    for depth in [z-hz, z, z+hz]:
                        travel = depth / math.cos(aim)
                        if v <= .1*travel:
                            continue
                        t = -math.log1p(-.1*travel/v)/.1
                        height = self.data["tee"][1]+(speed*loft+98)*(travel/v)-98*t
                        if t <= duration and abs(height-y) <= hy:
                            intersects = True
                    if intersects:
                        a = max(-spread, math.atan2(x-hx,z)-aim)
                        b = min(spread, math.atan2(x+hx,z)-aim)
                        if b > a:
                            intervals.append((a,b))
                end = -math.inf
                for a,b in sorted(intervals):
                    chance += max(0,b-max(a,end))/(2*spread)
                    end = max(end,b)
                chance = min(1,chance)
            hit += chance*(1-whiff)/samples
            # A colliding shot stops near the target rather than earning its
            # unobstructed full-range landing payout as well.
            landed = (1-chance)*yards*yards + chance*(target["yards"]**2 if target else 0)
            landing += (5+.0002*landed)*(1-whiff)/samples
        landing += whiff*5
        # Fan balls are spread widely; conservatively count extra landing money
        # but not extra target damage. Do not pretend all balls hit one collider.
        landing *= 1+self.upgrades["multi_ball"]
        damage_reward = target["per_hit"]*target["yards"]*self.data["balls"][self.ball].get("destruct_mult",1) if target else 0
        target_rate = hit*rate
        average_damage_income = damage_reward*target_rate
        if target:
            average_damage_income /= 1+target_rate*target["respawn"]/target["hits"]
        return {"target": target, "rate": rate, "hits": target_rate, "landing": landing*mult*rate,
                "per_hit": damage_reward*mult, "xp_mult": xp,
                "income": (landing*mult*rate+average_damage_income*mult), "hit_probability": hit,
                "speed": speed, "loft": loft, "aim": aim}

    def run(self):
        step = 30.0
        next_buy = 0
        plan = None
        while self.time < self.max_hours*3600 and self.course <= 3:
            if self.time >= next_buy or plan is None:
                if self.retirements == 0 and self.time >= 1200:
                    self.retire()
                elif self.retirements == 1 and self.time >= 7200 and self.medals_due() >= 100:
                    self.retire()
                self.shop()
                self.buy()
                candidates = [self.shot()]
                for target in self.data["courses"][f"course{self.course}"]["targets"]:
                    candidate = self.shot(target)
                    if candidate:
                        candidates.append(candidate)
                final = next((c for c in candidates if c["target"] and c["target"]["final"] and c["hit_probability"] >= .15), None)
                plan = final or max(candidates, key=lambda c:c["income"])
                next_buy = self.time+self.cadence
            self.time += step
            landing = plan["landing"]*step*self.income_factor
            self.earn(landing, landing*.1*plan["xp_mult"])
            if plan["target"]:
                target = plan["target"]
                progress = self.targets[target["id"]]
                clock = self.time-step
                while clock < self.time and plan["hits"] > 0:
                    clock = max(clock, progress["cooldown"])
                    if clock >= self.time:
                        break
                    active = min(self.time-clock, (target["hits"]-progress["hits"])/plan["hits"])
                    hits = min(target["hits"]-progress["hits"], plan["hits"]*active)
                    reward = hits*plan["per_hit"]*self.income_factor
                    progress["hits"] += hits
                    progress["pot"] += reward
                    progress["xp"] += reward*.1*plan["xp_mult"]
                    clock += active
                    if progress["hits"] >= target["hits"]-1e-8:
                        self.earn(progress["pot"], progress["xp"])
                        progress.update(hits=0, pot=0, xp=0, cooldown=clock+target["respawn"])
                        if target["final"]:
                            self.finished.append({"course": self.course, "hours": self.time/3600,
                                "course_hours": self.time/3600-(self.finished[-1]["hours"] if self.finished else 0),
                                "level": self.level, "upgrades": dict(self.upgrades), "golfer": self.golfer,
                                "bonuses": dict(self.bonuses),
                                "ball": self.ball, "hit_probability": plan["hit_probability"],
                                "speed": plan["speed"], "loft": plan["loft"], "aim": plan["aim"]})
                            self.milestones.append({"event": f"complete course{self.course}", "hours":self.time/3600})
                            if self.course < 3:
                                self.retire()
                                self.shop()
                                if f"course{self.course+1}" not in self.owned:
                                    raise RuntimeError("Course access blocked by medal budget")
                            self.course += 1
                            plan = None
                            break
        return {"policy":self.policy, "income_factor":self.income_factor, "purchase_interval_seconds":self.cadence,
                "completed":len(self.finished)==3, "hours":self.time/3600, "first_purchase_minutes": self.first_purchase,
                "courses":self.finished, "milestones":self.milestones, "last_level":self.level,
                "last_upgrades":self.upgrades, "retirements":self.retirements}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("snapshot", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--power", type=float)
    p.add_argument("--scale", type=float, default=50)
    p.add_argument("--policy", choices=["balanced","speed","income"], default="balanced")
    p.add_argument("--income-factor", type=float, default=1)
    p.add_argument("--cadence", type=float, default=60)
    p.add_argument("--max-hours", type=float, default=120)
    a = p.parse_args()
    data = json.loads(a.snapshot.read_text())
    result = Campaign(data, a.policy, a.income_factor, a.cadence, a.max_hours,
                      (a.power,a.scale) if a.power else None).run()
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
