extends Node

const Tune := preload("res://scripts/combat_tune.gd")

var ow: Overworld
var _duel_ents: Array = []
var _pvp_pending := ""
var _pending_card := {}


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _start_duel(e: Dictionary) -> void:
	if ow.duel != null:
		return
	ow._gather = {}
	ow.gather_progress = -1.0
	ow.stick = Vector2.ZERO
	ow.hero.set_walk(0.0)
	var group: Array = [e]
	for o in ow.ents:
		if o.type == "foe" and o != e and o.node != null and group.size() < 3 and (o.pos as Vector3).distance_to(e.pos) < 11.0:
			group.append(o)
	var foes: Array = []
	for g in group:
		(g.node as FighterVisual).set_walk(0.0)
		foes.append({"node": g.node, "def": EnemyDef.make_wild(g.wild), "enc": {"id": g.id, "wild": g.wild, "biome": g.biome}})
	_duel_ents = group
	Run.data.ow_x = ow._last_safe.x
	Run.data.ow_z = ow._last_safe.z
	Run.save()
	ow.duel = Duel.new()
	ow.duel.host = ow
	ow.duel.player = ow.hero
	ow.duel.foes = foes
	ow.hud.visible = false
	ow.add_child(ow.duel)


func duel_done(won: bool, d: Duel) -> void:
	ow.duel = null
	ow.hud.visible = true
	ow.cam.make_current()
	Engine.time_scale = 4.0 if ow._bot in ["tour", "gather"] else 1.0
	if not d.pvp.is_empty():
		_pvp_done(won, d)
		return
	for rec in d.slain:
		for e in _duel_ents:
			if e.node == rec.node:
				for k in ow._chunks:
					ow._chunks[k].ents.erase(e)
				(e.node as Node).queue_free()
				e.node = null
	for e in _duel_ents:
		if e.node != null:
			var v: FighterVisual = e.node
			v.set_tell(Color.BLACK, 0.1)
			v.play(&"idle")
			e.pos = e.home
			v.position = e.pos
	_duel_ents = []
	ow._collect_ents()
	ow.hero.play(&"idle")
	ow.hero.rotation = Vector3(0, ow.hero_yaw, 0)
	if won:
		ow.hero_pos = ow.hero.global_position
	else:
		ow.hero_pos = Land.START
		ow.cam_yaw = 0.0
	ow.hero_pos.y = Land.walk_height(ow.hero_pos.x, ow.hero_pos.z)
	ow.hero.position = ow.hero_pos
	ow._last_safe = ow.hero_pos
	ow.mover._update_camera(1.0)
	Run.data.ow_x = ow.hero_pos.x
	Run.data.ow_z = ow.hero_pos.z
	Run.save()
	if ow._bot == "tour" and not won:
		print("TOUR hero fell in the land")


func _pvp_done(won: bool, d: Duel) -> void:
	ow.hero.play(&"idle")
	ow.hero.rotation = Vector3(0, ow.hero_yaw, 0)
	var e: Dictionary = ow._remote.get(d.pvp.id, {})
	if not e.is_empty() and is_instance_valid(e.node):
		(e.node as PlaceholderVisual).play(&"idle")
		(e.node as PlaceholderVisual).rotation = Vector3.ZERO
	if won or not d.pvp.zone:
		ow.hero_pos = ow.hero.global_position
	else:
		ow.hero_pos = Land.START
		ow.cam_yaw = 0.0
		Run.captions.append("You wake by the hearth. %s took %d of your gold." % [d.pvp.name, int(d.reward.get("lost_gold", 0))])
	ow.hero_pos.y = Land.walk_height(ow.hero_pos.x, ow.hero_pos.z)
	ow.hero.position = ow.hero_pos
	ow._last_safe = ow.hero_pos
	ow.mover._update_camera(1.0)
	Run.data.ow_x = ow.hero_pos.x
	Run.data.ow_z = ow.hero_pos.z
	Run.save()
	if ow._bot.begins_with("pvp"):
		print("PVP done won=%s gold=%d record=%d-%d" % [won, Run.data.gold, Run.data.pvp_w, Run.data.pvp_l])
		ow.get_tree().create_timer(1.0).timeout.connect(func(): ow.get_tree().quit())


