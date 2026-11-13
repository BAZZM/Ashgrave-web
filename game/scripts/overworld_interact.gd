extends Node

const PROMPTS := {"smith": "TRADE", "store": "SELL", "task": "TALK", "brazier": "REST", "tower": "ENTER",
	"stones": "CROSS", "chest": "OPEN", "npc": "TALK", "spot": "LOOK", "beast": "SHOOT"}

var ow: Overworld
var _reached := ""


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _check_surroundings(delta: float) -> void:
	if ow.bots.agreal_hold():
		return
	ow.near = {}
	var best := 3.0
	var foe_close := false
	var now := Time.get_ticks_msec()
	for e in ow.ents:
		var d: float = Vector2(e.pos.x - ow.hero_pos.x, e.pos.z - ow.hero_pos.z).length()
		if e.type == "foe":
			if e.node == null and d < 60.0:
				var v := PlaceholderVisual.new()
				ow.add_child(v)
				var f: Dictionary = Land.FOES[e.wild]
				v.configure(EnemyDef.make_wild(e.wild).look)
				v.position = e.pos
				e.node = v
			elif e.node != null and d > 75.0:
				(e.node as Node).queue_free()
				e.node = null
			if e.node == null:
				continue
			var v2: PlaceholderVisual = e.node
			var home_d: float = (e.pos as Vector3).distance_to(e.home)
			var walking := 0.0
			if d < 11.0 and home_d < 30.0 and ow._bot not in ["gather", "pvp_a", "pvp_b"]:
				var to: Vector3 = (ow.hero_pos - e.pos)
				to.y = 0
				e.pos += to.normalized() * 2.6 * delta
				v2.rotation.y = atan2(-to.x, -to.z)
				walking = 0.7
			elif home_d > 1.0 and d > 16.0:
				var back: Vector3 = (e.home - e.pos)
				back.y = 0
				e.pos += back.normalized() * 1.8 * delta
				v2.rotation.y = atan2(-back.x, -back.z)
				walking = 0.5
			e.pos.y = Land.walk_height(e.pos.x, e.pos.z)
			v2.position = e.pos
			v2.set_walk(walking)
			if d < 8.0:
				foe_close = true
			if d < 2.5 and ow._bot not in ["gather", "pvp_a", "pvp_b"] and not ow.mover.dash_iframes():
				ow.duels._start_duel(e)
				return
		elif e.type == "beast":
			_tick_beast(e, d, delta)
		elif e.type == "node":
			if e.depleted and Run.respawn_due(e.id):
				e.depleted = false
				e.charges = int(Land.NODES[e.node_id].charges)
				(e.full as Node3D).visible = true
				(e.empty as Node3D).visible = false
			if not e.depleted and d < best:
				best = d
				ow.near = e
		elif d < best:
			best = d
			ow.near = e
	if ow.near.is_empty() and _can_shoot():
		var shot := 17.0
		for e in ow.ents:
			if e.type == "beast":
				var bd: float = (e.pos as Vector3).distance_to(ow.hero_pos)
				if bd < shot:
					shot = bd
					ow.near = e
	var here: String = ow.near.get("id", "") if ow.near.get("type", "") in ["spot", "tower"] else ""
	if here != _reached:
		_reached = here
		if here != "":
			Quests.on_reach(here)
	if not foe_close and ow.mover.is_free(ow.hero_pos):
		ow._last_safe = ow.hero_pos


func prompt() -> String:
	if ow.near.is_empty() or not ow._gather.is_empty():
		return ""
	if ow.near.type == "node":
		return Land.NODES[ow.near.node_id].verb
	if ow.near.type == "player":
		return "ATTACK" if ow.in_zone() and ow.near.get("zone", false) else "DUEL"
	if ow.near.type == "station":
		return {"smithing": "FORGE", "cooking": "COOK", "alchemy": "BREW", "fletching": "FLETCH"} [ow.near.skill]
	return PROMPTS.get(ow.near.type, "")


