class_name EnemyDef
extends Resource

@export var display_name := "The Cinder Warden"
@export var title := "Guardian of the first stair"
@export var max_hp := 240.0

@export var speed := 1.0
@export var idle_gap := 1.1
@export var winded_time := 1.1
@export var stagger_time := 1.25
@export var break_time := 2.4
@export var break_max := 100.0
@export var break_per_parry := 34.0

var weak := ""
var resist := ""
var kind := "guardian"

var ranged := false

var side_damage: float:
	get:
		return (combos[0][0] as AttackDef).damage * 0.8 if not combos.is_empty() else 10.0
var combos: Array = []
var enraged_combos: Array = []

var look := {}


static func make_for(floor_n: int, loop: int) -> EnemyDef:
	var e := EnemyDef.new()
	var L := AttackDef.Dir.LEFT
	var R := AttackDef.Dir.RIGHT
	var O := AttackDef.Dir.OVER
	var T := AttackDef.Dir.THRUST
	var m := AttackDef.make
	var d := 15.0
	match floor_n:
		1:
			e.display_name = "The Cinder Warden"
			e.title = "Guardian of the first stair"
			e.max_hp = 230.0
			e.look = {"style": "knight", "scale": 1.45, "body": Color(0.42, 0.36, 0.38), "accent": Color(0.85, 0.3, 0.1)}
			e.combos = [
				[m.call(L, 1.0, d)], [m.call(R, 1.0, d)], [m.call(O, 1.15, d * 1.3)],
				[m.call(L, 0.95, d), m.call(R, 0.75, d)],
				[m.call(T, 1.1, d * 1.2)],
			]
			e.enraged_combos = [
				[m.call(R, 0.9, d), m.call(O, 0.8, d * 1.3)],
				[m.call(L, 0.85, d), m.call(R, 0.65, d), m.call(O, 0.8, d * 1.3)],
			]
		2:
			e.display_name = "Ashbound Duelist"
			e.title = "She has never been touched"
			e.max_hp = 200.0
			e.speed = 1.22
			e.idle_gap = 0.8
			e.stagger_time = 1.2
			d = 12.0
			e.look = {"style": "duelist", "scale": 1.45, "body": Color(0.5, 0.48, 0.42), "accent": Color(0.2, 0.55, 0.5)}
			e.combos = [
				[m.call(L, 0.9, d), m.call(R, 0.6, d)],
				[m.call(R, 0.9, d), m.call(L, 0.6, d)],
				[m.call(L, 1.0, d, "f")], [m.call(R, 1.0, d, "f")],
				[m.call(T, 0.95, d * 1.2), m.call(L, 0.6, d)],
				[m.call(L, 0.85, d), m.call(R, 0.55, d), m.call(L, 0.55, d)],
			]
			e.enraged_combos = [
				[m.call(R, 0.8, d), m.call(L, 0.5, d), m.call(R, 0.5, d), m.call(T, 0.7, d * 1.2)],
				[m.call(O, 1.0, d * 1.3, "f"), m.call(L, 0.55, d)],
			]
		3:
			e.display_name = "Gravemaul"
			e.title = "The weight of the mountain"
			e.max_hp = 360.0
			e.speed = 0.88
			e.idle_gap = 1.3
			e.winded_time = 1.5
			e.break_per_parry = 26.0
			d = 21.0
			e.look = {"style": "brute", "scale": 1.85, "body": Color(0.3, 0.27, 0.25), "accent": Color(0.55, 0.15, 0.6)}
			e.combos = [
				[m.call(O, 1.3, d * 1.5, "h")],
				[m.call(L, 1.1, d)], [m.call(R, 1.1, d)],
				[m.call(L, 1.1, d), m.call(O, 1.0, d * 1.5, "h")],
				[m.call(T, 1.2, d * 1.2)],
			]
			e.enraged_combos = [
				[m.call(R, 1.0, d), m.call(L, 0.8, d), m.call(O, 1.0, d * 1.5, "h")],
				[m.call(L, 1.1, d, "hf")],
			]
		4:
			e.display_name = "Keeper of the Grave Gate"
			e.title = "None have passed"
			e.max_hp = 320.0
			e.speed = 1.1
			d = 18.0
			e.look = {"style": "sentinel", "scale": 1.55, "body": Color(0.22, 0.25, 0.36), "accent": Color(0.85, 0.72, 0.3)}
			e.combos = [
				[m.call(L, 0.95, d), m.call(R, 0.7, d)],
				[m.call(O, 1.1, d * 1.4, "h")],
				[m.call(R, 1.0, d, "f"), m.call(L, 0.6, d)],
				[m.call(T, 1.0, d * 1.2), m.call(O, 0.8, d * 1.3)],
				[m.call(L, 0.9, d), m.call(L, 0.7, d), m.call(R, 0.6, d)],
			]
			e.enraged_combos = [
				[m.call(R, 0.8, d), m.call(L, 0.6, d), m.call(T, 0.7, d * 1.2), m.call(O, 0.8, d * 1.4, "h")],
				[m.call(O, 1.0, d * 1.3, "f"), m.call(R, 0.6, d), m.call(L, 0.55, d)],
			]
		_:
			e.display_name = "The Hollow Regent"
			e.title = "King of ash, lord of nothing"
			var usurper: bool = Run.data.get("flags", {}).has("throne")
			e.max_hp = 460.0
			e.speed = 1.15
			e.idle_gap = 0.9
			e.break_per_parry = 26.0
			d = 20.0
			e.look = {"style": "boss", "scale": 1.75, "body": Color(0.14, 0.13, 0.17), "accent": Color(1.0, 0.45, 0.1)}
			if usurper:
				var mine := Run.look()
				e.display_name = "The Usurper King"
				e.look = {"style": "boss", "scale": 1.75, "body": mine.body, "accent": mine.accent}
			e.combos = [
				[m.call(L, 0.9, d), m.call(R, 0.65, d), m.call(O, 0.8, d * 1.4)],
				[m.call(O, 1.15, d * 1.6, "h")],
				[m.call(T, 0.95, d * 1.2), m.call(L, 0.6, d)],
				[m.call(R, 1.0, d, "f"), m.call(L, 0.55, d), m.call(R, 0.55, d)],
				[m.call(L, 0.95, d, "h"), m.call(T, 0.8, d * 1.2)],
			]
			e.enraged_combos = [
				[m.call(L, 0.75, d), m.call(R, 0.55, d), m.call(L, 0.55, d), m.call(R, 0.55, d), m.call(O, 0.8, d * 1.6, "h")],
				[m.call(T, 0.8, d * 1.2), m.call(T, 0.7, d * 1.2), m.call(O, 0.9, d * 1.4, "f")],
			]
	e.weak = ["frost", "storm", "ember", "frost", "storm"][clampi(floor_n, 1, 5) - 1]
	e.resist = ["ember", "frost", "storm", "ember", "ember"][clampi(floor_n, 1, 5) - 1]

	var hp_mul := 1.35 * (1.0 + 0.3 * loop)
	var dmg_mul := 1.0 + 0.2 * loop
	e.max_hp *= hp_mul
	e.speed = minf(e.speed + 0.05 * loop, 1.7)
	for pool in [e.combos, e.enraged_combos]:
		for c in pool:
			for a in c:
				a.damage *= dmg_mul
	return e