func _my_card() -> Dictionary:
	var st := Run.stats()
	return {"hp": st.max_hp, "cl": Run.combat_level(), "cv": Tune.CV}


func _challenge(e: Dictionary) -> void:
	if e.get("busy", false):
		Run.captions.append("They are already fighting.")
		return
	var forced: bool = ow.in_zone() and e.get("zone", false)
	_pvp_pending = e.id
	Online.send_to(e.id, {"k": "attack" if forced else "challenge", "card": _my_card(), "st": ow.remotes._my_state()})
	Run.captions.append("You fall on them, sword out." if forced else "Challenge sent. Waiting for their answer.")


func _busy() -> bool:
	return ow.duel != null or ow.hud.screen != "" or ow._leaving or not ow.started


func _net_message(from: String, m: Dictionary) -> void:
	if m.get("st") is Dictionary and not Online.players.has(from):
		var st: Dictionary = m.st
		st.seen = Time.get_ticks_msec()
		st.n = m.get("n", "?")
		Online.players[from] = st
	if ow.duel != null and not ow.duel.pvp.is_empty():
		return
	var who := String(m.get("n", "Someone")).left(16)
	match String(m.get("k", "")):
		"challenge":
			if _busy() and ow._bot == "":
				Online.send_to(from, {"k": "busy"})
			elif ow._bot == "pvp_b":
				pvp_answer("pvp:accept:" + from, m.get("card", {}))
			else:
				_pending_card = m.get("card", {})
				ow.hud.talk({"name": who, "lines": ["%s, combat level %d, challenges you to a duel. Nothing is at stake but honour." % [who, int(m.get("card", {}).get("cl", 1))]],
					"choices": [["Accept.", "pvp:accept:" + from], ["Decline.", "pvp:decline:" + from]]})
		"attack":
			if _busy() or not ow.in_zone():
				Online.send_to(from, {"k": "busy"})
			else:
				Online.send_to(from, {"k": "accept", "card": _my_card(), "zone": true})
				ow.hud.announce("%s attacks!" % who)
				_start_pvp(from, who, m.get("card", {}), false, true)
		"accept":
			if from == _pvp_pending and ow.duel == null:
				_pvp_pending = ""
				_start_pvp(from, who, m.get("card", {}), true, m.get("zone", false))
		"decline":
			if from == _pvp_pending:
				_pvp_pending = ""
				Run.captions.append("%s declines." % who)
		"busy":
			if from == _pvp_pending:
				_pvp_pending = ""
				Run.captions.append("%s cannot fight right now." % who)


func pvp_answer(action: String, card := {}) -> void:
	var parts := action.split(":")
	var from := parts[2]
	if card.is_empty():
		card = _pending_card
	if parts[1] != "accept" or ow.duel != null:
		Online.send_to(from, {"k": "decline"})
		return
	Online.send_to(from, {"k": "accept", "card": _my_card(), "zone": false})
	var who := String(Online.players.get(from, {}).get("n", "Challenger"))
	_start_pvp(from, who, card, false, false)


func _start_pvp(id: String, who: String, card: Dictionary, i_go_first: bool, zone: bool) -> void:
	if ow.duel != null:
		return
	if not ow._remote.has(id):
		ow.remotes._tick_remote(0.0)
	if not ow._remote.has(id):
		return
	ow._gather = {}
	ow.gather_progress = -1.0
	ow.stick = Vector2.ZERO
	ow.hero.set_walk(0.0)
	var e: Dictionary = ow._remote[id]
	(e.node as PlaceholderVisual).set_walk(0.0)
	ow.duel = Duel.new()
	ow.duel.host = ow
	ow.duel.player = ow.hero
	ow.duel.foes = [{"node": e.node, "def": null, "enc": {}}]
	ow.duel.pvp = {"id": id, "name": who, "first": i_go_first, "zone": zone, "max_hp": float(card.get("hp", 100.0)),
		"cv": mini(Tune.CV, int(card.get("cv", 1)))}
	ow.hud.screen = ""
	ow.hud.visible = false
	ow.add_child(ow.duel)
