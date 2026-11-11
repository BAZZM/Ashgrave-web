class_name AttackDef
extends Resource

enum Dir {LEFT, RIGHT, OVER, THRUST}

@export var dir: Dir = Dir.LEFT

@export var windup := 0.9
@export var damage := 18.0

@export var recover := 0.35

@export var heavy := false

@export var feint := false


static func make(d: Dir, windup_s: float, dmg: float, flags := "") -> AttackDef:
	var a := AttackDef.new()
	a.dir = d
	a.windup = windup_s
	a.damage = dmg
	a.heavy = flags.contains("h")
	a.feint = flags.contains("f")
	return a
