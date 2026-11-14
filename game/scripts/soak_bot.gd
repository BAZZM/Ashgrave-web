extends Node
## Memory soak bot (tools/check.js scenario `perf-soak`), started by perf.gd for the user arg
## `--soak`. Lives under the Perf autoload, so it survives every scene change, and plays the real
## journey through the game's own functions, in cycles:
##   land: roam five biomes (stick, sprint, dash, chunk streaming), win and lose a wild duel (the
##   loss respawns at the hearth), gather, open and close every HUD screen, fast travel, enter the tower;
##   tower: win on tier 1, a pack duel on tier 2, lose on tier 3 (a death in the tower: back to the land).
## Game time runs four times faster than real time. Once per cycle, idle at the hearth, it prints one
## "SOAK cycle=..." line of memory readings; "SOAK phase=..." lines give the same readings in each
## phase of play, and "SOAKGROW" lines say what the bot was doing whenever the wasm heap grew.
## Debug only: nothing here runs without --soak.

const Kit := preload("res://scripts/overworld_kit.gd")
const SPEED := 4.0
const MIN_CYCLES := 5
const MIN_GAME_S := 12.0 * 60.0
const SCREENS := ["bag", "map", "skills", "perks", "quests", "players", "shop"]

var cycle := 0
var game_s := 0.0
var doing := "boot"
var want_bot := "soak"
var peak_heap := 0
var _last_heap := 0
var _results: Array = []
var _said_phase := {}
var _fx: Sfx
var _noeval := "--soak-noeval" in OS.get_cmdline_user_args()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Run.ensure_loaded()
	# A fresh profile, set up as a player some hours in: combat skills as the tour bot has them,
	# every travel spot found, three tower tiers open, the tutorial done. Saves stay on.
	Run.data.tutorial_done = true
	Run.data.skills_seeded = true
	for sk in Craft.COMBAT:
		Run.data.skills[sk] = Craft.xp_for(45)
	Run.data.gold = 500
	Run.data.unlocked = 3
	Run.data.visited = ["camp_fire", "scar_anvil", "shrine", "altar", "circle", "watch", "tower"]
	Run.data.in_tower = false
	_main.call_deferred()


func _process(delta: float) -> void:
	game_s += delta
	var h := _heap() if not _noeval else 0
	if h > _last_heap:
		if _last_heap > 0:
			print("SOAKGROW %s %d->%d MB (+%d KB) cycle=%d" % [doing, _last_heap >> 20, h >> 20, (h - _last_heap) >> 10, cycle])
		_last_heap = h
		peak_heap = maxi(peak_heap, h)
	var sc := get_tree().current_scene
	if sc == null:
		return
	var d: Variant = sc.get("duel")
	if d is Duel and is_instance_valid(d):
		if d._bot == "":
			d._bot = want_bot
			d._base_time = SPEED
			Engine.time_scale = SPEED
	elif sc.get("is_land") != null and Engine.time_scale != SPEED:
		Engine.time_scale = SPEED


func _heap() -> int:
	var v: Variant = JavaScriptBridge.eval("window.__ag ? window.__ag.heap() : -1", true)
	return int(v) if v is float or v is int else -1


func _js_heap() -> int:
	var v: Variant = JavaScriptBridge.eval("(window.gc && window.gc(), (performance.memory && performance.memory.usedJSHeapSize) || -1)", true)
	return int(v) if v is float or v is int else -1


func _mon(m: int) -> int:
	return int(Performance.get_monitor(m))


