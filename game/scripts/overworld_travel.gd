extends Node

# Fast travel between discovered places, chosen on the map screen.
# The map (world_hud.gd) asks for `markers()` to draw and calls `request(id)` on a tap.

const DESTS := ["hearth", "camp_fire", "scar_anvil", "shrine", "altar", "circle", "watch", "tower"]
const FOE_RANGE := 12.0
const FADE_OUT := 0.3
const FADE_IN := 0.45

var ow: Overworld
var _phase := 0
var _t := 0.0
var _target := ""
var _scan := 0.0
var _inferred := false
var _fade: ColorRect


func _init(owner_world: Overworld) -> void:
	ow = owner_world


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	layer.add_child(_fade)


static func place(id: String) -> Dictionary:
	for pl in Land.PLACES:
		if pl.id == id:
			return pl
	return {}


func _near_place(id: String, p: Vector2, extra: float) -> bool:
	var pl := place(id)
	return not pl.is_empty() and p.distance_to(pl.pos) < float(pl.r) + extra


func is_discovered(id: String) -> bool:
	return id == "hearth" or (Run.data.visited as Array).has(id)


func _mark(id: String) -> void:
	if not (Run.data.visited as Array).has(id):
		(Run.data.visited as Array).append(id)


# Old saves have no record of visits: work out what we can from what they do hold.
func _infer() -> void:
	var here := Vector2(float(Run.data.ow_x), float(Run.data.ow_z))
	for id in DESTS:
		if _near_place(id, here, 10.0):
			_mark(id)
	var q: Dictionary = Run.data.quests
	if q.has("line"):
		_mark("camp_fire")
	if q.has("mire") and (Quests.state("mire").get("done", false) or int(Quests.state("mire").get("step", 0)) >= 2):
		_mark("shrine")
	if q.has("oath"):
		var st := Quests.state("oath")
		var done: bool = st.get("done", false)
		if done or int(st.get("step", 0)) >= 1:
			_mark("tower")
		if done or int(st.get("step", 0)) >= 2:
			_mark("altar")
	if int(Run.data.unlocked) > 1 or int(Run.data.best_floor) > 1 or Run.data.in_tower:
		_mark("tower")


func _process(delta: float) -> void:
	if ow.hero == null:
		return
	if not _inferred:
		_inferred = true
		_infer()
	_scan -= delta
	if _scan <= 0.0 and ow.duel == null:
		_scan = 0.4
		var p := Vector2(ow.hero_pos.x, ow.hero_pos.z)
		for id in DESTS:
			if not is_discovered(id) and _near_place(id, p, 10.0):
				_mark(id)
				if ow._bot == "" and Land.biome(place(id).pos.x, place(id).pos.y) != "ashlands":
					Run.captions.append("%s found. You can travel back here from the map." % place(id).label)
	if _phase == 0:
		return
	_t += delta
	if _phase == 1:
		_fade.color.a = clampf(_t / FADE_OUT, 0.0, 1.0)
		if _t >= FADE_OUT:
			_jump()
			_phase = 2
			_t = 0.0
	else:
		_fade.color.a = 1.0 - clampf(_t / FADE_IN, 0.0, 1.0)
		if _t >= FADE_IN:
			_phase = 0
			_fade.visible = false
			ow._leaving = false


# Why travel is not possible right now, or "" if it is.
func refusal() -> String:
	if ow.duel != null:
		return "No travelling during a duel."
	if ow.duels._pvp_pending != "":
		return "No travelling with a challenge pending."
	if ow.in_zone() or Land.biome(ow.hero_pos.x, ow.hero_pos.z) == "ashlands":
		return "No travelling out of the Ashlands. Anyone may attack here."
	if not ow._gather.is_empty() or ow.gather_progress >= 0.0:
		return "Finish gathering before you travel."
	if ow._leaving or _phase != 0:
		return "Already on the move."
	for e in ow.ents:
		if e.type == "foe" and Vector2(e.pos.x - ow.hero_pos.x, e.pos.z - ow.hero_pos.z).length() < FOE_RANGE:
			return "A foe is too close to travel."
	return ""


