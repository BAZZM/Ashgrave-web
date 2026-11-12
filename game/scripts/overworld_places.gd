extends Node

const Kit := preload("res://scripts/overworld_kit.gd")
const NPC_LOOKS := {
	"elder": {"style": "sentinel", "scale": 0.95, "body": Color(0.5, 0.48, 0.52), "accent": Color(0.75, 0.75, 0.9), "over": {"cape": 1.1, "wings": false}},
	"alchemist": {"style": "duelist", "scale": 0.95, "body": Color(0.3, 0.4, 0.32), "accent": Color(0.4, 0.9, 0.5), "over": {"focus": Color(0.4, 1.0, 0.5), "cape": 0.9}},
	"fisher": {"style": "duelist", "scale": 0.95, "body": Color(0.4, 0.42, 0.46), "accent": Color(0.3, 0.5, 0.7), "over": {"plume": false}},
	"ranger": {"style": "duelist", "scale": 1.05, "body": Color(0.26, 0.34, 0.22), "accent": Color(0.6, 0.45, 0.2), "over": {"back_bow": true, "cape": 0.9}},
	"villager": {"style": "duelist", "scale": 0.92, "body": Color(0.5, 0.42, 0.34), "accent": Color(0.55, 0.3, 0.2), "over": {"plume": false, "half_cape": false}},
}
const WALK_LOOPS := [
	[Vector2(-10, 14), Vector2(8, 12), Vector2(16, 30), Vector2(0, 44), Vector2(-18, 34)],
	[Vector2(20, 14), Vector2(26, 40), Vector2(4, 46), Vector2(-6, 30)],
	[Vector2(-24, 14), Vector2(-28, 30), Vector2(-12, 46), Vector2(-4, 20)],
]

var ow: Overworld


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _build_tower() -> void:
	var dark := Kit.mat("tower", Color(0.11, 0.1, 0.12), 0.85)
	var base := Vector3(Land.TOWER.x, 0.8, Land.TOWER.y)
	Kit._part(ow, MeshKit.lathe([[17.0, -2.0], [15.0, 6.0], [12.5, 40.0], [11.5, 95.0], [14.0, 104.0], [14.0, 110.0], [9.0, 112.0], [0.0, 126.0]], 14), base, dark)
	var fire := SphereMesh.new()
	fire.radius = 5.0
	fire.height = 9.0
	Kit._part(ow, fire, base + Vector3(0, 116, 0), Kit.mat("pyre", Color(1.0, 0.45, 0.1), 0.5, 5.0))
	var beacon := OmniLight3D.new()
	beacon.position = base + Vector3(0, 60, 16)
	beacon.light_color = Color(1.0, 0.5, 0.2)
	beacon.light_energy = 4.0
	beacon.omni_range = 70.0
	ow.add_child(beacon)
	var g := Vector3(Land.TOWER_GATE.x, 0.8, Land.TOWER_GATE.y)
	var post := BoxMesh.new()
	post.size = Vector3(1.4, 8.0, 1.4)
	Kit._part(ow, post, g + Vector3(-3.4, 4, -5), dark)
	Kit._part(ow, post, g + Vector3(3.4, 4, -5), dark)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(9.0, 1.4, 1.8)
	Kit._part(ow, lintel, g + Vector3(0, 8.4, -5), dark)
	var veil := StandardMaterial3D.new()
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.albedo_color = Color(1.0, 0.45, 0.15, 0.4)
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(5.4, 7.6)
	Kit._part(ow, q, g + Vector3(0, 3.8, -5), veil)


func _spawn_walkers() -> void:
	for i in WALK_LOOPS.size():
		var wv := PlaceholderVisual.new()
		ow.add_child(wv)
		var look: Dictionary = NPC_LOOKS.villager.duplicate()
		look.body = [Color(0.5, 0.42, 0.34), Color(0.36, 0.4, 0.5), Color(0.45, 0.5, 0.36)][i]
		wv.configure(look)
		var start: Vector2 = WALK_LOOPS[i][0]
		ow._walkers.append({"id": "villager", "type": "npc", "pos": Vector3(start.x, Land.walk_height(start.x, start.y), start.y), "label": "Villager",
			"height": 2.2, "node": wv, "loop": WALK_LOOPS[i], "at": 0, "pause": 0.0})


