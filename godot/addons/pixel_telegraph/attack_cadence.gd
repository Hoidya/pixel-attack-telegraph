class_name PixelAttackCadence
extends RefCounted
## Per-enemy rhythm helper: random-but-controlled gaps between attacks, and
## attack picking without immediate repeats.
##
## Gaps come from a shuffle bag of tiers (default [SHORT, MID, MID, LONG] =
## 25/50/25 %) and two SHORT gaps never happen back to back.
## The gap is measured from the END of the previous attack's recovery
## (never from the warning start), so recovery windows stay intact.

enum Tier { SHORT, MID, LONG }

var short_range := Vector2(1.0, 1.4)
var mid_range := Vector2(1.6, 2.4)
var long_range := Vector2(2.5, 3.0)
var tier_bag_template: Array = [Tier.SHORT, Tier.MID, Tier.MID, Tier.LONG]
var rng := RandomNumberGenerator.new()

var last_tier := -1
var last_attack: Variant = null
var _tier_bag: Array = []
var _attack_bag: Array = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Configure from an overall gap range split into 3 tiers (default 1.0-3.0 s).
func set_gap_range(min_s: float, max_s: float) -> void:
	var span := max_s - min_s
	short_range = Vector2(min_s, min_s + span * 0.2)
	mid_range = Vector2(min_s + span * 0.3, min_s + span * 0.7)
	long_range = Vector2(min_s + span * 0.75, max_s)


func next_tier() -> int:
	if _tier_bag.is_empty():
		_tier_bag = tier_bag_template.duplicate()
		_shuffle(_tier_bag)
	var tier: int = _tier_bag.pop_back()
	if tier == Tier.SHORT and last_tier == Tier.SHORT:
		# swap with a non-short tier still in the bag, or fall back to MID
		var j := -1
		for k in _tier_bag.size():
			if _tier_bag[k] != Tier.SHORT:
				j = k
				break
		if j >= 0:
			var other: int = _tier_bag[j]
			_tier_bag[j] = tier
			tier = other
		else:
			tier = Tier.MID
	last_tier = tier
	return tier


## Seconds to wait (after recovery ends) before asking for the next attack.
func next_gap() -> float:
	var r: Vector2
	match next_tier():
		Tier.SHORT:
			r = short_range
		Tier.MID:
			r = mid_range
		_:
			r = long_range
	return rng.randf_range(r.x, r.y)


## Picks the next attack id from `ids`, never the same one twice in a row.
func next_attack(ids: Array) -> Variant:
	if ids.is_empty():
		return null
	if ids.size() == 1:
		last_attack = ids[0]
		return ids[0]
	if _attack_bag.is_empty():
		_attack_bag = ids.duplicate()
		_shuffle(_attack_bag)
		if _attack_bag.back() == last_attack:
			_attack_bag.reverse()
	var pick: Variant = _attack_bag.pop_back()
	last_attack = pick
	return pick


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
