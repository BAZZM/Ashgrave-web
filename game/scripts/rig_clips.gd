extends RefCounted
## Clip names and section times for RigVisual (docs/RIG_PLAN.md section 3, corrected by R1's
## measurements of the sword tip in anims.glb). Times are clip seconds. Names live only here.

const SLICE := &"1H_Melee_Attack_Slice_Horizontal"
const CHOP := &"1H_Melee_Attack_Chop"
const STAB := &"1H_Melee_Attack_Stab"

## Per AttackDef.Dir (LEFT, RIGHT, OVER, THRUST): windup W, strike S, recovery R, each [from, to] in
## play order (a reversed clip runs from the larger time to the smaller). S ends at contact: the tip
## crosses the centre line in front (slice 0.255), drops level in front (chop 0.60) or is fully out (stab 0.44).
const ATTACK := {
	0: {"clip": SLICE, "w": [1.0667, 0.40], "s": [0.40, 0.255], "r": [0.255, 0.0]},
	1: {"clip": SLICE, "w": [0.0, 0.20], "s": [0.20, 0.255], "r": [0.255, 1.0667]},
	2: {"clip": CHOP, "w": [0.0, 0.533], "s": [0.533, 0.60], "r": [0.60, 1.0667]},
	3: {"clip": STAB, "w": [0.0, 0.333], "s": [0.333, 0.44], "r": [0.44, 1.6]},
}
## slash(dir): -1 L, 1 R, 2 U, 3 D -> the AttackDef.Dir whose S it plays.
const SLASH := {-1: 0, 1: 1, 2: 3, 3: 2}
const WINDUP_SHARE := 0.6

const IDLE := &"Idle"
const WALK := &"Walking_A"
const RUN := &"Running_A"
const BLOCKING := &"Blocking"
const BLOCK_HIT := &"Block_Hit"
const HIT := &"Hit_A"
const HIT_HEAVY := &"Hit_B"
const PICKUP := &"PickUp"
const DEATH := &"Death_A"
const DODGE_L := &"Dodge_Left"
const DODGE_R := &"Dodge_Right"
const TAUNT := &"Taunt"
const CHEER := &"Cheer"
const LOOPS := [IDLE, WALK, RUN, BLOCKING]

## Key clip times (pose the action is read by) for the one-shot actions.
const KEY := {
	&"stagger": 0.267, &"broken": 0.50, &"hit": 0.133, &"guard": 0.133, &"death": 0.533,
	&"taunt": 0.533, &"victory": 0.333,
}
## Seconds at which PlaceholderVisual reaches the same pose (its tween length, which ignores `duration`
## for these actions). RigVisual lands its key pose then.
const AT := {
	&"taunt": 0.5, &"stagger": 0.2, &"broken": 0.3, &"guard": 0.08, &"parry": 0.06, &"block": 0.1,
	&"dodge": 0.12, &"death": 0.9, &"victory": 0.5,
}
const DODGE_TIME := 0.46
const PARRY_HOLD := 0.08
const FEINT_NUDGE := 0.05
const BLEND := 0.12
const BLEND_FAST := 0.03