func readings() -> String:
	var sc := get_tree().current_scene
	var chunks: Variant = sc.get("_chunks") if sc != null else null
	var save_len := JSON.stringify(Run.data).length()
	var win := DisplayServer.window_get_size()
	return "win=%dx%d gt=%d heap=%d peak=%d js=%d oc=%d nc=%d orphan=%d res=%d tex=%d buf=%d vid=%d static=%d dc=%d prim=%d meshkit=%d kit=%d chunks=%s save=%d caps=%d slain=%d" % [
		win.x, win.y, int(game_s), _heap(), peak_heap, _js_heap(), _mon(Performance.OBJECT_COUNT), _mon(Performance.OBJECT_NODE_COUNT),
		_mon(Performance.OBJECT_ORPHAN_NODE_COUNT), _mon(Performance.OBJECT_RESOURCE_COUNT),
		_mon(Performance.RENDER_TEXTURE_MEM_USED), _mon(Performance.RENDER_BUFFER_MEM_USED), _mon(Performance.RENDER_VIDEO_MEM_USED),
		_mon(Performance.MEMORY_STATIC), _mon(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), _mon(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		MeshKit._cache.size(), Kit._meshes.size() + Kit._mats.size(), str(chunks.size()) if chunks is Dictionary else "-", save_len,
		Run.captions.size(), (Run.data.slain as Array).size()]


func _phase(name: String) -> void:
	# Each phase is printed on every cycle, so its growth can be read too.
	await _frames(3)
	print("SOAK phase=%s cycle=%d %s" % [name, cycle, readings()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Game seconds (follows Engine.time_scale).
func _wait(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, false).timeout


## Waits until cond() is true, or the real-time limit passes. Returns cond().
func _until(cond: Callable, real_secs: float) -> bool:
	var end := Time.get_ticks_msec() + int(real_secs * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _scene() -> Node:
	return get_tree().current_scene


func _land() -> Overworld:
	var sc := _scene()
	return sc as Overworld if sc is Overworld and (sc as Overworld).hero != null else null


func _tower() -> World:
	var sc := _scene()
	return sc as World if sc is World and (sc as World).hero != null and not (sc as World)._leaving else null


func _in_duel() -> bool:
	var sc := _scene()
	if sc == null:
		return false
	var d: Variant = sc.get("duel")
	return d is Duel and is_instance_valid(d)


func _fail(why: String) -> void:
	print("SOAK fail %s cycle=%d doing=%s" % [why, cycle, doing])
	get_tree().quit()


func _main() -> void:
	doing = "title"
	if not await _until(func(): return _land() != null, 120.0):
		_fail("no land")
		return
	# Measuring what a quality setting would save (debug): --soak-variant=nopos|noshadow|scale75|lowshadow
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--soak-variant="):
			var vp := get_viewport()
			match arg.trim_prefix("--soak-variant="):
				"nopos":
					vp.positional_shadow_atlas_size = 0
				"noshadow":
					_land().sky._sun.shadow_enabled = false
					RenderingServer.directional_shadow_atlas_set_size(256, true)
				"lowshadow":
					RenderingServer.directional_shadow_atlas_set_size(512, true)
				"sky64":
					_land().sky._env.sky.radiance_size = Sky.RADIANCE_SIZE_64
				"scale75":
					vp.scaling_3d_scale *= 0.75
			print("SOAK variant %s pos_atlas=%d scale3d=%.3f" % [arg, vp.positional_shadow_atlas_size, vp.scaling_3d_scale])
	await _wait(4.0)
	await _phase("title")
	if "--soak=idle" in OS.get_cmdline_user_args():
		# Debug: stand in the land and read memory every 20 s of real time, for finding growth that comes with
		# time rather than with what the player does.
		_land().begin()
		doing = "idle"
		for i in 13:
			var end := Time.get_ticks_msec() + 20000
			var churn := "--soak-churn=amb" in OS.get_cmdline_user_args() or "--soak-churn=fx" in OS.get_cmdline_user_args()
			while Time.get_ticks_msec() < end:
				if "--soak-churn=scene" in OS.get_cmdline_user_args():
					# Debug: a scene load every 6 s, land and tower in turn.
					var to := "res://scenes/world.tscn" if _scene() is Overworld else "res://scenes/overworld.tscn"
					Run.data.in_tower = to.ends_with("world.tscn")
					get_tree().change_scene_to_file(to)
					var t6 := Time.get_ticks_msec() + 6000
					while Time.get_ticks_msec() < mini(t6, end):
						await get_tree().process_frame
					continue
				if "--soak-churn=play" in OS.get_cmdline_user_args():
					# Debug: three effect plays a frame on one Sfx.
					if _fx == null:
						_fx = Sfx.new()
						_fx.ambience = false
						add_child(_fx)
					_fx.play("hit")
					_fx.play("clang")
					_fx.play("finish")
				if churn:
					# Debug: what a scene load does to the sound: a new Sfx (with ambience or not), a few plays, freed.
					var fx := Sfx.new()
					fx.ambience = "--soak-churn=amb" in OS.get_cmdline_user_args()
					add_child(fx)
					fx.play("hit")
					fx.play("clang")
					await _frames(3)
					fx.queue_free()
				await get_tree().process_frame
			print("SOAK phase=idle cycle=%d %s" % [i, readings()])
		print("SOAK done idle")
		get_tree().quit()
		return
	if "--soak=title" in OS.get_cmdline_user_args():
		print("SOAK done title only")
		get_tree().quit()
		return
	_land().begin()
	print("SOAK start biomes=%s" % [_waypoints().size()])
	while cycle < MIN_CYCLES or game_s < MIN_GAME_S:
		cycle += 1
		if not await _land_part():
			return
		if not await _tower_part():
			return
		# Back in the land after the death in the tower: idle at the hearth, then the cycle line.
		doing = "settle"
		if not await _until(func(): return _land() != null and not _in_duel(), 120.0):
			_fail("no land after tower")
			return
		await _wait(3.0)
		await _frames(3)
		print("SOAK cycle=%d %s results=%s" % [cycle, readings(), ",".join(_results)])
		_results.clear()
	print("SOAK done cycles=%d gt=%d peak=%d" % [cycle, int(game_s), peak_heap])
	get_tree().quit()


## A walkable spot in each of five biomes, found once.
var _wp: Array = []
func _waypoints() -> Array:
	if not _wp.is_empty():
		return _wp
	var seen := {}
	for b in ["meadow", "forest", "marsh", "quarry", "ruins", "ashlands"]:
		seen[b] = null
	var z := Land.Z_MIN + 20.0
	while z < Land.Z_MAX - 20.0:
		var x := -Land.X_MAX + 20.0
		while x < Land.X_MAX - 20.0:
			var b := Land.biome(x, z)
			if seen.has(b) and seen[b] == null and not Land.is_water(x, z) and Land.road_dist(x, z) > 6.0:
				seen[b] = Vector3(x, 0, z)
			x += 37.0
		z += 37.0
	for b in seen:
		if seen[b] != null:
			_wp.append(seen[b])
	return _wp


func _put(ow: Overworld, p: Vector3) -> void:
	ow.hero_pos = Vector3(p.x, Land.walk_height(p.x, p.z), p.z)
	ow.hero.position = ow.hero_pos
	ow._last_safe = ow.hero_pos
	ow.terrain._update_chunks(true)
	ow.mover.settle_position("soak")
	ow.mover.reset_motion()


## Wait out a duel the bot is in (started by us or by a foe catching the hero).
func _finish_duel() -> String:
	if not await _until(func(): return _in_duel(), 10.0):
		return "none"
	var d: Duel = _scene().duel
	await _until(func(): return not _in_duel(), 400.0)
	if _in_duel():
		_fail("duel did not end")
		return "stuck"
	return str(d.result) if is_instance_valid(d) else "done"


func _foe_near(ow: Overworld, from: Vector3) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in ow.ents:
		if e.type == "foe":
			var dist: float = (e.pos as Vector3).distance_to(from)
			if dist < bd:
				bd = dist
				best = e
	return best


func _wild_duel(bot: String, tag: String) -> bool:
	var ow := _land()
	if ow == null:
		return true
	want_bot = bot
	doing = "wild " + tag
	var wp: Array = _waypoints()
	var e := _foe_near(ow, wp[0] if bot != "idle" else wp[cycle % wp.size()])
	if e.is_empty():
		_results.append(tag + ":nofoe")
		return true
	var to_foe: Vector3 = e.pos
	_put(ow, to_foe + Vector3(7, 0, 0))
	# The foe's figure appears once the hero is within 60 units (next frame).
	await _until(func(): return _land() == null or e.node != null or _in_duel(), 10.0)
	ow = _land()
	if ow == null:
		return true
	if not _in_duel() and e.node != null:
		ow.duels._start_duel(e)
	var r := await _finish_duel()
	_results.append("%s:%s" % [tag, r])
	want_bot = "soak"
	await _frames(2)
	return r != "stuck"


func _land_part() -> bool:
	var ow := _land()
	if ow == null:
		_fail("cycle start not in land")
		return false
	# Roam: five biomes, three to four game seconds each of running with the stick, a sprint
	# and two dashes; chunks stream in and out on every hop.
	var i := 0
	for p in _waypoints():
		doing = "roam %d" % i
		ow = _land()
		if ow == null:
			break
		_put(ow, p)
		var heading := float(i) * 1.7 + cycle
		for s in 8:
			ow = _land()
			if ow == null or _in_duel():
				break
			ow.stick = Vector2(sin(heading + s * 0.4), -cos(heading + s * 0.4))
			if s == 3 or s == 6:
				ow.mover.try_dash()
			await _wait(0.5)
		if _land() != null:
			_land().stick = Vector2.ZERO
		if _in_duel():
			_results.append("caught:" + await _finish_duel())
		i += 1
	await _phase("land")
	if cycle == 1 or cycle == MIN_CYCLES:
		_mesh_census()
	if not await _wild_duel("soak", "win"):
		return false
	# Gather from the nearest node the hero has the level for.
	ow = _land()
	if ow != null:
		doing = "gather"
		_put(ow, Vector3(Land.START.x, 0, Land.START.z))
		var best := {}
		var bd := 1e9
		for e in ow.ents:
			if e.type == "node" and not e.depleted and Run.skill(Land.NODES[e.node_id].skill) >= int(Land.NODES[e.node_id].level):
				var dist: float = (e.pos as Vector3).distance_to(ow.hero_pos)
				if dist < bd:
					bd = dist
					best = e
		if best.is_empty():
			_results.append("gather:none")
		else:
			_put(ow, best.pos + Vector3(1.6, 0, 0))
			ow.near = best
			ow.interaction.interact()
			var before := JSON.stringify(Run.data.mats)
			await _until(func(): return _land() == null or _land()._gather.is_empty(), 60.0)
			_results.append("gather:%s" % ("ok" if JSON.stringify(Run.data.mats) != before else "nothing"))
	# Every HUD screen, opened and closed.
	ow = _land()
	if ow != null:
		doing = "screens"
		_put(ow, Vector3(Land.START.x, 0, Land.START.z))
		for s in SCREENS:
			ow.hud.open(s)
			await _frames(2)
			await _wait(0.4)
			ow.hud._close()
		ow.hud.open_craft("smithing")
		await _frames(2)
		ow.hud._close()
		await _phase("screens")
	# Fast travel from the hearth to a spot, alternating.
	ow = _land()
	if ow != null:
		doing = "travel"
		var dest: String = ["shrine", "camp_fire", "watch", "circle"][cycle % 4]
		var why := ow.travel.request(dest)
		if why == "":
			await _until(func(): return _land() == null or (_land().travel._phase == 0 and not _land()._leaving), 60.0)
		_results.append("travel:%s" % ("ok" if why == "" else why.replace(" ", "_")))
	if not await _wild_duel("idle", "lose"):
		return false
	# Into the tower by its gate.
	ow = _land()
	if ow == null:
		_fail("not in land before the tower")
		return false
	doing = "to tower"
	_put(ow, Vector3(Land.TOWER_GATE.x, 0, Land.TOWER_GATE.y + 3.0))
	ow._collect_ents()
	for e in ow.ents:
		if e.type == "tower":
			ow.near = e
	ow.interaction.interact()
	return true


func _tower_duel(t: World, bot: String, pack: bool, tag: String) -> String:
	want_bot = bot
	doing = "tower " + tag
	var first := {}
	var second := {}
	for e in t.ents:
		if e.type == "foe" and e.kind != "guardian" and e.node != null:
			if first.is_empty():
				first = e
			elif second.is_empty():
				second = e
	if first.is_empty():
		return "nofoe"
	if pack and not second.is_empty():
		# Bring a second foe beside the first, so the duel is a pack.
		second.pos = (first.pos as Vector3) + Vector3(2.0, 0, 0)
		(second.node as Node3D).position = second.pos
	t._start_duel(first)
	var r := await _finish_duel()
	want_bot = "soak"
	return r


func _tower_part() -> bool:
	doing = "tower load"
	if not await _until(func(): return _tower() != null, 120.0):
		_fail("tower did not load")
		return false
	await _wait(1.0)
	await _phase("tower")
	var t := _tower()
	var r := await _tower_duel(t, "soak", false, "t1")
	_results.append("t1:" + r)
	t = _tower()
	if t == null:
		return true  # lost and sent home: the death is had
	doing = "tier 2"
	t._travel(2, "entrance")
	var old := t.get_instance_id()
	if not await _until(func(): return _tower() != null and _tower().get_instance_id() != old, 120.0):
		_fail("tier 2 did not load")
		return false
	await _wait(1.0)
	t = _tower()
	_phase_duel()
	r = await _tower_duel(t, "soak", true, "pack")
	_results.append("pack:" + r)
	t = _tower()
	if t == null:
		return true
	doing = "tier 3"
	t._travel(3, "entrance")
	old = t.get_instance_id()
	if not await _until(func(): return _tower() != null and _tower().get_instance_id() != old, 120.0):
		_fail("tier 3 did not load")
		return false
	await _wait(1.0)
	r = await _tower_duel(_tower(), "idle", false, "t3")
	_results.append("t3:" + r)
	return true


## Reads the phase line in the middle of the next duel (a pack: the most fighters at once).
func _phase_duel() -> void:
	if not await _until(func(): return _in_duel(), 30.0):
		return
	await _wait(6.0)
	if _in_duel():
		await _phase("duel")


## Rough vertex and index memory by kind of thing in the scene (unique meshes counted once), for
## finding what fills RENDER_BUFFER_MEM_USED. Bytes are estimated at 32 per vertex and 4 per index.
func _mesh_census() -> void:
	var sc := _scene()
	var seen := {}
	var cat := {}
	var stack: Array = [sc]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var k := ""
		var bytes := 0
		var up := n
		while up != null and up != sc:
			if up is PlaceholderVisual:
				k = "figures"
				break
			up = up.get_parent()
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if k == "":
				k = "scatter"
			if not seen.has(mm):
				seen[mm] = true
				bytes += mm.instance_count * (48 + (16 if mm.use_colors else 0) + (16 if mm.use_custom_data else 0))
			if mm.mesh != null and not seen.has(mm.mesh):
				seen[mm.mesh] = true
				bytes += _mesh_bytes(mm.mesh)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			if k == "":
				k = "ground" if m is ArrayMesh and n.get_parent() != null and sc.get("_chunks") != null and _is_chunk_root(sc, n.get_parent()) else "other"
			if not seen.has(m):
				seen[m] = true
				bytes += _mesh_bytes(m)
		else:
			continue
		if not cat.has(k):
			cat[k] = [0, 0]
		cat[k][0] += 1
		cat[k][1] += bytes
	var line := "SOAKMESH cycle=%d" % cycle
	for k in cat:
		line += " %s=%dnodes/%dKB" % [k, cat[k][0], cat[k][1] >> 10]
	var cached := 0
	for key in MeshKit._cache:
		cached += _mesh_bytes(MeshKit._cache[key])
	var kit := 0
	for key in Kit._meshes:
		kit += _mesh_bytes(Kit._meshes[key])
	line += " meshkit_cache=%dKB kit_cache=%dKB unique=%d" % [cached >> 10, kit >> 10, seen.size()]
	print(line)


func _is_chunk_root(sc: Node, n: Node) -> bool:
	for k in sc._chunks:
		if sc._chunks[k].root == n:
			return true
	return false


func _mesh_bytes(m: Mesh) -> int:
	var b := 0
	for i in m.get_surface_count():
		if m is ArrayMesh:
			b += (m as ArrayMesh).surface_get_array_len(i) * 32 + (m as ArrayMesh).surface_get_array_index_len(i) * 4
		else:
			var a := m.surface_get_arrays(i)
			b += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 32 + (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() * 4 if a.size() > 0 else 0
	return b