func _add_house(chunk: Dictionary, h: Vector2) -> void:
	var n := Node3D.new()
	n.position = Vector3(h.x, Land.height(h.x, h.y), h.y)
	n.rotation.y = atan2(Land.VILLAGE.x - h.x, Land.VILLAGE.y - h.y)
	chunk.root.add_child(n)
	Kit._part(n, Kit.mesh("house"), Vector3(0, 1.6, 0), Kit.mat("plaster", Color(0.62, 0.56, 0.45)))
	Kit._part(n, Kit.mesh("roof"), Vector3(0, 3.2, 0), Kit.mat("thatch", Color(0.4, 0.22, 0.14)), Vector3(0, 45, 0), Vector3(1.0, 1.0, 0.86))
	var door := BoxMesh.new()
	door.size = Vector3(1.1, 2.0, 0.1)
	Kit._part(n, door, Vector3(0, 1.0, 3.02), Kit.mat("wood", Color(0.34, 0.22, 0.12)))
	var win := BoxMesh.new()
	win.size = Vector3(0.9, 0.8, 0.1)
	Kit._part(n, win, Vector3(2.2, 1.8, 3.02), Kit.mat("window", Color(1.0, 0.8, 0.4), 0.5, 2.0))
	chunk.obstacles.append(Vector3(h.x, h.y, 4.4))


