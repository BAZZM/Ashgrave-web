extends Node

var ow: Overworld
var _bot_step := 0
var _bot_wait := 0.0


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _walk_to(target: Vector3, delta: float) -> Vector3:
	var to := target - ow.hero_pos
	to.y = 0
	if ow._stuck > 0.4:
		to = to.rotated(Vector3.UP, 1.3)
		if ow._stuck > 1.5:
			ow._stuck = 0.0
	return to.normalized()


func _bot_dir(delta: float) -> Vector3:
	if ow._bot.begins_with("pvp"):
		return Vector3.ZERO
	if ow._bot == "tour":
		var gate := Vector3(Land.TOWER_GATE.x, 0, Land.TOWER_GATE.y + 2.0)
		if not ow.near.is_empty() and ow.near.type == "tower":
			ow.interaction.interact()
			return Vector3.ZERO
		return _walk_to(gate, delta)

	if not ow._gather.is_empty():
		return Vector3.ZERO
	_bot_wait -= delta
	if _bot_wait > 0.0:
		return Vector3.ZERO
	if _bot_step >= 3:
		var made: Array = []
		for r in Craft.RECIPES:
			if Craft.make(r):
				made.append(r.name)
		ow.interaction._task_talk()
		print("GATHER mats=%s made=%s total_level=%d task=%s" % [Run.data.mats, made, Run.total_level(), Run.data.task.get("foe", "")])
		ow.get_tree().quit()
		return Vector3.ZERO
	var best := {}
	var bd := 9999.0
	for e in ow.ents:
		if e.type == "node" and not e.depleted and Run.skill(Land.NODES[e.node_id].skill) >= int(Land.NODES[e.node_id].level):
			var d: float = (e.pos as Vector3).distance_to(ow.hero_pos)
			if d < bd:
				bd = d
				best = e
	if best.is_empty():
		return _walk_to(ow.hero_pos + Vector3(-30, 0, 0), delta)
	if bd < 2.8:
		ow.near = best
		ow.interaction.interact()
		_bot_step += 1
		_bot_wait = 0.5
		return Vector3.ZERO
	return _walk_to(best.pos, delta)


func _take_shot_if_due() -> void:
	if ow._shot_path == "":
		return
	if ow._shot_when == "pvp":
		return
	if ow._shot_when == "players" and ow.hud.screen == "" and ow._t > 3.0:
		ow.hud.open("players")
	if ow._shot_when in ["players", "online"] and ow._t < 4.5:
		return
	if ow._shot_when == "fight":
		for e in ow.ents:
			if e.type == "foe" and e.node != null and ow._t > 0.5:
				ow.hero_pos = e.pos + Vector3(0, 0, 2.2)
				ow._shot_path = ""
				return
		return
	if ow._shot_when in ["skills", "store", "map", "quests", "perks"] and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.open(ow._shot_when)
	if ow._shot_when == "talk" and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.talk(Quests.talk("elder"))
		ow.hud._talk.i = 1
	if ow._shot_when == "craft" and ow.hud.screen == "" and ow._t > 0.4:
		ow.hud.open_craft("smithing")
	if ow._t < 1.6:
		return
	var path := ow._shot_path
	ow._shot_path = ""
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	ow.get_viewport().get_texture().get_image().save_png(path)
	ow.get_tree().quit()
