extends RefCounted
## Every tunable number of the duel's feel and posture (docs/COMBAT_SPEC.md, Build 1).
## Constants only: no duel code holds a number of its own for these. Build 2 and 3
## add B2 and B3 here. Used as `const Tune := preload("res://scripts/combat_tune.gd")`
## and read as `Tune.B1.cut_freeze`.
##
## Times are real seconds unless the name says "game". Real seconds do not stretch
## with slow motion or the bots' 4x clock.

## Combat version carried as `cv` on PvP cards. Missing = 1 (the game before Build 1).
## Both players run min(mine, theirs): below 2 the old defence rules apply.
const CV := 2

const B1 := {
	# ---- Feel: a cut lands on an open foe ----
	cut_freeze = 0.06,          # hit-stop on contact (was 0.045)
	cut_shake = 0.35,           # camera shake (unchanged)
	cut_recoil = 0.12,          # foe body pushed this far along the cut, in duel units
	cut_recoil_out = 0.04,      # ...taking this long
	cut_recoil_back = 0.12,     # ...and returning in this long
	cut_kick = 0.06,            # camera kick toward the swipe (h/v offset)
	cut_kick_time = 0.12,       # kick decay time

	# ---- Feel: chain ender ----
	ender_freeze = 0.11,        # was 0.09
	ender_fov = 48.0,           # was 50
	ender_shake = 0.9,          # unchanged
	ender_flash = Color(1, 1, 1),   # white flash on the foe
	ender_sparks = 22,          # second spark burst

	# ---- Feel: parry ----
	parry_slow = 0.5,           # plain parry: slow-motion scale (was 0.25)
	parry_slow_time = 0.15,     # ...for this long (was 0.22)
	parry_fov = 51.0,           # was 49
	parry_shake = 0.7,          # unchanged
	perfect_freeze = 0.06,      # perfect parry: freeze first...
	perfect_slow = 0.25,        # ...then slow motion at this scale
	perfect_slow_time = 0.30,   # ...for this long
	perfect_fov = 46.0,
	perfect_edge = Color(1.0, 0.82, 0.35),   # gold edge flash
	perfect_sparks = 26,

	# ---- Feel: posture broken (foe) ----
	break_freeze = 0.10,
	break_slow = 0.35,
	break_slow_time = 0.5,

	# ---- Feel: being hurt, blocking, posture broken (player) ----
	hurt_shake = 1.0,           # ordinary hit (unchanged)
	hurt_big_frac = 0.15,       # a hit this fraction of max HP or more is "heavy"
	hurt_big_shake = 1.3,       # was 1.0
	block_shake = 0.5,          # unchanged; the sound is layer L6 now
	pbreak_edge = Color(0.35, 0.55, 1.0),    # blue edge flash
	pbreak_pitch = 0.8,         # layer L4 plays at this pitch factor for the player

	# ---- Finisher camera (FINISHER and posture break/execution) ----
	fin_x = 2.0,                # side of the foe, duel units (sign picked away from other foes)
	fin_y = 1.2,
	fin_z_off = 0.3,            # added to the z midway between the fighters
	fin_fov = 50.0,
	fin_time = 0.4,             # move-in time
	fin_ground_clear = 0.5,     # the camera stays this far above the ground (open land)
	fin_freeze = 0.15,          # contact freeze when the killing blow lands
	fin_slow = 0.25,            # slow motion while the foe waits to be finished (unchanged)
	fin_slow_time = 3.2,        # (unchanged)
	push_time = 0.15,           # on the deciding swipe: push in...
	push_frac = 0.65,           # ...this much of the way to the foe
	push_fov = 42.0,
	push_freeze = 0.15,
	push_slow = 0.3,
	push_slow_time = 0.8,
	ease_back = 0.5,            # then back to the normal camera

	# ---- Sound ----
	pitch_layers = true,        # false: layers ignore pitch (volume-only fallback)
	layer_gap_ms = 40,          # the same layer is skipped if started this recently
	sfx_pool = 12,              # players in the pool (was 8)

	# ---- Posture: foe gains (all multiplied by the weapon's break_mult) ----
	gain_parry = 0.5,           # x break_per_parry
	gain_perfect = 1.6,         # x break_per_parry
	gain_perfect_block = 12.0,
	gain_perfect_dodge = 10.0,
	gain_cut = 3.0,             # a cut while the foe is open
	gain_ender = 12.0,          # a chain ender
	gain_ranged = 15.0,         # ranged interrupt
	gain_frost = 25.0,          # Frost Bind
	gain_surge = 60.0,          # plus the surge's damage

	# ---- Posture: foe drain (game seconds) ----
	drain_delay = 2.5,          # starts this long after the posture last rose
	drain_rate = 5.0,           # per second, times (floor + weight x HP fraction)
	drain_hp_floor = 0.3,
	drain_hp_weight = 0.7,
	drain_enrage = 1.25,        # times this while enraged

	# ---- Posture: full bar and execution ----
	exec_window = 2.2,          # game seconds the foe stays open for the execution
	exec_miss_posture = 0.5,    # posture kept (fraction of full) if the window is missed
	exec_after_open = 1.0,      # game seconds open "broken" after an execution that does not kill
	exec_share = {"wild": 1.0, "lesser": 1.0, "elite": 0.6, "guardian": 0.4},   # of max HP

	# ---- Posture: the player's ----
	p_gain_hit = 0.3,           # x damage of a hit taken
	p_gain_whiff = 6.0,
	p_drain_delay = 1.0,        # game seconds without a gain before it drains
	p_drain_rate = 3.0,         # per second, not while blocking
	p_classic_rate = 2.0,       # the old shield refill, kept for classic PvP
	p_stun = 1.1,               # game seconds
	p_stun_warden = 0.5,        # with the Warden set
	p_reset = 0.5,              # posture after the stun, fraction of full

	# ---- Posture in player-vs-player (both sides at version 2 or more) ----
	pvp_parried_base = 34.0,    # percent; x 0.5 (parry) or x 1.6 (perfect) to the parried player
	pvp_broken_time = 2.5,      # real seconds the broken player can be executed (`pb`)
	pvp_grace = 0.5,            # extra real seconds the broken player still accepts an execution (message delay)
	pvp_exec_share = 0.3,       # of the broken player's own max HP
}

## Sound layers: lists of [sound, volume dB, pitch, delay s, pitch jitter].
## A delay runs on a timer that ignores time scale.
const LAYERS := {
	"L1": [["hit", 0.0, 1.0, 0.0, 0.15], ["whoosh", -10.0, 1.25, 0.0, 0.0]],
	"L2": [["hit", 1.0, 0.85, 0.0, 0.0], ["clang", -6.0, 0.75, 0.0, 0.0], ["break", -14.0, 1.3, 0.0, 0.0]],
	"L3": [["clang", 0.0, 1.0, 0.0, 0.0], ["clang", -5.0, 1.45, 0.03, 0.0], ["break", -12.0, 1.2, 0.0, 0.0]],
	"L4": [["break", 0.0, 0.8, 0.0, 0.0], ["clang", -4.0, 0.6, 0.0, 0.0]],
	"L5": [["hurt", 0.0, 1.0, 0.0, 0.08], ["hit", -4.0, 0.7, 0.0, 0.0]],
	"L6": [["block", 0.0, 1.0, 0.0, 0.08], ["clang", -14.0, 0.6, 0.0, 0.0]],
	"L7": [["finish", 2.0, 1.0, 0.0, 0.0], ["hit", 2.0, 0.7, 0.0, 0.0], ["break", -6.0, 0.9, 0.06, 0.0]],
}