func interact() -> void:
	if ow.near.is_empty() or ow._leaving:
		return
	var e := ow.near
	match e.type:
		"node":
			var def: Dictionary = Land.NODES[e.node_id]
			if Run.skill(def.skill) < int(def.level):
				Run.captions.append("%s needs %s level %d. Yours is %d." % [def.label, Craft.SKILLS[def.skill].name, def.level, Run.skill(def.skill)])
				return
			ow._gather = {"e": e, "t": 0.0}
			ow.gather_label = def.verb
			var to: Vector3 = e.pos - ow.hero_pos
			if e.node != null and def.skill == "fishing":
				to = (e.node as Node3D).position - ow.hero_pos
			ow.hero_yaw = atan2(-to.x, -to.z)
		"smith":
			var said := Quests.talk("smith")
			if said.lines.is_empty():
				ow.hud.open("shop")
			else:
				said.choices.append(["Show me your wares.", "shop"])
				ow.hud.talk(said)
		"npc":
			var words := Quests.talk(e.id)
			if words.lines.is_empty():
				words.lines = ["Good day to you."]
			ow.hud.talk(words)
		"beast":
			_shoot(e)
		"player":
			ow.duels._challenge(e)
			return
		"spot":
			match e.id:
				"circle":
					if int(Run.data.potions) < 2:
						Run.data.potions = 2
					Run.captions.append("The standing stones hum underfoot. You feel rested; your flasks are full.")
				"watch": Run.captions.append("A watchtower, long fallen. From its stump you can see the whole of Greywood.")
				"shrine": Run.captions.append("A shrine of marsh-stone. A green light burns in it.")
				"altar": Run.captions.append("The broken altar. Thirty names are cut into its side, all in one hand.")
		"station":
			ow.hud.open_craft(e.skill)
		"store":
			ow.hud.open("store")
		"task":
			_task_talk()
		"brazier":
			if int(Run.data.potions) < 2:
				Run.data.potions = 2
				Run.captions.append("You rest by the hearth. Your flasks are refilled.")
			else:
				Run.captions.append("The hearth is warm. Meals cooked on a fire give extra health in your next fight.")
		"chest":
			Run.data.ow_opened.append(e.id)
			Run.data.gold += int(e.gold)
			Run.add_mat("cinder", 1)
			Run.captions.append("The chest holds %d gold and a cinder shard." % e.gold)
			(e.node as Node3D).queue_free()
			for k in ow._chunks:
				ow._chunks[k].ents.erase(e)
			ow._collect_ents()
			ow.near = {}
		"stones":
			if Run.skill("agility") < 10:
				Run.captions.append("The stones are slick. Agility level 10 would see you across. Yours is %d." % Run.skill("agility"))
				return
			var east := ow.hero_pos.x < Land.river_x(Land.STONES_Z)
			ow.hero_pos = Vector3(Land.river_x(Land.STONES_Z) + (9.0 if east else -9.0), 0, Land.STONES_Z)
			ow.mover.settle_position("stones")
			ow.mover.reset_motion()
			Run.train("agility", 60)
		"tower":
			ow._leaving = true
			Run.data.in_tower = true
			Run.data.floor = 1
			Run.spawn = "entrance"
			Run.data.tower_slain = []
			Run.captions.append(Story.inscription(1, int(Run.data.bloodline)))
			if Run.combat_level() < 12:
				Run.captions.append("Everything here is far stronger than the land outside. Leave by the gate behind you if it is too much.")
			var back: Vector3 = ow.mover.free_near(ow.hero_pos + Vector3(0, 0, 6.0))
			Run.data.ow_x = back.x
			Run.data.ow_z = back.z
			ow.mover.reset_motion()
			Run.save()
			ow.get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	Run.save()


func _tick_gather(delta: float) -> void:
	if ow._gather.is_empty():
		ow.gather_progress = -1.0
		return
	var e: Dictionary = ow._gather.e
	var def: Dictionary = Land.NODES[e.node_id]
	var tool_tier := int(Run.data.tools.get(def.tool, 0)) if def.tool != "" else 0
	var period := (0.7 if def.skill == "foraging" else 1.6) / (1.0 + 0.3 * tool_tier)
	if ow._gather.t == 0.0:
		ow.hero.play(&"slash", 3 if def.skill != "fishing" else 2, period * 0.5)
	ow._gather.t += delta
	ow.gather_progress = ow._gather.t / period
	if ow._gather.t < period:
		return
	ow._gather.t = 0.0
	var lvl := Run.skill(def.skill)
	var chance := clampf(0.5 + 0.02 * (lvl - int(def.level)) + 0.1 * tool_tier, 0.3, 0.97)
	if def.skill == "foraging" or randf() < chance:
		Run.add_mat(def.mat, 1)
		Run.train(def.skill, int(def.xp))
		e.charges -= 1
	if e.charges <= 0:
		e.depleted = true
		Run.set_respawn(e.id, 45000 if def.skill == "foraging" else 60000)
		(e.full as Node3D).visible = false
		(e.empty as Node3D).visible = true
		ow._gather = {}
		ow.gather_progress = -1.0
		ow.hero.play(&"idle")
		Run.save()


