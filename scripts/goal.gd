class_name Goal
extends Resource

@export var id: StringName
@export var title := "Do it {n} times"
@export var stat: StringName
@export var start := 10.0
@export var growth := 10.0
@export var max_target := 0.0
@export var reward: StringName = &"acorn"
@export var reward_count := 3


func target(tier: int) -> float:
	var t := roundf(start * pow(growth, tier))
	return minf(t, max_target) if max_target > 0.0 else t


func maxed(tier: int) -> bool:
	return max_target > 0.0 and tier > 0 and target(tier - 1) >= max_target


func text(tier: int) -> String:
	return title.format({"n": int(target(tier))})


func reward_for(tier: int) -> int:
	return reward_count * (tier + 1)