static func make_encounter(kind_s: String, tier: int, loop: int) -> EnemyDef:
	var e: EnemyDef
	match kind_s:
		"elite":
			var arche: int = [2, 3, 4, 1, 4][tier - 1]
			e = make_for(arche, loop)
			e.display_name = "Sworn " + ["Blade", "Maul", "Keeper", "Warden", "Keeper"][tier - 1]
			e.title = ""
			e.max_hp *= 0.7
			_scale_damage(e, 1.0 + 0.12 * (tier - arche))
			e.look.scale = float(e.look.scale) * 0.9
		"lesser":
			var arche2: int = [1, 1, 2, 2, 1][tier - 1]
			e = make_for(arche2, loop)
			e.display_name = Tiers.LESSER_NAMES[tier - 1]
			e.title = ""
			e.max_hp *= 0.38
			e.enraged_combos = []
			_scale_damage(e, 0.8 + 0.1 * (tier - arche2))
			var th: Dictionary = Tiers.THEMES[tier]
			e.look = {"style": "knight" if arche2 == 1 else "duelist", "scale": 1.15, "body": (th.stone as Color).lightened(0.15), "accent": th.light}
		_:
			e = make_for(tier, loop)
	e.kind = kind_s

	e.max_hp *= 1.5 + 0.45 * (tier - 1)
	_scale_damage(e, 1.25 + 0.3 * (tier - 1))
	return e


static func make_wild(id: String) -> EnemyDef:
	var f: Dictionary = Land.FOES[id]
	var e := make_for(int(f.arche), 0)
	e.display_name = f.name
	e.title = ""
	e.kind = "wild"
	e.max_hp *= float(f.hp)
	_scale_damage(e, float(f.dmg))
	if int(f.level) < 20:
		e.enraged_combos = []
	e.look = {"style": f.style, "scale": f.scale, "body": f.body, "accent": f.accent}
	var d := 14.0 * float(f.dmg)
	var T := AttackDef.Dir.THRUST
	var O := AttackDef.Dir.OVER
	match f.get("ranged", ""):
		"archer":
			e.ranged = true
			e.title = "archer"
			e.look["over"] = {"back_bow": true, "blade": [0.7, 0.05]}
			e.combos = [[AttackDef.make(T, 1.0, d)], [AttackDef.make(T, 0.9, d), AttackDef.make(T, 0.6, d)],
				[AttackDef.make(T, 0.8, d), AttackDef.make(T, 0.55, d), AttackDef.make(T, 0.55, d)]]
			e.enraged_combos = []
		"caster":
			e.ranged = true
			e.title = "caster"
			e.look["over"] = {"focus": f.accent, "cape": 1.0, "blade": [1.2, 0.035], "runes": true, "rune_color": f.accent}
			e.combos = [[AttackDef.make(O, 1.15, d * 1.3, "h")], [AttackDef.make(O, 1.25, d * 1.3, "hf")],
				[AttackDef.make(T, 0.95, d), AttackDef.make(O, 0.8, d * 1.3, "h")]]
			e.enraged_combos = [[AttackDef.make(O, 0.9, d * 1.3, "h"), AttackDef.make(O, 0.8, d * 1.3, "h")]]
	return e


static func _scale_damage(e: EnemyDef, k: float) -> void:
	for pool in [e.combos, e.enraged_combos]:
		for c in pool:
			for a in c:
				a.damage *= k