func _add_place(chunk: Dictionary, pl: Dictionary) -> void:
	var p: Vector2 = pl.pos
	var pos := Vector3(p.x, Land.walk_height(p.x, p.y), p.y)
	var n := Node3D.new()
	n.position = pos
	chunk.root.add_child(n)
	var e := {"id": pl.id, "type": pl.type, "pos": pos, "label": pl.label, "height": 2.4, "node": n}
	var stone := Kit.mat("stone_solo", Color(0.4, 0.38, 0.36))
	var wood := Kit.mat("wood", Color(0.34, 0.22, 0.12))
	match pl.type:
		"smith", "store", "task":
			var look: Dictionary = {
				"smith": {"style": "knight", "scale": 1.0, "body": Color(0.45, 0.32, 0.2), "accent": Color(0.9, 0.7, 0.3)},
				"store": {"style": "duelist", "scale": 1.0, "body": Color(0.5, 0.42, 0.3), "accent": Color(0.3, 0.6, 0.3)},
				"task": {"style": "sentinel", "scale": 1.05, "body": Color(0.3, 0.3, 0.36), "accent": Color(0.8, 0.25, 0.2)},
			} [pl.type]
			var v := PlaceholderVisual.new()
			n.add_child(v)
			v.configure(look)
			v.rotation.y = atan2(- (Land.VILLAGE.x - p.x), - (Land.VILLAGE.y - p.y))
			var stall := BoxMesh.new()
			stall.size = Vector3(2.6, 1.0, 0.9)
			Kit._part(n, stall, Vector3(0, 0.5, 0).rotated(Vector3.UP, 0) + Vector3(sin(v.rotation.y) * -1.2, 0, cos(v.rotation.y) * -1.2), wood, Vector3(0, rad_to_deg(v.rotation.y), 0))
		"station":
			e.skill = pl.skill
			match pl.skill:
				"smithing":
					var blk := BoxMesh.new()
					blk.size = Vector3(0.7, 0.7, 0.7)
					Kit._part(n, blk, Vector3(0, 0.35, 0), wood)
					Kit._part(n, MeshKit.lathe([[0.3, 0.0], [0.2, 0.12], [0.2, 0.3], [0.5, 0.42], [0.5, 0.55], [0.0, 0.56]], 4, 1.7, 0.8), Vector3(0, 0.7, 0), Kit.mat("anvil", Color(0.2, 0.2, 0.23), 0.4))
				"cooking":
					Kit._part(n, MeshKit.lathe([[0.9, 0.0], [0.8, 0.25], [0.0, 0.3]], 8), Vector3.ZERO, stone)
					var fire := SphereMesh.new()
					fire.radius = 0.4
					fire.height = 0.9
					Kit._part(n, fire, Vector3(0, 0.6, 0), Kit.mat("fire", Color(1.0, 0.55, 0.15), 0.5, 4.0))
					_fire_light(n)
				"alchemy":
					var tbl := BoxMesh.new()
					tbl.size = Vector3(1.8, 0.9, 0.9)
					Kit._part(n, tbl, Vector3(0, 0.45, 0), wood)
					for i in 3:
						Kit._part(n, MeshKit.lathe([[0.0, 0.0], [0.12, 0.02], [0.14, 0.16], [0.05, 0.26], [0.05, 0.36], [0.0, 0.37]], 8), Vector3(-0.5 + i * 0.5, 0.9, 0),
							Kit.mat("vial%d" % i, [Color(0.3, 1.0, 0.5), Color(0.8, 0.4, 1.0), Color(1.0, 0.6, 0.2)][i], 0.2, 2.0))
				"fletching":
					var bench := BoxMesh.new()
					bench.size = Vector3(2.0, 0.8, 0.8)
					Kit._part(n, bench, Vector3(0, 0.4, 0), wood)
					Kit._part(n, MeshKit.horn(Vector3(0, -0.6, 0), Vector3(0, 0.6, 0), Vector3(0, 0, 0.25), 0.03, 9), Vector3(0, 1.0, 0), wood, Vector3(0, 0, 80))
		"brazier":
			Kit._part(n, MeshKit.lathe([[1.2, 0.0], [1.1, 0.3], [0.0, 0.35]], 10), Vector3.ZERO, stone)
			var f2 := SphereMesh.new()
			f2.radius = 0.55
			f2.height = 1.3
			Kit._part(n, f2, Vector3(0, 0.8, 0), Kit.mat("fire", Color(1.0, 0.55, 0.15), 0.5, 4.0))
			_fire_light(n)
		"stones":
			e.height = 1.5
			for i in 5:
				Kit._part(n, Kit.mesh("rock"), Vector3(4.0 + i * 3.4, Land.WATER_Y - 0.35 - pos.y, sin(i * 1.7) * 0.8), stone, Vector3.ZERO, Vector3(0.9, 0.5, 0.9))

			var far := Vector3(Land.river_x(Land.STONES_Z) + 9.0, 0, Land.STONES_Z)
			far.y = Land.walk_height(far.x, far.z)
			chunk.ents.append({"id": "stones_east", "type": "stones", "pos": far, "label": pl.label, "height": 1.5, "node": n})
		"tower":
			e.height = 4.0
		"npc":
			var nv := PlaceholderVisual.new()
			n.add_child(nv)
			nv.configure(NPC_LOOKS[pl.id])
			nv.rotation.y = atan2(- (Land.VILLAGE.x - p.x), - (Land.VILLAGE.y - p.y))
		"spot":
			match pl.id:
				"shrine", "altar":
					Kit._part(n, MeshKit.lathe([[1.3, 0.0], [1.2, 0.35], [0.5, 0.5], [0.45, 1.5], [0.7, 1.7], [0.0, 1.75]], 6), Vector3.ZERO, stone)
					var glow_c := Color(0.4, 1.0, 0.7) if pl.id == "shrine" else Color(1.0, 0.5, 0.2)
					Kit._part(n, Kit.mesh("ore"), Vector3(0, 1.9, 0), Kit.mat("glow_" + pl.id, glow_c, 0.4, 4.0), Vector3.ZERO, Vector3(1.6, 1.8, 1.6))
					var sl := OmniLight3D.new()
					sl.position = Vector3(0, 2.4, 0)
					sl.light_color = glow_c
					sl.light_energy = 2.0
					sl.omni_range = 9.0
					n.add_child(sl)
				"circle":
					for i in 9:
						var a := TAU * i / 9.0
						Kit._part(n, Kit.mesh("rock"), Vector3(cos(a) * 5.0, 0, sin(a) * 5.0), stone, Vector3(0, rad_to_deg(a), 0), Vector3(0.7, 2.6 + (i % 3) * 0.5, 0.5))
				"watch":
					var tw := BoxMesh.new()
					tw.size = Vector3(4.0, 7.0, 4.0)
					Kit._part(n, tw, Vector3(0, 3.2, -3.0), stone, Vector3(0, 12, 8))
					Kit._part(n, Kit.mesh("wall"), Vector3(3.0, 1.0, 0.5), stone, Vector3(0, 40, 70))
					chunk.obstacles.append(Vector3(p.x, p.y - 3.0, 2.8))
	chunk.ents.append(e)
	if pl.type in ["station", "brazier", "npc"]:
		chunk.obstacles.append(Vector3(p.x, p.y, 0.9))


func _fire_light(n: Node3D) -> void:
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.6, 0)
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 2.5
	l.omni_range = 10.0
	n.add_child(l)


func _tick_walkers(delta: float) -> void:
	for w in ow._walkers:
		var v: PlaceholderVisual = w.node
		if float(w.pause) > 0.0 or ow.hud.screen == "talk":
			w.pause = float(w.pause) - delta
			v.set_walk(0.0)
			continue
		var goal: Vector2 = w.loop[int(w.at)]
		var to := Vector3(goal.x - w.pos.x, 0, goal.y - w.pos.z)
		if to.length() < 0.6:
			w.at = (int(w.at) + 1) % (w.loop as Array).size()
			w.pause = randf_range(1.0, 5.0)
			continue
		w.pos += to.normalized() * 1.5 * delta
		w.pos.y = Land.walk_height(w.pos.x, w.pos.z)
		v.position = w.pos
		v.rotation.y = lerp_angle(v.rotation.y, atan2(-to.x, -to.z), clampf(delta * 6.0, 0.0, 1.0))
		v.set_walk(0.45)