func _task_talk() -> void:
	var task: Dictionary = Run.data.task
	if task.is_empty():
		var options: Array = []
		for id in Land.FOES:
			if int(Land.FOES[id].level) <= Run.combat_level() * 2 + 6:
				options.append(id)
		var pick: String = options[maxi(options.size() - 1 - (randi() % 2), 0)]
		var f: Dictionary = Land.FOES[pick]
		Run.data.task = {"foe": pick, "need": 3, "have": 0, "gold": int(f.level) * 12 + 40, "xp": int(f.level) * 14 + 40}
		var where := Land.region_of(pick)
		Run.captions.append("Taskmaster: \"Bring down three of the %ss in %s. There is %d gold in it.\"" % [f.name, where, Run.data.task.gold])
	elif int(task.have) >= int(task.need):
		Run.data.gold += int(task.gold)
		Run.train("slaying", int(task.xp))
		Run.captions.append("Taskmaster: \"Clean work. Here is your %d gold. Come back for another.\"" % task.gold)
		Run.data.task = {}
	else:
		Run.captions.append("Taskmaster: \"%d of %d %ss so far. Keep at it.\"" % [task.have, task.need, Land.FOES[task.foe].name])


func _tick_beast(e: Dictionary, d: float, delta: float) -> void:
	var n: Node3D = e.node
	var speed := 1.3
	if d < 7.0 and float(e.flee) <= 0.0:
		var away: Vector3 = e.pos - ow.hero_pos
		away.y = 0
		e.goal = e.pos + away.normalized() * 22.0
		e.flee = 2.6
	if float(e.flee) > 0.0:
		e.flee = float(e.flee) - delta
		speed = 6.4
	var to: Vector3 = e.goal - e.pos
	to.y = 0
	if to.length() < 0.5:
		e.wait = float(e.wait) - delta
		if float(e.wait) <= 0.0:
			e.wait = randf_range(2.0, 6.0)
			e.goal = e.home + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
		return
	var next: Vector3 = e.pos + to.normalized() * speed * delta
	if ow.terrain._blocked(next):
		e.goal = e.pos
		return
	e.pos = next
	e.pos.y = Land.walk_height(e.pos.x, e.pos.z) + absf(sin(ow._t * (14.0 if speed > 2.0 else 6.0))) * 0.06
	n.position = e.pos
	n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))


func _can_shoot() -> bool:
	var r: String = Run.data.equipped.get("ranged", "")
	return r == "throwing_knives" or (r == "hunters_bow" and Run.mat("arrow") > 0)


func _shoot(e: Dictionary) -> void:
	var d: float = (e.pos as Vector3).distance_to(ow.hero_pos)
	var to: Vector3 = e.pos - ow.hero_pos
	ow.hero_yaw = atan2(-to.x, -to.z)
	ow.hero.play(&"slash", 3, 0.15)
	if Run.data.equipped.ranged == "hunters_bow":
		Run.add_mat("arrow", -1)
	var chance := clampf(0.5 + 0.02 * Run.skill("archery") - d * 0.012, 0.2, 0.95)
	if randf() > chance:
		Run.xp_log.append("Missed")
		Run.train("archery", 6)
		e.flee = 0.0
		_tick_beast(e, 0.0, 0.0)
		return
	Run.train("archery", 34 if e.beast == "deer" else 46)
	Run.add_mat("raw_meat", 1)
	Run.add_mat("hide", 1 + (randi() % 2))
	Run.xp_log.append("Raw meat and hide")
	Run.set_respawn(e.id, 120000)
	(e.node as Node3D).queue_free()
	for k in ow._chunks:
		ow._chunks[k].ents.erase(e)
	ow._collect_ents()
	ow.near = {}