# Standing spot just beside a place, not in the Ashlands: {"pos": Vector3, "yaw": float}, or {} if none.
# Obstacle tests only see loaded chunks, so the land around the place must be built first.
func _arrival(id: String, origin: Vector3) -> Dictionary:
	var pl := place(id)
	if pl.is_empty():
		return {}
	var c: Vector2 = pl.pos
	var from := Vector2(origin.x, origin.z) - c
	var base := atan2(from.y, from.x) if from.length() > 1.0 else PI * 0.5
	var r := float(pl.r)
	# The fisher's fire stands in the lake (Land.height is below the water line there), so the
	# search reaches out to the nearest dry shore.
	for rad in [r + 1.8, r + 3.2, r + 5.0, r + 8.0, r + 11.0, r + 14.0, r + 18.0]:
		for i in 16:
			var off := ceili(i / 2.0) * (TAU / 16.0) * (1.0 if i % 2 == 0 else -1.0)
			var a: float = base + off
			var q: Vector2 = c + Vector2(cos(a), sin(a)) * float(rad)
			if not _walkable(q, id):
				continue
			var p := Vector3(q.x, Land.walk_height(q.x, q.y), q.y)
			var to := Vector3(c.x - q.x, 0, c.y - q.y)
			return {"pos": p, "yaw": atan2(-to.x, -to.z)}
	return {}


func _walkable(q: Vector2, id: String) -> bool:
	if not Land.in_bounds(q.x, q.y) or Land.is_water(q.x, q.y) or Land.biome(q.x, q.y) == "ashlands":
		return false
	for pl in Land.PLACES:
		if pl.id != id and q.distance_to(pl.pos) < float(pl.r) + 0.8:
			return false
	return not ow.terrain._blocked(Vector3(q.x, 0, q.y))


# Markers for the map: discovered destinations, and whether travel to each works right now.
# The tower gate lies inside the Ashlands, so it is never offered.
func markers() -> Array:
	var out: Array = []
	var why := refusal()
	var here := Vector2(ow.hero_pos.x, ow.hero_pos.z)
	for id in DESTS:
		if not is_discovered(id):
			continue
		var pl := place(id)
		if Land.biome(pl.pos.x, pl.pos.y) == "ashlands":
			continue
		out.append({"id": id, "label": pl.label, "pos": pl.pos, "ok": why == "" and here.distance_to(pl.pos) > float(pl.r) + 4.0})
	return out


# Called by the map on a tap on a marker. Returns "" if the trip began, else the reason it did not.
func request(id: String) -> String:
	if not is_discovered(id) or not DESTS.has(id):
		return "You have not been there yet."
	var why := refusal()
	if why != "":
		return why
	var pl := place(id)
	if Land.biome(pl.pos.x, pl.pos.y) == "ashlands":
		return "No travelling into the Ashlands."
	if Vector2(ow.hero_pos.x, ow.hero_pos.z).distance_to(pl.pos) <= float(pl.r) + 4.0:
		return "You are already here."
	_target = id
	_phase = 1
	_t = 0.0
	_fade.color.a = 0.0
	_fade.visible = true
	ow._leaving = true
	ow.stick = Vector2.ZERO
	ow.hero.set_walk(0.0)
	return ""


func _jump() -> void:
	var pl := place(_target)
	var old := ow.hero_pos
	# Build the land around the place first so the obstacle tests and the ground are real.
	ow.hero_pos = Vector3(pl.pos.x, 0, pl.pos.y)
	ow.terrain._update_chunks(true)
	var arr := _arrival(_target, old)
	if arr.is_empty():
		ow.hero_pos = old
		ow.terrain._update_chunks(true)
		Run.captions.append("The way is blocked. You stay where you are.")
		return
	ow.hero_pos = arr.pos
	ow.hero_yaw = arr.yaw
	ow.cam_yaw = arr.yaw
	ow.look_cool = 0.0
	ow._gather = {}
	ow.near = {}
	ow._last_safe = ow.hero_pos
	ow._stuck = 0.0
	ow.hero.position = ow.hero_pos
	ow.hero.rotation.y = ow.hero_yaw
	Run.data.ow_x = ow.hero_pos.x
	Run.data.ow_z = ow.hero_pos.z
	Run.save()
	ow.cam.position = ow.hero_pos + Vector3(sin(ow.cam_yaw), 0, cos(ow.cam_yaw)) * 6.6 + Vector3(0, 3.3, 0)
	ow.mover.reset_motion()
	ow.mover._update_camera(1.0)
